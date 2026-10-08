package identidad

import (
	"encoding/json"
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

// LA GEMELA de `api/internal/auth/roles_de_reparto_casos_test.go`: EL MISMO fichero,
// `docs/roles-de-reparto.casos.json`. La lista de quién entra a Reparto está escrita en dos
// módulos de Go que no se pueden importar el uno al otro; esto es lo que impide que se
// separen sin que se ponga nada en rojo (auditoría de seguridad, 08/10/2026).
func TestLaListaDeRolesDeRepartoEsLaDeLosCasosCompartidos(t *testing.T) {
	crudo, err := os.ReadFile("../../../docs/roles-de-reparto.casos.json")
	if err != nil {
		t.Fatalf("no se pudo leer docs/roles-de-reparto.casos.json: %v. En una imagen es que "+
			"deploy/Dockerfile.sync no lo copia", err)
	}
	var f struct {
		Casos []struct {
			Nombre string    `json:"nombre"`
			Role   *string   `json:"role"`
			Rol    *string   `json:"rol"`
			Roles  *[]string `json:"roles"`
			Entra  bool      `json:"entra"`
		} `json:"casos"`
	}
	if err := json.Unmarshal(crudo, &f); err != nil || len(f.Casos) < 20 {
		t.Fatalf("el fichero de casos no se entiende o está casi vacío (%d): %v", len(f.Casos), err)
	}

	for _, c := range f.Casos {
		t.Run(c.Nombre, func(t *testing.T) {
			rec := map[string]any{
				"sub": "p-1", "branchId": uuid.New().String(),
				"exp": time.Now().Add(time.Hour).Unix(),
			}
			if c.Role != nil {
				rec["role"] = *c.Role
			}
			if c.Rol != nil {
				rec["rol"] = *c.Rol
			}
			if c.Roles != nil {
				rec["roles"] = *c.Roles
			}
			_, err := conToken(t, firmar(t, rec, "HS256"))
			switch {
			case c.Entra && err != nil:
				t.Fatalf("los casos compartidos dicen que ENTRA y el sincronizador lo rechaza: %v", err)
			case !c.Entra && !errors.Is(err, ErrSinPermisoDeReparto):
				t.Fatalf("los casos compartidos dicen que NO entra y el sincronizador contesta %v", err)
			}
		})
	}

	// El Dockerfile de este módulo tiene que copiar el fichero (no viaja dentro de la imagen, así
	// que el chequeo sólo corre donde está `deploy/`): sin él esta prueba hace Fatalf en la
	// imagen, y Dokploy deja corriendo el contenedor viejo.
	if d, err := os.ReadFile("../../../deploy/Dockerfile.sync"); err == nil &&
		!strings.Contains(string(d), "COPY docs/roles-de-reparto.casos.json") {
		t.Errorf("deploy/Dockerfile.sync no copia docs/roles-de-reparto.casos.json: la imagen no " +
			"construiría (añade `COPY docs/roles-de-reparto.casos.json /docs/roles-de-reparto.casos.json`)")
	}
}

// El `admin` heredado SIN sucursal es super en la API (`EsSuperAdmin`) y aquí era un 401: las dos
// mitades decían cosas distintas de la misma persona. Ahora ve todas, igual que allí.
func TestElAdminHeredadoSinSucursalVeTodasComoEnLaAPI(t *testing.T) {
	id, err := conToken(t, firmar(t, map[string]any{
		"sub": "viejo", "role": "admin", "branchId": nil,
		"exp": time.Now().Add(time.Hour).Unix(),
	}, "HS256"))
	if err != nil || !id.EsSuperAdmin {
		t.Fatalf("el admin heredado sin sucursal tenía que ver todas: %v %+v", err, id)
	}
	// Y con sucursal, la suya, como todos.
	id, err = conToken(t, firmar(t, map[string]any{
		"sub": "viejo", "role": "admin", "branchId": uuid.New().String(),
		"exp": time.Now().Add(time.Hour).Unix(),
	}, "HS256"))
	if err != nil || id.EsSuperAdmin {
		t.Fatalf("el admin heredado CON sucursal no ve todas: %v %+v", err, id)
	}
}
