package reparto

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/sincro"
)

// LAS TRES CABECERAS QUE SÓLO PONE LA REVISIÓN (`docs/bandeja-de-revision.md`, B.2 «Aplicar» punto 3):
// `X-Sucursal-Id` FORZADA a la sucursal del apunte (lo que acota a un SUPER ADMIN a UNA sucursal: sin ella la
// autoridad prestada llega a las ocho), `X-Autor` y `X-Revision` (para el registro del reparto, que no
// autoriza nada con ellas). Y la pareja: la subida normal NO las manda.

func capturar(t *testing.T, p sincro.Peticion) http.Header {
	t.Helper()
	var visto http.Header
	servidor := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		visto = r.Header.Clone()
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{}`))
	}))
	defer servidor.Close()
	p.Metodo, p.Ruta, p.Cuerpo, p.Hecho, p.Clave = http.MethodPost, "/routes", json.RawMessage(`{}`), time.Now(), "k1"
	if _, err := Nuevo(servidor.URL, "clave-de-servicio", 5*time.Second).Aplicar(context.Background(), p); err != nil {
		t.Fatal(err)
	}
	return visto
}

func TestLaRevisionManda_XSucursalId_XAutor_YXRevision_ConElTokenDelRevisor(t *testing.T) {
	sucursal := uuid.New()
	h := capturar(t, sincro.Peticion{
		Token: "token-del-revisor", Persona: "revisor-1",
		Autor: "quien-lo-hizo", Revision: "entrega-9", SucursalPedida: sucursal,
	})
	if got := h.Get("X-Sucursal-Id"); got != sucursal.String() {
		t.Errorf("X-Sucursal-Id = %q, tiene que ser la sucursal del apunte %s", got, sucursal)
	}
	if got := h.Get("X-Autor"); got != "quien-lo-hizo" {
		t.Errorf("X-Autor = %q", got)
	}
	if got := h.Get("X-Revision"); got != "entrega-9" {
		t.Errorf("X-Revision = %q", got)
	}
	// Y firma el REVISOR, con su token, y no la clave de servicio.
	if got := h.Get("Authorization"); got != "Bearer token-del-revisor" {
		t.Errorf("Authorization = %q", got)
	}
	if h.Get("x-api-key") != "" {
		t.Error("la clave de servicio viajó junto al token del revisor: autoridad prestada sin límite")
	}
}

func TestLaSubidaNormalNoMandaLasCabecerasDeLaRevision(t *testing.T) {
	h := capturar(t, sincro.Peticion{Token: "token-de-la-persona", Persona: "p1", Sucursal: uuid.New()})
	for _, c := range []string{"X-Sucursal-Id", "X-Autor", "X-Revision"} {
		if v := h.Get(c); v != "" {
			t.Errorf("la subida normal mandó %s=%q: no es suya", c, v)
		}
	}
}
