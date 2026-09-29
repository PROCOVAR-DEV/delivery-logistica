package api

// UN FICHERO DE `docs/` QUE UNA PRUEBA LEE ES CÓDIGO, Y TIENE QUE VIAJAR EN LAS CUATRO
// IMÁGENES.
//
// Esto ha mordido TRES veces, siempre igual y siempre en el mismo sitio:
//
//	21/09/2026  `docs/orden-de-paradas.casos.json`
//	26/09/2026  `docs/almacen-de-origen.casos.json`
//	29/09/2026  `docs/armado-rechazado.casos.json`
//
// El mecanismo, que es lo que hay que entender para que no haya una cuarta: **el espejo y
// la api son el mismo módulo de Go**, así que el `go test ./...` del `Dockerfile.espejo`
// corre TODAS las pruebas de `internal/api` y de `internal/cotizar`, no sólo las del
// espejo. Quien añade una prueba que lee un fichero de `docs/` piensa en el Dockerfile de
// su servicio y no en los otros.
//
// Y lo que lo hace caro es cómo se ve desde fuera: el 29/09 la api, el sincronizador y la
// web entraron bien, y sólo el espejo dijo «error» — **dejando corriendo el contenedor
// viejo**, que es lo que Dokploy hace cuando un build falla. Tres verdes y uno rojo se lee
// como «ya está desplegado», y el espejo es justo el que escribe los pedidos.
//
// Los comentarios de los propios Dockerfile ya avisaban de esto las dos veces anteriores.
// No sirvieron: **un comentario no falla** (§3-bis). Esto sí.

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// LOS QUE CORREN `go test ./...` SOBRE **ESTE** MÓDULO, que son dos y no tres.
//
// `Dockerfile.sync` también corre `go test ./...`, y aun así no está aquí: construye desde
// `sync/`, que es **otro módulo de Go** (`procovar/reparto-sync`), así que sus pruebas no
// son éstas y estos ficheros no le hacen falta. Meterlo daría tres fallos que no existen y
// acabaría con alguien copiando ficheros por si acaso.
//
// La api y el espejo sí: los dos construyen desde `api/`, o sea `procovar/reparto-api`, y
// ahí `./...` es todo — también las pruebas de `internal/cotizar`, que es justo por donde
// mordió el 26/09/2026.
//
// Y la web tampoco está: compila Flutter, y sus ficheros los vigila su gemela de Dart.
var dockerfilesQueCorrenLasPruebasDeGo = []string{
	"Dockerfile.api",
	"Dockerfile.espejo",
}

// Lo que una prueba de Go abre por `../../../docs/…`.
var leeUnFicheroDeDocs = regexp.MustCompile(`\.\./\.\./\.\./(docs/[\w.-]+\.json)`)

func TestLosDockerfileCopianTodosLosCasosQueLasPruebasLeen(t *testing.T) {
	raiz := raizDelRepo(t)

	// 1 · Qué ficheros de `docs/` abre alguna prueba de este módulo.
	necesarios := map[string]string{} // fichero -> quién lo lee, para poder decirlo
	rutaApi := filepath.Join(raiz, "api")
	err := filepath.Walk(rutaApi, func(ruta string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() || !strings.HasSuffix(ruta, "_test.go") {
			return err
		}
		cuerpo, err := os.ReadFile(ruta)
		if err != nil {
			return err
		}
		for _, m := range leeUnFicheroDeDocs.FindAllStringSubmatch(string(cuerpo), -1) {
			if _, ya := necesarios[m[1]]; !ya {
				rel, _ := filepath.Rel(raiz, ruta)
				necesarios[m[1]] = rel
			}
		}
		return nil
	})
	if err != nil {
		t.Fatalf("no se pudo barrer las pruebas: %v", err)
	}

	// Si esto se queda en cero, la prueba no comprueba nada y saldría verde para siempre:
	// la expresión de arriba habría dejado de casar con cómo se escriben las rutas.
	if len(necesarios) == 0 {
		t.Fatal("ninguna prueba parece leer un fichero de `docs/`. O se quitaron todas " +
			"—y entonces sobran los COPY de los Dockerfile— o `leeUnFicheroDeDocs` ya no " +
			"casa con cómo se escribe la ruta. Las dos cosas hay que mirarlas: tal como " +
			"está, esta guarda no vigila nada")
	}

	// 2 · Y que los tres los copien.
	for _, nombre := range dockerfilesQueCorrenLasPruebasDeGo {
		ruta := filepath.Join(raiz, "deploy", nombre)
		cuerpo, err := os.ReadFile(ruta)
		if err != nil {
			t.Fatalf("no se pudo leer deploy/%s: %v", nombre, err)
		}
		texto := string(cuerpo)
		if !strings.Contains(texto, "go test ./...") {
			t.Fatalf("deploy/%s ya no corre `go test ./...`. Si es a propósito, sácalo de "+
				"`dockerfilesQueCorrenLasPruebasDeGo`; si no lo es, es el agujero del "+
				"16/09/2026, cuando una mutación de prueba se desplegó porque el "+
				"Dockerfile de `sync` sólo compilaba", nombre)
		}
		for fichero, quienLoLee := range necesarios {
			if strings.Contains(texto, "COPY "+fichero) {
				continue
			}
			t.Errorf("deploy/%s NO copia %s, y %s lo lee.\n\n"+
				"Esa imagen no va a construir: el `go test ./...` de ahí dentro corre "+
				"TODAS las pruebas de este módulo, también las de los otros servicios. Y "+
				"se ve tarde y mal — las demás imágenes entran, ésta dice «error» y "+
				"Dokploy DEJA CORRIENDO EL CONTENEDOR VIEJO, así que parece desplegado.\n\n"+
				"Añade esta línea a deploy/%s, junto a las otras:\n"+
				"    COPY %s /%s",
				nombre, fichero, quienLoLee, nombre, fichero, fichero)
		}
	}
}

// raizDelRepo sube hasta encontrar la carpeta `deploy/`. Se busca en vez de darla por
// sabida porque `go test` corre con el directorio del paquete, y esta prueba tiene que
// valer igual desde `api/internal/api` que desde la raíz.
func raizDelRepo(t *testing.T) string {
	t.Helper()
	aqui, err := os.Getwd()
	if err != nil {
		t.Fatalf("no se pudo saber dónde estamos: %v", err)
	}
	for i := 0; i < 8; i++ {
		if _, err := os.Stat(filepath.Join(aqui, "deploy")); err == nil {
			return aqui
		}
		padre := filepath.Dir(aqui)
		if padre == aqui {
			break
		}
		aqui = padre
	}
	t.Skip("no se encontró la raíz del repositorio: esta prueba mira los Dockerfile, que " +
		"no viajan dentro de la imagen")
	return ""
}
