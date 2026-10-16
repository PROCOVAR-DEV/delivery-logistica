import 'package:drift/drift.dart';

import '../base/base.dart';
import '../reloj.dart';

/// De que hora son los datos de cada coleccion.
///
/// Sin esto, una pantalla con datos de anteayer es indistinguible de una al dia,
/// y ese es el modo de fallo que nadie nota: el logistico arma la ruta de ayer
/// convencido de que es la de hoy.
class RegistroDeFrescura {
  RegistroDeFrescura(this._base, {Reloj reloj = relojDelAparato})
    : _reloj = reloj;

  final BaseLocal _base;
  final Reloj _reloj;

  /// Lo escribe la bajada, coleccion a coleccion.
  ///
  /// [hasta] se guarda **tal cual vino**, en texto. No se parsea ni se
  /// recalcula: la marca la pone el servidor, y un `DateTime` de ida y vuelta
  /// puede perder precision y saltarse cambios para siempre sin que nadie lo
  /// note (`sincronizacion.md` §1).
  Future<void> marcar(
    String coleccion, {
    required String? hasta,
    DateTime? bajadaAt,
    bool completa = false,
  }) => _base
      .into(_base.frescura)
      .insertOnConflictUpdate(
        FrescuraCompanion.insert(
          coleccion: coleccion,
          hasta: Value(hasta),
          bajadaAt: Value(bajadaAt ?? _reloj()),
          completa: Value(completa),
        ),
      );

  /// OLVIDA EL CURSOR de estas colecciones: la proxima bajada las trae ENTERAS.
  ///
  /// Se llama al cambiar de sucursal arriba, y sin esto la copia se queda a
  /// medias sin que nada falle. El ciclo pide «lo que cambio desde ...», y ese
  /// «desde» es de la bajada anterior, que era **de otra sucursal**: los pedidos
  /// de la nueva no han cambiado desde entonces, asi que no vienen. Nunca.
  ///
  /// Lo que se ve, y es el fallo mas caro que hay aqui —un numero creible que
  /// ninguna pantalla desmiente—: el 26/09/2026, cambiando a Camaguey, el
  /// Tablero decia «Sin colocar (0)» y luego «(24)» mientras `GET /api/board`
  /// contestaba **40**. Comprobado pidiendoselo al servidor desde la propia
  /// pagina. Ni un error, ni una rueda: un cero.
  ///
  /// `bajadaAt` NO se toca, y es a proposito. Esa marca es «esto llego alguna
  /// vez a este aparato», y con ella puesta las pantallas siguen distinguiendo
  /// «no lo tiene» de «todavia no ha bajado» mientras la bajada nueva corre. Lo
  /// que se olvida es **hasta donde** se habia llegado, que es lo unico que
  /// depende de la sucursal que se estaba mirando.
  Future<void> olvidarElCursor(List<String> colecciones) async {
    await (_base.update(_base.frescura)
          ..where((f) => f.coleccion.isIn(colecciones)))
        .write(const FrescuraCompanion(hasta: Value(null)));
  }

  /// LOS PEDIDOS SE VUELVEN A BAJAR ENTEROS UNA VEZ POR APARATO — 15/10/2026 (1.0.35).
  ///
  /// Desde la 1.0.35 la bajada lee `facturaAt`, la fecha de la factura: ordena «Sin colocar»
  /// y sale en el detalle del pedido. Pero la bajada es POR DIFERENCIAS: un pedido que no
  /// cambia no vuelve a viajar, así que en una APK o un escritorio que ya tenían la copia
  /// esos pedidos se quedarían sin fecha PARA SIEMPRE, y «Sin colocar» saldría en otro orden
  /// que en la web sin que nada fallara (auditoría del 15/10/2026). Se olvida el cursor de
  /// pedidos una sola vez y se deja escrito que ya se hizo en esta misma tabla, con una fila
  /// que no es una colección y que ninguna pantalla lee: todas las lecturas filtran por
  /// colección. En la web no cambia nada: su base nace vacía y baja entera en cada carga.
  static const yaRebajadosPorLaFechaDeFactura =
      'una-vez:pedidos-con-factura-at';

  /// LAS RUTAS SE VUELVEN A BAJAR ENTERAS UNA VEZ POR APARATO — 15/10/2026 (issue 7).
  ///
  /// Lo mismo que la fecha de factura, con `distribuidorId`: una ruta que ya estaba en el
  /// aparato y no cambia no vuelve a viajar, y se quedaria «Sin distribuidor» para
  /// siempre aunque el servidor lo tenga. Marca PROPIA: un aparato que ya hizo la de
  /// la factura tiene que hacer esta tambien, y uno que estrena las dos a la vez hace
  /// UNA sola bajada entera (las dos olvidan el mismo cursor antes de pedir).
  static const yaRebajadasPorElDistribuidor = 'una-vez:rutas-con-distribuidor';

  /// LOS PEDIDOS Y LOS ALMACENES, OTRA VEZ, POR SU ALMACÉN — 15/10/2026 (1.0.37).
  ///
  /// Lo mismo con `almacenSalidaCodigo` (el almacén del que sale cada pedido) y con el
  /// `codigo` de cada almacén: sin ellos «Sin colocar» no puede poner primero los del
  /// almacén elegido arriba, y no fallaría nada — saldría en el orden de siempre en la
  /// APK y con los suyos arriba en la web. Marcas PROPIAS, como la de arriba.
  static const yaRebajadosPorSuAlmacen = 'una-vez:pedidos-con-su-almacen';
  /// LOS CAMIONES CON SU FICHA ENTERA — 16/10/2026 (issue 14). Hasta la 1.0.38 la bajada
  /// guardaba de cada camion solo lo basico (sin tipo, costo por km, notas ni
  /// «para domicilio»). Se piden ENTEROS (`completas=vehicles`) una vez, no con una
  /// rebajada de pedidos: ver `Bajada.ciclo`.
  static const yaBajadosLosVehiculosConSuFicha = 'una-vez:vehiculos-con-ficha';
  static const yaBajadosLosAlmacenesConCodigo = 'una-vez:almacenes-con-codigo';

  /// Olvida el cursor de [colecciones] UNA vez por aparato, y deja escrito en [marca]
  /// que ya se hizo.
  ///
  /// OJO con que cursor se olvida: `/sync/cambios` lleva UN solo `desde` para todas
  /// las colecciones, y es el de `orders` (`Bajada.ciclo`). Olvidar solo el de
  /// `routes` no cambiaria la peticion: para rebajar rutas hay que olvidar tambien el
  /// de pedidos, y entonces baja todo entero.
  Future<void> rebajarUnaVez(String marca, List<String> colecciones) =>
      _base.transaction(() async {
        if (await leer(marca) != null) return;
        await olvidarElCursor(colecciones);
        await _base
            .into(_base.frescura)
            .insertOnConflictUpdate(FrescuraCompanion.insert(coleccion: marca));
      });

  Future<void> rebajarLosPedidosUnaVez() =>
      rebajarUnaVez(yaRebajadosPorLaFechaDeFactura, const [Colecciones.pedidos]);

  Future<void> rebajarLasRutasUnaVez() => rebajarUnaVez(
    yaRebajadasPorElDistribuidor,
    const [Colecciones.pedidos, Colecciones.rutas],
  );

  Future<void> rebajarLosPedidosPorSuAlmacen() =>
      rebajarUnaVez(yaRebajadosPorSuAlmacen, const [Colecciones.pedidos]);

  Future<FilaFrescura?> leer(String coleccion) => (_base.select(
    _base.frescura,
  )..where((f) => f.coleccion.equals(coleccion))).getSingleOrNull();

  Stream<FilaFrescura?> mirar(String coleccion) => (_base.select(
    _base.frescura,
  )..where((f) => f.coleccion.equals(coleccion))).watchSingleOrNull();

  /// La marca que va en el proximo `GET /sync/bajada?desde=…`. `null` = primera
  /// carga completa.
  Future<String?> desde(String coleccion) async =>
      (await leer(coleccion))?.hasta;

  /// La bajada mas VIEJA de todas. Es la que manda en la barra: una pantalla no
  /// esta al dia si una de las colecciones que usa no lo esta.
  Stream<DateTime?> laMasVieja([List<String> colecciones = Colecciones.todas]) {
    final consulta = _base.select(_base.frescura)
      ..where((f) => f.coleccion.isIn(colecciones));
    return consulta.watch().map((filas) => _laMasVieja(filas, colecciones));
  }

  /// LA MISMA PREGUNTA, una vez y sin stream.
  ///
  /// Hace falta para decidir **en seco**: el vigia, al volver la aplicacion
  /// delante, tiene que saber si lo que hay ya tiene edad antes de disparar un
  /// ciclo entero. Ahi no hay nada que pintar ni a quien avisar de los cambios,
  /// asi que un stream sobra — y un `await` sobre el primer valor de un stream
  /// de Drift lo deja abierto detras, que en una prueba de widget es un
  /// temporizador colgado y la sesion entera se va con el.
  Future<DateTime?> laMasViejaAhora([
    List<String> colecciones = Colecciones.todas,
  ]) async {
    final filas = await (_base.select(
      _base.frescura,
    )..where((f) => f.coleccion.isIn(colecciones))).get();
    return _laMasVieja(filas, colecciones);
  }

  static DateTime? _laMasVieja(
    List<FilaFrescura> filas,
    List<String> colecciones,
  ) {
    // Una coleccion que NUNCA se bajo no tiene fila. Eso no es «al dia»: es
    // «sin descargar», y se contesta con null para que el reloj lo diga.
    if (filas.length < colecciones.length) return null;
    final fechas = filas.map((f) => f.bajadaAt).whereType<DateTime>().toList();
    if (fechas.length < colecciones.length) return null;
    fechas.sort();
    return fechas.first;
  }

  /// ¿Se bajo alguna vez esta coleccion? **Una respuesta, y ya.**
  ///
  /// Separa «no hay nada» de «no se ha descargado», que es la pregunta del caso
  /// S7. Pero ojo con usarla para pintar: una pantalla que pregunte esto una vez
  /// se queda con la respuesta del instante en que se monto, y en la web ese
  /// instante es siempre con la base vacia —nace vacia en cada carga—, asi que
  /// la pantalla se clava en «no se ha descargado» aunque los datos lleguen
  /// enseguida. Eso paso en Pedidos y en Rutas el 17/09/2026.
  ///
  /// **Para pintar se usa [mirar]**, que es un stream y se entera. Esto queda
  /// para decidir en seco, sin nada que repintar.
  Future<bool> seDescargo(String coleccion) async =>
      (await leer(coleccion))?.bajadaAt != null;
}
