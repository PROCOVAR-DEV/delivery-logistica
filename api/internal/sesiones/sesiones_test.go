package sesiones

// Las pruebas del empuje de Accesos. Van contra una fuente FALSA —una interfaz pequeña, igual que
// `espejo.LectorDeAvisos`— y no contra un Redis, para correr en cada compilación. La conexión
// real se ejercita aparte, con un Redis de verdad, en `redis_real_test.go` (sólo si se pide).

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
	// marcas[n] es lo que devuelve el n-ésimo SCAN (el último se repite).
	marcas []Marcas
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

func nuevaFuente(m ...Marcas) *fuenteFalsa {
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
	if len(f.marcas) == 0 {
		return Marcas{}, nil
	}
	return f.marcas[min(f.llamadasMarcas-1, len(f.marcas)-1)], nil
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
		case <-time.After(plazoDeEsperaDePruebas):
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

// plazoDeEsperaDePruebas: cuánto espera una prueba a que algo ASÍNCRONO ocurra antes de darlo por
// perdido. Solo corre cuando algo ya falló o se colgó, así que alargarlo no cuesta nada con la
// prueba en verde; con 2 s, una máquina cargada (`go test -race` con otro `go test` en paralelo)
// daba un fallo sin que el código estuviera mal (auditoría final, 09/10/2026).
const plazoDeEsperaDePruebas = 15 * time.Second

func esperarA(t *testing.T, cond func() bool, msg string) {
	t.Helper()
	limite := time.Now().Add(plazoDeEsperaDePruebas)
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
	case <-time.After(plazoDeEsperaDePruebas):
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

// ------------------------------------------------------------------ las dos reglas, puras

// LA REGLA DE LA COOKIE: max(web, todo) >= iatms. Cero es "no hay marca" y NUNCA invalida, ni
// siquiera a una cookie sin `iatms` (que vale 0): sin marca no se echa a nadie al desplegar.
func TestLaReglaDeLaCookie(t *testing.T) {
	casos := []struct {
		nombre         string
		web, todo, iat int64
		invalida       bool
	}{
		{"sin marca", 0, 0, 1000, false},
		{"sin marca y cookie vieja sin iatms", 0, 0, 0, false},
		{"marca web posterior a la cookie", 2000, 0, 1000, true},
		{"marca todo posterior a la cookie", 0, 2000, 1000, true},
		{"cookie posterior a la marca", 2000, 0, 3000, false},
		{"mismo instante: invalida (conservador)", 2000, 0, 2000, true},
		{"la mayor de las dos manda: web vieja y todo nueva", 500, 2000, 1000, true},
		{"la mayor de las dos manda: ninguna alcanza", 500, 900, 1000, false},
		{"cookie vieja sin iatms + cualquier marca web", 700, 0, 0, true},
		{"cookie vieja sin iatms + cualquier marca todo", 0, 700, 0, true},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			if got := invalidaALaCookie(c.web, c.todo, c.iat); got != c.invalida {
				t.Errorf("invalidaALaCookie(web=%d, todo=%d, iatms=%d) = %v, se esperaba %v",
					c.web, c.todo, c.iat, got, c.invalida)
			}
		})
	}
}

// LA REGLA DEL BEARER: sólo cuenta `todo` —un `web` NO le llega— y se compara contra el `iatms` del
// token (milisegundos) o, si no lo trae, contra `iat*1000` (por arriba, o sea conservador).
//
// GEMELA de `TestLaReglaDelBearerSoloMiraLaMarcaTodo` en `reparto-sync`: los MISMOS casos en los
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

// UN EVENTO `web` NO INVALIDA AL BEARER; UNO `todo`, SÍ. Si se mezclan los dos mapas, un cierre de
// sesión en el navegador echaría al teléfono (y un `todo` dejaría pasar al navegador).
func TestUnEventoWebNoTocaAlBearerYUnoTodoSi(t *testing.T) {
	r := Nuevo(nil, slog.New(slog.NewTextHandler(&bytes.Buffer{}, nil)))
	r.Aplicar(mensaje("web", TipoSesionCerrada, 5_000_000, "soloweb"))
	r.Aplicar(mensaje("todo", TipoPermisosCambiados, 5_000_000, "todo"))

	if !r.LaCookieNoVale("soloweb", 4_000_000) {
		t.Error("un evento web tenía que invalidar la cookie web")
	}
	if r.ElBearerNoVale("soloweb", 1000, 0) {
		t.Error("un evento `web` invalidó al bearer: cerrar sesión en el navegador echaría al teléfono")
	}
	if !r.LaCookieNoVale("todo", 4_000_000) {
		t.Error("un evento todo tenía que invalidar también la cookie web")
	}
	if !r.ElBearerNoVale("todo", 1000, 0) {
		t.Error("un evento `todo` no invalidó al bearer")
	}
}

// ------------------------------------------------------------------ el arranque y los mensajes

func TestAlArrancarCargaLasMarcasConScanDeLasDosFamilias(t *testing.T) {
	f := nuevaFuente(Marcas{
		Web:  map[string]int64{"ana": 100},
		Todo: map[string]int64{"beto": 200},
	})
	r, _, _, _ := arrancar(t, f)
	esperarA(t, r.Activo, "el empuje no se activó")

	if !r.LaCookieNoVale("ana", 50) || r.LaCookieNoVale("ana", 101) {
		t.Error("la marca web de Ana no se cargó con su tms")
	}
	if !r.LaCookieNoVale("beto", 50) || r.LaCookieNoVale("beto", 201) {
		t.Error("la marca todo de Beto no se cargó con su tms")
	}
	if r.LaCookieNoVale("nadie", 0) {
		t.Error("una persona sin marca salió invalidada")
	}
	// Y cada familia en SU mapa.
	if r.ElBearerNoVale("ana", 1, 0) {
		t.Error("la marca web de Ana se cargó también como `todo`")
	}
	if !r.ElBearerNoVale("beto", 0, 0) {
		t.Error("la marca todo de Beto no se cargó como `todo`")
	}
	if _, scans := f.contadores(); scans != 1 {
		t.Errorf("hubo %d SCAN al arrancar, se esperaba 1", scans)
	}
}

func TestUnMensajeActualizaElMapaYAvisaDespues(t *testing.T) {
	f := nuevaFuente()
	r, _, _, _ := arrancar(t, f)
	sus := esperarSuscripcion(t, f)

	var (
		mu       sync.Mutex
		alcanceV string
		tipo     string
		quienes  []string
		vistoAl  bool
	)
	// Se asigna antes del primer mensaje; el bucle ya corre, así que se protege la lectura.
	r.AlEvento = func(a, t2 string, ids []string) {
		mu.Lock()
		defer mu.Unlock()
		alcanceV, tipo, quienes = a, t2, ids
		// El orden importa: quien recibe el aviso y reconecta tiene que encontrar la marca YA puesta.
		vistoAl = r.LaCookieNoVale("u1", 1)
	}
	sus.publicar(mensaje("web", TipoPermisosCambiados, 9000, "u1", "u2"))

	esperarA(t, func() bool { return r.LaCookieNoVale("u2", 8999) }, "el mensaje no llegó al mapa")
	esperarA(t, func() bool { mu.Lock(); defer mu.Unlock(); return tipo != "" }, "no se avisó al difusor")
	mu.Lock()
	defer mu.Unlock()
	if alcanceV != AlcanceWeb || tipo != TipoPermisosCambiados || len(quienes) != 2 || quienes[0] != "u1" || quienes[1] != "u2" {
		t.Errorf("el aviso fue %q/%q a %v", alcanceV, tipo, quienes)
	}
	if !vistoAl {
		t.Error("se avisó ANTES de actualizar el mapa: quien reconecte no encontraría la marca")
	}
}

func TestSeQuedaConElTmsMayor(t *testing.T) {
	r := Nuevo(nil, slog.New(slog.NewTextHandler(&bytes.Buffer{}, nil)))
	r.Aplicar(mensaje("web", TipoSesionCerrada, 9000, "u1"))
	r.Aplicar(mensaje("web", TipoSesionCerrada, 5000, "u1")) // atrasado
	if !r.LaCookieNoVale("u1", 8500) {
		t.Error("un mensaje atrasado rebajó la marca: la cookie de 8500 volvió a valer")
	}
	// Y la carga con SCAN tampoco rebaja lo que ya se supo por el canal.
	r.fusionar(Marcas{Web: map[string]int64{"u1": 100}})
	if !r.LaCookieNoVale("u1", 8500) {
		t.Error("el SCAN rebajó una marca más nueva que ya estaba en memoria")
	}
}

func TestSinAlcanceSeLeeComoTodo(t *testing.T) {
	r := Nuevo(nil, slog.New(slog.NewTextHandler(&bytes.Buffer{}, nil)))
	var alcanceAvisado string
	r.AlEvento = func(a, _ string, _ []string) { alcanceAvisado = a }
	r.Aplicar(mensaje("", TipoSesionCerrada, 9000, "u1"))
	if alcanceAvisado != AlcanceTodo {
		t.Errorf("al difusor llegó el alcance %q: un mensaje sin alcance se avisa como `todo`", alcanceAvisado)
	}
	if !r.LaCookieNoVale("u1", 100) || !r.ElBearerNoVale("u1", 1, 0) {
		t.Error("un mensaje sin alcance se tenía que leer como `todo` (fallar cerrado), no ignorarse")
	}
}

// LO QUE NO SE ENTIENDE SE IGNORA CON UN WARN Y NO PARA EL BUCLE: el siguiente mensaje bueno entra.
func TestLosMensajesQueNoSeEntiendenSeIgnoranSinRomperNada(t *testing.T) {
	f := nuevaFuente()
	r, salida, _, _ := arrancar(t, f)
	sus := esperarSuscripcion(t, f)
	llamadas := atomic.Int32{}
	r.AlEvento = func(string, string, []string) { llamadas.Add(1) }

	malos := []struct{ nombre, mensaje string }{
		{"JSON roto", `{"v":1,"tipo":"sesion-cerrada","userIds":["u1"`},
		{"no es ni objeto", `42`},
		{"v desconocida", `{"v":2,"tipo":"sesion-cerrada","alcance":"web","userIds":["u1"],"tms":5000}`},
		{"sin v", `{"tipo":"sesion-cerrada","alcance":"web","userIds":["u1"],"tms":5000}`},
		{"tipo desconocido", `{"v":1,"tipo":"fin-del-mundo","alcance":"web","userIds":["u1"],"tms":5000}`},
		{"alcance desconocido", `{"v":1,"tipo":"sesion-cerrada","alcance":"galaxia","userIds":["u1"],"tms":5000}`},
		{"sin tms", `{"v":1,"tipo":"sesion-cerrada","alcance":"web","userIds":["u1"]}`},
		{"tms texto", `{"v":1,"tipo":"sesion-cerrada","alcance":"web","userIds":["u1"],"tms":"ayer"}`},
		{"sin personas", `{"v":1,"tipo":"sesion-cerrada","alcance":"web","userIds":[],"tms":5000}`},
	}
	for _, m := range malos {
		sus.publicar(m.mensaje)
	}
	sus.publicar(mensaje("web", TipoSesionCerrada, 7000, "bueno"))

	esperarA(t, func() bool { return r.LaCookieNoVale("bueno", 6000) },
		"un mensaje malo paró el bucle: el bueno que venía detrás no entró")
	if r.LaCookieNoVale("u1", 1) {
		t.Error("algún mensaje malo marcó a u1")
	}
	if n := llamadas.Load(); n != 1 {
		t.Errorf("se avisó %d veces al difusor, se esperaba 1 (sólo el bueno)", n)
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
	case <-time.After(plazoDeEsperaDePruebas):
		t.Fatal("sin Redis, Correr se quedó esperando: tenía que avisar y volver")
	}
	r := Nuevo(nil, nil)
	if r.LaCookieNoVale("cualquiera", 0) || r.ElBearerNoVale("cualquiera", 0, 0) || r.Activo() {
		t.Error("sin Redis nadie puede salir invalidado ni el empuje activo")
	}
	if !strings.Contains(salida.String(), "level=WARN") || !strings.Contains(salida.String(), "sin Redis configurado") {
		t.Errorf("sin Redis no se dijo claro al arrancar:\n%s", salida.String())
	}
}

func TestConRedisCaidoLaApiSigueSirviendoYReintenta(t *testing.T) {
	f := nuevaFuente()
	f.falloAlSuscribir = 1 << 30 // nunca contesta
	r, salida, _, _ := arrancar(t, f)

	esperarA(t, func() bool { s, _ := f.contadores(); return s >= 3 }, "no reintentó la suscripción")
	if r.Activo() {
		t.Error("con Redis caído el empuje figura activo")
	}
	if r.LaCookieNoVale("u1", 0) {
		t.Error("con Redis caído salió alguien invalidado")
	}
	if !strings.Contains(salida.String(), "se perdió el empuje de Accesos") {
		t.Errorf("la caída no se dijo en el registro:\n%s", salida.String())
	}
}

// AL RECONECTAR VUELVE A CARGAR LAS MARCAS: lo que se publicó mientras no se oía está en la DB 6.
func TestAlReconectarRecargaLasMarcas(t *testing.T) {
	f := nuevaFuente(
		Marcas{Web: map[string]int64{"a": 100}},                                   // al arrancar
		Marcas{Web: map[string]int64{"a": 100}, Todo: map[string]int64{"b": 300}}, // tras la caída: "b" salió mientras no se oía
	)
	r, _, _, _ := arrancar(t, f)
	primera := esperarSuscripcion(t, f)
	esperarA(t, func() bool { return r.LaCookieNoVale("a", 50) }, "no cargó las marcas al arrancar")
	if r.LaCookieNoVale("b", 0) {
		t.Fatal("b ya estaba marcada antes de la caída")
	}

	primera.matar() // la conexión se cae
	esperarSuscripcion(t, f)
	esperarA(t, func() bool { return r.LaCookieNoVale("b", 250) },
		"tras reconectar no se recargaron las marcas: lo publicado mientras no se oía se perdió")
	if _, scans := f.contadores(); scans != 2 {
		t.Errorf("hubo %d SCAN, se esperaban 2 (arranque y reconexión)", scans)
	}
	if !r.Activo() {
		t.Error("tras reconectar el empuje no figura activo")
	}
}

// Un SCAN que falla NO es motivo para no oír el canal.
func TestUnScanQueFallaNoImpideOirElCanal(t *testing.T) {
	f := nuevaFuente()
	f.errMarcas = errors.New("NOPERM")
	r, salida, _, _ := arrancar(t, f)
	sus := esperarSuscripcion(t, f)
	sus.publicar(mensaje("web", TipoSesionCerrada, 4000, "u1"))
	esperarA(t, func() bool { return r.LaCookieNoVale("u1", 3000) }, "sin SCAN tampoco se oyó el canal")
	if !strings.Contains(salida.String(), "no pude cargar las marcas") {
		t.Error("el SCAN fallido no se dijo")
	}
}

// LA COMPROBACIÓN NO SALE POR LA RED. Es lo que se llama en cada petición: si cada una abriera un
// viaje a Redis, la API dependería de Redis en cada llamada, que es justo lo que el mapa evita.
func TestLaComprobacionNoLlamaALaRed(t *testing.T) {
	f := nuevaFuente(Marcas{Web: map[string]int64{"a": 100}})
	r, _, _, _ := arrancar(t, f)
	esperarA(t, r.Activo, "el empuje no se activó")
	s0, m0 := f.contadores()

	for i := 0; i < 1000; i++ {
		r.LaCookieNoVale("a", int64(i))
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
	r.fusionar(Marcas{
		Web:  map[string]int64{"vieja-web": vieja, "reciente": reciente},
		Todo: map[string]int64{"vieja-todo": vieja},
	})

	if n := r.limpiar(); n != 2 {
		t.Errorf("la limpieza quitó %d marcas, se esperaban 2", n)
	}
	if r.LaCookieNoVale("vieja-web", 0) || r.LaCookieNoVale("vieja-todo", 0) {
		t.Error("una marca de más de ocho días sigue en memoria")
	}
	if !r.LaCookieNoVale("reciente", 0) {
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
	case <-time.After(plazoDeEsperaDePruebas):
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
// NO es de fiar. Un `tms` en el futuro dejaba a una persona bloqueada para siempre (cada cookie nueva
// seguía siendo "anterior") y sin forma de rebajarlo hasta reiniciar; ids o mensajes sin tope llenaban
// la memoria.

func registroConReloj(ahora time.Time) (*Registro, *bufferSeguro) {
	salida := &bufferSeguro{}
	r := Nuevo(nil, slog.New(slog.NewTextHandler(salida, nil)))
	r.ahora = func() time.Time { return ahora }
	return r, salida
}

func TestUnTmsEnElFuturoSeIgnoraYNoBloqueaANadie(t *testing.T) {
	ahora := time.Date(2026, 10, 8, 12, 0, 0, 0, time.UTC)
	r, salida := registroConReloj(ahora)
	avisos := 0
	r.AlEvento = func(string, string, []string) { avisos++ }

	futuro := []int64{
		4102444800000, // el 01/01/2100
		ahora.Add(margenDelFuturo + time.Second).UnixMilli(),
		ahora.Add(24 * time.Hour).UnixMilli(),
	}
	for _, tms := range futuro {
		r.Aplicar(mensaje("todo", TipoSesionCerrada, tms, "u-futuro"))
	}
	if avisos != 0 {
		t.Errorf("se avisó %d veces por mensajes con tms en el futuro", avisos)
	}
	// La cookie y el token que se emiten AHORA siguen valiendo: ése es el daño que se evita.
	if r.LaCookieNoVale("u-futuro", ahora.UnixMilli()) || r.ElBearerNoVale("u-futuro", 0, ahora.UnixMilli()) {
		t.Error("un tms en el futuro dejó bloqueada a una persona: nada de lo que emita desde ahora vale")
	}
	if !strings.Contains(salida.String(), "en el futuro") {
		t.Error("no se dejó constancia en el registro")
	}

	// Dentro del margen sí se acepta (relojes que no cuadran del todo entre contenedores).
	r.Aplicar(mensaje("web", TipoSesionCerrada, ahora.Add(30*time.Second).UnixMilli(), "u-margen"))
	if !r.LaCookieNoVale("u-margen", ahora.UnixMilli()) {
		t.Error("un tms 30 s por delante (dentro del margen) se descartó")
	}
}

// Lo mismo para lo que trae el SCAN: no hay dos reglas, hay una.
func TestLasMarcasDelFuturoQueTraeElScanSeIgnoran(t *testing.T) {
	ahora := time.Date(2026, 10, 8, 12, 0, 0, 0, time.UTC)
	r, salida := registroConReloj(ahora)
	r.fusionar(Marcas{
		Web:  map[string]int64{"web-futura": 4102444800000, "web-buena": ahora.Add(-time.Hour).UnixMilli()},
		Todo: map[string]int64{"todo-futura": ahora.Add(time.Hour).UnixMilli()},
	})

	if r.LaCookieNoVale("web-futura", ahora.UnixMilli()) || r.LaCookieNoVale("todo-futura", ahora.UnixMilli()) ||
		r.ElBearerNoVale("todo-futura", 0, ahora.UnixMilli()) {
		t.Error("una marca del futuro cargada con SCAN bloquea a su persona")
	}
	if !r.LaCookieNoVale("web-buena", ahora.Add(-2*time.Hour).UnixMilli()) {
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
	var avisados int
	r.AlEvento = func(_, _ string, personas []string) { avisados = len(personas) }
	r.Aplicar(mensaje("web", TipoSesionCerrada, 5000, ids...))

	if avisados != maxIdsPorMensaje {
		t.Errorf("se avisó a %d personas, el tope es %d", avisados, maxIdsPorMensaje)
	}
	if !r.LaCookieNoVale("u0", 1) || !r.LaCookieNoVale("u"+strconv.Itoa(maxIdsPorMensaje-1), 1) {
		t.Error("los primeros ids del mensaje tenían que entrar")
	}
	if r.LaCookieNoVale("u"+strconv.Itoa(maxIdsPorMensaje), 1) {
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
	// 25 personas, cada una con una marca más reciente que la anterior.
	for i := 1; i <= 25; i++ {
		r.Aplicar(mensaje("web", TipoSesionCerrada, int64(1000*i), "p"+strconv.Itoa(i)))
	}

	if n := r.NumMarcas(); n > maxMarcas {
		t.Fatalf("el mapa tiene %d marcas y el tope es %d", n, maxMarcas)
	}
	for i := 25; i > 25-maxMarcas/2; i-- { // las más recientes, a salvo
		if !r.LaCookieNoVale("p"+strconv.Itoa(i), 1) {
			t.Errorf("se descartó la marca reciente de p%d", i)
		}
	}
	if r.LaCookieNoVale("p1", 1) || r.LaCookieNoVale("p2", 1) {
		t.Error("las más viejas siguen en el mapa y estorban a las nuevas")
	}
}

// Y un torrente de mensajes y de ids no hace crecer nada sin límite.
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
		r.Aplicar(mensaje("todo", TipoSesionCerrada, int64(1000+m), ids...))
	}
	if n := r.NumMarcas(); n > maxMarcas {
		t.Errorf("40.000 ids dejaron %d marcas en memoria, el tope es %d", n, maxMarcas)
	}
}

// LIMPIAR TAMBIÉN REBAJA: una marca que se coló por delante del reloj (el nuestro iba atrasado, o
// saltó) se deja en "ahora" —sigue cortando lo anterior y no bloquea lo nuevo—.
func TestLimpiarRebajaLasMarcasQueQuedaronPorDelanteDelReloj(t *testing.T) {
	ahora := time.Date(2026, 10, 8, 12, 0, 0, 0, time.UTC)
	r, _ := registroConReloj(ahora)
	// Como si se hubiera aceptado cuando nuestro reloj iba una hora atrasado.
	r.web["u1"] = ahora.Add(time.Hour).UnixMilli()
	r.todo["u1"] = ahora.Add(2 * time.Hour).UnixMilli()

	r.limpiar()

	nueva := ahora.Add(time.Second).UnixMilli()
	if r.LaCookieNoVale("u1", nueva) || r.ElBearerNoVale("u1", 0, nueva) {
		t.Error("tras limpiar, una cookie emitida DESPUÉS de ahora sigue bloqueada")
	}
	if !r.LaCookieNoVale("u1", ahora.Add(-time.Minute).UnixMilli()) || !r.ElBearerNoVale("u1", 0, ahora.Add(-time.Minute).UnixMilli()) {
		t.Error("al rebajar, la marca dejó de cortar lo emitido antes de ahora")
	}
}

// Mensajes enormes o sin forma: no paran el bucle y no se llevan la memoria.
func TestUnMensajeEnormeNoParaNada(t *testing.T) {
	r, _ := registroConReloj(time.Now())
	enorme := `{"v":1,"tipo":"sesion-cerrada","alcance":"web","userIds":["u1"],"tms":5000,"motivo":"` +
		strings.Repeat("x", 4<<20) + `"}`
	r.Aplicar(enorme)
	if !r.LaCookieNoVale("u1", 1) {
		t.Error("un mensaje válido con un motivo enorme tenía que entrar")
	}
	r.Aplicar(`{"v":1,"tipo":"sesion-cerrada","alcance":"web","userIds":[` + strings.Repeat(`"x",`, 200_000) + `"y"],"tms":6000}`)
	if n := r.NumMarcas(); n > 1+maxIdsPorMensaje {
		t.Errorf("200.000 ids dejaron %d marcas", n)
	}
	r.Aplicar(strings.Repeat("{", 1<<20)) // sin cerrar: JSON roto
}
