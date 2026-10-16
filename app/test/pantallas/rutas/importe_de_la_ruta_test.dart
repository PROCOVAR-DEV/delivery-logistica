// EL IMPORTE DE UNA RUTA NO PUEDE SER UN CERO QUE NADIE DESMIENTE.
//
// El 22/09/2026, en producción, `RT-20260921-007` decía **«sin cotizar» en sus
// dos paradas** y a la vez **`$0.00`** en su tarjeta y en su cabecera, con el
// camión cotizado a 1,50 USD/km y 10,4 km de recorrido. No se lee como «no hay
// tarifa»: se lee como que el reparto salió gratis, y es el fallo más caro de
// este proyecto —un número creíble y equivocado que ninguna pantalla desmiente
// (`CLAUDE.md` §2 y §4).
//
// Las pruebas van **en pareja**, y eso no es simetría de adorno: una que sólo
// comprueba el caso malo deja pasar un aviso que sale siempre, y un aviso que
// sale siempre deja de leerse (`CLAUDE.md` §3-quinquies). Por eso de cada cosa
// hay dos: que lo diga cuando falta cotizar, y que **no** lo diga cuando no.
//
// Y la cabecera del detalle se prueba SUELTA, con un `RutaConTodo` armado a
// mano: dentro de un `testWidgets` una consulta de Drift cuelga la prueba en vez
// de fallarla (`CLAUDE.md` §5), y un cuelgue no prueba nada. Por eso
// `LineaDeDatosDeLaRuta` es pública.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/pedidos/datos/formato.dart';
import 'package:reparto/pantallas/rutas/datos/importe_de_la_ruta.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/lista_rutas.dart';
import 'package:reparto/idioma.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';
import 'rutas_a_mano.dart';

/// Una parada con su costo puesto o sin poner. `null` es **«no se sabe»**, que
/// es justo lo que un `0` no puede decir.
Pedido paradaCon({required String id, required double? costo}) => Pedido(
  id: id,
  customerName: 'Cliente $id',
  address: 'Calle $id',
  weight: 10,
  status: EstadoPedido.pendiente,
  tripLeg: Tramo.ida,
  archivado: false,
  pedidoCosto: costo,
);

void main() {
  // ---------------------------------------------------------------- la regla
  group('ImporteDeRuta.deLasParadas', () {
    test('con TODAS cotizadas hay total, y no hay nada que avisar', () {
      final importe = ImporteDeRuta.deLasParadas(const [10.0, 5.5, 4.5]);

      expect(importe.total, 20.0);
      expect(importe.sinCotizar, 0);
      expect(importe.paradas, 3);
      expect(importe.completo, isTrue);
      expect(importe.rotulo, r'$20.00');
      expect(
        importe.queFalta,
        isNull,
        reason:
            'EL AVISO NO PUEDE SALIR SIEMPRE. Con las tres paradas cotizadas no '
            'falta nada, y un aviso que sale también aquí deja de leerse el día '
            'que de verdad falta algo.',
      );
    });

    test('con UNA sin cotizar no hay total, y se dice cuántas de cuántas', () {
      final importe = ImporteDeRuta.deLasParadas(const [10.0, null, 4.5]);

      expect(
        importe.total,
        isNull,
        reason:
            'UN TOTAL A MEDIAS ES PEOR QUE NINGUNO: sumar lo que hay e ignorar '
            'los nulos da 14.50, un número que parece completo y se queda '
            'corto. Y es un número que alguien cobra.',
      );
      expect(importe.sinCotizar, 1);
      expect(importe.paradas, 3);
      expect(importe.completo, isFalse);
      expect(
        importe.rotulo,
        '— (1 de 3 sin cotizar)',
        reason:
            'NUNCA UN \$0.00 NI UN GUION MUDO. El guion dice que no se sabe; el '
            'paréntesis dice cuántas faltan y de cuántas, que es lo único con '
            'lo que alguien puede ir a arreglarlo.',
      );
      expect(importe.queFalta, contains('1 parada de 3'));
    });

    test('con DOS sin cotizar el aviso va en plural y las cuenta', () {
      final importe = ImporteDeRuta.deLasParadas(const [null, null, 4.5, 1.0]);

      expect(importe.sinCotizar, 2);
      expect(importe.rotulo, '— (2 de 4 sin cotizar)');
      expect(importe.queFalta, contains('Faltan cotizar 2 paradas de 4'));
      expect(importe.rotulo, isNot(contains('0.00')));
    });

    test('una ruta SIN paradas vale cero, y eso sí es una cifra', () {
      final importe = ImporteDeRuta.deLasParadas(const []);

      expect(importe.total, 0);
      expect(importe.sinCotizar, 0);
      expect(importe.rotulo, r'$0.00');
      expect(importe.queFalta, isNull);
    });
  });

  // ------------------------------------------------- lo que sale de la base
  group('importePorRuta', () {
    late BaseLocal base;
    setUp(() => base = baseDePrueba());
    tearDown(() => base.close());

    test('una parada sin cotizar tira el total de SU ruta y sólo de ésa', () async {
      await sembrarCatalogo(base);
      await sembrarRuta(base, id: 'R1');
      await sembrarRuta(base, id: 'R2');
      await sembrarPedido(base, id: 'p1', cliente: 'Ana', rutaId: 'R1', pedidoCosto: 12.5);
      await sembrarPedido(base, id: 'p2', cliente: 'Beto', rutaId: 'R1', pedidoCosto: null, facturaDomicilio: null);
      await sembrarPedido(base, id: 'p3', cliente: 'Cira', rutaId: 'R2', pedidoCosto: 7.5);

      final porRuta = await importePorRuta(base).first;

      expect(porRuta['R1']!.total, isNull);
      expect(porRuta['R1']!.sinCotizar, 1);
      expect(
        porRuta['R1']!.paradas,
        2,
        reason:
            'SIN EL DENOMINADOR el rótulo no puede decir «1 de 2», y «falta 1» '
            'no distingue un fleco de una ruta entera sin precio.',
      );
      // Y LA DE AL LADO NO SE CONTAGIA: el nulo tira su suma, no la de todas.
      expect(porRuta['R2']!.total, 7.5);
      expect(porRuta['R2']!.sinCotizar, 0);
    });

    test('con todas cotizadas la suma es la suma', () async {
      await sembrarCatalogo(base);
      await sembrarRuta(base, id: 'R1');
      await sembrarPedido(base, id: 'p1', cliente: 'Ana', rutaId: 'R1', pedidoCosto: 12.5);
      await sembrarPedido(base, id: 'p2', cliente: 'Beto', rutaId: 'R1', pedidoCosto: 7.5);

      final porRuta = await importePorRuta(base).first;

      expect(porRuta['R1']!.total, 20.0);
      expect(porRuta['R1']!.sinCotizar, 0);
      expect(porRuta['R1']!.paradas, 2);
      expect(porRuta['R1']!.rotulo, r'$20.00');
    });
  });

  // --------------------------------------------- la cabecera del detalle
  group('la cabecera del detalle', () {
    Future<void> pintar(WidgetTester tester, RutaConTodo ruta) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LineaDeDatosDeLaRuta(ruta: ruta)),
      ),
    );

    testWidgets('con una parada sin cotizar NO escribe un importe, y dice qué falta', (
      tester,
    ) async {
      await pintar(
        tester,
        rutaAMano(
          paradas: [
            paradaCon(id: 'p1', costo: 8.0),
            paradaCon(id: 'p2', costo: null),
          ],
        ),
      );

      expect(
        find.textContaining(r'$0.00'),
        findsNothing,
        reason:
            'ES EL FALLO DE RT-20260921-007: la cabecera decía \$0.00 mientras '
            'sus dos paradas decían «sin cotizar» en la misma pantalla.',
      );
      // Ni el importe a medias: 8.00 es cierto y está incompleto, que es peor.
      expect(find.textContaining(r'$8.00'), findsNothing);
      expect(find.textContaining('— (1 de 2 sin cotizar)'), findsOneWidget);
      expect(
        find.textContaining('Falta cotizar 1 parada de 2'),
        findsOneWidget,
        reason: 'el «—» dice que no se sabe; esto dice a dónde ir',
      );
    });

    testWidgets('con TODAS cotizadas escribe el importe y el aviso no sale', (
      tester,
    ) async {
      await pintar(
        tester,
        rutaAMano(
          paradas: [
            paradaCon(id: 'p1', costo: 8.0),
            paradaCon(id: 'p2', costo: 12.0),
          ],
        ),
      );

      expect(find.textContaining(r'$20.00'), findsOneWidget);
      expect(
        find.textContaining('sin cotizar'),
        findsNothing,
        reason:
            'UN AVISO QUE SALE SIEMPRE DEJA DE LEERSE, y entonces tampoco se '
            'lee el día que importa (CLAUDE.md §3-quinquies).',
      );
      expect(find.textContaining('Falta'), findsNothing);
    });
  });

  // --------------------------------------------- la tarjeta de la lista
  group('la tarjeta de la lista', () {
    late BaseLocal base;
    final ahora = DateTime(2026, 9, 22, 16, 5);

    setUp(() => base = baseDePrueba());
    tearDown(() => base.close());

    Future<void> asentar(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pintar(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(base),
            relojProvider.overrideWithValue(() => ahora),
          ],
          child: MaterialApp(
            localizationsDelegates: delegacionesDeIdioma,
            supportedLocales: idiomas,
            home: const Scaffold(
              body: ListaDeRutas(deLaPestana: PestanaRutas.enCurso),
            ),
          ),
        ),
      );
      await asentar(tester);
    }

    Future<void> desmontar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    }

    Future<void> sembrarLaRuta(List<double?> costos) async {
      await sembrarCatalogo(base);
      await RegistroDeFrescura(
        base,
        reloj: () => ahora,
      ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);
      await sembrarRuta(
        base,
        id: 'R1',
        codigo: 'RT-20260921-007',
        estado: EstadoRuta.enCurso,
        creada: ahora,
      );
      for (var i = 0; i < costos.length; i++) {
        await sembrarPedido(
          base,
          id: 'p${i + 1}',
          cliente: 'Cliente ${i + 1}',
          rutaId: 'R1',
          orden: i + 1,
          pedidoCosto: costos[i],
          // Sin cotizar de verdad: tampoco cobrado en la factura (`costoDeLaParada`).
          facturaDomicilio: null,
        );
      }
    }

    testWidgets('con paradas sin cotizar la tarjeta NO dice \$0.00', (
      tester,
    ) async {
      await sembrarLaRuta([null, null]);
      await pintar(tester);

      expect(
        find.text(r'$0.00'),
        findsNothing,
        reason:
            'ES LO QUE SE VIO EN PRODUCCIÓN el 22/09/2026: la tarjeta de '
            'RT-20260921-007 en \$0.00 con sus dos paradas sin cotizar. Un cero '
            'es un precio: dice que el reparto salió gratis.',
      );
      expect(find.text('— (2 de 2 sin cotizar)'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('con todas cotizadas la tarjeta dice el importe, y nada más', (
      tester,
    ) async {
      await sembrarLaRuta([12.5, 7.5]);
      await pintar(tester);

      expect(find.text(r'$20.00'), findsOneWidget);
      expect(
        find.textContaining('sin cotizar'),
        findsNothing,
        reason: 'la mitad que falta en la pareja: que NO salga cuando no toca',
      );

      await desmontar(tester);
    });
  });

  // ------------------------------------------------------------- el 0 min
  group('duracion', () {
    test('una hora exacta se escribe «1 h», sin el 0 min colgando', () {
      expect(
        duracion(DateTime(2026, 9, 22, 8), DateTime(2026, 9, 22, 9)),
        '1 h',
        reason:
            'ESE «0 min» SE LEYÓ EN PANTALLA. Va pegado por puntos a los km, al '
            'peso y al importe en el renglón de datos del detalle, y un cero '
            'suelto ahí dentro se lee como un dato que falta.',
      );
      expect(
        duracion(DateTime(2026, 9, 22, 8), DateTime(2026, 9, 22, 11)),
        '3 h',
      );
    });

    test('con minutos se escriben los dos, que es lo de siempre', () {
      expect(
        duracion(DateTime(2026, 9, 22, 8), DateTime(2026, 9, 22, 11, 20)),
        '3 h 20 min',
      );
      expect(
        duracion(DateTime(2026, 9, 22, 8), DateTime(2026, 9, 22, 8, 45)),
        '45 min',
      );
      // Menos de un minuto no es «—»: es cero minutos y se sabe.
      expect(
        duracion(DateTime(2026, 9, 22, 8), DateTime(2026, 9, 22, 8)),
        '0 min',
      );
    });
  });
}
