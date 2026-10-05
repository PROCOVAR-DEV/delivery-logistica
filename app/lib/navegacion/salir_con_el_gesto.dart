// EL GESTO DE ATRAS NO SACA DE LA APLICACION SIN PREGUNTAR — 05/10/2026.
//
// Jose, probando la 1.0.22 en el telefono: «cuando salga de la aplicacion por el
// gesto de dar atras por favor q me salga un mensaje q se va a salir ook algo
// asi como estas seguro q queires salir **y si se pierde algo o no por salir**
// esas cosas las necesito».
//
// Las dos mitades del encargo son una pregunta y una respuesta, y la segunda es
// la que de verdad sirve: «¿estas seguro?» sin decir que se pierde es un peaje,
// no informacion — lo mismo que ya decia `diseno/preguntar_antes_de_borrar.dart`.
//
// ## POR QUE NO ES UN `PopScope`, que es lo primero que uno prueba
//
// Esto ya nos costo una vuelta y esta escrito en `diseno/cajon.dart`, que es de
// donde sale esta pieza; Jose lo recordaba al pedirlo («revisa q ya nos ah pasado
// antes creo q con retenless y el gesto de atras sigue sin sacarnos el cartel»).
// Resumido:
//
//  * `PopScope` se engancha al `popDisposition` de LA RUTA, o sea que se come
//    **todos** los `Navigator.maybePop()` de la casa. Puesto en el armazon, la ✕
//    de cualquier cajon y el `Cancelar` de cualquier pie sacarian el cartel de
//    «¿seguro que quieres salir?» en vez de cerrar su panel.
//  * `BackButtonListener` se engancha un piso mas arriba, en el
//    `BackButtonDispatcher` del `Router`, **que es por donde entra solo el atras
//    del sistema**. Los `maybePop` de la casa ni lo rozan.
//
// Asi que esto es un `BackButtonListener`, igual que `AtrasDelCajon`.
//
// Con una correccion honesta, comprobada mutandolo el mismo dia: **en ESTA
// posicion las dos cosas se portan igual**, porque el envoltorio cuelga de la
// pagina del `ShellRoute` y los `maybePop` que preocupaban en `cajon.dart` son de
// otras rutas —la del cajon, la de una subruta—, asi que no pasan por aqui. Un
// `PopScope` puesto aqui no se come la ✕ de nada, y cambiarlo no pone ninguna
// prueba en rojo.
//
// Se queda `BackButtonListener` por dos razones de diseno, que es lo que son:
//
//   1. Oye **solo el atras del sistema**, que es justo el alcance del encargo.
//      `PopScope` habla de popear rutas y su alcance depende de donde cuelgue:
//      hoy coincide, y el dia que el armazon se mueva —a `StatefulShellRoute`,
//      por ejemplo— deja de coincidir sin que nada avise.
//   2. El proyecto ya tiene `PopScope` por pantalla (`cierre_de_ruta.dart`,
//      `pantalla_rutas.dart`). Apilar otro arriba obliga a razonar como se
//      combinan; esto no se mezcla con ellos.
//
// Lo que NO se hace es fingir que hay una prueba que lo defiende. La hay para
// todo lo demas; para esto hay un motivo escrito, y la nota al final de
// `test/navegacion/salir_con_el_gesto_test.dart` lo dice tambien alli.
//
// ## Y POR QUE VA EN EL ARMAZON Y NO EN `app.dart`
//
// El sitio evidente seria el `builder:` de `MaterialApp.router`, que envuelve
// todas las pantallas. No vale: ese `builder` recibe el `Router` COMO HIJO, asi
// que su contexto esta **por encima** de el y `Router.maybeOf` devuelve `null`
// — no hay dispatcher al que engancharse y el gesto no se oiria nunca. Dentro
// del arbol del `Router`, el techo comun de todas las pantallas de trabajo es el
// armazon del `ShellRoute`, y ahi va.
//
// Lo que queda fuera es `/acceso`, que va `conArmazon: false`. Y esta bien, por
// lo mismo que el aviso de version nueva tampoco sale alli: en la puerta no hay
// trabajo que perder ni nada a medias, y preguntarle a alguien que no ha entrado
// si esta seguro de irse es un peaje puro.
//
// ## CUANDO SALE Y CUANDO NO
//
// Solo cuando el atras **iba a sacar de la aplicacion**, que es lo que pidio. Si
// hay algo que cerrar —un cajon abierto, una pantalla empujada encima— el gesto
// tiene que hacer su trabajo de siempre: se suelta devolviendo `false` y lo
// atiende quien toque. Eso lo contesta `GoRouter.canPop()`, que mira los
// navegadores de dentro hacia fuera; un cajon de esta casa entra por
// `showGeneralDialog`, o sea una ruta del navegador de arriba, y cuenta.
//
// Sin esa comprobacion, el primer atras de cualquier cajon abierto sacaria el
// cartel de salir por encima del cajon. Hay una prueba para cada lado.
//
// En la web esto no se ejecuta nunca, y no por un `if`: el atras del navegador
// es historial, le entra al `Router` por el `RouteInformationProvider` y no pasa
// por el dispatcher del boton. Tampoco habria nada que hacer — de un navegador
// no se «sale».
//
// ## QUE SE PIERDE AL SALIR: NADA, Y SE DICE ASI
//
// Es la trampa que ya se cayo una vez, el 17/09/2026, en el «Cerrar sesion» de
// `menu_de_cuenta.dart`: el cartel amenazaba con «se borra lo de este aparato y
// ese trabajo se pierde», y era mentira desde que cada persona tiene su propia
// base. Un aviso que amenaza con perder lo que no se pierde es PEOR que no
// avisar: se lee una vez, se comprueba que era mentira, y deja de leerse el dia
// que diga la verdad.
//
// Cerrar la aplicacion es todavia menos que cerrar sesion —aquello al menos
// revoca el token—: la base local y su cola se quedan enteras y vuelven al
// abrir. Asi que aqui el numero de apuntes sin subir se dice para **tranquilizar
// y para situar**, no para asustar: lo unico verdadero que pasa mientras no
// suban es que nadie mas los ve.
//
// Y cuando no queda nada pendiente se dice tambien, con esas palabras. Jose pidio
// «si se pierde algo o no»: «no» es una respuesta, y callarla obliga a deducirla.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../diseno/cajon.dart';
import '../diseno/tema.dart';
import '../nucleo/plataforma.dart';
import '../nucleo/proveedores.dart';

/// Envuelve [child] y pregunta antes de que el atras del sistema saque de la
/// aplicacion. Ver la cabecera del fichero.
class SalirConElGesto extends ConsumerStatefulWidget {
  const SalirConElGesto({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SalirConElGesto> createState() => _SalirConElGestoState();
}

class _SalirConElGestoState extends ConsumerState<SalirConElGesto> {
  /// Un cartel y no dos.
  ///
  /// El gesto se puede repetir mientras el cajon se esta abriendo —son 180 ms de
  /// animacion y un `await` a la base por medio—, y sin esto el segundo atras
  /// apila un cartel encima del otro: contestar «Me quedo» deja el de debajo
  /// puesto, y parece que la aplicacion no obedece.
  bool _preguntando = false;

  @override
  Widget build(BuildContext context) {
    // Sin `Router` no hay dispatcher que escuchar. Pasa en las pruebas que
    // montan el armazon dentro de un `MaterialApp` normal, y ahi no se finge
    // nada: no se pone el listener y el atras hace lo de siempre. La aplicacion
    // de verdad es `MaterialApp.router`.
    if (Router.maybeOf(context) == null) return widget.child;

    return BackButtonListener(
      onBackButtonPressed: _alDarAtras,
      child: widget.child,
    );
  }

  Future<bool> _alDarAtras() async {
    // Hay algo que cerrar: el atras es para eso, no para salir.
    if (GoRouter.of(context).canPop()) return false;

    // Ya hay un cartel puesto. Se da por atendido para que el gesto no caiga al
    // dispatcher de abajo y cierre la aplicacion por detras del cartel.
    if (_preguntando) return true;

    _preguntando = true;
    try {
      // LAS DOS CUENTAS, Y SEPARADAS. No es celo: `cuantosPendientes()` y
      // `cuantosRechazados()` tienen **respuestas distintas a «¿esto sube?»**, y
      // meterlas en un solo numero obliga al texto a mentirle a la mitad. Un
      // pendiente sube solo en cuanto haya senal; un rechazado NO sube nunca —
      // el servidor ya dijo que no y espera a que una persona decida en la
      // bandeja—. Decir «suben solos» de un rechazado es prometerle a alguien
      // que su trabajo esta en camino cuando esta parado.
      //
      // Por eso no se usa `cuantosSinSubir()`, que es justo la suma de los dos:
      // es la cuenta correcta para decidir si HAY algo (y la que usan el
      // arranque y el comprobador de version), pero no para explicarlo.
      final base = ref.read(baseProvider);
      final pendientes = await base.cuantosPendientes();
      final rechazados = await base.cuantosRechazados();
      if (!mounted) return true;

      final seVa = await _preguntar(
        context,
        pendientes: pendientes,
        rechazados: rechazados,
      );
      if (seVa) await SystemNavigator.pop();
    } finally {
      _preguntando = false;
    }
    // Atendido en los dos casos: si se queda, porque no hay que salir; si se va,
    // porque de salir ya se encargo `SystemNavigator.pop`.
    return true;
  }
}

/// El cartel. Suelto para poder probarlo sin gesto y sin `Router`.
///
/// Cerrar sin contestar —la ✕, tocar fuera, Escape— es **quedarse**: `abrirCajon`
/// devuelve `null` y aqui eso es `false`. Misma regla que al borrar.
Future<bool> _preguntar(
  BuildContext contexto, {
  required int pendientes,
  required int rechazados,
}) async {
  final seVa = await abrirCajon<bool>(
    contexto,
    titulo: '¿Salir de Reparto?',
    cuerpo: (contextoCajon) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(textoDeSalir(pendientes: pendientes, rechazados: rechazados)),
        const SizedBox(height: 20),
        BotonPrincipal(
          texto: 'Sí, salir',
          icono: Icons.logout,
          alPulsar: () => Navigator.of(contextoCajon).pop(true),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(contextoCajon).pop(false),
          child: const Text('Me quedo'),
        ),
      ],
    ),
  );
  return seVa ?? false;
}

/// Lo que dice el cartel. Aparte y publico para poder atarlo con pruebas sin
/// montar pantalla: es la mitad del encargo —«y si se pierde algo o no»— y es la
/// que ya salio mal una vez por amenazar con una perdida que no ocurre.
@visibleForTesting
String textoDeSalir({required int pendientes, required int rechazados}) {
  // En la web la cola es un sitio de paso —cada gesto sale en el momento—, asi
  // que algo dentro no es trabajo guardado: es un cambio que NO se pudo guardar,
  // y ahi si se pierde al cerrar la pestana. Por eso no dice lo mismo (§1 y
  // §3-quinquies del CLAUDE.md). No deberia verse nunca —el atras del navegador
  // es historial y no llega hasta aqui— pero el texto no puede mentir segun
  // donde se lea, y la web es el unico sitio donde la respuesta honesta a «¿se
  // pierde algo?» es SI.
  if (!Destino.trabajaSinConexion) {
    final sinLlegar = pendientes + rechazados;
    if (sinLlegar == 0) {
      return 'Todo lo que hiciste ya está en el servidor.\n\n'
          'Cerrar no pierde nada.';
    }
    return 'Hay ${_apuntes(sinLlegar)} que no llegaron al servidor. Si cierras '
        'ahora se pierden.\n\n'
        'Vuelve a intentarlo desde la pantalla donde los hiciste.';
  }

  if (pendientes == 0 && rechazados == 0) {
    return 'No queda nada sin subir: todo lo que hiciste ya está en el '
        'servidor.\n\nSalir no pierde nada.';
  }

  // Lo primero es la respuesta a lo que pregunto, y es la misma en los tres
  // casos que quedan: NO SE PIERDE NADA. Lo de despues es que le pasa a cada
  // cosa, que no es lo mismo para un pendiente que para un rechazado.
  final partes = <String>[
    'Salir no borra nada: lo que hay se queda en este '
        'aparato y vuelve al abrir.',
  ];

  if (pendientes > 0) {
    partes.add(
      'Quedan ${_apuntes(pendientes)} sin subir: suben solos la próxima vez '
      'que abras con señal. Lo único que pasa mientras es que nadie más los ve.',
    );
  }

  if (rechazados > 0) {
    partes.add(
      'Y ${_apuntes(rechazados)} que el servidor rechazó. Ésos NO suben solos: '
      'esperan a que decidas tú, en la bandeja.',
    );
  }

  return partes.join('\n\n');
}

String _apuntes(int cuantos) => cuantos == 1 ? '1 apunte' : '$cuantos apuntes';
