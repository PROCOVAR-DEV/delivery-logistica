// EL PRE-DESPACHO DE UNA RUTA — UNA SOLA REGLA, PARA TODAS LAS RUTAS.
//
// ## Por qué existe este fichero — issue 8 de Amado
//
// Amado: «la información de predespacho no se muestra igual cuando se crea la
// ruta manual y cuando se genera de los paneles; la que está en la manual es la
// más correcta».
//
// Y tenía razón por un motivo concreto, no por dos cálculos distintos: **el
// pre-despacho sólo existía dentro del asistente de «+ Nueva Ruta»** (paso 4,
// `_PreDespachoLateral`: la tabla producto a producto, los dos pesos y «Ver e
// imprimir»). Una ruta armada desde el tablero (`Armar la ruta de esta zona`) no
// pasa nunca por el asistente: va derecha al detalle de la ruta
// (`tablero/vista/acciones.dart`, a petición de Jose), y el detalle sólo traía la
// «Carga total» —una nube de chips `producto ×cantidad`, sin unidades, sin kg,
// sin hoja que imprimir—. Misma ruta, dos papeles: el completo si se armaba a
// mano y casi nada si se armaba desde el tablero. El servidor no interviene
// (no arma ningún pre-despacho; `GET /api/orders?resumen=1` es el de Pedidos).
//
// La salida no es copiar la tabla del asistente en el detalle: es que **el
// detalle de CUALQUIER ruta y el paso 4 llamen a la misma función**. Y ya
// existía: `ConsultasPedidos.preDespachoDe`, que suma los renglones de unos
// pedidos (empaques, unidades y los tres escalones del peso, `CLAUDE.md`
// §3-sexies). Aquí no se repite ni una de sus reglas; se le pregunta.
//
// Lo ata `test/pantallas/rutas/el_pre_despacho_de_la_ruta_test.dart`: el mismo
// juego de pedidos da las mismas líneas por el camino del asistente y por el de
// la ruta, venga ésta de donde venga.
//
// ## «Por producto y factura»
//
// La tabla nueva (`impresion/por_producto_y_factura.dart`: un bloque por
// producto, una fila por factura y su subtotal, como la hoja de Amado) sale del
// pre-despacho de CADA pedido por separado. No es un cálculo aparte: es la misma
// pregunta —`preDespachoDe`— hecha con un pedido cada vez, y la tabla sólo lo
// reparte. Así la regla de los empaques y el peso sigue siendo una, y que los
// subtotales de cada producto cuadren con la tabla de arriba se ata con una
// prueba y no con un comentario.
//
// **«La factura» es `orders.factura_numero`** (el de Ventra, `1024237`), por la misma regla
// que el tablero, Pedidos y los reportes: `NumeroDeFactura` (`nucleo/numero_de_factura.dart`).
// Antes esta tabla usaba el folio (`PTB25-261005-1479`) y caía a `factura_numero` si faltaba:
// el almacén leía en el papel un número que el resto de la aplicación no llamaba factura. Sin
// `factura_numero` la fila dice «Sin número»; NO cae al folio.
//
// **Una entrega con varias facturas (`1024237, 1024240`) es UNA fila POR FACTURA** (issue 22 de
// Maikel, Santiago, 22/10/2026: «debería hacer referencia a una única factura»; la tarjeta de
// estiba se rebaja por cantidad Y factura). Hasta entonces `order_items` no decía qué renglón
// salió de qué factura y partirla obligaba a repetir los renglones en cada una (rebajar DOS
// veces la misma mercancía), así que las dos iban juntas en una fila. Ahora cada renglón trae
// SU factura (`order_items.factura_numero`, 00026; esquema local 14) y
// `ConsultasPedidos.preDespachoPorFactura` reparte el pedido sin repetir ni perder ni un
// renglón: la suma de las partes es el pedido entero, y los subtotales siguen cuadrando con la
// tabla de arriba (lo ata `test/impresion/por_producto_y_factura_test.dart`).
//
// **Si ALGÚN renglón de la entrega no trae su factura** (los de PEDIDO, los escritos antes de la
// 00026 o los que aún no han bajado) no se parte: se queda como siempre, las facturas juntas en
// una fila. Nunca se le asigna a la primera.
//
// Funciona igual sin conexión (APK y escritorio: la base local) y en la web (su
// base en memoria, que llena la bajada): es el mismo código sobre la misma
// tabla `order_items`.

import '../../../impresion/hoja.dart' as papel;
import '../../../nucleo/base/base.dart';
import '../../../nucleo/numero_de_factura.dart';
import '../../pedidos/datos/repositorio_pedidos.dart';

/// El pre-despacho de una ruta: la tabla de producto a producto y lo que lleva
/// cada factura (el insumo de «Por producto y factura»).
class PreDespachoDeLaRuta {
  const PreDespachoDeLaRuta({required this.totales, required this.facturas});

  /// Lo mismo que enseña el paso 4 del asistente y el cajón de Pedidos.
  final TotalesPreDespacho totales;

  /// Una por parada, en el orden en que se leen ([ordenDeLasFacturas]).
  final List<papel.FacturaDelPreDespacho> facturas;
}

/// El orden de las facturas en la tabla: por número, sin distinguir mayúsculas;
/// las que no tienen número, al final, y a igualdad el orden de la parada.
///
/// ponytail: orden alfabético del texto, no natural. Con números de Ventra de ancho
/// fijo (`1024237`, siete cifras) coincide con el numérico; si algún día llegan números
/// de distinto largo («9» y «10») hay que pasar a orden natural aquí.
int ordenDeLasFacturas(Pedido a, Pedido b) {
  final na = NumeroDeFactura.de(a.facturaNumero)?.toLowerCase();
  final nb = NumeroDeFactura.de(b.facturaNumero)?.toLowerCase();
  if (na != nb) {
    if (na == null) return 1;
    if (nb == null) return -1;
    return na.compareTo(nb);
  }
  return (a.stopOrder ?? 1 << 30).compareTo(b.stopOrder ?? 1 << 30);
}

/// El pre-despacho de unas paradas. **La regla de los números es la de
/// [ConsultasPedidos.preDespachoDe]; aquí sólo se reparte.**
Future<PreDespachoDeLaRuta> preDespachoDeLaRuta(
  ConsultasPedidos pedidos,
  List<Pedido> paradas,
) async {
  final totales = await pedidos.preDespachoDe([for (final p in paradas) p.id]);

  final enOrden = [...paradas]..sort(ordenDeLasFacturas);
  final facturas = <papel.FacturaDelPreDespacho>[];
  var partidas = false;
  for (final parada in enOrden) {
    // Un pedido cada vez: una entrega ES un pedido, y su pre-despacho es el de
    // ese pedido. Son pocas paradas por ruta, y es lo que evita escribir una
    // segunda consulta con su propia copia de la regla.
    final numeros = NumeroDeFactura.separar(parada.facturaNumero);
    // Con una sola factura no hay nada que partir. `null` = no se puede sin mentir
    // (algún renglón sin su factura): sigue el camino de siempre.
    final partido = numeros.length > 1
        ? await pedidos.preDespachoPorFactura(parada.id)
        : null;
    if (partido == null) {
      final suyo = await pedidos.preDespachoDe([parada.id]);
      facturas.add(
        papel.FacturaDelPreDespacho(
          numero: NumeroDeFactura.de(parada.facturaNumero),
          lineas: lineasDelPapel(suyo),
        ),
      );
      continue;
    }
    partidas = true;
    for (final e in partido.entries) {
      facturas.add(
        papel.FacturaDelPreDespacho(
          numero: e.key,
          lineas: lineasDelPapel(e.value),
        ),
      );
    }
    // Una factura de la entrega que no trae ni un renglón (sólo domicilio) no desaparece:
    // sale «Sin renglones», igual que una factura suelta sin ellos.
    for (final n in numeros.where((n) => !partido.containsKey(n))) {
      facturas.add(papel.FacturaDelPreDespacho(numero: n, lineas: const []));
    }
  }
  // Partidas, las facturas de una parada se mezclan con las de las demás: el orden es el del
  // número, y a igualdad el de aparición.
  if (partidas) {
    final orden = {for (var i = 0; i < facturas.length; i++) facturas[i]: i};
    facturas.sort((a, b) {
      final na = a.numero?.toLowerCase();
      final nb = b.numero?.toLowerCase();
      if (na != nb) {
        if (na == null) return 1;
        if (nb == null) return -1;
        return na.compareTo(nb);
      }
      return orden[a]!.compareTo(orden[b]!);
    });
  }
  return PreDespachoDeLaRuta(totales: totales, facturas: facturas);
}

/// LAS LÍNEAS DE LA PANTALLA, PASADAS AL PAPEL. **Sólo hay esta traducción.**
///
/// Las usa la tabla de producto a producto y cada factura de «Por producto y
/// factura»; si cada una tuviera la suya, el papel podría decir una cosa arriba y
/// otra abajo.
List<papel.LineaPreDespacho> lineasDelPapel(TotalesPreDespacho totales) => [
  for (final linea in totales.lineas)
    papel.LineaPreDespacho(
      producto: linea.producto,
      formatos: linea.empaques,
      unidades: linea.unidades,
      // EL PESO VA TAL CUAL, CON SU NULO — 28/09/2026.
      //
      // Aqui habia un `?? 0` con este comentario: «en el papel el peso es
      // un numero: un producto sin peso resuelto suma cero kilos a la hoja,
      // que es lo que pesa lo que no sabemos». Era verdad cuando la hoja no
      // sabia imprimir un nulo; ya no lo es, y mientras tanto es el cero
      // creible de siempre: en el papel, `0 kg` no se distingue de un
      // producto que de verdad no pesa, y con esta hoja alguien baja al
      // almacen a cargar un camion.
      pesoKg: linea.pesoKg,
      // LOS CONTADORES VIAJAN AL PAPEL, igual que por el otro camino
      // (`pedidos/vista/pantalla_pedidos.dart`). Sin ellos esta hoja
      // imprimia la suma de lo que se sabe COMO SI FUERA EL TOTAL: el
      // mismo filtro decia `≥ 26320.0 kg (21 renglones sin peso)` en la
      // pantalla y `26320.0 kg` a secas en el papel. Dos papeles distintos
      // para lo mismo es el §3-bis, y lo que se lleva al almacen es el
      // papel.
      lineasSinUnidades: linea.lineasSinUnidades,
      lineasSinPeso: linea.lineasSinPeso,
    ),
];

/// LA HOJA DEL PRE-DESPACHO DE UNA RUTA, como funcion pura. Sirve al asistente
/// (la ruta que se va a armar) y al detalle de una ruta ya armada.
///
/// Va aparte del widget por lo mismo que su gemela de Pedidos
/// (`pedidos/vista/pantalla_pedidos.dart`, `hojaDePreDespacho`): es lo que de
/// verdad lleva los numeros al papel, y asi se comprueba sin pintar nada.
///
/// ## Por que existe: este camino imprimia OTRA hoja — 28/09/2026
///
/// Lo de aqui dentro estaba escrito a mano dentro de `_verEImprimir`, y cuando
/// el 28/09/2026 el pre-despacho cambio de regla —lo que no se sabe ya no borra
/// la fila: se imprime lo que si se sabe marcado con `≥` y con cuantos renglones
/// faltan— sólo se actualizo el camino de Pedidos. Por este otro, la misma fila
/// salia `26320.0 kg` a secas, como si fueran los kilos enteros de 4.949
/// empaques de MALTA GUAJIRA, mientras la vista del mismo cajon decia
/// `≥ 26320.0 kg (21 renglones sin peso)`. Dos papeles distintos para lo mismo
/// (`CLAUDE.md` §3-bis), y lo que baja al almacen es el papel.
///
/// Suelta, la cubre una prueba. Dentro del widget no la cubria nada.
///
/// [facturas] vacío = sin la tabla «Por producto y factura» (el paso 4 del asistente todavía
/// no tiene paradas de las que sacarla).
papel.HojaPreDespacho hojaDePreDespachoDeLaRuta({
  required TotalesPreDespacho totales,
  required String sucursal,
  required String vehiculo,
  required String? dia,
  required int pedidos,
  required double pesoKg,
  List<papel.FacturaDelPreDespacho> facturas =
      const <papel.FacturaDelPreDespacho>[],
  // Quien reparte, ya resuelto con `nombreDelDistribuidorParaLaHoja`; vacío = no consta.
  String distribuidor = '',
}) => papel.HojaPreDespacho(
  sucursal: sucursal,
  vehiculo: vehiculo,
  dia: dia,
  pedidos: pedidos,
  pesoKg: pesoKg,
  lineas: lineasDelPapel(totales),
  facturas: facturas,
  distribuidor: distribuidor,
);
