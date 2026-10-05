// Los providers de Pedidos.
//
// Todos cuelgan de la base local y de `sucursalMiradaProvider`. Eso ultimo es lo
// que hace verdad el literal del pliego «al cambiar de sucursal se invalidan
// todas las consultas (no se recarga la página)»: como cada provider la mira con
// `ref.watch`, cambiarla los reconstruye solos y los numeros cambian en el sitio.

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
// Del Tablero se usa lo de LEER y lo de ESCRIBIR, sin tocarlo: «Mandar a una
// zona» tiene que colocar por el mismo camino que el arrastre o serian dos
// maneras distintas de poner una tarjeta, con dos juegos de reglas.
import '../../tablero/datos/esquema.dart';
import '../../tablero/datos/modelos.dart';
import '../../tablero/estado/proveedores.dart';
import '../datos/filtros_pedidos.dart';
import '../datos/mandar_al_tablero.dart';
import '../datos/repositorio_pedidos.dart';

final consultasPedidosProvider = Provider<ConsultasPedidos>(
  (ref) => ConsultasPedidos(ref.watch(baseProvider)),
);

/// Los filtros de la pantalla. Arrancan ACOTADOS a lo que puede subir a un
/// camion, que es lo que pinta la franja azul.
class FiltrosPedidosNotifier extends Notifier<FiltrosPedidos> {
  @override
  FiltrosPedidos build() => const FiltrosPedidos();

  void poner(FiltrosPedidos nuevos) => state = nuevos;

  void cambiar(FiltrosPedidos Function(FiltrosPedidos) como) =>
      state = como(state);

  /// `Ver todos los pedidos`: quita **sólo** los dos del arranque.
  void verTodos() => state = state.copiarCon(
    factura: FacturaFiltro.cualquiera,
    archivado: ArchivadoFiltro.cualquiera,
  );

  /// `quitarlos todos`: los nueve, incluidos los del arranque.
  void quitarTodos() => state = const FiltrosPedidos.sinNada();

  void irAPagina(int pagina) => state = state.copiarCon(pagina: pagina);

  /// Las dos fechas a la vez, y con `null` explicito.
  ///
  /// Van juntas porque son un solo filtro: el rango. Y con `null` que borra,
  /// porque `copiarCon` no puede distinguir «ponlo a nada» de «no lo toques»
  /// —los dos llegan como `null`— y sin esto no habria forma de quitar una
  /// fecha ya puesta.
  void ponerFechas(DateTime? desde, DateTime? hasta) => state = state.copiarCon(
    desde: desde,
    limpiarDesde: desde == null,
    hasta: hasta,
    limpiarHasta: hasta == null,
  );

  /// Las dos fechas de la ENTREGA, que son otro filtro y otro par.
  ///
  /// Se pone desde el Panel («Entregados hoy») y se quita aquí. Van aparte de
  /// [ponerFechas] a propósito: acotar por la fecha del pedido y acotar por la de
  /// la entrega son dos preguntas distintas, y mezclarlas en un solo par es lo
  /// que hacía que «lo entregado hoy» fuera impedible — el pedido de Jose del
  /// 28/09/2026 es del día 25.
  void ponerFechasDeEntrega(DateTime? desde, DateTime? hasta) =>
      state = state.copiarCon(
        entregadoDesde: desde,
        limpiarEntregadoDesde: desde == null,
        entregadoHasta: hasta,
        limpiarEntregadoHasta: hasta == null,
      );
}

final filtrosPedidosProvider =
    NotifierProvider<FiltrosPedidosNotifier, FiltrosPedidos>(
      FiltrosPedidosNotifier.new,
    );

/// Lo marcado a mano. Es LOCAL y no se guarda: el pre-despacho de lo elegido se
/// arma y se imprime en el momento.
class SeleccionPedidos extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void alternar(String id) {
    final copia = {...state};
    if (!copia.remove(id)) copia.add(id);
    state = copia;
  }

  /// La casilla de la cabecera marca o desmarca **toda la pagina**, no toda la
  /// consulta: marcar doce mil pedidos de un golpe no lo pidio nadie.
  void marcarPagina(List<String> ids, {required bool marcar}) {
    final copia = {...state};
    if (marcar) {
      copia.addAll(ids);
    } else {
      copia.removeAll(ids);
    }
    state = copia;
  }

  void quitarLaMarca() => state = <String>{};

  /// Quita la marca SOLO de estos. Lo usa «Mandar a una zona»: los que se
  /// colocaron pierden la marca y **los que no pudieron ir se quedan
  /// marcados**, que es lo que deja seguir trabajando con ellos sin volver a
  /// buscarlos entre doce mil (`CLAUDE.md` §4: nada se descarta en silencio).
  void quitarLaMarcaDe(Iterable<String> ids) =>
      state = {...state}..removeAll(ids);
}

final seleccionPedidosProvider =
    NotifierProvider<SeleccionPedidos, Set<String>>(SeleccionPedidos.new);

/// El total que sale en la cabecera: `<total> pedidos`.
final totalPedidosProvider = StreamProvider<int>(
  (ref) => ref
      .watch(consultasPedidosProvider)
      .contar(
        ref.watch(filtrosPedidosProvider),
        sucursalId: ref.watch(sucursalMiradaProvider),
      ),
);

/// La pagina visible, ya ordenada por el orden LOCAL que eligio la persona.
final paginaPedidosProvider = StreamProvider<List<Pedido>>((ref) {
  final filtros = ref.watch(filtrosPedidosProvider);
  return ref
      .watch(consultasPedidosProvider)
      .pagina(filtros, sucursalId: ref.watch(sucursalMiradaProvider))
      .map((pagina) => ordenarPagina(pagina, filtros.orden));
});

/// Los renglones de los pedidos de la pagina: la columna `Artículos` y el peso
/// por linea de la ficha salen de aqui.
///
/// ## STREAM, no Future — 24/09/2026, y es el §3-ter otra vez
///
/// Esto era un `FutureProvider` que esperaba a `paginaPedidosProvider.future`,
/// o sea que se recalculaba **cuando cambiaba la tabla de PEDIDOS**. Y en la
/// bajada `orders` va antes que `order_items` (`Colecciones.todas`): cuando los
/// renglones entran, la tabla de pedidos ya no se toca, así que esta respuesta
/// no se volvía a pedir nunca.
///
/// Lo que quedaba en pantalla, medido con la sonda del §3-ter —montar con la
/// base vacía, sembrar los pedidos, y DESPUÉS los renglones sin remontar—:
///
///     tras los pedidos:   guion=3  arroz=0
///     tras los renglones: arroz=0      <-- aquí ya tenía que decir «Arroz ×2»
///
/// La columna `Artículos` se quedaba en «—» encima de un pedido con doce
/// líneas, y «—» no se lee como «todavía no ha llegado»: se lee como **«este
/// pedido no lleva nada»**. Un dato creíble y equivocado que ninguna pantalla
/// desmiente, que es el fallo que más caro sale aquí.
///
/// Se vigilan las DOS tablas de las que sale la columna: `order_items` y
/// `products` —el peso por empaque se resuelve contra el catálogo, y `products`
/// baja aún más tarde que los renglones—. Y el coste está acotado: se leen los
/// renglones de los 50 pedidos de la página, no de los doce mil.
final renglonesDePaginaProvider =
    StreamProvider<Map<String, List<RenglonConPeso>>>((ref) {
      final base = ref.watch(baseProvider);
      final consultas = ref.watch(consultasPedidosProvider);
      final pagina = ref.watch(paginaPedidosProvider).value;
      if (pagina == null) {
        // La página todavía no ha contestado. Un stream vacío deja esto
        // «cargando», que es la verdad; cuando conteste, este provider se
        // rehace solo porque la mira con `watch`.
        return const Stream<Map<String, List<RenglonConPeso>>>.empty();
      }
      final ids = [for (final p in pagina) p.id];

      Future<Map<String, List<RenglonConPeso>>> mirar() =>
          consultas.renglonesDe(ids);

      return () async* {
        // El primero enseguida: `tableUpdates` no emite al suscribirse, y sin
        // esto la columna arrancaría vacía aunque los renglones ya estuvieran.
        yield await mirar();
        yield* base
            .tableUpdates(
              TableUpdateQuery.onAllTables([base.orderItems, base.products]),
            )
            .asyncMap((_) => mirar());
      }();
    });

/// Lo que llena los desplegables «Municipio del cliente» y «Vendedor del
/// pedido», con su cuenta al lado.
///
/// ## STREAM, y por el mismo motivo que el de arriba — 17/09/2026
///
/// Esto era un `FutureProvider` que sólo miraba la sucursal, o sea que se
/// resolvía UNA vez y ya. En la web se resolvía siempre con la base vacía, y
/// entonces pasaba esto: el cartel de «no se ha descargado» se iba solo, la
/// cabecera pasaba a «299 pedidos», la lista salía… **y los dos desplegables se
/// quedaban vacíos para siempre**, sólo con «Todos los municipios». No había
/// forma de filtrar sin recargar.
///
/// Lo encontró el auditor justo después de arreglar el cartel: el mismo fallo,
/// en la misma pantalla, a doce líneas de distancia. Por eso se arreglan los
/// dos juntos y con la misma forma.
///
/// El primer valor sale enseguida —`tableUpdates` no emite al suscribirse, y sin
/// esto la pantalla arrancaría sin desplegables aunque los datos ya estuvieran—
/// y a partir de ahí se recalcula con cada escritura en la tabla de pedidos.
final facetasPedidosProvider = StreamProvider<Facetas>((ref) {
  final base = ref.watch(baseProvider);
  final consultas = ref.watch(consultasPedidosProvider);
  final sucursal = ref.watch(sucursalMiradaProvider);

  Future<Facetas> mirar() => consultas.facetas(sucursalId: sucursal);

  return () async* {
    yield await mirar();
    yield* base
        .tableUpdates(TableUpdateQuery.onTable(base.orders))
        .asyncMap((_) => mirar());
  }();
});

/// El pre-despacho de LO FILTRADO. Se pide sólo cuando se abre el bloque
/// plegable, igual que en la de Next: sumar doce mil pedidos al pintar la
/// pantalla es trabajo que casi nunca se mira.
final preDespachoFiltradoProvider = FutureProvider<TotalesPreDespacho>(
  (ref) => ref
      .watch(consultasPedidosProvider)
      .preDespachoDeLoFiltrado(
        ref.watch(filtrosPedidosProvider),
        sucursalId: ref.watch(sucursalMiradaProvider),
      ),
);

/// El pre-despacho de LO MARCADO.
final preDespachoElegidoProvider = FutureProvider<TotalesPreDespacho>(
  (ref) => ref
      .watch(consultasPedidosProvider)
      .preDespachoDe(ref.watch(seleccionPedidosProvider).toList()),
);

final detallePedidoProvider = FutureProvider.family<DetallePedido?, String>(
  (ref, id) => ref.watch(consultasPedidosProvider).detalle(id),
);

/// ¿Se bajaron los pedidos alguna vez?
///
/// Separa «no hay nada» de «no se ha descargado». Una lista vacia sin esta
/// respuesta es un fallo que se lee como un dato (caso S7).
///
/// ## STREAM, no Future — 17/09/2026
///
/// Esto era un `FutureProvider`, o sea **una sola respuesta, la del instante en
/// que la pantalla se pinta por primera vez**. En la APK daba igual: se entra
/// con el aparato ya configurado y para entonces la marca esta puesta. En la web
/// la base arranca VACIA en cada carga, asi que la primera respuesta era siempre
/// «no se descargo» — y como no se volvia a preguntar, se quedaba asi para
/// siempre.
///
/// Lo que se veia, y Jose lo vio: la cabecera diciendo «299 pedidos», el pie
/// diciendo «Mostrando 1-50 de 299» y en medio «Esta pantalla no se ha
/// descargado todavia». El total y la pagina son streams y se enteraban de la
/// bajada; esto no. Tres consultas sobre la misma tabla contando cosas
/// distintas.
///
/// `mirar` vigila la fila de frescura, asi que en cuanto la bajada la marca la
/// pantalla se rehace sola. Sin recargar, que es la otra cosa que Jose pidio.
final pedidosDescargadosProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(frescuraProvider)
      .mirar(Colecciones.pedidos)
      .map((fila) => fila?.bajadaAt != null),
);

/// El nombre de la sucursal que va en la cabecera de la hoja impresa.
///
/// Sin sucursal elegida arriba se escribe `Todas las sucursales`, literal de la
/// de Next: en la hoja del almacen no puede quedar un hueco donde tendria que
/// decir de donde sale la mercancia.
final sucursalDeLaHojaProvider = StreamProvider<String>((ref) {
  final base = ref.watch(baseProvider);
  final mirada = ref.watch(sucursalMiradaProvider);
  if (mirada == null || mirada.isEmpty) {
    return Stream<String>.value(SucursalDeLaHoja.todas);
  }
  return (base.select(base.branches)..where((b) => b.id.equals(mirada)))
      .watchSingleOrNull()
      .map((sucursal) => sucursal?.name ?? '');
});

abstract final class SucursalDeLaHoja {
  static const todas = 'Todas las sucursales';
}

/// Las rutas, por id. Lo necesita la columna `Entrega`: el estado
/// de reparto de un pedido «en despacho» o «en ruta» depende de en que estado
/// esta la ruta que lo lleva.
///
/// Va como mapa entero y no como consulta por fila porque las rutas de una
/// sucursal se cuentan por decenas: una sola lectura es mas barata que cincuenta.
final rutasPorIdProvider = StreamProvider<Map<String, Ruta>>((ref) {
  final base = ref.watch(baseProvider);
  return base
      .select(base.routes)
      .watch()
      .map((rutas) => {for (final ruta in rutas) ruta.id: ruta});
});

// -----------------------------------------------------------------------------
// MANDAR LO MARCADO A UNA ZONA DEL TABLERO
// -----------------------------------------------------------------------------
//
// Todo esto cuelga de las piezas del Tablero SIN pasar por `tableroProvider`, y
// no es por gusto: el `build` de ese notifier **le pide la foto al servidor**
// cuando cambia la sucursal. Usarlo desde aqui convertiria un gesto que tiene
// que funcionar sin conexion en uno que llama a la red al abrirse.
//
// `consultasTableroProvider` y `repositorioTableroProvider` son `Provider`
// pelados: leen y escriben en la base del aparato y no hablan con nadie.

/// El gesto, listo para llamarlo.
final mandarAlTableroProvider = Provider<MandarAlTablero>(
  (ref) => MandarAlTablero(
    ref.watch(baseProvider),
    ref.watch(repositorioTableroProvider),
  ),
);

/// LAS ZONAS DE LA SUCURSAL QUE SE ESTA MIRANDO, y de ninguna otra.
///
/// Es la mitad visible de la guarda del alcance: con La Habana mirada, en el
/// cajon no puede aparecer una zona de Holguin. La otra mitad la pone
/// `MandarAlTablero`, que vuelve a comprobarlo contra la base — una guarda que
/// solo vive en la lista que se pinta se cae el dia que alguien cambie de
/// sucursal con el cajon abierto.
///
/// **Stream y no Future** (`CLAUDE.md` §3-ter): en la web la base nace vacia en
/// cada carga y las zonas llegan un segundo despues. Un `Future` se resolveria
/// con la lista vacia y el cajon diria «este tablero no tiene ninguna zona»
/// para siempre, encima de un tablero con seis.
final zonasDelTableroProvider = StreamProvider<List<ColumnaTablero>>((ref) {
  final base = ref.watch(baseProvider);
  final consultas = ref.watch(consultasTableroProvider);
  // EL VALOR, NO SU `Future`. `watch` y no `read`, para que cambiar de sucursal
  // arriba rehaga la lista; y el `AsyncValue` y no `.future` porque un futuro
  // capturado en la creacion se queda esperando a una respuesta que ya no viene
  // cuando el provider de la sucursal se rehace por debajo — y entonces la
  // lista de zonas no sale NUNCA, sin error y sin aviso.
  final cual = ref.watch(sucursalDelTableroProvider);
  if (cual.isLoading) {
    // Todavia no se sabe de que sucursal es el tablero. Un stream que se cierra
    // sin decir nada deja esto «cargando», que es la verdad: cuando la sucursal
    // llegue, esto se rehace solo y emite.
    return const Stream<List<ColumnaTablero>>.empty();
  }
  final sucursalId = cual.value;
  if (sucursalId == null || sucursalId.isEmpty) {
    return Stream<List<ColumnaTablero>>.value(const <ColumnaTablero>[]);
  }

  Future<List<ColumnaTablero>> mirar() => consultas.columnas(sucursalId);

  return () async* {
    // El primero enseguida: `tableUpdates` no emite al suscribirse, y sin esto
    // el cajon arrancaria sin zonas aunque ya estuvieran en la base.
    yield await mirar();
    yield* base
        .tableUpdates(TableUpdateQuery.onTableName(EsquemaTablero.columnas))
        .asyncMap((_) => mirar());
  }();
});

/// Lo que hace el cajon, sin pantalla: crear una zona y mandarle lo marcado.
///
/// Vive aqui y no dentro del widget para que «la marca se quita al terminar» se
/// pueda comprobar sin montar nada.
class EnvioAlTablero extends Notifier<void> {
  @override
  void build() {}

  /// Una zona nueva en la sucursal que se esta mirando. Devuelve su id.
  Future<String> crearZona(String nombre) async {
    final sucursalId = await _sucursal();
    return ref
        .read(repositorioTableroProvider)
        .crearColumna(sucursalId: sucursalId, nombre: nombre);
  }

  /// Manda lo marcado a [columnaId] y **quita la marca de los que fueron**.
  ///
  /// Los que no pudieron ir se quedan marcados a proposito: el cajon dice
  /// cuales y por que, y quien esta delante sigue teniendolos a mano para
  /// arreglarlos o mandarlos a otra zona. Quitarles la marca seria descartarlos
  /// en silencio dos segundos despues de haberlo dicho.
  Future<ResultadoDeMandar> mandarLoMarcado(String columnaId) async {
    final sucursalId = await _sucursal();
    final marcados = ref.read(seleccionPedidosProvider).toList();
    final resultado = await ref
        .read(mandarAlTableroProvider)
        .mandar(
          pedidoIds: marcados,
          columnaId: columnaId,
          sucursalId: sucursalId,
        );
    ref
        .read(seleccionPedidosProvider.notifier)
        .quitarLaMarcaDe(resultado.fueron);
    return resultado;
  }

  /// Sin sucursal no hay zonas ni alcance: es el mismo rechazo del tablero, con
  /// el mismo texto.
  Future<String> _sucursal() async {
    final sucursalId = await ref.read(sucursalDelTableroProvider.future);
    if (sucursalId == null || sucursalId.isEmpty) {
      throw const FaltaElegirSucursal();
    }
    return sucursalId;
  }
}

final envioAlTableroProvider = NotifierProvider<EnvioAlTablero, void>(
  EnvioAlTablero.new,
);
