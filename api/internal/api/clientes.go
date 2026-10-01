package api

import (
	"context"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/cotizar"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// Los CLIENTES del espejo de PEDIDO. Sólo se leen: el alta a mano se retiró el
// 03/09/2026 y por eso aquí no hay POST ni PATCH ni DELETE.
//
// POR QUÉ NO HAY ALTA: un cliente creado aquí no existía en PEDIDO, así que ningún pedido
// suyo podía apuntarle y acababa duplicando al que ya estaba con otro nombre. Los clientes
// son de PEDIDO y llegan por el espejo; lo que se hace aquí es buscarlos.
//
// EL ALCANCE VA POR CÓDIGO DE SUCURSAL, no por `branch_id` —`customers` no tiene esa
// columna—, y lo rellena `internal/alcance`. Los clientes MANUALES (sin código) se ven
// siempre: no vinieron de ninguna sucursal concreta y esconderlos haría desaparecer
// clientes que sí se atienden, sin decir nada.

// avisarCambioDeClientes publica «cambió un cliente» para que las pantallas abiertas se
// enteren sin esperar al temporizador.
//
// # AQUÍ HABÍA UN COMENTARIO QUE MENTÍA — corregido el 29/09/2026
//
// `eventos.go` decía que `CambioClientes` no lo publicaba nadie y que **no era un olvido**,
// porque «en esta API NO HAY ninguna puerta que escriba `customers`». Era falso: la
// escribe `POST /api/webhooks/pedido` con el motivo `cliente`
// (`webhook_de_pedido.go`, `base.GuardarCliente`), que es justo el aviso de que alguien
// corrigió la coordenada de un cliente en PEDIDO.
//
// Y ése es el peor de los avisos que se pueden perder, porque **el reparto ordena las
// paradas por esa coordenada**: sin enterarse, la ruta se arma hacia el sitio de antes, con
// números y todo, sin un solo error y sin nada que lo desmienta.
//
// Lo que sigue sin publicar es el proceso del espejo (`cmd/espejo`, `ciclo.go`,
// `clientes()`), que corre en OTRO proceso y este bus vive en la memoria de éste.
//
// # LA SUCURSAL SE LA PASA QUIEN LLAMA, Y SU ÚNICO EMISOR LA MANDA GLOBAL
//
// Desde el 01/10/2026 el gancho acepta la sucursal igual que los demás, pero su único emisor
// —el webhook de PEDIDO— pasa `DeTodasLasSucursales` **a propósito y con su motivo escrito
// allí**: `customers` se acota por CÓDIGO de sucursal (`CAM`, `STG`…) y no por uuid, y el bus
// reparte por uuid, así que afinarlo costaría una consulta de traducción más en el camino de
// MÁS volumen que tiene esta API. El parámetro está para el día que lo llame alguien que ya
// tenga el uuid en la mano.
var avisarCambioDeClientes = func(_ context.Context, _ string) {}

// TopeClientes: 50 por página, FIJO y no configurable.
//
// Con doscientas filas los botones de página quedaban al final de un desplazamiento
// larguísimo y la gente daba por hecho que no había paginación. Cincuenta caben en dos
// pantallazos.
const TopeClientes = 50

// PedidosParaElUso y TopeCatalogo viven en productos.go: son del catálogo, no de aquí.

type ClienteSalida struct {
	ID             uuid.UUID  `json:"id"`
	Source         *string    `json:"source"`
	ExternalID     *string    `json:"externalId"`
	Name           string     `json:"name"`
	Phone          *string    `json:"phone"`
	Address        *string    `json:"address"`
	Municipio      *string    `json:"municipio"`
	Zona           *string    `json:"zona"`
	Lat            float64    `json:"lat"`
	Lng            float64    `json:"lng"`
	SucursalCodigo *string    `json:"sucursalCodigo"`
	Codigo         *string    `json:"codigo"`
	Vendedor       *string    `json:"vendedor"`
	SyncedAt       *time.Time `json:"syncedAt"`
	// KmDelAlmacen sólo sale cuando se midió, y por eso es `omitempty`: un 0 donde no se
	// midió nada se lee como «está en la puerta del almacén».
	KmDelAlmacen *float64 `json:"kmDelAlmacen,omitempty"`
}

// Faceta es una opción de un desplegable con cuántos clientes tiene detrás.
type Faceta struct {
	Valor    string `json:"valor"`
	Clientes int64  `json:"clientes"`
}

// PuntoDelAlmacen es desde dónde se midió. Se devuelve a propósito: «a 10 km» de un
// almacén y de otro no es lo mismo, y sin decirlo el número no se puede comprobar.
type PuntoDelAlmacen struct {
	Latitud  float64 `json:"latitud"`
	Longitud float64 `json:"longitud"`
}

type ClientesSalida struct {
	Count               int              `json:"count"`
	Total               int64            `json:"total"`
	Pagina              int              `json:"pagina"`
	PorPagina           int              `json:"porPagina"`
	Paginas             int64            `json:"paginas"`
	Truncated           bool             `json:"truncated"`
	Customers           []ClienteSalida  `json:"customers"`
	AlmacenDeReferencia *PuntoDelAlmacen `json:"almacenDeReferencia"`
	Municipios          []Faceta         `json:"municipios"`
	Sucursales          []Faceta         `json:"sucursales"`
	Zonas               []Faceta         `json:"zonas"`
	Vendedores          []Faceta         `json:"vendedores"`
	SinTelefono         int64            `json:"sinTelefono"`
}

// GET /api/customers
func (s *Servidor) listarClientes(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	p := r.URL.Query()

	pagina := 1
	if n, err := strconv.Atoi(strings.TrimSpace(p.Get("pagina"))); err == nil && n > 1 {
		pagina = n
	}

	// El código de sucursal que pide la query. Estrecha DENTRO del alcance y nunca lo
	// amplía: el SQL lo junta con un AND al filtro del alcance, así que pedir el de otra
	// sucursal no enseña la de otra, deja la lista vacía.
	sucursalPedida := textoQuery(p, "sucursalCodigo")

	filtros := sqlc.ListarClientesParams{
		SucursalCodigo: sucursalPedida,
		Q:              textoQuery(p, "q"),
		Municipio:      textoQuery(p, "municipio"),
		Zona:           textoQuery(p, "zona"),
		Vendedor:       textoQuery(p, "vendedor"),
		Origen:         origenDeClientes(p.Get("origen")),
		ConTelefono:    conTelefono(p.Get("telefono")),
		Desplazamiento: int32((pagina - 1) * TopeClientes),
		Limite:         TopeClientes,
	}

	// El filtro por kilómetros: primero la CAJA, que la resuelve un índice.
	//
	// La distancia exacta se mide DESPUÉS y sólo sobre la página. Meter el haversine en
	// el WHERE obliga a recorrer los siete mil clientes fila a fila en cada búsqueda.
	var almacen *PuntoDelAlmacen
	kmMax, _ := strconv.ParseFloat(strings.TrimSpace(p.Get("kmMax")), 64)
	if kmMax > 0 && !math.IsInf(kmMax, 0) {
		// Desde qué sucursal se mide: manda el código del ALCANCE; el de la query sólo
		// vale cuando no hay alcance (Super Admin mirando todas).
		codigo := a.Codigo()
		if codigo == nil {
			codigo = sucursalPedida
		}
		if codigo != nil {
			almacen = s.almacenDeReferencia(r, *codigo)
		}
		if almacen != nil {
			// Un grado de latitud son ~111 km en cualquier sitio; uno de longitud se
			// encoge con el coseno de la latitud. El suelo de 0.1 es para que cerca de
			// los polos no salga una caja infinita —aquí no pasa, pero una división que
			// puede tender a cero no se deja suelta.
			gradosLat := kmMax / 111
			gradosLng := kmMax / (111 * math.Max(0.1, math.Cos(almacen.Latitud*math.Pi/180)))
			filtros.LatMin, filtros.LatMax = flotante(almacen.Latitud-gradosLat), flotante(almacen.Latitud+gradosLat)
			filtros.LngMin, filtros.LngMax = flotante(almacen.Longitud-gradosLng), flotante(almacen.Longitud+gradosLng)
		}
	}

	filas, err := a.ListarClientes(r.Context(), filtros)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	// El total va con el MISMO where —menos el límite— y ANTES del filtro de distancia
	// exacto. Por eso puede ser mayor que `count`, y eso es lo correcto: el de la caja es
	// el que la base puede contar sin medir siete mil distancias.
	total, err := a.ContarClientes(r.Context(), sqlc.ContarClientesParams{
		SucursalCodigo: filtros.SucursalCodigo,
		Q:              filtros.Q,
		Municipio:      filtros.Municipio,
		Zona:           filtros.Zona,
		Vendedor:       filtros.Vendedor,
		Origen:         filtros.Origen,
		ConTelefono:    filtros.ConTelefono,
		LatMin:         filtros.LatMin,
		LatMax:         filtros.LatMax,
		LngMin:         filtros.LngMin,
		LngMax:         filtros.LngMax,
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	facetas, err := facetasDeClientes(r, a)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	salida := make([]ClienteSalida, 0, len(filas))
	for _, f := range filas {
		c := ClienteSalida{
			ID: f.ID, Source: procedencia(f.Source), ExternalID: f.ExternalID,
			Name: f.Name, Phone: f.Phone, Address: f.Address, Municipio: f.Municipio,
			Zona: f.Zona, Lat: f.Lat, Lng: f.Lng, SucursalCodigo: f.SucursalCodigo,
			Codigo: f.Codigo, Vendedor: f.Vendedor, SyncedAt: hora(f.SyncedAt),
		}
		if almacen != nil {
			// La caja mete de más en las esquinas del cuadrado; medir aquí lo quita.
			km := redondear(kmHaversine(almacen.Latitud, almacen.Longitud, f.Lat, f.Lng), 2)
			if km > kmMax {
				continue
			}
			c.KmDelAlmacen = &km
		}
		salida = append(salida, c)
	}

	paginas := (total + TopeClientes - 1) / TopeClientes
	if paginas < 1 {
		paginas = 1
	}
	httpx.JSON(w, r, http.StatusOK, ClientesSalida{
		Count:     len(salida),
		Total:     total,
		Pagina:    pagina,
		PorPagina: TopeClientes,
		Paginas:   paginas,
		// `truncated` se mide contra lo que trajo la consulta, NO contra lo que quedó
		// tras medir: dice «hay más páginas», no «se descartaron lejanos».
		Truncated:           total > int64(len(filas)),
		Customers:           salida,
		AlmacenDeReferencia: almacen,
		Municipios:          facetas.municipios,
		Sucursales:          facetas.sucursales,
		Zonas:               facetas.zonas,
		Vendedores:          facetas.vendedores,
		SinTelefono:         facetas.sinTelefono,
	})
}

// rutasClientes monta lo de este fichero. Va con `sesion`: los clientes los mira
// cualquiera que haya entrado, y lo que ve lo decide el alcance, no el rol.
//
// `admin` no se usa aquí y está a propósito en la firma: todas las de este paquete se
// montan igual, y una firma distinta por recurso es una invitación a montar uno sin
// alcance el día que haya prisa.
func (s *Servidor) rutasClientes(rt *httpx.Router, sesion, admin []httpx.Medio) {
	_ = admin
	rt.ManejarFunc(http.MethodGet, "/api/customers", s.listarClientes, sesion...)
}

// ---------------------------------------------------------------------------
// Ayudas
// ---------------------------------------------------------------------------

type facetasClientes struct {
	municipios  []Faceta
	sucursales  []Faceta
	zonas       []Faceta
	vendedores  []Faceta
	sinTelefono int64
}

// facetasDeClientes calcula los desplegables sobre TODO el alcance y SIN los filtros de
// búsqueda.
//
// POR QUÉ SIN LOS FILTROS: si se recalcularan con la búsqueda puesta, cada filtro dejaría
// a los demás con una sola opción —la que ya está elegida— y no habría forma de cambiar de
// idea sin borrarlo todo. Los desplegables tienen que seguir diciendo a dónde se puede ir.
func facetasDeClientes(r *http.Request, a *alcance.Acotado) (facetasClientes, error) {
	var f facetasClientes

	municipios, err := a.FacetasClientesMunicipios(r.Context())
	if err != nil {
		return f, err
	}
	sucursales, err := a.FacetasClientesSucursales(r.Context())
	if err != nil {
		return f, err
	}
	zonas, err := a.FacetasClientesZonas(r.Context())
	if err != nil {
		return f, err
	}
	vendedores, err := a.FacetasClientesVendedores(r.Context())
	if err != nil {
		return f, err
	}
	f.sinTelefono, err = a.ContarClientesSinTelefono(r.Context())
	if err != nil {
		return f, err
	}

	f.municipios = make([]Faceta, 0, len(municipios))
	for _, m := range municipios {
		f.municipios = append(f.municipios, Faceta{Valor: texto(m.Valor), Clientes: m.Clientes})
	}
	f.sucursales = make([]Faceta, 0, len(sucursales))
	for _, x := range sucursales {
		f.sucursales = append(f.sucursales, Faceta{Valor: texto(x.Valor), Clientes: x.Clientes})
	}
	f.zonas = make([]Faceta, 0, len(zonas))
	for _, z := range zonas {
		f.zonas = append(f.zonas, Faceta{Valor: texto(z.Valor), Clientes: z.Clientes})
	}
	f.vendedores = make([]Faceta, 0, len(vendedores))
	for _, v := range vendedores {
		f.vendedores = append(f.vendedores, Faceta{Valor: texto(v.Valor), Clientes: v.Clientes})
	}
	return f, nil
}

// almacenDeReferencia elige desde dónde se mide, con la MISMA función que la cotización y
// que el tablero: `cotizar.ElegirAlmacen`.
//
// AQUÍ HABÍA UNA COPIA DE LA REGLA, escrita a mano — 24/09/2026. Un bucle propio que
// miraba sólo las coordenadas: sin `activo`, sin descartar el (0,0) y desempatando por el
// orden en que Accesos sirviera la lista. Era la CUARTA escritura de la misma regla y
// nadie la comparaba con ninguna otra. Con ella, la columna de km y el filtro «Hasta N km»
// de la lista de Clientes de la WEB medían desde un almacén dado de baja mientras la ficha
// de Clientes de la APK medía desde el activo: el mismo cliente, dos distancias, y de esas
// distancias sale el domicilio que se cobra. Es el caso que Jose zanjó el mismo día — «no
// puede dar distinto, debe dar igual […] eso debe dar igual en todos los datos» — y el
// porqué entero está en `internal/cotizar/almacen.go`.
//
// La función y no «la misma regla escrita otra vez»: dos copias de una regla se separan, y
// ésta decide desde dónde se mide lo que se le cobra al cliente. Lo que ata a Go con el
// aparato es `docs/almacen-de-origen.casos.json`.
//
// Si Accesos no contesta NO se corta la petición: la lista de clientes sale igual, sin
// medir y con `almacenDeReferencia: null`. Que el buscador de clientes dependa de que
// Accesos esté en pie sería cambiar una función que casi nunca se usa por la que se usa
// todo el día.
func (s *Servidor) almacenDeReferencia(r *http.Request, codigo string) *PuntoDelAlmacen {
	lista, err := s.accesos.AlmacenesDeSucursal(r.Context(), codigo)
	if err != nil {
		httpx.Registro(r).Warn("no se pudo preguntar por los almacenes: se lista sin medir distancias",
			"sucursal", codigo, "err", err)
		return nil
	}
	elegido := cotizar.ElegirAlmacen(almacenesConPunto(lista))
	if elegido == nil {
		return nil
	}
	return &PuntoDelAlmacen{Latitud: *elegido.Latitud, Longitud: *elegido.Longitud}
}

// kmHaversine: distancia en línea recta, la misma fórmula y la misma constante que usan
// `pricing.ts` y la función `km_haversine` de la base. SIN redondear — quien la exponga
// decide con cuántos decimales.
//
// Se mide en línea recta a propósito y no por carretera: es lo que hace la APK y es lo
// que se cobra. Cambiar aquí a distancia de ruta cambiaría el precio de todos los
// domicilios sin que lo diga ninguna pantalla.
func kmHaversine(lat1, lng1, lat2, lng2 float64) float64 {
	const radioTierraKm = 6371.0
	dLat := (lat2 - lat1) * math.Pi / 180
	dLng := (lng2 - lng1) * math.Pi / 180
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*math.Pi/180)*math.Cos(lat2*math.Pi/180)*math.Sin(dLng/2)*math.Sin(dLng/2)
	return radioTierraKm * 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}

func redondear(v float64, decimales int) float64 {
	factor := math.Pow(10, float64(decimales))
	return math.Round(v*factor) / factor
}

// textoQuery devuelve nil cuando el parámetro no vino o vino en blanco. nil es «no
// filtres por esto»; una cadena vacía sería «filtra por lo que no tiene nada», que es
// justo lo contrario.
func textoQuery(p map[string][]string, nombre string) *string {
	vs, hay := p[nombre]
	if !hay || len(vs) == 0 {
		return nil
	}
	v := strings.TrimSpace(vs[0])
	if v == "" {
		return nil
	}
	return &v
}

// origenDeClientes: sólo 'pedido' y 'manual'. Cualquier otra cosa se ignora en vez de
// devolver cero clientes — un valor desconocido en la barra de direcciones no puede
// parecer «esta sucursal no tiene nadie».
func origenDeClientes(v string) *string {
	switch strings.TrimSpace(v) {
	case "pedido":
		s := "pedido"
		return &s
	case "manual":
		s := "manual"
		return &s
	}
	return nil
}

// conTelefono: '1' los que tienen, '0' los que no, nada = los dos.
func conTelefono(v string) *bool {
	switch strings.TrimSpace(v) {
	case "1":
		si := true
		return &si
	case "0":
		no := false
		return &no
	}
	return nil
}

func flotante(v float64) *float64 { return &v }

// procedencia pasa el enum de la base a texto. `source` NULL es el cliente MANUAL, y sale
// como null: es lo que distingue al que vino del espejo del que se dio de alta a mano.
func procedencia(p *sqlc.Procedencia) *string {
	if p == nil {
		return nil
	}
	v := string(*p)
	return &v
}

func texto(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
