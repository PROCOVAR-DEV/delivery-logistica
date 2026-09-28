package api

// Las pruebas del espejo. Sin VPN, sin Ventra y sin PEDIDO: el lector de Ventra es una
// interfaz y los dos servicios de fuera son `httptest`, así que esto se corre en cada
// compilación y no «cuando haya una Ventra a mano».

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

// --------------------------------------------------------------------------- el doble

type espejoFalso struct {
	*tableroFalso

	ajustes   sqlc.Setting
	marcada   int
	guardados map[string]int // sucursal|sku -> veces que se escribió

	// Los pedidos y las lápidas de la bajada. Van aparte de `tableroFalso.pedidos`: el
	// tablero necesita coordenadas y peso, y esto necesita marcas de tiempo y renglones.
	sync    []pedidoSync
	salidas []salidaSync

	// Las lápidas de TODO LO DEMÁS (`bajas_de_la_bajada`, 00006): rutas, camiones,
	// sucursales, catálogo, padrón y las dos del tablero.
	bajas []bajaSync

	// Las listas que sirve la bajada para esas colecciones. Están aquí y no en
	// `tableroFalso` porque lo que hace falta comprobar es OTRA cosa: que lo que sigue en
	// la lista NO salga en `quitados` pase lo que pase.
	rutasDelEspejo     []sqlc.ListarRutasRow
	vehiculosDelEspejo []sqlc.ListarVehiculosRow

	// El padrón de clientes de la bajada, entero. El doble lo sirve por tandas
	// respetando `Limite` y `Desplazamiento`, como el SQL: lo que se comprueba es que el
	// manejador sepa pedir la tanda siguiente.
	padron []sqlc.ListarClientesRow

	// El catálogo de la bajada, servido igual que el padrón: por tandas y respetando el
	// `cambiado_desde`.
	catalogoDelEspejo []sqlc.Product
}

func nuevoEspejo() *espejoFalso {
	return &espejoFalso{
		tableroFalso: nuevoTablero(),
		guardados:    map[string]int{},
	}
}

// --------------------------------------------------------------- la bajada de pedidos
//
// EL DOBLE REPITE LAS REGLAS DEL SQL, no contesta lo que le pidan: el `desde` estricto, el
// `hasta` inclusivo, las dos sucursales en AND, el interruptor de los archivados, el orden
// por la marca y el tope. Lo que hay que comprobar aquí es que el manejador respeta lo que
// la consulta le devuelve —y, sobre todo, que `cambiado_at` es el MÁS NUEVO del pedido y
// de sus renglones—, y con un doble que dijera a todo que sí no se comprobaría nada.

type renglonSync struct {
	linea int32
	desc  string
	marca time.Time // el `updated_at` del renglón
}

type pedidoSync struct {
	id        uuid.UUID
	sucursal  uuid.UUID
	nombre    string
	archivado bool
	marca     time.Time // el `updated_at` del pedido
	renglones []renglonSync
}

// cambiadoAt es el `GREATEST(o.updated_at, max(oi.updated_at))` de la consulta.
func (p pedidoSync) cambiadoAt() time.Time {
	m := p.marca
	for _, r := range p.renglones {
		if r.marca.After(m) {
			m = r.marca
		}
	}
	return m
}

type salidaSync struct {
	pedido   uuid.UUID
	sucursal uuid.UUID
	motivo   sqlc.SalidaDePedido
	salioAt  time.Time
}

func (q *espejoFalso) DiferenciasDePedidos(_ context.Context, arg sqlc.DiferenciasDePedidosParams) ([]sqlc.DiferenciasDePedidosRow, error) {
	var filas []sqlc.DiferenciasDePedidosRow
	for _, p := range q.sync {
		cambiado := p.cambiadoAt()
		// `desde` ESTRICTO y `hasta` INCLUSIVO, como el SQL: dos ventanas seguidas no se
		// pisan ni dejan hueco.
		if arg.Desde.Valid && !cambiado.After(arg.Desde.Time) {
			continue
		}
		if arg.Hasta.Valid && cambiado.After(arg.Hasta.Time) {
			continue
		}
		if arg.Sucursal.Valid && [16]byte(p.sucursal) != arg.Sucursal.Bytes {
			continue
		}
		if arg.BranchID.Valid && [16]byte(p.sucursal) != arg.BranchID.Bytes {
			continue
		}
		if p.archivado && !arg.ConArchivados {
			continue
		}
		filas = append(filas, sqlc.DiferenciasDePedidosRow{
			ID:           p.id,
			CustomerName: p.nombre,
			Address:      "una calle",
			Archivado:    p.archivado,
			BranchID:     pgtype.UUID{Bytes: [16]byte(p.sucursal), Valid: true},
			UpdatedAt:    pgtype.Timestamptz{Time: p.marca, Valid: true},
			CambiadoAt:   pgtype.Timestamptz{Time: cambiado, Valid: true},
		})
	}
	sort.Slice(filas, func(i, j int) bool {
		if filas[i].CambiadoAt.Time.Equal(filas[j].CambiadoAt.Time) {
			return filas[i].ID.String() < filas[j].ID.String()
		}
		return filas[i].CambiadoAt.Time.Before(filas[j].CambiadoAt.Time)
	})
	if int(arg.Tope) < len(filas) {
		filas = filas[:arg.Tope]
	}
	return filas, nil
}

func (q *espejoFalso) ListarRenglonesDePedidos(_ context.Context, arg sqlc.ListarRenglonesDePedidosParams) ([]sqlc.ListarRenglonesDePedidosRow, error) {
	pedidos := map[uuid.UUID]bool{}
	for _, id := range arg.PedidoIds {
		pedidos[id] = true
	}
	var salida []sqlc.ListarRenglonesDePedidosRow
	for _, p := range q.sync {
		if !pedidos[p.id] {
			continue
		}
		// El alcance va también aquí, como en el SQL: `order_items` no tiene sucursal y
		// sin el cruce bastaría con acertar un uuid para leer la mercancía de otra.
		if arg.Sucursal.Valid && [16]byte(p.sucursal) != arg.Sucursal.Bytes {
			continue
		}
		for _, r := range p.renglones {
			salida = append(salida, sqlc.ListarRenglonesDePedidosRow{
				ID: uuid.New(), OrderID: p.id, Linea: r.linea,
				Description: r.desc, Quantity: 1,
				UpdatedAt: pgtype.Timestamptz{Time: r.marca, Valid: true},
			})
		}
	}
	return salida, nil
}

func (q *espejoFalso) PedidosQueSalieronDelAlcance(_ context.Context, arg sqlc.PedidosQueSalieronDelAlcanceParams) ([]sqlc.PedidosQueSalieronDelAlcanceRow, error) {
	var filas []sqlc.PedidosQueSalieronDelAlcanceRow
	for _, f := range q.salidas {
		if arg.Desde.Valid && !f.salioAt.After(arg.Desde.Time) {
			continue
		}
		if arg.Hasta.Valid && f.salioAt.After(arg.Hasta.Time) {
			continue
		}
		if arg.Sucursal.Valid && [16]byte(f.sucursal) != arg.Sucursal.Bytes {
			continue
		}
		if arg.BranchID.Valid && [16]byte(f.sucursal) != arg.BranchID.Bytes {
			continue
		}
		// Sin sucursal ninguna —el Super Admin, que ve las ocho— sólo cuentan los
		// borrados: mudarse de sucursal no lo saca de SU vista.
		if !arg.Sucursal.Valid && !arg.BranchID.Valid && f.motivo != sqlc.SalidaDePedidoBorrado {
			continue
		}
		filas = append(filas, sqlc.PedidosQueSalieronDelAlcanceRow{
			OrderID:  f.pedido,
			BranchID: pgtype.UUID{Bytes: [16]byte(f.sucursal), Valid: true},
			Motivo:   f.motivo,
			SalioAt:  pgtype.Timestamptz{Time: f.salioAt, Valid: true},
		})
	}
	sort.Slice(filas, func(i, j int) bool { return filas[i].SalioAt.Time.Before(filas[j].SalioAt.Time) })
	if int(arg.Tope) < len(filas) {
		filas = filas[:arg.Tope]
	}
	return filas, nil
}

// ------------------------------------------------- las lápidas de las demás colecciones

type bajaSync struct {
	coleccion sqlc.ColeccionDeLaBajada
	clave     string
	// nil = lápida SIN sucursal: el catálogo, el padrón y un camión que no tenía ninguna.
	sucursal *uuid.UUID
	motivo   sqlc.MotivoDeBaja
	salioAt  time.Time
}

// BajasDeLaBajada REPITE EL `WHERE` DEL SQL, condición por condición, y no contesta lo
// que le pidan. Es lo mismo que hace el doble de los pedidos y por la misma razón: un
// doble que dijera a todo que sí aprobaría un manejador que acota mal, que es justo el
// fallo que borra trabajo del teléfono.
//
// Las cinco condiciones, en el mismo orden que `db/queries/bajas.sql`:
// la colección, el `desde` estricto, el `hasta` inclusivo, las dos sucursales en AND
// —con el `sin_sucursal_tambien` que copia el `OR v.branch_id IS NULL` de los vehículos—
// y el «sin sucursal ninguna, sólo los borrados».
func (q *espejoFalso) BajasDeLaBajada(_ context.Context, arg sqlc.BajasDeLaBajadaParams) ([]sqlc.BajasDeLaBajadaRow, error) {
	var filas []sqlc.BajasDeLaBajadaRow
	for _, b := range q.bajas {
		if b.coleccion != arg.Coleccion {
			continue
		}
		if arg.Desde.Valid && !b.salioAt.After(arg.Desde.Time) {
			continue
		}
		if arg.Hasta.Valid && b.salioAt.After(arg.Hasta.Time) {
			continue
		}
		if arg.Sucursal.Valid {
			cuadra := b.sucursal != nil && [16]byte(*b.sucursal) == arg.Sucursal.Bytes
			if !cuadra && !(b.sucursal == nil && arg.SinSucursalTambien) {
				continue
			}
		}
		if arg.BranchID.Valid {
			if b.sucursal == nil || [16]byte(*b.sucursal) != arg.BranchID.Bytes {
				continue
			}
		}
		if !arg.Sucursal.Valid && !arg.BranchID.Valid && b.motivo != sqlc.MotivoDeBajaBorrado {
			continue
		}
		fila := sqlc.BajasDeLaBajadaRow{
			Coleccion: b.coleccion,
			Clave:     b.clave,
			Motivo:    b.motivo,
			SalioAt:   pgtype.Timestamptz{Time: b.salioAt, Valid: true},
		}
		if b.sucursal != nil {
			fila.BranchID = pgtype.UUID{Bytes: [16]byte(*b.sucursal), Valid: true}
		}
		filas = append(filas, fila)
	}
	sort.Slice(filas, func(i, j int) bool {
		if filas[i].SalioAt.Time.Equal(filas[j].SalioAt.Time) {
			return filas[i].Clave < filas[j].Clave
		}
		return filas[i].SalioAt.Time.Before(filas[j].SalioAt.Time)
	})
	if int(arg.Tope) < len(filas) {
		filas = filas[:arg.Tope]
	}
	return filas, nil
}

func (q *espejoFalso) ObtenerAjustes(context.Context) (sqlc.Setting, error) { return q.ajustes, nil }

func (q *espejoFalso) MarcarCatalogoTraido(context.Context) error {
	q.marcada++
	q.ajustes.CatalogoTraidoAt = pgtype.Timestamptz{Time: time.Now(), Valid: true}
	return nil
}

func (q *espejoFalso) GuardarProductoDelCatalogo(_ context.Context, arg sqlc.GuardarProductoDelCatalogoParams) (sqlc.GuardarProductoDelCatalogoRow, error) {
	clave := *arg.SucursalCodigo + "|" + *arg.Sku
	q.guardados[clave]++
	return sqlc.GuardarProductoDelCatalogoRow{ID: uuid.New(), Name: arg.Name, Sku: arg.Sku}, nil
}

func (q *espejoFalso) ListarSucursales(_ context.Context, persona pgtype.UUID) ([]sqlc.ListarSucursalesRow, error) {
	stg, hol := "STG", "HOL"
	ahora := pgtype.Timestamptz{Time: time.Now(), Valid: true}
	// EL DATO DE PRODUCCIÓN, calcado: Santiago tiene tasa (700 CUP/USD, del 09/09, que
	// Accesos da por NO fresca) y Holguín no tiene ninguna. Las dos cosas tienen que llegar
	// al aparato, y la segunda tan explícitamente como la primera.
	entrega := "entrega"
	fresca := false
	cup := 700.0
	todas := []sqlc.ListarSucursalesRow{
		{ID: sucStg, Name: "Santiago", ExternalID: &stg, UpdatedAt: ahora,
			CupRate: &cup, CupRateFuente: &entrega, CupRateFresca: &fresca,
			CupRateTraidoAt: pgtype.Timestamptz{
				Time: time.Date(2026, 9, 9, 22, 3, 4, 0, time.UTC), Valid: true}},
		{ID: sucHol, Name: "Holguín", ExternalID: &hol, UpdatedAt: ahora},
	}
	if !persona.Valid {
		return todas, nil
	}
	var salida []sqlc.ListarSucursalesRow
	for _, b := range todas {
		if [16]byte(b.ID) == persona.Bytes {
			salida = append(salida, b)
		}
	}
	return salida, nil
}

// ListarVehiculos y ListarRutas REPITEN SU ACOTACIÓN, que NO es la misma en las dos, y
// ahí está media prueba de este cambio: `ListarVehiculos` lleva `OR v.branch_id IS NULL`
// —un camión sin sucursal lo ven los ocho aparatos— y `ListarRutas` no lo lleva. Si el
// doble las acotara igual, una lápida acotada al revés pasaría inadvertida.
func (q *espejoFalso) ListarVehiculos(_ context.Context, sucursal pgtype.UUID) ([]sqlc.ListarVehiculosRow, error) {
	var salida []sqlc.ListarVehiculosRow
	for _, v := range q.vehiculosDelEspejo {
		if sucursal.Valid && v.BranchID.Valid && v.BranchID.Bytes != sucursal.Bytes {
			continue
		}
		salida = append(salida, v)
	}
	return salida, nil
}

func (q *espejoFalso) ListarRutas(_ context.Context, arg sqlc.ListarRutasParams) ([]sqlc.ListarRutasRow, error) {
	var salida []sqlc.ListarRutasRow
	for _, rt := range q.rutasDelEspejo {
		// Sin `OR r.branch_id IS NULL`, a propósito: una ruta sin sucursal NO la ve un
		// aparato acotado, y el `= NULL` del SQL tampoco es cierto nunca.
		if arg.Sucursal.Valid && (!rt.BranchID.Valid || rt.BranchID.Bytes != arg.Sucursal.Bytes) {
			continue
		}
		salida = append(salida, rt)
	}
	return salida, nil
}
func (q *espejoFalso) ListarProductos(_ context.Context, arg sqlc.ListarProductosParams) ([]sqlc.Product, error) {
	// La de la PANTALLA: por nombre y con su tope. La bajada del aparato ya no pasa por
	// aquí — va por `DiferenciasDeProductos`, que ordena por la marca.
	cuadran := append([]sqlc.Product(nil), q.catalogoDelEspejo...)
	sort.Slice(cuadran, func(i, j int) bool { return cuadran[i].Name < cuadran[j].Name })
	if int(arg.Limite) < len(cuadran) {
		cuadran = cuadran[:arg.Limite]
	}
	return cuadran, nil
}

func (q *espejoFalso) ListarClientes(_ context.Context, arg sqlc.ListarClientesParams) ([]sqlc.ListarClientesRow, error) {
	cuadran := append([]sqlc.ListarClientesRow(nil), q.padron...)
	sort.Slice(cuadran, func(i, j int) bool { return cuadran[i].Name < cuadran[j].Name })
	desde := int(arg.Desplazamiento)
	if desde >= len(cuadran) {
		return nil, nil
	}
	hasta := desde + int(arg.Limite)
	if hasta > len(cuadran) {
		hasta = len(cuadran)
	}
	return cuadran[desde:hasta], nil
}

// DiferenciasDeProductos y DiferenciasDeClientes REPITEN EL SQL DE LA BAJADA, y cada trozo
// que repiten es un fallo que se puede ver desde aquí:
//
//   - el ORDEN POR LA MARCA (y el id de desempate). Con un doble que devolviera la lista en
//     cualquier orden, «la marca de la última fila servida» sería una marca cualquiera y la
//     prueba del encadenado saldría verde con el fallo puesto.
//   - el CURSOR `(marca, id)`, que es lo único que sirve cuando miles de filas comparten la
//     misma marca — que es lo que hay en producción después del traspaso.
//   - el `desde` ESTRICTO y el `hasta` INCLUSIVO, para que dos ventanas seguidas ni se
//     pisen ni dejen hueco.
//   - el TOPE tal cual se pide: quien llama pide una fila de más para saber si queda algo,
//     y un doble que sirviera siempre la lista entera escondería justo eso.
func porLaMarca[T any](filas []T, marca func(T) time.Time, id func(T) uuid.UUID) {
	sort.Slice(filas, func(i, j int) bool {
		mi, mj := marca(filas[i]), marca(filas[j])
		if !mi.Equal(mj) {
			return mi.Before(mj)
		}
		return id(filas[i]).String() < id(filas[j]).String()
	})
}

// enLaVentana es el `desde` estricto / `hasta` inclusivo / cursor `(marca, id)` del SQL.
func enLaVentana(m time.Time, fila uuid.UUID, desde, hasta, curMarca pgtype.Timestamptz, curID pgtype.UUID) bool {
	if desde.Valid && !m.After(desde.Time) {
		return false
	}
	if hasta.Valid && m.After(hasta.Time) {
		return false
	}
	if curMarca.Valid {
		if m.Before(curMarca.Time) {
			return false
		}
		if m.Equal(curMarca.Time) && !(fila.String() > uuid.UUID(curID.Bytes).String()) {
			return false
		}
	}
	return true
}

func (q *espejoFalso) DiferenciasDeProductos(_ context.Context, arg sqlc.DiferenciasDeProductosParams) ([]sqlc.Product, error) {
	var cuadran []sqlc.Product
	for _, p := range q.catalogoDelEspejo {
		if arg.Sucursal != nil && (p.SucursalCodigo == nil || *p.SucursalCodigo != *arg.Sucursal) {
			continue
		}
		if !enLaVentana(p.UpdatedAt.Time, p.ID, arg.Desde, arg.Hasta, arg.CursorMarca, arg.CursorID) {
			continue
		}
		cuadran = append(cuadran, p)
	}
	porLaMarca(cuadran, func(p sqlc.Product) time.Time { return p.UpdatedAt.Time },
		func(p sqlc.Product) uuid.UUID { return p.ID })
	if int(arg.Tope) < len(cuadran) {
		cuadran = cuadran[:arg.Tope]
	}
	return cuadran, nil
}

func (q *espejoFalso) DiferenciasDeClientes(_ context.Context, arg sqlc.DiferenciasDeClientesParams) ([]sqlc.DiferenciasDeClientesRow, error) {
	var cuadran []sqlc.DiferenciasDeClientesRow
	for _, c := range q.padron {
		// El alcance deja pasar además a los MANUALES, que no tienen código de sucursal.
		if arg.SucursalDelAlcance != nil && c.SucursalCodigo != nil &&
			*c.SucursalCodigo != *arg.SucursalDelAlcance {
			continue
		}
		if !enLaVentana(c.SyncedAt.Time, c.ID, arg.Desde, arg.Hasta, arg.CursorMarca, arg.CursorID) {
			continue
		}
		cuadran = append(cuadran, sqlc.DiferenciasDeClientesRow{
			ID: c.ID, Source: c.Source, ExternalID: c.ExternalID, Name: c.Name,
			Phone: c.Phone, Address: c.Address, Municipio: c.Municipio, Zona: c.Zona,
			Lat: c.Lat, Lng: c.Lng, SucursalCodigo: c.SucursalCodigo, Codigo: c.Codigo,
			Vendedor: c.Vendedor, SyncedAt: c.SyncedAt,
		})
	}
	porLaMarca(cuadran, func(c sqlc.DiferenciasDeClientesRow) time.Time { return c.SyncedAt.Time },
		func(c sqlc.DiferenciasDeClientesRow) uuid.UUID { return c.ID })
	if int(arg.Tope) < len(cuadran) {
		cuadran = cuadran[:arg.Tope]
	}
	return cuadran, nil
}

// --------------------------------------------------------------------------- Ventra de mentira

type ventraFalsa struct {
	bases    map[string]string
	catalogo map[string][]FilaDeVentra
	fallo    error
	llamadas int
}

func (v *ventraFalsa) Bases(context.Context) (map[string]string, error) {
	if v.fallo != nil {
		return nil, v.fallo
	}
	return v.bases, nil
}

func (v *ventraFalsa) Catalogo(_ context.Context, base string) ([]FilaDeVentra, error) {
	v.llamadas++
	return v.catalogo[base], nil
}

// ventraDePrueba es el lector que el montador le pone al servidor. Vive aquí, en las
// pruebas, y no en el paquete: el lector de verdad ya es un campo de `Servidor`.
//
// SE PONE ANTES DE MONTAR, que es como lo llaman todas las pruebas de este fichero: el
// montador lo lee al construir el servidor. Al acabar cada prueba se restaura, así que una
// no le deja el lector puesto a la siguiente.
var ventraDePrueba LectorDeVentra

func conVentra(t *testing.T, v LectorDeVentra) {
	t.Helper()
	anterior := ventraDePrueba
	ventraDePrueba = v
	t.Cleanup(func() { ventraDePrueba = anterior })
}

// --------------------------------------------------------------------------- pruebas

// SIN LECTOR DE VENTRA, 502 Y NO 200 CON CEROS. Un catálogo que dice «he escrito 0
// productos» cuando en realidad no ha preguntado a nadie deja al logístico mirando
// precios de hace tres semanas sin un solo aviso.
func TestProductosSyncSinLectorDeVentraEs502(t *testing.T) {
	conVentra(t, nil)
	h := montarTab(t, nuevoEspejo())
	w := pedirTab(t, h, http.MethodPost, "/api/products/sync", tokenTab(t, ""), "")
	if w.Code != http.StatusBadGateway {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "No se pudo preguntar a Ventra") {
		t.Fatalf("mensaje %q", w.Body.String())
	}
}

// El upsert es por (sucursal, sku): pasar el mismo lote dos veces NO duplica nada. Es la
// condición para poder reintentar cuando la VPN se corta a la mitad.
func TestProductosSyncEsReaplicable(t *testing.T) {
	v := &ventraFalsa{
		bases: map[string]string{"STG": "ventra_stg", "HOL": "ventra_hol"},
		catalogo: map[string][]FilaDeVentra{
			"ventra_stg": {
				{Sku: "MALTA-1", Nombre: "Malta 355 ml", Activo: true},
				{Sku: "", Nombre: "Sin sku", Activo: true},        // se salta: no hay por dónde reconocerla
				{Sku: "RETIRADO", Nombre: "Viejo", Activo: false}, // se salta: retirado en Ventra
			},
			"ventra_hol": {{Sku: "AGUA-5", Nombre: "Agua 5 L", Activo: true}},
		},
	}
	conVentra(t, v)
	q := nuevoEspejo()
	h := montarTab(t, q)
	jwt := tokenTab(t, "")

	for vuelta := 1; vuelta <= 2; vuelta++ {
		// `forzar` porque la segunda vuelta cae dentro del intervalo de doce horas.
		w := pedirTab(t, h, http.MethodPost, "/api/products/sync?forzar=1", jwt, "")
		if w.Code != http.StatusOK {
			t.Fatalf("vuelta %d: código %d (%s)", vuelta, w.Code, w.Body.String())
		}
		m := leerTab(t, w)
		if n, _ := m["escritos"].(float64); n != 2 {
			t.Fatalf("vuelta %d: escritos %v, cuerpo %s", vuelta, m["escritos"], w.Body.String())
		}
	}
	// Dos vueltas, dos escrituras por producto, PERO sólo dos productos: el upsert los
	// pisa, no los duplica.
	if len(q.guardados) != 2 {
		t.Fatalf("el catálogo se duplicó: %+v", q.guardados)
	}
	if q.guardados["STG|MALTA-1"] != 2 || q.guardados["HOL|AGUA-5"] != 2 {
		t.Fatalf("no se reescribieron los dos: %+v", q.guardados)
	}
}

// Si TODAS las sucursales fallan, la hora NO se marca: hay que poder reintentar antes de
// las doce horas en vez de quedarse medio día con el catálogo a medias.
func TestSiNingunaSucursalCuadraNoSeMarcaLaHora(t *testing.T) {
	conVentra(t, &ventraFalsa{bases: map[string]string{}})
	q := nuevoEspejo()
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/products/sync", tokenTab(t, ""), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	if n, _ := m["conError"].(float64); n != 2 {
		t.Fatalf("conError %v: %s", m["conError"], w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "sin base de Ventra que le cuadre") {
		t.Fatalf("falta el literal del contrato: %s", w.Body.String())
	}
	if q.marcada != 0 {
		t.Fatal("se marcó la hora sin haber escrito nada")
	}
}

// El intervalo: sin forzar, no se vuelve a preguntar antes de las doce horas.
func TestProductosSyncRespetaElIntervalo(t *testing.T) {
	v := &ventraFalsa{bases: map[string]string{"STG": "ventra_stg"}}
	conVentra(t, v)
	q := nuevoEspejo()
	q.ajustes.CatalogoTraidoAt = pgtype.Timestamptz{Time: time.Now().Add(-time.Hour), Valid: true}
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/products/sync", tokenTab(t, ""), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d", w.Code)
	}
	if saltado, _ := leerTab(t, w)["saltado"].(bool); !saltado {
		t.Fatalf("no se saltó: %s", w.Body.String())
	}
	if v.llamadas != 0 {
		t.Fatal("preguntó a Ventra igual")
	}
}

// La clave de servicio abre la puerta sin sesión: la ruta la dispara un temporizador.
func TestProductosSyncEntraConClaveDeServicio(t *testing.T) {
	t.Setenv("SERVICE_API_KEY", "la-clave-del-espejo")
	conVentra(t, &ventraFalsa{bases: map[string]string{}})
	h := montarTab(t, nuevoEspejo())

	r := httptest.NewRequest(http.MethodPost, "/api/products/sync", nil)
	r.Header.Set("X-Api-Key", "la-clave-del-espejo")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}

	// Y una clave equivocada NO entra, ni siquiera para mirar.
	r = httptest.NewRequest(http.MethodPost, "/api/products/sync", nil)
	r.Header.Set("X-Api-Key", "la-que-no-es")
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("una clave mala entró: %d", w.Code)
	}
}

// Sin la clave de servicio no se puede hablar con PEDIDO, y eso se dice ANTES de bajar
// cinco mil pedidos, no después.
func TestRecomputeSinClaveDeServicioEs500(t *testing.T) {
	t.Setenv("SERVICE_API_KEY", "")
	h := montarTab(t, nuevoEspejo())
	w := pedirTab(t, h, http.MethodPost, "/api/admin/recompute", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusInternalServerError {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if leerTab(t, w)["error"] != "SERVICE_API_KEY no configurada en el servidor" {
		t.Fatalf("mensaje %q", w.Body.String())
	}
}

func TestRecomputeDevuelve502ConLoQueDijoPedido(t *testing.T) {
	pedido := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte("la base de PEDIDO no contesta"))
	}))
	defer pedido.Close()

	t.Setenv("SERVICE_API_KEY", "clave")
	t.Setenv("PEDIDO_API_URL", pedido.URL)
	h := montarTab(t, nuevoEspejo())

	w := pedirTab(t, h, http.MethodPost, "/api/admin/recompute", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusBadGateway {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	// El cuerpo de PEDIDO viaja dentro: sin él, «502» no dice nada que se pueda arreglar.
	if !strings.Contains(w.Body.String(), "PEDIDO 500") ||
		!strings.Contains(w.Body.String(), "la base de PEDIDO no contesta") {
		t.Fatalf("mensaje %q", w.Body.String())
	}
}

// Que no haya nada que recostear NO es un fallo, y la pantalla necesita poder decirlo con
// esas palabras.
func TestRecomputeSinPedidosEs200ConMensaje(t *testing.T) {
	pedido := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Api-Key") == "" {
			t.Error("la petición a PEDIDO fue sin clave de servicio")
		}
		if !strings.Contains(r.URL.RawQuery, "sucursalCodigo=STG") {
			t.Errorf("el alcance no viajó como código: %s", r.URL.RawQuery)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"orders": []any{}})
	}))
	defer pedido.Close()

	t.Setenv("SERVICE_API_KEY", "clave")
	t.Setenv("PEDIDO_API_URL", pedido.URL)
	h := montarTab(t, nuevoEspejo())

	w := pedirTab(t, h, http.MethodPost, "/api/admin/recompute?dias=900",
		tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	// 900 días se acota a 120: con «todos los días» esto se convierte en una consulta de
	// 3.500 pedidos por la conexión de Cuba.
	if n, _ := m["dias"].(float64); n != 120 {
		t.Fatalf("los días no se acotaron: %v", m["dias"])
	}
	if !strings.Contains(m["message"].(string), "No hay pedidos con geolocalización") {
		t.Fatalf("mensaje %q", m["message"])
	}
}

// LA BAJADA NO PUEDE MENTIR CON UN CONJUNTO VACÍO.
//
// `warehouses` sigue sin poder servirse: los almacenes viven en Accesos, que no da marca de
// cambio ni dice qué borró. Mandarlo como `{"puestos":[],"quitados":[]}` le diría al
// aparato «no ha cambiado ningún almacén», que es lo contrario de la verdad, y desde el
// almacén se mide lo que se le cobra al cliente por el domicilio.
//
// `orders` YA NO ESTÁ en esa lista: se sirve de verdad. Que no vuelva a entrar.
func TestLaBajadaNombraLoQueNoSabeServirEnVezDeMandarloVacio(t *testing.T) {
	h := montarTab(t, nuevoEspejo())
	w := pedirTab(t, h, http.MethodGet, "/api/sync/cambios", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)

	cambios := m["cambios"].(map[string]any)
	if _, hay := cambios["warehouses"]; hay {
		t.Fatal("«warehouses» sale como conjunto vacío: eso le dice al aparato que no cambió nada")
	}
	if _, hay := cambios["orders"]; !hay {
		t.Fatalf("«orders» tiene que venir servido: %s", w.Body.String())
	}

	faltan := map[string]bool{}
	for _, f := range m["faltan"].([]any) {
		faltan[f.(string)] = true
	}
	if !faltan["warehouses"] {
		t.Fatalf("«warehouses» no está nombrado en «faltan»: %s", w.Body.String())
	}
	if faltan["orders"] {
		t.Fatal("«orders» sigue declarado como que falta, y ya se sirve")
	}
	if m["aviso"] == nil || m["aviso"].(string) == "" {
		t.Fatal("falta el aviso que explica por qué")
	}
}

// `hasta` LO PONE EL SERVIDOR, y la primera bajada es completa.
func TestLaBajadaTraeLaMarcaDelServidor(t *testing.T) {
	h := montarTab(t, nuevoEspejo())
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodGet, "/api/sync/cambios", jwt, "")
	m := leerTab(t, w)
	if completa, _ := m["completa"].(bool); !completa {
		t.Fatal("sin «desde», la bajada tiene que ser la carga inicial")
	}
	hasta, err := time.Parse(time.RFC3339, m["hasta"].(string))
	if err != nil || time.Since(hasta) > time.Minute {
		t.Fatalf("«hasta» no es una marca del servidor: %v", m["hasta"])
	}

	// Con `desde` en el futuro no cambió nada, pero las colecciones siguen ahí: ausente
	// y vacío significan cosas distintas y no se pueden confundir.
	futuro := time.Now().Add(time.Hour).UTC().Format(time.RFC3339)
	w = pedirTab(t, h, http.MethodGet, "/api/sync/cambios?desde="+futuro, jwt, "")
	m = leerTab(t, w)
	if completa, _ := m["completa"].(bool); completa {
		t.Fatal("con «desde» ya no es carga inicial")
	}
	sucursales := m["cambios"].(map[string]any)["branches"].(map[string]any)
	if len(sucursales["puestos"].([]any)) != 0 {
		t.Fatalf("con «desde» en el futuro no puede venir nada: %s", w.Body.String())
	}

	// Y un «desde» que no es una fecha es un 400 que lo dice, no un silencio.
	w = pedirTab(t, h, http.MethodGet, "/api/sync/cambios?desde=ayer", jwt, "")
	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
}

// El tablero de la bajada es POR SUCURSAL: al Super Admin sin elegir no se le mandan las
// ocho mezcladas, se le dice que falta elegir.
func TestLaBajadaDelTableroPideSucursal(t *testing.T) {
	h := montarTab(t, nuevoEspejo())

	w := pedirTab(t, h, http.MethodGet, "/api/sync/cambios", tokenTab(t, ""), "")
	m := leerTab(t, w)
	if _, hay := m["cambios"].(map[string]any)["boardColumns"]; hay {
		t.Fatal("se mandó el tablero sin saber de qué sucursal")
	}

	w = pedirTab(t, h, http.MethodGet, "/api/sync/cambios?sucursal="+sucStg.String(), tokenTab(t, ""), "")
	m = leerTab(t, w)
	cols, hay := m["cambios"].(map[string]any)["boardColumns"]
	if !hay {
		t.Fatalf("con sucursal tenía que venir el tablero: %s", w.Body.String())
	}
	if len(cols.(map[string]any)["puestos"].([]any)) != 3 {
		t.Fatalf("columnas: %s", w.Body.String())
	}
}

// ---------------------------------------------------------------------------
// LOS PEDIDOS DE LA BAJADA — lo que hace posible el día sin conexión
// ---------------------------------------------------------------------------

var (
	pedAntiguo   = uuid.MustParse("5d000000-0000-0000-0000-000000000001")
	pedTocado    = uuid.MustParse("5d000000-0000-0000-0000-000000000002")
	pedArchivado = uuid.MustParse("5d000000-0000-0000-0000-000000000003")
	pedRenglon   = uuid.MustParse("5d000000-0000-0000-0000-000000000004")
	pedMudado    = uuid.MustParse("5d000000-0000-0000-0000-000000000005")
	pedDeHolguin = uuid.MustParse("5d000000-0000-0000-0000-000000000006")
)

// conPedidos deja el espejo con cuatro pedidos de Santiago repartidos a los dos lados de
// una marca, más uno de Holguín para que se vea que el alcance sigue puesto.
//
// Devuelve la marca: lo de antes de ella no tiene que salir, lo de después sí.
func conPedidos(q *espejoFalso) time.Time {
	ahora := time.Now().UTC()
	marca := ahora.Add(-12 * time.Hour)
	antes := ahora.Add(-24 * time.Hour)
	despues := ahora.Add(-1 * time.Hour)

	q.sync = []pedidoSync{
		// Tocado ANTES de la marca: no cambió nada de él desde que el aparato bajó.
		{id: pedAntiguo, sucursal: sucStg, nombre: "Ana la de siempre", marca: antes,
			renglones: []renglonSync{{linea: 1, desc: "malta", marca: antes}}},
		// Tocado DESPUÉS: es lo que el aparato tiene que llevarse.
		{id: pedTocado, sucursal: sucStg, nombre: "Beto", marca: despues,
			renglones: []renglonSync{{linea: 1, desc: "cerveza", marca: despues}}},
		// Archivado en PEDIDO después de la marca: el aparato tiene que BORRARLO.
		{id: pedArchivado, sucursal: sucStg, nombre: "Carlos", marca: despues, archivado: true},
		// EL PEDIDO NO SE TOCÓ; le cambió un RENGLÓN. Tiene que salir igual, o el aparato
		// se queda con la lista de mercancía vieja.
		{id: pedRenglon, sucursal: sucStg, nombre: "Delia", marca: antes,
			renglones: []renglonSync{
				{linea: 1, desc: "refresco", marca: antes},
				{linea: 2, desc: "ron - LÍNEA NUEVA", marca: despues},
			}},
		{id: pedDeHolguin, sucursal: sucHol, nombre: "De Holguín", marca: despues},
	}
	// Uno que se MUDÓ de Santiago a Holguín, y uno BORRADO. Los dos tienen que
	// desaparecer del aparato de Santiago aunque su fila no diga nada (o ya no exista).
	q.salidas = []salidaSync{
		{pedido: pedMudado, sucursal: sucStg, motivo: sqlc.SalidaDePedidoMovido, salioAt: despues},
	}
	return marca
}

// conjuntoDe saca `cambios.<nombre>` de la respuesta.
func conjuntoDe(t *testing.T, m map[string]any, nombre string) (map[string]bool, map[string]bool, []any) {
	t.Helper()
	c, hay := m["cambios"].(map[string]any)[nombre]
	if !hay {
		t.Fatalf("no vino la colección %q", nombre)
	}
	conj := c.(map[string]any)
	puestos := map[string]bool{}
	crudos := conj["puestos"].([]any)
	for _, p := range crudos {
		puestos[p.(map[string]any)["id"].(string)] = true
	}
	quitados := map[string]bool{}
	for _, q := range conj["quitados"].([]any) {
		quitados[q.(string)] = true
	}
	return puestos, quitados, crudos
}

// LA PRUEBA QUE CIERRA EL AGUJERO: lo tocado después de la marca sale, lo anterior no, y
// lo archivado sale en `quitados` — no en `puestos` con una bandera que alguien tiene que
// acordarse de mirar.
func TestLaBajadaDeDiferenciasTraeLoTocadoYQuitaLoArchivado(t *testing.T) {
	q := nuevoEspejo()
	marca := conPedidos(q)
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodGet,
		"/api/sync/cambios?desde="+marca.Format(time.RFC3339), tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	puestos, quitados, _ := conjuntoDe(t, leerTab(t, w), "orders")

	if !puestos[pedTocado.String()] {
		t.Fatal("un pedido tocado después de la marca no salió en las diferencias")
	}
	if puestos[pedAntiguo.String()] || quitados[pedAntiguo.String()] {
		t.Fatal("un pedido anterior a la marca salió: la bajada por diferencias no diferencia nada")
	}
	if puestos[pedArchivado.String()] {
		t.Fatal("un pedido archivado salió en «puestos»: seguiría en el tablero del aparato")
	}
	if !quitados[pedArchivado.String()] {
		t.Fatal("un pedido archivado no salió en «quitados»: la lista local sólo crece")
	}
	// Y el alcance sigue puesto: lo de Holguín no se baja a un aparato de Santiago.
	if puestos[pedDeHolguin.String()] || quitados[pedDeHolguin.String()] {
		t.Fatal("se coló un pedido de otra sucursal")
	}
}

// SI CAMBIA UN RENGLÓN, EL PEDIDO SALE. El pedido no se tocó —su `updated_at` es de ayer—
// pero una de sus líneas sí, y lo que sube al camión son las líneas. Y tiene que venir con
// los renglones dentro: mandar el aviso sin la mercancía nueva no arregla nada.
func TestUnRenglonTocadoSacaASuPedidoConSuMercancia(t *testing.T) {
	q := nuevoEspejo()
	marca := conPedidos(q)
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodGet,
		"/api/sync/cambios?desde="+marca.Format(time.RFC3339), tokenTab(t, sucStg.String()), "")
	puestos, _, crudos := conjuntoDe(t, leerTab(t, w), "orders")

	if !puestos[pedRenglon.String()] {
		t.Fatal("cambió un renglón y el pedido no salió: el aparato se queda con la lista de mercancía vieja")
	}
	for _, p := range crudos {
		fila := p.(map[string]any)
		if fila["id"] != pedRenglon.String() {
			continue
		}
		items := fila["items"].([]any)
		if len(items) != 2 {
			t.Fatalf("el pedido salió sin sus renglones: %v", items)
		}
		// La marca que se devuelve es la del RENGLÓN, que es la más nueva. Con la del
		// pedido, el aparato volvería a pedirlo en cada bajada para siempre.
		devuelta, err := time.Parse(time.RFC3339, fila["updatedAt"].(string))
		if err != nil {
			t.Fatalf("«updatedAt» ilegible: %v", fila["updatedAt"])
		}
		if !devuelta.After(marca) {
			t.Fatalf("la marca devuelta es la del pedido y no la del renglón: %v", devuelta)
		}
		return
	}
	t.Fatal("no se encontró el pedido en «puestos»")
}

// `quitados` NO ES SÓLO LO BORRADO. Un pedido que se muda de sucursal deja de salir en las
// consultas de la vieja, así que sin las lápidas se quedaría en ese aparato para siempre —
// y seguiría apareciendo en un tablero que ya no es el suyo.
func TestUnPedidoQueSaleDelAlcanceDeLaSucursalSeQuita(t *testing.T) {
	q := nuevoEspejo()
	marca := conPedidos(q)
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodGet,
		"/api/sync/cambios?desde="+marca.Format(time.RFC3339), tokenTab(t, sucStg.String()), "")
	_, quitados, _ := conjuntoDe(t, leerTab(t, w), "orders")
	if !quitados[pedMudado.String()] {
		t.Fatalf("el pedido que se mudó de sucursal no salió en «quitados»: %s", w.Body.String())
	}
}

// LA CARGA INICIAL NO LLEVA ARCHIVADOS NI QUITADOS. El aparato empieza vacío: no hay nada
// que borrarle, y bajarle el histórico archivado de ocho meses le llena el tope con lo que
// no va a repartir y deja fuera lo del día.
func TestLaCargaInicialNoTraeArchivadosNiQuitados(t *testing.T) {
	q := nuevoEspejo()
	conPedidos(q)
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodGet, "/api/sync/cambios", tokenTab(t, sucStg.String()), "")
	puestos, quitados, _ := conjuntoDe(t, leerTab(t, w), "orders")

	if puestos[pedArchivado.String()] {
		t.Fatal("la carga inicial trajo un pedido archivado")
	}
	if len(quitados) != 0 {
		t.Fatalf("la carga inicial trae «quitados» y el aparato no tiene nada: %v", quitados)
	}
	if !puestos[pedAntiguo.String()] || !puestos[pedTocado.String()] {
		t.Fatalf("la carga inicial tiene que traerlo todo: %s", w.Body.String())
	}
}

// EL TOPE NO PUEDE PERDER PEDIDOS.
//
// Con `truncado`, la marca que se devuelve deja de ser el reloj y pasa a ser la de la
// última fila servida. Si se devolviera el reloj, el aparato pediría la próxima vez «a
// partir de ahora» y lo que no cupo no lo pediría nadie nunca más: sería trabajo perdido
// sin un solo error.
func TestElTopeTruncaSinPerderNiUnPedido(t *testing.T) {
	q := nuevoEspejo()
	marca := conPedidos(q)
	// Marcas distintas y separadas, para que el corte pueda caer entre dos.
	ahora := time.Now().UTC()
	q.salidas = nil
	q.sync = []pedidoSync{
		{id: pedAntiguo, sucursal: sucStg, nombre: "primero", marca: ahora.Add(-4 * time.Hour)},
		{id: pedTocado, sucursal: sucStg, nombre: "segundo", marca: ahora.Add(-3 * time.Hour)},
		{id: pedRenglon, sucursal: sucStg, nombre: "tercero", marca: ahora.Add(-2 * time.Hour)},
	}
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodGet,
		"/api/sync/cambios?tope=2&desde="+marca.Format(time.RFC3339), tokenTab(t, sucStg.String()), "")
	m := leerTab(t, w)
	if truncado, _ := m["truncado"].(bool); !truncado {
		t.Fatalf("no cupo todo y no se dijo: %s", w.Body.String())
	}
	puestos, _, _ := conjuntoDe(t, m, "orders")
	if len(puestos) != 2 {
		t.Fatalf("la tanda no respetó el tope: %v", puestos)
	}
	hasta := m["hasta"].(string)
	if time.Since(mustHora(t, hasta)) < time.Hour {
		t.Fatalf("con «truncado» la marca tiene que ser la de la última fila servida, no el reloj: %s", hasta)
	}

	// Segunda vuelta con la marca devuelta: tiene que traer lo que faltaba, sin repetir.
	w = pedirTab(t, h, http.MethodGet,
		"/api/sync/cambios?tope=2&desde="+hasta, tokenTab(t, sucStg.String()), "")
	m = leerTab(t, w)
	puestos2, _, _ := conjuntoDe(t, m, "orders")
	if !puestos2[pedRenglon.String()] {
		t.Fatalf("el pedido que no cupo se perdió para siempre: %s", w.Body.String())
	}
	if puestos2[pedAntiguo.String()] || puestos2[pedTocado.String()] {
		t.Fatalf("la segunda tanda repitió lo ya servido: %s", w.Body.String())
	}
	if truncado, _ := m["truncado"].(bool); truncado {
		t.Fatal("ya cupo todo y sigue diciendo «truncado»")
	}
}

func mustHora(t *testing.T, s string) time.Time {
	t.Helper()
	v, err := time.Parse(time.RFC3339, s)
	if err != nil {
		t.Fatalf("hora ilegible %q: %v", s, err)
	}
	return v
}

// EL PADRÓN ENTERO, TANDA A TANDA — el fallo de los 2.000 clientes.
//
// El 15/09/2026 se leyó la base del aparato después de la bajada contra producción:
// `clientes = 2000` redondos, y con esa cuenta (Super Admin) son 8.034. El catálogo y el
// padrón se servían siempre con `LIMIT tope OFFSET 0` ordenados por nombre, y se marcaba
// `truncado` al llegar al tope — pero no había por dónde seguir: la tanda siguiente pedía
// exactamente lo mismo. La bajada se dio por buena con un cuarto de los clientes y **nadie
// se enteró**, que es el patrón que más daño hace en este proyecto.
//
// Esta prueba falla si el encadenado deja de avanzar: si `continuar` desaparece, si no se
// lee, o si el desplazamiento vuelve a cero.
func TestElPadronSeSirveEnteroEnTandas(t *testing.T) {
	q := nuevoEspejo()
	stg := "STG"
	const total = 7
	for i := 0; i < total; i++ {
		q.padron = append(q.padron, sqlc.ListarClientesRow{
			ID:             uuid.New(),
			Name:           fmt.Sprintf("Cliente %02d", i),
			Lat:            20.0,
			Lng:            -75.0,
			SucursalCodigo: &stg,
		})
	}
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	vistos := map[string]bool{}
	continuar := ""
	tandas := 0
	for {
		tandas++
		if tandas > 10 {
			t.Fatal("la cadena de tandas no termina")
		}
		url := "/api/sync/cambios?tope=3"
		if continuar != "" {
			url += "&continuar=" + continuar
		}
		w := pedirTab(t, h, http.MethodGet, url, jwt, "")
		m := leerTab(t, w)

		puestos, _, _ := conjuntoDe(t, m, "customers")
		for id := range puestos {
			if vistos[id] {
				t.Fatalf("tanda %d: repitió un cliente ya servido (%s)", tandas, id)
			}
			vistos[id] = true
		}

		truncado, _ := m["truncado"].(bool)
		if !truncado {
			break
		}
		siguiente, _ := m["continuar"].(string)
		if siguiente == "" {
			t.Fatalf("tanda %d dijo «truncado» y no dijo por dónde seguir: %s",
				tandas, w.Body.String())
		}
		if siguiente == continuar {
			t.Fatalf("tanda %d: el cursor no avanza, la siguiente traería lo mismo", tandas)
		}
		continuar = siguiente
	}

	if len(vistos) != total {
		t.Fatalf("se sirvieron %d clientes de %d: %v", len(vistos), total, vistos)
	}
	if tandas != 3 {
		t.Fatalf("7 clientes de 3 en 3 son 3 tandas, no %d", tandas)
	}
}

// EL CURSOR MANDA SOBRE EL `desde` DE LA PETICIÓN, y sin eso la segunda tanda no emite nada.
//
// El aparato relee su marca de frescura antes de cada vuelta, así que el `desde` que manda
// AVANZA entre tandas. Los cuatro clientes de aquí son de ayer: contra el `desde` de la
// segunda petición no pasaría ni uno. Lo que los salva es que, habiendo cursor, el `desde`
// no se mira — el cursor ya dice por dónde iba la cadena, y viene de una fila servida de
// verdad (`alcance.TandaDelPadron.desdeDe`).
//
// Antes esto se resolvía guardando el `desde` original DENTRO del cursor. Se quitó al pasar
// a cursor `(marca, id)`: dos cotas para lo mismo es una de más, y la que sobraba era la
// que dejó 2.000 clientes de 8.103 el 15/09/2026.
func TestElCursorMandaSobreElDesdeDeLaPeticion(t *testing.T) {
	q := nuevoEspejo()
	stg := "STG"
	ayer := time.Now().UTC().Add(-24 * time.Hour)
	for i := 0; i < 4; i++ {
		q.padron = append(q.padron, sqlc.ListarClientesRow{
			ID:             uuid.New(),
			Name:           fmt.Sprintf("Cliente %02d", i),
			Lat:            20.0,
			Lng:            -75.0,
			SucursalCodigo: &stg,
			// Tocados AYER: con el `desde` de la primera tanda entran; con uno posterior,
			// no.
			SyncedAt: pgtype.Timestamptz{Time: ayer, Valid: true},
		})
	}
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	desde := ayer.Add(-time.Hour).Format(time.RFC3339)
	w := pedirTab(t, h, http.MethodGet, "/api/sync/cambios?tope=2&desde="+desde, jwt, "")
	m := leerTab(t, w)
	primera, _, _ := conjuntoDe(t, m, "customers")
	if len(primera) != 2 {
		t.Fatalf("la primera tanda tenía que traer 2: %s", w.Body.String())
	}
	continuar, _ := m["continuar"].(string)
	if continuar == "" {
		t.Fatalf("sin cursor no hay segunda tanda: %s", w.Body.String())
	}

	// La segunda tanda va con el `hasta` que devolvió la primera —que es lo que hace el
	// aparato— MÁS el cursor. Los clientes son de ayer, así que contra ese `desde` no
	// pasarían: el cursor es lo único que los salva.
	hasta := m["hasta"].(string)
	w = pedirTab(t, h, http.MethodGet,
		"/api/sync/cambios?tope=2&desde="+hasta+"&continuar="+continuar, jwt, "")
	m = leerTab(t, w)
	segunda, _, _ := conjuntoDe(t, m, "customers")
	if len(segunda) != 2 {
		t.Fatalf("los otros dos clientes se perdieron para siempre: %s", w.Body.String())
	}
	for id := range segunda {
		if primera[id] {
			t.Fatalf("la segunda tanda repitió lo ya servido: %s", id)
		}
	}
}

// LA TASA BAJA CON LA SUCURSAL, Y LA QUE NO TIENE BAJA DICIÉNDOLO.
//
// Es lo que hace posible que el aparato pinte los importes en CUP sin conexión. Antes no
// bajaba por ningún lado —la barra leía una tabla local `currencies` que no llenaba
// nadie— y el selector de moneda se quedaba en ámbar para siempre, en las ocho
// sucursales, tuvieran tasa o no.
//
// Las cuatro columnas van DENTRO de la sucursal a propósito: la tasa es suya. En
// `settings`, que es global, una sola tasa serviría a las ocho y es exactamente cómo
// Granma acabó enseñando los 685 de La Habana.
func TestLaBajadaTraeLaTasaDeCadaSucursal(t *testing.T) {
	h := montarTab(t, nuevoEspejo())
	// Sin sucursal en el token: el Super Admin se lleva las dos, la que tiene tasa y la
	// que no.
	w := pedirTab(t, h, http.MethodGet, "/api/sync/cambios", tokenTab(t, ""), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)

	porNombre := map[string]map[string]any{}
	for _, b := range m["cambios"].(map[string]any)["branches"].(map[string]any)["puestos"].([]any) {
		fila := b.(map[string]any)
		porNombre[fila["name"].(string)] = fila
	}

	santiago, hay := porNombre["Santiago"]
	if !hay {
		t.Fatalf("no vino Santiago: %s", w.Body.String())
	}
	if v, _ := santiago["cupRate"].(float64); v != 700 {
		t.Errorf("cupRate de Santiago = %v, se esperaba 700", santiago["cupRate"])
	}
	// LA MARCA DE CUÁNDO, que es lo único que demuestra que la tasa existe: el esquema
	// viejo traía 320 por defecto, así que el número por sí solo no demuestra nada.
	if v, _ := santiago["cupRateTraidoAt"].(string); !strings.HasPrefix(v, "2026-09-09") {
		t.Errorf("cupRateTraidoAt de Santiago = %v, se esperaba la del 09/09", santiago["cupRateTraidoAt"])
	}
	// `fresca` la decide ACCESOS y se copia tal cual: aquí no se calcula ninguna regla de
	// 24 h. Hoy las tasas que hay son del 09/09, así que el aviso tiene que salir.
	if v, _ := santiago["cupRateFresca"].(bool); v {
		t.Error("Accesos dijo que la tasa no es fresca y llegó como fresca")
	}
	if v, _ := santiago["cupRateFuente"].(string); v != "entrega" {
		t.Errorf("cupRateFuente = %v, se esperaba «entrega»", santiago["cupRateFuente"])
	}

	holguin, hay := porNombre["Holguín"]
	if !hay {
		t.Fatalf("no vino Holguín: %s", w.Body.String())
	}
	// LA QUE NO TIENE LLEGA CON NULL Y CON LA CLAVE PUESTA. Ausente y null significan
	// cosas distintas: con la clave presente el aparato sabe que se le preguntó y que no
	// hay; sin ella no podría distinguirlo de una versión vieja del servidor.
	for _, campo := range []string{"cupRate", "cupRateFuente", "cupRateTraidoAt", "cupRateFresca"} {
		valor, presente := holguin[campo]
		if !presente {
			t.Errorf("a Holguín le falta la clave %q: ausente y null no significan lo mismo", campo)
		}
		if valor != nil {
			t.Errorf("Holguín no tiene tasa y %q vino con %v: se le metió la de otra sucursal", campo, valor)
		}
	}
}

// ABRIR LA APLICACIÓN CON TODO AL DÍA CUESTA UNA IDA Y VUELTA, NO CINCO.
//
// Jose, 16/09/2026, mirando el teléfono arrancar: «cada ves q inicie la aplicacion no me
// traigas todo es comprobar no traer todo ok y ver si esta todo, para eso es el sync».
//
// Lo que veía era «Trayendo datos… Clientes…» varios segundos en CADA arranque, con el
// padrón ya bajado y sin un solo cambio. El motivo: el padrón y el catálogo se leían
// enteros de la base —`LIMIT/OFFSET` sin más— y el `desde` se aplicaba después, en Go, al
// recorrer las filas. Así la tanda llega al tope igual, se marca `truncado` igual, y el
// aparato encadena las cinco vueltas que hacen falta para recorrer 8.103 clientes… y no
// aplica ni una fila. Cinco peticiones y cinco barridos de tabla para no hacer nada, cada
// vez, con la red de Cuba por delante.
//
// La prueba es sobre el NÚMERO DE TANDAS porque es lo único que se nota desde fuera: las
// filas servidas ya eran cero antes del arreglo. Rompe si el filtro se sale del SQL.
func TestUnArranqueSinCambiosNoEncadenaTandas(t *testing.T) {
	q := nuevoEspejo()
	stg := "STG"
	// Bajado AYER y sin tocar desde entonces: es el aparato de quien abre la aplicación
	// por la mañana con el día de ayer dentro.
	ayer := time.Now().UTC().Add(-24 * time.Hour)
	for i := 0; i < 7; i++ {
		q.padron = append(q.padron, sqlc.ListarClientesRow{
			ID:             uuid.New(),
			Name:           fmt.Sprintf("Cliente %02d", i),
			Lat:            20.0,
			Lng:            -75.0,
			SucursalCodigo: &stg,
			SyncedAt:       pgtype.Timestamptz{Time: ayer, Valid: true},
		})
		q.catalogoDelEspejo = append(q.catalogoDelEspejo, sqlc.Product{
			ID:             uuid.New(),
			Name:           fmt.Sprintf("Producto %02d", i),
			SucursalCodigo: &stg,
			UpdatedAt:      pgtype.Timestamptz{Time: ayer, Valid: true},
		})
	}
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	// El aparato pregunta desde DESPUÉS de lo último que se trajo. No ha cambiado nada.
	desde := time.Now().UTC().Add(-time.Hour).Format(time.RFC3339)

	tandas := 0
	continuar := ""
	for {
		tandas++
		if tandas > 10 {
			t.Fatal("la cadena de tandas no termina")
		}
		url := "/api/sync/cambios?tope=3&desde=" + desde
		if continuar != "" {
			url += "&continuar=" + continuar
		}
		w := pedirTab(t, h, http.MethodGet, url, jwt, "")
		m := leerTab(t, w)

		clientes, _, _ := conjuntoDe(t, m, "customers")
		productos, _, _ := conjuntoDe(t, m, "products")
		if len(clientes) != 0 || len(productos) != 0 {
			t.Fatalf("tanda %d: nada cambió y sirvió %d clientes y %d productos",
				tandas, len(clientes), len(productos))
		}
		if truncado, _ := m["truncado"].(bool); !truncado {
			break
		}
		continuar, _ = m["continuar"].(string)
	}

	if tandas != 1 {
		t.Fatalf("abrir la aplicación con todo al día costó %d idas y vueltas: tiene que "+
			"costar UNA. El filtro por marca se salió del SQL y el padrón se está "+
			"recorriendo entero otra vez", tandas)
	}
}

// Y LO QUE SÍ CAMBIÓ SIGUE BAJANDO ENTERO, en tandas, sin repetir ni perder.
//
// Es la otra mitad y hace falta las dos: un filtro que se pase de listo —por ejemplo con
// `>=` mal puesto, o dejando fuera las filas sin marca— apagaría «Trayendo datos…» y
// dejaría al aparato sin los clientes nuevos, que es mucho peor que la espera.
func TestLoQueCambioBajaEnteroAunqueElFiltroVayaEnElSQL(t *testing.T) {
	q := nuevoEspejo()
	stg := "STG"
	ayer := time.Now().UTC().Add(-24 * time.Hour)
	hace10m := time.Now().UTC().Add(-10 * time.Minute)
	// Cuatro viejos, cuatro tocados hace diez minutos y uno SIN MARCA, que cuenta como
	// cambiado: no se puede fechar, y dejarlo fuera sería no mandarlo nunca.
	for i := 0; i < 4; i++ {
		q.padron = append(q.padron, sqlc.ListarClientesRow{
			ID: uuid.New(), Name: fmt.Sprintf("Viejo %02d", i),
			Lat: 20.0, Lng: -75.0, SucursalCodigo: &stg,
			SyncedAt: pgtype.Timestamptz{Time: ayer, Valid: true},
		})
	}
	nuevos := map[string]bool{}
	for i := 0; i < 4; i++ {
		id := uuid.New()
		nuevos[id.String()] = true
		q.padron = append(q.padron, sqlc.ListarClientesRow{
			ID: id, Name: fmt.Sprintf("Nuevo %02d", i),
			Lat: 20.0, Lng: -75.0, SucursalCodigo: &stg,
			SyncedAt: pgtype.Timestamptz{Time: hace10m, Valid: true},
		})
	}
	// Y UNO RECIÉN TRAÍDO, con la marca de AHORA MISMO. Aquí había un cliente SIN marca,
	// y ya no puede haberlo: `customers.synced_at` es `NOT NULL DEFAULT now()` en
	// 00001_init.sql, y desde que la bajada se trocea POR LA MARCA una fila sin ella no
	// tendría por dónde continuarse — se quedaría en el mismo sitio de la cadena para
	// siempre. Que la columna siga siendo NOT NULL lo vigila
	// `TestLaBajadaPorMarcaExigeQueLasDosColumnasSeanNotNull`.
	recien := uuid.New()
	nuevos[recien.String()] = true
	q.padron = append(q.padron, sqlc.ListarClientesRow{
		ID: recien, Name: "Recién traído",
		Lat: 20.0, Lng: -75.0, SucursalCodigo: &stg,
		SyncedAt: pgtype.Timestamptz{Time: time.Now().UTC().Add(-time.Minute), Valid: true},
	})

	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())
	desde := time.Now().UTC().Add(-time.Hour).Format(time.RFC3339)

	vistos := map[string]bool{}
	continuar := ""
	for tandas := 1; ; tandas++ {
		if tandas > 10 {
			t.Fatal("la cadena de tandas no termina")
		}
		url := "/api/sync/cambios?tope=2&desde=" + desde
		if continuar != "" {
			url += "&continuar=" + continuar
		}
		w := pedirTab(t, h, http.MethodGet, url, jwt, "")
		m := leerTab(t, w)
		clientes, _, _ := conjuntoDe(t, m, "customers")
		for id := range clientes {
			if vistos[id] {
				t.Fatalf("tanda %d repitió al cliente %s", tandas, id)
			}
			vistos[id] = true
		}
		if truncado, _ := m["truncado"].(bool); !truncado {
			break
		}
		continuar, _ = m["continuar"].(string)
		if continuar == "" {
			t.Fatalf("tanda %d dijo «truncado» y no dijo por dónde seguir", tandas)
		}
	}

	if len(vistos) != len(nuevos) {
		t.Fatalf("bajaron %d clientes de los %d que cambiaron", len(vistos), len(nuevos))
	}
	for id := range nuevos {
		if !vistos[id] {
			t.Errorf("no bajó el cliente %s, que sí había cambiado", id)
		}
	}
}

// LA CARGA INICIAL BAJA EL PADRÓN ENTERO, encadenando COMO ENCADENA EL APARATO.
//
// Ésta es la prueba que faltaba, y su forma es lo que importa: **el `desde` avanza en cada
// vuelta**. El aparato relee su marca de frescura antes de cada tanda (`bajada.dart`) y ya
// se apuntó el `hasta` que devolvió la anterior, así que la tanda 2 NO pide lo mismo que
// la 1. Las dos pruebas que había mandaban un `desde` fijo, y con `desde` fijo la fijación
// del cursor es un no-op: no comprobaban nada de esto.
//
// Sin `porDondeSeguir.Empezada`, la tanda 2 de una carga inicial confundía «la cadena
// empezó sin desde» con «todavía no se ha fijado», se quedaba con el `hasta` de la primera
// como filtro, no emitía ni una fila y daba la bajada por terminada: **2.000 clientes de
// 8.103, con cara de completa**. El mismo número y el mismo silencio del 15/09.
//
// Y lo peor: como la cadena acaba «bien», la guarda del aparato que avisa de una bajada
// cortada tampoco salta. No hay a quién preguntarle qué pasó.
func TestLaCargaInicialBajaElPadronEnteroEncadenandoComoElAparato(t *testing.T) {
	q := nuevoEspejo()
	stg := "STG"
	const total = 7
	ayer := time.Now().UTC().Add(-24 * time.Hour)
	for i := 0; i < total; i++ {
		q.padron = append(q.padron, sqlc.ListarClientesRow{
			ID:             uuid.New(),
			Name:           fmt.Sprintf("Cliente %02d", i),
			Lat:            20.0,
			Lng:            -75.0,
			SucursalCodigo: &stg,
			SyncedAt:       pgtype.Timestamptz{Time: ayer, Valid: true},
		})
	}
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	vistos := map[string]bool{}
	continuar, desde := "", "" // la primera tanda va SIN `desde`: aparato vacío
	for tandas := 1; ; tandas++ {
		if tandas > 10 {
			t.Fatal("la cadena de tandas no termina")
		}
		url := "/api/sync/cambios?tope=3"
		if desde != "" {
			url += "&desde=" + desde
		}
		if continuar != "" {
			url += "&continuar=" + continuar
		}
		w := pedirTab(t, h, http.MethodGet, url, jwt, "")
		m := leerTab(t, w)

		clientes, _, _ := conjuntoDe(t, m, "customers")
		for id := range clientes {
			if vistos[id] {
				t.Fatalf("tanda %d repitió al cliente %s", tandas, id)
			}
			vistos[id] = true
		}
		if truncado, _ := m["truncado"].(bool); !truncado {
			break
		}
		continuar, _ = m["continuar"].(string)
		if continuar == "" {
			t.Fatalf("tanda %d dijo «truncado» y no dijo por dónde seguir", tandas)
		}
		// AQUÍ ESTÁ LA GRACIA: el aparato se apunta el `hasta` y lo manda como `desde` en
		// la vuelta siguiente. Es lo que hace `bajada.dart`, y lo que ninguna prueba hacía.
		desde, _ = m["hasta"].(string)
	}

	if len(vistos) != total {
		t.Fatalf("la carga inicial dejó %d clientes de %d y dio la bajada por terminada: "+
			"el aparato se va al almacén con el padrón a medias y nadie se entera",
			len(vistos), total)
	}
}

// EL LOGÍSTICO SE LLEVA EL PADRÓN DE SU SUCURSAL, Y NADA MÁS.
//
// Es la pregunta que hizo Jose el 25/09/2026 antes de dar el proyecto por
// acabado: «un usuario logístico puede entrar ahora mismo, cargar los datos
// ÚNICOS DE SU SUCURSAL y irse sin conexión a trabajar».
//
// La bajada sirve el padrón con `ventanaDelAlcance` —la ventana SIN la sucursal
// que se elige arriba en la barra— porque los clientes van por CÓDIGO y no por
// id, y ese código sale de `Acotado.Codigo()`. Para un SUPER ADMIN es nil y
// bajan los ocho; para un operador es el suyo y baja el suyo. Eso estaba escrito
// en un comentario y no lo ataba nada: en producción son 2.689 clientes de
// Santiago contra 8.578 de las ocho, así que si el acotado se cae, el repartidor
// se lleva el triple de datos al almacén y ve clientes que no son suyos.
//
// Se comprueba con las DOS mitades, que es lo que pide el §3-bis:
//   - el operador de Santiago NO ve al de Holguín;
//   - y sí ve a los suyos, para que la prueba no pase por servir cero.
func TestElLogisticoSoloSeLlevaElPadronDeSuSucursal(t *testing.T) {
	q := nuevoEspejo()
	stg := "STG"
	hol := "HOL"

	deStg := uuid.New()
	deHol := uuid.New()
	q.padron = append(q.padron,
		sqlc.ListarClientesRow{
			ID: deStg, Name: "Kiosko de Santiago",
			Lat: 20.0, Lng: -75.8, SucursalCodigo: &stg,
		},
		sqlc.ListarClientesRow{
			ID: deHol, Name: "Kiosko de Holguín",
			Lat: 20.9, Lng: -76.2, SucursalCodigo: &hol,
		},
	)

	h := montarTab(t, q)

	// El operador de Santiago, que es quien se va al almacén.
	w := pedirTab(t, h, http.MethodGet, "/api/sync/cambios", tokenTab(t, sucStg.String()), "")
	puestos, _, _ := conjuntoDe(t, leerTab(t, w), "customers")

	if !puestos[deStg.String()] {
		t.Fatalf("el operador de Santiago NO recibió a su propio cliente: se llevaría un padrón incompleto al almacén")
	}
	if puestos[deHol.String()] {
		t.Fatalf("el operador de Santiago recibió un cliente de HOLGUÍN: el acotado del padrón se cayó")
	}
}

// EL RECOSTEO MANDA LOS PEDIDOS TRADUCIDOS A LA PUERTA.
//
// ESTO ESTUVO ROTO Y EN VERDE, y así se encontró el 26/09/2026 escribiendo la puerta del
// webhook, que necesitaba la misma traducción: el recosteo metía los pedidos de
// `/integration/orders` TAL CUAL en el `orders` del lote. Las dos formas no se parecen —PEDIDO
// manda `id` y `sucursalCodigo`, la puerta espera `externalId` y `sucursalExternalId`—, así
// que llegaba un lote entero con el id VACÍO y sin id no se guarda ningún pedido.
//
// LA FORMA DEL FALLO, que es la que importa: **no daba error**. Contestaba 200 con
// `total: 5000, recosteados: 0`, y un cero es perfectamente creíble para «no había nada que
// recostear». Las tres pruebas que ya había —el 502, el 200 sin pedidos y el aviso del tope—
// pasaban con el fallo puesto, porque ninguna miraba QUÉ le llegaba a la puerta.
//
// Por eso esta prueba no comprueba el código de la respuesta: comprueba el CUERPO que sale.
func TestElRecosteoMandaLosPedidosTraducidos(t *testing.T) {
	pedido := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		// La forma REAL de PEDIDO, la de `/integration/orders`.
		_ = json.NewEncoder(w).Encode(map[string]any{"orders": []any{map[string]any{
			"id":             "PED-42",
			"folio":          "X-2992",
			"sucursalCodigo": "STG",
			"itemsOrigen":    "factura",
			"cliente":        map[string]any{"nombre": "Uno", "latitud": 20.1, "longitud": -77.2},
			"items":          []any{map[string]any{"codigo": "A", "pesoLineaKg": 24, "packs": 12}},
		}}})
	}))
	defer pedido.Close()

	var loQueLlegoALaPuerta string
	puerta := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		crudo, _ := io.ReadAll(r.Body)
		loQueLlegoALaPuerta = string(crudo)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"weightsSource": "pedido",
			"results":       []any{map[string]any{"status": "quoted", "price": 100.0}},
		})
	}))
	defer puerta.Close()

	t.Setenv("SERVICE_API_KEY", "clave")
	t.Setenv("PEDIDO_API_URL", pedido.URL)
	t.Setenv("DELIVERY_URL", puerta.URL)
	h := montarTab(t, nuevoEspejo())

	w := pedirTab(t, h, http.MethodPost, "/api/admin/recompute", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}

	if !strings.Contains(loQueLlegoALaPuerta, `"externalId":"PED-42"`) {
		t.Fatalf("a la puerta le llegó el pedido SIN traducir: el `externalId` es lo que lo "+
			"identifica, y sin él no se guarda ninguno — el recosteo contestaría 200 y no "+
			"recostearía nada.\n  llegó: %s", loQueLlegoALaPuerta)
	}
	if !strings.Contains(loQueLlegoALaPuerta, `"sucursalExternalId":"STG"`) {
		t.Fatalf("se perdió la sucursal: sin ella la puerta no sabe desde qué almacén medir "+
			"la distancia.\n  llegó: %s", loQueLlegoALaPuerta)
	}
	// Y QUE EL NÚMERO QUE SALE CUADRE CON LO QUE PASÓ. Sin esto, «llegó traducido» se cumple
	// aunque la respuesta siga diciendo cero.
	if !strings.Contains(w.Body.String(), `"recosteados":1`) {
		t.Fatalf("llegó bien y la respuesta no lo cuenta: %s", w.Body.String())
	}
}

// LA BAJADA Y `/api/orders` SIRVEN EL MISMO RENGLÓN, Y SE ATAN CON UNA PRUEBA.
//
// El 26/09/2026 se le añadió el peso a `RenglonSalida`, que es lo que sirve `/api/orders`.
// Pero `pedidosDeLaBajada` **no usa esa struct**: arma el renglón a mano con un mapa
// suelto. Así que la API mandaba el peso por una puerta y el aparato se bajaba por la
// otra, donde no iba — y el 28/09 Jose lo vio: «no tenemos ni unidades ni peso individual;
// el pedido sí, pero cada item anda sin nada».
//
// Dos sitios que sirven lo mismo y no comparten la struct **se separan sin que nada falle**.
// Es el §3-bis del `CLAUDE.md` con otra cara: no se atan con un comentario, se atan con una
// prueba que compara las dos formas.
func TestLaBajadaSirveLosMismosCamposDelRenglonQuePedidos(t *testing.T) {
	// Los campos de `RenglonSalida`, leídos de sus etiquetas `json` — no de una lista
	// escrita a mano, que es lo que se desincroniza.
	deLaAPI := map[string]bool{}
	tipo := reflect.TypeOf(RenglonSalida{})
	for i := 0; i < tipo.NumField(); i++ {
		etiqueta := tipo.Field(i).Tag.Get("json")
		if etiqueta == "" || etiqueta == "-" {
			continue
		}
		deLaAPI[strings.Split(etiqueta, ",")[0]] = true
	}

	// Y los que de verdad escribe la bajada, leídos del código fuente: es un mapa
	// literal, así que no hay tipo que preguntar. Se lee el fichero a propósito — lo que
	// se quiere cazar es justo que alguien añada un campo en un sitio y no en el otro.
	crudo, err := os.ReadFile("espejo.go")
	if err != nil {
		t.Fatalf("no se pudo leer espejo.go: %v", err)
	}
	texto := string(crudo)
	i := strings.Index(texto, "renglones[l.OrderID] = append(")
	if i < 0 {
		t.Fatal("no se encontró dónde arma la bajada sus renglones: si se movió, esta " +
			"prueba deja de vigilar nada y hay que apuntarla al sitio nuevo")
	}
	bloque := texto[i:]
	if fin := strings.Index(bloque, "})"); fin > 0 {
		bloque = bloque[:fin]
	}

	var faltan []string
	for campo := range deLaAPI {
		// `id`, `name` y `productId` los sirve la bajada con otro nombre o no le hacen
		// falta al aparato; lo que se vigila es que no se pierda un campo de DATOS.
		if campo == "name" {
			continue
		}
		if !strings.Contains(bloque, `"`+campo+`"`) {
			faltan = append(faltan, campo)
		}
	}
	sort.Strings(faltan)

	if len(faltan) > 0 {
		t.Fatalf(
			"la bajada NO sirve estos campos del renglón y `/api/orders` sí: %v.\n"+
				"El aparato se baja por la bajada, así que lo que falte aquí no llega "+
				"aunque la API lo mande por la otra puerta. Pasó el 28/09/2026 con el "+
				"peso: el total del pedido salía y los renglones iban en blanco.",
			faltan,
		)
	}
}
