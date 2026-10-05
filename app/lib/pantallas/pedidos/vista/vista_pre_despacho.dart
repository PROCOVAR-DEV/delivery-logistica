// LA VISTA DEL PRE-DESPACHO. **Una sola**, y con la forma del post-despacho.
//
// ## Por qué existe este fichero — 22/09/2026
//
// El pre-despacho vivía en dos sitios distintos y no se parecían:
//
//  - en Pedidos, dentro de un desplegable (`Pre-despacho de lo filtrado ▾`) que
//    se abría **entre los filtros y la lista** y dejaba una tabla apretada en
//    medio de la página. Jose: «y la mierda de postdespacho ese q diseño mas
//    horrendo el pre me imagino q este igual» y «mejora la vista del predespacho
//    ese q no sea asi con un dropdown anormal ese de pedido no sirve mejora eso
//    ahi para q tenga su propiavista como el post»;
//  - en el asistente de rutas, en su propio cajón (`Pre-despacho`), con una
//    tabla de TRES columnas —sin los kg— en vez de cuatro.
//
// **Dos pre-despachos distintos son dos papeles distintos para el mismo
// almacén.** Así que la vista es ésta y sólo ésta, y los dos caminos —el botón
// de Pedidos y el del asistente— abren el MISMO cajón con el MISMO cuerpo.
//
// ## El esqueleto es el del post-despacho, a propósito
//
// El post-despacho (`rutas/vista/cierre_de_ruta.dart`) ya estaba resuelto así y
// es el patrón bueno: **un botón que abre un `Cajon` con título, las cuentas en
// el subtítulo y el contenido dentro**. No hay un tercer patrón: en este
// proyecto es cajón también en escritorio (`CLAUDE.md` §4, excepción del
// 05/09/2026), así que no hay variante modal que inventar.
//
// Lo que se gana metiendo las cuentas en el SUBTÍTULO del cajón, y no en un
// título dentro de la página: el subtítulo del `Cajon` es `maxLines: 1` con
// elipsis. En el teléfono de Jose ese mismo texto —«Pre-despacho de lo filtrado
// · 24 producto(s) · 23150 empaques · sin peso en el catálogo»— partía el
// encabezado en CUATRO líneas con el botón «Ver e imprimir» encajado en medio.
//
// ## Y por debajo de 640 px deja de ser una tabla
//
// Medido el 22/09/2026 con el teléfono de Jose (1080x2340 físicos = 390 px
// lógicos): la tabla de cuatro columnas pedía **502 px de ancho en una pantalla
// de 390**. `Empaques` empezaba en x=306, `Unidades` se cortaba por la mitad en
// el borde y **`kg` caía entera fuera, en x=473**. Las tres columnas que
// contienen los números por los que existe la pantalla estaban a la derecha, y
// una hoja de pre-despacho sin las cantidades no sirve para nada.
//
// Y cada fila medía **76 px** —el `dataRowMaxHeight` de `temaDeTabla`— para una
// sola línea de texto: cinco productos llenaban la pantalla, y hay veinticuatro.
//
// Por eso debajo de ese ancho se pinta una TARJETA por producto, igual que en
// `pedidos/vista/tabla_pedidos.dart`: el nombre arriba y las tres cifras debajo
// en un `Wrap` —que es lo que garantiza que ninguna palabra se parta, porque
// cada hijo recibe el ancho entero y salta de línea ENTERO cuando no cabe—, y
// **cada cifra lleva su rótulo pegado** (`1.234 empaques`), que es lo que
// sustituye a la cabecera de columna que ya no hay.

import 'package:flutter/material.dart';

import '../../../diseno/cargando.dart';
import '../../../diseno/tabla_ancha.dart';
import '../../../diseno/tema.dart';
import '../datos/formato.dart';
import '../datos/repositorio_pedidos.dart';
import 'kit.dart';

/// Los literales y las claves del pre-despacho, en un solo sitio: los buscan
/// las pruebas y los lee quien está delante.
abstract final class PreDespacho {
  /// El título del cajón de la vista. El de la hoja imprimible es
  /// [tituloDeLaHoja], y son dos cosas distintas a propósito: la vista se mira
  /// en pantalla y la hoja se imprime.
  static const titulo = 'Pre-despacho';

  static const subtituloVacio = 'Sin productos';

  /// El título del cajón de la VISTA PREVIA DEL PDF, que se abre encima de la
  /// vista. Antes era también `Pre-despacho` y con los dos cajones apilados no
  /// había forma de saber cuál estaba mirando una prueba.
  static const tituloDeLaHoja = 'Hoja de pre-despacho';

  static const verEImprimir = 'Ver e imprimir';

  /// Lo que dice el botón mientras no se ha sumado nada todavía.
  static const rotulo = 'Pre-despacho';

  /// Debajo de esto no hay tabla que valga: una tarjeta por producto.
  ///
  /// El número sale de la medida: la tabla pide ~500 px con nombres de producto
  /// normales y más con los largos, así que 640 es el primer escalón donde
  /// entra entera sin desplazamiento lateral. Se escribe aquí y no en
  /// `diseno/anchos.dart` porque ese fichero lo lleva otro; si se sube allí, se
  /// quita de aquí.
  static const enTarjetasBajo = 640.0;

  /// Lo que dice el subtítulo del cajón mientras la suma no ha llegado.
  static const sumando = 'Sumando lo que hay que sacar del almacén…';

  /// Los dos botones de Pedidos que abren la vista. Son dos pre-despachos
  /// distintos —lo filtrado y lo marcado a mano— y por eso son dos claves: con
  /// una sola, una prueba que pulse «el botón» pulsa el que pille.
  static const claveDelBotonDeLoFiltrado = ValueKey('pre-despacho-filtrado');
  static const claveDelBotonDeLoElegido = ValueKey('pre-despacho-elegido');

  /// La tarjeta de un producto. Es lo que deja MEDIRLA en una prueba
  /// (`tester.getRect`), que es la única forma de ver que una fila ya no ocupa
  /// lo que ocupaba.
  static LocalKey claveDeLaTarjeta(String producto) =>
      ValueKey('pre-despacho-$producto');
}

/// Las unidades del total, con la misma regla del `≥` que la columna: lo que se
/// sabe, marcado como mínimo, y cuántos renglones se quedaron fuera.
String _unidadesDelTotal(TotalesPreDespacho t) {
  final u = t.unidades;
  if (u == null) return '—';
  return t.unidadesCompletas
      ? cantidad(u)
      : '≥ ${cantidad(u)} (${t.sinUnidades} '
            '${t.sinUnidades == 1 ? 'renglón' : 'renglones'} sin unidades)';
}

/// EL PESO DE LA FRANJA, o por qué no dice «0.0 kg» — 22/09/2026.
///
/// La franja decía «10 producto(s) · 3185 empaques · **0.0 kg**» mientras la
/// hoja imprimible del mismo filtro decía «264 pedido(s) · **24891.0 kg**». Los
/// dos números eran ciertos cada uno en su definición, y juntos sólo pueden
/// hacer una cosa: que quien carga el camión se crea que no pesa nada.
///
/// Cuando faltan renglones por saber se dice **cuántos**, y la cifra va con un
/// `≥` delante: lo primero es lo que alguien puede ir a arreglar, lo segundo es
/// lo que impide leer un mínimo como un total.
///
/// **Tiene que decir LO MISMO que el papel**, letra por letra
/// (`pesoDeLosProductosEnPapel`, en `impresion/pre_despacho.dart`). Lo ata
/// `test/impresion/los_dos_pesos_del_pre_despacho_test.dart`.
String pesoDelPreDespacho(TotalesPreDespacho t) {
  final peso = t.pesoKg;
  if (peso == null) return 'sin peso en los pedidos';
  if (t.pesoCompleto) return '${peso.toStringAsFixed(1)} kg';
  // El mínimo, y CUÁNTAS LÍNEAS faltan. El número solo diría «falta algo» sin
  // decir cuánto; el conteo solo no deja cargar un camión. Las dos cosas sí.
  return '≥ ${peso.toStringAsFixed(1)} kg (${t.sinPeso} '
      '${t.sinPeso == 1 ? 'renglón' : 'renglones'} sin peso)';
}

/// UNO NO ES «PRODUCTO(S)» NI «1 EMPAQUES» — 28/09/2026.
///
/// Visto en un SM-A165M. Son dos cosas distintas y las dos estaban aquí:
///
///  * el `(s)` entre paréntesis, que es lo que se escribe cuando no se quiere
///    decidir. En el PAPEL se queda —es el punto de paridad con la hoja de Next
///    y se compara palabra por palabra (`impresion/pre_despacho.dart`)—, pero
///    esto es la pantalla y aquí no hay nada con lo que cuadrar;
///  * y `1 empaques`, que es directamente una errata.
///
/// Se pluraliza con el mismo patrón que ya usan las rutas —«3 paradas» / «1
/// parada»—, que es un ternario sobre `== 1` pegado al número. **Y el cero va en
/// plural**: «0 productos», no «0 producto». Es el que se cuela cuando alguien
/// pregunta por el singular y sólo mira el uno.
String resumenDelPreDespacho(TotalesPreDespacho t) =>
    '${t.productos} ${t.productos == 1 ? 'producto' : 'productos'} · '
    '${cantidad(t.empaques)} ${t.empaques == 1 ? 'empaque' : 'empaques'} · '
    '${pesoDelPreDespacho(t)}';

/// Lo que dice el botón que abre la vista: lleva dentro lo que hay contado,
/// para no tener que abrirlo sólo para ver si hay algo.
String rotuloDelPreDespacho(TotalesPreDespacho? t) => t == null
    ? PreDespacho.rotulo
    : '${PreDespacho.rotulo} · ${t.productos} '
          '${t.productos == 1 ? 'producto' : 'productos'}';

/// EL CAJÓN DEL PRE-DESPACHO, entero. **Los dos caminos abren ÉSTE**: el botón
/// de Pedidos y el del asistente de rutas.
///
/// Es la misma forma que el `Post-despacho` del cierre de ruta: título fijo, las
/// cuentas en el subtítulo —una línea con elipsis, que es lo que evita el
/// encabezado partido en cuatro— y el `Ver e imprimir` en el pie, siempre a la
/// vista aunque la lista de productos sea larga.
///
/// Quien lo abre lo envuelve en su propio `Consumer`: [totales] llega `null`
/// mientras se suma y el cajón se rellena solo cuando la suma cae, sin tener que
/// cerrarlo y volverlo a abrir.
class CajonDePreDespacho extends StatelessWidget {
  const CajonDePreDespacho({
    required this.totales,
    this.pie,
    this.alImprimir,
    super.key,
  });

  /// `null` = todavía sumando.
  final TotalesPreDespacho? totales;

  /// Lo que cada sitio añade debajo de la tabla.
  final Widget? pie;

  /// `null` deja el botón apagado. Una hoja en blanco no es una hoja.
  final VoidCallback? alImprimir;

  @override
  Widget build(BuildContext context) {
    final totales = this.totales;
    final hayQueImprimir =
        alImprimir != null && totales != null && totales.lineas.isNotEmpty;
    return Cajon(
      titulo: PreDespacho.titulo,
      subtitulo: totales == null
          ? PreDespacho.sumando
          : resumenDelPreDespacho(totales),
      ancho: AnchoCajon.xl,
      pie: Row(
        children: [
          const Spacer(),
          BotonPrincipal(
            icono: Icons.print_outlined,
            texto: PreDespacho.verEImprimir,
            alPulsar: hayQueImprimir ? alImprimir : null,
          ),
        ],
      ),
      cuerpo: VistaPreDespacho(totales: totales, pie: pie),
    );
  }
}

/// EL BOTÓN QUE ABRE LA VISTA. Es el hermano del `Post-despacho` del cierre de
/// ruta: mismo sitio, mismo gesto.
class BotonDelPreDespacho extends StatelessWidget {
  const BotonDelPreDespacho({
    required this.totales,
    required this.alAbrir,
    super.key,
  });

  /// `null` mientras no se ha sumado nada: el botón se puede pulsar igual, y es
  /// pulsarlo lo que dispara la suma.
  final TotalesPreDespacho? totales;
  final VoidCallback alAbrir;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: alAbrir,
    icon: const Icon(Icons.inventory_2_outlined, size: 18),
    label: Text(rotuloDelPreDespacho(totales)),
  );
}

/// EL CUERPO DE LA VISTA: la tabla (o las tarjetas) y lo que cada sitio añada
/// debajo.
///
/// El [pie] es lo único que cambia entre los dos caminos: el asistente pone ahí
/// el peso contra la capacidad del vehículo, que es suyo y no del almacén.
class VistaPreDespacho extends StatelessWidget {
  const VistaPreDespacho({required this.totales, this.pie, super.key});

  /// `null` = todavía sumando.
  final TotalesPreDespacho? totales;
  final Widget? pie;

  @override
  Widget build(BuildContext context) {
    final totales = this.totales;
    if (totales == null) return const Cargando('Cargando...');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TablaPreDespacho(totales: totales),
        if (totales.lineas.isNotEmpty) ...[
          Divider(height: Aire.xl, thickness: 1, color: Colores.linea),
          TotalesDelPreDespacho(totales: totales),
        ],
        if (pie != null) ...[
          Divider(height: Aire.xl, thickness: 1, color: Colores.linea),
          pie!,
        ],
      ],
    );
  }
}

/// LOS DOS PESOS, SEPARADOS Y CON SU RÓTULO — 22/09/2026.
///
/// En la hoja impresa la columna `kg` salía «—» en las diez líneas y el renglón
/// `Total` ponía **29835.4**. Los dos números son ciertos y cuentan cosas
/// distintas:
///
///  - el «—» de cada línea es el peso **por producto**, que sale del catálogo y
///    que el catálogo no sabe;
///  - el 29835.4 es el peso **de los pedidos**, que sí se sabe entero porque
///    viene en el propio pedido.
///
/// Puestos en la misma columna, con la misma unidad y sin nada que lo diga, un
/// total debajo de diez guiones **se lee como la suma de esos guiones**. Y en la
/// misma pantalla había un tercer número para lo mismo, el «0.0 kg» de la franja
/// —ése ya está arreglado, ver [pesoDelPreDespacho]—: tres cifras distintas para
/// una sola pregunta.
///
/// Aquí van los cuatro totales en filas con su rótulo, y **los dos pesos no
/// comparten renglón**: cada uno dice de qué habla. El de los productos vale
/// `—` cuando sus líneas lo valen, que es lo que no hacía el papel.
///
/// **El papel también, desde el 23/09.** Este comentario decía lo contrario —que
/// la hoja impresa se quedaba como estaba por paridad con la de Next— y se quedó
/// viejo el día que se arregló. Dejar la pantalla y el papel diciendo cosas
/// distintas era peor que cuando los dos mentían igual, así que el papel hace ya
/// esta misma separación, con estos mismos tres literales: ver
/// `TotalesPreDespacho` en `impresion/hoja.dart`, donde está escrito por qué nos
/// separamos de Next.
///
/// Los rótulos están **en los dos sitios a propósito**: cada capa tiene su tipo
/// de totales y el papel no puede depender de una pantalla. Lo que los ata no es
/// este comentario sino una prueba —`los_dos_pesos_del_pre_despacho_test.dart`
/// los compara carácter a carácter—, que es la regla del §3-bis: dos sitios que
/// tienen que decir lo mismo se atan con una prueba, no con un comentario, que
/// un comentario no falla. Éste es la demostración.
class TotalesDelPreDespacho extends StatelessWidget {
  const TotalesDelPreDespacho({required this.totales, super.key});

  final TotalesPreDespacho totales;

  /// El rótulo del peso por producto, literal: lo buscan las pruebas.
  static const pesoDeLosProductos = 'Peso de los productos';

  /// Y el del conjunto de pedidos, que es OTRA cuenta.
  static const pesoDeLosPedidos = 'Peso de los pedidos';

  static const porQueNoSuman =
      'No son el mismo número: el de arriba suma renglón a renglón, y el de '
      'abajo es el peso que trae cada pedido entero.';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      _Fila('Empaques', cantidad(totales.empaques)),
      _Fila('Unidades', _unidadesDelTotal(totales)),
      _Fila(pesoDeLosProductos, pesoDelPreDespacho(totales)),
      _Fila(
        pesoDeLosPedidos,
        '${totales.pesoDeLosPedidos.toStringAsFixed(1)} kg',
      ),
      const SizedBox(height: Aire.xs),
      Text(
        porQueNoSuman,
        style: Tipos.texto(tamano: 11.5, color: Colores.tintaSuave),
      ),
    ],
  );
}

/// Un rótulo y su cifra. En un `Wrap` para que en un teléfono la cifra baje
/// entera en vez de partirse contra el borde.
class _Fila extends StatelessWidget {
  const _Fila(this.rotulo, this.valor);

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Wrap(
      spacing: Aire.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          rotulo,
          style: Tipos.texto(tamano: 12.5, color: Colores.tintaSuave),
        ),
        Text(
          valor,
          style: Tipos.mono(
            tamano: 13,
            peso: FontWeight.w600,
            color: Colores.tinta,
          ),
        ),
      ],
    ),
  );
}

/// La tabla del pre-despacho: cuatro columnas en escritorio, una tarjeta por
/// producto por debajo de [PreDespacho.enTarjetasBajo].
class TablaPreDespacho extends StatelessWidget {
  const TablaPreDespacho({required this.totales, super.key});

  final TotalesPreDespacho totales;

  @override
  Widget build(BuildContext context) {
    if (totales.lineas.isEmpty) {
      return const EstadoVacio(PreDespacho.subtituloVacio);
    }
    return LayoutBuilder(
      builder: (contexto, medidas) {
        if (medidas.maxWidth < PreDespacho.enTarjetasBajo) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final linea in totales.lineas)
                _Tarjeta(
                  key: PreDespacho.claveDeLaTarjeta(linea.producto),
                  linea: linea,
                ),
            ],
          );
        }
        // En escritorio sigue siendo la tabla de siempre, con su propio
        // desplazamiento lateral por si un nombre de producto se sale: se
        // desplaza la tabla, no la página (pliego §11).
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Theme(
            data: Theme.of(contexto).copyWith(dataTableTheme: _tema(contexto)),
            child: DataTable(
              columns: [
                DataColumn(label: cabecera('Producto')),
                DataColumn(label: cabecera('Empaques'), numeric: true),
                DataColumn(label: cabecera('Unidades'), numeric: true),
                DataColumn(label: cabecera('kg'), numeric: true),
              ],
              rows: [
                for (final linea in totales.lineas)
                  DataRow(
                    key: PreDespacho.claveDeLaTarjeta(linea.producto),
                    cells: [
                      DataCell(Text(linea.producto)),
                      DataCell(_cifra(cantidad(linea.empaques))),
                      DataCell(_cifra(_unidades(linea))),
                      DataCell(_cifra(_peso(linea))),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// EL AIRE DE LAS FILAS, que es la otra mitad de la queja.
  ///
  /// `temaDeTabla` da `dataRowMinHeight: 52` y `dataRowMaxHeight: 76`, y una
  /// fila de pre-despacho salía a **76 px para una sola línea de texto**. Esa
  /// altura es la buena en la tabla de Pedidos, donde cada fila lleva dos
  /// líneas (cliente y folio); aquí la fila es el nombre del producto y tres
  /// cifras, y nada más.
  static DataTableThemeData _tema(BuildContext context) =>
      temaDeTabla(context).copyWith(
        headingRowHeight: 36,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 44,
        columnSpacing: 20,
        horizontalMargin: Aire.md,
      );

  /// EL `≥` ES LA MITAD DEL DATO, no un adorno — 28/09/2026.
  ///
  /// Estas dos celdas pintaban `—` en cuanto a UNA línea del producto le
  /// faltara el número. La intención era buena —un total corto que parece
  /// completo es el fallo más caro de esta casa— y el resultado fue que la
  /// columna `kg` salía en blanco en los productos que más se mueven: 21 líneas
  /// de 1.149 borraban 4.949 empaques de MALTA GUAJIRA. Jose, mirando la hoja:
  /// «por q me siguen saliendo cosas sin nada por q razon».
  ///
  /// Y no era pasajero: de los 129 productos de Ventra **sólo 57 traen peso**.
  ///
  /// Con el `≥` delante, el número ya no puede leerse como un total: dice «pesa
  /// por lo menos esto», que es una frase con la que alguien puede decidir si
  /// carga el camión. Una raya no lo es. La raya se queda para lo único que la
  /// merece: cuando no se sabe NADA.
  static String _unidades(LineaPreDespacho l) =>
      _conMinimo(l.unidades, l.unidadesCompletas, (v) => cantidad(v));

  static String _peso(LineaPreDespacho l) =>
      _conMinimo(l.pesoKg, l.pesoCompleto, (v) => v.toStringAsFixed(1));

  static String _conMinimo(
    double? valor,
    bool completo,
    String Function(double) comoSeEscribe,
  ) {
    if (valor == null) return '—';
    return completo ? comoSeEscribe(valor) : '≥ ${comoSeEscribe(valor)}';
  }

  /// Las cifras, en mono y de ancho fijo: se comparan de arriba abajo y con la
  /// proporcional las unidades bailan de fila a fila.
  static Widget _cifra(String texto) =>
      Text(texto, style: Tipos.mono(tamano: 13, color: Colores.tinta));
}

/// UN PRODUCTO EN UN TELÉFONO: el nombre arriba y las tres cifras debajo.
///
/// Cada cifra lleva **su rótulo pegado** —`1.234 empaques`, `— unidades`,
/// `88.5 kg`— porque encima de unas tarjetas no hay cabecera de columna que
/// diga qué es cada número. Y van en un `Wrap`, nunca en `Expanded`: un
/// `Expanded` reparte el ancho a partes y le puede tocar una celda de 39 px,
/// que es exactamente como se rompe una palabra letra a letra.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.linea, super.key});

  final LineaPreDespacho linea;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Colores.linea)),
    ),
    padding: const EdgeInsets.symmetric(vertical: Aire.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          linea.producto,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Tipos.texto(tamano: 13, peso: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Wrap(
          spacing: Aire.md,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // EL RÓTULO VA EN SINGULAR CUANDO ES UNO. `1 empaques` y
            // `1 unidades` se leyeron en un SM-A165M el 28/09/2026, y una
            // errata pegada a un número hace dudar del número.
            //
            // Se mira el VALOR y no el texto ya formateado: `_unidades` puede
            // devolver `≥ 1` o un `—`, y ninguna de las dos cosas es un uno.
            // `kg` no se pluraliza, que es lo que hace un símbolo.
            _Cifra(
              cantidad(linea.empaques),
              linea.empaques == 1 ? 'empaque' : 'empaques',
            ),
            _Cifra(
              TablaPreDespacho._unidades(linea),
              linea.unidades == 1 && linea.unidadesCompletas
                  ? 'unidad'
                  : 'unidades',
            ),
            _Cifra(TablaPreDespacho._peso(linea), 'kg'),
          ],
        ),
      ],
    ),
  );
}

/// Una cifra con su rótulo al lado, como una sola pieza que salta de línea
/// entera.
class _Cifra extends StatelessWidget {
  const _Cifra(this.valor, this.rotulo);

  final String valor;
  final String rotulo;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: valor,
          style: Tipos.mono(tamano: 13, color: Colores.tinta),
        ),
        TextSpan(
          text: ' $rotulo',
          style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
        ),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}
