import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/navegacion/franja_de_estado.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/proveedores.dart';

import '../apoyo/base_de_prueba.dart';

/// LA RUTA QUE SUBIÓ CON MENOS PEDIDOS DE LOS QUE SE PUSIERON **SE DICE**.
///
/// ## El agujero que cierra
///
/// Un apunte puede aplicarse y aun así dejar gente fuera. Armar una zona de doce
/// devuelve 201 con la ruta creada y, en el mismo cuerpo, quién se cayó y por
/// qué (`api/internal/api/tablero.go`, `DescartadoSalida`). `ColaDeSalida.
/// resolver` sólo miraba `resultado.id`, así que **la ruta salía con nueve y no
/// había ni un aviso en ningún sitio**: ni en «N sin subir» —ya subió—, ni en la
/// bandeja —no lo rechazó nadie—, ni en el Panel.
///
/// ## Por qué se dice AQUÍ
///
/// Porque el apunte sube horas después, con la pantalla del Tablero cerrada:
/// cuando se sabe la respuesta no hay nadie delante de donde se armó. La franja
/// está en las siete pantallas y es lo único que hace que alguien abra el cajón,
/// que es donde el aviso se lee entero, con el pedido nombrado y qué hacer.
///
/// ## Y la otra mitad: que NO salga cuando no toca
///
/// Un aviso que sale siempre deja de leerse, y entonces tampoco se lee el día
/// que importa (`CLAUDE.md` §3-quinquies). Un armado normal —que subió con todo
/// lo que llevaba— no puede encender nada.
///
/// ## Sobre el tiempo
///
/// Nada de `await` sobre el primer valor de un stream de Drift aquí dentro: el
/// reloj del `tester` no avanza solo y la prueba **se cuelga en vez de fallar**
/// (§5). Se siembra dentro del cuerpo, nunca en el `setUp`, y se avanza a mano.
void main() {
  late BaseLocal base;

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [baseProvider.overrideWith((ref) => base)],
        child: MaterialApp(
          theme: temaDeReparto(),
          home: const Scaffold(body: FranjaDeEstado()),
        ),
      ),
    );
    await tester.pump();
  }

  Future<bool> saleEl(WidgetTester tester, Finder que) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (que.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Un apunte de armar una zona que YA SUBIÓ. [conAviso] es lo que el servidor
  /// contestó de los que dejó fuera.
  Future<void> unArmadoQueSubio({String? conAviso}) async {
    final clave = await ColaDeSalida(base).encolar(
      metodo: 'POST',
      ruta: '/board/columns/z-vista/route',
      cuerpo: const <String, Object?>{'optimizar': false},
      provisional: 'local-9f3a2b7c',
    );
    await (base.update(
      base.apuntes,
    )..where((a) => a.clave.equals(clave))).write(
      ApuntesCompanion(
        estado: const Value(EstadoApunte.aplicado),
        resueltoAt: Value(DateTime.now()),
        motivo: conAviso == null ? const Value.absent() : Value(conAviso),
      ),
    );
  }

  final elAviso = find.textContaining('con menos pedidos de los que pusiste');

  testWidgets('el armado que subió dejando gente fuera SE DICE, y aparece con '
      'la pantalla ya abierta', (tester) async {
    await montar(tester);

    expect(
      elAviso,
      findsNothing,
      reason: 'todavía no ha subido nada; avisar aquí es avisar siempre',
    );

    // Y AHORA, sin que nadie vuelva a montar nada: el apunte sube y el
    // servidor contesta que uno se quedó fuera. Esto llega horas después, con
    // la pantalla del Tablero cerrada — por eso tiene que entrar con la
    // pantalla delante y no calcularse al pintar (§4-bis).
    await unArmadoQueSubio(
      conAviso:
          'Un pedido de los que armaste NO subió a ese camión:\n'
          'X-2992 · Ana Pérez: ya no estaba en esa zona cuando llegó tu apunte',
    );

    expect(
      await saleEl(tester, elAviso),
      isTrue,
      reason:
          'LA FRANJA NO SE ENTERÓ. La ruta se armó arriba con menos pedidos de '
          'los que el logístico puso, el servidor dijo quién se cayó y por qué, '
          'y no lo lee nadie: es el §4 al revés, «nada se descarta en silencio»',
    );
    expect(
      find.text('Una ruta subió con menos pedidos de los que pusiste'),
      findsOneWidget,
    );
    // Y NO se cuenta como «sin subir»: subió. Confundirlos es lo que hace que
    // el número de arriba no baje nunca a cero.
    expect(find.textContaining('sin subir'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('LO NORMAL NO AVISA: un armado que subió entero no enciende nada', (
    tester,
  ) async {
    await montar(tester);

    await unArmadoQueSubio();

    // Se le da el mismo tiempo que al caso bueno: si con esto sale, sale
    // siempre, y un aviso que sale siempre deja de leerse.
    expect(
      await saleEl(tester, elAviso),
      isFalse,
      reason:
          'nadie se cayó, así que no hay nada que decir. Avisar aquí es avisar '
          'en cada armado (§3-quinquies), y entonces tampoco se lee el día que '
          'importa',
    );

    await desmontar(tester);
  });

  testWidgets('un RECHAZADO no se cuenta aquí: ése tiene su bandeja y sí se '
      'puede reintentar', (tester) async {
    await montar(tester);

    final clave = await ColaDeSalida(base).encolar(
      metodo: 'POST',
      ruta: '/board/columns/z-vista/route',
      cuerpo: const <String, Object?>{},
    );
    await (base.update(
      base.apuntes,
    )..where((a) => a.clave.equals(clave))).write(
      ApuntesCompanion(
        estado: const Value(EstadoApunte.rechazado),
        motivo: const Value('Ese pedido ya va en otra ruta'),
        resueltoAt: Value(DateTime.now()),
      ),
    );

    expect(
      await saleEl(tester, elAviso),
      isFalse,
      reason:
          'un rechazado NO subió y se puede reintentar; esto otro SÍ subió y '
          'reintentarlo armaría una segunda ruta. Contarlos juntos ofrecería '
          'el gesto equivocado',
    );

    await desmontar(tester);
  });
}
