package api

// INACTIVAR Y ACTIVAR ZONAS DEL TABLERO (00022, 1.0.38), de punta a punta por HTTP.
//
// EL MISMO ESCENARIO CORRE DOS VECES: contra el doble de la base (`tableroFalso`) y contra
// Postgres de verdad (`TestMotorReal_ZonasInactivas`, sólo con `REPARTO_MOTOR_REAL_DSN`, en una
// transacción que se revierte). Un doble que reimplementa el SQL no ve el SQL: que la lista, el
// contador, el mover y el colocar digan lo mismo de una zona apagada lo dice la base.
//
// Cada «no» va con su pareja: la zona activa SÍ sale, SÍ admite tarjetas, SÍ arma.

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"procovar/reparto-api/internal/store/sqlc"
)

type mundoDeZonas struct {
	h        http.Handler
	jwt      string      // un logístico de la sucursal
	jwtOtra  string      // un logístico de OTRA sucursal
	pedidos  []uuid.UUID // tres pedidos colocables de la sucursal
	tarjetas func() int  // cuántas tarjetas hay puestas en total (en la base, no en la respuesta)
}

func (m mundoDeZonas) pedir(t *testing.T, metodo, ruta, jwt, cuerpo string) (int, map[string]any) {
	t.Helper()
	w := pedirTab(t, m.h, metodo, ruta, jwt, cuerpo)
	var salida map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &salida)
	return w.Code, salida
}

// zonas devuelve «nombre» -> la fila de columna que trae GET /api/board.
func zonasDelTablero(t *testing.T, m mundoDeZonas, query string) (map[string]map[string]any, int64) {
	t.Helper()
	cod, cuerpo := m.pedir(t, http.MethodGet, "/api/board"+query, m.jwt, "")
	if cod != http.StatusOK {
		t.Fatalf("GET /api/board%s: %d %v", query, cod, cuerpo)
	}
	salida := map[string]map[string]any{}
	for _, c := range cuerpo["columnas"].([]any) {
		f := c.(map[string]any)
		salida[f["nombre"].(string)] = f
	}
	return salida, int64(cuerpo["sinColocar"].(map[string]any)["total"].(float64))
}

func (m mundoDeZonas) crearZona(t *testing.T, nombre string) string {
	t.Helper()
	cod, cuerpo := m.pedir(t, http.MethodPost, "/api/board/columns", m.jwt, `{"nombre":"`+nombre+`"}`)
	if cod != http.StatusCreated {
		t.Fatalf("crear «%s»: %d %v", nombre, cod, cuerpo)
	}
	if cuerpo["activa"] != true {
		t.Fatalf("una zona nueva tiene que nacer activa: %v", cuerpo)
	}
	return cuerpo["id"].(string)
}

func (m mundoDeZonas) colocar(t *testing.T, pedido uuid.UUID, zona string) (int, map[string]any) {
	t.Helper()
	return m.pedir(t, http.MethodPut, "/api/board/placements/"+pedido.String(), m.jwt,
		`{"columnaId":"`+zona+`","posicion":1}`)
}

func (m mundoDeZonas) activa(t *testing.T, zona string, valor bool) (int, map[string]any) {
	t.Helper()
	cuerpo := `{"activa":false}`
	if valor {
		cuerpo = `{"activa":true}`
	}
	return m.pedir(t, http.MethodPatch, "/api/board/columns/"+zona, m.jwt, cuerpo)
}

func esperar(t *testing.T, que string, cod int, quiero int) {
	t.Helper()
	if cod != quiero {
		t.Fatalf("%s: código %d, se esperaba %d", que, cod, quiero)
	}
}

func escenarioDeZonasInactivas(t *testing.T, m mundoDeZonas) {
	norte := m.crearZona(t, "Norte")
	sur := m.crearZona(t, "Sur")
	esperar(t, "colocar en la activa", func() int { c, _ := m.colocar(t, m.pedidos[0], norte); return c }(), http.StatusOK)
	esperar(t, "colocar en la activa", func() int { c, _ := m.colocar(t, m.pedidos[1], norte); return c }(), http.StatusOK)

	zonas, sinColocar := zonasDelTablero(t, m, "")
	if len(zonas) != 2 || zonas["Norte"]["activa"] != true || zonas["Norte"]["pedidos"].(float64) != 2 || sinColocar != 1 {
		t.Fatalf("antes de inactivar: zonas=%v sinColocar=%d", zonas, sinColocar)
	}

	// --- Inactivar: los pedidos vuelven a «Sin colocar» y la zona sale de la lista ----------
	cod, cuerpo := m.activa(t, norte, false)
	esperar(t, "inactivar", cod, http.StatusOK)
	if cuerpo["activa"] != false || cuerpo["id"] != norte {
		t.Fatalf("inactivar tiene que devolver la zona apagada: %v", cuerpo)
	}
	zonas, sinColocar = zonasDelTablero(t, m, "")
	if _, sigue := zonas["Norte"]; sigue || len(zonas) != 1 {
		t.Fatalf("la zona inactiva sigue en GET /api/board: %v", zonas)
	}
	if sinColocar != 3 {
		t.Fatalf("Sin colocar = %d y tienen que ser 3 (los 2 devueltos + el que ya estaba)", sinColocar)
	}
	if n := m.tarjetas(); n != 0 {
		t.Fatalf("quedan %d tarjetas puestas tras inactivar la única zona con pedidos", n)
	}
	// ... y `?incluirInactivas=1` la trae, vacía y apagada.
	zonas, _ = zonasDelTablero(t, m, "?incluirInactivas=1")
	if z, hay := zonas["Norte"]; !hay || z["activa"] != false || z["pedidos"].(float64) != 0 {
		t.Fatalf("incluirInactivas=1 no trae la zona apagada, vacía: %v", zonas)
	}
	if zonas["Sur"]["activa"] != true {
		t.Fatalf("la zona activa tiene que decir activa:true: %v", zonas["Sur"])
	}

	// --- La bajada del aparato -----------------------------------------------------------------
	ayer := time.Now().Add(-24 * time.Hour).UTC().Format(time.RFC3339)
	columnasDeLaBajada := func(query string) (puestos map[string]map[string]any, quitados []any) {
		t.Helper()
		cod, cuerpo := m.pedir(t, http.MethodGet, "/api/sync/cambios"+query, m.jwt, "")
		esperar(t, "GET /api/sync/cambios"+query, cod, http.StatusOK)
		col := cuerpo["cambios"].(map[string]any)["boardColumns"].(map[string]any)
		puestos = map[string]map[string]any{}
		for _, p := range col["puestos"].([]any) {
			f := p.(map[string]any)
			puestos[f["nombre"].(string)] = f
		}
		return puestos, col["quitados"].([]any)
	}
	puestos, quitados := columnasDeLaBajada("")
	if _, hay := puestos["Norte"]; hay || puestos["Sur"]["activa"] != true || len(quitados) != 0 {
		t.Fatalf("carga inicial: puestos=%v quitados=%v (la apagada no baja)", puestos, quitados)
	}
	puestos, _ = columnasDeLaBajada("?incluirInactivas=1")
	if z, hay := puestos["Norte"]; !hay || z["activa"] != false {
		t.Fatalf("la carga con incluirInactivas=1 tiene que traer la apagada con activa:false: %v", puestos)
	}
	// Con marca: el aparato que ya tenía «Norte» se entera de que se apagó por `quitados`.
	puestos, quitados = columnasDeLaBajada("?desde=" + ayer)
	if _, hay := puestos["Norte"]; hay {
		t.Fatalf("la apagada bajó en `puestos`: %v", puestos)
	}
	if len(quitados) != 1 || quitados[0] != norte {
		t.Fatalf("el aparato no se entera de que la zona se apagó: quitados=%v", quitados)
	}
	// Una apagada que NO cambió desde la marca no vuelve a mandarse.
	futuro := time.Now().Add(time.Hour).UTC().Format(time.RFC3339)
	if _, quitados = columnasDeLaBajada("?desde=" + futuro); len(quitados) != 0 {
		t.Fatalf("una zona apagada que no cambió desde la marca no se manda: %v", quitados)
	}

	// --- Lo que una zona inactiva NO hace -------------------------------------------------------
	motivo := "La zona «Norte» está inactiva"
	cod, cuerpo = m.colocar(t, m.pedidos[0], norte)
	esperar(t, "colocar en la inactiva", cod, http.StatusConflict)
	if cuerpo["error"] != motivo {
		t.Fatalf("motivo de colocar en la inactiva: %v", cuerpo["error"])
	}
	if n := m.tarjetas(); n != 0 {
		t.Fatalf("se colocó una tarjeta en una zona inactiva (%d)", n)
	}
	cod, cuerpo = m.pedir(t, http.MethodPost, "/api/board/columns/"+norte+"/route", m.jwt, `{}`)
	esperar(t, "armar la ruta de la inactiva", cod, http.StatusConflict)
	if cuerpo["error"] != motivo {
		t.Fatalf("motivo de armar en la inactiva: %v", cuerpo["error"])
	}
	// Ni destino de un mover: borrar «Sur» con tarjetas hacia la apagada.
	if c, _ := m.colocar(t, m.pedidos[2], sur); c != http.StatusOK {
		t.Fatalf("colocar en la activa: %d", c)
	}
	cod, cuerpo = m.pedir(t, http.MethodDelete, "/api/board/columns/"+sur+"?destino="+norte, m.jwt, "")
	esperar(t, "mover a la inactiva al borrar", cod, http.StatusConflict)
	if cuerpo["error"] != motivo {
		t.Fatalf("motivo de mover a la inactiva: %v", cuerpo["error"])
	}
	if n := m.tarjetas(); n != 1 {
		t.Fatalf("el borrado fallido movió tarjetas (%d)", n)
	}
	// Y renombrar la inactiva no la reactiva.
	cod, cuerpo = m.pedir(t, http.MethodPatch, "/api/board/columns/"+norte, m.jwt, `{"nombre":"Norte"}`)
	esperar(t, "renombrar la inactiva", cod, http.StatusOK)
	if cuerpo["activa"] != false {
		t.Fatalf("renombrar reactivó la zona: %v", cuerpo)
	}

	// --- Alcance: otra sucursal ni la ve ni la toca -----------------------------------------
	cod, _ = m.pedir(t, http.MethodPatch, "/api/board/columns/"+norte, m.jwtOtra, `{"activa":true}`)
	esperar(t, "reactivar la zona de otra sucursal", cod, http.StatusNotFound)
	zonas, _ = zonasDelTablero(t, m, "?incluirInactivas=1")
	if zonas["Norte"]["activa"] != false {
		t.Fatalf("otra sucursal reactivó la zona: %v", zonas["Norte"])
	}

	// --- Reactivar: vuelve a salir, vacía, y admite tarjetas ---------------------------------
	cod, cuerpo = m.activa(t, norte, true)
	esperar(t, "reactivar", cod, http.StatusOK)
	if cuerpo["activa"] != true {
		t.Fatalf("reactivar: %v", cuerpo)
	}
	zonas, sinColocar = zonasDelTablero(t, m, "")
	if z, hay := zonas["Norte"]; !hay || z["activa"] != true || z["pedidos"].(float64) != 0 {
		t.Fatalf("la reactivada tiene que salir, activa y vacía: %v", zonas)
	}
	if sinColocar != 2 {
		t.Fatalf("Sin colocar = %d tras reactivar (los pedidos NO vuelven solos) y eran 2", sinColocar)
	}
	esperar(t, "colocar en la reactivada", func() int { c, _ := m.colocar(t, m.pedidos[0], norte); return c }(), http.StatusOK)

	// --- Borrar una zona inactiva funciona igual -------------------------------------------------
	cod, _ = m.activa(t, sur, false)
	esperar(t, "inactivar Sur", cod, http.StatusOK)
	cod, cuerpo = m.pedir(t, http.MethodDelete, "/api/board/columns/"+sur, m.jwt, "")
	esperar(t, "borrar una zona inactiva (vacía)", cod, http.StatusOK)
	if _, sinColocar = zonasDelTablero(t, m, ""); sinColocar != 2 {
		t.Fatalf("Sin colocar = %d y eran 2 (el de Sur volvió al apagarla)", sinColocar)
	}
	// El 409 de borrar con pedidos sigue como estaba.
	cod, cuerpo = m.pedir(t, http.MethodDelete, "/api/board/columns/"+norte, m.jwt, "")
	esperar(t, "borrar con pedidos sin destino ni vaciar", cod, http.StatusConflict)
	if !strings.Contains(cuerpo["error"].(string), "tiene 1 pedidos puestos") {
		t.Fatalf("el 409 de borrar con pedidos cambió: %v", cuerpo)
	}
	// Un PATCH con `activa` que no es booleano es un 400, no se ignora.
	cod, _ = m.pedir(t, http.MethodPatch, "/api/board/columns/"+norte, m.jwt, `{"activa":"si"}`)
	esperar(t, "activa que no es booleano", cod, http.StatusBadRequest)
}

func TestLasZonasInactivasConElDoble(t *testing.T) {
	q := nuevoEspejo()
	// El escenario crea sus zonas por la API: se parte de un tablero sin las de siempre.
	q.columnas = map[uuid.UUID]sqlc.BoardColumn{}
	h := montarTab(t, q)
	escenarioDeZonasInactivas(t, mundoDeZonas{
		h: h, jwt: tokenTab(t, sucStg.String()), jwtOtra: tokenTab(t, sucHol.String()),
		pedidos:  []uuid.UUID{ped1, ped2, ped3},
		tarjetas: func() int { return len(q.colocadas) },
	})
}

func TestMotorReal_ZonasInactivas(t *testing.T) {
	dsn := os.Getenv("REPARTO_MOTOR_REAL_DSN")
	if dsn == "" {
		t.Skip("requiere PostgreSQL aislado REPARTO_MOTOR_REAL_DSN")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	var base string
	if err := pool.QueryRow(ctx, "SELECT current_database()").Scan(&base); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(base, "verif") && !strings.Contains(base, "test") && !strings.Contains(base, "prueba") {
		t.Fatalf("la base %q no parece aislada (debe llamarse verif…, …test… o …prueba…): no se toca", base)
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = tx.Rollback(context.Background()) }()

	// Ids y códigos PROPIOS de esta prueba: la base puede tener datos de otras.
	id := func(sql string, args ...any) uuid.UUID {
		t.Helper()
		var u uuid.UUID
		if err := tx.QueryRow(ctx, sql, args...).Scan(&u); err != nil {
			t.Fatalf("siembra %q: %v", sql, err)
		}
		return u
	}
	codigo := "ZI" + strings.ToUpper(uuid.NewString()[:6])
	suc := id(`INSERT INTO branches (name, lat, lng, external_id) VALUES ($1, 0, 0, $2) RETURNING id`,
		"suc-"+uuid.NewString(), codigo)
	otra := id(`INSERT INTO branches (name, lat, lng) VALUES ($1, 0, 0) RETURNING id`, "suc-"+uuid.NewString())
	pedidos := make([]uuid.UUID, 3)
	for i := range pedidos {
		pedidos[i] = id(`
INSERT INTO orders (customer_name, address, weight, branch_id, source, external_id, end_lat, end_lng,
                    requiere_domicilio, factura_estado, factura_domicilio, pedido_costo, trip_leg)
VALUES ($1, 'calle 1', 1, $2, 'pedido', $3, 21.5, -77.9, true, 'igual', 5, 10, 'outbound') RETURNING id`,
			"zi-"+uuid.NewString()[:8], suc, "ext-"+uuid.NewString())
	}

	conAccesos(t, &accesosFalso{sucursales: []SucursalConAlmacenes{
		{Codigo: codigo, Nombre: "Zonas", Almacenes: []Almacen{
			{Nombre: "Almacén principal", Principal: true, Activo: true,
				Latitud: flotante(20.0247), Longitud: flotante(-75.8219)},
		}},
	}})
	h := montarTab(t, sqlc.New(tx))
	escenarioDeZonasInactivas(t, mundoDeZonas{
		h: h, jwt: tokenTab(t, suc.String()), jwtOtra: tokenTab(t, otra.String()),
		pedidos: pedidos,
		tarjetas: func() int {
			var n int
			if err := tx.QueryRow(ctx, `SELECT count(*) FROM board_placements p JOIN board_columns c ON c.id = p.column_id
			                            WHERE c.branch_id = $1`, suc).Scan(&n); err != nil {
				t.Fatal(err)
			}
			return n
		},
	})
}
