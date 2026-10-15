/// La cuenta del post-despacho: que salio, que se entrego y que tiene que
/// quedar arriba.
///
/// Se hace aqui y no en la pantalla porque es una resta que decide si falta
/// mercancia, y eso hay que poder probarlo. Dart puro: ni `pdf` ni Flutter
/// dentro. Calcado de `../docs/reglas-negocio.md` §12.
library;

import 'hoja.dart';

/// Una linea de un pedido tal y como llega de la API o de la base local.
class ItemDePedido {
  const ItemDePedido({this.name, this.description, this.packs, this.quantity});

  /// Desde un mapa suelto (lo que trae `items` en la base, que es JSON).
  /// Los numeros llegan a veces como texto, asi que se pasan por `num.tryParse`
  /// en vez de por un `as num`, que reventaria la hoja entera por una linea.
  factory ItemDePedido.deJson(Map<String, Object?> json) => ItemDePedido(
    name: json['name'] as String?,
    description: json['description'] as String?,
    packs: _aNumero(json['packs']),
    quantity: _aNumero(json['quantity']),
  );

  final String? name;
  final String? description;
  final num? packs;
  final num? quantity;

  /// Los formatos son la unidad con la que se carga y se cuenta un camion.
  /// Cuando la linea no los trae, se cae a las unidades: es lo que hay, y cero
  /// seria mentira.
  num get formatos {
    final p = packs;
    if (p != null && p > 0) return p;
    return quantity ?? 0;
  }

  /// `name`, y si no hay, `description`. Vacio si no hay ninguno de los dos.
  String get producto {
    final n = name?.trim() ?? '';
    return n.isNotEmpty ? n : (description ?? '').trim();
  }
}

num? _aNumero(Object? v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

/// Una parada de la ruta con su resultado ya marcado.
class PedidoDeRuta {
  const PedidoDeRuta({
    required this.customerName,
    this.resultado,
    this.resultadoNota,
    this.items = const <ItemDePedido>[],
  });

  final String customerName;

  /// `entregado`, `devuelto`, `cancelado`, o nada si nadie lo marco al volver.
  final String? resultado;
  final String? resultadoNota;
  final List<ItemDePedido> items;
}

/// Los datos de cabecera de la ruta: se copian tal cual a la hoja.
class DatosDeRuta {
  const DatosDeRuta({
    required this.ruta,
    required this.sucursal,
    required this.vehiculo,
    this.distribuidor = '',
    this.salida,
    this.regreso,
  });

  final String ruta;
  final String sucursal;
  final String vehiculo;

  /// QUIEN REPARTE (issue 7, 14/10/2026): la persona que firma «Entregó (chofer)».
  /// Vacio = la ruta no tiene (una anterior al 14/10/2026, o armada sin elegir): no
  /// se escribe nada, ni «sin distribuidor», en un papel que se firma.
  final String distribuidor;
  final String? salida;
  final String? regreso;
}

// La enye NO se pliega a `n`: en espanol es otra letra y va DETRAS de toda la
// n. La virgulilla vale como marca porque su codigo cae por encima de la `z`,
// asi que `naranja` < `nuez` < `name` (con enye) sale en ese orden.
const String _marcaEnye = 'n~';

const Map<String, String> _sinTilde = <String, String>{
  'á': 'a',
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'ã': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ç': 'c',
  'ñ': _marcaEnye,
};

String _clave(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    b.write(_sinTilde[c] ?? c);
  }
  return b.toString();
}

/// Ordena como `localeCompare('es')` de la de Next, no como `compareTo`.
///
/// `compareTo` de Dart compara unidades de codigo: pondria `Zumo` antes que
/// `Acido` con tilde, porque la tilde vive por encima de la Z en Unicode. En
/// una hoja que alguien lee de arriba abajo con el camion abierto eso se nota.
/// Se compara por una clave sin tildes y en minusculas, que es lo que hace el
/// idioma; si dos productos empatan ahi, se desempata con el texto crudo para
/// que el orden siga siendo estable entre dos impresiones.
int comparaProductos(String a, String b) {
  final c = _clave(a).compareTo(_clave(b));
  return c != 0 ? c : a.compareTo(b);
}

/// Arma la hoja del post-despacho a partir de las paradas de la ruta.
///
/// Lo que QUEDA es todo lo que no se entrego: lo devuelto, lo cancelado y
/// —sobre todo— lo que nadie marco. Eso ultimo se cuenta como que sigue arriba
/// a proposito: dar por entregada una parada que nadie toco es justo como se
/// pierde mercancia sin que salte nada. En la hoja sale aparte, para que se vea
/// que falta marcarla.
HojaPostDespacho armarPostDespacho(
  DatosDeRuta datos,
  List<PedidoDeRuta> pedidos,
) {
  // Un mapa que conserva el orden de llegada; el `sort` de Dart es estable, asi
  // que dos productos que empatan no se bailan entre una impresion y la
  // siguiente.
  final porProducto = <String, LineaPostDespacho>{};
  final pendientes = <ParadaPendiente>[];

  var entregadas = 0;
  var devueltas = 0;
  var canceladas = 0;
  var sinMarcar = 0;

  for (final p in pedidos) {
    final entregado = p.resultado == 'entregado';

    if (entregado) {
      entregadas++;
    } else if (p.resultado == 'devuelto') {
      devueltas++;
    } else if (p.resultado == 'cancelado') {
      canceladas++;
    } else {
      // Todo lo demas, incluido `null` y cualquier valor desconocido.
      sinMarcar++;
    }

    // Las lineas sin nombre de producto se tiran: en el papel serian una fila
    // en blanco que nadie sabe contar.
    final suyas = <ProductoDeParada>[
      for (final it in p.items)
        if (it.producto.isNotEmpty)
          ProductoDeParada(producto: it.producto, formatos: it.formatos),
    ];

    for (final l in suyas) {
      final acc = porProducto.putIfAbsent(
        l.producto,
        () => LineaPostDespacho(producto: l.producto),
      );

      acc.salio += l.formatos;
      if (entregado) {
        acc.entregado += l.formatos;
      } else {
        acc.queda += l.formatos;
      }
    }

    if (!entregado) {
      pendientes.add(
        ParadaPendiente(
          cliente: p.customerName,
          resultado: p.resultado,
          nota: p.resultadoNota,
          productos: suyas,
        ),
      );
    }
  }

  // Lo que mas queda primero: es por donde se empieza a contar al bajar el
  // camion. A igualdad, por nombre.
  final lineas = porProducto.values.toList()
    ..sort((a, b) {
      final porQueda = b.queda.compareTo(a.queda);
      return porQueda != 0
          ? porQueda
          : comparaProductos(a.producto, b.producto);
    });

  return HojaPostDespacho(
    ruta: datos.ruta,
    sucursal: datos.sucursal,
    vehiculo: datos.vehiculo,
    distribuidor: datos.distribuidor,
    salida: datos.salida,
    regreso: datos.regreso,
    entregadas: entregadas,
    devueltas: devueltas,
    canceladas: canceladas,
    sinMarcar: sinMarcar,
    lineas: lineas,
    pendientes: pendientes,
  );
}
