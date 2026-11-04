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
	ctx := context.Background()
	var tipo uuid.UUID
	if err := s.db.QueryRow(ctx, `INSERT INTO vehicle_types (nombre, branch_id) VALUES ($1, $2) RETURNING id`, "tipo-"+uuid.NewString(), s.sucursal).Scan(&tipo); err != nil {
		s.t.Fatal(err)
	}
	var v uuid.UUID
	if err := s.db.QueryRow(ctx, `INSERT INTO vehicles (name, vehicle_type_id, branch_id) VALUES ($1, $2, $3) RETURNING id`, "camion-"+uuid.NewString()[:8], tipo, s.sucursal).Scan(&v); err != nil {
		s.t.Fatal(err)
	}
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
	return v.String(), pedidos
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
// EL DISTRIBUIDOR SOLO VE Y TOCA LO SUYO (04/11/2026) — contra la API y el sync reales
// ---------------------------------------------------------------------------

// como devuelve el mismo stack pero hablando con OTRO token (el de otra persona).
func (s *stack) como(token string) *stack {
	otro := *s
	otro.token = token
	return &otro
}

func (s *stack) tokenDe(sub, rol, sucursal string) string {
	return jwt(env("REPARTO_E2E_JWT_SECRET", "secreto-de-desarrollo-de-mas-de-32-caracteres"), map[string]any{
		"sub": sub, "email": sub + "@procovar.cu", "role": rol, "branchId": sucursal,
		"entradas": []string{"delivery.entrar"}, "exp": time.Now().Add(time.Hour).Unix(),
	})
}

func (s *stack) distribuidor(nombre, persona string) uuid.UUID {
	s.t.Helper()
	var id uuid.UUID
	if err := s.db.QueryRow(context.Background(), `INSERT INTO distribuidores (branch_id, nombre, persona_id) VALUES ($1, $2, NULLIF($3, '')) RETURNING id`,
		s.sucursal, nombre, persona).Scan(&id); err != nil {
		s.t.Fatal(err)
	}
	return id
}

// rutaDe arma una ruta (la arma el logístico) con ese distribuidor y devuelve su id y sus pedidos.
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

func TestElDistribuidorSoloVeYTocaSusRutas(t *testing.T) {
	s := levantar(t)
	sub1, sub2 := "dist1-"+uuid.NewString()[:8], "dist2-"+uuid.NewString()[:8]
	d1, d2 := s.distribuidor("Uno e2e", sub1), s.distribuidor("Dos e2e", sub2)
	rutaA, camionA, pedidosA := s.rutaConDistribuidor(d1)
	rutaB, _, pedidosB := s.rutaConDistribuidor(d2)
	dist := s.como(s.tokenDe(sub1, "DISTRIBUIDOR", s.sucursal.String()))

	// 1 · su lista: solo la suya
	code, b := dist.web("GET", "/routes", nil)
	if code != 200 {
		t.Fatalf("GET /routes: %d %s", code, b)
	}
	vistas := map[string]bool{}
	var lista []map[string]any
	_ = json.Unmarshal(b, &lista)
	for _, r := range lista {
		vistas[r["id"].(string)] = true
	}
	if !vistas[rutaA] || vistas[rutaB] {
		t.Fatalf("tenía que ver SOLO su ruta: %v", vistas)
	}
	// 2 · la de otro es un 404 (no «prohibido»: ni se le dice que existe)
	if code, _ := dist.web("GET", "/routes/"+rutaB, nil); code != 404 {
		t.Fatalf("la ruta de otro distribuidor: %d, tenía que ser 404", code)
	}
	if code, _ := dist.web("POST", "/routes/"+rutaB+"/results", map[string]any{"resultados": []map[string]any{{"orderId": pedidosB[0], "resultado": "entregado"}}}); code != 404 {
		t.Fatalf("cerrar la ruta de otro: %d, tenía que ser 404", code)
	}
	// 3 · todo lo que no es suyo es un 403 con su marca
	for _, c := range []struct{ metodo, ruta string }{{"GET", "/orders"}, {"GET", "/vehicles"}, {"GET", "/customers"}, {"GET", "/distribuidores"}, {"POST", "/routes"}, {"DELETE", "/routes/" + rutaA}} {
		code, b := dist.web(c.metodo, c.ruta, nil)
		if code != 403 || !strings.Contains(string(b), "no_es_para_el_distribuidor") {
			t.Errorf("%s %s: %d %s, tenía que ser 403 con su marca", c.metodo, c.ruta, code, b)
		}
	}
	// 4 · en SU ruta: marca una parada y la inicia; pero no la renombra ni le cambia el camión
	if code, b := dist.web("PATCH", "/routes/"+rutaA, map[string]any{"name": "me la quedo"}); code != 403 {
		t.Errorf("renombrar su ruta: %d %s, tenía que ser 403", code, b)
	}
	if code, b := dist.web("PATCH", "/routes/"+rutaA, map[string]any{"distribuidorId": d2.String()}); code != 403 {
		t.Errorf("pasarle su ruta a otro: %d %s, tenía que ser 403", code, b)
	}
	if code, b := dist.web("PATCH", "/routes/"+rutaA, map[string]any{"status": "in_progress"}); code != 200 {
		t.Errorf("iniciar su ruta: %d %s", code, b)
	}
	if code, b := dist.web("POST", "/routes/"+rutaA+"/results", map[string]any{"resultados": []map[string]any{{"orderId": pedidosA[0], "resultado": "entregado"}}}); code != 200 {
		t.Errorf("marcar su parada: %d %s", code, b)
	}
	// 5 · su bajada: solo lo suyo (pedidos, ruta, camión, él mismo) y NADA de clientes, catálogo ni tablero
	code, b = dist.web("GET", "/sync/cambios", nil)
	if code != 200 {
		t.Fatalf("GET /sync/cambios: %d %s", code, b)
	}
	pedidos := idsDe(t, b, "cambios", "orders", "puestos")
	if len(pedidos) != 2 || !contiene(pedidos, pedidosA...) || contiene(pedidos, pedidosB...) {
		t.Fatalf("la bajada de pedidos tenía que ser solo los de su ruta: %v", pedidos)
	}
	if rs := idsDe(t, b, "cambios", "routes", "puestos"); len(rs) != 1 || rs[0] != rutaA {
		t.Fatalf("la bajada de rutas: %v", rs)
	}
	if ds := idsDe(t, b, "cambios", "distribuidores", "puestos"); len(ds) != 1 || ds[0] != d1.String() {
		t.Fatalf("la bajada de distribuidores: %v", ds)
	}
	if vs := idsDe(t, b, "cambios", "vehicles", "puestos"); len(vs) != 1 || vs[0] != camionA {
		t.Fatalf("la bajada de vehículos: %v", vs)
	}
	for _, k := range []string{"customers", "products", "boardColumns", "boardPlacements", "vehicle_types"} {
		if n := len(idsDe(t, b, "cambios", k, "puestos")); n != 0 {
			t.Errorf("a un distribuidor no se le baja %q (%d filas)", k, n)
		}
	}
	// 6 · el cuadre: igual
	code, b = dist.web("GET", "/sync/cuadre", nil)
	if code != 200 {
		t.Fatalf("GET /sync/cuadre: %d %s", code, b)
	}
	if ps := idsDe(t, b, "colecciones", "orders"); len(ps) != 2 || !contiene(ps, pedidosA...) {
		t.Fatalf("el cuadre de pedidos: %v", ps)
	}
	if rs := idsDe(t, b, "colecciones", "routes"); len(rs) != 1 || rs[0] != rutaA {
		t.Fatalf("el cuadre de rutas: %v", rs)
	}
	// 7 · FALLA CERRADO: con el rol DISTRIBUIDOR pero sin distribuidor ligado, o de otra sucursal, no ve NADA
	sinLigar := s.como(s.tokenDe("nadie-"+uuid.NewString()[:8], "DISTRIBUIDOR", s.sucursal.String()))
	if code, b := sinLigar.web("GET", "/routes", nil); code != 403 {
		t.Errorf("distribuidor sin ligar: %d %s, tenía que ser 403", code, b)
	}
	var otraSucursal uuid.UUID
	if err := s.db.QueryRow(context.Background(), `INSERT INTO branches (name, lat, lng) VALUES ($1, 20, -75) RETURNING id`, "otra-"+uuid.NewString()).Scan(&otraSucursal); err != nil {
		t.Fatal(err)
	}
	ajeno := s.como(s.tokenDe(sub1, "DISTRIBUIDOR", otraSucursal.String()))
	if code, b := ajeno.web("GET", "/routes", nil); code != 403 {
		t.Errorf("su distribuidor es de otra sucursal: %d %s, tenía que ser 403", code, b)
	}
	// 8 · el sync: da de alta su aparato y sube, pero no ve el panel ni la bandeja
	if code, _ := dist.llamar(dist.sync, "GET", "/sync/estado", nil, nil); code != 403 {
		t.Errorf("/sync/estado para un distribuidor: %d, tenía que ser 403", code)
	}
	if code, _ := dist.llamar(dist.sync, "POST", "/sync/aparato", map[string]any{"nombre": "movil e2e"}, map[string]string{"X-Aparato-Id": uuid.NewString()}); code != 200 && code != 201 {
		t.Errorf("dar de alta su aparato: %d", code)
	}
	// y el logístico sigue viendo las dos
	code, b = s.web("GET", "/routes", nil)
	var todas []map[string]any
	_ = json.Unmarshal(b, &todas)
	if code != 200 || len(todas) < 2 {
		t.Errorf("el logístico tenía que seguir viendo las rutas de todos: %d %d", code, len(todas))
	}
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
