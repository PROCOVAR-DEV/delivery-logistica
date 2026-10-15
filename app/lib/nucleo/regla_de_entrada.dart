/// LA REGLA DE ENTRADA A UNA RUTA, EN EL APARATO, EN UN SOLO SITIO — 15/10/2026.
///
/// Entra en una ruta si y sólo si:
///
///  1. la factura es `igual` **o `cambiado`** ([facturaQueEntra]);
///  2. la factura cobró el domicilio, `facturaDomicilio > 0` ([domicilioSinCobrar]);
///  3. y Entrega lo cotizó (`pedidoCosto` no nulo) **sólo si el vendedor marcó domicilio**
///     ([faltaLaCotizacion]).
///
/// El porqué es el issue 10 de Amado (15/10/2026), con un caso real de Santiago:
/// PBF26-2610131268, factura 47061. Se pidió «PARRANDA 0.33L ×20» sin marcar domicilio,
/// Ventra facturó «CERVEZA PARRANDA 500 ML BLISTER 6U ×20» y cobró «ENTREGA A DOMICILIO»
/// 1.31. No se podía poner en ruta por dos cosas que ya no valen: `cambiado` no entraba
/// —pero sus renglones YA son los de la factura, así que al camión sube lo facturado— y se le
/// exigía la cotización de Entrega, que sólo cotiza los marcados: lo dejaba fuera para siempre.
///
/// Es la misma regla que el servidor (`rechazoDelArmado` y `motivoDeCorteDelArmado` en
/// `api/internal/api/`, y el SQL de las listas) y la atan los casos de
/// `docs/armado-rechazado.casos.json` (`reglaDeEntrada`), que leen las pruebas de los dos lados.
/// Quien necesite saber si un pedido entra pregunta aquí, no la vuelve a escribir.
library;

import 'package:drift/drift.dart';

import 'base/base.dart';

/// `igual` o `cambiado`. NULL es «sin cotejar» y no entra.
bool facturaQueEntra(String? estado) =>
    estado == EstadoFactura.igual || estado == EstadoFactura.cambiado;

/// La factura no trae un cobro de domicilio positivo. Un cero no demuestra que se cobró.
bool domicilioSinCobrar(double? facturaDomicilio) =>
    facturaDomicilio == null || facturaDomicilio <= 0;

/// Se marcó domicilio y Entrega todavía no lo cotizó. Sin marcar (falso o nulo: «nadie lo
/// marcó») la cotización no se exige. Un costo de CERO sí es una cotización.
bool faltaLaCotizacion({
  required double? pedidoCosto,
  required bool? requiereDomicilio,
}) => pedidoCosto == null && requiereDomicilio == true;

/// Las tres juntas, como expresión de Drift para las listas locales (Sin colocar del
/// tablero y disponibles del asistente).
Expression<bool> entraEnRuta($OrdersTable o) =>
    o.facturaEstado.isIn(const [EstadoFactura.igual, EstadoFactura.cambiado]) &
    o.facturaDomicilio.isBiggerThanValue(0) &
    (o.pedidoCosto.isNotNull() |
        o.requiereDomicilio.isNull() |
        o.requiereDomicilio.equals(false));

/// Las tres juntas en SQL de SQLite, para las consultas a mano (el Panel). `IS NOT 1` es el
/// `IS NOT TRUE` de Postgres: un NULL también pasa.
const entraEnRutaSql =
    "o.factura_estado IN ('igual', 'cambiado') "
    'AND o.factura_domicilio > 0 '
    'AND (o.pedido_costo IS NOT NULL OR o.requiere_domicilio IS NOT 1)';
