// LA LISTA DE TODAS LAS PARADAS DE LA RUTA EN CURSO, cada una con su estado (issue 26 de Amado,
// 06/11/2026): hasta hoy la ruta guiada solo ensenaba LA parada de ahora, y el distribuidor no veia
// cuales llevaba entregadas, cobradas o devueltas. El estado sale de `estadoDeLaParada` (uno solo, en
// `diseno/estado_de_parada.dart`) y refleja ya lo marcado en el aparato aunque aun no haya subido.
import 'package:flutter/material.dart';

import '../diseno/colores.dart';
import '../diseno/estado_de_parada.dart';
import '../diseno/tema.dart';
import '../nucleo/base/base.dart';
import 'parada_actual.dart';

ValueKey<String> claveDeLaFilaDeParada(String pedidoId) =>
    ValueKey('guia-fila-$pedidoId');

class ParadasDeLaRuta extends StatelessWidget {
  const ParadasDeLaRuta({
    required this.paradas,
    required this.cobros,
    this.actualId,
    super.key,
  });

  final List<Pedido> paradas;

  /// `cobros_de_entrega` del aparato (`cobrosDeEntregaProvider`).
  final Map<String, bool> cobros;

  /// La parada de ahora: lleva «Ahora» y un borde mas fuerte.
  final String? actualId;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Paradas de la ruta (${paradas.length})',
          key: const ValueKey('guia-paradas-titulo'),
          style: tema.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        for (final (i, p) in enOrdenDeVisita(paradas).indexed)
          _Fila(
            numero: i + 1,
            parada: p,
            estado: estadoDeLaParada(p, cobros),
            esLaActual: p.id == actualId,
          ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.numero,
    required this.parada,
    required this.estado,
    required this.esLaActual,
  });

  final int numero;
  final Pedido parada;
  final EstadoDeParada estado;
  final bool esLaActual;

  @override
  Widget build(BuildContext context) {
    final factura = (parada.facturaNumero ?? '').trim();
    return Container(
      key: claveDeLaFilaDeParada(parada.id),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(
          color: esLaActual ? Colores.tinta : Colores.linea,
          width: esLaActual ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(Radios.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$numero.',
            style: Tipos.mono(tamano: 16, peso: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  parada.customerName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (factura.isNotEmpty)
                  Text(
                    'Factura $factura',
                    style: TextStyle(fontSize: 14, color: Colores.tintaSuave),
                  ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    EtiquetaDeEstadoDeParada(
                      estado,
                      tamano: 15,
                      motivo: estado == EstadoDeParada.noEntregada
                          ? parada.resultadoNota
                          : null,
                    ),
                    if (esLaActual)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.navigation_outlined, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            'Ahora',
                            key: const ValueKey('guia-fila-ahora'),
                            style: Tipos.texto(
                              tamano: 15,
                              peso: FontWeight.w700,
                              color: Colores.tinta,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
