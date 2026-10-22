package alcance_test

import (
	"context"
	"errors"
	"log/slog"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/store/sqlc"
)

// UN PEDIDO QUE LLEGA IGUAL NO SE REESCRIBE — Y SUS RENGLONES SIGUEN ENCONTRÁNDOSE.
//
// La tercera pata del 36 % de CPU del Postgres, medida en producción el 26/09/2026:
//
//	orders   5.452 filas  ·  7.170.587 actualizaciones
//
// Mil trescientas veces cada pedido, casi siempre para dejarlo exactamente igual. Las
// otras dos patas —98 millones en `customers` y 8,8 en `order_items`— se cortaron el mismo
// día con la misma guarda.
//
// PERO AQUÍ HAY UNA TRAMPA QUE NO ESTABA EN LAS OTRAS DOS, y es lo que esta prueba sujeta:
// el upsert de pedidos devuelve el `id`, y **los renglones lo necesitan**. Con el `WHERE`,
// una fila que no cambia no devuelve nada: `pgx.ErrNoRows`.
//
// Las dos formas de equivocarse aquí, y las dos son caras:
//
//   - devolver el error tal cual → el caso NORMAL se convierte en un fallo por pedido y el
//     ciclo del espejo se cae entero;
//   - seguir con el `id` en cero → los renglones se escriben colgando de un uuid que no
//     existe, o se borran los de otro pedido. Eso no da error: da una hoja de despacho
//     equivocada.
//
// La salida es buscar el pedido por su referencia, que es el índice único.

var (
	elPedido   = uuid.MustParse("11111111-1111-1111-1111-111111111111")
	laSucursal = uuid.MustParse("22222222-2222-2222-2222-222222222222")
)

type baseDePedidos struct {
	sqlc.Querier

	// Qué contesta el upsert: `nil` = no cambió nada (ErrNoRows).
	cambio bool

	buscadoPorReferencia int
	renglonesLeidosDe    []uuid.UUID
	borradosDe           []uuid.UUID
	renglonesEscritos    []sqlc.CrearRenglonDePedidoParams
}

func (b *baseDePedidos) GuardarPedidoDelEspejo(
	context.Context, sqlc.GuardarPedidoDelEspejoParams,
) (sqlc.GuardarPedidoDelEspejoRow, error) {
	if !b.cambio {
		return sqlc.GuardarPedidoDelEspejoRow{}, pgx.ErrNoRows
	}
	return sqlc.GuardarPedidoDelEspejoRow{ID: elPedido, EsNuevo: false}, nil
}

func (b *baseDePedidos) BuscarPedidoPorReferencia(
	context.Context, sqlc.BuscarPedidoPorReferenciaParams,
) (sqlc.BuscarPedidoPorReferenciaRow, error) {
	b.buscadoPorReferencia++
	return sqlc.BuscarPedidoPorReferenciaRow{ID: elPedido}, nil
}

func (b *baseDePedidos) RenglonesDePedidoParaComparar(
	_ context.Context, id uuid.UUID,
) ([]sqlc.RenglonesDePedidoParaCompararRow, error) {
	b.renglonesLeidosDe = append(b.renglonesLeidosDe, id)
	// Lo que ya hay: un renglón, el mismo que va a llegar.
	return []sqlc.RenglonesDePedidoParaCompararRow{
		{Linea: 1, Description: "MALTA GUAJIRA 330 ML", Quantity: 60},
	}, nil
}

func (b *baseDePedidos) BorrarRenglonesDePedido(_ context.Context, id uuid.UUID) error {
	b.borradosDe = append(b.borradosDe, id)
	return nil
}

func (b *baseDePedidos) CrearRenglonDePedido(
	_ context.Context, p sqlc.CrearRenglonDePedidoParams,
) (sqlc.CrearRenglonDePedidoRow, error) {
	b.renglonesEscritos = append(b.renglonesEscritos, p)
	return sqlc.CrearRenglonDePedidoRow{}, nil
}

func elMismoRenglon() []sqlc.CrearRenglonDePedidoParams {
	return []sqlc.CrearRenglonDePedidoParams{
		{Linea: 1, Description: "MALTA GUAJIRA 330 ML", Quantity: 60},
	}
}

func otroRenglon() []sqlc.CrearRenglonDePedidoParams {
	return []sqlc.CrearRenglonDePedidoParams{
		{Linea: 1, Description: "MALTA GUAJIRA 330 ML", Quantity: 24},
	}
}

func guardarCon(t *testing.T, b *baseDePedidos, renglones []sqlc.CrearRenglonDePedidoParams) (uuid.UUID, bool, error) {
	t.Helper()
	p := alcance.NuevaPorteria(fuenteDePedidos{q: b}, slog.New(slog.DiscardHandler))
	a, err := p.Resolver(context.Background(), &auth.Usuario{
		ID: "servicio:espejo", Rol: "SUPER ADMIN",
	}, "")
	if err != nil {
		t.Fatalf("resolver el alcance: %v", err)
	}
	return a.EspejoGuardarPedido(context.Background(), sqlc.GuardarPedidoDelEspejoParams{
		BranchID: pgtype.UUID{Bytes: [16]byte(laSucursal), Valid: true},
	}, renglones)
}

// EL CASO NORMAL: no cambió nada. Ni error, ni id en cero, ni renglones reescritos.
func TestUnPedidoQueNoCambioNoEsUnFalloYConservaSuID(t *testing.T) {
	b := &baseDePedidos{cambio: false}

	id, nuevo, err := guardarCon(t, b, elMismoRenglon())

	if err != nil {
		t.Fatalf(
			"un repaso en el que no cambió nada es el caso NORMAL y sale como error: "+
				"así el ciclo del espejo se cae entero. Salió: %v", err,
		)
	}
	if id != elPedido {
		t.Fatalf(
			"se perdió el id del pedido: los renglones se escribirían colgando de un "+
				"uuid que no existe y la hoja de despacho saldría equivocada SIN dar "+
				"error. Salió: %v", id,
		)
	}
	if nuevo {
		t.Fatalf("un pedido que no cambió no acaba de nacer")
	}
	if b.buscadoPorReferencia != 1 {
		t.Fatalf("no se buscó el id por su referencia: %d", b.buscadoPorReferencia)
	}
	if len(b.borradosDe) != 0 || len(b.renglonesEscritos) != 0 {
		t.Fatalf(
			"los renglones se reescribieron aunque son los mismos: borrados=%d escritos=%d",
			len(b.borradosDe), len(b.renglonesEscritos),
		)
	}
}

// LA OTRA MITAD: cuando SÍ cambió, se escribe. Sin esto, «no reescribir» se cumple no
// escribiendo nunca, y el reparto se queda con la foto del primer día.
func TestUnPedidoQueSiCambioSeEscribe(t *testing.T) {
	b := &baseDePedidos{cambio: true}

	id, _, err := guardarCon(t, b, otroRenglon())

	if err != nil {
		t.Fatal(err)
	}
	if id != elPedido {
		t.Fatalf("id equivocado: %v", id)
	}
	if b.buscadoPorReferencia != 0 {
		t.Fatalf("se buscó por referencia sin hacer falta: el upsert ya dio el id")
	}
	if len(b.borradosDe) != 1 || len(b.renglonesEscritos) != 1 {
		t.Fatalf(
			"los renglones cambiaron y NO se reescribieron: el despacho prepararía lo "+
				"que el cliente ya no pidió. borrados=%d escritos=%d",
			len(b.borradosDe), len(b.renglonesEscritos),
		)
	}
	// Y el `pedido_id` lo pone este método, no quien llama.
	if b.renglonesEscritos[0].PedidoID != elPedido {
		t.Fatalf("el renglón se escribió colgando de otro pedido: %v",
			b.renglonesEscritos[0].PedidoID)
	}
}

// Y UN FALLO DE VERDAD SIGUE SIENDO UN FALLO. Sin esto, «ErrNoRows no es error» se cumple
// tragándose todos, y una base caída se come el lote entero en silencio.
func TestUnFalloDeLaBaseAlGuardarElPedidoSIGUESIENDOUNFALLO(t *testing.T) {
	b := &baseQueRevienta{}

	_, _, err := guardarCon(t, &baseDePedidos{}, elMismoRenglon())
	_ = err // el de arriba es el caso bueno; el de abajo es el que importa

	p := alcance.NuevaPorteria(fuenteDePedidos{q: b}, slog.New(slog.DiscardHandler))
	a, errA := p.Resolver(context.Background(), &auth.Usuario{
		ID: "servicio:espejo", Rol: "SUPER ADMIN",
	}, "")
	if errA != nil {
		t.Fatal(errA)
	}
	_, _, err = a.EspejoGuardarPedido(context.Background(),
		sqlc.GuardarPedidoDelEspejoParams{}, elMismoRenglon())

	if !errors.Is(err, errLaBaseSeCayo) {
		t.Fatalf("una base caída se tragó el pedido en silencio: %v", err)
	}
}

var errLaBaseSeCayo = errors.New("connection reset by peer")

type baseQueRevienta struct{ sqlc.Querier }

func (b *baseQueRevienta) GuardarPedidoDelEspejo(
	context.Context, sqlc.GuardarPedidoDelEspejoParams,
) (sqlc.GuardarPedidoDelEspejoRow, error) {
	return sqlc.GuardarPedidoDelEspejoRow{}, errLaBaseSeCayo
}

type fuenteDePedidos struct{ q sqlc.Querier }

func (f fuenteDePedidos) Consultas() sqlc.Querier { return f.q }
func (f fuenteDePedidos) EnTx(ctx context.Context, fn func(sqlc.Querier) error) error {
	return fn(f.q)
}

// UN RENGLÓN QUE SÓLO CAMBIA DE ALMACÉN SÍ SE REESCRIBE — 26/09/2026.
//
// La migración 00012 añadió `order_items.almacen_salida_codigo` y `almacen_salida_nombre`: de
// qué almacén sale cada línea. La guarda de arriba —«si los renglones son los mismos, no se toca
// nada»— compara campo a campo, así que una columna nueva que no entre en esa comparación deja
// un agujero con una forma muy concreta: **el renglón se lee como «no cambió» y la columna se
// queda con el primer valor para siempre**, en silencio.
//
// Y ESE CASO PASA DE VERDAD, no es hipotético: un pedido entra al reparto ANTES de facturarse,
// así que llega sin almacén; cuando PEDIDO lo cierra contra la factura llega ya con el suyo, con
// el mismo producto, la misma cantidad y el mismo peso. Sin esto, el pedido de AURORA se quedaría
// apuntado como «no se sabe de dónde sale» hasta que alguien le cambiara además la cantidad.
//
// LA PAREJA COMPLETA, y la segunda mitad es la que evita el arreglo fácil: comparar de más
// —devolver «distinto» siempre— corta el agujero y devuelve los 8,8 millones de escrituras que
// la guarda vino a quitar. Las dos tienen que valer.
func TestUnRenglonQueSoloCambiaDeAlmacenSeReescribe(t *testing.T) {
	aurora, nombre := "2", "AURORA"

	casos := []struct {
		nombre      string
		renglones   []sqlc.CrearRenglonDePedidoParams
		seReescribe bool
		porQue      string
	}{
		{
			nombre: "el mismo renglón con el almacén puesto SÍ se reescribe",
			renglones: []sqlc.CrearRenglonDePedidoParams{{
				Linea: 1, Description: "MALTA GUAJIRA 330 ML", Quantity: 60,
				AlmacenSalidaCodigo: &aurora, AlmacenSalidaNombre: &nombre,
			}},
			seReescribe: true,
			porQue: "es lo que pasa cuando llega la factura: mismo producto, misma cantidad, " +
				"mismo peso, y por fin se sabe de qué almacén sale",
		},
		{
			nombre:      "y el mismo renglón SIN nada nuevo NO se reescribe",
			renglones:   elMismoRenglon(),
			seReescribe: false,
			porQue: "sin esta mitad, «compara el almacén» se cumple devolviendo «distinto» " +
				"siempre, y vuelven los 8,8 millones de escrituras sobre 7.450 filas",
		},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			b := &baseDePedidos{cambio: false}
			if _, _, err := guardarCon(t, b, c.renglones); err != nil {
				t.Fatalf("guardar: %v", err)
			}
			if c.seReescribe && len(b.borradosDe) == 0 {
				t.Fatalf("el renglón cambió de almacén y NO se reescribió: la columna se queda "+
					"con el primer valor para siempre y en silencio\n  por qué importa: %s", c.porQue)
			}
			if !c.seReescribe && len(b.borradosDe) != 0 {
				t.Fatalf("el renglón era idéntico y se reescribió igual\n  por qué importa: %s",
					c.porQue)
			}
		})
	}
}

// LA FACTURA DEL RENGLÓN ENTRA EN LA COMPARACIÓN (00026, issue 22 de Maikel). Los renglones de
// las entregas de factura escritos antes de la 00026 no tienen la suya: si la comparación no
// la mirara, el mismo producto con la misma cantidad parecería «no cambió nada» y se quedarían
// sin factura para siempre. La pareja es la de siempre: el mismo renglón SIN novedad no se
// reescribe.
func TestUnRenglonQueSoloGanaSuFacturaSeReescribe(t *testing.T) {
	factura := "47359"
	b := &baseDePedidos{cambio: false}
	conFactura := []sqlc.CrearRenglonDePedidoParams{{
		Linea: 1, Description: "MALTA GUAJIRA 330 ML", Quantity: 60, FacturaNumero: &factura,
	}}
	if _, _, err := guardarCon(t, b, conFactura); err != nil {
		t.Fatalf("guardar: %v", err)
	}
	if len(b.borradosDe) == 0 {
		t.Fatal("el renglón ganó su factura y NO se reescribió: se quedaría sin ella para siempre")
	}

	b = &baseDePedidos{cambio: false}
	if _, _, err := guardarCon(t, b, elMismoRenglon()); err != nil {
		t.Fatalf("guardar: %v", err)
	}
	if len(b.borradosDe) != 0 {
		t.Fatal("el renglón era idéntico (sin factura en los dos lados) y se reescribió igual")
	}
}
