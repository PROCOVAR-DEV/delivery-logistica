// EL AVISO DE LA PRIMERA VEZ: «Reparto registra tu ubicacion mientras haces una
// ruta, para un mejor trabajo» con «Aceptar». Se guarda QUIEN y CUANDO en las
// preferencias del aparato (la base de cada persona). Sin aceptar, no se activa
// el GPS, pero SE PUEDE TRABAJAR.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diseno/colores.dart';
import '../diseno/tema.dart';
import '../nucleo/proveedores.dart';

const claveDelAvisoDeUbicacion = 'avisoDeUbicacion';

const textoDelAvisoDeUbicacion =
    'Reparto registra tu ubicación mientras haces una ruta, para un mejor trabajo.';

class AceptacionDeUbicacion {
  const AceptacionDeUbicacion(this.quien, this.cuando);

  final String quien;
  final DateTime cuando;

  String aJson() =>
      jsonEncode({'quien': quien, 'cuando': cuando.toUtc().toIso8601String()});

  static AceptacionDeUbicacion? deJson(String? texto) {
    if (texto == null) return null;
    try {
      final m = jsonDecode(texto) as Map<String, Object?>;
      return AceptacionDeUbicacion(
        m['quien']! as String,
        DateTime.parse(m['cuando']! as String),
      );
    } on Object {
      return null;
    }
  }
}

/// Lo aceptado en ESTE aparato por la persona de la base abierta. `null` = aun no.
class AceptacionDeLaUbicacion extends AsyncNotifier<AceptacionDeUbicacion?> {
  @override
  Future<AceptacionDeUbicacion?> build() async {
    final base = ref.watch(baseProvider);
    return AceptacionDeUbicacion.deJson(
      await base.preferencia(claveDelAvisoDeUbicacion),
    );
  }

  Future<void> aceptar(String quien) async {
    final a = AceptacionDeUbicacion(quien, ref.read(relojProvider)());
    await ref
        .read(baseProvider)
        .anotarPreferencia(claveDelAvisoDeUbicacion, a.aJson());
    state = AsyncData(a);
  }
}

final aceptacionDeUbicacionProvider =
    AsyncNotifierProvider<AceptacionDeLaUbicacion, AceptacionDeUbicacion?>(
      AceptacionDeLaUbicacion.new,
    );

/// La pantalla. [alAceptar] guarda; [alAhoraNo] la quita solo por esta vez (se
/// vuelve a preguntar la proxima: sin aceptar no hay GPS, pero se trabaja).
class AvisoDeUbicacion extends StatelessWidget {
  const AvisoDeUbicacion({
    required this.alAceptar,
    required this.alAhoraNo,
    super.key,
  });

  final VoidCallback alAceptar;
  final VoidCallback alAhoraNo;

  @override
  Widget build(BuildContext context) => Material(
    color: Colores.blanco,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.location_on_outlined, size: 56, color: Colores.primario),
            const SizedBox(height: 16),
            const Text(
              textoDelAvisoDeUbicacion,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            BotonPrincipal(
              key: const ValueKey('aviso-ubicacion-aceptar'),
              icono: Icons.check,
              texto: 'Aceptar',
              alPulsar: alAceptar,
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('aviso-ubicacion-ahora-no'),
              onPressed: alAhoraNo,
              child: const Text(
                'Ahora no (sin ubicación podrás trabajar igual)',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
