import 'package:flutter/material.dart';

import '../../../diseno/cajon.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../datos/bandeja.dart';
import '../datos/que_hace.dart';
import '../datos/quien_revisa.dart';

/// ANTES DE APLICAR EN BLOQUE: el recuento, en un cajon, y sin un solo toque que
/// ejecute nada.
///
/// Auditoria de seguridad de la bandeja, M2 (09/10/2026): «Aplicar todo en orden»
/// no preguntaba, y un autor hostil puede dejar hasta 500 `DELETE /routes/<uuid>`
/// que se ejecutan con la autoridad del REVISOR. Lo unico que lo separa del
/// desastre es que el revisor SEPA lo que va a hacer, asi que aqui se le dice:
/// cuantos cambios, de que metodo y de que tipo, las rutas exactas (plegadas) y
/// los DELETE en rojo. Con cualquier DELETE o con mas de [maximoSinSegundoPaso]
/// cambios hay un SEGUNDO PASO: escribir el numero. Un toque no basta.
///
/// **Cerrar sin contestar es NO** (`abrirCajon` devuelve `null`).
Future<bool> confirmarAplicarTodo(
  BuildContext contexto,
  EntregaEnRevision entrega,
) async {
  final resumen = ResumenDeAplicar.de(entrega.apuntes);
  final si = await abrirCajon<bool>(
    contexto,
    titulo: TextosDeRevision.aplicarTodoTitulo,
    cuerpo: (_) => _CuerpoDeAplicarTodo(resumen: resumen),
  );
  return si ?? false;
}

class _CuerpoDeAplicarTodo extends StatefulWidget {
  const _CuerpoDeAplicarTodo({required this.resumen});

  final ResumenDeAplicar resumen;

  @override
  State<_CuerpoDeAplicarTodo> createState() => _CuerpoDeAplicarTodoState();
}

class _CuerpoDeAplicarTodoState extends State<_CuerpoDeAplicarTodo> {
  final _numero = TextEditingController();

  @override
  void dispose() {
    _numero.dispose();
    super.dispose();
  }

  /// El segundo paso se cumple cuando se escribio EXACTAMENTE el total.
  bool get _escritoBien =>
      !widget.resumen.exigeEscribirElNumero ||
      _numero.text.trim() == '${widget.resumen.total}';

  @override
  Widget build(BuildContext context) {
    final r = widget.resumen;
    final tema = Theme.of(context);
    final porMetodo = r.metodosOrdenados
        .map((e) => '${e.value} ${e.key}')
        .join(', ');
    // Los tipos: lo que borra, primero.
    final tipos = r.porTipo.entries.toList()
      ..sort((a, b) {
        final da = a.key.startsWith('DELETE|') ? 0 : 1;
        final db = b.key.startsWith('DELETE|') ? 0 : 1;
        return da != db ? da.compareTo(db) : b.value.compareTo(a.value);
      });

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(TextosDeRevision.recuento(r.total, porMetodo)),
        if (r.hayBorrados) ...[
          const SizedBox(height: Aire.md),
          Text(
            TextosDeRevision.avisoDeBorrados,
            style: tema.textTheme.bodyMedium?.copyWith(
              color: Colores.rojo,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: Aire.lg),
        Text(TextosDeRevision.porTipo, style: tema.textTheme.labelLarge),
        const SizedBox(height: Aire.sm),
        for (final t in tipos)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '${t.value} × ${_etiqueta(t.key)}',
              style: tema.textTheme.bodyMedium?.copyWith(
                color: t.key.startsWith('DELETE|') ? Colores.rojo : null,
                fontWeight: t.key.startsWith('DELETE|')
                    ? FontWeight.w600
                    : null,
              ),
            ),
          ),
        Theme(
          data: tema.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              TextosDeRevision.verLasRutas(r.rutas.length),
              style: tema.textTheme.labelLarge,
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in r.rutas.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: SelectableText(
                    e.value == 1 ? e.key : '${e.key}  (×${e.value})',
                    style: Tipos.mono(
                      tamano: 12,
                      color: e.key.startsWith('DELETE ')
                          ? Colores.rojo
                          : Colores.tinta,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (r.exigeEscribirElNumero) ...[
          const SizedBox(height: Aire.md),
          TextField(
            controller: _numero,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: TextosDeRevision.numeroDeCambios,
              helperText: TextosDeRevision.escribeElNumero(r.total),
              helperMaxLines: 2,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: Aire.lg),
        if (r.hayBorrados)
          BotonDestructivo(
            texto: TextosDeRevision.confirmaAplicar(r.total),
            icono: Icons.playlist_add_check,
            alPulsar: _escritoBien
                ? () => Navigator.of(context).pop(true)
                : null,
          )
        else
          BotonPrincipal(
            texto: TextosDeRevision.confirmaAplicar(r.total),
            icono: Icons.playlist_add_check,
            alPulsar: _escritoBien
                ? () => Navigator.of(context).pop(true)
                : null,
          ),
        const SizedBox(height: Aire.sm),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(TextosDeRevision.noAplicarTodo),
        ),
      ],
    );
  }

  /// `'DELETE|Borrar una ruta'` -> «Borrar una ruta (DELETE)»; lo crudo
  /// (`'DELETE|DELETE /x'`) se queda como esta.
  String _etiqueta(String clave) {
    final i = clave.indexOf('|');
    final metodo = clave.substring(0, i);
    final tipo = clave.substring(i + 1);
    return tipo.startsWith('$metodo ') ? tipo : '$tipo ($metodo)';
  }
}

/// ANTES DE APLICAR UN APUNTE SUELTO que borra o modifica: pregunta corta, con
/// el metodo y la ruta delante. Crear, mover y registrar resultados no preguntan.
Future<bool> confirmarAplicarSuelto(
  BuildContext contexto,
  ApunteEnRevision apunte,
) async {
  final metodo = apunte.metodo.toUpperCase();
  final borra = metodo == 'DELETE';
  final si = await abrirCajon<bool>(
    contexto,
    titulo: TextosDeRevision.sueltoTitulo(metodo),
    cuerpo: (contextoCajon) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (queHace(metodo, apunte.ruta) case final texto?)
          Text(
            texto,
            style: Theme.of(contextoCajon).textTheme.titleMedium
                ?.copyWith(color: borra ? Colores.rojo : null),
          ),
        const SizedBox(height: Aire.sm),
        SelectableText(
          '$metodo ${apunte.ruta}',
          style: Tipos.mono(tamano: 12, color: Colores.tinta),
        ),
        const SizedBox(height: Aire.md),
        const Text(TextosDeRevision.sueltoBorra),
        const SizedBox(height: Aire.lg),
        if (borra)
          BotonDestructivo(
            texto: TextosDeRevision.sueltoConfirma,
            icono: Icons.done_outlined,
            alPulsar: () => Navigator.of(contextoCajon).pop(true),
          )
        else
          BotonPrincipal(
            texto: TextosDeRevision.sueltoConfirma,
            icono: Icons.done_outlined,
            alPulsar: () => Navigator.of(contextoCajon).pop(true),
          ),
        const SizedBox(height: Aire.sm),
        TextButton(
          onPressed: () => Navigator.of(contextoCajon).pop(false),
          child: const Text(TextosDeRevision.sueltoNo),
        ),
      ],
    ),
  );
  return si ?? false;
}
