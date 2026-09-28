// EL TABLERO DE LA WEB ESCRIBE DE VERDAD.
//
// ## El fallo — medido en producción el 22/09/2026
//
// Se colocaba una tarjeta: la ficha se cerraba, la tarjeta seguía donde estaba y
// «Vista (0)» seguía en 0. La cola del navegador no subía NADA —sale por `/sync`
// y allí hace falta un aparato dado de alta, que en un navegador no existe: el
// alta contestaba 401— y la base de la web es en memoria, así que el apunte
// moría con la pestaña. Ni un mensaje.
//
// Lo que aquí se fija, y las tres mitades hacen falta:
//
//  * que el gesto **salga** al servidor con su método y su ruta;
//  * que si el servidor dice que no, **Drift deshaga la transacción entera** —la
//    tarjeta no se movió— y salga su motivo literal (`CLAUDE.md` §3-quinquies);
//  * que en la APK y en el escritorio no salga ni una petición y la cola siga
//    siendo la respuesta: allí el tablero se prepara por la tarde, sin señal.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/escritura_en_vivo.dart';
import 'package:reparto/nucleo/sincro/huerfanos.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

void main() {
  late BaseLocal base;
  late ConsultasTablero consultas;
  late ColaDeSalida cola;
  late ServidorFalso servidor;
  late RepositorioTablero enLaWeb;
  late RepositorioTablero enElAparato;
  late Future<RespuestaFalsa?> Function(PeticionVista) contesta;

  const origen = AlmacenOrigen(
    id: 'alm-1',
    nombre: 'Almacén principal',
    lat: almacenLat,
    lng: almacenLng,
  );

  setUp(() async {
    base = baseDePrueba();
    consultas = ConsultasTablero(base);
    cola = ColaDeSalida(base);
    contesta = (_) async => RespuestaFalsa(200, const <String, Object?>{});
    servidor = ServidorFalso((p) => contesta(p));
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
      ..httpClientAdapter = servidor;
    enLaWeb = RepositorioTablero(
      base,
      cola,
      enVivo: EscrituraEnVivo(
        ClienteApi(dio: dio, esperas: const <Duration>[]),
      ),
    );
    enElAparato = RepositorioTablero(base, cola);
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarPedido(base, id: 'p1');
    await sembrarPedido(base, id: 'p2', aGrados: 0.02);
  });

  tearDown(() => base.close());

  Future<int> cuantosApuntes() async =>
      (await base.select(base.apuntes).get()).length;

  Future<int> cuantasColocaciones() async {
    await EsquemaTablero.asegurar(base);
    final fila = await base
        .customSelect('SELECT count(*) AS n FROM ${EsquemaTablero.colocaciones}')
        .getSingle();
    return fila.read<int>('n');
  }

  // ---------------------------------------------------------------------------
  group('arrastrar', () {
    test('sale PUT /board/placements/<pedido> y la tarjeta se queda', () async {
      final columna = await enLaWeb.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Vista',
      );
      servidor.vistas.clear();

      await enLaWeb.colocar(pedidoId: 'p1', columnaId: columna);

      expect(servidor.vistas.length, 1);
      expect(servidor.vistas.single.metodo, 'PUT');
      expect(servidor.vistas.single.ruta, '/board/placements/p1');
      expect(servidor.vistas.single.cuerpo, {
        'columnaId': columna,
        'posicion': 1,
      });

      expect(await cuantasColocaciones(), 1);
      // NADA en la cola: con un apunte ahí, el ciclo volvería a intentar el
      // `POST /sync/aparato` y a comerse su 401 en cada vuelta.
      expect(await cuantosApuntes(), 0);
    });

    test('el servidor dice que no: LA TARJETA NO SE MUEVE, y se dice por qué',
        () async {
      final columna = await enLaWeb.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Vista',
      );
      const elNo = 'Ese pedido ya va en otra ruta';
      contesta = (p) async =>
          RespuestaFalsa(409, <String, Object?>{'error': elNo});

      await expectLater(
        () => enLaWeb.colocar(pedidoId: 'p1', columnaId: columna),
        throwsA(
          isA<RechazoDelTablero>().having((r) => r.mensaje, 'mensaje', elNo),
        ),
      );

      // ESTO ES LO QUE NO PUEDE QUEDAR: la tarjeta pintada en su columna nueva
      // con el servidor diciendo que no. La escritura local y el envío van en la
      // MISMA transacción, así que el «no» la deshace entera.
      expect(await cuantasColocaciones(), 0);
      expect(await cuantosApuntes(), 0);
    });

    test('PASAR UN PEDIDO DE UNA ZONA A OTRA: sale, y con la posición buena',
        () async {
      // EL GESTO QUE JOSE HACE MUCHAS VECES AL DÍA, y el que reportó roto:
      // «en la web no funcionó, pasaste un pedido para otro tablero y no hizo
      // nada». En la APK funciona; lo que no salía del navegador era esto.
      //
      // Colocar y mover son LA MISMA orden —«este pedido va aquí»— así que se
      // comprueban juntas: soltar en «Vista» y después arrastrar a «Centro».
      final vista = await enLaWeb.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Vista',
      );
      final centro = await enLaWeb.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Centro',
      );
      await enLaWeb.colocar(pedidoId: 'p1', columnaId: vista);
      await enLaWeb.colocar(pedidoId: 'p2', columnaId: centro);
      servidor.vistas.clear();

      await enLaWeb.colocar(pedidoId: 'p1', columnaId: centro);

      expect(servidor.vistas.length, 1);
      expect(servidor.vistas.single.metodo, 'PUT');
      expect(servidor.vistas.single.ruta, '/board/placements/p1');
      expect(servidor.vistas.single.cuerpo, containsPair('columnaId', centro));

      final columnas = await consultas.columnas(sucursalStg);
      final deVista = columnas.firstWhere((c) => c.id == vista);
      final deCentro = columnas.firstWhere((c) => c.id == centro);
      expect(deVista.pedidos, 0, reason: 'la zona de origen se queda vacía');
      expect(deCentro.pedidos, 2, reason: '«Centro (2)», no «Centro (0)»');
      expect(await cuantosApuntes(), 0);
    });

    test('mover a otra zona rechazado: la tarjeta se queda en la suya, '
        'con el motivo literal del servidor', () async {
      final vista = await enLaWeb.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Vista',
      );
      final centro = await enLaWeb.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Centro',
      );
      await enLaWeb.colocar(pedidoId: 'p1', columnaId: vista);

      // El literal de `porQueNoSePudoColocar` (`api/internal/api/tablero.go`,
      // `msgYaVaEnUnaRuta`). Se aprovecha el que ya existe en vez de inventar
      // otro: el mismo «no» tiene que leerse igual venga por donde venga.
      const elNo = 'Ese pedido ya está en una ruta';
      contesta = (p) async =>
          RespuestaFalsa(409, <String, Object?>{'error': elNo});

      await expectLater(
        () => enLaWeb.colocar(pedidoId: 'p1', columnaId: centro),
        throwsA(
          isA<RechazoDelTablero>().having((r) => r.mensaje, 'mensaje', elNo),
        ),
      );

      final columnas = await consultas.columnas(sucursalStg);
      expect(columnas.firstWhere((c) => c.id == vista).pedidos, 1);
      expect(columnas.firstWhere((c) => c.id == centro).pedidos, 0);
    });

    test('quitar rechazado: la tarjeta se queda donde estaba', () async {
      final columna = await enLaWeb.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Vista',
      );
      await enLaWeb.colocar(pedidoId: 'p1', columnaId: columna);
      contesta = (p) async => RespuestaFalsa(409, const <String, Object?>{
        'error': 'Esa tarjeta ya salió en una ruta',
      });

      await expectLater(
        () => enLaWeb.quitar('p1'),
        throwsA(
          isA<RechazoDelTablero>().having(
            (r) => r.mensaje,
            'mensaje',
            'Esa tarjeta ya salió en una ruta',
          ),
        ),
      );
      expect(await cuantasColocaciones(), 1);
    });

    test('sin conexión no se mueve nada, y se dice', () async {
      final columna = await enLaWeb.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Vista',
      );
      contesta = (p) async => null;

      await expectLater(
        () => enLaWeb.colocar(pedidoId: 'p1', columnaId: columna),
        throwsA(
          isA<RechazoDelTablero>().having(
            (r) => r.mensaje,
            'mensaje',
            'Sin conexión con el servidor.',
          ),
        ),
      );
      expect(await cuantasColocaciones(), 0);
    });
  });

  // ---------------------------------------------------------------------------
  group('las columnas', () {
    test('crear sale POST y el id que se manda es el que se guarda', () async {
      final id = await enLaWeb.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Vista',
      );
      expect(servidor.vistas.single.metodo, 'POST');
      expect(
        servidor.vistas.single.ruta,
        '/board/columns?branchId=$sucursalStg',
      );
      final cuerpo = servidor.vistas.single.cuerpo! as Map<String, Object?>;
      expect(cuerpo['id'], id);
      expect(cuerpo['nombre'], 'Vista');
      expect((await consultas.columnas(sucursalStg)).single.id, id);
      expect(await cuantosApuntes(), 0);
    });

    test('crear rechazada: NO queda columna ninguna', () async {
      contesta = (p) async => RespuestaFalsa(409, const <String, Object?>{
        'error': 'Ya hay una columna «Vista» en este tablero',
      });

      await expectLater(
        () => enLaWeb.crearColumna(sucursalId: sucursalStg, nombre: 'Vista'),
        throwsA(
          isA<RechazoDelTablero>().having(
            (r) => r.mensaje,
            'mensaje',
            'Ya hay una columna «Vista» en este tablero',
          ),
        ),
      );
      expect(await consultas.columnas(sucursalStg), isEmpty);
    });

    test('renombrar rechazado: el nombre viejo se queda', () async {
      final id = await enLaWeb.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Vista',
      );
      contesta = (p) async => RespuestaFalsa(409, const <String, Object?>{
        'error': 'Ya hay una columna «Centro» en este tablero',
      });

      await expectLater(
        () => enLaWeb.renombrarColumna(id, 'Centro'),
        throwsA(isA<RechazoDelTablero>()),
      );
      expect((await consultas.columnas(sucursalStg)).single.nombre, 'Vista');
    });
  });

  // ---------------------------------------------------------------------------
  group('de una columna sale una ruta', () {
    Future<String> conUnaColumnaPuesta() async {
      // CON SU CAMIÓN PREVISTO. Desde el 28/09/2026 una zona sin camión no arma
      // ruta (`armarRuta`, `RechazoDelTablero` de «Camión previsto»), así que
      // sin esto los cuatro casos de aquí abajo —el id del servidor, el 409, los
      // descartados y el 201 sin id— medirían ese rechazo y no lo suyo.
      await sembrarCamion(base, id: 'v1', capacidad: 2000);
      final id = await enLaWeb.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Vista',
        vehiculoId: 'v1',
      );
      await enLaWeb.colocar(pedidoId: 'p1', columnaId: id);
      await enLaWeb.colocar(pedidoId: 'p2', columnaId: id);
      servidor.vistas.clear();
      return id;
    }

    test('la ruta nace con el id DEL SERVIDOR, no con un `local-…`', () async {
      final columna = await conUnaColumnaPuesta();
      contesta = (p) async => RespuestaFalsa(201, const <String, Object?>{
        'id': 'r-de-verdad',
        'routeCode': 'RT-20260922-004',
        'paradas': 2,
        'descartados': <Object?>[],
      });

      final rutaId = await enLaWeb.armarRuta(
        columnaId: columna,
        origen: origen,
        sucursalId: sucursalStg,
      );

      expect(servidor.vistas.single.metodo, 'POST');
      expect(servidor.vistas.single.ruta, '/board/columns/$columna/route');
      expect(servidor.vistas.single.cuerpo, containsPair('optimizar', false));

      // EN UN NAVEGADOR EL `local-…` NO SE SUSTITUYE NUNCA: la sustitución la
      // hace la subida de la cola, y esa cola no sube. La pantalla se iría a
      // `/routes/local-9f3a` y al recargar no habría ni ruta ni tarjetas.
      expect(rutaId, 'r-de-verdad');
      expect(rutaId, isNot(startsWith('local-')));

      final ruta = await (base.select(
        base.routes,
      )..where((r) => r.id.equals('r-de-verdad'))).getSingle();
      expect(ruta.optimized, isFalse, reason: 'el orden lo puso una persona');
      final p1 = await (base.select(
        base.orders,
      )..where((o) => o.id.equals('p1'))).getSingle();
      expect(p1.routeId, 'r-de-verdad');
      expect(p1.ultimaRutaId, 'r-de-verdad');
      // Y la zona se vacía: esas tarjetas ya salieron.
      expect(await cuantasColocaciones(), 0);
      expect(await cuantosApuntes(), 0);
    });

    test('rechazada: ni ruta, ni tarjetas movidas, y con su motivo', () async {
      final columna = await conUnaColumnaPuesta();
      contesta = (p) async => RespuestaFalsa(409, const <String, Object?>{
        'error': 'Uno de los pedidos se subió a otra ruta mientras se armaba '
            'ésta. Vuelve a intentarlo.',
      });

      await expectLater(
        () => enLaWeb.armarRuta(
          columnaId: columna,
          origen: origen,
          sucursalId: sucursalStg,
        ),
        throwsA(
          isA<RechazoDelTablero>().having(
            (r) => r.mensaje,
            'mensaje',
            startsWith('Uno de los pedidos se subió a otra ruta'),
          ),
        ),
      );
      expect(await base.select(base.routes).get(), isEmpty);
      expect(await cuantasColocaciones(), 2);
    });

    test('el «no» trae NOMBRADOS los que se cayeron, y llegan a la pantalla',
        () async {
      // «La columna no tiene ningún pedido que se pueda repartir hoy» sobre doce
      // tarjetas, sin decir cuáles ni por qué, es el aviso que hace que el
      // logístico deje de fiarse del tablero (tablero.md §5.2). El servidor los
      // manda en `descartados`; si esta capa se queda sólo con la frase, esa
      // lista se pierde entera y nadie lo nota.
      final columna = await conUnaColumnaPuesta();
      contesta = (p) async => RespuestaFalsa(409, const <String, Object?>{
        'error': 'La columna no tiene ningún pedido que se pueda repartir hoy',
        'descartados': <Object?>[
          <String, Object?>{
            'pedidoId': 'p1',
            'operationNumber': 'F-001',
            'customerName': 'TCP OSNIER',
            'motivo': 'ya se entregó',
          },
          <String, Object?>{
            'pedidoId': 'p2',
            'customerName': 'Ana',
            'motivo': 'sin coordenadas de entrega',
          },
        ],
      });

      await expectLater(
        () => enLaWeb.armarRuta(
          columnaId: columna,
          origen: origen,
          sucursalId: sucursalStg,
        ),
        throwsA(
          isA<RechazoDelTablero>().having(
            (r) => r.detalles,
            'detalles',
            ['F-001 · TCP OSNIER: ya se entregó', 'p2 · Ana: sin coordenadas de entrega'],
          ),
        ),
      );
    });

    test('dijo que sí y no dijo cuál: no se inventa un id', () async {
      final columna = await conUnaColumnaPuesta();
      contesta = (p) async => RespuestaFalsa(201, const <String, Object?>{});

      await expectLater(
        () => enLaWeb.armarRuta(
          columnaId: columna,
          origen: origen,
          sucursalId: sucursalStg,
        ),
        throwsA(
          isA<RechazoDelTablero>().having(
            (r) => r.mensaje,
            'mensaje',
            contains('sin su identificador'),
          ),
        ),
      );
      expect(await base.select(base.routes).get(), isEmpty);
      expect(await cuantasColocaciones(), 2);
    });
  });

  // ---------------------------------------------------------------------------
  group('vaciar, mover todo y borrar la zona', () {
    late String vista;
    late String centro;

    setUp(() async {
      vista = await enLaWeb.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Vista',
      );
      centro = await enLaWeb.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Centro',
      );
      await enLaWeb.colocar(pedidoId: 'p1', columnaId: vista);
      await enLaWeb.colocar(pedidoId: 'p2', columnaId: vista);
      servidor.vistas.clear();
    });

    test('vaciar: un DELETE por tarjeta y la zona se queda', () async {
      expect(await enLaWeb.vaciarColumna(vista), 2);
      expect(servidor.vistas.map((p) => p.ruta).toList(), [
        '/board/placements/p1',
        '/board/placements/p2',
      ]);
      expect(servidor.vistas.every((p) => p.metodo == 'DELETE'), isTrue);
      expect(await cuantasColocaciones(), 0);
      expect((await consultas.columnas(sucursalStg)).length, 2);
      expect(await cuantosApuntes(), 0);
    });

    test('vaciar rechazado: NINGUNA tarjeta se cae', () async {
      contesta = (p) async => RespuestaFalsa(409, const <String, Object?>{
        'error': 'Ese pedido ya está en una ruta',
      });

      await expectLater(
        () => enLaWeb.vaciarColumna(vista),
        throwsA(isA<RechazoDelTablero>()),
      );
      // A MEDIAS NO VALE: el primer DELETE puede haber salido, pero lo que se
      // pinta es todo o nada. La transacción entera se deshace.
      expect(await cuantasColocaciones(), 2);
    });

    test('mover todo a otra zona: un PUT por tarjeta, detrás de lo que haya',
        () async {
      expect(await enLaWeb.moverTodo(vista, centro), 2);
      expect(servidor.vistas.length, 2);
      expect(servidor.vistas.first.cuerpo, {
        'columnaId': centro,
        'posicion': 1,
      });
      expect(servidor.vistas[1].cuerpo, {'columnaId': centro, 'posicion': 2});

      final columnas = await consultas.columnas(sucursalStg);
      expect(columnas.firstWhere((c) => c.id == vista).pedidos, 0);
      expect(columnas.firstWhere((c) => c.id == centro).pedidos, 2);
    });

    test('borrar con tarjetas dentro y sin decir qué hacer: no sale ni una '
        'petición', () async {
      // La guarda es de aquí y se comprueba ANTES de tocar la red: «"Vista"
      // tiene 2 pedidos puestos» se puede decir sin preguntarle a nadie.
      await expectLater(
        () => enLaWeb.borrarColumna(vista),
        throwsA(
          isA<RechazoDelTablero>()
              .having((r) => r.mensaje, 'mensaje', contains('Vista'))
              .having((r) => r.pedidos, 'pedidos', 2),
        ),
      );
      expect(servidor.vistas, isEmpty);
      expect((await consultas.columnas(sucursalStg)).length, 2);
    });

    test('borrar mandando las tarjetas a otra zona: PUTs y DELETE, en ese '
        'orden', () async {
      await enLaWeb.borrarColumna(vista, destinoId: centro);

      expect(servidor.vistas.map((p) => p.metodo).toList(), [
        'PUT',
        'PUT',
        'DELETE',
      ]);
      expect(servidor.vistas.last.ruta, '/board/columns/$vista?destino=$centro');
      final columnas = await consultas.columnas(sucursalStg);
      expect(columnas.map((c) => c.id).toList(), [centro]);
      expect(columnas.single.pedidos, 2);
    });

    test('borrar rechazado: la zona sigue ahí', () async {
      contesta = (p) async {
        if (p.metodo != 'DELETE') {
          return RespuestaFalsa(200, const <String, Object?>{});
        }
        return RespuestaFalsa(409, const <String, Object?>{
          'error': '«Vista» tiene 2 pedidos puestos',
          'pedidos': 2,
        });
      };

      await expectLater(
        () => enLaWeb.borrarColumna(vista, vaciar: true),
        throwsA(
          isA<RechazoDelTablero>()
              .having(
                (r) => r.mensaje,
                'mensaje',
                '«Vista» tiene 2 pedidos puestos',
              )
              // El número viaja aparte del texto: es lo que decide si hay que
              // vaciar dos tarjetas o mover ochenta.
              .having((r) => r.pedidos, 'pedidos', 2),
        ),
      );
      expect((await consultas.columnas(sucursalStg)).length, 2);
    });
  });

  // ---------------------------------------------------------------------------
  group('la marca de «esto no está arriba» NO se pone en la web', () {
    /// Lo que el ciclo hace ANTES de subir: buscar lo que está aquí y no arriba
    /// y volver a encolarlo (`nucleo/sincro/huerfanos.dart`).
    Future<int> loQueElCicloVolveriaAEncolar() =>
        Huerfanos(base).volverAEncolar(ColaDeSalida(base));

    test('en la web el rescatador no encuentra NADA que reencolar', () async {
      final columna = await enLaWeb.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Vista',
      );
      await enLaWeb.colocar(pedidoId: 'p1', columnaId: columna);
      await enLaWeb.renombrarColumna(columna, 'Vista Alegre');
      await enLaWeb.elegirCamion(columna, null);
      await enLaWeb.reordenarColumnas(sucursalStg, [columna]);
      servidor.vistas.clear();

      // SI ESTO DA >0, el fallo vuelve entero por la espalda: la cola se llena,
      // el ciclo pide `POST /sync/aparato` y se come su 401 otra vez. La zona y
      // la tarjeta ESTÁN arriba — el servidor las aceptó antes de que se
      // escribieran aquí—, así que no hay nada huérfano.
      expect(await loQueElCicloVolveriaAEncolar(), 0);
      expect(await cuantosApuntes(), 0);
      expect(servidor.vistas, isEmpty);
    });

    test('en la APK sí: ahí la marca es verdad y es lo que salva el día',
        () async {
      final columna = await enElAparato.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Vista',
      );
      await enElAparato.colocar(pedidoId: 'p1', columnaId: columna);
      // Se descarta la cola a mano, que es el caso de la zona «Vista» del
      // 16/09/2026: las filas quedan sin nadie que las suba.
      await base.delete(base.apuntes).go();

      expect(
        await loQueElCicloVolveriaAEncolar(),
        greaterThan(0),
        reason:
            'el trabajo sin conexión no se pierde por ninguna circunstancia: '
            'es la única regla que no se negocia en el tablero',
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('EL OTRO MUNDO, intacto', () {
    test('en la APK no sale NI UNA petición y todo queda en la cola', () async {
      final columna = await enElAparato.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Vista',
      );
      await enElAparato.colocar(pedidoId: 'p1', columnaId: columna);
      await enElAparato.quitar('p1');

      expect(
        servidor.vistas,
        isEmpty,
        reason:
            'el tablero se prepara por la tarde, que es cuando no hay señal: '
            'una pantalla que espera al servidor para mover la tarjeta no se '
            'puede usar a la hora a la que se usa',
      );
      expect(await cuantosApuntes(), 3);
      final apuntes = await cola.pendientes().first;
      expect(apuntes.map((a) => a.metodo).toList(), ['POST', 'PUT', 'DELETE']);
    });
  });
}
