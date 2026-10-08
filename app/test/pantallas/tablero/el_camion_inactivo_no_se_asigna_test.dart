// UN CAMION INACTIVO NO SE ASIGNA A UNA ZONA NI SALE EN UNA RUTA — 1.0.29.
//
// Amado, 07/10/2026 (incidencia 4): un camion con rutas no se borra, se
// INACTIVA, y desde ese momento no se asigna a una ruta. El servidor lo rechaza
// con el literal de `docs/armado-rechazado.casos.json` (`camion-inactivo`) y el
// aparato lo dice ANTES de escribir nada, para que en la APK el «no» no llegue
// horas despues a la bandeja de rechazos: `RepositorioTablero.elegirCamion` (al
// ponerlo de «Camion previsto») y `armarRuta` (la zona ya lo tenia puesto
// cuando se dio de baja).
//
// Esas dos guardas sobrevivian a la mutacion (`if (false)`): ninguna prueba las
// pisaba. Van EN PAREJA: el inactivo rechaza con el literal exacto, y el ACTIVO
// no rechaza (sin esa mitad, rechazar siempre dejaria la primera en verde).
// El literal se lee del JSON compartido con el servidor (§3-bis) y ademas se
// compara con el texto escrito aqui, porque un JSON que cambiara en silencio
// arrastraria a esta prueba con el.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo.dart';

const _rutaDeLosCasos = '../docs/armado-rechazado.casos.json';

/// El literal del servidor para un camion inactivo, leido del JSON compartido.
String _literalDelServidor() {
  final raiz =
      jsonDecode(File(_rutaDeLosCasos).readAsStringSync())
          as Map<String, dynamic>;
  final fijos =
      ((raiz['mensajesDelServidor'] as Map<String, dynamic>)['literalesFijos']
              as List<dynamic>)
          .cast<Map<String, dynamic>>();
  return fijos.singleWhere((c) => c['nombre'] == 'camion-inactivo')['literal']
      as String;
}

void main() {
  late BaseLocal base;
  late ConsultasTablero consultas;
  late ColaDeSalida cola;
  late RepositorioTablero repo;
  late AlmacenOrigen origen;
  late String centro;

  const textoDelServidor =
      'El vehículo está inactivo y no se puede asignar a una ruta.';

  setUp(() async {
    base = baseDePrueba();
    consultas = ConsultasTablero(base);
    cola = ColaDeSalida(base);
    repo = RepositorioTablero(base, cola);
    // La base nace VACIA de camiones y de pedidos: se siembran dentro de cada
    // prueba, despues.
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    origen = await consultas.almacenDe(sucursalStg);
    centro = await repo.crearColumna(sucursalId: sucursalStg, nombre: 'Centro');
  });

  tearDown(() => base.close());

  Future<String?> camionPrevisto() async {
    final fila = await base
        .customSelect(
          'SELECT vehicle_id FROM board_columns WHERE id = ?1',
          variables: [Variable<String>(centro)],
        )
        .getSingle();
    return fila.readNullable<String>('vehicle_id');
  }

  Future<int> apuntes() async => (await cola.lote()).length;

  test('el literal del JSON compartido es el del servidor, letra por letra', () {
    expect(_literalDelServidor(), textoDelServidor);
  });

  group('elegirCamion', () {
    test('un camion INACTIVO se rechaza con el literal del servidor y no se guarda nada', () async {
      await sembrarCamion(base, id: 'v-baja', activo: false);
      final antes = await apuntes();

      await expectLater(
        repo.elegirCamion(centro, 'v-baja'),
        throwsA(
          isA<RechazoDelTablero>().having(
            (e) => e.mensaje,
            'mensaje',
            textoDelServidor,
          ),
        ),
      );

      expect(await camionPrevisto(), isNull, reason: 'la zona no lo toma');
      expect(
        await apuntes(),
        antes,
        reason:
            'si el apunte se encola, el «no» llega horas despues a la bandeja '
            'de rechazos de la APK',
      );
    });

    test('en pareja: el mismo camion ACTIVO se asigna', () async {
      await sembrarCamion(base, id: 'v-ok');

      await repo.elegirCamion(centro, 'v-ok');

      expect(await camionPrevisto(), 'v-ok');
    });

    test('quitar el camion (null) se puede siempre, aunque el de la zona este de baja', () async {
      await sembrarCamion(base, id: 'v1');
      await repo.elegirCamion(centro, 'v1');
      await (base.update(base.vehicles)..where((v) => v.id.equals('v1'))).write(
        const VehiclesCompanion(isActive: Value(false)),
      );

      await repo.elegirCamion(centro, null);

      expect(await camionPrevisto(), isNull);
    });
  });

  group('armarRuta', () {
    Future<void> zonaConDosPedidos() async {
      await sembrarPedido(base, id: 'p1');
      await sembrarPedido(base, id: 'p2', aGrados: 0.02);
      await repo.colocar(pedidoId: 'p1', columnaId: centro);
      await repo.colocar(pedidoId: 'p2', columnaId: centro);
    }

    test('la zona cuyo camion se dio de baja NO arma, con el literal del servidor', () async {
      await sembrarCamion(base, id: 'v1');
      await repo.elegirCamion(centro, 'v1');
      await zonaConDosPedidos();
      // La zona lo puso cuando estaba activo; despues alguien lo inactivo.
      await (base.update(base.vehicles)..where((v) => v.id.equals('v1'))).write(
        const VehiclesCompanion(isActive: Value(false)),
      );
      final antes = await apuntes();

      await expectLater(
        repo.armarRuta(
          columnaId: centro,
          origen: origen,
          sucursalId: sucursalStg,
        ),
        throwsA(
          isA<RechazoDelTablero>().having(
            (e) => e.mensaje,
            'mensaje',
            textoDelServidor,
          ),
        ),
      );

      expect(await base.select(base.routes).get(), isEmpty);
      expect((await consultas.colocados(sucursalStg, origen)).length, 2);
      expect(await apuntes(), antes, reason: 'nada sale a la cola');
    });

    test('en pareja: la misma zona con el camion ACTIVO arma su ruta', () async {
      await sembrarCamion(base, id: 'v1');
      await repo.elegirCamion(centro, 'v1');
      await zonaConDosPedidos();

      final rutaId = await repo.armarRuta(
        columnaId: centro,
        origen: origen,
        sucursalId: sucursalStg,
      );

      final ruta = await (base.select(
        base.routes,
      )..where((r) => r.id.equals(rutaId))).getSingle();
      expect(ruta.vehicleId, 'v1');
    });

    test('un camion en el TALLER no rechaza: aviso, no bloqueo', () async {
      // La mitad que fija la decision de Jose del 28/09/2026: solo el INACTIVO
      // se niega. Rechazar `maintenance` dejaria sin armar a una sucursal con un
      // solo camion olvidado en el taller.
      await sembrarCamion(base, id: 'v1', estado: 'maintenance');
      await repo.elegirCamion(centro, 'v1');
      await zonaConDosPedidos();

      final rutaId = await repo.armarRuta(
        columnaId: centro,
        origen: origen,
        sucursalId: sucursalStg,
      );

      expect(rutaId, startsWith('local-'));
    });
  });
}
