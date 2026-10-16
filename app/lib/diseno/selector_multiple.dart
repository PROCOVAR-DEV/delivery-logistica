import 'package:flutter/material.dart';

import 'anchos.dart';
import 'cajon.dart';
import 'colores.dart';
import 'tema.dart';

/// Una opción: su texto es su valor. No es el `OpcionSelector` de [Selector] a
/// propósito —el kit de Pedidos tiene otro con el mismo nombre y las pantallas
/// importan los dos—, y aquí la etiqueta y el valor son lo mismo (un nombre).
class OpcionMultiple {
  const OpcionMultiple(this.valor, {this.nota});

  final String valor;

  /// Pequeña, a la derecha: cuántos pedidos tiene.
  final String? nota;
}

/// EL FILTRO DE ELEGIR UNO O VARIOS (issue 18 de Amado, 16/10/2026: «ajustar el
/// filtro de vendedores para que sea de múltiple selección […] porque pueden haber
/// pocos domicilios y se combinan los de ambos»).
///
/// Es hermano de [Selector]: la misma caja blanca con borde y flecha, y **cajón
/// siempre**, también en escritorio (CLAUDE.md §4). Lo que cambia es lo de dentro:
/// una casilla por opción, que se marca y se desmarca sin cerrar, y arriba
/// «[todos]», que limpia la selección. Sin nada marcado es «todos»: el filtro no
/// filtra, igual que la primera opción de un [Selector].
///
/// **Lo que hay marcado vive FUERA** ([seleccion], [alCambiar]): esto no guarda
/// estado entre aperturas, porque el filtro vive en la URL del tablero y en el
/// provider de la pantalla. Dentro del cajón sí hay una copia local, porque el
/// cajón es otra ruta y no se repinta cuando la pantalla de debajo cambia.
///
/// El resumen de la caja: nada = [todos]; uno = su nombre; varios = «3 vendedores»
/// ([plural]). Una selección que ya no está en las [opciones] —el enlace trae un
/// vendedor que hoy no tiene pedidos— se sigue enseñando y se puede desmarcar: un
/// filtro puesto que no se ve es un filtro que no se puede quitar.
class SelectorMultiple extends StatelessWidget {
  const SelectorMultiple({
    required this.titulo,
    required this.todos,
    required this.plural,
    required this.opciones,
    required this.seleccion,
    required this.alCambiar,
    this.expandido = false,
    this.desdeCuantasBusca = 4,
    super.key,
  });

  /// El título del cajón y el tooltip de la caja: `Vendedor del pedido`.
  final String titulo;

  /// El texto de «no filtra»: `Todos los vendedores`.
  final String todos;

  /// Lo que se cuenta cuando hay varios: `vendedores` → «3 vendedores».
  final String plural;

  final List<OpcionMultiple> opciones;
  final List<String> seleccion;
  final ValueChanged<List<String>> alCambiar;

  /// `true` para una columna de formulario: la caja ocupa todo el ancho y el
  /// texto va a la izquierda. `false` para una barra de filtros: mide lo que mide
  /// su texto.
  final bool expandido;

  final int desdeCuantasBusca;

  /// Lo que dice la caja. Aquí y no en el `build` para que lo lean las pruebas.
  static String resumen(
    List<String> seleccion, {
    required String todos,
    required String plural,
  }) => switch (seleccion.length) {
    0 => todos,
    1 => seleccion.first,
    final n => '$n $plural',
  };

  @override
  Widget build(BuildContext context) {
    final filtrando = seleccion.isNotEmpty;
    final texto = Text(
      resumen(seleccion, todos: todos, plural: plural),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
    return Tooltip(
      message: titulo,
      child: OutlinedButton(
        onPressed: () => abrirCajon<void>(
          context,
          titulo: titulo,
          ancho: AnchoCajon.md,
          cuerpo: (_) => _Cuerpo(
            todos: todos,
            opciones: opciones,
            inicial: seleccion,
            conBuscador: opciones.length >= desdeCuantasBusca,
            alCambiar: alCambiar,
          ),
        ),
        // EL BLANCO SE QUEDA, por lo mismo que en [Selector]: no es un botón, es
        // un campo que se dibuja al lado de las cajas de buscar y de fecha.
        style: OutlinedButton.styleFrom(
          backgroundColor: Colores.blanco,
          foregroundColor: filtrando ? Colores.tinta : Colores.tintaSuave,
          alignment: expandido ? Alignment.centerLeft : Alignment.center,
          side: BorderSide(
            color: filtrando
                ? Colores.primario.withValues(alpha: 0.5)
                : Colores.linea,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          textStyle: Tipos.texto(
            tamano: 14,
            peso: filtrando ? FontWeight.w600 : FontWeight.w400,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radios.lg),
          ),
        ),
        child: Row(
          mainAxisSize: expandido ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (expandido) Expanded(child: texto) else Flexible(child: texto),
            const SizedBox(width: Aire.xs),
            Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: Colores.tintaSuave,
            ),
          ],
        ),
      ),
    );
  }
}

class _Cuerpo extends StatefulWidget {
  const _Cuerpo({
    required this.todos,
    required this.opciones,
    required this.inicial,
    required this.conBuscador,
    required this.alCambiar,
  });

  final String todos;
  final List<OpcionMultiple> opciones;
  final List<String> inicial;
  final bool conBuscador;
  final ValueChanged<List<String>> alCambiar;

  @override
  State<_Cuerpo> createState() => _CuerpoState();
}

class _CuerpoState extends State<_Cuerpo> {
  late final Set<String> _marcadas = {...widget.inicial};
  String _busca = '';

  /// Lo marcado, en el orden de las opciones y con lo que ya no está en ellas al
  /// final: el mismo conjunto da siempre la misma lista, y la URL no cambia de
  /// texto por marcar en otro orden.
  List<String> _enOrden() => [
    for (final o in widget.opciones)
      if (_marcadas.contains(o.valor)) o.valor,
    for (final v in widget.inicial)
      if (_marcadas.contains(v) && !widget.opciones.any((o) => o.valor == v)) v,
  ];

  void _poner(void Function() cambio) {
    setState(cambio);
    widget.alCambiar(_enOrden());
  }

  @override
  Widget build(BuildContext context) {
    final texto = _busca.trim().toLowerCase();
    // Las que ya no están en la lista, arriba y siempre a la vista: el buscador no
    // las esconde, que es justo cuando hay que poder quitarlas.
    final sueltas = [
      for (final v in widget.inicial)
        if (!widget.opciones.any((o) => o.valor == v)) OpcionMultiple(v),
    ];
    final visibles = [
      for (final o in widget.opciones)
        if (texto.isEmpty ||
            o.valor.toLowerCase().contains(texto) ||
            (o.nota ?? '').toLowerCase().contains(texto))
          o,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.conBuscador) ...[
          TextField(
            // Sin `autofocus`: en un teléfono el teclado se come la mitad del
            // cajón (mismo motivo que en [Selector]).
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              prefixIconConstraints: BoxConstraints(minWidth: 34),
              hintText: 'Buscar…',
            ),
            onChanged: (v) => setState(() => _busca = v),
          ),
          const SizedBox(height: Aire.sm),
        ],
        // «TODOS» LIMPIA, y no la filtra el buscador: es la salida.
        ListTile(
          key: const ValueKey('selector-multiple-todos'),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(
            widget.todos,
            style: Tipos.texto(
              tamano: 14,
              peso: _marcadas.isEmpty ? FontWeight.w600 : FontWeight.w400,
              color: _marcadas.isEmpty ? Colores.primario : Colores.tinta,
            ),
          ),
          trailing: _marcadas.isEmpty
              ? Icon(Icons.check, size: 16, color: Colores.primario)
              : null,
          onTap: _marcadas.isEmpty ? null : () => _poner(_marcadas.clear),
        ),
        if (texto.isNotEmpty && visibles.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Aire.lg),
            child: Text(
              'Nada que cuadre con «${_busca.trim()}»',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colores.tintaSuave),
            ),
          ),
        for (final o in [...sueltas, ...visibles])
          CheckboxListTile(
            key: ValueKey('selector-multiple-${o.valor}'),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            value: _marcadas.contains(o.valor),
            onChanged: (marcada) => _poner(() {
              if (marcada ?? false) {
                _marcadas.add(o.valor);
              } else {
                _marcadas.remove(o.valor);
              }
            }),
            title: Text(
              o.valor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tipos.texto(tamano: 14, color: Colores.tinta),
            ),
            secondary: o.nota == null
                ? null
                : Text(
                    o.nota!,
                    style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
                  ),
          ),
      ],
    );
  }
}
