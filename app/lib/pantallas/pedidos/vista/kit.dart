// El kit que usan Pedidos y Rutas: cajon, insignias, paginacion, selector con
// buscador, estados vacios y la barra con el reloj de datos.
//
// **Ya NO tiene colores ni anchos propios.** Los tenia: una copia de la paleta y
// otra del enum de anchos, escritas cuando `lib/diseno/` todavia no existia. Con
// las dos copias vivas, «ámbar» era un ámbar aqui y otro en el Panel, y el azul
// de una insignia de Pedidos no era el azul de una de Rutas. Ahora los dos
// salen de `lib/diseno/` y se reexportan desde aqui para que las ocho pantallas
// que importan este fichero no tengan que cambiar sus `import`.
//
// Lo que si sigue viviendo aqui son las piezas con la forma que usan estas dos
// pantallas (el `Cajon` de `cuerpo:`, el `Selector` de `MenuAnchor`); lo que
// cambio es **como se ven**, que ahora es lo mismo que en `lib/diseno/`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/cajon.dart' show AtrasDelCajon;
import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/frescura/reloj_de_datos.dart';
import '../../../nucleo/proveedores.dart';

/// La paleta y los anchos de cajon son los de `lib/diseno/`, punto. Se
/// reexportan para no tocar los `import` de las ocho pantallas que los leen
/// desde aqui.
export '../../../diseno/anchos.dart' show AnchoCajon;
export '../../../diseno/colores.dart' show Colores;

/// Por debajo de esto es «movil»: el cajon ocupa la pantalla entera y las
/// columnas prescindibles de la tabla se esconden.
const anchoEscritorio = Anchos.escritorio;

// -----------------------------------------------------------------------------
// El cajon
// -----------------------------------------------------------------------------

/// El patron cajon: entra deslizandose por la derecha, a alto completo, sobre un
/// velo negro al 40 %.
///
/// **Esta aplicacion usa cajon tambien en escritorio.** Es la excepcion aprobada
/// del 05/09/2026 (`pantallas.md` §0 y §9.2): en el resto de Procovar es modal en
/// escritorio y cajon en movil, aqui no hay variante modal. Lo que se conserva de
/// la regla de la casa es lo que de verdad importa: en movil ocupa la pantalla
/// entera, en escritorio es un panel lateral a alto completo —nunca un
/// `AlertDialog` centrado— y **la ✕ de cerrar no desaparece nunca**, esté donde
/// esté el desplazamiento del cuerpo.
class Cajon extends StatelessWidget {
  const Cajon({
    required this.titulo,
    required this.cuerpo,
    this.subtitulo,
    this.ancho = AnchoCajon.lg,
    this.pie,
    this.bajoLaCabecera,
    super.key,
  });

  final String titulo;
  final String? subtitulo;
  final Widget cuerpo;

  /// LO QUE VA PEGADO DEBAJO DE LA CABECERA Y NO SE DESPLAZA NUNCA.
  ///
  /// Es el hermano del [pie] por arriba: el armazon del panel se queda quieto y
  /// lo unico que se mueve es el cuerpo. Lo pide el asistente de rutas para su
  /// barra de pasos, que es por donde se vuelve a un paso anterior: si se va
  /// con el desplazamiento, en un telefono hay que subir por toda la lista de
  /// pedidos para poder retroceder, que es justo lo que se estaba arreglando.
  ///
  /// Opcional, y los demas cajones no lo usan: sin el, el panel es exactamente
  /// el de antes.
  final Widget? bajoLaCabecera;

  /// Pegado abajo, con los botones de accion **siempre a la vista**.
  final Widget? pie;
  final AnchoCajon ancho;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final pantalla = MediaQuery.sizeOf(context);
    final enMovil = pantalla.width < anchoEscritorio;
    final anchoFinal = enMovil
        ? pantalla.width
        : ancho.px.clamp(0.0, pantalla.width);

    // El teclado, igual que en `diseno/cajon.dart`: este cajon tambien se abre
    // con `showGeneralDialog`, o sea fuera del `body` del `Scaffold`, y sin esto
    // el pie y el final del cuerpo se quedan por debajo de las teclas.
    final teclado = MediaQuery.viewInsetsOf(context).bottom;

    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(bottom: teclado),
        child: DecoratedBox(
          // `shadow-2xl` y borde fino a la izquierda, como el `Drawer.tsx` de
          // delivery: sobre el velo al 40 %, un panel sin sombra se pega al borde
          // y no se lee como algo que esta por encima de la lista.
          decoration: BoxDecoration(
            color: Colores.blanco,
            border: Border(left: BorderSide(color: Colores.linea)),
            boxShadow: Sombras.xl,
          ),
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: anchoFinal,
              height: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Aire.xl,
                        Aire.lg,
                        Aire.sm,
                        Aire.lg,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  titulo,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tema.textTheme.titleMedium,
                                ),
                                if (subtitulo != null)
                                  Text(
                                    subtitulo!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tema.textTheme.bodySmall?.copyWith(
                                      color: Colores.tintaSuave,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // La ✕: fuera del cuerpo desplazable, para que no se pueda
                          // ir de la vista por mucho que se baje.
                          IconButton(
                            tooltip: 'Cerrar',
                            icon: const Icon(Icons.close, size: 20),
                            color: Colores.tintaSuave,
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: Colores.linea),
                  if (bajoLaCabecera != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Aire.xl,
                        Aire.md,
                        Aire.xl,
                        Aire.md,
                      ),
                      child: bajoLaCabecera,
                    ),
                    Divider(height: 1, thickness: 1, color: Colores.linea),
                  ],
                  Expanded(
                    child: SingleChildScrollView(
                      // LO ULTIMO DEL CUERPO NO PUEDE QUEDAR DEBAJO DE LA BARRA
                      // DE GESTOS — 17/09/2026.
                      //
                      // La cabecera lleva `SafeArea(bottom: false)` y el pie
                      // `SafeArea(top: false)`: entre los dos apartan el panel del
                      // reloj de arriba y de la barra de abajo. Pero **sin pie no
                      // hay quien aparte nada por abajo**, y el cuerpo es lo unico
                      // que queda: el cajon de detalle de un pedido no tiene pie,
                      // asi que su ultimo renglon se metia por debajo de la barra
                      // de gestos.
                      //
                      // Medido a 390x844 con una barra de 34 px: el ultimo renglon
                      // terminaba en y=819 con la barra empezando en y=810. No es
                      // que se viera raro — es que la ultima linea no se leia y no
                      // habia forma de bajar mas, porque el desplazamiento ya
                      // estaba al final.
                      //
                      // Va en el relleno del desplazable y no en un `SafeArea`
                      // alrededor: asi el contenido sigue pudiendo pasar POR
                      // DEBAJO de la barra mientras se desplaza, y lo unico que
                      // cambia es donde se para.
                      padding: EdgeInsets.fromLTRB(
                        Aire.xl,
                        Aire.lg,
                        Aire.xl,
                        Aire.xl +
                            (pie == null
                                ? MediaQuery.paddingOf(context).bottom
                                : 0),
                      ),
                      child: cuerpo,
                    ),
                  ),
                  if (pie != null) ...[
                    Divider(height: 1, thickness: 1, color: Colores.linea),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Aire.xl,
                          vertical: Aire.md,
                        ),
                        child: pie,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Abre un [Cajon]. `Escape` y el velo cierran, y la animacion es la del pliego:
/// 180 ms desde 24 px a la derecha.
Future<T?> abrirCajon<T>(BuildContext context, WidgetBuilder construir) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: Colores.tinta.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 180),
    // ATRÁS CIERRA EL CAJÓN, TAMBIÉN EN EL NAVEGADOR — 28/09/2026.
    //
    // Éste es el único cajón que no pasa por `diseno/cajon.dart`, y sin esto se
    // quedaba puesto cuando alguien daba atrás en el navegador: el atrás del
    // navegador no dispara ningún `popRoute`, sólo cambia la dirección, así que
    // la pantalla de debajo se repintaba con la anterior y el cajón seguía
    // flotando encima. Jose: «dar atras cuando estoy en un drawer no sale del
    // drawer sigue trabajando atras».
    //
    // `AtrasDelCajon` vigila el CAMINO de la pantalla de debajo —no la
    // dirección entera, que los filtros van después del `?` y hay cajones que
    // existen justo para cambiarlos— y se cierra cuando cambia.
    pageBuilder: (contexto, _, _) => AtrasDelCajon(child: construir(contexto)),
    transitionBuilder: (contexto, animacion, _, hijo) {
      final curva = CurvedAnimation(parent: animacion, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curva,
        child: Transform.translate(
          offset: Offset(24 * (1 - curva.value), 0),
          child: hijo,
        ),
      );
    },
  );
}

// -----------------------------------------------------------------------------
// Piezas sueltas
// -----------------------------------------------------------------------------

/// Una insignia de color con su texto. Nada de emojis: color y palabra.
class Insignia extends StatelessWidget {
  const Insignia(this.texto, {required this.color, this.tooltip, super.key});

  final String texto;
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final pinta = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radios.pastilla),
      ),
      child: Text(
        texto,
        style: Tipos.texto(
          tamano: 11,
          peso: FontWeight.w600,
          color: color,
          interletra: 0.1,
        ),
      ),
    );
    return tooltip == null ? pinta : Tooltip(message: tooltip!, child: pinta);
  }
}

/// El estado vacio. Son tres textos distintos y se confunden con facilidad, asi
/// que el que toca lo decide quien llama y aqui sólo se pinta.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio(this.texto, {this.accion, super.key});

  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: Aire.xl),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          texto,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Colores.tintaSuave),
        ),
        if (accion != null) ...[const SizedBox(height: Aire.lg), accion!],
      ],
    ),
  );
}

/// La barra de paginas del pliego (§9.7). No se pinta si el total es 0.
class Paginacion extends StatelessWidget {
  const Paginacion({
    required this.pagina,
    required this.porPagina,
    required this.total,
    required this.alIr,
    super.key,
  });

  final int pagina;
  final int porPagina;
  final int total;
  final void Function(int) alIr;

  int get paginas => total == 0 ? 1 : ((total - 1) ~/ porPagina) + 1;

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();
    final desde = ((pagina - 1) * porPagina) + 1;
    final hasta = (pagina * porPagina).clamp(0, total);

    // Ventana de 5 numeros alrededor de la actual.
    final primero = (pagina - 2).clamp(1, paginas);
    final ultimo = (primero + 4).clamp(1, paginas);
    final inicio = (ultimo - 4).clamp(1, paginas);

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: Aire.md,
        horizontal: Aire.lg,
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Aire.xs,
        runSpacing: Aire.xs,
        children: [
          // Las cifras en mono y en negrita, que es lo que se lee de un vistazo.
          Text.rich(
            TextSpan(
              style: Tipos.texto(tamano: 13, color: Colores.tintaSuave),
              children: [
                const TextSpan(text: 'Mostrando '),
                TextSpan(
                  text: '$desde–$hasta',
                  style: Tipos.mono(
                    tamano: 13,
                    peso: FontWeight.w600,
                    color: Colores.tinta,
                  ),
                ),
                const TextSpan(text: ' de '),
                TextSpan(
                  text: '$total',
                  style: Tipos.mono(
                    tamano: 13,
                    peso: FontWeight.w600,
                    color: Colores.tinta,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Aire.sm),
          _boton(context, '«', pagina > 1 ? () => alIr(1) : null),
          _boton(context, '‹', pagina > 1 ? () => alIr(pagina - 1) : null),
          for (var n = inicio; n <= ultimo; n++)
            _boton(
              context,
              '$n',
              n == pagina ? null : () => alIr(n),
              actual: n == pagina,
            ),
          _boton(
            context,
            '›',
            pagina < paginas ? () => alIr(pagina + 1) : null,
          ),
          _boton(context, '»', pagina < paginas ? () => alIr(paginas) : null),
        ],
      ),
    );
  }

  /// La actual va en primario LLENO y en blanco (`bg-blue-600 text-white`); las
  /// demas son cajas blancas con el borde fino, y las que no llevan a ninguna
  /// parte al 40 % (`disabled:opacity-40`).
  Widget _boton(
    BuildContext context,
    String texto,
    VoidCallback? alPulsar, {
    bool actual = false,
  }) => SizedBox(
    width: 34,
    height: 34,
    child: Material(
      color: actual ? Colores.primario : Colores.blanco,
      borderRadius: BorderRadius.circular(Radios.md),
      child: InkWell(
        onTap: alPulsar,
        borderRadius: BorderRadius.circular(Radios.md),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radios.md),
            border: Border.all(
              color: actual ? Colores.primario : Colores.linea,
            ),
          ),
          child: Center(
            child: Opacity(
              opacity: alPulsar == null && !actual ? 0.4 : 1,
              child: Text(
                texto,
                style: Tipos.texto(
                  tamano: 13,
                  peso: actual ? FontWeight.w600 : FontWeight.w500,
                  color: actual ? Colors.white : Colores.tintaSuave,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Una opcion del selector: etiqueta y una nota pequena a la derecha (un
/// conteo, un codigo, `en ruta`).
class OpcionSelector<T> {
  const OpcionSelector(this.valor, this.etiqueta, {this.nota});

  final T valor;
  final String etiqueta;
  final String? nota;
}

/// El desplegable con buscador (§9.6): **caja de busqueda a partir de 4
/// opciones**, o siempre si se fuerza.
///
/// **En el telefono no es un menu: es un cajon.** Ver el comentario largo del
/// `build`, que cuenta el 28/09/2026.
///
/// POR QUÉ ESTO NO ES EL `Selector` DE `lib/diseno/`, QUE SERÍA MEJOR.
///
/// Se miró, y sería una pieza en vez de tres. No se puede de golpe, y el motivo
/// no es de gusto:
///
///  1. **El `OpcionSelector` de aquí lleva los argumentos por posición**
///     (`OpcionSelector('cam', 'Camagüey', nota: 'CAM')`) y el del común por
///     nombre. Son dos clases distintas con el mismo nombre, y cambiar de una a
///     otra toca las DIECISÉIS pantallas que importan este fichero —Pedidos,
///     Rutas, el asistente de cuatro pasos y el Tablero entero—, que ahora
///     mismo las están escribiendo otros agentes.
///  2. El común pinta la **marca ✓ de lo elegido** y la **nota corta dentro de
///     la caja**; éste no hace ninguna de las dos. Traerlas es un cambio de
///     aspecto en dieciséis pantallas, no un renombre.
///  3. `Selector.nadaQueCuadre` es público y lo usa
///     `test/pantallas/pedidos/selector_del_kit_test.dart`.
///
/// Unificar es un buen cambio y hay que hacerlo, pero es otro y de un solo
/// agente con el árbol quieto. Mientras tanto, lo que sí se comparte es **el
/// comportamiento**: el mismo corte en `Anchos.escritorio` y el mismo cajón,
/// que es lo que ve Jose.
class Selector<T> extends StatelessWidget {
  const Selector({
    required this.titulo,
    required this.valor,
    required this.opciones,
    required this.alElegir,
    this.buscadorSiempre = false,
    super.key,
  });

  final String titulo;
  final T valor;

  /// La opcion «todos» va la primera y su texto lo pone cada pantalla.
  final List<OpcionSelector<T>> opciones;
  final void Function(T) alElegir;
  final bool buscadorSiempre;

  /// Lo que se lee cuando el buscador del desplegable no encuentra nada.
  /// Literal aquí para que la prueba busque lo que se lee en pantalla.
  static const nadaQueCuadre = 'Nada que cuadre con';

  @override
  Widget build(BuildContext context) {
    final elegida = opciones.where((o) => o.valor == valor).firstOrNull;
    // Igual que el de `lib/diseno/selector.dart`: con algo elegido el borde se
    // tine de primario y la letra se pone en semibold, para que se vea que el
    // filtro ESTA PUESTO sin leer la etiqueta.
    final filtrando = elegida != null;
    final conBuscador = buscadorSiempre || opciones.length >= 4;

    // EN EL TELÉFONO ES UN CAJÓN; EN ESCRITORIO, EL MENÚ ANCLADO DE SIEMPRE.
    //
    // Jose, 28/09/2026, con Pedidos abierto en el móvil:
    //
    //     «recuerda que este modal en el movil debe ser un drawer, el
    //      calendario, todo lo que salga asi como modal que sobresalga, los
    //      dropdowns creo que seria mejor ponerlos como drawer, todo eso para
    //      las opciones y queda mucho mas comodo»
    //
    // Dijo «los dropdowns», en plural, y en la aplicación son CUATRO: el común
    // de `lib/diseno/selector.dart`, el calendario de `rango_de_fechas.dart`,
    // el de Clientes y éste. Los dos primeros se pasaron a cajón ese mismo día.
    //
    // Éste es el que más sitios toca: los filtros de Pedidos, los de Rutas, el
    // Tablero y los cuatro pasos del asistente. Su panel mide 320x360 como
    // mucho y se ancla al botón; en un teléfono de 390 px eso ya se pega a los
    // bordes, y el buscador hace `autofocus`, así que el teclado se come lo que
    // quedaba. El caso que lo hace insufrible es el selector de vendedor del
    // asistente, con ciento y pico opciones en un panel de 360 px de alto.
    //
    // Y EN ESCRITORIO TAMBIÉN, desde el 28/09/2026 por la tarde.
    //
    // Aquí estuvo escrito que el corte era `anchoEscritorio` «y NO cajón
    // siempre, aunque el §4 del CLAUDE.md lo permitiría», con el argumento de
    // que las cuatro piezas que hacen lo mismo tienen que cortar por el mismo
    // sitio. El argumento era bueno y la conclusión al revés: **las cuatro
    // cortan igual, y ninguna corta**. El §4 no lo permite, lo manda: «**Cajón
    // siempre**, también en escritorio (excepción aprobada para este proyecto el
    // 05/09/2026)».
    //
    // Jose lo vio el mismo día en su monitor, con un desplegable flotando y
    // descolocado sobre la página: «q te dije de los dropdowns flotantes q los
    // pusieras como drawer».
    //
    // Con el menú se va su `MenuAnchor` entero: **quitar algo es quitarlo
    // entero** (§6). Y lo que el menú vino a arreglar el 25/09/2026 —quedarse
    // flotando al desplazar la página— el cajón no lo tiene: no está anclado a
    // nada, así que no hay a qué seguir.
    return _caja(
      elegida: elegida,
      filtrando: filtrando,
      alPulsar: () => _abrirElCajon(context, conBuscador: conBuscador),
    );
  }

  /// El cajón del teléfono. Lo titula el [titulo] del filtro, que en escritorio
  /// es el `tooltip` del botón — y en un teléfono no hay ratón que lo saque,
  /// así que aquí es la única vez que se lee.
  ///
  /// **Va con el `Cajon` de este mismo fichero y no con el de `lib/diseno/`.**
  /// Los dos existen y hacen lo mismo; éste es el que ya abren las dieciséis
  /// pantallas que importan el kit, así que un selector de Pedidos que abriera
  /// el otro tendría distinto relleno y distinto `SafeArea` que el cajón de
  /// detalle de al lado, y nadie sabría por qué.
  Future<void> _abrirElCajon(
    BuildContext contexto, {
    required bool conBuscador,
  }) => abrirCajon<void>(
    contexto,
    (_) => Cajon(
      titulo: titulo,
      // En movil `Cajon` ignora este ancho y ocupa la pantalla entera; se pone
      // el mas estrecho para que un escritorio estrecho —una ventana a 900 px,
      // que tambien entra por aqui— no se coma la pantalla por una lista de
      // opciones.
      ancho: AnchoCajon.md,
      cuerpo: _OpcionesEnCajon<T>(
        opciones: opciones,
        conBuscador: conBuscador,
        alElegir: alElegir,
      ),
    ),
  );

  /// La caja del filtro. Es la MISMA en los dos sitios: lo unico que cambia es
  /// lo que hace al pulsarla. Estaba escrita dentro del `builder` del
  /// `MenuAnchor`, y ahi solo la podia usar el escritorio.
  Widget _caja({
    required OpcionSelector<T>? elegida,
    required bool filtrando,
    required VoidCallback alPulsar,
  }) => Tooltip(
    message: titulo,
    child: OutlinedButton(
      onPressed: alPulsar,
      // EL BLANCO SE QUEDA, Y ES LO QUE SE ESPERA — 28/09/2026.
      //
      // La regla de la casa es que **un boton no lleva fondo**
      // (`diseno/tema.dart`, [Botones]), y esto es un `OutlinedButton` que
      // contradice al tema a proposito: **no es un boton, es un campo**. Se
      // dibuja al lado de las cajas de buscar y de fecha, hace lo mismo que un
      // desplegable, y lo que manda ahi es `inputDecorationTheme`, que pone
      // `filled: true` con `fillColor: Colores.blanco`. Quitarle el blanco
      // dejaria un filtro translucido en una barra de filtros opacos: se veria
      // roto, no limpio.
      //
      // La prueba de si algo de esto es un boton o un campo: ¿hace algo al
      // pulsarlo, o abre algo para elegir? Esto abre.
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
          Flexible(
            child: Text(
              elegida?.etiqueta ?? titulo,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Aire.xs),
          Icon(Icons.keyboard_arrow_down, size: 16, color: Colores.tintaSuave),
        ],
      ),
    ),
  );
}

/// Las opciones que quedan al escribir en el buscador.
///
/// SE BUSCA TAMBIÉN POR LA NOTA, no sólo por la etiqueta. La nota es el código
/// de la sucursal (`CAM`, `HOL`, `STG`), que es como se las nombra aquí;
/// buscando sólo por etiqueta, escribir `CAM` en el selector de sucursal del
/// asistente no encuentra Camagüey.
///
/// Está aquí suelta y la usan los DOS caminos —el menú de escritorio y el cajón
/// del teléfono—, porque son el mismo filtro. Copiada dos veces, el día que
/// alguien le añada un criterio lo arregla en un sitio y en el otro no, y la
/// mitad de los usuarios ve otra lista.
List<OpcionSelector<T>> _visibles<T>(
  List<OpcionSelector<T>> opciones,
  String texto,
) {
  final busca = texto.trim().toLowerCase();
  if (busca.isEmpty) return opciones;

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
              o.etiqueta.toLowerCase().contains(busca) ||
              (o.nota ?? '').toLowerCase().contains(busca),
        ),
  ];
}

class _MenuConBuscador<T> extends StatefulWidget {
  const _MenuConBuscador({
    required this.opciones,
    required this.conBuscador,
    required this.alElegir,
  });

  final List<OpcionSelector<T>> opciones;
  final bool conBuscador;
  final void Function(T) alElegir;

  @override
  State<_MenuConBuscador<T>> createState() => _MenuConBuscadorState<T>();
}

class _MenuConBuscadorState<T> extends State<_MenuConBuscador<T>> {
  String _texto = '';

  @override
  Widget build(BuildContext context) {
    final visibles = _visibles(widget.opciones, _texto);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360, maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.conBuscador) ...[
            Padding(
              padding: const EdgeInsets.all(Aire.sm),
              child: TextField(
                autofocus: true,
                style: Tipos.texto(tamano: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  prefixIconConstraints: BoxConstraints(minWidth: 34),
                  hintText: 'Buscar…',
                ),
                onChanged: (t) => setState(() => _texto = t),
              ),
            ),
            Divider(height: 1, thickness: 1, color: Colores.linea),
          ],
          Flexible(
            // `primary: false`: el desplazamiento de un menu es SUYO y nunca el
            // principal de la pantalla. Sin esto, abrir un selector dentro de un
            // `Cajon` deja dos desplazamientos colgados del mismo
            // `PrimaryScrollController` —el del cuerpo del cajon y el del
            // menu— y Flutter lo corta en seco: «The PrimaryScrollController is
            // attached to more than one ScrollPosition». Se ve abriendo el
            // selector de vehiculo del asistente de rutas.
            child: SingleChildScrollView(
              primary: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_hayCoincidencias(widget.opciones, _texto))
                    _NadaQueCuadre(
                      texto: _texto,
                      salida: _laSalida(widget.opciones),
                    ),
                  for (final opcion in visibles)
                    MenuItemButton(
                      onPressed: () => widget.alElegir(opcion.valor),
                      trailingIcon: opcion.nota == null
                          ? null
                          : Text(
                              opcion.nota!,
                              style: Tipos.texto(
                                tamano: 11,
                                color: Colores.tintaSuave,
                              ),
                            ),
                      child: Text(
                        opcion.etiqueta,
                        style: Tipos.texto(tamano: 14, color: Colores.tinta),
                      ),
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

/// Las mismas opciones, dentro del cajon del telefono (28/09/2026).
///
/// **Aqui no hay ningun desplazamiento propio, y es a proposito.** El cuerpo de
/// un [Cajon] YA es un `SingleChildScrollView` a alto completo, asi que la
/// lista entera se desplaza sola y llega hasta el final —el caso que importa es
/// el vendedor con ciento y pico opciones, que no cabe ni de lejos—. Meter aqui
/// otro desplazable dentro de uno que crece sin limite es el error de siempre:
/// o revienta por altura infinita, o queda un panel de 360 px con su barra
/// dentro de otro, que es peor que el menu de antes.
///
/// Y por lo mismo NO hay `BoxConstraints(maxHeight: 360, maxWidth: 320)`: ese
/// tope es del menu flotante, que no puede taparlo todo. El cajon si puede, y
/// de eso va.
class _OpcionesEnCajon<T> extends StatefulWidget {
  const _OpcionesEnCajon({
    required this.opciones,
    required this.conBuscador,
    required this.alElegir,
  });

  final List<OpcionSelector<T>> opciones;
  final bool conBuscador;
  final void Function(T) alElegir;

  @override
  State<_OpcionesEnCajon<T>> createState() => _OpcionesEnCajonState<T>();
}

class _OpcionesEnCajonState<T> extends State<_OpcionesEnCajon<T>> {
  String _texto = '';

  @override
  Widget build(BuildContext context) {
    final visibles = _visibles(widget.opciones, _texto);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.conBuscador) ...[
          TextField(
            // SIN `autofocus`, al contrario que el menu de escritorio.
            //
            // Alli el panel mide 320 px y el teclado no le quita nada, asi que
            // abrir escribiendo sale gratis. Aqui el cajon es la pantalla
            // entera y el teclado del telefono se come la mitad: abrirlo sin
            // que nadie lo haya pedido tapa justo las opciones que se venian a
            // mirar. Quien quiera buscar toca la caja; quien venga a tocar
            // «Todos los vehículos» lo ve sin pelear con el teclado.
            style: Tipos.texto(tamano: 14),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              prefixIconConstraints: BoxConstraints(minWidth: 34),
              hintText: 'Buscar…',
            ),
            onChanged: (t) => setState(() => _texto = t),
          ),
          const SizedBox(height: Aire.sm),
        ],
        // BUSCAR Y NO ENCONTRAR NADA SE DICE, también aquí — 24/09/2026.
        //
        // Un cajón a pantalla completa con la caja de buscar y NADA debajo es
        // todavía peor que el panel en blanco de aquel día: ocupa los 390 px de
        // ancho y los 800 de alto para no decir nada.
        if (!_hayCoincidencias(widget.opciones, _texto))
          _NadaQueCuadre(texto: _texto, salida: _laSalida(widget.opciones)),
        for (final opcion in visibles)
          ListTile(
            // SIN `dense`, al contrario que el menú. Aquí se toca con el dedo y
            // una fila de 38 px se falla; sin `dense` el `ListTile` se va a los
            // 48 px que pide cualquier guía de toque.
            title: Text(
              opcion.etiqueta,
              style: Tipos.texto(tamano: 14, color: Colores.tinta),
            ),
            trailing: opcion.nota == null
                ? null
                : Text(
                    opcion.nota!,
                    style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
                  ),
            onTap: () {
              // Primero se avisa y luego se cierra: cerrar antes desmonta este
              // `State` y el aviso se perderia.
              widget.alElegir(opcion.valor);
              // EL CAJON SI ES UNA RUTA —`showGeneralDialog`—, asi que aqui el
              // `Navigator` es lo correcto. Es justo lo contrario del menu, que
              // NO es una ruta y se cierra solo con su `MenuController`: alli
              // un `pop` cerraria la pantalla de debajo (25/09/2026,
              // `los_menus_no_cierran_la_pantalla_test.dart`).
              Navigator.of(context).maybePop();
            },
          ),
      ],
    );
  }
}

/// El cartel de cuando el buscador no deja nada. Uno solo para los dos sitios:
/// mismo texto en el menu y en el cajon, que es lo que pedia el 24/09/2026 —«la
/// misma frase en toda la aplicacion»— y que separados duraria un mes.
///
/// Un panel en blanco es indistinguible de «este desplegable esta roto» y de
/// «aqui no hay nada que elegir», que es justo lo que no pasa.
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

/// La etiqueta de la opcion que SIGUE ESTANDO debajo del aviso: la primera, la
/// de «todos», que el buscador no filtra. `null` si no hay ninguna.
String? _laSalida<T>(List<OpcionSelector<T>> opciones) =>
    opciones.isEmpty ? null : opciones.first.etiqueta;

class _NadaQueCuadre extends StatelessWidget {
  const _NadaQueCuadre({required this.texto, this.salida});

  final String texto;

  /// La etiqueta de la opcion de «todos», que es la unica que queda debajo.
  final String? salida;

  /// EL AVISO NO PUEDE DESMENTIRLO LA PANTALLA DOS LINEAS MAS ABAJO —28/09/2026.
  ///
  /// Jose, escribiendo `toda` en un desplegable con buscador: salia «Nada que
  /// cuadre con «toda»» y **debajo estaba `Todas (8)`**, que a la vista de quien
  /// lee cuadra perfectamente. Un aviso que la propia pantalla contradice se
  /// deja de leer, y entonces tampoco se lee el dia que dice la verdad.
  ///
  /// Lo que NO se toca es el motivo por el que esa opcion sigue ahi: la primera
  /// —la de «todos»— es la que DESHACE el filtro, y se la llevaba el buscador
  /// justo cuando hacia falta (ver [_visibles]). Eso esta bien y se queda.
  ///
  /// Lo que se arregla es el texto: se nombra lo que queda y **para que sirve**.
  /// Nombrarlo es lo que convierte la contradiccion en una explicacion — quien
  /// lee «abajo solo queda «Todas (8)», que quita el filtro» ya sabe las dos
  /// cosas: que lo suyo no esta, y que lo de abajo es la salida y no un
  /// resultado.
  String _elTexto() {
    final aviso = '${Selector.nadaQueCuadre} «${texto.trim()}»';
    final queda = salida;
    // Sin opciones no hay nada que nombrar y el aviso se queda como estaba: no
    // se inventa una salida que no existe.
    if (queda == null) return aviso;
    return '$aviso.\nAbajo sólo queda «$queda», que quita el filtro.';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Aire.lg),
    child: Text(
      _elTexto(),
      textAlign: TextAlign.center,
      style: Tipos.texto(tamano: 13, color: Colores.tintaSuave),
    ),
  );
}

// -----------------------------------------------------------------------------
// La barra con el reloj de datos
// -----------------------------------------------------------------------------

/// De que hora son los datos de unas colecciones, listo para el [RelojDeDatos].
///
/// Manda la bajada MAS VIEJA de las que usa la pantalla: una pantalla no esta al
/// dia si una de las colecciones que pinta no lo esta.
final frescuraDePantallaProvider =
    StreamProvider.family<EstadoFrescura, List<String>>((ref, colecciones) {
      final reloj = ref.watch(relojProvider);
      return ref
          .watch(frescuraProvider)
          .laMasVieja(colecciones)
          .map((bajada) => EstadoFrescura.de(bajada, ahora: reloj()));
    });

/// La franja de arriba, **siempre visible**: de que hora son los datos y cuanto
/// queda sin subir (caso S8). Sin esto, una pantalla con datos de anteayer es
/// indistinguible de una al dia.
class BarraDeDatos extends ConsumerWidget {
  const BarraDeDatos({
    required this.colecciones,
    this.alPulsarPendientes,
    super.key,
  });

  final List<String> colecciones;
  final VoidCallback? alPulsarPendientes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frescura = ref.watch(frescuraDePantallaProvider(colecciones));
    final sinSubir = ref.watch(sinSubirProvider);

    return RelojDeDatos(
      // «NO HE MIRADO» NO SE PINTA COMO «NO HAY NADA» — 28/09/2026.
      //
      // Aqui ponia `frescura.value ?? const SinDescargar()`, con el motivo de
      // que «mientras carga no se puede afirmar que los datos esten al dia».
      // El motivo era bueno y la conclusion equivocada: `SinDescargar` no es
      // una reserva prudente, es una AFIRMACION —«este aparato no ha bajado
      // nunca»—, va en ambar y enciende el gesto de traer el dia.
      //
      // Lo que se veia el 28/09/2026 al abrir sin senal en un SM-A165M: el
      // renglon de frescura diciendo que no habia nada durante unos cuatro
      // segundos y asentandose despues en la hora de la ultima bajada. Un
      // estado vacio leido como otro, que es el §3-ter.
      //
      // `hasValue` y no `value != null` a proposito: la consulta contesta
      // `null` de verdad cuando alguna coleccion no se bajo nunca, y ESE null
      // si es `SinDescargar`. Los dos casos dan `value == null` y son opuestos.
      estado: switch (frescura) {
        AsyncData(:final value) => value,
        // Un fallo leyendo la propia base no es «no hay datos», pero tampoco se
        // puede callar (§4): se dice en ambar y con el unico estado que empuja
        // al gesto que lo arregla.
        AsyncError() => const SinDescargar(),
        _ => const SinMirarTodavia(),
      },
      sinSubir: sinSubir.value ?? 0,
      alPulsarPendientes: alPulsarPendientes,
    );
  }
}

/// Las colecciones que mira cada pantalla. Se declaran aqui, al lado de la
/// barra, para que anadir una consulta nueva a una pantalla obligue a pensar si
/// su frescura cuenta.
abstract final class ColeccionesDePantalla {
  static const pedidos = <String>[
    Colecciones.pedidos,
    Colecciones.renglones,
    Colecciones.productos,
  ];

  static const rutas = <String>[
    Colecciones.rutas,
    Colecciones.pedidos,
    Colecciones.vehiculos,
    Colecciones.almacenes,
  ];
}
