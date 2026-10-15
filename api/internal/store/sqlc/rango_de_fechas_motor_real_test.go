package sqlc

// EL RANGO DE FECHAS DEL PEDIDO, CONTRA POSTGRES DE VERDAD — issue 13 de Amado, 15/10/2026.
//
// «Sin colocar» del tablero sólo sabía de UN día y ahora acota por un rango, cada extremo
// por su lado (`dia_desde` incluido, `dia_hasta` excluido y ya como el día siguiente). El
// paso 4 del asistente pide lo mismo a los disponibles, que ya tenían `desde`/`hasta`. Aquí
// se comprueba en pareja —lo de dentro ENTRA, en los dos bordes, y lo de fuera NO— y que el
// contador dice lo mismo que la lista con cada rango. Corre como las demás de motor real:
// con `REPARTO_MOTOR_REAL_DSN`, en su transacción, que se revierte.

import (
	"sort"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

func TestMotorReal_SinColocarPorRangoDeFechas(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)
	suc := b.sucursal()

	en := func(d, h, m int) *time.Time {
		f := time.Date(2026, 10, d, h, m, 0, 0, time.UTC)
		return &f
	}
	nombreDe := map[string]string{}
	for _, c := range []struct {
		nombre string
		fecha  *time.Time
	}{
		{"del_1_a_las_0", en(1, 0, 0)},    // el borde de abajo, en el instante exacto
		{"del_3_a_las_23", en(3, 23, 30)}, // el borde de arriba, a última hora
		{"del_4_a_las_0", en(4, 0, 0)},    // el primero de FUERA por arriba
		{"sin_fecha_creado_el_2", nil},    // sin `order_date`: va por `created_at`
	} {
		s := listo(c.nombre, suc)
		s.OrderDate = c.fecha
		id := b.pedido(s)
		nombreDe[id.String()] = c.nombre
		if c.fecha == nil {
			b.exec(`UPDATE orders SET created_at = $2 WHERE id = $1`, id, *en(2, 12, 0))
		}
	}

	dia := func(d int) pgtype.Timestamptz {
		return pgtype.Timestamptz{Time: time.Date(2026, 10, d, 0, 0, 0, 0, time.UTC), Valid: true}
	}
	nada := pgtype.Timestamptz{}

	for _, c := range []struct {
		nombre       string
		desde, hasta pgtype.Timestamptz
		esperado     []string
	}{
		{"del_1_al_3_entran_los_dos_bordes", dia(1), dia(4),
			[]string{"del_1_a_las_0", "del_3_a_las_23", "sin_fecha_creado_el_2"}},
		{"solo_desde_el_4", dia(4), nada, []string{"del_4_a_las_0"}},
		{"solo_hasta_el_3", nada, dia(4),
			[]string{"del_1_a_las_0", "del_3_a_las_23", "sin_fecha_creado_el_2"}},
		{"el_2_solo_el_que_no_tiene_fecha", dia(2), dia(3), []string{"sin_fecha_creado_el_2"}},
		// Y el hasta también corta al que va por `created_at`: creado el 2, fuera de «hasta el 1».
		{"hasta_el_1_deja_fuera_al_creado_el_2", nada, dia(2), []string{"del_1_a_las_0"}},
		{"fuera_de_todo_no_sale_nada", dia(5), dia(9), nil},
	} {
		t.Run(c.nombre, func(t *testing.T) {
			filas, err := b.q.ListarPedidosSinColocar(b.ctx, ListarPedidosSinColocarParams{
				BranchID: suc, Sucursal: sinAlcance, DiaDesde: c.desde, DiaHasta: c.hasta, Limite: 100})
			if err != nil {
				t.Fatal(err)
			}
			var salen []string
			for _, f := range filas {
				salen = append(salen, nombreDe[f.ID.String()])
			}
			sort.Strings(salen)
			igualesTxt(t, "ListarPedidosSinColocar", salen, c.esperado)

			total, err := b.q.ContarPedidosSinColocar(b.ctx, ContarPedidosSinColocarParams{
				BranchID: suc, Sucursal: sinAlcance, DiaDesde: c.desde, DiaHasta: c.hasta})
			if err != nil {
				t.Fatal(err)
			}
			if int(total) != len(filas) {
				t.Errorf("ContarPedidosSinColocar = %d y la lista trae %d con el mismo rango", total, len(filas))
			}
		})
	}

	// Los disponibles del asistente ya tenían `desde`/`hasta` (`hasta` llega como fin del
	// día, `finalDelDia`): la misma pareja, para que las dos listas contesten igual.
	finDelDia := func(d int) pgtype.Timestamptz {
		return pgtype.Timestamptz{Time: time.Date(2026, 10, d, 23, 59, 59, 999_000_000, time.UTC), Valid: true}
	}
	for _, c := range []struct {
		nombre       string
		desde, hasta pgtype.Timestamptz
		esperado     []string
	}{
		{"disponibles_del_1_al_3", dia(1), finDelDia(3),
			[]string{"del_1_a_las_0", "del_3_a_las_23", "sin_fecha_creado_el_2"}},
		{"disponibles_desde_el_4", dia(4), nada, []string{"del_4_a_las_0"}},
		{"disponibles_fuera_de_todo", dia(5), finDelDia(9), nil},
	} {
		t.Run(c.nombre, func(t *testing.T) {
			filas, err := b.q.ListarPedidosDisponibles(b.ctx, ListarPedidosDisponiblesParams{
				BranchID: alcance(suc), Desde: c.desde, Hasta: c.hasta, Limite: 100})
			if err != nil {
				t.Fatal(err)
			}
			var salen []string
			for _, f := range filas {
				salen = append(salen, nombreDe[f.ID.String()])
			}
			sort.Strings(salen)
			igualesTxt(t, "ListarPedidosDisponibles", salen, c.esperado)

			total, err := b.q.ContarPedidosDisponibles(b.ctx, ContarPedidosDisponiblesParams{
				BranchID: alcance(suc), Desde: c.desde, Hasta: c.hasta})
			if err != nil {
				t.Fatal(err)
			}
			if int(total) != len(filas) {
				t.Errorf("ContarPedidosDisponibles = %d y la lista trae %d con el mismo rango", total, len(filas))
			}
		})
	}
}
