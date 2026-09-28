import 'package:flutter/material.dart';

import '../../../diseno/cajon.dart';
import '../../../diseno/tema.dart' show BotonDestructivo, BotonPrincipal;
import '../../rutas/datos/mapa_en_vivo.dart';
import '../datos/almacen_api.dart';
import '../datos/coordenadas.dart';
import '../datos/geocodificar.dart';
import 'mapa_para_elegir_punto.dart';

/// El editor de un almacen (cajon/modal `lg`). Pliego: `pantallas.md` §6.
///
/// Devuelve el almacen editado; quien compone la lista de la sucursal y la manda
/// a Accesos es la pantalla. La razon es la regla del principal: para desmarcar
/// a los demas hay que ver la lista entera, y este widget sólo ve uno.
///
/// ═══════════════════════════════════════════════════════════════════════════
/// LAS TRES VIAS DE PONER EL PUNTO, Y POR QUE SON TRES
/// ═══════════════════════════════════════════════════════════════════════════
///
/// De este punto salen los kilometros de cada cliente de la sucursal, y de esos
/// kilometros sale lo que se le cobra a cada domicilio **todos los dias**. Un
/// punto puesto a ojo con dos digitos cambiados se lee perfectamente bien y esta
/// mal, que es lo peor que le puede pasar a un numero que alguien va a cobrar
/// (`CLAUDE.md` §4). Por eso hay tres formas de ponerlo y no una:
///
///  1. **Escribir la direccion y buscarla.** Sale a Nominatim. Es la comoda: la
///     direccion del almacen se sabe siempre, las coordenadas no las sabe nadie
///     de memoria.
///  2. **Escribir `lat, lng` a mano.** No le pide nada a nadie. Es la que
///     **nunca falla** y por eso no se toca jamas (ver `datos/coordenadas.dart`).
///  3. **Pulsar en el mapa.** Tambien es geometria y **tambien funciona sin
///     señal**: lo unico que necesita red es traer el nombre de la calle
///     despues, y eso es un adorno que se puede quedar vacio.
///
/// Las tres escriben en la MISMA caja de coordenadas, con el mismo formato
/// (`escribirCoordenadas`), y lo que se guarda sale siempre de leer esa caja.
/// Asi no hay dos sitios donde pueda estar el punto: lo que se ve es lo que se
/// manda a Accesos.
///
/// ═══════════════════════════════════════════════════════════════════════════
/// SIN CONEXION: SE DICE, Y NO SE INVENTA NADA
/// ═══════════════════════════════════════════════════════════════════════════
///
/// La mitad del proyecto es trabajar sin señal (`CLAUDE.md` §1), y aqui eso
/// parte las tres vias en dos grupos:
///
///  * la 2 y la 3 siguen funcionando enteras (la 3 pinta el fondo con el paquete
///    de Cuba descargado, y sin fondo el punto se pone igual);
///  * la 1 **no puede funcionar**, y entonces la pantalla lo dice con esas
///    palabras y **deja el punto como estaba**. Ni se queda girando, ni contesta
///    «esa direccion no existe» —que seria mentira—, ni escribe unas coordenadas
///    inventadas.
///
/// Ahi esta la separacion del patron que hay que tener escrita (§2): su
/// `reverseGeocode` devuelve `formatCoords(lat,lng)` cuando falla, o sea que la
/// caja de la direccion se rellena sola con «20.02470, -75.82190» y la pantalla
/// queda **identica** a si hubiera geocodificado. Aqui no: sin respuesta, la
/// direccion se queda como estaba y se dice por que.
///
/// Y la otra separacion, tambien a proposito: **se busca con un boton, no
/// mientras se escribe**. El patron geocodifica solo a los 700 ms de cada pausa.
/// Dos motivos: la politica de uso de Nominatim (una peticion por segundo, y el
/// castigo por pasarse es un bloqueo por IP — ya nos paso con las teselas el
/// 04/08/2026, `api/internal/api/mapa.go`), y que un punto que se mueve solo
/// mientras alguien teclea es justo el punto que nadie mira antes de guardar.
class EditorAlmacen extends StatefulWidget {
  const EditorAlmacen({
    required this.sucursal,
    required this.guardando,
    required this.alGuardar,
    required this.geocodificador,
    required this.fondoDelMapa,
    this.almacen,
    this.alQuitar,
    this.centroDelMapa,
    super.key,
  });

  /// `null` = almacen nuevo.
  final AlmacenDeAccesos? almacen;

  /// El nombre de la sucursal, que va de subtitulo.
  final String sucursal;
  final bool guardando;
  final ValueChanged<AlmacenDeAccesos> alGuardar;

  /// Quien traduce entre direcciones y puntos. **Inyectado**, como el fondo del
  /// mapa del croquis de la ruta y por lo mismo: en las pruebas entra
  /// [SinGeocodificar] y no sale ni una peticion, que es regla de la casa en
  /// este PC.
  final Geocodificador geocodificador;

  /// De donde salen las teselas. En la APK y el escritorio es el paquete de Cuba
  /// descargado; en las pruebas, [SinCalles].
  final FondoDeCalles fondoDelMapa;

  /// Donde abrir el mapa cuando este almacen todavia no tiene punto. La pantalla
  /// pasa el de otro almacen de la misma sucursal si lo hay.
  final PuntoEnElMapa? centroDelMapa;

  /// `null` en uno nuevo: no se puede quitar lo que aun no existe.
  final VoidCallback? alQuitar;

  @override
  State<EditorAlmacen> createState() => _EditorAlmacenState();
}

class _EditorAlmacenState extends State<EditorAlmacen> {
  late final TextEditingController _nombre;
  late final TextEditingController _direccion;
  late final TextEditingController _punto;

  late bool _principal;
  late bool _activo;

  /// Lo que paso la ultima vez que se pregunto a Nominatim, ya en palabras. Se
  /// pinta tal cual debajo de la direccion.
  String? _loQuePaso;

  /// Si lo de arriba es un fallo (rojo) o una noticia normal.
  bool _loQuePasoEsFallo = false;

  bool _preguntando = false;

  /// La direccion que devolvio el mapa cuando **ya habia una escrita**. No se
  /// pisa sola: se ofrece.
  ///
  /// El patron sobrescribe la direccion en cada pulsacion del mapa. Alli daba
  /// igual porque era una caja sola; aqui la direccion la escribe una persona
  /// —y en Cuba la escribe mejor que Nominatim, que devuelve cosas como «90400,
  /// Cuba»—, asi que un toque sin querer no puede borrarla. Si la caja esta
  /// vacia si se rellena sola: ahi no hay nada que perder.
  String? _direccionQueOfreceElMapa;

  /// Si el fondo del mapa ha llegado. `false` es el caso normal en el patio de
  /// un almacen y **se dice**, en vez de dejar un recuadro liso sin explicacion.
  bool _conCalles = false;

  @override
  void initState() {
    super.initState();
    final a = widget.almacen;
    _nombre = TextEditingController(text: a?.nombre ?? '');
    _direccion = TextEditingController(text: a?.direccion ?? '');
    _punto = TextEditingController(
      text: a == null || a.sinPunto ? '' : '${a.latitud}, ${a.longitud}',
    );
    _principal = a?.principal ?? false;
    _activo = a?.activo ?? true;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _direccion.dispose();
    _punto.dispose();
    super.dispose();
  }

  PuntoEnElMapa? get _coordenadas =>
      _punto.text.trim().isEmpty ? null : leerCoordenadas(_punto.text);

  bool get _puntoMalEscrito =>
      _punto.text.trim().isNotEmpty && _coordenadas == null;

  bool get _leFaltaElNombre => _nombre.text.trim().isEmpty;

  bool get _sePuedeBuscar =>
      _direccion.text.trim().length >= minimoParaBuscar && !_preguntando;

  /// PONE EL PUNTO. **Es el unico sitio por el que se escribe la coordenada**,
  /// lo mande el mapa o lo mande la busqueda: si cada via escribiera por su
  /// cuenta, arreglar el formato en una dejaria las otras dos con el viejo.
  void _ponerElPunto(PuntoEnElMapa punto) {
    _punto.text = escribirCoordenadas(punto);
  }

  /// VIA 1: la direccion escrita, buscada en Nominatim.
  Future<void> _buscarLaDireccion() async {
    setState(() {
      _preguntando = true;
      _loQuePaso = null;
      _direccionQueOfreceElMapa = null;
    });
    final hallado = await widget.geocodificador.buscarDireccion(
      _direccion.text,
    );
    if (!mounted) return;
    setState(() {
      _preguntando = false;
      switch (hallado) {
        case PuntoHallado(:final punto, :final comoLoLlama):
          // EL PUNTO ES EL QUE CONTESTO, sin tocar. Escribirlo en la caja es lo
          // que lo deja a la vista ANTES de guardar: quien mira ve la
          // coordenada y el mapa saltando a ella, y puede decir que no.
          _ponerElPunto(punto);
          _loQuePasoEsFallo = false;
          _loQuePaso = comoLoLlama == null
              ? 'Encontrado. Punto puesto en ${escribirCoordenadas(punto)}; '
                    'míralo en el mapa antes de guardar.'
              : 'Encontrado «$comoLoLlama». Punto puesto en '
                    '${escribirCoordenadas(punto)}; míralo en el mapa antes de '
                    'guardar.';
        case NoHayTalDireccion():
          // Contesto y no la conoce. **El punto que hubiera no se toca**: no
          // encontrar una direccion no es motivo para mover un almacen.
          _loQuePasoEsFallo = true;
          _loQuePaso =
              'No se encontró esa dirección. Prueba con menos detalle, o '
              'púlsalo en el mapa, o escribe las coordenadas a mano.';
        case DemasiadoCorto():
          _loQuePasoEsFallo = true;
          _loQuePaso =
              'Escribe al menos $minimoParaBuscar letras para poder buscar.';
        case NoSePudoPreguntar():
          // NO SE PUDO PREGUNTAR. Es otra cosa que «no existe» y se dice con
          // otras palabras, porque lo que hay que hacer es distinto.
          _loQuePasoEsFallo = true;
          _loQuePaso =
              'Sin conexión no se puede buscar una dirección: no se preguntó a '
              'nadie y el punto se ha quedado como estaba. Púlsalo en el mapa '
              'o escribe las coordenadas a mano — esa vía funciona siempre.';
      }
    });
  }

  /// VIA 3: pulsar en el mapa.
  ///
  /// **El punto se pone YA**, antes de preguntar nada: es geometria del propio
  /// aparato y no depende de que haya señal. Lo unico que se pide despues es el
  /// nombre de la calle, y que no llegue no le quita nada al punto.
  Future<void> _pulsarEnElMapa(PuntoEnElMapa punto) async {
    setState(() {
      _ponerElPunto(punto);
      _direccionQueOfreceElMapa = null;
      _loQuePasoEsFallo = false;
      _loQuePaso = 'Punto puesto en ${escribirCoordenadas(punto)}.';
      _preguntando = true;
    });
    final dicho = await widget.geocodificador.comoSeLlamaEstePunto(punto);
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
            // Ya habia direccion escrita: se OFRECE, no se pisa.
            _direccionQueOfreceElMapa = texto;
          }
        case SinNombreParaEsePunto():
          _loQuePaso =
              'Punto puesto en ${escribirCoordenadas(punto)}. Ese sitio no '
              'tiene dirección con nombre: escríbela tú.';
        case NoSePudoPreguntarElPunto():
          // El punto sigue puesto —eso no dependia de la red— y la direccion se
          // queda VACIA en vez de rellenarse con las coordenadas, que es lo que
          // hace el patron y lo que deja un hueco disfrazado de dato.
          _loQuePaso =
              'Punto puesto en ${escribirCoordenadas(punto)}. Sin conexión no '
              'se pudo traer la dirección: escríbela tú.';
      }
    });
  }

  Future<void> _confirmarQuitar() async {
    final nombre = widget.almacen?.titulo ?? '';
    final seguro = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        content: Text('¿Quitar «$nombre»? Deja de poder medirse desde ahí.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Cancelar'),
          ),
          // QUITAR UN ALMACEN ES DESTRUCTIVO, y este es el boton que lo
          // confirma: va en rojo, con contorno de 2 px y con la papelera, igual
          // que el «Sí, borrar la columna» del tablero. Estaba de principal —el
          // oro de guardar— dentro de un cuadro que pregunta si se borra.
          BotonDestructivo(
            texto: 'Quitar',
            alPulsar: () => Navigator.of(contexto).pop(true),
          ),
        ],
      ),
    );
    if (seguro ?? false) widget.alQuitar?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final punto = _coordenadas;

    return Cajon(
      titulo: widget.almacen == null ? 'Nuevo almacén' : widget.almacen!.titulo,
      subtitulo: widget.sucursal,
      pie: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: widget.guardando
                ? null
                : () => Navigator.of(context).maybePop(),
            child: const Text('Cerrar'),
          ),
          const SizedBox(width: 8),
          BotonPrincipal(
            alPulsar: _leFaltaElNombre || _puntoMalEscrito || widget.guardando
                ? null
                : () => widget.alGuardar(
                    AlmacenDeAccesos(
                      id: widget.almacen?.id,
                      nombre: _nombre.text.trim(),
                      direccion: _direccion.text.trim().isEmpty
                          ? null
                          : _direccion.text.trim(),
                      // LO QUE SE GUARDA ES LO QUE SE VE. Sale de leer la caja
                      // de coordenadas, escriba en ella quien escriba: la mano,
                      // el mapa o la busqueda.
                      latitud: punto?.lat,
                      longitud: punto?.lng,
                      principal: _principal,
                      activo: _activo,
                    ),
                  ),
            icono: Icons.save_outlined,
            texto: widget.guardando ? 'Guardando…' : 'Guardar',
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nombre,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Nombre del almacén',
                border: OutlineInputBorder(),
              ),
            ),
            if (_leFaltaElNombre)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Le falta el nombre.',
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: tema.colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Tooltip(
                  message: 'Desde éste se mide cuando nadie dice cuál',
                  child: FilterChip(
                    selected: _principal,
                    label: const Text('Principal'),
                    avatar: Icon(
                      _principal ? Icons.star : Icons.star_border,
                      size: 18,
                    ),
                    onSelected: (v) => setState(() => _principal = v),
                  ),
                ),
                FilterChip(
                  selected: _activo,
                  label: Text(_activo ? 'Activo' : 'Inactivo'),
                  onSelected: (v) => setState(() => _activo = v),
                ),
                if (widget.alQuitar != null)
                  IconButton(
                    tooltip: 'Quitar',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: widget.guardando ? null : _confirmarQuitar,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Dónde está', style: tema.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Tres formas de poner el punto: buscar la dirección, pulsar en el '
              'mapa, o escribir las coordenadas. Escribirlas a mano funciona '
              'siempre, también sin conexión.',
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            // VIA 1 — la direccion, con su boton. El boton y no un temporizador:
            // ver la cabecera de la clase.
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
                  color: _loQuePasoEsFallo ? tema.colorScheme.error : null,
                ),
              ),
            ],
            const SizedBox(height: 8),
            // VIA 2 — a mano. **No se toca nunca**: es la que funciona siempre.
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
            // VIA 3 — el mapa.
            MapaParaElegirPunto(
              fondo: widget.fondoDelMapa,
              punto: punto,
              centroPorDefecto: widget.centroDelMapa ?? centroDeCuba,
              alElegir: _pulsarEnElMapa,
              alVerse: (que) {
                if (que.conCalles == _conCalles || !mounted) return;
                setState(() => _conCalles = que.conCalles);
              },
            ),
            const SizedBox(height: 6),
            Text(
              _conCalles
                  ? 'Pulsa en el mapa para poner el punto. Dos dedos (o el '
                        'ratón) mueven el mapa.'
                  // LO QUE SE VE SE DICE. Un recuadro liso encima de un punto
                  // que se va a cobrar es el peor sitio para adivinar; y lo que
                  // hay que saber es que **pulsar sigue funcionando**.
                  : 'El fondo del mapa no ha cargado: sin señal se dibuja sólo '
                        'si está descargado el mapa de Cuba. Pulsar en el mapa '
                        'pone el punto igual, y escribir las coordenadas '
                        'también.',
              style: tema.textTheme.bodySmall,
            ),
            if (punto == null && !_puntoMalEscrito) ...[
              const SizedBox(height: 8),
              // El aviso del pliego. Un almacen sin punto entra igual —a veces no
              // se sabe todavia— pero desde el no se cotiza, y eso tiene que
              // estar dicho antes de guardar, no descubrirse al cotizar.
              Text(
                'Sin coordenadas: desde éste no se puede medir el domicilio.',
                style: tema.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
