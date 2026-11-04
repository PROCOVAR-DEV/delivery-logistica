// LA RUTA GUIADA: de una ruta EN CURSO enseña SIEMPRE la parada de ahora (la
// primera sin resultado, por el orden de la ruta) con lo que hay que hacer en ella:
// factura, cliente, telefono, direccion, los productos con su cantidad en
// empaques, y el cronometro de la parada y de la ruta. Al marcar, pasa sola a la
// siguiente; al marcar la ultima, la ruta se completa sola.
//
// Sin importes (decision A): lo unico de dinero es el «cobrado: si/no» de la parada.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diseno/tema.dart';
import '../nucleo/base/base.dart';
import '../nucleo/proveedores.dart';
import '../pantallas/pedidos/datos/formato.dart';
import '../pantallas/pedidos/vista/kit.dart';
import '../pantallas/rutas/datos/abrir_y_compartir.dart';
import '../pantallas/pedidos/datos/repositorio_pedidos.dart'
    show RenglonConPeso;
import '../pantallas/rutas/datos/acciones_rutas.dart' show RechazoLocal;
import '../pantallas/rutas/datos/repositorio_rutas.dart' show PestanaRutas;
import '../pantallas/rutas/estado/proveedores_rutas.dart';
import 'enlaces.dart';
import 'guia_de_ruta.dart';
import 'parada_actual.dart';
import 'proveedores_distribuidor.dart';

class RutaGuiada extends ConsumerWidget {
  const RutaGuiada({required this.rutaId, super.key});

  final String rutaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ruta = ref.watch(rutaConTodoProvider(rutaId)).value?.ruta;
    final paradas = ref.watch(paradasDeRutaProvider(rutaId)).value;
    if (ruta == null || paradas == null) return const SizedBox.shrink();

    final permiso = ref.watch(permisoDeUbicacionProvider);
    final aviso = permiso?.aviso;
    final siguiente = siguienteParada(paradas);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (aviso != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              aviso,
              key: const ValueKey('guia-aviso-ubicacion'),
              style: TextStyle(color: Colores.ambar),
            ),
          ),
        _Cronometros(
          salida: ruta.startedAt,
          inicioDeLaParada: inicioDeLaParada(paradas, ruta.startedAt),
          conParada: siguiente != null,
        ),
        const SizedBox(height: 8),
        if (paradas.isEmpty)
          const Text('Esta ruta no tiene paradas.')
        else if (siguiente == null)
          _TodoMarcado(rutaId: rutaId)
        else
          _ParadaDeAhora(
            // Otra parada = formulario nuevo (nota y cobrado vuelven a vacio).
            key: ValueKey('parada-de-ahora-${siguiente.id}'),
            rutaId: rutaId,
            parada: siguiente,
            numero: paradasHechas(paradas) + 1,
            total: paradas.length,
          ),
        // No se cancela una ruta con entregas hechas (el servidor tampoco deja).
        if (!paradas.any((p) => p.resultado == ResultadoParada.entregado)) ...[
          const SizedBox(height: 8),
          _CancelarLaRuta(rutaId: rutaId),
        ],
      ],
    );
  }
}

class _CancelarLaRuta extends ConsumerWidget {
  const _CancelarLaRuta({required this.rutaId});

  final String rutaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Align(
    alignment: Alignment.centerRight,
    child: TextButton.icon(
      key: const ValueKey('guia-cancelar-ruta'),
      onPressed: () async {
        final mensajero = ScaffoldMessenger.maybeOf(context);
        final motivo = await abrirCajon<String>(
          context,
          (_) => const _PreguntaDelMotivo(),
        );
        if (motivo == null) return;
        try {
          await ref.read(guiaDeRutaProvider).cancelar(rutaId, motivo: motivo);
          ref.read(rutaElegidaProvider.notifier).elegir(null);
          ref
              .read(pestanaRutasProvider.notifier)
              .elegir(PestanaRutas.historial);
        } on RechazoLocal catch (no) {
          mensajero?.showSnackBar(SnackBar(content: Text(no.mensaje)));
        }
      },
      icon: const Icon(Icons.cancel_outlined),
      label: const Text('Cancelar la ruta'),
    ),
  );
}

/// Pide el motivo y la confirmacion de cancelar, en un CAJON (regla de la casa: nada
/// de dialogos). Devuelve el motivo, o `null` si se arrepiente.
class _PreguntaDelMotivo extends StatefulWidget {
  const _PreguntaDelMotivo();

  @override
  State<_PreguntaDelMotivo> createState() => _PreguntaDelMotivoState();
}

class _PreguntaDelMotivoState extends State<_PreguntaDelMotivo> {
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Cajon(
    titulo: '¿Cancelar la ruta entera?',
    ancho: AnchoCajon.md,
    cuerpo: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Ninguna parada se da por entregada. Cuéntale a logística por qué.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('guia-motivo-de-cancelar'),
            controller: _motivo,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Motivo (obligatorio)',
            ),
          ),
          const SizedBox(height: 16),
          BotonDestructivo(
            key: const ValueKey('guia-confirmar-cancelar'),
            icono: Icons.cancel_outlined,
            texto: 'Sí, cancelar la ruta',
            alPulsar: _motivo.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(_motivo.text.trim()),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('No, seguir con la ruta'),
          ),
        ],
      ),
    ),
  );
}

class _Cronometros extends ConsumerStatefulWidget {
  const _Cronometros({
    required this.salida,
    required this.inicioDeLaParada,
    required this.conParada,
  });

  final DateTime? salida;
  final DateTime? inicioDeLaParada;
  final bool conParada;

  @override
  ConsumerState<_Cronometros> createState() => _CronometrosState();
}

class _CronometrosState extends ConsumerState<_Cronometros> {
  Timer? _tic;

  @override
  void initState() {
    super.initState();
    _tic = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tic?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ahora = ref.read(relojProvider)();
    String desde(DateTime? t) =>
        t == null ? '--:--' : cronometro(ahora.difference(t));
    return Row(
      children: [
        if (widget.conParada)
          Expanded(
            child: Text(
              'Parada: ${desde(widget.inicioDeLaParada)}',
              key: const ValueKey('cronometro-parada'),
              style: Tipos.mono(tamano: 15, peso: FontWeight.w700),
            ),
          ),
        Expanded(
          child: Text(
            'Ruta: ${desde(widget.salida)}',
            key: const ValueKey('cronometro-ruta'),
            textAlign: widget.conParada ? TextAlign.end : TextAlign.start,
            style: Tipos.mono(tamano: 15, peso: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _TodoMarcado extends ConsumerWidget {
  const _TodoMarcado({required this.rutaId});

  final String rutaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Todas las paradas tienen su resultado.'),
      const SizedBox(height: 8),
      // Solo se ve si la ruta no llego a completarse sola (un fallo al hacerlo).
      BotonPrincipal(
        key: const ValueKey('guia-completar'),
        icono: Icons.check_circle_outline,
        texto: 'Completar la ruta',
        alPulsar: () async {
          final mensajero = ScaffoldMessenger.maybeOf(context);
          try {
            await ref.read(guiaDeRutaProvider).completarSiToca(rutaId);
          } on RechazoLocal catch (no) {
            mensajero?.showSnackBar(SnackBar(content: Text(no.mensaje)));
          }
        },
      ),
    ],
  );
}

class _ParadaDeAhora extends ConsumerStatefulWidget {
  const _ParadaDeAhora({
    required this.rutaId,
    required this.parada,
    required this.numero,
    required this.total,
    super.key,
  });

  final String rutaId;
  final Pedido parada;
  final int numero;
  final int total;

  @override
  ConsumerState<_ParadaDeAhora> createState() => _ParadaDeAhoraState();
}

class _ParadaDeAhoraState extends ConsumerState<_ParadaDeAhora> {
  SalidaDeParada? _salida;
  bool _cobrado = false;
  bool _guardando = false;
  final _nota = TextEditingController();

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  Future<void> _abrir(Uri? enlace, String sinDato) async {
    final mensajero = ScaffoldMessenger.maybeOf(context);
    if (enlace == null) {
      mensajero?.showSnackBar(SnackBar(content: Text(sinDato)));
      return;
    }
    final ok = await ref.read(abrirYCompartirProvider).abrir(enlace);
    if (!ok) {
      mensajero?.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir en este telefono.')),
      );
    }
  }

  bool get _puedeGuardar {
    final s = _salida;
    if (s == null || _guardando) return false;
    return !s.exigeMotivo || _nota.text.trim().isNotEmpty;
  }

  Future<void> _guardar() async {
    final salida = _salida;
    if (salida == null || _guardando) return;
    final mensajero = ScaffoldMessenger.maybeOf(context);
    setState(() => _guardando = true);
    try {
      final completada = await ref
          .read(guiaDeRutaProvider)
          .marcar(
            widget.rutaId,
            widget.parada.id,
            salida,
            nota: _nota.text,
            cobrado: _cobrado,
          );
      if (completada) {
        mensajero?.showSnackBar(
          const SnackBar(content: Text('Ruta completada. Buen trabajo.')),
        );
        ref.read(rutaElegidaProvider.notifier).elegir(null);
        ref.read(pestanaRutasProvider.notifier).elegir(PestanaRutas.historial);
      }
    } on RechazoLocal catch (no) {
      mensajero?.showSnackBar(SnackBar(content: Text(no.mensaje)));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.parada;
    final renglones =
        ref.watch(renglonesDeParadasProvider(widget.rutaId)).value?[p.id] ??
        const <RenglonConPeso>[];
    final conduce = ref
        .watch(conducesDeRutaProvider(widget.rutaId))
        .value?[p.id];
    final tel = (p.customerPhone ?? '').trim();

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.xl),
        side: BorderSide(color: Colores.primario.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Parada ${widget.numero} de ${widget.total}',
              key: const ValueKey('guia-numero-de-parada'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            FacturaYCliente(
              facturaNumero: p.facturaNumero,
              facturadaEl: p.facturaAt,
              cliente: p.customerName,
              conduce: conduce?.etiqueta,
            ),
            const SizedBox(height: 4),
            Text(
              p.endAddress ?? p.address,
              key: const ValueKey('guia-direccion'),
            ),
            if (tel.isNotEmpty)
              Text(
                'Tel. $tel',
                key: const ValueKey('guia-telefono'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            if ((p.notes ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Nota: ${p.notes!.trim()}',
                  key: const ValueKey('guia-notas'),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('guia-navegar'),
                  onPressed: () => _abrir(
                    enlaceParaNavegar(p),
                    'Esta parada no tiene punto en el mapa.',
                  ),
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('Navegar a esta parada'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('guia-llamar'),
                  onPressed: () => _abrir(
                    enlaceParaLlamar(p.customerPhone),
                    'El cliente no tiene telefono.',
                  ),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Llamar al cliente'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Entregar', style: Theme.of(context).textTheme.titleSmall),
            if (renglones.isEmpty)
              const Text('Sin productos en el aparato.')
            else
              for (final l in renglones)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${cantidad(l.empaques)}×',
                        style: Tipos.mono(
                          tamano: 14,
                          peso: FontWeight.w700,
                          color: Colores.tinta,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: Text(l.renglon.description)),
                    ],
                  ),
                ),
            const Divider(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in SalidaDeParada.values)
                  ChoiceChip(
                    key: ValueKey('guia-${s.name}'),
                    label: Text(s.etiqueta),
                    selected: _salida == s,
                    onSelected: _guardando
                        ? null
                        : (_) => setState(() {
                            _salida = s;
                            if (s != SalidaDeParada.entregado) _cobrado = false;
                          }),
                  ),
              ],
            ),
            if (_salida == SalidaDeParada.entregado)
              SwitchListTile(
                key: const ValueKey('guia-cobrado'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Cobrado'),
                subtitle: Text(_cobrado ? 'Sí, cobré' : 'No cobré'),
                value: _cobrado,
                onChanged: _guardando
                    ? null
                    : (v) => setState(() => _cobrado = v),
              ),
            TextField(
              key: const ValueKey('guia-nota'),
              controller: _nota,
              enabled: !_guardando,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _salida?.exigeMotivo == true
                    ? 'Motivo (obligatorio)'
                    : 'Nota (opcional)',
              ),
            ),
            const SizedBox(height: 12),
            BotonPrincipal(
              key: const ValueKey('guia-guardar'),
              icono: Icons.check,
              texto: widget.numero == widget.total
                  ? 'Guardar y terminar la ruta'
                  : 'Guardar y pasar a la siguiente',
              alPulsar: _puedeGuardar ? _guardar : null,
            ),
          ],
        ),
      ),
    );
  }
}
