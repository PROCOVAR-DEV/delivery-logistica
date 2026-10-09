// Validación de la identidad que emite auth.procovar.cloud.
//
// AQUÍ NO SE COMPRUEBAN CONTRASEÑAS, y no es una tarea pendiente: es la decisión. Quien
// manda en personas, roles y sucursales es auth, y punto (`docs/identidad.md`). Dos
// sitios comprobando contraseñas son dos sitios donde dar de baja a alguien, y el día
// que se olvide uno, la persona despedida sigue entrando por el otro.
//
// Lo que se hace aquí es leer un token ya firmado y creerle SÓLO si la firma cuadra.
//
// La verificación va a mano, con `crypto/hmac`, y no con una biblioteca de JWT. Son
// treinta líneas de recorte de cadenas y un HMAC; a cambio no hay una dependencia más
// que mantener, y sobre todo el algoritmo está FIJADO en el código: la familia de fallos
// clásica del JWT es aceptar el `alg` que venga en el token —`none`, o RS256 verificado
// con la clave pública como si fuera secreto HMAC— y eso aquí no se puede ni escribir.
package auth

import (
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

	"procovar/reparto-api/internal/httpx"
)

var (
	ErrSinToken   = errors.New("no viene token")
	ErrTokenRoto  = errors.New("el token no tiene la forma de un JWT")
	ErrFirma      = errors.New("la firma no cuadra")
	ErrCaducado   = errors.New("el token está caducado")
	ErrSinPersona = errors.New("el token no dice de quién es")
	// ErrAmbito: el token trae `ambito`, o sea que es un token RESTRINGIDO (hoy, el de entrega a
	// revisión: `reparto.entrega`). Ver [Verificador.Verificar].
	ErrAmbito = errors.New("el token es de un ámbito restringido y no abre esta ruta")
)

// Usuario es lo que el token dice de quien pide. Nada de esto se consulta en la base:
// la base de personas es la de auth.
type Usuario struct {
	ID       string // `sub` (APK) o `id` (web) — el identificador de la persona
	Email    string
	Nombre   string
	Rol      string   // el principal, para las comprobaciones que ya existen
	Roles    []string // todos, para lo que venga
	Sucursal string   // "" = no pertenece a ninguna (Super Admin)

	// ENTRADAS: las llaves `<app>.entrar` que AUTH firma en el token (`delivery.entrar`,
	// `pedido.entrar`…). Es lo que decide si la persona entra a Reparto (ver
	// [Usuario.PuedeEntrarAReparto]). `HayEntradas` distingue «el token no traía el campo»
	// (un token anterior al cambio: se cae a la lista de roles) de «traía `entradas: []`»
	// (Auth dice que no entra a nada). NO son lo mismo y una prueba lo ata.
	Entradas    []string
	HayEntradas bool

	// IatMs: cuándo se emitió el token, en MILISEGUNDOS (claim `iatms`). Lo firman la cookie de la
	// web (`auth_web.go`) y, desde el 08/10/2026, Accesos en el token de acceso de la APK. Cero = no
	// lo trae (una cookie anterior a este cambio, o un token de Accesos anterior a él).
	IatMs int64
	// Iat: cuándo se emitió el token, en SEGUNDOS (claim estándar `iat`). Cero = no lo trae.
	Iat int64
	// FirmadoPorLaWeb: el token lleva la marca `web` que SÓLO pone `auth_web.go` (la cookie de la
	// web). Las firmas de Accesos no la llevan. Antes se distinguía por llevar `iatms`; dejó de
	// valer cuando Accesos empezó a firmarlo también en el token de la APK.
	FirmadoPorLaWeb bool
	// SesionWeb: la credencial es de la SESIÓN DE LA WEB —vino en la cookie `token`, o es de las que
	// firma la web— y no del par de la APK y el escritorio. Lo pone [Verificador.delaPeticion].
	SesionWeb bool
}

// LOS ROLES DE VERDAD, escritos como los escribe PEDIDO, que es de donde salen.
//
// Leídos de la tabla `role` de Accesos el 16/09/2026. Son SIETE: ADMINISTRADOR,
// DESARROLLADOR, GERENTE, GESTOR, OPERADOR, SUPER ADMIN y SUPERVISOR.
//
// Aquí se comparaba contra `"admin"` a secas, que **no es ninguno de ellos**. O sea que un
// `SUPER ADMIN` de verdad no pasaba `EsSuperAdmin()` y el catálogo le contestaba «Solo el
// Super Admin puede tocar el catálogo» a la única persona que podía. No se vio porque las
// pruebas montaban el token con `"role": "admin"`, copiando el error del código: una
// prueba que repite la suposición que prueba no prueba nada.
//
// Se comparan como texto exacto, igual que PEDIDO. Nada de «¿contiene admin?»:
// `ADMINISTRADOR` es de UNA sucursal y eso le daría las ocho.
const (
	rolSuperAdmin    = "SUPER ADMIN"
	rolDesarrollador = "DESARROLLADOR"
	rolAdministrador = "ADMINISTRADOR"
	// Sin tilde, tal como lo firma Accesos (08/10/2026). Es el rol de quien arma las rutas.
	rolLogistico = "LOGISTICO"
	// `admin` a secas es lo que traían los tokens VIEJOS de la web de delivery. Se acepta
	// mientras esa puerta siga abierta; el día que se cierre, se quita de aquí.
	rolAdminHeredado = "admin"
)

func (u *Usuario) tieneAlguno(roles ...string) bool {
	for _, candidato := range append([]string{u.Rol}, u.Roles...) {
		for _, r := range roles {
			if MismoRol(candidato, r) {
				return true
			}
		}
	}
	return false
}

// MismoRol: la ÚNICA comparación de roles de la casa. Sin espacios a los lados y sin distinguir
// mayúsculas de minúsculas, pero SOLO las ASCII (A-Z).
//
// Aquí se usaba `strings.EqualFold`, que pliega TODO Unicode, y una auditoría (08/10/2026)
// demostró que casa 'ſ' (U+017F, «s larga») con 's': «ſUPER ADMIN» y «ADMINIſTRADOR» eran
// SUPER ADMIN y ADMINISTRADOR, y entraban a Reparto. Con 'İ' (U+0130) pasa lo mismo en otros
// lenguajes. Los roles los firma Accesos con un catálogo de nombres ASCII: lo que se sale de
// ahí no es una variante del rol, es otro texto. Se comparan los BYTES.
//
// `sync/internal/identidad/token.go` tiene su gemela (`mismoRol`): otro módulo de Go. Las dos se
// atan con `docs/roles-de-reparto.casos.json`, que leen las pruebas de los dos lados.
func MismoRol(a, b string) bool {
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

// EsAdmin: la comprobación de `/api/branches`, que exige administrador.
//
// Entra también `ADMINISTRADOR`, que administra LO SUYO: su sucursal. Que pueda
// administrar no es lo mismo que verlo todo — eso lo decide [EsSuperAdmin].
func (u *Usuario) EsAdmin() bool {
	return u.tieneAlguno(rolSuperAdmin, rolDesarrollador, rolAdministrador, rolAdminHeredado)
}

// EsSuperAdmin: quien manda en todo Procovar, no en una sucursal.
//
// Son DOS roles y nada más. Palabras de Jose, 16/09/2026: «los super administradores
// pueden tocar en todos lados y el desarrollador mucho mas arriba aun».
//
// Antes esto era «EsAdmin() && Sucursal == ""», o sea que lo decidía un HUECO: quien
// llegara sin sucursal pasaba por super. Eso convertía un dato que falta —alguien a quien
// todavía no le han dado la suya— en el permiso más grande que hay. Lo decide el rol.
//
// El alcance por sucursal es otra cosa y se resuelve aparte (`internal/alcance`): un SUPER
// ADMIN que elija una sucursal arriba ve esa, no las ocho.
func (u *Usuario) EsSuperAdmin() bool {
	if u.tieneAlguno(rolSuperAdmin, rolDesarrollador) {
		return true
	}
	// EL `admin` HEREDADO DE LA WEB VIEJA conserva su regla de siempre: admin y SIN
	// sucursal. No se le aplica la nueva porque no tiene los roles nuevos —sus tokens
	// dicen `admin` a secas— y cambiársela lo dejaría fuera de su propio sistema.
	//
	// Es un puente, no la regla: el día que esa puerta se cierre, esto se va con ella.
	return u.tieneAlguno(rolAdminHeredado) && u.Sucursal == ""
}

// LlaveEntrarReparto: la llave que Auth firma en `entradas` a quien puede entrar a Reparto.
// Texto EXACTO —sin recortar, sin mayúsculas, sin plegado Unicode—: es un identificador de
// máquina que escribe Auth, no un rol que alguien teclea.
const LlaveEntrarReparto = "delivery.entrar"

// CaidaPorRolesDeTransicion: mientras valga `true`, un token SIN el campo `entradas` (emitido
// antes de que Auth lo firmara) se decide por la lista de roles de abajo.
//
// QUITAR cuando caduquen los tokens/cookies anteriores al 08/10/2026 (la cookie web dura 7 días
// -> 15/10/2026; el access token de la APK, 15 minutos): después Reparto decide SOLO por
// `entradas`, y esta constante y la lista de roles de `PuedeEntrarAReparto`
// se borran. `TestLaCaidaPorRolesEsDeTransicion` la nombra para que no se olvide.
//
// Jose, 08/10/2026: «Reparto no decide quién entra; eso lo maneja Auth (Accesos); Reparto es un
// microservicio y el login es de Auth». Antes (mismo día) la lista de roles ERA la regla.
const CaidaPorRolesDeTransicion = true

// PuedeEntrarAReparto: QUIÉN ENTRA A REPARTO.
//
//  1. Si el token trae `entradas` (aunque sea `[]`) decide SOLO ella: entra si y solo si trae
//     `delivery.entrar`. Con la llave entra AUNQUE su rol no esté en la lista de abajo (así Auth
//     puede darle acceso a otro rol sin tocar Reparto), y un rol de la lista SIN la llave NO entra.
//  2. Si el token NO trae el campo (anterior al cambio) y la caída está activa
//     ([CaidaPorRolesDeTransicion]), se decide por los roles de ayer: SUPER ADMIN, DESARROLLADOR,
//     ADMINISTRADOR y LOGISTICO (+ el `admin` heredado). Lista de los que ENTRAN: un rol nuevo
//     nace sin acceso; `MismoRol`, sin plegado Unicode.
//
// «Ausente» y «vacío» NO son lo mismo: ausente = «Auth todavía no lo decía» (caída), vacío =
// «Auth dice que no» (403). Las cuentas de servicio (espejo, sync, n8n, webhook de PEDIDO)
// llevan `SUPER ADMIN` puesto a mano y NO pasan por [Verificador.Exigir]: no se tocan.
func (u *Usuario) PuedeEntrarAReparto() bool {
	if u.HayEntradas {
		for _, e := range u.Entradas {
			if e == LlaveEntrarReparto {
				return true
			}
		}
		return false
	}
	if !CaidaPorRolesDeTransicion {
		return false
	}
	return u.tieneAlguno(rolSuperAdmin, rolDesarrollador, rolAdministrador, rolLogistico, rolAdminHeredado)
}

// LeerEntradas interpreta el campo `entradas` tal como llegó. `hay` es false SOLO si el campo no
// venía. Presente pero que no es un array de textos (`null`, un texto, un objeto) cuenta como
// PRESENTE Y VACÍO: ante un campo roto se falla cerrado, no se cae a los roles. Los elementos
// que no son texto se ignoran.
func LeerEntradas(crudo json.RawMessage) (llaves []string, hay bool) {
	if len(crudo) == 0 {
		return nil, false
	}
	llaves = []string{}
	var v []any
	if err := json.Unmarshal(crudo, &v); err != nil {
		return llaves, true
	}
	for _, e := range v {
		if t, ok := e.(string); ok {
			llaves = append(llaves, t)
		}
	}
	return llaves, true
}

// Verificador guarda el secreto. Se construye una vez al arrancar.
type Verificador struct {
	secreto []byte
	// margen para el desfase de reloj entre este servidor y el de auth. Sin él, dos
	// máquinas con medio minuto de diferencia rechazan tokens recién emitidos.
	margen time.Duration

	// inv y borrarCookie los pone [Verificador.ConInvalidaciones] ANTES de servir. Sin ellos
	// (Redis sin configurar, pruebas) no se comprueba nada, que es como era antes.
	inv          Invalidaciones
	borrarCookie func(http.ResponseWriter, *http.Request)
}

func NuevoVerificador(secreto []byte) *Verificador {
	return &Verificador{secreto: secreto, margen: 60 * time.Second}
}

// DelaPeticion saca el token y lo valida.
//
// El orden es el del contrato: cabecera `Authorization: Bearer <token>` primero —es por
// donde entra la APK— y si no, la cookie `token`, que es lo que deja el login único de
// la web.
//
// # SE PRUEBAN TODAS LAS CANDIDATAS, NO LA PRIMERA — 29/09/2026
//
// Aquí se hacía `r.Cookie("token")`, que devuelve **la primera y calla las demás**. Un
// navegador puede traer dos cookies con el mismo nombre sin que sea culpa de nadie: basta
// que otra aplicación de la casa deje una `token` con `Domain=.procovar.cloud` —que viaja
// a todos los subdominios— para que se cuele por delante de la nuestra, que es de host y
// de `Path=/`. Y el orden lo decide el navegador, no nosotros.
//
// Ése es un 401 permanente que no se puede explicar desde fuera: la sesión buena está
// puesta, es válida, y nadie la mira. Probándolas todas la buena entra, y no se pierde
// nada de seguridad porque todas pasan por la misma firma.
//
// El motivo que se devuelve cuando ninguna vale es **el de la primera**, para que el
// registro diga lo mismo que decía en el caso normal de una sola credencial. Cuántas
// había se anota aparte, en [RastroDe] (`cookies_token`).
func (v *Verificador) DelaPeticion(r *http.Request) (*Usuario, error) {
	u, _, err := v.delaPeticion(r, nil)
	return u, err
}

// DelaPeticionDeReparto es [Verificador.DelaPeticion] para las rutas que dejan entrar o no a
// Reparto (`Exigir`, el canal en vivo y `/api/me`): entre las candidatas VÁLIDAS prefiere la
// primera que puede entrar a Reparto, y si ninguna puede, devuelve la primera válida (la que
// explica el 403).
//
// Es el caso de las dos cookies `token` del 29/09/2026, ahora con un rol de por medio: una
// cookie vieja de la misma persona con el rol de antes (GERENTE) delante de la buena (LOGISTICO)
// ganaba por orden y daba un 403 `sin_permiso_reparto` a quien sí tiene permiso. Todas las
// candidatas pasan por la misma firma, así que elegir la que entra no abre nada que no pudiera
// abrir ya la persona con la credencial que trajo.
func (v *Verificador) DelaPeticionDeReparto(r *http.Request) (*Usuario, error) {
	u, _, err := v.delaPeticion(r, (*Usuario).PuedeEntrarAReparto)
	return u, err
}

// DelaPeticionDeRepartoConCredencial es lo mismo y además devuelve la credencial CRUDA que se
// eligió, para que `/api/me` pueda devolver el token de la MISMA cookie que decidió quién es
// la persona (y no el de la primera, que puede ser de otro rol).
func (v *Verificador) DelaPeticionDeRepartoConCredencial(r *http.Request) (*Usuario, string, error) {
	return v.delaPeticion(r, (*Usuario).PuedeEntrarAReparto)
}

func (v *Verificador) delaPeticion(r *http.Request, preferida func(*Usuario) bool) (*Usuario, string, error) {
	candidatas, _, _ := Credenciales(r)
	if len(candidatas) == 0 {
		return nil, "", ErrSinToken
	}
	cookies := valoresDeLaCookie(r)
	var primerFallo, invalidada error
	var primeraValida *Usuario
	var suCredencial string
	yaInvalidadas := map[string]bool{}
	for _, crudo := range candidatas {
		// La web manda el MISMO token en la cookie y en el Bearer: una vez invalidado, no se vuelve
		// a evaluar ni a escribir en el registro.
		if yaInvalidadas[crudo] {
			continue
		}
		u, err := v.Verificar(crudo)
		if err != nil {
			if primerFallo == nil {
				primerFallo = err
			}
			continue
		}
		// UNA CREDENCIAL INVALIDADA POR ACCESOS CUENTA COMO UN FALLO MÁS, y se prueba con las demás:
		// un Bearer viejo delante de una cookie recién emitida no puede echar a quien ya volvió a entrar.
		u.SesionWeb = u.FirmadoPorLaWeb || cookies[crudo]
		if v.sesionInvalidada(u) {
			yaInvalidadas[crudo] = true
			if u.SesionWeb {
				httpx.Registro(r).Info("sesión web invalidada desde Accesos",
					"ruta", r.URL.Path, "persona", u.ID, "emitida_ms", u.IatMs, "via_cookie", cookies[crudo])
				invalidada = errWebInvalidada
			} else {
				httpx.Registro(r).Info("sesión de la APK o el escritorio invalidada desde Accesos",
					"ruta", r.URL.Path, "persona", u.ID, "emitida_s", u.Iat)
				if invalidada == nil {
					invalidada = errAparatoInvalidado
				}
			}
			continue
		}
		if preferida == nil || preferida(u) {
			return u, crudo, nil
		}
		if primeraValida == nil {
			primeraValida, suCredencial = u, crudo
		}
	}
	if primeraValida != nil {
		return primeraValida, suCredencial, nil
	}
	if invalidada != nil {
		return nil, "", invalidada // la causa que se puede arreglar (volver a entrar), no otra
	}
	return nil, "", primerFallo
}

// Verificar comprueba la firma y la vigencia, y devuelve la persona.
func (v *Verificador) Verificar(token string) (*Usuario, error) {
	partes := strings.Split(token, ".")
	if len(partes) != 3 {
		return nil, ErrTokenRoto
	}

	cabecera, err := decodificar(partes[0])
	if err != nil {
		return nil, ErrTokenRoto
	}
	var cab struct {
		Alg string `json:"alg"`
	}
	if err := json.Unmarshal(cabecera, &cab); err != nil {
		return nil, ErrTokenRoto
	}
	// El `alg` del token NO elige nada: sólo tiene que coincidir con uno de los nuestros.
	// Un token que diga `none` o `RS256` se cae aquí, no más abajo.
	nuevoHash, ok := algoritmos[cab.Alg]
	if !ok {
		return nil, fmt.Errorf("%w: algoritmo %q no admitido", ErrFirma, cab.Alg)
	}

	firmaEsperada, err := decodificar(partes[2])
	if err != nil {
		return nil, ErrTokenRoto
	}
	mac := hmac.New(nuevoHash, v.secreto)
	mac.Write([]byte(partes[0] + "." + partes[1]))
	// Comparación en tiempo constante: comparar firmas con `==` filtra por el tiempo de
	// respuesta cuántos bytes iniciales acertó quien prueba.
	if !hmac.Equal(mac.Sum(nil), firmaEsperada) {
		return nil, ErrFirma
	}

	cuerpo, err := decodificar(partes[1])
	if err != nil {
		return nil, ErrTokenRoto
	}
	var c reclamos
	if err := json.Unmarshal(cuerpo, &c); err != nil {
		return nil, ErrTokenRoto
	}

	// UN TOKEN CON `ambito` NO ENTRA POR AQUÍ, NUNCA — bandeja de revisión, paquete V
	// (`docs/bandeja-de-revision.md`, B.1). Accesos firma, con el MISMO secreto, un token
	// restringido «solo-entrega-a-revisión» (`ambito:"reparto.entrega"`, `entradas:[]`, sin
	// roles) para que quien perdió `delivery.entrar` pueda dejar su cola en cuarentena. Solo
	// abre las dos rutas de entrega de `sync`; en cada ruta normal de esta API es una credencial
	// que no vale, y es la misma regla que `sync/internal/identidad` (las ata
	// `docs/ambito-de-entrega.casos.json`).
	//
	// Se rechaza por PRESENCIA —cualquier valor: `""`, `null`, `[]`— y aquí, en `Verificar`, no en
	// `PuedeEntrarAReparto`: por `Verificar` pasan `Exigir`, el canal en vivo y `/api/me` (que no
	// da 403 y contesta quién es). Y vale aunque el token traiga `delivery.entrar` en `entradas`:
	// la llave NO lo rescata, que es justo el agujero que esto cierra (un token de entrega al que
	// alguien consiguiera meterle la llave aplicaría gestos «con autoridad» sin pasar por revisión).
	// El 401 es el de siempre y su motivo queda en el registro.
	if len(c.Ambito) > 0 {
		return nil, ErrAmbito
	}

	ahora := time.Now()
	// Sin `exp` no hay sesión que muera nunca. Se exige.
	if c.Exp == nil {
		return nil, fmt.Errorf("%w: el token no trae exp", ErrCaducado)
	}
	if ahora.After(time.Unix(int64(*c.Exp), 0).Add(v.margen)) {
		return nil, ErrCaducado
	}
	if c.Nbf != nil && ahora.Add(v.margen).Before(time.Unix(int64(*c.Nbf), 0)) {
		return nil, fmt.Errorf("%w: todavía no vale", ErrCaducado)
	}

	// `sub` es lo que manda auth en el token nuevo (el de la APK); `id` es lo que
	// llevaba el de la web. Se aceptan los dos porque las dos puertas están abiertas a
	// la vez y el mismo servicio atiende a las dos.
	u := &Usuario{
		ID:       primero(c.Sub, c.ID),
		Email:    c.Email,
		Nombre:   primero(c.Name, c.Nombre),
		Rol:      primero(c.Role, c.Rol),
		Roles:    c.Roles,
		Sucursal: strings.TrimSpace(primero(c.BranchID, c.BranchIDSnake, c.Sucursal)),
	}
	if u.ID == "" {
		return nil, ErrSinPersona
	}
	if u.Rol == "" && len(u.Roles) > 0 {
		u.Rol = u.Roles[0]
	}
	u.Entradas, u.HayEntradas = LeerEntradas(c.Entradas)
	u.FirmadoPorLaWeb = c.Web
	if c.IatMs != nil {
		u.IatMs = int64(*c.IatMs)
	}
	if c.Iat != nil {
		u.Iat = int64(*c.Iat)
	}
	return u, nil
}

// reclamos: los campos que se leen del token. Van con punteros los numéricos para poder
// distinguir "no vino" de "vino cero".
//
// `branchId` llega a veces como null: por eso es *string y no string, y por eso hay tres
// nombres — `branchId` (web), `branch_id` y `sucursal` (token nuevo). Escribir sólo uno
// y que el otro llegue vacío es exactamente el fallo de «se ven cero pedidos con un 200».
type reclamos struct {
	Sub           string   `json:"sub"`
	ID            string   `json:"id"`
	Email         string   `json:"email"`
	Name          string   `json:"name"`
	Nombre        string   `json:"nombre"`
	Role          string   `json:"role"`
	Rol           string   `json:"rol"`
	Roles         []string `json:"roles"`
	BranchID      string   `json:"branchId"`
	BranchIDSnake string   `json:"branch_id"`
	Sucursal      string   `json:"sucursal"`
	Exp           *float64 `json:"exp"`
	Nbf           *float64 `json:"nbf"`
	// `iat` NO se usa para decidir nada —un token sin él vale igual— y está aquí sólo para
	// poder contar `exp - iat` en el registro de un rechazo: es lo que separa la sesión de
	// la web (7 días) de la de la APK (15 minutos) sin tener que creerse el token. Ver
	// `rastro.go`.
	Iat *float64 `json:"iat"`
	// `iatms`: lo mismo en MILISEGUNDOS. Lo firman la web (`auth_web.go`) y Accesos (token de la APK).
	// Con él se compara la marca de invalidación de Accesos (`internal/sesiones`), que va en ms.
	IatMs *float64 `json:"iatms"`
	// `web`: SÓLO lo pone la cookie que firma `auth_web.go`. Es lo que dice «esto es una sesión web».
	Web bool `json:"web"`
	// `entradas`: en crudo para poder distinguir «no vino» (len 0) de `[]` y de `null`. Ver
	// [LeerEntradas].
	Entradas json.RawMessage `json:"entradas"`
	// `ambito`: también en crudo; solo importa si VIENE (len > 0), sea cual sea su valor. Ver
	// [Verificador.Verificar].
	Ambito json.RawMessage `json:"ambito"`
}

// UnmarshalJSON tolera que los campos de texto vengan como null o como número. El
// contrato de delivery dice "si alguno no es string, no hay usuario", pero eso sólo
// aplica a los obligatorios: un `branchId: null` es lo normal en el Super Admin, y
// reventar ahí lo dejaría fuera de su propio sistema.
func (c *reclamos) UnmarshalJSON(b []byte) error {
	type alias reclamos
	var a alias
	dec := json.NewDecoder(strings.NewReader(string(b)))
	if err := dec.Decode(&a); err != nil {
		// Un tipo inesperado en un campo suelto no puede tumbar el token entero: se
		// reintenta campo a campo y lo que no sea texto se deja vacío.
		var suelto map[string]any
		if err2 := json.Unmarshal(b, &suelto); err2 != nil {
			return err
		}
		a = alias{
			Sub:           texto(suelto, "sub"),
			ID:            texto(suelto, "id"),
			Email:         texto(suelto, "email"),
			Name:          texto(suelto, "name"),
			Nombre:        texto(suelto, "nombre"),
			Role:          texto(suelto, "role"),
			Rol:           texto(suelto, "rol"),
			Roles:         textos(suelto, "roles"),
			BranchID:      texto(suelto, "branchId"),
			BranchIDSnake: texto(suelto, "branch_id"),
			Sucursal:      texto(suelto, "sucursal"),
			Exp:           numero(suelto, "exp"),
			Nbf:           numero(suelto, "nbf"),
			Iat:           numero(suelto, "iat"),
			IatMs:         numero(suelto, "iatms"),
			Web:           suelto["web"] == true,
		}
	}
	// `entradas` se lee APARTE y en crudo, salga por el camino que salga lo demás: un campo suelto
	// con otro tipo no puede tumbar el token, y «presente» no puede perderse por el camino.
	var solo struct {
		Entradas json.RawMessage `json:"entradas"`
		Ambito   json.RawMessage `json:"ambito"`
	}
	_ = json.Unmarshal(b, &solo)
	a.Entradas = solo.Entradas
	a.Ambito = solo.Ambito
	*c = reclamos(a)
	return nil
}

var algoritmos = map[string]func() hash.Hash{
	"HS256": sha256.New,
	"HS384": sha512.New384,
	"HS512": sha512.New,
}

// Los JWT van en base64url SIN relleno; hay emisores que lo ponen igual. Se aceptan los
// dos: rechazar el token por un `=` de más es un 401 que nadie sabe explicar.
func decodificar(s string) ([]byte, error) {
	if b, err := base64.RawURLEncoding.DecodeString(s); err == nil {
		return b, nil
	}
	return base64.URLEncoding.DecodeString(s)
}

func primero(valores ...string) string {
	for _, v := range valores {
		if v != "" {
			return v
		}
	}
	return ""
}

func texto(m map[string]any, clave string) string {
	if v, ok := m[clave].(string); ok {
		return v
	}
	return ""
}

func textos(m map[string]any, clave string) []string {
	bruto, ok := m[clave].([]any)
	if !ok {
		return nil
	}
	var salida []string
	for _, v := range bruto {
		if s, ok := v.(string); ok {
			salida = append(salida, s)
		}
	}
	return salida
}

func numero(m map[string]any, clave string) *float64 {
	if v, ok := m[clave].(float64); ok {
		return &v
	}
	return nil
}

// EsDesarrollador: EL ÚNICO ROL POR ENCIMA DE TODO, y el listón más alto que hay aquí.
//
// No es lo mismo que [EsSuperAdmin], y por eso no se delega en él: un SUPER ADMIN
// administra todo Procovar, pero hay cosas que no son de administrar la empresa sino de
// mirar cómo están pegadas las tuberías entre dos sistemas — con motivos de error de
// PEDIDO dentro, colas, reintentos y códigos HTTP.
//
// Jose, 26/09/2026, sobre la pantalla del webhook: «que sólo lo pueda ver yo, eso no lo
// puede ver más nadie, sólo yo, el desarrollador».
//
// Aquí NO entra `rolAdminHeredado`: el `admin` de la web vieja es un puente para que su
// gente no se quede fuera de su propio sistema, no una llave maestra.
func (u *Usuario) EsDesarrollador() bool {
	return u.tieneAlguno(rolDesarrollador)
}

// PuedeMirarElCanal: quién entra en la pantalla de las tuberías con PEDIDO.
//
// EL DESARROLLADOR Y EL SUPER ADMIN, y sólo ellos. Jose, 26/09/2026: «ponle para super
// admin también, de todas formas yo limpiaré eso después». Lo anterior era sólo
// `DESARROLLADOR` —sus palabras del mismo día: «que sólo lo pueda ver yo»— y lo abrió él
// mismo al ver que su propia cuenta, que es `SUPER ADMIN` por defecto, se quedaba fuera.
//
// ESTÁ APARTE DE [Usuario.EsSuperAdmin] A PROPÓSITO, aunque hoy dé casi lo mismo: aquel
// deja pasar además al `admin` heredado de la web vieja, que es un puente para que su gente
// no se quede fuera de su propio sistema, y esto no es su sistema. Y separado es como se
// vuelve a cerrar el día que Jose lo limpie: se quita `rolSuperAdmin` de esta línea y no se
// toca nada más.
func (u *Usuario) PuedeMirarElCanal() bool {
	return u.tieneAlguno(rolDesarrollador, rolSuperAdmin)
}
