// MANDAR LO MARCADO A UNA ZONA DEL TABLERO.
//
// El gesto que cerraba el flujo y no estaba. En Pedidos se marca lo que se va a
// repartir —con los nueve filtros, que es como se decide— y hasta hoy lo unico
// que se podia hacer con esa marca era imprimir el pre-despacho. Para pasarlo al
// tablero habia que irse alli y colocar los pedidos **uno a uno**.
//
// ## Lo que esto NO hace, a proposito
//
//  * **No escribe en la base ni encola nada por su cuenta.** Llama a
//    `RepositorioTablero.colocar`, que es el mismo camino del arrastre: escribe
//    la colocacion y encola su apunte EN LA MISMA transaccion. Un segundo camino
//    para lo mismo es un sitio mas donde la colocacion y el apunte se pueden
//    separar, y esa es la averia que el repositorio existe para que no pase.
//  * **No afloja ni duplica las reglas de «colocable».** Se pregunta a
//    `porQueNoSePuedeColocar`, la misma pieza que usa `RepositorioTablero.colocar`
//    y que repite palabra por palabra el «no» del servidor. Si manana cambia lo
//    que se puede colocar, cambia aqui sin que nadie se acuerde.
//  * **No descarta nada en silencio** (`CLAUDE.md` §4). Lo que no puede ir sale
//    NOMBRADO y con su motivo, con la misma forma que los descartes de
//    `armarRuta`: «F-2992 · Ana: Ya va en otra ruta».

import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import '../../tablero/datos/esquema.dart';
import '../../tablero/datos/modelos.dart';
import '../../tablero/datos/repositorio.dart';

/// Un pedido marcado que no se pudo mandar, con nombre y motivo.
class PedidoQueNoFue {
  const PedidoQueNoFue({
    required this.pedidoId,
    required this.nombre,
    required this.motivo,
  });

  final String pedidoId;

  /// Como lo reconoce quien lo marco: `F-2992 · Ana`.
  final String nombre;
  final String motivo;

  /// La linea que se le ensena a una persona, con la misma forma que los
  /// descartes de `armarRuta`.
  String get linea => '$nombre: $motivo';
}

/// Que paso al mandar lo marcado.
class ResultadoDeMandar {
  const ResultadoDeMandar({
    required this.zona,
    required this.fueron,
    required this.noFueron,
  });

  /// El nombre de la zona, para poder decir «3 pedidos en «Centro»» y no un id.
  final String zona;

  /// Los que estan puestos, en el orden en que se colocaron.
  final List<String> fueron;

  /// Los que se quedaron, nombrados y con su motivo.
  final List<PedidoQueNoFue> noFueron;

  int get cuantos => fueron.length;
  bool get alguienSeQuedo => noFueron.isNotEmpty;
}

/// Los motivos que NO salen de `MarcaTarjeta` porque no son marcas de la
/// tarjeta, sino cosas que sabe la base.
abstract final class MotivoDeQuedarse {
  /// El pedido no esta en esta base. En la web pasa el primer segundo, con la
  /// base todavia llenandose; en el aparato, si se marco algo que despues se
  /// borro.
  static const noEstaAqui = 'No está en este aparato';

  /// LA GUARDA DEL ALCANCE. Un pedido de La Habana no entra en una zona de
  /// Holguin, y no es un detalle: las zonas son de una sucursal y la cercania se
  /// mide desde SU almacen. Con el Super Admin mirando «todas», la pagina de
  /// Pedidos ensena las ocho a la vez y marcar de dos es un gesto de un segundo.
  static const deOtraSucursal = 'Es de otra sucursal';

  /// Sin coordenadas no hay tablero para el: no se puede ordenar por cercania
  /// ni medir el recorrido de la ruta que salga de la zona. Es la quinta
  /// condicion de `sinColocar`, y la unica que no vive en `MarcaTarjeta`.
  static const sinCoordenadas = 'Sin coordenadas de entrega';
}

/// El gesto, sin pantalla.
class MandarAlTablero {
  MandarAlTablero(this._base, this._repositorio);

  final BaseLocal _base;
  final RepositorioTablero _repositorio;

  /// Manda [pedidoIds] a la zona [columnaId], que tiene que ser de
  /// [sucursalId].
  ///
  /// Los que se puedan; los que no, nombrados en el resultado. **No lanza** por
  /// un pedido que no pueda ir: que uno este archivado no es motivo para dejar
  /// los otros nueve sin colocar. Lanza [RechazoDelTablero] cuando lo que no
  /// vale es la ZONA, porque entonces no hay nada que hacer con ninguno.
  Future<ResultadoDeMandar> mandar({
    required List<String> pedidoIds,
    required String columnaId,
    required String sucursalId,
  }) async {
    final zona = await _zonaDe(columnaId, sucursalId);

    // De una vez y no uno por uno: son hasta cincuenta pedidos y `colocar` ya
    // abre su propia transaccion por cada uno.
    final filas = await (_base.select(
      _base.orders,
    )..where((o) => o.id.isIn(pedidoIds))).get();
    final porId = {for (final fila in filas) fila.id: fila};

    final fueron = <String>[];
    final noFueron = <PedidoQueNoFue>[];

    // EN EL ORDEN EN QUE SE MARCARON, no en el que los devuelva la base: es el
    // orden de visita con el que nacen dentro de la zona, y quien marco de
    // arriba abajo espera encontrarlos asi.
    for (final pedidoId in pedidoIds) {
      final pedido = porId[pedidoId];
      if (pedido == null) {
        noFueron.add(
          PedidoQueNoFue(
            pedidoId: pedidoId,
            nombre: pedidoId,
            motivo: MotivoDeQuedarse.noEstaAqui,
          ),
        );
        continue;
      }

      final motivo = _porQueNoPuedeIr(pedido, sucursalId);
      if (motivo != null) {
        noFueron.add(
          PedidoQueNoFue(
            pedidoId: pedidoId,
            nombre: _nombreDe(pedido),
            motivo: motivo,
          ),
        );
        continue;
      }

      // EL MISMO CAMINO QUE EL ARRASTRE. Escribe aqui y encola, las dos cosas
      // en la misma transaccion, y no llama a nadie: el gesto tiene que
      // funcionar en el patio a las cuatro de la tarde, que es cuando se hace.
      await _repositorio.colocar(pedidoId: pedidoId, columnaId: columnaId);
      fueron.add(pedidoId);
    }

    return ResultadoDeMandar(zona: zona, fueron: fueron, noFueron: noFueron);
  }

  /// La zona existe y es DE ESTA SUCURSAL, o no se manda nada.
  ///
  /// Se comprueba aqui y no en la pantalla porque la pantalla ya ensena solo las
  /// de la sucursal mirada: una guarda que solo vive en la lista que se pinta se
  /// cae el dia que alguien cambie de sucursal con el cajon abierto.
  Future<String> _zonaDe(String columnaId, String sucursalId) async {
    await EsquemaTablero.asegurar(_base);
    final fila = await _base
        .customSelect(
          'SELECT branch_id, nombre FROM ${EsquemaTablero.columnas} '
          'WHERE id = ?1',
          variables: [Variable<String>(columnaId)],
        )
        .getSingleOrNull();
    if (fila == null) {
      throw const RechazoDelTablero('Esa zona ya no está en el tablero');
    }
    if (fila.read<String>('branch_id') != sucursalId) {
      throw const RechazoDelTablero('Esa zona es de otra sucursal');
    }
    return fila.read<String>('nombre');
  }

  /// `null` = puede ir.
  ///
  /// # LO MISMO QUE DIRIA EL SERVIDOR, con sus mismas palabras — 07/10/2026
  ///
  /// Esto mira lo que mira `porQueNoSePudoColocar` del servidor
  /// (`api/internal/api/tablero.go`), **a traves de la misma pieza que usa el
  /// arrastre** ([porQueNoSePuedeColocar]): ya entregado, ya en una ruta, domicilio
  /// cobrado y domicilio cotizado. Antes miraba solo las marcas de la tarjeta,
  /// que no saben de domicilio ni de entregado: en la web un lote de cincuenta
  /// abortaba a medias en el primer 409 —el servidor si lo mira— y en la APK se
  /// mandaba al tablero lo que el servidor iba a rechazar horas despues.
  ///
  /// Lo propio de aqui, que el servidor no dice en ese «no»: que el pedido sea de
  /// otra sucursal, que este archivado en PEDIDO, que no tenga punto de entrega y
  /// las dos marcas graves de factura (sin cotejar, sin factura). Estas ultimas
  /// el servidor al colocar no las mira, pero la ruta de la zona las descartaria
  /// y la lista de «Sin colocar» tampoco las ofrece: mandarlas seria fabricar el
  /// descarte.
  String? _porQueNoPuedeIr(Pedido pedido, String sucursalId) {
    if (pedido.branchId != sucursalId) return MotivoDeQuedarse.deOtraSucursal;
    if (pedido.archivado) return MarcaTarjeta.archivado.texto;

    final delServidor = porQueNoSePuedeColocar(pedido);
    if (delServidor != null) return delServidor;

    if (pedido.facturaEstado == null) return MarcaTarjeta.sinCotejar.texto;
    if (pedido.facturaEstado == EstadoFactura.sinFactura) {
      return MarcaTarjeta.sinFactura.texto;
    }

    if (pedido.endLat == null || pedido.endLng == null) {
      return MotivoDeQuedarse.sinCoordenadas;
    }
    return null;
  }

  static String _nombreDe(Pedido pedido) =>
      '${pedido.operationNumber ?? pedido.id} · ${pedido.customerName}';
}
