package alcance

// LA PUERTA A LAS CONSULTAS DE LAS RUTAS DE REPARTO.
//
// Continuación de `consultas.go` con la misma regla: es ESTE fichero —y no el manejador—
// quien rellena el parámetro `sucursal`. Va en fichero aparte por lo mismo que
// `tablero.go`: rutas, pedidos y tablero se escriben a la vez y dos manos en el mismo
// fichero es un conflicto seguro.
//
// Los nombres SIN prefijo son los de aquí: `tablero.go` dejó los suyos con `Tablero…`
// justo para que el armador de siempre —éste— se quedara con el nombre natural. El día
// que los dos lados se junten, se unifican.

import (
	"context"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/store/sqlc"
)

// ---------------------------------------------------------------------------
// Acotar todavía más: la sucursal que elige el Super Admin al armar
// ---------------------------------------------------------------------------

// EnSucursal devuelve el MISMO alcance pero acotado ADEMÁS a esa sucursal.
//
// SÓLO ACOTA, NUNCA ABRE. Si esta petición ya venía acotada se devuelve tal cual y lo
// pedido se ignora, que es literalmente la regla del contrato: «quien tiene alcance no
// puede pasar otra sucursal por el cuerpo, manda el suyo». Y al revés, el Super Admin
// —que no tiene alcance— sí tiene que poder decir «esta ruta es de Holguín» en el primer
// paso del asistente, porque si no la ruta nacía sin sucursal o con la del primer pedido,
// por casualidad.
//
// `codigo` se deja vacío a propósito: el código (CAM, HAB, STG…) no se conoce aquí, y
// devolver el de la sucursal anterior sería peor que no tener ninguno.
func (a *Acotado) EnSucursal(id *uuid.UUID) *Acotado {
	if a.sucursal != nil || id == nil {
		return a
	}
	dentro := *a
	dentro.sucursal = id
	dentro.codigo = nil
	return &dentro
}

// ---------------------------------------------------------------------------
// Lectura: el tablero de rutas y el detalle
// ---------------------------------------------------------------------------

// ListarRutas no acepta filtro de estado a propósito: el contrato de `GET /api/routes`
// dice «Query: ninguna». El parámetro existe en el SQL para quien lo necesite después.
func (a *Acotado) ListarRutas(ctx context.Context) ([]sqlc.ListarRutasRow, error) {
	return a.q.ListarRutas(ctx, sqlc.ListarRutasParams{Sucursal: a.sucursalPg()})
}

func (a *Acotado) ObtenerRuta(ctx context.Context, id uuid.UUID) (sqlc.ObtenerRutaRow, error) {
	return a.q.ObtenerRuta(ctx, sqlc.ObtenerRutaParams{ID: id, Sucursal: a.sucursalPg()})
}

// BloquearRuta se usa sólo dentro de EnTx: completar y cualquier modificación
// comparten el bloqueo de la fila; una lectura anterior no protege el histórico.
func (a *Acotado) BloquearRuta(ctx context.Context, id uuid.UUID) (sqlc.RouteStatus, error) {
	return a.q.BloquearRuta(ctx, sqlc.BloquearRutaParams{ID: id, Sucursal: a.sucursalPg()})
}

// ParadasDeRutas trae las paradas de VARIAS rutas de una vez. Es lo que evita que pintar
// el tablero cueste una consulta por ruta.
func (a *Acotado) ParadasDeRutas(ctx context.Context, rutas []uuid.UUID) ([]sqlc.ListarParadasDeRutasRow, error) {
	return a.q.ListarParadasDeRutas(ctx, sqlc.ListarParadasDeRutasParams{
		RutaIds: rutas, Sucursal: a.sucursalPg(),
	})
}

func (a *Acotado) RenglonesDeRutas(ctx context.Context, rutas []uuid.UUID) ([]sqlc.ListarRenglonesDeRutasRow, error) {
	return a.q.ListarRenglonesDeRutas(ctx, sqlc.ListarRenglonesDeRutasParams{
		RutaIds: rutas, Sucursal: a.sucursalPg(),
	})
}

// ParadasQueViajaronEnRuta es el universo del CIERRE: las que siguen en la ruta
// (`route_id`) y las que la soltaron CON UN RESULTADO por `ultima_ruta_id`, o sea los
// devueltos y cancelados. Con `route_id` solo no se podría corregir el resultado de un
// devuelto, que es media hoja de cierre. Un pedido simplemente quitado de la ruta no
// entra: no viajó (ver la consulta, «la parada fantasma»).
func (a *Acotado) ParadasQueViajaronEnRuta(ctx context.Context, ruta uuid.UUID) ([]sqlc.ListarParadasQueViajaronEnRutaRow, error) {
	return a.q.ListarParadasQueViajaronEnRuta(ctx, sqlc.ListarParadasQueViajaronEnRutaParams{
		RutaID: aPg(&ruta), Sucursal: a.sucursalPg(),
	})
}

// ---------------------------------------------------------------------------
// Armado  (POST /api/routes)
// ---------------------------------------------------------------------------

// PedidosParaArmarRuta es la VALIDACIÓN, no una lectura previa a ella: devuelve sólo los
// que siguen estando libres, y de que vuelvan menos de los pedidos sale el 409.
func (a *Acotado) PedidosParaArmarRuta(ctx context.Context, pedidos []uuid.UUID) ([]sqlc.PedidosParaArmarRutaRow, error) {
	return a.q.PedidosParaArmarRuta(ctx, sqlc.PedidosParaArmarRutaParams{
		PedidoIds: pedidos, Sucursal: a.sucursalPg(),
	})
}

// PorQueNoSePuedeArmar explica el 409 del armado, uno por uno.
//
// Lleva el MISMO alcance que `PedidosParaArmarRuta` y no puede llevar otro: si se leyera
// sin acotar para «poder decir más», un id sondeado a mano contestaría el número de
// operación y el nombre del cliente de otra sucursal, que es la fuga de la regla 1 por la
// puerta del mensaje de error. Lo que no devuelve fila se nombra igual, con «no existe o
// no es de tu sucursal», que es lo mismo que contesta `ObtenerRuta`.
func (a *Acotado) PorQueNoSePuedeArmar(ctx context.Context, pedidos []uuid.UUID) ([]sqlc.PorQueNoSePuedeArmarRow, error) {
	return a.q.PorQueNoSePuedeArmar(ctx, sqlc.PorQueNoSePuedeArmarParams{
		PedidoIds: pedidos, Sucursal: a.sucursalPg(),
	})
}

// ContarRutasDelDia NO lleva alcance a propósito: el `NNN` de `RT-YYYYMMDD-NNN` es de toda
// la casa. Numerar por sucursal daría dos rutas distintas con el MISMO código el mismo
// día, y ese código es lo que la gente se dice por teléfono.
func (a *Acotado) ContarRutasDelDia(ctx context.Context, prefijo string) (int64, error) {
	return a.q.ContarRutasDelDia(ctx, prefijo)
}

// CrearRuta: el alcance MANDA sobre lo que traiga el cuerpo. Quien está acotado crea la
// ruta en SU sucursal aunque mande otra; quien no lo está (Super Admin) usa la que venga
// en `arg.BranchID`, que el manejador ya resolvió como «la elegida, o la del primer
// pedido».
func (a *Acotado) CrearRuta(ctx context.Context, arg sqlc.CrearRutaParams) (sqlc.CrearRutaRow, error) {
	if a.sucursal != nil {
		arg.BranchID = a.sucursalPg()
	}
	arg.CreadoPor = a.ActorRef() // constancia de quién la armó. NO filtra nada.
	return a.q.CrearRuta(ctx, arg)
}

func (a *Acotado) EngancharPedidoARuta(ctx context.Context, arg sqlc.EngancharPedidoARutaParams) (int64, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.EngancharPedidoARuta(ctx, arg)
}

func (a *Acotado) FijarTotalesDeRuta(ctx context.Context, arg sqlc.FijarTotalesDeRutaParams) (sqlc.FijarTotalesDeRutaRow, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.FijarTotalesDeRuta(ctx, arg)
}

// ---------------------------------------------------------------------------
// Cambios de estado  (PATCH /api/routes/[id])
// ---------------------------------------------------------------------------

func (a *Acotado) ActualizarEstadoDeRuta(ctx context.Context, arg sqlc.ActualizarEstadoDeRutaParams) (sqlc.ActualizarEstadoDeRutaRow, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.ActualizarEstadoDeRuta(ctx, arg)
}

func (a *Acotado) CambiarVehiculoDeRuta(ctx context.Context, arg sqlc.CambiarVehiculoDeRutaParams) (sqlc.CambiarVehiculoDeRutaRow, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.CambiarVehiculoDeRuta(ctx, arg)
}

// CambiarEstadoDeVehiculo ocupa o libera el camión. El SQL deja pasar también los de
// `branch_id` NULL, que son los compartidos: un camión de todas se ocupa igual.
func (a *Acotado) CambiarEstadoDeVehiculo(ctx context.Context, id uuid.UUID, estado sqlc.VehicleStatus) (int64, error) {
	return a.q.CambiarEstadoDeVehiculo(ctx, sqlc.CambiarEstadoDeVehiculoParams{
		ID: id, Status: estado, Sucursal: a.sucursalPg(),
	})
}

// ObtenerVehiculoParaCapacidad va SIN alcance, calcado del contrato: si el camión no
// aparece, delivery no valida la capacidad en vez de negarse. La fila trae su `branch_id`
// para que el manejador lo mire si le hace falta.
func (a *Acotado) ObtenerVehiculoParaCapacidad(ctx context.Context, id uuid.UUID) (sqlc.ObtenerVehiculoParaCapacidadRow, error) {
	return a.q.ObtenerVehiculoParaCapacidad(ctx, id)
}

// ---------------------------------------------------------------------------
// Cierre y borrado
// ---------------------------------------------------------------------------

// MarcarResultadoDeParada lleva la ruta en el WHERE (`route_id`, o `ultima_ruta_id` si la
// parada la soltó con un resultado): cero filas es «ese pedido no va en esta ruta», que es
// el rechazo del contrato. Comprobarlo antes en Go sobre una lectura anterior es mirar una
// foto vieja.
func (a *Acotado) MarcarResultadoDeParada(ctx context.Context, ruta, pedido uuid.UUID, resultado sqlc.StopResult, nota *string) (int64, error) {
	return a.q.MarcarResultadoDeParada(ctx, sqlc.MarcarResultadoDeParadaParams{
		Resultado: resultado,
		Nota:      nota,
		PedidoID:  pedido,
		RutaID:    aPg(&ruta),
		Sucursal:  a.sucursalPg(),
	})
}

// LimpiarResultadoDeParada deshace la marca de una parada. Ver la consulta en
// `db/queries/routes.sql`: devuelve además el `route_id`, o un devuelto desmarcado se
// quedaría fuera de su propia ruta con la ruta todavía abierta.
func (a *Acotado) LimpiarResultadoDeParada(ctx context.Context, ruta, pedido uuid.UUID) (int64, error) {
	return a.q.LimpiarResultadoDeParada(ctx, sqlc.LimpiarResultadoDeParadaParams{
		PedidoID: pedido,
		RutaID:   aPg(&ruta),
		Sucursal: a.sucursalPg(),
	})
}

// DondeEstanLosPedidos NO lleva alcance a propósito, igual que `ContarRutasDelDia` y
// `ObtenerVehiculoParaCapacidad`, y por una razón más estrecha que las suyas: es el
// diagnóstico del REGISTRO del servidor cuando un cierre rechaza paradas, y su resultado
// no sale nunca en la respuesta. Con alcance, el pedido de otra sucursal —que es una de las
// causas posibles del rechazo— saldría como «no existe». Quien la llame no puede devolver
// lo que lea al cliente. Ver la consulta.
func (a *Acotado) DondeEstanLosPedidos(ctx context.Context, pedidos []uuid.UUID) ([]sqlc.DondeEstanLosPedidosRow, error) {
	return a.q.DondeEstanLosPedidos(ctx, pedidos)
}

func (a *Acotado) SoltarPedidosDeRuta(ctx context.Context, ruta uuid.UUID) (int64, error) {
	return a.q.SoltarPedidosDeRuta(ctx, sqlc.SoltarPedidosDeRutaParams{
		RutaID: aPg(&ruta), Sucursal: a.sucursalPg(),
	})
}

func (a *Acotado) SoltarParadaPlanificada(ctx context.Context, ruta, pedido uuid.UUID) (uuid.UUID, error) {
	return a.q.SoltarParadaPlanificada(ctx, sqlc.SoltarParadaPlanificadaParams{
		RutaID: ruta, PedidoID: pedido, Sucursal: a.sucursalPg(),
	})
}

func (a *Acotado) BorrarRuta(ctx context.Context, id uuid.UUID) (int64, error) {
	return a.q.BorrarRuta(ctx, sqlc.BorrarRutaParams{ID: id, Sucursal: a.sucursalPg()})
}

// ---------------------------------------------------------------------------
// El buzón de salida hacia PEDIDO
// ---------------------------------------------------------------------------
//
// VA SIN ALCANCE, y es a propósito. Un aviso encolado es un hecho que ya pasó —esta parada
// acabó así—, y quien lo drena es un trabajador de fondo que no tiene sucursal ni persona
// detrás. Acotarlo dejaría avisos que nadie puede mandar.
//
// El porqué de que exista la tabla está en `00010_avisos_a_pedido.sql`: la llamada
// síncrona del cierre se pierde si PEDIDO está caído, y entonces el pedido queda entregado
// aquí y eterno «en proceso» allá sin que nadie se entere.

// EncolarAvisoAPedido apunta que hay que contarle esto a PEDIDO.
//
// Se llama DENTRO de la misma transacción que escribe el resultado: o se guardan los dos o
// ninguno. Fuera de ella, un fallo entre las dos escrituras deja el resultado sin aviso, que
// es justo el agujero que esto viene a tapar.
func (a *Acotado) EncolarAvisoAPedido(ctx context.Context, p sqlc.EncolarAvisoAPedidoParams) error {
	return a.q.EncolarAvisoAPedido(ctx, p)
}

// AvisosAPedidoPendientes son los que hay que mandar, los más viejos primero.
func (a *Acotado) AvisosAPedidoPendientes(ctx context.Context, tope int32) ([]sqlc.AvisosAPedidoPendientesRow, error) {
	return a.q.AvisosAPedidoPendientes(ctx, tope)
}

func (a *Acotado) AvisoAPedidoEnviado(ctx context.Context, id uuid.UUID) error {
	return a.q.AvisoAPedidoEnviado(ctx, id)
}

// AvisoAPedidoRechazado: PEDIDO dijo que no, y con su motivo. No se borra.
func (a *Acotado) AvisoAPedidoRechazado(ctx context.Context, id uuid.UUID, motivo string) error {
	return a.q.AvisoAPedidoRechazado(ctx, sqlc.AvisoAPedidoRechazadoParams{ID: id, Motivo: &motivo})
}

// AvisoAPedidoSeReintenta: no se pudo ni preguntar. Sigue pendiente — eso NO es un rechazo,
// y confundirlos daría por perdido lo que sólo estaba esperando.
func (a *Acotado) AvisoAPedidoSeReintenta(ctx context.Context, id uuid.UUID, motivo string) error {
	return a.q.AvisoAPedidoSeReintenta(ctx, sqlc.AvisoAPedidoSeReintentaParams{ID: id, Motivo: &motivo})
}

// ---------------------------------------------------------------------------
// Cómo va el webhook, en los dos sentidos
// ---------------------------------------------------------------------------
//
// SIN ALCANCE, igual que el buzón: esto no son datos de una sucursal, es el estado de una
// tubería. Quien lo mira es administración, y quién puede mirarlo se decide en la ruta.

func (a *Acotado) ApuntarEnvioDelWebhook(ctx context.Context, p sqlc.ApuntarEnvioDelWebhookParams) error {
	return a.q.ApuntarEnvioDelWebhook(ctx, p)
}

func (a *Acotado) ApuntarRecepcionDelWebhook(ctx context.Context, p sqlc.ApuntarRecepcionDelWebhookParams) error {
	return a.q.ApuntarRecepcionDelWebhook(ctx, p)
}

func (a *Acotado) ListarEnviosDelWebhook(ctx context.Context, tope int32) ([]sqlc.EnviosDelWebhook, error) {
	return a.q.ListarEnviosDelWebhook(ctx, tope)
}

func (a *Acotado) ListarRecepcionesDelWebhook(ctx context.Context, tope int32) ([]sqlc.RecepcionesDelWebhook, error) {
	return a.q.ListarRecepcionesDelWebhook(ctx, tope)
}

func (a *Acotado) ResumenDelWebhook(ctx context.Context) (sqlc.ResumenDelWebhookRow, error) {
	return a.q.ResumenDelWebhook(ctx)
}

func (a *Acotado) ListarAvisosAPedido(ctx context.Context, p sqlc.ListarAvisosAPedidoParams) ([]sqlc.ListarAvisosAPedidoRow, error) {
	return a.q.ListarAvisosAPedido(ctx, p)
}

func (a *Acotado) ContarAvisosAPedido(ctx context.Context) (sqlc.ContarAvisosAPedidoRow, error) {
	return a.q.ContarAvisosAPedido(ctx)
}
