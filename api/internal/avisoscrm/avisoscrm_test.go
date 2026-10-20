package avisoscrm

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"sync"
	"testing"
	"time"
)

func logMudo() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

func TestEntenderLeeElAvisoDelCRM(t *testing.T) {
	casos := []struct {
		nombre, crudo, codigo string
		entendido             bool
	}{
		{"el aviso tal como lo publica el CRM", `{"v":1,"tipo":"almacenes-cambiados","sucursal":"STG","tms":1792512000000}`, "STG", true},
		{"el código se normaliza: mayúsculas y sin espacios", `{"v":1,"tipo":"almacenes-cambiados","sucursal":" stg ","tms":1}`, "STG", true},
		{"un aviso bueno sin sucursal es de todas, no un error", `{"v":1,"tipo":"almacenes-cambiados","tms":1}`, "", true},
		{"otra versión no se entiende", `{"v":2,"tipo":"almacenes-cambiados","sucursal":"STG"}`, "", false},
		{"sin versión no se entiende", `{"tipo":"almacenes-cambiados","sucursal":"STG"}`, "", false},
		{"otro tipo no se entiende", `{"v":1,"tipo":"clientes-cambiados","sucursal":"STG"}`, "", false},
		{"no es JSON", `almacenes cambiaron`, "", false},
		{"vacío", ``, "", false},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			codigo, ok := Entender(c.crudo)
			if codigo != c.codigo || ok != c.entendido {
				t.Fatalf("Entender(%q) = (%q, %v); quería (%q, %v)", c.crudo, codigo, ok, c.codigo, c.entendido)
			}
		})
	}
}

// fuenteFalsa da, en cada conexión, los mensajes que se le hayan preparado y luego un error: así se
// prueba el bucle entero (leer, avisar, perder la conexión, reintentar) sin un Redis.
type fuenteFalsa struct {
	mu       sync.Mutex
	vidas    [][]string // mensajes de cada conexión; la última vida que se acaba da error y se reintenta
	conexion int
	cerrada  bool
}

func (f *fuenteFalsa) Suscribir(ctx context.Context) (Suscripcion, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.conexion++
	if f.conexion > len(f.vidas) {
		return nil, errors.New("sin más vidas")
	}
	return &suscripcionFalsa{msgs: f.vidas[f.conexion-1]}, nil
}
func (f *fuenteFalsa) Cerrar() error { f.cerrada = true; return nil }

type suscripcionFalsa struct{ msgs []string }

func (s *suscripcionFalsa) Siguiente(ctx context.Context) (string, error) {
	if len(s.msgs) == 0 {
		return "", errors.New("la conexión murió")
	}
	m := s.msgs[0]
	s.msgs = s.msgs[1:]
	return m, nil
}
func (s *suscripcionFalsa) Cerrar() error { return nil }

func corredor(t *testing.T, f Fuente, quiero int) (avisos []string) {
	t.Helper()
	esperaMin, esperaMax = time.Millisecond, 5*time.Millisecond
	ctx, parar := context.WithCancel(context.Background())
	defer parar()
	var mu sync.Mutex
	hecho := make(chan struct{})
	go func() {
		Correr(ctx, f, logMudo(), func(_ context.Context, codigo string) {
			mu.Lock()
			avisos = append(avisos, codigo)
			n := len(avisos)
			mu.Unlock()
			if n == quiero {
				parar()
			}
		})
		close(hecho)
	}()
	select {
	case <-hecho:
	case <-time.After(5 * time.Second):
		t.Fatal("Correr no terminó")
	}
	mu.Lock()
	defer mu.Unlock()
	return avisos
}

func TestCorrerAvisaUnaVezPorMensajeYConLaSucursal(t *testing.T) {
	f := &fuenteFalsa{vidas: [][]string{{
		`{"v":1,"tipo":"almacenes-cambiados","sucursal":"STG","tms":1}`,
		`{"v":1,"tipo":"almacenes-cambiados","sucursal":"cam","tms":2}`,
	}}}
	got := corredor(t, f, 2)
	if len(got) != 2 || got[0] != "STG" || got[1] != "CAM" {
		t.Fatalf("avisos = %v; quería [STG CAM]", got)
	}
	if !f.cerrada {
		t.Error("al terminar hay que cerrar la fuente")
	}
}

// El mensaje que no se entiende NO se ignora: se avisa «de todas» (código vacío). Ignorarlo mediría con
// el punto viejo de un almacén justo cuando alguien lo acaba de corregir, sin que nada lo dijera.
func TestUnMensajeQueNoSeEntiendeAvisaDeTodas(t *testing.T) {
	f := &fuenteFalsa{vidas: [][]string{{`esto no es JSON`, `{"v":9,"tipo":"otra-cosa"}`}}}
	got := corredor(t, f, 2)
	if len(got) != 2 || got[0] != "" || got[1] != "" {
		t.Fatalf("avisos = %q; los dos mensajes raros tenían que avisar de todas (código vacío)", got)
	}
}

// Si la conexión muere, reintenta y sigue oyendo: lo que se publique después tiene que llegar.
func TestSiSePierdeLaConexionReintentaYSigueOyendo(t *testing.T) {
	f := &fuenteFalsa{vidas: [][]string{
		{`{"v":1,"tipo":"almacenes-cambiados","sucursal":"STG"}`}, // y la conexión muere
		{`{"v":1,"tipo":"almacenes-cambiados","sucursal":"HOL"}`}, // la siguiente vida
	}}
	got := corredor(t, f, 2)
	if len(got) != 2 || got[0] != "STG" || got[1] != "HOL" {
		t.Fatalf("avisos = %v; tras perder la conexión tenía que seguir con HOL", got)
	}
	if f.conexion < 2 {
		t.Errorf("hubo %d conexiones; tenía que haber reconectado", f.conexion)
	}
}

// Sin Redis configurado no hay fuente: Correr lo dice y vuelve en el acto; la API sirve igual.
func TestSinFuenteCorrerVuelveEnElActo(t *testing.T) {
	hecho := make(chan struct{})
	go func() {
		Correr(context.Background(), nil, logMudo(), func(context.Context, string) { t.Error("sin fuente no se avisa") })
		close(hecho)
	}()
	select {
	case <-hecho:
	case <-time.After(2 * time.Second):
		t.Fatal("sin fuente, Correr tenía que volver en el acto")
	}
}

// Cancelar el contexto saca a Correr aunque la suscripción esté bloqueada esperando un mensaje.
func TestCancelarSacaACorrerDeLaLectura(t *testing.T) {
	ctx, parar := context.WithCancel(context.Background())
	bloqueada := &fuenteBloqueada{}
	hecho := make(chan struct{})
	go func() {
		Correr(ctx, bloqueada, logMudo(), func(context.Context, string) {})
		close(hecho)
	}()
	time.Sleep(20 * time.Millisecond)
	parar()
	select {
	case <-hecho:
	case <-time.After(2 * time.Second):
		t.Fatal("Correr no salió al cancelar el contexto")
	}
}

type fuenteBloqueada struct{}

func (fuenteBloqueada) Suscribir(context.Context) (Suscripcion, error) { return susBloqueada{}, nil }
func (fuenteBloqueada) Cerrar() error                                  { return nil }

type susBloqueada struct{}

func (susBloqueada) Siguiente(ctx context.Context) (string, error) {
	<-ctx.Done()
	return "", ctx.Err()
}
func (susBloqueada) Cerrar() error { return nil }
