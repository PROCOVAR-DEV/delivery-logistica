import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/reloj.dart';

/// Las siete cifras de arriba del Panel.
class CifrasDelPanel {
  const CifrasDelPanel({
    required this.totalPedidos,
    required this.sinRuta,
    required this.rutasActivas,
    required this.entregadosHoy,
    required this.entregadosHoyEnRutaSinCerrar,
    required this.totalVehiculos,
    required this.vehiculosEnRuta,
    required this.pesoPendiente,
    required this.totalDomicilios,
  });

  static const cero = CifrasDelPanel(
    totalPedidos: 0,
    sinRuta: 0,
    rutasActivas: 0,
    entregadosHoy: 0,
    entregadosHoyEnRutaSinCerrar: 0,
    totalVehiculos: 0,
    vehiculosEnRuta: 0,
    pesoPendiente: 0,
    totalDomicilios: 0,
  );

  final int totalPedidos;
  final int sinRuta;
  final int rutasActivas;
  final int entregadosHoy;

  /// DE LOS DE ARRIBA, LOS QUE VIAJAN EN UNA RUTA QUE TODAVÍA NO SE HA CERRADO.
  ///
  /// Existe por una pregunta de Jose del 28/09/2026: «me dice q entregado uno y
  /// en hsitorial me sale vacio eso q se entrego si no se ah completado nada».
  /// Las dos cuentas estaban bien y decían cosas distintas —ésta cuenta PEDIDOS
  /// con `delivered_at` de hoy; el Historial de Rutas cuenta RUTAS cerradas, sin
  /// ventana de tiempo—, y un camión en la calle con una parada hecha sale en la
  /// primera y no en el segundo. Eso es lo normal y la pantalla no lo decía.
  ///
  /// Se cuenta para poder decirlo **sólo cuando pasa**: con todas las rutas
  /// cerradas esto es 0 y la tarjeta no explica nada, que es la otra mitad de la
  /// regla (`CLAUDE.md` §3-quinquies: un aviso que sale siempre deja de leerse).
  final int entregadosHoyEnRutaSinCerrar;

  final int totalVehiculos;
  final int vehiculosEnRuta;
  final double pesoPendiente;
  final double totalDomicilios;
}

/// Una fila de «Pendiente por sucursal».
class PendienteDeSucursal {
  const PendienteDeSucursal({
    required this.sucursal,
    required this.pedidos,
    required this.pesoKg,
  });

  final String sucursal;
  final int pedidos;
  final double pesoKg;
}

/// El Panel, calculado **en el aparato**.
///
/// Todo lo que pinta esta pantalla sale de la base local, no de
/// `GET /api/dashboard`: es la regla 2 (nunca esperar al servidor) y ademas es
/// lo que hace que la pantalla de la manana funcione en el patio del almacen sin
/// senal.
///
/// La definicion de REPARTIBLE esta escrita **una sola vez**, en [_repartible],
/// y es la de la lista de disponibles de Rutas (`ConsultasRutas.disponibles`):
/// de PEDIDO, sin ruta, con punto de entrega, factura que CUADRE (`igual`),
/// domicilio cobrado (`factura_domicilio > 0`) y domicilio cotizado
/// (`pedido_costo` no nulo). Tenerla dos veces es como se acaba con dos numeros
/// distintos para la misma pregunta, y el que sobra siempre es el que alguien
/// mira: el Panel decia «40 por repartir» y el armador ofrecia 12.
///
/// **Lo ata una prueba, no este comentario** (`CLAUDE.md` §3-bis):
/// `test/pantallas/panel/el_panel_cuenta_lo_que_ofrece_rutas_test.dart` siembra
/// un caso por condicion y compara el Panel con la lista.
class ConsultasPanel {
  ConsultasPanel(this._base, {Reloj reloj = relojDelAparato}) : _reloj = reloj;

  final BaseLocal _base;
  final Reloj _reloj;

  static const _repartible =
      "o.source = 'pedido' AND o.route_id IS NULL "
      "AND o.end_lat IS NOT NULL AND o.end_lng IS NOT NULL "
      "AND o.factura_estado = 'igual' "
      "AND o.factura_domicilio > 0 AND o.pedido_costo IS NOT NULL";

  // «EN MARCHA» ES LA QUE SALIÓ, y una planificada no ha salido — 22/09/2026.
  //
  // Aquí ponía `status NOT IN ('completed','cancelled')`, que suma las
  // planificadas. En el teléfono de Jose el Panel decía «Rutas en marcha: 6» y
  // Rutas → En curso decía **1**: las otras cinco estaban planificadas, quietas
  // en la oficina. Dos pantallas contestando distinto a la misma pregunta, y la
  // que se lee de un vistazo es la que estaba mal.
  //
  // Lo que falta de la vista no se pierde: las planificadas están en Rutas, con
  // su propia pestaña y su propio número.
  static const _enMarcha = "status = '${EstadoRuta.enCurso}'";

  /// Las 00:00 de hoy **con el reloj del APARATO**. No es un detalle: sin red el
  /// aparato es el unico reloj que hay, y lo entregado «hoy» tiene que cuadrar
  /// con el dia que la persona esta viviendo, no con el del servidor.
  DateTime get medianoche {
    final ahora = _reloj();
    return DateTime(ahora.year, ahora.month, ahora.day);
  }

  Stream<CifrasDelPanel> cifras({String? sucursalId}) {
    // `?1 IS NULL OR …` en vez de dos consultas: una sola sentencia, un solo
    // `watch`, y la version «todas las sucursales» no puede quedarse atras de la
    // version filtrada porque son el mismo SQL.
    final sql =
        '''
SELECT
  (SELECT COUNT(*) FROM orders o
     WHERE (?1 IS NULL OR o.branch_id = ?1)) AS total_pedidos,
  (SELECT COUNT(*) FROM orders o
     WHERE (?1 IS NULL OR o.branch_id = ?1) AND $_repartible) AS sin_ruta,
  (SELECT COALESCE(SUM(o.weight), 0) FROM orders o
     WHERE (?1 IS NULL OR o.branch_id = ?1) AND $_repartible) AS peso_pendiente,
  (SELECT COALESCE(SUM(o.pedido_costo), 0) FROM orders o
     WHERE (?1 IS NULL OR o.branch_id = ?1)) AS total_domicilios,
  (SELECT COUNT(*) FROM orders o
     WHERE (?1 IS NULL OR o.branch_id = ?1)
       AND o.delivered_at IS NOT NULL
       AND o.delivered_at >= ?2) AS entregados_hoy,
  -- LOS DE HOY QUE SIGUEN EN UNA RUTA ABIERTA. Mismo `WHERE` que el de arriba
  -- —se lee justo encima, y por eso van pegados— más la ruta que lo lleva.
  --
  -- `status <> 'completed'` y no `= 'in_progress'`: lo que hace que el Historial
  -- de Rutas no lo enseñe es que la ruta NO esté cerrada, no que esté rodando.
  -- Una planificada o una cancelada tampoco salen allí.
  (SELECT COUNT(*) FROM orders o
     WHERE (?1 IS NULL OR o.branch_id = ?1)
       AND o.delivered_at IS NOT NULL
       AND o.delivered_at >= ?2
       AND o.route_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM routes r
                    WHERE r.id = o.route_id
                      AND r.status <> '${EstadoRuta.completada}')
  ) AS entregados_hoy_sin_cerrar,
  (SELECT COUNT(*) FROM routes r
     WHERE (?1 IS NULL OR r.branch_id = ?1) AND $_enMarcha) AS rutas_activas,
  (SELECT COUNT(*) FROM vehicles v
     WHERE (?1 IS NULL OR v.branch_id = ?1)) AS total_vehiculos,
  -- EL CAMIÓN SALE DE LA RUTA, no del pedido.
  --
  -- El vehículo de cada pedido sale de la ruta en la que viaja; `orders.vehicle_id`
  -- se eliminó porque duplicaba esa relación. Así el Panel cuenta las asignaciones
  -- reales que viven en `routes.vehicle_id`.
  (SELECT COUNT(DISTINCT r.vehicle_id) FROM routes r
     WHERE r.vehicle_id IS NOT NULL
       AND (?1 IS NULL OR r.branch_id = ?1)
       AND r.$_enMarcha) AS vehiculos_en_ruta
''';

    return _base
        .customSelect(
          sql,
          variables: [
            Variable<String>(sucursalId),
            Variable<DateTime>(medianoche),
          ],
          readsFrom: {_base.orders, _base.routes, _base.vehicles},
        )
        .watchSingle()
        .map(
          (fila) => CifrasDelPanel(
            totalPedidos: fila.read<int>('total_pedidos'),
            sinRuta: fila.read<int>('sin_ruta'),
            rutasActivas: fila.read<int>('rutas_activas'),
            entregadosHoy: fila.read<int>('entregados_hoy'),
            entregadosHoyEnRutaSinCerrar: fila.read<int>(
              'entregados_hoy_sin_cerrar',
            ),
            totalVehiculos: fila.read<int>('total_vehiculos'),
            vehiculosEnRuta: fila.read<int>('vehiculos_en_ruta'),
            pesoPendiente: fila.read<double>('peso_pendiente'),
            totalDomicilios: fila.read<double>('total_domicilios'),
          ),
        );
  }

  /// EL NOMBRE DE LA SUCURSAL QUE SE ESTA MIRANDO, o `null` mientras no se sepa.
  ///
  /// Las siete cifras de arriba son de UNA sucursal —la del selector de la barra
  /// superior—, y eso no se veia por ninguna parte. El 28/09/2026 fue la mitad
  /// de la confusion: la ruta completada que Jose buscaba existia, pero era de
  /// La Habana y el estaba mirando Santiago.
  ///
  /// `null` con la sucursal puesta y el nombre todavia sin bajar: se prefiere no
  /// escribir nada a escribir un hueco o un identificador. En la web eso dura un
  /// segundo, y por eso es un `Stream` y no un `Future` (`CLAUDE.md` §3-ter):
  /// cuando `branches` baje, la linea aparece sola.
  Stream<String?> nombreDeLaSucursal(String? sucursalId) {
    if (sucursalId == null || sucursalId.isEmpty) {
      return Stream<String?>.value(null);
    }
    return (_base.select(_base.branches)..where((b) => b.id.equals(sucursalId)))
        .watchSingleOrNull()
        .map((fila) => fila?.name);
  }

  /// «Pendiente por sucursal», ordenado de mas a menos pedidos.
  ///
  /// `'Sin sucursal'` cuando el pedido no trae `branch_id` o apunta a una
  /// sucursal que no esta bajada: se agrupa igual y se dice, en vez de
  /// desaparecer de la suma y dejar la tarjeta sin cuadrar con la de arriba.
  Stream<List<PendienteDeSucursal>> porSucursal({String? sucursalId}) {
    const sql =
        '''
SELECT COALESCE(b.name, 'Sin sucursal') AS sucursal,
       COUNT(*) AS pedidos,
       COALESCE(SUM(o.weight), 0) AS peso
  FROM orders o
  LEFT JOIN branches b ON b.id = o.branch_id
 WHERE (?1 IS NULL OR o.branch_id = ?1)
   AND $_repartible
 GROUP BY COALESCE(b.name, 'Sin sucursal')
 ORDER BY pedidos DESC
''';

    return _base
        .customSelect(
          sql,
          variables: [Variable<String>(sucursalId)],
          readsFrom: {_base.orders, _base.branches},
        )
        .watch()
        .map(
          (filas) => filas
              .map(
                (f) => PendienteDeSucursal(
                  sucursal: f.read<String>('sucursal'),
                  pedidos: f.read<int>('pedidos'),
                  pesoKg: f.read<double>('peso'),
                ),
              )
              .toList(),
        );
  }
}
