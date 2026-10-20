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
// El 14/10/2026 se subió a la 8 (los distribuidores, issue 7 de Amado: una tabla nueva y
// `routes.distribuidor_id`): ver el último grupo de este fichero. Es la primera subida que CREA
// una tabla en vez de añadir una columna, y se prueba igual, con la cola dentro.
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

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';

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
    await ayer
        .into(ayer.apuntes)
        .insert(
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
  test(
    'desde la 4: quitar vehicle_id y añadir is_active conserva la cola',
    () async {
      final fichero = await _ficheroDePrueba();
      addTearDown(() async {
        if (fichero.existsSync()) await fichero.delete();
      });

      final ayer = BaseLocal.con(NativeDatabase(fichero));
      await ayer
          .into(ayer.apuntes)
          .insert(
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
      await ayer.customStatement(
        'ALTER TABLE orders ADD COLUMN vehicle_id TEXT',
      );
      await ayer.customStatement(
        "UPDATE orders SET vehicle_id = 'camion-viejo'",
      );
      await ayer.customStatement('ALTER TABLE vehicles DROP COLUMN is_active');
      await ayer.customStatement(
        "INSERT INTO vehicles (id, name) VALUES ('v-4', 'Camión de la 4')",
      );
      await ayer.customStatement('PRAGMA user_version = 4');
      await ayer.close();

      final nueva = BaseLocal.con(NativeDatabase(fichero));
      addTearDown(nueva.close);

      expect((await nueva.select(nueva.apuntes).get()).map((a) => a.clave), [
        '01J8-lo-de-la-4',
      ], reason: 'la cola sin subir sobrevive a un DROP COLUMN');
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
    },
  );

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
          await ayer
              .into(ayer.apuntes)
              .insert(
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
        await ayer.customStatement(
          'ALTER TABLE vehicles DROP COLUMN is_active',
        );
        if (conLaColumna) {
          await ayer.customStatement(
            'ALTER TABLE orders ADD COLUMN vehicle_id TEXT',
          );
          await ayer.customStatement("UPDATE orders SET vehicle_id = 'v-1'");
        }
        await ayer.customStatement('PRAGMA user_version = 4');
        await ayer.close();

        // --- Se abre con el de hoy ------------------------------------------------
        final nueva = BaseLocal.con(NativeDatabase(fichero));
        addTearDown(nueva.close);

        expect(
          (await nueva.select(nueva.apuntes).get()).map(
            (a) => (a.metodo, a.clave),
          ),
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
        expect(
          (pedido.customerName, pedido.routeId),
          ('Bodega La Rica', 'r-1'),
        );
        expect(
          (await nueva.select(nueva.orderItems).get()).map(
            (r) => r.description,
          ),
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
        final indices =
            (await nueva
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE type = 'index'",
                    )
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
          await ayer
              .into(ayer.apuntes)
              .insert(
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
            await ayer.customStatement(
              'ALTER TABLE apuntes DROP COLUMN $columna',
            );
          }
          // Un aparato de verdad en la 6 tampoco tiene lo de la 8 (auditoría del 15/10/2026: con
          // la tabla ya creada, `desde == 7` en vez de `desde < 8` salía verde).
          await ayer.customStatement('DROP TABLE distribuidores');
          await ayer.customStatement(
            'ALTER TABLE routes DROP COLUMN distribuidor_id',
          );
        }
        await ayer.customStatement('PRAGMA user_version = 6');
        await ayer.close();

        final nueva = BaseLocal.con(NativeDatabase(fichero));
        addTearDown(nueva.close);

        final cola = await (nueva.select(
          nueva.apuntes,
        )..orderBy([(a) => OrderingTerm.asc(a.orden)])).get();
        expect(
          cola.map((a) => (a.clave, a.estado, a.motivo, a.cuerpo)),
          [
            (
              '01J8-pendiente',
              EstadoApunte.pendiente,
              null,
              '{"v":"01J8-pendiente"}',
            ),
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
        final hay =
            (await nueva.customSelect('PRAGMA table_info(apuntes)').get()).map(
              (f) => f.read<String>('name'),
            );
        expect(hay, containsAll(columnasDeLaRevision));
        expect(
          cola.every((a) => a.revision == null && a.revisadoPor == null),
          isTrue,
        );
        // Y lo de la 8, que un aparato que viene de la 6 SE SALTA la 7: la tabla de los
        // distribuidores y la columna de la ruta tienen que estar al abrir.
        final tablas =
            (await nueva
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE type = 'table'",
                    )
                    .get())
                .map((f) => f.read<String>('name'));
        expect(
          tablas,
          contains('distribuidores'),
          reason: 'desde la 6 la migración tiene que crear también lo de la 8',
        );
        final deRutas =
            (await nueva.customSelect('PRAGMA table_info(routes)').get()).map(
              (f) => f.read<String>('name'),
            );
        expect(deRutas, contains('distribuidor_id'));

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
          nueva.schemaVersion,
        );
        expect(nueva.schemaVersion, 12);
      },
    );
  }

  // LA 8: LOS DISTRIBUIDORES (14/10/2026, issue 7 de Amado).
  //
  // Una TABLA nueva (`distribuidores`) y una columna nueva (`routes.distribuidor_id`). Se prueba
  // con un fichero RICO —la cola de los tres verbos, un camión, una ruta con su pedido y sus
  // renglones— porque lo que se defiende es lo de siempre: que la base abra y que la cola sin
  // subir siga ahí. Y por triplicado, que es el caso que protege la guarda de `desde < 8`:
  //
  //  · SIN la tabla ni la columna (el aparato de ayer, de verdad);
  //  · CON las dos ya puestas (una copia nacida con el esquema nuevo y el `user_version` atrás):
  //    un `CREATE TABLE` de una que existe LANZA, la migración no termina y la base no abre;
  //  · sólo la tabla, o sólo la columna (un salto interrumpido a la mitad).
  for (final (nombre, quitaLaTabla, quitaLaColumna) in const [
    ('SIN la tabla ni la columna', true, true),
    ('CON la tabla y la columna ya puestas', false, false),
    ('con la tabla pero SIN la columna', false, true),
    ('con la columna pero SIN la tabla', true, false),
  ]) {
    test(
      'desde la 7: los distribuidores $nombre abren y no pierden nada',
      () async {
        final fichero = await _ficheroDePrueba();
        addTearDown(() async {
          if (fichero.existsSync()) await fichero.delete();
        });

        final ayer = BaseLocal.con(NativeDatabase(fichero));
        for (final (clave, metodo, ruta) in const [
          ('01J8-a-post', 'POST', '/api/routes'),
          ('01J8-b-patch', 'PATCH', '/api/routes/r-1'),
          ('01J8-c-delete', 'DELETE', '/api/routes/r-1/stops/ped-1'),
        ]) {
          await ayer
              .into(ayer.apuntes)
              .insert(
                ApuntesCompanion.insert(
                  clave: clave,
                  hechoAt: DateTime(2026, 10, 13, 9),
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
          'INSERT INTO routes (id, route_code, status, vehicle_id, branch_id) '
          "VALUES ('r-1', 'RT-20261013-001', 'planned', 'v-1', 'suc-1')",
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
        // Lo de la 8, tal como lo tiene o no tiene el aparato de ayer.
        if (quitaLaTabla) {
          await ayer.customStatement('DROP TABLE distribuidores');
        }
        if (quitaLaColumna) {
          await ayer.customStatement(
            'ALTER TABLE routes DROP COLUMN distribuidor_id',
          );
        }
        await ayer.customStatement('PRAGMA user_version = 7');
        await ayer.close();

        final nueva = BaseLocal.con(NativeDatabase(fichero));
        addTearDown(nueva.close);

        // LA COLA, entera y en su orden.
        expect(
          (await nueva.select(nueva.apuntes).get()).map(
            (a) => (a.metodo, a.clave),
          ),
          [
            ('POST', '01J8-a-post'),
            ('PATCH', '01J8-b-patch'),
            ('DELETE', '01J8-c-delete'),
          ],
          reason:
              'la cola sin subir es el trabajo del día: una migración que se la lleve '
              'no se nota hasta que alguien la reclama',
        );
        final ruta = (await nueva.select(nueva.routes).get()).single;
        expect(
          (ruta.routeCode, ruta.vehicleId, ruta.branchId),
          ('RT-20261013-001', 'v-1', 'suc-1'),
        );
        expect(
          ruta.distribuidorId,
          isNull,
          reason:
              'una ruta de antes de la 8 no tiene distribuidor, y la migración no le '
              'inventa uno: un hueco se ve y se rellena, un nombre puesto no',
        );
        expect(
          (await nueva.select(nueva.orders).get()).single.customerName,
          'Bodega La Rica',
        );
        expect(
          (await nueva.select(nueva.orderItems).get()).map(
            (r) => r.description,
          ),
          unorderedEquals(['Arroz', 'Aceite']),
        );

        // LA TABLA Y LA COLUMNA EXISTEN, preguntándoselo a SQLite (un nulo y una columna
        // que no está se leen igual desde Dart).
        final tablas =
            (await nueva
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE type = 'table'",
                    )
                    .get())
                .map((f) => f.read<String>('name'));
        expect(tablas, contains('distribuidores'));
        final deRutas =
            (await nueva.customSelect('PRAGMA table_info(routes)').get()).map(
              (f) => f.read<String>('name'),
            );
        expect(deRutas, contains('distribuidor_id'));

        // Y SE PUEDE USAR: se escribe, se lee y la ruta lo apunta.
        await nueva
            .into(nueva.distribuidores)
            .insert(
              DistribuidoresCompanion.insert(
                id: 'd-1',
                nombre: 'Juan Pérez',
                branchId: const Value('suc-1'),
              ),
            );
        await (nueva.update(nueva.routes)..where((r) => r.id.equals('r-1')))
            .write(const RoutesCompanion(distribuidorId: Value('d-1')));
        final d = (await nueva.select(nueva.distribuidores).get()).single;
        expect(
          (d.nombre, d.activo),
          ('Juan Pérez', true),
          reason: 'un distribuidor nace ACTIVO: leerlo al reves esconderia a toda la sucursal',
        );
        expect(
          (await nueva.select(nueva.routes).get()).single.distribuidorId,
          'd-1',
        );

        expect(
          (await nueva.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          nueva.schemaVersion,
        );
        expect(nueva.schemaVersion, 12);
      },
    );
  }

  // LA 9: EL PUNTO DE SALIDA DE CADA ZONA (15/10/2026).
  //
  // `board_columns` gana `almacen_id`. Esa tabla NO es de Drift (la crea `EsquemaTablero`
  // al abrir el Tablero), así que la migración sólo la toca si existe y le falta la columna.
  // Se prueba con un fichero RICO —la cola con gestos del tablero, una zona con su camión y
  // una tarjeta puesta— en las formas que puede tener el aparato de ayer:
  //
  //  · en la 8, con el tablero y SIN la columna (el de verdad);
  //  · en la 7 y en la 6 (desde ≤7 también llega, con los pasos de en medio);
  //  · en la 8 SIN tablero (nunca lo abrió): no hay nada que tocar y no revienta;
  //  · en la 8 CON la columna ya puesta (copia nacida nueva y `user_version` atrás): un
  //    `ADD COLUMN` repetido LANZA y la base no abriría.
  for (final (desde, conTablero, conLaColumna) in const [
    (8, true, false),
    (7, true, false),
    (6, true, false),
    (8, false, false),
    (8, true, true),
  ]) {
    final forma = !conTablero
        ? 'que nunca se abrió'
        : (conLaColumna ? 'con almacen_id ya puesto' : 'sin almacen_id');
    test('desde la $desde: el tablero $forma abre y no pierde nada', () async {
      final fichero = await _ficheroDePrueba();
      addTearDown(() async {
        if (fichero.existsSync()) await fichero.delete();
      });

      final ayer = BaseLocal.con(NativeDatabase(fichero));
      for (final (clave, metodo, ruta) in const [
        ('01J8-a-zona', 'POST', '/board/columns?branchId=suc-1'),
        ('01J8-b-puesta', 'PUT', '/board/placements/ped-1'),
        ('01J8-c-camion', 'PATCH', '/board/columns/z-1'),
      ]) {
        await ayer
            .into(ayer.apuntes)
            .insert(
              ApuntesCompanion.insert(
                clave: clave,
                hechoAt: DateTime(2026, 10, 15, 9),
                metodo: metodo,
                ruta: ruta,
                cuerpo: '{"v":"$clave"}',
              ),
            );
      }
      await ayer.customStatement(
        'INSERT INTO orders (id, customer_name, address, weight, archivado) '
        "VALUES ('ped-1', 'Bodega La Rica', 'Calle 1', 75, 0)",
      );
      if (conTablero) {
        await EsquemaTablero.asegurar(ayer);
        await ayer.customStatement(
          'INSERT INTO board_columns (id, branch_id, nombre, posicion, '
          "vehicle_id, nacio_aqui) VALUES ('z-1', 'suc-1', 'Centro', 1, 'v-1', 1)",
        );
        await ayer.customStatement(
          'INSERT INTO board_placements (order_id, column_id, posicion, '
          "nacio_aqui) VALUES ('ped-1', 'z-1', 1, 1)",
        );
        if (!conLaColumna) {
          await ayer.customStatement(
            'ALTER TABLE board_columns DROP COLUMN almacen_id',
          );
        }
      }
      await ayer.customStatement('PRAGMA user_version = $desde');
      await ayer.close();

      final nueva = BaseLocal.con(NativeDatabase(fichero));
      addTearDown(nueva.close);

      expect(
        (await nueva.select(nueva.apuntes).get()).map(
          (a) => (a.metodo, a.clave),
        ),
        [
          ('POST', '01J8-a-zona'),
          ('PUT', '01J8-b-puesta'),
          ('PATCH', '01J8-c-camion'),
        ],
        reason:
            'la cola sin subir es el trabajo del día: una migración que se '
            'la lleve no se nota hasta que alguien la reclama',
      );
      expect(
        (await nueva.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        12,
      );

      // LA COLUMNA EXISTE, preguntándoselo a SQLite, ANTES de que el Tablero
      // vuelva a pasar por `EsquemaTablero` (que sólo crea lo que no existe).
      if (conTablero) {
        final deZonas =
            (await nueva.customSelect('PRAGMA table_info(board_columns)').get())
                .map((f) => f.read<String>('name'));
        expect(
          deZonas,
          contains('almacen_id'),
          reason: 'sin ella, leer o guardar el punto de una zona revienta',
        );
        final zona = await nueva
            .customSelect(
              'SELECT nombre, vehicle_id, almacen_id, nacio_aqui FROM board_columns',
            )
            .getSingle();
        expect(
          (
            zona.read<String>('nombre'),
            zona.readNullable<String>('vehicle_id'),
            zona.readNullable<String>('almacen_id'),
            zona.read<int>('nacio_aqui'),
          ),
          ('Centro', 'v-1', null, 1),
          reason:
              'la zona de ayer sigue con su camión y su marca; sin punto = '
              'el principal, que es de donde salía',
        );
        expect(
          (await nueva
                  .customSelect('SELECT column_id FROM board_placements')
                  .getSingle())
              .read<String>('column_id'),
          'z-1',
        );
      }

      // Y SE PUEDE USAR (también donde el tablero nace ahora).
      await EsquemaTablero.asegurar(nueva);
      await nueva.customStatement(
        'INSERT INTO board_columns (id, branch_id, nombre, posicion, almacen_id) '
        "VALUES ('z-2', 'suc-1', 'Aurora', 2, 'alm-aurora')",
      );
      expect(
        (await nueva
                .customSelect(
                  "SELECT almacen_id FROM board_columns WHERE id = 'z-2'",
                )
                .getSingle())
            .read<String>('almacen_id'),
        'alm-aurora',
      );
    });
  }

  // LA 10: DE QUÉ ALMACÉN SALE CADA PEDIDO (15/10/2026, 1.0.37).
  //
  // `orders` gana `almacen_salida_codigo` y `warehouses` gana `codigo`. Las formas que puede
  // tener el aparato de ayer: en la 9 SIN las dos (el de verdad), en la 8 sin ellas (llega con
  // los pasos de en medio) y en la 9 CON las dos ya puestas (copia nacida nueva y
  // `user_version` atrás): un `ADD COLUMN` repetido LANZA y la base no abriría.
  for (final (desde, yaEstaban) in const [(9, false), (8, false), (9, true)]) {
    test(
      'desde la $desde: el almacén de cada pedido ${yaEstaban ? 'CON' : 'SIN'} las '
      'columnas abre y no pierde nada',
      () async {
        final fichero = await _ficheroDePrueba();
        addTearDown(() async {
          if (fichero.existsSync()) await fichero.delete();
        });

        final ayer = BaseLocal.con(NativeDatabase(fichero));
        await ayer
            .into(ayer.apuntes)
            .insert(
              ApuntesCompanion.insert(
                clave: '01J8-puesta',
                hechoAt: DateTime(2026, 10, 15, 9),
                metodo: 'PUT',
                ruta: '/board/placements/ped-1',
                cuerpo: '{"v":"01J8-puesta"}',
              ),
            );
        await ayer.customStatement(
          'INSERT INTO orders (id, customer_name, address, weight, archivado) '
          "VALUES ('ped-1', 'Bodega La Rica', 'Calle 1', 75, 0)",
        );
        await ayer.customStatement(
          'INSERT INTO warehouses (id, sucursal_codigo, nombre, principal, activo) '
          "VALUES ('alm-aurora', 'STG', 'AURORA', 0, 1)",
        );
        if (!yaEstaban) {
          await ayer.customStatement(
            'ALTER TABLE orders DROP COLUMN almacen_salida_codigo',
          );
          await ayer.customStatement(
            'ALTER TABLE warehouses DROP COLUMN codigo',
          );
        }
        await ayer.customStatement('PRAGMA user_version = $desde');
        await ayer.close();

        final nueva = BaseLocal.con(NativeDatabase(fichero));
        addTearDown(nueva.close);

        expect(
          (await nueva.select(nueva.apuntes).get()).map((a) => a.clave),
          ['01J8-puesta'],
          reason:
              'la cola sin subir es el trabajo del día y sobrevive al salto',
        );
        final pedido = await nueva.select(nueva.orders).getSingle();
        expect(
          (pedido.customerName, pedido.almacenSalidaCodigo),
          ('Bodega La Rica', null),
          reason: 'el pedido de ayer sigue, y su almacén es «no se sabe» hasta que baje',
        );
        final almacen = await nueva.select(nueva.warehouses).getSingle();
        expect((almacen.nombre, almacen.codigo), ('AURORA', null));
        expect(
          (await nueva.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          12,
        );

        // Y SE PUEDE ESCRIBIR: es lo que hará la bajada.
        await (nueva.update(nueva.orders)..where((o) => o.id.equals('ped-1')))
            .write(const OrdersCompanion(almacenSalidaCodigo: Value('2')));
        await (nueva.update(nueva.warehouses)
              ..where((w) => w.id.equals('alm-aurora')))
            .write(const WarehousesCompanion(codigo: Value('2')));
        expect(
          (await nueva.select(nueva.orders).getSingle()).almacenSalidaCodigo,
          '2',
        );
        expect((await nueva.select(nueva.warehouses).getSingle()).codigo, '2');
      },
    );
  }

  // LA 12: EL PUNTO DE ENTREGA A MANO (20/10/2026, issue 19 de Amado).
  //
  // `orders` gana seis columnas. Las formas que puede tener el aparato de ayer: en la 11 SIN
  // ellas (el de verdad), en la 10 (llega con el paso de en medio) y en la 11 CON ellas ya
  // puestas (copia nacida nueva y `user_version` atrás): un `ADD COLUMN` repetido LANZA y la
  // base no abriría, o sea la cola del día secuestrada.
  for (final (desde, yaEstaban) in const [
    (11, false),
    (10, false),
    (11, true),
  ]) {
    test(
      'desde la $desde: el punto a mano ${yaEstaban ? 'CON' : 'SIN'} las columnas '
      'abre y no pierde nada',
      () async {
        final fichero = await _ficheroDePrueba();
        addTearDown(() async {
          if (fichero.existsSync()) await fichero.delete();
        });

        final ayer = BaseLocal.con(NativeDatabase(fichero));
        await ayer
            .into(ayer.apuntes)
            .insert(
              ApuntesCompanion.insert(
                clave: '01J8-punto',
                hechoAt: DateTime(2026, 10, 20, 9),
                metodo: 'PUT',
                ruta: '/orders/ped-1/punto',
                cuerpo: '{"lat":1,"lng":2}',
              ),
            );
        await ayer.customStatement(
          'INSERT INTO orders (id, customer_name, address, weight, archivado) '
          "VALUES ('ped-1', 'Bodega La Rica', 'Calle 1', 75, 0)",
        );
        if (!yaEstaban) {
          for (final c in const [
            'punto_manual',
            'punto_manual_por',
            'punto_manual_at',
            'punto_cliente_lat',
            'punto_cliente_lng',
            'punto_cliente_address',
          ]) {
            await ayer.customStatement('ALTER TABLE orders DROP COLUMN $c');
          }
        }
        await ayer.customStatement('PRAGMA user_version = $desde');
        await ayer.close();

        final nueva = BaseLocal.con(NativeDatabase(fichero));
        addTearDown(nueva.close);

        expect(
          (await nueva.select(nueva.apuntes).get()).map((a) => a.clave),
          ['01J8-punto'],
          reason:
              'la cola sin subir es el trabajo del día y sobrevive al salto',
        );
        final pedido = await nueva.select(nueva.orders).getSingle();
        expect(
          (pedido.customerName, pedido.puntoManual, pedido.puntoClienteLat),
          ('Bodega La Rica', false, null),
          reason: 'el pedido de ayer sigue, y su punto es el del cliente',
        );
        expect(
          (await nueva.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          12,
        );

        // CADA UNA de las seis columnas está en la tabla, por su nombre en SQL (una
        // migración a la que le falte UNA abre sin quejarse hasta que alguien la lee).
        final columnas =
            (await nueva.customSelect('PRAGMA table_info(orders)').get())
                .map((f) => f.read<String>('name'))
                .toSet();
        for (final c in const [
          'punto_manual',
          'punto_manual_por',
          'punto_manual_at',
          'punto_cliente_lat',
          'punto_cliente_lng',
          'punto_cliente_address',
        ]) {
          expect(
            columnas,
            contains(c),
            reason: 'la migración 11→12 no la creó',
          );
        }

        // Y SE PUEDE ESCRIBIR Y LEER CADA UNA: es lo que hará la acción.
        final cuando = DateTime.utc(2026, 10, 20, 9);
        await (nueva.update(
          nueva.orders,
        )..where((o) => o.id.equals('ped-1'))).write(
          OrdersCompanion(
            puntoManual: const Value(true),
            puntoManualPor: const Value('Marta Pérez'),
            puntoManualAt: Value(cuando),
            puntoClienteLat: const Value(21.4),
            puntoClienteLng: const Value(-77.9),
            puntoClienteAddress: const Value('Calle 1 entre 2 y 3'),
          ),
        );
        final despues = await nueva.select(nueva.orders).getSingle();
        expect(
          (
            despues.puntoManual,
            despues.puntoManualPor,
            despues.puntoManualAt?.toUtc(),
            despues.puntoClienteLat,
            despues.puntoClienteLng,
            despues.puntoClienteAddress,
          ),
          (true, 'Marta Pérez', cuando, 21.4, -77.9, 'Calle 1 entre 2 y 3'),
        );
        // Los apuntes siguen DESPUÉS de escribir las columnas nuevas.
        expect((await nueva.select(nueva.apuntes).get()).map((a) => a.clave), [
          '01J8-punto',
        ]);
      },
    );
  }
}

Future<File> _ficheroDePrueba() async {
  final dir = await Directory.systemTemp.createTemp('reparto-migracion');
  return File('${dir.path}/base.sqlite');
}
