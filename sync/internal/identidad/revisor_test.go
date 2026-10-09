package identidad

import (
	"testing"
	"time"

	"github.com/google/uuid"
)

// QUIÉN REVISA LA BANDEJA (`docs/bandeja-de-revision.md` B.3, Jose 08/10/2026): ADMINISTRADOR de esa
// sucursal, SUPER ADMIN y DESARROLLADOR. LOGISTICO entra a Reparto pero NO revisa. Por NOMBRE de rol, exacto en
// ASCII (sin el plegado Unicode de `strings.EqualFold`), y con el token del revisor: sin él no hay reenvío.

func TestElTokenLlevaSusRolesPorNombre(t *testing.T) {
	ahora := time.Now().Unix()
	id, err := conToken(t, firmar(t, map[string]any{
		"sub": "u-1", "role": "ADMINISTRADOR", "roles": []string{"LOGISTICO", " "}, "branchId": uuid.NewString(),
		"entradas": []string{"delivery.entrar"}, "exp": ahora + 600,
	}, "HS256"))
	if err != nil {
		t.Fatal(err)
	}
	if len(id.Roles) != 2 || id.Roles[0] != "ADMINISTRADOR" || id.Roles[1] != "LOGISTICO" {
		t.Errorf("los roles del token verificado: %v (sin vacíos, el principal primero)", id.Roles)
	}
	if rol, ok := id.RolDeRevisor(); !ok || rol != "ADMINISTRADOR" {
		t.Errorf("un ADMINISTRADOR revisa: %q %v", rol, ok)
	}
}

func TestSoloEstosRolesRevisan(t *testing.T) {
	casos := []struct {
		nombre string
		id     Identidad
		rol    string // "" = no revisa
	}{
		{"ADMINISTRADOR", Identidad{Token: "t", Roles: []string{"ADMINISTRADOR"}}, "ADMINISTRADOR"},
		{"SUPER ADMIN", Identidad{Token: "t", Roles: []string{"SUPER ADMIN"}}, "SUPER ADMIN"},
		{"DESARROLLADOR", Identidad{Token: "t", Roles: []string{"DESARROLLADOR"}}, "DESARROLLADOR"},
		{"minúsculas y espacios", Identidad{Token: "t", Roles: []string{"  super admin "}}, "SUPER ADMIN"},
		{"uno de varios", Identidad{Token: "t", Roles: []string{"LOGISTICO", "ADMINISTRADOR"}}, "ADMINISTRADOR"},

		{"LOGISTICO entra a Reparto pero no revisa", Identidad{Token: "t", Roles: []string{"LOGISTICO"}}, ""},
		{"GERENTE", Identidad{Token: "t", Roles: []string{"GERENTE"}}, ""},
		{"SUPERVISOR", Identidad{Token: "t", Roles: []string{"SUPERVISOR"}}, ""},
		{"GESTOR", Identidad{Token: "t", Roles: []string{"GESTOR"}}, ""},
		{"OPERADOR", Identidad{Token: "t", Roles: []string{"OPERADOR"}}, ""},
		{"ECONOMICA", Identidad{Token: "t", Roles: []string{"ECONOMICA"}}, ""},
		{"el `admin` heredado de la web vieja no es ninguno", Identidad{Token: "t", Roles: []string{"admin"}, EsSuperAdmin: true}, ""},
		{"«contiene admin» no basta", Identidad{Token: "t", Roles: []string{"SUBADMINISTRADOR"}}, ""},
		{"sin roles (modo cabeceras)", Identidad{Token: "t"}, ""},
		// El plegado Unicode de EqualFold casaba 'ſ' (U+017F) con 's': «ſUPER ADMIN» pasaba por SUPER ADMIN.
		{"ſUPER ADMIN (U+017F)", Identidad{Token: "t", Roles: []string{"ſUPER ADMIN"}}, ""},
		// Sin el token del revisor no hay reenvío posible: caería a la clave de servicio.
		{"un ADMINISTRADOR SIN token", Identidad{Roles: []string{"ADMINISTRADOR"}}, ""},
		// El token de entrega a revisión no revisa jamás, lleve lo que lleve.
		{"token de entrega", Identidad{Token: "t", Ambito: AmbitoEntrega, Roles: []string{"ADMINISTRADOR"}}, ""},
	}
	for _, c := range casos {
		rol, ok := c.id.RolDeRevisor()
		if (c.rol != "") != ok || rol != c.rol {
			t.Errorf("%s: RolDeRevisor() = %q, %v; se esperaba %q", c.nombre, rol, ok, c.rol)
		}
	}
}
