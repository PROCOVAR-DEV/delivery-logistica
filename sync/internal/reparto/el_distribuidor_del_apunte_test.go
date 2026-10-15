package reparto

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/sincro"
)

// EL DISTRIBUIDOR DEL APUNTE LLEGA AL REPARTO TAL CUAL — issue 7 de Amado, 14/10/2026.
//
// La APK y el escritorio crean la ruta sin conexion y eligen quien la reparte: el apunte
// `POST /routes` lleva `distribuidorId` en su cuerpo. El sincronizador NO interpreta ese cuerpo (el
// reparto es quien valida que el distribuidor sea de la sucursal de la ruta y este en activo), asi
// que lo unico que puede salir mal aqui es que lo toque: que lo recorte, que lo reescriba o que
// convierta en un rechazo propio algo que es del reparto. Esta prueba ata las dos mitades:
//
//   - el cuerpo llega BYTE A BYTE, con su `distribuidorId` dentro;
//   - y el «no» del reparto por un distribuidor retirado o ajeno llega al aparato como RECHAZO con su
//     motivo LITERAL (un 4xx es un «no» de negocio y se queda a la vista en la bandeja, no se reintenta).
func TestElDistribuidorDelApunteLlegaAlRepartoTalCual(t *testing.T) {
	const cuerpo = `{"vehicleId":"v-1","distribuidorId":"d1000000-0000-0000-0000-000000000001","orderIds":["p-1"],"optimizar":true}`
	var vistos []byte
	var ruta string
	servidor := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		vistos, _ = io.ReadAll(r.Body)
		ruta = r.URL.Path
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{"id":"` + uuid.NewString() + `"}`))
	}))
	defer servidor.Close()

	c := Nuevo(servidor.URL, "clave-de-prueba", 5*time.Second)
	_, err := c.Aplicar(context.Background(), sincro.Peticion{
		Metodo: http.MethodPost, Ruta: "/routes", Cuerpo: json.RawMessage(cuerpo),
		Hecho: time.Now(), Sucursal: uuid.New(), Persona: "p", Clave: "k",
	})
	if err != nil {
		t.Fatalf("no tenia que fallar: %v", err)
	}
	if ruta != "/api/routes" {
		t.Errorf("se llamo a %q y se esperaba /api/routes", ruta)
	}
	if string(vistos) != cuerpo {
		t.Fatalf("el reparto recibio %s y se esperaba el cuerpo del apunte TAL CUAL: sin el "+
			"`distribuidorId` la ruta sube sin decir quien la reparte", vistos)
	}
}

func TestElNoDelRepartoPorUnDistribuidorEsUnRechazoConSuMotivo(t *testing.T) {
	for nombre, motivo := range map[string]string{
		"retirado":         "El distribuidor está retirado y no se puede asignar a una ruta.",
		"de otra sucursal": "El distribuidor 'd-1' no es de la sucursal de esta ruta",
		"que no existe":    "No existe el distribuidor 'd-1'",
	} {
		t.Run(nombre, func(t *testing.T) {
			servidor := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusBadRequest)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": motivo})
			}))
			defer servidor.Close()

			c := Nuevo(servidor.URL, "clave-de-prueba", 5*time.Second)
			_, err := c.Aplicar(context.Background(), sincro.Peticion{
				Metodo: http.MethodPost, Ruta: "/routes", Cuerpo: json.RawMessage(`{"distribuidorId":"d-1"}`),
				Hecho: time.Now(), Sucursal: uuid.New(), Persona: "p", Clave: "k",
			})
			var rechazo *sincro.Rechazo
			if !errors.As(err, &rechazo) {
				t.Fatalf("un 400 del reparto es un rechazo de negocio y se quedo en %v", err)
			}
			if rechazo.Motivo != motivo {
				t.Errorf("motivo = %q, se esperaba el literal %q", rechazo.Motivo, motivo)
			}
		})
	}
}
