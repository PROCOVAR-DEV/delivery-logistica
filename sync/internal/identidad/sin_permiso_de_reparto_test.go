package identidad

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

// SÓLO CUATRO ROLES ENTRAN A REPARTO (Jose, 08/10/2026) — también por el sincronizador.
//
// Este servicio verifica el token por su cuenta y sirve la bajada de SU base sin pasar por
// `reparto-api`: si el control sólo estuviera en la API, un GERENTE con la APK se bajaría el
// día entero de su sucursal por aquí. Misma lista, mismo 403 y mismo `codigo` que la API.

const cuerpoSinPermiso = `{"error":"No tienes permiso para entrar a Reparto.","codigo":"sin_permiso_reparto"}`

func tokenDeRol(t *testing.T, reclamos map[string]any) string {
	t.Helper()
	reclamos["sub"] = "persona-1"
	reclamos["branchId"] = uuid.New().String()
	reclamos["exp"] = time.Now().Add(time.Hour).Unix()
	return firmar(t, reclamos, "HS256")
}

func TestLosCuatroRolesDeRepartoEntranAlSincronizador(t *testing.T) {
	for _, rol := range []string{"SUPER ADMIN", "DESARROLLADOR", "ADMINISTRADOR", "LOGISTICO", "admin"} {
		if _, err := conToken(t, tokenDeRol(t, map[string]any{"role": rol})); err != nil {
			t.Errorf("%s tenía que entrar: %v", rol, err)
		}
	}
	// Sólo en `roles`, y con otro rol delante.
	if _, err := conToken(t, tokenDeRol(t, map[string]any{"roles": []string{"GERENTE", "LOGISTICO"}})); err != nil {
		t.Errorf("un token con dos roles, uno de Reparto, tenía que entrar: %v", err)
	}
}

func TestLosDemasRolesNoEntranAlSincronizador(t *testing.T) {
	for _, rol := range []string{
		"GERENTE", "SUPERVISOR", "GESTOR", "OPERADOR", "ECONOMICA", "ANALISTA",
		"", "DESCONOCIDO", "LOGISTICA",
	} {
		_, err := conToken(t, tokenDeRol(t, map[string]any{"role": rol}))
		if !errors.Is(err, ErrSinPermisoDeReparto) {
			t.Errorf("rol %q: error %v, se esperaba ErrSinPermisoDeReparto", rol, err)
		}
	}
	_, err := conToken(t, tokenDeRol(t, map[string]any{
		"role": "GERENTE", "roles": []string{"GERENTE", "OPERADOR"}}))
	if !errors.Is(err, ErrSinPermisoDeReparto) {
		t.Errorf("dos roles y ninguno de Reparto: %v", err)
	}
}

// A quien no entra NO se le traduce el código de su sucursal: eso es una llamada al reparto
// por cada petición de quien no tiene nada que hacer aquí.
func TestQuienNoEntraNoGastaUnaLlamadaAlReparto(t *testing.T) {
	llamadas := 0
	_, err := conTokenY(t, firmar(t, map[string]any{
		"sub": "x", "role": "GERENTE", "sucursal": "CAM",
		"exp": time.Now().Add(time.Hour).Unix(),
	}, "HS256"), func(context.Context, string) (uuid.UUID, error) {
		llamadas++
		return uuid.New(), nil
	})
	if !errors.Is(err, ErrSinPermisoDeReparto) {
		t.Fatalf("error %v", err)
	}
	if llamadas != 0 {
		t.Fatalf("se tradujo el código %d veces: el control va ANTES de la sucursal", llamadas)
	}
}

// El 403 de `Exigir`: mismo cuerpo que la API, y ni el cuerpo ni el registro llevan el token.
func TestExigirContestaElMismo403DeLaAPISinFiltrarElToken(t *testing.T) {
	var registro bytes.Buffer
	anterior := slog.Default()
	slog.SetDefault(slog.New(slog.NewTextHandler(&registro, nil)))
	t.Cleanup(func() { slog.SetDefault(anterior) })

	llegó := false
	h := Exigir(DeToken([]byte(secreto), nil), http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		llegó = true
	}))

	jwt := tokenDeRol(t, map[string]any{"role": "GERENTE"})
	r := httptest.NewRequest(http.MethodPost, "/sync/aparato", nil)
	r.Header.Set("Authorization", "Bearer "+jwt)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)

	if llegó {
		t.Fatal("un GERENTE llegó al manejador")
	}
	if w.Code != http.StatusForbidden {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if got := strings.TrimSpace(w.Body.String()); got != cuerpoSinPermiso {
		t.Fatalf("cuerpo %q, se esperaba %q", got, cuerpoSinPermiso)
	}
	for _, quiero := range []string{"level=WARN", "sin permiso de reparto", "GERENTE", "/sync/aparato"} {
		if !strings.Contains(registro.String(), quiero) {
			t.Errorf("al registro le falta %q:\n%s", quiero, registro.String())
		}
	}
	for _, trozo := range append(strings.Split(jwt, "."), jwt) {
		if strings.Contains(registro.String(), trozo) || strings.Contains(w.Body.String(), trozo) {
			t.Errorf("el token se filtró (%.12s…)", trozo)
		}
	}

	// Y un token de Reparto sigue pasando por el mismo `Exigir`.
	llegó = false
	r = httptest.NewRequest(http.MethodPost, "/sync/aparato", nil)
	r.Header.Set("Authorization", "Bearer "+tokenDeRol(t, map[string]any{"role": "LOGISTICO"}))
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if !llegó || w.Code != http.StatusOK {
		t.Fatalf("un LOGISTICO no entró: %d %s", w.Code, w.Body.String())
	}
}

// Sin token sigue siendo 401 (mata la sesión en el cliente) y NO 403: son dos cosas opuestas.
func TestSinTokenSigueSiendo401YNoElSinPermiso(t *testing.T) {
	h := Exigir(DeToken([]byte(secreto), nil), http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/sync/aparato", nil))
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
}

// EL ORDEN IMPORTA: el control de rol va ANTES de la regla de la sucursal (auditoría del repo,
// 08/10/2026). Un GERENTE sin sucursal tiene que recibir `ErrSinPermisoDeReparto` (403, y la app
// lo manda a Accesos), NO `ErrSinSesion` (401): un 401 que sobrevive a renovar mata la sesión en
// el cliente y lo tira a la puerta sin decirle nada. Con el control movido detrás de la
// comprobación de «sin sucursal» esta prueba da 401 y se pone roja.
func TestUnGerenteSinSucursalRecibeSinPermisoYNoSinSesion(t *testing.T) {
	for _, rol := range []string{"GERENTE", "OPERADOR", "SUPERVISOR", "GESTOR", ""} {
		cuerpo := map[string]any{
			"sub": "persona-1", "branchId": nil,
			"exp": time.Now().Add(time.Hour).Unix(),
		}
		if rol != "" {
			cuerpo["role"] = rol
		}
		_, err := conToken(t, firmar(t, cuerpo, "HS256"))
		if !errors.Is(err, ErrSinPermisoDeReparto) || errors.Is(err, ErrSinSesion) {
			t.Errorf("rol %q sin sucursal: %v, se esperaba ErrSinPermisoDeReparto y NO ErrSinSesion", rol, err)
		}
	}
	// LA PAREJA: un rol de Reparto sin sucursal y sin ver todo SÍ es ErrSinSesion (regla de la
	// sucursal, que no cambia).
	_, err := conToken(t, firmar(t, map[string]any{
		"sub": "persona-1", "role": "LOGISTICO", "branchId": nil,
		"exp": time.Now().Add(time.Hour).Unix(),
	}, "HS256"))
	if !errors.Is(err, ErrSinSesion) || errors.Is(err, ErrSinPermisoDeReparto) {
		t.Fatalf("LOGISTICO sin sucursal: %v, se esperaba ErrSinSesion", err)
	}
}
