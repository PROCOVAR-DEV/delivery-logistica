import 'package:flutter/material.dart';

import 'colores.dart';
import 'tema.dart';

/// LA MARCA «DEVUELTA» (issue 25 de Amado, 05/11/2026): una factura que volvió del camión y sigue sin ruta
/// se distingue de las nuevas que han entrado. Color, BORDE e icono, sin emojis y sin relleno sólido
/// (CLAUDE.md §4): la pastilla de [Insignia] no basta porque «Devuelto» ya salía en ámbar y no se veía.
///
/// Una sola en la aplicación: la usan la tabla y la tarjeta del teléfono de Facturas, «Sin colocar» del
/// Tablero y la ficha.
class MarcaDevuelta extends StatelessWidget {
  const MarcaDevuelta({super.key});

  static const texto = 'Devuelta';
  static const ayuda =
      'Esta factura volvió del camión y sigue sin ruta: se puede poner en otra o cancelar.';

  @override
  Widget build(BuildContext context) => Tooltip(
    message: ayuda,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Colores.ambar, width: 1.4),
        borderRadius: BorderRadius.circular(Radios.pastilla),
      ),
      // `FittedBox`: en la columna estrecha de la tabla la marca se encoge en vez de desbordar.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.undo, size: 13, color: Colores.ambar),
            const SizedBox(width: 4),
            Text(
              texto,
              style: Tipos.texto(
                tamano: 11,
                peso: FontWeight.w700,
                color: Colores.ambar,
                interletra: 0.1,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
