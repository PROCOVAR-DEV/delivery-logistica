package identidad

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/sha512"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"hash"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
)

// EL VERIFICADOR DEL TOKEN DE AUTH, que es lo que este servicio debió tener desde el
// principio.
//
// # Por qué existe, y qué pasaba sin él
//
// `DeCabeceras` saca la identidad de `X-Persona`, que debía poner «el proxy que verifica
// el token delante de este servicio». **Ese proxy no existe.** Traefik enruta
// `reparto.procovar.cloud/sync` directo al contenedor y no añade ninguna cabecera, así que
// `X-Persona` llegaba SIEMPRE vacía y este servicio contestaba 401 a todo.
//
// Lo que eso provocaba aguas arriba es mucho peor que un 401: el cliente de la aplicación
// trata un 401 que sobrevive a renovar como «la sesión murió», así que **echaba a la
// persona a la pantalla de acceso en cuanto volvía la señal** — justo en el momento en el
// que iba a subir el trabajo del día. Visto el 16/09/2026 con el teléfono en la mano:
// «cogio internet y volvio a cerrarme la session y no subio nada».
//
// Y no subió nunca nada: `POST /sync/aparato` llevaba 401 desde el primer día.
//
// El propio comentario de `identidad.go` avisaba de la condición —«confiar en una cabecera
// es seguro exactamente mientras nadie más pueda llegar a este puerto»— y el puerto está
// publicado en internet. O sea que la premisa se rompió al desplegar, no al programar.
//
// # Qué se lee
//
// El mismo token de auth que ya verifica `reparto-api`, con el mismo secreto y las mismas
// reglas: HS256, `alg` que tiene que coincidir con uno nuestro, firma comparada en tiempo
// constante, y `exp` obligatorio. Un token sin caducidad es una sesión que no muere nunca.
//
// El alcance sale como en `reparto-api`: **la sucursal del token manda, y sin sucursal se
// ven todas** (Super Admin). Dos reglas distintas en dos servicios sería peor que el fallo
// que se está arreglando.

var algoritmos = map[string]func() hash.Hash{
	"HS256": sha256.New,
	"HS384": sha512.New384,
	"HS512": sha512.New,
}

// ErrSinPermisoDeReparto: el token es bueno y es de alguien, pero su rol no entra a Reparto.
//
// NO ES UN `ErrSinSesion` A PROPÓSITO. Un 401 que sobrevive a renovar mata la sesión en el
// cliente y lo manda a la puerta; esto es un 403 con `codigo`, y lo que la app hace con él es
// enseñar «no tienes permiso» y mandar a Accesos. Ver [Exigir].
var ErrSinPermisoDeReparto = errors.New("el rol no entra a Reparto")

// ErrSesionInvalidada: el token es bueno de firma y de fecha, pero Accesos cortó las sesiones de esa
// persona (alcance `todo`) DESPUÉS de emitirlo. Cuelga de [ErrSinSesion]: sale como un 401, EXACTAMENTE
// como un token inválido, y NO como un 403 — el cliente trata un 401 como sesión caducada, renueva, y
// es Accesos quien decide si la sesión murió o sólo falta un permiso. Un 403 aquí mataría la cola.
var ErrSesionInvalidada = fmt.Errorf("%w: Accesos cortó la sesión", ErrSinSesion)

// Invalidaciones es lo que se pregunta para saber si un token de acceso ya no vale. La implementa
// `sesiones.Registro` y TIENE QUE CONTESTAR SIN RED: se pregunta en cada petición. `iatMs` es el
// `iatms` del token (milisegundos, 0 si no lo trae) y `iatSeg` su `iat` en SEGUNDOS, de donde se
// cae a `iat*1000`. Ver `internal/sesiones`.
//
// DOS REGLAS, según de quién sea el token:
//   - `ElBearerNoVale`: el de la APK y el escritorio (y el de entrega). Sólo cuentan los cortes `todo`: un
//     cierre de sesión del navegador no echa al teléfono.
//   - `LaCookieNoVale`: el de una SESIÓN WEB (`web:true`, el que da `/api/me` y la bandeja web manda de
//     Bearer). Cuentan los `web` y los `todo` (max): quien cerró sesión en el navegador deja de pasar la
//     puerta del revisor (auditoría de seguridad, 09/10/2026, SERIO 2).
type Invalidaciones interface {
	ElBearerNoVale(persona string, iatSeg, iatMs int64) bool
	LaCookieNoVale(persona string, iatMs int64) bool
}

// ErrTokenRoto: no es un JWT, o no se puede leer.
var ErrTokenRoto = errors.New("token ilegible")

// Resolutor traduce el CÓDIGO de la sucursal a NUESTRO id.
//
// LO QUE ACCESOS FIRMA ES EL CÓDIGO —`CAM`, `HOL`, `STG`—, no un uuid: es la única clave
// que cruza los cinco sistemas de Procovar, porque los identificadores internos de cada
// aplicación no se parecen en nada (`apk-tokens.ts`, `firmarAcceso`, y el token de la web
// que emite `api/internal/api/auth_web.go`).
//
// Aquí eso se hacía `uuid.Parse("CAM")`, fallaba, y **todo el protocolo contestaba 401**:
// `POST /sync/aparato` el primero, y sin alta no hay `POST /sync/subida` —contesta 404—,
// así que la cola del aparato no subía NUNCA. Es el mismo cuadro del 16/09/2026 que este
// fichero cuenta más arriba, por otro camino: el cliente trata un 401 que sobrevive a
// renovar como «la sesión murió» y echa a la persona a la pantalla de acceso justo cuando
// vuelve la señal, con el día del almacén dentro.
//
// La traducción la hace quien tiene la tabla, que es `reparto-api`
// (`GET /api/service/sucursal?codigo=CAM`). Aquí no se copia la lista de sucursales: una
// segunda copia es un segundo sitio que se queda viejo.
type Resolutor func(ctx context.Context, codigo string) (uuid.UUID, error)

// ErrNoSePudoComprobar: el código no se pudo traducir porque el reparto no contestó.
//
// VA SEPARADO DE `ErrSinSesion` A PROPÓSITO, y es la diferencia entre un susto y perder el
// día: un 401 mata la sesión en el cliente (`docs/identidad.md`, regla 3), mientras que un
// 5xx conserva los tokens y reintenta. Si un tropiezo del reparto saliera por aquí como
// 401, el aparato se quedaría en la puerta con la cola dentro — exactamente lo que este
// arreglo viene a evitar.
var ErrNoSePudoComprobar = errors.New("no se pudo comprobar la sucursal")

// DeToken construye la fuente de identidad que verifica el token de auth.
//
// `resolutor` puede ser nil sólo donde no haya códigos que traducir (pruebas de firma).
func DeToken(secreto []byte, resolutor Resolutor) Fuente {
	return DeTokenConInvalidaciones(secreto, resolutor, nil)
}

// DeTokenConInvalidaciones es [DeToken] además de rechazar el token emitido ANTES de un corte de
// sesiones de Accesos (`inv`, que puede ser nil: Redis sin configurar o caído no cambia nada). El
// rechazo es [ErrSesionInvalidada], o sea un 401 normal.
func DeTokenConInvalidaciones(secreto []byte, resolutor Resolutor, inv Invalidaciones) Fuente {
	return func(r *http.Request) (Identidad, error) {
		crudo := bearerDe(r)
		if strings.TrimSpace(crudo) == "" {
			return Identidad{}, ErrSinSesion
		}
		id, codigo, err := verificar(crudo, secreto, inv)
		if err != nil {
			return Identidad{}, err
		}
		if codigo != "" {
			if resolutor == nil {
				return Identidad{}, fmt.Errorf(
					"%w: el token trae el código %q y no hay con qué traducirlo", ErrSinSesion, codigo)
			}
			s, err := resolutor(r.Context(), codigo)
			if err != nil {
				// El resolutor distingue «no es de ninguna sucursal» (ErrSinSesion) de
				// «no pude preguntarlo» (ErrNoSePudoComprobar). Se pasa tal cual.
				return Identidad{}, err
			}
			id.Sucursal = s
		}
		// Se guarda DESPUÉS de verificar, nunca antes: lo que se reenvía al reparto tiene
		// que ser un token que ya pasó por la firma, el `exp` y el alcance de aquí.
		id.Token = crudo
		return id, nil
	}
}

// bearerDe saca el token de `Authorization: Bearer …`; vacío si no viene o viene de otra forma.
func bearerDe(r *http.Request) string {
	if cab := r.Header.Get("Authorization"); cab != "" {
		if partes := strings.Fields(cab); len(partes) == 2 && strings.EqualFold(partes[0], "Bearer") {
			return partes[1]
		}
	}
	return ""
}

type reclamos struct {
	Sub           string   `json:"sub"`
	ID            string   `json:"id"`
	BranchID      string   `json:"branchId"`
	BranchIDSnake string   `json:"branch_id"`
	Sucursal      string   `json:"sucursal"`
	Role          string   `json:"role"`
	Rol           string   `json:"rol"`
	Roles         []string `json:"roles"`
	Exp           *float64 `json:"exp"`
	Nbf           *float64 `json:"nbf"`
	// `iat` en SEGUNDOS y `iatms` en MILISEGUNDOS: con ellos se compara el corte de sesiones de
	// Accesos (`iatms` manda si viene). Ausentes son 0.
	Iat   *float64 `json:"iat"`
	IatMs *float64 `json:"iatms"`
	// `entradas` EN CRUDO: las llaves `<app>.entrar` que firma Auth. Ausente (len 0), `[]`,
	// `null` y «no es un array» son cosas distintas. Ver [entradasDelToken].
	Entradas json.RawMessage `json:"entradas"`

	// LO QUE DISTINGUE AL TOKEN DE ENTREGA A REVISIÓN (`docs/bandeja-de-revision.md`, B.1).
	//
	// `TieneAmbito` es si la clave VIENE, sea cual sea su valor y como sea que esté escrita
	// (`ambito`, `Ambito`, `AMBITO`): una rutas normal rechaza a quien la traiga, así que «viene
	// vacía», «null» o «un número» NO pueden colarse por no ser un texto. `Ambito` es el valor en
	// crudo, para compararlo exacto.
	TieneAmbito bool
	Ambito      json.RawMessage
	Purpose     string
	// `web`: SÓLO lo pone la cookie que firma la web. Dice «esto es una sesión web» (ver [Invalidaciones]).
	Web    bool
	Nombre string // `name`: para que la bandeja diga «Yasmani» y no un uuid
	Jti    string
}

// UnmarshalJSON tolera que los campos de texto vengan como `null` o como número.
//
// `branchId: null` es LO NORMAL en un Super Admin, y reventar ahí lo dejaría fuera de su
// propio sistema. Es el mismo trato que le da `reparto-api`.
func (c *reclamos) UnmarshalJSON(b []byte) error {
	var suelto map[string]json.RawMessage
	if err := json.Unmarshal(b, &suelto); err != nil {
		return err
	}
	texto := func(clave string) string {
		v, hay := suelto[clave]
		if !hay {
			return ""
		}
		var s string
		if json.Unmarshal(v, &s) == nil {
			return s
		}
		return ""
	}
	numero := func(clave string) *float64 {
		v, hay := suelto[clave]
		if !hay {
			return nil
		}
		var f float64
		if json.Unmarshal(v, &f) != nil {
			return nil
		}
		return &f
	}
	c.Sub = texto("sub")
	c.ID = texto("id")
	c.Role = texto("role")
	c.Rol = texto("rol")
	if v, hay := suelto["roles"]; hay {
		_ = json.Unmarshal(v, &c.Roles)
	}
	c.BranchID = texto("branchId")
	c.BranchIDSnake = texto("branch_id")
	c.Sucursal = texto("sucursal")
	c.Exp = numero("exp")
	c.Nbf = numero("nbf")
	c.Iat = numero("iat")
	c.IatMs = numero("iatms")
	if v, hay := suelto["entradas"]; hay {
		c.Entradas = v
	}
	// Sin distinguir mayúsculas, como las casa el decodificador de Go en `reparto-api`: «Ambito»
	// no puede ser la forma de colar un token de entrega por las rutas normales.
	for k, v := range suelto {
		if strings.EqualFold(k, "ambito") {
			c.TieneAmbito = true
			c.Ambito = v
		}
	}
	if v, hay := suelto["web"]; hay {
		_ = json.Unmarshal(v, &c.Web) // sólo un booleano `true` cuenta; cualquier otra cosa es «no es web»
	}
	c.Purpose = texto("purpose")
	c.Nombre = texto("name")
	c.Jti = texto("jti")
	return nil
}

// margen: un minuto de holgura contra relojes que no cuadran. El aparato marca la hora del
// suceso y el servidor la suya, y en un teléfono que lleva el día entero sin sincronizar
// esa diferencia existe.
const margen = time.Minute

// verificar devuelve la identidad y, cuando la sucursal del token no es un uuid, el
// CÓDIGO que hay que traducir. Traducirlo aquí es imposible: hace falta ir al reparto.
func verificar(token string, secreto []byte, inv Invalidaciones) (Identidad, string, error) {
	c, id, err := abrir(token, secreto, inv)
	if err != nil {
		return Identidad{}, "", err
	}
	id.Nombre, id.Jti = strings.TrimSpace(c.Nombre), c.Jti
	for _, r := range rolesDelToken(c) {
		if r = strings.TrimSpace(r); r != "" {
			id.Roles = append(id.Roles, r)
		}
	}

	// UN TOKEN DE ENTREGA A REVISIÓN NO ENTRA POR LAS RUTAS NORMALES, y se mira ANTES de la llave.
	//
	// Accesos firma, con este mismo secreto, un token restringido para quien conserva sesión pero
	// perdió `delivery.entrar` (`ambito:"reparto.entrega"`, `entradas:[]`). Hasta hoy sólo era
	// seguro porque `entradas` PRESENTE —aunque `[]`— falla cerrado; bastaba que alguien le
	// metiera la llave (o que un día se cayera a los roles) para que esa misma firma abriera la
	// SUBIDA con la autoridad de la persona y se saltara la revisión. Por eso la regla no es
	// «sin llave no entra» sino «con `ambito` no entra, lleve lo que lleve». Es un 403 con el
	// mismo cuerpo que el de la llave, no un 401: un 401 que sobrevive a renovar mata la sesión.
	// La gemela está en `api/internal/auth`; las ata `docs/ambito-de-entrega.casos.json`.
	if c.TieneAmbito {
		return Identidad{}, "", fmt.Errorf(
			"%w: el token trae `ambito` y sólo abre las rutas de entrega a revisión", ErrSinPermisoDeReparto)
	}
	return resolverAlcance(c, id)
}

// abrir es TODO lo que se le exige a cualquier token de auth antes de mirar a qué viene: forma,
// `alg`, firma en tiempo constante, `exp` obligatorio, `nbf`, `sub` y el corte de sesiones de
// Accesos. Lo comparten [verificar] (las rutas normales) y [DeTokenDeEntrega], para que ninguno
// de los dos pueda aflojar nada de esto por su lado.
func abrir(token string, secreto []byte, inv Invalidaciones) (reclamos, Identidad, error) {
	partes := strings.Split(token, ".")
	if len(partes) != 3 {
		return reclamos{}, Identidad{}, ErrTokenRoto
	}

	cabecera, err := decodificar(partes[0])
	if err != nil {
		return reclamos{}, Identidad{}, ErrTokenRoto
	}
	var cab struct {
		Alg string `json:"alg"`
	}
	if err := json.Unmarshal(cabecera, &cab); err != nil {
		return reclamos{}, Identidad{}, ErrTokenRoto
	}
	// El `alg` del token NO elige nada: sólo tiene que coincidir con uno de los nuestros.
	// Un token que diga `none` o `RS256` se cae aquí, no más abajo.
	nuevoHash, ok := algoritmos[cab.Alg]
	if !ok {
		return reclamos{}, Identidad{}, fmt.Errorf("%w: algoritmo %q no admitido", ErrSinSesion, cab.Alg)
	}

	firma, err := decodificar(partes[2])
	if err != nil {
		return reclamos{}, Identidad{}, ErrTokenRoto
	}
	mac := hmac.New(nuevoHash, secreto)
	mac.Write([]byte(partes[0] + "." + partes[1]))
	// Tiempo constante: comparar firmas con `==` filtra por el tiempo de respuesta
	// cuántos bytes iniciales acertó quien prueba.
	if !hmac.Equal(mac.Sum(nil), firma) {
		return reclamos{}, Identidad{}, ErrSinSesion
	}

	cuerpo, err := decodificar(partes[1])
	if err != nil {
		return reclamos{}, Identidad{}, ErrTokenRoto
	}
	var c reclamos
	if err := json.Unmarshal(cuerpo, &c); err != nil {
		return reclamos{}, Identidad{}, ErrTokenRoto
	}

	ahora := time.Now()
	// Sin `exp` no hay sesión que muera nunca. Se exige.
	if c.Exp == nil {
		return reclamos{}, Identidad{}, fmt.Errorf("%w: el token no trae exp", ErrSinSesion)
	}
	if ahora.After(time.Unix(int64(*c.Exp), 0).Add(margen)) {
		return reclamos{}, Identidad{}, fmt.Errorf("%w: caducado", ErrSinSesion)
	}
	if c.Nbf != nil && ahora.Add(margen).Before(time.Unix(int64(*c.Nbf), 0)) {
		return reclamos{}, Identidad{}, fmt.Errorf("%w: todavía no vale", ErrSinSesion)
	}

	var id Identidad
	id.Persona = primero(c.Sub, c.ID)
	if id.Persona == "" {
		return reclamos{}, Identidad{}, ErrSinSesion
	}

	// ACCESOS CORTÓ LAS SESIONES DE ESTA PERSONA DESPUÉS DE EMITIR ESTE TOKEN: 401, antes que cualquier
	// otra decisión (un 403 de «sin permiso» no puede tapar un token que ya no vale). Sólo memoria.
	if inv != nil {
		var iat, iatms int64
		if c.Iat != nil {
			iat = int64(*c.Iat)
		}
		if c.IatMs != nil {
			iatms = int64(*c.IatMs)
		}
		// `web:true` SÓLO lo firma la web (`auth_web.go`), y es lo que dice «esto es una sesión web»: no se
		// deduce de `iatms`, que Accesos también firma en el token de la APK.
		if c.Web {
			if inv.LaCookieNoVale(id.Persona, iatms) {
				return reclamos{}, Identidad{}, ErrSesionInvalidada
			}
		} else if inv.ElBearerNoVale(id.Persona, iat, iatms) {
			return reclamos{}, Identidad{}, ErrSesionInvalidada
		}
	}

	return c, id, nil
}

// resolverAlcance es lo que `verificar` hacía al final: quién entra a Reparto y de qué sucursal es.
func resolverAlcance(c reclamos, id Identidad) (Identidad, string, error) {
	// QUIÉN ENTRA A REPARTO, antes de mirar la sucursal: a quien no entra no se le traduce
	// ningún código (eso es una llamada al reparto) ni se le dice que le falta la sucursal.
	// Es el MISMO control que `Exigir` de `reparto-api` y por lo mismo que aquí no se delega:
	// este servicio sirve la bajada de su propia base, sin pasar por la API.
	if !puedeEntrarAReparto(c) {
		return Identidad{}, "", fmt.Errorf(
			"%w: rol=%q roles=%v sucursal=%q entradas=%v",
			ErrSinPermisoDeReparto, primero(c.Role, c.Rol), c.Roles,
			strings.TrimSpace(primero(c.BranchID, c.BranchIDSnake, c.Sucursal)), string(c.Entradas))
	}

	sucursal := strings.TrimSpace(primero(c.BranchID, c.BranchIDSnake, c.Sucursal))
	if sucursal == "" {
		// SIN SUCURSAL **NO** SIGNIFICA «TODAS». Sólo lo significa para un SUPER ADMIN.
		//
		// Ésta es la regla 1 de la casa y ya costó dinero una vez: «el alcance sale de
		// quién pregunta, no de lo que mande el cliente… ya pasó en delivery: un operador
		// de Santiago vio los precios de La Habana».
		//
		// Un token sin sucursal lo puede tener alguien a quien todavía no le han dado la
		// suya, o alguien mal dado de alta. Tratar ese hueco como «las ocho» convierte un
		// dato que FALTA en el permiso más grande que hay. Palabras de Jose, 16/09/2026:
		// «sin sucursal no es por el tipo de usuario no hagas eso por q entonces un
		// usuario sin sucursal ve todas eso esta malisimo».
		//
		// Así que se exige el rol. Los dos que ven todo están en `rolesQueVenTodo`;
		// cualquier otro sin sucursal se queda fuera, que es el fallo barato: se arregla
		// dándole la suya.
		if !veTodo(c) {
			return Identidad{}, "", fmt.Errorf(
				"%w: sin sucursal y sin un rol que vea todo no hay alcance que aplicar",
				ErrSinSesion)
		}
		id.EsSuperAdmin = true
		return id, "", nil
	}
	if s, err := uuid.Parse(sucursal); err == nil {
		id.Sucursal = s
		return id, "", nil
	}
	// NO ES UN UUID: es el CÓDIGO que firma Accesos. Se devuelve para que lo traduzca
	// quien tiene la tabla. Lo que NO se hace es tratarlo como «ninguna» —eso convertiría
	// un dato que no se entiende en permiso para verlo todo, que es la regla 1 de la
	// casa— ni darlo por bueno sin comprobar que existe.
	return id, sucursal, nil
}

// LOS DOS ROLES QUE VEN LAS OCHO SUCURSALES, y no hay más.
//
// Salen de la tabla `role` de Accesos, leída el 16/09/2026, que tiene SIETE y no los cinco
// que dice el `CLAUDE.md` de Procovar: ADMINISTRADOR, DESARROLLADOR, GERENTE, GESTOR,
// OPERADOR, SUPER ADMIN y SUPERVISOR.
//
//   - `SUPER ADMIN` administra todo Procovar. Palabras de Jose: «los super
//     administradores pueden tocar en todos lados».
//   - `DESARROLLADOR` está por encima todavía: «y el desarrollador mucho mas arriba aun».
//
// Los otros cinco pertenecen a UNA sucursal, incluido `ADMINISTRADOR` — y por eso la
// comparación es contra el texto exacto y no «contiene admin»: un ADMINISTRADOR sin su
// sucursal se llevaría las ocho, que es justo la fuga que se está tapando.
//
// Se compara como texto porque así es como lo compara PEDIDO, que es la fuente.
var rolesQueVenTodo = []string{"SUPER ADMIN", "DESARROLLADOR"}

// rolAdminHeredado: el `admin` a secas de los tokens VIEJOS de la web. Es un puente y se va con
// ella. Aquí hace EXACTAMENTE lo que en `api/internal/auth/auth.go`: entra a Reparto y, SIN
// sucursal, ve todas (`EsSuperAdmin`). Antes (08/10/2026) entraba pero sin sucursal era un 401
// aquí y super en la api: las dos mitades de Reparto decían cosas distintas de la misma persona.
const rolAdminHeredado = "admin"

func veTodo(c reclamos) bool {
	return tieneAlguno(c, rolesQueVenTodo...) || tieneAlguno(c, rolAdminHeredado)
}

// QUIÉN ENTRA A REPARTO LO DECIDE AUTH — Jose, 08/10/2026: «Reparto no decide quién entra; eso lo
// maneja Auth (Accesos); Reparto es un microservicio y el login es de Auth». Auth firma en el
// token `entradas`, las llaves `<app>.entrar` de la persona, y Reparto entra si y solo si trae
// [llaveEntrarReparto]. Misma regla que `auth.Usuario.PuedeEntrarAReparto` en `reparto-api`, y los
// dos ficheros se cambian JUNTOS: lo ata `docs/roles-de-reparto.casos.json`, que leen las pruebas
// de los dos módulos.
//
//  1. Con `entradas` PRESENTE (aunque sea `[]`) decide SOLO ella: con la llave entra AUNQUE su
//     rol no esté en la lista de abajo, y un rol de la lista SIN la llave NO entra.
//  2. AUSENTE (token anterior al cambio) y con la caída activa, se decide por los roles de ayer.
//
// «Ausente» y «vacío» NO son lo mismo: ausente = «Auth todavía no lo decía» (caída), vacío = «Auth
// dice que no» (403). Presente pero roto (`null`, un texto…) falla cerrado: cuenta como vacío.
const llaveEntrarReparto = "delivery.entrar"

// caidaPorRolesDeTransicion: ver `auth.CaidaPorRolesDeTransicion`.
//
// QUITAR cuando caduquen los tokens/cookies anteriores al 08/10/2026 (cookie web 7 días ->
// 15/10/2026; access token de la APK, 15 minutos): después Reparto decide SOLO por `entradas`, y
// esta constante y `rolesQueEntranAReparto` se borran. `TestLaCaidaPorRolesEsDeTransicion` la
// nombra para que no se olvide.
const caidaPorRolesDeTransicion = true

// LOS ROLES DE LA CAÍDA — los que entraban a Reparto ANTES de que Auth firmara `entradas`
// (Jose, 08/10/2026: «esos roles son los únicos que pueden entrar a Reparto»). `LOGISTICO` va sin
// tilde, como lo firma Accesos; `admin` a secas es el de los tokens viejos de la web. Es una lista
// de los que entran: un rol nuevo en Accesos nace sin acceso.
var rolesQueEntranAReparto = []string{
	"SUPER ADMIN", "DESARROLLADOR", "ADMINISTRADOR", "LOGISTICO", rolAdminHeredado,
}

func puedeEntrarAReparto(c reclamos) bool {
	if llaves, hay := entradasDelToken(c); hay {
		for _, l := range llaves {
			if l == llaveEntrarReparto {
				return true
			}
		}
		return false
	}
	if !caidaPorRolesDeTransicion {
		return false
	}
	return tieneAlguno(c, rolesQueEntranAReparto...)
}

// entradasDelToken: `hay` es false SOLO si el campo no venía. Presente pero que no es un array de
// textos cuenta como PRESENTE Y VACÍO (falla cerrado, no cae a los roles); los elementos que no
// son texto se ignoran. Gemela de `auth.LeerEntradas`.
func entradasDelToken(c reclamos) (llaves []string, hay bool) {
	if len(c.Entradas) == 0 {
		return nil, false
	}
	llaves = []string{}
	var v []any
	if err := json.Unmarshal(c.Entradas, &v); err != nil {
		return llaves, true
	}
	for _, e := range v {
		if t, ok := e.(string); ok {
			llaves = append(llaves, t)
		}
	}
	return llaves, true
}

// rolesDelToken: LOS MISMOS CAMPOS Y EN EL MISMO ORDEN que `reparto-api` (`Verificar`): el
// principal es `role` y, si viene vacío, `rol`; luego `roles`. Antes aquí se miraban `role`,
// `rol` y `roles` A LA VEZ, y un token con `role=GESTOR` y `rol=LOGISTICO` pasaba por el
// sincronizador y no por la API.
func rolesDelToken(c reclamos) []string {
	principal := c.Role
	if principal == "" {
		principal = c.Rol
	}
	return append([]string{principal}, c.Roles...)
}

func tieneAlguno(c reclamos, roles ...string) bool {
	for _, candidato := range rolesDelToken(c) {
		for _, r := range roles {
			if mismoRol(candidato, r) {
				return true
			}
		}
	}
	return false
}

// mismoRol: sin espacios a los lados y sin distinguir mayúsculas, pero SOLO las ASCII.
// `strings.EqualFold` pliega todo Unicode y casa 'ſ' (U+017F) con 's': «ſUPER ADMIN» pasaba
// por SUPER ADMIN (auditoría, 08/10/2026). Se comparan los bytes. Gemela de `auth.MismoRol`.
func mismoRol(a, b string) bool {
	a, b = strings.TrimSpace(a), strings.TrimSpace(b)
	if len(a) != len(b) {
		return false
	}
	for i := 0; i < len(a); i++ {
		if mayusculaASCII(a[i]) != mayusculaASCII(b[i]) {
			return false
		}
	}
	return true
}

func mayusculaASCII(c byte) byte {
	if c >= 'a' && c <= 'z' {
		return c - 'a' + 'A'
	}
	return c
}

func decodificar(s string) ([]byte, error) {
	return base64.RawURLEncoding.DecodeString(s)
}

func primero(valores ...string) string {
	for _, v := range valores {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}
