package auth_test

import (
	"testing"
	"time"

	"procovar/reparto-api/internal/auth"
)

// QUIÉN ENTRA A REPARTO (Jose, 08/10/2026): SUPER ADMIN, DESARROLLADOR, ADMINISTRADOR y
// LOGISTICO. Es una lista de los que entran: un rol nuevo en Accesos nace SIN acceso.
func TestPuedeEntrarAReparto(t *testing.T) {
	casos := []struct {
		nombre string
		u      auth.Usuario
		entra  bool
	}{
		{"SUPER ADMIN", auth.Usuario{Rol: "SUPER ADMIN"}, true},
		{"DESARROLLADOR", auth.Usuario{Rol: "DESARROLLADOR"}, true},
		{"ADMINISTRADOR", auth.Usuario{Rol: "ADMINISTRADOR"}, true},
		{"LOGISTICO", auth.Usuario{Rol: "LOGISTICO"}, true},
		{"admin heredado de la web vieja", auth.Usuario{Rol: "admin"}, true},
		{"en minúscula y con espacios (como el resto de comparaciones)", auth.Usuario{Rol: " logistico "}, true},
		{"sólo en Roles", auth.Usuario{Roles: []string{"GERENTE", "LOGISTICO"}}, true},
		{"en Rol y Roles de otra cosa", auth.Usuario{Rol: "LOGISTICO", Roles: []string{"GERENTE"}}, true},
		{"Rol de otra cosa, uno de Roles entra", auth.Usuario{Rol: "GERENTE", Roles: []string{"GERENTE", "ADMINISTRADOR"}}, true},

		{"GERENTE", auth.Usuario{Rol: "GERENTE"}, false},
		{"SUPERVISOR", auth.Usuario{Rol: "SUPERVISOR"}, false},
		{"GESTOR", auth.Usuario{Rol: "GESTOR"}, false},
		{"OPERADOR", auth.Usuario{Rol: "OPERADOR"}, false},
		{"ECONOMICA", auth.Usuario{Rol: "ECONOMICA"}, false},
		{"ANALISTA", auth.Usuario{Rol: "ANALISTA"}, false},
		{"rol vacío", auth.Usuario{}, false},
		{"Roles vacío", auth.Usuario{Roles: []string{}}, false},
		{"rol desconocido", auth.Usuario{Rol: "INVENTADO"}, false},
		{"la errata LOGISTICA", auth.Usuario{Rol: "LOGISTICA"}, false},
		{"con tilde no es el que firma Accesos", auth.Usuario{Rol: "LOGÍSTICO"}, false},
		{"«contiene admin» no vale", auth.Usuario{Rol: "SUBADMINISTRADOR"}, false},
		// El plegado Unicode de `strings.EqualFold` (auditoría, 08/10/2026): ya NO entran.
		{"«ſUPER ADMIN» (s larga, U+017F)", auth.Usuario{Rol: "ſUPER ADMIN"}, false},
		{"«ADMINIſTRADOR» (s larga, U+017F)", auth.Usuario{Rol: "ADMINIſTRADOR"}, false},
		{"«ADMİNİSTRADOR» (İ con punto, U+0130)", auth.Usuario{Rol: "ADMİNİSTRADOR"}, false},
		{"«LOGİSTICO» (İ con punto)", auth.Usuario{Rol: "LOGİSTICO"}, false},
		{"«ſuper admin» en Roles", auth.Usuario{Rol: "GERENTE", Roles: []string{"ſuper admin"}}, false},
		{"mayúsculas y minúsculas ASCII siguen valiendo", auth.Usuario{Rol: "Super Admin"}, true},
		{"dos roles y ninguno entra", auth.Usuario{Rol: "GERENTE", Roles: []string{"GERENTE", "OPERADOR"}}, false},
		// Las cuentas de servicio llevan Rol:"SUPER ADMIN" puesto a mano (ver
		// `TestLasPersonasSinteticasDeServicioLlevanSuRol`): entran por esto además de por
		// no pasar por `Exigir`.
		{"cuenta de servicio", auth.Usuario{ID: "servicio:espejo", Rol: "SUPER ADMIN"}, true},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			if got := c.u.PuedeEntrarAReparto(); got != c.entra {
				t.Fatalf("PuedeEntrarAReparto() = %v, se esperaba %v para %+v", got, c.entra, c.u)
			}
		})
	}
}

// `MismoRol` es LA comparación (la usan `tieneAlguno`, la web y `EsAdmin`/`EsSuperAdmin`): ASCII
// sin distinguir mayúsculas, con espacios recortados, y NADA de plegado Unicode.
func TestMismoRol(t *testing.T) {
	for _, c := range []struct {
		a, b string
		es   bool
	}{
		{"SUPER ADMIN", "super admin", true},
		{"  LOGISTICO ", "logistico", true},
		{"admin", "ADMIN", true},
		{"ſUPER ADMIN", "SUPER ADMIN", false},
		{"ADMİNİSTRADOR", "ADMINISTRADOR", false},
		{"SUPER ADMIN", "SUPER  ADMIN", false},
		{"", "", true},
		{"GERENTE", "", false},
	} {
		if got := auth.MismoRol(c.a, c.b); got != c.es {
			t.Errorf("MismoRol(%q, %q) = %v, se esperaba %v", c.a, c.b, got, c.es)
		}
	}
	// Y las dos preguntas de siempre siguen contestando lo mismo con los roles de verdad.
	if !(&auth.Usuario{Rol: "SUPER ADMIN"}).EsSuperAdmin() || !(&auth.Usuario{Rol: "administrador"}).EsAdmin() {
		t.Fatal("EsSuperAdmin/EsAdmin dejaron de reconocer los roles de verdad")
	}
	if (&auth.Usuario{Rol: "ſUPER ADMIN"}).EsSuperAdmin() || (&auth.Usuario{Rol: "ADMINIſTRADOR"}).EsAdmin() {
		t.Fatal("EsSuperAdmin/EsAdmin aceptan un rol con plegado Unicode")
	}
}

// ---------------------------------------------------------------------------
// QUIÉN ENTRA LO DECIDE AUTH (`entradas`, 08/10/2026). La tabla de roles de arriba es la CAÍDA.
// ---------------------------------------------------------------------------

func conEntradas(hay bool, rol string, llaves ...string) auth.Usuario {
	return auth.Usuario{Rol: rol, Entradas: llaves, HayEntradas: hay}
}

func TestEntradasDecideSoloCuandoEstaPresente(t *testing.T) {
	casos := []struct {
		nombre string
		u      auth.Usuario
		entra  bool
	}{
		{"delivery.entrar: GERENTE entra", conEntradas(true, "GERENTE", "delivery.entrar"), true},
		{"delivery.entrar: un rol desconocido entra", conEntradas(true, "INVENTADO", "delivery.entrar"), true},
		{"delivery.entrar: sin rol entra", conEntradas(true, "", "delivery.entrar"), true},
		{"pedido.entrar: ADMINISTRADOR NO", conEntradas(true, "ADMINISTRADOR", "pedido.entrar"), false},
		{"pedido.entrar: SUPER ADMIN NO", conEntradas(true, "SUPER ADMIN", "pedido.entrar"), false},
		{"presente y vacío: LOGISTICO NO", conEntradas(true, "LOGISTICO"), false},
		{"AUSENTE: LOGISTICO entra por la caída", conEntradas(false, "LOGISTICO"), true},
		{"AUSENTE: GERENTE NO", conEntradas(false, "GERENTE"), false},
		{"texto exacto: DELIVERY.ENTRAR NO", conEntradas(true, "LOGISTICO", "DELIVERY.ENTRAR"), false},
		{"texto exacto: con un espacio NO", conEntradas(true, "LOGISTICO", " delivery.entrar"), false},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			if got := c.u.PuedeEntrarAReparto(); got != c.entra {
				t.Fatalf("PuedeEntrarAReparto() = %v, se esperaba %v para %+v", got, c.entra, c.u)
			}
		})
	}
}

// «AUSENTE» Y «VACÍO» NO SON LO MISMO, desde el token: es el corazón de la transición. Ausente =
// «Auth todavía no lo decía» (caída a los roles); `[]` = «Auth dice que no».
func TestAusenteYVacioNoSonLoMismoEnElToken(t *testing.T) {
	v := auth.NuevoVerificador([]byte(secreto))
	leer := func(rec map[string]any) *auth.Usuario {
		rec["sub"], rec["role"] = "p-1", "LOGISTICO"
		u, err := v.Verificar(firmar(t, "HS256", rec))
		if err != nil {
			t.Fatal(err)
		}
		return u
	}

	ausente := leer(map[string]any{})
	if ausente.HayEntradas || !ausente.PuedeEntrarAReparto() {
		t.Fatalf("ausente: HayEntradas=%v entra=%v (tenía que caer a los roles y entrar)", ausente.HayEntradas, ausente.PuedeEntrarAReparto())
	}
	vacio := leer(map[string]any{"entradas": []string{}})
	if !vacio.HayEntradas || vacio.PuedeEntrarAReparto() {
		t.Fatalf("[]: HayEntradas=%v entra=%v (tenía que ser PRESENTE y no entrar)", vacio.HayEntradas, vacio.PuedeEntrarAReparto())
	}
	// `null` y «no es un array»: presentes y rotos -> falla cerrado.
	for nombre, valor := range map[string]any{"null": nil, "un texto": "delivery.entrar", "un objeto": map[string]any{"a": 1}} {
		u := leer(map[string]any{"entradas": valor})
		if !u.HayEntradas || u.PuedeEntrarAReparto() {
			t.Errorf("entradas=%s: HayEntradas=%v entra=%v (presente y roto: no entra)", nombre, u.HayEntradas, u.PuedeEntrarAReparto())
		}
	}
	// El campo sobrevive aunque OTRO campo del token traiga un tipo raro (camino tolerante).
	u := leer(map[string]any{"entradas": []string{"delivery.entrar"}, "branchId": 7})
	if !u.HayEntradas || !u.PuedeEntrarAReparto() {
		t.Errorf("con un campo suelto raro se perdió `entradas`: %+v", u)
	}
	// Los elementos que no son texto se ignoran.
	u = leer(map[string]any{"entradas": []any{"pedido.entrar", 5, nil, "delivery.entrar"}})
	if !u.PuedeEntrarAReparto() || len(u.Entradas) != 2 {
		t.Errorf("elementos que no son texto: %+v", u.Entradas)
	}
}

// LA CAÍDA POR ROLES ES DE TRANSICIÓN, y esta prueba la NOMBRA para que no se olvide.
//
// QUITAR `CaidaPorRolesDeTransicion` (y la lista de roles de `PuedeEntrarAReparto`) cuando
// caduquen los tokens y cookies anteriores al 08/10/2026: la cookie web dura 7 días ->
// 15/10/2026 (el access token de la APK, 15 minutos). Después Reparto decide SOLO por
// `entradas`. NO falla pasada la fecha a propósito —una prueba que se pone roja sola rompería la
// construcción de la imagen el día del despliegue—: avisa en el registro de la prueba (`-v`).
func TestLaCaidaPorRolesEsDeTransicion(t *testing.T) {
	if !auth.CaidaPorRolesDeTransicion {
		t.Fatal("la caída por roles está apagada: si es a propósito (ya caducaron los tokens " +
			"anteriores al 08/10/2026), borra esta prueba y la lista de roles; si no, enciéndela")
	}
	// Mientras esté encendida, la caída es EXACTAMENTE la tabla de roles de ayer.
	if !(&auth.Usuario{Rol: "LOGISTICO"}).PuedeEntrarAReparto() {
		t.Fatal("con la caída encendida, un LOGISTICO sin `entradas` tiene que entrar")
	}
	if time.Now().After(time.Date(2026, 10, 16, 0, 0, 0, 0, time.UTC)) {
		t.Log("YA PUEDE QUITARSE la caída por roles (CaidaPorRolesDeTransicion): caducaron las " +
			"cookies web anteriores al 08/10/2026. Reparto debe decidir SOLO por `entradas`.")
	}
}
