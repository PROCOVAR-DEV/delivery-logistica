package sincro

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"procovar/reparto-sync/internal/identidad"
)

// LA UNIÓN CON «DISPOSITIVOS» DE ACCESOS — 29/10/2026.
//
// El aparato manda su `X-Aparato-Id` (el UUID de la instalación que Accesos enseña) en cada petición; aquí se anota en el aparato
// para que «Ver actividad» de Accesos llegue a esta pantalla. Es constancia: solo identifica, jamás da alcance ni cambia a quién
// pertenece el aparato.

const instalacionV7 = "0192f3c4-8a3b-7d0e-9d62-6a1f3b6f2c10"

func (b *banco) pedirCon(metodo, ruta string, cabeceras map[string]string, quien identidad.Identidad) *httptest.ResponseRecorder {
	b.t.Helper()
	req := httptest.NewRequest(metodo, ruta, strings.NewReader(""))
	for k, v := range cabeceras {
		req.Header.Set(k, v)
	}
	req = req.WithContext(identidad.Con(req.Context(), quien))
	w := httptest.NewRecorder()
	b.mux.ServeHTTP(w, req)
	return w
}

func TestLaBajadaUneElAparatoConSuInstalacionDeAccesos(t *testing.T) {
	b := montar(t)
	if b.base.aparatos[b.aparato.ID].InstalacionID != nil {
		t.Fatalf("el aparato de la prueba no debería traer instalación")
	}
	w := b.pedirCon(http.MethodGet, "/sync/bajada?aparato="+b.aparato.ID.String(),
		map[string]string{"X-Aparato-Id": strings.ToUpper(instalacionV7)}, b.quien)
	if w.Code != http.StatusOK {
		t.Fatalf("tenía que bajar (200), fue %d (%s)", w.Code, w.Body.String())
	}
	got := b.base.aparatos[b.aparato.ID].InstalacionID
	if got == nil || *got != instalacionV7 {
		t.Fatalf("tenía que quedar unido a %s (en minúsculas); quedó %v", instalacionV7, got)
	}
}

func TestUnaCabeceraMalaNoUneNadaNiRompeLaBajada(t *testing.T) {
	b := montar(t)
	for _, mala := range []string{"", "no-es-un-uuid", "../../etc/passwd", instalacionV7 + "x", "{" + instalacionV7 + "}"} {
		w := b.pedirCon(http.MethodGet, "/sync/bajada?aparato="+b.aparato.ID.String(),
			map[string]string{"X-Aparato-Id": mala}, b.quien)
		if w.Code != http.StatusOK {
			t.Fatalf("con la cabecera %q la bajada tenía que seguir (200), fue %d", mala, w.Code)
		}
		if got := b.base.aparatos[b.aparato.ID].InstalacionID; got != nil {
			t.Fatalf("la cabecera %q no es un UUID: no tenía que unirse a nada y quedó %q", mala, *got)
		}
	}
}

func TestElPanelDiceDeQueInstalacionEsCadaAparato(t *testing.T) {
	b := montar(t)
	b.pedirCon(http.MethodGet, "/sync/bajada?aparato="+b.aparato.ID.String(),
		map[string]string{"X-Aparato-Id": instalacionV7}, b.quien)

	w := b.pedir(http.MethodGet, "/sync/estado", nil, b.quien)
	if w.Code != http.StatusOK {
		t.Fatalf("el panel tenía que contestar 200, fue %d", w.Code)
	}
	var salida struct {
		Aparatos []struct {
			Aparato     string  `json:"aparato"`
			Instalacion *string `json:"instalacion"`
		} `json:"aparatos"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatalf("el panel no se entiende: %v", err)
	}
	var visto bool
	for _, a := range salida.Aparatos {
		if a.Aparato == b.aparato.ID.String() {
			visto = true
			if a.Instalacion == nil || *a.Instalacion != instalacionV7 {
				t.Fatalf("el panel tenía que decir la instalación %s, dijo %v", instalacionV7, a.Instalacion)
			}
		}
	}
	if !visto {
		t.Fatalf("el aparato no salió en el panel")
	}
}
