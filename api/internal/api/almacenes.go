package api

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// avisarCambioDeAlmacenes publica «cambiaron los almacenes» para que las pantallas
// abiertas se enteren sin esperar al temporizador.
//
// Vacío por defecto y lo engancha el fichero del bus (`eventos.go`), igual que el de rutas
// y el del tablero. **No devuelve error y no se mira lo que conteste.**
//
// DESDE EL 20/10/2026 NADIE EN ESTE REPO LO LLAMA: Reparto ya no guarda almacenes (se
// editan en el CRM) y el `PUT /api/almacenes` que lo disparaba se quitó. SE QUEDA a
// propósito: el aviso del CRM (que se cablea en otro cambio) entrará por aquí y las
// pantallas se repintan con este evento. Las pruebas lo llaman directamente.
//
// Por qué hace falta repintar: la pantalla de Almacenes no vive de la base local, pide
// `GET /api/almacenes` a la red, y los almacenes NI SIQUIERA VIAJAN en `GET /api/sync/cambios`
// —salen en `faltan`— sino en una petición aparte al final del ciclo. Y no es cosmético: el
// domicilio se cobra por la distancia DESDE el almacén; dos personas mirando puntos
// distintos cobran precios distintos por la misma entrega.
//
// LOS ORÍGENES (`/api/origins`) NO AVISAN, y no es un olvido: ninguna pantalla de la
// aplicación los pide —se comprobó buscando `origins` en `app/lib` el 17/09/2026—. Son
// herencia del front de delivery. El día que una pantalla los enseñe, aquí va su aviso.
//
// LA SUCURSAL SE LA PASA QUIEN AVISA — 01/10/2026. Antes la sacaba el bus del alcance, y
// para un SUPER ADMIN eso es «de todas»: mover el punto del almacén de Santiago mandaba a las
// otras siete a pedir `GET /api/almacenes` por nada. Aquí la sucursal es la del uuid que se
// pasa, y solo a ésa le llega. El porqué entero, en `eventos.go` encima del `init()`.
var avisarCambioDeAlmacenes = func(_ context.Context, _ string) {}

// PUNTOS DE PARTIDA (/api/origins) y ALMACENES (/api/almacenes). Dos cosas parecidas que
// NO son la misma, y por eso están juntas aquí donde se ve la diferencia:
//
//   - Un ORIGEN es nuestro: desde dónde sale una ruta. Vive en esta base, en
//     `saved_origins`, y es de la sucursal donde está.
//   - Un ALMACÉN es de la sucursal y VIVE EN ACCESOS. Se edita en el CRM (decisión de Jose,
//     20/10/2026) y Reparto SOLO LO LEE —para cotizar, medir y armar rutas—. El domicilio se
//     cobra por la distancia desde el almacén, así que un punto mal puesto se cobra mal en
//     cada entrega. No se copia aquí. Una copia se separa del original en cuanto alguien mueve unas
//     coordenadas allá, y con esas coordenadas se mide lo que se le cobra al cliente.
//
// De esta base sale UNA sola cosa para los almacenes: qué códigos de sucursal puede ver
// quien pregunta. Accesos devuelve las ocho porque no sabe nada de nuestro alcance.

// ---------------------------------------------------------------------------
// Puntos de partida guardados
// ---------------------------------------------------------------------------

type OrigenSalida struct {
	ID        uuid.UUID          `json:"id"`
	Name      string             `json:"name"`
	Address   string             `json:"address"`
	Lat       float64            `json:"lat"`
	Lng       float64            `json:"lng"`
	CreadoPor *string            `json:"creadoPor"`
	BranchID  *uuid.UUID         `json:"branchId"`
	CreatedAt *time.Time         `json:"createdAt"`
	UpdatedAt *time.Time         `json:"updatedAt"`
	Branch    *SucursalDelOrigen `json:"branch"`
}

// SucursalDelOrigen es el `branch: { id, name }` del contrato. Va entero y no sólo el
// nombre porque la pantalla enlaza a la sucursal desde la lista de orígenes.
type SucursalDelOrigen struct {
	ID   uuid.UUID `json:"id"`
	Name string    `json:"name"`
}

func deOrigen(o sqlc.SavedOrigin) OrigenSalida {
	return OrigenSalida{
		ID: o.ID, Name: o.Name, Address: o.Address, Lat: o.Lat, Lng: o.Lng,
		CreadoPor: o.CreadoPor, BranchID: idOpcional(o.BranchID),
		CreatedAt: hora(o.CreatedAt), UpdatedAt: hora(o.UpdatedAt),
	}
}

// GET /api/origins
func (s *Servidor) listarOrigenes(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	// `branchId` de la query SÓLO se mira cuando no hay alcance (Super Admin). Quien lo
	// decide es `internal/alcance`; aquí sólo se lee. Un id mal escrito se trata como si
	// no viniera: filtrar por una sucursal inexistente daría cero orígenes con 200, que
	// desde fuera es idéntico a «esta sucursal no tiene ninguno».
	var pedida *uuid.UUID
	if v := strings.TrimSpace(r.URL.Query().Get("branchId")); v != "" {
		if id, err := uuid.Parse(v); err == nil {
			pedida = &id
		} else {
			httpx.Registro(r).Warn("branchId de /api/origins no es un uuid: se ignora", "branchId", v)
		}
	}

	filas, err := a.ListarOrigenes(r.Context(), pedida)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	salida := make([]OrigenSalida, 0, len(filas))
	for _, f := range filas {
		o := OrigenSalida{
			ID: f.ID, Name: f.Name, Address: f.Address, Lat: f.Lat, Lng: f.Lng,
			CreadoPor: f.CreadoPor, BranchID: idOpcional(f.BranchID),
			CreatedAt: hora(f.CreatedAt), UpdatedAt: hora(f.UpdatedAt),
		}
		if f.BranchID.Valid && f.SucursalNombre != nil {
			o.Branch = &SucursalDelOrigen{ID: uuid.UUID(f.BranchID.Bytes), Name: *f.SucursalNombre}
		}
		salida = append(salida, o)
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// cuerpoOrigen: `lat` y `lng` entran como `any` A PROPÓSITO.
//
// El contrato distingue dos errores con dos mensajes distintos: «faltan campos» y «lat y
// lng deben ser números». Con un `float64` pelado, un `"lat": "19.1"` reventaría el
// decodificador y saldría el 400 genérico del cuerpo no válido, perdiendo el literal que
// está inventariado.
type cuerpoOrigen struct {
	Name     httpx.Opcional[string] `json:"name"`
	Address  httpx.Opcional[string] `json:"address"`
	Lat      httpx.Opcional[any]    `json:"lat"`
	Lng      httpx.Opcional[any]    `json:"lng"`
	BranchID httpx.Opcional[string] `json:"branchId"`
}

// POST /api/origins
func (s *Servidor) crearOrigen(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	var c cuerpoOrigen
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	// Literales del contrato, y en este orden: primero qué falta, después qué no es un
	// número. Al revés, quien no manda `lat` leería «lat y lng deben ser números», que no
	// es lo que le pasa.
	nombre := strings.TrimSpace(c.Name.Con(""))
	direccion := strings.TrimSpace(c.Address.Con(""))
	if nombre == "" || direccion == "" || c.Lat.Valor == nil || c.Lng.Valor == nil {
		httpx.Error(w, r, http.StatusBadRequest, "Faltan campos requeridos: name, address, lat, lng")
		return
	}
	lat, bien := numeroJSON(*c.Lat.Valor)
	lng, tambien := numeroJSON(*c.Lng.Valor)
	if !bien || !tambien {
		httpx.Error(w, r, http.StatusBadRequest, "lat y lng deben ser números")
		return
	}

	// La sucursal la pone el ALCANCE, y sólo cuando no hay alcance se mira la del cuerpo.
	// Así nadie cuelga un origen en la sucursal de otro mandando su id en la petición: un
	// punto de partida suelto en la lista de Holguín es una ruta que empieza a 800 km de
	// donde debía.
	var destino *uuid.UUID
	if suya := a.Sucursal(); suya != nil {
		destino = suya
	} else if v := strings.TrimSpace(c.BranchID.Con("")); v != "" {
		id, err := uuid.Parse(v)
		if err != nil {
			httpx.Error(w, r, http.StatusForbidden, "Sucursal no válida")
			return
		}
		destino = &id
	}

	arg := sqlc.CrearOrigenParams{Name: nombre, Address: direccion, Lat: lat, Lng: lng}
	if destino != nil {
		// Que exista, y que sea una a la que se llega. `ObtenerSucursal` ya va acotada,
		// así que la de otro no aparece ni sabiendo su id.
		b, err := a.ObtenerSucursal(r.Context(), *destino)
		if errors.Is(err, pgx.ErrNoRows) {
			httpx.Error(w, r, http.StatusForbidden, "Sucursal no válida")
			return
		}
		if err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
		arg.BranchID = pgDe(b.ID)
	}

	creado, err := a.CrearOrigen(r.Context(), arg)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, http.StatusCreated, deOrigen(creado))
}

// PATCH /api/origins/{id}
//
// Corrige un punto de partida que ya está: mover el pin unos metros o arreglarle el
// nombre. Antes había que borrarlo y crearlo otra vez, y eso pierde quién lo puso.
func (s *Servidor) actualizarOrigen(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	var c cuerpoOrigen
	if !httpx.LeerJSON(w, r, &c) {
		return
	}

	arg := sqlc.ActualizarOrigenParams{ID: id}
	if c.Name.Presente && c.Name.Valor != nil {
		if n := strings.TrimSpace(*c.Name.Valor); n != "" {
			arg.Name = &n
		}
	}
	if c.Address.Presente && c.Address.Valor != nil {
		if d := strings.TrimSpace(*c.Address.Valor); d != "" {
			arg.Address = &d
		}
	}
	// Si mandan coordenadas, tienen que ser números. El mismo literal que el alta: es el
	// mismo error y verlo escrito de dos maneras distintas parece otra cosa.
	if c.Lat.Presente && c.Lat.Valor != nil {
		v, bien := numeroJSON(*c.Lat.Valor)
		if !bien {
			httpx.Error(w, r, http.StatusBadRequest, "lat y lng deben ser números")
			return
		}
		arg.Lat = &v
	}
	if c.Lng.Presente && c.Lng.Valor != nil {
		v, bien := numeroJSON(*c.Lng.Valor)
		if !bien {
			httpx.Error(w, r, http.StatusBadRequest, "lat y lng deben ser números")
			return
		}
		arg.Lng = &v
	}
	// La sucursal de un origen NO se cambia por aquí: sería la forma de plantar uno en la
	// sucursal de otro saltándose la comprobación del alta. Se avisa en el registro en
	// vez de tragárselo, que es como se descubre que un cliente lo sigue mandando.
	if c.BranchID.Presente {
		httpx.Registro(r).Warn("llegó branchId a PATCH /api/origins: la sucursal de un origen no se cambia; "+
			"para llevarlo a otra, bórralo y créalo allí", "origen", id, "actor", a.Actor())
	}

	o, err := a.ActualizarOrigen(r.Context(), arg)
	// Cero filas es o que no existe o que es de otra sucursal. Las dos son 404: decir
	// cuál de las dos sólo sirve para que alguien pruebe ids.
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, http.StatusOK, deOrigen(o))
}

// DELETE /api/origins/{id}
func (s *Servidor) borrarOrigen(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	filas, err := a.BorrarOrigen(r.Context(), id)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if filas == 0 {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	httpx.JSON(w, r, http.StatusOK, map[string]bool{"success": true})
}

// ---------------------------------------------------------------------------
// Almacenes (viven en Accesos)
// ---------------------------------------------------------------------------

// Almacen es lo que devuelve Accesos. `Latitud` y `Longitud` son punteros porque un
// almacén PUEDE no tenerlas —a veces se da de alta antes de tener el punto— y un 0 en su
// lugar es la costa de Guinea: desde ahí el domicilio de cualquier cliente sale a 8.000 km
// y el precio que se cobra es absurdo sin que nada falle.
type Almacen struct {
	ID *string `json:"id,omitempty"`
	// Codigo ES LA IDENTIDAD DEL ALMACÉN, junto con la sucursal — y no el nombre.
	//
	// Es el `objectCode` de Ventra, el mismo que PEDIDO manda dentro de cada pedido desde el
	// 26/09/2026. Sin él no se puede emparejar «el almacén del que sale este pedido» con «el
	// almacén que tiene las coordenadas», y entonces todo se mide desde el principal: en
	// Santiago, dos de cada tres pedidos salen de AURORA y se medían desde PV-STGO.
	//
	// POR QUÉ NO SE EMPAREJA POR NOMBRE, ni como respaldo. Comprobado en Ventra el
	// 26/09/2026: `Tiendas Parranda` existe en cinco sucursales con cinco ids, `Parranda
	// Oferta` en cuatro, y **`PV-STGO` está en Santiago Y en Palma Soriano**. Un respaldo por
	// nombre no falla nunca: sólo mide desde el almacén de otro sitio.
	//
	// ES OPCIONAL Y PUEDE LLEGAR VACÍO, y eso NO se trata como un error. Lo escribe el
	// CRM, no esta aplicación; mientras no lo haya puesto, `cotizar.ElegirOrigenDelPedido` lo dice con su propio
	// motivo —`accesos-sin-codigos`— en vez de acusar a catorce almacenes de no existir.
	Codigo    *string  `json:"codigo,omitempty"`
	Nombre    string   `json:"nombre"`
	Direccion *string  `json:"direccion"`
	Latitud   *float64 `json:"latitud"`
	Longitud  *float64 `json:"longitud"`
	Principal bool     `json:"principal"`
	Activo    bool     `json:"activo"`
}

// Y `activo` AUSENTE ES `true`, NO `false` — 24/09/2026.
//
// El contrato lo da por opcional (`activo?`, `docs/contratos-api.md`), Accesos lo guarda
// con `@default(true)` y al escribir lo rellena con `a.activo ?? true`, y el aparato lo lee
// igual: `activo: Value(a['activo'] != false)`, en `app/lib/nucleo/sincro/bajada.dart`. Un
// `bool` pelado de Go entiende lo contrario —ausente = `false`—, y desde que `activo` FILTRA
// (`cotizar.ElegirAlmacen`) eso sería el `409 «<Sucursal> no tiene ningún almacén con
// coordenadas»` en las ocho sucursales a la vez y con el teléfono funcionando, porque el
// teléfono lee el mismo JSON al revés. Es el `CLAUDE.md` §3-bis una capa más abajo: dos
// lados leyendo el mismo campo y entendiendo cosas distintas, sin que falle nada.
func (a *Almacen) UnmarshalJSON(crudo []byte) error {
	// `mismo` no hereda los métodos de `Almacen`, así que esto no se llama a sí mismo. Los
	// campos que el JSON no traiga se quedan con lo que valgan aquí.
	type mismo Almacen
	copia := mismo{Activo: true}
	if err := json.Unmarshal(crudo, &copia); err != nil {
		return err
	}
	*a = Almacen(copia)
	return nil
}

type SucursalConAlmacenes struct {
	Codigo    string    `json:"codigo"`
	Nombre    string    `json:"nombre"`
	Almacenes []Almacen `json:"almacenes"`
}

// GET /api/almacenes
func (s *Servidor) listarAlmacenes(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	// «A CUÁLES PUEDO LLEGAR», no «cuál estoy mirando». Son dos preguntas distintas y
	// confundirlas dejaba el Tablero en blanco acusando en falso (26/09/2026).
	//
	// Esto usaba `CodigosDeSucursalesVisibles`, que se acota por la sucursal del alcance
	// — y la del alcance, para quien ve las ocho, es **la de la cabecera
	// `X-Sucursal-Id`**, o sea la que tiene elegida arriba en ese momento. Así que a un
	// Super Admin mirando Camagüey esta ruta le devolvía SÓLO el almacén de Camagüey, y
	// el aparato, que reemplaza su copia entera con lo que llega, se quedaba con ese uno.
	//
	// Al cambiar a Holguín, el Tablero preguntaba por el almacén de `HOL`, no lo
	// encontraba —la copia tenía el de `CAM`— y ponía la pantalla en blanco con
	// «Holguín no tiene ningún almacén con coordenadas», que es mentira: lo tiene. Se
	// arreglaba solo al minuto, cuando el ciclo volvía a pedir esta ruta ya con la
	// cabecera nueva. Jose lo vio tres veces: «eso no puede pasar ok».
	//
	// `ListarSucursalesVisibles` se acota con `personaPg()` — la sucursal DE LA PERSONA,
	// ignorando la cabecera—, que es la misma lista con la que se pinta el desplegable de
	// arriba. Un logístico de Camagüey sigue viendo su almacén y nada más; quien ve las
	// ocho se lleva los ocho, que es lo que su aparato necesita para no mentir al cambiar.
	// La regla 1 de la casa se respeta igual: el alcance sale de quién pregunta.
	visibles, err := a.ListarSucursalesVisibles(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	permitidos := make(map[string]bool, len(visibles))
	for _, v := range visibles {
		if v.ExternalID != nil {
			permitidos[strings.TrimSpace(*v.ExternalID)] = true
		}
	}

	sucursales, err := s.accesos.Almacenes(r.Context())
	if err != nil {
		// 502 y no 500: el que no contesta es Accesos, no nosotros, y el mensaje lo dice
		// para que quien lo lea sepa dónde mirar. Literal del contrato.
		httpx.Error(w, r, http.StatusBadGateway,
			fmt.Sprintf("No se pudieron traer los almacenes de Accesos: %s", err))
		return
	}

	// Se filtra por lo que esta persona puede ver: el alcance es cosa nuestra, y Accesos
	// devuelve las ocho sucursales porque no sabe nada de él.
	salida := make([]SucursalConAlmacenes, 0, len(sucursales))
	for _, su := range sucursales {
		if permitidos[strings.TrimSpace(su.Codigo)] {
			salida = append(salida, su)
		}
	}
	httpx.JSON(w, r, http.StatusOK, map[string]any{"sucursales": salida})
}

// rutasAlmacenes monta los orígenes y los almacenes.
//
// Todo con `sesion`. Los almacenes aquí son SOLO LECTURA (`GET /api/almacenes`): el
// `PUT` se eliminó el 20/10/2026 porque se editan en el CRM, y una prueba fija que la ruta
// ya no existe. El alcance ya impide ver los de otra sucursal.
func (s *Servidor) rutasAlmacenes(rt *httpx.Router, sesion, admin []httpx.Medio) {
	_ = admin
	rt.ManejarFunc(http.MethodGet, "/api/origins", s.listarOrigenes, sesion...)
	rt.ManejarFunc(http.MethodPost, "/api/origins", s.crearOrigen, sesion...)
	rt.ManejarFunc(http.MethodPatch, "/api/origins/{id}", s.actualizarOrigen, sesion...)
	rt.ManejarFunc(http.MethodDelete, "/api/origins/{id}", s.borrarOrigen, sesion...)

	rt.ManejarFunc(http.MethodGet, "/api/almacenes", s.listarAlmacenes, sesion...)
}

// ---------------------------------------------------------------------------
// El cliente de Accesos
// ---------------------------------------------------------------------------

// ClienteAccesos es por dónde se habla con Accesos. Es una interfaz para que las pruebas
// no tengan que levantar un Accesos ni salir a la red.
type ClienteAccesos interface {
	// Almacenes trae TODAS las sucursales con sus almacenes. Accesos no sabe de nuestro
	// alcance: filtrar es cosa de quien llama.
	Almacenes(ctx context.Context) ([]SucursalConAlmacenes, error)
	// AlmacenesDeSucursal es lo mismo, ya indexado por código. Una sucursal desconocida
	// devuelve la lista vacía y NO un error: que Accesos no tenga almacenes de una
	// sucursal es un estado normal.
	AlmacenesDeSucursal(ctx context.Context, codigo string) ([]Almacen, error)
}

// Accesos: el cliente del proceso. EL SITIO BUENO ES `s.accesos`, el campo del servidor.
//
// Esta variable de paquete se quedó por una razón concreta y temporal: `cotizacion.go`
// todavía la usa (`almacenesDeCotizacion`) y ese fichero lo está escribiendo otro ahora
// mismo, así que no se puede tocar en este cambio. En cuanto se libere, esa llamada pasa a
// `s.accesos` y esta variable desaparece. Está apuntada en
// `docs/integracion-pendiente.md`.
//
// MIENTRAS TANTO ES UNA SOLA INSTANCIA, no dos: `NuevoServidor` mete ESTA en el campo del
// servidor. Es lo que importa, porque el cliente lleva dentro el recuerdo de cinco minutos
// de la lista de almacenes; con dos instancias habría dos recuerdos y un lote de 200
// pedidos volvería a preguntarle a Accesos lo que la otra acababa de traer.
var Accesos ClienteAccesos = &accesosHTTP{}

// accesosDelServidor devuelve el cliente que usa el servidor, con la configuración puesta.
//
// La configuración se le pone AQUÍ y no al declarar la variable porque al declararla
// todavía no se ha leído el entorno. Sólo se rellena si está vacía —nadie pisa una que ya
// esté— y bajo el mismo candado que el recuerdo, que es lo que evita la carrera entre dos
// servidores montados a la vez en las pruebas.
//
// Si alguien puso un doble (las pruebas), la aserción de tipo falla y se devuelve el doble
// tal cual, que es justo lo que se quiere.
func accesosDelServidor(cfg *config.Config) ClienteAccesos {
	if h, ok := Accesos.(*accesosHTTP); ok {
		h.mu.Lock()
		if h.cfg == nil {
			h.cfg = cfg
		}
		h.mu.Unlock()
	}
	return Accesos
}

// accesosHTTP habla con Accesos firmando cada petición.
//
// ACCESOS NO ACEPTA UNA CLAVE SUELTA EN UNA CABECERA, y es lo correcto: cada aplicación
// firma con SU llave sobre el método, la ruta, la hora, un nonce y el hash del cuerpo, así
// que una petición copiada de un registro no sirve al minuto siguiente. Se reutiliza la
// llave del login único en vez de abrir una segunda puerta.
//
// EL RECUERDO DE LA LISTA (5 min, `ALMACENES_CACHE_MS`) SE TIRA DE DOS FORMAS: caduca solo, y lo tira
// el aviso del CRM (`Olvidar`, que llama `CambiaronLosAlmacenes` desde `internal/avisoscrm`). Los
// almacenes viven en Accesos y se editan desde el CRM (Jose, 20/10/2026): Reparto ya no guarda, así que
// ya no hay un guardado propio que lo tire. Sin el aviso —Redis caído o sin configurar—, un punto
// corregido en el CRM tarda hasta 5 minutos en medirse, y con él se cobra la distancia.
type accesosHTTP struct {
	cfg      *config.Config
	mu       sync.Mutex
	cuando   time.Time
	recuerdo map[string][]Almacen
	// generacion sube cada vez que se tira el recuerdo (`Olvidar`). Una lectura que EMPEZÓ antes del
	// aviso del CRM y termina después no puede guardar su respuesta (es la lista vieja): ver `recordar`.
	generacion uint64
}

// RutaAlmacenesDeAccesos: de dónde se LEEN los almacenes. Reparto ya no escribe en ella
// (20/10/2026): los almacenes se editan en el CRM.
const RutaAlmacenesDeAccesos = "/api/service/almacenes"

// recuerdoDeAlmacenes: cuánto se recuerda la lista. Sale de `ALMACENES_CACHE_MS`, que ya
// viene validada de `config` (cinco minutos por defecto, ver allí el porqué).
//
// Con `cfg` nil se cae al valor de siempre en vez de a cero: un recuerdo de cero segundos
// no se nota en ninguna pantalla y convierte cada lote de 200 pedidos en 200 llamadas a
// Accesos, que es justo lo que este recuerdo existe para evitar.
func (c *accesosHTTP) recuerdoDeAlmacenes() time.Duration {
	if c.cfg != nil && c.cfg.AlmacenesCache > 0 {
		return c.cfg.AlmacenesCache
	}
	return 5 * time.Minute
}

func (c *accesosHTTP) Almacenes(ctx context.Context) ([]SucursalConAlmacenes, error) {
	// LA GENERACIÓN SE LEE ANTES DE PEDIR: si durante la petición llega el aviso del CRM (`Olvidar`), lo
	// que contesta Accesos puede ser la lista de ANTES del cambio, y guardarla dejaría el punto viejo
	// cinco minutos más, que es justo lo que el aviso viene a evitar.
	c.mu.Lock()
	generacion := c.generacion
	c.mu.Unlock()
	crudo, err := c.pedirFirmado(ctx, http.MethodGet, RutaAlmacenesDeAccesos, nil, 10*time.Second)
	if err != nil {
		return nil, err
	}
	var r struct {
		Sucursales []SucursalConAlmacenes `json:"sucursales"`
	}
	if err := json.Unmarshal(crudo, &r); err != nil {
		return nil, fmt.Errorf("Accesos contestó algo que no se entiende: %w", err)
	}
	// Se guarda el recuerdo aquí y no sólo en `AlmacenesDeSucursal`: la lista es la misma
	// llamada, y una pantalla que acaba de pedir los almacenes deja calientes las
	// distancias de la siguiente búsqueda de clientes.
	c.recordar(r.Sucursales, generacion)
	return r.Sucursales, nil
}

func (c *accesosHTTP) AlmacenesDeSucursal(ctx context.Context, codigo string) ([]Almacen, error) {
	clave := strings.ToUpper(strings.TrimSpace(codigo))

	c.mu.Lock()
	vivo := c.recuerdo != nil && time.Since(c.cuando) < c.recuerdoDeAlmacenes()
	if vivo {
		lista := c.recuerdo[clave]
		c.mu.Unlock()
		return lista, nil
	}
	c.mu.Unlock()

	sucursales, err := c.Almacenes(ctx)
	if err != nil {
		return nil, err
	}
	// SE USA LO QUE ACABA DE CONTESTAR ACCESOS, no se vuelve a leer el recuerdo: entre `recordar` y
	// aquí un `Olvidar` lo deja en nil y `c.recuerdo[clave]` daría la lista vacía SIN error, o sea que
	// la cotización mediría como «esta sucursal no tiene almacenes».
	//
	// Una sucursal que Accesos no conoce devuelve la lista vacía, NO un error: que no tenga almacenes
	// todavía es un estado normal y quien pregunta ya sabe qué hacer con una lista vacía (no medir).
	for _, su := range sucursales {
		if strings.ToUpper(strings.TrimSpace(su.Codigo)) == clave {
			return su.Almacenes, nil
		}
	}
	return nil, nil
}

// recordar guarda la lista SÓLO si no se ha tirado el recuerdo desde que empezó la lectura (`generacion`
// es la que había entonces): si se tiró, esta respuesta puede ser la de antes del cambio.
func (c *accesosHTTP) recordar(sucursales []SucursalConAlmacenes, generacion uint64) {
	porCodigo := make(map[string][]Almacen, len(sucursales))
	for _, s := range sucursales {
		porCodigo[strings.ToUpper(strings.TrimSpace(s.Codigo))] = s.Almacenes
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.generacion != generacion {
		return
	}
	c.recuerdo, c.cuando = porCodigo, time.Now()
}

// Olvidar tira el recuerdo de la lista: la siguiente pregunta vuelve a Accesos. Se tira TODO y no
// sólo la sucursal del aviso porque el recuerdo es de una sola llamada (todas las sucursales) y volver
// a pedirla cuesta lo mismo; y con un aviso que no se entiende, tirar todo es lo que se acordó.
func (c *accesosHTTP) Olvidar() {
	c.mu.Lock()
	c.recuerdo, c.cuando = nil, time.Time{}
	c.generacion++
	c.mu.Unlock()
}

var _ interface{ Olvidar() } = (*accesosHTTP)(nil)

// pedirFirmado hace la llamada con la firma puesta.
//
// La firma es HMAC-SHA256 sobre `MÉTODO\nruta\nhora\nnonce\nhash-del-cuerpo`, con la llave
// que auth deriva POR APLICACIÓN —la de reparto no sirve para hacerse pasar por PEDIDO—.
// El nonce y la hora son contra la repetición: Accesos rechaza una firma repetida o de
// hace más de cinco minutos.
func (c *accesosHTTP) pedirFirmado(ctx context.Context, metodo, ruta string, cuerpo []byte, plazo time.Duration) ([]byte, error) {
	// Las tres salen de `config`, que ya les puso su valor por defecto y les quitó la
	// barra final a la URL. Aquí sólo se comprueba que haya llave.
	if c.cfg == nil {
		return nil, errors.New("el cliente de Accesos no tiene configuración")
	}
	llave := c.cfg.AuthSigningKey
	if llave == "" {
		// Se dice ANTES de salir a la red: sin llave no hay petición que valga, y un
		// «401 de auth» es mucho más difícil de relacionar con una variable que falta.
		return nil, errors.New("PROCOVAR_AUTH_SIGNING_KEY no está configurada")
	}
	base := c.cfg.AuthURL
	cliente := c.cfg.AuthClientID

	ts := strconv.FormatInt(time.Now().Unix(), 10)
	nonce := make([]byte, 16)
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	hashCuerpo := sha256.Sum256(cuerpo)
	aFirmar := strings.Join([]string{
		strings.ToUpper(metodo), ruta, ts, hex.EncodeToString(nonce), hex.EncodeToString(hashCuerpo[:]),
	}, "\n")

	// La llave viaja en hexadecimal, igual que en delivery. Si no lo fuera se usa tal
	// cual: mejor una firma que Accesos rechaza con un 401 legible que una llave medio
	// decodificada que produce firmas que no cuadran nunca y no dicen por qué.
	secreto, err := hex.DecodeString(llave)
	if err != nil {
		secreto = []byte(llave)
	}
	mac := hmac.New(sha256.New, secreto)
	mac.Write([]byte(aFirmar))

	ctx, cancelar := context.WithTimeout(ctx, plazo)
	defer cancelar()

	var lector io.Reader
	if cuerpo != nil {
		lector = bytes.NewReader(cuerpo)
	}
	pet, err := http.NewRequestWithContext(ctx, metodo, strings.TrimRight(base, "/")+ruta, lector)
	if err != nil {
		return nil, err
	}
	pet.Header.Set("x-client-id", cliente)
	pet.Header.Set("x-timestamp", ts)
	pet.Header.Set("x-nonce", hex.EncodeToString(nonce))
	pet.Header.Set("x-signature", hex.EncodeToString(mac.Sum(nil)))
	pet.Header.Set("content-type", "application/json")
	pet.Header.Set("accept", "application/json")

	res, err := http.DefaultClient.Do(pet)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	crudo, err := io.ReadAll(io.LimitReader(res.Body, 4<<20))
	if err != nil {
		return nil, err
	}
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		// Se recorta el cuerpo: una página de error entera dentro del mensaje que se
		// enseña en la pantalla del logístico no ayuda a nadie.
		return nil, fmt.Errorf("auth %d: %s", res.StatusCode, recorte(string(crudo), 160))
	}
	return crudo, nil
}

func recorte(s string, n int) string {
	s = strings.TrimSpace(s)
	if len(s) <= n {
		return s
	}
	return s[:n]
}

// numeroJSON: `true` sólo si el valor decodificado es un número de JSON. Es el
// `typeof lat !== 'number'` del contrato — una coordenada que llega como texto («19.1»)
// se rechaza en vez de convertirse, porque lo que viene como texto suele venir de un campo
// que no se validó y a veces trae una coma decimal.
func numeroJSON(v any) (float64, bool) {
	f, ok := v.(float64)
	return f, ok
}
