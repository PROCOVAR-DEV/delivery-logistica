// Lo que Pedidos ESCRIBE: el punto de entrega puesto a MANO (issue 19 de Amado,
// «Geolocalización», Reparto 1.0.39; Jose, 20/10/2026).
//
// El cliente pide entregar en otro sitio y quien factura lo apunta en el ticket:
// esa dirección no coincide con la geolocalización del cliente, que es la única
// que manda PEDIDO. El logístico, al armar la ruta, le pone a mano el punto
// (lat, lng y dirección) y ese punto MANDA sobre el del cliente y sobrevive al
// espejo (eso último lo hace el servidor, `api/internal/api/punto_de_entrega.go`).
//
// Las TRES formas de la aplicación (`CLAUDE.md` §1), como `AccionesDeRuta`:
//
//  * WEB ([EscrituraEnVivo] no nulo): va al servidor y ESPERA. Con un 4xx sale su
//    literal y no se escribe ninguna fila; con un 200 se refleja lo que él guardó.
//    No hay cola.
//  * APK y ESCRITORIO: se valida aquí con LOS MISMOS literales del servidor, y en
//    UNA transacción se escribe la fila, se recalcula lo que el aparato ya sabe
//    calcular sin conexión (el km de la parada y el total de su ruta, con las
//    mismas cuentas del armado) y se encola el apunte. La bajada trae la verdad.
//
// # LO QUE EL APARATO NO RECALCULA: `deliveryDistanceKm`
//
// El servidor lo mide desde el almacén DEL PEDIDO con `ElegirOrigenDelPedido`
// (código del almacén, degradación al principal, último recurso el punto de la
// sucursal). Esa elección no tiene gemela en Dart —`AlmacenDeReferencia` es la del
// almacén principal, no la del pedido— y escribirla aquí sería una tercera copia de
// una regla que se separa sin que salte nada (§3-bis). Así que en la APK y el
// escritorio `deliveryDistanceKm` se queda como estaba hasta que suba el apunte y
// baje el servidor, que es quien manda.

import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/cola/cola_salida.dart';
import '../../../nucleo/red/escritura_en_vivo.dart';
import '../../../nucleo/registro/registro.dart';
import '../../../nucleo/reloj.dart';
import '../../rutas/datos/acciones_rutas.dart'
    show RechazoLocal, msgRutaSinOrigen;
import '../../rutas/datos/geo.dart';

/// Los «no» de las dos puertas, LETRA POR LETRA los del servidor
/// (`punto_de_entrega.go`). Sin señal los dice el aparato y con ella la nube: si no
/// se leen igual, el mismo rechazo enseña dos idiomas (`CLAUDE.md` §3-quinquies).
const msgPuntoNoEncontrado = 'No encontrado';
const msgPuntoImposible = 'lat y lng tienen que ser un punto del planeta';
const msgPuntoYaEntregado =
    'La factura ya está entregada: no se le puede cambiar el punto';
const msgPuntoRutaCompletada =
    'La ruta ya está completada: no se le puede cambiar el punto a sus paradas';
const msgPuntoNoEsManual = 'La factura no tiene un punto puesto a mano';
const msgPuntoSinPuntoCliente =
    'La factura no guardó el punto del cliente: no se puede volver a él';

/// ¿Se le puede cambiar el punto a este pedido? `null` = sí; si no, el literal
/// del porqué. Lo usa la acción para rechazar y la pantalla para no enseñar el
/// botón y DECIR por qué: son la misma pregunta y no pueden contestar distinto.
String? porQueNoSeLePuedeCambiarElPunto(Pedido pedido, Ruta? ruta) {
  if (pedido.deliveredAt != null ||
      pedido.resultado == ResultadoParada.entregado) {
    return msgPuntoYaEntregado;
  }
  if (ruta != null && ruta.status == EstadoRuta.completada) {
    return msgPuntoRutaCompletada;
  }
  return null;
}

class AccionesDePedido {
  AccionesDePedido(
    this._base,
    this._cola, {
    Reloj reloj = relojDelAparato,
    EscrituraEnVivo? enVivo,
  }) : _reloj = reloj,
       _enVivo = enVivo;

  final BaseLocal _base;
  final ColaDeSalida _cola;
  final Reloj _reloj;

  /// `null` en la APK y en el escritorio, que es donde la cola es la respuesta
  /// correcta. Se decide fuera, en `proveedores_pedidos.dart`.
  final EscrituraEnVivo? _enVivo;

  /// Lo que ya va de camino, por acción: un clic duplicado por el navegador
  /// (medido en Vehículos el 01/10/2026) no manda dos `PUT`. Al segundo se le
  /// devuelve el MISMO `Future`. Ver la explicación larga en `AccionesDeRuta`.
  final Map<String, Future<void>> _enVuelo = <String, Future<void>>{};

  Future<void> _unaSola(String clave, Future<void> Function() accion) {
    final yaVa = _enVuelo[clave];
    if (yaVa != null) return yaVa;
    final vuelo = accion();
    _enVuelo[clave] = vuelo;
    vuelo.whenComplete(() {
      if (_enVuelo[clave] == vuelo) _enVuelo.remove(clave);
    }).ignore();
    return vuelo;
  }

  /// PONE A MANO el punto de entrega de [pedidoId]. [direccion] vacía o en blanco
  /// es «no la cambies» (como en el servidor: dejar un punto sin dirección es
  /// dejar a quien reparte sin saber a qué puerta llamar).
  Future<void> ponerPunto(
    String pedidoId, {
    required double lat,
    required double lng,
    String? direccion,
  }) => _unaSola('punto:$pedidoId', () async {
    if (!puntoDelPlaneta(lat, lng) || (lat == 0 && lng == 0)) {
      throw const RechazoLocal(msgPuntoImposible);
    }
    final dicha = direccion?.trim();
    final cuerpo = <String, Object?>{
      'lat': lat,
      'lng': lng,
      if (dicha != null && dicha.isNotEmpty) 'direccion': dicha,
    };
    final (:pedido, :ruta) = await _poderTocar(pedidoId);

    final enVivo = _enVivo;
    if (enVivo != null) {
      final respuesta = await _mandar(
        enVivo,
        metodo: 'PUT',
        ruta: '/orders/$pedidoId/punto',
        cuerpo: cuerpo,
      );
      await _reflejar(pedido, respuesta);
      return;
    }

    await _escribir(
      pedido,
      ruta,
      lat: lat,
      lng: lng,
      orden: OrdersCompanion(
        endAddress: dicha != null && dicha.isNotEmpty
            ? Value(dicha)
            : const Value.absent(),
        puntoManual: const Value(true),
        // QUIÉN LO PUSO lo sabe el servidor (la sesión); aquí no se inventa un
        // nombre: se queda vacío hasta que baje.
        puntoManualPor: const Value(null),
        puntoManualAt: Value(_reloj()),
        // El punto que traía el cliente se guarda SOLO la primera vez: a la
        // segunda lo que hay en `end*` ya es el de la mano, y guardarlo perdería
        // a dónde volver.
        puntoClienteLat: pedido.puntoManual
            ? const Value.absent()
            : Value(pedido.endLat),
        puntoClienteLng: pedido.puntoManual
            ? const Value.absent()
            : Value(pedido.endLng),
        puntoClienteAddress: pedido.puntoManual
            ? const Value.absent()
            : Value(pedido.endAddress),
      ),
      metodo: 'PUT',
      cuerpo: cuerpo,
    );
  });

  /// VUELVE al punto del cliente: el último que mandó el espejo, guardado en
  /// `puntoCliente*` mientras el pedido es manual.
  Future<void> volverAlPuntoDelCliente(String pedidoId) =>
      _unaSola('punto:$pedidoId', () async {
        final (:pedido, :ruta) = await _poderTocar(pedidoId);
        if (!pedido.puntoManual) throw const RechazoLocal(msgPuntoNoEsManual);
        final lat = pedido.puntoClienteLat;
        final lng = pedido.puntoClienteLng;
        if (lat == null || lng == null) {
          throw const RechazoLocal(msgPuntoSinPuntoCliente);
        }

        final enVivo = _enVivo;
        if (enVivo != null) {
          final respuesta = await _mandar(
            enVivo,
            metodo: 'DELETE',
            ruta: '/orders/$pedidoId/punto',
          );
          await _reflejar(pedido, respuesta);
          return;
        }

        await _escribir(
          pedido,
          ruta,
          lat: lat,
          lng: lng,
          orden: OrdersCompanion(
            endAddress: Value(pedido.puntoClienteAddress),
            puntoManual: const Value(false),
            puntoManualPor: const Value(null),
            puntoManualAt: const Value(null),
            puntoClienteLat: const Value(null),
            puntoClienteLng: const Value(null),
            puntoClienteAddress: const Value(null),
          ),
          metodo: 'DELETE',
          cuerpo: const <String, Object?>{},
        );
      });

  /// El pedido y su ruta, o el «no» de siempre: no existe, ya se entregó, o su
  /// ruta es histórico. Las mismas comprobaciones y en el mismo orden que el
  /// servidor (`pedidoParaElPunto`).
  Future<({Pedido pedido, Ruta? ruta})> _poderTocar(String pedidoId) async {
    final pedido = await (_base.select(
      _base.orders,
    )..where((o) => o.id.equals(pedidoId))).getSingleOrNull();
    if (pedido == null) throw const RechazoLocal(msgPuntoNoEncontrado);
    final rutaId = pedido.routeId;
    final ruta = rutaId == null
        ? null
        : await (_base.select(
            _base.routes,
          )..where((r) => r.id.equals(rutaId))).getSingleOrNull();
    final no = porQueNoSeLePuedeCambiarElPunto(pedido, ruta);
    if (no != null) throw RechazoLocal(no);
    return (pedido: pedido, ruta: ruta);
  }

  /// La APK y el escritorio: la fila, el km de la parada, el total de la ruta y el
  /// apunte, TODO en una transacción. Una fila escrita sin su apunte es un cambio
  /// que no sube nunca; un apunte sin su fila, una pantalla que lo desmiente.
  Future<void> _escribir(
    Pedido pedido,
    Ruta? ruta, {
    required double lat,
    required double lng,
    required OrdersCompanion orden,
    required String metodo,
    required Map<String, Object?> cuerpo,
  }) async {
    final origen = ruta == null ? null : _origenDe(ruta);
    final ahora = _reloj();
    await _base.transaction(() async {
      await (_base.update(
        _base.orders,
      )..where((o) => o.id.equals(pedido.id))).write(
        orden.copyWith(
          endLat: Value(lat),
          endLng: Value(lng),
          lat: Value(lat),
          lng: Value(lng),
          // LA RADIAL desde el origen de la ruta, como al armar (y como el
          // servidor: `kmHaversine` del origen al punto nuevo).
          segmentKm: origen == null
              ? const Value.absent()
              : Value(haversineKm(origen, Punto(lat, lng))),
          updatedAt: Value(ahora),
        ),
      );
      if (ruta != null && origen != null) {
        await _recalcularElTotal(ruta, origen);
      }
      await _cola.encolar(
        metodo: metodo,
        ruta: '/orders/${pedido.id}/punto',
        cuerpo: cuerpo,
      );
    });
  }

  /// El punto de salida de la ruta. Sin él no se pueden medir los km: el mismo
  /// 409 del servidor. (Una ruta que no baja entera no llega aquí: `ruta` es
  /// `null` y la parada se queda con el km que traía.)
  Punto _origenDe(Ruta ruta) {
    final lat = ruta.originLat;
    final lng = ruta.originLng;
    if (lat == null || lng == null) throw const RechazoLocal(msgRutaSinOrigen);
    return Punto(lat, lng);
  }

  /// El circuito de la ruta con las paradas como están AHORA y en el orden que
  /// tienen (`stopOrder`, `createdAt`). No se toca `optimized`: mover un punto no
  /// cambia quién ordenó las paradas.
  Future<void> _recalcularElTotal(Ruta ruta, Punto origen) async {
    final cargadas =
        await (_base.select(_base.orders)
              ..where((o) => o.routeId.equals(ruta.id))
              ..orderBy([
                (o) => OrderingTerm.asc(o.stopOrder, nulls: NullsOrder.last),
                (o) => OrderingTerm.asc(o.createdAt),
              ]))
            .get();
    final conPunto = [
      for (final p in cargadas)
        if (p.endLat != null &&
            p.endLng != null &&
            puntoDelPlaneta(p.endLat!, p.endLng!))
          Parada(p.id, p.endLat!, p.endLng!),
    ];
    await (_base.update(
      _base.routes,
    )..where((r) => r.id.equals(ruta.id))).write(
      RoutesCompanion(
        totalDistance: Value(kmDelCircuito(origen, conPunto)),
        // `rutaConTodo` solo se rehace cuando cambia la fila de la ruta: sin tocar
        // `updatedAt`, un total que saliera igual dejaría el croquis con el punto viejo.
        updatedAt: Value(_reloj()),
      ),
    );
  }

  Future<Object?> _mandar(
    EscrituraEnVivo enVivo, {
    required String metodo,
    required String ruta,
    Map<String, Object?> cuerpo = const <String, Object?>{},
  }) async {
    try {
      return await enVivo.mandar(metodo: metodo, ruta: ruta, cuerpo: cuerpo);
    } on RechazoDelServidor catch (no) {
      throw RechazoLocal(no.motivo);
    }
  }

  /// LO QUE EL SERVIDOR GUARDÓ, reflejado en la base de la pestaña (la web): el
  /// punto, la marca y los dos km que recalculó. Los `puntoCliente*` no vienen en
  /// la respuesta: se deducen igual que en la APK (se guardan la primera vez, se
  /// sueltan al volver) y la bajada trae la verdad.
  Future<void> _reflejar(Pedido antes, Object? respuesta) async {
    if (respuesta is! Map<Object?, Object?>) {
      Registro.fallo('el punto se guardo y la respuesta llego sin datos');
      throw const RechazoLocal(
        'El punto se guardó en el servidor, pero la respuesta llegó sin datos. '
        'Recarga la pantalla para verlo.',
      );
    }
    double? numero(Object? v) => v is num ? v.toDouble() : null;
    final manual = respuesta['puntoManual'] == true;
    final lat = numero(respuesta['endLat']);
    final lng = numero(respuesta['endLng']);
    final direccion = respuesta['endAddress'];
    final cuando = respuesta['puntoManualAt'];
    final km = numero(respuesta['deliveryDistanceKm']);
    final segmento = numero(respuesta['segmentKm']);
    await (_base.update(
      _base.orders,
    )..where((o) => o.id.equals(antes.id))).write(
      OrdersCompanion(
        endLat: Value(lat),
        endLng: Value(lng),
        lat: Value(lat),
        lng: Value(lng),
        endAddress: Value(direccion is String ? direccion : null),
        puntoManual: Value(manual),
        puntoManualPor: Value(
          respuesta['puntoManualPor'] is String
              ? respuesta['puntoManualPor']! as String
              : null,
        ),
        puntoManualAt: Value(
          cuando is String ? DateTime.tryParse(cuando)?.toUtc() : null,
        ),
        puntoClienteLat: manual && !antes.puntoManual
            ? Value(antes.endLat)
            : (manual ? const Value.absent() : const Value(null)),
        puntoClienteLng: manual && !antes.puntoManual
            ? Value(antes.endLng)
            : (manual ? const Value.absent() : const Value(null)),
        puntoClienteAddress: manual && !antes.puntoManual
            ? Value(antes.endAddress)
            : (manual ? const Value.absent() : const Value(null)),
        deliveryDistanceKm: km == null ? const Value.absent() : Value(km),
        segmentKm: segmento == null ? const Value.absent() : Value(segmento),
      ),
    );
    // La ruta se entera: el servidor ya recalculó sus totales (llegarán con la
    // bajada) y el detalle de la ruta se rehace al cambiar su fila, no la del pedido.
    final rutaId = antes.routeId;
    if (rutaId != null) {
      await (_base.update(_base.routes)..where((r) => r.id.equals(rutaId)))
          .write(RoutesCompanion(updatedAt: Value(_reloj())));
    }
  }
}
