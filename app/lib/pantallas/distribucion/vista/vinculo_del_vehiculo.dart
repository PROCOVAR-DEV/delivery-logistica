// EL VEHÍCULO Y SU TELÉFONO: «Vinculado al teléfono X desde <fecha>», «Desvincular» y la historia de vínculos.
//
// Regla de Jose: el enlace de una ruta lleva el vehículo, y el teléfono que lo abre queda vinculado a ESE vehículo. Para poner otro
// teléfono, la oficina DESVINCULA desde aquí: el teléfono se vacía (pierde el acceso y su APK se queda sin nada), las rutas
// planificadas o en curso que tenía quedan libres y SU ENLACE SE REVOCA (hay que mandar uno nuevo), y el servidor conserva TODO el
// histórico (rutas completadas, GPS, vínculos) por el id del dispositivo. Sale en la tarjeta del vehículo y, completo, en su
// historial. Es de la oficina: el cerrojo es el del servidor.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/cajon.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../../pedidos/datos/formato.dart';
import '../../pedidos/vista/kit.dart' show Insignia;
import '../datos/api_distribucion.dart';
import '../datos/modelos.dart';
import 'enviar_a_distribuidor.dart' show mensajeConEnlace;
import '../../rutas/datos/abrir_y_compartir.dart';
import '../../rutas/datos/enlace_de_la_ruta.dart' show enlaceDeWhatsApp;

abstract final class TextosDelVinculo {
  static String vinculado(String? telefono, DateTime? desde) =>
      'Vinculado al teléfono ${telefono ?? 'sin nombre'}${desde == null ? '' : ' desde ${fechaYHora(desde)}'}';
  static const sinTelefono = 'Sin teléfono vinculado.';
  static const desvincular = 'Desvincular';
  static const explicacion =
      'El teléfono se vaciará y las rutas abiertas quedarán libres; lo que no haya enviado se perderá. El servidor conserva todo el histórico.';
  static const desvinculado = 'Teléfono desvinculado.';
  static const sinVinculos =
      'Este vehículo todavía no ha tenido ningún teléfono vinculado.';
}

const claveDelVinculoActual = ValueKey('vinculo-actual');
const claveDeDesvincular = ValueKey('vinculo-desvincular');
const claveDelMotivo = ValueKey('vinculo-motivo');
const claveDeConfirmarDesvinculo = ValueKey('vinculo-confirmar');
const claveDelAvisoDelVinculo = ValueKey('vinculo-aviso');
const claveDeLasRutasSueltas = ValueKey('vinculo-rutas-sueltas');
Key claveDeEnviarEnlaceNuevo(String rutaId) =>
    ValueKey('vinculo-enlace-nuevo-$rutaId');
Key claveDelVinculoDeLaHistoria(String id) => ValueKey('vinculo-historia-$id');

/// DESVINCULAR, con su cajón de confirmación y motivo opcional; lo comparten la tarjeta del vehículo y la pestaña «Teléfonos».
///
/// [alConfirmar] se llama justo antes de mandar. Tras el «sí» refresca lo que depende del vínculo y, si quedaron rutas sueltas,
/// abre el cajón con «Enviar enlace nuevo». Devuelve `false` si se dijo que no; el fallo del servidor (el 409 de «no estaba
/// vinculado», por ejemplo) se LANZA para que quien llama lo enseñe, y las listas se refrescan igual.
Future<bool> desvincularConConfirmacion(
  BuildContext context,
  WidgetRef ref, {
  required String vehiculoId,
  required String nombre,
  String? telefono,
  VoidCallback? alConfirmar,
}) async {
  final motivo = await abrirCajon<String>(
    context,
    titulo: 'Desvincular el teléfono',
    subtitulo: '$nombre${telefono == null ? '' : ' · $telefono'}',
    cuerpo: (_) => const _ConfirmarDesvinculo(),
  );
  if (motivo == null || !context.mounted) return false;
  alConfirmar?.call();
  void refrescar() {
    ref.invalidate(vehiculosEnVivoProvider);
    ref.invalidate(vinculosDelVehiculoProvider(vehiculoId));
    ref.invalidate(revisionesProvider);
    ref.invalidate(telefonosProvider);
  }

  final List<String> sueltas;
  try {
    sueltas = await ref
        .read(apiDistribucionProvider)
        .desvincular(vehiculoId, motivo: motivo);
  } on Object {
    if (context.mounted) refrescar();
    rethrow;
  }
  if (!context.mounted) return true;
  refrescar();
  if (sueltas.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text(TextosDelVinculo.desvinculado)),
    );
  } else {
    await abrirCajon<void>(
      context,
      titulo: 'Rutas sin teléfono',
      subtitulo: nombre,
      cuerpo: (_) => RutasSueltas(rutaIds: sueltas),
    );
  }
  return true;
}

class VinculoDelVehiculo extends ConsumerStatefulWidget {
  const VinculoDelVehiculo({
    required this.vehiculoId,
    required this.nombre,
    this.compacto = false,
    super.key,
  });

  final String vehiculoId;
  final String nombre;

  /// En la tarjeta: no dice nada si no hay teléfono ni si no se pudo comprobar (30 tarjetas con el mismo aviso serían ruido).
  final bool compacto;

  @override
  ConsumerState<VinculoDelVehiculo> createState() => _VinculoDelVehiculoState();
}

class _VinculoDelVehiculoState extends ConsumerState<VinculoDelVehiculo> {
  bool _ocupado = false;
  String? _fallo;

  Future<void> _desvincular(String? telefono) async {
    try {
      await desvincularConConfirmacion(
        context,
        ref,
        vehiculoId: widget.vehiculoId,
        nombre: widget.nombre,
        telefono: telefono,
        alConfirmar: () => setState(() {
          _ocupado = true;
          _fallo = null;
        }),
      );
    } on Object catch (e) {
      if (mounted) setState(() => _fallo = motivoDelFallo(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final vehiculos = ref.watch(vehiculosEnVivoProvider);
    final v = vehiculos.value?[widget.vehiculoId];
    if (vehiculos.hasError && !widget.compacto) {
      return Text(
        'No se pudo comprobar el teléfono del vehículo: ${motivoDelFallo(vehiculos.error!)}',
        style: tema.textTheme.bodySmall?.copyWith(color: Colores.ambar),
      );
    }
    if (v == null) return const SizedBox.shrink();
    if (v.dispositivoId == null) {
      return widget.compacto
          ? const SizedBox.shrink()
          : Text(
              TextosDelVinculo.sinTelefono,
              key: claveDelVinculoActual,
              style: tema.textTheme.bodyMedium,
            );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              const Icon(
                Icons.smartphone,
                size: 16,
                color: ColoresDelMapa.recorrido,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  TextosDelVinculo.vinculado(
                    v.dispositivoNombre,
                    v.vinculadoAt,
                  ),
                  key: claveDelVinculoActual,
                  style: tema.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          key: claveDeDesvincular,
          icon: const Icon(Icons.link_off, size: 18),
          label: const Text(TextosDelVinculo.desvincular),
          onPressed: _ocupado ? null : () => _desvincular(v.dispositivoNombre),
        ),
        if (_fallo != null)
          DecoratedBox(
            key: claveDelAvisoDelVinculo,
            decoration: BoxDecoration(
              color: Colores.ambarFondo,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                _fallo!,
                style: TextStyle(fontSize: 12, color: Colores.tinta),
              ),
            ),
          ),
      ],
    );
  }
}

/// El cajón de confirmación: explica qué pasa, deja un motivo (opcional) y pide el «sí».
class _ConfirmarDesvinculo extends StatefulWidget {
  const _ConfirmarDesvinculo();

  @override
  State<_ConfirmarDesvinculo> createState() => _ConfirmarDesvinculoState();
}

class _ConfirmarDesvinculoState extends State<_ConfirmarDesvinculo> {
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(TextosDelVinculo.explicacion),
      const SizedBox(height: 16),
      TextField(
        key: claveDelMotivo,
        controller: _motivo,
        maxLength: 300,
        decoration: const InputDecoration(
          labelText: 'Motivo (opcional)',
          hintText: 'Se rompió el teléfono, cambia de distribuidor…',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      BotonDestructivo(
        key: claveDeConfirmarDesvinculo,
        texto: 'Sí, desvincular el teléfono',
        icono: Icons.link_off,
        alPulsar: () => Navigator.of(context).pop(_motivo.text.trim()),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('No, dejarlo vinculado'),
      ),
    ],
  );
}

/// Las rutas que quedaron libres al desvincular, cada una con «Enviar enlace nuevo» (su enlace anterior ya no sirve).
class RutasSueltas extends ConsumerWidget {
  const RutasSueltas({required this.rutaIds, super.key});

  final List<String> rutaIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conocidas = {
      for (final r
          in ref.watch(revisionesProvider).value ?? const <RevisionDeRuta>[])
        r.id: r,
    };
    return Column(
      key: claveDeLasRutasSueltas,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'El teléfono ya no tiene estas rutas y sus enlaces dejaron de servir. Manda un enlace nuevo a quien las vaya a llevar.',
        ),
        const SizedBox(height: 12),
        for (final id in rutaIds) _FilaSuelta(rutaId: id, ruta: conocidas[id]),
      ],
    );
  }
}

class _FilaSuelta extends ConsumerStatefulWidget {
  const _FilaSuelta({required this.rutaId, required this.ruta});

  final String rutaId;
  final RevisionDeRuta? ruta;

  @override
  ConsumerState<_FilaSuelta> createState() => _FilaSueltaState();
}

class _FilaSueltaState extends ConsumerState<_FilaSuelta> {
  bool _ocupado = false;
  String? _fallo;

  Future<void> _enviar() async {
    final r = widget.ruta;
    setState(() {
      _ocupado = true;
      _fallo = null;
    });
    try {
      final mensaje = await mensajeConEnlace(
        ref.read(apiDistribucionProvider),
        rutaId: widget.rutaId,
        codigo: r?.codigo ?? widget.rutaId,
        nombre: r?.nombre,
        fecha: fechaCorta(r?.fecha),
        paradas: r?.paradas ?? 0,
        // Fresco siempre: el anterior está revocado.
        renovar: true,
      );
      if (!mounted) return;
      if (!await ref
              .read(abrirYCompartirProvider)
              .abrir(enlaceDeWhatsApp(mensaje)) &&
          mounted) {
        setState(
          () => _fallo =
              'No se pudo abrir WhatsApp. Comprueba que está instalado.',
        );
      }
    } on Object catch (e) {
      if (mounted) setState(() => _fallo = motivoDelFallo(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.ruta;
    final tema = Theme.of(context);
    final titulo = r == null
        ? 'Ruta ${widget.rutaId}'
        : [?r.codigo, ?r.nombre].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: tema.textTheme.titleSmall),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              key: claveDeEnviarEnlaceNuevo(widget.rutaId),
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('Enviar enlace nuevo'),
              onPressed: _ocupado ? null : _enviar,
            ),
            if (_fallo != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _fallo!,
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: Colores.ambar,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// La historia de teléfonos que ha llevado el vehículo.
class HistorialDeVinculos extends ConsumerWidget {
  const HistorialDeVinculos({required this.vehiculoId, super.key});

  final String vehiculoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(vinculosDelVehiculoProvider(vehiculoId))) {
        AsyncValue(:final error?) => Text(
          'No se pudo leer la historia de teléfonos: ${motivoDelFallo(error)}',
        ),
        AsyncData(:final value) when value.isEmpty => const Text(
          TextosDelVinculo.sinVinculos,
        ),
        AsyncData(:final value) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final v in value) _FilaDeVinculo(v)],
        ),
        _ => const Text('Cargando los teléfonos…'),
      };
}

class _FilaDeVinculo extends StatelessWidget {
  const _FilaDeVinculo(this.v);

  final VinculoDeVehiculo v;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      key: claveDelVinculoDeLaHistoria(v.id),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    v.dispositivo ?? 'Teléfono sin nombre',
                    style: tema.textTheme.titleSmall,
                  ),
                ),
                Insignia(
                  v.vigente ? 'Vinculado ahora' : 'Desvinculado',
                  color: v.vigente ? ColoresDelMapa.salida : Colores.tintaSuave,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Desde ${fechaYHora(v.desde)}${v.hasta == null ? '' : ' hasta ${fechaYHora(v.hasta)}'}',
              style: tema.textTheme.bodySmall,
            ),
            if (v.vinculadoPor != null)
              Text(
                'Lo vinculó ${v.vinculadoPor}',
                style: tema.textTheme.bodySmall,
              ),
            if (v.desvinculadoPor != null)
              Text(
                'Lo desvinculó ${v.desvinculadoPor}',
                style: tema.textTheme.bodySmall,
              ),
            if (v.motivo != null)
              Text('Motivo: ${v.motivo}', style: tema.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
