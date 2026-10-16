// La ficha del pedido, en cajon `lg`. Sólo lectura: en esta pantalla no hay
// ninguna accion de escritura, y por eso no toca la cola.
//
// Sale entera de la base local, incluidas las bandas de factura y el bloque de
// domicilio: sin conexion la ficha se abre igual, y lo unico que falta son los
// pedidos que todavia no bajaron.

import 'package:flutter/material.dart';

import '../../../nucleo/frescura/reloj_de_datos.dart';
import '../../../nucleo/frescura/primera_bajada.dart';
import '../../../nucleo/numero_de_factura.dart';
import '../../../nucleo/plataforma.dart';
import '../../../nucleo/regla_de_entrada.dart' show facturaQueEntra;
import '../../../nucleo/texto_de_fuera.dart' show sinLaComillaDeExcel;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../tablero/datos/repositorio.dart' show porQueNoSePuedeColocar;
import '../datos/formato.dart';
import '../datos/repositorio_pedidos.dart';
import '../estado/proveedores_pedidos.dart';
import 'kit.dart';

class CajonDetallePedido extends ConsumerWidget {
  const CajonDetallePedido({required this.pedidoId, super.key});

  final String pedidoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detalle = ref.watch(detallePedidoProvider(pedidoId));

    return detalle.when(
      loading: () => const Cajon(
        titulo: 'Cargando...',
        cuerpo: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (fallo, _) => Cajon(
        titulo: 'No se pudo abrir',
        cuerpo: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('$fallo'),
        ),
      ),
      data: (ficha) {
        if (ficha == null) {
          // LA ULTIMA FRASE DEL APARATO QUE QUEDABA SUELTA EN LA WEB.
          //
          // «No esta en el aparato» y «Con conexion baja sola» son dos de las
          // cinco que Jose lleva seis veces pidiendo que desaparezcan, y aqui no
          // habia ninguna guarda. Camino estrecho —se abre la ficha de un pedido
          // que ya no esta en la base en ese instante— pero es la frase literal.
          //
          // Y en la web el motivo real es otro: la base nace vacia en cada carga,
          // asi que o todavia esta bajando, o la bajada no llego.
          return Cajon(
            titulo: Destino.trabajaSinConexion
                ? 'No está en el aparato'
                : 'No se encontró el pedido',
            cuerpo: EstadoVacio(switch (ref.watch(porQueEstaVacioProvider)) {
              PorQueEstaVacio.noSeDescargo =>
                SinDescargar.textoDeLaPantallaVacia,
              PorQueEstaVacio.todaviaBajando => TextosDeLaWeb.cargando(
                'el pedido',
              ),
              PorQueEstaVacio.noPudoBajar => TextosDeLaWeb.noPudoBajar(
                'los pedidos',
              ),
            }),
          );
        }
        return _Ficha(ficha: ficha);
      },
    );
  }
}

class _Ficha extends StatelessWidget {
  const _Ficha({required this.ficha});

  final DetallePedido ficha;

  @override
  Widget build(BuildContext context) {
    final p = ficha.pedido;
    return Cajon(
      titulo: p.customerName,
      subtitulo: p.operationNumber,
      cuerpo: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Seccion(
              titulo: 'Entrega',
              hijos: [
                Text(p.endAddress ?? p.address),
                if (p.endLat != null && p.endLng != null)
                  Text(
                    '${p.endLat!.toStringAsFixed(5)}, '
                    '${p.endLng!.toStringAsFixed(5)}',
                    style: TextStyle(color: Colores.gris),
                  ),
                // Sin la comilla de Excel, igual que en el cajón de mover un
                // pedido del tablero. Ver `nucleo/texto_de_fuera.dart`.
                if (p.customerPhone != null)
                  Text(sinLaComillaDeExcel(p.customerPhone!)),
              ],
            ),
            _Seccion(
              titulo: 'Recorrido',
              hijos: [
                // El mapa de 220 px es de la ola de `lib/mapas/` y todavia no
                // existe. Se deja el PIE literal del pliego, que es lo que dice
                // desde donde se mide, y no un hueco mudo que parezca un fallo.
                Text(
                  ficha.almacen == null
                      ? 'Sin coordenadas GPS para esta ruta'
                      : 'Del almacén (${ficha.almacen!.nombre}) al cliente.',
                  style: TextStyle(color: Colores.gris),
                ),
              ],
            ),
            _BandaFactura(pedido: p),
            _Domicilio(pedido: p),
            _Seccion(
              titulo: 'Productos (${ficha.renglones.length})',
              hijos: ficha.renglones.isEmpty
                  ? const [Text('Sin productos')]
                  : [
                      for (final r in ficha.renglones)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          // LOS EMPAQUES PRIMERO, LAS UNIDADES DETRÁS — Amado,
                          // 14/10/2026 (issue 6): lo importante es el blíster,
                          // «que es como cargan y transportan». Antes salían las
                          // unidades delante, y además sin mirar si `quantity` era
                          // de fiar. Ver `RenglonConPeso.cantidadEnTexto`.
                          child: Text(
                            '${r.renglon.description} · '
                            '${r.cantidadEnTexto()} · '
                            '${r.pesoLinea == null ? 'sin peso' : kg(r.pesoLinea)}',
                          ),
                        ),
                    ],
            ),
            if (ficha.ruta != null)
              _Seccion(
                titulo: 'Ruta',
                hijos: [
                  Text(ficha.ruta!.routeCode ?? ficha.ruta!.id),
                  if (ficha.vehiculo != null) Text(ficha.vehiculo!.name),
                  Text(fechaCorta(ficha.ruta!.deliveryDate)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.hijos});

  final String titulo;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        ...hijos,
      ],
    ),
  );
}

class _BandaFactura extends StatelessWidget {
  const _BandaFactura({required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final numero = NumeroDeFactura.de(pedido.facturaNumero) ?? '—';
    // EL NÚMERO Y LA FECHA, DELANTE Y GRANDES — Amado, 14/10/2026 (issues 6 y 8). Hasta
    // hoy el número sólo salía metido en la frase de abajo y la fecha no salía.
    final cabecera = etiquetaDeFactura(
      pedido.facturaNumero,
      facturadaEl: pedido.facturaAt,
    );
    // `cambiado` YA NO DICE «no entra a una ruta» (issue 10 de Amado, 15/10/2026):
    // PBF26-2610131268 salía así y sí entra. Al camión va lo facturado, y los
    // productos de abajo ya son los de la factura (`itemsOrigen`).
    final (texto, color) = switch (pedido.facturaEstado) {
      EstadoFactura.igual => (
        'Cuadra con la factura $numero de Ventra: lo pedido es lo facturado.',
        Colores.verde,
      ),
      // «Los productos de abajo» sólo se afirma cuando `itemsOrigen` lo dice: un
      // `cambiado` cuyo cotejo no ató la factura a ESTE pedido trae los renglones
      // del pedido, y nulo es «no se sabe» (`Orders.itemsOrigen`).
      EstadoFactura.cambiado => (
        'Se facturó algo distinto de lo pedido (factura $numero). Al camión va '
            'lo facturado${switch (pedido.itemsOrigen) {
              'factura' => ': los productos de abajo ya son los de la factura.',
              Procedencia.pedido => ', pero los productos de abajo son los del '
                  'pedido: la factura no se pudo atar a este pedido.',
              _ => '.',
            }}',
        Colores.ambar,
      ),
      _ => ('Todavía no aparece facturado en Ventra.', Colores.gris),
    };
    // La banda sólo habla de la ruta cuando hay factura que cargar.
    final ruta = facturaQueEntra(pedido.facturaEstado)
        ? lineaDeRutaDeLaFicha(pedido)
        : null;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cabecera != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                cabecera,
                key: const ValueKey('ficha-factura'),
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ),
          Text(texto, style: TextStyle(color: color)),
          if (ruta != null)
            Text(
              ruta,
              key: const ValueKey('ficha-ruta'),
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          if (pedido.facturaDomicilio != null)
            Text(
              'La factura cobró '
              '${pedido.facturaDomicilio!.toStringAsFixed(2)} USD de domicilio.',
              style: TextStyle(color: color),
            ),
        ],
      ),
    );
  }
}

/// LO QUE LA FICHA DICE DE LA RUTA, o `null` si no dice nada.
///
/// **No repite la regla: le pregunta a [porQueNoSePuedeColocar]**, la misma pieza
/// que el arrastre del tablero y el «Sin cobro de domicilio» de la tabla, que a su
/// vez lee `nucleo/regla_de_entrada.dart`. «No entra» sale SÓLO cuando de verdad no
/// entra por el domicilio: sin cobrar en la factura (la cotización de Entrega no
/// cuenta, Amado 16/10/2026). Un
/// entregado, uno que ya va en una ruta o uno archivado no tienen nada que decir
/// aquí (lo cuenta el resto de la ficha), y uno sin punto de entrega tampoco puede
/// ir, así que no se le dice que puede.
String? lineaDeRutaDeLaFicha(Pedido pedido) {
  final motivo = porQueNoSePuedeColocar(pedido);
  if (motivo == null &&
      !pedido.archivado &&
      pedido.endLat != null &&
      pedido.endLng != null) {
    return 'Puede ir a una ruta.';
  }
  return null;
}

class _Domicilio extends StatelessWidget {
  const _Domicilio({required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final conPrecio = pedido.pedidoCosto != null;
    // Sin precio es un DATO, no un aviso (Amado, 16/10/2026: para ir a una ruta lo que
    // manda es el cobro en la factura): gris, nunca ámbar.
    final color = conPrecio ? Colores.verde : Colores.gris;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Distancia ${km(pedido.deliveryDistanceKm)} · '
                  'Peso total ${kg(pedido.weight)}',
                ),
              ),
              Text(
                conPrecio ? usd(pedido.pedidoCosto) : 'Sin calcular todavía',
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            conPrecio
                ? 'El costo lo puso el repartidor desde Entrega. '
                      'La distancia es del almacén al cliente.'
                : 'Entrega todavía no lo cotizó. No hace falta para ir a una ruta: '
                      'lo que cuenta es el cobro de domicilio en la factura.',
            style: TextStyle(fontSize: 12, color: Colores.gris),
          ),
        ],
      ),
    );
  }
}
