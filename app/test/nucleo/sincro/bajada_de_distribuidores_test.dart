import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/sincro/bajada.dart';
import 'package:reparto/nucleo/sincro/recuento.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

/// LOS DISTRIBUIDORES BAJAN CON EL DIA (issue 7 de Amado, 14/10/2026).
///
/// Se eligen SIN conexion al crear la ruta, asi que viajan en `GET /api/sync/cambios` como una
/// coleccion mas: con sus `puestos`, sus `quitados` y su marca de frescura (de la que sale el
/// cartel de «no bajo»). Y un caso que ninguna otra coleccion tiene: el aparato que YA sincronizo
/// con la version anterior avanzo su marca con ellos ya creados, y la bajada por diferencias no
/// vuelve a traerlos nunca — por eso se piden ENTEROS la primera vez (`completas`).
void main() {
  late BaseLocal base;
  late RegistroDeFrescura frescura;
  final ahora = DateTime(2026, 10, 14, 9);

  setUp(() {
    base = baseDePrueba();
    frescura = RegistroDeFrescura(base, reloj: () => ahora);
  });
  tearDown(() => base.close());

  Map<String, Object?> conjunto({
    List<Object?> puestos = const [],
    List<String> quitados = const [],
  }) => <String, Object?>{'puestos': puestos, 'quitados': quitados};

  Map<String, Object?> unDistribuidor(
    String id,
    String nombre, {
    bool? activo,
    String sucursal = 'suc-stg',
  }) => <String, Object?>{
    'id': id,
    'nombre': nombre,
    'activo': ?activo,
    'branchId': sucursal,
    'updatedAt': '2026-10-14T08:00:00.000Z',
  };

  /// Un servidor que contesta lo que se le diga y apunta cada peticion.
  Bajada contra(
    List<Map<String, Object?>> cambiosPorVuelta,
    List<PeticionVista> peticiones,
  ) {
    var vuelta = 0;
    return Bajada(
      cliente: clienteFalso((p) async {
        peticiones.add(p);
        final cambios =
            cambiosPorVuelta[vuelta.clamp(0, cambiosPorVuelta.length - 1)];
        vuelta++;
        return RespuestaFalsa(200, <String, Object?>{
          'hasta': '2026-10-14T0$vuelta:00:00.000Z',
          'completa': vuelta == 1,
          'truncado': false,
          'cambios': cambios,
        });
      }),
      base: base,
      frescura: frescura,
      reloj: () => ahora,
    );
  }

  test('la bajada escribe los distribuidores y marca la coleccion', () async {
    final peticiones = <PeticionVista>[];
    await contra([
      <String, Object?>{
        'orders': conjunto(),
        'distribuidores': conjunto(
          puestos: [
            unDistribuidor('d-1', 'Juan Pérez'),
            unDistribuidor('d-2', 'Pedro Gil', activo: false),
          ],
        ),
      },
    ], peticiones).ciclo();

    final filas = await base.select(base.distribuidores).get();
    expect(filas.map((d) => (d.id, d.nombre, d.activo, d.branchId)), [
      ('d-1', 'Juan Pérez', true, 'suc-stg'),
      ('d-2', 'Pedro Gil', false, 'suc-stg'),
    ], reason: 'el retirado baja como retirado, y uno sin `activo` es ACTIVO');
    expect(
      await frescura.seDescargo(Colecciones.distribuidores),
      isTrue,
      reason: 'sin marca, la pantalla dice «sin descargar» con los datos ya puestos',
    );
  });

  test('`quitados` borra al distribuidor, y solo a ese', () async {
    await base.into(base.distribuidores).insert(
      DistribuidoresCompanion.insert(id: 'd-1', nombre: 'Juan Pérez'),
    );
    await base.into(base.distribuidores).insert(
      DistribuidoresCompanion.insert(id: 'd-2', nombre: 'María López'),
    );
    await contra([
      <String, Object?>{
        'orders': conjunto(),
        'distribuidores': conjunto(quitados: ['d-1']),
      },
    ], []).ciclo();

    expect(
      (await base.select(base.distribuidores).get()).map((d) => d.id),
      ['d-2'],
      reason: 'un borrado en el servidor tiene que desaparecer del aparato, o se '
          'seguiria ofreciendo a quien ya no existe',
    );
  });

  test('la ruta bajada lleva su distribuidor, y una vieja baja sin el', () async {
    await contra([
      <String, Object?>{
        'orders': conjunto(),
        'routes': conjunto(
          puestos: [
            <String, Object?>{
              'id': 'r-1',
              'routeCode': 'RT-1',
              'status': 'planned',
              'distribuidorId': 'd-1',
            },
            <String, Object?>{'id': 'r-2', 'routeCode': 'RT-2', 'status': 'planned'},
          ],
        ),
      },
    ], []).ciclo();

    final rutas = {
      for (final r in await base.select(base.routes).get()) r.id: r.distribuidorId,
    };
    expect(rutas, {'r-1': 'd-1', 'r-2': null});
  });

  group('el aparato que ya habia sincronizado', () {
    // Ya hizo tambien las rebajadas de una vez (frescura.dart): si no, la primera
    // peticion iria sin `desde` y no habria nada que pedir `completas`.
    Future<void> yaSincronizoAyer() async {
      await frescura.rebajarLosPedidosUnaVez();
      await frescura.rebajarLasRutasUnaVez();
      await frescura.rebajarLosPedidosPorSuAlmacen();
      // La flota (issue 14) tiene sus pruebas en `bajada_de_la_flota_test.dart`.
      await frescura.marcar(
        Colecciones.tiposDeVehiculo,
        hasta: null,
        completa: true,
      );
      await frescura.marcar(
        RegistroDeFrescura.yaBajadosLosVehiculosConSuFicha,
        hasta: null,
      );
      await frescura.marcar(
        Colecciones.pedidos,
        hasta: '2026-10-13T08:00:00.000Z',
        completa: true,
      );
    }

    // Una api ANTERIOR a la 00019 no manda `distribuidores`. EN PAREJA con el de arriba
    // (con la clave, se marca y no se vuelve a pedir): sin la clave NO se marca, y el
    // ciclo siguiente la sigue pidiendo entera.
    test('si la api no manda la coleccion, no se da por bajada y se sigue pidiendo', () async {
      await yaSincronizoAyer();
      final peticiones = <PeticionVista>[];
      final bajada = contra([
        <String, Object?>{'orders': conjunto()},
        <String, Object?>{'orders': conjunto()},
      ], peticiones);

      await bajada.ciclo();
      expect(await frescura.seDescargo(Colecciones.distribuidores), isFalse,
          reason: 'no vino: marcarla es tirar la lista para siempre');
      await bajada.ciclo();
      expect(peticiones.last.parametros['completas'], Colecciones.distribuidores,
          reason: 'cuando la api se actualice, los tiene que pedir enteros');
    });

    test('pide los distribuidores ENTEROS (completas) hasta que los baja', () async {
      await yaSincronizoAyer();
      final peticiones = <PeticionVista>[];
      final bajada = contra([
        <String, Object?>{
          'orders': conjunto(),
          'distribuidores': conjunto(puestos: [unDistribuidor('d-1', 'Juan Pérez')]),
        },
        <String, Object?>{'orders': conjunto(), 'distribuidores': conjunto()},
      ], peticiones);

      await bajada.ciclo();
      expect(
        peticiones.first.parametros['completas'],
        Colecciones.distribuidores,
        reason: 'con la marca de ayer, sin esto la lista no vuelve a salir NUNCA: lo '
            'creado antes de ayer no «cambio desde ayer»',
      );
      expect(peticiones.first.parametros['desde'], '2026-10-13T08:00:00.000Z',
          reason: 'lo demas sigue por diferencias: pedir ENTERO lo que pesa es la carga inicial');

      // La PAREJA: ya bajados, el siguiente ciclo no los vuelve a pedir enteros.
      await bajada.ciclo();
      expect(
        peticiones.last.parametros.containsKey('completas'),
        isFalse,
        reason: 'un aparato al dia no puede pedir la lista entera en cada ciclo',
      );
    });

    test('un aparato NUEVO (sin marca) no pide nada especial: la primera tanda ya es entera', () async {
      final peticiones = <PeticionVista>[];
      await contra([
        <String, Object?>{'orders': conjunto(), 'distribuidores': conjunto()},
      ], peticiones).ciclo();
      expect(peticiones.single.parametros.containsKey('completas'), isFalse);
      expect(peticiones.single.parametros.containsKey('desde'), isFalse);
    });
  });

  test('sin bajar, el cartel de «no bajo» sale; bajados, no', () async {
    Future<List<String>> faltan() async {
      final recuento = await Recontador(base, frescura).ahora();
      return [for (final f in Faltas.de(recuento)) f.coleccion];
    }

    expect(await faltan(), contains(Colecciones.distribuidores),
        reason: 'un aparato que nunca los bajo tiene que decirlo, y decir que se rompe');

    await contra([
      <String, Object?>{'orders': conjunto(), 'distribuidores': conjunto()},
    ], []).ciclo();

    expect(await faltan(), isNot(contains(Colecciones.distribuidores)),
        reason: 'cero distribuidores es una respuesta legitima: una sucursal puede no tener ninguno');
    expect(Faltas.queSeRompe(Colecciones.distribuidores),
        contains('quién reparte'));
  });
}
