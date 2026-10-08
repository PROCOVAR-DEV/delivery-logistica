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
}

Future<File> _ficheroDePrueba() async {
  final dir = await Directory.systemTemp.createTemp('reparto-migracion');
  return File('${dir.path}/base.sqlite');
}
