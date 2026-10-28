import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diseno/cajon.dart';
import '../diseno/colores.dart';
import '../nucleo/base/base.dart';
import '../nucleo/proveedores.dart';
import '../nucleo/sincro/cuadre.dart' show QuitadaDelCuadre;

/// LO QUE EL CUADRE QUITÓ DE ESTE APARATO, dicho con todas las letras (28/10/2026, Jose: «que notifique lo que
/// ocurrió»). El cuadre diario (`nucleo/sincro/cuadre.dart`) compara lo que el aparato guarda con lo que tiene el
/// servidor y quita lo que ya no existe; esto cuenta qué fue, por qué y qué hacer: nada. Se queda en la franja de
/// estado hasta que la persona pulsa «Entendido».
Future<void> abrirCajonDelCuadre(BuildContext context) =>
    abrirPanel<void>(context, (_) => const CajonDelCuadre());

class CajonDelCuadre extends ConsumerWidget {
  const CajonDelCuadre({super.key});

  static const _lasQueSeEnsenan = 40;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(avisoDelCuadreProvider);
    final tema = Theme.of(context);
    final facturas = [
      for (final q in r?.quitadas ?? const <QuitadaDelCuadre>[])
        if (q.coleccion == Colecciones.pedidos) q,
    ];
    final otras = (r?.quitadas.length ?? 0) - facturas.length;
    return Cajon(
      titulo: 'Se quitaron datos que ya no existen',
      pie: Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          key: const ValueKey('cuadre-entendido'),
          onPressed: () {
            ref.read(avisoDelCuadreProvider.notifier).entendido();
            Navigator.of(context).maybePop();
          },
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Entendido'),
        ),
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            'Este aparato guardaba datos que el servidor ya no tiene. Es normal si una factura se canceló o se '
            'retiró: la bajada del día no siempre avisa de todo, y por eso el aparato se cuadra con el servidor '
            'una vez al día. No tienes que hacer nada: lo quitado no estaba en ninguna ruta tuya ni tenía nada '
            'sin subir.',
            style: tema.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (facturas.isNotEmpty)
            Text(
              facturas.length == 1
                  ? '1 factura quitada'
                  : '${facturas.length} facturas quitadas',
              style: tema.textTheme.titleSmall,
            ),
          for (final q in facturas.take(_lasQueSeEnsenan))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(q.etiqueta ?? q.id, style: tema.textTheme.bodySmall),
            ),
          if (facturas.length > _lasQueSeEnsenan)
            Text(
              'y ${facturas.length - _lasQueSeEnsenan} más',
              style: tema.textTheme.bodySmall,
            ),
          if (otras > 0) ...[
            const SizedBox(height: 8),
            Text(
              otras == 1
                  ? '1 dato más (rutas, clientes, camiones…)'
                  : '$otras datos más (rutas, clientes, camiones…)',
              style: tema.textTheme.bodySmall,
            ),
          ],
          if ((r?.totalQueFaltaba ?? 0) > 0) ...[
            const SizedBox(height: 12),
            Text(
              r!.totalQueFaltaba == 1
                  ? 'Faltaba 1 dato que el servidor sí tiene'
                  : 'Faltaban ${r.totalQueFaltaba} datos que el servidor sí tiene',
              style: tema.textTheme.titleSmall,
            ),
            Text(
              'Se vuelven a bajar en la próxima descarga, sin que tengas que hacer nada.',
              style: tema.textTheme.bodySmall,
            ),
          ],
          if ((r?.apuntesCerrados ?? 0) > 0) ...[
            const SizedBox(height: 12),
            Text(
              r!.apuntesCerrados == 1
                  ? '1 apunte rechazado se cerró solo'
                  : '${r.apuntesCerrados} apuntes rechazados se cerraron solos',
              style: tema.textTheme.titleSmall?.copyWith(color: Colores.ambar),
            ),
            Text(
              'El servidor los había rechazado con «Esa factura no existe»: apuntaban a facturas que ya no están. '
              'No se borraron: quedan descartados con su motivo, por si hay que revisarlos.',
              style: tema.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
