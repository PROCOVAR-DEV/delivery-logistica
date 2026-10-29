import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../diseno/cargando.dart';
import '../../../diseno/estado_vacio.dart';
import '../../../nucleo/red/fallos.dart';
import '../../sincronizacion/datos/panel_sincronizacion.dart';
import '../../sincronizacion/vista/fila_de_rechazo.dart';
import '../estado/proveedores_actividad.dart';

/// «VER ACTIVIDAD» DE ACCESOS — 29/10/2026.
///
/// La pantalla «Dispositivos» de Accesos enseña QUÉ es cada aparato; lo que HIZO (cuándo bajó y subió, cuántos apuntes le quedan, qué se le
/// rechazó y por qué) lo guarda el sincronizador y se ve aquí. Se llega con `/dispositivos?aparato=<X-Aparato-Id>`, el id que el aparato
/// manda en cada petición (`nucleo/red/instalacion.dart`) y el sincronizador anota en `aparatos.instalacion_id`.
///
/// **Se puede abrir en la web**: no es la cola de nadie, es una lectura de oficina (la misma regla que la bandeja de revisión). No guarda
/// nada. Si el aparato aún no ha hablado con el sincronizador desde la versión que manda su id, se dice así, sin inventar.
class PantallaActividadDeAparato extends ConsumerWidget {
  const PantallaActividadDeAparato({required this.instalacion, super.key});

  static const ruta = '/dispositivos';

  /// El `X-Aparato-Id` de Accesos, tal como viene en la dirección.
  final String? instalacion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buscado = instalacion?.trim().toLowerCase();
    if (buscado == null || buscado.isEmpty) {
      return const EstadoVacio(
        'Falta el aparato. Esta pantalla se abre desde «Ver actividad» en '
        'Dispositivos de Accesos.',
      );
    }
    final lectura = ref.watch(actividadDeAparatosProvider);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Actividad del aparato',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          if (lectura.error case final fallo?)
            _Fallo(
              fallo: fallo,
              alReintentar: () => ref.invalidate(actividadDeAparatosProvider),
            )
          else if (lectura.value case final estado?)
            _Detalle(estado: estado, buscado: buscado)
          else
            const Cargando('Leyendo la actividad del aparato…'),
        ],
      ),
    );
  }
}

final _fecha = DateFormat('dd/MM/yyyy HH:mm');
String _cuando(DateTime? f) => f == null ? '—' : _fecha.format(f);

class _Detalle extends StatelessWidget {
  const _Detalle({required this.estado, required this.buscado});

  final EstadoDelSincronizador estado;
  final String buscado;

  @override
  Widget build(BuildContext context) {
    AparatoDelPanel? aparato;
    for (final a in estado.aparatos) {
      if (a.instalacion?.toLowerCase() == buscado) {
        aparato = a;
        break;
      }
    }
    if (aparato == null) {
      return const AvisoAmbar(
        'El sincronizador todavía no conoce este aparato. Se une la próxima vez '
        'que baje o suba con la versión 1.0.48 o posterior, o no es de tu '
        'sucursal.',
        icono: Icons.info_outline,
      );
    }
    final rechazos = [
      for (final r in estado.bandeja)
        if (r.aparato == aparato.aparato) r,
    ];
    final texto = Theme.of(context).textTheme;
    final sinSubir = aparato.nuncaSubio
        ? 'Nunca ha subido'
        : '${aparato.horasSinSubir ?? 0} h';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(aparato.comoSeLlama, style: texto.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Persona ${AparatoDelPanel.corto(aparato.persona)} · sucursal '
          '${AparatoDelPanel.corto(aparato.sucursal)}',
        ),
        const SizedBox(height: 16),
        _Dato('Visto por última vez', _cuando(aparato.visto)),
        _Dato('Última bajada', _cuando(aparato.bajada)),
        _Dato('Última subida', _cuando(aparato.subida)),
        _Dato('Sin subir hace', sinSubir),
        _Dato('Pendientes de subir', '${aparato.pendientes}'),
        _Dato('Rechazados', '${aparato.rechazados}'),
        const SizedBox(height: 16),
        Text('Rechazos sin atender', style: texto.titleMedium),
        const SizedBox(height: 8),
        if (rechazos.isEmpty)
          const Text('Ninguno.')
        else
          for (final r in rechazos)
            FilaDeRechazo(
              motivo: r.motivo,
              quien: aparato.comoSeLlama,
              horas: _cuando(r.rechazadoEl),
              peticion: '${r.metodo} ${r.ruta}',
            ),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.rotulo, this.valor);

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(width: 200, child: Text(rotulo)),
        Expanded(
          child: Text(
            valor,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _Fallo extends StatelessWidget {
  const _Fallo({required this.fallo, required this.alReintentar});

  final Object fallo;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    final texto = switch (fallo) {
      FalloDeRed() => 'No hay conexión con el servidor. Vuelve a intentarlo.',
      final FalloApi f => f.mensaje,
      _ => 'No se pudo leer la actividad. $fallo',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AvisoAmbar(texto, icono: Icons.cloud_off),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: alReintentar,
            child: const Text('Reintentar'),
          ),
        ),
      ],
    );
  }
}
