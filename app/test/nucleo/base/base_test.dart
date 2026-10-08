import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  late BaseLocal base;

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  test('la base arranca en el esquema 6 con todas las tablas', () async {
    expect(base.schemaVersion, 6);
    final nombres = base.allTables.map((t) => t.actualTableName).toSet();
    expect(
      nombres,
      containsAll(<String>[
        'orders',
        'order_items',
        'routes',
        'customers',
        'products',
        'vehicles',
        'vehicle_types',
        'branches',
        'warehouses',
        'settings',
        'apuntes',
        'equivalencias',
        'frescura',
        'preferencias',
      ]),
    );
    // `currencies` SE QUITO ENTERA (esquema 2). Era la tabla que leia el
    // selector de moneda y no la llenaba nadie: no esta en `Colecciones`, la
    // bajada no la trae y el servidor no la sirve, asi que la barra se quedaba
    // en la pastilla ambar para siempre. Que no vuelva: con ella aqui, el
    // selector volveria a mirar una tasa global de las que la casa prohibe.
    expect(nombres, isNot(contains('currencies')));
  });

  test(
    'la tasa de cambio es UNA COLUMNA DE LA SUCURSAL, no de los ajustes',
    () async {
      // Donde vive la tasa es la decision de fondo de todo esto. `settings` es
      // GLOBAL —lo dice la propia API— y una sola tasa para las ocho sucursales es
      // como Granma acabo enseñando los 685 de La Habana como si fueran suyos.
      final columnas = base.branches.$columns.map((c) => c.name).toSet();
      expect(
        columnas,
        containsAll(<String>[
          'cup_rate',
          'cup_rate_fuente',
          'cup_rate_traido_at',
          'cup_rate_fresca',
        ]),
      );
      // Y NACEN NULAS, sin ningun 320 por defecto: con un valor por defecto, ver un
      // numero no demostraria que nadie haya puesto la tasa.
      for (final c in base.branches.$columns.where(
        (c) => c.name.startsWith('cup_rate'),
      )) {
        expect(
          c.$nullable,
          isTrue,
          reason: '${c.name} tiene que poder ser nula',
        );
        expect(
          c.defaultValue,
          isNull,
          reason: '${c.name} no puede traer un valor por defecto',
        );
      }
    },
  );

  test('los nombres de columna son los del servidor', () async {
    // Si esto cambia, la bajada deja de ser un `insertOnConflictUpdate` y hace
    // falta un traductor en medio.
    final columnas = base.orders.$columns.map((c) => c.name).toSet();
    expect(
      columnas,
      containsAll(<String>[
        'route_id',
        'ultima_ruta_id',
        'pedido_costo',
        'factura_estado',
        'end_lat',
        'order_date',
        'pedido_updated_at',
      ]),
    );
  });

  test('`quitados` borra de verdad', () async {
    for (final id in ['p1', 'p2', 'p3']) {
      await base
          .into(base.orders)
          .insert(
            OrdersCompanion.insert(id: id, customerName: 'C', address: 'D'),
          );
    }
    // Sin esto la lista local sólo crece: un pedido archivado se queda en el
    // aparato para siempre.
    await (base.delete(
      base.orders,
    )..where((o) => o.id.isIn(['p1', 'p3']))).go();

    final quedan = await base.select(base.orders).get();
    expect(quedan.map((o) => o.id), ['p2']);
  });

  test(
    'cerrar sesion borra el dominio y NO toca la cola (regla 8, caso I7)',
    () async {
      final cola = ColaDeSalida(base);
      await base
          .into(base.orders)
          .insert(
            OrdersCompanion.insert(
              id: 'p1',
              customerName: 'Cliente',
              address: 'Calle con su número',
            ),
          );
      await base
          .into(base.customers)
          .insert(
            CustomersCompanion.insert(
              id: 'c1',
              name: 'Cliente',
              lat: 19.83,
              lng: -75.82,
            ),
          );
      await base
          .into(base.frescura)
          .insert(
            FrescuraCompanion.insert(
              coleccion: Colecciones.pedidos,
              hasta: const Value('2026-09-14T11:02:31.481Z'),
            ),
          );
      final clave = await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes',
        cuerpo: const {},
      );

      await base.borrarTodoLoDelDominio();

      // Los clientes con sus direcciones se van: el telefono puede cambiar de
      // manos.
      expect(await base.select(base.orders).get(), isEmpty);
      expect(await base.select(base.customers).get(), isEmpty);
      expect(await base.select(base.frescura).get(), isEmpty);
      // El trabajo sin subir, NO. Quien decide es la persona.
      expect(await cola.porClave(clave), isNotNull);
      expect(await base.cuantosPendientes(), 1);
    },
  );

  test('las fechas van y vuelven con su hora, no redondeadas', () async {
    // Se guardan como texto ISO-8601 a proposito: un entero de segundos pierde
    // los milisegundos y la zona.
    final momento = DateTime(2026, 9, 14, 16, 4, 22, 481);
    await base
        .into(base.apuntes)
        .insert(
          ApuntesCompanion.insert(
            clave: 'k1',
            hechoAt: momento,
            metodo: 'POST',
            ruta: '/x',
            cuerpo: '{}',
          ),
        );
    final fila = await base.select(base.apuntes).getSingle();
    expect(fila.hechoAt, momento);
  });
}
