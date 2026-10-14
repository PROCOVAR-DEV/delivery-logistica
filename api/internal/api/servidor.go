// Los manejadores HTTP.
//
// AQUÍ ESTÁ EL PATRÓN A COPIAR. Están montados los cuatro recursos más simples
// —sucursales, vehículos, tipos de vehículo y ajustes—; los demás (pedidos, rutas,
// clientes, productos, panel, informes) se escriben igual. Lo que hay que respetar:
//
//  1. El manejador NO recibe un `sqlc.Querier`. Recibe `*alcance.Acotado`, que saca de la
//     petición con `alcance.De(r)`, y por ahí es por donde llega a las consultas. Si la
//     consulta que necesitas no está en `internal/alcance/consultas.go`, se añade ALLÍ.
//  2. Los mensajes de error son los LITERALES de `docs/contratos-api.md`. Están como
//     constantes en `internal/httpx`. No se escriben a mano en el manejador.
//  3. La forma de la respuesta se declara en un tipo `…Salida` de este paquete, no se
//     devuelve la fila de sqlc tal cual. La fila cambia cuando cambia una consulta; el
//     contrato con el cliente, no.
//  4. Lo que son varias escrituras va en `a.EnTx(...)`. A medias no vale.
package api

import (
	"context"
	"log/slog"
	"net/http"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
)

// Servidor junta lo que necesitan los manejadores. NO tiene un Querier: la única forma de
// consultar es el alcance de la petición.
type Servidor struct {
	cfg      *config.Config
	reg      *slog.Logger
	porteria *alcance.Porteria
	verif    *auth.Verificador
	// salud es sólo el ping a la base. Una función y no el almacén entero para que las
	// pruebas no tengan que levantar un pool.
	salud func(ctx context.Context) error

	// --- Lo de fuera ---------------------------------------------------------
	//
	// Los tres eran VARIABLES DE PAQUETE (`api.Ventra`, `api.Accesos` y el gancho
	// `avisarEstadoAPedido`). Se pusieron así porque este fichero lo estaba escribiendo
	// otro y no se podían añadir campos sin chocar; no porque fuera lo correcto. Una
	// variable de paquete la comparten TODOS los servidores del proceso —y todas las
	// pruebas a la vez—, así que dos pruebas en paralelo se pisan el doble la una a la
	// otra, y en producción no hay forma de tener dos configuraciones distintas.
	//
	// Siguen siendo interfaces y funciones, no clientes concretos: eso es lo que deja que
	// las pruebas corran sin VPN, sin Ventra, sin Accesos y sin PEDIDO.

	// aPedido es el canal de salida hacia PEDIDO (ver `canal_pedido.go`). Nunca es nil:
	// sin configuración se monta el canal mudo, que no llama a nadie y lo dice.
	aPedido CanalAPedido

	// ventra es el lector del catálogo de Ventra, que vive detrás de la VPN. Puede ser
	// nil: mientras lo sea, `products/sync` contesta 502 —que es lo correcto, nunca 200
	// con ceros—.
	ventra LectorDeVentra

	// accesos es el cliente del login único (almacenes y tasas), con firma HMAC.
	accesos ClienteAccesos

	// avisos es por dónde se le cuenta A UNA PERSONA que el canal con PEDIDO se rompió
	// (ver `canal_notify.go`). Nunca es nil viniendo de `NuevoServidor`: sin configuración
	// se monta el canal mudo, que no llama a nadie y devuelve error nombrando la variable
	// que falta — nunca un «ya está mandado».
	avisos CanalDeAvisos
}

func NuevoServidor(cfg *config.Config, reg *slog.Logger, p *alcance.Porteria, v *auth.Verificador, salud func(ctx context.Context) error) *Servidor {
	if reg == nil {
		reg = slog.Default()
	}
	if salud == nil {
		salud = func(context.Context) error { return nil }
	}
	return &Servidor{
		cfg: cfg, reg: reg, porteria: p, verif: v, salud: salud,
		aPedido: nuevoCanalAPedido(cfg, reg),
		// Nada de lector de Ventra por defecto: hace falta la VPN y un MySQL, y montarlo
		// sin ellos daría un cliente que falla en cada llamada en vez de un 502 que dice
		// que no está configurado.
		ventra:  nil,
		accesos: accesosDelServidor(cfg),
		avisos:  nuevoCanalDeAvisos(cfg, reg),
	}
}

// Rutas monta el router entero.
//
// Los middlewares comunes van en el router —una vez, para todo— y los de sesión y alcance
// en cada ruta que los necesita. Escribirlos ruta por ruta en vez de dentro del manejador
// es lo que hace que el alcance NO SE PUEDA OLVIDAR: se ve de un vistazo cuál lo lleva y
// cuál no, en una sola pantalla, en vez de tener que abrir treinta y cinco ficheros.
func (s *Servidor) Rutas() http.Handler {
	rt := httpx.NuevoRouter(
		httpx.IDDePeticion,
		httpx.ConRegistro(s.reg),
		httpx.RecuperarPanico,
		httpx.RegistrarPeticiones,
		httpx.CORS(s.cfg.OrigenesPermitidos),
		httpx.SinCache,
	)

	// --- Sin sesión ------------------------------------------------------------
	// /health lo sondea el desplegador; /version lo lee la APK para saber si tiene
	// que actualizarse. Pedir token en cualquiera de las dos las vuelve inútiles.
	rt.ManejarFunc(http.MethodGet, "/health", s.salud_)
	rt.ManejarFunc(http.MethodGet, "/version", s.version)
	rt.ManejarFunc(http.MethodGet, "/api/version", s.version)
	// /mapa dice qué paquete de mapa de Cuba hay colgado para trabajar sin
	// conexión. Sin sesión por lo mismo: se consulta al arrancar. Ver
	// `internal/api/mapa.go` y `docs/mapa-sin-conexion.md`.
	rt.ManejarFunc(http.MethodGet, "/mapa", s.mapa)
	rt.ManejarFunc(http.MethodGet, "/api/mapa", s.mapa)

	// --- Con sesión y con alcance ----------------------------------------------
	conSesion := s.verif.Exigir
	conAlcance := s.porteria.Exigir
	sesion := []httpx.Medio{conSesion, conAlcance}
	admin := []httpx.Medio{conSesion, auth.ExigirAdmin, conAlcance}

	// Sucursales. El GET va con la sucursal DE LA PERSONA, no con la elegida: ver
	// `alcance.ListarSucursalesVisibles`.
	rt.ManejarFunc(http.MethodGet, "/api/branches", s.listarSucursales, sesion...)
	rt.ManejarFunc(http.MethodPost, "/api/branches", s.crearSucursal, admin...)
	rt.ManejarFunc(http.MethodGet, "/api/branches/{id}", s.obtenerSucursal, sesion...)
	rt.ManejarFunc(http.MethodPatch, "/api/branches/{id}", s.actualizarSucursal, admin...)
	rt.ManejarFunc(http.MethodDelete, "/api/branches/{id}", s.borrarSucursal, admin...)
	// La traducción del CÓDIGO de Accesos a nuestro id, para `reparto-sync`. Va con
	// clave de servicio porque quien pregunta es el paso que resuelve la identidad y
	// por tanto todavía no tiene ninguna. El porqué entero, en `sucursales.go`.
	rt.ManejarFunc(http.MethodGet, "/api/service/sucursal", s.sucursalPorCodigo, s.mediosDeServicio()...)

	// Vehículos.
	rt.ManejarFunc(http.MethodGet, "/api/vehicles", s.listarVehiculos, sesion...)
	rt.ManejarFunc(http.MethodPost, "/api/vehicles", s.crearVehiculo, sesion...)
	rt.ManejarFunc(http.MethodGet, "/api/vehicles/{id}", s.obtenerVehiculo, sesion...)
	rt.ManejarFunc(http.MethodPatch, "/api/vehicles/{id}", s.actualizarVehiculo, sesion...)
	rt.ManejarFunc(http.MethodDelete, "/api/vehicles/{id}", s.borrarVehiculo, sesion...)

	// Tipos de vehículo. RECURSO NUEVO: en delivery esto se mandaba dentro de
	// `PUT /api/settings` con la clave `tiposVehiculo`, un campo que NUNCA EXISTIÓ en el
	// esquema — la pantalla creaba tipos, los guardaba y se perdían sin un solo error.
	// Ahora es una tabla, así que es un recurso con sus rutas.
	//
	// LAS CUATRO SON DE SESIÓN, NO DE ADMIN (Jose, 14/10/2026): el logístico de Santiago, entrenándose
	// con Amado, no podía crear un tipo, y la APK es completa para el logístico. Antes de la tabla
	// esto iba en `PUT /api/settings`, que tampoco pedía admin. OJO: el catálogo es GLOBAL y el costo
	// por km del tipo es el que cotiza el domicilio en las ocho sucursales; si hubiera que volver a
	// cerrarlo, es cambiar estas tres líneas a `admin...` (y la prueba `un_logistico_gestiona_tipos`).
	rt.ManejarFunc(http.MethodGet, "/api/vehicle-types", s.listarTiposDeVehiculo, sesion...)
	rt.ManejarFunc(http.MethodPost, "/api/vehicle-types", s.crearTipoDeVehiculo, sesion...)
	rt.ManejarFunc(http.MethodPatch, "/api/vehicle-types/{id}", s.actualizarTipoDeVehiculo, sesion...)
	rt.ManejarFunc(http.MethodDelete, "/api/vehicle-types/{id}", s.borrarTipoDeVehiculo, sesion...)

	// Ajustes. Globales: llevan sesión pero el alcance no pinta nada (y aun así se monta,
	// porque es por donde se llega a las consultas).
	rt.ManejarFunc(http.MethodGet, "/api/settings", s.obtenerAjustes, sesion...)
	rt.ManejarFunc(http.MethodPut, "/api/settings", s.guardarAjustes, sesion...)

	// --- El resto de los recursos ----------------------------------------------
	//
	// Cada módulo registra las suyas en su propio fichero y aquí sólo se llaman. No es
	// una manía de orden: este fichero lo tocan todos, y con doce recursos escribiendo
	// sus `ManejarFunc` aquí dentro, dos personas trabajando a la vez chocan siempre.
	// Así cada uno es dueño de su fichero y esto es la lista de lo que hay montado.
	//
	// El orden no importa para el enrutado —ServeMux resuelve por especificidad, no por
	// orden de registro— pero sí para leerlo: primero lo que se usa todos los días.
	s.rutasPedidos(rt, sesion, admin)
	s.rutasDeReparto(rt, sesion, admin)
	s.rutasTablero(rt, sesion, admin)
	s.rutasClientes(rt, sesion, admin)
	s.rutasProductos(rt, sesion, admin)
	s.rutasAlmacenes(rt, sesion, admin)
	s.rutasCotizacion(rt, sesion, admin)
	s.rutasPanel(rt, sesion, admin)
	s.rutasInformes(rt, sesion, admin)
	s.rutasEventos(rt, sesion, admin)
	s.rutasYo(rt, sesion, admin)
	// La puerta de la WEB: redirección a Accesos y vuelta con cookie. Las cuatro
	// van SIN sesión —son a las que se llega sin tenerla— y no tocan a la APK,
	// que sigue entrando con usuario y contraseña (`internal/api/auth_web.go`).
	s.rutasAuthWeb(rt, sesion, admin)
	s.rutasEspejo(rt, sesion, admin)

	return rt.Handler()
}
