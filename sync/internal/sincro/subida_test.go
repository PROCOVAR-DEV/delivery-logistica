package sincro

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/httpx"
	"procovar/reparto-sync/internal/identidad"
	"procovar/reparto-sync/internal/store/sqlc"
)

// 1 · IDEMPOTENCIA
//
// Una subida a medias —el servidor guardó y se cortó antes de contestar— se reintenta
// entera. Si el reintento se aplicara otra vez, una ruta armada sin conexión acabaría
// duplicada y saldría el mismo camión dos veces.
func TestUnLoteQueLlegaDosVecesNoSeAplicaDosVeces(t *testing.T) {
	b := montar(t)

	creada := uuid.New()
	b.aplicador.responde = func(p Peticion) (*uuid.UUID, error) { return &creada, nil }

	lote := []apunteEntrada{{
		Clave:       "01J8AAAA",
		Hecho:       enPunto(t, "2026-09-14T16:04:22Z"),
		Metodo:      http.MethodPost,
		Ruta:        "/api/routes",
		Cuerpo:      json.RawMessage(`{"vehicleId":"v1","orderIds":["p1","p2"]}`),
		Provisional: "local-9f3a",
	}}

	_, primera := b.subir(lote, b.quien)
	if len(primera) != 1 || primera[0].Estado != EstadoAplicado {
		t.Fatalf("la primera vez tenía que aplicarse: %+v", primera)
	}
	if primera[0].ID == nil || *primera[0].ID != creada {
		t.Fatalf("la primera vez tenía que devolver el id creado: %+v", primera[0])
	}

	// El mismo lote otra vez, tal cual, como lo reintentaría el teléfono.
	_, segunda := b.subir(lote, b.quien)
	if len(segunda) != 1 || segunda[0].Estado != EstadoRepetido {
		t.Fatalf("la segunda vez tenía que ser `repetido`: %+v", segunda)
	}
	// Y CON LA MISMA RESPUESTA: el id de entonces, no uno nuevo. Un id nuevo aquí es una
	// ruta duplicada esperando a pasar.
	if segunda[0].ID == nil || *segunda[0].ID != creada {
		t.Fatalf("`repetido` tiene que devolver el id de la primera vez; devolvió %+v", segunda[0].ID)
	}

	if len(b.aplicador.llamadas) != 1 {
		t.Fatalf("el reparto tenía que ver el apunte UNA vez, lo vio %d", len(b.aplicador.llamadas))
	}
}

// Y lo mismo dentro de un solo envío: el aparato reenvió su cola sin limpiarla.
func TestLaMismaClaveDosVecesEnElMismoLote(t *testing.T) {
	b := montar(t)
	creada := uuid.New()
	b.aplicador.responde = func(p Peticion) (*uuid.UUID, error) { return &creada, nil }

	uno := apunteEntrada{
		Clave: "01J8BBBB", Hecho: enPunto(t, "2026-09-14T16:04:22Z"),
		Metodo: http.MethodPost, Ruta: "/api/routes", Provisional: "local-77",
	}
	_, res := b.subir([]apunteEntrada{uno, uno}, b.quien)

	if len(res) != 2 {
		t.Fatalf("tenía que contestar apunte por apunte: %+v", res)
	}
	if res[0].Estado != EstadoAplicado || res[1].Estado != EstadoRepetido {
		t.Fatalf("el segundo tenía que ser `repetido`: %+v", res)
	}
	if *res[1].ID != creada {
		t.Fatalf("y con el mismo id")
	}
	if len(b.aplicador.llamadas) != 1 {
		t.Fatalf("el reparto tenía que verlo una sola vez, lo vio %d", len(b.aplicador.llamadas))
	}
}

// 2 · EL ORDEN
//
// Marcar una parada y corregirla después son dos apuntes sobre el mismo pedido. Aplicarlos
// al revés deja puesta la primera marca y borra la corrección.
//
// La corrección va con una hora ANTERIOR a propósito: el reloj del teléfono se mueve —se
// cambia a mano, salta de zona horaria, se va con la batería—, así que ordenar por él sería
// exactamente el fallo que esta prueba impide. La cola es FIFO y manda el orden en que
// vino.
func TestElOrdenDeLaColaMandaSobreElRelojDelAparato(t *testing.T) {
	b := montar(t)

	marca := apunteEntrada{
		Clave: "01J8C001", Hecho: enPunto(t, "2026-09-14T16:30:00Z"),
		Metodo: http.MethodPost, Ruta: "/api/orders/p1/estado",
		Cuerpo: json.RawMessage(`{"estado":"ENTREGADO"}`),
	}
	correccion := apunteEntrada{
		Clave: "01J8C002", Hecho: enPunto(t, "2026-09-14T15:00:00Z"), // el reloj se atrasó
		Metodo: http.MethodPost, Ruta: "/api/orders/p1/estado",
		Cuerpo: json.RawMessage(`{"estado":"NO_ENTREGADO","motivo":"nadie en casa"}`),
	}

	_, res := b.subir([]apunteEntrada{marca, correccion}, b.quien)
	if len(res) != 2 || res[0].Estado != EstadoAplicado || res[1].Estado != EstadoAplicado {
		t.Fatalf("los dos tenían que aplicarse: %+v", res)
	}

	claves := []string{b.aplicador.llamadas[0].Clave, b.aplicador.llamadas[1].Clave}
	if claves[0] != "01J8C001" || claves[1] != "01J8C002" {
		t.Fatalf("el reparto los tenía que ver en el orden de la cola, los vio %v", claves)
	}

	// Lo que cuenta de verdad: lo que quedó puesto al final.
	if quedo := b.aplicador.estado["/api/orders/p1/estado"]; !strings.Contains(quedo, "NO_ENTREGADO") {
		t.Fatalf("tenía que quedar la corrección, quedó %q", quedo)
	}

	// Y la hora que se guarda es la del APARATO, la que venía en el apunte: lo que se
	// marcó a las cuatro consta como las cuatro aunque suba a las siete.
	guardado := b.base.apuntes[llave(b.aparato.ID, "01J8C001")]
	if !guardado.HechoAt.Time.Equal(marca.Hecho) {
		t.Fatalf("se guardó la hora %v en vez de la del aparato %v", guardado.HechoAt.Time, marca.Hecho)
	}
	if b.aplicador.llamadas[0].Hecho != marca.Hecho {
		t.Fatalf("al reparto se le manda la hora del aparato")
	}
}

// 3 · LOS IDENTIFICADORES PROVISIONALES
//
// Si esto falla, el cierre de una ruta armada sin red se pierde con un 404 justo después de
// haber subido bien la ruta.
func TestElCierreDeLaRutaVaAlIdDeVerdadYNoAlLocal(t *testing.T) {
	b := montar(t)

	rutaCreada := uuid.New()
	b.aplicador.responde = func(p Peticion) (*uuid.UUID, error) {
		if p.Ruta == "/api/routes" {
			return &rutaCreada, nil
		}
		return nil, nil
	}

	arma := apunteEntrada{
		Clave: "01J8D001", Hecho: enPunto(t, "2026-09-14T09:10:00Z"),
		Metodo: http.MethodPost, Ruta: "/api/routes",
		Cuerpo:      json.RawMessage(`{"vehicleId":"v1","orderIds":["p1","p2"]}`),
		Provisional: "local-9f3a",
	}
	cierra := apunteEntrada{
		Clave: "01J8D002", Hecho: enPunto(t, "2026-09-14T18:40:00Z"),
		Metodo: http.MethodPost, Ruta: "/api/routes/local-9f3a/results",
		Cuerpo: json.RawMessage(`{"ruta":"local-9f3a","entregados":["p1"]}`),
	}

	_, res := b.subir([]apunteEntrada{arma, cierra}, b.quien)
	if len(res) != 2 || res[1].Estado != EstadoAplicado {
		t.Fatalf("el cierre tenía que aplicarse: %+v", res)
	}

	esperada := "/api/routes/" + rutaCreada.String() + "/results"
	if got := b.aplicador.llamadas[1].Ruta; got != esperada {
		t.Fatalf("el cierre fue a %q en vez de a %q", got, esperada)
	}
	// También dentro del cuerpo: el `local-…` viaja en la ruta Y en lo que se manda.
	if cuerpo := string(b.aplicador.llamadas[1].Cuerpo); !strings.Contains(cuerpo, rutaCreada.String()) || strings.Contains(cuerpo, "local-9f3a") {
		t.Fatalf("el cuerpo se quedó con el provisional: %s", cuerpo)
	}

	// La traducción queda guardada, que es la red debajo: si el aparato se corta antes de
	// sustituir el `local-…` en el resto de su cola y lo manda en OTRO envío, aquí se sabe
	// de qué ruta hablaba.
	otroDia := apunteEntrada{
		Clave: "01J8D003", Hecho: enPunto(t, "2026-09-15T08:00:00Z"),
		Metodo: http.MethodPost, Ruta: "/api/routes/local-9f3a/results",
	}
	_, res2 := b.subir([]apunteEntrada{otroDia}, b.quien)
	if res2[0].Estado != EstadoAplicado {
		t.Fatalf("el reenvío tardío tenía que aplicarse: %+v", res2)
	}
	if got := b.aplicador.llamadas[2].Ruta; got != esperada {
		t.Fatalf("en otro envío el provisional se tradujo a %q", got)
	}
}

// Y el que no se puede traducir NO se pierde con un 404: se rechaza con un motivo que se
// entiende y queda en la bandeja.
func TestUnProvisionalQueNoExisteSeRechazaConMotivo(t *testing.T) {
	b := montar(t)

	huerfano := apunteEntrada{
		Clave: "01J8E001", Hecho: enPunto(t, "2026-09-14T18:40:00Z"),
		Metodo: http.MethodPost, Ruta: "/api/routes/local-nadie/results",
	}
	_, res := b.subir([]apunteEntrada{huerfano}, b.quien)

	if res[0].Estado != EstadoRechazado {
		t.Fatalf("tenía que rechazarse: %+v", res)
	}
	if !strings.Contains(res[0].Motivo, "local-nadie") {
		t.Fatalf("el motivo tiene que decir cuál: %q", res[0].Motivo)
	}
	if len(b.aplicador.llamadas) != 0 {
		t.Fatalf("no se le manda al reparto para que conteste 404")
	}
	if _, hay := b.base.rechazos[llave(b.aparato.ID, "01J8E001")]; !hay {
		t.Fatalf("tenía que quedar en la bandeja")
	}
}

// 4 · LO RECHAZADO NO SE BORRA NI SE REINTENTA
//
// Un apunte que desaparece solo es trabajo perdido que nadie sabe que perdió.
func TestLoRechazadoSeGuardaConSuMotivoYNoSeVuelveAEvaluar(t *testing.T) {
	b := montar(t)

	// EL MOTIVO TAL Y COMO LO ESCRIBE EL REPARTO: con el pedido nombrado y con la ruta en
	// la que está. Es el caso que pidió Jose el 21/09/2026 —una ruta armada sin señal con
	// pedidos que ya iban en otra— y el que tiene que llegar hasta aquí entero. Antes este
	// literal era «3 de los 8 pedidos ya están en otra ruta. Vuelve a elegirlos.», que ni
	// decía cuál ni era cierto la mitad de las veces (`api/internal/api/rutas.go`,
	// `porQueNoSeArma`).
	const motivo = "1 de los 3 pedidos elegidos no pueden ir en esta ruta: " +
		"X-2992 (ya va en la ruta RT-20260921-002)."
	b.aplicador.responde = func(p Peticion) (*uuid.UUID, error) {
		return nil, &Rechazo{Motivo: motivo}
	}

	apunte := apunteEntrada{
		Clave: "01J8F001", Hecho: enPunto(t, "2026-09-14T10:00:00Z"),
		Metodo: http.MethodPost, Ruta: "/api/routes",
		Cuerpo: json.RawMessage(`{"orderIds":["p1","p2"]}`),
	}

	_, res := b.subir([]apunteEntrada{apunte}, b.quien)
	if res[0].Estado != EstadoRechazado || res[0].Motivo != motivo {
		t.Fatalf("tenía que salir rechazado con su motivo literal: %+v", res[0])
	}

	// El apunte queda anotado como rechazado...
	guardado, hay := b.base.apuntes[llave(b.aparato.ID, "01J8F001")]
	if !hay || guardado.Estado != sqlc.ApunteEstadoRechazado {
		t.Fatalf("el apunte tenía que quedar anotado como rechazado: %+v", guardado)
	}
	// ...y el motivo con el sobre, en la bandeja, para que una persona pueda ver qué se
	// intentó y repetirlo a mano.
	enLaBandeja, hay := b.base.rechazos[llave(b.aparato.ID, "01J8F001")]
	if !hay || enLaBandeja.Motivo != motivo {
		t.Fatalf("el motivo tenía que quedar en la bandeja: %+v", enLaBandeja)
	}
	if enLaBandeja.Cuerpo == nil || !strings.Contains(*enLaBandeja.Cuerpo, "p1") {
		t.Fatalf("el cuerpo del apunte tenía que guardarse tal cual")
	}
	if n := b.base.subidas[0].RechazadosDelLote; n != 1 {
		t.Fatalf("el contador del panel tenía que subir 1, subió %d", n)
	}

	// Si el aparato lo vuelve a mandar, NO se vuelve a evaluar: se le contesta lo mismo.
	_, otra := b.subir([]apunteEntrada{apunte}, b.quien)
	if otra[0].Estado != EstadoRepetido || otra[0].Motivo != motivo {
		t.Fatalf("un rechazo reenviado se contesta con lo mismo de la primera vez: %+v", otra[0])
	}
	if len(b.aplicador.llamadas) != 1 {
		t.Fatalf("no se vuelve a pedir al reparto: %d llamadas", len(b.aplicador.llamadas))
	}

	// Y sale en el panel, que es de donde sale la llamada de teléfono.
	w := b.pedir(http.MethodGet, "/sync/estado", nil, b.quien)
	var panel estadoSalida
	if err := json.Unmarshal(w.Body.Bytes(), &panel); err != nil {
		t.Fatalf("el estado no se entiende: %v", err)
	}
	if len(panel.Bandeja) != 1 || panel.Bandeja[0].Motivo != motivo {
		t.Fatalf("el rechazo tenía que salir en el estado: %+v", panel.Bandeja)
	}
	if len(panel.Aparatos) != 1 || panel.Aparatos[0].Rechazados != 1 {
		t.Fatalf("el aparato tenía que salir con 1 rechazo: %+v", panel.Aparatos)
	}
}

// LA PAREJA DE LA DE ARRIBA: el apunte que SÍ entra no deja nada en la bandeja.
//
// Un aviso que sale en cada movimiento deja de leerse, y entonces tampoco se lee el día que
// importa (`CLAUDE.md` del repo, §3-quinquies). Sin esta prueba, un `rechazar` llamado
// siempre pasaría la de arriba con nota.
func TestElApunteQueEntraNoDejaNadaEnLaBandeja(t *testing.T) {
	b := montar(t)
	creada := uuid.New()
	b.aplicador.responde = func(p Peticion) (*uuid.UUID, error) { return &creada, nil }

	apunte := apunteEntrada{
		Clave: "01J8F010", Hecho: enPunto(t, "2026-09-14T10:00:00Z"),
		Metodo: http.MethodPost, Ruta: "/api/routes",
		Cuerpo: json.RawMessage(`{"orderIds":["p1","p2"]}`),
	}
	_, res := b.subir([]apunteEntrada{apunte}, b.quien)
	if res[0].Estado != EstadoAplicado || res[0].Motivo != "" {
		t.Fatalf("tenía que aplicarse y sin motivo: %+v", res[0])
	}
	if len(b.base.rechazos) != 0 {
		t.Fatalf("no tenía que quedar nada en la bandeja: %+v", b.base.rechazos)
	}
	if n := b.base.subidas[0].RechazadosDelLote; n != 0 {
		t.Fatalf("el contador del panel tenía que quedarse en 0, quedó en %d", n)
	}

	w := b.pedir(http.MethodGet, "/sync/estado", nil, b.quien)
	var panel estadoSalida
	if err := json.Unmarshal(w.Body.Bytes(), &panel); err != nil {
		t.Fatalf("el estado no se entiende: %v", err)
	}
	if len(panel.Bandeja) != 0 {
		t.Fatalf("la bandeja tenía que salir vacía: %+v", panel.Bandeja)
	}
}

// El apunte rechazado y su motivo entran juntos o no entra ninguno: un apunte marcado
// rechazado sin motivo en la bandeja es el descarte en silencio.
func TestSiNoSePuedeGuardarElMotivoTampocoSeMarcaElApunte(t *testing.T) {
	b := montar(t)
	b.base.fallaElMotivo = true
	b.aplicador.responde = func(p Peticion) (*uuid.UUID, error) {
		return nil, &Rechazo{Motivo: "no cabe en el vehículo"}
	}

	_, res := b.subir([]apunteEntrada{{
		Clave: "01J8G001", Hecho: enPunto(t, "2026-09-14T10:00:00Z"),
		Metodo: http.MethodPost, Ruta: "/api/routes",
	}}, b.quien)

	if len(res) != 0 {
		t.Fatalf("el lote se corta: no se puede contestar lo que no se pudo anotar: %+v", res)
	}
	if _, hay := b.base.apuntes[llave(b.aparato.ID, "01J8G001")]; hay {
		t.Fatalf("el apunte no puede quedar marcado si su motivo no entró")
	}
	// Y lo que quedó sin procesar cuenta como pendiente en el panel.
	if n := b.base.subidas[0].Pendientes; n != 1 {
		t.Fatalf("tenía que quedar 1 pendiente, quedó %d", n)
	}
}

// 6 · EL ALCANCE POR SUCURSAL, en la subida.
func TestNoSeSubePorUnAparatoDeOtraSucursal(t *testing.T) {
	b := montar(t)
	otra := identidad.Identidad{Persona: "el-de-camaguey", Sucursal: uuid.New()}

	w, _ := b.subir([]apunteEntrada{{
		Clave: "01J8H001", Hecho: enPunto(t, "2026-09-14T10:00:00Z"),
		Metodo: http.MethodPost, Ruta: "/api/routes",
	}}, otra)

	if w.Code != http.StatusForbidden {
		t.Fatalf("tenía que contestar 403, contestó %d", w.Code)
	}
	if len(b.aplicador.llamadas) != 0 {
		t.Fatalf("no se le manda nada al reparto")
	}
}

// Un apunte sin clave es un fallo de la aplicación, no un rechazo de negocio: 400 con el
// lote entero sin tocar, en vez de llenar de basura técnica la bandeja de una persona.
func TestUnApunteSinClaveNoEntraEnLaBandeja(t *testing.T) {
	b := montar(t)

	w, _ := b.subir([]apunteEntrada{{
		Hecho:  enPunto(t, "2026-09-14T10:00:00Z"),
		Metodo: http.MethodPost, Ruta: "/api/routes",
	}}, b.quien)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("tenía que contestar 400, contestó %d", w.Code)
	}
	if len(b.base.rechazos) != 0 || len(b.base.apuntes) != 0 {
		t.Fatalf("no se guarda nada de un lote malformado")
	}
}

// Un aparato que no está en el registro tiene que poder distinguir «me borraron» de «se me
// caducó la sesión»: 404, no 401.
func TestUnAparatoDesconocidoRecibe404(t *testing.T) {
	b := montar(t)
	w := b.pedir(http.MethodPost, "/sync/subida", loteEntrada{
		Aparato: uuid.New().String(),
	}, b.quien)
	if w.Code != http.StatusNotFound {
		t.Fatalf("tenía que contestar 404, contestó %d", w.Code)
	}
	if !strings.Contains(b.errorDe(w), "darlo de alta") {
		t.Fatalf("el mensaje tiene que decir qué hacer: %q", b.errorDe(w))
	}

	// Y LA MARCA, que es la mitad que lee la máquina.
	//
	// El teléfono tira su identificador y se da de alta otra vez cuando ve este 404, y eso
	// es destructivo: deja una fila más en el panel marcada en rojo como «lleva días sin
	// subir». Hasta el 21/09/2026 le bastaba el número, y un 404 de Traefik durante un
	// redespliegue hacía lo mismo: en producción salieron **12 aparatos para un solo
	// teléfono**, once fantasmas.
	//
	// Sin esta marca el cliente falla CERRADO —relanza y no toca su identificador—, así
	// que quitarla de aquí no rompe nada visible: simplemente el aparato que de verdad se
	// borró del registro deja de poder volver solo. Por eso hace falta la prueba.
	var cuerpo struct {
		Codigo string `json:"codigo"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &cuerpo); err != nil {
		t.Fatalf("la respuesta no es JSON: %v", err)
	}
	if cuerpo.Codigo != httpx.CodigoAparatoNoRegistrado {
		t.Fatalf(
			"falta la marca legible por una máquina: se esperaba %q y vino %q.\n"+
				"Sin ella el teléfono no puede distinguir ESTE 404 de uno de un proxy, "+
				"y no podrá volver a darse de alta cuando de verdad lo borren.",
			httpx.CodigoAparatoNoRegistrado, cuerpo.Codigo,
		)
	}
}

// El alta abre la fila de estado: un aparato que no aparece en el panel es un aparato del
// que nadie se acuerda.
func TestElAltaDejaAlAparatoEnElPanelDesdeElPrimerDia(t *testing.T) {
	b := montar(t)
	nombre := "el Samsung de Palma"
	w := b.pedir(http.MethodPost, "/sync/aparato", altaEntrada{Nombre: &nombre}, b.quien)
	if w.Code != http.StatusCreated {
		t.Fatalf("tenía que contestar 201, contestó %d (%s)", w.Code, w.Body.String())
	}
	var salida altaSalida
	_ = json.Unmarshal(w.Body.Bytes(), &salida)
	if salida.Aparato == uuid.Nil {
		t.Fatalf("el identificador lo pone la base y se devuelve")
	}
	if salida.Sucursal != b.sucursal {
		t.Fatalf("la sucursal sale de la sesión, no del cuerpo")
	}
	if _, hay := b.base.estados[salida.Aparato]; !hay {
		t.Fatalf("el alta tiene que abrir la fila de estado")
	}

	// Y sale el primero en el panel: nunca ha subido.
	filas, _ := b.base.PanelDeEstado(context.Background(), alcance(&b.sucursal))
	if len(filas) != 2 || filas[0].SubidaAt.Valid {
		t.Fatalf("el que nunca subió va arriba: %+v", filas)
	}
}

// LOS DESCARTADOS LLEGAN AL APARATO, Y SÓLO CUANDO LOS HAY — 28/09/2026.
//
// Un apunte puede aplicarse y **aun así dejar gente fuera**: armar una zona de doce
// devuelve 201 con la ruta creada y, en el mismo cuerpo, quién se cayó y por qué
// (`api/internal/api/tablero.go`, `DescartadoSalida`). Este servicio leía el `id` y tiraba
// el resto, así que la ruta salía con nueve paradas y el teléfono no tenía forma de
// saberlo — el §4 del reparto al revés, «nada se descarta en silencio».
//
// Las dos mitades van juntas a propósito (§3-quinquies del reparto): que llegue cuando se
// cayó alguien, y que **NO llegue** cuando no se cayó nadie. Un aviso que sale en cada
// armado deja de leerse, y entonces tampoco se lee el día que importa; y en una conexión
// que se paga, un `"descartados": []` por apunte es peso a cambio de nada.
func TestLosDescartadosLleganAlAparato(t *testing.T) {
	b := montar(t)

	const fuera = `[{"pedidoId":"0199a1b2-0000-7000-8000-00000000000a",` +
		`"operationNumber":"X-2992","customerName":"Ana Pérez",` +
		`"motivo":"ya no estaba en esa zona cuando llegó tu apunte",` +
		`"queHacer":"comprueba si se entregó igual"}]`

	b.aplicador.descarta = func(p Peticion) json.RawMessage {
		if strings.HasSuffix(p.Ruta, "/route") {
			return json.RawMessage(fuera)
		}
		return nil
	}

	w, salida := b.subir([]apunteEntrada{
		{
			Clave: "01J8DESC1", Hecho: enPunto(t, "2026-09-28T08:05:00Z"),
			Metodo: http.MethodPost, Ruta: "/api/board/columns/z1/route",
			Cuerpo:      json.RawMessage(`{"pedidoIds":["p1","p2"]}`),
			Provisional: "local-9f3a",
		},
		// Un apunte normal, que no descarta a nadie.
		{
			Clave: "01J8DESC2", Hecho: enPunto(t, "2026-09-28T08:06:00Z"),
			Metodo: http.MethodPatch, Ruta: "/api/routes/r1",
			Cuerpo: json.RawMessage(`{"status":"en_curso"}`),
		},
	}, b.quien)

	if len(salida) != 2 {
		t.Fatalf("tenían que volver dos resultados: %+v", salida)
	}
	if salida[0].Estado != EstadoAplicado {
		t.Fatalf("el armado se aplicó, no es un rechazo: %+v", salida[0])
	}
	if !strings.Contains(string(salida[0].Descartados), "X-2992") {
		t.Fatalf("EL APARATO NO SE ENTERA DE QUIÉN SE CAYÓ: el reparto lo dijo con nombre y "+
			"motivo y aquí se perdió. Sin esto la ruta sale con menos pedidos de los que el "+
			"logístico puso y no hay ni un aviso en ningún sitio. Volvió: %q",
			string(salida[0].Descartados))
	}
	if !strings.Contains(string(salida[0].Descartados), "comprueba si se entregó igual") {
		t.Fatalf("el `queHacer` también viaja: un aviso sin qué hacer es una queja. Volvió: %q",
			string(salida[0].Descartados))
	}

	// Y LA OTRA MITAD: el apunte que no descartó a nadie no lleva el campo.
	if salida[1].Descartados != nil {
		t.Fatalf("un apunte que no dejó a nadie fuera NO puede llevar `descartados`: %q",
			string(salida[1].Descartados))
	}
	// Y no lo lleva NI VACÍO EN EL CABLE. Se mira el cuerpo de verdad y no la struct
	// porque lo que se paga es lo que viaja: `omitempty` es lo único que distingue «no se
	// cayó nadie» de «se cayó una lista de cero», y las dos se leen igual desde Dart.
	if strings.Count(w.Body.String(), `"descartados"`) != 1 {
		t.Fatalf("`descartados` tiene que salir SÓLO en el apunte que descartó a alguien; "+
			"el cuerpo fue: %s", w.Body.String())
	}
}

// EL REINTENTO DE UN APUNTE QUE DEJÓ GENTE FUERA TIENE QUE DECIR A QUIÉN.
//
// Es el caso más caro de todos los del reintento, y estuvo escrito como agujero conocido
// desde el día que se hizo `mismaRespuestaQueLaPrimeraVez`:
//
//	se arma una zona sin señal con doce pedidos → el apunte sube → el reparto crea la ruta
//	con NUEVE y nombra a los tres que se cayeron → la respuesta se pierde por el camino.
//
// El aparato, que no recibió nada, reintenta. Aquí se contesta `repetido` —correctamente,
// la regla 1 dice que un apunte se queda como se resolvió la primera vez— pero hasta el
// 29/09/2026 ese `repetido` **iba sin los descartados**, porque no se guardaban.
//
// Lo que se veía: la ruta arriba con nueve de doce, el teléfono enseñando que el armado
// salió bien, y los tres pedidos sin repartir sin que sonara nada en ningún sitio. Es
// exactamente el «nada se descarta en silencio» del §4, roto por el único camino que nadie
// mira — el de la respuesta perdida.
func TestUnRepetidoTambienDiceQuienSeCayo(t *testing.T) {
	b := montar(t)

	const fuera = `[{"pedidoId":"0199a1b2-0000-7000-8000-00000000000a",` +
		`"operationNumber":"X-2992","customerName":"Ana Pérez",` +
		`"motivo":"ya no estaba en esa zona cuando llegó tu apunte",` +
		`"queHacer":"comprueba si se entregó igual"}]`

	b.aplicador.descarta = func(p Peticion) json.RawMessage {
		if strings.HasSuffix(p.Ruta, "/route") {
			return json.RawMessage(fuera)
		}
		return nil
	}

	armar := []apunteEntrada{{
		Clave: "01J8REP1", Hecho: enPunto(t, "2026-09-29T08:05:00Z"),
		Metodo: http.MethodPost, Ruta: "/api/board/columns/z1/route",
		Cuerpo:      json.RawMessage(`{"pedidoIds":["p1","p2"]}`),
		Provisional: "local-9f3a",
	}}

	// PRIMERA VEZ: entra y deja a uno fuera. Esta respuesta es la que se pierde.
	_, primera := b.subir(armar, b.quien)
	if primera[0].Estado != EstadoAplicado {
		t.Fatalf("la primera vez tenía que aplicarse: %+v", primera[0])
	}

	// SEGUNDA VEZ: el aparato, que no se enteró de nada, vuelve a mandar el mismo apunte.
	_, segunda := b.subir(armar, b.quien)
	if segunda[0].Estado != EstadoRepetido {
		t.Fatalf("la segunda vez tenía que ser `repetido`: %+v", segunda[0])
	}
	if !strings.Contains(string(segunda[0].Descartados), "X-2992") {
		t.Fatalf("EL REINTENTO NO DICE QUIÉN SE CAYÓ. La ruta está arriba con menos pedidos "+
			"de los que se pusieron, el aparato da el armado por bueno y los que quedaron "+
			"fuera no salen en ninguna pantalla. Volvió: %q", string(segunda[0].Descartados))
	}
	if !strings.Contains(string(segunda[0].Descartados), "comprueba si se entregó igual") {
		t.Fatalf("el `queHacer` también tiene que volver: un aviso sin qué hacer es una "+
			"queja. Volvió: %q", string(segunda[0].Descartados))
	}
	// Y sigue siendo el MISMO id, que es el resto de la regla 1.
	if primera[0].ID == nil || segunda[0].ID == nil || *primera[0].ID != *segunda[0].ID {
		t.Fatalf("`repetido` tiene que devolver el id de la primera vez: %+v vs %+v",
			primera[0].ID, segunda[0].ID)
	}
}

// Y LA OTRA MITAD, que es la que evita cambiar un silencio por un aviso falso: un apunte
// que no dejó a nadie fuera no puede inventarse una lista vacía al repetirse. «[]» se lee
// como «lo comprobé y no se cayó nadie», y eso sobre un apunte viejo —de antes de que la
// columna existiera— sería afirmar algo que nunca se supo.
func TestUnRepetidoSinDescartadosNoInventaNada(t *testing.T) {
	b := montar(t)

	normal := []apunteEntrada{{
		Clave: "01J8REP2", Hecho: enPunto(t, "2026-09-29T08:06:00Z"),
		Metodo: http.MethodPatch, Ruta: "/api/routes/r1",
		Cuerpo: json.RawMessage(`{"status":"en_curso"}`),
	}}

	b.subir(normal, b.quien)
	_, segunda := b.subir(normal, b.quien)

	if segunda[0].Estado != EstadoRepetido {
		t.Fatalf("la segunda vez tenía que ser `repetido`: %+v", segunda[0])
	}
	if segunda[0].Descartados != nil {
		t.Fatalf("un apunte que no dejó a nadie fuera no puede volver con `descartados`: %q",
			string(segunda[0].Descartados))
	}
}

// 7 · UN 403 DE «TU ROL NO ENTRA A REPARTO» NO DESTRUYE LA COLA (08/10/2026).
//
// Si el reparto contesta 403 con `codigo: "sin_permiso_reparto"`, la subida contesta 403 con
// ese mismo cuerpo y NO ANOTA NADA: ni rechazo, ni apunte, ni la cuenta de la subida. El
// apunte se queda pendiente en el aparato y sube solo el día que se le dé el rol en Accesos.
// Marcarlo `rechazado` —lo que hacía cualquier 4xx— dejaría toda su cola retenida en la
// bandeja, pidiendo a una persona que decida sobre algo que no es del apunte.
func TestSinPermisoDeRepartoNoMarcaNadaRechazadoYContesta403(t *testing.T) {
	b := montar(t)
	b.aplicador.responde = func(p Peticion) (*uuid.UUID, error) {
		return nil, &SinPermiso{Motivo: "No tienes permiso para entrar a Reparto."}
	}

	apuntes := []apunteEntrada{
		{Clave: "01J8H001", Hecho: enPunto(t, "2026-09-14T10:00:00Z"),
			Metodo: http.MethodPost, Ruta: "/api/routes", Cuerpo: json.RawMessage(`{"orderIds":["p1"]}`)},
		{Clave: "01J8H002", Hecho: enPunto(t, "2026-09-14T10:01:00Z"),
			Metodo: http.MethodPost, Ruta: "/api/routes", Cuerpo: json.RawMessage(`{"orderIds":["p2"]}`)},
	}
	w, _ := b.subir(apuntes, b.quien)

	if w.Code != http.StatusForbidden {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if got := strings.TrimSpace(w.Body.String()); got !=
		`{"error":"No tienes permiso para entrar a Reparto.","codigo":"sin_permiso_reparto"}` {
		t.Fatalf("cuerpo %q", got)
	}
	// NADA anotado: ni apuntes, ni rechazos, ni la cuenta de la subida.
	if len(b.base.apuntes) != 0 || len(b.base.rechazos) != 0 {
		t.Fatalf("la cola tenía que quedar intacta: apuntes=%v rechazos=%v", b.base.apuntes, b.base.rechazos)
	}
	if len(b.base.subidas) != 0 {
		t.Fatalf("no se anota la subida: %+v", b.base.subidas)
	}
	// Se cortó en el primero: el segundo ni se intentó (sería otro 403 igual).
	if len(b.aplicador.llamadas) != 1 {
		t.Fatalf("llamadas al reparto: %d", len(b.aplicador.llamadas))
	}

	// Y en cuanto la persona tiene el rol, la MISMA cola sube entera y sin marcas de antes.
	creada := uuid.New()
	b.aplicador.responde = func(p Peticion) (*uuid.UUID, error) { return &creada, nil }
	_, res := b.subir(apuntes, b.quien)
	if len(res) != 2 || res[0].Estado != EstadoAplicado || res[1].Estado != EstadoAplicado {
		t.Fatalf("con el rol dado, la cola tenía que subir entera: %+v", res)
	}
}

// LA PAREJA: el 403 del alcance (un `*Rechazo`, sin `codigo`) SIGUE marcando el apunte
// rechazado y la subida sigue contestando 200. Sin ella, «cualquier error es SinPermiso»
// pasaría la de arriba.
func TestUnRechazoDeAlcanceSigueSiendoRechazoYContesta200(t *testing.T) {
	b := montar(t)
	b.aplicador.responde = func(p Peticion) (*uuid.UUID, error) {
		return nil, &Rechazo{Motivo: "tu sucursal MOA no está dada de alta en Reparto"}
	}
	w, res := b.subir([]apunteEntrada{{
		Clave: "01J8H010", Hecho: enPunto(t, "2026-09-14T10:00:00Z"),
		Metodo: http.MethodPost, Ruta: "/api/routes",
	}}, b.quien)

	if w.Code != http.StatusOK || len(res) != 1 || res[0].Estado != EstadoRechazado {
		t.Fatalf("tenía que salir 200 y rechazado: %d %+v", w.Code, res)
	}
	if _, hay := b.base.rechazos[llave(b.aparato.ID, "01J8H010")]; !hay {
		t.Fatal("el rechazo del alcance tenía que quedar en la bandeja")
	}
}
