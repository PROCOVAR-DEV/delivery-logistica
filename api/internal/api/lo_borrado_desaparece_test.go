package api

// LO QUE SE BORRA EN EL SERVIDOR TIENE QUE DESAPARECER DEL APARATO.
//
// El 17/09/2026 Jose miró su teléfono y vio una ruta que ya no existía en el servidor:
// «Completada», 0 paradas, 2,6 km. Sus palabras: «¿por qué no actualiza a partir de lo que
// tiene el servidor? Eso no puede pasar».
//
// El protocolo lo contemplaba desde el principio —`Conjunto.Quitados`— pero sólo estaba
// implementado para `orders`. Las otras siete colecciones pasaban por `conjunto()`, que
// devolvía `[]string{}` SIEMPRE, así que una ruta borrada, un camión dado de baja o una
// zona del tablero quitada desde la web se quedaban en el aparato para siempre.
//
// ESTE FICHERO VIGILA LAS DOS MITADES, y la segunda importa más que la primera:
//
//  1. Que lo que se fue SALGA en `quitados`.
//  2. Que lo que sigue existiendo NO SALGA NUNCA. Una lápida mal puesta borra trabajo del
//     teléfono del repartidor, y ése es el riesgo de todo este cambio.
//
// LO QUE ESTAS PRUEBAS **NO** COMPRUEBAN, y hay que saberlo antes de fiarse: corren contra
// el doble de `espejo_test.go`, que reimplementa el `WHERE` de `db/queries/bajas.sql` en
// Go. Comprueban que el MANEJADOR acota cada colección como acota su lista y que tacha lo
// que sigue vivo. Que los DISPARADORES de `00006_bajas_de_la_bajada.sql` pongan y quiten la
// lápida cuando toca sólo lo puede comprobar un Postgres de verdad, y en esta máquina no
// hay ninguno. Lo que sí se vigila sin base es el TEXTO del SQL, en
// `internal/store/guardas_del_reparto_test.go`.

import (
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

var (
	rutaViva        = uuid.MustParse("7a000000-0000-0000-0000-000000000001")
	rutaBorrada     = uuid.MustParse("7a000000-0000-0000-0000-000000000002")
	rutaMudada      = uuid.MustParse("7a000000-0000-0000-0000-000000000003")
	rutaSinSucursal = uuid.MustParse("7a000000-0000-0000-0000-000000000004")
	rutaVieja       = uuid.MustParse("7a000000-0000-0000-0000-000000000005")
	rutaDeHolguin   = uuid.MustParse("7a000000-0000-0000-0000-000000000006")

	vehVivo         = uuid.MustParse("7b000000-0000-0000-0000-000000000001")
	vehBorrado      = uuid.MustParse("7b000000-0000-0000-0000-000000000002")
	vehSinSucursal  = uuid.MustParse("7b000000-0000-0000-0000-000000000003")
	vehDeHolguin    = uuid.MustParse("7b000000-0000-0000-0000-000000000004")
	colBorrada      = uuid.MustParse("7c000000-0000-0000-0000-000000000001")
	colBorradaDeHol = uuid.MustParse("7c000000-0000-0000-0000-000000000002")
	pedSacado       = uuid.MustParse("7d000000-0000-0000-0000-000000000001")
	prodBorrado     = uuid.MustParse("7e000000-0000-0000-0000-000000000001")
	cliBorrado      = uuid.MustParse("7f000000-0000-0000-0000-000000000002")
	sucBorrada      = uuid.MustParse("70000000-0000-0000-0000-000000000009")
)

// conBajas deja el espejo con lo vivo y lo que se fue, repartido a los dos lados de una
// marca y a los dos lados del alcance. Devuelve la marca que el aparato manda en `desde`.
func conBajas(q *espejoFalso) time.Time {
	ahora := time.Now().UTC()
	marca := ahora.Add(-12 * time.Hour)
	antes := ahora.Add(-24 * time.Hour)
	despues := ahora.Add(-1 * time.Hour)

	pg := func(id uuid.UUID) pgtype.UUID {
		return pgtype.UUID{Bytes: [16]byte(id), Valid: true}
	}
	reciente := pgtype.Timestamptz{Time: despues, Valid: true}

	// LAS LISTAS, que son la red de seguridad: lo que está aquí no puede salir en
	// `quitados` pase lo que pase.
	q.rutasDelEspejo = []sqlc.ListarRutasRow{
		{ID: rutaViva, BranchID: pg(sucStg), UpdatedAt: reciente},
		{ID: rutaDeHolguin, BranchID: pg(sucHol), UpdatedAt: reciente},
	}
	q.vehiculosDelEspejo = []sqlc.ListarVehiculosRow{
		{ID: vehVivo, BranchID: pg(sucStg), UpdatedAt: reciente},
	}
	// Tres tarjetas puestas en Centro (Santiago): ped1, ped2, ped3.
	q.tresPuestas()

	q.bajas = []bajaSync{
		// --- Rutas ---
		{sqlc.ColeccionDeLaBajadaRoutes, rutaBorrada.String(), &sucStg, sqlc.MotivoDeBajaBorrado, despues},
		{sqlc.ColeccionDeLaBajadaRoutes, rutaMudada.String(), &sucStg, sqlc.MotivoDeBajaMovido, despues},
		// LA LÁPIDA MENTIROSA: dice que se fue algo que sigue en la lista. Puede pasar si
		// un disparador no limpió al volver a entrar, y tiene que tacharse.
		{sqlc.ColeccionDeLaBajadaRoutes, rutaViva.String(), &sucStg, sqlc.MotivoDeBajaBorrado, despues},
		// Anterior a la marca que manda el aparato: ya se la llevó en su día.
		{sqlc.ColeccionDeLaBajadaRoutes, rutaVieja.String(), &sucStg, sqlc.MotivoDeBajaBorrado, antes},
		// Sin sucursal: `ListarRutas` no se la enseña a un aparato acotado, así que su
		// lápida tampoco.
		{sqlc.ColeccionDeLaBajadaRoutes, rutaSinSucursal.String(), nil, sqlc.MotivoDeBajaBorrado, despues},
		// De otra sucursal.
		{sqlc.ColeccionDeLaBajadaRoutes, rutaDeHolguin.String(), &sucHol, sqlc.MotivoDeBajaBorrado, despues},

		// --- Vehículos ---
		{sqlc.ColeccionDeLaBajadaVehicles, vehBorrado.String(), &sucStg, sqlc.MotivoDeBajaBorrado, despues},
		// SIN SUCURSAL, y aquí sí tiene que llegar: `ListarVehiculos` lleva
		// `OR v.branch_id IS NULL`, así que ese camión lo ven los ocho aparatos.
		{sqlc.ColeccionDeLaBajadaVehicles, vehSinSucursal.String(), nil, sqlc.MotivoDeBajaBorrado, despues},
		{sqlc.ColeccionDeLaBajadaVehicles, vehDeHolguin.String(), &sucHol, sqlc.MotivoDeBajaBorrado, despues},

		// --- Sucursales ---
		{sqlc.ColeccionDeLaBajadaBranches, sucBorrada.String(), &sucBorrada, sqlc.MotivoDeBajaBorrado, despues},

		// --- Tablero ---
		{sqlc.ColeccionDeLaBajadaBoardColumns, colBorrada.String(), &sucStg, sqlc.MotivoDeBajaBorrado, despues},
		{sqlc.ColeccionDeLaBajadaBoardColumns, colBorradaDeHol.String(), &sucHol, sqlc.MotivoDeBajaBorrado, despues},
		{sqlc.ColeccionDeLaBajadaBoardPlacements, pedSacado.String(), &sucStg, sqlc.MotivoDeBajaBorrado, despues},
		// La tarjeta que salió y VOLVIÓ esa misma tarde: sigue colocada, así que su lápida
		// no puede viajar. Es el caso que pasa cada día, porque la clave es el pedido.
		{sqlc.ColeccionDeLaBajadaBoardPlacements, ped1.String(), &sucStg, sqlc.MotivoDeBajaBorrado, despues},

		// --- Catálogo y padrón: globales, sin sucursal ---
		{sqlc.ColeccionDeLaBajadaProducts, prodBorrado.String(), nil, sqlc.MotivoDeBajaBorrado, despues},
		{sqlc.ColeccionDeLaBajadaCustomers, cliBorrado.String(), nil, sqlc.MotivoDeBajaBorrado, despues},
	}
	return marca
}

// bajasDe saca `cambios.<nombre>.quitados`. No vale `conjuntoDe`, que lee el `id` de cada
// puesto: una colocación del tablero no tiene `id`, se identifica por su `pedidoId`.
func bajasDe(t *testing.T, m map[string]any, nombre string) map[string]bool {
	t.Helper()
	c, hay := m["cambios"].(map[string]any)[nombre]
	if !hay {
		t.Fatalf("no vino la colección %q", nombre)
	}
	crudos, hay := c.(map[string]any)["quitados"]
	if !hay || crudos == nil {
		t.Fatalf("la colección %q vino sin «quitados»: es null y el aparato no lo recorre", nombre)
	}
	fuera := map[string]bool{}
	for _, q := range crudos.([]any) {
		fuera[q.(string)] = true
	}
	return fuera
}

func bajadaDe(t *testing.T, q *espejoFalso, jwt, cola string) map[string]any {
	t.Helper()
	h := montarTab(t, q)
	w := pedirTab(t, h, http.MethodGet, "/api/sync/cambios"+cola, jwt, "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	return leerTab(t, w)
}

// ---------------------------------------------------------------------------
// 1. Lo que se fue, sale
// ---------------------------------------------------------------------------

// LA DE JOSE. Una ruta borrada en el servidor tiene que llegar al aparato como «bórrala».
func TestUnaRutaBorradaDesapareceDelAparato(t *testing.T) {
	q := nuevoEspejo()
	marca := conBajas(q)

	m := bajadaDe(t, q, tokenTab(t, sucStg.String()),
		"?desde="+marca.Format(time.RFC3339Nano))
	fuera := bajasDe(t, m, "routes")

	if !fuera[rutaBorrada.String()] {
		t.Fatalf("la ruta borrada no salió en «quitados»: el aparato la sigue enseñando "+
			"«Completada» con 0 paradas, que es justo lo que Jose vio en su teléfono.\n%v", fuera)
	}
	// Y la que se MUDÓ de sucursal también: su fila sigue existiendo, pero con otra
	// sucursal, así que nunca más saldría en la lista de Santiago.
	if !fuera[rutaMudada.String()] {
		t.Fatalf("la ruta que se mudó de sucursal no salió en «quitados»: %v", fuera)
	}
}

// Las demás colecciones, cada una con el caso que duele.
func TestCadaColeccionDiceLoQueSeFue(t *testing.T) {
	q := nuevoEspejo()
	marca := conBajas(q)
	m := bajadaDe(t, q, tokenTab(t, sucStg.String()),
		"?desde="+marca.Format(time.RFC3339Nano))

	casos := []struct {
		coleccion string
		clave     uuid.UUID
		porQue    string
	}{
		{"vehicles", vehBorrado,
			"un camión dado de baja que sigue en el teléfono se puede asignar a una ruta"},
		{"boardColumns", colBorrada,
			"una zona borrada desde la web sigue en el tablero del repartidor y él coloca tarjetas ahí"},
		{"boardPlacements", pedSacado,
			"una tarjeta que ya no está en el tablero se queda pegada en la zona equivocada"},
		{"products", prodBorrado,
			"un producto borrado sigue ofreciéndose en el buscador: es prometer mercancía que no hay"},
		{"customers", cliBorrado,
			"el padrón sólo crece; `BorrarClientesDelEspejoQueYaNoVienen` borra de golpe y sin esto nadie se entera"},
	}
	for _, c := range casos {
		t.Run(c.coleccion, func(t *testing.T) {
			if !bajasDe(t, m, c.coleccion)[c.clave.String()] {
				t.Fatalf("«%s» no informó de su baja.\nPor qué importa: %s", c.coleccion, c.porQue)
			}
		})
	}
}

// Las sucursales se las lleva quien ve las ocho: a un aparato acotado a Santiago sólo
// podría llegarle la baja de Santiago, que es otro problema.
func TestUnaSucursalBorradaSeLeDiceAQuienVeLasOcho(t *testing.T) {
	q := nuevoEspejo()
	marca := conBajas(q)
	m := bajadaDe(t, q, tokenTab(t, ""), "?desde="+marca.Format(time.RFC3339Nano))

	if !bajasDe(t, m, "branches")[sucBorrada.String()] {
		t.Fatalf("una sucursal borrada no salió en «quitados»: %s", m["cambios"])
	}
}

// ---------------------------------------------------------------------------
// 2. Lo que sigue vivo NO sale — el riesgo de verdad de este cambio
// ---------------------------------------------------------------------------

// UNA LÁPIDA DE ALGO QUE SIGUE EN LA LISTA SE TACHA.
//
// No es un caso de laboratorio: la clave de una colocación del tablero es el PEDIDO, así
// que una tarjeta que sale de una zona y vuelve a otra esa misma tarde reusa su clave.
// Si la lápida vieja viajara, la misma bajada diría «tenla» en `puestos` y «bórrala» en
// `quitados`, y cuál gana dependería del orden en que el aparato las aplique.
func TestNadaQueSigaVivoSaleEnQuitados(t *testing.T) {
	q := nuevoEspejo()
	marca := conBajas(q)
	m := bajadaDe(t, q, tokenTab(t, sucStg.String()),
		"?desde="+marca.Format(time.RFC3339Nano))

	if bajasDe(t, m, "routes")[rutaViva.String()] {
		t.Fatal("se mandó borrar una ruta que sigue en la lista del servidor: " +
			"una lápida mal puesta borra trabajo del aparato")
	}
	if bajasDe(t, m, "boardPlacements")[ped1.String()] {
		t.Fatal("se mandó borrar una tarjeta que sigue colocada: la misma bajada dice " +
			"«tenla» y «bórrala», y gana la que el aparato aplique la última")
	}
	// Y lo mismo dicho desde el otro lado: nada de `quitados` puede estar en `puestos`.
	for _, coleccion := range []string{"routes", "vehicles", "branches", "boardColumns"} {
		puestos, _, _ := conjuntoDe(t, m, coleccion)
		for clave := range bajasDe(t, m, coleccion) {
			if puestos[clave] {
				t.Fatalf("%s: «%s» viene en «puestos» y en «quitados» a la vez", coleccion, clave)
			}
		}
	}
}

// LO ANTERIOR A LA MARCA NO SE REPITE: el aparato ya se lo llevó, y remandarlo es gastarle
// la conexión en decirle que borre lo que ya borró.
func TestLoQueSeFueAntesDeLaMarcaNoSeVuelveAMandar(t *testing.T) {
	q := nuevoEspejo()
	marca := conBajas(q)
	m := bajadaDe(t, q, tokenTab(t, sucStg.String()),
		"?desde="+marca.Format(time.RFC3339Nano))

	if bajasDe(t, m, "routes")[rutaVieja.String()] {
		t.Fatal("volvió a salir una baja anterior al «desde» que mandó el aparato")
	}
}

// EN LA CARGA INICIAL NO SE MANDA NI UNA BAJA. El aparato empieza vacío: no hay nada que
// quitarle, y mandarle los borrados de los últimos dos años es gastarle la conexión en
// decirle que borre lo que nunca tuvo.
func TestLaCargaInicialNoTraeBajasDeNingunaColeccion(t *testing.T) {
	q := nuevoEspejo()
	conBajas(q)
	m := bajadaDe(t, q, tokenTab(t, sucStg.String()), "")

	for _, coleccion := range []string{
		"routes", "vehicles", "branches", "products", "customers",
		"boardColumns", "boardPlacements", "settings",
	} {
		if fuera := bajasDe(t, m, coleccion); len(fuera) != 0 {
			t.Fatalf("la carga inicial trae bajas de «%s» y el aparato no tiene nada: %v",
				coleccion, fuera)
		}
	}
}

// ---------------------------------------------------------------------------
// 3. El alcance: cada lápida se acota COMO SU LISTA, ni más ni menos
// ---------------------------------------------------------------------------

// LAS DOS COLECCIONES QUE NO SE ACOTAN IGUAL, en la misma prueba y a propósito.
//
// `ListarVehiculos` lleva `OR v.branch_id IS NULL` —un camión sin sucursal lo ven los ocho
// aparatos— y `ListarRutas` no lo lleva. Copiar mal esa diferencia rompe por los dos lados:
// el camión sin sucursal se queda en los ocho teléfonos para siempre, o al aparato de
// Santiago le llega la orden de borrar una ruta que nunca fue suya.
func TestLasBajasSeAcotanComoSuLista(t *testing.T) {
	q := nuevoEspejo()
	marca := conBajas(q)
	m := bajadaDe(t, q, tokenTab(t, sucStg.String()),
		"?desde="+marca.Format(time.RFC3339Nano))

	if !bajasDe(t, m, "vehicles")[vehSinSucursal.String()] {
		t.Fatal("un camión SIN sucursal dado de baja no llegó al aparato de Santiago, " +
			"y `ListarVehiculos` sí se lo enseñaba (`OR v.branch_id IS NULL`): " +
			"se le queda en el teléfono para siempre")
	}
	if bajasDe(t, m, "routes")[rutaSinSucursal.String()] {
		t.Fatal("llegó la baja de una ruta SIN sucursal a un aparato acotado, " +
			"y `ListarRutas` nunca se la enseñó: se le manda borrar algo que no es suyo")
	}
	// Y lo de la sucursal de al lado no llega nunca, en ninguna de las dos.
	if bajasDe(t, m, "routes")[rutaDeHolguin.String()] {
		t.Fatal("llegó a Santiago la baja de una ruta de Holguín")
	}
	if bajasDe(t, m, "vehicles")[vehDeHolguin.String()] {
		t.Fatal("llegó a Santiago la baja de un camión de Holguín")
	}
}

// A QUIEN VE LAS OCHO NO SE LE BORRA LO QUE SÓLO SE MUDÓ.
//
// Una ruta que pasa de Santiago a Holguín sigue en su lista; mandársela en `quitados` le
// borraría del aparato algo que existe. Borrado sí es borrado para todos.
func TestQuienVeLasOchoSoloSeLlevaLoBorrado(t *testing.T) {
	q := nuevoEspejo()
	marca := conBajas(q)
	m := bajadaDe(t, q, tokenTab(t, ""), "?desde="+marca.Format(time.RFC3339Nano))
	fuera := bajasDe(t, m, "routes")

	if fuera[rutaMudada.String()] {
		t.Fatal("a quien ve las ocho se le mandó borrar una ruta que sólo cambió de " +
			"sucursal: la sigue viendo, y se le borra del aparato")
	}
	if !fuera[rutaBorrada.String()] {
		t.Fatalf("a quien ve las ocho no le llegó una ruta BORRADA: %v", fuera)
	}
}

// EL TABLERO SE ACOTA POR LA SUCURSAL QUE SE MIRA, igual que sus dos listas.
func TestElTableroNoSeLlevaLasBajasDeOtraSucursal(t *testing.T) {
	q := nuevoEspejo()
	marca := conBajas(q)
	m := bajadaDe(t, q, tokenTab(t, ""),
		"?sucursal="+sucStg.String()+"&desde="+marca.Format(time.RFC3339Nano))
	fuera := bajasDe(t, m, "boardColumns")

	if !fuera[colBorrada.String()] {
		t.Fatalf("no llegó la baja de la zona de la sucursal que se está mirando: %v", fuera)
	}
	if fuera[colBorradaDeHol.String()] {
		t.Fatal("llegó la baja de una zona de OTRA sucursal: el tablero se sirve por " +
			"sucursal y sus bajas tienen que acotarse igual")
	}
}

// ---------------------------------------------------------------------------
// 4. La ventana: el tope y el horizonte
// ---------------------------------------------------------------------------

// EL TOPE TAMBIÉN ACOTA LAS BAJAS, y cuando corta, la marca que se devuelve RETROCEDE.
//
// Sin esto, el aparato se apuntaría el reloj del servidor como «ya lo tengo todo» con la
// mitad de las bajas sin mandar, y esas bajas no se vuelven a pedir nunca: la ruta borrada
// se queda en el teléfono igual que antes de este cambio.
func TestElTopeTambienAcotaLasBajasYLaMarcaRetrocede(t *testing.T) {
	q := nuevoEspejo()
	ahora := time.Now().UTC()
	marca := ahora.Add(-12 * time.Hour)

	// Cinco bajas de rutas, cada una con su propia marca para que el corte sea limpio.
	for i := range 5 {
		id := uuid.New()
		q.bajas = append(q.bajas, bajaSync{
			coleccion: sqlc.ColeccionDeLaBajadaRoutes, clave: id.String(),
			sucursal: &sucStg, motivo: sqlc.MotivoDeBajaBorrado,
			salioAt: ahora.Add(time.Duration(-10+i) * time.Minute),
		})
	}

	m := bajadaDe(t, q, tokenTab(t, sucStg.String()),
		"?tope=2&desde="+marca.Format(time.RFC3339Nano))

	if len(bajasDe(t, m, "routes")) != 2 {
		t.Fatalf("con tope 2 tenían que venir 2 bajas: %v", bajasDe(t, m, "routes"))
	}
	if truncado, _ := m["truncado"].(bool); !truncado {
		t.Fatal("no cupo todo y no se dijo «truncado»: el aparato no vuelve a pedir")
	}
	hasta, err := time.Parse(time.RFC3339, m["hasta"].(string))
	if err != nil {
		t.Fatalf("«hasta» ilegible: %v", m["hasta"])
	}
	if !hasta.Before(ahora.Add(-5 * time.Minute)) {
		t.Fatalf("la marca no retrocedió al corte (%v): lo que no cupo cae por debajo del "+
			"próximo «desde» y no se pide nunca más", hasta)
	}
}

// UNA MARCA MÁS VIEJA QUE EL HORIZONTE SE DICE, no se calla.
//
// Las lápidas se podan. Pasado el horizonte ya no están, así que se puede contestar lo que
// cambió pero no lo que se fue, y el aparato se quedaría creyéndose al día con rutas y
// clientes que no existen. `CLAUDE.md` §4: nada se descarta en silencio.
func TestUnaMarcaMasViejaQueElHorizonteAvisa(t *testing.T) {
	q := nuevoEspejo()
	conBajas(q)

	viejisima := time.Now().UTC().Add(-HorizonteDeLapidas - 24*time.Hour)
	m := bajadaDe(t, q, tokenTab(t, sucStg.String()),
		"?desde="+viejisima.Format(time.RFC3339Nano))
	aviso, _ := m["aviso"].(string)
	if aviso == "" || !strings.Contains(aviso, "carga entera") {
		t.Fatalf("un «desde» anterior al horizonte de las lápidas no avisó de nada: %q", aviso)
	}

	// Y una marca de dentro del horizonte NO avisa: un aviso que sale siempre deja de
	// leerse, y entonces tampoco se lee el día que importa.
	m = bajadaDe(t, q, tokenTab(t, sucStg.String()),
		"?desde="+time.Now().UTC().Add(-time.Hour).Format(time.RFC3339Nano))
	if aviso, _ := m["aviso"].(string); strings.Contains(aviso, "carga entera") {
		t.Fatalf("avisó de lápidas podadas con un «desde» de hace una hora: %q", aviso)
	}
}

// UN GRUPO DE LÁPIDAS CON LA MISMA HORA MÁS GRANDE QUE EL TOPE LLEGA ENTERO, POR LOTES (28/10/2026).
//
// El 21/10/2026 el espejo borró 2.828 facturas de Santiago en UNA transacción (misma hora al
// microsegundo) con el tope en 2.000: el corte no podía caer sin partir el grupo y las 828 de más no
// llegaron nunca a ningún aparato, que siguió enseñando facturas que ya no existen (Maikel metió 171 en
// la zona «descarte»). Aquí, 7 lápidas con la misma hora y tope 3: la cadena de `continuar` las trae
// las 7, sin repetir ni saltar ninguna.
func TestUnGrupoDeLapidasConLaMismaHoraLlegaEnteroPorLotes(t *testing.T) {
	q := nuevoEspejo()
	ahora := time.Now().UTC()
	misma := ahora.Add(-6 * time.Hour)
	quitar := map[string]bool{}
	for range 7 {
		id := uuid.New()
		quitar[id.String()] = true
		q.salidas = append(q.salidas, salidaSync{
			pedido: id, sucursal: sucStg, motivo: sqlc.SalidaDePedidoBorrado, salioAt: misma,
		})
	}

	desde := ahora.Add(-12 * time.Hour)
	continuar := ""
	llegaron := map[string]int{}
	for vuelta := 0; vuelta < 10; vuelta++ {
		cola := "?tope=3&desde=" + desde.Format(time.RFC3339Nano)
		if continuar != "" {
			cola += "&continuar=" + continuar
		}
		m := bajadaDe(t, q, tokenTab(t, sucStg.String()), cola)
		for id := range bajasDe(t, m, "orders") {
			llegaron[id]++
		}
		if truncado, _ := m["truncado"].(bool); !truncado {
			break
		}
		continuar, _ = m["continuar"].(string)
		if continuar == "" {
			t.Fatal("dice «truncado» y no da por dónde seguir: el aparato repetiría la misma tanda")
		}
		h, err := time.Parse(time.RFC3339, m["hasta"].(string))
		if err != nil {
			t.Fatalf("«hasta» ilegible: %v", m["hasta"])
		}
		desde = h
	}
	for id := range quitar {
		if llegaron[id] != 1 {
			t.Errorf("la lápida %s llegó %d veces (tenía que ser 1): %v", id, llegaron[id], llegaron)
		}
	}
	if len(llegaron) != len(quitar) {
		t.Errorf("llegaron %d lápidas y había %d", len(llegaron), len(quitar))
	}
}

// LO MISMO PARA LAS LÁPIDAS DE LAS DEMÁS COLECCIONES (clientes, rutas, camiones, zonas…): un grupo con la misma hora
// mayor que el tope llega entero por lotes con el cursor `(hora, clave)` (28/10/2026). Clientes tuvo uno de 1.711,
// a un borrado grande del tope.
func TestUnGrupoDeBajasConLaMismaHoraLlegaEnteroPorLotes(t *testing.T) {
	q := nuevoEspejo()
	ahora := time.Now().UTC()
	misma := ahora.Add(-6 * time.Hour)
	quitar := map[string]bool{}
	for range 7 {
		id := uuid.New()
		quitar[id.String()] = true
		q.bajas = append(q.bajas, bajaSync{
			coleccion: sqlc.ColeccionDeLaBajadaRoutes, clave: id.String(),
			sucursal: &sucStg, motivo: sqlc.MotivoDeBajaBorrado, salioAt: misma,
		})
	}

	desde := ahora.Add(-12 * time.Hour)
	continuar := ""
	llegaron := map[string]int{}
	for vuelta := 0; vuelta < 10; vuelta++ {
		cola := "?tope=3&desde=" + desde.Format(time.RFC3339Nano)
		if continuar != "" {
			cola += "&continuar=" + continuar
		}
		m := bajadaDe(t, q, tokenTab(t, sucStg.String()), cola)
		for id := range bajasDe(t, m, "routes") {
			llegaron[id]++
		}
		if truncado, _ := m["truncado"].(bool); !truncado {
			break
		}
		continuar, _ = m["continuar"].(string)
		if continuar == "" {
			t.Fatal("dice «truncado» y no da por dónde seguir")
		}
		h, err := time.Parse(time.RFC3339, m["hasta"].(string))
		if err != nil {
			t.Fatalf("«hasta» ilegible: %v", m["hasta"])
		}
		desde = h
	}
	for id := range quitar {
		if llegaron[id] != 1 {
			t.Errorf("la baja %s llegó %d veces (tenía que ser 1): %v", id, llegaron[id], llegaron)
		}
	}
	if len(llegaron) != len(quitar) {
		t.Errorf("llegaron %d bajas y había %d", len(llegaron), len(quitar))
	}
}
