// Las pruebas del canal de salida hacia PEDIDO.
//
// Sin PEDIDO y sin red: el otro lado es un `httptest.Server` que contesta lo que haga
// falta para cada caso —incluido no contestar—. Lo que se prueba aquí es lo que el
// original de delivery resuelve y no se puede perder al pasarlo a Go:
//
//   - que la hora que sale es LA DEL SUCESO y no la de la llamada;
//   - que si PEDIDO no contesta la ruta sigue y QUEDA DICHO en el registro;
//   - que va en lote, que es idempotente y que nunca dice `ok` sin haber avisado.
package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/config"
)

// laHoraDelPatio es la hora a la que se marcó el cierre: las 16:04 de una tarde, en un
// patio sin señal. La cola sube a las 19:30, pero en PEDIDO tiene que decir 16:04.
var laHoraDelPatio = time.Date(2026, 9, 14, 16, 4, 22, 0, time.UTC)

// llamarConCabeceras es `llamarRutas` pero dejando poner cabeceras, que es por donde viaja
// la hora del aparato (`X-Hecho-At`).
func llamarConCabeceras(t *testing.T, h http.Handler, metodo, ruta, jwt, cuerpo string, cab map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	var lector io.Reader
	if cuerpo != "" {
		lector = strings.NewReader(cuerpo)
	}
	r := httptest.NewRequest(metodo, ruta, lector)
	if jwt != "" {
		r.Header.Set("Authorization", "Bearer "+jwt)
	}
	if cuerpo != "" {
		r.Header.Set("Content-Type", "application/json")
	}
	for k, v := range cab {
		r.Header.Set(k, v)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

// canalDePrueba monta el canal de verdad contra un destino cualquiera.
func canalDePrueba(destino, clave string, reg *slog.Logger) CanalAPedido {
	return nuevoCanalAPedido(&config.Config{PedidoAPIURL: destino, ServiceAPIKey: clave}, reg)
}

// registroSeguro es un buffer con candado.
//
// HACE FALTA: el aviso de «despachado» del armado sale en una goroutine de fondo y escribe
// en el registro a la vez que lo hace la petición del cierre. Un `bytes.Buffer` pelado no
// aguanta dos escritores, y el detector de carreras lo caza —con razón: la prueba leería
// un registro a medio escribir—.
type registroSeguro struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (r *registroSeguro) Write(p []byte) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.buf.Write(p)
}

func (r *registroSeguro) String() string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.buf.String()
}

func registroDePrueba() (*slog.Logger, *registroSeguro) {
	var buf registroSeguro
	return slog.New(slog.NewTextHandler(&buf, nil)), &buf
}

// ---------------------------------------------------------------------------
// LA HORA DEL SUCESO
// ---------------------------------------------------------------------------

// LO QUE SE MARCA A LAS CUATRO LLEGA COMO LAS CUATRO, aunque suba a las siete y media.
//
// Es la prueba de la razón de ser del campo `at`. El logístico cierra la ruta en un patio
// sin cobertura a las 16:04; la cola del aparato sube a las 19:30 y el sincronizador
// reenvía el apunte con `X-Hecho-At`. En PEDIDO el vendedor tiene que ver cuándo recibió su
// cliente, no cuándo pilló señal el teléfono.
func TestElAvisoLlevaLaHoraDelSucesoYNoLaDeLaLlamada(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h, s := montarRutasCon(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1])

	var candado sync.Mutex
	var visto []AvisoDeParada
	s.aPedido = func(_ context.Context, avisos []AvisoDeParada) ParteAPedido {
		candado.Lock()
		visto = append(visto, avisos...)
		candado.Unlock()
		return ParteAPedido{Ok: true, Enviados: len(avisos), Aplicados: len(avisos)}
	}

	antesDeLlamar := time.Now().UTC()
	cuerpo := fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, stg[1])
	w := llamarConCabeceras(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo,
		map[string]string{"X-Hecho-At": laHoraDelPatio.Format(time.RFC3339Nano)})
	if w.Code != http.StatusOK {
		t.Fatalf("el cierre tenía que ir bien: %d %s", w.Code, w.Body.String())
	}

	candado.Lock()
	defer candado.Unlock()
	var entregado *AvisoDeParada
	for i, a := range visto {
		if a.Estado == "entregado" {
			entregado = &visto[i]
		}
	}
	if entregado == nil {
		t.Fatalf("a PEDIDO no le llegó el entregado: %+v", visto)
	}
	if !entregado.At.Equal(laHoraDelPatio) {
		t.Fatalf("la hora que salió es %s y tenía que ser la del suceso, %s",
			entregado.At.Format(time.RFC3339), laHoraDelPatio.Format(time.RFC3339))
	}
	// Y que no sea, «por casualidad», la de ahora: si alguien quitara la lectura de la
	// cabecera, `At` sería la hora de la llamada y la comparación de arriba fallaría —pero
	// esta segunda lo dice con todas las letras y no depende de que la fecha sea antigua.
	if !entregado.At.Before(antesDeLlamar) {
		t.Fatalf("la hora del aviso (%s) no es anterior a la de la llamada (%s): se mandó la de la llamada",
			entregado.At.Format(time.RFC3339), antesDeLlamar.Format(time.RFC3339))
	}
}

// Y la hora tiene que llegar hasta el CUERPO que se le manda a PEDIDO, no quedarse en la
// estructura de Go. Ésta es la prueba de extremo a extremo, con el canal de verdad.
func TestElCuerpoQueLlegaAPedidoLlevaElAtDelSuceso(t *testing.T) {
	recibido := make(chan []byte, 4)
	pedido := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != RutaEstadoEnPedido {
			t.Errorf("PEDIDO recibió la petición en %q y esperaba %q", r.URL.Path, RutaEstadoEnPedido)
		}
		if r.Header.Get("x-api-key") != "la-clave" {
			t.Errorf("no llegó la clave de servicio: %q", r.Header.Get("x-api-key"))
		}
		crudo, _ := io.ReadAll(r.Body)
		recibido <- crudo
		_, _ = w.Write([]byte(`{"aplicados":[{"pedidoId":"PED-2"}],"rechazados":[]}`))
	}))
	defer pedido.Close()

	reg, _ := registroDePrueba()
	canal := canalDePrueba(pedido.URL, "la-clave", reg)

	parte := canal(context.Background(), []AvisoDeParada{
		{PedidoID: "PED-2", Estado: "entregado", At: laHoraDelPatio},
	})
	if !parte.Ok || parte.Enviados != 1 || parte.Aplicados != 1 {
		t.Fatalf("el parte salió %+v", parte)
	}

	var sobre struct {
		Pedidos []struct {
			PedidoID string `json:"pedidoId"`
			Estado   string `json:"estado"`
			At       string `json:"at"`
		} `json:"pedidos"`
	}
	crudo := <-recibido
	if err := json.Unmarshal(crudo, &sobre); err != nil {
		t.Fatalf("el cuerpo no se entiende: %v (%s)", err, crudo)
	}
	if len(sobre.Pedidos) != 1 {
		t.Fatalf("llegaron %d pedidos: %s", len(sobre.Pedidos), crudo)
	}
	if sobre.Pedidos[0].At != "2026-09-14T16:04:22Z" {
		t.Fatalf("el `at` que llegó es %q y tenía que ser la hora del suceso: %s",
			sobre.Pedidos[0].At, crudo)
	}
}

// Sin hora del aparato —el caso normal, con señal— el `at` es el de ahora. Lo que NO puede
// pasar es que vaya el año 1: un `time.Time` vacío serializado sin cuidado pone 0001-01-01
// y PEDIDO se creería esa fecha.
func TestSinCabeceraElAtEsElDeAhoraYNuncaElAnoUno(t *testing.T) {
	r := httptest.NewRequest(http.MethodPost, "/api/routes/x/results", nil)
	cuando := horaDelSuceso(r)
	if time.Since(cuando) > time.Minute {
		t.Fatalf("sin cabecera la hora tenía que ser la de ahora, y fue %s", cuando)
	}

	// Y una cabecera ilegible tampoco se cuela: se cae a la de ahora.
	r.Header.Set("X-Hecho-At", "ayer por la tarde")
	if cuando := horaDelSuceso(r); time.Since(cuando) > time.Minute {
		t.Fatalf("una cabecera ilegible tenía que caer en la hora de ahora, y dio %s", cuando)
	}

	// Un aviso sin hora no manda el campo, en vez de mandar el año 1.
	crudo, err := json.Marshal(AvisoDeParada{PedidoID: "PED-1", Estado: "despachado"})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(crudo), "0001-01-01") {
		t.Fatalf("un aviso sin hora mandó la fecha del año 1: %s", crudo)
	}
	if strings.Contains(string(crudo), `"at"`) {
		t.Fatalf("un aviso sin hora tenía que omitir `at`: %s", crudo)
	}
}

// ---------------------------------------------------------------------------
// «LO MEJOR QUE SE PUEDA»: si PEDIDO no contesta, aquí no se rompe nada
// ---------------------------------------------------------------------------

// EL CIERRE SE GUARDA AUNQUE PEDIDO ESTÉ CAÍDO, Y QUEDA DICHO.
//
// Las dos mitades importan lo mismo. Si se rompiera, un camión que volvió con nueve
// entregas no podría cerrar la ruta porque otra aplicación está caída; si no quedara
// dicho, nadie sabría nunca que el vendedor no se enteró.
func TestSiPedidoNoContestaElCierreSigueYQuedaEnElRegistro(t *testing.T) {
	// PEDIDO contesta 503: está en pie pero no puede con esto.
	pedido := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "estoy caído", http.StatusServiceUnavailable)
	}))
	defer pedido.Close()

	d, stg, _ := datosDeReparto()
	var registro registroSeguro
	h, s := montarRutasRegistrando(t, d, &registro)
	reg := slog.New(slog.NewTextHandler(&registro, nil))
	s.aPedido = canalDePrueba(pedido.URL, "la-clave", reg)

	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1])

	cuerpo := fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, stg[1])
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)

	// 1. LA RUTA SIGUE SU CURSO: 200, y el resultado guardado.
	if w.Code != http.StatusOK {
		t.Fatalf("PEDIDO caído no puede tumbar el cierre: %d %s", w.Code, w.Body.String())
	}
	var salida salidaDeCierre
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	// `Resultado` es un puntero desde el 28/09/2026: `null` es «se quitó la marca», que no
	// es un resultado. Aquí se marcó de verdad, así que tiene que venir con valor.
	if len(salida.Aplicados) != 1 || salida.Aplicados[0].Resultado == nil ||
		*salida.Aplicados[0].Resultado != "entregado" {
		t.Fatalf("el cierre tenía que quedar guardado igual: %+v", salida.Aplicados)
	}

	// 2. Y NO MIENTE: el parte dice que no se pudo, con el motivo dentro.
	if salida.APedido.Ok {
		t.Fatalf("el parte dijo que sí con PEDIDO caído: %+v", salida.APedido)
	}
	if !strings.Contains(salida.APedido.Error, "503") {
		t.Fatalf("el motivo tenía que decir qué contestó PEDIDO: %q", salida.APedido.Error)
	}

	// 3. Y QUEDA DICHO EN EL REGISTRO. Nunca en silencio.
	texto := registro.String()
	if !strings.Contains(texto, "PEDIDO no tomó una tanda de estados") {
		t.Fatalf("el canal no dejó el fallo en el registro:\n%s", texto)
	}
	if !strings.Contains(texto, "el cierre se guardó pero PEDIDO no se enteró") {
		t.Fatalf("el cierre no dejó el fallo en el registro:\n%s", texto)
	}
}

// Y lo mismo al ARMAR la ruta, que es el otro sitio donde se avisa. Aquí el aviso va de
// fondo, así que lo que se comprueba es que quien pulsa el botón recibe su 201 igual.
func TestSiPedidoNoContestaLaRutaSeArmaIgual(t *testing.T) {
	// Un destino que no existe: ni siquiera hay quien conteste.
	d, stg, _ := datosDeReparto()
	var registro registroSeguro
	h, s := montarRutasRegistrando(t, d, &registro)
	reg := slog.New(slog.NewTextHandler(&registro, nil))
	s.aPedido = canalDePrueba("http://127.0.0.1:1", "la-clave", reg)

	jwt := deSantiagoEnRutas(t)
	w := llamarRutas(t, h, http.MethodPost, "/api/routes", jwt,
		cuerpoDeArmado(camionStg.String(), stg[1]))
	if w.Code != http.StatusCreated {
		t.Fatalf("con PEDIDO inalcanzable la ruta se arma igual: %d %s", w.Code, w.Body.String())
	}
}

// Sin URL de PEDIDO el canal NO MIENTE: no dice `ok` y deja el motivo escrito.
//
// Un aviso que nadie recibe y que además se declara enviado es peor que no avisar, porque
// nadie lo busca. Es lo que ya pasó con el canal de Entrega.
func TestSinConfiguracionElCanalNoDiceQueSi(t *testing.T) {
	casos := []struct {
		nombre string
		cfg    *config.Config
		trozo  string
	}{
		{"sin url", &config.Config{ServiceAPIKey: "k"}, "no hay canal a PEDIDO"},
		{"sin clave", &config.Config{PedidoAPIURL: "http://pedido"}, "falta SERVICE_API_KEY"},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			reg, buf := registroDePrueba()
			parte := nuevoCanalAPedido(c.cfg, reg)(context.Background(),
				[]AvisoDeParada{{PedidoID: "PED-1", Estado: "despachado", At: laHoraDelPatio}})
			if parte.Ok {
				t.Fatalf("dijo que sí sin poder avisar: %+v", parte)
			}
			if parte.Enviados != 1 || parte.Aplicados != 0 {
				t.Fatalf("las cuentas del parte no cuadran: %+v", parte)
			}
			if !strings.Contains(parte.Error, c.trozo) {
				t.Fatalf("el motivo %q no dice %q", parte.Error, c.trozo)
			}
			if !strings.Contains(buf.String(), "no se pudo avisar a PEDIDO") {
				t.Fatalf("no quedó en el registro:\n%s", buf.String())
			}
		})
	}
}

// ---------------------------------------------------------------------------
// EL LOTE
// ---------------------------------------------------------------------------

// Va en tandas de 200 y NO ABORTA en la primera que falla: las que vienen detrás son
// pedidos distintos y no tienen la culpa. `aplicados` cuenta lo que sí entró.
func TestElCanalVaEnTandasYSigueAunqueUnaFalle(t *testing.T) {
	var mu sync.Mutex
	var tandas []int
	vuelta := 0
	pedido := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var sobre struct {
			Pedidos []json.RawMessage `json:"pedidos"`
		}
		crudo, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(crudo, &sobre)

		mu.Lock()
		tandas = append(tandas, len(sobre.Pedidos))
		vuelta++
		esLaSegunda := vuelta == 2
		mu.Unlock()

		if esLaSegunda {
			http.Error(w, "no puedo con ésta", http.StatusInternalServerError)
			return
		}
		aplicados := make([]string, len(sobre.Pedidos))
		cuerpo, _ := json.Marshal(map[string]any{"aplicados": aplicados})
		_, _ = w.Write(cuerpo)
	}))
	defer pedido.Close()

	// 450 avisos: dos tandas de 200 y una de 50.
	avisos := make([]AvisoDeParada, 0, 450)
	for i := range 450 {
		avisos = append(avisos, AvisoDeParada{
			PedidoID: fmt.Sprintf("PED-%d", i), Estado: estadoDespachado, At: laHoraDelPatio,
		})
	}

	reg, buf := registroDePrueba()
	parte := canalDePrueba(pedido.URL, "k", reg)(context.Background(), avisos)

	mu.Lock()
	defer mu.Unlock()
	if len(tandas) != 3 || tandas[0] != TandaAPedido || tandas[1] != TandaAPedido || tandas[2] != 50 {
		t.Fatalf("las tandas salieron %v y tenían que ser [200 200 50]", tandas)
	}
	if parte.Ok {
		t.Fatalf("una tanda falló: el parte no puede decir que sí (%+v)", parte)
	}
	if parte.Enviados != 450 {
		t.Fatalf("enviados = %d, y se le dieron 450", parte.Enviados)
	}
	// Las otras DOS sí entraron: 200 + 50. Si se hubiera abortado en la segunda, serían 200.
	if parte.Aplicados != 250 {
		t.Fatalf("aplicados = %d: se abortó en la tanda mala en vez de seguir", parte.Aplicados)
	}
	if !strings.Contains(buf.String(), "PEDIDO no tomó una tanda") {
		t.Fatalf("la tanda que falló no quedó en el registro:\n%s", buf.String())
	}
}

// Un lote vacío no llama a nadie. Armar una ruta con pedidos tecleados a mano es un caso
// normal y no tiene a quién avisar.
func TestUnLoteVacioNoLlamaANadie(t *testing.T) {
	llamadas := 0
	pedido := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		llamadas++
		_, _ = w.Write([]byte(`{"aplicados":[]}`))
	}))
	defer pedido.Close()

	reg, _ := registroDePrueba()
	parte := canalDePrueba(pedido.URL, "k", reg)(context.Background(), nil)
	if !parte.Ok || parte.Enviados != 0 {
		t.Fatalf("un lote vacío es un éxito de cero avisos: %+v", parte)
	}
	if llamadas != 0 {
		t.Fatalf("llamó a PEDIDO %d veces con el lote vacío", llamadas)
	}
}

// IDEMPOTENCIA. El aviso dice en qué punto ESTÁ el pedido, no qué le acaba de pasar, así
// que repetirlo no cuenta nada dos veces. Dentro de un mismo lote, además, el repetido
// idéntico no se manda: cada uno le cuesta a PEDIDO una escritura y un aviso en vivo.
func TestElRepetidoIdenticoNoSeMandaDosVeces(t *testing.T) {
	mismo := AvisoDeParada{PedidoID: "PED-2", Estado: "entregado", At: laHoraDelPatio}
	// Pero dos hechos DISTINTOS del mismo pedido son dos avisos, y los dos tienen que ir.
	otroEstado := AvisoDeParada{PedidoID: "PED-2", Estado: "devuelto", At: laHoraDelPatio}
	otraHora := AvisoDeParada{PedidoID: "PED-2", Estado: "entregado", At: laHoraDelPatio.Add(time.Hour)}

	salida := sinRepetidos([]AvisoDeParada{mismo, mismo, otroEstado, mismo, otraHora})
	if len(salida) != 3 {
		t.Fatalf("quedaron %d avisos y tenían que quedar 3: %+v", len(salida), salida)
	}
	if salida[0] != mismo || salida[1] != otroEstado || salida[2] != otraHora {
		t.Fatalf("se perdió el orden o un hecho distinto: %+v", salida)
	}
}

// Un 200 con `rechazados` NO es un éxito: se guarda el PRIMER motivo, que es lo que cabe
// en una pantalla, y `aplicados` sigue contando lo que sí entró.
func TestUnRechazoDePedidoSaleEnElParte(t *testing.T) {
	pedido := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"aplicados":[{"x":1}],"rechazados":[{"motivo":"ese pedido no existe aquí"},{"motivo":"otro"}]}`))
	}))
	defer pedido.Close()

	reg, _ := registroDePrueba()
	parte := canalDePrueba(pedido.URL, "k", reg)(context.Background(), []AvisoDeParada{
		{PedidoID: "PED-1", Estado: estadoDespachado, At: laHoraDelPatio},
		{PedidoID: "PED-9", Estado: estadoDespachado, At: laHoraDelPatio},
	})
	if parte.Ok {
		t.Fatalf("con rechazados el parte no puede decir que sí: %+v", parte)
	}
	if parte.Error != "ese pedido no existe aquí" {
		t.Fatalf("tenía que guardarse el PRIMER motivo, y guardó %q", parte.Error)
	}
	if parte.Aplicados != 1 {
		t.Fatalf("aplicados = %d y PEDIDO dijo que aplicó 1", parte.Aplicados)
	}
}

// Un 200 con un cuerpo que no se entiende NO se cuenta como aplicado: contarlo sería dar
// por contado lo que no consta en ningún sitio.
func TestUnCuerpoIlegibleNoCuentaComoAplicado(t *testing.T) {
	pedido := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`<html>no soy json</html>`))
	}))
	defer pedido.Close()

	reg, _ := registroDePrueba()
	parte := canalDePrueba(pedido.URL, "k", reg)(context.Background(),
		[]AvisoDeParada{{PedidoID: "PED-1", Estado: estadoDespachado, At: laHoraDelPatio}})
	if parte.Ok || parte.Aplicados != 0 {
		t.Fatalf("un cuerpo ilegible no es un aviso aplicado: %+v", parte)
	}
}

// El estado que sale al ARMAR es `despachado` y lleva su hora: es el momento en que el
// pedido se carga en el camión.
func TestAlArmarSaleDespachadoConSuHora(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h, s := montarRutasCon(t, d)

	var candado sync.Mutex
	var visto []AvisoDeParada
	llegaron := make(chan struct{}, 1)
	s.aPedido = func(_ context.Context, avisos []AvisoDeParada) ParteAPedido {
		candado.Lock()
		visto = append(visto, avisos...)
		candado.Unlock()
		select {
		case llegaron <- struct{}{}:
		default:
		}
		return ParteAPedido{Ok: true, Enviados: len(avisos), Aplicados: len(avisos)}
	}

	jwt := deSantiagoEnRutas(t)
	w := llamarConCabeceras(t, h, http.MethodPost, "/api/routes", jwt,
		cuerpoDeArmado(camionStg.String(), stg[1]),
		map[string]string{"X-Hecho-At": laHoraDelPatio.Format(time.RFC3339Nano)})
	if w.Code != http.StatusCreated {
		t.Fatalf("no se armó la ruta: %d %s", w.Code, w.Body.String())
	}

	// El aviso del armado sale de fondo: se espera a que llegue en vez de dormir.
	select {
	case <-llegaron:
	case <-time.After(2 * time.Second):
		t.Fatal("el aviso de despachado no salió")
	}

	candado.Lock()
	defer candado.Unlock()
	if len(visto) == 0 {
		t.Fatal("no salió ningún aviso al armar")
	}
	for _, a := range visto {
		if a.Estado != estadoDespachado {
			t.Fatalf("al armar tenía que salir %q y salió %q", estadoDespachado, a.Estado)
		}
		if !a.At.Equal(laHoraDelPatio) {
			t.Fatalf("el despachado salió con la hora %s en vez de la del suceso %s",
				a.At.Format(time.RFC3339), laHoraDelPatio.Format(time.RFC3339))
		}
	}
}

// Guardia: que el uuid no se use sin querer y el paquete siga compilando igual.
var _ = uuid.Nil
