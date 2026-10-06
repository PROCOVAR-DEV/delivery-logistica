// CUANDO SE PREGUNTA EL ESTADO DE CADA PARADA, Y CUANDO YA NO SE PREGUNTA.
//
// Jose, 17/09/2026, mirando el cierre de una ruta ya completada: «ese estado se
// pone cuando están en ruta, no completados; ahí el cierre ya viene con el
// estado de cuando le van a dar a completado, es que se pregunta ese estado».
//
// Asi que el cierre tiene tres momentos y esta prueba cubre los dos nuevos:
//
//  - `alCompletar`: se pulso `Marcar como completada` y quedan paradas sin
//    marcar. Se pregunta como acabaron, y **guardar y completar es un solo
//    gesto**. Si el cierre es rechazado, la ruta NO se completa.
//  - `soloLectura`: la ruta ya esta completada. No hay botones de marcar, ni
//    fila de `Todas:`, ni boton de guardar; lo que hay es como acabo cada una.
//
// El modo `marcar` de siempre lo cubre `cierre_widget_test.dart`.

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';
import 'package:reparto/pantallas/rutas/estado/proveedores_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/cierre_de_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';
import 'cierre_widget_test.dart' show asentar, desmontar;

void main() {
  late BaseLocal base;
  final laHoraDelPatio = DateTime(2026, 9, 14, 16, 5);

  /// Siembra catalogo, ruta y tres paradas. **Se llama DENTRO del cuerpo de
  /// cada prueba**, nunca en el `setUp`: el `setUp` corre fuera del reloj falso
  /// de `testWidgets` y lo que Drift deja empezado alli no avanza dentro —la
  /// prueba se cuelga en vez de fallar (`CLAUDE.md` §5).
  Future<void> sembrar({required String estadoDeLaRuta}) async {
    await sembrarCatalogo(base);
    await sembrarRuta(
      base,
      id: 'R1',
      estado: estadoDeLaRuta,
      codigo: 'RT-20260914-001',
    );
    for (final (i, nombre) in <String>['Ana', 'Beto', 'Carla'].indexed) {
      await sembrarPedido(
        base,
        id: 'p${i + 1}',
        cliente: nombre,
        rutaId: 'R1',
        orden: i + 1,
      );
    }
  }

  Future<String?> estadoDeLaRuta() async {
    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals('R1'))).getSingleOrNull();
    return ruta?.status;
  }

  Future<List<String?>> resultadosGuardados() async {
    final pedidos =
        await (base.select(base.orders)
              ..where((o) => o.ultimaRutaId.equals('R1'))
              ..orderBy([(o) => OrderingTerm(expression: o.id)]))
            .get();
    return [for (final p in pedidos) p.resultado];
  }

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> pintar(
    WidgetTester tester, {
    required ModoDelCierre modo,
    VoidCallback? alCompletar,
    bool elServidorRechazaElCierre = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => laHoraDelPatio),
          if (elServidorRechazaElCierre)
            accionesDeRutaProvider.overrideWith(
              (ref) => _ElCierreRebotado(
                base,
                ref.watch(colaProvider),
                reloj: () => laHoraDelPatio,
              ),
            ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CierreDeRuta(
              rutaId: 'R1',
              modo: modo,
              alCompletar: alCompletar,
            ),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  /// El boton de una parada concreta. Hacen falta indices porque `Entregado`
  /// sale cuatro veces: una por parada y una en la fila de atajos.
  Finder botonDeParada(String texto, int parada) =>
      find.widgetWithText(OutlinedButton, texto).at(parada + 1);

  // ── El momento de completar ───────────────────────────────────────────────

  testWidgets(
    'al completar se PREGUNTA el estado, y guardar cierra y completa de una',
    (tester) async {
      await sembrar(estadoDeLaRuta: EstadoRuta.enCurso);
      var volvioALaLista = false;
      await pintar(
        tester,
        modo: ModoDelCierre.alCompletar,
        alCompletar: () => volvioALaLista = true,
      );

      // La cabecera es la del momento, no la de siempre.
      expect(find.text(CierreDeRuta.cabeceraAlCompletar), findsOneWidget);
      expect(find.text(CierreDeRuta.cabecera), findsNothing);
      // Y el boton dice lo que va a pasar de verdad.
      expect(find.text('Guardar y completar'), findsOneWidget);
      expect(find.textContaining('Guardar 0 marcada(s)'), findsNothing);

      await tester.tap(botonDeParada('Entregado', 0));
      await tester.tap(botonDeParada('Entregado', 1));
      await tester.tap(botonDeParada('Devuelto', 2));
      await asentar(tester);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Guardar y completar'),
      );
      await asentar(tester);

      // Las tres marcas guardadas...
      expect(await resultadosGuardados(), [
        ResultadoParada.entregado,
        ResultadoParada.entregado,
        ResultadoParada.devuelto,
      ]);
      // ...y la ruta completada en el MISMO gesto.
      expect(await estadoDeLaRuta(), EstadoRuta.completada);
      expect(find.text(CierreDeRuta.exitoAlCompletar), findsOneWidget);
      // La pantalla de Rutas se entera para soltar la ruta e irse al Historial.
      expect(volvioALaLista, isTrue);

      await desmontar(tester);
    },
  );

  testWidgets(
    'se puede completar sin marcar nada: lo sin marcar siguió en el camión',
    (tester) async {
      await sembrar(estadoDeLaRuta: EstadoRuta.enCurso);
      await pintar(tester, modo: ModoDelCierre.alCompletar);

      // **Con cero marcadas el boton NO esta apagado.** En el modo de siempre
      // si lo esta, porque guardar cero marcas no hace nada; aqui completar la
      // ruta si hace algo, y dejar las tres sin marcar es una respuesta:
      // volvieron en el camion.
      final boton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Guardar y completar'),
      );
      expect(boton.onPressed, isNotNull);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Guardar y completar'),
      );
      await asentar(tester);

      expect(await estadoDeLaRuta(), EstadoRuta.completada);
      expect(await resultadosGuardados(), [null, null, null]);

      await desmontar(tester);
    },
  );

  testWidgets('si el cierre es RECHAZADO, la ruta no se completa', (
    tester,
  ) async {
    await sembrar(estadoDeLaRuta: EstadoRuta.enCurso);
    var volvioALaLista = false;
    await pintar(
      tester,
      modo: ModoDelCierre.alCompletar,
      alCompletar: () => volvioALaLista = true,
      elServidorRechazaElCierre: true,
    );

    await tester.tap(botonDeParada('Entregado', 0));
    await asentar(tester);
    final antesDeGuardar = RegistroDeControles.acciones.value;
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar y completar'));
    await asentar(tester);
    expect(
      RegistroDeControles.acciones.value,
      antesDeGuardar,
      reason: 'guardar rechazado no da la acción por completada',
    );

    // **El orden importa**: completar va DESPUES de guardar y solo si guardar
    // salio bien. Al reves quedaria una ruta dada por cerrada con las paradas
    // sin marcar, y nadie sabria que es lo que bajo del camion.
    expect(await estadoDeLaRuta(), EstadoRuta.enCurso);
    expect(volvioALaLista, isFalse);
    // Y el motivo, literal, sin envolver en un «no se pudo guardar».
    expect(find.text(_motivoDelRechazo), findsOneWidget);

    await desmontar(tester);
  });

  // ── La ruta ya completada ────────────────────────────────────────────────

  testWidgets('en una ruta completada el cierre se MIRA, no se toca', (
    tester,
  ) async {
    await sembrar(estadoDeLaRuta: EstadoRuta.completada);
    await (base.update(base.orders)..where((o) => o.id.equals('p1'))).write(
      const OrdersCompanion(resultado: Value(ResultadoParada.entregado)),
    );
    await (base.update(base.orders)..where((o) => o.id.equals('p2'))).write(
      const OrdersCompanion(
        resultado: Value(ResultadoParada.devuelto),
        resultadoNota: Value('el cliente había cerrado'),
      ),
    );
    await pintar(tester, modo: ModoDelCierre.soloLectura);

    expect(find.text(CierreDeRuta.cabeceraSoloLectura), findsOneWidget);
    expect(find.text(CierreDeRuta.cabecera), findsNothing);

    // NI UN SOLO BOTON DE MARCAR, ni apagado: ni los de las paradas ni la fila
    // de `Todas:`. Un boton apagado invita a buscar como encenderlo.
    expect(find.text('Todas:'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Entregado'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Entregado'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Devuelto'), findsNothing);
    // Y tampoco hay donde guardar.
    expect(find.textContaining('Guardar'), findsNothing);
    expect(find.text('Guardar y completar'), findsNothing);

    // Lo que SI se ve: como acabo cada una, con su nombre.
    expect(find.text('Entregado'), findsOneWidget);
    expect(find.text('Devuelto'), findsOneWidget);
    // La tercera no se marco: eso no es «nada», es que volvio en el camion.
    expect(find.text('Sin marcar · siguió en el camión'), findsOneWidget);
    // Y el porque de la devolucion, que en una ruta cerrada es la unica
    // explicacion que queda.
    expect(find.text('el cliente había cerrado'), findsOneWidget);
    // El post-despacho se sigue pudiendo sacar: eso es leer, no marcar.
    expect(
      find.widgetWithText(OutlinedButton, 'Post-despacho'),
      findsOneWidget,
    );

    await desmontar(tester);
  });
}

const _motivoDelRechazo = 'Ese pedido ya va en otra ruta';

/// Las acciones de siempre, pero con el cierre rebotado por el servidor. Lo
/// demas —completar incluido— sigue siendo el de verdad: lo que se comprueba es
/// que no llega a llamarse.
class _ElCierreRebotado extends AccionesDeRuta {
  _ElCierreRebotado(super.base, super.cola, {super.reloj});

  @override
  Future<String> cerrar(String rutaId, List<MarcaDeParada> marcas) async =>
      throw const RechazoLocal(_motivoDelRechazo);
}
