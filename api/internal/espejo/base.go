package espejo

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/store/sqlc"
)

// LO QUE EL ESPEJO GUARDA POR SU CUENTA, y por qué no va todo por HTTP.
//
// Los PEDIDOS entran por `/api/quote/batch` y por ningún otro sitio: es la puerta donde se
// les resuelve el peso y la distancia, y tener una segunda puerta sería tener dos formas de
// que el mismo pedido quedara distinto.
//
// Pero hay tres cosas que no pasan por ahí:
//
//   - La MARCA DE AGUA y la POSICIÓN DEL BARRIDO, que son el estado del propio espejo y se
//     leen de los pedidos ya guardados y de los ajustes.
//   - Los CLIENTES, que no tienen ruta de entrada: en el reparto se leen, no se dan de alta.
//
// Todo eso se lee y se escribe por el MISMO camino que los manejadores —`alcance.Acotado`—
// y no con el `Querier` pelado. El espejo no tiene persona ni sucursal, así que su alcance
// es «todas», que es justo lo que le toca: trae las ocho de una pasada.

// Base es el estado del espejo en la base del reparto.
type Base interface {
	// MarcaDeAgua es lo más nuevo que ya tenemos SEGÚN PEDIDO. nil = todavía no hay nada,
	// y entonces no hay incremental que hacer: se llena con el repaso y el barrido.
	MarcaDeAgua(ctx context.Context) (*time.Time, error)
	PosicionDelBarrido(ctx context.Context) (int, error)
	FijarBarrido(ctx context.Context, dia int) error
	GuardarCliente(ctx context.Context, c ClienteDeFuera) error
	BorrarClientesQueYaNoVienen(ctx context.Context, ids []string) (int64, error)
	// QuitarPedidos borra los que PEDIDO avisó como borrados. Ver `atender_avisos.go`.
	QuitarPedidos(ctx context.Context, externalIDs []string) error
	// ApuntarTandaDeAvisos deja constancia de una tanda que entró por el canal.
	//
	// Lo pidió la sesión de PEDIDO y tienen razón: desde su lado, **un aviso que sale y
	// no lleva a nada se ve exactamente igual que uno que funcionó**. Ellos ven que lo
	// mandaron; lo que pasó después sólo se ve aquí.
	ApuntarTandaDeAvisos(ctx context.Context, t TandaDeAvisos) error
}

// TandaDeAvisos es lo que pasó con una lectura del canal.
//
// `Traidos` son los avisos que llegaron; `Atendidos`, los que llevaron a una acción; y
// `SinEfecto`, los que no. Los tres números y no uno: «llegaron veinte» no dice nada, y
// «veinte de veinte atendidos» frente a «tres de veinte» son dos situaciones distintas que
// se arreglan en sitios distintos.
type TandaDeAvisos struct {
	Traidos   int
	Atendidos int
	SinEfecto int
	// Motivos, en palabras: «4 repetidos», «2 borrados que ya no estaban». Vacío cuando
	// todos llevaron a algo.
	Motivos string
	TardoMs int
}

// BaseDelReparto es la Base de verdad, sobre el alcance.
type BaseDelReparto struct{ Acotado *alcance.Acotado }

func (b BaseDelReparto) MarcaDeAgua(ctx context.Context) (*time.Time, error) {
	marca, err := b.Acotado.EspejoMarcaDeAgua(ctx)
	if err != nil {
		return nil, err
	}
	if !marca.Valid {
		return nil, nil
	}
	t := marca.Time
	return &t, nil
}

func (b BaseDelReparto) PosicionDelBarrido(ctx context.Context) (int, error) {
	dia, err := b.Acotado.EspejoPosicionDelBarrido(ctx)
	return int(dia), err
}

func (b BaseDelReparto) FijarBarrido(ctx context.Context, dia int) error {
	return b.Acotado.EspejoFijarBarrido(ctx, int32(dia))
}

// GuardarCliente copia un cliente. Sólo los GEOLOCALIZADOS —lo comprueba quien llama— y
// siempre por el upsert: dos pasadas a la vez no pueden duplicarlo.
func (b BaseDelReparto) GuardarCliente(ctx context.Context, c ClienteDeFuera) error {
	if c.Latitud == nil || c.Longitud == nil {
		return nil
	}
	fuente := sqlc.ProcedenciaPedido
	id := strings.TrimSpace(c.ID)
	_, err := b.Acotado.EspejoGuardarCliente(ctx, sqlc.GuardarClienteDelEspejoParams{
		Source:         &fuente,
		ExternalID:     &id,
		Name:           c.Nombre,
		Phone:          textoONada(c.Telefono),
		Address:        textoONada(c.Direccion),
		Municipio:      textoONada(c.Municipio),
		Zona:           textoONada(c.Zona),
		Codigo:         textoONada(c.Codigo),
		Vendedor:       textoONada(nombreDelVendedor(c.Vendedor)),
		Lat:            *c.Latitud,
		Lng:            *c.Longitud,
		SucursalCodigo: textoONada(c.SucursalCodigo),
	})
	// SIN FILA NO ES UN FALLO: ES QUE NO HABÍA NADA QUE CAMBIAR.
	//
	// El upsert lleva desde el 26/09/2026 un `WHERE ... IS DISTINCT FROM ...` que evita
	// reescribir una fila idéntica — es lo que corta los 98 millones de actualizaciones
	// sobre 8.673 clientes—. Pero con ese `WHERE`, el `RETURNING` de una fila que no
	// cambia **no devuelve nada**, y la consulta es `:one`: sale `pgx.ErrNoRows`.
	//
	// Devolverlo tal cual convierte el caso NORMAL —un repaso en el que no cambió nada,
	// que es la inmensa mayoría de las vueltas— en un error por cliente, y el ciclo del
	// espejo se cae entero. O sea: la optimización habría tumbado la sincronización el
	// primer minuto. Aquí es donde se traduce a lo que de verdad significa.
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	return err
}

// QuitarPedidos: los que PEDIDO borró. Que no encuentre ninguno NO es un error — el stream
// entrega al menos una vez y el mismo aviso puede llegar dos veces.
func (b BaseDelReparto) QuitarPedidos(ctx context.Context, externalIDs []string) error {
	_, err := b.Acotado.QuitarPedidosDelEspejo(ctx, externalIDs)
	return err
}

// ApuntarTandaDeAvisos escribe la constancia en `recepciones_del_webhook`, la MISMA tabla
// que las tandas que entran por HTTP.
//
// Es a propósito: son dos caminos para lo mismo —enterarse de lo que cambió en PEDIDO— y
// tenerlos en dos tablas obligaría a mirar en dos sitios para responder «¿está entrando
// algo?». El `origen` los distingue.
func (b BaseDelReparto) ApuntarTandaDeAvisos(ctx context.Context, t TandaDeAvisos) error {
	return b.Acotado.ApuntarRecepcionDelWebhook(ctx, sqlc.ApuntarRecepcionDelWebhookParams{
		Origen:     "stream",
		Traidos:    int32(t.Traidos),
		Escritos:   int32(t.Atendidos),
		Rechazados: int32(t.SinEfecto),
		Motivos:    textoONada(t.Motivos),
		DuracionMs: int32(t.TardoMs),
	})
}

func (b BaseDelReparto) BorrarClientesQueYaNoVienen(ctx context.Context, ids []string) (int64, error) {
	return b.Acotado.EspejoBorrarClientesQueYaNoVienen(ctx, ids)
}

// ---------------------------------------------------------------------------
// Lo que necesita la factura como fuente (issue 20)
// ---------------------------------------------------------------------------

// BaseDeFacturas es la otra mitad de [Base] para `SYNC_FUENTE=factura|ambas`. Va aparte para que
// quien sólo trae PEDIDO no tenga que saber que existe.
type BaseDeFacturas interface {
	// PuntosDeClientes: los clientes geolocalizados del espejo de PEDIDO de una sucursal.
	PuntosDeClientes(ctx context.Context, sucursal string) ([]PuntoDeCliente, error)
	// ProductosDeVentra: peso y unidades por unidad de venta de una sucursal, por sku normalizado.
	ProductosDeVentra(ctx context.Context, sucursal string) (map[string]ProductoDeVentra, error)
	// EntregasDeFacturaEnVentana: las entregas de factura guardadas de una sucursal cuyo día de
	// factura cae en [desde, hasta].
	EntregasDeFacturaEnVentana(ctx context.Context, sucursal string, desde, hasta time.Time) ([]EntregaGuardada, error)
	// RetirarEntregasDeFactura borra las que se pidan, y SOLO las que no van en una ruta ni
	// tienen resultado (la guarda está también en el DELETE). Devuelve cuántas borró.
	RetirarEntregasDeFactura(ctx context.Context, ids []uuid.UUID) (int64, error)
}

// EntregaGuardada es una entrega de factura que ya está en la base. `Ocupada` es que va o fue
// en una ruta, o tiene resultado: eso no se retira nunca, porque ya está en el camión.
type EntregaGuardada struct {
	ID         uuid.UUID
	ExternalID string
	Ocupada    bool
}

func (b BaseDelReparto) PuntosDeClientes(ctx context.Context, sucursal string) ([]PuntoDeCliente, error) {
	filas, err := b.Acotado.EspejoPuntosDeClientes(ctx, sucursal)
	if err != nil {
		return nil, err
	}
	salida := make([]PuntoDeCliente, 0, len(filas))
	for _, f := range filas {
		c := PuntoDeCliente{Nombre: f.Name, Lat: f.Lat, Lng: f.Lng}
		if f.Codigo != nil {
			c.Codigo = *f.Codigo
		}
		salida = append(salida, c)
	}
	return salida, nil
}

func (b BaseDelReparto) ProductosDeVentra(ctx context.Context, sucursal string) (map[string]ProductoDeVentra, error) {
	filas, err := b.Acotado.EspejoPesosDeProductos(ctx, sucursal)
	if err != nil {
		return nil, err
	}
	salida := make(map[string]ProductoDeVentra, len(filas))
	for _, f := range filas {
		if f.Sku == nil {
			continue
		}
		p := ProductoDeVentra{Sku: *f.Sku, PesoKg: f.Weight}
		if f.UnitsPerPackage != nil {
			p.UnidadesPorEmpaque = *f.UnitsPerPackage
		}
		salida[claveDeProducto(*f.Sku)] = p
	}
	return salida, nil
}

func (b BaseDelReparto) EntregasDeFacturaEnVentana(
	ctx context.Context, sucursal string, desde, hasta time.Time,
) ([]EntregaGuardada, error) {
	filas, err := b.Acotado.EspejoEntregasDeFacturaEnVentana(ctx, sucursal, desde, hasta)
	if err != nil {
		return nil, err
	}
	salida := make([]EntregaGuardada, 0, len(filas))
	for _, f := range filas {
		g := EntregaGuardada{ID: f.ID, Ocupada: f.Ocupada}
		if f.ExternalID != nil {
			g.ExternalID = *f.ExternalID
		}
		salida = append(salida, g)
	}
	return salida, nil
}

func (b BaseDelReparto) RetirarEntregasDeFactura(ctx context.Context, ids []uuid.UUID) (int64, error) {
	return b.Acotado.EspejoRetirarEntregasDeFactura(ctx, ids)
}
