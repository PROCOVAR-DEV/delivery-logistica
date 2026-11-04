import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'diseno/tema.dart';
import 'navegacion/pantalla_registrada.dart';
import 'navegacion/portero.dart';
import 'navegacion/rutas.dart';
import 'nucleo/proveedores.dart';
import 'nucleo/sincro/vigia.dart';
import 'idioma.dart';

/// La aplicacion.
///
/// `MaterialApp.router` y no `MaterialApp` porque en web la URL tiene que ser de
/// verdad: los filtros de las listas viajan en la direccion, y una pantalla
/// filtrada que no se puede mandar por enlace deja a media oficina leyendo
/// numeros por telefono.
class RepartoApp extends ConsumerStatefulWidget {
  const RepartoApp({
    super.key,
    this.enrutador,
    this.pantallas,
    this.inicial,
    this.enlaceDeEntrada,
    this.alrededor,
  });

  /// «Reparto Distribuidor» (`main_distribuidor.dart`): su lista de pantallas, su
  /// inicio, el enlace con el que se abrio y un envoltorio de la app (aviso de
  /// ubicacion y GPS; va DENTRO del `MaterialApp`, con su tema). El portero y el vigia se montan IGUAL que en la de siempre.
  final List<PantallaRegistrada>? pantallas;
  final String? inicial;
  final String? enlaceDeEntrada;
  final Widget Function(Widget app)? alrededor;

  /// Se puede inyectar en los tests para montar el armazon con pantallas de
  /// mentira.
  final GoRouter? enrutador;

  @override
  ConsumerState<RepartoApp> createState() => _RepartoAppState();
}

class _RepartoAppState extends ConsumerState<RepartoApp> {
  late final GoRouter _enrutador =
      widget.enrutador ??
      crearEnrutador(
        portero: ref.read(porteroProvider),
        pantallas: widget.pantallas,
        inicial: widget.inicial ?? rutaDeInicio,
        enlaceDeEntrada: widget.enlaceDeEntrada,
      );

  /// El aviso de red y el reloj del ciclo. Se montan aqui y no en el portero
  /// porque quien sabe si la aplicacion esta delante es el widget, y porque asi
  /// una prueba que inyecta su enrutador no levanta ni un temporizador.
  Portero? _portero;
  VigiaDeSincronizacion? _vigia;
  AppLifecycleListener? _ciclosDeVida;

  @override
  void initState() {
    super.initState();
    // EL ARRANQUE, una sola vez y aqui: abre la base, lee la sesion guardada e
    // intenta renovar. Mientras tanto se ve la espera; al acabar, el portero
    // mueve la aplicacion al Panel o al acceso.
    if (widget.enrutador == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(porteroProvider).comprobar(),
      );

      _vigia = ref.read(vigiaProvider);
      final portero = ref.read(porteroProvider)..addListener(_segunElAcceso);
      _portero = portero;
      _ciclosDeVida = AppLifecycleListener(
        onStateChange: (estado) =>
            _vigia?.enPrimerPlano(estado == AppLifecycleState.resumed),
      );
    }
  }

  /// Con sesion se vigila; sin ella, **no queda nada vivo**. Un temporizador que
  /// sobrevive a la salida es trabajo corriendo sobre una sesion muerta.
  void _segunElAcceso() {
    if (_portero?.estado == EstadoDeAcceso.dentro) {
      _vigia?.arrancar();
    } else {
      _vigia?.parar();
    }
  }

  @override
  void dispose() {
    _portero?.removeListener(_segunElAcceso);
    _ciclosDeVida?.dispose();
    _vigia?.parar();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Reparto',
    debugShowCheckedModeBanner: false,
    theme: temaDeReparto(),
    // El papel con su rejilla, DEBAJO de todas las pantallas y por encima de
    // nada. Va aqui, en el `builder`, y no en cada `Scaffold`: asi lo tienen
    // tambien los cajones y los menus, que se pintan fuera del arbol de la
    // pantalla.
    builder: (contexto, pantalla) => FondoDePapel(
      child: widget.alrededor?.call(pantalla ?? const SizedBox.shrink()) ??
          pantalla ??
          const SizedBox.shrink(),
    ),
    // ESPANOL Y NADA MAS. Las delegaciones son las de MATERIAL, no unas
    // nuestras: sin ellas Flutter cae en `DefaultMaterialLocalizations`, que
    // solo sabe ingles, y los cinco calendarios de la aplicacion saldrian con
    // `January` y `Cancel` dentro de una pantalla en espanol. El porque de que
    // aqui no haya traduccion esta escrito en `lib/idioma.dart`.
    localizationsDelegates: delegacionesDeIdioma,
    supportedLocales: idiomas,
    routerConfig: _enrutador,
  );
}
