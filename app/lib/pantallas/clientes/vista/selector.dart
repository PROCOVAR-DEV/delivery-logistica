import 'package:flutter/material.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/cajon.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';

/// Una opcion de un selector: etiqueta y una **nota** pequena a la derecha (un
/// conteo, un codigo).
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

/// El `Selector` del pliego (`pantallas.md` §9.6): **no es un desplegable del
/// sistema**, es un boton que abre un menu anclado a su borde, con buscador a
/// partir de 4 opciones.
///
/// El buscador desde 4 no es capricho: en el telefono, con el teclado abierto,
/// una lista de municipios es mas rapida escribiendo que arrastrando.
///
/// **En el telefono no es un menu: es un cajon.** Ver el comentario largo del
/// `build`, que cuenta el 28/09/2026.
///
/// POR QUÉ ESTO NO ES EL `Selector` DE `lib/diseno/`, QUE SERÍA MEJOR.
///
/// Se miró, y sería una pieza en vez de tres. No se puede **sin tocar
/// `pantalla_clientes.dart`**, y ahí hay tres cosas que el común no sabe hacer:
///
///  1. El **rótulo de encima** («MUNICIPIO DEL CLIENTE», en 10 px y semibold).
///     El común no tiene rótulo: su `tooltip` sale al pasar el ratón, y en un
///     teléfono no hay ratón. Con seis filtros en fila, quitar los rótulos deja
///     seis cajas que dicen «Todos los…» y no se sabe de qué.
///  2. El `alElegir` de aquí es `ValueChanged<T?>` y **avisa con `null`** para
///     «todos»; el del común es `ValueChanged<T>` y espera que «todos» sea una
///     opción más de la lista, con su propio valor. Las seis llamadas de
///     Clientes están escritas sobre la primera forma (`filtros.copiar(
///     municipio: v)` con `v` nulo para quitar el filtro).
///  3. Aquí el «todos» **no lo filtra el buscador nunca**: es la salida de
///     vuelta. En el común es una opción más y escribir tres letras la esconde.
///
/// Unificar es un buen cambio, pero es otro: toca las seis llamadas de
/// `pantalla_clientes.dart`, y el común tendría que aprender el rótulo y el
/// «todos» que no se filtra. Mientras tanto, lo que sí se comparte es **el
/// comportamiento**: el mismo corte en `Anchos.escritorio` y el mismo `Cajon`
/// de `lib/diseno/`, que es lo que ve Jose.
class SelectorFiltro<T> extends StatelessWidget {
  const SelectorFiltro({
    required this.titulo,
    required this.textoTodos,
    required this.opciones,
    required this.valor,
    required this.alElegir,
    this.icono,
    this.desdeCuantasBusca = 4,
    super.key,
  });

  final String titulo;

  /// El texto de la opcion «todos», que lo pone cada pantalla. Va siempre la
  /// primera.
  final String textoTodos;
  final List<OpcionSelector<T>> opciones;
  final T? valor;
  final ValueChanged<T?> alElegir;
  final IconData? icono;
  final int desdeCuantasBusca;

  @override
  Widget build(BuildContext context) {
    final elegida = opciones.where((o) => o.valor == valor).firstOrNull;
    // Con algo elegido el borde se tine de primario y la letra se pone en
    // semibold, igual que en `lib/diseno/selector.dart`: asi se ve de un vistazo
    // cuales de los seis filtros estan puestos.
    final filtrando = elegida != null;
    final conBuscador = opciones.length >= desdeCuantasBusca;

    // EN EL TELÉFONO ES UN CAJÓN; EN ESCRITORIO, EL MENÚ ANCLADO DE SIEMPRE.
    //
    // Jose, 28/09/2026, con la aplicación abierta en el móvil:
    //
    //     «recuerda que este modal en el movil debe ser un drawer, el
    //      calendario, todo lo que salga asi como modal que sobresalga, los
    //      dropdowns creo que seria mejor ponerlos como drawer, todo eso para
    //      las opciones y queda mucho mas comodo»
    //
    // Dijo «los dropdowns», en plural, y en la aplicación son CUATRO: el común
    // de `lib/diseno/selector.dart`, el calendario de `rango_de_fechas.dart`,
    // éste y el de `pedidos/vista/kit.dart`. Los dos primeros se pasaron a
    // cajón ese mismo día; éste seguía siendo menú a cualquier ancho, y un
    // filtro que se comporta distinto según la pantalla en la que estés es
    // peor que los cuatro mal igual.
    //
    // Aquí el panel del menú mide 280 px de ancho y hasta 360 de alto, y se
    // abre anclado a un botón que vive en una barra de SEIS filtros: en un
    // teléfono de 390 px, los de la derecha abren su panel pegado al borde y
    // con el teclado del buscador encima no queda sitio para la lista de
    // municipios, que es la larga (La Habana tiene quince). El cajón ocupa la
    // pantalla entera, aparta el teclado y trae su ✕.
    //
    // **En escritorio no se toca nada**: el menú anclado es lo que arregló el
    // 25/09/2026 —al desplazar la lista de clientes el menú se quedaba
    // flotando— y `MenuAnchor` es lo que lo sostiene.
    //
    // El corte es `Anchos.escritorio` y NO «cajón siempre», aunque §4 del
    // CLAUDE.md lo permitiría en este proyecto: los otros dos desplegables ya
    // cortan ahí, y cuatro piezas que hacen lo mismo tienen que cortar por el
    // mismo sitio o alguien arregla una y deja tres.
    final enElTelefono = MediaQuery.sizeOf(context).width < Anchos.escritorio;

    if (enElTelefono) {
      return _caja(
        elegida: elegida,
        filtrando: filtrando,
        alPulsar: () => _abrirElCajon(context, conBuscador: conBuscador),
      );
    }

    // EL MENÚ VA ANCLADO AL BOTÓN, Y LO SIGUE.
    //
    // Era `showMenu`, que fija la posición una sola vez al abrirse y deja el
    // menú clavado en el `Overlay`: al desplazar la lista de clientes el botón
    // se iba y el menú se quedaba flotando. Jose, 25/09/2026: «los select
    // también son modales, se mueven en la vista si me muevo con el scroll en
    // vez de quedarse debajo de su input». El mismo arreglo y el mismo motivo
    // que en `lib/diseno/selector.dart`, atado allí por
    // `test/diseno/selector_sigue_al_boton_test.dart`.
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
          textoTodos: textoTodos,
          opciones: opciones,
          conBuscador: conBuscador,
          alElegir: alElegir,
        ),
      ],
      builder: (contexto, controlador, _) => _caja(
        elegida: elegida,
        filtrando: filtrando,
        alPulsar: () =>
            controlador.isOpen ? controlador.close() : controlador.open(),
      ),
    );
  }

  /// El cajón del teléfono. Lo titula el [titulo] del filtro —«Municipio del
  /// cliente»—, que es justo el rótulo que en escritorio se lee encima del
  /// botón y que dentro del cajón ya no se ve.
  Future<void> _abrirElCajon(
    BuildContext contexto, {
    required bool conBuscador,
  }) => abrirCajon<void>(
    contexto,
    titulo: titulo,
    // En móvil `Cajon` ignora este ancho y ocupa la pantalla entera; se pone el
    // más estrecho para que un escritorio estrecho —una ventana a 900 px, que
    // también entra por aquí— no se coma la pantalla por seis municipios.
    ancho: AnchoCajon.md,
    cuerpo: (_) => _OpcionesEnCajon<T>(
      textoTodos: textoTodos,
      opciones: opciones,
      conBuscador: conBuscador,
      alElegir: alElegir,
    ),
  );

  /// El rótulo y su caja. Es LO MISMO en los dos sitios: lo único que cambia es
  /// lo que hace al pulsarla. Estaba escrito dentro del `builder` del
  /// `MenuAnchor`, y ahí sólo lo podía usar el escritorio.
  Widget _caja({
    required OpcionSelector<T>? elegida,
    required bool filtrando,
    required VoidCallback alPulsar,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        titulo,
        style: Tipos.texto(
          tamano: 10,
          peso: FontWeight.w600,
          color: Colores.tintaSuave.withValues(alpha: 0.75),
          interletra: 0.4,
        ),
      ),
      const SizedBox(height: 5),
      OutlinedButton(
        onPressed: alPulsar,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colores.blanco,
          foregroundColor: filtrando ? Colores.tinta : Colores.tintaSuave,
          side: BorderSide(
            color: filtrando
                ? Colores.primario.withValues(alpha: 0.5)
                : Colores.linea,
          ),
          padding: const EdgeInsets.symmetric(horizontal: Aire.md, vertical: 9),
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
            Icon(
              icono ?? Icons.filter_list,
              size: 16,
              color: Colores.tintaSuave,
            ),
            const SizedBox(width: Aire.sm),
            Flexible(
              child: Text(
                elegida?.etiqueta ?? textoTodos,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Aire.xs),
            Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: Colores.tintaSuave,
            ),
          ],
        ),
      ),
    ],
  );
}

/// Las opciones que quedan al escribir en el buscador.
///
/// Suelta y usada por los DOS caminos —el menú de escritorio y el cajón del
/// teléfono—, porque son el mismo filtro. Copiada dos veces, el día que alguien
/// le añada «buscar también por la nota» —que es lo que ya hace el de
/// `pedidos/vista/kit.dart`— lo arreglaría en un sitio y en el otro no, y la
/// mitad de los usuarios vería otra lista.
///
/// El «todos» NO entra aquí: va suelto y siempre el primero, porque es la
/// salida de vuelta y esconderla al escribir tres letras deja al filtro sin
/// forma de quitarse.
List<OpcionSelector<T>> _visibles<T>(
  List<OpcionSelector<T>> opciones,
  String busca,
) {
  final texto = busca.trim().toLowerCase();
  if (texto.isEmpty) return opciones;
  return opciones
      .where((o) => o.etiqueta.toLowerCase().contains(texto))
      .toList();
}

class _Menu<T> extends StatefulWidget {
  const _Menu({
    required this.textoTodos,
    required this.opciones,
    required this.conBuscador,
    required this.alElegir,
  });

  final String textoTodos;
  final List<OpcionSelector<T>> opciones;
  final bool conBuscador;

  /// Se avisa por aqui y NO con `Navigator.pop`. El `pop` era de `showMenu`,
  /// que abria el menu como una ruta aparte; con `MenuAnchor` el menu vive en
  /// la misma pantalla y un `pop` cerraria la pantalla de debajo.
  final ValueChanged<T?> alElegir;

  @override
  State<_Menu<T>> createState() => _MenuState<T>();
}

class _MenuState<T> extends State<_Menu<T>> {
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.conBuscador) ...[
            Padding(
              padding: const EdgeInsets.all(Aire.sm),
              child: TextField(
                autofocus: true,
                style: Tipos.texto(tamano: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Buscar…',
                  prefixIcon: Icon(Icons.search, size: 18),
                  prefixIconConstraints: BoxConstraints(minWidth: 34),
                ),
                onChanged: (t) => setState(() => _busqueda = t),
              ),
            ),
            Divider(height: 1, thickness: 1, color: Colores.linea),
          ],
          Flexible(
            // NO ES UN `ListView`, Y NO PUEDE SERLO — lo mismo que ya decía
            // `lib/diseno/selector.dart`, y que aquí costó un reventón.
            //
            // `MenuAnchor` pregunta a su contenido cuánto mide de ancho para
            // decidir el ancho del menú, y un `ListView` no sabe contestar a
            // eso: «RenderShrinkWrappingViewport does not support returning
            // intrinsic dimensions». Un `SingleChildScrollView` sobre una
            // `Column` sí, porque su hijo es una caja normal. Con `showMenu` no
            // pasaba porque el menú era una ruta con ancho impuesto.
            //
            // `primary: false`: el desplazamiento de un menú es SUYO y nunca el
            // principal de la pantalla. Sin esto quedan dos desplazamientos
            // colgando del mismo `PrimaryScrollController` —el de la lista de
            // clientes y el del menú— y Flutter lo corta en seco: «The
            // PrimaryScrollController is attached to more than one
            // ScrollPosition».
            child: SingleChildScrollView(
              primary: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _filas<T>(
                  textoTodos: widget.textoTodos,
                  opciones: widget.opciones,
                  busca: _busqueda,
                  alElegir: widget.alElegir,
                  enCajon: false,
                ),
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
/// un `Cajon` YA es un `SingleChildScrollView` a alto completo, así que la
/// lista entera se desplaza sola y llega hasta el final —el caso que importa es
/// el de vendedores, que en producción son ciento y pico—. Meter aquí otro
/// desplazable dentro de uno que crece sin límite es el error de siempre: o
/// revienta por altura infinita, o queda un panel con su propia barra dentro de
/// otro, que es peor que el menú de antes.
///
/// Y por lo mismo NO hay `SizedBox(width: 280)`: esos 280 px son del panel
/// flotante, que no puede taparlo todo. El cajón sí puede, y de eso va.
class _OpcionesEnCajon<T> extends StatefulWidget {
  const _OpcionesEnCajon({
    required this.textoTodos,
    required this.opciones,
    required this.conBuscador,
    required this.alElegir,
  });

  final String textoTodos;
  final List<OpcionSelector<T>> opciones;
  final bool conBuscador;
  final ValueChanged<T?> alElegir;

  @override
  State<_OpcionesEnCajon<T>> createState() => _OpcionesEnCajonState<T>();
}

class _OpcionesEnCajonState<T> extends State<_OpcionesEnCajon<T>> {
  String _busqueda = '';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (widget.conBuscador) ...[
        TextField(
          // SIN `autofocus`, al contrario que el menú de escritorio.
          //
          // Allí el panel mide 280 px y el teclado no le quita nada, así que
          // abrir escribiendo sale gratis. Aquí el cajón es la pantalla entera
          // y el teclado del teléfono se come la mitad: abrirlo sin que nadie
          // lo haya pedido tapa justo las opciones que se venían a mirar. Quien
          // quiera buscar toca la caja; quien venga a tocar «Todos los
          // municipios» lo ve sin pelear con el teclado.
          style: Tipos.texto(tamano: 14),
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Buscar…',
            prefixIcon: Icon(Icons.search, size: 18),
            prefixIconConstraints: BoxConstraints(minWidth: 34),
          ),
          onChanged: (t) => setState(() => _busqueda = t),
        ),
        const SizedBox(height: Aire.sm),
      ],
      ..._filas<T>(
        textoTodos: widget.textoTodos,
        opciones: widget.opciones,
        busca: _busqueda,
        alElegir: widget.alElegir,
        enCajon: true,
      ),
    ],
  );
}

/// Las filas del desplegable: el «todos» SIEMPRE el primero y sin filtrar, y
/// debajo lo que deje el buscador.
///
/// Una sola función para el menú y para el cajón. Separadas, el día que alguien
/// toque el orden o el «todos» lo arregla en un sitio y deja el otro, y el
/// mismo filtro enseña dos listas distintas según el ancho de la pantalla.
List<Widget> _filas<T>({
  required String textoTodos,
  required List<OpcionSelector<T>> opciones,
  required String busca,
  required ValueChanged<T?> alElegir,
  required bool enCajon,
}) => [
  _Fila<T>(
    etiqueta: textoTodos,
    valor: null,
    alElegir: alElegir,
    enCajon: enCajon,
  ),
  for (final o in _visibles(opciones, busca))
    _Fila<T>(
      etiqueta: o.etiqueta,
      nota: o.nota,
      valor: o.valor,
      alElegir: alElegir,
      enCajon: enCajon,
    ),
];

/// Una fila. Lo único que cambia entre el menú y el cajón son dos cosas, y las
/// dos las decide [enCajon]:
///
///  - **quién cierra lo que está abierto**, que confundirlo ya costó un día:
///    el menú NO es una ruta y lo cierra su `MenuController` —un
///    `Navigator.pop` ahí cerraría la pantalla de Clientes entera
///    (25/09/2026, `los_menus_no_cierran_la_pantalla_test.dart`)—, y el cajón
///    SÍ es una ruta y se cierra con el `Navigator`;
///  - **el alto**. En el menú la fila es `dense` porque se apunta con el ratón;
///    en el cajón se toca con el dedo, y una fila `dense` de 38 px se falla.
///    Sin `dense` el `ListTile` se va a los 48 px que pide cualquier guía de
///    toque.
class _Fila<T> extends StatelessWidget {
  const _Fila({
    required this.etiqueta,
    required this.valor,
    required this.alElegir,
    required this.enCajon,
    this.nota,
  });

  final String etiqueta;
  final String? nota;
  final T? valor;
  final ValueChanged<T?> alElegir;
  final bool enCajon;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: !enCajon,
    title: Text(etiqueta, style: Tipos.texto(tamano: 14, color: Colores.tinta)),
    trailing: nota == null
        ? null
        : Text(
            nota!,
            style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
          ),
    onTap: () {
      // Primero se avisa y luego se cierra: cerrar antes desmonta este `State`
      // y el aviso se perdería.
      alElegir(valor);
      if (enCajon) {
        Navigator.of(context).maybePop();
      } else {
        MenuController.maybeOf(context)?.close();
      }
    },
  );
}
