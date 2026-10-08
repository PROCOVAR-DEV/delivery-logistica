// Lo que Rutas LEE. Todo de la base local, igual que Pedidos: sin conexion se ve
// la lista, se filtra, se pagina, se abre el detalle con sus paradas y su carga
// total. Lo unico que cambia sin red es que el mapa se queda sin baldosas y que
// `Abrir en Google Maps` no puede salir.

import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import '../../pedidos/datos/repositorio_pedidos.dart';

/// Las tres pestanas, con los estados que agrupa cada una y su texto de vacio.
enum PestanaRutas {
  activas('Planificadas', 'Sin rutas planificadas. Crea la primera.'),
  enCurso('En curso', 'Sin rutas en curso.'),
  historial('Historial', 'Sin rutas completadas aún.');

  const PestanaRutas(this.etiqueta, this.vacio);

  final String etiqueta;
  final String vacio;

  /// LA PRIMERA PESTAÑA SE LLAMA «PLANIFICADAS» — 17/09/2026.
  ///
  /// Se llamaba «Activas» y esa palabra estaba mal: la ruta que esta ACTIVA es
  /// la que va en el camion, y esa es «En curso». Una ruta que todavia no ha
  /// salido no esta activa, esta planificada.
  ///
  /// Jose, mirandolo: «ahi en activas, que no son activas, son planificadas».
  /// Y la confusion no es de palabras: quien lee «Activas (1)» cree que tiene un
  /// camion en la calle.
  ///
  /// Lo que AGRUPA no cambia y sigue siendo «ni completada ni en curso», no
  /// «estado == planificada»: una ruta con un estado que todavia no conocemos
  /// tiene que salir en algun sitio, y el sitio es donde se trabaja. Si se
  /// filtrara por el estado exacto, un estado nuevo del servidor dejaria rutas
  /// invisibles en las tres pestañas.
  bool agrupa(String estado) => switch (this) {
    PestanaRutas.activas =>
      estado != EstadoRuta.completada && estado != EstadoRuta.enCurso,
    PestanaRutas.enCurso => estado == EstadoRuta.enCurso,
    PestanaRutas.historial => estado == EstadoRuta.completada,
  };
}

/// `estado` — el estado del pedido **en PEDIDO**, del paso 4 del asistente.
///
/// `expirada` no es un valor de la columna `orders.estado`: es una cuenta contra
/// `fechaComprometida`, y por eso vive aqui y no en `EstadoEnPedido`, que es el
/// espejo de lo que manda PEDIDO.
enum EstadoDelPedido {
  cualquiera('', 'Cualquier estado'),
  enProceso(EstadoEnPedido.enProceso, 'En proceso'),
  completada(EstadoEnPedido.completada, 'Completada'),
  expirada(expiradaParam, 'Expirada');

  const EstadoDelPedido(this.param, this.etiqueta);

  /// El literal del query param, aparte, para poder usarlo en un `switch` de
  /// constantes.
  static const expiradaParam = 'expirada';

  final String param;
  final String etiqueta;
}

/// `domicilio` — si el pedido lleva entrega a domicilio. **Arranca en `1`**
/// (pliego §3, paso 4): una ruta se arma con lo que hay que llevar a casa.
enum DomicilioFiltro {
  cualquiera('', 'Con y sin domicilio'),
  soloCon('1', 'Sólo con domicilio'),
  soloSin('0', 'Sólo sin domicilio');

  const DomicilioFiltro(this.param, this.etiqueta);

  final String param;
  final String etiqueta;
}

/// `cotizado` — si Entrega ya le puso costo de domicilio.
enum CotizadoDelDomicilio {
  cualquiera('', 'Cotizados y sin cotizar'),
  si('1', 'Ya cotizados'),
  no('0', 'Sin cotizar');

  const CotizadoDelDomicilio(this.param, this.etiqueta);

  final String param;
  final String etiqueta;
}

/// Los filtros de la columna izquierda. Se aplican **en el cliente** sobre las
/// rutas ya traidas, como en la de Next.
class FiltrosRutas {
  const FiltrosRutas({
    this.q = '',
    this.vehiculoId = '',
    this.ubicacionSalida = '',
    this.desde,
    this.hasta,
  });

  /// LA MARCA DE «LAS QUE NO TIENEN PUNTO DE PARTIDA».
  ///
  /// `ubicacionSalida` guarda el texto del origen tal cual, asi que hace falta
  /// un valor que NINGUNA direccion pueda tener para poder pedir justo las que
  /// no lo tienen. Una cadena vacia no sirve: esa ya significa «cualquiera».
  ///
  /// Y esas rutas tienen que poder pedirse. Sin esta opcion, una ruta sin
  /// origen solo se ve en «cualquier ubicacion» y desaparece en cuanto alguien
  /// filtra — eso es descartar trabajo en silencio, que es lo que prohibe el
  /// §4 del CLAUDE.md. Ademas es justo el caso que hay que arreglar: una ruta
  /// sin punto de partida no se puede medir.
  static const sinPuntoDePartida = '\u0000sin-punto-de-partida';

  final String q;
  final String vehiculoId;

  /// DE DONDE SALIO, tal cual lo escribe la tarjeta (`routes.origin_address`).
  ///
  /// Jose, 28/09/2026: «en las rutas añadir tambien el filtro por la ubicacion
  /// q salio para saber de donde saiioo sin necesidad de estar viendo todas
  /// juntas».
  ///
  /// **Es el TEXTO del origen y no el id de un almacen, y no es un descuido.**
  /// `routes` no guarda de que almacen salio: el asistente escribe
  /// `origenDireccion: _salida?.direccion ?? _salida?.nombre`
  /// (`vista/asistente_nueva_ruta.dart`), o sea el texto, y lo que baja del
  /// servidor trae ese mismo campo y nada mas. Cruzarlo contra `warehouses`
  /// para filtrar por id tendria dos agujeros, los dos de los que dejan datos
  /// fuera sin decirlo:
  ///
  ///  * un almacen renombrado o retirado deja sus rutas viejas con el texto
  ///    antiguo, y esas rutas se volverian **imposibles de pedir**;
  ///  * y al reves, un almacen recien dado de alta saldria en la lista sin
  ///    ninguna ruta detras, o sea una opcion que no filtra nada.
  ///
  /// Filtrando por el texto, lo que se elige es exactamente lo que se lee en
  /// la tarjeta, y cada opcion tiene al menos una ruta detras. El dia que
  /// `routes` guarde el almacen de salida, esto se cambia — y entonces habra
  /// que migrar lo viejo, no antes.
  final String ubicacionSalida;

  final DateTime? desde;
  final DateTime? hasta;

  bool get hayAlguno =>
      q.isNotEmpty ||
      vehiculoId.isNotEmpty ||
      ubicacionSalida.isNotEmpty ||
      desde != null ||
      hasta != null;

  /// Copiar cambiando lo justo.
  ///
  /// Estaba escrito a pelo en los cuatro controles de la barra —cada uno
  /// rehacia el objeto entero repitiendo los otros tres campos—, y con el
  /// quinto filtro eso deja de ser legible: basta olvidarse de uno para que
  /// **elegir una fecha borre la ubicacion** sin que salte nada. Es el mismo
  /// molde que ya usa `FiltrosDisponibles` del paso 4.
  ///
  /// Los `limpiar…` hacen falta porque `null` aqui es indistinguible de «no lo
  /// toques»: sin ellos no habria forma de QUITAR una fecha.
  FiltrosRutas copiarCon({
    String? q,
    String? vehiculoId,
    String? ubicacionSalida,
    DateTime? desde,
    bool limpiarDesde = false,
    DateTime? hasta,
    bool limpiarHasta = false,
  }) => FiltrosRutas(
    q: q ?? this.q,
    vehiculoId: vehiculoId ?? this.vehiculoId,
    ubicacionSalida: ubicacionSalida ?? this.ubicacionSalida,
    desde: limpiarDesde ? null : (desde ?? this.desde),
    hasta: limpiarHasta ? null : (hasta ?? this.hasta),
  );
}

/// UNA UBICACION DE SALIDA DE LAS QUE HAY, con cuantas rutas salieron de ella.
///
/// Sale de las propias rutas (ver [ubicacionesDeSalidaDe]), no del catalogo de
/// almacenes, y por eso la cuenta va pegada: un desplegable que dice
/// «PV-STGO 12» contesta de un vistazo la pregunta de Jose —de donde salieron—
/// sin tener que elegir para averiguarlo.
class UbicacionDeSalida {
  const UbicacionDeSalida({required this.clave, required this.rutas});

  /// Lo que se guarda en `FiltrosRutas.ubicacionSalida`: el texto del origen,
  /// o [FiltrosRutas.sinPuntoDePartida] para las que no tienen.
  final String clave;

  /// Cuantas rutas salieron de aqui.
  final int rutas;

  bool get esSinPuntoDePartida => clave == FiltrosRutas.sinPuntoDePartida;

  /// Lo que se lee en el desplegable. Para las que no tienen origen es la
  /// MISMA frase que ya pinta la tarjeta (`lista_rutas.dart`): dos maneras de
  /// decir lo mismo en la misma pantalla es lo que hace dudar de si son dos
  /// cosas distintas.
  String get etiqueta => esSinPuntoDePartida ? 'Sin punto de partida' : clave;
}

/// LAS UBICACIONES DE SALIDA QUE HAY EN UNAS RUTAS, ordenadas y con su cuenta.
///
/// Suelta y sin providers a proposito: asi se puede probar la regla —que no se
/// pierde ninguna, que las de sin origen van juntas y al final, y que el orden
/// no depende de en que orden vinieran las rutas— sin montar una pantalla.
///
/// El orden es alfabetico y **sin distinguir mayusculas**, que es como se lee
/// una lista de sitios; las que no tienen origen van SIEMPRE las ultimas,
/// porque no son un sitio y mezcladas por la «S» de «Sin» estarian en medio.
List<UbicacionDeSalida> ubicacionesDeSalidaDe(List<Ruta> rutas) {
  final cuentas = <String, int>{};
  var sinOrigen = 0;
  for (final ruta in rutas) {
    final origen = (ruta.originAddress ?? '').trim();
    if (origen.isEmpty) {
      sinOrigen++;
      continue;
    }
    cuentas[origen] = (cuentas[origen] ?? 0) + 1;
  }
  final claves = cuentas.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [
    for (final clave in claves)
      UbicacionDeSalida(clave: clave, rutas: cuentas[clave]!),
    if (sinOrigen > 0)
      UbicacionDeSalida(
        clave: FiltrosRutas.sinPuntoDePartida,
        rutas: sinOrigen,
      ),
  ];
}

/// Una ruta con lo que la tarjeta y el detalle necesitan, ya resuelto.
class RutaConTodo {
  const RutaConTodo({
    required this.ruta,
    required this.paradas,
    this.vehiculo,
    this.sucursal,
  });

  final Ruta ruta;

  /// Las paradas son los pedidos con `routeId = ruta.id` **o** los que la
  /// soltaron CON un resultado (`routeId` nulo, `ultimaRutaId = ruta.id` y
  /// `resultado` puesto). Lo que no se entrega suelta su `routeId` para poder ir
  /// en la ruta de manana, y si solo se mirara esa columna desapareceria de su
  /// propia hoja de cierre en cuanto se marcara como devuelto.
  ///
  /// **Y el `resultado` no es un adorno**: un pedido QUITADO de la ruta tambien
  /// tiene `routeId` nulo, y lo unico que lo distingue de un devuelto es que
  /// nunca bajo del camion y por eso no tiene resultado. Sin esa condicion la
  /// parada quitada seguia saliendo en la hoja (la parada fantasma de Amado,
  /// 07/10/2026). Lo repiten `paradasDe`, `mirarParadasDe` y el `cerrar` de
  /// `AccionesDeRuta`; las tres se atan con una prueba.
  final List<Pedido> paradas;

  final Vehiculo? vehiculo;
  final Sucursal? sucursal;

  double get pesoTotal => paradas.fold<double>(0, (suma, p) => suma + p.weight);

  bool get sobrepeso {
    final capacidad = vehiculo?.capacity;
    return capacidad != null && pesoTotal > capacidad;
  }

  int get sinMarcar => paradas.where((p) => p.resultado == null).length;
}

class ConsultasRutas {
  ConsultasRutas(this._base) : _pedidos = ConsultasPedidos(_base);

  final BaseLocal _base;
  final ConsultasPedidos _pedidos;

  /// 20 por pagina, en el cliente. Lo fija el pliego (§9.7).
  static const porPagina = 20;

  /// Todas las rutas del alcance, de la mas nueva a la mas vieja.
  Stream<List<Ruta>> rutas({String? sucursalId}) {
    final consulta = _base.select(_base.routes)
      ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]);
    if (sucursalId != null && sucursalId.isNotEmpty) {
      consulta.where((r) => r.branchId.equals(sucursalId));
    }
    return consulta.watch();
  }

  /// Una ruta con sus paradas, su vehiculo y su sucursal.
  Stream<RutaConTodo?> rutaConTodo(String rutaId) {
    final consulta = _base.select(_base.routes)
      ..where((r) => r.id.equals(rutaId));
    return consulta.watchSingleOrNull().asyncMap((ruta) async {
      if (ruta == null) return null;
      return RutaConTodo(
        ruta: ruta,
        paradas: await paradasDe(rutaId),
        vehiculo: await _vehiculo(ruta.vehicleId),
        sucursal: await _sucursal(ruta.branchId),
      );
    });
  }

  Future<List<Pedido>> paradasDe(String rutaId) {
    final consulta = _base.select(_base.orders)
      ..where(
        (o) =>
            o.routeId.equals(rutaId) |
            (o.routeId.isNull() &
                o.ultimaRutaId.equals(rutaId) &
                o.resultado.isNotNull()),
      )
      ..orderBy([
        (o) => OrderingTerm.asc(o.stopOrder),
        (o) => OrderingTerm.asc(o.customerName),
      ]);
    return consulta.get();
  }

  /// CUANTAS PARADAS LLEVA CADA RUTA, todas de una vez.
  ///
  /// La lista de rutas lo enseña en cada tarjeta —«2 paradas · 68.0 km»,
  /// igual que el patrón—, y son **una consulta agrupada, no una por
  /// tarjeta**: con veinte rutas en pantalla, veinte `watch` sobre la misma
  /// tabla es veinte veces el mismo trabajo cada vez que cambia un pedido.
  ///
  /// Se cuenta por `ultimaRutaId` y no por `routeId`, por lo mismo que las
  /// paradas del detalle: lo que no se entrega suelta su `routeId` para poder
  /// ir en la ruta de mañana, y contando esa columna una ruta cerrada iría
  /// perdiendo paradas según se marcan los devueltos.
  Stream<Map<String, int>> paradasPorRuta() {
    final cuantas = _base.orders.id.count();
    final consulta = _base.selectOnly(_base.orders)
      ..addColumns([_base.orders.ultimaRutaId, cuantas])
      ..where(_base.orders.ultimaRutaId.isNotNull())
      ..groupBy([_base.orders.ultimaRutaId]);
    return consulta.watch().map(
      (filas) => <String, int>{
        for (final fila in filas)
          fila.read(_base.orders.ultimaRutaId)!: fila.read(cuantas) ?? 0,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // EN QUE ANDA CADA CAMION — 28/09/2026
  // ---------------------------------------------------------------------------
  //
  // Jose: «si la idea es q salga el vehiculo y ese vehiculo se ponga su estado
  // para q saber como anda ese vehiculo y saber de la flota».
  //
  // Devuelve, por camion, **la ruta abierta que lo tiene cogido**. Es la misma
  // cuenta que hace el servidor en `db/queries/vehicles.sql`
  // (`RutasAbiertasDeLaFlota`) y por la misma razon: `vehicles.status` es un
  // campo que alguien pone y alguien tiene que quitar, y se queda en `in_use`
  // en cuanto una ruta se cierra por otro camino.
  //
  // Aqui sirve para lo que la lista y la ficha de una ruta no podian decir: si
  // el camion de ESTA ruta esta ademas metido en OTRA. Eso es un conflicto de
  // verdad —dos rutas planificadas con el mismo camion el mismo dia— y hasta hoy
  // no se veia por ningun sitio: la tarjeta pintaba el nombre y la matricula y
  // se acababa ahi.
  //
  // VA POR STREAM y no por `Future` (CLAUDE.md §3-ter): en la web la base nace
  // vacia en cada carga y la bajada llega un segundo despues, asi que una sola
  // respuesta se queda congelada diciendo que no hay ninguna.
  //
  // EL ORDEN, que es el que decide cual gana si hay dos: primero la que esta EN
  // CURSO —esa es la que tiene el camion fuera ahora mismo—, y entre
  // planificadas la del dia mas proximo. Sin eso, una planificada de la semana
  // que viene taparia la que esta rodando hoy. Calcado del `ORDER BY` del
  // servidor.
  Stream<Map<String, RutaQueOcupa>> camionesOcupados() {
    final consulta = _base.select(_base.routes)
      ..where(
        (r) =>
            r.vehicleId.isNotNull() &
            r.status.isNotIn([EstadoRuta.completada, EstadoRuta.cancelada]),
      )
      ..orderBy([
        // `in_progress` primero. Drift no tiene un `CASE` comodo aqui, asi que
        // se ordena por el texto del estado: `in_progress` < `planned` en
        // alfabetico, que da justo el orden que hace falta. Si alguna vez se
        // añade un estado abierto nuevo, esto hay que volver a mirarlo — y por
        // eso lo vigila una prueba, no este comentario (§3-bis).
        (r) => OrderingTerm.asc(r.status),
        (r) => OrderingTerm.asc(r.deliveryDate),
        (r) => OrderingTerm.asc(r.createdAt),
      ]);
    return consulta.watch().map((filas) {
      final porCamion = <String, RutaQueOcupa>{};
      for (final r in filas) {
        final camion = r.vehicleId;
        if (camion == null) continue;
        // La primera que llega gana: la lista ya viene en el orden bueno.
        porCamion.putIfAbsent(
          camion,
          () => RutaQueOcupa(
            rutaId: r.id,
            codigo: r.routeCode,
            nombre: r.name,
            estado: r.status,
          ),
        );
      }
      return porCamion;
    });
  }

  /// Paradas actuales y las ya soltadas por devolución/cancelación que siguen
  /// perteneciendo al historial de esta ruta. Las QUITADAS no: ver
  /// [RutaConTodo.paradas].
  Stream<List<Pedido>> mirarParadasDe(String rutaId) {
    final consulta = _base.select(_base.orders)
      ..where(
        (o) =>
            o.routeId.equals(rutaId) |
            (o.routeId.isNull() &
                o.ultimaRutaId.equals(rutaId) &
                o.resultado.isNotNull()),
      )
      ..orderBy([
        (o) => OrderingTerm.asc(o.stopOrder),
        (o) => OrderingTerm.asc(o.customerName),
      ]);
    return consulta.watch();
  }

  Future<Vehiculo?> _vehiculo(String? id) async => id == null
      ? null
      : (await (_base.select(
          _base.vehicles,
        )..where((v) => v.id.equals(id))).getSingleOrNull());

  Future<Sucursal?> _sucursal(String? id) async => id == null
      ? null
      : (await (_base.select(
          _base.branches,
        )..where((b) => b.id.equals(id))).getSingleOrNull());

  Stream<List<Vehiculo>> vehiculos({String? sucursalId}) {
    final consulta = _base.select(_base.vehicles)
      ..orderBy([(v) => OrderingTerm.asc(v.name)]);
    if (sucursalId != null && sucursalId.isNotEmpty) {
      consulta.where((v) => v.branchId.equals(sucursalId));
    }
    return consulta.watch();
  }

  Stream<List<Sucursal>> sucursales() => (_base.select(
    _base.branches,
  )..orderBy([(b) => OrderingTerm.asc(b.name)])).watch();

  /// Los almacenes de una sucursal, **el principal primero**: es el punto de
  /// partida por defecto y el origen desde el que se mide todo.
  Future<List<Almacen>> almacenesDe(String sucursalCodigo) {
    final consulta = _base.select(_base.warehouses)
      ..where(
        (a) => a.sucursalCodigo.equals(sucursalCodigo) & a.activo.equals(true),
      )
      ..orderBy([
        (a) => OrderingTerm.desc(a.principal),
        (a) => OrderingTerm.asc(a.nombre),
      ]);
    return consulta.get();
  }

  /// Los pedidos que se pueden meter en una ruta.
  ///
  /// Las condiciones fijas son las del servidor y **no son negociables**:
  /// `source='pedido'`, sin ruta, con coordenadas de entrega y facturado. El
  /// filtro de factura de la pantalla NO es configurable: siempre `cuadra`
  /// (`facturaEstado = 'igual'`), que es lo unico que el armado del servidor
  /// acepta —`cambiado` no entra: «en el camion solo sube lo que cuadra con la
  /// factura», Jose, 07/10/2026—. Y desde el 07/10/2026 (Amado, incidencias 2 y
  /// 6) tambien el domicilio cobrado (`facturaDomicilio > 0`) y cotizado en
  /// Entrega (`pedidoCosto` no nulo). Ofrecer aqui lo que alli se rechaza es
  /// fabricar rechazos tardios.
  /// [estado], [domicilio] y [cotizado] llevan **los mismos valores que los
  /// query params del servidor** (`contratos-api.md`, «Filtros compartidos»):
  /// `''` es sin filtro. Se escriben asi, como texto, y no como enums propios,
  /// para que la prueba de paridad pueda mandar la misma cadena a las dos.
  ///
  /// [ahora] entra por parametro porque `en_proceso` y `expirada` se deciden
  /// contra la hora: leyendo el reloj aqui dentro la consulta daria un resultado
  /// distinto cada vez que se llama y no habria forma de probarla.
  Future<List<Pedido>> disponibles({
    String? sucursalId,
    String q = '',
    String municipio = '',
    String vendedor = '',
    String estado = '',
    String domicilio = '',
    String cotizado = '',
    DateTime? dia,
    double? kmMax,
    double? costoMin,
    DateTime? ahora,
  }) async {
    final o = _base.orders;
    Expression<bool> donde =
        o.source.equals(Procedencia.pedido) &
        o.routeId.isNull() &
        o.endLat.isNotNull() &
        o.endLng.isNotNull() &
        o.facturaEstado.equals(EstadoFactura.igual) &
        o.facturaDomicilio.isBiggerThanValue(0) &
        o.pedidoCosto.isNotNull();

    if (sucursalId != null && sucursalId.isNotEmpty) {
      donde = donde & o.branchId.equals(sucursalId);
    }
    if (municipio.isNotEmpty) donde = donde & o.municipio.equals(municipio);
    if (vendedor.isNotEmpty) donde = donde & o.vendedor.equals(vendedor);

    // `domicilio=0` incluye los NULL a proposito: un pedido al que nadie le dijo
    // si lleva domicilio NO lleva domicilio. Es lo que hace el servidor, y si
    // aqui se tratara el nulo como «no se sabe» las dos listas no cuadrarian.
    if (domicilio == '1') {
      donde = donde & o.requiereDomicilio.equals(true);
    } else if (domicilio == '0') {
      donde =
          donde &
          (o.requiereDomicilio.isNull() | o.requiereDomicilio.equals(false));
    }

    // Cotizado mira `pedidoCosto`, y **un nulo no es un cero**: cero es un precio
    // puesto (un domicilio gratis) y nulo es que Entrega todavia no lo puso.
    if (cotizado == '1') {
      donde = donde & o.pedidoCosto.isNotNull();
    } else if (cotizado == '0') {
      donde = donde & o.pedidoCosto.isNull();
    }

    if (estado.isNotEmpty) {
      // `noCompletada` cuenta los NULL: un pedido sin estado sigue siendo un
      // pedido por entregar, y dejarlo fuera lo haria invisible para rutear.
      final noCompletada =
          o.estado.isNull() | o.estado.equals(EstadoEnPedido.completada).not();
      final cuando = ahora ?? DateTime.now();
      donde =
          donde &
          switch (estado) {
            EstadoEnPedido.completada => o.estado.equals(
              EstadoEnPedido.completada,
            ),
            EstadoEnPedido.enProceso =>
              noCompletada &
                  (o.fechaComprometida.isNull() |
                      o.fechaComprometida.isBiggerOrEqualValue(cuando)),
            EstadoDelPedido.expiradaParam =>
              noCompletada & o.fechaComprometida.isSmallerThanValue(cuando),
            // Un valor que no conocemos no filtra nada: mas vale ensenar de mas que
            // esconder pedidos por una cadena que alguien escribio mal.
            _ => const Constant(true),
          };
    }

    final busca = q.trim().toLowerCase();
    if (busca.isNotEmpty) {
      donde =
          donde &
          (o.customerName.lower().contains(busca) |
              o.operationNumber.lower().contains(busca) |
              o.endAddress.lower().contains(busca) |
              o.address.lower().contains(busca));
    }
    if (dia != null) {
      // Un dia natural completo, igual que el servidor.
      final inicio = DateTime(dia.year, dia.month, dia.day);
      final fin = inicio.add(const Duration(days: 1));
      donde =
          donde &
          ((o.orderDate.isBiggerOrEqualValue(inicio) &
                  o.orderDate.isSmallerThanValue(fin)) |
              (o.orderDate.isNull() &
                  o.createdAt.isBiggerOrEqualValue(inicio) &
                  o.createdAt.isSmallerThanValue(fin)));
    }

    final consulta = _base.select(_base.orders)
      ..where((_) => donde)
      ..orderBy([
        (o) => OrderingTerm.desc(o.orderDate),
        (o) => OrderingTerm.desc(o.createdAt),
      ]);
    final filas = await consulta.get();

    return [
      for (final pedido in filas)
        // `kmMax` y `costoMin` se filtran despues de la consulta, igual que en el
        // servidor. Un pedido SIN distancia medida nunca se descarta: no saber
        // cuan lejos esta no es lo mismo que estar lejos.
        if (!(kmMax != null &&
                pedido.deliveryDistanceKm != null &&
                pedido.deliveryDistanceKm! > kmMax) &&
            !(costoMin != null &&
                _conCeroParaCostoMin(pedido.pedidoCosto) < costoMin))
          pedido,
    ];
  }

  /// Los renglones de unos pedidos, con el peso por empaque ya resuelto. Se
  /// reutiliza el de Pedidos: la carga del camion y el pre-despacho tienen que
  /// contar igual en las dos pantallas.
  Future<Map<String, List<RenglonConPeso>>> renglonesDe(List<String> ids) =>
      _pedidos.renglonesDe(ids);
}

/// EL `?? 0` DE `costoMin`, QUE ES UN CONTRATO Y NO UN DESCUIDO.
///
/// Un pedido sin cotizar cuenta como CERO para «costo mínimo», así que con
/// `costoMin = 10` se cae. Eso **descarta trabajo sin decirlo**, que es justo lo
/// que prohíbe el `CLAUDE.md` §4, y por eso se miró en serio el 23/09/2026. No
/// se cambia, y el motivo es que **no es una decisión de este fichero**:
///
///  * el servidor hace exactamente esto, y lo tiene razonado:
///    `if hayCostoMin && conCero(x.PedidoCosto) < costoMin` en
///    `api/internal/api/pedidos.go:544` — «`costoMin` es "enséñame lo que valga
///    la pena mover", y un pedido sin cotizar no lo vale todavía»;
///  * está escrito en el contrato: `docs/contratos-api.md:423`, «Descarta si
///    `(pedidoCosto ?? 0) < costoMin`»;
///  * y está atado por una prueba del otro lado,
///    `TestDisponiblesCostoMinCuentaElSinCotizarComoCero`.
///
/// Cambiarlo **sólo aquí** parte en dos la misma pregunta: la web pide la lista
/// al servidor y la APK la calcula con esto, así que el mismo filtro daría dos
/// listas distintas en los dos aparatos de la misma persona y nadie vería saltar
/// nada (`CLAUDE.md` §3-bis). Si hay que cambiarlo se cambia a la vez el
/// servidor, el contrato, su prueba en Go y ésta.
///
/// **Lo que sigue faltando**, y es la mitad que sí es deuda: el paso 4 del
/// asistente no dice cuántos se cayeron por no estar cotizados. El servidor ya
/// manda el `total` de antes de estos dos filtros (`docs/contratos-api.md:431`),
/// así que el número para decirlo ya existe; falta pintarlo, y eso es de
/// `vista/asistente_nueva_ruta.dart`, que no es de esta ola.
double _conCeroParaCostoMin(double? costo) => costo ?? 0;

/// Los filtros de la lista, aplicados en el cliente.
List<Ruta> filtrarRutas(
  List<Ruta> rutas,
  FiltrosRutas filtros, {
  required Map<String, Vehiculo> vehiculos,
  required Map<String, Sucursal> sucursales,
}) {
  final busca = filtros.q.trim().toLowerCase();
  return [
    for (final ruta in rutas)
      if (_cuadra(ruta, filtros, busca, vehiculos, sucursales)) ruta,
  ];
}

bool _cuadra(
  Ruta ruta,
  FiltrosRutas filtros,
  String busca,
  Map<String, Vehiculo> vehiculos,
  Map<String, Sucursal> sucursales,
) {
  if (filtros.vehiculoId.isNotEmpty && ruta.vehicleId != filtros.vehiculoId) {
    return false;
  }
  // DE DONDE SALIO. Se compara con el texto YA RECORTADO por los dos lados,
  // igual que lo recorta `ubicacionesDeSalidaDe` al armar las opciones: si una
  // capa recorta y la otra no, `PV-STGO ` no cuadraria con `PV-STGO` y el
  // desplegable ofreceria una opcion que no devuelve nada. Es el §3-bis —dos
  // sitios que tienen que contestar lo mismo— en pequeño.
  final queSalida = filtros.ubicacionSalida;
  if (queSalida.isNotEmpty) {
    final salida = (ruta.originAddress ?? '').trim();
    if (queSalida == FiltrosRutas.sinPuntoDePartida) {
      if (salida.isNotEmpty) return false;
    } else if (salida != queSalida) {
      return false;
    }
  }
  final creada = ruta.createdAt;
  if (filtros.desde != null && creada != null) {
    final inicio = DateTime(
      filtros.desde!.year,
      filtros.desde!.month,
      filtros.desde!.day,
    );
    if (creada.isBefore(inicio)) return false;
  }
  if (filtros.hasta != null && creada != null) {
    // `hasta` incluye el dia entero: si no, filtrar «hasta hoy» deja fuera lo de
    // hoy y parece que no hay rutas.
    final fin = DateTime(
      filtros.hasta!.year,
      filtros.hasta!.month,
      filtros.hasta!.day,
      23,
      59,
      59,
      999,
    );
    if (creada.isAfter(fin)) return false;
  }
  if (busca.isEmpty) return true;

  final donde = [
    ruta.routeCode ?? '',
    ruta.name ?? '',
    ruta.originAddress ?? '',
    vehiculos[ruta.vehicleId]?.name ?? '',
    sucursales[ruta.branchId]?.name ?? '',
  ].join(' ').toLowerCase();
  return donde.contains(busca);
}

/// La ruta ABIERTA que tiene cogido a un camion. Ver `ConsultasRutas.camionesOcupados`.
class RutaQueOcupa {
  const RutaQueOcupa({
    required this.rutaId,
    required this.estado,
    this.codigo,
    this.nombre,
  });

  final String rutaId;

  /// `routes.status`: `planned` o `in_progress`. Las cerradas no llegan aqui.
  final String estado;
  final String? codigo;
  final String? nombre;

  /// Esta rodando AHORA. Lo otro es «lo tiene cogido, pero no ha salido».
  bool get enCurso => estado == EstadoRuta.enCurso;

  /// Como se nombra en una linea: el codigo si lo hay, si no el nombre.
  String get titulo {
    final c = codigo?.trim();
    if (c != null && c.isNotEmpty) return c;
    final n = nombre?.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'otra ruta';
  }
}
