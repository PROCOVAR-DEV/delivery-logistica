// EL CAJON DE «DISTRIBUIDORES» — issue 7 de Amado, 14/10/2026.
//
// Crear, renombrar, retirar, volver a activar y borrar a quienes reparten en una sucursal. Cada toque
// es UNA peticion, y la pantalla tiene que decir LO QUE PASO, con las mismas exigencias que el cajon
// de Tipos de vehiculo (que edita la lista entera y por eso tiene su `GuardadoAMedias`):
//
//  * el «no» del servidor se ensena LITERAL (el 409 del nombre repetido dice cual es);
//  * una red que se cae NO se resuelve adivinando: se vuelve a leer la lista y se dice «ya esta
//    guardado» (la respuesta se perdio) o «NO se guardo» o, si ni leer se puede, «no se sabe»;
//  * borrar solo se ofrece a quien ninguna ruta usa; el que se usa se RETIRA, y si el servidor lo
//    retira en vez de borrarlo (una ruta lo uso mientras tanto) la pantalla lo dice;
//  * y cada escritura que el servidor confirma queda tambien en la base local, que es de donde mira
//    el selector de «Nueva ruta».
//
// Habla el CONTRATO REAL de `api/internal/api/distribuidores.go` en un servidor falso CON memoria.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/distribuidores/vista/cajon_distribuidores.dart';

import '../../apoyo/servidor_falso.dart';
import '../vehiculos/apoyo_vehiculos.dart';

void main() {
  /// Un servidor con memoria que habla el contrato de `/api/distribuidores`.
  ///
  /// `usados` son los ids que alguna ruta usa: borrarlos los RETIRA. [forzar] contesta antes que la
  /// tabla (un 403, un corte); `null` deja pasar. [sinRed] simula la red caida: `null` = la
  /// peticion ni sale.
  ({Banco banco, List<Map<String, Object?>> filas}) montarServidor({
    List<Map<String, Object?>> filas = const [],
    Set<String> usados = const {},
    Future<RespuestaFalsa?>? Function(PeticionVista)? forzar,
  }) {
    var siguiente = 0;
    final guardados = [
      for (final f in filas)
        <String, Object?>{
          'id': 'd${siguiente++}',
          'activo': true,
          'sucursalId': 'B1',
          'sucursal': 'Camagüey',
          'rutas': 0,
          ...f,
        },
    ];
    const yaExiste = <String, Object?>{
      'error': 'Ya existe un distribuidor con ese nombre en esta sucursal',
    };
    bool repetido(Object? nombre, {String? salvo}) => guardados.any(
      (d) =>
          d['id'] != salvo &&
          (d['nombre']! as String).toLowerCase() ==
              (nombre! as String).toLowerCase(),
    );
    final banco = Banco((p) async {
      final forzada = forzar?.call(p);
      if (forzada != null) return forzada;
      if (!p.ruta.contains('/distribuidores')) {
        return RespuestaFalsa(404, const <String, Object?>{'error': 'Not found'});
      }
      final id = p.ruta.split('/').last;
      final cuerpo = p.cuerpo as Map<String, Object?>?;
      final fila = guardados.where((d) => d['id'] == id).firstOrNull;
      switch (p.metodo) {
        case 'POST':
          if (repetido(cuerpo!['nombre'])) return RespuestaFalsa(409, yaExiste);
          final nuevo = <String, Object?>{
            'id': 'd${siguiente++}',
            'activo': true,
            'sucursalId': 'B1',
            'sucursal': 'Camagüey',
            'rutas': 0,
            'nombre': cuerpo['nombre'],
          };
          guardados.add(nuevo);
          return RespuestaFalsa(201, nuevo);
        case 'PATCH':
          if (fila == null) {
            return RespuestaFalsa(404, const <String, Object?>{'error': 'Not found'});
          }
          if (cuerpo!.containsKey('nombre') && repetido(cuerpo['nombre'], salvo: id)) {
            return RespuestaFalsa(409, yaExiste);
          }
          fila.addAll(cuerpo);
          return RespuestaFalsa(200, fila);
        case 'DELETE':
          if (fila == null) {
            return RespuestaFalsa(404, const <String, Object?>{'error': 'Not found'});
          }
          final enUso = usados.contains(id) || (fila['rutas']! as int) > 0;
          if (enUso) {
            fila['activo'] = false;
          } else {
            guardados.remove(fila);
          }
          return RespuestaFalsa(200, <String, Object?>{'success': true, 'retirado': enUso});
      }
      return RespuestaFalsa(200, guardados);
    });
    return (banco: banco, filas: guardados);
  }

  Future<void> pintar(WidgetTester tester, Banco banco) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(banco.base),
          clienteApiProvider.overrideWithValue(banco.contenedor.read(clienteApiProvider)),
        ],
        child: const MaterialApp(home: Scaffold(body: CajonDeDistribuidores())),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> asentar(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );

  String? aviso(WidgetTester tester) {
    final w = find.byKey(CajonDeDistribuidores.claveDelAviso);
    if (w.evaluate().isEmpty) return null;
    return tester.widget<Container>(w).child is Text
        ? (tester.widget<Container>(w).child! as Text).data
        : null;
  }

  List<String> escrituras(Banco banco) => [
    for (final p in banco.servidor.vistas)
      if (p.metodo != 'GET') '${p.metodo} ${p.ruta}',
  ];

  Future<List<Distribuidor>> locales(Banco banco) => banco.base.select(banco.base.distribuidores).get();

  testWidgets('enseña los de la sucursal, con los retirados aparte y cuantas rutas usa cada uno', (tester) async {
    final m = montarServidor(filas: [
      {'nombre': 'Juan Pérez', 'rutas': 3},
      {'nombre': 'María López'},
      {'nombre': 'Pedro Gil', 'activo': false},
    ]);
    addTearDown(m.banco.cerrar);
    await pintar(tester, m.banco);

    expect(find.text('Juan Pérez'), findsOneWidget);
    expect(find.text('María López'), findsOneWidget);
    expect(find.text('Pedro Gil'), findsOneWidget, reason: 'los retirados se VEN: para volver a activarlos');
    expect(find.text('Retirado'), findsOneWidget);
    expect(find.text('3 rutas'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('lista vacia: lo dice y no finge una pantalla rota', (tester) async {
    final m = montarServidor();
    addTearDown(m.banco.cerrar);
    await pintar(tester, m.banco);
    expect(find.textContaining('no tiene distribuidores'), findsOneWidget);
    await desmontar(tester);
  });

  group('agregar', () {
    testWidgets('lo crea en el servidor, lo deja en la base local y lo dice', (tester) async {
      final m = montarServidor();
      addTearDown(m.banco.cerrar);
      await pintar(tester, m.banco);

      await tester.enterText(find.byKey(CajonDeDistribuidores.claveDelCampoNuevo), '  Ana Torres ');
      await tester.tap(find.text('Agregar'));
      await asentar(tester);

      expect(escrituras(m.banco), ['POST /distribuidores']);
      expect((m.banco.servidor.vistas.firstWhere((p) => p.metodo == 'POST').cuerpo! as Map)['nombre'], 'Ana Torres',
          reason: 'el nombre viaja limpio, sin los espacios de los bordes');
      expect(find.text('Ana Torres'), findsOneWidget);
      expect(aviso(tester), 'Distribuidor «Ana Torres» agregado.');
      expect((await tester.runAsync(() => locales(m.banco)))!.map((d) => d.nombre), ['Ana Torres'],
          reason: 'el selector de «Nueva ruta» mira la base: tiene que verlo en el acto');
      expect(
        tester.widget<TextField>(find.byKey(CajonDeDistribuidores.claveDelCampoNuevo)).controller!.text,
        isEmpty,
        reason: 'se guardo: el campo se vacia para el siguiente',
      );
      await desmontar(tester);
    });

    testWidgets('un nombre repetido: el 409 se ensena LITERAL, no se escribe nada y el campo se queda', (tester) async {
      final m = montarServidor(filas: [{'nombre': 'Juan Pérez'}]);
      addTearDown(m.banco.cerrar);
      await pintar(tester, m.banco);

      await tester.enterText(find.byKey(CajonDeDistribuidores.claveDelCampoNuevo), 'juan pérez');
      await tester.tap(find.text('Agregar'));
      await asentar(tester);

      expect(aviso(tester), 'Ya existe un distribuidor con ese nombre en esta sucursal');
      expect(m.filas, hasLength(1));
      expect((await tester.runAsync(() => locales(m.banco)))!, isEmpty,
          reason: 'lo que el servidor rechazo no se escribe en la base local');
      expect(
        tester.widget<TextField>(find.byKey(CajonDeDistribuidores.claveDelCampoNuevo)).controller!.text,
        'juan pérez',
        reason: 'no se guardo: lo escrito no se pierde',
      );
      await desmontar(tester);
    });

    testWidgets('en modo «todas» el «elige una sucursal» del servidor sale tal cual', (tester) async {
      final m = montarServidor(forzar: (p) => p.metodo == 'POST'
          ? Future.value(RespuestaFalsa(400, const <String, Object?>{
              'error': 'Elige una sucursal arriba para crear el distribuidor: los distribuidores son de cada sucursal.',
            }))
          : null);
      addTearDown(m.banco.cerrar);
      await pintar(tester, m.banco);
      await tester.enterText(find.byKey(CajonDeDistribuidores.claveDelCampoNuevo), 'Ana');
      await tester.tap(find.text('Agregar'));
      await asentar(tester);
      expect(aviso(tester), startsWith('Elige una sucursal arriba'));
      await desmontar(tester);
    });

    testWidgets('un nombre vacio no sale a la red', (tester) async {
      final m = montarServidor();
      addTearDown(m.banco.cerrar);
      await pintar(tester, m.banco);
      await tester.enterText(find.byKey(CajonDeDistribuidores.claveDelCampoNuevo), '   ');
      await tester.tap(find.text('Agregar'));
      await asentar(tester);
      expect(escrituras(m.banco), isEmpty);
      await desmontar(tester);
    });
  });

  group('renombrar', () {
    testWidgets('cambia el nombre, solo ese campo, y lo dice', (tester) async {
      final m = montarServidor(filas: [{'nombre': 'Juan Pérez'}]);
      addTearDown(m.banco.cerrar);
      await pintar(tester, m.banco);

      await tester.tap(find.byKey(CajonDeDistribuidores.claveDeRenombrar('d0')));
      await asentar(tester);
      await tester.enterText(find.byType(TextField).last, 'Juan Carlos Pérez');
      await tester.tap(find.byTooltip('Guardar el nombre'));
      await asentar(tester);

      expect(m.banco.servidor.vistas.where((p) => p.metodo == 'PATCH').single.cuerpo, {'nombre': 'Juan Carlos Pérez'},
          reason: 'solo lo que se cambio: mandar tambien `activo` pisaria lo que hizo otra persona');
      expect(find.text('Juan Carlos Pérez'), findsOneWidget);
      expect(aviso(tester), '«Juan Pérez» ahora es «Juan Carlos Pérez».');
      await desmontar(tester);
    });

    testWidgets('a un nombre que ya existe: 409 literal y el de antes se queda', (tester) async {
      final m = montarServidor(filas: [{'nombre': 'Juan Pérez'}, {'nombre': 'María López'}]);
      addTearDown(m.banco.cerrar);
      await pintar(tester, m.banco);

      await tester.tap(find.byKey(CajonDeDistribuidores.claveDeRenombrar('d1')));
      await asentar(tester);
      await tester.enterText(find.byType(TextField).last, 'Juan Pérez');
      await tester.tap(find.byTooltip('Guardar el nombre'));
      await asentar(tester);

      expect(aviso(tester), startsWith('Ya existe un distribuidor con ese nombre'));
      expect(m.filas[1]['nombre'], 'María López');
      await desmontar(tester);
    });

    testWidgets('dejarlo igual no manda nada', (tester) async {
      final m = montarServidor(filas: [{'nombre': 'Juan Pérez'}]);
      addTearDown(m.banco.cerrar);
      await pintar(tester, m.banco);
      await tester.tap(find.byKey(CajonDeDistribuidores.claveDeRenombrar('d0')));
      await asentar(tester);
      await tester.tap(find.byTooltip('Guardar el nombre'));
      await asentar(tester);
      expect(escrituras(m.banco), isEmpty);
      await desmontar(tester);
    });
  });

  group('retirar y volver a activar', () {
    testWidgets('retirar cambia solo `activo`, y activar lo devuelve', (tester) async {
      final m = montarServidor(filas: [{'nombre': 'Juan Pérez'}]);
      addTearDown(m.banco.cerrar);
      await pintar(tester, m.banco);

      await tester.tap(find.byKey(CajonDeDistribuidores.claveDeRetirar('d0')));
      await asentar(tester);
      expect(m.banco.servidor.vistas.where((p) => p.metodo == 'PATCH').last.cuerpo, {'activo': false});
      expect(aviso(tester), contains('está retirado'));
      expect(find.text('Retirado'), findsOneWidget);
      expect((await tester.runAsync(() => locales(m.banco)))!.single.activo, isFalse,
          reason: 'retirado en el servidor, retirado en la base local: el selector ya no lo ofrece');

      await tester.tap(find.byKey(CajonDeDistribuidores.claveDeRetirar('d0')));
      await asentar(tester);
      expect(m.banco.servidor.vistas.where((p) => p.metodo == 'PATCH').last.cuerpo, {'activo': true});
      expect(find.text('Retirado'), findsNothing);
      await desmontar(tester);
    });
  });

  group('borrar', () {
    testWidgets('al que ninguna ruta usa: pregunta, y al decir que si se borra de verdad', (tester) async {
      final m = montarServidor(filas: [{'nombre': 'Juan Pérez'}]);
      addTearDown(m.banco.cerrar);
      await pintar(tester, m.banco);

      await tester.tap(find.byKey(CajonDeDistribuidores.claveDeBorrar('d0')));
      await asentar(tester);
      expect(escrituras(m.banco), isEmpty, reason: 'borrar de verdad se pregunta antes');
      await tester.tap(find.textContaining('Sí, borrar'));
      await asentar(tester);

      expect(escrituras(m.banco), ['DELETE /distribuidores/d0']);
      expect(find.text('Juan Pérez'), findsNothing);
      expect(aviso(tester), '«Juan Pérez» borrado.');
      await desmontar(tester);
    });

    testWidgets('y si dice que no, no se manda nada', (tester) async {
      final m = montarServidor(filas: [{'nombre': 'Juan Pérez'}]);
      addTearDown(m.banco.cerrar);
      await pintar(tester, m.banco);
      await tester.tap(find.byKey(CajonDeDistribuidores.claveDeBorrar('d0')));
      await asentar(tester);
      await tester.tap(find.text('No, dejarlo'));
      await asentar(tester);
      expect(escrituras(m.banco), isEmpty);
      expect(find.text('Juan Pérez'), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('al que una ruta usa NO se ofrece borrar: solo retirar', (tester) async {
      final m = montarServidor(filas: [{'nombre': 'Juan Pérez', 'rutas': 2}]);
      addTearDown(m.banco.cerrar);
      await pintar(tester, m.banco);
      expect(find.byKey(CajonDeDistribuidores.claveDeBorrar('d0')), findsNothing,
          reason: 'borrarlo dejaria las rutas sin decir quien las reparte');
      expect(find.byKey(CajonDeDistribuidores.claveDeRetirar('d0')), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('si una ruta lo uso ENTRE medias, el servidor lo retira y la pantalla lo dice', (tester) async {
      final m = montarServidor(filas: [{'nombre': 'Juan Pérez'}], usados: {'d0'});
      addTearDown(m.banco.cerrar);
      await pintar(tester, m.banco);
      await tester.tap(find.byKey(CajonDeDistribuidores.claveDeBorrar('d0')));
      await asentar(tester);
      await tester.tap(find.textContaining('Sí, borrar'));
      await asentar(tester);
      expect(aviso(tester), contains('no se borró: quedó retirado'),
          reason: 'decir «borrado» de algo que sigue ahi, retirado, seria mentir');
      expect(find.text('Juan Pérez'), findsOneWidget);
      await desmontar(tester);
    });
  });

  group('la red que se cae a mitad se RECONCILIA, no se adivina', () {
    testWidgets('el servidor SI guardo y la respuesta se perdio: se dice «ya esta guardado»', (tester) async {
      // El POST llega y se guarda (la tabla lo apunta), pero la respuesta no vuelve nunca.
      final m = montarServidor(forzar: (p) => p.metodo == 'POST' ? Future.value(null) : null);
      addTearDown(m.banco.cerrar);
      await pintar(tester, m.banco);
      // Lo que el POST habria escrito en el servidor antes de cortarse la respuesta.
      m.filas.add(<String, Object?>{
        'id': 'dX', 'nombre': 'Ana Torres', 'activo': true, 'sucursalId': 'B1', 'sucursal': 'Camagüey', 'rutas': 0,
      });

      await tester.enterText(find.byKey(CajonDeDistribuidores.claveDelCampoNuevo), 'Ana Torres');
      await tester.tap(find.text('Agregar'));
      await asentar(tester);

      expect(aviso(tester), contains('ya está guardado'),
          reason: 'decir «no se guardo» de algo que SI esta arriba es el fallo de los tipos');
      await desmontar(tester);
    });

    testWidgets('el servidor NO guardo: se dice «NO se guardo»', (tester) async {
      final m = montarServidor(forzar: (p) => p.metodo == 'POST' ? Future.value(null) : null);
      addTearDown(m.banco.cerrar);
      await pintar(tester, m.banco);
      await tester.enterText(find.byKey(CajonDeDistribuidores.claveDelCampoNuevo), 'Ana Torres');
      await tester.tap(find.text('Agregar'));
      await asentar(tester);
      expect(aviso(tester), contains('NO se guardó'));
      expect(m.filas, isEmpty);
      await desmontar(tester);
    });

    testWidgets('y si ni LEER se puede, se dice que NO SE SABE', (tester) async {
      var sinRed = false;
      final m = montarServidor(forzar: (p) {
        if (p.metodo == 'POST') {
          sinRed = true;
          return Future.value(null);
        }
        return sinRed ? Future.value(null) : null;
      });
      addTearDown(m.banco.cerrar);
      await pintar(tester, m.banco);
      await tester.enterText(find.byKey(CajonDeDistribuidores.claveDelCampoNuevo), 'Ana Torres');
      await tester.tap(find.text('Agregar'));
      await asentar(tester);
      expect(aviso(tester), contains('no se sabe si se guardó'));
      await desmontar(tester);
    });
  });

  testWidgets('un doble toque en «Agregar» manda UN alta', (tester) async {
    final m = montarServidor();
    addTearDown(m.banco.cerrar);
    await pintar(tester, m.banco);
    await tester.enterText(find.byKey(CajonDeDistribuidores.claveDelCampoNuevo), 'Ana Torres');
    await tester.tap(find.text('Agregar'));
    await tester.tap(find.text('Agregar'));
    await asentar(tester);
    expect(escrituras(m.banco), ['POST /distribuidores'],
        reason: 'un doble toque no puede dar de alta a la misma persona dos veces');
    await desmontar(tester);
  });

  testWidgets('sin red la lista no se lee y se dice QUE se rompe y que SIGUE sirviendo', (tester) async {
    final m = montarServidor(forzar: (_) => Future.value(null));
    addTearDown(m.banco.cerrar);
    await pintar(tester, m.banco);
    expect(find.textContaining('Sin conexión con el servidor'), findsOneWidget);
    expect(find.textContaining('se sigue pudiendo elegir al crear una ruta'), findsOneWidget,
        reason: 'lo bajado en el aparato sigue sirviendo sin red: eso es lo que importa decir');
    expect(find.text('Reintentar'), findsOneWidget);
    await desmontar(tester);
  });
}
