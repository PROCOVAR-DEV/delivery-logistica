package api

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// LA PUERTA POR DONDE PEDIDO TOCA: `POST /api/webhooks/pedido`.
//
// LO QUE ESTAS PRUEBAS DEFIENDEN, y cada una es un fallo que ya cuesta caro en otro sitio:
//
//  1. **Sin firma no entra nada.** Es la única cosa que separa «PEDIDO me avisó» de
//     «cualquiera con la URL me metió un pedido en un camión».
//  2. **Sin configurar contesta 503 y NO 401.** Los dos «no entras» son opuestos para el que
//     llama: PEDIDO descarta el 401 a la primera y reintenta el 5xx. Si un despiste de
//     despliegue NUESTRO —el secreto sin poner— contestara 401, PEDIDO tiraría cada aviso al
//     primer intento y nadie se enteraría de qué pedidos se perdieron.
//  3. **Lo que no lleva a nada es 200, no un error.** Un cliente sin coordenadas o un pedido
//     que todavía no es repartible son el sistema haciendo lo correcto. Contestar error haría
//     que PEDIDO reintentara tres veces algo que va a dar lo mismo, y que lo contara como
//     fallo en su pantalla — enseñando a ignorar su propio rojo.
//  4. **Un motivo DESCONOCIDO con pedido dentro se guarda.** Es una versión nueva de PEDIDO
//     contra una vieja de esto: descartarlo sería perder el pedido sin un solo error.
//  5. **La constancia se apunta también cuando se rechaza.** Sin la fila, un PEDIDO que manda
//     y un reparto que rechaza todo se ven exactamente igual desde la pantalla del canal.
//
// LA FORMA: se cuenta lo que se ESCRIBE, no sólo el código de la respuesta. Un 200 con cero
// escrituras es lo más parecido que hay a que todo vaya bien, y es justo cuando hay que
// mirar — es la regla del §3 del `CLAUDE.md` de este repo.

const (
	claveDePruebas   = "rp_clave_de_pruebas"
	secretoDePruebas = "un-secreto-de-webhook-de-pruebas"
)

// --------------------------------------------------------------------------- la firma

func TestSinFirmaBuenaNoEntraNada(t *testing.T) {
	cuerpo := `{"aviso":{"avisoId":"1-0","motivo":"borrado","id":"PED-1"}}`

	casos := []struct {
		nombre string
		clave  string
		firma  string
		quiere int
	}{
		{"la clave equivocada", "rp_otra", firmarDePruebas(secretoDePruebas, cuerpo), http.StatusUnauthorized},
		{"sin clave", "", firmarDePruebas(secretoDePruebas, cuerpo), http.StatusUnauthorized},
		{"sin firma", claveDePruebas, "", http.StatusUnauthorized},
		{"el secreto equivocado", claveDePruebas, firmarDePruebas("otro-secreto", cuerpo), http.StatusUnauthorized},
		{"la firma de OTRO cuerpo", claveDePruebas, firmarDePruebas(secretoDePruebas, `{"aviso":{}}`), http.StatusUnauthorized},
		{"sin el prefijo sha256=", claveDePruebas,
			strings.TrimPrefix(firmarDePruebas(secretoDePruebas, cuerpo), "sha256="), http.StatusUnauthorized},
		{"la firma que no es hexadecimal", claveDePruebas, "sha256=no-es-hex", http.StatusUnauthorized},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			h, q, _ := montarLaPuerta(t, nil)
			w := tocarLaPuerta(t, h, c.clave, c.firma, cuerpo)

			if w.Code != c.quiere {
				t.Fatalf("entró con %s: %d %s", c.nombre, w.Code, w.Body.String())
			}
			// Y NO TOCÓ LA BASE. Sin esto, «contestó 401» se cumple habiendo borrado el
			// pedido primero y rechazando después, que es el peor de los dos mundos.
			if q.quitados > 0 {
				t.Fatalf("rechazó la petición PERO quitó %d pedidos antes", q.quitados)
			}
		})
	}
}

// LA OTRA MITAD, y sin ella «no entra nada» se cumple con la puerta tapiada: entonces PEDIDO
// recibe 401 en todo, lo descarta a la primera y se pierde cada aviso.
func TestConLaFirmaBuenaEntra(t *testing.T) {
	cuerpo := `{"aviso":{"avisoId":"1-0","motivo":"borrado","id":"PED-1"}}`
	h, q, _ := montarLaPuerta(t, nil)

	w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)

	if w.Code != http.StatusOK {
		t.Fatalf("la firma era buena y no entró: %d %s", w.Code, w.Body.String())
	}
	if q.quitados != 1 {
		t.Fatalf("contestó 200 y NO quitó el pedido: quitados=%d", q.quitados)
	}
	if r := leerLaRespuesta(t, w.Body.String()); r.Aplicados != 1 {
		t.Fatalf("dijo que aplicó %d y tenía que ser 1: %s", r.Aplicados, w.Body.String())
	}
}

// LA FIRMA VA SOBRE LOS BYTES EXACTOS, no sobre el JSON reserializado.
//
// Dos serializaciones del mismo objeto se diferencian en el orden de las claves o en un
// espacio, y entonces la firma no cuadra JAMÁS por un motivo que no se ve en ningún registro:
// los dos lados juran tener el mismo secreto. Esta prueba fija que lo que se firma es el
// cuerpo tal como viajó.
func TestLaFirmaEsSobreElCuerpoExacto(t *testing.T) {
	conEspacios := `{ "aviso" : {"avisoId":"1-0","motivo":"borrado","id":"PED-1"} }`
	h, q, _ := montarLaPuerta(t, nil)

	// Firmado CON los espacios y enviado CON los espacios: cuadra.
	w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, conEspacios), conEspacios)
	if w.Code != http.StatusOK {
		t.Fatalf("el mismo cuerpo firmado y enviado no cuadró: %d %s", w.Code, w.Body.String())
	}
	if q.quitados != 1 {
		t.Fatalf("no se aplicó: quitados=%d", q.quitados)
	}

	// Firmado SIN los espacios y enviado CON ellos: no cuadra. Es el fallo de reserializar.
	sinEspacios := `{"aviso":{"avisoId":"1-0","motivo":"borrado","id":"PED-1"}}`
	h2, q2, _ := montarLaPuerta(t, nil)
	w2 := tocarLaPuerta(t, h2, claveDePruebas, firmarDePruebas(secretoDePruebas, sinEspacios), conEspacios)
	if w2.Code != http.StatusUnauthorized {
		t.Fatalf("aceptó una firma calculada sobre OTROS bytes: %d %s", w2.Code, w2.Body.String())
	}
	if q2.quitados != 0 {
		t.Fatalf("además aplicó el aviso: quitados=%d", q2.quitados)
	}
}

// --------------------------------------------------------------------------- sin configurar

// SIN LA PAREJA PUESTA: 503, y NO 401. Ver el punto 2 de la cabecera.
func TestSinLaParejaPuestaSeReintenta(t *testing.T) {
	cuerpo := `{"aviso":{"avisoId":"1-0","motivo":"borrado","id":"PED-1"}}`
	h, q, _ := montarLaPuerta(t, func(t *testing.T) {
		t.Setenv("PEDIDO_WEBHOOK_KEY", "")
		t.Setenv("PEDIDO_WEBHOOK_SECRET", "")
	})

	w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)

	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("sin configurar tiene que contestar 503 para que PEDIDO REINTENTE y no "+
			"tire el aviso; contestó %d %s", w.Code, w.Body.String())
	}
	if q.quitados > 0 {
		t.Fatalf("sin poder comprobar la firma, aplicó el aviso igual: quitados=%d", q.quitados)
	}
}

// Y con SÓLO una de las dos, tampoco. La key sola no comprueba nada: viaja en claro.
func TestConLaKeySolaTampoco(t *testing.T) {
	cuerpo := `{"aviso":{"avisoId":"1-0","motivo":"borrado","id":"PED-1"}}`
	h, _, _ := montarLaPuerta(t, func(t *testing.T) {
		t.Setenv("PEDIDO_WEBHOOK_SECRET", "")
	})

	w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)

	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("con la key sola dio por bueno el aviso: %d %s", w.Code, w.Body.String())
	}
}

// --------------------------------------------------------------------------- los motivos

// `borrado` y `ya_no_va` quitan el pedido. SON DOS SUCESOS DISTINTOS y la reacción es la
// misma: si se queda, alguien lo mete en un camión y nadie lo echa en falta.
func TestLosDosMotivosDeQuitarQuitan(t *testing.T) {
	for _, motivo := range []string{"borrado", "ya_no_va"} {
		t.Run(motivo, func(t *testing.T) {
			h, q, _ := montarLaPuerta(t, nil)
			cuerpo := `{"aviso":{"avisoId":"1-0","motivo":"` + motivo + `","id":"PED-9"}}`

			w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)

			if w.Code != http.StatusOK {
				t.Fatalf("%s no entró: %d %s", motivo, w.Code, w.Body.String())
			}
			if q.quitados != 1 {
				t.Fatalf("%s no quitó el pedido: quitados=%d", motivo, q.quitados)
			}
		})
	}
}

// UN BORRADO SIN ID no dice qué quitar: 422, que PEDIDO descarta a la primera. Lo que NO
// puede hacer es quitar algo a ciegas.
func TestUnBorradoSinIDNoQuitaNada(t *testing.T) {
	h, q, _ := montarLaPuerta(t, nil)
	cuerpo := `{"aviso":{"avisoId":"1-0","motivo":"borrado","id":""}}`

	w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)

	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("un borrado sin id tenía que ser 422: %d %s", w.Code, w.Body.String())
	}
	if q.quitados != 0 {
		t.Fatalf("quitó pedidos sin saber cuál: quitados=%d", q.quitados)
	}
}

// EL CLIENTE SE MOVIÓ DE SITIO: se guarda con sus coordenadas.
func TestElClienteMovidoSeGuarda(t *testing.T) {
	h, q, _ := montarLaPuerta(t, nil)
	cuerpo := `{"aviso":{"avisoId":"1-0","entidad":"cliente","motivo":"cliente","id":"CLI-1"},
	            "cliente":{"id":"CLI-1","codigo":"C1","nombre":"Uno","latitud":20.1,"longitud":-77.2}}`

	w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)

	if w.Code != http.StatusOK {
		t.Fatalf("el cliente movido no entró: %d %s", w.Code, w.Body.String())
	}
	if q.clientes != 1 {
		t.Fatalf("contestó 200 y NO guardó el cliente: clientes=%d", q.clientes)
	}
}

// SIN COORDENADAS NO HAY PARADA: 200 con `sinEfecto`, no un error. Y no se escribe nada —la
// columna no admite nulos y el repaso completo hace lo mismo.
func TestUnClienteSinCoordenadasNoEsUnFallo(t *testing.T) {
	h, q, _ := montarLaPuerta(t, nil)
	cuerpo := `{"aviso":{"avisoId":"1-0","entidad":"cliente","motivo":"cliente","id":"CLI-2"},
	            "cliente":{"id":"CLI-2","codigo":"C2","nombre":"Dos"}}`

	w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)

	if w.Code != http.StatusOK {
		t.Fatalf("un cliente sin coordenadas hizo que PEDIDO reintentara: %d %s",
			w.Code, w.Body.String())
	}
	if q.clientes != 0 {
		t.Fatalf("guardó un cliente sin coordenadas: clientes=%d", q.clientes)
	}
	r := leerLaRespuesta(t, w.Body.String())
	if r.SinEfecto != 1 || r.Aplicados != 0 {
		t.Fatalf("no lo contó como sin efecto: %s", w.Body.String())
	}
	if !strings.Contains(r.Motivos, "coordenadas") {
		t.Fatalf("el motivo no dice qué faltó: %q", r.Motivos)
	}
}

// UN AVISO DE CLIENTE SIN EL CLIENTE DENTRO: 422. No se va a pedir a PEDIDO —eso es medio
// sondeo otra vez— y no se calla.
func TestUnAvisoDeClienteSinClienteSeDice(t *testing.T) {
	h, q, _ := montarLaPuerta(t, nil)
	cuerpo := `{"aviso":{"avisoId":"1-0","entidad":"cliente","motivo":"cliente","id":"CLI-3"}}`

	w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)

	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("tenía que ser 422: %d %s", w.Code, w.Body.String())
	}
	if q.clientes != 0 {
		t.Fatalf("guardó algo: clientes=%d", q.clientes)
	}
}

// --------------------------------------------------------------------------- el pedido

// EL PEDIDO ENTRA POR LA PUERTA ÚNICA, traducido con el mismo traductor del ciclo.
//
// Se comprueba QUÉ LLEGA a `/api/quote/batch`: que el `externalId` va puesto es justo lo que
// se pierde si alguien manda el pedido de PEDIDO sin traducir —es el fallo que tiene hoy
// `/api/admin/recompute`, que mete la forma de `/integration/orders` tal cual y todos los
// pedidos le entran con el id vacío—.
func TestElPedidoEntraTraducidoPorLaPuertaUnica(t *testing.T) {
	var loQueLlego string
	puerta := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		crudo := make([]byte, r.ContentLength)
		_, _ = r.Body.Read(crudo)
		loQueLlego = string(crudo)
		_, _ = w.Write([]byte(`{"total":1,"persisted":1,"results":[{"status":"quoted","persisted":true}]}`))
	}))
	defer puerta.Close()

	h, _, _ := montarLaPuerta(t, func(t *testing.T) {
		t.Setenv("DELIVERY_URL", puerta.URL)
	})
	cuerpo := `{"aviso":{"avisoId":"1-0","motivo":"factura","id":"PED-7","sucursalId":"STG"},
	            "pedido":{"id":"PED-7","folio":"X-2992","sucursalCodigo":"STG",
	                      "itemsOrigen":"factura","requiereDomicilio":true,
	                      "cliente":{"nombre":"Uno","latitud":20.1,"longitud":-77.2},
	                      "items":[{"codigo":"A","pesoKg":2,"pesoLineaKg":24,"packs":12}]}}`

	w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)

	if w.Code != http.StatusOK {
		t.Fatalf("el pedido no entró: %d %s", w.Code, w.Body.String())
	}
	if !strings.Contains(loQueLlego, `"externalId":"PED-7"`) {
		t.Fatalf("llegó a la puerta SIN traducir: el `externalId` es lo que la identifica "+
			"y sin él no entra ningún pedido.\n  llegó: %s", recorteDePruebas(loQueLlego))
	}
	if !strings.Contains(loQueLlego, `"itemsOrigen":"factura"`) {
		t.Fatalf("se perdió de dónde salen los renglones: lo que sube al camión es lo que "+
			"se facturó, no lo que se pidió.\n  llegó: %s", recorteDePruebas(loQueLlego))
	}
	if r := leerLaRespuesta(t, w.Body.String()); r.Aplicados != 1 {
		t.Fatalf("dijo que no aplicó nada: %s", w.Body.String())
	}
}

// UN MOTIVO QUE NO SE CONOCE, CON PEDIDO DENTRO, SE GUARDA. Es una versión nueva de PEDIDO
// contra una vieja de esto: descartarlo sería perder el pedido sin un solo error.
func TestUnMotivoDesconocidoConPedidoSeGuarda(t *testing.T) {
	llamada := false
	puerta := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		llamada = true
		_, _ = w.Write([]byte(`{"total":1,"persisted":1,"results":[{"status":"quoted","persisted":true}]}`))
	}))
	defer puerta.Close()

	h, _, _ := montarLaPuerta(t, func(t *testing.T) { t.Setenv("DELIVERY_URL", puerta.URL) })
	cuerpo := `{"aviso":{"avisoId":"1-0","motivo":"algo_que_pedido_invento_despues","id":"PED-8"},
	            "pedido":{"id":"PED-8","folio":"X-1","sucursalCodigo":"STG",
	                      "cliente":{"nombre":"Uno","latitud":20.1,"longitud":-77.2},
	                      "items":[{"codigo":"A","pesoLineaKg":10,"packs":1}]}}`

	w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)

	if w.Code != http.StatusOK {
		t.Fatalf("un motivo nuevo tumbó el aviso: %d %s", w.Code, w.Body.String())
	}
	if !llamada {
		t.Fatal("se tiró el pedido de un motivo que no se conoce: eso es perderlo en silencio")
	}
}

// LA PUERTA NO GUARDÓ: 200 con el MOTIVO LITERAL de la puerta. No es un fallo de PEDIDO —ese
// pedido puede no ser repartible todavía—, pero «no se pudo» no le dice nada a nadie.
func TestSiLaPuertaNoGuardaSeDiceConSuMotivo(t *testing.T) {
	puerta := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"total":1,"persisted":0,"results":` +
			`[{"status":"skipped","reason":"sin coordenadas del cliente"}]}`))
	}))
	defer puerta.Close()

	h, _, _ := montarLaPuerta(t, func(t *testing.T) { t.Setenv("DELIVERY_URL", puerta.URL) })
	cuerpo := `{"aviso":{"avisoId":"1-0","motivo":"factura","id":"PED-5"},
	            "pedido":{"id":"PED-5","folio":"X-2","sucursalCodigo":"STG","items":[]}}`

	w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)

	if w.Code != http.StatusOK {
		t.Fatalf("hizo reintentar algo que va a dar lo mismo: %d %s", w.Code, w.Body.String())
	}
	r := leerLaRespuesta(t, w.Body.String())
	if r.Aplicados != 0 || r.SinEfecto != 1 {
		t.Fatalf("no lo contó bien: %s", w.Body.String())
	}
	if !strings.Contains(r.Motivos, "sin coordenadas del cliente") {
		t.Fatalf("se perdió el motivo literal de la puerta: %q", r.Motivos)
	}
}

// LA PUERTA NO CONTESTA: 503, que PEDIDO SÍ reintenta. Es lo contrario del caso de arriba y
// por eso van los dos: uno no va a cambiar por repetirlo y el otro sí.
func TestSiLaPuertaNoContestaSeReintenta(t *testing.T) {
	puerta := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer puerta.Close()

	h, _, _ := montarLaPuerta(t, func(t *testing.T) { t.Setenv("DELIVERY_URL", puerta.URL) })
	cuerpo := `{"aviso":{"avisoId":"1-0","motivo":"factura","id":"PED-6"},
	            "pedido":{"id":"PED-6","folio":"X-3","sucursalCodigo":"STG","items":[]}}`

	w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)

	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("un fallo que pasa solo se descartó a la primera: %d %s", w.Code, w.Body.String())
	}
}

// --------------------------------------------------------------------------- la constancia

// LA FILA SE APUNTA SIEMPRE, también cuando se rechaza.
//
// Sin ella, un PEDIDO que manda y un reparto que rechaza todo se ven exactamente igual desde
// la pantalla del canal: «no ha entrado nada». Y son dos cosas que se arreglan en sitios
// distintos.
func TestLaRecepcionSeApuntaTambienCuandoSeRechaza(t *testing.T) {
	h, q, _ := montarLaPuerta(t, nil)
	// Un cuerpo que no se entiende: la firma es buena, el JSON no.
	cuerpo := `esto no es json`

	w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)

	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("un cuerpo ilegible tenía que ser 422 —PEDIDO lo descarta a la primera—: "+
			"%d %s", w.Code, w.Body.String())
	}
	if len(q.recepciones) != 1 {
		t.Fatalf("no quedó constancia del rechazo: %d filas. Desde la pantalla del canal, "+
			"«PEDIDO no manda» y «el reparto rechaza todo» se verían igual",
			len(q.recepciones))
	}
	r := q.recepciones[0]
	if r.Origen != OrigenDelWebhook {
		t.Fatalf("el origen tiene que ser %q —la puerta del webhook, para poder separarla "+
			"del lote del espejo en la pantalla—, y fue %q", OrigenDelWebhook, r.Origen)
	}
	if r.Traidos != 1 || r.Rechazados != 1 || r.Escritos != 0 {
		t.Fatalf("los números no cuentan lo que pasó: traidos=%d escritos=%d rechazados=%d",
			r.Traidos, r.Escritos, r.Rechazados)
	}
	if r.Motivos == nil || *r.Motivos == "" {
		t.Fatal("se apuntó el rechazo sin motivo: la fila dice que algo falló y no qué")
	}
}

// Y CUANDO ENTRA, también, con el número del otro lado.
func TestLaRecepcionSeApuntaCuandoEntra(t *testing.T) {
	h, q, _ := montarLaPuerta(t, nil)
	cuerpo := `{"aviso":{"avisoId":"1-0","motivo":"borrado","id":"PED-1"}}`

	tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)

	if len(q.recepciones) != 1 {
		t.Fatalf("no quedó constancia: %d filas", len(q.recepciones))
	}
	if r := q.recepciones[0]; r.Escritos != 1 || r.Rechazados != 0 {
		t.Fatalf("no contó la escritura: escritos=%d rechazados=%d", r.Escritos, r.Rechazados)
	}
}

// --------------------------------------------------------------------------- el montaje

func firmarDePruebas(secreto, cuerpo string) string {
	mac := hmac.New(sha256.New, []byte(secreto))
	mac.Write([]byte(cuerpo))
	return "sha256=" + hex.EncodeToString(mac.Sum(nil))
}

func tocarLaPuerta(t *testing.T, h http.Handler, clave, firma, cuerpo string) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(http.MethodPost, "/api/webhooks/pedido", strings.NewReader(cuerpo))
	r.Header.Set("Content-Type", "application/json")
	if clave != "" {
		r.Header.Set(CabeceraClaveDelWebhook, clave)
	}
	if firma != "" {
		r.Header.Set(CabeceraFirmaDelWebhook, firma)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func leerLaRespuesta(t *testing.T, crudo string) respuestaDelWebhook {
	t.Helper()
	var r respuestaDelWebhook
	if err := json.Unmarshal([]byte(crudo), &r); err != nil {
		t.Fatalf("la respuesta no se entiende: %v — %s", err, crudo)
	}
	return r
}

func recorteDePruebas(s string) string {
	if len(s) > 400 {
		return s[:400] + "…"
	}
	return s
}

// montarLaPuerta monta SÓLO la del webhook, con la pareja de pruebas puesta. `antes` deja
// cambiar el entorno para los casos que prueban justo eso.
func montarLaPuerta(t *testing.T, antes func(*testing.T)) (http.Handler, *dobleDeLaPuerta, *Servidor) {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoDeRutas)
	t.Setenv("PEDIDO_WEBHOOK_KEY", claveDePruebas)
	t.Setenv("PEDIDO_WEBHOOK_SECRET", secretoDePruebas)
	if antes != nil {
		antes(t)
	}
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	reg := slog.New(slog.DiscardHandler)
	q := &dobleDeLaPuerta{}
	porteria := alcance.NuevaPorteria(fuenteDeLaPuerta{q: q}, reg)
	verif := auth.NuevoVerificador([]byte(secretoDeRutas))
	s := NuevoServidor(cfg, reg, porteria, verif, func(context.Context) error { return nil })

	rt := httpx.NuevoRouter(httpx.IDDePeticion, httpx.ConRegistro(reg),
		httpx.RecuperarPanico, httpx.SinCache)
	sesion := []httpx.Medio{verif.Exigir, porteria.Exigir}
	admin := []httpx.Medio{verif.Exigir, auth.ExigirAdmin, porteria.Exigir}
	s.rutasEspejo(rt, sesion, admin)
	return rt.Handler(), q, s
}

type fuenteDeLaPuerta struct{ q sqlc.Querier }

func (f fuenteDeLaPuerta) Consultas() sqlc.Querier { return f.q }
func (f fuenteDeLaPuerta) EnTx(ctx context.Context, fn func(sqlc.Querier) error) error {
	return fn(f.q)
}

// dobleDeLaPuerta CUENTA LO QUE SE ESCRIBE. Es el corazón de estas pruebas: comprobar sólo
// el código de la respuesta deja pasar un 200 que no escribió nada y un 401 que borró antes
// de rechazar.
type dobleDeLaPuerta struct {
	sqlc.Querier
	quitados    int
	clientes    int
	recepciones []sqlc.ApuntarRecepcionDelWebhookParams
}

func (d *dobleDeLaPuerta) QuitarPedidosDelEspejo(_ context.Context, ids []string) (int64, error) {
	d.quitados += len(ids)
	return int64(len(ids)), nil
}

func (d *dobleDeLaPuerta) GuardarClienteDelEspejo(
	context.Context, sqlc.GuardarClienteDelEspejoParams,
) (sqlc.GuardarClienteDelEspejoRow, error) {
	d.clientes++
	return sqlc.GuardarClienteDelEspejoRow{}, nil
}

func (d *dobleDeLaPuerta) ApuntarRecepcionDelWebhook(_ context.Context, p sqlc.ApuntarRecepcionDelWebhookParams) error {
	d.recepciones = append(d.recepciones, p)
	return nil
}

func (d *dobleDeLaPuerta) ResolverSucursal(context.Context, uuid.UUID) (sqlc.ResolverSucursalRow, error) {
	return sqlc.ResolverSucursalRow{}, pgx.ErrNoRows
}

// --------------------------------------------------------------------------- el SSE

// LA PANTALLA SE REPINTA SOLA: el aviso sale SIEMPRE, también cuando se rechaza.
//
// Jose, 26/09/2026: «SSE con todo esto igual, nada de polling». Sin este aviso la pantalla del
// canal se queda con la foto del instante en que se abrió y hay que darle a un botón, que es
// medio sondeo con una persona haciendo de temporizador.
//
// LOS TRES CASOS, y el que más importa es el tercero: un PEDIDO que manda y un reparto que
// rechaza todo es justo la situación que hay que ver al instante, y es la que se quedaría sin
// pintar con un aviso que sólo sale cuando algo va bien.
func TestElCanalAvisaParaQueLaPantallaSeRepinte(t *testing.T) {
	casos := []struct {
		nombre string
		cuerpo string
	}{
		{"cuando entra", `{"aviso":{"avisoId":"1-0","motivo":"borrado","id":"PED-1"}}`},
		{"cuando se rechaza por el cuerpo", `esto no es json`},
		{"cuando falta el pedido dentro",
			`{"aviso":{"avisoId":"1-0","motivo":"factura","id":"PED-2"}}`},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			avisos := 0
			antes := avisarCambioEnElCanal
			avisarCambioEnElCanal = func(context.Context) { avisos++ }
			t.Cleanup(func() { avisarCambioEnElCanal = antes })

			h, _, _ := montarLaPuerta(t, nil)
			tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, c.cuerpo), c.cuerpo)

			if avisos != 1 {
				t.Fatalf("salieron %d avisos y tenía que salir 1: sin él la pantalla del "+
					"canal se queda con la foto vieja y hay que darle a un botón", avisos)
			}
		})
	}
}

// Y NO SALE CUANDO LA PUERTA NI SE ABRE. Un aviso con la firma mala no ha pasado nada: avisar
// ahí haría que ocho navegadores se bajaran el estado del canal por un intento que no entró —y
// si alguien empieza a aporrear la URL, uno por golpe.
func TestConLaFirmaMalaNoSeAvisaANadie(t *testing.T) {
	avisos := 0
	antes := avisarCambioEnElCanal
	avisarCambioEnElCanal = func(context.Context) { avisos++ }
	t.Cleanup(func() { avisarCambioEnElCanal = antes })

	cuerpo := `{"aviso":{"avisoId":"1-0","motivo":"borrado","id":"PED-1"}}`
	h, _, _ := montarLaPuerta(t, nil)
	tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas("otro-secreto", cuerpo), cuerpo)

	if avisos != 0 {
		t.Fatalf("avisó %d veces por una petición que no entró", avisos)
	}
}

// --------------------------------------------------------------------------- una sola fila

// UN AVISO DEJA UNA FILA, NO DOS — y con su propio `origen`.
//
// SE ENCONTRÓ EN PRODUCCIÓN el 26/09/2026, mirando la tabla después del primer POST bueno: el
// lote del espejo apuntaba con `origen='pedido'` y el webhook también, así que los avisos —de
// uno en uno— quedaban enterrados entre tandas de doscientos y la pantalla no podía contestar
// «¿entra algo POR EL WEBHOOK?», que es su única pregunta.
//
// Y LO PEOR NO ERA EL NOMBRE: un aviso con pedido dentro pasa por `/api/quote/batch`, que
// apunta SU fila, así que el mismo pedido dejaba DOS y `escritosHoy` lo contaba dos veces. Un
// número doblado en la pantalla que existe para mirar ese número es de los caros aquí: es
// creíble, y ninguna otra pantalla lo desmiente.
func TestUnAvisoConPedidoDejaUnaSolaFila(t *testing.T) {
	// La puerta de mentira apunta si le llegó la cabecera que evita la fila doble.
	var traíaLaCabecera bool
	puerta := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		traíaLaCabecera = r.Header.Get(CabeceraDeConstancia) == YaApuntada
		_, _ = w.Write([]byte(`{"total":1,"persisted":1,"results":[{"status":"quoted","persisted":true}]}`))
	}))
	defer puerta.Close()

	h, q, _ := montarLaPuerta(t, func(t *testing.T) { t.Setenv("DELIVERY_URL", puerta.URL) })
	cuerpo := `{"aviso":{"avisoId":"1-0","motivo":"factura","id":"PED-7"},
	            "pedido":{"id":"PED-7","folio":"X-1","sucursalCodigo":"STG",
	                      "cliente":{"nombre":"Uno","latitud":20.1,"longitud":-77.2},
	                      "items":[{"codigo":"A","pesoLineaKg":10,"packs":1}]}}`

	tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)

	if !traíaLaCabecera {
		t.Fatal("el salto interno fue SIN la cabecera de constancia: la puerta va a apuntar " +
			"su propia fila y `escritosHoy` contará este pedido dos veces")
	}
	if len(q.recepciones) != 1 {
		t.Fatalf("quedaron %d filas por UN aviso", len(q.recepciones))
	}
	if o := q.recepciones[0].Origen; o != OrigenDelWebhook {
		t.Fatalf("el origen fue %q: con el mismo nombre que el lote del espejo (%q), los "+
			"avisos quedan enterrados entre tandas de doscientos", o, OrigenDelLote)
	}
}

// Y LOS DOS NOMBRES SON DISTINTOS. Sin esto, «el origen es OrigenDelWebhook» se cumple
// habiendo puesto las dos constantes al mismo texto, que es exactamente el fallo de partida.
func TestLosDosOrigenesNoSeLlamanIgual(t *testing.T) {
	if OrigenDelWebhook == OrigenDelLote {
		t.Fatalf("las dos puertas se llaman %q: en la pantalla no se pueden separar, y la "+
			"pregunta «¿entra algo por el webhook?» no tiene respuesta", OrigenDelWebhook)
	}
}

// SOLO FACTURA (21/10/2026, Jose: «solo facturas»): con `SYNC_FUENTE=factura` un aviso de PEDIDO con
// un pedido dentro NO crea ninguna entrega —ni siquiera llega a la puerta de cotización— y se
// contesta 200 sin efecto con su motivo. Es lo que impide que el borrado de los pedidos de STG y GTO se
// deshaga solo con cada pedido nuevo. En pareja con `TestElPedidoEntraTraducidoPorLaPuertaUnica`
// (sin la variable, entra).
func TestConSoloFacturaUnPedidoDePedidoNoCreaNada(t *testing.T) {
	llamadas := 0
	puerta := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		llamadas++
		_, _ = w.Write([]byte(`{"total":1,"persisted":1,"results":[{"status":"quoted","persisted":true}]}`))
	}))
	defer puerta.Close()

	h, _, _ := montarLaPuerta(t, func(t *testing.T) {
		t.Setenv("DELIVERY_URL", puerta.URL)
		t.Setenv("SYNC_FUENTE", "factura")
	})
	cuerpo := `{"aviso":{"avisoId":"1-0","motivo":"factura","id":"PED-7","sucursalId":"STG"},
	            "pedido":{"id":"PED-7","folio":"X-2992","sucursalCodigo":"STG",
	                      "itemsOrigen":"factura","requiereDomicilio":true,
	                      "cliente":{"nombre":"Uno","latitud":20.1,"longitud":-77.2},
	                      "items":[{"codigo":"A","pesoKg":2,"pesoLineaKg":24,"packs":12}]}}`

	w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)

	if w.Code != http.StatusOK {
		t.Fatalf("PEDIDO no tiene que reintentar ni descartar: esperaba 200, vino %d %s", w.Code, w.Body.String())
	}
	if llamadas != 0 {
		t.Fatalf("el pedido llegó a la puerta de cotización %d veces: se está creando una entrega por la puerta de atrás", llamadas)
	}
	r := leerLaRespuesta(t, w.Body.String())
	if r.Aplicados != 0 || r.SinEfecto != 1 || !strings.Contains(r.Motivos, "trabaja por factura") {
		t.Fatalf("tenía que decir sin efecto y por qué: %s", w.Body.String())
	}
}

// Y lo que NO se corta: el aviso de cliente movido de sitio sigue aplicándose (los clientes viven en PEDIDO).
func TestConSoloFacturaElClienteMovidoSiSeGuarda(t *testing.T) {
	h, q, _ := montarLaPuerta(t, func(t *testing.T) { t.Setenv("SYNC_FUENTE", "factura") })
	cuerpo := `{"aviso":{"avisoId":"1-0","motivo":"cliente","id":"C-1"},
	            "cliente":{"id":"C-1","nombre":"Uno","latitud":20.1,"longitud":-77.2,"sucursalCodigo":"STG"}}`

	w := tocarLaPuerta(t, h, claveDePruebas, firmarDePruebas(secretoDePruebas, cuerpo), cuerpo)

	if w.Code != http.StatusOK {
		t.Fatalf("el cliente no entró: %d %s", w.Code, w.Body.String())
	}
	if q.clientes != 1 {
		t.Fatalf("el cliente movido tiene que guardarse también en solo factura: clientes=%d", q.clientes)
	}
}
