package api

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/config"
)

// accesosQueCuenta monta el cliente HTTP REAL de Accesos contra un servidor falso que cuenta cuántas
// veces le piden la lista de almacenes. Es lo único que demuestra que la caché se tira de verdad: un
// doble de la interfaz no tiene caché.
func accesosQueCuenta(t *testing.T) *atomic.Int32 {
	t.Helper()
	var llamadas atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		llamadas.Add(1)
		w.Header().Set("content-type", "application/json")
		_, _ = w.Write([]byte(`{"sucursales":[{"codigo":"STG","nombre":"Santiago","almacenes":[` +
			`{"id":"a1","nombre":"AURORA","codigo":"2","latitud":20.03191,"longitud":-75.85058,"principal":true,"activo":true}]}]}`))
	}))
	t.Cleanup(srv.Close)

	anterior := Accesos
	t.Cleanup(func() { Accesos = anterior })
	Accesos = &accesosHTTP{cfg: &config.Config{
		AuthURL:        srv.URL,
		AuthClientID:   "reparto",
		AuthSigningKey: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
	}}
	return &llamadas
}

// avisosCapturados sustituye el gancho de aviso y devuelve lo que se avisó (la sucursal de cada aviso).
func avisosCapturados(t *testing.T) func() []string {
	t.Helper()
	var mu sync.Mutex
	var vistos []string
	anterior := avisarCambioDeAlmacenes
	t.Cleanup(func() { avisarCambioDeAlmacenes = anterior })
	avisarCambioDeAlmacenes = func(_ context.Context, sucursal string) {
		mu.Lock()
		vistos = append(vistos, sucursal)
		mu.Unlock()
	}
	return func() []string { mu.Lock(); defer mu.Unlock(); return append([]string(nil), vistos...) }
}

func conocidas(m map[string]uuid.UUID) func(context.Context, string) (uuid.UUID, bool) {
	return func(_ context.Context, codigo string) (uuid.UUID, bool) { id, ok := m[codigo]; return id, ok }
}

// EL CASO QUE ESTO VIENE A CERRAR. Tras un cambio en el CRM, la lista que Reparto recuerda es la VIEJA:
// sin el aviso, el cotizador seguiría midiendo desde el punto anterior hasta que caduque (5 min).
func TestElAvisoDelCRMTiraLaCacheDeAlmacenes(t *testing.T) {
	llamadas := accesosQueCuenta(t)
	_ = avisosCapturados(t)
	ctx := context.Background()

	if _, err := Accesos.AlmacenesDeSucursal(ctx, "STG"); err != nil {
		t.Fatal(err)
	}
	if _, err := Accesos.AlmacenesDeSucursal(ctx, "STG"); err != nil {
		t.Fatal(err)
	}
	if n := llamadas.Load(); n != 1 {
		t.Fatalf("la segunda pregunta tenía que salir de la caché: %d llamadas a Accesos", n)
	}

	CambiaronLosAlmacenes(ctx, conocidas(nil), "STG")

	if _, err := Accesos.AlmacenesDeSucursal(ctx, "STG"); err != nil {
		t.Fatal(err)
	}
	if n := llamadas.Load(); n != 2 {
		t.Fatalf("tras el aviso del CRM la lista tenía que volver a pedirse a Accesos: %d llamadas (quería 2)", n)
	}
}

// El aviso a las pantallas sale CON la sucursal del cambio y a nadie más: un aviso sin sucursal manda
// a las otras siete a pedir la lista por nada (trampa del 01/10/2026).
func TestElAvisoDelCRMAvisaSoloASuSucursal(t *testing.T) {
	_ = accesosQueCuenta(t)
	avisados := avisosCapturados(t)
	stg := uuid.MustParse("11111111-1111-1111-1111-111111111111")

	CambiaronLosAlmacenes(context.Background(), conocidas(map[string]uuid.UUID{"STG": stg}), "STG")

	got := avisados()
	if len(got) != 1 || got[0] != stg.String() {
		t.Fatalf("avisos = %v; quería solo la sucursal de Santiago (%s)", got, stg)
	}
}

// Ante la duda, tira y avisa de todas: un código vacío (mensaje que no se entendió, o aviso sin
// sucursal) y una sucursal que Reparto no conoce (MOA, PLS: existen en Accesos, no aquí).
func TestAnteLaDudaAvisaDeTodas(t *testing.T) {
	casos := map[string]string{
		"el aviso no se entendió o no trae sucursal": "",
		"una sucursal que Reparto no conoce":         "PLS",
	}
	for nombre, codigo := range casos {
		t.Run(nombre, func(t *testing.T) {
			llamadas := accesosQueCuenta(t)
			avisados := avisosCapturados(t)
			ctx := context.Background()
			if _, err := Accesos.AlmacenesDeSucursal(ctx, "STG"); err != nil {
				t.Fatal(err)
			}

			CambiaronLosAlmacenes(ctx, conocidas(map[string]uuid.UUID{"STG": uuid.New()}), codigo)

			got := avisados()
			if len(got) != 1 || got[0] != DeTodasLasSucursales {
				t.Fatalf("avisos = %q; ante la duda tenía que avisar de todas (%q)", got, DeTodasLasSucursales)
			}
			if _, err := Accesos.AlmacenesDeSucursal(ctx, "STG"); err != nil {
				t.Fatal(err)
			}
			if n := llamadas.Load(); n != 2 {
				t.Fatalf("también tenía que tirar la caché: %d llamadas a Accesos (quería 2)", n)
			}
		})
	}
}

// Un cliente de Accesos que no sabe olvidar (un doble de las pruebas) no rompe nada: el aviso a las
// pantallas sale igual.
func TestUnClienteSinOlvidarNoImpideElAviso(t *testing.T) {
	anterior := Accesos
	t.Cleanup(func() { Accesos = anterior })
	Accesos = &accesosFalso{}
	avisados := avisosCapturados(t)

	CambiaronLosAlmacenes(context.Background(), conocidas(nil), "")

	if got := avisados(); len(got) != 1 {
		t.Fatalf("avisos = %v; el aviso a las pantallas tenía que salir igual", got)
	}
}

// accesosQueSeDetiene es un Accesos cuya PRIMERA respuesta se queda esperando hasta que se suelte: es la
// lectura que ya salió cuando llega el aviso del CRM.
func accesosQueSeDetiene(t *testing.T) (llamadas *atomic.Int32, entro, soltar chan struct{}) {
	t.Helper()
	llamadas, entro, soltar = new(atomic.Int32), make(chan struct{}), make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if llamadas.Add(1) == 1 {
			close(entro)
			<-soltar
		}
		w.Header().Set("content-type", "application/json")
		_, _ = w.Write([]byte(`{"sucursales":[{"codigo":"STG","nombre":"Santiago","almacenes":[` +
			`{"id":"a1","nombre":"AURORA","codigo":"2","latitud":20.03191,"longitud":-75.85058,"principal":true,"activo":true}]}]}`))
	}))
	t.Cleanup(srv.Close)
	anterior := Accesos
	t.Cleanup(func() { Accesos = anterior })
	Accesos = &accesosHTTP{cfg: &config.Config{
		AuthURL:        srv.URL,
		AuthClientID:   "reparto",
		AuthSigningKey: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
	}}
	return llamadas, entro, soltar
}

// LAS DOS CARRERAS DE LA AUDITORÍA DEL 20/10/2026 (S2), con una lectura detenida a medias:
//
//	(a) un `Olvidar()` entre pedir y leer dejaba `c.recuerdo` en nil, y `c.recuerdo[clave]` contestaba la
//	    lista VACÍA sin error: la cotización medía como «esta sucursal no tiene almacenes»;
//	(b) esa lectura, que empezó ANTES del aviso, guardaba al terminar la lista de antes del cambio: el
//	    punto viejo cinco minutos más, que es lo que el aviso viene a evitar.
func TestUnAvisoDelCRMEnMitadDeUnaLecturaNoDejaLaListaVaciaNiLaVieja(t *testing.T) {
	llamadas, entro, soltar := accesosQueSeDetiene(t)
	_ = avisosCapturados(t)
	ctx := context.Background()

	resultado := make(chan []Almacen, 1)
	go func() {
		lista, err := Accesos.AlmacenesDeSucursal(ctx, "STG")
		if err != nil {
			t.Error(err)
		}
		resultado <- lista
	}()
	<-entro // la lectura ya salió hacia Accesos y está esperando

	CambiaronLosAlmacenes(ctx, conocidas(nil), "STG") // llega el aviso del CRM
	close(soltar)

	if lista := <-resultado; len(lista) != 1 || lista[0].Nombre != "AURORA" {
		t.Fatalf("la lectura en vuelo contestó %v; (a) no puede ser la lista vacía: tenía que traer lo que contestó Accesos", lista)
	}
	if _, err := Accesos.AlmacenesDeSucursal(ctx, "STG"); err != nil {
		t.Fatal(err)
	}
	if n := llamadas.Load(); n != 2 {
		t.Fatalf("%d llamadas a Accesos; (b) la respuesta que empezó antes del aviso NO se puede guardar: "+
			"la siguiente pregunta tenía que volver a Accesos (quería 2)", n)
	}
}
