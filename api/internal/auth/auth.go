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
)

var (
	ErrSinToken   = errors.New("no viene token")
	ErrTokenRoto  = errors.New("el token no tiene la forma de un JWT")
	ErrFirma      = errors.New("la firma no cuadra")
	ErrCaducado   = errors.New("el token está caducado")
	ErrSinPersona = errors.New("el token no dice de quién es")
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
	// `admin` a secas es lo que traían los tokens VIEJOS de la web de delivery. Se acepta
	// mientras esa puerta siga abierta; el día que se cierre, se quita de aquí.
	rolAdminHeredado = "admin"
)

func (u *Usuario) tieneAlguno(roles ...string) bool {
	for _, candidato := range append([]string{u.Rol}, u.Roles...) {
		c := strings.TrimSpace(candidato)
		for _, r := range roles {
			if strings.EqualFold(c, r) {
				return true
			}
		}
	}
	return false
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

// Verificador guarda el secreto. Se construye una vez al arrancar.
type Verificador struct {
	secreto []byte
	// margen para el desfase de reloj entre este servidor y el de auth. Sin él, dos
	// máquinas con medio minuto de diferencia rechazan tokens recién emitidos.
	margen time.Duration
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
	candidatas, _, _ := Credenciales(r)
	if len(candidatas) == 0 {
		return nil, ErrSinToken
	}
	var primerFallo error
	for _, crudo := range candidatas {
		u, err := v.Verificar(crudo)
		if err == nil {
			return u, nil
		}
		if primerFallo == nil {
			primerFallo = err
		}
	}
	return nil, primerFallo
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
		}
	}
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
