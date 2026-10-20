package sqlc

// EL PUNTO DE ENTREGA A MANO CONTRA POSTGRES DE VERDAD (issue 19 de Amado, 20/10/2026).
//
// Lo que ningún doble ve: los CASE del `ON CONFLICT DO UPDATE` y de su `WHERE ... IS DISTINCT FROM`
// de `GuardarPedidoDelEspejo`. Una versión del upsert que pisara el punto (CASE quitado del SET) o
// que reescribiera el pedido en cada pasada (CASE quitado del WHERE) se ve aquí y en ningún otro
// sitio. Se salta sin REPARTO_MOTOR_REAL_DSN y revierte su transacción (ver
// `consultas_motor_real_test.go`).

import (
	"errors"
	"fmt"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type puntoLeido struct {
	EndLat, EndLng, Lat, Lng *float64
	EndAddress               *string
	Km                       *float64
	Manual                   bool
	Por                      *string
	ClienteLat, ClienteLng   *float64
	ClienteAddress           *string
	Nombre                   string
}

// String enseña los VALORES: con punteros, un rojo imprimía direcciones de memoria.
func (p puntoLeido) String() string {
	f := func(v *float64) any {
		if v == nil {
			return nil
		}
		return *v
	}
	t := func(v *string) any {
		if v == nil {
			return nil
		}
		return *v
	}
	return fmt.Sprintf("{end=(%v,%v) lat/lng=(%v,%v) dir=%v km=%v manual=%v por=%v cliente=(%v,%v,%v) nombre=%q}",
		f(p.EndLat), f(p.EndLng), f(p.Lat), f(p.Lng), t(p.EndAddress), f(p.Km), p.Manual, t(p.Por),
		f(p.ClienteLat), f(p.ClienteLng), t(p.ClienteAddress), p.Nombre)
}

func (b *banco) puntoDe(external string) puntoLeido {
	b.t.Helper()
	var p puntoLeido
	err := b.tx.QueryRow(b.ctx, `
SELECT end_lat, end_lng, lat, lng, end_address, delivery_distance_km, punto_manual, punto_manual_por,
       punto_cliente_lat, punto_cliente_lng, punto_cliente_address, customer_name
FROM orders WHERE source = 'pedido' AND external_id = $1`, external).Scan(
		&p.EndLat, &p.EndLng, &p.Lat, &p.Lng, &p.EndAddress, &p.Km, &p.Manual, &p.Por,
		&p.ClienteLat, &p.ClienteLng, &p.ClienteAddress, &p.Nombre)
	if err != nil {
		b.t.Fatal(err)
	}
	return p
}

// repaso es una pasada del espejo con el punto del cliente que se le diga. Devuelve si el
// upsert ESCRIBIÓ (false = el WHERE dijo «nada que cambiar», que no devuelve fila).
func (b *banco) repaso(sucursal [16]byte, external, nombre string, lat, lng float64, dir string, km float64) bool {
	b.t.Helper()
	fuente := ProcedenciaPedido
	_, err := b.q.GuardarPedidoDelEspejo(b.ctx, GuardarPedidoDelEspejoParams{
		CustomerName: nombre, Address: dir, EndAddress: &dir,
		Lat: &lat, Lng: &lng, EndLat: &lat, EndLng: &lng, Weight: 5,
		BranchID: alcance(sucursal), Source: &fuente, ExternalID: &external,
		DeliveryDistanceKm: &km,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return false
	}
	if err != nil {
		b.t.Fatalf("GuardarPedidoDelEspejo: %v", err)
	}
	return true
}

func igualF(a *float64, b float64) bool { return a != nil && *a == b }

func TestMotorReal_ElEspejoRespetaElPuntoDeEntregaAMano(t *testing.T) {
	b := nuevoBanco(t, motorReal(t))
	suc := b.sucursal()
	const ext = "punto-mano-1"

	// 1. El pedido entra con el punto del cliente.
	if !b.repaso(suc, ext, "Bar", 20.01, -75.81, "Calle del cliente", 10) {
		t.Fatal("el alta no devolvió fila")
	}
	// Sin punto manual, un repaso con otro punto del cliente SÍ lo sigue (la pareja: sin ella,
	// «el espejo respeta el manual» se cumpliría con un espejo que no escribe nunca).
	if !b.repaso(suc, ext, "Bar", 20.02, -75.82, "Calle del cliente", 11) {
		t.Fatal("sin punto manual, un punto nuevo del cliente tenía que escribirse")
	}
	if p := b.puntoDe(ext); !igualF(p.EndLat, 20.02) || !igualF(p.Km, 11) || p.Manual || p.ClienteLat != nil {
		t.Fatalf("sin punto manual el espejo sigue al cliente y no guarda punto_cliente: %+v", p)
	}

	// 2. Una persona pone el suyo.
	id := b.id(`SELECT id FROM orders WHERE external_id = $1`, ext)
	if _, err := b.q.PonerPuntoDeEntregaAMano(b.ctx, PonerPuntoDeEntregaAManoParams{
		ID: id, Lat: f64(20.10), Lng: f64(-75.90), Direccion: str("Calle del logístico"),
		Por: str("p-logistico"), DeliveryDistanceKm: f64(3), Sucursal: alcance(suc),
	}); err != nil {
		t.Fatal(err)
	}
	p := b.puntoDe(ext)
	if !p.Manual || !igualF(p.EndLat, 20.10) || !igualF(p.Lat, 20.10) || !igualF(p.Lng, -75.90) ||
		*p.EndAddress != "Calle del logístico" || !igualF(p.Km, 3) || *p.Por != "p-logistico" ||
		!igualF(p.ClienteLat, 20.02) || !igualF(p.ClienteLng, -75.82) || *p.ClienteAddress != "Calle del cliente" {
		t.Fatalf("el punto manual no quedó como se puso, o no guardó el del cliente: %+v", p)
	}

	// 3. UN REPASO IDÉNTICO NO REESCRIBE. Es lo que se pierde si el CASE del WHERE se quita: el
	// punto manual difiere de `excluded.*` para siempre y el pedido se reescribe cada minuto.
	if b.repaso(suc, ext, "Bar", 20.02, -75.82, "Calle del cliente", 11) {
		t.Fatal("un pedido con punto manual y sin más cambios se REESCRIBIÓ: el WHERE compara contra el valor de PEDIDO y no contra el efectivo")
	}

	// 4. El cliente corrige su punto: NO pisa el manual y SÍ actualiza punto_cliente_*, aunque
	// nada más haya cambiado (por eso el punto del cliente entra en la comparación).
	if !b.repaso(suc, ext, "Bar", 20.30, -75.50, "Calle corregida", 14) {
		t.Fatal("un punto del cliente nuevo no se guardó (punto_cliente_* tiene que entrar en el WHERE)")
	}
	p = b.puntoDe(ext)
	// `lng` TAMBIÉN (set-lng): lat/lng son los mismos que end_lat/end_lng, los cuatro, y un espejo que
	// pisara sólo `lng` dejaría el punto partido: la latitud del logístico y la longitud del cliente.
	if !p.Manual || !igualF(p.EndLat, 20.10) || !igualF(p.EndLng, -75.90) || !igualF(p.Lat, 20.10) || !igualF(p.Lng, -75.90) ||
		*p.EndAddress != "Calle del logístico" || !igualF(p.Km, 3) {
		t.Fatalf("el espejo PISÓ el punto manual o su distancia: %+v", p)
	}
	if !igualF(p.ClienteLat, 20.30) || !igualF(p.ClienteLng, -75.50) || *p.ClienteAddress != "Calle corregida" {
		t.Fatalf("punto_cliente_* no quedó con el último punto del cliente: %+v", p)
	}
	if b.repaso(suc, ext, "Bar", 20.30, -75.50, "Calle corregida", 14) {
		t.Fatal("el repaso repetido del punto corregido se reescribió")
	}

	// 5. Otro cambio del pedido (el nombre) se aplica, y el punto sigue siendo el manual.
	if !b.repaso(suc, ext, "Bar del puerto", 20.30, -75.50, "Calle corregida", 14) {
		t.Fatal("un cambio de nombre no se escribió")
	}
	if p = b.puntoDe(ext); p.Nombre != "Bar del puerto" || !igualF(p.EndLat, 20.10) || !igualF(p.EndLng, -75.90) ||
		!igualF(p.Lat, 20.10) || !igualF(p.Lng, -75.90) || !p.Manual {
		t.Fatalf("lo demás del upsert tenía que seguir igual y el punto manual quedarse: %+v", p)
	}

	// 6. Volver al del cliente: el MÁS RECIENTE, y desde ahí el espejo vuelve a mandar.
	if _, err := b.q.DevolverPuntoDeEntregaAlCliente(b.ctx, DevolverPuntoDeEntregaAlClienteParams{
		ID: id, Lat: f64(20.30), Lng: f64(-75.50), DeliveryDistanceKm: f64(14), Sucursal: alcance(suc),
	}); err != nil {
		t.Fatal(err)
	}
	p = b.puntoDe(ext)
	if p.Manual || p.Por != nil || !igualF(p.EndLat, 20.30) || !igualF(p.Lat, 20.30) || !igualF(p.EndLng, -75.50) ||
		*p.EndAddress != "Calle corregida" || p.ClienteLat != nil || p.ClienteLng != nil || p.ClienteAddress != nil {
		t.Fatalf("el DELETE no dejó el punto del cliente más reciente con la marca limpia: %+v", p)
	}
	if !b.repaso(suc, ext, "Bar del puerto", 20.40, -75.40, "Calle otra vez", 15) {
		t.Fatal("ya no es manual: el espejo tenía que volver a escribir el punto del cliente")
	}
	if p = b.puntoDe(ext); !igualF(p.EndLat, 20.40) || !igualF(p.EndLng, -75.40) || !igualF(p.Lat, 20.40) || !igualF(p.Lng, -75.40) ||
		!igualF(p.Km, 15) || p.ClienteLat != nil {
		t.Fatalf("tras volver al cliente el espejo manda otra vez: %+v", p)
	}
}

// Las guardas del UPDATE: lo que el manejador comprueba y el WHERE repite por la carrera.
func TestMotorReal_PonerElPuntoALaManoSoloDondeSePuede(t *testing.T) {
	b := nuevoBanco(t, motorReal(t))
	suc, otra := b.sucursal(), b.sucursal()
	ruta := b.ruta(suc, RouteStatusPlanned)

	ponerEn := func(id [16]byte, sucursal [16]byte, rutaID [16]byte, rutaValida bool, almacen *string) error {
		r := alcance(rutaID)
		if !rutaValida {
			r = sinAlcance
		}
		_, err := b.q.PonerPuntoDeEntregaAMano(b.ctx, PonerPuntoDeEntregaAManoParams{
			ID: id, Lat: f64(20.1), Lng: f64(-75.9), Por: str("p"), DeliveryDistanceKm: f64(1),
			RutaID: r, AlmacenSalidaCodigo: almacen, Sucursal: alcance(sucursal),
		})
		return err
	}
	suelto := b.pedido(listo("suelto", suc))
	if err := ponerEn(suelto, suc, ruta, false, nil); err != nil {
		t.Fatalf("un pedido suelto tenía que aceptarlo: %v", err)
	}
	// Otra sucursal.
	if err := ponerEn(suelto, otra, ruta, false, nil); !errors.Is(err, pgx.ErrNoRows) {
		t.Fatalf("otra sucursal: %v", err)
	}
	// La ruta que se bloqueó no es la del pedido (la carrera).
	if err := ponerEn(suelto, suc, ruta, true, nil); !errors.Is(err, pgx.ErrNoRows) {
		t.Fatalf("ruta distinta: %v", err)
	}
	// El almacén con el que se midió ya no es el del pedido.
	if err := ponerEn(suelto, suc, ruta, false, str("2")); !errors.Is(err, pgx.ErrNoRows) {
		t.Fatalf("almacén distinto: %v", err)
	}
	// Un entregado: nunca.
	e := listo("entregado", suc)
	e.Entregado, e.Resultado = true, str("entregado")
	if err := ponerEn(b.pedido(e), suc, ruta, false, nil); !errors.Is(err, pgx.ErrNoRows) {
		t.Fatalf("un entregado se aceptó: %v", err)
	}
	// El DELETE de uno que no es manual no encuentra fila.
	if _, err := b.q.DevolverPuntoDeEntregaAlCliente(b.ctx, DevolverPuntoDeEntregaAlClienteParams{
		ID: b.pedido(listo("normal", suc)), Lat: f64(1), Lng: f64(1), Sucursal: alcance(suc),
	}); !errors.Is(err, pgx.ErrNoRows) {
		t.Fatalf("devolver un pedido que no es manual: %v", err)
	}
}

// repasoSinPunto es una pasada del espejo cuyo pedido NO trae punto (una entrega de factura cuyo
// cliente no está en `customers`): lat, lng, end_lat, end_lng y km vacíos.
func (b *banco) repasoSinPunto(sucursal [16]byte, external, nombre, dir string) bool {
	b.t.Helper()
	fuente := ProcedenciaPedido
	_, err := b.q.GuardarPedidoDelEspejo(b.ctx, GuardarPedidoDelEspejoParams{
		CustomerName: nombre, Address: dir, EndAddress: &dir, Weight: 5,
		BranchID: alcance(sucursal), Source: &fuente, ExternalID: &external,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return false
	}
	if err != nil {
		b.t.Fatalf("GuardarPedidoDelEspejo: %v", err)
	}
	return true
}

// G1 (auditoría del 20/10/2026): una entrada SIN punto no borra el que la fila ya tenía.
func TestMotorReal_UnaEntradaSinPuntoNoBorraElQueYaHabia(t *testing.T) {
	b := nuevoBanco(t, motorReal(t))
	suc := b.sucursal()
	const ext = "punto-g1"

	// La fila de PEDIDO, con su punto, su dirección y su km, y va en una ruta.
	b.repaso(suc, ext, "Bar", 20.05, -75.75, "Calle del cliente", 12)
	b.exec(`UPDATE orders SET route_id = $2, ultima_ruta_id = $2, stop_order = 1 WHERE external_id = $1`, ext, b.ruta(suc, RouteStatusPlanned))

	// Llega la factura del mismo pedido (el adoptado conserva el external_id; aquí el mismo upsert):
	// su cliente no está en `customers`, sin punto.
	if !b.repasoSinPunto(suc, ext, "Bar de la factura", "Otra calle") {
		t.Fatal("el nombre cambió: el upsert tenía que escribir")
	}
	p := b.puntoDe(ext)
	if !igualF(p.EndLat, 20.05) || !igualF(p.EndLng, -75.75) || !igualF(p.Lat, 20.05) || !igualF(p.Lng, -75.75) {
		t.Fatalf("la entrada sin punto BORRÓ el punto que ya tenía (el armador excluye la parada por end_lat IS NULL): %+v", p)
	}
	if !igualF(p.Km, 12) || p.EndAddress == nil || *p.EndAddress != "Calle del cliente" {
		t.Fatalf("y se conserva CON su km y su dirección (un km sin su punto, o un punto sin su km, mienten): %+v", p)
	}
	if p.Nombre != "Bar de la factura" {
		t.Fatalf("lo demás del upsert sí se aplica: %+v", p)
	}
	if b.entero(`SELECT count(*) FROM orders WHERE external_id = $1 AND route_id IS NOT NULL AND end_lat IS NOT NULL`, ext) != 1 {
		t.Fatal("la parada de la ruta sigue siendo armable")
	}

	// UN REPASO IDÉNTICO NO REESCRIBE: el WHERE usa los mismos valores efectivos que el SET.
	if b.repasoSinPunto(suc, ext, "Bar de la factura", "Otra calle") {
		t.Fatal("un repaso idéntico sin punto se REESCRIBIÓ: el WHERE compara contra NULL y no contra el valor efectivo")
	}

	// Un punto a medias (sólo la latitud) tampoco es un punto: se conserva el que había.
	fuente := ProcedenciaPedido
	ext2 := ext
	dir := "Media"
	if _, err := b.q.GuardarPedidoDelEspejo(b.ctx, GuardarPedidoDelEspejoParams{
		CustomerName: "Bar de la factura", Address: dir, EndAddress: &dir, Weight: 5, EndLat: f64(33),
		BranchID: alcance(suc), Source: &fuente, ExternalID: &ext2,
	}); err != nil && !errors.Is(err, pgx.ErrNoRows) {
		t.Fatal(err)
	}
	if p = b.puntoDe(ext); !igualF(p.EndLat, 20.05) || !igualF(p.EndLng, -75.75) {
		t.Fatalf("un punto a medias no sustituye al entero: %+v", p)
	}

	// Si el que entra TRAE punto, MANDA el que entra (la pareja: sin ella, «conservar» se cumpliría
	// con un upsert que no escribe el punto nunca).
	if !b.repaso(suc, ext, "Bar de la factura", 20.30, -75.50, "Calle nueva", 14) {
		t.Fatal("un punto nuevo tenía que escribirse")
	}
	if p = b.puntoDe(ext); !igualF(p.EndLat, 20.30) || !igualF(p.EndLng, -75.50) || !igualF(p.Lat, 20.30) || !igualF(p.Lng, -75.50) ||
		!igualF(p.Km, 14) || *p.EndAddress != "Calle nueva" {
		t.Fatalf("si el que entra trae punto, manda el que entra: %+v", p)
	}
}

func TestMotorReal_UnaEntregaNuevaSinPuntoSeGuardaSinPuntoYUnPedidoDePedidoSigueAlCliente(t *testing.T) {
	b := nuevoBanco(t, motorReal(t))
	suc := b.sucursal()

	// Una entrega nueva sin punto se guarda sin punto (no se inventa uno).
	if !b.repasoSinPunto(suc, "sin-punto-1", "Sin punto", "Calle") {
		t.Fatal("el alta no devolvió fila")
	}
	if p := b.puntoDe("sin-punto-1"); p.EndLat != nil || p.EndLng != nil || p.Lat != nil || p.Lng != nil || p.Km != nil {
		t.Fatalf("una entrega nueva sin punto se guarda SIN punto: %+v", p)
	}
	// Sin punto antes y sin punto ahora: lo que entra (la dirección) se aplica.
	if !b.repasoSinPunto(suc, "sin-punto-1", "Sin punto", "Calle mejor escrita") {
		t.Fatal("la dirección cambió y no se escribió")
	}
	if p := b.puntoDe("sin-punto-1"); p.EndAddress == nil || *p.EndAddress != "Calle mejor escrita" {
		t.Fatalf("sin punto previo manda lo que entra: %+v", p)
	}
	// Y gana el primer punto cuando llega.
	if !b.repaso(suc, "sin-punto-1", "Sin punto", 20.2, -75.2, "Calle mejor escrita", 7) {
		t.Fatal("el primer punto tenía que escribirse")
	}
	if p := b.puntoDe("sin-punto-1"); !igualF(p.EndLat, 20.2) || !igualF(p.Lng, -75.2) || !igualF(p.Km, 7) {
		t.Fatalf("el primer punto entra: %+v", p)
	}

	// UN PEDIDO DE PEDIDO (siempre con punto) se comporta como siempre: cada repaso con otro punto
	// lo sigue, y uno idéntico no reescribe.
	b.repaso(suc, "de-pedido-1", "Bar", 20.01, -75.81, "Calle A", 10)
	if !b.repaso(suc, "de-pedido-1", "Bar", 20.02, -75.82, "Calle B", 11) {
		t.Fatal("un punto nuevo del cliente tenía que escribirse")
	}
	if p := b.puntoDe("de-pedido-1"); !igualF(p.EndLat, 20.02) || !igualF(p.Lng, -75.82) || !igualF(p.Km, 11) || *p.EndAddress != "Calle B" {
		t.Fatalf("un pedido con punto sigue al cliente: %+v", p)
	}
	if b.repaso(suc, "de-pedido-1", "Bar", 20.02, -75.82, "Calle B", 11) {
		t.Fatal("un repaso idéntico se reescribió")
	}
}

// Las marcas de «entregado» son DOS (`resultado` y `delivered_at`) y cada una, SOLA, rechaza el PUT y
// el DELETE del punto (poner-sin-resultado, poner-sin-delivered, devolver-sin-entregado,
// devolver-sin-delivered): una guarda que mirara sólo una de las dos dejaría cambiar el punto de
// algo que ya bajó del camión.
func TestMotorReal_CadaMarcaDeEntregadoPorSiSolaRechazaElPuntoALaMano(t *testing.T) {
	b := nuevoBanco(t, motorReal(t))
	suc := b.sucursal()
	marcas := map[string]string{
		"solo resultado":    `UPDATE orders SET resultado = 'entregado' WHERE id = $1`,
		"solo delivered_at": `UPDATE orders SET delivered_at = now() WHERE id = $1`,
	}
	poner := func(id uuid.UUID) error {
		_, err := b.q.PonerPuntoDeEntregaAMano(b.ctx, PonerPuntoDeEntregaAManoParams{
			ID: id, Lat: f64(20.1), Lng: f64(-75.9), Por: str("p"), DeliveryDistanceKm: f64(1), Sucursal: alcance(suc),
		})
		return err
	}
	devolver := func(id uuid.UUID) error {
		_, err := b.q.DevolverPuntoDeEntregaAlCliente(b.ctx, DevolverPuntoDeEntregaAlClienteParams{
			ID: id, Lat: f64(21.5), Lng: f64(-77.9), Sucursal: alcance(suc),
		})
		return err
	}

	// La pareja: el pedido SIN marcas acepta las dos cosas.
	libre := b.pedido(listo("libre", suc))
	if err := poner(libre); err != nil {
		t.Fatalf("un pedido sin marcas acepta el PUT: %v", err)
	}
	if err := devolver(libre); err != nil {
		t.Fatalf("y el DELETE: %v", err)
	}

	for nombre, marca := range marcas {
		// PUT
		p := b.pedido(listo("put "+nombre, suc))
		b.exec(marca, p)
		if err := poner(p); !errors.Is(err, pgx.ErrNoRows) {
			t.Errorf("PUT con %s: tenía que rechazarse y salió %v", nombre, err)
		}
		if b.entero(`SELECT count(*) FROM orders WHERE id = $1 AND punto_manual`, p) != 0 {
			t.Errorf("PUT con %s: la fila se marcó a pesar del rechazo", nombre)
		}
		// DELETE: primero manual (sin marcas), luego la marca sola.
		d := b.pedido(listo("delete "+nombre, suc))
		if err := poner(d); err != nil {
			t.Fatal(err)
		}
		b.exec(marca, d)
		if err := devolver(d); !errors.Is(err, pgx.ErrNoRows) {
			t.Errorf("DELETE con %s: tenía que rechazarse y salió %v", nombre, err)
		}
		if b.entero(`SELECT count(*) FROM orders WHERE id = $1 AND punto_manual`, d) != 1 {
			t.Errorf("DELETE con %s: la fila dejó de ser manual a pesar del rechazo", nombre)
		}
	}
}

// poner-pc-siempre, poner-pc-addr-siempre y poner-dir-pisa: el punto del CLIENTE (a donde vuelve el
// DELETE) se guarda sólo la PRIMERA vez, y un PUT sin dirección no borra la que había.
func TestMotorReal_UnSegundoPonerNoPisaElPuntoDelClienteNiBorraLaDireccion(t *testing.T) {
	b := nuevoBanco(t, motorReal(t))
	suc := b.sucursal()
	const ext = "punto-dos-puts"
	b.repaso(suc, ext, "Bar", 20.01, -75.81, "Calle del cliente", 10)
	id := b.id(`SELECT id FROM orders WHERE external_id = $1`, ext)

	poner := func(lat, lng float64, dir *string) {
		t.Helper()
		if _, err := b.q.PonerPuntoDeEntregaAMano(b.ctx, PonerPuntoDeEntregaAManoParams{
			ID: id, Lat: f64(lat), Lng: f64(lng), Direccion: dir, Por: str("p"), DeliveryDistanceKm: f64(3), Sucursal: alcance(suc),
		}); err != nil {
			t.Fatal(err)
		}
	}
	poner(20.10, -75.90, str("Calle A del logístico"))
	poner(20.20, -75.95, nil) // SEGUNDO PUT, sin dirección

	p := b.puntoDe(ext)
	if !igualF(p.ClienteLat, 20.01) || !igualF(p.ClienteLng, -75.81) {
		t.Fatalf("el segundo PUT PISÓ punto_cliente_lat/lng con el punto manual anterior: se perdió a dónde vuelve el DELETE: %+v", p)
	}
	if p.ClienteAddress == nil || *p.ClienteAddress != "Calle del cliente" {
		t.Fatalf("el segundo PUT PISÓ punto_cliente_address con la dirección manual anterior: %+v", p)
	}
	if !igualF(p.EndLat, 20.20) || !igualF(p.EndLng, -75.95) || !igualF(p.Lat, 20.20) || !igualF(p.Lng, -75.95) {
		t.Fatalf("el segundo PUT sí pone el punto nuevo: %+v", p)
	}
	if p.EndAddress == nil || *p.EndAddress != "Calle A del logístico" {
		t.Fatalf("un PUT sin dirección CONSERVA la que había (end_address): %+v", p)
	}
	// Y la dirección que sí viene, pisa.
	poner(20.30, -75.99, str("Calle B"))
	if p = b.puntoDe(ext); p.EndAddress == nil || *p.EndAddress != "Calle B" {
		t.Fatalf("un PUT con dirección la pone: %+v", p)
	}
}
