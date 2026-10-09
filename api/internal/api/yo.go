// QUIÉN SOY  (GET /api/me)  Y A DÓNDE PUEDO IR  (GET /api/apps).
//
// Las dos son de la sesión y ninguna toca la base: lo que contestan sale del token, que ya
// viene firmado por Accesos. Aquí NO se comprueban contraseñas ni se consulta una tabla de
// personas —no la hay— y eso es la decisión, no una tarea pendiente: quien manda en
// personas, roles y sucursales es auth (`../docs/identidad.md`).
package api

import (
	"net/http"
	"strings"

	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/httpx"
)

// PersonaSalida son los cinco campos que la pantalla guarda de la sesión.
type PersonaSalida struct {
	ID       string  `json:"id"`
	Email    string  `json:"email"`
	Name     string  `json:"name"`
	Role     string  `json:"role"`
	BranchID *string `json:"branchId"`
}

// YoSalida: el usuario y el token.
//
// El token se devuelve a propósito y no es un descuido de seguridad: la web entra por el
// login único y se queda con una cookie `httpOnly`, que su propio JavaScript no puede
// leer; para llamar a la API con `Authorization: Bearer` —que es como habla la APK— tiene
// que pedirlo por aquí. Sólo se devuelve el que ya traía la petición: esto no emite nada.
type YoSalida struct {
	User  *PersonaSalida `json:"user"`
	Token *string        `json:"token"`
}

// AppSalida es una baldosa del menú de aplicaciones.
type AppSalida struct {
	Href        string `json:"href"`
	Icon        string `json:"icon"`
	Title       string `json:"title"`
	Description string `json:"description"`
}

// app es la entrada del catálogo. `soloAdmin` NO SALE en la respuesta: decirle a quien no
// puede entrar que existe una puerta y que es de administración es media pista regalada.
type app struct {
	AppSalida
	soloAdmin bool
}

// El catálogo, fijo y en este orden. Es una lista escrita y no una tabla porque son los
// dominios de la casa: cambian una vez al año y a la vez que el DNS, no desde una pantalla.
var appsDeLaCasa = []app{
	{AppSalida{"https://pedidos.procovar.cloud", "mdi:clipboard-list-outline", "PEDIDO", "Pedidos, clientes y vendedores."}, false},
	{AppSalida{"https://entrega.procovar.cloud", "mdi:package-variant-closed-check", "Entrega", "El panel de los repartidores."}, false},
	{AppSalida{"https://rutas.procovar.cloud", "mdi:routes", "Rutas", "Recorridos de los vendedores en el mapa."}, false},
	{AppSalida{"https://analitics.procovar.cloud", "mdi:chart-bar", "Analitics", "Informes de ventas y gestores."}, false},
	{AppSalida{"https://caja.procovar.cloud", "mdi:cash-register", "Caja", "Cobros y cierres de caja."}, false},
	{AppSalida{"https://traslado.procovar.cloud", "mdi:swap-horizontal", "Traslado", "Mercancía entre sucursales."}, false},
	{AppSalida{"https://ccsa.procovar.cloud", "mdi:view-dashboard-outline", "Tablero Parranda", "El tablero de Parranda / CCSA."}, false},
	{AppSalida{"https://procovar.cloud", "mdi:home-outline", "Portal", "La entrada común a todo lo demás."}, false},
	// Sólo para el administrador GLOBAL: el que es admin y NO pertenece a ninguna
	// sucursal. Un administrador de sucursal manda en lo suyo, no en las cuentas de todos.
	{AppSalida{"https://auth.procovar.cloud/dashboard", "mdi:shield-account-outline", "Accesos", "Cuentas, sucursales y permisos."}, true},
}

// rutasYo monta las dos. Ninguna lleva los middlewares de `sesion`, y por razones
// distintas en cada una:
//
//   - `/api/me` comprueba la sesión ELLA MISMA porque su 401 es `{"user":null}` y no el
//     `{"error":"Unauthorized"}` de todo lo demás. La web arranca preguntando aquí si tiene
//     sesión, y con el cuerpo de siempre no sabría distinguir «no has entrado» de «se rompió
//     algo», que llevan a sitios distintos: al login o a un aviso.
//   - `/api/apps` sí exige sesión, pero NO alcance: es una lista escrita en el código, no
//     toca la base, y montar el alcance le añadiría una consulta a Postgres —resolver una
//     sucursal que nadie va a usar— a la pantalla que se abre la primera de todas.
func (s *Servidor) rutasYo(rt *httpx.Router, sesion, admin []httpx.Medio) {
	rt.ManejarFunc(http.MethodGet, "/api/me", s.yo)
	rt.ManejarFunc(http.MethodGet, "/api/apps", s.apps, s.verif.Exigir)
}

// GET /api/me
func (s *Servidor) yo(w http.ResponseWriter, r *http.Request) {
	// LA MISMA ELECCIÓN QUE `Exigir` y el canal en vivo (`DelaPeticionDeReparto`): con dos
	// cookies `token` de la misma persona [GERENTE, LOGISTICO], `/api/vehicles` entra como
	// LOGISTICO y `/api/me` decía GERENTE, o sea que la app enseñaba «sin permiso» a quien sí
	// entra. Y el token que se devuelve es el de ESA cookie.
	u, elegida, err := s.verif.DelaPeticionDeRepartoConCredencial(r)
	if err != nil {
		// 401 con `{"user":null}`, no con `{"error":...}`. El motivo va al registro: qué
		// falló exactamente —no hay token, la firma no cuadra, está caducado— no se le
		// cuenta a quien pregunta.
		httpx.Registro(r).Warn("sesión rechazada en /api/me", "motivo", err)
		s.verif.BorrarCookieSiInvalidada(w, r, err)
		httpx.JSON(w, r, http.StatusUnauthorized, YoSalida{})
		return
	}
	httpx.JSON(w, r, http.StatusOK, YoSalida{
		User: &PersonaSalida{
			ID: u.ID, Email: u.Email, Name: u.Nombre, Role: u.Rol,
			// Vacío es null y no "": la persona SIN sucursal es el Super Admin, y una
			// cadena vacía guardada en la pantalla acabaría viajando en la cabecera
			// `X-Sucursal-Id` como si fuera una sucursal elegida.
			BranchID: aTexto(u.Sucursal),
		},
		Token: tokenDeLaCookie(r, elegida),
	})
}

// GET /api/apps
func (s *Servidor) apps(w http.ResponseWriter, r *http.Request) {
	u := auth.De(r)
	if u == nil {
		// Imposible salvo fallo de montaje (falta `Exigir` delante). Se deja constancia
		// porque si no, no lo ve nadie.
		httpx.Registro(r).Error("/api/apps sin sesión delante")
		httpx.NoAutorizado(w, r)
		return
	}
	// `EsSuperAdmin` es exactamente el `role === 'admin' && !branchId` del contrato.
	global := u.EsSuperAdmin()

	salida := make([]AppSalida, 0, len(appsDeLaCasa))
	for _, a := range appsDeLaCasa {
		if a.soloAdmin && !global {
			continue
		}
		salida = append(salida, a.AppSalida)
	}
	httpx.JSON(w, r, http.StatusOK, map[string]any{"apps": salida})
}

// tokenDeLaCookie devuelve el token de la cookie que decidió quién es la persona, o nil.
//
// SÓLO el de una cookie: si la petición vino con `Authorization: Bearer`, quien pregunta ya
// tiene su token y devolvérselo no añade nada. Es el contrato, y además deja esta ruta sin
// ninguna forma de convertir una credencial de un sitio en otra. Con varias cookies `token`
// es la que [Verificador.DelaPeticionDeRepartoConCredencial] eligió, no la primera.
func tokenDeLaCookie(r *http.Request, elegida string) *string {
	for _, c := range r.CookiesNamed("token") {
		if v := strings.TrimSpace(c.Value); v != "" && v == elegida {
			return &v
		}
	}
	return nil
}
