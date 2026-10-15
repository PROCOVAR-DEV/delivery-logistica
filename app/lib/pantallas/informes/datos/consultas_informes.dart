import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/numero_de_factura.dart';

/// Lo que se le pide al informe. Sin valores por defecto: arranca sin rango y
/// sin vehiculo (pliego §7).
class FiltroDeInforme {
  const FiltroDeInforme({this.desde, this.hasta, this.vehiculoId});

  final DateTime? desde;
  final DateTime? hasta;
  final String? vehiculoId;

  bool get hayAlgoPuesto =>
      desde != null || hasta != null || vehiculoId != null;

  FiltroDeInforme copiar({
    DateTime? desde,
    DateTime? hasta,
    String? vehiculoId,
    bool quitarDesde = false,
    bool quitarHasta = false,
    bool quitarVehiculo = false,
  }) => FiltroDeInforme(
    desde: quitarDesde ? null : (desde ?? this.desde),
    hasta: quitarHasta ? null : (hasta ?? this.hasta),
    vehiculoId: quitarVehiculo ? null : (vehiculoId ?? this.vehiculoId),
  );

  @override
  bool operator ==(Object other) =>
      other is FiltroDeInforme &&
      other.desde == desde &&
      other.hasta == hasta &&
      other.vehiculoId == vehiculoId;

  @override
  int get hashCode => Object.hash(desde, hasta, vehiculoId);
}

/// Una fila de «Detalle de Órdenes».
class FilaDeInforme {
  const FilaDeInforme({
    required this.id,
    required this.cliente,
    required this.destino,
    required this.pesoKg,
    required this.importe,
    this.fecha,
    this.ruta,
    this.vehiculoId,
    this.vehiculo,
    this.placa,
    this.kmDesdePartida,
    this.factura,
  });

  final String id;
  final String cliente;
  final String destino;
  final double pesoKg;

  /// **Ingreso de un pedido = `price` si lo tiene, si no `pedidoCosto`.** Es el
  /// numero que mas facil se equivoca de todo el pliego, y por eso se calcula
  /// aqui y en ningun otro sitio.
  ///
  /// **`null` = SIN COTIZAR, y no es cero** (`CLAUDE.md` §2). Aqui habia un
  /// `?? 0` y ese cero llegaba entero hasta la hoja que se manda a
  /// contabilidad: el 22/09/2026, en produccion, `Pedidos` decia «sin cotizar»
  /// en todas sus filas y `Reportes -> Detalle de Ordenes` decia **0,00 USD**
  /// en las mismas, con el vehiculo teniendo su tarifa puesta (1,50 USD/km).
  /// Eso no dice «no hay tarifa»: dice que el reparto fue gratis. Un hueco se
  /// ve y se rellena; un cero se suma y nadie se entera.
  final double? importe;

  final DateTime? fecha;
  final String? ruta;

  /// El ID del vehiculo de la ruta. **Es por lo que se agrupa**, no por el
  /// nombre: dos camiones se pueden llamar igual.
  final String? vehiculoId;

  final String? vehiculo;
  final String? placa;
  final double? kmDesdePartida;

  /// El número de factura del pedido (issue 9 de Amado): su `factura_numero`, el de
  /// Ventra, sin caer nunca al folio. Sale de [NumeroDeFactura.de] y de ningún otro
  /// sitio. `null` = el pedido no tiene número, y se pinta con la raya: nunca en
  /// blanco ni inventado.
  final String? factura;
}

class ResumenDeInforme {
  const ResumenDeInforme({
    required this.totalOrdenes,
    required this.ingresos,
    required this.peso,
    required this.precioPromedio,
    this.sinCotizar = 0,
  });

  final int totalOrdenes;

  /// `null` cuando **falta el importe de alguna orden**: un total a medias
  /// parece completo y se cobra. Ver [ConsultasInformes.sumaCompleta].
  final double? ingresos;

  final double peso;

  /// `null` por lo mismo que [ingresos]: un promedio sobre una suma incompleta
  /// es un numero creible y equivocado.
  final double? precioPromedio;

  /// Cuantas ordenes entraron sin importe. Es lo que convierte el `—` en algo
  /// que se puede arreglar: dice cuantas faltan por cotizar.
  final int sinCotizar;
}

class FilaDeVehiculo {
  const FilaDeVehiculo({
    required this.id,
    required this.nombre,
    required this.ordenes,
    required this.ingresos,
    required this.peso,
    this.placa,
    this.sinCotizar = 0,
    this.facturas = const [],
    this.sinFactura = 0,
  });

  /// El vehiculo, por su identificador. Dos camiones homonimos son dos filas.
  final String id;

  final String nombre;
  final String? placa;
  final int ordenes;

  /// `null` cuando alguna de sus ordenes no tiene importe.
  final double? ingresos;

  final double peso;

  /// Cuantas de sus [ordenes] entraron sin importe.
  final int sinCotizar;

  /// Los números de factura de sus órdenes, sin repetir y en el orden en que
  /// salen (issue 9 de Amado). **Es sólo la lista de referencias**: no cambia
  /// [ordenes] ni ningún total.
  final List<String> facturas;

  /// Cuántas de sus [ordenes] no tienen número de factura. Se dice y no se
  /// calla: una lista que parece completa y no lo es esconde facturas.
  final int sinFactura;

  /// `null` arrastra: sin la suma no hay promedio. Con cero ordenes no se
  /// divide por cero, pero eso aqui no pasa —una fila existe porque tiene al
  /// menos un pedido—.
  double? get promedioPorOrden {
    final total = ingresos;
    if (total == null) return null;
    return ordenes == 0 ? 0 : total / ordenes;
  }
}

class Informe {
  const Informe({
    required this.filas,
    required this.resumen,
    required this.porVehiculo,
  });

  static const vacio = Informe(
    filas: <FilaDeInforme>[],
    resumen: ResumenDeInforme(
      totalOrdenes: 0,
      ingresos: 0,
      peso: 0,
      precioPromedio: 0,
    ),
    porVehiculo: <FilaDeVehiculo>[],
  );

  final List<FilaDeInforme> filas;
  final ResumenDeInforme resumen;

  /// **Solo los pedidos cuya ruta tiene vehiculo.** Lo dice el contrato, y sin
  /// esa condicion aparece una fila «sin vehiculo» que en la de Next no existe y
  /// descuadra la paridad.
  final List<FilaDeVehiculo> porVehiculo;
}

/// Los Informes, cuadrados **con lo que hay bajado en el aparato**.
///
/// Esta pantalla no es la del dia sin conexion y no pretende serlo: el informe
/// de verdad lo da `GET /api/reports`, sobre TODO lo que hay en el servidor.
/// Aqui solo puede salir lo que se haya bajado, y por eso la pantalla dice de
/// cuando son sus datos en vez de presentar un total como si fuera el bueno. Un
/// informe con la mitad de los pedidos no es un informe a medias: es un informe
/// equivocado.
class ConsultasInformes {
  ConsultasInformes(this._base);

  final BaseLocal _base;

  Stream<Informe> mirar(FiltroDeInforme filtro, {String? sucursalId}) {
    const sql = '''
SELECT o.id, o.customer_name, o.address, o.end_address, o.weight,
       o.price, o.pedido_costo, o.segment_km, o.created_at,
       o.factura_numero,
       COALESCE(r.route_code, r.name) AS ruta_nombre,
       v.id    AS vehiculo_id,
       v.name  AS vehiculo_nombre,
       v.plate AS vehiculo_placa
  FROM orders o
  LEFT JOIN routes   r ON r.id = o.route_id
  LEFT JOIN vehicles v ON v.id = r.vehicle_id
 WHERE (?1 IS NULL OR o.branch_id = ?1)
   AND (?2 IS NULL OR julianday(o.created_at) >= julianday(?2))
   AND (?3 IS NULL OR julianday(o.created_at) <= julianday(?3))
   AND (?4 IS NULL OR r.vehicle_id = ?4)
 ORDER BY o.created_at DESC
''';

    return _base
        .customSelect(
          sql,
          variables: [
            Variable<String>(sucursalId),
            Variable<DateTime>(comienzoDelDia(filtro.desde)),
            // `hasta` incluye el DIA ENTERO. Sin esto, pedir «hasta el 14» deja
            // fuera todo lo del 14, que es justo el dia que se queria mirar.
            Variable<DateTime>(finDelDia(filtro.hasta)),
            Variable<String>(filtro.vehiculoId),
          ],
          readsFrom: {_base.orders, _base.routes, _base.vehicles},
        )
        .watch()
        .map(armar);
  }

  /// Las 00:00:00.000 del dia de [dia], **EN UTC**. Publica porque se prueba
  /// sola.
  static DateTime? comienzoDelDia(DateTime? dia) =>
      dia == null ? null : DateTime.utc(dia.year, dia.month, dia.day);

  /// Las 23:59:59.999 del dia de [dia], **EN UTC**. Publica porque se prueba
  /// sola.
  ///
  /// ## Por que UTC y no la hora de aqui
  ///
  /// La de Next corta el rango en UTC: `new Date('2026-09-14')` es medianoche
  /// UTC y `new Date(to + 'T23:59:59.999Z')` es el final del dia UTC
  /// (`src/app/api/reports/route.ts`). Aqui se cortaba en hora local, y con
  /// Cuba a −4/−5 eso son **hasta cinco horas de pedidos que entran en un lado
  /// y no en el otro**: el informe del aparato y el del servidor daban dos
  /// totales distintos para el mismo dia, que es lo peor que le puede pasar a
  /// una pantalla que existe para cuadrar caja.
  ///
  /// La comparacion va con `julianday()` y no con `>=` a secas por lo mismo.
  /// Drift guarda las fechas como texto ISO y las locales llevan su desfase
  /// pegado (`2026-09-14T22:00:00.000 -04:00`), asi que comparar con un limite
  /// en UTC (`…Z`) seria comparar dos textos con formatos distintos letra a
  /// letra. `julianday()` los pasa los dos al mismo instante antes de mirar
  /// cual es mayor. Comprobado: sin el, un pedido de las 02:00 UTC del dia 15
  /// entraba en «hasta el 14».
  static DateTime? finDelDia(DateTime? dia) => dia == null
      ? null
      : DateTime.utc(dia.year, dia.month, dia.day, 23, 59, 59, 999);

  /// EL INGRESO DE UN PEDIDO. Es el numero que mas facil se equivoca de todo el
  /// pliego, y por eso se calcula aqui y en ningun otro sitio.
  ///
  /// ## De donde salia el `0,00 USD` de `Detalle de Órdenes`
  ///
  /// Esto era `precio ?? costo ?? 0`, copiado de `revenueOf` del Next
  /// (`src/app/api/reports/route.ts:46-49`). Y `price` **no es un precio
  /// propio**: es una COPIA de `pedidoCosto` que se hace al enganchar el pedido
  /// a una ruta, y esa copia **pierde el nulo**. Lo dice el propio servidor, en
  /// `api/internal/api/rutas.go:958`: «`price` se COPIA de `pedidoCosto` […]
  /// **un `null` se guarda como 0**», y lo remacha el SQL:
  /// `price = coalesce(sqlc.narg('price'), 0)` en `EngancharPedidoARuta`
  /// (`api/db/queries/routes.sql:283`).
  ///
  /// O sea: en cuanto un pedido sin cotizar entra en una ruta, su `price` vale
  /// `0` y ya nunca es nulo. `precio ?? costo` se queda con ese cero y no llega
  /// a mirar `pedidoCosto`. Eso es exactamente lo que se midio el 22/09/2026 en
  /// produccion: `Pedidos` —que lee `pedidoCosto`— decia «sin cotizar» en todas
  /// sus filas, y `Reportes -> Detalle de Órdenes` decia `0,00 USD` en las
  /// mismas, con el camion cotizado a 1,50 USD/km y una ruta de 10,4 km. No
  /// decia «no hay tarifa»: decia que el reparto fue gratis.
  ///
  /// ## La regla, y por que no se tira el `price` entero
  ///
  ///  * con `pedidoCosto`, ese es el ingreso (y `price`, que es su copia, se
  ///    respeta por delante para no separarse del patron);
  ///  * **sin `pedidoCosto`, un `price` de CERO no es un precio**: es el
  ///    `coalesce` de arriba, y se dice `null` = sin cotizar;
  ///  * sin `pedidoCosto` pero con un `price` distinto de cero, ese numero no
  ///    puede venir del `coalesce` —lo pone la APK de Entrega, que es quien
  ///    cotiza— y se respeta. Tirarlo seria perder un cobro de verdad.
  ///
  /// **Un cero legitimo sigue siendo cero**: un domicilio gratis lleva
  /// `pedidoCosto = 0`, y de ahi sale `0,00`, que es una cifra.
  static double? ingresoDe({required double? precio, required double? costo}) {
    if (costo != null) return precio ?? costo;
    if (precio != null && precio != 0) return precio;
    return null;
  }

  /// De filas crudas a informe. Separado de la consulta **a proposito**: asi las
  /// cuatro cifras y `Por Vehículo` se prueban con datos a mano, sin base.
  static Informe armar(List<QueryRow> crudas) {
    final filas = <FilaDeInforme>[];
    for (final f in crudas) {
      final precio = f.read<double?>('price');
      final costo = f.read<double?>('pedido_costo');
      filas.add(
        FilaDeInforme(
          id: f.read<String>('id'),
          cliente: f.read<String>('customer_name'),
          destino: f.read<String?>('end_address') ?? f.read<String>('address'),
          pesoKg: f.read<double>('weight'),
          importe: ingresoDe(precio: precio, costo: costo),
          fecha: f.read<DateTime?>('created_at'),
          ruta: f.read<String?>('ruta_nombre'),
          vehiculoId: f.read<String?>('vehiculo_id'),
          vehiculo: f.read<String?>('vehiculo_nombre'),
          placa: f.read<String?>('vehiculo_placa'),
          kmDesdePartida: f.read<double?>('segment_km'),
          factura: NumeroDeFactura.de(f.read<String?>('factura_numero')),
        ),
      );
    }
    return Informe(
      filas: filas,
      resumen: resumir(filas),
      porVehiculo: agruparPorVehiculo(filas),
    );
  }

  /// UN TOTAL A MEDIAS ES PEOR QUE NINGUNO. Es la misma regla, la misma forma y
  /// el mismo nombre que `TotalesPreDespacho._sumaCompleta`
  /// (`pantallas/pedidos/datos/repositorio_pedidos.dart`): en cuanto falte UN
  /// sumando, el total es `null` y la pantalla pinta `—` diciendo cuantos
  /// faltan. Sumar lo que hay y callar lo que falta es la misma mentira con
  /// menos escandalo.
  ///
  /// **La unica diferencia con aquella, y es a proposito:** sobre una lista
  /// VACIA esto da `0`, no `null`. Alli una lista vacia significa «ningun
  /// producto resuelto»; aqui significa «no hay ninguna orden en el filtro», y
  /// entonces el cero es una cifra de verdad —«se sabe y vale cero»—, no un
  /// hueco. La pantalla ademas ensena `No hay órdenes para los filtros
  /// seleccionados` antes de llegar a pintarlo.
  static double? sumaCompleta(Iterable<double?> valores) {
    var suma = 0.0;
    for (final valor in valores) {
      if (valor == null) return null;
      suma += valor;
    }
    return suma;
  }

  static ResumenDeInforme resumir(List<FilaDeInforme> filas) {
    var peso = 0.0;
    for (final f in filas) {
      peso += f.pesoKg;
    }
    final ingresos = sumaCompleta(filas.map((f) => f.importe));
    final double? promedio;
    if (filas.isEmpty) {
      // Sin ordenes el promedio es 0, no una division por cero ni un `NaN` que
      // se pinta como «NaN» en la tarjeta.
      promedio = 0;
    } else if (ingresos == null) {
      promedio = null;
    } else {
      promedio = ingresos / filas.length;
    }
    return ResumenDeInforme(
      totalOrdenes: filas.length,
      ingresos: ingresos,
      peso: peso,
      precioPromedio: promedio,
      sinCotizar: filas.where((f) => f.importe == null).length,
    );
  }

  /// **Se agrupa por el ID del vehiculo, nunca por su nombre.**
  ///
  /// La de Next indexa `byVehicle` por `v.id` (`api/reports/route.ts`). Aqui se
  /// hacia por nombre, y entonces dos camiones que se llamen igual —«Camión
  /// #1» en dos sucursales, o el de siempre y su sustituto— se fundian en una
  /// sola fila con los ingresos sumados de los dos. Este error ya se cazo una
  /// vez en este proyecto; por eso la clave es el id y no vuelve a ser otra
  /// cosa.
  static List<FilaDeVehiculo> agruparPorVehiculo(List<FilaDeInforme> filas) {
    final porId = <String, FilaDeVehiculo>{};
    // Los numeros de factura de cada camion, tal cual salen, para juntarlos al
    // final con `NumeroDeFactura.agrupar` (una sola regla, la del fichero de
    // casos compartidos con el servidor).
    final numeros = <String, List<String?>>{};
    for (final f in filas) {
      final id = f.vehiculoId;
      if (id == null) continue; // sin vehiculo no entra (contrato §9)
      (numeros[id] ??= []).add(f.factura);
      final previo = porId[id];
      // Una sola orden sin cotizar deja SU CAMION sin total, y el `null` ya no
      // se recupera aunque las siguientes si tengan importe: es la misma regla
      // de [sumaCompleta], aplicada segun se agrupa.
      final acumulado = previo == null ? 0.0 : previo.ingresos;
      final importe = f.importe;
      porId[id] = FilaDeVehiculo(
        id: id,
        nombre: f.vehiculo ?? previo?.nombre ?? '',
        placa: f.placa ?? previo?.placa,
        ordenes: (previo?.ordenes ?? 0) + 1,
        ingresos: (acumulado == null || importe == null)
            ? null
            : acumulado + importe,
        sinCotizar: (previo?.sinCotizar ?? 0) + (importe == null ? 1 : 0),
        peso: (previo?.peso ?? 0) + f.pesoKg,
      );
    }
    final lista = porId.values.toList()
      // De mas a menos ingreso: `Top vehículos` son las 3 primeras de aqui.
      //
      // **Un camion sin total va al final, no arriba.** No se puede ordenar por
      // un numero que no se sabe, y colarlo entre los tres primeros con un `—`
      // en la tarjeta seria decir que es de los que mas trae sin tener con que
      // sostenerlo.
      ..sort(
        (a, b) => (b.ingresos ?? double.negativeInfinity).compareTo(
          a.ingresos ?? double.negativeInfinity,
        ),
      );
    // Las facturas se juntan al final, ya en su orden: no cuentan para ordenar.
    return lista.map((v) {
      final g = NumeroDeFactura.agrupar(numeros[v.id]!);
      return FilaDeVehiculo(
        id: v.id,
        nombre: v.nombre,
        placa: v.placa,
        ordenes: v.ordenes,
        ingresos: v.ingresos,
        peso: v.peso,
        sinCotizar: v.sinCotizar,
        facturas: g.facturas,
        sinFactura: g.sinFactura,
      );
    }).toList();
  }
}
