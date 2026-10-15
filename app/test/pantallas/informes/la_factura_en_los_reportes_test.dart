// LA COLUMNA DE FACTURAS EN LOS REPORTES — issue 9 de Amado.
//
// «Adicionar la factura como elemento de referencia importante: adicionar a los
// reportes la columna de facturas».
//
// Esto lo mira DE PUNTA A PUNTA, con la base local de por medio (la de la APK y
// el escritorio; la web arma el informe con la misma consulta sobre su base en
// memoria, así que da lo mismo):
//
//  1. la consulta saca el número de la base (`informe` → `FilaDeInforme.factura`
//     y `FilaDeVehiculo.facturas`);
//  2. la PANTALLA lo pinta, a 1440 y a 390 px, sin partirlo ni desbordar;
//  3. el EXCEL que sale del botón lleva el mismo número que la pantalla, y la
//     lista ENTERA de cada camión;
//  4. y NADA de eso toca los totales: ni las órdenes, ni los ingresos, ni el pie.
//
// La regla del número (cuál de los dos, qué pasa si faltan) y su paridad con el
// servidor viven en `el_numero_de_factura_test.dart`, contra el fichero de casos
// que también lee Go.
//
// Todas las pruebas de pantalla siembran DENTRO del cuerpo y no en el `setUp`
// (CLAUDE.md §5: lo que Drift deja empezado fuera del reloj falso no avanza).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/diseno/pestanas.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/informes/datos/consultas_informes.dart';
import 'package:reparto/pantallas/informes/datos/entrega_del_excel.dart';
import 'package:reparto/pantallas/informes/datos/excel_del_informe.dart';
import 'package:reparto/pantallas/informes/registro.dart';
import 'package:reparto/pantallas/informes/vista/boton_exportar.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo/leer_xlsx.dart';

/// La costura con el aparato: se queda con el fichero para poder abrirlo.
class _EntregaGuardada implements EntregaDeFichero {
  Uint8List? bytes;

  @override
  Future<Entregado> entregar({
    required Uint8List bytes,
    required String nombre,
    required String tipoMime,
  }) async {
    this.bytes = bytes;
    return Entregado.hecho('Excel guardado en /descargas/$nombre');
  }
}

/// El MISMO fichero que lee `api/internal/api/numero_de_factura_casos_compartidos_test.go`
/// (y la prueba de Postgres de verdad): el informe de cinco pedidos de un camión
/// que se siembra aquí en la base local, allí en el doble del servidor y allí en
/// Postgres, y que tiene que dar lo mismo en los tres.
const _rutaDeLosCasos = '../docs/numero-de-factura.casos.json';

Map<String, dynamic> _informeDelFichero() =>
    (jsonDecode(File(_rutaDeLosCasos).readAsStringSync())
            as Map<String, dynamic>)['informe']
        as Map<String, dynamic>;

// Los números de la siembra (son los del fichero de arriba): «factura» es el
// número de Ventra (`factura_numero`), nunca el folio (decisión del 14/10/2026).
const _f1 = '1024237'; // pedidos a y d
const _f2 = '1024240'; // pedido b (venía con la comilla de Excel)
const _f3 = '1024251, 1024299'; // pedido e: dos facturas
const _porVehiculoPantalla = '$_f1, $_f2 y 2 más · 2 sin número';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  final ahora = DateTime(2026, 9, 14, 10, 36);

  late BaseLocal base;
  late _EntregaGuardada entrega;
  setUp(() {
    base = baseDePrueba();
    entrega = _EntregaGuardada();
  });
  tearDown(() => base.close());

  Future<void> bajadaEntera() async {
    for (final coleccion in Colecciones.todas) {
      await base
          .into(base.frescura)
          .insert(
            FrescuraCompanion.insert(
              coleccion: coleccion,
              bajadaAt: Value(ahora),
              hasta: Value(ahora.toIso8601String()),
            ),
          );
    }
  }

  /// Un camión con una ruta, y los cinco pedidos de esa ruta que trae el fichero
  /// compartido, del más nuevo al más viejo:
  ///
  ///  * `a`  — factura `_f1`;
  ///  * `b`  — factura `_f2`, que llegó con la comilla de Excel;
  ///  * `c`  — sin factura (su folio NO se enseña como factura);
  ///  * `d`  — la MISMA factura que `a` (no se repite en la lista del camión);
  ///  * `e`  — dos facturas (`_f3`);
  ///  * `f`  — factura sólo con blancos raros: cuenta como sin número.
  ///
  /// Los importes y lo esperado salen del fichero compartido.
  Future<void> sembrar() async {
    final informe = _informeDelFichero();
    await base
        .into(base.vehicles)
        .insert(
          VehiclesCompanion.insert(id: 'v1', name: informe['camion'] as String),
        );
    await base
        .into(base.routes)
        .insert(
          RoutesCompanion.insert(
            id: 'r1',
            routeCode: const Value('R-001'),
            vehicleId: const Value('v1'),
          ),
        );
    final pedidos = (informe['pedidos'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    for (var i = 0; i < pedidos.length; i++) {
      final p = pedidos[i];
      final cliente = p['cliente'] as String;
      await base
          .into(base.orders)
          .insert(
            OrdersCompanion.insert(
              id: cliente.split(' ').last,
              customerName: cliente,
              address: 'Calle $cliente',
              routeId: const Value('r1'),
              price: Value((p['ingreso'] as num).toDouble()),
              operationNumber: Value(p['operationNumber'] as String?),
              facturaNumero: Value(p['facturaNumero'] as String?),
              // El primero del fichero es el más nuevo.
              createdAt: Value(DateTime(2026, 9, 13, 12 - i)),
            ),
          );
    }
  }

  Future<void> montar(WidgetTester tester, {required Size tamano}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
          entregaDeFicheroProvider.overrideWithValue(entrega),
        ],
        child: RepartoApp(
          enrutador: crearEnrutador(
            pantallas: [registrarInformes()],
            inicial: '/reports',
          ),
        ),
      ),
    );
    // LAS TIPOGRAFÍAS, ANTES DEL PRIMER FOTOGRAMA (mismo motivo que en
    // `exportar_test.dart`: `google_fonts` carga por `rootBundle`, que no avanza
    // dentro del reloj falso, y el primer fotograma se mide con una letra y se
    // pinta con otra).
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  /// QUE SE LEE ENTERO: lo que mide el texto escrito en una línea cabe en su
  /// celda con [holgura] píxeles de sobra.
  ///
  /// Las celdas de estas tablas son `Text` con `overflow: ellipsis`, y un número
  /// que no cabe NO se parte ni desborda: se corta con «…» y `find.text` lo sigue
  /// encontrando entero. Por eso `findsOneWidget` no basta, y por eso se mide. La
  /// holgura es para una letra más ancha que la de esta máquina (Android no pinta
  /// con la misma tipografía que las pruebas).
  void seLeEntero(WidgetTester tester, String texto, {double holgura = 40}) {
    final parrafo = tester.renderObject<RenderParagraph>(
      find.text(texto).first,
    );
    final natural = parrafo.getMaxIntrinsicWidth(double.infinity);
    final celda = tester.getSize(find.text(texto).first).width;
    expect(
      celda,
      greaterThanOrEqualTo(natural + holgura),
      reason:
          '«$texto» mide ${natural.toStringAsFixed(1)} px y su celda tiene '
          '${celda.toStringAsFixed(1)}: sin $holgura px de holgura se corta con '
          '«…» en cuanto la letra sea algo más ancha, y el aviso de «sin '
          'número» o el final de una factura se pierden sin que nada falle.',
    );
  }

  /// El Row (la fila de la tabla) que contiene [texto].
  Finder laFilaDe(String texto) =>
      find.ancestor(of: find.text(texto), matching: find.byType(Row)).first;

  // ---------------------------------------------------------------------------
  // 1. La consulta saca el número de la base
  // ---------------------------------------------------------------------------

  group('la consulta', () {
    test('saca el número de cada pedido y la lista de cada camión, como el '
        'fichero compartido con el servidor', () async {
      await sembrar();
      final informe = await ConsultasInformes(base)
          .mirar(const FiltroDeInforme())
          .first;
      final esperado = _informeDelFichero()['esperado'] as Map<String, dynamic>;

      expect(
        {for (final f in informe.filas) f.cliente: f.factura},
        esperado['porPedido'],
        reason:
            'El número de cada pedido no es el de $_rutaDeLosCasos, que es '
            'también el que tiene que dar GET /api/reports. Manda la operación, '
            'respalda la factura, y sin ninguno de los dos no hay número.',
      );

      final v = informe.porVehiculo.single;
      final camion = esperado['camion'] as Map<String, dynamic>;
      expect(v.facturas, camion['facturas']);
      expect(v.sinFactura, camion['sinFactura']);
    });

    // LA PAREJA, y es la que importa a Amado: ponerle la columna a los reportes
    // NO cambia ni una cifra. Sin esta, una "factura" que se cuele en la
    // agrupación (por ejemplo, agrupando por número) pasaría con los números
    // de la columna bien y las órdenes del camión mal.
    test('y no toca ni las órdenes, ni los ingresos, ni el peso', () async {
      await sembrar();
      final informe = await ConsultasInformes(base)
          .mirar(const FiltroDeInforme())
          .first;

      final camion =
          (_informeDelFichero()['esperado'] as Map<String, dynamic>)['camion']
              as Map<String, dynamic>;
      expect(informe.filas, hasLength(camion['ordenes']));
      expect(informe.resumen.totalOrdenes, camion['ordenes']);
      expect(informe.resumen.ingresos, camion['ingresos']);
      final v = informe.porVehiculo.single;
      expect(
        v.ordenes,
        camion['ordenes'],
        reason:
            'Dos pedidos con el MISMO número de factura siguen siendo dos '
            'órdenes: la lista de facturas es sólo una lista de referencias.',
      );
      expect(v.ingresos, camion['ingresos']);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. La pantalla
  // ---------------------------------------------------------------------------

  group('en la pantalla, a 1440 px', () {
    testWidgets('«Detalle de Órdenes» lleva la columna Factura', (
      tester,
    ) async {
      await bajadaEntera();
      await sembrar();
      await montar(tester, tamano: const Size(1440, 1200));

      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Detalle de Órdenes'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Factura'), findsOneWidget);
      // Los dos pedidos con el mismo número lo enseñan los dos: en el detalle
      // es UN número por orden, que es para lo que sirve de referencia.
      expect(find.text(_f1), findsNWidgets(2));
      expect(find.text(_f2), findsOneWidget);
      expect(find.text(_f3), findsOneWidget);
      // Y el que no tiene ninguno lo dice con la raya, no en blanco.
      expect(
        find.descendant(of: laFilaDe('Cliente c'), matching: find.text('—')),
        findsOneWidget,
        reason:
            'El pedido sin número de factura salió con la celda en blanco: '
            'tiene que decir «—» como las otras columnas que faltan.',
      );
      // El número es para copiarlo: se lee ENTERO, no cortado con «…».
      seLeEntero(tester, _f1);
      // Los totales, intactos: 6 órdenes que suman 84, y el pie sigue siendo el
      // pie.
      expect(find.text('Totales:'), findsOneWidget);
      expect(find.text('84,00 USD'), findsOneWidget);
      // Y cada total bajo SU columna: la de las facturas es una celda más en
      // cada fila, y el pie que se queda una celda corta corre el total del
      // Precio un hueco a la izquierda sin que ninguna cifra cambie.
      expect(
        tester.getTopLeft(find.text('84,00 USD')).dx,
        tester.getTopLeft(find.text('Precio')).dx,
        reason: 'El total del pie ya no cae bajo la columna «Precio».',
      );
      expect(
        tester.getTopLeft(find.text(_f2)).dx,
        tester.getTopLeft(find.text('Factura')).dx,
        reason: 'Los números de factura no caen bajo la cabecera «Factura».',
      );
      expect(tester.takeException(), isNull);

      await desmontar(tester);
    });

    testWidgets('«Por Vehículo» lleva sus facturas, y cuántas quedan fuera', (
      tester,
    ) async {
      await bajadaEntera();
      await sembrar();
      await montar(tester, tamano: const Size(1440, 1200));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Por Vehículo'));
      await tester.pumpAndSettle();

      expect(find.text('Facturas'), findsOneWidget);
      expect(
        find.text(_porVehiculoPantalla),
        findsOneWidget,
        reason:
            'La celda del camión tiene que decir sus dos primeras facturas, '
            'cuántas quedan fuera y cuántos pedidos no tienen número. El mismo '
            'número de `a` y `d` cuenta UNA vez.',
      );
      seLeEntero(tester, _porVehiculoPantalla);
      // Las órdenes y el total del camión, como siempre.
      expect(find.text('Ford 600'), findsOneWidget);
      expect(find.text('84,00 USD'), findsWidgets);
      expect(
        tester.getTopLeft(find.text(_porVehiculoPantalla)).dx,
        tester.getTopLeft(find.text('Facturas')).dx,
        reason: 'La lista del camión no cae bajo la cabecera «Facturas».',
      );
      expect(tester.takeException(), isNull);

      await desmontar(tester);
    });
  });

  group('en la pantalla, a 390 px', () {
    testWidgets('las dos tablas pintan las facturas sin desbordar', (
      tester,
    ) async {
      await bajadaEntera();
      await sembrar();
      await montar(tester, tamano: const Size(390, 844));

      // Por Vehículo (la 2.ª), y luego Detalle (la 3.ª): en un teléfono las
      // pestañas son un carrusel con flechas.
      await tester.tap(find.byKey(ClavesDePestanas.adelante));
      await tester.pumpAndSettle();
      expect(find.text('Facturas'), findsOneWidget);
      expect(find.text(_porVehiculoPantalla), findsOneWidget);
      seLeEntero(tester, _porVehiculoPantalla);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(ClavesDePestanas.adelante));
      await tester.pumpAndSettle();
      expect(find.text('Factura'), findsOneWidget);
      expect(find.text(_f1), findsNWidgets(2));
      // La tabla es ancha y se desplaza de lado; el número tiene que caber en
      // su columna, que se mide aunque la parte visible sea de 390 px.
      seLeEntero(tester, _f1);
      // `RenderFlex overflowed` y compañía llegan aquí como excepción.
      expect(tester.takeException(), isNull);

      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Lo exportado
  // ---------------------------------------------------------------------------

  group('en el Excel', () {
    testWidgets('lleva el MISMO número que la pantalla, y la lista entera', (
      tester,
    ) async {
      await bajadaEntera();
      await sembrar();
      await montar(tester, tamano: const Size(1440, 1200));

      await tester.tap(find.widgetWithText(FilledButton, 'Exportar a Excel'));
      await tester.pumpAndSettle();
      expect(entrega.bytes, isNotNull, reason: 'no salió ningún fichero');
      final libro = leerXlsx(entrega.bytes!);

      // Detalle: la columna Factura, fila por fila.
      final detalle = libro['Detalle de Órdenes']!;
      final columna = detalle.first.indexOf('Factura');
      expect(columna, isNonNegative, reason: 'la hoja no trae «Factura»');
      final clientes = detalle.first.indexOf('Cliente');
      expect(
        {
          for (final fila in detalle.skip(1).take(6))
            fila[clientes]: fila[columna],
        },
        {
          'Cliente a': _f1,
          'Cliente b': _f2,
          'Cliente c': '—',
          'Cliente d': _f1,
          'Cliente e': _f3,
          'Cliente f': '—',
        },
      );
      // El pie sigue en su sitio y con su total.
      expect(detalle.last.first, 'Totales:');
      expect(detalle.last.last, 84);

      // Por Vehículo: la lista ENTERA, sin el «y 1 más» de la pantalla.
      final porVehiculo = libro['Por Vehículo']!;
      final facturas = porVehiculo.first.indexOf('Facturas');
      expect(facturas, isNonNegative);
      expect(
        porVehiculo[1][facturas],
        '1024237, 1024240, 1024251, 1024299 · 2 sin número',
      );
      expect(porVehiculo[1][2], 6, reason: 'las órdenes del camión cambiaron');

      await desmontar(tester);
    });

    // EL TECHO DE UNA CELDA, DE PUNTA A PUNTA. Excel no abre un fichero con una
    // celda de más de 32.767 letras. Un camión con 3.000 facturas (un rango
    // grande sin filtrar) las pasa de largo: tiene que salir una lista CORTADA
    // QUE LO DICE, no un fichero que no abre. La pareja de abajo: con pocas, la
    // lista va entera.
    test('la lista de un camión con miles de facturas cabe en su celda', () {
      List<FilaDeInforme> filas(int cuantas) => [
        for (var i = 0; i < cuantas; i++)
          FilaDeInforme(
            id: 'o$i',
            cliente: 'Cliente $i',
            destino: 'Calle',
            pesoKg: 1,
            importe: 1,
            vehiculoId: 'v1',
            vehiculo: 'Ford 600',
            factura: 'PTB25-261005-${1000 + i}',
          ),
      ];
      String celdaDeFacturas(int cuantas) {
        final f = filas(cuantas);
        final libro = leerXlsx(
          ExcelDelInforme.armar(
            informe: Informe(
              filas: f,
              resumen: ConsultasInformes.resumir(f),
              porVehiculo: ConsultasInformes.agruparPorVehiculo(f),
            ),
            filtro: const FiltroDeInforme(),
            conversion: ConversionDelInforme.usd,
            generado: ahora,
          ),
        );
        return libro['Por Vehículo']![1].last! as String;
      }

      final enorme = celdaDeFacturas(3000);
      expect(
        enorme.length,
        lessThan(32767),
        reason:
            'La celda «Facturas» pasa de 32.767 letras: Excel no abre el '
            'fichero («contenido ilegible») y quien lo pidió se queda sin '
            'reporte.',
      );
      expect(enorme, matches(RegExp(r' y \d+ más$')));

      expect(
        celdaDeFacturas(3),
        'PTB25-261005-1000, PTB25-261005-1001, PTB25-261005-1002',
        reason: 'Con pocas facturas la lista tiene que ir entera, sin cortar.',
      );
    });

    // La pareja: con un reporte vacío no hay botón que pulsar (no se exporta
    // una hoja de cabeceras), y la columna no inventa números.
    testWidgets('sin ningún pedido el botón sigue apagado', (tester) async {
      await bajadaEntera();
      await montar(tester, tamano: const Size(1440, 1200));

      final boton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, TextosDeExportar.etiqueta),
      );
      expect(boton.onPressed, isNull);

      await desmontar(tester);
    });
  });
}
