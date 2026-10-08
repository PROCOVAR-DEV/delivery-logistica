// El repositorio de Pedidos.
//
// **Lee de la base local y NUNCA de la red.** Esa es la regla que sostiene el
// dia sin conexion: la pantalla mira Drift, y si hay red el sincronizador
// escribe por detras y las consultas vuelven a emitir solas. No hay un camino
// alternativo «si hay internet pide al servidor», porque tener dos caminos es
// tener dos comportamientos y sólo uno probado.
//
// El `WHERE` es el MISMO de `../../../../docs/contratos-api.md`
// («Filtros compartidos de pedido»), traducido a Drift. Cualquier diferencia
// aqui sale como un numero distinto en la prueba de paridad contra la de Next.

import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import 'filtros_pedidos.dart';

/// Una linea del pre-despacho: cuanto hay que sacar del almacen de cada
/// producto.
class LineaPreDespacho {
  const LineaPreDespacho({
    required this.producto,
    required this.empaques,
    required this.unidades,
    this.pesoKg,
    this.lineasSinUnidades = 0,
    this.lineasSinPeso = 0,
  });

  final String producto;
  final double empaques;

  /// CUÁNTAS LÍNEAS DE ESTE PRODUCTO NO TRAEN EL DATO, y por qué se cuentan en
  /// vez de borrar el número — 28/09/2026, por la tarde.
  ///
  /// Por la mañana la regla era: falta una, se borra el producto entero. Nació
  /// bien —un total corto que parece completo es el fallo más caro de esta
  /// casa— y en cuanto salió a producción se vio lo bruto que era: **21 líneas
  /// de 1.149 dejaban sin kg una fila de 4.949 empaques** de MALTA GUAJIRA, que
  /// es el producto que más se mueve. Jose, mirando la hoja: «por q me siguen
  /// saliendo cosas sin nada por q razon».
  ///
  /// Y no se va a arreglar solo llenando datos: la sesión de PEDIDO comprobó
  /// contra Ventra que **de 129 productos sólo 57 traen peso**. Los otros 72
  /// vienen vacíos de verdad, así que con la regla de la mañana media hoja se
  /// quedaba en blanco para siempre.
  ///
  /// La salida no es relajar la regla, es **decir la verdad entera**: se enseña
  /// lo que sí se sabe marcado como MÍNIMO —`≥ 26.320,0 kg`— y al lado cuántas
  /// líneas faltan. Un `≥` no se puede leer como un total completo, que es lo
  /// único que el §3 prohíbe, y en cambio sí sirve para cargar un camión:
  /// «pesa por lo menos esto» es una decisión que alguien puede tomar; una raya
  /// no lo es.
  final int lineasSinUnidades;
  final int lineasSinPeso;

  /// Si el número de arriba es el de TODAS las líneas o sólo el de las que lo
  /// traen. Es lo que decide el `≥` de la pantalla.
  bool get pesoCompleto => lineasSinPeso == 0;
  bool get unidadesCompletas => lineasSinUnidades == 0;

  /// Las unidades sueltas que hay dentro de esos empaques: **la `quantity` de
  /// cada renglón del pedido**, cuando es de fiar.
  ///
  /// Esto salía del catálogo —`empaques × unitsPerPackage`— y en producción el
  /// catálogo no lo dice de ningún producto, así que la columna entera era una
  /// raya: Jose, 28/09/2026, mirando la hoja de pre-despacho, «sigo sin ver
  /// peso y sin ver unidades». Un dato que nunca sale no es una cautela, es una
  /// columna vacía.
  ///
  /// El dato sí está, y está en el propio pedido, que es de donde tiene que
  /// salir: lo manda Ventra renglón a renglón. Lo que había que conservar del
  /// 22/09/2026 —«SERVILLETA PROSITO PACA 24P · 7 empaques · 4 unidades»— es
  /// que `quantity` no SIEMPRE son unidades; ver [Repositorio] y su predicado,
  /// que deja esas líneas fuera de la suma y las cuenta en [lineasSinUnidades],
  /// para que lo que salga sea `≥ 600` y no un total de sólo algunas.
  final double? unidades;

  /// **El peso que el servidor resolvió para cada renglón** (`peso_linea_kg`),
  /// sumado por producto. Salía del catálogo local —`empaques ×
  /// products.weight`— y por eso la columna estaba en blanco: ese catálogo no
  /// trae el peso de nadie, mientras que 7.650 de las 7.738 líneas de
  /// producción sí lo traen. La cascada que lo resuelve es UNA y está en
  /// `PesosDeRenglones` (`api/internal/cotizar/pesos.go`); aquí sólo se suma.
  ///
  /// Es la suma de las líneas que SÍ lo traen, y [lineasSinPeso] dice cuántas
  /// no: por eso la columna lo pinta con un `≥` delante mientras ese contador
  /// no sea cero. `null` sólo cuando no lo trae ninguna, y entonces la columna
  /// pinta `—`. **Nunca cero**: cero se lee como «no pesa», y en la hoja del
  /// almacén ése es otro error.
  final double? pesoKg;
}

/// Los totales del bloque de pre-despacho.
class TotalesPreDespacho {
  const TotalesPreDespacho(
    this.lineas, {
    this.pedidos = 0,
    this.pesoDeLosPedidos = 0,
  });

  final List<LineaPreDespacho> lineas;

  /// Cuantos pedidos entraron en esta suma. Es el `<n> pedido(s)` de la cabecera
  /// de la hoja impresa.
  final int pedidos;

  /// El peso del CONJUNTO de pedidos, que es el `<n.n> kg` de la cabecera de la
  /// hoja. **No es la suma de [pesoKg] por producto**: la de Next imprime el
  /// peso de los pedidos, y un producto sin peso resuelto no suma nada ahi
  /// aunque el pedido si pese.
  final double pesoDeLosPedidos;

  int get productos => lineas.length;
  double get empaques => lineas.fold(0, (suma, linea) => suma + linea.empaques);

  /// LO QUE SE SABE, SUMADO; Y APARTE, CUÁNTO FALTA POR SABER.
  ///
  /// El incidente que dio la regla sigue en pie y es el del 22/09/2026: la
  /// franja decía «10 producto(s) · 3185 empaques · **0.0 kg**» mientras la hoja
  /// imprimible del mismo filtro decía «264 pedido(s) · **24891.0 kg**». Los dos
  /// números eran ciertos cada uno en su definición y juntos sólo podían hacer
  /// una cosa: que quien carga el camión se crea que no pesa nada.
  ///
  /// Lo que cambió el 28/09/2026 es la SALIDA, no la regla. Devolver `null` en
  /// cuanto faltara una línea dejaba media hoja en blanco —21 líneas de 1.149
  /// borraban 4.949 empaques de MALTA GUAJIRA— y no era una situación pasajera:
  /// de los 129 productos de Ventra, **sólo 57 traen peso**. Una columna que no
  /// va a salir nunca no protege a nadie.
  ///
  /// Así que la suma es de lo que hay y se acompaña de [sinPeso] /
  /// [sinUnidades], que dicen cuántas líneas quedaron fuera. La pantalla lo
  /// pinta con un `≥`, y un `≥` no se puede leer como un total completo — que es
  /// lo único que el §3 prohíbe. `null` sólo cuando no se sabe NADA.
  double? get unidades => _suma((l) => l.unidades);
  double? get pesoKg => _suma((l) => l.pesoKg);

  /// Cuántas LÍNEAS quedaron fuera de cada suma. **Líneas, no productos**: es lo
  /// que dice de verdad cuánto falta, porque un producto con 21 líneas huérfanas
  /// de 1.149 y otro con las 6 que tiene no son el mismo agujero.
  ///
  /// Y una línea sin cifra cuenta **al menos una**, aunque venga con el contador
  /// en cero. Sin eso, unos totales armados a mano —los de una prueba, los de
  /// otro sitio que construya [LineaPreDespacho] sin contadores— sumaban
  /// `180 + nada` y lo enseñaban como `180.0 kg` **sin el `≥`**: una suma a
  /// medias presentada como completa, que es exactamente lo único que esto
  /// tiene que impedir. Misma regla que en el papel (`faltan`, en
  /// `impresion/hoja.dart`), y lo que las ata es
  /// `test/impresion/los_dos_pesos_del_pre_despacho_test.dart`.
  int get sinPeso => lineas.fold(
    0,
    (n, l) => n + _faltan(l.lineasSinPeso, hayCifra: l.pesoKg != null),
  );
  int get sinUnidades => lineas.fold(
    0,
    (n, l) => n + _faltan(l.lineasSinUnidades, hayCifra: l.unidades != null),
  );

  /// Si lo de arriba es el total o un mínimo.
  bool get pesoCompleto => sinPeso == 0;
  bool get unidadesCompletas => sinUnidades == 0;

  /// El gemelo de `faltan` del papel, escrito aquí porque esta capa no depende
  /// de la de impresión. Que los dos digan lo mismo lo comprueba una prueba.
  int _faltan(int contados, {required bool hayCifra}) {
    if (contados > 0) return contados;
    return hayCifra ? 0 : 1;
  }

  double? _suma(double? Function(LineaPreDespacho) de) {
    double? suma;
    for (final linea in lineas) {
      final valor = de(linea);
      if (valor == null) continue;
      suma = (suma ?? 0) + valor;
    }
    return suma;
  }
}

/// Una opcion de faceta con su conteo: `Camagüey` · `312`.
class OpcionFaceta {
  const OpcionFaceta(this.valor, this.pedidos);

  final String valor;
  final int pedidos;
}

/// Lo que llena los dos selectores de municipio y vendedor.
class Facetas {
  const Facetas({required this.municipios, required this.vendedores});

  static const vacias = Facetas(municipios: [], vendedores: []);

  final List<OpcionFaceta> municipios;
  final List<OpcionFaceta> vendedores;
}

/// Un renglon del pedido con su peso YA RESUELTO POR EL SERVIDOR.
///
/// ## EL PESO SE RESUELVE UNA VEZ, Y NO ES AQUI — 28/09/2026
///
/// Aqui habia una cascada de tres escalones, y otra igual en el pre-despacho, y
/// la de verdad en `PesosDeRenglones` (`api/internal/cotizar/pesos.go`, §2.1 de
/// `reglas-negocio.md`). TRES sitios contestando la misma pregunta. Jose: «era
/// mas facil ponerlo en el api y ya q lo consuman».
///
/// Y el proyecto ya estaba hecho asi: la 00004 añadio `peso_linea_kg`
/// «precisamente para no tener que recalcular el peso con el catalogo de hoy
/// sobre un pedido de hace tres meses». Los tres sitios no eran el diseño: eran
/// una desviacion suya, y por eso se desincronizaron — ese mismo dia la ficha
/// decia «40,0 kg» y la hoja del almacen ponia «—» sobre los mismos veinte
/// empaques.
///
/// Asi que el aparato **lee y no calcula**: `peso_linea_kg` es la respuesta, y
/// el servidor ya guardo en `origen_peso` de que escalon salio. El trabajo sin
/// conexion no pierde nada: el numero resuelto baja en la misma columna que ya
/// bajaba y se lee de la base local con señal o sin ella.
class RenglonConPeso {
  const RenglonConPeso(this.renglon);

  final RenglonPedido renglon;

  /// Los empaques de la linea: sus `packs` y si no los trae sus `quantity`,
  /// nunca cero (`reglas-negocio.md` §12).
  double get empaques {
    final packs = renglon.packs;
    if (packs != null && packs > 0) return packs;
    return renglon.quantity;
  }

  /// El peso de la LINEA, tal como lo resolvio el servidor.
  ///
  /// `null` = **sin peso**, y la ficha lo dice con esas palabras. Es la MISMA
  /// lectura que hace el pre-despacho (`_pesoDeLaLinea`), y que las dos
  /// contesten igual lo ata
  /// `test/pantallas/pedidos/el_peso_del_pre_despacho_cambia_de_sucursal_test.dart`.
  double? get pesoLinea => soloSiPesa(renglon.pesoLineaKg);
}

/// UN CERO NO ES UN PESO: devuelve el numero solo si es mayor que cero, y nulo
/// en cualquier otro caso.
///
/// Es el `Positivo()` del servidor (`api/internal/cotizar/pesos.go`) escrito en
/// Dart, y sigue haciendo falta aunque el servidor no escriba ceros: los
/// renglones que dejo la migracion del delivery viejo (`db/migracion/02_pedidos.sql`)
/// copian `pesoLineaKg` del JSON tal cual, cero incluido. Sin esto la celda dice
/// «0,0 kg» sobre un renglon que no se sabe lo que pesa, y un cero se suma, se
/// ordena y se lee como «no pesa nada».
double? soloSiPesa(double? kg) => kg != null && kg > 0 ? kg : null;

/// El pedido con todo lo que la ficha necesita, en una sola lectura.
class DetallePedido {
  const DetallePedido({
    required this.pedido,
    required this.renglones,
    this.ruta,
    this.vehiculo,
    this.almacen,
  });

  final Pedido pedido;
  final List<RenglonConPeso> renglones;
  final Ruta? ruta;
  final Vehiculo? vehiculo;

  /// El almacen de partida, para el mapa `Recorrido` y su pie
  /// `Del almacén (<nombre>) al cliente.`
  final Almacen? almacen;
}

class ConsultasPedidos {
  ConsultasPedidos(this._base);

  final BaseLocal _base;

  /// Lo fija el servidor y el control de tamano esta deshabilitado en la
  /// pantalla. Se deja como constante para que la paginacion local de en el
  /// aparato exactamente las mismas paginas que la de Next.
  static const porPagina = 50;

  // --------------------------------------------------------------------------
  // El WHERE
  // --------------------------------------------------------------------------

  /// Traduce los 9 filtros a SQL. Es la pieza que hay que mirar cuando un total
  /// no cuadra con el de Next.
  ///
  /// [sucursalId] no es un filtro de la pantalla: es el ALCANCE, y viene del
  /// selector de la barra superior. Va aqui y no en la pantalla para que no se
  /// pueda olvidar en una consulta.
  Expression<bool> donde(FiltrosPedidos f, {String? sucursalId}) {
    final o = _base.orders;
    // Se parte de «todo cuadra» y cada filtro puesto va estrechando. Asi el
    // caso de «ningun filtro» es el mismo camino que los demas y no una rama
    // aparte que nadie prueba.
    Expression<bool> todo = const Constant(true);

    void anadir(Expression<bool> mas) => todo = todo & mas;

    if (sucursalId != null && sucursalId.isNotEmpty) {
      anadir(o.branchId.equals(sucursalId));
    }

    final q = f.q.trim().toLowerCase();
    if (q.isNotEmpty) {
      // El mismo juego de campos que el servidor, incluido el texto de los
      // productos: quien busca «arroz» espera el pedido que lleva arroz, no sólo
      // el cliente que se apellida asi.
      final enElPedido =
          o.customerName.lower().contains(q) |
          o.operationNumber.lower().contains(q) |
          o.endAddress.lower().contains(q) |
          o.address.lower().contains(q) |
          o.municipio.lower().contains(q) |
          o.vendedor.lower().contains(q);

      final enLosProductos = o.id.isInQuery(
        _base.selectOnly(_base.orderItems)
          ..addColumns([_base.orderItems.orderId])
          ..where(_base.orderItems.description.lower().contains(q)),
      );

      anadir(enElPedido | enLosProductos);
    }

    switch (f.archivado) {
      case ArchivadoFiltro.cualquiera:
        break;
      case ArchivadoFiltro.no:
        anadir(o.archivado.equals(false));
      case ArchivadoFiltro.si:
        anadir(o.archivado.equals(true));
    }

    switch (f.cotizado) {
      case CotizadoFiltro.cualquiera:
        break;
      case CotizadoFiltro.conPrecio:
        anadir(o.pedidoCosto.isNotNull());
      case CotizadoFiltro.sinCotizar:
        anadir(o.pedidoCosto.isNull());
    }

    if (f.municipio.isNotEmpty) anadir(o.municipio.equals(f.municipio));
    if (f.vendedor.isNotEmpty) anadir(o.vendedor.equals(f.vendedor));

    switch (f.factura) {
      case FacturaFiltro.cualquiera:
        break;
      case FacturaFiltro.conFactura:
        // `con_factura` admite lo que cambio: se carga con las lineas de la
        // factura, no con las del pedido.
        anadir(
          o.facturaEstado.isIn([EstadoFactura.igual, EstadoFactura.cambiado]),
        );
      case FacturaFiltro.cuadra:
        anadir(o.facturaEstado.equals(EstadoFactura.igual));
      case FacturaFiltro.sinCotejar:
        // NULL no es `sin_factura`: NULL es «el cotejo no ha pasado por aqui».
        anadir(o.facturaEstado.isNull());
    }

    switch (f.reparto) {
      case RepartoFiltro.cualquiera:
        break;
      case RepartoFiltro.sinEntregar:
        anadir(
          o.routeId.isNull() &
              o.deliveredAt.isNull() &
              (o.resultado.isNull() |
                  o.resultado.equals(ResultadoParada.entregado).not()),
        );
      case RepartoFiltro.enDespacho:
        anadir(_enRutaCon(EstadoRuta.planificada));
      case RepartoFiltro.enRuta:
        anadir(_enRutaCon(EstadoRuta.enCurso));
      case RepartoFiltro.entregado:
        // Manda `resultado` de la parada. El `deliveredAt` entra tambien porque
        // los pedidos viejos del espejo lo tienen puesto sin resultado.
        anadir(
          o.resultado.equals(ResultadoParada.entregado) |
              o.deliveredAt.isNotNull(),
        );
      case RepartoFiltro.devuelto:
        anadir(
          o.resultado.isIn([
            ResultadoParada.devuelto,
            ResultadoParada.cancelado,
          ]),
        );
    }

    // ACOTAR POR LA FECHA DE ENTREGA, que NO es la del pedido — 28/09/2026.
    //
    // Los nueve filtros que había no podían expresar «entregados hoy»:
    // `reparto=entregado` es todo lo entregado alguna vez, sin ventana, y
    // `desde`/`hasta` acotan por la fecha DEL PEDIDO. El pedido de la queja lo
    // demuestra: `POR26-260925-3700` es del día 25 y se entregó el 28, así que
    // «del 28 al 28» lo dejaba fuera.
    //
    // Sale de que Jose no pudiera ver QUÉ se había entregado: «me dice q
    // entregado uno y en hsitorial me sale vacio eso q se entrego». El contador
    // del Panel enlaza aquí.
    final entregadoDesde = f.entregadoDesde;
    if (entregadoDesde != null) {
      // Un `delivered_at` NULO no entra: en SQL la comparación contra NULL da
      // NULL y NULL no cuadra. Es lo que se quiere —«entregado desde el 28» no
      // puede incluir lo que no se ha entregado— y es lo mismo que hace el
      // contador del Panel, que pide `delivered_at IS NOT NULL` aparte.
      anadir(
        o.deliveredAt.isBiggerOrEqualValue(
          DateTime(
            entregadoDesde.year,
            entregadoDesde.month,
            entregadoDesde.day,
          ),
        ),
      );
    }
    final entregadoHasta = f.entregadoHasta;
    if (entregadoHasta != null) {
      // El día entero, como el otro rango: sin esto, «entregado del 28 al 28»
      // no devuelve nada y se lee como «ese día no se entregó nada».
      anadir(
        o.deliveredAt.isSmallerOrEqualValue(
          DateTime(
            entregadoHasta.year,
            entregadoHasta.month,
            entregadoHasta.day,
            23,
            59,
            59,
            999,
          ),
        ),
      );
    }

    final rango = _rangoDeFechas(f);
    if (rango != null) {
      final (desde, hasta) = rango;
      // El mismo OR del servidor: un pedido sin `orderDate` se acota por la
      // fecha en que se copio, o desapareceria de todos los rangos.
      anadir(
        (o.orderDate.isBiggerOrEqualValue(desde) &
                o.orderDate.isSmallerOrEqualValue(hasta)) |
            (o.orderDate.isNull() &
                o.createdAt.isBiggerOrEqualValue(desde) &
                o.createdAt.isSmallerOrEqualValue(hasta)),
      );
    }

    return todo;
  }

  /// `en_despacho` / `en_ruta`: el pedido esta ocupado por una ruta que esta en
  /// ese estado. Va como subconsulta y no como join para que el `WHERE` sirva
  /// igual en la lista, en el conteo y en el pre-despacho.
  Expression<bool> _enRutaCon(String estadoRuta) {
    final o = _base.orders;
    return o.routeId.isNotNull() &
        o.routeId.isInQuery(
          _base.selectOnly(_base.routes)
            ..addColumns([_base.routes.id])
            ..where(_base.routes.status.equals(estadoRuta)),
        );
  }

  /// `hasta` incluye el dia entero. Sin esto, filtrar «del 3 al 3» no devuelve
  /// nada y parece que no hubo pedidos ese dia.
  (DateTime, DateTime)? _rangoDeFechas(FiltrosPedidos f) {
    final desde = f.desde;
    final hasta = f.hasta;
    if (desde == null && hasta == null) return null;
    final inicio = desde == null
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime(desde.year, desde.month, desde.day);
    final fin = hasta == null
        ? DateTime(9999)
        : DateTime(hasta.year, hasta.month, hasta.day, 23, 59, 59, 999);
    return (inicio, fin);
  }

  // --------------------------------------------------------------------------
  // Lectura
  // --------------------------------------------------------------------------

  /// Cuantos pedidos cuadran. Es el `<total> pedidos` de la cabecera y el que se
  /// compara contra el de Next.
  Stream<int> contar(FiltrosPedidos f, {String? sucursalId}) {
    final cuenta = _base.orders.id.count();
    final consulta = _base.selectOnly(_base.orders)
      ..addColumns([cuenta])
      ..where(donde(f, sucursalId: sucursalId));
    return consulta.watchSingle().map((fila) => fila.read(cuenta) ?? 0);
  }

  /// La pagina, en el orden del SERVIDOR (`orderDate desc nulls last`, luego
  /// `createdAt desc`). El orden que elige la persona se aplica despues, sobre
  /// esta lista y nada mas: ver [ordenarPagina].
  Stream<List<Pedido>> pagina(FiltrosPedidos f, {String? sucursalId}) {
    final consulta = _base.select(_base.orders)
      ..where((_) => donde(f, sucursalId: sucursalId))
      // SQLite pone los NULL al final en DESC, que es exactamente el
      // `nulls last` del servidor.
      ..orderBy([
        (o) => OrderingTerm.desc(o.orderDate),
        (o) => OrderingTerm.desc(o.createdAt),
      ])
      ..limit(porPagina, offset: (f.pagina - 1) * porPagina);
    return consulta.watch();
  }

  /// Los renglones de unos pedidos, con el peso que resolvio el SERVIDOR.
  ///
  /// Aqui habia un `leftOuterJoin` contra el catalogo local para rehacer la
  /// cascada del peso. Fuera: la cascada es una y vive en
  /// `PesosDeRenglones` (`api/internal/cotizar/pesos.go`). Ver [RenglonConPeso].
  Future<Map<String, List<RenglonConPeso>>> renglonesDe(
    List<String> pedidoIds,
  ) async {
    if (pedidoIds.isEmpty) return const {};
    final consulta = _base.select(_base.orderItems)
      ..where((r) => r.orderId.isIn(pedidoIds))
      ..orderBy([(r) => OrderingTerm.asc(r.linea)]);

    final porPedido = <String, List<RenglonConPeso>>{};
    for (final renglon in await consulta.get()) {
      porPedido
          .putIfAbsent(renglon.orderId, () => <RenglonConPeso>[])
          .add(RenglonConPeso(renglon));
    }
    return porPedido;
  }

  /// El pre-despacho de LO FILTRADO, sumado en SQL.
  ///
  /// **Sin tope.** El servidor corta en 5000 porque ahi estan los pedidos de
  /// ocho sucursales; en el aparato sólo esta la suya, asi que sumarlos todos es
  /// barato y no hay motivo para negarle el numero a nadie (PLAN.md §7.2).
  Future<TotalesPreDespacho> preDespachoDeLoFiltrado(
    FiltrosPedidos f, {
    String? sucursalId,
  }) => _preDespacho(donde(f, sucursalId: sucursalId));

  /// El pre-despacho de LO MARCADO a mano.
  Future<TotalesPreDespacho> preDespachoDe(List<String> pedidoIds) {
    if (pedidoIds.isEmpty) return Future.value(const TotalesPreDespacho([]));
    return _preDespacho(_base.orders.id.isIn(pedidoIds));
  }

  /// **Los empaques de una linea: sus `packs`, y si no los trae, sus
  /// `quantity`.** Nunca cero.
  ///
  /// Esto es la MISMA regla que [RenglonConPeso.empaques], que `armarPostDespacho`
  /// y que `reglas-negocio.md` §12, y no estaba aqui: el pre-despacho sumaba
  /// `SUM(packs)` a secas, asi que un producto cuya linea viene sin empaques
  /// contaba **0** y **la hoja del almacen salia corta** — se cargan menos cajas
  /// de las que hay que cargar, y eso no se descubre hasta que el camion ya se
  /// fue. Un cero ahi no es un dato: es una mentira con forma de numero.
  ///
  /// `CASE WHEN packs > 0` cubre tambien el `packs` nulo: en SQL una condicion
  /// nula no es cierta, asi que cae al `ELSE` igual que el `> 0` de Dart.
  Expression<double> get _empaquesDeLaLinea => CaseWhenExpression<double>(
    cases: <CaseWhen<bool, double>>[
      CaseWhen(
        _base.orderItems.packs.isBiggerThanValue(0),
        then: _base.orderItems.packs,
      ),
    ],
    orElse: _base.orderItems.quantity,
  );

  /// **EL PESO DE UNA LINEA: EL QUE RESOLVIO EL SERVIDOR, Y NADA MAS** —
  /// 28/09/2026.
  ///
  /// ## AQUI HABIA UNA CASCADA, Y ERA LA TERCERA COPIA DE LA MISMA
  ///
  /// Esto miraba `peso_linea_kg`, luego `peso_kg × empaques` y luego el catalogo
  /// local. La ficha del pedido hacia lo mismo por su cuenta, y la de verdad
  /// estaba en el servidor: `PesosDeRenglones`
  /// (`api/internal/cotizar/pesos.go`, §2.1 de `reglas-negocio.md`). Tres sitios
  /// para una sola pregunta, y por eso se separaron — la ficha decia «40,0 kg»
  /// y esta hoja ponia «—» sobre los mismos veinte empaques.
  ///
  /// Jose, el mismo dia: «era mas facil ponerlo en el api y ya q lo consuman una
  /// cada uno». Y el proyecto ya estaba hecho asi desde la 00004, que añadio
  /// estas columnas «precisamente para no tener que recalcular el peso con el
  /// catalogo de hoy sobre un pedido de hace tres meses».
  ///
  /// El servidor resuelve los cuatro escalones —la linea, el empaque por los
  /// empaques, el peso escrito a mano y el catalogo— y escribe el resultado en
  /// `peso_linea_kg`, con `origen_peso` al lado diciendo de cual salio. Aqui se
  /// lee. Nada mas.
  ///
  /// EL CATALOGO LOCAL NO SE PIERDE PORQUE NUNCA ESTUVO: no trae el peso de
  /// NINGUN producto en produccion, que es justamente por lo que la columna `kg`
  /// salia entera en blanco antes del 28/09.
  ///
  /// Y SIGUE EXIGIENDO UN NUMERO POSITIVO, con `_siPesa`: el servidor no escribe
  /// ceros —deja la columna vacia— pero los renglones que dejo la migracion del
  /// delivery viejo (`api/db/migracion/02_pedidos.sql`) copian el JSON tal cual,
  /// cero incluido. Un `0.0 kg` en la hoja del almacen se lee como «no pesa»: es
  /// el cero creible del §3, y aqui no entra.
  Expression<double> get _pesoDeLaLinea =>
      _siPesa(_base.orderItems.pesoLineaKg);

  /// Vale si el numero es MAYOR QUE CERO; si no, nulo. Nulo aqui no es «pesa
  /// cero»: es «no se sabe», y es lo que cuenta el contador de «sin peso».
  Expression<double> _siPesa(Expression<double> kg) =>
      CaseWhenExpression<double>(
        cases: <CaseWhen<bool, double>>[
          CaseWhen(kg.isBiggerThanValue(0), then: kg),
        ],
      );

  /// **LAS UNIDADES DE UNA LINEA: su `quantity`, si es de fiar.**
  ///
  /// Ventra manda `quantity` y `packs` juntos, y casi siempre `quantity` son las
  /// unidades sueltas y `packs` los bultos: 7.301 de las 7.738 lineas de
  /// produccion tienen `quantity` mayor o igual que `packs` y ademas multiplo
  /// exacto suyo — «MALTA GUAJIRA 330 ML BLISTER 6U · 120 unidades · 20
  /// empaques».
  ///
  /// Las otras 437 no: ahi `quantity` viene POR DEBAJO de los empaques, asi que
  /// no son unidades de nada. Son las del 22/09/2026 —«SERVILLETA PROSITO PACA
  /// 24P · 7 empaques · 4 unidades»—, y meterlas en la hoja con la que se carga
  /// el camion da un numero mas bajo que los propios bultos.
  ///
  /// Asi que la linea vale cuando trae empaques Y `quantity` llega a ellos; si
  /// no, se cae al catalogo igual que el peso. `packs` nulo queda fuera por el
  /// `isBiggerThanValue`, como en [_empaquesDeLaLinea]: en SQL una comparacion
  /// con nulo no es cierta.
  Expression<double> get _unidadesDeLaLinea => coalesce([
    CaseWhenExpression<double>(
      cases: <CaseWhen<bool, double>>[
        CaseWhen(
          _base.orderItems.packs.isBiggerThanValue(0) &
              _base.orderItems.quantity.isBiggerOrEqual(_base.orderItems.packs),
          then: _base.orderItems.quantity,
        ),
      ],
    ),
    _empaquesDeLaLinea * _base.products.unitsPerPackage,
  ]);

  Future<TotalesPreDespacho> _preDespacho(Expression<bool> filtro) async {
    final producto = _base.orderItems.description;
    final empaques = _empaquesDeLaLinea.sum();
    final unidades = _unidadesDeLaLinea.sum();
    final peso = _pesoDeLaLinea.sum();
    // UNA SUMA A MEDIAS NO PUEDE PARECER COMPLETA, y aqui se aplica por
    // PRODUCTO. `SUM` se salta las lineas nulas y devuelve la suma de ALGUNAS
    // con pinta de ser la de todas: el numero creible y equivocado del §3. Por
    // eso al lado va el contador de las que faltan, que es lo que la celda pinta
    // como `≥ 26320.0 (21 renglones sin peso)`. La celda sólo se vuelve `—`
    // cuando el contador se come TODAS las lineas del producto.
    // `filter:` y NO `isNull().count()`: `COUNT(x)` cuenta los valores NO
    // NULOS de lo que le den, y `x IS NULL` vale `true` o `false` pero nunca
    // nulo — o sea que `COUNT(x IS NULL)` son TODAS las filas, siempre mayor
    // que cero, y con eso las dos columnas salian `—` hasta con el dato puesto.
    // Duro media hora el 28/09/2026 y lo cazaron las pruebas de esta misma
    // carpeta, que saben los numeros a mano.
    final sinUnidades = _base.orderItems.id.count(
      filter: _unidadesDeLaLinea.isNull(),
    );
    final sinPeso = _base.orderItems.id.count(filter: _pesoDeLaLinea.isNull());

    final consulta =
        _base.selectOnly(_base.orderItems).join([
            innerJoin(
              _base.orders,
              _base.orders.id.equalsExp(_base.orderItems.orderId),
            ),
            leftOuterJoin(
              _base.products,
              _base.products.id.equalsExp(_base.orderItems.productId),
            ),
          ])
          ..addColumns([
            producto,
            empaques,
            unidades,
            sinUnidades,
            peso,
            sinPeso,
          ])
          // Una linea sin nombre no se puede sacar del almacen: se salta, igual
          // que en el servidor.
          ..where(filtro & producto.trim().equals('').not())
          ..groupBy([producto])
          ..orderBy([OrderingTerm.desc(empaques)]);

    final filas = await consulta.get();
    final (cuantos, kilos) = await _cabeceraDeLaHoja(filtro);
    return TotalesPreDespacho(
      [
        for (final fila in filas)
          LineaPreDespacho(
            producto: fila.read(producto) ?? '',
            empaques: fila.read(empaques) ?? 0,
            // LO QUE SE SABE SE DA, Y SE DICE LO QUE FALTA. `SUM` se salta las
            // líneas nulas, así que esto es la suma de las que sí traen el
            // dato: un MÍNIMO, no un total. Lo que lo convierte en honesto es
            // el contador de al lado, que la pantalla pinta como `≥`.
            // Ver [LineaPreDespacho.lineasSinPeso].
            unidades: fila.read(unidades),
            pesoKg: fila.read(peso),
            lineasSinUnidades: fila.read(sinUnidades) ?? 0,
            lineasSinPeso: fila.read(sinPeso) ?? 0,
          ),
      ],
      pedidos: cuantos,
      pesoDeLosPedidos: kilos,
    );
  }

  /// Cuantos pedidos y cuantos kilos entran en la hoja. Es la esquina derecha
  /// del papel (`pantallas.md` §10.1) y va aparte de la suma por producto
  /// porque cuenta PEDIDOS, no lineas: sumarlo en la misma consulta lo
  /// multiplicaria por el numero de renglones de cada pedido.
  Future<(int, double)> _cabeceraDeLaHoja(Expression<bool> filtro) async {
    final cuantos = _base.orders.id.count();
    final kilos = _base.orders.weight.sum();
    final consulta = _base.selectOnly(_base.orders)
      ..addColumns([cuantos, kilos])
      ..where(filtro);
    final fila = await consulta.getSingle();
    return (fila.read(cuantos) ?? 0, fila.read(kilos) ?? 0);
  }

  /// Los municipios y vendedores con su conteo, para los dos selectores.
  ///
  /// Se calculan en local, como todo lo demas: pedirlas a `/api/orders/facetas`
  /// dejaria dos selectores vacios en cuanto no hubiera red.
  Future<Facetas> facetas({String? sucursalId}) async {
    Future<List<OpcionFaceta>> agrupar(GeneratedColumn<String> columna) async {
      final cuenta = _base.orders.id.count();
      final consulta = _base.selectOnly(_base.orders)
        ..addColumns([columna, cuenta])
        ..where(
          columna.isNotNull() &
              columna.equals('').not() &
              (sucursalId == null || sucursalId.isEmpty
                  ? const Constant(true)
                  : _base.orders.branchId.equals(sucursalId)),
        )
        ..groupBy([columna])
        ..orderBy([OrderingTerm.asc(columna)]);
      final filas = await consulta.get();
      return [
        for (final fila in filas)
          OpcionFaceta(fila.read(columna) ?? '', fila.read(cuenta) ?? 0),
      ];
    }

    return Facetas(
      municipios: await agrupar(_base.orders.municipio),
      vendedores: await agrupar(_base.orders.vendedor),
    );
  }

  /// La ficha del pedido, entera y en una lectura.
  Future<DetallePedido?> detalle(String pedidoId) async {
    final pedido = await (_base.select(
      _base.orders,
    )..where((o) => o.id.equals(pedidoId))).getSingleOrNull();
    if (pedido == null) return null;

    final renglones = (await renglonesDe([pedidoId]))[pedidoId] ?? const [];

    // La ruta del pedido: la que lo lleva, o la que lo solto CON resultado
    // (devuelto o cancelado). Sin resultado, un `ultimaRutaId` suelto es una
    // parada QUITADA, y no es de ninguna ruta (la misma condicion que
    // `ConsultasRutas.paradasDe`).
    final rutaId =
        pedido.routeId ??
        (pedido.resultado != null ? pedido.ultimaRutaId : null);
    final ruta = rutaId == null
        ? null
        : await (_base.select(
            _base.routes,
          )..where((r) => r.id.equals(rutaId))).getSingleOrNull();

    final vehiculoId = ruta?.vehicleId;
    final vehiculo = vehiculoId == null
        ? null
        : await (_base.select(
            _base.vehicles,
          )..where((v) => v.id.equals(vehiculoId))).getSingleOrNull();

    final almacen = await almacenPrincipal(pedido.sucursalCodigo);

    return DetallePedido(
      pedido: pedido,
      renglones: renglones,
      ruta: ruta,
      vehiculo: vehiculo,
      almacen: almacen,
    );
  }

  /// El almacen principal de una sucursal: el punto desde el que se mide todo.
  Future<Almacen?> almacenPrincipal(String? sucursalCodigo) async {
    final consulta = _base.select(_base.warehouses)
      ..where(
        (a) => sucursalCodigo == null
            ? a.activo.equals(true)
            : a.sucursalCodigo.equals(sucursalCodigo) & a.activo.equals(true),
      )
      ..orderBy([
        (a) => OrderingTerm.desc(a.principal),
        (a) => OrderingTerm.asc(a.nombre),
      ])
      ..limit(1);
    final filas = await consulta.get();
    return filas.isEmpty ? null : filas.first;
  }
}

/// El orden que elige la persona, aplicado **sólo a la pagina visible**.
///
/// Es una funcion pura y por eso se prueba sin base y sin widget: se le dan 50
/// pedidos y se comprueba que salen en el orden que toca, y que la lista que
/// entra no es la de la consulta entera.
List<Pedido> ordenarPagina(List<Pedido> pagina, OrdenLocal orden) {
  final copia = [...pagina];

  /// «Sin valor» se va SIEMPRE al final, suba o baje el orden. Y eso hay que
  /// decidirlo antes de invertir la comparacion: si se ordenara al reves
  /// intercambiando los argumentos, los nulos se irian al principio en uno de
  /// los dos sentidos y «sin cotizar» se leeria como «lo mas barato».
  int porNumero(double? a, double? b, {required bool descendente}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return descendente ? b.compareTo(a) : a.compareTo(b);
  }

  int porFecha(Pedido a, Pedido b, {required bool descendente}) {
    final fa = a.orderDate ?? a.createdAt;
    final fb = b.orderDate ?? b.createdAt;
    if (fa == null && fb == null) return 0;
    // Sin fecha no se sabe cuando fue, asi que no puede encabezar ni «lo mas
    // nuevo» ni «lo mas viejo».
    if (fa == null) return 1;
    if (fb == null) return -1;
    return descendente ? fb.compareTo(fa) : fa.compareTo(fb);
  }

  switch (orden) {
    case OrdenLocal.recientes:
      copia.sort((a, b) => porFecha(a, b, descendente: true));
    case OrdenLocal.antiguos:
      copia.sort((a, b) => porFecha(a, b, descendente: false));
    case OrdenLocal.precioDesc:
      copia.sort(
        (a, b) => porNumero(a.pedidoCosto, b.pedidoCosto, descendente: true),
      );
    case OrdenLocal.precioAsc:
      copia.sort(
        (a, b) => porNumero(a.pedidoCosto, b.pedidoCosto, descendente: false),
      );
    case OrdenLocal.distanciaDesc:
      copia.sort(
        (a, b) => porNumero(
          a.deliveryDistanceKm,
          b.deliveryDistanceKm,
          descendente: true,
        ),
      );
    case OrdenLocal.pesoDesc:
      copia.sort((a, b) => porNumero(a.weight, b.weight, descendente: true));
  }
  return copia;
}
