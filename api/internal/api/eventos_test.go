package api

// Las pruebas de los eventos en vivo.
//
// Van contra un servidor HTTP DE VERDAD y no contra un `httptest.ResponseRecorder`: lo que
// hay que comprobar aquí es un flujo que se queda abierto, y un grabador no tiene ni
// vaciado, ni corte de cliente, ni apagado. Con un grabador estas cuatro pruebas pasarían
// sin probar nada.

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"runtime"
	"strings"
	"testing"
	"time"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
)

// manejadorDeEventos monta `/api/eventos` con el bus que se le diga, y con los middlewares
// comunes puestos: `SinCache` tiene que quedar pisado por las cabeceras del flujo.
func manejadorDeEventos(t *testing.T, bus *Difusor) http.Handler {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoDePanel)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	s := NuevoServidor(cfg, reg,
		alcance.NuevaPorteria(fuenteDePanel{q: &dobleDePanel{}}, reg),
		auth.NuevoVerificador([]byte(secretoDePanel)), nil)

	rt := httpx.NuevoRouter(httpx.ConRegistro(reg), httpx.SinCache)
	rt.ManejarFunc(http.MethodGet, "/api/eventos", func(w http.ResponseWriter, r *http.Request) {
		s.servirEventos(w, r, bus)
	})
	return rt.Handler()
}

// lineas lee el flujo en una gorutina y las va soltando. La gorutina muere cuando se cierra
// el cuerpo de la respuesta, que es lo que hace el `defer` de cada prueba.
func lineasDeEventos(cuerpo io.Reader) <-chan string {
	ch := make(chan string, 64)
	go func() {
		defer close(ch)
		sc := bufio.NewScanner(cuerpo)
		for sc.Scan() {
			ch <- sc.Text()
		}
	}()
	return ch
}

// esperarLinea espera a que llegue una línea que empiece por el prefijo, descartando las de
// en medio (el latido puede colarse antes que el cambio). Devuelve la línea entera.
func esperarLinea(t *testing.T, ch <-chan string, prefijo string, plazo time.Duration) string {
	t.Helper()
	limite := time.After(plazo)
	for {
		select {
		case l, abierto := <-ch:
			if !abierto {
				t.Fatalf("el flujo se cerró antes de ver %q", prefijo)
			}
			if strings.HasPrefix(l, prefijo) {
				return l
			}
		case <-limite:
			t.Fatalf("no llegó %q en %s", prefijo, plazo)
		}
	}
}

// El 401 de esta ruta es TEXTO PLANO, no el {"error":...} de todas las demás: es lo que
// sabe leer el EventSource del navegador.
func TestEventosSinSesionDevuelveTextoPlano(t *testing.T) {
	h := manejadorDeEventos(t, NuevoDifusor())
	r := httptest.NewRequest(http.MethodGet, "/api/eventos", nil)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("código %d, se esperaba 401", w.Code)
	}
	if cuerpo := w.Body.String(); cuerpo != "Unauthorized" {
		t.Errorf("el cuerpo es %q, se esperaba el literal «Unauthorized» sin JSON", cuerpo)
	}
	if ct := w.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/plain") {
		t.Errorf("el tipo de contenido es %q, se esperaba texto plano", ct)
	}
}

// El flujo entero: cabeceras, el `listo` de apertura, un cambio y el latido.
func TestEventosMandaListoCambioYLatido(t *testing.T) {
	// El latido de verdad son veinte segundos; aquí se acorta para no esperarlos.
	original := latidoSSE
	latidoSSE = 20 * time.Millisecond
	defer func() { latidoSSE = original }()

	bus := NuevoDifusor()
	srv := httptest.NewServer(manejadorDeEventos(t, bus))
	defer srv.Close()

	r, err := http.NewRequest(http.MethodGet, srv.URL+"/api/eventos", nil)
	if err != nil {
		t.Fatal(err)
	}
	r.Header.Set("Authorization", "Bearer "+tokenDePanel(t, map[string]any{"sub": "u1", "role": "SUPER ADMIN"}))
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("código %d", resp.StatusCode)
	}
	// Las tres cabeceras que no se pueden tocar sin romper el flujo por detrás de un proxy.
	if ct := resp.Header.Get("Content-Type"); ct != "text/event-stream; charset=utf-8" {
		t.Errorf("Content-Type es %q", ct)
	}
	if cc := resp.Header.Get("Cache-Control"); cc != "no-store, no-transform" {
		t.Errorf("Cache-Control es %q: tiene que pisar al de SinCache y llevar no-transform", cc)
	}
	if b := resp.Header.Get("X-Accel-Buffering"); b != "no" {
		t.Errorf("falta X-Accel-Buffering: no (vale %q); nginx guardaría los eventos en su colchón", b)
	}
	// NUNCA keep-alive: HTTP/2 y HTTP/3 lo prohíben y Cloudflare corta la conexión.
	if c := resp.Header.Get("Connection"); strings.EqualFold(c, "keep-alive") {
		t.Error("salió Connection: keep-alive, que es justo lo que no puede ir")
	}

	ch := lineasDeEventos(resp.Body)
	if l := esperarLinea(t, ch, "event:", time.Second); l != "event: listo" {
		t.Fatalf("el primer evento es %q, tiene que ser «listo»", l)
	}
	if l := esperarLinea(t, ch, "data:", time.Second); l != `data: {"vivo":true}` {
		t.Errorf("el dato del listo es %q", l)
	}

	// EL LATIDO, Y SE MIRAN LAS DOS LÍNEAS.
	//
	// Es lo único que impide que el proxy corte la conexión por callada, y desde el
	// 29/09/2026 va con NOMBRE y con `data:` para que el navegador pueda verlo: el
	// `EventSource` descarta los comentarios SSE, y una trama sin `data:` tampoco la
	// entrega. Mirar sólo una de las dos líneas deja pasar justo la mitad que lo haría
	// invisible en la web — y eso no falla: el canal sigue vivo, lo que vuelve es el reloj.
	if l := esperarLinea(t, ch, "event: ", time.Second); l != "event: "+NombreDelLatido {
		t.Fatalf("el latido salió como %q y tenía que ser «event: %s».\n"+
			"  Un comentario SSE (`: latido`) mantiene la conexión abierta pero el "+
			"`EventSource` del navegador lo tira por especificación: la web se queda sin "+
			"saber que el canal está vivo y le vuelve el reloj.", l, NombreDelLatido)
	}
	if l := esperarLinea(t, ch, "data:", time.Second); l != "data: {}" {
		t.Errorf("el latido llegó con %q y tiene que llevar `data: {}`.\n"+
			"  Un evento SIN `data:` el navegador NO lo entrega: el analizador de SSE "+
			"descarta la trama con el búfer de datos vacío, así que sería el mismo "+
			"agujero con otra forma.", l)
	}

	// Y un cambio de verdad.
	if !bus.Avisar(CambioPedidos, map[string]any{"pedidos": 42}) {
		t.Fatal("el aviso no salió")
	}
	esperarLinea(t, ch, "event: cambio", time.Second)
	dato := esperarLinea(t, ch, "data:", time.Second)

	var m map[string]any
	if err := json.Unmarshal([]byte(strings.TrimPrefix(dato, "data: ")), &m); err != nil {
		t.Fatalf("el dato del cambio no es JSON: %v (%s)", err, dato)
	}
	if m["tipo"] != CambioPedidos {
		t.Errorf("el tipo del cambio es %v", m["tipo"])
	}
	if m["pedidos"] != float64(42) {
		t.Errorf("el detalle no viajó: %v", m)
	}
	if _, hay := m["cuando"]; !hay {
		t.Error("el cambio no lleva «cuando»")
	}
}

// AL CORTAR EL CLIENTE, LA CONEXIÓN SE CIERRA Y NO QUEDA NADA VIVO. Con una gorutina por
// conexión, cada pestaña que se cierra sin avisar deja una detrás; con doscientas al día,
// eso es un proceso que crece hasta que alguien lo reinicia.
func TestEventosSeCierranAlCortarElClienteYNoDejanNadaVivo(t *testing.T) {
	bus := NuevoDifusor()
	srv := httptest.NewServer(manejadorDeEventos(t, bus))
	defer srv.Close()

	antes := runtime.NumGoroutine()

	ctx, cancelar := context.WithCancel(context.Background())
	r, err := http.NewRequestWithContext(ctx, http.MethodGet, srv.URL+"/api/eventos", nil)
	if err != nil {
		t.Fatal(err)
	}
	r.Header.Set("Authorization", "Bearer "+tokenDePanel(t, map[string]any{"sub": "u1", "role": "SUPER ADMIN"}))
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	ch := lineasDeEventos(resp.Body)
	esperarLinea(t, ch, "event: listo", time.Second)

	if bus.Abonados() != 1 {
		t.Fatalf("hay %d abonados, se esperaba 1", bus.Abonados())
	}

	cancelar()
	_ = resp.Body.Close()

	// El abono suelto es la prueba de que el manejador VOLVIÓ y corrió sus `defer`. Es una
	// señal mucho más firme que contar gorutinas, que las tiene también net/http.
	esperarA(t, 2*time.Second, func() bool { return bus.Abonados() == 0 },
		"el abonado sigue enganchado: el manejador no volvió al cortar el cliente")

	esperarA(t, 2*time.Second, func() bool { return runtime.NumGoroutine() <= antes+2 },
		"quedaron gorutinas vivas después de cortar la conexión")
}

// EL APAGADO ORDENADO. `Shutdown` espera a las peticiones en vuelo, y una conexión de
// eventos no termina nunca por su cuenta: sin engancharla al apagado, el servidor se come
// el plazo entero y luego corta a lo bruto, llevándose por delante las peticiones normales
// que sí estaban a medias.
func TestEventosAbiertosNoDejanColgadoElApagado(t *testing.T) {
	bus := NuevoDifusor()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	srv := &http.Server{Handler: manejadorDeEventos(t, bus)}
	go func() { _ = srv.Serve(ln) }()

	r, err := http.NewRequest(http.MethodGet, "http://"+ln.Addr().String()+"/api/eventos", nil)
	if err != nil {
		t.Fatal(err)
	}
	r.Header.Set("Authorization", "Bearer "+tokenDePanel(t, map[string]any{"sub": "u1", "role": "SUPER ADMIN"}))
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	esperarLinea(t, lineasDeEventos(resp.Body), "event: listo", time.Second)

	ctx, cancelar := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancelar()
	inicio := time.Now()
	if err := srv.Shutdown(ctx); err != nil {
		t.Fatalf("el apagado se quedó colgado con una conexión de eventos abierta: %v", err)
	}
	if tardo := time.Since(inicio); tardo > 2*time.Second {
		t.Errorf("el apagado tardó %s: la conexión de eventos no se cerró sola", tardo)
	}
	if bus.Abonados() != 0 {
		t.Errorf("quedan %d abonados después del apagado", bus.Abonados())
	}
}

// Con el bus ya cerrado —el proceso se está parando— una conexión nueva no se queda
// esperando algo que no va a llegar: se le dice y se cierra, y la pantalla pasa a refrescar
// sola.
func TestEventosConElBusCerradoDiceSinVivo(t *testing.T) {
	bus := NuevoDifusor()
	bus.Cerrar()

	h := manejadorDeEventos(t, bus)
	r := httptest.NewRequest(http.MethodGet, "/api/eventos", nil)
	r.Header.Set("Authorization", "Bearer "+tokenDePanel(t, map[string]any{"sub": "u1", "role": "SUPER ADMIN"}))
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)

	if cuerpo := w.Body.String(); cuerpo != "event: sin-vivo\ndata: {}\n\n" {
		t.Errorf("el cuerpo es %q", cuerpo)
	}
}

// El freno: como mucho un aviso cada quince segundos POR TIPO. El espejo importa por lotes
// de doscientos y avisaba por cada uno — veinte recargas seguidas de la pantalla.
func TestDifusorFrenaUnAvisoPorTipoCada15s(t *testing.T) {
	reloj := time.Date(2026, 9, 14, 10, 0, 0, 0, time.UTC)
	d := NuevoDifusor()
	d.ahora = func() time.Time { return reloj }

	if !d.Avisar(CambioPedidos, nil) {
		t.Fatal("el primer aviso tiene que salir")
	}
	reloj = reloj.Add(14 * time.Second)
	if d.Avisar(CambioPedidos, nil) {
		t.Error("el segundo aviso del mismo tipo a los 14 s tenía que quedarse fuera")
	}
	// Otro TIPO no comparte el freno: el catálogo y los pedidos se invalidan por separado.
	if !d.Avisar(CambioCatalogo, nil) {
		t.Error("el freno de «pedidos» no puede parar a «catalogo»")
	}
	reloj = reloj.Add(2 * time.Second) // 16 s del primero
	if !d.Avisar(CambioPedidos, nil) {
		t.Error("pasados los 15 s el aviso tiene que volver a salir")
	}
}

// Un detalle que traiga `tipo` no puede pisar el del aviso: la pantalla invalidaría otra
// cosa distinta de la que cambió.
func TestCambioNoDejaQueElDetallePiseElTipo(t *testing.T) {
	c := Cambio{
		Tipo:    CambioRutas,
		Cuando:  time.Date(2026, 9, 14, 10, 0, 0, 0, time.UTC),
		Detalle: map[string]any{"tipo": "clientes", "cuando": "ayer", "rutas": 2},
	}
	var m map[string]any
	if err := json.Unmarshal(c.datos(), &m); err != nil {
		t.Fatal(err)
	}
	if m["tipo"] != CambioRutas {
		t.Errorf("el tipo quedó en %v", m["tipo"])
	}
	if m["cuando"] != "2026-09-14T10:00:00.000Z" {
		t.Errorf("«cuando» quedó en %v", m["cuando"])
	}
	if m["rutas"] != float64(2) {
		t.Errorf("el detalle se perdió: %v", m)
	}
}

// Un abonado que no lee no puede frenar a quien avisa: se le pierde el aviso y ya, que el
// siguiente le dirá lo mismo. Si bloqueara, una importación de mil pedidos se quedaría
// esperando a un navegador con la pestaña en segundo plano.
func TestDifusorNoSeBloqueaConUnAbonadoQueNoLee(t *testing.T) {
	d := NuevoDifusor()
	d.freno = 0 // aquí se prueba el atasco, no el freno
	if _, _, vivo := d.Suscribir(); !vivo {
		t.Fatal("el bus tenía que estar vivo")
	}

	hecho := make(chan struct{})
	go func() {
		for i := 0; i < colaAbonado*3; i++ {
			d.Avisar(CambioPedidos, map[string]any{"n": i})
		}
		close(hecho)
	}()
	select {
	case <-hecho:
	case <-time.After(2 * time.Second):
		t.Fatal("avisar se quedó bloqueado por un abonado que no lee")
	}
}

func esperarA(t *testing.T, plazo time.Duration, cumple func() bool, queja string) {
	t.Helper()
	limite := time.Now().Add(plazo)
	for time.Now().Before(limite) {
		if cumple() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Error(queja)
}

// LO QUE PASA DENTRO DEL FRENO NO SE PIERDE: sale al vencer.
//
// El freno era de flanco de SUBIDA puro: lo que llegaba dentro de los quince segundos se
// descartaba y no se reprogramaba. Con el espejo daba igual —siempre hay un lote detrás
// que vuelve a avisar—, pero **con un gesto humano no**: doce tarjetas arrastradas en doce
// segundos mandaban UN aviso, el de la primera, o sea el momento en que menos hay que
// contar. La otra pantalla refrescaba tras la tarjeta 1 y se quedaba once atrás hasta el
// temporizador: dos minutos en la web, cinco en la APK.
//
// Es la queja de Jose del 16/09 —«moví cosas y en la web no salió en tiempo real»—
// arreglada a un doceavo.
func TestLoQueEntraDentroDelFrenoSaleAlVencer(t *testing.T) {
	reloj := time.Date(2026, 9, 17, 10, 0, 0, 0, time.UTC)
	d := NuevoDifusor()
	d.ahora = func() time.Time { return reloj }

	canal, cortar, vivo := d.Suscribir()
	if !vivo {
		t.Fatal("el bus tenía que estar vivo")
	}
	defer cortar()

	// Doce gestos en doce segundos, como arrastrar doce tarjetas seguidas.
	for i := 0; i < 12; i++ {
		d.Avisar(CambioTablero, map[string]any{"gesto": i})
		reloj = reloj.Add(time.Second)
	}

	// Sale el primero, que es lo correcto: la pantalla se entera en el acto.
	primero := recibir(t, canal)
	if primero.Detalle["gesto"] != 0 {
		t.Fatalf("el primero fue %v", primero.Detalle["gesto"])
	}
	if hayCambio(canal) {
		t.Fatal("salió un segundo aviso dentro del freno: eso es el parpadeo que el " +
			"freno viene a evitar")
	}

	// Pasa el freno y lo suelta el latido.
	reloj = reloj.Add(15 * time.Second)
	d.SoltarPendientes()

	ultimo := recibir(t, canal)
	if ultimo.Detalle["gesto"] != 11 {
		t.Errorf("salió el gesto %v y tenía que salir el ÚLTIMO (11): es el que describe "+
			"cómo está el tablero ahora", ultimo.Detalle["gesto"])
	}
}

// Y si no quedó nada pendiente, soltar no manda nada.
//
// Lo llama el latido de CADA conexión abierta, cada veinte segundos. Si mandara algo sin
// haber cambiado nada, diez navegadores abiertos serían diez recargas del tablero por
// minuto sin que nadie hubiera tocado una tarjeta.
func TestSoltarSinNadaPendienteNoMandaNada(t *testing.T) {
	reloj := time.Date(2026, 9, 17, 10, 0, 0, 0, time.UTC)
	d := NuevoDifusor()
	d.ahora = func() time.Time { return reloj }

	canal, cortar, _ := d.Suscribir()
	defer cortar()

	d.Avisar(CambioTablero, nil)
	recibir(t, canal)

	reloj = reloj.Add(time.Hour)
	d.SoltarPendientes()
	d.SoltarPendientes()

	if hayCambio(canal) {
		t.Error("mandó un aviso sin que hubiera cambiado nada: con diez navegadores " +
			"abiertos eso son diez recargas por minuto de balde")
	}
}

// Cada tipo lleva su propio pendiente: un cambio del tablero no se come el de pedidos.
func TestCadaTipoGuardaSuPendiente(t *testing.T) {
	reloj := time.Date(2026, 9, 17, 10, 0, 0, 0, time.UTC)
	d := NuevoDifusor()
	d.ahora = func() time.Time { return reloj }

	canal, cortar, _ := d.Suscribir()
	defer cortar()

	d.Avisar(CambioTablero, nil)
	d.Avisar(CambioPedidos, nil)
	recibir(t, canal)
	recibir(t, canal)

	// Los dos, dentro del freno.
	reloj = reloj.Add(2 * time.Second)
	d.Avisar(CambioTablero, map[string]any{"cual": "tablero"})
	d.Avisar(CambioPedidos, map[string]any{"cual": "pedidos"})

	reloj = reloj.Add(20 * time.Second)
	d.SoltarPendientes()

	vistos := map[string]bool{}
	for i := 0; i < 2; i++ {
		c := recibir(t, canal)
		vistos[c.Tipo] = true
	}
	if !vistos[CambioTablero] || !vistos[CambioPedidos] {
		t.Errorf("se perdió uno de los dos: %v", vistos)
	}
}

func recibir(t *testing.T, canal <-chan Cambio) Cambio {
	t.Helper()
	select {
	case c := <-canal:
		return c
	case <-time.After(time.Second):
		t.Fatal("no llegó ningún aviso")
		return Cambio{}
	}
}

func hayCambio(canal <-chan Cambio) bool {
	select {
	case <-canal:
		return true
	default:
		return false
	}
}

// EL LATIDO SE VE DESDE EL NAVEGADOR, Y SIGUE SIENDO TRÁFICO.
//
// Son las dos mitades del cambio del 29/09/2026 y hay que comprobar las dos:
//
//  1. **Que se ve.** `EventSource` descarta los comentarios SSE por especificación, así que
//     un `: latido` es invisible en la web. Con nombre y con `data:` lo entrega — las dos
//     cosas: una trama con el búfer de datos vacío tampoco se entrega.
//  2. **Que sigue sirviendo para lo que servía.** El latido está ahí para que un proxy no
//     corte una conexión callada, o sea para que haya tráfico cada veinte segundos. Un
//     evento con nombre son más bytes que un comentario, pero si dejara de repetirse la
//     conexión se caería igual. Por eso se esperan DOS, no uno.
//
// Y la tercera, que es la que no se ve venir: **un latido no puede leerse como un cambio**.
// Si lo fuera, cada veinte segundos toda pantalla abierta volvería a pedir su lista — el
// sondeo que esto vino a quitar, con otro nombre.
func TestElLatidoSeVeDesdeElNavegadorYNoEsUnCambio(t *testing.T) {
	original := latidoSSE
	latidoSSE = 20 * time.Millisecond
	defer func() { latidoSSE = original }()

	srv := httptest.NewServer(manejadorDeEventos(t, NuevoDifusor()))
	t.Cleanup(srv.Close)

	r, err := http.NewRequest(http.MethodGet, srv.URL+"/api/eventos", nil)
	if err != nil {
		t.Fatal(err)
	}
	r.Header.Set("Authorization", "Bearer "+tokenDePanel(t,
		map[string]any{"sub": "u1", "role": "SUPER ADMIN"}))
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	ch := lineasDeEventos(resp.Body)
	esperarLinea(t, ch, "event: listo", time.Second)
	esperarLinea(t, ch, "data:", time.Second)

	// Se leen las tramas del latido de una en una: nombre, dato, y vuelta.
	for i := 1; i <= 2; i++ {
		l := esperarLinea(t, ch, "event", time.Second)
		if l != "event: "+NombreDelLatido {
			t.Fatalf("el latido %d salió como %q.\n"+
				"  Tenía que ser «event: %s»: un comentario SSE no lo entrega el "+
				"navegador, y un `event: cambio` mandaría a toda pantalla abierta a "+
				"pedir su lista cada veinte segundos.", i, l, NombreDelLatido)
		}
		if d := esperarLinea(t, ch, "data", time.Second); d != "data: {}" {
			t.Fatalf("el latido %d llegó con %q y tiene que llevar `data: {}`: una trama "+
				"sin datos no se entrega y el latido volvería a ser invisible", i, d)
		}
	}
}

// EL LATIDO ES UN CONTRATO ENTRE DOS FICHEROS QUE NO SE VEN, así que su literal se fija.
//
// La web lo escucha por su nombre (`app/lib/nucleo/red/eventos_web.dart`,
// `addEventListener`), y un `EventSource` que escucha «latido» no recibe nada si el
// servidor manda «pulso». **Eso no falla**: la conexión sigue abierta, los avisos siguen
// llegando, y lo único que pasa es que la web deja de saber que el canal está vivo y le
// vuelve el reloj — nueve vueltas en una jornada, sin un error y sin un registro.
//
// SE COMPARA CONTRA EL TEXTO A PELO Y NO CONTRA LA CONSTANTE, a propósito: una prueba que
// escribe `NombreDelLatido` a los dos lados pasa con la constante renombrada, que es
// exactamente el fallo que viene a cerrar. Es la misma trampa de la casa que
// `protocolo_avisos_test.go` cierra para los tipos de `Cambio…` — allí se puede leer el
// fichero de Dart porque el Dockerfile lo copia; aquí se fija el literal, que es lo que
// obliga a venir a este mensaje antes de cambiarlo.
func TestElNombreDelLatidoNoSeRenombraSolo(t *testing.T) {
	if NombreDelLatido != "latido" {
		t.Errorf("el latido se llama ahora %q por el cable.\n"+
			"  La web lo escucha por su nombre en app/lib/nucleo/red/eventos_web.dart: si "+
			"se cambia aquí y no allí, el navegador deja de ver el latido, el canal se lee "+
			"como callado y vuelve el reloj. No falla, no da error y no sale en ningún "+
			"registro.\n"+
			"  Si de verdad hay que renombrarlo, se cambian LOS DOS y se cambia también "+
			"este literal.", NombreDelLatido)
	}
	if bloqueDelLatido != "event: latido\ndata: {}\n\n" {
		t.Errorf("el latido sale por el cable como %q.\n"+
			"  Tiene que ser una trama SSE entera: `event:` para que el navegador no la "+
			"tire como comentario, y `data:` para que la entregue — sin datos, el "+
			"analizador de SSE descarta la trama y el latido vuelve a ser invisible.",
			bloqueDelLatido)
	}
}
