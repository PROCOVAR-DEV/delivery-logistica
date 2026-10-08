// Package reparto es la frontera con `reparto-api`, que es el dueño de los datos.
//
// El sincronizador no escribe pedidos ni rutas: pide diferencias y reenvía apuntes. Toda la
// lógica de negocio —quién puede armar una ruta, si el peso cabe en el vehículo, si esos
// pedidos ya están en otra— vive allí y se queda allí. Aquí sólo se traduce entre HTTP y
// las dos interfaces de `internal/sincro`.
package reparto

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/identidad"
	"procovar/reparto-sync/internal/sincro"
)

type Cliente struct {
	base  string
	clave string
	http  *http.Client
}

var (
	_ sincro.Origen    = (*Cliente)(nil)
	_ sincro.Aplicador = (*Cliente)(nil)
)

func Nuevo(base, clave string, espera time.Duration) *Cliente {
	return &Cliente{
		base:  base,
		clave: clave,
		http:  &http.Client{Timeout: espera},
	}
}

// sobreCambios es la respuesta de `GET /api/sync/cambios`.
//
// `hasta` Y `continuar` SE LEEN, Y AQUÍ ESTUVO EL AGUJERO. Esta estructura tenía dos
// campos —`cambios` y `truncado`— y los otros dos se tiraban al decodificar. Con ellos en
// el suelo, quien llama no tenía más marca que la que él mismo había mandado, así que una
// tanda cortada anotaba el reloj: el reparto había servido hasta la fila N y el aparato se
// apuntaba «lo tengo todo hasta ahora». Lo que va de la fila N al reloj **no lo vuelve a
// pedir nadie**. Es el §3 del `CLAUDE.md` y es el fallo que no se ve: 200 OK, ninguna
// excepción, ningún registro, y un cuarto de los clientes que no están.
type sobreCambios struct {
	Cambios  sincro.Cambios `json:"cambios"`
	Truncado bool           `json:"truncado"`
	// Hasta es hasta dónde sirvió DE VERDAD: con `truncado`, la marca de la última fila
	// servida, no el reloj del reparto.
	Hasta time.Time `json:"hasta"`
	// Continuar es el cursor de la tanda siguiente. Opaco: se devuelve tal cual.
	Continuar string `json:"continuar"`
}

// Diferencias le pide al reparto lo que cambió en la ventana.
//
// La ventana la PROPONE el sincronizador —el `desde`, el `hasta` y el tope— y el reparto la
// obedece por arriba: nunca sirve más allá del `hasta` que se le manda. Por abajo puede
// quedarse corto, y entonces lo dice con `truncado` y devuelve hasta dónde llegó. Quien
// llama tiene que anotar ESA marca y no la que mandó.
func (c *Cliente) Diferencias(ctx context.Context, v sincro.Ventana) (sincro.Bajada, error) {
	q := url.Values{}
	q.Set("sucursal", v.Sucursal.String())
	q.Set("hasta", v.Hasta.Format(time.RFC3339Nano))
	q.Set("tope", strconv.Itoa(int(v.Tope)))
	if v.Desde != nil {
		q.Set("desde", v.Desde.Format(time.RFC3339Nano))
	}
	// POR DÓNDE SEGUIR, tal cual vino. Sin esto, el catálogo y el padrón no pueden
	// continuarse cuando miles de filas comparten la misma marca —que es lo que hay en
	// producción desde el traspaso— y la cadena se queda repitiendo la primera tanda.
	if v.Continuar != "" {
		q.Set("continuar", v.Continuar)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.base+"/api/sync/cambios?"+q.Encode(), nil)
	if err != nil {
		return sincro.Bajada{}, err
	}
	c.cabeceras(req, time.Time{})

	res, err := c.http.Do(req)
	if err != nil {
		return sincro.Bajada{}, err
	}
	defer res.Body.Close()

	cuerpo, err := io.ReadAll(io.LimitReader(res.Body, 64<<20))
	if err != nil {
		return sincro.Bajada{}, err
	}
	if res.StatusCode != http.StatusOK {
		return sincro.Bajada{}, fmt.Errorf("el reparto contestó %d: %s", res.StatusCode, motivoDe(cuerpo))
	}

	var sobre sobreCambios
	if err := json.Unmarshal(cuerpo, &sobre); err != nil {
		return sincro.Bajada{}, fmt.Errorf("no se entendió la respuesta del reparto: %w", err)
	}
	return sincro.Bajada{
		Cambios:   sobre.Cambios,
		Hasta:     sobre.Hasta.UTC(),
		Truncado:  sobre.Truncado,
		Continuar: sobre.Continuar,
	}, nil
}

// sobreCreado lee el id de lo que se acaba de crear, y **mira los dos sitios donde el
// reparto lo pone**.
//
// Aquí sólo se miraba `id` en la raíz, y el reparto NO contesta así al crear una ruta:
// devuelve `{"ruta": {...}, "avisos": {...}}` (`api/internal/api/rutas.go`,
// `responderConLaRutaYAvisos`). O sea que el id de verdad no volvía nunca al aparato.
//
// Lo que se veía, y costó una tarde el 21/09/2026: se arma una ruta con sus paradas, sube
// bien, el servidor la guarda entera —comprobado en su base: 5 paradas— y en el teléfono
// el detalle dice **«Ver paradas (0)» y «Carga total: 0»** con los kilómetros y los kilos
// al lado. La razón es esta línea: sin id no hay equivalencia, así que el `local-…` del
// aparato no se sustituye nunca; los pedidos, que SÍ bajan del servidor, pasan a colgar
// del id de verdad, y la pantalla se queda mirando una ruta que ya no tiene ninguno.
//
// Jose, viéndolo: «se sigue creando la ruta sin paradas y tiene paradas».
type sobreCreado struct {
	ID   *uuid.UUID `json:"id"`
	Ruta *struct {
		ID *uuid.UUID `json:"id"`
	} `json:"ruta"`

	// QUIÉN SE CAYÓ AUNQUE EL APUNTE ENTRARA. Se reenvía TAL CUAL al aparato.
	//
	// Lo escribe `api/internal/api/tablero.go` (`DescartadoSalida`) en el 201 de armar
	// una zona, con el pedido nombrado, su motivo y qué hacer, y hasta el 28/09/2026
	// se quedaba aquí: este servicio leía el `id` y tiraba el resto. Así, una zona de
	// doce podía parir una ruta de nueve y el teléfono no tenía forma de saberlo.
	//
	// Va como `json.RawMessage` a propósito: esto es un reenvío, no una traducción. El
	// día que el reparto añada un campo al descarte llega al aparato sin tocar nada de
	// aquí, y ningún campo se pierde por el camino por no haberlo declarado.
	Descartados json.RawMessage `json:"descartados"`
}

// id devuelve el primero que haya: la raíz manda, y si no, el de `ruta`.
func (c sobreCreado) id() *uuid.UUID {
	if c.ID != nil {
		return c.ID
	}
	if c.Ruta != nil {
		return c.Ruta.ID
	}
	return nil
}

// Aplicar reenvía un apunte al reparto tal cual, con la hora del aparato y su sucursal.
//
// La traducción de los códigos es lo importante de esta función:
//
//   - 2xx          → aplicado. Si trae `id`, es el de lo que se acaba de crear.
//   - 4xx          → RECHAZO de negocio, con el motivo literal que escribió el reparto. No
//     se reintenta: queda en la bandeja para que una persona lo lea.
//   - 5xx o red    → caída. Es un error normal y el apunte se queda en la cola del aparato.
//
// Confundir los dos últimos es lo que llenaría la bandeja de rechazos falsos el día que el
// reparto se reinicie, y lo que haría reintentar para siempre un apunte que nunca va a
// entrar.
func (c *Cliente) Aplicar(ctx context.Context, p sincro.Peticion) (sincro.Aplicado, error) {
	var cuerpo io.Reader
	if len(p.Cuerpo) > 0 {
		cuerpo = bytes.NewReader(p.Cuerpo)
	}
	// EL `/api` LO PONE ESTE LADO, y aquí estuvo el fallo que lo tiró todo.
	//
	// El aparato encola la ruta SIN prefijo —`/board/columns`, `/routes/{id}`— porque es
	// la que usa contra su propia base. `reparto-api` las sirve todas bajo `/api`, así
	// que reenviarlas tal cual daba **404 en cada apunte**.
	//
	// Lo que eso provocaba no se parecía a un fallo de enrutado. Un 4xx aquí es «rechazo
	// de negocio», así que el 404 acababa en la bandeja de rechazos como si el reparto
	// hubiera dicho que no; y como el apunte rechazado era el que CREA la zona del
	// tablero, los cinco que colocaban pedidos dentro se caían detrás con «el
	// identificador provisional todavía no corresponde a nada». Visto el 16/09/2026: seis
	// apuntes de trabajo real, rechazados, por una barra.
	//
	// No se arregla poniendo `/api` en `REPARTO_URL`: la bajada de ahí arriba ya lo
	// escribe a mano en su línea y quedaría `/api/api/sync/cambios`, que es el mismo
	// fallo del otro lado. Se pone AQUÍ, que es donde se reenvía lo del aparato.
	req, err := http.NewRequestWithContext(ctx, p.Metodo, c.base+"/api"+p.Ruta, cuerpo)
	if err != nil {
		return sincro.Aplicado{}, err
	}
	if len(p.Cuerpo) > 0 {
		req.Header.Set("Content-Type", "application/json")
	}
	c.cabeceras(req, p.Hecho)
	// EL TOKEN DE LA PERSONA manda sobre la clave de servicio, y la SUSTITUYE.
	//
	// Las rutas del aparato (`/api/board/columns`, `/api/routes/…`) exigen sesión de
	// persona: con la clave a secas contestaban 401 «no viene token» y el apunte se
	// quedaba en la cola sin que nadie supiera por qué. Y se quita la clave a propósito:
	// en el reparto hay rutas que, al ver `x-api-key`, se cuelgan un Super Admin sin
	// sucursal —correcto para su temporizador, inaceptable para el trabajo de una
	// persona—. Mandar las dos sería dejar que un apunte de Camagüey se ejecutara con
	// permiso de todas.
	if p.Token != "" {
		req.Header.Del("x-api-key")
		req.Header.Set("Authorization", "Bearer "+p.Token)
	}
	req.Header.Set("X-Apunte", p.Clave)

	res, err := c.http.Do(req)
	if err != nil {
		return sincro.Aplicado{}, err
	}
	defer res.Body.Close()

	datos, err := io.ReadAll(io.LimitReader(res.Body, 8<<20))
	if err != nil {
		return sincro.Aplicado{}, err
	}

	switch {
	case res.StatusCode >= 200 && res.StatusCode < 300:
		var creado sobreCreado
		// Que no venga `id` es normal: hay apuntes que no crean nada (marcar una parada,
		// corregirla). Por eso un cuerpo que no se entiende no tira el apunte.
		_ = json.Unmarshal(datos, &creado)
		return sincro.Aplicado{ID: creado.id(), Descartados: creado.Descartados}, nil
	case res.StatusCode == http.StatusNotFound && !esRespuestaDelReparto(datos):
		// UN 404 QUE NO VIENE DEL REPARTO ES NUESTRO, NO UN RECHAZO.
		//
		// El reparto contesta sus «no encontrado» con un JSON suyo (`{"error": …}`).
		// Un 404 con otra cosa dentro —el `404 page not found` del enrutador de Go— dice
		// que se llamó a una puerta que no existe, o sea un fallo de despliegue o de
		// ruta. Eso NO es «el reparto dijo que no»: es que no llegó a preguntárselo.
		//
		// La diferencia no es teórica. Tratarlo como rechazo dejaba el apunte muerto en
		// la bandeja, pidiendo que una persona decidiera sobre algo que ninguna persona
		// puede arreglar; y con él se caían todos los que dependían de lo que iba a
		// crear. Así se perdieron seis apuntes el 16/09/2026 por un `/api` que faltaba.
		//
		// Como caída, el apunte SE QUEDA EN LA COLA del aparato y sube solo en cuanto la
		// puerta exista. Que es lo que tiene que pasar cuando el fallo es nuestro.
		return sincro.Aplicado{}, fmt.Errorf("el reparto contestó 404 sin decir por qué: la ruta %q no "+
			"existe en el reparto (fallo de despliegue, no rechazo)", p.Ruta)
	case res.StatusCode == http.StatusUnauthorized:
		// UN 401 NO ES UN RECHAZO DE NEGOCIO. NUNCA.
		//
		// Es el mismo error que el 404 de aquí arriba, con otro número: «el reparto dijo
		// que no» exige que el reparto haya entendido la pregunta, y un 401 dice que ni
		// siquiera supo quién la hacía. Eso es nuestro —una credencial que no viajó, un
		// despliegue a medias—, y **ninguna persona delante de un teléfono puede
		// decidir nada sobre ello**.
		//
		// Tratarlo como rechazo es lo que dejó seis apuntes muertos en la bandeja el
		// 16/09/2026: `POST /api/board/columns` contestaba 401 «no viene token» porque
		// este servicio reenviaba con la clave de servicio en vez de con el token de la
		// persona. El apunte que CREA la zona se marcó rechazado, y detrás se cayeron los
		// cinco que colocaban pedidos dentro. Arreglado el reenvío, los seis seguían en
		// la bandeja: un rechazo no se reintenta solo, así que el arreglo no los
		// rescataba. Dos fallos, y el segundo tapaba al primero.
		//
		// Como caída, el apunte SE QUEDA EN LA COLA y sube solo en cuanto la credencial
		// vuelva a valer. Que es lo que tiene que pasar cuando el fallo es nuestro.
		//
		// El 403 sí se queda como rechazo: ahí el reparto SÍ entendió quién preguntaba y
		// dijo que no puede. Reintentar eso para siempre es un bucle, no una defensa.
		return sincro.Aplicado{}, fmt.Errorf("el reparto no reconoció la sesión al subir %q (401): la "+
			"credencial no llegó o no vale — es fallo nuestro, no un rechazo", p.Ruta)
	case res.StatusCode == http.StatusForbidden && esSinPermisoDeReparto(datos):
		// UN 403 CON `codigo: "sin_permiso_reparto"` NO ES UN RECHAZO DEL APUNTE (08/10/2026).
		//
		// Quien dice que no es el ROL de la persona, no lo que pide el apunte: marcarlo
		// `rechazado` dejaría TODA su cola retenida en la bandeja hasta que alguien decidiera
		// (Reintentar/Descartar) por algo que se arregla en Accesos dándole el rol, y el
		// trabajo pendiente se perdería. Se devuelve aparte para que `/sync/subida` conteste
		// 403 con ese `codigo` SIN anotar nada. El 403 del alcance de sucursal NO lleva
		// `codigo` y sigue siendo un rechazo de abajo: ahí el apunte sí es lo que sobra.
		return sincro.Aplicado{}, &sincro.SinPermiso{Motivo: motivoDe(datos)}
	case res.StatusCode >= 400 && res.StatusCode < 500:
		return sincro.Aplicado{}, &sincro.Rechazo{Motivo: motivoDe(datos)}
	default:
		return sincro.Aplicado{}, fmt.Errorf("el reparto contestó %d: %s", res.StatusCode, motivoDe(datos))
	}
}

// cabeceras pone lo COMÚN de cualquier llamada al reparto. Quién firma se decide arriba,
// en `Aplicar`: con el token de la persona cuando lo hay, y sólo entonces se quita esta
// clave.
//
// ## Aquí vivían `X-Persona` y `X-Sucursal`, y no las leía nadie
//
// Se escribían en cada apunte desde el primer día y **el reparto nunca las miró**: un
// `grep` de las dos en `api/` no devuelve un solo lector. Medio protocolo, escrito con
// nadie al otro lado, dando la impresión de que la identidad viajaba cuando no viajaba —
// que es justo lo que hizo tardar en ver por qué `/api/board/columns` contestaba 401.
//
// (Ojo: `X-Sucursal-Id` de `alcance.go` es OTRA cabecera, de la web al reparto. Se parecen
// en el nombre y no tienen nada que ver.)
//
// Ahora la identidad viaja donde tiene que viajar, en el token. Y estas dos se van enteras,
// que es la regla de la casa: quitar algo es quitarlo con sus tipos, sus llamadas y su
// firma.
//
// `X-Hecho-At` se queda porque SÍ tiene lector: `api/internal/api/rutas.go:168`.
func (c *Cliente) cabeceras(req *http.Request, hecho time.Time) {
	req.Header.Set("x-api-key", c.clave)
	req.Header.Set("Accept", "application/json")
	if !hecho.IsZero() {
		// La hora del APARATO, para que el reparto guarde cuándo se hizo y no cuándo
		// llegó. Lo que se marcó a las cuatro tiene que constar como las cuatro.
		req.Header.Set("X-Hecho-At", hecho.UTC().Format(time.RFC3339Nano))
	}
}

// motivoDe saca la frase de `{"error": "..."}`. Es el mensaje literal en español que va a
// leer la persona que tenga que arreglarlo, así que se conserva entero; si la respuesta no
// tiene esa forma, se devuelve lo que vino, recortado.
// esRespuestaDelReparto: si el cuerpo es un `{"error": …}` de los nuestros.
//
// Es lo que separa «el reparto dijo que no» de «se llamó a una puerta que no existe». Lo
// primero lo decide una persona; lo segundo lo arregla un despliegue.
func esRespuestaDelReparto(datos []byte) bool {
	var sobre struct {
		Error string `json:"error"`
	}
	return json.Unmarshal(datos, &sobre) == nil && sobre.Error != ""
}

// esSinPermisoDeReparto: si el cuerpo es el `{"error":…,"codigo":"sin_permiso_reparto"}` del 403
// de rol (`auth.PermitirReparto` en `reparto-api`).
func esSinPermisoDeReparto(datos []byte) bool {
	var sobre struct {
		Codigo string `json:"codigo"`
	}
	return json.Unmarshal(datos, &sobre) == nil && sobre.Codigo == identidad.CodigoSinPermisoReparto
}

func motivoDe(datos []byte) string {
	var sobre struct {
		Error string `json:"error"`
	}
	if err := json.Unmarshal(datos, &sobre); err == nil && sobre.Error != "" {
		return sobre.Error
	}
	texto := string(bytes.TrimSpace(datos))
	if texto == "" {
		return "El reparto no dijo por qué"
	}
	if len(texto) > 500 {
		texto = texto[:500]
	}
	return texto
}

// SucursalPorCodigo traduce el CÓDIGO que firma Accesos (`CAM`) a NUESTRO id.
//
// La tabla `branches` es del reparto, no de aquí, y aquí no se copia: una segunda lista de
// sucursales es una segunda lista que se queda vieja. Ver
// `api/internal/api/sucursales.go` y `internal/identidad/token.go`.
//
// Los tres finales son TRES cosas distintas y se devuelven distintas, porque arriba se
// contestan distinto:
//
//	200  -> el id
//	404  -> ese código no es de ninguna sucursal: sesión que no vale (401 arriba)
//	resto o fallo de red -> NO SE SABE: 503 arriba, que conserva los tokens
func (c *Cliente) SucursalPorCodigo(ctx context.Context, codigo string) (uuid.UUID, error) {
	q := url.Values{}
	q.Set("codigo", codigo)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		c.base+"/api/service/sucursal?"+q.Encode(), nil)
	if err != nil {
		return uuid.Nil, fmt.Errorf("%w: %v", identidad.ErrNoSePudoComprobar, err)
	}
	c.cabeceras(req, time.Time{})

	res, err := c.http.Do(req)
	if err != nil {
		return uuid.Nil, fmt.Errorf("%w: %v", identidad.ErrNoSePudoComprobar, err)
	}
	defer res.Body.Close()
	cuerpo, err := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if err != nil {
		return uuid.Nil, fmt.Errorf("%w: %v", identidad.ErrNoSePudoComprobar, err)
	}

	switch res.StatusCode {
	case http.StatusOK:
	case http.StatusNotFound:
		// LA SUCURSAL NO EXISTE AQUÍ. Es un «no» de verdad y se dice como tal: el aparato
		// no se puede dar de alta y hay que arreglarlo en la oficina. Lo que NO se hace es
		// dejarle pasar sin sucursal, que en el reparto significa las ocho.
		return uuid.Nil, fmt.Errorf("%w: la sucursal %q no existe en el reparto",
			identidad.ErrSinSesion, codigo)
	default:
		return uuid.Nil, fmt.Errorf("%w: el reparto contestó %d: %s",
			identidad.ErrNoSePudoComprobar, res.StatusCode, motivoDe(cuerpo))
	}

	var sobre struct {
		ID uuid.UUID `json:"id"`
	}
	if err := json.Unmarshal(cuerpo, &sobre); err != nil {
		return uuid.Nil, fmt.Errorf("%w: no se entendió la respuesta: %v",
			identidad.ErrNoSePudoComprobar, err)
	}
	if sobre.ID == uuid.Nil {
		// Un uuid en blanco NO es una respuesta buena: guardado en `aparatos.branch_id`
		// sería un aparato que no es de ninguna sucursal.
		return uuid.Nil, fmt.Errorf("%w: el reparto devolvió una sucursal vacía para %q",
			identidad.ErrNoSePudoComprobar, codigo)
	}
	return sobre.ID, nil
}
