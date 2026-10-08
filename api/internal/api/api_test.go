package api_test

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/api"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/store/sqlc"
)

// Las mismas pruebas del alcance, pero ENTERAS: por HTTP, con token de verdad y pasando
// por el router. Aquí se comprueba que la regla no se pierde en el montaje —que los
// middlewares están puestos y en el orden bueno—, que es donde se escapan estas cosas.

const secreto = "un-secreto-de-pruebas-de-al-menos-32-caracteres"

var (
	stg = uuid.MustParse("11111111-1111-1111-1111-111111111111")
	hol = uuid.MustParse("22222222-2222-2222-2222-222222222222")
	// La sucursal que ya no está: el token dura siete días y lleva dentro la que la
	// persona tenía al entrar.
	fantasma = uuid.MustParse("99999999-9999-9999-9999-999999999999")

	vehStg = uuid.MustParse("aaaaaaaa-0000-0000-0000-000000000001")
	vehHol = uuid.MustParse("bbbbbbbb-0000-0000-0000-000000000002")
)

// --------------------------------------------------------------------------- doble

type doble struct {
	sqlc.Querier
	vehiculos []sqlc.ListarVehiculosRow
	// Las rutas ABIERTAS de la flota, una por camión. Es lo que dice en qué anda cada
	// uno: `vehicles.status` no se mira (ver `db/queries/vehicles.sql`).
	rutasAbiertas []sqlc.RutasAbiertasDeLaFlotaRow
}

func (d *doble) ResolverSucursal(_ context.Context, id uuid.UUID) (sqlc.ResolverSucursalRow, error) {
	switch id {
	case stg:
		c := "STG"
		return sqlc.ResolverSucursalRow{ID: stg, Name: "Santiago", ExternalID: &c}, nil
	case hol:
		c := "HOL"
		return sqlc.ResolverSucursalRow{ID: hol, Name: "Holguín", ExternalID: &c}, nil
	}
	return sqlc.ResolverSucursalRow{}, pgx.ErrNoRows
}

// BuscarSucursalPorCodigo es por donde entra un token de Accesos de verdad (`STG`, `HOL`…).
// Sin él, un código que no es uuid reventaba el doble con un puntero nil y las pruebas del
// «código que Reparto no conoce» (`MOA`) no podían escribirse por HTTP.
func (d *doble) BuscarSucursalPorCodigo(_ context.Context, codigo *string) (sqlc.BuscarSucursalPorCodigoRow, error) {
	if codigo != nil {
		switch *codigo {
		case "STG":
			return sqlc.BuscarSucursalPorCodigoRow{ID: stg, Name: "Santiago", ExternalID: codigo}, nil
		case "HOL":
			return sqlc.BuscarSucursalPorCodigoRow{ID: hol, Name: "Holguín", ExternalID: codigo}, nil
		}
	}
	return sqlc.BuscarSucursalPorCodigoRow{}, pgx.ErrNoRows
}

func (d *doble) ListarVehiculos(_ context.Context, sucursal pgtype.UUID) ([]sqlc.ListarVehiculosRow, error) {
	var salida []sqlc.ListarVehiculosRow
	for _, v := range d.vehiculos {
		if !sucursal.Valid || !v.BranchID.Valid || v.BranchID.Bytes == sucursal.Bytes {
			salida = append(salida, v)
		}
	}
	return salida, nil
}

// La flota de este doble no lleva rutas: aquí se mide el ALCANCE, no en qué anda cada
// camión. Devuelve vacío y no `nil, error`: un `Querier` embebido sin implementar revienta
// con un 500 que no dice nada, y ése fue el 500 que salió al añadir esta consulta.
func (d *doble) RutasAbiertasDeLaFlota(_ context.Context, _ pgtype.UUID) ([]sqlc.RutasAbiertasDeLaFlotaRow, error) {
	return d.rutasAbiertas, nil
}

func (d *doble) ObtenerVehiculo(_ context.Context, arg sqlc.ObtenerVehiculoParams) (sqlc.ObtenerVehiculoRow, error) {
	for _, v := range d.vehiculos {
		if v.ID != arg.ID {
			continue
		}
		if !arg.Sucursal.Valid || !v.BranchID.Valid || v.BranchID.Bytes == arg.Sucursal.Bytes {
			return sqlc.ObtenerVehiculoRow{ID: v.ID, Name: v.Name, TipoNombre: v.TipoNombre, BranchID: v.BranchID}, nil
		}
	}
	return sqlc.ObtenerVehiculoRow{}, pgx.ErrNoRows
}

type fuente struct{ q *doble }

func (f fuente) Consultas() sqlc.Querier { return f.q }
func (f fuente) EnTx(_ context.Context, fn func(sqlc.Querier) error) error {
	return fn(f.q)
}

// --------------------------------------------------------------------------- montaje

func servidor(t *testing.T) http.Handler {
	t.Helper()
	return servidorCon(t, nil)
}

// servidorCon: el mismo montaje, con las rutas abiertas que se le digan. Existe para poder
// probar «en qué anda cada camión» sin tocar las otras veinte pruebas que usan `servidor`.
func servidorCon(t *testing.T, abiertas []sqlc.RutasAbiertasDeLaFlotaRow) http.Handler {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secreto)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	q := &doble{vehiculos: []sqlc.ListarVehiculosRow{
		{ID: vehStg, Name: "Camión de Santiago", TipoNombre: "truck", BranchID: pg(stg)},
		{ID: vehHol, Name: "Camión de Holguín", TipoNombre: "truck", BranchID: pg(hol)},
		{ID: uuid.New(), Name: "Camión compartido", TipoNombre: "van"},
	}, rutasAbiertas: abiertas}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	return api.NuevoServidor(cfg, reg,
		alcance.NuevaPorteria(fuente{q: q}, reg),
		auth.NuevoVerificador([]byte(secreto)),
		func(context.Context) error { return nil },
	).Rutas()
}

func pg(id uuid.UUID) pgtype.UUID { return pgtype.UUID{Bytes: [16]byte(id), Valid: true} }

// token firma un JWT HS256 como el que emite auth.
func token(t *testing.T, reclamos map[string]any) string {
	t.Helper()
	if _, hay := reclamos["exp"]; !hay {
		reclamos["exp"] = time.Now().Add(time.Hour).Unix()
	}
	cab := b64(t, map[string]any{"alg": "HS256", "typ": "JWT"})
	cuerpo := b64(t, reclamos)
	mac := hmac.New(sha256.New, []byte(secreto))
	mac.Write([]byte(cab + "." + cuerpo))
	return cab + "." + cuerpo + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func b64(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

func pedir(t *testing.T, h http.Handler, metodo, ruta, jwt string, cabeceras map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(metodo, ruta, nil)
	if jwt != "" {
		r.Header.Set("Authorization", "Bearer "+jwt)
	}
	for k, v := range cabeceras {
		r.Header.Set(k, v)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

// --------------------------------------------------------------------------- pruebas

func TestSinTokenEs401ConElMensajeDelContrato(t *testing.T) {
	w := pedir(t, servidor(t), http.MethodGet, "/api/vehicles", "", nil)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("código %d", w.Code)
	}
	if got := strings.TrimSpace(w.Body.String()); got != `{"error":"Unauthorized"}` {
		t.Fatalf("cuerpo %q", got)
	}
}

func TestTokenConFirmaCambiadaEs401(t *testing.T) {
	bueno := token(t, map[string]any{"sub": "p-1", "role": "LOGISTICO", "branchId": stg.String()})

	// SE CAMBIA UN BIT DE LA FIRMA DECODIFICADA, no un carácter del base64.
	//
	// Antes esta prueba sustituía el último carácter por "X" y fallaba ~1 de cada 16: el
	// último carácter de un base64url de 43 caracteres sólo codifica 4 bits, así que si el
	// original ya caía en el mismo grupo, la firma decodificada salía IDÉNTICA, el token
	// seguía valiendo y la respuesta era 200. Una prueba que pasa quince de cada dieciséis
	// veces es peor que no tenerla: se acaba ejecutando con `-count=1` y mirando a otro
	// lado. Cambiando un bit de los bytes de verdad, la firma es siempre otra.
	partes := strings.Split(bueno, ".")
	if len(partes) != 3 {
		t.Fatalf("el token no tiene tres partes: %q", bueno)
	}
	firma, err := base64.RawURLEncoding.DecodeString(partes[2])
	if err != nil || len(firma) == 0 {
		t.Fatalf("no se pudo decodificar la firma: %v", err)
	}
	firma[len(firma)-1] ^= 0x01
	roto := partes[0] + "." + partes[1] + "." + base64.RawURLEncoding.EncodeToString(firma)
	if roto == bueno {
		t.Fatal("la firma cambiada salió igual que la buena: la prueba no probaría nada")
	}
	w := pedir(t, servidor(t), http.MethodGet, "/api/vehicles", roto, nil)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("una firma cambiada tiene que ser 401, y fue %d", w.Code)
	}
}

// El fallo clásico del JWT: un token sin firmar que declara `alg: none`.
func TestTokenSinFirmaEs401(t *testing.T) {
	cab := b64(t, map[string]any{"alg": "none", "typ": "JWT"})
	cuerpo := b64(t, map[string]any{"sub": "p-1", "role": "SUPER ADMIN", "exp": time.Now().Add(time.Hour).Unix()})
	w := pedir(t, servidor(t), http.MethodGet, "/api/vehicles", cab+"."+cuerpo+".", nil)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("«alg: none» tiene que ser 401, y fue %d", w.Code)
	}
}

func TestTokenCaducadoEs401(t *testing.T) {
	jwt := token(t, map[string]any{"sub": "p-1", "role": "LOGISTICO", "branchId": stg.String(),
		"exp": time.Now().Add(-8 * 24 * time.Hour).Unix()})
	w := pedir(t, servidor(t), http.MethodGet, "/api/vehicles", jwt, nil)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("código %d", w.Code)
	}
}

// LA PRUEBA: por HTTP, un operador de Santiago no llega a los datos de Holguín ni
// pidiéndolo por cabecera.
func TestPorHttpUnOperadorNoLlegaAOtraSucursal(t *testing.T) {
	h := servidor(t)
	jwt := token(t, map[string]any{"sub": "p-1", "email": "stg@procovar.cu", "role": "LOGISTICO", "branchId": stg.String()})

	w := pedir(t, h, http.MethodGet, "/api/vehicles", jwt, map[string]string{"X-Sucursal-Id": hol.String()})
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if strings.Contains(w.Body.String(), "Holguín") {
		t.Fatalf("Santiago vio datos de Holguín: %s", w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "Santiago") {
		t.Fatalf("Santiago no vio ni lo suyo: %s", w.Body.String())
	}

	// Y por id directo, que es por donde se cuela quien prueba a mano.
	w = pedir(t, h, http.MethodGet, "/api/vehicles/"+vehHol.String(), jwt, nil)
	if w.Code != http.StatusNotFound {
		t.Fatalf("el camión de Holguín tenía que ser 404 para Santiago, y fue %d", w.Code)
	}
	if got := strings.TrimSpace(w.Body.String()); got != `{"error":"Not found"}` {
		t.Fatalf("el mensaje literal del contrato es «Not found»; salió %q", got)
	}
}

// El modo de fallo de producción, por HTTP: 200 con CERO filas y sin trazas. Para quien ve
// todas (SUPER ADMIN, DESARROLLADOR) una sucursal que ya no está sigue siendo «todas» con
// aviso; para cualquier otro rol es un 403 que nombra el código (ver la pareja de abajo).
func TestPorHttpUnaSucursalQueNoExisteNoDevuelveCero(t *testing.T) {
	h := servidor(t)
	jwt := token(t, map[string]any{"sub": "p-2", "email": "vieja@procovar.cu", "role": "SUPER ADMIN",
		"branchId": fantasma.String()})

	w := pedir(t, h, http.MethodGet, "/api/vehicles", jwt, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d", w.Code)
	}
	var lista []map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &lista); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	if len(lista) != 3 {
		t.Fatalf("una sucursal que ya no está acotó la lista a %d en vez de enseñarlas todas", len(lista))
	}
}

// LA PAREJA (08/10/2026): el token de un OPERADOR de una sucursal que Reparto no conoce
// —Accesos sabe de `MOA` y `PLS`, Reparto no— es un 403 CON EL CÓDIGO en el texto, no las
// ocho sucursales. Y que la cabecera no lo rescate ni lo agrande.
func TestPorHttpUnaSucursalQueRepartoNoConoceEsUn403QueLaNombra(t *testing.T) {
	h := servidor(t)
	jwt := token(t, map[string]any{"sub": "p-2", "email": "moa@procovar.cu", "role": "LOGISTICO",
		"branchId": "MOA"})

	for _, cab := range []map[string]string{nil, {"X-Sucursal-Id": hol.String()}, {"X-Sucursal-Id": "basura"}} {
		w := pedir(t, h, http.MethodGet, "/api/vehicles", jwt, cab)
		if w.Code != http.StatusForbidden {
			t.Fatalf("cabecera %v: tenía que ser 403 y fue %d: %s", cab, w.Code, w.Body.String())
		}
		if got := strings.TrimSpace(w.Body.String()); got !=
			`{"error":"tu sucursal MOA no está dada de alta en Reparto: pide en la oficina que la den de alta"}` {
			t.Fatalf("cabecera %v: el 403 tiene que nombrar el código: %s", cab, got)
		}
	}
}

// Sin sucursal y sin rol que lo ve todo, la cabecera no abre nada: antes `basura` caía en
// «no existe -> todas» y un id real le dejaba mirar esa sucursal.
func TestPorHttpSinSucursalLaCabeceraNoAbreNada(t *testing.T) {
	h := servidor(t)
	jwt := token(t, map[string]any{"sub": "p-2", "email": "sin@procovar.cu", "role": "LOGISTICO"})

	for _, cab := range []string{"basura", stg.String(), hol.String(), "STG"} {
		w := pedir(t, h, http.MethodGet, "/api/vehicles", jwt, map[string]string{"X-Sucursal-Id": cab})
		if w.Code != http.StatusForbidden {
			t.Fatalf("cabecera %q: tenía que ser 403 y fue %d: %s", cab, w.Code, w.Body.String())
		}
		if strings.Contains(w.Body.String(), "Santiago") || strings.Contains(w.Body.String(), "Holguín") {
			t.Fatalf("cabecera %q: salieron datos: %s", cab, w.Body.String())
		}
	}
}

func TestSuperAdminEligeSucursalPorCabecera(t *testing.T) {
	h := servidor(t)
	jwt := token(t, map[string]any{"sub": "p-3", "role": "SUPER ADMIN"}) // sin branchId

	w := pedir(t, h, http.MethodGet, "/api/vehicles", jwt, map[string]string{"X-Sucursal-Id": hol.String()})
	cuerpo := w.Body.String()
	if strings.Contains(cuerpo, "Santiago") {
		t.Fatalf("eligió Holguín y le salió Santiago: %s", cuerpo)
	}
	if !strings.Contains(cuerpo, "Holguín") || !strings.Contains(cuerpo, "compartido") {
		t.Fatalf("tenía que ver el de Holguín y el compartido: %s", cuerpo)
	}
}

// El rol se comprueba ANTES que nada en las rutas de administración.
func TestCrearSucursalExigeAdmin(t *testing.T) {
	jwt := token(t, map[string]any{"sub": "p-4", "role": "LOGISTICO", "branchId": stg.String()})
	w := pedir(t, servidor(t), http.MethodPost, "/api/branches", jwt, nil)
	if w.Code != http.StatusForbidden {
		t.Fatalf("código %d", w.Code)
	}
	if got := strings.TrimSpace(w.Body.String()); got != `{"error":"Admin access required"}` {
		t.Fatalf("mensaje %q", got)
	}
}

// /version y /health van SIN sesión: la APK consulta la versión antes de entrar y el
// desplegador sondea la salud sin token ninguno.
func TestVersionYSaludSinSesion(t *testing.T) {
	h := servidor(t)
	for _, ruta := range []string{"/version", "/api/version", "/health"} {
		w := pedir(t, h, http.MethodGet, ruta, "", nil)
		if w.Code != http.StatusOK {
			t.Fatalf("%s: código %d", ruta, w.Code)
		}
	}
	w := pedir(t, h, http.MethodGet, "/api/version", "", nil)
	if !strings.Contains(w.Body.String(), "v-pruebas") {
		t.Fatalf("la versión no sale: %s", w.Body.String())
	}
	if cc := w.Header().Get("Cache-Control"); !strings.Contains(cc, "no-store") {
		t.Fatalf("la versión no puede quedarse guardada en el navegador: %q", cc)
	}
}

// Los 404 y los 405 también salen con {"error": ...}: un cliente que espera JSON siempre
// y se encuentra texto plano no enseña el problema, enseña un fallo de parseo.
func TestRutaDesconocidaYMetodoNoPermitidoSalenEnJson(t *testing.T) {
	h := servidor(t)

	w := pedir(t, h, http.MethodGet, "/api/loquesea", "", nil)
	if w.Code != http.StatusNotFound || !strings.HasPrefix(w.Body.String(), `{"error"`) {
		t.Fatalf("404: %d %s", w.Code, w.Body.String())
	}

	jwt := token(t, map[string]any{"sub": "p-5", "role": "SUPER ADMIN"})
	w = pedir(t, h, http.MethodDelete, "/api/settings", jwt, nil)
	if w.Code != http.StatusMethodNotAllowed || !strings.HasPrefix(w.Body.String(), `{"error"`) {
		t.Fatalf("405: %d %s", w.Code, w.Body.String())
	}
	if allow := w.Header().Get("Allow"); !strings.Contains(allow, "PUT") {
		t.Fatalf("falta la cabecera Allow: %q", allow)
	}
}
