package api

// LA FACTURA ANULADA QUE IBA EN UNA RUTA, CONTRA POSTGRES DE VERDAD (00027, Jose y Amado, 23/10/2026:
// «la cancelada que ya va en una ruta, si ya no aparece, quitarla e INFORMAR que esa factura ya fue
// cancelada»).
//
// Lo que se ata aquí lo hace la BASE y no lo ve ningún doble: el UPDATE con sus guardas (ruta sin
// completar, sin resultado ni entrega, aún no anulada), el trigger de totales de la ruta, el CHECK
// «anulada implica archivada», el upsert que la reactiva y que las listas y los contadores no la
// cuentan. Comparte entorno con `facturas_motor_real_test.go` (REPARTO_MOTOR_REAL_DSN, base aislada).

import (
	"math"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/espejo"
	"procovar/reparto-api/internal/store/sqlc"
)

// estaAnulada: marcada, archivada y fuera de toda ruta.
func (env *entornoReal) estaAnulada(id uuid.UUID) bool {
	env.t.Helper()
	return env.entero(`SELECT count(*) FROM orders WHERE id = $1 AND anulada_at IS NOT NULL AND archivado
	    AND route_id IS NULL AND ultima_ruta_id IS NULL AND stop_order IS NULL`, id) == 1
}

// rutaEn crea una ruta del estado que se pida y mete en ella estas entregas, en este orden.
func (env *entornoReal) rutaEn(estado string, entregas ...uuid.UUID) uuid.UUID {
	env.t.Helper()
	var ruta uuid.UUID
	if err := env.pool.QueryRow(env.ctx, `INSERT INTO routes (branch_id, status, name, origin_lat, origin_lng, total_distance, optimized)
	    VALUES ($1, $2::route_status, 'Centro', 20.0, -75.8, 1, false) RETURNING id`, env.branch, estado).Scan(&ruta); err != nil {
		env.t.Fatal(err)
	}
	for i, id := range entregas {
		env.exec(`UPDATE orders SET route_id = $2, ultima_ruta_id = $2, stop_order = $3 WHERE id = $1`, id, ruta, i+1)
	}
	return ruta
}

func (env *entornoReal) pesoDeLaRuta(ruta uuid.UUID) (peso, importe float64, sinCotizar int) {
	env.t.Helper()
	if err := env.pool.QueryRow(env.ctx, `SELECT total_weight, total_price, paradas_sin_cotizar FROM routes WHERE id = $1`, ruta).
		Scan(&peso, &importe, &sinCotizar); err != nil {
		env.t.Fatal(err)
	}
	return
}

// dosEnUnaRuta siembra las facturas 1 y 2 (misma fecha) y las mete en una ruta del estado dado.
func (env *entornoReal) dosEnUnaRuta(estado string) (cancelada, viva espejo.FacturaDeVentra, idC, idV, ruta uuid.UUID) {
	env.t.Helper()
	cancelada, viva = facturaDeMentira("1", "2026-10-19", "FA"), facturaDeMentira("2", "2026-10-19", "FB")
	env.sembrarEntregas(cancelada, viva)
	idC, idV = env.idDe(env.exF("1", "2026-10-19")), env.idDe(env.exF("2", "2026-10-19"))
	ruta = env.rutaEn(estado, idC, idV)
	return
}

// LA PRUEBA PRINCIPAL: planned e in_progress. La fila se queda, marcada y archivada; sale de la ruta; la
// ruta queda coherente (totales por el trigger, la otra parada intacta); y se dice.
func TestMotorReal_LaFacturaAnuladaEnUnaRutaSinCompletarSeQuitaYQuedaMarcada(t *testing.T) {
	for _, estado := range []string{"planned", "in_progress"} {
		t.Run(estado, func(t *testing.T) {
			env := nuevoEntornoReal(t)
			cancelada, viva, idC, idV, ruta := env.dosEnUnaRuta(estado)
			// El importe de una parada es lo cobrado de domicilio en su factura (0,29 en la factura de mentira).
			if peso, importe, _ := env.pesoDeLaRuta(ruta); peso != 72 || math.Abs(importe-0.58) > 1e-9 {
				t.Fatalf("la ruta con las dos paradas pesa 72 y cobra 0,58: %v %v", peso, importe)
			}
			// La zona de la que salió la parada: al anularla NO vuelve al tablero.
			var zona uuid.UUID
			if err := env.pool.QueryRow(env.ctx, `INSERT INTO board_columns (branch_id, nombre, posicion) VALUES ($1, 'Zona '||$2, 0) RETURNING id`,
				env.branch, env.codigo).Scan(&zona); err != nil {
				t.Fatal(err)
			}
			env.exec(`INSERT INTO board_route_origins (route_id, order_id, column_id, posicion) VALUES ($1, $2, $3, 0)`, ruta, idC, zona)
			antes := env.entero(`SELECT count(*) FROM orders WHERE sucursal_codigo = $1`, env.codigo)

			env.ventra.poner(viva) // Ventra ya no manda la 1
			env.registro.Reset()
			_ = cancelada
			env.ciclo()

			if !env.estaAnulada(idC) {
				t.Fatalf("la 1 tenía que quedar anulada, archivada y fuera de la ruta\n%s", env.registro.String())
			}
			if env.entero(`SELECT count(*) FROM orders WHERE sucursal_codigo = $1`, env.codigo) != antes {
				t.Error("la fila NO se borra: es lo que permite informar")
			}
			if env.entero(`SELECT count(*) FROM orders WHERE id = $1 AND anulada_de_ruta_id = $2 AND anulada_at > now() - interval '1 minute'`, idC, ruta) != 1 {
				t.Error("y recuerda de qué ruta salió y cuándo")
			}
			// La otra parada, intacta: misma ruta, mismo orden (los huecos no se renumeran, como al quitar a mano).
			if env.entero(`SELECT count(*) FROM orders WHERE id = $1 AND route_id = $2 AND ultima_ruta_id = $2 AND stop_order = 2 AND anulada_at IS NULL`, idV, ruta) != 1 {
				t.Error("la parada viva sigue en su ruta y en su sitio")
			}
			// La ruta, coherente: el trigger de totales sacó el peso y el importe de la anulada.
			if peso, importe, sin := env.pesoDeLaRuta(ruta); peso != 36 || math.Abs(importe-0.29) > 1e-9 || sin != 0 {
				t.Errorf("la ruta tiene que quedar con SOLO la parada viva (36 kg, 0,29): %v %v sin cotizar %d", peso, importe, sin)
			}
			// No vuelve a su zona del tablero, y su rastro de origen se va.
			if env.entero(`SELECT count(*) FROM board_placements WHERE order_id = $1`, idC) != 0 ||
				env.entero(`SELECT count(*) FROM board_route_origins WHERE order_id = $1`, idC) != 0 {
				t.Error("una factura cancelada no reaparece en ninguna zona del tablero")
			}
			if !strings.Contains(env.registro.String(), "se quitó de su ruta") || !strings.Contains(env.registro.String(), "anuladasQuitadasDeRuta=1") ||
				!strings.Contains(env.registro.String(), env.exF("1", "2026-10-19")) {
				t.Errorf("y se dice, con la factura:\n%s", env.registro.String())
			}
			// Una segunda vuelta con Ventra sin la 1 NO la borra ni la vuelve a contar: ya está anulada.
			env.registro.Reset()
			env.ciclo()
			if !env.hay(env.exF("1", "2026-10-19")) || !env.estaAnulada(idC) {
				t.Fatalf("la anulada ya marcada no se borra en el ciclo siguiente\n%s", env.registro.String())
			}
			if !strings.Contains(env.registro.String(), "anuladasQuitadasDeRuta=0") || !strings.Contains(env.registro.String(), "retiradas=0") {
				t.Errorf("y no se vuelve a contar:\n%s", env.registro.String())
			}
		})
	}
}

// Rutas completadas y canceladas, y entregas con resultado: HISTORIAL. No se tocan, solo se cuentan.
func TestMotorReal_LoQueEsHistorialNoSeQuitaDeSuRuta(t *testing.T) {
	casos := []struct {
		nombre, estado, preparar string
	}{
		{"ruta completada", "completed", ``},
		{"ruta cancelada", "cancelled", ``},
		{"con resultado en ruta viva", "planned", `UPDATE orders SET resultado = 'entregado' WHERE id = $1`},
		{"entregada en ruta viva", "in_progress", `UPDATE orders SET delivered_at = now() WHERE id = $1`},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			env := nuevoEntornoReal(t)
			_, viva, idC, _, ruta := env.dosEnUnaRuta(c.estado)
			if c.preparar != "" {
				env.exec(c.preparar, idC)
			}
			env.ventra.poner(viva)
			env.registro.Reset()
			env.ciclo()
			if env.entero(`SELECT count(*) FROM orders WHERE id = $1 AND anulada_at IS NULL AND NOT archivado AND route_id = $2 AND ultima_ruta_id = $2 AND stop_order = 1`, idC, ruta) != 1 {
				t.Fatalf("%s: es historial, no se toca\n%s", c.nombre, env.registro.String())
			}
			if !strings.Contains(env.registro.String(), "anuladasConRuta=1") || !strings.Contains(env.registro.String(), "anuladasQuitadasDeRuta=0") {
				t.Errorf("%s: se deja y se cuenta\n%s", c.nombre, env.registro.String())
			}
		})
	}
}

// Sin ruta: se borra como siempre, sin aviso (nadie la vio en una ruta).
func TestMotorReal_LaAnuladaSinRutaSeBorraSinAviso(t *testing.T) {
	env := nuevoEntornoReal(t)
	env.sembrarEntregas(facturaDeMentira("1", "2026-10-19", "FA"), facturaDeMentira("2", "2026-10-19", "FB"))
	env.ventra.poner(facturaDeMentira("2", "2026-10-19", "FB"))
	env.ciclo()
	if env.hay(env.exF("1", "2026-10-19")) {
		t.Error("sin ruta se borra")
	}
	if env.entero(`SELECT count(*) FROM orders WHERE sucursal_codigo = $1 AND anulada_at IS NOT NULL`, env.codigo) != 0 {
		t.Error("y no deja ninguna marca de anulada: no hay nada que avisar")
	}
}

// LAS GUARDAS DE SIEMPRE siguen mandando con el nuevo camino: ventana, lista vacía y fallo de Ventra.
func TestMotorReal_LasGuardasDeLaRetiradaTambienFrenanLaAnulacion(t *testing.T) {
	env := nuevoEntornoReal(t)
	env.primerBarrido()
	// La 1 está dentro de la ventana del repaso (17-20/10); la 9 es del 01/06, fuera de toda ventana.
	vieja := facturaDeMentira("9", "2026-06-01", "FV")
	cancelada, viva := facturaDeMentira("1", "2026-10-19", "FA"), facturaDeMentira("2", "2026-10-19", "FB")
	env.sembrarEntregas(vieja, cancelada, viva)
	idV, idC, idViva := env.idDe(env.exF("9", "2026-06-01")), env.idDe(env.exF("1", "2026-10-19")), env.idDe(env.exF("2", "2026-10-19"))
	env.rutaEn("planned", idV, idC, idViva)
	nadie := func(que string) {
		t.Helper()
		if n := env.entero(`SELECT count(*) FROM orders WHERE sucursal_codigo = $1 AND (anulada_at IS NOT NULL OR route_id IS NULL)`, env.codigo); n != 0 {
			t.Fatalf("%s: NADIE se quita de su ruta, y se quitaron %d\n%s", que, n, env.registro.String())
		}
	}

	// Ventra falla: no es una anulación.
	env.ventra.mu.Lock()
	env.ventra.fallo = errFalsoDeVentra
	env.ventra.mu.Unlock()
	env.ciclo()
	nadie("con Ventra caído")

	// Ventra contesta VACÍO: una base caída contesta así, sin error.
	env.ventra.poner()
	env.ciclo()
	nadie("con la respuesta vacía")

	// Ventra contesta bien, sin la 1 ni la 9: la 1 (dentro de la ventana) se quita; la 9 (fuera) NO se juzga.
	env.ventra.poner(viva)
	env.ciclo()
	if !env.estaAnulada(idC) {
		t.Fatalf("la 1, dentro de la ventana, se quita de su ruta\n%s", env.registro.String())
	}
	if env.estaAnulada(idV) || env.entero(`SELECT count(*) FROM orders WHERE id = $1 AND route_id IS NOT NULL`, idV) != 1 {
		t.Error("la 9 cae FUERA de la ventana consultada: no se puede decir que ya no viene, y no se toca")
	}
}

// Si la factura REAPARECE, la misma fila se reactiva: sin duplicarse, sin marca, sin archivar, y SIN ruta
// (vuelve como cualquier entrega nueva: a «Sin colocar»).
func TestMotorReal_LaFacturaAnuladaQueReaparecesReactivaSinDuplicarse(t *testing.T) {
	env := nuevoEntornoReal(t)
	cancelada, viva, idC, _, _ := env.dosEnUnaRuta("planned")
	env.ventra.poner(viva)
	env.ciclo()
	if !env.estaAnulada(idC) {
		t.Fatalf("la siembra: tenía que estar anulada\n%s", env.registro.String())
	}

	env.ventra.poner(cancelada, viva) // Ventra la vuelve a mandar
	env.registro.Reset()
	if env.ciclo() < 1 {
		t.Fatalf("el ciclo tenía que guardar la que reaparece\n%s", env.registro.String())
	}
	if got := env.idDe(env.exF("1", "2026-10-19")); got != idC {
		t.Fatalf("es la MISMA fila (mismo id): era %s y ahora es %s", idC, got)
	}
	if env.entero(`SELECT count(*) FROM orders WHERE sucursal_codigo = $1`, env.codigo) != 2 {
		t.Fatal("no se duplica: siguen siendo dos filas")
	}
	if env.entero(`SELECT count(*) FROM orders WHERE id = $1 AND anulada_at IS NULL AND anulada_de_ruta_id IS NULL AND NOT archivado AND route_id IS NULL`, idC) != 1 {
		t.Error("reactivada: sin marca de anulada, sin archivar y sin ruta")
	}
	// Y vuelve a ser una entrega normal: si se cancela otra vez estando en una ruta, otra vez se quita.
	ruta2 := env.rutaEn("planned", idC)
	env.ventra.poner(viva)
	env.ciclo()
	if !env.estaAnulada(idC) {
		t.Error("la reactivada vuelve a poder anularse")
	}
	if peso, _, _ := env.pesoDeLaRuta(ruta2); peso != 0 {
		t.Errorf("y su ruta queda vacía: %v kg", peso)
	}
}

// El CHECK: una anulada que no estuviera archivada contaría en todas las listas.
func TestMotorReal_UnaAnuladaNoArchivadaNoExiste(t *testing.T) {
	env := nuevoEntornoReal(t)
	env.sembrarEntregas(facturaDeMentira("1", "2026-10-19", "FA"))
	id := env.idDe(env.exF("1", "2026-10-19"))
	if _, err := env.pool.Exec(env.ctx, `UPDATE orders SET anulada_at = now(), archivado = false WHERE id = $1`, id); err == nil {
		t.Fatal("la base tiene que negarse: anulada implica archivada")
	}
}

// NINGUNA LISTA NI CONTADOR LA CUENTA. Se ejecutan de verdad con dos entregas que cumplen TODO lo repartible (sin
// ruta, con punto, facturadas): la viva y la anulada, que sólo se distinguen por `archivado`/`anulada_at`. Cada
// consulta tiene que ver la viva (si no, la prueba no comprueba nada) y no la anulada.
func TestMotorReal_LaAnuladaNoCuentaEnNingunaListaNiContador(t *testing.T) {
	env := nuevoEntornoReal(t)
	_, viva, idC, idV, _ := env.dosEnUnaRuta("planned")
	env.ventra.poner(viva)
	env.ciclo()
	if !env.estaAnulada(idC) {
		t.Fatalf("la siembra: tenía que estar anulada\n%s", env.registro.String())
	}
	// La viva sale de su ruta; las dos con punto y factura que cuadra: todo lo repartible menos la regla.
	env.exec(`UPDATE orders SET route_id = NULL, ultima_ruta_id = NULL, stop_order = NULL WHERE id = $1`, idV)
	env.exec(`UPDATE orders SET end_lat = 20.1, end_lng = -75.8, lat = 20.1, lng = -75.8, factura_estado = 'igual', source = 'pedido'
	    WHERE id = ANY($1)`, []uuid.UUID{idC, idV})
	if env.entero(`SELECT count(*) FROM orders WHERE branch_id = $1 AND route_id IS NULL AND end_lat IS NOT NULL AND factura_estado = 'igual'`, env.branch) != 2 {
		t.Fatal("la siembra: las dos cumplen todo menos la regla")
	}

	soloLaViva := func(que string, ids []uuid.UUID) {
		t.Helper()
		var vio, vioLaAnulada bool
		for _, id := range ids {
			vio = vio || id == idV
			vioLaAnulada = vioLaAnulada || id == idC
		}
		if !vio || vioLaAnulada {
			t.Errorf("%s: tiene que ver la viva (%v) y NO la anulada (%v)", que, vio, vioLaAnulada)
		}
	}

	disp, err := env.acotado.ListarPedidosDisponibles(env.ctx, sqlc.ListarPedidosDisponiblesParams{Limite: 100})
	if err != nil {
		t.Fatal(err)
	}
	var ids []uuid.UUID
	for _, d := range disp {
		ids = append(ids, d.ID)
	}
	soloLaViva("ListarPedidosDisponibles", ids)
	if n, err := env.acotado.ContarPedidosDisponibles(env.ctx, sqlc.ContarPedidosDisponiblesParams{}); err != nil || n != int64(len(disp)) {
		t.Errorf("ContarPedidosDisponibles: %d (error %v) y la lista trae %d", n, err, len(disp))
	}

	sin, err := env.acotado.ListarPedidosSinColocar(env.ctx, sqlc.ListarPedidosSinColocarParams{BranchID: env.branch, Limite: 100})
	if err != nil {
		t.Fatal(err)
	}
	ids = nil
	for _, d := range sin {
		ids = append(ids, d.ID)
	}
	soloLaViva("ListarPedidosSinColocar", ids)
	if n, err := env.acotado.ContarPedidosSinColocar(env.ctx, sqlc.ContarPedidosSinColocarParams{BranchID: env.branch}); err != nil || n != int64(len(sin)) {
		t.Errorf("ContarPedidosSinColocar: %d (error %v) y la lista trae %d", n, err, len(sin))
	}

	panel, err := env.acotado.PanelResumen(env.ctx, medianocheDeHoy(env.ahora))
	if err != nil {
		t.Fatal(err)
	}
	var enLaBase int64
	_ = env.pool.QueryRow(env.ctx, `SELECT count(*) FROM orders WHERE branch_id = $1 AND NOT archivado AND route_id IS NULL`, env.branch).Scan(&enLaBase)
	if enLaBase != 1 {
		t.Fatalf("la siembra: una sola sin archivar en la sucursal de la prueba: %d", enLaBase)
	}
	// PanelResumen cuenta toda la base (la de pruebas puede traer otras sucursales): se compara contra lo que
	// hay SIN archivar, que es lo que tiene que contar.
	var sinArchivar, sinRuta int64
	_ = env.pool.QueryRow(env.ctx, `SELECT count(*), count(*) FILTER (WHERE route_id IS NULL AND end_lat IS NOT NULL AND factura_estado IN ('igual','cambiado'))
	    FROM orders WHERE NOT archivado`).Scan(&sinArchivar, &sinRuta)
	if panel.TotalPedidos != sinArchivar || panel.SinRuta != sinRuta {
		t.Errorf("PanelResumen cuenta %d pedidos y %d sin ruta; sin archivar hay %d y %d", panel.TotalPedidos, panel.SinRuta, sinArchivar, sinRuta)
	}
	filas, err := env.acotado.PanelPorSucursal(env.ctx)
	if err != nil {
		t.Fatal(err)
	}
	var panelDeLaSucursal int64
	for _, f := range filas {
		if f.BranchID.Valid && uuid.UUID(f.BranchID.Bytes) == env.branch {
			panelDeLaSucursal = f.Pedidos
		}
	}
	if panelDeLaSucursal != 1 {
		t.Errorf("PanelPorSucursal cuenta %d de la sucursal de la prueba y sólo la viva es repartible", panelDeLaSucursal)
	}

	// Y la bajada de los aparatos la manda como aviso y como «quitada», nunca como fila viva.
	// (La marca de la anulada es la hora de verdad de la base, no el reloj de mentira del espejo.)
	ahora := time.Now().UTC()
	v := alcance.VentanaDeBajada{Hasta: ahora.Add(time.Hour), Tope: 100}
	haceUnDia := ahora.Add(-24 * time.Hour)
	for nombre, desde := range map[string]*time.Time{"carga inicial": nil, "por diferencias": &haceUnDia} {
		v.Desde = desde
		filas, err := env.acotado.EspejoDiferenciasDePedidos(env.ctx, v)
		if err != nil {
			t.Fatal(err)
		}
		var vista bool
		for _, f := range filas {
			if f.ID == idC {
				vista = f.AnuladaAt.Valid && f.Archivado
			}
		}
		if !vista {
			t.Errorf("%s: la bajada tiene que traer la anulada (archivada y con su marca) para avisar", nombre)
		}
	}
	// Pasada la ventana de 7 días, la carga inicial ya no la trae: sólo se la sigue diciendo a quien la tenía viva.
	v.Desde, v.Hasta = nil, ahora.Add(8*24*time.Hour)
	filas2, err := env.acotado.EspejoDiferenciasDePedidos(env.ctx, v)
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range filas2 {
		if f.ID == idC {
			t.Error("pasados los 7 días la carga inicial ya no trae la anulada")
		}
	}
	// Otra sucursal no se entera.
	v.Hasta, v.Sucursal = ahora.Add(time.Hour), func() *uuid.UUID { u := uuid.New(); return &u }()
	filas3, _ := env.acotado.EspejoDiferenciasDePedidos(env.ctx, v)
	for _, f := range filas3 {
		if f.ID == idC {
			t.Error("pedir otra sucursal no ensancha nada: la anulada es de la mía")
		}
	}
}

var errFalsoDeVentra = &errDeVentra{"Ventra 500"}

type errDeVentra struct{ s string }

func (e *errDeVentra) Error() string { return e.s }
