import 'package:flutter/material.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/cajon.dart';
import '../../../diseno/tema.dart' show BotonPrincipal;
import '../datos/vehiculo_api.dart';

/// El cajon `md` de «Tipos de vehículo». Pliego: `pantallas.md` §5.
///
/// Se edita la lista entera y se manda entera en `PUT /api/settings`, igual que
/// los almacenes: el servidor guarda `tiposVehiculo` como un bloque, no tipo a
/// tipo.
class TiposDeVehiculo extends StatefulWidget {
  const TiposDeVehiculo({
    required this.tipos,
    required this.guardando,
    required this.alGuardar,
    super.key,
  });

  final List<TipoDeVehiculo> tipos;
  final bool guardando;
  final ValueChanged<List<TipoDeVehiculo>> alGuardar;

  @override
  State<TiposDeVehiculo> createState() => _TiposDeVehiculoState();
}

class _TiposDeVehiculoState extends State<TiposDeVehiculo> {
  late List<_Fila> _filas;

  @override
  void initState() {
    super.initState();
    _filas = [
      for (final t in widget.tipos)
        _Fila(
          nombre: TextEditingController(text: t.nombre),
          costo: TextEditingController(
            text: t.costoKmUsd == null ? '' : '${t.costoKmUsd}',
          ),
        ),
    ];
  }

  @override
  void dispose() {
    for (final f in _filas) {
      f.nombre.dispose();
      f.costo.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Cajon(
    titulo: 'Tipos de vehículo',
    // El `md` del pliego. En la copia que habia aqui el ancho se recibia y no
    // se usaba —`showModalBottomSheet` lo ocupaba todo—, asi que este cajon
    // sale ahora mas estrecho que antes, que es lo que pedia §9.2.
    ancho: AnchoCajon.md,
    pie: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: widget.guardando
              ? null
              : () => Navigator.of(context).maybePop(),
          child: const Text('Cancelar'),
        ),
        const SizedBox(width: 8),
        BotonPrincipal(
          icono: Icons.save_outlined,
          texto: 'Guardar',
          alPulsar: widget.guardando
              ? null
              : () => widget.alGuardar([
                  // Los que se quedaron sin nombre no se mandan: un tipo sin
                  // nombre no se puede elegir despues y sólo ensucia la lista.
                  for (final f in _filas)
                    if (f.nombre.text.trim().isNotEmpty)
                      TipoDeVehiculo(
                        nombre: f.nombre.text.trim(),
                        costoKmUsd: double.tryParse(f.costo.text.trim()),
                      ),
                ]),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Define cada tipo con su costo por km por defecto. Al crear un '
            'vehículo de ese tipo se hereda el costo/km (editable por vehículo).',
          ),
          const SizedBox(height: 12),
          if (_filas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Sin tipos. Agrega el primero.'),
            )
          else
            for (final (indice, fila) in _filas.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: fila.nombre,
                        decoration: const InputDecoration(
                          labelText: 'Nombre',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: fila.costo,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Costo/km (USD)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Quitar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() {
                        final quitada = _filas.removeAt(indice);
                        quitada.nombre.dispose();
                        quitada.costo.dispose();
                      }),
                    ),
                  ],
                ),
              ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(
                () => _filas.add(
                  _Fila(
                    nombre: TextEditingController(),
                    costo: TextEditingController(),
                  ),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Agregar tipo'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Fila {
  _Fila({required this.nombre, required this.costo});
  final TextEditingController nombre;
  final TextEditingController costo;
}
