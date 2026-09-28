// DESMARCAR UNA PARADA SE GUARDA — 28/09/2026.
//
// Jose: «desmarco el estado de cierre y no se guarda cuando salgo por q razon».
//
// Marcar persistía; quitar la marca, no. Y eran DOS agujeros seguidos, los dos
// del mismo patrón —«quitar un valor se confunde con no haber tocado nada»—:
//
//  1. `_guardar` sólo armaba `MarcaDeParada` para las paradas CON resultado, así
//     que una parada desmarcada **no producía ningún apunte**. Nada salía de la
//     pantalla, nada llegaba al servidor, y al reabrir la marca vieja seguía ahí.
//  2. Y aunque hubiera sabido mandarlo, el botón de guardar se apagaba con
//     `_marcadas == 0`: quitar la ÚLTIMA marca dejaba el gesto sin forma de
//     ejecutarse.
//
// Este fichero prueba el camino ENTERO, tal y como lo hace Jose: abrir, marcar,
// guardar, salir, volver a entrar, desmarcar, guardar, y volver a entrar.
//
// La otra mitad de la pareja está en `cierre_widget_test.dart`, «pulsar el mismo
// botón dos veces DESMARCA»: ahí se marca y se desmarca EN LA MISMA sesión, sin
// nada guardado detrás, y entonces no hay nada que guardar y el botón sigue
// apagado. Las dos cosas se parecen en la pantalla y son distintas por debajo.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/cierre_de_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Hacen falta DOS pasadas: el temporizador lo crea el propio desmontaje, al
/// final del primer fotograma. Con una sola, la suite **se cuelga** en vez de
/// fallar. Igual que en `cierre_widget_test.dart`.
Future<void> desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late BaseLocal base;
  final laHoraDelPatio = DateTime(2026, 9, 28, 16, 5);

  setUp(() async {
    base = baseDePrueba();
    await sembrarCatalogo(base);
    await sembrarRuta(
      base,
      id: 'R1',
      estado: EstadoRuta.enCurso,
      codigo: 'RT-20260928-001',
    );
    for (final (i, nombre) in <String>['Ana', 'Beto'].indexed) {
      await sembrarPedido(
        base,
        id: 'p${i + 1}',
        cliente: nombre,
        rutaId: 'R1',
        orden: i + 1,
      );
      await sembrarRenglon(
        base,
        id: 'ri${i + 1}',
        pedidoId: 'p${i + 1}',
        producto: 'Arroz',
        unidades: 10,
        empaques: 2,
      );
    }
  });

  tearDown(() => base.close());

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => laHoraDelPatio),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CierreDeRuta(rutaId: 'R1')),
        ),
      ),
    );
    await asentar(tester);
  }

  /// El botón de una parada concreta. Hacen falta índices porque `Entregado`
  /// aparece una vez por parada más una en la fila de atajos.
  Finder botonDeParada(String texto, int parada) =>
      find.widgetWithText(OutlinedButton, texto).at(parada + 1);

  /// El resultado que hay GUARDADO en la base para una parada.
  Future<String?> guardadoDe(WidgetTester tester, String pedidoId) async {
    final fila = await tester.runAsync(
      () => (base.select(
        base.orders,
      )..where((o) => o.id.equals(pedidoId))).getSingle(),
    );
    return fila!.resultado;
  }

  testWidgets(
    'se marca, se guarda, se desmarca y AL REABRIR ya no está marcada',
    (tester) async {
      // ---- 1. Se marca y se guarda. -------------------------------------
      await pintar(tester);
      await tester.tap(botonDeParada('Entregado', 0));
      await asentar(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Guardar 1 marcada(s)'),
      );
      await asentar(tester);
      expect(
        await guardadoDe(tester, 'p1'),
        ResultadoParada.entregado,
        reason: 'la marca no se guardó: esta prueba no probaría nada',
      );
      await desmontar(tester);

      // ---- 2. Se vuelve a abrir: la marca está, como debe. ---------------
      await pintar(tester);
      expect(find.text('Guardar 1 marcada(s)'), findsOneWidget);

      // ---- 3. Se DESMARCA. ----------------------------------------------
      //
      // El botón de una parada YA marcada es un `FilledButton`, no un
      // `OutlinedButton`: buscarlo con `botonDeParada` cogería el de la parada
      // de al lado y la marcaría en vez de desmarcar ésta. Mismo truco que en
      // `cierre_widget_test.dart`.
      await tester.tap(find.widgetWithText(FilledButton, 'Entregado'));
      await asentar(tester);

      // EL BOTÓN NO SE APAGA. Aquí estaba la mitad que hacía el gesto
      // imposible: con `_marcadas == 0` el botón quedaba muerto, así que no
      // había manera de guardar el desmarcado ni aunque supiera mandarse.
      final guardar = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Guardar 0 y quitar 1'),
      );
      expect(
        guardar.onPressed,
        isNotNull,
        reason:
            'quitar la última marca apagaba el botón de guardar: el gesto no se '
            'podía ni intentar',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Guardar 0 y quitar 1'));
      await asentar(tester);

      // ---- 4. Y SE GUARDÓ DE VERDAD. ------------------------------------
      expect(
        await guardadoDe(tester, 'p1'),
        isNull,
        reason:
            'la marca sigue en la base: es exactamente lo que veía Jose al '
            'volver a entrar',
      );

      // El apunte salió a la cola, con `resultado: null` dentro: el servidor
      // distingue eso de «no vino el campo» (`entradaDeCierre`, con
      // `httpx.Opcional`).
      final cola = ColaDeSalida(base, reloj: () => laHoraDelPatio);
      final pendientes = (await tester.runAsync(cola.lote))!;
      final ultimo = pendientes.last;
      expect(ultimo.ruta, '/routes/R1/results');
      expect(
        ultimo.cuerpo,
        contains('"resultado":null'),
        reason:
            'sin el nulo explícito en el cuerpo, el servidor no puede saber que '
            'hay que BORRAR la marca; sólo ve una parada que no vino',
      );
      await desmontar(tester);

      // ---- 5. Se vuelve a abrir: ya no está marcada. ---------------------
      await pintar(tester);
      expect(find.text('Guardar 0 marcada(s)'), findsOneWidget);
      expect(
        find.text('2 sin marcar · cuentan como que siguen en el camión'),
        findsOneWidget,
      );
      await desmontar(tester);
    },
  );

  testWidgets('la parada desmarcada VUELVE A SU RUTA, no se queda suelta', (
    tester,
  ) async {
    // Un devuelto SUELTA su `routeId` al marcarse: baja del camión y vuelve a
    // la lista de disponibles de mañana. Desmarcarlo sin devolvérselo lo deja
    // fuera de su propia ruta con la ruta todavía abierta, y entonces la zona lo
    // vuelve a coger y sale un SEGUNDO camión con el mismo bulto.
    await pintar(tester);
    await tester.tap(botonDeParada('Devuelto', 0));
    await asentar(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar 1 marcada(s)'));
    await asentar(tester);
    await desmontar(tester);

    final sueltoTrasMarcar = await tester.runAsync(
      () async => (await (base.select(
        base.orders,
      )..where((o) => o.id.equals('p1'))).getSingle()).routeId,
    );
    expect(
      sueltoTrasMarcar,
      isNull,
      reason: 'un devuelto suelta su ruta: si no, esta prueba no probaría nada',
    );

    await pintar(tester);
    // Ya marcada: su botón es un `FilledButton`. Ver la nota de la prueba de
    // arriba.
    await tester.tap(find.widgetWithText(FilledButton, 'Devuelto'));
    await asentar(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar 0 y quitar 1'));
    await asentar(tester);

    final tras = await tester.runAsync(
      () async => (await (base.select(
        base.orders,
      )..where((o) => o.id.equals('p1'))).getSingle()),
    );
    expect(
      tras!.routeId,
      'R1',
      reason:
          'el devuelto desmarcado se quedó FUERA de su ruta: vuelve a la lista '
          'de disponibles con la ruta abierta y sale en dos camiones',
    );
    // Y todo lo demás de la marca se fue con ella.
    expect(tras.resultado, isNull);
    expect(tras.resultadoNota, isNull);
    expect(tras.deliveredAt, isNull);
    expect(tras.ultimaRutaId, 'R1', reason: 'la hoja de cierre no se toca');
    await desmontar(tester);
  });

  testWidgets('sin tocar nada, el botón de salir no habla de cambios', (
    tester,
  ) async {
    // La otra mitad del aviso de «sin guardar»: que NO salga cuando no toca. Un
    // aviso que sale siempre deja de leerse, y entonces tampoco se lee el día
    // que importa (`CLAUDE.md` §3-quinquies).
    await pintar(tester);
    expect(find.widgetWithText(TextButton, 'Cerrar'), findsOneWidget);

    await tester.tap(botonDeParada('Entregado', 0));
    await asentar(tester);
    expect(
      find.widgetWithText(TextButton, 'Salir sin guardar (1 sin guardar)'),
      findsOneWidget,
      reason:
          'cerrar la hoja con una marca puesta y que no pase nada es el «dato '
          'que está y no se escribe» (§4)',
    );

    // Y al deshacerlo a mano vuelve a no haber nada que guardar.
    await tester.tap(find.widgetWithText(FilledButton, 'Entregado'));
    await asentar(tester);
    expect(find.widgetWithText(TextButton, 'Cerrar'), findsOneWidget);
    await desmontar(tester);
  });
}
