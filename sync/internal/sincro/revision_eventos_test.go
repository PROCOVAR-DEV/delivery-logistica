package sincro

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"go/types"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/http/httptrace"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/httpx"
	"procovar/reparto-sync/internal/identidad"
	"procovar/reparto-sync/internal/store"
	"procovar/reparto-sync/internal/store/sqlc"
)

// EL AVISO EN VIVO DE LA REVISIÓN (`revision_eventos.go`, `avisos.go`): quien entregó su cola abre un SSE con su
// token de entrega y le llega una señal cuando un revisor decide algo suyo. Las que importan, por orden:
//
//  1. LLEGA a la persona dueña del apunte, y a NADIE MÁS; y no lleva datos.
//  2. SÓLO se abre con el token de entrega, del aparato de esa persona (los mismos códigos que `mias`).
//  3. Se avisa DESPUÉS de confirmar y nunca dentro de una transacción; un fallo del aviso no toca la respuesta al revisor.
//  4. Los topes (3 por persona, un total) y que irse el cliente lo libere TODO.
//  5. Se cierra solo al caducar el token y al apagar el servicio, y NO lo mata el `WriteTimeout` (que sigue
//     valiendo para el resto de rutas).
//
// Un SSE no se prueba con un `ResponseRecorder` (no tiene deadline ni conexión que se cierre): estas pruebas
// levantan un servidor de verdad con la misma cadena de `main` (`httpx.Recuperar` + `httpx.Registro`) y el
// `Servicio` real contra los dobles de la base (y contra Postgres si hay `SYNC_MOTOR_REAL_DSN`).

const (
	entradaDelCanal = ": abierto\n\n"
	avisoDelCanal   = "event: revision\ndata: {\"v\":1}\n\n"
)

// ---------------------------------------------------------------------------
// El servidor y el cliente de las pruebas
// ---------------------------------------------------------------------------

// servidorConFuentes monta lo que monta `main` para estas rutas: la cadena de `httpx`, `RutasDeRevision` con las
// fuentes que se le den y el registro del apagado. `plazo` > 0 pone ese `ReadTimeout` y `WriteTimeout` (en
// producción son 60 s; aquí milisegundos, para ver qué les pasa a un flujo largo y a una petición lenta).
func (e *entorno) servidorConFuentes(t *testing.T, entrega, mias identidad.Fuente, plazo time.Duration, extra ...func(*http.ServeMux)) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	e.servicio.RutasDeRevision(mux, entrega, mias)
	for _, f := range extra {
		f(mux)
	}
	srv := httptest.NewUnstartedServer(httpx.Recuperar(e.servicio.log, httpx.Registro(e.servicio.log, mux)))
	if plazo > 0 {
		srv.Config.ReadTimeout, srv.Config.WriteTimeout = plazo, plazo
	}
	srv.Config.RegisterOnShutdown(e.servicio.CerrarAvisos)
	srv.Start()
	// LIFO: los flujos (que cierran su cuerpo) se limpian ANTES que esto; `CerrarAvisos` es la red por si alguno
	// no lo hizo, porque `Close` espera a que terminen las peticiones y un SSE no termina solo.
	t.Cleanup(func() { e.servicio.CerrarAvisos(); srv.Close() })
	return srv
}

// servidorDeAvisos: las dos fuentes son «el token es el nombre de una identidad de `tokens`», como hace el
// entorno con `e.entrega`. Con ella el manejador ve identidades que la fuente real jamás le daría (un token normal,
// un Super Admin con ámbito…): lo que se prueba es que se planta POR SÍ MISMO.
func (e *entorno) servidorDeAvisos(t *testing.T, tokens map[string]identidad.Identidad, plazo time.Duration, extra ...func(*http.ServeMux)) *httptest.Server {
	t.Helper()
	fuente := fuenteDe(tokens)
	return e.servidorConFuentes(t, fuente, fuente, plazo, extra...)
}

func fuenteDe(tokens map[string]identidad.Identidad) identidad.Fuente {
	return func(r *http.Request) (identidad.Identidad, error) {
		if id, hay := tokens[strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")]; hay {
			return id, nil
		}
		return identidad.Identidad{}, identidad.ErrSinSesion
	}
}

// plazoParaAbrir: lo que se espera a que lleguen las CABECERAS de un canal. Sin plazo, un canal que no vacía el
// búfer (sin `Flush`) o no escribe nada al entrar dejaba la prueba colgada hasta el timeout de `go test`, que en el
// `Dockerfile.sync` son diez minutos: una prueba tiene que FALLAR, no esperar.
const plazoParaAbrir = 2 * time.Second

func clienteConPlazoParaAbrir(srv *httptest.Server) *http.Client {
	tr := srv.Client().Transport.(*http.Transport).Clone()
	tr.ResponseHeaderTimeout = plazoParaAbrir
	return &http.Client{Transport: tr}
}

// deEntrega: la identidad que daría el token de entrega de esa persona, que vive `vive` a partir de AHORA (el
// reloj de verdad: el canal espera a su `exp` con `time.Until`, como el verificador).
func (e *entorno) deEntrega(persona string, sucursal uuid.UUID, vive time.Duration) identidad.Identidad {
	return identidad.Identidad{Persona: persona, Nombre: "Yasmani", Sucursal: sucursal, Jti: "jti-" + uuid.NewString(),
		Ambito: identidad.AmbitoEntrega, Caduca: time.Now().Add(vive)}
}

// pedirEventos: una petición que NO tiene que abrir el canal. Con plazo, por si lo abriera.
func pedirEventos(t *testing.T, srv *httptest.Server, ruta, token, aparato string) (estado int, codigo string, cab http.Header, cuerpo string) {
	t.Helper()
	ctx, cancelar := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancelar()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, srv.URL+ruta+aparato, nil)
	if err != nil {
		t.Fatal(err)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := srv.Client().Do(req)
	if err != nil {
		t.Fatalf("GET %s%s: %v", ruta, aparato, err)
	}
	defer resp.Body.Close()
	crudo, _ := io.ReadAll(resp.Body)
	var sobre struct{ Codigo string }
	_ = json.Unmarshal(crudo, &sobre)
	return resp.StatusCode, sobre.Codigo, resp.Header, string(crudo)
}

// flujo es un canal abierto: lo que llega, trama a trama (hasta la línea en blanco).
type flujo struct {
	t        *testing.T
	resp     *http.Response
	cancelar context.CancelFunc
	tramas   chan string
	fin      chan struct{} // se cierra cuando el servidor cerró el flujo (o se perdió la conexión)
	parar    chan struct{}
	cierre   sync.Once
	todo     string // todo lo recibido hasta ahora, en orden
}

// canalSinCabeceras: un canal que no entrega ni las cabeceras (sin `Flush`, o sin escribir nada al entrar) las hará
// esperar a TODAS las pruebas que abren uno; con el primer fallo basta, y las demás fallan al instante en vez de sumar
// `plazoParaAbrir` cada una (veinte pruebas son casi un minuto).
var canalSinCabeceras atomic.Bool

func abrirFlujo(t *testing.T, srv *httptest.Server, token, aparato string) *flujo {
	t.Helper()
	if canalSinCabeceras.Load() {
		t.Fatal("un canal anterior de esta ejecución no entregó ni las cabeceras (¿sin `Flush`, o sin escribir nada al entrar?): no se espera otra vez")
	}
	ctx, cancelar := context.WithCancel(context.Background())
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, srv.URL+"/sync/revision/eventos?aparato="+aparato, nil)
	if err != nil {
		cancelar()
		t.Fatal(err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	cliente := clienteConPlazoParaAbrir(srv)
	t.Cleanup(cliente.CloseIdleConnections)
	resp, err := cliente.Do(req)
	if err != nil {
		cancelar()
		canalSinCabeceras.Store(true)
		t.Fatalf("no se pudo abrir el canal (¿no vacía el búfer, o no escribe nada al entrar?): %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		cuerpo, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		cancelar()
		t.Fatalf("el canal contestó %d: %s", resp.StatusCode, cuerpo)
	}
	f := &flujo{t: t, resp: resp, cancelar: cancelar, tramas: make(chan string, 256), fin: make(chan struct{}), parar: make(chan struct{})}
	t.Cleanup(f.cerrar)
	go f.leer()
	return f
}

func (f *flujo) leer() {
	defer close(f.fin)
	lector := bufio.NewReader(f.resp.Body)
	var trama strings.Builder
	for {
		linea, err := lector.ReadString('\n')
		trama.WriteString(linea)
		if linea == "\n" {
			select {
			case f.tramas <- trama.String():
			case <-f.parar:
				return
			}
			trama.Reset()
		}
		if err != nil {
			return
		}
	}
}

// cerrar es «el cliente se va»: cierra la conexión sin esperar a nadie.
func (f *flujo) cerrar() {
	f.cierre.Do(func() {
		close(f.parar)
		f.cancelar()
		f.resp.Body.Close()
	})
}

// siguiente devuelve la próxima trama, o false si en `espera` no llegó ninguna (o el servidor cerró el flujo).
func (f *flujo) siguiente(espera time.Duration) (string, bool) {
	tomar := func() (string, bool) {
		select {
		case tr := <-f.tramas:
			f.todo += tr
			return tr, true
		default:
			return "", false
		}
	}
	if tr, ok := tomar(); ok {
		return tr, true
	}
	reloj := time.NewTimer(espera)
	defer reloj.Stop()
	select {
	case tr := <-f.tramas:
		f.todo += tr
		return tr, true
	case <-f.fin:
		return tomar() // lo que dejó escrito antes de cerrar
	case <-reloj.C:
		return "", false
	}
}

// esperar exige que la próxima trama sea exactamente `quiero`.
func (f *flujo) esperar(quiero string) {
	f.t.Helper()
	tr, ok := f.siguiente(3 * time.Second)
	if !ok {
		f.t.Fatalf("no llegó %q (llevaba recibido %q)", quiero, f.todo)
	}
	if tr != quiero {
		f.t.Fatalf("llegó %q y se esperaba %q", tr, quiero)
	}
}

// silencio exige que en `durante` no llegue NADA.
func (f *flujo) silencio(durante time.Duration) {
	f.t.Helper()
	if tr, ok := f.siguiente(durante); ok {
		f.t.Fatalf("llegó %q y no tenía que llegar nada", tr)
	}
}

func (f *flujo) seCierra(espera time.Duration) bool {
	select {
	case <-f.fin:
		return true
	case <-time.After(espera):
		return false
	}
}

func esperarCanales(t *testing.T, a *avisos, total int) {
	t.Helper()
	limite := time.Now().Add(3 * time.Second)
	for {
		if n, _ := a.cuantas(); n == total {
			return
		}
		if time.Now().After(limite) {
			n, _ := a.cuantas()
			t.Fatalf("hay %d canales registrados y se esperaban %d", n, total)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

// ajustar cambia los topes o el latido bajo el cerrojo, para probarlos sin abrir 500 canales ni esperar 25 s.
func (a *avisos) ajustar(f func(*avisos)) {
	a.mu.Lock()
	defer a.mu.Unlock()
	f(a)
}

// manejadoresDeEventos cuenta cuántas goroutines están DENTRO de `eventos` ahora mismo, mirando las pilas: es la
// forma exacta de saber que no quedó ningún manejador huérfano (un `runtime.NumGoroutine` cuenta también las del
// servidor de pruebas y las del cliente).
func manejadoresDeEventos() int {
	buf := make([]byte, 1<<20)
	return strings.Count(string(buf[:runtime.Stack(buf, true)]), ".(*Servicio).eventos(")
}

// ---------------------------------------------------------------------------
// Las decisiones que tienen que avisar
// ---------------------------------------------------------------------------

type decisionDeRevision struct {
	nombre  string
	decidir func(t *testing.T, e *entorno, entrega uuid.UUID)
}

// Los TRES manejadores que deciden (aplicar uno, aplicar todo, descartar) y el rechazo al aplicar, que es un
// camino aparte dentro de «aplicar». Cada uno con UN apunte `A1` de la persona del entorno.
var decisionesQueAvisan = []decisionDeRevision{
	{"descartar uno", func(t *testing.T, e *entorno, _ uuid.UUID) {
		e.esperar(e.descartar(e.aparato.ID, "A1", map[string]any{"motivo": "no era para hoy"}), http.StatusOK, "")
	}},
	{"aplicar uno", func(t *testing.T, e *entorno, _ uuid.UUID) {
		w := e.aplicarUno(e.aparato.ID, "A1", nil)
		e.esperar(w, http.StatusOK, "")
		if r := resultadosDe(t, w).Resultados; len(r) != 1 || r[0].Estado != EstadoAplicado {
			t.Fatalf("no quedó aplicado: %+v", r)
		}
	}},
	{"aplicar todo en orden", func(t *testing.T, e *entorno, entrega uuid.UUID) {
		w, s := e.aplicarEntrega(entrega)
		e.esperar(w, http.StatusOK, "")
		if len(s.Resultados) != 1 || s.Resultados[0].Estado != EstadoAplicado {
			t.Fatalf("no quedó aplicado: %+v", s)
		}
	}},
	{"rechazado al aplicar", func(t *testing.T, e *entorno, _ uuid.UUID) {
		e.aplicador.responde = func(Peticion) (*uuid.UUID, error) { return nil, &Rechazo{Motivo: "La parada ya está cerrada."} }
		w := e.aplicarUno(e.aparato.ID, "A1", nil)
		e.esperar(w, http.StatusOK, "")
		if r := resultadosDe(t, w).Resultados; len(r) != 1 || r[0].Estado != "rechazado" {
			t.Fatalf("no quedó rechazado: %+v", r)
		}
	}},
}

// ---------------------------------------------------------------------------
// 1 · Llega a la persona, y sólo a ella
// ---------------------------------------------------------------------------

func TestLaPersonaRecibeSuAvisoEnVivoCuandoUnRevisorDecideUnApunteSuyo(t *testing.T) {
	for _, d := range decisionesQueAvisan {
		t.Run(d.nombre, func(t *testing.T) {
			paraCadaMotor(t, func(t *testing.T, e *entorno) {
				entrega := e.entregaDeLaPersona("A1")
				e.comoRevisor("admin-cam", "ADMINISTRADOR", e.sucursal)
				srv := e.servidorDeAvisos(t, map[string]identidad.Identidad{"ana": e.entrega}, 0)

				f := abrirFlujo(t, srv, "ana", e.aparato.ID.String())
				if c := f.resp.Header; c.Get("Content-Type") != "text/event-stream; charset=utf-8" || c.Get("Cache-Control") != "no-cache, no-transform" ||
					c.Get("X-Accel-Buffering") != "no" || c.Get("Connection") != "" {
					t.Errorf("las cabeceras del canal: %v", c)
				}
				f.esperar(entradaDelCanal)
				f.silencio(100 * time.Millisecond) // sin decisión no hay aviso

				d.decidir(t, e, entrega)
				f.esperar(avisoDelCanal)
				f.silencio(150 * time.Millisecond) // una decisión, un aviso

				// LO ÚNICO QUE SALIÓ POR EL CANAL: la entrada y la señal. Ni clave, ni aparato, ni estado, ni
				// motivo, ni nombre: el canal no tiene nada que filtrar porque no lleva nada.
				if f.todo != entradaDelCanal+avisoDelCanal {
					t.Errorf("por el canal salió algo más que la señal vacía: %q", f.todo)
				}
			})
		})
	}
}

func TestElAvisoNoLlegaANingunaOtraPersona(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		e.entregaDeLaPersona("A1")
		otraPersona := "p-otra-" + uuid.NewString()
		aparatoDeLaOtra, _ := e.entregarDeOtro(otraPersona, e.sucursal, "B1") // la MISMA sucursal: el alcance no las separa
		e.comoRevisor("admin-cam", "ADMINISTRADOR", e.sucursal)
		srv := e.servidorDeAvisos(t, map[string]identidad.Identidad{
			"ana": e.entrega, "otra": e.deEntrega(otraPersona, e.sucursal, time.Hour),
		}, 0)
		ana := abrirFlujo(t, srv, "ana", e.aparato.ID.String())
		otra := abrirFlujo(t, srv, "otra", aparatoDeLaOtra.ID.String())
		ana.esperar(entradaDelCanal)
		otra.esperar(entradaDelCanal)

		e.esperar(e.descartar(e.aparato.ID, "A1", map[string]any{"motivo": "no era para hoy"}), http.StatusOK, "")
		ana.esperar(avisoDelCanal)
		otra.silencio(200 * time.Millisecond)

		e.esperar(e.descartar(aparatoDeLaOtra.ID, "B1", map[string]any{"motivo": "no era para hoy"}), http.StatusOK, "")
		otra.esperar(avisoDelCanal)
		ana.silencio(200 * time.Millisecond)
	})
}

// Un 5xx del reparto devuelve el apunte a `en_revision`: para quien espera NO cambió nada, y avisar a cada reintento
// del revisor sería ruido en un canal cuyo único trabajo es no ser ruido.
func TestUnaCaidaDelRepartoNoAvisaAQuienEspera(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		e.entregaDeLaPersona("A1")
		e.comoRevisor("admin-cam", "ADMINISTRADOR", e.sucursal)
		srv := e.servidorDeAvisos(t, map[string]identidad.Identidad{"ana": e.entrega}, 0)
		f := abrirFlujo(t, srv, "ana", e.aparato.ID.String())
		f.esperar(entradaDelCanal)

		e.aplicador.responde = func(Peticion) (*uuid.UUID, error) { return nil, errors.New("connection refused") }
		e.esperar(e.aplicarUno(e.aparato.ID, "A1", nil), http.StatusBadGateway, CodigoRepartoNoContesta)
		f.silencio(200 * time.Millisecond)
		if got := e.estadoDe(e.aparato.ID, "A1"); got != sqlc.RevisionEstadoEnRevision {
			t.Errorf("el apunte quedó %s", got)
		}
	})
}

// ---------------------------------------------------------------------------
// 2 · Después de confirmar, nunca dentro; y el aviso no toca la respuesta
// ---------------------------------------------------------------------------

// datosConEspia envuelve los datos del entorno: al terminar CADA transacción, antes de devolver, mira si a la
// suscripción vigilada ya le han dejado un aviso. Eso sólo puede pasar si alguien avisó DENTRO de la transacción
// (el aviso es síncrono), o sea antes de que lo escrito esté confirmado.
type datosConEspia struct {
	store.Datos
	vigilada    *suscripcion
	avisoDentro atomic.Int32
	// Si no es nil, se llama justo DESPUÉS de que una transacción se confirme (ya devolvió sin error).
	alConfirmar func()
	// Cuántas veces se pidió `RevisionEntregaPorId`: ya no hay ninguna lectura de más para avisar (ver más abajo).
	lecturasDeLaEntrega atomic.Int32
}

func (d *datosConEspia) EnTransaccion(ctx context.Context, fn func(sqlc.Querier) error) error {
	err := d.Datos.EnTransaccion(ctx, func(q sqlc.Querier) error {
		err := fn(q)
		if d.vigilada != nil && len(d.vigilada.c) > 0 {
			d.avisoDentro.Add(1)
		}
		return err
	})
	if err == nil && d.alConfirmar != nil {
		d.alConfirmar()
	}
	return err
}

func (d *datosConEspia) RevisionEntregaPorId(ctx context.Context, id uuid.UUID) (sqlc.RevisionEntregaPorIdRow, error) {
	d.lecturasDeLaEntrega.Add(1)
	return d.Datos.RevisionEntregaPorId(ctx, id)
}

func TestElAvisoSaleDespuesDeConfirmarLaDecisionYNuncaDentroDeUnaTransaccion(t *testing.T) {
	for _, d := range decisionesQueAvisan {
		t.Run(d.nombre, func(t *testing.T) {
			espia := &datosConEspia{Datos: nuevaBaseConRevision(nuevaBase())}
			e := nuevoEntorno(t, "doble", espia)
			sus, err := e.servicio.avisos.suscribir(e.persona)
			if err != nil {
				t.Fatal(err)
			}
			espia.vigilada = sus
			entrega := e.entregaDeLaPersona("A1")
			e.comoRevisor("admin-cam", "ADMINISTRADOR", e.sucursal)

			d.decidir(t, e, entrega)

			if n := espia.avisoDentro.Load(); n != 0 {
				t.Errorf("SE AVISÓ DENTRO DE UNA TRANSACCIÓN (%d veces): quien recibe el aviso consulta `mias` y puede leer lo de antes", n)
			}
			if pendientes(sus) != 1 {
				t.Errorf("tras decidir no quedó el aviso (pendientes: %d)", pendientes(sus))
			}
		})
	}
}

// A QUIÉN SE AVISA SALE DE LA PROPIA SENTENCIA que escribe la decisión (`RETURNING e.persona` en el descarte, la fila ya
// cargada en «aplicar»): ninguna lectura de más entre confirmar y contestar al revisor. Una lectura ahí es lo que, con la
// base lenta, retenía la respuesta al revisor (net/http no vacía hasta que el manejador vuelve), y un fallo suyo dejaba
// sin aviso a quien lo espera.
func TestAvisarNoCuestaNingunaLecturaMasAntesDeContestarAlRevisor(t *testing.T) {
	for _, d := range decisionesQueAvisan {
		t.Run(d.nombre, func(t *testing.T) {
			espia := &datosConEspia{Datos: nuevaBaseConRevision(nuevaBase())}
			e := nuevoEntorno(t, "doble", espia)
			sus, _ := e.servicio.avisos.suscribir(e.persona)
			entrega := e.entregaDeLaPersona("A1")
			e.comoRevisor("admin-cam", "ADMINISTRADOR", e.sucursal)
			antes := espia.lecturasDeLaEntrega.Load()

			d.decidir(t, e, entrega)

			if n := espia.lecturasDeLaEntrega.Load() - antes; n != 0 {
				t.Errorf("decidir leyó la entrega %d veces solo para saber a quién avisar", n)
			}
			if pendientes(sus) != 1 {
				t.Errorf("no avisó a la persona (pendientes: %d)", pendientes(sus))
			}
		})
	}
}

// SI EL REVISOR SE VA JUSTO DESPUÉS DE CONFIRMAR (cierra la pestaña: el contexto de su petición se cancela), la
// decisión ya está escrita y la persona RECIBE el aviso igual. Un `if ctx.Err() == nil` delante del aviso, o una
// lectura con ese contexto, la dejaría sin él.
func TestSiElRevisorSeVaJustoDespuesDeConfirmarLaPersonaRecibeElAviso(t *testing.T) {
	for _, d := range decisionesQueAvisan {
		t.Run(d.nombre, func(t *testing.T) {
			espia := &datosConEspia{Datos: nuevaBaseConRevision(nuevaBase())}
			e := nuevoEntorno(t, "doble", espia)
			sus, _ := e.servicio.avisos.suscribir(e.persona)
			ctx, seFue := context.WithCancel(context.Background())
			defer seFue()
			e.ctx = ctx
			entrega := e.entregaDeLaPersona("A1")
			e.comoRevisor("admin-cam", "ADMINISTRADOR", e.sucursal)
			espia.alConfirmar = seFue // la primera transacción que se confirma tras esto: el revisor ya no está

			d.decidir(t, e, entrega)

			if ctx.Err() == nil {
				t.Fatal("la prueba no canceló el contexto: no demuestra nada")
			}
			if pendientes(sus) != 1 {
				t.Errorf("EL REVISOR SE FUE Y LA PERSONA SE QUEDÓ SIN AVISO (pendientes: %d)", pendientes(sus))
			}
			if got := e.estadoDe(e.aparato.ID, "A1"); got == sqlc.RevisionEstadoEnRevision {
				t.Errorf("la decisión no quedó escrita: %s", got)
			}
		})
	}
}

// ---------------------------------------------------------------------------
// 3 · Quién puede abrirlo
// ---------------------------------------------------------------------------

func TestElCanalSoloLoAbreElTokenDeEntregaDeLaPersonaDelAparato(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	otraPersona := "p-otra-" + uuid.NewString()
	aparatoDeLaOtra, _ := e.entregarDeOtro(otraPersona, e.sucursal, "B1")
	e.comoRevisor("admin-cam", "ADMINISTRADOR", e.sucursal)
	otraSucursal := uuid.New()
	sinCaducidad := e.deEntrega(e.persona, e.sucursal, time.Hour)
	sinCaducidad.Caduca = time.Time{}

	tokens := map[string]identidad.Identidad{
		"ana":  e.entrega,
		"otra": e.deEntrega(otraPersona, e.sucursal, time.Hour),
		// EL TOKEN NORMAL de la APK (con `Token` reenviable y sin ámbito): lo que `mias` sí acepta y el canal NO.
		"normal": e.normal,
		// Un revisor con rol de revisor y token propio, SIN ser dueño del aparato: para él existe su bandeja.
		"revisor": e.normal,
		// La identidad que dan las cabeceras de un proxy (`SYNC_IDENTIDAD=cabeceras`): ni token ni ámbito. Sólo la
		// comprobación del ÁMBITO la para (la del `Token` no: no lo lleva), por eso es un caso aparte del normal.
		"cabeceras": {Persona: e.persona, Sucursal: e.sucursal, Jti: "j", Caduca: time.Now().Add(time.Hour)},
		// Con ámbito pero reenviable, o Super Admin: nada de eso es un token de entrega.
		"reenviable": {Persona: e.persona, Sucursal: e.sucursal, Jti: "j", Ambito: identidad.AmbitoEntrega, Token: "x", Caduca: time.Now().Add(time.Hour)},
		"superadmin": {Persona: e.persona, Sucursal: e.sucursal, Jti: "j", Ambito: identidad.AmbitoEntrega, EsSuperAdmin: true, Caduca: time.Now().Add(time.Hour)},
		// Una persona con ámbito de entrega que pide el aparato de otra, aunque tenga rol de revisor.
		"revisor-con-ambito": e.deEntrega("admin-cam", e.sucursal, time.Hour),
		// La misma persona, pero con un token de otra sucursal: el aparato no es de su alcance.
		"ana-de-otra-sucursal": e.deEntrega(e.persona, otraSucursal, time.Hour),
		// Sin `exp` no hay con qué cerrar el flujo: no se abre.
		"sin-caducidad": sinCaducidad,
	}
	srv := e.servidorDeAvisos(t, tokens, 0)
	suyo, ajeno := "?aparato="+e.aparato.ID.String(), "?aparato="+aparatoDeLaOtra.ID.String()

	casos := []struct {
		nombre, token, query string
		estado               int
		codigo               string
		// ¿`mias` contesta LO MISMO a esta petición? Para los casos del aparato, sí: los mismos códigos, sin un
		// oráculo nuevo. Para los del token, no: `mias` acepta el normal, y el canal no.
		igualQueMias bool
	}{
		{"sin token", "", suyo, http.StatusUnauthorized, "", false},
		{"token desconocido", "no-existe", suyo, http.StatusUnauthorized, "", false},
		{"el token NORMAL de la APK", "normal", suyo, http.StatusForbidden, identidad.CodigoSinPermisoReparto, false},
		{"un revisor con su token normal", "revisor", suyo, http.StatusForbidden, identidad.CodigoSinPermisoReparto, false},
		{"la identidad de un proxy: ni token ni ámbito", "cabeceras", suyo, http.StatusForbidden, identidad.CodigoSinPermisoReparto, false},
		{"ámbito de entrega pero con token reenviable", "reenviable", suyo, http.StatusForbidden, identidad.CodigoSinPermisoReparto, false},
		{"Super Admin con ámbito", "superadmin", suyo, http.StatusForbidden, identidad.CodigoSinPermisoReparto, false},
		{"sin caducidad no se abre", "sin-caducidad", suyo, http.StatusUnauthorized, "", false},
		{"el aparato de otra persona", "ana", ajeno, http.StatusForbidden, CodigoAparatoAjeno, true},
		{"la otra persona pide el aparato de Ana", "otra", suyo, http.StatusForbidden, CodigoAparatoAjeno, true},
		{"un revisor con ámbito pide el aparato de Ana", "revisor-con-ambito", suyo, http.StatusForbidden, CodigoAparatoAjeno, true},
		{"Ana con un token de otra sucursal", "ana-de-otra-sucursal", suyo, http.StatusForbidden, CodigoAparatoAjeno, true},
		{"sin aparato", "ana", "", http.StatusBadRequest, "", true},
		{"un aparato que no es un uuid", "ana", "?aparato=no-es-un-uuid", http.StatusBadRequest, "", true},
		{"un aparato que no existe", "ana", "?aparato=" + uuid.NewString(), http.StatusNotFound, httpx.CodigoAparatoNoRegistrado, true},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			estado, codigo, cab, cuerpo := pedirEventos(t, srv, "/sync/revision/eventos", c.token, c.query)
			if estado != c.estado || codigo != c.codigo {
				t.Fatalf("contestó %d %q y se esperaba %d %q: %s", estado, codigo, c.estado, c.codigo, cuerpo)
			}
			if strings.HasPrefix(cab.Get("Content-Type"), "text/event-stream") {
				t.Errorf("un rechazo no puede llevar el tipo de un flujo: %s", cab.Get("Content-Type"))
			}
			if c.igualQueMias {
				e2, k2, _, _ := pedirEventos(t, srv, "/sync/revision/mias", c.token, c.query)
				if e2 != estado || k2 != codigo {
					t.Errorf("`mias` contesta %d %q y el canal %d %q: tienen que ser los mismos para no abrir un oráculo nuevo", e2, k2, estado, codigo)
				}
			}
		})
	}
	// Ningún rechazo gastó un hueco: el tope se cuenta DESPUÉS de las comprobaciones.
	if total, _ := e.servicio.avisos.cuantas(); total != 0 {
		t.Errorf("los rechazos dejaron %d canales registrados", total)
	}
	// Y el que sí es de Ana abre.
	f := abrirFlujo(t, srv, "ana", e.aparato.ID.String())
	f.esperar(entradaDelCanal)
}

// LA PUERTA DE LA RUTA, aparte de la guarda del manejador (las dos tienen que valer por separado): `eventos` va
// con la fuente `entrega` (sólo token de entrega) y NO con la de `mias` (que acepta también el normal).
func TestElCanalDeAvisosSeMontaConLaFuenteDeEntregaYNoConLaDeMias(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	var deEntrega, deMias atomic.Int32
	entrega := func(*http.Request) (identidad.Identidad, error) { deEntrega.Add(1); return e.entrega, nil }
	mias := func(*http.Request) (identidad.Identidad, error) { deMias.Add(1); return e.entrega, nil }
	srv := e.servidorConFuentes(t, entrega, mias, 0)

	f := abrirFlujo(t, srv, "da-igual", e.aparato.ID.String())
	f.esperar(entradaDelCanal)
	if deEntrega.Load() != 1 || deMias.Load() != 0 {
		t.Errorf("la puerta de /eventos: fuente de entrega %d veces y fuente de mias %d (tenía que ser 1 y 0)", deEntrega.Load(), deMias.Load())
	}
}

// ---------------------------------------------------------------------------
// 4 · Los topes y la baja
// ---------------------------------------------------------------------------

func TestLaCuartaConexionDeLaMismaPersonaRecibe429ConRetryAfter(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	otraPersona := "p-otra-" + uuid.NewString()
	aparatoDeLaOtra, _ := e.entregarDeOtro(otraPersona, e.sucursal, "B1")
	srv := e.servidorDeAvisos(t, map[string]identidad.Identidad{
		"ana": e.entrega, "otra": e.deEntrega(otraPersona, e.sucursal, time.Hour),
	}, 0)
	aparato := e.aparato.ID.String()

	var canales []*flujo
	for i := 0; i < 3; i++ {
		f := abrirFlujo(t, srv, "ana", aparato)
		f.esperar(entradaDelCanal)
		canales = append(canales, f)
	}
	estado, codigo, cab, cuerpo := pedirEventos(t, srv, "/sync/revision/eventos", "ana", "?aparato="+aparato)
	if estado != http.StatusTooManyRequests || codigo != CodigoAvisosAlTope {
		t.Fatalf("la 4.ª conexión: %d %q (%s)", estado, codigo, cuerpo)
	}
	if cab.Get("Retry-After") != "30" {
		t.Errorf("Retry-After = %q, tenía que ser 30", cab.Get("Retry-After"))
	}
	if !strings.Contains(cuerpo, "30 segundos") || !strings.Contains(cuerpo, "Actualizar estados") {
		t.Errorf("el mensaje tiene que decir qué hacer, en español: %s", cuerpo)
	}
	// El rechazo no gastó hueco, y el tope es POR PERSONA: la otra entra.
	if total, _ := e.servicio.avisos.cuantas(); total != 3 {
		t.Errorf("tras el 429 hay %d canales y tenían que seguir siendo 3", total)
	}
	otra := abrirFlujo(t, srv, "otra", aparatoDeLaOtra.ID.String())
	otra.esperar(entradaDelCanal)

	// Al irse uno, vuelve a caber.
	canales[0].cerrar()
	esperarCanales(t, e.servicio.avisos, 3) // 2 de Ana + 1 de la otra
	f := abrirFlujo(t, srv, "ana", aparato)
	f.esperar(entradaDelCanal)
}

func TestElTopeGlobalDeCanalesDiceQueEsDelServicioNoDeLaPersona(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	otraPersona := "p-otra-" + uuid.NewString()
	aparatoDeLaOtra, _ := e.entregarDeOtro(otraPersona, e.sucursal, "B1")
	e.servicio.avisos.ajustar(func(a *avisos) { a.topeEnTotal = 2 })
	srv := e.servidorDeAvisos(t, map[string]identidad.Identidad{
		"ana": e.entrega, "otra": e.deEntrega(otraPersona, e.sucursal, time.Hour),
	}, 0)

	abrirFlujo(t, srv, "ana", e.aparato.ID.String()).esperar(entradaDelCanal)
	abrirFlujo(t, srv, "otra", aparatoDeLaOtra.ID.String()).esperar(entradaDelCanal)
	estado, codigo, cab, cuerpo := pedirEventos(t, srv, "/sync/revision/eventos", "ana", "?aparato="+e.aparato.ID.String())
	if estado != http.StatusTooManyRequests || codigo != CodigoAvisosAlTope || cab.Get("Retry-After") != "30" {
		t.Fatalf("con el servicio al tope: %d %q Retry-After=%q (%s)", estado, codigo, cab.Get("Retry-After"), cuerpo)
	}
	if !strings.Contains(cuerpo, "demasiados canales") {
		t.Errorf("tenía que decir que es el servicio, no ella: %s", cuerpo)
	}
}

func TestCuandoElClienteSeVaSeLiberaSuCanalYNoQuedaNingunaGoroutine(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	srv := e.servidorDeAvisos(t, map[string]identidad.Identidad{"ana": e.entrega}, 0)
	antes := manejadoresDeEventos()

	var canales []*flujo
	for i := 0; i < 3; i++ {
		f := abrirFlujo(t, srv, "ana", e.aparato.ID.String())
		f.esperar(entradaDelCanal)
		canales = append(canales, f)
	}
	if total, _ := e.servicio.avisos.cuantas(); total != 3 {
		t.Fatalf("con tres canales abiertos hay %d registrados", total)
	}
	if n := manejadoresDeEventos() - antes; n != 3 {
		t.Fatalf("con tres canales abiertos hay %d manejadores vivos (la comprobación de pilas no ve lo que debería)", n)
	}

	for _, f := range canales {
		f.cerrar() // el teléfono se queda sin señal: la conexión se corta sin avisar
	}
	limite := time.Now().Add(3 * time.Second)
	for {
		total, personas := e.servicio.avisos.cuantas()
		vivos := manejadoresDeEventos() - antes
		if total == 0 && personas == 0 && vivos == 0 {
			break
		}
		if time.Now().After(limite) {
			t.Fatalf("tras irse los clientes quedan %d canales, %d personas y %d manejadores vivos: la suscripción no se libera", total, personas, vivos)
		}
		time.Sleep(5 * time.Millisecond)
	}
	// Y el cupo de Ana está entero.
	for i := 0; i < 3; i++ {
		abrirFlujo(t, srv, "ana", e.aparato.ID.String()).esperar(entradaDelCanal)
	}
}

// ---------------------------------------------------------------------------
// 5 · Cuándo se cierra, y el latido
// ---------------------------------------------------------------------------

func TestElCanalSeCierraSoloCuandoCaducaElTokenDeEntrega(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	srv := e.servidorDeAvisos(t, map[string]identidad.Identidad{
		"corto":    e.deEntrega(e.persona, e.sucursal, 300*time.Millisecond),
		"largo":    e.deEntrega(e.persona, e.sucursal, time.Hour),
		"caducado": e.deEntrega(e.persona, e.sucursal, -time.Second),
	}, 0)
	aparato := e.aparato.ID.String()

	corto := abrirFlujo(t, srv, "corto", aparato)
	largo := abrirFlujo(t, srv, "largo", aparato)
	corto.esperar(entradaDelCanal)
	largo.esperar(entradaDelCanal)
	if !corto.seCierra(3 * time.Second) {
		t.Fatal("EL CANAL SIGUE ABIERTO TRAS CADUCAR EL TOKEN: una conexión de diez minutos viviría para siempre")
	}
	// Ni antes ni más de lo debido: el de token largo sigue ahí, y el del corto liberó su sitio.
	if largo.seCierra(100 * time.Millisecond) {
		t.Error("el canal de un token que no ha caducado se cerró")
	}
	esperarCanales(t, e.servicio.avisos, 1)

	// Un token que ya caducó entre la comprobación y el manejador no deja un canal abierto.
	caducado := abrirFlujo(t, srv, "caducado", aparato)
	if !caducado.seCierra(3 * time.Second) {
		t.Error("un token ya caducado dejó el canal abierto")
	}
}

func TestElCanalMandaUnComentarioDeLatidoCadaTanto(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	e.servicio.avisos.ajustar(func(a *avisos) { a.latido = 40 * time.Millisecond })
	srv := e.servidorDeAvisos(t, map[string]identidad.Identidad{"ana": e.entrega}, 0)

	f := abrirFlujo(t, srv, "ana", e.aparato.ID.String())
	f.esperar(entradaDelCanal)
	f.esperar(": ka\n\n")
	f.esperar(": ka\n\n")
	// El latido es un comentario SSE, que el cliente ignora: no pasa por `event:` y no es un aviso.
	if strings.Contains(f.todo, "event:") {
		t.Errorf("un latido se coló como evento: %q", f.todo)
	}
}

// La constante del contrato (25 s), que las pruebas de arriba acortan.
func TestElLatidoEsDe25SegundosSegunElContrato(t *testing.T) {
	if latidoDeLosAvisos != 25*time.Second || nuevosAvisos().latido != 25*time.Second {
		t.Errorf("el latido es %s y el contrato dice 25 s", latidoDeLosAvisos)
	}
	if topeDeAvisosPorPersona != 3 || topeDeAvisosEnTotal != 500 {
		t.Errorf("los topes son %d y %d y el contrato dice 3 por persona y 500 en total", topeDeAvisosPorPersona, topeDeAvisosEnTotal)
	}
}

// ---------------------------------------------------------------------------
// 6 · El WriteTimeout del servidor
// ---------------------------------------------------------------------------

// `main` pone `WriteTimeout` (60 s) a TODO el servidor: un SSE con esa espera moriría a los 60 s sin decir nada.
// Aquí se quita sólo para ESTE flujo. Con la cadena de verdad (`Registro` envuelve el escritor: sin su `Unwrap`,
// `SetWriteDeadline` contesta `ErrNotSupported` y el canal ni se abre) y plazos de 300 ms.
func TestElCanalSobreviveAlPlazoDeEscrituraDelServidorYElRestoDeRutasNoLoPierde(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	e.entregaDeLaPersona("A1")
	e.comoRevisor("admin-cam", "ADMINISTRADOR", e.sucursal)
	lenta := func(mux *http.ServeMux) {
		mux.HandleFunc("GET /lenta", func(w http.ResponseWriter, r *http.Request) {
			time.Sleep(600 * time.Millisecond) // el doble del plazo
			_, _ = io.WriteString(w, "tarde")
		})
	}
	// El plazo de cada escritura del canal, también corto: si se fijara UNA vez al abrir en vez de renovarlo antes de
	// cada escritura, el aviso de más abajo (a los 900 ms) caería en un plazo ya vencido.
	e.servicio.avisos.ajustar(func(a *avisos) { a.plazoDeEscritura = 300 * time.Millisecond })
	srv := e.servidorDeAvisos(t, map[string]identidad.Identidad{"ana": e.entrega}, 300*time.Millisecond, lenta)

	f := abrirFlujo(t, srv, "ana", e.aparato.ID.String())
	f.esperar(entradaDelCanal)
	time.Sleep(900 * time.Millisecond) // el triple del plazo de escritura Y de lectura
	e.esperar(e.descartar(e.aparato.ID, "A1", map[string]any{"motivo": "no era para hoy"}), http.StatusOK, "")
	f.esperar(avisoDelCanal) // si el plazo siguiera puesto, esta escritura habría cortado la conexión

	// EL RESTO NO SE ESTROPEA: en el mismo servidor, una petición que tarda más que el plazo sigue muriendo.
	if resp, err := srv.Client().Get(srv.URL + "/lenta"); err == nil {
		cuerpo, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Errorf("el WriteTimeout ya no corta al resto de rutas: contestó %d %q", resp.StatusCode, cuerpo)
	}
}

// Y el plazo VUELVE para la siguiente petición de la MISMA conexión: Go lo pone de nuevo al leer cada petición, y
// esta prueba lo ata (un flujo que termina y deja la conexión reutilizable no puede dejarla sin plazo para siempre).
func TestElPlazoDeEscrituraVuelveParaLaSiguientePeticionDeLaMismaConexion(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	lenta := func(mux *http.ServeMux) {
		mux.HandleFunc("GET /lenta", func(w http.ResponseWriter, r *http.Request) {
			time.Sleep(600 * time.Millisecond)
			_, _ = io.WriteString(w, "tarde")
		})
	}
	srv := e.servidorDeAvisos(t, map[string]identidad.Identidad{"corto": e.deEntrega(e.persona, e.sucursal, 150*time.Millisecond)},
		300*time.Millisecond, lenta)

	// 1 · el canal se abre, caduca y termina limpio, dejando la conexión en el depósito del cliente.
	_, _, _, cuerpo := pedirEventos(t, srv, "/sync/revision/eventos", "corto", "?aparato="+e.aparato.ID.String())
	if !strings.HasPrefix(cuerpo, entradaDelCanal) {
		t.Fatalf("el canal no se abrió: %q", cuerpo)
	}
	// 2 · la petición lenta, por esa misma conexión.
	reutilizada := false
	// (si el servidor corta una conexión reutilizada, el cliente reintenta el GET por otra nueva: se guarda si ALGUNA fue la misma)
	traza := &httptrace.ClientTrace{GotConn: func(i httptrace.GotConnInfo) { reutilizada = reutilizada || i.Reused }}
	req, _ := http.NewRequestWithContext(httptrace.WithClientTrace(context.Background(), traza), http.MethodGet, srv.URL+"/lenta", nil)
	resp, err := srv.Client().Do(req)
	if !reutilizada {
		t.Fatal("el cliente no reutilizó la conexión: la prueba no demuestra lo que quiere demostrar")
	}
	if err == nil {
		resp.Body.Close()
		t.Errorf("LA PETICIÓN SIGUIENTE POR LA MISMA CONEXIÓN QUEDÓ SIN PLAZO DE ESCRITURA (contestó %d)", resp.StatusCode)
	}
}

// ---------------------------------------------------------------------------
// 6-bis · Las cabeceras tal como salen, y el cliente que deja de leer
// ---------------------------------------------------------------------------

// NUNCA `Connection: keep-alive` (HTTP/2 y HTTP/3 lo prohíben: tras Cloudflare da `ERR_QUIC_PROTOCOL_ERROR`, la trampa de
// `docs/despliegue.md`). Se mira con un SOCKET EN CRUDO y no con `http.Client`, que normaliza y reordena las cabeceras
// y esconde justo lo que hay que ver. También cuando la PETICIÓN trae `Connection: keep-alive`: el servidor de Go no
// lo repite, y un manejador que «ayudara» a contestarla lo haría.
func TestLaRespuestaDelCanalNoLlevaConnectionTalComoSale(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	srv := e.servidorDeAvisos(t, map[string]identidad.Identidad{"ana": e.entrega}, 0)

	for nombre, conexion := range map[string]string{"sin cabecera Connection": "", "la petición trae Connection: keep-alive": "Connection: keep-alive\r\n"} {
		t.Run(nombre, func(t *testing.T) {
			sock, err := net.DialTimeout("tcp", srv.Listener.Addr().String(), 3*time.Second)
			if err != nil {
				t.Fatal(err)
			}
			defer sock.Close()
			_ = sock.SetDeadline(time.Now().Add(plazoParaAbrir))
			fmt.Fprintf(sock, "GET /sync/revision/eventos?aparato=%s HTTP/1.1\r\nHost: sync\r\nAuthorization: Bearer ana\r\n%s\r\n", e.aparato.ID, conexion)

			lector := bufio.NewReader(sock)
			var cabeceras []string
			for {
				linea, err := lector.ReadString('\n')
				if err != nil {
					t.Fatalf("no llegaron las cabeceras enteras (¿no vacía el búfer?): %v (recibido %q)", err, cabeceras)
				}
				linea = strings.TrimRight(linea, "\r\n")
				if linea == "" {
					break
				}
				cabeceras = append(cabeceras, linea)
			}
			if len(cabeceras) == 0 || !strings.HasPrefix(cabeceras[0], "HTTP/1.1 200") {
				t.Fatalf("la respuesta: %q", cabeceras)
			}
			tiene := map[string]bool{}
			for _, c := range cabeceras[1:] {
				tiene[c] = true
				nombre, _, _ := strings.Cut(c, ":")
				if n := strings.ToLower(strings.TrimSpace(nombre)); n == "connection" || n == "keep-alive" {
					t.Errorf("LA RESPUESTA DEL CANAL LLEVA %q: con HTTP/2 o HTTP/3 delante (Cloudflare) rompe la conexión", c)
				}
			}
			for _, quiero := range []string{
				"Content-Type: text/event-stream; charset=utf-8", "Cache-Control: no-cache, no-transform", "X-Accel-Buffering: no",
			} {
				if !tiene[quiero] {
					t.Errorf("falta la cabecera %q; salieron %q", quiero, cabeceras)
				}
			}
			// Y lo primero que sigue es la entrada, en un trozo `chunked` (11 bytes = 0xb).
			if cuerpo, _ := lector.ReadString('\n'); strings.TrimSpace(cuerpo) != "b" {
				t.Errorf("tras las cabeceras tenía que venir el trozo de `: abierto` (b) y vino %q", cuerpo)
			}
		})
	}
}

// oyenteEnMemoria entrega UNA conexión (`net.Pipe`) al servidor HTTP. En un pipe cada escritura se BLOQUEA hasta que el otro
// lado lee, que es justo un cliente cuyo socket murió sin RST: no lee ni cierra, y el servidor se queda escribiendo.
type oyenteEnMemoria struct {
	conexiones chan net.Conn
	cerrado    chan struct{}
	cierre     sync.Once
}

type direccionEnMemoria struct{}

func (direccionEnMemoria) Network() string { return "memoria" }
func (direccionEnMemoria) String() string  { return "memoria" }

func (o *oyenteEnMemoria) Accept() (net.Conn, error) {
	select {
	case c := <-o.conexiones:
		return c, nil
	case <-o.cerrado:
		return nil, net.ErrClosed
	}
}
func (o *oyenteEnMemoria) Close() error   { o.cierre.Do(func() { close(o.cerrado) }); return nil }
func (o *oyenteEnMemoria) Addr() net.Addr { return direccionEnMemoria{} }

// UN CLIENTE QUE DEJA DE LEER SIN CERRAR (el móvil pierde la señal y no manda RST) NO RETIENE EL CANAL: el plazo de cada
// escritura se RENUEVA antes de escribir, así que la que se queda bloqueada vence a los pocos segundos, el manejador
// vuelve y el hueco del tope se libera. Quitar el plazo del todo (en vez de renovarlo) lo dejaba retenido hasta el
// timeout de TCP, que son horas, y con tres huecos por persona un teléfono con mala señal se quedaba sin canal.
func TestUnClienteQueDejaDeLeerSinCerrarNoRetieneElCanal(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	e.servicio.avisos.ajustar(func(a *avisos) { a.plazoDeEscritura = 300 * time.Millisecond })
	mux := http.NewServeMux()
	e.servicio.RutasDeRevision(mux, fuenteDe(map[string]identidad.Identidad{"ana": e.entrega}), fuenteDe(nil))
	servidor := &http.Server{Handler: httpx.Recuperar(e.servicio.log, httpx.Registro(e.servicio.log, mux))}
	oyente := &oyenteEnMemoria{conexiones: make(chan net.Conn, 1), cerrado: make(chan struct{})}
	cliente, deLaConexion := net.Pipe()
	oyente.conexiones <- deLaConexion
	go func() { _ = servidor.Serve(oyente) }()
	t.Cleanup(func() { _ = servidor.Close(); _ = cliente.Close() })

	_ = cliente.SetDeadline(time.Now().Add(plazoParaAbrir))
	if _, err := fmt.Fprintf(cliente, "GET /sync/revision/eventos?aparato=%s HTTP/1.1\r\nHost: sync\r\nAuthorization: Bearer ana\r\n\r\n", e.aparato.ID); err != nil {
		t.Fatal(err)
	}
	// Lee las cabeceras y la entrada, y ahí se queda: ni lee más ni cierra.
	lector := bufio.NewReader(cliente)
	visto := ""
	for !strings.Contains(visto, ": abierto\n\n") {
		linea, err := lector.ReadString('\n')
		if err != nil {
			t.Fatalf("no llegó la entrada del canal (¿falta `: abierto` o el `Flush`?): %v (recibido %q)", err, visto)
		}
		visto += linea
	}
	esperarCanales(t, e.servicio.avisos, 1)

	// El teléfono ya no lee. Un aviso: la escritura se bloquea y vence a los 300 ms.
	e.servicio.avisos.avisar(e.persona)
	esperarCanales(t, e.servicio.avisos, 0) // el manejador volvió y dio de baja su hueco (3 s de margen)
}

// ---------------------------------------------------------------------------
// 7 · El apagado
// ---------------------------------------------------------------------------

// Un SSE no queda inactivo nunca, así que `Shutdown` lo esperaría hasta el plazo de `main` (30 s): `CerrarAvisos`,
// registrado en el apagado del servidor, lo cierra. Sin él, esta prueba se queda sin respuesta hasta el plazo.
func TestElApagadoDelServidorCierraLosCanalesAbiertosSinEsperarAlPlazo(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	srv := e.servidorDeAvisos(t, map[string]identidad.Identidad{"ana": e.entrega}, 0)
	f := abrirFlujo(t, srv, "ana", e.aparato.ID.String())
	f.esperar(entradaDelCanal)

	ctx, cancelar := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancelar()
	inicio := time.Now()
	if err := srv.Config.Shutdown(ctx); err != nil {
		t.Fatalf("Shutdown no terminó con un canal abierto: %v", err)
	}
	if d := time.Since(inicio); d > 2*time.Second {
		t.Errorf("Shutdown tardó %s con un canal abierto", d)
	}
	if !f.seCierra(2 * time.Second) {
		t.Error("el canal siguió abierto tras el apagado")
	}
}

// `cmd/sync/main.go` tiene que REGISTRAR `CerrarAvisos` en el apagado del servidor que de verdad se apaga: la prueba de
// arriba demuestra que el mecanismo vale, y `cmd/sync` no tiene pruebas. Por AST (un comentario no cuenta) y ATANDO LOS
// DOS EXTREMOS: el receptor de `RegisterOnShutdown` tiene que ser la variable que sale de `&http.Server{…}` y a la que
// después se le llama `Shutdown`, y lo registrado, el `CerrarAvisos` del servicio que sale de `sincro.Nuevo`. Con
// `(&http.Server{}).RegisterOnShutdown(servicio.CerrarAvisos)` el registro existe y no apaga nada: el cierre real
// espera los 30 s del plazo.
func TestMainRegistraElCierreDeLosAvisosEnElServidorQueDespuesSeApaga(t *testing.T) {
	f, err := parser.ParseFile(token.NewFileSet(), "../../cmd/sync/main.go", nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	var servidor, servicio string // las variables a las que main asigna el servidor HTTP y el servicio
	var registros [][2]string     // (receptor, argumento) de cada RegisterOnShutdown
	var apagados []string         // receptor de cada Shutdown
	ast.Inspect(f, func(n ast.Node) bool {
		switch x := n.(type) {
		case *ast.AssignStmt:
			if len(x.Lhs) != 1 || len(x.Rhs) != 1 {
				break
			}
			nombre, ok := x.Lhs[0].(*ast.Ident)
			if !ok {
				break
			}
			switch r := x.Rhs[0].(type) {
			case *ast.UnaryExpr: // servidor := &http.Server{…}
				if c, ok := r.X.(*ast.CompositeLit); ok && r.Op == token.AND && types.ExprString(c.Type) == "http.Server" {
					servidor = nombre.Name
				}
			case *ast.CallExpr: // servicio := sincro.Nuevo(…)
				if types.ExprString(r.Fun) == "sincro.Nuevo" {
					servicio = nombre.Name
				}
			}
		case *ast.CallExpr:
			sel, ok := x.Fun.(*ast.SelectorExpr)
			if !ok {
				break
			}
			switch sel.Sel.Name {
			case "RegisterOnShutdown":
				if len(x.Args) == 1 {
					registros = append(registros, [2]string{types.ExprString(sel.X), types.ExprString(x.Args[0])})
				}
			case "Shutdown":
				apagados = append(apagados, types.ExprString(sel.X))
			}
		}
		return true
	})
	if servidor == "" || servicio == "" {
		t.Fatalf("main.go ya no asigna `x := &http.Server{…}` (%q) o `y := sincro.Nuevo(…)` (%q): la prueba no sabe qué atar", servidor, servicio)
	}
	apagaElServidor := false
	for _, a := range apagados {
		apagaElServidor = apagaElServidor || a == servidor
	}
	if !apagaElServidor {
		t.Errorf("main.go no llama a %s.Shutdown(…): el servidor no se apaga con cierre ordenado", servidor)
	}
	registrado := false
	for _, r := range registros {
		registrado = registrado || (r[0] == servidor && r[1] == servicio+".CerrarAvisos")
	}
	if !registrado {
		t.Errorf("cmd/sync/main.go no llama a %s.RegisterOnShutdown(%s.CerrarAvisos) sobre el MISMO servidor al que luego "+
			"hace Shutdown (registros vistos: %v): un canal de avisos abierto retendría el cierre ordenado hasta el plazo de 30 s, "+
			"que es el que necesitan las colas que se están aplicando", servidor, servicio, registros)
	}
}

// ---------------------------------------------------------------------------
// 8 · De punta a punta, con tokens de verdad y el cableado de `main`
// ---------------------------------------------------------------------------

func TestElCanalDeAvisosConTokensDeVerdadPorElCableadoDeMain(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	e.entregaDeLaPersona("A1")
	e.comoRevisor("admin-cam", "ADMINISTRADOR", e.sucursal)
	resolutor := func(_ context.Context, codigo string) (uuid.UUID, error) {
		if codigo == "STG" {
			return e.sucursal, nil
		}
		return uuid.Nil, identidad.ErrSinSesion
	}
	secreto := []byte(secretoDePrueba)
	normal := identidad.DeToken(secreto, resolutor)
	entrega, mias := identidad.FuentesDeEntrega("token", secreto, resolutor, nil, normal)
	srv := e.servidorConFuentes(t, entrega, mias, 0)
	aparato := "?aparato=" + e.aparato.ID.String()

	tEntrega, tConLlave, tSinLlave := tokensDe(t, e.persona)
	// 1 · el token de entrega abre el canal y le llega el aviso de lo suyo.
	f := abrirFlujo(t, srv, tEntrega, e.aparato.ID.String())
	f.esperar(entradaDelCanal)
	e.esperar(e.descartar(e.aparato.ID, "A1", map[string]any{"motivo": "no era para hoy"}), http.StatusOK, "")
	f.esperar(avisoDelCanal)

	// 2 · NINGÚN OTRO TOKEN lo abre: ni el normal con la llave (el que `mias` sí acepta), ni el normal sin ella, ni
	// uno roto, ni la falta de token.
	for _, c := range []struct {
		nombre, token string
		estado        int
		codigo        string
	}{
		{"el token normal de la APK (con la llave)", tConLlave, http.StatusForbidden, identidad.CodigoSinPermisoReparto},
		{"un token normal sin la llave", tSinLlave, http.StatusForbidden, identidad.CodigoSinPermisoReparto},
		{"sin token", "", http.StatusUnauthorized, ""},
		{"un token roto", tEntrega[:len(tEntrega)-3] + "AAA", http.StatusUnauthorized, ""},
		{"basura", "esto.no.es-un-token", http.StatusUnauthorized, ""},
	} {
		estado, codigo, _, cuerpo := pedirEventos(t, srv, "/sync/revision/eventos", c.token, aparato)
		if estado != c.estado || codigo != c.codigo {
			t.Errorf("%s: %d %q (%s), se esperaba %d %q", c.nombre, estado, codigo, cuerpo, c.estado, c.codigo)
		}
	}
	// (y `mias` con ese mismo token normal SÍ contesta: la diferencia entre las dos puertas es a propósito)
	if estado, _, _, _ := pedirEventos(t, srv, "/sync/revision/mias", tConLlave, aparato); estado != http.StatusOK {
		t.Errorf("mias con el token normal de la misma persona: %d", estado)
	}

	// 3 · y el canal muere con el `exp` del token de verdad (Accesos los firma de 10 minutos; éste, de 2 segundos).
	ahora := time.Now()
	corto := firmarToken(t, map[string]any{
		"sub": e.persona, "name": "Yasmani", "sucursal": "STG", "branch_id": "STG", "jti": "j-" + uuid.NewString(),
		"iat": ahora.Unix(), "exp": ahora.Add(2 * time.Second).Unix(),
		"purpose": identidad.PropositoEntrega, "ambito": identidad.AmbitoEntrega, "entradas": []string{}, "roles": []string{}, "role": "",
	})
	g := abrirFlujo(t, srv, corto, e.aparato.ID.String())
	g.esperar(entradaDelCanal)
	if !g.seCierra(4 * time.Second) {
		t.Error("el canal abierto con un token de verdad no se cerró al caducar su `exp`")
	}
}
