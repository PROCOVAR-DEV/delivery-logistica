package api

// EL MOTIVO DE UNA ZONA INACTIVA (00022, 1.0.38) es el mismo en el servidor y en el aparato:
// `docs/zonas-inactivas.casos.json` lo ata, y lo leen esta prueba y su gemela de la app. Es EL
// MISMO fichero, no una copia (`CLAUDE.md` §3-bis).

import (
	"encoding/json"
	"net/http"
	"os"
	"testing"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/store/sqlc"
)

const rutaDeLosCasosDeZonasInactivas = "../../../docs/zonas-inactivas.casos.json"

type casosDeZonasInactivas struct {
	Motivo string `json:"motivo"`
	Casos  []struct {
		Nombre   string `json:"nombre"`
		Esperado string `json:"esperado"`
	} `json:"casos"`
}

func leerCasosDeZonasInactivas(t *testing.T) casosDeZonasInactivas {
	t.Helper()
	b, err := os.ReadFile(rutaDeLosCasosDeZonasInactivas)
	if err != nil {
		t.Fatalf("no se pudo leer %s: %v\nEs lo que ata el literal del servidor con el del "+
			"aparato; sin él esta prueba no comprueba nada.", rutaDeLosCasosDeZonasInactivas, err)
	}
	var f casosDeZonasInactivas
	if err := json.Unmarshal(b, &f); err != nil {
		t.Fatalf("%s no se puede interpretar: %v", rutaDeLosCasosDeZonasInactivas, err)
	}
	if f.Motivo == "" || len(f.Casos) == 0 {
		t.Fatalf("%s sin motivo o sin casos: una prueba sobre nada sale verde", rutaDeLosCasosDeZonasInactivas)
	}
	return f
}

func TestElMotivoDeUnaZonaInactivaEsElDelFichero(t *testing.T) {
	f := leerCasosDeZonasInactivas(t)
	if f.Motivo != msgZonaInactiva {
		t.Fatalf("el literal del fichero es %q y el del servidor %q", f.Motivo, msgZonaInactiva)
	}
	for _, c := range f.Casos {
		if got := zonaInactiva(c.Nombre); got != c.Esperado {
			t.Errorf("zona %q: el servidor dice %q y el fichero %q", c.Nombre, got, c.Esperado)
		}
	}
}

// Y por HTTP, con cada nombre del fichero: colocar una tarjeta en la zona apagada devuelve
// EXACTAMENTE ese texto (el nombre sin recortar y con sus comillas).
func TestElMotivoQueSaleDeLaRespuestaEsElDelFichero(t *testing.T) {
	for _, c := range leerCasosDeZonasInactivas(t).Casos {
		q := nuevoTablero()
		zona := uuid.New()
		q.columnas[zona] = sqlc.BoardColumn{ID: zona, BranchID: sucStg, Nombre: c.Nombre, Posicion: 9}
		h := montarTab(t, q)
		w := pedirTab(t, h, http.MethodPut, "/api/board/placements/"+ped1.String(), tokenTab(t, sucStg.String()),
			`{"columnaId":"`+zona.String()+`","posicion":1}`)
		if w.Code != http.StatusConflict {
			t.Fatalf("zona %q: código %d, se esperaba 409 — %s", c.Nombre, w.Code, w.Body.String())
		}
		if got := leerTab(t, w)["error"]; got != c.Esperado {
			t.Errorf("zona %q: la respuesta dice %q y el fichero %q", c.Nombre, got, c.Esperado)
		}
	}
}
