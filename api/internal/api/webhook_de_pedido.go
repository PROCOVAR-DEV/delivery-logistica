// LA PUERTA POR DONDE PEDIDO TOCA: `POST /api/webhooks/pedido`.
//
// Hasta hoy lo que PEDIDO cambiaba llegaba por la COLA de Redis: el reparto leía bloqueado
// y, con el aviso en la mano, volvía a pedirle el pedido a PEDIDO. Eso funciona y sigue
// puesto, pero son dos vueltas por cada cambio. Jose, 26/09/2026: «que el webhook mande
// todo para rellenar lo que le hace falta a reparto» — y con el pedido entero dentro del
// POST, la segunda vuelta desaparece.
//
// LOS DOS CAMINOS CONVIVEN A PROPÓSITO durante la mudanza, y NO se pisan: el `avisoId` es
// **el mismo identificador por los dos lados** —es el id que Redis le pone a la entrada del
// stream—, así que un aviso que entre por los dos se reconoce como el mismo. Lo acordamos
// con la sesión de PEDIDO el 26/09/2026.
//
// ---------------------------------------------------------------------------
// POR QUÉ NO HACE FALTA UNA TABLA DE «AVISOS YA VISTOS»
//
// PEDIDO reintenta tres veces, así que el mismo aviso puede llegar dos veces: la primera se
// aplicó y la respuesta se perdió por el camino. Lo normal sería apuntar los ids vistos para
// no aplicarlo dos veces.
//
// AQUÍ NO HACE FALTA, y conviene que quede escrito porque no es obvio: **las tres escrituras
// de este fichero son idempotentes por construcción**.
//
//   - El pedido entra por `/api/quote/batch`, que es un upsert por `externalId`; y desde el
//     26/09/2026 sus consultas llevan `IS DISTINCT FROM`, así que una fila idéntica **no se
//     reescribe** — se midió: con los guardas puestos, `orders +1` en cuatro minutos donde
//     antes había 7,1 millones de escrituras acumuladas sobre 5.452 filas.
//   - El cliente, igual: `GuardarClienteDelEspejo` con el mismo guarda.
//   - El borrado es un `DELETE` por id: borrar dos veces lo que ya no está no hace nada.
//
// Así que un reintento vuelve a hacer el mismo trabajo y deja la base exactamente igual. Una
// tabla de vistos sería una tabla más que mantener, que crece, que hay que podar, y que el
// día que se llene de más delataría un problema que no existe.
//
// LO QUE SÍ SE HACE con el `avisoId` es decirlo en el registro y contarlo en la constancia,
// que es otra pregunta: «esto ya lo tenía» y «esto es nuevo» se ven distintas desde la
// pantalla del canal, y sin ese número «entraron veinte avisos» no dice nada.
//
// ---------------------------------------------------------------------------
// LA PUERTA DE LOS PEDIDOS SIGUE SIENDO UNA SOLA
//
// Un pedido que llega por aquí **no se escribe aquí**: se traduce con `espejo.ArmarLote` —el
// mismo traductor que usa el ciclo— y se mete por `/api/quote/batch`, que es donde se le
// resuelve el peso y el reparto de carga. Tener una segunda puerta sería tener dos formas de
// que el mismo pedido quedara distinto, y el reparto de carga depende del peso TOTAL del
// envío: cotizar de a uno por otro camino daría otro número sin que nada fallara.
package api

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/espejo"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// Las cabeceras, tal como las manda PEDIDO (contrato §5.3).
const (
	CabeceraClaveDelWebhook = "X-Webhook-Key"
	CabeceraFirmaDelWebhook = "X-Webhook-Signature"
	// PrefijoDeLaFirma: el digest va en hexadecimal y en MINÚSCULAS, que es lo que
	// devuelve `createHmac(...).digest('hex')` de Node. Confirmado con la sesión de PEDIDO
	// el 26/09/2026: «no normalices mayúsculas, no te van a llegar».
	PrefijoDeLaFirma = "sha256="
)

// MaxCuerpoDelWebhook: un pedido con sus líneas y su cliente. Ocho megas es holgadísimo y
// sigue siendo un tope: sin él, un cuerpo enorme de un PEDIDO que se volvió loco se lee
// entero en memoria antes de que nadie pueda decir que no.
const MaxCuerpoDelWebhook = 8 << 20

// Los motivos de rechazo, en palabras. Van en la respuesta y PEDIDO los guarda literales en
// su pantalla, así que dicen QUÉ falta y no «no autorizado».
const (
	msgWebhookSinConfigurar = "esta API no tiene configurada la pareja key/secret del " +
		"webhook de PEDIDO: el aviso no se puede comprobar y no se aplica"
	msgWebhookClaveMala  = "la X-Webhook-Key no es la de este reparto"
	msgWebhookSinFirma   = "falta la cabecera X-Webhook-Signature"
	msgWebhookFirmaMala  = "la firma no cuadra con el cuerpo recibido"
	msgWebhookCuerpoMalo = "el cuerpo no se entiende como un aviso de PEDIDO"
)

// avisoEntrante es el cuerpo del POST (contrato §5).
//
// `Pedido` y `Cliente` son PUNTEROS para poder distinguir «no vino» de «vino vacío»: un
// aviso de `borrado` llega con el aviso solo, y un `factura` con un pedido vacío dentro es
// un fallo de PEDIDO que hay que decir, no un borrado silencioso.
type avisoEntrante struct {
	Aviso   *avisoDeFuera          `json:"aviso"`
	Pedido  *espejo.PedidoDeFuera  `json:"pedido"`
	Cliente *espejo.ClienteDeFuera `json:"cliente"`
}

// avisoDeFuera son los campos del §3.1. Todos texto: por la cola viajan como texto —un
// stream de Redis es campo/valor— y por el webhook se mandan iguales para que el mismo
// aviso se lea igual por los dos caminos.
type avisoDeFuera struct {
	AvisoID    string `json:"avisoId"`
	Entidad    string `json:"entidad"`
	Motivo     string `json:"motivo"`
	Accion     string `json:"accion"`
	ID         string `json:"id"`
	SucursalID string `json:"sucursalId"`
}

// mediosDelWebhook: la puerta se comprueba ANTES de tocar la base.
//
// Comprueba clave y firma, y sólo entonces mete la persona sintética de servicio y deja que
// la portería resuelva el alcance — el mismo camino que cualquier otra petición, para que el
// webhook no tenga una forma propia de leer y escribir.
//
// EL CUERPO SE LEE AQUÍ, porque la firma va sobre los BYTES EXACTOS que viajaron: volver a
// serializar el JSON para firmarlo cambia el orden de las claves o un espacio y la firma no
// cuadra jamás, por un motivo que no se ve. Se guarda en el contexto para que el manejador
// no tenga que leerlo otra vez (y no pueda leer algo distinto de lo que se firmó).
func (s *Servidor) mediosDelWebhook() []httpx.Medio {
	return []httpx.Medio{
		s.comprobarLaFirmaDePedido,
		func(siguiente http.Handler) http.Handler {
			return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				u := &auth.Usuario{
					ID: "servicio:webhook", Nombre: "webhook de PEDIDO", Rol: "SUPER ADMIN",
				}
				r2 := r.Clone(auth.ConUsuario(r.Context(), u))
				// SIN SUCURSAL: un aviso de PEDIDO habla de la sucursal que él diga, no de
				// una elegida en una pantalla. Si llegara la cabecera, el alcance se
				// estrecharía y un pedido de Holguín entraría «fuera de alcance» sin que
				// nada fallara.
				r2.Header.Del(alcance.CabeceraSucursal)
				siguiente.ServeHTTP(w, r2)
			})
		},
		s.porteria.Exigir,
	}
}

// claveDelCuerpo es dónde vive el cuerpo crudo entre el medio y el manejador.
type claveDelCuerpo struct{}

func (s *Servidor) comprobarLaFirmaDePedido(siguiente http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		clave, secreto := s.cfg.WebhookDePedidoKey, s.cfg.WebhookDePedidoSecret

		// SIN CONFIGURAR NO SE ACEPTA NADA, y contesta 503 y no 401.
		//
		// La diferencia importa porque PEDIDO decide por el código: 401 lo descarta a la
		// primera —es configuración de SU lado y repetirlo da lo mismo— y 5xx lo reintenta.
		// Aquí lo que falta es de ESTE lado, así que el aviso tiene que seguir vivo allá
		// hasta que se ponga el secreto. Con un 401, esos avisos se perderían por un
		// despiste de despliegue nuestro.
		if clave == "" || secreto == "" {
			httpx.Registro(r).Error("llegó un aviso de PEDIDO y el webhook no está configurado",
				"falta_key", clave == "", "falta_secret", secreto == "")
			httpx.Error(w, r, http.StatusServiceUnavailable, msgWebhookSinConfigurar)
			return
		}

		crudo, err := io.ReadAll(io.LimitReader(r.Body, MaxCuerpoDelWebhook+1))
		defer r.Body.Close()
		if err != nil {
			httpx.Error(w, r, http.StatusBadRequest, "no se pudo leer el cuerpo del aviso")
			return
		}
		if len(crudo) > MaxCuerpoDelWebhook {
			httpx.Error(w, r, http.StatusRequestEntityTooLarge,
				fmt.Sprintf("el aviso pasa de %d bytes", MaxCuerpoDelWebhook))
			return
		}

		// LA CLAVE se compara EN TIEMPO CONSTANTE igual que la firma. Un `==` normal se
		// rinde en el primer byte distinto, y de esa diferencia de tiempo se saca la clave
		// letra por letra. Es barato hacerlo bien.
		if !hmac.Equal([]byte(r.Header.Get(CabeceraClaveDelWebhook)), []byte(clave)) {
			httpx.Registro(r).Warn("aviso de PEDIDO con la clave equivocada")
			httpx.Error(w, r, http.StatusUnauthorized, msgWebhookClaveMala)
			return
		}

		firma := r.Header.Get(CabeceraFirmaDelWebhook)
		if firma == "" {
			httpx.Error(w, r, http.StatusUnauthorized, msgWebhookSinFirma)
			return
		}
		if !firmaCuadra(firma, secreto, crudo) {
			httpx.Registro(r).Warn("aviso de PEDIDO con la firma mala", "bytes", len(crudo))
			httpx.Error(w, r, http.StatusUnauthorized, msgWebhookFirmaMala)
			return
		}

		siguiente.ServeHTTP(w, r.WithContext(contextoConCuerpo(r.Context(), crudo)))
	})
}

// firmaCuadra comprueba `sha256=<hex>` sobre los bytes exactos.
//
// SE COMPARA EN TIEMPO CONSTANTE (`hmac.Equal`) y no con `==`: la comparación normal se
// rinde en el primer byte distinto, y midiendo cuánto tarda se saca la firma byte a byte.
// Con eso, cualquiera puede mandarle al reparto un pedido que no existe.
func firmaCuadra(cabecera, secreto string, cuerpo []byte) bool {
	// El prefijo se exige, no se adivina. Aceptar un hex pelado además del prefijado sería
	// aceptar dos formatos, y entonces «la firma no cuadra» puede ser que el otro lado
	// cambió de formato y nadie se enteró.
	if !strings.HasPrefix(cabecera, PrefijoDeLaFirma) {
		return false
	}
	dado, err := hex.DecodeString(strings.TrimPrefix(cabecera, PrefijoDeLaFirma))
	if err != nil {
		return false
	}
	mac := hmac.New(sha256.New, []byte(secreto))
	mac.Write(cuerpo)
	return hmac.Equal(mac.Sum(nil), dado)
}

func contextoConCuerpo(ctx context.Context, crudo []byte) context.Context {
	return context.WithValue(ctx, claveDelCuerpo{}, crudo)
}

func cuerpoDelContexto(r *http.Request) []byte {
	crudo, _ := r.Context().Value(claveDelCuerpo{}).([]byte)
	return crudo
}

// ---------------------------------------------------------------------------
// El manejador
// ---------------------------------------------------------------------------

// respuestaDelWebhook es lo que PEDIDO lee para decidir si reintenta. Los nombres y los
// códigos se acordaron con su sesión el 26/09/2026, y cada uno significa una cosa:
//
//   - 200 con `aplicados: 0` **no es un fallo**: ese aviso no llevó a nada porque ya estaba.
//     PEDIDO no lo reintenta, y hace bien.
//   - 401 y 422 se descartan a la primera: son configuración o un cuerpo que no se entiende,
//     y repetirlos da exactamente lo mismo.
//   - 503 sí se reintenta: no se pudo escribir y eso pasa solo.
type respuestaDelWebhook struct {
	Recibidos int    `json:"recibidos"`
	Aplicados int    `json:"aplicados"`
	SinEfecto int    `json:"sinEfecto"`
	Motivos   string `json:"motivos,omitempty"`
	AvisoID   string `json:"avisoId,omitempty"`
}

// avisoDePedido atiende `POST /api/webhooks/pedido`.
//
// UN AVISO POR PETICIÓN, que es como los manda PEDIDO. No se acumulan ni se agrupan aquí:
// agrupar es lo que hace falta cuando uno LEE una cola de golpe —cien avisos de Camagüey en
// una petición y no cien—, y aquí el que decide el ritmo es el que llama.
func (s *Servidor) avisoDePedido(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	arranque := time.Now()

	var c avisoEntrante
	if err := json.Unmarshal(cuerpoDelContexto(r), &c); err != nil || c.Aviso == nil {
		// 422 Y NO 400 a propósito: es lo que PEDIDO descarta a la primera. Un cuerpo que no
		// se entiende no se va a entender mejor al tercer intento.
		s.apuntarElAviso(r, a, respuestaDelWebhook{
			Recibidos: 1, SinEfecto: 1, Motivos: msgWebhookCuerpoMalo,
		}, arranque)
		// SE AVISA TAMBIÉN DE ESTO. Se quedó fuera al escribirlo —este camino salía antes de
		// llegar al aviso— y lo cazó su prueba: un PEDIDO que manda cuerpos que no se
		// entienden es justo lo que hay que ver aparecer en la pantalla del canal, no algo
		// que se descubra recargando.
		avisarCambioEnElCanal(r.Context())
		httpx.Error(w, r, http.StatusUnprocessableEntity, msgWebhookCuerpoMalo)
		return
	}

	reg := httpx.Registro(r).With(
		"aviso", c.Aviso.AvisoID, "motivo", c.Aviso.Motivo,
		"entidad", c.Aviso.Entidad, "id", c.Aviso.ID,
	)

	res, estado := s.aplicarElAviso(r, a, c, reg)
	res.Recibidos = 1
	res.AvisoID = c.Aviso.AvisoID

	// LA CONSTANCIA, SIEMPRE Y PASE LO QUE PASE — también cuando se rechaza. Es lo que hace
	// que la pantalla del canal pueda contestar «¿está entrando algo?»: sin la fila, un
	// PEDIDO que manda y un reparto que rechaza todo se ven exactamente igual desde aquí.
	s.apuntarElAviso(r, a, res, arranque)
	// Y SE AVISA, pase lo que pase: ver `CambioCanal`.
	avisarCambioEnElCanal(r.Context())

	if estado != http.StatusOK {
		httpx.Error(w, r, estado, res.Motivos)
		return
	}
	httpx.JSON(w, r, http.StatusOK, res)
}

// aplicarElAviso hace el trabajo y devuelve qué pasó y con qué código contestar.
//
// Está aparte del manejador para poder probar las cinco ramas —factura, domicilio,
// importación, cliente, borrado— sin montar un servidor ni firmar nada.
func (s *Servidor) aplicarElAviso(
	r *http.Request, a *alcance.Acotado, c avisoEntrante, reg *slog.Logger,
) (respuestaDelWebhook, int) {
	ctx := r.Context()
	base := espejo.BaseDelReparto{Acotado: a}

	switch c.Aviso.Motivo {
	// LO QUE SE FUE. `borrado` y `ya_no_va` son dos sucesos distintos —uno se borró en
	// PEDIDO, el otro dejó de ser repartible— y la reacción de este lado es la misma: si se
	// queda, alguien lo mete en un camión y nadie lo echa en falta. Llegan SIN pedido
	// dentro, que es lo que significan.
	case espejo.MotivoBorrado, espejo.MotivoYaNoVa:
		if c.Aviso.ID == "" {
			return respuestaDelWebhook{SinEfecto: 1,
				Motivos: "un aviso de borrado sin id no dice qué quitar"}, http.StatusUnprocessableEntity
		}
		if err := base.QuitarPedidos(ctx, []string{c.Aviso.ID}); err != nil {
			reg.Error("no se pudo quitar un pedido avisado como borrado", "err", err)
			return respuestaDelWebhook{Motivos: "no se pudo quitar: " + err.Error()},
				http.StatusServiceUnavailable
		}
		reg.Info("pedido quitado por aviso de PEDIDO")
		// SE AVISA A LAS PANTALLAS, y son DOS — 29/09/2026.
		//
		// Hasta hoy por aquí sólo salía `canal`, que es el aviso de la pantalla del
		// desarrollador. O sea: se borraba un pedido de la base y **ninguna pantalla del
		// logístico se enteraba de que había desaparecido**.
		//
		//   - `pedidos`, porque la fila se fue de `orders`;
		//   - `tablero`, porque `board_placements.order_id` cuelga de `orders` con
		//     `ON DELETE CASCADE` (`00002_tablero.sql`): si ese pedido estaba colocado en
		//     una zona, la tarjeta se va con él. Quien esté armando el tablero tiene que
		//     verla irse, no seguir arrastrando algo que ya no existe.
		//
		// Van sin acotar porque quien entra por esta puerta es el servicio de PEDIDO, que no
		// es una persona y no tiene sucursal: `sucursalDelAlcance` devolvería vacío de todos
		// modos, y el pedido borrado puede ser de cualquiera de las ocho.
		avisarCambioDePedidos(ctx)
		avisarCambioDelTablero(ctx)
		return respuestaDelWebhook{Aplicados: 1}, http.StatusOK

	// EL CLIENTE SE MOVIÓ DE SITIO. El reparto ordena las paradas por su coordenada: si
	// alguien la corrige y esto no se entera, la ruta se arma hacia el sitio de antes, con
	// números y todo y sin un solo error.
	case espejo.MotivoCliente:
		if c.Cliente == nil {
			return respuestaDelWebhook{SinEfecto: 1,
				Motivos: "el aviso de cliente vino sin el cliente dentro"}, http.StatusUnprocessableEntity
		}
		// SIN COORDENADAS NO HAY PARADA, y la columna no admite nulos. Es lo mismo que hace
		// el repaso completo, y no es un fallo: un cliente puede quedarse sin geolocalizar.
		if c.Cliente.Latitud == nil || c.Cliente.Longitud == nil {
			return respuestaDelWebhook{SinEfecto: 1,
				Motivos: "el cliente llegó sin coordenadas: no hay parada que visitar"}, http.StatusOK
		}
		if err := base.GuardarCliente(ctx, *c.Cliente); err != nil {
			reg.Error("no se pudo guardar un cliente movido de sitio", "err", err)
			return respuestaDelWebhook{Motivos: "no se pudo guardar el cliente: " + err.Error()},
				http.StatusServiceUnavailable
		}
		reg.Info("cliente al día por aviso de PEDIDO", "cliente", c.Cliente.ID)
		// Y SE AVISA. `CambioClientes` llevaba desde el principio declarado y sin publicar,
		// con un comentario en `eventos.go` que lo daba por bueno diciendo que aquí no hay
		// ninguna puerta que escriba `customers`. La hay, y es ésta. Ver
		// `avisarCambioDeClientes` en `clientes.go`.
		avisarCambioDeClientes(ctx)
		return respuestaDelWebhook{Aplicados: 1}, http.StatusOK
	}

	// EL RESTO SON PEDIDOS: `factura`, `domicilio`, `importacion` — y cualquier motivo NUEVO
	// que PEDIDO invente contra una versión vieja de esto.
	//
	// UN MOTIVO DESCONOCIDO NO SE TIRA: si trae un pedido dentro, se guarda. Es la reacción
	// segura —cuesta lo mismo y no pierde nada—; descartarlo sería perder el pedido sin un
	// solo error, que es el fallo que más caro sale aquí porque no se ve.
	if c.Pedido == nil {
		// POR AQUÍ NO SE VA A PEDIR NADA A PEDIDO, y es a propósito. Quien recibe un POST no
		// tiene por qué volver a llamar para enterarse de lo que le acaban de contar: eso es
		// la mitad del sondeo otra vez. Se dice, se cuenta como sin efecto, y la red de
		// debajo —el ciclo lento— lo recoge en su pasada.
		reg.Warn("aviso de pedido sin el pedido dentro: lo recogerá el ciclo lento")
		return respuestaDelWebhook{SinEfecto: 1,
			Motivos: "el aviso vino sin el pedido dentro: lo recogerá el ciclo"}, http.StatusOK
	}

	// LA PUERTA ÚNICA. Se traduce con el MISMO traductor del ciclo y se mete por
	// `/api/quote/batch`, que es quien sabe repartir la carga. Ver la cabecera del fichero.
	lote, err := json.Marshal(espejo.ArmarLote([]espejo.PedidoDeFuera{*c.Pedido}))
	if err != nil {
		return respuestaDelWebhook{Motivos: "no se pudo armar el lote: " + err.Error()},
			http.StatusServiceUnavailable
	}
	destino := s.cfg.DeliveryURL
	if destino == "" {
		destino = "http://127.0.0.1:" + s.cfg.Puerto
	}
	// SIN LA FILA DE LA PUERTA, que este aviso ya tiene la suya.
	//
	// `/api/quote/batch` apunta su propia recepción, y con razón: es por donde entran los
	// lotes del espejo. Pero este salto es INTERNO —el mismo aviso pasando al sitio que sabe
	// repartir la carga—, así que dejaría DOS filas por un solo aviso y `escritosHoy`
	// contaría el mismo pedido dos veces. Un número doble en la pantalla que existe para
	// mirar ese número es exactamente el fallo que aquí sale más caro: creíble y equivocado.
	cuerpo, estado, err := s.pedirAlEspejo(ctx, http.MethodPost, destino+"/api/quote/batch", lote,
		CabeceraDeConstancia, YaApuntada)
	if err != nil {
		reg.Error("la puerta de entrada no contestó", "err", err)
		return respuestaDelWebhook{Motivos: "la cotización no contesta: " + err.Error()},
			http.StatusServiceUnavailable
	}
	if estado < 200 || estado >= 300 {
		reg.Error("la puerta de entrada rechazó el pedido", "estado", estado)
		return respuestaDelWebhook{
			Motivos: fmt.Sprintf("la cotización contestó %d: %s", estado, recortar(cuerpo, 200)),
		}, http.StatusServiceUnavailable
	}

	var res espejo.RespuestaDelLote
	if err := json.Unmarshal(cuerpo, &res); err != nil {
		// 200 CON UN CUERPO QUE NO SE ENTIENDE NO SE CUENTA COMO APLICADO. Contarlo sería
		// declarar guardado un pedido del que no se sabe nada.
		return respuestaDelWebhook{Motivos: "la cotización contestó algo que no se entiende"},
			http.StatusServiceUnavailable
	}
	if res.Persisted == 0 {
		// QUE NO ENTRE NO ES UN FALLO DE PEDIDO, y por eso es 200: puede que ese pedido
		// todavía no sea repartible, o que llegara sin coordenadas. Pero **se dice con el
		// motivo literal de la puerta**, que es lo único que le sirve a quien lo mire: «no
		// se pudo» no le dice nada a nadie.
		porQue := motivoDeNoEntrar(res)
		reg.Info("el aviso no metió el pedido", "porque", porQue)
		return respuestaDelWebhook{SinEfecto: 1, Motivos: porQue}, http.StatusOK
	}
	reg.Info("pedido al día por aviso de PEDIDO")
	return respuestaDelWebhook{Aplicados: res.Persisted}, http.StatusOK
}

// motivoDeNoEntrar saca el motivo LITERAL que dio la puerta.
//
// Un lote de uno tiene un resultado y un motivo; si viniera vacío se dice así, porque «no
// entró y no hay motivo» es una situación distinta de «no entró porque tal» y se arregla en
// otro sitio.
func motivoDeNoEntrar(res espejo.RespuestaDelLote) string {
	for _, r := range res.Results {
		if r.Reason != "" {
			return r.Reason
		}
		if r.Status != "" {
			return "la puerta lo dejó en " + r.Status
		}
	}
	return "la puerta no lo guardó y no dijo por qué"
}

// apuntarElAviso deja la fila en `recepciones_del_webhook`, la MISMA tabla que usa la cola.
//
// LAS DOS EN LA MISMA LISTA Y NO EN DOS: son dos caminos para lo mismo, y tenerlos separados
// obliga a mirar en dos sitios para contestar «¿está entrando algo?», que es la primera
// pregunta cuando algo no llega. El `origen` las distingue —`pedido` es por HTTP, `stream`
// por la cola— y la pantalla lo dice con esas palabras.
//
// UN FALLO AL APUNTAR NO TUMBA EL AVISO: lo que importa ya está escrito, y devolver un error
// aquí haría que PEDIDO reintentara un aviso que sí se aplicó.
func (s *Servidor) apuntarElAviso(
	r *http.Request, a *alcance.Acotado, res respuestaDelWebhook, arranque time.Time,
) {
	if err := a.ApuntarRecepcionDelWebhook(r.Context(), sqlc.ApuntarRecepcionDelWebhookParams{
		// `webhook` Y NO `pedido`, que es lo que se puso primero y estaba mal.
		//
		// `pedido` ya lo usa el LOTE del espejo (`apuntarLaRecepcion`), que entra por
		// `/api/quote/batch` en tandas de 200. Con el mismo nombre, los avisos del webhook
		// —de uno en uno— quedaban enterrados entre lotes de doscientos, y la pantalla no
		// podía contestar «¿está entrando algo POR EL WEBHOOK?», que es justo su pregunta.
		// Se vio en producción el 26/09/2026, con las dos clases de fila mezcladas.
		Origen:     OrigenDelWebhook,
		Traidos:    int32(res.Recibidos),
		Escritos:   int32(res.Aplicados),
		Rechazados: int32(res.SinEfecto),
		Motivos:    textoONil(res.Motivos),
		DuracionMs: int32(time.Since(arranque).Milliseconds()),
	}); err != nil {
		httpx.Registro(r).Warn("no se pudo apuntar la recepción del webhook", "err", err)
	}
}

// avisarCambioEnElCanal publica «se movió algo en el canal» para que la pantalla del
// desarrollador se repinte sin que nadie le dé a nada. Se engancha en `eventos.go`, como
// todos los demás: quien escribe no tiene por qué saber cómo se reparten los avisos.
//
// NO HACE NADA POR DEFECTO a propósito: así las pruebas que montan sólo estas rutas no
// necesitan un bus levantado, y este fichero no sabe que el bus existe.
var avisarCambioEnElCanal = func(_ context.Context) {}

// Los nombres del `origen` en `recepciones_del_webhook`. Son TRES y cada uno es una puerta
// distinta; la pantalla los dice con palabras («por el webhook», «por la cola», «por HTTP»).
//
// Que se llamen distinto no es orden por el orden: con dos de ellos compartiendo nombre, la
// pregunta «¿está entrando algo por el webhook?» no se puede contestar mirando la tabla.
const (
	// OrigenDelWebhook: un aviso que entró por `POST /api/webhooks/pedido`, de uno en uno.
	OrigenDelWebhook = "webhook"
	// OrigenDelLote: una tanda que entró por `/api/quote/batch` — el espejo, de 200 en 200.
	OrigenDelLote = "pedido"
)

// CabeceraDeConstancia dice que la fila de esta tanda YA la escribió quien llama.
//
// Sólo la pone este proceso hablando consigo mismo, y `/api/quote/batch` ya exige clave de
// servicio: nadie de fuera puede usarla para esconder su lote del registro.
const (
	CabeceraDeConstancia = "X-Reparto-Constancia"
	YaApuntada           = "ya-apuntada"
)
