// Los 9 filtros de la pantalla de Pedidos, tal y como los define el pliego
// (../../../../docs/pantallas.md §2) y con los MISMOS valores de parametro que
// manda el servidor (../../../../docs/contratos-api.md, «Filtros compartidos»).
//
// Van en su propio fichero, como datos puros y sin Flutter dentro, porque son
// tres cosas a la vez: lo que pinta la barra de filtros, lo que traduce el
// repositorio a SQL y lo que se compara en las pruebas de paridad contra la de
// Next. Si vivieran dentro del widget no se podrian probar sin pintar.

import 'package:flutter/foundation.dart' show immutable;

/// `reparto` — el estado de reparto EN DELIVERY. Manda `resultado` de la parada,
/// nunca el estado de la ruta: una ruta completada no convierte en entregado un
/// pedido que volvio.
enum RepartoFiltro {
  cualquiera('', 'Cualquier reparto'),
  sinEntregar('sin_entregar', 'Sin entregar'),
  enDespacho('en_despacho', 'En despacho'),
  enRuta('en_ruta', 'En ruta'),
  entregado('entregado', 'Entregado'),
  devuelto('devuelto', 'Devuelto o cancelado');

  const RepartoFiltro(this.param, this.etiqueta);

  final String param;
  final String etiqueta;
}

/// `factura` — `con_factura` admite `igual` y `cambiado`; `cuadra` sólo `igual`.
/// La diferencia importa: el armador de rutas exige `cuadra` y esta pantalla
/// arranca en `con_factura`.
enum FacturaFiltro {
  cualquiera('', 'Cualquier factura'),
  conFactura('con_factura', 'Con factura'),
  cuadra('cuadra', 'Sólo lo que cuadra'),
  sinCotejar('sin_cotejar', 'Sin cotejar');

  const FacturaFiltro(this.param, this.etiqueta);

  final String param;
  final String etiqueta;
}

/// `archivado` — NO es un booleano de tres estados por gusto: «cualquiera» es
/// distinto de «no archivado», y el arranque acotado depende de poder decir
/// exactamente `0`.
enum ArchivadoFiltro {
  cualquiera('', 'Archivados y sin archivar'),
  no('0', 'Sin archivar'),
  si('1', 'Sólo archivados');

  const ArchivadoFiltro(this.param, this.etiqueta);

  final String param;
  final String etiqueta;
}

/// `cotizado` — si Entrega ya le puso costo de domicilio.
enum CotizadoFiltro {
  cualquiera('', 'Cualquier precio'),
  conPrecio('1', 'Con precio puesto'),
  sinCotizar('0', 'Sin cotizar');

  const CotizadoFiltro(this.param, this.etiqueta);

  final String param;
  final String etiqueta;
}

/// `Cómo se ordena esta página`.
///
/// **Ordena SÓLO la pagina visible**, no la consulta. Es lo que hace la de Next
/// y es deliberado: el orden de la consulta lo fija el servidor
/// (`orderDate desc nulls last, createdAt desc`) y cambiarlo aqui haria que dos
/// paginas consecutivas ensenaran el mismo pedido dos veces.
enum OrdenLocal {
  recientes('recientes', 'Más recientes'),
  antiguos('antiguos', 'Más antiguos'),
  precioDesc('precio_desc', 'Precio: mayor a menor'),
  precioAsc('precio_asc', 'Precio: menor a mayor'),
  distanciaDesc('distancia_desc', 'Distancia: más larga'),
  pesoDesc('peso_desc', 'Peso: mayor');

  const OrdenLocal(this.valor, this.etiqueta);

  final String valor;
  final String etiqueta;
}

/// El juego completo de filtros de la pantalla.
///
/// Inmutable y con `==` de verdad porque es el argumento de los providers de
/// Riverpod: sin `==` cada reconstruccion del widget crearia un provider nuevo y
/// la pantalla volveria a consultar sin que nada hubiera cambiado.
@immutable
class FiltrosPedidos {
  /// El arranque de la pantalla: **acotado a lo que puede subir a un camion**.
  /// Mientras estos dos sigan exactamente asi se pinta la franja azul.
  const FiltrosPedidos({
    this.q = '',
    this.reparto = RepartoFiltro.cualquiera,
    this.municipio = '',
    this.vendedor = '',
    this.cotizado = CotizadoFiltro.cualquiera,
    this.factura = FacturaFiltro.conFactura,
    this.archivado = ArchivadoFiltro.no,
    this.desde,
    this.hasta,
    this.entregadoDesde,
    this.entregadoHasta,
    this.orden = OrdenLocal.recientes,
    this.pagina = 1,
  });

  /// Sin ningun filtro puesto. Es lo que deja `Ver todos los pedidos` en los dos
  /// del arranque y `quitarlos todos` en los nueve.
  const FiltrosPedidos.sinNada()
    : q = '',
      reparto = RepartoFiltro.cualquiera,
      municipio = '',
      vendedor = '',
      cotizado = CotizadoFiltro.cualquiera,
      factura = FacturaFiltro.cualquiera,
      archivado = ArchivadoFiltro.cualquiera,
      desde = null,
      hasta = null,
      entregadoDesde = null,
      entregadoHasta = null,
      orden = OrdenLocal.recientes,
      pagina = 1;

  final String q;
  final RepartoFiltro reparto;
  final String municipio;
  final String vendedor;
  final CotizadoFiltro cotizado;
  final FacturaFiltro factura;
  final ArchivadoFiltro archivado;

  /// `desde`/`hasta` son dias naturales sobre la FECHA DEL PEDIDO. `hasta`
  /// incluye el dia entero (hasta 23:59:59.999), que es como lo hace el
  /// servidor.
  final DateTime? desde;
  final DateTime? hasta;

  /// LA OTRA FECHA, Y NO ES LA MISMA: el dia en que el pedido SE ENTREGO
  /// (`delivered_at`), no el dia en que se hizo.
  ///
  /// Nacio el 28/09/2026 y de un caso concreto: el Panel decia «Entregados hoy:
  /// 1» y no habia forma de llegar a ese pedido. Con [desde]/[hasta] no se podia
  /// pedir —acotan por la fecha DEL PEDIDO— y justo el caso de Jose lo enseña:
  /// el `POR26-260925-3700` es un pedido **del 25** entregado **el 28**, asi que
  /// «del 28 al 28» sobre la fecha del pedido lo deja fuera. Dos preguntas
  /// parecidas y distintas, cada una con su par de fechas.
  ///
  /// Dias naturales, igual que las otras dos: [entregadoDesde] desde las 00:00 y
  /// [entregadoHasta] hasta las 23:59:59.999.
  final DateTime? entregadoDesde;
  final DateTime? entregadoHasta;

  final OrdenLocal orden;
  final int pagina;

  /// Cuando los dos filtros del arranque siguen intactos. Es la condicion
  /// LITERAL de la franja azul del pliego.
  bool get arranqueAcotado =>
      factura == FacturaFiltro.conFactura && archivado == ArchivadoFiltro.no;

  /// ¿Hay algo puesto? Decide si debajo del estado vacio sale el boton de
  /// quitarlos todos.
  bool get hayAlguno =>
      q.isNotEmpty ||
      reparto != RepartoFiltro.cualquiera ||
      municipio.isNotEmpty ||
      vendedor.isNotEmpty ||
      cotizado != CotizadoFiltro.cualquiera ||
      factura != FacturaFiltro.cualquiera ||
      archivado != ArchivadoFiltro.cualquiera ||
      desde != null ||
      hasta != null ||
      entregadoDesde != null ||
      entregadoHasta != null;

  /// Cualquier cambio de filtro vuelve a la pagina 1: quedarse en la 7 de una
  /// lista que ahora tiene 2 paginas es una pantalla vacia sin motivo.
  FiltrosPedidos copiarCon({
    String? q,
    RepartoFiltro? reparto,
    String? municipio,
    String? vendedor,
    CotizadoFiltro? cotizado,
    FacturaFiltro? factura,
    ArchivadoFiltro? archivado,
    DateTime? desde,
    bool limpiarDesde = false,
    DateTime? hasta,
    bool limpiarHasta = false,
    DateTime? entregadoDesde,
    bool limpiarEntregadoDesde = false,
    DateTime? entregadoHasta,
    bool limpiarEntregadoHasta = false,
    OrdenLocal? orden,
    int? pagina,
  }) {
    final cambioUnFiltro =
        q != null ||
        reparto != null ||
        municipio != null ||
        vendedor != null ||
        cotizado != null ||
        factura != null ||
        archivado != null ||
        desde != null ||
        hasta != null ||
        entregadoDesde != null ||
        entregadoHasta != null ||
        limpiarDesde ||
        limpiarHasta ||
        limpiarEntregadoDesde ||
        limpiarEntregadoHasta;

    return FiltrosPedidos(
      q: q ?? this.q,
      reparto: reparto ?? this.reparto,
      municipio: municipio ?? this.municipio,
      vendedor: vendedor ?? this.vendedor,
      cotizado: cotizado ?? this.cotizado,
      factura: factura ?? this.factura,
      archivado: archivado ?? this.archivado,
      desde: limpiarDesde ? null : (desde ?? this.desde),
      hasta: limpiarHasta ? null : (hasta ?? this.hasta),
      entregadoDesde: limpiarEntregadoDesde
          ? null
          : (entregadoDesde ?? this.entregadoDesde),
      entregadoHasta: limpiarEntregadoHasta
          ? null
          : (entregadoHasta ?? this.entregadoHasta),
      orden: orden ?? this.orden,
      pagina: pagina ?? (cambioUnFiltro ? 1 : this.pagina),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FiltrosPedidos &&
          other.q == q &&
          other.reparto == reparto &&
          other.municipio == municipio &&
          other.vendedor == vendedor &&
          other.cotizado == cotizado &&
          other.factura == factura &&
          other.archivado == archivado &&
          other.desde == desde &&
          other.hasta == hasta &&
          other.entregadoDesde == entregadoDesde &&
          other.entregadoHasta == entregadoHasta &&
          other.orden == orden &&
          other.pagina == pagina;

  @override
  int get hashCode => Object.hash(
    q,
    reparto,
    municipio,
    vendedor,
    cotizado,
    factura,
    archivado,
    desde,
    hasta,
    entregadoDesde,
    entregadoHasta,
    orden,
    pagina,
  );

  @override
  String toString() =>
      'FiltrosPedidos(q: $q, reparto: ${reparto.param}, municipio: $municipio, '
      'vendedor: $vendedor, cotizado: ${cotizado.param}, '
      'factura: ${factura.param}, archivado: ${archivado.param}, '
      'desde: $desde, hasta: $hasta, '
      'entregadoDesde: $entregadoDesde, entregadoHasta: $entregadoHasta, '
      'orden: ${orden.valor}, pagina: $pagina)';
}

/// El conteo de la cabecera, literal del pliego: `<total> pedidos`, con el rango
/// de fechas si lo hay y siempre `, del más nuevo al más viejo`.
///
/// Va aqui, como funcion pura sobre los filtros, porque es un texto que se
/// compara caracter a caracter con el de Next y no quiero tener que pintar la
/// pantalla para comprobarlo.
String textoDelConteo(
  int total,
  FiltrosPedidos f,
  String Function(DateTime) dia,
) {
  // «1 pedidos» en la cabecera — 28/09/2026. Mismo patrón que las rutas
  // («3 paradas» / «1 parada»), y el CERO en plural: «0 pedidos».
  final partes = StringBuffer('$total ${total == 1 ? 'pedido' : 'pedidos'}');
  final desde = f.desde;
  final hasta = f.hasta;
  if (desde != null && hasta != null) {
    partes.write(
      desde == hasta
          ? ' · del ${dia(desde)}'
          : ' · del ${dia(desde)} al ${dia(hasta)}',
    );
  } else if (desde != null) {
    partes.write(' · desde el ${dia(desde)}');
  } else if (hasta != null) {
    partes.write(' · hasta el ${dia(hasta)}');
  }
  // Y LA OTRA FECHA SE DICE APARTE, con el verbo delante.
  //
  // Sin esto, `/orders?entregado_desde=2026-09-28` enseña «1 pedidos, del más
  // nuevo al más viejo» y nada dice por qué hay uno y no doce mil: un número
  // acotado que se lee como el total. Y no se puede juntar con el rango de
  // arriba porque no son lo mismo —una acota por la fecha DEL PEDIDO y la otra
  // por la de la ENTREGA—, que es justo la confusión que esto viene a cerrar.
  final entregadoDesde = f.entregadoDesde;
  final entregadoHasta = f.entregadoHasta;
  if (entregadoDesde != null && entregadoHasta != null) {
    partes.write(
      entregadoDesde == entregadoHasta
          ? ' · entregados el ${dia(entregadoDesde)}'
          : ' · entregados del ${dia(entregadoDesde)} '
                'al ${dia(entregadoHasta)}',
    );
  } else if (entregadoDesde != null) {
    partes.write(' · entregados desde el ${dia(entregadoDesde)}');
  } else if (entregadoHasta != null) {
    partes.write(' · entregados hasta el ${dia(entregadoHasta)}');
  }
  partes.write(', del más nuevo al más viejo');
  return partes.toString();
}

/// LOS FILTROS DE «Entregados hoy» DEL PANEL, en un solo sitio.
///
/// El 28/09/2026 Jose miró el Panel: «me dice q entregado uno y en hsitorial me
/// sale vacio eso q se entrego si no se ah completado nada». Los números estaban
/// bien —el pedido se entregó a las 19:44 en una ruta que sigue **en curso**, y
/// el Historial cuenta RUTAS cerradas—, pero la tarjeta no dejaba llegar al
/// pedido, y entonces la única salida era preguntar.
///
/// Esta función es la mitad de pantalla del enlace; la otra mitad es la consulta
/// del Panel (`panel/datos/consultas_panel.dart`, `entregados_hoy`). **Tienen
/// que contar lo mismo**, y por eso están atadas con una prueba y no con un
/// comentario (`CLAUDE.md` §3-bis):
/// `test/pantallas/pedidos/entregados_hoy_cuadra_test.dart`.
///
/// Las dos trampas que hacen que cuadre, y las dos se ven aquí:
///
///  * **se parte de [FiltrosPedidos.sinNada], no del arranque**. El arranque
///    acota a `con_factura` + `sin archivar` y el contador del Panel no mira
///    ninguna de las dos: con el arranque, un pedido archivado entregado hoy
///    saldría en la tarjeta y no en la lista, que es el §3-bis otra vez;
///  * **sólo [FiltrosPedidos.entregadoDesde], sin `hasta`**. El contador es
///    `delivered_at >= medianoche` y no tiene techo; ponerle uno al filtro
///    dejaría fuera un `delivered_at` adelantado —el reloj del aparato del
///    repartidor no es el de este— y la lista diría 0 debajo de un 1.
///
/// El alcance (la sucursal de arriba) NO va aquí: lo pone
/// `sucursalMiradaProvider`, que es el mismo en las dos pantallas y no se pierde
/// al navegar. Meterlo en el enlace sería tener dos formas de decir lo mismo.
FiltrosPedidos filtrosDeEntregadosDesde(DateTime medianoche) =>
    const FiltrosPedidos.sinNada().copiarCon(
      // El día pelado. La hora la pone la consulta (00:00), y así el enlace que
      // se escribe en la dirección —`AAAA-MM-DD`— vuelve a leerse igual: el
      // viaje de ida y vuelta por la URL no puede cambiar lo que se cuenta.
      entregadoDesde: DateTime(
        medianoche.year,
        medianoche.month,
        medianoche.day,
      ),
    );
