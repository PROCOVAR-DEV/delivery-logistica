// EL CAJON DE «MANDAR A UNA ZONA».
//
// Lo que faltaba para cerrar el flujo: se marca en Pedidos lo que se va a
// repartir —con los nueve filtros, que es como se decide— y se manda de golpe a
// una zona del tablero. Hasta hoy habia que irse al tablero y colocarlos uno a
// uno.
//
// Cajon y no modal, tambien en escritorio: es la excepcion aprobada el
// 05/09/2026 (`CLAUDE.md` §4). La ✕ la pone `Cajon` fuera del cuerpo
// desplazable, asi que no desaparece por mucho que se baje. Sin emojis.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/tema.dart';
import '../../tablero/datos/modelos.dart';
import '../datos/mandar_al_tablero.dart';
import '../estado/proveedores_pedidos.dart';
import 'kit.dart';

/// Abre el cajon. Lo llama la barra de lo marcado de la pantalla de Pedidos.
Future<void> abrirCajonMandarAlTablero(BuildContext context) =>
    abrirCajon<void>(context, (_) => const CajonMandarAlTablero());

class CajonMandarAlTablero extends ConsumerStatefulWidget {
  const CajonMandarAlTablero({super.key});

  /// Los literales, aqui arriba: son lo que buscan las pruebas y lo que lee
  /// quien esta delante.
  static const titulo = 'Mandar a una zona del tablero';
  static const mandar = 'Mandar a la zona';
  static const crearOtra = 'Crear una zona nueva';
  static const crear = 'Crear';
  static const sinZonas =
      'Este tablero todavía no tiene ninguna zona. Crea la primera con el '
      'nombre del barrio o del distrito.';

  @override
  ConsumerState<CajonMandarAlTablero> createState() =>
      _CajonMandarAlTableroState();
}

class _CajonMandarAlTableroState extends ConsumerState<CajonMandarAlTablero> {
  final _nombre = TextEditingController();

  String? _zonaElegida;
  bool _creando = false;
  bool _trabajando = false;
  String? _error;
  ResultadoDeMandar? _resultado;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final marcados = ref.watch(seleccionPedidosProvider);
    final resultado = _resultado;

    return Cajon(
      titulo: CajonMandarAlTablero.titulo,
      subtitulo: resultado == null
          ? '${marcados.length} pedido(s) marcados'
          : 'Zona «${resultado.zona}»',
      ancho: AnchoCajon.md,
      cuerpo: resultado == null ? _formulario() : _ResumenDeLoQuePaso(resultado),
      pie: resultado == null ? _pie() : _piePasoTerminado(),
    );
  }

  // ---------------------------------------------------------------------------
  // Antes de mandar
  // ---------------------------------------------------------------------------

  Widget _formulario() {
    final zonas = ref.watch(zonasDelTableroProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Se colocan en el orden en que están marcados, y el gesto es el mismo '
          'que arrastrarlos: se guarda aquí y sube cuando haya señal.',
          style: Tipos.texto(tamano: 13, color: Colores.tintaSuave, alto: 1.5),
        ),
        const SizedBox(height: Aire.lg),
        // El cajon se abre y las zonas pueden llegar DESPUES: en la web la base
        // nace vacia en cada carga. Por eso esto es un stream y aqui se
        // distinguen los tres estados en vez de pintar «no hay zonas» sobre una
        // lista que todavia esta bajando.
        switch (zonas) {
          AsyncValue<List<ColumnaTablero>>(hasError: true, :final error?) =>
            _Aviso('No se pudieron leer las zonas: $error'),
          AsyncValue<List<ColumnaTablero>>(:final value?) =>
            _listaDeZonas(value),
          _ => const Padding(
            padding: EdgeInsets.symmetric(vertical: Aire.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
        if (_error case final fallo?) ...[
          const SizedBox(height: Aire.md),
          _Aviso(fallo),
        ],
      ],
    );
  }

  Widget _listaDeZonas(List<ColumnaTablero> zonas) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (zonas.isEmpty)
        Text(
          CajonMandarAlTablero.sinZonas,
          style: Tipos.texto(tamano: 13, color: Colores.tintaSuave, alto: 1.5),
        )
      else
        for (final zona in zonas) _fila(zona),
      const SizedBox(height: Aire.sm),
      if (_creando || zonas.isEmpty)
        _cajaDeNombre()
      else
        TextButton.icon(
          onPressed: () => setState(() => _creando = true),
          icon: const Icon(Icons.add, size: 18),
          label: const Text(CajonMandarAlTablero.crearOtra),
        ),
    ],
  );

  /// Una zona de la lista. Sin `RadioListTile`: lo que hace falta es que se vea
  /// cual esta elegida y que se pueda tocar toda la fila.
  Widget _fila(ColumnaTablero zona) {
    final elegida = zona.id == _zonaElegida;
    return Padding(
      padding: const EdgeInsets.only(bottom: Aire.xs),
      child: Material(
        color: elegida ? Colores.primarioTenue : Colores.blanco,
        borderRadius: BorderRadius.circular(Radios.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radios.lg),
          onTap: _trabajando
              ? null
              : () => setState(() {
                  _zonaElegida = zona.id;
                  _error = null;
                }),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radios.lg),
              border: Border.all(
                color: elegida ? Colores.primario : Colores.linea,
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: Aire.md,
              vertical: Aire.md,
            ),
            child: Row(
              children: [
                Icon(
                  elegida
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: elegida ? Colores.primario : Colores.tintaSuave,
                ),
                const SizedBox(width: Aire.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        zona.nombre,
                        style: Tipos.texto(
                          tamano: 14,
                          peso: FontWeight.w600,
                          color: Colores.tinta,
                        ),
                      ),
                      Text(
                        '${zona.pedidos} pedido(s) puestos',
                        style: Tipos.texto(
                          tamano: 12,
                          color: Colores.tintaSuave,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cajaDeNombre() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: TextField(
          controller: _nombre,
          enabled: !_trabajando,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Nombre de la zona nueva',
            hintText: 'Vista Alegre',
          ),
          onSubmitted: (_) => _crearZona(),
        ),
      ),
      const SizedBox(width: Aire.sm),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: OutlinedButton(
          onPressed: _trabajando ? null : _crearZona,
          child: const Text(CajonMandarAlTablero.crear),
        ),
      ),
    ],
  );

  /// `Wrap` y no `Row`: en el cajon estrecho —y en el telefono, donde ocupa la
  /// pantalla entera— los dos botones no caben en una linea y un `Row` los
  /// desborda por la derecha, que es esconder el gesto que importa.
  Widget _pie() => Wrap(
    alignment: WrapAlignment.end,
    spacing: Aire.sm,
    runSpacing: Aire.xs,
    children: [
      TextButton(
        onPressed: _trabajando ? null : () => Navigator.of(context).maybePop(),
        child: const Text('Cancelar'),
      ),
      // `ElevatedButton` Y NO `FilledButton`, y da igual: los dos cuelgan del
      // mismo nivel principal del tema (`diseno/tema.dart`, [Botones]). Por eso
      // este tambien entra por [BotonPrincipal] — el agujero del icono era de
      // los dos, no solo del relleno.
      BotonPrincipal(
        icono: Icons.send_outlined,
        texto: CajonMandarAlTablero.mandar,
        alPulsar: _zonaElegida == null || _trabajando ? null : _mandar,
      ),
    ],
  );

  Widget _piePasoTerminado() => Wrap(
    alignment: WrapAlignment.end,
    children: [
      BotonPrincipal(
        icono: Icons.close,
        texto: 'Cerrar',
        alPulsar: () => Navigator.of(context).maybePop(),
      ),
    ],
  );

  // ---------------------------------------------------------------------------

  Future<void> _crearZona() async {
    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(envioAlTableroProvider.notifier)
          .crearZona(_nombre.text);
      if (!mounted) return;
      setState(() {
        _zonaElegida = id;
        _creando = false;
        _nombre.clear();
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = _decirlo(e));
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _mandar() async {
    final columnaId = _zonaElegida;
    if (columnaId == null) return;
    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      final resultado = await ref
          .read(envioAlTableroProvider.notifier)
          .mandarLoMarcado(columnaId);
      if (!mounted) return;
      setState(() => _resultado = resultado);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = _decirlo(e));
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  /// El motivo LITERAL cuando lo hay. «Ya hay una columna «Centro» en este
  /// tablero» le dice a alguien que hacer; «no se pudo guardar» no le dice nada
  /// (`CLAUDE.md` §3-quinquies).
  static String _decirlo(Object e) => switch (e) {
    RechazoDelTablero(:final mensaje) => mensaje,
    FaltaElegirSucursal(:final mensaje) => mensaje,
    _ => 'No se pudo: $e',
  };
}

/// QUE PASO, con nombres y motivos. Nada se descarta en silencio (§4).
class _ResumenDeLoQuePaso extends StatelessWidget {
  const _ResumenDeLoQuePaso(this.resultado);

  final ResultadoDeMandar resultado;

  /// El literal del titular, para que la prueba busque lo que lee una persona.
  static String titular(ResultadoDeMandar r) =>
      '${r.cuantos} pedido(s) en «${r.zona}»';

  static String seQuedaron(ResultadoDeMandar r) =>
      'No se pudieron mandar ${r.noFueron.length}, y siguen marcados:';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        titular(resultado),
        style: Tipos.texto(
          tamano: 15,
          peso: FontWeight.w600,
          color: Colores.tinta,
        ),
      ),
      if (resultado.alguienSeQuedo) ...[
        const SizedBox(height: Aire.lg),
        _Aviso(seQuedaron(resultado)),
        const SizedBox(height: Aire.sm),
        for (final quedado in resultado.noFueron)
          Padding(
            padding: const EdgeInsets.only(bottom: Aire.xs),
            child: Text(
              quedado.linea,
              style: Tipos.texto(tamano: 13, color: Colores.tinta, alto: 1.4),
            ),
          ),
      ],
    ],
  );
}

/// Una caja en ámbar: no es una avería, es algo que hay que leer.
class _Aviso extends StatelessWidget {
  const _Aviso(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(Aire.md),
    decoration: BoxDecoration(
      color: Colores.ambarFondo,
      border: Border.all(color: Colores.ambar.withValues(alpha: 0.3)),
      borderRadius: BorderRadius.circular(Radios.lg),
    ),
    child: Text(
      texto,
      style: Tipos.texto(tamano: 13, color: Colores.tinta, alto: 1.4),
    ),
  );
}
