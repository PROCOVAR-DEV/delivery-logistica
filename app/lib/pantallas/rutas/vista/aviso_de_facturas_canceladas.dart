// El aviso de «esta factura se canceló en Ventra y se quitó de su ruta».
//
// Jose y Amado, 23/10/2026: «la cancelada que ya va en una ruta, si ya no aparece, quitarla e
// INFORMAR que esa factura ya fue cancelada». El espejo la quita de la ruta y la deja marcada en el
// servidor (`orders.anulada_at`, 00027); la bajada la trae a `facturas_anuladas` (esquema 15) y de
// ahí sale esto.
//
// Dos formas del mismo texto:
//
//  * [AvisoDeFacturasCanceladas], arriba de la lista de Rutas: ámbar, PERSISTENTE mientras haya
//    alguna sin ver en este aparato, con «Entendido» que las deja vistas.
//  * [FacturasCanceladasDeLaRuta], dentro del detalle de la ruta afectada: las de esa ruta (vistas
//    o no, los 7 días que dura el aviso), sin botón.
//
// El dibujo está aparte de los conectores ([VistaDeFacturasCanceladas]) para probarlo suelto, a 390
// y a 1440 px, sin pasar por Drift dentro de un `testWidgets` (`CLAUDE.md` §5).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/proveedores.dart';
import '../datos/repositorio_rutas.dart';
import '../estado/proveedores_rutas.dart';

/// La frase de UNA factura. Sin emojis, con el cliente, la ruta y la hora.
String textoDeLaFacturaCancelada(FacturaCancelada c) {
  final f = c.factura;
  final cuando = DateFormat('d/M H:mm').format(f.anuladaAt.toLocal());
  final cual = (f.numero ?? '').isEmpty
      ? 'Una factura'
      : 'La factura ${f.numero}';
  final cliente = f.cliente.isEmpty ? '' : ' (${f.cliente})';
  final ruta = (c.rutaNombre ?? '').isEmpty
      ? 'de su ruta'
      : 'de la ruta ${c.rutaNombre}';
  return '$cual$cliente fue cancelada en Ventra y se quitó $ruta · $cuando';
}

/// Las claves que usan las pruebas.
const claveDelAvisoDeCanceladas = ValueKey('aviso-de-facturas-canceladas');
const claveDeEntendidoDeCanceladas = ValueKey('aviso-de-canceladas-entendido');

/// El dibujo. [alEntender] nulo = sin botón (el detalle de la ruta).
class VistaDeFacturasCanceladas extends StatelessWidget {
  const VistaDeFacturasCanceladas({
    super.key,
    required this.facturas,
    this.alEntender,
  });

  final List<FacturaCancelada> facturas;
  final VoidCallback? alEntender;

  @override
  Widget build(BuildContext context) {
    if (facturas.isEmpty) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Container(
        key: claveDelAvisoDeCanceladas,
        margin: const EdgeInsets.fromLTRB(Aire.sm, Aire.xs, Aire.sm, Aire.xs),
        padding: const EdgeInsets.all(Aire.sm),
        decoration: BoxDecoration(
          color: Colores.ambarFondo,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colores.ambar),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 18,
                  color: Colores.ambar,
                ),
                const SizedBox(width: Aire.xs),
                Expanded(
                  child: Text(
                    facturas.length == 1
                        ? 'Una factura cancelada se quitó de su ruta'
                        : '${facturas.length} facturas canceladas se quitaron de sus rutas',
                    style: Tipos.texto(
                      tamano: 13,
                      peso: FontWeight.w700,
                      color: Colores.tinta,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Aire.xs),
            // Una línea por factura. Con muchas, se desplaza DENTRO del aviso: no tapa la lista, y
            // ninguna se esconde tras un «y N más» (nada se descarta en silencio, §4).
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 132),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final c in facturas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Aire.xs),
                      child: Text(
                        textoDeLaFacturaCancelada(c),
                        style: Tipos.texto(tamano: 13, color: Colores.tinta),
                      ),
                    ),
                ],
              ),
            ),
            if (alEntender != null)
              Align(
                alignment: Alignment.centerRight,
                child: BotonPrincipal(
                  key: claveDeEntendidoDeCanceladas,
                  texto: 'Entendido',
                  icono: Icons.done_all,
                  alPulsar: alEntender,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Arriba de la lista de Rutas: las que nadie ha dado por vistas en este aparato.
class AvisoDeFacturasCanceladas extends ConsumerWidget {
  const AvisoDeFacturasCanceladas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facturas =
        ref.watch(facturasCanceladasSinVerProvider).value ??
        const <FacturaCancelada>[];
    return VistaDeFacturasCanceladas(
      facturas: facturas,
      alEntender: () => ref.read(consultasRutasProvider).marcarVistas([
        for (final c in facturas) c.factura.id,
      ], ref.read(relojProvider)()),
    );
  }
}

/// Dentro del detalle de la ruta: las que salieron de ESA ruta.
class FacturasCanceladasDeLaRuta extends ConsumerWidget {
  const FacturasCanceladasDeLaRuta({super.key, required this.rutaId});

  final String rutaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      VistaDeFacturasCanceladas(
        facturas:
            ref.watch(facturasCanceladasDeLaRutaProvider(rutaId)).value ??
            const <FacturaCancelada>[],
      );
}
