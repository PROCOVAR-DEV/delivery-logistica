// «TELÉFONOS»: los dispositivos de los distribuidores, para que la oficina vea cuál está vinculado a qué vehículo y lo DESVINCULE.
//
// `GET /api/dispositivos` (ya acotado a la sucursal de quien pregunta; SUPER ADMIN y DESARROLLADOR ven todas). Siempre en vivo contra el
// servidor, como el resto de «Distribución»: sin red lo dice y ofrece «Reintentar». Se refresca solo cada 30 segundos y al desvincular.
// «Desvincular» es la MISMA acción que la del vehículo (`desvincularConConfirmacion`): mismo cajón, mismo texto, mismas rutas sueltas.
// Tarjetas en teléfono y tabla en ancho de escritorio.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/caja_de_busqueda.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/tabla_ancha.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/proveedores.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../../pedidos/datos/formato.dart';
import '../../pedidos/vista/kit.dart'
    show EstadoVacio, Insignia, OpcionSelector, Selector;
import '../datos/api_distribucion.dart';
import '../datos/modelos.dart';
import 'donde_estan_ahora.dart' show TextosDeDondeEstan;
import 'recorrido_real.dart' show cuantoDura;
import 'vinculo_del_vehiculo.dart' show desvincularConConfirmacion;

abstract final class TextosDeLosTelefonos {
  static const sinNombre = 'Teléfono sin nombre';
  static const sinVehiculo = 'Sin vehículo';
  static const deBaja = 'Dado de baja';
  static const nuncaVisto = 'Nunca visto';
  static const ninguno =
      'Todavía no hay teléfonos de distribuidores. Aparecen aquí cuando uno abre el enlace de una ruta.';
  static const ningunoVinculado =
      'Ningún teléfono está vinculado ahora. Cambia a «Todos» para ver los que se desvincularon.';
  static const nadaDeEsto = 'No hay teléfonos que cuadren con esto.';
  static String vinculadoDesde(DateTime? d) =>
      'Vinculado desde ${fechaYHora(d)}';
  static String rutas(int n) => n == 1 ? '1 ruta abierta' : '$n rutas abiertas';
  static String visto(Duration? d) => d == null
      ? nuncaVisto
      : d.inMinutes < 1
      ? 'Visto hace menos de 1 minuto'
      : 'Visto hace ${cuantoDura(d)}';
}

const claveDeLosTelefonos = ValueKey('telefonos-lista');
const claveDeActualizarTelefonos = ValueKey('telefonos-actualizar');
const claveDelFiltroDeTelefonos = ValueKey('telefonos-filtro');
const claveDelAvisoDeTelefonos = ValueKey('telefonos-aviso');
ValueKey<String> claveDelTelefono(String id) => ValueKey('telefono-$id');
Key claveDeDesvincularTelefono(String id) =>
    ValueKey('telefono-desvincular-$id');
Key claveDelAvisoSinSenalTelefono(String id) =>
    ValueKey('telefono-sin-senal-$id');

enum FiltroDeTelefonos { vinculados, todos }

int cuantosVinculados(List<TelefonoDeDistribuidor> l) =>
    l.where((t) => t.vinculado).length;

/// Lo que se ve según el filtro y el buscador (nombre, vehículo, placa o distribuidor). Pura, para probarla sin pantalla.
List<TelefonoDeDistribuidor> filtrarTelefonos(
  List<TelefonoDeDistribuidor> telefonos, {
  FiltroDeTelefonos filtro = FiltroDeTelefonos.vinculados,
  String q = '',
}) {
  final t = q.trim().toLowerCase();
  return [
    for (final x in telefonos)
      if ((filtro == FiltroDeTelefonos.todos || x.vinculado) &&
          (t.isEmpty ||
              [
                x.nombre,
                x.vehiculo,
                x.placa,
                x.distribuidor,
              ].any((c) => c != null && c.toLowerCase().contains(t))))
        x,
  ];
}

class TelefonosDeDistribuidores extends ConsumerStatefulWidget {
  const TelefonosDeDistribuidores({
    this.cada = const Duration(seconds: 30),
    super.key,
  });

  /// Cada cuánto se vuelve a pedir solo.
  final Duration cada;

  @override
  ConsumerState<TelefonosDeDistribuidores> createState() =>
      _TelefonosDeDistribuidoresState();
}

class _TelefonosDeDistribuidoresState
    extends ConsumerState<TelefonosDeDistribuidores> {
  Timer? _reloj;
  var _filtro = FiltroDeTelefonos.vinculados;
  var _q = '';
  String? _fallo;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _reloj = Timer.periodic(
      widget.cada,
      (_) => ref.invalidate(telefonosProvider),
    );
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  Future<void> _desvincular(TelefonoDeDistribuidor t) async {
    try {
      await desvincularConConfirmacion(
        context,
        ref,
        vehiculoId: t.vehiculoId!,
        nombre: t.vehiculo ?? TextosDeLosTelefonos.sinVehiculo,
        telefono: t.nombre,
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
    final lista = ref.watch(telefonosProvider);
    // Mientras se vuelve a pedir se sigue enseñando lo que había: no parpadea a «Cargando».
    final datos = lista.value;
    if (datos == null) {
      return lista.hasError
          ? EstadoVacio(
              'No se pudieron leer los teléfonos: ${motivoDelFallo(lista.error!)}',
              accion: OutlinedButton.icon(
                key: claveDeActualizarTelefonos,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
                onPressed: () => ref.invalidate(telefonosProvider),
              ),
            )
          : const EstadoVacio('Cargando los teléfonos…');
    }
    final tema = Theme.of(context);
    final vistos = filtrarTelefonos(datos, filtro: _filtro, q: _q);
    final variasSucursales = datos.map((t) => t.sucursalId).toSet().length > 1;
    final ahora = ref.watch(relojProvider)();
    final primero = vistos.where((t) => t.vinculado).firstOrNull?.id;
    return ListView(
      key: claveDeLosTelefonos,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CajaDeBusqueda(
              valor: _q,
              ancho: 260,
              pista: 'Buscar por teléfono, vehículo, distribuidor…',
              alBuscar: (t) => setState(() => _q = t),
            ),
            Selector<FiltroDeTelefonos>(
              key: claveDelFiltroDeTelefonos,
              titulo: 'Mostrar',
              valor: _filtro,
              opciones: const [
                OpcionSelector(FiltroDeTelefonos.vinculados, 'Solo vinculados'),
                OpcionSelector(FiltroDeTelefonos.todos, 'Todos'),
              ],
              alElegir: (f) => setState(() => _filtro = f),
            ),
            TextButton.icon(
              key: claveDeActualizarTelefonos,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Actualizar'),
              onPressed: () => ref.invalidate(telefonosProvider),
            ),
          ],
        ),
        if (lista.hasError)
          _Aviso(
            'No se pudo actualizar (${motivoDelFallo(lista.error!)}). Se ve lo último que se supo.',
          ),
        if (_fallo != null) _Aviso(_fallo!),
        const SizedBox(height: 12),
        if (vistos.isEmpty)
          EstadoVacio(
            datos.isEmpty
                ? TextosDeLosTelefonos.ninguno
                : _q.trim().isNotEmpty
                ? TextosDeLosTelefonos.nadaDeEsto
                : _filtro == FiltroDeTelefonos.vinculados
                ? TextosDeLosTelefonos.ningunoVinculado
                : TextosDeLosTelefonos.nadaDeEsto,
          )
        else
          LayoutBuilder(
            builder: (context, medidas) => medidas.maxWidth >= Anchos.escritorio
                ? _tabla(context, vistos, ahora, variasSucursales, primero)
                : Column(
                    children: [
                      for (final t in vistos)
                        _Tarjeta(
                          t,
                          tema: tema,
                          ahora: ahora,
                          conSucursal: variasSucursales,
                          boton: _boton(t, primero),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }

  /// «Desvincular», solo en los vinculados. El manual señala el primero de la lista.
  Widget? _boton(TelefonoDeDistribuidor t, String? primero) => !t.vinculado
      ? null
      : ControlSenalado(
          nombre: Senalado.distribucionDesvincularTelefono,
          senalable: t.id == primero,
          child: BotonDestructivo(
            key: claveDeDesvincularTelefono(t.id),
            texto: 'Desvincular',
            icono: Icons.link_off,
            alPulsar: _ocupado ? null : () => _desvincular(t),
          ),
        );

  Widget _tabla(
    BuildContext context,
    List<TelefonoDeDistribuidor> vistos,
    DateTime ahora,
    bool conSucursal,
    String? primero,
  ) {
    final tema = Theme.of(context);
    return TarjetaDeTabla(
      child: TablaAncha(
        anchoMinimo: 1100,
        child: Theme(
          data: tema.copyWith(dataTableTheme: temaDeTabla(context)),
          child: DataTable(
            showCheckboxColumn: false,
            columns: [
              DataColumn(label: cabecera('Teléfono')),
              if (conSucursal) DataColumn(label: cabecera('Sucursal')),
              DataColumn(label: cabecera('Vehículo')),
              DataColumn(label: cabecera('Vinculado desde')),
              DataColumn(label: cabecera('Distribuidor')),
              DataColumn(label: cabecera('Rutas abiertas')),
              DataColumn(label: cabecera('Visto')),
              const DataColumn(label: SizedBox.shrink()),
            ],
            rows: [
              for (final t in vistos)
                DataRow(
                  cells: [
                    // `DataRow` no es un widget: la clave de la fila va en su primera celda.
                    DataCell(
                      KeyedSubtree(
                        key: claveDelTelefono(t.id),
                        child: _Nombre(t),
                      ),
                    ),
                    if (conSucursal) DataCell(Text(t.sucursal ?? '—')),
                    DataCell(Text(_vehiculo(t))),
                    DataCell(
                      Text(
                        t.vinculado
                            ? TextosDeLosTelefonos.vinculadoDesde(t.vinculadoAt)
                            : '—',
                      ),
                    ),
                    DataCell(Text(t.distribuidor ?? '—')),
                    DataCell(Text(TextosDeLosTelefonos.rutas(t.rutasAbiertas))),
                    DataCell(_Visto(t, ahora)),
                    DataCell(_boton(t, primero) ?? const SizedBox.shrink()),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _vehiculo(TelefonoDeDistribuidor t) => !t.vinculado
    ? TextosDeLosTelefonos.sinVehiculo
    : [?t.vehiculo, ?t.placa].join(' · ');

class _Aviso extends StatelessWidget {
  const _Aviso(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: DecoratedBox(
      key: claveDelAvisoDeTelefonos,
      decoration: BoxDecoration(
        color: Colores.ambarFondo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          texto,
          style: TextStyle(fontSize: 12, color: Colores.tinta),
        ),
      ),
    ),
  );
}

/// El nombre del teléfono con su etiqueta si está dado de baja.
class _Nombre extends StatelessWidget {
  const _Nombre(this.t);

  final TelefonoDeDistribuidor t;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        t.nombre ?? TextosDeLosTelefonos.sinNombre,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      if (!t.activo)
        Insignia(TextosDeLosTelefonos.deBaja, color: Colores.tintaSuave),
    ],
  );
}

/// «Visto hace X», con el aviso ámbar de «Dónde están» pasados [minutosSinSenalParaAvisar] (solo si el teléfono sigue en servicio).
class _Visto extends StatelessWidget {
  const _Visto(this.t, this.ahora);

  final TelefonoDeDistribuidor t;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    final d = t.vistoHace(ahora);
    final avisa =
        d != null &&
        t.vinculado &&
        t.activo &&
        d.inMinutes >= minutosSinSenalParaAvisar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          TextosDeLosTelefonos.visto(d),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (avisa)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: DecoratedBox(
              key: claveDelAvisoSinSenalTelefono(t.id),
              decoration: BoxDecoration(
                color: Colores.ambarFondo,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  TextosDeDondeEstan.sinSenal(minutosSinSenalParaAvisar),
                  style: TextStyle(fontSize: 12, color: Colores.tinta),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta(
    this.t, {
    required this.tema,
    required this.ahora,
    required this.conSucursal,
    required this.boton,
  });

  final TelefonoDeDistribuidor t;
  final ThemeData tema;
  final DateTime ahora;
  final bool conSucursal;
  final Widget? boton;

  @override
  Widget build(BuildContext context) => Card(
    key: claveDelTelefono(t.id),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Nombre(t),
          if (conSucursal && t.sucursal != null)
            Text(t.sucursal!, style: tema.textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(_vehiculo(t), style: tema.textTheme.bodyMedium),
          if (t.vinculado)
            Text(
              TextosDeLosTelefonos.vinculadoDesde(t.vinculadoAt),
              style: tema.textTheme.bodySmall,
            ),
          if (t.distribuidor != null)
            Text(t.distribuidor!, style: tema.textTheme.bodySmall),
          Text(
            TextosDeLosTelefonos.rutas(t.rutasAbiertas),
            style: tema.textTheme.bodySmall,
          ),
          _Visto(t, ahora),
          if (boton != null) ...[const SizedBox(height: 8), boton!],
        ],
      ),
    ),
  );
}
