// «UBICAR LA ENTREGA»: el cajón donde el logístico le pone a mano el punto de
// entrega a un pedido (issue 19 de Amado, «Geolocalización», Reparto 1.0.39).
//
// El caso: el cliente pide entregar en otro sitio y quien factura lo apunta en el
// ticket. Esa dirección no coincide con la geolocalización del cliente, que es la
// única que manda PEDIDO. Aquí el logístico pone el punto bueno y MANDA sobre el
// del cliente (y sobrevive al espejo: lo hace el servidor). Decisión de Jose: nada
// de PEDIDO, el logístico lo pone en Reparto.
//
// Es UN cajón y se abre desde tres sitios sin copiar código: la ficha del pedido,
// la tarjeta de la parada del detalle de la ruta y cada fila del paso «Pedidos» del
// asistente. Lo que escribe es `AccionesDePedido` (web: al servidor y espera;
// APK y escritorio: la base local y la cola).
//
// # LAS TRES VÍAS DE PONER EL PUNTO
//
// Son las del editor de almacenes que se fue al CRM, y con el mismo cuidado:
//
//  1. escribir la dirección y BUSCARLA (Nominatim; con un botón, no mientras se
//     escribe: la política de uso de Nominatim y un punto que se mueve solo es el
//     que nadie mira antes de guardar);
//  2. escribir `lat, lng` a mano: no le pide nada a nadie, **funciona siempre**;
//  3. pulsar en el mapa: geometría, también sin señal.
//
// Las tres escriben en la MISMA caja de coordenadas por [_ponerElPunto], y lo que
// se guarda sale siempre de LEER esa caja: no hay dos sitios donde pueda estar el
// punto. Sin conexión la vía 1 no puede funcionar y se dice con esas palabras,
// dejando el punto como estaba.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/cajon.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart' show BotonPrincipal;
import '../../../mapa/ubicacion/coordenadas.dart';
import '../../../mapa/ubicacion/geocodificar.dart';
import '../../../mapa/ubicacion/mapa_para_elegir_punto.dart';
import '../../rutas/datos/acciones_rutas.dart' show RechazoLocal;
import '../../rutas/datos/mapa_en_vivo.dart' show fondoDeCallesProvider;
import '../datos/acciones_de_pedido.dart';
import '../datos/repositorio_pedidos.dart' show DetallePedido;
import '../estado/proveedores_pedidos.dart';

/// Abre el cajón de [pedidoId]. Devuelve cuando se cierra.
Future<void> abrirUbicarLaEntrega(BuildContext context, String pedidoId) =>
    abrirPanel<void>(context, (_) => CajonUbicarEntrega(pedidoId: pedidoId));

/// ¿Se le puede cambiar el punto a la ficha? `null` = sí; si no, el porqué en las
/// palabras del servidor.
///
/// La ruta que cuenta es la ACTUAL del pedido (`routeId`), no la que lo soltó: un
/// devuelto de una ruta ya completada queda libre para otra, y el servidor le deja
/// cambiar el punto (`LeerPedidoParaElPunto`, `route_id`). `DetallePedido.ruta`
/// también trae la ruta de la que salió con resultado, y mirarla bloquearía de más.
String? porQueNoSePuedeUbicar(DetallePedido ficha) =>
    porQueNoSeLePuedeCambiarElPunto(
      ficha.pedido,
      ficha.pedido.routeId == null ? null : ficha.ruta,
    );

class CajonUbicarEntrega extends ConsumerStatefulWidget {
  const CajonUbicarEntrega({required this.pedidoId, super.key});

  final String pedidoId;

  @override
  ConsumerState<CajonUbicarEntrega> createState() => _CajonUbicarEntregaState();
}

class _CajonUbicarEntregaState extends ConsumerState<CajonUbicarEntrega> {
  final _direccion = TextEditingController();
  final _punto = TextEditingController();

  /// Las cajas se rellenan UNA vez, con lo que el pedido tiene al abrir. La ficha
  /// se rehace sola cuando baja algo (`detallePedidoProvider`) y no puede pisar lo
  /// que la persona está escribiendo.
  bool _iniciado = false;

  /// Con qué se rellenaron las cajas: «Guardar punto» no se enciende hasta que
  /// algo cambie, o un pedido saldría marcado «a mano» sin que nadie lo moviera.
  String _puntoInicial = '';
  String _direccionInicial = '';

  /// Lo que pasó la última vez que se preguntó a Nominatim, ya en palabras.
  String? _loQuePaso;
  bool _loQuePasoEsFallo = false;
  bool _preguntando = false;

  /// La dirección que devolvió el mapa cuando YA había una escrita: se ofrece, no
  /// se pisa (la escribe mejor una persona que Nominatim en Cuba).
  String? _direccionQueOfreceElMapa;

  /// Si el fondo del mapa ha llegado. `false` es el caso normal en el patio de un
  /// almacén y se dice.
  bool _conCalles = false;

  bool _guardando = false;

  /// El «no» del servidor (o del aparato), literal, debajo de las cajas.
  String? _rechazo;

  @override
  void dispose() {
    _direccion.dispose();
    _punto.dispose();
    super.dispose();
  }

  PuntoEnElMapa? get _coordenadas =>
      _punto.text.trim().isEmpty ? null : leerCoordenadas(_punto.text);

  bool get _puntoMalEscrito =>
      _punto.text.trim().isNotEmpty && _coordenadas == null;

  bool get _hayCambios =>
      _punto.text.trim() != _puntoInicial ||
      _direccion.text.trim() != _direccionInicial;

  bool get _sePuedeBuscar =>
      _direccion.text.trim().length >= minimoParaBuscar && !_preguntando;

  /// PONE EL PUNTO. **Es el único sitio por el que se escribe la coordenada**, lo
  /// mande el mapa o lo mande la búsqueda.
  void _ponerElPunto(PuntoEnElMapa punto) {
    _punto.text = escribirCoordenadas(punto);
  }

  /// VÍA 1: la dirección escrita, buscada en Nominatim.
  Future<void> _buscarLaDireccion() async {
    setState(() {
      _preguntando = true;
      _loQuePaso = null;
      _direccionQueOfreceElMapa = null;
    });
    final hallado = await ref
        .read(geocodificadorProvider)
        .buscarDireccion(_direccion.text);
    if (!mounted) return;
    setState(() {
      _preguntando = false;
      switch (hallado) {
        case PuntoHallado(:final punto, :final comoLoLlama):
          // EL PUNTO ES EL QUE CONTESTÓ, sin tocar, y a la vista ANTES de guardar.
          _ponerElPunto(punto);
          _loQuePasoEsFallo = false;
          _loQuePaso = comoLoLlama == null
              ? 'Encontrado. Punto puesto en ${escribirCoordenadas(punto)}; '
                    'míralo en el mapa antes de guardar.'
              : 'Encontrado «$comoLoLlama». Punto puesto en '
                    '${escribirCoordenadas(punto)}; míralo en el mapa antes de '
                    'guardar.';
        case NoHayTalDireccion():
          // No encontrar una dirección no es motivo para mover un punto.
          _loQuePasoEsFallo = true;
          _loQuePaso =
              'No se encontró esa dirección. Prueba con menos detalle, o '
              'púlsalo en el mapa, o escribe las coordenadas a mano.';
        case DemasiadoCorto():
          _loQuePasoEsFallo = true;
          _loQuePaso =
              'Escribe al menos $minimoParaBuscar letras para poder buscar.';
        case NoSePudoPreguntar():
          // NO SE PUDO PREGUNTAR es otra cosa que «no existe».
          _loQuePasoEsFallo = true;
          _loQuePaso =
              'Sin conexión no se puede buscar una dirección: no se preguntó a '
              'nadie y el punto se ha quedado como estaba. Púlsalo en el mapa '
              'o escribe las coordenadas a mano — esa vía funciona siempre.';
      }
    });
  }

  /// VÍA 3: pulsar en el mapa. El punto se pone YA —es geometría del propio
  /// aparato—; lo único que se pide después es el nombre de la calle, y que no
  /// llegue no le quita nada al punto.
  Future<void> _pulsarEnElMapa(PuntoEnElMapa punto) async {
    setState(() {
      _ponerElPunto(punto);
      _direccionQueOfreceElMapa = null;
      _loQuePasoEsFallo = false;
      _loQuePaso = 'Punto puesto en ${escribirCoordenadas(punto)}.';
      _preguntando = true;
    });
    final dicho = await ref
        .read(geocodificadorProvider)
        .comoSeLlamaEstePunto(punto);
    if (!mounted) return;
    setState(() {
      _preguntando = false;
      switch (dicho) {
        case DireccionHallada(:final texto):
          if (_direccion.text.trim().isEmpty) {
            _direccion.text = texto;
            _loQuePaso =
                'Punto puesto en ${escribirCoordenadas(punto)}, con la '
                'dirección que le da el mapa.';
          } else {
            _direccionQueOfreceElMapa = texto;
          }
        case SinNombreParaEsePunto():
          _loQuePaso =
              'Punto puesto en ${escribirCoordenadas(punto)}. Ese sitio no '
              'tiene dirección con nombre: escríbela tú.';
        case NoSePudoPreguntarElPunto():
          // El punto sigue puesto y la dirección se queda VACÍA en vez de
          // rellenarse con las coordenadas, que sería un hueco disfrazado de dato.
          _loQuePaso =
              'Punto puesto en ${escribirCoordenadas(punto)}. Sin conexión no '
              'se pudo traer la dirección: escríbela tú.';
      }
    });
  }

  Future<void> _guardar() async {
    // LO QUE SE GUARDA ES LO QUE SE VE: sale de leer la caja de coordenadas.
    final punto = _coordenadas;
    if (punto == null) return;
    setState(() {
      _guardando = true;
      _rechazo = null;
    });
    try {
      await ref
          .read(accionesDePedidoProvider)
          .ponerPunto(
            widget.pedidoId,
            lat: punto.lat,
            lng: punto.lng,
            direccion: _direccion.text,
          );
      if (mounted) Navigator.of(context).pop();
    } on RechazoLocal catch (no) {
      // EL «NO» SE DICE, con sus palabras (§3-quinquies): el cajón no se cierra
      // como si hubiera ido bien.
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _rechazo = no.mensaje;
      });
    }
  }

  /// «Volver al punto del cliente» PREGUNTA, en un cajón: se pierde el punto que
  /// puso una persona (con su dirección), y rehacerlo es volver a ubicarlo.
  Future<void> _volverAlDelCliente(DetallePedido ficha) async {
    final p = ficha.pedido;
    final delCliente = p.puntoClienteLat == null || p.puntoClienteLng == null
        ? null
        : escribirCoordenadas(
            PuntoEnElMapa(p.puntoClienteLat!, p.puntoClienteLng!),
          );
    final seguro = await abrirCajon<bool>(
      context,
      titulo: 'Volver al punto del cliente',
      cuerpo: (c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'El punto puesto a mano se quita y la entrega vuelve a la '
            'geolocalización del cliente'
            '${delCliente == null ? '' : ' ($delCliente)'}'
            '${(p.puntoClienteAddress ?? '').isEmpty ? '' : ', ${p.puntoClienteAddress}'}. '
            'Los kilómetros de la parada se miden otra vez desde ahí. Para '
            'entregar en el otro sitio habría que ubicarlo de nuevo.',
          ),
          const SizedBox(height: 20),
          BotonPrincipal(
            texto: 'Sí, volver al punto del cliente',
            icono: Icons.undo,
            alPulsar: () => Navigator.of(c).pop(true),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('No, dejar el punto a mano'),
          ),
        ],
      ),
    );
    if (seguro != true || !mounted) return;
    setState(() {
      _guardando = true;
      _rechazo = null;
    });
    try {
      await ref
          .read(accionesDePedidoProvider)
          .volverAlPuntoDelCliente(widget.pedidoId);
      if (mounted) Navigator.of(context).pop();
    } on RechazoLocal catch (no) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _rechazo = no.mensaje;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ficha = ref.watch(detallePedidoProvider(widget.pedidoId)).value;
    if (ficha == null) {
      return Cajon(
        titulo: 'Ubicar la entrega',
        pie: _soloCerrar(),
        child: const Text('No se encontró la factura.'),
      );
    }
    final p = ficha.pedido;
    final tema = Theme.of(context);

    if (!_iniciado) {
      _iniciado = true;
      if (p.endLat != null && p.endLng != null) {
        _ponerElPunto(PuntoEnElMapa(p.endLat!, p.endLng!));
      }
      // La dirección del cliente NO se copia a la caja: vacía es «no la cambies», y
      // una dirección vieja escrita como si fuera la del sitio nuevo sería mentir.
      if (p.puntoManual) _direccion.text = p.endAddress ?? '';
      _puntoInicial = _punto.text.trim();
      _direccionInicial = _direccion.text.trim();
    }

    final no = porQueNoSePuedeUbicar(ficha);
    final subtitulo = [
      if ((p.operationNumber ?? '').isNotEmpty) p.operationNumber!,
      p.customerName,
    ].join(' · ');

    if (no != null) {
      // NO SE PUEDE, Y SE DICE POR QUÉ: sin formulario que se rechace al guardar.
      return Cajon(
        titulo: 'Ubicar la entrega',
        subtitulo: subtitulo,
        pie: _soloCerrar(),
        child: Text(no, key: const ValueKey('ubicar-no-se-puede')),
      );
    }

    final punto = _coordenadas;
    final centro = ficha.almacen?.lat != null && ficha.almacen?.lng != null
        ? PuntoEnElMapa(ficha.almacen!.lat!, ficha.almacen!.lng!)
        : centroDeCuba;

    return Cajon(
      titulo: 'Ubicar la entrega',
      subtitulo: subtitulo,
      pie: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton(
            onPressed: _guardando
                ? null
                : () => Navigator.of(context).maybePop(),
            child: const Text('Cancelar'),
          ),
          if (p.puntoManual)
            OutlinedButton.icon(
              onPressed: _guardando ? null : () => _volverAlDelCliente(ficha),
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Volver al punto del cliente'),
            ),
          BotonPrincipal(
            alPulsar: punto == null || !_hayCambios || _guardando
                ? null
                : _guardar,
            icono: Icons.edit_location_alt_outlined,
            texto: _guardando ? 'Guardando…' : 'Guardar punto',
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Si el cliente pidió entregar en otro sitio, ponlo aquí. Este punto '
            'manda sobre el de la geolocalización del cliente, y la parada sale '
            'en el mapa con su número en rojo.',
            style: tema.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            p.puntoManual
                ? 'Ahora: punto puesto a mano'
                      '${(p.puntoManualPor ?? '').isEmpty ? '' : ' por ${p.puntoManualPor}'}.'
                : 'Ahora: el punto del cliente '
                      '(${p.endAddress ?? p.address}).',
            style: tema.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          // VÍA 1 — la dirección, con su botón.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _direccion,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) =>
                      _sePuedeBuscar ? _buscarLaDireccion() : null,
                  decoration: const InputDecoration(
                    labelText: 'Dirección',
                    helperText:
                        'La de la entrega. Vacía, se queda la que tenía.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OutlinedButton.icon(
                  onPressed: _sePuedeBuscar ? _buscarLaDireccion : null,
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(_preguntando ? 'Buscando…' : 'Buscar'),
                ),
              ),
            ],
          ),
          if (_direccionQueOfreceElMapa case final ofrecida?) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'El mapa dice que ahí es «$ofrecida».',
                    style: tema.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _direccion.text = ofrecida;
                    _direccionQueOfreceElMapa = null;
                  }),
                  child: const Text('Usar ésa'),
                ),
              ],
            ),
          ],
          if (_loQuePaso case final dicho?) ...[
            const SizedBox(height: 6),
            Text(
              dicho,
              style: tema.textTheme.bodySmall?.copyWith(
                color: _loQuePasoEsFallo ? Colores.rojo : null,
              ),
            ),
          ],
          const SizedBox(height: 8),
          // VÍA 2 — a mano. **No se toca nunca**: es la que funciona siempre.
          TextField(
            controller: _punto,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Coordenadas',
              hintText: '19.83, -75.82',
              border: const OutlineInputBorder(),
              errorText: _puntoMalEscrito
                  ? 'No se entiende. Escríbelo como «19.83, -75.82».'
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          // VÍA 3 — el mapa.
          MapaParaElegirPunto(
            fondo: ref.watch(fondoDeCallesProvider),
            punto: punto,
            centroPorDefecto: centro,
            alElegir: _pulsarEnElMapa,
            alVerse: (que) {
              if (que.conCalles == _conCalles || !mounted) return;
              setState(() => _conCalles = que.conCalles);
            },
          ),
          const SizedBox(height: 6),
          Text(
            _conCalles
                ? 'Pulsa en el mapa para poner el punto. Dos dedos (o el ratón) '
                      'mueven el mapa.'
                : 'El fondo del mapa no ha cargado: sin señal se dibuja sólo si '
                      'está descargado el mapa de Cuba. Pulsar en el mapa pone el '
                      'punto igual, y escribir las coordenadas también.',
            style: tema.textTheme.bodySmall,
          ),
          if (_rechazo case final dicho?) ...[
            const SizedBox(height: 12),
            Text(
              dicho,
              key: const ValueKey('ubicar-rechazo'),
              style: tema.textTheme.bodyMedium?.copyWith(color: Colores.rojo),
            ),
          ],
        ],
      ),
    );
  }

  Widget _soloCerrar() => Align(
    alignment: Alignment.centerRight,
    child: TextButton(
      onPressed: () => Navigator.of(context).maybePop(),
      child: const Text('Cerrar'),
    ),
  );
}
