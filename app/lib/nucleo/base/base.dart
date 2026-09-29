import 'package:drift/drift.dart';

import 'conexion/conexion.dart';
import 'preferencias_del_aparato.dart';
import 'tablas/aparato.dart';
import 'tablas/dominio.dart';

export 'tablas/aparato.dart' show EstadoApunte;
export 'tablas/catalogos.dart';

part 'base.g.dart';

/// Las colecciones que baja `GET /sync/bajada`. Son las claves de `cambios` y
/// las mismas que las filas de `frescura`.
abstract final class Colecciones {
  static const pedidos = 'orders';
  static const renglones = 'order_items';
  static const rutas = 'routes';
  static const clientes = 'customers';
  static const productos = 'products';
  static const vehiculos = 'vehicles';
  static const sucursales = 'branches';
  static const almacenes = 'warehouses';
  static const ajustes = 'settings';

  static const todas = <String>[
    pedidos,
    renglones,
    rutas,
    clientes,
    productos,
    vehiculos,
    sucursales,
    almacenes,
    ajustes,
  ];
}

/// Las claves de `preferencias`. Viven aqui, y no en quien las usa, porque
/// `borrarTodoLoDelDominio()` tiene que saber cual **no** se borra sin importar
/// media aplicacion.
abstract final class ClaveDePreferencia {
  /// El alta de esta instalacion contra `POST /sync/aparato`. La pone el
  /// servidor y **sobrevive a cerrar sesion**: el porque, en
  /// `sincro/identidad_del_aparato.dart` y en `borrarTodoLoDelDominio()`.
  static const aparato = 'aparato';

  /// DE QUIEN ES ESTA COPIA: el `sub` del token de la persona.
  ///
  /// Se escribe la primera vez que se abre la base de alguien y no se toca mas.
  /// Es la segunda cerradura de «la cola de A no sube con el token de B»: la
  /// primera es que cada persona tiene su fichero, asi que con B delante la cola
  /// de A ni siquiera esta abierta; esta es la que sigue valiendo el dia que
  /// alguien cambie como se abren las bases. La mira `Subida` antes de mandar un
  /// solo apunte.
  static const dueno = 'dueno';

  /// EL NOMBRE de quien es esta copia, para PINTARLO.
  ///
  /// Sin esto, el gesto de olvidar a alguien tendria que ensenar el `sub`
  /// —`uaoOUHqTXNYUv672kjdLoZLpFrseCz9e`—, que a quien lo lee no le dice nada y
  /// que es sacar la base de auth a la cara. Se escribe al entrar, porque es el
  /// unico momento en el que se tiene el token delante.
  static const nombreDelDueno = 'nombreDelDueno';

  /// LA SUCURSAL QUE SE ESTA MIRANDO, y la MONEDA en la que se leen los
  /// importes. Las dos son del aparato y las dos se recuerdan.
  ///
  /// Hasta el 16/09/2026 no se guardaban: vivian en un `Notifier` que arrancaba
  /// en `null` y se perdian al cerrar la aplicacion. Un Super Admin que elegia
  /// La Habana volvia a «Todas (8)» en cada arranque, y con «Todas» puesto el
  /// Panel dice «Falta configurar esta sucursal 3 de 4» y no convierte a CUP
  /// —la tasa es POR SUCURSAL—, asi que la aplicacion se abria pareciendo rota
  /// sin estarlo. Jose lo vio en su telefono ese mismo dia.
  ///
  /// `null` guardado NO existe: para decir «todas» se borra la fila. Guardar la
  /// cadena «null» seria una sucursal llamada null.
  static const sucursalMirada = 'sucursalMirada';
  static const monedaMirada = 'monedaMirada';

  /// DE QUE SUCURSAL ES ESTE APARATO. No es lo mismo que la que se mira.
  ///
  /// Un aparato pertenece a UNA sucursal —asi lo exige `POST /sync/aparato`— y
  /// quien tiene la suya no elige nada: la pone el servidor con la sesion. El
  /// caso que faltaba es el de quien ve las ocho: con «Todas» puesto no hay
  /// ninguna que mandar, el alta contesta **400 «Falta la sucursal del
  /// aparato»** y la pantalla lo enseña como «No subio ninguno».
  ///
  /// Pasó en el telefono de Jose el 21/09/2026, con una ruta entera hecha sin
  /// señal esperando a subir. Y la trampa es que el trabajo **no se pierde** —
  /// sigue entero en el aparato— pero no sube, y el aviso no dice que hacer.
  ///
  /// Asi que se pregunta UNA vez y se recuerda aqui, en las preferencias del
  /// aparato, que es de donde es: la sucursal que se MIRA es a donde uno mira;
  /// esta es donde uno esta.
  static const sucursalDelAparato = 'sucursalDelAparato';
}

@DriftDatabase(
  tables: [
    // dominio — espejo del esquema del servidor
    Branches,
    VehicleTypes,
    Vehicles,
    Products,
    Customers,
    Orders,
    OrderItems,
    Routes,
    Warehouses,
    Settings,
    // aparato — no suben nunca
    Apuntes,
    Equivalencias,
    Frescura,
    Preferencias,
  ],
)
class BaseLocal extends _$BaseLocal {
  /// La base de una persona. [dueno] es el `sub` de su token.
  ///
  /// **Un fichero por persona**, y el porque entero esta en
  /// `conexion/nombre.dart`. `null` es «todavia no ha entrado nadie»: una base
  /// neutra y aparte, que no es la de nadie.
  BaseLocal({String? dueno})
    : _dueno = dueno,
      super(abrirConexion(dueno: dueno));

  /// Para los tests y para el dia que haga falta una segunda base.
  BaseLocal.con(super.executor, {String? dueno}) : _dueno = dueno;

  /// El `sub` de quien es esta copia, o `null` si no es de nadie.
  final String? _dueno;

  String? get dueno => _dueno;

  /// ## 2 — la tasa de cambio, en la sucursal (15/09/2026)
  ///
  /// `branches` gana las cuatro columnas de la tasa y la tabla `currencies` se
  /// va entera. El porque de las dos cosas esta en `tablas/dominio.dart`; en una
  /// linea: la tasa es POR SUCURSAL y `currencies` no la llenaba nadie.
  ///
  /// Hay migracion y no un «borra el fichero y vuelve a entrar» aunque esto no
  /// este todavia en produccion, porque el fichero de una base local NO es el de
  /// un servidor: vive en el aparato de alguien, y ahi dentro esta **la cola sin
  /// subir**. Un aparato que se quede sin poder abrir su base pierde el trabajo
  /// del dia, que es lo unico que esta aplicacion no puede permitirse.
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, desde, hasta) async {
      if (desde < 2) {
        await m.addColumn(branches, branches.cupRate);
        await m.addColumn(branches, branches.cupRateFuente);
        await m.addColumn(branches, branches.cupRateTraidoAt);
        await m.addColumn(branches, branches.cupRateFresca);
        // `currencies` ya no existe en el esquema, asi que no hay `TableInfo` que
        // pasarle a `m.deleteTable`: se tira por SQL. `IF EXISTS` porque una base
        // recien creada con la version 2 nunca la tuvo.
        await customStatement('DROP TABLE IF EXISTS currencies');
      }
      if (desde < 3) {
        // DE DÓNDE SON LOS RENGLONES. Ver `Orders.itemsOrigen`.
        //
        // Se añade vacía: nula es «no se sabe», y la pantalla no dice nada hasta
        // que la bajada la rellene. Poner `'pedido'` por defecto sería afirmar
        // sobre todo lo que ya tiene el aparato algo que nadie ha comprobado.
        await m.addColumn(orders, orders.itemsOrigen);
      }
      if (desde < 4) {
        // EL PESO DEL RENGLON. Ver `OrderItems.pesoKg`.
        //
        // Vacias las dos: nulo es «no se sabe» y la pantalla ya lo dice con esas
        // palabras. Rellenarlas con lo que diga el catalogo de hoy seria repetir
        // el fallo que esto viene a arreglar — el peso es el de cuando se
        // facturo, no el de hoy. Se llenan solas con la siguiente bajada.
        await m.addColumn(orderItems, orderItems.pesoKg);
        await m.addColumn(orderItems, orderItems.pesoLineaKg);
      }
    },
    beforeOpen: (detalles) async {
      // Las claves ajenas van ENCENDIDAS. SQLite las trae apagadas por defecto y
      // sin ellas un borrado de ruta deja renglones huerfanos que luego salen en
      // el post-despacho de una ruta que ya no existe.
      await customStatement('PRAGMA foreign_keys = ON');
      for (final indice in indicesDeLaBase) {
        await customStatement(indice);
      }
      await customStatement(tablaDeRenuncias);
      // QUIEN ES EL DUENO, dentro de la propia base. Escrito al abrir y no al
      // guardar el primer apunte: la cola tiene que poder decir de quien es
      // AUNQUE este vacia, porque lo que se comprueba antes de subir es de quien
      // es la copia, no de quien es cada apunte.
      final quien = _dueno;
      if (quien != null && quien.isNotEmpty) {
        await into(preferencias).insertOnConflictUpdate(
          PreferenciasCompanion.insert(
            clave: ClaveDePreferencia.dueno,
            valor: quien,
          ),
        );
      }
    },
  );

  /// LOS ÍNDICES DE LA COPIA, medidos el 26/09/2026 con el volumen de un aparato
  /// (20.000 pedidos, 80.000 renglones, 300 colocados):
  ///
  ///   buscar un producto en «Sin colocar»   44.286 ms  ->  28 ms
  ///   la página de Pedidos (página 100)         30 ms  ->  1,3 ms
  ///   los renglones de una página              4,9 ms  ->  0,6 ms
  ///   las paradas de una ruta                  1,7 ms  ->  0,14 ms
  ///
  /// La primera no es una errata: el `EXISTS` de «¿qué pedidos llevan malta?»
  /// recorría los 80.000 renglones POR CADA pedido. Hasta aquí la base no tenía
  /// ni un índice aparte de las claves primarias.
  ///
  /// **Van al ABRIR y con `IF NOT EXISTS`, no en una migración**, y es a
  /// propósito: así los recibe también el aparato que ya está en la calle con
  /// su base llena, sin subir `schemaVersion` —que es tocar la base donde vive
  /// la cola sin subir—. Cuando ya están, cada uno cuesta una consulta a
  /// `sqlite_master`. Y la web, con su base en memoria que nace vacía en cada
  /// carga, los crea antes de que llegue nada.
  ///
  /// El orden de las columnas es el de las consultas que los usan, y lo ata
  /// `test/nucleo/base/indices_de_la_base_test.dart` con `EXPLAIN QUERY PLAN`:
  /// un índice con otra forma no falla, sólo deja de usarse.
  static const indicesDeLaBase = <String>[
    // Los renglones de un pedido: el buscador por producto, el peso y la hoja
    // del despacho. Es el que se comía los 44 segundos.
    'CREATE INDEX IF NOT EXISTS order_items_order_idx ON order_items (order_id)',
    // La lista de Pedidos, en su orden (`RepositorioPedidos.pagina`).
    'CREATE INDEX IF NOT EXISTS orders_sucursal_fecha_idx '
        'ON orders (branch_id, order_date DESC, created_at DESC)',
    // Las paradas de una ruta, ya en su orden (`RepositorioRutas.paradasDe`).
    'CREATE INDEX IF NOT EXISTS orders_ultima_ruta_idx '
        'ON orders (ultima_ruta_id, stop_order)',
    // La cola: cuántos quedan, y si una zona tiene algo sin subir.
    'CREATE INDEX IF NOT EXISTS apuntes_estado_idx ON apuntes (estado)',
  ];

  /// LO QUE UNA PERSONA HA DADO POR PERDIDO, y por que hace falta una tabla.
  ///
  /// El aviso de «sólo en este aparato» cuenta trabajo que se hizo sin señal y
  /// que **no va a subir nunca**: una ruta con id `local-…` que se quedó sin
  /// ningún apunte que la subiera. El ciclo sabe reconstruir las zonas del
  /// tablero, pero no una ruta ni un vehículo ni un almacén, así que ésos se
  /// cuentan y ahí se quedan — en ámbar, en las siete pantallas, sin un botón.
  ///
  /// Jose, 29/09/2026: «los errores se acumulan y nunca se borran se mantienen
  /// aunq se allan borrado las cosas y solucionado». El §4 del `CLAUDE.md` dice
  /// que eso se queda a la vista **hasta que una persona decida**, y hasta hoy
  /// no había forma de decidir.
  ///
  /// Se anota la renuncia en vez de borrar la fila, y es a propósito: borrar una
  /// ruta local se lleva por delante sus paradas y deja los pedidos apuntando a
  /// algo que ya no está. Aquí no se destruye nada — deja de contarse, y la fila
  /// sigue ahí para quien pregunte mañana qué pasó con aquel reparto.
  ///
  /// **Se crea al abrir y con `IF NOT EXISTS`, no en una migración**, por lo
  /// mismo que [indicesDeLaBase]: así la recibe también el aparato que ya está
  /// en la calle con su base llena, sin tocar `schemaVersion`.
  static const tablaDeRenuncias =
      'CREATE TABLE IF NOT EXISTS renuncias ('
      '  tabla TEXT NOT NULL,'
      '  id TEXT NOT NULL,'
      '  cuando TEXT NOT NULL,'
      '  PRIMARY KEY (tabla, id)'
      ')';

  /// Vacia el dominio de ESTA copia.
  ///
  /// ## Ya NO se llama al cerrar sesion
  ///
  /// Hasta el 15/09/2026 esto era lo que pasaba al salir, y era la mitad de un
  /// fallo: borraba el dominio y dejaba la cola, asi que los 23 apuntes del que
  /// se iba se quedaban esperando a que entrara otro para subir con SU token.
  /// Ahora cada persona tiene su copia, cerrar sesion **cambia de copia** y no
  /// borra nada, y quien vuelve encuentra lo suyo (`conexion/nombre.dart`).
  ///
  /// Esto se sigue usando para **olvidar a alguien**, que es un gesto aparte y
  /// explicito, y por eso sigue sin tocar la cola: quien olvida a una persona
  /// tiene que haber mirado antes si le queda trabajo sin subir, y esa pregunta
  /// se hace fuera, con [cuantosPendientes], para poder avisar ANTES.
  Future<void> borrarTodoLoDelDominio() async {
    await transaction(() async {
      for (final tabla in <TableInfo<Table, Object?>>[
        orderItems,
        orders,
        routes,
        customers,
        products,
        vehicles,
        vehicleTypes,
        warehouses,
        branches,
        settings,
        frescura,
      ]) {
        await delete(tabla).go();
      }

      // `preferencias` se vacia MENOS el alta del aparato.
      //
      // El aparato es el mismo aparato antes y despues de que alguien salga. Si
      // su identificador muriera aqui, la proxima entrada daria de alta uno
      // nuevo y el panel de sincronizacion —que existe para ver que «Palma lleva
      // desde el martes sin subir»— se llenaria de instalaciones fantasma, todas
      // «nunca han subido», entre las que no se podria distinguir el telefono
      // que de verdad se quedo atras.
      //
      // Lo que se borra es el DOMINIO (regla 8): los clientes con sus
      // direcciones y los pedidos del dia, que es lo que no puede quedarse en un
      // telefono que cambia de manos. Aqui solo sobrevive un UUID que no dice
      // nada de nadie. Y si el telefono cambia de sucursal, el servidor lo corta
      // solo: `aparatoDeLaPeticion` contesta 403 «Ese aparato no es de tu
      // sucursal» (`sync/internal/sincro/bajada.go`).
      await (delete(
        preferencias,
      )..where((p) => p.clave.equals(ClaveDePreferencia.aparato).not())).go();
    });
  }

  /// OLVIDAR A ESTA PERSONA: su dominio y **su cola**, todo.
  ///
  /// Es lo unico que borra una cola, y por eso es un gesto aparte: quien llama
  /// tiene que haber preguntado antes con [cuantosPendientes] y haber avisado
  /// si queda trabajo sin subir. Un apunte que desaparece solo es trabajo
  /// perdido que nadie sabe que perdio (`sincronizacion.md`).
  ///
  /// El alta del aparato TAMBIEN se va aqui, al reves que en
  /// [borrarTodoLoDelDominio]: es el alta de esta copia, y la copia deja de
  /// existir. El aparato como tal sigue dado de alta en las demas copias.
  Future<void> olvidar() async {
    await borrarTodoLoDelDominio();
    await transaction(() async {
      await delete(equivalencias).go();
      await delete(apuntes).go();
      await delete(preferencias).go();
    });
  }

  /// DE QUIEN DICE LA PROPIA BASE que es esta copia.
  ///
  /// Sale de `preferencias` y no de [dueno], que es lo que le pasaron al
  /// constructor: lo que hay que comprobar antes de subir una cola es de quien
  /// son las filas que hay escritas, no con que nombre se abrio el fichero.
  /// `null` en una base que nunca tuvo dueno — la neutra de antes de entrar, o
  /// una de prueba.
  Future<String?> duenoGuardado() async {
    final fila =
        await (select(preferencias)
              ..where((p) => p.clave.equals(ClaveDePreferencia.dueno)))
            .getSingleOrNull();
    final valor = fila?.valor;
    return (valor == null || valor.isEmpty) ? null : valor;
  }

  Future<String?> nombreDelDueno() async {
    final fila =
        await (select(preferencias)
              ..where((p) => p.clave.equals(ClaveDePreferencia.nombreDelDueno)))
            .getSingleOrNull();
    return fila?.valor;
  }

  /// Anota el nombre para PINTAR de quien es esta copia. Se llama al entrar.
  Future<void> anotarNombreDelDueno(String nombre) async {
    if (nombre.isEmpty) return;
    await into(preferencias).insertOnConflictUpdate(
      PreferenciasCompanion.insert(
        clave: ClaveDePreferencia.nombreDelDueno,
        valor: nombre,
      ),
    );
  }

  /// Lo ultimo que se eligio, para volver a ponerlo al abrir. `null` cuando no
  /// hay nada elegido: en la sucursal eso es «todas».
  Future<String?> preferencia(String clave) async {
    // EN LA WEB, FUERA DE AQUI. Esta tabla vive en la base del navegador, que es
    // en memoria desde que la web dejo de guardar copia: se vaciaria en cada
    // recarga y la sucursal elegida se perderia. Ver
    // `preferencias_del_aparato.dart`.
    if (PreferenciasDelAparato.fueraDeLaBase) {
      return PreferenciasDelAparato.leer(clave);
    }
    final fila = await (select(
      preferencias,
    )..where((p) => p.clave.equals(clave))).getSingleOrNull();
    final valor = fila?.valor;
    return (valor == null || valor.isEmpty) ? null : valor;
  }

  /// Anota lo elegido. **`null` borra la fila** en vez de escribir una cadena
  /// vacia: leer luego «» y tratarlo como una sucursal es el fallo que esto
  /// evita.
  Future<void> anotarPreferencia(String clave, String? valor) async {
    if (PreferenciasDelAparato.fueraDeLaBase) {
      PreferenciasDelAparato.escribir(clave, valor);
      return;
    }
    if (valor == null || valor.isEmpty) {
      await (delete(preferencias)..where((p) => p.clave.equals(clave))).go();
      return;
    }
    await into(preferencias).insertOnConflictUpdate(
      PreferenciasCompanion.insert(clave: clave, valor: valor),
    );
  }

  /// TRABAJO QUE NO ESTA ARRIBA, contando **tambien los rechazados**.
  ///
  /// `cuantosPendientes()` contesta «¿queda algo EN LA COLA esperando a subir?»,
  /// y hay sitios donde esa es justo la pregunta (cuanto falta de un lote, que
  /// numero pintar en «N sin subir»). Pero **antes de borrar algo** la pregunta
  /// es otra: «¿hay aqui trabajo que no ha llegado al servidor?». Y un apunte
  /// rechazado es exactamente eso — el servidor dijo que no, se quedo con su
  /// motivo esperando a que una persona decida, y **es lo unico que queda de un
  /// cierre que nunca llego**.
  ///
  /// Es el mismo agujero que el tablero cerro el 16/09/2026 con la zona «Vista»
  /// (`pantallas/tablero/datos/servicio.dart`): preguntar por la cola no es
  /// preguntar por lo que no esta arriba. Aqui se separan las dos preguntas en
  /// vez de ensanchar la de siempre, porque las dos hacen falta y confundirlas
  /// fue el fallo.
  ///
  /// **Lo huerfano no cabe aqui** y por eso no esta: no vive en `apuntes`, vive
  /// en las tablas de dominio, y quien lo cuenta es `Huerfanos.mirar()`. Quien
  /// vaya a borrar tiene que preguntar por las dos cosas
  /// (`nucleo/base/personas.dart`).
  Future<int> cuantosSinSubir() async {
    final cuenta = apuntes.orden.count();
    final fila =
        await (selectOnly(apuntes)
              ..addColumns([cuenta])
              ..where(
                apuntes.estado.equalsValue(EstadoApunte.pendiente) |
                    apuntes.estado.equalsValue(EstadoApunte.rechazado),
              ))
            .getSingle();
    return fila.read(cuenta) ?? 0;
  }

  /// Los que el servidor rechazo y siguen esperando a que alguien decida.
  Future<int> cuantosRechazados() async {
    final cuenta = apuntes.orden.count();
    final fila =
        await (selectOnly(apuntes)
              ..addColumns([cuenta])
              ..where(apuntes.estado.equalsValue(EstadoApunte.rechazado)))
            .getSingle();
    return fila.read(cuenta) ?? 0;
  }

  /// ¿Queda algo EN LA COLA esperando a subir? **No cuenta los rechazados**: ver
  /// [cuantosSinSubir], que es la que hay que usar antes de borrar nada.
  Future<int> cuantosPendientes() async {
    final cuenta = apuntes.orden.count();
    final fila =
        await (selectOnly(apuntes)
              ..addColumns([cuenta])
              ..where(apuntes.estado.equalsValue(EstadoApunte.pendiente)))
            .getSingle();
    return fila.read(cuenta) ?? 0;
  }
}
