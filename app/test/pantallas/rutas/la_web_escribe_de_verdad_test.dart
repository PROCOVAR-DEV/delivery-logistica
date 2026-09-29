// LA WEB ESCRIBE DE VERDAD, Y LO QUE EL SERVIDOR RECHAZA SE DICE.
//
// ## El fallo que trajo estas pruebas — medido en producción el 22/09/2026
//
// Se armaba una ruta con tres pedidos en el navegador: el asistente se cerraba,
// **no salía ni un mensaje**, y tras un F5 no había ruta. La única petición que
// salía al pulsar «Generar Ruta» era `POST /sync/aparato`, y contestaba 401 —en
// un navegador no hay par de tokens que dar de alta—. O sea que el apunte se
// quedaba en una cola que no sube nunca, sobre una base **en memoria** que muere
// al recargar, y ninguna pantalla lo desmentía.
//
// Lo que aquí se fija son las dos mitades, y las dos hacen falta:
//
//  * que el gesto **salga** —con su método, su ruta y su cuerpo— y que lo que
//    quede escrito lleve el id DEL SERVIDOR, no un `local-…`;
//  * que cuando el servidor dice que no, **no quede escrita una sola fila** y
//    salga su motivo LITERAL (`CLAUDE.md` §3-quinquies).
//
// Y la tercera, la que impide arreglar una cosa rompiendo la otra: en la APK y
// en el escritorio no sale ni una petición y la cola sigue siendo la respuesta.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late RelojFalso reloj;
  late ServidorFalso servidor;
  late AccionesDeRuta enLaWeb;
  late AccionesDeRuta enElAparato;

  /// Lo que contesta el servidor falso. Se cambia dentro de cada prueba.
  late Future<RespuestaFalsa?> Function(PeticionVista) contesta;

  setUp(() async {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime.utc(2026, 9, 22, 16, 5));
    cola = ColaDeSalida(base, reloj: reloj.leer);
    contesta = (_) async => RespuestaFalsa(200, const <String, Object?>{});
    servidor = ServidorFalso((p) => contesta(p));
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
      ..httpClientAdapter = servidor;
    enLaWeb = AccionesDeRuta(
      base,
      cola,
      reloj: reloj.leer,
      sufijoAparato: 'WEB',
      enVivo: EscrituraEnVivo(
        // Sin esperas: un `FalloDeRed` no se reintenta cuatro veces dentro de
        // una prueba, que es como se pasa de 40 ms a 15 s sin enterarse.
        ClienteApi(dio: dio, esperas: const <Duration>[]),
      ),
    );
    enElAparato = AccionesDeRuta(
      base,
      cola,
      reloj: reloj.leer,
      sufijoAparato: 'MSI',
    );

    await sembrarCatalogo(base);
    await sembrarPedido(
      base,
      id: 'q1',
      cliente: 'Ana',
      folio: 'F-001',
      peso: 100,
      endLat: 0,
      endLng: 0.1,
    );
    await sembrarPedido(
      base,
      id: 'q2',
      cliente: 'Beto',
      folio: 'F-002',
      peso: 200,
      endLat: 0,
      endLng: 0.3,
    );
  });

  tearDown(() => base.close());

  Future<String> armar(AccionesDeRuta acciones) => acciones.armar(
    vehiculoId: 'V1',
    pedidoIds: const ['q1', 'q2'],
    origenLat: 0,
    origenLng: 0,
    sucursalId: 'B1',
    nombre: 'Reparto de la mañana',
  );

  /// La ruta tal y como la devuelve `POST /api/routes`
  /// (`api/internal/api/rutas.go`, `RutaSalida`).
  Map<String, Object?> laRutaDelServidor({String id = 'r-de-verdad'}) =>
      <String, Object?>{
        'id': id,
        'name': 'Reparto de la mañana',
        'routeCode': 'RT-20260922-007',
        'status': EstadoRuta.planificada,
        'originLat': 0.0,
        'originLng': 0.0,
        'totalDistance': 66.7,
        'totalWeight': 300.0,
        'totalPrice': 20.0,
        'vehicleId': 'V1',
        'branchId': 'B1',
        'optimized': true,
        'createdAt': '2026-09-22T16:05:00Z',
        'updatedAt': '2026-09-22T16:05:00Z',
        'orders': <Object?>[
          <String, Object?>{
            'id': 'q1',
            'stopOrder': 1,
            'segmentKm': 11.1,
            'price': 10.0,
            'tripLeg': Tramo.ida,
          },
          <String, Object?>{
            'id': 'q2',
            'stopOrder': 2,
            'segmentKm': 33.3,
            'price': 10.0,
            'tripLeg': Tramo.ida,
          },
        ],
      };

  Future<int> cuantasRutas() async =>
      (await base.select(base.routes).get()).length;

  Future<int> cuantosApuntes() async =>
      (await base.select(base.apuntes).get()).length;

  // ---------------------------------------------------------------------------
  group('armar', () {
    test('sale POST /routes y lo que queda lleva el id DEL SERVIDOR', () async {
      contesta = (p) async => RespuestaFalsa(201, laRutaDelServidor());

      final rutaId = await armar(enLaWeb);

      // 1. Salió, y con su cuerpo.
      expect(servidor.vistas.length, 1);
      expect(servidor.vistas.single.metodo, 'POST');
      expect(servidor.vistas.single.ruta, '/routes');
      final cuerpo = servidor.vistas.single.cuerpo! as Map<String, Object?>;
      expect(cuerpo['orderIds'], ['q1', 'q2']);
      expect(cuerpo['vehicleId'], 'V1');
      expect(cuerpo['branchId'], 'B1');
      expect(cuerpo['optimizar'], true);

      // 2. El id es el del servidor. NADA de `local-…`: en un navegador esa
      //    sustitución no llega nunca, y el cierre de la tarde se iría a
      //    `/routes/local-9f3a`.
      expect(rutaId, 'r-de-verdad');
      expect(rutaId, isNot(startsWith('local-')));

      // 3. Y lo que se guarda es lo que el servidor guardó, no lo que
      //    creíamos. Su código de ruta, sus totales, su orden de paradas.
      final ruta = await (base.select(
        base.routes,
      )..where((r) => r.id.equals(rutaId))).getSingle();
      expect(ruta.routeCode, 'RT-20260922-007');
      expect(ruta.totalDistance, 66.7);
      expect(ruta.totalWeight, 300);
      expect(ruta.optimized, isTrue);

      final paradas = await (base.select(
        base.orders,
      )..where((o) => o.routeId.equals(rutaId))).get();
      expect({for (final p in paradas) p.id: p.stopOrder}, {'q1': 1, 'q2': 2});
      expect(paradas.every((p) => p.ultimaRutaId == rutaId), isTrue);

      // 4. Y NO SE ENCOLA NADA. Con un apunte en la cola, el ciclo volvería a
      //    intentar `POST /sync/aparato` y a comerse su 401.
      expect(await cuantosApuntes(), 0);
    });

    test('el aviso de los domicilios sin costear viene envuelto y el id '
        'se encuentra igual', () async {
      // `responderConLaRutaYAvisos` contesta `{"ruta": …, "avisos": …}` cuando
      // hay domicilios sin costo. Son 657 de 686, o sea casi todas las rutas:
      // leer sólo la forma desnuda dejaría sin id justo el caso normal.
      contesta = (p) async => RespuestaFalsa(201, <String, Object?>{
        'ruta': laRutaDelServidor(),
        'avisos': <String, Object?>{'sinCosto': 3, 'detalle': 'tres sin costo'},
      });

      expect(await armar(enLaWeb), 'r-de-verdad');
      expect(await cuantasRutas(), 1);
    });

    test('el servidor dice que no: el motivo LITERAL y NI UNA FILA', () async {
      const elNo =
          '1 de los 2 pedidos elegidos no puede ir en esta ruta: '
          'F-002 (ya va en la ruta RT-20260922-003).';
      contesta = (p) async =>
          RespuestaFalsa(409, <String, Object?>{'error': elNo});

      await expectLater(
        () => armar(enLaWeb),
        throwsA(
          isA<RechazoLocal>().having((r) => r.mensaje, 'mensaje', elNo),
        ),
      );

      // ESTO ES LO QUE NO PUEDE QUEDAR DE NINGUNA MANERA: la pantalla pintando
      // como hecho algo que no salió del navegador.
      expect(await cuantasRutas(), 0);
      expect(await cuantosApuntes(), 0);
      final q1 = await (base.select(
        base.orders,
      )..where((o) => o.id.equals('q1'))).getSingle();
      expect(q1.routeId, isNull);
      expect(q1.ultimaRutaId, isNull);
    });

    test('sin conexión tampoco se pinta nada, y se dice', () async {
      // `null` = la petición ni sale. En la web esto NO se reintenta luego: no
      // hay cola. Lo único que no puede pasar es que se dé por hecha.
      contesta = (p) async => null;

      await expectLater(
        () => armar(enLaWeb),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            'Sin conexión con el servidor.',
          ),
        ),
      );
      expect(await cuantasRutas(), 0);
      expect(await cuantosApuntes(), 0);
    });

    test('dijo que sí y no dijo cuál: tampoco se da por armada', () async {
      contesta = (p) async => RespuestaFalsa(201, const <String, Object?>{});

      await expectLater(
        () => armar(enLaWeb),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            contains('sin su identificador'),
          ),
        ),
      );
      expect(await cuantasRutas(), 0);
    });
  });

  // ---------------------------------------------------------------------------
  group('las otras cuatro acciones', () {
    setUp(() async {
      contesta = (p) async => RespuestaFalsa(201, laRutaDelServidor());
      await armar(enLaWeb);
      servidor.vistas.clear();
    });

    test('iniciar: sale el PATCH, y si dicen que no la ruta no se mueve',
        () async {
      contesta = (p) async => RespuestaFalsa(409, const <String, Object?>{
        'error': 'Ese camión ya está en otra ruta',
      });

      await expectLater(
        () => enLaWeb.iniciar('r-de-verdad'),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            'Ese camión ya está en otra ruta',
          ),
        ),
      );
      expect(servidor.vistas.single.metodo, 'PATCH');
      expect(servidor.vistas.single.ruta, '/routes/r-de-verdad');

      final ruta = await (base.select(
        base.routes,
      )..where((r) => r.id.equals('r-de-verdad'))).getSingle();
      expect(ruta.status, EstadoRuta.planificada);
      expect(ruta.startedAt, isNull);
      final camion = await (base.select(
        base.vehicles,
      )..where((v) => v.id.equals('V1'))).getSingle();
      expect(camion.status, isNot(EstadoVehiculo.enUso));
    });

    test('iniciar: si dicen que sí, se mueve aquí también', () async {
      contesta = (p) async => RespuestaFalsa(200, laRutaDelServidor());
      await enLaWeb.iniciar('r-de-verdad');

      final ruta = await (base.select(
        base.routes,
      )..where((r) => r.id.equals('r-de-verdad'))).getSingle();
      expect(ruta.status, EstadoRuta.enCurso);
      expect(ruta.startedAt, reloj.ahora);
      expect(await cuantosApuntes(), 0);
    });

    test('completar: rechazado, la ruta sigue como estaba', () async {
      contesta = (p) async => RespuestaFalsa(200, laRutaDelServidor());
      await enLaWeb.iniciar('r-de-verdad');
      contesta = (p) async => RespuestaFalsa(400, const <String, Object?>{
        'error': 'Quedan paradas sin cerrar',
      });

      await expectLater(
        () => enLaWeb.completar('r-de-verdad'),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            'Quedan paradas sin cerrar',
          ),
        ),
      );
      final ruta = await (base.select(
        base.routes,
      )..where((r) => r.id.equals('r-de-verdad'))).getSingle();
      expect(ruta.status, EstadoRuta.enCurso);
      expect(ruta.finishedAt, isNull);
    });

    test('eliminar: el portazo del servidor manda, y con su número de paradas',
        () async {
      // El literal lleva el número dentro a propósito: es lo que hace que quien
      // lo lee sepa de qué ruta le hablan. Aquí no se puede saber sin bajarse la
      // hoja entera, así que lo dice el servidor y se pinta tal cual.
      const elNo =
          'Esa ruta ya tiene 9 parada(s) cerradas y no se puede borrar: se '
          'perdería la hoja de lo que bajó del camión. Márcala como cancelada '
          'si hace falta.';
      contesta = (p) async =>
          RespuestaFalsa(409, <String, Object?>{'error': elNo});

      await expectLater(
        () => enLaWeb.eliminar('r-de-verdad'),
        throwsA(
          isA<RechazoLocal>().having((r) => r.mensaje, 'mensaje', elNo),
        ),
      );
      expect(servidor.vistas.single.metodo, 'DELETE');
      expect(await cuantasRutas(), 1);
      final q1 = await (base.select(
        base.orders,
      )..where((o) => o.id.equals('q1'))).getSingle();
      expect(q1.routeId, 'r-de-verdad', reason: 'la parada sigue enganchada');
    });

    test('cerrar: el cierre sale ENTERO al servidor antes de tocar nada',
        () async {
      contesta = (p) async => RespuestaFalsa(400, const <String, Object?>{
        'error': 'ese pedido no va en esta ruta',
      });

      await expectLater(
        () => enLaWeb.cerrar('r-de-verdad', const [
          MarcaDeParada(
            pedidoId: 'q1',
            resultado: ResultadoParada.entregado,
            nota: '  con recibo  ',
          ),
        ]),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            'ese pedido no va en esta ruta',
          ),
        ),
      );

      // El cierre es el caso de uso principal y el más caro de equivocar: lo que
      // baja del camión es lo que se cuadra. Ni una marca puesta.
      final q1 = await (base.select(
        base.orders,
      )..where((o) => o.id.equals('q1'))).getSingle();
      expect(q1.resultado, isNull);
      expect(q1.deliveredAt, isNull);
      expect(await cuantosApuntes(), 0);
    });

    test('cerrar: aceptado, se marca aquí y la nota va recortada', () async {
      contesta = (p) async => RespuestaFalsa(200, const <String, Object?>{});

      final clave = await enLaWeb.cerrar('r-de-verdad', const [
        MarcaDeParada(
          pedidoId: 'q1',
          resultado: ResultadoParada.entregado,
          nota: '  con recibo  ',
        ),
        MarcaDeParada(
          pedidoId: 'q2',
          resultado: ResultadoParada.devuelto,
          nota: '   ',
        ),
      ]);
      // En la web no hay apunte al que seguirle la pista: ya está arriba.
      expect(clave, '');

      final cuerpo = servidor.vistas.single.cuerpo! as Map<String, Object?>;
      expect(servidor.vistas.single.ruta, '/routes/r-de-verdad/results');
      final resultados = cuerpo['resultados']! as List<Object?>;
      expect(resultados.length, 2);
      // La nota ya sale limpia hacia el servidor, igual que la escribe él.
      expect(
        (resultados.first! as Map<String, Object?>)['nota'],
        'con recibo',
      );
      expect((resultados[1]! as Map<String, Object?>)['nota'], isNull);

      final q1 = await (base.select(
        base.orders,
      )..where((o) => o.id.equals('q1'))).getSingle();
      expect(q1.resultado, ResultadoParada.entregado);
      expect(q1.deliveredAt, reloj.ahora);
      final q2 = await (base.select(
        base.orders,
      )..where((o) => o.id.equals('q2'))).getSingle();
      // Lo que no se entrega suelta su ruta y conserva `ultimaRutaId`.
      expect(q2.routeId, isNull);
      expect(q2.ultimaRutaId, 'r-de-verdad');
      expect(await cuantosApuntes(), 0);
    });
  });

  // ---------------------------------------------------------------------------
  group('EL OTRO MUNDO, intacto', () {
    test('en la APK no sale NI UNA petición y la cola sigue mandando', () async {
      final rutaId = await armar(enElAparato);

      expect(
        servidor.vistas,
        isEmpty,
        reason:
            'la APK arma la ruta en el patio de un almacén, sin señal: si esto '
            'llama a alguien, no se puede armar una ruta sin red',
      );
      expect(rutaId, startsWith('local-'));
      expect(await cuantosApuntes(), 1);

      final apunte = (await cola.pendientes().first).single;
      expect(apunte.metodo, 'POST');
      expect(apunte.ruta, '/routes');
      expect(apunte.provisional, rutaId);
      final cuerpo = ColaDeSalida.cuerpoDe(apunte)! as Map<String, Object?>;
      expect(cuerpo['orderIds'], ['q1', 'q2']);
      expect(cuerpo['optimizar'], true);

      // Y el código de ruta lo sigue poniendo el aparato, con su sufijo.
      final ruta = await (base.select(
        base.routes,
      )..where((r) => r.id.equals(rutaId))).getSingle();
      expect(ruta.routeCode, 'RT-20260922-001-MSI');
    });

    test('iniciar y eliminar en la APK: local + cola, sin red', () async {
      final rutaId = await armar(enElAparato);
      await enElAparato.iniciar(rutaId);
      await enElAparato.eliminar(rutaId);

      expect(servidor.vistas, isEmpty);
      expect(await cuantosApuntes(), 3);
      expect(await cuantasRutas(), 0);
    });
  });
}
