import 'package:drift/drift.dart';

import '../base/base.dart';
import '../frescura/frescura.dart';

/// QUE TIENE EL APARATO, contado en la base local.
///
/// **Los numeros salen de aqui y NUNCA de lo que contesto el servidor.** No es
/// una manera equivalente de contar lo mismo: la respuesta dice lo que el
/// servidor creyo mandar, y la base dice lo que de verdad quedo escrito. Entre
/// las dos cosas hay una transaccion que puede haberse deshecho, una tanda que
/// no llego y un `quitados` que borro mas de lo que trajo. Quien se va al
/// almacen se lleva la base, asi que es la base la que tiene que hablar.
class RecuentoDeLoQueHay {
  const RecuentoDeLoQueHay({required this.filas, required this.bajadaAt});

  static const vacio = RecuentoDeLoQueHay(
    filas: <String, int>{},
    bajadaAt: <String, DateTime?>{},
  );

  /// Cuantas filas hay de cada coleccion, por la clave de [Colecciones].
  final Map<String, int> filas;

  /// Cuando se bajo cada coleccion. `null` —o ausente— es **nunca**, que no es
  /// lo mismo que «hace mucho» y no se puede pintar igual.
  final Map<String, DateTime?> bajadaAt;

  int cuantas(String coleccion) => filas[coleccion] ?? 0;

  bool seBajo(String coleccion) => bajadaAt[coleccion] != null;

  /// La bajada mas VIEJA de las nueve, que es la que manda: el aparato no esta
  /// al dia si una sola coleccion no lo esta. `null` si alguna no se bajo nunca.
  DateTime? get laMasVieja {
    final fechas = <DateTime>[];
    for (final coleccion in Colecciones.todas) {
      final cuando = bajadaAt[coleccion];
      if (cuando == null) return null;
      fechas.add(cuando);
    }
    if (fechas.isEmpty) return null;
    fechas.sort();
    return fechas.first;
  }

  /// `true` cuando la proxima bajada va a traer **TODO**, no las diferencias.
  ///
  /// Son dos cosas distintas y el boton no las puede llamar igual. La primera
  /// vez el aparato esta vacio y se trae la sucursal entera —unos 2.500 clientes
  /// en Santiago, que es la mas grande—: eso tarda, y llamarlo «traer el día»
  /// es mentir sobre lo que va a pasar y sobre cuanto va a tardar. A partir de
  /// ahi se manda `desde` y bajan cuatro filas.
  ///
  /// Se mira la marca de `orders` **y no otra**, porque es exactamente la que
  /// `Bajada.ciclo` usa de cursor (`_frescura.desde(Colecciones.pedidos)`): sin
  /// ella no hay `desde` que mandar y el servidor sirve la carga completa. Mirar
  /// cualquier otra seria adivinar.
  bool get vaATraerTodo => !seBajo(Colecciones.pedidos);

  @override
  String toString() => 'RecuentoDeLoQueHay($filas)';
}

/// Cuenta lo que hay en la base local, coleccion a coleccion.
///
/// Se pregunta **despues** de bajar, no durante: mientras la bajada corre las
/// filas entran dentro de una transaccion que todavia se puede deshacer.
class Recontador {
  Recontador(this._base, this._frescura);

  final BaseLocal _base;
  final RegistroDeFrescura _frescura;

  Future<RecuentoDeLoQueHay> ahora() async {
    final filas = <String, int>{
      Colecciones.pedidos: await _cuantas(_base.orders),
      Colecciones.renglones: await _cuantas(_base.orderItems),
      Colecciones.rutas: await _cuantas(_base.routes),
      Colecciones.clientes: await _cuantas(_base.customers),
      Colecciones.productos: await _cuantas(_base.products),
      Colecciones.vehiculos: await _cuantas(_base.vehicles),
      Colecciones.distribuidores: await _cuantas(_base.distribuidores),
      Colecciones.tiposDeVehiculo: await _cuantas(_base.vehicleTypes),
      Colecciones.sucursales: await _cuantas(_base.branches),
      Colecciones.almacenes: await _cuantas(_base.warehouses),
      Colecciones.ajustes: await _cuantas(_base.settings),
    };

    final bajadaAt = <String, DateTime?>{};
    for (final coleccion in Colecciones.todas) {
      bajadaAt[coleccion] = (await _frescura.leer(coleccion))?.bajadaAt;
    }

    return RecuentoDeLoQueHay(filas: filas, bajadaAt: bajadaAt);
  }

  Future<int> _cuantas(TableInfo<Table, Object?> tabla) async {
    final cuenta = countAll();
    final fila = await (_base.selectOnly(
      tabla,
    )..addColumns([cuenta])).getSingle();
    return fila.read(cuenta) ?? 0;
  }
}

/// Por que una coleccion cuenta como que NO esta.
enum PorQueFalta {
  /// No hay marca de bajada: no se pidio nunca, o el ciclo se corto antes de
  /// llegar a ella. Vale para las nueve.
  nuncaSeBajo,

  /// Se bajo y quedo a cero filas. Solo cuenta para las imprescindibles: en las
  /// demas, cero es una respuesta legitima.
  vacia,
}

/// Una coleccion que no esta, con **que es** y **que se rompe sin ella**.
class Falta {
  const Falta(this.coleccion, this.porQue);

  final String coleccion;
  final PorQueFalta porQue;

  String get queEs => Faltas.comoSeLlama(coleccion);

  String get consecuencia => Faltas.queSeRompe(coleccion);

  @override
  String toString() => 'Falta($coleccion, $porQue)';

  @override
  bool operator ==(Object other) =>
      other is Falta && other.coleccion == coleccion && other.porQue == porQue;

  @override
  int get hashCode => Object.hash(coleccion, porQue);
}

/// LA GUARDA: que le falta al aparato para poder trabajar el dia.
///
/// Este es el fichero que existe para evitar UN fallo concreto: que la pantalla
/// diga «listo» con el catalogo de productos sin bajar, y que alguien se vaya al
/// almacen con esa pantalla en la mano. Un aparato que se calla lo que le falta
/// es peor que uno que no bajo nada, porque el segundo se nota y el primero no.
///
/// Por eso la respuesta **no sale de la respuesta del servidor**, que solo sabe
/// lo que creyo mandar, sino de [RecuentoDeLoQueHay], que es la base.
abstract final class Faltas {
  /// Sin estas cuatro **el dia no se puede trabajar**, y cero filas es un fallo
  /// y no un dato:
  ///
  ///  * `products` — los pesos. Sin catalogo, el peso de cada renglon sale a
  ///    cero, el camion se carga por debajo y el pre-despacho manda sacar menos
  ///    mercancia de la que va. Es el ejemplo literal del encargo.
  ///  * `customers` — las direcciones y las coordenadas. Sin clientes, un pedido
  ///    no se puede colocar en el mapa ni medir, y la ruta sale sin kilometros.
  ///  * `branches` — el punto de origen desde el que se mide todo.
  ///  * `warehouses` — desde donde se mide lo que se le cobra al cliente por el
  ///    domicilio. Uno viejo cobra mal cada entrega del dia.
  static const imprescindibles = <String>[
    Colecciones.productos,
    Colecciones.clientes,
    Colecciones.sucursales,
    Colecciones.almacenes,
  ];

  /// Y en estas cinco, **cero es una respuesta legitima** y no se avisa:
  ///
  ///  * `orders` y `order_items` — una sucursal puede amanecer sin nada que
  ///    repartir.
  ///  * `routes` — por la mannana lo normal es que no haya ninguna armada.
  ///  * `vehicles` — una sucursal nueva puede no tener ninguno dado de alta
  ///    todavia. Avisar aqui seria gritar todas las mannanas por algo que nadie
  ///    puede arreglar desde el telefono, y el dia que grite de verdad ya no lo
  ///    leeria nadie.
  ///  * `settings` — sin la fila de ajustes los importes se quedan en USD, que
  ///    es el valor guardado. Se ve raro, pero no manda mal un camion.
  ///  * `distribuidores` — una sucursal puede no tener ninguno dado de alta todavia
  ///    (issue 7, 14/10/2026), y la ruta se arma igual, sin distribuidor. Lo que SI
  ///    se avisa es que **no se bajaron** (`nuncaSeBajo`): sin la lista el selector
  ///    de «Nueva ruta» no ofrece a nadie aunque la sucursal tenga a diez.
  ///
  /// Que no se avise **no es que no se cuente**: las nueve salen con su numero
  /// en el resumen. Lo que no hacen es tumbar el verde.
  static const delDia = <String>[
    Colecciones.pedidos,
    Colecciones.renglones,
    Colecciones.rutas,
    Colecciones.vehiculos,
    Colecciones.distribuidores,
    Colecciones.tiposDeVehiculo,
    Colecciones.ajustes,
  ];

  /// LAS TRES QUE PESAN, y las unicas que la persona reconoce por su nombre.
  ///
  /// Son las que tardan: ocho mil clientes, mil productos, y los pedidos con sus
  /// lineas dentro. Cuando alguien pregunta «¿que me traigo?», la respuesta es
  /// esta y no una lista de nueve renglones.
  ///
  /// `order_items` no sale aparte: los renglones **viajan dentro del pedido** y
  /// contarlos como una coleccion suya hace creer que son otra descarga.
  static const lasQuePesan = <String>[
    Colecciones.pedidos,
    Colecciones.clientes,
    Colecciones.productos,
  ];

  /// LO DE SIEMPRE: menos de **veinte filas entre las cinco** (los distribuidores
  /// se sumaron el 14/10/2026: unas decenas por sucursal).
  ///
  /// No tardan nada y por eso no merecen cuatro renglones en la pantalla — pero
  /// hacen falta las cuatro, y por eso no se pueden callar del todo: sin
  /// vehiculo no se cierra una ruta, sin sucursal no hay punto de partida desde
  /// donde medir, sin almacen el domicilio se cobra desde el sitio equivocado, y
  /// los ajustes son UNA fila con la tasa. Van juntas, en una linea.
  static const loDeSiempre = <String>[
    Colecciones.vehiculos,
    Colecciones.distribuidores,
    Colecciones.tiposDeVehiculo,
    Colecciones.sucursales,
    Colecciones.almacenes,
    Colecciones.ajustes,
  ];

  /// LO QUE NO SE ENSENA, porque **no es algo que te traigas**.
  ///
  /// Las rutas son lo que la aplicacion PRODUCE, no lo que consume: el logistico
  /// arma la ruta sin conexion y la sube. Se siguen bajando —son cero filas casi
  /// siempre y cubren el caso de que alguien abra el telefono y el portatil—,
  /// pero ensenarlas entre lo que se descarga confunde justo sobre lo que hace
  /// la aplicacion. Que vayan calladas.
  ///
  /// `order_items` esta aqui por otro motivo: no es que no importe, es que ya
  /// esta contado dentro de los pedidos.
  static const calladas = <String>[Colecciones.rutas, Colecciones.renglones];

  /// Lo que le falta al aparato, en el orden de [Colecciones.todas].
  ///
  /// Dos reglas, y las dos hacen falta:
  ///
  ///  1. **Sin marca de bajada, falta** — vale para las nueve. Es lo que caza el
  ///     ciclo que se corto a la mitad: los pedidos entraron y quedaron
  ///     marcados, la tanda siguiente no llego y `warehouses` se quedo sin
  ///     marca. El ciclo devuelve su fallo, si, pero esto lo dice **por
  ///     coleccion**, que es lo que hace falta para poder escribir «faltan los
  ///     almacenes» en vez de «hubo un error».
  ///  2. **Imprescindible y a cero, falta** — es la que caza el caso silencioso:
  ///     el servidor contesta 200, `cambios` viene sin `products`, todo queda
  ///     marcado y verde, y el catalogo esta vacio. Ahi no hay ningun fallo que
  ///     mirar; lo unico que lo delata es contar las filas.
  static List<Falta> de(RecuentoDeLoQueHay recuento) {
    final faltas = <Falta>[];
    for (final coleccion in Colecciones.todas) {
      if (!recuento.seBajo(coleccion)) {
        faltas.add(Falta(coleccion, PorQueFalta.nuncaSeBajo));
        continue;
      }
      if (imprescindibles.contains(coleccion) &&
          recuento.cuantas(coleccion) == 0) {
        faltas.add(Falta(coleccion, PorQueFalta.vacia));
      }
    }
    return faltas;
  }

  /// Lo que falta, **agrupado como se lee**: las que pesan por su nombre, y
  /// todo lo demas junto.
  ///
  /// Sin esto, una bajada que no llego deja al logistico leyendo nueve vinetas
  /// para enterarse de que lo que fallo es «todo». Nueve avisos no son nueve
  /// veces mas informacion: son un aviso que nadie lee.
  static List<String> agrupar(List<Falta> faltan) {
    if (faltan.isEmpty) return const <String>[];
    final nombres = <String>[
      for (final c in lasQuePesan)
        if (faltan.any((f) => f.coleccion == c)) comoSeLlama(c),
    ];
    if (faltan.any((f) => !lasQuePesan.contains(f.coleccion))) {
      nombres.add(nombreDeLoDeSiempre);
    }
    return nombres;
  }

  /// `true` cuando no bajo NADA. Se dice de una vez y no coleccion a coleccion.
  static bool faltaTodo(List<Falta> faltan) =>
      agrupar(faltan).length >= lasQuePesan.length + 1;

  static const nombreDeLoDeSiempre = 'lo de siempre';

  /// Que se rompe sin **lo de siempre**, en una sola frase. Son cuatro cosas de
  /// menos de veinte filas, y leerlas por separado es leer cuatro veces lo mismo.
  static const seRompeSinLoDeSiempre =
      'Lo de siempre: sin vehículo no se cierra una ruta, sin distribuidor no '
      'se puede decir quién la reparte, sin sucursal no hay desde dónde medir '
      'y sin almacén el domicilio se cobra desde el sitio equivocado.';

  static String comoSeLlama(String coleccion) => switch (coleccion) {
    Colecciones.pedidos => 'los pedidos',
    Colecciones.renglones => 'las líneas de los pedidos',
    Colecciones.rutas => 'las rutas',
    Colecciones.clientes => 'los clientes',
    Colecciones.productos => 'el catálogo de productos',
    Colecciones.vehiculos => 'los vehículos',
    Colecciones.distribuidores => 'los distribuidores',
    Colecciones.tiposDeVehiculo => 'los tipos de vehículo',
    Colecciones.sucursales => 'las sucursales',
    Colecciones.almacenes => 'los almacenes',
    Colecciones.ajustes => 'los ajustes',
    _ => coleccion,
  };

  /// **Que se rompe sin ella.** No es adorno: es la unica parte del aviso que le
  /// dice a alguien si puede irse al almacen o no.
  static String queSeRompe(String coleccion) => switch (coleccion) {
    Colecciones.pedidos => 'sin ellos no hay nada que repartir',
    Colecciones.renglones => 'sin ellas el pre-despacho sale vacío',
    Colecciones.rutas => 'sin ellas no se ven las que quedaron abiertas',
    Colecciones.clientes =>
      'sin ellos los pedidos se quedan sin dirección ni coordenadas',
    Colecciones.productos =>
      'sin él los pesos van incompletos y el pre-despacho sale corto',
    Colecciones.vehiculos => 'sin ellos no se puede asignar camión a una ruta',
    Colecciones.distribuidores =>
      'sin ellos no se puede decir quién reparte la ruta',
    Colecciones.tiposDeVehiculo =>
      'sin ellos no se puede elegir el tipo de un vehículo ni su costo por km',
    Colecciones.sucursales => 'sin ellas no hay punto de origen para medir',
    Colecciones.almacenes =>
      'sin ellos el domicilio se cobra desde el sitio equivocado',
    Colecciones.ajustes => 'sin ellos no hay tasa y los importes salen en USD',
    _ => 'sin ella la pantalla que la usa se queda sin datos',
  };
}
