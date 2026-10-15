import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/colores.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../pedidos/vista/kit.dart' show OpcionSelector, Selector;
import '../estado/proveedores_distribuidores.dart';
import 'cajon_distribuidores.dart';

/// «Distribuidor» al crear una ruta: quien responde de la entrega y de devolver las
/// facturas entregadas (issue 7 de Amado, 14/10/2026).
///
/// La usan los DOS sitios donde nace una ruta con una persona delante: el asistente
/// de «Nueva ruta» y el cajon de la zona del tablero (que es por donde se arma el
/// dia). Una sola pieza para que los dos digan lo mismo y recuerden lo mismo.
///
/// ## OPCIONAL, pero visible y recordado — y por que no obligatorio
///
/// No es obligatorio porque no se puede serlo todavia: las rutas de antes no
/// tienen distribuidor, hay sucursales que aun no han dado de alta a ninguno, y un
/// campo obligatorio sin un sitio donde crear el valor deja a esa sucursal sin
/// poder armar NADA — el mismo callejon del camion en el taller (`CLAUDE.md` §4).
/// Pero una ruta que sale sin decir quien la reparte es justo lo que Amado pide
/// evitar, asi que:
///
///  * **va a la vista**, en el mismo paso que el vehiculo, y con una frase que dice
///    para que sirve;
///  * **se recuerda**: queda elegido el de la ultima ruta de ESA sucursal (si sigue
///    en activo), porque quien arma diez rutas el mismo dia suele armarlas con las
///    mismas personas. Se ve elegido: no se manda nada a escondidas;
///  * **si se deja vacio con distribuidores disponibles, se avisa** en ambar;
///  * **si la sucursal no tiene ninguno, hay un enlace a crearlos** (el cajon de
///    «Distribuidores») sin salir del asistente;
///  * **si el aparato no los ha descargado, se dice** y se dice que se rompe: el
///    selector estaria vacio sin que sea verdad que no hay nadie.
class SelectorDeDistribuidor extends ConsumerStatefulWidget {
  const SelectorDeDistribuidor({
    required this.sucursalId,
    required this.elegido,
    required this.alElegir,
    super.key,
  });

  /// La sucursal de la RUTA: la del paso 1 del asistente o la de la zona. Un
  /// distribuidor tiene que ser de la misma que la ruta.
  final String? sucursalId;

  /// El id elegido, o `null` si la ruta saldra sin distribuidor.
  final String? elegido;

  final ValueChanged<String?> alElegir;

  static const claveDelSelector = ValueKey('selector-de-distribuidor');
  static const claveDelEnlace = ValueKey('enlace-a-distribuidores');
  static const claveDelAvisoSinElegir = ValueKey('distribuidor-sin-elegir');

  static const textoSinNinguno = 'Sin distribuidor';
  static const titulo = 'Distribuidor (opcional)';

  @override
  ConsumerState<SelectorDeDistribuidor> createState() =>
      _SelectorDeDistribuidorState();
}

class _SelectorDeDistribuidorState
    extends ConsumerState<SelectorDeDistribuidor> {
  /// La sucursal para la que ya se miro lo recordado. Se vuelve a mirar al cambiar
  /// de sucursal (otra lista, otro recuerdo) y no antes: si la persona elige «Sin
  /// distribuidor» a proposito, no se le vuelve a poner el de siempre.
  String? _recordadoParaLaSucursal;

  Future<void> _recordar(List<Distribuidor> lista) async {
    final sucursal = widget.sucursalId;
    if (sucursal == null || _recordadoParaLaSucursal == sucursal) return;
    _recordadoParaLaSucursal = sucursal;
    if (widget.elegido != null || lista.isEmpty) return;
    final guardado = await ref
        .read(baseProvider)
        .preferencia(ClaveDePreferencia.ultimoDistribuidorDe(sucursal));
    if (!mounted || guardado == null || widget.elegido != null) return;
    // Solo si sigue valiendo: de esa sucursal y en activo (la lista ya es asi).
    if (lista.any((d) => d.id == guardado)) widget.alElegir(guardado);
  }

  Future<void> _elegir(String id) async {
    final sucursal = widget.sucursalId;
    final valor = id.isEmpty ? null : id;
    // El recuerdo se guarda tambien al elegir «Sin distribuidor» (se borra): si no,
    // la proxima ruta resucitaria al de dos rutas atras.
    if (sucursal != null) {
      await ref
          .read(baseProvider)
          .anotarPreferencia(
            ClaveDePreferencia.ultimoDistribuidorDe(sucursal),
            valor,
          );
    }
    widget.alElegir(valor);
  }

  @override
  Widget build(BuildContext context) {
    final lista =
        ref.watch(distribuidoresParaRutaNuevaProvider(widget.sucursalId)).value ??
        const <Distribuidor>[];
    final copia = ref.watch(distribuidoresEnElAparatoProvider).value;
    final tema = Theme.of(context);

    if (lista.isNotEmpty && widget.elegido == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recordar(lista));
    }

    // El que estaba elegido pero ya no esta en la lista (se retiro mientras tanto):
    // no se deja puesto un valor que el desplegable no sabe pintar.
    final elegidoVale = lista.any((d) => d.id == widget.elegido);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Selector<String>(
          key: SelectorDeDistribuidor.claveDelSelector,
          titulo: SelectorDeDistribuidor.titulo,
          valor: elegidoVale ? widget.elegido! : '',
          opciones: [
            const OpcionSelector('', SelectorDeDistribuidor.textoSinNinguno),
            for (final d in lista) OpcionSelector(d.id, d.nombre),
          ],
          alElegir: _elegir,
        ),
        const SizedBox(height: 4),
        Text(
          'Quien responde de la entrega y de devolver las facturas entregadas.',
          style: tema.textTheme.bodySmall,
        ),
        if (lista.isEmpty) ...[
          const SizedBox(height: 4),
          Text(
            // «No bajo» y «no hay» se arreglan al reves, y se dicen distinto.
            copia != null && !copia.seDescargo
                ? 'Este aparato no ha descargado los distribuidores todavía. '
                      'Trae el día con conexión; la ruta se arma igual, sin '
                      'distribuidor.'
                : 'Esta sucursal no tiene distribuidores dados de alta. La ruta '
                      'se arma igual, sin distribuidor.',
            style: tema.textTheme.bodySmall?.copyWith(color: Colores.ambar),
          ),
        ] else if (!elegidoVale)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              key: SelectorDeDistribuidor.claveDelAvisoSinElegir,
              'Sin distribuidor: la ruta saldrá sin decir quién la reparte.',
              style: tema.textTheme.bodySmall?.copyWith(color: Colores.ambar),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: SelectorDeDistribuidor.claveDelEnlace,
            onPressed: () => abrirCajonDeDistribuidores(context),
            icon: const Icon(Icons.badge_outlined),
            label: Text(
              lista.isEmpty
                  ? 'Crear distribuidores'
                  : 'Administrar distribuidores',
            ),
          ),
        ),
      ],
    );
  }
}
