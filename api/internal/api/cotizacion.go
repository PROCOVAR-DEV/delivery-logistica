// LA COTIZACIÓN. Las cuatro rutas de `/api/quote` y `/api/tasa`.
//
// AQUÍ UN ERROR NO REVIENTA: DA UN NÚMERO DISTINTO, y nadie se entera hasta que no cuadra
// la caja. Por eso las cuentas NO están en este fichero: viven en `internal/cotizar`, que
// es un paquete de funciones puras con pruebas de tabla —entrada concreta, salida
// concreta— sacadas de correr las fórmulas del pliego en Node. Este fichero sólo hace de
// puerta: valida el cuerpo en el ORDEN del contrato, busca los datos y llama a la fórmula.
//
// Pliego: `../../../docs/reglas-negocio.md` §1 (geometría), §2 (pesos y armado del Order),
// §7 (el costo del domicilio), §8 (la tasa), §10 (almacenes); y `docs/contratos-api.md`
// para las cuatro rutas, sus códigos y sus mensajes literales.
//
// LA REGLA DE FONDO DE TODO ESTO: **el precio del domicilio lo pone la APK de Entrega y
// nadie más.** Aquí no se calcula un precio propio: `/api/quote` está retirado y el
// `price` del lote es SIEMPRE null. Lo único que se calcula es el costo de UN domicilio
// (`/api/quote/home-delivery`) y se calcula con la fórmula de Entrega, calcada, para que
// un pedido metido a mano salga por el mismo número que uno hecho desde el teléfono.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/cotizar"
	"procovar/reparto-api/internal/espejo"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// ---------------------------------------------------------------------------
// Mensajes literales del contrato
// ---------------------------------------------------------------------------
//
// Salen tal cual de `docs/contratos-api.md`. Se enseñan en la pantalla del logístico y
// hay quien los compara, así que no se tocan ni se «mejoran».
//
// Por el patrón (ver la cabecera de `servidor.go`) su sitio natural es `internal/httpx`,
// con los demás. Están aquí porque este encargo no toca ese fichero; al primer cambio de
// `httpx/respuesta.go` se mueven allí y se borran de aquí.
const (
	msgCotizadorRetirado = "El cotizador individual se retiró. El costo del domicilio lo pone Entrega y lo escribe en PEDIDO. Para el reparto de carga de delivery, usa POST /api/quote/batch."
	msgLoteSinPedidos    = "Se espera { orders: [...] }"
	msgFaltaSucursal     = "Falta sucursalCodigo"
	msgFaltaUbicacion    = "Falta la ubicación del cliente (lat/lng)"
	// LA UBICACIÓN ESTÁ, PERO NO EXISTE. Distinto de la de arriba a propósito: quien lee
	// «falta» se va a buscar un campo vacío y este campo está lleno, con un número que no
	// es un punto de la Tierra.
	//
	// El contrato de delivery sólo comprueba `Number.isFinite`, y nos separamos de él
	// (CLAUDE.md §2). Una latitud de 200 ES finita: pasa el filtro, la haversine devuelve
	// un número grande y con sentido aparente, y el domicilio sale cobrado a cientos o
	// miles de kilómetros. Es literalmente el caso que el CLAUDE.md §4 pone como lo peor
	// que puede pasar —«un importe así se lee bien y está mal»—, y encima lo cobra la APK
	// tal cual. Mejor un 400 que dice qué mirar.
	msgUbicacionImposibleF = "La ubicación del cliente (%s, %s) no es un punto del mapa: " +
		"la latitud va de -90 a 90 y la longitud de -180 a 180. Hay que corregirla en PEDIDO."
	msgFaltaPeso  = "Falta el peso (pesoKg > 0)"
	msgSinCalculo = "No se pudo calcular con los datos que hay"

	// Los que llevan el código o el nombre de la sucursal dentro. Se nombra SIEMPRE a la
	// sucursal: «no hay tasa» a secas obliga a adivinar cuál de las ocho falta.
	msgSucursalDesconocidaF = "No hay sucursal con código %s"
	msgSinAlmacenF          = "%s no tiene ningún almacén con coordenadas"
	msgSinTasaEnAccesosF    = "No hay tasa de cambio de %s en Accesos"
	msgSinTarifaEnEntregaF  = "No hay tarifa base de %s en Entrega"

	// Avisos de `/api/tasa`. Son 200, no errores: que falte la tasa es un estado normal.
	avisoVariasSucursales = "Elegí una sucursal arriba para ver los importes en CUP: cada una tiene su tasa."
	avisoSinTasaF         = "%s no tiene tasa de cambio todavía: los importes sólo se pueden ver en USD."
	avisoTasaViejaF       = "La tasa es del %s y puede estar desfasada."
	// El sujeto del aviso cuando la sucursal del alcance no tiene nombre.
	sucursalSinNombre = "Esta sucursal"
)

// ---------------------------------------------------------------------------
// La tasa y la tarifa: de Entrega, por Accesos
// ---------------------------------------------------------------------------
//
// LA TASA SE PIDE A ACCESOS, NO SE TECLEA AQUÍ (§8). Antes vivía en Configuración →
// «Monedas»: alguien escribía un número a mano y ése usaba toda la aplicación, mientras
// PEDIDO la traía de Entrega. *Dos tasas para lo mismo se separan en cuanto una se olvida
// —y se olvida, porque la de aquí no la refresca nadie—, y el mismo domicilio vale
// distinto según dónde se mire. Eso no falla en pantalla: sale un importe creíble y cuadra
// mal en la caja, que es donde se descubre tarde.*
//
// De los almacenes se encarga `Accesos` (ver `almacenes.go`): NO se abre aquí un segundo
// cliente ni una segunda caché, que sería el mismo error otra vez con otro dato.

// RutaTasasDeAccesos es el endpoint de las tasas. Accesos contesta **200 con `tasa: null`**
// cuando esa sucursal no tiene: que falte es un estado normal, no un error, y por eso no
// viene como 404.
const RutaTasasDeAccesos = "/api/service/tasas"

// ClienteTasas es por dónde se piden las tasas. Interfaz para que las pruebas no tengan
// que levantar un Accesos, igual que `ClienteAccesos`.
type ClienteTasas interface {
	// TasaDeSucursal devuelve (nil, nil) cuando Accesos dice que esa sucursal no tiene.
	TasaDeSucursal(ctx context.Context, codigo string) (*cotizar.Tasa, error)
}

// Tasas es el cliente que usan los manejadores. Variable de paquete por lo mismo que
// `Accesos`: `servidor.go` no se toca en este cambio.
var Tasas ClienteTasas = &tasasDeAccesos{}

// tasasDeAccesos reutiliza la FIRMA del cliente de almacenes. Accesos no acepta una clave
// suelta en una cabecera: cada aplicación firma con SU llave sobre método, ruta, hora,
// nonce y hash del cuerpo. Aquí no se vuelve a escribir esa firma —una segunda copia es
// una segunda forma de que deje de cuadrar—, se usa la que ya hay.
//
// # No guarda un `accesosHTTP` suyo, y esa es la corrección del 16/09/2026
//
// Antes esto era `struct{ firmante accesosHTTP }`: un cliente PROPIO, con su `cfg` a nil.
// La configuración se le pone al cliente en `accesosDelServidor(cfg)`, que rellena **el
// del paquete** (`Accesos`), no éste. Así que este segundo cliente nunca tuvo llave ni
// URL, y todas las llamadas morían antes de salir a la red con:
//
//	Accesos no dio la tasa: se deja la guardada
//	err="el cliente de Accesos no tiene configuración"
//
// O sea: la tasa de cambio NUNCA se pudo leer, de ninguna sucursal, desde que existe el
// refresco. Y no se vio por lo de siempre: el refresco trata «Accesos no contesta» como un
// tropiezo pasajero —no toca lo guardado, que es lo correcto—, y la pantalla acababa
// diciendo «esta sucursal no tiene tasa todavía», que puede ser verdad. Es el MISMO fallo
// que ya se arregló una vez unas líneas más abajo, con la lectura de `tasa: null`, y por
// el mismo motivo se coló: dos sitios distintos, la misma frase creíble al final.
//
// Ahora se pide el cliente YA CONFIGURADO en el momento de usarlo. Dos clientes, uno con
// configuración y otro sin ella, era un fallo esperando a que alguien lo mirara.
type tasasDeAccesos struct{}

// firmante devuelve el cliente de Accesos del paquete, que es el que tiene la
// configuración puesta. Se resuelve AL LLAMAR y no al construir porque cuando se construye
// —una variable de paquete— todavía no se ha leído el entorno.
func (t *tasasDeAccesos) firmante() (*accesosHTTP, error) {
	h, ok := Accesos.(*accesosHTTP)
	if !ok || h == nil {
		// Alguien cambió `Accesos` por un doble pero dejó `Tasas` de verdad. Se dice, en
		// vez de intentarlo con un cliente sin configurar.
		return nil, errors.New("las tasas necesitan el cliente de Accesos del paquete")
	}
	return h, nil
}

func (t *tasasDeAccesos) TasaDeSucursal(ctx context.Context, codigo string) (*cotizar.Tasa, error) {
	firmante, err := t.firmante()
	if err != nil {
		return nil, err
	}
	ruta := RutaTasasDeAccesos + "?codigo=" + url.QueryEscape(codigo)
	crudo, err := firmante.pedirFirmado(ctx, http.MethodGet, ruta, nil, 10*time.Second)
	if err != nil {
		return nil, err
	}
	var b struct {
		Tasa       json.RawMessage `json:"tasa"`
		Codigo     *string         `json:"codigo"`
		CupPorUsd  *float64        `json:"cupPorUsd"`
		TarifaBase *float64        `json:"tarifaBase"`
		Fuente     *string         `json:"fuente"`
		TraidoAt   *string         `json:"traidoAt"`
		Fresca     *bool           `json:"fresca"`
	}
	if err := json.Unmarshal(crudo, &b); err != nil {
		return nil, fmt.Errorf("Accesos contestó algo que no se entiende: %w", err)
	}
	// Dos formas de decir «no hay»: `tasa: null`, o un `cupPorUsd` que no es un número.
	// Sin tasa no se convierte nada, y NO se echa mano de la de otra sucursal.
	//
	// AUSENTE NO ES `null`, y aquí estuvo el fallo. Cuando Accesos SÍ tiene la tasa
	// contesta los campos sueltos —`cupPorUsd`, `fresca`, `traidoAt`— y **no manda ningún
	// campo `tasa`**; ese campo sólo aparece, valiendo `null`, cuando no la tiene. Con la
	// comprobación de antes (`esNuloJSON(b.Tasa)`, que daba true también para el campo
	// ausente) una tasa buena se leía como «no hay», así que este servicio NUNCA pudo
	// leer una tasa, de ninguna sucursal.
	//
	// Y no se vio porque degrada a un estado legítimo: la pantalla decía «esta sucursal
	// no tiene tasa de cambio todavía», que es una frase que puede ser verdad, así que
	// nadie la iba a cuestionar. Por eso la comprobación ahora distingue las dos cosas.
	if (len(b.Tasa) > 0 && esNuloJSON(b.Tasa)) || b.CupPorUsd == nil {
		return nil, nil
	}
	cod := strings.ToUpper(codigo)
	if b.Codigo != nil {
		cod = *b.Codigo
	}
	traido := ""
	if b.TraidoAt != nil {
		traido = *b.TraidoAt
	}
	return &cotizar.Tasa{
		Codigo:    cod,
		CupPorUsd: *b.CupPorUsd,
		// `tarifaBase` sólo si es número; si no, nil. Un 0 se rechaza más adelante en la
		// fórmula, que es donde tiene que rechazarse.
		TarifaBase: b.TarifaBase,
		Fuente:     b.Fuente,
		TraidoAt:   traido,
		// AUSENTE SIGNIFICA FRESCA: `fresca = (b.fresca !== false)`. Quien decide si la
		// tasa está pasada es ACCESOS, no este servicio.
		Fresca: b.Fresca == nil || *b.Fresca,
	}, nil
}

func esNuloJSON(v json.RawMessage) bool {
	s := strings.TrimSpace(string(v))
	return s == "" || s == "null"
}

// CatalogoDePesos baja el catálogo local de pesos (§5) para el lote. Es el RESPALDO: sólo
// se llama cuando alguna línea del lote no trae peso de PEDIDO. Mientras no esté montado,
// esas líneas se quedan sin peso y el lote lo dice en `weightsSource: "none"` — que es
// mejor que un peso inventado, porque con el peso se cobra y se carga el camión.
var CatalogoDePesos func(ctx context.Context) (cotizar.Catalogo, error)

// GuardarPedidoDelEspejo escribe el pedido del lote (§2.3) con sus renglones.
//
// VIENE MONTADA Y NO NIL. Estuvo sin montar un tiempo y el lote contestaba
// `persisted:false, reason:"espejo-no-montado"`: cotizaba bien y no guardaba nada, así que
// la base nueva no tenía ni un pedido. Esta ruta no es un cotizador — es LA PUERTA DE
// ENTRADA de los pedidos, y no hay otra.
//
// Sigue siendo una variable para que una prueba pueda cambiarla; la comprobación de `nil`
// de más abajo se queda porque una prueba que la ponga a nil tiene que degradar diciéndolo
// y no reventar con un puntero.
var GuardarPedidoDelEspejo = func(ctx context.Context, a *alcance.Acotado, p PedidoParaGuardar) (uuid.UUID, error) {
	id, _, err := a.EspejoGuardarPedido(ctx, paraLaBase(p), renglonesParaLaBase(p.Renglones))
	return id, err
}

// recuerdoDeTasas es la caché del proceso (§8): 5 min para una tasa que existe, 20 s para
// el «no hay». Una sola para todo el servicio, porque el lote de 200 pedidos pregunta la
// tasa de su sucursal una vez por pedido.
var recuerdoDeTasas = cotizar.NuevoRecuerdoDeTasas(func(ctx context.Context, codigo string) (*cotizar.Tasa, error) {
	return Tasas.TasaDeSucursal(ctx, codigo)
}, nil)

// almacenesDeCotizacion pide los almacenes con el `.catch(() => [])` que hace la ruta de
// Next: si Accesos falla, la lista queda VACÍA y el camino sigue hasta el 409 con el
// nombre de la sucursal dentro, que es lo que el contrato manda enseñar. Nunca se contesta
// un número aproximado: un importe aproximado se cobra igual que uno bueno.
func almacenesDeCotizacion(ctx context.Context, r *http.Request, codigo string) []cotizar.Almacen {
	crudos, err := Accesos.AlmacenesDeSucursal(ctx, codigo)
	if err != nil {
		httpx.Registro(r).Warn("Accesos no dio los almacenes: se sigue como si no hubiera",
			"sucursal", codigo, "err", err)
		return nil
	}
	// `api.Almacen` es la forma en la que llega de Accesos; `cotizar.Almacen` es la que
	// entiende la fórmula. La traducción va aquí y no en `cotizar` para que ese paquete
	// siga sin saber nada de HTTP ni de Accesos.
	salida := make([]cotizar.Almacen, 0, len(crudos))
	for _, a := range crudos {
		salida = append(salida, deAlmacenDeAccesos(a))
	}
	return salida
}

// recuerdoDeAlmacenesDelLote devuelve una función que trae los almacenes de una sucursal y se
// acuerda de lo que ya preguntó DENTRO DE ESTA TANDA.
//
// Un lote son 200 pedidos de hasta ocho sucursales: sin esto, doscientas vueltas para ocho
// respuestas. Y la lista vacía SE RECUERDA IGUAL —el valor cero de `[]cotizar.Almacen` no
// distingue «no pregunté» de «no hay»—, por eso el recuerdo lleva su propio mapa de
// preguntados: si Accesos está caído, se le pregunta UNA vez por sucursal y no doscientas.
func recuerdoDeAlmacenesDelLote(r *http.Request) func(string) []cotizar.Almacen {
	visto := map[string][]cotizar.Almacen{}
	preguntados := map[string]bool{}
	return func(codigo string) []cotizar.Almacen {
		clave := strings.ToUpper(strings.TrimSpace(codigo))
		if preguntados[clave] {
			return visto[clave]
		}
		preguntados[clave] = true
		visto[clave] = almacenesDeCotizacion(r.Context(), r, codigo)
		return visto[clave]
	}
}

// codigoDelAlmacenDelLote: el código que trae el pedido, o «» cuando no trae almacén.
//
// NO SE CAE AL NOMBRE cuando el código viene vacío, y no es un olvido. `PV-STGO` está en
// Santiago Y en Palma Soriano, y `Tiendas Parranda` en cinco sucursales: emparejar por nombre
// no falla nunca, sólo mide desde el almacén de otro sitio. Sin código se mide desde el
// principal y se dice, que es peor dato y mejor información.
func codigoDelAlmacenDelLote(a *almacenDelPedidoDelLote) string {
	if a == nil {
		return ""
	}
	return a.Codigo
}

// avisarDeLosOrigenesQueNoEran deja UNA línea por tanda con lo que no se midió desde su
// almacén, y sólo si hubo algo. Ver la llamada en `cotizarLote`.
func avisarDeLosOrigenesQueNoEran(r *http.Request, porMotivo map[cotizar.MotivoDelOrigen]int) {
	// SE RECORREN LAS CLAVES QUE HAY, ORDENADAS. Aquí había una lista FIJA de los cinco motivos
	// planos, y **al caso peor no lo contaba nadie** — 26/09/2026, encontrado por el auditor
	// ejecutándolo.
	//
	// El motivo de «no había ni un almacén con punto» sale SIEMPRE COMPUESTO
	// (`sucursal-sin-almacen-con-punto+almacen-no-dado-de-alta` y sus variantes), porque son dos
	// preguntas y las dos tienen respuesta. `MotivoSucursalSinAlmacen` a secas no ocurre nunca,
	// así que comparar por igualdad contra la lista de cinco dejaba fuera justo los pedidos
	// medidos desde las coordenadas de la SUCURSAL. Y peor: una tanda con SÓLO de ésos dejaba
	// `campos` vacío, la función salía por el `return` de abajo y **no había ni una línea en el
	// registro**. El motivo aparte existe precisamente para que el caso peor no sea el invisible,
	// y el contador lo volvía invisible por otra puerta.
	//
	// Ordenar las claves es lo que sustituye a la lista fija: un mapa de Go se recorre en otro
	// orden en cada ejecución, y un aviso con los campos bailando no se puede comparar con el de
	// ayer ni buscar en el registro. Y recorrer lo que HAY, en vez de lo que se espera, hace que
	// un motivo nuevo —o uno compuesto que nadie previó— salga solo en vez de desaparecer.
	//
	// Y EL BUENO NO CUENTA. `almacen-del-pedido` es «se midió desde donde tocaba»: meterlo
	// aquí hacía que el aviso saliera **también cuando la tanda estaba perfecta** —200 de
	// 200 bien y un WARN igual—, que es la otra mitad del mismo fallo. Un aviso que sale
	// siempre deja de leerse, y entonces tampoco se lee el día que de verdad hay algo.
	motivos := make([]string, 0, len(porMotivo))
	malos := 0
	for m, n := range porMotivo {
		if n > 0 && m != cotizar.MotivoAlmacenDelPedido {
			motivos = append(motivos, string(m))
			malos += n
		}
	}
	if malos == 0 {
		return
	}
	sort.Strings(motivos)

	campos := make([]any, 0, 2*len(motivos))
	for _, m := range motivos {
		campos = append(campos, m, porMotivo[cotizar.MotivoDelOrigen(m)])
	}
	if len(campos) == 0 {
		return
	}
	campos = append(campos, "desde_su_almacen", porMotivo[cotizar.MotivoAlmacenDelPedido])
	httpx.Registro(r).Warn("pedidos medidos desde un almacén que no es el suyo: "+
		"mientras esto no sea cero, su kilometraje sale del principal de la sucursal", campos...)
}

// deAlmacenDeAccesos traduce UNA vez lo que da Accesos a lo que entiende la fórmula.
//
// ESTABA ESCRITO DOS VECES —aquí y en `almacenesConPunto` del tablero— y el 26/09/2026 eso
// costó descubrirlo al añadir el `codigo`: una de las dos copias se habría quedado sin
// arrastrarlo y entonces el tablero mediría desde el almacén del pedido y la cotización desde
// el principal, o al revés. Es el mismo modo de fallo del 24/09 (`internal/cotizar/almacen.go`):
// dos copias de una regla se separan, y ésta decide desde dónde se mide lo que se cobra.
func deAlmacenDeAccesos(a Almacen) cotizar.Almacen {
	return cotizar.Almacen{
		ID:        oVacio(a.ID),
		Codigo:    oVacio(a.Codigo),
		Nombre:    a.Nombre,
		Direccion: a.Direccion,
		Latitud:   a.Latitud,
		Longitud:  a.Longitud,
		Principal: a.Principal,
		Activo:    a.Activo,
	}
}

// oVacio: un puntero nulo es la cadena vacía. Vale para `id` y para `codigo`, que Accesos da
// por opcionales los dos. No se llama `textoDe` porque ése ya existe en `pedidos.go` y hace lo
// contrario (texto a puntero).
func oVacio(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

// ---------------------------------------------------------------------------
// Montaje
// ---------------------------------------------------------------------------

// rutasCotizacion monta las cuatro rutas. La llama `Rutas()` en `servidor.go`.
//
// `admin` no se usa: aquí no hay nada reservado a administradores. El lote y el domicilio
// son de SERVICIO (el espejo de PEDIDO, que no es una persona) y `/api/tasa` es de
// cualquiera con sesión, porque es sólo mirar.
func (s *Servidor) rutasCotizacion(rt *httpx.Router, sesion, admin []httpx.Medio) {
	_ = admin

	// La puerta del espejo: `x-api-key`, un actor sintético para que el alcance se pueda
	// resolver, y el alcance. En este orden.
	servicio := []httpx.Medio{
		auth.LlaveDeServicio(s.cfg.ServiceAPIKey),
		soloServicioDeCotizacion,
		s.porteria.Exigir,
	}

	// SIN AUTH Y SIN CUERPO: contesta 410 a todo el mundo. Pedir llave para decir «esto se
	// retiró» sólo consigue que quien todavía llama vea un 401 y crea que es de permisos.
	rt.ManejarFunc(http.MethodPost, "/api/quote", s.cotizadorRetirado)

	rt.ManejarFunc(http.MethodPost, "/api/quote/batch", s.cotizarLote, servicio...)
	rt.ManejarFunc(http.MethodPost, "/api/quote/home-delivery", s.cotizarDomicilio, servicio...)

	rt.ManejarFunc(http.MethodGet, "/api/tasa", s.tasaDelAlcance, sesion...)
}

// soloServicioDeCotizacion cuelga una persona sintética para que la portería pueda resolver el
// alcance: sin persona, `Porteria.Resolver` devuelve error y la ruta daría 500.
//
// SIN SUCURSAL, que es lo que el contrato pide para estas dos rutas («sin alcance por
// sucursal»): el espejo trae pedidos de las ocho y tiene que poder escribirlos todos.
//
// Y SE BORRA LA CABECERA `X-Sucursal-Id` ANTES DE RESOLVER. Si no, quien tenga la llave de
// servicio podría acotarse a una sucursal mandando esa cabecera, y entonces el lote
// nocturno de PEDIDO se comería en silencio los pedidos de las otras siete: cero errores,
// cero pedidos, y nadie mirando.
func soloServicioDeCotizacion(siguiente http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.Header.Del(alcance.CabeceraSucursal)
		// EL ROL VA EXPLÍCITO, y sin él esta ruta lleva rechazando desde el 16/09/2026.
		//
		// Ese día `VeTodasLasSucursales` dejó de ser «no tiene sucursal» y pasó a mirar el
		// ROL, que es como tenía que haber sido siempre: «sin sucursal no es por el tipo
		// de usuario… un usuario sin sucursal ve todas, eso está malísimo». Pero esta
		// persona sintética se quedó sin rol, así que desde entonces no veía NINGUNA
		// sucursal y la portería contestaba 403. El lote de PEDIDO dejó de entrar:
		// **84 rechazos en quince minutos**, todos con 403 y ninguno con una línea que
		// dijera por qué. Se vio mirando el registro del servidor, no la aplicación.
		//
		// Esto NO es «un usuario sin sucursal»: es el propio espejo, que entra por la
		// puerta de la llave de servicio y por definición trae pedidos de las ocho. La
		// regla de Jose es sobre PERSONAS, y la puerta que protege a ésta es la llave, no
		// el alcance. El de `espejo.go` ya lo llevaba puesto; éste se quedó atrás.
		u := &auth.Usuario{ID: "servicio:pedido", Nombre: "servicio", Rol: "SUPER ADMIN"}
		siguiente.ServeHTTP(w, r.WithContext(auth.ConUsuario(r.Context(), u)))
	})
}

// ---------------------------------------------------------------------------
// POST /api/quote — RETIRADO
// ---------------------------------------------------------------------------

// cotizadorRetirado contesta 410 siempre, e ignora el cuerpo por completo.
//
// POR QUÉ 410 Y NO BORRAR LA RUTA: un 404 se lee como «me equivoqué de dirección» y quien
// llamaba se pone a buscar la buena. El 410 con este texto dice lo que pasó y a dónde ir.
// La razón de fondo está en §1: éste era la SEGUNDA fórmula viva del domicilio, y *el
// mismo pedido costaba una cosa entrando por el espejo y otra entrando a mano*.
func (s *Servidor) cotizadorRetirado(w http.ResponseWriter, r *http.Request) {
	httpx.Error(w, r, http.StatusGone, msgCotizadorRetirado)
}

// ---------------------------------------------------------------------------
// POST /api/quote/home-delivery — el costo de UN domicilio
// ---------------------------------------------------------------------------

type cuerpoDomicilio struct {
	SucursalCodigo string         `json:"sucursalCodigo"`
	Lat            cotizar.Numero `json:"lat"`
	Lng            cotizar.Numero `json:"lng"`
	PesoKg         cotizar.Numero `json:"pesoKg"`

	// DE QUÉ ALMACÉN SALE LA MERCANCÍA — 26/09/2026. Es OPCIONAL y ausente se comporta igual
	// que siempre (el principal de la sucursal), así que quien no lo mande no se rompe.
	//
	// SIN ESTE CAMPO, ESTA RUTA NO PODÍA ACERTAR. Es la ÚNICA cuenta de dinero que hace esta
	// API —la APK de Entrega cobra el número que devuelve y lo guarda en PEDIDO— y sólo
	// recibía `sucursalCodigo`, así que medía desde el principal: en Santiago cobraba desde
	// PV-STGO las 2.185 líneas que salen de AURORA. El lote ya mide desde el almacén del
	// pedido; dejar esta ruta como estaba habría puesto en la MISMA tarjeta un kilometraje
	// bueno y un importe malo, sin nada que dijera cuál creer. Eso es peor que los dos mal:
	// dos números que no se pueden conciliar y ninguna pantalla desmintiendo a ninguno.
	AlmacenCodigo string `json:"almacenCodigo"`
}

type domicilioSalida struct {
	DistanciaKm float64 `json:"distanciaKm"`
	PesoKg      float64 `json:"pesoKg"`
	USD         float64 `json:"usd"`
	CUP         float64 `json:"cup"`
	TarifaUsd   float64 `json:"tarifaUsd"`
	Desde       string  `json:"desde"`
	Almacen     *string `json:"almacen"`
	Sucursal    string  `json:"sucursal"`

	// AlmacenCodigo y AlmacenMotivo: desde qué almacén se midió y por qué ése.
	//
	// `almacen` (el nombre) ya estaba, y NO basta: dos almacenes se pueden llamar igual
	// —`PV-STGO` está en Santiago y en Palma Soriano— y, sobre todo, el nombre no dice si
	// se midió desde el que se pidió o desde el principal porque el que se pidió no se pudo
	// usar. Un importe que no se puede explicar es un importe que nadie puede discutir.
	AlmacenCodigo *string `json:"almacenCodigo"`
	AlmacenMotivo string  `json:"almacenMotivo"`
}

// cotizarDomicilio es la única ruta que calcula un importe, y lo calcula con la fórmula de
// Entrega calcada: tarifa base (CUP/km·kg) ÷ tasa × distancia × peso.
//
// LAS VALIDACIONES VAN EN EL ORDEN DEL CONTRATO y no en otro. No es capricho: el mensaje
// que sale es el del PRIMER fallo, y quien lo lee corrige eso. Reordenarlas cambia qué se
// le dice al que llama.
func (s *Servidor) cotizarDomicilio(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}

	c := leerCuerpoDomicilio(r)

	// 1. El código de la sucursal, normalizado. Es la clave que cruza las aplicaciones.
	codigo := strings.ToUpper(strings.TrimSpace(c.SucursalCodigo))
	if codigo == "" {
		httpx.Error(w, r, http.StatusBadRequest, msgFaltaSucursal)
		return
	}
	// 2. La ubicación del cliente.
	if !c.Lat.Finito() || !c.Lng.Finito() {
		httpx.Error(w, r, http.StatusBadRequest, msgFaltaUbicacion)
		return
	}
	// Y TIENE QUE CAER EN EL PLANETA. Ver `msgUbicacionImposibleF`: lo que se tapa aquí no
	// es un error, es un importe equivocado que nadie va a cuestionar.
	if !puntoDelPlaneta(c.Lat.Valor, c.Lng.Valor) {
		httpx.Error(w, r, http.StatusBadRequest, fmt.Sprintf(msgUbicacionImposibleF,
			strconv.FormatFloat(c.Lat.Valor, 'g', -1, 64),
			strconv.FormatFloat(c.Lng.Valor, 'g', -1, 64)))
		return
	}
	// 3. El peso. Aquí sí se exige > 0: un domicilio de 0 kg no es un domicilio, es un
	// pedido al que todavía no se le resolvió el peso, y cotizarlo daría 0 —que se lee
	// como gratis— en vez de decir que falta el dato.
	if !c.PesoKg.Finito() || c.PesoKg.Valor <= 0 {
		httpx.Error(w, r, http.StatusBadRequest, msgFaltaPeso)
		return
	}

	// 4. La sucursal.
	suc, err := sucursalParaCotizar(r.Context(), a, codigo)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if suc == nil {
		httpx.Error(w, r, http.StatusNotFound, fmt.Sprintf(msgSucursalDesconocidaF, codigo))
		return
	}

	// 5. El almacén de origen. ES DESDE DONDE SALE LA MERCANCÍA, que es lo que mide la
	// APK; las coordenadas de la SUCURSAL no valen para esto.
	//
	// Y DESDE EL 26/09/2026 ES EL DEL PEDIDO cuando el que llama lo dice, no el principal de
	// la sucursal. Ver `cuerpoDomicilio.AlmacenCodigo`: mientras hubo un almacén por sucursal
	// las dos cosas eran la misma frase, y dejaron de serlo. Sin `almacenCodigo` se comporta
	// igual que siempre y lo dice en `almacenMotivo`, así que un cliente viejo no cambia de
	// respuesta por este despliegue — pero tampoco acierta, y eso queda escrito en el número
	// que devuelve y no sólo en un informe.
	origen := cotizar.ElegirOrigenDelPedido(
		almacenesDeCotizacion(r.Context(), r, codigo), c.AlmacenCodigo)
	almacen := origen.Almacen
	if almacen == nil {
		// AQUÍ SÍ SE CONTESTA 409, al revés que en el lote, y la diferencia es la de siempre:
		// esto es una cuenta de dinero y el lote es una puerta. Un importe aproximado se cobra
		// igual que uno bueno; un pedido rechazado en la puerta se pierde.
		httpx.Error(w, r, http.StatusConflict, fmt.Sprintf(msgSinAlmacenF, suc.Name))
		return
	}
	// UN ALMACÉN PEDIDO Y NO ENCONTRADO NO ES UN 409, y merece decirse en el registro: el
	// importe sale del principal y quien llama se lo va a cobrar a alguien. El 409 es para
	// «no hay desde dónde medir», no para «no medí desde donde pediste»: eso último sí tiene
	// un número que dar, sólo que peor, y taparlo con un error dejaría sin cotizar los
	// pedidos de un almacén nuevo el día que alguien lo dé de alta en Ventra y no en Accesos.
	if !origen.DelPedido() && strings.TrimSpace(c.AlmacenCodigo) != "" {
		httpx.Registro(r).Warn("se cobra un domicilio desde un almacén que no es el pedido",
			"sucursal", codigo, "pedido", c.AlmacenCodigo,
			"medido_desde", almacen.Nombre, "motivo", string(origen.Motivo))
	}

	// 6 y 7. Tasa y tarifa, las dos de ESTA sucursal. Nunca las de otra: convertir un
	// importe de Granma con la tasa de La Habana da un número creíble que nadie cuestiona.
	tasa := recuerdoDeTasas.DeSucursal(r.Context(), codigo)
	if tasa == nil || tasa.CupPorUsd <= 0 {
		httpx.Error(w, r, http.StatusConflict, fmt.Sprintf(msgSinTasaEnAccesosF, codigo))
		return
	}
	if tasa.TarifaBase == nil {
		httpx.Error(w, r, http.StatusConflict, fmt.Sprintf(msgSinTarifaEnEntregaF, codigo))
		return
	}

	// 8. La cuenta.
	km := cotizar.DistanciaEntre(almacen.Punto(), cotizar.Punto{Lat: c.Lat.Valor, Lng: c.Lng.Valor})
	costo := cotizar.CostoDomicilioEntrega(*tasa.TarifaBase, tasa.CupPorUsd, km, c.PesoKg.Valor)
	if costo == nil {
		// La fórmula devuelve nil y NUNCA cero, así que llegar aquí es «no se sabe».
		httpx.Error(w, r, http.StatusConflict, msgSinCalculo)
		return
	}

	var nombreAlmacen *string
	if almacen.Nombre != "" {
		n := almacen.Nombre
		nombreAlmacen = &n
	}
	var codigoAlmacen *string
	if almacen.Codigo != "" {
		c := almacen.Codigo
		codigoAlmacen = &c
	}
	httpx.JSON(w, r, http.StatusOK, domicilioSalida{
		DistanciaKm: costo.DistanciaKm,
		PesoKg:      costo.PesoKg,
		USD:         costo.USD,
		CUP:         costo.CUP,
		TarifaUsd:   costo.TarifaUsd,
		// `desde` dice con qué se midió, y AHORA LLEVA EL ALMACÉN — 26/09/2026.
		//
		// Decía `almacen:<SUCURSAL>` y su propio comentario prometía que «si mañana se
		// midiera desde otro punto, los importes viejos siguen explicándose solos». Mañana
		// llegó: con varios almacenes por sucursal, `almacen:STG` es la misma cadena para un
		// importe medido desde PV-STGO y para otro medido desde AURORA, así que los dos
		// quedan indistinguibles en el histórico de PEDIDO — que es donde viven los importes
		// cobrados. El campo cuyo único trabajo es explicar de dónde salió el número fallaba
		// exactamente el día en que hacía falta.
		//
		// La forma es `almacen:<SUCURSAL>:<CÓDIGO>`, y sin código se queda en
		// `almacen:<SUCURSAL>` como siempre: así lo viejo sigue leyéndose igual y lo nuevo
		// dice más. Se añade por detrás y no por delante para que quien parta por `:` y coja
		// los dos primeros trozos siga funcionando.
		Desde:         desdeDelDomicilio(codigo, almacen.Codigo),
		Almacen:       nombreAlmacen,
		AlmacenCodigo: codigoAlmacen,
		AlmacenMotivo: string(origen.Motivo),
		Sucursal:      suc.Name,
	})
}

// desdeDelDomicilio arma el `desde`. Ver el comentario del campo en `cotizarDomicilio`.
func desdeDelDomicilio(sucursal, almacen string) string {
	if strings.TrimSpace(almacen) == "" {
		return "almacen:" + sucursal
	}
	return "almacen:" + sucursal + ":" + almacen
}

// leerCuerpoDomicilio decodifica con la tolerancia de la ruta de Next: **si el cuerpo no
// parsea, se sigue con `{}`** y el fallo sale como «Falta sucursalCodigo», que es un
// mensaje que se entiende, en vez de un «cuerpo no válido» que no dice qué falta.
//
// Los tres numéricos arrancan en «no vino» (NaN) a propósito: ver `cotizar.Numero`. Con el
// cero de Go, un `lat` ausente pasaría la validación y se cotizaría desde el golfo de
// Guinea.
func leerCuerpoDomicilio(r *http.Request) cuerpoDomicilio {
	vacio := cuerpoDomicilio{Lat: cotizar.NoVino(), Lng: cotizar.NoVino(), PesoKg: cotizar.NoVino()}
	defer r.Body.Close()
	crudo, err := io.ReadAll(io.LimitReader(r.Body, maxCuerpoCotizacion))
	if err != nil {
		return vacio
	}
	c := vacio
	if err := json.Unmarshal(crudo, &c); err != nil {
		return vacio
	}
	return c
}

// maxCuerpoCotizacion: el mismo tope que `httpx.LeerJSON`. Un lote del espejo cabe de
// sobra; lo que no cabe es el intento de tumbar el proceso a base de memoria.
const maxCuerpoCotizacion = 8 << 20 // 8 MiB

// ---------------------------------------------------------------------------
// GET /api/tasa — qué tasa está usando quien mira
// ---------------------------------------------------------------------------

type tasaVariasSucursales struct {
	Tasa    *float64 `json:"tasa"`   // siempre null
	Motivo  string   `json:"motivo"` // "varias-sucursales"
	Aviso   string   `json:"aviso"`
	SinTasa []string `json:"sinTasa"`
}

type tasaAusente struct {
	Tasa     *float64 `json:"tasa"`   // siempre null
	Motivo   string   `json:"motivo"` // "sin-tasa"
	Sucursal *string  `json:"sucursal"`
	Aviso    string   `json:"aviso"`
}

type tasaPresente struct {
	Tasa     float64 `json:"tasa"`
	Fuente   *string `json:"fuente"`
	TraidoAt string  `json:"traidoAt"`
	Fresca   bool    `json:"fresca"`
	Sucursal *string `json:"sucursal"`
	Aviso    *string `json:"aviso"`
}

// tasaDelAlcance contesta 200 SIEMPRE. Que falte la tasa no es un error de nadie: es un
// estado normal que alguien está arreglando en Entrega, y la pantalla tiene que poder
// enseñar los importes en USD mientras tanto.
func (s *Servidor) tasaDelAlcance(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	sucursales, err := a.ListarSucursalesVisibles(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	// --- Sin alcance: el Super Admin mirando las ocho -------------------------
	//
	// NO se elige ninguna tasa. Enseñar la de una sucursal cualquiera cuando se están
	// viendo todas es justo el error que más daño hace: un importe creíble convertido con
	// la tasa que no era.
	if a.Todas() {
		sin := []string{}
		for _, b := range sucursales {
			if b.ExternalID == nil || strings.TrimSpace(*b.ExternalID) == "" {
				continue // sin código no hay nada que preguntarle a Accesos
			}
			if t := recuerdoDeTasas.DeSucursal(r.Context(), *b.ExternalID); t == nil {
				sin = append(sin, b.Name)
			}
		}
		httpx.JSON(w, r, http.StatusOK, tasaVariasSucursales{
			Motivo: "varias-sucursales", Aviso: avisoVariasSucursales, SinTasa: sin,
		})
		return
	}

	// --- Con alcance ----------------------------------------------------------
	var nombre *string
	if id := a.Sucursal(); id != nil {
		for _, b := range sucursales {
			if b.ID == *id {
				n := b.Name
				nombre = &n
				break
			}
		}
	}

	var tasa *cotizar.Tasa
	if cod := a.Codigo(); cod != nil {
		tasa = recuerdoDeTasas.DeSucursal(r.Context(), *cod)
	}
	if tasa == nil {
		// El sujeto del aviso: el nombre si se sabe, «Esta sucursal» si no.
		quien := sucursalSinNombre
		if nombre != nil && *nombre != "" {
			quien = *nombre
		}
		httpx.JSON(w, r, http.StatusOK, tasaAusente{
			Motivo: "sin-tasa", Sucursal: nombre, Aviso: fmt.Sprintf(avisoSinTasaF, quien),
		})
		return
	}

	// `fresca` la decide ACCESOS, no este servicio. Cuando dice que no, se avisa con la
	// fecha: una tasa de hace tres semanas convierte, pero quien mira tiene que saberlo.
	var aviso *string
	if !tasa.Fresca {
		v := fmt.Sprintf(avisoTasaViejaF, fechaCortaEs(tasa.TraidoAt))
		aviso = &v
	}
	httpx.JSON(w, r, http.StatusOK, tasaPresente{
		Tasa: tasa.CupPorUsd, Fuente: tasa.Fuente, TraidoAt: tasa.TraidoAt,
		Fresca: tasa.Fresca, Sucursal: nombre, Aviso: aviso,
	})
}

// fechaCortaEs imita `new Date(traidoAt).toLocaleDateString('es')`: d/m/aaaa, SIN ceros a la
// izquierda. Si la fecha no se puede leer se devuelve tal cual vino, que es más útil que
// un "Invalid Date" y deja ver qué mandó Accesos.
func fechaCortaEs(iso string) string {
	t, err := time.Parse(time.RFC3339, iso)
	if err != nil {
		return iso
	}
	l := t.Local()
	return fmt.Sprintf("%d/%d/%d", l.Day(), int(l.Month()), l.Year())
}

// ---------------------------------------------------------------------------
// POST /api/quote/batch — el espejo de PEDIDO
// ---------------------------------------------------------------------------

type cuerpoLote struct {
	// `preview` se compara como TRUTHY, no como booleano estricto: en la de Next vale
	// tanto `true` como `1` o `"si"`. Por eso llega crudo.
	Preview json.RawMessage `json:"preview"`
	// `useWarehouseWeights !== false`: ausente o null SÍ deja bajar el catálogo.
	UseWarehouseWeights *bool `json:"useWarehouseWeights"`
	// Puntero para poder distinguir «no vino» de «vino vacío»: sin `orders` es un 400,
	// con `orders: []` es un lote de cero pedidos, que es legítimo.
	Orders *[]pedidoDelLote `json:"orders"`
}

type pedidoDelLote struct {
	ExternalID         string            `json:"externalId"`
	OperationNumber    string            `json:"operationNumber"`
	SucursalExternalID string            `json:"sucursalExternalId"`
	CustomerName       string            `json:"customerName"`
	Address            string            `json:"address"`
	Phone              string            `json:"phone"`
	Lat                *float64          `json:"lat"`
	Lng                *float64          `json:"lng"`
	Weight             cotizar.Numero    `json:"weight"`
	RequiereDomicilio  *bool             `json:"requiereDomicilio"`
	OrderDate          *string           `json:"orderDate"`
	Archivado          *bool             `json:"archivado"`
	PedidoCosto        *float64          `json:"pedidoCosto"`
	Municipio          *string           `json:"municipio"`
	Vendedor           *string           `json:"vendedor"`
	Items              []cotizar.Renglon `json:"items"`

	// `pedidoUpdatedAt` NO ES UN CAMPO MÁS: es la MARCA DE AGUA del espejo.
	//
	// El espejo pide `since = max(pedido_updated_at)` de lo que ya tiene. Si este campo no
	// se leyera aquí, la columna se quedaría siempre en NULL, el `since` no existiría
	// nunca y cada ciclo volvería a barrerse el año entero — 56.000 pedidos cada minuto
	// por la conexión de allá, para traer las cuatro filas que se movieron.
	PedidoUpdatedAt *string `json:"pedidoUpdatedAt"`

	// El estado y la fecha comprometida, copiados de PEDIDO para poder FILTRAR. Dentro de
	// un JSON no se filtra sin leerse y descartar los cincuenta mil pedidos enteros.
	Estado            *string `json:"estado"`
	FechaComprometida *string `json:"fechaComprometida"`

	// El cotejo contra la FACTURA, tal como lo dejó PEDIDO. Lo hace PEDIDO —el pedido es
	// suyo— y aquí sólo se copia: el armador ofrece por defecto los que cuadran, porque
	// cargar el camión con un pedido que la factura cambió es descuadrar la caja.
	//
	// `facturaDomicilio` es además la señal MÁS FIABLE de que va a domicilio: sale del
	// mostrador y no de una casilla marcada al tomar el pedido.
	FacturaEstado      *string  `json:"facturaEstado"`
	FacturaNumero      *string  `json:"facturaNumero"`
	FacturaAt          *string  `json:"facturaAt"`
	FacturaDomicilio   *float64 `json:"facturaDomicilio"`
	FacturaCorregidoAt *string  `json:"facturaCorregidoAt"`
	// DE DÓNDE SON LOS RENGLONES: `factura` o `pedido`.
	//
	// PEDIDO manda las líneas de la FACTURA en cuanto hay una cotejada y atada a este
	// pedido —descartando las que se pidieron y no se facturaron, para que nadie cargue un
	// hueco—. O sea que los kg y las unidades que llegan aquí ya son los que suben al
	// camión. Lo que faltaba era decirlo: en pantalla salía «Cambió en la factura» y nada
	// más, y quien mira un número no sabe cuál de los dos tiene delante.
	//
	// NO se deduce de `facturaEstado`: un `cambiado` cuyo cotejo no pudo atar la factura a
	// ESTE pedido se queda con las del pedido, y un `igual` también trae las de la factura.
	// Son dos preguntas distintas. Ver `00009_de_donde_son_los_renglones.sql`.
	ItemsOrigen *string `json:"itemsOrigen"`

	// DE QUÉ ALMACÉN SALE EL PEDIDO. Es lo que decide DESDE DÓNDE se mide la distancia, y de
	// esa distancia sale el costo del domicilio. Ver `almacenDelPedidoDelLote`.
	Almacen *almacenDelPedidoDelLote `json:"almacen"`

	// `meta` LLEGA Y NO SE GUARDA, a propósito. El esquema nuevo no tiene columnas JSON
	// (decisión 0 de la migración): lo que hace falta de PEDIDO se extrae a su columna, y
	// guardar además el documento entero «por si acaso» es tener el mismo dato en dos
	// sitios y no saber cuál manda. Se lee aquí sólo para no romper a quien lo manda.
	Meta json.RawMessage `json:"meta"`
}

// almacenDelPedidoDelLote es el almacén que trae el pedido, con la forma acordada con la
// sesión de PEDIDO el 26/09/2026:
//
//	"almacen": { "codigo": "2", "nombre": "AURORA", "sucursalCodigo": "STG", "mezclado": false }
//
// `Mezclado` es PUNTERO y `Codigo`/`Nombre` no: un `almacen` que llega sin `mezclado` no
// afirma que el pedido salga de un solo almacén —eso es un dato que nadie comprobó— y la
// columna se queda NULL. Los textos vacíos no hace falta distinguirlos del ausente: vacío y
// ausente significan lo mismo, «no se sabe de qué almacén sale».
type almacenDelPedidoDelLote struct {
	Codigo         string `json:"codigo"`
	Nombre         string `json:"nombre"`
	SucursalCodigo string `json:"sucursalCodigo"`
	Mezclado       *bool  `json:"mezclado"`
}

type sucursalDelLote struct {
	ID   uuid.UUID `json:"id"`
	Name string    `json:"name"`
}

type baseDelLote struct {
	Ref        *string         `json:"ref"`
	Status     string          `json:"status"`
	Reason     string          `json:"reason,omitempty"`
	DistanceKm float64         `json:"distanceKm"`
	WeightKg   float64         `json:"weightKg"`
	Branch     sucursalDelLote `json:"branch"`
	OrderID    *string         `json:"orderId,omitempty"`
	Persisted  *bool           `json:"persisted,omitempty"`

	// DESDE DÓNDE SE MIDIÓ ESE `distanceKm`, y por qué. Va en la respuesta y no sólo en la
	// columna porque quien lo tiene que arreglar está al otro lado: PEDIDO ve el resultado de
	// cada pedido que manda, y el webhook lo repite en su motivo. Un kilometraje medido desde
	// el principal porque el almacén no estaba dado de alta es, sin esto, indistinguible de
	// uno bueno — mismos decimales, misma tarjeta, y nadie sospechando.
	//
	// `AlmacenDesde` es el NOMBRE del almacén desde el que se midió, o nil cuando no se midió
	// desde ninguno (entonces salió del punto de la sucursal y el motivo lo dice).
	AlmacenDesde  *string `json:"almacenDesde,omitempty"`
	AlmacenMotivo string  `json:"almacenMotivo,omitempty"`
}

// loteCotizado es el resultado de un pedido que SÍ lleva domicilio. `price` se emite
// siempre y siempre vale null: delivery ya no cotiza. Un 0 ahí se suma, se ordena y se lee
// como «este domicilio es gratis», que es peor que decir que no se sabe.
type loteCotizado struct {
	baseDelLote
	Price *float64 `json:"price"`
}

// loteSaltado es el resultado de los rechazos de los pasos 1 a 4: ni distancia, ni peso,
// ni sucursal, porque justamente es lo que no se pudo resolver.
type loteSaltado struct {
	Ref    *string `json:"ref"`
	Status string  `json:"status"`
	Reason string  `json:"reason"`
}

type loteSalida struct {
	Total         int    `json:"total"`
	Quoted        int    `json:"quoted"`
	Persisted     int    `json:"persisted"`
	Skipped       int    `json:"skipped"`
	WeightsSource string `json:"weightsSource"`
	Currency      string `json:"currency"`
	Results       []any  `json:"results"`
}

// cotizarLote es el espejo: PEDIDO manda tandas de pedidos y aquí se les resuelve el peso
// y la distancia, y se guardan.
//
// NO SE LES PONE PRECIO. `price` es null en todos, siempre. Lo que se cobra es
// `pedidoCosto`, el costo que la APK de Entrega escribió EN PEDIDO.
func (s *Servidor) cotizarLote(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	// CUÁNDO EMPEZÓ, para poder apuntar cuánto tardó la tanda. Ver `apuntarLaRecepcion`.
	arranqueDelLote := time.Now()

	var c cuerpoLote
	defer r.Body.Close()
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxCuerpoCotizacion))
	if err := dec.Decode(&c); err != nil || c.Orders == nil {
		httpx.Error(w, r, http.StatusBadRequest, msgLoteSinPedidos)
		return
	}
	pedidos := *c.Orders
	preview := esVerdaderoJS(c.Preview)

	// --- El catálogo de pesos, sólo si hace falta -----------------------------
	//
	// Se baja ÚNICAMENTE si alguna línea del lote no trae peso de PEDIDO. Bajarlo siempre
	// es traerse el catálogo entero de Ventra por la conexión de allá para no usarlo.
	faltaAlgunPeso := false
	for _, p := range pedidos {
		for _, it := range p.Items {
			if !it.PesoLineaKg.Positivo() && !it.PesoKg.Positivo() {
				faltaAlgunPeso = true
				break
			}
		}
		if faltaAlgunPeso {
			break
		}
	}
	var catalogo cotizar.Catalogo
	// `useWarehouseWeights !== false`: ausente o null deja bajarlo.
	quiereCatalogo := c.UseWarehouseWeights == nil || *c.UseWarehouseWeights
	if faltaAlgunPeso && quiereCatalogo && CatalogoDePesos != nil {
		if cat, err := CatalogoDePesos(r.Context()); err != nil {
			httpx.Registro(r).Warn("no se pudo bajar el catálogo de pesos: se sigue sin él", "err", err)
		} else {
			catalogo = cat
		}
	}
	// `'warehouse'` está declarado en el contrato pero no se emite nunca; se conserva la
	// rareza porque hay quien lee este campo.
	fuentePesos := "pedido"
	if faltaAlgunPeso {
		fuentePesos = "none"
		if catalogo != nil {
			fuentePesos = "mixto"
		}
	}

	// --- Las sucursales, indexadas por su código ------------------------------
	//
	// Una sola lectura para todo el lote. En la de Next esto era un `findUnique` por
	// pedido con caché por `externalId`; con 200 pedidos y ocho sucursales, traerlas de
	// golpe es lo mismo y se lee mejor.
	sucursales, err := a.ListarSucursalesVisibles(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	porCodigo := map[string]sqlc.ListarSucursalesRow{}
	for _, b := range sucursales {
		if b.ExternalID != nil {
			porCodigo[*b.ExternalID] = b
		}
	}

	// --- LOS ALMACENES, UNA VEZ POR SUCURSAL Y NO UNA POR PEDIDO -------------
	//
	// De aquí sale DESDE DÓNDE se mide cada pedido, que es el arreglo del 26/09/2026. Se
	// recuerda por código dentro de la tanda: un lote son 200 pedidos de ocho sucursales, y
	// preguntar por cada uno sería doscientas vueltas para ocho respuestas. El cliente de
	// Accesos además ya recuerda la lista cinco minutos (`ALMACENES_CACHE_MS`), así que esto
	// es la segunda red, no la única.
	//
	// ACCESOS CAÍDO NO CORTA EL LOTE. `almacenesDeCotizacion` devuelve la lista vacía y lo
	// avisa en el registro; el pedido se mide entonces desde el punto de la sucursal y lo dice
	// en su motivo. Aquí no se puede hacer lo que hace `/api/quote/home-delivery` —contestar
	// 409 antes que dar un número aproximado— porque esto no es un cotizador: es LA PUERTA de
	// los pedidos, y un pedido rechazado en la puerta es un pedido perdido.
	almacenesDeLaSucursal := recuerdoDeAlmacenesDelLote(r)

	// LO QUE NO SE MIDIÓ DESDE SU ALMACÉN, contado por motivo para decirlo UNA vez al final.
	// Una línea de registro por pedido son doscientas por tanda y cada minuto: un registro que
	// no se puede leer es un registro que nadie lee, y entonces el día que aparezca un almacén
	// nuevo tampoco se va a leer.
	porMotivo := map[cotizar.MotivoDelOrigen]int{}

	salida := loteSalida{
		// `quoted` es SIEMPRE 0: la variable se declara y nunca se incrementa. Está
		// inventariado en el contrato, así que se conserva la rareza en vez de
		// «arreglarla» y romper a quien la lee.
		Quoted:        0,
		WeightsSource: fuentePesos,
		Currency:      "USD",
		Results:       []any{},
	}

	for _, p := range pedidos {
		salida.Total++
		ref := refDelPedidoDelLote(p)

		// 1. Sin coordenadas no hay reparto posible: no se puede ordenar la ruta ni medir
		//    la distancia. `== null` flojo: un 0 es una coordenada válida.
		if p.Lat == nil || p.Lng == nil {
			salida.Skipped++
			salida.Results = append(salida.Results, loteSaltado{ref, "skipped", "sin-geolocalizacion"})
			continue
		}
		// 2. La sucursal tiene que estar mapeada, o el pedido no es de nadie.
		suc, hay := porCodigo[p.SucursalExternalID]
		if p.SucursalExternalID == "" || !hay {
			salida.Skipped++
			salida.Results = append(salida.Results, loteSaltado{ref, "skipped", "sucursal-no-mapeada"})
			continue
		}
		// 3. Sin punto de partida no se puede armar ruta desde esa sucursal.
		if !suc.OriginConfigured {
			salida.Skipped++
			salida.Results = append(salida.Results, loteSaltado{ref, "skipped", "sucursal-sin-punto-de-partida"})
			continue
		}
		// 4. Sin domicilio Y sin factura cotejada: no se guarda nada. Un pedido así no va
		//    a salir en ningún camión y ocuparía sitio en la lista del logístico.
		//
		// LA FACTURA COTEJADA SON DOS ESTADOS, NO UNO — 28/09/2026, y esto congeló un
		// tercio del espejo durante semanas sin dar un solo error.
		//
		// Aquí decía `== "igual"` a secas. Pero cotejada son **`igual` Y `cambiado`**: en
		// todo el resto de este proyecto la condición es `factura_estado IN
		// ('igual','cambiado')` —el armador de rutas, el panel, el pre-despacho— y el
		// propio `soloRepartibles` de PEDIDO usa ese mismo par. `cambiado` significa que la
		// factura existe y difiere del pedido, no que no haya factura.
		//
		// El efecto, con un pedido de MOSTRADOR (`requiereDomicilio = false`):
		//
		//   1. entra en el espejo el día que su factura está en `igual`;
		//   2. PEDIDO la coteja después y la pasa a `cambiado`;
		//   3. **desde ese momento, TODOS los barridos lo tiran aquí** — y su fila se queda
		//      congelada con lo que hubiera el primer día. No sólo el peso: `factura_estado`
		//      también, y cualquier otro campo que cambie después.
		//
		// Se vio el 28/09/2026 buscando por qué 81 renglones no tenían peso: tras TRES
		// barridos seguían siendo 81, producto por producto idénticos, y el `updated_at` de
		// esos pedidos no se movía. PEDIDO demostró que los servía con el peso puesto por
		// todos los caminos —por id, por rango de fechas y con el filtro puesto—, así que la
		// pérdida estaba entre la respuesta y la escritura. Estaba aquí.
		//
		// Y el aviso encima MENTÍA: decía `sin-domicilio-y-sin-factura` sobre pedidos que
		// tienen factura, así que quien leyera el log iba a buscar donde no era.
		sinDomicilio := p.RequiereDomicilio != nil && !*p.RequiereDomicilio
		if esMostradorSinFactura(p.RequiereDomicilio, p.FacturaEstado) {
			salida.Skipped++
			salida.Results = append(salida.Results, loteSaltado{ref, "skipped", "sin-domicilio-y-sin-factura"})
			continue
		}

		// 5. Peso y distancia.
		pesos := cotizar.PesosDeRenglones(p.Items, catalogo)
		peso := pesos.Total
		if !(peso > 0) {
			// Un total de 0 se considera «no resuelto» y cede al peso que trajo el
			// pedido. Un cero de verdad no existe: diría que en el camión cabe todo.
			peso = p.Weight.O(0)
		}

		// 5-bis. DESDE DÓNDE SE MIDE — y es el arreglo del 26/09/2026.
		//
		// # QUÉ HABÍA AQUÍ Y POR QUÉ ESTABA MAL, dos fallos encajados
		//
		// Ponía `cotizar.DistanciaHaversineKm(suc.Lat, suc.Lng, ...)`: desde el punto de la
		// SUCURSAL. O sea que `delivery_distance_km` —la columna de los ~5.500 pedidos, la que
		// sale en la tarjeta y por la que filtra «Hasta N km»— no salía de ningún almacén,
		// mientras `/api/quote/home-delivery`, el tablero y la lista de Clientes sí medían
		// desde el almacén (`ElegirAlmacen`). CUATRO consumidores y dos orígenes: es el mismo
		// fallo del 24/09 que cuenta `internal/cotizar/almacen.go` —«el mismo botón, dos
		// orígenes y dos kilometrajes»— una capa más abajo, y el punto de la sucursal *no es
		// el sitio del que sale la carga* (§10 de `reglas-negocio.md`).
		//
		// Y encima de eso, el fallo caro: los otros tres medían desde el PRINCIPAL de la
		// sucursal, que mientras hubo un almacén por sucursal era el único. Ya no. Contado por
		// la sesión de PEDIDO el 26/09/2026:
		//
		//	SANTIAGO    2.185 líneas desde AURORA · 804 desde PV-STGO · 11 desde PTO MONEDERO
		//	CAMAGÜEY    2.778 desde PV CAMAGÜEY   · 183 desde FLORIDA · 39 desde ALM CAMAGÜEY
		//	GUANTÁNAMO  2.060 desde PV GTMO       · 940 desde ALM CENTRAL
		//
		// En Santiago **dos de cada tres pedidos salen de AURORA** y se medían desde PV-STGO.
		//
		// # LO QUE ESTO CAMBIA Y HAY QUE SABER ANTES DE DESPLEGAR
		//
		// `delivery_distance_km` no es sólo un número que se enseña: `GET /api/orders` descarta
		// los que pasan de `kmMax` (`pedidos.go`). Al mover el origen, un pedido que hoy sale
		// en la lista puede dejar de salir, y al revés. No es «el número mejoró»: es una lista
		// que cambia de contenido tras el despliegue. Lo fija
		// `TestElFiltroDeKmSeMueveConElOrigen`.
		origen := cotizar.ElegirOrigenDelPedido(
			almacenesDeLaSucursal(p.SucursalExternalID), codigoDelAlmacenDelLote(p.Almacen))
		porMotivo[origen.Motivo]++

		var km float64
		if origen.Almacen != nil {
			km = cotizar.DistanciaEntre(origen.Almacen.Punto(),
				cotizar.Punto{Lat: *p.Lat, Lng: *p.Lng})
		} else {
			// EL ÚLTIMO RECURSO, y va con su propio motivo para que no se confunda con los
			// demás: aquí no se midió desde ningún almacén, se midió desde el punto de la
			// sucursal. Es lo único que queda cuando esa sucursal no tiene ni un almacén con
			// coordenadas, y es el caso que un `409` taparía a costa de perder el pedido.
			km = cotizar.DistanciaHaversineKm(suc.Lat, suc.Lng, *p.Lat, *p.Lng)
		}

		base := baseDelLote{
			Ref: ref, Status: "quoted", DistanceKm: km, WeightKg: peso,
			Branch:        sucursalDelLote{ID: suc.ID, Name: suc.Name},
			AlmacenMotivo: string(origen.Motivo),
		}
		if origen.Almacen != nil && origen.Almacen.Nombre != "" {
			n := origen.Almacen.Nombre
			base.AlmacenDesde = &n
		}
		if sinDomicilio {
			// 6. Llega aquí con la factura cotejada: se guarda igual —hace falta para las
			//    rutas y para la capacidad del camión— pero marcado como sin domicilio.
			//    OJO: estos NO cuentan en `skipped`, sólo los de los pasos 1 a 4.
			base.Status = "skipped"
			base.Reason = "sin-domicilio"
		}

		// 7. En vista previa no se escribe nada.
		if preview {
			salida.Results = append(salida.Results, resultadoDelLote(base, sinDomicilio))
			continue
		}
		// 8. Sin nombre de cliente no se guarda: el nombre es lo que el chofer busca en la
		//    puerta, y una fila sin él no se puede repartir.
		if p.CustomerName == "" {
			no := false
			base.Persisted = &no
			base.Reason = "falta-customerName"
			salida.Results = append(salida.Results, resultadoDelLote(base, sinDomicilio))
			continue
		}
		// 9. Persistencia idempotente por (source='pedido', externalId).
		if GuardarPedidoDelEspejo == nil {
			// El manejador del espejo todavía no está montado. Se COTIZA igual —que es lo
			// que esta ruta sabe hacer— y se dice que no se guardó, en vez de contestar
			// `persisted: true` sobre algo que no se escribió.
			httpx.Registro(r).Error("el lote cotiza pero no persiste: falta montar GuardarPedidoDelEspejo")
			no := false
			base.Persisted = &no
			base.Reason = "espejo-no-montado"
			salida.Results = append(salida.Results, resultadoDelLote(base, sinDomicilio))
			continue
		}
		id, err := GuardarPedidoDelEspejo(r.Context(), a, armarPedidoDelLote(p, suc, pesos, peso, km, origen))
		if err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
		texto := id.String()
		si := true
		base.OrderID = &texto
		base.Persisted = &si
		salida.Persisted++
		salida.Results = append(salida.Results, resultadoDelLote(base, sinDomicilio))
	}

	if salida.Persisted > 0 {
		// El aviso a las pantallas va FUERA de toda escritura y sin mirar lo que devuelve:
		// un aviso perdido no puede tumbar una importación de mil pedidos. Y no lleva los
		// datos dentro —dice «los pedidos cambiaron», no cuáles—, así que quien lo reciba
		// volverá a pedir la lista y ESA sí va acotada por sucursal.
		s.AvisarCambio(CambioPedidos, map[string]any{"pedidos": salida.Persisted})
	}
	// LO QUE NO SE MIDIÓ DESDE SU ALMACÉN, DICHO UNA VEZ.
	//
	// `CLAUDE.md` §4: nada se descarta en silencio. Estos pedidos NO se descartan —están
	// guardados y medidos desde donde se pudo— pero el motivo tiene que salir por algún sitio
	// que una persona mire, y el registro de la tanda es el primero. El segundo es la vista
	// `almacenes_del_pedido_sin_medir` (00012), que es la que aguanta días.
	//
	// `almacen-del-pedido` NO se avisa: es lo normal, y un aviso que sale siempre deja de
	// leerse — y entonces tampoco se lee el día que importa (`CLAUDE.md` §3-quinquies).
	avisarDeLosOrigenesQueNoEran(r, porMotivo)

	// LA TANDA, APUNTADA. Es la mitad de «ver cómo está funcionando el webhook».
	//
	// Los pedidos ya quedan guardados, sí — pero cuando uno NO aparece en el reparto, sin
	// esto no hay forma de saber de quién es el problema: si PEDIDO no lo mandó, si lo
	// mandó y se saltó, o si llegó y se escribió mal. La respuesta era «mira los logs del
	// contenedor», que es no tener respuesta.
	s.apuntarLaRecepcion(r, a, salida, time.Since(arranqueDelLote))

	httpx.JSON(w, r, http.StatusOK, salida)
}

// resultadoDelLote añade el `price` (siempre null) a los que llevan domicilio. Los de
// `sin-domicilio` no lo llevan: no es que su precio sea desconocido, es que no hay
// domicilio que cobrar.
func resultadoDelLote(base baseDelLote, sinDomicilio bool) any {
	if sinDomicilio {
		return base
	}
	return loteCotizado{baseDelLote: base}
}

// refDelPedidoDelLote es `externalId || operationNumber || null`. Es con lo que PEDIDO reconoce
// cada resultado en la respuesta, así que la cadena vacía NO vale: sería un `ref` que
// parece puesto y no identifica nada.
// facturaCotejada: los DOS estados en que la factura existe y se puede repartir.
//
// `igual` es «la factura dice lo mismo que el pedido» y `cambiado` es «existe y difiere».
// Los dos son factura. El que NO lo es —`sin_factura`— y el nulo, que es «nadie la ha
// cotejado todavía», se quedan fuera.
//
// Está aquí como función y no escrito a mano en el `if` para que no vuelva a pasar lo de
// arriba: la próxima vez que alguien necesite esta pregunta, la encuentra.
// esMostradorSinFactura: la regla del punto 4, entera y en un sitio que se puede probar.
//
// Está aquí fuera y no escrita dentro del `for` porque el `for` necesita un servidor, una
// base y un catálogo para correr, y entonces la regla no tiene prueba propia — que es
// exactamente cómo el `== "igual"` de arriba aguantó semanas congelando un tercio del
// espejo sin que nada se pusiera rojo.
//
// `requiereDomicilio` es TRI-ESTADO: `true`, `false` y nil («nadie lo ha marcado»). Sólo un
// `false` explícito es mostrador; el nil se queda dentro, porque descartar por lo que no se
// sabe es descartar de verdad.
func esMostradorSinFactura(requiereDomicilio *bool, facturaEstado *string) bool {
	sinDomicilio := requiereDomicilio != nil && !*requiereDomicilio
	return sinDomicilio && !facturaCotejada(facturaEstado)
}

func facturaCotejada(estado *string) bool {
	if estado == nil {
		return false
	}
	return *estado == "igual" || *estado == "cambiado"
}

func refDelPedidoDelLote(p pedidoDelLote) *string {
	if p.ExternalID != "" {
		v := p.ExternalID
		return &v
	}
	if p.OperationNumber != "" {
		v := p.OperationNumber
		return &v
	}
	return nil
}

// esVerdaderoJS aplica la verdad de JavaScript a un valor crudo: false, 0, "", null y el campo
// ausente son falsos; todo lo demás es verdadero (incluido `"false"`, que es una cadena no
// vacía — sí, en JavaScript eso es `true`).
func esVerdaderoJS(v json.RawMessage) bool {
	s := strings.TrimSpace(string(v))
	switch s {
	case "", "null", "false", `""`, "undefined":
		return false
	}
	// Cualquier número que valga 0 es falso (0, -0, 0.0, 0e5). El resto, verdadero.
	// Ojo con la cadena `"0"`: en JavaScript es una cadena NO vacía y por tanto VERDADERA,
	// y por eso se mira aquí el número crudo y no el texto entrecomillado.
	if n, err := strconv.ParseFloat(s, 64); err == nil {
		return n != 0
	}
	return true
}

// ---------------------------------------------------------------------------
// El pedido armado para el espejo (§2.3 `buildOrderData`)
// ---------------------------------------------------------------------------

// PedidoParaGuardar es el pedido ya resuelto, listo para escribir. Lo consume el manejador
// del espejo de PEDIDO.
//
// Se arma AQUÍ y no allí porque las reglas que no son mapeo trivial —el peso resuelto, la
// dirección de respaldo, el precio nulo, el texto de productos— son parte de la
// cotización y están en §2.3.
type PedidoParaGuardar struct {
	ExternalID      *string // `externalId || operationNumber || null`
	Source          string  // "pedido", fijo
	BranchID        uuid.UUID
	OperationNumber *string

	CustomerName  string
	CustomerPhone *string
	// Address nunca va vacío: `address || customerName`. Una fila sin dirección no se
	// puede repartir, y el nombre al menos se puede preguntar.
	Address    string
	EndAddress *string // `address || null`: aquí sí puede faltar
	// Los cuatro se llenan con la MISMA coordenada del cliente (§2.3).
	Lat, Lng, EndLat, EndLng float64

	// Weight es el peso ya resuelto. 0 = SIN PESO RESUELTO, y así entra al generador de
	// rutas (capacidad del camión). No es «no pesa».
	Weight float64
	// DeliveryDistanceKm son los km en línea recta de la sucursal al cliente.
	DeliveryDistanceKm float64
	// DeliveryPrice es SIEMPRE nil: delivery ya no cotiza. Lo que se cobra es PedidoCosto.
	DeliveryPrice *float64

	// Renglones son las líneas del pedido con el peso ya resuelto. Van a la tabla
	// `order_items`, una fila por línea.
	//
	// YA NO SON UN JSON, y con ellos se fue `productosTexto`: aquella era una copia a mano
	// de los nombres en texto plano, metida al lado del JSON para poder responder a «¿qué
	// pedidos llevan malta?» sin leerse los cincuenta mil pedidos enteros. Con los
	// renglones en su tabla se pregunta por el nombre y ya está —hay un índice de texto
	// para eso—, y un dato copiado en dos sitios acaba discrepando.
	Renglones []cotizar.RenglonPesado

	OrderDate         *time.Time
	PedidoUpdatedAt   *time.Time // la MARCA DE AGUA del espejo; ver `pedidoDelLote`
	Estado            *string
	FechaComprometida *time.Time
	RequiereDomicilio *bool // tri-estado: true / false / desconocido
	Archivado         bool
	PedidoCosto       *float64 // el costo que la APK puso EN PEDIDO. NO es DeliveryPrice.

	FacturaEstado      *string
	FacturaNumero      *string
	FacturaAt          *time.Time
	FacturaDomicilio   *float64
	FacturaCorregidoAt *time.Time
	// ItemsOrigen: `factura` | `pedido` | nil. De donde salieron los renglones de arriba.
	// No se deduce de FacturaEstado: son dos preguntas distintas y confundirlas hace que
	// la pantalla afirme algo que nadie comprobo. Ver `00009_de_donde_son_los_renglones`.
	ItemsOrigen *string

	Municipio      *string
	Vendedor       *string
	SucursalCodigo *string

	// EL ALMACÉN DEL QUE SALE, y desde dónde se midió de verdad. Migración 00012.
	//
	// Los cuatro primeros son lo que mandó PEDIDO, COPIADO TAL CUAL —también cuando ese
	// almacén no está dado de alta en Accesos—: si se tirara, lo único que quedaría del
	// `28 · PTO MONEDERO` de Santiago sería un kilometraje medido desde otro sitio, sin una
	// sola pista de por qué. `AlmacenMotivo` es la confesión: DESDE DÓNDE se midió y POR QUÉ.
	AlmacenCodigo   *string
	AlmacenNombre   *string
	AlmacenSucursal *string
	AlmacenMezclado *bool
	AlmacenMotivo   *string
}

func armarPedidoDelLote(
	p pedidoDelLote, suc sqlc.ListarSucursalesRow, pesos cotizar.PesosResueltos,
	peso, km float64, origen cotizar.OrigenDelPedido,
) PedidoParaGuardar {
	// LA COMILLA DE EXCEL SE QUITA EN LA PUERTA — 28/09/2026.
	//
	// El 28/09/2026 un teléfono salía en pantalla como `'+53 5 2675220`. La comilla la pone
	// Excel delante de un número para que no lo convierta, y se coló hasta la pantalla del
	// cajón de mover un pedido. Se limpia AQUÍ, en la puerta, porque `/api/quote/batch` es
	// por donde entra TODO pedido de PEDIDO —el que trae el espejo y el que empuja el canal
	// firmado—: limpiarlo en un consumidor deja sucios a los otros.
	//
	// `internal/espejo` lo quita además en su `textoONada`, y las dos capas hacen falta: la
	// del espejo protege lo que el espejo copia, ésta protege la puerta venga quien venga.
	//
	// La regla es deliberadamente corta y sólo dispara sobre lo que no puede ser un nombre
	// —ver [espejo.SinLaComillaDeExcel]—, y NO toca `externalId`, que es la identidad.
	direccion := espejo.SinLaComillaDeExcel(strings.TrimSpace(p.Address))
	nombre := espejo.SinLaComillaDeExcel(strings.TrimSpace(p.CustomerName))
	// `address || customerName`: nunca vacío.
	if direccion == "" {
		direccion = nombre
	}

	out := PedidoParaGuardar{
		ExternalID:      refDelPedidoDelLote(p),
		Source:          "pedido",
		BranchID:        suc.ID,
		OperationNumber: aTexto(espejo.SinLaComillaDeExcel(strings.TrimSpace(p.OperationNumber))),
		CustomerName:    nombre,
		CustomerPhone:   aTexto(espejo.SinLaComillaDeExcel(strings.TrimSpace(p.Phone))),
		Address:         direccion,
		EndAddress:      aTexto(espejo.SinLaComillaDeExcel(strings.TrimSpace(p.Address))),
		// Los cuatro con la coordenada del cliente. Ya se comprobó que no son nil.
		Lat: *p.Lat, Lng: *p.Lng, EndLat: *p.Lat, EndLng: *p.Lng,
		Weight:             peso,
		DeliveryDistanceKm: km,
		// COMPARACIÓN ESTRICTA CON false: un `requiereDomicilio` ausente o null NO anula
		// el precio. Y como delivery ya no cotiza, aquí es nil en los dos casos.
		DeliveryPrice:     nil,
		Renglones:         pesos.Renglones,
		RequiereDomicilio: p.RequiereDomicilio,
		// `archivado === true` estricto: por defecto false.
		Archivado:        p.Archivado != nil && *p.Archivado,
		PedidoCosto:      p.PedidoCosto,
		Estado:           p.Estado,
		FacturaEstado:    p.FacturaEstado,
		FacturaNumero:    limpioOpcional(p.FacturaNumero),
		FacturaDomicilio: p.FacturaDomicilio,
		Municipio:        limpioOpcional(p.Municipio),
		Vendedor:         limpioOpcional(p.Vendedor),
		SucursalCodigo:   suc.ExternalID,
		// `orderDate` existe SEPARADO de `createdAt` por algo: `createdAt` es cuándo lo
		// copió el espejo. Filtrar el día del armador de rutas por `createdAt` daba CERO
		// cualquier día que no fuera hoy, porque el espejo trae quince días de una vez y
		// todos nacen con la fecha de hoy.
		OrderDate:          fechaDelLote(p.OrderDate),
		PedidoUpdatedAt:    fechaDelLote(p.PedidoUpdatedAt),
		FechaComprometida:  fechaDelLote(p.FechaComprometida),
		FacturaAt:          fechaDelLote(p.FacturaAt),
		FacturaCorregidoAt: fechaDelLote(p.FacturaCorregidoAt),
		// DE DÓNDE SON LOS RENGLONES. Se copia tal cual, sin deducirlo de nada: un
		// `cambiado` cuyo cotejo no pudo atar la factura a ESTE pedido se queda con las
		// líneas del pedido, y afirmar lo contrario se lee igual de bien que la verdad.
		ItemsOrigen: p.ItemsOrigen,

		// EL ALMACÉN, TAL CUAL LLEGÓ, Y LA CONFESIÓN AL LADO. Son dos cosas distintas y las
		// dos hacen falta: lo que mandó PEDIDO no se toca (aunque no se haya podido usar) y
		// `almacen_salida_motivo` dice qué se hizo con ello. Sin el primero no se sabe a quién
		// dar de alta; sin el segundo, un kilometraje medido desde el principal es
		// indistinguible de uno bueno.
		AlmacenCodigo:   textoONil(codigoDelAlmacenDelLote(p.Almacen)),
		AlmacenNombre:   textoONil(nombreDelAlmacenDelLote(p.Almacen)),
		AlmacenSucursal: textoONil(sucursalDelAlmacenDelLote(p.Almacen)),
		AlmacenMezclado: mezcladoDelAlmacenDelLote(p.Almacen),
		AlmacenMotivo:   textoONil(string(origen.Motivo)),
	}
	return out
}

// Los tres restantes del almacén del lote. Van sueltos y no como métodos de
// `almacenDelPedidoDelLote` porque el puntero puede ser nil —el caso normal hasta que PEDIDO
// mande el campo— y un método con receptor de valor sobre nil revienta.
func nombreDelAlmacenDelLote(a *almacenDelPedidoDelLote) string {
	if a == nil {
		return ""
	}
	return a.Nombre
}

func sucursalDelAlmacenDelLote(a *almacenDelPedidoDelLote) string {
	if a == nil {
		return ""
	}
	return a.SucursalCodigo
}

// mezcladoDelAlmacenDelLote: nil cuando PEDIDO no lo dijo, y NO false.
//
// Un `false` escrito por defecto afirma «este pedido sale de un solo almacén», que es
// exactamente lo que nadie comprobó. Y es el peor sitio para afirmar de más: `mezclado` es la
// señal de que ese pedido son DOS recogidas, así que un false inventado manda al que despacha
// a un solo almacén a por mercancía que está en dos.
func mezcladoDelAlmacenDelLote(a *almacenDelPedidoDelLote) *bool {
	if a == nil {
		return nil
	}
	return a.Mezclado
}

// fechaDelLote lee una fecha del lote. Una que no se entiende se trata como AUSENTE y no
// como un error del pedido entero: el resto del pedido es bueno y se guarda igual, que es
// mejor que perderlo por una fecha mal escrita en el otro lado.
func fechaDelLote(crudo *string) *time.Time {
	if crudo == nil || strings.TrimSpace(*crudo) == "" {
		return nil
	}
	t, err := time.Parse(time.RFC3339, *crudo)
	if err != nil {
		return nil
	}
	return &t
}

// ---------------------------------------------------------------------------
// Ayudas
// ---------------------------------------------------------------------------

// sucursalParaCotizar busca la sucursal por su CÓDIGO de PEDIDO/Ventra (CAM, HAB, STG…), que
// es la clave con la que cotizan las demás aplicaciones. nil si no está.
//
// Va por `ListarSucursalesVisibles` y no por la consulta `BuscarSucursalPorCodigo` —que
// existe en sqlc— porque esa todavía no está expuesta en `internal/alcance/consultas.go`,
// que es el único sitio por el que un manejador puede llegar a la base. Con ocho
// sucursales el recorrido no se nota; cuando la consulta se exponga, esta función se
// cambia por una línea y nada más se mueve.
//
// El alcance viene puesto de la petición: para las rutas de servicio son todas, y para una
// persona con sucursal es la suya. Si pide el código de otra, aquí no aparece.
func sucursalParaCotizar(ctx context.Context, a *alcance.Acotado, codigo string) (*sqlc.ListarSucursalesRow, error) {
	filas, err := a.ListarSucursalesVisibles(ctx)
	if err != nil {
		return nil, err
	}
	for i := range filas {
		if filas[i].ExternalID != nil && *filas[i].ExternalID == codigo {
			return &filas[i], nil
		}
	}
	return nil, nil
}

// ---------------------------------------------------------------------------
// El pedido, ya en la forma de la base
// ---------------------------------------------------------------------------

// paraLaBase traduce el pedido armado a los parámetros del upsert.
//
// LA IDEMPOTENCIA LA PONE EL `ON CONFLICT (source, external_id)` de la consulta, no un
// «busca y si existe actualiza» escrito aquí: con dos pasadas del espejo a la vez, las dos
// leen «no existe» antes de que ninguna escriba y el pedido entra DOS VECES. Entonces sale
// dos veces en la lista del armador, con el mismo folio, y alguien lo carga dos veces.
func paraLaBase(p PedidoParaGuardar) sqlc.GuardarPedidoDelEspejoParams {
	fuente := sqlc.ProcedenciaPedido
	// Las cuatro coordenadas llevan la MISMA del cliente (§2.3): `lat/lng` es dónde está,
	// y `end_lat/end_lng` es dónde termina la parada, que en un reparto es el mismo sitio.
	lat, lng := p.Lat, p.Lng

	return sqlc.GuardarPedidoDelEspejoParams{
		Source:     &fuente,
		ExternalID: p.ExternalID,
		BranchID:   pgtype.UUID{Bytes: [16]byte(p.BranchID), Valid: p.BranchID != uuid.Nil},

		OperationNumber: p.OperationNumber,
		CustomerName:    p.CustomerName,
		CustomerPhone:   p.CustomerPhone,
		Address:         p.Address,
		EndAddress:      p.EndAddress,
		Lat:             &lat,
		Lng:             &lng,
		EndLat:          &lat,
		EndLng:          &lng,

		// 0 = SIN PESO RESUELTO, y así entra al armador (capacidad del camión). No es
		// «no pesa»: es que nadie ha podido decir cuánto.
		Weight:             p.Weight,
		DeliveryDistanceKm: &p.DeliveryDistanceKm,
		// SIEMPRE nil: delivery ya no cotiza. Lo que se cobra es `pedido_costo`.
		DeliveryPrice: p.DeliveryPrice,

		OrderDate:         marcaDeTiempo(p.OrderDate),
		PedidoUpdatedAt:   marcaDeTiempo(p.PedidoUpdatedAt),
		FechaComprometida: marcaDeTiempo(p.FechaComprometida),

		Estado:            estadoDePedido(p.Estado),
		Archivado:         p.Archivado,
		RequiereDomicilio: p.RequiereDomicilio,
		PedidoCosto:       p.PedidoCosto,

		FacturaEstado:      estadoDeFactura(p.FacturaEstado),
		FacturaNumero:      p.FacturaNumero,
		FacturaAt:          marcaDeTiempo(p.FacturaAt),
		FacturaDomicilio:   p.FacturaDomicilio,
		FacturaCorregidoAt: marcaDeTiempo(p.FacturaCorregidoAt),
		ItemsOrigen:        p.ItemsOrigen,

		Municipio:      p.Municipio,
		Vendedor:       p.Vendedor,
		SucursalCodigo: p.SucursalCodigo,

		AlmacenSalidaCodigo:   p.AlmacenCodigo,
		AlmacenSalidaNombre:   p.AlmacenNombre,
		AlmacenSalidaSucursal: p.AlmacenSucursal,
		AlmacenSalidaMezclado: p.AlmacenMezclado,
		AlmacenSalidaMotivo:   p.AlmacenMotivo,
	}
}

// renglonesParaLaBase pasa las líneas a filas de `order_items`.
//
// `linea` conserva la POSICIÓN ORIGINAL en el pedido —no el número de fila escrita— para
// que la hoja del despacho salga en el mismo orden que el papel del vendedor.
//
// Una línea sin nada que enseñar se descarta: `description` es obligatoria y una fila
// vacía no se puede ni buscar ni despachar. Deja hueco en la numeración a propósito: el
// hueco dice que allí venía algo que no se entendió, y rehacer la cuenta lo escondería.
func renglonesParaLaBase(renglones []cotizar.RenglonPesado) []sqlc.CrearRenglonDePedidoParams {
	salida := make([]sqlc.CrearRenglonDePedidoParams, 0, len(renglones))
	for i, r := range renglones {
		texto := strings.TrimSpace(r.Name)
		if texto == "" {
			texto = strings.TrimSpace(r.Description)
		}
		if texto == "" {
			continue
		}
		fila := sqlc.CrearRenglonDePedidoParams{
			// PedidoID lo rellena `EspejoGuardarPedido` con el id que devuelve el upsert.
			Linea:       int32(i + 1),
			Description: texto,
			Quantity:    r.Quantity.O(0),
		}
		// Los bultos sólo si los hay. Un 0 escrito aquí diría «cero cajas», que no es lo
		// mismo que «la factura no distingue cajas de unidades» — y son indistinguibles al
		// llegar: un `packs` ausente se decodifica como 0, no como «no vino».
		if r.Packs.Positivo() {
			v := r.Packs.Valor
			fila.Packs = &v
		}
		// LA CONSTANCIA DEL PESO, que estaba dada de alta y no la escribía NADIE.
		//
		// `00004_peso_por_renglon.sql` añadió estas columnas precisamente para no tener
		// que recalcular el peso con el catálogo de HOY sobre un pedido de hace tres
		// meses: el catálogo cambia —precios, envases, productos que salen— y un peso
		// recalculado sobre una ruta vieja no es el peso con el que se cargó ese camión.
		//
		// Y sin embargo estaban en NULL en los 7.515 renglones de producción, comprobado
		// el 26/09/2026. El comentario de `orders.sql` decía «quien los pone es
		// `renglonesParaLaBase`» — y no los ponía. Un comentario no falla.
		//
		// No hay que calcular nada: `cotizar.Resolver` ya devolvió todo esto. Sólo había
		// que dejar de tirarlo.
		//
		// TODOS ANULABLES A PROPÓSITO: un renglón que no sabe lo que pesa se guarda VACÍO,
		// no en cero. Un cero se lee como «este producto no pesa», que es un número
		// creíble y equivocado. `origen_peso` sí se escribe aunque sea `none`: es el
		// renglón confesando que lo intentó y no pudo, y es lo que la vista mira.
		if r.WeightKg > 0 {
			v := r.WeightKg
			fila.PesoLineaKg = &v
		}
		if r.UnitWeightKg > 0 {
			v := r.UnitWeightKg
			fila.PesoUnitarioKg = &v
		}
		if origen := string(r.WeightSource); origen != "" {
			fila.OrigenPeso = &origen
		}
		fila.AlmacenNombre = r.WhName
		emparejado := r.Matched
		fila.Caso = &emparejado

		// EL ALMACÉN DE ESTE RENGLÓN, en sus columnas y no en `almacen_nombre`.
		//
		// `almacen_nombre` existe desde la 00004 y, a pesar de cómo se llama, lo que lleva es
		// la línea de arriba: `WhName`, el nombre del PRODUCTO con el que casó el catálogo
		// local de pesos. Meter un almacén ahí dejaría a quien busca un producto leyendo «2» y
		// «AURORA», y a quien busca un almacén leyendo «MALTA BUCANERO 355 ML». Columnas
		// nuevas, 00012.
		//
		// POR RENGLÓN Y NO SÓLO POR PEDIDO porque un pedido mezclado sale de DOS almacenes: con
		// sólo el del pedido, las 804 líneas de PV-STGO de Santiago quedarían apuntadas como de
		// AURORA, que es el que más renglones pone.
		fila.AlmacenSalidaCodigo = textoONil(r.AlmacenCodigo)
		fila.AlmacenSalidaNombre = textoONil(r.AlmacenNombre)

		// `product_id` se queda vacío y NO es un fallo: el emparejamiento con el catálogo
		// de Ventra da el peso, no el id de la fila del catálogo, y hay renglones escritos
		// a mano que no están en Ventra. Se resuelve por nombre cuando hace falta.
		salida = append(salida, fila)
	}
	return salida
}

// marcaDeTiempo: nil -> NULL. Una fecha ausente es ausente, no el año cero, que es lo que
// deja el valor por defecto de Go y lo que ordenaría los pedidos por delante de todo.
func marcaDeTiempo(t *time.Time) pgtype.Timestamptz {
	if t == nil {
		return pgtype.Timestamptz{}
	}
	return pgtype.Timestamptz{Time: *t, Valid: true}
}

// estadoDePedido y estadoDeFactura filtran contra los valores que el enum admite.
//
// UN VALOR QUE NO ESTÁ EN EL ENUM NO ES UN PEDIDO PERDIDO: Postgres rechazaría la fila
// entera, y con ella el lote, por un estado nuevo que alguien añadió en PEDIDO. Se guarda
// como NULL —«no cotejado», que es la verdad— y el pedido entra igual.
func estadoDePedido(v *string) *sqlc.PedidoEstado {
	if v == nil {
		return nil
	}
	switch e := sqlc.PedidoEstado(strings.TrimSpace(*v)); e {
	case sqlc.PedidoEstadoCompletada, sqlc.PedidoEstadoEnProceso:
		return &e
	}
	return nil
}

func estadoDeFactura(v *string) *sqlc.FacturaEstado {
	if v == nil {
		return nil
	}
	switch e := sqlc.FacturaEstado(strings.TrimSpace(*v)); e {
	case sqlc.FacturaEstadoIgual, sqlc.FacturaEstadoCambiado, sqlc.FacturaEstadoSinFactura:
		return &e
	}
	return nil
}
