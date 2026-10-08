package api

// LO QUE NADIE IBA A TECLEAR, TECLEADO.
//
// Estas pruebas salen de romper la API desde fuera el 24/09/2026 —no de leer el diff— y
// cada una guarda un caso que llegó a pasar contra el servidor de pruebas. Van en pareja,
// que es la regla de la casa: la guarda salta cuando toca y **no** salta cuando no. Sin la
// segunda mitad, una guarda que rechazara SIEMPRE dejaría la primera en verde y la
// aplicación inservible.
//
//	1. Coordenadas fuera del planeta -> la respuesta salía con 201 y el cuerpo VACÍO, y
//	   la lista de rutas se quedaba muda para siempre.
//	2. La misma parada dos veces en una hoja de cierre -> dos avisos contradictorios a
//	   PEDIDO sobre el mismo pedido.
//	3. Capacidad y costo por km imposibles -> el freno del sobrepeso deja de medir y el
//	   kilómetro pasa a pagar.

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"procovar/reparto-api/internal/store/sqlc"
)

// ---------------------------------------------------------------------------
// 1 · El punto de partida tiene que caer en el mapa
// ---------------------------------------------------------------------------

// EL CASO, literal. `POST /api/routes` con `"originLat": 1e308` contestaba:
//
//	HTTP 201, cuerpo: ""            (cero bytes)
//
// y a partir de ahí `GET /api/routes` contestaba `200` con cero bytes. La ruta quedaba
// guardada con `total_distance = NaN` porque `(0 - 1e308) * math.Pi` se desborda a -Inf y
// `math.Sin(-Inf)` es NaN; `json.Encoder` se niega a codificar eso, y el código de éxito
// ya estaba escrito. Nadie ve un error: ve una pantalla de rutas vacía.
func TestArmarConUnOrigenFueraDelPlanetaSeRechazaYNoEnvenenaLaLista(t *testing.T) {
	imposibles := []struct{ nombre, lat, lng string }{
		{"una latitud desbordada", "1e308", "1e308"},
		{"una latitud de 91 grados", "91", "0"},
		{"una longitud de 200 grados", "0", "200"},
		{"el polo sur pasado de largo", "-90.0001", "0"},
	}
	for _, caso := range imposibles {
		t.Run(caso.nombre, func(t *testing.T) {
			d, pedidos, _ := datosDeReparto()
			h := montarRutas(t, d)
			jwt := deSantiagoEnRutas(t)

			// Primero una ruta buena, para tener la lista con algo dentro.
			buena := armarRutaDePrueba(t, h, jwt, pedidos[1])

			cuerpo := fmt.Sprintf(`{"vehicleId":%q,"originLat":%s,"originLng":%s,"orderIds":[%q]}`,
				camionStg, caso.lat, caso.lng, pedidos[0])
			w := llamarRutas(t, h, http.MethodPost, "/api/routes", jwt, cuerpo)

			if w.Code != http.StatusBadRequest {
				t.Fatalf("un origen en (%s, %s) tiene que ser un 400 y fue %d con %d bytes de cuerpo.\n"+
					"  Si fue 201 con el cuerpo vacío, es EL fallo: la ruta se guardó con la distancia "+
					"en NaN y la lista de rutas se queda muda a partir de ahora.",
					caso.lat, caso.lng, w.Code, w.Body.Len())
			}
			if msg := errorDeRutas(t, w); !strings.Contains(msg, "no es un punto del mapa") {
				t.Fatalf("el mensaje tiene que decir qué pasa y qué hacer, y fue %q", msg)
			}

			// Y LA LISTA SIGUE VIVA. Ésta es la mitad que de verdad dolía: comprobar sólo
			// el 400 dejaría pasar una guarda que rechazara la petición DESPUÉS de haber
			// escrito la ruta.
			w = llamarRutas(t, h, http.MethodGet, "/api/routes", jwt, "")
			if w.Code != http.StatusOK || w.Body.Len() == 0 {
				t.Fatalf("la lista de rutas se quedó rota: %d con %d bytes", w.Code, w.Body.Len())
			}
			var lista []RutaSalida
			if err := json.Unmarshal(w.Body.Bytes(), &lista); err != nil {
				t.Fatalf("la lista dejó de ser JSON legible: %v — %q", err, w.Body.String())
			}
			if len(lista) != 1 || lista[0].ID != buena {
				t.Fatalf("la lista tiene que traer sólo la ruta buena y trajo %d", len(lista))
			}
		})
	}
}

// LA OTRA MITAD: los orígenes normales siguen armando ruta. El cero incluido, que el
// contrato declara válido —es lo que manda la pantalla mientras el mapa carga— y es
// justamente el valor que una guarda escrita con prisa (`lat != 0`) se llevaría por
// delante.
func TestArmarConUnOrigenNormalSigueArmandoRuta(t *testing.T) {
	buenos := []struct{ nombre, lat, lng string }{
		{"el cero del contrato", "0", "0"},
		{"Santiago de Cuba", "20.0247", "-75.8219"},
		{"el borde exacto del planeta", "90", "180"},
		{"el otro borde exacto", "-90", "-180"},
	}
	for _, caso := range buenos {
		t.Run(caso.nombre, func(t *testing.T) {
			d, pedidos, _ := datosDeReparto()
			h := montarRutas(t, d)
			cuerpo := fmt.Sprintf(`{"vehicleId":%q,"originLat":%s,"originLng":%s,"orderIds":[%q]}`,
				camionStg, caso.lat, caso.lng, pedidos[0])
			w := llamarRutas(t, h, http.MethodPost, "/api/routes", deSantiagoEnRutas(t), cuerpo)
			if w.Code != http.StatusCreated {
				t.Fatalf("un origen en (%s, %s) es legítimo y tiene que armar: %d %s",
					caso.lat, caso.lng, w.Code, w.Body.String())
			}
			var ruta RutaSalida
			if err := json.Unmarshal(w.Body.Bytes(), &ruta); err != nil {
				t.Fatalf("respuesta ilegible: %v", err)
			}
			// Y el número que sale tiene que poder leerse. Un NaN aquí es el envenenamiento
			// otra vez, por otra puerta.
			if math.IsNaN(ruta.TotalDistance) || math.IsInf(ruta.TotalDistance, 0) {
				t.Fatalf("totalDistance salió %v: eso rompe la codificación de toda respuesta que lo lleve",
					ruta.TotalDistance)
			}
		})
	}
}

// LA SEGUNDA PUERTA A LA MISMA AVERÍA: las coordenadas de las PARADAS no las teclea nadie
// —vienen del espejo de PEDIDO— y una fuera del mapa hace exactamente lo mismo con
// `total_distance`. Se rechaza NOMBRANDO el pedido, porque desde aquí no se arregla: hay
// que corregir la dirección en PEDIDO, y un «vuelve a intentarlo» sería un reintento
// imposible de los que prohíbe el CLAUDE.md.
func TestArmarConUnaParadaFueraDelMapaDiceCualEsYNoArma(t *testing.T) {
	d, pedidos, _ := datosDeReparto()
	malo := d.pedidos[pedidos[0]]
	*malo.endLat = 1e308

	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	w := llamarRutas(t, h, http.MethodPost, "/api/routes", jwt,
		cuerpoDeArmado(camionStg.String(), pedidos[0], pedidos[1]))

	if w.Code != http.StatusConflict {
		t.Fatalf("una parada fuera del mapa tiene que ser 409 y fue %d con %d bytes: %s",
			w.Code, w.Body.Len(), w.Body.String())
	}
	msg := errorDeRutas(t, w)
	if !strings.Contains(msg, "fuera del mapa") {
		t.Fatalf("el mensaje no dice qué pasa: %q", msg)
	}
	if !strings.Contains(msg, *malo.operacion) {
		t.Fatalf("el mensaje tiene que NOMBRAR el pedido (%s) o hay que quitarlos de uno en uno: %q",
			*malo.operacion, msg)
	}
	if !strings.Contains(msg, "PEDIDO") {
		t.Fatalf("el mensaje tiene que decir dónde se arregla: %q", msg)
	}

	// Y NO SE ARMÓ NADA A MEDIAS: el otro pedido sigue libre.
	if d.pedidos[pedidos[1]].rutaID != nil {
		t.Fatal("el pedido bueno quedó enganchado a una ruta que no llegó a existir")
	}
}

// La otra mitad: con las paradas donde tienen que estar, se arma igual que siempre.
func TestArmarConLasParadasEnSuSitioSigueArmando(t *testing.T) {
	d, pedidos, _ := datosDeReparto()
	h := montarRutas(t, d)
	w := llamarRutas(t, h, http.MethodPost, "/api/routes", deSantiagoEnRutas(t),
		cuerpoDeArmado(camionStg.String(), pedidos[0], pedidos[1]))
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
}

// ---------------------------------------------------------------------------
// 2 · La misma parada dos veces en una hoja de cierre
// ---------------------------------------------------------------------------

// EL CASO. La cola del aparato junta apuntes cuando vuelve la señal, así que una hoja de
// cierre puede traer el mismo `orderId` dos veces —y con resultados distintos, que es la
// corrección del caso S3 del guion de QA: «entregado» y luego «devuelto»—.
//
// En la base no hay duda: son dos UPDATE y manda el segundo, el pedido queda `devuelto`.
// En PEDIDO sí la había: se le mandaban LOS DOS avisos en el mismo lote y cuál gana depende
// de en qué orden los aplique él. El vendedor podía quedarse viendo «entregado» sobre un
// pedido que volvió en el camión — un estado creíble y equivocado, con las dos aplicaciones
// diciendo cosas distintas del mismo pedido.
func TestUnaHojaDeCierreConElMismoPedidoDosVecesMandaUnSoloAvisoYElUltimo(t *testing.T) {
	d, pedidos, _ := datosDeReparto()
	h, s := montarRutasCon(t, d)
	jwt := deSantiagoEnRutas(t)
	ruta := armarRutaDePrueba(t, h, jwt, pedidos[0], pedidos[1])

	var mandados []AvisoDeParada
	s.aPedido = func(_ context.Context, avisos []AvisoDeParada) ParteAPedido {
		mandados = append(mandados, avisos...)
		return ParteAPedido{Ok: true, Enviados: len(avisos), Aplicados: len(avisos)}
	}

	cuerpo := fmt.Sprintf(`{"resultados":[
		{"orderId":%q,"resultado":"entregado"},
		{"orderId":%q,"resultado":"devuelto","nota":"volvió en el camión"},
		{"orderId":%q,"resultado":"entregado"}]}`,
		pedidos[0], pedidos[0], pedidos[1])
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+ruta.String()+"/results", jwt, cuerpo)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}

	// UN aviso por pedido. Dos son los dos estados contradictorios viajando juntos.
	porPedido := map[string][]string{}
	for _, a := range mandados {
		porPedido[a.PedidoID] = append(porPedido[a.PedidoID], a.Estado)
	}
	ext := *d.pedidos[pedidos[0]].externalID
	if len(porPedido[ext]) != 1 {
		t.Fatalf("a PEDIDO le fueron %d avisos del pedido %s (%v).\n"+
			"  Con dos, cuál gana depende del orden en que PEDIDO los aplique: el vendedor "+
			"puede acabar viendo «entregado» sobre un pedido que volvió en el camión.",
			len(porPedido[ext]), ext, porPedido[ext])
	}
	// Y ES EL ÚLTIMO, que es el que la base acaba teniendo. Mandar el primero sería la
	// misma discrepancia con el sello de garantía puesto.
	if porPedido[ext][0] != string(sqlc.StopResultDevuelto) {
		t.Fatalf("a PEDIDO le fue %q y la base se quedó en «devuelto»: las dos aplicaciones "+
			"dirían cosas distintas del mismo pedido", porPedido[ext][0])
	}
	if d.pedidos[pedidos[0]].resultado == nil || *d.pedidos[pedidos[0]].resultado != sqlc.StopResultDevuelto {
		t.Fatalf("la base tenía que quedarse en «devuelto» y quedó en %v", d.pedidos[pedidos[0]].resultado)
	}
	// La nota que viaja es la del apunte que ganó.
	for _, a := range mandados {
		if a.PedidoID == ext && a.Nota != "volvió en el camión" {
			t.Fatalf("el aviso que salió lleva la nota %q, que no es la del resultado que quedó", a.Nota)
		}
	}

	// `aplicados` NO se recorta: es el acuse de lo que se procesó, y el aparato lo compara
	// con lo que mandó.
	var salida salidaDeCierre
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	if len(salida.Aplicados) != 3 {
		t.Fatalf("aplicados tiene que llevar las 3 entradas procesadas y llevó %d", len(salida.Aplicados))
	}
}

// LA OTRA MITAD: una hoja normal —cada pedido una vez— manda un aviso por pedido y no se
// come ninguno. Sin esto, un «manda sólo el último aviso de todos» pasaría la de arriba.
func TestUnaHojaDeCierreNormalMandaUnAvisoPorCadaPedido(t *testing.T) {
	d, pedidos, _ := datosDeReparto()
	h, s := montarRutasCon(t, d)
	jwt := deSantiagoEnRutas(t)
	ruta := armarRutaDePrueba(t, h, jwt, pedidos[0], pedidos[1], pedidos[2])

	var mandados []AvisoDeParada
	s.aPedido = func(_ context.Context, avisos []AvisoDeParada) ParteAPedido {
		mandados = append(mandados, avisos...)
		return ParteAPedido{Ok: true, Enviados: len(avisos), Aplicados: len(avisos)}
	}

	cuerpo := fmt.Sprintf(`{"resultados":[
		{"orderId":%q,"resultado":"entregado"},
		{"orderId":%q,"resultado":"devuelto"},
		{"orderId":%q,"resultado":"cancelado"}]}`,
		pedidos[0], pedidos[1], pedidos[2])
	if w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+ruta.String()+"/results", jwt, cuerpo); w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}

	if len(mandados) != 3 {
		t.Fatalf("tenían que salir 3 avisos, uno por pedido, y salieron %d: %+v", len(mandados), mandados)
	}
	esperado := map[string]string{
		*d.pedidos[pedidos[0]].externalID: string(sqlc.StopResultEntregado),
		*d.pedidos[pedidos[1]].externalID: string(sqlc.StopResultDevuelto),
		*d.pedidos[pedidos[2]].externalID: string(sqlc.StopResultCancelado),
	}
	for _, a := range mandados {
		if esperado[a.PedidoID] != a.Estado {
			t.Fatalf("al pedido %s le fue el estado %q y la base dice %q", a.PedidoID, a.Estado, esperado[a.PedidoID])
		}
		delete(esperado, a.PedidoID)
	}
	if len(esperado) != 0 {
		t.Fatalf("estos pedidos se cerraron y PEDIDO no se enteró: %v", esperado)
	}
}

// ---------------------------------------------------------------------------
// 3 · Los dos números de un camión
// ---------------------------------------------------------------------------

// La capacidad es el ÚNICO freno contra un camión sobrecargado
// (`pesoTotal > vehiculo.Capacity`). Con cero o negativa deja de medir: rechaza todas las
// rutas, incluso la de un bulto, con un mensaje que no se puede entender.
//
// El costo por km negativo es el hermano del cero que el CLAUDE.md §2 ya manda dejar
// vacío: se lee igual de bien que un positivo y significa que el kilómetro paga.
func TestUnCamionConNumerosImposiblesNoSeDaDeAlta(t *testing.T) {
	casos := []struct{ nombre, cuerpo, dice string }{
		{"capacidad cero", `{"name":"C","capacity":0}`, "mayor que cero"},
		{"capacidad negativa", `{"name":"C","capacity":-500}`, "mayor que cero"},
		{"costo por km negativo", `{"name":"C","costoKmUsd":-1.5}`, "no puede ser negativo"},
	}
	for _, caso := range casos {
		t.Run(caso.nombre, func(t *testing.T) {
			h := montarAvisos(t, &dobleAvisos{})
			w := pedirAv(t, h, http.MethodPost, "/api/vehicles", avLogisticoStg(t), caso.cuerpo)
			if w.Code != http.StatusBadRequest {
				t.Fatalf("código %d, se esperaba 400: %s", w.Code, w.Body.String())
			}
			if !strings.Contains(w.Body.String(), caso.dice) {
				t.Fatalf("el mensaje no explica qué está mal: %s", w.Body.String())
			}
		})
	}
	// Y por la otra puerta a la misma fila: el PATCH.
	t.Run("y tampoco por un PATCH", func(t *testing.T) {
		h := montarAvisos(t, &dobleAvisos{})
		w := pedirAv(t, h, http.MethodPatch, "/api/vehicles/"+avVehStg.String(), avLogisticoStg(t),
			`{"capacity":-1}`)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("código %d, se esperaba 400: %s", w.Code, w.Body.String())
		}
	})
	// Y en el TIPO, que es el valor por defecto de toda la flota que lo use.
	t.Run("ni en el tipo de vehículo", func(t *testing.T) {
		h := montarAvisos(t, &dobleAvisos{})
		w := pedirAv(t, h, http.MethodPost, "/api/vehicle-types", avAdmin(t),
			`{"nombre":"rastra","costoKmUsd":-0.5}`)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("código %d, se esperaba 400: %s", w.Code, w.Body.String())
		}
	})
}

// LA OTRA MITAD, y aquí es la que importa de verdad: lo normal sigue entrando. Un camión
// sin capacidad dicha se queda con los 1.000 kg del contrato, y un costo por km VACÍO
// —«usa el del tipo», que es el hueco que el CLAUDE.md §2 manda dejar— no es un error.
func TestUnCamionNormalSigueDandoseDeAlta(t *testing.T) {
	casos := []struct {
		nombre, cuerpo string
		capacidad      float64
	}{
		{"sin decir la capacidad", `{"name":"C"}`, CapacidadPorDefecto},
		{"con la capacidad puesta", `{"name":"C","capacity":3500.5}`, 3500.5},
		{"con capacidad y sin costo por km", `{"name":"C","capacity":800}`, 800},
		{"con el costo por km a cero", `{"name":"C","capacity":800,"costoKmUsd":0}`, 800},
		{"con el costo por km vacío", `{"name":"C","capacity":800,"costoKmUsd":null}`, 800},
	}
	for _, caso := range casos {
		t.Run(caso.nombre, func(t *testing.T) {
			h := montarAvisos(t, &dobleAvisos{})
			w := pedirAv(t, h, http.MethodPost, "/api/vehicles", avLogisticoStg(t), caso.cuerpo)
			if w.Code != http.StatusCreated {
				t.Fatalf("código %d, se esperaba 201: %s", w.Code, w.Body.String())
			}
			var v VehiculoSalida
			if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
				t.Fatalf("respuesta ilegible: %v", err)
			}
			if v.Capacity != caso.capacidad {
				t.Fatalf("capacidad %v, se esperaba %v", v.Capacity, caso.capacidad)
			}
		})
	}
	t.Run("y el tipo con su costo normal", func(t *testing.T) {
		h := montarAvisos(t, &dobleAvisos{})
		w := pedirAv(t, h, http.MethodPost, "/api/vehicle-types", avAdmin(t),
			`{"nombre":"rastra","costoKmUsd":0.42}`)
		if w.Code != http.StatusCreated {
			t.Fatalf("código %d, se esperaba 201: %s", w.Code, w.Body.String())
		}
	})
	t.Run("y el tipo SIN costo, que es el hueco que hay que dejar", func(t *testing.T) {
		h := montarAvisos(t, &dobleAvisos{})
		w := pedirAv(t, h, http.MethodPost, "/api/vehicle-types", avAdmin(t), `{"nombre":"rastra"}`)
		if w.Code != http.StatusCreated {
			t.Fatalf("código %d, se esperaba 201: %s", w.Code, w.Body.String())
		}
		var tipo TipoVehiculoSalida
		if err := json.Unmarshal(w.Body.Bytes(), &tipo); err != nil {
			t.Fatalf("respuesta ilegible: %v", err)
		}
		if tipo.CostoKmUsd != nil {
			t.Fatalf("un tipo sin costo tiene que quedarse VACÍO y quedó en %v: "+
				"un cero guardado se lee como «el kilómetro es gratis»", *tipo.CostoKmUsd)
		}
	})
}

// ---------------------------------------------------------------------------
// 4 · La ubicación del cliente que no cae en el planeta
// ---------------------------------------------------------------------------

// `POST /api/quote/home-delivery` es la ÚNICA cuenta de dinero que hace esta API, y el
// número que devuelve lo cobra la APK tal cual. El contrato de delivery sólo comprueba
// `Number.isFinite`, y una latitud de 200 es finita: pasaba, la haversine daba un número
// grande con sentido aparente y salía un domicilio cobrado a cientos de kilómetros. Es el
// caso que el CLAUDE.md §4 pone como lo peor que puede pasar —«un importe así se lee bien y
// está mal»—.
//
// Se comprueba ANTES de mirar la sucursal a propósito: así la prueba no necesita ni tasa ni
// almacén, y el 400 que espera no puede venir de otro sitio.
func TestCotizarUnDomicilioConLaUbicacionFueraDelPlanetaSeRechaza(t *testing.T) {
	casos := []struct{ nombre, lat, lng string }{
		{"latitud de 200 grados", "200", "-75.8"},
		{"longitud de 1000 grados", "20.0", "1000"},
		{"latitud desbordada", "1e308", "-75.8"},
	}
	for _, caso := range casos {
		t.Run(caso.nombre, func(t *testing.T) {
			h := montarCotizacion(t, &dobleDePanel{})
			cuerpo := fmt.Sprintf(`{"sucursalCodigo":"STG","lat":%s,"lng":%s,"pesoKg":12}`, caso.lat, caso.lng)
			r := httptest.NewRequest(http.MethodPost, "/api/quote/home-delivery", strings.NewReader(cuerpo))
			r.Header.Set("X-Api-Key", claveDeServicioDePrueba)
			r.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()
			h.ServeHTTP(w, r)

			if w.Code != http.StatusBadRequest {
				t.Fatalf("una ubicación en (%s, %s) tiene que ser 400 y fue %d: %s\n"+
					"  Si salió un importe, es un número que alguien va a cobrar y está mal.",
					caso.lat, caso.lng, w.Code, w.Body.String())
			}
			if !strings.Contains(w.Body.String(), "no es un punto del mapa") {
				t.Fatalf("el mensaje no dice qué pasa ni dónde se arregla: %s", w.Body.String())
			}
		})
	}
}

// LA OTRA MITAD: una ubicación normal sigue pasando de la guarda. No se comprueba el
// importe —para eso hace falta tasa, tarifa y almacén, y eso lo prueban las de
// `internal/cotizar`—: lo que se comprueba es que la guarda NO se traga una coordenada
// legítima. Por eso se exige que el fallo, si lo hay, sea otro.
func TestCotizarUnDomicilioConUnaUbicacionNormalNoLoParaEstaGuarda(t *testing.T) {
	buenas := []struct{ nombre, lat, lng string }{
		{"Santiago de Cuba", "20.0247", "-75.8219"},
		{"el cero", "0", "0"},
		{"el borde del planeta", "-90", "180"},
	}
	for _, caso := range buenas {
		t.Run(caso.nombre, func(t *testing.T) {
			h := montarCotizacion(t, &dobleDePanel{})
			cuerpo := fmt.Sprintf(`{"sucursalCodigo":"STG","lat":%s,"lng":%s,"pesoKg":12}`, caso.lat, caso.lng)
			r := httptest.NewRequest(http.MethodPost, "/api/quote/home-delivery", strings.NewReader(cuerpo))
			r.Header.Set("X-Api-Key", claveDeServicioDePrueba)
			r.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()
			h.ServeHTTP(w, r)

			if strings.Contains(w.Body.String(), "no es un punto del mapa") {
				t.Fatalf("(%s, %s) es una coordenada legítima y la guarda la rechazó: %s\n"+
					"  Una guarda que rechaza lo normal deja la aplicación inservible.",
					caso.lat, caso.lng, w.Body.String())
			}
		})
	}
}
