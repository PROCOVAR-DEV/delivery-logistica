package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"

	"procovar/reparto-api/internal/auth"
)

// LA WEB LEE LA UNIÓN DE LOS ROLES, no sólo los de la primera membresía (08/10/2026).
//
// `/api/auth/exchange` de Accesos devuelve `role` y `roles` de PRIMER NIVEL: el rol por defecto
// y los de TODAS las membresías sin repetir, con SUPER ADMIN añadido si la cuenta es
// `isSystemAdmin`. Aquí sólo se leía `memberships[].roles`, que es el `member.role` de
// better-auth: UNO por membresía y de otro vocabulario. Una persona [GESTOR, LOGISTICO]
// aparecía como GESTOR y se quedaba fuera de Reparto web; una cuenta con SUPER ADMIN sólo como
// rol por defecto tampoco entraba. Fallaba cerrado, pero fallaba.
//
// Se prueba DE PUNTA A PUNTA, como la web: canje -> cookie -> una ruta detrás de `Exigir`.

func entrarPorLaWeb(t *testing.T, persona map[string]any) (cookie *http.Cookie, apps *httptest.ResponseRecorder, h http.Handler) {
	t.Helper()
	accesos := levantarAccesos(t, func(string, map[string]any) (int, any) { return http.StatusOK, persona })
	h = puertaDePrueba(t, accesos.URL, llaveDeFirma)
	galleta := laCookie(t, pedir(h, "/api/auth/callback?code=abc"))
	r := httptest.NewRequest(http.MethodGet, "http://reparto.test/api/apps", nil)
	r.AddCookie(&http.Cookie{Name: galleta.Name, Value: galleta.Value})
	apps = httptest.NewRecorder()
	h.ServeHTTP(apps, r)
	return galleta, apps, h
}

func personaConRoles(esSistema bool, role string, roles []string, membresias ...map[string]any) map[string]any {
	ms := make([]any, 0, len(membresias))
	for _, m := range membresias {
		ms = append(ms, m)
	}
	p := map[string]any{
		"user":        map[string]any{"id": "u-9", "email": "ana@procovar.cu", "name": "Ana", "isSystemAdmin": esSistema},
		"memberships": ms,
	}
	if role != "" {
		p["role"] = role
	}
	if roles != nil {
		p["roles"] = roles
	}
	return p
}

func membresia(slug string, roles ...string) map[string]any {
	return map[string]any{
		"organization": map[string]any{"slug": slug, "name": slug},
		"roles":        roles,
	}
}

func TestLaWebEntraConLaUnionDeLosRolesDeAccesos(t *testing.T) {
	casos := []struct {
		nombre  string
		persona map[string]any
		entra   bool
		rol     string // el principal que queda en el token
	}{
		{"[GESTOR, LOGISTICO] en los roles de primer nivel",
			personaConRoles(false, "GESTOR", []string{"GESTOR", "LOGISTICO"}, membresia("hab", "GESTOR")),
			true, "LOGISTICO"},
		{"sólo GESTOR no entra",
			personaConRoles(false, "GESTOR", []string{"GESTOR"}, membresia("hab", "GESTOR")),
			false, "GESTOR"},
		{"SUPER ADMIN sólo como rol por defecto, sin membresías",
			personaConRoles(false, "SUPER ADMIN", []string{"SUPER ADMIN"}),
			true, "SUPER ADMIN"},
		{"isSystemAdmin sin rol ni membresías (SUPER ADMIN lo añade RolesDeVerdad)",
			personaConRoles(true, "", nil),
			true, "SUPER ADMIN"},
		{"el rol de Reparto sólo en la segunda membresía",
			personaConRoles(false, "", nil, membresia("hab", "GESTOR"), membresia("cam", "LOGISTICO")),
			true, "LOGISTICO"},
		{"Accesos viejo, sin roles de primer nivel: la membresía sigue valiendo",
			personaConRoles(false, "", nil, membresia("hab", "ADMINISTRADOR")),
			true, "ADMINISTRADOR"},
		{"Accesos viejo y sólo GESTOR: no entra",
			personaConRoles(false, "", nil, membresia("hab", "GESTOR")),
			false, "GESTOR"},
		{"el vocabulario de better-auth (owner, member) no abre nada",
			personaConRoles(false, "GERENTE", []string{"GERENTE"}, membresia("hab", "owner", "member")),
			false, "GERENTE"},
		{"sin ningún rol",
			personaConRoles(false, "", nil, membresia("hab")),
			false, ""},
		// LA AUDITORÍA DEL 08/10/2026 (ALTO): `admin` a secas es el puente de la web vieja, y
		// el `member.role` de better-auth puede valer `admin`. Un GERENTE con esa membresía
		// entraba a Reparto y era además `EsAdmin()`.
		{"GERENTE con member.role = admin NO entra por la membresía",
			personaConRoles(false, "GERENTE", []string{"GERENTE"}, membresia("hab", "admin")),
			false, "GERENTE"},
		{"member.role = admin en un Accesos viejo (sin primer nivel) tampoco abre",
			personaConRoles(false, "", nil, membresia("hab", "admin")),
			false, ""},
		{"`admin` en el primer nivel tampoco se acuña",
			personaConRoles(false, "admin", []string{"admin"}, membresia("hab", "GESTOR")),
			false, ""},
		{"con primer nivel, la membresía NO suma (solo es la caída de un Accesos viejo)",
			personaConRoles(false, "GESTOR", []string{"GESTOR"}, membresia("hab", "LOGISTICO")),
			false, "GESTOR"},
		{"`admin` se filtra y lo demás del primer nivel sigue valiendo",
			personaConRoles(false, "admin", []string{"admin", "LOGISTICO"}, membresia("hab", "GESTOR")),
			true, "LOGISTICO"},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			galleta, apps, h := entrarPorLaWeb(t, c.persona)

			if c.entra && apps.Code != http.StatusOK {
				t.Fatalf("tenía que entrar a Reparto por la web: %d %s", apps.Code, apps.Body.String())
			}
			if !c.entra {
				if apps.Code != http.StatusForbidden || !strings.Contains(apps.Body.String(), `"codigo":"sin_permiso_reparto"`) {
					t.Fatalf("tenía que recibir el 403 con `codigo`: %d %s", apps.Code, apps.Body.String())
				}
			}

			// El principal que queda en el token y que `/api/me` le dice a la app.
			r := httptest.NewRequest(http.MethodGet, "http://reparto.test/api/me", nil)
			r.AddCookie(&http.Cookie{Name: galleta.Name, Value: galleta.Value})
			w := httptest.NewRecorder()
			h.ServeHTTP(w, r)
			var yo YoSalida
			if err := json.Unmarshal(w.Body.Bytes(), &yo); err != nil || yo.User == nil {
				t.Fatalf("/api/me: %v %s", err, w.Body.String())
			}
			if yo.User.Role != c.rol {
				t.Errorf("/api/me dice rol %q y tenía que decir %q: la app decide con eso", yo.User.Role, c.rol)
			}
		})
	}
}

// La unión no repite ni distingue mayúsculas, y respeta el orden en que aparecen.
func TestUnirRolesNoRepiteYConservaElOrden(t *testing.T) {
	got := unirRoles([]string{"GESTOR"}, []string{"GESTOR", " logistico "}, []string{"LOGISTICO", "", "OPERADOR"})
	want := []string{"GESTOR", "logistico", "OPERADOR"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("%v, se esperaba %v", got, want)
	}
	if got := unirRoles(nil, []string{}, []string{""}); len(got) != 0 {
		t.Fatalf("sin roles tiene que salir vacío: %v", got)
	}
}

// Y NO SE ACUÑA `admin`: ni `EsAdmin()` ni `EsSuperAdmin()` del token que sale de la puerta de la
// web pueden deberse al puente de la web vieja. Es la mitad "es además EsAdmin()" del hallazgo.
func TestElAdminHeredadoNoSeAcunaEnElTokenDeLaWeb(t *testing.T) {
	persona := personaConRoles(false, "GERENTE", []string{"GERENTE"}, membresia("hab", "admin"))
	galleta, _, _ := entrarPorLaWeb(t, persona)
	u, err := auth.NuevoVerificador([]byte(secretoDePrueba)).Verificar(galleta.Value)
	if err != nil {
		t.Fatal(err)
	}
	if u.EsAdmin() || u.EsSuperAdmin() || u.PuedeEntrarAReparto() {
		t.Fatalf("un GERENTE con member.role=admin salió con poderes: rol %q roles %v", u.Rol, u.Roles)
	}
	for _, r := range append([]string{u.Rol}, u.Roles...) {
		if auth.MismoRol(r, "admin") {
			t.Fatalf("el token lleva `admin`: rol %q roles %v", u.Rol, u.Roles)
		}
	}
}

// EL LÍMITE CONOCIDO, escrito como prueba para que no se pierda (08/10/2026). NO es una
// garantía: describe lo que pasa HOY y que hay que arreglar ANTES de dar una segunda membresía.
//
// La sucursal sale de la primera membresía y los roles son de la PERSONA (el primer nivel de
// Accesos junta los de todas). Quien es GESTOR en Habana y ADMINISTRADOR en Camagüey entra
// como ADMINISTRADOR **en Habana**. Hoy nadie tiene dos membresías (medido el 08/10/2026), así
// que no se explota. Si esta prueba empieza a fallar porque alguien ligó el rol a la sucursal,
// MUY BIEN: cámbiala por la aserción buena.
func TestLimiteConocidoElRolMasAltoDeUnaSucursalSeLlevaLaOtra(t *testing.T) {
	persona := personaConRoles(false, "GESTOR", []string{"GESTOR", "ADMINISTRADOR"},
		membresia("hab", "GESTOR"), membresia("cam", "ADMINISTRADOR"))
	galleta, apps, _ := entrarPorLaWeb(t, persona)
	u, err := auth.NuevoVerificador([]byte(secretoDePrueba)).Verificar(galleta.Value)
	if err != nil {
		t.Fatal(err)
	}
	if apps.Code != http.StatusOK || u.Rol != "ADMINISTRADOR" || u.Sucursal != "HAB" {
		t.Fatalf("el límite documentado cambió: código %d, rol %q, sucursal %q (hoy: entra como "+
			"ADMINISTRADOR en la PRIMERA membresía, HAB)", apps.Code, u.Rol, u.Sucursal)
	}
}
