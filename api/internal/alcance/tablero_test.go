package alcance_test

// EL ALCANCE DE `alcance/tablero.go`, CONSULTA POR CONSULTA — Y AHORA SÍ TODAS.
//
// La cabecera decía «consulta por consulta» y no lo era: de las 26 apariciones de
// `Sucursal: a.sucursalPg()` del fichero, la tabla cubría 23. Las tres que faltaban eran
// las del ESPEJO —`EspejoListarRutas`, `EspejoDiferenciasDePedidos` y
// `EspejoPedidosQueSalieron`—, que son la bajada de las APK y no la pantalla, y por eso
// se colaron: se leyó «tablero» como «el tablero de la pantalla». Ya están abajo, y la
// tabla es la lista completa del fichero.
//
// Hasta el 18/09/2026 esto no lo probaba NADA. El auditor sustituyó las apariciones de
// `Sucursal: a.sucursalPg()` de `alcance/tablero.go` por `pgtype.UUID{}` —que es «todas
// las sucursales»— una por una, y la suite entera siguió en verde: ni una prueba roja.
//
// La razón es que las pruebas del tablero van contra un doble de la base que no miraba
// `arg.Sucursal`, así que el parámetro podía llegar vacío sin que se notara en la
// respuesta. Un doble que no mira el alcance no puede cazar una fuga de alcance.
//
// ESTO ES LA RED DE ABAJO, y es la que muere con el cambio de UNA línea: se llama a cada
// método de `Acotado` y se comprueba QUÉ SUCURSAL LLEGÓ a la consulta. No hay filas, ni
// columnas, ni pedidos — sólo el parámetro. Si alguien quita un narg, aquí sale rojo y con
// el nombre de la sucursal que se escapó.
//
// Importa de verdad porque hay CINCO endpoints que no reciben `branchId` ni pasan por
// `tableroDe`, y para ellos ese narg es la única defensa que existe:
//
//	PATCH  /api/board/columns/{id}
//	DELETE /api/board/columns/{id}
//	POST   /api/board/columns/{id}/route
//	PUT    /api/board/placements/{id}
//	DELETE /api/board/placements/{id}
//
// Y por las tres del espejo, donde es peor todavía: `GET /api/sync/cambios` se cree el
// `?sucursal=` que le manden (`sucursalDeLaBajada` lo devuelve tal cual), así que el narg
// es lo único que impide que un GESTOR de una sucursal se baje los pedidos de otra
// escribiendo el uuid en la barra del navegador. Es la regla dura del `CLAUDE.md` §4: el
// alcance sale de quién pregunta, no de lo que mande el cliente.
//
// Y la otra mitad de la regla, que también se prueba aquí: con `SUPER ADMIN` y
// `DESARROLLADOR` el narg tiene que llegar NULO, porque ésos sí ven las ocho. Un narg que
// se pusiera «siempre» dejaría a los dos de arriba sin ver nada.

import (
	"context"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/store/sqlc"
)

// ---------------------------------------------------------------------------
// El registrador: un doble que no devuelve datos, sólo apunta el alcance que le llegó
// ---------------------------------------------------------------------------
//
// Va sobre `querierFalso` para reaprovechar `ResolverSucursal`, que es lo que necesita la
// portería para resolver el alcance antes de nada.

type registrador struct {
	*querierFalso
	// visto es el `sucursal` de cada consulta que pasó por aquí. Se comprueba que haya
	// EXACTAMENTE uno: si una llamada no llega a la consulta, el caso está vacío y la
	// prueba lo dice, en vez de dar por buena una comprobación que no se hizo.
	visto []pgtype.UUID
}

func (q *registrador) apuntar(s pgtype.UUID) { q.visto = append(q.visto, s) }

// ObtenerSucursal es LA PRIMERA consulta del tablero y, desde el 22/09/2026, la que decide
// desde dónde se mide: de la fila que devuelve sale el `external_id` con el que
// `almacenDe` le pide a Accesos los almacenes de esa sucursal. Por eso se apunta aquí.
func (q *registrador) ObtenerSucursal(_ context.Context, arg sqlc.ObtenerSucursalParams) (sqlc.Branch, error) {
	q.apuntar(arg.Sucursal)
	return sqlc.Branch{ID: arg.ID}, nil
}

func (q *registrador) ListarColumnasDelTablero(_ context.Context, arg sqlc.ListarColumnasDelTableroParams) ([]sqlc.ListarColumnasDelTableroRow, error) {
	q.apuntar(arg.Sucursal)
	return nil, nil
}

func (q *registrador) ObtenerColumna(_ context.Context, arg sqlc.ObtenerColumnaParams) (sqlc.BoardColumn, error) {
	q.apuntar(arg.Sucursal)
	return sqlc.BoardColumn{}, nil
}

func (q *registrador) CrearColumna(_ context.Context, arg sqlc.CrearColumnaParams) (sqlc.CrearColumnaRow, error) {
	q.apuntar(arg.Sucursal)
	return sqlc.CrearColumnaRow{}, nil
}

func (q *registrador) ActualizarColumna(_ context.Context, arg sqlc.ActualizarColumnaParams) (sqlc.BoardColumn, error) {
	q.apuntar(arg.Sucursal)
	return sqlc.BoardColumn{}, nil
}

func (q *registrador) ReordenarColumnas(_ context.Context, arg sqlc.ReordenarColumnasParams) (int64, error) {
	q.apuntar(arg.Sucursal)
	return 0, nil
}

func (q *registrador) ContarPedidosEnColumna(_ context.Context, arg sqlc.ContarPedidosEnColumnaParams) (int64, error) {
	q.apuntar(arg.Sucursal)
	return 0, nil
}

func (q *registrador) VaciarColumna(_ context.Context, arg sqlc.VaciarColumnaParams) (int64, error) {
	q.apuntar(arg.Sucursal)
	return 0, nil
}

func (q *registrador) MoverPedidosDeColumna(_ context.Context, arg sqlc.MoverPedidosDeColumnaParams) (int64, error) {
	q.apuntar(arg.Sucursal)
	return 0, nil
}

func (q *registrador) BorrarColumna(_ context.Context, arg sqlc.BorrarColumnaParams) (int64, error) {
	q.apuntar(arg.Sucursal)
	return 0, nil
}

func (q *registrador) ListarPedidosColocados(_ context.Context, arg sqlc.ListarPedidosColocadosParams) ([]sqlc.ListarPedidosColocadosRow, error) {
	q.apuntar(arg.Sucursal)
	return nil, nil
}

func (q *registrador) AvisosDelTablero(_ context.Context, arg sqlc.AvisosDelTableroParams) (sqlc.AvisosDelTableroRow, error) {
	q.apuntar(arg.Sucursal)
	return sqlc.AvisosDelTableroRow{}, nil
}

func (q *registrador) ListarPedidosSinColocar(_ context.Context, arg sqlc.ListarPedidosSinColocarParams) ([]sqlc.ListarPedidosSinColocarRow, error) {
	q.apuntar(arg.Sucursal)
	return nil, nil
}

func (q *registrador) ContarPedidosSinColocar(_ context.Context, arg sqlc.ContarPedidosSinColocarParams) (int64, error) {
	q.apuntar(arg.Sucursal)
	return 0, nil
}

func (q *registrador) ColocarPedido(_ context.Context, arg sqlc.ColocarPedidoParams) (sqlc.ColocarPedidoRow, error) {
	q.apuntar(arg.Sucursal)
	return sqlc.ColocarPedidoRow{}, nil
}

func (q *registrador) AbrirHuecoEnColumna(_ context.Context, arg sqlc.AbrirHuecoEnColumnaParams) (int64, error) {
	q.apuntar(arg.Sucursal)
	return 0, nil
}

func (q *registrador) CerrarHuecoEnColumna(_ context.Context, arg sqlc.CerrarHuecoEnColumnaParams) (int64, error) {
	q.apuntar(arg.Sucursal)
	return 0, nil
}

func (q *registrador) QuitarPedidoDelTablero(_ context.Context, arg sqlc.QuitarPedidoDelTableroParams) (sqlc.QuitarPedidoDelTableroRow, error) {
	q.apuntar(arg.Sucursal)
	return sqlc.QuitarPedidoDelTableroRow{}, nil
}

func (q *registrador) PedidosDeColumnaParaArmarRuta(_ context.Context, arg sqlc.PedidosDeColumnaParaArmarRutaParams) ([]sqlc.PedidosDeColumnaParaArmarRutaRow, error) {
	q.apuntar(arg.Sucursal)
	return nil, nil
}

func (q *registrador) QuitarDelTableroLosDeRuta(_ context.Context, arg sqlc.QuitarDelTableroLosDeRutaParams) (int64, error) {
	q.apuntar(arg.Sucursal)
	return 0, nil
}

func (q *registrador) ListarOrigenes(_ context.Context, sucursal pgtype.UUID) ([]sqlc.ListarOrigenesRow, error) {
	q.apuntar(sucursal)
	return nil, nil
}

func (q *registrador) ObtenerPedido(_ context.Context, arg sqlc.ObtenerPedidoParams) (sqlc.ObtenerPedidoRow, error) {
	q.apuntar(arg.Sucursal)
	return sqlc.ObtenerPedidoRow{}, nil
}

func (q *registrador) EngancharPedidoARuta(_ context.Context, arg sqlc.EngancharPedidoARutaParams) (int64, error) {
	q.apuntar(arg.Sucursal)
	return 0, nil
}

func (q *registrador) FijarTotalesDeRuta(_ context.Context, arg sqlc.FijarTotalesDeRutaParams) (sqlc.FijarTotalesDeRutaRow, error) {
	q.apuntar(arg.Sucursal)
	return sqlc.FijarTotalesDeRutaRow{}, nil
}

// Las tres del ESPEJO — la bajada de las APK. No son del tablero de la pantalla, pero
// salen del mismo `Acotado` y llevan el mismo narg, y son las tres que se quedaron sin
// red hasta el 18/09/2026.

func (q *registrador) ListarRutas(_ context.Context, arg sqlc.ListarRutasParams) ([]sqlc.ListarRutasRow, error) {
	q.apuntar(arg.Sucursal)
	return nil, nil
}

func (q *registrador) DiferenciasDePedidos(_ context.Context, arg sqlc.DiferenciasDePedidosParams) ([]sqlc.DiferenciasDePedidosRow, error) {
	q.apuntar(arg.Sucursal)
	return nil, nil
}

func (q *registrador) BajasDeLaBajada(_ context.Context, arg sqlc.BajasDeLaBajadaParams) ([]sqlc.BajasDeLaBajadaRow, error) {
	q.apuntar(arg.Sucursal)
	return nil, nil
}

func (q *registrador) PedidosQueSalieronDelAlcance(_ context.Context, arg sqlc.PedidosQueSalieronDelAlcanceParams) ([]sqlc.PedidosQueSalieronDelAlcanceRow, error) {
	q.apuntar(arg.Sucursal)
	return nil, nil
}

// fuenteRegistradora es lo que `alcance` pide para poder consultar.
type fuenteRegistradora struct{ q *registrador }

func (f fuenteRegistradora) Consultas() sqlc.Querier { return f.q }
func (f fuenteRegistradora) EnTx(ctx context.Context, fn func(sqlc.Querier) error) error {
	return fn(f.q)
}

// ---------------------------------------------------------------------------
// La tabla: TODAS las consultas del tablero que llevan alcance
// ---------------------------------------------------------------------------
//
// LAS TRES QUE NO ESTÁN AQUÍ, y por qué no están, para que quede claro que faltan a
// propósito y no por olvido:
//
//   - `TableroVehiculoParaCapacidad` — la consulta no admite alcance. Lo acota quien
//     llama: `vehiculoDelCuerpo` resuelve el camión CON alcance, y `armarRutaDeColumna`
//     coteja además el `branch_id` que viene en la fila.
//   - `TableroContarRutasDelDia` — el `NNN` de `RT-YYYYMMDD-NNN` es de TODA la casa.
//     Numerar por sucursal daría dos rutas con el mismo código el mismo día.
//   - `TableroCrearRuta` — la ruta nace en la sucursal del TABLERO, que llega por
//     argumento: el Super Admin no tiene alcance y aun así arma la de la que mira.
var consultasDelTablero = []struct {
	nombre string
	llamar func(context.Context, *alcance.Acotado) error
}{
	// LA PRIMERA DE TODAS, y la que se quedó fuera de esta tabla hasta el 23/09/2026.
	//
	// `tableroDe` la llama con el `branchId` QUE MANDA EL CLIENTE, y con lo que devuelve
	// —su `external_id`— le pide a Accesos los almacenes de esa sucursal. Desde que el
	// origen sale de Accesos y no de `saved_origins`, este narg es lo ÚNICO que separa a
	// un logístico de Santiago del almacén de Holguín: quitarlo no rompe ninguna otra
	// consulta, porque todas reciben después el id ya «validado». Se pide LA DE AL LADO,
	// como las del espejo, que es la forma que caza la fuga.
	{"ObtenerSucursal", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.ObtenerSucursal(ctx, hol)
		return err
	}},
	{"ListarColumnasDelTablero", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.ListarColumnasDelTablero(ctx, stg)
		return err
	}},
	{"ObtenerColumna", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.ObtenerColumna(ctx, uuid.New())
		return err
	}},
	{"CrearColumna", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.CrearColumna(ctx, sqlc.CrearColumnaParams{Nombre: "Centro", BranchID: stg})
		return err
	}},
	{"ActualizarColumna", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.ActualizarColumna(ctx, sqlc.ActualizarColumnaParams{ID: uuid.New()})
		return err
	}},
	{"ReordenarColumnas", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.ReordenarColumnas(ctx, stg, []uuid.UUID{uuid.New()})
		return err
	}},
	{"ContarPedidosEnColumna", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.ContarPedidosEnColumna(ctx, uuid.New())
		return err
	}},
	{"VaciarColumna", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.VaciarColumna(ctx, uuid.New())
		return err
	}},
	{"MoverPedidosDeColumna", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.MoverPedidosDeColumna(ctx, uuid.New(), uuid.New())
		return err
	}},
	{"BorrarColumna", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.BorrarColumna(ctx, uuid.New())
		return err
	}},
	{"ListarPedidosColocados", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.ListarPedidosColocados(ctx, sqlc.ListarPedidosColocadosParams{BranchID: stg})
		return err
	}},
	{"AvisosDelTablero", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.AvisosDelTablero(ctx, stg)
		return err
	}},
	{"ListarPedidosSinColocar", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.ListarPedidosSinColocar(ctx, sqlc.ListarPedidosSinColocarParams{BranchID: stg, Limite: 10})
		return err
	}},
	{"ContarPedidosSinColocar", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.ContarPedidosSinColocar(ctx, sqlc.ContarPedidosSinColocarParams{BranchID: stg})
		return err
	}},
	{"ColocarPedido", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.ColocarPedido(ctx, sqlc.ColocarPedidoParams{PedidoID: uuid.New(), ColumnaID: uuid.New(), Posicion: 1})
		return err
	}},
	{"AbrirHuecoEnColumna", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.AbrirHuecoEnColumna(ctx, uuid.New(), 1)
		return err
	}},
	{"CerrarHuecoEnColumna", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.CerrarHuecoEnColumna(ctx, uuid.New(), 1)
		return err
	}},
	{"QuitarPedidoDelTablero", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.QuitarPedidoDelTablero(ctx, uuid.New())
		return err
	}},
	{"PedidosDeColumnaParaArmarRuta", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.PedidosDeColumnaParaArmarRuta(ctx, uuid.New())
		return err
	}},
	{"QuitarDelTableroLosDeRuta", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.QuitarDelTableroLosDeRuta(ctx, uuid.New())
		return err
	}},
	{"TableroObtenerPedido", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.TableroObtenerPedido(ctx, uuid.New())
		return err
	}},
	{"TableroEngancharPedidoARuta", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.TableroEngancharPedidoARuta(ctx, sqlc.EngancharPedidoARutaParams{PedidoID: uuid.New()})
		return err
	}},
	{"TableroFijarTotalesDeRuta", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.TableroFijarTotalesDeRuta(ctx, sqlc.FijarTotalesDeRutaParams{ID: uuid.New()})
		return err
	}},

	// -----------------------------------------------------------------------
	// Las tres del ESPEJO: la bajada de las APK, que es por donde peor duele
	// -----------------------------------------------------------------------
	//
	// `EspejoListarRutas` no tiene `BranchID`: el alcance es el ÚNICO filtro. Con el narg
	// vacío cada aparato se baja las rutas de las ocho sucursales.
	{"EspejoListarRutas", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.EspejoListarRutas(ctx)
		return err
	}},

	// Las dos de pedidos SÍ tienen `BranchID`, y ahí está la trampa: ese `BranchID` es
	// el `?sucursal=` DEL CLIENTE tal cual (`api/espejo.go`, `sucursalDeLaBajada`), que
	// lo devuelve sin comprobar nada porque «el alcance lo vuelve a aplicar dentro de
	// cada consulta». Si el narg se pierde, esa frase deja de ser verdad y un GESTOR de
	// Santiago que pida `GET /api/sync/cambios?sucursal=<Holguín>` se baja Holguín.
	// Por eso las dos se llaman aquí pidiendo LA SUCURSAL DE AL LADO.
	{"EspejoDiferenciasDePedidos", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.EspejoDiferenciasDePedidos(ctx, ventanaPidiendoHolguin())
		return err
	}},
	{"EspejoPedidosQueSalieron", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.EspejoPedidosQueSalieron(ctx, ventanaPidiendoHolguin())
		return err
	}},

	// Y LA CUARTA, de 00006: las lápidas de todo lo que no son pedidos. Misma trampa que
	// las dos de arriba y peor consecuencia, porque lo que viaja por aquí no es un dato
	// que se ve de más: es una orden de BORRAR. Sin el narg, a un GESTOR de Santiago que
	// pida `?sucursal=<Holguín>` se le manda quitar del teléfono las rutas de Holguín.
	{"EspejoBajas", func(ctx context.Context, a *alcance.Acotado) error {
		_, err := a.EspejoBajas(ctx, sqlc.ColeccionDeLaBajadaRoutes, ventanaPidiendoHolguin(), false)
		return err
	}},
}

// ventanaPidiendoHolguin: la bajada tal y como la arma `sucursalDeLaBajada` cuando en la
// URL viene `?sucursal=<Holguín>`. `Desde` puesto para que sea una bajada por diferencias
// y no la carga inicial, que es cuando se llaman las dos.
func ventanaPidiendoHolguin() alcance.VentanaDeBajada {
	desde := time.Now().Add(-time.Hour)
	ajena := hol
	return alcance.VentanaDeBajada{
		Desde:    &desde,
		Hasta:    time.Now(),
		Sucursal: &ajena, // lo que mandó el cliente; el alcance va aparte y en AND
		Tope:     100,
	}
}

func acotadoDe(t *testing.T, u *auth.Usuario) (*alcance.Acotado, *registrador) {
	t.Helper()
	q := &registrador{querierFalso: base()}
	p := alcance.NuevaPorteria(fuenteRegistradora{q: q}, registroMudo())
	a, err := p.Resolver(context.Background(), u, "")
	if err != nil {
		t.Fatalf("resolver el alcance de %q: %v", u.Rol, err)
	}
	return a, q
}

// NINGUNA CONSULTA DEL TABLERO SALE SIN SU SUCURSAL.
//
// Quitar un solo `Sucursal: a.sucursalPg()` de `alcance/tablero.go` pone esta prueba en
// rojo con el nombre de la consulta por la que se escapa Santiago.
func TestCadaConsultaDelTableroLlevaLaSucursalDeQuienPregunta(t *testing.T) {
	for _, c := range consultasDelTablero {
		t.Run(c.nombre, func(t *testing.T) {
			a, q := acotadoDe(t, &auth.Usuario{
				ID: "p-1", Rol: "OPERADOR", Sucursal: stg.String(),
			})
			if err := c.llamar(context.Background(), a); err != nil {
				t.Fatalf("%s: %v", c.nombre, err)
			}
			if len(q.visto) != 1 {
				t.Fatalf("%s: la consulta se llamó %d veces y tenía que ser UNA; "+
					"sin eso esta prueba no comprueba nada", c.nombre, len(q.visto))
			}
			s := q.visto[0]
			if !s.Valid {
				t.Fatalf("%s SALE SIN ALCANCE: le llegó «todas las sucursales» a un "+
					"OPERADOR de Santiago (%s).\n"+
					"Con el narg vacío esa consulta toca las OCHO sucursales.\n%s",
					c.nombre, stg, porQueDuele(c.nombre))
			}
			if uuid.UUID(s.Bytes) != stg {
				t.Fatalf("%s: le llegó la sucursal %s y la de quien pregunta es %s (Santiago)",
					c.nombre, uuid.UUID(s.Bytes), stg)
			}
		})
	}
}

// Y LA OTRA MITAD: con narg nulo NO se acota, y eso es lo correcto para los dos de arriba.
//
// `SUPER ADMIN` y `DESARROLLADOR` ven las ocho; los otros cinco roles son de UNA sucursal.
// Un narg que se pusiera «siempre» arreglaría la fuga dejando a los dos de arriba sin ver
// nada, que es el otro fallo, el que sí se nota en cuanto alguien abre la pantalla.
func TestLosDosDeArribaSiguenSinAcotarEnElTablero(t *testing.T) {
	for _, rol := range []string{"SUPER ADMIN", "DESARROLLADOR"} {
		for _, c := range consultasDelTablero {
			t.Run(rol+"/"+c.nombre, func(t *testing.T) {
				a, q := acotadoDe(t, &auth.Usuario{ID: "p-jefe", Rol: rol})
				if err := c.llamar(context.Background(), a); err != nil {
					t.Fatalf("%s: %v", c.nombre, err)
				}
				if len(q.visto) != 1 {
					t.Fatalf("%s: la consulta se llamó %d veces y tenía que ser UNA",
						c.nombre, len(q.visto))
				}
				if s := q.visto[0]; s.Valid {
					t.Fatalf("%s acotó a %s a un %s, que ve las OCHO sucursales",
						c.nombre, uuid.UUID(s.Bytes), rol)
				}
			})
		}
	}
}

// porQueDuele explica, EN EL MENSAJE DE LA PRUEBA, qué se escapa exactamente por esa
// consulta. Sin esto el rojo dice «falta un narg» y hay que abrir el código para saber si
// eso es grave; con esto dice a quién se le enseñan los datos de quién.
func porQueDuele(nombre string) string {
	switch nombre {
	case "ObtenerSucursal":
		return "Es la puerta del tablero: `tableroDe` la llama con el `branchId` que " +
			"manda el cliente y de la fila que devuelve saca el `external_id` con el " +
			"que `almacenDe` le pide a Accesos los almacenes. Sin narg, un OPERADOR de " +
			"Santiago que pida `GET /api/board?branchId=<uuid de Holguín>` se lleva el " +
			"tablero de Holguín MEDIDO DESDE EL ALMACÉN DE HOLGUÍN, con sus kilómetros " +
			"y todo: nada en la pantalla lo desmiente. CLAUDE.md §4."
	case "EspejoListarRutas":
		return "Aquí el alcance es el ÚNICO filtro: esta consulta no tiene `BranchID`. " +
			"Sin narg, CADA APARATO se baja en su sincronización las rutas de las ocho " +
			"sucursales."
	case "EspejoDiferenciasDePedidos", "EspejoPedidosQueSalieron", "EspejoBajas":
		return "Esta lleva además `BranchID`, pero ése es el `?sucursal=` DEL CLIENTE tal " +
			"cual (`api/espejo.go`, `sucursalDeLaBajada`), que no comprueba nada porque " +
			"da por hecho que el alcance se vuelve a aplicar aquí. Sin narg, un GESTOR " +
			"de Santiago que pida `GET /api/sync/cambios?sucursal=<uuid de Holguín>` se " +
			"baja los pedidos de Holguín. CLAUDE.md §4: el alcance sale de quién " +
			"pregunta, no de lo que mande el cliente."
	default:
		return "Hay cinco endpoints del tablero que no reciben `branchId` ni pasan por " +
			"`tableroDe` (PATCH/DELETE de columnas, POST .../route, PUT/DELETE de " +
			"placements): para ellos ese narg es la única defensa que existe."
	}
}

// registroMudo: las pruebas de esta tabla no miran el registro, sólo el parámetro.
func registroMudo() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}
