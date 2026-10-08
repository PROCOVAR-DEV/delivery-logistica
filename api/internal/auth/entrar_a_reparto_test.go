package auth_test

import (
	"testing"

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
