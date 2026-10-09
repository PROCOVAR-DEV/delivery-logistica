import 'package:flutter/material.dart';

import '../../../diseno/cajon.dart';
import '../../../diseno/tema.dart';
import '../datos/quien_revisa.dart';

/// ¿REINTENTAR UN APUNTE INTERRUMPIDO? Pregunta antes, en un cajon.
///
/// Un `aplicando` que lleva mas de 10 minutos se quedo a medias: el servidor no
/// sabe si el reparto llego a aplicarlo, y la API no lee `X-Apunte`, asi que no
/// hay otra red que la persona. Reintentar sin comprobar es aplicar DOS VECES.
///
/// **Cerrar sin contestar es NO** (`abrirCajon` devuelve `null`): lo que puede
/// duplicar un cambio no se hace por un descuido.
Future<bool> confirmarReintentoInterrumpido(BuildContext contexto) async {
  final si = await abrirCajon<bool>(
    contexto,
    titulo: TextosDeRevision.reintentarTitulo,
    cuerpo: (contextoCajon) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(TextosDeRevision.reintentarExplica),
        const SizedBox(height: Aire.lg),
        BotonDestructivo(
          texto: TextosDeRevision.reintentarConfirma,
          icono: Icons.restart_alt,
          alPulsar: () => Navigator.of(contextoCajon).pop(true),
        ),
        const SizedBox(height: Aire.sm),
        TextButton(
          onPressed: () => Navigator.of(contextoCajon).pop(false),
          child: const Text(TextosDeRevision.reintentarNo),
        ),
      ],
    ),
  );
  return si ?? false;
}
