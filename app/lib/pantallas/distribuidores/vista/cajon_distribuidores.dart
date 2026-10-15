import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/cajon.dart';
import '../../../diseno/preguntar_antes_de_borrar.dart';
import '../../../diseno/tema.dart';
import '../../../diseno/colores.dart';
import '../../../nucleo/red/fallos.dart';
import '../../../nucleo/registro/registro.dart';
import '../datos/repositorio_distribuidores.dart';
import '../estado/proveedores_distribuidores.dart';

/// Abre el cajon de «Distribuidores». Se puede abrir desde donde haga falta: la
/// pantalla de Vehiculos (donde vive junto a «Tipos de vehiculo») y el selector de
/// «Nueva ruta», cuando la sucursal no tiene ninguno todavia.
Future<void> abrirCajonDeDistribuidores(BuildContext contexto) =>
    abrirPanel<void>(contexto, (_) => const CajonDeDistribuidores());

/// El cajon `md` de «Distribuidores» (issue 7 de Amado, 14/10/2026): crear,
/// renombrar y retirar a quienes reparten en esta sucursal.
///
/// ## Por que en el cajon de Vehiculos y no una pantalla en el menu
///
/// Es una lista corta que se toca de higos a brevas, de la misma familia que los
/// tipos de vehiculo y que la flota: quien da de alta un triciclo es quien da de
/// alta a su chofer. Una pantalla nueva pedia entrada de menu, ruta, registro, guia
/// y sus pruebas de navegacion para un nombre y un interruptor. Y como es un cajon
/// suelto (no va colgado de la pantalla), tambien se abre desde el selector de
/// «Nueva ruta».
///
/// ## Cada toque se guarda en el acto, y la pantalla dice lo que paso
///
/// A diferencia de «Tipos de vehiculo», que edita la lista entera y la manda al
/// pulsar «Guardar» (de ahi su `GuardadoAMedias`), aqui cada gesto es UNA peticion:
/// agregar, renombrar, retirar, activar, borrar. No hay «a medias» posible: lo que
/// ya salio en pantalla como hecho esta hecho, y lo que falla se dice con su motivo
/// LITERAL y se vuelve a leer la lista del servidor para que se vea lo que hay.
///
/// ## Y la red que se cae a mitad se reconcilia, no se adivina
///
/// Un `FalloDeRed` no dice si el servidor llego a escribir (el corte puede estar
/// antes o DESPUES). Antes de contestar «no se guardo», se vuelve a leer la lista y
/// se compara con lo que se queria: si ya esta, se dice «ya esta guardado» (la
/// respuesta se perdio por el camino); si no esta, no; y si ni leer se puede, se
/// dice que NO SE SABE. Lo que no se hace es dar un «no se guardo nada» que puede
/// ser mentira, que es el fallo que costo la edicion de tipos.
///
/// **Sin conexion el cajon lo dice y no finge**: lo bajado en el aparato sigue
/// sirviendo para elegir al crear una ruta, pero esta lista no se toca.
class CajonDeDistribuidores extends ConsumerStatefulWidget {
  const CajonDeDistribuidores({super.key});

  /// Para que las pruebas encuentren cada pieza sin depender del texto.
  static const claveDelCampoNuevo = ValueKey('distribuidor-nuevo');
  static const claveDelAviso = ValueKey('distribuidores-aviso');
  static Key claveDeLaFila(String id) => ValueKey('distribuidor-$id');
  static Key claveDeRetirar(String id) => ValueKey('distribuidor-retirar-$id');
  static Key claveDeBorrar(String id) => ValueKey('distribuidor-borrar-$id');
  static Key claveDeRenombrar(String id) =>
      ValueKey('distribuidor-renombrar-$id');

  @override
  ConsumerState<CajonDeDistribuidores> createState() =>
      _CajonDeDistribuidoresState();
}

class _Aviso {
  const _Aviso(this.texto, {this.esFallo = false});
  final String texto;
  final bool esFallo;
}

class _CajonDeDistribuidoresState
    extends ConsumerState<CajonDeDistribuidores> {
  final _nuevo = TextEditingController();
  final _renombrando = TextEditingController();

  /// Cual se esta renombrando, si alguno.
  String? _editando;

  /// Las acciones que van de camino. Una sola de cada a la vez: un doble toque no
  /// puede dar de alta a la misma persona dos veces ni borrar dos veces.
  final _enVuelo = <String>{};

  _Aviso? _aviso;

  @override
  void dispose() {
    _nuevo.dispose();
    _renombrando.dispose();
    super.dispose();
  }

  RepositorioDistribuidores get _repo =>
      ref.read(repositorioDistribuidoresProvider);

  /// La puerta de las escrituras. [verificar] contesta, sobre la lista que hay
  /// AHORA en el servidor, «esto que queria ya esta hecho»; solo se usa cuando la
  /// red se cae sin saber si la peticion llego.
  Future<void> _hacer(
    String clave,
    Future<String> Function() accion, {
    required bool Function(List<DistribuidorDelServidor> ahora) verificar,
    required String yaEstaba,
  }) async {
    if (!_enVuelo.add(clave)) return;
    setState(() => _aviso = null);
    _Aviso? resultado;
    try {
      resultado = _Aviso(await accion());
    } on FalloDeRed {
      resultado = await _alCaerseLaRed(verificar, yaEstaba);
    } on Rechazo catch (e) {
      // El servidor entendio y dijo que no: su frase, LITERAL.
      resultado = _Aviso(e.mensaje, esFallo: true);
    } on SesionMuerta catch (e) {
      resultado = _Aviso(e.mensaje, esFallo: true);
    } on Object catch (e, pila) {
      // Lo que no se sabe nombrar tampoco se calla: el boton se pulso y alguien
      // tiene que enterarse de que no paso nada.
      Registro.fallo('distribuidores: la accion fallo sin motivo conocido', e, pila);
      resultado = const _Aviso(
        'No se pudo guardar y no se sabe por qué: el servidor contestó algo que '
        'esta pantalla no entiende. Vuelve a intentarlo y, si sigue igual, avisa '
        'a la oficina.',
        esFallo: true,
      );
    } finally {
      _enVuelo.remove(clave);
    }
    // Se vuelve a leer lo que hay, salga como salga.
    ref.invalidate(distribuidoresDelServidorProvider);
    if (!mounted) return;
    setState(() => _aviso = resultado);
  }

  Future<_Aviso> _alCaerseLaRed(
    bool Function(List<DistribuidorDelServidor>) verificar,
    String yaEstaba,
  ) async {
    try {
      final ahora = await _repo.listar();
      if (verificar(ahora)) return _Aviso(yaEstaba);
      return const _Aviso(
        'Sin conexión con el servidor: NO se guardó. Lo que ves abajo es lo que '
        'hay guardado.',
        esFallo: true,
      );
    } on Object {
      return const _Aviso(
        'Se cortó la conexión y no se sabe si se guardó. Cuando vuelva la '
        'señal, mira la lista antes de repetirlo.',
        esFallo: true,
      );
    }
  }

  Future<void> _agregar() async {
    final nombre = _nuevo.text.trim();
    if (nombre.isEmpty) return;
    await _hacer(
      'agregar:${nombre.toLowerCase()}',
      () async {
        await _repo.crear(nombre);
        _nuevo.clear();
        return 'Distribuidor «$nombre» agregado.';
      },
      verificar: (ahora) => ahora.any(
        (d) => d.nombre.toLowerCase() == nombre.toLowerCase(),
      ),
      yaEstaba: '«$nombre» ya está guardado: la respuesta se perdió por el camino.',
    );
  }

  Future<void> _renombrar(DistribuidorDelServidor d) async {
    final nombre = _renombrando.text.trim();
    if (nombre.isEmpty || nombre == d.nombre) {
      setState(() => _editando = null);
      return;
    }
    await _hacer(
      'renombrar:${d.id}',
      () async {
        await _repo.cambiar(d.id, nombre: nombre);
        if (mounted) setState(() => _editando = null);
        return '«${d.nombre}» ahora es «$nombre».';
      },
      verificar: (ahora) => ahora.any((x) => x.id == d.id && x.nombre == nombre),
      yaEstaba: '«$nombre» ya está guardado: la respuesta se perdió por el camino.',
    );
  }

  Future<void> _activar(DistribuidorDelServidor d, {required bool activo}) =>
      _hacer(
        'activo:${d.id}',
        () async {
          await _repo.cambiar(d.id, activo: activo);
          return activo
              ? '«${d.nombre}» vuelve a estar en activo.'
              : '«${d.nombre}» está retirado: ya no se ofrece en rutas nuevas.';
        },
        verificar: (ahora) => ahora.any((x) => x.id == d.id && x.activo == activo),
        yaEstaba: '«${d.nombre}» ya está '
            '${activo ? 'en activo' : 'retirado'}: la respuesta se perdió por el camino.',
      );

  Future<void> _borrar(DistribuidorDelServidor d) async {
    final seguro = await preguntarAntesDeBorrar(
      context,
      queSeVa: d.nombre,
      loQuePasa:
          'Ninguna ruta lo usa, así que se borra de verdad y no se puede '
          'deshacer. Si prefieres que no se ofrezca pero conservarlo, retíralo.',
      noLoBorres: 'No, dejarlo',
    );
    if (!seguro || !mounted) return;
    await _hacer(
      'borrar:${d.id}',
      () async {
        final r = await _repo.quitar(d.id);
        return r == ResultadoDeQuitar.retirado
            // Una ruta lo uso entre que se abrio el cajon y ahora: el servidor lo
            // RETIRA en vez de borrarlo, y la pantalla tiene que decirlo.
            ? '«${d.nombre}» lo usa alguna ruta, así que no se borró: quedó retirado.'
            : '«${d.nombre}» borrado.';
      },
      verificar: (ahora) =>
          !ahora.any((x) => x.id == d.id) ||
          ahora.any((x) => x.id == d.id && !x.activo),
      yaEstaba: '«${d.nombre}» ya no está en la lista: la respuesta se perdió por el camino.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = ref.watch(distribuidoresDelServidorProvider);
    final hayFallo = lista.hasError;
    final tema = Theme.of(context);
    return Cajon(
      titulo: 'Distribuidores',
      subtitulo: 'Quién reparte, por sucursal',
      ancho: AnchoCajon.md,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'El distribuidor es la persona responsable de la entrega y de '
              'devolver las facturas entregadas: el chofer mismo si va en '
              'triciclo, un empleado de Procovar si el vehículo es rentado. Se '
              'elige al crear la ruta.',
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_aviso case final aviso?) ...[
              Container(
                key: CajonDeDistribuidores.claveDelAviso,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: aviso.esFallo ? Colores.rojo : Colores.verde,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  aviso.texto,
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: aviso.esFallo ? Colores.rojo : Colores.verde,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: CajonDeDistribuidores.claveDelCampoNuevo,
                    controller: _nuevo,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del distribuidor',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _agregar(),
                  ),
                ),
                const SizedBox(width: 8),
                BotonPrincipal(
                  icono: Icons.person_add_alt_outlined,
                  texto: 'Agregar',
                  alPulsar: _enVuelo.any((c) => c.startsWith('agregar:'))
                      ? null
                      : _agregar,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // El valor y el fallo se miran POR SEPARADO (`AsyncValue` los puede tener a la
            // vez): Riverpod reintenta solo un `FutureProvider` que falla, y mientras
            // reintenta el estado es «cargando» CON el error dentro. Un `switch` sobre
            // `AsyncError` no lo veria nunca y la pantalla se quedaria en «Cargando».
            if (lista.value case final lista?) ...[
              // Si la ultima lectura fallo pero hay una lista de antes, se ensena y se
              // DICE que puede estar vieja: callarlo la haria pasar por la de ahora.
              if (hayFallo)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'No se pudo actualizar la lista: puede estar desfasada.',
                    style: tema.textTheme.bodySmall?.copyWith(color: Colores.ambar),
                  ),
                ),
              if (lista.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Esta sucursal no tiene distribuidores. Agrega el primero '
                    'arriba: sin él la ruta se arma igual, pero no dice quién la '
                    'reparte.',
                  ),
                )
              else
                _Lista(
                  distribuidores: lista,
                  editando: _editando,
                  controlDelNombre: _renombrando,
                  enVuelo: _enVuelo,
                  alEditar: (d) => setState(() {
                    _editando = d.id;
                    _renombrando.text = d.nombre;
                  }),
                  alCancelarEdicion: () => setState(() => _editando = null),
                  alGuardarNombre: _renombrar,
                  alRetirar: (d) => _activar(d, activo: false),
                  alActivar: (d) => _activar(d, activo: true),
                  alBorrar: _borrar,
                ),
            ] else if (lista.error case final error?)
              _NoSeLeyo(
                error: error,
                alReintentar: () =>
                    ref.invalidate(distribuidoresDelServidorProvider),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Cargando distribuidores...')),
              ),
          ],
        ),
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({
    required this.distribuidores,
    required this.editando,
    required this.controlDelNombre,
    required this.enVuelo,
    required this.alEditar,
    required this.alCancelarEdicion,
    required this.alGuardarNombre,
    required this.alRetirar,
    required this.alActivar,
    required this.alBorrar,
  });

  final List<DistribuidorDelServidor> distribuidores;
  final String? editando;
  final TextEditingController controlDelNombre;
  final Set<String> enVuelo;
  final ValueChanged<DistribuidorDelServidor> alEditar;
  final VoidCallback alCancelarEdicion;
  final ValueChanged<DistribuidorDelServidor> alGuardarNombre;
  final ValueChanged<DistribuidorDelServidor> alRetirar;
  final ValueChanged<DistribuidorDelServidor> alActivar;
  final ValueChanged<DistribuidorDelServidor> alBorrar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    // La sucursal de cada fila solo se escribe cuando hay mas de una en la lista
    // (quien ve las ocho): con una sola es ruido.
    final variasSucursales =
        distribuidores.map((d) => d.sucursalId).toSet().length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final d in distribuidores)
          Padding(
            key: CajonDeDistribuidores.claveDeLaFila(d.id),
            padding: const EdgeInsets.only(bottom: 4),
            child: editando == d.id
                ? Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controlDelNombre,
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => alGuardarNombre(d),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Guardar el nombre',
                        icon: const Icon(Icons.check),
                        onPressed: () => alGuardarNombre(d),
                      ),
                      IconButton(
                        tooltip: 'Cancelar',
                        icon: const Icon(Icons.close),
                        onPressed: alCancelarEdicion,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(
                        d.activo ? Icons.badge_outlined : Icons.person_off_outlined,
                        size: 18,
                        color: d.activo ? Colores.gris : Colores.ambar,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.nombre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tema.textTheme.bodyMedium?.copyWith(
                                color: d.activo ? null : Colores.gris,
                              ),
                            ),
                            Text(
                              [
                                if (!d.activo) 'Retirado',
                                if (d.rutas > 0)
                                  d.rutas == 1 ? '1 ruta' : '${d.rutas} rutas',
                                if (variasSucursales && d.sucursal != null)
                                  d.sucursal!,
                              ].join(' · '),
                              style: tema.textTheme.bodySmall?.copyWith(
                                color: Colores.gris,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: CajonDeDistribuidores.claveDeRenombrar(d.id),
                        tooltip: 'Renombrar',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => alEditar(d),
                      ),
                      IconButton(
                        key: CajonDeDistribuidores.claveDeRetirar(d.id),
                        tooltip: d.activo ? 'Retirar' : 'Volver a activar',
                        icon: Icon(
                          d.activo
                              ? Icons.person_off_outlined
                              : Icons.person_add_alt_1_outlined,
                        ),
                        onPressed: enVuelo.contains('activo:${d.id}')
                            ? null
                            : () => d.activo ? alRetirar(d) : alActivar(d),
                      ),
                      // BORRAR SOLO SE OFRECE AL QUE NINGUNA RUTA USA. Con rutas, lo
                      // unico que se puede hacer es retirarlo (el servidor lo hace
                      // igual aunque lleguen a pedir el borrado): borrarlo dejaria
                      // la ruta sin decir quien la reparte.
                      if (d.rutas == 0)
                        IconButton(
                          key: CajonDeDistribuidores.claveDeBorrar(d.id),
                          tooltip: 'Borrar',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: enVuelo.contains('borrar:${d.id}')
                              ? null
                              : () => alBorrar(d),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }
}

/// La lista no se pudo leer. Dice QUE se rompe y que SI sigue sirviendo.
class _NoSeLeyo extends StatelessWidget {
  const _NoSeLeyo({required this.error, required this.alReintentar});

  final Object error;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    final sinRed = error is FalloDeRed;
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sinRed
              ? 'Sin conexión con el servidor. Los distribuidores se mantienen '
                    'con conexión.'
              : 'No se pudo leer la lista: ${error is FalloApi ? (error as FalloApi).mensaje : error}',
          style: tema.textTheme.bodyMedium?.copyWith(color: Colores.rojo),
        ),
        const SizedBox(height: 4),
        Text(
          'Lo que este aparato ya tiene bajado se sigue pudiendo elegir al '
          'crear una ruta; lo que no se puede es agregar, renombrar ni retirar '
          'hasta que vuelva la señal.',
          style: tema.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: alReintentar,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      ],
    );
  }
}
