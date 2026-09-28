import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import 'anchos.dart';
import 'cajon.dart';
import 'colores.dart';
import 'tema.dart';

/// Una opcion del selector: etiqueta a la izquierda y **nota** pequena a la
/// derecha (un conteo, un codigo de sucursal, una tasa).
class OpcionSelector<T> {
  const OpcionSelector({
    required this.valor,
    required this.etiqueta,
    this.nota,
  });

  final T valor;
  final String etiqueta;
  final String? nota;
}

/// El desplegable del pliego (§9.6). **No es un `<select>` del sistema**: es un
/// boton que abre un menu anclado a su propio borde, con buscador **a partir de
/// 4 opciones**.
///
/// El buscador no es un adorno: el selector de vendedor del armador de rutas
/// tiene ciento y pico opciones, y en el teclado de un telefono escribir tres
/// letras es mas rapido que recorrer la lista con el dedo. Por eso se puede
/// forzar con [siempreConBuscador].
///
/// **En el telefono no es un menu: es un cajon.** Ver el comentario largo del
/// `build`, que cuenta el 28/09/2026.
class Selector<T> extends StatefulWidget {
  const Selector({
    required this.opciones,
    required this.valor,
    required this.alElegir,
    required this.etiquetaVacia,
    this.icono,
    this.desdeCuantasBusca = 4,
    this.siempreConBuscador = false,
    this.tooltip,
    super.key,
  });

  /// La opcion «todos» va **la primera** y su texto lo pone cada pantalla
  /// (`Todas las sucursales (8)`, `Todos los vehículos`), asi que entra en esta
  /// lista como una mas.
  final List<OpcionSelector<T>> opciones;
  final T? valor;
  final ValueChanged<T> alElegir;

  /// Lo que se pinta cuando `valor` no esta en la lista.
  final String etiquetaVacia;

  final IconData? icono;
  final int desdeCuantasBusca;
  final bool siempreConBuscador;
  final String? tooltip;

  @override
  State<Selector<T>> createState() => _SelectorState<T>();
}

class _SelectorState<T> extends State<Selector<T>> {
  @override
  Widget build(BuildContext context) {
    final elegida = widget.opciones
        .where((o) => o.valor == widget.valor)
        .firstOrNull;

    // Cuando hay algo elegido el borde se tine de primario y la letra se pone
    // en semibold: es como se ve en `Selector.tsx` que un filtro ESTA PUESTO
    // sin tener que leer la etiqueta entera.
    final filtrando = elegida != null;

    final conBuscador =
        widget.siempreConBuscador ||
        widget.opciones.length >= widget.desdeCuantasBusca;

    // EN EL TELÉFONO ES UN CAJÓN; EN ESCRITORIO, EL MENÚ ANCLADO DE SIEMPRE.
    //
    // Jose, 28/09/2026, con Pedidos abierto en el móvil y el calendario
    // flotando encima de la tabla:
    //
    //     «recuerda que este modal en el movil debe ser un drawer, el
    //      calendario, todo lo que salga asi como modal que sobresalga, los
    //      dropdowns creo que seria mejor ponerlos como drawer, todo eso para
    //      las opciones y queda mucho mas comodo»
    //
    // Y es la regla de la casa de Procovar —cajón en móvil, modal en
    // escritorio—, con la ✕ de cerrar que no puede desaparecer nunca.
    //
    // Un panel flotante de 448 px sobre una pantalla de 390 se sale por los dos
    // lados, se recorta contra el borde, y con el teclado abierto —el buscador
    // hace autofocus— se queda sin sitio donde pintar la lista. El cajón no
    // tiene ninguno de esos problemas: ocupa la pantalla entera, aparta el
    // teclado (ver `cajon.dart`, 17/09/2026) y trae su ✕.
    //
    // **En escritorio no se toca nada**, y es importante: el menú anclado es lo
    // que arregló el 25/09/2026 —el menú se quedaba flotando al desplazar la
    // página, ver `selector_sigue_al_boton_test.dart`— y `MenuAnchor` es lo que
    // lo sostiene. El corte sale de `Anchos.escritorio`, el mismo que ya usa
    // `Cajon` para decidir su ancho: dos números distintos para el mismo corte
    // es un teléfono ancho con media regla aplicada.
    final enElTelefono = MediaQuery.sizeOf(context).width < Anchos.escritorio;

    if (enElTelefono) {
      return _conTooltip(
        _boton(
          elegida: elegida,
          filtrando: filtrando,
          alPulsar: widget.opciones.isEmpty
              ? null
              : () => _abrirElCajon(context, conBuscador: conBuscador),
        ),
      );
    }

    // EL MENÚ VA ANCLADO AL BOTÓN, Y LO SIGUE.
    //
    // Antes esto era `showMenu`, que calcula la posición UNA SOLA VEZ al
    // abrirse —con el `RenderBox` del botón en ese instante— y deja el menú
    // clavado en la pantalla, dentro del `Overlay`. En cuanto la página se
    // desplaza, el botón se va y el menú se queda donde estaba, flotando sobre
    // cualquier cosa. Jose, 25/09/2026:
    //
    //     «los select tambien son modales no se por q se mueven en la vista si
    //      me muevo con el scrool en ves de quedarse debajo de su input select»
    //
    // Y el comentario que había encima decía «anclado al borde del boton», que
    // era verdad sólo en el instante de abrirlo. `MenuAnchor` sí lo ancla de
    // verdad: recoloca el menú en cada pasada de trazado, así que se queda
    // debajo de su botón pase lo que pase. Es además el patrón que ya usaban
    // `rango_de_fechas.dart` y el selector de Pedidos, que nunca dieron este
    // problema.
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Colores.blanco),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radios.lg),
            side: BorderSide(color: Colores.linea),
          ),
        ),
      ),
      menuChildren: [
        _Menu<T>(
          opciones: widget.opciones,
          conBuscador: conBuscador,
          valor: widget.valor,
          alElegir: (v) => widget.alElegir(v),
        ),
      ],
      builder: (contexto, controlador, _) => _conTooltip(
        _boton(
          elegida: elegida,
          filtrando: filtrando,
          alPulsar: widget.opciones.isEmpty
              ? null
              : () => controlador.isOpen
                    ? controlador.close()
                    : controlador.open(),
        ),
      ),
    );
  }

  /// El cajón del teléfono. El título es el `tooltip` cuando lo hay —es la
  /// frase larga, `Municipio del cliente`— y si no la etiqueta de «todos», que
  /// es lo único que se sabe del filtro desde aquí.
  Future<void> _abrirElCajon(
    BuildContext contexto, {
    required bool conBuscador,
  }) => abrirCajon<void>(
    contexto,
    titulo: widget.tooltip ?? widget.etiquetaVacia,
    // En móvil `Cajon` ignora este ancho y ocupa la pantalla entera; se pone el
    // más estrecho para que un escritorio estrecho —una ventana a 900 px, que
    // también entra por aquí— no se coma la pantalla por una lista de opciones.
    ancho: AnchoCajon.md,
    cuerpo: (_) => _OpcionesEnCajon<T>(
      opciones: widget.opciones,
      conBuscador: conBuscador,
      valor: widget.valor,
      alElegir: widget.alElegir,
    ),
  );

  Widget _conTooltip(Widget boton) => widget.tooltip == null
      ? boton
      : Tooltip(message: widget.tooltip!, child: boton);

  /// La caja del filtro. Es la MISMA en los dos sitios: lo único que cambia es
  /// lo que hace al pulsarla.
  Widget _boton({
    required OpcionSelector<T>? elegida,
    required bool filtrando,
    required VoidCallback? alPulsar,
  }) => OutlinedButton(
    onPressed: alPulsar,
    style: OutlinedButton.styleFrom(
      backgroundColor: Colores.blanco,
      foregroundColor: filtrando ? Colores.tinta : Colores.tintaSuave,
      side: BorderSide(
        color: filtrando
            ? Colores.primario.withValues(alpha: 0.5)
            : Colores.linea,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      textStyle: Tipos.texto(
        tamano: 14,
        peso: filtrando ? FontWeight.w600 : FontWeight.w400,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.lg),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icono != null) ...[
          Icon(widget.icono, size: 16, color: Colores.tintaSuave),
          const SizedBox(width: Aire.sm),
        ],
        Flexible(
          child: Text(
            elegida?.etiqueta ?? widget.etiquetaVacia,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // LA NOTA, EN LA CAJA, SOLO SI ES CORTA.
        //
        // En la lista la nota es todo lo larga que haga falta: ahi se esta
        // eligiendo y cuanto mas se sepa, mejor. En la CAJA es otra cosa: vive
        // dentro de una barra que tiene que caber, y una nota larga la infla y
        // empuja fuera de la pantalla lo que viene detras.
        //
        // Pasaba con la moneda: al elegir CUP, la caja pasaba a decir «CUP
        // 1 USD = 715 · del 16/9/2026» y se comia media barra. Jose, el
        // 16/09/2026: «cuando escojo la moneda ese boton se agranda mucho y me
        // jode la barra superior».
        //
        // El corte es por longitud y no por quien llama, porque el que decide
        // si cabe es el ancho, no el sitio. Las notas cortas —«HAB», «STG»—
        // son justo las que sirven de un vistazo y las que caben; una frase
        // entera se queda en la lista y en el tooltip, donde no estorba.
        if (_cabeEnLaCaja(elegida?.nota)) ...[
          const SizedBox(width: 6),
          Text(
            elegida!.nota!,
            style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
          ),
        ],
        const SizedBox(width: Aire.xs),
        Icon(Icons.keyboard_arrow_down, size: 16, color: Colores.tintaSuave),
      ],
    ),
  );
}

/// Las opciones que quedan al escribir en el buscador.
///
/// Está aquí, suelta y usada por los DOS caminos —el menú de escritorio y el
/// cajón del teléfono—, porque son el mismo filtro. Copiada dos veces, el día
/// que alguien le añada «buscar tambien por el valor» lo va a arreglar en un
/// sitio y en el otro no, y la mitad de los usuarios verá otra lista.
List<OpcionSelector<T>> _visibles<T>(
  List<OpcionSelector<T>> opciones,
  String busca,
) {
  final texto = busca.trim().toLowerCase();
  if (texto.isEmpty) return opciones;

  // LA PRIMERA OPCIÓN NO LA FILTRA EL BUSCADOR — 28/09/2026.
  //
  // La primera es siempre la de «todos» —«Cualquier vehículo», «Todos los
  // municipios», «Cualquier ubicación»—, la pone la pantalla y es la que
  // DESHACE el filtro. Se la llevaba el buscador como a cualquier otra: con
  // cuatro opciones o más sale la caja de buscar, y al escribir «PV» la lista
  // se quedaba en las que casan y **la salida desaparecía**. Entonces, para
  // quitar el filtro, hay que borrar lo escrito primero y darse cuenta de que
  // era eso — o cerrar y volver a abrir.
  //
  // No se busca por el texto «todos» ni nada parecido: se respeta la POSICIÓN,
  // que es lo único que esta pieza sabe. Quien arma las opciones decide qué va
  // primero; aquí sólo se garantiza que esa no se pierde.
  final salida = opciones.isEmpty ? null : opciones.first;
  return [
    ?salida,
    ...opciones
        .skip(1)
        .where(
          (o) =>
              o.etiqueta.toLowerCase().contains(texto) ||
              (o.nota ?? '').toLowerCase().contains(texto),
        ),
  ];
}

class _Menu<T> extends StatefulWidget {
  const _Menu({
    required this.opciones,
    required this.conBuscador,
    required this.valor,
    required this.alElegir,
  });

  final List<OpcionSelector<T>> opciones;
  final bool conBuscador;
  final T? valor;

  /// Se avisa por aqui y NO con `Navigator.pop`. El `pop` era de `showMenu`,
  /// que abria el menu como una ruta; con `MenuAnchor` el menu no es una ruta,
  /// asi que un `pop` cerraria la PANTALLA de debajo.
  final ValueChanged<T> alElegir;

  @override
  State<_Menu<T>> createState() => _MenuState<T>();
}

class _MenuState<T> extends State<_Menu<T>> {
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final visibles = _visibles(widget.opciones, _busca);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.conBuscador)
            Padding(
              padding: const EdgeInsets.all(Aire.sm),
              child: TextField(
                autofocus: true,
                style: tema.textTheme.bodyMedium,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  prefixIconConstraints: BoxConstraints(minWidth: 34),
                  hintText: 'Buscar…',
                ),
                onChanged: (v) => setState(() => _busca = v),
              ),
            ),
          if (widget.conBuscador)
            Divider(height: 1, thickness: 1, color: Colores.linea),
          // NO ES UN `ListView`, Y NO PUEDE SERLO.
          //
          // `PopupMenuItem` envuelve a su hijo en un `IntrinsicWidth` para que
          // el menu se ajuste a lo que hay dentro. Un `ListView` es un
          // `RenderShrinkWrappingViewport`, y una lista perezosa **no sabe decir
          // cuanto mide sin construir todos sus hijos**, que es precisamente lo
          // que la pereza evita. Preguntarselo lanza:
          //
          //     RenderShrinkWrappingViewport does not support returning
          //     intrinsic dimensions.
          //
          // Y eso pasaba al abrir CUALQUIER desplegable de la aplicacion: el de
          // sucursal, el de moneda, los filtros de las siete pantallas y los
          // cuatro pasos del asistente. Jose lo vio en el Tablero — el menu se
          // pintaba y elegir no hacia nada.
          //
          // `SingleChildScrollView` sobre una `Column` si sabe medirse, porque
          // su hijo es una caja normal. Y la pereza aqui no compra nada: la
          // lista mas larga es la de vendedores, ciento y pico filas de texto.
          Flexible(
            // `primary: false`: el desplazamiento de un menu es SUYO y nunca el
            // principal de la pantalla. Antes daba igual porque `showMenu`
            // abria el menu como una RUTA aparte; ahora, con `MenuAnchor`, el
            // menu vive en la misma pantalla y sin esto quedan dos
            // desplazamientos colgando del mismo `PrimaryScrollController`
            // —el del cuerpo y el del menu— y Flutter lo corta en seco: «The
            // PrimaryScrollController is attached to more than one
            // ScrollPosition». Lo mismo que ya le pasó al menu de Pedidos
            // (`pedidos/vista/kit.dart`).
            child: SingleChildScrollView(
              primary: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_hayCoincidencias(widget.opciones, _busca))
                    _NadaQueCuadre(busca: _busca),
                  for (final o in visibles)
                    _Opcion<T>(
                      opcion: o,
                      elegida: o.valor == widget.valor,
                      alElegir: widget.alElegir,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Las mismas opciones, dentro del cajón del teléfono (28/09/2026).
///
/// **Aquí no hay ningún desplazamiento propio, y es a propósito.** El cuerpo de
/// un `Cajon` YA es un `SingleChildScrollView` a alto completo, así que la lista
/// entera se desplaza sola y llega hasta el final —el caso que importa es el
/// vendedor con ciento y pico opciones, que no cabe ni de lejos—. Meter aquí
/// otro desplazable dentro de uno que crece sin límite es el error de siempre:
/// o revienta por altura infinita, o queda un panel de 360 px con su barra
/// dentro de otro, que es peor que el menú de antes.
///
/// Y por lo mismo NO hay `ConstrainedBox(maxHeight: 360)`: ese tope es del menú
/// flotante, que no puede taparlo todo. El cajón sí puede, y de eso va.
class _OpcionesEnCajon<T> extends StatefulWidget {
  const _OpcionesEnCajon({
    required this.opciones,
    required this.conBuscador,
    required this.valor,
    required this.alElegir,
  });

  final List<OpcionSelector<T>> opciones;
  final bool conBuscador;
  final T? valor;
  final ValueChanged<T> alElegir;

  @override
  State<_OpcionesEnCajon<T>> createState() => _OpcionesEnCajonState<T>();
}

class _OpcionesEnCajonState<T> extends State<_OpcionesEnCajon<T>> {
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final visibles = _visibles(widget.opciones, _busca);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.conBuscador) ...[
          TextField(
            // SIN `autofocus`, al contrario que el menú de escritorio.
            //
            // Allí el panel mide 360 px y el teclado no le quita nada, así que
            // abrir escribiendo sale gratis. Aquí el cajón es la pantalla
            // entera y el teclado del teléfono se come la mitad: abrirlo sin
            // que nadie lo haya pedido tapa justo las opciones que se venían a
            // mirar. Quien quiera buscar toca la caja; quien venga a tocar
            // «Todos los municipios» lo ve sin pelear con el teclado.
            style: tema.textTheme.bodyMedium,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              prefixIconConstraints: BoxConstraints(minWidth: 34),
              hintText: 'Buscar…',
            ),
            onChanged: (v) => setState(() => _busca = v),
          ),
          const SizedBox(height: Aire.sm),
        ],
        if (!_hayCoincidencias(widget.opciones, _busca))
          _NadaQueCuadre(busca: _busca),
        for (final o in visibles)
          _Opcion<T>(
            opcion: o,
            elegida: o.valor == widget.valor,
            alElegir: widget.alElegir,
            // El cajón SÍ es una ruta —`showGeneralDialog`—, así que aquí el
            // `Navigator` es lo correcto y no se lleva la pantalla de debajo.
            // Es justo lo contrario del menú: ver `_Opcion.alCerrar`.
            alCerrar: () => Navigator.of(context).maybePop(),
            // Con el dedo, no con el ratón: 9 px arriba y abajo dejan una fila
            // de 38 px y se falla el toque. Con 14 la fila pasa de 48.
            aireVertical: 14,
          ),
      ],
    );
  }
}

/// El cartel de cuando el buscador no deja nada. Uno solo para los dos sitios.
/// SI EL BUSCADOR NO ENCONTRÓ NADA, y es distinto de «la lista está vacía».
///
/// Desde que la primera opción —la de «todos»— no la filtra el buscador, la
/// lista NUNCA se queda vacía: siempre queda al menos la salida. Si el aviso de
/// «nada que cuadre» se decidiera mirando si la lista está vacía, dejaría de
/// salir para siempre, y quien escribe «pv-stgoo» con una letra de más se
/// quedaría mirando una sola opción sin entender por qué.
///
/// Lo que se pregunta es si cuadró alguna de las BUSCABLES, que son todas menos
/// la primera.
bool _hayCoincidencias<T>(List<OpcionSelector<T>> opciones, String busca) {
  final texto = busca.trim().toLowerCase();
  if (texto.isEmpty) return true;
  return opciones
      .skip(1)
      .any(
        (o) =>
            o.etiqueta.toLowerCase().contains(texto) ||
            (o.nota ?? '').toLowerCase().contains(texto),
      );
}

class _NadaQueCuadre extends StatelessWidget {
  const _NadaQueCuadre({required this.busca});

  final String busca;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Aire.lg),
    child: Text(
      'Nada que cuadre con «$busca»',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Colores.tintaSuave),
    ),
  );
}

/// Una fila del menu. La elegida va en primario y con la marca a la derecha,
/// como en `Selector.tsx`; el resto en tinta.
class _Opcion<T> extends StatelessWidget {
  const _Opcion({
    required this.opcion,
    required this.elegida,
    required this.alElegir,
    this.alCerrar,
    this.aireVertical = 9,
  });

  final OpcionSelector<T> opcion;
  final bool elegida;
  final ValueChanged<T> alElegir;

  /// Quién cierra lo que está abierto, que **no es lo mismo en los dos sitios**
  /// y confundirlos ya costó un día:
  ///
  /// - en el menú de escritorio lo cierra su `MenuController`, porque el menú
  ///   NO es una ruta y un `Navigator.pop` cerraría la pantalla de debajo
  ///   (25/09/2026, `los_menus_no_cierran_la_pantalla_test.dart`);
  /// - en el cajón del teléfono sí es una ruta, y se cierra con el `Navigator`.
  ///
  /// `null` deja el comportamiento del menú, que es el que ya estaba probado.
  final VoidCallback? alCerrar;

  /// El aire de arriba y abajo de la fila. En el cajón es mayor porque ahí se
  /// toca con el dedo.
  final double aireVertical;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () {
      // Primero se avisa y luego se cierra: cerrar antes desmonta este
      // `State` y el aviso se perderia.
      alElegir(opcion.valor);
      final cerrar = alCerrar;
      if (cerrar != null) {
        cerrar();
      } else {
        MenuController.maybeOf(context)?.close();
      }
    },
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: aireVertical),
      child: Row(
        children: [
          Expanded(
            child: Text(
              opcion.etiqueta,
              overflow: TextOverflow.ellipsis,
              style: Tipos.texto(
                tamano: 14,
                peso: elegida ? FontWeight.w600 : FontWeight.w400,
                color: elegida ? Colores.primario : Colores.tinta,
              ),
            ),
          ),
          if (opcion.nota != null) ...[
            const SizedBox(width: Aire.sm),
            Text(
              opcion.nota!,
              style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
            ),
          ],
          if (elegida) ...[
            const SizedBox(width: Aire.sm),
            Icon(Icons.check, size: 16, color: Colores.primario),
          ],
        ],
      ),
    ),
  );
}

/// Cuantos caracteres de nota caben al lado de la etiqueta sin inflar la caja.
///
/// Doce es lo que mide «HAB» con sitio de sobra y lo que NO mide una frase. El
/// numero esta aqui y no repartido para que cambiarlo sea un sitio.
const int _notaCortaEnLaCaja = 12;

bool _cabeEnLaCaja(String? nota) =>
    nota != null && nota.trim().length <= _notaCortaEnLaCaja;
