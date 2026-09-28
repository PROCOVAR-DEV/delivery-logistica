package api

// EL ALCANCE DEL TABLERO, POR HTTP Y POR LOS CINCO ENDPOINTS QUE NO LO PIDEN.
//
// `GET /api/board` y `GET /api/board/unplaced` pasan por `tableroDe`, que resuelve el
// `branchId` y comprueba que la sucursal exista y sea del alcance. Los otros cinco NO:
//
//	PATCH  /api/board/columns/{id}
//	DELETE /api/board/columns/{id}
//	POST   /api/board/columns/{id}/route
//	PUT    /api/board/placements/{id}
//	DELETE /api/board/placements/{id}
//
// Llegan con un id a secas y sin sucursal por ninguna parte, así que su ÚNICA defensa es
// el `sqlc.narg('sucursal')` que pone `alcance/tablero.go` dentro del SQL. Estas pruebas
// van por ahí: Santiago con el id de una zona o una tarjeta de Holguín en la mano.
//
// Hasta el 18/09/2026 no las cazaba nadie, y no por falta de pruebas sino porque el doble
// de la base no miraba `arg.Sucursal`: se podían quitar las 24 apariciones de
// `Sucursal: a.sucursalPg()` y la suite seguía verde. La red de abajo, consulta por
// consulta, está en `internal/alcance/tablero_test.go`; ésta es la de arriba, la que
// comprueba que el montaje entero —router, portería, manejador y SQL— no se la deja.

import (
	"net/http"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

// La zona de Holguín y su tarjeta. Van aparte de `nuevoTablero()` a propósito: las pruebas
// de siempre no tienen por qué cambiar de escenario para que éstas existan.
var colHol = uuid.MustParse("c0000000-0000-0000-0000-0000000000f1")

func conHolguin(q *tableroFalso) *tableroFalso {
	q.columnas[colHol] = sqlc.BoardColumn{
		ID: colHol, BranchID: sucHol, Nombre: "Centro de Holguín", Posicion: 1,
	}
	q.colocadas[pedHol] = colocacion{colHol, 1}
	return q
}

// ---------------------------------------------------------------------------
// Los cinco endpoints sin `branchId`
// ---------------------------------------------------------------------------

func TestSantiagoNoRenombraLaZonaDeHolguin(t *testing.T) {
	q := conHolguin(nuevoTablero())
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPatch, "/api/board/columns/"+colHol.String(),
		tokenTab(t, sucStg.String()), `{"nombre":"Mía ahora"}`)

	if w.Code != http.StatusNotFound {
		t.Fatalf("PATCH a la zona de Holguín desde Santiago: código %d, se esperaba 404 — %s",
			w.Code, w.Body.String())
	}
	if n := q.columnas[colHol].Nombre; n != "Centro de Holguín" {
		t.Fatalf("la zona de Holguín se llama ahora «%s»: Santiago le escribió dentro", n)
	}
}

func TestSantiagoNoBorraLaZonaDeHolguin(t *testing.T) {
	q := conHolguin(nuevoTablero())
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodDelete, "/api/board/columns/"+colHol.String()+"?vaciar=1",
		tokenTab(t, sucStg.String()), "")

	if w.Code != http.StatusNotFound {
		t.Fatalf("DELETE de la zona de Holguín desde Santiago: código %d, se esperaba 404 — %s",
			w.Code, w.Body.String())
	}
	if _, sigue := q.columnas[colHol]; !sigue {
		t.Fatal("Santiago borró la zona de Holguín")
	}
	if _, sigue := q.colocadas[pedHol]; !sigue {
		t.Fatal("Santiago vació el tablero de Holguín: la tarjeta ya no está puesta")
	}
}

func TestSantiagoNoArmaLaRutaDeLaZonaDeHolguin(t *testing.T) {
	q := conHolguin(nuevoTablero())
	q.capacidad = 1000
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colHol.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)

	if w.Code != http.StatusNotFound {
		t.Fatalf("armar la ruta de la zona de Holguín desde Santiago: código %d, se "+
			"esperaba 404 — %s", w.Code, w.Body.String())
	}
	if q.rutaCreada != nil {
		t.Fatalf("Santiago armó una ruta con los pedidos de Holguín: %+v", q.rutaCreada)
	}
	if _, sigue := q.colocadas[pedHol]; !sigue {
		t.Fatal("la tarjeta de Holguín salió de su tablero")
	}
}

func TestSantiagoNoColocaUnaTarjetaEnLaZonaDeHolguin(t *testing.T) {
	q := conHolguin(nuevoTablero())
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPut, "/api/board/placements/"+ped1.String(),
		tokenTab(t, sucStg.String()), `{"columnaId":"`+colHol.String()+`","posicion":1}`)

	if w.Code != http.StatusNotFound {
		t.Fatalf("colocar en la zona de Holguín desde Santiago: código %d, se esperaba "+
			"404 — %s", w.Code, w.Body.String())
	}
	if c, puesto := q.colocadas[ped1]; puesto {
		t.Fatalf("un pedido de Santiago acabó en el tablero de Holguín: %+v", c)
	}
	// Y la tarjeta que sí era de Holguín no se movió de sitio: el `AbrirHueco` de la
	// transacción tampoco puede correr las posiciones de un tablero ajeno.
	if q.colocadas[pedHol] != (colocacion{colHol, 1}) {
		t.Fatalf("se corrieron las posiciones del tablero de Holguín: %+v", q.colocadas[pedHol])
	}
}

func TestSantiagoNoQuitaLaTarjetaDeHolguin(t *testing.T) {
	q := conHolguin(nuevoTablero())
	h := montarTab(t, q)

	// Quitar es REAPLICABLE: «lo que ya no está» contesta 200 y no es un error. Lo que
	// esta prueba mira no es el código, es si la tarjeta sigue puesta en Holguín.
	w := pedirTab(t, h, http.MethodDelete, "/api/board/placements/"+pedHol.String(),
		tokenTab(t, sucStg.String()), "")

	if w.Code >= 500 {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if _, sigue := q.colocadas[pedHol]; !sigue {
		t.Fatal("Santiago sacó del tablero una tarjeta de Holguín sabiendo su id de pedido")
	}
	if quitado, _ := leerTab(t, w)["quitado"].(bool); quitado {
		t.Fatal("la respuesta dice que quitó algo, y lo que había que quitar no era suyo")
	}
}

// Y el tablero de Santiago no enseña nada de Holguín aunque las dos zonas existan.
func TestElTableroDeSantiagoNoTraeNadaDeHolguin(t *testing.T) {
	q := conHolguin(nuevoTablero())
	q.tresPuestas()
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodGet, "/api/board", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if contieneDeInforme(w.Body.String(), "Holguín") || contieneDeInforme(w.Body.String(), "De Holguín") {
		t.Fatalf("el tablero de Santiago trae cosas de Holguín: %s", w.Body.String())
	}
}

// ---------------------------------------------------------------------------
// EL CAMIÓN DE OTRA SUCURSAL
// ---------------------------------------------------------------------------
//
// `vehiculoDelCuerpo` sólo comprobaba que el `vehiculoId` fuese un uuid. Con eso, un
// `PATCH /api/board/columns/{suya}` con el id del camión de otra sucursal contestaba 200 y
// se guardaba; después `ListarColumnasDelTablero` —`LEFT JOIN vehicles` SIN condición de
// sucursal— servía su nombre, su matrícula y su capacidad en cada `GET /api/board`, y al
// armar la ruta ese mismo id pisaba al de la columna y llegaba tal cual a `CrearRuta`.
//
// Son tres puertas —crear la zona, tocarla, y armar su ruta— y las tres se prueban.

func TestElCamionDeHolguinNoSeGuardaEnUnaZonaDeSantiago(t *testing.T) {
	q := nuevoTablero()
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPatch, "/api/board/columns/"+colCentro.String(),
		tokenTab(t, sucStg.String()), `{"vehiculoId":"`+vehHolTab.String()+`"}`)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d, se esperaba 400: el camión de Holguín no se engancha a una "+
			"zona de Santiago ni sabiendo su id — %s", w.Code, w.Body.String())
	}
	// SE COMPRUEBA QUE SIGA CON EL SUYO, no que se quede vacía.
	//
	// Antes esto era `if v.Valid { … }`, y valía mientras la zona naciera sin camión. Desde
	// el 28/09/2026 `colCentro` nace con el de Santiago —lo pide `msgZonaSinCamion`, que se
	// niega a armar una zona sin camión— y «vacía» dejaría de ser la respuesta correcta:
	// un PATCH rechazado no puede DESENGANCHAR el camión bueno, que sería el mismo fallo
	// con otra cara (la zona se queda sin poder armar por un intento que se denegó).
	if v := q.columnas[colCentro].VehicleID; !v.Valid || uuid.UUID(v.Bytes) != vehStgTab {
		t.Fatalf("la zona de Santiago tenía que quedarse con SU camión (%s) y tiene %v",
			vehStgTab, v)
	}
}

func TestCrearUnaZonaConElCamionDeOtraSucursalNoCuela(t *testing.T) {
	q := nuevoTablero()
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns", tokenTab(t, sucStg.String()),
		`{"nombre":"Reparto Norte","vehiculoId":"`+vehHolTab.String()+`"}`)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d, se esperaba 400: %s", w.Code, w.Body.String())
	}
	if len(q.creadas) != 0 {
		t.Fatalf("se creó la zona igual, con el camión de otra sucursal dentro: %v", q.creadas)
	}
}

func TestArmarLaRutaConElCamionDeOtraSucursalNoCuela(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.capacidad = 1000
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{"vehiculoId":"`+vehHolTab.String()+`"}`)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d, se esperaba 400: %s", w.Code, w.Body.String())
	}
	if q.rutaCreada != nil {
		t.Fatalf("la ruta se creó con el camión de Holguín dentro: %+v", q.rutaCreada.VehicleID)
	}
	if len(q.colocadas) != 3 {
		t.Fatal("y encima se vació la columna")
	}
}

// EL SEGUNDO CIERRE: la columna que YA tenía guardado un camión ajeno.
//
// Las zonas tocadas antes del 18/09/2026 pueden llevar dentro el camión de otra sucursal,
// porque entonces el `PATCH` lo aceptaba. Arreglar sólo la puerta de entrada dejaría a esas
// columnas pariendo rutas con el camión de otro hasta que alguien las repasara a mano.
func TestUnaZonaConUnCamionAjenoYaGuardadoNoParieUnaRuta(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.capacidad = 1000
	c := q.columnas[colCentro]
	c.VehicleID = pgtype.UUID{Bytes: [16]byte(vehHolTab), Valid: true}
	q.columnas[colCentro] = c
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d, se esperaba 400: la zona llevaba guardado el camión de "+
			"Holguín y la ruta salió con él dentro — %s", w.Code, w.Body.String())
	}
	if q.rutaCreada != nil {
		t.Fatalf("se creó la ruta: %+v", q.rutaCreada.VehicleID)
	}
}

// Y EL CASO BUENO, que es la otra mitad: el camión propio sí se engancha. Sin esta prueba,
// «prohibirlo todo» pasaría por arreglo.
func TestElCamionDeSantiagoSiSeEnganchaAUnaZonaDeSantiago(t *testing.T) {
	q := nuevoTablero()
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPatch, "/api/board/columns/"+colCentro.String(),
		tokenTab(t, sucStg.String()), `{"vehiculoId":"`+vehStgTab.String()+`"}`)

	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	v := q.columnas[colCentro].VehicleID
	if !v.Valid || uuid.UUID(v.Bytes) != vehStgTab {
		t.Fatalf("no se guardó el camión propio: %+v", v)
	}
}

// Un `vehiculoId` vacío sigue siendo «quítamelo», no «no existe»: son dos órdenes
// distintas y las dos llegan con el campo en blanco.
func TestElVehiculoVacioSigueDesenganchando(t *testing.T) {
	q := nuevoTablero()
	c := q.columnas[colCentro]
	c.VehicleID = pgtype.UUID{Bytes: [16]byte(vehStgTab), Valid: true}
	q.columnas[colCentro] = c
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPatch, "/api/board/columns/"+colCentro.String(),
		tokenTab(t, sucStg.String()), `{"vehiculoId":null}`)

	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if q.columnas[colCentro].VehicleID.Valid {
		t.Fatal("no se desenganchó el camión")
	}
}
