// FACTURAS DEVUELTAS Y CANCELADAS EN PANTALLA — issue 25 de Amado, 05/11/2026, a 390 px (teléfono, tarjetas)
// y a 1440 px (escritorio, tabla).
//
// Forma del §3-ter de CLAUDE.md: se monta con la base VACÍA y se siembra DESPUÉS, dentro del cuerpo y sin
// volver a montar. Lo que se mira es lo que lee quien está delante:
//
//  * la devuelta lleva la marca «Devuelta» y la nueva NO (en pareja);
//  * la ficha de una devuelta ofrece «Cancelar la factura»; la de una nueva no;
//  * el cajón pide una nota opcional, cancela de verdad (base local + apunte) y la ficha pasa a «Cancelada»;
//  * si el servidor dice que no (web), el motivo sale LITERAL en el cajón y la factura sigue devuelta;
//  * la pestaña «Canceladas»: contador, la factura, el cliente, la fecha en hora de Cuba y la nota.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/diseno/marca_devuelta.dart';
import 'package:reparto/diseno/pestanas.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';
import 'package:reparto/pantallas/pedidos/datos/acciones_de_pedido.dart';
import 'package:reparto/pantallas/pedidos/estado/proveedores_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/cancelar_devuelta.dart';
import 'package:reparto/pantallas/pedidos/vista/canceladas.dart';
import 'package:reparto/pantallas/pedidos/vista/pantalla_pedidos.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'sembrar.dart';

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  late BaseLocal base;
  final ahora = DateTime(2026, 11, 5, 9);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> pintar(
    WidgetTester tester,
    Size tamano, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [baseProvider.overrideWithValue(base), ...overrides],
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: const Scaffold(body: PantallaPedidos()),
        ),
      ),
    );
    await asentar(tester);
  }

  /// La bajada que llega DESPUÉS de montar: n nueva, d devuelta, c cancelada (el 4/11 a las 22:30 en Cuba).
  Future<void> llegaLaBajada(WidgetTester tester) async {
    await sembrarCatalogo(base);
    for (final (id, numero, cliente, resultado) in [
      ('n', '47001', 'Cliente Nuevo', null),
      ('d', '47002', 'Cliente Devuelto', ResultadoParada.devuelto),
      ('c', '47003', 'Cliente Cancelado', ResultadoParada.cancelado),
    ]) {
      await sembrarPedido(
        base,
        id: id,
        cliente: cliente,
        facturaNumero: numero,
        resultado: resultado,
        ultimaRutaId: resultado == null ? null : 'R-vieja',
        endLat: 21.38,
        endLng: -77.91,
      );
    }
    await (base.update(base.orders)..where((o) => o.id.equals('c'))).write(
      OrdersCompanion(
        resultadoAt: Value(DateTime.utc(2026, 11, 5, 3, 30)),
        resultadoNota: const Value('Se arrepintió'),
      ),
    );
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.pedidos, hasta: null, bajadaAt: ahora);
    await asentar(tester);
  }

  void prueba(String nombre, Future<void> Function(WidgetTester) cuerpo) =>
      testWidgets(nombre, (tester) async {
        await cuerpo(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
      });

  Future<Pedido> fila(String id) =>
      (base.select(base.orders)..where((o) => o.id.equals(id))).getSingle();

  Future<void> irAPestanaCanceladas(WidgetTester tester, Size tamano) async {
    if (tamano.width < 900) {
      await tester.tap(find.byKey(ClavesDePestanas.adelante));
      await asentar(tester);
      await tester.tap(find.byKey(ClavesDePestanas.adelante));
    } else {
      await tester.tap(find.text(TextosDeCanceladas.pestana));
    }
    await asentar(tester);
  }

  for (final (nombre, tamano) in [
    ('390 px (tarjetas)', const Size(390, 1800)),
    ('1440 px (tabla)', const Size(1440, 1400)),
  ]) {
    group(nombre, () {
      prueba('la devuelta lleva «Devuelta» y la nueva NO (en pareja)', (
        tester,
      ) async {
        await pintar(tester, tamano);
        expect(
          find.text(MarcaDevuelta.texto),
          findsNothing,
          reason: 'con la base vacía no hay nada',
        );
        await llegaLaBajada(tester);

        expect(
          find.text(MarcaDevuelta.texto),
          findsOneWidget,
          reason: 'sólo la devuelta (d); la nueva y la cancelada no la llevan',
        );
        expect(
          find.text('Cancelado'),
          findsOneWidget,
          reason: 'la cancelada sigue diciendo lo que es',
        );
      });

      prueba(
        'la ficha de una devuelta ofrece «Cancelar la factura»; la de una nueva no',
        (tester) async {
          await pintar(tester, tamano);
          await llegaLaBajada(tester);

          await tester.tap(find.textContaining('Cliente Nuevo').first);
          await asentar(tester);
          expect(
            find.byKey(const ValueKey('ficha-cancelar-la-factura')),
            findsNothing,
          );
          expect(find.byKey(const ValueKey('ficha-devuelta')), findsNothing);
          await tester.tap(find.byTooltip('Cerrar').first);
          await asentar(tester);

          await tester.tap(find.textContaining('Cliente Devuelto').first);
          await asentar(tester);
          expect(find.byKey(const ValueKey('ficha-devuelta')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('ficha-cancelar-la-factura')),
            findsOneWidget,
          );
        },
      );

      prueba(
        'cancelar: nota opcional, confirmar, la fila queda cancelada y la ficha lo dice',
        (tester) async {
          await pintar(tester, tamano);
          await llegaLaBajada(tester);
          await tester.tap(find.textContaining('Cliente Devuelto').first);
          await asentar(tester);

          final boton = find.byKey(const ValueKey('ficha-cancelar-la-factura'));
          await tester.ensureVisible(boton);
          await asentar(tester);
          await tester.tap(boton);
          await asentar(tester);
          expect(find.text(TextosDeCancelar.pregunta), findsOneWidget);

          await tester.enterText(
            find.byKey(const ValueKey('cancelar-nota')),
            'El cliente se arrepintió',
          );
          await tester.tap(find.byKey(const ValueKey('cancelar-confirmar')));
          await asentar(tester);

          final d = await fila('d');
          expect(d.resultado, ResultadoParada.cancelado);
          expect(d.resultadoNota, 'El cliente se arrepintió');
          final apuntes = await ColaDeSalida(base).lote();
          expect(apuntes.map((a) => '${a.metodo} ${a.ruta}'), [
            'POST /orders/d/cancelar',
          ]);
          // La ficha, sin cerrarla, ya dice «Cancelada» y ya no ofrece cancelar.
          expect(find.byKey(const ValueKey('ficha-cancelada')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('ficha-cancelar-la-factura')),
            findsNothing,
          );
          expect(find.text('El cliente se arrepintió'), findsWidgets);
        },
      );

      prueba(
        'WEB: si el servidor dice que no, su motivo sale LITERAL en el cajón y sigue devuelta',
        (tester) async {
          final servidor = ServidorFalso(
            (_) async =>
                RespuestaFalsa(409, {'error': 'La factura ya está cancelada'}),
          );
          final web = AccionesDePedido(
            base,
            ColaDeSalida(base),
            enVivo: EscrituraEnVivo(
              ClienteApi(
                dio: Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
                  ..httpClientAdapter = servidor,
                esperas: const <Duration>[],
              ),
            ),
          );
          await pintar(
            tester,
            tamano,
            overrides: [accionesDePedidoProvider.overrideWithValue(web)],
          );
          await llegaLaBajada(tester);
          await tester.tap(find.textContaining('Cliente Devuelto').first);
          await asentar(tester);
          final boton = find.byKey(const ValueKey('ficha-cancelar-la-factura'));
          await tester.ensureVisible(boton);
          await asentar(tester);
          await tester.tap(boton);
          await asentar(tester);
          await tester.tap(find.byKey(const ValueKey('cancelar-confirmar')));
          await asentar(tester);

          expect(find.text('La factura ya está cancelada'), findsOneWidget);
          expect((await fila('d')).resultado, ResultadoParada.devuelto);
          expect(
            await ColaDeSalida(base).lote(),
            isEmpty,
            reason: 'la web no tiene cola',
          );
        },
      );

      prueba(
        'la pestaña «Canceladas»: contador, factura, cliente, fecha en Cuba y nota',
        (tester) async {
          await pintar(tester, tamano);
          await irAPestanaCanceladas(tester, tamano);
          expect(
            find.text('0 canceladas'),
            findsOneWidget,
            reason: 'base vacía: cero, en plural',
          );
          await llegaLaBajada(tester);

          expect(find.text('1 cancelada'), findsOneWidget);
          expect(find.text('Factura 47003'), findsOneWidget);
          expect(find.text('Cliente Cancelado'), findsOneWidget);
          expect(
            find.text('Cancelada el 4/11/2026 22:30'),
            findsOneWidget,
            reason: 'hora de Cuba, no UTC',
          );
          expect(find.text('Se arrepintió'), findsOneWidget);
          // La devuelta y la nueva no salen aquí.
          expect(find.textContaining('Cliente Devuelto'), findsNothing);
          expect(find.textContaining('Cliente Nuevo'), findsNothing);

          // Y al cancelar una devuelta, la lista y su contador se enteran sin volver a montar.
          await (base.update(
            base.orders,
          )..where((o) => o.id.equals('d'))).write(
            OrdersCompanion(
              resultado: const Value(ResultadoParada.cancelado),
              resultadoAt: Value(DateTime.utc(2026, 11, 5, 14)),
            ),
          );
          await asentar(tester);
          expect(find.text('2 canceladas'), findsOneWidget);
          expect(find.text('Sin nota'), findsOneWidget);
        },
      );
    });
  }
}
