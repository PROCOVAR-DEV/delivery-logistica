// EL ESTADO DE UNA PARADA, dicho UNA vez (issue 26 de Amado, 06/11/2026): «si se visualizan las
// paradas (entregas) se sepa si ya fue entregada, cobrada, etc.».
//
// Hay DOS piezas y no se repiten en ninguna pantalla (CLAUDE.md §3-sexies, la regla vive en un sitio):
//
//  · [estadoDeParada] decide el estado a partir de `(resultado, cobroEntrega)`. Es pura.
//  · [EtiquetaDeEstadoDeParada] lo pinta: color + borde + icono + texto. SIN fondo relleno y sin
//    emojis (la regla de la casa para lo que se toca o se lee al sol); el texto va SIEMPRE, el color
//    solo no basta y el icono de cada estado es distinto.
//
// «Cobrada / sin cobrar» solo existe para las entregadas: un devuelto no muestra cobro. Y una
// entregada cuyo cobro nadie anoto (la cerro la oficina, que no pregunta el cobro) es solo
// «Entregada», sin inventar un «sin cobrar».
//
// Lo ata `test/diseno/estado_de_parada_test.dart`.
import 'package:flutter/material.dart';

import '../nucleo/base/base.dart' show Pedido;
import '../nucleo/base/tablas/catalogos.dart' show ResultadoParada;
import 'colores.dart';
import 'tema.dart';

enum EstadoDeParada {
  pendiente('Pendiente', Icons.schedule),
  entregadaCobrada('Entregada · cobrada', Icons.paid_outlined),
  entregadaSinCobrar('Entregada · sin cobrar', Icons.money_off_outlined),
  entregada('Entregada', Icons.check_circle_outline),
  noEntregada('No entregada', Icons.undo),
  cancelada('Cancelada', Icons.block);

  const EstadoDeParada(this.texto, this.icono);

  /// La palabra que se lee SIEMPRE.
  final String texto;
  final IconData icono;

  /// El tono de mando (7 de contraste sobre el papel): se lee con sol.
  Color get color => switch (this) {
    pendiente => Colores.grisMando,
    entregadaCobrada || entregada => Colores.verdeMando,
    entregadaSinCobrar => Colores.ambarMando,
    noEntregada => Colores.rojoMando,
    cancelada => Colores.tinta,
  };
}

/// EL ESTADO de una parada. [resultado] es `orders.resultado` (`entregado`, `devuelto`,
/// `cancelado`; el servidor tambien dice `no_entregada` en el recorrido) y [cobroEntrega] es
/// `orders.cobro_entrega` (`cobrado` | `no_cobrado` | nulo).
EstadoDeParada estadoDeParada(String? resultado, String? cobroEntrega) =>
    switch (resultado) {
      null => EstadoDeParada.pendiente,
      ResultadoParada.entregado => switch (cobroEntrega) {
        'cobrado' => EstadoDeParada.entregadaCobrada,
        'no_cobrado' => EstadoDeParada.entregadaSinCobrar,
        _ => EstadoDeParada.entregada,
      },
      ResultadoParada.cancelado => EstadoDeParada.cancelada,
      // `devuelto` y `no_entregada`: lo que volvio al camion.
      _ => EstadoDeParada.noEntregada,
    };

/// El cobro de una parada de ESTE aparato: lo que el distribuidor marco aqui (`cobros_de_entrega`,
/// que se escribe al marcar, antes de subir) manda; si no hay, lo que bajo del servidor
/// (`orders.cobro_entrega`). Asi una parada marcada sin conexion ya se ve cobrada antes de subir.
String? cobroDeLaParada(Pedido parada, Map<String, bool> locales) {
  final local = locales[parada.id];
  if (local == null) return parada.cobroEntrega;
  return local ? 'cobrado' : 'no_cobrado';
}

/// El estado de un `Pedido` de la base, con el cobro local si lo hay.
EstadoDeParada estadoDeLaParada(
  Pedido parada,
  Map<String, bool> cobrosLocales,
) => estadoDeParada(parada.resultado, cobroDeLaParada(parada, cobrosLocales));

/// La etiqueta de estado. [motivo] sale debajo (el «por que no se entrego»), solo si hay.
class EtiquetaDeEstadoDeParada extends StatelessWidget {
  const EtiquetaDeEstadoDeParada(
    this.estado, {
    this.motivo,
    this.tamano = 14,
    super.key,
  });

  final EstadoDeParada estado;
  final String? motivo;

  /// El tamano de la letra. 16 en el telefono del distribuidor, que se lee en la calle.
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final nota = (motivo ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // `FittedBox`: en una columna estrecha la etiqueta se encoge en vez de desbordar.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: estado.color, width: 1.6),
            borderRadius: BorderRadius.circular(Radios.pastilla),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(estado.icono, size: tamano + 2, color: estado.color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  estado.texto,
                  key: ValueKey('estado-de-parada-${estado.name}'),
                  style: Tipos.texto(
                    tamano: tamano,
                    peso: FontWeight.w700,
                    color: estado.color,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (nota.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4),
            child: Text(
              nota,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Tipos.texto(tamano: tamano - 1, color: Colores.tinta),
            ),
          ),
      ],
    );
  }
}
