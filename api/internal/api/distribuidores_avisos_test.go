package api

// UN DISTRIBUIDOR DE SANTIAGO LLEGA A SANTIAGO Y NO A HOLGUÍN — issue 7, 14/10/2026.
//
// Como los tipos de vehículo desde la 00018: el nomenclador es de cada sucursal, así que avisar a las
// otras siete es mandarlas a pedir `GET /api/vehicles` y `GET /api/distribuidores` (y a bajarse un ciclo
// entero) para pintar exactamente lo mismo. Publica el tipo `vehiculos`, que es el de la pantalla donde
// se mantiene, con la sucursal DEL DISTRIBUIDOR que se escribió (la fila), no la del alcance de quien llama.
//
// Mira el CABLE —el bus de verdad, un suscriptor por sucursal— y no el gancho: lo que hay que comprobar
// es que a Holguín no le llega, no que alguien llamó a una función. Y las dos mitades en PAREJA: lo que NO
// se escribió (404, 409, 400) no se avisa.

import (
	"net/http"
	"testing"
)

func TestUnDistribuidorDeSantiagoLlegaASantiagoYNoAHolguin(t *testing.T) {
	// LO ESCRIBE UN `ADMINISTRADOR` DE SANTIAGO: un administrador es de UNA sucursal. Con un SUPER ADMIN en
	// modo «todas» el alcance es «todas», y es justo el caso que el aviso por FILA arregla (ver `eventos.go`).
	for nombre, jwt := range map[string]func(*testing.T) string{
		"un logístico de Santiago":       func(t *testing.T) string { return logisticoDe(t, stgDeRutas) },
		"un SUPER ADMIN en modo «todas»": func(t *testing.T) string { return superSinSucursalDeDist(t) },
	} {
		casos := []struct {
			nombre, metodo, ruta, cuerpo string
			codigo                       int
		}{
			// Crear necesita sucursal: el SUPER ADMIN en modo «todas» recibe 400, y eso es otra prueba.
			{"editar", http.MethodPatch, "/api/distribuidores/" + distMariaStg.String(), `{"nombre":"María Elena"}`, http.StatusOK},
			{"retirar (lo usa una ruta)", http.MethodDelete, "/api/distribuidores/" + distJuanStg.String(), ``, http.StatusOK},
			{"borrar (sin rutas)", http.MethodDelete, "/api/distribuidores/" + distMariaStg.String(), ``, http.StatusOK},
		}
		for _, c := range casos {
			t.Run(nombre+": "+c.nombre, func(t *testing.T) {
				stg, hol := bus(t)
				d, _, _ := nuevoDobleDeDistribuidores()
				codigoDist(t, llamarDist(t, montarDist(t, d), c.metodo, c.ruta, jwt(t), "", c.cuerpo), c.codigo)

				cambio, hay := recibio(stg)
				if !hay {
					t.Fatal("el cambio no llegó ni a la sucursal del distribuidor: la pantalla de Vehículos no vive de " +
						"la base local, así que sin este aviso no hay nada que repinte la lista de distribuidores")
				}
				if cambio.Tipo != CambioVehiculos {
					t.Errorf("salió el tipo %q y le toca %q", cambio.Tipo, CambioVehiculos)
				}
				if cambio.Sucursal != stgDeRutas.String() {
					t.Errorf("el aviso salió con la sucursal %q y tenía que salir con la de Santiago (%s), que es la del "+
						"distribuidor que se tocó, también cuando quien lo toca ve las ocho", cambio.Sucursal, stgDeRutas)
				}
				if _, hay := recibio(hol); hay {
					t.Error("un cambio en un distribuidor de Santiago LLEGÓ a Holguín: son pantallas que piden la lista " +
						"entera a la red y un ciclo de sincronización cada una, por la conexión de allá, para pintar lo mismo")
				}
			})
		}
	}

	t.Run("crear", func(t *testing.T) {
		stg, hol := bus(t)
		d, _, _ := nuevoDobleDeDistribuidores()
		codigoDist(t, llamarDist(t, montarDist(t, d), http.MethodPost, "/api/distribuidores", logisticoDe(t, stgDeRutas), "",
			`{"nombre":"Ana Torres"}`), http.StatusCreated)
		cambio, hay := recibio(stg)
		if !hay || cambio.Tipo != CambioVehiculos || cambio.Sucursal != stgDeRutas.String() {
			t.Fatalf("crear un distribuidor de Santiago tenía que avisar a Santiago con %q: %+v (%v)", CambioVehiculos, cambio, hay)
		}
		if _, hay := recibio(hol); hay {
			t.Error("crear un distribuidor de Santiago llegó a Holguín")
		}
	})
}

// LO QUE NO SE ESCRIBIÓ NO SE AVISA: 404, 409 y 400 no mueven ninguna pantalla.
func TestLoQueNoSeEscribioDelNomencladorNoSeAvisa(t *testing.T) {
	santiago := logisticoDe(t, stgDeRutas)
	casos := []struct {
		nombre, metodo, ruta, cuerpo string
		codigo                       int
	}{
		{"editar el de Holguín (404)", http.MethodPatch, "/api/distribuidores/" + distJuanHol.String(), `{"nombre":"X"}`, http.StatusNotFound},
		{"borrar el de Holguín (404)", http.MethodDelete, "/api/distribuidores/" + distJuanHol.String(), ``, http.StatusNotFound},
		{"crear uno repetido (409)", http.MethodPost, "/api/distribuidores", `{"nombre":"juan pérez"}`, http.StatusConflict},
		{"renombrar a uno repetido (409)", http.MethodPatch, "/api/distribuidores/" + distMariaStg.String(), `{"nombre":"Juan Pérez"}`, http.StatusConflict},
		{"crear sin nombre (400)", http.MethodPost, "/api/distribuidores", `{}`, http.StatusBadRequest},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			avisos := contarAvisos(t)
			d, _, _ := nuevoDobleDeDistribuidores()
			codigoDist(t, llamarDist(t, montarDist(t, d), c.metodo, c.ruta, santiago, "", c.cuerpo), c.codigo)
			avisos.exigeSilencio(t, c.nombre)
		})
	}

	t.Run("pareja: editar uno suyo SÍ avisa, y con la sucursal de la fila", func(t *testing.T) {
		avisos := contarAvisos(t)
		d, _, _ := nuevoDobleDeDistribuidores()
		codigoDist(t, llamarDist(t, montarDist(t, d), http.MethodPatch, "/api/distribuidores/"+distMariaStg.String(), santiago, "",
			`{"nombre":"María Elena"}`), http.StatusOK)
		avisos.exige(t, "editar un distribuidor", CambioVehiculos)
		if suc, _ := avisos.sucursalDe(CambioVehiculos); suc != stgDeRutas.String() {
			t.Fatalf("el aviso salió con la sucursal %q y tenía que salir con la de la fila (%s)", suc, stgDeRutas)
		}
	})
}

// bus deja un bus limpio con un suscriptor por sucursal (Santiago y Holguín) y los devuelve.
func bus(t *testing.T) (stg, hol <-chan Cambio) {
	t.Helper()
	anterior := busEventos
	t.Cleanup(func() { busEventos = anterior })
	busEventos = NuevoDifusor()
	stg, cortarStg, _ := busEventos.SuscribirDe(stgDeRutas.String())
	t.Cleanup(cortarStg)
	hol, cortarHol, _ := busEventos.SuscribirDe(holDeRutas.String())
	t.Cleanup(cortarHol)
	return stg, hol
}
