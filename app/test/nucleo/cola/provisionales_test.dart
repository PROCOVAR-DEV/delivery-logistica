import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/cola/provisionales.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';

void main() {
  late BaseLocal base;
  late RelojFalso reloj;
  late ColaDeSalida cola;

  setUp(() {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime(2026, 9, 14, 10));
    cola = ColaDeSalida(base, reloj: reloj.leer);
  });

  tearDown(() => base.close());

  test('un id provisional se reconoce de un vistazo', () {
    final id = Provisionales.nuevoId();
    expect(id, startsWith('local-'));
    expect(id.length, 'local-'.length + 8);
    expect(Provisionales.esProvisional(id), isTrue);
    expect(Provisionales.esProvisional('cm2xabc'), isFalse);
    expect(Provisionales.esProvisional(null), isFalse);
  });

  test(
    'el dia entero sin red: armar, cerrar, y que el cierre NO se pierda',
    () async {
      // ── Sin red, por la manana ──────────────────────────────────────────
      // El logistico arma una ruta. No hay id: se inventa uno.
      const provisional = 'local-9f3a2b7c';

      await base
          .into(base.routes)
          .insert(
            RoutesCompanion.insert(
              id: provisional,
              routeCode: const Value('PAL-260914-01'),
              status: const Value('planned'),
            ),
          );
      // Y los ocho pedidos quedan ocupados por esa ruta.
      for (var i = 1; i <= 8; i++) {
        await base
            .into(base.orders)
            .insert(
              OrdersCompanion.insert(
                id: 'p$i',
                customerName: 'Cliente $i',
                address: 'Calle $i',
                routeId: const Value(provisional),
                ultimaRutaId: const Value(provisional),
              ),
            );
      }

      final claveArmado = await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes',
        cuerpo: const {
          'routeCode': 'PAL-260914-01',
          'pedidos': ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'],
        },
        provisional: provisional,
      );

      // ── Sin red, por la tarde ───────────────────────────────────────────
      // El camion vuelve y se cierra parada por parada. La ruta sigue sin tener
      // otro nombre que el `local-…`.
      final claveCierre = await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes/$provisional/results',
        cuerpo: const {
          'rutaId': provisional,
          'paradas': [
            {'pedido': 'p1', 'resultado': 'entregado'},
            {'pedido': 'p2', 'resultado': 'devuelto', 'nota': 'cerrado'},
          ],
        },
      );

      // ── Con red, por la noche ───────────────────────────────────────────
      // Sube el primero y el servidor devuelve el id de verdad.
      await cola.resolver(
        claveArmado,
        const ResultadoApunte(
          estado: EstadoResultado.aplicado,
          id: 'cm2xreal000',
        ),
      );

      // Y AQUI ESTA LO QUE SE COMPRUEBA: el cierre que quedaba detras ya no
      // menciona el `local-…` ni en la ruta ni en el cuerpo. Sin esto se iria a
      // `/api/routes/local-9f3a2b7c/results`, que no existe en ningun sitio, y
      // el dia se perderia justo despues de haberlo subido (caso S4).
      final cierre = await cola.porClave(claveCierre);
      expect(cierre!.ruta, '/api/routes/cm2xreal000/results');
      expect(cierre.cuerpo, isNot(contains('local-')));
      expect(cierre.cuerpo, contains('cm2xreal000'));
      expect(cierre.estado, EstadoApunte.pendiente);

      // Las filas locales tambien: la pantalla deja de ensenar el `local-…` sin
      // esperar a la proxima bajada.
      expect(
        await (base.select(
          base.routes,
        )..where((r) => r.id.equals(provisional))).getSingleOrNull(),
        isNull,
      );
      final ruta = await (base.select(
        base.routes,
      )..where((r) => r.id.equals('cm2xreal000'))).getSingle();
      expect(ruta.routeCode, 'PAL-260914-01');

      final pedidos = await base.select(base.orders).get();
      expect(pedidos, hasLength(8));
      expect(pedidos.every((p) => p.routeId == 'cm2xreal000'), isTrue);
      expect(pedidos.every((p) => p.ultimaRutaId == 'cm2xreal000'), isTrue);

      // Y queda el rastro.
      expect(await Provisionales(base).real(provisional), 'cm2xreal000');
    },
  );

  test('un apunte ya resuelto NO se reescribe', () async {
    // Reescribir lo ya mandado seria falsear la unica prueba que queda de lo que
    // de verdad salio del aparato.
    const provisional = 'local-aabbccdd';
    final viejo = await cola.encolar(
      metodo: 'POST',
      ruta: '/api/routes/$provisional/results',
      cuerpo: const {'rutaId': provisional},
    );
    await cola.resolver(
      viejo,
      const ResultadoApunte(
        estado: EstadoResultado.rechazado,
        motivo: 'la ruta no existe',
      ),
    );

    await Provisionales(base).sustituir(provisional, 'cm2xreal111');

    final apunte = await cola.porClave(viejo);
    expect(apunte!.ruta, contains(provisional));
    expect(apunte.motivo, 'la ruta no existe');
  });

  test('sustituir un vehiculo creado sin red', () async {
    const provisional = 'local-11223344';
    await base
        .into(base.vehicles)
        .insert(VehiclesCompanion.insert(id: provisional, name: 'Camión 3'));
    await Provisionales(base).sustituir(provisional, 'veh-real');

    final vehiculo = await base.select(base.vehicles).getSingle();
    expect(vehiculo.id, 'veh-real');
  });

  test('sustituir por si mismo no hace nada', () async {
    await Provisionales(base).sustituir('local-x', 'local-x');
    expect(await base.select(base.equivalencias).get(), isEmpty);
  });
}
