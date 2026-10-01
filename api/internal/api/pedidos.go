// Los pedidos: el catálogo, los disponibles para armar ruta, las facetas y el repaso de
// pesos.
//
// DOS COSAS QUE SE ESCAPAN SIEMPRE Y QUE AQUÍ VAN A PROPÓSITO:
//
//  1. `/api/orders/available` aplica `kmMax` y `costoMin` DESPUÉS de la consulta, y
//     `total`/`truncated` se calculan ANTES que ellos. Bajarlos al SQL cambiaría esos dos
//     números: la pantalla diría «358» sobre una tabla de 120. Eso ya pasó.
//  2. Los renglones YA NO SON UN JSON. Donde delivery miraba `productosTexto` —una copia
//     a mano de los nombres, porque dentro de un JSON no se busca— ahora se consulta
//     `order_items`. Eso vive en el SQL (`db/queries/orders.sql`); aquí sólo se pasa `q`.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// avisarCambioDePedidos publica «algo cambió en los pedidos» para que las pantallas
// abiertas se enteren sin esperar al temporizador.
//
// Vacío por defecto y lo engancha el fichero del bus (`eventos.go`), igual que el de rutas
// y el del tablero. **No devuelve error y no se mira lo que conteste**: un pedido no se
// deja de guardar porque el aviso no salga.
//
// ## HASTA HOY AVISABA UN SOLO SITIO, y era el equivocado para esto — 17/09/2026
//
// El único `CambioPedidos` del servicio salía del lote del espejo (`cotizacion.go`,
// `cotizarLote`). O sea: los pedidos que entran solos avisaban, y los que toca una persona
// —cambiar el estado, asignar ruta, borrar uno— no los avisaba nadie. Justo al revés de lo
// que hace falta, porque lo que toca una persona es lo que otra está mirando en ese mismo
// momento.
//
// ## LA SUCURSAL SE LA PASA EL MANEJADOR, LEÍDA DE `orders.branch_id` — 01/10/2026
//
// Antes la sacaba el bus del alcance, y para quien ve las ocho eso es «de todas». El porqué
// entero, en `eventos.go` encima del `init()`. Las dos puertas de persona —el `PATCH` y el
// `DELETE`— tienen la fila delante; la faena del repaso de pesos NO, y ésa sigue saliendo del
// alcance con su motivo escrito en el sitio.
var avisarCambioDePedidos = func(_ context.Context, _ string) {}

// Los topes del contrato, con nombre para que se vean en un sitio y no repartidos por los
// manejadores.
const (
	// El `min(200, max(1, Number(porPagina)||50))` del contrato. La página, por su lado,
	// es `max(1, …)`: no hay página cero.
	PorPaginaPorDefecto = 50
	PorPaginaTope       = 200

	// TopeResumen: por encima de esto el pre-despacho NO se calcula y `resumen` sale
	// `null`. Calcularlo obligaría a releer los pedidos filtrados ENTEROS, y con el
	// histórico de las ocho sucursales eso es la petición que tumba el proceso.
	TopeResumen = 5000

	// TopeDisponibles: el `take = 2000` del contrato. Lo que pase de ahí sale marcado con
	// `truncated`, que es lo que le dice al armador que está mirando un recorte.
	TopeDisponibles = 2000
)

// rutasPedidos monta las rutas de este fichero. La llama `Rutas()` en servidor.go.
//
// `admin` no lo usa ninguna: en pedidos NO hay ruta de administración. El catálogo lo
// mira y lo corrige quien reparte, y el único escalón distinto es el repaso de pesos, que
// no va por rol sino por CLAVE DE SERVICIO —ver `mediosDeServicio`—. Se recibe igual para
// que la firma sea la misma que la de los demás recursos y no haya que pensarlo dos veces
// al montar el siguiente.
func (s *Servidor) rutasPedidos(rt *httpx.Router, sesion, admin []httpx.Medio) {
	_ = admin

	rt.ManejarFunc(http.MethodGet, "/api/orders", s.listarPedidos, sesion...)

	// `/available`, `/facetas` y `/recompute-weights` son literales y ganan al comodín
	// `{id}`: ServeMux prefiere siempre el patrón más específico. No hace falta ningún
	// orden de registro ni ninguna comprobación dentro del manejador de `{id}`.
	rt.ManejarFunc(http.MethodGet, "/api/orders/available", s.pedidosDisponibles, sesion...)
	rt.ManejarFunc(http.MethodGet, "/api/orders/facetas", s.facetasDePedidos, sesion...)

	rt.ManejarFunc(http.MethodGet, "/api/orders/{id}", s.obtenerPedido, sesion...)
	rt.ManejarFunc(http.MethodPatch, "/api/orders/{id}", s.actualizarPedido, sesion...)
	rt.ManejarFunc(http.MethodDelete, "/api/orders/{id}", s.borrarPedido, sesion...)

	rt.ManejarFunc(http.MethodPost, "/api/orders/recompute-weights", s.recalcularPesos, s.mediosDeServicio()...)

	// POST /api/orders NO SE REGISTRA, y no es un olvido: el alta manual se retiró el
	// 03/09/2026 y el contrato dice que responde 405. Al no registrarlo, el 405 lo da el
	// router con `Allow: GET, OPTIONS`, que es la verdad. Registrarlo con un manejador
	// que devolviera 405 pondría POST en esa cabecera y anunciaría un alta que no existe.
}

// mediosDeServicio es la puerta del repaso de pesos: clave de API, sin persona y sin
// alcance.
//
// Las consultas sólo se alcanzan por `alcance.Acotado`, y el alcance exige una persona.
// Así que se le cuelga una de servicio y se BORRA la cabecera `X-Sucursal-Id` antes de
// resolverlo: si no, quien llamara con esa cabecera puesta acotaría una faena que tiene
// que ir sobre el espejo entero, y siete sucursales se quedarían con el peso viejo sin una
// sola traza.
//
// LA PERSONA DE SERVICIO LLEVA SU ROL ESCRITO, y eso es nuevo. Antes se apoyaba en «sin
// sucursal = todas», que era justo el hueco por el que cualquiera a quien le faltara la
// suya veía las ocho. Al taparlo (16/09/2026), quedarse sin rol dejaba esta faena en un
// 403. Se dice lo que es: quien entra con la llave de servicio no es una persona a la que
// le falte la sucursal, es el propio sistema. El espejo ya lo hacía así.
func (s *Servidor) mediosDeServicio() []httpx.Medio {
	return []httpx.Medio{
		auth.LlaveDeServicio(s.cfg.ServiceAPIKey),
		func(siguiente http.Handler) http.Handler {
			return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				u := &auth.Usuario{ID: "servicio", Nombre: "servicio", Rol: "SUPER ADMIN"}
				r2 := r.Clone(auth.ConUsuario(r.Context(), u))
				r2.Header.Del(alcance.CabeceraSucursal)
				siguiente.ServeHTTP(w, r2)
			})
		},
		s.porteria.Exigir,
	}
}

// ---------------------------------------------------------------------------
// La forma con la que sale un pedido
// ---------------------------------------------------------------------------

// RenglonSalida es una línea del pedido. Antes iba dentro del JSON `items`; ahora sale de
// `order_items`, que es su tabla.
//
// `name` es el MISMO valor que `description`, no otro dato: las pantallas viejas leen
// `item.name || item.description` y se quedarían en blanco. Sale de la misma columna en
// la misma respuesta, así que no hay dos sitios que puedan discrepar — que es lo que sí
// pasaba con `productosTexto`.
type RenglonSalida struct {
	ID          uuid.UUID  `json:"id"`
	Linea       int32      `json:"linea"`
	Description string     `json:"description"`
	Name        string     `json:"name"`
	Quantity    float64    `json:"quantity"`
	Packs       *float64   `json:"packs"`
	ProductID   *uuid.UUID `json:"productId"`
	// La marca del RENGLÓN, que no es la del pedido: PEDIDO reescribe las líneas con lo
	// que dijo la factura sin tocar el pedido. Es lo que deja saber si la mercancía que se
	// está mirando es la de ahora o la del papel de ayer.
	UpdatedAt *time.Time `json:"updatedAt"`

	// EL PESO DEL RENGLÓN, tal como quedó cuando el pedido entró. Los dos, y con nombres
	// distintos a propósito: `pesoKg` es lo que pesa UN empaque y `pesoLineaKg` la línea
	// entera. Mandar sólo el primero llamándolo «el peso» es pedir que alguien se acuerde
	// de multiplicar por los empaques, y el día que se olvide el camión sale dividido
	// entre treinta sin que falle nada.
	//
	// HASTA EL 26/09/2026 NO VIAJABAN, y la aplicación los recalculaba contra su catálogo
	// local. Lo que se veía: la ficha decía «sin peso» en un renglón mientras el total del
	// pedido decía 72,6 kg —la pantalla contradiciéndose a sí misma—, y el pre-despacho,
	// que es la hoja con la que se carga el camión, salía con las catorce filas en raya y
	// «sin peso en el catálogo» encima de 7.446 empaques. Inservible.
	//
	// El dato estaba en la base desde la 00004, que se escribió justamente «para no tener
	// que recalcular el peso con el catálogo de hoy»: un producto que hoy no está en el
	// catálogo de esa sucursal no tiene por qué perder el peso con el que se facturó ayer.
	// Se perdía en el último salto.
	//
	// `null` en los dos = **no se sabe**, y la pantalla lo dice con esas palabras. No es
	// cero: un cero se suma, se ordena y se lee como «no pesa nada».
	PesoKg      *float64 `json:"pesoKg"`
	PesoLineaKg *float64 `json:"pesoLineaKg"`
}

// RutaDePedido y VehiculoDeRuta: el `route: { …, vehicle: {…} }` del contrato.
type RutaDePedido struct {
	ID           *uuid.UUID      `json:"id"`
	Name         *string         `json:"name"`
	RouteCode    *string         `json:"routeCode,omitempty"`
	Status       *string         `json:"status,omitempty"`
	DeliveryDate *time.Time      `json:"deliveryDate,omitempty"`
	Vehicle      *VehiculoDeRuta `json:"vehicle,omitempty"`
}

type VehiculoDeRuta struct {
	Name  *string `json:"name"`
	Plate *string `json:"plate"`
}

// SucursalDePedido es el `branch: { id, name, lat, lng }`. Va con las coordenadas porque
// la pantalla dibuja el pedido y su sucursal en el mismo mapa.
type SucursalDePedido struct {
	ID   *uuid.UUID `json:"id"`
	Name *string    `json:"name"`
	Lat  *float64   `json:"lat"`
	Lng  *float64   `json:"lng"`
}

// PedidoSalida es una fila del catálogo (`GET /api/orders`).
type PedidoSalida struct {
	ID                 uuid.UUID       `json:"id"`
	OperationNumber    *string         `json:"operationNumber"`
	CustomerName       string          `json:"customerName"`
	CustomerPhone      *string         `json:"customerPhone"`
	Address            string          `json:"address"`
	EndAddress         *string         `json:"endAddress"`
	EndLat             *float64        `json:"endLat"`
	EndLng             *float64        `json:"endLng"`
	Weight             float64         `json:"weight"`
	Status             string          `json:"status"`
	Notes              *string         `json:"notes"`
	RouteID            *uuid.UUID      `json:"routeId"`
	DeliveryPrice      *float64        `json:"deliveryPrice"`
	DeliveryDistanceKm *float64        `json:"deliveryDistanceKm"`
	Price              *float64        `json:"price"`
	Items              []RenglonSalida `json:"items"`
	OrderDate          *time.Time      `json:"orderDate"`
	CreatedAt          *time.Time      `json:"createdAt"`
	DeliveredAt        *time.Time      `json:"deliveredAt"`
	Resultado          *string         `json:"resultado"`
	ResultadoNota      *string         `json:"resultadoNota"`
	StopOrder          *int32          `json:"stopOrder"`
	Estado             *string         `json:"estado"`
	Archivado          bool            `json:"archivado"`
	FechaComprometida  *time.Time      `json:"fechaComprometida"`
	RequiereDomicilio  *bool           `json:"requiereDomicilio"`
	PedidoCosto        *float64        `json:"pedidoCosto"`
	FacturaEstado      *string         `json:"facturaEstado"`
	FacturaNumero      *string         `json:"facturaNumero"`
	FacturaDomicilio   *float64        `json:"facturaDomicilio"`
	Municipio          *string         `json:"municipio"`
	Vendedor           *string         `json:"vendedor"`
	SucursalCodigo     *string         `json:"sucursalCodigo"`
	// ¿ESE `weight` SALE DE ALGO? Campo NUEVO, no un tipo cambiado: `weight` sigue siendo
	// un número y una APK instalada lo lee igual que ayer.
	//
	// `weight` no sabe decir «no se sabe» —la columna es `NOT NULL`, un peso sin resolver
	// entra como 0 y lo anterior al traspaso como **1**, que es perfectamente creíble para
	// un paquete— y de ahí se suma en la tarjeta «Peso Total», en el Excel que alguien abre
	// para cobrar y en la barra de capacidad del camión, que decide qué cabe. Así que la
	// duda viaja al lado del número, que es lo único que no rompe a nadie.
	//
	// Tres estados, y el tercero NO es «está bien»:
	//   false — hay constancia y nada respalda ese peso: el número es inventado.
	//   true  — algún renglón trae peso propio.
	//   null  — no consta. Hoy es la inmensa mayoría: el espejo no escribe todavía
	//           `origen_peso` (ver `CrearRenglonDePedido` en db/queries/orders.sql).
	PesoRespaldado *bool `json:"pesoRespaldado"`
	// Cuándo se tocó la fila. La bajada del aparato la necesita para pedir por
	// diferencias; la pantalla, para saber si lo que enseña es de hace un minuto o de hace
	// tres días.
	UpdatedAt *time.Time        `json:"updatedAt"`
	Route     *RutaDePedido     `json:"route"`
	Branch    *SucursalDePedido `json:"branch"`
}

// PedidoDisponibleSalida es una fila de `GET /api/orders/available`. Lleva MENOS campos
// que el catálogo, y son los del contrato: el armador de rutas pinta una tabla de hasta
// dos mil filas y cada campo de más son dos mil campos de más por el cable.
type PedidoDisponibleSalida struct {
	ID                 uuid.UUID       `json:"id"`
	OrderDate          *time.Time      `json:"orderDate"`
	CreatedAt          *time.Time      `json:"createdAt"`
	OperationNumber    *string         `json:"operationNumber"`
	CustomerName       string          `json:"customerName"`
	Address            string          `json:"address"`
	EndAddress         *string         `json:"endAddress"`
	EndLat             *float64        `json:"endLat"`
	EndLng             *float64        `json:"endLng"`
	Weight             float64         `json:"weight"`
	DeliveryPrice      *float64        `json:"deliveryPrice"`
	DeliveryDistanceKm *float64        `json:"deliveryDistanceKm"`
	Items              []RenglonSalida `json:"items"`
	Estado             *string         `json:"estado"`
	Archivado          bool            `json:"archivado"`
	RequiereDomicilio  *bool           `json:"requiereDomicilio"`
	PedidoCosto        *float64        `json:"pedidoCosto"`
	Municipio          *string         `json:"municipio"`
	Vendedor           *string         `json:"vendedor"`
	// ¿Ese `weight` sale de algo? false = inventado, true = algún renglón lo respalda,
	// null = no consta (que no es «está bien»). Ver `PedidoSalida.PesoRespaldado`.
	PesoRespaldado *bool `json:"pesoRespaldado"`
}

// PedidoDetalleSalida es `GET /api/orders/{id}` y la respuesta del PATCH: el pedido
// entero. Aquí sí van todos los campos, porque es UNA fila y la pantalla de detalle los
// enseña.
type PedidoDetalleSalida struct {
	ID                 uuid.UUID  `json:"id"`
	OperationNumber    *string    `json:"operationNumber"`
	CustomerName       string     `json:"customerName"`
	CustomerPhone      *string    `json:"customerPhone"`
	Address            string     `json:"address"`
	EndAddress         *string    `json:"endAddress"`
	EndLat             *float64   `json:"endLat"`
	EndLng             *float64   `json:"endLng"`
	Lat                *float64   `json:"lat"`
	Lng                *float64   `json:"lng"`
	Weight             float64    `json:"weight"`
	Status             string     `json:"status"`
	TripLeg            string     `json:"tripLeg"`
	Notes              *string    `json:"notes"`
	RouteID            *uuid.UUID `json:"routeId"`
	UltimaRutaID       *uuid.UUID `json:"ultimaRutaId"`
	VehicleID          *uuid.UUID `json:"vehicleId"`
	Price              *float64   `json:"price"`
	SegmentKm          *float64   `json:"segmentKm"`
	DeliveryPrice      *float64   `json:"deliveryPrice"`
	DeliveryDistanceKm *float64   `json:"deliveryDistanceKm"`
	BranchID           *uuid.UUID `json:"branchId"`
	Source             *string    `json:"source"`
	ExternalID         *string    `json:"externalId"`
	OrderDate          *time.Time `json:"orderDate"`
	PedidoUpdatedAt    *time.Time `json:"pedidoUpdatedAt"`
	Estado             *string    `json:"estado"`
	Archivado          bool       `json:"archivado"`
	FechaComprometida  *time.Time `json:"fechaComprometida"`
	RequiereDomicilio  *bool      `json:"requiereDomicilio"`
	PedidoCosto        *float64   `json:"pedidoCosto"`
	Municipio          *string    `json:"municipio"`
	Vendedor           *string    `json:"vendedor"`
	SucursalCodigo     *string    `json:"sucursalCodigo"`
	FacturaEstado      *string    `json:"facturaEstado"`
	FacturaNumero      *string    `json:"facturaNumero"`
	FacturaAt          *time.Time `json:"facturaAt"`
	FacturaDomicilio   *float64   `json:"facturaDomicilio"`
	FacturaCorregidoAt *time.Time `json:"facturaCorregidoAt"`
	// DE DÓNDE SON `items`, `weight` y las unidades: `factura` o `pedido`.
	//
	// Cuando la factura cambió lo que se pidió, lo que llega aquí YA son las líneas de la
	// factura — es lo que sube al camión—. Sin este campo la pantalla enseña un número y
	// no puede decir cuál de los dos es, que es justo lo que hay que saber para no cargar
	// de más. Ver `00009_de_donde_son_los_renglones.sql`.
	ItemsOrigen   *string           `json:"itemsOrigen"`
	StopOrder     *int32            `json:"stopOrder"`
	DeliveredAt   *time.Time        `json:"deliveredAt"`
	Resultado     *string           `json:"resultado"`
	ResultadoAt   *time.Time        `json:"resultadoAt"`
	ResultadoNota *string           `json:"resultadoNota"`
	CreatedAt     *time.Time        `json:"createdAt"`
	UpdatedAt     *time.Time        `json:"updatedAt"`
	Items         []RenglonSalida   `json:"items"`
	Route         *RutaDePedido     `json:"route"`
	Vehicle       *VehiculoDePedido `json:"vehicle"`
	// ¿Ese `weight` sale de algo? false = inventado, true = algún renglón lo respalda,
	// null = no consta (que no es «está bien»). Ver `PedidoSalida.PesoRespaldado`.
	PesoRespaldado *bool `json:"pesoRespaldado"`
}

// VehiculoDePedido es el `vehicle: {id, name, type, plate}` del detalle. `type` es el
// NOMBRE del tipo (el del catálogo `vehicle_types`), que es lo que la pantalla enseña.
type VehiculoDePedido struct {
	ID    *uuid.UUID `json:"id"`
	Name  *string    `json:"name"`
	Type  *string    `json:"type"`
	Plate *string    `json:"plate"`
}

// LineaResumen es una línea del pre-despacho: qué hay que sacar del almacén.
type LineaResumen struct {
	Producto string  `json:"producto"`
	Formatos int64   `json:"formatos"`
	Unidades int64   `json:"unidades"`
	PesoKg   float64 `json:"pesoKg"`
}

// CatalogoSalida es la respuesta entera de `GET /api/orders`.
//
// `Resumen` es un PUNTERO a rodaja para poder decir las tres cosas del contrato con un
// solo campo: nil -> no se pidió y se omite del JSON; puntero a rodaja nil -> se pidió
// pero se pasó del tope, y sale `null`; puntero a rodaja -> el array. Con una rodaja
// pelada no hay forma de separar «no lo pedí» de «no se pudo».
type CatalogoSalida struct {
	Orders      []PedidoSalida  `json:"orders"`
	Total       int64           `json:"total"`
	Pagina      int             `json:"pagina"`
	PorPagina   int             `json:"porPagina"`
	Paginas     int             `json:"paginas"`
	Resumen     *[]LineaResumen `json:"resumen,omitempty"`
	ResumenTope int             `json:"resumenTope"`
	PesoTotal   float64         `json:"pesoTotal"`
}

// DisponiblesSalida es la respuesta de `GET /api/orders/available`.
type DisponiblesSalida struct {
	Orders    []PedidoDisponibleSalida `json:"orders"`
	Total     int64                    `json:"total"`
	Truncated bool                     `json:"truncated"`
}

// FacetasSalida llena los desplegables del catálogo.
type FacetasSalida struct {
	Municipios []FacetaValor    `json:"municipios"`
	Vendedores []FacetaValor    `json:"vendedores"`
	Sucursales []FacetaSucursal `json:"sucursales"`
}

type FacetaValor struct {
	Valor   string `json:"valor"`
	Pedidos int64  `json:"pedidos"`
}

type FacetaSucursal struct {
	Valor   uuid.UUID `json:"valor"`
	Nombre  string    `json:"nombre"`
	Pedidos int64     `json:"pedidos"`
}

// ---------------------------------------------------------------------------
// GET /api/orders
// ---------------------------------------------------------------------------

func (s *Servidor) listarPedidos(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	f := leerFiltros(r)

	pagina := enteroConTope(r.URL.Query().Get("pagina"), 1, 1, 0)
	porPagina := enteroConTope(r.URL.Query().Get("porPagina"), PorPaginaPorDefecto, 1, PorPaginaTope)

	// El conteo va ANTES de la página: con él se sabe si el pre-despacho cabe bajo el
	// tope, y sin él `paginas` no se puede calcular.
	total, err := a.ContarPedidos(r.Context(), sqlc.ContarPedidosParams{
		BranchID: f.BranchID, Q: f.Q, Estado: f.Estado, Archivado: f.Archivado,
		Domicilio: f.Domicilio, Cotizado: f.Cotizado, Municipio: f.Municipio,
		Vendedor: f.Vendedor, Reparto: f.Reparto, Factura: f.Factura,
		Desde: f.Desde, Hasta: f.Hasta,
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	filas, err := a.ListarPedidos(r.Context(), sqlc.ListarPedidosParams{
		BranchID: f.BranchID, Q: f.Q, Estado: f.Estado, Archivado: f.Archivado,
		Domicilio: f.Domicilio, Cotizado: f.Cotizado, Municipio: f.Municipio,
		Vendedor: f.Vendedor, Reparto: f.Reparto, Factura: f.Factura,
		Desde: f.Desde, Hasta: f.Hasta,
		Desplazamiento: int32((pagina - 1) * porPagina),
		Limite:         int32(porPagina),
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	// Los renglones de TODA la página en UNA consulta. Una por fila serían doscientas
	// idas y vueltas para pintar una pantalla.
	ids := make([]uuid.UUID, 0, len(filas))
	for _, x := range filas {
		ids = append(ids, x.ID)
	}
	renglones, err := s.renglonesPorPedido(r, a, ids)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	salida := CatalogoSalida{
		Orders:      make([]PedidoSalida, 0, len(filas)),
		Total:       total,
		Pagina:      pagina,
		PorPagina:   porPagina,
		Paginas:     paginas(total, porPagina),
		ResumenTope: TopeResumen,
	}
	for _, x := range filas {
		salida.Orders = append(salida.Orders, dePedido(x, renglones[x.ID]))
	}

	// El pre-despacho: sólo si lo piden y sólo si cabe.
	if r.URL.Query().Get("resumen") == "1" {
		lineas, peso, err := s.preDespacho(r, a, f, total)
		if err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
		salida.Resumen = &lineas // lineas nil -> sale `null`: se pidió y no cupo
		salida.PesoTotal = peso
	}

	httpx.JSON(w, r, http.StatusOK, salida)
}

// preDespacho calcula qué mercancía hay que sacar del almacén para lo que se está
// filtrando, y cuánto pesa.
//
// Releer TODOS los pedidos filtrados es caro, y por eso está el tope: pasado `TopeResumen`
// se devuelve nil (que el llamante convierte en `null`) en vez de arrastrar el histórico
// entero de las ocho sucursales por una casilla marcada sin pensar.
//
// El peso total sale de los pedidos releídos y no de la página: es el peso de LO
// FILTRADO, que es lo que se va a cargar, no el de las cincuenta filas que se están
// viendo.
func (s *Servidor) preDespacho(r *http.Request, a *alcance.Acotado, f filtrosPedido, total int64) ([]LineaResumen, float64, error) {
	if total > TopeResumen {
		return nil, 0, nil
	}
	todos, err := a.ListarPedidos(r.Context(), sqlc.ListarPedidosParams{
		BranchID: f.BranchID, Q: f.Q, Estado: f.Estado, Archivado: f.Archivado,
		Domicilio: f.Domicilio, Cotizado: f.Cotizado, Municipio: f.Municipio,
		Vendedor: f.Vendedor, Reparto: f.Reparto, Factura: f.Factura,
		Desde: f.Desde, Hasta: f.Hasta,
		Desplazamiento: 0,
		Limite:         int32(total),
	})
	if err != nil {
		return nil, 0, err
	}

	ids := make([]uuid.UUID, 0, len(todos))
	var peso float64
	for _, x := range todos {
		ids = append(ids, x.ID)
		peso += x.Weight
	}
	// Rodaja VACÍA, no nil: «se pidió, se calculó y no hay nada» sale `[]`, que es
	// distinto de `null` («no se pudo calcular»).
	lineas := make([]LineaResumen, 0)
	if len(ids) == 0 {
		return lineas, peso, nil
	}
	filas, err := a.ResumenPreDespacho(r.Context(), ids)
	if err != nil {
		return nil, 0, err
	}
	for _, x := range filas {
		lineas = append(lineas, LineaResumen{
			Producto: x.Producto,
			Formatos: x.Formatos,
			Unidades: x.Unidades,
			PesoKg:   decimalDelResumen(x.PesoKg),
		})
	}
	return lineas, peso, nil
}

// ---------------------------------------------------------------------------
// GET /api/orders/available
// ---------------------------------------------------------------------------

func (s *Servidor) pedidosDisponibles(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()
	f := leerFiltros(r)
	diaDesde, diaHasta := diaNatural(strings.TrimSpace(q.Get("fecha")))

	// EL ORDEN IMPORTA Y ES EL DEL CONTRATO: primero el conteo y la lista con el WHERE
	// del SQL, y sólo DESPUÉS `kmMax` y `costoMin`. `total` y `truncated` salen de este
	// punto, antes de los dos filtros de memoria. Al revés, el contador diría «358»
	// sobre una tabla de 120 y nadie sabría cuál de los dos creerse.
	total, err := a.ContarPedidosDisponibles(r.Context(), sqlc.ContarPedidosDisponiblesParams{
		BranchID: f.BranchID, Q: f.Q, Estado: f.Estado, Archivado: f.Archivado,
		Domicilio: f.Domicilio, Cotizado: f.Cotizado, Municipio: f.Municipio,
		Vendedor: f.Vendedor, Reparto: f.Reparto, Factura: f.Factura,
		Desde: f.Desde, Hasta: f.Hasta, DiaDesde: diaDesde, DiaHasta: diaHasta,
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	filas, err := a.ListarPedidosDisponibles(r.Context(), sqlc.ListarPedidosDisponiblesParams{
		BranchID: f.BranchID, Q: f.Q, Estado: f.Estado, Archivado: f.Archivado,
		Domicilio: f.Domicilio, Cotizado: f.Cotizado, Municipio: f.Municipio,
		Vendedor: f.Vendedor, Reparto: f.Reparto, Factura: f.Factura,
		Desde: f.Desde, Hasta: f.Hasta, DiaDesde: diaDesde, DiaHasta: diaHasta,
		Limite: TopeDisponibles,
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	truncado := total > int64(len(filas))

	// Ahora sí, los dos filtros de memoria.
	kmMax, hayKmMax := numeroDeQuery(q.Get("kmMax"))
	costoMin, hayCostoMin := numeroDeQuery(q.Get("costoMin"))
	quedan := make([]sqlc.ListarPedidosDisponiblesRow, 0, len(filas))
	for _, x := range filas {
		if !pasaElTopeDeKm(x.DeliveryDistanceKm, kmMax, hayKmMax) {
			continue
		}
		// Aquí el ausente SÍ cuenta como cero, y es lo pedido: `costoMin` es «enséñame
		// lo que valga la pena mover», y un pedido sin cotizar no lo vale todavía.
		if hayCostoMin && conCero(x.PedidoCosto) < costoMin {
			continue
		}
		quedan = append(quedan, x)
	}

	ids := make([]uuid.UUID, 0, len(quedan))
	for _, x := range quedan {
		ids = append(ids, x.ID)
	}
	renglones, err := s.renglonesPorPedido(r, a, ids)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	salida := DisponiblesSalida{
		Orders:    make([]PedidoDisponibleSalida, 0, len(quedan)),
		Total:     total,
		Truncated: truncado,
	}
	for _, x := range quedan {
		salida.Orders = append(salida.Orders, PedidoDisponibleSalida{
			ID: x.ID, OrderDate: hora(x.OrderDate), CreatedAt: hora(x.CreatedAt),
			OperationNumber: x.OperationNumber, CustomerName: x.CustomerName,
			Address: x.Address, EndAddress: x.EndAddress,
			EndLat: x.EndLat, EndLng: x.EndLng, Weight: x.Weight,
			PesoRespaldado: x.PesoRespaldado,
			DeliveryPrice:  x.DeliveryPrice, DeliveryDistanceKm: x.DeliveryDistanceKm,
			Items: renglones[x.ID], Estado: textoDe(x.Estado), Archivado: x.Archivado,
			RequiereDomicilio: x.RequiereDomicilio, PedidoCosto: x.PedidoCosto,
			Municipio: x.Municipio, Vendedor: x.Vendedor,
		})
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// ---------------------------------------------------------------------------
// GET /api/orders/facetas
// ---------------------------------------------------------------------------

func (s *Servidor) facetasDePedidos(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	municipios, err := a.FacetasMunicipios(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	vendedores, err := a.FacetasVendedores(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	sucursales, err := a.FacetasSucursales(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	salida := FacetasSalida{
		Municipios: make([]FacetaValor, 0, len(municipios)),
		Vendedores: make([]FacetaValor, 0, len(vendedores)),
		Sucursales: make([]FacetaSucursal, 0, len(sucursales)),
	}
	for _, x := range municipios {
		if x.Valor == nil {
			continue
		}
		salida.Municipios = append(salida.Municipios, FacetaValor{Valor: *x.Valor, Pedidos: x.Pedidos})
	}
	for _, x := range vendedores {
		if x.Valor == nil {
			continue
		}
		salida.Vendedores = append(salida.Vendedores, FacetaValor{Valor: *x.Valor, Pedidos: x.Pedidos})
	}
	for _, x := range sucursales {
		id := idOpcional(x.Valor)
		if id == nil {
			continue
		}
		salida.Sucursales = append(salida.Sucursales, FacetaSucursal{
			Valor:   *id,
			Nombre:  nombreDeSucursal(x.SucursalNombre, x.SucursalCodigo),
			Pedidos: x.Pedidos,
		})
	}
	// Se ordena por el nombre COMPUESTO, que es lo que se lee en el desplegable, y no por
	// el de la tabla: con «Nombre (COD)» y «Sin sucursal» mezclados, el orden del SQL
	// dejaría «Sin sucursal» donde cayera. Se compara en minúsculas y sin depender de
	// ninguna biblioteca de intercalación: para ocho sucursales es de sobra, y una
	// dependencia más es una versión más que alguien tendrá que subir.
	sort.SliceStable(salida.Sucursales, func(i, j int) bool {
		return strings.ToLower(salida.Sucursales[i].Nombre) < strings.ToLower(salida.Sucursales[j].Nombre)
	})
	httpx.JSON(w, r, http.StatusOK, salida)
}

// nombreDeSucursal compone lo que la gente reconoce: «Santiago (STG)». El código a secas
// no dice nada y el nombre solo se repite entre sucursales parecidas.
func nombreDeSucursal(nombre, codigo *string) string {
	if nombre == nil || *nombre == "" {
		// La sucursal del pedido ya no está en la tabla. Se dice, no se esconde: es
		// justo el dato que hay que arreglar.
		return "Sin sucursal"
	}
	if codigo != nil && *codigo != "" {
		return fmt.Sprintf("%s (%s)", *nombre, *codigo)
	}
	return *nombre
}

// ---------------------------------------------------------------------------
// GET /api/orders/{id}
// ---------------------------------------------------------------------------

func (s *Servidor) obtenerPedido(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	// `Not found`, en inglés, es el literal del contrato para esta ruta. No es lo mismo
	// que el `No encontrado` de sucursales y rutas: están inventariados uno por uno.
	id, ok := idDeRuta(w, r, httpx.MsgNotFound)
	if !ok {
		return
	}
	salida, ok := s.detalleDePedido(w, r, a, id)
	if !ok {
		return
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// detalleDePedido lee el pedido con sus renglones y ya ha respondido si no lo encuentra.
// Lo usan el GET y el PATCH: el cliente vuelve a pintar la misma ficha con lo que le
// devuelve cualquiera de los dos, así que la forma tiene que ser LA MISMA.
func (s *Servidor) detalleDePedido(w http.ResponseWriter, r *http.Request, a *alcance.Acotado, id uuid.UUID) (PedidoDetalleSalida, bool) {
	x, err := a.ObtenerPedido(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return PedidoDetalleSalida{}, false
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return PedidoDetalleSalida{}, false
	}
	renglones, err := a.ListarRenglonesDePedido(r.Context(), id)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return PedidoDetalleSalida{}, false
	}
	items := make([]RenglonSalida, 0, len(renglones))
	for _, g := range renglones {
		items = append(items, RenglonSalida{
			ID: g.ID, Linea: g.Linea, Description: g.Description, Name: g.Description,
			Quantity: g.Quantity, Packs: g.Packs, ProductID: idOpcional(g.ProductID),
			UpdatedAt: hora(g.UpdatedAt),
			PesoKg:    g.PesoUnitarioKg, PesoLineaKg: g.PesoLineaKg,
		})
	}

	salida := PedidoDetalleSalida{
		ID: x.ID, OperationNumber: x.OperationNumber, CustomerName: x.CustomerName,
		CustomerPhone: x.CustomerPhone, Address: x.Address, EndAddress: x.EndAddress,
		EndLat: x.EndLat, EndLng: x.EndLng, Lat: x.Lat, Lng: x.Lng, Weight: x.Weight,
		PesoRespaldado: x.PesoRespaldado,
		Status:         string(x.Status), TripLeg: string(x.TripLeg), Notes: x.Notes,
		RouteID: idOpcional(x.RouteID), UltimaRutaID: idOpcional(x.UltimaRutaID),
		VehicleID: idOpcional(x.VehicleID), Price: x.Price, SegmentKm: x.SegmentKm,
		DeliveryPrice: x.DeliveryPrice, DeliveryDistanceKm: x.DeliveryDistanceKm,
		BranchID: idOpcional(x.BranchID), Source: textoDe(x.Source), ExternalID: x.ExternalID,
		OrderDate: hora(x.OrderDate), PedidoUpdatedAt: hora(x.PedidoUpdatedAt),
		Estado: textoDe(x.Estado), Archivado: x.Archivado,
		FechaComprometida: hora(x.FechaComprometida), RequiereDomicilio: x.RequiereDomicilio,
		PedidoCosto: x.PedidoCosto, Municipio: x.Municipio, Vendedor: x.Vendedor,
		SucursalCodigo: x.SucursalCodigo, FacturaEstado: textoDe(x.FacturaEstado),
		FacturaNumero: x.FacturaNumero, FacturaAt: hora(x.FacturaAt),
		FacturaDomicilio: x.FacturaDomicilio, FacturaCorregidoAt: hora(x.FacturaCorregidoAt),
		ItemsOrigen: x.ItemsOrigen,
		StopOrder:   x.StopOrder, DeliveredAt: hora(x.DeliveredAt),
		Resultado: textoDe(x.Resultado), ResultadoAt: hora(x.ResultadoAt),
		ResultadoNota: x.ResultadoNota, CreatedAt: hora(x.CreatedAt),
		UpdatedAt: hora(x.UpdatedAt), Items: items,
	}
	if id := idOpcional(x.RouteID); id != nil {
		salida.Route = &RutaDePedido{ID: id, Name: x.RutaNombre}
	}
	if id := idOpcional(x.VehicleID); id != nil {
		salida.Vehicle = &VehiculoDePedido{
			ID: id, Name: x.VehiculoNombre, Type: x.VehiculoTipo, Plate: x.VehiculoMatricula,
		}
	}
	return salida, true
}

// ---------------------------------------------------------------------------
// PATCH /api/orders/{id}
// ---------------------------------------------------------------------------

// cuerpoPedido: sólo se aplica lo que VIENE. `httpx.Opcional` es lo que separa «no me
// mandes esto» de «déjalo vacío»; sin esa distinción, un PATCH que sólo quería corregir
// la dirección borra las coordenadas y el pedido desaparece del armador de rutas.
type cuerpoPedido struct {
	OperationNumber httpx.Opcional[string]  `json:"operationNumber"`
	CustomerName    httpx.Opcional[string]  `json:"customerName"`
	Address         httpx.Opcional[string]  `json:"address"`
	EndAddress      httpx.Opcional[string]  `json:"endAddress"`
	EndLat          httpx.Opcional[float64] `json:"endLat"`
	EndLng          httpx.Opcional[float64] `json:"endLng"`
	Lat             httpx.Opcional[float64] `json:"lat"`
	Lng             httpx.Opcional[float64] `json:"lng"`
	Weight          httpx.Opcional[float64] `json:"weight"`
	Notes           httpx.Opcional[string]  `json:"notes"`
	Status          httpx.Opcional[string]  `json:"status"`
	TripLeg         httpx.Opcional[string]  `json:"tripLeg"`
	RouteID         httpx.Opcional[string]  `json:"routeId"`
	Price           httpx.Opcional[float64] `json:"price"`
	StopOrder       httpx.Opcional[int32]   `json:"stopOrder"`
}

func (s *Servidor) actualizarPedido(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNotFound)
	if !ok {
		return
	}
	var c cuerpoPedido
	if !httpx.LeerJSON(w, r, &c) {
		return
	}

	arg := sqlc.ActualizarPedidoParams{
		ID:              id,
		OperationNumber: c.OperationNumber.Puntero(),
		CustomerName:    c.CustomerName.Puntero(),
		Address:         c.Address.Puntero(),
		EndAddress:      c.EndAddress.Puntero(),
		EndLat:          c.EndLat.Puntero(),
		EndLng:          c.EndLng.Puntero(),
		Lat:             c.Lat.Puntero(),
		Lng:             c.Lng.Puntero(),
		Weight:          c.Weight.Puntero(),
		Notes:           c.Notes.Puntero(),
		Price:           c.Price.Puntero(),
		StopOrder:       c.StopOrder.Puntero(),
	}
	if c.Status.Presente && c.Status.Valor != nil {
		estado, ok := estadoDePedidoValido(w, r, *c.Status.Valor)
		if !ok {
			return
		}
		arg.Status = &estado
	}
	if c.TripLeg.Presente && c.TripLeg.Valor != nil {
		tramo, ok := tramoValido(w, r, *c.TripLeg.Valor)
		if !ok {
			return
		}
		arg.TripLeg = &tramo
	}
	// `routeId` va con interruptor y no con `coalesce`: mandarlo a null es la mitad de su
	// utilidad —es como se baja un pedido de un camión a mano cuando alguien se equivocó—
	// y con `coalesce` esa mitad no se puede expresar.
	if c.RouteID.Presente {
		arg.TocarRouteID = true
		if c.RouteID.Valor != nil && strings.TrimSpace(*c.RouteID.Valor) != "" {
			ruta, err := uuid.Parse(strings.TrimSpace(*c.RouteID.Valor))
			if err != nil {
				httpx.Error(w, r, http.StatusBadRequest,
					fmt.Sprintf("El identificador de ruta '%s' no es válido", *c.RouteID.Valor))
				return
			}
			arg.RouteID = pgDe(ruta)
		}
	}

	// SE GUARDA LA FILA, aunque la respuesta se arme releyendo: de ella sale la sucursal
	// del aviso. Era un `_` y por eso el aviso tenía que salir del alcance de quien llamó.
	tocado, err := a.ActualizarPedido(r.Context(), arg)
	// Cero filas: o no existe, o es de otra sucursal. Las dos cosas son 404; decir cuál
	// sólo le sirve a quien está probando qué ids existen.
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	// Se relee para devolver la ficha COMPLETA —con la ruta, el vehículo y los
	// renglones—, que es la misma forma que dio el GET. El UPDATE devuelve las columnas
	// de `orders` y nada más: con eso, el cliente que repinta la ficha con la respuesta
	// del PATCH perdería el nombre de la ruta y la lista de mercancía.
	salida, ok := s.detalleDePedido(w, r, a, id)
	if !ok {
		return
	}
	avisarCambioDePedidos(r.Context(), deLaFilaPg(tocado.BranchID))
	httpx.JSON(w, r, http.StatusOK, salida)
}

// estadoDePedidoValido comprueba el enum antes que Postgres. Dejarlo caer hasta la base
// da un 500 con la jerga del motor dentro; esto da un 400 que se puede leer. Mismo trato
// que el estado del vehículo, por la misma razón.
func estadoDePedidoValido(w http.ResponseWriter, r *http.Request, v string) (sqlc.OrderStatus, bool) {
	switch sqlc.OrderStatus(v) {
	case sqlc.OrderStatusPending, sqlc.OrderStatusDelivered:
		return sqlc.OrderStatus(v), true
	}
	httpx.Error(w, r, http.StatusBadRequest,
		fmt.Sprintf("Estado de pedido no válido: '%s'. Sólo 'pending' o 'delivered'", v))
	return "", false
}

func tramoValido(w http.ResponseWriter, r *http.Request, v string) (sqlc.TripLeg, bool) {
	switch sqlc.TripLeg(v) {
	case sqlc.TripLegOutbound, sqlc.TripLegReturn:
		return sqlc.TripLeg(v), true
	}
	httpx.Error(w, r, http.StatusBadRequest,
		fmt.Sprintf("Tramo no válido: '%s'. Sólo 'outbound' o 'return'", v))
	return "", false
}

// ---------------------------------------------------------------------------
// DELETE /api/orders/{id}
// ---------------------------------------------------------------------------

func (s *Servidor) borrarPedido(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNotFound)
	if !ok {
		return
	}
	// Los renglones se van solos: `order_items.order_id` es una clave ajena con
	// ON DELETE CASCADE. No hace falta transacción ni borrado previo, y por eso esto es
	// una sola consulta y no un `EnTx`.
	// DEVUELVE LA SUCURSAL DEL PEDIDO BORRADO, y no el número de filas: el aviso sale de la
	// fila y la fila ya no existe cuando se avisa. `pgx.ErrNoRows` es el «no existe o no es
	// de tu sucursal» que antes era `filas == 0`, o sea el mismo 404.
	sucursalDelBorrado, err := a.BorrarPedido(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisarCambioDePedidos(r.Context(), deLaFilaPg(sucursalDelBorrado))
	httpx.JSON(w, r, http.StatusOK, map[string]bool{"success": true})
}

// ---------------------------------------------------------------------------
// POST /api/orders/recompute-weights
// ---------------------------------------------------------------------------

type cuerpoRecalculo struct {
	Source httpx.Opcional[string] `json:"source"`
	DryRun httpx.Opcional[bool]   `json:"dryRun"`
}

// RecalculoSalida es el parte del repaso.
type RecalculoSalida struct {
	DryRun           bool              `json:"dryRun"`
	TotalOrders      int               `json:"totalOrders"`
	Updated          int               `json:"updated"`
	Unchanged        int               `json:"unchanged"`
	OrdersSinPeso    int               `json:"ordersSinPeso"`
	ProductosSinPeso []ProductoSinPeso `json:"productosSinPeso"`
}

type ProductoSinPeso struct {
	Name  string `json:"name"`
	Veces int64  `json:"veces"`
}

// recalcularPesos vuelve a poner el peso de cada pedido del espejo a partir del catálogo.
//
// EL PESO YA NO SE BUSCA EN EL WAREHOUSE DESDE AQUÍ. En delivery esta ruta bajaba el
// catálogo de Ventra y emparejaba nombres a mano, y de ahí salía su 502 «No se pudo leer
// el catálogo del warehouse (¿VPN?)». Ahora el catálogo ES una tabla nuestra
// (`products`), que la trae `/api/products/sync`, y el peso sale de `products.weight` —el
// mismo dato con el que PEDIDO cotiza—. Así que este repaso no depende de la VPN y ese
// 502 no puede ocurrir: si el catálogo está viejo, se arregla sincronizándolo, y eso se
// ve en `traido_at`.
func (s *Servidor) recalcularPesos(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	// El cuerpo es OPCIONAL: si no viene o no parsea, se trabaja con los valores de la
	// casa. Un 400 aquí dejaría la tarea de mantenimiento sin poder dispararse con un
	// POST pelado, que es como se dispara.
	var c cuerpoRecalculo
	if r.Body != nil {
		defer r.Body.Close()
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&c); err != nil {
			httpx.Registro(r).Info("cuerpo de recompute-weights ilegible: se usan los valores por defecto", "err", err)
		}
	}
	fuente, ok := fuenteValida(w, r, c.Source.Con(string(sqlc.ProcedenciaPedido)))
	if !ok {
		return
	}
	enSeco := c.DryRun.Con(false) // `=== true` estricto: sin decirlo, se escribe

	filas, err := a.PesosDelCatalogoPorFuente(r.Context(), fuente)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	salida := RecalculoSalida{
		DryRun:           enSeco,
		TotalOrders:      len(filas),
		ProductosSinPeso: make([]ProductoSinPeso, 0),
	}
	for _, x := range filas {
		// La comparación con epsilon y no con `!=`: son dobles, y sin holgura una suma
		// que da 12.299999999999999 se "actualiza" a 12.3 en cada pasada, para siempre.
		if math.Abs(x.PesoCatalogo-x.PesoGuardado) < 1e-6 {
			salida.Unchanged++
		} else {
			// `updated` cuenta TAMBIÉN en seco: lo que se pregunta con `dryRun` es
			// cuántos CAMBIARÍAN. Si no contara, el ensayo diría siempre cero y no
			// serviría para lo único para lo que existe.
			salida.Updated++
			if !enSeco {
				// Una a una y sin transacción a propósito: es mantenimiento sobre
				// decenas de miles de filas. Una transacción única tendría la tabla
				// bloqueada media hora, y si se corta a mitad no se pierde nada —lo ya
				// corregido queda corregido y basta con volver a lanzarlo—.
				if err := a.ActualizarPesoDePedido(r.Context(), sqlc.ActualizarPesoDePedidoParams{
					ID: x.ID, Weight: x.PesoCatalogo,
				}); err != nil {
					httpx.ErrorInterno(w, r, err)
					return
				}
			}
		}
		if x.PesoCatalogo == 0 {
			salida.OrdersSinPeso++
		}
	}

	// La lista de lo que el catálogo no sabe pesar. Sin ella, `ordersSinPeso` dice que
	// hay un problema pero no dice de qué producto, y no hay nada que llevarle a quien
	// mantiene el catálogo.
	sinPeso, err := a.RenglonesSinPesoPorFuente(r.Context(), fuente)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	for _, x := range sinPeso {
		salida.ProductosSinPeso = append(salida.ProductosSinPeso, ProductoSinPeso{Name: x.Nombre, Veces: x.Veces})
	}
	// SÓLO si se escribió de verdad. En seco (`dryRun`) no se ha tocado una fila, y un
	// aviso ahí manda a todas las pantallas abiertas a volver a pedir la lista para
	// encontrarla igual; sin nada actualizado tampoco hay nada nuevo que enseñar.
	if !enSeco && salida.Updated > 0 {
		// AQUÍ SÍ SALE DEL ALCANCE, Y ES EL ÚNICO DE PEDIDOS QUE LO HACE. No hay una fila
		// de la que leerlo: esto recorre TODO el espejo de una fuente y puede haber
		// corregido el peso de pedidos de las ocho sucursales en la misma pasada. La única
		// sucursal honesta es el techo de quien lo lanzó, y cuando ese techo son las ocho
		// el aviso tiene que llegarles a las ocho — que es exactamente lo que pasa.
		//
		// Acotarlo a una sola sería el fallo caro de esta casa: las otras siete pantallas se
		// quedarían con el peso viejo, sin error y sin nada en ningún registro.
		avisarCambioDePedidos(r.Context(), sucursalDelAlcance(r.Context()))
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// fuenteValida comprueba el enum `procedencia` antes de que lo haga Postgres, igual que
// con los demás enums: un valor raro daría un 500 con la jerga del motor dentro.
//
// El enum tiene UN solo valor, `pedido`: el alta manual se guarda con `source` NULL, no
// con una procedencia propia. Se comprueba igual porque el valor llega del cuerpo de la
// petición y mañana el enum puede crecer.
func fuenteValida(w http.ResponseWriter, r *http.Request, v string) (sqlc.Procedencia, bool) {
	if sqlc.Procedencia(v) == sqlc.ProcedenciaPedido {
		return sqlc.ProcedenciaPedido, true
	}
	httpx.Error(w, r, http.StatusBadRequest,
		fmt.Sprintf("Procedencia no válida: '%s'. Sólo 'pedido'", v))
	return "", false
}

// ---------------------------------------------------------------------------
// Los filtros compartidos  (`leerFiltros` / `whereDeFiltros` del contrato)
// ---------------------------------------------------------------------------

// filtrosPedido son los mismos para el catálogo y para los disponibles. TIENEN QUE
// SIGNIFICAR LO MISMO EN LOS DOS: si no, los números de una pantalla no cuadran con los
// de la otra y nadie sabe cuál creerse. Por eso se leen en UN sitio y se pasan enteros a
// las dos consultas.
//
// Todos son opcionales y nil quiere decir «no filtra», que es lo que espera el SQL.
type filtrosPedido struct {
	Q         *string
	Estado    *string
	Archivado *bool
	Domicilio *bool
	Cotizado  *bool
	Municipio *string
	Vendedor  *string
	BranchID  pgtype.UUID
	Reparto   *string
	Factura   *string
	Desde     pgtype.Timestamptz
	Hasta     pgtype.Timestamptz
}

func leerFiltros(r *http.Request) filtrosPedido {
	q := r.URL.Query()
	// `valorDe` y no `texto`: en este paquete ya hay un `texto(*string) string` y dos
	// nombres iguales con firmas distintas se leen mal en la revisión.
	valorDe := func(nombre string) string { return strings.TrimSpace(q.Get(nombre)) }

	f := filtrosPedido{
		// `q` va en minúsculas como en el contrato. Da igual para el ILIKE del SQL, que
		// ya es insensible, pero se conserva para que el valor que llega a la consulta
		// sea EL MISMO que llegaba en delivery y una comparación de registros cuadre.
		Q:         opcional(strings.ToLower(valorDe("q"))),
		Estado:    deLaLista(valorDe("estado"), "completada", "en_proceso", "expirada"),
		Archivado: unoOCero(valorDe("archivado")),
		Domicilio: unoOCero(valorDe("domicilio")),
		Cotizado:  unoOCero(valorDe("cotizado")),
		Municipio: opcional(valorDe("municipio")),
		Vendedor:  opcional(valorDe("vendedor")),
		Reparto:   deLaLista(valorDe("reparto"), "sin_entregar", "en_despacho", "en_ruta", "entregado", "devuelto"),
		// `factura` NO se valida contra una lista: el contrato dice que cualquier otro
		// valor no vacío se compara tal cual contra `factura_estado`. La última rama del
		// SQL es justo ésa.
		Factura: opcional(valorDe("factura")),
		Desde:   inicioDelDia(valorDe("desde")),
		Hasta:   finalDelDia(valorDe("hasta")),
	}

	// `branchId` es UN FILTRO MÁS, nunca el alcance. Va en AND con él en el SQL, así que
	// quien sólo ve una sucursal no puede pedir la de otra poniéndolo a mano: el AND de
	// los dos no deja pasar nada.
	if bruto := valorDe("branchId"); bruto != "" {
		if id, err := uuid.Parse(bruto); err == nil {
			f.BranchID = pgDe(id)
		} else {
			// Un id que no es un uuid no es de ninguna sucursal, así que el filtro no
			// puede casar con nada. Se traduce al uuid cero —que existe como valor pero
			// no como sucursal— en vez de ignorarlo: ignorarlo ENSANCHARÍA la consulta,
			// y un filtro que al escribirse mal enseña MÁS es justo lo contrario de un
			// filtro.
			f.BranchID = pgDe(uuid.Nil)
		}
	}
	return f
}

var esFecha = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`)

// inicioDelDia: `<fecha>T00:00:00` en la hora LOCAL del servidor, como el contrato. Si no
// casa el patrón, no hay filtro.
func inicioDelDia(s string) pgtype.Timestamptz {
	d, ok := diaLocal(s)
	if !ok {
		return pgtype.Timestamptz{}
	}
	return pgtype.Timestamptz{Time: d, Valid: true}
}

// finalDelDia: `<fecha>T23:59:59.999`. EL `hasta` INCLUYE EL DÍA ENTERO — quien escribe
// el 24 quiere los del 24, no los del 24 a las 00:00. Cortar a medianoche deja fuera la
// jornada completa de ese día, que es el día que se está mirando.
func finalDelDia(s string) pgtype.Timestamptz {
	d, ok := diaLocal(s)
	if !ok {
		return pgtype.Timestamptz{}
	}
	return pgtype.Timestamptz{Time: d.Add(24*time.Hour - time.Millisecond), Valid: true}
}

// diaNatural es el `fecha=YYYY-MM-DD` de los disponibles: un día completo, medio abierto
// por arriba. Es OTRO filtro distinto del rango `desde`/`hasta` —la pantalla del armador
// ofrece los dos y se combinan en AND—, y por eso tiene sus propios parámetros.
//
// Devuelve los dos extremos o ninguno: el SQL comprueba sólo el primero para saber si
// aplica el filtro, así que dejar uno puesto y el otro vacío compararía contra NULL y la
// condición no casaría nunca.
func diaNatural(s string) (pgtype.Timestamptz, pgtype.Timestamptz) {
	d, ok := diaLocal(s)
	if !ok {
		return pgtype.Timestamptz{}, pgtype.Timestamptz{}
	}
	return pgtype.Timestamptz{Time: d, Valid: true},
		pgtype.Timestamptz{Time: d.AddDate(0, 0, 1), Valid: true}
}

func diaLocal(s string) (time.Time, bool) {
	if !esFecha.MatchString(s) {
		return time.Time{}, false
	}
	d, err := time.ParseInLocation("2006-01-02", s, time.Local)
	if err != nil {
		return time.Time{}, false
	}
	return d, true
}

// ---------------------------------------------------------------------------
// Conversiones y cuentas pequeñas
// ---------------------------------------------------------------------------

// renglonesPorPedido trae los renglones de TODA la página en una consulta y los reparte
// por pedido. Con doscientos pedidos en pantalla, una consulta por fila son doscientas
// idas y vueltas a la base para pintar una tabla.
func (s *Servidor) renglonesPorPedido(r *http.Request, a *alcance.Acotado, ids []uuid.UUID) (map[uuid.UUID][]RenglonSalida, error) {
	porPedido := make(map[uuid.UUID][]RenglonSalida, len(ids))
	if len(ids) == 0 {
		return porPedido, nil
	}
	filas, err := a.ListarRenglonesDePedidos(r.Context(), ids)
	if err != nil {
		return nil, err
	}
	for _, g := range filas {
		porPedido[g.OrderID] = append(porPedido[g.OrderID], RenglonSalida{
			ID: g.ID, Linea: g.Linea, Description: g.Description, Name: g.Description,
			Quantity: g.Quantity, Packs: g.Packs, ProductID: idOpcional(g.ProductID),
			UpdatedAt: hora(g.UpdatedAt),
			PesoKg:    g.PesoUnitarioKg, PesoLineaKg: g.PesoLineaKg,
		})
	}
	return porPedido, nil
}

func dePedido(x sqlc.ListarPedidosRow, items []RenglonSalida) PedidoSalida {
	if items == nil {
		// Rodaja vacía y no nil: un pedido sin renglones sale `[]`, no `null`. La
		// pantalla recorre `items` sin mirar, y un null ahí es una fila en blanco.
		items = []RenglonSalida{}
	}
	p := PedidoSalida{
		ID: x.ID, OperationNumber: x.OperationNumber, CustomerName: x.CustomerName,
		CustomerPhone: x.CustomerPhone, Address: x.Address, EndAddress: x.EndAddress,
		EndLat: x.EndLat, EndLng: x.EndLng, Weight: x.Weight, Status: string(x.Status),
		PesoRespaldado: x.PesoRespaldado,
		Notes:          x.Notes, RouteID: idOpcional(x.RouteID), DeliveryPrice: x.DeliveryPrice,
		DeliveryDistanceKm: x.DeliveryDistanceKm,
		// `price = deliveryPrice ?? null` del contrato. No es un campo propio: es el
		// mismo precio con el nombre que la pantalla vieja espera.
		Price:             x.DeliveryPrice,
		Items:             items,
		OrderDate:         hora(x.OrderDate),
		CreatedAt:         hora(x.CreatedAt),
		DeliveredAt:       hora(x.DeliveredAt),
		Resultado:         textoDe(x.Resultado),
		ResultadoNota:     x.ResultadoNota,
		StopOrder:         x.StopOrder,
		Estado:            textoDe(x.Estado),
		Archivado:         x.Archivado,
		FechaComprometida: hora(x.FechaComprometida),
		RequiereDomicilio: x.RequiereDomicilio,
		PedidoCosto:       x.PedidoCosto,
		FacturaEstado:     textoDe(x.FacturaEstado),
		FacturaNumero:     x.FacturaNumero,
		FacturaDomicilio:  x.FacturaDomicilio,
		Municipio:         x.Municipio,
		Vendedor:          x.Vendedor,
		UpdatedAt:         hora(x.UpdatedAt),
		SucursalCodigo:    x.SucursalCodigo,
	}
	if id := idOpcional(x.RouteID); id != nil {
		p.Route = &RutaDePedido{
			ID: id, Name: x.RutaNombre, RouteCode: x.RutaCodigo,
			Status: textoDe(x.RutaEstado), DeliveryDate: hora(x.RutaFecha),
			Vehicle: &VehiculoDeRuta{Name: x.VehiculoNombre, Plate: x.VehiculoMatricula},
		}
	}
	if id := idOpcional(x.BranchID); id != nil {
		p.Branch = &SucursalDePedido{
			ID: id, Name: x.SucursalNombre, Lat: x.SucursalLat, Lng: x.SucursalLng,
		}
	}
	return p
}

// textoDe pasa un enum anulable de sqlc a texto anulable. Los enums son tipos propios
// (`PedidoEstado`, `FacturaEstado`…) y salir con ellos tal cual ataría el JSON a cómo los
// genere sqlc mañana.
func textoDe[T ~string](p *T) *string {
	if p == nil {
		return nil
	}
	v := string(*p)
	return &v
}

// decimalDelResumen saca el float de un `numeric` de Postgres. El peso del pre-despacho
// ya viene redondeado a dos decimales desde el SQL; aquí sólo se traduce el tipo.
func decimalDelResumen(n pgtype.Numeric) float64 {
	if !n.Valid {
		return 0
	}
	f, err := n.Float64Value()
	if err != nil || !f.Valid {
		return 0
	}
	return f.Float64
}

// conCero es el `pedidoCosto ?? 0` del filtro `costoMin`.
func conCero(p *float64) float64 {
	if p == nil {
		return 0
	}
	return *p
}

// opcional devuelve nil para la cadena vacía: es el «sin filtro» que espera el SQL.
func opcional(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

// deLaLista deja pasar sólo el vocabulario del contrato. Un valor de fuera de la lista NO
// se pasa a la consulta: el SQL compara contra cada opción una a una, así que un valor
// desconocido no casaría con ninguna rama y la pantalla saldría vacía sin decir por qué.
// Ignorarlo enseña el catálogo entero, que es lo que se ve venir.
func deLaLista(s string, validos ...string) *string {
	for _, v := range validos {
		if s == v {
			return &s
		}
	}
	return nil
}

// unoOCero: `'1'` -> true, `'0'` -> false, cualquier otra cosa -> sin filtro (los dos).
func unoOCero(s string) *bool {
	switch s {
	case "1":
		v := true
		return &v
	case "0":
		v := false
		return &v
	}
	return nil
}

// pasaElTopeDeKm decide si un pedido sobrevive al filtro «Hasta N km».
//
// SALIÓ A FUNCIÓN EL 26/09/2026 PARA PODER PROBARLA, y no por gusto. Ese día el lote dejó de
// medir `delivery_distance_km` desde el punto de la sucursal y empezó a medirlo desde el
// almacén del pedido (`cotizacion.go`, bloque 5-bis). En Santiago eso mueve un pedido de
// AURORA unos veinte kilómetros, así que **un pedido que hoy sale en la lista puede dejar de
// salir tras el despliegue, y al revés**: este filtro no cambia de código y sí cambia de
// resultado. Estando en línea, dentro de un bucle, no había forma de escribir esa prueba sin
// montar media API; ahora la escribe `TestElFiltroDeKmSeMueveConElOrigen`.
//
// UN PEDIDO SIN DISTANCIA MEDIDA NUNCA SE DESCARTA: no saber cuánto hay no es estar lejos, y
// dejarlo fuera esconde justo los que hay que mirar a mano.
func pasaElTopeDeKm(km *float64, tope float64, hayTope bool) bool {
	if !hayTope || km == nil {
		return true
	}
	return *km <= tope
}

// numeroDeQuery lee `kmMax` / `costoMin`. Cadena vacía o no numérica -> se ignora el
// filtro, como dice el contrato: con un tope mal escrito es mejor enseñar de más que
// esconder pedidos sin avisar.
func numeroDeQuery(s string) (float64, bool) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, false
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil || math.IsNaN(v) || math.IsInf(v, 0) {
		return 0, false
	}
	return v, true
}

// enteroConTope lee un entero de la query con su valor por defecto, su mínimo y su tope.
// Un `tope` de 0 quiere decir «sin tope». Es el `min(200, max(1, Number(x)||50))` del
// contrato, escrito una vez.
func enteroConTope(s string, porDefecto, minimo, tope int) int {
	v, err := strconv.Atoi(strings.TrimSpace(s))
	if err != nil {
		v = porDefecto
	}
	if v < minimo {
		v = minimo
	}
	if tope > 0 && v > tope {
		v = tope
	}
	return v
}

// paginas es `max(1, ceil(total/porPagina))`. Nunca cero: una tabla vacía sigue teniendo
// una página, y un cero deja al paginador sin nada que pintar.
func paginas(total int64, porPagina int) int {
	if porPagina <= 0 || total <= 0 {
		return 1
	}
	n := int((total + int64(porPagina) - 1) / int64(porPagina))
	if n < 1 {
		return 1
	}
	return n
}
