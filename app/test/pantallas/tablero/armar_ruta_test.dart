import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/rutas/datos/geo.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo.dart';

/// §5: de una columna sale una ruta, tambien sin conexion.
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
    await sembrarCamion(base, id: 'v1', capacidad: 2000);
    origen = await consultas.almacenDe(sucursalStg);
    centro = await repo.crearColumna(
      sucursalId: sucursalStg,
      nombre: 'Centro',
      vehiculoId: 'v1',
    );
  });

  tearDown(() => base.close());

  test('respeta el orden que puso el logístico y no llama a nadie', () async {
    for (var i = 1; i <= 3; i++) {
      await sembrarPedido(base, id: 'p$i', peso: 100.0 * i);
      await repo.colocar(pedidoId: 'p$i', columnaId: centro);
    }
    // El de en medio pasa a ser el primero: él conoce las calles.
    await repo.colocar(pedidoId: 'p3', columnaId: centro, posicion: 1);

    final rutaId = await repo.armarRuta(
      columnaId: centro,
      origen: origen,
      sucursalId: sucursalStg,
    );

    expect(rutaId, startsWith('local-'));
    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals(rutaId))).getSingle();
    expect(ruta.name, 'Centro');
    expect(ruta.vehicleId, 'v1');
    expect(ruta.totalWeight, 600);
    expect(ruta.originLat, origen.lat);
    // El orden del logistico gana al greedy por defecto: la ruta nace sin
    // optimizar, y eso tiene que quedar dicho.
    expect(ruta.optimized, isFalse);

    final pedidos = await base.select(base.orders).get();
    final porId = {for (final p in pedidos) p.id: p};
    expect(porId['p3']!.stopOrder, 1);
    expect(porId['p1']!.stopOrder, 2);
    expect(porId['p2']!.stopOrder, 3);
    expect(porId['p3']!.routeId, rutaId);
    // `ultimaRutaId` no se libera nunca: un devuelto suelta `routeId` pero
    // conserva esta.
    expect(porId['p3']!.ultimaRutaId, rutaId);

    // La columna se queda; lo que se vacía es lo que llevaba dentro hoy.
    expect((await consultas.columnas(sucursalStg)).single.pedidos, 0);
    expect(await consultas.colocados(sucursalStg, origen), isEmpty);

    final ultimo = (await cola.lote()).last;
    expect(ultimo.metodo, 'POST');
    expect(ultimo.ruta, '/board/columns/$centro/route');
    expect(ultimo.provisional, rutaId);
    // EL CUERPO, CAMPO A CAMPO Y SIN SOBRAS. Se compara el mapa entero a
    // propósito: lo que viaja aquí es lo que el servidor va a creerse horas
    // después, cuando el apunte suba, y un campo de más o de menos no se ve
    // hasta que la ruta ya está armada allá.
    //
    // `deliveryDate` se añadió el 28/09/2026 y va aparte porque es una hora: es
    // la del aparato, no la del servidor —un apunte hecho sin señal llega
    // horas tarde y la ruta se armó el día que la armó el logístico— y por eso
    // se comprueba que ESTÉ y que sea de hoy, no contra un literal.
    final cuerpo = jsonDecode(ultimo.cuerpo) as Map<String, Object?>;
    final dia = cuerpo.remove('deliveryDate');
    expect(cuerpo, {'vehiculoId': 'v1', 'optimizar': false});
    expect(
      dia,
      isA<String>(),
      reason:
          'sin el día, el servidor guarda `delivery_date` nulo y la ruta pierde '
          'su fecha al subir: es el «—» que vio Jose en la ficha y en la lista',
    );
    expect(
      DateTime.parse(dia! as String).difference(DateTime.now()).abs(),
      lessThan(const Duration(minutes: 1)),
    );
  });

  test('la ruta nace con SUS KILÓMETROS, también sin conexión', () async {
    // «Esa ruta, como que cero. Tiene que calcularlo, si eso se calcula sin
    // necesidad de conexión» — Jose, 17/09/2026, con el teléfono sin señal y una
    // ruta de tres paradas que decía «0.0 km (incl. regreso)».
    //
    // Y tenía razón: los datos están todos en el aparato. Cada tarjeta ya enseña
    // sus kilómetros al almacén con la misma fórmula, y el asistente de Rutas
    // —el OTRO camino que crea rutas— ya los calculaba. Eran dos caminos para lo
    // mismo y sólo uno calculaba.
    for (var i = 1; i <= 3; i++) {
      await sembrarPedido(base, id: 'p$i', aGrados: 0.01 * i);
      await repo.colocar(pedidoId: 'p$i', columnaId: centro);
    }

    final rutaId = await repo.armarRuta(
      columnaId: centro,
      origen: origen,
      sucursalId: sucursalStg,
    );

    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals(rutaId))).getSingle();

    expect(
      ruta.totalDistance,
      greaterThan(0),
      reason:
          'una ruta de tres paradas no puede nacer con cero kilómetros: la '
          'pantalla enseña ese número encima de las paradas y quien lo lee se '
          'cree que el camión no se mueve',
    );
    // Y el número es el del CIRCUITO —tramos más el regreso al almacén—, que es
    // lo que dice el rótulo, no la suma de las distancias radiales.
    expect(
      ruta.totalDistance,
      closeTo(
        kmDelCircuito(Punto(origen.lat, origen.lng), [
          for (var i = 1; i <= 3; i++)
            Parada('p$i', almacenLat + 0.01 * i, almacenLng),
        ]),
        0.001,
      ),
      reason: 'los tramos más el regreso, como dice «(incl. regreso)»',
    );
  });

  test('los que no se pueden repartir se quedan puestos y marcados', () async {
    await sembrarPedido(base, id: 'bueno');
    await sembrarPedido(
      base,
      id: 'malo',
      facturaEstado: EstadoFactura.sinFactura,
    );
    await repo.colocar(pedidoId: 'bueno', columnaId: centro);
    await repo.colocar(pedidoId: 'malo', columnaId: centro);

    await repo.armarRuta(
      columnaId: centro,
      origen: origen,
      sucursalId: sucursalStg,
    );

    final quedan = await consultas.colocados(sucursalStg, origen);
    expect(quedan.single.pedido.pedidoId, 'malo');
    expect(quedan.single.pedido.marcas, [MarcaTarjeta.sinFactura]);
  });

  test(
    'sin nada repartible no se crea una ruta vacía, y se dice por qué',
    () async {
      await sembrarPedido(
        base,
        id: 'sin-cotejar',
        cliente: 'Bodega La Palma',
        operacion: 'SC06-1257',
        facturaEstado: null,
      );
      await sembrarPedido(base, id: 'archivado', archivado: true);
      await repo.colocar(pedidoId: 'sin-cotejar', columnaId: centro);
      await repo.colocar(pedidoId: 'archivado', columnaId: centro);

      await expectLater(
        repo.armarRuta(
          columnaId: centro,
          origen: origen,
          sucursalId: sucursalStg,
        ),
        throwsA(
          isA<RechazoDelTablero>()
              .having(
                (e) => e.mensaje,
                'mensaje',
                'La columna no tiene ningún pedido que se pueda repartir hoy',
              )
              // Nombrados: una columna que produce una ruta mas corta sin
              // explicacion es la manera mas rapida de que el logistico deje de
              // fiarse.
              .having(
                (e) => e.detalles.join(' | '),
                'detalles',
                contains('SC06-1257 · Bodega La Palma: Sin cotejar'),
              ),
        ),
      );

      expect(await base.select(base.routes).get(), isEmpty);
      expect((await consultas.colocados(sucursalStg, origen)).length, 2);
    },
  );

  // ---------------------------------------------------------------------------
  // LA DISTANCIA DE CADA PARADA SE ESCRIBE AQUÍ — 28/09/2026
  // ---------------------------------------------------------------------------
  //
  // Jose, mirando `RT-20260928-001` recién armada en el teléfono: «mira todos
  // los — que hay en la ruta». Las tres paradas decían «— desde partida».
  //
  // No era que el dato no existiera: los otros TRES caminos que enganchan una
  // parada lo escriben —los dos del servidor y el armado local del asistente de
  // Rutas—, y en producción las 24 paradas tenían su número. El que no lo
  // escribía era éste, que es **el principal**: es como se arma el día, por
  // zonas. Así que la ruta nacía con la raya puesta y sólo se arreglaba cuando
  // la siguiente bajada traía del servidor un número que el aparato ya tenía.

  test('cada parada nace con su distancia desde la partida', () async {
    for (var i = 1; i <= 3; i++) {
      await sembrarPedido(base, id: 'p$i', aGrados: 0.01 * i);
      await repo.colocar(pedidoId: 'p$i', columnaId: centro);
    }

    await repo.armarRuta(
      columnaId: centro,
      origen: origen,
      sucursalId: sucursalStg,
    );

    final porId = {
      for (final p in await base.select(base.orders).get()) p.id: p,
    };
    for (var i = 1; i <= 3; i++) {
      expect(
        porId['p$i']!.segmentKm,
        isNotNull,
        reason:
            'la parada p$i nació sin distancia: es el «— desde partida» que vio '
            'Jose en las tres paradas de RT-20260928-001',
      );
    }

    // Y es la RADIAL del almacén al cliente, la misma cuenta que hace el
    // servidor. Se comprueba contra la fórmula, no contra un número copiado:
    // p2 está al doble de grados que p1, así que tiene que estar más lejos.
    final esperada = haversineKm(
      Punto(origen.lat, origen.lng),
      Punto(almacenLat + 0.01, almacenLng),
    );
    expect(porId['p1']!.segmentKm, closeTo(esperada, 0.0001));
    expect(porId['p2']!.segmentKm!, greaterThan(porId['p1']!.segmentKm!));
  });

  test('sin coordenada del cliente la distancia queda NULA, no en cero', () async {
    await sembrarPedido(base, id: 'p1');
    await sembrarPedido(base, id: 'p2', conCoordenadas: false);
    await repo.colocar(pedidoId: 'p1', columnaId: centro);
    await repo.colocar(pedidoId: 'p2', columnaId: centro);

    await repo.armarRuta(
      columnaId: centro,
      origen: origen,
      sucursalId: sucursalStg,
    );

    final porId = {
      for (final p in await base.select(base.orders).get()) p.id: p,
    };
    expect(
      porId['p2']!.segmentKm,
      isNull,
      reason:
          'un cero ahí se lee como «el cliente está en la puerta del almacén», '
          'que es un número creíble y equivocado',
    );
    expect(porId['p1']!.segmentKm, isNotNull);
  });

  // ---------------------------------------------------------------------------
  // NINGUNA RUTA SIN CAMIÓN — 28/09/2026
  // ---------------------------------------------------------------------------
  //
  // Jose, viendo `RT-20260928-001` en producción, «En curso · 3 paradas · Sin
  // vehículo»: «por q se creo una ruta sin vehiculo eso no se puede mi broder».
  //
  // Sin camión la ruta sale con su peso y su importe y **no hay nada con que
  // contrastarlos**: la capacidad se mide contra la del camión y el coste por km
  // sale de su `costo_km_usd`. Dos números creíbles sin denominador, que es el
  // fallo que más caro sale aquí.
  //
  // El `setUp` de este fichero crea «Centro» CON camión (`v1`), así que todo lo
  // de arriba sigue midiendo lo suyo. Estas dos prueban la guarda, y van EN
  // PAREJA a propósito: sin la segunda, un bloqueo de más —el caso de los 657 de
  // 686 domicilios sin costo del CLAUDE.md §2, que dejaría el tablero
  // inservible— no lo cazaría nadie.

  test('sin camión previsto no se arma la ruta, y se dice dónde se arregla', () async {
    // Una zona igual que Centro pero sin camión, y con dos pedidos BUENOS: si
    // estuviera vacía, el «no» saldría por «no hay nada repartible» y esta
    // prueba pasaría aunque la guarda no existiera.
    final sinCamion = await repo.crearColumna(
      sucursalId: sucursalStg,
      nombre: 'Carretera',
    );
    await sembrarPedido(base, id: 'p1');
    await sembrarPedido(base, id: 'p2', aGrados: 0.02);
    await repo.colocar(pedidoId: 'p1', columnaId: sinCamion);
    await repo.colocar(pedidoId: 'p2', columnaId: sinCamion);

    await expectLater(
      repo.armarRuta(
        columnaId: sinCamion,
        origen: origen,
        sucursalId: sucursalStg,
      ),
      throwsA(
        isA<RechazoDelTablero>()
            .having(
              (e) => e.mensaje,
              'mensaje',
              contains('no tiene camión previsto'),
            )
            // NOMBRADA. «La zona no tiene camión» sobre un tablero de seis zonas
            // manda a mirar las seis.
            .having((e) => e.mensaje, 'la zona, por su nombre', contains('Carretera'))
            // Y DÓNDE SE ARREGLA. El camión de una zona no se elige en el
            // asistente: se pone en «Camión previsto», en sus opciones. Un
            // rechazo que no dice dónde es un rechazo permanente.
            .having(
              (e) => e.detalles.join(' | '),
              'detalles',
              contains('Camión previsto'),
            ),
      ),
    );

    // NI RUTA NI TARJETAS MOVIDAS. Un «no» que deja media ruta escrita es peor
    // que no tener guarda.
    expect(await base.select(base.routes).get(), isEmpty);
    expect((await consultas.colocados(sucursalStg, origen)).length, 2);
    // Y NADA SALIÓ A LA COLA: el apunte ni se encola, así que no hay nada que
    // rechazar horas después en la bandeja.
    expect(
      (await cola.lote()).where((a) => a.ruta.endsWith('/route')),
      isEmpty,
      reason:
          'si el apunte se encola, la APK sin señal se lleva a la bandeja de '
          'rechazos un «no» que ya sabíamos dar aquí mismo',
    );
  });

  test('la MISMA zona con camión previsto sí arma su ruta', () async {
    // Lo único que cambia: `vehiculoId`. Es la mitad que caza un bloqueo de más
    // — si esto se pone rojo, el tablero se quedó sin poder armar nada.
    final conCamion = await repo.crearColumna(
      sucursalId: sucursalStg,
      nombre: 'Carretera',
      vehiculoId: 'v1',
    );
    await sembrarPedido(base, id: 'p1');
    await sembrarPedido(base, id: 'p2', aGrados: 0.02);
    await repo.colocar(pedidoId: 'p1', columnaId: conCamion);
    await repo.colocar(pedidoId: 'p2', columnaId: conCamion);

    final rutaId = await repo.armarRuta(
      columnaId: conCamion,
      origen: origen,
      sucursalId: sucursalStg,
    );

    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals(rutaId))).getSingle();
    expect(ruta.vehicleId, 'v1');
  });

  // Y EL ORDEN: primero «no hay nada repartible», después el camión.
  //
  // Es el orden del servidor (`api/internal/api/tablero.go`,
  // `armarRutaDeColumna`: el 409 de la zona sin nada va antes que el 400 del
  // camión). Si dos fallan a la vez, la persona tiene que leer el MISMO mensaje
  // por los dos caminos: moverlo aquí y no allá deja al aparato y al servidor
  // diciendo cosas distintas del mismo gesto, y eso sólo se ve en producción.
  test('una zona sin camión Y sin nada repartible habla de lo repartible', () async {
    final sinNada = await repo.crearColumna(
      sucursalId: sucursalStg,
      nombre: 'Carretera',
    );
    await sembrarPedido(
      base,
      id: 'sin-cotejar',
      cliente: 'Bodega La Palma',
      operacion: 'SC06-1257',
      facturaEstado: null,
    );
    await repo.colocar(pedidoId: 'sin-cotejar', columnaId: sinNada);

    await expectLater(
      repo.armarRuta(
        columnaId: sinNada,
        origen: origen,
        sucursalId: sucursalStg,
      ),
      throwsA(
        isA<RechazoDelTablero>().having(
          (e) => e.mensaje,
          'mensaje',
          'La columna no tiene ningún pedido que se pueda repartir hoy',
        ),
      ),
    );
  });
}
