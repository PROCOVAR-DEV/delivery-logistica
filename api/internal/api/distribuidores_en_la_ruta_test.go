package api

// EL DISTRIBUIDOR SE ASOCIA A LA RUTA AL CREARLA — issue 7 de Amado, 14/10/2026.
//
// Las TRES puertas que arman o cambian una ruta lo aceptan, opcional, y lo validan igual
// (`distribuidorDeLaRuta`): `POST /api/routes`, `PATCH /api/routes/{id}` y el armado desde el tablero
// (`POST /api/board/columns/{id}/route`). Tiene que ser de LA MISMA SUCURSAL que la ruta y seguir en
// activo; lo de otra sucursal se contesta como «no existe» (decir «es de otra» sería contar algo de
// él), salvo para quien ve las ocho, que ya lo alcanza y a quien se le dice la verdad.
//
// Y la ruta lo devuelve CON SU NOMBRE, en el detalle y en la lista, y lo baja el aparato en la
// colección `distribuidores` (sin conexión se elige de la copia local).

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

// distBorradoHol: uno de Holguín que se borró (para ver que su baja no llega a Santiago).
var distBorradoHol = uuid.MustParse("d1000000-0000-0000-0000-000000000005")

// conDistribuidor mete `"distribuidorId": <crudo>` en un cuerpo JSON ya armado.
func conDistribuidor(cuerpo, crudo string) string {
	return strings.Replace(cuerpo, "{", `{"distribuidorId":`+crudo+`,`, 1)
}

func comillas(id uuid.UUID) string { return `"` + id.String() + `"` }

func rutaDeRespuesta(t *testing.T, w *httptest.ResponseRecorder, codigo int) RutaSalida {
	t.Helper()
	codigoDist(t, w, codigo)
	var r RutaSalida
	if err := json.Unmarshal(w.Body.Bytes(), &r); err != nil {
		t.Fatalf("la respuesta no es una ruta: %v: %s", err, w.Body.String())
	}
	return r
}

// --------------------------------------------------------------------------- POST /api/routes

// LA RUTA SE ARMA CON SU DISTRIBUIDOR Y LO DEVUELVE CON SU NOMBRE, en el POST, en el detalle y en la
// lista. En PAREJA: sin él, con null o con la cadena vacía, la ruta sale sin distribuidor y NO se
// inventa uno.
func TestLaRutaSeArmaConSuDistribuidorYLoDevuelveConSuNombre(t *testing.T) {
	santiago := logisticoDe(t, stgDeRutas)

	t.Run("con distribuidor: lo guarda y lo devuelve con su nombre", func(t *testing.T) {
		d, pedidos, _ := nuevoDobleDeDistribuidores()
		h := montarDist(t, d)
		cuerpo := conDistribuidor(cuerpoDeArmado(camionStg.String(), pedidos[0], pedidos[1]), comillas(distJuanStg))
		ruta := rutaDeRespuesta(t, llamarDist(t, h, http.MethodPost, "/api/routes", santiago, "", cuerpo), http.StatusCreated)
		if ruta.DistribuidorID == nil || *ruta.DistribuidorID != distJuanStg ||
			ruta.Distribuidor == nil || ruta.Distribuidor.ID != distJuanStg ||
			ruta.Distribuidor.Nombre == nil || *ruta.Distribuidor.Nombre != "Juan Pérez" {
			t.Fatalf("la ruta tenía que llevar a «Juan Pérez»: id=%v distribuidor=%+v", ruta.DistribuidorID, ruta.Distribuidor)
		}

		detalle := rutaDeRespuesta(t, llamarDist(t, h, http.MethodGet, "/api/routes/"+ruta.ID.String(), santiago, "", ""), http.StatusOK)
		if detalle.Distribuidor == nil || detalle.Distribuidor.Nombre == nil || *detalle.Distribuidor.Nombre != "Juan Pérez" {
			t.Fatalf("el detalle tiene que decir quién reparte: %+v", detalle.Distribuidor)
		}

		w := llamarDist(t, h, http.MethodGet, "/api/routes", santiago, "", "")
		codigoDist(t, w, http.StatusOK)
		var lista []RutaSalida
		if err := json.Unmarshal(w.Body.Bytes(), &lista); err != nil || len(lista) != 1 {
			t.Fatalf("la lista: %v: %s", err, w.Body.String())
		}
		if lista[0].Distribuidor == nil || lista[0].DistribuidorID == nil || *lista[0].DistribuidorID != distJuanStg ||
			lista[0].Distribuidor.Nombre == nil || *lista[0].Distribuidor.Nombre != "Juan Pérez" {
			t.Fatalf("la lista de rutas tiene que decir quién reparte, CON su nombre: %+v", lista[0].Distribuidor)
		}
	})

	for nombre, crudo := range map[string]string{"sin el campo": "", "null": "null", "la cadena vacía": `""`, "sólo espacios": `"  "`} {
		t.Run("sin distribuidor ("+nombre+"): la ruta sale sin él", func(t *testing.T) {
			d, pedidos, _ := nuevoDobleDeDistribuidores()
			cuerpo := cuerpoDeArmado(camionStg.String(), pedidos[0])
			if crudo != "" {
				cuerpo = conDistribuidor(cuerpo, crudo)
			}
			ruta := rutaDeRespuesta(t, llamarDist(t, montarDist(t, d), http.MethodPost, "/api/routes", santiago, "", cuerpo), http.StatusCreated)
			if ruta.DistribuidorID != nil || ruta.Distribuidor != nil {
				t.Fatalf("no se pidió distribuidor y la ruta salió con uno: %+v %v", ruta.Distribuidor, ruta.DistribuidorID)
			}
			if len(d.distribuidorDe) != 0 {
				t.Fatalf("se guardó un distribuidor que nadie eligió: %v", d.distribuidorDe)
			}
		})
	}
}

// EL DISTRIBUIDOR TIENE QUE SER DE LA SUCURSAL DE LA RUTA Y ESTAR EN ACTIVO, y la ruta NO se crea si no.
func TestLaRutaNoAdmiteUnDistribuidorQueNoEsDeSuSucursalNiRetirado(t *testing.T) {
	santiago := logisticoDe(t, stgDeRutas)

	rechazos := []struct {
		nombre, jwt, crudo, branchEnElCuerpo, dice, noDice string
	}{
		{"el de Holguín, pedido desde Santiago", santiago, comillas(distJuanHol), "", "No existe el distribuidor", "no es de la sucursal"},
		{"un id que no es un uuid", santiago, `"no-es-un-id"`, "", "No existe el distribuidor 'no-es-un-id'", ""},
		{"un id que no existe", santiago, comillas(uuid.New()), "", "No existe el distribuidor", ""},
		{"uno RETIRADO", santiago, comillas(distPedroStg), "", msgDistribuidorRetirado, ""},
		// Quien ve las ocho ya alcanza al de Holguín: la verdad sale entera.
		{"el de Holguín, en una ruta de Santiago de un SUPER ADMIN", superSinSucursalDeDist(t), comillas(distJuanHol), "",
			"no es de la sucursal de esta ruta", ""},
		// Y si elige la sucursal en el cuerpo, el alcance se estrecha a ella: «no existe».
		{"el de Holguín, con la sucursal de Santiago elegida en el cuerpo", superSinSucursalDeDist(t), comillas(distJuanHol), stgDeRutas.String(),
			"No existe el distribuidor", ""},
	}
	for _, c := range rechazos {
		t.Run(c.nombre+": 400 y no crea la ruta", func(t *testing.T) {
			d, pedidos, _ := nuevoDobleDeDistribuidores()
			cuerpo := conDistribuidor(cuerpoDeArmado(camionStg.String(), pedidos[0]), c.crudo)
			if c.branchEnElCuerpo != "" {
				cuerpo = strings.Replace(cuerpo, "{", `{"branchId":"`+c.branchEnElCuerpo+`",`, 1)
			}
			w := llamarDist(t, montarDist(t, d), http.MethodPost, "/api/routes", c.jwt, "", cuerpo)
			codigoDist(t, w, http.StatusBadRequest)
			if !strings.Contains(w.Body.String(), c.dice) {
				t.Fatalf("el 400 tenía que decir %q: %s", c.dice, w.Body.String())
			}
			if c.noDice != "" && strings.Contains(w.Body.String(), c.noDice) {
				t.Fatalf("el 400 cuenta algo de un distribuidor ajeno (%q): %s", c.noDice, w.Body.String())
			}
			if len(d.rutas) != 0 {
				t.Fatalf("el 400 llegó DESPUÉS de crear la ruta: %d", len(d.rutas))
			}
		})
	}

	// LA PAREJA: lo mismo, pero con uno bueno, pasa — por las dos puertas de quien ve las ocho.
	t.Run("un SUPER ADMIN con el de la sucursal de la ruta: pasa", func(t *testing.T) {
		d, pedidos, _ := nuevoDobleDeDistribuidores()
		cuerpo := conDistribuidor(cuerpoDeArmado(camionStg.String(), pedidos[0]), comillas(distJuanStg))
		ruta := rutaDeRespuesta(t, llamarDist(t, montarDist(t, d), http.MethodPost, "/api/routes", superSinSucursalDeDist(t), "", cuerpo), http.StatusCreated)
		if ruta.DistribuidorID == nil || *ruta.DistribuidorID != distJuanStg {
			t.Fatalf("tenía que llevar a Juan de Santiago: %+v", ruta)
		}
	})
	t.Run("Holguín usa el SUYO, que se llama igual que uno de Santiago", func(t *testing.T) {
		d, _, ajeno := nuevoDobleDeDistribuidores()
		cuerpo := conDistribuidor(cuerpoDeArmado(camionHol.String(), ajeno), comillas(distJuanHol))
		ruta := rutaDeRespuesta(t, llamarDist(t, montarDist(t, d), http.MethodPost, "/api/routes", logisticoDe(t, holDeRutas), "", cuerpo), http.StatusCreated)
		if ruta.DistribuidorID == nil || *ruta.DistribuidorID != distJuanHol {
			t.Fatalf("tenía que llevar a Juan de Holguín: %+v", ruta)
		}
	})
}

// --------------------------------------------------------------------------- PATCH /api/routes/{id}

// EL PATCH CAMBIA, QUITA Y NO TOCA. Ausente es «no lo toques»; null o vacío es «quítalo»; con valor es
// «éste» (validado). Por los DOS caminos del PATCH —el del camión, que retorna antes, y el del estado—.
func TestElPatchDeLaRutaCambiaQuitaYNoTocaAlDistribuidor(t *testing.T) {
	santiago := logisticoDe(t, stgDeRutas)

	// armada deja una ruta de Santiago con Juan y devuelve el doble, el manejador y la ruta.
	armada := func(t *testing.T) (*dobleDeDistribuidores, http.Handler, uuid.UUID) {
		t.Helper()
		d, pedidos, _ := nuevoDobleDeDistribuidores()
		h := montarDist(t, d)
		cuerpo := conDistribuidor(cuerpoDeArmado(camionStg.String(), pedidos[0]), comillas(distJuanStg))
		return d, h, rutaDeRespuesta(t, llamarDist(t, h, http.MethodPost, "/api/routes", santiago, "", cuerpo), http.StatusCreated).ID
	}
	quien := func(t *testing.T, h http.Handler, ruta uuid.UUID) *uuid.UUID {
		t.Helper()
		return rutaDeRespuesta(t, llamarDist(t, h, http.MethodGet, "/api/routes/"+ruta.String(), santiago, "", ""), http.StatusOK).DistribuidorID
	}

	t.Run("lo cambia por otro de la sucursal", func(t *testing.T) {
		_, h, ruta := armada(t)
		cambiada := rutaDeRespuesta(t, llamarDist(t, h, http.MethodPatch, "/api/routes/"+ruta.String(), santiago, "",
			`{"distribuidorId":`+comillas(distMariaStg)+`}`), http.StatusOK)
		if cambiada.DistribuidorID == nil || *cambiada.DistribuidorID != distMariaStg ||
			cambiada.Distribuidor == nil || *cambiada.Distribuidor.Nombre != "María López" {
			t.Fatalf("tenía que pasar a María: %+v", cambiada.Distribuidor)
		}
	})

	t.Run("un PATCH que no lo menciona NO lo toca", func(t *testing.T) {
		d, h, ruta := armada(t)
		codigoDist(t, llamarDist(t, h, http.MethodPatch, "/api/routes/"+ruta.String(), santiago, "", `{"name":"Otro nombre"}`), http.StatusOK)
		if got := quien(t, h, ruta); got == nil || *got != distJuanStg {
			t.Fatalf("cambiar el nombre borró al distribuidor: %v", got)
		}
		if d.tocadas != 0 {
			t.Fatalf("un PATCH sin distribuidorId llegó a tocarlo %d veces", d.tocadas)
		}
	})

	for nombre, crudo := range map[string]string{"null": "null", "la cadena vacía": `""`} {
		t.Run("con "+nombre+" lo QUITA", func(t *testing.T) {
			_, h, ruta := armada(t)
			quitada := rutaDeRespuesta(t, llamarDist(t, h, http.MethodPatch, "/api/routes/"+ruta.String(), santiago, "",
				`{"distribuidorId":`+crudo+`}`), http.StatusOK)
			if quitada.DistribuidorID != nil || quitada.Distribuidor != nil {
				t.Fatalf("tenía que quedar sin distribuidor: %+v", quitada.Distribuidor)
			}
		})
	}

	t.Run("por el camino del camión (vehicleId + distribuidorId) también", func(t *testing.T) {
		_, h, ruta := armada(t)
		cambiada := rutaDeRespuesta(t, llamarDist(t, h, http.MethodPatch, "/api/routes/"+ruta.String(), santiago, "",
			`{"vehicleId":`+comillas(camionStg)+`,"distribuidorId":`+comillas(distMariaStg)+`}`), http.StatusOK)
		if cambiada.DistribuidorID == nil || *cambiada.DistribuidorID != distMariaStg {
			t.Fatalf("el camino del camión se tragó el distribuidor: %+v", cambiada.Distribuidor)
		}
		// Y sin mencionarlo, el camino del camión tampoco lo borra.
		again := rutaDeRespuesta(t, llamarDist(t, h, http.MethodPatch, "/api/routes/"+ruta.String(), santiago, "",
			`{"vehicleId":`+comillas(camionStg)+`}`), http.StatusOK)
		if again.DistribuidorID == nil || *again.DistribuidorID != distMariaStg {
			t.Fatalf("cambiar el camión borró al distribuidor: %+v", again.Distribuidor)
		}
	})

	t.Run("uno que no vale (de Holguín, retirado, que no existe): 400 y el de antes se queda", func(t *testing.T) {
		for nombre, id := range map[string]string{"de Holguín": comillas(distJuanHol), "retirado": comillas(distPedroStg), "que no existe": comillas(uuid.New())} {
			d, h, ruta := armada(t)
			w := llamarDist(t, h, http.MethodPatch, "/api/routes/"+ruta.String(), santiago, "", `{"distribuidorId":`+id+`}`)
			codigoDist(t, w, http.StatusBadRequest)
			if got := quien(t, h, ruta); got == nil || *got != distJuanStg {
				t.Fatalf("el 400 (%s) dejó la ruta con %v", nombre, got)
			}
			if d.tocadas != 0 {
				t.Fatalf("el 400 (%s) llegó DESPUÉS de escribir", nombre)
			}
		}
	})

	t.Run("una ruta COMPLETADA es histórico: 409 y no se toca", func(t *testing.T) {
		d, h, ruta := armada(t)
		codigoDist(t, llamarDist(t, h, http.MethodPatch, "/api/routes/"+ruta.String(), santiago, "", `{"status":"completed"}`), http.StatusOK)
		w := llamarDist(t, h, http.MethodPatch, "/api/routes/"+ruta.String(), santiago, "", `{"distribuidorId":`+comillas(distMariaStg)+`}`)
		codigoDist(t, w, http.StatusConflict)
		if got := quien(t, h, ruta); got == nil || *got != distJuanStg {
			t.Fatalf("el histórico cambió de distribuidor: %v", got)
		}
		if d.tocadas != 0 {
			t.Fatal("el 409 llegó DESPUÉS de escribir")
		}
	})

	t.Run("la ruta de OTRA sucursal es un 404", func(t *testing.T) {
		d, h, ruta := armada(t)
		w := llamarDist(t, h, http.MethodPatch, "/api/routes/"+ruta.String(), logisticoDe(t, holDeRutas), "",
			`{"distribuidorId":`+comillas(distJuanHol)+`}`)
		codigoDist(t, w, http.StatusNotFound)
		if d.tocadas != 0 {
			t.Fatal("el 404 llegó DESPUÉS de escribir")
		}
	})
}

// --------------------------------------------------------------------------- el armado desde el tablero

// tableroConDistribuidores añade al doble del tablero el nomenclador, que es lo único que el armado
// le pregunta.
type tableroConDistribuidores struct {
	*tableroFalso
	lista []sqlc.ObtenerDistribuidorRow
}

func (q *tableroConDistribuidores) ObtenerDistribuidor(_ context.Context, arg sqlc.ObtenerDistribuidorParams) (sqlc.ObtenerDistribuidorRow, error) {
	for _, d := range q.lista {
		if d.ID == arg.ID && alcanzaDist(arg.Sucursal, d.BranchID) {
			return d, nil
		}
	}
	return sqlc.ObtenerDistribuidorRow{}, pgx.ErrNoRows
}

func nuevoTableroConDistribuidores() *tableroConDistribuidores {
	q := nuevoTablero()
	q.capacidad = 1000
	q.tresPuestas()
	return &tableroConDistribuidores{tableroFalso: q, lista: []sqlc.ObtenerDistribuidorRow{
		{ID: distJuanStg, BranchID: sucStg, Nombre: "Juan Pérez", Activo: true},
		{ID: distPedroStg, BranchID: sucStg, Nombre: "Pedro Gil", Activo: false},
		{ID: distJuanHol, BranchID: sucHol, Nombre: "Juan Pérez", Activo: true},
	}}
}

// LA ZONA SE ARMA CON SU DISTRIBUIDOR: es por donde se arma el día de verdad. Misma validación que el
// POST de rutas, en PAREJA: sin él sale sin distribuidor.
func TestLaZonaSeArmaConSuDistribuidor(t *testing.T) {
	arma := func(t *testing.T, q *tableroConDistribuidores, jwt, cuerpo string) *httptest.ResponseRecorder {
		t.Helper()
		return pedirTab(t, montarTab(t, q), http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route", jwt, cuerpo)
	}
	santiago := tokenTab(t, sucStg.String())

	t.Run("con un distribuidor de la sucursal de la zona: lo guarda", func(t *testing.T) {
		q := nuevoTableroConDistribuidores()
		w := arma(t, q, santiago, `{"nombre":"Centro","distribuidorId":`+comillas(distJuanStg)+`}`)
		codigoDist(t, w, http.StatusCreated)
		if q.rutaCreada == nil || !q.rutaCreada.DistribuidorID.Valid || q.rutaCreada.DistribuidorID.Bytes != [16]byte(distJuanStg) {
			t.Fatalf("la ruta se creó SIN el distribuidor que se pidió: %+v", q.rutaCreada)
		}
		if leerTab(t, w)["distribuidorId"] != distJuanStg.String() {
			t.Fatalf("la respuesta tiene que decir quién reparte: %s", w.Body.String())
		}
	})

	for nombre, cuerpo := range map[string]string{
		"sin el campo": `{"nombre":"Centro"}`, "null": `{"nombre":"Centro","distribuidorId":null}`, "vacío": `{"nombre":"Centro","distribuidorId":""}`,
	} {
		t.Run("sin distribuidor ("+nombre+"): la ruta sale sin él", func(t *testing.T) {
			q := nuevoTableroConDistribuidores()
			codigoDist(t, arma(t, q, santiago, cuerpo), http.StatusCreated)
			if q.rutaCreada == nil || q.rutaCreada.DistribuidorID.Valid {
				t.Fatalf("la ruta salió con un distribuidor que nadie eligió: %+v", q.rutaCreada)
			}
		})
	}

	rechazos := map[string]struct {
		jwt, crudo, dice string
	}{
		"el de Holguín, desde Santiago": {santiago, comillas(distJuanHol), "No existe el distribuidor"},
		"uno retirado":                  {santiago, comillas(distPedroStg), msgDistribuidorRetirado},
		"un id que no es un uuid":       {santiago, `"nada"`, "No existe el distribuidor 'nada'"},
		// Quien ve las ocho alcanza al de Holguín, pero la zona es de Santiago.
		"el de Holguín, en una zona de Santiago de un SUPER ADMIN": {tokenTab(t, ""), comillas(distJuanHol), "no es de la sucursal de esta ruta"},
	}
	for nombre, c := range rechazos {
		t.Run(nombre+": 400 y no crea la ruta", func(t *testing.T) {
			q := nuevoTableroConDistribuidores()
			w := arma(t, q, c.jwt, `{"nombre":"Centro","distribuidorId":`+c.crudo+`}`)
			codigoDist(t, w, http.StatusBadRequest)
			if !strings.Contains(w.Body.String(), c.dice) {
				t.Fatalf("el 400 tenía que decir %q: %s", c.dice, w.Body.String())
			}
			if q.rutaCreada != nil {
				t.Fatal("el 400 llegó DESPUÉS de crear la ruta")
			}
		})
	}
}

// --------------------------------------------------------------------------- la bajada del aparato

// espejoConDistribuidores no necesita más que el espejo de siempre: `ListarDistribuidores` ya está en él.
func unDistribuidorDeLaBajada(id, sucursal uuid.UUID, nombre string, activo bool, marca time.Time) sqlc.ListarDistribuidoresRow {
	return sqlc.ListarDistribuidoresRow{
		ID: id, BranchID: sucursal, Nombre: nombre, Activo: activo,
		UpdatedAt: pgtype.Timestamptz{Time: marca, Valid: true},
	}
}

func puestosDe(t *testing.T, m map[string]any, nombre string) map[string]map[string]any {
	t.Helper()
	c, hay := m["cambios"].(map[string]any)[nombre]
	if !hay {
		t.Fatalf("no vino la colección %q", nombre)
	}
	salida := map[string]map[string]any{}
	for _, p := range c.(map[string]any)["puestos"].([]any) {
		fila := p.(map[string]any)
		salida[fila["id"].(string)] = fila
	}
	return salida
}

// LOS DISTRIBUIDORES BAJAN CON EL DÍA, y cada aparato recibe SÓLO los de su sucursal (también los
// retirados, que las rutas viejas siguen nombrando), con su lápida cuando se borra uno.
func TestLaBajadaLlevaLosDistribuidoresDeSuSucursal(t *testing.T) {
	ahora := time.Now().UTC()
	q := nuevoEspejo()
	q.distribuidoresDelEspejo = []sqlc.ListarDistribuidoresRow{
		unDistribuidorDeLaBajada(distJuanStg, sucStg, "Juan Pérez", true, ahora),
		unDistribuidorDeLaBajada(distPedroStg, sucStg, "Pedro Gil", false, ahora),
		unDistribuidorDeLaBajada(distJuanHol, sucHol, "Juan Pérez", true, ahora),
	}

	t.Run("Santiago recibe los suyos, con el retirado, y no el de Holguín", func(t *testing.T) {
		m := bajadaDe(t, q, tokenTab(t, sucStg.String()), "")
		puestos := puestosDe(t, m, "distribuidores")
		if len(puestos) != 2 || puestos[distJuanStg.String()] == nil || puestos[distPedroStg.String()] == nil {
			t.Fatalf("Santiago tenía que recibir sus dos (el retirado también) y recibió %v", puestos)
		}
		juan := puestos[distJuanStg.String()]
		if juan["nombre"] != "Juan Pérez" || juan["activo"] != true || juan["branchId"] != sucStg.String() {
			t.Fatalf("la fila tiene que llevar nombre, estado y sucursal: %v", juan)
		}
		if puestos[distPedroStg.String()]["activo"] != false {
			t.Fatal("el retirado tiene que bajar como retirado: el selector lo esconde él")
		}
	})

	t.Run("Holguín recibe el suyo", func(t *testing.T) {
		puestos := puestosDe(t, bajadaDe(t, q, tokenTab(t, sucHol.String()), ""), "distribuidores")
		if len(puestos) != 1 || puestos[distJuanHol.String()] == nil {
			t.Fatalf("Holguín tenía que recibir sólo el suyo: %v", puestos)
		}
	})

	t.Run("quien ve las ocho recibe los de todas", func(t *testing.T) {
		puestos := puestosDe(t, bajadaDe(t, q, tokenTab(t, ""), ""), "distribuidores")
		if len(puestos) != 3 {
			t.Fatalf("en modo «todas» tenía que recibir los tres: %v", puestos)
		}
	})

	t.Run("por diferencias: sólo lo que cambió después de la marca", func(t *testing.T) {
		marca := ahora.Add(-time.Hour)
		viejo := *q
		viejo.distribuidoresDelEspejo = append([]sqlc.ListarDistribuidoresRow{},
			unDistribuidorDeLaBajada(distJuanStg, sucStg, "Juan Pérez", true, ahora),
			unDistribuidorDeLaBajada(distMariaStg, sucStg, "María López", true, ahora.Add(-24*time.Hour)))
		puestos := puestosDe(t, bajadaDe(t, &viejo, tokenTab(t, sucStg.String()), "?desde="+marca.Format(time.RFC3339Nano)), "distribuidores")
		if len(puestos) != 1 || puestos[distJuanStg.String()] == nil {
			t.Fatalf("con «desde» sólo tenía que venir el que cambió: %v", puestos)
		}
	})

	// EL APARATO QUE YA HABIA SINCRONIZADO ANTES DE CONOCER LOS DISTRIBUIDORES. Su marca `desde` es
	// de TODAS las colecciones y la avanzó con ellos ya creados: «lo que cambió desde ayer» no los
	// trae nunca. `completas=distribuidores` los pide enteros, sin tocar el resto de la bajada.
	t.Run("`completas=distribuidores` los trae TODOS aunque `desde` los deje atrás; sin él, no", func(t *testing.T) {
		marca := ahora.Add(-time.Hour)
		viejos := *q
		viejos.distribuidoresDelEspejo = []sqlc.ListarDistribuidoresRow{
			unDistribuidorDeLaBajada(distJuanStg, sucStg, "Juan Pérez", true, ahora.Add(-48*time.Hour)),
			unDistribuidorDeLaBajada(distMariaStg, sucStg, "María López", true, ahora.Add(-24*time.Hour)),
		}
		viejos.bajas = []bajaSync{
			// Una lápida posterior a la marca: con la lista ENTERA no hay nada que quitar.
			{sqlc.ColeccionDeLaBajadaDistribuidores, distBorradoHol.String(), &sucStg, sqlc.MotivoDeBajaBorrado, ahora.Add(-30 * time.Minute)},
		}
		desde := "?desde=" + marca.Format(time.RFC3339Nano)

		sin := bajadaDe(t, &viejos, tokenTab(t, sucStg.String()), desde)
		if got := puestosDe(t, sin, "distribuidores"); len(got) != 0 {
			t.Fatalf("la pareja está rota: sin `completas`, con `desde` de hace una hora y dos viejos, no podía venir nada: %v", got)
		}

		con := bajadaDe(t, &viejos, tokenTab(t, sucStg.String()), desde+"&completas=distribuidores")
		if got := puestosDe(t, con, "distribuidores"); len(got) != 2 {
			t.Fatalf("`completas=distribuidores` tenía que traer los dos, y trajo %v", got)
		}
		if quitados := bajasDe(t, con, "distribuidores"); len(quitados) != 0 {
			t.Fatalf("pidiendo la lista entera no hay nada que quitar: %v", quitados)
		}
		// Y no arrastra a las demás: sólo lo que se nombra.
		if got := puestosDe(t, con, "routes"); len(got) != 0 {
			t.Fatalf("`completas` no puede ensanchar las demás colecciones: %v", got)
		}
		// Un nombre que no se conoce se ignora (no es un 400 ni ensancha nada).
		raro := bajadaDe(t, &viejos, tokenTab(t, sucStg.String()), desde+"&completas=ruta%20inventada,vehicles")
		if got := puestosDe(t, raro, "distribuidores"); len(got) != 0 {
			t.Fatalf("un nombre ajeno en `completas` ensanchó los distribuidores: %v", got)
		}
	})

	t.Run("el borrado de uno sale en «quitados» de SU sucursal y de ninguna otra", func(t *testing.T) {
		marca := ahora.Add(-12 * time.Hour)
		fuera := *q
		fuera.bajas = []bajaSync{
			{sqlc.ColeccionDeLaBajadaDistribuidores, distMariaStg.String(), &sucStg, sqlc.MotivoDeBajaBorrado, ahora.Add(-time.Hour)},
			{sqlc.ColeccionDeLaBajadaDistribuidores, distBorradoHol.String(), &sucHol, sqlc.MotivoDeBajaBorrado, ahora.Add(-time.Hour)},
			// LA LÁPIDA MENTIROSA: de uno que sigue vivo. Tiene que tacharse.
			{sqlc.ColeccionDeLaBajadaDistribuidores, distJuanStg.String(), &sucStg, sqlc.MotivoDeBajaBorrado, ahora.Add(-time.Hour)},
			// Anterior a la marca: ya se la llevó en su día.
			{sqlc.ColeccionDeLaBajadaDistribuidores, "d1000000-0000-0000-0000-0000000000ff", &sucStg, sqlc.MotivoDeBajaBorrado, ahora.Add(-24 * time.Hour)},
		}
		m := bajadaDe(t, &fuera, tokenTab(t, sucStg.String()), "?desde="+marca.Format(time.RFC3339Nano))
		quitados := bajasDe(t, m, "distribuidores")
		if !quitados[distMariaStg.String()] {
			t.Fatalf("el distribuidor borrado no salió en «quitados»: el aparato lo seguiría ofreciendo.\n%v", quitados)
		}
		if quitados[distBorradoHol.String()] {
			t.Fatal("a Santiago le llegó la baja de un distribuidor de Holguín")
		}
		if quitados[distJuanStg.String()] {
			t.Fatal("salió en «quitados» uno que sigue vivo: se lo llevaría el aparato por una lápida mal puesta")
		}
		if quitados["d1000000-0000-0000-0000-0000000000ff"] {
			t.Fatal("salió una baja anterior a la marca del aparato")
		}
	})
}

// LA RUTA DE LA BAJADA LLEVA SU `distribuidorId`: con el id y la colección `distribuidores` el aparato
// pinta el nombre sin red. Sin el id, la ruta bajaría sin saber quién la reparte.
func TestLaBajadaDeRutasLlevaElDistribuidor(t *testing.T) {
	q := nuevoEspejo()
	reciente := pgtype.Timestamptz{Time: time.Now().UTC(), Valid: true}
	q.rutasDelEspejo = []sqlc.ListarRutasRow{
		{ID: rutaViva, BranchID: pgtype.UUID{Bytes: [16]byte(sucStg), Valid: true}, UpdatedAt: reciente,
			DistribuidorID: pgtype.UUID{Bytes: [16]byte(distJuanStg), Valid: true}},
		{ID: rutaVieja, BranchID: pgtype.UUID{Bytes: [16]byte(sucStg), Valid: true}, UpdatedAt: reciente},
	}
	puestos := puestosDe(t, bajadaDe(t, q, tokenTab(t, sucStg.String()), ""), "routes")
	if puestos[rutaViva.String()]["distribuidorId"] != distJuanStg.String() {
		t.Fatalf("la ruta bajó sin su distribuidor: %v", puestos[rutaViva.String()])
	}
	if v, hay := puestos[rutaVieja.String()]["distribuidorId"]; !hay || v != nil {
		t.Fatalf("una ruta histórica baja con distribuidorId null (no se inventa uno): %v", v)
	}
}
