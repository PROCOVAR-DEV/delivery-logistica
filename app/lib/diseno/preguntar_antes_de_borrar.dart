import 'package:flutter/material.dart';

import 'cajon.dart';
import 'tema.dart';

/// LA PREGUNTA DE ANTES DE BORRAR, con el nombre de lo que se va.
///
/// La casa ya tenía la pieza y el literal: los puso «Borrar la columna» del
/// tablero el 25/09/2026, cuando Jose vio una zona desaparecer de un toque —
/// «sacame notificaciones emergentes para esto, no me pongas eso asi borrar por
/// borrar»—. Lo que no tenía era un sitio donde vivieran, así que la siguiente
/// pantalla que necesitara lo mismo volvía a escribirlo (o se lo saltaba, que es
/// lo que pasó con «Eliminar» de Vehículos hasta el 01/10/2026).
///
/// Las tres cosas que esta pieza garantiza, y que son las tres que se pierden al
/// escribirla a mano otra vez:
///
///  * **En un cajón, no en un `AlertDialog`** — también en escritorio, que es la
///    excepción aprobada el 05/09/2026 para este proyecto. Con la ✕ que pone el
///    cajón y que no desaparece.
///  * **El botón de borrar NOMBRA lo que se va**: «Sí, borrar «X»» dice qué
///    desaparece; «Aceptar» no dice nada. Y entra por [BotonDestructivo], así
///    que es rojo, con contorno de 2 px y con la papelera — sin relleno, como
///    todos.
///  * **Cerrar sin contestar es NO.** `abrirCajon` devuelve `null` al tocar
///    fuera o al dar Escape, y aquí eso es `false`: lo irreversible no se hace
///    por un descuido.
///
/// [loQuePasa] es la mitad que de verdad sirve, y por eso no tiene valor por
/// defecto: dice **qué se pierde y qué cuesta rehacerlo**. «¿Estás seguro?» no
/// es información, es un peaje.
Future<bool> preguntarAntesDeBorrar(
  BuildContext contexto, {
  required String queSeVa,
  required String loQuePasa,
  String noLoBorres = 'No, dejarla',
}) async {
  final seguro = await abrirCajon<bool>(
    contexto,
    titulo: 'Borrar «$queSeVa»',
    cuerpo: (contextoCajon) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(loQuePasa),
        const SizedBox(height: 20),
        BotonDestructivo(
          texto: 'Sí, borrar «$queSeVa»',
          alPulsar: () => Navigator.of(contextoCajon).pop(true),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(contextoCajon).pop(false),
          child: Text(noLoBorres),
        ),
      ],
    ),
  );
  return seguro ?? false;
}
