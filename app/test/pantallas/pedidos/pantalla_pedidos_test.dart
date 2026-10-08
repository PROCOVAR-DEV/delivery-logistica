// La pantalla de Pedidos, pintada.
//
// Lo que se comprueba aqui es lo que un test de datos no puede ver: que una lista
// vacia de algo que nunca se bajo se dice con OTRAS palabras (caso S7), que la
// franja azul del arranque acotado sale con su texto literal, y que el reloj de
// datos esta arriba.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/frescura/reloj_de_datos.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/pedidos/vista/pantalla_pedidos.dart';

import '../../apoyo/base_de_prueba.dart';
import 'sembrar.dart';

/// `pumpAndSettle` no vale aqui: mientras una consulta esta en vuelo la
/// pantalla pinta un indicador giratorio, que es una animacion que no para
/// nunca, asi que «esperar a que no quede nada por animar» no termina jamas. Se
/// bombean unos cuantos fotogramas y ya.
Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Desmontar a mano y bombear una vez mas.
///
/// Al desmontarse, los `watch()` de Drift programan un temporizador de cero
/// para cerrarse; si el test acaba antes de que corra, el marco de pruebas lo
/// cuenta como temporizador pendiente y falla. Esto le da ese fotograma.
Future<void> desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() {
    base = baseDePrueba();
  });

  tearDown(() => base.close());

  Future<void> pintar(WidgetTester tester) async {
    // Una pantalla ancha: asi salen las 12 columnas y se comprueba lo que de
    // verdad se ve en el escritorio del despacho.
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // DESMONTAR PASE LO QUE PASE.
    //
    // Sin esto, una comprobación que falla deja la pantalla montada y los
    // `watch()` de Drift vivos, y la prueba **se cuelga en vez de fallar** —lo
    // peor que puede hacer una prueba, `CLAUDE.md` §5—. Se vio mutando el vacío
    // de esta pantalla el 25/09/2026: la mutación no daba rojo, daba siete
    // minutos de nada.
    addTearDown(() => desmontar(tester));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        // La pantalla ya NO trae `Scaffold` propio —lo pone el armazon—, asi que
        // aqui se monta con el suyo: sin el, un `TextField` no encuentra ningun
        // `Material` encima y la pantalla ni se pinta.
        child: const MaterialApp(home: Scaffold(body: PantallaPedidos())),
      ),
    );
    await asentar(tester);
  }

  testWidgets(
    'sin descargar NO es «no hay pedidos»: son dos textos distintos',
    (tester) async {
      await sembrarCatalogo(base);
      await pintar(tester);

      expect(find.text(SinDescargar.textoDeLaPantallaVacia), findsOneWidget);
      // Y el reloj de arriba lo dice tambien, en ambar.
      expect(find.text('Sin descargar todavía'), findsOneWidget);
      // Lo que NO puede salir es el vacio de «no hay nada».
      expect(find.text('Aún no hay pedidos de esta sucursal.'), findsNothing);
      expect(find.text('Ningún pedido cuadra con estos filtros.'), findsNothing);
      await desmontar(tester);
    },
  );

  testWidgets('con datos sale la franja azul del arranque acotado', (
    tester,
  ) async {
    await sembrarLosOnce(base);
    await RegistroDeFrescura(base, reloj: () => ahora).marcar(
      Colecciones.pedidos,
      hasta: '2026-09-14T16:00:00Z',
      bajadaAt: ahora.subtract(const Duration(minutes: 20)),
    );
    for (final coleccion in const [
      Colecciones.renglones,
      Colecciones.productos,
    ]) {
      await RegistroDeFrescura(base, reloj: () => ahora).marcar(
        coleccion,
        hasta: '2026-09-14T16:00:00Z',
        bajadaAt: ahora.subtract(const Duration(minutes: 20)),
      );
    }

    await pintar(tester);

    expect(find.text(PantallaPedidos.franjaAzul), findsOneWidget);
    expect(find.text('Ver todos los pedidos'), findsOneWidget);
    // 8 de los 11: el arranque deja fuera lo archivado y lo no facturado.
    expect(
      find.textContaining('8 pedidos, del más nuevo al más viejo'),
      findsOneWidget,
    );
    // El reloj de datos, arriba y siempre visible.
    expect(find.text('Datos de las 15:45'), findsOneWidget);
    // Y la tabla, con sus cabeceras.
    expect(find.text('Cliente'), findsOneWidget);
    expect(find.text('Dirección'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('`Ver todos los pedidos` quita los dos filtros del arranque', (
    tester,
  ) async {
    await sembrarLosOnce(base);
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.pedidos, hasta: null, bajadaAt: ahora);
    await pintar(tester);

    await tester.tap(find.text('Ver todos los pedidos'));
    await asentar(tester);

    expect(find.text(PantallaPedidos.franjaAzul), findsNothing);
    expect(
      find.textContaining('11 pedidos, del más nuevo al más viejo'),
      findsOneWidget,
    );
    await desmontar(tester);
  });

  // VACIA POR UN FILTRO NO ES VACIA DE VERDAD.
  //
  // Antes las dos decian lo mismo: «Aun no hay pedidos». Con un filtro que no
  // casa eso es mentira —hay 246, lo que no hay es ninguno que cuadre— y quien
  // lo lee se queda pensando que la bajada fallo, cuando solo escribio mal una
  // busqueda. Visto el 25/09/2026 buscando `ZZZNOEXISTE`: arriba «0 pedidos» y
  // en medio «aun no hay pedidos».
  //
  // Va en pareja: sin la primera mitad, poner siempre el texto del filtro
  // cumpliria igual y mentiria al reves.
  testWidgets('buscando lo que no existe, el vacio culpa al filtro', (
    tester,
  ) async {
    await sembrarLosOnce(base);
    // Sin la marca de bajada la pantalla ensena «no se ha descargado todavia»,
    // que es otra cosa y tapa justo lo que se mira aqui.
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.pedidos, hasta: null, bajadaAt: ahora);
    await pintar(tester);

    // Sin filtros, con datos: no hay ningun vacio.
    expect(find.text('Ningún pedido cuadra con estos filtros.'), findsNothing);
    expect(find.text('Aún no hay pedidos de esta sucursal.'), findsNothing);

    // Y ahora se busca algo que no existe.
    await tester.enterText(
      find.byType(TextField).first,
      'ZZZNOEXISTEDENINGUNAMANERA',
    );
    // La caja de buscar tiene 400 ms de respiro a proposito —no consulta en
    // cada letra—, asi que hay que dejarlos pasar o se mira la lista de antes.
    await tester.pump(const Duration(milliseconds: 600));
    await asentar(tester);

    expect(
      find.text('Ningún pedido cuadra con estos filtros.'),
      findsOneWidget,
      reason:
          'el vacio por un filtro tiene que culpar al filtro, no decir que no '
          'hay pedidos: los hay, y quien lo lee cree que fallo la bajada',
    );
    expect(
      find.text('Aún no hay pedidos de esta sucursal.'),
      findsNothing,
      reason: 'con un filtro puesto ese texto miente',
    );
    // Y la salida, a la vista.
    expect(find.text('Quitar todos los filtros'), findsOneWidget);

    await desmontar(tester);
  });
}
