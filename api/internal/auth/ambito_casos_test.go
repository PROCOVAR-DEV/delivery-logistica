package auth_test

import (
	"encoding/json"
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	"procovar/reparto-api/internal/auth"
)

// «UN TOKEN CON `ambito` NO ENTRA POR LAS RUTAS NORMALES» ESTÁ ESCRITO DOS VECES: aquí
// (`Verificador.Verificar`) y en `sync/internal/identidad/token.go`, que son dos módulos de Go.
// Las ata `docs/ambito-de-entrega.casos.json`, EL MISMO fichero que lee la prueba gemela de sync
// (`entrega_test.go`); y viaja en las imágenes (`COPY` en los Dockerfile, que vigila
// `TestLosDockerfileCopianTodosLosCasosQueLasPruebasLeen`). De ese fichero, esta mitad lee la
// ruta normal (`normal`); `entrega` es de sync (`DeTokenDeEntrega`) y aquí no se lee nunca.
//
// Lo que cada módulo CONTESTA (api 401, sync 403 `sin_permiso_reparto`) no se compara: solo que
// NO entra. Aquí, además, se exige lo más estricto que esta mitad promete: si el token trae la
// clave `ambito`, lo rechaza `Verificar` (ErrAmbito), no solo `PuedeEntrarAReparto`.

type casoDeAmbito struct {
	Nombre string         `json:"nombre"`
	Base   string         `json:"base"`
	Con    map[string]any `json:"con"`
	Sin    []string       `json:"sin"`
	Normal string         `json:"normal"` // "entra" | "rechaza" | "" (no se comprueba)
}

func casosDeAmbito(t *testing.T) (base map[string]map[string]any, casos []casoDeAmbito) {
	t.Helper()
	crudo, err := os.ReadFile("../../../docs/ambito-de-entrega.casos.json")
	if err != nil {
		t.Fatalf("no se pudo leer docs/ambito-de-entrega.casos.json: %v. En una imagen es que "+
			"el Dockerfile no lo copia", err)
	}
	var f struct {
		Base  map[string]map[string]any `json:"base"`
		Casos []casoDeAmbito            `json:"casos"`
	}
	if err := json.Unmarshal(crudo, &f); err != nil || len(f.Casos) < 20 || len(f.Base) == 0 {
		t.Fatalf("el fichero de casos no se entiende o está casi vacío (%d): %v", len(f.Casos), err)
	}
	return f.Base, f.Casos
}

func TestElAmbitoDeEntregaEsElDeLosCasosCompartidos(t *testing.T) {
	bases, casos := casosDeAmbito(t)
	v := auth.NuevoVerificador([]byte(secreto))
	comprobados, conAmbito := 0, 0
	for _, c := range casos {
		if c.Normal == "" {
			continue
		}
		comprobados++
		t.Run(c.Nombre, func(t *testing.T) {
			ahora := time.Now()
			claims := map[string]any{}
			for k, val := range bases[c.Base] {
				claims[k] = val
			}
			claims["iat"] = ahora.Unix()
			claims["exp"] = ahora.Add(600 * time.Second).Unix()
			for k, val := range c.Con {
				switch val {
				case "$caducado":
					val = ahora.Add(-2 * time.Hour).Unix()
				case "$larga":
					val = ahora.Add(time.Hour).Unix()
				}
				claims[k] = val
			}
			for _, k := range c.Sin {
				delete(claims, k)
			}
			traeAmbito := false
			for k := range claims {
				traeAmbito = traeAmbito || strings.EqualFold(k, "ambito")
			}

			u, err := v.Verificar(firmar(t, "HS256", claims))
			entra := err == nil && u.PuedeEntrarAReparto()
			switch c.Normal {
			case "entra":
				if !entra {
					t.Fatalf("tenía que entrar y no entró (err %v)", err)
				}
			case "rechaza":
				if entra {
					t.Fatalf("un token que los casos compartidos rechazan ENTRÓ a Reparto como %+v", u)
				}
			default:
				t.Fatalf("`normal` = %q: el fichero dice algo que esta prueba no entiende", c.Normal)
			}
			if traeAmbito {
				conAmbito++
				if !errors.Is(err, auth.ErrAmbito) {
					t.Fatalf("trae `ambito` y Verificar tenía que rechazarlo con ErrAmbito: %v", err)
				}
			}
		})
	}
	if comprobados < 15 || conAmbito == 0 {
		t.Fatalf("la prueba no comprueba nada: %d casos de ruta normal, %d con ambito (¿cambió el formato del fichero?)",
			comprobados, conAmbito)
	}
}
