/// EL RECORRIDO GUIADO: un paso cada vez, SENALANDO el control, encima de la
/// aplicacion de verdad.
///
/// ## Lo que vino a arreglar, con las palabras de Jose — 05/10/2026
///
/// La 1.0.22 llevaba la Guia con sus tareas y su boton de «Ir a ‹pantalla›». La
/// probo y la rechazo entera:
///
/// > «me pusiste las tareas pero las tareas no me mueven a ningún lugar
/// > enseñándome cómo debería trabajar en tiempo real, como un vídeo, diciéndome
/// > paso a paso qué hace cada cosa en la aplicación»
/// > «todo me lo pusiste como documento, nada de q me llevara o me enseñara… o q
/// > me enseñara en la misma aplicación»
/// > «las cosas q tienen botones me mueven a la página pero no me dice paso a
/// > paso con sus tooltips señalándome paso a paso en la aplicación cada botón q
/// > debo tocar en cada tarea con sus pasos»
/// > «q las tareas enseñen algo de verdad no mierda textual q la gente no quiere
/// > leer quiere q le enseñes donde ir donde tocar para cada cosa»
///
/// Las cuatro dicen lo mismo con mas rabia cada vez: **el texto no es el
/// producto.** El producto es el foco encima del boton, con la nota al lado y un
/// «Siguiente» que lleva al que viene.
///
/// ## Las cuatro condiciones, y como las cumple
///
///  1. **El control se tiene que VER.** La tarjeta del paso se coloca al otro lado
///     del control —si el control esta arriba, la tarjeta abajo, y al reves—, y
///     antes de senalarlo se le lleva a la vista con `Scrollable.ensureVisible`.
///     Senalar algo que esta fuera de la pantalla es no senalar nada.
///  2. **Un paso cada vez**, con «Atrás» y «Siguiente», y «3 de 7». Eso es lo que
///     lo hace un recorrido y no un muro de texto.
///  3. **Se sale cuando quiera.** «Salir» quita la capa y no toca nada mas: se
///     queda en la pantalla en la que estaba, que es la de la tarea. Lo que no
///     hace es deshacer la navegacion, porque nadie quiere que al salir de la
///     explicacion de Vehiculos le devuelvan a la Guia.
///  4. **Lo que no se puede senalar se dice.** Un paso cuyo control no esta
///     marcado —o esta montado dos veces, o es un paso que no se hace en esta
///     pantalla— sale **sin foco y con el motivo escrito**. Nunca apunta a un
///     sitio cualquiera: un recorrido que senala el boton equivocado es peor que
///     uno que no senala.
///
/// ## Lo que NO hace, y es una decision
///
/// No bloquea el control senalado: el agujero del velo **deja pasar el dedo**.
/// Jose va a seguir el recorrido tocando de verdad, no mirandolo. Lo que el velo
/// absorbe es todo lo de alrededor, y eso ademas tiene un efecto que hacia falta:
/// con el resto de la pantalla sordo, nadie puede desplazar la lista por debajo
/// del foco y dejar el anillo senalando un hueco.
///
/// ## Donde vive la capa
///
/// En el `Overlay` **de la raiz**, no en el de la pantalla. Asi sobrevive al
/// `context.go` que lleva a la pantalla de la tarea: si viviera dentro de la
/// pantalla, se iria con ella justo al empezar. Y por eso esto no necesita tocar
/// `navegacion/`: el `Overlay` de la raiz ya existe, lo pone `MaterialApp.router`.
library;

import 'package:flutter/material.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../datos/manual.dart';
import 'control_senalado.dart';
import 'demostracion_del_gesto.dart';
import 'pintar_markdown.dart';

/// Los literales del recorrido, en un sitio: los usan la capa y sus pruebas.
abstract final class TextosDelRecorrido {
  static const empezar = 'Guiarme paso a paso';
  static const siguiente = 'Siguiente';
  static const atras = 'Atrás';
  static const salir = 'Salir';
  static const acabar = 'Ya está';

  static String cualDeCuantos(int cual, int deCuantos) => '$cual de $deCuantos';

  /// CUANDO UN PASO NO SE PUEDE SENALAR. **Dice el por que**, que es la regla:
  /// un paso mudo parece un fallo de la aplicacion, y entonces nadie se fia del
  /// resto del recorrido.
  static const sinControlMarcado =
      'Este paso todavía no tiene su botón marcado en la pantalla, así que no se '
      'puede señalar. Lo que hay que tocar está escrito arriba.';

  /// Cuando el paso SÍ nombra un control y el control no aparece. Son tres casos
  /// —no está marcado, no es de esta pantalla, o está dos veces y no se puede
  /// distinguir— y se cuentan igual porque la consecuencia es la misma: aquí no se
  /// puede poner el foco. **Lo que no se hace es ponerlo en otro sitio.**
  static const controlFueraDeEstaPantalla =
      'Esto no se puede señalar aquí: el control de este paso no está en esta '
      'pantalla, o todavía no está marcado. Lo que hay que tocar está escrito '
      'arriba.';

  /// Cuando la tarea entera no se puede guiar.
  static String noSePuedeGuiar(String titulo) =>
      'A «$titulo» no se le puede hacer un recorrido: el manual no la cuenta en '
      'pasos numerados. El texto completo está aquí debajo y dice lo mismo.';

  static String noEsDeEstaForma(String pantalla) =>
      'A esta tarea no se le puede hacer un recorrido aquí: se hace en '
      '«$pantalla», que en esta forma de la aplicación no existe. El texto se '
      'queda por si te toca en otra.';
}

abstract final class ClavesDelRecorrido {
  static const capa = ValueKey('recorrido-capa');
  static const siguiente = ValueKey('recorrido-siguiente');
  static const atras = ValueKey('recorrido-atras');
  static const salir = ValueKey('recorrido-salir');
  static const foco = ValueKey('recorrido-foco');

  /// LA TARJETA ENTERA. Hace falta aparte del boton: para medir si la tarjeta tapa
  /// lo que senala hay que medir LA TARJETA, y midiendo el boton de «Siguiente» —que
  /// esta a la derecha— una tarjeta puesta justo encima de un control de la
  /// izquierda no se solapa con el y la prueba sale verde. Medido el 05/10/2026.
  static const tarjeta = ValueKey('recorrido-tarjeta');
  static const empezar = ValueKey('recorrido-empezar');
}

/// EL MANDO DEL RECORRIDO. Uno a la vez, y por eso es estatico.
///
/// Dos recorridos encima de la misma pantalla serian dos focos y dos
/// «Siguiente»: [empezar] cierra el que hubiera antes de abrir el nuevo.
abstract final class Recorrido {
  static OverlayEntry? _capa;

  /// `true` mientras hay un recorrido puesto. Lo mira la Guia para no abrir dos.
  static bool get enMarcha => _capa != null;

  /// Arranca el recorrido de [tarea] sobre la pantalla que ya esta delante.
  ///
  /// Quien llama es el que navega: la Guia cierra su cajon, hace el `context.go`
  /// a la pantalla de la tarea y **despues** llama aqui. El orden importa: la capa
  /// mide los controles de la pantalla que hay, asi que tiene que empezar con la
  /// pantalla buena ya puesta.
  ///
  /// Recibe el [OverlayState] ya resuelto y no un `BuildContext`, y es el detalle
  /// que lo hace funcionar: quien llama lo resuelve **antes** de navegar, porque
  /// despues su propio contexto esta en camino de desaparecer.
  static void empezarEn(OverlayState capa, TareaDelManual tarea) {
    salir();
    if (!capa.mounted) return;
    final entrada = OverlayEntry(
      builder: (_) => CapaDelRecorrido(tarea: tarea, alSalir: salir),
    );
    _capa = entrada;
    capa.insert(entrada);
  }

  /// Quita la capa. No deshace la navegacion y no toca ningun dato: al salir, la
  /// aplicacion se queda exactamente donde estaba, con la pantalla de la tarea
  /// delante.
  static void salir() {
    _capa?.remove();
    _capa = null;
  }
}

/// LA CAPA: el velo con su agujero, el anillo y la tarjeta del paso.
///
/// Publica porque las pruebas la montan sola, sin `Overlay`: asi se puede
/// comprobar que un paso sin control marcado lo dice, sin arrastrar un enrutador.
class CapaDelRecorrido extends StatefulWidget {
  const CapaDelRecorrido({
    required this.tarea,
    required this.alSalir,
    super.key = ClavesDelRecorrido.capa,
  });

  final TareaDelManual tarea;
  final VoidCallback alSalir;

  @override
  State<CapaDelRecorrido> createState() => _CapaDelRecorridoState();
}

class _CapaDelRecorridoState extends State<CapaDelRecorrido> {
  int _cual = 0;
  int _repeticion = 0;

  /// Un arrastre necesita abiertos el origen y el destino en el mismo paso.
  List<Rect> _focos = const [];

  PasoGuiado get _paso => widget.tarea.pasos[_cual];

  @override
  void initState() {
    super.initState();
    _colocar();
  }

  /// LLEVA EL CONTROL A LA VISTA Y LO MIDE, en ese orden.
  ///
  /// Las dos mitades: `ensureVisible` desplaza la lista hasta que el control esta
  /// dentro, y la medida se toma **despues** de que el desplazamiento acabe. Al
  /// reves —medir y luego desplazar— el anillo se queda en el sitio de antes y
  /// senala un hueco, que es el fallo que mas se nota de los dos.
  Future<void> _colocar() async {
    final nombres = _paso.controles;
    if (nombres.isEmpty) {
      if (mounted) setState(() => _focos = const []);
      return;
    }

    // SE LE DAN UNOS FOTOGRAMAS A LA PANTALLA ANTES DE DECIR QUE NO ESTA.
    //
    // El recorrido empieza justo despues del `context.go`: ese fotograma la
    // pantalla nueva todavia no existe, y el siguiente la lista aun esta
    // pintandose. Preguntar una sola vez daria «este paso no se puede senalar»
    // sobre un boton que aparece dos fotogramas despues — un aviso falso, que es
    // peor que no avisar.
    //
    // El tope existe para que lo contrario tampoco pase: un control que de verdad
    // no esta no puede dejar la tarjeta esperando para siempre.
    var puestos = [
      for (final nombre in nombres) RegistroDeControles.donde(nombre),
    ];
    for (
      var intento = 0;
      puestos.any((p) => p == null) && intento < _fotogramasDeEspera;
      intento++
    ) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      puestos = [
        for (final nombre in nombres) RegistroDeControles.donde(nombre),
      ];
    }
    if (puestos.any((p) => p == null)) {
      setState(() => _focos = const []);
      return;
    }

    // `ensureVisible` revienta si el contexto no esta dentro de un `Scrollable`,
    // y hay controles que no lo estan (la franja de arriba, la barra). Eso no es
    // un fallo: es que no hay nada que desplazar.
    for (final ubicado in puestos) {
      final puesto = ubicado!;
      if (Scrollable.maybeOf(puesto.contexto) != null) {
        await Scrollable.ensureVisible(
          puesto.contexto,
          // Se mide todo después del último desplazamiento: mover el destino
          // también puede mover el origen del arrastre.
          alignment: 0.5,
          duration: const Duration(milliseconds: 220),
        );
        if (!mounted) return;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
    }

    // Se vuelve a preguntar: el desplazamiento movio el control, y la medida de
    // antes ya no vale.
    final medidos = [
      for (final nombre in nombres) RegistroDeControles.donde(nombre)?.rect,
    ];
    setState(() {
      _focos = medidos.any((r) => r == null) ? const [] : medidos.cast<Rect>();
    });
  }

  void _ir(int aCual) {
    setState(() {
      _cual = aCual;
      _focos = const [];
    });
    _colocar();
  }

  @override
  Widget build(BuildContext context) {
    final pantalla = MediaQuery.sizeOf(context);
    final huecos = [
      for (final foco in _focos)
        _dentroDe(foco.inflate(_aireDelFoco), pantalla),
    ].where((r) => !r.isEmpty).toList();
    final seVeCompleto =
        huecos.length == _paso.controles.length && huecos.isNotEmpty;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // EL VELO SE RECORTA ALREDEDOR DE TODOS LOS CONTROLES DEL GESTO.
          //
          // Rectangulos y no un `CustomPainter` con un `Path` recortado, y
          // es la decision que hace que el dedo pase por el agujero: un pintor
          // dibuja el agujero pero **sigue recibiendo el toque**, asi que habria
          // que escribir un `hitTest` a mano para dejarlo pasar. Con los
          // trozos, cada agujero es un sitio donde no
          // hay widget ninguno.
          ..._velo(pantalla, huecos),
          for (final hueco in huecos) _anillo(hueco),
          if (seVeCompleto)
            DemostracionDelGesto(
              key: ValueKey('gesto-$_cual-$_repeticion'),
              focos: huecos,
            ),
          _tarjeta(pantalla, huecos, seVeCompleto),
        ],
      ),
    );
  }

  /// Se resta cada agujero del velo. El destino recibe el arrastre aunque el
  /// ratón haya cruzado una parte cubierta; el resto sigue absorbiendo toques.
  List<Widget> _velo(Size pantalla, List<Rect> huecos) {
    var partes = [Offset.zero & pantalla];
    for (final hueco in huecos) {
      final siguientes = <Rect>[];
      for (final parte in partes) {
        final corte = parte.intersect(hueco);
        if (corte.isEmpty) {
          siguientes.add(parte);
          continue;
        }
        siguientes.addAll(
          [
            Rect.fromLTRB(parte.left, parte.top, parte.right, corte.top),
            Rect.fromLTRB(parte.left, corte.bottom, parte.right, parte.bottom),
            Rect.fromLTRB(parte.left, corte.top, corte.left, corte.bottom),
            Rect.fromLTRB(corte.right, corte.top, parte.right, corte.bottom),
          ].where((r) => !r.isEmpty),
        );
      }
      partes = siguientes;
    }
    return [
      for (final parte in partes)
        Positioned.fromRect(
          rect: parte,
          child: AbsorbPointer(
            child: ColoredBox(color: Colores.veloDelRecorrido),
          ),
        ),
    ];
  }

  /// EL ANILLO va **fuera** del control. La mano sólo aparece durante el gesto.
  /// Un borde pintado encima taparia la mitad del icono del boton
  /// que se esta senalando.
  Widget _anillo(Rect hueco) => Positioned.fromRect(
    rect: hueco,
    child: IgnorePointer(
      child: DecoratedBox(
        key: ClavesDelRecorrido.foco,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radios.lg),
          border: Border.all(color: Colores.marca, width: 2.5),
        ),
      ),
    ),
  );

  /// LA TARJETA DEL PASO, al otro lado del control.
  Widget _tarjeta(Size pantalla, List<Rect> huecos, bool seVeCompleto) {
    // Si el control esta en la mitad de arriba, la tarjeta abajo; si no, arriba.
    // Sin esto, la tarjeta tapa justo lo que esta senalando — que es el fallo que
    // hace inutil un recorrido entero.
    final conjunto = huecos.isEmpty
        ? null
        : huecos.reduce((a, b) => a.expandToInclude(b));
    final abajo = conjunto == null || conjunto.center.dy < pantalla.height / 2;

    return Positioned(
      left: Aire.md,
      right: Aire.md,
      top: abajo ? null : Aire.md,
      bottom: abajo ? Aire.md : null,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Anchos.idioma),
            child: _Tarjeta(
              tarea: widget.tarea,
              paso: _paso,
              seSenala: seVeCompleto,
              alSalir: widget.alSalir,
              alRepetir:
                  !MediaQuery.disableAnimationsOf(context) && seVeCompleto
                  ? () => setState(() => _repeticion++)
                  : null,
              alAtras: _cual == 0 ? null : () => _ir(_cual - 1),
              alSiguiente: _cual + 1 >= widget.tarea.pasos.length
                  ? null
                  : () => _ir(_cual + 1),
            ),
          ),
        ),
      ),
    );
  }

  /// El agujero, recortado a la pantalla. Un control pegado al borde deja un
  /// rectangulo que se sale, y un `Positioned` con un ancho negativo revienta.
  Rect _dentroDe(Rect cual, Size pantalla) => Rect.fromLTRB(
    cual.left.clamp(0.0, pantalla.width),
    cual.top.clamp(0.0, pantalla.height),
    cual.right.clamp(0.0, pantalla.width),
    cual.bottom.clamp(0.0, pantalla.height),
  );
}

/// El aire entre el control y el anillo.
const _aireDelFoco = 6.0;

/// Cuantos fotogramas se espera a que el control aparezca antes de decir que no
/// esta. A 60 Hz son ~250 ms, que es lo que tarda una pantalla en montarse con su
/// lista. Mas seria una tarjeta que se queda muda sin motivo.
const _fotogramasDeEspera = 15;

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.tarea,
    required this.paso,
    required this.seSenala,
    required this.alSalir,
    required this.alRepetir,
    required this.alAtras,
    required this.alSiguiente,
  });

  final TareaDelManual tarea;
  final PasoGuiado paso;
  final bool seSenala;
  final VoidCallback alSalir;
  final VoidCallback? alRepetir;
  final VoidCallback? alAtras;
  final VoidCallback? alSiguiente;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: ClavesDelRecorrido.tarjeta,
    decoration: BoxDecoration(
      color: Colores.blanco,
      borderRadius: BorderRadius.circular(Radios.xl),
      border: Border.all(color: Colores.marca, width: 1.4),
      boxShadow: Sombras.lg,
    ),
    child: Padding(
      padding: const EdgeInsets.all(Aire.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                TextosDelRecorrido.cualDeCuantos(paso.cual, paso.deCuantos),
                style: Tipos.mono(
                  tamano: 12,
                  peso: FontWeight.w700,
                  color: Colores.primario,
                ),
              ),
              const SizedBox(width: Aire.sm),
              Expanded(
                child: Text(
                  tarea.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tipos.texto(
                    tamano: 11.5,
                    peso: FontWeight.w600,
                    color: Colores.tintaSuave,
                    interletra: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Aire.sm),
          // Sin enlaces: un enlace dentro de la tarjeta de un paso se lleva a
          // otra pagina del manual y deja el recorrido a medias encima de una
          // pantalla que ya no es la de la tarea.
          RenglonDelManual(paso.texto, enlaces: EnlacesDelManual.sinEnlaces),
          for (final detalle in paso.detalles)
            Padding(
              padding: const EdgeInsets.only(top: Aire.xs, left: Aire.md),
              child: RenglonDelManual(
                detalle,
                enlaces: EnlacesDelManual.sinEnlaces,
              ),
            ),
          if (!seSenala)
            Padding(
              padding: const EdgeInsets.only(top: Aire.sm),
              child: Text(
                paso.seSenala
                    ? TextosDelRecorrido.controlFueraDeEstaPantalla
                    : TextosDelRecorrido.sinControlMarcado,
                style: Tipos.texto(
                  tamano: 12.5,
                  color: Colores.tintaSuave,
                  alto: 1.4,
                ),
              ),
            ),
          const SizedBox(height: Aire.md),
          if (alRepetir != null)
            TextButton.icon(
              onPressed: alRepetir,
              icon: const Icon(Icons.replay, size: 17),
              label: const Text('Ver el gesto otra vez'),
            ),
          Row(
            children: [
              // «Salir» a la izquierda y sin peso: esta siempre, y no es lo que
              // se viene a pulsar.
              TextButton.icon(
                key: ClavesDelRecorrido.salir,
                onPressed: alSalir,
                icon: const Icon(Icons.close, size: 17),
                label: const Text(TextosDelRecorrido.salir),
              ),
              const Spacer(),
              if (alAtras != null)
                OutlinedButton.icon(
                  key: ClavesDelRecorrido.atras,
                  onPressed: alAtras,
                  icon: const Icon(Icons.arrow_back, size: 17),
                  label: const Text(TextosDelRecorrido.atras),
                ),
              const SizedBox(width: Aire.sm),
              // El ultimo paso no lleva «Siguiente»: lleva «Ya está», que cierra.
              // Un «Siguiente» apagado en el ultimo paso deja a alguien pulsando
              // un boton muerto sin saber que ya acabo.
              Flexible(
                child: BotonPrincipal(
                  key: ClavesDelRecorrido.siguiente,
                  texto: alSiguiente == null
                      ? TextosDelRecorrido.acabar
                      : TextosDelRecorrido.siguiente,
                  icono: alSiguiente == null
                      ? Icons.check
                      : Icons.arrow_forward,
                  iconoAlFinal: true,
                  enUnaLinea: true,
                  alPulsar: alSiguiente ?? alSalir,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
