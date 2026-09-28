// Los providers de Rutas.
//
// Igual que en Pedidos: todo cuelga de la base local y de `sucursalMiradaProvider`.
// Lo que esta pantalla anade es la ESCRITURA, y la escritura no tiene provider de
// «guardando»: se escribe en local, se pinta como hecho y la cola se encarga. Lo
// unico que la pantalla mira despues es `sinSubirProvider`, que ya vive en el
// nucleo.

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../pedidos/datos/repositorio_pedidos.dart';
import '../datos/acciones_rutas.dart';
import '../datos/repositorio_rutas.dart';

final consultasRutasProvider = Provider<ConsultasRutas>(
  (ref) => ConsultasRutas(ref.watch(baseProvider)),
);

/// Las cinco acciones de escritura. Comparten la MISMA cola y el MISMO reloj que
/// el resto de la aplicacion: dos relojes distintos serian dos horas distintas
/// para el mismo cierre.
///
/// Y comparten el mismo `escrituraEnVivoProvider`, que es `null` en la APK y en
/// el escritorio —alli se escribe en local y se encola— y **no es null en la
/// web**, donde el gesto va al servidor y se espera (`CLAUDE.md` §1). Todo el
/// porque esta en `nucleo/red/escritura_en_vivo.dart`.
final accionesDeRutaProvider = Provider<AccionesDeRuta>(
  (ref) => AccionesDeRuta(
    ref.watch(baseProvider),
    ref.watch(colaProvider),
    reloj: ref.watch(relojProvider),
    enVivo: ref.watch(escrituraEnVivoProvider),
  ),
);

class PestanaElegida extends Notifier<PestanaRutas> {
  @override
  PestanaRutas build() => PestanaRutas.activas;

  void elegir(PestanaRutas cual) => state = cual;
}

final pestanaRutasProvider = NotifierProvider<PestanaElegida, PestanaRutas>(
  PestanaElegida.new,
);

class FiltrosDeRutas extends Notifier<FiltrosRutas> {
  @override
  FiltrosRutas build() => const FiltrosRutas();

  void poner(FiltrosRutas nuevos) => state = nuevos;

  void limpiar() => state = const FiltrosRutas();
}

final filtrosRutasProvider = NotifierProvider<FiltrosDeRutas, FiltrosRutas>(
  FiltrosDeRutas.new,
);

class PaginaDeRutas extends Notifier<int> {
  @override
  int build() => 1;

  void ir(int pagina) => state = pagina;
}

final paginaRutasProvider = NotifierProvider<PaginaDeRutas, int>(
  PaginaDeRutas.new,
);

/// La ruta seleccionada en la columna izquierda. `null` = el detalle dice
/// `Selecciona una ruta para ver el detalle`.
class RutaElegida extends Notifier<String?> {
  @override
  String? build() {
    // SI LA RUTA ELEGIDA SUBE MIENTRAS SE MIRA, SE LA SIGUE.
    //
    // Sin esto: se arma una ruta sin red, el detalle se abre solo con el id
    // provisional, la ruta sube en ese mismo instante y sus pedidos pasan a
    // colgar del id de verdad. La pantalla se queda mirando un id que ya no
    // tiene paradas y dice **«Ver paradas (0)»** encima de una ruta de cinco,
    // con sus kilómetros y sus kilos al lado. Cerrar y volver a abrir lo
    // arreglaba, que es la peor forma posible: el dato estaba bien y la pantalla
    // mentía.
    //
    // Pasó el 21/09/2026 con Jose delante: «no, eso no puede pasar, eso es al
    // momento».
    ref.listen(equivalenciasProvider, (_, siguiente) {
      final mapa = siguiente.value;
      final actual = state;
      if (mapa == null || actual == null) return;
      final real = mapa[actual];
      if (real != null && real != actual) state = real;
    });
    return null;
  }

  /// Elegir resuelve el id **en el momento**, además de seguirlo si cambia
  /// después.
  ///
  /// Las dos cosas hacen falta y cada una tapa un hueco distinto. Mirar sólo los
  /// cambios deja fuera el caso más común de todos: la ruta se arma, sube en el
  /// mismo segundo —el ciclo está corriendo— y **para cuando alguien la elige la
  /// equivalencia ya existe**, así que no hay ningún cambio que escuchar. Eso es
  /// justo lo que se vio el 21/09/2026: «Ver paradas (0)» encima de una ruta
  /// recién armada con sus kilómetros y sus kilos al lado.
  void elegir(String? rutaId) {
    final mapa = ref.read(equivalenciasProvider).value;
    state = mapa?[rutaId] ?? rutaId;
  }
}

final rutaElegidaProvider = NotifierProvider<RutaElegida, String?>(
  RutaElegida.new,
);

final todasLasRutasProvider = StreamProvider<List<Ruta>>(
  (ref) => ref
      .watch(consultasRutasProvider)
      .rutas(sucursalId: ref.watch(sucursalMiradaProvider)),
);

final vehiculosProvider = StreamProvider<List<Vehiculo>>(
  (ref) => ref
      .watch(consultasRutasProvider)
      .vehiculos(sucursalId: ref.watch(sucursalMiradaProvider)),
);

final sucursalesProvider = StreamProvider<List<Sucursal>>(
  (ref) => ref.watch(consultasRutasProvider).sucursales(),
);

/// Cuantas rutas hay en cada pestana. Va en la propia pestana, como en el
/// pliego.
final contadoresDePestanaProvider = Provider<Map<PestanaRutas, int>>((ref) {
  final rutas = ref.watch(todasLasRutasProvider).value ?? const <Ruta>[];
  return {
    for (final pestana in PestanaRutas.values)
      pestana: rutas.where((r) => pestana.agrupa(r.status)).length,
  };
});

/// LAS UBICACIONES DE SALIDA QUE HAY, para el filtro de la barra.
///
/// Jose, 28/09/2026: «en las rutas añadir tambien el filtro por la ubicacion q
/// salio para saber de donde saiioo sin necesidad de estar viendo todas juntas».
///
/// **Sale de las RUTAS y no del catalogo de almacenes.** El porque entero esta
/// en `FiltrosRutas.ubicacionSalida`; en una linea: `routes` no guarda de que
/// almacen salio, solo el texto, y cruzarlo contra `warehouses` dejaria sin
/// poder pedir las rutas de un almacen renombrado y ofreceria opciones vacias
/// de los almacenes sin rutas.
///
/// **Y de TODAS las rutas del alcance, no de las de la pestaña que se mira.**
/// Con las de la pestaña, la lista de opciones cambiaria al cambiar de pestaña
/// —un filtro que se queda puesto sobre una opcion que ya no esta en su propio
/// desplegable— y ademas el desplegable se vaciaria en `Historial` el primer
/// dia. Lo que se filtra es la pestaña; lo que se OFRECE es lo que hay.
///
/// Es un `Provider` y no un `FutureProvider`, que es lo que pide el §3-ter:
/// cuelga de [todasLasRutasProvider], que ya es un `Stream`, asi que se rehace
/// solo cada vez que la bajada mete rutas. Con un `Future` este desplegable se
/// quedaria **vacio para siempre** en la web, que nace con la base vacia en
/// cada carga de la pagina — el mismo fallo que ya se pago en los desplegables
/// de Pedidos (17/09) y en los del paso 4 del asistente (24/09).
final ubicacionesDeSalidaProvider = Provider<List<UbicacionDeSalida>>(
  (ref) => ubicacionesDeSalidaDe(
    ref.watch(todasLasRutasProvider).value ?? const <Ruta>[],
  ),
);

/// La lista ya filtrada por la pestana y por los filtros del cliente.
///
/// **Por pestana, no «la de la pestana elegida»**: en el movil las tres listas
/// van en un `PageView` y mientras el dedo arrastra se ven DOS a la vez, la que
/// se va y la que llega. Con un solo provider atado a la elegida, la pagina de
/// al lado pintaba la misma lista y el deslizamiento parecia no hacer nada hasta
/// que soltabas.
final rutasDePestanaProvider = Provider.family<List<Ruta>, PestanaRutas>((
  ref,
  pestana,
) {
  final rutas = ref.watch(todasLasRutasProvider).value ?? const <Ruta>[];
  final vehiculos = {
    for (final v in ref.watch(vehiculosProvider).value ?? const <Vehiculo>[])
      v.id: v,
  };
  final sucursales = {
    for (final s in ref.watch(sucursalesProvider).value ?? const <Sucursal>[])
      s.id: s,
  };
  return filtrarRutas(
    [
      for (final ruta in rutas)
        if (pestana.agrupa(ruta.status)) ruta,
    ],
    ref.watch(filtrosRutasProvider),
    vehiculos: vehiculos,
    sucursales: sucursales,
  );
});

/// La de la pestana que se esta mirando. Sigue existiendo porque es lo que pide
/// casi todo el mundo; por dentro es la de arriba con la elegida puesta.
final rutasDeLaPestanaProvider = Provider<List<Ruta>>(
  (ref) => ref.watch(rutasDePestanaProvider(ref.watch(pestanaRutasProvider))),
);

final rutaConTodoProvider = StreamProvider.family<RutaConTodo?, String>(
  (ref, rutaId) => ref.watch(consultasRutasProvider).rutaConTodo(rutaId),
);

/// Cuantas paradas lleva cada ruta, para la lista. Una sola consulta agrupada
/// en vez de una por tarjeta.
final paradasPorRutaProvider = StreamProvider<Map<String, int>>(
  (ref) => ref.watch(consultasRutasProvider).paradasPorRuta(),
);

/// EN QUE ANDA CADA CAMION, para la lista y la ficha de una ruta.
///
/// Mapa `vehicleId -> ruta abierta que lo tiene cogido`. Sale de la tabla
/// `routes` y NO de `vehicles.status`: ver `ConsultasRutas.camionesOcupados`.
///
/// Una sola consulta agrupada para las veinte tarjetas, como `paradasPorRuta`, y
/// no una por tarjeta.
final camionesOcupadosProvider = StreamProvider<Map<String, RutaQueOcupa>>(
  (ref) => ref.watch(consultasRutasProvider).camionesOcupados(),
);

/// Las paradas en vivo: el cierre se tiene que ver marcado en el detalle sin
/// esperar a nada ni a nadie.
final paradasDeRutaProvider = StreamProvider.family<List<Pedido>, String>(
  (ref, rutaId) => ref.watch(consultasRutasProvider).mirarParadasDe(rutaId),
);

/// Los renglones de las paradas: de aqui sale la `Carga total` y el bloque
/// `Queda en el camión` del cierre.
///
/// ## STREAM, no Future — 24/09/2026, y es el §3-ter otra vez
///
/// Esto era un `FutureProvider` colgado de la lista de paradas, o sea que sólo
/// se recalculaba **cuando cambiaba la tabla de pedidos**. En la bajada `orders`
/// va antes que `order_items` (`Colecciones.todas`): cuando los renglones
/// entran, esa tabla ya no se toca y la respuesta no se volvia a pedir nunca.
///
/// Lo que quedaba delante: la `Carga total` y el `Queda en el camión` del cierre
/// **en cero**, encima de un camion cargado. Un peso creible y equivocado que
/// ninguna pantalla desmiente, que es el fallo que mas caro sale aqui (§4). Y en
/// la web pasa SIEMPRE, porque la base nace vacia en cada carga de la pagina.
///
/// Se vigilan las DOS tablas de las que sale: `order_items` y `products` —el
/// peso por empaque se resuelve contra el catalogo, y `products` baja aun mas
/// tarde que los renglones—.
final renglonesDeParadasProvider =
    StreamProvider.family<Map<String, List<RenglonConPeso>>, String>((
      ref,
      rutaId,
    ) {
      final base = ref.watch(baseProvider);
      final consultas = ref.watch(consultasRutasProvider);
      final paradas = ref.watch(paradasDeRutaProvider(rutaId)).value;
      if (paradas == null) {
        // Las paradas todavia no han contestado. Un stream vacio deja esto
        // «cargando», que es la verdad; cuando contesten, este provider se rehace
        // solo porque las mira con `watch`.
        return const Stream<Map<String, List<RenglonConPeso>>>.empty();
      }
      final ids = [for (final p in paradas) p.id];

      Future<Map<String, List<RenglonConPeso>>> mirar() =>
          consultas.renglonesDe(ids);

      return () async* {
        // El primero enseguida: `tableUpdates` no emite al suscribirse, y sin
        // esto la carga arrancaria en cero aunque los renglones ya estuvieran.
        yield await mirar();
        yield* base
            .tableUpdates(
              TableUpdateQuery.onAllTables([base.orderItems, base.products]),
            )
            .asyncMap((_) => mirar());
      }();
    });

/// ¿Se bajaron las rutas alguna vez?
///
/// **Stream y no Future**, por lo mismo que en `pedidosDescargadosProvider`: una
/// sola respuesta se toma con la base vacia —que en la web es siempre, porque
/// arranca vacia en cada carga— y deja la pantalla clavada en «Esta pantalla no
/// se ha descargado todavia» aunque las rutas lleguen dos segundos despues.
final rutasDescargadasProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(frescuraProvider)
      .mirar(Colecciones.rutas)
      .map((fila) => fila?.bajadaAt != null),
);

/// Los filtros del paso 4 del asistente. Van como valor con `==` porque son el
/// argumento de un `family`.
@immutable
class FiltrosDisponibles {
  const FiltrosDisponibles({
    this.sucursalId,
    this.q = '',
    this.municipio = '',
    this.vendedor = '',
    this.estado = EstadoDelPedido.cualquiera,
    this.domicilio = DomicilioFiltro.soloCon,
    this.cotizado = CotizadoDelDomicilio.cualquiera,
    this.dia,
    this.kmMax,
    this.costoMin,
  });

  final String? sucursalId;
  final String q;
  final String municipio;
  final String vendedor;
  final EstadoDelPedido estado;

  /// **Arranca en `Sólo con domicilio`** (pliego §3, paso 4), y `Limpiar` vuelve
  /// aqui, no a «con y sin».
  final DomicilioFiltro domicilio;

  final CotizadoDelDomicilio cotizado;
  final DateTime? dia;
  final double? kmMax;
  final double? costoMin;

  /// `Limpiar` del paso 4: se queda la sucursal —es de lo que va la ruta— y
  /// vuelve el domicilio a `1`.
  FiltrosDisponibles limpios() => FiltrosDisponibles(sucursalId: sucursalId);

  FiltrosDisponibles copiarCon({
    String? sucursalId,
    String? q,
    String? municipio,
    String? vendedor,
    EstadoDelPedido? estado,
    DomicilioFiltro? domicilio,
    CotizadoDelDomicilio? cotizado,
    DateTime? dia,
    bool limpiarDia = false,
    double? kmMax,
    bool limpiarKmMax = false,
    double? costoMin,
    bool limpiarCostoMin = false,
  }) => FiltrosDisponibles(
    sucursalId: sucursalId ?? this.sucursalId,
    q: q ?? this.q,
    municipio: municipio ?? this.municipio,
    vendedor: vendedor ?? this.vendedor,
    estado: estado ?? this.estado,
    domicilio: domicilio ?? this.domicilio,
    cotizado: cotizado ?? this.cotizado,
    dia: limpiarDia ? null : (dia ?? this.dia),
    // Sin el `limpiar…` no habria forma de BORRAR un tope: pasar `null` es
    // indistinguible de «no lo toques», y el `km máx.` se quedaria puesto para
    // siempre.
    kmMax: limpiarKmMax ? null : (kmMax ?? this.kmMax),
    costoMin: limpiarCostoMin ? null : (costoMin ?? this.costoMin),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FiltrosDisponibles &&
          other.sucursalId == sucursalId &&
          other.q == q &&
          other.municipio == municipio &&
          other.vendedor == vendedor &&
          other.estado == estado &&
          other.domicilio == domicilio &&
          other.cotizado == cotizado &&
          other.dia == dia &&
          other.kmMax == kmMax &&
          other.costoMin == costoMin;

  @override
  int get hashCode => Object.hash(
    sucursalId,
    q,
    municipio,
    vendedor,
    estado,
    domicilio,
    cotizado,
    dia,
    kmMax,
    costoMin,
  );
}

/// Los pedidos elegibles para una ruta. **El cuadre con la factura no es
/// configurable**: siempre `cuadra`, que es lo unico que el armado acepta.
///
/// ## STREAM, no Future — 24/09/2026, §3-ter
///
/// Era un `FutureProvider`: una sola respuesta, la del instante en que se pinta
/// el paso 4. En la web la base nace vacia en cada carga, asi que esa respuesta
/// era siempre la lista vacia y el paso 4 se quedaba en **«No hay pedidos
/// disponibles para rutear»** sobre una sucursal con 299. Y no se arreglaba
/// cerrando y reabriendo el cajon: el cache es del provider, no del widget.
final disponiblesProvider =
    StreamProvider.family<List<Pedido>, FiltrosDisponibles>((ref, filtros) {
      final base = ref.watch(baseProvider);
      final consultas = ref.watch(consultasRutasProvider);
      // El MISMO reloj que el resto de la aplicacion: `expirada` se decide
      // contra la hora, y dos relojes distintos son dos listas distintas.
      final ahora = ref.watch(relojProvider)();

      Future<List<Pedido>> mirar() => consultas.disponibles(
        sucursalId: filtros.sucursalId,
        q: filtros.q,
        municipio: filtros.municipio,
        vendedor: filtros.vendedor,
        estado: filtros.estado.param,
        domicilio: filtros.domicilio.param,
        cotizado: filtros.cotizado.param,
        dia: filtros.dia,
        kmMax: filtros.kmMax,
        costoMin: filtros.costoMin,
        ahora: ahora,
      );

      return () async* {
        // El primero enseguida: `tableUpdates` no emite al suscribirse, y sin
        // esto la lista arrancaria vacia aunque los pedidos ya estuvieran.
        yield await mirar();
        yield* base
            .tableUpdates(TableUpdateQuery.onTable(base.orders))
            .asyncMap((_) => mirar());
      }();
    });

/// Los municipios y los vendedores que hay **entre los disponibles**, para los
/// dos selectores del paso 4.
///
/// Salen de la lista SIN `q`, sin vendedor y sin municipio a proposito (es lo
/// que hace `/api/orders/available` para las opciones de filtro): si se sacaran
/// de la lista ya filtrada, elegir un vendedor borraria del desplegable a todos
/// los demas y no habria forma de cambiar de opinion sin limpiar.
/// **STREAM, no Future** — 24/09/2026. Es el MISMO fallo que ya se arreglo en
/// los desplegables de Pedidos el 17/09 (`facetasPedidosProvider`) y que no se
/// llevo aqui: con una sola respuesta, en la web los dos desplegables se
/// quedaban vacios para siempre —solo «Todos los municipios»— y no habia forma
/// de filtrar sin recargar la pagina. Ahora cuelga de [disponiblesProvider], que
/// ya es un `Stream`, asi que se rehace cada vez que aquel emite.
final opcionesDeDisponiblesProvider =
    StreamProvider.family<OpcionesDeDisponibles, FiltrosDisponibles>((
      ref,
      filtros,
    ) {
      final pedidos = ref
          .watch(
            disponiblesProvider(
              filtros.copiarCon(q: '', vendedor: '', municipio: ''),
            ),
          )
          .value;
      // Todavia no ha contestado: un stream vacio deja esto «cargando», y cuando
      // conteste este provider se rehace solo.
      if (pedidos == null) return const Stream<OpcionesDeDisponibles>.empty();
      return Stream<OpcionesDeDisponibles>.value(
        OpcionesDeDisponibles(
          municipios: {
            for (final p in pedidos)
              if ((p.municipio ?? '').isNotEmpty) p.municipio!,
          }.toList()..sort(),
          vendedores: {
            for (final p in pedidos)
              if ((p.vendedor ?? '').isNotEmpty) p.vendedor!,
          }.toList()..sort(),
        ),
      );
    });

/// Los renglones de los pedidos elegibles: de aqui salen los articulos de cada
/// fila del paso 4.
///
/// **STREAM, no Future**, y por lo mismo que [renglonesDeParadasProvider]: los
/// renglones bajan DESPUES que los pedidos, y con una sola respuesta la columna
/// de articulos se quedaba vacia para siempre. Vacia no se lee como «todavia no
/// ha llegado»: se lee como «este pedido no lleva nada», y con eso se carga un
/// camion.
final renglonesDeDisponiblesProvider =
    StreamProvider.family<
      Map<String, List<RenglonConPeso>>,
      FiltrosDisponibles
    >((ref, filtros) {
      final base = ref.watch(baseProvider);
      final consultas = ref.watch(consultasRutasProvider);
      final pedidos = ref.watch(disponiblesProvider(filtros)).value;
      if (pedidos == null) {
        return const Stream<Map<String, List<RenglonConPeso>>>.empty();
      }
      final ids = [for (final p in pedidos) p.id];

      Future<Map<String, List<RenglonConPeso>>> mirar() =>
          consultas.renglonesDe(ids);

      return () async* {
        yield await mirar();
        yield* base
            .tableUpdates(
              TableUpdateQuery.onAllTables([base.orderItems, base.products]),
            )
            .asyncMap((_) => mirar());
      }();
    });

/// Lo que llena los dos desplegables del paso 4.
@immutable
class OpcionesDeDisponibles {
  const OpcionesDeDisponibles({
    required this.municipios,
    required this.vendedores,
  });

  static const vacias = OpcionesDeDisponibles(
    municipios: <String>[],
    vendedores: <String>[],
  );

  final List<String> municipios;
  final List<String> vendedores;
}

/// Los almacenes de una sucursal, por su CODIGO (`branches.externalId`), que es
/// como los guarda Accesos. El principal viene primero.
///
/// ## STREAM, no Future — 24/09/2026, y era el mas grave de los cinco
///
/// `warehouses` es la **penultima** coleccion de `Colecciones.todas`, o sea de
/// las ultimas en bajar; `branches`, que es lo que hace que aqui llegue un
/// codigo, va antes. Asi que en la web esta respuesta se pedia casi siempre con
/// la tabla todavia vacia, y con un `Future` se quedaba cacheada asi: el paso 2
/// del asistente —«Salida»— **sin ninguna opcion para siempre**, con su
/// `_salida ??= conUbicacion.firstOrNull` sin resolver nunca.
///
/// Y **no se arreglaba cerrando y reabriendo el cajon**, que es lo primero que
/// intenta quien esta delante: el cache es del provider, no del widget. Solo
/// recargando la pagina.
final almacenesProvider = StreamProvider.family<List<Almacen>, String>((
  ref,
  sucursalCodigo,
) {
  final base = ref.watch(baseProvider);
  final consultas = ref.watch(consultasRutasProvider);

  Future<List<Almacen>> mirar() => consultas.almacenesDe(sucursalCodigo);

  return () async* {
    // El primero enseguida: `tableUpdates` no emite al suscribirse.
    yield await mirar();
    yield* base
        .tableUpdates(TableUpdateQuery.onTable(base.warehouses))
        .asyncMap((_) => mirar());
  }();
});
