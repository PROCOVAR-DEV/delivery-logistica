/// EL NÚMERO DE FACTURA DE UN PEDIDO, EN UN SOLO SITIO — 14/10/2026.
///
/// Amado pidió «el número de factura» en el tablero, en Pedidos, en los reportes y en el
/// pre-despacho, y tres agentes lo resolvieron con criterios distintos: el tablero y Pedidos
/// enseñaban el número de Ventra, y los reportes y el pre-despacho el folio. La misma
/// pantalla de Reparto decía `1024237` en un sitio y `PTB25-261005-1479` en otro **para el
/// mismo pedido**. Decisión de Jose: «factura» es `orders.factura_numero` en TODA la app, y
/// aquí se decide, una vez. Nadie más lo repite: tablero, Pedidos, Reportes (pantalla y Excel)
/// y la tabla «Por factura» llaman a [NumeroDeFactura.de].
///
/// ## QUÉ ES «EL NÚMERO DE FACTURA»: `orders.factura_numero`, NO `operation_number`
///
/// Hay dos números en el pedido y no son lo mismo:
///
///  * **`operation_number`** es el FOLIO DEL PEDIDO en PEDIDO (`PTB25-261005-1479`,
///    `pedido.folio`). Es lo que desde el 07/10/2026 se llama «conduce» (Jose: «el conduce
///    es el número de operación de la factura») y ya es el título de cada tarjeta y de
///    cada rechazo. Existe desde que el pedido se toma, antes de facturar. **Sigue visible
///    donde estaba, con su rótulo de siempre; pero no es «la factura».**
///  * **`factura_numero`** es el número de la FACTURA de Ventra: el `operNumber` de las
///    líneas facturadas (`1024237`; varias líneas lo comparten, y si el pedido se cubrió
///    con más de una factura PEDIDO las junta con coma: `1024237, 1024240`). Lo escribe el
///    cotejo de PEDIDO (`cotejarFactura.ts`: `numero = [...new Set(operNumber)].sort().join(', ')`)
///    y por eso no existe hasta que el pedido se factura.
///
/// **Sin `factura_numero` NO HAY NÚMERO, y no se cae al folio.** Caer al folio es justo lo
/// que hacía que una pantalla dijera `1024237` y otra `PTB25-261005-1479`: cada pedido sin
/// factura enseñaría un número de otra clase, y nadie lo distinguiría a simple vista. Cada
/// sitio dice a su manera que falta (`—`, «Sin número»), pero ninguno inventa.
///
/// ## Lo que hace con el texto
///
///  * Quita los blancos de los extremos —los de Unicode también: NBSP, tabulador y el BOM
///    `U+FEFF`, que es lo que `trim()` de Dart quita— y vacío o en blanco es «falta».
///  * Quita la comilla de Excel (`'1024237`): `a_mano/comilla_de_excel.sql` lista
///    `factura_numero` entre las columnas que pudieron bajar con ella. El servidor ya la
///    limpia al entrar, pero lo que bajó antes sigue en la base de este aparato
///    (`texto_de_fuera.dart`).
///  * Varias facturas (`1024237, 1024240`) se dicen tal cual, normalizadas a coma y espacio
///    como las escribe PEDIDO. [separar] las da una a una para quien las cuenta o las junta
///    (la lista de un camión en los reportes).
///
/// ## Dos escritos, atados por un fichero (CLAUDE.md §3-bis)
///
/// La regla vive también en Go (`api/internal/api/informes.go`, `numeroDeFactura`,
/// `numerosDeFactura` y `agruparFacturas`), porque `GET /api/reports` contesta lo mismo que
/// arma el informe con la base local. Los dos leen `docs/numero-de-factura.casos.json`: si
/// alguien cambia un lado, el otro se pone rojo.
library;

import 'dart:math' show min;

import 'texto_de_fuera.dart' show sinLaComillaDeExcelODejarlo;

/// Los números de factura de un grupo de pedidos: los que hay, sin repetir y en el
/// orden en que aparecen, y cuántos pedidos se quedaron sin número.
typedef FacturasDeUnGrupo = ({List<String> facturas, int sinFactura});

abstract final class NumeroDeFactura {
  /// Las facturas de [crudo] (el `factura_numero` tal como está en la base), una a una,
  /// sin blancos ni comilla de Excel. Vacío si no hay ninguna.
  ///
  /// Se parte por la coma: `1024237, 1024240` son DOS facturas. Un trozo vacío
  /// (`1024237,, 1024240`) no es una factura y se descarta.
  static List<String> separar(String? crudo) {
    final sinComilla = sinLaComillaDeExcelODejarlo(crudo?.trim());
    if (sinComilla == null) return const <String>[];
    return [
      for (final trozo in sinComilla.split(','))
        if (trozo.trim().isNotEmpty) trozo.trim(),
    ];
  }

  /// El número de factura que se enseña, o `null` si el pedido no tiene. Es [separar]
  /// vuelto a juntar con `, `: el texto del pedido y sus facturas sueltas no se pueden
  /// separar, porque uno sale del otro.
  static String? de(String? crudo) {
    final facturas = separar(crudo);
    return facturas.isEmpty ? null : facturas.join(', ');
  }

  /// Junta los [numeros] de los pedidos de un camión (o de lo que sea que se agrupe), crudos
  /// o ya pasados por [de]: da igual, [separar] es idempotente. Cada factura cuenta UNA vez
  /// —la ida y la vuelta del mismo pedido llevan la misma— y en el orden de aparición. Un
  /// pedido sin ninguna no se descarta: se cuenta en `sinFactura`, para que quien lea la
  /// fila sepa que le falta alguno.
  ///
  /// **No toca las cuentas de órdenes ni los totales**: es sólo la lista de referencias.
  static FacturasDeUnGrupo agrupar(Iterable<String?> numeros) {
    final vistos = <String>{};
    final facturas = <String>[];
    var sinFactura = 0;
    for (final numero in numeros) {
      final suyas = separar(numero);
      if (suyas.isEmpty) sinFactura++;
      for (final factura in suyas) {
        if (vistos.add(factura)) facturas.add(factura);
      }
    }
    return (facturas: facturas, sinFactura: sinFactura);
  }

  /// Cómo se dice en una celda la lista de un camión.
  ///
  /// [visibles] `null` = todas (el Excel, que tiene sitio). Con un tope (la
  /// pantalla) se dicen las primeras y **cuántas quedan fuera**: cortar la lista
  /// sin decirlo es esconder facturas. Los pedidos sin número se dicen aparte.
  /// Sin nada que decir, la raya.
  ///
  /// [maxCaracteres] es el techo de una celda de Excel (32.767 letras): una hoja
  /// con una celda más larga NO ABRE («contenido ilegible»), y es peor que una
  /// lista cortada que lo dice. Se corta por números enteros, nunca a mitad de
  /// uno.
  static String texto(
    FacturasDeUnGrupo grupo, {
    String separador = ', ',
    int? visibles,
    int? maxCaracteres,
  }) {
    final todas = grupo.facturas;
    var cuantas = visibles == null ? todas.length : min(visibles, todas.length);
    if (maxCaracteres != null) {
      var largo = 0;
      for (var i = 0; i < cuantas; i++) {
        largo += todas[i].length + separador.length;
        if (largo > maxCaracteres) {
          cuantas = i;
          break;
        }
      }
    }
    final partes = <String>[];
    if (todas.isNotEmpty) {
      final resto = todas.length - cuantas;
      partes.add(
        [
          if (cuantas > 0) todas.take(cuantas).join(separador),
          if (resto > 0) (cuantas > 0 ? 'y $resto más' : '$resto facturas'),
        ].join(' '),
      );
    }
    if (grupo.sinFactura > 0) partes.add('${grupo.sinFactura} sin número');
    return partes.isEmpty ? '—' : partes.join(' · ');
  }
}
