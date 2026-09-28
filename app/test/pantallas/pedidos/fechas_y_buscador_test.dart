// Los filtros de fecha y el buscador de Pedidos.
//
// Las dos cosas estaban a medias, y a medias de la peor forma: el SQL que acota
// por fecha ya estaba escrito y la ✕ de quitarlo tambien, pero no habia ningun
// control que PUSIERA las fechas — o sea que «el pre-despacho de HOY», con lo
// que empieza la mañana del logistico, era inalcanzable. Y el buscador exigia
// Intro y **no se vaciaba al quitar los filtros**, asi que se quedaba un texto
// filtrando en silencio debajo de una lista que ya no estaba filtrada.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/rango_de_fechas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/pedidos/estado/proveedores_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/pantalla_pedidos.dart';
import 'package:reparto/idioma.dart';

import '../../apoyo/base_de_prueba.dart';
import 'sembrar.dart';

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Dos pasadas: el temporizador que cierra los `watch()` de Drift nace al final
/// del primer fotograma del desmontaje.
Future<void> desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late BaseLocal base;
  // El «hoy» de la aplicacion. Es el que abre el calendario por septiembre de
  // 2026, que es donde estan los pedidos del juego de datos: si el calendario
  // leyera el reloj del sistema, esta prueba cambiaria de mes sola.
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() async {
    base = baseDePrueba();
    await sembrarLosOnce(base);
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.pedidos, hasta: null, bajadaAt: ahora);
  });

  tearDown(() => base.close());

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: const Scaffold(body: PantallaPedidos()),
        ),
      ),
    );
    await asentar(tester);
  }

  /// Abre el calendario de un boton de fecha y pica un dia de septiembre.
  Future<void> elegirDia(WidgetTester tester, String boton, String dia) async {
    await tester.tap(find.byTooltip(boton));
    await asentar(tester);
    expect(
      find.byType(CalendarDatePicker),
      findsOneWidget,
      reason:
          'el calendario sale en un menu anclado al boton, no en un modal '
          'centrado: en esta aplicacion es cajon siempre',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(CalendarDatePicker),
        matching: find.text(dia),
      ),
    );
    await asentar(tester);
  }

  testWidgets('poner un rango de fechas FILTRA la lista', (tester) async {
    await pintar(tester);

    // El arranque acotado: 8 de los 11.
    expect(find.textContaining('8 pedidos'), findsOneWidget);

    await elegirDia(tester, 'Desde (fecha del pedido)', '2');

    // Del 2 de septiembre en adelante quedan 6: o1 es del 1 y o11 se acota por
    // la fecha en que se copio (agosto).
    expect(
      find.text('6 pedidos · desde el 2/9/2026, del más nuevo al más viejo'),
      findsOneWidget,
    );

    // `sólo ese día` copia `desde` en `hasta`. Es el atajo de la mañana.
    await tester.tap(find.text('sólo ese día'));
    await asentar(tester);
    expect(
      find.text('1 pedido · del 2/9/2026, del más nuevo al más viejo'),
      findsOneWidget,
    );

    // Y la ✕ los quita los dos.
    await tester.tap(find.byTooltip(RangoDeFechas.tooltipQuitar));
    await asentar(tester);
    expect(find.text('8 pedidos, del más nuevo al más viejo'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('el buscador busca solo a los 400 ms, sin pulsar Intro', (
    tester,
  ) async {
    await pintar(tester);

    await tester.enterText(find.byType(TextField), 'Ana');
    // A los 200 ms todavia no ha buscado: se esta escribiendo.
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('8 pedidos'), findsOneWidget);

    // Pasados los 400, si.
    await tester.pump(const Duration(milliseconds: 250));
    await asentar(tester);
    expect(find.textContaining('1 pedido,'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('`quitarlos todos` limpia TAMBIEN la caja de buscar', (
    tester,
  ) async {
    await pintar(tester);

    await tester.enterText(find.byType(TextField), 'no existe este cliente');
    await tester.pump(const Duration(milliseconds: 450));
    await asentar(tester);

    // Sin resultados, y con el boton de quitarlos todos debajo.
    expect(
      find.text('Ningún pedido cuadra con estos filtros.'),
      findsOneWidget,
    );
    final quitar = find.text('Quitar todos los filtros');
    expect(quitar, findsOneWidget);

    await tester.tap(quitar);
    await asentar(tester);

    // Lo que importa: la caja **se vacia**. Antes se quedaba el texto puesto
    // filtrando en silencio debajo de una lista ya sin filtrar, y eso se lee
    // como «esto es todo lo que hay».
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );
    expect(find.textContaining('11 pedidos'), findsOneWidget);

    await desmontar(tester);
  });

  // LA DE ARRIBA PASA POR ACCIDENTE, y ésta es la que prueba la guarda.
  //
  // Arriba se arranca con el filtro acotado, así que pulsar «Quitar todos» también
  // quita la franja azul de encima de la lista. Esa franja no lleva `key`, y al
  // desaparecer corre de sitio todo lo de debajo: Flutter DESMONTA la caja de buscar y
  // la monta de nuevo, y una caja recién nacida sale vacía por nacer, no porque
  // `didUpdateWidget` (`diseno/caja_de_busqueda.dart`) la vaciara. Con ese paso roto
  // la prueba de arriba seguía verde; lo cazó la auditoría del 26/09/2026.
  //
  // Aquí se quitan antes los dos del arranque («Ver todos»), la franja no está ni
  // antes ni después, y la caja es LA MISMA: si no se vacía, es que la guarda no está.
  testWidgets(
    '`quitarlos todos` vacía la caja aunque la caja no se vuelva a montar',
    (tester) async {
      await pintar(tester);
      ProviderScope.containerOf(tester.element(find.byType(PantallaPedidos)))
          .read(filtrosPedidosProvider.notifier)
          .verTodos();
      await asentar(tester);
      expect(find.textContaining('11 pedidos'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'no existe este cliente');
      await tester.pump(const Duration(milliseconds: 450));
      await asentar(tester);
      final antes = tester.state(find.byType(TextField));

      await tester.tap(find.text('Quitar todos los filtros'));
      await asentar(tester);

      expect(
        identical(tester.state(find.byType(TextField)), antes),
        isTrue,
        reason:
            'la caja se volvió a montar: esta prueba ya no mira la guarda de '
            'didUpdateWidget, que es para lo que existe',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '',
        reason:
            'la caja se quedó con el texto puesto: filtra en silencio debajo de '
            'una lista que dice no tener filtros',
      );
      expect(find.textContaining('11 pedidos'), findsOneWidget);

      await desmontar(tester);
    },
  );
}
