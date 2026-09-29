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
	sinDespertadores(d)

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
// descartaba y no se reprogramaba. Con una avalancha de PEDIDO daba igual —siempre hay un
// lote detrás que vuelve a avisar—, pero si el último lote es el que se come el freno, ese
// aviso no se decía nunca y la pantalla se quedaba en el penúltimo hasta el temporizador:
// dos minutos en la web, cinco en la APK.
//
// # VEINTE AVISOS DE MÁQUINA SEGUIDOS Y SALEN FRENADOS — la pareja obligatoria
//
// Esta prueba es la mitad que impide cambiar un fallo por el otro. Su pareja es
// `TestDosGestosSeguidosSalenLosDosAlMomento`: allí se comprueba que un gesto no espera
// NADA, y aquí que una importación sigue sin provocar una tormenta. Si sólo estuviera una de
// las dos, arreglar un lado rompería el otro en silencio.
//
// Estaba escrita con `CambioTablero` porque ése era el ejemplo vivo mientras TODOS los tipos
// se frenaban. Va con `CambioPedidos`, que es lo que de verdad llega por lotes de doscientos
// (`tiposFrenados`).
func TestVeinteAvisosDeMaquinaSalenFrenadosYNoSePierdeElUltimo(t *testing.T) {
	reloj := time.Date(2026, 9, 17, 10, 0, 0, 0, time.UTC)
	d := NuevoDifusor()
	d.ahora = func() time.Time { return reloj }
	sinDespertadores(d)

	canal, cortar, vivo := d.Suscribir()
	if !vivo {
		t.Fatal("el bus tenía que estar vivo")
	}
	defer cortar()

	// Veinte lotes en veinte segundos, que es lo que hace una importación del espejo.
	for i := 0; i < 20; i++ {
		d.Avisar(CambioPedidos, map[string]any{"lote": i})
		reloj = reloj.Add(time.Second)
	}

	// VEINTE LOTES, DOS AVISOS. Los números van a mano y son de la aritmética, no de la
	// constante: con freno de 15 s y lotes de 1 s salen el lote 0 (no había nada antes) y el
	// lote 15 (justo cuando vence el freno del 0). Los otros dieciocho se quedan dentro.
	salidos := []any{}
	for {
		c, hay := siHayCambio(canal)
		if !hay {
			break
		}
		salidos = append(salidos, c.Detalle["lote"])
	}
	if len(salidos) != 2 {
		t.Fatalf("de veinte lotes salieron %d avisos (%v) y tenían que salir 2.\n"+
			"  Cada aviso dispara un ciclo de sincronización ENTERO en el aparato: veinte "+
			"avisos son veinte ciclos contra la conexión de Cuba, que es la tormenta que "+
			"el freno existe para evitar («tiposFrenados»).", len(salidos), salidos)
	}
	if salidos[0] != 0 || salidos[1] != 15 {
		t.Errorf("salieron los lotes %v y tenían que salir el 0 y el 15 (segundo 0 y "+
			"segundo 15, que es cuando vence el freno del primero)", salidos)
	}

	// Y EL ÚLTIMO NO SE PIERDE: lo que se quedó dentro sale al vencer.
	reloj = reloj.Add(15 * time.Second)
	d.SoltarPendientes()

	ultimo := recibir(t, canal)
	if ultimo.Detalle["lote"] != 19 {
		t.Errorf("salió el lote %v y tenía que salir el ÚLTIMO (19): es el que describe "+
			"cómo está la base ahora, y si se pierde nadie vuelve a decirlo",
			ultimo.Detalle["lote"])
	}
}

// EL PENDIENTE SALE SOLO, SIN QUE NADIE LLAME A NADA — 29/09/2026.
//
// Hasta hoy `SoltarPendientes` sólo lo llamaba el latido, cada `latidoSSE` = 20 s. Con un
// freno de 15, eso son quince segundos REDONDEADOS AL ALZA A MÚLTIPLO DE VEINTE. Medido en
// producción esa noche: cinco frenadas de 6,77 · 17,89 · 20,41 · 20,76 y **26,68** segundos,
// contra una constante que dice quince. Las horas de salida lo cantaban —21:02:40.300 ·
// 21:03:00.298 · 21:03:20.319, veinte clavados.
//
// Va con el RELOJ DEL SISTEMA y con un freno de milisegundos, porque lo que se comprueba es
// justamente el temporizador de verdad: con el reloj a mano no hay nada que esperar y la
// prueba pasaría sin despertador ninguno. **Y NO SE LLAMA A `SoltarPendientes`**: si hiciera
// falta llamarlo, esto se cuelga hasta el plazo y sale rojo, que es lo que tiene que pasar.
func TestElPendienteSaleSoloSinEsperarAlLatido(t *testing.T) {
	d := NuevoDifusor()
	d.freno = 40 * time.Millisecond

	canal, cortar, vivo := d.Suscribir()
	if !vivo {
		t.Fatal("el bus tenía que estar vivo")
	}
	defer cortar()

	if !d.Avisar(CambioPedidos, map[string]any{"lote": 1}) {
		t.Fatal("el primero tenía que salir")
	}
	recibir(t, canal)
	if d.Avisar(CambioPedidos, map[string]any{"lote": 2}) {
		t.Fatal("el segundo tenía que quedarse dentro del freno")
	}

	// Un segundo de plazo contra un freno de 40 ms: veinticinco veces de margen. Si el
	// pendiente esperase al latido no llegaría nunca aquí — `latidoSSE` son 20 s.
	select {
	case c := <-canal:
		if c.Detalle["lote"] != 2 {
			t.Errorf("salió el lote %v y tenía que salir el 2", c.Detalle["lote"])
		}
	case <-time.After(time.Second):
		t.Fatal("el pendiente NO salió solo: sigue esperando a que alguien llame a " +
			"SoltarPendientes.\n" +
			"  Colgado del latido, un freno de 15 s se convierte en 15 redondeado al alza a " +
			"múltiplo de 20 — medido en producción el 29/09/2026, la peor frenada fue de " +
			"26,68 s contra una constante que dice quince. Ver «despertarEn».")
	}
}

// EL CASO DE JOSE, MEDIDO: dos gestos seguidos y los DOS salen al momento.
//
// 29/09/2026, con el navegador en una mano y el teléfono en la otra, moviendo dos tarjetas
// del tablero. Lo que salió por el cable:
//
//	20:59:22.622  mueve la primera  ->  aviso 20:59:22.776    154 ms
//	20:59:24.052  mueve la segunda  ->  aviso 20:59:40.441    16 SEGUNDOS
//
// Los quince del freno más lo que tardó el latido en soltar el pendiente. Jose: «pero debe
// ser en tiempo real deben ocurrir por q se demoran 15segundos en ocurrir».
//
// **Un gesto de una persona no espera NADA. Cero.** No es un número más corto: es que
// `tablero` ya no está en `tiposFrenados`.
//
// EL RELOJ NO SE MUEVE ENTRE LOS DOS AVISOS a propósito — o sí, un segundo, que es lo que
// Jose tardó. Si hubiera cualquier freno, por corto que fuera, el segundo se quedaría dentro
// y esta prueba se pondría roja. Es justo lo que tiene que pasar.
func TestDosGestosSeguidosSalenLosDosAlMomento(t *testing.T) {
	reloj := time.Date(2026, 9, 29, 20, 59, 22, 0, time.UTC)
	d := NuevoDifusor()
	d.ahora = func() time.Time { return reloj }

	canal, cortar, vivo := d.Suscribir()
	if !vivo {
		t.Fatal("el bus tenía que estar vivo")
	}
	defer cortar()

	if !d.Avisar(CambioTablero, map[string]any{"tarjeta": 1}) {
		t.Fatal("la primera tarjeta no avisó")
	}
	// UN SEGUNDO DESPUÉS, que es lo que Jose tardó en coger la segunda.
	reloj = reloj.Add(time.Second)
	if !d.Avisar(CambioTablero, map[string]any{"tarjeta": 2}) {
		t.Fatal("LA SEGUNDA TARJETA SE QUEDÓ FRENADA.\n" +
			"  Éste es el fallo entero: el 29/09/2026 tardó 16,4 segundos en verse en la " +
			"otra pantalla. Un gesto de una persona no espera nada — «tablero» no puede " +
			"estar en `tiposFrenados` (eventos.go).")
	}

	// Y LAS DOS SALEN POR EL CABLE, en orden y sin que nadie suelte nada.
	if c := recibir(t, canal); c.Detalle["tarjeta"] != 1 {
		t.Errorf("la primera que salió fue la tarjeta %v", c.Detalle["tarjeta"])
	}
	segunda := recibir(t, canal)
	if segunda.Detalle["tarjeta"] != 2 {
		t.Errorf("la segunda que salió fue la tarjeta %v", segunda.Detalle["tarjeta"])
	}
	// Sin llamar a `SoltarPendientes`: si hiciera falta el latido, el retraso real sería de
	// hasta veinte segundos más y volveríamos a los dieciséis de aquel día.
	if len(d.pendiente) != 0 {
		t.Errorf("quedaron %d avisos esperando al latido: %v.\n"+
			"  Un gesto que se guarda como pendiente sale cuando late la conexión, o sea "+
			"hasta 20 s después. Eso NO es tiempo real.", len(d.pendiente), d.pendiente)
	}
}

// LOS TIPOS FRENADOS SON EXACTAMENTE ESTOS TRES, Y LOS TRES NOMBRES VAN A MANO.
//
// # Por qué la lista se fija aquí y no se compara contra la constante
//
// Comparar `tiposFrenados` consigo misma no comprueba nada: añadir un tipo mañana dejaría
// esto en verde y su pantalla se quedaría hasta medio minuto vieja sin que fallara nada, sin
// error y sin registro. Los tres nombres están escritos a mano para que meter un cuarto
// obligue a venir aquí — y de paso a leer lo que significa estar en esa lista.
//
// # Qué significa estar en la lista
//
// Que ese aviso puede tardar **hasta 15 segundos** en llegar a la otra pantalla. Se acepta
// sólo para lo que entra por la manguera de PEDIDO, donde un aviso por lote son veinte
// ciclos de sincronización seguidos contra la conexión de allá.
//
// Eran hasta 35 —el freno más el latido que lo soltaba— hasta que el 29/09/2026 cada
// pendiente pasó a tener su propio despertador (`despertarEn`). Sin él, cualquier número que
// se ponga en `FrenoAvisos` se redondea al alza a múltiplo de `latidoSSE`.
func TestSoloEstosTiposSeFrenan(t *testing.T) {
	// A mano y por su texto, no por las constantes: renombrar una constante y la entrada del
	// mapa a la vez dejaría esto verde, y ese texto es lo que viaja por el cable.
	frenadosEsperados := map[string]bool{"pedidos": true, "clientes": true, "canal": true}

	for tipo, motivo := range tiposFrenados {
		if !frenadosEsperados[tipo] {
			t.Errorf("«%s» se ha metido en la lista de frenados y no estaba decidido.\n"+
				"  Estar ahí significa que ese aviso puede tardar HASTA 15 SEGUNDOS en "+
				"llegar a la otra pantalla.\n"+
				"  Sólo se frena lo que entra en avalancha desde PEDIDO. Lo que se usa "+
				"para trabajar en el reparto va al momento — Jose, 29/09/2026: «deja todo "+
				"lo demas listo al momento... q se utiliza en reparto».\n"+
				"  El motivo que trae escrito es: %s", tipo, motivo)
		}
		if strings.TrimSpace(motivo) == "" {
			t.Errorf("«%s» está frenado sin decir por qué. El valor del mapa es "+
				"obligatorio: un tipo frenado sin motivo es el que nadie se atreve a "+
				"sacar dentro de seis meses", tipo)
		}
	}
	for tipo := range frenadosEsperados {
		if _, hay := tiposFrenados[tipo]; !hay {
			t.Errorf("«%s» ha SALIDO de la lista de frenados.\n"+
				"  Los tres que quedan son la manguera de PEDIDO: el lote del espejo son "+
				"doscientos pedidos por vuelta y avisa por cada uno, y hasta el 29/09/2026 "+
				"PEDIDO devolvía 2.000 pedidos por cada aviso de uno. Sin freno, cada aviso "+
				"es un ciclo de sincronización entero en el aparato: veinte ciclos seguidos "+
				"contra la conexión de Cuba.", tipo)
		}
	}
}

// Y AL REVÉS: lo que se usa para trabajar en el reparto NO se frena, uno por uno.
//
// Es la otra mitad de la de arriba y no sobra: aquélla cazaría un tipo NUEVO metido en la
// lista, y ésta caza que alguien meta en ella uno de los que ya hay. Jose los nombró:
// «pedidos y clientes si pero lo otro no q se utiliza en reparto dejalo al momento».
func TestLoDelRepartoSaleAlMomento(t *testing.T) {
	alMomento := []string{
		CambioTablero, CambioRutas, CambioVehiculos, CambioAlmacenes,
		CambioSucursales, CambioAjustes, CambioCatalogo,
	}
	d := NuevoDifusor()
	reloj := time.Date(2026, 9, 29, 21, 0, 0, 0, time.UTC)
	d.ahora = func() time.Time { return reloj }

	for _, tipo := range alMomento {
		if freno := d.frenoDe(tipo); freno != 0 {
			t.Errorf("«%s» tiene un freno de %s y tenía que salir al momento.\n"+
				"  Es una pantalla de trabajo del reparto: dos personas la miran a la vez, "+
				"una desde el teléfono y otra desde el navegador, y lo que hace una tiene "+
				"que aparecerle a la otra en el acto.", tipo, freno)
		}
		// Y de verdad, no sólo en la cuenta: dos seguidos sin mover el reloj.
		if !d.Avisar(tipo, nil) || !d.Avisar(tipo, nil) {
			t.Errorf("dos avisos seguidos de «%s» y el segundo no salió", tipo)
		}
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

// Cada tipo lleva su propio pendiente: un cambio de clientes no se come el de pedidos.
//
// VA CON LOS DOS TIPOS FRENADOS y no con `tablero`, que era como estaba: desde el
// 29/09/2026 `tablero` sale al momento y nunca se queda pendiente, así que escrito con él
// esta prueba pasaría comprobando la mitad (`tiposFrenados`).
func TestCadaTipoGuardaSuPendiente(t *testing.T) {
	reloj := time.Date(2026, 9, 17, 10, 0, 0, 0, time.UTC)
	d := NuevoDifusor()
	d.ahora = func() time.Time { return reloj }
	sinDespertadores(d)

	canal, cortar, _ := d.Suscribir()
	defer cortar()

	d.Avisar(CambioClientes, nil)
	d.Avisar(CambioPedidos, nil)
	recibir(t, canal)
	recibir(t, canal)

	// Los dos, dentro del freno.
	reloj = reloj.Add(2 * time.Second)
	d.Avisar(CambioClientes, map[string]any{"cual": "clientes"})
	d.Avisar(CambioPedidos, map[string]any{"cual": "pedidos"})

	reloj = reloj.Add(20 * time.Second)
	d.SoltarPendientes()

	vistos := map[string]bool{}
	for i := 0; i < 2; i++ {
		c := recibir(t, canal)
		vistos[c.Tipo] = true
	}
	if !vistos[CambioClientes] || !vistos[CambioPedidos] {
		t.Errorf("se perdió uno de los dos: %v", vistos)
	}
}

// sinDespertadores apaga los `time.AfterFunc` de un bus con el reloj a mano.
//
// NO ES COSMÉTICO. Un despertador de verdad armado sobre un reloj falso salta quince
// segundos después, cuando esta prueba ya terminó, y lee la variable `reloj` del cuerpo sin
// ninguna sincronización: eso es una carrera que `-race` marca, y el fallo sale con el
// nombre de OTRA prueba. Lo que estas pruebas comprueban es la aritmética del freno, y para
// eso llaman a `SoltarPendientes` a mano.
//
// Que el despertador funciona de verdad lo prueba `TestElPendienteSaleSoloSinEsperarAlLatido`,
// que va con el reloj del sistema.
func sinDespertadores(d *Difusor) { d.alVencer = nil }

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

// siHayCambio saca lo que ya esté en el canal, sin esperar. Para contar cuántos avisos
// salieron de verdad en vez de sólo mirar si salió alguno.
func siHayCambio(canal <-chan Cambio) (Cambio, bool) {
	select {
	case c := <-canal:
		return c, true
	default:
		return Cambio{}, false
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
