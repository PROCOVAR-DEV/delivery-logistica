package api

// EL RASTRO DE QUIÉN — 08/10/2026 (auditoría de la 1.0.28).
//
// Quitar una parada, borrar una ruta, cerrarla, cambiarle el camión, dar de alta/editar/
// borrar un camión, guardar la tasa y lanzar el recosteo cambian datos de la casa. Hasta
// hoy no dejaban escrito DE QUIÉN: cuando una ruta desaparece, el registro es la única
// respuesta que va a existir. Cada una deja UNA línea Info con `actor` (el `sub`) y los ids.
//
// EN PAREJA, como todo aquí: la línea sale cuando la acción se hace, NO sale cuando se
// rechaza (un aviso de «borró» sobre algo que no se borró es peor que no tener aviso); y en
// ningún caso lleva el token, ni su cuerpo, ni su firma (`TestElRastroNoEnsenaElToken`).

import (
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"procovar/reparto-api/internal/httpx"

	"github.com/google/uuid"
)

// Reset completa el `registroSeguro` de canal_pedido_test.go (que ya tiene candado): `avisarDeFondo`
// (rutas.go) escribe en el registro DESPUÉS de contestar, en su gorutina, mientras la prueba hace
// `Reset`/`String`. Con un `bytes.Buffer` pelado eso es una carrera que `go test -race` canta
// (13 por prueba, 09/10/2026).
func (r *registroSeguro) Reset() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.buf.Reset()
}

// sinElToken falla si el registro lleva la credencial entera, su cuerpo o su firma.
func sinElToken(t *testing.T, registro, jwt string) {
	t.Helper()
	partes := strings.Split(jwt, ".")
	if len(partes) != 3 {
		t.Fatalf("la prueba esperaba un JWT: %q", jwt)
	}
	for _, prohibido := range []string{jwt, partes[1], partes[2], "Bearer"} {
		if strings.Contains(registro, prohibido) {
			t.Fatalf("EL REGISTRO LLEVA LA CREDENCIAL (%.12q…):\n%s", prohibido, registro)
		}
	}
}

// lineaCon devuelve la línea del registro que contiene el mensaje, o "".
func lineaCon(registro, mensaje string) string {
	for _, l := range strings.Split(registro, "\n") {
		if strings.Contains(l, "msg=\""+mensaje+"\"") || strings.Contains(l, "msg="+mensaje+" ") {
			return l
		}
	}
	return ""
}

func TestLasAccionesDeRutasDejanQuienFue(t *testing.T) {
	d, stg, _ := datosDeReparto()
	var registro registroSeguro
	h, _ := montarRutasRegistrando(t, d, &registro)
	jwt := deSantiagoEnRutas(t)
	compartido := uuid.MustParse("aaaaaaaa-0000-0000-0000-00000000000c")
	d.camiones[compartido] = &camionDeRutas{id: compartido, nombre: "Compartido", capacidad: 500,
		estado: "available"}

	ruta := armarRutaDePrueba(t, h, jwt, stg[0], stg[1])
	outra := armarRutaDePrueba(t, h, jwt, stg[2])

	casos := []struct {
		mensaje string
		metodo  string
		ruta    string
		cuerpo  string
		ids     []string // lo que tiene que nombrar la línea
	}{
		{"parada quitada de una ruta planificada", http.MethodDelete,
			fmt.Sprintf("/api/routes/%s/stops/%s", ruta, stg[0]), "", []string{ruta.String(), stg[0].String()}},
		{"ruta: camión cambiado", http.MethodPatch, "/api/routes/" + ruta.String(),
			fmt.Sprintf(`{"vehicleId":%q}`, compartido), []string{ruta.String(), compartido.String()}},
		{"ruta: estado cambiado", http.MethodPatch, "/api/routes/" + ruta.String(),
			`{"status":"in_progress"}`, []string{ruta.String(), "a=in_progress"}},
		{"cierre de ruta guardado", http.MethodPost, "/api/routes/" + ruta.String() + "/results",
			fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, stg[1]), []string{ruta.String(), "aplicados=1"}},
		{"ruta: estado cambiado", http.MethodPatch, "/api/routes/" + ruta.String(),
			`{"status":"completed"}`, []string{ruta.String(), "a=completed"}},
		{"ruta borrada", http.MethodDelete, "/api/routes/" + outra.String(), "", []string{outra.String()}},
	}
	for _, c := range casos {
		registro.Reset()
		w := llamarRutas(t, h, c.metodo, c.ruta, jwt, c.cuerpo)
		if w.Code != http.StatusOK && w.Code != http.StatusCreated {
			t.Fatalf("%s: la acción no se hizo (%d): %s", c.mensaje, w.Code, w.Body.String())
		}
		l := lineaCon(registro.String(), c.mensaje)
		if l == "" {
			t.Fatalf("%s: no dejó la línea de quién:\n%s", c.mensaje, registro.String())
		}
		for _, quiero := range append([]string{"level=INFO", "actor=p-stg", "rol=LOGISTICO"}, c.ids...) {
			if !strings.Contains(l, quiero) {
				t.Errorf("%s: a la línea le falta %q:\n%s", c.mensaje, quiero, l)
			}
		}
		sinElToken(t, registro.String(), jwt)
	}
}

// LA PAREJA: lo que se rechaza no deja la línea de «lo hizo».
func TestLoQueSeRechazaNoDejaLaLineaDeQuienLoHizo(t *testing.T) {
	d, stg, ajeno := datosDeReparto()
	var registro registroSeguro
	h, _ := montarRutasRegistrando(t, d, &registro)
	jwt := deSantiagoEnRutas(t)
	ruta := armarRutaDePrueba(t, h, jwt, stg[1])

	registro.Reset()
	intentos := []struct{ metodo, ruta, cuerpo string }{
		{http.MethodDelete, "/api/routes/" + uuid.New().String(), ""},                                                                                 // no existe
		{http.MethodDelete, fmt.Sprintf("/api/routes/%s/stops/%s", ruta, ajeno), ""},                                                                  // parada que no es de la ruta
		{http.MethodPost, "/api/routes/" + ruta.String() + "/results", `{"resultados":[]}`},                                                           // cierre vacío
		{http.MethodPost, "/api/routes/" + ruta.String() + "/results", fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, ajeno)}, // 409 sin guardar nada
	}
	for _, c := range intentos {
		w := llamarRutas(t, h, c.metodo, c.ruta, jwt, c.cuerpo)
		if w.Code < 400 {
			t.Fatalf("%s %s tenía que rechazarse y fue %d", c.metodo, c.ruta, w.Code)
		}
	}
	for _, mensaje := range []string{"ruta borrada", "parada quitada de una ruta planificada", "cierre de ruta guardado"} {
		if l := lineaCon(registro.String(), mensaje); l != "" {
			t.Errorf("se escribió %q aunque la acción se rechazó:\n%s", mensaje, l)
		}
	}
}

func TestLasAccionesDeFlotaYAjustesDejanQuienFue(t *testing.T) {
	var registro registroSeguro
	destinoDelRegistroDePruebas = &registro
	defer func() { destinoDelRegistroDePruebas = io.Discard }()
	h := montarAvisos(t, &dobleAvisos{})
	jwt := avLogisticoStg(t)

	casos := []struct {
		mensaje, metodo, ruta, cuerpo, jwt string
		quiero                             []string
	}{
		{"vehículo creado", http.MethodPost, "/api/vehicles", `{"name":"Camión #9"}`, jwt, []string{"actor=p-stg", "vehiculo="}},
		{"vehículo editado", http.MethodPatch, "/api/vehicles/" + avVehStg.String(), `{"isActive":false}`, jwt,
			[]string{"actor=p-stg", "vehiculo=" + avVehStg.String(), "activo=" + "false"}},
		{"vehículo borrado", http.MethodDelete, "/api/vehicles/" + avVehStg.String(), "", jwt,
			[]string{"actor=p-stg", "vehiculo=" + avVehStg.String()}},
		{"ajustes guardados", http.MethodPut, "/api/settings", `{"cupRate":340}`, avAdmin(t),
			[]string{"actor=p-super", "rol=\"SUPER ADMIN\"", "tasa_cup="}},
	}
	for _, c := range casos {
		registro.Reset()
		w := pedirAv(t, h, c.metodo, c.ruta, c.jwt, c.cuerpo)
		if w.Code != http.StatusOK && w.Code != http.StatusCreated {
			t.Fatalf("%s: %d %s", c.mensaje, w.Code, w.Body.String())
		}
		l := lineaCon(registro.String(), c.mensaje)
		if l == "" {
			t.Fatalf("%s: no dejó la línea de quién:\n%s", c.mensaje, registro.String())
		}
		for _, q := range c.quiero {
			if !strings.Contains(l, q) {
				t.Errorf("%s: a la línea le falta %q:\n%s", c.mensaje, q, l)
			}
		}
		sinElToken(t, registro.String(), c.jwt)
	}

	// LA PAREJA: el 403 del camión compartido no deja «vehículo editado».
	registro.Reset()
	w := pedirAv(t, montarAvisos(t, &dobleAvisos{camionCompartido: true}), http.MethodPatch,
		"/api/vehicles/"+avVehStg.String(), jwt, `{"isActive":false}`)
	if w.Code != http.StatusForbidden {
		t.Fatalf("%d", w.Code)
	}
	if l := lineaCon(registro.String(), "vehículo editado"); l != "" {
		t.Errorf("se escribió «vehículo editado» aunque el 403 lo impidió:\n%s", l)
	}
}

func TestElRecosteoDejaQuienLoLanzo(t *testing.T) {
	var registro registroSeguro
	destinoDelRegistroDePruebas = &registro
	defer func() { destinoDelRegistroDePruebas = io.Discard }()

	pedido := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"orders":[{"id":"p-1"}]}`))
	}))
	defer pedido.Close()
	lote := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"weightsSource":"warehouse","results":[]}`))
	}))
	defer lote.Close()
	t.Setenv("SERVICE_API_KEY", "clave")
	t.Setenv("PEDIDO_API_URL", pedido.URL)
	t.Setenv("DELIVERY_URL", lote.URL)
	h := montarTab(t, nuevoEspejo())

	jwt := tokenTab(t, sucStg.String())
	w := pedirTab(t, h, http.MethodPost, "/api/admin/recompute?dias=7", jwt, "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	l := lineaCon(registro.String(), "recosteo lanzado")
	if l == "" {
		t.Fatalf("el recosteo no dejó la línea de quién:\n%s", registro.String())
	}
	for _, q := range []string{"actor=p-logistico", "dias=7", "sucursal=STG"} {
		if !strings.Contains(l, q) {
			t.Errorf("a la línea le falta %q:\n%s", q, l)
		}
	}
	sinElToken(t, registro.String(), jwt)

	// La pareja: sin la clave de servicio configurada el recosteo ni empieza, y no deja
	// la línea de «lanzado».
	registro.Reset()
	t.Setenv("SERVICE_API_KEY", "")
	h = montarTab(t, nuevoEspejo())
	w = pedirTab(t, h, http.MethodPost, "/api/admin/recompute", jwt, "")
	if w.Code != http.StatusInternalServerError {
		t.Fatalf("código %d", w.Code)
	}
	if lineaCon(registro.String(), "recosteo lanzado") != "" {
		t.Errorf("dejó «recosteo lanzado» sin lanzarse:\n%s", registro.String())
	}
}

// llamarRutasConCabeceras es llamarRutas con las cabeceras que `sync` pone al aplicar una revisión.
func llamarRutasConCabeceras(t *testing.T, h http.Handler, metodo, ruta, jwt string, cab map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(metodo, ruta, nil)
	if jwt != "" {
		r.Header.Set("Authorization", "Bearer "+jwt)
	}
	for k, v := range cab {
		r.Header.Set(k, v)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

// LA AUTORÍA DE LA BANDEJA DE REVISIÓN (paquete P). `X-Autor` y `X-Revision` se ESCRIBEN en la línea
// general de la petición (`httpx.RegistrarPeticiones`) de TODA escritura —también las que no llaman a
// `rastroDeQuien`, como el tablero— y nada más: ni cambian el `actor`, ni autorizan, ni crecen sin
// límite, ni salen en un GET. Es el ÚNICO sitio: la línea de `rastroDeQuien` no las repite.
func TestLaEscrituraDejaElAutorYLaRevisionEnElRegistro(t *testing.T) {
	cab := map[string]string{"X-Autor": "p-yasmani", "X-Revision": "rev-0042"}

	// 1. Una ruta que SÍ llama a `rastroDeQuien` (/routes): la línea de quién lleva el actor del token
	// y la de la petición, las dos personas; el autor NO se repite en la de quién.
	d, stg, _ := datosDeReparto()
	var registro registroSeguro
	h, _ := montarRutasRegistrando(t, d, &registro)
	jwt := deSantiagoEnRutas(t)
	ruta := armarRutaDePrueba(t, h, jwt, stg[0])
	otra := armarRutaDePrueba(t, h, jwt, stg[1])

	registro.Reset()
	if w := llamarRutasConCabeceras(t, h, http.MethodDelete, "/api/routes/"+ruta.String(), jwt, cab); w.Code != http.StatusOK {
		t.Fatalf("no se borró (%d): %s", w.Code, w.Body.String())
	}
	pet := lineaCon(registro.String(), "peticion")
	for _, quiero := range []string{"metodo=DELETE", "autor=p-yasmani", "revision=rev-0042"} {
		if !strings.Contains(pet, quiero) {
			t.Errorf("/routes: a la línea de la petición le falta %q:\n%s", quiero, registro.String())
		}
	}
	quien := lineaCon(registro.String(), "ruta borrada")
	if !strings.Contains(quien, "actor=p-stg") || !strings.Contains(quien, "rol=LOGISTICO") || strings.Contains(quien, "autor=") {
		t.Errorf("/routes: la línea de quién tiene que llevar el actor del token y no repetir el autor:\n%s", quien)
	}
	sinElToken(t, registro.String(), jwt)

	// 2. LA CABECERA NO PUEDE CAMBIAR EL ACTOR NI EL ROL, ni diciendo el nombre de alguien con más poder.
	registro.Reset()
	llamarRutasConCabeceras(t, h, http.MethodDelete, "/api/routes/"+otra.String(), jwt,
		map[string]string{"X-Autor": "p-sa", "X-Revision": "SUPER ADMIN"})
	quien = lineaCon(registro.String(), "ruta borrada")
	if !strings.Contains(quien, "actor=p-stg") || strings.Contains(quien, "actor=p-sa") || !strings.Contains(quien, "rol=LOGISTICO") {
		t.Errorf("la cabecera cambió el actor o el rol:\n%s", quien)
	}

	// 3. Una ruta que NO llama a `rastroDeQuien` (/board/columns): antes no dejaba ni rastro (F2 de la
	// prueba de punta a punta, 09/10/2026).
	var regTab registroSeguro
	destinoDelRegistroDePruebas = &regTab
	defer func() { destinoDelRegistroDePruebas = io.Discard }()
	ht := montarTab(t, nuevoEspejo())
	jwtTab := tokenTab(t, sucStg.String())
	w := pedirTabConCabeceras(t, ht, http.MethodPost, "/api/board/columns", jwtTab, `{"nombre":"Zona de revisión"}`, cab)
	if w.Code != http.StatusCreated && w.Code != http.StatusOK {
		t.Fatalf("la columna no se creó (%d): %s", w.Code, w.Body.String())
	}
	pet = lineaCon(regTab.String(), "peticion")
	for _, quiero := range []string{"metodo=POST", "ruta=/api/board/columns", "autor=p-yasmani", "revision=rev-0042"} {
		if !strings.Contains(pet, quiero) {
			t.Errorf("/board/columns: a la línea de la petición le falta %q:\n%s", quiero, regTab.String())
		}
	}
	sinElToken(t, regTab.String(), jwtTab)

	// 3-bis. Y con el router ENTERO (`Rutas()`), que es el que de verdad lleva `RegistrarPeticiones`: quitarlo
	// de ahí dejaría las pruebas de arriba (que montan su propio router) en verde y el servidor sin la línea.
	regTab.Reset()
	hr := montarAvisos(t, &dobleAvisos{})
	jwtAv := avLogisticoStg(t)
	r := httptest.NewRequest(http.MethodPost, "/api/vehicles", strings.NewReader(`{"name":"Camión #9"}`))
	r.Header.Set("Authorization", "Bearer "+jwtAv)
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("X-Autor", "p-yasmani")
	r.Header.Set("X-Revision", "rev-0042")
	wr := httptest.NewRecorder()
	hr.ServeHTTP(wr, r)
	if wr.Code != http.StatusCreated && wr.Code != http.StatusOK {
		t.Fatalf("el camión no se creó (%d): %s", wr.Code, wr.Body.String())
	}
	pet = lineaCon(regTab.String(), "peticion")
	if !strings.Contains(pet, "autor=p-yasmani") || !strings.Contains(pet, "revision=rev-0042") {
		t.Errorf("Rutas(): la línea de la petición no lleva la autoría:\n%s", regTab.String())
	}
	if q := lineaCon(regTab.String(), "vehículo creado"); !strings.Contains(q, "actor=p-stg") || strings.Contains(q, "p-yasmani") {
		t.Errorf("Rutas(): la línea de quién tiene que llevar el actor del token y no el autor:\n%s", q)
	}
	sinElToken(t, regTab.String(), jwtAv)

	// 4. LA PAREJA: un GET con las mismas cabeceras no las anota, y una escritura sin ellas tampoco.
	regTab.Reset()
	pedirTabConCabeceras(t, ht, http.MethodGet, "/api/board", jwtTab, "", cab)
	if l := lineaCon(regTab.String(), "peticion"); l == "" || strings.Contains(l, "autor=") || strings.Contains(l, "revision=") {
		t.Errorf("un GET no debe anotar autor ni revision:\n%s", regTab.String())
	}
	regTab.Reset()
	pedirTabConCabeceras(t, ht, http.MethodPost, "/api/board/columns", jwtTab, `{"nombre":"Otra zona"}`, nil)
	if l := lineaCon(regTab.String(), "peticion"); l == "" || strings.Contains(l, "autor=") || strings.Contains(l, "revision=") {
		t.Errorf("sin cabeceras la línea no debe llevar autor ni revision (ni vacíos):\n%s", regTab.String())
	}
}

func pedirTabConCabeceras(t *testing.T, h http.Handler, metodo, ruta, jwt, cuerpo string, cab map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(metodo, ruta, strings.NewReader(cuerpo))
	r.Header.Set("Authorization", "Bearer "+jwt)
	if cuerpo != "" {
		r.Header.Set("Content-Type", "application/json")
	}
	for k, v := range cab {
		r.Header.Set(k, v)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func TestElRastroRecortaElAutorYLaRevision(t *testing.T) {
	d, stg, _ := datosDeReparto()
	var registro registroSeguro
	h, _ := montarRutasRegistrando(t, d, &registro)
	jwt := deSantiagoEnRutas(t)
	ruta := armarRutaDePrueba(t, h, jwt, stg[0])

	registro.Reset()
	// Con tildes y mucho más largo que un id: el corte es por caracteres, no parte una «ñ» a la mitad.
	llamarRutasConCabeceras(t, h, http.MethodDelete, "/api/routes/"+ruta.String(), jwt,
		map[string]string{"X-Autor": strings.Repeat("ñ", 5000), "X-Revision": strings.Repeat("r", 5000)})
	l := lineaCon(registro.String(), "peticion")
	if l == "" {
		t.Fatalf("no dejó la línea:\n%s", registro.String())
	}
	if len(l) > 700 {
		t.Errorf("la línea creció con las cabeceras (%d bytes): %.200s…", len(l), l)
	}
	if !strings.Contains(l, strings.Repeat("ñ", httpx.TopeDeLaAutoria)+"…") || strings.Contains(l, strings.Repeat("ñ", httpx.TopeDeLaAutoria+1)) {
		t.Errorf("el autor no se recortó a %d caracteres:\n%.300s", httpx.TopeDeLaAutoria, l)
	}
	if !strings.Contains(l, strings.Repeat("r", httpx.TopeDeLaAutoria)+"…") || strings.Contains(l, strings.Repeat("r", httpx.TopeDeLaAutoria+1)) {
		t.Errorf("la revisión no se recortó a %d caracteres:\n%.300s", httpx.TopeDeLaAutoria, l)
	}
}

// NO AUTORIZAN NADA: con las dos cabeceras puestas, quien no tiene permiso sigue sin tenerlo.
func TestElAutorYLaRevisionNoAutorizanNada(t *testing.T) {
	d, stg, _ := datosDeReparto()
	var registro registroSeguro
	h, _ := montarRutasRegistrando(t, d, &registro)
	jwt := deSantiagoEnRutas(t)
	ruta := armarRutaDePrueba(t, h, jwt, stg[0])
	cab := map[string]string{"X-Autor": "p-sa", "X-Revision": "rev-1"}

	registro.Reset()
	// Sin token: 401 aunque diga ser un SUPER ADMIN; y lo rechazado no deja la línea de «lo hizo».
	if w := llamarRutasConCabeceras(t, h, http.MethodDelete, "/api/routes/"+ruta.String(), "", cab); w.Code != http.StatusUnauthorized {
		t.Errorf("sin token tenía que ser 401 y fue %d", w.Code)
	}
	if l := lineaCon(registro.String(), "ruta borrada"); l != "" {
		t.Errorf("se escribió «ruta borrada» aunque se rechazó:\n%s", l)
	}
	if w := llamarRutas(t, h, http.MethodGet, "/api/routes", jwt, ""); w.Code != http.StatusOK {
		t.Fatalf("la ruta tenía que seguir ahí: %d", w.Code)
	}
}
