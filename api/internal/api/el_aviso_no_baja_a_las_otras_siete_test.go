package api

// LAS CUATRO PUERTAS QUE SE ARREGLARON EL 29/09/2026, CADA UNA CON SU PRUEBA.
//
// Jose había repetido tres cosas y son tres cosas distintas:
//
//  1. «no solo tablero» — todas las pantallas tienen que enterarse en vivo;
//  2. «tiene un evento para cada cosa para cada lugar… y también depende del usuario»;
//  3. «el aviso por sucursales, ese evento debe de salir de su sucursal, no puede dar una
//     bajada a las otras 7».
//
// Lo que faltaba, y lo que vigila cada prueba de este fichero:
//
//   - LA FUGA DE LA FLOTA. Un camión de Santiago mandaba a las OTRAS SIETE pantallas de
//     Vehículos a pedir `GET /api/vehicles` **y** `GET /api/settings` para pintar lo mismo.
//     El gancho era uno solo y era global porque lo compartía con los TIPOS de vehículo,
//     que sí son de las ocho. Ahora son dos ganchos. `TestUnCamionDeSantiago…` y su gemela
//     en positivo, `TestUnTipoDeVehiculoNuevo…`, que sin ella el arreglo pasaría igual con
//     el aviso roto del todo.
//   - LA TASA, QUE NO AVISABA A NADIE. El refresco de cada hora escribía
//     `branches.cup_rate` y no publicaba nada: era la única escritura de la api sin aviso.
//     Con la tasa se convierte TODO importe que se pinta.
//   - EL BORRADO Y EL CLIENTE QUE LLEGAN DE PEDIDO. Por el webhook sólo salía `canal`, que
//     es el aviso de la pantalla del desarrollador: se borraba un pedido de la base, o se
//     corregía la coordenada de un cliente, y ninguna pantalla del logístico se enteraba.
//   - LA RUTA ARMADA DESDE UNA ZONA, que nacía sin decírselo a la pantalla de Rutas.

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"procovar/reparto-api/internal/cotizar"
	"procovar/reparto-api/internal/store/sqlc"
)

// --------------------------------------------------------------------------- utilidad

// conElBusDePruebas cambia `busEventos` por uno limpio y abona UNA conexión por sucursal,
// devolviendo sus canales por código.
//
// UN BUS LIMPIO Y NO EL DEL PAQUETE: el freno de quince segundos es por tipo y sucursal, y
// otra prueba que haya publicado lo mismo hace un instante se comería este aviso. Eso
// saldría como «no avisó» y mandaría a quien lo lea a buscar un fallo que no existe.
func conElBusDePruebas(t *testing.T) map[string]<-chan Cambio {
	t.Helper()
	anterior := busEventos
	t.Cleanup(func() { busEventos = anterior })
	busEventos = NuevoDifusor()

	canales := map[string]<-chan Cambio{}
	for _, s := range lasOchoSucursales {
		ch, cortar, vivo := busEventos.SuscribirDe(s.id.String())
		if !vivo {
			t.Fatal("el bus nació cerrado")
		}
		t.Cleanup(cortar)
		canales[s.codigo] = ch
	}
	return canales
}

// aQuienesLlego devuelve los códigos de las sucursales a cuyo cable salió algo.
func aQuienesLlego(canales map[string]<-chan Cambio) []string {
	tocadas := []string{}
	for _, s := range lasOchoSucursales {
		if _, hay := recibio(canales[s.codigo]); hay {
			tocadas = append(tocadas, s.codigo)
		}
	}
	return tocadas
}

// --------------------------------------------------------------------------- la flota

// UN CAMIÓN DE SANTIAGO NO LE CUESTA UNA BAJADA A LAS OTRAS SIETE.
//
// Va por el manejador de verdad —`PATCH /api/vehicles/{id}` con el token de un OPERADOR de
// Santiago— y mira el CABLE, no el gancho: lo que hay que comprobar es que a Holguín no le
// llega, no que alguien llamó a una función.
//
// Y la pantalla de Vehículos es de las caras: no vive de la base local, así que cada aviso
// le cuesta `GET /api/vehicles` **y** `GET /api/settings`, por la conexión de allá.
func TestUnCamionDeSantiagoNoBajaLaFlotaDeLasOtrasSiete(t *testing.T) {
	// El doble de la flota resuelve Santiago con el uuid `avSucStg`, no con el de
	// `lasOchoSucursales`. Se abona un canal más con ESE uuid, que es el que va a llevar el
	// aviso, y los ocho de siempre hacen de «las otras».
	anterior := busEventos
	t.Cleanup(func() { busEventos = anterior })
	busEventos = NuevoDifusor()

	stg, cortarStg, _ := busEventos.SuscribirDe(avSucStg.String())
	t.Cleanup(cortarStg)
	otras := map[string]<-chan Cambio{}
	for _, s := range lasOchoSucursales {
		ch, cortar, _ := busEventos.SuscribirDe(s.id.String())
		t.Cleanup(cortar)
		otras[s.codigo] = ch
	}

	h := montarAvisos(t, &dobleAvisos{})
	w := pedirAv(t, h, http.MethodPatch, "/api/vehicles/"+avVehStg.String(),
		avOperadorStg(t), `{"name":"Camión renombrado"}`)
	avCodigo(t, w, http.StatusOK)

	c, hay := recibio(stg)
	if !hay {
		t.Fatal("editar el camión de Santiago no avisó ni a Santiago: la pantalla de " +
			"Vehículos no vive de la base local, así que sin este aviso no hay nada que " +
			"la repinte hasta que alguien salga y vuelva a entrar")
	}
	if c.Tipo != CambioVehiculos {
		t.Errorf("salió el tipo %q y le toca %q", c.Tipo, CambioVehiculos)
	}
	if c.Sucursal != avSucStg.String() {
		t.Errorf("el aviso salió con la sucursal %q y tenía que salir con la de Santiago "+
			"(%s), que es la del camión que se tocó", c.Sucursal, avSucStg)
	}

	if tocadas := aQuienesLlego(otras); len(tocadas) > 0 {
		t.Errorf("editar UN camión de Santiago le llegó también a %v.\n"+
			"  Son %d sucursales que se bajan `GET /api/vehicles` y `GET /api/settings` "+
			"para pintar exactamente lo mismo, por la conexión de allá y con ocho "+
			"navegadores en la oficina más los teléfonos.\n"+
			"  `vehicles` tiene `branch_id` y los tres manejadores pasan por `acotado()`: "+
			"el aviso va por `avisarCambioDeVehiculos`, que está acotado. El que NO se "+
			"acota es el de los TIPOS (`avisarCambioDeTiposDeVehiculo`), que son de toda "+
			"la empresa.", tocadas, len(tocadas))
	}
}

// LA GEMELA EN POSITIVO, Y SIN ELLA LA DE ARRIBA PASA CON EL AVISO ROTO DEL TODO.
//
// `vehicle_types` NO tiene columna de sucursal: es el catálogo de toda la empresa, y sale
// en el desplegable del alta de un camión de las ocho. Acotarlo dejaría a siete pantallas
// de Vehículos sin enterarse de un tipo nuevo — y como esa pantalla no vive de la base
// local, el ciclo tampoco la repinta: se queda clavada hasta salir y volver a entrar.
func TestUnTipoDeVehiculoNuevoSiLlegaALasOcho(t *testing.T) {
	// LO CREA UN `ADMINISTRADOR` DE SANTIAGO, y esto no es un adorno de la prueba.
	//
	// `ExigirAdmin` deja pasar a `ADMINISTRADOR`, que **es de UNA sucursal**
	// (`../../CLAUDE.md` §5). Con un SUPER ADMIN esta prueba pasaría con el gancho acotado,
	// porque el alcance de un SUPER ADMIN ya es «todas» y el aviso saldría global de todos
	// modos: verde por la razón equivocada. Comprobado mutando el 29/09/2026.
	anterior := busEventos
	t.Cleanup(func() { busEventos = anterior })
	busEventos = NuevoDifusor()

	suya, cortarSuya, _ := busEventos.SuscribirDe(avSucStg.String())
	t.Cleanup(cortarSuya)
	otra, cortarOtra, _ := busEventos.SuscribirDe(avSucHol.String())
	t.Cleanup(cortarOtra)

	h := montarAvisos(t, &dobleAvisos{})
	w := pedirAv(t, h, http.MethodPost, "/api/vehicle-types", avAdminDeStg(t), `{"nombre":"rastra"}`)
	avCodigo(t, w, http.StatusCreated)

	if _, hay := recibio(suya); !hay {
		t.Fatal("el tipo nuevo no llegó ni a la sucursal de quien lo creó")
	}
	if _, hay := recibio(otra); !hay {
		t.Error("un tipo de vehículo creado desde Santiago NO llegó a Holguín.\n" +
			"  `vehicle_types` no tiene columna de sucursal ninguna: es el catálogo de toda " +
			"la empresa y ese tipo sale en el desplegable de las ocho.\n" +
			"  Que no llegue NO falla, no da error y no sale en ningún registro: la " +
			"pantalla de Vehículos no vive de la base local, así que el ciclo tampoco la " +
			"repinta y se queda clavada hasta salir y volver a entrar.")
	}
}

// avAdminDeStg: un `ADMINISTRADOR` con su sucursal. Pasa `ExigirAdmin` —administra LO
// SUYO— y su alcance es UNA sucursal, que es lo que hace visible la diferencia entre un
// gancho acotado y uno global.
func avAdminDeStg(t *testing.T) string {
	t.Helper()
	return tokenDeDatos(t, map[string]any{"sub": "p-admin-stg", "email": "admin@procovar.cu",
		"role": "ADMINISTRADOR", "branchId": avSucStg.String()})
}

// --------------------------------------------------------------------------- la tasa

// laBaseDeUnaTasaConID: como `lasOchoDePrueba` pero CON el uuid de cada sucursal puesto.
//
// El uuid es lo que hace falta aquí y en ningún otro sitio de las pruebas de tasas: el
// aviso se acota por `branches.id`, no por el código. Sin él, el aviso saldría con la
// sucursal vacía —o sea, a las ocho— y esta prueba pasaría por la razón equivocada.
func laBaseDeUnaTasaConID(t *testing.T) *baseDeTasas {
	t.Helper()
	return &baseDeTasas{sucursales: []sqlc.CodigosParaRefrescarLaTasaRow{
		{ID: idDeSucursal(t, "GR"), Name: "Granma", ExternalID: codDePrueba("GR")},
		{ID: idDeSucursal(t, "HAB"), Name: "La Habana", ExternalID: codDePrueba("HAB")},
	}}
}

// LA TASA QUE CAMBIA SE DICE, Y SÓLO A SU SUCURSAL.
//
// Era la ÚNICA escritura de esta api que no publicaba nada. La cabecera de
// `refresco_de_tasas.go` lo tenía escrito desde el principio —PEDIDO puede permitirse
// refrescar cada 12 h «porque cuando la tasa cambia, `emitEvent('tasa')` va por Redis al
// SSE»— con la coletilla «aquí no hay ese canal». Lo hay desde el 17/09/2026.
//
// Y con el reloj fuera (plan §5, «el reloj no lo quiero») esto dejaría de llegar del todo:
// la tasa se quedaría vieja y con ella se convierte TODO importe que se pinta. No se ve
// rota — se ve como un número creíble y equivocado.
func TestLaTasaQueCambiaAvisaASuSucursalYSoloAEsa(t *testing.T) {
	canales := conElBusDePruebas(t)

	base := laBaseDeUnaTasaConID(t)
	accesos := &accesosDeTasasFalso{tasas: map[string]*cotizar.Tasa{
		"GR": tasaDePrueba(700, "2026-09-29T09:00:00Z", true),
	}}
	n := NuevoRefrescoDeTasas(base, accesos, mudoDeTasas(), time.Hour).UnaVuelta(context.Background())
	if n != 1 {
		t.Fatalf("la vuelta cambió %d tasas y tenía que cambiar 1: esta prueba pasaría "+
			"por la razón equivocada", n)
	}

	tocadas := aQuienesLlego(canales)
	switch {
	case len(tocadas) == 0:
		t.Fatal("la tasa de Granma cambió y NO se avisó a nadie.\n" +
			"  Con la tasa se convierte todo importe que se pinta, así que una tasa vieja " +
			"no se ve rota: se ve como un número creíble y equivocado, que es lo peor que " +
			"le puede pasar a algo que alguien va a cobrar.")
	case len(tocadas) != 1 || tocadas[0] != "GR":
		t.Errorf("la tasa de Granma se avisó a %v.\n"+
			"  La tasa es POR SUCURSAL: la de Granma no le cambia ni un importe a "+
			"Camagüey, así que no tiene por qué costarle una vuelta.", tocadas)
	}
}

// Y LA OTRA MITAD, sin la cual el aviso sale ocho veces por hora las veinticuatro horas.
//
// `GuardarTasaDeSucursal` lleva un `IS DISTINCT FROM` en el `WHERE` justamente para no
// escribir cuando la tasa es la misma, y lo normal —todas las vueltas del día menos una— es
// que no cambie nada. Un aviso que sale siempre deja de leerse, y entonces tampoco se lee
// el día que importa (`CLAUDE.md` §3-quinquies).
func TestLaTasaQueNoCambiaNoAvisaANadie(t *testing.T) {
	canales := conElBusDePruebas(t)

	base := laBaseDeUnaTasaConID(t)
	base.sinFilasTocadas = true // el `IS DISTINCT FROM` no escribió: la tasa es la misma
	accesos := &accesosDeTasasFalso{tasas: map[string]*cotizar.Tasa{
		"GR": tasaDePrueba(700, "2026-09-29T09:00:00Z", true),
	}}
	if n := NuevoRefrescoDeTasas(base, accesos, mudoDeTasas(), time.Hour).
		UnaVuelta(context.Background()); n != 0 {
		t.Fatalf("la vuelta dijo que cambiaron %d tasas y no cambió ninguna", n)
	}

	if tocadas := aQuienesLlego(canales); len(tocadas) > 0 {
		t.Errorf("se avisó a %v de una tasa que NO cambió.\n"+
			"  Esto corre cada hora sobre ocho sucursales: serían ciento noventa y dos "+
			"avisos al día para decir que no ha pasado nada, y un aviso que sale siempre "+
			"deja de leerse.", tocadas)
	}
}

// --------------------------------------------------------------------------- el webhook

// LO QUE PEDIDO BORRA SE DICE, Y A LAS DOS PANTALLAS QUE CAMBIAN.
//
// Por esta puerta sólo salía `canal`, que es el aviso de la pantalla del desarrollador: el
// pedido desaparecía de `orders` y ninguna pantalla del logístico se enteraba.
//
// Y son DOS: `board_placements.order_id` cuelga de `orders` con `ON DELETE CASCADE`
// (`00002_tablero.sql`), así que si ese pedido estaba colocado en una zona, la tarjeta se va
// con él. Quien esté armando el tablero tiene que verla irse, no seguir arrastrando algo que
// ya no existe.
func TestLoQuePEDIDOBorraAvisaAPedidosYAlTablero(t *testing.T) {
	for _, motivo := range []string{"borrado", "ya_no_va"} {
		t.Run(motivo, func(t *testing.T) {
			h, q, _ := montarLaPuerta(t, nil)
			avisos := contarAvisos(t)

			cuerpo := `{"aviso":{"avisoId":"1-0","motivo":"` + motivo + `","id":"PED-9"}}`
			w := tocarLaPuerta(t, h, claveDePruebas,
				firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)
			if w.Code != http.StatusOK {
				t.Fatalf("%s no entró: %d %s", motivo, w.Code, w.Body.String())
			}
			if q.quitados != 1 {
				t.Fatalf("no se borró nada: la prueba pasaría por la razón equivocada "+
					"(quitados=%d)", q.quitados)
			}

			if avisos.tiene(CambioPedidos) == 0 {
				t.Errorf("se borró un pedido y NO se avisó de «%s».\n"+
					"  La lista de Pedidos y su detalle siguen enseñando un pedido que ya "+
					"no está en la base, y nadie sabe por qué.", CambioPedidos)
			}
			if avisos.tiene(CambioTablero) == 0 {
				t.Errorf("se borró un pedido y NO se avisó de «%s».\n"+
					"  `board_placements.order_id` cuelga de `orders` con ON DELETE "+
					"CASCADE: si ese pedido estaba colocado, su tarjeta se fue con él. "+
					"Quien esté armando el tablero la sigue arrastrando.", CambioTablero)
			}
			if avisos.tiene(CambioCanal) == 0 {
				t.Errorf("se perdió el aviso del canal, que ya estaba: la pantalla que " +
					"contesta «¿está entrando algo?» deja de ver este aviso aparecer")
			}
		})
	}
}

// EL CLIENTE QUE SE MOVIÓ DE SITIO SE DICE, y `CambioClientes` deja de ser una constante
// declarada que no publica nadie.
//
// `eventos.go` decía —en negrita y para que nadie lo tocara— que eso «no es un olvido»
// porque «en esta API NO HAY ninguna puerta que escriba `customers`». La hay, y es ésta. Un
// comentario no falla, y ése llevaba desde el 17/09/2026 tapando el hueco que decía
// explicar.
//
// Y es de los peores que se pueden perder: **el reparto ordena las paradas por la
// coordenada del cliente**. Sin enterarse, la ruta se arma hacia el sitio de antes, con
// números y todo y sin un solo error.
func TestElClienteQueSeMovioAvisaDeClientes(t *testing.T) {
	h, q, _ := montarLaPuerta(t, nil)
	avisos := contarAvisos(t)

	cuerpo := `{"aviso":{"avisoId":"1-0","entidad":"cliente","motivo":"cliente","id":"CLI-1"},
	            "cliente":{"id":"CLI-1","codigo":"C1","nombre":"Uno","latitud":20.1,"longitud":-77.2}}`
	w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)
	if w.Code != http.StatusOK {
		t.Fatalf("el cliente movido no entró: %d %s", w.Code, w.Body.String())
	}
	if q.clientes != 1 {
		t.Fatalf("no se guardó el cliente: la prueba pasaría por la razón equivocada "+
			"(clientes=%d)", q.clientes)
	}

	if avisos.tiene(CambioClientes) == 0 {
		t.Errorf("se guardó un cliente movido de sitio y NO se avisó de «%s».\n"+
			"  El reparto ordena las paradas por esa coordenada: sin este aviso la ruta "+
			"se arma hacia el sitio de antes, con números y todo y sin un solo error.\n"+
			"  Salieron: %v", CambioClientes, avisos.tipos)
	}
}

// Y UN CLIENTE SIN COORDENADAS NO AVISA: no se escribió nada.
func TestUnClienteSinCoordenadasNoAvisaDeClientes(t *testing.T) {
	h, q, _ := montarLaPuerta(t, nil)
	avisos := contarAvisos(t)

	cuerpo := `{"aviso":{"avisoId":"1-0","entidad":"cliente","motivo":"cliente","id":"CLI-2"},
	            "cliente":{"id":"CLI-2","codigo":"C2","nombre":"Dos"}}`
	w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)
	if w.Code != http.StatusOK {
		t.Fatalf("un cliente sin coordenadas no es un fallo: %d %s", w.Code, w.Body.String())
	}
	if q.clientes != 0 {
		t.Fatalf("escribió un cliente sin coordenadas (clientes=%d)", q.clientes)
	}

	if avisos.tiene(CambioClientes) > 0 {
		t.Errorf("avisó de «%s» sin haber escrito nada: todas las pantallas abiertas "+
			"vuelven a pedir su lista para encontrarla igual", CambioClientes)
	}
}

// --------------------------------------------------------------------------- la ruta

// ARMAR LA RUTA DE UNA ZONA AVISA TAMBIÉN DE RUTAS, que es donde nace la ruta.
//
// El comentario de `armarRutaDeColumna` decía «avisa del TABLERO además de las rutas, que ya
// lo hace el armador», y era falso: el armador que avisa es el de `rutas.go`
// (`POST /api/routes`), y éste es otro, escrito entero en `tablero.go`. Por aquí nacía una
// ruta con su código y sus paradas y la pantalla de Rutas no se enteraba.
//
// Hoy se tapaba solo porque el vigía del aparato dispara un ciclo con CUALQUIER aviso. Eso
// deja de ser verdad en cuanto el aviso se afine —«por tablero no puede actualizarse cada
// vez que se haga algo en rutas»— y entonces esa pantalla se queda vieja sin que nadie sepa
// por qué.
func TestArmarLaRutaDeUnaZonaAvisaTambienDeRutas(t *testing.T) {
	q := nuevoTablero()
	q.colocadas[ped1] = colocacion{colCentro, 1}
	q.colocadas[ped2] = colocacion{colCentro, 2}
	q.capacidad = 1000
	h := montarTab(t, q)
	avisos := contarAvisos(t)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("la ruta no se armó: %d %s", w.Code, w.Body.String())
	}

	if avisos.tiene(CambioTablero) == 0 {
		t.Errorf("armar la ruta vació la zona y NO avisó del tablero: quien lo esté " +
			"mirando desde el navegador sigue arrastrando tarjetas que ya salieron")
	}
	if avisos.tiene(CambioRutas) == 0 {
		t.Errorf("nació una ruta con su código y sus paradas y NO se avisó de «%s».\n"+
			"  La pantalla de Rutas no se entera de que existe.\n"+
			"  Salieron: %v", CambioRutas, avisos.tipos)
	}
}

// --------------------------------------------------------------------------- el canal

// LA PUERTA DEL LOTE AVISA AL CANAL — y es la puerta por la que entra el grueso de todo.
//
// La pantalla del canal existe para contestar UNA pregunta: «¿está entrando algo?». Hasta
// hoy esa pregunta sólo se contestaba con lo que entraba de uno en uno por el webhook: el
// LOTE del espejo —tandas de doscientos, el grueso de lo que entra de verdad— escribía su
// fila en `recepciones_del_webhook` y no la veía nadie hasta que alguien recargara. O sea,
// medio sondeo con el dedo de una persona haciendo de temporizador, que es justo lo que
// Jose pidió quitar: «SSE con todo esto igual, nada de polling».
//
// Y LA OTRA MITAD EN EL MISMO CASO: con la cabecera `YaApuntada` NO se apunta fila, así que
// tampoco se avisa. Sin esa mitad, un aviso del webhook —que ya avisa por su cuenta— haría
// que la pantalla se repintara dos veces por un solo suceso.
func TestLaPuertaDelLoteAvisaAlCanalSoloCuandoDejaFila(t *testing.T) {
	casos := []struct {
		nombre   string
		cabecera string
		quiere   int
	}{
		{"un lote de verdad: deja fila y se dice", "", 1},
		{"una tanda que ya tiene su fila: ni fila ni aviso", YaApuntada, 0},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			q := &dobleDeConstancia{}
			h := montarCotizacion(t, q)
			avisos := contarAvisos(t)

			r := httptest.NewRequest(http.MethodPost, "/api/quote/batch",
				strings.NewReader(`{"orders":[]}`))
			r.Header.Set("Content-Type", "application/json")
			r.Header.Set("X-Api-Key", claveDeServicioDePrueba)
			if c.cabecera != "" {
				r.Header.Set(CabeceraDeConstancia, c.cabecera)
			}
			w := httptest.NewRecorder()
			h.ServeHTTP(w, r)
			if w.Code != http.StatusOK {
				t.Fatalf("la puerta contestó %d: %s", w.Code, w.Body.String())
			}
			if q.filas != c.quiere {
				t.Fatalf("quedaron %d filas y tenían que quedar %d: la prueba estaría "+
					"midiendo otra cosa", q.filas, c.quiere)
			}

			if n := avisos.tiene(CambioCanal); n != c.quiere {
				t.Errorf("salieron %d avisos de «%s» y tenían que salir %d.\n"+
					"  La fila y el aviso van juntos: si se escribe la fila, la pantalla "+
					"del canal tiene que ver el lote APARECER —es la única pregunta que "+
					"esa pantalla contesta—; y si no se escribe, avisar la repinta dos "+
					"veces por un solo suceso.\n"+
					"  Salieron: %v", n, CambioCanal, c.quiere, avisos.tipos)
			}
		})
	}
}

// EL CIERRE QUE LLENA EL BUZÓN TAMBIÉN AVISA AL CANAL.
//
// `drenaje_del_buzon.go` avisa cuando la tanda SALE, y nadie avisaba cuando ENTRA. Con
// PEDIDO caído eso es justamente lo que hay que ver: la cola llenándose. Aquí PEDIDO está
// caído a propósito, que es el caso que importa.
func TestElCierreQueLlenaElBuzonAvisaAlCanal(t *testing.T) {
	pedido := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "estoy caído", http.StatusServiceUnavailable)
	}))
	defer pedido.Close()

	d, stg, _ := datosDeReparto()
	var registro registroSeguro
	h, s := montarRutasRegistrando(t, d, &registro)
	s.aPedido = canalDePrueba(pedido.URL, "la-clave", slog.New(slog.DiscardHandler))

	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1])

	// El contador se pone DESPUÉS de armar la ruta: armarla avisa de rutas y del tablero, y
	// lo que se mide aquí es lo que publica el CIERRE.
	avisos := contarAvisos(t)

	cuerpo := fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, stg[1])
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)
	if w.Code != http.StatusOK {
		t.Fatalf("PEDIDO caído no puede tumbar el cierre: %d %s", w.Code, w.Body.String())
	}
	if len(d.avisosEncolados) != 1 {
		t.Fatalf("no quedó nada en el buzón: la prueba pasaría por la razón equivocada "+
			"(encolados=%d)", len(d.avisosEncolados))
	}

	if avisos.tiene(CambioRutas) == 0 {
		t.Errorf("el cierre no avisó de «%s», que es el aviso que ya tenía", CambioRutas)
	}
	if avisos.tiene(CambioCanal) == 0 {
		t.Errorf("el cierre metió una fila en el buzón de salida y NO avisó de «%s».\n"+
			"  Esa pantalla contesta «¿está saliendo algo?», y con PEDIDO caído lo que hay "+
			"que ver es la cola llenándose. El drenaje avisa cuando la tanda SALE; cuando "+
			"ENTRA no avisaba nadie.\n"+
			"  Salieron: %v", CambioCanal, avisos.tipos)
	}
}

// Y UN CIERRE QUE NO ENCOLA NADA NO TOCA EL CANAL: el buzón no se movió.
//
// Es la mitad en negativo, y sin ella la de arriba pasaría con un aviso incondicional — que
// es un aviso que sale siempre, y un aviso que sale siempre deja de leerse.
func TestUnCierreQueNoEncolaNadaNoAvisaAlCanal(t *testing.T) {
	d, stg, _ := datosDeReparto()
	var registro registroSeguro
	h, _ := montarRutasRegistrando(t, d, &registro)

	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1])

	// DESMARCAR una parada es el caso: se escribe de verdad —se le quita el resultado— y
	// **no sale aviso a PEDIDO**, porque en su contrato no existe «des-entregado». O sea,
	// un cierre que aplica algo y no toca el buzón, que es justo lo que hay que distinguir.
	avisos := contarAvisos(t)

	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt,
		fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":null}]}`, stg[1]))
	if w.Code != http.StatusOK {
		t.Fatalf("el desmarcado contestó %d: %s", w.Code, w.Body.String())
	}
	if len(d.avisosEncolados) != 0 {
		t.Fatalf("se encoló algo al desmarcar: la prueba mediría otra cosa (%d)",
			len(d.avisosEncolados))
	}

	if n := avisos.tiene(CambioCanal); n != 0 {
		t.Errorf("salieron %d avisos de «%s» sin que el buzón se moviera: un aviso que "+
			"sale siempre deja de leerse, y entonces tampoco se lee el día que importa",
			n, CambioCanal)
	}
}
