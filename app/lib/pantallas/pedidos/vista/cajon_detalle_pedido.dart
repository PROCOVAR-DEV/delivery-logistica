// La ficha del pedido, en cajon `lg`. Sólo lectura: en esta pantalla no hay
// ninguna accion de escritura, y por eso no toca la cola.
//
// Sale entera de la base local, incluidas las bandas de factura y el bloque de
// domicilio: sin conexion la ficha se abre igual, y lo unico que falta son los
// pedidos que todavia no bajaron.

import 'package:flutter/material.dart';

import '../../../nucleo/frescura/reloj_de_datos.dart';
import '../../../nucleo/frescura/primera_bajada.dart';
import '../../../nucleo/plataforma.dart';
import '../../../nucleo/texto_de_fuera.dart' show sinLaComillaDeExcel;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
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
                          child: Text(
                            '${r.renglon.description} · '
                            '${cantidad(r.renglon.quantity)} '
                            '${r.renglon.quantity == 1 ? 'unidad' : 'unidades'} · '
                            '×${cantidad(r.empaques)} '
                            '${r.empaques == 1 ? 'empaque' : 'empaques'} · '
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
    final numero = pedido.facturaNumero ?? '—';
    final (texto, color) = switch (pedido.facturaEstado) {
      EstadoFactura.igual => (
        'Cuadra con la factura $numero de Ventra: se puede repartir tal cual.',
        Colores.verde,
      ),
      EstadoFactura.cambiado => (
        'Se facturó algo distinto de lo pedido (factura $numero). '
            'No cuadra con la factura, así que no entra a una ruta.',
        Colores.ambar,
      ),
      _ => ('Todavía no aparece facturado en Ventra.', Colores.gris),
    };

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
          Text(texto, style: TextStyle(color: color)),
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

class _Domicilio extends StatelessWidget {
  const _Domicilio({required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final conPrecio = pedido.pedidoCosto != null;
    final color = conPrecio ? Colores.verde : Colores.ambar;

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
                : 'El costo lo pone el repartidor desde Entrega; hasta entonces '
                      'este pedido no tiene precio de domicilio.',
            style: TextStyle(fontSize: 12, color: Colores.gris),
          ),
        ],
      ),
    );
  }
}
