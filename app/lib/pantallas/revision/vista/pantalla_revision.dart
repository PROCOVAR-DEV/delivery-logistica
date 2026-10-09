import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/cargando.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/estado_vacio.dart';
import '../../../diseno/numeros.dart';
import '../../../diseno/tarjeta.dart';
import '../../../diseno/tema.dart';
import '../../../navegacion/estado_navegacion.dart';
import '../../../navegacion/menu_de_cuenta.dart' show sesionParaElMenuProvider;
import '../../../nucleo/identidad/sesion.dart';
import '../../../nucleo/red/fallos.dart';
import '../datos/bandeja.dart';
import '../datos/quien_revisa.dart';
import '../estado/proveedores_revision.dart';
import 'tarjeta_de_entrega.dart';

/// REVISION — `/revision`. La bandeja de quien decide sobre lo que entrego
/// alguien que perdio el permiso de Reparto (`docs/bandeja-de-revision.md`).
///
/// **Es un buzon de oficina, no una cola.** No guarda nada en el aparato ni en el
/// navegador: habla con `sync` y lo que ve es lo que el servidor sabe ahora. Por
/// eso vale en la web (Jose, 08/10/2026) con el mismo dibujo que en la APK y el
/// escritorio.
///
/// **La ruta NO empieza por `/sync` ni por `/api`** (`CLAUDE.md` §3-quater):
/// Traefik se queda con esos dos prefijos antes que la aplicacion, y recargar
/// aqui llegaria al sincronizador con un `401` que no tiene nada que ver. Lo
/// vigila `test/navegacion/contrato_registro_test.dart`.
///
/// Solo ve la bandeja quien puede revisar ([puedeRevisar]). Los demas, aunque
/// lleguen por la direccion, ven por que no y **no se pide nada al servidor**.
///
/// SIN `Scaffold` ni `AppBar` propios: los pone el armazon.
class PantallaRevision extends ConsumerWidget {
  const PantallaRevision({super.key});

  static const ruta = '/revision';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionParaElMenuProvider);
    // Mientras se lee quien eres no se enseña ni se pide nada: el lado seguro es
    // no abrir la bandeja a quien no se sabe quien es.
    if (sesion.isLoading) {
      return const _Marco(child: Cargando(TextosDeRevision.cargando));
    }
    final quien = sesion.value;
    if (!puedeRevisar(quien)) {
      return const _Marco(
        child: Tarjeta(
          titulo: TextosDeRevision.titulo,
          child: EstadoVacio(
            TextosDeRevision.noRevisas,
            icono: Icons.lock_outline,
          ),
        ),
      );
    }
    return _Bandeja(quien: quien!);
  }
}

class _Marco extends StatelessWidget {
  const _Marco({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(padding: const EdgeInsets.all(Aire.xl), children: [child]),
  );
}

class _Bandeja extends ConsumerWidget {
  const _Bandeja({required this.quien});

  final Sesion quien;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bandeja = ref.watch(bandejaProvider);
    final tema = Theme.of(context);
    return _Marco(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TextosDeRevision.titulo,
                      style: tema.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      TextosDeRevision.explicacion,
                      style: tema.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Aire.md),
              OutlinedButton.icon(
                onPressed: () {
                  ref.invalidate(bandejaProvider);
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Actualizar'),
              ),
            ],
          ),
          const SizedBox(height: Aire.md),
          // El fallo se mira ANTES que el valor: una recarga que no llega no
          // puede dejar la lista anterior con pinta de recien traida, y un error
          // NO es una bandeja vacia (dos cosas distintas, §3).
          if (bandeja.error case final fallo?)
            _Fallo(fallo: fallo)
          else if (bandeja.value case final datos?)
            _Lista(bandeja: datos, quien: quien)
          else
            const Cargando(TextosDeRevision.cargando),
        ],
      ),
    );
  }
}

class _Fallo extends StatelessWidget {
  const _Fallo({required this.fallo});

  final Object fallo;

  @override
  Widget build(BuildContext context) {
    final texto = switch (fallo) {
      FalloDeRed() => TextosDeRevision.sinConexion,
      // Un 403 se dice con SU texto, tal cual.
      final FalloApi f => f.mensaje,
      _ => 'No se pudo leer la bandeja. $fallo',
    };
    return AvisoAmbar(texto, icono: Icons.cloud_off);
  }
}

class _Lista extends ConsumerWidget {
  const _Lista({required this.bandeja, required this.quien});

  final BandejaDelRevisor bandeja;
  final Sesion quien;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (bandeja.entregas.isEmpty) {
      return const Tarjeta(
        child: EstadoVacio(TextosDeRevision.vacia, icono: Icons.inbox_outlined),
      );
    }

    // Por sucursal, en el orden en que el servidor las trajo.
    final sucursales = ref.watch(sucursalesProvider).value;
    // El servidor NO manda el nombre de la sucursal: sale de la copia de
    // sucursales que ya tiene la app o, si aun no ha bajado, del principio del
    // uuid.
    String nombreDe(EntregaEnRevision e) =>
        sucursales
            ?.where((s) => s.id == e.sucursal)
            .map((s) => s.name)
            .firstOrNull ??
        (e.sucursal.length <= 8 ? e.sucursal : e.sucursal.substring(0, 8));

    final porSucursal = <String, List<EntregaEnRevision>>{};
    for (final e in bandeja.entregas) {
      porSucursal.putIfAbsent(e.sucursal, () => []).add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Un tope alcanzado se DICE (CLAUDE.md §3).
        if (bandeja.truncado) ...[
          const AvisoAmbar(TextosDeRevision.truncada),
          const SizedBox(height: Aire.md),
        ],
        SizedBox(
          width: Anchos.articulosYFactura,
          child: TarjetaDeCifra(
            etiqueta: 'Esperan una decisión',
            valor: Numeros.entero(bandeja.porDecidir),
            subtexto: 'Apuntes en revisión o rechazados al aplicar',
            color: bandeja.porDecidir > 0 ? Colores.rojo : Colores.verde,
            icono: Icons.fact_check_outlined,
          ),
        ),
        for (final grupo in porSucursal.values) ...[
          const SizedBox(height: Aire.lg),
          Text(
            nombreDe(grupo.first),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final e in grupo) ...[
            const SizedBox(height: Aire.sm),
            TarjetaDeEntrega(entrega: e, quien: quien),
          ],
        ],
      ],
    );
  }
}
