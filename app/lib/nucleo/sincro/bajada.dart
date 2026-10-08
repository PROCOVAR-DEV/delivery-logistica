import 'package:drift/drift.dart';

import '../base/base.dart';
import '../frescura/frescura.dart';
import '../red/cliente_api.dart';
import '../registro/registro.dart';
import '../reloj.dart';

/// POR DONDE VA LA BAJADA, para quien la este mirando.
///
/// Existe porque una rueda girando cuarenta segundos no dice nada: la persona
/// que acaba de darle al boton necesita ver que la cosa avanza y por donde. Se
/// avisa **por coleccion y por tanda**, que son las dos unidades en las que esto
/// de verdad progresa.
class AvanceDeBajada {
  const AvanceDeBajada({
    required this.coleccion,
    required this.tanda,
    required this.filas,
  });

  /// La clave de [Colecciones] que se esta aplicando ahora mismo.
  final String coleccion;

  /// En que tanda va, desde 1. Con `truncado` se encadenan varias.
  final int tanda;

  /// Filas puestas hasta este momento en esta bajada. Es lo que hace que el
  /// numero se mueva cuando el servidor manda en tandas.
  final int filas;

  @override
  String toString() =>
      'AvanceDeBajada($coleccion, tanda: $tanda, filas: $filas)';
}

/// Quien mira la bajada avanzar. Es un aviso para pintar, **no una promesa**:
/// se avisa ANTES de aplicar cada coleccion, y la transaccion que viene detras
/// todavia se puede deshacer. Lo que de verdad quedo se cuenta despues, en la
/// base (`recuento.dart`).
typedef AvisoDeBajada = void Function(AvanceDeBajada);

/// `GET /api/sync/cambios` — LA BAJADA DEL DIA.
///
/// Es lo que hace que las pantallas dejen de decir «no se ha descargado
/// todavia». Se llama nada mas entrar, cuando hay red, y despues de cada subida
/// de la cola.
///
/// **Escribe en la base local y nada mas.** Ninguna pantalla mira lo que
/// devuelve esto: todas miran la base (regla 2). Por eso lo unico que hace falta
/// comprobar aqui es que las filas queden puestas y que la `frescura` quede
/// marcada — de ahi sale la hora de la franja de estado.
///
/// El orden de las dos cosas importa: primero las filas y **despues** la marca,
/// las dos en la misma transaccion. Al reves, un corte en medio dejaria la marca
/// movida sin los datos detras, y ese trozo de tiempo no lo volveria a pedir
/// nadie (`sincronizacion.md` §1).
class Bajada {
  Bajada({
    required ClienteApi cliente,
    required BaseLocal base,
    required RegistroDeFrescura frescura,
    Reloj reloj = relojDelAparato,
  }) : _cliente = cliente,
       _base = base,
       _frescura = frescura,
       _reloj = reloj;

  final ClienteApi _cliente;
  final BaseLocal _base;
  final RegistroDeFrescura _frescura;
  final Reloj _reloj;

  /// Cuantas tandas se encadenan como mucho cuando el servidor dice `truncado`.
  ///
  /// Un tope y no un `while (truncado)`: un bucle sin tope se comeria la bateria
  /// y la conexion del logistico en el patio del almacen.
  ///
  /// **Eran 8, y 8 no llegaban.** El servidor sirve hasta 2.000 filas por
  /// coleccion y por tanda (`api/internal/api/espejo.go`, `TopeDeBajada`), asi
  /// que ocho tandas topan en 16.000 clientes — y Santiago con Super Admin son
  /// 8.034 de los 8.034 que hay, pero cualquier sucursal grande que crezca se
  /// come el margen sin avisar. Cincuenta deja sitio de sobra y sigue siendo un
  /// tope.
  ///
  /// Lo que de verdad arreglo el caso de los 2.000 clientes no fue este numero:
  /// fue [ResumenDeBajada.entera] —que ahora DICE que se quedo a medias— y la
  /// guarda de la marca que no avanza, abajo. El 15/09/2026 la bajada se dio por
  /// buena con un cuarto de los clientes y nadie se entero.
  static const maximoDeTandas = 50;

  /// Las colecciones que sirve `GET /api/sync/cambios`.
  ///
  /// `order_items` no viene como conjunto suyo —los renglones viajan DENTRO del
  /// pedido— pero se marca igual: la franja de estado mira las nueve de
  /// `Colecciones.todas` y una sin marcar deja la pantalla diciendo «sin
  /// descargar» con los datos ya puestos.
  ///
  /// ## Por que `boardColumns` y `boardPlacements` NO estan aqui
  ///
  /// Decidido el 15/09/2026, al montar el ciclo de sincronizacion. Se quedan
  /// donde estan —`ServicioTablero`, `GET /api/board`— por tres razones, y
  /// cualquiera de las tres basta:
  ///
  ///  1. **El servidor no las sirve.** `sync/internal/sincro/servicio.go` lista
  ///     exactamente ocho conjuntos: `orders`, `routes`, `customers`,
  ///     `products`, `vehicles`, `branches`, `warehouses` y `settings`.
  ///     `docs/tablero.md` §9 las da como algo que la sincronizacion **ganara**,
  ///     no como algo que tenga. Ponerlas aqui hoy seria codigo que parece hecho
  ///     y nunca recibe una fila — el peor estado en el que dejar esto.
  ///  2. **No hay diferencias que bajar.** `/api/board` devuelve la FOTO entera
  ///     de una sucursal, no `puestos`/`quitados`, y encima necesita saber que
  ///     sucursal se mira; esta bajada es por diferencias y la sucursal le es
  ///     opcional. Meter un reemplazo completo dentro de la transaccion de las
  ///     diferencias son dos protocolos en el mismo sitio.
  ///  3. **El tablero tiene una guarda que esta bajada NO puede tener.**
  ///     `ServicioTablero.descargar` se niega a bajar si queda algo en la cola,
  ///     porque la foto del servidor —que no sabe nada de las cuarenta tarjetas
  ///     que se movieron esta tarde— las borraria de golpe y en silencio. Dentro
  ///     de `_aplicar` esa guarda o se pierde, o envenena la bajada del dia
  ///     entera: unas tarjetas sin subir dejarian a los pedidos, las rutas y los
  ///     clientes sin actualizar.
  ///
  /// Lo que SI arregla el ciclo es el momento: al correr `subir` antes de
  /// `bajar`, cuando el tablero se refresca la cola ya esta vacia y su guarda
  /// deja pasar la bajada, que es lo que antes casi nunca ocurria.
  ///
  /// **El dia que el servidor las sirva de verdad** entran aqui como dos
  /// colecciones mas, con sus `puestos` y sus `quitados`, y tienen que entrar en
  /// la MISMA transaccion que el resto —igual que la frescura— para que un corte
  /// no deje la marca movida sin las tarjetas detras.
  static const colecciones = <String>[
    Colecciones.pedidos,
    Colecciones.rutas,
    Colecciones.clientes,
    Colecciones.productos,
    Colecciones.vehiculos,
    Colecciones.sucursales,
    Colecciones.ajustes,
  ];

  /// Baja lo que haya cambiado y lo deja en la base local.
  ///
  /// Lo que lance sale tal cual (`fallos.dart`): `SesionMuerta` manda a la
  /// pantalla de acceso, `FalloDeRed` se reintenta luego y **no** toca nada de lo
  /// que ya estaba bajado. Una bajada que falla nunca deja la base peor que
  /// antes: lo que ya habia sigue ahi y la marca no se mueve.
  Future<ResumenDeBajada> ciclo({
    String? sucursal,
    AvisoDeBajada? avisar,
  }) async {
    var puestos = 0;
    var quitados = 0;
    var completa = false;
    var tandas = 0;
    String? quedoPor;
    String? marcaAnterior;
    // POR DONDE SEGUIR, tal cual lo mando el servidor. **No se mira por dentro**:
    // es suyo y lo que lleva dentro es cosa suya (`api/internal/api/espejo.go`).
    //
    // Hace falta porque el catalogo y el padron de clientes NO se pueden trocear
    // por marca de tiempo —se ordenan por nombre, y miles de filas comparten el
    // mismo `synced_at` porque PEDIDO las trae de una vez—, asi que `hasta` no
    // dice por donde iban. Sin esto, `truncado` era una promesa que el servidor
    // no podia cumplir: se pedia la tanda siguiente y llegaba la misma.
    String? continuar;

    for (var vuelta = 0; vuelta < maximoDeTandas; vuelta++) {
      final desde = await _frescura.desde(Colecciones.pedidos);

      final datos = await _cliente.pedir<Map<String, Object?>>(
        '/sync/cambios',
        params: <String, Object?>{
          'desde': ?desde,
          'sucursal': ?sucursal,
          'continuar': ?continuar,
        },
      );

      tandas++;
      final hasta = datos['hasta'] as String?;
      final continuarNuevo = datos['continuar'] as String?;
      completa = completa || datos['completa'] == true;
      final cambios = (datos['cambios'] as Map<Object?, Object?>?) ?? const {};

      final cuenta = await _aplicar(
        cambios,
        hasta: hasta,
        completa: completa,
        avisar: avisar,
        tanda: tandas,
        yaPuestas: puestos,
      );
      puestos += cuenta.puestos;
      quitados += cuenta.quitados;

      // CUPO TODO: se acabo, y la bajada esta entera.
      if (datos['truncado'] != true) break;

      // A partir de aqui el servidor dijo que queda mas. Todo lo que corte el
      // bucle de ahora en adelante deja la bajada A MEDIAS, y eso tiene que
      // SALIR en el resumen: ese es el fallo de verdad del 15/09/2026, no que se
      // cortara, sino que se cortara callandoselo.

      // Sin marca nueva no hay por donde seguir: pedir otra vez desde el mismo
      // sitio devolveria lo mismo para siempre.
      if (hasta == null) {
        quedoPor = 'el servidor dijo que quedaba mas y no mando la marca';
        Registro.aviso('la bajada vino truncada y sin `hasta`; se para aqui');
        break;
      }

      // NADA SE MOVIO. Es el caso que se comio los clientes: el servidor
      // contesta `truncado` pero no avanza ni la marca ni el cursor, asi que la
      // tanda siguiente pide exactamente lo mismo y aplica exactamente las
      // mismas filas. Sin esta guarda se dan `maximoDeTandas` vueltas
      // escribiendo dos mil clientes una y otra vez, se sale del bucle con cara
      // de haber terminado y el aparato se queda con un cuarto de los clientes
      // —2.000 de 8.034— sin una sola linea en el registro.
      //
      // **Las dos cosas y no solo la marca**: los pedidos se continuan por la
      // marca y el padron por el cursor, asi que una tanda que solo mueve el
      // cursor SI avanza, y cortarla ahi seria volver a dejarse clientes atras.
      if (hasta == marcaAnterior && continuarNuevo == continuar) {
        quedoPor =
            'el servidor dijo que quedaba mas y no avanzo ni la marca ($hasta) '
            'ni el cursor: pedir otra vez traeria lo mismo';
        Registro.fallo('la bajada no avanza: $quedoPor');
        break;
      }
      marcaAnterior = hasta;
      continuar = continuarNuevo;

      // EL TOPE DE TANDAS. Se mira aqui, con `truncado` puesto, para poder
      // decirlo: quedarse a medias por el tope es distinto de haber terminado.
      if (vuelta == maximoDeTandas - 1) {
        quedoPor =
            'se llego al tope de $maximoDeTandas tandas y el servidor seguia '
            'diciendo que queda mas';
        Registro.fallo('la bajada se corto: $quedoPor');
        break;
      }

      Registro.info('la bajada venia truncada: otra tanda desde $hasta');
    }

    return ResumenDeBajada(
      puestos: puestos,
      quitados: quitados,
      completa: completa,
      tandas: tandas,
      quedoPor: quedoPor,
    );
  }

  /// Los almacenes, que NO vienen en `cambios`.
  ///
  /// Viven en Accesos y de ahi salen (`GET /api/almacenes`). Estan declarados en
  /// `faltan` a proposito —Accesos no da marca de cambio ni dice que borro, asi
  /// que no hay diferencias posibles— y por eso aqui se reemplaza la copia
  /// entera en vez de mezclarla. Desde el almacen se mide lo que se le cobra al
  /// cliente por el domicilio: uno viejo cobra mal cada entrega del dia.
  /// CADA CUANTO SE VUELVEN A PEDIR LOS ALMACENES SI NADIE AVISA.
  ///
  /// Hace falta un suelo y no se puede quitar del todo: **los almacenes viven en
  /// Accesos**, y un almacen que se cree o se mueva alli **no publica ningun
  /// aviso del reparto**. Sin este plazo, un almacen nuevo no llegaria nunca a un
  /// aparato que ya tiene los suyos.
  ///
  /// Una hora es de sobra: un almacen no se muda dos veces en la misma manana, y
  /// quien lo cambie desde el reparto si publica su aviso y llega al momento.
  static const cadaCuantoLosAlmacenes = Duration(hours: 1);

  /// ¿HACE FALTA VOLVER A PEDIR LOS ALMACENES?
  ///
  /// Sin fila de frescura es que nunca se bajaron: entonces si, y ademas sin
  /// almacen no hay Tablero.
  Future<bool> _hacenFaltaLosAlmacenes() async {
    final cuando = await _frescura.laMasViejaAhora(const [
      Colecciones.almacenes,
    ]);
    if (cuando == null) return true;
    return _reloj().difference(cuando) >= cadaCuantoLosAlmacenes;
  }

  /// Los almacenes, y **NO en cada vuelta** — 29/09/2026.
  ///
  /// ## Lo que costaba pedirlos siempre
  ///
  /// Esto se llamaba al final de cada ciclo, sin condicion. Medido ese dia en el
  /// telefono de Jose, con la aplicacion abierta y sin tocar nada:
  ///
  ///     GET /api/sync/cambios    584 bytes   <- las OCHO colecciones, en vacio
  ///     GET /api/almacenes     2.671 bytes   <- siempre, cambien o no
  ///
  /// O sea que **el 82 % de lo que se gasta en reposo son los almacenes**, que no
  /// cambian casi nunca. Con la conexion de alla y un ciclo cada pocos minutos,
  /// eso es mas de un mega por hora y por aparato para traer ocho filas iguales.
  ///
  /// ## Cuando se piden ahora
  ///
  ///  * **la primera vez**, o si la copia esta vacia — sin almacen no hay desde
  ///    donde medir, o sea que no hay Tablero;
  ///  * **cuando llega su aviso** (`forzar`), que es el caso de alguien
  ///    cambiandolos desde el reparto: llega al momento;
  ///  * y **cada hora** como red de seguridad, porque viven en Accesos y un
  ///    cambio hecho alli no publica ningun aviso nuestro.
  ///
  /// Devuelve 0 cuando no hacia falta, que no es lo mismo que «no habia
  /// ninguno»: quien mire el resumen tiene la marca de frescura para saberlo.
  Future<int> almacenes({
    AvisoDeBajada? avisar,
    int tanda = 1,
    bool forzar = false,
  }) async {
    if (!forzar && !await _hacenFaltaLosAlmacenes()) {
      Registro.info('almacenes: recientes, no se piden');
      return 0;
    }
    avisar?.call(
      AvanceDeBajada(coleccion: Colecciones.almacenes, tanda: tanda, filas: 0),
    );
    final datos = await _cliente.pedir<Map<String, Object?>>('/almacenes');
    final sucursales = (datos['sucursales'] as List<Object?>?) ?? const [];

    var puestos = 0;
    // LOS QUE VIENEN, para saber después cuáles ya no están.
    //
    // AQUÍ HABÍA UN `delete` DE TODA LA TABLA ANTES DE RELLENARLA, y costó una
    // pantalla en blanco que acusaba en falso. Mientras esa transacción corría,
    // la tabla estaba vacía, y el Tablero —que pregunta desde qué almacén mide
    // en cuanto se pinta— leía justo ahí y decía «Camagüey no tiene ningún
    // almacén con coordenadas» sobre una sucursal que lo tiene. Y no era un
    // caso raro: **el ciclo entero corre en cada cambio de sucursal**, así que
    // pasaba cada vez que Jose cambiaba en la barra de arriba (25/09/2026).
    //
    // Se reemplaza igual que antes —Accesos no da marca de cambio ni dice qué
    // borró, así que la lista que llega ES la verdad—, pero sin el hueco: se
    // ponen todos y **después** se quita lo que no vino.
    final vistos = <String>[];
    await _base.transaction(() async {
      for (final cruda in sucursales.whereType<Map<Object?, Object?>>()) {
        final codigo = _texto(cruda['codigo']) ?? '';
        final lista = (cruda['almacenes'] as List<Object?>?) ?? const [];
        for (final a in lista.whereType<Map<Object?, Object?>>()) {
          final id = _texto(a['id']);
          if (id == null) continue; // sin id no hay fila que casar
          await _base
              .into(_base.warehouses)
              .insertOnConflictUpdate(
                WarehousesCompanion.insert(
                  id: id,
                  sucursalCodigo: codigo,
                  nombre: _texto(a['nombre']) ?? '',
                  direccion: Value(_texto(a['direccion'])),
                  lat: Value(_numero(a['latitud'])),
                  lng: Value(_numero(a['longitud'])),
                  principal: Value(a['principal'] == true),
                  activo: Value(a['activo'] != false),
                ),
              );
          vistos.add(id);
          puestos++;
        }
      }
      // LO QUE YA NO VIENE SE QUITA, pero sólo si vino algo.
      //
      // Una respuesta vacía no es una respuesta buena (`CLAUDE.md` §3): Accesos
      // caído, un despliegue a medias o un alcance mal resuelto devuelven
      // `{"sucursales": []}` con un 200 limpio, y con el `delete` de antes eso
      // borraba los ocho almacenes de un aparato que estaba perfectamente. Sin
      // almacén no hay desde dónde medir, o sea: sin Tablero.
      if (vistos.isNotEmpty) {
        await (_base.delete(
          _base.warehouses,
        )..where((w) => w.id.isNotIn(vistos))).go();
      }
      await _marcar(const [Colecciones.almacenes], hasta: null, completa: true);
    });
    return puestos;
  }

  Future<_Cuenta> _aplicar(
    Map<Object?, Object?> cambios, {
    required String? hasta,
    required bool completa,
    AvisoDeBajada? avisar,
    int tanda = 1,
    int yaPuestas = 0,
  }) async {
    var puestos = 0;
    var quitados = 0;

    await _base.transaction(() async {
      for (final coleccion in colecciones) {
        // El aviso va ANTES de aplicar y **aunque la coleccion no venga en esta
        // tanda**: lo que se pinta es «por donde va», y una coleccion que se
        // salta sin decirlo deja la pantalla parada en la anterior como si se
        // hubiera colgado.
        avisar?.call(
          AvanceDeBajada(
            coleccion: coleccion,
            tanda: tanda,
            filas: yaPuestas + puestos,
          ),
        );

        final conjunto = cambios[coleccion];
        if (conjunto is! Map<Object?, Object?>) continue;

        final filas = (conjunto['puestos'] as List<Object?>?) ?? const [];
        for (final fila in filas.whereType<Map<Object?, Object?>>()) {
          await _poner(coleccion, fila);
          puestos++;
        }

        final fuera = (conjunto['quitados'] as List<Object?>?) ?? const [];
        for (final id in fuera.whereType<String>()) {
          await _quitar(coleccion, id);
          quitados++;
        }
      }

      // La marca, DENTRO de la misma transaccion que las filas.
      await _marcar(
        <String>[...colecciones, Colecciones.renglones],
        hasta: hasta,
        completa: completa,
      );
    });

    return _Cuenta(puestos, quitados);
  }

  Future<void> _marcar(
    List<String> colecciones, {
    required String? hasta,
    required bool completa,
  }) async {
    final ahora = _reloj();
    for (final coleccion in colecciones) {
      await _frescura.marcar(
        coleccion,
        hasta: hasta,
        bajadaAt: ahora,
        completa: completa,
      );
    }
  }

  Future<void> _poner(String coleccion, Map<Object?, Object?> j) async {
    switch (coleccion) {
      case Colecciones.pedidos:
        await _pedido(j);
      case Colecciones.rutas:
        await _base
            .into(_base.routes)
            .insertOnConflictUpdate(
              // LOS CAMPOS QUE FALTABAN, y lo que se veia sin ellos.
              //
              // Visto el 17/09/2026 con la aplicacion delante, contra el entorno
              // local: la lista de rutas ensenaba **`$0.00`** en una ruta de 720
              // USD, «Sin punto de partida» teniendo almacen, y una raya donde
              // va la fecha. El servidor los mandaba los tres —comprobado en la
              // respuesta de `/api/routes`— y **esta funcion no los leia**.
              //
              // Es el fallo que mas caro sale aqui: un importe en cero se lee
              // bien y esta mal, y nadie lo desmiente. No habia forma de cazarlo
              // sin ejecutar, porque lo que no se lee no falla — sale un cero,
              // que es un numero perfectamente creible.
              //
              // `startedAt` y `finishedAt` van por lo mismo: son la linea de
              // «Salida» y «Regreso» de la hoja del post-despacho, la que firma
              // el chofer. Sin ellos la hoja sale sin horario y no se nota.
              RoutesCompanion.insert(
                id: _texto(j['id'])!,
                name: Value(_texto(j['name'])),
                routeCode: Value(_texto(j['routeCode'])),
                status: Value(_texto(j['status']) ?? EstadoRuta.planificada),
                originAddress: Value(_texto(j['originAddress'])),
                originLat: Value(_numero(j['originLat'])),
                originLng: Value(_numero(j['originLng'])),
                totalDistance: Value(_numero(j['totalDistance']) ?? 0),
                totalWeight: Value(_numero(j['totalWeight']) ?? 0),
                // EL `?? 0` DE AQUI NO ES EL IMPORTE DE LA RUTA, y no se
                // quita: `total_price` es `NOT NULL DEFAULT 0` en el servidor
                // (`api/db/migrations/00001_init.sql:426`), asi que el campo
                // siempre viene con numero y esto solo salta si faltara. Lo que
                // se hizo el 22/09/2026 fue quitarle el trabajo de ser el
                // importe: ese se suma de las paradas, que si saben decir
                // `null`. Ver `ImporteDeRuta.espejoDelTotalDelServidor`.
                totalPrice: Value(_numero(j['totalPrice']) ?? 0),
                deliveryDate: Value(_fecha(j['deliveryDate'])),
                vehicleId: Value(_texto(j['vehicleId'])),
                creadoPor: Value(_texto(j['creadoPor'])),
                branchId: Value(_texto(j['branchId'])),
                startedAt: Value(_fecha(j['startedAt'])),
                finishedAt: Value(_fecha(j['finishedAt'])),
                createdAt: Value(_fecha(j['createdAt'])),
                updatedAt: Value(_fecha(j['updatedAt'])),
              ),
            );
      case Colecciones.clientes:
        await _base
            .into(_base.customers)
            .insertOnConflictUpdate(
              CustomersCompanion.insert(
                id: _texto(j['id'])!,
                name: _texto(j['name']) ?? '',
                phone: Value(_texto(j['phone'])),
                address: Value(_texto(j['address'])),
                municipio: Value(_texto(j['municipio'])),
                zona: Value(_texto(j['zona'])),
                codigo: Value(_texto(j['codigo'])),
                vendedor: Value(_texto(j['vendedor'])),
                lat: _numero(j['lat']) ?? 0,
                lng: _numero(j['lng']) ?? 0,
                sucursalCodigo: Value(_texto(j['sucursalCodigo'])),
                // `source` FALTABA. Sin el, los 8.000 del padron salian con la
                // insignia «Manual» y el filtro de origen contestaba al reves:
                // cero para «de PEDIDO» y los ocho mil para «manual».
                source: Value(_texto(j['source'])),
                syncedAt: Value(_fecha(j['syncedAt'])),
              ),
            );
      case Colecciones.productos:
        await _base
            .into(_base.products)
            .insertOnConflictUpdate(
              ProductsCompanion.insert(
                id: _texto(j['id'])!,
                name: _texto(j['name']) ?? '',
                // EL PESO DE UN PRODUCTO QUE NADIE SABE LLEGA COMO CERO, y el
                // `?? 0` de aqui NO es quien lo inventa: `products.weight` es
                // `double precision NOT NULL DEFAULT 0` en el servidor
                // (`api/db/migrations/00001_init.sql:204`) y su DTO es
                // `float64`, no puntero (`api/internal/api/productos.go:59`).
                // O sea que el nulo ya viene perdido de casa: Ventra si lo
                // distingue —`TestPesoNuloNoEsCero` en
                // `api/internal/ventra/ventra_test.go`, «cero kilos es una
                // mentira»— y el esquema del servidor se lo come al guardarlo.
                //
                // Taparlo aqui seria mentir al reves. El arreglo es del
                // servidor: columna nulable y DTO con puntero. Dicho en el
                // informe del 23/09/2026 con lo que cuesta.
                weight: Value(_numero(j['weight']) ?? 0),
                category: Value(_texto(j['category'])),
                sku: Value(_texto(j['sku'])),
                sucursalCodigo: Value(_texto(j['sucursalCodigo'])),
                price: Value(_numero(j['price'])),
                stock: Value(_numero(j['stock'])),
                unit: Value(_texto(j['unit'])),
                updatedAt: Value(_fecha(j['updatedAt'])),
              ),
            );
      case Colecciones.vehiculos:
        await _base
            .into(_base.vehicles)
            .insertOnConflictUpdate(
              VehiclesCompanion.insert(
                id: _texto(j['id'])!,
                name: _texto(j['name']) ?? '',
                plate: Value(_texto(j['plate'])),
                capacity: Value(_numero(j['capacity']) ?? 1000),
                status: Value(_texto(j['status']) ?? EstadoVehiculo.disponible),
                // `isActive` AUSENTE ES ACTIVO. Un servidor viejo no manda el
                // campo, y leerlo con `== true` dejaria TODA la flota dada de
                // baja de golpe: ningun selector ofreceria un camion y no se
                // podria armar una ruta. Solo un `false` explicito es una baja
                // (Amado, 07/10/2026: un camion con rutas se inactiva, no se
                // borra). Lo vigila `la_bajada_no_pierde_campos_test.dart`.
                isActive: Value(j['isActive'] != false),
                branchId: Value(_texto(j['branchId'])),
                updatedAt: Value(_fecha(j['updatedAt'])),
              ),
            );
      case Colecciones.sucursales:
        await _base
            .into(_base.branches)
            .insertOnConflictUpdate(
              BranchesCompanion.insert(
                id: _texto(j['id'])!,
                name: _texto(j['name']) ?? '',
                address: Value(_texto(j['address'])),
                lat: _numero(j['lat']) ?? 0,
                lng: _numero(j['lng']) ?? 0,
                externalId: Value(_texto(j['externalId'])),
                originConfigured: Value(j['originConfigured'] == true),
                updatedAt: Value(_fecha(j['updatedAt'])),
                // LA TASA DE CAMBIO DE ESTA SUCURSAL. Es lo que hace que los
                // importes se puedan ver en CUP sin conexion.
                //
                // Los cuatro se copian TAL CUAL, sin respaldo y sin inventar
                // nada: un `null` que llega es «esta sucursal no tiene tasa», que
                // es un estado normal —hoy le pasa a seis de las ocho— y la
                // barra lo dice con el nombre de la sucursal delante. Poner aqui
                // un `?? 320`, o la tasa de la sucursal de al lado, seria
                // convertir con un numero creible y equivocado; eso no falla en
                // pantalla, falla en la caja.
                //
                // `cupRateFresca` viene de ACCESOS y aqui no se recalcula: la
                // regla de las 24 h es suya. El aparato solo la enseña.
                cupRate: Value(_numero(j['cupRate'])),
                cupRateFuente: Value(_texto(j['cupRateFuente'])),
                cupRateTraidoAt: Value(_fecha(j['cupRateTraidoAt'])),
                cupRateFresca: Value(j['cupRateFresca'] as bool?),
              ),
            );
      case Colecciones.ajustes:
        // UNA sola fila, como en el servidor: dos filas de ajustes es media
        // aplicacion mirando una y media mirando la otra.
        await _base
            .into(_base.settings)
            .insertOnConflictUpdate(
              SettingsCompanion.insert(
                id: const Value(1),
                currency: Value(_texto(j['currency']) ?? 'USD'),
                cupRate: Value(_numero(j['cupRate']) ?? 320),
                cupRateUpdatedAt: Value(_fecha(j['cupRateUpdatedAt'])),
                catalogoTraidoAt: Value(_fecha(j['catalogoTraidoAt'])),
                updatedAt: Value(_fecha(j['updatedAt'])),
              ),
            );
    }
  }

  /// Un pedido con SUS RENGLONES, que viajan dentro.
  ///
  /// Los renglones se reemplazan enteros y no se mezclan: si la factura de
  /// PEDIDO quito una linea, mezclar la dejaria puesta y el despacho cargaria
  /// mercancia que ya no va (`sincronizacion.md` §1).
  Future<void> _pedido(Map<Object?, Object?> j) async {
    final id = _texto(j['id']);
    if (id == null) return;

    await _base
        .into(_base.orders)
        .insertOnConflictUpdate(
          OrdersCompanion.insert(
            id: id,
            operationNumber: Value(_texto(j['operationNumber'])),
            customerName: _texto(j['customerName']) ?? '',
            customerPhone: Value(_texto(j['customerPhone'])),
            address: _texto(j['address']) ?? '',
            endAddress: Value(_texto(j['endAddress'])),
            endLat: Value(_numero(j['endLat'])),
            endLng: Value(_numero(j['endLng'])),
            lat: Value(_numero(j['lat'])),
            lng: Value(_numero(j['lng'])),
            // UN PEDIDO SIN PESO LLEGA COMO **1 kg**, que es una cifra
            // perfectamente creible para un paquete y se suma en «Peso Total»,
            // en el pie de las tablas, en el Excel y —lo peor— en la barra de
            // capacidad del camion, que decide que cabe.
            //
            // **El 1 NO se lo inventa el aparato**, comprobado el 23/09/2026:
            // `orders.weight` es `double precision NOT NULL DEFAULT 1` en el
            // servidor (`api/db/migrations/00001_init.sql:276`) y su DTO es
            // `float64`, no puntero (`api/internal/api/pedidos.go:189`), asi
            // que el campo NUNCA llega nulo. Este `?? 1` solo salta si la
            // respuesta viniera sin el campo, y entonces repite el mismo
            // defecto que el servidor. Quitarlo de aqui no cambiaria un solo
            // pedido.
            //
            // **Donde esta el arreglo, y lo que cuesta**: hacer nulable
            // `orders.weight` en el servidor y en esta tabla, poner puntero en
            // el DTO, y propagar `double?` por todo lo que hoy suma pesos —los
            // informes, el pre y el post-despacho, la barra de capacidad—, que
            // son pantallas de otros. No se empieza a medias. Lo que SI existe
            // ya y no se esta usando es la confesion por renglon:
            // `order_items.weight_source` y `caso`
            // (`api/db/migrations/00004_peso_por_renglon.sql`) dicen de donde
            // salio cada peso y si el renglon caso con el catalogo; ese es el
            // hilo por el que se puede saber que un peso es inventado sin tocar
            // el tipo de la columna.
            weight: Value(_numero(j['weight']) ?? 1),
            status: Value(_texto(j['status']) ?? EstadoPedido.pendiente),
            tripLeg: Value(_texto(j['tripLeg']) ?? Tramo.ida),
            notes: Value(_texto(j['notes'])),
            routeId: Value(_texto(j['routeId'])),
            ultimaRutaId: Value(_texto(j['ultimaRutaId'])),
            price: Value(_numero(j['price'])),
            segmentKm: Value(_numero(j['segmentKm'])),
            deliveryPrice: Value(_numero(j['deliveryPrice'])),
            deliveryDistanceKm: Value(_numero(j['deliveryDistanceKm'])),
            branchId: Value(_texto(j['branchId'])),
            source: Value(_texto(j['source'])),
            externalId: Value(_texto(j['externalId'])),
            orderDate: Value(_fecha(j['orderDate'])),
            // `createdAt` FALTABA, y con el se caia una guarda entera: un
            // pedido sin `orderDate` se acota por esta fecha, «o desapareceria
            // de todos los rangos» (`repositorio_pedidos.dart`). Como nunca
            // llegaba, siempre era nulo y esa rama no podia ser cierta: todo
            // pedido que PEDIDO manda sin fecha se caia de CUALQUIER filtro por
            // fecha, aqui y en el escritorio, mientras la web si lo ensenaba.
            //
            // Tambien es el desempate del orden (`orderDate desc, createdAt
            // desc`): con esto nulo, dos pedidos del mismo dia salian en un
            // orden distinto al del servidor.
            createdAt: Value(_fecha(j['createdAt'])),
            estado: Value(_texto(j['estado'])),
            archivado: Value(j['archivado'] == true),
            fechaComprometida: Value(_fecha(j['fechaComprometida'])),
            requiereDomicilio: Value(j['requiereDomicilio'] as bool?),
            pedidoCosto: Value(_numero(j['pedidoCosto'])),
            municipio: Value(_texto(j['municipio'])),
            vendedor: Value(_texto(j['vendedor'])),
            sucursalCodigo: Value(_texto(j['sucursalCodigo'])),
            facturaEstado: Value(_texto(j['facturaEstado'])),
            // DE DÓNDE SON LOS RENGLONES Y EL PESO. Ver `Orders.itemsOrigen`.
            itemsOrigen: Value(_texto(j['itemsOrigen'])),
            facturaNumero: Value(_texto(j['facturaNumero'])),
            facturaDomicilio: Value(_numero(j['facturaDomicilio'])),
            stopOrder: Value(_entero(j['stopOrder'])),
            deliveredAt: Value(_fecha(j['deliveredAt'])),
            resultado: Value(_texto(j['resultado'])),
            resultadoNota: Value(_texto(j['resultadoNota'])),
            updatedAt: Value(_fecha(j['updatedAt'])),
          ),
        );

    final renglones = (j['items'] as List<Object?>?) ?? const [];
    await (_base.delete(
      _base.orderItems,
    )..where((r) => r.orderId.equals(id))).go();
    for (final r in renglones.whereType<Map<Object?, Object?>>()) {
      final renglonId = _texto(r['id']);
      if (renglonId == null) continue;
      await _base
          .into(_base.orderItems)
          .insertOnConflictUpdate(
            OrderItemsCompanion.insert(
              id: renglonId,
              orderId: id,
              linea: _entero(r['linea']) ?? 1,
              description: _texto(r['description']) ?? '',
              quantity: _numero(r['quantity']) ?? 0,
              packs: Value(_numero(r['packs'])),
              productId: Value(_texto(r['productId'])),
              updatedAt: Value(_fecha(r['updatedAt'])),
              // EL PESO QUE MANDA EL SERVIDOR, que es el de cuando se facturo y
              // no el del catalogo de hoy. Ver `OrderItems.pesoKg`: sin esto la
              // ficha decia «sin peso» con 72,6 kg en el total, y el
              // pre-despacho salia con las catorce filas en raya.
              pesoKg: Value(_numero(r['pesoKg'])),
              pesoLineaKg: Value(_numero(r['pesoLineaKg'])),
            ),
          );
    }
  }

  Future<void> _quitar(String coleccion, String id) async {
    switch (coleccion) {
      case Colecciones.pedidos:
        // Los renglones primero: se borran a mano y no por cascada, porque la
        // tabla local no declara la clave ajena y un renglon huerfano sale luego
        // en el post-despacho de un pedido que ya no existe.
        await (_base.delete(
          _base.orderItems,
        )..where((r) => r.orderId.equals(id))).go();
        await (_base.delete(_base.orders)..where((p) => p.id.equals(id))).go();
      case Colecciones.rutas:
        await (_base.delete(_base.routes)..where((r) => r.id.equals(id))).go();
      case Colecciones.clientes:
        await (_base.delete(
          _base.customers,
        )..where((c) => c.id.equals(id))).go();
      case Colecciones.productos:
        await (_base.delete(
          _base.products,
        )..where((p) => p.id.equals(id))).go();
      case Colecciones.vehiculos:
        await (_base.delete(
          _base.vehicles,
        )..where((v) => v.id.equals(id))).go();
      case Colecciones.sucursales:
        await (_base.delete(
          _base.branches,
        )..where((s) => s.id.equals(id))).go();
    }
  }

  static String? _texto(Object? v) => switch (v) {
    final String s => s,
    _ => null,
  };

  static double? _numero(Object? v) => switch (v) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  static int? _entero(Object? v) => switch (v) {
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };

  /// Las fechas llegan en texto ISO. Una que no se entienda se guarda como
  /// `null` y no revienta la bajada: quedarse sin el dia entero por una marca
  /// rara es mucho peor que quedarse sin una fecha.
  static DateTime? _fecha(Object? v) {
    final texto = _texto(v);
    if (texto == null || texto.isEmpty) return null;
    return DateTime.tryParse(texto)?.toLocal();
  }
}

class ResumenDeBajada {
  const ResumenDeBajada({
    required this.puestos,
    required this.quitados,
    required this.completa,
    required this.tandas,
    this.quedoPor,
  });

  static const nada = ResumenDeBajada(
    puestos: 0,
    quitados: 0,
    completa: false,
    tandas: 0,
  );

  final int puestos;
  final int quitados;

  /// `true` si alguna tanda fue una carga inicial completa, no por diferencias.
  final bool completa;

  final int tandas;

  /// POR QUE SE QUEDO A MEDIAS, en cristiano. `null` cuando no se quedo.
  ///
  /// Esto es lo que faltaba el 15/09/2026. La bajada encadenaba tandas mientras
  /// viniera `truncado`, se quedaba sin cuerda —marca que no avanza, tope de
  /// tandas, `hasta` que no vino— y devolvia un resumen indistinguible del de
  /// una bajada entera. El aparato se quedo con 2.000 clientes de 8.034 y todo
  /// dijo que habia ido bien.
  ///
  /// Un fallo que no revienta y da un numero distinto es el que mas dano hace
  /// aqui: nadie se entera hasta que no cuadra el inventario.
  final String? quedoPor;

  /// `true` cuando el servidor no dejo nada atras.
  bool get entera => quedoPor == null;

  @override
  String toString() =>
      'ResumenDeBajada(puestos: $puestos, quitados: $quitados, '
      'completa: $completa, tandas: $tandas'
      '${quedoPor == null ? "" : ", a medias: $quedoPor"})';
}

class _Cuenta {
  const _Cuenta(this.puestos, this.quitados);

  final int puestos;
  final int quitados;
}
