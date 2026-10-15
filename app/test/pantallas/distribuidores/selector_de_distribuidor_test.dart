// «DISTRIBUIDOR» AL CREAR LA RUTA — issue 7 de Amado, 14/10/2026.
//
// OPCIONAL pero visible y recordado: no se puede obligar mientras las rutas de antes no lo tengan y
// haya sucursales sin ninguno dado de alta (el mismo callejon del camion en el taller), pero una ruta
// que sale sin decir quien la reparte es justo lo que se quiere evitar. Lo que se vigila aqui:
//
//  * solo se ofrecen los de LA SUCURSAL DE LA RUTA y EN ACTIVO (los que el servidor aceptaria);
//  * sin ninguno elegido se AVISA en ambar; sin ninguno dado de alta hay un ENLACE a crearlos;
//  * y no es lo mismo «esta sucursal no tiene» que «este aparato no los ha descargado»;
//  * el ultimo elegido se RECUERDA por sucursal, se ve elegido, y no resucita si se dejo «sin»;
//  * todo con la base sembrada DENTRO del cuerpo de cada prueba y los datos llegando DESPUES de pintar
//    (`CLAUDE.md` §3-ter).
//
// TODO EN PAREJA: cada «no» tiene su «sí» al lado.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/distribuidores/vista/selector_de_distribuidor.dart';

import '../../apoyo/base_de_prueba.dart';

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

/// El anfitrion: guarda lo elegido y lo pinta, como lo hace el asistente.
class _Anfitrion extends StatefulWidget {
  const _Anfitrion({required this.sucursalId, this.alElegir});

  final String? sucursalId;
  final ValueChanged<String?>? alElegir;

  @override
  State<_Anfitrion> createState() => _AnfitrionState();
}

class _AnfitrionState extends State<_Anfitrion> {
  String? elegido;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SelectorDeDistribuidor(
        sucursalId: widget.sucursalId,
        elegido: elegido,
        alElegir: (id) {
          widget.alElegir?.call(id);
          setState(() => elegido = id);
        },
      ),
      Text('ELEGIDO=${elegido ?? 'nadie'}'),
    ],
  );
}

void main() {
  late BaseLocal base;

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> marcarBajados() => RegistroDeFrescura(base).marcar(
    Colecciones.distribuidores,
    hasta: null,
    bajadaAt: DateTime(2026, 10, 14, 9),
    completa: true,
  );

  Future<void> sembrar({bool bajados = true}) async {
    for (final (id, nombre, sucursal, activo) in const [
      ('d-juan', 'Juan Pérez', 'B1', true),
      ('d-maria', 'María López', 'B1', true),
      ('d-pedro', 'Pedro Gil', 'B1', false), // retirado
      ('d-luis', 'Luis Gómez', 'B2', true), // de otra sucursal
    ]) {
      await base.into(base.distribuidores).insert(
        DistribuidoresCompanion.insert(
          id: id,
          nombre: nombre,
          activo: Value(activo),
          branchId: Value(sucursal),
        ),
      );
    }
    if (bajados) await marcarBajados();
  }

  Future<void> pintar(
    WidgetTester tester, {
    String? sucursalId = 'B1',
    ValueChanged<String?>? alElegir,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [baseProvider.overrideWithValue(base)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: _Anfitrion(sucursalId: sucursalId, alElegir: alElegir),
            ),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  Future<void> abrirElDesplegable(WidgetTester tester) async {
    await tester.tap(find.byKey(SelectorDeDistribuidor.claveDelSelector));
    await asentar(tester);
  }

  testWidgets('ofrece SOLO los de la sucursal de la ruta y en activo', (tester) async {
    await tester.runAsync(sembrar);
    await pintar(tester);
    await abrirElDesplegable(tester);

    expect(find.text('Juan Pérez'), findsOneWidget);
    expect(find.text('María López'), findsOneWidget);
    expect(find.text(SelectorDeDistribuidor.textoSinNinguno), findsWidgets);
    expect(find.text('Pedro Gil'), findsNothing,
        reason: 'uno retirado no se asigna a una ruta nueva: el servidor lo rechazaria');
    expect(find.text('Luis Gómez'), findsNothing,
        reason: 'uno de OTRA sucursal tampoco: es el 400 del servidor');
    await desmontar(tester);
  });

  testWidgets('la pareja: para la OTRA sucursal salen los de la otra', (tester) async {
    await tester.runAsync(sembrar);
    await pintar(tester, sucursalId: 'B2');
    await abrirElDesplegable(tester);

    expect(find.text('Luis Gómez'), findsOneWidget);
    expect(find.text('Juan Pérez'), findsNothing);
    await desmontar(tester);
  });

  testWidgets('elegir uno lo entrega, y «sin distribuidor» lo quita', (tester) async {
    await tester.runAsync(() async {
      await sembrar();
      // Que el recuerdo no pise lo que la prueba elige.
    });
    final elegidos = <String?>[];
    await pintar(tester, alElegir: elegidos.add);
    await abrirElDesplegable(tester);
    await tester.tap(find.text('María López'));
    await asentar(tester);
    expect(find.text('ELEGIDO=d-maria'), findsOneWidget);

    await abrirElDesplegable(tester);
    await tester.tap(find.text(SelectorDeDistribuidor.textoSinNinguno).last);
    await asentar(tester);
    expect(find.text('ELEGIDO=nadie'), findsOneWidget);
    expect(elegidos, ['d-maria', null]);
    await desmontar(tester);
  });

  group('sin ninguno elegido se avisa; con uno, no', () {
    testWidgets('con distribuidores disponibles y ninguno elegido: aviso ambar', (tester) async {
      await tester.runAsync(sembrar);
      await pintar(tester);
      expect(find.byKey(SelectorDeDistribuidor.claveDelAvisoSinElegir), findsOneWidget,
          reason: 'una ruta que sale sin decir quien la reparte es lo que Amado pide evitar');
      await desmontar(tester);
    });

    testWidgets('la pareja: con uno elegido el aviso se va', (tester) async {
      await tester.runAsync(sembrar);
      await pintar(tester);
      await abrirElDesplegable(tester);
      await tester.tap(find.text('Juan Pérez'));
      await asentar(tester);
      expect(find.byKey(SelectorDeDistribuidor.claveDelAvisoSinElegir), findsNothing);
      await desmontar(tester);
    });
  });

  group('la lista vacia no es una sola cosa', () {
    testWidgets('descargados y de verdad sin ninguno: lo dice y ofrece CREARLOS', (tester) async {
      await tester.runAsync(marcarBajados);
      await pintar(tester);
      expect(find.textContaining('no tiene distribuidores dados de alta'), findsOneWidget);
      expect(find.text('Crear distribuidores'), findsOneWidget,
          reason: 'sin un sitio donde crearlos, el campo opcional no tiene salida');
      expect(find.byKey(SelectorDeDistribuidor.claveDelAvisoSinElegir), findsNothing,
          reason: 'no se avisa de «elige uno» si no hay ninguno que elegir');
      await desmontar(tester);
    });

    testWidgets('sin descargar: lo dice con otras palabras (se arregla trayendo el dia)', (tester) async {
      await pintar(tester);
      expect(find.textContaining('no ha descargado los distribuidores'), findsOneWidget);
      expect(find.textContaining('no tiene distribuidores dados de alta'), findsNothing,
          reason: 'decir «no tiene ninguno» de una lista que nunca bajo seria mentir');
      await desmontar(tester);
    });

    testWidgets('con distribuidores el enlace dice «Administrar»', (tester) async {
      await tester.runAsync(sembrar);
      await pintar(tester);
      expect(find.text('Administrar distribuidores'), findsOneWidget);
      expect(find.text('Crear distribuidores'), findsNothing);
      await desmontar(tester);
    });

    testWidgets('sin sucursal no hay nada que ofrecer', (tester) async {
      await tester.runAsync(sembrar);
      await pintar(tester, sucursalId: null);
      await abrirElDesplegable(tester);
      expect(find.text('Juan Pérez'), findsNothing);
      await desmontar(tester);
    });
  });

  group('recordado', () {
    final clave = ClaveDePreferencia.ultimoDistribuidorDe('B1');

    testWidgets('queda elegido el de la ultima ruta de ESA sucursal, y se VE', (tester) async {
      await tester.runAsync(() async {
        await sembrar();
        await base.anotarPreferencia(clave, 'd-maria');
      });
      await pintar(tester);
      expect(find.text('ELEGIDO=d-maria'), findsOneWidget);
      expect(find.byKey(SelectorDeDistribuidor.claveDelAvisoSinElegir), findsNothing);
      await desmontar(tester);
    });

    testWidgets('la pareja: sin recuerdo no se elige nada solo', (tester) async {
      await tester.runAsync(sembrar);
      await pintar(tester);
      expect(find.text('ELEGIDO=nadie'), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('si el recordado ya esta retirado o es de otra sucursal, NO se pone', (tester) async {
      for (final id in ['d-pedro', 'd-luis']) {
        await tester.runAsync(() async {
          await sembrar();
          await base.anotarPreferencia(clave, id);
        });
        await pintar(tester);
        expect(find.text('ELEGIDO=nadie'), findsOneWidget,
            reason: '$id no se puede asignar a una ruta nueva de B1: ponerlo seria fabricar un 400');
        await desmontar(tester);
        await tester.runAsync(() async {
          await base.delete(base.distribuidores).go();
          await base.delete(base.frescura).go();
          await base.anotarPreferencia(clave, null);
        });
      }
    });

    testWidgets('elegir guarda el recuerdo, y «sin distribuidor» lo BORRA', (tester) async {
      await tester.runAsync(sembrar);
      await pintar(tester);
      await abrirElDesplegable(tester);
      await tester.tap(find.text('Juan Pérez'));
      await asentar(tester);
      expect(await tester.runAsync(() => base.preferencia(clave)), 'd-juan');

      await abrirElDesplegable(tester);
      await tester.tap(find.text(SelectorDeDistribuidor.textoSinNinguno).last);
      await asentar(tester);
      expect(await tester.runAsync(() => base.preferencia(clave)), isNull,
          reason: 'si no, la proxima ruta resucitaria al de dos rutas atras');
      await desmontar(tester);
    });

    testWidgets('lo dejado en «sin» a proposito NO se vuelve a rellenar en el mismo asistente', (tester) async {
      await tester.runAsync(() async {
        await sembrar();
        await base.anotarPreferencia(clave, 'd-juan');
      });
      await pintar(tester);
      expect(find.text('ELEGIDO=d-juan'), findsOneWidget);

      await abrirElDesplegable(tester);
      await tester.tap(find.text(SelectorDeDistribuidor.textoSinNinguno).last);
      await asentar(tester);
      await asentar(tester);
      expect(find.text('ELEGIDO=nadie'), findsOneWidget);
      await desmontar(tester);
    });
  });

  testWidgets('los datos que llegan DESPUES de pintar tambien salen (la web nace vacia)', (tester) async {
    // §3-ter: montar con la base VACIA y sembrar DESPUES, sin volver a montar.
    await pintar(tester);
    expect(find.textContaining('no ha descargado'), findsOneWidget);

    // Como `llega_la_bajada_test.dart`: se escribe con la pantalla delante, SIN `runAsync` (con un
    // stream de Drift vivo, `runAsync` deja la prueba colgada en vez de fallar).
    await sembrar();
    await asentar(tester);
    await abrirElDesplegable(tester);
    expect(find.text('Juan Pérez'), findsOneWidget,
        reason: 'con un Future la lista se quedaria vacia para siempre en la web');
    await desmontar(tester);
  });
}
