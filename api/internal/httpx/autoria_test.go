package httpx

import (
	"bytes"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// La línea general de la petición lleva `autor` y `revision` SOLO en las escrituras (POST, PUT,
// PATCH, DELETE): lo demás no las anota aunque lleguen. Ver [autoriaDe].
func TestLaLineaDeLaPeticionLlevaLaAutoriaSoloEnLasEscrituras(t *testing.T) {
	for metodo, quiere := range map[string]bool{
		http.MethodPost: true, http.MethodPut: true, http.MethodPatch: true, http.MethodDelete: true,
		http.MethodGet: false, http.MethodHead: false, http.MethodOptions: false,
	} {
		var salida bytes.Buffer
		h := NuevoRouter(IDDePeticion, ConRegistro(slog.New(slog.NewTextHandler(&salida, nil))), RegistrarPeticiones)
		h.ManejarFunc(metodo, "/x", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) })
		r := httptest.NewRequest(metodo, "/x", nil)
		r.Header.Set("Authorization", "Bearer cabecera.cuerpo.firma")
		r.Header.Set("X-Autor", "  p-yasmani ")
		r.Header.Set("X-Revision", "rev-7")
		h.Handler().ServeHTTP(httptest.NewRecorder(), r)

		linea := salida.String()
		tiene := strings.Contains(linea, "autor=p-yasmani") && strings.Contains(linea, "revision=rev-7")
		if tiene != quiere {
			t.Errorf("%s: autor/revision en la línea = %v, se esperaba %v:\n%s", metodo, tiene, quiere, linea)
		}
		if strings.Contains(linea, "firma") || strings.Contains(linea, "Bearer") || strings.Contains(linea, "actor=") {
			t.Errorf("%s: la línea de la petición lleva la credencial o un actor:\n%s", metodo, linea)
		}
	}
}
