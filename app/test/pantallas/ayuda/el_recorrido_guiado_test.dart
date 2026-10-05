// EL RECORRIDO GUIADO, MONTADO. Lo que de verdad va a ver el logistico de Santiago.
//
// Se monta a 390 px con un enrutador de verdad, porque el recorrido empieza con un
// `context.go` y vive en el `Overlay` de la raiz: sin enrutador no hay ninguna de
// las dos cosas.
//
// Las dos trampas del §5 de `CLAUDE.md` no aplican —esta pantalla no toca la base
// local, el manual viene de un asset— pero la tercera sI: **`rootBundle.loadString`
// dentro de un `testWidgets` cuelga la prueba**, asi que el manual se le pasa al
// proveedor ya leido y nunca se lee del paquete aqui.
//
// Y se desmonta al final: una capa del `Overlay` que se queda puesta se arrastra a
// la prueba siguiente y la hace fallar por un motivo que no es el suyo.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:reparto/pantallas/ayuda/datos/empaquetado.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';
import 'package:reparto/pantallas/ayuda/datos/proveedores.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';
import 'package:reparto/pantallas/ayuda/vista/pantalla_guia.dart';
import 'package:reparto/pantallas/ayuda/vista/recorrido_guiado.dart';

const _telefono = Size(390, 800);

/// Los nombres de los controles de mentira. **No se usan los de `Senalado`** a
/// proposito: esta prueba comprueba el mecanismo, no el catalogo. Que los nombres
/// del catalogo esten envueltos de verdad lo ata
/// `los_pasos_senalan_controles_que_existen_test.dart`.
const _elBotonBueno = 'prueba-boton-bueno';
const _elQueNoEstaMarcado = 'prueba-no-marcado';
const _elDeAbajo = 'prueba-el-de-abajo';

/// UN CONTROL PEGADO AL BORDE DE ABAJO, fuera del desplazable.
///
/// Existe por una mutación que salió verde: con la tarjeta del paso puesta SIEMPRE
/// abajo, la prueba de «no tapa el control» pasaba igual, porque el único control
/// que se comprobaba estaba arriba. Con éste, el paso que lo señala obliga a que la
/// tarjeta se vaya ARRIBA, que es la mitad de la regla que no se estaba midiendo.
const _elPegadoAbajo = 'prueba-pegado-abajo';

const _pantallas = <PantallaDelMenu>[
  PantallaDelMenu('/vehicles', 'Vehículos'),
  PantallaDelMenu('/guia', 'Guía'),
];

final _paginas = <String, String>{
  'apk/3-tareas.md':
      '''
# Tareas sueltas

## Dar de alta un camión
$marcaDeTarea

**Empieza en:** **Menú → «Vehículos»**. **Necesita señal.**

1. Toca **«Nuevo vehículo»**, arriba a la derecha. <!-- señala: $_elBotonBueno -->
2. Escribe la matrícula. <!-- señala: $_elQueNoEstaMarcado -->
3. Baja y toca **«Guardar»**. <!-- señala: $_elDeAbajo -->
4. Y por último, toca **«Entregar»**, abajo del todo. <!-- señala: $_elPegadoAbajo -->

## Mirar el canal con PEDIDO
$marcaDeTarea

**Empieza en:** **Menú → «Canal con PEDIDO»**.

1. Mira la cola. <!-- señala: $_elBotonBueno -->

## Reordenar las zonas
$marcaDeTarea

**Empieza en:** **Menú → «Vehículos»**.

No se puede desde el teléfono: hace falta pantalla grande.
''',
};

final _idDelCamion = 'apk/3-tareas.md~dar-de-alta-un-camión';
final _idDelCanal = 'apk/3-tareas.md~mirar-el-canal-con-pedido';
final _idSinPasos = 'apk/3-tareas.md~reordenar-las-zonas';

String _direccionDeTarea(String id) =>
    Uri(path: PantallaGuia.ruta, queryParameters: {'tarea': id}).toString();

Manual _manualDePrueba() => Manual.desdeElPaquete(
  empaquetarManual(_paginas),
  pantallas: _pantallas,
).paraLaForma(FormaDeLaAplicacion.apk);

/// LA PANTALLA DE VEHICULOS DE MENTIRA, con sus controles marcados.
///
/// El de abajo esta a 1.200 px dentro de un `ListView` de 800: fuera de la vista, a
/// proposito. Es el caso que obliga a `Scrollable.ensureVisible`, y sin un control
/// ahi abajo esa mitad del recorrido no se comprueba.
class _VehiculosDeMentira extends StatelessWidget {
  const _VehiculosDeMentira();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                ControlSenalado(
                  nombre: _elBotonBueno,
                  child: ElevatedButton(
                    onPressed: () {},
                    child: const Text('Nuevo vehículo'),
                  ),
                ),
                const SizedBox(height: 1200),
                ControlSenalado(
                  nombre: _elDeAbajo,
                  child: ElevatedButton(
                    onPressed: () {},
                    child: const Text('Guardar'),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Pegado al borde de abajo, fuera del desplazable.
        ControlSenalado(
          nombre: _elPegadoAbajo,
          child: ElevatedButton(
            onPressed: () {},
            child: const Text('Entregar'),
          ),
        ),
      ],
    ),
  );
}

Future<void> _montar(WidgetTester tester, {String? donde}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = _telefono;
  addTearDown(tester.view.reset);
  // El registro es global: si una prueba deja contextos muertos, la siguiente ve
  // «dos a la vez» donde hay uno y el foco desaparece sin motivo.
  addTearDown(RegistroDeControles.vaciar);
  addTearDown(Recorrido.salir);

  final enrutador = GoRouter(
    initialLocation: donde ?? PantallaGuia.ruta,
    routes: [
      GoRoute(
        path: PantallaGuia.ruta,
        builder: (_, _) => const Scaffold(body: PantallaGuia()),
      ),
      GoRoute(
        path: '/vehicles',
        builder: (_, _) => const _VehiculosDeMentira(),
      ),
    ],
  );
  addTearDown(enrutador.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        formaDeLaAplicacionProvider.overrideWithValue(FormaDeLaAplicacion.apk),
        manualProvider.overrideWith((ref) => _manualDePrueba()),
      ],
      child: MaterialApp.router(routerConfig: enrutador),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
}

/// Abre la tarea y arranca el recorrido.
Future<void> _empezarElRecorrido(WidgetTester tester, String id) async {
  await _montar(tester, donde: _direccionDeTarea(id));
  await tester.tap(find.byKey(ClavesDeLaGuia.guiarme));
  await tester.pumpAndSettle();
}

void main() {
  /// EL ENCARGO, EN UNA PRUEBA: te lleva a la pantalla Y te senala el control.
  ///
  /// Jose, 05/10/2026: «las cosas q tienen botones me mueven a la página pero no me
  /// dice paso a paso con sus tooltips señalándome paso a paso en la aplicación cada
  /// botón q debo tocar».
  testWidgets('te lleva a la pantalla y pone el foco encima del control', (
    tester,
  ) async {
    await _empezarElRecorrido(tester, _idDelCamion);

    // 1. esta en la pantalla de la tarea, no en la Guia.
    expect(find.text('Nuevo vehículo'), findsOneWidget);

    // 2. el paso se ve ENCIMA de la aplicacion, y dice por donde va.
    expect(find.textContaining('Toca'), findsWidgets);
    expect(find.text(TextosDelRecorrido.cualDeCuantos(1, 4)), findsOneWidget);

    // 3. Y EL FOCO ESTA PUESTO, que es lo que no habia.
    expect(
      find.byKey(ClavesDelRecorrido.foco),
      findsOneWidget,
      reason:
          'sin el anillo esto vuelve a ser un texto encima de una pantalla, que es '
          'justo lo que Jose rechazo de la 1.0.22',
    );
  });

  /// Y EL ANILLO ESTA DONDE ESTA EL BOTON, no en una esquina.
  testWidgets('el foco rodea al control de verdad, no a otra cosa', (
    tester,
  ) async {
    await _empezarElRecorrido(tester, _idDelCamion);

    final boton = tester.getRect(find.text('Nuevo vehículo'));
    final foco = tester.getRect(find.byKey(ClavesDelRecorrido.foco));
    expect(
      foco.contains(boton.center),
      isTrue,
      reason:
          'el anillo esta en $foco y el boton que senala, en $boton. Un recorrido '
          'que apunta al sitio equivocado es peor que uno que no apunta.',
    );
  });

  testWidgets('un paso cada vez, con siguiente y atras, y «3 de 7»', (
    tester,
  ) async {
    await _empezarElRecorrido(tester, _idDelCamion);

    expect(find.text(TextosDelRecorrido.cualDeCuantos(1, 4)), findsOneWidget);
    expect(find.textContaining('Nuevo vehículo'), findsWidgets);
    // En el primer paso no hay «Atrás»: no hay a donde volver.
    expect(find.byKey(ClavesDelRecorrido.atras), findsNothing);

    await tester.tap(find.byKey(ClavesDelRecorrido.siguiente));
    await tester.pumpAndSettle();
    expect(find.text(TextosDelRecorrido.cualDeCuantos(2, 4)), findsOneWidget);
    expect(find.textContaining('matrícula'), findsOneWidget);
    expect(find.byKey(ClavesDelRecorrido.atras), findsOneWidget);

    await tester.tap(find.byKey(ClavesDelRecorrido.atras));
    await tester.pumpAndSettle();
    expect(find.text(TextosDelRecorrido.cualDeCuantos(1, 4)), findsOneWidget);
  });

  /// EL CONTROL QUE ESTA FUERA DE LA VISTA SE TRAE A LA VISTA ANTES DE SENALARLO.
  ///
  /// El de la prueba esta a 1.200 px de arriba, en una pantalla de 800: construido
  /// pero fuera de lo que se ve. Senalarlo sin desplazar seria poner el anillo
  /// fuera de la pantalla, o recortado contra el borde.
  ///
  /// **Se mira el rectangulo, no `find.text`.** Un widget construido lo encuentra
  /// `find` este donde este, asi que comprobarlo con `findsNothing` no comprueba
  /// nada de la vista: es la trampa de «una prueba que copia la direccion del
  /// codigo que prueba» (§5) con otra cara.
  testWidgets('el control de abajo se trae a la vista antes de senalarlo', (
    tester,
  ) async {
    await _empezarElRecorrido(tester, _idDelCamion);
    final alto = _telefono.height;
    expect(
      tester.getRect(find.text('Guardar')).top,
      greaterThan(alto),
      reason:
          'tiene que empezar FUERA de la vista, o no hay nada que desplazar',
    );

    await tester.tap(find.byKey(ClavesDelRecorrido.siguiente));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ClavesDelRecorrido.siguiente));
    await tester.pumpAndSettle();

    expect(find.text(TextosDelRecorrido.cualDeCuantos(3, 4)), findsOneWidget);
    final boton = tester.getRect(find.text('Guardar'));
    expect(
      boton.top >= 0 && boton.bottom <= alto,
      isTrue,
      reason:
          'no lo trajo a la vista: se quedo en $boton con la pantalla de $alto',
    );
    final foco = tester.getRect(find.byKey(ClavesDelRecorrido.foco));
    expect(foco.contains(boton.center), isTrue);
  });

  /// LA TARJETA NO TAPA LO QUE SENALA. Si lo tapa, el recorrido no sirve de nada.
  testWidgets('la tarjeta del paso no se pone encima del control', (
    tester,
  ) async {
    await _empezarElRecorrido(tester, _idDelCamion);

    final boton = tester.getRect(find.text('Nuevo vehículo'));
    final tarjeta = tester.getRect(find.byKey(ClavesDelRecorrido.tarjeta));
    expect(
      tarjeta.overlaps(boton),
      isFalse,
      reason:
          'la tarjeta del paso ($tarjeta) se solapa con el control que senala '
          '($boton). «Si el paso dice «toca la pastilla de la sucursal», la '
          'pastilla tiene que verse».',
    );
  });

  /// EL AGUJERO DEL VELO DEJA PASAR EL DEDO, y lo de alrededor NO.
  ///
  /// Es lo que hace que el recorrido se siga **tocando de verdad** y no mirandolo:
  /// Jose va a pulsar el boton que le senalan. Y la otra mitad importa igual: con el
  /// resto de la pantalla sordo, nadie puede desplazar la lista por debajo del foco y
  /// dejar el anillo senalando un hueco.
  ///
  /// Se mide **pulsando**, no mirando el arbol: un velo con su agujero dibujado pero
  /// sin recortar sigue comiendose el toque, y eso no se ve en ningun `find`. La
  /// mutacion que dejo el velo de una pieza salia VERDE con las otras once pruebas
  /// (05/10/2026).
  testWidgets('el dedo pasa por el agujero y no por el resto del velo', (
    tester,
  ) async {
    var tocadoElBueno = 0;
    var tocadoElDeAbajo = 0;
    RegistroDeControles.vaciar();
    addTearDown(RegistroDeControles.vaciar);
    addTearDown(Recorrido.salir);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = _telefono;
    addTearDown(tester.view.reset);

    late final OverlayState capa;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (contexto) {
              capa = Overlay.of(contexto, rootOverlay: true);
              return Column(
                children: [
                  ControlSenalado(
                    nombre: _elBotonBueno,
                    child: ElevatedButton(
                      onPressed: () => tocadoElBueno++,
                      child: const Text('Nuevo vehículo'),
                    ),
                  ),
                  ControlSenalado(
                    nombre: _elDeAbajo,
                    child: ElevatedButton(
                      onPressed: () => tocadoElDeAbajo++,
                      child: const Text('Guardar'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tarea = _manualDePrueba().tarea(_idDelCamion)!;
    Recorrido.empezarEn(capa, tarea);
    await tester.pumpAndSettle();
    expect(find.byKey(ClavesDelRecorrido.foco), findsOneWidget);

    // El del paso 1, que es el senalado: el dedo pasa.
    await tester.tap(find.text('Nuevo vehículo'));
    await tester.pumpAndSettle();
    expect(
      tocadoElBueno,
      1,
      reason:
          'el velo se comio el toque del control que esta senalando. El recorrido se '
          'sigue tocando de verdad: si no deja pulsar, no sirve de nada.',
    );

    // El otro, que esta debajo del velo: el dedo NO pasa.
    await tester.tap(find.text('Guardar'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      tocadoElDeAbajo,
      0,
      reason:
          'el velo dejo pulsar un control que no es el del paso. Con el resto de la '
          'pantalla vivo, un desplazamiento deja el anillo senalando un hueco.',
    );

    await tester.pumpWidget(const SizedBox());
  });

  /// Y SU MITAD QUE FALTABA: CON EL CONTROL ABAJO, LA TARJETA SE VA ARRIBA.
  ///
  /// La de arriba, sola, **salia verde con la tarjeta puesta siempre abajo**: el
  /// unico control que miraba estaba arriba, asi que no se solapaban de todas
  /// formas. Medido el 05/10/2026 rompiendo `_tarjeta` a mano. Esta es la pareja: el
  /// control esta pegado al borde de abajo, y si la tarjeta no se mueve, lo tapa.
  testWidgets('con el control abajo, la tarjeta del paso se va arriba', (
    tester,
  ) async {
    await _empezarElRecorrido(tester, _idDelCamion);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(ClavesDelRecorrido.siguiente));
      await tester.pumpAndSettle();
    }
    expect(find.text(TextosDelRecorrido.cualDeCuantos(4, 4)), findsOneWidget);

    final boton = tester.getRect(find.text('Entregar'));
    final tarjeta = tester.getRect(find.byKey(ClavesDelRecorrido.tarjeta));
    expect(
      boton.center.dy,
      greaterThan(_telefono.height / 2),
      reason: 'el control tiene que estar en la mitad de ABAJO, o esto no mide nada',
    );
    expect(
      tarjeta.overlaps(boton),
      isFalse,
      reason:
          'la tarjeta ($tarjeta) tapa el control que senala ($boton). Con el control '
          'abajo la tarjeta tiene que irse arriba.',
    );
    expect(
      tarjeta.center.dy,
      lessThan(boton.center.dy),
      reason: 'la tarjeta se quedo DEBAJO del control que senala',
    );
  });

  /// EL PASO QUE NO SE PUEDE SENALAR LO DICE, y no se queda mudo (§4).
  testWidgets('un paso sin control marcado lo dice con palabras', (
    tester,
  ) async {
    await _empezarElRecorrido(tester, _idDelCamion);
    await tester.tap(find.byKey(ClavesDelRecorrido.siguiente));
    await tester.pumpAndSettle();

    // El paso 2 apunta a un control que ninguna pantalla envuelve.
    expect(find.byKey(ClavesDelRecorrido.foco), findsNothing);
    expect(
      find.textContaining('no se puede señalar'),
      findsOneWidget,
      reason:
          'sin esta linea el paso sale sin foco y parece que la aplicacion esta '
          'rota, que es peor que no senalar',
    );
    // Y el texto del paso sigue estando: es lo que se puede seguir a mano.
    expect(find.textContaining('matrícula'), findsOneWidget);
  });

  /// SE SALE CUANDO QUIERA, Y NO DEJA NADA A MEDIAS.
  testWidgets('«Salir» quita el recorrido y deja la pantalla donde estaba', (
    tester,
  ) async {
    await _empezarElRecorrido(tester, _idDelCamion);
    expect(Recorrido.enMarcha, isTrue);

    await tester.tap(find.byKey(ClavesDelRecorrido.salir));
    await tester.pumpAndSettle();

    expect(Recorrido.enMarcha, isFalse);
    expect(find.byKey(ClavesDelRecorrido.siguiente), findsNothing);
    expect(find.byKey(ClavesDelRecorrido.foco), findsNothing);
    // Se queda en Vehiculos, que es la pantalla de la tarea. No se deshace la
    // navegacion: nadie quiere que al salir de la explicacion le devuelvan a la
    // Guia.
    expect(find.text('Nuevo vehículo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  /// EL ULTIMO PASO CIERRA, no deja un «Siguiente» muerto.
  testWidgets('el ultimo paso dice «Ya está» y al pulsarlo se acaba', (
    tester,
  ) async {
    await _empezarElRecorrido(tester, _idDelCamion);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(ClavesDelRecorrido.siguiente));
      await tester.pumpAndSettle();
    }
    expect(find.text(TextosDelRecorrido.cualDeCuantos(4, 4)), findsOneWidget);
    expect(find.text(TextosDelRecorrido.acabar), findsOneWidget);
    await tester.tap(find.byKey(ClavesDelRecorrido.siguiente));
    await tester.pumpAndSettle();
    expect(Recorrido.enMarcha, isFalse);
  });

  /// LA TAREA QUE NO SE PUEDE GUIAR NO OFRECE UN RECORRIDO EN BLANCO.
  testWidgets('sin pasos numerados no hay boton de guiar, y se dice por que', (
    tester,
  ) async {
    await _montar(tester, donde: _direccionDeTarea(_idSinPasos));

    expect(find.byKey(ClavesDeLaGuia.guiarme), findsNothing);
    expect(
      find.textContaining('no se le puede hacer un recorrido'),
      findsOneWidget,
    );
    // Y el botón de ir a la pantalla sigue ahí: la pantalla existe.
    expect(find.byKey(ClavesDeLaGuia.llevameAhi), findsOneWidget);
  });

  /// LA PANTALLA QUE EN ESTA FORMA NO EXISTE: ni «Ir a», ni recorrido, y con motivo.
  testWidgets('si la pantalla no existe aqui, no se guia y se explica', (
    tester,
  ) async {
    await _montar(tester, donde: _direccionDeTarea(_idDelCanal));

    expect(find.byKey(ClavesDeLaGuia.guiarme), findsNothing);
    expect(find.byKey(ClavesDeLaGuia.llevameAhi), findsNothing);
    expect(
      find.textContaining('«Canal con PEDIDO» no existe en el teléfono'),
      findsOneWidget,
    );
  });

  /// DOS CONTROLES CON EL MISMO NOMBRE NO SE SENALAN A CARA O CRUZ.
  testWidgets('con el mismo control dos veces no se senala ninguno', (
    tester,
  ) async {
    RegistroDeControles.vaciar();
    addTearDown(RegistroDeControles.vaciar);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ControlSenalado(nombre: _elBotonBueno, child: Text('uno')),
              ControlSenalado(nombre: _elBotonBueno, child: Text('otro')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      RegistroDeControles.donde(_elBotonBueno),
      isNull,
      reason:
          'con dos montados no se puede saber a cual se referia el paso, y elegir '
          'uno seria senalar el boton equivocado la mitad de las veces',
    );
    await tester.pumpWidget(const SizedBox());
  });

  /// Y EL QUE PIDE NO SER SENALADO NO SE REGISTRA.
  ///
  /// Es como las pantallas marcan sólo la primera fila de una lista. Si
  /// `senalable: false` registrara igual, cada lista de nueve camiones daria «dos a
  /// la vez» y el foco no saldria nunca en ninguna tarjeta.
  testWidgets('senalable: false deja el envoltorio y no registra', (
    tester,
  ) async {
    RegistroDeControles.vaciar();
    addTearDown(RegistroDeControles.vaciar);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ControlSenalado(nombre: _elBotonBueno, child: Text('la primera')),
              ControlSenalado(
                nombre: _elBotonBueno,
                senalable: false,
                child: Text('la segunda'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // El hijo de las dos se pinta igual: el envoltorio es transparente.
    expect(find.text('la primera'), findsOneWidget);
    expect(find.text('la segunda'), findsOneWidget);
    // Y sólo hay UNO registrado, asi que se puede senalar.
    final puesto = RegistroDeControles.donde(_elBotonBueno);
    expect(puesto, isNotNull);
    expect(
      tester.getRect(find.text('la primera')).contains(puesto!.rect.center),
      isTrue,
      reason: 'se registro la segunda, que es justo la que pidio no serlo',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
