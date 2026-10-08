package auth_test

import (
	"encoding/json"
	"os"
	"testing"

	"procovar/reparto-api/internal/auth"
)

// LA LISTA DE QUIÉN ENTRA A REPARTO ESTÁ ESCRITA DOS VECES: aquí (`Usuario.PuedeEntrarAReparto`)
// y en `sync/internal/identidad/token.go`, que son dos módulos de Go y no se pueden importar.
// Auditoría de seguridad, 08/10/2026: ya se habían separado (con `role=GESTOR` y
// `rol=LOGISTICO` el sincronizador dejaba pasar y la API no).
//
// Las ata `docs/roles-de-reparto.casos.json`, EL MISMO fichero que lee la prueba gemela del
// sincronizador (`roles_de_reparto_casos_test.go`): cada caso es un token y lo que tienen que
// decir las dos mitades. Si cambia una lista sin la otra, esta o aquélla se pone roja. Y el
// fichero viaja en las imágenes (`COPY docs/roles-de-reparto.casos.json` en los Dockerfile).
type casoDeRol struct {
	Nombre string    `json:"nombre"`
	Role   *string   `json:"role"`
	Rol    *string   `json:"rol"`
	Roles  *[]string `json:"roles"`
	Entra  bool      `json:"entra"`
}

func casosDeRoles(t *testing.T) []casoDeRol {
	t.Helper()
	crudo, err := os.ReadFile("../../../docs/roles-de-reparto.casos.json")
	if err != nil {
		t.Fatalf("no se pudo leer docs/roles-de-reparto.casos.json: %v. En una imagen es que el "+
			"Dockerfile no lo copia", err)
	}
	var f struct {
		Casos []casoDeRol `json:"casos"`
	}
	if err := json.Unmarshal(crudo, &f); err != nil || len(f.Casos) < 20 {
		t.Fatalf("el fichero de casos no se entiende o está casi vacío (%d): %v", len(f.Casos), err)
	}
	return f.Casos
}

func TestLaListaDeRolesDeRepartoEsLaDeLosCasosCompartidos(t *testing.T) {
	v := auth.NuevoVerificador([]byte(secreto))
	for _, c := range casosDeRoles(t) {
		t.Run(c.Nombre, func(t *testing.T) {
			rec := map[string]any{"sub": "p-1", "branchId": "s-1"}
			if c.Role != nil {
				rec["role"] = *c.Role
			}
			if c.Rol != nil {
				rec["rol"] = *c.Rol
			}
			if c.Roles != nil {
				rec["roles"] = *c.Roles
			}
			u, err := v.Verificar(firmar(t, "HS256", rec))
			if err != nil {
				t.Fatal(err)
			}
			if got := u.PuedeEntrarAReparto(); got != c.Entra {
				t.Fatalf("PuedeEntrarAReparto() = %v, los casos compartidos dicen %v (rol %q, roles %v)",
					got, c.Entra, u.Rol, u.Roles)
			}
		})
	}
}
