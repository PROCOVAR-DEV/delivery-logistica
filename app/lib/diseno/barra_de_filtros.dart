// LA BARRA DE FILTROS DE TODAS LAS LISTAS. Una sola, y por eso está aquí.
//
// Las piezas de filtrar ya eran comunes —`CajaDeBusqueda`, `Selector`,
// `RangoDeFechas`—, pero cada pantalla las COLOCABA a su manera, y en un
// teléfono de 390 px eso se veía como cuatro aplicaciones distintas. Palabras
// de Jose, 25/09/2026:
//
//     «en movil sigues teniendo los filtros en todas las vistas q tengan
//      filtros lo tienes mal ubicados regados sin uniformidad sin nada lo
//      tienes super mal organizado»
//
// Lo que había, mirado a 390 px en el navegador:
//
//   - **Tablero**: la caja de buscar a todo el ancho y, encima de ella, un
//     embudo suelto pegado al borde derecho, sin nada al lado.
//   - **Pedidos**: la caja de buscar de 220 px con un hueco muerto a su
//     derecha, y debajo siete pastillas partidas en escalones desiguales
//     —dos, dos, una y una— con el borde derecho hecho sierra.
//   - **Clientes**: la caja de buscar de 220 px y los filtros en columna, cada
//     uno con su etiqueta encima («Municipio del cliente»...). Otro diseño.
//   - **Rutas**: la caja de buscar de 220 px y tres pastillas en una fila que
//     acaba antes que la caja de arriba.
//
// Cuatro maneras de resolver lo mismo. En escritorio las cuatro se ven bien
// porque sobra ancho; el desorden nace justo donde se trabaja de verdad.
//
// LA REGLA QUE IMPONE ESTA BARRA, y son tres cosas:
//
// 1. **La caja de buscar manda sola y a todo el ancho.** Siempre arriba,
//    siempre la primera, siempre pegada a los dos márgenes. Es lo que más se
//    usa y lo que antes se encogía a 220 px dejando el hueco.
// 2. **Los filtros van en rejilla de dos columnas iguales.** No en `Wrap`: el
//    `Wrap` reparte según lo que mide cada etiqueta y por eso salían los
//    escalones. Dos columnas de la MISMA anchura dejan el borde derecho recto
//    aunque las etiquetas midan distinto. Si el número de filtros es impar, el
//    último ocupa la fila entera en vez de quedarse cojo al lado de un hueco.
// 3. **En escritorio vuelve a ser una fila que fluye.** A partir de
//    [Anchos.idioma] hay ancho de sobra y la rejilla forzada desperdiciaría
//    sitio; ahí el `Wrap` es lo correcto y además es como está hoy, que
//    funciona.
//
// Lo que esta barra NO hace: NO decide qué filtros hay ni cómo se pintan. Eso
// sigue siendo de cada pantalla y de las piezas de siempre. Aquí sólo se decide
// DÓNDE van, que es lo que estaba mal.

import 'package:flutter/material.dart';

import 'anchos.dart';
import 'tema.dart';

class BarraDeFiltros extends StatelessWidget {
  const BarraDeFiltros({
    required this.busqueda,
    this.filtros = const [],
    this.anchoCompleto = const [],
    this.acciones = const [],
    this.accionFinal,
    this.margen,
    super.key,
  });

  /// La caja de buscar. Va sola en su fila y a todo el ancho: no se le pone
  /// `ancho` —o se le pone `null`—, porque aquí quien manda es esta barra.
  final Widget busqueda;

  /// Los desplegables y pastillas, en el orden en que se leen. Van a la
  /// rejilla de dos columnas.
  final List<Widget> filtros;

  /// Los que NO caben en media columna y ocupan la fila entera: un rango de
  /// fechas —que ya son dos botones y una ✕—, un grupo de segmentos, una
  /// pastilla con un texto largo. Van debajo de la rejilla.
  ///
  /// Meterlos en la rejilla es lo que partía el rango de fechas de Pedidos en
  /// dos escalones con la ✕ colgando sola.
  final List<Widget> anchoCompleto;

  /// Los botones que hacen algo en vez de filtrar: «Agregar vehículo», «Tipos
  /// de vehículo», «Nuevo almacén». Se colocan con la MISMA regla que los
  /// filtros —rejilla de dos columnas en el teléfono— para que la pantalla no
  /// se vea distinta, pero van en su propia lista porque no son filtros y
  /// llamarlos así engañaría a quien lea esto dentro de seis meses.
  final List<Widget> acciones;

  /// Lo que va al final del todo y no es un filtro: «Limpiar», «Quitar
  /// filtros», un embudo de avanzados. Ocupa la fila entera para que no se
  /// confunda con un filtro más.
  final Widget? accionFinal;

  /// El margen lateral. Por defecto el del teléfono ([Aire.md]) y el de las
  /// pantallas grandes ([Aire.xl]), que es la regla de `Aire`.
  final EdgeInsetsGeometry? margen;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final estrecho = ancho < Anchos.idioma;

    final porDefecto = EdgeInsets.symmetric(
      horizontal: estrecho ? Aire.md : Aire.xl,
      vertical: Aire.md,
    );

    return Padding(
      padding: margen ?? porDefecto,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // EN PANTALLA ANCHA LA CAJA DE BUSCAR VA EN LA MISMA FILA QUE LOS
          // FILTROS, no en una suya.
          //
          // La primera versión la ponía siempre sola y a todo el ancho. En un
          // teléfono es lo correcto —va sola de verdad—, pero en un monitor
          // dejaba la caja de lado a lado y los filtros cayendo debajo de uno
          // en uno, gastando tres líneas para lo que cabe en una. Jose lo vio
          // enseguida: «el responsive sigue mal, mira, los filtros pasaron
          // abajo».
          if (estrecho) ...[
            busqueda,
            if (filtros.isNotEmpty) ...[
              const SizedBox(height: Aire.sm),
              _Rejilla(filtros: filtros),
            ],
          ] else
            _Fila(filtros: [busqueda, ...filtros]),
          for (final ancho in anchoCompleto) ...[
            SizedBox(height: estrecho ? Aire.sm : Aire.md),
            ancho,
          ],
          if (acciones.isNotEmpty) ...[
            SizedBox(height: estrecho ? Aire.sm : Aire.md),
            if (estrecho) _Rejilla(filtros: acciones) else _Fila(filtros: acciones),
          ],
          if (accionFinal != null) ...[
            SizedBox(height: estrecho ? Aire.sm : Aire.md),
            Align(
              alignment: estrecho ? Alignment.centerLeft : Alignment.centerRight,
              child: accionFinal,
            ),
          ],
        ],
      ),
    );
  }
}

/// Dos columnas iguales, y el impar de abajo a todo lo ancho.
///
/// Se hace con `Row`+`Expanded` y no con `GridView` a propósito: el `GridView`
/// quiere un alto fijo por celda y aquí las pastillas miden lo que miden. Con
/// `Expanded` las dos columnas salen exactamente iguales —que es lo que endereza
/// el borde derecho— sin imponer alto.
class _Rejilla extends StatelessWidget {
  const _Rejilla({required this.filtros});

  final List<Widget> filtros;

  @override
  Widget build(BuildContext context) {
    final filas = <Widget>[];

    for (var i = 0; i < filtros.length; i += 2) {
      final ultimoSuelto = i == filtros.length - 1;

      if (filas.isNotEmpty) filas.add(const SizedBox(height: Aire.sm));

      // Un filtro solo en la última fila NO se queda a media anchura con un
      // hueco al lado: eso es justo el escalón que había. Ocupa la fila entera.
      if (ultimoSuelto) {
        filas.add(SizedBox(width: double.infinity, child: filtros[i]));
        continue;
      }

      filas.add(
        // `start` y NO `stretch`: la barra vive dentro de un `ListView`, o sea
        // con alto sin acotar, y `stretch` le pide a la fila que ocupe todo lo
        // alto —que ahí es infinito— y revienta el trazado entero. Lo cazó
        // `test/diseno/barra_de_filtros_test.dart` antes de salir de aquí.
        //
        // CADA UNO SE LLEVA LO QUE MIDE, NO LA MITAD EXACTA — 28/09/2026.
        //
        // Jose, mirando Pedidos en el teléfono: «esos campos son de ese mismo
        // tamaño en vez de repartirse para que quepan todos y con su respectivo
        // tamaño». Tenía razón: «Cualquier precio» y «Todos los vendedores» no
        // miden lo mismo, y darles media caja a cada uno deja al corto con
        // hueco y al largo con los puntos suspensivos.
        //
        // `Expanded` con `flex` a lo que mide cada uno, y **`Expanded` y no
        // `Flexible`**: el reparto ya no es 50/50, pero los dos siguen llenando
        // la fila de borde a borde, que es lo que arregló el escalonado del
        // 25/09 y no se puede perder.
        //
        // Con `Flexible` —que fue el primer intento, el 28/09— cada uno se
        // queda en lo que mide su contenido y **el de la derecha deja hueco
        // hasta el borde**: vuelve el borde en sierra del que se quejaba Jose,
        // sólo que por el otro lado. Lo cazaron tres pruebas de aquí abajo
        // diciendo `Expected: <208.0>  Actual: <390.0>`, que son esos 182 px de
        // hueco. `Expanded` da las dos cosas: cada uno su tamaño, y la fila
        // entera ocupada.
        //
        // El peso se mide por los caracteres del rótulo, que es lo único que
        // esta capa sabe de un filtro: no conoce sus tipos ni tiene por qué.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: _peso(filtros[i]), child: filtros[i]),
            const SizedBox(width: Aire.sm),
            Expanded(flex: _peso(filtros[i + 1]), child: filtros[i + 1]),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: filas,
    );
  }

  /// Cuánto pesa un filtro en el reparto de su fila.
  ///
  /// Sale de la LONGITUD DE SU RÓTULO, que es lo único que esta capa sabe de un
  /// filtro: aquí no se conocen sus tipos ni hay por qué conocerlos — ver la
  /// nota de arriba sobre lo que esta barra NO hace.
  ///
  /// Con topes por los dos lados y a propósito: **sin el mínimo**, un rótulo de
  /// una palabra se quedaría tan estrecho que su propio texto saldría cortado,
  /// que es peor que el hueco que esto viene a quitar; **sin el máximo**, un
  /// vendedor con nombre largo se llevaría la fila entera y dejaría al de al
  /// lado hecho una rendija. Entre 2 y 5 el reparto va como mucho de 2 a 5, que
  /// es bastante y no es una desaparición.
  static int _peso(Widget filtro) {
    final t = _rotuloDe(filtro);
    if (t == null) return 3;
    final n = (t.length / 8).round();
    return n < 2 ? 2 : (n > 5 ? 5 : n);
  }

  /// El rótulo de un filtro, si se puede saber. `null` cuando no, y entonces
  /// pesa lo de en medio: **no se adivina**, porque un peso inventado descoloca
  /// la fila sin que nadie sepa por qué.
  static String? _rotuloDe(Widget filtro) {
    final k = filtro.key;
    if (k is ValueKey<String>) return k.value;
    return null;
  }
}

/// En escritorio, la fila que fluye de siempre.
class _Fila extends StatelessWidget {
  const _Fila({required this.filtros});

  final List<Widget> filtros;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Aire.sm,
      runSpacing: Aire.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: filtros,
    );
  }
}
