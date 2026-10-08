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

// ---------------------------------------------------------------------------
// QUIÉN ENTRA LO DECIDE AUTH: `entradas` (Jose, 08/10/2026: «Reparto no decide quién entra; eso
// lo maneja Auth»). Misma regla que `auth.Usuario.PuedeEntrarAReparto` en la API, atada por
// `docs/roles-de-reparto.casos.json`. Con el campo PRESENTE (aunque sea `[]`) decide sólo él;
// AUSENTE se cae a la lista de roles de transición.
// ---------------------------------------------------------------------------

func TestElSincronizadorDecidePorLaLlaveDeAuth(t *testing.T) {
	con := func(entradas any, rol string) error {
		rec := map[string]any{"role": rol}
		if entradas != nil {
			rec["entradas"] = entradas
		}
		_, err := conToken(t, tokenDeRol(t, rec))
		return err
	}
	// Con la llave entra QUIEN SEA.
	for _, rol := range []string{"GERENTE", "GESTOR", "INVENTADO", ""} {
		if err := con([]string{"delivery.entrar"}, rol); err != nil {
			t.Errorf("delivery.entrar + rol %q tenía que entrar: %v", rol, err)
		}
	}
	// Sin la llave NO entra nadie, tampoco los de la lista de ayer.
	for _, rol := range []string{"ADMINISTRADOR", "SUPER ADMIN", "DESARROLLADOR", "LOGISTICO", "admin"} {
		if err := con([]string{"pedido.entrar"}, rol); !errors.Is(err, ErrSinPermisoDeReparto) {
			t.Errorf("pedido.entrar + rol %q: %v, se esperaba ErrSinPermisoDeReparto", rol, err)
		}
	}
	// Vacío NO es ausente.
	if err := con([]string{}, "LOGISTICO"); !errors.Is(err, ErrSinPermisoDeReparto) {
		t.Errorf("entradas [] + LOGISTICO: %v, tenía que ser ErrSinPermisoDeReparto", err)
	}
	if err := con(nil, "LOGISTICO"); err != nil {
		t.Errorf("AUSENTE + LOGISTICO tenía que entrar por la caída: %v", err)
	}
	// Presente pero roto, y texto exacto.
	for nombre, v := range map[string]any{"un texto": "delivery.entrar", "mayúsculas": []string{"DELIVERY.ENTRAR"}} {
		if err := con(v, "LOGISTICO"); !errors.Is(err, ErrSinPermisoDeReparto) {
			t.Errorf("entradas %s: %v, tenía que ser ErrSinPermisoDeReparto", nombre, err)
		}
	}
}

// Con `entradas` el control sigue yendo ANTES que la regla de la sucursal: un GERENTE sin
// sucursal y sin la llave recibe 403 (a Accesos), NO el 401 que mata la sesión.
func TestSinLaLlaveElPermisoVaAntesQueLaSucursal(t *testing.T) {
	_, err := conToken(t, firmar(t, map[string]any{
		"sub": "p-1", "role": "GERENTE", "branchId": nil, "entradas": []string{"pedido.entrar"},
		"exp": time.Now().Add(time.Hour).Unix(),
	}, "HS256"))
	if !errors.Is(err, ErrSinPermisoDeReparto) || errors.Is(err, ErrSinSesion) {
		t.Fatalf("%v, se esperaba ErrSinPermisoDeReparto y NO ErrSinSesion", err)
	}
}

// `Exigir`: el mismo 403 con `entradas`, y ni el cuerpo ni el registro llevan el token.
func TestExigirPorEntradasContestaElMismo403SinFiltrarElToken(t *testing.T) {
	var registro bytes.Buffer
	anterior := slog.Default()
	slog.SetDefault(slog.New(slog.NewTextHandler(&registro, nil)))
	t.Cleanup(func() { slog.SetDefault(anterior) })

	llegó := 0
	h := Exigir(DeToken([]byte(secreto), nil), http.HandlerFunc(func(http.ResponseWriter, *http.Request) { llegó++ }))
	pedir := func(jwt string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(http.MethodPost, "/sync/aparato", nil)
		r.Header.Set("Authorization", "Bearer "+jwt)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}

	jwt := tokenDeRol(t, map[string]any{"role": "ADMINISTRADOR", "entradas": []string{"pedido.entrar"}})
	w := pedir(jwt)
	if llegó != 0 || w.Code != http.StatusForbidden || strings.TrimSpace(w.Body.String()) != cuerpoSinPermiso {
		t.Fatalf("ADMINISTRADOR sin la llave: llegó=%d %d %s", llegó, w.Code, w.Body.String())
	}
	for _, trozo := range append(strings.Split(jwt, "."), jwt) {
		if strings.Contains(registro.String(), trozo) || strings.Contains(w.Body.String(), trozo) {
			t.Errorf("el token se filtró (%.12s…)", trozo)
		}
	}
	// Y un GERENTE con la llave llega al manejador.
	w = pedir(tokenDeRol(t, map[string]any{"role": "GERENTE", "entradas": []string{"delivery.entrar"}}))
	if llegó != 1 || w.Code != http.StatusOK {
		t.Fatalf("GERENTE con la llave: llegó=%d %d %s", llegó, w.Code, w.Body.String())
	}
}

// LA CAÍDA POR ROLES ES DE TRANSICIÓN, y esta prueba la NOMBRA para que no se olvide: QUITAR
// `caidaPorRolesDeTransicion` (y `rolesQueEntranAReparto`) cuando caduquen los tokens anteriores
// al 08/10/2026 (cookie web 7 días -> 15/10/2026; access token de la APK, 15 minutos). Gemela de
// `TestLaCaidaPorRolesEsDeTransicion` de la API. No falla pasada la fecha a propósito: rompería la
// construcción de la imagen el día del despliegue.
func TestLaCaidaPorRolesEsDeTransicion(t *testing.T) {
	if !caidaPorRolesDeTransicion {
		t.Fatal("la caída por roles está apagada: si es a propósito (ya caducaron los tokens " +
			"anteriores al 08/10/2026), borra esta prueba y la lista; si no, enciéndela")
	}
	if time.Now().After(time.Date(2026, 10, 16, 0, 0, 0, 0, time.UTC)) {
		t.Log("YA PUEDE QUITARSE la caída por roles (caidaPorRolesDeTransicion): caducaron las " +
			"cookies web anteriores al 08/10/2026. Reparto debe decidir SOLO por `entradas`.")
	}
}
