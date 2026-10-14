package api

// LOS TIPOS DE VEHÍCULO SON POR SUCURSAL — Jose, 14/10/2026 (migración 00018).
//
// Hasta ese día `vehicle_types` era un catálogo de toda la empresa y el costo por km del tipo
// es el que cotiza el domicilio: el logístico de Santiago editaba «truck» y movía el precio en
// las ocho. Ahora cada sucursal tiene SUS tipos y quien trabaja en una ve y toca sólo los suyos;
// los de otra sucursal y los «de todas» (`branch_id` nulo, los camiones compartidos) le son un 404,
// no un 403, como el resto del alcance de esta api.
//
// QUÉ PRUEBA ESTO Y QUÉ NO. Va contra el doble `dobleAvisos`, que reimplementa el SQL en Go:
// comprueba que el manejador y `alcance.Acotado` PASAN la sucursal que toca (quien la quite de
// `Acotado` pone esto en rojo). Que el SQL de verdad la use lo prueba
// `store/sqlc/consultas_motor_real_test.go` contra Postgres, que es lo único que ve la base.
//
// TODO VA EN PAREJA: cada «no» tiene su «sí» al lado, para que una prueba que dice 404 no pase
// con el recurso roto del todo.

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

// --------------------------------------------------------------------------- personas

func avLogisticoDe(t *testing.T, sucursal uuid.UUID) string {
	t.Helper()
	return tokenDeDatos(t, map[string]any{"sub": "p-log-" + sucursal.String(), "email": "log@procovar.cu",
		"role": "LOGISTICO", "branchId": sucursal.String(), "entradas": []string{"delivery.entrar"}})
}

// avSuperSinSucursal: un SUPER ADMIN SIN sucursal, o sea el alcance «todas».
func avSuperSinSucursal(t *testing.T) string {
	t.Helper()
	return tokenDeDatos(t, map[string]any{"sub": "p-super", "email": "super@procovar.cu",
		"role": "SUPER ADMIN", "entradas": []string{"delivery.entrar"}})
}

// pedirDe es `pedirAv` con la cabecera de sucursal, que es como un SUPER ADMIN elige cuál mira.
func pedirDe(t *testing.T, h http.Handler, metodo, ruta, jwt, sucursal, cuerpo string) *httptest.ResponseRecorder {
	t.Helper()
	var lector io.Reader
	if cuerpo != "" {
		lector = strings.NewReader(cuerpo)
	}
	r := httptest.NewRequest(metodo, ruta, lector)
	r.Header.Set("Authorization", "Bearer "+jwt)
	if sucursal != "" {
		r.Header.Set("X-Sucursal-Id", sucursal)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func tiposDe(t *testing.T, w *httptest.ResponseRecorder) []TipoVehiculoSalida {
	t.Helper()
	avCodigo(t, w, http.StatusOK)
	var tipos []TipoVehiculoSalida
	if err := json.Unmarshal(w.Body.Bytes(), &tipos); err != nil {
		t.Fatalf("la lista de tipos no es JSON: %v: %s", err, w.Body.String())
	}
	return tipos
}

func idsDe(tipos []TipoVehiculoSalida) map[uuid.UUID]bool {
	ids := map[uuid.UUID]bool{}
	for _, tp := range tipos {
		ids[tp.ID] = true
	}
	return ids
}

func tipoDe(t *testing.T, w *httptest.ResponseRecorder, codigo int) TipoVehiculoSalida {
	t.Helper()
	avCodigo(t, w, codigo)
	var tp TipoVehiculoSalida
	if err := json.Unmarshal(w.Body.Bytes(), &tp); err != nil {
		t.Fatalf("la respuesta no es un tipo: %v: %s", err, w.Body.String())
	}
	return tp
}

// --------------------------------------------------------------------------- listar

// CADA SUCURSAL VE SÓLO SUS TIPOS. Y quien ve todas, todos, con la sucursal de cada uno: el
// mismo «truck» está tres veces y sin `sucursalId` ni `sucursal` no se sabe cuál es cuál.
func TestCadaSucursalVeSoloSusTipos(t *testing.T) {
	h := montarAvisos(t, &dobleAvisos{})

	t.Run("Santiago ve el suyo, con su sucursal, y ni el de Holguín ni el de todas", func(t *testing.T) {
		tipos := tiposDe(t, pedirAv(t, h, http.MethodGet, "/api/vehicle-types", avLogisticoDe(t, avSucStg), ""))
		if len(tipos) != 1 || tipos[0].ID != avTipoCam {
			t.Fatalf("Santiago tenía que ver sólo su «truck» (%s) y vio %+v", avTipoCam, tipos)
		}
		if tipos[0].SucursalID == nil || *tipos[0].SucursalID != avSucStg ||
			tipos[0].Sucursal == nil || *tipos[0].Sucursal != "Santiago" {
			t.Fatalf("el tipo tiene que decir de quién es: %+v", tipos[0])
		}
	})

	t.Run("Holguín ve el suyo, no el de Santiago", func(t *testing.T) {
		tipos := tiposDe(t, pedirAv(t, h, http.MethodGet, "/api/vehicle-types", avLogisticoDe(t, avSucHol), ""))
		if len(tipos) != 1 || tipos[0].ID != avTipoHol {
			t.Fatalf("Holguín tenía que ver sólo su «truck» (%s) y vio %+v", avTipoHol, tipos)
		}
	})

	t.Run("un SUPER ADMIN sin sucursal ve los tres, y el de todas sale sin sucursal", func(t *testing.T) {
		tipos := tiposDe(t, pedirAv(t, h, http.MethodGet, "/api/vehicle-types", avSuperSinSucursal(t), ""))
		ids := idsDe(tipos)
		if len(tipos) != 3 || !ids[avTipoCam] || !ids[avTipoHol] || !ids[avTipoTodas] {
			t.Fatalf("quien ve todas tenía que ver los tres y vio %+v", tipos)
		}
		for _, tp := range tipos {
			if tp.ID == avTipoTodas && (tp.SucursalID != nil || tp.Sucursal != nil) {
				t.Fatalf("el tipo «de todas» tiene que salir con sucursalId y sucursal nulos: %+v", tp)
			}
		}
	})

	t.Run("un SUPER ADMIN que mira Holguín ve sólo lo de Holguín, ni siquiera el de todas", func(t *testing.T) {
		tipos := tiposDe(t, pedirDe(t, h, http.MethodGet, "/api/vehicle-types", avSuperSinSucursal(t), avSucHol.String(), ""))
		if len(tipos) != 1 || tipos[0].ID != avTipoHol {
			t.Fatalf("mirando Holguín tenía que ver sólo su «truck» y vio %+v", tipos)
		}
	})
}

// --------------------------------------------------------------------------- editar y borrar

// SANTIAGO NO TOCA EL TIPO DE HOLGUÍN NI EL «DE TODAS»: 404 —no 403—, y no se escribe nada.
// En PAREJA: el suyo sí, y quien ve todas toca cualquiera.
func TestSantiagoNoTocaLosTiposDeHolguinNiLosDeTodas(t *testing.T) {
	santiago := avLogisticoDe(t, avSucStg)

	for nombre, ajeno := range map[string]uuid.UUID{"el de Holguín": avTipoHol, "el de todas": avTipoTodas} {
		for _, p := range []struct{ metodo, cuerpo string }{
			{http.MethodPatch, `{"costoKmUsd":0.9}`},
			{http.MethodDelete, ``},
		} {
			t.Run(p.metodo+" de Santiago sobre "+nombre+": 404 y no escribe", func(t *testing.T) {
				d := &dobleAvisos{}
				w := pedirAv(t, montarAvisos(t, d), p.metodo, "/api/vehicle-types/"+ajeno.String(), santiago, p.cuerpo)
				avCodigo(t, w, http.StatusNotFound)
				if d.escritosTipos != 0 {
					t.Fatalf("el 404 llegó DESPUÉS de escribir: %d escrituras sobre el catálogo", d.escritosTipos)
				}
			})
		}
	}

	t.Run("PATCH de Santiago sobre el suyo: pasa", func(t *testing.T) {
		d := &dobleAvisos{}
		w := pedirAv(t, montarAvisos(t, d), http.MethodPatch, "/api/vehicle-types/"+avTipoCam.String(), santiago, `{"costoKmUsd":0.9}`)
		avCodigo(t, w, http.StatusOK)
		if d.escritosTipos != 1 {
			t.Fatalf("tenía que escribir una vez: %d", d.escritosTipos)
		}
	})

	t.Run("DELETE de Santiago sobre el suyo, que usa un camión: se retira", func(t *testing.T) {
		w := pedirAv(t, montarAvisos(t, &dobleAvisos{}), http.MethodDelete, "/api/vehicle-types/"+avTipoCam.String(), santiago, "")
		avCodigo(t, w, http.StatusOK)
		if !strings.Contains(w.Body.String(), `"retirado":true`) {
			t.Fatalf("lo usa un camión, así que se retira y no se borra: %s", w.Body.String())
		}
	})

	t.Run("quien ve todas sí toca el de Holguín y el de todas", func(t *testing.T) {
		d := &dobleAvisos{}
		h := montarAvisos(t, d)
		for _, id := range []uuid.UUID{avTipoHol, avTipoTodas} {
			avCodigo(t, pedirAv(t, h, http.MethodPatch, "/api/vehicle-types/"+id.String(), avSuperSinSucursal(t),
				`{"costoKmUsd":0.9}`), http.StatusOK)
		}
	})

	t.Run("un SUPER ADMIN que mira Santiago no toca el de Holguín", func(t *testing.T) {
		// Elegir sucursal ACOTA, no abre: mirando Santiago, el tipo de Holguín es un 404.
		w := pedirDe(t, montarAvisos(t, &dobleAvisos{}), http.MethodPatch, "/api/vehicle-types/"+avTipoHol.String(),
			avSuperSinSucursal(t), avSucStg.String(), `{"costoKmUsd":0.9}`)
		avCodigo(t, w, http.StatusNotFound)
	})
}

// --------------------------------------------------------------------------- crear

// UN TIPO NUEVO NACE EN LA SUCURSAL DE QUIEN LO CREA, y no en la que mande el cliente.
func TestUnTipoNuevoNaceEnLaSucursalDeQuienLoCrea(t *testing.T) {
	h := montarAvisos(t, &dobleAvisos{})

	t.Run("Santiago", func(t *testing.T) {
		tp := tipoDe(t, pedirAv(t, h, http.MethodPost, "/api/vehicle-types", avLogisticoDe(t, avSucStg), `{"nombre":"rastra"}`), http.StatusCreated)
		if tp.SucursalID == nil || *tp.SucursalID != avSucStg || tp.Sucursal == nil || *tp.Sucursal != "Santiago" {
			t.Fatalf("el tipo de Santiago tenía que nacer en Santiago: %+v", tp)
		}
	})

	t.Run("el cuerpo no elige la sucursal", func(t *testing.T) {
		// Aunque el cliente mande otra, manda quién pregunta (CLAUDE.md §4).
		tp := tipoDe(t, pedirAv(t, h, http.MethodPost, "/api/vehicle-types", avLogisticoDe(t, avSucStg),
			`{"nombre":"furgon","sucursalId":"`+avSucHol.String()+`","branchId":"`+avSucHol.String()+`"}`), http.StatusCreated)
		if tp.SucursalID == nil || *tp.SucursalID != avSucStg {
			t.Fatalf("el cuerpo movió el tipo de sucursal: %+v", tp)
		}
	})

	t.Run("un SUPER ADMIN sin sucursal lo deja «de todas»", func(t *testing.T) {
		tp := tipoDe(t, pedirAv(t, h, http.MethodPost, "/api/vehicle-types", avSuperSinSucursal(t), `{"nombre":"gandola"}`), http.StatusCreated)
		if tp.SucursalID != nil || tp.Sucursal != nil {
			t.Fatalf("sin sucursal elegida el tipo nace «de todas»: %+v", tp)
		}
	})

	t.Run("un SUPER ADMIN que mira Holguín lo crea en Holguín", func(t *testing.T) {
		tp := tipoDe(t, pedirDe(t, h, http.MethodPost, "/api/vehicle-types", avSuperSinSucursal(t), avSucHol.String(), `{"nombre":"chata"}`), http.StatusCreated)
		if tp.SucursalID == nil || *tp.SucursalID != avSucHol {
			t.Fatalf("mirando Holguín el tipo tenía que nacer en Holguín: %+v", tp)
		}
	})
}

// EL MISMO NOMBRE EN DOS SUCURSALES SÍ; EN LA MISMA, NO. Y uno igual al de un tipo «de todas» NO es
// un choque: quien tiene sucursal no ve los «de todas» ni puede ponérselos a un camión suyo, así que
// negarle el nombre sería esconderle algo por un motivo que no puede ver.
func TestElMismoNombreEnDosSucursalesSiEnLaMismaNo(t *testing.T) {
	h := montarAvisos(t, &dobleAvisos{})
	santiago, holguin := avLogisticoDe(t, avSucStg), avLogisticoDe(t, avSucHol)

	avCodigo(t, pedirAv(t, h, http.MethodPost, "/api/vehicle-types", santiago, `{"nombre":"rastra"}`), http.StatusCreated)

	w := pedirAv(t, h, http.MethodPost, "/api/vehicle-types", santiago, `{"nombre":"rastra"}`)
	avCodigo(t, w, http.StatusConflict)
	if !strings.Contains(w.Body.String(), "Ya existe un tipo de vehículo con ese nombre") {
		t.Fatalf("el 409 no dice por qué: %s", w.Body.String())
	}

	avCodigo(t, pedirAv(t, h, http.MethodPost, "/api/vehicle-types", holguin, `{"nombre":"rastra"}`), http.StatusCreated)

	// «truck» es el nombre del tipo «de todas»: Santiago ya tiene el suyo (409), pero un nombre que
	// SÓLO existe «de todas» no le estorba.
	avCodigo(t, pedirAv(t, h, http.MethodPost, "/api/vehicle-types", santiago, `{"nombre":"truck"}`), http.StatusConflict)
	avCodigo(t, pedirAv(t, h, http.MethodPost, "/api/vehicle-types", avSuperSinSucursal(t), `{"nombre":"gandola"}`), http.StatusCreated)
	avCodigo(t, pedirAv(t, h, http.MethodPost, "/api/vehicle-types", santiago, `{"nombre":"gandola"}`), http.StatusCreated)

	// Y renombrar a uno que ya existe EN LA MISMA sucursal es 409; a uno de otra, no.
	avCodigo(t, pedirAv(t, h, http.MethodPatch, "/api/vehicle-types/"+avTipoCam.String(), santiago, `{"nombre":"rastra"}`), http.StatusConflict)
	avCodigo(t, pedirAv(t, h, http.MethodPatch, "/api/vehicle-types/"+avTipoHol.String(), holguin, `{"nombre":"gandola"}`), http.StatusOK)
}

// --------------------------------------------------------------------------- los camiones

// EL TIPO DE UN CAMIÓN ES DE LA SUCURSAL DEL CAMIÓN. Cada «no» (400, con su motivo) con su «sí».
func TestElTipoDeUnCamionEsDeLaSucursalDelCamion(t *testing.T) {
	// Un tipo que sólo existe en Holguín.
	conRastraDeHolguin := func() *dobleAvisos {
		d := &dobleAvisos{}
		*d.catalogo() = append(*d.catalogo(), tipoDePrueba{VehicleType: sqlcTipo("rastra", avPg(avSucHol))})
		return d
	}

	t.Run("el camión de Santiago admite el tipo de Santiago", func(t *testing.T) {
		d := conRastraDeHolguin()
		w := pedirAv(t, montarAvisos(t, d), http.MethodPost, "/api/vehicles", avLogisticoDe(t, avSucStg), `{"name":"c","type":"truck"}`)
		avCodigo(t, w, http.StatusCreated)
		if !strings.Contains(w.Body.String(), avTipoCam.String()) {
			t.Fatalf("el camión de Santiago tenía que llevar el «truck» de Santiago (%s): %s", avTipoCam, w.Body.String())
		}
		if len(d.buscadoPara) != 1 || d.buscadoPara[0] != avPg(avSucStg) {
			t.Fatalf("el tipo se buscó para %+v y el camión nace en Santiago", d.buscadoPara)
		}
	})

	t.Run("pero no el de Holguín: 400 con el motivo", func(t *testing.T) {
		w := pedirAv(t, montarAvisos(t, conRastraDeHolguin()), http.MethodPost, "/api/vehicles", avLogisticoDe(t, avSucStg), `{"name":"c","type":"rastra"}`)
		avCodigo(t, w, http.StatusBadRequest)
		if !strings.Contains(w.Body.String(), "No existe el tipo de vehículo 'rastra'") ||
			!strings.Contains(w.Body.String(), "su sucursal") {
			t.Fatalf("el 400 no dice qué pasa: %s", w.Body.String())
		}
	})

	t.Run("y Holguín sí tiene el suyo", func(t *testing.T) {
		w := pedirAv(t, montarAvisos(t, conRastraDeHolguin()), http.MethodPost, "/api/vehicles", avLogisticoDe(t, avSucHol), `{"name":"c","type":"rastra"}`)
		avCodigo(t, w, http.StatusCreated)
	})

	t.Run("un camión COMPARTIDO (lo da de alta quien ve todas) sólo admite tipos «de todas»", func(t *testing.T) {
		d := conRastraDeHolguin()
		h := montarAvisos(t, d)
		w := pedirAv(t, h, http.MethodPost, "/api/vehicles", avSuperSinSucursal(t), `{"name":"c","type":"truck"}`)
		avCodigo(t, w, http.StatusCreated)
		if !strings.Contains(w.Body.String(), avTipoTodas.String()) {
			t.Fatalf("el compartido tenía que llevar el «truck» de TODAS (%s): %s", avTipoTodas, w.Body.String())
		}
		if len(d.buscadoPara) != 1 || d.buscadoPara[0].Valid {
			t.Fatalf("el tipo se buscó para %+v y el camión nace compartido (nulo)", d.buscadoPara)
		}
		w = pedirAv(t, h, http.MethodPost, "/api/vehicles", avSuperSinSucursal(t), `{"name":"c","type":"rastra"}`)
		avCodigo(t, w, http.StatusBadRequest)
		if !strings.Contains(w.Body.String(), "«de todas»") {
			t.Fatalf("el 400 tenía que decir que un compartido sólo admite los «de todas»: %s", w.Body.String())
		}
	})
}

// AL EDITAR, EL TIPO SE BUSCA PARA EL CAMIÓN QUE SE EDITA Y NO PARA QUIEN LO EDITA. Dos casos que se
// equivocarían si se mirara el alcance de quien llama: un SUPER ADMIN que mira Santiago y edita un
// camión compartido; y uno en modo «todas» que edita el camión de Santiago.
func TestAlEditarElTipoSeBuscaParaElCamionNoParaQuienLoEdita(t *testing.T) {
	t.Run("un compartido, tocado por un SUPER ADMIN que mira Santiago: el tipo es el de todas", func(t *testing.T) {
		d := &dobleAvisos{camionCompartido: true}
		w := pedirDe(t, montarAvisos(t, d), http.MethodPatch, "/api/vehicles/"+avVehStg.String(),
			avSuperSinSucursal(t), avSucStg.String(), `{"type":"truck"}`)
		avCodigo(t, w, http.StatusOK)
		if len(d.buscadoPara) != 1 || d.buscadoPara[0].Valid {
			t.Fatalf("el compartido no tiene sucursal, pero el tipo se buscó para %+v", d.buscadoPara)
		}
		if d.tipoEscrito != avPg(avTipoTodas) {
			t.Fatalf("el compartido tenía que quedar con el «truck» de todas y quedó con %+v", d.tipoEscrito)
		}
	})

	t.Run("el de Santiago, tocado por un SUPER ADMIN en modo «todas»: el tipo es el de Santiago", func(t *testing.T) {
		d := &dobleAvisos{}
		w := pedirAv(t, montarAvisos(t, d), http.MethodPatch, "/api/vehicles/"+avVehStg.String(),
			avSuperSinSucursal(t), `{"type":"truck"}`)
		avCodigo(t, w, http.StatusOK)
		if d.tipoEscrito != avPg(avTipoCam) {
			t.Fatalf("el camión de Santiago tenía que quedar con el «truck» de Santiago y quedó con %+v", d.tipoEscrito)
		}
	})

	t.Run("un tipo de otra sucursal sobre un camión de Santiago: 400 y no escribe", func(t *testing.T) {
		d := &dobleAvisos{}
		*d.catalogo() = append(*d.catalogo(), tipoDePrueba{VehicleType: sqlcTipo("rastra", avPg(avSucHol))})
		w := pedirAv(t, montarAvisos(t, d), http.MethodPatch, "/api/vehicles/"+avVehStg.String(),
			avLogisticoDe(t, avSucStg), `{"type":"rastra"}`)
		avCodigo(t, w, http.StatusBadRequest)
		if d.escritos != 0 {
			t.Fatalf("el 400 llegó DESPUÉS de escribir: %d escrituras", d.escritos)
		}
	})
}

// --------------------------------------------------------------------------- una sucursal nueva

// UNA SUCURSAL NUEVA NACE CON LOS TIPOS «DE TODAS». Sin ellos empezaría con el catálogo vacío y su
// primer camión (`type` por defecto: «truck») daría 400. En PAREJA: si el alta se rechaza, no se
// siembra nada.
func TestUnaSucursalNuevaNaceConLosTiposDeTodas(t *testing.T) {
	d := &dobleAvisos{}
	h := montarAvisos(t, d)

	w := pedirAv(t, h, http.MethodPost, "/api/branches", avSuperSinSucursal(t), `{"name":"Bayamo"}`)
	avCodigo(t, w, http.StatusBadRequest)
	if len(d.sembradas) != 0 {
		t.Fatalf("el alta se rechazó y aun así se sembraron tipos: %v", d.sembradas)
	}

	w = pedirAv(t, h, http.MethodPost, "/api/branches", avSuperSinSucursal(t), `{"name":"Bayamo","lat":20.38,"lng":-76.64}`)
	avCodigo(t, w, http.StatusCreated)
	var creada struct {
		ID uuid.UUID `json:"id"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &creada); err != nil {
		t.Fatal(err)
	}
	if len(d.sembradas) != 1 || d.sembradas[0] != creada.ID {
		t.Fatalf("la sucursal nueva (%s) tenía que recibir los tipos «de todas» y se sembró %v", creada.ID, d.sembradas)
	}
}

func sqlcTipo(nombre string, sucursal pgtype.UUID) sqlc.VehicleType {
	return sqlc.VehicleType{ID: uuid.New(), Nombre: nombre, Activo: true, BranchID: sucursal}
}
