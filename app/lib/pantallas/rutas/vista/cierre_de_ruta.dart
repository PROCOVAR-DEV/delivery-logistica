// El cierre parada por parada. **Es el caso de uso principal del proyecto.**
//
// El camion vuelve al patio del almacen, donde no hay senal, y hay que cuadrar lo
// que baja. Asi que aqui no se espera a nadie: se marca, se guarda en la base
// local con la hora del aparato, se encola el apunte y la pantalla se pinta como
// hecha. Si hay red, sube por detras; si no, sube manana y sigue diciendo la hora
// de hoy.
//
// Pliego: `../../../../docs/pantallas.md` §9.1.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/tema.dart';
import '../../../impresion/armar_post_despacho.dart' as papel;
import '../../../impresion/post_despacho.dart' show pdfPostDespacho;
import '../../../impresion/vista_previa.dart';
import '../../../nucleo/base/base.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../../pedidos/datos/formato.dart';
import '../../pedidos/datos/repositorio_pedidos.dart';
import '../../pedidos/vista/kit.dart';
import '../datos/acciones_rutas.dart';
import '../datos/post_despacho.dart';
import '../datos/repositorio_rutas.dart';
import '../estado/proveedores_rutas.dart';

/// EN QUE MOMENTO SE ABRE EL CIERRE. Son tres, y no es lo mismo.
enum ModoDelCierre {
  /// Operación interna de guardado que se conserva para probar el protocolo
  /// de resultados. Ninguna entrada de navegación ofrece este modo: los
  /// estados se piden sólo al pulsar «Marcar como completada».
  marcar,

  /// Se acaba de pulsar `Marcar como completada`. Aquí se revisan siempre
  /// todas las paradas, conservando marcas anteriores. Al guardar, se da por
  /// completada en el mismo gesto.
  alCompletar,

  /// La ruta ya esta COMPLETADA: el cierre solo se mira.
  soloLectura,
}

class CierreDeRuta extends ConsumerStatefulWidget {
  const CierreDeRuta({
    required this.rutaId,
    required this.modo,
    this.alCompletar,
    super.key,
  });

  final String rutaId;

  /// Ver `ModoDelCierre`.
  final ModoDelCierre modo;

  /// Lo que hace la pantalla DESPUES de completar, en el modo `alCompletar`:
  /// soltar la ruta elegida e irse al Historial. Vive fuera porque es
  /// navegacion de la pantalla de Rutas, no del cajon.
  final VoidCallback? alCompletar;

  /// La cabecera, literal. Explica la regla que mas se malinterpreta: lo que no
  /// se entrego sigue arriba, y lo devuelto no toca inventario —eso lo hace
  /// Ventra—, aqui queda la constancia.
  static const cabecera =
      'Marca cada parada según cómo acabó. De aquí sale el post-despacho: lo que '
      'tiene que quedar en el camión es todo lo que no se entregó. Lo devuelto y '
      'lo cancelado no tocan el inventario —eso lo hace Ventra—: aquí queda la '
      'constancia y el control de lo que baja.';

  static const exito =
      'Cierre guardado. En PEDIDO cada pedido ya dice si se entregó o volvió.';

  /// LA CABECERA DEL MODO `alCompletar`, literal.
  ///
  /// Jose, 17/09/2026, mirando el cierre de una ruta ya completada: «ese estado
  /// se pone cuando están en ruta, no completados; ahí el cierre ya viene con el
  /// estado de cuando le van a dar a completado, es que se pregunta ese estado».
  static const cabeceraAlCompletar =
      'Antes de dar la ruta por completada: ¿cómo acabó cada parada? Lo que '
      'dejes sin marcar se da por no entregado y cuenta como que sigue en el '
      'camión.';

  /// LA CABECERA DEL MODO `soloLectura`, literal. Una ruta completada ya no se
  /// marca: lo que se ve es como acabo.
  static const cabeceraSoloLectura =
      'La ruta ya está completada: así acabó cada parada. Para corregir algo, '
      'hay que hacerlo en PEDIDO.';

  static const exitoAlCompletar =
      'Cierre guardado y ruta completada. En PEDIDO cada pedido ya dice si se '
      'entregó o volvió.';

  @override
  ConsumerState<CierreDeRuta> createState() => _CierreDeRutaState();
}

class _CierreDeRutaState extends ConsumerState<CierreDeRuta> {
  /// Lo marcado en esta sesion. `null` en el mapa = sin marcar.
  final _resultados = <String, String?>{};

  /// LO QUE HABIA GUARDADO AL ABRIR. De aqui sale saber si una parada se
  /// DESMARCO, que es distinto de no haberla tocado nunca — 28/09/2026.
  ///
  /// Jose: «desmarco el estado de cierre y no se guarda cuando salgo por q
  /// razon». Sin esta foto no hay forma de distinguir los dos nulos: el de «esta
  /// parada nunca se marco» y el de «estaba marcada y le he quitado la marca».
  /// El primero no tiene nada que guardar; el segundo si, y era el que se
  /// perdia.
  final _alAbrir = <String, String?>{};
  final _notas = <String, TextEditingController>{};
  bool _partidoDeLoGuardado = false;
  bool _guardando = false;

  @override
  void dispose() {
    for (final control in _notas.values) {
      control.dispose();
    }
    super.dispose();
  }

  /// **Al abrir se parte de lo ya guardado en cada parada** (resultado y nota).
  /// Sin esto, reabrir el cierre para corregir una parada borraria las otras
  /// veinte de la vista y habria que marcarlas otra vez.
  void _partirDeLoGuardado(List<Pedido> paradas) {
    // **`paradas.isEmpty` no es «ninguna parada»: casi siempre es «todavia no han
    // llegado».** Las paradas vienen de un flujo de la base y el primer
    // fotograma se pinta con la lista vacia. Dandolo por bueno se marcaba el
    // arranque como hecho contra cero paradas, y cuando llegaban de verdad ya no
    // se volvia a mirar: reabrir el cierre para corregir UNA parada ensenaba las
    // otras veinte sin marcar, como si no se hubiera guardado nada.
    if (_partidoDeLoGuardado || paradas.isEmpty) return;
    _partidoDeLoGuardado = true;
    for (final parada in paradas) {
      _resultados[parada.id] = parada.resultado;
      _alAbrir[parada.id] = parada.resultado;
      _notaGuardada[parada.id] = parada.resultadoNota ?? '';
      _notas[parada.id] = TextEditingController(
        text: parada.resultadoNota ?? '',
      );
    }
  }

  TextEditingController _nota(String pedidoId) =>
      _notas.putIfAbsent(pedidoId, TextEditingController.new);

  int get _marcadas => _resultados.values.where((r) => r != null).length;

  /// Las que estaban marcadas al abrir y ya NO lo estan. Es lo que hay que
  /// guardar de un desmarcado, y es lo que antes no contaba nadie.
  int get _desmarcadas => _alAbrir.entries
      .where((e) => e.value != null && _resultados[e.key] == null)
      .length;

  /// Lo que ha cambiado respecto a lo guardado: marcas nuevas, marcas cambiadas
  /// y marcas quitadas. **Las notas tambien cuentan**, o alguien escribe un
  /// motivo de devolucion, sale, y ese motivo no existe.
  int get _cambios => _alAbrir.keys
      .where(
        (id) =>
            _resultados[id] != _alAbrir[id] ||
            (_resultados[id] != null &&
                _nota(id).text.trim() != (_notaGuardada[id] ?? '')),
      )
      .length;

  /// La nota tal y como estaba al abrir, para poder ver si se toco.
  final _notaGuardada = <String, String>{};

  /// HAY ALGO QUE GUARDAR — 28/09/2026.
  ///
  /// Era `_marcadas == 0`, y ahi estaba la segunda mitad del fallo de Jose
  /// («desmarco el estado de cierre y no se guarda cuando salgo»): abre una hoja
  /// con UNA parada marcada, le quita la marca, y el boton de guardar **se
  /// apaga**. Aunque la pantalla hubiera sabido mandar el desmarcado —no sabia—,
  /// no habia forma de pulsarlo. Quitar la ultima marca es un cambio, y de los
  /// que mas importan: dice que esa parada no bajo del camion.
  bool get _hayQueGuardar => _marcadas > 0 || _desmarcadas > 0;

  bool get _soloLectura =>
      widget.modo == ModoDelCierre.soloLectura ||
      ref.read(rutaConTodoProvider(widget.rutaId)).value?.ruta.status ==
          EstadoRuta.completada;
  bool get _completando => widget.modo == ModoDelCierre.alCompletar;

  void _marcar(String pedidoId, String resultado) => setState(() {
    // **Pulsar el mismo boton dos veces desmarca.** Es como se corrige un dedazo
    // sin tener que recargar nada.
    _resultados[pedidoId] = _resultados[pedidoId] == resultado
        ? null
        : resultado;
  });

  void _todas(String resultado, List<Pedido> paradas) => setState(() {
    for (final parada in paradas) {
      _resultados[parada.id] = resultado;
    }
  });

  Future<void> _guardar(List<Pedido> paradas) async {
    // LO MARCADO **Y LO DESMARCADO** — 28/09/2026.
    //
    // Jose: «desmarco el estado de cierre y no se guarda cuando salgo por q
    // razon». Aqui ponia `if (_resultados[parada.id] != null)`, o sea que una
    // parada a la que se le habia QUITADO la marca sencillamente no entraba en
    // la lista: no se encolaba nada para ella, el servidor no se enteraba, y al
    // volver a abrir la hoja la marca vieja seguia puesta. Marcar si persistia;
    // quitar la marca, no.
    //
    // Es el clasico de «un valor que se quita se confunde con no haber tocado
    // nada», y aqui pasaba en el primer eslabon de la cadena: el nulo ni
    // siquiera llegaba a salir de la pantalla.
    //
    // Se manda `resultado: null` SOLO para las que estaban marcadas al abrir y
    // ahora no lo estan. Las que nunca se marcaron no se mandan: un apunte por
    // cada parada intacta seria escribir veinte UPDATE para no cambiar nada, y
    // ademas los apuntes de la cola se leen uno a uno cuando algo va mal.
    final marcas = <MarcaDeParada>[
      for (final parada in paradas)
        if (_resultados[parada.id] != null)
          MarcaDeParada(
            pedidoId: parada.id,
            resultado: _resultados[parada.id],
            nota: _nota(parada.id).text,
          )
        else if (_alAbrir[parada.id] != null)
          // Estaba marcada y se le quito la marca. La nota se va con ella.
          MarcaDeParada(pedidoId: parada.id, resultado: null),
    ];
    final completando = widget.modo == ModoDelCierre.alCompletar;
    // Sin nada marcado no hay nada que guardar **y no pasa nada**: se puede dar
    // una ruta por completada dejando paradas sin marcar, que es como se dice
    // «eso siguio en el camion». Lo que no se puede es salir sin hacer nada,
    // por eso el `return` solo vale fuera del modo de completar.
    if (marcas.isEmpty && !completando) return;

    setState(() => _guardando = true);
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final navegador = Navigator.of(context);
    try {
      // En APK/escritorio escribe y encola; en web espera el servidor.
      // Un rechazo parcial se muestra, pero no impide completar lo que sí se guardó.
      final acciones = ref.read(accionesDeRutaProvider);
      String? avisoDeParadasRechazadas;
      ResultadoCierreDeRuta? resultadoDelCierre;
      if (marcas.isNotEmpty) {
        resultadoDelCierre = await acciones.cerrar(widget.rutaId, marcas);
        avisoDeParadasRechazadas = resultadoDelCierre.aviso;
      }
      // Completar va después de guardar. Un rechazo total sigue dejando la ruta
      // abierta; un rechazo parcial trae los IDs válidos y un aviso para corregir.
      if (completando) await acciones.completar(widget.rutaId);
      RegistroDeControles.completar(Senalado.rutasGuardarElCierre);
      // LA FOTO DE «LO GUARDADO» SE MUEVE. Sin esto, tras guardar, el boton de
      // salir seguiria diciendo que hay cambios pendientes sobre algo que ya
      // esta escrito, y un aviso que sale siempre deja de leerse (§3-quinquies).
      for (final marca in marcas) {
        if (resultadoDelCierre != null &&
            !resultadoDelCierre.idsAplicados.contains(marca.pedidoId)) {
          continue;
        }
        _alAbrir[marca.pedidoId] = marca.resultado;
        _notaGuardada[marca.pedidoId] = marca.quitaLaMarca
            ? ''
            : _nota(marca.pedidoId).text.trim();
      }
      mensajero?.showSnackBar(
        SnackBar(
          duration: avisoDeParadasRechazadas == null
              ? const Duration(seconds: 4)
              : const Duration(seconds: 8),
          content: Text(
            avisoDeParadasRechazadas ??
                (completando
                    ? CierreDeRuta.exitoAlCompletar
                    : CierreDeRuta.exito),
          ),
        ),
      );
      navegador.maybePop();
      if (completando) widget.alCompletar?.call();
    } on RechazoLocal catch (fallo) {
      // El mensaje del servidor, literal y sin envolver.
      mensajero?.showSnackBar(SnackBar(content: Text(fallo.mensaje)));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// ¿DE VERDAD SE VA SIN GUARDAR? `true` sólo si la persona lo dice.
  ///
  /// Cajón y no diálogo, también en escritorio: regla de la casa (§4). Y la
  /// pregunta lleva el NÚMERO delante en vez de un «¿seguro?»: quien tiene doce
  /// marcas puestas no le da que sí sin mirar si el título se las cuenta.
  ///
  /// Los dos botones dicen lo que hacen —«Seguir marcando» y «Salir y
  /// perderlas»—, que es lo que deja contestar sin volver a leer el título.
  Future<bool> _seVaSinGuardar() async {
    final dijoQueSi = await abrirCajon<bool>(
      context,
      (contexto) => Cajon(
        titulo: 'Tienes $_cambios sin guardar',
        subtitulo:
            'Si sales ahora se pierden, y marcar las paradas otra vez es '
            'volver a recorrer la hoja entera.',
        ancho: AnchoCajon.md,
        cuerpo: Padding(
          padding: const EdgeInsets.all(Aire.lg),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: Aire.sm,
            runSpacing: Aire.sm,
            children: [
              TextButton.icon(
                key: const ValueKey('cierre-seguir-marcando'),
                style: Botones.secundario(),
                onPressed: () => Navigator.of(contexto).pop(false),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Seguir marcando'),
              ),
              TextButton.icon(
                key: const ValueKey('cierre-salir-sin-guardar'),
                style: Botones.destructivo(),
                onPressed: () => Navigator.of(contexto).pop(true),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Salir y perderlas'),
              ),
            ],
          ),
        ),
      ),
    );
    return dijoQueSi ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final datosRuta = ref.watch(rutaConTodoProvider(widget.rutaId));
    final datosParadas = ref.watch(paradasDeRutaProvider(widget.rutaId));
    final ruta = datosRuta.value;
    final paradas = datosParadas.value ?? const <Pedido>[];
    // Un vacío mientras llega la consulta no prueba que la ruta no tenga paradas.
    final datosListos =
        ruta != null &&
        datosParadas.hasValue &&
        !datosRuta.hasError &&
        !datosParadas.hasError;
    final errorDatos = datosRuta.error ?? datosParadas.error;
    final renglones =
        ref.watch(renglonesDeParadasProvider(widget.rutaId)).value ??
        const <String, List<RenglonConPeso>>{};

    _partirDeLoGuardado(paradas);

    final sinMarcar = paradas.where((p) => _resultados[p.id] == null).length;
    final hoja = armarPostDespacho([
      for (final parada in paradas)
        ParadaDelCierre(
          pedidoId: parada.id,
          cliente: parada.customerName,
          resultado: _resultados[parada.id],
          lineas: [
            for (final r in renglones[parada.id] ?? const <RenglonConPeso>[])
              LineaDeParada(r.renglon.description, r.empaques),
          ],
        ),
    ]);

    // EL «ATRÁS» DEL SISTEMA PREGUNTA — 29/09/2026.
    //
    // Se vio probando el cierre en el teléfono: con dos paradas marcadas y sin
    // guardar, el botón de atrás cerró el cajón y **se perdieron las dos**. La
    // pantalla lo avisaba —el botón de abajo dice «Salir sin guardar (2 sin
    // guardar)»— pero eso es el rótulo de un botón que nadie pulsó: quien da
    // atrás no lo lee. Y en Android el atrás se hace sin mirar, con el gesto del
    // borde: una jornada de doce marcas se va con eso.
    //
    // **No se bloquea, se pregunta**, que es lo que ya decía el comentario del
    // botón de salir: irse sin guardar es legítimo —se abrió a mirar y se tocó
    // sin querer— y un cajón que no deja salir es peor. Lo que no puede pasar es
    // que se pierda sin que nadie lo diga (§4).
    //
    // Y sin nada que perder no pregunta nada: un aviso que sale siempre deja de
    // leerse, y entonces tampoco se lee el día que importa (§3-quinquies).
    return PopScope(
      canPop: _soloLectura || _cambios == 0,
      onPopInvokedWithResult: (bool salio, Object? _) async {
        if (salio || !mounted) return;
        // EL NAVIGATOR SE COGE ANTES DEL `await`, no despues. Entre la pregunta
        // y la respuesta puede pasar de todo —cerrar sesion, un 401 que echa a
        // la puerta— y buscar el contexto al volver es buscarlo en un arbol que
        // ya no es el mismo.
        final volver = Navigator.of(context);
        if (await _seVaSinGuardar() && mounted) volver.pop();
      },
      child: Cajon(
        titulo: 'Cierre de ruta',
        subtitulo:
            '${ruta?.ruta.routeCode ?? ruta?.ruta.name ?? widget.rutaId} · '
            '${paradas.length} parada(s)',
        ancho: AnchoCajon.xl,
        // EL PIE VA EN UN `Wrap`, NO EN UN `Row` — 22/09/2026.
        //
        // Era un `Row` con un `Spacer`, y un `Row` no baja de linea: aprieta.
        // Medido a 390 px —el telefono de Jose—, los tres botones piden 678 px en
        // los 342 que hay: **desbordaba 336 px** y `Guardar 0 marcada(s)`
        // terminaba en x=677.9, o sea 288 px POR FUERA de la pantalla. El boton
        // de guardar el cierre, inalcanzable en un telefono, que es justo el
        // aparato con el que se cierra una ruta en el patio del almacen.
        //
        // Con el `Wrap` los que no caben bajan ENTEROS y `Guardar` se queda solo
        // en la segunda linea, que ademas es donde tiene que estar: es la accion
        // principal.
        pie: Wrap(
          alignment: WrapAlignment.end,
          spacing: Aire.sm,
          runSpacing: Aire.sm,
          children: [
            ControlSenalado(
              nombre: Senalado.rutasPostDespacho,
              child: OutlinedButton(
                onPressed: () => _verPostDespacho(
                  ruta: ruta,
                  paradas: paradas,
                  renglones: renglones,
                ),
                child: const Text('Post-despacho'),
              ),
            ),
            // NADA SE DESCARTA EN SILENCIO (§4). Si hay algo sin guardar, el boton
            // lo dice con su cuenta en vez de llamarse «Cerrar»: cerrar la hoja
            // con tres marcas puestas y que no pase nada es el «dato que esta y no
            // se escribe» en su version mas barata de evitar.
            //
            // Se DICE y no se bloquea: salir sin guardar es legitimo —se abrio a
            // mirar y se toco sin querer— y un cajon que no deja salir es peor.
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(
                _soloLectura || _cambios == 0
                    ? 'Cerrar'
                    : 'Salir sin guardar ($_cambios sin guardar)',
              ),
            ),
            // **En una ruta completada no hay boton de guardar.** No es que este
            // apagado: no esta. Un boton apagado invita a buscar como encenderlo.
            if (!_soloLectura)
              ControlSenalado(
                nombre: Senalado.rutasGuardarElCierre,
                child: BotonPrincipal(
                  // EL GLIFO DICE CUAL DE LOS DOS GESTOS ES. Guardar lo marcado se
                  // puede repetir; guardar Y COMPLETAR cierra la ruta y la manda al
                  // historial, que no tiene vuelta. Con la papeleta de guardar en
                  // los dos, el que cierra la ruta se leeria igual que el que no.
                  icono: _completando
                      ? Icons.check_circle_outline
                      : Icons.save_outlined,
                  texto: _guardando
                      ? 'Guardando…'
                      : _completando
                      ? 'Guardar y completar'
                      // EL ROTULO DICE LAS DOS COSAS. Con una marca quitada,
                      // `Guardar 0 marcada(s)` se lee como «no hay nada que
                      // guardar» justo cuando si lo hay.
                      : _desmarcadas > 0
                      ? 'Guardar $_marcadas y quitar $_desmarcadas'
                      : 'Guardar $_marcadas marcada(s)',
                  // `_hayQueGuardar` y no `_marcadas > 0`: quitar la ultima marca
                  // apagaba el boton, asi que el desmarcado no se podia ni intentar
                  // guardar. Ver `_hayQueGuardar`.
                  alPulsar:
                      !datosListos ||
                          _guardando ||
                          (!_hayQueGuardar && !_completando)
                      ? null
                      : () => _guardar(paradas),
                ),
              ),
          ],
        ),
        cuerpo: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _soloLectura
                    ? CierreDeRuta.cabeceraSoloLectura
                    : switch (widget.modo) {
                        ModoDelCierre.marcar => CierreDeRuta.cabecera,
                        ModoDelCierre.alCompletar =>
                          CierreDeRuta.cabeceraAlCompletar,
                        ModoDelCierre.soloLectura =>
                          CierreDeRuta.cabeceraSoloLectura,
                      },
              ),
              if (!datosListos)
                Text(errorDatos?.toString() ?? 'Cargando las paradas…'),
              const SizedBox(height: 12),
              if (!_soloLectura)
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Todas:'),
                    for (final atajo in const [
                      (ResultadoParada.entregado, 'Entregado'),
                      (ResultadoParada.devuelto, 'Devuelto'),
                      (ResultadoParada.cancelado, 'Cancelado'),
                    ])
                      OutlinedButton(
                        onPressed: () => _todas(atajo.$1, paradas),
                        child: Text(atajo.$2),
                      ),
                  ],
                ),
              if (sinMarcar > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '$sinMarcar sin marcar · cuentan como que siguen en el camión',
                    style: TextStyle(color: Colores.ambar),
                  ),
                ),
              const SizedBox(height: 12),
              for (var i = 0; i < paradas.length; i++)
                _Parada(
                  // Sólo la primera parada se deja senalar por la Guia: hay tres
                  // botones por parada y pueden ser veinticinco paradas.
                  esLaPrimera: i == 0,
                  numero: paradas[i].stopOrder ?? (i + 1),
                  pedido: paradas[i],
                  resultado: _resultados[paradas[i].id],
                  nota: _nota(paradas[i].id),
                  soloLectura: _soloLectura,
                  alMarcar: (cual) => _marcar(paradas[i].id, cual),
                ),
              const SizedBox(height: 16),
              _QuedaEnElCamion(hoja: hoja),
            ],
          ),
        ),
      ),
    );
  }

  /// La hoja imprimible del post-despacho, **con lo marcado en este momento**
  /// aunque todavia no se haya guardado: es lo que quien descarga tiene en la
  /// mano mientras cuenta, y esperar a guardar seria pedirle que cuente de
  /// memoria.
  ///
  /// Aqui estaba el hueco: la cuenta y el PDF existian los dos y estaban
  /// probados, pero el boton abria una tabla en un cajon. Sin papel no hay
  /// firma del chofer de lo que volvio en el camion.
  ///
  /// La cuenta se rehace con `armarPostDespacho` de `lib/impresion/`, que es el
  /// que come la hoja: es la MISMA regla de `reglas-negocio.md` §12 que la de
  /// `datos/post_despacho.dart` —empaques con respaldo a unidades, lo sin
  /// marcar cuenta como que sigue arriba—, y las dos estan probadas contra los
  /// mismos numeros.
  void _verPostDespacho({
    required RutaConTodo? ruta,
    required List<Pedido> paradas,
    required Map<String, List<RenglonConPeso>> renglones,
  }) {
    final hoja = papel.armarPostDespacho(
      papel.DatosDeRuta(
        ruta: ruta?.ruta.routeCode ?? ruta?.ruta.name ?? widget.rutaId,
        sucursal: ruta?.sucursal?.name ?? '',
        vehiculo: ruta?.vehiculo?.name ?? '',
        // Sin salida no se escribe linea de horario, y el regreso no va solo:
        // igual que en la de Next.
        salida: ruta?.ruta.startedAt == null
            ? null
            : fechaYHora(ruta!.ruta.startedAt),
        regreso: ruta?.ruta.finishedAt == null
            ? null
            : fechaYHora(ruta!.ruta.finishedAt),
      ),
      <papel.PedidoDeRuta>[
        for (final parada in paradas)
          papel.PedidoDeRuta(
            customerName: parada.customerName,
            resultado: _resultados[parada.id],
            resultadoNota: _notas[parada.id]?.text,
            items: <papel.ItemDePedido>[
              for (final r in renglones[parada.id] ?? const <RenglonConPeso>[])
                papel.ItemDePedido(
                  description: r.renglon.description,
                  packs: r.renglon.packs,
                  quantity: r.renglon.quantity,
                ),
            ],
          ),
      ],
    );

    abrirCajon<void>(
      context,
      (contexto) => Cajon(
        titulo: 'Post-despacho',
        subtitulo:
            '${hoja.entregadas} entregadas · ${hoja.devueltas} devueltas · '
            '${hoja.canceladas} canceladas · ${hoja.sinMarcar} sin marcar',
        ancho: AnchoCajon.xl,
        // El cuerpo del cajon se desplaza, asi que no tiene alto que dar; la
        // vista previa necesita uno concreto para pintar la hoja.
        cuerpo: SizedBox(
          height: MediaQuery.sizeOf(contexto).height * 0.75,
          child: VistaPreviaPdf(
            armar: (formato) =>
                pdfPostDespacho(hoja, impresoEn: DateTime.now()),
            nombreDeFichero: 'post-despacho.pdf',
          ),
        ),
      ),
    );
  }
}

class _Parada extends StatelessWidget {
  const _Parada({
    required this.esLaPrimera,
    required this.numero,
    required this.pedido,
    required this.resultado,
    required this.nota,
    required this.soloLectura,
    required this.alMarcar,
  });

  final int numero;
  final Pedido pedido;
  final String? resultado;
  final TextEditingController nota;

  /// La ruta ya esta completada: como acabo esta parada se mira, no se toca.
  final bool soloLectura;
  final void Function(String) alMarcar;

  /// Si la Guia puede senalar los botones de resultado de ESTA parada.
  final bool esLaPrimera;

  /// Como se llama cada resultado y de que color va, en un solo sitio: la
  /// insignia de solo lectura y los tres botones decian lo mismo por separado.
  static final nombres = <String, (String, Color)>{
    ResultadoParada.entregado: ('Entregado', Colores.verde),
    ResultadoParada.devuelto: ('Devuelto', Colores.rojo),
    ResultadoParada.cancelado: ('Cancelado', Colores.gris),
  };

  /// LO QUE DICE UNA PARADA SIN MARCAR EN UNA RUTA YA CERRADA. No es «nada»:
  /// es que ese bulto volvio al almacen, que es lo que cuadra el post-despacho.
  static const sinMarcarEnCerrada = 'Sin marcar · siguió en el camión';

  @override
  Widget build(BuildContext context) {
    final pideMotivo =
        resultado == ResultadoParada.devuelto ||
        resultado == ResultadoParada.cancelado;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 14, child: Text('$numero')),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pedido.customerName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        pedido.endAddress ?? pedido.address,
                        style: TextStyle(color: Colores.gris),
                      ),
                      // El numero de operacion de la factura ES el conduce
                      // (Jose, 07/10/2026): con el se cuadra lo que baja del
                      // camion contra el papel de quien lo recibe.
                      if (pedido.operationNumber != null)
                        Text(
                          'Conduce: ${pedido.operationNumber}',
                          style: TextStyle(color: Colores.gris, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (soloLectura)
              // SIN BOTONES, NI SIQUIERA APAGADOS. En una ruta completada el
              // resultado es un dato, no una eleccion.
              Insignia(
                nombres[resultado]?.$1 ?? sinMarcarEnCerrada,
                color: nombres[resultado]?.$2 ?? Colores.ambar,
              )
            else
              Wrap(
                spacing: 8,
                children: [
                  for (final (sitio, cual) in const [
                    ResultadoParada.entregado,
                    ResultadoParada.devuelto,
                    ResultadoParada.cancelado,
                  ].indexed)
                    ControlSenalado(
                      nombre: Senalado.rutasResultadoDeLaParada,
                      // El primero de los tres, y sólo en la primera parada.
                      senalable: esLaPrimera && sitio == 0,
                      child: _BotonResultado(
                        texto: nombres[cual]!.$1,
                        color: nombres[cual]!.$2,
                        elegido: resultado == cual,
                        alPulsar: () {
                          alMarcar(cual);
                          if (esLaPrimera && sitio == 0 && resultado != cual) {
                            RegistroDeControles.completar(
                              Senalado.rutasResultadoDeLaParada,
                            );
                          }
                        },
                      ),
                    ),
                ],
              ),
            if (soloLectura) ...[
              // La nota tambien se mira: es el «por que volvio», y en una ruta
              // cerrada es la unica explicacion que queda de lo que paso.
              if (nota.text.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(nota.text.trim(), style: TextStyle(color: Colores.gris)),
              ],
            ] else if (pideMotivo) ...[
              const SizedBox(height: 8),
              TextField(
                controller: nota,
                maxLength: AccionesDeRuta.topeDeNota,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText:
                      '¿Por qué volvió? (el cliente cerró, no lo quiso, '
                      'no había nadie…)',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BotonResultado extends StatelessWidget {
  const _BotonResultado({
    required this.texto,
    required this.color,
    required this.elegido,
    required this.alPulsar,
  });

  final String texto;
  final Color color;
  final bool elegido;
  final VoidCallback alPulsar;

  /// AQUI EL COLOR NO DICE JERARQUIA, DICE QUE ESTADO ES — y por eso este grupo
  /// de tres tiene su propio par de estilos en [Botones] y no usa el principal y
  /// el secundario de siempre.
  ///
  /// «Entregado» es verde, «Devuelto» rojo y «Cancelado» gris porque son las
  /// senales de la paleta, no porque uno importe mas que otro. Lo que hay que ver
  /// de un vistazo es **cual de los tres esta marcado**.
  ///
  /// ## Se marcaba rellenando, y eso ya no se hace — 28/09/2026
  ///
  /// El elegido era el unico `FilledButton` con el fondo cambiado a mano, con su
  /// texto en blanco escrito a proposito para que se leyera encima del verde.
  /// Jose: «sin background y de colores y los bordes y iconos lo diferenciaban».
  ///
  /// Asi que ahora se marca con lo mismo con lo que se marca todo:
  ///
  ///   · **color** — el elegido va en SU color fuerte, los otros dos en tinta
  ///     suave. Antes los tres iban de color y el elegido se distinguia por el
  ///     relleno; ahora el color es del que manda;
  ///   · **borde** — 2 px del color contra 1 px del mismo color casi
  ///     transparente;
  ///   · **icono** — el elegido, y solo el elegido, lleva un visto delante. Es
  ///     lo que sostiene la lectura cuando los tres se ven pequenos, de reojo y
  ///     con sol, o cuando quien mira no separa el verde del rojo.
  ///
  /// Y con eso se va el tinte de fondo `_fondoSuave` que tenian los no elegidos
  /// (verdeFondo / rojoFondo / papel): era un fondo, y un fondo es justo lo que
  /// no puede llevar un boton. Lo que unia a los tres «como un juego de tres» y
  /// no como botones sueltos lo hace ahora el borde, que es del color de cada
  /// uno.
  @override
  Widget build(BuildContext context) {
    // El widget sigue siendo `FilledButton` cuando esta elegido y
    // `OutlinedButton` cuando no, **a proposito**: es por donde lo encuentran
    // `cierre_widget_test.dart` y `cierre_al_completar_test.dart` para saber
    // cual esta marcado, y cambiar el tipo de widget seria romper tres ficheros
    // de pruebas para no ganar nada. Lo que cambia es con que se dibuja.
    if (!elegido) {
      return OutlinedButton(
        onPressed: alPulsar,
        style: Botones.sueltoDelGrupo(color),
        child: Text(texto),
      );
    }
    return FilledButton.icon(
      onPressed: alPulsar,
      style: Botones.elegidoDelGrupo(color),
      icon: const Icon(Icons.check),
      label: Text(texto),
    );
  }
}

/// La vista previa en vivo de lo que baja del camion. Se recalcula con cada
/// marca, sin guardar nada: es la comprobacion que hace quien descarga antes de
/// firmar.
class _QuedaEnElCamion extends StatelessWidget {
  const _QuedaEnElCamion({required this.hoja});

  final HojaPostDespacho hoja;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Queda en el camión',
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      // «Sin lineas» NO es «nada queda»: un pedido sin renglones no aporta
      // ninguna, y decir que se entregó todo encima de tres paradas sin marcar
      // es el numero creible y equivocado que nadie desmiente. Ver
      // `HojaPostDespacho.seEntregoTodo`.
      if (hoja.noConstaQueQueda)
        Text(
          noConstaQueBaja(hoja.pendientes.length),
          style: Tipos.texto(tamano: 13, color: Colores.ambar, alto: 1.5),
        )
      else if (hoja.lineas.isEmpty)
        const Text('Nada: se entregó todo lo que salió.')
      else
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final linea in hoja.lineas)
              Insignia(
                '${linea.producto} ×${cantidad(linea.queda)}',
                color: Colores.ambar,
              ),
          ],
        ),
    ],
  );
}
