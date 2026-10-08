package sincro

import (
	"net/http"
	"testing"
	"time"
)

// Esto SÓLO existe para las pruebas de `sincro_test`, el paquete de pruebas de fuera.
//
// Hace falta porque la prueba de extremo a extremo —el cliente HTTP REAL de
// `internal/reparto` metido en este servicio— no puede vivir dentro del paquete: `reparto`
// importa `sincro`, y una prueba de dentro que importara `reparto` sería un ciclo. Desde
// fuera sí se puede, pero entonces los dobles de `dobles_test.go` (la base en memoria, el
// banco) son invisibles. Este fichero los presta sin duplicar ni uno: es el mismo `montar`
// de las demás pruebas, con un único cambio —el `Aplicador` que se le dice.

// Resultado es lo que el servicio contestó de un apunte, tal como lo lee el aparato.
type Resultado struct{ Clave, Estado, Motivo string }

// Prueba es un servicio montado sobre la base en memoria, para usarlo desde fuera.
type Prueba struct{ b *banco }

// MontarConAplicador monta el servicio de siempre pero escribiendo en `ap`.
func MontarConAplicador(t *testing.T, ap Aplicador) *Prueba {
	b := montar(t)
	b.servicio.aplicador = ap
	return &Prueba{b: b}
}

// Subir manda UN lote con estos apuntes (clave, ruta, cuerpo), todos POST.
func (p *Prueba) Subir(apuntes ...[3]string) []Resultado {
	p.b.t.Helper()
	var lote []apunteEntrada
	for _, a := range apuntes {
		lote = append(lote, apunteEntrada{
			Clave: a[0], Metodo: http.MethodPost, Ruta: a[1], Cuerpo: []byte(a[2]),
			Hecho: time.Date(2026, 10, 8, 10, 0, 0, 0, time.UTC),
		})
	}
	w, res := p.b.subir(lote, p.b.quien)
	if w.Code != http.StatusOK {
		p.b.t.Fatalf("la subida contestó %d: %s", w.Code, w.Body.String())
	}
	salida := make([]Resultado, 0, len(res))
	for _, r := range res {
		salida = append(salida, Resultado{r.Clave, r.Estado, r.Motivo})
	}
	return salida
}

// Anotado dice cómo quedó el apunte en el libro del servidor: "" si no consta.
func (p *Prueba) Anotado(clave string) string {
	return string(p.b.base.apuntes[llave(p.b.aparato.ID, clave)].Estado)
}

// EnLaBandeja devuelve el motivo que una persona va a leer, si el apunte está en ella.
func (p *Prueba) EnLaBandeja(clave string) (string, bool) {
	r, hay := p.b.base.rechazos[llave(p.b.aparato.ID, clave)]
	return r.Motivo, hay
}

// Pendientes es lo que el panel anotó como pendiente en la última subida.
func (p *Prueba) Pendientes() int32 {
	return p.b.base.subidas[len(p.b.base.subidas)-1].Pendientes
}
