package api

import (
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

// LO QUE EL SERVIDOR TIENE Y NO ESCRIBE.
//
// Es la clase de fallo que más caro sale en esta casa, y el 17/09/2026 se cazó tres veces
// el mismo día, ninguna leyendo el código:
//
//   - Las rutas viajaban sin `totalPrice`, `originAddress` ni `deliveryDate`: el aparato
//     enseñaba **$0.00** en una ruta de 720 USD, «Sin punto de partida» teniendo almacén y
//     una raya donde va la fecha.
//   - Los pedidos viajaban sin `createdAt`, y con él se caía la guarda que acota por fecha
//     los que vienen sin `orderDate`: desaparecían de CUALQUIER filtro por fecha en la APK.
//   - El padrón viajaba sin `source`: los 8.000 clientes salían como «Manual» y el filtro
//     de origen contestaba al revés.
//
// Las tres tienen la misma forma: **el dato está en la fila, la columna existe en el
// aparato, y la función que arma el JSON no lo escribe.** No hay error, no hay pantalla en
// blanco, no hay tirón. Sale un cero, y un cero se lee bien.
//
// Y las tres se pudieron deshacer enteras sin que nada se pusiera rojo, porque lo único
// que las sujetaba era un comentario que decía que existía esta prueba. No existía. Un
// comentario no falla (`CLAUDE.md` §3-bis).
//
// Por eso esto comprueba **claves**, no valores: lo que se rompe es que una clave deje de
// escribirse, y eso no lo nota ningún `assert` sobre un número.
func TestLaBajadaNoPierdeCamposPorElCamino(t *testing.T) {
	q := nuevoEspejo()
	desde := conBajas(q)

	// Una ruta con TODO relleno: si un campo no se escribe, no sale la clave.
	ahora := pgtype.Timestamptz{Time: time.Now().UTC(), Valid: true}
	direccion := "Almacén Camagüey, Carretera Central km 3"
	q.rutasDelEspejo = []sqlc.ListarRutasRow{{
		ID:            rutaViva,
		BranchID:      pgtype.UUID{Bytes: [16]byte(sucStg), Valid: true},
		OriginAddress: &direccion,
		TotalPrice:    720,
		TotalDistance: 33.6,
		DeliveryDate:  ahora,
		StartedAt:     ahora,
		FinishedAt:    ahora,
		CreatedAt:     ahora,
		UpdatedAt:     ahora,
	}}

	// Un pedido facturado, cambiado después de `desde`, con su número y su fecha de factura.
	facturadoEl := time.Date(2026, 10, 12, 9, 30, 0, 0, time.UTC)
	q.sync = append(q.sync, pedidoSync{
		id: ped1, sucursal: sucStg, nombre: "Facturado", marca: time.Now().UTC().Add(-1 * time.Hour),
		facturaNumero: "1024237", facturaAt: &facturadoEl,
	})

	cambios := bajadaDe(t, q, tokenTab(t, sucStg.String()),
		"?desde="+desde.Format(time.RFC3339Nano))

	// --- Rutas: lo que se arregló el 17/09 -----------------------------------
	//
	// `originAddress`, `totalPrice` y `deliveryDate` son los tres que Jose vio mal en la
	// pantalla. `startedAt` y `finishedAt` son la línea de «Salida» y «Regreso» de la hoja
	// del post-despacho, la que firma el chofer: sin ellos la hoja sale sin horario y
	// tampoco se nota.
	exigirClaves(t, cambios, "routes", []string{
		"id", "name", "routeCode", "status",
		"originAddress", "originLat", "originLng",
		"totalDistance", "totalWeight", "totalPrice",
		"deliveryDate", "vehicleId", "branchId",
		"startedAt", "finishedAt", "createdAt", "updatedAt",
	})

	// --- Pedidos: la factura, que faltaba en 14/10/2026 --------------------------
	//
	// `facturaNumero` viajaba y `facturaAt` NO: la columna `orders.factura_at` existía en el
	// aparato y valía NULL en todos los pedidos. Amado (issues 6 y 8) pide la fecha de
	// facturación en el detalle y «Sin colocar» ordenado por ella: sin esta clave el detalle
	// no la puede decir y la lista cae, sin avisar, a la fecha del pedido.
	exigirClaves(t, cambios, "orders", []string{
		"id", "operationNumber", "orderDate", "createdAt",
		"facturaEstado", "facturaNumero", "facturaAt", "facturaDomicilio",
	})
	// Y no basta con la clave: `"facturaAt": nil` también la tiene. El valor tiene que ser
	// el del pedido, en el formato de las demás fechas.
	pedido := cambios["cambios"].(map[string]any)["orders"].(map[string]any)["puestos"].([]any)[0].(map[string]any)
	if pedido["facturaNumero"] != "1024237" {
		t.Errorf("orders: facturaNumero = %v, tendría que ser 1024237", pedido["facturaNumero"])
	}
	llego, _ := pedido["facturaAt"].(string)
	esperada := facturadoEl.Format(time.RFC3339Nano)
	if llego != esperada {
		t.Errorf("orders: facturaAt = %q, tendría que ser %q. El aparato la guarda tal cual para "+
			"ordenar «Sin colocar» y para decir cuándo se facturó.", llego, esperada)
	}
}

// exigirClaves comprueba que el primer elemento de `puestos` de esa colección trae todas
// las claves, y **nombra la que falta**: «routes: falta `totalPrice`» dice dónde mirar;
// «el JSON no coincide» no dice nada.
func exigirClaves(t *testing.T, cambios map[string]any, coleccion string, claves []string) {
	t.Helper()
	c, ok := cambios["cambios"].(map[string]any)[coleccion].(map[string]any)
	if !ok {
		t.Fatalf("la bajada no trae la colección %q", coleccion)
	}
	puestos, _ := c["puestos"].([]any)
	if len(puestos) == 0 {
		t.Fatalf("%s: no vino ningún elemento, así que esto no comprueba nada", coleccion)
	}
	fila, _ := puestos[0].(map[string]any)
	for _, k := range claves {
		if _, hay := fila[k]; !hay {
			t.Errorf(
				"%s: falta la clave %q.\n"+
					"El dato está en la fila de Go y la columna existe en el aparato: lo que\n"+
					"falla es que esta función no lo escribe. Sin ella el aparato enseña el\n"+
					"valor por defecto —un cero, un nulo— que se lee perfectamente bien y\n"+
					"está mal, y ninguna pantalla lo desmiente.",
				coleccion, k,
			)
		}
	}
}
