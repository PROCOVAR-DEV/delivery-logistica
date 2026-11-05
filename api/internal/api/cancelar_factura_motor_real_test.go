package api

// CANCELAR UNA FACTURA DEVUELTA CONTRA POSTGRES DE VERDAD (issue 25 de Amado, 05/11/2026): POST /api/orders/{id}/cancelar.
// «La cancelada es el cancelado ese»: sin estado ni columna nueva, `resultado = 'cancelado'`. Aquí se ejecutan las
// consultas reales por la puerta HTTP, en una transacción que se revierte. Se salta sin REPARTO_MOTOR_REAL_DSN.

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/store/sqlc"
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
	// Y el origen de tablero que dejó una ruta vieja (`board_route_origins`, UNIQUE por factura): con él, borrar esa ruta
	// devolvería la tarjeta a su zona. Una cancelada no vuelve a ninguna.
	rutaVieja := e.id(`INSERT INTO routes (branch_id, status, name) VALUES ($1, 'planned', 'vieja') RETURNING id`, e.stg)
	e.exec(`INSERT INTO board_route_origins (route_id, order_id, column_id, posicion) VALUES ($1, $2, $3, 0)`, rutaVieja, f, col)

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
	var origenes int
	if err := e.tx.QueryRow(e.ctx, `SELECT count(*) FROM board_route_origins WHERE order_id = $1`, f).Scan(&origenes); err != nil || origenes != 0 {
		t.Fatalf("la cancelada conserva su origen de tablero y reaparecería al borrar la ruta: %d (%v)", origenes, err)
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

// ---------------------------------------------------------------------------
// Auditoría del issue 25
// ---------------------------------------------------------------------------

type cierreDeRuta struct {
	Error     string `json:"error"`
	Aplicados []struct {
		OrderID string `json:"orderId"`
	} `json:"aplicados"`
	Rechazados []struct {
		OrderID string `json:"orderId"`
		Motivo  string `json:"motivo"`
	} `json:"rechazados"`
}

// G1 · UNA CANCELADA NO SE DESHACE POR `/results` MIENTRAS LA RUTA NO ESTÉ COMPLETADA. Ruta en curso, parada devuelta,
// se cancela, y se reenvía «devuelto», «entregado» y «sin marca»: los tres 409 con el motivo literal, la fila sigue
// cancelada y sale en la hoja de la ruta. Volver a mandar «cancelado» (una hoja reenviada entera) SÍ pasa.
func TestMotorReal_Cancelar_NoSeDeshaceDesdeLaHojaDeCierre(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	f := e.factura("47600", "Cliente", 2)
	otra := e.factura("47601", "Otra", 2)
	ruta := e.id(`INSERT INTO routes (branch_id, status, name, origin_lat, origin_lng) VALUES ($1, 'in_progress', 'hoy', 20, -75) RETURNING id`, e.stg)
	e.exec(`UPDATE orders SET route_id = $2, ultima_ruta_id = $2, stop_order = 1 WHERE id = $1`, f, ruta)
	e.exec(`UPDATE orders SET route_id = $2, ultima_ruta_id = $2, stop_order = 2 WHERE id = $1`, otra, ruta)
	url := "/api/routes/" + ruta.String() + "/results"
	marcar := func(id uuid.UUID, resultado string) (int, cierreDeRuta) {
		t.Helper()
		code, cuerpo := e.llamar(e.jwt, http.MethodPost, url, `{"resultados":[{"orderId":"`+id.String()+`","resultado":`+resultado+`}]}`)
		var c cierreDeRuta
		_ = json.Unmarshal([]byte(cuerpo), &c)
		return code, c
	}

	if code, c := marcar(f, `"devuelto"`); code != http.StatusOK {
		t.Fatalf("devolver la parada de la ruta en curso: %d %+v", code, c)
	}
	if code, cuerpo := e.llamar(e.jwt, http.MethodPost, "/api/orders/"+f.String()+"/cancelar", `{"nota":"se arrepintió"}`); code != http.StatusOK {
		t.Fatalf("cancelar: %d %s", code, cuerpo)
	}
	for _, c := range []struct{ nombre, resultado string }{
		{"devuelto", `"devuelto"`}, {"entregado", `"entregado"`}, {"sin marca (null)", `null`},
	} {
		code, cierre := marcar(f, c.resultado)
		if code != http.StatusConflict || len(cierre.Rechazados) != 1 || cierre.Rechazados[0].Motivo != msgParadaCancelada || len(cierre.Aplicados) != 0 {
			t.Fatalf("reenviar %s sobre una cancelada: %d %+v (tenía que ser 409 «%s»)", c.nombre, code, cierre, msgParadaCancelada)
		}
		if d := e.foto(f); d.Resultado == nil || *d.Resultado != "cancelado" || d.Ruta != nil || d.Nota == nil || *d.Nota != "se arrepintió" {
			t.Fatalf("reenviar %s deshizo la cancelación: %+v", c.nombre, d)
		}
	}
	// Una hoja con la cancelada Y otra parada buena: la buena se guarda, la cancelada se rechaza con su motivo.
	code, cuerpo := e.llamar(e.jwt, http.MethodPost, url, `{"resultados":[{"orderId":"`+f.String()+`","resultado":"entregado"},{"orderId":"`+otra.String()+`","resultado":"entregado"}]}`)
	if code != http.StatusConflict || !strings.Contains(cuerpo, otra.String()) {
		t.Fatalf("hoja mixta: %d %s", code, cuerpo)
	}
	if d := e.foto(otra); d.Resultado == nil || *d.Resultado != "entregado" {
		t.Fatalf("la parada buena de la hoja mixta no se guardó: %+v", d)
	}
	// Repetir «cancelado» no se rechaza.
	if code, c := marcar(f, `"cancelado"`); code != http.StatusOK {
		t.Fatalf("repetir «cancelado»: %d %+v", code, c)
	}
	// LA PAREJA: una devuelta de la misma ruta sí se corrige y se desmarca.
	d := e.factura("47602", "Devuelta", 1)
	e.exec(`UPDATE orders SET route_id = $2, ultima_ruta_id = $2, stop_order = 3 WHERE id = $1`, d, ruta)
	if code, c := marcar(d, `"devuelto"`); code != http.StatusOK {
		t.Fatalf("devolver: %d %+v", code, c)
	}
	if code, c := marcar(d, `null`); code != http.StatusOK {
		t.Fatalf("desmarcar una devuelta: %d %+v", code, c)
	}
}

// M1 · UN NUL EN LA NOTA ES UN 400 (Postgres no lo guarda en un `text`; era un 500 y por la cola el apunte se reintentaba
// para siempre). En la cancelación y en el cierre de ruta; nada se escribe.
func TestMotorReal_Cancelar_UnaNotaConNULEsUn400(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	f := e.devuelta(e.factura("47610", "Uno", 1))
	if code, cuerpo := e.llamar(e.jwt, http.MethodPost, "/api/orders/"+f.String()+"/cancelar", `{"nota":"a\u0000b"}`); code != http.StatusBadRequest || !strings.Contains(cuerpo, msgNotaConNUL) {
		t.Fatalf("cancelar con NUL: %d %s", code, cuerpo)
	}
	if d := e.foto(f); *d.Resultado != "devuelto" {
		t.Fatalf("un 400 cambió la factura: %+v", d)
	}
	ruta := e.id(`INSERT INTO routes (branch_id, status, name, origin_lat, origin_lng) VALUES ($1, 'in_progress', 'hoy', 20, -75) RETURNING id`, e.stg)
	p := e.factura("47611", "Dos", 1)
	e.exec(`UPDATE orders SET route_id = $2, ultima_ruta_id = $2 WHERE id = $1`, p, ruta)
	url := "/api/routes/" + ruta.String() + "/results"
	if code, cuerpo := e.llamar(e.jwt, http.MethodPost, url, `{"resultados":[{"orderId":"`+p.String()+`","resultado":"devuelto","nota":"a\u0000b"}]}`); code != http.StatusBadRequest || !strings.Contains(cuerpo, msgNotaConNUL) {
		t.Fatalf("cierre con NUL: %d %s", code, cuerpo)
	}
	// LA PAREJA: la misma hoja sin NUL se guarda.
	if code, cuerpo := e.llamar(e.jwt, http.MethodPost, url, `{"resultados":[{"orderId":"`+p.String()+`","resultado":"devuelto","nota":"ab"}]}`); code != http.StatusOK {
		t.Fatalf("cierre sin NUL: %d %s", code, cuerpo)
	}
}

// S2 · EL `if len(ids) == 0` DEL MANEJADOR: la lectura previa dice que se puede, pero entre ella y la escritura la factura
// entró en una ruta (la carrera). La escritura no toca nada y contesta 409 «cambió mientras se cancelaba», sin avisar a PEDIDO.
func TestMotorReal_Cancelar_LaCarreraEntreLaLecturaYLaEscritura(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	f := e.devuelta(e.factura("47620", "Uno", 1))
	ruta := e.id(`INSERT INTO routes (branch_id, status, name) VALUES ($1, 'planned', 'hoy') RETURNING id`, e.stg)
	e.trasLeerPedido = func(id uuid.UUID) { e.exec(`UPDATE orders SET route_id = $2 WHERE id = $1`, id, ruta) }
	code, cuerpo := e.llamar(e.jwt, http.MethodPost, "/api/orders/"+f.String()+"/cancelar", "")
	if code != http.StatusConflict || !strings.Contains(cuerpo, msgCancelarCambio) {
		t.Fatalf("la carrera: %d %s (tenía que ser 409 «%s»)", code, cuerpo, msgCancelarCambio)
	}
	if d := e.foto(f); *d.Resultado != "devuelto" || d.Ruta == nil {
		t.Fatalf("la carrera canceló la factura: %+v", d)
	}
	if len(e.avisados) != 0 || e.avisosEnElBuzon("cancelado") != 0 {
		t.Fatalf("la carrera avisó a PEDIDO: %+v", e.avisados)
	}
}

// S3 · LOS TRES MOTIVOS DE «ESTÁ CANCELADA»: colocar en una zona, la tarjeta ya puesta (candidata) y armar una ruta.
func TestMotorReal_Cancelar_LosMotivosDeLaCancelada(t *testing.T) {
	e := nuevoEntornoDeConduces(t)
	tipo := e.id(`INSERT INTO vehicle_types (nombre) VALUES ('Camión de prueba') RETURNING id`)
	camion := e.id(`INSERT INTO vehicles (name, vehicle_type_id, capacity, branch_id) VALUES ('C1', $1, 1000, $2) RETURNING id`, tipo, e.stg)
	zona := e.id(`INSERT INTO board_columns (branch_id, nombre, posicion, vehicle_id) VALUES ($1, 'Centro', 1, $2) RETURNING id`, e.stg, camion)
	cancelada := func(numero string) uuid.UUID {
		f := e.devuelta(e.factura(numero, "Cliente "+numero, 1))
		e.exec(`UPDATE orders SET resultado = 'cancelado' WHERE id = $1`, f)
		return f
	}

	// 1 · COLOCAR: 409 «Esa factura está cancelada» (y no el 404 de la zona ni «ya va en una ruta»).
	c1 := cancelada("47630")
	code, cuerpo := e.llamar(e.jwt, http.MethodPut, "/api/board/placements/"+c1.String(), fmt.Sprintf(`{"columnaId":%q}`, zona))
	if code != http.StatusConflict || !strings.Contains(cuerpo, msgYaSeCancelo) {
		t.Fatalf("colocar una cancelada: %d %s", code, cuerpo)
	}
	var puestas int
	if err := e.tx.QueryRow(e.ctx, `SELECT count(*) FROM board_placements WHERE order_id = $1`, c1).Scan(&puestas); err != nil || puestas != 0 {
		t.Fatalf("la cancelada quedó colocada: %d (%v)", puestas, err)
	}

	// 2 · LA TARJETA YA PUESTA (cancelada después de colocarse), con punto: no se arma y se nombra («está cancelada»).
	c2 := cancelada("47631")
	e.exec(`INSERT INTO board_placements (order_id, column_id, posicion) VALUES ($1, $2, 0)`, c2, zona)
	code, cuerpo = e.llamar(e.jwt, http.MethodPost, "/api/board/columns/"+zona.String()+"/route", `{"nombre":"r"}`)
	if code != http.StatusConflict || !strings.Contains(cuerpo, `"motivo":"está cancelada"`) {
		t.Fatalf("armar la zona con una cancelada: %d %s", code, cuerpo)
	}
	// 3 · ARMAR UNA RUTA con ella: el literal del plural/singular, y el detalle de «no se pudo armar» (sin punto).
	c3 := cancelada("47632")
	code, cuerpo = e.llamar(e.jwt, http.MethodPost, "/api/routes", fmt.Sprintf(`{"vehicleId":%q,"orderIds":[%q],"originLat":20,"originLng":-75}`, camion, c3))
	if code != http.StatusConflict || !strings.Contains(cuerpo, "1 de las facturas elegidas ESTÁ CANCELADA y no puede volver a un camión: 47632.") {
		t.Fatalf("armar con una cancelada: %d %s", code, cuerpo)
	}
	e.exec(`UPDATE orders SET end_lat = NULL, end_lng = NULL WHERE id = $1`, c3)
	code, cuerpo = e.llamar(e.jwt, http.MethodPost, "/api/routes", fmt.Sprintf(`{"vehicleId":%q,"orderIds":[%q],"originLat":20,"originLng":-75}`, camion, c3))
	if code != http.StatusBadRequest || !strings.Contains(cuerpo, "47632 (está cancelada y no puede volver a un camión)") {
		t.Fatalf("armar con una cancelada sin punto: %d %s", code, cuerpo)
	}
}

// S3 · LOS DOS TRADUCTORES DE «POR QUÉ NO», sin pasar por el HTTP (la tarjeta sin punto de una zona rompe `ListarPedidosColocados`
// con un NULL en `km_al_almacen`, hallazgo previo y ajeno a este cambio: ver el informe): la cancelada se nombra «está cancelada»
// y, EN PAREJA, la misma fila con ruta o sin resultado cae en su motivo de siempre.
func TestElPorQueNoDeLaCanceladaSeNombra(t *testing.T) {
	cancelado, devuelto := sqlc.StopResultCancelado, sqlc.StopResultDevuelto
	if m, q := porQueNoEsCandidato(sqlc.ListarPedidosColocadosRow{Resultado: &cancelado}); m != "está cancelada" || q == "" {
		t.Fatalf("porQueNoEsCandidato(cancelada) = %q / %q", m, q)
	}
	if m, _ := porQueNoEsCandidato(sqlc.ListarPedidosColocadosRow{Resultado: &devuelto}); m == "está cancelada" {
		t.Fatalf("una devuelta no está cancelada: %q", m)
	}
	if got := porQueNoSeArma(sqlc.PorQueNoSePuedeArmarRow{Resultado: &cancelado}); got != "está cancelada y no puede volver a un camión" {
		t.Fatalf("porQueNoSeArma(cancelada) = %q", got)
	}
	if got := porQueNoSeArma(sqlc.PorQueNoSePuedeArmarRow{Resultado: &devuelto}); got == "está cancelada y no puede volver a un camión" {
		t.Fatalf("una devuelta no está cancelada: %q", got)
	}
}
