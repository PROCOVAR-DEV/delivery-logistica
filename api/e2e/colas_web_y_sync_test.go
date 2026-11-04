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
