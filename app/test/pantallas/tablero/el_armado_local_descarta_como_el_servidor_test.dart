// EL ARMADO LOCAL DE UNA ZONA DESCARTA COMO EL SERVIDOR — 1.0.29.
//
// `RepositorioTablero.armarRuta` arma en la APK y en el escritorio, y lo que
// decide ahi tiene que ser lo mismo que decide `armarRutaDeColumna`
// (`api/internal/api/tablero.go`) cuando el apunte suba: solo entra lo facturado
// (`igual` o `cambiado`, este desde el 15/10/2026), con domicilio cobrado y, si
// el vendedor lo marco, cotizado (`nucleo/regla_de_entrada.dart`). Hasta
// 1.0.28 el aparato solo miraba las marcas graves, asi que subia al camion lo que
// el servidor descartaba despues, con el camion ya cargado: ningun rechazo local,
// y el aviso llegaba horas mas tarde, con un nombre equivocado.
//
// Los dos literales de domicilio NO estan escritos aqui: se leen de
// `docs/armado-rechazado.casos.json` (§3-bis), el fichero que tambien lee la
// prueba del servidor. Si alguien cambia el texto de un lado, esto se pone rojo.
//
// Todas van EN PAREJA: sube lo bueno / se cae lo malo, y NO se cae nadie cuando
// todo es bueno. La base nace vacia y se siembra dentro del cuerpo.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

void main() {
  late BaseLocal base;
  late ConsultasTablero consultas;
  late ColaDeSalida cola;
  late RepositorioTablero repo;
  late AlmacenOrigen origen;
  late String centro;

  setUp(() async {
    base = baseDePrueba();
    consultas = ConsultasTablero(base);
    cola = ColaDeSalida(base);
    repo = RepositorioTablero(base, cola);
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    origen = await consultas.almacenDe(sucursalStg);
  });

  tearDown(() => base.close());

  /// Una zona con su camion previsto, sembrado AHORA (con la base vacia hasta
  /// este punto).
  Future<String> unaZona() async {
    await sembrarCamion(base, id: 'v1', capacidad: 5000);
    centro = await repo.crearColumna(
      sucursalId: sucursalStg,
      nombre: 'Centro',
      vehiculoId: 'v1',
    );
    return centro;
  }

  /// Pone un pedido en la zona. Se coloca BUENO —`colocar` rechaza un domicilio
  /// sin cobrar o sin cotizar— y despues se estropea, que es como ocurre de
  /// verdad: la bajada trae la factura cambiada con la tarjeta ya puesta.
  Future<void> ponerEnLaZona(
    String id, {
    double aGrados = 0.01,
    String? facturaEstado = EstadoFactura.igual,
    double? domicilio = 5,
    double? costo = 5,
    bool? marcado = true,
  }) async {
    await sembrarPedido(base, id: id, aGrados: aGrados, cliente: 'Cliente $id');
    await repo.colocar(pedidoId: id, columnaId: centro);
    await (base.update(base.orders)..where((o) => o.id.equals(id))).write(
      OrdersCompanion(
        facturaEstado: Value(facturaEstado),
        facturaDomicilio: Value(domicilio),
        pedidoCosto: Value(costo),
        requiereDomicilio: Value(marcado),
      ),
    );
  }

  Future<Map<String, Pedido>> pedidos() async => {
    for (final p in await base.select(base.orders).get()) p.id: p,
  };

  group('una zona de cuatro: sube la buena y se NOMBRAN las otras tres', () {
    // TEMPORAL 16/10/2026 (Jose): sin cobrar y sin cotizar SUBEN; sólo se queda fuera la que no
    // tiene factura (la regla es `nucleo/regla_de_entrada.dart`).
    test('sin factura se queda fuera; sin cobrar y sin cotizar suben', () async {
      await unaZona();
      await ponerEnLaZona('buena', aGrados: 0.01);
      await ponerEnLaZona(
        'sin-factura',
        aGrados: 0.02,
        facturaEstado: EstadoFactura.sinFactura,
      );
      await ponerEnLaZona('sin-cobrar', aGrados: 0.03, domicilio: null);
      await ponerEnLaZona('sin-cotizar', aGrados: 0.04, costo: null);
      await ponerEnLaZona('cero', aGrados: 0.05, domicilio: 0.0);

      List<String>? fuera;
      final rutaId = await repo.armarRuta(
        columnaId: centro,
        sucursalId: sucursalStg,
        alDejarFuera: (f) => fuera = f,
      );

      final porId = await pedidos();
      for (final id in ['buena', 'sin-cobrar', 'sin-cotizar', 'cero']) {
        expect(porId[id]!.routeId, rutaId, reason: '$id sube: está facturada');
      }
      expect(porId['sin-factura']!.routeId, isNull);

      // NOMBRADA, con el numero de operacion (el «conduce» de Amado) y el motivo
      // del servidor, letra por letra.
      expect(fuera, [
        'sin-factura · Cliente sin-factura: ${MarcaTarjeta.sinFactura.texto}',
      ]);

      // Lo que se cae se QUEDA puesto, no desaparece el trabajo de nadie.
      final quedan = await consultas.colocados(sucursalStg, origen);
      expect(quedan.map((t) => t.pedido.pedidoId).toList(), ['sin-factura']);

      // Y lo que SUBE al servidor es exactamente lo que subio al camion.
      final ultimo = (await cola.lote()).last;
      final cuerpo = jsonDecode(ultimo.cuerpo) as Map<String, Object?>;
      expect(
        cuerpo['pedidoIds'],
        unorderedEquals(['buena', 'sin-cobrar', 'sin-cotizar', 'cero']),
      );
    });

    // LOS DOS CASOS REALES (PBF26-2610131268, issue 10; PCC25-261014-1435, Amado
    // 16/10/2026: MARCADO, sin cotizar y 0.05 cobrado) suben al camion.
    test('los casos reales suben', () async {
      await unaZona();
      await ponerEnLaZona(
        'real',
        aGrados: 0.01,
        facturaEstado: EstadoFactura.cambiado,
        domicilio: 1.31,
        costo: null,
        marcado: false,
      );
      await ponerEnLaZona('marcada', aGrados: 0.02, domicilio: 0.05, costo: null);

      List<String>? fuera;
      final rutaId = await repo.armarRuta(
        columnaId: centro,
        sucursalId: sucursalStg,
        alDejarFuera: (f) => fuera = f,
      );

      final porId = await pedidos();
      expect(porId['real']!.routeId, rutaId);
      expect(porId['marcada']!.routeId, rutaId);
      expect(fuera, isNull);
    });
  });

  test('ninguna cumple: rechazo total con el literal del servidor, y NO se arma nada', () async {
    await unaZona();
    await ponerEnLaZona(
      'sin-factura',
      aGrados: 0.02,
      facturaEstado: EstadoFactura.sinFactura,
    );
    await ponerEnLaZona(
      'sin-cotejar',
      aGrados: 0.03,
      facturaEstado: null,
    );
    final apuntesAntes = (await cola.lote()).length;

    var avisado = false;
    await expectLater(
      repo.armarRuta(
        columnaId: centro,
        sucursalId: sucursalStg,
        alDejarFuera: (_) => avisado = true,
      ),
      throwsA(
        isA<RechazoDelTablero>()
            .having(
              (e) => e.mensaje,
              'mensaje',
              'La columna no tiene ningún pedido que se pueda repartir hoy',
            )
            .having(
              (e) => e.detalles,
              'detalles',
              unorderedEquals([
                'sin-factura · Cliente sin-factura: ${MarcaTarjeta.sinFactura.texto}',
                'sin-cotejar · Cliente sin-cotejar: ${MarcaTarjeta.sinCotejar.texto}',
              ]),
            ),
      ),
    );

    expect(avisado, isFalse, reason: 'un rechazo no es un «sí con avisos»');
    expect(await base.select(base.routes).get(), isEmpty);
    expect((await consultas.colocados(sucursalStg, origen)).length, 2);
    expect(
      (await cola.lote()).length,
      apuntesAntes,
      reason: 'si el apunte se encola, el «no» llega horas despues a la bandeja',
    );
  });

  test('todas cumplen: sube entera y no sale ni un aviso', () async {
    await unaZona();
    await ponerEnLaZona('a', aGrados: 0.01);
    await ponerEnLaZona('b', aGrados: 0.02);
    await ponerEnLaZona('c', aGrados: 0.03);

    var avisado = false;
    final rutaId = await repo.armarRuta(
      columnaId: centro,
      sucursalId: sucursalStg,
      alDejarFuera: (_) => avisado = true,
    );

    expect(avisado, isFalse, reason: 'un aviso que sale siempre no se lee');
    final porId = await pedidos();
    for (final id in ['a', 'b', 'c']) {
      expect(porId[id]!.routeId, rutaId);
    }
    expect(await consultas.colocados(sucursalStg, origen), isEmpty);
  });

  // ---------------------------------------------------------------------------
  // LA WEB: el servidor contesta, pero lo que el aparato ya nombro NO se repite
  // con la voz del servidor.
  // ---------------------------------------------------------------------------
  //
  // Como el aparato no manda lo descartado en `pedidoIds`, el servidor lo llama
  // «lo pusieron en la zona después de que armaras», y no es verdad: estaba ahi,
  // y no cumple. Con el motivo bueno ya dicho por el aparato, esa linea sobra y
  // confunde.
  test('en la web cada descartado sale UNA vez, con su motivo de verdad', () async {
    final servidor = ServidorFalso((_) async => RespuestaFalsa(201, <String, Object?>{
          'id': 'r-de-verdad',
          'descartados': [
            {
              'pedidoId': 'sin-factura',
              'operationNumber': 'sin-factura',
              'customerName': 'Cliente sin-factura',
              'motivo': 'lo pusieron en la zona después de que armaras',
            },
            {
              // Uno que el aparato NO conocia: este si se dice, con la voz del servidor.
              'pedidoId': 'otro',
              'operationNumber': 'otro',
              'customerName': 'Cliente otro',
              'motivo': 'ya va en otra ruta',
            },
          ],
        }));
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
      ..httpClientAdapter = servidor;
    final enLaWeb = RepositorioTablero(
      base,
      cola,
      enVivo: EscrituraEnVivo(ClienteApi(dio: dio, esperas: const <Duration>[])),
    );
    await unaZona();
    await ponerEnLaZona('buena', aGrados: 0.01);
    await ponerEnLaZona(
      'sin-factura',
      aGrados: 0.02,
      facturaEstado: EstadoFactura.sinFactura,
    );

    List<String>? fuera;
    await enLaWeb.armarRuta(
      columnaId: centro,
      sucursalId: sucursalStg,
      alDejarFuera: (f) => fuera = f,
    );

    expect(fuera, [
      'sin-factura · Cliente sin-factura: ${MarcaTarjeta.sinFactura.texto}',
      'otro · Cliente otro: ya va en otra ruta',
    ]);
    // Y al servidor solo va lo que sube al camion.
    expect(servidor.vistas.single.cuerpo, containsPair('pedidoIds', ['buena']));
  });

  // ---------------------------------------------------------------------------
  // P4 — REASIGNAR UN DEVUELTO ES UN INTENTO NUEVO (hallazgo I-2)
  // ---------------------------------------------------------------------------
  group('reasignar un devuelto', () {
    test('al armar, el resultado de la vuelta anterior se borra', () async {
      await unaZona();
      await ponerEnLaZona('devuelto', aGrados: 0.01);
      await (base.update(base.orders)..where((o) => o.id.equals('devuelto')))
          .write(
        OrdersCompanion(
          resultado: const Value(ResultadoParada.devuelto),
          resultadoAt: Value(DateTime(2026, 10, 6, 15)),
          resultadoNota: const Value('Nadie en casa'),
        ),
      );

      // El devuelto sigue siendo repartible (el servidor lo deja volver a una
      // ruta); un entregado, y cualquiera con `deliveredAt`, NO (ver la pareja).
      // Por eso `deliveredAt` no se siembra aqui: no hay devuelto con fecha de
      // entrega, y el `null` que se le pone al armar es de cinturon.
      await repo.armarRuta(
        columnaId: centro,
        sucursalId: sucursalStg,
      );

      final p = (await pedidos())['devuelto']!;
      expect(p.routeId, isNotNull);
      expect(p.resultado, isNull, reason: 'es un intento nuevo');
      expect(p.resultadoAt, isNull);
      expect(p.resultadoNota, isNull, reason: 'la nota era de la vuelta anterior');
    });

    test('en pareja: un pedido sin resultado entra igual, y uno ENTREGADO no entra', () async {
      await unaZona();
      await ponerEnLaZona('limpio', aGrados: 0.01);
      await ponerEnLaZona('entregado', aGrados: 0.02);
      await (base.update(base.orders)..where((o) => o.id.equals('entregado')))
          .write(
        OrdersCompanion(
          resultado: const Value(ResultadoParada.entregado),
          resultadoAt: Value(DateTime(2026, 10, 6, 15)),
          deliveredAt: Value(DateTime(2026, 10, 6, 15)),
        ),
      );

      List<String>? fuera;
      await repo.armarRuta(
        columnaId: centro,
        sucursalId: sucursalStg,
        alDejarFuera: (f) => fuera = f,
      );

      final porId = await pedidos();
      expect(porId['limpio']!.routeId, isNotNull);
      // Borrarle el resultado a una entrega de verdad la repartiria dos veces.
      expect(porId['entregado']!.routeId, isNull);
      expect(porId['entregado']!.resultado, ResultadoParada.entregado);
      expect(porId['entregado']!.deliveredAt, isNotNull);
      expect(fuera, ['entregado · Cliente entregado: ya se entregó']);
    });
  });
}
