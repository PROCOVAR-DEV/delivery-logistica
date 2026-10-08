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
	"bytes"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"
)

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
	var registro bytes.Buffer
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
		for _, quiero := range append([]string{"level=INFO", "actor=p-stg", "rol=OPERADOR"}, c.ids...) {
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
	var registro bytes.Buffer
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
	var registro bytes.Buffer
	destinoDelRegistroDePruebas = &registro
	defer func() { destinoDelRegistroDePruebas = io.Discard }()
	h := montarAvisos(t, &dobleAvisos{})
	jwt := avOperadorStg(t)

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
	var registro bytes.Buffer
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
