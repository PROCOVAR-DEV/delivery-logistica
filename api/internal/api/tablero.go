// EL TABLERO DE PREPARACIÓN. La pantalla nueva, especificada entera en `docs/tablero.md`.
//
// En una línea: entre «me han llegado 180 pedidos» y «sale este camión con estas 14
// paradas» hay un trabajo que hoy se hace en la cabeza del logístico y en un papel —
// agrupar por zona—. El tablero es ese paso: columnas que él pone, tarjetas que él
// arrastra, y de cada columna sale una ruta.
//
// LO QUE NO SE REINVENTA AQUÍ, porque ya lo decide la base y decidirlo dos veces es
// tenerlo decidido de dos maneras:
//
//   - «un pedido está en una columna o en ninguna» lo sostiene la clave primaria de
//     `board_placements`, que ES el pedido. No hay ningún `findFirst` que lo compruebe.
//   - «no se borra una columna con pedidos dentro» lo sostiene el `ON DELETE RESTRICT`.
//     Lo que pone este fichero es el mensaje que se entiende, no la prohibición.
//   - «este pedido ya va en un camión» lo comprueba el `WHERE` del propio INSERT, en el
//     mismo instante en que escribe. Mirarlo antes en Go es mirar una foto vieja.
//
// Y LO QUE SÍ ES DE AQUÍ: que el exceso de peso AVISE y no impida (§7.3 de la spec), que
// las escrituras sean REAPLICABLES —el tablero se usa sin red y sus órdenes suben en
// lotes que se reintentan (`docs/sincronizacion.md`)—, y que ninguna tarjeta desaparezca
// sola: se marca, no se esconde.
package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/cotizar"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// rutasTablero monta el tablero. Lo llama `Rutas()` en servidor.go.
//
// Todas con sesión y con alcance —aquí el alcance es SEGURIDAD y va dentro del SQL— y
// ninguna con `admin`: el tablero es la herramienta diaria del logístico de la sucursal,
// no una pantalla de administración. `admin` se recibe igual para que la firma sea la
// misma que la de los demás grupos de rutas y no haya que recordar cuál la lleva.
func (s *Servidor) rutasTablero(rt *httpx.Router, sesion, admin []httpx.Medio) {
	_ = admin

	rt.ManejarFunc(http.MethodGet, "/api/board", s.tablero, sesion...)
	rt.ManejarFunc(http.MethodGet, "/api/board/unplaced", s.tableroSinColocar, sesion...)

	rt.ManejarFunc(http.MethodPost, "/api/board/columns", s.crearColumna, sesion...)
	// `PUT /api/board/columns/orden` va por el MISMO patrón que `{id}` y se reparte
	// dentro, no como una ruta propia. No es un capricho: este router monta, por cada
	// patrón, una entrada sin método que recoge los 405, y `ServeMux` rechaza de plano
	// registrar `/api/board/columns/{id}` sin método junto a `/api/board/columns/orden`
	// —el proceso se cae AL ARRANCAR, con un pánico—. Repartir dentro deja la URL del
	// contrato intacta y el router con un patrón solo.
	rt.ManejarFunc(http.MethodPut, "/api/board/columns/{id}", s.putColumna, sesion...)
	rt.ManejarFunc(http.MethodPatch, "/api/board/columns/{id}", s.actualizarColumna, sesion...)
	rt.ManejarFunc(http.MethodDelete, "/api/board/columns/{id}", s.borrarColumna, sesion...)
	rt.ManejarFunc(http.MethodPost, "/api/board/columns/{id}/route", s.armarRutaDeColumna, sesion...)

	rt.ManejarFunc(http.MethodPut, "/api/board/placements/{id}", s.colocarPedido, sesion...)
	rt.ManejarFunc(http.MethodDelete, "/api/board/placements/{id}", s.quitarPedidoDelTablero, sesion...)
}

// avisarCambioDelTablero publica «algo cambió en el tablero» para que las pantallas
// abiertas se enteren sin esperar al temporizador.
//
// Vacío por defecto y lo engancha el fichero del bus (`eventos.go`), igual que el de rutas.
// **NO devuelve error y no se mira lo que conteste**: una zona no se deja de crear porque
// el aviso no salga.
//
// AQUÍ DECÍA QUE EL BUS LO FRENA, Y YA NO — 29/09/2026. Ponía que «el bus tiene un freno de
// quince segundos por tipo, así que arrastrar doce tarjetas seguidas no manda doce avisos».
// Eso era verdad y era justamente el fallo: Jose movió dos tarjetas seguidas con el teléfono
// y el navegador delante, y la segunda tardó dieciséis segundos en aparecer al otro lado.
// `tablero` ya NO está en `tiposFrenados` (`eventos.go`): cada gesto sale en el acto, y sí,
// doce tarjetas son doce avisos. Es lo que se pidió — esta pantalla es la que dos personas
// miran a la vez.
//
// # LA SUCURSAL SE LA PASA EL MANEJADOR, LEÍDA DE LA FILA — 01/10/2026
//
// Antes no llevaba ninguna y el bus la sacaba del alcance de quien llamó. Eso dejaba el
// aviso PELADO —y por tanto «de todas», o sea una bajada del tablero entero en las otras
// siete— en los dos casos que más se dan aquí: quien ve las ocho (SUPER ADMIN) y cualquier
// apunte que suba por la cola del teléfono, porque el sincronizador no reenvía
// `X-Sucursal-Id`. Medido en producción el 01/10/2026 a las 13:07:54 UTC.
//
// Los siete manejadores de este fichero tienen la sucursal delante sin preguntar nada: o es
// `t.sucursal` —la del tablero que se está tocando, ya comprobada contra el alcance en
// `tableroDe`— o es el `BranchID` de la propia fila que se acaba de escribir, leer o borrar.
// El porqué entero está en `eventos.go`, encima del `init()`.
var avisarCambioDelTablero = func(_ context.Context, _ string) {}

// ---------------------------------------------------------------------------
// Mensajes literales del tablero
// ---------------------------------------------------------------------------
//
// Van aquí, juntos y como constantes, por lo mismo que los de `httpx`: salen en la
// pantalla del logístico y están inventariados en la spec. Escritos a mano dentro del
// manejador acaban diciendo tres cosas parecidas en tres sitios.
const (
	msgElijeSucursal = "Elige una sucursal para ver su tablero"
	msgYaVaEnUnaRuta = "Ese pedido ya está en una ruta"
	// EL OTRO 409 DE ESA MISMA PUERTA, y no se arregla igual que el de arriba.
	//
	// «Ya está en una ruta» se arregla solo en cuanto esa ruta se cierre; «ya se
	// entregó» NO se arregla nunca, y quien lo lea tiene que saber que no tiene que
	// esperar a nada. Decirle lo primero cuando pasa lo segundo es mandarlo a vigilar
	// una ruta que puede que ni exista ya.
	// LOS «NO ESTÁ», EN ESPAÑOL Y DICIENDO QUÉ — 29/09/2026.
	//
	// Estos catorce sitios contestaban `httpx.MsgNotFound`, o sea **«Not found»**, y son
	// justo las puertas por las que sube un apunte armado sin señal. El sincronizador
	// reenvía el cuerpo del 4xx tal cual (`sync/internal/reparto/reparto.go`), así que ese
	// «Not found» acababa literalmente en la bandeja del teléfono de un repartidor, en
	// inglés y sin decir qué es lo que no está.
	//
	// La constante de `httpx` no se toca: está inventariada como literal del contrato de
	// `/api/vehicles/[id]` y cambiarla rompe a quien la compara. Lo que se cambia es lo
	// que dice ESTA pantalla, que es la que lee una persona.
	//
	// Y se dice «no existe» también cuando existe pero es de otra sucursal, a propósito:
	// decir «existe pero no es tuyo» ya es contar algo de otra sucursal, que es la fuga
	// que el §4 prohíbe. La persona ve lo mismo en los dos casos, y es lo correcto.
	msgZonaNoEsta     = "Esa zona del tablero ya no existe"
	msgPedidoNoEsta   = "Ese pedido no existe o no es de tu sucursal"
	msgSucursalNoEsta = "Esa sucursal no existe o no es tuya"

	msgYaSeEntrego     = "Ese pedido ya se entregó"
	msgColumnaSinNada  = "La columna no tiene ningún pedido que se pueda repartir hoy"
	msgNombreRequerido = "La columna necesita un nombre"
	// La lista de pedidos vino VACÍA. No es lo mismo que no mandarla: mandarla vacía es
	// un aparato diciendo que no eligió nada, y armar entonces con todo lo que haya
	// puesto es exactamente el fallo que la lista viene a tapar.
	msgListaVacia = "Vino la lista de pedidos pero está vacía: no se sabe qué tenía que salir en esta ruta"
	// NINGUNA RUTA SIN CAMIÓN — 28/09/2026.
	//
	// Jose, viendo `RT-20260928-001`, «En curso · 3 paradas · Sin vehículo»: «por q se
	// creo una ruta sin vehiculo eso no se puede mi broder». Aquí arriba se leía
	// «Puede no haber ninguno; la ruta se arma igual y el camión se elige después», y eso
	// era exactamente el agujero: sin camión, el `516.5 kg` y el `$2.99` de esa ruta no se
	// pueden contrastar con nada —la capacidad se mide contra la del camión y el coste por
	// km sale de su `costo_km_usd`—, así que la ruta sale con dos números creíbles y sin
	// denominador.
	//
	// El mensaje NO es el de `POST /api/routes` («Se requiere un vehículo para crear la
	// ruta») a propósito: ahí el camión se elige en el paso 3 del asistente y allí mismo se
	// arregla; aquí el camión es el PREVISTO DE LA ZONA y se pone en otro sitio —«Camión
	// previsto», en las opciones de la zona—, así que el «no» tiene que decir dónde. Un
	// rechazo que no dice dónde se arregla es un rechazo permanente.
	msgZonaSinCamion = "La zona no tiene camión previsto, y sin camión no se arma su ruta. " +
		"Elígelo en «Camión previsto», en las opciones de la zona, y vuelve a armar: sin " +
		"camión no hay capacidad contra la que medir la carga ni costo por km con el que " +
		"cotizar el domicilio."
)

// TopeSinColocar es el tope por defecto de la mitad izquierda. Se puede bajar por query,
// no subir: la conexión de allá no da para más.
//
// EL TOPE YA NO ES UN TECHO, ES UNA TANDA. Hasta el 18/09/2026 sí era un techo: la
// consulta acababa en `LIMIT` sin `OFFSET` ni cursor, así que lo que no cabía en los 200
// primeros NO SE PODÍA PEDIR DE NINGUNA MANERA. Medido en producción el 17/09/2026, La
// Habana tenía 300 pedidos sin colocar: el logístico veía los 200 más cercanos y los 100
// más lejanos no existían para él. `Truncated` lo avisaba y no llevaba a ningún sitio,
// que es el §3 del CLAUDE.md —pedir un tope y no poder seguir— y el fallo que más caro
// sale aquí.
//
// Ahora se pide la tanda siguiente con `?desde=<cursor>`, y el cursor lo devuelve la
// respuesta anterior en `siguiente`.
const TopeSinColocar = 200

// ---------------------------------------------------------------------------
// La respuesta
// ---------------------------------------------------------------------------

type ColumnaSalida struct {
	ID        uuid.UUID  `json:"id"`
	BranchID  uuid.UUID  `json:"branchId"`
	Nombre    string     `json:"nombre"`
	Posicion  int32      `json:"posicion"`
	VehicleID *uuid.UUID `json:"vehiculoId"`
	// Del camión previsto se enseña lo que hace falta para entender el aviso de peso.
	VehiculoNombre    *string  `json:"vehiculoNombre,omitempty"`
	VehiculoMatricula *string  `json:"vehiculoMatricula,omitempty"`
	VehiculoCapacidad *float64 `json:"vehiculoCapacidad,omitempty"`
	// Los totales los da la BASE, no la suma de lo pintado: la pantalla pagina y el
	// camión no. Con 60 pedidos puestos, sumar lo que se ve da el peso de los 20
	// primeros y el aviso de que no cabe no aparecería nunca.
	Pedidos  int64   `json:"pedidos"`
	PesoKg   float64 `json:"pesoKg"`
	CostoUsd float64 `json:"costoUsd"`
	// PUNTERO Y NO bool: sin camión previsto esto es NULL, que NO es `false`. Significa
	// «todavía no se sabe», y pintar «cabe» cuando nadie ha dicho en qué va es peor que
	// no pintar nada.
	ExcedeCamion *bool      `json:"excedeCamion"`
	CreatedAt    *time.Time `json:"createdAt"`
	UpdatedAt    *time.Time `json:"updatedAt"`
}

// TarjetaSalida es un pedido YA COLOCADO.
//
// Lleva `facturaEstado`, `archivado` y `rutaId` crudos a propósito: la tarjeta que dejó
// de servir SE MARCA, NO SE ESCONDE. Quitarla sola es hacer desaparecer el trabajo de
// alguien sin decírselo — el logístico vuelve a la columna, ve once paradas donde puso
// doce y no tiene manera de saber cuál falta ni por qué.
type TarjetaSalida struct {
	PedidoID        uuid.UUID  `json:"pedidoId"`
	ColumnaID       uuid.UUID  `json:"columnaId"`
	Posicion        int32      `json:"posicion"`
	ColumnaNombre   string     `json:"columnaNombre"`
	OperationNumber *string    `json:"operationNumber"`
	CustomerName    string     `json:"customerName"`
	CustomerPhone   *string    `json:"customerPhone"`
	Address         string     `json:"address"`
	EndAddress      *string    `json:"endAddress"`
	Weight          float64    `json:"weight"`
	PedidoCosto     *float64   `json:"pedidoCosto"`
	Municipio       *string    `json:"municipio"`
	Vendedor        *string    `json:"vendedor"`
	KmAlAlmacen     float64    `json:"kmAlAlmacen"`
	FacturaEstado   *string    `json:"facturaEstado"`
	Archivado       bool       `json:"archivado"`
	RutaID          *uuid.UUID `json:"rutaId"`
	Resultado       *string    `json:"resultado"`
	ColocadoAt      *time.Time `json:"colocadoAt"`
	// MismoCliente marca «2 pedidos de este cliente hoy». NO se funden las tarjetas: el
	// sufijo del folio es nuestro y X-2992 y X-2992-2 son dos pedidos, con su peso y su
	// domicilio cada uno. Juntarlos porque coincide el cliente es repetir el error de
	// julio: dos facturas, un solo bulto cargado.
	MismoCliente int `json:"mismoCliente"`
}

// SinColocarSalida es una tarjeta de la mitad izquierda. `kmAlAlmacen` es el campo por el
// que existe media pantalla.
type SinColocarSalida struct {
	ID              uuid.UUID  `json:"id"`
	OperationNumber *string    `json:"operationNumber"`
	CustomerName    string     `json:"customerName"`
	CustomerPhone   *string    `json:"customerPhone"`
	Address         string     `json:"address"`
	EndAddress      *string    `json:"endAddress"`
	Weight          float64    `json:"weight"`
	PedidoCosto     *float64   `json:"pedidoCosto"`
	Municipio       *string    `json:"municipio"`
	Vendedor        *string    `json:"vendedor"`
	OrderDate       *time.Time `json:"orderDate"`
	FacturaEstado   *string    `json:"facturaEstado"`
	KmAlAlmacen     float64    `json:"kmAlAlmacen"`
	MismoCliente    int        `json:"mismoCliente"`
}

// AvisosSalida son los tres contadores de arriba. TRES y no uno: «lo archivaron en
// PEDIDO», «se lo llevó otra ruta» y «no está facturado» se arreglan de tres maneras
// distintas, y un número único obligaría a abrir las doce columnas para saber cuál es.
type AvisosSalida struct {
	Archivados int64 `json:"archivados"`
	EnOtraRuta int64 `json:"enOtraRuta"`
	SinFactura int64 `json:"sinFactura"`
	Cambiados  int64 `json:"cambiados"`
	Colocados  int64 `json:"colocados"`
}

type AlmacenSalida struct {
	Nombre string  `json:"nombre"`
	Lat    float64 `json:"lat"`
	Lng    float64 `json:"lng"`
}

type SucursalDelTablero struct {
	ID     uuid.UUID `json:"id"`
	Nombre string    `json:"nombre"`
}

type MitadIzquierda struct {
	// Total son TODOS los que hay sin colocar con estos filtros, no los de esta tanda:
	// es el número que va encima de la lista y no puede bajar porque alguien pagine.
	Total int64 `json:"total"`
	Count int   `json:"count"`
	// Truncated es «HAY MÁS TANDAS», y se calcula pidiendo una fila de más, no restando
	// del total. Restando del total daba `true` para siempre en cuanto se paginaba.
	Truncated bool `json:"truncated"`
	// Siguiente es el cursor de la tanda siguiente, o nil si ésta fue la última. Es lo
	// que se le vuelve a mandar al servidor en `?desde=`. Antes no existía y por eso
	// `truncated` no llevaba a ningún sitio.
	Siguiente *string            `json:"siguiente"`
	Pedidos   []SinColocarSalida `json:"pedidos"`
}

// TableroSalida: el tablero entero en UNA ida y vuelta. Cinco peticiones para pintar una
// pantalla no caben en la conexión de allá.
type TableroSalida struct {
	Sucursal   SucursalDelTablero `json:"sucursal"`
	Almacen    AlmacenSalida      `json:"almacen"`
	Columnas   []ColumnaSalida    `json:"columnas"`
	Colocados  []TarjetaSalida    `json:"colocados"`
	Avisos     AvisosSalida       `json:"avisos"`
	SinColocar MitadIzquierda     `json:"sinColocar"`
	// VistoAt es la hora del servidor al contestar. Es lo que la pantalla enseña como
	// «visto por última vez a las 9:14» cuando se queda sin señal: un tablero que parece
	// vivo y lleva seis horas congelado es peor que uno que avisa.
	VistoAt time.Time `json:"vistoAt"`
}

// ---------------------------------------------------------------------------
// De dónde se mide la cercanía
// ---------------------------------------------------------------------------

// tableroDe resuelve las dos cosas sin las que no hay tablero: QUÉ sucursal se mira y
// DESDE DÓNDE se mide.
//
// `branchId` es obligatorio y no es redundante con el alcance: no existe «el tablero de
// todas». Las columnas son de una sucursal y la cercanía se mide desde el almacén de una
// sucursal — con diez mezcladas, el «más cercano primero» sale midiendo Holguín desde
// Santiago. Quien tiene alcance no necesita decirlo (se usa el suyo); el Super Admin, que
// no lo tiene, TIENE que elegir, y si no elige no se le enseña «todo», que es lo que
// parecería razonable y sería lo peor.
type tableroCtx struct {
	sucursal uuid.UUID
	nombre   string
	almacen  AlmacenSalida
}

func (s *Servidor) tableroDe(w http.ResponseWriter, r *http.Request, a *alcance.Acotado) (tableroCtx, bool) {
	var ctx tableroCtx

	crudo := strings.TrimSpace(r.URL.Query().Get("branchId"))
	if crudo == "" {
		if id := a.Sucursal(); id != nil {
			crudo = id.String()
		}
	}
	if crudo == "" {
		httpx.Error(w, r, http.StatusBadRequest, msgElijeSucursal)
		return ctx, false
	}
	id, err := uuid.Parse(crudo)
	if err != nil {
		// Un id que ni siquiera es un uuid es el mismo caso que uno que ya no está: los
		// de delivery eran cuid. 404, no 400.
		httpx.Error(w, r, http.StatusNotFound, msgSucursalNoEsta)
		return ctx, false
	}

	// Que la sucursal EXISTA y esté dentro del alcance. Sin esto, un `branchId` ajeno
	// devolvería un tablero vacío con 200, que es indistinguible de «todavía no hay
	// columnas»: el modo de fallo que este proyecto ya vio en producción.
	suc, err := a.ObtenerSucursal(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, msgSucursalNoEsta)
		return ctx, false
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return ctx, false
	}

	origen, ok := s.almacenDe(w, r, suc)
	if !ok {
		return ctx, false
	}
	return tableroCtx{sucursal: id, nombre: suc.Name, almacen: origen}, true
}

// almacenDe resuelve el punto desde el que se mide, y NO se inventa ninguno.
//
// SALE DE ACCESOS, QUE ES DONDE VIVEN LOS ALMACENES, y se elige con la MISMA función que
// `/api/quote/home-delivery` y que `GET /api/customers` (`cotizar.ElegirAlmacen`): el
// principal con coordenadas, si no el primero que las tenga, y si no hay ninguno NO HAY
// TABLERO. La misma función y no «la misma regla escrita otra vez»: dos copias de una
// regla se separan, y ésta decide desde dónde se mide lo que se le cobra al cliente.
//
// # DE DÓNDE SALÍA ANTES, Y POR QUÉ ERA EL FALLO (22/09/2026)
//
// Salía de `saved_origins` —los puntos de partida de ESTA base, herencia de delivery— y
// no de los almacenes. Son dos cosas distintas y no se llenan igual: el punto de partida
// lo dejó puesto quien dio de alta la sucursal en delivery, y el almacén lo pone el
// logístico desde la pantalla de Almacenes, que escribe en Accesos y **no toca esta
// base**. Resultado: La Habana, la única sucursal con `saved_origins`, tenía tablero, y
// las otras siete recibían `409 «<Sucursal> no tiene ningún almacén con coordenadas»`
// teniendo el almacén puesto, con su punto, a la vista en la pantalla de Almacenes y con
// el ✓ del Panel al lado. Tres pantallas contestando cosas distintas sobre el mismo dato:
// `CLAUDE.md` §3-bis. Lo que lo ata ahora es una prueba —`TestElTableroYLaCotizacionMiran
// ElMismoAlmacen`— y no este comentario.
//
// # POR QUÉ ESTO SIGUE SIENDO EL PRINCIPAL DE LA SUCURSAL, Y NO EL ALMACÉN DEL PEDIDO
//
// El 26/09/2026 `/api/quote/batch` dejó de medir `delivery_distance_km` desde el punto de la
// sucursal y pasó a medirlo desde el almacén DE CADA PEDIDO (`cotizar.ElegirOrigenDelPedido`).
// Aquí NO se hizo, y es una decisión, no un olvido — hay que saberlo antes de «arreglarlo»:
//
// De este almacén salen tres cosas, todas escritas en la base: el `origin_lat/lng` de la ruta,
// el `segment_km` de CADA parada y el `total_distance`. **Una ruta tiene UN origen porque el
// camión sale de UN sitio**: medir cada parada desde un almacén distinto daría un `segment_km`
// que no corresponde a ningún recorrido real, y `segment_km` es además el número con el que se
// repartió la carga hasta hoy, así que cambiarlo descuadra los informes viejos.
//
// Y el problema de fondo no se arregla eligiendo mejor aquí: **las columnas del tablero son por
// ZONA, no por almacén**, así que una ruta de Santiago puede llevar pedidos de AURORA y de
// PV-STGO a la vez y entonces ningún origen único es correcto para las dos mitades. Lo que hay
// que decidir es si una zona con dos almacenes son dos rutas o una ruta con dos recogidas, y eso
// lo decide Jose, no este fichero. Está apuntado en `docs/integracion-pendiente.md`.
//
// MIENTRAS TANTO, LO QUE PASA: una ruta armada sólo con pedidos de AURORA se arma desde PV-STGO,
// así que sus km no cuadran con el `delivery_distance_km` de sus propios pedidos. Los dos números
// existen y son distintos; lo que NO puede pasar es que nadie lo sepa, y por eso está escrito.
//
// # ACCESOS CAÍDO NO ES «NO TIENE ALMACÉN»
//
// La cotización trata el fallo de Accesos como lista vacía y acaba en el 409, y ahí es lo
// correcto: nunca se contesta un importe aproximado. Aquí no: decirle al logístico que su
// sucursal no tiene almacén cuando lo que pasa es que Accesos no contesta le manda a
// arreglar algo que no está roto. Eso es un 502 con el nombre de quien no contestó, igual
// que en `GET /api/almacenes`.
func (s *Servidor) almacenDe(w http.ResponseWriter, r *http.Request, suc sqlc.Branch) (AlmacenSalida, bool) {
	codigo := ""
	if suc.ExternalID != nil {
		codigo = strings.TrimSpace(*suc.ExternalID)
	}

	var lista []Almacen
	if codigo != "" {
		crudos, err := s.accesos.AlmacenesDeSucursal(r.Context(), codigo)
		if err != nil {
			httpx.Error(w, r, http.StatusBadGateway,
				fmt.Sprintf("No se pudieron traer los almacenes de Accesos: %s", err))
			return AlmacenSalida{}, false
		}
		lista = crudos
	}
	// Una sucursal sin código no tiene a quién preguntarle: no se adivina nada y se dice
	// lo mismo que si no tuviera almacén, que es lo que le pasa de hecho.

	elegido := cotizar.ElegirAlmacen(almacenesConPunto(lista))
	if elegido == nil {
		httpx.Error(w, r, http.StatusConflict,
			fmt.Sprintf(msgSinAlmacenF, suc.Name))
		return AlmacenSalida{}, false
	}
	return AlmacenSalida{Nombre: elegido.Nombre, Lat: *elegido.Latitud, Lng: *elegido.Longitud}, true
}

// almacenesConPunto traduce lo que da Accesos a lo que entiende la fórmula y deja fuera
// los que no tienen un punto DE VERDAD.
//
// (0,0) es el golfo de Guinea, no Santiago: un almacén así no tiene coordenadas, las tiene
// sin poner. Ordenar el tablero desde ahí pondría el pedido más lejano el primero y nada
// en la pantalla lo desmentiría — sale una lista ordenada, con sus kilómetros y todo.
func almacenesConPunto(crudos []Almacen) []cotizar.Almacen {
	salida := make([]cotizar.Almacen, 0, len(crudos))
	for _, a := range crudos {
		if a.Latitud == nil || a.Longitud == nil {
			continue
		}
		if *a.Latitud == 0 && *a.Longitud == 0 {
			continue
		}
		salida = append(salida, deAlmacenDeAccesos(a))
	}
	return salida
}

// ---------------------------------------------------------------------------
// GET /api/board
// ---------------------------------------------------------------------------

func (s *Servidor) tablero(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	t, ok := s.tableroDe(w, r, a)
	if !ok {
		return
	}

	columnas, err := a.ListarColumnasDelTablero(r.Context(), t.sucursal)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	colocados, err := a.ListarPedidosColocados(r.Context(), sqlc.ListarPedidosColocadosParams{
		OrigenLat: t.almacen.Lat, OrigenLng: t.almacen.Lng, BranchID: t.sucursal,
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisos, err := a.AvisosDelTablero(r.Context(), t.sucursal)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	izquierda, ok := s.mitadIzquierda(w, r, a, t)
	if !ok {
		return
	}

	salida := TableroSalida{
		Sucursal:   SucursalDelTablero{ID: t.sucursal, Nombre: t.nombre},
		Almacen:    t.almacen,
		Columnas:   deColumnas(columnas),
		Colocados:  deTarjetas(colocados),
		Avisos:     AvisosSalida(avisos),
		SinColocar: izquierda,
		VistoAt:    time.Now().UTC(),
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// GET /api/board/unplaced — sólo la mitad izquierda, para paginar y filtrar sin recargar
// las doce columnas enteras.
func (s *Servidor) tableroSinColocar(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	t, ok := s.tableroDe(w, r, a)
	if !ok {
		return
	}
	izquierda, ok := s.mitadIzquierda(w, r, a, t)
	if !ok {
		return
	}
	httpx.JSON(w, r, http.StatusOK, izquierda)
}

func (s *Servidor) mitadIzquierda(w http.ResponseWriter, r *http.Request, a *alcance.Acotado, t tableroCtx) (MitadIzquierda, bool) {
	q := r.URL.Query()
	limite := int32(TopeSinColocar)
	if n, err := strconv.Atoi(strings.TrimSpace(q.Get("limite"))); err == nil && n > 0 && n < TopeSinColocar {
		limite = int32(n)
	}
	desde, hasta := diaDelPedido(q.Get("dia"))

	// EL CURSOR DE LA TANDA SIGUIENTE. Un cursor que no se entiende es un 400 y no una
	// lista vacía: los tres trozos van juntos o la comparación queda en NULL y la consulta
	// devuelve CERO filas con un 200 limpio, que aquí es el modo de fallo caro — parecería
	// «ya no queda nada» justo cuando quedan cien.
	cursor, err := cursorDeLaTanda(q.Get("desde"))
	if err != nil {
		httpx.Error(w, r, http.StatusBadRequest, err.Error())
		return MitadIzquierda{}, false
	}

	arg := sqlc.ListarPedidosSinColocarParams{
		OrigenLat:  t.almacen.Lat,
		OrigenLng:  t.almacen.Lng,
		BranchID:   t.sucursal,
		Q:          textoOpcional(q.Get("q")),
		Municipio:  textoOpcional(q.Get("municipio")),
		Vendedor:   textoOpcional(q.Get("vendedor")),
		DiaDesde:   desde,
		DiaHasta:   hasta,
		KmMax:      numeroOpcional(q.Get("kmMax")),
		DesdeID:    cursor.id,
		DesdeKm:    cursor.km,
		DesdeFecha: cursor.fecha,
		// UNA FILA DE MÁS. Es lo que convierte «truncado» en un dato y no en una
		// sospecha: si vuelve, hay otra tanda; si no vuelve, ésta era la última. Restar
		// del total no sirve —el total es de TODOS, no de los que quedan— y daba
		// `truncated: true` para siempre en cuanto se paginaba.
		Limite: limite + 1,
	}
	filas, err := a.ListarPedidosSinColocar(r.Context(), arg)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return MitadIzquierda{}, false
	}
	hayMas := int32(len(filas)) > limite
	if hayMas {
		filas = filas[:limite]
	}

	// El contador lleva EL MISMO `WHERE` sin tope: si contara otra cosa diría «358»
	// encima de una lista de 120. VA SIN CURSOR a propósito: el número de arriba es el
	// TOTAL —«Sin colocar (300)»— y no puede bajar a 100 porque alguien haya bajado con
	// el dedo. El trozo del cursor está también en su SQL para que los dos `WHERE` sigan
	// siendo el mismo texto, que es lo único que vigila que el número no se separe de la
	// lista (`internal/store/contador_y_lista_test.go`).
	total, err := a.ContarPedidosSinColocar(r.Context(), paramsDelContador(arg))
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return MitadIzquierda{}, false
	}

	pedidos := make([]SinColocarSalida, 0, len(filas))
	repes := porCliente(filas)
	for _, f := range filas {
		pedidos = append(pedidos, SinColocarSalida{
			ID: f.ID, OperationNumber: f.OperationNumber, CustomerName: f.CustomerName,
			CustomerPhone: f.CustomerPhone, Address: f.Address, EndAddress: f.EndAddress,
			Weight: f.Weight, PedidoCosto: f.PedidoCosto, Municipio: f.Municipio,
			Vendedor: f.Vendedor, OrderDate: hora(f.OrderDate),
			FacturaEstado: facturaEstado(f.FacturaEstado), KmAlAlmacen: f.KmAlAlmacen,
			MismoCliente: repes[strings.ToLower(strings.TrimSpace(f.CustomerName))],
		})
	}
	// El cursor que se le devuelve: la ÚLTIMA fila servida. Sólo si hay más — mandar uno
	// cuando ya no queda nada invita a una vuelta de más por la conexión de allá.
	var siguiente *string
	if hayMas && len(filas) > 0 {
		ultima := filas[len(filas)-1]
		c := cursorHacia(ultima.KmAlAlmacen, ultima.OrderDate, ultima.ID)
		siguiente = &c
	}
	return MitadIzquierda{
		Total: total, Count: len(pedidos),
		Truncated: hayMas, Siguiente: siguiente, Pedidos: pedidos,
	}, true
}

// ---------------------------------------------------------------------------
// El cursor de la mitad izquierda
// ---------------------------------------------------------------------------

// tandaDesde son los tres trozos del cursor, ya en el tipo que espera sqlc.
type tandaDesde struct {
	km    *float64
	fecha pgtype.Timestamptz
	id    pgtype.UUID
}

// EL FORMATO ES «km|fecha|id», en texto plano y a propósito.
//
// Ni base64 ni JSON cifrado: esto se lee en un registro de acceso y en la barra del
// navegador cuando alguien dice «me faltan pedidos», y un cursor opaco obliga a
// descodificarlo a mano para saber por dónde iba. La fecha es RFC3339 con nanosegundos, o
// vacía cuando el pedido no tiene `order_date` —que es un caso real y va al final de la
// lista, no al principio—.
//
// No lleva firma ni caducidad porque no concede nada: el alcance no sale de aquí, sale de
// quién pregunta, y con un cursor inventado lo peor que se consigue es empezar a leer la
// lista propia por otro sitio.
const separadorDeTanda = "|"

func cursorHacia(km float64, fecha pgtype.Timestamptz, id uuid.UUID) string {
	texto := ""
	if fecha.Valid {
		texto = fecha.Time.UTC().Format(time.RFC3339Nano)
	}
	// 'g' con -1 es la representación más corta que vuelve a dar EXACTAMENTE el mismo
	// float al leerla. Importa: el corte compara `km = desde_km` en la base, y un
	// redondeo por el camino repetiría una fila o se saltaría otra.
	return strconv.FormatFloat(km, 'g', -1, 64) + separadorDeTanda + texto + separadorDeTanda + id.String()
}

func cursorDeLaTanda(crudo string) (tandaDesde, error) {
	crudo = strings.TrimSpace(crudo)
	if crudo == "" {
		return tandaDesde{}, nil // desde el principio
	}
	trozos := strings.Split(crudo, separadorDeTanda)
	if len(trozos) != 3 {
		return tandaDesde{}, errCursorRoto
	}
	km, err := strconv.ParseFloat(trozos[0], 64)
	if err != nil {
		return tandaDesde{}, errCursorRoto
	}
	id, err := uuid.Parse(trozos[2])
	if err != nil {
		return tandaDesde{}, errCursorRoto
	}
	salida := tandaDesde{km: &km, id: pgtype.UUID{Bytes: [16]byte(id), Valid: true}}
	if trozos[1] != "" {
		t, err := time.Parse(time.RFC3339Nano, trozos[1])
		if err != nil {
			return tandaDesde{}, errCursorRoto
		}
		salida.fecha = pgtype.Timestamptz{Time: t, Valid: true}
	}
	return salida, nil
}

// errCursorRoto: se dice QUÉ hacer. Un cursor a medias dejaría la comparación del SQL en
// NULL y la lista saldría vacía con un 200 limpio — «no queda nada» con cien esperando.
var errCursorRoto = errors.New(
	"«desde» no es un cursor de esta lista. Vuelve a pedir la primera tanda sin «desde» " +
		"y usa el «siguiente» que venga en la respuesta.")

// ---------------------------------------------------------------------------
// Las columnas
// ---------------------------------------------------------------------------

type cuerpoColumna struct {
	Nombre     httpx.Opcional[string] `json:"nombre"`
	VehiculoID httpx.Opcional[string] `json:"vehiculoId"`

	// EL ID QUE PONE EL APARATO. Opcional: sin él lo pone la base, como siempre.
	//
	// Es lo que hace que subir dos veces la misma zona no cree dos. El aparato lo genera
	// como UUIDv7 al crearla —aunque esté sin señal— y lo manda; si la respuesta no llega
	// y reintenta, el mismo id entra una sola vez y se le devuelve la que ya estaba.
	//
	// Sin esto, «¿llegó o no llegó?» era una pregunta sin respuesta: el aparato se
	// inventaba un `local-…`, había que sustituirlo cuando el servidor contestaba, y si no
	// contestaba, el reintento creaba otra zona.
	ID httpx.Opcional[string] `json:"id"`
}

// POST /api/board/columns — va al final; la posición la calcula la base.
//
// La posición NO la manda la pantalla a propósito: dos aparatos sin conexión propondrían
// el mismo número, y entonces hay dos «tercera» y ninguna «quinta».
func (s *Servidor) crearColumna(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	t, ok := s.tableroDe(w, r, a)
	if !ok {
		return
	}
	var c cuerpoColumna
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	nombre := strings.TrimSpace(c.Nombre.Con(""))
	if nombre == "" {
		httpx.Error(w, r, http.StatusBadRequest, msgNombreRequerido)
		return
	}
	veh, ok := vehiculoDelCuerpo(w, r, a, c.VehiculoID)
	if !ok {
		return
	}

	// EL ID DEL APARATO, si lo trae. Se exige que sea un uuid: uno que no lo sea es un
	// `local-…` de una versión anterior, y aceptarlo a ciegas metería en la base un id que
	// ningún otro aparato podría volver a nombrar.
	var id pgtype.UUID
	if crudo := strings.TrimSpace(c.ID.Con("")); crudo != "" {
		u, err := uuid.Parse(crudo)
		if err != nil {
			httpx.Error(w, r, http.StatusBadRequest,
				"«id» tiene que ser un uuid: lo pone el aparato al crear la zona, y es "+
					"lo que permite subirla dos veces sin que se creen dos")
			return
		}
		id = pgtype.UUID{Bytes: u, Valid: true}
	}

	fila, err := a.CrearColumna(r.Context(), sqlc.CrearColumnaParams{
		ID: id, Nombre: nombre, VehicleID: veh, BranchID: t.sucursal,
	})
	// Dos «Vista Alegre» en el mismo tablero es colocar la mitad de los pedidos en la
	// equivocada y no enterarse hasta que salen dos camiones al mismo barrio. Lo impide
	// el índice único; aquí se traduce a algo que se entiende.
	//
	// SE MIRA CUÁL DE LAS DOS ÚNICAS SALTÓ, y no un 23505 a secas. `board_columns` tiene
	// otra —`board_columns_posicion_unica`, `DEFERRABLE INITIALLY DEFERRED`— que revienta
	// al cerrar la transacción cuando dos aparatos suben a la vez: los dos calcularon el
	// mismo `max(posicion)+1`. Con el 23505 a secas, ese choque se contestaba «Ya hay una
	// columna “X” en este tablero», que es FALSO, y el apunte quedaba rechazado en la
	// bandeja con un motivo que no explica nada ni dice qué hacer.
	if esEstaClaveRepetida(err, "board_columns_nombre_idx") {
		httpx.Error(w, r, http.StatusConflict,
			fmt.Sprintf("Ya hay una columna «%s» en este tablero", nombre))
		return
	}
	// El choque de posición SÍ se reintenta: no es un rechazo de negocio, es que dos
	// aparatos llegaron a la vez. Un 409 lo mataría en la bandeja; un 409 con este texto
	// deja claro que se vuelva a intentar.
	if esEstaClaveRepetida(err, "board_columns_posicion_unica") {
		httpx.Error(w, r, http.StatusConflict,
			"Otro aparato creó una zona en el mismo momento. Vuelve a intentarlo.")
		return
	}
	if errors.Is(err, pgx.ErrNoRows) {
		// El `FROM branches` de la consulta no casó: la sucursal no existe o no es del
		// alcance. Ya se comprobó arriba, así que llegar aquí es una carrera.
		httpx.Error(w, r, http.StatusNotFound, msgSucursalNoEsta)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// DE LA FILA, no del alcance: la zona se acaba de escribir con `BranchID: t.sucursal`
	// tres líneas más arriba, así que la sucursal del aviso es la que lleva dentro.
	avisarCambioDelTablero(r.Context(), deLaFila(fila.BranchID))
	httpx.JSON(w, r, http.StatusCreated, deColumnaPelada(fila))
}

// PATCH /api/board/columns/{id} — renombrar y elegir camión.
func (s *Servidor) actualizarColumna(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, msgZonaNoEsta)
	if !ok {
		return
	}
	var c cuerpoColumna
	if !httpx.LeerJSON(w, r, &c) {
		return
	}

	arg := sqlc.ActualizarColumnaParams{ID: id}
	if c.Nombre.Presente && c.Nombre.Valor != nil {
		nombre := strings.TrimSpace(*c.Nombre.Valor)
		if nombre == "" {
			httpx.Error(w, r, http.StatusBadRequest, msgNombreRequerido)
			return
		}
		arg.Nombre = &nombre
	}
	// `tocar_vehiculo` existe porque «no me lo toques» y «quítamelo» son dos órdenes
	// distintas y las dos llegan con el campo vacío. Sin la bandera, renombrar la
	// columna le desasignaría el camión de paso.
	if c.VehiculoID.Presente {
		arg.TocarVehiculo = true
		veh, ok := vehiculoDelCuerpo(w, r, a, c.VehiculoID)
		if !ok {
			return
		}
		arg.VehicleID = veh
	}

	fila, err := a.ActualizarColumna(r.Context(), arg)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, msgZonaNoEsta)
		return
	}
	if esClaveRepetida(err) {
		httpx.Error(w, r, http.StatusConflict,
			fmt.Sprintf("Ya hay una columna «%s» en este tablero", strings.TrimSpace(c.Nombre.Con(""))))
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisarCambioDelTablero(r.Context(), deLaFila(fila.BranchID))
	httpx.JSON(w, r, http.StatusOK, deColumnaPelada(fila))
}

type cuerpoOrden struct {
	Ids []string `json:"ids"`
}

// putColumna reparte el PUT: `/orden` reordena el tablero entero y cualquier otra cosa es
// un id de columna, que por PUT no se admite (se renombra por PATCH).
func (s *Servidor) putColumna(w http.ResponseWriter, r *http.Request) {
	if strings.EqualFold(r.PathValue("id"), "orden") {
		s.reordenarColumnas(w, r)
		return
	}
	w.Header().Set("Allow", "PATCH, DELETE, OPTIONS")
	httpx.Error(w, r, http.StatusMethodNotAllowed, httpx.MsgMetodoNoValido)
}

// PUT /api/board/columns/orden — el tablero entero de una vez.
//
// UNA SOLA SENTENCIA, no una por columna: el aparato que se queda sin señal a la mitad
// dejaría el tablero con dos «tercera» y ninguna «quinta». Aquí, o entran todas o no
// entra ninguna. Es también la razón de que la única de `posicion` sea DEFERRABLE: a
// mitad del baile hay posiciones repetidas y la comprobación tiene que esperar al final.
func (s *Servidor) reordenarColumnas(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	t, ok := s.tableroDe(w, r, a)
	if !ok {
		return
	}
	var c cuerpoOrden
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	ids := make([]uuid.UUID, 0, len(c.Ids))
	for _, crudo := range c.Ids {
		id, err := uuid.Parse(strings.TrimSpace(crudo))
		if err != nil {
			httpx.Error(w, r, http.StatusBadRequest,
				fmt.Sprintf("«%s» no es el id de una columna", crudo))
			return
		}
		ids = append(ids, id)
	}
	if len(ids) == 0 {
		httpx.Error(w, r, http.StatusBadRequest, "No vino ninguna columna que reordenar")
		return
	}

	n, err := a.ReordenarColumnas(r.Context(), t.sucursal, ids)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// Se devuelve el tablero recolocado y no un `{"ok":true}`: quien reordena quiere ver
	// el resultado, y si alguno de los ids no era de este tablero (`n` < los mandados)
	// la lista de vuelta lo enseña sin tener que pedirla otra vez.
	columnas, err := a.ListarColumnasDelTablero(r.Context(), t.sucursal)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// `t.sucursal` y no el alcance: es el tablero que se acaba de reordenar, y el propio
	// SQL sólo movió columnas de ESA sucursal (`ReordenarColumnas` filtra por `branch_id`),
	// así que no hay otra que pueda haber cambiado.
	avisarCambioDelTablero(r.Context(), deLaFila(t.sucursal))
	httpx.JSON(w, r, http.StatusOK, map[string]any{
		"reordenadas": n,
		"columnas":    deColumnas(columnas),
	})
}

// DELETE /api/board/columns/{id} — con `?vaciar=1`, con `?destino=<id>`, o 409.
//
// LA BASE SE NIEGA A BORRAR UNA COLUMNA CON PEDIDOS DENTRO (`ON DELETE RESTRICT`), y eso
// no se toca. Con CASCADE, las tarjetas volverían a «sin colocar» sin decir nada y quien
// borró «Centro» creyéndola vacía se entera al día siguiente, cuando a la ruta le faltan
// ocho paradas.
//
// Lo que hace este manejador es PREGUNTAR ANTES para poder decir «tiene 8 pedidos
// puestos» en vez de devolverle a la persona el error de clave ajena de Postgres, que no
// entiende nadie. Y si aun así la base se niega —porque alguien colocó una tarjeta entre
// la cuenta y el borrado—, ese error también se traduce: nunca sale un 500.
func (s *Servidor) borrarColumna(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, msgZonaNoEsta)
	if !ok {
		return
	}
	q := r.URL.Query()
	vaciar := q.Get("vaciar") == "1" || q.Get("vaciar") == "true"
	var destino *uuid.UUID
	if crudo := strings.TrimSpace(q.Get("destino")); crudo != "" {
		d, err := uuid.Parse(crudo)
		if err != nil {
			httpx.Error(w, r, http.StatusBadRequest,
				fmt.Sprintf("«%s» no es el id de una columna", crudo))
			return
		}
		if d == id {
			httpx.Error(w, r, http.StatusBadRequest, "La columna de destino no puede ser la que se borra")
			return
		}
		destino = &d
	}

	columna, err := a.ObtenerColumna(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, msgZonaNoEsta)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	var dentro int64
	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		var err error
		dentro, err = tx.ContarPedidosEnColumna(r.Context(), id)
		if err != nil {
			return err
		}
		if dentro > 0 {
			switch {
			case destino != nil:
				// Las tarjetas se van DETRÁS de lo que ya haya en la otra columna y en
				// su mismo orden relativo: quien junta dos zonas no quiere que se le
				// mezclen las paradas. Y las dos columnas tienen que ser de la misma
				// sucursal, cosa que comprueba el propio SQL.
				movidos, err := tx.MoverPedidosDeColumna(r.Context(), id, *destino)
				if err != nil {
					return err
				}
				if movidos != dentro {
					return errDestinoNoVale
				}
			case vaciar:
				if _, err := tx.VaciarColumna(r.Context(), id); err != nil {
					return err
				}
			default:
				return errColumnaConPedidos
			}
		}
		filas, err := tx.BorrarColumna(r.Context(), id)
		if err != nil {
			return err
		}
		if filas == 0 {
			return errColumnaNoEstaba
		}
		return nil
	})

	switch {
	case errors.Is(err, errColumnaConPedidos), esRestriccionDeColumna(err):
		// El 409 del contrato, con el número dentro: sin él, la persona no sabe si lo
		// que tiene que hacer es vaciar dos tarjetas o mover ochenta.
		httpx.JSON(w, r, http.StatusConflict, map[string]any{
			"error":   fmt.Sprintf("«%s» tiene %d pedidos puestos", columna.Nombre, dentro),
			"pedidos": dentro,
		})
		return
	case errors.Is(err, errDestinoNoVale):
		httpx.Error(w, r, http.StatusConflict,
			"La columna de destino no existe o es de otra sucursal")
		return
	case errors.Is(err, errColumnaNoEstaba):
		httpx.Error(w, r, http.StatusNotFound, msgZonaNoEsta)
		return
	case err != nil:
		httpx.ErrorInterno(w, r, err)
		return
	}
	// DE LA COLUMNA QUE SE FUE. Se leyó arriba con `ObtenerColumna` —hace falta de todos
	// modos para poder decir ««Centro» tiene 8 pedidos puestos»—, así que la sucursal está
	// en la mano sin una consulta más, y eso es lo que importa aquí: cuando se avisa, la
	// fila ya no existe.
	avisarCambioDelTablero(r.Context(), deLaFila(columna.BranchID))
	httpx.JSON(w, r, http.StatusOK, map[string]any{"success": true, "movidos": dentro})
}

// Los cortes de la transacción del borrado. Van como errores y no como banderas porque
// tienen que DESHACER lo ya movido: un borrado que falla no puede dejar las tarjetas en
// la otra columna y la columna vieja en pie.
var (
	errColumnaConPedidos = errors.New("la columna tiene pedidos puestos")
	errColumnaNoEstaba   = errors.New("la columna no existe en este alcance")
	errDestinoNoVale     = errors.New("la columna de destino no sirve")
)

// esRestriccionDeColumna reconoce el 23503 de Postgres (foreign_key_violation), que es lo
// que devuelve el `ON DELETE RESTRICT` de `board_placements.column_id`.
//
// Se mira el CÓDIGO y no el texto, igual que en `esClaveRepetida`: el texto lo traduce el
// servidor según su idioma y una comprobación por texto deja de funcionar el día que la
// base se levante con otro locale, sin que nada falle al compilar.
func esRestriccionDeColumna(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23503"
}

// ---------------------------------------------------------------------------
// Arrastrar
// ---------------------------------------------------------------------------

type cuerpoColocar struct {
	ColumnaID string `json:"columnaId"`
	Posicion  *int32 `json:"posicion"`
}

// PUT /api/board/placements/{id} — colocar O mover. Es la MISMA orden: soltar una tarjeta
// en una columna es decir «este pedido va aquí», venga de donde venga.
//
// REAPLICABLE, y eso es un requisito y no una casualidad: el tablero se usa sin red y sus
// escrituras suben en lotes que se reintentan (`docs/sincronizacion.md`). Colocar dos
// veces el mismo pedido en el mismo sitio tiene que dar el mismo tablero, no dos tarjetas
// ni un error. Se consigue con tres pasos que se anulan entre sí:
//
//  1. se SACA de donde estuviera (si estaba) y se cierra el hueco que deja;
//  2. se abre hueco en la posición de destino;
//  3. se inserta.
//
// Repetido sobre el tablero que ya quedó, el paso 1 y el paso 2 se cancelan y el
// resultado es idéntico. Hacer sólo el paso 2 + 3 correría una posición a los vecinos en
// cada reintento; hacer sólo el 3 chocaría con la única de `(column_id, posicion)`.
//
// Los tres van en UNA transacción, que es también lo que deja que la única sea DEFERRABLE:
// a mitad del corrimiento hay dos filas con la misma posición.
func (s *Servidor) colocarPedido(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	pedido, ok := idDeRuta(w, r, msgPedidoNoEsta)
	if !ok {
		return
	}
	var c cuerpoColocar
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	columna, err := uuid.Parse(strings.TrimSpace(c.ColumnaID))
	if err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "Falta la columna donde se suelta la tarjeta")
		return
	}
	posicion := int32(1)
	if c.Posicion != nil && *c.Posicion > 0 {
		posicion = *c.Posicion
	}
	// No asociar una factura al tablero mientras no esté cotejada y con el domicilio
	// cotizado. Se comprueba antes de mover la tarjeta para que el rechazo no deje el
	// pedido fuera de su columna anterior. La segunda validación de elegibilidad ocurre
	// al crear la ruta, porque la factura puede cambiar después de colocarse.
	pedidoActual, err := a.TableroObtenerPedido(r.Context(), pedido)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, msgPedidoNoEsta)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if pedidoActual.FacturaEstado == nil || (*pedidoActual.FacturaEstado != sqlc.FacturaEstadoIgual && *pedidoActual.FacturaEstado != sqlc.FacturaEstadoCambiado) {
		httpx.Error(w, r, http.StatusConflict,
			"No se puede asociar al tablero: primero coteja la factura del pedido.")
		return
	}
	if pedidoActual.FacturaDomicilio == nil || *pedidoActual.FacturaDomicilio <= 0 {
		httpx.Error(w, r, http.StatusConflict,
			"No se puede asociar al tablero: la factura no tiene un cobro de domicilio registrado.")
		return
	}
	if pedidoActual.PedidoCosto == nil {
		httpx.Error(w, r, http.StatusConflict,
			"No se puede asociar al tablero: primero cotiza el domicilio del pedido.")
		return
	}

	var puesto sqlc.ColocarPedidoRow
	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		// 1. De donde estuviera. `pgx.ErrNoRows` aquí es lo NORMAL: el pedido venía de
		//    la mitad izquierda y no estaba puesto en ninguna parte.
		anterior, err := tx.QuitarPedidoDelTablero(r.Context(), pedido)
		switch {
		case err == nil:
			if _, err := tx.CerrarHuecoEnColumna(r.Context(), anterior.ColumnID, anterior.Posicion); err != nil {
				return err
			}
		case errors.Is(err, pgx.ErrNoRows):
		default:
			return err
		}

		// 2. Sitio en la de destino.
		if _, err := tx.AbrirHuecoEnColumna(r.Context(), columna, posicion); err != nil {
			return err
		}

		// 3. Y dentro. El `WHERE` de esta sentencia ES la validación —misma sucursal,
		//    sin ruta, dentro del alcance—, y va en el mismo instante en que escribe.
		puesto, err = tx.ColocarPedido(r.Context(), sqlc.ColocarPedidoParams{
			Posicion: posicion, PedidoID: pedido, ColumnaID: columna,
		})
		return err
	})

	if errors.Is(err, pgx.ErrNoRows) {
		s.porQueNoSePudoColocar(w, r, a, pedido)
		return
	}
	// EL CHOQUE DE POSICIÓN ES UN 409 REINTENTABLE, NO UN 500.
	//
	// La única de `(column_id, posicion)` es `DEFERRABLE INITIALLY DEFERRED`, así que dos
	// colocaciones a la vez no chocan al escribir: chocan EN EL COMMIT, y el error sale
	// por `EnTx`, no por `ColocarPedido`. Aquí sólo se traducía `pgx.ErrNoRows`, de modo
	// que ese 23505 caía en `httpx.ErrorInterno` y la respuesta era «Error interno» con un
	// 500 dentro.
	//
	// Y un 500 aquí no es un detalle: el tablero se usa sin red y sus escrituras suben en
	// LOTES que se reintentan. Un 500 corta el lote entero; un 409 con este texto dice lo
	// único que hay que hacer, que es volver a mandarlo. Es la misma traducción que ya hace
	// `crearColumna` con `board_columns_posicion_unica`, y por la misma razón: las colas se
	// vacían de golpe cuando vuelve la señal, así que dos aparatos soltando tarjeta en la
	// misma posición a la vez pasa más cuanto peor esté la conexión.
	if esEstaClaveRepetida(err, "board_placements_posicion_unica") {
		httpx.Error(w, r, http.StatusConflict,
			"Otro aparato puso una tarjeta en ese mismo sitio en el mismo momento. "+
				"Vuelve a intentarlo.")
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// LA SUCURSAL VIENE DENTRO DE LA TARJETA COLOCADA. `board_placements` no tiene
	// `branch_id` —cuelga de la columna—, así que `ColocarPedido` devuelve el de
	// `board_columns` en la MISMA sentencia que escribe (ver su SQL): una lectura aparte
	// sería una segunda versión de los hechos.
	avisarCambioDelTablero(r.Context(), deLaFila(puesto.BranchID))
	httpx.JSON(w, r, http.StatusOK, map[string]any{
		"pedidoId":   puesto.OrderID,
		"columnaId":  puesto.ColumnID,
		"posicion":   puesto.Posicion,
		"colocadoAt": hora(puesto.ColocadoAt),
	})
}

// paramsDelContador pasa los filtros de la lista al contador, campo por campo.
//
// EXISTE PARA PODER PROBARLA. Esto estaba escrito a mano dentro del manejador, y
// ahí no había forma de que nada vigilara que no se olvidara un campo: el
// auditor quitó `Municipio:` el 17/09/2026 y `go build && go vet && go test ./...`
// de `api/` entero quedó **en verde**. Con el filtro de municipio puesto, la
// lista enseñaría un municipio y el número contaría la sucursal entera — que es
// exactamente el «Sin colocar (722) encima de una lista de 293» que costó tres
// días, en el fichero de al lado.
//
// `contador_y_lista_test.go` compara los dos `WHERE` y los dos `FROM`, pero eso
// es el SQL: lo que Go le pasa no lo miraba nadie. Ahora lo mira
// `params_del_contador_test.go`, campo por campo y por reflexión, así que un
// campo NUEVO en la consulta también entra sin que haya que acordarse.
//
// Los tres `Desde…` se dejan a cero A PROPÓSITO y no por olvido: el número de
// arriba es el TOTAL —«Sin colocar (300)»— y no puede bajar a 100 porque alguien
// haya pedido la tanda siguiente. La prueba conoce esa excepción por su nombre.
func paramsDelContador(arg sqlc.ListarPedidosSinColocarParams) sqlc.ContarPedidosSinColocarParams {
	return sqlc.ContarPedidosSinColocarParams{
		BranchID:  arg.BranchID,
		Sucursal:  arg.Sucursal,
		Q:         arg.Q,
		Municipio: arg.Municipio,
		Vendedor:  arg.Vendedor,
		DiaDesde:  arg.DiaDesde,
		DiaHasta:  arg.DiaHasta,
		KmMax:     arg.KmMax,
		OrigenLat: arg.OrigenLat,
		OrigenLng: arg.OrigenLng,
	}
}

// porQueNoSePudoColocar traduce el «cero filas» del INSERT.
//
// Cero filas puede ser cuatro cosas —el pedido no existe, es de otra sucursal, la columna
// no es suya, o el pedido ya va en un camión— y las cuatro no se responden igual: que ya
// vaya en una ruta es un 409 que la persona puede arreglar; que sea de otra sucursal es
// un 404 y NO se dice que existe, porque decirlo ya es contar algo.
func (s *Servidor) porQueNoSePudoColocar(w http.ResponseWriter, r *http.Request, a *alcance.Acotado, pedido uuid.UUID) {
	p, err := a.TableroObtenerPedido(r.Context(), pedido)
	if err != nil {
		// Si no se puede leer —no existe, o es de otra sucursal—, 404 y punto.
		httpx.Error(w, r, http.StatusNotFound, msgPedidoNoEsta)
		return
	}
	// PRIMERO EL ENTREGADO Y DESPUÉS LA RUTA, y el orden es lo que importa aquí.
	//
	// Un entregado conserva su `route_id` mientras la ruta exista, así que mirando la
	// ruta primero los dos casos contestarían «ya está en una ruta» — verdad a medias y
	// consejo equivocado: ese pedido no está esperando a que se cierre nada, ya se
	// repartió. Y cuando la ruta se borra (`ON DELETE SET NULL` en la clave ajena,
	// `db/migrations/00001_init.sql:446`) el `route_id` desaparece y sólo quedan estas
	// dos columnas para saberlo.
	if p.DeliveredAt.Valid || (p.Resultado != nil && *p.Resultado == sqlc.StopResultEntregado) {
		httpx.Error(w, r, http.StatusConflict, msgYaSeEntrego)
		return
	}
	if p.RouteID.Valid {
		httpx.Error(w, r, http.StatusConflict, msgYaVaEnUnaRuta)
		return
	}
	if p.FacturaEstado == nil || (*p.FacturaEstado != sqlc.FacturaEstadoIgual && *p.FacturaEstado != sqlc.FacturaEstadoCambiado) {
		httpx.Error(w, r, http.StatusConflict,
			"No se puede asociar al tablero: primero coteja la factura del pedido.")
		return
	}
	if p.FacturaDomicilio == nil || *p.FacturaDomicilio <= 0 {
		httpx.Error(w, r, http.StatusConflict,
			"No se puede asociar al tablero: la factura no tiene un cobro de domicilio registrado.")
		return
	}
	if p.PedidoCosto == nil {
		httpx.Error(w, r, http.StatusConflict,
			"No se puede asociar al tablero: primero cotiza el domicilio del pedido.")
		return
	}
	// El pedido existe y está libre: entonces lo que no cuadra es la columna.
	httpx.Error(w, r, http.StatusNotFound, msgZonaNoEsta)
}

// DELETE /api/board/placements/{id} — de vuelta a «sin colocar», que es de donde salió.
//
// Reaplicable también: quitar dos veces lo que ya no está no es un error, es el mismo
// tablero. Un lote que se reintenta no puede empezar a fallar por eso.
func (s *Servidor) quitarPedidoDelTablero(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	pedido, ok := idDeRuta(w, r, msgPedidoNoEsta)
	if !ok {
		return
	}

	quitado := false
	// La sucursal de la tarjeta que se quitó, para el aviso. Se queda vacía cuando no había
	// nada que quitar —quitar dos veces lo que ya no está es reaplicable y no es un error—,
	// y entonces el aviso sale global, que es el lado seguro: el reintento de un lote no
	// puede dejar una pantalla vieja.
	var sucursalDeLaTarjeta string
	err := a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		fila, err := tx.QuitarPedidoDelTablero(r.Context(), pedido)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		quitado = true
		sucursalDeLaTarjeta = deLaFila(fila.BranchID)
		// Cerrar el hueco no es imprescindible —el orden se lee, no se cuenta— pero sin
		// ello las posiciones se van separando hasta que un día alguien lee «la parada
		// número 47» de una columna de nueve.
		_, err = tx.CerrarHuecoEnColumna(r.Context(), fila.ColumnID, fila.Posicion)
		return err
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisarCambioDelTablero(r.Context(), sucursalDeLaTarjeta)
	httpx.JSON(w, r, http.StatusOK, map[string]any{"success": true, "quitado": quitado})
}

// ---------------------------------------------------------------------------
// De una columna sale una ruta
// ---------------------------------------------------------------------------

type cuerpoArmar struct {
	Nombre     httpx.Opcional[string] `json:"nombre"`
	VehiculoID httpx.Opcional[string] `json:"vehiculoId"`
	// Optimizar reordena por cercanía (el greedy de siempre). Por defecto NO: el
	// logístico ya propuso un orden arrastrando y él conoce las calles de su distrito;
	// el vecino más próximo no. Lo que no puede pasar es que su orden se pierda sin que
	// nadie se lo diga.
	Optimizar httpx.Opcional[bool] `json:"optimizar"`

	// EL DÍA DE LA RUTA, y por qué lo manda el aparato y no lo pone el reloj de aquí.
	//
	// Las NUEVE rutas que había en producción el 28/09/2026 tenían `delivery_date` nulo,
	// las nueve, y por eso la ficha y la lista enseñaban una raya donde va el día. Jose:
	// «mira todos los — que hay en la ruta y esos datos debemos de tenerlo». Eran dos
	// agujeros a la vez: el asistente tenía el campo en «(opcional)» y nadie lo rellenaba,
	// y ESTE camino —el del tablero, que es por donde se arma de verdad— ni siquiera
	// mandaba nada. El aparato sí escribía el día en su base local, así que la ruta
	// nacía con fecha en el teléfono y la PERDÍA al subir, cuando la bajada la pisaba con
	// el nulo del servidor. Lo vio la prueba del móvil sin señal: «Planificada · 1.7 km ·
	// 28/9/2026» antes de sincronizar y «En curso · 1.7 km · —» después.
	//
	// Viene del aparato porque un apunte hecho sin señal llega HORAS después: la ruta se
	// armó el día que la armó el logístico, no el día en que el servidor se enteró. Es la
	// misma razón por la que viaja [cuerpoArmar.PedidoIds].
	//
	// Y si no viene —las APK ya instaladas no la mandan— se pone la de HOY en vez de
	// dejarla nula: una ruta siempre tiene día, y un hueco ahí no es «no se sabe», es un
	// dato que se perdió. Con las viejas se acerca, que es infinitamente mejor que la raya.
	FechaDeEntrega httpx.Opcional[string] `json:"deliveryDate"`

	// LOS PEDIDOS QUE EL APARATO DECIDIÓ QUE IBAN EN ESA RUTA. Opcional, y así tiene que
	// seguir: la aplicación lo manda **desde el 28/09/2026** (`app/lib/pantallas/tablero/
	// datos/repositorio.dart`, `armarRuta`), y hasta ese día no lo mandaba nadie aunque
	// esto llevara escrito desde el 18/09 por qué hace falta. Las APK instaladas antes de
	// esa versión siguen sin mandarlo, y si esto se volviera obligatorio dejarían de poder
	// armar rutas de golpe.
	//
	// POR QUÉ HACE FALTA, que es el fallo del 18/09/2026 y es grave:
	//
	// Sin esta lista, el servidor arma la ruta con LO QUE ÉL TENGA PUESTO EN ESA ZONA EN
	// EL INSTANTE EN QUE LE LLEGA EL APUNTE — y un apunte hecho sin señal llega horas
	// después. Si mientras tanto la web movió una tarjeta de esa zona:
	//
	//   · la ruta del servidor nace SIN ese pedido, aunque el repartidor ya lo entregó;
	//   · su resultado llega a `/routes/{id}/results` para una parada que no va en la
	//     ruta y se rechaza — una entrega de verdad que no se guarda;
	//   · y el pedido se queda suelto en el tablero, así que la web lo mete en otra ruta
	//     y sale un SEGUNDO camión con el mismo bulto.
	//
	// Con la lista, el servidor arma exactamente lo que el aparato decidió y DICE LA
	// DIFERENCIA: lo que el aparato eligió y ya no está, y lo que hay ahora en la zona y
	// el aparato no eligió. Ninguna de las dos cosas se calla.
	//
	// Se aceptan los dos nombres, `pedidoIds` (el del resto de este cuerpo, en castellano)
	// y `orderIds` (el de `POST /api/routes`), para que la pantalla pueda mandar el que ya
	// usa sin que haya que acertar cuál es. Manda el primero si vienen los dos.
	PedidoIds json.RawMessage `json:"pedidoIds"`
	OrderIds  json.RawMessage `json:"orderIds"`
}

// loQueEligioElAparato saca la lista de pedidos del cuerpo, si vino.
//
// El segundo valor es «vino la lista», que NO es lo mismo que «la lista tiene algo»: un
// `"pedidoIds": []` es un aparato diciendo que no eligió nada, y eso es un cuerpo mal
// formado, no una orden de armar con todo lo que haya. Confundir los dos es justo cómo se
// vuelve al fallo que esto arregla.
func loQueEligioElAparato(c cuerpoArmar) (map[uuid.UUID]bool, bool) {
	crudo := c.PedidoIds
	if len(crudo) == 0 {
		crudo = c.OrderIds
	}
	if len(crudo) == 0 || string(bytes.TrimSpace(crudo)) == "null" {
		return nil, false
	}
	elegidos := map[uuid.UUID]bool{}
	for _, id := range soloUuids(leerIdsDePedidos(crudo)) {
		elegidos[id] = true
	}
	return elegidos, true
}

// DescartadoSalida nombra a cada pedido que se cayó, POR QUÉ y QUÉ HACER. Una columna de
// doce que produce una ruta de nueve sin explicación es la manera más rápida de que el
// logístico deje de fiarse del tablero.
//
// `queHacer` no es un adorno. El 409 que esto sustituye decía «1 de los 2 pedidos ya están
// en otra ruta. Vuelve a elegirlos.» sobre una tarjeta cuyo pedido se había quedado SIN
// COORDENADAS: el motivo era falso, no se nombraba la tarjeta, y «vuelve a elegirlos» no
// arreglaba nada — volver a pulsar daba el mismo 409 para siempre. Un rechazo permanente
// que dice que se reintente es la peor forma de no dejar salir a nadie.
type DescartadoSalida struct {
	PedidoID        uuid.UUID `json:"pedidoId"`
	OperationNumber *string   `json:"operationNumber"`
	CustomerName    string    `json:"customerName"`
	Motivo          string    `json:"motivo"`
	QueHacer        string    `json:"queHacer"`
}

// POST /api/board/columns/{id}/route
func (s *Servidor) armarRutaDeColumna(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, msgZonaNoEsta)
	if !ok {
		return
	}
	var c cuerpoArmar
	if !httpx.LeerJSON(w, r, &c) {
		return
	}

	// El día de la ruta. Ver [cuerpoArmar.FechaDeEntrega]: si el aparato no la manda
	// —las APK viejas no lo hacen— se pone la de hoy, nunca nulo.
	entrega, ok := fechaDeEntrega(w, r, c.FechaDeEntrega.Con(""))
	if !ok {
		return
	}
	if !entrega.Valid {
		entrega = pgtype.Timestamptz{Time: time.Now(), Valid: true}
	}

	columna, err := a.ObtenerColumna(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, msgZonaNoEsta)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	suc, err := a.ObtenerSucursal(r.Context(), columna.BranchID)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	almacen, ok := s.almacenDe(w, r, suc)
	if !ok {
		return
	}

	// ESTA CONSULTA ES LA VALIDACIÓN, no una lectura previa a ella. Si vuelven menos de
	// los que hay puestos, alguien se los llevó entre que se pintó el tablero y se pulsó
	// el botón —con el Super Admin y el armador de siempre por medio eso pasa de verdad—
	// y de ahí sale el 409.
	candidatos, err := a.PedidosDeColumnaParaArmarRuta(r.Context(), id)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// LO QUE LA CONSULTA DE ARRIBA DEJÓ FUERA, NOMBRADO UNO A UNO.
	//
	// Antes esto era una RESTA —`ContarPedidosEnColumna` menos los candidatos— y la
	// diferencia entera se le atribuía a «ya están en otra ruta». Era falso y no tenía
	// salida: `PedidosDeColumnaParaArmarRuta` descarta además `source <> 'pedido'` y los
	// pedidos SIN COORDENADAS, y eso último pasa de verdad — el upsert del espejo hace
	// `end_lat = excluded.end_lat` sin `coalesce` (`db/queries/orders.sql:718`), así que
	// una bajada puede dejar sin punto de entrega un pedido que ya estaba colocado.
	//
	// Ejecutado contra una columna de dos con una tarjeta así, la respuesta era:
	// `409 {"error":"1 de los 2 pedidos ya están en otra ruta. Vuelve a elegirlos."}`.
	// Permanente —volver a pulsar daba lo mismo—, con el motivo equivocado, sin decir cuál
	// de las dos era, y sin llegar nunca a `descartados`, que existe justo para esto.
	//
	// Ahora se leen las tarjetas puestas y se compara con los candidatos: los que faltan se
	// nombran con su motivo de verdad y la ruta se arma con el resto. Es la regla de la
	// casa —«los avisos del armador son aviso, no bloqueo»— y la otra —«nada se descarta en
	// silencio»— al mismo tiempo.
	//
	// La carrera de verdad sigue cubierta, y en el único sitio donde se puede cubrir: el
	// `EngancharPedidoARuta` de la transacción devuelve cero filas si alguien se llevó el
	// pedido entre medias, y de ahí sale `errSeLoLlevaron` con su «vuelve a intentarlo».
	puestas, err := a.ListarPedidosColocados(r.Context(), sqlc.ListarPedidosColocadosParams{
		OrigenLat: almacen.Lat, OrigenLng: almacen.Lng, BranchID: columna.BranchID,
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	esCandidato := make(map[uuid.UUID]bool, len(candidatos))
	for _, p := range candidatos {
		esCandidato[p.ID] = true
	}
	descartados := []DescartadoSalida{}
	for _, t := range puestas {
		if t.ColumnID != id || esCandidato[t.OrderID] {
			continue
		}
		motivo, queHacer := porQueNoEsCandidato(t)
		descartados = append(descartados, DescartadoSalida{
			PedidoID: t.OrderID, OperationNumber: t.OperationNumber,
			CustomerName: t.CustomerName, Motivo: motivo, QueHacer: queHacer,
		})
	}

	// LO QUE EL APARATO ELIGIÓ CONTRA LO QUE HAY AHORA EN LA ZONA.
	//
	// Sin la lista (las APK de hoy) esto no se ejecuta y todo sigue como estaba: se arma
	// con lo que haya puesto. Con la lista, la ruta lleva EXACTAMENTE lo que el aparato
	// decidió, y las dos diferencias posibles se nombran en vez de callarse:
	//
	//   · lo que él eligió y ya no está en la zona — se lo llevó otro, o alguien quitó la
	//     tarjeta entre que él armó sin señal y el apunte subió. ESE es el pedido que su
	//     repartidor puede haber entregado ya, así que hay que decirlo con su id.
	//   · lo que hay ahora en la zona y él NO eligió — llegó después. No sube a este
	//     camión: él no lo cargó. Se queda en la zona y se dice que se quedó.
	elegidos, hayEleccion := loQueEligioElAparato(c)
	if hayEleccion {
		if len(elegidos) == 0 {
			httpx.Error(w, r, http.StatusBadRequest, msgListaVacia)
			return
		}
		enLaZona := map[uuid.UUID]bool{}
		for _, t := range puestas {
			if t.ColumnID == id {
				enLaZona[t.OrderID] = true
			}
		}
		// Lo que eligió y ya NO está puesto en esta zona. Los que siguen puestos pero no
		// pueden ir ya los nombró el bucle de arriba con su motivo de verdad.
		// Ordenados: un mapa en Go se recorre al azar, y una respuesta que cambia de orden
		// entre dos llamadas iguales es imposible de leer en un registro y de comparar en
		// una prueba.
		faltan := make([]uuid.UUID, 0, len(elegidos))
		for ped := range elegidos {
			if !enLaZona[ped] {
				faltan = append(faltan, ped)
			}
		}
		sort.Slice(faltan, func(i, j int) bool { return faltan[i].String() < faltan[j].String() })
		for _, ped := range faltan {
			descartados = append(descartados, DescartadoSalida{
				PedidoID: ped,
				Motivo:   "ya no estaba en esa zona cuando llegó tu apunte",
				QueHacer: "Se movió o se quitó de la zona mientras tu aparato estaba sin " +
					"señal. NO ha subido a este camión: comprueba si se entregó igual y " +
					"míralo antes de que salga en otra ruta.",
			})
		}
		// Y lo que hay ahora y él no eligió: se queda, y se dice.
		for _, t := range puestas {
			if t.ColumnID != id || elegidos[t.OrderID] || !esCandidato[t.OrderID] {
				continue
			}
			descartados = append(descartados, DescartadoSalida{
				PedidoID: t.OrderID, OperationNumber: t.OperationNumber,
				CustomerName: t.CustomerName,
				Motivo:       "lo pusieron en la zona después de que armaras",
				QueHacer: "No iba en tu camión, así que no ha subido. Se queda en la zona: " +
					"arma otra vez si tiene que salir hoy.",
			})
		}
	}

	// El corte por factura se hace AQUÍ y no en el SQL, para poder nombrar cuál falla y
	// por qué. Un WHERE que los descartara en la consulta deja el mismo rechazo sin nada
	// que decir.
	var buenos []sqlc.PedidosDeColumnaParaArmarRutaRow
	for _, p := range candidatos {
		// Si el aparato dijo qué iba, lo que él no eligió NO sube: ya se nombró arriba.
		if hayEleccion && !elegidos[p.ID] {
			continue
		}
		motivo, queHacer := "", ""
		switch {
		// LO QUE YA SE ENTREGÓ NO VUELVE A SUBIR A UN CAMIÓN.
		//
		// Se corta AQUÍ y no en el `WHERE` de la consulta, igual que el corte por
		// factura y por lo mismo: la tarjeta se nombra con su motivo y la zona sale
		// igual con el resto. Y hace falta cortarlo: la consulta pide `route_id IS
		// NULL`, y un entregado se queda sin `route_id` en cuanto alguien borra la ruta
		// en la que viajó (`ON DELETE SET NULL`, `db/migrations/00001_init.sql:446`).
		// Sin esto, la zona de ayer vuelve a parir la ruta de ayer.
		case p.DeliveredAt.Valid || (p.Resultado != nil && *p.Resultado == sqlc.StopResultEntregado):
			motivo = "ya se entregó"
			queHacer = "Ese pedido ya se repartió. Quita la tarjeta de la zona: volver a " +
				"subirlo a un camión lo entregaría dos veces."
		case p.Archivado:
			motivo = "archivado en PEDIDO"
			queHacer = "PEDIDO le dio de baja. Quita la tarjeta de la zona."
		case p.FacturaEstado == nil:
			// NULL NO ES «cuadra». Con un NULL colado se armó una ruta sin facturar el
			// 2/09; por eso se nombra distinto de `sin_factura`.
			motivo = "sin cotejar"
			queHacer = "Nadie ha cotejado su factura todavía. Se cotea y vuelve a armar."
		case *p.FacturaEstado == sqlc.FacturaEstadoSinFactura:
			motivo = "sin factura"
			queHacer = "No tiene factura. Se le hace en PEDIDO y vuelve a armar."
		case *p.FacturaEstado == sqlc.FacturaEstadoCambiado:
			motivo = "cambió en la factura"
			queHacer = "La factura ya no es la que era: repásala antes de cargar."
		case p.FacturaDomicilio == nil || *p.FacturaDomicilio <= 0:
			motivo = "la factura no tiene domicilio cobrado"
			queHacer = "Corrige o coteja la factura para registrar el cobro del domicilio antes de crear la ruta."
		case p.PedidoCosto == nil:
			motivo = "domicilio sin cotizar"
			queHacer = "Cotiza el domicilio del pedido antes de crear la ruta."
		}
		if motivo == "" {
			buenos = append(buenos, p)
			continue
		}
		descartados = append(descartados, DescartadoSalida{
			PedidoID: p.ID, OperationNumber: p.OperationNumber,
			CustomerName: p.CustomerName, Motivo: motivo, QueHacer: queHacer,
		})
	}
	if len(buenos) == 0 {
		// No se crea una ruta vacía, y se dice por qué se cayó cada uno.
		httpx.JSON(w, r, http.StatusConflict, map[string]any{
			"error":       msgColumnaSinNada,
			"descartados": descartados,
		})
		return
	}

	// El camión: el que venga en el cuerpo, si no el PREVISTO de la columna.
	vehiculo := columna.VehicleID
	if c.VehiculoID.Presente {
		v, ok := vehiculoDelCuerpo(w, r, a, c.VehiculoID)
		if !ok {
			return
		}
		vehiculo = v
	}
	// Y TIENE QUE HABER UNO. Ver [msgZonaSinCamion]: hasta el 28/09/2026 aquí decía «puede
	// no haber ninguno; la ruta se arma igual y el camión se elige después», y así nació
	// `RT-20260928-001` sin vehículo.
	//
	// SE MIRA `vehiculo` Y NO `columna.VehicleID`, que es la diferencia que importa: un
	// aparato que manda `vehiculoId` en el cuerpo tiene camión aunque su zona no lo tenga
	// —es lo que hace una APK que armó con la zona ya elegida—, y negárselo sería negar
	// una ruta que sí tiene camión.
	//
	// EL ORDEN es el mismo que el del aparato (`app/lib/pantallas/tablero/datos/
	// repositorio.dart`, `armarRuta`): primero «la zona no tiene nada repartible», luego el
	// camión, luego la capacidad. Si dos fallan a la vez, la persona lee el mismo mensaje
	// por los dos caminos.
	//
	// 400 y no 409: no es una carrera ni algo que cambie al reintentar, es un dato que
	// falta. Y con motivo legible, porque este 400 lo va a leer una persona dos veces: en
	// la pantalla cuando arma con conexión, y en la bandeja de rechazos cuando el apunte de
	// una APK sin señal suba horas después (`sync/internal/reparto/reparto.go`: un 4xx es
	// rechazo de negocio, no se reintenta y se queda a la vista con su motivo).
	if !vehiculo.Valid {
		httpx.Error(w, r, http.StatusBadRequest, msgZonaSinCamion)
		return
	}

	// El orden de visita. Por defecto se RESPETA el del logístico —ya vienen ordenados
	// por `p.posicion`—; el greedy sólo si lo pide.
	if c.Optimizar.Con(false) {
		buenos = porCercania(buenos, almacen.Lat, almacen.Lng)
	}

	pesoTotal := 0.0
	costoTotal := 0.0
	for _, p := range buenos {
		pesoTotal += p.Weight
		if p.PedidoCosto != nil {
			costoTotal += *p.PedidoCosto
		}
	}

	// La capacidad se comprueba AL ARMAR, que es donde importa. En el tablero el exceso
	// sólo avisa (§7.3): el tablero es un borrador y el camión previsto es una intención.
	// Aquí ya no: lo que no cabe, no sube.
	// `vehiculo.Valid` es SIEMPRE cierto desde la guarda de arriba, y este `if` se queda a
	// propósito: si algún día el camión vuelve a ser opcional por algún camino, la
	// comprobación de capacidad no puede empezar a pedirle la fila a un uuid vacío.
	if vehiculo.Valid {
		v, err := a.TableroVehiculoParaCapacidad(r.Context(), uuid.UUID(vehiculo.Bytes))
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			httpx.ErrorInterno(w, r, err)
			return
		}
		// EL SEGUNDO CIERRE DEL CAMIÓN. Esta consulta va SIN alcance —no lo admite— y por
		// eso devuelve `branch_id`: es aquí donde se coteja. El camión de la ruta tiene
		// que ser de la sucursal de la columna, o no tener ninguna (compartido).
		//
		// El primer cierre es `vehiculoDelCuerpo`, que ya lo resuelve con alcance. Éste
		// cubre lo que aquél no ve: el camión PREVISTO que quedó guardado en la columna
		// antes del 18/09/2026, cuando el `PATCH` aceptaba cualquier uuid. Sin él, esas
		// columnas seguirían pariendo rutas con el camión de otra sucursal dentro.
		if err == nil && v.BranchID.Valid && uuid.UUID(v.BranchID.Bytes) != columna.BranchID {
			httpx.Error(w, r, http.StatusBadRequest,
				fmt.Sprintf("No existe el vehículo '%s'", uuid.UUID(vehiculo.Bytes)))
			return
		}
		if err == nil && v.Capacity > 0 && pesoTotal > v.Capacity {
			httpx.Error(w, r, http.StatusBadRequest,
				fmt.Sprintf("Peso total (%.1f kg) supera la capacidad del vehículo (%g kg)", pesoTotal, v.Capacity))
			return
		}
	}

	codigo, err := s.codigoDeRuta(r, a)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	nombre := strings.TrimSpace(c.Nombre.Con(columna.Nombre))

	var ruta sqlc.CrearRutaRow
	var enganchados int64
	distancia := 0.0
	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		var err error
		ruta, err = tx.TableroCrearRuta(r.Context(), sqlc.CrearRutaParams{
			Name:          &nombre,
			RouteCode:     &codigo,
			OriginAddress: aTexto(almacen.Nombre),
			OriginLat:     &almacen.Lat,
			OriginLng:     &almacen.Lng,
			VehicleID:     vehiculo,
			BranchID:      pgDe(columna.BranchID),
			DeliveryDate:  entrega,
		})
		if err != nil {
			return err
		}

		anteriorLat, anteriorLng := almacen.Lat, almacen.Lng
		for i, p := range buenos {
			orden := int32(i + 1)
			// `segment_km` es la distancia RADIAL desde el origen y no la del tramo: se
			// hereda así de delivery porque es el número con el que se repartió la carga
			// hasta hoy. Cambiarlo aquí descuadraría los informes viejos.
			radial := kmHaversine(almacen.Lat, almacen.Lng, coord(p.EndLat), coord(p.EndLng))
			n, err := tx.TableroEngancharPedidoARuta(r.Context(), sqlc.EngancharPedidoARutaParams{
				RutaID:    pgDe(ruta.ID),
				StopOrder: &orden,
				SegmentKm: &radial,
				PedidoID:  p.ID,
			})
			if err != nil {
				return err
			}
			if n == 0 {
				// Se lo llevaron entre la validación y el enganche. Se deshace todo: una
				// ruta a la que le falta una parada es peor que ninguna ruta.
				return errSeLoLlevaron
			}
			enganchados += n
			distancia += kmHaversine(anteriorLat, anteriorLng, coord(p.EndLat), coord(p.EndLng))
			anteriorLat, anteriorLng = coord(p.EndLat), coord(p.EndLng)
		}
		// El CIRCUITO CERRADO: los tramos más el regreso al origen. El camión vuelve, y
		// no contar la vuelta subestima el viaje justo a la mitad de las rutas largas.
		distancia += kmHaversine(anteriorLat, anteriorLng, almacen.Lat, almacen.Lng)

		// QUIEN ORDENÓ LAS PARADAS, dicho de verdad.
		//
		// Aquí el orden por defecto es **el del logístico** (§5.4 de `tablero.md`): se
		// reordena por cercanía sólo si lo pide. Pero esta llamada no mandaba el campo,
		// y sin él el SQL deja `optimized` en `true` — o sea que la ruta quedaba firmada
		// como «la ordenó la máquina» aunque el orden lo hubiera puesto una persona a
		// mano, arrastrando tarjetas. Quien lo lea después no tiene forma de saberlo.
		optimizado := c.Optimizar.Con(false)
		//
		// El peso y el importe ya NO se mandan desde aquí (29/09/2026): los escriben los
		// `TableroEngancharPedidoARuta` de arriba, en esta misma transacción, porque una
		// parada que entra dispara el recálculo del espejo de su ruta
		// (`db/migrations/00014_los_totales_de_la_ruta_no_se_congelan.sql`). De paso se
		// arregla lo que este armador nunca llegó a calcular: `paradas_sin_cotizar`, que
		// salía NULL en toda ruta armada desde el tablero y dejaba su importe pareciendo
		// completo.
		if _, err := tx.TableroFijarTotalesDeRuta(r.Context(), sqlc.FijarTotalesDeRutaParams{
			TotalDistance: distancia,
			ID:            ruta.ID, Optimizado: &optimizado,
		}); err != nil {
			return err
		}

		// Y las tarjetas de esa columna se vacían, EN LA MISMA TRANSACCIÓN. La columna se
		// queda: el distrito sigue existiendo mañana. Lo que se vacía es lo que llevaba
		// dentro hoy.
		_, err = tx.QuitarDelTableroLosDeRuta(r.Context(), ruta.ID)
		return err
	})
	if errors.Is(err, errSeLoLlevaron) {
		httpx.Error(w, r, http.StatusConflict,
			"Uno de los pedidos se subió a otra ruta mientras se armaba ésta. Vuelve a intentarlo.")
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	// Armar la ruta VACÍA la zona: los pedidos pasan a la ruta y dejan de estar en el
	// tablero. Es el cambio más grande que hay aquí, y el que más falta hace que vea la
	// otra persona — quien esté mirando el tablero desde el navegador tiene que enterarse
	// de que esas doce tarjetas ya salieron, no seguir arrastrándolas.
	//
	// Y AVISA DE LAS DOS PANTALLAS, porque las dos cambian.
	//
	// Aquí decía «avisa del TABLERO además de las rutas, que ya lo hace el armador» y era
	// FALSO: el armador que lo hace es el de `rutas.go` (`POST /api/routes`), y éste es
	// otro —el de la columna— escrito entero en este fichero. Por esta puerta nace una ruta
	// de verdad, con su código y sus paradas, y por aquí no salía ni un aviso de `rutas`:
	// la pantalla de Rutas no se enteraba de que existía.
	//
	// Que hoy se tapara solo no lo arregla, lo esconde: el vigía del aparato dispara un
	// ciclo con CUALQUIER aviso, así que el de `tablero` acababa trayendo también las rutas.
	// Eso deja de ser verdad en cuanto el aviso se afine —que es justo lo que pide el plan,
	// «por tablero no puede actualizarse cada vez que se haga algo en rutas»— y entonces
	// esta pantalla se queda vieja sin que nadie sepa por qué.
	//
	// Y LAS DOS CON LA SUCURSAL DE LA COLUMNA, que es la misma con la que nació la ruta
	// (`CrearRutaParams{… BranchID: pgDe(columna.BranchID)}`, aquí arriba): la zona y la
	// ruta que sale de ella son de la misma sucursal por construcción.
	avisarCambioDeRutas(r.Context(), deLaFila(columna.BranchID))
	avisarCambioDelTablero(r.Context(), deLaFila(columna.BranchID))

	httpx.JSON(w, r, http.StatusCreated, map[string]any{
		"id":          ruta.ID,
		"routeCode":   ruta.RouteCode,
		"name":        ruta.Name,
		"status":      string(ruta.Status),
		"branchId":    columna.BranchID,
		"columnaId":   columna.ID,
		"paradas":     enganchados,
		"totalWeight": pesoTotal,
		"totalPrice":  costoTotal,
		"distanciaKm": distancia,
		"origen":      almacen,
		// Quién se cayó y por qué, siempre, aunque esté vacío: la pantalla tiene que
		// poder decir «de doce salieron nueve, y éstos tres son los que faltan».
		"descartados": descartados,
	})
}

var errSeLoLlevaron = errors.New("un pedido se subió a otra ruta mientras se armaba")

// porQueNoEsCandidato traduce cada condición del `WHERE` de `PedidosDeColumnaParaArmarRuta`
// a algo que una persona pueda leer y hacer.
//
// LOS TRES MOTIVOS SON DISTINTOS Y SE ARREGLAN DE TRES MANERAS, y por eso no se juntan en
// un número. Meterlos todos en «ya están en otra ruta» es lo que dejaba al logístico
// pulsando un botón que nunca iba a funcionar.
//
// El orden importa: se mira primero la ruta, porque un pedido que ya salió puede además
// haberse quedado sin coordenadas, y lo que hay que contarle a quien mira la pantalla es
// que el camión ya se lo llevó.
func porQueNoEsCandidato(t sqlc.ListarPedidosColocadosRow) (motivo, queHacer string) {
	switch {
	// EL ENTREGADO VA ANTES QUE LA RUTA. Un entregado conserva su `route_id`, así que
	// mirando la ruta primero se le contaría al logístico que «otro lo subió a un
	// camión» — y lo que pasó es que ese pedido YA SE REPARTIÓ, en el camión de ayer o
	// en el de esta mañana. Lo que hay que hacer es distinto y no se puede adivinar.
	case t.Resultado != nil && *t.Resultado == sqlc.StopResultEntregado:
		return "ya se entregó",
			"Ese pedido ya se repartió. Quita la tarjeta de la zona: volver a subirlo " +
				"a un camión lo entregaría dos veces."
	case t.RouteID.Valid:
		return "ya va en otra ruta",
			"Otro lo subió a un camión. Quita la tarjeta de la zona."
	case t.EndLat == nil || t.EndLng == nil:
		// PASA DE VERDAD, y es la que estaba escondida detrás del 409 mentiroso: el
		// upsert del espejo escribe `end_lat = excluded.end_lat` sin `coalesce`, así que
		// una bajada de PEDIDO puede dejar sin punto de entrega un pedido ya colocado.
		return "sin coordenadas de entrega",
			"Se quedó sin punto de entrega. Hay que ponérselo en PEDIDO; con la bajada " +
				"siguiente vuelve a poder ir en una ruta."
	case t.Source == nil || *t.Source != sqlc.ProcedenciaPedido:
		return "no vino de PEDIDO",
			"Sólo se arman rutas con pedidos de PEDIDO. Quita la tarjeta de la zona."
	}
	// No debería llegar aquí: las de arriba son todas las condiciones de la consulta. Si
	// llega, se dice que no se sabe en vez de inventar un motivo — un motivo equivocado es
	// peor que ninguno, que es exactamente lo que pasó con el 409 de «otra ruta».
	return "ya no se puede meter en una ruta",
		"Cambió mientras se armaba. Vuelve a abrir el tablero para ver cómo está."
}

// codigoDeRuta arma el `RT-YYYYMMDD-NNN`.
//
// OJO: no es atómico, y se hereda así. Dos armados a la vez leen el mismo número y salen
// con el mismo código; delivery tenía la misma carrera. Se mantiene para no cambiar el
// formato, que es lo que la gente se dice por teléfono. Si empieza a chocar, la salida es
// una secuencia por día, no un reintento.
func (s *Servidor) codigoDeRuta(r *http.Request, a *alcance.Acotado) (string, error) {
	prefijo := "RT-" + time.Now().Format("20060102")
	n, err := a.TableroContarRutasDelDia(r.Context(), prefijo)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%s-%03d", prefijo, n+1), nil
}

// ---------------------------------------------------------------------------
// Ayudas
// ---------------------------------------------------------------------------

func deColumnas(filas []sqlc.ListarColumnasDelTableroRow) []ColumnaSalida {
	salida := make([]ColumnaSalida, 0, len(filas))
	for _, f := range filas {
		salida = append(salida, ColumnaSalida{
			ID: f.ID, BranchID: f.BranchID, Nombre: f.Nombre, Posicion: f.Posicion,
			VehicleID:         idOpcional(f.VehicleID),
			VehiculoNombre:    f.VehiculoNombre,
			VehiculoMatricula: f.VehiculoMatricula,
			VehiculoCapacidad: f.VehiculoCapacidad,
			Pedidos:           f.Pedidos, PesoKg: f.PesoKg, CostoUsd: f.CostoUsd,
			ExcedeCamion: f.ExcedeCamion,
			CreatedAt:    hora(f.CreatedAt), UpdatedAt: hora(f.UpdatedAt),
		})
	}
	return salida
}

// deColumnaPelada es la columna recién creada o recién tocada, sin totales: no los tiene
// todavía, y devolver ceros diría «esta columna está vacía» de una que puede no estarlo.
func deColumnaPelada(c sqlc.BoardColumn) ColumnaSalida {
	return ColumnaSalida{
		ID: c.ID, BranchID: c.BranchID, Nombre: c.Nombre, Posicion: c.Posicion,
		VehicleID: idOpcional(c.VehicleID),
		CreatedAt: hora(c.CreatedAt), UpdatedAt: hora(c.UpdatedAt),
	}
}

func deTarjetas(filas []sqlc.ListarPedidosColocadosRow) []TarjetaSalida {
	repes := map[string]int{}
	for _, f := range filas {
		repes[strings.ToLower(strings.TrimSpace(f.CustomerName))]++
	}
	salida := make([]TarjetaSalida, 0, len(filas))
	for _, f := range filas {
		salida = append(salida, TarjetaSalida{
			PedidoID: f.OrderID, ColumnaID: f.ColumnID, Posicion: f.Posicion,
			ColumnaNombre: f.ColumnaNombre, OperationNumber: f.OperationNumber,
			CustomerName: f.CustomerName, CustomerPhone: f.CustomerPhone,
			Address: f.Address, EndAddress: f.EndAddress, Weight: f.Weight,
			PedidoCosto: f.PedidoCosto, Municipio: f.Municipio, Vendedor: f.Vendedor,
			KmAlAlmacen:   f.KmAlAlmacen,
			FacturaEstado: facturaEstado(f.FacturaEstado),
			Archivado:     f.Archivado,
			RutaID:        idOpcional(f.RouteID),
			Resultado:     resultado(f.Resultado),
			ColocadoAt:    hora(f.ColocadoAt),
			MismoCliente:  repes[strings.ToLower(strings.TrimSpace(f.CustomerName))],
		})
	}
	return salida
}

// porCliente cuenta cuántas tarjetas tiene cada cliente en la lista. NO se funden: lo
// único que hace la pantalla es marcarlas para que el logístico las meta en la misma
// columna a propósito y no por casualidad.
func porCliente(filas []sqlc.ListarPedidosSinColocarRow) map[string]int {
	m := map[string]int{}
	for _, f := range filas {
		m[strings.ToLower(strings.TrimSpace(f.CustomerName))]++
	}
	return m
}

// porCercania ordena la columna por el camino que hará el camión.
//
// Era el greedy del vecino más próximo pelado, y por eso Jose lo vio y dijo lo que dijo el
// 21/09/2026: «esa planificada está mal, no hace ruta lógica ni nada». Tenía razón, y no
// era esta pantalla nada más: el greedy deja cruces y un último tramo larguísimo de vuelta
// al almacén. Ahora llama a `ordenDeVisita` —el mismo que arma la ruta, con 2-opt y
// Or-opt—, así que **la columna se ordena igual que se ordenará la ruta**. Si no, el
// logístico ve un orden en el tablero y otro distinto en la ruta creada, y no hay forma de
// saber cuál es el bueno.
//
// Sólo se aplica si lo piden: el orden por defecto sigue siendo el del logístico.
//
// LOS PEDIDOS SIN COORDENADAS SE QUEDAN AL FINAL, en su orden, y esto es un arreglo de
// paso: antes entraban al cálculo con `coord(nil) == 0`, o sea el golfo de Guinea, y
// arrastraban el orden de todos los demás hacia un punto que no existe. Un orden así se lee
// perfectamente bien y está mal, que es lo peor que le puede pasar a esta pantalla.
func porCercania(pedidos []sqlc.PedidosDeColumnaParaArmarRutaRow, lat, lng float64) []sqlc.PedidosDeColumnaParaArmarRutaRow {
	// Copia estable primero, para que dos llamadas con los mismos datos den lo mismo.
	quedan := append([]sqlc.PedidosDeColumnaParaArmarRutaRow(nil), pedidos...)
	sort.SliceStable(quedan, func(i, j int) bool { return quedan[i].Posicion < quedan[j].Posicion })

	porID := make(map[uuid.UUID]sqlc.PedidosDeColumnaParaArmarRutaRow, len(quedan))
	paradas := make([]paradaGeo, 0, len(quedan))
	sinSitio := make([]sqlc.PedidosDeColumnaParaArmarRutaRow, 0)
	for _, p := range quedan {
		if p.EndLat == nil || p.EndLng == nil {
			sinSitio = append(sinSitio, p)
			continue
		}
		porID[p.ID] = p
		paradas = append(paradas, paradaGeo{id: p.ID, lat: *p.EndLat, lng: *p.EndLng})
	}

	orden := make([]sqlc.PedidosDeColumnaParaArmarRutaRow, 0, len(quedan))
	for _, id := range ordenDeVisita(lat, lng, paradas) {
		orden = append(orden, porID[id])
	}
	return append(orden, sinSitio...)
}

func coord(v *float64) float64 {
	if v == nil {
		return 0
	}
	return *v
}

// vehiculoDelCuerpo traduce el `vehiculoId` del cuerpo. Vacío o null es «quítamelo»; un
// id que no es un uuid es un 400, porque aquí sí se sabe que el que escribe es el cliente.
//
// Y SE COMPRUEBA CON ALCANCE, igual que en `rutas.go` y por lo mismo: el camión de
// Holguín no se engancha a una zona de Santiago ni sabiendo su id. Hasta el 18/09/2026
// aquí sólo se miraba que fuese un uuid, y con eso un `PATCH /api/board/columns/{suya}`
// con el `vehiculoId` de otra sucursal contestaba 200 y se guardaba; después
// `ListarColumnasDelTablero` —que trae el camión por un `LEFT JOIN vehicles` SIN condición
// de sucursal— servía su nombre, su matrícula y su capacidad en cada `GET /api/board`, y
// al armar la ruta ese mismo id pisaba al de la columna y llegaba tal cual a `CrearRuta`.
// Es la regla 1 de la casa por la puerta de atrás: el alcance sale de quién pregunta.
//
// En producción hay ocho camiones, uno por sucursal, los ocho con `branch_id`: no hay
// camiones compartidos que disculpen un id ajeno. Los que no tienen sucursal —si algún día
// los hay— sí pasan, que para eso están, y eso lo decide el `WHERE` de `ObtenerVehiculo`.
//
// El mensaje es el mismo de `rutas.go` a propósito: «no existe» y «no es de tu sucursal»
// se contestan igual, porque distinguirlos ya es contar algo.
func vehiculoDelCuerpo(w http.ResponseWriter, r *http.Request, a *alcance.Acotado, v httpx.Opcional[string]) (pgtype.UUID, bool) {
	crudo := strings.TrimSpace(v.Con(""))
	if crudo == "" {
		return pgtype.UUID{}, true
	}
	id, err := uuid.Parse(crudo)
	if err != nil {
		httpx.Error(w, r, http.StatusBadRequest,
			fmt.Sprintf("«%s» no es el id de un vehículo", crudo))
		return pgtype.UUID{}, false
	}
	vehiculo, err := a.ObtenerVehiculo(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusBadRequest,
			fmt.Sprintf("No existe el vehículo '%s'", crudo))
		return pgtype.UUID{}, false
	} else if err != nil {
		httpx.ErrorInterno(w, r, err)
		return pgtype.UUID{}, false
	}
	if !vehiculo.IsActive {
		httpx.Error(w, r, http.StatusBadRequest, "El vehículo está inactivo y no se puede asignar a una ruta.")
		return pgtype.UUID{}, false
	}
	return pgDe(id), true
}

// diaDelPedido convierte `dia=2026-09-14` en el intervalo MEDIO ABIERTO del día, igual
// que en el armador. Medio abierto y no `<=` del último segundo: con `<=` se pierde lo
// que cae en el mismo segundo del corte, que con marcas de microsegundos pasa.
func diaDelPedido(crudo string) (pgtype.Timestamptz, pgtype.Timestamptz) {
	crudo = strings.TrimSpace(crudo)
	if crudo == "" {
		return pgtype.Timestamptz{}, pgtype.Timestamptz{}
	}
	d, err := time.Parse("2006-01-02", crudo)
	if err != nil {
		return pgtype.Timestamptz{}, pgtype.Timestamptz{}
	}
	return pgtype.Timestamptz{Time: d, Valid: true},
		pgtype.Timestamptz{Time: d.AddDate(0, 0, 1), Valid: true}
}

func textoOpcional(v string) *string {
	v = strings.TrimSpace(v)
	if v == "" {
		return nil
	}
	return &v
}

func numeroOpcional(v string) *float64 {
	v = strings.TrimSpace(v)
	if v == "" {
		return nil
	}
	n, err := strconv.ParseFloat(v, 64)
	if err != nil || n <= 0 {
		return nil
	}
	return &n
}

func facturaEstado(v *sqlc.FacturaEstado) *string {
	if v == nil {
		return nil
	}
	s := string(*v)
	return &s
}

func resultado(v *sqlc.StopResult) *string {
	if v == nil {
		return nil
	}
	s := string(*v)
	return &s
}
