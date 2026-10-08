package api

import (
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

func textoDeInforme(s string) *string { return &s }

func filaDeInforme(cliente string, ingreso, peso float64, vehiculo *uuid.UUID, nombreVeh string) sqlc.ListarPedidosParaInformeRow {
	f := sqlc.ListarPedidosParaInformeRow{
		ID: uuid.New(), CustomerName: cliente, Address: "una calle",
		Weight: peso, Ingreso: ingreso,
		CreatedAt: pgtype.Timestamptz{Time: time.Now(), Valid: true},
	}
	if vehiculo != nil {
		f.VehiculoID = pgDePanel(*vehiculo)
		f.VehiculoNombre = textoDeInforme(nombreVeh)
	}
	return f
}

// Los tres bloques de la respuesta salen de la MISMA lectura, así que tienen que sumar lo
// mismo. Aquí se comprueba justo eso, y que un pedido sin camión cuente en el resumen
// aunque no aparezca en el reparto por vehículo.
func TestInformeSumaLoMismoEnSusTresBloques(t *testing.T) {
	camion := uuid.New()
	q := &dobleDePanel{informe: []sqlc.ListarPedidosParaInformeRow{
		filaDeInforme("Ana", 100, 10, &camion, "Camión 1"),
		filaDeInforme("Beto", 50, 5, &camion, "Camión 1"),
		// Sin camión: cuenta en el resumen y en el detalle, NO en byVehicle.
		filaDeInforme("Caro", 25, 2.5, nil, ""),
	}}
	h := montarDePanel(t, q)

	w := pedirDePanel(t, h, "/api/reports", tokenDePanel(t, map[string]any{"sub": "u1", "role": "SUPER ADMIN"}))
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	inf := leerJSONDePanel[InformeSalida](t, w)

	if len(inf.Orders) != 3 || inf.Summary.TotalOrders != 3 {
		t.Fatalf("el detalle trae %d pedidos y el resumen dice %d", len(inf.Orders), inf.Summary.TotalOrders)
	}
	if inf.Summary.TotalRevenue != 175 || inf.Summary.TotalWeight != 17.5 {
		t.Errorf("los totales no cuadran: %+v", inf.Summary)
	}
	// 175 / 3
	if esperado := 175.0 / 3.0; inf.Summary.AvgPrice != esperado {
		t.Errorf("la media es %v, se esperaba %v", inf.Summary.AvgPrice, esperado)
	}
	if len(inf.ByVehicle) != 1 {
		t.Fatalf("byVehicle trae %d filas, se esperaba 1 (el pedido sin camión no cuenta)", len(inf.ByVehicle))
	}
	v := inf.ByVehicle[0]
	if v.Name != "Camión 1" || v.Count != 2 || v.Revenue != 150 || v.Weight != 15 {
		t.Errorf("la fila del camión es %+v", v)
	}
	// El ingreso ya resuelto viaja en `price`: la columna de la tabla y el total salen del
	// mismo número, que es lo que en delivery no pasaba.
	if inf.Orders[0].Price != 100 {
		t.Errorf("el ingreso del primer pedido es %v, se esperaba 100", inf.Orders[0].Price)
	}
}

// Dos camiones que se llaman igual y sin matrícula son DOS camiones. Agrupar por el texto
// los juntaría en una fila con el doble de ingresos y desde fuera no se vería.
func TestInformeAgrupaPorIdDeVehiculoYNoPorNombre(t *testing.T) {
	unoDeStg, unoDeHol := uuid.New(), uuid.New()
	q := &dobleDePanel{informe: []sqlc.ListarPedidosParaInformeRow{
		filaDeInforme("Ana", 100, 10, &unoDeStg, "Camión 1"),
		filaDeInforme("Beto", 40, 4, &unoDeHol, "Camión 1"),
	}}
	h := montarDePanel(t, q)

	w := pedirDePanel(t, h, "/api/reports", tokenDePanel(t, map[string]any{"sub": "super", "role": "SUPER ADMIN"}))
	inf := leerJSONDePanel[InformeSalida](t, w)

	if len(inf.ByVehicle) != 2 {
		t.Fatalf("byVehicle trae %d filas, se esperaban 2: son dos camiones distintos con el mismo nombre", len(inf.ByVehicle))
	}
	if inf.ByVehicle[0].Revenue != 100 || inf.ByVehicle[1].Revenue != 40 {
		t.Errorf("los ingresos se mezclaron: %+v", inf.ByVehicle)
	}
}

// Un informe vacío tiene que dar cuatro ceros y dos listas vacías, no un null ni un NaN:
// `NaN` no es JSON válido y la respuesta saldría cortada a la mitad.
func TestInformeVacioNoDaNaNNiNull(t *testing.T) {
	h := montarDePanel(t, &dobleDePanel{})
	w := pedirDePanel(t, h, "/api/reports", tokenDePanel(t, map[string]any{"sub": "u1", "role": "SUPER ADMIN"}))
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if cuerpo := w.Body.String(); contieneDeInforme(cuerpo, "NaN") || contieneDeInforme(cuerpo, "null") {
		t.Errorf("la respuesta trae NaN o null: %s", cuerpo)
	}
	inf := leerJSONDePanel[InformeSalida](t, w)
	if inf.Summary.AvgPrice != 0 || inf.Summary.TotalOrders != 0 {
		t.Errorf("el resumen vacío es %+v", inf.Summary)
	}
	if inf.Orders == nil || inf.ByVehicle == nil {
		t.Error("las listas vacías salieron como null")
	}
}

func contieneDeInforme(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}

// El rango va en UTC y `to` incluye el día entero. Con la zona del proceso, el mismo mes
// daría dos informes distintos según desde dónde se pida.
func TestInformeInterpretaElRangoEnUTCYHastaIncluyeElDia(t *testing.T) {
	q := &dobleDePanel{}
	h := montarDePanel(t, q)

	w := pedirDePanel(t, h, "/api/reports?from=2026-09-01&to=2026-09-30", tokenDePanel(t, map[string]any{"sub": "u1", "role": "SUPER ADMIN"}))
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}

	desde := q.argInforme.Desde
	if !desde.Valid || !desde.Time.Equal(time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)) {
		t.Errorf("«desde» llegó como %v", desde.Time)
	}
	hasta := q.argInforme.Hasta
	esperado := time.Date(2026, 9, 30, 23, 59, 59, int(999*time.Millisecond), time.UTC)
	if !hasta.Valid || !hasta.Time.Equal(esperado) {
		t.Errorf("«hasta» llegó como %v, se esperaba %v", hasta.Time, esperado)
	}
}

func TestInformeSinRangoNoFiltraPorFecha(t *testing.T) {
	q := &dobleDePanel{}
	h := montarDePanel(t, q)
	pedirDePanel(t, h, "/api/reports", tokenDePanel(t, map[string]any{"sub": "u1", "role": "SUPER ADMIN"}))

	if q.argInforme.Desde.Valid || q.argInforme.Hasta.Valid {
		t.Errorf("sin rango no se puede filtrar por fecha: %+v", q.argInforme)
	}
}

// Una fecha o un id que no se entienden son un 400, NO un filtro que se ignora: ignorarlos
// devuelve el histórico entero —o un informe vacío— con un 200, y eso se lo cree cualquiera.
func TestInformeRechazaLosFiltrosQueNoSeEntienden(t *testing.T) {
	h := montarDePanel(t, &dobleDePanel{})
	jwt := tokenDePanel(t, map[string]any{"sub": "u1", "role": "SUPER ADMIN"})

	for _, ruta := range []string{
		"/api/reports?from=el-lunes",
		"/api/reports?to=30-09-2026",
		"/api/reports?vehicleId=camion-1",
	} {
		w := pedirDePanel(t, h, ruta, jwt)
		if w.Code != http.StatusBadRequest {
			t.Errorf("%s devolvió %d, se esperaba 400: %s", ruta, w.Code, w.Body.String())
		}
	}
}

func TestInformeAceptaElVehiculoYLoPasaALaConsulta(t *testing.T) {
	camion := uuid.New()
	q := &dobleDePanel{}
	h := montarDePanel(t, q)

	w := pedirDePanel(t, h, "/api/reports?vehicleId="+camion.String(), tokenDePanel(t, map[string]any{"sub": "u1", "role": "SUPER ADMIN"}))
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if !q.argInforme.VehiculoID.Valid || uuid.UUID(q.argInforme.VehiculoID.Bytes) != camion {
		t.Errorf("el vehículo no llegó a la consulta: %v", q.argInforme.VehiculoID)
	}
}

// El informe es un fichero que sale de la casa: el alcance lo pone el paquete `alcance` y
// no se puede pedir sin él.
func TestInformeVaAcotadoALaSucursal(t *testing.T) {
	q := &dobleDePanel{}
	h := montarDePanel(t, q)

	pedirDePanel(t, h, "/api/reports", tokenDePanel(t, map[string]any{"sub": "u1", "role": "LOGISTICO", "branchId": stgDePanel.String()}))
	if len(q.sucursalVista) != 1 {
		t.Fatalf("el informe hizo %d consultas, se esperaba 1", len(q.sucursalVista))
	}
	if s := q.sucursalVista[0]; !s.Valid || uuid.UUID(s.Bytes) != stgDePanel {
		t.Errorf("el informe llegó con la sucursal %v, se esperaba Santiago", s)
	}
}

func TestInformeSinSesionEs401(t *testing.T) {
	h := montarDePanel(t, &dobleDePanel{})
	w := pedirDePanel(t, h, "/api/reports", "")
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("código %d, se esperaba 401", w.Code)
	}
	if e := leerJSONDePanel[httpx.CuerpoError](t, w); e.Error != httpx.MsgNoAutorizado {
		t.Errorf("el cuerpo del 401 es %q", e.Error)
	}
}
