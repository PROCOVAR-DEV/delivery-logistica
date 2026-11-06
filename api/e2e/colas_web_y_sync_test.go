// Package e2e prueba contra la API y el sincronizador DE VERDAD (los contenedores del portátil) que las dos colas se respetan:
// la del aparato —que sube por `/sync/subida` y el sync reenvía a la API— y la del navegador —que escribe directo a `/api/*` con
// el id que puso quien creó—. Se salta sola si no hay stack: `REPARTO_E2E=1 go test ./e2e` con `docker compose up -d postgres
// migraciones api sync` (docs/entorno-local.md) y `REPARTO_E2E_DSN` apuntando a la base `reparto`.
package e2e

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type stack struct {
	t         *testing.T
	api, sync string
	token     string
	sucursal  uuid.UUID
	db        *pgx.Conn
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func levantar(t *testing.T) *stack {
	t.Helper()
	if os.Getenv("REPARTO_E2E") == "" {
		t.Skip("sin REPARTO_E2E=1 no se prueba contra el stack local")
	}
	ctx := context.Background()
	db, err := pgx.Connect(ctx, env("REPARTO_E2E_DSN", "postgres://reparto:reparto@127.0.0.1:5433/reparto?sslmode=disable"))
	if err != nil {
		t.Fatalf("la base del stack local: %v", err)
	}
	t.Cleanup(func() { _ = db.Close(ctx) })
	s := &stack{t: t, api: env("REPARTO_E2E_API", "http://127.0.0.1:8080"), sync: env("REPARTO_E2E_SYNC", "http://127.0.0.1:8081"), db: db}
	if err := db.QueryRow(ctx, `INSERT INTO branches (name, lat, lng) VALUES ($1, 20, -75) RETURNING id`, "e2e-"+uuid.NewString()).Scan(&s.sucursal); err != nil {
		t.Fatal(err)
	}
	s.token = jwt(env("REPARTO_E2E_JWT_SECRET", "secreto-de-desarrollo-de-mas-de-32-caracteres"), map[string]any{
		"sub": "e2e-" + uuid.NewString(), "email": "e2e@procovar.cu", "role": "LOGISTICO", "branchId": s.sucursal.String(),
		"entradas": []string{"delivery.entrar"}, "exp": time.Now().Add(time.Hour).Unix(),
	})
	return s
}

func jwt(secreto string, reclamos map[string]any) string {
	b64 := func(v any) string { b, _ := json.Marshal(v); return base64.RawURLEncoding.EncodeToString(b) }
	cab, cuerpo := b64(map[string]any{"alg": "HS256", "typ": "JWT"}), b64(reclamos)
	mac := hmac.New(sha256.New, []byte(secreto))
	mac.Write([]byte(cab + "." + cuerpo))
	return cab + "." + cuerpo + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func (s *stack) llamar(base, metodo, ruta string, cuerpo any, cab map[string]string) (int, []byte) {
	s.t.Helper()
	var r io.Reader
	if cuerpo != nil {
		b, _ := json.Marshal(cuerpo)
		r = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(metodo, base+ruta, r)
	req.Header.Set("Authorization", "Bearer "+s.token)
	req.Header.Set("Content-Type", "application/json")
	for k, v := range cab {
		req.Header.Set(k, v)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		s.t.Fatalf("%s %s: %v", metodo, ruta, err)
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(res.Body)
	return res.StatusCode, b
}

// web es lo que hace el navegador: directo a la API.
func (s *stack) web(metodo, ruta string, cuerpo any) (int, []byte) {
	return s.llamar(s.api, metodo, "/api"+ruta, cuerpo, nil)
}

// aparato da de alta un aparato en el sync y devuelve su id.
func (s *stack) aparato() string {
	s.t.Helper()
	code, b := s.llamar(s.sync, "POST", "/sync/aparato", map[string]any{"nombre": "e2e"}, map[string]string{"X-Aparato-Id": uuid.NewString()})
	var a struct {
		Aparato string `json:"aparato"`
	}
	if code != 200 && code != 201 || json.Unmarshal(b, &a) != nil || a.Aparato == "" {
		s.t.Fatalf("alta del aparato: %d %s", code, b)
	}
	return a.Aparato
}

type apunte struct {
	Clave       string `json:"clave"`
	Hecho       string `json:"hecho"`
	Metodo      string `json:"metodo"`
	Ruta        string `json:"ruta"`
	Cuerpo      any    `json:"cuerpo,omitempty"`
	Provisional string `json:"provisional,omitempty"`
}

type resultado struct {
	Clave  string `json:"clave"`
	Estado string `json:"estado"`
	ID     string `json:"id"`
	Motivo string `json:"motivo"`
}

// subir es lo que hace la cola del aparato: `/sync/subida` con sus apuntes EN ORDEN.
func (s *stack) subir(aparato string, apuntes ...apunte) []resultado {
	s.t.Helper()
	pend := int32(0)
	code, b := s.llamar(s.sync, "POST", "/sync/subida", map[string]any{"aparato": aparato, "pendientes": pend, "apuntes": apuntes}, nil)
	var r struct {
		Resultados []resultado `json:"resultados"`
	}
	if code != 200 || json.Unmarshal(b, &r) != nil {
		s.t.Fatalf("subida: %d %s", code, b)
	}
	return r.Resultados
}

func nuevo() string { id, _ := uuid.NewV7(); return id.String() }

func clave() string { return "01E2E" + uuid.NewString()[:12] }

func ahora() string { return time.Now().UTC().Format(time.RFC3339Nano) }

func (s *stack) cuantos(tabla, id string) int {
	s.t.Helper()
	var n int
	if err := s.db.QueryRow(context.Background(), fmt.Sprintf(`SELECT count(*) FROM %s WHERE id = $1`, tabla), id).Scan(&n); err != nil {
		s.t.Fatal(err)
	}
	return n
}

// 1 · El mismo alta por las DOS colas: gana uno, el otro recibe lo que ya estaba, y en la base hay UNA fila.
func TestElMismoAltaPorLaColaDelAparatoYPorLaWebNoDuplica(t *testing.T) {
	s := levantar(t)
	ap := s.aparato()
	tipo := nuevo()
	cuerpo := map[string]any{"id": tipo, "nombre": "Furgón e2e", "costoKmUsd": 0.5}

	// el aparato sube su alta (id definitivo, `provisional` = el mismo id)…
	r := s.subir(ap, apunte{Clave: clave(), Hecho: ahora(), Metodo: "POST", Ruta: "/vehicle-types", Cuerpo: cuerpo, Provisional: tipo})
	if len(r) != 1 || r[0].Estado != "aplicado" || r[0].ID != tipo {
		t.Fatalf("la subida del aparato: %+v", r)
	}
	// …y la web, que no se enteró, manda el MISMO alta directo (su reintento): le devuelve lo que ya había
	if code, b := s.web("POST", "/vehicle-types", cuerpo); code != 201 && code != 200 {
		t.Fatalf("la web con el mismo id: %d %s", code, b)
	}
	// …y el aparato lo reintenta con OTRA clave (una cola reconstruida): tampoco duplica
	r = s.subir(ap, apunte{Clave: clave(), Hecho: ahora(), Metodo: "POST", Ruta: "/vehicle-types", Cuerpo: cuerpo, Provisional: tipo})
	if len(r) != 1 || r[0].Estado == "rechazado" {
		t.Fatalf("el reintento del aparato con otra clave no es un rechazo: %+v", r)
	}
	if n := s.cuantos("vehicle_types", tipo); n != 1 {
		t.Fatalf("hay %d filas con ese id", n)
	}
}

// 2 · El orden: el aparato sube [alta del tipo, alta del camión de ese tipo] y la web hace lo mismo con otras ids. Cada cola respeta el
// suyo y no se pisan.
func TestCadaColaRespetaSuOrdenYNoSePisanEntreSi(t *testing.T) {
	s := levantar(t)
	ap := s.aparato()
	tipoA, camionA := nuevo(), nuevo()
	tipoW, camionW := nuevo(), nuevo()

	var wg sync.WaitGroup
	wg.Add(2)
	var rA []resultado
	go func() { // el aparato
		defer wg.Done()
		rA = s.subir(ap,
			apunte{Clave: clave(), Hecho: ahora(), Metodo: "POST", Ruta: "/vehicle-types", Cuerpo: map[string]any{"id": tipoA, "nombre": "Tipo A e2e"}, Provisional: tipoA},
			apunte{Clave: clave(), Hecho: ahora(), Metodo: "POST", Ruta: "/vehicles", Cuerpo: map[string]any{"id": camionA, "name": "Camión A", "type": "Tipo A e2e"}, Provisional: camionA},
		)
	}()
	go func() { // la web, de una en una y en orden (lo que hace su cola)
		defer wg.Done()
		if code, b := s.web("POST", "/vehicle-types", map[string]any{"id": tipoW, "nombre": "Tipo W e2e"}); code != 201 {
			t.Errorf("web tipo: %d %s", code, b)
			return
		}
		if code, b := s.web("POST", "/vehicles", map[string]any{"id": camionW, "name": "Camión W", "type": "Tipo W e2e"}); code != 201 {
			t.Errorf("web camión: %d %s", code, b)
		}
	}()
	wg.Wait()

	if len(rA) != 2 || rA[0].Estado != "aplicado" || rA[1].Estado != "aplicado" || rA[0].ID != tipoA || rA[1].ID != camionA {
		t.Fatalf("la cola del aparato: %+v", rA)
	}
	for tabla, id := range map[string]string{"vehicle_types": tipoA, "vehicles": camionA} {
		if s.cuantos(tabla, id) != 1 {
			t.Fatalf("%s %s: no hay exactamente una fila", tabla, id)
		}
	}
	if s.cuantos("vehicle_types", tipoW) != 1 || s.cuantos("vehicles", camionW) != 1 {
		t.Fatalf("lo de la web no quedó")
	}
	// todo nació con el id de quien lo creó, y ese id es un v7
	for _, id := range []string{tipoA, camionA, tipoW, camionW} {
		if u, _ := uuid.Parse(id); u.Version() != 7 {
			t.Fatalf("%s no es v7", id)
		}
	}
}

// 3 · Un id que no es v7 (un `local-…` de una app vieja, un v4) se rechaza en la API y el sync lo deja como rechazado con su motivo,
// sin bloquear a los apuntes que van detrás en la cola.
func TestUnIdMalNoBloqueaLaColaDelAparato(t *testing.T) {
	s := levantar(t)
	ap := s.aparato()
	bueno := nuevo()
	r := s.subir(ap,
		apunte{Clave: clave(), Hecho: ahora(), Metodo: "POST", Ruta: "/distribuidores", Cuerpo: map[string]any{"id": uuid.NewString(), "nombre": "Mal e2e"}, Provisional: "local-abc123"},
		apunte{Clave: clave(), Hecho: ahora(), Metodo: "POST", Ruta: "/distribuidores", Cuerpo: map[string]any{"id": bueno, "nombre": "Bien e2e"}, Provisional: bueno},
	)
	if len(r) != 2 || r[0].Estado != "rechazado" || r[0].Motivo == "" {
		t.Fatalf("el id v4 tenía que rechazarse con motivo: %+v", r)
	}
	if r[1].Estado != "aplicado" || r[1].ID != bueno || s.cuantos("distribuidores", bueno) != 1 {
		t.Fatalf("el de detrás tenía que entrar: %+v", r)
	}
}

// ---------------------------------------------------------------------------
// RUTAS — el caso que originó todo esto (códigos repetidos, 03/11/2026)
// ---------------------------------------------------------------------------

const alfabeto = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

// codigoDe es la regla del código de ruta, escrita OTRA VEZ aquí a propósito (no se importa la del servidor): fecha UTC del id + 30 bits.
func codigoDe(id string) string {
	u := uuid.MustParse(id)
	ms := int64(u[0])<<40 | int64(u[1])<<32 | int64(u[2])<<24 | int64(u[3])<<16 | int64(u[4])<<8 | int64(u[5])
	n := (uint32(u[12])<<24 | uint32(u[13])<<16 | uint32(u[14])<<8 | uint32(u[15])) & (1<<30 - 1)
	var c [6]byte
	for i := 5; i >= 0; i-- {
		c[i] = alfabeto[n&31]
		n >>= 5
	}
	return time.UnixMilli(ms).UTC().Format("060102") + "-" + string(c[:])
}

// siembraDeRuta deja un camión y n pedidos que entran en una ruta (facturados, con domicilio cobrado y coordenadas).
func (s *stack) siembraDeRuta(n int) (camion string, pedidos []string) {
	s.t.Helper()
	camion = s.nuevoCamion()
	return camion, s.siembraDePedidos(n)
}

// nuevoCamion deja un camión (con su tipo) en la sucursal de la prueba.
func (s *stack) nuevoCamion() string {
	s.t.Helper()
	ctx := context.Background()
	var tipo uuid.UUID
	if err := s.db.QueryRow(ctx, `INSERT INTO vehicle_types (nombre, branch_id) VALUES ($1, $2) RETURNING id`, "tipo-"+uuid.NewString(), s.sucursal).Scan(&tipo); err != nil {
		s.t.Fatal(err)
	}
	var v uuid.UUID
	if err := s.db.QueryRow(ctx, `INSERT INTO vehicles (name, vehicle_type_id, branch_id) VALUES ($1, $2, $3) RETURNING id`, "camion-"+uuid.NewString()[:8], tipo, s.sucursal).Scan(&v); err != nil {
		s.t.Fatal(err)
	}
	return v.String()
}

// siembraDePedidos deja n pedidos que entran en una ruta (facturados, con domicilio cobrado y coordenadas).
func (s *stack) siembraDePedidos(n int) (pedidos []string) {
	s.t.Helper()
	ctx := context.Background()
	for i := 0; i < n; i++ {
		var p uuid.UUID
		if err := s.db.QueryRow(ctx, `
INSERT INTO orders (customer_name, address, weight, branch_id, source, external_id, end_lat, end_lng, requiere_domicilio,
                    factura_estado, factura_domicilio, pedido_costo, trip_leg)
VALUES ($1, 'calle 1', 10, $2, 'pedido'::procedencia, $3, 20.0, -75.0, true, 'igual'::factura_estado, 5, 10, 'outbound'::trip_leg)
RETURNING id`, fmt.Sprintf("cliente-%d", i), s.sucursal, "ext-"+uuid.NewString()).Scan(&p); err != nil {
			s.t.Fatal(err)
		}
		pedidos = append(pedidos, p.String())
	}
	return pedidos
}

func (s *stack) cuerpoDeRuta(id, camion string, pedidos []string) map[string]any {
	return map[string]any{"id": id, "name": "Ruta e2e", "vehicleId": camion, "originLat": 20.0, "originLng": -75.0, "orderIds": pedidos, "optimizar": true}
}

func (s *stack) rutaDe(cuerpo []byte) (id, codigo string) {
	s.t.Helper()
	var r struct {
		ID        string `json:"id"`
		RouteCode string `json:"routeCode"`
	}
	if json.Unmarshal(cuerpo, &r) != nil || r.ID == "" {
		s.t.Fatalf("respuesta de ruta ilegible: %s", cuerpo)
	}
	return r.ID, r.RouteCode
}

func (s *stack) pedidosEnLaRuta(ruta string) int {
	s.t.Helper()
	var n int
	if err := s.db.QueryRow(context.Background(), `SELECT count(*) FROM orders WHERE route_id = $1`, ruta).Scan(&n); err != nil {
		s.t.Fatal(err)
	}
	return n
}

// 4 · La ruta armada sin señal: el aparato la sube por su cola (id y código suyos) y luego la web manda el MISMO alta (su reintento).
// Una sola ruta, el código que sale del id, y los pedidos enganchados una sola vez. El cierre que viaja detrás en la misma cola
// va al mismo id, sin traducir nada.
func TestLaRutaDelAparatoYElReintentoDeLaWebSonUnaSola(t *testing.T) {
	s := levantar(t)
	ap := s.aparato()
	camion, pedidos := s.siembraDeRuta(2)
	ruta := nuevo()
	cuerpo := s.cuerpoDeRuta(ruta, camion, pedidos)

	r := s.subir(ap,
		apunte{Clave: clave(), Hecho: ahora(), Metodo: "POST", Ruta: "/routes", Cuerpo: cuerpo, Provisional: ruta},
		apunte{Clave: clave(), Hecho: ahora(), Metodo: "POST", Ruta: "/routes/" + ruta + "/results",
			Cuerpo: map[string]any{"resultados": []map[string]any{{"orderId": pedidos[0], "resultado": "entregado"}}}},
	)
	if len(r) != 2 || r[0].Estado != "aplicado" || r[0].ID != ruta {
		t.Fatalf("el alta de la ruta por la cola del aparato: %+v", r)
	}
	if r[1].Estado != "aplicado" {
		t.Fatalf("el cierre iba detrás con el MISMO id y tenía que aplicarse: %+v", r[1])
	}

	code, b := s.web("POST", "/routes", cuerpo) // el reintento de la web, con el mismo id
	if code != 200 && code != 201 {
		t.Fatalf("la web con el mismo id: %d %s", code, b)
	}
	id, codigo := s.rutaDe(b)
	if id != ruta || codigo != codigoDe(ruta) {
		t.Fatalf("id=%s código=%s, esperaba %s / %s", id, codigo, ruta, codigoDe(ruta))
	}
	if s.cuantos("routes", ruta) != 1 || s.pedidosEnLaRuta(ruta) != 2 {
		t.Fatalf("tenía que haber UNA ruta con sus 2 pedidos enganchados una vez")
	}
	if ok, _ := regexpFormato(codigo); !ok {
		t.Fatalf("el código %q no es AAMMDD-XXXXXX", codigo)
	}
}

// 5 · El choque de verdad: una ruta ya tiene el código que le saldría a la nueva. La nueva CONSERVA su id y recibe otro código libre;
// nunca dos rutas con el mismo código.
func TestSiElCodigoChocaLaRutaConservaSuIdYRecibeOtro(t *testing.T) {
	s := levantar(t)
	ap := s.aparato()
	camion, pedidos := s.siembraDeRuta(1)
	ruta := nuevo()
	ocupado := codigoDe(ruta)
	if _, err := s.db.Exec(context.Background(), `INSERT INTO routes (branch_id, status, name, route_code) VALUES ($1, 'planned', 'ocupa el codigo', $2)`, s.sucursal, ocupado); err != nil {
		t.Fatal(err)
	}

	r := s.subir(ap, apunte{Clave: clave(), Hecho: ahora(), Metodo: "POST", Ruta: "/routes", Cuerpo: s.cuerpoDeRuta(ruta, camion, pedidos), Provisional: ruta})
	if len(r) != 1 || r[0].Estado != "aplicado" || r[0].ID != ruta {
		t.Fatalf("la ruta con el código ocupado tenía que entrar con SU id: %+v", r)
	}
	var codigo string
	if err := s.db.QueryRow(context.Background(), `SELECT route_code FROM routes WHERE id = $1`, ruta).Scan(&codigo); err != nil {
		t.Fatal(err)
	}
	if codigo == "" || codigo == ocupado {
		t.Fatalf("tenía que recibir OTRO código y tiene %q (ocupado %q)", codigo, ocupado)
	}
	var cuantas int
	if err := s.db.QueryRow(context.Background(), `SELECT count(*) FROM routes WHERE route_code = $1`, ocupado).Scan(&cuantas); err != nil || cuantas != 1 {
		t.Fatalf("el código ocupado lo tiene %d rutas (err %v)", cuantas, err)
	}
}

var reFormato = regexp.MustCompile(`^[0-9]{6}-[0-9A-HJKMNP-TV-Z]{6}$`)

func regexpFormato(c string) (bool, error) { return reFormato.MatchString(c), nil }

// ---------------------------------------------------------------------------
// EL DISTRIBUIDOR TRABAJA POR ENLACE, SIN CUENTA (04/11/2026) — contra la API y el sync reales
// ---------------------------------------------------------------------------

// como devuelve el mismo stack pero hablando con OTRO token.
func (s *stack) como(token string) *stack {
	otro := *s
	otro.token = token
	return &otro
}

// sinSesion llama sin ningún token (lo que hace el teléfono al reclamar un enlace).
func (s *stack) sinSesion(metodo, ruta string, cuerpo any) (int, []byte) {
	s.t.Helper()
	var r io.Reader
	if cuerpo != nil {
		b, _ := json.Marshal(cuerpo)
		r = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(metodo, s.api+"/api"+ruta, r)
	req.Header.Set("Content-Type", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		s.t.Fatal(err)
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(res.Body)
	return res.StatusCode, b
}

func (s *stack) distribuidor(nombre string) uuid.UUID {
	s.t.Helper()
	var id uuid.UUID
	if err := s.db.QueryRow(context.Background(), `INSERT INTO distribuidores (branch_id, nombre) VALUES ($1, $2) RETURNING id`, s.sucursal, nombre).Scan(&id); err != nil {
		s.t.Fatal(err)
	}
	return id
}

// rutaConDistribuidor arma una ruta (la arma el logístico) con ese distribuidor.
func (s *stack) rutaConDistribuidor(d uuid.UUID) (ruta string, camion string, pedidos []string) {
	s.t.Helper()
	camion, pedidos = s.siembraDeRuta(2)
	ruta = nuevo()
	cuerpo := s.cuerpoDeRuta(ruta, camion, pedidos)
	cuerpo["distribuidorId"] = d.String()
	if code, b := s.web("POST", "/routes", cuerpo); code != 201 && code != 200 {
		s.t.Fatalf("armar la ruta: %d %s", code, b)
	}
	return ruta, camion, pedidos
}

// rutaConDistribuidorEnCamion arma otra ruta de ese distribuidor con un camión que ya existe (el teléfono acumula rutas del MISMO camión).
func (s *stack) rutaConDistribuidorEnCamion(d uuid.UUID, camion string) (ruta string, pedidos []string) {
	s.t.Helper()
	pedidos = s.siembraDePedidos(2)
	ruta = nuevo()
	cuerpo := s.cuerpoDeRuta(ruta, camion, pedidos)
	cuerpo["distribuidorId"] = d.String()
	if code, b := s.web("POST", "/routes", cuerpo); code != 201 && code != 200 {
		s.t.Fatalf("armar la ruta: %d %s", code, b)
	}
	return ruta, pedidos
}

// enlace pide el enlace de la ruta (como la oficina) y devuelve su token.
func (s *stack) enlace(ruta string, renovar bool) string {
	s.t.Helper()
	code, b := s.web("POST", "/routes/"+ruta+"/enlace", map[string]any{"renovar": renovar})
	var e struct{ Token, URL string }
	if (code != 200 && code != 201) || json.Unmarshal(b, &e) != nil || e.Token == "" || !strings.Contains(e.URL, "/r/"+e.Token) {
		s.t.Fatalf("enlace de la ruta: %d %s", code, b)
	}
	return e.Token
}

type telefono struct {
	id      string
	secreto string
	acceso  string
}

// reclama es lo que hace el teléfono al abrir el enlace: sin token de nadie, con su id y (si ya lo conoce) su secreto.
func (s *stack) reclama(tel *telefono, token string) (int, []byte) {
	s.t.Helper()
	cuerpo := map[string]any{"token": token, "dispositivoId": tel.id, "nombre": "Samsung e2e"}
	if tel.secreto != "" {
		cuerpo["secreto"] = tel.secreto
	}
	code, b := s.sinSesion("POST", "/d/reclamar", cuerpo)
	if code == 200 {
		var r struct{ Acceso, Secreto string }
		_ = json.Unmarshal(b, &r)
		tel.acceso = r.Acceso
		if r.Secreto != "" {
			tel.secreto = r.Secreto
		}
	}
	return code, b
}

func (s *stack) nuevoTelefono() *telefono { return &telefono{id: nuevo()} }

func idsDe(t *testing.T, cuerpo []byte, ruta ...string) []string {
	t.Helper()
	var x any
	if err := json.Unmarshal(cuerpo, &x); err != nil {
		t.Fatalf("respuesta ilegible: %s", cuerpo)
	}
	for _, k := range ruta {
		m, _ := x.(map[string]any)
		x = m[k]
	}
	var ids []string
	if l, ok := x.([]any); ok {
		for _, e := range l {
			switch v := e.(type) {
			case string:
				ids = append(ids, v)
			case map[string]any:
				if id, ok := v["id"].(string); ok {
					ids = append(ids, id)
				}
			}
		}
	}
	return ids
}

func contiene(lista []string, quien ...string) bool {
	m := map[string]bool{}
	for _, x := range lista {
		m[x] = true
	}
	for _, q := range quien {
		if m[q] {
			return true
		}
	}
	return false
}

func TestElTelefonoSoloVeYTocaLasRutasQueReclamo(t *testing.T) {
	s := levantar(t)
	d1, d2 := s.distribuidor("Uno e2e"), s.distribuidor("Dos e2e")
	rutaA, camionA, pedidosA := s.rutaConDistribuidor(d1)
	rutaB, _, pedidosB := s.rutaConDistribuidor(d2)
	rutaC, pedidosC := s.rutaConDistribuidorEnCamion(d1, camionA)

	// el enlace es de la oficina: el mismo enlace se devuelve mientras nadie lo suelta
	tokenA := s.enlace(rutaA, false)
	if s.enlace(rutaA, false) != tokenA {
		t.Fatalf("pedir el enlace dos veces tenía que dar el mismo")
	}
	tokenB, tokenC := s.enlace(rutaB, false), s.enlace(rutaC, false)

	// SIN CUENTA: el teléfono reclama el enlace de la ruta A y trabaja con lo que recibe
	tel := s.nuevoTelefono()
	if code, b := s.reclama(tel, tokenA); code != 200 || tel.acceso == "" || tel.secreto == "" {
		t.Fatalf("reclamar: %d %s", code, b)
	}
	dist := s.como(tel.acceso)

	code, b := dist.web("GET", "/routes", nil)
	var lista []map[string]any
	_ = json.Unmarshal(b, &lista)
	if code != 200 || len(lista) != 1 || lista[0]["id"] != rutaA {
		t.Fatalf("tenía que ver SOLO la ruta que reclamó: %d %s", code, b)
	}
	// las demás son un 404: ni se le dice que existen
	for _, otra := range []string{rutaB, rutaC} {
		if code, _ := dist.web("GET", "/routes/"+otra, nil); code != 404 {
			t.Fatalf("una ruta que no reclamó: %d, tenía que ser 404", code)
		}
	}
	if code, _ := dist.web("POST", "/routes/"+rutaB+"/results", map[string]any{"resultados": []map[string]any{{"orderId": pedidosB[0], "resultado": "entregado"}}}); code != 404 {
		t.Fatalf("cerrar una ruta ajena: %d, tenía que ser 404", code)
	}
	// ACUMULA: reclama una segunda ruta con el mismo teléfono (con su secreto) y ahora ve las dos
	if code, b := s.reclama(tel, tokenC); code != 200 {
		t.Fatalf("segunda ruta: %d %s", code, b)
	}
	dist = s.como(tel.acceso)
	_, b = dist.web("GET", "/routes", nil)
	lista = nil
	_ = json.Unmarshal(b, &lista)
	if len(lista) != 2 {
		t.Fatalf("tenía que ver sus DOS rutas: %s", b)
	}
	// todo lo que no es suyo, 403 con su marca
	for _, c := range []struct{ metodo, ruta string }{{"GET", "/orders"}, {"GET", "/vehicles"}, {"GET", "/customers"}, {"POST", "/routes"}, {"DELETE", "/routes/" + rutaA}, {"POST", "/routes/" + rutaA + "/enlace"}} {
		code, b := dist.web(c.metodo, c.ruta, nil)
		if code != 403 || !strings.Contains(string(b), "no_es_para_el_distribuidor") {
			t.Errorf("%s %s: %d %s, tenía que ser 403 con su marca", c.metodo, c.ruta, code, b)
		}
	}
	// en SU ruta: inicia y marca, pero no renombra ni cambia de camión
	if code, b := dist.web("PATCH", "/routes/"+rutaA, map[string]any{"name": "me la quedo"}); code != 403 {
		t.Errorf("renombrar: %d %s", code, b)
	}
	if code, b := dist.web("PATCH", "/routes/"+rutaA, map[string]any{"status": "in_progress"}); code != 200 {
		t.Errorf("iniciar: %d %s", code, b)
	}
	if code, b := dist.web("POST", "/routes/"+rutaA+"/results", map[string]any{"resultados": []map[string]any{{"orderId": pedidosA[0], "resultado": "entregado"}}}); code != 200 {
		t.Errorf("marcar: %d %s", code, b)
	}
	// su bajada: solo lo de sus dos rutas, y nada de clientes ni catálogo ni tablero
	code, b = dist.web("GET", "/sync/cambios", nil)
	if code != 200 {
		t.Fatalf("cambios: %d %s", code, b)
	}
	pedidos := idsDe(t, b, "cambios", "orders", "puestos")
	if len(pedidos) != 4 || contiene(pedidos, pedidosB...) || !contiene(pedidos, pedidosA...) || !contiene(pedidos, pedidosC...) {
		t.Fatalf("la bajada de pedidos: %v", pedidos)
	}
	if rs := idsDe(t, b, "cambios", "routes", "puestos"); len(rs) != 2 || contiene(rs, rutaB) {
		t.Fatalf("la bajada de rutas: %v", rs)
	}
	if vs := idsDe(t, b, "cambios", "vehicles", "puestos"); !contiene(vs, camionA) || len(vs) != 1 {
		t.Fatalf("la bajada de vehículos: %v", vs)
	}
	for _, k := range []string{"customers", "products", "boardColumns", "boardPlacements", "vehicle_types"} {
		if n := len(idsDe(t, b, "cambios", k, "puestos")); n != 0 {
			t.Errorf("a un distribuidor no se le baja %q (%d filas)", k, n)
		}
	}
	code, b = dist.web("GET", "/sync/cuadre", nil)
	if ps := idsDe(t, b, "colecciones", "orders"); code != 200 || len(ps) != 4 || contiene(ps, pedidosB...) {
		t.Fatalf("el cuadre de pedidos: %d %v", code, ps)
	}
	// el sync: da de alta su aparato y sube, pero no ve el panel
	if code, _ := dist.llamar(dist.sync, "GET", "/sync/estado", nil, nil); code != 403 {
		t.Errorf("/sync/estado: %d, tenía que ser 403", code)
	}
	if code, _ := dist.llamar(dist.sync, "POST", "/sync/aparato", map[string]any{"nombre": "movil e2e"}, map[string]string{"X-Aparato-Id": uuid.NewString()}); code != 200 && code != 201 {
		t.Errorf("alta del aparato: %d", code)
	}

	// UNA RUTA, UN TELÉFONO: otro teléfono con el mismo enlace recibe 403 y no ve nada
	otro := s.nuevoTelefono()
	if code, b := s.reclama(otro, tokenA); code != 403 || !strings.Contains(string(b), "ruta_de_otro_dispositivo") {
		t.Errorf("otro teléfono con el enlace reclamado: %d %s", code, b)
	}
	// el mismo teléfono puede volver a abrir su enlace (idempotente) y se le da un acceso nuevo
	if code, _ := s.reclama(tel, tokenA); code != 200 {
		t.Errorf("reabrir su propio enlace: %d", code)
	}
	// un teléfono conocido con otro secreto no entra
	malo := &telefono{id: tel.id, secreto: "no-es-el-secreto"}
	if code, _ := s.reclama(malo, tokenB); code != 401 {
		t.Errorf("secreto incorrecto: %d, tenía que ser 401", code)
	}
	if code, _ := s.sinSesion("POST", "/d/renovar", map[string]any{"dispositivoId": tel.id, "secreto": "no-es-el-secreto"}); code != 401 {
		t.Errorf("renovar con secreto incorrecto: %d", code)
	}
	if code, b := s.sinSesion("POST", "/d/renovar", map[string]any{"dispositivoId": tel.id, "secreto": tel.secreto}); code != 200 || !strings.Contains(string(b), "acceso") {
		t.Errorf("renovar: %d %s", code, b)
	}
	// un enlace que no existe, o un token cualquiera
	if code, _ := s.reclama(s.nuevoTelefono(), "token-que-no-existe"); code != 404 {
		t.Errorf("enlace inexistente: %d", code)
	}
	// SOLTAR LA RUTA (la oficina): se revoca, el teléfono la pierde y se puede mandar a otro
	nuevoToken := s.enlace(rutaC, true)
	if nuevoToken == tokenC {
		t.Fatalf("renovar tenía que dar un token nuevo")
	}
	if code, b := s.reclama(s.nuevoTelefono(), tokenC); code != 410 {
		t.Errorf("el enlace viejo: %d %s, tenía que ser 410", code, b)
	}
	_, b = s.como(tel.acceso).web("GET", "/routes", nil)
	lista = nil
	_ = json.Unmarshal(b, &lista)
	if len(lista) != 1 || lista[0]["id"] != rutaA {
		t.Errorf("tras soltar la ruta C el teléfono tenía que ver solo la A: %s", b)
	}
	// DAR DE BAJA EL TELÉFONO corta su acceso al instante, aunque el token no haya caducado
	if _, err := s.db.Exec(context.Background(), `UPDATE dispositivos_distribuidor SET activo = false WHERE id = $1`, tel.id); err != nil {
		t.Fatal(err)
	}
	if code, b := s.como(tel.acceso).web("GET", "/routes", nil); code != 403 {
		t.Errorf("teléfono dado de baja: %d %s, tenía que ser 403", code, b)
	}
	// un token con el rol pero sin dispositivo (o con uno que no existe) no ve nada
	falso := s.como(jwt(env("REPARTO_E2E_JWT_SECRET", "secreto-de-desarrollo-de-mas-de-32-caracteres"), map[string]any{
		"sub": "disp-x", "role": "DISTRIBUIDOR", "roles": []string{"DISTRIBUIDOR"}, "branchId": s.sucursal.String(),
		"entradas": []string{"delivery.entrar"}, "dispositivo": nuevo(), "exp": time.Now().Add(time.Hour).Unix(),
	}))
	if code, _ := falso.web("GET", "/routes", nil); code != 403 {
		t.Errorf("dispositivo inexistente: %d", code)
	}
	// y el logístico sigue viendo todas
	_, b = s.web("GET", "/routes", nil)
	var todas []map[string]any
	_ = json.Unmarshal(b, &todas)
	if len(todas) < 3 {
		t.Errorf("el logístico tenía que seguir viendo las rutas de todos: %d", len(todas))
	}
	// el estado del enlace, para la oficina
	if code, b := s.web("GET", "/routes/"+rutaA+"/enlace", nil); code != 200 || !strings.Contains(string(b), "reclamado") {
		t.Errorf("estado del enlace: %d %s", code, b)
	}
}

// EL GPS: lo manda el teléfono, lo ve la oficina, y el distribuidor no ve NADA de ello.
func TestElGpsLoVeLaOficinaYNoElDistribuidor(t *testing.T) {
	s := levantar(t)
	d1, d2 := s.distribuidor("Gps Uno"), s.distribuidor("Gps Dos")
	rutaA, camionA, pedidosA := s.rutaConDistribuidor(d1)
	rutaB, _, _ := s.rutaConDistribuidor(d2)
	tel := s.nuevoTelefono()
	if code, b := s.reclama(tel, s.enlace(rutaA, false)); code != 200 {
		t.Fatalf("reclamar: %d %s", code, b)
	}
	dist := s.como(tel.acceso)

	hace := func(d time.Duration) string { return time.Now().UTC().Add(-d).Format(time.RFC3339Nano) }
	punto := func(id string, rutas []string, lat, lng float64, hora string, evento string) map[string]any {
		p := map[string]any{"id": id, "rutaIds": rutas, "lat": lat, "lng": lng, "hora": hora, "precision": 8.5, "velocidad": 3.2, "rumbo": 90.0}
		if evento != "" {
			p["evento"] = evento
		}
		return p
	}
	if code, b := dist.web("PATCH", "/routes/"+rutaA, map[string]any{"status": "in_progress"}); code != 200 {
		t.Fatalf("iniciar: %d %s", code, b)
	}
	p1, p2 := nuevo(), nuevo()
	lote := map[string]any{"puntos": []map[string]any{
		punto(p1, []string{rutaA}, 20.01, -75.01, hace(30*time.Minute), "inicio"),
		punto(p2, []string{rutaA}, 20.02, -75.02, hace(20*time.Minute), ""),
		punto(nuevo(), []string{rutaB}, 20.03, -75.03, hace(10*time.Minute), ""),                                   // ruta que no es de su teléfono
		punto(uuid.NewString(), []string{rutaA}, 20.04, -75.04, hace(5*time.Minute), ""),                           // id v4
		punto(nuevo(), []string{rutaA}, 20.05, -75.05, time.Now().UTC().Add(2*time.Hour).Format(time.RFC3339), ""), // futuro
		punto(nuevo(), []string{rutaA}, 99, -75.05, hace(time.Minute), ""),                                         // fuera de rango
	}}
	code, b := dist.web("POST", "/track", lote)
	if code != 200 {
		t.Fatalf("POST /track: %d %s", code, b)
	}
	var r1 struct {
		Recibidos  int `json:"recibidos"`
		Nuevos     int `json:"nuevos"`
		Rechazados []struct{ ID, Motivo string }
	}
	_ = json.Unmarshal(b, &r1)
	if r1.Recibidos != 2 || r1.Nuevos != 2 || len(r1.Rechazados) != 4 {
		t.Fatalf("el lote: %+v", r1)
	}
	code, b = dist.web("POST", "/track", lote) // el aparato no supo si llegó: lo manda otra vez
	_ = json.Unmarshal(b, &r1)
	if code != 200 || r1.Recibidos != 2 || r1.Nuevos != 0 {
		t.Fatalf("el reintento: %d %+v", code, r1)
	}
	horaReal := hace(25 * time.Minute)
	if code, b := dist.web("POST", "/routes/"+rutaA+"/results", map[string]any{"resultados": []map[string]any{
		{"orderId": pedidosA[0], "resultado": "entregado", "hora": horaReal, "cobrado": true}}}); code != 200 {
		t.Fatalf("marcar: %d %s", code, b)
	}
	dist.web("POST", "/track", map[string]any{"puntos": []map[string]any{
		{"id": nuevo(), "rutaIds": []string{rutaA}, "lat": 20.015, "lng": -75.015, "hora": horaReal, "evento": "parada", "pedidoId": pedidosA[0]},
		punto(nuevo(), []string{rutaA}, 20.06, -75.06, hace(time.Minute), ""),
	}})

	for _, ruta := range []string{"/routes/" + rutaA + "/track", "/vehicles/" + camionA + "/historial", "/tracking/ahora"} {
		if code, b := dist.web("GET", ruta, nil); code != 403 || !strings.Contains(string(b), "no_es_para_el_distribuidor") {
			t.Errorf("GET %s como distribuidor: %d %s, tenía que ser 403", ruta, code, b)
		}
	}
	if code, _ := s.web("POST", "/track", lote); code != 403 {
		t.Errorf("POST /track como logístico: %d, tenía que ser 403", code)
	}

	code, b = s.web("GET", "/routes/"+rutaA+"/track", nil)
	if code != 200 {
		t.Fatalf("recorrido: %d %s", code, b)
	}
	var rec struct {
		Puntos  []struct{ ID, Evento string } `json:"puntos"`
		Paradas []struct {
			PedidoID     string  `json:"pedidoId"`
			Resultado    *string `json:"resultado"`
			ResultadoAt  string  `json:"resultadoAt"`
			CobroEntrega *string `json:"cobroEntrega"`
		} `json:"paradas"`
	}
	_ = json.Unmarshal(b, &rec)
	if len(rec.Puntos) != 4 {
		t.Fatalf("los puntos del recorrido: %d %s", len(rec.Puntos), b)
	}
	hechas := 0
	for _, p := range rec.Paradas {
		if p.PedidoID == pedidosA[0] {
			hechas++
			real, _ := time.Parse(time.RFC3339Nano, horaReal)
			vista, _ := time.Parse(time.RFC3339Nano, p.ResultadoAt)
			if d := real.Sub(vista); d > time.Second || d < -time.Second {
				t.Errorf("la hora de la parada tenía que ser la del aparato (%s) y es %s", horaReal, p.ResultadoAt)
			}
			if p.CobroEntrega == nil || *p.CobroEntrega != "cobrado" || p.Resultado == nil || *p.Resultado != "entregado" {
				t.Errorf("la parada: %+v", p)
			}
		}
	}
	if hechas != 1 {
		t.Fatalf("la parada marcada no salió en el recorrido")
	}
	code, b = s.web("GET", "/vehicles/"+camionA+"/historial", nil)
	var hist struct {
		Rutas []struct {
			ID                                    string
			Entregadas, Cobradas, Puntos, Paradas int64
		} `json:"rutas"`
	}
	_ = json.Unmarshal(b, &hist)
	if code != 200 || len(hist.Rutas) != 1 || hist.Rutas[0].ID != rutaA || hist.Rutas[0].Entregadas != 1 || hist.Rutas[0].Cobradas != 1 || hist.Rutas[0].Puntos != 4 || hist.Rutas[0].Paradas != 2 {
		t.Fatalf("el historial del vehículo: %d %s", code, b)
	}
	code, b = s.web("GET", "/tracking/ahora", nil)
	if code != 200 || !strings.Contains(string(b), d1.String()) {
		t.Fatalf("dónde están ahora: %d %s", code, b)
	}
}

func TestElDistribuidorCompletaCancelaYLaOficinaRevisa(t *testing.T) {
	s := levantar(t)
	d := s.distribuidor("Cierre e2e")
	marca := func(c *stack, ruta, pedido, res, nota string) (int, []byte) {
		e := map[string]any{"orderId": pedido, "resultado": res, "cobrado": true}
		if nota != "" {
			e["nota"] = nota
		}
		return c.web("POST", "/routes/"+ruta+"/results", map[string]any{"resultados": []map[string]any{e}})
	}
	telefonoDe := func(ruta string) *stack {
		tel := s.nuevoTelefono()
		if code, b := s.reclama(tel, s.enlace(ruta, false)); code != 200 {
			t.Fatalf("reclamar: %d %s", code, b)
		}
		return s.como(tel.acceso)
	}

	// COMPLETAR: solo con todas las paradas marcadas; «no entregada» exige su motivo
	ruta, _, pedidos := s.rutaConDistribuidor(d)
	dist := telefonoDe(ruta)
	if code, b := dist.web("PATCH", "/routes/"+ruta, map[string]any{"status": "in_progress"}); code != 200 {
		t.Fatalf("iniciar: %d %s", code, b)
	}
	if code, b := dist.web("PATCH", "/routes/"+ruta, map[string]any{"status": "completed"}); code != 409 || !strings.Contains(string(b), "Faltan paradas") {
		t.Errorf("completar sin marcar: %d %s", code, b)
	}
	if _, b := marca(dist, ruta, pedidos[0], "devuelto", ""); !strings.Contains(string(b), msgMotivo) {
		t.Errorf("no entregada sin motivo tenía que rechazarse: %s", b)
	}
	if code, b := dist.web("PATCH", "/routes/"+ruta, map[string]any{"status": "completed"}); code != 409 {
		t.Errorf("completar con la parada rechazada: %d %s", code, b)
	}
	if code, b := marca(dist, ruta, pedidos[0], "devuelto", "el cliente no estaba"); code != 200 {
		t.Fatalf("no entregada con motivo: %d %s", code, b)
	}
	if code, b := marca(dist, ruta, pedidos[1], "entregado", ""); code != 200 {
		t.Fatalf("entregada: %d %s", code, b)
	}
	// REVISIÓN: solo cuando está completada, solo la oficina, y confirmar otra vez no cambia quién
	if code, _ := s.web("POST", "/routes/"+ruta+"/revision", map[string]any{"confirmar": true}); code != 409 {
		t.Errorf("revisar una ruta sin completar: %d, tenía que ser 409", code)
	}
	if code, b := dist.web("PATCH", "/routes/"+ruta, map[string]any{"status": "completed"}); code != 200 {
		t.Fatalf("completar: %d %s", code, b)
	}
	if code, b := dist.web("POST", "/routes/"+ruta+"/revision", map[string]any{"confirmar": true}); code != 403 {
		t.Errorf("el distribuidor no revisa: %d %s", code, b)
	}
	code, b := s.web("POST", "/routes/"+ruta+"/revision", map[string]any{"confirmar": true})
	var r struct {
		RevisadaAt  *string `json:"revisadaAt"`
		RevisadaPor *string `json:"revisadaPor"`
	}
	if code != 200 || json.Unmarshal(b, &r) != nil || r.RevisadaAt == nil {
		t.Fatalf("revisar: %d %s", code, b)
	}
	if code, b := s.web("POST", "/routes/"+ruta+"/revision", map[string]any{"confirmar": true}); code != 200 || !strings.Contains(string(b), *r.RevisadaAt) {
		t.Errorf("revisar otra vez tenía que dejarlo igual: %d %s", code, b)
	}

	// CANCELAR: sin ninguna entregada sí (y las paradas vuelven a disponibles); con una entregada, no
	ruta2, _, pedidos2 := s.rutaConDistribuidor(d)
	dist2 := telefonoDe(ruta2)
	_, _ = dist2.web("PATCH", "/routes/"+ruta2, map[string]any{"status": "in_progress"})
	if code, b := marca(dist2, ruta2, pedidos2[0], "entregado", ""); code != 200 {
		t.Fatalf("entregar: %d %s", code, b)
	}
	if code, b := dist2.web("PATCH", "/routes/"+ruta2, map[string]any{"status": "cancelled"}); code != 409 || !strings.Contains(string(b), "No se puede cancelar") {
		t.Errorf("cancelar con una entregada: %d %s", code, b)
	}
	ruta3, _, pedidos3 := s.rutaConDistribuidor(d)
	dist3 := telefonoDe(ruta3)
	_, _ = dist3.web("PATCH", "/routes/"+ruta3, map[string]any{"status": "in_progress"})
	if code, b := dist3.web("PATCH", "/routes/"+ruta3, map[string]any{"status": "cancelled"}); code != 200 {
		t.Fatalf("cancelar sin entregadas: %d %s", code, b)
	}
	if n := s.pedidosEnLaRuta(ruta3); n != 0 {
		t.Errorf("al cancelar las paradas tenían que quedar libres, quedan %d en la ruta (%v)", n, pedidos3)
	}
	// una ruta cerrada por la OFICINA (sin teléfono) cuenta como revisada; solo se revisa lo que hizo un teléfono
	rutaOficina, _, _ := s.rutaConDistribuidor(d)
	if code, b := s.web("PATCH", "/routes/"+rutaOficina, map[string]any{"status": "completed"}); code != 200 {
		t.Fatalf("completar desde la oficina: %d %s", code, b)
	}
	if _, b := s.web("GET", "/routes/"+rutaOficina, nil); !strings.Contains(string(b), `"revisadaPor":"oficina"`) {
		t.Errorf("una ruta cerrada por la oficina tenía que venir revisada: %s", b)
	}
	// planificada: no la toca
	ruta4, _, _ := s.rutaConDistribuidor(d)
	dist4 := telefonoDe(ruta4)
	if code, _ := dist4.web("PATCH", "/routes/"+ruta4, map[string]any{"status": "planned"}); code != 403 {
		t.Errorf("volver a planificada: %d, tenía que ser 403", code)
	}
}

const msgMotivo = "necesita su motivo"

func TestElVehiculoLlevaSuDistribuidorPorDefecto(t *testing.T) {
	s := levantar(t)
	d := s.distribuidor("Del camion e2e")
	camion, _ := s.siembraDeRuta(1)
	leer := func() (string, string) {
		code, b := s.web("GET", "/vehicles/"+camion, nil)
		var v struct {
			DistribuidorID     *string `json:"distribuidorId"`
			DistribuidorNombre string  `json:"distribuidorNombre"`
		}
		if code != 200 || json.Unmarshal(b, &v) != nil {
			t.Fatalf("leer camión: %d %s", code, b)
		}
		if v.DistribuidorID == nil {
			return "", v.DistribuidorNombre
		}
		return *v.DistribuidorID, v.DistribuidorNombre
	}
	if id, _ := leer(); id != "" {
		t.Fatalf("un camión nuevo no lleva distribuidor: %q", id)
	}
	if code, b := s.web("PATCH", "/vehicles/"+camion, map[string]any{"distribuidorId": d.String()}); code != 200 {
		t.Fatalf("asignar: %d %s", code, b)
	}
	if id, n := leer(); id != d.String() || n != "Del camion e2e" {
		t.Errorf("tras asignar: %q %q", id, n)
	}
	// un id que no existe es un 400 y no toca nada
	if code, _ := s.web("PATCH", "/vehicles/"+camion, map[string]any{"distribuidorId": nuevo()}); code != 400 {
		t.Errorf("distribuidor inexistente: %d, tenía que ser 400", code)
	}
	// la bajada del aparato lo trae
	_, b := s.web("GET", "/sync/cambios", nil)
	if !strings.Contains(string(b), d.String()) {
		t.Errorf("la bajada de vehículos no lleva el distribuidor")
	}
	if code, b := s.web("PATCH", "/vehicles/"+camion, map[string]any{"distribuidorId": nil}); code != 200 {
		t.Fatalf("quitar: %d %s", code, b)
	}
	if id, _ := leer(); id != "" {
		t.Errorf("tras quitar sigue %q", id)
	}
}

func TestElVehiculoSeVinculaAlTelefonoYSeDesvincula(t *testing.T) {
	s := levantar(t)
	d := s.distribuidor("Vinculo e2e")
	camionA, camionB := s.nuevoCamion(), s.nuevoCamion()
	r1, _ := s.rutaConDistribuidorEnCamion(d, camionA)
	r2, _ := s.rutaConDistribuidorEnCamion(d, camionA)
	r3, _ := s.rutaConDistribuidorEnCamion(d, camionB)

	// una ruta SIN camión no se puede mandar
	sinCamion := nuevo()
	if code, b := s.web("POST", "/routes", s.cuerpoDeRuta(sinCamion, camionB, s.siembraDePedidos(1))); code != 201 && code != 200 {
		t.Fatalf("armar la ruta: %d %s", code, b)
	}
	if code, b := s.web("PATCH", "/routes/"+sinCamion, map[string]any{"vehicleId": nil}); code != 200 {
		t.Fatalf("quitarle el camión: %d %s", code, b)
	}
	if code, _ := s.web("POST", "/routes/"+sinCamion+"/enlace", map[string]any{}); code != 409 {
		t.Errorf("enlace de una ruta sin camión: %d, tenía que ser 409", code)
	}

	// el primer teléfono reclama y queda vinculado al camión A
	t1 := s.nuevoTelefono()
	code, b := s.reclama(t1, s.enlace(r1, false))
	if code != 200 || !strings.Contains(string(b), "vinculoId") || !strings.Contains(string(b), camionA) {
		t.Fatalf("reclamar: %d %s", code, b)
	}
	_, b = s.web("GET", "/vehicles/"+camionA, nil)
	if !strings.Contains(string(b), t1.id) {
		t.Errorf("el camión tenía que decir a qué teléfono está vinculado: %s", b)
	}
	// otro teléfono NO puede coger el mismo camión, ni este teléfono otro camión
	if code, b := s.reclama(s.nuevoTelefono(), s.enlace(r2, false)); code != 403 || !strings.Contains(string(b), "vehiculo_de_otro_dispositivo") {
		t.Errorf("otro teléfono en el mismo camión: %d %s", code, b)
	}
	if code, b := s.reclama(t1, s.enlace(r3, false)); code != 403 || !strings.Contains(string(b), "dispositivo_de_otro_vehiculo") {
		t.Errorf("el mismo teléfono en otro camión: %d %s", code, b)
	}
	// el mismo teléfono SÍ acumula otra ruta del mismo camión
	if code, b := s.reclama(t1, s.enlace(r2, false)); code != 200 {
		t.Errorf("segunda ruta del mismo camión: %d %s", code, b)
	}
	// y una ruta en un teléfono no cambia de camión
	if code, _ := s.web("PATCH", "/routes/"+r1, map[string]any{"vehicleId": camionB}); code != 409 {
		t.Errorf("cambiar el camión de una ruta ya reclamada: %d, tenía que ser 409", code)
	}
	fono := s.como(t1.acceso)
	if code, _ := fono.web("GET", "/routes", nil); code != 200 {
		t.Fatalf("el teléfono vinculado ve sus rutas: %d", code)
	}
	if code, _ := fono.web("POST", "/vehicles/"+camionA+"/desvincular", map[string]any{}); code != 403 {
		t.Errorf("el distribuidor no desvincula: %d", code)
	}

	// LA OFICINA DESVINCULA: el teléfono pierde el acceso y se le dice por qué; sus rutas abiertas quedan libres
	code, b = s.web("POST", "/vehicles/"+camionA+"/desvincular", map[string]any{"motivo": "cambio de camion"})
	if code != 200 || !strings.Contains(string(b), r1) || !strings.Contains(string(b), r2) {
		t.Fatalf("desvincular: %d %s", code, b)
	}
	if code, b := fono.web("GET", "/routes", nil); code != 403 || !strings.Contains(string(b), "dispositivo_desvinculado") {
		t.Errorf("tras desvincular: %d %s, tenía que ser 403 dispositivo_desvinculado", code, b)
	}
	if code, b := s.sinSesion("POST", "/d/renovar", map[string]any{"dispositivoId": t1.id, "secreto": t1.secreto}); code != 403 || !strings.Contains(string(b), "dispositivo_desvinculado") {
		t.Errorf("renovar desvinculado: %d %s", code, b)
	}
	if code, _ := s.web("POST", "/vehicles/"+camionA+"/desvincular", map[string]any{}); code != 409 {
		t.Errorf("desvincular dos veces: %d, tenía que ser 409", code)
	}
	// el servidor no borra nada: la historia del vínculo está, con quién y por qué
	_, b = s.web("GET", "/vehicles/"+camionA+"/vinculos", nil)
	if !strings.Contains(string(b), t1.id) || !strings.Contains(string(b), "cambio de camion") {
		t.Errorf("la historia del vínculo: %s", b)
	}
	// el enlace viejo ya no vale y la ruta se manda con uno nuevo a OTRO teléfono, en el mismo camión
	if code, _ := s.reclama(s.nuevoTelefono(), s.enlace(r1, false)); code != 200 {
		t.Errorf("enlace nuevo de la ruta soltada a otro teléfono: %d", code)
	}
	// el teléfono vaciado puede empezar de nuevo con OTRO camión
	if code, b := s.reclama(t1, s.enlace(r3, false)); code != 200 {
		t.Errorf("teléfono desvinculado con otro camión: %d %s", code, b)
	}
	if code, _ := s.como(t1.acceso).web("GET", "/routes", nil); code != 200 {
		t.Errorf("con su vínculo nuevo vuelve a ver sus rutas: %d", code)
	}
}

// LOS HUECOS DE LA AUDITORÍA (04/11/2026): cada uno con la prueba que lo pisa.
func TestLosHuecosDeLaAuditoriaQuedanTapados(t *testing.T) {
	s := levantar(t)
	secretoJWT := env("REPARTO_E2E_JWT_SECRET", "secreto-de-desarrollo-de-mas-de-32-caracteres")
	d := s.distribuidor("Auditoria uno")
	camion := s.nuevoCamion()
	r1, _ := s.rutaConDistribuidorEnCamion(d, camion)

	t1 := s.nuevoTelefono()
	if code, b := s.reclama(t1, s.enlace(r1, false)); code != 200 {
		t.Fatalf("reclamar: %d %s", code, b)
	}
	fono := s.como(t1.acceso)

	// 1. el canal de avisos en vivo no es del distribuidor
	if code, b := fono.web("GET", "/eventos", nil); code != 403 || !strings.Contains(string(b), "no_es_para_el_distribuidor") {
		t.Errorf("/eventos con un teléfono: %d %s, tenía que ser 403", code, b)
	}

	// 2. un teléfono nuevo cuyo primer reclamo FALLA no queda bloqueado: tras desvincular el vehículo, el mismo id entra con su secreto
	t2 := s.nuevoTelefono()
	r2, _ := s.rutaConDistribuidorEnCamion(d, camion)
	if code, b := s.reclama(t2, s.enlace(r2, false)); code != 403 || !strings.Contains(string(b), "vehiculo_de_otro_dispositivo") {
		t.Fatalf("vehículo ocupado: %d %s", code, b)
	}
	if n := s.cuantos("dispositivos_distribuidor", t2.id); n != 0 {
		t.Errorf("el reclamo fallido no debe dejar un teléfono huérfano: %d filas", n)
	}
	if code, b := s.web("POST", "/vehicles/"+camion+"/desvincular", map[string]any{}); code != 200 {
		t.Fatalf("desvincular: %d %s", code, b)
	}
	if code, b := s.reclama(t2, s.enlace(r2, true)); code != 200 || t2.secreto == "" {
		t.Errorf("el mismo teléfono reintenta y entra: %d %s", code, b)
	}
	// el token viejo de t1 (vínculo anterior) no vale aunque el vehículo vuelva a tener un teléfono
	if code, b := fono.web("GET", "/routes", nil); code != 403 || !strings.Contains(string(b), "dispositivo_desvinculado") {
		t.Errorf("token de un vínculo anterior: %d %s", code, b)
	}

	// 3. una ruta cancelada por la oficina no la reabre el teléfono
	fono2 := s.como(t2.acceso)
	if code, b := s.web("PATCH", "/routes/"+r2, map[string]any{"status": "cancelled"}); code != 200 {
		t.Fatalf("cancelar desde la oficina: %d %s", code, b)
	}
	if code, b := fono2.web("PATCH", "/routes/"+r2, map[string]any{"status": "in_progress"}); code != 409 {
		t.Errorf("reabrir una ruta cancelada: %d %s, tenía que ser 409", code, b)
	}

	// 4. «dónde están ahora» ve al teléfono aunque la ruta no tenga distribuidor
	camionB := s.nuevoCamion()
	cuerpo := s.cuerpoDeRuta(nuevo(), camionB, s.siembraDePedidos(1))
	rSin := cuerpo["id"].(string)
	if code, b := s.web("POST", "/routes", cuerpo); code != 201 && code != 200 {
		t.Fatalf("ruta sin distribuidor: %d %s", code, b)
	}
	t3 := s.nuevoTelefono()
	if code, b := s.reclama(t3, s.enlace(rSin, false)); code != 200 {
		t.Fatalf("reclamar sin distribuidor: %d %s", code, b)
	}
	fono3 := s.como(t3.acceso)
	if code, b := fono3.web("PATCH", "/routes/"+rSin, map[string]any{"status": "in_progress"}); code != 200 {
		t.Fatalf("iniciar: %d %s", code, b)
	}
	punto := map[string]any{"puntos": []map[string]any{{"id": nuevo(), "rutaIds": []string{rSin}, "lat": 20.1, "lng": -75.1, "hora": ahora()}}}
	if code, b := fono3.web("POST", "/track", punto); code != 200 {
		t.Fatalf("track: %d %s", code, b)
	}
	if _, b := s.web("GET", "/tracking/ahora", nil); !strings.Contains(string(b), t3.id) {
		t.Errorf("dónde están ahora tenía que traer al teléfono sin distribuidor: %s", b)
	}
	// GPS: una hora de hace 400 días se rechaza
	viejo := map[string]any{"puntos": []map[string]any{{"id": nuevo(), "rutaIds": []string{rSin}, "lat": 20.1, "lng": -75.1,
		"hora": time.Now().UTC().Add(-400 * 24 * time.Hour).Format(time.RFC3339)}}}
	if _, b := fono3.web("POST", "/track", viejo); !strings.Contains(string(b), "demasiado antigua") {
		t.Errorf("hora de hace 400 días: %s", b)
	}

	// 5. el cuadre y la bajada de un teléfono solo llevan lo suyo: nada de catálogo, clientes ni tablero, y solo SU distribuidor
	otro := s.distribuidor("Auditoria otro")
	rOtro, _ := s.rutaConDistribuidorEnCamion(otro, s.nuevoCamion())
	_ = rOtro
	_, b := fono3.web("GET", "/sync/cuadre", nil)
	for _, k := range []string{"customers", "products", "vehicle_types", "boardColumns", "boardPlacements"} {
		if n := len(idsDe(t, b, "colecciones", k)); n != 0 {
			t.Errorf("el cuadre de un teléfono no lleva %q (%d)", k, n)
		}
	}
	_, b = fono3.web("GET", "/sync/cambios", nil)
	if ds := idsDe(t, b, "cambios", "distribuidores", "puestos"); contiene(ds, otro.String()) || contiene(ds, d.String()) {
		t.Errorf("la bajada de un teléfono no lleva distribuidores de rutas que no son suyas: %v", ds)
	}

	// 6. un teléfono dado de baja, o de otra sucursal, no reclama ni renueva
	baja := s.nuevoTelefono()
	rBaja, _ := s.rutaConDistribuidorEnCamion(d, s.nuevoCamion())
	if code, b := s.reclama(baja, s.enlace(rBaja, false)); code != 200 {
		t.Fatalf("alta del teléfono: %d %s", code, b)
	}
	if _, err := s.db.Exec(context.Background(), `UPDATE dispositivos_distribuidor SET activo = false WHERE id = $1`, baja.id); err != nil {
		t.Fatal(err)
	}
	rBaja2, _ := s.rutaConDistribuidorEnCamion(d, s.nuevoCamion())
	if code, _ := s.reclama(baja, s.enlace(rBaja2, false)); code != 403 {
		t.Errorf("teléfono dado de baja reclamando: %d, tenía que ser 403", code)
	}
	if code, _ := s.sinSesion("POST", "/d/renovar", map[string]any{"dispositivoId": baja.id, "secreto": baja.secreto}); code != 403 {
		t.Errorf("teléfono dado de baja renovando: %d, tenía que ser 403", code)
	}
	var otraSucursal uuid.UUID
	if err := s.db.QueryRow(context.Background(), `INSERT INTO branches (name, lat, lng) VALUES ($1, 20, -75) RETURNING id`, "e2e-otra-"+uuid.NewString()).Scan(&otraSucursal); err != nil {
		t.Fatal(err)
	}
	ajeno := s.nuevoTelefono()
	hashAjeno := sha256.Sum256([]byte("clave-del-ajeno"))
	if _, err := s.db.Exec(context.Background(), `INSERT INTO dispositivos_distribuidor (id, branch_id, secreto_hash) VALUES ($1, $2, $3)`, ajeno.id, otraSucursal, hashAjeno[:]); err != nil {
		t.Fatal(err)
	}
	ajeno.secreto = "clave-del-ajeno"
	if code, _ := s.reclama(ajeno, s.enlace(rBaja2, false)); code != 403 {
		t.Errorf("teléfono de otra sucursal reclamando: %d, tenía que ser 403", code)
	}
	// y un token con el teléfono de otra sucursal tampoco entra aunque el JWT sea válido y diga la sucursal de la ruta
	var vOtra, vinculoAjeno uuid.UUID
	var tipoOtra uuid.UUID
	if err := s.db.QueryRow(context.Background(), `INSERT INTO vehicle_types (nombre, branch_id) VALUES ($1, $2) RETURNING id`, "t-"+uuid.NewString(), otraSucursal).Scan(&tipoOtra); err != nil {
		t.Fatal(err)
	}
	if err := s.db.QueryRow(context.Background(), `INSERT INTO vehicles (name, vehicle_type_id, branch_id) VALUES ('v-otra', $1, $2) RETURNING id`, tipoOtra, otraSucursal).Scan(&vOtra); err != nil {
		t.Fatal(err)
	}
	if err := s.db.QueryRow(context.Background(), `INSERT INTO vinculos_vehiculo_dispositivo (vehicle_id, dispositivo_id, branch_id) VALUES ($1, $2, $3) RETURNING id`, vOtra, ajeno.id, otraSucursal).Scan(&vinculoAjeno); err != nil {
		t.Fatal(err)
	}
	falso := s.como(jwt(secretoJWT, map[string]any{
		"sub": "disp-" + ajeno.id, "role": "DISTRIBUIDOR", "roles": []string{"DISTRIBUIDOR"}, "branchId": s.sucursal.String(),
		"entradas": []string{"delivery.entrar"}, "dispositivo": ajeno.id, "vinculo": vinculoAjeno.String(), "exp": time.Now().Add(time.Hour).Unix(),
	}))
	if code, _ := falso.web("GET", "/routes", nil); code != 403 {
		t.Errorf("teléfono de otra sucursal con un token de esta: %d, tenía que ser 403", code)
	}
}

func TestLaOficinaVeLosTelefonosYLosDesvincula(t *testing.T) {
	s := levantar(t)
	d := s.distribuidor("Telefonos e2e")
	camion := s.nuevoCamion()
	ruta, _ := s.rutaConDistribuidorEnCamion(d, camion)
	tel := s.nuevoTelefono()
	if code, b := s.reclama(tel, s.enlace(ruta, false)); code != 200 {
		t.Fatalf("reclamar: %d %s", code, b)
	}
	lista := func(c *stack) []map[string]any {
		code, b := c.web("GET", "/dispositivos", nil)
		if code != 200 {
			t.Fatalf("listar teléfonos: %d %s", code, b)
		}
		var l []map[string]any
		_ = json.Unmarshal(b, &l)
		return l
	}
	buscar := func(l []map[string]any) map[string]any {
		for _, x := range l {
			if x["id"] == tel.id {
				return x
			}
		}
		return nil
	}
	x := buscar(lista(s))
	if x == nil || x["vehiculo"] == nil || x["distribuidor"] == nil || x["rutasAbiertas"].(float64) != 1 || x["vinculadoAt"] == nil {
		t.Fatalf("el teléfono vinculado con su vehículo, distribuidor y 1 ruta abierta: %v", x)
	}
	// un distribuidor no ve la lista de teléfonos
	if code, b := s.como(tel.acceso).web("GET", "/dispositivos", nil); code != 403 {
		t.Errorf("el distribuidor no lista teléfonos: %d %s", code, b)
	}
	// un teléfono de OTRA sucursal real no sale en mi lista
	var sucB uuid.UUID
	if err := s.db.QueryRow(context.Background(), `INSERT INTO branches (name, lat, lng) VALUES ($1, 20, -75) RETURNING id`, "e2e-b-"+uuid.NewString()).Scan(&sucB); err != nil {
		t.Fatal(err)
	}
	ajeno := nuevo()
	h := sha256.Sum256([]byte("x"))
	if _, err := s.db.Exec(context.Background(), `INSERT INTO dispositivos_distribuidor (id, branch_id, secreto_hash) VALUES ($1, $2, $3)`, ajeno, sucB, h[:]); err != nil {
		t.Fatal(err)
	}
	for _, x := range lista(s) {
		if x["id"] == ajeno {
			t.Errorf("el teléfono de otra sucursal no tenía que salir en mi lista")
		}
	}
	// otra sucursal no lo ve
	otra := s.como(jwt(env("REPARTO_E2E_JWT_SECRET", "secreto-de-desarrollo-de-mas-de-32-caracteres"), map[string]any{
		"sub": "e2e-otra", "role": "LOGISTICO", "branchId": uuid.NewString(), "entradas": []string{"delivery.entrar"}, "exp": time.Now().Add(time.Hour).Unix(),
	}))
	if code, _ := otra.web("GET", "/dispositivos", nil); code == 200 {
		t.Errorf("una sucursal inexistente no tenía que listar teléfonos")
	}
	// desvincular desde la lista: el teléfono sigue en la lista, ya sin vehículo y al final
	if code, b := s.web("POST", "/vehicles/"+camion+"/desvincular", map[string]any{"motivo": "prueba"}); code != 200 {
		t.Fatalf("desvincular: %d %s", code, b)
	}
	x = buscar(lista(s))
	if x == nil || x["vehiculo"] != nil || x["vinculadoAt"] != nil || x["rutasAbiertas"].(float64) != 0 {
		t.Errorf("tras desvincular: sin vehículo, sin vínculo y sin rutas abiertas: %v", x)
	}
}
