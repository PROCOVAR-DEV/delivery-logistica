// LA FACTURA Y LOS EMPAQUES EN EL TABLERO — Amado, issues 6 y 8, 14/10/2026.
//
//  · Issue 6, punto 1: «en el tablero, el detalle del pedido debe incluir la fecha de
//    facturación y el número de factura, y se están mostrando las cantidades en
//    unidades, que puede ser interesante, pero más importante es en blíster, que es
//    como cargan y transportan».
//  · Issue 8: «los logísticos operan con número de factura, debe ser una información
//    importante a mostrar en los CARDS de pedidos».
//
// ## Qué es «el número de factura»
//
// `facturaNumero` (el `operNumber` de Ventra, `1024237`), NO el folio del pedido
// (`PTB25-261005-1479`, el «conduce»), que ya era el título de cada tarjeta. Los dos se
// siembran DISTINTOS a propósito en todas las pruebas: con el mismo valor en los dos,
// pintar uno por otro saldría en verde. El porqué entero, en `numeroDeFactura`
// (`pedidos/datos/formato.dart`).
//
// ## Cómo van las pruebas
//
// El cajón de mover se abre por la pantalla entera y con el dedo, como las de
// `el_cajon_de_mover_y_el_no_del_camion_test.dart`: una prueba que llamara a
// `AccionesTablero.moverTarjeta` a pelo saldría verde mientras la pantalla no abre nada.
// Y van EN PAREJA: sale con número / no sale sin él, unidades de fiar / unidades que no
// lo son. Los literales están escritos a mano, sin importarlos del código: una prueba
// que lee la frase del propio widget no caza que alguien la cambie.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart' show sucursalDeLaSesionProvider;
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';
import 'package:reparto/pantallas/tablero/vista/tarjeta.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

const _escritorio = Size(1400, 900);

void main() {
  late BaseLocal base;
  late ServidorFalso servidor;
  late ProviderContainer contenedor;

  // Aquí SÓLO se abre la base: sembrar en el `setUp` de un `testWidgets` es la segunda
  // trampa del §5 y cuelga la prueba en vez de fallarla.
  setUp(() {
    base = BaseLocal.con(NativeDatabase.memory());
    servidor = ServidorFalso((peticion) async => null);
  });

  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );

  Future<void> pasadasCortas(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Widget montar() {
    final dio = Dio()..httpClientAdapter = servidor;
    contenedor = ProviderContainer(
      overrides: [
        baseProvider.overrideWith((ref) => base),
        clienteApiProvider.overrideWithValue(
          ClienteApi(dio: dio, esperas: const <Duration>[]),
        ),
        almacenSesionProvider.overrideWithValue(
          AlmacenEnMemoria(
            const Sesion(
              token: 't',
              refresh: 'r',
              sub: 'logistico',
              sucursalId: sucursalStg,
            ),
          ),
        ),
        sucursalDeLaSesionProvider.overrideWithValue(sucursalStg),
      ],
    );
    addTearDown(contenedor.dispose);
    return UncontrolledProviderScope(
      container: contenedor,
      child: const MaterialApp(home: Scaffold(body: PantallaTablero())),
    );
  }

  Future<void> abrirElTablero(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(_escritorio);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await RepositorioTablero(
      base,
      ColaDeSalida(base),
    ).crearColumna(sucursalId: sucursalStg, nombre: 'Centro');

    await tester.pumpWidget(montar());
    await asentar(tester);
  }

  /// Siembra un pedido de «Bodega La Esquina» con su factura y UN renglón, y abre el
  /// cajón de moverlo. El folio y el número de factura son distintos a propósito.
  Future<void> abrirElCajonDe(
    WidgetTester tester, {
    String? facturaNumero = '1024237',
    DateTime? facturaAt,
    double cantidad = 120,
    double? empaques = 20,
    String descripcion = 'MALTA GUAJIRA 330 ML BLISTER 6U',
  }) async {
    await abrirElTablero(tester);
    await sembrarPedido(
      base,
      id: 'p1',
      cliente: 'Bodega La Esquina',
      direccion: 'Calle 4 esquina a 7',
      operacion: 'PTB25-261005-1479',
      facturaNumero: facturaNumero,
      facturaAt: facturaAt ?? DateTime(2026, 10, 12, 9, 30),
    );
    await sembrarRenglon(
      base,
      id: 'i1',
      pedidoId: 'p1',
      descripcion: descripcion,
      cantidad: cantidad,
      empaques: empaques,
    );
    await pasadasCortas(tester);

    await tester.tap(find.text('Bodega La Esquina'));
    await pasadasCortas(tester);
  }

  // ---------------------------------------------------------------------------
  // 1. EL DETALLE: LA FACTURA Y SU FECHA
  // ---------------------------------------------------------------------------

  group('el detalle del pedido, al moverlo', () {
    testWidgets('lleva el número de factura y la fecha en que se facturó', (
      tester,
    ) async {
      await abrirElCajonDe(tester);

      expect(
        find.text('Factura 1024237 · facturada el 12/10/2026'),
        findsOneWidget,
        reason:
            'el detalle no dice la factura ni cuándo se facturó: es lo que pidió '
            'Amado en el punto 1 del issue 6',
      );
      // El folio sigue siendo el título del cajón y NO es la factura: son dos números.
      expect(find.textContaining('Factura PTB25'), findsNothing);
      expect(
        find.text('PTB25-261005-1479'),
        findsWidgets,
        reason: 'el folio (el conduce) tiene que seguir donde estaba',
      );

      await desmontar(tester);
    });

    testWidgets('sin número de factura se DICE, y no inventa fecha ni número', (
      tester,
    ) async {
      await abrirElCajonDe(tester, facturaNumero: null);

      expect(
        find.text('Sin número de factura'),
        findsOneWidget,
        reason: 'un pedido sin número tiene que decirlo, no dejar un hueco',
      );
      // La fecha del cotejo existe (`facturaAt` está sembrada) y aun así NO sale
      // como «facturada el»: sin factura no hay fecha de facturación.
      expect(find.textContaining('facturada el'), findsNothing);
      expect(find.textContaining('Factura 1024237'), findsNothing);

      await desmontar(tester);
    });

    testWidgets('el número limpio de la comilla de Excel', (tester) async {
      // `a_mano/comilla_de_excel.sql` lista `factura_numero`: lo que bajó antes del
      // arreglo del servidor puede traer `'1024237` en la base de este aparato.
      await abrirElCajonDe(tester, facturaNumero: "'1024237");

      expect(
        find.text('Factura 1024237 · facturada el 12/10/2026'),
        findsOneWidget,
      );
      expect(find.textContaining("'1024237"), findsNothing);

      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. EL DETALLE: LAS CANTIDADES, EN EMPAQUES PRIMERO
  // ---------------------------------------------------------------------------

  group('las cantidades del detalle', () {
    testWidgets('van en EMPAQUES primero y las unidades detrás', (
      tester,
    ) async {
      await abrirElCajonDe(tester, cantidad: 120, empaques: 20);

      expect(
        find.text('MALTA GUAJIRA 330 ML BLISTER 6U · 20 empaques · 120 uds'),
        findsOneWidget,
        reason:
            'las cantidades tienen que salir en empaques (blíster) antes que en '
            'unidades: es como se carga y se transporta',
      );

      await desmontar(tester);
    });

    testWidgets('un solo empaque va en singular', (tester) async {
      await abrirElCajonDe(tester, cantidad: 6, empaques: 1);

      expect(
        find.text('MALTA GUAJIRA 330 ML BLISTER 6U · 1 empaque · 6 uds'),
        findsOneWidget,
      );

      await desmontar(tester);
    });

    testWidgets('si `quantity` no llega a los empaques NO son unidades y no se '
        'enseñan', (tester) async {
      // «SERVILLETA PROSITO PACA 24P · 7 empaques · 4 unidades» (22/09/2026): 437 de
      // las 7.738 líneas de producción vienen así. El `4` no son unidades de nada, y
      // enseñarlo como tales es un número creíble y equivocado.
      await abrirElCajonDe(
        tester,
        descripcion: 'SERVILLETA PROSITO PACA 24P',
        cantidad: 4,
        empaques: 7,
      );

      expect(
        find.text('SERVILLETA PROSITO PACA 24P · 7 empaques'),
        findsOneWidget,
      );
      expect(find.textContaining('uds'), findsNothing);

      await desmontar(tester);
    });

    testWidgets('sin empaques la línea cuenta `quantity` como empaques y no '
        'saca unidades', (tester) async {
      await abrirElCajonDe(tester, cantidad: 5, empaques: null);

      expect(
        find.text('MALTA GUAJIRA 330 ML BLISTER 6U · 5 empaques'),
        findsOneWidget,
      );
      expect(find.textContaining('uds'), findsNothing);

      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // 3. LA TARJETA: EL NÚMERO DE FACTURA A LA VISTA, SIN ROMPER EL ANCHO
  // ---------------------------------------------------------------------------

  group('la tarjeta del tablero', () {
    TarjetaPedido pedido({String? facturaNumero = '1024237'}) => TarjetaPedido(
      pedidoId: 'p-1',
      customerName: 'Bodega La Esquina',
      address: 'Calle 4 esquina a 7, Reparto Sueño, Santiago de Cuba',
      weight: 128.5,
      kmAlAlmacen: 3.2,
      mismoCliente: 0,
      operationNumber: 'PTB25-261005-1479',
      facturaEstado: 'igual',
      facturaNumero: facturaNumero,
    );

    Future<void> pintar(
      WidgetTester tester, {
      required double ancho,
      required TarjetaPedido tarjeta,
    }) async {
      tester.view.physicalSize = Size(ancho + 40, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tasaDeLaMiradaProvider.overrideWithValue(
              const TasaDeLaMirada.no('en estas pruebas no hay tasa'),
            ),
          ],
          child: MaterialApp(
            theme: temaDeReparto(),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: ancho,
                  child: TarjetaDePedido(pedido: tarjeta),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final ancho in const [390.0, 280.0, 180.0]) {
      testWidgets('a $ancho px el número de factura se ve y la tarjeta no '
          'desborda', (tester) async {
        await pintar(tester, ancho: ancho, tarjeta: pedido());

        final linea = find.byKey(const ValueKey('tarjeta-factura'));
        expect(linea, findsOneWidget);
        expect(
          tester.widget<Text>(linea).data,
          'Factura 1024237',
          reason: 'la tarjeta tiene que decir la factura con su rótulo',
        );
        final tarjeta = tester.getRect(find.byType(TarjetaDePedido));
        final texto = tester.getRect(linea);
        expect(texto.left, greaterThanOrEqualTo(tarjeta.left));
        expect(texto.right, lessThanOrEqualTo(tarjeta.right));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('un número LARGO (dos facturas) se corta con elipsis, no '
        'desborda', (tester) async {
      await pintar(
        tester,
        ancho: 180,
        tarjeta: pedido(facturaNumero: '1024237, 1024240, 1024251, 1024299'),
      );

      final linea = find.byKey(const ValueKey('tarjeta-factura'));
      expect(linea, findsOneWidget);
      expect(
        tester.getRect(linea).right,
        lessThanOrEqualTo(tester.getRect(find.byType(TarjetaDePedido)).right),
      );
      expect(tester.takeException(), isNull);
    });

    for (final vacio in const <String?>[null, '', '   ']) {
      testWidgets(
        'sin número de factura (${vacio == null ? 'nulo' : "'$vacio'"}) '
        'no sale la línea',
        (tester) async {
          await pintar(
            tester,
            ancho: 280,
            tarjeta: pedido(facturaNumero: vacio),
          );

          expect(
            find.byKey(const ValueKey('tarjeta-factura')),
            findsNothing,
            reason: 'sin factura no se pinta un «Factura» vacío',
          );
          expect(find.text('Factura'), findsNothing);
        },
      );
    }
  });
}
