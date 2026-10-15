// QUIEN REPARTE, EN LA LISTA DE RUTAS — issue 7 de Amado, 14/10/2026.
//
// Cada tarjeta dice quien reparte la ruta. Tres respuestas y ninguna se confunde con otra:
//
//  * con distribuidor y con su fila bajada -> su nombre (y «retirado» si ya no esta en activo: sigue
//    siendo quien reparto esa ruta);
//  * sin distribuidor (una ruta anterior al 14/10/2026, o armada sin elegir) -> «Sin distribuidor»;
//  * con distribuidor pero sin su fila en el aparato -> «Distribuidor sin descargar». Decir «Sin
//    distribuidor» de una ruta que SI lo tiene seria afirmar lo contrario de lo que sabe el servidor.
//
// Y las tarjetas con y sin distribuidor miden LO MISMO: si el renglon solo saliera cuando hay uno,
// las rutas historicas serian mas bajas que las nuevas y la lista saldria con dientes de sierra.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/distribuidores/datos/distribuidor_de_la_ruta.dart';
import 'package:reparto/pantallas/distribuidores/vista/distribuidor_de_la_ruta.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/lista_rutas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 10, 14, 9);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> pintar(WidgetTester tester, Widget cuerpo) async {
    tester.view.physicalSize = const Size(390, 844);
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
          home: Scaffold(body: cuerpo),
        ),
      ),
    );
    await asentar(tester);
  }

  Future<void> sembrarTodo() async {
    await sembrarCatalogo(base);
    await RegistroDeFrescura(base, reloj: () => ahora)
        .marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);
    for (final (id, nombre, activo) in const [
      ('d-juan', 'Juan Pérez', true),
      ('d-pedro', 'Pedro Gil', false),
    ]) {
      await base.into(base.distribuidores).insert(
        DistribuidoresCompanion.insert(
          id: id,
          nombre: nombre,
          activo: Value(activo),
          branchId: const Value('B1'),
        ),
      );
    }
    for (final (id, distribuidor) in const [
      ('R-con', 'd-juan'),
      ('R-retirado', 'd-pedro'),
      ('R-sin', null),
      ('R-sinbajar', 'd-fantasma'),
    ]) {
      await sembrarRuta(base, id: id, estado: EstadoRuta.enCurso, creada: ahora);
      await (base.update(base.routes)..where((r) => r.id.equals(id)))
          .write(RoutesCompanion(distribuidorId: Value(distribuidor)));
    }
  }

  testWidgets('cada tarjeta dice quien reparte: nombre, retirado, nadie o sin descargar', (tester) async {
    await sembrarTodo();
    await pintar(tester, const ListaDeRutas(deLaPestana: PestanaRutas.enCurso));

    expect(find.text('Juan Pérez'), findsOneWidget);
    expect(find.text('Pedro Gil · retirado'), findsOneWidget,
        reason: 'un retirado sigue siendo quien reparto esa ruta');
    expect(find.text(textoSinDistribuidor), findsOneWidget);
    expect(find.text(textoDistribuidorSinBajar), findsOneWidget,
        reason: 'tiene distribuidor y el aparato no sabe cual: no es «sin distribuidor»');
    await desmontar(tester);
  });

  testWidgets('las tarjetas con y sin distribuidor miden LO MISMO', (tester) async {
    await sembrarTodo();
    await pintar(tester, const ListaDeRutas(deLaPestana: PestanaRutas.enCurso));

    final altos = tester
        .widgetList<Card>(find.byType(Card))
        .map((c) => tester.getSize(find.byWidget(c)).height)
        .toSet();
    expect(altos, hasLength(1),
        reason: 'si el renglon solo saliera cuando hay distribuidor, las historicas serian mas bajas');
    await desmontar(tester);
  });

  testWidgets('el renglon suelto para el detalle resuelve el nombre contra la base, aunque llegue DESPUES', (tester) async {
    // §3-ter: montar con la base vacia y sembrar despues, sin volver a montar.
    await pintar(tester, const DistribuidorDeLaRuta(distribuidorId: 'd-juan'));
    expect(find.text('Distribuidor: $textoDistribuidorSinBajar'), findsOneWidget);

    await base.into(base.distribuidores).insert(
      DistribuidoresCompanion.insert(id: 'd-juan', nombre: 'Juan Pérez'),
    );
    await asentar(tester);
    expect(find.text('Distribuidor: Juan Pérez'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('y sin distribuidor el renglon suelto dice «Sin distribuidor»', (tester) async {
    await pintar(tester, const DistribuidorDeLaRuta(distribuidorId: null));
    expect(find.text(textoSinDistribuidor), findsOneWidget);
    await desmontar(tester);
  });

  test('textoDelDistribuidor: las cuatro respuestas, y ninguna se confunde con otra', () {
    final juan = Distribuidor(id: 'd-juan', nombre: 'Juan Pérez', activo: true, branchId: 'B1', updatedAt: null);
    final pedro = Distribuidor(id: 'd-pedro', nombre: 'Pedro Gil', activo: false, branchId: 'B1', updatedAt: null);
    final conocidos = {juan.id: juan, pedro.id: pedro};
    expect(textoDelDistribuidor(null, conocidos), textoSinDistribuidor);
    expect(textoDelDistribuidor('', conocidos), textoSinDistribuidor);
    expect(textoDelDistribuidor('d-juan', conocidos), 'Juan Pérez');
    expect(textoDelDistribuidor('d-pedro', conocidos), 'Pedro Gil · retirado');
    expect(textoDelDistribuidor('d-fantasma', conocidos), textoDistribuidorSinBajar);
  });
}
