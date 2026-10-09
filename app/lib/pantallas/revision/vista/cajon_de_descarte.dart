import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/cajon.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../datos/bandeja.dart';
import '../datos/quien_revisa.dart';
import '../estado/proveedores_revision.dart';

/// DESCARTAR UN APUNTE: en un cajon, con el motivo OBLIGATORIO.
///
/// Descartar **no borra** (`CLAUDE.md` §4: «una decision de una persona se
/// ESCRIBE»). El apunte se queda como `descartado`, con tu nombre, la hora y lo
/// que escribas aqui, y la persona lo ve. Por eso el boton no se enciende hasta
/// que hay un motivo de verdad ([motivoValido]) y por eso la respuesta del
/// servidor manda: si dice que no (`403`, `422`…), el cajon se queda abierto y
/// lo dice con sus palabras.
Future<void> descartarConMotivo(
  BuildContext contexto,
  EntregaEnRevision entrega,
  ApunteEnRevision apunte,
) => abrirCajon<void>(
  contexto,
  titulo: TextosDeRevision.descartarTitulo,
  subtitulo: '${apunte.metodo} ${apunte.ruta}',
  cuerpo: (_) => _CuerpoDelDescarte(entrega: entrega, apunte: apunte),
);

class _CuerpoDelDescarte extends ConsumerStatefulWidget {
  const _CuerpoDelDescarte({required this.entrega, required this.apunte});

  final EntregaEnRevision entrega;
  final ApunteEnRevision apunte;

  @override
  ConsumerState<_CuerpoDelDescarte> createState() => _CuerpoDelDescarteState();
}

class _CuerpoDelDescarteState extends ConsumerState<_CuerpoDelDescarte> {
  final _motivo = TextEditingController();
  bool _enviando = false;

  /// Lo que el servidor contesto que NO, literal. `null` = nada que decir.
  String? _noPudo;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _descartar() async {
    setState(() {
      _enviando = true;
      _noPudo = null;
    });
    final noPudo = await ref
        .read(decisionesDelRevisorProvider.notifier)
        .descartar(widget.entrega, widget.apunte, _motivo.text);
    if (!mounted) return;
    if (noPudo == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _enviando = false;
      _noPudo = noPudo;
    });
  }

  @override
  Widget build(BuildContext context) {
    final puede = motivoValido(_motivo.text) && !_enviando;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(TextosDeRevision.descartarExplica),
        const SizedBox(height: Aire.lg),
        TextField(
          controller: _motivo,
          enabled: !_enviando,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: TextosDeRevision.motivoDelDescarte,
            helperText: TextosDeRevision.motivoDelDescarteAyuda,
            helperMaxLines: 3,
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_noPudo != null) ...[
          const SizedBox(height: Aire.md),
          Text(
            _noPudo!,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Colores.rojo, fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: Aire.lg),
        BotonDestructivo(
          texto: TextosDeRevision.descartarConMotivo,
          icono: Icons.block_outlined,
          alPulsar: puede ? _descartar : null,
        ),
      ],
    );
  }
}
