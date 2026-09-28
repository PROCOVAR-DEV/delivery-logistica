// EL ESPEJO: las rutas por las que esta base se pone al día con las de fuera, y la que
// deja al aparato ponerse al día con ésta.
//
// Son tres y ninguna la abre una persona mirando una pantalla:
//
//	POST /api/products/sync   el catálogo de Ventra, sucursal por sucursal
//	POST /api/admin/recompute el recosteo de lo de los últimos N días, vía PEDIDO
//	GET  /api/sync/cambios    la BAJADA del aparato (`docs/sincronizacion.md`)
//
// LO QUE TIENEN EN COMÚN, y por eso están juntas: ninguna es idempotente por casualidad.
// Las tres se llaman desde un temporizador o desde un aparato que reintenta, así que
// repetirlas tiene que ser barato y no puede duplicar nada. El catálogo se escribe con un
// `ON CONFLICT (sucursal_codigo, sku)`; el recosteo no escribe aquí, delega; y la bajada
// sólo lee.
//
// Y LO QUE NO HACEN: ninguna borra lo que deja de venir. Media lista por un corte de VPN
// no puede vaciar el catálogo de una sucursal — lo viejo se nota por `traido_at`, que dice
// si lo que se está mirando es de hace diez minutos o de hace tres días.
package api

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/espejo"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// rutasEspejo monta las tres. Lo llama `Rutas()` en servidor.go.
func (s *Servidor) rutasEspejo(rt *httpx.Router, sesion, admin []httpx.Medio) {
	// CÓMO VA EL WEBHOOK. DESARROLLADOR Y SUPER ADMIN, y fuera del menú.
	//
	// No son datos de una sucursal ni de administrar la empresa: es el estado de una
	// tubería entre dos sistemas, con colas, reintentos, códigos HTTP y motivos de error
	// de PEDIDO dentro. Jose, 26/09/2026: «esto es para administración, esta vista no la
	// puede ver nadie» y «que sólo lo pueda ver yo, eso no lo puede ver más nadie, sólo yo,
	// el desarrollador» — y esa misma tarde, al quedarse fuera su propia cuenta: «ponle
	// para super admin también, de todas formas yo limpiaré eso después».
	//
	// Por eso NO va con `admin` aunque dos de sus roles coincidan: `ExigirAdmin` deja pasar
	// además a ADMINISTRADOR, que administra UNA sucursal, y al `admin` heredado de la web
	// vieja. Quién entra exactamente está en `auth.PuedeMirarElCanal`, en un solo sitio.
	soloElCanal := append(append([]httpx.Medio{}, sesion...), auth.ExigirQuienMiraElCanal)
	rt.ManejarFunc(http.MethodGet, "/api/admin/webhook", s.estadoDelWebhook, soloElCanal...)

	// LA PUERTA POR DONDE PEDIDO TOCA. Va SIN sesión y con su propia llave: quien llama es
	// otro sistema, no una persona, y no tiene ni token ni sucursal. Se comprueba con la
	// pareja key+secret y el cuerpo FIRMADO — ver `webhook_de_pedido.go`.
	//
	// EL CAMINO IMPORTA: `PathPrefix(/api)` de Traefik ya manda esto a la API, así que
	// montarla bajo `/api` es lo que hace que funcione sin tocar el proxy. Una ruta
	// `/webhooks/...` a secas se la comería la aplicación web y PEDIDO recibiría un HTML.
	rt.ManejarFunc(http.MethodPost, "/api/webhooks/pedido", s.avisoDePedido, s.mediosDelWebhook()...)
	_ = admin

	// `products/sync` admite LAS DOS PUERTAS —clave de servicio o sesión— porque la
	// dispara un temporizador y también un administrador que ve el catálogo viejo y le
	// da al botón. Dejar sólo la de servicio obligaría a repartir la clave a mano.
	servicioOSesion := []httpx.Medio{s.servicioOSesion, s.porteria.Exigir}
	rt.ManejarFunc(http.MethodPost, "/api/products/sync", s.sincronizarProductos, servicioOSesion...)

	// `admin/recompute` es de PERSONA y no de servicio: usa la clave de servicio para
	// hablar con PEDIDO, pero quien la dispara tiene que estar identificado, porque de su
	// alcance sale a qué sucursal se le recuesta lo de los últimos treinta días.
	rt.ManejarFunc(http.MethodPost, "/api/admin/recompute", s.recomputar, sesion...)

	// La bajada del aparato.
	rt.ManejarFunc(http.MethodGet, "/api/sync/cambios", s.cambiosDesde, sesion...)
}

// servicioOSesion deja pasar a quien traiga la clave de servicio O una sesión válida.
//
// Cuando entra por la clave, se cuelga del contexto una persona SIN sucursal: no es un
// disfraz para saltarse nada, es que el alcance necesita alguien de quien partir y el
// espejo, por definición, recorre las ocho sucursales. Si se dejara sin persona, el
// middleware del alcance respondería 401 y la ruta no se podría llamar nunca desde el
// temporizador.
//
// El orden importa: primero la clave. Un servicio que además arrastre una cookie caducada
// no puede quedarse fuera por la cookie.
func (s *Servidor) servicioOSesion(siguiente http.Handler) http.Handler {
	conLlave := auth.LlaveDeServicio(s.cfg.ServiceAPIKey)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if s.cfg.ServiceAPIKey != "" && r.Header.Get("X-Api-Key") != "" {
			conLlave(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				ctx := auth.ConUsuario(r.Context(), &auth.Usuario{
					ID: "servicio:espejo", Rol: "SUPER ADMIN",
				})
				siguiente.ServeHTTP(w, r.WithContext(ctx))
			})).ServeHTTP(w, r)
			return
		}
		s.verif.Exigir(siguiente).ServeHTTP(w, r)
	})
}

// ---------------------------------------------------------------------------
// POST /api/products/sync
// ---------------------------------------------------------------------------

// FilaDeVentra es una línea del catálogo tal como la da Ventra. Es lo mínimo que hace
// falta para escribir un producto; lo demás de Ventra no se guarda porque no se usa, y un
// campo guardado que nadie lee es un campo que nadie mantiene.
type FilaDeVentra struct {
	Sku               string
	Nombre            string
	PesoKg            *float64
	Categoria         string
	Unidad            string
	Envase            string
	UnidadesPorEnvase *float64
	Precio            *float64
	Existencias       *float64
	// Activo=false NO se guarda: es un producto retirado en Ventra, y ofrecerlo en el
	// buscador es prometer mercancía que no hay.
	Activo bool
}

// LectorDeVentra es por donde se pregunta al catálogo de Ventra, que vive detrás de la
// VPN y en bases MySQL que no son ésta.
//
// ES UNA INTERFAZ Y NO UNA FUNCIÓN SUELTA porque son dos preguntas distintas —qué bases
// hay y qué tiene cada una— y porque así las pruebas de esta ruta no necesitan ni VPN ni
// MySQL: se corren en cada compilación y no «cuando haya una Ventra a mano».
type LectorDeVentra interface {
	// Bases devuelve, por CÓDIGO de sucursal (STG, HOL, CAM...), el nombre de la base de
	// Ventra que le corresponde.
	Bases(ctx context.Context) (map[string]string, error)
	// Catalogo lee el catálogo de una de esas bases.
	Catalogo(ctx context.Context, base string) ([]FilaDeVentra, error)
}

// YA NO HAY `var Ventra`: el lector es `s.ventra`, un campo del servidor (ver
// `servidor.go`). Estaba como variable de paquete a regañadientes, porque `Servidor` se
// construye en `servidor.go` y este fichero no lo tocaba mientras se escribían los dos a
// la vez. Se enchufa al arrancar con `PonerLectorDeVentra`.
//
// LO QUE NO CAMBIA: mientras sea nil, la ruta contesta 502 y NO 200 con ceros. Un catálogo
// que dice «he escrito 0 productos» cuando en realidad no ha preguntado a nadie deja al
// logístico mirando precios de hace tres semanas sin un solo aviso.

// CatalogoCadaMs es el intervalo por defecto de la bajada, en milisegundos. Se puede
// cambiar con `CATALOGO_CADA_MS` y saltar de una vez con `?forzar=1`.
const CatalogoCadaMs = 12 * 60 * 60 * 1000

// PonerLectorDeVentra enchufa el lector. Lo llama el arranque, una vez, ANTES de servir:
// no hay candado porque no está pensado para cambiarse con el servidor ya en pie.
func (s *Servidor) PonerLectorDeVentra(v LectorDeVentra) { s.ventra = v }

type SucursalDelCatalogo struct {
	Sucursal string `json:"sucursal"`
	Database string `json:"database"`
	Leidos   int    `json:"leidos"`
	Escritos int    `json:"escritos"`
	Error    string `json:"error,omitempty"`
}

func (s *Servidor) sincronizarProductos(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	forzar := r.URL.Query().Get("forzar") == "1"

	ajustes, err := a.ObtenerAjustes(r.Context())
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// El intervalo: sin forzar, no se vuelve a preguntar antes de las doce horas. El
	// catálogo de ocho sucursales por la VPN de allá no es una consulta barata.
	if !forzar && ajustes.CatalogoTraidoAt.Valid {
		if time.Since(ajustes.CatalogoTraidoAt.Time) < s.intervaloDelCatalogo() {
			httpx.JSON(w, r, http.StatusOK, map[string]any{
				"saltado": true, "traidoAt": hora(ajustes.CatalogoTraidoAt),
			})
			return
		}
	}

	if s.ventra == nil {
		httpx.Error(w, r, http.StatusBadGateway,
			"No se pudo preguntar a Ventra (¿VPN?): este servicio todavía no tiene lector de Ventra configurado")
		return
	}
	bases, err := s.ventra.Bases(r.Context())
	if err != nil {
		httpx.Error(w, r, http.StatusBadGateway,
			fmt.Sprintf("No se pudo preguntar a Ventra (¿VPN?): %s", err))
		return
	}

	sucursales, err := a.ListarSucursalesVisibles(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	filas := make([]SucursalDelCatalogo, 0, len(sucursales))
	escritosTotal, conError := 0, 0
	for _, suc := range sucursales {
		fila := SucursalDelCatalogo{Sucursal: suc.Name}
		codigo := ""
		if suc.ExternalID != nil {
			codigo = strings.TrimSpace(*suc.ExternalID)
		}
		base, hay := bases[codigo]
		if codigo == "" || !hay {
			// Literal del contrato. NO es un error del servicio: es una sucursal que
			// todavía no tiene su base emparejada, y las demás siguen.
			fila.Error = "sin base de Ventra que le cuadre"
			conError++
			filas = append(filas, fila)
			continue
		}
		fila.Database = base

		// Una sucursal que falla NO tumba a las otras siete. Es la diferencia entre
		// «Holguín se quedó sin catálogo» y «hoy no hay catálogo».
		leidos, escritos, err := s.catalogoDeUnaSucursal(r, a, base, codigo)
		fila.Leidos, fila.Escritos = leidos, escritos
		if err != nil {
			fila.Error = err.Error()
			conError++
			httpx.Registro(r).Warn("el catálogo de una sucursal no se pudo traer",
				"sucursal", suc.Name, "base", base, "err", err)
		}
		escritosTotal += escritos
		filas = append(filas, fila)
	}

	// La hora SÓLO se marca si se escribió algo. Si todas fallaron no se toca, para poder
	// reintentar antes de las doce horas en vez de quedarse medio día con el catálogo a
	// medias y creyendo que está al día.
	if escritosTotal > 0 {
		if err := a.EspejoMarcarCatalogoTraido(r.Context()); err != nil {
			httpx.Registro(r).Error("el catálogo entró pero no se pudo marcar la hora", "err", err)
		}
	}

	// SÓLO si entró algo. Una vuelta que no escribió nada —todas las sucursales con
	// error, o la respuesta «saltado» de más arriba, que sale antes de llegar aquí— no
	// cambió el catálogo de nadie, y avisar mandaría a todas las pantallas a bajarse otra
	// vez lo mismo por la conexión de allá.
	if escritosTotal > 0 {
		avisarCambioDelCatalogo(r.Context())
	}
	httpx.JSON(w, r, http.StatusOK, map[string]any{
		"sucursales": filas,
		"escritos":   escritosTotal,
		"conError":   conError,
	})
}

func (s *Servidor) catalogoDeUnaSucursal(r *http.Request, a *alcance.Acotado, base, codigo string) (int, int, error) {
	lineas, err := s.ventra.Catalogo(r.Context(), base)
	if err != nil {
		return 0, 0, err
	}
	escritos := 0
	for _, l := range lineas {
		sku := strings.TrimSpace(l.Sku)
		nombre := strings.TrimSpace(l.Nombre)
		// Sin sku no hay clave por la que reconocer la fila entre pasadas, y sin nombre
		// no hay nada que enseñar. Se saltan, no se inventan.
		if sku == "" || nombre == "" || !l.Activo {
			continue
		}
		cod := codigo
		peso := 0.0
		if l.PesoKg != nil {
			peso = *l.PesoKg
		}
		if _, err := a.EspejoGuardarProducto(r.Context(), sqlc.GuardarProductoDelCatalogoParams{
			Name: nombre, Weight: peso,
			Packaging: aTexto(strings.TrimSpace(l.Envase)),
			// El peso por envase se guarda tal cual venga; un cero no es «no lo sé» y
			// por eso va como puntero desde Ventra.
			UnitsPerPackage: l.UnidadesPorEnvase,
			Category:        aTexto(strings.TrimSpace(l.Categoria)),
			Sku:             &sku,
			SucursalCodigo:  &cod,
			Price:           l.Precio,
			Stock:           l.Existencias,
			Unit:            aTexto(strings.TrimSpace(l.Unidad)),
		}); err != nil {
			// Una línea mala no se lleva por delante el catálogo entero de la sucursal.
			httpx.Registro(r).Warn("una línea del catálogo no entró",
				"sucursal", codigo, "sku", sku, "err", err)
			continue
		}
		escritos++
	}
	return len(lineas), escritos, nil
}

// intervaloDelCatalogo: cada cuánto se vuelve a bajar el catálogo. Sale de
// `CATALOGO_CADA_MS`, ya validada en `config` (doce horas por defecto).
//
// Con la configuración a cero se cae a las doce horas y NO a «siempre»: un intervalo de
// cero convierte cada visita a la pantalla en una bajada entera del catálogo de las ocho
// sucursales por la VPN, que es exactamente lo que este freno existe para evitar.
func (s *Servidor) intervaloDelCatalogo() time.Duration {
	if s.cfg != nil && s.cfg.CatalogoCada > 0 {
		return s.cfg.CatalogoCada
	}
	return CatalogoCadaMs * time.Millisecond
}

// ---------------------------------------------------------------------------
// POST /api/admin/recompute
// ---------------------------------------------------------------------------

// ClienteDelEspejo es el http.Client con el que se habla con PEDIDO y con la cotización.
//
// CON PLAZO Y NO EL DE POR DEFECTO, que no tiene ninguno: una petición sin plazo contra la
// VPN de allá se queda colgada para siempre y se lleva una conexión del pool con ella. Y
// como variable de paquete para que las pruebas puedan apuntarlo a un servidor de mentira.
var ClienteDelEspejo = &http.Client{Timeout: 120 * time.Second}

// DiasPorDefecto y los topes del recosteo. Acotado a [1,120] a propósito: con «todos los
// días» esto se convierte en una consulta de 3.500 pedidos por la conexión de Cuba.
const (
	DiasPorDefecto = 30
	DiasMinimo     = 1
	DiasMaximo     = 120
	// TopeDelRecosteo es el `limit` que se le pide a PEDIDO en una sola llamada.
	//
	// ESTÁ AQUÍ Y NO EN LA URL PARA PODER COMPROBARLO. Escrito a mano dentro del
	// `fmt.Sprintf` no había con qué comparar lo que volvía, y eso es exactamente el fallo
	// del §3: se pedía un tope y no se miraba cuántos venían. PEDIDO corta sin decirlo —de
	// un `limit=5000` vuelven 2.000 clavados— y una ventana de 30 días que hoy son ~13.000
	// pedidos se recosteaba a medias con un 200 OK.
	TopeDelRecosteo = 5000
)

func (s *Servidor) recomputar(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	// La clave se comprueba ANTES de nada: sin ella no hay manera de hablar con PEDIDO y
	// el trabajo entero no se puede hacer. Enterarse después de bajar 5.000 pedidos es
	// enterarse tarde.
	if strings.TrimSpace(s.cfg.ServiceAPIKey) == "" {
		httpx.Error(w, r, http.StatusInternalServerError, "SERVICE_API_KEY no configurada en el servidor")
		return
	}
	// De `config`, que ya la validó y le quitó la barra final. Vacía sigue siendo un 500
	// con el nombre de la variable dentro: sin PEDIDO no hay nada que recostear, y
	// enterarse después de bajar 5.000 pedidos es enterarse tarde.
	pedidoURL := s.cfg.PedidoAPIURL
	if pedidoURL == "" {
		httpx.Error(w, r, http.StatusInternalServerError, "PEDIDO_API_URL no configurada en el servidor")
		return
	}

	dias := DiasPorDefecto
	if n, err := strconv.Atoi(strings.TrimSpace(r.URL.Query().Get("dias"))); err == nil && n != 0 {
		dias = n
	}
	dias = min(max(dias, DiasMinimo), DiasMaximo)

	// El alcance se traduce a CÓDIGO porque es lo que entiende PEDIDO: allí las
	// sucursales son STG y HOL, no uuids nuestros. Sin alcance se piden todas.
	codigo := ""
	if c := a.Codigo(); c != nil {
		codigo = *c
	}

	desde := time.Now().AddDate(0, 0, -dias).Format("2006-01-02")
	url := fmt.Sprintf("%s/integration/orders?desde=%s&limit=%d", pedidoURL, desde, TopeDelRecosteo)
	if codigo != "" {
		url += "&sucursalCodigo=" + codigo
	}

	cuerpo, estado, err := s.pedirAlEspejo(r.Context(), http.MethodGet, url, nil)
	if err != nil {
		httpx.Error(w, r, http.StatusBadGateway, fmt.Sprintf("PEDIDO no contesta: %s", err))
		return
	}
	if estado < 200 || estado >= 300 {
		httpx.Error(w, r, http.StatusBadGateway,
			fmt.Sprintf("PEDIDO %d: %s", estado, recortar(cuerpo, 200)))
		return
	}

	var respuesta struct {
		Orders []json.RawMessage `json:"orders"`
	}
	if err := json.Unmarshal(cuerpo, &respuesta); err != nil {
		httpx.Error(w, r, http.StatusBadGateway,
			fmt.Sprintf("PEDIDO contestó algo que no se entiende: %s", recortar(cuerpo, 200)))
		return
	}

	quien := codigo
	if quien == "" {
		quien = "todas"
	}
	if len(respuesta.Orders) == 0 {
		// 200 y no 404: que no haya nada que recostear no es un fallo, y la pantalla
		// necesita poder decirlo con esas palabras.
		httpx.JSON(w, r, http.StatusOK, map[string]any{
			"total": 0, "recosteados": 0, "dias": dias,
			"message":  fmt.Sprintf("No hay pedidos con geolocalización en los últimos %d días.", dias),
			"sucursal": quien,
		})
		return
	}

	// El recosteo de verdad lo hace `/api/quote/batch`, que es quien sabe repartir la
	// carga. Aquí NO se duplica esa cuenta: dos sitios calculando el mismo precio es la
	// forma más rápida de que discrepen, y este número acaba en la factura del cliente.
	destino := s.cfg.DeliveryURL
	if destino == "" {
		destino = "http://127.0.0.1:" + s.cfg.Puerto
	}

	// LOS PEDIDOS SE TRADUCEN, y esto es un ARREGLO del 26/09/2026, no un refinamiento.
	//
	// Antes se metían los de `/integration/orders` TAL CUAL en `orders`, y las dos formas no
	// se parecen: PEDIDO manda `id`, `sucursalCodigo` y `cliente{}`; la puerta espera
	// `externalId`, `sucursalExternalId` y `customerName`. Así que a la puerta le llegaba un
	// lote entero con el `externalId` VACÍO —y sin id no se puede guardar ningún pedido—.
	//
	// LA FORMA DEL FALLO es la de siempre aquí: no daba error. Contestaba 200, con
	// `total: 5000` y `recosteados: 0`, y un cero es un número perfectamente creíble para
	// «no había nada que recostear». El botón existía, se pulsaba, decía que sí y no
	// recosteaba un solo pedido.
	//
	// Se encontró escribiendo la puerta del webhook, que necesitaba la misma traducción. Es
	// `espejo.ArmarLote`, la MISMA que usa el ciclo — que es la razón de que el ciclo sí
	// funcionara y esto no.
	var pedidos []espejo.PedidoDeFuera
	if err := json.Unmarshal(cuerpo, &struct {
		Orders *[]espejo.PedidoDeFuera `json:"orders"`
	}{Orders: &pedidos}); err != nil {
		httpx.Error(w, r, http.StatusBadGateway,
			fmt.Sprintf("los pedidos de PEDIDO no se entienden: %s", err))
		return
	}
	lote, _ := json.Marshal(espejo.ArmarLote(pedidos))
	cuerpo, estado, err = s.pedirAlEspejo(r.Context(), http.MethodPost, destino+"/api/quote/batch", lote)
	if err != nil {
		httpx.Error(w, r, http.StatusBadGateway, fmt.Sprintf("Cotización no contesta: %s", err))
		return
	}
	if estado < 200 || estado >= 300 {
		httpx.Error(w, r, http.StatusBadGateway,
			fmt.Sprintf("Cotización %d: %s", estado, recortar(cuerpo, 200)))
		return
	}

	var batch struct {
		WeightsSource string `json:"weightsSource"`
		Results       []struct {
			Status string   `json:"status"`
			Price  *float64 `json:"price"`
		} `json:"results"`
	}
	_ = json.Unmarshal(cuerpo, &batch)
	recosteados := 0
	for _, res := range batch.Results {
		if res.Status == "quoted" && res.Price != nil {
			recosteados++
		}
	}
	if batch.WeightsSource == "" {
		batch.WeightsSource = "none"
	}

	salida := map[string]any{
		"total": len(respuesta.Orders), "recosteados": recosteados, "dias": dias,
		"weightsSource": batch.WeightsSource, "sucursal": quien,
	}
	// SE PIDIÓ UN TOPE: HAY QUE COMPROBAR SI SE ALCANZÓ. Es el tercero de la familia del
	// §3 y el que quedaba sin cerrar.
	//
	// Aquí no se puede paginar —`/integration/orders` de PEDIDO no da cursor ni
	// desplazamiento; la forma que funciona es partir la ventana en tramos, y eso ya lo
	// hace `internal/espejo`, que es quien barre el histórico—. Así que lo que toca es lo
	// otro que manda la regla: **decirlo, nombrando lo que se quedó fuera**. Un recosteo
	// que contesta «total: 5000, recosteados: 5000» sobre una ventana de 13.000 es una
	// pantalla verde encima de 8.000 pedidos con el precio viejo, y ésos acaban en la
	// factura de alguien.
	if len(respuesta.Orders) >= TopeDelRecosteo {
		aviso := fmt.Sprintf(
			"PEDIDO devolvió %d pedidos, que es justo el tope que se le pidió: es casi "+
				"seguro que hay MÁS en esos %d días y que se han quedado sin recostear. "+
				"Repite con menos días (?dias=) hasta que el total baje del tope.",
			len(respuesta.Orders), dias)
		salida["truncado"] = true
		salida["aviso"] = aviso
		httpx.Registro(r).Warn("el recosteo tocó el tope de PEDIDO: puede haber pedidos sin recostear",
			"tope", TopeDelRecosteo, "dias", dias, "sucursal", quien)
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// Las cabeceras extra van en pares `nombre, valor`. Un número impar se ignora entero en vez
// de mandar media cabecera: media cabecera es una que el otro lado lee como ausente.
func (s *Servidor) pedirAlEspejo(
	ctx context.Context, metodo, url string, cuerpo []byte, extras ...string,
) ([]byte, int, error) {
	var lector io.Reader
	if cuerpo != nil {
		lector = strings.NewReader(string(cuerpo))
	}
	req, err := http.NewRequestWithContext(ctx, metodo, url, lector)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("X-Api-Key", s.cfg.ServiceAPIKey)
	req.Header.Set("Accept", "application/json")
	// `no-store` explícito: por el medio hay proxies y una respuesta guardada del
	// recosteo de ayer es exactamente el número que no se quiere.
	req.Header.Set("Cache-Control", "no-store")
	if cuerpo != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if len(extras)%2 == 0 {
		for i := 0; i < len(extras); i += 2 {
			req.Header.Set(extras[i], extras[i+1])
		}
	}
	res, err := ClienteDelEspejo.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer res.Body.Close()
	// Tope de lectura: una respuesta enorme de un servicio que se volvió loco no puede
	// tumbar este proceso por memoria.
	leido, err := io.ReadAll(io.LimitReader(res.Body, 32<<20))
	return leido, res.StatusCode, err
}

func recortar(b []byte, n int) string {
	s := strings.TrimSpace(string(b))
	if len(s) <= n {
		return s
	}
	return s[:n]
}

// ---------------------------------------------------------------------------
// GET /api/sync/cambios — la bajada del aparato
// ---------------------------------------------------------------------------

// Conjunto es la forma de cada colección en la bajada: lo que se puso o cambió, y lo que
// se fue. `quitados` hace falta DE VERDAD: sin él, un pedido archivado o una ruta borrada
// se quedan en el aparato para siempre y la lista local sólo crece.
//
// HASTA EL 17/09/2026 ESTO ERA VERDAD SÓLO PARA `orders`. Las demás colecciones pasaban
// por el ayudante `conjunto()`, que devolvía `Quitados: []string{}` siempre, y el
// comentario de arriba nombraba «una ruta borrada» como ejemplo de lo que no podía pasar
// mientras exactamente eso pasaba. Jose lo vio en su teléfono: una ruta borrada en el
// servidor seguía en el aparato, «Completada», con 0 paradas y 2,6 km.
//
// Hoy lo llenan de verdad `orders` (lápidas de 00003), `routes`, `vehicles`, `branches`,
// `products`, `customers`, `boardColumns` y `boardPlacements` (lápidas de 00006). Quedan
// dos y las dos están razonadas donde se sirven: `settings` es una fila global que nadie
// borra, y `warehouses` no viaja en `cambios` sino en `faltan`.
type Conjunto struct {
	Puestos  []any    `json:"puestos"`
	Quitados []string `json:"quitados"`
}

// CambiosSalida es el sobre del protocolo (`docs/sincronizacion.md`).
type CambiosSalida struct {
	// Hasta LO PONE EL SERVIDOR, nunca el aparato. El reloj de un teléfono se mueve —se
	// cambia a mano, se va con la batería, salta de huso—, y si el aparato dijera desde
	// cuándo pedir, un reloj atrasado se perdería cambios para siempre sin que nadie lo
	// note.
	Hasta    time.Time           `json:"hasta"`
	Completa bool                `json:"completa"`
	Cambios  map[string]Conjunto `json:"cambios"`
	Truncado bool                `json:"truncado"`
	// Faltan son las colecciones que esta versión del servidor NO SABE servir todavía.
	//
	// VAN NOMBRADAS Y NO COMO UN CONJUNTO VACÍO, y ésa es toda la razón de que este campo
	// exista: un `{"puestos":[],"quitados":[]}` le dice al aparato «no ha cambiado nada»,
	// que es exactamente lo contrario de la verdad, y el aparato se queda con la foto de
	// la mañana creyendo que está al día. Ausente y nombrado aquí, el aparato puede
	// decirlo en la pantalla.
	Faltan []string `json:"faltan,omitempty"`
	Aviso  string   `json:"aviso,omitempty"`
	// Continuar es POR DÓNDE SEGUIR en el catálogo y en el padrón de clientes. El aparato
	// lo devuelve tal cual en la petición siguiente (`?continuar=…`) y no lo mira por
	// dentro.
	//
	// EXISTE POR UN CASO Y SÓLO POR UNO: un grupo de filas con la MISMA marca más grande
	// que el tope. El traspaso metió los 7.975 clientes de producción en una sola
	// transacción y `now()` es la del inicio de la transacción, así que los 7.975 comparten
	// `synced_at` al microsegundo. Ahí `hasta` no basta —cualquier marca que se devuelva o
	// repite el grupo entero o se salta lo que quedaba—, y el cursor `(marca, id)` es lo
	// único que puede empezar exactamente donde acabó la tanda anterior.
	//
	// EN TODO LO DEMÁS MANDA `hasta`, y es a propósito: quien pierda el cursor a mitad de
	// la cadena —se reinstala, se corta la red, se acaba el tope de tandas— vuelve a pedir
	// desde la marca de la última fila servida y no se deja NADA atrás. Un cursor que fuera
	// la única forma de seguir es un cursor que, perdido, pierde trabajo.
	Continuar string `json:"continuar,omitempty"`
}

// cursorDeTanda es la ÚLTIMA FILA SERVIDA de una colección: su marca y su id.
//
// Las dos mitades hacen falta. La marca sola no distingue entre las filas de un mismo
// grupo —y en esta base los grupos son de miles: una transacción, una hora—, así que un
// corte dentro del grupo con sólo la marca o no avanza o se salta el resto. El id
// desempata, que es el mismo orden del SQL (`ORDER BY marca ASC, id ASC`).
type cursorDeTanda struct {
	// Hay dice que este cursor EXISTE, y va aparte de la marca a propósito: una marca
	// vacía es un valor legítimo —lo es en las pruebas, y lo sería el día que una columna
	// dejara de ser NOT NULL—, así que deducir «no hay cursor» de «la marca está a cero»
	// deja la cadena repitiendo la primera tanda para siempre.
	Hay   bool      `json:"h"`
	Marca time.Time `json:"m"`
	ID    uuid.UUID `json:"i"`
}

func (c cursorDeTanda) puesto() bool { return c.Hay }

// leer devuelve el cursor como lo quiere `alcance.TandaDelPadron`: nil cuando no hay.
func (c cursorDeTanda) leer() (*time.Time, *uuid.UUID) {
	if !c.puesto() {
		return nil, nil
	}
	marca, id := c.Marca, c.ID
	return &marca, &id
}

// porDondeSeguir es lo que viaja dentro de `continuar`.
type porDondeSeguir struct {
	Productos cursorDeTanda `json:"p"`
	Clientes  cursorDeTanda `json:"c"`
}

// leerPorDondeSeguir saca el cursor de la query. Uno ilegible se trata como «empieza de
// cero» y no como un error: lo peor que pasa es que el aparato se baje otra vez una tanda
// que ya tenía, y eso se resuelve solo con el `insertOnConflictUpdate` de allá. Cortarle
// la bajada del día por un parámetro mal copiado sería mucho peor.
func leerPorDondeSeguir(crudo string) porDondeSeguir {
	var d porDondeSeguir
	crudo = strings.TrimSpace(crudo)
	if crudo == "" {
		return d
	}
	bruto, err := base64.RawURLEncoding.DecodeString(crudo)
	if err != nil {
		return porDondeSeguir{}
	}
	if err := json.Unmarshal(bruto, &d); err != nil {
		return porDondeSeguir{}
	}
	return d
}

func (d porDondeSeguir) escribir() string {
	bruto, err := json.Marshal(d)
	if err != nil {
		return ""
	}
	return base64.RawURLEncoding.EncodeToString(bruto)
}

// TopeDeBajada acota cada colección. Si alguna lo toca, `truncado` va a true y el aparato
// vuelve a pedir con el `hasta` devuelto.
const TopeDeBajada = 2000

// HorizonteDeLapidas es CUÁNTO ATRÁS se puede confiar en las lápidas.
//
// Las lápidas —`orders_fuera_de_alcance` de 00003 y `bajas_de_la_bajada` de 00006— no
// pueden guardarse para siempre: un aparato que sincroniza cada día sólo recibe las de
// ayer, pero la tabla crece sin techo y un aparato que vuelva con una marca de hace dos
// años se llevaría los borrados de dos años en una sola bajada, por la conexión de allá.
// Para eso están `PodarBajasDeLaBajada` y `PodarLapidasDePedidos` (`db/queries/bajas.sql`).
//
// Y DE AHÍ SALE EL AVISO: en cuanto se poda, un `desde` anterior al horizonte ya no puede
// contestarse por diferencias —las lápidas de ese trozo ya no están— y lo que toca es una
// carga entera. Eso se DICE, no se calla: `CLAUDE.md` §4, «nada se descarta en silencio».
//
// Noventa días y no dos años: es lo que aguanta un aparato guardado en un cajón entre
// campañas sin obligar a reinstalar, y a la vez deja la tabla podable.
const HorizonteDeLapidas = 90 * 24 * time.Hour

func (s *Servidor) cambiosDesde(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()

	var desde *time.Time
	if crudo := strings.TrimSpace(q.Get("desde")); crudo != "" {
		t, err := time.Parse(time.RFC3339, crudo)
		if err != nil {
			httpx.Error(w, r, http.StatusBadRequest,
				"«desde» tiene que ser una fecha en formato RFC3339 (2026-09-14T11:02:31Z)")
			return
		}
		desde = &t
	}

	// `hasta` CIERRA LA VENTANA POR ARRIBA, y se admite del que llama porque quien llama
	// de verdad es el sincronizador, que lo coge de SU reloj ANTES de preguntar: lo que
	// cambie mientras se responde tiene que caer en la ventana siguiente y no perderse
	// entre las dos. Lo que NO se admite nunca es que lo ponga el aparato, y no puede:
	// entre el aparato y esto está el sincronizador, que lo pisa con el suyo.
	//
	// Sin él, el reloj de este proceso. Un aparato que pregunte directamente sigue
	// funcionando igual.
	hasta := time.Now().UTC()
	if crudo := strings.TrimSpace(q.Get("hasta")); crudo != "" {
		t, err := time.Parse(time.RFC3339, crudo)
		if err != nil {
			httpx.Error(w, r, http.StatusBadRequest,
				"«hasta» tiene que ser una fecha en formato RFC3339 (2026-09-14T11:02:31Z)")
			return
		}
		hasta = t.UTC()
	}

	// POR DÓNDE VA LA CADENA. En la primera tanda viene vacío.
	seguir := leerPorDondeSeguir(q.Get("continuar"))

	// EL `desde` DE LA PETICIÓN VALE PARA TODAS LAS COLECCIONES, incluidas las dos que se
	// continúan por cursor. Aquí vivía un `desdeDelPadron` que conservaba el `desde` de la
	// primera tanda dentro del propio cursor, y ya no hace falta: el cursor es ahora
	// `(marca, id)` de la última fila servida, así que él mismo dice desde dónde seguir y
	// el `desde` de la petición sólo se mira cuando no hay cursor.

	salida := CambiosSalida{
		Hasta:    hasta,
		Completa: desde == nil,
		Cambios:  map[string]Conjunto{},
	}
	truncado := false
	// Lo que va a pedir la tanda siguiente. Se copia el cursor de entrada y se van
	// moviendo los desplazamientos de lo que no cupo.
	siguiente := seguir

	// La sucursal de la bajada se resuelve ARRIBA porque los pedidos la necesitan igual
	// que el tablero: el alcance va aparte y en AND, así que esto estrecha y nunca amplía.
	sucursal := sucursalDeLaBajada(r, a)

	tope := int32(topeDeLaBajada(q))
	ventana := alcance.VentanaDeBajada{
		Desde: desde, Hasta: hasta, Sucursal: sucursal, Tope: tope,
	}
	// LA MISMA VENTANA PERO SIN LA SUCURSAL PEDIDA, para las colecciones que NO se sirven
	// por sucursal. No es una copia de más: `ListarRutas`, `ListarVehiculos` y
	// `ListarSucursalesVisibles` sólo miran el ALCANCE —el `?sucursal=` es del tablero—, y
	// una lápida acotada distinto que su lista es exactamente cómo se borra de más.
	ventanaDelAlcance := ventana
	ventanaDelAlcance.Sucursal = nil

	// anotarCorte junta los cortes de todas las colecciones. Manda EL MÁS ATRASADO: la
	// marca que se devuelve tiene que ser una que TODAS las listas hayan servido enteras,
	// o lo que quedó sin mandar de una cae por debajo del próximo `desde` y no se pide
	// nunca más.
	anotarCorte := func(corte *time.Time) {
		if corte == nil {
			return
		}
		truncado = true
		if corte.Before(salida.Hasta) {
			salida.Hasta = *corte
		}
	}

	// --- Pedidos ------------------------------------------------------------
	//
	// LO PRIMERO, y no por orden alfabético: es lo que el logístico se baja cada mañana y
	// lo único sin lo cual el día sin conexión no existe.
	pedidos, corte, err := s.pedidosDeLaBajada(r, a, ventana)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	salida.Cambios["orders"] = pedidos
	// NO CABE TODO. La marca que se devuelve deja de ser el reloj y pasa a ser la de la
	// última fila servida: el aparato vuelve a pedir desde ahí y se lleva el resto.
	// Devolverle el reloj entero sería decirle «ya lo tienes todo hasta ahora» con media
	// tanda sin mandar, y eso no se vuelve a pedir nunca.
	anotarCorte(corte)

	// --- Sucursales ---------------------------------------------------------
	sucursales, err := a.ListarSucursalesVisibles(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	var puestos []any
	// LO QUE SIGUE VIVO, para tachar de `quitados` cualquier lápida que se equivoque.
	// Se llena con la lista ENTERA y no sólo con lo que cambió: lo que no cambió tampoco
	// puede borrarse. Ver `quitadosDe`.
	vivas := make(map[string]bool, len(sucursales))
	for _, b := range sucursales {
		vivas[b.ID.String()] = true
		if !cambioDesde(b.UpdatedAt, desde) {
			continue
		}
		puestos = append(puestos, map[string]any{
			"id": b.ID, "name": b.Name, "externalId": b.ExternalID,
			"address": b.Address, "lat": b.Lat, "lng": b.Lng,
			"originConfigured": b.OriginConfigured, "updatedAt": hora(b.UpdatedAt),
			// LA TASA DE CAMBIO DE ESTA SUCURSAL, y de ninguna otra.
			//
			// Viaja DENTRO de la sucursal a propósito. Es un dato suyo —lo mantiene
			// Entrega, lo trae Accesos y lo deja aquí la tarea de fondo de
			// `refresco_de_tasas.go`— y el aparato tiene que poder pintar los importes en
			// CUP sin conexión, así que tiene que bajar con el resto del día.
			//
			// No va en `settings`, que es GLOBAL: una tasa sola para las ocho sucursales
			// es exactamente cómo Granma acabó enseñando los 685 de La Habana como si
			// fueran suyos.
			//
			// Los cuatro pueden venir null, y el que manda es `cupRateTraidoAt`: **la
			// marca de cuándo, no el número**. Sin ella no hay tasa que valga, porque el
			// esquema viejo traía 320 por defecto y un 320 no demuestra que nadie la haya
			// puesto.
			"cupRate":         b.CupRate,
			"cupRateFuente":   b.CupRateFuente,
			"cupRateTraidoAt": hora(b.CupRateTraidoAt),
			// La frescura la decide ACCESOS (allí son 24 h), no nosotros y no el aparato:
			// quien sabe cuándo una tasa está pasada es quien la mantiene. Aquí se copia
			// el booleano tal cual para que el aparato pueda avisar sin decidir nada.
			"cupRateFresca": b.CupRateFresca,
		})
	}
	// UNA SUCURSAL BORRADA SÓLO PUEDE ESTAR BORRADA: no se muda a ningún sitio, así que no
	// hay lápidas `movido` que valorar. `sinSucursalTambien` va en false porque
	// `ListarSucursalesVisibles` compara `b.id = <la de la persona>` y no deja pasar nada
	// sin sucursal.
	//
	// LA ÚNICA ASIMETRÍA DE TODO ESTO, escrita para que sea una decisión y no un descuido:
	// esta lista se acota con `personaPg()` —a cuáles PUEDO llegar— y las lápidas con
	// `sucursalPg()` —cuál estoy MIRANDO—, que es la que lleva además la sucursal elegida
	// por cabecera. Las dos coinciden salvo en un caso: quien ve las ocho y ha elegido una
	// arriba. A ése se le mandan las bajas de la elegida y no las de las otras siete, así
	// que se entera de MENOS, nunca de más. Se deja así a propósito: `sucursalPg()` nunca
	// es más ancha que `personaPg()`, y de los dos errores posibles —quedarse una sucursal
	// borrada en la lista, o borrar del aparato una que existe— sólo el segundo destruye
	// algo. `branches` son ocho filas que se repintan enteras en cuanto se quita la
	// elección.
	quitadas, corteSuc, err := s.quitadosDe(r, a,
		sqlc.ColeccionDeLaBajadaBranches, ventanaDelAlcance, false, vivas)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	anotarCorte(corteSuc)
	salida.Cambios["branches"] = conjuntoCon(puestos, quitadas)

	// --- Vehículos ----------------------------------------------------------
	vehiculos, err := a.ListarVehiculos(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	puestos = nil
	vivas = make(map[string]bool, len(vehiculos))
	for _, v := range vehiculos {
		vivas[v.ID.String()] = true
		if !cambioDesde(v.UpdatedAt, desde) {
			continue
		}
		puestos = append(puestos, map[string]any{
			"id": v.ID, "name": v.Name, "type": v.TipoNombre, "plate": v.Plate,
			"capacity": v.Capacity, "status": string(v.Status),
			"branchId": idOpcional(v.BranchID), "updatedAt": hora(v.UpdatedAt),
		})
	}
	// `sinSucursalTambien` EN TRUE, y es el único sitio donde va en true. `ListarVehiculos`
	// lleva `OR v.branch_id IS NULL`: un camión sin sucursal lo ven los ocho aparatos, así
	// que cuando se da de baja hay que quitárselo a los ocho. Puesto en false, ese camión
	// se queda en los ocho teléfonos para siempre.
	quitados, corteVeh, err := s.quitadosDe(r, a,
		sqlc.ColeccionDeLaBajadaVehicles, ventanaDelAlcance, true, vivas)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	anotarCorte(corteVeh)
	salida.Cambios["vehicles"] = conjuntoCon(puestos, quitados)

	// --- Rutas --------------------------------------------------------------
	//
	// LA QUE EMPEZÓ TODO ESTO. El 17/09/2026 se borró una ruta desde la web y el teléfono
	// la siguió enseñando: «Completada», 0 paradas, 2,6 km. No había forma de que se
	// enterara, porque aquí se mandaba `quitados: []`.
	rutas, err := a.EspejoListarRutas(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	puestos = nil
	vivas = make(map[string]bool, len(rutas))
	for _, rt := range rutas {
		vivas[rt.ID.String()] = true
		if !cambioDesde(rt.UpdatedAt, desde) {
			continue
		}
		// LOS SIETE CAMPOS QUE FALTABAN, y lo que se veía sin ellos.
		//
		// Visto el 17/09/2026 con la aplicación delante, contra el entorno local: la
		// lista de rutas del aparato enseñaba **`$0.00`** en una ruta de 720 USD,
		// «Sin punto de partida» teniendo almacén, y una raya donde va la fecha. La
		// fila ya traía los tres —`ListarRutasRow` los tiene desde siempre— y esta
		// función simplemente no los escribía.
		//
		// Es el fallo que más caro sale aquí, y por eso está escrito: un importe en
		// cero **se lee bien y está mal**, y nadie lo desmiente. No hay pantalla en
		// blanco, no hay error, no hay tirón. Sólo un número creíble y falso, igual
		// que los 685 de La Habana que enseñaba Granma.
		//
		// `startedAt` y `finishedAt` van por lo mismo: son la línea de «Salida» y
		// «Regreso» de la hoja del post-despacho, la que firma el chofer. Sin ellos
		// la hoja sale sin horario y tampoco se nota.
		//
		// La guarda está en `TestLaBajadaDeRutasLlevaElImporteYLaDireccion`: si
		// alguien quita una de estas claves, esa prueba la nombra.
		puestos = append(puestos, map[string]any{
			"id": rt.ID, "name": rt.Name, "routeCode": rt.RouteCode,
			"status": string(rt.Status), "originAddress": rt.OriginAddress,
			"originLat": rt.OriginLat, "originLng": rt.OriginLng,
			"totalWeight": rt.TotalWeight, "totalDistance": rt.TotalDistance,
			"totalPrice": rt.TotalPrice, "deliveryDate": hora(rt.DeliveryDate),
			"vehicleId": idOpcional(rt.VehicleID), "branchId": idOpcional(rt.BranchID),
			"creadoPor": rt.CreadoPor,
			"startedAt": hora(rt.StartedAt), "finishedAt": hora(rt.FinishedAt),
			"createdAt": hora(rt.CreatedAt),
			"paradas":   rt.Paradas, "updatedAt": hora(rt.UpdatedAt),
		})
	}
	// `sinSucursalTambien` en FALSE: `ListarRutas` filtra `r.branch_id = <la mía>` a secas,
	// y una ruta sin sucursal no la ve un aparato acotado. Ponerlo en true le mandaría
	// lápidas de rutas que nunca tuvo.
	quitadas, corteRut, err := s.quitadosDe(r, a,
		sqlc.ColeccionDeLaBajadaRoutes, ventanaDelAlcance, false, vivas)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	anotarCorte(corteRut)
	salida.Cambios["routes"] = conjuntoCon(puestos, quitadas)

	// --- Catálogo -----------------------------------------------------------
	// UNA FILA DE MÁS, igual que en los pedidos: con exactamente `tope` filas no hay forma
	// de distinguir «caben justo» de «hay más», y dar por buena la primera deja al aparato
	// sin volver a pedir lo que falta.
	marcaCursor, idCursor := seguir.Productos.leer()
	productos, err := a.EspejoDiferenciasDeProductos(r.Context(), alcance.TandaDelPadron{
		Desde: desde, Hasta: hasta, Tope: tope + 1,
		CursorMarca: marcaCursor, CursorID: idCursor,
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// LA TANDA SIGUIENTE EMPIEZA DONDE ACABÓ ÉSTA, y el `hasta` que se devuelve es la
	// marca de la última fila servida. Antes esto era
	// `truncado = truncado || len(productos) >= TopeDeBajada` sobre una lista ordenada por
	// NOMBRE: se decía que quedaba más y la marca que se devolvía era el reloj, así que lo
	// que no cupo quedaba por debajo del próximo `desde` y no lo pedía nadie nunca más.
	productos, curProd, corteProdTanda := tandaDeLaBajada(r, productos, int(tope), "products",
		func(p sqlc.Product) time.Time { return p.UpdatedAt.Time },
		func(p sqlc.Product) uuid.UUID { return p.ID })
	siguiente.Productos = curProd
	anotarCorte(corteProdTanda)
	puestos = nil
	for _, p := range productos {
		// SIN `cambioDesde` AQUÍ, y no se olvidó: el filtro por marca vive EN EL SQL desde
		// el 16/09/2026. Volver a filtrar en Go sobre las filas ya servidas descuadraría
		// la cuenta del corte —se emitirían menos filas de las que el cursor da por
		// servidas— y eso es exactamente cómo se pierde una fila sin que salte nada.
		puestos = append(puestos, map[string]any{
			"id": p.ID, "name": p.Name, "weight": p.Weight, "sku": p.Sku,
			"sucursalCodigo": p.SucursalCodigo, "price": p.Price, "stock": p.Stock,
			"unit": p.Unit, "category": p.Category, "updatedAt": hora(p.UpdatedAt),
		})
	}
	// LAS LÁPIDAS DEL CATÁLOGO VAN SIN SUCURSAL, Y ESO SE DECIDIÓ ASÍ. Merece leerse
	// entero, porque el catálogo NO es global: `EspejoListarProductos` lo acota por
	// `sucursal_codigo` (el CÓDIGO —STG, HOL—, no el uuid), así que a un aparato le llegan
	// ids que su lista nunca le enseñó.
	//
	//   · No borra de más, y eso es lo que decide. Una lápida sólo nace de un `DELETE` de
	//     verdad: esa fila ya no existe para NADIE, así que quitársela a quien no la tenía
	//     es una orden que no encuentra nada y no hace nada. Cuesta unos cuantos ids por la
	//     conexión y no cuesta un solo dato.
	//   · `sinSucursalTambien` EN TRUE es lo que las deja pasar: sus lápidas no llevan
	//     sucursal y el alcance de quien pregunta sí. En false, a un logístico de Camagüey
	//     no le llegaría NI UNA baja del catálogo.
	//   · LO QUE SIGUE SIN CUBRIRSE, dicho para que no se dé por hecho: un producto al que
	//     le CAMBIAN el `sucursal_codigo` sale del alcance sin borrarse y no lleva lápida,
	//     así que se le queda puesto al aparato de la sucursal vieja. Es el mismo agujero
	//     que había antes de esto; taparlo pide guardar el código en la lápida y un
	//     disparador de `UPDATE OF sucursal_codigo`.
	//
	// Y `vivos` va nil: el catálogo se sirve POR TANDAS, así que aquí nunca está la lista
	// entera contra la que tachar. Se puede prescindir de la red porque la única lápida que
	// puede nacer aquí es `borrado` —no hay `movido` sin columna de sucursal— y una fila
	// borrada no puede estar a la vez en `puestos`.
	quitados, corteProd, err := s.quitadosDe(r, a,
		sqlc.ColeccionDeLaBajadaProducts, ventanaDelAlcance, true, nil)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	anotarCorte(corteProd)
	salida.Cambios["products"] = conjuntoCon(puestos, quitados)

	// --- Clientes -----------------------------------------------------------
	//
	// OJO: los clientes se filtran por `synced_at` y no por `updated_at`, porque es lo
	// único que trae la consulta. Significan cosas parecidas pero no iguales —`synced_at`
	// es «cuándo lo trajo PEDIDO»—, y mientras sea eso lo que hay, es lo que se usa.
	marcaCursor, idCursor = seguir.Clientes.leer()
	clientes, err := a.EspejoDiferenciasDeClientes(r.Context(), alcance.TandaDelPadron{
		Desde: desde, Hasta: hasta, Tope: tope + 1,
		CursorMarca: marcaCursor, CursorID: idCursor,
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	clientes, curCli, corteCliTanda := tandaDeLaBajada(r, clientes, int(tope), "customers",
		func(c sqlc.DiferenciasDeClientesRow) time.Time { return c.SyncedAt.Time },
		func(c sqlc.DiferenciasDeClientesRow) uuid.UUID { return c.ID })
	siguiente.Clientes = curCli
	anotarCorte(corteCliTanda)
	puestos = nil
	for _, c := range clientes {
		puestos = append(puestos, map[string]any{
			"id": c.ID, "name": c.Name, "phone": c.Phone, "address": c.Address,
			"municipio": c.Municipio, "zona": c.Zona, "lat": c.Lat, "lng": c.Lng,
			"sucursalCodigo": c.SucursalCodigo, "codigo": c.Codigo,
			"vendedor": c.Vendedor, "syncedAt": hora(c.SyncedAt),
			// `source` FALTABA, y sin él los 8.000 del padrón salían como
			// «Manual» en el aparato: la insignia de `tabla_clientes.dart` lee
			// esta columna, y el filtro de origen devolvía **cero** para «de
			// PEDIDO» y los ocho mil para «manual». Una lista creíble y al
			// revés, que es el peor fallo de esta casa.
			"source": textoDe(c.Source),
		})
	}
	// EL PADRÓN ES EL QUE MÁS FALTA LE HACÍA. `BorrarClientesDelEspejoQueYaNoVienen` borra
	// de golpe todos los que PEDIDO dejó de mandar, y sin lápida esos clientes se quedaban
	// en el teléfono del repartidor hasta que alguien reinstalara la aplicación.
	//
	// Vale palabra por palabra lo escrito arriba para el catálogo, incluido lo que NO se
	// cubre: el padrón también se acota por `sucursal_codigo`, las lápidas no lo llevan, y
	// un cliente al que le cambian el código se le queda puesto al aparato de la sucursal
	// vieja. Lo que sí queda resuelto —y es lo gordo— es el borrado de verdad.
	quitados, corteCli, err := s.quitadosDe(r, a,
		sqlc.ColeccionDeLaBajadaCustomers, ventanaDelAlcance, true, nil)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	anotarCorte(corteCli)
	salida.Cambios["customers"] = conjuntoCon(puestos, quitados)

	// --- Ajustes ------------------------------------------------------------
	//
	// LA ÚNICA COLECCIÓN QUE SIGUE CON `quitados` VACÍO, y con su razón: `settings` es UNA
	// fila, global para toda la casa, y no existe ni una sentencia `DELETE FROM settings`
	// en `db/queries/`. No hay baja que contar. El caso de que la fila no exista todavía ya
	// está contestado abajo con `pgx.ErrNoRows`, que es distinto de «se borró».
	//
	// Si algún día se pudiera borrar, la lápida iría en `bajas_de_la_bajada` como las
	// demás y este comentario se cambia por la llamada.
	ajustes, err := a.ObtenerAjustes(r.Context())
	switch {
	case err == nil:
		puestos = nil
		if cambioDesde(ajustes.UpdatedAt, desde) {
			puestos = append(puestos, map[string]any{
				"currency": ajustes.Currency, "cupRate": ajustes.CupRate,
				"cupRateUpdatedAt": hora(ajustes.CupRateUpdatedAt),
				"catalogoTraidoAt": hora(ajustes.CatalogoTraidoAt),
				"updatedAt":        hora(ajustes.UpdatedAt),
			})
		}
		salida.Cambios["settings"] = conjunto(puestos)
	case errors.Is(err, pgx.ErrNoRows):
		salida.Cambios["settings"] = conjunto(nil)
	default:
		httpx.ErrorInterno(w, r, err)
		return
	}

	// --- El tablero ---------------------------------------------------------
	//
	// Las dos colecciones del tablero son POR SUCURSAL, como el tablero mismo. Si quien
	// pide no dice cuál —un Super Admin sin cabecera—, no se le manda el tablero de las
	// ocho mezclado: se le dice que falta elegir.
	if sucursal == nil {
		salida.Faltan = append(salida.Faltan, "boardColumns", "boardPlacements")
		salida.Aviso = "para bajar el tablero hace falta decir la sucursal (?sucursal=<id>)"
	} else {
		columnas, err := a.ListarColumnasDelTablero(r.Context(), *sucursal)
		if err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
		puestos = nil
		vivas = make(map[string]bool, len(columnas))
		for _, c := range columnas {
			vivas[c.ID.String()] = true
			if !cambioDesde(c.UpdatedAt, desde) {
				continue
			}
			puestos = append(puestos, map[string]any{
				"id": c.ID, "branchId": c.BranchID, "nombre": c.Nombre,
				"posicion": c.Posicion, "vehiculoId": idOpcional(c.VehicleID),
				"updatedAt": hora(c.UpdatedAt),
			})
		}
		// AQUÍ SÍ VA LA SUCURSAL PEDIDA (`ventana`, no `ventanaDelAlcance`): las dos
		// colecciones del tablero se sirven POR SUCURSAL, igual que sus listas, y una
		// lápida acotada distinto que su lista es cómo se borra de más. Una zona borrada
		// desde la web es justo el caso que Jose nombró.
		quitadas, corteCol, err := s.quitadosDe(r, a,
			sqlc.ColeccionDeLaBajadaBoardColumns, ventana, false, vivas)
		if err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
		anotarCorte(corteCol)
		salida.Cambios["boardColumns"] = conjuntoCon(puestos, quitadas)

		// El origen va en (0,0) A PROPÓSITO: el `km_al_almacen` de esta consulta no se
		// usa en la bajada. El aparato recalcula la cercanía él mismo con el almacén que
		// bajó por la mañana —así el tablero ordena igual sin red—, y mandarle un número
		// medido desde otro sitio sería darle dos verdades.
		colocados, err := a.ListarPedidosColocados(r.Context(), sqlc.ListarPedidosColocadosParams{
			BranchID: *sucursal,
		})
		if err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
		puestos = nil
		vivas = make(map[string]bool, len(colocados))
		for _, p := range colocados {
			// LA CLAVE DE UNA COLOCACIÓN ES SU PEDIDO, no un id propio: así está la tabla
			// (`board_placements.order_id` es la clave primaria) y así viaja en `puestos`
			// (`pedidoId`). La lápida usa la misma o el aparato no sabría qué borrar.
			vivas[p.OrderID.String()] = true
			if !cambioDesde(p.UpdatedAt, desde) {
				continue
			}
			puestos = append(puestos, map[string]any{
				"pedidoId": p.OrderID, "columnaId": p.ColumnID, "posicion": p.Posicion,
				"colocadoPor": p.ColocadoPor, "colocadoAt": hora(p.ColocadoAt),
				"updatedAt": hora(p.UpdatedAt),
			})
		}
		// LA RED DE SEGURIDAD IMPORTA MÁS AQUÍ QUE EN NINGÚN SITIO. Una tarjeta sale de una
		// zona y vuelve a otra la misma tarde —eso son dos filas en `board_placements` con
		// la MISMA clave— y sin tachar contra lo que está vivo, la bajada diría «tenla» y
		// «bórrala» a la vez. El disparador de 00006 ya quita la lápida al volver a
		// colocarla; esto es el segundo cierre, del lado de quien contesta.
		quitadas, corteColoc, err := s.quitadosDe(r, a,
			sqlc.ColeccionDeLaBajadaBoardPlacements, ventana, false, vivas)
		if err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
		anotarCorte(corteColoc)
		salida.Cambios["boardPlacements"] = conjuntoCon(puestos, quitadas)
	}

	// --- Lo que todavía no se puede servir -----------------------------------
	//
	// `orders` YA NO ESTÁ AQUÍ: se sirve de verdad, arriba, por `DiferenciasDePedidos`.
	//
	// QUEDA `warehouses`, Y QUEDA DECLARADO — no vacío. La decisión, escrita para no
	// tener que volver a tomarla:
	//
	//   Los almacenes viven en ACCESOS, no en esta base, y esto sí se podría preguntar
	//   allí en cada bajada (`s.accesos.AlmacenesDeSucursal`). No se hace, y el motivo no
	//   es la llamada de red: es que **Accesos no da ninguna marca de cambio ni dice qué
	//   borró**. Sin marca no hay diferencias —habría que mandar la lista entera cada
	//   vez— y, sobre todo, sin saber qué se fue, `quitados` sería siempre `[]`: un
	//   almacén retirado en Accesos se quedaría en el aparato para siempre.
	//
	//   Y eso no es un defecto cosmético. Desde el almacén se mide lo que se le cobra al
	//   cliente por el domicilio; un almacén viejo que sigue en el teléfono cobra mal cada
	//   entrega del día y nadie lo nota hasta cuadrar la caja.
	//
	//   Así que se declara. El aparato puede decir en pantalla «los almacenes son los de
	//   la última vez que hubo red», que es la verdad, en vez de creerse al día.
	//
	//   QUÉ LO DESBLOQUEARÍA, por si alguien lo retoma: que Accesos devuelva un
	//   `actualizado_at` por almacén y un id estable siempre presente (hoy es opcional).
	//   Con eso, esta colección se sirve como las demás y se borra este comentario.
	//   Apuntado en `docs/integracion-pendiente.md`.
	salida.Faltan = append(salida.Faltan, "warehouses")
	if salida.Aviso != "" {
		salida.Aviso += "; "
	}
	salida.Aviso += "«warehouses» vive en Accesos, que no da marca de cambio ni dice qué " +
		"borró: se pide allí"

	// --- Una marca demasiado vieja para contestarla por diferencias -----------
	//
	// Las lápidas se podan (`HorizonteDeLapidas`, `PodarBajasDeLaBajada`). Pasado ese
	// horizonte, las bajas de ese trozo YA NO ESTÁN, así que se puede contestar lo que
	// cambió pero no lo que se fue: el aparato se quedaría con rutas, camiones y clientes
	// que ya no existen y creyéndose al día. Eso SE DICE —`CLAUDE.md` §4, nada se descarta
	// en silencio— y no se decide por él: la respuesta sigue siendo válida, y quien tiene
	// que rehacer la carga entera es el aparato.
	if desde != nil && desde.Before(hasta.Add(-HorizonteDeLapidas)) {
		if salida.Aviso != "" {
			salida.Aviso += "; "
		}
		salida.Aviso += fmt.Sprintf(
			"«desde» es de hace más de %d días y las lápidas de ese trozo ya están podadas: "+
				"lo que se borró en ese tiempo NO viaja en «quitados». Hace falta una carga "+
				"entera (sin «desde»)", int(HorizonteDeLapidas.Hours()/24))
	}

	salida.Truncado = truncado
	if truncado {
		// POR DÓNDE SEGUIR, siempre que se diga que queda más, y también cuando lo que
		// quedó corto fueron los pedidos: el catálogo y el padrón ya sirvieron su tanda y
		// el cursor evita volver a mandarla. Quien no lo devuelva NO pierde nada —para eso
		// `hasta` es la marca de la última fila servida—, sólo repite trabajo.
		salida.Continuar = siguiente.escribir()
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// sucursalDeLaBajada: la que se pida por query, si no la del alcance, si no ninguna.
func sucursalDeLaBajada(r *http.Request, a *alcance.Acotado) *uuid.UUID {
	if crudo := strings.TrimSpace(r.URL.Query().Get("sucursal")); crudo != "" {
		if id, err := uuid.Parse(crudo); err == nil {
			// Se devuelve tal cual: el alcance lo vuelve a aplicar dentro de cada
			// consulta, así que una sucursal ajena sale vacía y no filtra nada.
			return &id
		}
	}
	return a.Sucursal()
}

// cambioDesde dice si esta fila entra en la bajada.
//
// Sin `desde` entra todo: es la carga inicial. Una fila SIN marca también entra, y no es
// un descuido — «no sé cuándo cambió» tiene que tratarse como «puede haber cambiado»: lo
// contrario es dejarla fuera para siempre.
func cambioDesde(marca pgtype.Timestamptz, desde *time.Time) bool {
	if desde == nil || !marca.Valid {
		return true
	}
	return marca.Time.After(*desde)
}

// conjunto es para la colección que NO PUEDE TENER BAJAS, hoy sólo `settings`: una fila
// global que nadie borra. Su nombre dice lo que hace y el que lo use tiene que poder
// explicar por qué su colección no se da de baja nunca.
//
// HASTA EL 17/09/2026 LO USABAN OCHO COLECCIONES, y ése era el agujero entero: `branches`,
// `vehicles`, `routes`, `products`, `customers`, `boardColumns` y `boardPlacements`
// contestaban `quitados: []` sin que nadie lo hubiera decidido, y por eso una ruta borrada
// se quedaba en el teléfono para siempre. Las siete usan ahora `conjuntoCon`.
func conjunto(puestos []any) Conjunto {
	return conjuntoCon(puestos, nil)
}

// conjuntoCon normaliza los dos nil a listas vacías: el aparato lee JSON y `null` no se
// recorre —en Dart, un nulo donde se espera una lista es una excepción en mitad de la
// sincronización—.
func conjuntoCon(puestos []any, quitados []string) Conjunto {
	if puestos == nil {
		puestos = []any{}
	}
	if quitados == nil {
		quitados = []string{}
	}
	return Conjunto{Puestos: puestos, Quitados: quitados}
}

// quitadosDe arma el `quitados` de una colección que no es `orders`, leyendo las lápidas
// de `bajas_de_la_bajada` (00006).
//
// Devuelve además LA MARCA DE CORTE cuando no cupo todo (nil si cupo), como los pedidos:
// quien llama la mezcla con las demás y la más atrasada manda, para que la marca que se
// devuelve sea una que TODAS las listas hayan servido enteras.
//
// LAS TRES REGLAS QUE SE CUMPLEN AQUÍ:
//
//  1. EN LA CARGA INICIAL NO SE PREGUNTA. El aparato empieza vacío: no hay nada que
//     quitarle, y mandarle los borrados de los últimos dos años es gastarle la conexión en
//     decirle que borre lo que nunca tuvo. Mismo criterio que `EspejoPedidosQueSalieron`.
//  2. EL ALCANCE Y LA SUCURSAL PEDIDA SE COPIAN DE SU LISTA. Una lápida acotada distinto
//     que su lista es, literalmente, cómo se borra de más. Lo pone quien llama, colección
//     por colección, y cada uno lleva escrito al lado por qué.
//  3. LO QUE SIGUE VIVO NO SE BORRA NUNCA. `vivos` es la lista entera que este mismo
//     manejador acaba de leer, y cualquier lápida que coincida con ella se TACHA y se
//     registra. Es la red contra el único fallo grave de todo esto —que la misma bajada
//     diga «tenlo» y «bórralo», y gane el que aplique el aparato— y contra una lápida mal
//     puesta, que borra trabajo del teléfono. Puede venir nil donde no hay lista entera
//     que comparar (el catálogo y el padrón se sirven por tandas); quien lo hace lo
//     explica allí.
func (s *Servidor) quitadosDe(
	r *http.Request,
	a *alcance.Acotado,
	coleccion sqlc.ColeccionDeLaBajada,
	v alcance.VentanaDeBajada,
	sinSucursalTambien bool,
	vivos map[string]bool,
) ([]string, *time.Time, error) {
	if v.Desde == nil {
		return nil, nil, nil
	}

	// SE PIDE UNA FILA DE MÁS, como en los pedidos: es la forma barata de distinguir
	// «caben justo `tope`» de «hay más y no caben». Con exactamente `tope` filas las dos
	// son indistinguibles, y dar por buena la primera deja al aparato sin volver a pedir.
	sonda := v
	sonda.Tope = v.Tope + 1

	filas, err := a.EspejoBajas(r.Context(), coleccion, sonda, sinSucursalTambien)
	if err != nil {
		return nil, nil, err
	}
	filas, corte := recortarPorMarca(r, filas, int(v.Tope),
		func(f sqlc.BajasDeLaBajadaRow) time.Time { return f.SalioAt.Time })

	quitados := make([]string, 0, len(filas))
	for _, f := range filas {
		if vivos[f.Clave] {
			// Una lápida de algo que sigue en la lista. No se manda, y se deja dicho: o el
			// disparador no limpió al volver a entrar, o la lápida se puso mal. Las dos
			// son fallos que hay que poder encontrar, y ninguno puede costarle al
			// repartidor el trabajo que tiene en el teléfono.
			httpx.Registro(r).Warn("lápida de algo que sigue vivo: no se manda en «quitados»",
				"coleccion", string(coleccion), "clave", f.Clave, "motivo", string(f.Motivo))
			continue
		}
		quitados = append(quitados, f.Clave)
	}
	return quitados, corte, nil
}

// ---------------------------------------------------------------------------
// Los pedidos de la bajada
// ---------------------------------------------------------------------------

// pedidosDeLaBajada arma el conjunto `orders`: lo que cambió y lo que hay que borrar.
//
// Devuelve además LA MARCA DE CORTE cuando no cupo todo (nil si cupo): es la de la última
// fila servida, y quien contesta la usa como `hasta` para que el aparato vuelva a pedir
// justo desde ahí. Es lo que hace que un tope no pierda nada.
//
// LAS TRES REGLAS QUE SE CUMPLEN AQUÍ:
//
//  1. Un pedido tocado después de la marca sale; uno anterior, no. Eso lo decide el SQL,
//     que compara contra `cambiado_at` —el más nuevo del pedido y de sus renglones— y no
//     contra `updated_at` a secas.
//  2. UN PEDIDO ARCHIVADO SALE EN `quitados`, no en `puestos`. En PEDIDO archivar es el
//     borrado blando, y son la inmensa mayoría del histórico: dejarlo en `puestos` con su
//     bandera puesta confía en que el aparato la mire, y el día que no la mire el pedido
//     archivado sigue apareciendo en el tablero y alguien lo carga en el camión.
//  3. Los renglones VIAJAN CON SU PEDIDO. Si cambió una línea, lo que hay que mandar no es
//     un aviso: es la lista de mercancía nueva, o el despacho prepara lo de ayer.
func (s *Servidor) pedidosDeLaBajada(r *http.Request, a *alcance.Acotado, v alcance.VentanaDeBajada) (Conjunto, *time.Time, error) {
	ctx := r.Context()
	tope := int(v.Tope)

	// SE PIDE UNA FILA DE MÁS. Es la forma barata de distinguir «caben justo `tope`» de
	// «hay más y no caben»: con exactamente `tope` filas las dos son indistinguibles, y
	// dar por buena la primera deja al aparato sin volver a pedir lo que falta.
	sonda := v
	sonda.Tope = v.Tope + 1

	filas, err := a.EspejoDiferenciasDePedidos(ctx, sonda)
	if err != nil {
		return Conjunto{}, nil, err
	}
	filas, corte := recortarPorMarca(r, filas, tope, func(f sqlc.DiferenciasDePedidosRow) time.Time {
		return f.CambiadoAt.Time
	})

	puestos := make([]any, 0, len(filas))
	quitados := make([]string, 0)

	// Los renglones de una sola vez para toda la tanda, no uno por pedido: con 2.000
	// pedidos, lo segundo son 2.000 idas y vueltas por la conexión de allá.
	vivos := make([]uuid.UUID, 0, len(filas))
	for _, f := range filas {
		if !f.Archivado {
			vivos = append(vivos, f.ID)
		}
	}
	renglones := map[uuid.UUID][]any{}
	if len(vivos) > 0 {
		lineas, err := a.ListarRenglonesDePedidos(ctx, vivos)
		if err != nil {
			return Conjunto{}, nil, err
		}
		for _, l := range lineas {
			renglones[l.OrderID] = append(renglones[l.OrderID], map[string]any{
				"id": l.ID, "linea": l.Linea, "description": l.Description,
				"quantity": l.Quantity, "packs": l.Packs, "productId": idOpcional(l.ProductID),
				"updatedAt": hora(l.UpdatedAt),
				// EL PESO DEL RENGLÓN, QUE AQUÍ SE QUEDABA FUERA — 28/09/2026.
				//
				// El 26/09 se añadió a `RenglonSalida`, que es lo que sirve
				// `/api/orders`… y esta bajada **no usa esa struct**: arma el renglón a
				// mano, con un mapa suelto. Así que la API mandaba el peso por una puerta
				// y el aparato se bajaba por la otra, donde no iba.
				//
				// Lo que se veía, y lo vio Jose: «no tenemos ni unidades ni peso
				// individual; el pedido sí, pero cada item anda sin nada». El total del
				// pedido salía —ése viene en su propia fila— y los renglones, en blanco.
				//
				// La lección, que es la que importa: **dos sitios que sirven lo mismo y
				// no comparten la struct se separan sin que nada falle.** Es el §3-bis
				// del `CLAUDE.md` con otra cara. Si alguna vez se tocan los campos del
				// renglón, hay que tocar LOS DOS: aquí y `RenglonSalida` en `pedidos.go`.
				"pesoKg":      l.PesoUnitarioKg,
				"pesoLineaKg": l.PesoLineaKg,
			})
		}
	}

	for _, f := range filas {
		if f.Archivado {
			// Archivado en PEDIDO = fuera del aparato. Ver la regla 2 de arriba.
			quitados = append(quitados, f.ID.String())
			continue
		}
		items := renglones[f.ID]
		if items == nil {
			// Lista vacía y no `null`: el aparato recorre lo que llega, y en Dart un nulo
			// donde se espera una lista es una excepción en mitad de la sincronización.
			items = []any{}
		}
		puestos = append(puestos, map[string]any{
			"id":                 f.ID,
			"operationNumber":    f.OperationNumber,
			"customerName":       f.CustomerName,
			"customerPhone":      f.CustomerPhone,
			"address":            f.Address,
			"endAddress":         f.EndAddress,
			"endLat":             f.EndLat,
			"endLng":             f.EndLng,
			"lat":                f.Lat,
			"lng":                f.Lng,
			"weight":             f.Weight,
			"status":             string(f.Status),
			"tripLeg":            string(f.TripLeg),
			"notes":              f.Notes,
			"routeId":            idOpcional(f.RouteID),
			"ultimaRutaId":       idOpcional(f.UltimaRutaID),
			"vehicleId":          idOpcional(f.VehicleID),
			"price":              f.Price,
			"segmentKm":          f.SegmentKm,
			"deliveryPrice":      f.DeliveryPrice,
			"deliveryDistanceKm": f.DeliveryDistanceKm,
			"branchId":           idOpcional(f.BranchID),
			"source":             textoDe(f.Source),
			"externalId":         f.ExternalID,
			"orderDate":          hora(f.OrderDate),
			// `createdAt` FALTABA, y con él se caía una guarda entera.
			//
			// `repositorio_pedidos.dart` acota por fecha así: por `orderDate`, y
			// **si el pedido no lo trae, por `createdAt`** —«o desaparecería de
			// todos los rangos», dice su comentario—. Como esta clave nunca
			// viajaba, esa segunda rama no podía ser cierta nunca: todo pedido
			// que PEDIDO manda sin `order_date` (es `narg`, pasa) se caía de
			// CUALQUIER filtro por fecha en la APK y el escritorio, mientras el
			// servidor y la web sí lo devolvían.
			//
			// Y no saltaba nada, porque la cabecera y la lista salen del mismo
			// `donde()`: los dos números se daban la razón entre ellos, los dos
			// mal. Es el «Sin colocar (722) encima de una lista de 293» al
			// revés.
			"createdAt":         hora(f.CreatedAt),
			"estado":            textoDe(f.Estado),
			"archivado":         f.Archivado,
			"fechaComprometida": hora(f.FechaComprometida),
			"requiereDomicilio": f.RequiereDomicilio,
			"pedidoCosto":       f.PedidoCosto,
			"municipio":         f.Municipio,
			"vendedor":          f.Vendedor,
			"sucursalCodigo":    f.SucursalCodigo,
			"facturaEstado":     textoDe(f.FacturaEstado),
			"facturaNumero":     f.FacturaNumero,
			"facturaDomicilio":  f.FacturaDomicilio,
			// DE DÓNDE SON `items` Y `weight`: `factura` o `pedido`.
			//
			// Cuando la factura cambió lo que se pidió, lo que va en `items` YA son las
			// líneas de la factura —es lo que sube al camión—. Sin esta clave la pantalla
			// enseña un número y no puede decir cuál de los dos es, que es justo lo que
			// hay que saber para no cargar de más. Ver
			// `00009_de_donde_son_los_renglones.sql`.
			"itemsOrigen":   f.ItemsOrigen,
			"stopOrder":     f.StopOrder,
			"deliveredAt":   hora(f.DeliveredAt),
			"resultado":     textoDe(f.Resultado),
			"resultadoNota": f.ResultadoNota,
			"items":         items,
			// La marca que el aparato guarda para la próxima vez. Es `cambiado_at` y NO
			// `updated_at`: con la del pedido a secas, un pedido al que sólo le cambió un
			// renglón volvería a salir en cada bajada para siempre.
			"updatedAt": hora(f.CambiadoAt),
		})
	}

	// --- Lo que se fue ------------------------------------------------------
	//
	// EN LA CARGA INICIAL NO SE PREGUNTA. El aparato empieza vacío: no hay nada que
	// quitarle, y mandarle los borrados de los últimos dos años es gastarle la conexión
	// en decirle que borre lo que nunca tuvo.
	if v.Desde != nil {
		salidas, err := a.EspejoPedidosQueSalieron(ctx, sonda)
		if err != nil {
			return Conjunto{}, nil, err
		}
		salidas, corteSalidas := recortarPorMarca(r, salidas, tope,
			func(f sqlc.PedidosQueSalieronDelAlcanceRow) time.Time { return f.SalioAt.Time })
		for _, f := range salidas {
			quitados = append(quitados, f.OrderID.String())
		}
		// De los dos cortes manda EL MÁS ATRASADO: la marca que se devuelve tiene que ser
		// una que las dos listas hayan servido enteras. Con la más nueva, lo que quedó sin
		// mandar de la otra cae por debajo del próximo `desde` y no se pide nunca más.
		corte = laMasAtrasada(corte, corteSalidas)
	}

	return Conjunto{Puestos: puestos, Quitados: quitados}, corte, nil
}

// recortarPorMarca deja la tanda en `tope` filas y dice por qué marca se cortó.
//
// Devuelve nil como marca cuando cupo todo — que es el caso normal y el que no lleva
// `truncado`.
//
// EL DETALLE QUE PARECE UN ADORNO Y NO LO ES: el corte no puede partir un grupo de filas
// que comparten la misma marca. Postgres le pone a todas las filas de una transacción la
// MISMA hora (`now()` es la del inicio de la transacción), así que una tanda del espejo de
// 200 pedidos son 200 filas con el mismo `updated_at` al microsegundo. Si el corte cayera
// en medio y se devolviera esa marca como `hasta`, la próxima bajada pediría «a partir de
// ahí» y las que quedaron dentro del grupo no saldrían nunca más. Por eso se recorta el
// grupo entero y se corta por la marca anterior.
func recortarPorMarca[T any](r *http.Request, filas []T, tope int, marca func(T) time.Time) ([]T, *time.Time) {
	if tope <= 0 || len(filas) <= tope {
		return filas, nil
	}
	primeraQueNoCabe := marca(filas[tope])
	servidas := filas[:tope]
	ultima := marca(servidas[tope-1])

	if primeraQueNoCabe.After(ultima) {
		// El grupo de `ultima` está entero dentro. Se corta limpio por ahí.
		return servidas, &ultima
	}

	// El grupo está partido: fuera entero.
	i := tope - 1
	for i >= 0 && !marca(servidas[i]).Before(ultima) {
		i--
	}
	if i < 0 {
		// TODA la tanda comparte una sola marca y aun así no cabe: una sola transacción
		// escribió más pedidos que el tope. No hay corte posible que no parta el grupo, así
		// que se sirve lo que cabe y SE DEJA DICHO — es el único caso en que esta bajada
		// puede dejarse filas atrás, y tiene que verse en el registro y no adivinarse.
		httpx.Registro(r).Warn("una sola marca no cabe en el tope de la bajada: puede perderse parte de la tanda",
			"marca", ultima, "tope", tope)
		return servidas, &ultima
	}
	corte := marca(servidas[i])
	return servidas[:i+1], &corte
}

// tandaDeLaBajada recorta una colección que se continúa por cursor —el catálogo y el
// padrón— y devuelve las tres cosas que hacen falta para que un tope no pierda nada:
//
//  1. LAS FILAS SERVIDAS. Se le pasa la tanda pedida con UNA FILA DE MÁS (`tope+1`): con
//     exactamente `tope` no hay forma de distinguir «caben justo» de «hay más y no caben»,
//     y dar por buena la primera deja al aparato sin volver a pedir lo que falta.
//  2. EL CURSOR de la última fila servida, `(marca, id)`. Es lo único que sirve cuando un
//     grupo de filas con la misma marca es más grande que el tope, que aquí no es un caso
//     de laboratorio: el traspaso metió los 7.975 clientes en una transacción y comparten
//     `synced_at` al microsegundo.
//  3. LA MARCA SEGURA para devolver como `hasta`: la mayor cuyo grupo se sirvió ENTERO.
//     Quien pierda el cursor vuelve a pedir desde ahí y no se deja una sola fila.
//
// Nil como marca es «cupo todo», que es el caso normal y el que no lleva `truncado`.
func tandaDeLaBajada[T any](r *http.Request, filas []T, tope int, coleccion string,
	marca func(T) time.Time, id func(T) uuid.UUID) ([]T, cursorDeTanda, *time.Time) {

	cursor := func(servidas []T) cursorDeTanda {
		if len(servidas) == 0 {
			return cursorDeTanda{}
		}
		u := servidas[len(servidas)-1]
		return cursorDeTanda{Hay: true, Marca: marca(u), ID: id(u)}
	}

	if tope <= 0 || len(filas) <= tope {
		return filas, cursor(filas), nil
	}

	servidas := filas[:tope]
	ultima := marca(servidas[tope-1])
	primeraQueNoCabe := marca(filas[tope])

	// El grupo de `ultima` cabe entero: se corta limpio por ahí.
	if primeraQueNoCabe.After(ultima) {
		return servidas, cursor(servidas), &ultima
	}

	// EL GRUPO ESTÁ PARTIDO. Las filas se sirven igual —el cursor sabe por dónde seguir—,
	// pero `ultima` YA NO SIRVE como `hasta`: devolverla dejaría fuera lo que queda del
	// grupo para cualquiera que vuelva a pedir por marca. Se retrocede a la marca anterior,
	// que sí está servida entera.
	i := tope - 1
	for i >= 0 && !marca(servidas[i]).Before(ultima) {
		i--
	}
	if i >= 0 {
		anterior := marca(servidas[i])
		return servidas, cursor(servidas), &anterior
	}

	// TODA LA TANDA ES UN SOLO GRUPO y no cabe: no hay ninguna marca servida entera. Se
	// devuelve la anterior por un microsegundo —que es la resolución de un `timestamptz` de
	// Postgres, así que no se salta ninguna fila— y se deja dicho: a partir de aquí, el
	// cursor es lo ÚNICO que hace avanzar la cadena, y quien lo pierda repetirá esta misma
	// tanda para siempre en vez de perder filas. De los dos males, ése es el que se ve.
	httpx.Registro(r).Warn("una sola marca no cabe en el tope de la bajada: sin el cursor la cadena no avanza",
		"coleccion", coleccion, "marca", ultima, "tope", tope)
	antes := ultima.Add(-time.Microsecond)
	return servidas, cursor(servidas), &antes
}

// laMasAtrasada: de dos cortes, el que menos avanza. Nil es «no hubo corte», así que no
// limita nada y gana el otro.
func laMasAtrasada(a, b *time.Time) *time.Time {
	switch {
	case a == nil:
		return b
	case b == nil:
		return a
	case b.Before(*a):
		return b
	default:
		return a
	}
}

// topeDeLaBajada: cuántas filas por colección y por tanda.
//
// Se admite del que llama —el sincronizador lo manda, porque es quien sabe la conexión que
// hay— pero ACOTADO. Un tope de cero o negativo se traga la tanda entera sin `truncado` y
// el aparato se queda sin la mitad del día creyendo que lo tiene todo; uno enorme es
// pedirle a la conexión de allá algo que no va a terminar nunca.
func topeDeLaBajada(q url.Values) int {
	n, err := strconv.Atoi(strings.TrimSpace(q.Get("tope")))
	if err != nil || n <= 0 {
		return TopeDeBajada
	}
	return min(n, TopeDeBajada)
}
