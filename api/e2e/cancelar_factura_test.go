package e2e

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/google/uuid"
)

// devuelta deja una factura DEVUELTA y sin ruta, como la deja el cierre de una ruta.
func (s *stack) devuelta() string {
	s.t.Helper()
	p := s.siembraDePedidos(1)[0]
	if _, err := s.db.Exec(context.Background(),
		`UPDATE orders SET resultado = 'devuelto', resultado_at = now() - interval '1 day', resultado_nota = 'no estaba' WHERE id = $1`, p); err != nil {
		s.t.Fatal(err)
	}
	return p
}

func (s *stack) resultadoDe(id string) (resultado, nota string) {
	s.t.Helper()
	var r, n *string
	if err := s.db.QueryRow(context.Background(), `SELECT resultado::text, resultado_nota FROM orders WHERE id = $1`, id).Scan(&r, &n); err != nil {
		s.t.Fatal(err)
	}
	if r != nil {
		resultado = *r
	}
	if n != nil {
		nota = *n
	}
	return
}

func (s *stack) disponible(id string) bool {
	s.t.Helper()
	code, b := s.web("GET", "/orders/available?limit=500", nil)
	if code != 200 {
		s.t.Fatalf("available: %d %s", code, b)
	}
	return strings.Contains(string(b), id)
}

// 6 · ISSUE 25 (Facturas devueltas): cancelar por la WEB (directo a la API) y por la COLA del aparato (sync -> API). El reintento
// de la cola sobre una factura ya cancelada NO queda rechazado (409 `ya_cancelada` = apunte hecho), y cualquier otro 409 sí, con su
// motivo literal. La cancelada deja de ofrecerse para repartir; la devuelta de al lado, no.
func TestCancelarUnaFacturaDevueltaPorLaWebYPorLaColaDelAparato(t *testing.T) {
	s := levantar(t)
	ap := s.aparato()
	porWeb, porCola, queSigue := s.devuelta(), s.devuelta(), s.devuelta()
	if !s.disponible(porWeb) || !s.disponible(queSigue) {
		t.Fatal("antes de cancelar, las devueltas tienen que ofrecerse")
	}

	// la WEB
	code, b := s.web("POST", "/orders/"+porWeb+"/cancelar", map[string]any{"nota": "se arrepintió"})
	if code != 200 {
		t.Fatalf("cancelar por la web: %d %s", code, b)
	}
	var ficha struct {
		Resultado     string `json:"resultado"`
		ResultadoNota string `json:"resultadoNota"`
	}
	if json.Unmarshal(b, &ficha) != nil || ficha.Resultado != "cancelado" || ficha.ResultadoNota != "se arrepintió" {
		t.Fatalf("la ficha: %s", b)
	}
	if r, n := s.resultadoDe(porWeb); r != "cancelado" || n != "se arrepintió" {
		t.Fatalf("en la base: %q %q", r, n)
	}
	// el reintento de la web: 409 con su código
	if code, b = s.web("POST", "/orders/"+porWeb+"/cancelar", map[string]any{}); code != 409 || !strings.Contains(string(b), `"codigo":"ya_cancelada"`) {
		t.Fatalf("el reintento de la web: %d %s", code, b)
	}

	// la COLA del aparato: se aplica…
	r := s.subir(ap, apunte{Clave: clave(), Hecho: ahora(), Metodo: "POST", Ruta: "/orders/" + porCola + "/cancelar", Cuerpo: map[string]any{"nota": "desde el aparato"}})
	if len(r) != 1 || r[0].Estado != "aplicado" {
		t.Fatalf("la cancelación por la cola: %+v", r)
	}
	if rr, n := s.resultadoDe(porCola); rr != "cancelado" || n != "desde el aparato" {
		t.Fatalf("en la base: %q %q", rr, n)
	}
	// …y su reintento (otra clave, como una cola reconstruida) NO queda rechazado: la factura ya está cancelada.
	r = s.subir(ap, apunte{Clave: clave(), Hecho: ahora(), Metodo: "POST", Ruta: "/orders/" + porCola + "/cancelar", Cuerpo: map[string]any{"nota": "otra vez"}})
	if len(r) != 1 || r[0].Estado != "aplicado" {
		t.Fatalf("el reintento de la cola tenía que darse por hecho: %+v", r)
	}
	if _, n := s.resultadoDe(porCola); n != "desde el aparato" {
		t.Fatalf("el reintento cambió la nota: %q", n)
	}

	// EN PAREJA: otro 409 SÍ es un rechazo con su motivo literal (una factura que ya va en una ruta).
	enRuta := s.devuelta()
	camion := s.nuevoCamion()
	ruta := nuevo()
	if code, b := s.web("POST", "/routes", s.cuerpoDeRuta(ruta, camion, []string{enRuta})); code != 200 && code != 201 {
		t.Fatalf("armar la ruta con la devuelta (se reasigna): %d %s", code, b)
	}
	r = s.subir(ap, apunte{Clave: clave(), Hecho: ahora(), Metodo: "POST", Ruta: "/orders/" + enRuta + "/cancelar"})
	if len(r) != 1 || r[0].Estado != "rechazado" || !strings.Contains(r[0].Motivo, "va en una ruta") {
		t.Fatalf("una factura en ruta no se cancela y queda rechazada con su motivo: %+v", r)
	}

	// Una cancelada YA NO se ofrece, ni se arma en una ruta; la devuelta de al lado, sí.
	if s.disponible(porWeb) || s.disponible(porCola) {
		t.Fatal("una cancelada volvió a disponibles")
	}
	if !s.disponible(queSigue) {
		t.Fatal("la devuelta que no se canceló dejó de ofrecerse")
	}
	code, b = s.web("POST", "/routes", s.cuerpoDeRuta(nuevo(), camion, []string{porWeb}))
	if code != 409 || !strings.Contains(string(b), "ESTÁ CANCELADA y no puede volver a un camión") {
		t.Fatalf("armar con una cancelada: %d %s", code, b)
	}

	// Un id que no existe (o es de otra sucursal: el alcance lo prueba `TestMotorReal_Cancelar_LosRechazosDicenPorQue`): 404.
	if code, _ := s.web("POST", "/orders/"+uuid.NewString()+"/cancelar", nil); code != 404 {
		t.Fatalf("id inexistente: %d", code)
	}
}
