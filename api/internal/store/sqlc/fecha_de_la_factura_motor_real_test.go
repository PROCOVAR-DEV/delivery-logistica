package sqlc

// LA FECHA DE LA FACTURA, EN HORA DE CUBA, CONTRA POSTGRES DE VERDAD — issue 16 de Amado,
// 16/10/2026.
//
// «[El cliente] tiene 6 facturas el día 15, pero se generaron de pedidos creados los días 14
// (4) y el 15 (2). Cuando se busca lo que hay que entregar el 15 solo salen 2 en lugar de
// 6.» Los filtros de fecha de pedidos miraban la fecha DEL PEDIDO; el logístico trabaja
// contra la factura. Ahora son `coalesce(factura_at, order_date, created_at)` y el día es el
// de Cuba (`AT TIME ZONE 'America/Havana'`), no el de UTC.
//
// Los casos son los de `docs/fecha-de-la-factura.casos.json`, el MISMO fichero que lee el
// aparato: las SEIS consultas que filtran por fecha —Sin colocar, el catálogo de Pedidos y
// los disponibles del asistente, cada una con su contador— tienen que contestar lo mismo, y
// el contador lo mismo que su lista. Corre como las demás de motor real: con
// `REPARTO_MOTOR_REAL_DSN`, en su transacción, que se revierte.

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

type casosDeLaFechaDeLaFactura struct {
	Pedidos []struct {
		Nombre    string     `json:"nombre"`
		FacturaAt *time.Time `json:"facturaAt"`
		OrderDate *time.Time `json:"orderDate"`
		CreatedAt *time.Time `json:"createdAt"`
	} `json:"pedidos"`
	Casos []struct {
		Nombre   string   `json:"nombre"`
		Desde    *string  `json:"desde"`
		Hasta    *string  `json:"hasta"`
		Esperado []string `json:"esperado"`
	} `json:"casos"`
	Instantes []struct {
		Instante time.Time `json:"instante"`
		Dia      string    `json:"dia"`
	} `json:"instantes"`
	IniciosDeDia []struct {
		Dia    string    `json:"dia"`
		Inicio time.Time `json:"inicio"`
	} `json:"iniciosDeDia"`
}

func leerCasosDeLaFechaDeLaFactura(t *testing.T) casosDeLaFechaDeLaFactura {
	t.Helper()
	ruta := filepath.Join("..", "..", "..", "..", "docs", "fecha-de-la-factura.casos.json")
	b, err := os.ReadFile(ruta)
	if err != nil {
		t.Fatalf("no se pudo leer %s: %v", ruta, err)
	}
	var c casosDeLaFechaDeLaFactura
	if err := json.Unmarshal(b, &c); err != nil {
		t.Fatalf("%s no se entiende: %v", ruta, err)
	}
	if len(c.Pedidos) == 0 || len(c.Casos) == 0 || len(c.Instantes) == 0 || len(c.IniciosDeDia) == 0 {
		t.Fatalf("%s sin pedidos, casos o instantes: una prueba sobre nada sale verde", ruta)
	}
	return c
}

func diaPg(t *testing.T, s *string) pgtype.Date {
	t.Helper()
	if s == nil {
		return pgtype.Date{}
	}
	d, err := time.Parse("2006-01-02", *s)
	if err != nil {
		t.Fatalf("día %q: %v", *s, err)
	}
	return pgtype.Date{Time: d, Valid: true}
}

func TestMotorReal_LaFechaDeLaFacturaEsElDiaDeCuba(t *testing.T) {
	pool := motorReal(t)
	b := nuevoBanco(t, pool)
	f := leerCasosDeLaFechaDeLaFactura(t)

	// El día de cada instante, preguntado a la base: lo que dice el fichero tiene que ser lo
	// que hace `AT TIME ZONE 'America/Havana'`, o el aparato (que lo calcula a mano) se ata a
	// una regla que el servidor no cumple.
	for _, c := range f.Instantes {
		var dia string
		if err := b.tx.QueryRow(b.ctx,
			`SELECT ($1::timestamptz AT TIME ZONE 'America/Havana')::date::text`, c.Instante).Scan(&dia); err != nil {
			t.Fatal(err)
		}
		if dia != c.Dia {
			t.Errorf("%s es el día %s en Cuba y el fichero dice %s", c.Instante.Format(time.RFC3339), dia, c.Dia)
		}
	}
	for _, c := range f.IniciosDeDia {
		var empieza, antes string
		if err := b.tx.QueryRow(b.ctx,
			`SELECT ($1::timestamptz AT TIME ZONE 'America/Havana')::date::text,
                    (($1::timestamptz - interval '1 second') AT TIME ZONE 'America/Havana')::date::text`,
			c.Inicio).Scan(&empieza, &antes); err != nil {
			t.Fatal(err)
		}
		if empieza != c.Dia || antes >= c.Dia {
			t.Errorf("el día %s no empieza a las %s (ese instante es el %s y un segundo antes el %s)",
				c.Dia, c.Inicio.Format(time.RFC3339), empieza, antes)
		}
	}

	suc := b.sucursal()
	nombreDe := map[string]string{}
	for _, p := range f.Pedidos {
		s := listo(p.Nombre, suc)
		s.OrderDate, s.FacturaAt = p.OrderDate, p.FacturaAt
		id := b.pedido(s)
		nombreDe[id.String()] = p.Nombre
		// `created_at` es NOT NULL con `now()` de respaldo: lo que dice el fichero se pone a mano.
		if p.CreatedAt != nil {
			b.exec(`UPDATE orders SET created_at = $2 WHERE id = $1`, id, *p.CreatedAt)
		}
	}
	nombres := func(ids []string) []string {
		var salen []string
		for _, id := range ids {
			salen = append(salen, nombreDe[id])
		}
		sort.Strings(salen)
		return salen
	}

	for _, c := range f.Casos {
		t.Run(c.Nombre, func(t *testing.T) {
			desde, hasta := diaPg(t, c.Desde), diaPg(t, c.Hasta)
			esperado := append([]string{}, c.Esperado...)
			sort.Strings(esperado)
			if len(esperado) == 0 {
				esperado = nil
			}
			vistos := func(ids []string) []string {
				if s := nombres(ids); len(s) > 0 {
					return s
				}
				return nil
			}

			// 1) Sin colocar: la lista y el contador.
			sc, err := b.q.ListarPedidosSinColocar(b.ctx, ListarPedidosSinColocarParams{
				BranchID: suc, Sucursal: sinAlcance, DiaDesde: desde, DiaHasta: hasta, Limite: 100})
			if err != nil {
				t.Fatal(err)
			}
			var ids []string
			for _, x := range sc {
				ids = append(ids, x.ID.String())
			}
			igualesTxt(t, "ListarPedidosSinColocar", vistos(ids), esperado)
			n, err := b.q.ContarPedidosSinColocar(b.ctx, ContarPedidosSinColocarParams{
				BranchID: suc, Sucursal: sinAlcance, DiaDesde: desde, DiaHasta: hasta})
			if err != nil {
				t.Fatal(err)
			}
			if int(n) != len(esperado) {
				t.Errorf("ContarPedidosSinColocar = %d y la lista trae %d", n, len(esperado))
			}

			// 2) El catálogo de Pedidos: la lista y el contador.
			ped, err := b.q.ListarPedidos(b.ctx, ListarPedidosParams{
				BranchID: alcance(suc), Desde: desde, Hasta: hasta, Limite: 100})
			if err != nil {
				t.Fatal(err)
			}
			ids = nil
			for _, x := range ped {
				ids = append(ids, x.ID.String())
			}
			igualesTxt(t, "ListarPedidos", vistos(ids), esperado)
			n, err = b.q.ContarPedidos(b.ctx, ContarPedidosParams{
				BranchID: alcance(suc), Desde: desde, Hasta: hasta})
			if err != nil {
				t.Fatal(err)
			}
			if int(n) != len(esperado) {
				t.Errorf("ContarPedidos = %d y la lista trae %d", n, len(esperado))
			}

			// 3) Los disponibles del asistente: la lista y el contador.
			dis, err := b.q.ListarPedidosDisponibles(b.ctx, ListarPedidosDisponiblesParams{
				BranchID: alcance(suc), Desde: desde, Hasta: hasta, Limite: 100})
			if err != nil {
				t.Fatal(err)
			}
			ids = nil
			for _, x := range dis {
				ids = append(ids, x.ID.String())
			}
			igualesTxt(t, "ListarPedidosDisponibles", vistos(ids), esperado)
			n, err = b.q.ContarPedidosDisponibles(b.ctx, ContarPedidosDisponiblesParams{
				BranchID: alcance(suc), Desde: desde, Hasta: hasta})
			if err != nil {
				t.Fatal(err)
			}
			if int(n) != len(esperado) {
				t.Errorf("ContarPedidosDisponibles = %d y la lista trae %d", n, len(esperado))
			}
		})
	}
}
