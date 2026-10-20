package sqlc

// LA MIGRACIÓN 00025 (el folio del pedido) CONTRA POSTGRES DE VERDAD, issue 20.
//
// Lo que tiene que cumplir el relleno de las ~15.000 filas que hay:
//
//  1. `folio` queda igual a `operation_number` en las filas de PEDIDO, y SOLO en ellas.
//  2. NO MUEVE `updated_at`. La bajada de los aparatos se pide por `updated_at`: un UPDATE normal
//     haría que cada teléfono y cada escritorio se volviera a bajar todos los pedidos para
//     recibir una columna que no leen.
//  3. El trigger que mantiene `updated_at` queda ENCENDIDO al terminar: apagarlo para el relleno
//     y dejarlo apagado es la peor forma de acabar esto.
//  4. El índice que usa la adopción existe.
//
// Dentro de UNA transacción que se revierte: se deshace la 00025, se siembra el estado de ANTES
// y se vuelve a subir. Mientras dura, `orders` queda bloqueada para otras conexiones (es lo que
// cuesta la migración de verdad), así que no se corre contra una base que esté usando otro.

import (
	"context"
	"strings"
	"testing"
	"time"
)

func TestMotorReal_Migracion00025ElFolioRellenaSinMoverLaBajada(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)
	up, down := seccionesDeLaMigracion(t, "00025_folio_del_pedido.sql")

	b.exec(down)
	if got := b.entero(`SELECT count(*) FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'folio'`); got != 0 {
		t.Fatal("el Down tenía que quitar la columna")
	}

	// ANTES: dos pedidos de PEDIDO (uno sin número de operación), un alta manual y uno de OTRA sucursal,
	// todos con un `updated_at` viejo y reconocible.
	viejo := time.Date(2020, 1, 1, 12, 0, 0, 0, time.UTC)
	sembrar := func(operacion any, fuente any, externo any, sucursal string) string {
		var id string
		if err := b.tx.QueryRow(b.ctx, `INSERT INTO orders (customer_name, address, weight, operation_number, source, external_id, sucursal_codigo, updated_at)
		    VALUES ('cliente', 'calle', 1, $1, $2::text::procedencia, $3, $4, $5) RETURNING id::text`,
			operacion, fuente, externo, sucursal, viejo).Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id
	}
	unoDePedido := sembrar("PXX-1", "pedido", "ped-1", "STG")
	sinOperacion := sembrar(nil, "pedido", "ped-2", "STG")
	altaManual := sembrar("MANUAL-1", nil, nil, "STG")
	deHolguin := sembrar("PXX-1", "pedido", "ped-3", "HOL")

	b.exec(up)

	folio := func(id string) (f *string) {
		t.Helper()
		if err := b.tx.QueryRow(b.ctx, `SELECT folio FROM orders WHERE id = $1::uuid`, id).Scan(&f); err != nil {
			t.Fatal(err)
		}
		return
	}
	if f := folio(unoDePedido); f == nil || *f != "PXX-1" {
		t.Errorf("la fila de PEDIDO tiene que quedar con folio = operation_number: %v", f)
	}
	if f := folio(deHolguin); f == nil || *f != "PXX-1" {
		t.Errorf("también la de otra sucursal (el folio es único dentro de su sucursal, no en la casa): %v", f)
	}
	if f := folio(sinOperacion); f != nil {
		t.Errorf("sin operation_number no hay folio que copiar, y no se inventa uno: %q", *f)
	}
	if f := folio(altaManual); f != nil {
		t.Errorf("un alta manual no es de PEDIDO y no se rellena: %q", *f)
	}

	// 2. La bajada no se entera.
	for _, id := range []string{unoDePedido, sinOperacion, altaManual, deHolguin} {
		var cuando time.Time
		if err := b.tx.QueryRow(b.ctx, `SELECT updated_at FROM orders WHERE id = $1::uuid`, id).Scan(&cuando); err != nil {
			t.Fatal(err)
		}
		if !cuando.Equal(viejo) {
			t.Errorf("el relleno movió updated_at de %s a %s: cada aparato se bajaría todos los pedidos", id, cuando)
		}
	}

	// 3. El trigger quedó encendido ('O' = habilitado) y funciona.
	var estado string
	if err := b.tx.QueryRow(b.ctx, `SELECT tgenabled::text FROM pg_trigger WHERE tgname = 'trg_orders_updated' AND tgrelid = 'orders'::regclass`).Scan(&estado); err != nil {
		t.Fatal(err)
	}
	if estado != "O" {
		t.Fatalf("trg_orders_updated tiene que quedar habilitado y está en %q", estado)
	}
	b.exec(`UPDATE orders SET notes = 'tocado' WHERE id = $1::uuid`, unoDePedido)
	var despues time.Time
	if err := b.tx.QueryRow(b.ctx, `SELECT updated_at FROM orders WHERE id = $1::uuid`, unoDePedido).Scan(&despues); err != nil {
		t.Fatal(err)
	}
	if !despues.After(viejo) {
		t.Error("y tiene que seguir moviendo updated_at cuando alguien toca una fila")
	}

	// 4. El índice de la adopción es POR EXPRESIÓN: la adopción compara `folio_normalizado(folio)`, y un
	// índice sobre `folio` a secas no la sirve (G3).
	if got := b.entero(`SELECT count(*) FROM pg_indexes WHERE tablename = 'orders' AND indexname = 'orders_sucursal_folio_idx'
	                    AND indexdef LIKE '%(sucursal_codigo, folio_normalizado(folio))%'`); got != 1 {
		t.Error("falta el índice (sucursal_codigo, folio_normalizado(folio))")
	}
}

// El planificador USA el índice de expresión para la pregunta de la adopción (G3). Fuera de la
// transacción de la prueba de la migración: ahí los UPDATE del relleno dejan el índice recién creado
// "no apto" para esa transacción (indcheckxmin) y el plan no diría nada.
func TestMotorReal_LaAdopcionVaPorElIndiceDeExpresion(t *testing.T) {
	pool := motorReal(t)
	ctx := context.Background()
	conn, err := pool.Acquire(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Release()
	if _, err := conn.Exec(ctx, `SET enable_seqscan = off`); err != nil {
		t.Fatal(err)
	}
	defer func() { _, _ = conn.Exec(ctx, `RESET enable_seqscan`) }()
	// Lo que hacen `AdoptarPedidoPorFolio` y `ExisteEntregaDeFacturaDelFolio`, tal cual.
	filas, err := conn.Query(ctx, `EXPLAIN SELECT o.id FROM orders o
	    WHERE o.source = 'pedido' AND o.sucursal_codigo = 'STG'
	      AND folio_normalizado(o.folio) = folio_normalizado($1::text)`, "pxx - 1")
	if err != nil {
		t.Fatal(err)
	}
	plan := ""
	for filas.Next() {
		var linea string
		if err := filas.Scan(&linea); err != nil {
			t.Fatal(err)
		}
		plan += linea + "\n"
	}
	filas.Close()
	// El nombre no basta: un índice sobre `folio` a secas también se llamaría así y serviría sólo por
	// la sucursal. Lo que prueba que sirve la EXPRESIÓN es que esté en la condición del índice (la
	// función SQL sale inlinada: upper(regexp_replace(folio…))).
	cond := ""
	for _, l := range strings.Split(plan, "\n") {
		if strings.Contains(l, "Index Cond") {
			cond = l
		}
	}
	if !strings.Contains(plan, "orders_sucursal_folio_idx") || !strings.Contains(cond, "regexp_replace(folio") {
		t.Errorf("la pregunta de la adopción tiene que ir por el índice de EXPRESIÓN (con el folio normalizado en su condición); el plan es:\n%s", plan)
	}
}
