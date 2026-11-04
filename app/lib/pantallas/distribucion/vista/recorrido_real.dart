// EL RECORRIDO REAL DE UNA RUTA (tarea 3): por donde fue de verdad el teléfono del distribuidor.
//
// Solo para la oficina. El mapa es el mismo croquis de siempre (`CroquisDeRuta`, con calles si hay red o paquete, y croquis si no)
// con la traza del GPS encima; debajo, cada parada con su hora REAL (la del aparato), su resultado y su cobro, y los tiempos.
//
// Estados vacíos con palabras: cargando, sin conexión, sin puntos todavía. Nunca un cuadro gris ni una rueda para siempre.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../diseno/cajon.dart';
import '../../../diseno/colores.dart';
import '../../pedidos/datos/formato.dart';
import '../../pedidos/vista/kit.dart' show Insignia;
import '../../rutas/datos/mapa_en_vivo.dart';
import '../../rutas/datos/recorrido.dart';
import '../../rutas/vista/croquis_de_ruta.dart';
import '../datos/api_distribucion.dart';
import '../datos/modelos.dart';

final _soloHora = DateFormat('H:mm');
String horaDe(DateTime? d) => d == null ? '—' : _soloHora.format(d);

/// «1 h 5 min», «12 min», «menos de 1 min». `null` = no se sabe: «—».
String cuantoDura(Duration? d) {
  if (d == null) return '—';
  if (d.inMinutes < 1) return 'menos de 1 min';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

String resultadoEnPalabras(String? r) => switch (r) {
  null => 'Sin marcar',
  'entregado' => 'Entregada',
  'devuelto' => 'Devuelta',
  'no_entregada' => 'No entregada',
  _ => '${r[0].toUpperCase()}${r.substring(1).replaceAll('_', ' ')}',
};

String? cobroEnPalabras(String? c) => switch (c) {
  'cobrado' => 'Cobrada',
  'no_cobrado' => 'No cobrada',
  _ => null,
};

abstract final class TextosDelRecorridoReal {
  static const cargando = 'Cargando el recorrido…';
  static const sinPuntos =
      'Esta ruta todavía no tiene recorrido del GPS. Aparece cuando el teléfono del distribuidor empieza la ruta y manda su ubicación '
      '(si no tiene señal, la manda al volver a tener).';
  static const truncado =
      'La traza es larga y el servidor la recortó: lo que se ve es una parte del recorrido, no todo.';
  static const leyenda =
      'Línea morada: por donde fue el GPS. Punto verde: salida. Punto oscuro: último punto.';
  static String noSePudo(String motivo) =>
      'No se pudo leer el recorrido: $motivo';
}

const claveDelRecorridoCargando = ValueKey('recorrido-real-cargando');
const claveDelRecorridoVacio = ValueKey('recorrido-real-vacio');
const claveDelRecorridoConError = ValueKey('recorrido-real-error');
const claveDelResumenDelRecorrido = ValueKey('recorrido-real-resumen');
Key claveDeLaParadaReal(int numero) =>
    ValueKey('recorrido-real-parada-$numero');

Future<void> abrirRecorridoReal(
  BuildContext contexto,
  String rutaId, {
  String? titulo,
  String? subtitulo,
}) => abrirCajon<void>(
  contexto,
  titulo: titulo ?? 'Recorrido real',
  subtitulo: subtitulo,
  cuerpo: (_) => RecorridoRealDeLaRuta(rutaId: rutaId),
);

/// Una línea corta debajo de «Recorrido» en el detalle de la ruta: el botón que abre el recorrido, solo si hay puntos.
/// Mientras se lee no dice nada; si falla, lo dice; sin puntos, lo dice con palabras (no hay botón que no lleve a nada).
class EntradaAlRecorridoReal extends ConsumerWidget {
  const EntradaAlRecorridoReal({
    required this.rutaId,
    required this.titulo,
    super.key,
  });

  final String rutaId;
  final String titulo;

  static const claveDelBoton = ValueKey('recorrido-real-abrir');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    return switch (ref.watch(recorridoRealProvider(rutaId))) {
      AsyncValue(:final error?) => Text(
        TextosDelRecorridoReal.noSePudo(motivoDelFallo(error)),
        style: tema.textTheme.bodySmall?.copyWith(color: Colores.ambar),
      ),
      AsyncData(:final value) when value.hayPuntos => OutlinedButton.icon(
        key: claveDelBoton,
        icon: const Icon(Icons.timeline, size: 18),
        label: const Text('Recorrido real'),
        onPressed: () => abrirRecorridoReal(
          context,
          rutaId,
          titulo: 'Recorrido real · $titulo',
        ),
      ),
      AsyncData() => Text(
        'Todavía no hay recorrido del GPS de esta ruta.',
        key: claveDelRecorridoVacio,
        style: tema.textTheme.bodySmall,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class RecorridoRealDeLaRuta extends ConsumerWidget {
  const RecorridoRealDeLaRuta({required this.rutaId, super.key});

  final String rutaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    return switch (ref.watch(recorridoRealProvider(rutaId))) {
      AsyncValue(:final error?) => Column(
        key: claveDelRecorridoConError,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(TextosDelRecorridoReal.noSePudo(motivoDelFallo(error))),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reintentar'),
            onPressed: () => ref.invalidate(recorridoRealProvider(rutaId)),
          ),
        ],
      ),
      AsyncData(:final value) when !value.hayPuntos => Text(
        TextosDelRecorridoReal.sinPuntos,
        key: claveDelRecorridoVacio,
        style: tema.textTheme.bodyMedium,
      ),
      AsyncData(:final value) => _Contenido(recorrido: value),
      _ => Text(
        TextosDelRecorridoReal.cargando,
        key: claveDelRecorridoCargando,
        style: tema.textTheme.bodyMedium,
      ),
    };
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.recorrido});

  final RecorridoReal recorrido;

  Recorrido _paraElMapa(List<ParadaConTiempos> paradas) => Recorrido(
    soloTraza: true,
    traza: recorrido.traza,
    paradas: [
      for (final p in paradas)
        ParadaDelRecorrido(
          id: p.parada.pedidoId,
          numero: p.numero,
          etiqueta: p.parada.cliente ?? 'Parada ${p.numero}',
          factura: p.parada.factura,
          punto: p.parada.punto,
          entregada: p.parada.resultado == 'entregado',
          esRegreso:
              p.parada.resultado != null && p.parada.resultado != 'entregado',
          detalle: [
            resultadoEnPalabras(p.parada.resultado) +
                (p.parada.resultadoAt == null
                    ? ''
                    : ' a las ${horaDe(p.parada.resultadoAt)}'),
            ?cobroEnPalabras(p.parada.cobroEntrega),
          ].join('\n'),
        ),
    ],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final paradas = recorrido.conTiempos;
    final marcadas = paradas.where((p) => p.parada.resultado != null).length;
    final r = recorrido.ruta;

    Widget dato(String rotulo, String valor) => Padding(
      padding: const EdgeInsets.only(right: 20, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rotulo,
            style: tema.textTheme.bodySmall?.copyWith(
              color: Colores.tintaSuave,
            ),
          ),
          Text(valor, style: tema.textTheme.titleSmall),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (r.distribuidor != null || r.vehiculo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              [?r.distribuidor, ?r.vehiculo].join(' · '),
              style: tema.textTheme.bodyMedium,
            ),
          ),
        Wrap(
          key: claveDelResumenDelRecorrido,
          children: [
            dato('Salió', horaDe(recorrido.salida)),
            dato(
              'Llegó',
              recorrido.llegada == null
                  ? 'Sigue en ruta'
                  : horaDe(recorrido.llegada),
            ),
            dato(
              'Duración total',
              recorrido.llegada == null
                  ? '—'
                  : cuantoDura(recorrido.duracionTotal),
            ),
            dato('Km por el GPS', km(recorrido.kmPorLaTraza)),
            dato('Paradas marcadas', '$marcadas de ${paradas.length}'),
          ],
        ),
        if (recorrido.truncado) ...[
          const SizedBox(height: 4),
          _Aviso(TextosDelRecorridoReal.truncado),
        ],
        const SizedBox(height: 8),
        CroquisDeRuta(
          recorrido: _paraElMapa(paradas),
          fondo: ref.watch(fondoDeCallesProvider),
          porCalles: const SinCallesQueSeguir(),
        ),
        const SizedBox(height: 6),
        Text(TextosDelRecorridoReal.leyenda, style: tema.textTheme.bodySmall),
        const SizedBox(height: 16),
        Text(
          'Paradas',
          style: tema.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (paradas.isEmpty)
          Text('Esta ruta no tiene paradas.', style: tema.textTheme.bodyMedium)
        else
          for (final p in paradas) _FilaDeParada(p),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colores.ambarFondo,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(texto, style: TextStyle(fontSize: 12, color: Colores.tinta)),
    ),
  );
}

class _FilaDeParada extends StatelessWidget {
  const _FilaDeParada(this.p);

  final ParadaConTiempos p;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final x = p.parada;
    final cobro = cobroEnPalabras(x.cobroEntrega);
    final tiempos = [
      if (p.desdeLaAnterior != null)
        'Desde la anterior: ${cuantoDura(p.desdeLaAnterior)}',
      if (p.enLaParada != null) 'En la parada: ${cuantoDura(p.enLaParada)}',
    ];
    return Container(
      key: claveDeLaParadaReal(p.numero),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colores.linea),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${p.numero}. ${x.cliente ?? 'Parada'}',
            style: tema.textTheme.titleSmall,
          ),
          if (x.factura != null)
            Text(x.factura!, style: tema.textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Insignia(
                '${resultadoEnPalabras(x.resultado)}${x.resultadoAt == null ? '' : ' · ${horaDe(x.resultadoAt)}'}',
                color: switch (x.resultado) {
                  'entregado' => ColoresDelMapa.salida,
                  null => Colores.tintaSuave,
                  _ => ColoresDelMapa.regreso,
                },
              ),
              if (cobro != null)
                Insignia(
                  cobro,
                  color: x.cobroEntrega == 'cobrado'
                      ? ColoresDelMapa.salida
                      : ColoresDelMapa.puntoManual,
                ),
            ],
          ),
          if (tiempos.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(tiempos.join(' · '), style: tema.textTheme.bodySmall),
          ],
          if (x.nota != null) ...[
            const SizedBox(height: 4),
            Text('Nota: ${x.nota}', style: tema.textTheme.bodySmall),
          ],
          if (p.marcaLejana) ...[
            const SizedBox(height: 6),
            _Aviso(
              'Se marcó a ${p.metrosDeLaMarca!.round()} m del punto de la parada: puede que se marcara sin estar allí.',
            ),
          ],
        ],
      ),
    );
  }
}
