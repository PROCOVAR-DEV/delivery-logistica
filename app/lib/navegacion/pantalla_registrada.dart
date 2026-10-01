import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// ============================================================================
/// EL CONTRATO DE REGISTRO DE RUTAS — léelo antes de escribir tu pantalla.
/// ============================================================================
///
/// El armazon (barra lateral, barra superior, franja de estado) lo monta
/// `navegacion/`. Tu pantalla **no monta ninguna de esas tres cosas**: se
/// enchufa, y el armazon la envuelve.
///
/// Son tres pasos y ninguno toca un fichero de otro:
///
///  1. En tu carpeta creas **un fichero propio**, `lib/pantallas/<tuya>/registro.dart`,
///     con **una sola funcion de nivel superior** que devuelve una
///     `PantallaRegistrada`:
///
///     ```dart
///     // lib/pantallas/pedidos/registro.dart
///     import 'package:flutter/widgets.dart';
///     import '../../navegacion/pantalla_registrada.dart';
///     import 'vista/pantalla_pedidos.dart';
///
///     PantallaRegistrada registrarPedidos() => PantallaRegistrada(
///           ruta: '/orders',
///           titulo: 'Pedidos',              // literal de la barra superior
///           icono: Icons.inventory_2_outlined,
///           enElMenu: true,
///           // DE QUE HORA SON LOS DATOS DE ESTA PANTALLA. Obligatorio y sin
///           // valor por defecto: ver [PantallaRegistrada.colecciones].
///           colecciones: ColeccionesDePantalla.pedidos,
///           construir: (contexto, estado) => const PantallaPedidos(),
///         );
///     ```
///
///  2. En `lib/navegacion/pantallas.dart` sustituyes **tu** linea
///     `_pendiente('/orders', …)` por `registrarPedidos()` y anades el import.
///     Es la UNICA linea que tocas fuera de tu carpeta: una linea por pantalla,
///     asi que dos agentes no chocan aunque entren a la vez.
///
///  3. Ya esta. La entrada del menu, el titulo, el reloj de datos, la cola
///     pendiente y el selector de sucursal salen solos.
///
/// **Los filtros van en la URL** (`estado.uri.queryParameters`), que es lo que
/// hace que en web se pueda mandar un enlace a la lista ya filtrada. Lee de ahi
/// y escribe con `context.go(...)`; no guardes el filtro solo en un `State`.
///
/// **Tu pantalla no lleva `Scaffold` ni `AppBar`.** El armazon ya pone los dos:
/// devolver otro deja dos barras superiores y rompe el selector de sucursal.
/// ============================================================================
typedef ConstructorDePantalla = Widget Function(
  BuildContext contexto,
  GoRouterState estado,
);

class PantallaRegistrada {
  const PantallaRegistrada({
    required this.ruta,
    required this.titulo,
    required this.construir,
    required this.colecciones,
    this.icono,
    this.enElMenu = false,
    this.soloParaRoles = const <String>[],
    this.conArmazon = true,
    this.subrutas = const <RouteBase>[],
  });

  /// La ruta, con barra delante: `/dashboard`, `/orders`, `/routes`…
  final String ruta;

  /// El titulo que pinta la barra superior. **Literal del pliego**, en espanol.
  final String titulo;

  final ConstructorDePantalla construir;

  /// LAS COLECCIONES QUE ESTA PANTALLA USA. Contra ellas se mide la franja de
  /// arriba, y **sólo contra ellas**.
  ///
  /// Sale de `ColeccionesDePantalla`
  /// (`nucleo/frescura/colecciones_de_cada_pantalla.dart`), que es donde viven
  /// las listas y el caso del 01/10/2026 que las trajo: la franja decia «Datos de
  /// las 8:46» con el Tablero al dia a las 9:07, porque se medía contra las NUEVE
  /// colecciones y una de ellas —`almacenes`— se refresca sola una vez por hora.
  ///
  /// **OBLIGATORIO Y SIN VALOR POR DEFECTO, a proposito.** Un defecto —cualquiera
  /// de los dos: las nueve, o ninguna— deja a la pantalla nueva midiendo contra
  /// algo que no es lo suyo **sin que nada falle**, que es exactamente el modo de
  /// fallo que esto viene a cerrar. Asi, quien anada una pantalla no tiene la
  /// opcion de olvidarlo: no compila.
  ///
  /// Si una pantalla de verdad no pinta nada de la copia —la puerta de acceso,
  /// Sincronizacion, el canal con PEDIDO, el mapa— eso se declara, y se declara
  /// con nombre: `ColeccionesDePantalla.ninguna`. Es una decision escrita, no un
  /// hueco (§4: «borrar no es decidir»).
  ///
  /// La lista lleva **todo** lo que alimenta algo de lo que se ve, aunque sea un
  /// dato de al lado. Quedarse corto hace que la franja se diga **mas fresca de
  /// lo que esta**, y ése es el único lado del que este aviso no puede
  /// equivocarse.
  final List<String> colecciones;

  /// El icono de la barra lateral. Solo hace falta si [enElMenu].
  final IconData? icono;

  /// Si sale en la barra lateral. **Reportes va a `false`**: el pliego (§8.1)
  /// dice que la pantalla existe pero NO esta en el menu; se llega por URL y
  /// desde las acciones rapidas del Panel.
  final bool enElMenu;

  /// Los roles a los que se le ENSENA en el menu. Vacio = a todos.
  ///
  /// Solo la del canal con PEDIDO lo usa hoy: `DESARROLLADOR` y `SUPER ADMIN`.
  /// Jose, 26/09/2026, entrando por URL y no encontrandola: «tampoco agregaste el
  /// link en el menu para poder verlo como super admin».
  ///
  /// **ESTO NO ES UN PERMISO Y NO PUEDE SERLO.** El rol viaja en el token del
  /// aparato y cualquiera con un editor de texto escribe el que quiera; esconder
  /// una entrada del menu no cierra nada, porque la ruta sigue alcanzable
  /// escribiendo la direccion. Sirve para **no estorbar**: que quien no tenga
  /// nada que hacer ahi no tropiece con una pantalla de colas y codigos HTTP.
  ///
  /// El cerrojo de verdad esta en la api —`auth.PuedeMirarElCanal`, que contesta
  /// 403— y es el que hay que cambiar si alguna vez hay que cerrar o abrir esto.
  /// Se prueba alli con los siete roles, uno a uno.
  final List<String> soloParaRoles;

  /// Si va DENTRO del armazon (barra lateral, barra superior y franja de
  /// estado). Lo normal es que si, y por eso es el valor por defecto.
  ///
  /// La unica que va a `false` hoy es la **pantalla de acceso**: las tres piezas
  /// del armazon salen de la sesion y de la base local, que es justo lo que no
  /// hay todavia cuando alguien esta mirando esa pantalla. Una pantalla con
  /// `conArmazon: false` se monta sola dentro de su propio `Scaffold`, que sigue
  /// poniendo `rutas.dart` y no ella — la regla de «tu pantalla no lleva
  /// Scaffold» no cambia.
  final bool conArmazon;

  /// Rutas colgando de esta, si tu pantalla las necesita.
  final List<RouteBase> subrutas;

  /// Lo que consume `rutas.dart`. Aqui y en ningun otro sitio se decide como se
  /// traduce una pantalla registrada a una ruta de go_router.
  GoRoute aGoRoute() =>
      GoRoute(path: ruta, builder: construir, routes: subrutas);
}
