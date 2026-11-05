package api

// CANCELAR UNA FACTURA DEVUELTA CONTRA POSTGRES DE VERDAD (issue 25 de Amado, 05/11/2026): POST /api/orders/{id}/cancelar.
// «La cancelada es el cancelado ese»: sin estado ni columna nueva, `resultado = 'cancelado'`. Aquí se ejecutan las
// consultas reales por la puerta HTTP, en una transacción que se revierte. Se salta sin REPARTO_MOTOR_REAL_DSN.

import (
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
)

// devuelta deja una factura como la deja el cierre de una ruta con un devuelto: sin route_id, con la hoja
// (`ultima_ruta_id`), su resultado, su hora de ayer y su nota.
func (e *entornoDeConduces) devuelta(id uuid.UUID) uuid.UUID {
	e.t.Helper()
	ruta := e.id(`INSERT INTO routes (branch_id, status, name) VALUES ($1, 'completed', 'ayer') RETURNING id`, e.stg)
	e.exec(`UPDATE orders SET resultado = 'devuelto', resultado_at = now() - interval '1 day',
	          resultado_nota = 'el cliente no estaba', ultima_ruta_id = $2 WHERE id = $1`, id, ruta)
	return id
}

type fotoDeCancelar struct {
	Resultado *string
	Nota      *string
	ConHora   bool
	Archivado bool
	Ruta      *uuid.UUID
}

func (e *entornoDeConduces) foto(id uuid.UUID) fotoDeCancelar {
	e.t.Helper()
	var f fotoDeCancelar
	if err := e.tx.QueryRow(e.ctx, `SELECT resultado::text, resultado_nota, coalesce(resultado_at > now() - interval '1 hour', false),
	     archivado, route_id FROM orders WHERE id = $1`, id).Scan(&f.Resultado, &f.Nota, &f.ConHora, &f.Archivado, &f.Ruta); err != nil {
		e.t.Fatal(err)
	}
	return f
}

func (e *entornoDeConduces) avisosEnElBuzon(estado string) int {
	e.t.Helper()
	var n int
	if err := e.tx.QueryRow(e.ctx, `SELECT count(*) FROM avisos_a_pedido WHERE estado = $1`, estado).Scan(&n); err != nil {
		e.t.Fatal(err)
	}
	return n
}

func TestMotorReal_Cancelar_UnaDevueltaSeCancelaYSeAvisaAPedido(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	f := e.devuelta(e.factura("47500", "Cliente Arrepentido", 3))
	col := e.id(`INSERT INTO board_columns (branch_id, nombre, posicion) VALUES ($1, 'Centro', 0) RETURNING id`, e.stg)
	e.exec(`INSERT INTO board_placements (order_id, column_id, posicion) VALUES ($1, $2, 0)`, f, col)

	// Antes de cancelar la devuelta vuelve: está en los disponibles.
	_, cuerpo := e.llamar(e.jwt, http.MethodGet, "/api/orders/available", "")
	if !strings.Contains(cuerpo, f.String()) {
		t.Fatalf("la devuelta tenía que estar en disponibles antes de cancelarla: %s", cuerpo)
	}

	code, cuerpo := e.llamar(e.jwt, http.MethodPost, "/api/orders/"+f.String()+"/cancelar", `{"nota":"  el cliente se arrepintió  "}`)
	if code != http.StatusOK {
		t.Fatalf("cancelar: %d %s", code, cuerpo)
	}
	ficha := decodificar[struct {
		ID            uuid.UUID `json:"id"`
		Resultado     *string   `json:"resultado"`
		ResultadoAt   *string   `json:"resultadoAt"`
		ResultadoNota *string   `json:"resultadoNota"`
		Archivado     bool      `json:"archivado"`
	}](t, cuerpo)
	if ficha.ID != f || ficha.Resultado == nil || *ficha.Resultado != "cancelado" || ficha.ResultadoAt == nil ||
		ficha.ResultadoNota == nil || *ficha.ResultadoNota != "el cliente se arrepintió" || ficha.Archivado {
		t.Fatalf("la ficha de la cancelada: %s", cuerpo)
	}
	if d := e.foto(f); d.Resultado == nil || *d.Resultado != "cancelado" || !d.ConHora || d.Ruta != nil || d.Archivado {
		t.Fatalf("en la base: %+v", d)
	}
	// La tarjeta ya no está en ninguna zona.
	var enZona int
	if err := e.tx.QueryRow(e.ctx, `SELECT count(*) FROM board_placements WHERE order_id = $1`, f).Scan(&enZona); err != nil || enZona != 0 {
		t.Fatalf("la cancelada sigue en una zona del tablero: %d (%v)", enZona, err)
	}

	// PEDIDO se entera POR FACTURA, con la nota, y queda apuntado en el buzón.
	if len(e.avisados) != 1 || e.avisados[0].Estado != "cancelado" || e.avisados[0].Factura != "47500" ||
		e.avisados[0].Folio != "FOLIO-47500" || e.avisados[0].Nota != "el cliente se arrepintió" || e.avisados[0].PedidoID != "" {
		t.Fatalf("el aviso a PEDIDO: %+v", e.avisados)
	}
	if n := e.avisosEnElBuzon("cancelado"); n != 1 {
		t.Fatalf("avisos cancelados en el buzón = %d, tenía que ser 1", n)
	}

	// YA NO VUELVE a disponibles (el resto de consultas del pool, en `consultas_motor_real_test.go`).
	_, cuerpo = e.llamar(e.jwt, http.MethodGet, "/api/orders/available", "")
	if strings.Contains(cuerpo, f.String()) {
		t.Fatalf("una cancelada volvió a disponibles: %s", cuerpo)
	}

	// EL REINTENTO de la cola del aparato: 409 «ya está cancelada», y no cambia nada ni avisa otra vez.
	code, cuerpo = e.llamar(e.jwt, http.MethodPost, "/api/orders/"+f.String()+"/cancelar", `{"nota":"otra"}`)
	if code != http.StatusConflict || !strings.Contains(cuerpo, msgYaCancelada) || !strings.Contains(cuerpo, `"codigo":"`+CodigoYaCancelada+`"`) {
		t.Fatalf("el reintento: %d %s (el sincronizador lo reconoce por el codigo)", code, cuerpo)
	}
	if d := e.foto(f); d.Nota == nil || *d.Nota != "el cliente se arrepintió" {
		t.Fatalf("el reintento cambió la nota: %+v", d)
	}
	if n := e.avisosEnElBuzon("cancelado"); n != 1 {
		t.Fatalf("el reintento apuntó otro aviso: %d", n)
	}
}

// Sin cuerpo y sin nota se conserva la de la devolución (no se pierde el porqué); una nota en blanco es «sin nota».
func TestMotorReal_Cancelar_SinNotaConservaLaDeLaDevolucion(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	a := e.devuelta(e.factura("47510", "Uno", 1))
	b := e.devuelta(e.factura("47511", "Dos", 1))
	if code, cuerpo := e.llamar(e.jwt, http.MethodPost, "/api/orders/"+a.String()+"/cancelar", ""); code != http.StatusOK {
		t.Fatalf("sin cuerpo: %d %s", code, cuerpo)
	}
	if code, cuerpo := e.llamar(e.jwt, http.MethodPost, "/api/orders/"+b.String()+"/cancelar", `{"nota":"   "}`); code != http.StatusOK {
		t.Fatalf("nota en blanco: %d %s", code, cuerpo)
	}
	for _, id := range []uuid.UUID{a, b} {
		if d := e.foto(id); d.Resultado == nil || *d.Resultado != "cancelado" || d.Nota == nil || *d.Nota != "el cliente no estaba" {
			t.Fatalf("%s: %+v", id, d)
		}
	}
}

func TestMotorReal_Cancelar_LaNotaLargaYElCuerpoRotoSeRechazanSinTocarNada(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	f := e.devuelta(e.factura("47520", "Uno", 1))
	casos := []struct{ nombre, cuerpo, mensaje string }{
		{"501 caracteres", `{"nota":"` + strings.Repeat("ñ", 501) + `"}`, msgNotaLarga},
		{"la nota no es texto", `{"nota":5}`, msgCancelarCuerpo},
		{"no es JSON", `{"nota":`, msgCancelarCuerpo},
	}
	for _, c := range casos {
		code, cuerpo := e.llamar(e.jwt, http.MethodPost, "/api/orders/"+f.String()+"/cancelar", c.cuerpo)
		if code != http.StatusBadRequest || !strings.Contains(cuerpo, c.mensaje) {
			t.Fatalf("%s: %d %s", c.nombre, code, cuerpo)
		}
	}
	if d := e.foto(f); *d.Resultado != "devuelto" {
		t.Fatalf("un cuerpo rechazado cambió la factura: %+v", d)
	}
	// La pareja: justo 500 caracteres SÍ pasa.
	if code, cuerpo := e.llamar(e.jwt, http.MethodPost, "/api/orders/"+f.String()+"/cancelar", `{"nota":"`+strings.Repeat("ñ", 500)+`"}`); code != http.StatusOK {
		t.Fatalf("500 caracteres: %d %s", code, cuerpo)
	}
}

// Cada 409 dice POR QUÉ, y no toca la factura. Y el alcance falla cerrado: otra sucursal es un 404.
func TestMotorReal_Cancelar_LosRechazosDicenPorQue(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	sinMarcar := e.factura("47530", "Sin marcar", 1)
	entregada := e.factura("47531", "Entregada", 1)
	e.exec(`UPDATE orders SET resultado = 'entregado', delivered_at = now() WHERE id = $1`, entregada)
	enRuta := e.factura("47532", "En ruta", 1)
	ruta := e.id(`INSERT INTO routes (branch_id, status, name) VALUES ($1, 'planned', 'hoy') RETURNING id`, e.stg)
	e.exec(`UPDATE orders SET route_id = $2, ultima_ruta_id = $2, resultado = 'devuelto' WHERE id = $1`, enRuta, ruta)
	ya := e.devuelta(e.factura("47533", "Ya cancelada", 1))
	e.exec(`UPDATE orders SET resultado = 'cancelado' WHERE id = $1`, ya)

	for _, c := range []struct {
		nombre  string
		id      uuid.UUID
		mensaje string
	}{
		{"sin marcar", sinMarcar, msgCancelarNoDevuelta},
		{"entregada", entregada, msgCancelarNoDevuelta},
		{"va en una ruta", enRuta, msgCancelarVaEnRuta},
		{"ya cancelada", ya, msgYaCancelada},
	} {
		code, cuerpo := e.llamar(e.jwt, http.MethodPost, "/api/orders/"+c.id.String()+"/cancelar", `{"nota":"x"}`)
		if code != http.StatusConflict || !strings.Contains(cuerpo, c.mensaje) {
			t.Fatalf("%s: %d %s", c.nombre, code, cuerpo)
		}
	}
	if d := e.foto(enRuta); *d.Resultado != "devuelto" || d.Ruta == nil {
		t.Fatalf("el 409 por ruta cambió la factura: %+v", d)
	}
	if d := e.foto(entregada); *d.Resultado != "entregado" {
		t.Fatalf("el 409 por entregada cambió la factura: %+v", d)
	}
	if len(e.avisados) != 0 || e.avisosEnElBuzon("cancelado") != 0 {
		t.Fatalf("un rechazo avisó a PEDIDO: %+v", e.avisados)
	}

	// EL ALCANCE: la devuelta de Holguín, para el logístico de Santiago, no existe (404, no 409). El SUPER ADMIN sí la cancela.
	hol := e.devuelta(e.facturaDe(e.hol, "HOL", "60001", "De Holguín", 1))
	if code, cuerpo := e.llamar(e.jwt, http.MethodPost, "/api/orders/"+hol.String()+"/cancelar", ""); code != http.StatusNotFound {
		t.Fatalf("otra sucursal: %d %s", code, cuerpo)
	}
	if d := e.foto(hol); *d.Resultado != "devuelto" {
		t.Fatalf("un 404 cambió la factura de otra sucursal: %+v", d)
	}
	if code, cuerpo := e.llamar(e.jwtTodas, http.MethodPost, "/api/orders/"+hol.String()+"/cancelar", ""); code != http.StatusOK {
		t.Fatalf("SUPER ADMIN: %d %s", code, cuerpo)
	}
	// Y un id que no existe también es 404.
	if code, _ := e.llamar(e.jwt, http.MethodPost, "/api/orders/"+uuid.NewString()+"/cancelar", ""); code != http.StatusNotFound {
		t.Fatalf("id inexistente: %d", code)
	}
}

// Cancelar la PRINCIPAL de un conduce cancela a sus miembros (el resultado de la principal es el de todos, regla 5) y se
// avisa a PEDIDO por cada factura. Un miembro suelto no se cancela.
func TestMotorReal_Cancelar_UnConduceSeCancelaEnteroPorSuPrincipal(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	a := e.factura("47540", "Mismo Cliente", 2)
	b := e.factura("47541", "Mismo Cliente", 3)
	if code, cuerpo := e.crear(e.jwt, a, b); code != http.StatusCreated {
		t.Fatalf("crear el conduce: %d %s", code, cuerpo)
	}
	// El cierre dejó las dos devueltas (el conduce se conserva).
	e.devuelta(a)
	e.devuelta(b)

	if code, cuerpo := e.llamar(e.jwt, http.MethodPost, "/api/orders/"+b.String()+"/cancelar", ""); code != http.StatusConflict ||
		!strings.Contains(cuerpo, msgCancelarMiembro) {
		t.Fatalf("un miembro suelto: %d %s", code, cuerpo)
	}
	if code, cuerpo := e.llamar(e.jwt, http.MethodPost, "/api/orders/"+a.String()+"/cancelar", `{"nota":"se arrepintió"}`); code != http.StatusOK {
		t.Fatalf("cancelar la principal: %d %s", code, cuerpo)
	}
	for _, id := range []uuid.UUID{a, b} {
		if d := e.foto(id); *d.Resultado != "cancelado" {
			t.Fatalf("%s tenía que quedar cancelada: %+v", id, d)
		}
	}
	facturas := map[string]bool{}
	for _, av := range e.avisados {
		facturas[av.Factura+":"+av.Estado] = true
	}
	if len(e.avisados) != 2 || !facturas["47540:cancelado"] || !facturas["47541:cancelado"] {
		t.Fatalf("PEDIDO tenía que enterarse de las dos facturas: %+v", e.avisados)
	}
}
