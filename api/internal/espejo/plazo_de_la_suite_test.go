package espejo

import (
	"fmt"
	"os"
	"testing"
	"time"
)

// UN BUCLE QUE NO AVANZA TIENE QUE SER UN FALLO, NO UN CUELGUE.
//
// La mutación `v-tramo-sin-siguiente` de la auditoría del 20/10/2026 —quitarle el paso a
// `Tramos` (`d += 0`)— dejó la suite colgada 255 s con la memoria creciendo: el bucle añade a una
// lista para siempre y lo llama CADA prueba que hace un ciclo (`e.Ciclo` → `porTramos`), no sólo
// las de `tramos_test.go`. Una función pura no se puede interrumpir desde fuera, y `-timeout`
// (10 min por defecto) llega tarde y con la memoria ya por las nubes.
//
// Esta suite entera tarda decenas de milisegundos (y cada segundo de bucle son GB de memoria: 3 s ya
// son varios). Si pasa de `plazoDeLaSuite`, algo no termina:
// se dice qué y se sale con error, que es lo que ve quien corre `go test` (rojo, y rápido).
// Las dos pruebas que llaman a `Tramos` y `Trozos` directamente llevan además su propio plazo
// (`conPlazo`, en `tramos_test.go`) y fallan con un mensaje más fino.
const plazoDeLaSuite = 3 * time.Second

func TestMain(m *testing.M) {
	vigia := time.AfterFunc(plazoDeLaSuite, func() {
		fmt.Fprintf(os.Stderr, "--- FAIL: la suite de internal/espejo pasó de %v y suele tardar milisegundos.\n"+
			"    Un bucle no avanza: ¿se rompió el paso de `Tramos` (`d += tramoDias`) o de `Trozos` (`i += tamano`)?\n"+
			"    Se aborta en vez de colgarse.\nFAIL\n", plazoDeLaSuite)
		os.Exit(1)
	})
	code := m.Run()
	vigia.Stop()
	os.Exit(code)
}
