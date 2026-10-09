// SUBIR EL ESQUEMA NO PUEDE LLEVARSE LA COLA SIN SUBIR.
//
// Esta base no es la de un servidor: vive en el teléfono de alguien y ahí dentro está **el
// trabajo del día que todavía no ha subido**. Una migración que recrea tablas, o que falla
// a medias y deja la base sin abrir, es lo único que esta aplicación no puede permitirse
// —lo dice `BaseLocal.schemaVersion` y por eso se toca tan poco—.
//
// El 26/09/2026 se subió a la 3 para añadir `orders.items_origen`, que dice si los
// renglones y el peso son los del pedido o los de la FACTURA. Es un `ALTER TABLE ADD
// COLUMN`, la operación más barata que hay, y aun así se prueba: lo barato es el cambio,
// no la consecuencia de equivocarse.
//
// El 09/10/2026 se subió a la 7 (la bandeja de revisión: cuatro columnas nuevas en `apuntes`, la
// tabla de la cola sin subir): ver el final de este fichero.
//
// El 07/10/2026 se subió a la 6: la 5 quita `orders.vehicle_id` (el camión de un pedido es el
// de su ruta, y la copia se desactualizaba) con `DROP COLUMN`, y la 6 añade
// `vehicles.is_active`. Es la primera migración que QUITA algo y por eso la prueba mira dos
// cosas más: que la columna ya no está y que una flota que ya existía queda ACTIVA, no
// inactiva —un camión que desaparece de los selectores por una migración es peor que
// el fallo que se vino a arreglar—.
//
// LA FORMA: se abre una base **en la versión vieja**, se le mete un apunte en la cola y un
// pedido, se cierra, y se vuelve a abrir con la versión de ahora. Lo que se comprueba es
// que siguen ahí. Crear directamente en la 3 no probaría nada: ése es el camino del
// aparato nuevo, que no tiene nada que perder.

import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';

void main() {
  test('el trabajo sin subir sobrevive al salto de esquema', () async {
    // Un fichero de verdad, no memoria: lo que se prueba es que la base se
    // **reabre** con el esquema nuevo, y una base en memoria nace otra vez.
    final fichero = await _ficheroDePrueba();
    addTearDown(() async {
      if (fichero.existsSync()) await fichero.delete();
    });

    // --- El aparato de ayer, en la versión 2 -------------------------------
    //
    // Se monta con el esquema DE VERDAD y después se le quita la columna nueva y
    // se le baja el `user_version` a mano. Declarar a mano una copia del
    // esquema viejo era peor: lo que se probaría entonces es esa copia, no la
    // base que llevan los teléfonos.
    final ayer = BaseLocal.con(NativeDatabase(fichero));
    await ayer.into(ayer.apuntes).insert(
      ApuntesCompanion.insert(
        clave: '01J8-la-zona-de-ayer',
        hechoAt: DateTime(2026, 9, 26, 9),
        metodo: 'POST',
        ruta: '/api/board/columns',
        cuerpo: '{"nombre":"Vista"}',
      ),
    );
    await ayer.customStatement(
      'INSERT INTO orders (id, customer_name, address, weight, archivado) '
      "VALUES ('ped-1', 'Bodega La Esquina', 'Calle 4', 120.5, 0)",
    );
    await ayer.customStatement('ALTER TABLE orders DROP COLUMN items_origen');
    // Y las del esquema 4, o la migracion intenta anadirlas sobre las que ya
    // estan: la base se monta con el esquema DE VERDAD y despues se le quitan
    // las columnas nuevas, que es lo que la deja como la de un aparato que
    // lleva dias en la calle.
    await ayer.customStatement('ALTER TABLE order_items DROP COLUMN peso_kg');
    await ayer.customStatement(
      'ALTER TABLE order_items DROP COLUMN peso_linea_kg',
    );
    // El esquema 4 TENÍA `orders.vehicle_id` (texto simple, sin índice ni clave
    // ajena: por eso `DROP COLUMN` puede quitarla) y NO tenía `vehicles.is_active`.
    await ayer.customStatement('ALTER TABLE orders ADD COLUMN vehicle_id TEXT');
    await ayer.customStatement("UPDATE orders SET vehicle_id = 'camion-viejo'");
    await ayer.customStatement('ALTER TABLE vehicles DROP COLUMN is_active');
    await ayer.customStatement(
      "INSERT INTO vehicles (id, name) VALUES ('v-1', 'Camión de ayer')",
    );
    await ayer.customStatement('PRAGMA user_version = 2');
    await ayer.close();

    // --- Y se abre con el de hoy -------------------------------------------
    final nueva = BaseLocal.con(NativeDatabase(fichero));
    addTearDown(nueva.close);

    final cola = await nueva.select(nueva.apuntes).get();
    expect(
      cola.map((a) => a.clave),
      ['01J8-la-zona-de-ayer'],
      reason:
          'la cola sin subir es el trabajo del día de una persona: una '
          'migración que se la lleve no se nota hasta que alguien la reclama',
    );

    final pedidos = await nueva.select(nueva.orders).get();
    expect(pedidos.single.customerName, 'Bodega La Esquina');
    expect(pedidos.single.weight, 120.5);

    // LA COLUMNA EXISTE, preguntándoselo a SQLite.
    //
    // Mirar sólo que el valor es nulo NO vale, y esto se descubrió mutando: con
    // el `addColumn` quitado la prueba seguía verde, porque un nulo y una
    // columna que no está se leen igual desde Dart. La que falla es ésta.
    final columnas = await nueva
        .customSelect('PRAGMA table_info(orders)')
        .get();
    expect(
      columnas.map((f) => f.read<String>('name')),
      contains('items_origen'),
      reason: 'la migración no añadió la columna y nadie se enteró',
    );

    // Y llega VACÍA, que es «no se sabe».
    expect(
      pedidos.single.itemsOrigen,
      isNull,
      reason:
          'poner «pedido» por defecto afirmaría sobre todo lo que el aparato '
          'ya tiene algo que nadie ha comprobado',
    );

    // La 5: `orders.vehicle_id` YA NO ESTÁ, y el pedido sigue entero.
    expect(
      columnas.map((f) => f.read<String>('name')),
      isNot(contains('vehicle_id')),
      reason: 'el camión de un pedido es el de su ruta: la copia se quitó',
    );

    // La 6: la columna existe y el camión que ya había queda ACTIVO.
    final deVehiculos = await nueva
        .customSelect('PRAGMA table_info(vehicles)')
        .get();
    expect(
      deVehiculos.map((f) => f.read<String>('name')),
      contains('is_active'),
    );
    final camiones = await nueva.select(nueva.vehicles).get();
    expect(camiones.single.name, 'Camión de ayer');
    expect(
      camiones.single.isActive,
      isTrue,
      reason:
          'una flota existente tiene que seguir saliendo en los selectores: '
          'inactivar es una decisión de una persona, no de una migración',
    );
  });

  // El caso más común: el teléfono que ya estaba en la 4 y sólo da los dos pasos
  // nuevos. Se prueba aparte porque `desde < 2`, `< 3` y `< 4` NO corren aquí, y el
  // fallo sería justo que la 5 o la 6 dependieran de que hubieran corrido.
  test('desde la 4: quitar vehicle_id y añadir is_active conserva la cola',
      () async {
    final fichero = await _ficheroDePrueba();
    addTearDown(() async {
      if (fichero.existsSync()) await fichero.delete();
    });

    final ayer = BaseLocal.con(NativeDatabase(fichero));
    await ayer.into(ayer.apuntes).insert(
      ApuntesCompanion.insert(
        clave: '01J8-lo-de-la-4',
        hechoAt: DateTime(2026, 10, 6, 9),
        metodo: 'POST',
        ruta: '/api/routes/r-1/results',
        cuerpo: '{"resultados":[]}',
      ),
    );
    await ayer.customStatement(
      'INSERT INTO orders (id, customer_name, address, weight, archivado) '
      "VALUES ('ped-4', 'Casa Marta', 'Calle 9', 80, 0)",
    );
    await ayer.customStatement('ALTER TABLE orders ADD COLUMN vehicle_id TEXT');
    await ayer.customStatement("UPDATE orders SET vehicle_id = 'camion-viejo'");
    await ayer.customStatement('ALTER TABLE vehicles DROP COLUMN is_active');
    await ayer.customStatement(
      "INSERT INTO vehicles (id, name) VALUES ('v-4', 'Camión de la 4')",
    );
    await ayer.customStatement('PRAGMA user_version = 4');
    await ayer.close();

    final nueva = BaseLocal.con(NativeDatabase(fichero));
    addTearDown(nueva.close);

    expect(
      (await nueva.select(nueva.apuntes).get()).map((a) => a.clave),
      ['01J8-lo-de-la-4'],
      reason: 'la cola sin subir sobrevive a un DROP COLUMN',
    );
    expect(
      (await nueva.select(nueva.orders).get()).single.customerName,
      'Casa Marta',
    );
    final columnas = await nueva
        .customSelect('PRAGMA table_info(orders)')
        .get();
    expect(
      columnas.map((f) => f.read<String>('name')),
      isNot(contains('vehicle_id')),
    );
    expect(
      (await nueva.select(nueva.vehicles).get()).single.isActive,
      isTrue,
    );
  });

  // EL FICHERO RICO, con la columna y SIN ella.
  //
  // Las dos pruebas de arriba llevan UN apunte y UN pedido. Un aparato de verdad en
  // la 4 trae una cola de varios verbos, un camión con su ruta, pedidos con
  // renglones y los índices de `beforeOpen` ya creados, y lo que se defiende es que
  // TODO eso siga ahí y que la base abra. Se prueba por duplicado, y la segunda es
  // el caso que protege la guarda de `desde < 5`: una base que YA no tiene
  // `orders.vehicle_id` (un salto interrumpido, una copia nacida con el esquema nuevo
  // y el `user_version` atrás). `DROP COLUMN` de una columna que no está LANZA, la
  // migración no termina y la base no abre: el trabajo del día, secuestrado.
  for (final conLaColumna in [true, false]) {
    test(
      'un aparato de la 4 con la cola, un camión, una ruta y un pedido con 2 '
      'renglones ${conLaColumna ? 'CON' : 'SIN'} vehicle_id: abre y no pierde nada',
      () async {
        final fichero = await _ficheroDePrueba();
        addTearDown(() async {
          if (fichero.existsSync()) await fichero.delete();
        });

        final ayer = BaseLocal.con(NativeDatabase(fichero));
        // Una cola de los tres verbos que sube la aplicación.
        for (final (clave, metodo, ruta) in const [
          ('01J8-a-post', 'POST', '/api/routes'),
          ('01J8-b-patch', 'PATCH', '/api/routes/r-1'),
          ('01J8-c-delete', 'DELETE', '/api/routes/r-1/stops/ped-1'),
        ]) {
          await ayer.into(ayer.apuntes).insert(
            ApuntesCompanion.insert(
              clave: clave,
              hechoAt: DateTime(2026, 10, 7, 9),
              metodo: metodo,
              ruta: ruta,
              cuerpo: '{"v":"$clave"}',
            ),
          );
        }
        await ayer.customStatement(
          "INSERT INTO vehicles (id, name, capacity) VALUES ('v-1', 'Camión rico', 3000)",
        );
        await ayer.customStatement(
          'INSERT INTO routes (id, route_code, status, vehicle_id) '
          "VALUES ('r-1', 'RT-20261007-001', 'planned', 'v-1')",
        );
        await ayer.customStatement(
          'INSERT INTO orders (id, customer_name, address, weight, archivado, route_id) '
          "VALUES ('ped-1', 'Bodega La Rica', 'Calle 1', 75, 0, 'r-1')",
        );
        for (final (id, linea, descripcion) in const [
          ('ri-1', 1, 'Arroz'),
          ('ri-2', 2, 'Aceite'),
        ]) {
          await ayer.customStatement(
            'INSERT INTO order_items (id, order_id, linea, description, quantity) '
            "VALUES ('$id', 'ped-1', $linea, '$descripcion', 10)",
          );
        }
        // Lo que el esquema 6 trae y el 4 no.
        await ayer.customStatement('ALTER TABLE vehicles DROP COLUMN is_active');
        if (conLaColumna) {
          await ayer.customStatement('ALTER TABLE orders ADD COLUMN vehicle_id TEXT');
          await ayer.customStatement("UPDATE orders SET vehicle_id = 'v-1'");
        }
        await ayer.customStatement('PRAGMA user_version = 4');
        await ayer.close();

        // --- Se abre con el de hoy ------------------------------------------------
        final nueva = BaseLocal.con(NativeDatabase(fichero));
        addTearDown(nueva.close);

        expect(
          (await nueva.select(nueva.apuntes).get()).map((a) => (a.metodo, a.clave)),
          [
            ('POST', '01J8-a-post'),
            ('PATCH', '01J8-b-patch'),
            ('DELETE', '01J8-c-delete'),
          ],
          reason: 'los tres verbos de la cola, en su orden y sin tocar',
        );
        final camion = (await nueva.select(nueva.vehicles).get()).single;
        expect(camion.name, 'Camión rico');
        expect(camion.isActive, isTrue);
        final ruta = (await nueva.select(nueva.routes).get()).single;
        expect((ruta.routeCode, ruta.vehicleId), ('RT-20261007-001', 'v-1'));
        final pedido = (await nueva.select(nueva.orders).get()).single;
        expect((pedido.customerName, pedido.routeId), ('Bodega La Rica', 'r-1'));
        expect(
          (await nueva.select(nueva.orderItems).get()).map((r) => r.description),
          unorderedEquals(['Arroz', 'Aceite']),
          reason: 'los renglones cuelgan del pedido y viajan con él',
        );

        // La columna se fue (o ya no estaba) y nadie lo notó.
        expect(
          (await nueva.customSelect('PRAGMA table_info(orders)').get()).map(
            (f) => f.read<String>('name'),
          ),
          isNot(contains('vehicle_id')),
        );

        // `beforeOpen` sigue haciendo lo suyo sobre una base migrada: las claves
        // ajenas encendidas y los índices de la copia presentes.
        expect(
          (await nueva.customSelect('PRAGMA foreign_keys').getSingle())
              .read<int>('foreign_keys'),
          1,
        );
        final indices = (await nueva
                .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
                .get())
            .map((f) => f.read<String>('name'))
            .toSet();
        expect(
          indices,
          containsAll([
            'order_items_order_idx',
            'orders_sucursal_fecha_idx',
            'orders_ultima_ruta_idx',
            'apuntes_estado_idx',
          ]),
        );
        expect(
          (await nueva.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          nueva.schemaVersion,
        );
      },
    );
  }

  // LA 7: LA BANDEJA DE REVISIÓN (09/10/2026).
  //
  // `apuntes` —la tabla donde vive LA COLA SIN SUBIR— gana cuatro columnas nulas
  // (`revision`, `revisado_por`, `revisado_at`, `motivo_revision`). Es la primera vez que la
  // migración toca esa tabla, así que se prueba con la cola real dentro: un apunte pendiente,
  // uno rechazado con su motivo y otro descartado. Las dos pruebas son el mismo salto con y
  // sin las columnas ya puestas: el segundo caso es una copia nacida con el esquema nuevo y el
  // `user_version` atrás, y un `ADD COLUMN` de una columna que ya está LANZA, la migración no
  // termina y la base no abre.
  const columnasDeLaRevision = [
    'revision',
    'revisado_por',
    'revisado_at',
    'motivo_revision',
  ];
  
  for (final yaEstaban in [false, true]) {
    test(
      'desde la 6: la bandeja de revisión ${yaEstaban ? 'CON' : 'SIN'} las columnas ya puestas '
      'abre y conserva la cola',
      () async {
        final fichero = await _ficheroDePrueba();
        addTearDown(() async {
          if (fichero.existsSync()) await fichero.delete();
        });
  
        final ayer = BaseLocal.con(NativeDatabase(fichero));
        for (final (clave, estado, motivo) in const [
          ('01J8-pendiente', 'pendiente', null),
          ('01J8-rechazado', 'rechazado', 'Ese pedido ya va en otra ruta'),
          ('01J8-descartado', 'descartado', 'Se rehízo en la web'),
        ]) {
          await ayer.into(ayer.apuntes).insert(
            ApuntesCompanion.insert(
              clave: clave,
              hechoAt: DateTime(2026, 10, 8, 9),
              metodo: 'POST',
              ruta: '/routes/r-1/results',
              cuerpo: '{"v":"$clave"}',
            ),
          );
          await ayer.customStatement(
            'UPDATE apuntes SET estado = ?1, motivo = ?2 WHERE clave = ?3',
            [estado, motivo, clave],
          );
        }
        if (!yaEstaban) {
          for (final columna in columnasDeLaRevision) {
            await ayer.customStatement('ALTER TABLE apuntes DROP COLUMN $columna');
          }
        }
        await ayer.customStatement('PRAGMA user_version = 6');
        await ayer.close();
  
        final nueva = BaseLocal.con(NativeDatabase(fichero));
        addTearDown(nueva.close);
  
        final cola = await (nueva.select(nueva.apuntes)
              ..orderBy([(a) => OrderingTerm.asc(a.orden)]))
            .get();
        expect(
          cola.map((a) => (a.clave, a.estado, a.motivo, a.cuerpo)),
          [
            ('01J8-pendiente', EstadoApunte.pendiente, null, '{"v":"01J8-pendiente"}'),
            (
              '01J8-rechazado',
              EstadoApunte.rechazado,
              'Ese pedido ya va en otra ruta',
              '{"v":"01J8-rechazado"}',
            ),
            (
              '01J8-descartado',
              EstadoApunte.descartado,
              'Se rehízo en la web',
              '{"v":"01J8-descartado"}',
            ),
          ],
          reason: 'la cola sin subir sobrevive al salto, con su estado, motivo y cuerpo',
        );
        // Y las cuatro columnas existen, preguntándoselo a SQLite (un nulo y una columna
        // que no está se leen igual desde Dart).
        final hay = (await nueva.customSelect('PRAGMA table_info(apuntes)').get())
            .map((f) => f.read<String>('name'));
        expect(hay, containsAll(columnasDeLaRevision));
        expect(cola.every((a) => a.revision == null && a.revisadoPor == null), isTrue);
  
        // Y SE PUEDE ESCRIBIR LO NUEVO: el estado nuevo y las columnas nuevas viajan.
        await nueva.customStatement(
          "UPDATE apuntes SET estado = 'enRevision', revision = 'ent-1', "
          "revisado_por = 'Marta Pérez', motivo_revision = 'x' "
          "WHERE clave = '01J8-pendiente'",
        );
        expect(await nueva.cuantosEnRevision(), 1);
        expect(
          (await nueva.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          7,
        );
        expect(nueva.schemaVersion, 7);
      },
    );
  }
  
}

Future<File> _ficheroDePrueba() async {
  final dir = await Directory.systemTemp.createTemp('reparto-migracion');
  return File('${dir.path}/base.sqlite');
}
