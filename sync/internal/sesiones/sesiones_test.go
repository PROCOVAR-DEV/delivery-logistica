package sesiones

// Las pruebas del empuje de Accesos en el sincronizador: gemelas de `api/internal/sesiones`, con lo
// que sólo toca a la APK (la marca `todo`). Van contra una fuente FALSA y no contra un Redis, para
// correr en cada compilación. La conexión real se ejercita aparte, con un Redis de verdad, en
// `redis_real_test.go` (sólo si se pide).

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// ------------------------------------------------------------------ la fuente falsa

type fuenteFalsa struct {
	mu sync.Mutex
	// marcas[n] es lo que devuelve el n-ésimo SCAN (el último se repite): las marcas `todo`.
	marcas []map[string]int64
	// marcasWeb[n], igual, para la familia `web` (vacía si no se pone).
	marcasWeb []map[string]int64
	// falloAlSuscribir: las primeras N suscripciones fallan (Redis caído).
	falloAlSuscribir int
	errMarcas        error

	suscripciones      int
	llamadasMarcas     int
	cerrada            atomic.Bool
	vivas              []*suscripcionFalsa
	nuevaSuscripcion   chan *suscripcionFalsa
	suscripcionesVivas atomic.Int32
}

func nuevaFuente(m ...map[string]int64) *fuenteFalsa {
	return &fuenteFalsa{marcas: m, nuevaSuscripcion: make(chan *suscripcionFalsa, 32)}
}

func (f *fuenteFalsa) Suscribir(ctx context.Context) (Suscripcion, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.suscripciones++
	if f.suscripciones <= f.falloAlSuscribir {
		return nil, errors.New("connection refused")
	}
	s := &suscripcionFalsa{msgs: make(chan string, 16), muerta: make(chan struct{}), duena: f}
	f.suscripcionesVivas.Add(1)
	f.vivas = append(f.vivas, s)
	f.nuevaSuscripcion <- s
	return s, nil
}

func (f *fuenteFalsa) Marcas(context.Context) (Marcas, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.llamadasMarcas++
	if f.errMarcas != nil {
		return Marcas{}, f.errMarcas
	}
	var m Marcas
	if len(f.marcas) > 0 {
		m.Todo = f.marcas[min(f.llamadasMarcas-1, len(f.marcas)-1)]
	}
	if len(f.marcasWeb) > 0 {
		m.Web = f.marcasWeb[min(f.llamadasMarcas-1, len(f.marcasWeb)-1)]
	}
	return m, nil
}

func (f *fuenteFalsa) Cerrar() error { f.cerrada.Store(true); return nil }

func (f *fuenteFalsa) contadores() (suscripciones, scans int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.suscripciones, f.llamadasMarcas
}

type suscripcionFalsa struct {
	msgs   chan string
	muerta chan struct{}
	once   sync.Once
	duena  *fuenteFalsa
}

func (s *suscripcionFalsa) Siguiente(ctx context.Context) (string, error) {
	select {
	case m := <-s.msgs:
		return m, nil
	case <-s.muerta:
		return "", errors.New("use of closed network connection")
	case <-ctx.Done():
		return "", ctx.Err()
	}
}

func (s *suscripcionFalsa) Cerrar() error {
	s.once.Do(func() { s.duena.suscripcionesVivas.Add(-1) })
	return nil
}

func (s *suscripcionFalsa) publicar(m string) { s.msgs <- m }
func (s *suscripcionFalsa) matar()            { close(s.muerta) }

// ------------------------------------------------------------------ ayudantes

// arrancar lanza el bucle con tiempos de pruebas y, al terminar la prueba, lo para y EXIGE que
// vuelva: un bucle que no sale al cancelar es la gorutina colgada que este paquete no puede dejar.
func arrancar(t *testing.T, f Fuente) (*Registro, *bufferSeguro, context.CancelFunc, <-chan struct{}) {
	t.Helper()
	salida := &bufferSeguro{}
	log := slog.New(slog.NewTextHandler(salida, &slog.HandlerOptions{Level: slog.LevelDebug}))
	r := Nuevo(f, log)
	r.esperaMin, r.esperaMax, r.cadaLimpiar = 5*time.Millisecond, 20*time.Millisecond, time.Hour
	ctx, cancelar := context.WithCancel(context.Background())
	hecho := make(chan struct{})
	go func() { defer close(hecho); r.Correr(ctx) }()
	t.Cleanup(func() {
		cancelar()
		select {
		case <-hecho:
		case <-time.After(2 * time.Second):
			t.Error("Correr no volvió al cancelar el contexto: queda una gorutina colgada")
		}
	})
	return r, salida, cancelar, hecho
}

// bufferSeguro: el registro se escribe desde la gorutina del bucle y se lee desde la prueba.
type bufferSeguro struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (s *bufferSeguro) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.Write(p)
}

func (s *bufferSeguro) String() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.String()
}

func esperarA(t *testing.T, cond func() bool, msg string) {
	t.Helper()
	limite := time.Now().Add(2 * time.Second)
	for !cond() {
		if time.Now().After(limite) {
			t.Fatal(msg)
		}
		time.Sleep(2 * time.Millisecond)
	}
}

func esperarSuscripcion(t *testing.T, f *fuenteFalsa) *suscripcionFalsa {
	t.Helper()
	select {
	case s := <-f.nuevaSuscripcion:
		return s
	case <-time.After(2 * time.Second):
		t.Fatal("no se abrió la suscripción")
		return nil
	}
}

func mensaje(alcance, tipo string, tms int64, ids ...string) string {
	lista := `"` + strings.Join(ids, `","`) + `"`
	if len(ids) == 0 {
		lista = ""
	}
	a := ""
	if alcance != "" {
		a = `"alcance":"` + alcance + `",`
	}
	return `{"v":1,"tipo":"` + tipo + `",` + a + `"userIds":[` + lista + `],"tms":` + strconv.FormatInt(tms, 10) + `,"motivo":"prueba"}`
}

// ------------------------------------------------------------------ la regla, pura

// LA REGLA DEL BEARER: sólo cuenta `todo` —un `web` NO le llega— y se compara contra el `iatms` del
// token (milisegundos) o, si no lo trae, contra `iat*1000` (por arriba, o sea conservador).
//
// GEMELA de `TestLaReglaDelBearerSoloMiraLaMarcaTodo` en `reparto-api`: los MISMOS casos en los
// dos módulos. Si se cambia uno, se cambia el otro.
func TestLaReglaDelBearerSoloMiraLaMarcaTodo(t *testing.T) {
	casos := []struct {
		nombre             string
		todo, iatSg, iatMs int64
		invalida           bool
	}{
		// Sin `iatms`: cae a iat*1000.
		{"sin marca todo", 0, 1000, 0, false},
		{"marca todo posterior", 1_500_000, 1000, 0, true},
		{"token posterior a la marca", 1_500_000, 1501, 0, false},
		{"sin iatms, mismo segundo que la marca: invalida (conservador)", 1_000_500, 1000, 0, true},
		{"sin iatms, el segundo siguiente: ya no", 1_000_500, 1001, 0, false},
		{"token sin iat ni iatms y una marca todo", 1_000_500, 0, 0, true},
		{"token sin iat ni iatms y sin marca", 0, 0, 0, false},
		// Con `iatms`: manda él.
		{"iatms 250 ms DESPUÉS de la marca no rebota (iat*1000 lo habría invalidado)", 1_000_100, 1000, 1_000_350, false},
		{"iatms ANTES de la marca invalida", 1_000_100, 1000, 1_000_050, true},
		{"iatms en el mismo milisegundo que la marca: invalida (conservador)", 1_000_100, 1000, 1_000_100, true},
		{"iatms manda aunque iat diga otra cosa", 1_000_100, 5000, 1_000_350, false},
		{"iatms y sin marca", 0, 1000, 1_000_350, false},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			if got := invalidaAlBearer(c.todo, c.iatSg, c.iatMs); got != c.invalida {
				t.Errorf("invalidaAlBearer(todo=%d, iat=%ds, iatms=%d) = %v, se esperaba %v",
					c.todo, c.iatSg, c.iatMs, got, c.invalida)
			}
		})
	}
}

// UN EVENTO `web` NO INVALIDA AL BEARER; UNO `todo`, SÍ. Si se mezclan, un cierre de sesión en el
// navegador echaría al teléfono (y sus 15 minutos de cola con él).
func TestUnEventoWebNoTocaAlBearerYUnoTodoSi(t *testing.T) {
	r := Nuevo(nil, slog.New(slog.NewTextHandler(&bytes.Buffer{}, nil)))
	r.Aplicar(mensaje("web", tipoSesionCerrada, 5_000_000, "soloweb"))
	r.Aplicar(mensaje("todo", tipoPermisosCambiados, 5_000_000, "todo"))

	if r.ElBearerNoVale("soloweb", 1000, 0) {
		t.Error("un evento `web` invalidó al bearer: cerrar sesión en el navegador echaría al teléfono")
	}
	if !r.ElBearerNoVale("todo", 1000, 0) {
		t.Error("un evento `todo` no invalidó al bearer")
	}
}

func TestSinAlcanceSeLeeComoTodo(t *testing.T) {
	r := Nuevo(nil, slog.New(slog.NewTextHandler(&bytes.Buffer{}, nil)))
	r.Aplicar(mensaje("", tipoSesionCerrada, 9000, "u1"))
	if !r.ElBearerNoVale("u1", 1, 0) {
		t.Error("un mensaje sin alcance se tenía que leer como `todo` (fallar cerrado), no ignorarse")
	}
}

// ------------------------------------------------------------------ el arranque y los mensajes

func TestAlArrancarCargaLasMarcasConScan(t *testing.T) {
	f := nuevaFuente(map[string]int64{"beto": 2_000_000})
	r, _, _, _ := arrancar(t, f)
	esperarA(t, r.Activo, "el empuje no se activó")

	if !r.ElBearerNoVale("beto", 1000, 0) || r.ElBearerNoVale("beto", 2001, 0) {
		t.Error("la marca todo de Beto no se cargó con su tms")
	}
	if r.ElBearerNoVale("nadie", 0, 0) {
		t.Error("una persona sin marca salió invalidada")
	}
	if _, scans := f.contadores(); scans != 1 {
		t.Errorf("hubo %d SCAN al arrancar, se esperaba 1", scans)
	}
}

func TestUnMensajeActualizaElMapa(t *testing.T) {
	f := nuevaFuente()
	r, _, _, _ := arrancar(t, f)
	sus := esperarSuscripcion(t, f)

	sus.publicar(mensaje("todo", tipoPermisosCambiados, 9_000_000, "u1", "u2"))

	esperarA(t, func() bool { return r.ElBearerNoVale("u2", 8999, 0) }, "el mensaje no llegó al mapa")
	if !r.ElBearerNoVale("u1", 8999, 0) {
		t.Error("la primera persona del mensaje no quedó marcada")
	}
}

func TestSeQuedaConElTmsMayor(t *testing.T) {
	r := Nuevo(nil, slog.New(slog.NewTextHandler(&bytes.Buffer{}, nil)))
	r.Aplicar(mensaje("todo", tipoSesionCerrada, 9_000_000, "u1"))
	r.Aplicar(mensaje("todo", tipoSesionCerrada, 5_000_000, "u1")) // atrasado
	if !r.ElBearerNoVale("u1", 8500, 0) {
		t.Error("un mensaje atrasado rebajó la marca: el token de 8500 s volvió a valer")
	}
	// Y la carga con SCAN tampoco rebaja lo que ya se supo por el canal.
	r.fusionar(Marcas{Todo: map[string]int64{"u1": 100}})
	if !r.ElBearerNoVale("u1", 8500, 0) {
		t.Error("el SCAN rebajó una marca más nueva que ya estaba en memoria")
	}
}

// LO QUE NO SE ENTIENDE SE IGNORA CON UN WARN Y NO PARA EL BUCLE: el siguiente mensaje bueno entra.
func TestLosMensajesQueNoSeEntiendenSeIgnoranSinRomperNada(t *testing.T) {
	f := nuevaFuente()
	r, salida, _, _ := arrancar(t, f)
	sus := esperarSuscripcion(t, f)

	malos := []struct{ nombre, mensaje string }{
		{"JSON roto", `{"v":1,"tipo":"sesion-cerrada","userIds":["u1"`},
		{"no es ni objeto", `42`},
		{"v desconocida", `{"v":2,"tipo":"sesion-cerrada","alcance":"todo","userIds":["u1"],"tms":5000}`},
		{"sin v", `{"tipo":"sesion-cerrada","alcance":"todo","userIds":["u1"],"tms":5000}`},
		{"tipo desconocido", `{"v":1,"tipo":"fin-del-mundo","alcance":"todo","userIds":["u1"],"tms":5000}`},
		{"alcance desconocido", `{"v":1,"tipo":"sesion-cerrada","alcance":"galaxia","userIds":["u1"],"tms":5000}`},
		{"sin tms", `{"v":1,"tipo":"sesion-cerrada","alcance":"todo","userIds":["u1"]}`},
		{"tms texto", `{"v":1,"tipo":"sesion-cerrada","alcance":"todo","userIds":["u1"],"tms":"ayer"}`},
		{"sin personas", `{"v":1,"tipo":"sesion-cerrada","alcance":"todo","userIds":[],"tms":5000}`},
	}
	for _, m := range malos {
		sus.publicar(m.mensaje)
	}
	sus.publicar(mensaje("todo", tipoSesionCerrada, 7_000_000, "bueno"))

	esperarA(t, func() bool { return r.ElBearerNoVale("bueno", 6000, 0) },
		"un mensaje malo paró el bucle: el bueno que venía detrás no entró")
	if r.ElBearerNoVale("u1", 1, 0) {
		t.Error("algún mensaje malo marcó a u1")
	}
	if avisos := strings.Count(salida.String(), "level=WARN"); avisos < len(malos) {
		t.Errorf("hay %d WARN para %d mensajes malos: se ignoraron en silencio", avisos, len(malos))
	}
}

// ------------------------------------------------------------------ Redis caído, sin configurar, reconexión

func TestSinRedisConfiguradoNoImpideArrancarNiServir(t *testing.T) {
	_, salida, _, hecho := arrancar(t, nil)
	select {
	case <-hecho:
	case <-time.After(time.Second):
		t.Fatal("sin Redis, Correr se quedó esperando: tenía que avisar y volver")
	}
	r := Nuevo(nil, nil)
	if r.ElBearerNoVale("cualquiera", 0, 0) || r.Activo() {
		t.Error("sin Redis nadie puede salir invalidado ni el empuje activo")
	}
	if !strings.Contains(salida.String(), "level=WARN") || !strings.Contains(salida.String(), "sin Redis configurado") {
		t.Errorf("sin Redis no se dijo claro al arrancar:\n%s", salida.String())
	}
}

func TestConRedisCaidoElSincronizadorSigueSirviendoYReintenta(t *testing.T) {
	f := nuevaFuente()
	f.falloAlSuscribir = 1 << 30 // nunca contesta
	r, salida, _, _ := arrancar(t, f)

	esperarA(t, func() bool { s, _ := f.contadores(); return s >= 3 }, "no reintentó la suscripción")
	if r.Activo() {
		t.Error("con Redis caído el empuje figura activo")
	}
	if r.ElBearerNoVale("u1", 0, 0) {
		t.Error("con Redis caído salió alguien invalidado")
	}
	if !strings.Contains(salida.String(), "se perdió el empuje de Accesos") {
		t.Errorf("la caída no se dijo en el registro:\n%s", salida.String())
	}
}

// AL RECONECTAR VUELVE A CARGAR LAS MARCAS: lo que se publicó mientras no se oía está en la DB 6.
func TestAlReconectarRecargaLasMarcas(t *testing.T) {
	f := nuevaFuente(
		map[string]int64{"a": 100_000},                   // al arrancar
		map[string]int64{"a": 100_000, "b": 300_000_000}, // tras la caída: "b" salió mientras no se oía
	)
	r, _, _, _ := arrancar(t, f)
	primera := esperarSuscripcion(t, f)
	esperarA(t, func() bool { return r.ElBearerNoVale("a", 50, 0) }, "no cargó las marcas al arrancar")
	if r.ElBearerNoVale("b", 0, 0) {
		t.Fatal("b ya estaba marcada antes de la caída")
	}

	primera.matar() // la conexión se cae
	esperarSuscripcion(t, f)
	esperarA(t, func() bool { return r.ElBearerNoVale("b", 250_000, 0) },
		"tras reconectar no se recargaron las marcas: lo publicado mientras no se oía se perdió")
	if _, scans := f.contadores(); scans != 2 {
		t.Errorf("hubo %d SCAN, se esperaban 2 (arranque y reconexión)", scans)
	}
}

// Un SCAN que falla NO es motivo para no oír el canal.
func TestUnScanQueFallaNoImpideOirElCanal(t *testing.T) {
	f := nuevaFuente()
	f.errMarcas = errors.New("NOPERM")
	r, salida, _, _ := arrancar(t, f)
	sus := esperarSuscripcion(t, f)
	sus.publicar(mensaje("todo", tipoSesionCerrada, 4_000_000, "u1"))
	esperarA(t, func() bool { return r.ElBearerNoVale("u1", 3000, 0) }, "sin SCAN tampoco se oyó el canal")
	if !strings.Contains(salida.String(), "no pude cargar las marcas") {
		t.Error("el SCAN fallido no se dijo")
	}
}

// LA COMPROBACIÓN NO SALE POR LA RED. Es lo que se llama en cada petición de la bajada y de la
// subida: si cada una abriera un viaje a Redis, el sincronizador dependería de Redis en cada llamada.
func TestLaComprobacionNoLlamaALaRed(t *testing.T) {
	f := nuevaFuente(map[string]int64{"a": 100_000})
	r, _, _, _ := arrancar(t, f)
	esperarA(t, r.Activo, "el empuje no se activó")
	s0, m0 := f.contadores()

	for i := 0; i < 1000; i++ {
		r.ElBearerNoVale("a", int64(i), 0)
	}
	if s1, m1 := f.contadores(); s1 != s0 || m1 != m0 {
		t.Errorf("1000 comprobaciones hicieron %d suscripciones y %d SCAN de más: la petición sale a la red",
			s1-s0, m1-m0)
	}
}

func TestLaLimpiezaOlvidaLasMarcasDeMasDeOchoDias(t *testing.T) {
	r := Nuevo(nil, slog.New(slog.NewTextHandler(&bytes.Buffer{}, nil)))
	ahora := time.Date(2026, 10, 20, 12, 0, 0, 0, time.UTC)
	r.ahora = func() time.Time { return ahora }
	vieja := ahora.Add(-VidaDeUnaMarca - time.Hour).UnixMilli()
	reciente := ahora.Add(-VidaDeUnaMarca + time.Hour).UnixMilli()
	r.fusionar(Marcas{Todo: map[string]int64{"vieja": vieja, "reciente": reciente}})

	if n := r.limpiar(); n != 1 {
		t.Errorf("la limpieza quitó %d marcas, se esperaba 1", n)
	}
	if r.ElBearerNoVale("vieja", 0, 0) {
		t.Error("una marca de más de ocho días sigue en memoria")
	}
	if !r.ElBearerNoVale("reciente", 0, 0) {
		t.Error("la limpieza se llevó una marca que todavía vale")
	}
}

// Cancelar el contexto saca al bucle aunque esté bloqueado leyendo, y suelta la fuente.
func TestCancelarElContextoNoDejaNadaColgado(t *testing.T) {
	f := nuevaFuente()
	_, _, cancelar, hecho := arrancar(t, f)
	esperarSuscripcion(t, f) // ya está bloqueado en Siguiente

	cancelar()
	select {
	case <-hecho:
	case <-time.After(time.Second):
		t.Fatal("Correr no volvió tras cancelar el contexto")
	}
	if !f.cerrada.Load() {
		t.Error("la fuente no se cerró al terminar")
	}
	if v := f.suscripcionesVivas.Load(); v != 0 {
		t.Errorf("quedan %d suscripciones abiertas", v)
	}
}

// ------------------------------------------------------------------ los topes (auditoría, 08/10/2026)
//
// El Redis lo comparte toda la casa con una clave común: lo que llegue por el canal o por las marcas
// NO es de fiar. GEMELAS de las de `reparto-api`.

func registroConReloj(ahora time.Time) (*Registro, *bufferSeguro) {
	salida := &bufferSeguro{}
	r := Nuevo(nil, slog.New(slog.NewTextHandler(salida, nil)))
	r.ahora = func() time.Time { return ahora }
	return r, salida
}

func TestUnTmsEnElFuturoSeIgnoraYNoBloqueaANadie(t *testing.T) {
	ahora := time.Date(2026, 10, 8, 12, 0, 0, 0, time.UTC)
	r, salida := registroConReloj(ahora)

	for _, tms := range []int64{
		4102444800000, // el 01/01/2100
		ahora.Add(margenDelFuturo + time.Second).UnixMilli(),
		ahora.Add(24 * time.Hour).UnixMilli(),
	} {
		r.Aplicar(mensaje("todo", tipoSesionCerrada, tms, "u-futuro"))
	}
	// El token que se emite AHORA sigue valiendo: ése es el daño que se evita.
	if r.ElBearerNoVale("u-futuro", 0, ahora.UnixMilli()) {
		t.Error("un tms en el futuro dejó bloqueada a una persona: nada de lo que emita desde ahora vale")
	}
	if !strings.Contains(salida.String(), "en el futuro") {
		t.Error("no se dejó constancia en el registro")
	}
	// Dentro del margen sí se acepta.
	r.Aplicar(mensaje("todo", tipoSesionCerrada, ahora.Add(30*time.Second).UnixMilli(), "u-margen"))
	if !r.ElBearerNoVale("u-margen", 0, ahora.UnixMilli()) {
		t.Error("un tms 30 s por delante (dentro del margen) se descartó")
	}
}

func TestLasMarcasDelFuturoQueTraeElScanSeIgnoran(t *testing.T) {
	ahora := time.Date(2026, 10, 8, 12, 0, 0, 0, time.UTC)
	r, salida := registroConReloj(ahora)
	r.fusionar(Marcas{Todo: map[string]int64{"futura": 4102444800000, "buena": ahora.Add(-time.Hour).UnixMilli()}})

	if r.ElBearerNoVale("futura", 0, ahora.UnixMilli()) {
		t.Error("una marca del futuro cargada con SCAN bloquea a su persona")
	}
	if !r.ElBearerNoVale("buena", 0, ahora.Add(-2*time.Hour).UnixMilli()) {
		t.Error("la marca buena del mismo SCAN se perdió")
	}
	if !strings.Contains(salida.String(), "en el futuro") {
		t.Error("el SCAN con marcas del futuro no lo dijo")
	}
}

func TestUnMensajeSoloLeeLosPrimerosIds(t *testing.T) {
	r, salida := registroConReloj(time.Now())
	ids := make([]string, 0, maxIdsPorMensaje+500)
	for i := 0; i < maxIdsPorMensaje+500; i++ {
		ids = append(ids, "u"+strconv.Itoa(i))
	}
	r.Aplicar(mensaje("todo", tipoSesionCerrada, 5000, ids...))

	if !r.ElBearerNoVale("u0", 0, 1) || !r.ElBearerNoVale("u"+strconv.Itoa(maxIdsPorMensaje-1), 0, 1) {
		t.Error("los primeros ids del mensaje tenían que entrar")
	}
	if r.ElBearerNoVale("u"+strconv.Itoa(maxIdsPorMensaje), 0, 1) {
		t.Error("un id por encima del tope entró")
	}
	if !strings.Contains(salida.String(), "demasiadas personas") {
		t.Error("el recorte no se dijo")
	}
}

// EL MAPA TIENE TOPE, y al pasarse se van las MÁS VIEJAS: las recientes no se tocan nunca.
func TestElMapaTieneTopeYDescartaLasMasViejas(t *testing.T) {
	original := maxMarcas
	maxMarcas = 10
	defer func() { maxMarcas = original }()

	r, _ := registroConReloj(time.Now())
	for i := 1; i <= 25; i++ {
		r.Aplicar(mensaje("todo", tipoSesionCerrada, int64(1000*i), "p"+strconv.Itoa(i)))
	}
	if n := r.NumMarcas(); n > maxMarcas {
		t.Fatalf("el mapa tiene %d marcas y el tope es %d", n, maxMarcas)
	}
	for i := 25; i > 25-maxMarcas/2; i-- {
		if !r.ElBearerNoVale("p"+strconv.Itoa(i), 0, 1) {
			t.Errorf("se descartó la marca reciente de p%d", i)
		}
	}
	if r.ElBearerNoVale("p1", 0, 1) || r.ElBearerNoVale("p2", 0, 1) {
		t.Error("las más viejas siguen en el mapa y estorban a las nuevas")
	}
}

func TestUnTorrenteDeMensajesNoHaceCrecerElMapaSinLimite(t *testing.T) {
	original := maxMarcas
	maxMarcas = 500
	defer func() { maxMarcas = original }()

	r, _ := registroConReloj(time.Now())
	for m := 0; m < 40; m++ {
		ids := make([]string, 0, 1000)
		for i := 0; i < 1000; i++ {
			ids = append(ids, "m"+strconv.Itoa(m)+"-"+strconv.Itoa(i))
		}
		r.Aplicar(mensaje("todo", tipoSesionCerrada, int64(1000+m), ids...))
	}
	if n := r.NumMarcas(); n > maxMarcas {
		t.Errorf("40.000 ids dejaron %d marcas en memoria, el tope es %d", n, maxMarcas)
	}
}

// LIMPIAR TAMBIÉN REBAJA: una marca que se coló por delante del reloj se deja en "ahora".
func TestLimpiarRebajaLasMarcasQueQuedaronPorDelanteDelReloj(t *testing.T) {
	ahora := time.Date(2026, 10, 8, 12, 0, 0, 0, time.UTC)
	r, _ := registroConReloj(ahora)
	r.todo["u1"] = ahora.Add(2 * time.Hour).UnixMilli()

	r.limpiar()

	if r.ElBearerNoVale("u1", 0, ahora.Add(time.Second).UnixMilli()) {
		t.Error("tras limpiar, un token emitido DESPUÉS de ahora sigue bloqueado")
	}
	if !r.ElBearerNoVale("u1", 0, ahora.Add(-time.Minute).UnixMilli()) {
		t.Error("al rebajar, la marca dejó de cortar lo emitido antes de ahora")
	}
}

func TestUnMensajeEnormeNoParaNada(t *testing.T) {
	r, _ := registroConReloj(time.Now())
	r.Aplicar(`{"v":1,"tipo":"sesion-cerrada","alcance":"todo","userIds":["u1"],"tms":5000,"motivo":"` +
		strings.Repeat("x", 4<<20) + `"}`)
	if !r.ElBearerNoVale("u1", 0, 1) {
		t.Error("un mensaje válido con un motivo enorme tenía que entrar")
	}
	r.Aplicar(`{"v":1,"tipo":"sesion-cerrada","alcance":"todo","userIds":[` + strings.Repeat(`"x",`, 200_000) + `"y"],"tms":6000}`)
	if n := r.NumMarcas(); n > 1+maxIdsPorMensaje {
		t.Errorf("200.000 ids dejaron %d marcas", n)
	}
	r.Aplicar(strings.Repeat("{", 1<<20))
}

// ------------------------------------------------------------------ la familia `web` (SERIO 2, 09/10/2026)

// La regla de un token de SESIÓN WEB (`web:true`), gemela de `invalidaALaCookie` de `reparto-api`: vale
// max(web, todo) contra el instante en que se emitió.
func TestInvalidaALaCookie(t *testing.T) {
	casos := []struct {
		nombre           string
		web, todo, iatMs int64
		invalida         bool
	}{
		{"sin marcas", 0, 0, 1000, false},
		{"marca web posterior", 2000, 0, 1000, true},
		{"marca todo posterior", 0, 2000, 1000, true},
		{"gana la mayor de las dos", 500, 2000, 1000, true},
		{"las dos anteriores al token", 500, 800, 1000, false},
		{"el mismo instante invalida", 1000, 0, 1000, true},
		{"token nuevo, después del cierre", 1000, 0, 1001, false},
		{"sin iatms cualquier marca lo invalida", 5, 0, 0, true},
		{"sin marcas y sin iatms no invalida", 0, 0, 0, false},
	}
	for _, c := range casos {
		if got := invalidaALaCookie(c.web, c.todo, c.iatMs); got != c.invalida {
			t.Errorf("%s: invalidaALaCookie(web=%d, todo=%d, iatms=%d) = %v, se esperaba %v", c.nombre, c.web, c.todo, c.iatMs, got, c.invalida)
		}
	}
}

// UN CIERRE DE SESIÓN SOLO-WEB corta al token de la web (el de `/api/me` que la bandeja web manda de Bearer) y
// NO a la APK; uno `todo` corta a los dos; el token que la web pidió DESPUÉS del cierre vale.
func TestUnCierreSoloWebCortaAlTokenWebYNoAlBearerDeLaAPK(t *testing.T) {
	r := Nuevo(nil, slog.New(slog.NewTextHandler(&bytes.Buffer{}, nil)))
	r.Aplicar(mensaje("web", tipoSesionCerrada, 5_000_000, "soloweb"))
	r.Aplicar(mensaje("todo", tipoPermisosCambiados, 5_000_000, "todo"))

	if !r.LaCookieNoVale("soloweb", 4_000_000) {
		t.Error("EL CIERRE DE SESIÓN SOLO-WEB NO CORTÓ AL TOKEN WEB: la bandeja web seguiría abierta siete días")
	}
	if r.LaCookieNoVale("soloweb", 5_000_001) {
		t.Error("el token que la web pidió DESPUÉS del cierre no puede salir cortado")
	}
	if r.ElBearerNoVale("soloweb", 4000, 0) {
		t.Error("un cierre solo-web echó al bearer de la APK")
	}
	if !r.LaCookieNoVale("todo", 4_000_000) || !r.ElBearerNoVale("todo", 4000, 0) {
		t.Error("un evento `todo` tenía que cortar al token web y al de la APK")
	}
	if r.LaCookieNoVale("nadie", 0) {
		t.Error("una persona sin marcas salió cortada")
	}
	if r.NumMarcas() != 2 {
		t.Errorf("marcas en memoria: %d (una web y una todo)", r.NumMarcas())
	}
}

// El SCAN carga las DOS familias, también al reconectar: un cierre solo-web ocurrido mientras el sincronizador
// estaba sin Redis tiene que cortar igual al volver.
func TestElScanCargaLaFamiliaWebAlArrancarYAlReconectar(t *testing.T) {
	f := nuevaFuente(map[string]int64{"beto": 2_000_000})
	f.marcasWeb = []map[string]int64{{"ana": 3_000_000}, {"ana": 3_000_000, "carla": 4_000_000}}
	r, _, _, _ := arrancar(t, f)
	sus := esperarSuscripcion(t, f)
	esperarA(t, r.Activo, "el empuje no se activó")

	if !r.LaCookieNoVale("ana", 2_999_999) || r.LaCookieNoVale("ana", 3_000_001) {
		t.Error("la marca WEB de Ana no se cargó con el SCAN")
	}
	if r.ElBearerNoVale("ana", 1000, 0) {
		t.Error("una marca web cargada con el SCAN cortó al bearer de la APK")
	}
	if !r.ElBearerNoVale("beto", 1000, 0) {
		t.Error("la marca todo de Beto no se cargó")
	}
	// Se cae la conexión y, al volver, el SCAN trae un cierre solo-web nuevo (el de Carla).
	sus.matar()
	esperarA(t, func() bool { return r.LaCookieNoVale("carla", 3_999_999) }, "tras reconectar no se recargó la familia web")
}

// La limpieza toca las DOS familias: olvida las marcas web de más de ocho días y rebaja las que quedaron por
// delante del reloj, igual que las `todo`.
func TestLaLimpiezaTocaTambienLasMarcasWeb(t *testing.T) {
	r := Nuevo(nil, slog.New(slog.NewTextHandler(&bytes.Buffer{}, nil)))
	ahora := time.Date(2026, 10, 20, 12, 0, 0, 0, time.UTC)
	r.ahora = func() time.Time { return ahora }
	vieja := ahora.Add(-VidaDeUnaMarca - time.Hour).UnixMilli()
	reciente := ahora.Add(-VidaDeUnaMarca + time.Hour).UnixMilli()
	r.fusionar(Marcas{Web: map[string]int64{"vieja": vieja, "reciente": reciente}, Todo: map[string]int64{"viejaTodo": vieja}})
	r.web["futura"] = ahora.Add(2 * time.Hour).UnixMilli() // se coló con el reloj atrasado

	if n := r.limpiar(); n != 2 {
		t.Errorf("la limpieza quitó %d marcas, se esperaban 2 (la web y la todo viejas)", n)
	}
	if r.LaCookieNoVale("vieja", 0) {
		t.Error("una marca WEB de más de ocho días sigue en memoria")
	}
	if !r.LaCookieNoVale("reciente", 0) {
		t.Error("la limpieza se llevó una marca web que todavía vale")
	}
	if got := r.web["futura"]; got != ahora.UnixMilli() {
		t.Errorf("una marca web por delante del reloj tenía que rebajarse a «ahora» y está en %d", got)
	}
}
