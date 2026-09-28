package alcance

// LA PUERTA A LAS CONSULTAS.
//
// Cada consulta con alcance se expone aquí como un método de `Acotado`, y es ESTE fichero
// —no el manejador— quien rellena el parámetro `sucursal`. Lo que traiga el manejador en
// ese campo se pisa sin preguntar: un alcance que se pueda pasar desde fuera no es un
// alcance, es una sugerencia.
//
// PARA AÑADIR UN RECURSO (pedidos, rutas, clientes, productos...):
//
//  1. Añade aquí el método, copiando el de al lado. Pon el parámetro de sucursal con
//     `a.sucursalPg()` y no lo aceptes como argumento.
//  2. Si la consulta NO lleva alcance, va en la sección de abajo, con un comentario que
//     diga POR QUÉ no lo lleva. Sin ese porqué no se acepta: lo global se justifica, no
//     se supone.
//  3. El manejador recibe `*alcance.Acotado` y nunca un `sqlc.Querier`. Si un manejador
//     necesita el Querier pelado, es que la consulta que le falta hay que añadirla aquí.

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

// ---------------------------------------------------------------------------
// Sucursales
// ---------------------------------------------------------------------------

// ListarSucursalesVisibles: «a cuáles puedo llegar», que depende sólo de la persona y no
// de la que tenga elegida arriba. Ver `personaPg`.
func (a *Acotado) ListarSucursalesVisibles(ctx context.Context) ([]sqlc.ListarSucursalesRow, error) {
	return a.q.ListarSucursales(ctx, a.personaPg())
}

// BuscarSucursalPorCodigo traduce el código de Accesos (`CAM`, `HOL`…) a NUESTRO id.
//
// NO LLEVA ALCANCE, y es lo correcto: es la misma consulta que usa `Porteria.Resolver`
// para saber QUÉ acotar, así que acotarla con lo que todavía no se ha resuelto sería una
// pescadilla. Lo que devuelve —el id, el nombre y el código de una sucursal— no es dato
// de nadie: la lista entera ya la da `/api/branches` a cualquiera con sesión.
func (a *Acotado) BuscarSucursalPorCodigo(ctx context.Context, codigo string) (sqlc.BuscarSucursalPorCodigoRow, error) {
	return a.q.BuscarSucursalPorCodigo(ctx, &codigo)
}

func (a *Acotado) ObtenerSucursal(ctx context.Context, id uuid.UUID) (sqlc.Branch, error) {
	return a.q.ObtenerSucursal(ctx, sqlc.ObtenerSucursalParams{ID: id, Sucursal: a.sucursalPg()})
}

// CrearSucursal NO lleva alcance, y es lo correcto: una sucursal que todavía no existe no
// puede pertenecer a ninguna. La puerta aquí es el rol —sólo administradores—, y eso lo
// pone el router con `auth.ExigirAdmin`.
func (a *Acotado) CrearSucursal(ctx context.Context, arg sqlc.CrearSucursalParams) (sqlc.Branch, error) {
	arg.CreadoPor = a.ActorRef() // constancia de quién la dio de alta. NO filtra nada.
	return a.q.CrearSucursal(ctx, arg)
}

func (a *Acotado) ActualizarSucursal(ctx context.Context, arg sqlc.ActualizarSucursalParams) (sqlc.Branch, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.ActualizarSucursal(ctx, arg)
}

func (a *Acotado) BorrarSucursal(ctx context.Context, id uuid.UUID) (int64, error) {
	return a.q.BorrarSucursal(ctx, sqlc.BorrarSucursalParams{ID: id, Sucursal: a.sucursalPg()})
}

// ContarOrigenesDeSucursal se pregunta de la sucursal que se acaba de tocar, no de la del
// alcance: se usa para decidir si hay que crearle el punto de partida por defecto. El
// alcance ya lo dio por bueno el UPDATE de arriba, que no devolvió fila si no tocaba.
func (a *Acotado) ContarOrigenesDeSucursal(ctx context.Context, sucursal uuid.UUID) (int64, error) {
	return a.q.ContarOrigenesDeSucursal(ctx, aPg(&sucursal))
}

func (a *Acotado) CrearOrigen(ctx context.Context, arg sqlc.CrearOrigenParams) (sqlc.SavedOrigin, error) {
	arg.CreadoPor = a.ActorRef()
	return a.q.CrearOrigen(ctx, arg)
}

// ---------------------------------------------------------------------------
// Vehículos
// ---------------------------------------------------------------------------
//
// OJO con la forma del filtro de vehículos: deja pasar también los de `branch_id` NULL,
// que significan «de todas las sucursales». Eso va en el SQL (`db/queries/vehicles.sql`)
// y no aquí. Un camión compartido que no salga en la lista de nadie es un camión que no
// se puede usar.

func (a *Acotado) ListarVehiculos(ctx context.Context) ([]sqlc.ListarVehiculosRow, error) {
	return a.q.ListarVehiculos(ctx, a.sucursalPg())
}

// RutasAbiertasDeLaFlota: en qué anda cada camión, DEDUCIDO de sus rutas.
//
// Se acota por la sucursal de la RUTA y no por la del camión, igual que
// `ContarVehiculosEnRuta`: un camión compartido (`branch_id` nulo) sale en la lista de
// todas, pero la ruta que lleva es de UNA, y decirle a Holguín que su camión compartido
// está en ruta cuando quien lo tiene es Santiago sería contar el trabajo de otro.
func (a *Acotado) RutasAbiertasDeLaFlota(ctx context.Context) ([]sqlc.RutasAbiertasDeLaFlotaRow, error) {
	return a.q.RutasAbiertasDeLaFlota(ctx, a.sucursalPg())
}

func (a *Acotado) ObtenerVehiculo(ctx context.Context, id uuid.UUID) (sqlc.ObtenerVehiculoRow, error) {
	return a.q.ObtenerVehiculo(ctx, sqlc.ObtenerVehiculoParams{ID: id, Sucursal: a.sucursalPg()})
}

// CrearVehiculo: el camión NACE en la sucursal del alcance. Quien no tiene alcance —el
// Super Admin— lo deja sin sucursal, que quiere decir «de todas».
func (a *Acotado) CrearVehiculo(ctx context.Context, arg sqlc.CrearVehiculoParams) (sqlc.Vehicle, error) {
	arg.BranchID = a.sucursalPg()
	return a.q.CrearVehiculo(ctx, arg)
}

func (a *Acotado) ActualizarVehiculo(ctx context.Context, arg sqlc.ActualizarVehiculoParams) (sqlc.Vehicle, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.ActualizarVehiculo(ctx, arg)
}

func (a *Acotado) BorrarVehiculo(ctx context.Context, id uuid.UUID) (int64, error) {
	return a.q.BorrarVehiculo(ctx, sqlc.BorrarVehiculoParams{ID: id, Sucursal: a.sucursalPg()})
}

// DesmarcarReferenciaDeDomicilio desmarca los demás camiones de referencia DE ESTA
// SUCURSAL. Va siempre en la misma transacción que el marcado, o el índice único parcial
// `vehicles_una_referencia_por_sucursal` rechaza el segundo.
func (a *Acotado) DesmarcarReferenciaDeDomicilio(ctx context.Context, exceptoID uuid.UUID) (int64, error) {
	return a.q.DesmarcarReferenciaDeDomicilio(ctx, sqlc.DesmarcarReferenciaDeDomicilioParams{
		ExceptoID: exceptoID,
		Sucursal:  a.sucursalPg(),
	})
}

func (a *Acotado) DesvincularVehiculoDePedidos(ctx context.Context, vehiculo uuid.UUID) (int64, error) {
	return a.q.DesvincularVehiculoDePedidos(ctx, sqlc.DesvincularVehiculoDePedidosParams{
		VehiculoID: aPg(&vehiculo),
		Sucursal:   a.sucursalPg(),
	})
}

func (a *Acotado) DesvincularVehiculoDeRutas(ctx context.Context, vehiculo uuid.UUID) (int64, error) {
	return a.q.DesvincularVehiculoDeRutas(ctx, sqlc.DesvincularVehiculoDeRutasParams{
		VehiculoID: aPg(&vehiculo),
		Sucursal:   a.sucursalPg(),
	})
}

func (a *Acotado) CompletarRutasDeVehiculo(ctx context.Context, vehiculo uuid.UUID) (int64, error) {
	return a.q.CompletarRutasDeVehiculo(ctx, sqlc.CompletarRutasDeVehiculoParams{
		VehiculoID: aPg(&vehiculo),
		Sucursal:   a.sucursalPg(),
	})
}

// BorrarAsignacionesDeVehiculo no lleva sucursal porque `order_vehicles` no tiene esa
// columna. El alcance ya se comprobó antes: sólo se llama con un vehículo que el UPDATE
// o el SELECT acotado devolvió como propio.
func (a *Acotado) BorrarAsignacionesDeVehiculo(ctx context.Context, vehiculo uuid.UUID) (int64, error) {
	return a.q.BorrarAsignacionesDeVehiculo(ctx, vehiculo)
}

// ---------------------------------------------------------------------------
// SIN ALCANCE, a propósito
// ---------------------------------------------------------------------------
//
// Lo de abajo es GLOBAL de la empresa y ninguna de estas tablas tiene columna de sucursal
// que filtrar. No es un olvido; está escrito en el esquema y repetido aquí porque es
// justo lo que hay que mirar dos veces cuando se revisa la seguridad.

// Tipos de vehículo: un «camión» es un camión en las ocho sucursales. Lo que sí es por
// sucursal es qué VEHÍCULO concreto es el de referencia, y eso vive en `vehicles`.
func (a *Acotado) ListarTiposDeVehiculo(ctx context.Context, soloActivos *bool) ([]sqlc.ListarTiposDeVehiculoRow, error) {
	return a.q.ListarTiposDeVehiculo(ctx, soloActivos)
}

func (a *Acotado) ObtenerTipoDeVehiculo(ctx context.Context, id uuid.UUID) (sqlc.VehicleType, error) {
	return a.q.ObtenerTipoDeVehiculo(ctx, id)
}

func (a *Acotado) BuscarTipoDeVehiculoPorNombre(ctx context.Context, nombre string) (sqlc.BuscarTipoDeVehiculoPorNombreRow, error) {
	return a.q.BuscarTipoDeVehiculoPorNombre(ctx, nombre)
}

func (a *Acotado) CrearTipoDeVehiculo(ctx context.Context, arg sqlc.CrearTipoDeVehiculoParams) (sqlc.VehicleType, error) {
	return a.q.CrearTipoDeVehiculo(ctx, arg)
}

func (a *Acotado) ActualizarTipoDeVehiculo(ctx context.Context, arg sqlc.ActualizarTipoDeVehiculoParams) (sqlc.VehicleType, error) {
	return a.q.ActualizarTipoDeVehiculo(ctx, arg)
}

func (a *Acotado) RetirarTipoDeVehiculo(ctx context.Context, id uuid.UUID) (int64, error) {
	return a.q.RetirarTipoDeVehiculo(ctx, id)
}

func (a *Acotado) BorrarTipoDeVehiculoSinUso(ctx context.Context, id uuid.UUID) (int64, error) {
	return a.q.BorrarTipoDeVehiculoSinUso(ctx, id)
}

// Ajustes y monedas: son de toda la empresa. La tasa POR SUCURSAL es otra cosa y vive en
// Accesos, no aquí.
func (a *Acotado) ObtenerAjustes(ctx context.Context) (sqlc.Setting, error) {
	return a.q.ObtenerAjustes(ctx)
}

func (a *Acotado) ActualizarAjustes(ctx context.Context, arg sqlc.ActualizarAjustesParams) (sqlc.Setting, error) {
	return a.q.ActualizarAjustes(ctx, arg)
}

func (a *Acotado) ListarMonedas(ctx context.Context, soloActivas *bool) ([]sqlc.Currency, error) {
	return a.q.ListarMonedas(ctx, soloActivas)
}

func (a *Acotado) GuardarMoneda(ctx context.Context, arg sqlc.GuardarMonedaParams) (sqlc.Currency, error) {
	return a.q.GuardarMoneda(ctx, arg)
}

func (a *Acotado) DesactivarMoneda(ctx context.Context, code string) (int64, error) {
	return a.q.DesactivarMoneda(ctx, code)
}

// ---------------------------------------------------------------------------
// Pedidos
// ---------------------------------------------------------------------------
//
// Todas llevan `a.sucursalPg()` puesto AQUÍ y ninguna acepta la sucursal como argumento.
// Es la regla del fichero, y en pedidos es la que más pesa: los 3.528 pedidos importados
// de delivery quedaron a nombre de quien los dio de alta, y por eso Holguín no veía lo de
// Holguín. El único campo que decide es `branch_id`, y lo rellena este fichero.

func (a *Acotado) ListarPedidos(ctx context.Context, arg sqlc.ListarPedidosParams) ([]sqlc.ListarPedidosRow, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.ListarPedidos(ctx, arg)
}

// ContarPedidos va con los MISMOS filtros que ListarPedidos. Si alguna vez se llaman con
// argumentos distintos, el contador dice una cosa y la tabla otra, y nadie sabe cuál
// creerse: pasó con el «358» sobre una tabla vacía.
func (a *Acotado) ContarPedidos(ctx context.Context, arg sqlc.ContarPedidosParams) (int64, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.ContarPedidos(ctx, arg)
}

func (a *Acotado) ListarPedidosDisponibles(ctx context.Context, arg sqlc.ListarPedidosDisponiblesParams) ([]sqlc.ListarPedidosDisponiblesRow, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.ListarPedidosDisponibles(ctx, arg)
}

func (a *Acotado) ContarPedidosDisponibles(ctx context.Context, arg sqlc.ContarPedidosDisponiblesParams) (int64, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.ContarPedidosDisponibles(ctx, arg)
}

func (a *Acotado) ObtenerPedido(ctx context.Context, id uuid.UUID) (sqlc.ObtenerPedidoRow, error) {
	return a.q.ObtenerPedido(ctx, sqlc.ObtenerPedidoParams{ID: id, Sucursal: a.sucursalPg()})
}

func (a *Acotado) ActualizarPedido(ctx context.Context, arg sqlc.ActualizarPedidoParams) (sqlc.ActualizarPedidoRow, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.ActualizarPedido(ctx, arg)
}

func (a *Acotado) BorrarPedido(ctx context.Context, id uuid.UUID) (int64, error) {
	return a.q.BorrarPedido(ctx, sqlc.BorrarPedidoParams{ID: id, Sucursal: a.sucursalPg()})
}

// Los renglones también van acotados aunque el id del pedido salga de una consulta que ya
// lo estaba: el id llega de fuera en `/api/orders/{id}`, y sin este filtro bastaría con
// acertar un uuid para leer qué mercancía lleva un cliente de otra sucursal.
func (a *Acotado) ListarRenglonesDePedido(ctx context.Context, pedido uuid.UUID) ([]sqlc.ListarRenglonesDePedidoRow, error) {
	return a.q.ListarRenglonesDePedido(ctx, sqlc.ListarRenglonesDePedidoParams{
		PedidoID: pedido,
		Sucursal: a.sucursalPg(),
	})
}

func (a *Acotado) ListarRenglonesDePedidos(ctx context.Context, pedidos []uuid.UUID) ([]sqlc.ListarRenglonesDePedidosRow, error) {
	return a.q.ListarRenglonesDePedidos(ctx, sqlc.ListarRenglonesDePedidosParams{
		PedidoIds: pedidos,
		Sucursal:  a.sucursalPg(),
	})
}

func (a *Acotado) ResumenPreDespacho(ctx context.Context, pedidos []uuid.UUID) ([]sqlc.ResumenPreDespachoRow, error) {
	return a.q.ResumenPreDespacho(ctx, sqlc.ResumenPreDespachoParams{
		PedidoIds: pedidos,
		Sucursal:  a.sucursalPg(),
	})
}

// Las facetas llenan los desplegables del catálogo, así que se acotan igual que la lista:
// ofrecer un municipio o un vendedor de otra sucursal ya cuenta lo que hay allí, aunque
// al elegirlo no salga ni un pedido.
func (a *Acotado) FacetasMunicipios(ctx context.Context) ([]sqlc.FacetasMunicipiosRow, error) {
	return a.q.FacetasMunicipios(ctx, a.sucursalPg())
}

func (a *Acotado) FacetasVendedores(ctx context.Context) ([]sqlc.FacetasVendedoresRow, error) {
	return a.q.FacetasVendedores(ctx, a.sucursalPg())
}

func (a *Acotado) FacetasSucursales(ctx context.Context) ([]sqlc.FacetasSucursalesRow, error) {
	return a.q.FacetasSucursales(ctx, a.sucursalPg())
}

// --- El repaso de pesos: SIN alcance, y aquí está el porqué -----------------
//
// `POST /api/orders/recompute-weights` entra con clave de servicio y no con una persona:
// es una faena de mantenimiento sobre el espejo ENTERO, las ocho sucursales de una vez.
// Acotarla por sucursal dejaría a siete con el peso viejo y sin una sola traza que lo
// dijera. El universo lo decide `source`, no `branch_id`, y por eso estas tres no llevan
// `a.sucursalPg()`.

func (a *Acotado) PesosDelCatalogoPorFuente(ctx context.Context, fuente sqlc.Procedencia) ([]sqlc.PesosDelCatalogoPorFuenteRow, error) {
	return a.q.PesosDelCatalogoPorFuente(ctx, fuente)
}

func (a *Acotado) RenglonesSinPesoPorFuente(ctx context.Context, fuente sqlc.Procedencia) ([]sqlc.RenglonesSinPesoPorFuenteRow, error) {
	return a.q.RenglonesSinPesoPorFuente(ctx, fuente)
}

func (a *Acotado) ActualizarPesoDePedido(ctx context.Context, arg sqlc.ActualizarPesoDePedidoParams) error {
	return a.q.ActualizarPesoDePedido(ctx, arg)
}

// ---------------------------------------------------------------------------
// Clientes
// ---------------------------------------------------------------------------
//
// AQUÍ EL ALCANCE VA POR CÓDIGO, NO POR uuid. `customers` no tiene `branch_id`: tiene
// `sucursal_codigo`, que es el código de Ventra (CAM, HAB, STG...). La traducción la hace
// `Codigo()`, que la Porteria rellenó al resolver la sucursal.
//
// Y si la sucursal del alcance NO tiene `external_id`, `Codigo()` es nil y se pasa NULL,
// que es lo correcto: meter el uuid donde va un código no da error, DA CERO CLIENTES. Un
// 200 con la lista vacía es indistinguible de «esta sucursal todavía no tiene nadie».

func (a *Acotado) ListarClientes(ctx context.Context, arg sqlc.ListarClientesParams) ([]sqlc.ListarClientesRow, error) {
	arg.SucursalDelAlcance = a.Codigo()
	return a.q.ListarClientes(ctx, arg)
}

// ContarClientes usa el MISMO where que la lista. Es el `total` de la respuesta y se
// cuenta antes del filtro de distancia exacto, así que puede ser mayor que `count`.
func (a *Acotado) ContarClientes(ctx context.Context, arg sqlc.ContarClientesParams) (int64, error) {
	arg.SucursalDelAlcance = a.Codigo()
	return a.q.ContarClientes(ctx, arg)
}

// Las facetas van con el alcance y SIN los filtros de búsqueda: los desplegables tienen
// que seguir ofreciendo a dónde ir después de filtrar.
func (a *Acotado) FacetasClientesMunicipios(ctx context.Context) ([]sqlc.FacetasClientesMunicipiosRow, error) {
	return a.q.FacetasClientesMunicipios(ctx, a.Codigo())
}

func (a *Acotado) FacetasClientesZonas(ctx context.Context) ([]sqlc.FacetasClientesZonasRow, error) {
	return a.q.FacetasClientesZonas(ctx, a.Codigo())
}

func (a *Acotado) FacetasClientesVendedores(ctx context.Context) ([]sqlc.FacetasClientesVendedoresRow, error) {
	return a.q.FacetasClientesVendedores(ctx, a.Codigo())
}

func (a *Acotado) FacetasClientesSucursales(ctx context.Context) ([]sqlc.FacetasClientesSucursalesRow, error) {
	return a.q.FacetasClientesSucursales(ctx, a.Codigo())
}

func (a *Acotado) ContarClientesSinTelefono(ctx context.Context) (int64, error) {
	return a.q.ContarClientesSinTelefono(ctx, a.Codigo())
}

// ---------------------------------------------------------------------------
// Productos (catálogo)
// ---------------------------------------------------------------------------
//
// El catálogo TAMBIÉN se acota por código, y aquí importa más que en ningún otro sitio:
// el PRECIO y las EXISTENCIAS de un producto son de su sucursal. Enseñar el catálogo de
// otra no es sólo ver de más, es cotizar con un precio que allí no se cobra.

// codigoAcotado decide entre el código del alcance y el que pidieron en la query.
//
// MANDA EL DEL ALCANCE. El de la query sólo sirve cuando no hay alcance —el Super Admin
// mirando «todas», que arma un pedido para una sucursal concreta—. Al revés, un operador
// de Santiago vería el catálogo de La Habana escribiendo `?sucursal=HAB` en la barra del
// navegador, que es la misma línea que en delivery dejaba pasar: allí el parámetro tenía
// prioridad SOBRE el alcance.
func (a *Acotado) codigoAcotado(pedido *string) *string {
	if a.codigo != nil {
		return a.codigo
	}
	return pedido
}

func (a *Acotado) ListarProductos(ctx context.Context, arg sqlc.ListarProductosParams) ([]sqlc.Product, error) {
	arg.Sucursal = a.codigoAcotado(arg.Sucursal)
	return a.q.ListarProductos(ctx, arg)
}

// ObtenerProductoDelAlcance es la del GET de la ficha: acotada por código.
func (a *Acotado) ObtenerProductoDelAlcance(ctx context.Context, id uuid.UUID, pedido *string) (sqlc.Product, error) {
	return a.q.ObtenerProductoDelAlcance(ctx, sqlc.ObtenerProductoDelAlcanceParams{
		ID: id, Sucursal: a.codigoAcotado(pedido),
	})
}

// UsoDeProductos cuenta sobre los pedidos DEL ALCANCE, y ésos sí van por `branch_id`:
// `orders` tiene la columna. «Lo más movido» tiene que significar algo en la sucursal de
// quien mira, no en la empresa entera.
func (a *Acotado) UsoDeProductos(ctx context.Context, recientes int32) ([]sqlc.UsoDeProductosRow, error) {
	return a.q.UsoDeProductos(ctx, sqlc.UsoDeProductosParams{
		Sucursal: a.sucursalPg(), PedidosRecientes: recientes,
	})
}

// ObtenerProducto, ActualizarProducto y BorrarProducto van SIN ALCANCE, y está decidido:
// son las correcciones a mano del catálogo, que es de toda la empresa —una fila tocada
// aquí la ven las ocho sucursales—. La puerta no es la sucursal sino el ROL: sólo el
// Super Admin, y eso lo comprueba el manejador con el literal del contrato.
func (a *Acotado) ObtenerProducto(ctx context.Context, id uuid.UUID) (sqlc.Product, error) {
	return a.q.ObtenerProducto(ctx, id)
}

func (a *Acotado) ActualizarProducto(ctx context.Context, arg sqlc.ActualizarProductoParams) (sqlc.ActualizarProductoRow, error) {
	return a.q.ActualizarProducto(ctx, arg)
}

func (a *Acotado) BorrarProducto(ctx context.Context, id uuid.UUID) (int64, error) {
	return a.q.BorrarProducto(ctx, id)
}

// ---------------------------------------------------------------------------
// Puntos de partida guardados (/api/origins)
// ---------------------------------------------------------------------------

// ListarOrigenes: con alcance, los de esa sucursal; sin alcance, los de la que se pida
// por query, o todos. El `pedida` NO puede ampliar el alcance — por eso se mira primero
// el del alcance y sólo después el de fuera.
func (a *Acotado) ListarOrigenes(ctx context.Context, pedida *uuid.UUID) ([]sqlc.ListarOrigenesRow, error) {
	if a.sucursal != nil {
		return a.q.ListarOrigenes(ctx, a.sucursalPg())
	}
	return a.q.ListarOrigenes(ctx, aPg(pedida))
}

func (a *Acotado) ActualizarOrigen(ctx context.Context, arg sqlc.ActualizarOrigenParams) (sqlc.SavedOrigin, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.ActualizarOrigen(ctx, arg)
}

func (a *Acotado) BorrarOrigen(ctx context.Context, id uuid.UUID) (int64, error) {
	return a.q.BorrarOrigen(ctx, sqlc.BorrarOrigenParams{ID: id, Sucursal: a.sucursalPg()})
}

// ---------------------------------------------------------------------------
// Almacenes (/api/almacenes)
// ---------------------------------------------------------------------------

// CodigosDeSucursalesVisibles es lo ÚNICO que pone esta base en `/api/almacenes`: los
// almacenes viven en Accesos y no se copian aquí. Accesos devuelve las ocho sucursales
// porque no sabe nada de nuestro alcance; con esta lista se descartan las que no tocan.
func (a *Acotado) CodigosDeSucursalesVisibles(ctx context.Context) ([]sqlc.CodigosDeSucursalesVisiblesRow, error) {
	return a.q.CodigosDeSucursalesVisibles(ctx, a.sucursalPg())
}

// AlmacenesDelPedidoSinMedir: los pedidos que NO se midieron desde su propio almacén,
// agrupados por sucursal, motivo y almacén.
//
// `sucursales` NULL (nil) es «todas» y una lista acota. NO se acota aquí dentro a propósito:
// el que llama es la pantalla de administración, que ve las ocho, y la lista se le pasa hecha
// desde `CodigosDeSucursalesVisibles`. Hacerlo aquí con `a.Codigo()` sería acotarlo por la
// sucursal ELEGIDA ARRIBA en la cabecera, que es justo el fallo del 26/09/2026 de
// `/api/almacenes`: a un Super Admin mirando Camagüey le devolvería sólo Camagüey.
func (a *Acotado) AlmacenesDelPedidoSinMedir(
	ctx context.Context, sucursales []string, tope int32,
) ([]sqlc.AlmacenesDelPedidoSinMedirRow, error) {
	return a.q.AlmacenesDelPedidoSinMedir(ctx, sqlc.AlmacenesDelPedidoSinMedirParams{
		Sucursales: sucursales, Tope: tope,
	})
}

// ---------------------------------------------------------------------------
// Panel e informes  (/api/dashboard, /api/reports)
// ---------------------------------------------------------------------------
//
// AQUÍ ESTABA EL FALLO DE DELIVERY. El panel contaba «los pedidos de la cuenta que mira» y
// no los de la SUCURSAL: como las ocho sucursales las dio de alta el Super Admin, los 3.528
// pedidos importados quedaron a su nombre y el logístico de Holguín veía ceros con un 200.
// Las seis consultas de abajo se acotan con `a.sucursalPg()` y con nada más — ni actor, ni
// creador, ni «quién lo importó».

// PanelResumen: los cinco números que salen de `orders` en una sola consulta. `hoy` lo
// calcula quien atiende la petición, no Postgres: la hora local del motor no tiene por qué
// ser la del proceso, y «entregados hoy» arrancaría a las siete de la tarde de ayer.
func (a *Acotado) PanelResumen(ctx context.Context, hoy pgtype.Timestamptz) (sqlc.PanelResumenRow, error) {
	return a.q.PanelResumen(ctx, sqlc.PanelResumenParams{Hoy: hoy, Sucursal: a.sucursalPg()})
}

// PanelPorSucursal: el desglose de lo repartible. Con alcance sale una sola fila —la
// propia—, que es justo lo correcto; sin alcance salen las ocho.
func (a *Acotado) PanelPorSucursal(ctx context.Context) ([]sqlc.PanelPorSucursalRow, error) {
	return a.q.PanelPorSucursal(ctx, a.sucursalPg())
}

func (a *Acotado) ContarRutasActivas(ctx context.Context) (int64, error) {
	return a.q.ContarRutasActivas(ctx, a.sucursalPg())
}

// ContarVehiculos y ContarVehiculosEnRuta se acotan como se LISTAN los vehículos (ver
// `db/queries/vehicles.sql`): los de la sucursal más los de `branch_id` NULL, que son los
// compartidos. Contarlos de otra forma daría una tarjeta que dice «3 vehículos» encima de
// una lista de cuatro.
func (a *Acotado) ContarVehiculos(ctx context.Context) (int64, error) {
	return a.q.ContarVehiculos(ctx, a.sucursalPg())
}

func (a *Acotado) ContarVehiculosEnRuta(ctx context.Context) (int64, error) {
	return a.q.ContarVehiculosEnRuta(ctx, a.sucursalPg())
}

// ListarPedidosParaInforme: el detalle del informe. El filtro de vehículo y el de fechas
// llegan del manejador; la sucursal NO, se pisa aquí. Un informe es un fichero que sale de
// la casa: si el alcance se pudiera pasar desde fuera, bastaría con no mandarlo.
func (a *Acotado) ListarPedidosParaInforme(ctx context.Context, arg sqlc.ListarPedidosParaInformeParams) ([]sqlc.ListarPedidosParaInformeRow, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.ListarPedidosParaInforme(ctx, arg)
}

// ---------------------------------------------------------------------------
// El espejo de PEDIDO
// ---------------------------------------------------------------------------
//
// LA PUERTA DE ENTRADA DE LOS PEDIDOS. Sin esto, la base nueva no tiene ni un pedido:
// aquí dentro no se da de alta nada a mano, todo llega de PEDIDO por `/api/quote/batch`.
//
// NINGUNA LLEVA `a.sucursalPg()`, y esta vez no es un olvido ni una excepción cómoda: el
// espejo entra con clave de servicio, sin persona y sin sucursal, y trae las ocho de una
// pasada. La sucursal de cada fila la decide el LOTE (`branch_id` sale de la sucursal que
// el propio pedido dice), no quien llama. Acotarlo por sucursal dejaría a siete sin
// pedidos y sin una sola traza que lo dijera.

// EspejoGuardarPedido escribe un pedido del lote CON SUS RENGLONES, todo o nada.
//
// LOS RENGLONES SE REESCRIBEN ENTEROS: se borran y se vuelven a poner. PEDIDO puede haber
// quitado una línea, y actualizar línea a línea dejaría la vieja colgada — el despacho
// prepararía mercancía que el cliente ya no pidió.
//
// Y VA EN UNA TRANSACCIÓN porque entre el borrado y el alta el pedido se queda SIN
// renglones: si el proceso se cae justo ahí, en la pantalla queda un pedido vacío que
// nadie sabe explicar, y el peso con el que se cargó el camión ya no cuadra con nada.
//
// Devuelve el id y si la fila es NUEVA (la primera vez que este pedido entra).
func (a *Acotado) EspejoGuardarPedido(
	ctx context.Context,
	pedido sqlc.GuardarPedidoDelEspejoParams,
	renglones []sqlc.CrearRenglonDePedidoParams,
) (uuid.UUID, bool, error) {
	var id uuid.UUID
	var nuevo bool
	err := a.EnTx(ctx, func(dentro *Acotado) error {
		fila, err := dentro.q.GuardarPedidoDelEspejo(ctx, pedido)
		switch {
		case err == nil:
			id, nuevo = fila.ID, fila.EsNuevo

		// SIN FILA NO ES UN FALLO: ES QUE NO HABÍA NADA QUE CAMBIAR.
		//
		// El upsert lleva desde el 26/09/2026 un `WHERE ... IS DISTINCT FROM ...` que
		// evita reescribir un pedido idéntico — es lo que corta los 7,1 millones de
		// actualizaciones sobre 5.452 filas—. Con ese `WHERE`, el `RETURNING` no devuelve
		// nada cuando la fila se queda igual, y la consulta es `:one`: sale
		// `pgx.ErrNoRows`.
		//
		// Pero el `id` HACE FALTA igualmente: los renglones se comparan contra los que ya
		// hay, y para eso hay que saber de qué pedido son. Se busca por la referencia, que
		// es el índice único. Un SELECT cuesta mucho menos que el UPDATE con su WAL que
		// esto viene a evitar, y sólo se paga cuando NO cambió nada.
		//
		// `nuevo` queda en false, que es la verdad: si no cambió nada, desde luego no
		// acaba de nacer.
		case errors.Is(err, pgx.ErrNoRows):
			ref, errRef := dentro.q.BuscarPedidoPorReferencia(ctx, sqlc.BuscarPedidoPorReferenciaParams{
				Source:     pedido.Source,
				ExternalID: pedido.ExternalID,
			})
			if errRef != nil {
				return errRef
			}
			id, nuevo = ref.ID, false

		default:
			return err
		}

		// SI LOS RENGLONES SON LOS MISMOS, NO SE TOCA NADA.
		//
		// Medido en producción el 26/09/2026:
		//
		//     order_items   7.450 filas · 8.892.252 insertados · 8.884.802 borrados
		//
		// Mil ciento noventa veces cada renglón, casi siempre para dejarlo exactamente
		// igual: el espejo repasa cada minuto y borra y reinserta enteros en cada pasada.
		// Es la otra mitad del 36 % de CPU del Postgres, junto con los 98 millones de
		// `customers`.
		//
		// La lectura cuesta un índice por `order_id` —el que se puso el 26/09— y ahorra un
		// borrado y N inserciones con su WAL y su autovacuum. Cuando SÍ cambió, se paga la
		// lectura de más, que es lo barato de las dos.
		iguales, err := dentro.renglonesIguales(ctx, id, renglones)
		if err != nil {
			return err
		}
		if iguales {
			return nil
		}

		if err := dentro.q.BorrarRenglonesDePedido(ctx, id); err != nil {
			return err
		}
		for i := range renglones {
			// El `pedido_id` lo pone ESTE método y no quien llama: es el id que acaba de
			// devolver el upsert, y el de arriba puede no tenerlo (un pedido que ya
			// existía se reconoce por `external_id`, no por su uuid).
			renglones[i].PedidoID = id
			if _, err := dentro.q.CrearRenglonDePedido(ctx, renglones[i]); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return uuid.Nil, false, err
	}
	return id, nuevo, nil
}

// EspejoMarcaDeAgua es el `since` de la próxima bajada: lo más nuevo que ya tenemos,
// SEGÚN PEDIDO (`max(pedido_updated_at)`), no según nuestro reloj.
//
// SALE DE LOS DATOS Y NO DE UN CONTADOR, y ésa es toda la razón de que exista: un contador
// se adelanta si una tanda falla a medias, y entonces el espejo se salta esos pedidos para
// siempre sin dar un solo error. Aquí, una tanda que no se escribió simplemente no mueve
// la marca y se vuelve a pedir en el ciclo siguiente.
//
// Se acota por CÓDIGO como los clientes: `orders.sucursal_codigo`. Sin alcance —el caso
// del espejo— es NULL y sale la de las ocho.
func (a *Acotado) EspejoMarcaDeAgua(ctx context.Context) (pgtype.Timestamptz, error) {
	return a.q.MarcaDeAguaDelEspejo(ctx, a.Codigo())
}

// EspejoPosicionDelBarrido: por dónde va el recorrido del histórico, en DÍAS HACIA ATRÁS.
//
// ESTO SÍ ES UN CONTADOR GUARDADO, al revés que la marca de agua, y tiene su porqué: de
// los datos NO se puede deducir. El espejo ya tenía pedidos sueltos de hace un año —de
// cuando se traía todo—, así que «el más antiguo que tengo» no significa «tengo todo hasta
// ahí»: el barrido arrancaba a 357 días y se saltaba entero el año de en medio, que era
// justo lo que faltaba por recuperar.
//
// Que este contador se pueda adelantar no rompe nada: lo que se mueva sigue llegando por
// `since` en cada ciclo, y el barrido da la vuelta al año una y otra vez, así que un tramo
// saltado se recoge en la pasada siguiente.
func (a *Acotado) EspejoPosicionDelBarrido(ctx context.Context) (int32, error) {
	ajustes, err := a.q.ObtenerAjustes(ctx)
	if err != nil {
		return 0, err
	}
	return ajustes.SyncBarridoDia, nil
}

func (a *Acotado) EspejoFijarBarrido(ctx context.Context, dia int32) error {
	return a.q.FijarBarridoDelEspejo(ctx, dia)
}

// EspejoGuardarCliente copia un cliente GEOLOCALIZADO de PEDIDO. Idempotente por
// (`source`, `external_id`) con `ON CONFLICT`: dos pasadas a la vez no lo duplican.
func (a *Acotado) EspejoGuardarCliente(ctx context.Context, arg sqlc.GuardarClienteDelEspejoParams) (sqlc.GuardarClienteDelEspejoRow, error) {
	return a.q.GuardarClienteDelEspejo(ctx, arg)
}

// EspejoBorrarClientesQueYaNoVienen quita los de PEDIDO que dejaron de venir: borrados
// allá, o sin coordenadas. NO toca el alta manual (`source` nulo), que no está en ningún
// otro sitio y no se podría recuperar.
//
// QUIEN LLAME TIENE QUE HABER RECORRIDO TODAS LAS PÁGINAS ANTES. Con media lista —un corte
// de la VPN a mitad del recorrido— esto vacía el espejo entero, y el logístico se queda
// sin a quién repartir con un 200 y sin un solo error.
func (a *Acotado) EspejoBorrarClientesQueYaNoVienen(ctx context.Context, ids []string) (int64, error) {
	return a.q.BorrarClientesDelEspejoQueYaNoVienen(ctx, sqlc.BorrarClientesDelEspejoQueYaNoVienenParams{
		Source:      sqlc.ProcedenciaPedido,
		ExternalIds: ids,
	})
}

// renglonesIguales dice si lo que hay guardado es exactamente lo que viene.
//
// SE COMPARA LO QUE SE ESCRIBE Y NADA MÁS. Ni el `id` ni las fechas entran: cambian aunque
// el renglón sea el mismo y harían que la comparación dijera «distinto» siempre — la
// guarda parecería puesta y no serviría de nada, que es peor que no tenerla porque nadie
// vuelve a mirarla.
//
// El orden lo fija el `ORDER BY linea` de la consulta y el `linea` de lo que viene, que es
// la POSICIÓN ORIGINAL en el pedido. Sin un orden estable, dos listas iguales en distinto
// orden se leerían como un cambio y se reescribirían igual.
//
// Distinto número de renglones es distinto y se sale antes: es el caso de una línea que
// PEDIDO quitó, y ése hay que reescribirlo sí o sí o el despacho prepara mercancía que el
// cliente ya no pidió.
func (a *Acotado) renglonesIguales(
	ctx context.Context, pedido uuid.UUID, vienen []sqlc.CrearRenglonDePedidoParams,
) (bool, error) {
	hay, err := a.q.RenglonesDePedidoParaComparar(ctx, pedido)
	if err != nil {
		return false, err
	}
	if len(hay) != len(vienen) {
		return false, nil
	}
	for i, h := range hay {
		v := vienen[i]
		if h.Linea != v.Linea ||
			h.Description != v.Description ||
			h.Quantity != v.Quantity ||
			!mismoFlotante(h.Packs, v.Packs) ||
			h.ProductID != v.ProductID ||
			!mismoTexto(h.Nombre, v.Nombre) ||
			!mismoTexto(h.Codigo, v.Codigo) ||
			!mismoTexto(h.AlmacenNombre, v.AlmacenNombre) ||
			!mismoBooleano(h.Caso, v.Caso) ||
			!mismoFlotante(h.PesoUnitarioKg, v.PesoUnitarioKg) ||
			!mismoFlotante(h.PesoLineaKg, v.PesoLineaKg) ||
			!mismoTexto(h.OrigenPeso, v.OrigenPeso) ||
			// EL ALMACÉN DEL RENGLÓN ENTRA EN LA COMPARACIÓN (00012). Si no entrara, un pedido
			// que llega con el mismo peso y el mismo producto pero desde OTRO almacén se
			// leería como «no cambió nada» y la columna se quedaría con el primer almacén para
			// siempre. Pasa de verdad: un pedido entra antes de facturarse sin almacén, y
			// cuando PEDIDO lo cierra contra la factura llega ya con el suyo. Sin esto, las
			// dos consultas —la que compara y la que escribe— contestarían cosas distintas
			// sobre lo mismo, que es el §3-bis del `CLAUDE.md`.
			!mismoTexto(h.AlmacenSalidaCodigo, v.AlmacenSalidaCodigo) ||
			!mismoTexto(h.AlmacenSalidaNombre, v.AlmacenSalidaNombre) {
			return false, nil
		}
	}
	return true, nil
}

// Los comparadores de punteros. `product_id` no lleva uno: es un `pgtype.UUID`, un struct
// comparable, y `!=` ya distingue el nulo —`Valid: false`— de un id de verdad.
// DOS NULOS SON IGUALES, y un nulo contra un valor es
// distinto: es el mismo criterio que `IS DISTINCT FROM` en SQL, escrito en Go para que las
// dos guardas —la de `customers` y ésta— digan lo mismo.
func mismoTexto(a, b *string) bool {
	if a == nil || b == nil {
		return a == b
	}
	return *a == *b
}

func mismoFlotante(a, b *float64) bool {
	if a == nil || b == nil {
		return a == b
	}
	return *a == *b
}

func mismoBooleano(a, b *bool) bool {
	if a == nil || b == nil {
		return a == b
	}
	return *a == *b
}

// QuitarPedidosDelEspejo borra los que PEDIDO dice que ya no están.
//
// VA SIN ALCANCE, igual que el resto de lo del espejo: el que llama es un proceso de
// servicio que recorre las ocho sucursales, no una persona. Lo que sí acota la consulta es
// `source = 'pedido'`: un alta manual del reparto no se toca ni por casualidad.
func (a *Acotado) QuitarPedidosDelEspejo(ctx context.Context, ids []string) (int64, error) {
	if len(ids) == 0 {
		return 0, nil
	}
	return a.q.QuitarPedidosDelEspejo(ctx, ids)
}
