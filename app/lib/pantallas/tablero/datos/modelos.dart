import '../../../nucleo/base/base.dart';

/// El punto desde el que se mide la cercania: el almacen principal de la
/// sucursal (§3 «De donde sale la distancia»).
class AlmacenOrigen {
  const AlmacenOrigen({
    required this.id,
    required this.nombre,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String nombre;
  final double lat;
  final double lng;
}

/// UN ALMACEN DE LA SUCURSAL, PARA PODER ELEGIRLO — 26/09/2026.
///
/// Es la lista que se ensena al tocar la cabecera del tablero, y lleva **todos**
/// los de la sucursal, tambien los que no tienen la ubicacion puesta.
///
/// ## Por que los que no sirven tambien salen
///
/// Hasta hoy cada sucursal tenia un almacen en Accesos y se llamaba como la
/// sucursal. Jose dio de alta los 14 de verdad, leidos de Ventra, y **seis de
/// ellos estan sin coordenadas a proposito**: las ponen los logisticos de cada
/// sucursal. O sea que «existe pero le falta la ubicacion» es el estado normal
/// de estos dias, no una averia.
///
/// Con la lista filtrada por «los que sirven», esos seis desaparecian en
/// silencio y quien mira no se enteraba de que su sucursal tiene un almacen a
/// medio dar de alta. Eso es el §4 del `CLAUDE.md`: **nada se descarta en
/// silencio**. Jose, 26/09/2026: «hace falta que aparezca por lo menos y diga
/// que no esta configurado el que no tiene la ubicacion puesta».
///
/// Y la otra mitad, que es la que cuesta dinero: **el que no tiene ubicacion no
/// se puede elegir**. De los kilometros desde el almacen sale el costo del
/// domicilio, asi que medir desde un punto que no existe da un numero creible y
/// equivocado — el fallo que mas caro sale aqui. Que exista y que le falte algo
/// son dos cosas distintas, y las dos hay que ensenarlas.
class AlmacenDeLaSucursal {
  const AlmacenDeLaSucursal({
    required this.id,
    required this.nombre,
    required this.principal,
    required this.sirveParaMedir,
  });

  final String id;
  final String nombre;

  /// El que Accesos marca como principal. Es el que se elige solo cuando nadie
  /// ha elegido nada.
  final bool principal;

  /// `false` = **le falta la ubicacion**, asi que no hay desde donde medir y no
  /// se puede elegir. Las condiciones enteras —y por que cada una— viven en
  /// `nucleo/almacenes/almacen_de_referencia.dart`, en un solo sitio: tres
  /// pantallas hacen esta misma pregunta y el 22/09/2026 contestaban tres cosas
  /// distintas de la misma sucursal.
  final bool sirveParaMedir;

  /// El motivo, en palabras de la casa, para quien ve la fila apagada. Se guarda
  /// como texto y no como un enum porque es lo que se lee en la pantalla, y
  /// «sin ubicación configurada» es exactamente lo que Jose pidió que dijera.
  static const sinUbicacion = 'sin ubicación configurada';
}

/// La sucursal no tiene ningun almacen con coordenadas: **no hay tablero**.
///
/// No se ordena por un punto inventado ni por las coordenadas de la sucursal,
/// que no son el sitio del que sale la mercancia. El mensaje es literal, el
/// mismo que devuelve el servidor con su 409.
class SinAlmacenConCoordenadas implements Exception {
  const SinAlmacenConCoordenadas(this.sucursal) : noHaBajado = false;

  /// LO QUE NO SE SABE NO ES LO MISMO QUE LO QUE FALTA — 22/09/2026.
  ///
  /// Este aparato no ha descargado los almacenes todavia, asi que **no hay nada
  /// que le permita decir que la sucursal no tiene almacen**. Decirlo igual es
  /// mandar a alguien a dar de alta lo que ya existe, y en la web —donde la base
  /// nace vacia en cada carga y se vuelve a llenar en cada ciclo— salia cada vez
  /// que la copia se estaba rehaciendo: la pantalla en blanco acusando a La
  /// Habana de no tener el almacen que dos segundos antes ensenaba arriba.
  ///
  /// Es el mismo `ComoVa.sinSaber` que el paso a paso del Panel ya distinguia, y
  /// por eso el Panel decia ✓ donde el Tablero decia que no.
  const SinAlmacenConCoordenadas.todaviaNoHaBajado(this.sucursal)
    : noHaBajado = true;

  final String sucursal;

  /// `true` = no se miro, porque los almacenes no han llegado a este aparato.
  final bool noHaBajado;

  String get mensaje => noHaBajado
      ? 'Los almacenes todavía no han llegado a este aparato, así que no se '
            'sabe desde dónde medir. No es que $sucursal no lo tenga puesto: es '
            'que no ha bajado. Vuelve a intentarlo en un momento.'
      : '$sucursal no tiene ningún almacén con coordenadas';

  @override
  String toString() => mensaje;
}

/// Todavia no se ha elegido sucursal. **No se ensena «todo»**, que es lo que
/// pareceria razonable y seria lo peor: un tablero con las diez mezcladas
/// ordenaria los pedidos de Holguin por su distancia al almacen de Santiago.
class FaltaElegirSucursal implements Exception {
  const FaltaElegirSucursal();

  String get mensaje => 'Elige una sucursal para ver su tablero';

  @override
  String toString() => mensaje;
}

/// El servidor —o la base local, que aqui manda igual— dijo que no, con un
/// motivo que se le puede ensenar a una persona tal cual.
class RechazoDelTablero implements Exception {
  const RechazoDelTablero(
    this.mensaje, {
    this.pedidos,
    this.detalles = const <String>[],
  });

  final String mensaje;

  /// Cuantos pedidos hay dentro, cuando el motivo es ese (§7.6).
  final int? pedidos;

  /// Quien se cayo y POR QUE, NOMBRADOS. Una columna de doce que produce una
  /// ruta de nueve sin explicacion es la manera mas rapida de que el logistico
  /// deje de fiarse del tablero (§5.2).
  final List<String> detalles;

  @override
  String toString() => mensaje;
}

/// Una columna del tablero, con sus totales.
///
/// Los totales los da la base y NO la suma de lo pintado: la pantalla pagina y
/// el camion no. Con 60 pedidos puestos, sumar lo que se ve en el movil da el
/// peso de los 20 primeros y el aviso de que no cabe no apareceria nunca.
class ColumnaTablero {
  const ColumnaTablero({
    required this.id,
    required this.branchId,
    required this.nombre,
    required this.posicion,
    required this.pedidos,
    required this.pesoKg,
    required this.costoUsd,
    this.vehiculoId,
    this.vehiculoNombre,
    this.vehiculoMatricula,
    this.vehiculoCapacidad,
    this.sinSubir = false,
    this.rechazada = false,
  });

  final String id;
  final String branchId;
  final String nombre;
  final int posicion;
  final String? vehiculoId;
  final String? vehiculoNombre;
  final String? vehiculoMatricula;
  final double? vehiculoCapacidad;
  final int pedidos;
  final double pesoKg;
  final double costoUsd;

  /// Le queda algo por subir: la propia zona, o un cambio suyo.
  final bool sinSubir;

  /// El servidor dijo que no a algo de esta zona y espera a que alguien decida.
  final bool rechazada;

  /// `null` **no es `false`**: sin camion previsto todavia no se sabe si cabe, y
  /// pintar «cabe» cuando nadie ha dicho en que va es peor que no pintar nada
  /// (§7.3).
  bool? get excedeCamion {
    final capacidad = vehiculoCapacidad;
    if (capacidad == null) return null;
    return pesoKg > capacidad;
  }

  /// ¿Le falta llegar arriba?
  ///
  /// **Sale de la cola, no del id**, y ese cambio es del 16/09/2026. Antes era
  /// `id.startsWith('local-')`, que dejo de significar nada el dia que el aparato
  /// empezo a poner el id definitivo —un UUIDv7— al crear la zona, este o no
  /// este arriba.
  ///
  /// Y el prefijo nunca supo contar la otra mitad: una zona que subio y que
  /// despues se renombro sin senal tambien tiene trabajo sin subir, y con el id
  /// de verdad puesto se daba por entregada.
  bool get faltaPorSubir => sinSubir || rechazada;
}

/// Por que una tarjeta dejo de servir. **Se marca, no se esconde** (§7.2).
enum MarcaTarjeta {
  /// PEDIDO lo dio de baja con la tarjeta puesta.
  archivado('Archivado en PEDIDO', grave: true),

  /// Se lo llevo otra ruta: el Super Admin, o el armador de siempre desde otro
  /// aparato.
  enOtraRuta('Ya va en otra ruta', grave: true),

  /// `factura_estado` NULL. **No es «cuadra»**: es «no se sabe». Con un NULL
  /// colado se armo una ruta sin facturar el 2/09.
  sinCotejar('Sin cotejar', grave: true),

  /// No hay nada que llevar: hoy no sale.
  sinFactura('Sin factura', grave: true),

  /// Se facturo distinto de como se pidio. **Tampoco sale** —Jose, 07/10/2026:
  /// «en el camion solo sube lo que cuadra con la factura»; el servidor lo
  /// descarta en `armarRutaDeColumna` con «cambió en la factura»— y por eso es
  /// grave: hasta 1.0.28 estaba en ambar, el armado local lo subia y la ruta
  /// salia con una factura que ya no era la que se cargo.
  cambiado('Cambió en la factura', grave: true);

  const MarcaTarjeta(this.texto, {required this.grave});

  final String texto;

  /// En rojo lo que hoy NO sale en un camion; en ambar, si algun dia hay algo
  /// que se avisa pero sale (hoy no queda ninguna marca asi).
  final bool grave;
}

/// Lo comun a las dos mitades: una tarjeta de pedido.
class TarjetaPedido {
  const TarjetaPedido({
    required this.pedidoId,
    required this.customerName,
    required this.address,
    required this.weight,
    required this.kmAlAlmacen,
    required this.mismoCliente,
    this.operationNumber,
    this.customerPhone,
    this.pedidoCosto,
    this.municipio,
    this.vendedor,
    this.orderDate,
    this.facturaEstado,
    this.facturaDomicilio,
    this.archivado = false,
    this.rutaId,
    this.resultado,
    this.deliveredAt,
  });

  final String pedidoId;
  final String? operationNumber;
  final String customerName;
  final String? customerPhone;
  final String address;
  final double weight;
  final double? pedidoCosto;
  final String? municipio;
  final String? vendedor;
  final DateTime? orderDate;
  final String? facturaEstado;

  /// Lo que la factura cobro de domicilio. `null` y cero son lo mismo aqui:
  /// «no esta cobrado» (ver [motivoDeNoSubir]).
  final double? facturaDomicilio;
  final bool archivado;
  final String? rutaId;
  final String? resultado;
  final DateTime? deliveredAt;
  final double kmAlAlmacen;

  /// Cuantos pedidos hay hoy de este mismo cliente. **No se funden las
  /// tarjetas**: X-2992 y X-2992-2 son dos pedidos, con sus renglones, su peso
  /// y su costo de domicilio cada uno; juntarlos porque coincide el cliente es
  /// repetir el error de julio —dos facturas, un solo bulto cargado—. Lo unico
  /// que hace la pantalla es decirlo, para que el logistico los meta en la
  /// misma columna a proposito y no por casualidad (§7.1).
  final int mismoCliente;

  /// Las marcas, de la mas grave a la menos. Una tarjeta puede llevar varias:
  /// un pedido archivado y sin facturar es las dos cosas.
  List<MarcaTarjeta> get marcas => <MarcaTarjeta>[
    if (archivado) MarcaTarjeta.archivado,
    if (rutaId != null) MarcaTarjeta.enOtraRuta,
    if (facturaEstado == null) MarcaTarjeta.sinCotejar,
    if (facturaEstado == EstadoFactura.sinFactura) MarcaTarjeta.sinFactura,
    if (facturaEstado == EstadoFactura.cambiado) MarcaTarjeta.cambiado,
  ];

  /// POR QUE ESTA TARJETA NO SUBE A UNA RUTA, o `null` si sube.
  ///
  /// Es la regla de entrada de `armarRutaDeColumna` (`api/internal/api/
  /// tablero.go`), **la misma y con las mismas palabras**: sin senal el que dice
  /// «no» es el telefono, y si dos lados discrepan la misma zona arma una ruta
  /// con conexion y otra distinta sin ella. Hasta 1.0.28 el aparato solo miraba
  /// las marcas graves y armaba con lo que el servidor descarta: domicilio sin
  /// cobrar, sin cotizar y `cambiado` (Amado, 07/10/2026, incidencia 6).
  ///
  /// Solo entra lo facturado y que cuadre (`igual`; `cambiado` NO), con
  /// `facturaDomicilio > 0` y `pedidoCosto` no nulo. Las marcas conservan su
  /// texto de siempre; los dos de domicilio son los del servidor, letra por
  /// letra (`docs/armado-rechazado.casos.json`, `descartadosDelTablero`).
  ///
  /// `ya se entregó` va aqui aunque el servidor lo pregunte primero: al armar,
  /// el aparato deja a `null` el resultado del pedido (reasignar un devuelto es
  /// un intento nuevo), y sin esta guarda borraria una entrega de verdad.
  String? get motivoDeNoSubir {
    for (final m in marcas) {
      if (m.grave) return m.texto;
    }
    if (deliveredAt != null || resultado == ResultadoParada.entregado) {
      return 'ya se entregó';
    }
    final domicilio = facturaDomicilio;
    if (domicilio == null || domicilio <= 0) {
      return 'la factura no tiene domicilio cobrado';
    }
    if (pedidoCosto == null) return 'domicilio sin cotizar';
    return null;
  }

  /// ¿Se puede repartir hoy? Es la pregunta del armador (§5.2), no la de si se
  /// ensena: lo que no se puede repartir se ensena igual, marcado.
  bool get repartible => motivoDeNoSubir == null;
}

/// Una tarjeta YA COLOCADA, con la columna y el sitio en el que esta.
class TarjetaColocada {
  const TarjetaColocada({
    required this.pedido,
    required this.columnaId,
    required this.posicion,
    this.colocadoAt,
  });

  final TarjetaPedido pedido;
  final String columnaId;

  /// El orden de visita que propone el logistico, el que conoce las calles.
  final int posicion;
  final DateTime? colocadoAt;
}

/// Los contadores de arriba. **Tres y no uno**: «lo archivaron en PEDIDO», «se
/// lo llevo otra ruta» y «no esta facturado» se arreglan de maneras distintas, y
/// un numero unico obligaria a abrir las doce columnas para saber cual es.
class AvisosTablero {
  const AvisosTablero({
    this.archivados = 0,
    this.enOtraRuta = 0,
    this.sinFactura = 0,
    this.cambiados = 0,
    this.colocados = 0,
  });

  final int archivados;
  final int enOtraRuta;
  final int sinFactura;
  final int cambiados;
  final int colocados;

  bool get hayAlguno =>
      archivados > 0 || enOtraRuta > 0 || sinFactura > 0 || cambiados > 0;
}

/// Un pedido que estaba puesto y ya no existe en PEDIDO (§7.5). Se avisa UNA
/// vez, con lo que se sabia de el antes de que se fuera.
class PedidoDesaparecido {
  const PedidoDesaparecido({
    required this.pedidoId,
    this.operationNumber,
    this.customerName,
    this.columna,
  });

  final String pedidoId;
  final String? operationNumber;
  final String? customerName;
  final String? columna;
}

/// La mitad izquierda: los pedidos sin colocar, ordenados por cercania.
class MitadIzquierda {
  const MitadIzquierda({required this.pedidos, required this.total});

  final List<TarjetaPedido> pedidos;

  /// Cuantos hay de verdad con estos filtros. `pedidos.length` es lo que cabe.
  final int total;

  bool get truncada => total > pedidos.length;
}

/// El tablero entero, tal y como se pinta.
class Tablero {
  const Tablero({
    required this.sucursalId,
    required this.sucursalNombre,
    required this.almacen,
    this.almacenes = const <AlmacenDeLaSucursal>[],
    required this.columnas,
    required this.colocados,
    required this.avisos,
    required this.sinColocar,
    required this.desaparecidos,
    this.vistoAt,
  }) : problema = null;

  /// EL TABLERO QUE NO SE PUEDE PINTAR, y por que.
  ///
  /// Son dos situaciones **normales**, no averias: que el Super Admin todavia
  /// no haya elegido sucursal y que la sucursal no tenga ningun almacen con
  /// coordenadas. Van como un tablero vacio con su motivo, y no como una
  /// excepcion, porque una excepcion se reintenta sola —eso hace Riverpod— y
  /// reintentar «elige una sucursal» cada pocos segundos, para siempre, no
  /// arregla nada y calienta el telefono.
  const Tablero.imposible(
    this.problema, {
    this.sucursalId = '',
    this.sucursalNombre = '',
  }) : almacen = const AlmacenOrigen(id: '', nombre: '', lat: 0, lng: 0),
       almacenes = const <AlmacenDeLaSucursal>[],
       columnas = const <ColumnaTablero>[],
       colocados = const <TarjetaColocada>[],
       avisos = const AvisosTablero(),
       sinColocar = const MitadIzquierda(pedidos: <TarjetaPedido>[], total: 0),
       desaparecidos = const <PedidoDesaparecido>[],
       vistoAt = null;

  /// `null` cuando el tablero se puede pintar.
  final String? problema;

  final String sucursalId;
  final String sucursalNombre;
  final AlmacenOrigen almacen;

  /// TODOS los almacenes de la sucursal, con ubicacion o sin ella. Vacia cuando
  /// el tablero no se puede pintar.
  ///
  /// Va en el tablero y no en un provider aparte porque quien la ensena es la
  /// cabecera, que ya tiene el tablero delante, y porque asi la lista y el
  /// almacen desde el que se mide salen de **la misma lectura**: dos lecturas
  /// distintas del mismo dato es como llegamos al 17/09/2026 con «Sin colocar
  /// (722)» encima de una lista de 293 (`CLAUDE.md` §3-bis).
  final List<AlmacenDeLaSucursal> almacenes;

  final List<ColumnaTablero> columnas;
  final List<TarjetaColocada> colocados;
  final AvisosTablero avisos;
  final MitadIzquierda sinColocar;
  final List<PedidoDesaparecido> desaparecidos;

  /// De cuando son estos datos. Es lo que se ensena arriba con todas las
  /// letras: un tablero que parece vivo y lleva seis horas congelado es peor
  /// que uno que avisa.
  final DateTime? vistoAt;

  List<TarjetaColocada> deColumna(String columnaId) =>
      colocados.where((t) => t.columnaId == columnaId).toList(growable: false);
}
