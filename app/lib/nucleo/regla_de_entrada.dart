/// LA REGLA DE ENTRADA A UNA RUTA, EN EL APARATO, EN UN SOLO SITIO — 16/10/2026.
///
/// Entra en una ruta si y sólo si:
///
///  1. la factura es `igual` **o `cambiado`** ([facturaQueEntra]).
///
/// NADA MÁS. TEMPORAL 16/10/2026 (Jose): hasta que la factura mande sobre el pedido; para volver a exigir el cobro, restaurar `factura_domicilio > 0` (ver Notas/Pendiente/Delivery.md).
/// Ni la casilla «requiere domicilio», ni la cotización de Entrega (`pedidoCosto`), ni el cobro
/// del domicilio (`facturaDomicilio`) deciden si entra: Jose, 16/10/2026, «por ahora que entren
/// todos los pedidos con facturas»; el logístico busca sólo los cobrados con el filtro «Cobro del
/// domicilio» (`conCobroDeDomicilio`). Hasta hoy se exigía el cobro (Amado, 07/10/2026) y, si el
/// vendedor marcó domicilio, la cotización (quitada antes, el mismo día).
///
/// El porqué son dos casos reales de Santiago. PBF26-2610131268 (issue 10, 15/10/2026): factura
/// 47061, se pidió «PARRANDA 0.33L ×20» sin marcar domicilio, Ventra facturó otra cosa
/// (`cambiado`) y cobró «ENTREGA A DOMICILIO» 1.31; `cambiado` no entraba y se le exigía la
/// cotización. Y PCC25-261014-1435 (16/10/2026): factura 47073, `igual`, MARCADO, 0.05 cobrado y
/// Entrega no lo cotizó: se quedaba fuera y ayer se armaron rutas sin él.
///
/// Es la misma regla que el servidor (`rechazoDelArmado` y `motivoDeCorteDelArmado` en
/// `api/internal/api/`, y el SQL de las listas) y la atan los casos de
/// `docs/armado-rechazado.casos.json` (`reglaDeEntrada` y `costoDeLaParada`), que leen las
/// pruebas de los dos lados. Quien necesite saber si un pedido entra pregunta aquí, no la
/// vuelve a escribir.
library;

import 'package:drift/drift.dart';

import 'base/base.dart';

/// `igual` o `cambiado`. NULL es «sin cotejar» y no entra.
bool facturaQueEntra(String? estado) =>
    estado == EstadoFactura.igual || estado == EstadoFactura.cambiado;

/// La factura no trae un cobro de domicilio positivo. Un cero no demuestra que se cobró. Hoy es
/// sólo un DATO (la tabla de Pedidos lo señala); NO decide si un pedido entra en una ruta.
bool domicilioSinCobrar(double? facturaDomicilio) =>
    facturaDomicilio == null || facturaDomicilio <= 0;

/// El costo del domicilio de una PARADA: el `pedidoCosto` que cotizó Entrega y, si no hay, lo que
/// la factura cobró (`facturaDomicilio > 0`). Sin ninguno de los dos, nulo = sin cotizar de
/// verdad. Un costo de CERO cotizado SÍ es una cotización y no se pisa. Es `costoDeLaParada` del
/// servidor (`api/internal/api/rutas.go`); lo ata `costoDeLaParada` del fichero de casos.
double? costoDeLaParada(double? pedidoCosto, double? facturaDomicilio) =>
    pedidoCosto ??
    (facturaDomicilio != null && facturaDomicilio > 0
        ? facturaDomicilio
        : null);

/// [costoDeLaParada] en SQL de SQLite, para las sumas a mano (importe de las rutas, costo de
/// una zona). `prefijo` es el alias de `orders` con su punto, o vacío.
String costoDeLaParadaSql([String prefijo = '']) =>
    'COALESCE(${prefijo}pedido_costo, CASE WHEN ${prefijo}factura_domicilio > 0 '
    'THEN ${prefijo}factura_domicilio END)';

/// La regla, como expresión de Drift para las listas locales (Sin colocar del
/// tablero y disponibles del asistente).
///
/// TEMPORAL 16/10/2026 (Jose): hasta que la factura mande sobre el pedido; para volver a exigir el cobro, restaurar `factura_domicilio > 0` (ver Notas/Pendiente/Delivery.md).
Expression<bool> entraEnRuta($OrdersTable o) =>
    o.facturaEstado.isIn(const [EstadoFactura.igual, EstadoFactura.cambiado]);

/// LLEVA DOMICILIO: el vendedor lo marcó O la factura lo cobró (`facturaDomicilio > 0`). Es el
/// filtro `domicilio` de los pedidos («Sólo con domicilio» = `1`), el mismo que el SQL de
/// `ListarPedidos`/`ListarPedidosDisponibles` y sus contadores, atado por `filtroDeDomicilio`
/// de `docs/armado-rechazado.casos.json`. Con sólo la casilla, el asistente —que arranca en
/// «Sólo con domicilio»— escondía el caso del issue 10 (PBF26-2610131268, sin marcar y con
/// 1.31 cobrado). Ninguna de las dos ramas da NULL, así que «Sólo sin domicilio» es
/// `conDomicilio(o).not()`, el contrario exacto (nulo no es llevarlo; un cero no es cobro).
Expression<bool> conDomicilio($OrdersTable o) =>
    o.requiereDomicilio.isValue(true) |
    coalesce([o.facturaDomicilio, const Constant(0.0)]).isBiggerThanValue(0);

/// [entraEnRuta] en SQL de SQLite, para las consultas a mano (el Panel).
///
/// TEMPORAL 16/10/2026 (Jose): hasta que la factura mande sobre el pedido; para volver a exigir el cobro, restaurar `factura_domicilio > 0` (ver Notas/Pendiente/Delivery.md).
const entraEnRutaSql = "o.factura_estado IN ('igual', 'cambiado')";
