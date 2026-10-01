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
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/alcance"
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

// elAvisoDe vacía el canal y devuelve el aviso de ESE tipo, si salió.
//
// No vale mirar el primero que llegue: hay puertas que publican dos avisos distintos a la vez
// —el armador de una zona cambia el tablero Y crea una ruta— y el orden es cosa del manejador.
func elAvisoDe(canal <-chan Cambio, tipo string) (Cambio, bool) {
	for {
		c, hay := recibio(canal)
		if !hay {
			return Cambio{}, false
		}
		if c.Tipo == tipo {
			return c, true
		}
	}
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

// ===========================================================================
// EL AVISO SALE DE LA FILA, NO DEL ALCANCE DE QUIEN LLAMÓ  — 01/10/2026
// ===========================================================================
//
// LO QUE SE MIDIÓ EN PRODUCCIÓN ESE DÍA. Se creó una zona en el Tablero de Santiago desde el
// teléfono y por el canal salió, literal:
//
//	{"cuando":"2026-10-01T13:07:54.849Z","tipo":"tablero"}
//
// **Sin `sucursal`**, o sea «de todas»: las ocho se bajaron el tablero entero por un gesto de
// una. Y la columna se había escrito CON su `branch_id` puesto (`CrearColumnaParams{…
// BranchID: t.sucursal}`), así que el dato estaba ahí y el aviso no lo usaba.
//
// Eran dos piezas que se sumaban, y por eso lo de abajo se prueba con el PEOR de los dos
// casos a la vez:
//
//  1. el aviso sacaba la sucursal del ALCANCE, y el alcance de quien ve las ocho
//     (DESARROLLADOR, SUPER ADMIN) es «todas» -> vacío;
//  2. todo lo que hace el teléfono sube por la COLA, y el sincronizador no reenvía
//     `X-Sucursal-Id` (`sync/internal/reparto/reparto.go`, `cabeceras`) -> la petición llega
//     sin decir qué sucursal se miraba, sea quien sea el que pulsó.
//
// Así que estas pruebas entran con un **SUPER ADMIN sin sucursal y SIN la cabecera** —
// `tokenTab(t, "")` y `pedirTab`, que no la pone— que es exactamente la petición que llega del
// teléfono. Con el aviso saliendo del alcance, las siete fallan.

// losSieteGestosDelTablero: las siete escrituras del tablero, cada una dejando el doble en el
// estado que necesita. Son las MISMAS siete que vigila
// `TestNingunaEscrituraDelTableroSeQuedaSinAvisar` en el otro fichero.
//
// Todas trabajan sobre zonas de SANTIAGO (`sucStg`), así que el aviso de las siete tiene que
// salir con ese uuid y con ningún otro.
func losSieteGestosDelTablero() []struct {
	nombre   string
	preparar func(q *tableroFalso)
	pedir    func(t *testing.T, h http.Handler, jwt string) *httptest.ResponseRecorder
	codigo   int
	// tambienRutas: el armador de una zona avisa de DOS pantallas porque cambian las dos.
	tambienRutas bool
} {
	return []struct {
		nombre   string
		preparar func(q *tableroFalso)
		pedir    func(t *testing.T, h http.Handler, jwt string) *httptest.ResponseRecorder
		codigo   int

		tambienRutas bool
	}{
		{
			nombre:   "crear una zona",
			preparar: func(*tableroFalso) {},
			pedir: func(t *testing.T, h http.Handler, jwt string) *httptest.ResponseRecorder {
				// CON `?branchId=`, que es como lo manda el aparato: la cola encola
				// `/board/columns?branchId=<sucursal>` (`app/lib/pantallas/tablero/datos/
				// repositorio.dart`). Es el único dato que dice de qué tablero se habla
				// cuando no viene la cabecera.
				return pedirTab(t, h, http.MethodPost,
					"/api/board/columns?branchId="+sucStg.String(), jwt, `{"nombre":"Reparto Norte"}`)
			},
			codigo: http.StatusCreated,
		},
		{
			nombre:   "renombrarla",
			preparar: func(*tableroFalso) {},
			pedir: func(t *testing.T, h http.Handler, jwt string) *httptest.ResponseRecorder {
				return pedirTab(t, h, http.MethodPatch, "/api/board/columns/"+colCentro.String(),
					jwt, `{"nombre":"Centro Norte"}`)
			},
			codigo: http.StatusOK,
		},
		{
			nombre:   "reordenar el tablero",
			preparar: func(*tableroFalso) {},
			pedir: func(t *testing.T, h http.Handler, jwt string) *httptest.ResponseRecorder {
				return pedirTab(t, h, http.MethodPut,
					"/api/board/columns/orden?branchId="+sucStg.String(), jwt,
					`{"ids":["`+colVista.String()+`","`+colCentro.String()+`"]}`)
			},
			codigo: http.StatusOK,
		},
		{
			nombre:   "borrar una zona vacía",
			preparar: func(*tableroFalso) {},
			pedir: func(t *testing.T, h http.Handler, jwt string) *httptest.ResponseRecorder {
				return pedirTab(t, h, http.MethodDelete, "/api/board/columns/"+colVacia.String(), jwt, "")
			},
			codigo: http.StatusOK,
		},
		{
			nombre:   "colocar una tarjeta",
			preparar: func(*tableroFalso) {},
			pedir: func(t *testing.T, h http.Handler, jwt string) *httptest.ResponseRecorder {
				return pedirTab(t, h, http.MethodPut, "/api/board/placements/"+ped1.String(),
					jwt, `{"columnaId":"`+colCentro.String()+`"}`)
			},
			codigo: http.StatusOK,
		},
		{
			nombre: "quitarla",
			// TIENE QUE HABER TARJETA PUESTA. Quitar lo que no está es reaplicable y no
			// escribe nada, así que ahí no hay fila de la que leer la sucursal — y entonces
			// esta prueba mediría el caso vacío creyendo medir el bueno.
			preparar: func(q *tableroFalso) { q.colocadas[ped1] = colocacion{colCentro, 1} },
			pedir: func(t *testing.T, h http.Handler, jwt string) *httptest.ResponseRecorder {
				return pedirTab(t, h, http.MethodDelete, "/api/board/placements/"+ped1.String(), jwt, "")
			},
			codigo: http.StatusOK,
		},
		{
			nombre: "armar la ruta de la zona",
			preparar: func(q *tableroFalso) {
				q.colocadas[ped1] = colocacion{colCentro, 1}
				q.colocadas[ped2] = colocacion{colCentro, 2}
				q.capacidad = 1000
			},
			pedir: func(t *testing.T, h http.Handler, jwt string) *httptest.ResponseRecorder {
				return pedirTab(t, h, http.MethodPost,
					"/api/board/columns/"+colCentro.String()+"/route", jwt, `{}`)
			},
			codigo:       http.StatusCreated,
			tambienRutas: true,
		},
	}
}

// UN GESTO DEL TELÉFONO SALE CON SU SUCURSAL AUNQUE NO VENGA LA CABECERA Y LO HAGA UN SUPER
// ADMIN. Es la prueba del fallo medido: con el aviso saliendo del alcance, las siete fallan.
func TestElGestoDelTableroSaleDeSuSucursalSinCabeceraYDeUnSuperAdmin(t *testing.T) {
	// EL UUID A MANO. `sucStg` es la constante que usa el doble; compararse con ella no
	// comprobaría nada, así que el valor esperado se escribe aquí.
	const santiagoAMano = "11111111-1111-1111-1111-111111111111"
	if sucStg.String() != santiagoAMano {
		t.Fatalf("el doble del tablero ya no usa %s para Santiago, sino %s: esta prueba "+
			"compara contra el valor escrito a mano y hay que cambiarlo aquí",
			santiagoAMano, sucStg)
	}

	for _, c := range losSieteGestosDelTablero() {
		t.Run(c.nombre, func(t *testing.T) {
			q := nuevoTablero()
			c.preparar(q)
			h := montarTab(t, q)

			// UN BUS LIMPIO con un canal para Santiago y otro para Holguín. Son los dos
			// lados de la misma pregunta: a Santiago TIENE que llegarle y a Holguín NO.
			anterior := busEventos
			t.Cleanup(func() { busEventos = anterior })
			busEventos = NuevoDifusor()
			stg, cortarStg, _ := busEventos.SuscribirDe(santiagoAMano)
			t.Cleanup(cortarStg)
			hol, cortarHol, _ := busEventos.SuscribirDe(sucHol.String())
			t.Cleanup(cortarHol)

			// SUPER ADMIN SIN SUCURSAL, y `pedirTab` no manda `X-Sucursal-Id`: la petición
			// que llega de la cola del teléfono, tal cual.
			w := c.pedir(t, h, tokenTab(t, ""))
			if w.Code != c.codigo {
				t.Fatalf("código %d, se esperaba %d: %s", w.Code, c.codigo, w.Body.String())
			}

			// SE VACÍA EL CANAL Y SE BUSCA EL DE `tablero`, no se mira el primero: el
			// armador de una zona publica DOS avisos —`rutas` y `tablero`— y el de rutas sale
			// antes. Quedarse con el primero haría que esta prueba midiera otro aviso en ese
			// caso y sólo en ése.
			cambio, hay := elAvisoDe(stg, CambioTablero)
			if !hay {
				t.Fatalf("%s no avisó del tablero ni a Santiago, que es de quien es la zona",
					c.nombre)
			}
			if cambio.Sucursal != santiagoAMano {
				t.Errorf("%s publicó el aviso con la sucursal %q y tenía que ser %s "+
					"(Santiago, la de la fila que se escribió).\n"+
					"  Vacío = «de todas»: es el fallo medido en producción el 01/10/2026 a "+
					"las 13:07:54 UTC, cuando las OCHO sucursales se bajaron el tablero "+
					"entero por una zona creada en Santiago.\n"+
					"  Esta petición entra como la del teléfono: SUPER ADMIN (alcance = las "+
					"ocho) y SIN `X-Sucursal-Id`, porque el sincronizador no la reenvía. Si "+
					"la sucursal se saca del alcance, aquí sale vacía. Tiene que salir de la "+
					"FILA.", c.nombre, cambio.Sucursal, santiagoAMano)
			}

			if _, llego := recibio(hol); llego {
				t.Errorf("%s en Santiago le llegó también a Holguín.\n"+
					"  Eso son SIETE sucursales bajándose un tablero que no ha cambiado, "+
					"por la conexión de allá y con ocho navegadores en la oficina más los "+
					"teléfonos.", c.nombre)
			}
		})
	}
}

// Y EL AVISO DE RUTAS DEL ARMADOR TAMBIÉN SALE ACOTADO. Es el otro aviso de la misma puerta
// —nace una ruta de verdad, con su código y sus paradas— y se le olvidaba igual.
func TestLaRutaQueNaceDeUnaZonaAvisaSoloASuSucursal(t *testing.T) {
	const santiagoAMano = "11111111-1111-1111-1111-111111111111"

	q := nuevoTablero()
	q.colocadas[ped1] = colocacion{colCentro, 1}
	q.colocadas[ped2] = colocacion{colCentro, 2}
	q.capacidad = 1000
	h := montarTab(t, q)

	avisos := contarAvisos(t)
	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, ""), `{}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("la ruta no se armó: %d %s", w.Code, w.Body.String())
	}

	for _, tipo := range []string{CambioRutas, CambioTablero} {
		suc, hubo := avisos.sucursalDe(tipo)
		if !hubo {
			t.Errorf("armar la zona no avisó de «%s». Salieron: %v", tipo, avisos.tipos)
			continue
		}
		if suc != santiagoAMano {
			t.Errorf("el aviso de «%s» salió con la sucursal %q y tenía que ser %s, la de "+
				"la columna de la que nació la ruta.\n"+
				"  La ruta se crea con `BranchID: pgDe(columna.BranchID)`, así que el dato "+
				"está en la mano: sacarlo del alcance de quien llamó lo tira.",
				tipo, suc, santiagoAMano)
		}
	}
}

// ===========================================================================
// UN GESTO ES UN AVISO. ¿Y los CUATRO que se midieron?
// ===========================================================================
//
// El 01/10/2026 a las 12:59:39 llegaron CUATRO `cambio` de tipo `tablero` en 32 ms (`.465`,
// `.477`, `.489`, `.497`) por un solo gesto de una persona armando una ruta desde una zona.
// La pregunta era si sobraban tres.
//
// NO SOBRAN, Y ESTA PRUEBA ES LA MITAD QUE LE TOCA AL SERVIDOR: cada puerta del tablero
// publica **un** aviso de `tablero` por petición, ni dos ni cuatro. Los cuatro de aquella
// mañana son cuatro PETICIONES, no una que avisa cuatro veces — el aparato encola **un
// apunte por tarjeta** a propósito (`vaciarColumna` y `moverTodo` en
// `app/lib/pantallas/tablero/datos/repositorio.dart`: «Un apunte por tarjeta y no uno de
// “vaciar”: el contrato no tiene esa orden, y quitar tarjeta a tarjeta es además
// reaplicable»), y el sincronizador los sube de uno en uno (`Aplicar`, una llamada HTTP por
// apunte). Tres tarjetas y el armado son cuatro escrituras legítimas en 32 ms.
//
// Lo que esta prueba impide es el OTRO caso, el que sí sería de más: que un manejador
// empiece a publicar dos avisos del mismo tipo por una sola escritura.
func TestUnaPeticionDelTableroPublicaUnSoloAvisoDeTablero(t *testing.T) {
	for _, c := range losSieteGestosDelTablero() {
		t.Run(c.nombre, func(t *testing.T) {
			q := nuevoTablero()
			c.preparar(q)
			h := montarTab(t, q)
			avisos := contarAvisos(t)

			w := c.pedir(t, h, tokenTab(t, sucStg.String()))
			if w.Code != c.codigo {
				t.Fatalf("código %d, se esperaba %d: %s", w.Code, c.codigo, w.Body.String())
			}

			if n := avisos.tiene(CambioTablero); n != 1 {
				t.Errorf("%s publicó %d avisos de «%s» y tiene que publicar exactamente 1.\n"+
					"  Cada aviso dispara un ciclo de sincronización entero en cada aparato, "+
					"contra la conexión de allá: dos por un solo gesto es el doble de todo.\n"+
					"  Salieron: %v", c.nombre, n, CambioTablero, avisos.tipos)
			}
			// Y NADA MÁS, salvo el armador, que avisa también de Rutas porque la pantalla de
			// Rutas cambió de verdad.
			esperados := 1
			if c.tambienRutas {
				esperados = 2
			}
			if avisos.total() != esperados {
				t.Errorf("%s publicó %v y se esperaban %d avisos.\n"+
					"  Un aviso de más manda a todas las pantallas abiertas a bajarse una "+
					"lista que no ha cambiado.", c.nombre, avisos.tipos, esperados)
			}
		})
	}
}

// ===========================================================================
// Y ESTO NO TOCA LA REGLA 1 DE LA CASA
// ===========================================================================
//
// «El alcance sale de quién pregunta, no de lo que mande el cliente» (`CLAUDE.md` §4). El
// aviso ahora lee la sucursal de la fila, y en una de las siete puertas esa sucursal llega
// por el `?branchId=` del cliente (`tableroDe`). La pregunta es si por ahí se cuela algo.
//
// NO: `tableroDe` comprueba ese `branchId` contra `a.ObtenerSucursal`, que va acotada, así que
// un id ajeno muere en un 404 **antes** de que haya nada escrito y antes de cualquier aviso.
// Lo que se afina es a quién se le AVISA, no a quién se le deja VER.
//
// Se prueba por los dos lados, porque fallan distinto: el que manda un `branchId` ajeno y el
// que nombra la zona de otra sucursal sin mandar ninguno.
func TestNadieSeAsomaAOtraSucursalPorElAviso(t *testing.T) {
	casos := []struct {
		nombre string
		pedir  func(t *testing.T, h http.Handler, jwt string) *httptest.ResponseRecorder
	}{
		{"con el branchId de otra sucursal en la URL",
			func(t *testing.T, h http.Handler, jwt string) *httptest.ResponseRecorder {
				return pedirTab(t, h, http.MethodPost,
					"/api/board/columns?branchId="+sucStg.String(), jwt, `{"nombre":"Colada"}`)
			}},
		{"nombrando la zona de otra sucursal",
			func(t *testing.T, h http.Handler, jwt string) *httptest.ResponseRecorder {
				return pedirTab(t, h, http.MethodPatch, "/api/board/columns/"+colCentro.String(),
					jwt, `{"nombre":"Colada"}`)
			}},
		{"soltando una tarjeta en la zona de otra sucursal",
			func(t *testing.T, h http.Handler, jwt string) *httptest.ResponseRecorder {
				return pedirTab(t, h, http.MethodPut, "/api/board/placements/"+ped1.String(),
					jwt, `{"columnaId":"`+colCentro.String()+`"}`)
			}},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			h := montarTab(t, nuevoTablero())

			anterior := busEventos
			t.Cleanup(func() { busEventos = anterior })
			busEventos = NuevoDifusor()
			// UN ABONADO QUE SE LO LLEVA TODO, también lo global: si se colara un aviso
			// —acotado o pelado—, aquí se ve.
			todo, cortar, _ := busEventos.Suscribir()
			t.Cleanup(cortar)

			// UN OPERADOR DE HOLGUÍN. Todo lo de arriba es de Santiago.
			w := c.pedir(t, h, tokenTab(t, sucHol.String()))
			if w.Code != http.StatusNotFound {
				t.Fatalf("código %d y tenía que ser 404: un operador de Holguín no puede "+
					"tocar nada de Santiago, ni sabiendo sus ids. Respuesta: %s",
					w.Code, w.Body.String())
			}
			if c, hay := recibio(todo); hay {
				t.Errorf("salió un aviso (%s / sucursal %q) por una escritura RECHAZADA.\n"+
					"  Avisar de lo que no pasó ya es malo; aquí es peor, porque el aviso "+
					"nombraría una sucursal que esta persona no puede ver.", c.Tipo, c.Sucursal)
			}
		})
	}
}

// ===========================================================================
// LAS OTRAS PANTALLAS, con el mismo SUPER ADMIN sin cabecera
// ===========================================================================

// LA BAJA DE UN CAMIÓN AVISA DE TRES COSAS Y LAS TRES CON SU SUCURSAL.
//
// Es la puerta que más se notaba: un SUPER ADMIN dando de baja un camión de Santiago mandaba a
// las OCHO a pedir `/api/vehicles`, `/api/routes` y `/api/orders`. Y la sucursal no estaba en
// ninguna variable: la fila ya no existe cuando se avisa, así que la trae el propio DELETE
// (`BorrarVehiculo` devuelve `branch_id`).
func TestLaBajaDeUnCamionAvisaSoloASuSucursal(t *testing.T) {
	// A MANO: es el uuid con el que `dobleAvisos` resuelve Santiago.
	const santiagoAMano = "11111111-1111-1111-1111-111111111111"
	if avSucStg.String() != santiagoAMano {
		t.Fatalf("el doble de avisos ya no usa %s para Santiago: %s", santiagoAMano, avSucStg)
	}

	h := montarAvisos(t, &dobleAvisos{})
	avisos := contarAvisos(t)

	// SUPER ADMIN y sin `X-Sucursal-Id`: alcance «todas», que es donde el aviso salía pelado.
	w := pedirAv(t, h, http.MethodDelete, "/api/vehicles/"+avVehStg.String(), avAdmin(t), "")
	avCodigo(t, w, http.StatusOK)

	for _, tipo := range []string{CambioVehiculos, CambioRutas, CambioPedidos} {
		suc, hubo := avisos.sucursalDe(tipo)
		if !hubo {
			t.Errorf("la baja del camión no avisó de «%s»: desvincula sus rutas y sus "+
				"pedidos antes de borrarlo, así que las tres listas cambiaron. Salieron: %v",
				tipo, avisos.tipos)
			continue
		}
		if suc != santiagoAMano {
			t.Errorf("el aviso de «%s» salió con la sucursal %q y tenía que ser %s.\n"+
				"  Lo borra un SUPER ADMIN, o sea alcance «todas»: si la sucursal sale del "+
				"alcance, este aviso va a las OCHO y siete se bajan tres listas que no han "+
				"cambiado.", tipo, suc, santiagoAMano)
		}
	}
}

// EL ALTA Y LA EDICIÓN DE UN CAMIÓN, por el mismo camino y con el mismo SUPER ADMIN.
func TestElAltaYLaEdicionDeUnCamionAvisanSoloASuSucursal(t *testing.T) {
	const santiagoAMano = "11111111-1111-1111-1111-111111111111"

	casos := []struct {
		nombre string
		hacer  func(t *testing.T, h http.Handler) *httptest.ResponseRecorder
		codigo int
	}{
		{nombre: "dar de alta un camión", hacer: func(t *testing.T, h http.Handler) *httptest.ResponseRecorder {
			// CON LA CABECERA, porque el alta necesita saber de qué sucursal es el camión:
			// sin alcance no hay `branch_id` que poner. Lo que esta prueba mira es que el
			// aviso salga de la FILA creada, no que se adivine la sucursal.
			return pedirAvConSucursal(t, h, http.MethodPost, "/api/vehicles", avAdmin(t),
				`{"name":"Camión nuevo","type":"truck"}`, avSucStg.String())
		}, codigo: http.StatusCreated},
		{nombre: "editarlo", hacer: func(t *testing.T, h http.Handler) *httptest.ResponseRecorder {
			return pedirAv(t, h, http.MethodPatch, "/api/vehicles/"+avVehStg.String(),
				avAdmin(t), `{"name":"Camión renombrado"}`)
		}, codigo: http.StatusOK},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			h := montarAvisos(t, &dobleAvisos{})
			avisos := contarAvisos(t)
			w := c.hacer(t, h)
			avCodigo(t, w, c.codigo)

			suc, hubo := avisos.sucursalDe(CambioVehiculos)
			if !hubo {
				t.Fatalf("%s no avisó de la flota. Salieron: %v", c.nombre, avisos.tipos)
			}
			if suc != santiagoAMano {
				t.Errorf("%s publicó el aviso con la sucursal %q y tenía que ser %s, la del "+
					"camión.\n"+
					"  Lo hace un SUPER ADMIN: con la sucursal sacada del alcance sale vacía "+
					"y las otras siete pantallas de Vehículos se bajan `/api/vehicles` y "+
					"`/api/settings` para pintar lo mismo.", c.nombre, suc, santiagoAMano)
			}
		})
	}
}

// pedirAvConSucursal es `pedirAv` con la cabecera de sucursal puesta. Hace falta para el alta
// de un camión: un SUPER ADMIN sin sucursal elegida no tiene `branch_id` que escribir.
func pedirAvConSucursal(t *testing.T, h http.Handler, metodo, ruta, jwt, cuerpo, sucursal string) *httptest.ResponseRecorder {
	t.Helper()
	var lector io.Reader
	if cuerpo != "" {
		lector = strings.NewReader(cuerpo)
	}
	r := httptest.NewRequest(metodo, ruta, lector)
	r.Header.Set("Authorization", "Bearer "+jwt)
	r.Header.Set(alcance.CabeceraSucursal, sucursal)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

// UN PEDIDO EDITADO O BORRADO AVISA SOLO A SU SUCURSAL.
//
// El borrado es el interesante: la fila ya no está cuando se avisa, así que la sucursal la
// trae el `RETURNING branch_id` del propio DELETE.
func TestTocarUnPedidoAvisaSoloASuSucursal(t *testing.T) {
	// A MANO: el uuid con el que el doble de pedidos resuelve Santiago.
	const santiagoAMano = "11111111-1111-1111-1111-111111111111"
	if pedidosSucStg.String() != santiagoAMano {
		t.Fatalf("el doble de pedidos ya no usa %s para Santiago: %s", santiagoAMano, pedidosSucStg)
	}

	casos := []struct {
		nombre string
		hacer  func(t *testing.T, h http.Handler) *httptest.ResponseRecorder
	}{
		{"editarlo", func(t *testing.T, h http.Handler) *httptest.ResponseRecorder {
			return pedirPedidos(t, h, http.MethodPatch, "/api/orders/"+pedidosStgA.String(),
				superAdminDePedidos(t), `{"customerName":"Bar del puerto"}`, nil)
		}},
		{"borrarlo", func(t *testing.T, h http.Handler) *httptest.ResponseRecorder {
			return pedirPedidos(t, h, http.MethodDelete, "/api/orders/"+pedidosStgA.String(),
				superAdminDePedidos(t), "", nil)
		}},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			h := servidorDePedidos(t, datosDePedidos())
			avisos := contarAvisos(t)
			w := c.hacer(t, h)
			avCodigo(t, w, http.StatusOK)

			suc, hubo := avisos.sucursalDe(CambioPedidos)
			if !hubo {
				t.Fatalf("%s no avisó de pedidos. Salieron: %v", c.nombre, avisos.tipos)
			}
			if suc != santiagoAMano {
				t.Errorf("%s publicó el aviso con la sucursal %q y tenía que ser %s, la del "+
					"pedido.\n"+
					"  Lo hace un SUPER ADMIN sin cabecera de sucursal: si el aviso sale del "+
					"alcance, sale vacío y las ocho se bajan la lista de pedidos entera.",
					c.nombre, suc, santiagoAMano)
			}
		})
	}
}

// superAdminDePedidos: el que ve las ocho, en el harness de pedidos. Es el caso en el que el
// alcance no sirve para acotar el aviso.
func superAdminDePedidos(t *testing.T) string {
	t.Helper()
	return jwtDePedidos(t, map[string]any{"sub": "p-super", "email": "super@procovar.cu",
		"role": "SUPER ADMIN"})
}

// LAS CUATRO PUERTAS DE RUTAS AVISAN CON LA SUCURSAL DE LA RUTA.
//
// Van con un SUPER ADMIN y sin cabecera de sucursal, que es el caso en el que el alcance no
// sirve de nada: es «todas». La ruta sí sabe de dónde es (`routes.branch_id`), y de ahí sale.
func TestLasPuertasDeRutasAvisanConLaSucursalDeLaRuta(t *testing.T) {
	// A MANO: es el uuid con el que el doble de rutas resuelve Santiago.
	const santiagoAMano = "11111111-1111-1111-1111-111111111111"
	if stgDeRutas.String() != santiagoAMano {
		t.Fatalf("el doble de rutas ya no usa %s para Santiago: %s", santiagoAMano, stgDeRutas)
	}

	casos := []struct {
		nombre string
		hacer  func(t *testing.T, h http.Handler, ruta uuid.UUID) *httptest.ResponseRecorder
	}{
		{nombre: "despacharla", hacer: func(t *testing.T, h http.Handler, ruta uuid.UUID) *httptest.ResponseRecorder {
			return llamarRutas(t, h, http.MethodPatch, "/api/routes/"+ruta.String(),
				superAdminEnRutas(t), `{"status":"in_progress"}`)
		}},
		{nombre: "cambiarle el camión", hacer: func(t *testing.T, h http.Handler, ruta uuid.UUID) *httptest.ResponseRecorder {
			return llamarRutas(t, h, http.MethodPatch, "/api/routes/"+ruta.String(),
				superAdminEnRutas(t), `{"vehicleId":null}`)
		}},
		{nombre: "borrarla", hacer: func(t *testing.T, h http.Handler, ruta uuid.UUID) *httptest.ResponseRecorder {
			return llamarRutas(t, h, http.MethodDelete, "/api/routes/"+ruta.String(),
				superAdminEnRutas(t), "")
		}},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			d, stg, _ := datosDeReparto()
			h := montarRutas(t, d)
			// La ruta se arma con el token de Santiago —hace falta sucursal para crearla— y
			// lo que se MIDE es la puerta de después, que va con el SUPER ADMIN.
			ruta := armarRutaDePrueba(t, h, deSantiagoEnRutas(t), stg[1])

			avisos := contarAvisos(t)
			w := c.hacer(t, h, ruta)
			if w.Code != http.StatusOK {
				t.Fatalf("código %d, se esperaba 200: %s", w.Code, w.Body.String())
			}

			suc, hubo := avisos.sucursalDe(CambioRutas)
			if !hubo {
				t.Fatalf("%s no avisó de rutas. Salieron: %v", c.nombre, avisos.tipos)
			}
			if suc != santiagoAMano {
				t.Errorf("%s publicó el aviso con la sucursal %q y tenía que ser %s, la de "+
					"la ruta.\n"+
					"  Lo hace un SUPER ADMIN y sin `X-Sucursal-Id`: si el aviso sale del "+
					"alcance, sale vacío y las ocho se bajan la lista de rutas entera.",
					c.nombre, suc, santiagoAMano)
			}
		})
	}
}

// Y EL ARMADO DE UNA RUTA, la otra puerta de `rutas.go`.
func TestArmarUnaRutaAvisaConLaSucursalDeLaRutaCreada(t *testing.T) {
	const santiagoAMano = "11111111-1111-1111-1111-111111111111"

	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	avisos := contarAvisos(t)

	// CON LA CABECERA, porque crear una ruta necesita saber de qué sucursal es: sin alcance no
	// hay `branch_id` que escribir. Lo que se mide es que el aviso salga de la fila CREADA.
	r := httptest.NewRequest(http.MethodPost, "/api/routes",
		strings.NewReader(cuerpoDeArmado(camionStg.String(), stg[1])))
	r.Header.Set("Authorization", "Bearer "+superAdminEnRutas(t))
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set(alcance.CabeceraSucursal, stgDeRutas.String())
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != http.StatusCreated {
		t.Fatalf("la ruta no se armó (%d): %s", w.Code, w.Body.String())
	}

	suc, hubo := avisos.sucursalDe(CambioRutas)
	if !hubo {
		t.Fatalf("armar una ruta no avisó de rutas. Salieron: %v", avisos.tipos)
	}
	if suc != santiagoAMano {
		t.Errorf("el aviso salió con la sucursal %q y tenía que ser %s, la de la ruta que "+
			"se acaba de crear (`creada.BranchID`).", suc, santiagoAMano)
	}
}
