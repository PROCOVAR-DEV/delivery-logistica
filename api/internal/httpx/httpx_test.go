package httpx_test

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"procovar/reparto-api/internal/httpx"
)

// Un pánico en un manejador no puede llevarse el proceso: con él se van las peticiones
// en vuelo de las otras nueve sucursales.
func TestUnPanicoNoTumbaElProceso(t *testing.T) {
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	h := httpx.Encadenar(
		http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
			var v []int
			_ = v[3] // fuera de rango, a propósito
		}),
		httpx.IDDePeticion, httpx.ConRegistro(reg), httpx.RecuperarPanico,
	)

	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/orders", nil))

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("código %d", w.Code)
	}
	// Y hacia fuera NO sale la traza: lleva la consulta y a veces el dato que falló.
	cuerpo := strings.TrimSpace(w.Body.String())
	if cuerpo != `{"error":"Error interno"}` {
		t.Fatalf("cuerpo %q", cuerpo)
	}
}

// El id de la petición es lo que permite abrir el registro por la línea buena cuando el
// logístico llama diciendo «me salió un error».
func TestElIdDeLaPeticionVuelveEnLaCabecera(t *testing.T) {
	h := httpx.Encadenar(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if httpx.IDDeLaPeticion(r) == "" {
			t.Error("el manejador tiene que poder leer el id")
		}
		w.WriteHeader(http.StatusOK)
	}), httpx.IDDePeticion)

	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/health", nil))
	if w.Header().Get("X-Peticion-Id") == "" {
		t.Fatal("falta la cabecera")
	}

	// El que traiga el cliente se conserva: así una cadena APK -> API -> PEDIDO se sigue
	// entera con el mismo hilo.
	r := httptest.NewRequest(http.MethodGet, "/health", nil)
	r.Header.Set("X-Peticion-Id", "hilo-de-la-apk")
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Header().Get("X-Peticion-Id") != "hilo-de-la-apk" {
		t.Fatalf("se perdió el hilo: %q", w.Header().Get("X-Peticion-Id"))
	}
}

// El tri-estado de los PATCH. Sin esto, un PATCH que sólo quería cambiar el nombre borra
// la matrícula del camión.
func TestOpcionalDistingueNoVinoDeVinoVacio(t *testing.T) {
	type cuerpo struct {
		Plate httpx.Opcional[string] `json:"plate"`
	}

	var sinPlate cuerpo
	leer(t, `{"name":"X"}`, &sinPlate)
	if sinPlate.Plate.Presente {
		t.Fatal("no vino: no se toca")
	}

	var plateNula cuerpo
	leer(t, `{"plate":null}`, &plateNula)
	if !plateNula.Plate.Presente || plateNula.Plate.Valor != nil {
		t.Fatal("vino null: se borra")
	}

	var conPlate cuerpo
	leer(t, `{"plate":"B-123"}`, &conPlate)
	if !conPlate.Plate.Presente || conPlate.Plate.Valor == nil || *conPlate.Plate.Valor != "B-123" {
		t.Fatal("vino con valor: se pone")
	}
}

func leer(t *testing.T, json string, destino any) {
	t.Helper()
	r := httptest.NewRequest(http.MethodPatch, "/api/vehicles/x", strings.NewReader(json))
	if !httpx.LeerJSON(httptest.NewRecorder(), r, destino) {
		t.Fatalf("no se pudo leer %s", json)
	}
}

// `codigo` es para los pocos errores donde el cliente tiene que distinguir; en el resto el
// cuerpo sigue siendo `{"error":"..."}` byte por byte (los clientes en la calle lo leen así).
func TestErrorConCodigoLlevaElCodigoYErrorNoLoInventa(t *testing.T) {
	w := httptest.NewRecorder()
	httpx.ErrorConCodigo(w, httptest.NewRequest(http.MethodGet, "/x", nil), http.StatusForbidden, "No.", "mi_codigo")
	if w.Code != http.StatusForbidden || strings.TrimSpace(w.Body.String()) != `{"error":"No.","codigo":"mi_codigo"}` {
		t.Fatalf("ErrorConCodigo: %d %q", w.Code, w.Body.String())
	}

	w = httptest.NewRecorder()
	httpx.Error(w, httptest.NewRequest(http.MethodGet, "/x", nil), http.StatusForbidden, "No.")
	if strings.TrimSpace(w.Body.String()) != `{"error":"No."}` {
		t.Fatalf("Error no debe llevar `codigo`: %q", w.Body.String())
	}
}
