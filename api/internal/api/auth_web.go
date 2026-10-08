// LA PUERTA DE LA WEB: se entra por Accesos y se vuelve con una cookie.
//
// Son DOS puertas distintas al mismo sitio y eso no es un descuido, es
// `docs/identidad.md`:
//
//	Web (Flutter) | Login único de auth: redirección y vuelta con sesión | Cookie
//	APK (Flutter) | Usuario y contraseña contra el endpoint de token      | El par
//
// La APK manda usuario y contraseña porque se va al patio de un almacén y tiene
// que poder guardar el par para el día entero sin señal. La web no se va a
// ningún sitio: quien ya entró en Accesos aterriza dentro **sin escribir nada**,
// y lo que sostiene su sesión es una cookie `httpOnly` que su propio JavaScript
// no puede leer. Esa es la diferencia entera, y romperla rompe el trabajo sin
// señal de un lado o el login único del otro.
//
// # Lo que pasa, en orden
//
//  1. La web se abre y pregunta GET /api/me.
//  2. Sin sesión, manda el navegador a GET /api/auth/entrar.
//  3. Aquí se le pide a Accesos a dónde mandar a esa persona y se la manda.
//  4. Accesos la identifica y la devuelve a GET /api/auth/callback?code=…
//  5. El código se canjea por quién es, se firma NUESTRO token y se deja en la
//     cookie `token` —la misma que ya lee `auth.Verificador.DelaPeticion`—.
//  6. Se la devuelve a donde iba, y ahora /api/me sí contesta.
//
// Salir son otras dos: /api/auth/logout manda a Accesos, que es donde vive la
// sesión y donde está el cartel de «¿seguro?», y /api/auth/logout/done borra la
// cookie de aquí **al volver**. El orden importa y está copiado del patrón
// (`delivery`, Next 15, en producción): borrando la cookie ANTES de ir, decir
// que no en el cartel dejaba a la persona a medias —dentro de Accesos y fuera
// de aquí, por haber dicho que no quería salir—.
//
// # Nada de esto toca la base
//
// Este servicio NO tiene tabla de personas y no se le añade una (ver `yo.go`).
// El patrón de Next sí hace un `upsert` en la suya, pero allí las filas de
// pedidos y rutas apuntan a esa cuenta local; aquí todo va por el `sub` que
// firma Accesos, así que una tabla de personas sería un segundo sitio donde dar
// de baja a alguien — que es exactamente lo que el login único viene a quitar.
package api

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
)

// nombreDeLaCookie: `token`, que es la que ya lee `auth.Verificador` y la que
// `/api/me` devuelve. Cambiarla aquí deja la sesión escrita en un sitio donde
// nadie la busca: se entraría bien y la siguiente petición sería 401.
const nombreDeLaCookie = "token"

// rutaDeLaPuerta es la pantalla de acceso de la web (Flutter, `portero.dart`).
// Es a donde se vuelve cuando el login único falla, **con el motivo en la
// dirección**: una pantalla en blanco no le dice a nadie qué hacer.
const rutaDeLaPuerta = "/acceso"

// duracionDeLaSesionWeb: lo que dura la cookie y lo que dura el token que lleva
// dentro. Los dos el mismo número a propósito — una cookie que sobrevive a su
// token es una sesión que parece viva y contesta 401.
//
// SIETE DÍAS, Y NO LOS QUINCE MINUTOS DEL TOKEN DE LA APK. No es una relajación
// por descuido: son dos cosas distintas.
//
//   - El de la APK dura quince minutos porque **se renueva solo** con el
//     refresh, sin que nadie se entere, y acotar la ventana de un token robado
//     no le cuesta nada a nadie.
//   - En la web no hay refresh: lo que renueva es volver a pasar por Accesos, y
//     eso es una recarga entera de la página. Con quince minutos, al logístico
//     se le vaciaría la pantalla a media mañana mientras arma una ruta.
//
// A cambio la cookie es `httpOnly` —el JavaScript de la página no la puede leer,
// así que un script colado no se la lleva— y `Secure`. Es el mismo número que
// lleva el patrón en producción (`delivery/src/lib/auth.ts`, `expiresIn: '7d'`).
const duracionDeLaSesionWeb = 7 * 24 * time.Hour

// Los motivos que se le cuentan a la puerta, tal cual los escribe el patrón.
// Son pocos y son los de verdad: cada uno lleva a hacer una cosa distinta.
const (
	motivoNoDisponible = "nodisponible" // falta la llave: no se puede ni empezar
	motivoSinCodigo    = "sincodigo"    // Accesos devolvió sin `code`
	motivoError        = "error"        // Accesos contestó mal, o no contestó
)

// ---------------------------------------------------------------------------
// Las cuatro rutas
// ---------------------------------------------------------------------------

// rutasAuthWeb monta la puerta de la web.
//
// NINGUNA lleva `sesion` ni `alcance`, y es lo correcto: son justamente las
// cuatro a las que se llega SIN sesión. Exigir token en `/api/auth/entrar`
// sería pedirle la sesión a quien viene a conseguirla.
func (s *Servidor) rutasAuthWeb(rt *httpx.Router, sesion, admin []httpx.Medio) {
	_, _ = sesion, admin
	rt.ManejarFunc(http.MethodGet, "/api/auth/entrar", s.entrarPorAccesos)
	rt.ManejarFunc(http.MethodGet, "/api/auth/callback", s.vueltaDeAccesos)
	rt.ManejarFunc(http.MethodGet, "/api/auth/logout", s.salirPorAccesos)
	rt.ManejarFunc(http.MethodGet, "/api/auth/logout/done", s.vueltaDeSalir)
}

// GET /api/auth/entrar — empieza el login único.
//
// La dirección de vuelta se calcula DESDE LA PETICIÓN y no de una constante:
// así funciona igual en local, en pruebas y en producción sin configurar nada,
// y no hay forma de que apunte a un sitio que ya no existe.
func (s *Servidor) entrarPorAccesos(w http.ResponseWriter, r *http.Request) {
	origen := origenPublico(r)

	if !s.hayLoginUnico() {
		// Sin llave no se puede ni empezar. Se vuelve a la puerta DICIÉNDOLO, no
		// a una pantalla de error: quien lo tiene que arreglar necesita saber
		// que es una variable que falta, no un servidor caído.
		httpx.Registro(r).Error("login único sin configurar: falta PROCOVAR_AUTH_SIGNING_KEY")
		aLaPuerta(w, r, origen, motivoNoDisponible)
		return
	}

	// Comprobado: `volverA` lo escribe quien quiera en la dirección.
	volverA := destinoSeguro(r.URL.Query().Get("volverA"), origen)

	destino, err := s.sso().Redireccion(r.Context(), origen+"/api/auth/callback", volverA)
	if err != nil {
		// El motivo va al registro, no a la pantalla: a quien entra no le sirve
		// de nada y a quien lo arregla le hace falta entero. Sin esta línea, un
		// fallo aquí es un `sso=error` mudo.
		httpx.Registro(r).Error("no se pudo pedir la redirección al login único", "motivo", err)
		aLaPuerta(w, r, origen, motivoError)
		return
	}
	http.Redirect(w, r, destino, http.StatusFound)
}

// GET /api/auth/callback — la vuelta de Accesos.
//
// Accesos ya comprobó quién es; aquí sólo se traduce a NUESTRO token y se deja
// en la cookie. Las treinta y tantas rutas que ya comprueban la sesión no se
// enteran de que la puerta cambió, que es exactamente lo que se busca: cambiar
// la entrada sin tocar ninguna de las cerraduras de dentro.
func (s *Servidor) vueltaDeAccesos(w http.ResponseWriter, r *http.Request) {
	origen := origenPublico(r)

	codigo := r.URL.Query().Get("code")
	if codigo == "" {
		httpx.Registro(r).Warn("la vuelta del login único llegó sin código")
		aLaPuerta(w, r, origen, motivoSinCodigo)
		return
	}

	persona, err := s.sso().Canjear(r.Context(), codigo)
	if err != nil {
		// UN CÓDIGO QUE NO VALE DICE EL MOTIVO. En el registro va entero —es lo
		// que hace falta para arreglarlo— y en la pantalla va `sso=error`, que
		// es lo que la puerta sabe explicar. Lo que no puede pasar es que el
		// navegador se quede en una página en blanco.
		httpx.Registro(r).Error("falló el canje del código del login único", "motivo", err)
		aLaPuerta(w, r, origen, motivoError)
		return
	}

	token, err := s.firmarTokenDeLaWeb(persona, time.Now())
	if err != nil {
		httpx.Registro(r).Error("no se pudo firmar el token de la web", "motivo", err)
		aLaPuerta(w, r, origen, motivoError)
		return
	}

	// Se vuelve a comprobar AQUÍ, no sólo al salir: `returnTo` ha ido y vuelto
	// por Accesos, y lo que se comprueba tiene que ser lo que se usa.
	destino := destinoSeguro(persona.VolverA, origen)

	http.SetCookie(w, cookieDeLaWeb(origen, token, duracionDeLaSesionWeb))
	http.Redirect(w, r, destino, http.StatusFound)
}

// GET /api/auth/logout — cerrar sesión DE VERDAD.
//
// El botón de la aplicación no puede cerrar nada por su cuenta: la sesión vive
// en una cookie `httpOnly` que el JavaScript no puede ni leer ni borrar (y ha de
// ser así). Quien le daba a «cerrar sesión» volvía a entrar sin más y creía que
// había salido — y eso importa justamente en el ordenador compartido, que es
// donde se le da al botón.
//
// Se cierra en los DOS lados y en este orden: primero Accesos, que es donde vive
// la sesión, y la cookie de aquí se borra al VOLVER (`/api/auth/logout/done`).
func (s *Servidor) salirPorAccesos(w http.ResponseWriter, r *http.Request) {
	origen := origenPublico(r)
	base := s.urlDeAccesos()
	if base == "" {
		// Sin Accesos configurado no hay a quién mandar a nadie, pero SALIR
		// TIENE QUE SALIR: se va directo a borrar la cookie. Dejar la sesión
		// abierta porque falta una variable es lo contrario de lo que pidió
		// quien pulsó el botón.
		httpx.Registro(r).Error("PROCOVAR_AUTH_URL sin configurar: se cierra sólo la sesión de aquí")
		http.Redirect(w, r, origen+"/api/auth/logout/done", http.StatusFound)
		return
	}

	q := url.Values{
		"returnTo":  {origen + "/api/auth/logout/done"},
		"cancelUrl": {origen + "/"},
	}
	http.Redirect(w, r, base+"/logout?"+q.Encode(), http.StatusFound)
}

// GET /api/auth/logout/done — la vuelta de Accesos, ya cerrada la sesión de
// allí. Aquí sólo queda borrar la cookie y dejar a la persona en la puerta.
func (s *Servidor) vueltaDeSalir(w http.ResponseWriter, r *http.Request) {
	origen := origenPublico(r)
	// Duración cero la borra. LOS DEMÁS VALORES TIENEN QUE SER LOS MISMOS que
	// cuando se puso —nombre, camino, `Secure`, `SameSite`—: con uno distinto el
	// navegador la trata como otra cookie y deja la buena donde estaba, o sea
	// que «cerrar sesión» no cierra nada y nadie se entera.
	http.SetCookie(w, cookieDeLaWeb(origen, "", 0))
	http.Redirect(w, r, origen+"/", http.StatusFound)
}

// ---------------------------------------------------------------------------
// La cookie
// ---------------------------------------------------------------------------

// cookieDeLaWeb arma la cookie de la sesión. `dura <= 0` la borra.
//
//   - `HttpOnly`: el JavaScript de la página no la puede leer. Un token que el
//     navegador puede leer se lo lleva cualquier script de la página, y es la
//     razón por la que `/api/me` devuelve el token en el cuerpo en vez de
//     dejarlo a mano en un sitio legible.
//   - `Secure` cuando se sirve por HTTPS, y sólo entonces: puesto siempre, en el
//     `localhost` de desarrollo el navegador la descarta y no se entra nunca.
//   - `SameSite=Lax` y no `Strict`: la vuelta de Accesos es una navegación de
//     primer nivel desde OTRO sitio (`auth.procovar.cloud`), y con `Strict` el
//     navegador no manda la cookie en esa cadena — se entraría y se volvería a
//     la puerta en bucle. `None` no hace falta: la aplicación y la API salen
//     bajo el mismo dominio, así que sus peticiones son del mismo sitio.
func cookieDeLaWeb(origen, valor string, dura time.Duration) *http.Cookie {
	c := &http.Cookie{
		Name:     nombreDeLaCookie,
		Value:    valor,
		Path:     "/",
		HttpOnly: true,
		Secure:   strings.HasPrefix(origen, "https://"),
		SameSite: http.SameSiteLaxMode,
	}
	if dura <= 0 {
		// MaxAge negativo es lo que Go escribe como `Max-Age=0`, que es el
		// borrado. Cero a secas significaría «sin Max-Age», o sea una cookie de
		// sesión que se queda.
		c.MaxAge = -1
		c.Expires = time.Unix(0, 0)
		return c
	}
	c.MaxAge = int(dura.Seconds())
	c.Expires = time.Now().Add(dura)
	return c
}

// ---------------------------------------------------------------------------
// Dónde estamos y a dónde se puede mandar a alguien
// ---------------------------------------------------------------------------

// origenPublico es la dirección de ESTE servicio vista desde fuera.
//
// `r.Host` a secas NO vale detrás del proxy: dentro del contenedor la petición
// llega a `0.0.0.0:8080`, así que la vuelta del login se construiría como
// `http://0.0.0.0:8080/…` y no llevaría a ninguna parte.
//
// Manda `PROCOVAR_PUBLIC_URL`. Es lo preferible porque las cabeceras
// `x-forwarded-*` las escribe el proxy, y si algún día el contenedor quedara
// alcanzable por otro camino, alguien podría mandarlas a mano y conseguir que
// construyéramos direcciones apuntando a su servidor. Queda un cortafuegos más:
// Accesos sólo acepta direcciones de vuelta de su lista blanca.
//
// SE LEE DEL ENTORNO AQUÍ Y NO DE `config`, y es una deuda anotada, no una
// opinión: `internal/config` lo está escribiendo otro agente ahora mismo y
// añadirle un campo en este cambio sería pisarlo. En cuanto se libere, esto pasa
// a `cfg.PublicURL`.
func origenPublico(r *http.Request) string {
	if declarado := strings.TrimSpace(os.Getenv("PROCOVAR_PUBLIC_URL")); declarado != "" {
		return strings.TrimRight(declarado, "/")
	}

	host := primerValor(r.Header.Get("X-Forwarded-Host"))
	if host == "" {
		host = r.Host
	}
	protocolo := primerValor(r.Header.Get("X-Forwarded-Proto"))
	if protocolo == "" {
		protocolo = "http"
		if r.TLS != nil {
			protocolo = "https"
		}
	}
	return protocolo + "://" + host
}

// primerValor se queda con el primero de una cabecera que pueda venir en lista
// (`X-Forwarded-Host: a.example, b.example`). Con la lista entera se armaría una
// dirección que no es de nadie.
func primerValor(cabecera string) string {
	if i := strings.IndexByte(cabecera, ','); i >= 0 {
		cabecera = cabecera[:i]
	}
	return strings.TrimSpace(cabecera)
}

// destinoSeguro dice a dónde se puede mandar a alguien después de entrar: SÓLO a
// esta misma aplicación.
//
// `volverA` viaja en la dirección y lo puede escribir cualquiera. Sin esta
// comprobación, un enlace `…/api/auth/entrar?volverA=https://sitio-falso/` haría
// que, tras identificarse DE VERDAD en Procovar, la persona acabara en una copia
// del sistema pidiéndole la contraseña — y habiendo pasado por nuestro dominio,
// que es justo lo que da confianza.
//
// Cualquier otra cosa cae a la raíz, en silencio: quien lo intenta no merece una
// explicación y quien llega por error tampoco la necesita.
func destinoSeguro(candidato, origen string) string {
	candidato = strings.TrimSpace(candidato)
	if candidato == "" {
		return origen + "/"
	}
	// Una ruta relativa es segura por definición, pero `//otro-sitio.com`
	// también empieza por barra y el navegador la lee como otro dominio. Y
	// `/\otro` la lee igual: hay navegadores que tratan la contrabarra como
	// barra al normalizar.
	if strings.HasPrefix(candidato, "/") &&
		!strings.HasPrefix(candidato, "//") &&
		!strings.HasPrefix(candidato, "/\\") {
		return origen + candidato
	}
	if u, err := url.Parse(candidato); err == nil && u.Scheme != "" && u.Host != "" {
		if strings.EqualFold(u.Scheme+"://"+u.Host, origen) {
			return candidato
		}
	}
	return origen + "/"
}

// aLaPuerta devuelve a la pantalla de acceso DICIENDO por qué. El motivo va en
// la dirección porque es lo único que sobrevive a una redirección del navegador
// y lo único que la puerta puede leer sin sesión.
func aLaPuerta(w http.ResponseWriter, r *http.Request, origen, motivo string) {
	http.Redirect(w, r, origen+rutaDeLaPuerta+"?sso="+url.QueryEscape(motivo), http.StatusFound)
}

// ---------------------------------------------------------------------------
// El token que se deja en la cookie
// ---------------------------------------------------------------------------

// firmarTokenDeLaWeb emite NUESTRO token con lo que dijo Accesos.
//
// Va firmado con el mismo `JWT_SECRET` con el que firma Accesos, que es el que
// `auth.Verificador` comprueba: de otro modo la cookie que acabamos de escribir
// sería un 401 en la petición siguiente.
//
// Los reclamos se escriben con los DOS nombres que el verificador acepta
// (`sub`/`id`, `branchId`/`sucursal`, `role`/`roles`) a propósito: el token de la
// web y el de la APK vienen de sitios distintos y el mismo servicio atiende a
// los dos.
func (s *Servidor) firmarTokenDeLaWeb(p *personaDeAccesos, ahora time.Time) (string, error) {
	if s.cfg == nil || len(s.cfg.JWTSecret) == 0 {
		return "", errors.New("JWT_SECRET no está configurada: no se puede emitir la sesión de la web")
	}
	if p == nil || p.ID == "" {
		return "", errors.New("Accesos no devolvió la persona")
	}

	reclamos := map[string]any{
		"sub":   p.ID,
		"id":    p.ID,
		"email": p.Email,
		"name":  p.Nombre,
		// El rol PRINCIPAL y la lista entera. `EsAdmin` mira los dos.
		"role":  p.RolPrincipal(),
		"roles": p.RolesDeVerdad(),
		// El CÓDIGO de la sucursal (CAM, HOL…), que es lo que lee el alcance.
		// Vacío significa «ninguna», y eso NO es un permiso: quién ve las ocho
		// lo decide el rol (`auth.EsSuperAdmin`), nunca un hueco.
		"branchId": p.CodigoSucursal,
		"sucursal": p.CodigoSucursal,
		"iat":      ahora.Unix(),
		"exp":      ahora.Add(duracionDeLaSesionWeb).Unix(),
	}

	// `entradas` va en la cookie SÓLO si Auth la mandó: ausente se queda ausente (y la API cae a
	// los roles), y `[]` se queda `[]` (y no entra). Un slice nil saldría `null`, por eso el
	// vacío se escribe a mano.
	if p.HayEntradas {
		entradas := p.Entradas
		if entradas == nil {
			entradas = []string{}
		}
		reclamos["entradas"] = entradas
	}

	cabecera, err := json.Marshal(map[string]string{"alg": "HS256", "typ": "JWT"})
	if err != nil {
		return "", err
	}
	cuerpo, err := json.Marshal(reclamos)
	if err != nil {
		return "", err
	}
	sinFirmar := base64.RawURLEncoding.EncodeToString(cabecera) + "." +
		base64.RawURLEncoding.EncodeToString(cuerpo)

	mac := hmac.New(sha256.New, s.cfg.JWTSecret)
	mac.Write([]byte(sinFirmar))
	return sinFirmar + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil)), nil
}

// ---------------------------------------------------------------------------
// El cliente del login único
// ---------------------------------------------------------------------------

// personaDeAccesos es quién dijo Accesos que es, ya traducido a lo nuestro.
type personaDeAccesos struct {
	ID     string
	Email  string
	Nombre string
	// Roles TAL CUAL los escribe Procovar: `SUPERVISOR`, `SUPER ADMIN`… No se
	// traducen a `admin`/`operator` como hace el patrón de Next, porque esta API
	// compara contra los siete de verdad (`internal/auth/auth.go`).
	Roles []string
	// CodigoSucursal es el `slug` de la organización en mayúsculas (CAM, HOL…),
	// o vacío. Es lo único que ata a esta persona con una sucursal de aquí: los
	// identificadores internos de cada aplicación no se parecen en nada.
	CodigoSucursal string
	// EsSuperAdmin es el `isSystemAdmin` de Accesos.
	EsSuperAdmin bool
	// Entradas son las llaves `<app>.entrar` que Auth firma en el intercambio (`delivery.entrar`…)
	// y deciden si la persona entra a Reparto. HayEntradas distingue «el intercambio no traía el
	// campo» (un Accesos anterior al cambio: la cookie sale SIN `entradas` y se decide por roles)
	// de «traía `[]`» (la cookie sale con `entradas: []` y no entra).
	Entradas    []string
	HayEntradas bool
	// VolverA es la dirección que se le dio a Accesos al empezar y que devuelve
	// al terminar. **Se vuelve a comprobar**: fue y vino por fuera.
	VolverA string
}

// RolesDeVerdad son los roles que van al token.
//
// Si Accesos dice que es administrador del sistema se añade `SUPER ADMIN`
// aunque no venga en la lista: es exactamente lo que hace el patrón
// (`rolDeDelivery`: `if (persona.esSuperAdmin) return 'admin'`), y sin ello el
// administrador global entraría sin ver las ocho sucursales — 200 en todo y la
// aplicación medio vacía, que desde dentro parece que no hay datos.
//
// No se cae hacia arriba en ningún otro caso: un rol que no conozcamos se copia
// tal cual y quien decide qué puede hacer es `internal/auth`.
func (p *personaDeAccesos) RolesDeVerdad() []string {
	roles := make([]string, 0, len(p.Roles)+1)
	roles = append(roles, p.Roles...)
	if p.EsSuperAdmin {
		for _, r := range roles {
			if auth.MismoRol(r, "SUPER ADMIN") {
				return roles
			}
		}
		roles = append(roles, "SUPER ADMIN")
	}
	return roles
}

// RolPrincipal es el que va en `role`. El de más mando primero: si no, una
// persona que es `SUPER ADMIN` y además `GESTOR` podría entrar como gestor sólo
// por el orden en que Accesos devolvió su lista.
func (p *personaDeAccesos) RolPrincipal() string {
	roles := p.RolesDeVerdad()
	// LOGISTICO va el último de los que mandan: quien es [GESTOR, LOGISTICO] entra a Reparto
	// como LOGISTICO, y que `role` (y `/api/me`) diga GESTOR sería decirle a la app que no.
	for _, mandan := range []string{"DESARROLLADOR", "SUPER ADMIN", "ADMINISTRADOR", "LOGISTICO"} {
		for _, r := range roles {
			if auth.MismoRol(r, mandan) {
				return mandan
			}
		}
	}
	if len(roles) > 0 {
		return strings.TrimSpace(roles[0])
	}
	return ""
}

// clienteSSO es por dónde se habla con el login único. Interfaz para que las
// pruebas puedan poner un doble sin salir a la red.
type clienteSSO interface {
	// Redireccion pide a dónde mandar a la persona para que se identifique.
	Redireccion(ctx context.Context, callbackURL, volverA string) (string, error)
	// Canjear cambia el código que trae de vuelta por quién es esa persona.
	Canjear(ctx context.Context, codigo string) (*personaDeAccesos, error)
}

// sso devuelve el cliente del login único.
//
// Se construye por petición y no se guarda en el servidor porque no tiene estado
// que recordar: ninguna de las dos llamadas se puede cachear. La firma se
// reutiliza de `accesosHTTP` (`almacenes.go`) —la misma llave y el mismo
// esquema—, porque abrir una segunda forma de firmar serían dos sitios donde
// equivocarse.
//
// **Las pruebas no necesitan un doble**: apuntan `cfg.AuthURL` a un `httptest`
// y lo que se ejercita es el cliente de verdad, con su firma puesta. Un doble
// aquí probaría el manejador contra una idea de Accesos, no contra Accesos.
func (s *Servidor) sso() clienteSSO { return &ssoDeAccesos{cfg: s.cfg} }

// hayLoginUnico: sin llave no se puede ni empezar, y se dice ANTES de salir a la
// red — un «401 de auth» es mucho más difícil de relacionar con una variable que
// falta.
func (s *Servidor) hayLoginUnico() bool {
	return s.cfg != nil && strings.TrimSpace(s.cfg.AuthSigningKey) != ""
}

func (s *Servidor) urlDeAccesos() string {
	if s.cfg == nil {
		return ""
	}
	return strings.TrimRight(strings.TrimSpace(s.cfg.AuthURL), "/")
}

// Las dos rutas del login único en Accesos. Escritas aquí y no repartidas porque
// son parte de la firma: se firma el MÉTODO y LA RUTA, así que una errata aquí
// no da un 404, da un 401 de firma que no cuadra.
const (
	rutaPedirRedireccion = "/api/auth/callback-token"
	rutaCanjearCodigo    = "/api/auth/exchange"
)

type ssoDeAccesos struct{ cfg *config.Config }

func (c *ssoDeAccesos) Redireccion(ctx context.Context, callbackURL, volverA string) (string, error) {
	cuerpo, err := json.Marshal(map[string]string{
		"clientId":    c.clienteID(),
		"callbackUrl": callbackURL,
		"returnTo":    volverA,
	})
	if err != nil {
		return "", err
	}
	crudo, err := c.firmado(ctx, http.MethodPost, rutaPedirRedireccion, cuerpo, 10*time.Second)
	if err != nil {
		return "", err
	}
	var r struct {
		RedirectURL string `json:"redirectUrl"`
	}
	if err := json.Unmarshal(crudo, &r); err != nil {
		return "", fmt.Errorf("Accesos contestó algo que no se entiende: %w", err)
	}
	if r.RedirectURL == "" {
		return "", errors.New("Accesos no dijo a dónde mandar a la persona")
	}
	// LA DIRECCIÓN TIENE QUE SER DE ACCESOS. Sin esto, esta ruta es un redirector
	// abierto con nuestro dominio delante: basta que la respuesta de Accesos se
	// tuerza —o que `AUTH_URL` apunte donde no debe— para mandar a alguien a una
	// copia del login con nuestra dirección en la barra.
	if !mismoSitio(r.RedirectURL, c.base()) {
		return "", fmt.Errorf("Accesos mandó a un sitio que no es suyo: %s", recorte(r.RedirectURL, 120))
	}
	return r.RedirectURL, nil
}

func (c *ssoDeAccesos) Canjear(ctx context.Context, codigo string) (*personaDeAccesos, error) {
	cuerpo, err := json.Marshal(map[string]string{"code": codigo})
	if err != nil {
		return nil, err
	}
	crudo, err := c.firmado(ctx, http.MethodPost, rutaCanjearCodigo, cuerpo, 15*time.Second)
	if err != nil {
		return nil, err
	}

	var r struct {
		User *struct {
			ID            string `json:"id"`
			Email         string `json:"email"`
			Name          string `json:"name"`
			IsSystemAdmin bool   `json:"isSystemAdmin"`
		} `json:"user"`
		Memberships []struct {
			Organization *struct {
				Slug string `json:"slug"`
				Name string `json:"name"`
			} `json:"organization"`
			Roles []string `json:"roles"`
		} `json:"memberships"`
		ReturnTo string `json:"returnTo"`
		// LOS ROLES DE LA PERSONA, de primer nivel (Accesos, 08/10/2026): el rol por defecto y
		// los de TODAS sus membresías sin repetir, más SUPER ADMIN si la cuenta es
		// `isSystemAdmin`. Es lo que vale para decidir si entra a Reparto.
		// `memberships[].roles` NO lo es: es el `member.role` de better-auth, uno por
		// membresía y de otro vocabulario, así que una persona con [GESTOR, LOGISTICO]
		// aparecía ahí sólo como GESTOR y se quedaba fuera de su propio sistema.
		Role  string   `json:"role"`
		Roles []string `json:"roles"`
		// `entradas` en crudo: «no vino» y `[]` no son lo mismo. Ver [auth.LeerEntradas].
		Entradas json.RawMessage `json:"entradas"`
	}
	if err := json.Unmarshal(crudo, &r); err != nil {
		return nil, fmt.Errorf("Accesos contestó algo que no se entiende: %w", err)
	}
	if r.User == nil || r.User.ID == "" || r.User.Email == "" {
		return nil, errors.New("Accesos no devolvió la persona")
	}

	persona := &personaDeAccesos{
		ID:           r.User.ID,
		Email:        r.User.Email,
		Nombre:       r.User.Name,
		EsSuperAdmin: r.User.IsSystemAdmin,
		VolverA:      r.ReturnTo,
	}
	if persona.Nombre == "" {
		persona.Nombre = r.User.Email
	}
	// Una persona puede estar en varias sucursales; el reparto guarda una. Se
	// toma la primera, que Accesos devuelve de la más reciente a la más antigua.
	// Para quien lleve dos habrá que decidir cómo se elige; hoy no hay nadie así
	// y adivinarlo ahora sería inventar la regla.
	//
	// LOS ROLES: los de PRIMER NIVEL del intercambio (`role` + `roles`) y, SOLO si vienen vacíos
	// (un Accesos viejo), los de las membresías. En cualquier caso SIN el `admin` heredado.
	//
	// Por qué no la unión de todo, que es lo que había (auditoría, 08/10/2026): los roles de una
	// membresía son el `member.role` de better-auth, otro vocabulario (owner, admin, member…).
	// Un GERENTE con `member.role = 'admin'` salía con `admin` en el token, y `admin` a secas es
	// el PUENTE de la web vieja (`rolAdminHeredado`): entraba a Reparto y además era `EsAdmin()`.
	// Accesos nunca firma `admin` —sólo lo emitía la web vieja—, así que aquí no se acuña nunca,
	// venga de donde venga.
	//
	// Datos medidos HOY en producción (08/10/2026): los `member.role` reales son GESTOR,
	// OPERADOR, SUPERVISOR, ADMINISTRADOR y `member`; ninguno `admin`.
	//
	// ## EL LÍMITE QUE QUEDA (no se rediseña aquí; lo documenta `TestLimiteConocido…`)
	//
	// LA SUCURSAL sale de la PRIMERA membresía, y los roles son de LA PERSONA (el primer nivel
	// de Accesos junta los de todas sus membresías). Con una sola membresía —que es lo que hay
	// hoy: **ningún usuario tiene más de una**, medido el 08/10/2026— no se nota. Quien tuviera
	// GESTOR en una sucursal y ADMINISTRADOR en otra entraría como ADMINISTRADOR **en la
	// primera**. ANTES DE DARLE UNA SEGUNDA MEMBRESÍA A ALGUIEN HAY QUE LIGAR EL ROL A LA SUCURSAL
	// (aquí y en el alcance), o el rol más alto de una se lo lleva a la otra.
	var porMembresia [][]string
	for _, m := range r.Memberships {
		porMembresia = append(porMembresia, m.Roles)
	}
	persona.Roles = rolesDeLaPersona(r.Role, r.Roles, porMembresia)
	// QUIÉN ENTRA A REPARTO lo decide Auth con `entradas` (ver [auth.Usuario.PuedeEntrarAReparto]);
	// aquí sólo se conserva tal cual para firmarlo en la cookie. Ausente se queda ausente.
	persona.Entradas, persona.HayEntradas = auth.LeerEntradas(r.Entradas)
	if len(r.Memberships) > 0 && r.Memberships[0].Organization != nil {
		persona.CodigoSucursal = strings.ToUpper(strings.TrimSpace(r.Memberships[0].Organization.Slug))
	}
	return persona, nil
}

// rolesDeLaPersona elige los roles que van al token. Ver [ssoDeAccesos.Canjear].
func rolesDeLaPersona(role string, roles []string, porMembresia [][]string) []string {
	salida := unirRoles([]string{role}, roles)
	if len(salida) == 0 {
		salida = unirRoles(porMembresia...)
	}
	// Se filtra al final y de TODO: `admin` es el puente de la web vieja y no se acuña.
	filtrados := salida[:0:0]
	for _, r := range salida {
		if !auth.MismoRol(r, "admin") {
			filtrados = append(filtrados, r)
		}
	}
	return filtrados
}

// unirRoles junta listas de roles sin repetir, en el orden en que aparecen. Se repite por la
// misma comparación que el resto de la casa ([auth.MismoRol]: sin espacios, mayúsculas ASCII).
// Se queda con la primera forma escrita.
func unirRoles(grupos ...[]string) []string {
	var salida []string
	for _, g := range grupos {
		for _, r := range g {
			r = strings.TrimSpace(r)
			if r == "" {
				continue
			}
			repetido := false
			for _, ya := range salida {
				if auth.MismoRol(ya, r) {
					repetido = true
					break
				}
			}
			if !repetido {
				salida = append(salida, r)
			}
		}
	}
	return salida
}

func (c *ssoDeAccesos) base() string {
	if c.cfg == nil {
		return ""
	}
	return strings.TrimRight(strings.TrimSpace(c.cfg.AuthURL), "/")
}

func (c *ssoDeAccesos) clienteID() string {
	if c.cfg == nil {
		return ""
	}
	return c.cfg.AuthClientID
}

// firmado reutiliza la firma de `accesosHTTP` (`almacenes.go`). Se construye uno
// nuevo cada vez a propósito: lo único que ese cliente recuerda es la lista de
// almacenes, y estas dos llamadas no la tocan.
func (c *ssoDeAccesos) firmado(ctx context.Context, metodo, ruta string, cuerpo []byte, plazo time.Duration) ([]byte, error) {
	return (&accesosHTTP{cfg: c.cfg}).pedirFirmado(ctx, metodo, ruta, cuerpo, plazo)
}

// mismoSitio dice si dos direcciones son del mismo esquema y el mismo host.
func mismoSitio(candidato, base string) bool {
	if base == "" {
		return false
	}
	a, err := url.Parse(candidato)
	if err != nil || a.Scheme == "" || a.Host == "" {
		return false
	}
	b, err := url.Parse(base)
	if err != nil {
		return false
	}
	return strings.EqualFold(a.Scheme, b.Scheme) && strings.EqualFold(a.Host, b.Host)
}
