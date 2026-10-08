// Lo que Rutas ESCRIBE. Es el corazon del proyecto.
//
// Las cinco acciones —armar, iniciar, completar, eliminar y cerrar parada por
// parada— hacen siempre lo mismo y en este orden:
//
//   1. se comprueba **en el aparato** lo que se puede comprobar, con los mensajes
//      LITERALES del servidor, para que un rechazo local y uno remoto se lean
//      igual;
//   2. se escribe en la base local y se pinta como hecho;
//   3. se encola el apunte con la **hora del aparato** y se sube por detras.
//
// EN LA APK Y EN EL ESCRITORIO no hay un «modo sin conexion»: eso es lo que
// pasa siempre, tenga red o no. Quien tenga senal todo el dia simplemente vera
// subir la cola a medida que trabaja. El caso que manda es el otro: el patio del
// almacen, donde no hay senal, es donde se cierra la ruta.
//
// # LA WEB NO. LA WEB ESCRIBE EN EL SERVIDOR Y ESPERA — 22/09/2026
//
// Aqui ponia «esto es lo que pasa siempre», y en la web eso era falso de la
// peor manera posible. Medido en produccion: se armaba una ruta con tres
// pedidos, el asistente se cerraba, **no salia ni un mensaje**, y tras un F5 no
// habia ruta. La unica peticion que salia al pulsar «Generar Ruta» era
// `POST /sync/aparato`, y contestaba 401 — en un navegador no hay par de tokens
// que dar de alta, la sesion es la cookie de Accesos. O sea: el apunte se
// quedaba en una cola que no sube, sobre una base **en memoria** que muere al
// recargar, y ninguna pantalla lo desmentia.
//
// `CLAUDE.md` §1, palabras de Jose: «la web siempre esta en vivo porque saca de
// la base de datos de la nube, no de una extra». Asi que cuando hay
// [EscrituraEnVivo] —y solo la hay en la web— las cinco acciones cambian de
// orden y de forma:
//
//   1. se comprueba lo que se pueda con lo que hay delante, igual que siempre;
//   2. **se manda al servidor y se espera su respuesta**;
//   3. si dice que no, no se escribe una sola fila y sale su motivo LITERAL
//      (`CLAUDE.md` §3-quinquies);
//   4. si dice que si, se refleja lo que el servidor guardo —con SU id, no con
//      un `local-...`— para que la pantalla ensene lo que hay arriba.
//
// No se encola nada. No hay id provisional. Y como la cola se queda vacia, el
// `POST /sync/aparato` de cada ciclo tampoco vuelve a salir: `Subida.ciclo`
// se planta en `if (lote.isEmpty) return 0` antes de tocar la red.

import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/cola/cola_salida.dart';
import '../../../nucleo/cola/provisionales.dart';
import '../../../nucleo/red/escritura_en_vivo.dart';
import '../../../nucleo/registro/registro.dart';
import '../../../nucleo/reloj.dart';
import 'geo.dart';
import 'importe_de_la_ruta.dart';

/// LA CABECERA DEL RECHAZO DEL ARMADO, con sus dos numeros.
///
/// [seCaen] son los pedidos que no pueden ir y [seEligieron] los que la persona
/// marco en la pantalla — no los ids distintos: es lo que tiene delante
/// mientras lee el aviso.
///
/// **Es letra por letra la del servidor** (`encabezadoDelArmado` en
/// `api/internal/api/rutas.go`): sin señal el rechazo lo redacta el aparato y
/// con señal lo redacta la nube, y dos redacciones del mismo «no» obligan a
/// aprender dos idiomas de error. Lo que ata las dos es
/// `docs/armado-rechazado.casos.json`, que leen las dos pruebas.
///
/// # El singular — 29/09/2026
///
/// Decia «1 de los 1 pedidos elegidos no pueden ir en esta ruta»: tres faltas en
/// siete palabras, y en el caso mas comun de todos, elegir UN pedido y que no
/// entre. Son dos concordancias distintas porque los dos numeros cuentan cosas
/// distintas: el verbo va con los que se caen, que son el sujeto, y el
/// sustantivo con los que se eligieron. Y con un solo pedido elegido los dos
/// numeros son el mismo, asi que decir «1 de 1» no informa de nada y la frase va
/// sin ellos.
///
/// El patron de plural es el de la casa —`n == 1 ? singular : plural`, como
/// `EnlaceDeLaRuta.cuantasParadas`—, con el cero cayendo en plural.
String encabezadoDelArmado(int seCaen, int seEligieron) {
  final verbo = seCaen == 1 ? 'no puede ir' : 'no pueden ir';
  if (seEligieron == 1) return 'El pedido elegido $verbo en esta ruta: ';
  return '$seCaen de los $seEligieron pedidos elegidos $verbo en esta ruta: ';
}

/// Un «no» dicho por el aparato, con el MISMO texto que diria el servidor.
///
/// Se comprueba aqui lo que se puede para que el rechazo tardio —el que llega
/// horas despues, al subir, y sale en la bandeja— sea la excepcion y no lo
/// normal. Y con el mismo texto para que nadie tenga que aprender dos idiomas de
/// error.
class RechazoLocal implements Exception {
  const RechazoLocal(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// El mismo rechazo del servidor para el histórico ya completado.
const msgRutaCompletada =
    'La ruta está completada y no se puede modificar ni eliminar: se conserva como histórico.';

/// Los dos «no» de «Quitar de ruta», LETRA POR LETRA los del servidor
/// (`quitarParadaPlanificada`, `api/internal/api/rutas.go`), sin punto final.
/// Sin señal los dice el aparato y con ella la nube: si no se leen igual, el
/// mismo rechazo enseña dos idiomas (`CLAUDE.md` §3-quinquies).
const msgSoloSeRetiranDeRutaPlanificada =
    'Sólo se pueden retirar paradas de una ruta planificada';
const msgParadaNoPerteneceAPlanificada =
    'El pedido no pertenece a una ruta planificada o ya fue retirado';

/// El «no» de armar con un camión dado de baja, el literal del servidor
/// (`api/internal/api/rutas.go`, `armarRuta`). Con el camión en `isActive =
/// false` el servidor contesta 400 con esto; el aparato lo dice antes para que
/// no llegue horas después a la bandeja de rechazados.
const msgVehiculoInactivo =
    'El vehículo está inactivo y no se puede asignar a una ruta.';

/// Como acabo una parada, tal y como sale del cierre.
class MarcaDeParada {
  const MarcaDeParada({
    required this.pedidoId,
    required this.resultado,
    this.nota,
  });

  final String pedidoId;

  /// `entregado` | `devuelto` | `cancelado`, **o `null` = QUITAR LA MARCA**.
  ///
  /// Lo tercero se añadió el 28/09/2026. Jose: «desmarco el estado de cierre y
  /// no se guarda cuando salgo por q razon».
  ///
  /// En la hoja de cierre, pulsar dos veces el mismo botón desmarca —así se
  /// corrige un dedazo, y estaba puesto desde el principio—, pero esa marca
  /// quitada **no tenía por dónde salir de la pantalla**: la hoja sólo armaba
  /// `MarcaDeParada` para las paradas CON resultado, así que al volver a abrir
  /// seguía puesta. El clásico de «no viene» leído como «no lo toques» en vez
  /// de como «bórralo», con el agravante de que aquí ni siquiera venía.
  ///
  /// En el JSON viaja como `"resultado": null` EXPLÍCITO, que es distinto de no
  /// mandar el campo: el servidor lo lee con `httpx.Opcional` y distingue los
  /// dos (`api/internal/api/rutas.go`, `entradaDeCierre`).
  final String? resultado;
  final String? nota;

  bool get seEntrego => resultado == ResultadoParada.entregado;

  /// Esta marca no marca: la quita.
  bool get quitaLaMarca => resultado == null;

  Map<String, Object?> aJson() => <String, Object?>{
    'orderId': pedidoId,
    'resultado': resultado,
    'nota': nota,
  };
}

/// Una parada que el servidor NO guardó en un cierre parcial (409 con
/// `aplicados` y `rechazados`).
///
/// [numeroOperacion] es el CONDUCE (`orders.operation_number`), que es como la
/// persona reconoce una factura; el servidor lo manda en cada elemento de
/// `rechazados[]`. Un servidor viejo no lo manda: [conduce] cae entonces al
/// [pedidoId], feo pero honesto, antes que dejar la parada sin nombre.
class ParadaRechazada {
  const ParadaRechazada({
    required this.pedidoId,
    required this.motivo,
    this.numeroOperacion,
  });

  final String pedidoId;
  final String? numeroOperacion;

  /// El motivo literal del servidor, sin envolver (§3-quinquies).
  final String motivo;

  /// Con qué se nombra la parada: su número de operación, o el id si no vino.
  String get conduce {
    final numero = numeroOperacion?.trim() ?? '';
    return numero.isEmpty ? pedidoId : numero;
  }
}

/// Lo que dejó guardar el cierre de una ruta.
///
/// [claveDelApunte] es la del apunte de la cola con la que se le sigue la pista;
/// va vacía en la web, que no tiene cola porque el cierre ya está arriba.
/// [rechazadas] sólo viene cuando el servidor guardó unas paradas y rechazó otras
/// (409 parcial): cada una con su conduce y su motivo literal, y [idsAplicados]
/// dice cuáles sí. La pantalla obliga a acusar recibo (`CierreDeRuta`).
class ResultadoCierreDeRuta {
  const ResultadoCierreDeRuta({
    required this.idsAplicados,
    this.claveDelApunte = '',
    this.rechazadas = const <ParadaRechazada>[],
  });

  final Set<String> idsAplicados;
  final String claveDelApunte;
  final List<ParadaRechazada> rechazadas;
}

class AccionesDeRuta {
  AccionesDeRuta(
    this._base,
    this._cola, {
    Reloj reloj = relojDelAparato,
    String sufijoAparato = 'LOC',
    EscrituraEnVivo? enVivo,
  }) : _reloj = reloj,
       _sufijo = sufijoAparato,
       _enVivo = enVivo;

  final BaseLocal _base;
  final ColaDeSalida _cola;
  final Reloj _reloj;

  /// QUIEN MANDA EL GESTO AL SERVIDOR Y ESPERA. `null` en la APK y en el
  /// escritorio, que es donde la cola es la respuesta correcta.
  ///
  /// Se decide **fuera**, en `proveedores_rutas.dart`, y no preguntando aqui por
  /// `Destino.trabajaSinConexion`: asi una prueba puede ejercitar los dos mundos
  /// sin compilar para web, que es justo lo que no habia — la web estuvo sin
  /// poder escribir un solo apunte desde que existe y no habia ni una prueba que
  /// lo dijera.
  final EscrituraEnVivo? _enVivo;

  /// Manda el gesto y traduce el «no» al idioma que la pantalla ya entiende.
  ///
  /// Las cuatro pantallas de Rutas cazan `RechazoLocal` y pintan su `mensaje`
  /// tal cual (`vista/asistente_nueva_ruta.dart`, `vista/detalle_ruta.dart`,
  /// `vista/lista_rutas.dart`, `vista/cierre_de_ruta.dart`). Cualquier otra
  /// excepcion que saliera de aqui no la caza nadie: el cajon se quedaria
  /// abierto y mudo, que es la mitad del fallo que esto viene a arreglar.
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

  /// El sufijo que distingue los codigos de ruta generados sin conexion. Sin el,
  /// dos sucursales sin red el mismo dia generan `RT-20260914-001` las dos.
  final String _sufijo;

  /// LO QUE YA VA DE CAMINO, por accion.
  ///
  /// UN SOLO CLIC MANDABA DOS BORRADOS — 01/10/2026, medido en Vehiculos con el
  /// navegador delante: un espia de raton certifico UN `pointerdown`, UN
  /// `pointerup` y UN `click`, y el registro de red enseno DOS `DELETE` a 113 ms
  /// uno del otro. El primero contesto `200 {"success":true}` y el segundo `404
  /// {"error":"Not found"}`, porque el camion ya no estaba: lo habia borrado el
  /// primero. El gesto se duplica **en el navegador** —el mismo clic llega por
  /// los eventos de puntero y por el nodo de accesibilidad del boton— y eso
  /// desde aqui no se arregla. Todo el detalle esta en
  /// `pantallas/vehiculos/estado/estado_vehiculos.dart`.
  ///
  /// `Eliminar` de la lista de rutas tenia el mismo agujero y es peor: aqui el
  /// «no» del segundo borrado se pinta LITERAL por el §4, asi que lo que se ve
  /// es «No encontrada» —o el `Not found` del servidor— **encima de un borrado
  /// que si funciono**. El §4 hace lo suyo; lo que estaba mal es que hubiera un
  /// rechazo que no debia existir.
  ///
  /// Dos cosas que no se pueden perder, las dos razonadas en Vehiculos:
  ///
  ///  * la llave es **por accion concreta** y no una para toda la pantalla: con
  ///    una global, borrar la ruta A y acto seguido la B dejaria la B tirada sin
  ///    decir nada, que es el descarte en silencio que prohibe el §4;
  ///  * al segundo que llega se le devuelve **el mismo `Future`**, no un `false`
  ///    ni un rechazo inventado: los dos ven el mismo resultado y la pantalla se
  ///    comporta como lo que de verdad hubo, un gesto. Si el primero falla, los
  ///    dos reciben el mismo `RechazoLocal`.
  ///
  /// Y es «mientras va», no «una sola vez en la vida»: la llave se suelta en
  /// cuanto termina, asi que reintentar a mano tras un fallo de red sigue
  /// saliendo.
  final Map<String, Future<void>> _enVuelo = <String, Future<void>>{};

  /// La puerta: una sola de cada [clave] a la vez.
  Future<void> _unaSola(String clave, Future<void> Function() accion) {
    final yaVa = _enVuelo[clave];
    if (yaVa != null) return yaVa;
    final vuelo = accion();
    _enVuelo[clave] = vuelo;
    // Se suelta en cuanto termina, salga bien o mal. Y el `Future` que devuelve
    // `whenComplete` se IGNORA a proposito: si `vuelo` acaba en `RechazoLocal`,
    // ese segundo `Future` acaba igual, y un error que nadie escucha lo denuncia
    // Dart como no atrapado. Quien lo tiene que escuchar es quien llamo, y a ese
    // se le devuelve `vuelo`.
    vuelo.whenComplete(() {
      if (_enVuelo[clave] == vuelo) _enVuelo.remove(clave);
    }).ignore();
    return vuelo;
  }

  /// El maximo que acepta el servidor para la nota de una parada.
  static const topeDeNota = 500;

  // ---------------------------------------------------------------------------
  // Armar
  // ---------------------------------------------------------------------------

  /// Arma una ruta con pedidos que ya existen. Devuelve el id de la ruta, que
  /// sin conexion es un `local-…`.
  ///
  /// El orden de visita, los km, el peso y el precio se calculan **en el
  /// aparato** (`geo.dart`, calcado de `reglas-negocio.md` §1): si los pusiera el
  /// servidor, no se podria armar una ruta sin red, que es la mitad del dia.
  ///
  /// [optimizar] dice QUIEN ORDENA LAS PARADAS, y de ahi sale `optimized` tal
  /// cual. Con `true` —lo de siempre— el orden lo calcula `ordenDeVisita`. Con
  /// `false` se respeta el de [pedidoIds], que es el que puso una persona que
  /// conoce las calles de su distrito, y la ruta se guarda diciendolo.
  Future<String> armar({
    required String? vehiculoId,
    required List<String> pedidoIds,
    required double? origenLat,
    required double? origenLng,
    String? nombre,
    String? origenDireccion,
    String? sucursalId,
    DateTime? fechaDeEntrega,
    bool optimizar = true,
  }) async {
    // Las validaciones van en el ORDEN ESTRICTO del servidor: si dos fallan a la
    // vez, la persona tiene que leer el mismo mensaje en los dos sitios.
    if (origenLat == null || origenLng == null) {
      throw const RechazoLocal(
        'Las coordenadas del punto de partida son requeridas',
      );
    }
    if (vehiculoId == null || vehiculoId.isEmpty) {
      throw const RechazoLocal('Se requiere un vehículo para crear la ruta');
    }
    if (pedidoIds.isEmpty) {
      throw const RechazoLocal(
        'Una ruta se arma eligiendo pedidos ya existentes. Manda `orderIds`.',
      );
    }

    final pedidos = await _pedidosArmables(pedidoIds, sucursalId);

    // EL REPETIDO NO ES UN CONFLICTO. Mandar dos veces el mismo id devolvia UNA
    // fila para DOS ids, `1 < 2` se cumplia, y el aviso salia vacio de verdad:
    // «0 de los 3 pedidos elegidos no pueden ir en esta ruta: .» — un «no» sin
    // nadie dentro, sobre pedidos que estaban perfectamente libres. Ademas el
    // servidor los acepta, asi que el aparato negaba lo que la nube permite.
    //
    // Lo que falta se cuenta sobre los ids DISTINTOS, igual que `faltanDelArmado`
    // en `api/internal/api/rutas.go`. La M del mensaje sigue siendo lo que la
    // persona marco en la pantalla, que es lo que tiene delante al leerlo.
    if (pedidos.length < pedidoIds.toSet().length) {
      throw RechazoLocal(
        await _porQueNoSePuedenArmar(pedidoIds, pedidos, sucursalId),
      );
    }

    // SOLO LO QUE CUADRA CON LA FACTURA, `igual`, y `cambiado` NO entra —
    // 07/10/2026, Jose: «en el camión sólo sube lo que cuadra con la factura».
    // Es la regla de siempre y el servidor la sigue diciendo (`mensajeNoFacturados`
    // en `api/internal/api/rutas.go`); lo nuevo de Amado (domicilio cobrado y
    // cotización) se suma debajo, no sustituye a esto.
    final noFacturados = [
      for (final p in pedidos)
        if (p.facturaEstado != EstadoFactura.igual) p,
    ];
    if (noFacturados.isNotEmpty) {
      throw RechazoLocal(_mensajeDeFactura(noFacturados));
    }
    final sinDomicilioCobrado = [
      for (final p in pedidos)
        if (p.facturaDomicilio == null || p.facturaDomicilio! <= 0) p,
    ];
    if (sinDomicilioCobrado.isNotEmpty) {
      throw RechazoLocal(_mensajeDeDomicilioSinCobrar(sinDomicilioCobrado));
    }
    final sinCotizacion = [
      for (final p in pedidos)
        if (p.pedidoCosto == null) p,
    ];
    if (sinCotizacion.isNotEmpty) {
      throw RechazoLocal(_mensajeSinCotizacion(sinCotizacion));
    }

    final pesoTotal = pedidos.fold<double>(0, (suma, p) => suma + p.weight);
    final vehiculo = await (_base.select(
      _base.vehicles,
    )..where((v) => v.id.equals(vehiculoId))).getSingleOrNull();
    // Si el vehiculo no esta en el aparato NO se valida capacidad y la ruta se
    // crea igual: es lo que hace el servidor, y negarla aqui dejaria sin armar
    // rutas a quien todavia no ha bajado su flota.
    //
    // UN CAMION DADO DE BAJA NO SALE — 07/10/2026, Amado. El servidor lo
    // rechaza con un 400 y este literal, ANTES de medir la capacidad; el aparato
    // lo dice en el mismo orden para que el «no» no llegue horas despues a la
    // bandeja. Una bajada vieja trae `isActive` ausente = activo (`bajada.dart`),
    // asi que esto solo salta cuando alguien lo dio de baja de verdad.
    if (vehiculo != null && !vehiculo.isActive) {
      throw const RechazoLocal(msgVehiculoInactivo);
    }
    if (vehiculo != null && pesoTotal > vehiculo.capacity) {
      throw RechazoLocal(
        'Peso total (${pesoTotal.toStringAsFixed(1)} kg) supera la capacidad '
        'del vehículo (${_sinDecimalesSobrantes(vehiculo.capacity)} kg)',
      );
    }

    final origen = Punto(origenLat, origenLng);
    final paradas = [
      for (final p in pedidos)
        if (p.endLat != null && p.endLng != null)
          Parada(p.id, p.endLat!, p.endLng!),
    ];
    // EL ORDEN BUENO, NO EL DEL GREEDY A SECAS — 21/09/2026.
    //
    // Aqui se llamaba a `vecinoMasCercano`, y eso es lo que Jose estaba viendo:
    // «esa planificada esta mal, no hace ruta logica ni nada». El vecino mas
    // proximo deja cruces y un ultimo tramo larguisimo de vuelta al almacen.
    // `ordenDeVisita` arranca de ese mismo greedy y le pasa 2-opt y Or-opt sobre
    // el circuito CERRADO —el de `kmDelCircuito`, con la vuelta dentro— hasta
    // que no mejora. El servidor hace exactamente lo mismo
    // (`api/internal/api/rutas.go`, `ordenDeVisita`) y las dos lo demuestran
    // contra `docs/orden-de-paradas.casos.json`.
    //
    // Y QUIEN ORDENA SE APUNTA. Con `optimizar: false` no se toca el orden en
    // que vienen los pedidos: lo puso una persona. Aqui se guardaba
    // `optimized: true` SIEMPRE, tambien en ese caso, y eso es una firma falsa
    // —quien lo lea despues da por calculado lo que no calculo nadie, y no
    // vuelve a optimizar una ruta que «ya lo esta»—.
    final orden = optimizar
        ? ordenDeVisita(origen, paradas)
        : _ordenDelLogistico(pedidoIds, paradas);
    final porId = {for (final p in pedidos) p.id: p};
    final ordenadas = [
      for (final id in orden)
        Parada(id, porId[id]!.endLat!, porId[id]!.endLng!),
    ];

    final ahora = _reloj();
    final sucursalDeLaRuta = sucursalId ?? pedidos.first.branchId;

    // EL CUERPO ES UNO SOLO PARA LOS DOS CAMINOS.
    //
    // Se armaba dentro del `encolar`, o sea que el dia que la web escribiera en
    // directo habria dos copias del mismo cuerpo y una se quedaria atras. Es
    // exactamente lo que le paso al mensaje de `_porQueNoSePuedenArmar`: el
    // servidor lo cambio el 21/09 y el aparato se quedo con el literal viejo.
    final cuerpo = <String, Object?>{
      'name': ?nombre,
      'branchId': sucursalDeLaRuta,
      'vehicleId': vehiculoId,
      if (fechaDeEntrega != null)
        'deliveryDate': fechaDeEntrega.toIso8601String(),
      'originAddress': origenDireccion,
      'originLat': origenLat,
      'originLng': origenLng,
      // `orderIds` en el ORDEN CALCULADO aqui. Con `optimizar: true` el servidor
      // recalcula el suyo —hacen la misma cuenta y lo demuestran contra
      // `docs/orden-de-paradas.casos.json`—; con `false` este orden ES el dato,
      // porque lo puso una persona que conoce las calles.
      'orderIds': orden,
      // Se manda SIEMPRE, tambien cuando vale `true`. El servidor da por `true`
      // el cuerpo que no lo trae —las APK viejas no lo mandan y su orden SI lo
      // calculo el aparato—, asi que callarlo cuando es `false` devolveria la
      // ruta a estar firmada como calculada.
      'optimizar': optimizar,
    };

    // --- LA WEB: al servidor, y sin pintar nada hasta que conteste ---------
    final enVivo = _enVivo;
    if (enVivo != null) {
      final respuesta = await _mandar(
        enVivo,
        metodo: 'POST',
        ruta: '/routes',
        cuerpo: cuerpo,
      );
      return _guardarLaRutaQueVolvio(respuesta);
    }

    final rutaId = Provisionales.nuevoId();
    final codigo = await _codigoDeRuta();

    await _base.transaction(() async {
      await _base
          .into(_base.routes)
          .insert(
            RoutesCompanion.insert(
              id: rutaId,
              name: Value(nombre),
              routeCode: Value(codigo),
              status: const Value(EstadoRuta.planificada),
              originAddress: Value(origenDireccion),
              originLat: Value(origenLat),
              originLng: Value(origenLng),
              totalDistance: Value(kmDelCircuito(origen, ordenadas)),
              totalWeight: Value(pesoTotal),
              // ESTO NO ES EL IMPORTE DE LA RUTA, y por eso ya no se escribe a
              // pelo: es el ESPEJO de lo que el servidor va a calcular cuando
              // esto suba (`api/internal/api/rutas.go:810-814` suma igual, sólo
              // los `pedidoCosto` no nulos). La columna es `NOT NULL DEFAULT 0`
              // aquí y allí, así que no sabe decir «no se sabe»: el importe de
              // verdad sale de las paradas, con `ImporteDeRuta`, que sí sabe.
              // El porqué entero está en `espejoDelTotalDelServidor`.
              totalPrice: Value(
                ImporteDeRuta.espejoDelTotalDelServidor(
                  pedidos.map((p) => p.pedidoCosto),
                ),
              ),
              deliveryDate: Value(fechaDeEntrega),
              vehicleId: Value(vehiculoId),
              branchId: Value(sucursalDeLaRuta),
              optimized: Value(optimizar),
              createdAt: Value(ahora),
              updatedAt: Value(ahora),
            ),
          );

      for (var i = 0; i < orden.length; i++) {
        final pedido = porId[orden[i]]!;
        await (_base.update(
          _base.orders,
        )..where((o) => o.id.equals(pedido.id))).write(
          OrdersCompanion(
            routeId: Value(rutaId),
            ultimaRutaId: Value(rutaId),
            stopOrder: Value(i + 1),
            tripLeg: const Value(Tramo.ida),
            // `segmentKm` es la distancia RADIAL desde el origen, no la del
            // tramo del recorrido. Es raro y es a proposito: es lo que guarda el
            // servidor y con lo que se compara la paridad.
            segmentKm: Value(
              haversineKm(origen, Punto(pedido.endLat!, pedido.endLng!)),
            ),
            // EL NULO SE ESCRIBE. `orders.price` es `real().nullable()` aquí,
            // así que sí puede decir «sin cotizar», y este `?? 0` era quien se
            // lo quitaba: una parada sin cotizar quedaba GRABADA a cero y el
            // globo del croquis decía `$0.00` sobre un domicilio que nadie ha
            // cotizado todavía (`CLAUDE.md` §2).
            //
            // El servidor NO puede hacer lo mismo: `EngancharPedidoARuta` hace
            // `price = coalesce(sqlc.narg('price'), 0)`
            // (`api/db/queries/routes.sql:283`), así que en cuanto esta ruta
            // suba y vuelva a bajar, el nulo se convierte otra vez en cero. Por
            // eso quien LEE `price` tiene que aplicar además la regla de
            // `ConsultasInformes.ingresoDe` —un `price` de cero sin
            // `pedidoCosto` no es un precio, es ese `coalesce`—, y es lo que
            // hace `recorrido.dart`.
            price: Value(pedido.pedidoCosto),
            // REASIGNAR UN DEVUELTO ES UN INTENTO NUEVO — 1.0.29. El pedido que
            // vuelve a una ruta no arrastra el resultado del intento anterior:
            // un «devuelto» con su nota colgando de la ruta nueva se leería como
            // la hoja ya cerrada. El servidor hace lo mismo al engancharlo
            // (`EngancharPedidoARuta`), y esto es lo que se ve hasta que sube.
            resultado: const Value(null),
            resultadoAt: const Value(null),
            resultadoNota: const Value(null),
            deliveredAt: const Value(null),
            updatedAt: Value(ahora),
          ),
        );
      }
    });

    await _cola.encolar(
      metodo: 'POST',
      ruta: '/routes',
      cuerpo: cuerpo,
      // La bisagra: cuando esto suba, el id de verdad sustituye a `local-…` en
      // la cola y en las filas locales. Sin esto, el cierre de la tarde se iria
      // a `/routes/local-9f3a/results` y se perderia justo despues de subir.
      provisional: rutaId,
    );

    return rutaId;
  }

  /// LO QUE EL SERVIDOR GUARDO, reflejado tal cual en la base de la pestana.
  ///
  /// La base de la web es en memoria y de ella leen las siete pantallas. Esto NO
  /// la convierte en una copia que pueda mentir: aqui solo entra lo que el
  /// servidor **ya escribio** y acaba de devolver, con SU id, SU codigo de ruta
  /// y SU orden de paradas. Lo que se pinta es lo que hay arriba.
  ///
  /// Y el id es el de verdad desde el primer instante: nada de `local-…`, nada
  /// de `Provisionales`. La pantalla selecciona la ruta recien armada con ese
  /// id, y el cierre de la tarde se va a `/routes/<id>/results` sin depender de
  /// que una sustitucion llegue a tiempo.
  Future<String> _guardarLaRutaQueVolvio(Object? respuesta) async {
    final ruta = _laRutaDe(respuesta);
    final id = ruta?['id'];
    if (ruta == null || id is! String || id.isEmpty) {
      // EL SERVIDOR DIJO QUE SI Y NO DIJO CUAL. No se inventa un id ni se da la
      // ruta por armada en silencio: eso es exactamente el fallo de hoy, con la
      // pantalla pintando como hecho algo que no puede volver a encontrar.
      Registro.fallo('la ruta se creo y la respuesta llego sin id: $respuesta');
      throw const RechazoLocal(
        'La ruta se creó en el servidor, pero la respuesta llegó sin su '
        'identificador. Recarga la pantalla para verla.',
      );
    }
    await _espejarLaRuta(id, ruta);
    return id;
  }

  /// La ruta dentro de la respuesta.
  ///
  /// Hoy el servidor manda el objeto de la ruta a secas, con el `id` en la
  /// raiz. Se sigue leyendo tambien `{"ruta": …, "avisos": …}`, que era la otra
  /// forma mientras se dejaban armar rutas con domicilios sin costear: desde el
  /// 07/10/2026 (Amado) eso ya no se arma —el armador exige domicilio cobrado y
  /// cotizado— y el servidor no lo manda, pero un servidor que aun no se haya
  /// actualizado si, y dejarlo sin leer dejaria la ruta sin id.
  static Map<Object?, Object?>? _laRutaDe(Object? respuesta) {
    if (respuesta is! Map<Object?, Object?>) return null;
    final dentro = respuesta['ruta'];
    if (dentro is Map<Object?, Object?>) return dentro;
    return respuesta.containsKey('id') ? respuesta : null;
  }

  Future<void> _espejarLaRuta(String id, Map<Object?, Object?> ruta) async {
    final paradas = ruta['orders'];
    final ahora = _reloj();
    await _base.transaction(() async {
      await _base
          .into(_base.routes)
          .insertOnConflictUpdate(
            RoutesCompanion.insert(
              id: id,
              name: Value(_texto(ruta['name'])),
              routeCode: Value(_texto(ruta['routeCode'])),
              status: Value(_texto(ruta['status']) ?? EstadoRuta.planificada),
              originAddress: Value(_texto(ruta['originAddress'])),
              originLat: Value(_numero(ruta['originLat'])),
              originLng: Value(_numero(ruta['originLng'])),
              totalDistance: Value(_numero(ruta['totalDistance']) ?? 0),
              totalWeight: Value(_numero(ruta['totalWeight']) ?? 0),
              // El `?? 0` de aquí NO inventa nada: es el valor por defecto de
              // una columna que el servidor tiene como `NOT NULL DEFAULT 0`, y
              // sólo salta si la respuesta viniera sin el campo. Lo que no se
              // puede hacer es LEER esta columna como el importe de la ruta:
              // ver `ImporteDeRuta.espejoDelTotalDelServidor`.
              totalPrice: Value(_numero(ruta['totalPrice']) ?? 0),
              deliveryDate: Value(_fecha(ruta['deliveryDate'])),
              vehicleId: Value(_texto(ruta['vehicleId'])),
              creadoPor: Value(_texto(ruta['creadoPor'])),
              branchId: Value(_texto(ruta['branchId'])),
              // LA FIRMA DE QUIEN ORDENO, que es un dato y no un adorno: quien
              // lea `optimized: true` no vuelve a optimizar una ruta que «ya lo
              // esta». Se lee del servidor y no se supone.
              optimized: Value(ruta['optimized'] == true),
              startedAt: Value(_fecha(ruta['startedAt'])),
              finishedAt: Value(_fecha(ruta['finishedAt'])),
              createdAt: Value(_fecha(ruta['createdAt']) ?? ahora),
              updatedAt: Value(_fecha(ruta['updatedAt']) ?? ahora),
            ),
          );

      if (paradas is! List) return;
      for (final cruda in paradas) {
        if (cruda is! Map<Object?, Object?>) continue;
        final pedidoId = _texto(cruda['id']);
        if (pedidoId == null || pedidoId.isEmpty) continue;
        await (_base.update(
          _base.orders,
        )..where((o) => o.id.equals(pedidoId))).write(
          OrdersCompanion(
            routeId: Value(id),
            ultimaRutaId: Value(id),
            stopOrder: Value(_entero(cruda['stopOrder'])),
            tripLeg: Value(_texto(cruda['tripLeg']) ?? Tramo.ida),
            segmentKm: Value(_numero(cruda['segmentKm'])),
            price: Value(_numero(cruda['price'])),
            // El servidor limpia el intento anterior al engancharlo (un
            // devuelto reasignado empieza de cero): se refleja aquí también, o la
            // ruta nueva enseñaría la marca de la vieja hasta la próxima bajada.
            resultado: const Value(null),
            resultadoAt: const Value(null),
            resultadoNota: const Value(null),
            deliveredAt: const Value(null),
            updatedAt: Value(ahora),
          ),
        );
      }
    });
  }

  // Lectores del JSON del servidor. Los mismos tres de `nucleo/sincro/bajada.dart`
  // y por el mismo motivo: un numero puede llegar como `int` o como `double`
  // segun lo redondo que sea, y leerlo con un `as double` revienta con `1` donde
  // no revienta con `1.5`.
  static String? _texto(Object? v) => v is String && v.isNotEmpty ? v : null;

  static double? _numero(Object? v) => v is num ? v.toDouble() : null;

  static int? _entero(Object? v) => v is num ? v.toInt() : null;

  static DateTime? _fecha(Object? v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toUtc() : null;

  /// El orden que trae [pedidoIds], tal cual, sin tocar una coma.
  ///
  /// No es «el algoritmo apagado»: es el otro orden posible, y el bueno cuando
  /// quien arma la ruta conoce las calles. Lo unico que hace es quedarse con los
  /// que de verdad van en la ruta —los que tienen punto de entrega, que son los
  /// de [paradas]— y CONSERVAR la posicion en que llegaron. Un id repetido no se
  /// visita dos veces. Es la gemela de `ordenDelLogistico` en `rutas.go`.
  static List<String> _ordenDelLogistico(
    List<String> pedidoIds,
    List<Parada> paradas,
  ) {
    final tienePunto = {for (final p in paradas) p.id};
    final puesto = <String>{};
    final orden = <String>[];
    for (final id in pedidoIds) {
      if (tienePunto.contains(id) && puesto.add(id)) orden.add(id);
    }
    // Lo que estaba en `paradas` y no en la lista se va al final, no se cae. No
    // puede pasar hoy —las dos salen de los mismos ids— pero descartar una
    // parada en silencio es un bulto en el camion que no sale en la hoja.
    for (final p in paradas) {
      if (puesto.add(p.id)) orden.add(p.id);
    }
    return orden;
  }

  /// Los pedidos que de verdad se pueden meter, con las mismas condiciones que
  /// la consulta del servidor.
  Future<List<Pedido>> _pedidosArmables(
    List<String> ids,
    String? sucursalId,
  ) async {
    final consulta = _base.select(_base.orders)
      ..where(
        (o) =>
            o.id.isIn(ids) &
            o.source.equals(Procedencia.pedido) &
            o.routeId.isNull() &
            // ARCHIVADO Y ENTREGADO, que faltaban — 22/09/2026.
            //
            // El servidor los descarta (`PedidosParaArmarRuta`) y aquí no se
            // miraban, así que el aparato dejaba armar la ruta, la encolaba, y
            // el «no» llegaba horas después a la bandeja de rechazados. Peor
            // todavía con un entregado: conserva su `routeId`, así que se
            // colaba sólo si la ruta que lo llevó se borró — y volver a
            // subirlo a un camión es ir a casa de alguien que ya recibió.
            o.archivado.equals(false) &
            o.deliveredAt.isNull() &
            o.endLat.isNotNull() &
            o.endLng.isNotNull() &
            (sucursalId == null || sucursalId.isEmpty
                ? const Constant(true)
                : o.branchId.equals(sucursalId)),
      );
    return consulta.get();
  }

  /// POR QUÉ NO SE PUEDEN ARMAR, pedido a pedido y con el motivo de VERDAD.
  ///
  /// ## El aparato se había quedado atrás — 22/09/2026
  ///
  /// Aquí se decía siempre lo mismo: «N de los M pedidos ya están en otra ruta.
  /// Vuelve a elegirlos.» El servidor **ya no dice eso** —lo cambió el 21/09 por
  /// esto mismo, motivo a motivo (`api/internal/api/rutas.go`,
  /// `porQueNoSeArma`)— y el aparato se quedó con el literal viejo. Que es peor
  /// que no tener mensaje: la criba descarta por seis motivos distintos y cinco
  /// de cada seis veces el aviso señalaba el sitio equivocado. Alguien vuelve a
  /// la lista, elige otros pedidos, y le pasa otra vez lo mismo.
  ///
  /// «Vuelve a elegirlos» sólo vale para uno de los seis. Para un pedido sin
  /// coordenadas o archivado en PEDIDO, volver a elegirlo es justo lo que no
  /// arregla nada.
  ///
  /// **Palabra por palabra igual que el servidor**, porque el mismo «no» puede
  /// llegar por los dos caminos —aquí al armar, o horas después en la bandeja de
  /// rechazados— y leerlo distinto enseña que la aplicación miente a veces.
  /// `armado_test.dart` los compara carácter a carácter.
  Future<String> _porQueNoSePuedenArmar(
    List<String> pedidos,
    List<Pedido> armables,
    String? sucursalId,
  ) async {
    final buenos = {for (final p in armables) p.id};
    // Los repetidos NO cuentan: mandar dos veces el mismo id es una lista mal
    // hecha, no un conflicto. Es lo que hace `faltanDelArmado` en el servidor.
    final fuera = <String>[];
    final visto = <String>{};
    for (final id in pedidos) {
      if (!visto.add(id)) continue;
      if (!buenos.contains(id)) fuera.add(id);
    }

    // Se leen SIN ningún filtro: hace falta saber qué tiene cada fila, no si
    // pasa la criba. Que un pedido ni siquiera esté aquí también es respuesta.
    final filas = await (_base.select(
      _base.orders,
    )..where((o) => o.id.isIn(fuera))).get();
    final porId = {for (final f in filas) f.id: f};

    // El CÓDIGO de la ruta, para poder decir en cuál va. «Ya va en la ruta
    // RT-20260922-003» dice dónde mirar; «ya va en otra ruta» deja quince rutas
    // que abrir.
    final rutas = <String, String?>{};
    final idsDeRuta = <String>{
      for (final f in filas)
        if (f.routeId != null) f.routeId!,
    };
    if (idsDeRuta.isNotEmpty) {
      final encontradas = await (_base.select(
        _base.routes,
      )..where((r) => r.id.isIn(idsDeRuta.toList()))).get();
      for (final r in encontradas) {
        rutas[r.id] = r.routeCode;
      }
    }

    // EL ORDEN ES EL DEL SERVIDOR y no es casual: el entregado va PRIMERO
    // porque conserva su `routeId`, y mirando la ruta antes se le contaría al
    // logístico que «otro lo subió a un camión» cuando ese pedido ya está en
    // casa del cliente. Lo que hay que hacer es distinto.
    String motivo(Pedido p) {
      if (p.deliveredAt != null || p.resultado == ResultadoParada.entregado) {
        return 'ya se entregó y no puede volver a un camión';
      }
      if (p.routeId != null) {
        final codigo = rutas[p.routeId];
        if (codigo != null && codigo.isNotEmpty) {
          return 'ya va en la ruta $codigo';
        }
        return 'ya va en otra ruta';
      }
      if (p.archivado) return 'PEDIDO lo archivó';
      if (p.endLat == null || p.endLng == null) {
        return 'sin coordenadas de entrega';
      }
      if (p.source != Procedencia.pedido) return 'no vino de PEDIDO';
      // No debería llegar aquí. Si llega, es que la criba cambió y esto no:
      // decirlo es mejor que inventar un motivo, que es lo que se acaba de
      // quitar.
      return 'cambió mientras se armaba';
    }

    final detalle = <String>[];
    for (final id in fuera) {
      if (detalle.length >= 5) break;
      final p = porId[id];
      if (p == null) {
        // NO EXISTE Y NO ES TUYO SON LO MISMO desde fuera: decir «existe pero es
        // de Holguín» ya es contar algo de Holguín.
        detalle.add('$id (no existe o no es de tu sucursal)');
        continue;
      }
      detalle.add('${p.operationNumber ?? p.customerName} (${motivo(p)})');
    }

    final cola = fuera.length > detalle.length
        ? ' y ${fuera.length - detalle.length} más.'
        : '.';
    // La M es `pedidos.length`, lo que la persona marcó en la pantalla y tiene
    // delante mientras lee el aviso, no el número de ids distintos.
    //
    // ESTE MENSAJE ES EL DEL SERVIDOR, LETRA POR LETRA. Lo copia de
    // `api/internal/api/rutas.go` (`encabezadoDelArmado`) para que sin señal se
    // lea exactamente lo mismo que con ella: es la regla del §3-quinquies —«lo
    // que el servidor rechaza se dice, y con su motivo literal»—. Tocar el
    // plural SÓLO aquí rompe esa paridad y deja dos frases distintas para el
    // mismo rechazo, que es peor que un «1 pedidos».
    //
    // EL SINGULAR, ARREGLADO EN LOS DOS LADOS A LA VEZ — 29/09/2026. Decía «1 de
    // los 1 pedidos elegidos no pueden ir en esta ruta», tres faltas en siete
    // palabras y en el caso más común: elegir un pedido y que no entre. Son dos
    // concordancias distintas porque los dos números cuentan cosas distintas:
    // el VERBO va con los que se caen y el SUSTANTIVO con los que se eligieron.
    // Y con un solo pedido elegido los dos números son el mismo, así que decir
    // «1 de 1» no informa de nada y la frase va sin ellos.
    //
    // Lo que ata esta redacción con la del servidor es
    // `docs/armado-rechazado.casos.json`, que leen las dos pruebas —la de aquí y
    // la de Go—, no este comentario (`CLAUDE.md` §3-bis).
    return '${encabezadoDelArmado(fuera.length, pedidos.length)}'
        '${detalle.join(", ")}$cola';
  }

  /// El mensaje compuesto de los no facturados, letra a letra como el servidor:
  /// los 5 primeros con su motivo y, si hay mas, ` y <n> más.`
  String _mensajeDeFactura(List<Pedido> noFacturados) {
    String motivo(Pedido p) => switch (p.facturaEstado) {
      EstadoFactura.cambiado => 'cambió en la factura',
      EstadoFactura.sinFactura => 'sin facturar',
      // NULL y cualquier otro valor: sin cotejar.
      _ => 'sin cotejar',
    };

    final n = noFacturados.length;
    final detalle = noFacturados
        .take(5)
        .map((p) => '${p.operationNumber ?? p.customerName} (${motivo(p)})')
        .join(', ');
    final cola = n > 5 ? ' y ${n - 5} más.' : '.';
    return 'En una ruta sólo entra lo facturado y que cuadre. '
        '$n no cumplen: $detalle$cola';
  }

  String _mensajeDeDomicilioSinCobrar(List<Pedido> pedidos) {
    final detalle = pedidos
        .take(5)
        .map((p) => p.operationNumber ?? p.customerName)
        .join(', ');
    final cola = pedidos.length > 5 ? ' y ${pedidos.length - 5} más.' : '.';
    return 'En una ruta sólo entra lo facturado con domicilio cobrado. '
        '${pedidos.length} no cumplen: $detalle$cola';
  }

  String _mensajeSinCotizacion(List<Pedido> pedidos) {
    final detalle = pedidos
        .take(5)
        .map((p) => p.operationNumber ?? p.customerName)
        .join(', ');
    final cola = pedidos.length > 5 ? ' y ${pedidos.length - 5} más.' : '.';
    return 'No se puede crear la ruta: ${pedidos.length} pedidos no tienen '
        'cotizado el domicilio en Entrega: $detalle$cola';
  }

  /// `RT-YYYYMMDD-NNN-<aparato>`.
  ///
  /// El formato es el de `generateRouteCode()` mas el sufijo del aparato
  /// (PLAN.md §3.2): el `NNN` sale de contar lo que hay **en este aparato**, asi
  /// que sin el sufijo dos sucursales sin red generarian el mismo codigo el mismo
  /// dia. **Al aplicarse en el servidor manda el del servidor** y la fila local se
  /// reescribe con la respuesta.
  Future<String> _codigoDeRuta() async {
    final hoy = _reloj().toUtc();
    final fecha =
        '${hoy.year.toString().padLeft(4, '0')}'
        '${hoy.month.toString().padLeft(2, '0')}'
        '${hoy.day.toString().padLeft(2, '0')}';
    final prefijo = 'RT-$fecha-';

    final cuenta = _base.routes.id.count();
    final fila =
        await (_base.selectOnly(_base.routes)
              ..addColumns([cuenta])
              ..where(_base.routes.routeCode.like('$prefijo%')))
            .getSingle();
    final siguiente = (fila.read(cuenta) ?? 0) + 1;
    return '$prefijo${siguiente.toString().padLeft(3, '0')}-$_sufijo';
  }

  // ---------------------------------------------------------------------------
  // Estado de la ruta
  // ---------------------------------------------------------------------------

  /// `Iniciar ruta`. Marca el vehiculo como ocupado, igual que el servidor.
  Future<void> iniciar(String rutaId) async {
    final ahora = _reloj();
    final ruta = await _ruta(rutaId);
    if (ruta == null) throw const RechazoLocal('No encontrada');
    _exigirRutaEditable(ruta);

    // LA WEB PRIMERO AL SERVIDOR. Si dice que no, no se toca una fila y sale su
    // motivo: el camion no sale porque un boton se ponga gris.
    final enVivo = _enVivo;
    if (enVivo != null) {
      await _mandar(
        enVivo,
        metodo: 'PATCH',
        ruta: '/routes/$rutaId',
        cuerpo: const <String, Object?>{'status': EstadoRuta.enCurso},
      );
    }

    await _base.transaction(() async {
      await (_base.update(
        _base.routes,
      )..where((r) => r.id.equals(rutaId))).write(
        OrdersDeRuta.enCurso(ahora: ahora, yaEmpezada: ruta.startedAt != null),
      );
      await _ocuparVehiculo(ruta.vehicleId, EstadoVehiculo.enUso);
    });

    if (enVivo != null) return; // ya esta arriba: no hay nada que subir
    await _cola.encolar(
      metodo: 'PATCH',
      ruta: '/routes/$rutaId',
      cuerpo: <String, Object?>{'status': EstadoRuta.enCurso},
    );
  }

  /// `Marcar como completada`. Libera el vehiculo.
  ///
  /// **El estado de cada parada se pregunta AL COMPLETAR, no despues.** Si
  /// quedan paradas sin marcar, `detalle_ruta.dart` abre el cierre en modo
  /// `alCompletar` y esto se llama al guardar, en el mismo gesto. Una ruta ya
  /// `completed` ensena su cierre en solo lectura.
  ///
  /// Aqui nos separamos del patron de Next a proposito (`CLAUDE.md` §2): el
  /// Next deja el boton `Cierre` vivo sobre una ruta completada, y Jose lo vio
  /// el 17/09/2026 — «ese estado se pone cuando estan en ruta, no completados».
  /// Lo que baja del camion se cuadra antes de dar la ruta por cerrada, que es
  /// justo lo que significa cerrarla.
  Future<void> completar(String rutaId) async {
    final ahora = _reloj();
    final ruta = await _ruta(rutaId);
    if (ruta == null) throw const RechazoLocal('No encontrada');
    _exigirRutaEditable(ruta);

    final enVivo = _enVivo;
    if (enVivo != null) {
      await _mandar(
        enVivo,
        metodo: 'PATCH',
        ruta: '/routes/$rutaId',
        cuerpo: const <String, Object?>{'status': EstadoRuta.completada},
      );
    }

    await _base.transaction(() async {
      await (_base.update(
        _base.routes,
      )..where((r) => r.id.equals(rutaId))).write(
        RoutesCompanion(
          status: const Value(EstadoRuta.completada),
          finishedAt: Value(ahora),
          updatedAt: Value(ahora),
        ),
      );
      await _ocuparVehiculo(ruta.vehicleId, EstadoVehiculo.disponible);
    });

    if (enVivo != null) return;
    await _cola.encolar(
      metodo: 'PATCH',
      ruta: '/routes/$rutaId',
      cuerpo: <String, Object?>{'status': EstadoRuta.completada},
    );
  }

  /// `Eliminar`, sólo rutas no completadas.
  ///
  /// **No borra pedidos**: les suelta la ruta y los devuelve a la lista de
  /// disponibles. `ultimaRutaId` se conserva, o el pedido desapareceria de la
  /// hoja de lo que bajo del camion.
  ///
  /// Y PASA POR [_unaSola]: el gesto duplicado del navegador mandaba dos
  /// borrados, y el segundo pintaba un «No encontrada» en rojo encima de un
  /// borrado que si funciono.
  Future<void> eliminar(String rutaId) =>
      _unaSola('eliminar:$rutaId', () => _eliminar(rutaId));

  /// Quita una parada de una ruta planificada y devuelve el pedido a disponibles.
  ///
  /// # LA PARADA FANTASMA — 07/10/2026
  ///
  /// Aqui se soltaba `routeId` y se dejaba `ultimaRutaId`, que es lo que hace
  /// bien el devuelto (la hoja de lo que bajo del camion tiene que seguir
  /// teniendolo). Pero un pedido que se QUITA no bajo de ningun camion: con la
  /// ruta todavia a medias, `ultimaRutaId` lo seguia atando a ella y la parada
  /// quitada seguia saliendo en su hoja y sumando en su peso y su importe —que
  /// agrupan por esa columna— mientras ya estaba en disponibles: en dos sitios a
  /// la vez. Por eso se suelta TAMBIEN `ultimaRutaId`.
  ///
  /// Es reflejo exacto de lo que hace el servidor (`SoltarParadaPlanificada`), y
  /// de ahi las dos condiciones de las lecturas de paradas: un pedido sin
  /// `routeId` es parada de una ruta solo si lo solto con un resultado puesto
  /// (devuelto o cancelado).
  ///
  /// Los dos «no» son los LITERALES del servidor, en su orden.
  Future<void> quitarParada(String rutaId, String pedidoId) =>
      _unaSola('quitar-parada:$rutaId:$pedidoId', () async {
        final ruta = await _ruta(rutaId);
        if (ruta == null) throw const RechazoLocal('No encontrada');
        if (ruta.status != EstadoRuta.planificada) {
          throw const RechazoLocal(msgSoloSeRetiranDeRutaPlanificada);
        }
        // La parada tiene que estar en ESTA ruta y sin resultado ni entrega: lo
        // que el servidor exige en el `WHERE` de `SoltarParadaPlanificada`. Sin
        // esta guarda la APK soltaria algo que luego el servidor rechaza con un
        // 409 que llega horas despues a la bandeja.
        final parada = await (_base.select(
          _base.orders,
        )..where((o) => o.id.equals(pedidoId))).getSingleOrNull();
        if (parada == null ||
            parada.routeId != rutaId ||
            parada.resultado != null ||
            parada.deliveredAt != null) {
          throw const RechazoLocal(msgParadaNoPerteneceAPlanificada);
        }
        final enVivo = _enVivo;
        if (enVivo != null) {
          await _mandar(
            enVivo,
            metodo: 'DELETE',
            ruta: '/routes/$rutaId/stops/$pedidoId',
          );
        }
        await (_base.update(
          _base.orders,
        )..where((o) => o.id.equals(pedidoId))).write(
          const OrdersCompanion(
            routeId: Value(null),
            ultimaRutaId: Value(null),
            stopOrder: Value(null),
            segmentKm: Value(null),
            tripLeg: Value(Tramo.ida),
          ),
        );
        if (enVivo == null) {
          await _cola.encolar(
            metodo: 'DELETE',
            ruta: '/routes/$rutaId/stops/$pedidoId',
            cuerpo: const <String, Object?>{},
          );
        }
      });

  Future<void> _eliminar(String rutaId) async {
    final ruta = await _ruta(rutaId);
    if (ruta == null) throw const RechazoLocal('No encontrada');
    _exigirRutaEditable(ruta);

    // La web espera el borrado aceptado antes de tocar su vista.
    final enVivo = _enVivo;
    if (enVivo != null) {
      await _mandar(enVivo, metodo: 'DELETE', ruta: '/routes/$rutaId');
    }

    await _base.transaction(() async {
      await (_base.update(
        _base.orders,
      )..where((o) => o.routeId.equals(rutaId))).write(
        const OrdersCompanion(
          routeId: Value(null),
          stopOrder: Value(null),
          segmentKm: Value(null),
          tripLeg: Value(Tramo.ida),
        ),
      );
      await _ocuparVehiculo(ruta.vehicleId, EstadoVehiculo.disponible);
      await (_base.delete(
        _base.routes,
      )..where((r) => r.id.equals(rutaId))).go();
    });

    if (enVivo != null) return;
    await _cola.encolar(
      metodo: 'DELETE',
      ruta: '/routes/$rutaId',
      cuerpo: const <String, Object?>{},
    );
  }

  void _exigirRutaEditable(Ruta ruta) {
    if (ruta.status == EstadoRuta.completada) {
      throw const RechazoLocal(msgRutaCompletada);
    }
  }

  Future<Ruta?> _ruta(String rutaId) => (_base.select(
    _base.routes,
  )..where((r) => r.id.equals(rutaId))).getSingleOrNull();

  Future<void> _ocuparVehiculo(String? vehiculoId, String estado) async {
    if (vehiculoId == null) return;
    await (_base.update(_base.vehicles)..where((v) => v.id.equals(vehiculoId)))
        .write(VehiclesCompanion(status: Value(estado)));
  }

  // ---------------------------------------------------------------------------
  // El cierre parada por parada — el caso de uso principal
  // ---------------------------------------------------------------------------

  /// Guarda el cierre: se escribe en la base local **con la hora del aparato** y
  /// se encola un solo apunte hacia `POST /api/routes/<id>/results`.
  ///
  /// Se pinta como hecho sin esperar al servidor. Esto pasa en el patio del
  /// almacen, donde no hay senal: esperar una respuesta seria no poder cerrar
  /// ninguna ruta.
  ///
  /// Devuelve qué paradas quedaron guardadas y la `clave` del apunte, que es con
  /// lo que se le sigue la pista (`ResultadoCierreDeRuta`).
  Future<ResultadoCierreDeRuta> cerrar(
    String rutaId,
    List<MarcaDeParada> marcas,
  ) async {
    final ruta = await _ruta(rutaId);
    if (ruta == null) throw const RechazoLocal('No encontrada');
    _exigirRutaEditable(ruta);
    if (marcas.isEmpty) throw const RechazoLocal('No vino ningún resultado');

    // Una parada actual se reconoce por `routeId`; si ya se devolvió o canceló,
    // usa `ultimaRutaId` para permitir corregir su cierre histórico. Y SOLO si
    // trae resultado: sin `routeId` y sin resultado es un pedido que se QUITÓ de
    // la ruta, no una parada suya (`paradasDe` lleva la misma condición).
    final paradas =
        await (_base.select(_base.orders)..where(
              (o) =>
                  o.routeId.equals(rutaId) |
                  (o.routeId.isNull() &
                      o.ultimaRutaId.equals(rutaId) &
                      o.resultado.isNotNull()),
            ))
            .get();
    final deLaRuta = {for (final p in paradas) p.id};

    final validas = <MarcaDeParada>[];
    for (final marca in marcas) {
      if (!deLaRuta.contains(marca.pedidoId)) {
        // El mismo motivo literal del servidor. No aborta el resto: lo que se
        // puede guardar se guarda.
        Registro.aviso(
          'cierre de $rutaId: ${marca.pedidoId} — ese pedido no va en esta ruta',
        );
        continue;
      }
      // `null` es «quitar la marca» y es válido: NO es un resultado desconocido.
      // Confundir los dos es lo que dejaba el desmarcado sin salir de la
      // pantalla.
      if (!marca.quitaLaMarca &&
          !const [
            ResultadoParada.entregado,
            ResultadoParada.devuelto,
            ResultadoParada.cancelado,
          ].contains(marca.resultado)) {
        Registro.aviso(
          "cierre de $rutaId: resultado '${marca.resultado}' desconocido",
        );
        continue;
      }
      validas.add(marca);
    }
    if (validas.isEmpty) throw const RechazoLocal('No vino ningún resultado');

    // LA HORA DEL APARATO. Lo que se marca a las cuatro en el patio queda como
    // las cuatro aunque suba a las siete (regla 7).
    final ahora = _reloj();

    final limpias = <MarcaDeParada>[
      for (final marca in validas)
        MarcaDeParada(
          pedidoId: marca.pedidoId,
          resultado: marca.resultado,
          // LA NOTA SE VA CON LA MARCA. Un motivo de devolución colgando de una
          // parada que ya no tiene resultado es la explicación de algo que no
          // consta, y el servidor hace lo mismo (`LimpiarResultadoDeParada`
          // pone `resultado_nota` a NULL).
          nota: marca.quitaLaMarca ? null : _notaLimpia(marca.nota),
        ),
    ];

    // EN LA WEB EL CIERRE VA AL SERVIDOR Y SE ESPERA.
    //
    // Es el caso de uso principal y el mas caro de equivocar: lo que baja del
    // camion es lo que se cuadra. Pintarlo como guardado sin que saliera del
    // navegador es el «dato que esta y no se escribe» en su peor version — un
    // cierre perdido no lo desmiente ninguna pantalla hasta que no cuadra el
    // inventario.
    final enVivo = _enVivo;
    var aplicadas = limpias;
    var rechazadas = const <ParadaRechazada>[];
    if (enVivo != null) {
      try {
        await enVivo.mandar(
          metodo: 'POST',
          ruta: '/routes/$rutaId/results',
          cuerpo: <String, Object?>{
            'resultados': [for (final m in limpias) m.aJson()],
          },
        );
      } on RechazoDelServidor catch (rechazo) {
        final parcial = _cierreParcialDe(rechazo);
        // Un rechazo TOTAL sale como `RechazoLocal` con el motivo literal del
        // servidor, igual que en las otras acciones (`_mandar`): es el tipo que
        // las pantallas saben enseñar. Dejar pasar el `RechazoDelServidor` tal
        // cual lo convertía en un error genérico sin motivo.
        if (rechazo.codigo != 409 || parcial == null) {
          throw RechazoLocal(rechazo.motivo);
        }
        aplicadas = limpias
            .where((marca) => parcial.aplicados.contains(marca.pedidoId))
            .toList();
        rechazadas = parcial.rechazadas;
      }
    }

    await _base.transaction(() async {
      for (final marca in aplicadas) {
        final nota = marca.nota;
        // QUITAR LA MARCA DESHACE LO DE ABAJO, COLUMNA POR COLUMNA. Media vuelta
        // atras es peor que ninguna, y hay dos que no son obvias:
        //
        //  · `deliveredAt` a null y `status` a pendiente. Si no, la parada se
        //    queda sin resultado pero con hora de entrega, y la lista la pinta
        //    «entregada»: la contradiccion del 2 de septiembre, al reves.
        //  · **`routeId` VUELVE A SER EL DE LA RUTA**, que es la que importa.
        //    Un devuelto SOLTO su `routeId` al marcarse; desmarcarlo sin
        //    devolverselo lo deja fuera de su propia ruta con la ruta todavia
        //    abierta, y entonces sale en DOS camiones. Se recupera de `rutaId`,
        //    que es por donde se eligieron las paradas (`ultimaRutaId`).
        //
        // Es lo mismo que hace el servidor en `LimpiarResultadoDeParada`.
        await (_base.update(
          _base.orders,
        )..where((o) => o.id.equals(marca.pedidoId))).write(
          marca.quitaLaMarca
              ? OrdersCompanion(
                  resultado: const Value(null),
                  ultimaRutaId: Value(rutaId),
                  resultadoAt: const Value(null),
                  resultadoNota: const Value(null),
                  deliveredAt: const Value(null),
                  status: const Value(EstadoPedido.pendiente),
                  routeId: Value(rutaId),
                  updatedAt: Value(ahora),
                )
              : OrdersCompanion(
                  resultado: Value(marca.resultado),
                  ultimaRutaId: Value(rutaId),
                  resultadoAt: Value(ahora),
                  resultadoNota: Value(nota),
                  deliveredAt: Value(marca.seEntrego ? ahora : null),
                  status: Value(
                    marca.seEntrego
                        ? EstadoPedido.entregado
                        : EstadoPedido.pendiente,
                  ),
                  // Lo que NO se entrega suelta su `routeId` y vuelve a la lista
                  // de disponibles para la ruta de manana. `ultimaRutaId` y
                  // `stopOrder` no se tocan NUNCA: son lo que ata el pedido a la
                  // hoja de cierre.
                  routeId: Value(marca.seEntrego ? rutaId : null),
                  updatedAt: Value(ahora),
                ),
        );
      }
    });

    // En la web no hay apunte al que seguirle la pista porque no hay cola: el
    // cierre ya esta arriba. Quien llama no lo mira (`vista/cierre_de_ruta.dart`).
    if (enVivo != null) {
      return ResultadoCierreDeRuta(
        idsAplicados: {for (final marca in aplicadas) marca.pedidoId},
        rechazadas: rechazadas,
      );
    }

    final clave = await _cola.encolar(
      metodo: 'POST',
      ruta: '/routes/$rutaId/results',
      cuerpo: <String, Object?>{
        'resultados': [for (final m in limpias) m.aJson()],
      },
    );
    return ResultadoCierreDeRuta(
      idsAplicados: {for (final marca in limpias) marca.pedidoId},
      claveDelApunte: clave,
    );
  }

  /// El servidor puede guardar las paradas válidas y responder 409 con las
  /// rechazadas. En ese caso se actualizan localmente sólo las que aparecen
  /// en `aplicados`, se informa el rechazo (cada parada con su conduce y su
  /// motivo) y la pantalla aún puede completar la ruta. Un 409 sin ese contrato
  /// sigue siendo un rechazo total.
  ///
  /// `numeroOperacion` de cada rechazada lo añadió la 1.0.29; un servidor viejo
  /// no lo manda y la parada se nombra por su `orderId` (`ParadaRechazada`).
  ({Set<String> aplicados, List<ParadaRechazada> rechazadas})?
  _cierreParcialDe(RechazoDelServidor rechazo) {
    final cuerpo = rechazo.cuerpo;
    if (cuerpo is! Map ||
        cuerpo['aplicados'] is! List ||
        cuerpo['rechazados'] is! List) {
      return null;
    }
    final rechazados = cuerpo['rechazados'] as List;
    if (rechazados.isEmpty) return null;
    final aplicados = cuerpo['aplicados'] as List;
    // Si no se guardó ninguna marca, no es un cierre parcial: dejar completar aquí
    // ocultaría un rechazo total y perdería la oportunidad de corregir la ruta.
    if (aplicados.isEmpty) return null;
    final ids = <String>{};
    for (final elemento in aplicados) {
      if (elemento is! Map || elemento['orderId'] is! String) return null;
      ids.add(elemento['orderId'] as String);
    }
    return (
      aplicados: ids,
      rechazadas: [
        for (final elemento in rechazados)
          if (elemento is Map)
            ParadaRechazada(
              pedidoId: '${elemento['orderId'] ?? ''}',
              numeroOperacion: elemento['numeroOperacion'] == null
                  ? null
                  : '${elemento['numeroOperacion']}',
              motivo: '${elemento['motivo'] ?? rechazo.motivo}',
            ),
      ],
    );
  }

  /// La nota, recortada como la recorta el servidor: sin espacios sobrantes,
  /// maximo 500 caracteres, y vacia es `null` y no `''`.
  static String? _notaLimpia(String? cruda) {
    final texto = cruda?.trim() ?? '';
    if (texto.isEmpty) return null;
    return texto.length <= topeDeNota ? texto : texto.substring(0, topeDeNota);
  }

  /// La capacidad va en el mensaje **sin formatear**, igual que el servidor:
  /// `1000` y no `1000.0`.
  static String _sinDecimalesSobrantes(double valor) =>
      valor == valor.roundToDouble()
      ? valor.round().toString()
      : valor.toString();
}

/// Los dos companions del cambio de estado, juntos para que el «sólo si aun es
/// null» de `startedAt` no se pierda en medio de un metodo.
abstract final class OrdersDeRuta {
  static RoutesCompanion enCurso({
    required DateTime ahora,
    required bool yaEmpezada,
  }) => RoutesCompanion(
    status: const Value(EstadoRuta.enCurso),
    // `startedAt` sólo se pone la primera vez: volver a iniciar una ruta no
    // reescribe a que hora salio el camion, que es con lo que se mide la
    // duracion.
    startedAt: yaEmpezada ? const Value.absent() : Value(ahora),
    finishedAt: const Value(null),
    updatedAt: Value(ahora),
  );
}
