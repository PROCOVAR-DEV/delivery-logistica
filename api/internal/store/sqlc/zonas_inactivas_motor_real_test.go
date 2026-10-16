package sqlc

// ZONAS INACTIVAS (00022, 1.0.38) contra Postgres de verdad. Se salta sin
// `REPARTO_MOTOR_REAL_DSN`, como el resto del motor real. Cada caso es su pareja: lo que una
// zona activa SÍ hace, y que la inactiva NO lo hace.

import (
	"errors"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func TestMotorReal_ZonasInactivas(t *testing.T) {
	pool := motorReal(t)

	apagar := func(b *banco, suc, col uuid.UUID, activa bool) (BoardColumn, error) {
		return b.q.ActualizarColumna(b.ctx, ActualizarColumnaParams{
			ID: col, Activa: &activa, Sucursal: alcance(suc)})
	}
	nombres := func(b *banco, suc uuid.UUID, incluir bool) []string {
		filas, err := b.q.ListarColumnasDelTablero(b.ctx, ListarColumnasDelTableroParams{
			BranchID: suc, Sucursal: sinAlcance, IncluirInactivas: incluir})
		if err != nil {
			t.Fatal(err)
		}
		var s []string
		for _, f := range filas {
			s = append(s, f.Nombre)
		}
		return s
	}

	t.Run("una_zona_nueva_nace_activa_y_la_inactiva_solo_sale_si_se_pide", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		centro := b.columna(suc, "Centro", 0)
		b.columna(suc, "Vista", 1)
		igualesTxt(t, "al nacer", nombres(b, suc, false), []string{"Centro", "Vista"})
		if _, err := apagar(b, suc, centro, false); err != nil {
			t.Fatal(err)
		}
		igualesTxt(t, "sin pedirlas", nombres(b, suc, false), []string{"Vista"})
		igualesTxt(t, "incluirInactivas", nombres(b, suc, true), []string{"Centro", "Vista"})
		fila, err := b.q.ObtenerColumna(b.ctx, ObtenerColumnaParams{ID: centro, Sucursal: alcance(suc)})
		if err != nil || fila.Activa {
			t.Fatalf("ObtenerColumna tiene que traer la inactiva (para reactivarla o borrarla): %+v %v", fila, err)
		}
		if f, err := apagar(b, suc, centro, true); err != nil || !f.Activa {
			t.Fatalf("reactivar: %+v %v", f, err)
		}
		igualesTxt(t, "reactivada", nombres(b, suc, false), []string{"Centro", "Vista"})
	})

	t.Run("ActualizarColumna_sin_activa_no_la_toca", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		col := b.columna(suc, "Centro", 0)
		if _, err := apagar(b, suc, col, false); err != nil {
			t.Fatal(err)
		}
		nuevo := "Otro"
		f, err := b.q.ActualizarColumna(b.ctx, ActualizarColumnaParams{ID: col, Nombre: &nuevo, Sucursal: alcance(suc)})
		if err != nil || f.Activa || f.Nombre != "Otro" {
			t.Fatalf("renombrar no puede reactivar: %+v %v", f, err)
		}
	})

	t.Run("otra_sucursal_no_la_apaga", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc, otra := b.sucursal(), b.sucursal()
		col := b.columna(suc, "Centro", 0)
		_, err := apagar(b, otra, col, false)
		if !errors.Is(err, pgx.ErrNoRows) {
			t.Fatalf("apagar la zona de otra sucursal: %v", err)
		}
		igualesTxt(t, "sigue activa", nombres(b, suc, false), []string{"Centro"})
	})

	t.Run("colocar_en_una_inactiva_da_cero_filas_y_en_una_activa_coloca", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		col := b.columna(suc, "Centro", 0)
		p := b.pedido(listo("p", suc))
		colocar := func() error {
			_, err := b.q.ColocarPedido(b.ctx, ColocarPedidoParams{
				Posicion: 1, PedidoID: p, ColumnaID: col, Sucursal: alcance(suc)})
			return err
		}
		if err := colocar(); err != nil {
			t.Fatalf("en la activa: %v", err)
		}
		_, _ = b.q.QuitarPedidoDelTablero(b.ctx, QuitarPedidoDelTableroParams{PedidoID: p, Sucursal: alcance(suc)})
		if _, err := apagar(b, suc, col, false); err != nil {
			t.Fatal(err)
		}
		if err := colocar(); !errors.Is(err, pgx.ErrNoRows) {
			t.Fatalf("colocar en la inactiva tenía que dar cero filas: %v", err)
		}
		if b.colocaciones() != 0 {
			t.Fatal("se colocó una tarjeta en una zona inactiva")
		}
	})

	t.Run("mover_a_una_inactiva_no_mueve_nada_y_a_una_activa_si", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		origen, destino := b.columna(suc, "Origen", 0), b.columna(suc, "Destino", 1)
		b.ficha(suc, origen, "a", 1)
		mover := func() int64 {
			n, err := b.q.MoverPedidosDeColumna(b.ctx, MoverPedidosDeColumnaParams{
				ColumnaOrigen: origen, ColumnaDestino: destino, Sucursal: alcance(suc)})
			if err != nil {
				t.Fatal(err)
			}
			return n
		}
		if _, err := apagar(b, suc, destino, false); err != nil {
			t.Fatal(err)
		}
		if n := mover(); n != 0 {
			t.Fatalf("movió %d tarjetas a una zona inactiva", n)
		}
		igualesTxt(t, "el origen conserva su tarjeta", b.fichas(origen), []string{"a@1"})
		if _, err := apagar(b, suc, destino, true); err != nil {
			t.Fatal(err)
		}
		if n := mover(); n != 1 {
			t.Fatalf("movió %d a una zona activa y tenían que ser 1", n)
		}
	})

	t.Run("inactivar_devuelve_los_pedidos_a_sin_colocar_y_la_lista_y_el_contador_lo_dicen_igual", func(t *testing.T) {
		b := nuevoBanco(t, pool)
		suc := b.sucursal()
		col := b.columna(suc, "Centro", 0)
		b.ficha(suc, col, "a", 1)
		b.ficha(suc, col, "b", 2)
		sinColocar := func() (int, int64) {
			filas, err := b.q.ListarPedidosSinColocar(b.ctx, ListarPedidosSinColocarParams{
				BranchID: suc, Sucursal: sinAlcance, Limite: 100})
			if err != nil {
				t.Fatal(err)
			}
			total, err := b.q.ContarPedidosSinColocar(b.ctx, ContarPedidosSinColocarParams{BranchID: suc, Sucursal: sinAlcance})
			if err != nil {
				t.Fatal(err)
			}
			return len(filas), total
		}
		if l, c := sinColocar(); l != 0 || c != 0 {
			t.Fatalf("con los dos puestos Sin colocar tenía que estar vacío: lista=%d contador=%d", l, c)
		}
		// Lo que hace el manejador, en su orden y en una transacción: apagar y vaciar.
		if _, err := apagar(b, suc, col, false); err != nil {
			t.Fatal(err)
		}
		if n, err := b.q.VaciarColumna(b.ctx, VaciarColumnaParams{ColumnaID: col, Sucursal: alcance(suc)}); err != nil || n != 2 {
			t.Fatalf("vaciar: n=%d err=%v", n, err)
		}
		if l, c := sinColocar(); l != 2 || c != 2 {
			t.Fatalf("tras inactivar, Sin colocar: lista=%d contador=%d y eran 2 y 2", l, c)
		}
		if b.colocaciones() != 0 {
			t.Fatal("quedaron tarjetas en la zona inactiva")
		}
		// Reactivar la deja vacía.
		if _, err := apagar(b, suc, col, true); err != nil {
			t.Fatal(err)
		}
		if b.colocaciones() != 0 {
			t.Fatal("reactivar no devuelve las tarjetas")
		}
	})

	t.Run("borrar_la_ruta_no_restaura_a_una_zona_inactiva_y_a_una_activa_si", func(t *testing.T) {
		for _, activa := range []bool{true, false} {
			b := nuevoBanco(t, pool)
			suc := b.sucursal()
			col := b.columna(suc, "Centro", 0)
			ruta := b.ruta(suc, RouteStatusPlanned)
			p := b.parada(suc, ruta, col, "p1", 1, 1)
			if !activa {
				if _, err := apagar(b, suc, col, false); err != nil {
					t.Fatal(err)
				}
			}
			filas, err := b.q.SoltarPedidosDeRuta(b.ctx, SoltarPedidosDeRutaParams{RutaID: alcance(ruta), Sucursal: alcance(suc)})
			if err != nil || filas != 1 {
				t.Fatalf("soltar la ruta (activa=%v): filas=%d err=%v", activa, filas, err)
			}
			b.restricciones("SoltarPedidosDeRuta")
			quedan := b.colocaciones()
			if activa && quedan != 1 {
				t.Fatalf("a la zona activa tenía que volver la tarjeta y hay %d", quedan)
			}
			if !activa && quedan != 0 {
				t.Fatalf("la tarjeta volvió a una zona inactiva (%d): no la vería nadie, ni en Sin colocar", quedan)
			}
			_ = p
		}
	})

	t.Run("quitar_una_parada_no_la_restaura_a_una_zona_inactiva_y_a_una_activa_si", func(t *testing.T) {
		for _, activa := range []bool{true, false} {
			b := nuevoBanco(t, pool)
			suc := b.sucursal()
			col := b.columna(suc, "Centro", 0)
			ruta := b.ruta(suc, RouteStatusPlanned)
			p := b.parada(suc, ruta, col, "p1", 1, 1)
			if !activa {
				if _, err := apagar(b, suc, col, false); err != nil {
					t.Fatal(err)
				}
			}
			if _, err := b.q.SoltarParadaPlanificada(b.ctx, SoltarParadaPlanificadaParams{
				PedidoID: p, RutaID: ruta, Sucursal: alcance(suc)}); err != nil {
				t.Fatalf("soltar la parada (activa=%v): %v", activa, err)
			}
			b.restricciones("SoltarParadaPlanificada")
			quedan := b.colocaciones()
			if activa && quedan != 1 {
				t.Fatalf("a la zona activa tenía que volver la tarjeta y hay %d", quedan)
			}
			if !activa && quedan != 0 {
				t.Fatalf("la tarjeta volvió a una zona inactiva (%d)", quedan)
			}
			if b.tieneOrigen(p) {
				t.Fatal("el origen se tenía que gastar igual")
			}
		}
	})
}
