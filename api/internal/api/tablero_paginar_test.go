package api

// LA MITAD IZQUIERDA SE PUEDE PAGINAR ENTERA.
//
// `TopeSinColocar` son 200, `limite` sólo podía BAJAR, y la consulta terminaba en `LIMIT`
// sin `OFFSET` y sin cursor. Medido en producción el 17/09/2026, La Habana tenía 300
// pedidos sin colocar: el logístico veía los 200 primeros y LOS 100 ÚLTIMOS NO SE PODÍAN
// PEDIR DE NINGUNA MANERA. `Truncated` avisaba y no llevaba a ningún sitio.
//
// Desde el 14/10/2026 la lista va del más viejo al más reciente por la fecha de la factura
// (issue 6 de Amado) y el cursor es la pareja `fecha|id` de ese `ORDER BY`. Lo que ataca
// el orden contra Postgres de verdad es `TestMotorReal_SinColocarCronologico`.
//
// Es el §3 del CLAUDE.md —pedir un tope y no comprobar el resultado— y el fallo que más
// caro sale en este proyecto, porque no se ve: la pantalla se queda perfectamente normal.
//
// Estas pruebas recorren la lista ENTERA a tandas pequeñas y comprueban las tres cosas que
// tienen que cumplirse a la vez: que se llega al último, que no se repite ninguno, y que
// no se salta ninguno.

import (
	"fmt"
	"net/http"
	"net/url"
	"testing"
	"time"

	"github.com/google/uuid"
)

// sembrar deja `n` pedidos sin colocar en Santiago, todos con la MISMA fecha de pedido y sin
// fecha de factura: el orden lo decide entonces el id, que es el desempate y la parte del
// cursor que más fácil se rompe. El tablero de base ya trae tres (Ana, Beto y Ana otra
// vez), esos sin fecha de ningún tipo.
func sembrar(q *tableroFalso, n int) {
	ayer := time.Date(2026, 9, 16, 10, 0, 0, 0, time.UTC)
	for i := 0; i < n; i++ {
		id := uuid.MustParse(fmt.Sprintf("5e000000-0000-0000-0000-%012d", i+1))
		f := ayer
		q.pedidos[id] = pedidoFalso{
			id: id, sucursal: sucStg, nombre: fmt.Sprintf("Cliente %02d", i+1),
			peso: 1, lat: 20.0247 + float64(i+1)*0.01, lng: -75.8219, fecha: &f,
		}
	}
}

// recorrerLaLista pide tanda tras tanda siguiendo el cursor y devuelve los ids en el orden
// en que salieron, más el total de la primera tanda.
//
// Con un tope de vueltas: si el cursor no avanza —el fallo clásico de un desempate mal
// hecho— esto se quedaría dando vueltas para siempre en vez de fallar, y una prueba
// colgada no dice nada.
func recorrerLaLista(t *testing.T, h http.Handler, jwt string, limite int) ([]string, float64) {
	t.Helper()
	var ids []string
	var total float64
	desde := ""
	for vuelta := 0; ; vuelta++ {
		if vuelta > 50 {
			t.Fatalf("el cursor no avanza: 50 vueltas y todavía queda.\n"+
				"Salieron %d filas y las tres primeras son %v — si se repiten, el "+
				"«desde» no está llegando a la consulta y cada tanda devuelve la misma.",
				len(ids), ids[:min(3, len(ids))])
		}
		ruta := fmt.Sprintf("/api/board/unplaced?limite=%d", limite)
		if desde != "" {
			ruta += "&desde=" + url.QueryEscape(desde)
		}
		w := pedirTab(t, h, http.MethodGet, ruta, jwt, "")
		if w.Code != http.StatusOK {
			t.Fatalf("vuelta %d: código %d — %s", vuelta, w.Code, w.Body.String())
		}
		m := leerTab(t, w)
		if vuelta == 0 {
			total, _ = m["total"].(float64)
		}
		for _, cruda := range m["pedidos"].([]any) {
			ids = append(ids, cruda.(map[string]any)["id"].(string))
		}
		truncado, _ := m["truncated"].(bool)
		siguiente, hay := m["siguiente"].(string)
		if !truncado {
			if hay && siguiente != "" {
				t.Fatalf("vuelta %d: dice que no hay más y manda cursor igual: %q", vuelta, siguiente)
			}
			return ids, total
		}
		if !hay || siguiente == "" {
			t.Fatalf("vuelta %d: dice que hay más tandas y NO manda por dónde seguir. "+
				"Eso es exactamente el fallo que se está arreglando: un aviso de "+
				"truncado que no lleva a ningún sitio — %s", vuelta, w.Body.String())
		}
		desde = siguiente
	}
}

// LA PRUEBA QUE IMPORTA: se llega hasta el último, sin repetidos y sin saltos.
func TestSePuedePedirLaListaEnteraATandas(t *testing.T) {
	q := nuevoTablero()
	sembrar(q, 9) // 9 + los 3 de siempre = 12 sin colocar
	h := montarTab(t, q)

	ids, total := recorrerLaLista(t, h, tokenTab(t, sucStg.String()), 2)

	if total != 12 {
		t.Fatalf("el total dice %v y sin colocar hay 12", total)
	}
	if len(ids) != 12 {
		t.Fatalf("paginando entero salieron %d pedidos de los 12 que hay.\n"+
			"Los que faltan son los MÁS LEJANOS, y son justo los que no se podían pedir "+
			"de ninguna manera: %v", len(ids), ids)
	}
	vistos := map[string]bool{}
	for _, id := range ids {
		if vistos[id] {
			t.Fatalf("el pedido %s salió dos veces: el cursor se está quedando corto en "+
				"el desempate y repite la última fila de cada tanda", id)
		}
		vistos[id] = true
	}
}

// Con tanda de UNO se aprieta el desempate al máximo: cada corte cae entre dos filas.
func TestPaginarDeUnoEnUnoTampocoSeSaltaNingunPedido(t *testing.T) {
	q := nuevoTablero()
	sembrar(q, 5)
	h := montarTab(t, q)

	ids, total := recorrerLaLista(t, h, tokenTab(t, sucStg.String()), 1)
	if int(total) != len(ids) {
		t.Fatalf("el total dice %v y paginando de uno en uno salieron %d: %v",
			total, len(ids), ids)
	}
}

// TRES FACTURAS DE LA MISMA FECHA Y UNA SIN FECHA ES EL CASO QUE ROMPE UN CURSOR MAL HECHO.
//
// Dos facturas anotadas en el mismo instante dan exactamente la misma fecha. Un cursor que
// sólo mirara la fecha o se quedaría pegado —devolviendo siempre las mismas— o se saltaría
// a la vecina. Por eso la pareja es la del `ORDER BY` entera, con el id dentro. Y los sin
// fecha de ningún tipo van al final, que es donde más fácil se cuela un salto.
func TestDosFacturasDeLaMismaFechaNoSePierdenAlPaginar(t *testing.T) {
	q := nuevoTablero()
	misma := time.Date(2026, 9, 10, 8, 0, 0, 0, time.UTC)
	otra := time.Date(2026, 9, 15, 8, 0, 0, 0, time.UTC)
	mismoInstante := []struct {
		id    string
		fecha *time.Time
	}{
		{"6e000000-0000-0000-0000-000000000001", &misma},
		{"6e000000-0000-0000-0000-000000000002", &misma},
		{"6e000000-0000-0000-0000-000000000003", &otra},
		{"6e000000-0000-0000-0000-000000000004", nil},
	}
	for i, m := range mismoInstante {
		id := uuid.MustParse(m.id)
		q.pedidos[id] = pedidoFalso{
			id: id, sucursal: sucStg, nombre: fmt.Sprintf("Vecino %d", i+1),
			peso: 1, lat: 20.0447, lng: -75.8219, facturaAt: m.fecha,
		}
	}
	h := montarTab(t, q)

	ids, total := recorrerLaLista(t, h, tokenTab(t, sucStg.String()), 1)
	if int(total) != len(ids) {
		t.Fatalf("total %v, salieron %d: %v", total, len(ids), ids)
	}
	for _, m := range mismoInstante {
		hay := false
		for _, id := range ids {
			if id == m.id {
				hay = true
			}
		}
		if !hay {
			t.Fatalf("la factura %s no salió en ninguna tanda: el desempate del cursor se "+
				"la saltó — %v", m.id, ids)
		}
	}
}

// LA LISTA VA POR LA FECHA DE LA FACTURA, NO POR LA DEL PEDIDO, Y EL CURSOR TAMBIÉN.
//
// Amado, issue 6 (14/10/2026): «la lista de facturas debe salir ordenada cronológicamente
// de lo más viejo a lo más reciente». La fecha es `factura_at` y, si el pedido no la tiene,
// `order_date`; sin ninguna de las dos, al final.
//
// Los datos están hechos para que ningún orden ACCIDENTAL dé el esperado: el más viejo por
// pedido es el más reciente por factura, y viceversa; ni el id ni la distancia (que crece
// con el sufijo) caminan en el sentido bueno. Y se recorre de uno en uno y de dos en dos:
// si el cursor se armara con `order_date` y no con la fecha por la que se ordenó, las
// tandas se repetirían o saltarían justo en el pedido cuyas dos fechas difieren.
func TestLaListaVaDelMasViejoAlMasRecientePorLaFechaDeLaFactura(t *testing.T) {
	d := func(dia int) *time.Time {
		f := time.Date(2026, 10, dia, 9, 30, 0, 0, time.UTC)
		return &f
	}
	siembra := []struct {
		id        string
		pedido    *time.Time // order_date
		factura   *time.Time // factura_at
		esperaPos int        // lugar esperado entre estos seis (1 = el primero)
	}{
		// Factura del 3: manda sobre un pedido del 14.
		{"8e000000-0000-0000-0000-000000000001", d(14), d(3), 1},
		// Sin factura: vale la fecha del pedido, del 5.
		{"8e000000-0000-0000-0000-000000000002", d(5), nil, 2},
		// Pedido viejísimo del 1 pero facturado el 9: por factura va detrás.
		{"8e000000-0000-0000-0000-000000000003", d(1), d(9), 3},
		// Facturado el 12.
		{"8e000000-0000-0000-0000-000000000004", d(11), d(12), 4},
		// Las dos sin fecha: al final, y entre ellas por id.
		{"8e000000-0000-0000-0000-000000000005", nil, nil, 5},
		{"8e000000-0000-0000-0000-000000000006", nil, nil, 6},
	}
	q := nuevoTablero()
	for _, s := range siembra {
		id := uuid.MustParse(s.id)
		q.pedidos[id] = pedidoFalso{
			id: id, sucursal: sucStg, nombre: "Fecha " + s.id[len(s.id)-1:],
			peso: 1, lat: 20.0247 + float64(s.esperaPos)*0.01, lng: -75.8219,
			fecha: s.pedido, facturaAt: s.factura,
		}
	}
	// Los tres de siempre no tienen fecha de ningún tipo: se quedan detrás de los seis,
	// que son los que se miran. Sus ids (0d…) van ANTES que los 8e… en el desempate de
	// «sin fecha», así que salen los primeros de ese grupo final.
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	esperado := []string{
		"8e000000-0000-0000-0000-000000000001",
		"8e000000-0000-0000-0000-000000000002",
		"8e000000-0000-0000-0000-000000000003",
		"8e000000-0000-0000-0000-000000000004",
	}
	for _, limite := range []int{1, 2, 3, 100} {
		ids, total := recorrerLaLista(t, h, jwt, limite)
		if int(total) != len(ids) {
			t.Fatalf("limite %d: el total dice %v y salieron %d", limite, total, len(ids))
		}
		if len(ids) < len(esperado) {
			t.Fatalf("limite %d: salieron %d pedidos y tendrían que ser al menos %d: %v",
				limite, len(ids), len(esperado), ids)
		}
		for i, id := range esperado {
			if ids[i] != id {
				t.Fatalf("limite %d: en el lugar %d tendría que estar %s y está %s.\n"+
					"Orden entero: %v\nEl orden es del más viejo al más reciente por "+
					"`coalesce(factura_at, order_date)`.", limite, i+1, id, ids[i], ids)
			}
		}
		// Y los dos sin fecha, que son los últimos de los seis, salen DESPUÉS de los
		// cuatro con fecha y en orden de id.
		posicion := map[string]int{}
		for i, id := range ids {
			posicion[id] = i
		}
		for _, conFecha := range esperado {
			for _, sinFecha := range []string{
				"8e000000-0000-0000-0000-000000000005",
				"8e000000-0000-0000-0000-000000000006",
			} {
				if posicion[conFecha] > posicion[sinFecha] {
					t.Fatalf("limite %d: %s (con fecha) sale detrás de %s (sin fecha). "+
						"Un pedido sin fecha no es «el más viejo»: va al final.", limite, conFecha, sinFecha)
				}
			}
		}
		if posicion["8e000000-0000-0000-0000-000000000005"] > posicion["8e000000-0000-0000-0000-000000000006"] {
			t.Fatalf("limite %d: los dos sin fecha no salen por id: %v", limite, ids)
		}
	}
}

// LA CERCANÍA YA NO ORDENA. Es la mitad opuesta de la prueba de arriba, en pareja: el más
// lejano del almacén, si su factura es la más vieja, sale el PRIMERO. Si alguien devuelve
// `km_al_almacen` al `ORDER BY`, aquí cambia el primero.
func TestElMasLejanoConLaFacturaMasViejaSaleElPrimero(t *testing.T) {
	q := nuevoTablero()
	vieja := time.Date(2026, 10, 1, 8, 0, 0, 0, time.UTC)
	nueva := time.Date(2026, 10, 13, 8, 0, 0, 0, time.UTC)
	lejos := uuid.MustParse("8f000000-0000-0000-0000-000000000001")
	cerca := uuid.MustParse("8f000000-0000-0000-0000-000000000002")
	q.pedidos[lejos] = pedidoFalso{id: lejos, sucursal: sucStg, nombre: "Lejos y viejo",
		peso: 1, lat: 20.50, lng: -75.8219, facturaAt: &vieja}
	q.pedidos[cerca] = pedidoFalso{id: cerca, sucursal: sucStg, nombre: "Cerca y nuevo",
		peso: 1, lat: 20.0248, lng: -75.8219, facturaAt: &nueva}
	h := montarTab(t, q)

	ids, _ := recorrerLaLista(t, h, tokenTab(t, sucStg.String()), 100)
	if ids[0] != lejos.String() || ids[1] != cerca.String() {
		t.Fatalf("salen %v: tendría que ir primero el de la factura más vieja (%s), aunque "+
			"sea el más lejano, y después el más reciente (%s)", ids[:2], lejos, cerca)
	}
}

// EL TOTAL ES EL TOTAL Y NO BAJA AL PAGINAR. Es el número de «Sin colocar (300)»: si
// bajara a 100 porque alguien arrastró el dedo, sería un número creíble y equivocado, que
// es lo peor que le puede pasar a un número en esta casa.
func TestElTotalNoBajaAlPedirLaTandaSiguiente(t *testing.T) {
	q := nuevoTablero()
	sembrar(q, 9)
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	primera := leerTab(t, pedirTab(t, h, http.MethodGet, "/api/board/unplaced?limite=2", jwt, ""))
	cursor, _ := primera["siguiente"].(string)
	if cursor == "" {
		t.Fatalf("sin cursor no hay tanda siguiente: %v", primera)
	}
	segunda := leerTab(t, pedirTab(t, h, http.MethodGet,
		"/api/board/unplaced?limite=2&desde="+url.QueryEscape(cursor), jwt, ""))

	if primera["total"] != segunda["total"] {
		t.Fatalf("el total cambió de %v a %v al pasar de tanda: el número de arriba es el "+
			"TOTAL, no lo que queda", primera["total"], segunda["total"])
	}
	if n, _ := segunda["count"].(float64); n != 2 {
		t.Fatalf("la segunda tanda trae %v pedidos y se pidieron 2", segunda["count"])
	}
}

// LA ÚLTIMA TANDA DICE QUE ES LA ÚLTIMA. Antes `truncated` se calculaba restando del
// total, así que en cuanto se paginaba salía `true` para siempre y la pantalla no tenía
// manera de saber cuándo parar.
func TestLaUltimaTandaNoDiceQueHayMas(t *testing.T) {
	q := nuevoTablero() // tres sin colocar
	h := montarTab(t, q)

	m := leerTab(t, pedirTab(t, h, http.MethodGet, "/api/board/unplaced?limite=3",
		tokenTab(t, sucStg.String()), ""))

	if truncado, _ := m["truncated"].(bool); truncado {
		t.Fatalf("caben los tres en la tanda y dice que hay más: %v", m)
	}
	if s, hay := m["siguiente"]; hay && s != nil {
		t.Fatalf("no hay más y manda cursor igual: %v", s)
	}
}

// UN CURSOR QUE NO SE ENTIENDE ES UN 400, NO UNA LISTA VACÍA.
//
// En la base, un cursor a medias deja la comparación en NULL y la consulta devuelve CERO
// filas con un 200 limpio. Eso se lee como «ya no queda nada» justo cuando quedan cien, y
// no deja ni una traza. «Una respuesta vacía no es una respuesta buena.»
func TestUnCursorRotoEs400YNoUnaListaVacia(t *testing.T) {
	q := nuevoTablero()
	sembrar(q, 5)
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	for _, malo := range []string{
		"cualquier-cosa",
		"2026-09-16T10:00:00Z|",
		"no-es-una-fecha|6e000000-0000-0000-0000-000000000001",
		"2026-09-16T10:00:00Z|no-es-un-uuid",
		// EL CURSOR DE ANTES DEL 14/10/2026 (`km|fecha|id`, tres trozos) tiene que ser un
		// 400 y no leerse con el orden nuevo: se repetirían o se saltarían pedidos.
		"12.5|2026-09-16T10:00:00Z|6e000000-0000-0000-0000-000000000001",
		"12.5||6e000000-0000-0000-0000-000000000001",
	} {
		w := pedirTab(t, h, http.MethodGet,
			"/api/board/unplaced?desde="+url.QueryEscape(malo), jwt, "")
		if w.Code != http.StatusBadRequest {
			t.Errorf("cursor %q: código %d, se esperaba 400 — %s", malo, w.Code, w.Body.String())
			continue
		}
		if m := leerTab(t, w); m["error"] == "" {
			t.Errorf("cursor %q: 400 sin decir qué hacer", malo)
		}
	}
}

// Y el cursor no amplía el alcance: sigue saliendo de quién pregunta. Un cursor es una
// posición en la lista propia, no una llave.
func TestElCursorNoSacaPedidosDeOtraSucursal(t *testing.T) {
	q := nuevoTablero()
	sembrar(q, 5)
	h := montarTab(t, q)

	ids, _ := recorrerLaLista(t, h, tokenTab(t, sucStg.String()), 2)
	for _, id := range ids {
		if id == pedHol.String() {
			t.Fatal("paginando apareció el pedido de Holguín")
		}
	}
}
