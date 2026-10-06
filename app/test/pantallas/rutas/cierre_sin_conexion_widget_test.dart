// EL CIERRE SIN CONEXION, **DESDE LA PANTALLA Y CONTRA UN FICHERO**.
//
// `cierre_test.dart` ya comprueba esto mismo a nivel de datos, llamando a
// `AccionesDeRuta.cerrar()` a mano. Aqui se comprueba por el camino que recorre
// la persona: pulsar los botones de cada parada y darle a `Guardar`. Entre los
// dos hay sitio de sobra para un fallo —un `setState` que no llega a la base, un
// guardado que se queda en el `State` del widget— y ese fallo no se ve en
// ninguna de las dos pruebas por separado.
//
// **La base es un FICHERO de verdad, no una en memoria.** Es la diferencia
// entre «lo guarda» y «vive en el aparato»: con una base en memoria se estaria
// comprobando que un mapa de Dart conserva lo que se le mete, que es exactamente
// lo que tambien pasa cuando la aplicacion no guarda nada. Es el paso 2 del guion
// del dia sin conexion (`PLAN.md` §5.1): cerrar del todo y volver a abrir.
//
// Y no hay servidor en ningun sitio de este fichero: **no se apaga la red, es que
// no hay red que apagar**. Si algo de esto necesitara hablar con alguien, aqui
// fallaria.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/cierre_de_ruta.dart';

import '../pedidos/sembrar.dart';

/// El indicador giratorio es una animacion que no termina, asi que
/// `pumpAndSettle` no volveria nunca. Se bombean unos fotogramas y basta.
Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// **DOS pasadas, no una.** Al desmontarse, los `watch()` de Drift programan un
/// temporizador de cero para cerrarse, y ese temporizador nace al final del
/// primer fotograma: con un solo `pump` todavia no existe y no llega a
/// dispararse. Con uno solo esto no falla — **cuelga la suite entera diez
/// minutos**, que es peor. El mismo `desmontar()` de `cierre_widget_test.dart`.
Future<void> desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late Directory carpeta;
  late File fichero;
  late BaseLocal base;

  /// La hora del patio del almacen. Lo que se marca a las 16:05 tiene que llegar
  /// como las 16:05 aunque suba mañana (regla 7, caso S2).
  final laHoraDelPatio = DateTime(2026, 9, 14, 16, 5);

  void abrir() => base = BaseLocal.con(NativeDatabase(fichero));

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('reparto_cierre_pantalla');
    fichero = File('${carpeta.path}/reparto.sqlite');
    abrir();

    await sembrarCatalogo(base);
    await sembrarRuta(
      base,
      id: 'R1',
      estado: EstadoRuta.enCurso,
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

  tearDown(() async {
    await base.close();
    await carpeta.delete(recursive: true);
  });

  /// El cajon se monta SOBRE un `Scaffold`, como en la aplicacion: alli lo pone
  /// el armazon y el cajon se abre encima. Sin el, el aviso de `Cierre guardado`
  /// no encuentra de donde colgarse.
  ///
  /// Lee `base` al llamar, no al declarar: despues de reabrir el fichero hay una
  /// `BaseLocal` nueva y es esa la que tiene que pintar.
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
          home: Scaffold(body: CierreDeRuta(rutaId: 'R1', modo: ModoDelCierre.marcar)),
        ),
      ),
    );
    await asentar(tester);
  }

  /// El boton de una parada concreta. Hace falta el indice porque `Entregado`
  /// sale cuatro veces: una por parada y otra en la fila de atajos.
  Finder botonDeParada(String texto, int parada) =>
      find.widgetWithText(OutlinedButton, texto).at(parada + 1);

  testWidgets('sin red: se marca, se cierra la base, se reabre y SIGUE marcado', (
    tester,
  ) async {
    await pintar(tester);

    // Se marca como en el patio: dos paradas, la tercera se queda sin marcar
    // porque el camion vuelve con ella.
    await tester.tap(botonDeParada('Entregado', 0));
    await asentar(tester);
    await tester.tap(botonDeParada('Devuelto', 1));
    await asentar(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Guardar 2 marcada(s)'));
    await asentar(tester);

    // Se pinta como hecho en el momento, sin esperar a nadie.
    expect(find.text(CierreDeRuta.exito), findsOneWidget);

    // El apunte esta en la cola con **la hora del aparato**.
    //
    // Se lee con `lote()` y dentro de `runAsync`: `pendientes()` es un flujo de
    // Drift cuyo primer valor llega por un temporizador, y en un test de widget
    // el tiempo no corre solo — `await ….first` se quedaria esperando para
    // siempre.
    final pendientes = (await tester.runAsync(
      ColaDeSalida(base, reloj: () => laHoraDelPatio).lote,
    ))!;
    expect(pendientes.length, 1);
    expect(pendientes.single.ruta, '/routes/R1/results');
    expect(
      pendientes.single.hechoAt,
      laHoraDelPatio,
      reason: 'la hora del patio, no la de la subida',
    );

    // ── Aqui es donde se cae lo que sólo estaba en memoria ────────────────
    // Se cierra la base y se vuelve a abrir el MISMO fichero. Es lo que le
    // pasa a la aplicacion cuando alguien la desliza fuera, o cuando el
    // telefono se apaga en el patio.
    await desmontar(tester);
    await tester.runAsync(() async {
      await base.close();
      abrir();
    });

    // Y se vuelve a abrir el cierre: **se parte de lo ya guardado**.
    await pintar(tester);
    expect(find.text('Guardar 2 marcada(s)'), findsOneWidget);
    expect(
      find.text('1 sin marcar · cuentan como que siguen en el camión'),
      findsOneWidget,
    );

    // Y el apunte sigue en la cola, con su hora: reabrir no lo da por subido.
    final trasReabrir = (await tester.runAsync(
      ColaDeSalida(base, reloj: () => laHoraDelPatio).lote,
    ))!;
    expect(trasReabrir.length, 1);
    expect(trasReabrir.single.hechoAt, laHoraDelPatio);

    await desmontar(tester);
  });
}
