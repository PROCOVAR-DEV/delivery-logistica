package sincro

import (
	"sync"
	"testing"
	"time"
)

// EL CONCENTRADOR DE AVISOS (`avisos.go`), sin HTTP. Las pruebas con el canal abierto de verdad están en
// `revision_eventos_test.go`; aquí lo que se puede romper dentro de la estructura: a quién llega, que nunca
// bloquee, los topes y que la baja no deje nada. Corren con `-race` en `comprobar.sh`.

func pendientes(s *suscripcion) int { return len(s.c) }

// avisarSinColgarse llama a `avisar` con plazo: uno que bloqueara (con el cerrojo cogido) dejaría la prueba esperando al
// timeout de `go test`, que en el `Dockerfile.sync` son diez minutos. Una prueba tiene que FALLAR, no esperar.
func avisarSinColgarse(t *testing.T, a *avisos, persona string) {
	t.Helper()
	hecho := make(chan struct{})
	go func() { a.avisar(persona); close(hecho) }()
	select {
	case <-hecho:
	case <-time.After(2 * time.Second):
		t.Fatalf("avisar(%q) se quedó bloqueado con el canal lleno: el revisor no recibiría su respuesta", persona)
	}
}

func (a *avisos) cuantas() (total, personas int) {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.total, len(a.porPersona)
}

func TestUnAvisoLlegaSoloALosCanalesDeEsaPersona(t *testing.T) {
	a := nuevosAvisos()
	ana1, _ := a.suscribir("ana")
	ana2, _ := a.suscribir("ana")
	beto, _ := a.suscribir("beto")

	avisarSinColgarse(t, a, "ana")
	if pendientes(ana1) != 1 || pendientes(ana2) != 1 {
		t.Errorf("los dos canales de Ana tenían que recibirlo: %d y %d", pendientes(ana1), pendientes(ana2))
	}
	if pendientes(beto) != 0 {
		t.Error("UN AVISO DE ANA LLEGÓ A BETO")
	}

	avisarSinColgarse(t, a, "nadie") // sin canales: no pasa nada
	avisarSinColgarse(t, a, "")      // sin dueño: tampoco
	if pendientes(beto) != 0 {
		t.Error("un aviso sin dueño llegó a alguien")
	}
}

// UNA SEÑAL, NO UNA COLA: «aplicar todo en orden» de 25 apuntes son 25 avisos, y a quien no está leyendo le queda UNO.
// Y avisar a un canal lleno no se bloquea: esto corre en el manejador del revisor, con la bandeja ya escrita.
func TestAvisarNoBloqueaNiApilaConUnAvisoYaPendiente(t *testing.T) {
	a := nuevosAvisos()
	ana, _ := a.suscribir("ana")
	hecho := make(chan struct{})
	go func() {
		defer close(hecho)
		for i := 0; i < 1000; i++ {
			a.avisar("ana")
		}
	}()
	select {
	case <-hecho:
	case <-time.After(2 * time.Second):
		t.Fatal("avisar se quedó bloqueado con un canal lleno: el revisor no recibiría su respuesta")
	}
	if n := pendientes(ana); n != 1 {
		t.Errorf("quedaron %d avisos apilados y tenía que quedar 1 (es una señal, no una cola)", n)
	}
	// Y leído ese, el siguiente vuelve a entrar.
	<-ana.c
	avisarSinColgarse(t, a, "ana")
	if pendientes(ana) != 1 {
		t.Error("tras leer el aviso, el siguiente no entró")
	}
}

func TestElTopeDeCanalesPorPersonaYElTotal(t *testing.T) {
	a := nuevosAvisos()
	for i := 0; i < topeDeAvisosPorPersona; i++ {
		if _, err := a.suscribir("ana"); err != nil {
			t.Fatalf("el canal %d de Ana tenía que caber: %v", i+1, err)
		}
	}
	if _, err := a.suscribir("ana"); err != errPersonaAlTopeDeAvisos {
		t.Errorf("la 4.ª de Ana: %v, se esperaba el tope por persona", err)
	}
	if _, err := a.suscribir("beto"); err != nil {
		t.Errorf("el tope de Ana frenó a Beto: %v", err)
	}

	// El total, con un tope pequeño para no abrir 500.
	b := nuevosAvisos()
	b.topeEnTotal = 2
	_, _ = b.suscribir("ana")
	_, _ = b.suscribir("beto")
	if _, err := b.suscribir("carla"); err != errServicioAlTopeDeAvisos {
		t.Errorf("el 3.º con tope total de 2: %v, se esperaba el tope del servicio", err)
	}
}

func TestLaBajaLiberaElHuecoYNoDescuentaDosVeces(t *testing.T) {
	a := nuevosAvisos()
	var canales []*suscripcion
	for i := 0; i < topeDeAvisosPorPersona; i++ {
		s, _ := a.suscribir("ana")
		canales = append(canales, s)
	}
	otra, _ := a.suscribir("beto")

	a.baja(canales[0])
	a.baja(canales[0]) // la segunda es un no-op: si descontara, el total quedaría en 3 y dejaría colarse a uno de más
	if total, _ := a.cuantas(); total != 3 {
		t.Fatalf("total = %d tras una baja repetida, tenía que ser 3", total)
	}
	if _, err := a.suscribir("ana"); err != nil {
		t.Errorf("tras la baja, Ana tenía que poder abrir otro: %v", err)
	}
	// Lo dado de baja ya no recibe, y el mapa de personas no crece con quien se fue.
	avisarSinColgarse(t, a, "ana")
	if pendientes(canales[0]) != 0 {
		t.Error("un canal dado de baja siguió recibiendo avisos")
	}
	for _, c := range append(canales[1:], otra) {
		a.baja(c)
	}
	avisarSinColgarse(t, a, "ana") // el nuevo de Ana sigue
	if total, personas := a.cuantas(); total != 1 || personas != 1 {
		t.Errorf("tras bajar a todos menos uno: total=%d personas=%d", total, personas)
	}
}

// Suscribir, avisar y bajar a la vez desde muchas goroutines: sin carreras (`-race`) y con las cuentas en cero.
func TestSuscribirAvisarYBajarEnParaleloDejaTodoEnCero(t *testing.T) {
	a := nuevosAvisos()
	a.topePorPersona = 1000
	a.topeEnTotal = 100000
	var grupo sync.WaitGroup
	for g := 0; g < 16; g++ {
		persona := []string{"ana", "beto", "carla"}[g%3]
		grupo.Add(1)
		go func() {
			defer grupo.Done()
			for i := 0; i < 300; i++ {
				s, err := a.suscribir(persona)
				if err != nil {
					t.Errorf("suscribir: %v", err)
					return
				}
				a.avisar(persona)
				select {
				case <-s.c:
				default:
				}
				a.baja(s)
			}
		}()
	}
	// Con plazo: un `avisar` que bloqueara con el cerrojo cogido dejaría a todos esperando y la prueba colgada hasta el
	// timeout de `go test` (diez minutos en el `Dockerfile.sync`). Una prueba tiene que FALLAR, no esperar.
	hecho := make(chan struct{})
	go func() { grupo.Wait(); close(hecho) }()
	select {
	case <-hecho:
	case <-time.After(10 * time.Second):
		t.Fatal("las goroutines no terminaron en 10 s: un `avisar` bloqueado con el cerrojo cogido, o una baja que no libera")
	}
	if total, personas := a.cuantas(); total != 0 || personas != 0 {
		t.Errorf("tras bajar a todos: total=%d personas=%d, tenían que ser 0", total, personas)
	}
}

func TestCerrarLosAvisosEsIdempotente(t *testing.T) {
	a := nuevosAvisos()
	a.cerrar()
	a.cerrar() // un segundo `close` sobre el mismo canal sería un pánico en el apagado
	select {
	case <-a.cerrado:
	default:
		t.Error("cerrar no cerró")
	}
}
