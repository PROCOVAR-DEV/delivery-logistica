import 'package:flutter/material.dart';

import 'anchos.dart';
import 'colores.dart';
import 'tema.dart';

/// EL CAJON. **Siempre cajon, nunca `AlertDialog`** (pliego §9.2).
///
/// En el resto de Procovar la regla es modal en escritorio y cajon por debajo de
/// 1024 px. Delivery es una **excepcion aprobada el 05/09/2026**: aqui es cajon
/// tambien en escritorio. El motivo es de uso, no de gusto: estos paneles llevan
/// listas largas (las paradas de una ruta, los renglones de un pedido) y un
/// modal centrado con scroll interno es peor que un panel a alto completo.
///
/// Estructura fija: cabecera (titulo + subtitulo + cerrar), cuerpo desplazable y
/// pie opcional pegado abajo con los botones **siempre a la vista**.
Future<T?> abrirCajon<T>(
  BuildContext contexto, {
  required String titulo,
  required WidgetBuilder cuerpo,
  String? subtitulo,
  WidgetBuilder? pie,
  AnchoCajon ancho = AnchoCajon.lg,
}) {
  return abrirPanel<T>(
    contexto,
    (contextoCajon) => Cajon(
      titulo: titulo,
      subtitulo: subtitulo,
      ancho: ancho,
      pie: pie?.call(contextoCajon),
      child: cuerpo(contextoCajon),
    ),
  );
}

/// La misma puerta que [abrirCajon] —el mismo velo, la misma entrada— pero es
/// **quien llama el que construye el [Cajon]**.
///
/// Hace falta cuando la cabecera, el cuerpo y el pie comparten estado. En
/// [abrirCajon] el titulo es un `String` y el cuerpo y el pie son dos
/// constructores distintos que se llaman por separado, asi que el `Guardar` del
/// pie no puede mirar lo que hay escrito en un campo del cuerpo: para saber si
/// se habilita tendria que leer un estado que no ve. Con esto el
/// `StatefulWidget` devuelve el [Cajon] entero y un solo `setState` repinta los
/// tres a la vez. Asi entran la ficha de vehiculo, los tipos de vehiculo y el
/// editor de almacen.
///
/// No es una segunda forma de cajon: lo que se devuelve sigue siendo un
/// [Cajon], con su cabecera del pliego §9.2 y su ✕ que no desaparece.
Future<T?> abrirPanel<T>(BuildContext contexto, WidgetBuilder panel) {
  return showGeneralDialog<T>(
    context: contexto,
    // El velo negro al 40 % del pliego. `barrierDismissible` da las dos cosas
    // que pide §9.2 de una vez: pulsar fuera cierra y Escape cierra (el
    // `ModalBarrier` de Flutter atiende el `DismissIntent` del teclado).
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: Colores.tinta.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 180),
    // TODO CAJON VIENE ENVUELTO EN [AtrasDelCajon], y no es opcional: es lo que
    // hace que el cajon se vaya con la pantalla sobre la que se abrio. El porque
    // esta entero en el comentario de esa clase.
    pageBuilder: (contextoPanel, _, _) =>
        AtrasDelCajon(child: panel(contextoPanel)),
    transitionBuilder: (_, animacion, _, hijo) {
      // Entra desde 24 px a la derecha, 180 ms. Los mismos numeros del pliego:
      // lo bastante para que se lea «viene de fuera» y no tanto como para
      // esperarlo cincuenta veces al dia.
      final curva = CurvedAnimation(
        parent: animacion,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curva,
        child: Padding(
          padding: EdgeInsets.only(left: 24 * (1 - curva.value)),
          child: hijo,
        ),
      );
    },
  );
}

/// EL «ATRAS» ES DEL CAJON, NO DE LA PANTALLA DE DEBAJO — 28/09/2026.
///
/// Jose, con el asistente de nueva ruta abierto: «dar atras cuando estoy en un
/// drawer no sale del drawer sigue trabajando atras arregla eso tambien», «y
/// tiene q ir al paso anterior de el drawer». Son dos cosas y las dos pasan por
/// aqui.
///
/// ## 1. El cajon se va con la pantalla sobre la que se abrio
///
/// El cajon se abre con `showGeneralDialog`, o sea que es una ruta **sin
/// pagina** colgada del `Navigator` de arriba. En el telefono eso basta: el
/// atras del sistema llega como `didPopRoute`, go_router se lo pasa al
/// `Navigator` raiz y el cajon —que es lo de arriba— se cierra. En el navegador
/// **no**: el atras del navegador no dispara ningun `popRoute`, cambia la
/// direccion. go_router repinta la pantalla de debajo con la anterior y el
/// cajon, que no esta en el historial del navegador, **se queda puesto encima**.
/// Reproducido el 28/09/2026 en `test/diseno/atras_en_el_cajon_test.dart`: con
/// el cajon abierto sobre `/detalle` y el atras del navegador, la pantalla pasa
/// a `/lista` y el cajon sigue ahi. Eso es literalmente «no sale del drawer,
/// sigue trabajando atras».
///
/// Asi que el cajon se vigila la direccion: **si cambia la pantalla de debajo,
/// el cajon se cierra**. Se mira el CAMINO y no la direccion entera a proposito:
/// los filtros de las listas viajan en la parte de despues del `?`
/// (`/orders?municipio=…`), y hay cajones —el de filtros del telefono— que
/// existen justo para cambiarlos. Comparando la direccion entera, tocar un
/// filtro dentro del cajon lo cerraria de golpe en la cara. Las dos mitades se
/// prueban juntas: cambia el camino y se cierra; cambian solo los filtros y NO
/// se cierra.
///
/// Se cierra **esta** ruta y solo esta (`isActive`, y `removeRoute` si ya no es
/// la de arriba), nunca con un `pop` a ciegas: un `pop` cuando el cajon ya no
/// esta se lleva por delante la pantalla de debajo, que es el fallo del
/// 28/09/2026 con los selectores.
///
/// ## 2. Con pasos, atras va al paso anterior
///
/// El asistente de nueva ruta son 4 pasos DENTRO de un cajon. Estando en el 3,
/// atras cerraba el asistente entero y se perdia lo elegido. Quien tenga pasos
/// se envuelve en esto con [quedaPasoAtras] y [atras], y el cajon se queda con
/// el gesto mientras quede paso; en el primero lo suelta y el cajon se cierra
/// como siempre. Es generico a proposito: el cajon no sabe que hay un asistente
/// dentro, solo pregunta «¿te queda paso atras?».
///
/// ### Por que NO es un `PopScope`, que es lo primero que uno prueba
///
/// `PopScope` se engancha al `popDisposition` de la ruta, o sea que se come
/// **todos** los `Navigator.maybePop()` de la casa, no solo el gesto de atras.
/// Y la ✕ de la cabecera de los dos cajones de este proyecto —el de aqui y el
/// de `pantallas/pedidos/vista/kit.dart`, que es el que usa el asistente— cierra
/// con `maybePop()`. Con un `PopScope` puesto, la ✕ del asistente en el paso 3
/// **retrocederia un paso en vez de cerrar**, y la ✕ es la unica salida
/// garantizada cuando el teclado tapa media pantalla (§9.2). Lo mismo el
/// `Cancelar` del pie.
///
/// `BackButtonListener` se engancha un piso mas arriba, en el
/// `BackButtonDispatcher` del `Router`, que es por donde entra **solo el atras
/// del sistema**. Los `maybePop` de la casa ni lo rozan. Por eso la ✕ se queda
/// como estaba y hay una prueba que lo ata: «la ✕ cierra el cajon entero aunque
/// queden pasos».
///
/// El `PopScope` queda de red para un arbol **sin `Router`** (un `MaterialApp`
/// normal, como los de algunas pruebas): ahi no hay dispatcher que escuchar y el
/// atras entra por `WidgetsApp.didPopRoute` → `maybePop`, asi que el `PopScope`
/// es el unico sitio donde cazarlo. La aplicacion de verdad es
/// `MaterialApp.router` y va siempre por el primer camino.
class AtrasDelCajon extends StatefulWidget {
  const AtrasDelCajon({
    required this.child,
    this.quedaPasoAtras = false,
    this.atras,
    super.key,
  });

  final Widget child;

  /// Lo que el contenido del cajon contesta a «¿te queda paso atras?». Mientras
  /// sea `true` el cajon se queda con el gesto; en `false` lo suelta y atras
  /// cierra.
  final bool quedaPasoAtras;

  /// Que hacer con el atras en vez de cerrar. Sin esto el cajon solo se vigila
  /// la pantalla de debajo, que es lo que quiere el 99 % de los cajones.
  final VoidCallback? atras;

  @override
  State<AtrasDelCajon> createState() => _AtrasDelCajonState();
}

class _AtrasDelCajonState extends State<AtrasDelCajon> {
  ModalRoute<dynamic>? _ruta;
  RouteInformationProvider? _direccion;

  /// El camino sobre el que se abrio este cajon. No se actualiza nunca: el cajon
  /// muere en el primer cambio, asi que solo hace falta el de la apertura.
  String? _pantallaDeAbajo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ruta = ModalRoute.of(context);

    // Se lee del `Router` y no de go_router: `lib/diseno/` no conoce el
    // enrutador de la aplicacion, y `routeInformationProvider` es lo que cambia
    // tanto con el atras del navegador como con un `context.go` de dentro.
    final direccion = Router.maybeOf(context)?.routeInformationProvider;
    if (!identical(direccion, _direccion)) {
      _direccion?.removeListener(_siCambioLaPantallaDeAbajo);
      _direccion = direccion;
      _pantallaDeAbajo = direccion?.value.uri.path;
      direccion?.addListener(_siCambioLaPantallaDeAbajo);
    }
  }

  @override
  void dispose() {
    _direccion?.removeListener(_siCambioLaPantallaDeAbajo);
    super.dispose();
  }

  void _siCambioLaPantallaDeAbajo() {
    final ahora = _direccion?.value.uri.path;
    if (ahora == null || ahora == _pantallaDeAbajo) return;
    // El aviso llega en mitad del fotograma en el que el enrutador esta
    // rehaciendo sus paginas. Quitar una ruta ahi mismo es marcar el `Navigator`
    // para reconstruir mientras se construye, y Flutter lo corta en seco. Se
    // espera a que termine el fotograma.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cerrarEsteCajonYNadaMas();
    });
  }

  /// Cierra ESTA ruta, y solo esta.
  ///
  /// Nunca `Navigator.pop()` a secas: si el cajon ya no esta —porque lo cerro la
  /// ✕ medio segundo antes, o porque la pantalla se fue— ese `pop` se lleva la
  /// pantalla de debajo. Con dos rutas apiladas eso se ve; con una sola el
  /// `Navigator` se niega a dejar la pila vacia y el fallo **sale verde**.
  void _cerrarEsteCajonYNadaMas() {
    final ruta = _ruta;
    if (ruta == null || !ruta.isActive) return;
    // Si es la de arriba se cierra con su animacion de salida; si le han puesto
    // otro cajon encima, se saca de la pila sin tocar al de arriba.
    if (ruta.isCurrent) {
      ruta.navigator?.pop();
    } else {
      ruta.navigator?.removeRoute(ruta);
    }
  }

  /// `true` = me quedo con el atras. `false` = que siga su camino y cierre el
  /// cajon como siempre.
  Future<bool> _alDarAtras() async {
    // Con otro cajon abierto encima, el atras es del de arriba. Sin esto, el
    // asistente retrocederia un paso por detras de un cajon que sigue puesto.
    final ruta = _ruta;
    if (ruta != null && !ruta.isCurrent) return false;
    if (!widget.quedaPasoAtras) return false;
    widget.atras?.call();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Sin pasos no hay nada que interceptar: este cajon solo se vigila la
    // pantalla de debajo.
    if (widget.atras == null) return widget.child;

    if (Router.maybeOf(context) != null) {
      return BackButtonListener(
        onBackButtonPressed: _alDarAtras,
        child: widget.child,
      );
    }
    // La red de abajo, para un arbol sin `Router`. Ojo: aqui SI se comen los
    // `maybePop` de la casa, incluida la ✕.
    return PopScope(
      canPop: !widget.quedaPasoAtras,
      onPopInvokedWithResult: (seFue, _) {
        if (seFue) return;
        widget.atras?.call();
      },
      child: widget.child,
    );
  }
}

/// El panel en si. Se expone suelto para poder probarlo sin abrir una ruta.
class Cajon extends StatelessWidget {
  const Cajon({
    required this.titulo,
    required this.child,
    this.subtitulo,
    this.pie,
    this.ancho = AnchoCajon.lg,
    super.key,
  });

  final String titulo;
  final String? subtitulo;
  final Widget child;
  final Widget? pie;
  final AnchoCajon ancho;

  @override
  Widget build(BuildContext context) {
    final anchoPantalla = MediaQuery.sizeOf(context).width;
    // En movil la pantalla entera, sin excepciones: un panel de 448 px sobre una
    // pantalla de 390 px es un panel de 390 px con los bordes cortados.
    final anchoUtil = anchoPantalla < Anchos.escritorio
        ? anchoPantalla
        : (ancho.px.isFinite ? ancho.px : anchoPantalla);

    // EL TECLADO NO PUEDE TAPAR EL PIE — 17/09/2026.
    //
    // El cajon se abre con `showGeneralDialog`, o sea que vive en el `Overlay`
    // y **no dentro del `body` del `Scaffold`**. Esa es toda la diferencia: al
    // `body` el `Scaffold` le quita el alto del teclado (`resizeToAvoidBottom
    // Inset`), al `Overlay` no le quita nada. Asi que en un telefono, en cuanto
    // alguien tocaba un campo, el panel seguia midiendo los 844 px de la
    // pantalla entera y el pie —con el «Guardar»— se quedaba en el pixel 800,
    // trescientos por debajo del borde del teclado. No se podia pulsar, y
    // tampoco se llegaba desplazando: el cuerpo no habia encogido, asi que no
    // habia nada que desplazar.
    //
    // Medido a 390x844 con el teclado de 336 px: «Guardar» en y=799..817 y el
    // teclado tapando desde y=508.
    //
    // Se aparta el panel ENTERO y no solo el pie: asi el cuerpo desplazable
    // encoge con el, y lo ultimo del formulario se alcanza desplazando en vez
    // de quedar debajo de las teclas.
    final teclado = MediaQuery.viewInsetsOf(context).bottom;

    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(bottom: teclado),
        child: DecoratedBox(
          // `shadow-2xl` y el borde fino a la izquierda: sobre el velo al 40 % un
          // panel blanco sin sombra se pega al borde de la pantalla y no se lee
          // como algo que esta POR ENCIMA de la lista.
          decoration: BoxDecoration(
            color: Colores.blanco,
            border: Border(left: BorderSide(color: Colores.linea)),
            boxShadow: Sombras.xl,
          ),
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: anchoUtil,
              height: double.infinity,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Cabecera(titulo: titulo, subtitulo: subtitulo),
                    Divider(height: 1, thickness: 1, color: Colores.linea),
                    // El cuerpo es lo unico que se desplaza.
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          Aire.xl,
                          Aire.lg,
                          Aire.xl,
                          Aire.xl,
                        ),
                        child: child,
                      ),
                    ),
                    if (pie != null) ...[
                      Divider(height: 1, thickness: 1, color: Colores.linea),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Aire.xl,
                          vertical: Aire.md,
                        ),
                        child: pie,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.titulo, this.subtitulo});

  final String titulo;
  final String? subtitulo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Aire.xl, Aire.lg, Aire.sm, Aire.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tema.textTheme.titleMedium,
                ),
                if (subtitulo != null)
                  Text(
                    subtitulo!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: Colores.tintaSuave,
                    ),
                  ),
              ],
            ),
          ),
          // La ✕ NUNCA puede desaparecer: es la unica salida garantizada cuando
          // el teclado del telefono tapa media pantalla.
          IconButton(
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close, size: 20),
            color: Colores.tintaSuave,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
