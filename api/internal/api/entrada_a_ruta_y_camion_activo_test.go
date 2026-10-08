package api

// LA REGLA DE ENTRADA A UNA RUTA Y LOS CAMIONES INACTIVOS (Amado, 07/10/2026).
//
// Cuatro cosas, todas con su pareja —avisa cuando toca y NO avisa cuando no— porque una
// guarda que sólo se prueba por el lado que falla no distingue «rechaza lo malo» de
// «rechaza todo» (`CLAUDE.md` §3-quinquies):
//
//  1. COLOCAR EN EL TABLERO: el domicilio cobrado y cotizado bloquea, la factura sin cotejar
//     NO (se llegó a bloquear y se quitó el mismo día), y los motivos salen en su orden.
//  2. EL CAMIÓN INACTIVO no se asigna: al armar una ruta, al cambiárselo, al armar una zona
//     con el camión del cuerpo y al armarla con el PREVISTO.
//  3. QUITAR UNA PARADA de una ruta planificada: los totales bajan y el pedido deja de ser
//     parada de la ruta (la parada fantasma).
//  4. EL CIERRE RECHAZADO deja escrito dónde estaba cada pedido, y el cierre bueno no pregunta.
//
// Lo que se ata contra Postgres de verdad —que el SQL hace lo que estos dobles repiten— está
// en `internal/store/sqlc/consultas_motor_real_test.go`.

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/store/sqlc"
)

// ---------------------------------------------------------------------------
// 1. Colocar una tarjeta
// ---------------------------------------------------------------------------

func colocarEn(t *testing.T, q *tableroFalso, pedido, columna uuid.UUID) (int, string) {
	t.Helper()
	h := montarTab(t, q)
	w := pedirTab(t, h, http.MethodPut, "/api/board/placements/"+pedido.String(),
		tokenTab(t, sucStg.String()), fmt.Sprintf(`{"columnaId":%q,"posicion":1}`, columna))
	return w.Code, errorDeTab(t, w)
}

func errorDeTab(t *testing.T, w *httptest.ResponseRecorder) string {
	t.Helper()
	var m struct {
		Error string `json:"error"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &m)
	return m.Error
}

// Los dos motivos de Amado, cada uno con su literal, y la pareja: con todo en regla SÍ se coloca.
func TestColocarExigeElDomicilioCobradoYCotizado(t *testing.T) {
	casos := []struct {
		nombre   string
		prepara  func(p *pedidoFalso)
		codigo   int
		mensaje  string
		colocado bool
	}{
		{"cobrado y cotizado: se coloca", func(*pedidoFalso) {}, http.StatusOK, "", true},
		{"sin cobrar", func(p *pedidoFalso) { p.sinCobrar = true }, http.StatusConflict, msgTableroSinDomicilioCobrado, false},
		{"sin cotizar", func(p *pedidoFalso) { p.sinCotizar = true }, http.StatusConflict, msgTableroSinCotizar, false},
		// Si faltan los dos, se dice el primero que se arregla: el cobro en la factura.
		{"sin cobrar y sin cotizar", func(p *pedidoFalso) { p.sinCobrar, p.sinCotizar = true, true },
			http.StatusConflict, msgTableroSinDomicilioCobrado, false},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			q := nuevoTablero()
			p := q.pedidos[ped1]
			c.prepara(&p)
			q.pedidos[ped1] = p
			codigo, mensaje := colocarEn(t, q, ped1, colCentro)
			if codigo != c.codigo || mensaje != c.mensaje {
				t.Fatalf("código %d (%q), se esperaba %d (%q)", codigo, mensaje, c.codigo, c.mensaje)
			}
			if _, puesto := q.colocadas[ped1]; puesto != c.colocado {
				t.Fatalf("colocada=%v, se esperaba %v", puesto, c.colocado)
			}
		})
	}
}

// LA FACTURA SIN COTEJAR NO BLOQUEA COLOCAR. Se añadió ese bloqueo el 07/10/2026 y se quitó
// el mismo día (decisión D1): `cambiado` no entra a una ruta, pero se puede preparar en una
// zona, y el corte a `igual` se hace al armar con su motivo. Si alguien lo vuelve a poner en
// `ColocarPedido` o en `porQueNoSePudoColocar`, esto se pone en rojo.
func TestColocarNoMiraLaFactura(t *testing.T) {
	cambiado := sqlc.FacturaEstadoCambiado
	sinFactura := sqlc.FacturaEstadoSinFactura
	for nombre, estado := range map[string]*sqlc.FacturaEstado{
		"cambiado": &cambiado, "sin factura": &sinFactura, "sin cotejar": nil,
	} {
		t.Run(nombre, func(t *testing.T) {
			q := nuevoTablero()
			p := q.pedidos[ped1]
			p.factura = estado
			q.pedidos[ped1] = p
			if codigo, mensaje := colocarEn(t, q, ped1, colCentro); codigo != http.StatusOK {
				t.Fatalf("colocar con factura %q dio %d (%q): la factura no es condición de colocar", nombre, codigo, mensaje)
			}
		})
	}
}

// D8 — LA PRIORIDAD DE LOS MOTIVOS. Un pedido que ya se entregó y al que además le falta la
// cotización contestaba «primero cotiza el domicilio», un consejo imposible de seguir.
// Entregado, después ruta, después domicilio, después cotización.
func TestColocarDiceYaSeEntregoAntesQueLaCotizacion(t *testing.T) {
	ruta := colCentro // cualquier uuid: sólo importa que no sea nulo
	casos := []struct {
		nombre  string
		prepara func(p *pedidoFalso)
		mensaje string
	}{
		{"entregado y sin cotizar", func(p *pedidoFalso) { p.entregado, p.sinCotizar = true, true }, msgYaSeEntrego},
		{"entregado y sin cobrar", func(p *pedidoFalso) { p.entregado, p.sinCobrar = true, true }, msgYaSeEntrego},
		{"en una ruta y sin cotizar", func(p *pedidoFalso) { p.ruta, p.sinCotizar = &ruta, true }, msgYaVaEnUnaRuta},
		{"entregado y en una ruta: manda el entregado", func(p *pedidoFalso) { p.entregado, p.ruta = true, &ruta }, msgYaSeEntrego},
		// Y la pareja: sin lo de arriba, es el motivo del dato el que sale.
		{"libre y sin cotizar", func(p *pedidoFalso) { p.sinCotizar = true }, msgTableroSinCotizar},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			q := nuevoTablero()
			p := q.pedidos[ped1]
			c.prepara(&p)
			q.pedidos[ped1] = p
			codigo, mensaje := colocarEn(t, q, ped1, colCentro)
			if codigo != http.StatusConflict || mensaje != c.mensaje {
				t.Fatalf("código %d (%q), se esperaba 409 (%q)", codigo, mensaje, c.mensaje)
			}
		})
	}
}

// UN RECHAZO NO MUEVE LA TARJETA. Se comprobaba ANTES de abrir la transacción «para no dejar
// el pedido fuera de su columna anterior», y era innecesario: si `ColocarPedido` no coloca,
// la transacción se deshace. Se prueba el efecto, no el mecanismo.
func TestUnRechazoAlColocarNoSacaLaTarjetaDeDondeEstaba(t *testing.T) {
	q := nuevoTablero()
	q.colocadas[ped1] = colocacion{colVista, 1}
	p := q.pedidos[ped1]
	p.sinCotizar = true
	q.pedidos[ped1] = p

	codigo, mensaje := colocarEn(t, q, ped1, colCentro)
	if codigo != http.StatusConflict || mensaje != msgTableroSinCotizar {
		t.Fatalf("código %d (%q)", codigo, mensaje)
	}
	if got := q.colocadas[ped1]; got.columna != colVista || got.posicion != 1 {
		t.Fatalf("la tarjeta rechazada se movió a %+v: tenía que seguir en Vista Alegre@1", got)
	}
}

func TestColocarUnPedidoQueNoExisteEs404(t *testing.T) {
	q := nuevoTablero()
	codigo, mensaje := colocarEn(t, q, uuid.New(), colCentro)
	if codigo != http.StatusNotFound || mensaje != msgPedidoNoEsta {
		t.Fatalf("código %d (%q)", codigo, mensaje)
	}
}

// La mitad izquierda sólo ofrece lo que se puede colocar: la lista y su contador aplican las
// mismas dos condiciones (§3-bis: dos preguntas, una prueba).
func TestLaMitadIzquierdaNoOfreceLoQueColocarRechaza(t *testing.T) {
	q := nuevoTablero()
	for id, mod := range map[uuid.UUID]func(*pedidoFalso){
		ped2: func(p *pedidoFalso) { p.sinCobrar = true },
		ped3: func(p *pedidoFalso) { p.sinCotizar = true },
	} {
		p := q.pedidos[id]
		mod(&p)
		q.pedidos[id] = p
	}
	filas, err := q.ListarPedidosSinColocar(context.Background(), sqlc.ListarPedidosSinColocarParams{BranchID: sucStg, Limite: 100})
	if err != nil {
		t.Fatal(err)
	}
	total, _ := q.ContarPedidosSinColocar(context.Background(), sqlc.ContarPedidosSinColocarParams{BranchID: sucStg})
	if len(filas) != 1 || filas[0].ID != ped1 || total != 1 {
		t.Fatalf("la lista ofrece %d (%v) y el contador dice %d: sólo ped1 es colocable", len(filas), filas, total)
	}
}

// ---------------------------------------------------------------------------
// 2. El camión inactivo
// ---------------------------------------------------------------------------

func TestArmarUnaRutaConUnCamionInactivoSeRechaza(t *testing.T) {
	for _, inactivo := range []bool{true, false} {
		t.Run(fmt.Sprintf("inactivo=%v", inactivo), func(t *testing.T) {
			d, stg, _ := datosDeReparto()
			d.camiones[camionStg].inactivo = inactivo
			h := montarRutas(t, d)
			w := llamarRutas(t, h, http.MethodPost, "/api/routes", deSantiagoEnRutas(t),
				cuerpoDeArmado(camionStg.String(), stg[1]))
			if inactivo {
				if w.Code != http.StatusBadRequest || errorDeRutas(t, w) != msgVehiculoInactivo {
					t.Fatalf("código %d: %s", w.Code, w.Body.String())
				}
				if len(d.rutas) != 0 {
					t.Fatal("se armó una ruta con un camión inactivo")
				}
				return
			}
			if w.Code != http.StatusCreated {
				t.Fatalf("con el camión activo tiene que salir: %d %s", w.Code, w.Body.String())
			}
		})
	}
}

func TestCambiarElCamionDeUnaRutaAUnoInactivoSeRechaza(t *testing.T) {
	d, stg, _ := datosDeReparto()
	otro := uuid.MustParse("aaaaaaaa-0000-0000-0000-000000000009")
	d.camiones[otro] = &camionDeRutas{id: otro, nombre: "Segundo de Santiago", capacidad: 100,
		estado: sqlc.VehicleStatusAvailable, sucursal: &stgDeRutas, inactivo: true}
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1])

	w := llamarRutas(t, h, http.MethodPatch, "/api/routes/"+id.String(), jwt,
		fmt.Sprintf(`{"vehicleId":%q}`, otro))
	if w.Code != http.StatusBadRequest || errorDeRutas(t, w) != msgVehiculoInactivo {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if d.rutas[id].vehiculo == nil || *d.rutas[id].vehiculo != camionStg {
		t.Fatalf("la ruta cambió de camión a pesar del rechazo: %v", d.rutas[id].vehiculo)
	}

	// La pareja: el mismo cambio con el camión ACTIVO sí se hace.
	d.camiones[otro].inactivo = false
	w = llamarRutas(t, h, http.MethodPatch, "/api/routes/"+id.String(), jwt,
		fmt.Sprintf(`{"vehicleId":%q}`, otro))
	if w.Code != http.StatusOK || d.rutas[id].vehiculo == nil || *d.rutas[id].vehiculo != otro {
		t.Fatalf("con el camión activo tenía que cambiar: %d %s", w.Code, w.Body.String())
	}
	// Y QUITAR el camión no pasa por la comprobación: es la salida de un camión dado de baja.
	d.camiones[camionStg].inactivo = true
	w = llamarRutas(t, h, http.MethodPatch, "/api/routes/"+id.String(), jwt, `{"vehicleId":""}`)
	if w.Code != http.StatusOK {
		t.Fatalf("quitar el camión tiene que poder: %d %s", w.Code, w.Body.String())
	}
}

// Armar una ZONA: el camión del cuerpo y el PREVISTO de la zona se comprueban los dos.
func TestArmarUnaZonaConUnCamionInactivoSeRechaza(t *testing.T) {
	armar := func(q *tableroFalso, cuerpo string) (int, string) {
		q.tresPuestas()
		q.capacidad = 1000
		h := montarTab(t, q)
		w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
			tokenTab(t, sucStg.String()), cuerpo)
		return w.Code, errorDeTab(t, w)
	}
	t.Run("el previsto de la zona, inactivo", func(t *testing.T) {
		q := nuevoTablero()
		v := q.vehiculos[vehStgTab]
		v.inactivo = true
		q.vehiculos[vehStgTab] = v
		codigo, mensaje := armar(q, `{}`)
		if codigo != http.StatusBadRequest || mensaje != msgVehiculoInactivo {
			t.Fatalf("código %d (%q)", codigo, mensaje)
		}
		if q.rutaCreada != nil {
			t.Fatal("se creó la ruta con el camión previsto inactivo")
		}
	})
	t.Run("el previsto de la zona, activo: sale", func(t *testing.T) {
		q := nuevoTablero()
		if codigo, mensaje := armar(q, `{}`); codigo != http.StatusCreated {
			t.Fatalf("código %d (%q)", codigo, mensaje)
		}
	})
	t.Run("el camión del cuerpo, inactivo", func(t *testing.T) {
		q := nuevoTablero()
		q.vehiculos[vehStgTab] = vehiculoFalso{id: vehStgTab, nombre: "Camión de Santiago", sucursal: sucStg}
		otro := uuid.MustParse("7e000000-0000-0000-0000-0000000000a9")
		q.vehiculos[otro] = vehiculoFalso{id: otro, nombre: "Otro de Santiago", sucursal: sucStg, inactivo: true}
		codigo, mensaje := armar(q, fmt.Sprintf(`{"vehiculoId":%q}`, otro))
		if codigo != http.StatusBadRequest || mensaje != msgVehiculoInactivo {
			t.Fatalf("código %d (%q)", codigo, mensaje)
		}
	})
}

// ---------------------------------------------------------------------------
// 2-bis. El tablero NO deja subir lo sin cobrar ni sin cotizar al armar una zona
// ---------------------------------------------------------------------------

func TestArmarUnaZonaNombraLoQueNoTieneDomicilioCobradoNiCotizado(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.capacidad = 1000
	a, b := q.pedidos[ped2], q.pedidos[ped3]
	a.sinCobrar, a.folio = true, "PTB25-261005-1479"
	b.sinCotizar = true
	q.pedidos[ped2], q.pedidos[ped3] = a, b
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	if n, _ := m["paradas"].(float64); n != 1 {
		t.Fatalf("paradas %v, se esperaba 1 (sólo Ana está cobrada y cotizada): %s", m["paradas"], w.Body.String())
	}
	d := descartadoPorNombre(t, m, "Beto")
	if d["motivo"] != "la factura no tiene domicilio cobrado" || d["operationNumber"] != "PTB25-261005-1479" {
		t.Fatalf("Beto: %v", d)
	}
	if d := descartadoPorNombre(t, m, "Ana"); d["motivo"] != "domicilio sin cotizar" {
		t.Fatalf("la segunda Ana: %v", d)
	}
}

// ---------------------------------------------------------------------------
// 3. Quitar una parada de una ruta planificada
// ---------------------------------------------------------------------------

func TestQuitarUnaParadaBajaLosTotalesYLaSacaDeLaHojaDeCierre(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1], stg[2]) // Cerca 30 kg + Medio 30 kg
	if got := d.rutas[id].peso; got != 60 {
		t.Fatalf("antes de quitar la ruta pesa %v y tenía que pesar 60", got)
	}

	w := llamarRutas(t, h, http.MethodDelete, "/api/routes/"+id.String()+"/stops/"+stg[1].String(), jwt, "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if r := d.rutas[id]; r.peso != 30 || r.precio != 10 {
		t.Fatalf("tras quitar una parada la ruta pesa %v kg y vale %v: tenía que ser 30 y 10", r.peso, r.precio)
	}
	quitado := d.pedidos[stg[1]]
	if quitado.rutaID != nil || quitado.ultimaRuta != nil {
		t.Fatalf("el quitado conserva la ruta: route_id=%v ultima_ruta_id=%v", quitado.rutaID, quitado.ultimaRuta)
	}

	// LA PARADA FANTASMA: no se puede cerrar desde la hoja de la ruta que ya no la lleva.
	cuerpo := fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, stg[1])
	w = llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)
	if w.Code != http.StatusConflict || !strings.Contains(w.Body.String(), msgParadaAjena) {
		t.Fatalf("el cierre de un pedido quitado tenía que rechazarse: %d %s", w.Code, w.Body.String())
	}
	if quitado.entregadoEn != nil || quitado.rutaID != nil {
		t.Fatal("el cierre marcó entregado un pedido que ya no iba en la ruta")
	}

	// La pareja: la que SIGUE en la ruta se cierra con normalidad.
	cuerpo = fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, stg[2])
	w = llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)
	if w.Code != http.StatusOK {
		t.Fatalf("la parada que sigue tenía que cerrarse: %d %s", w.Code, w.Body.String())
	}
}

func TestQuitarUnaParadaSoloEnUnaRutaPlanificada(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1], stg[2])

	w := llamarRutas(t, h, http.MethodDelete, "/api/routes/"+id.String()+"/stops/"+stg[0].String(), jwt, "")
	if w.Code != http.StatusConflict || errorDeRutas(t, w) != "El pedido no pertenece a una ruta planificada o ya fue retirado" {
		t.Fatalf("un pedido que no va en la ruta: %d %s", w.Code, w.Body.String())
	}

	d.rutas[id].estado = sqlc.RouteStatusInProgress
	w = llamarRutas(t, h, http.MethodDelete, "/api/routes/"+id.String()+"/stops/"+stg[1].String(), jwt, "")
	if w.Code != http.StatusConflict || errorDeRutas(t, w) != "Sólo se pueden retirar paradas de una ruta planificada" {
		t.Fatalf("una ruta en curso: %d %s", w.Code, w.Body.String())
	}
	if d.pedidos[stg[1]].rutaID == nil {
		t.Fatal("se quitó una parada de una ruta en curso")
	}
}

// ---------------------------------------------------------------------------
// 4. El cierre rechazado se explica solo en el registro
// ---------------------------------------------------------------------------

func TestUnCierreRechazadoDejaEscritoDondeEstabaCadaPedido(t *testing.T) {
	d, stg, _ := datosDeReparto()
	var registro bytes.Buffer
	h, _ := montarRutasRegistrando(t, d, &registro)
	jwt := deSantiagoEnRutas(t)
	rutaA := armarRutaDePrueba(t, h, jwt, stg[1])
	rutaB := armarRutaDePrueba(t, h, jwt, stg[2])

	// Se cierra A con un pedido que va en B, uno que no va en ninguna y un id que ni es id.
	cuerpo := fmt.Sprintf(`{"resultados":[
		{"orderId":%q,"resultado":"entregado"},
		{"orderId":%q,"resultado":"entregado"},
		{"orderId":"no-es-un-id","resultado":"entregado"}]}`, stg[2], stg[0])
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+rutaA.String()+"/results", jwt, cuerpo)
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if d.dondeEstanLlamadas != 1 {
		t.Fatalf("el diagnóstico tenía que preguntarse UNA vez, en una sola lectura: %d", d.dondeEstanLlamadas)
	}
	log := registro.String()

	// El pedido que iba en la OTRA ruta: las tres columnas, con los valores de verdad.
	var linea string
	for _, l := range strings.Split(log, "\n") {
		if strings.Contains(l, "parada rechazada en el cierre") && strings.Contains(l, "pedido="+stg[2].String()) {
			linea = l
		}
	}
	if linea == "" {
		t.Fatalf("no hay renglón del pedido %s que iba en la otra ruta:\n%s", stg[2], log)
	}
	for _, quiere := range []string{
		"route_id=" + rutaB.String(), "ultima_ruta_id=" + rutaB.String(),
		"branch_id=" + stgDeRutas.String(), "ruta=" + rutaA.String(),
	} {
		if !strings.Contains(linea, quiere) {
			t.Errorf("al renglón le falta %q:\n%s", quiere, linea)
		}
	}
	// El que no va en ninguna ruta: NULL, que es un dato, no un hueco.
	if !strings.Contains(log, "route_id=NULL ultima_ruta_id=NULL branch_id="+stgDeRutas.String()) {
		t.Errorf("el pedido sin ruta tenía que decir route_id=NULL ultima_ruta_id=NULL:\n%s", log)
	}
	if !strings.Contains(log, "el orderId no es un id") {
		t.Errorf("el que ni es un id también se nombra:\n%s", log)
	}
	// Y NADA que sea secreto: el renglón no lleva el token de la sesión.
	if strings.Contains(log, jwt) || strings.Contains(strings.ToLower(log), "bearer") {
		t.Errorf("el registro lleva el token o la cabecera de autorización:\n%s", log)
	}
}

// La pareja: un cierre que sale bien NO pregunta nada ni escribe renglones de rechazo.
func TestUnCierreBuenoNoPreguntaDondeEstanLosPedidos(t *testing.T) {
	d, stg, _ := datosDeReparto()
	var registro bytes.Buffer
	h, _ := montarRutasRegistrando(t, d, &registro)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1])

	cuerpo := fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, stg[1])
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if d.dondeEstanLlamadas != 0 {
		t.Fatalf("el cierre bueno hizo %d lecturas de diagnóstico: el camino feliz no paga nada", d.dondeEstanLlamadas)
	}
	if strings.Contains(registro.String(), "parada rechazada") {
		t.Fatalf("un cierre bueno dejó renglones de rechazo:\n%s", registro.String())
	}
}
