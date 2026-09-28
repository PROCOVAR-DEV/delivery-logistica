import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/cargando.dart';
import '../../../nucleo/registro/registro.dart';
import '../../vehiculos/datos/vehiculo_api.dart' show estadoEnMantenimiento;
import '../datos/modelos.dart';
import '../estado/proveedores.dart';
import 'kit.dart';

/// Los gestos que no son arrastrar.
///
/// **Existen para el dedo.** Arrastrar una tarjeta de una punta a otra de un
/// telefono, con la mitad izquierda y las doce columnas en pantallas distintas,
/// no se puede hacer; asi que tocar la tarjeta abre «moverla a», que hace
/// exactamente lo mismo y llama al mismo sitio. En el escritorio estan las dos
/// maneras y cada cual usa la que quiera.
abstract final class AccionesTablero {
  /// Toca una tarjeta: a que columna va, o de vuelta a «sin colocar».
  static Future<void> moverTarjeta(
    BuildContext context,
    WidgetRef ref, {
    required TarjetaPedido pedido,
    required Tablero tablero,
    String? columnaActual,
    int? posicionActual,
  }) async {
    await mostrarCajon<void>(
      context: context,
      titulo: pedido.operationNumber ?? pedido.customerName,
      contenido: (contexto) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${pedido.customerName} · ${pesoBonito(pedido.weight)}'
            '${pedido.kmAlAlmacen.isFinite ? ' · ${kmBonito(pedido.kmAlAlmacen)}' : ''}',
            style: Theme.of(contexto).textTheme.bodySmall,
          ),
          // Lo que dejo de servir se dice tambien aqui, no sólo en la tarjeta:
          // es el momento en el que alguien esta decidiendo que hacer con el.
          for (final marca in pedido.marcas)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: insigniaDeMarca(marca),
              ),
            ),
          const Divider(height: 24),
          if (columnaActual != null) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.arrow_upward),
              title: const Text('Subir una posición'),
              enabled: (posicionActual ?? 1) > 1,
              onTap: () {
                Navigator.of(contexto).pop();
                hacer(
                  context,
                  ref,
                  () => ref
                      .read(tableroProvider.notifier)
                      .colocar(
                        pedidoId: pedido.pedidoId,
                        columnaId: columnaActual,
                        posicion: (posicionActual ?? 2) - 1,
                      ),
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.arrow_downward),
              title: const Text('Bajar una posición'),
              onTap: () {
                Navigator.of(contexto).pop();
                hacer(
                  context,
                  ref,
                  () => ref
                      .read(tableroProvider.notifier)
                      .colocar(
                        pedidoId: pedido.pedidoId,
                        columnaId: columnaActual,
                        posicion: (posicionActual ?? 0) + 1,
                      ),
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.undo),
              title: const Text('Devolver a sin colocar'),
              onTap: () {
                Navigator.of(contexto).pop();
                hacer(
                  context,
                  ref,
                  () => ref
                      .read(tableroProvider.notifier)
                      .quitar(pedido.pedidoId),
                );
              },
            ),
            const Divider(height: 24),
          ],
          for (final columna in tablero.columnas)
            if (columna.id != columnaActual)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.view_column_outlined),
                title: Text('Colocar en «${columna.nombre}»'),
                subtitle: Text(
                  '${columna.pedidos} pedidos · '
                  '${pesoBonito(columna.pesoKg)}',
                ),
                onTap: () {
                  Navigator.of(contexto).pop();
                  hacer(
                    context,
                    ref,
                    () => ref
                        .read(tableroProvider.notifier)
                        .colocar(
                          pedidoId: pedido.pedidoId,
                          columnaId: columna.id,
                        ),
                  );
                },
              ),
          if (tablero.columnas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Todavía no hay ninguna columna. Créala con el «+» del tablero '
                'y ponle el nombre de la zona.',
              ),
            ),
        ],
      ),
    );
  }

  /// El menu de la columna: renombrar, camion, vaciar, mover todo, borrar y
  /// armar la ruta.
  static Future<void> menuDeColumna(
    BuildContext context,
    WidgetRef ref, {
    required ColumnaTablero columna,
    required Tablero tablero,
  }) async {
    await mostrarCajon<void>(
      context: context,
      titulo: columna.nombre,
      contenido: (contexto) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Renombrar'),
            onTap: () async {
              Navigator.of(contexto).pop();
              final nombre = await _pedirNombre(context, columna.nombre);
              if (nombre == null || !context.mounted) return;
              await hacer(
                context,
                ref,
                () => ref
                    .read(tableroProvider.notifier)
                    .renombrar(columna.id, nombre),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.local_shipping_outlined),
            title: const Text('Camión previsto'),
            subtitle: Text(columna.vehiculoNombre ?? 'Sin elegir'),
            onTap: () {
              Navigator.of(contexto).pop();
              _elegirCamion(context, ref, columna);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.layers_clear_outlined),
            title: const Text('Vaciar'),
            subtitle: const Text('Las tarjetas vuelven a «sin colocar»'),
            onTap: () {
              Navigator.of(contexto).pop();
              hacer(
                context,
                ref,
                () => ref.read(tableroProvider.notifier).vaciar(columna.id),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.drive_file_move_outlined),
            title: const Text('Mover todo a otra columna'),
            onTap: () {
              Navigator.of(contexto).pop();
              _elegirDestino(
                context,
                ref,
                columna: columna,
                tablero: tablero,
                borrarDespues: false,
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline),
            title: const Text('Borrar la columna'),
            onTap: () {
              Navigator.of(contexto).pop();
              _borrar(context, ref, columna: columna, tablero: tablero);
            },
          ),
          const Divider(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.route_outlined),
            label: const Text('Armar la ruta de esta zona'),
            onPressed: () {
              Navigator.of(contexto).pop();
              hacer(
                context,
                ref,
                () => ref.read(tableroProvider.notifier).armarRuta(columna.id),
                exito:
                    'Ruta armada con lo que se puede repartir de '
                    '«${columna.nombre}».',
              );
            },
          ),
        ],
      ),
    );
  }

  /// Crear una columna. El nombre lo pone la persona: las zonas son suyas.
  static Future<void> crearColumna(BuildContext context, WidgetRef ref) async {
    final nombre = await _pedirNombre(context, '');
    if (nombre == null || !context.mounted) return;
    await hacer(
      context,
      ref,
      () => ref.read(tableroProvider.notifier).crearColumna(nombre),
    );
  }

  /// EL CAJÓN DEL «CAMIÓN PREVISTO».
  ///
  /// ## Lo que pasaba: se cerraba el menú y NO SE ABRÍA NADA — 28/09/2026
  ///
  /// Jose, en un SM-A165M, con un vehículo dado de alta en la sucursal
  /// («Vehículos 0 / 1»): tocar «Camión previsto / Sin elegir» cerraba la hoja
  /// de opciones de la zona y ahí se acababa. Ni selector, ni rueda, ni aviso.
  /// Dos veces seguidas. Y la consecuencia no es cosmética: la ruta se arma y
  /// se inicia **sin vehículo**, así que después el coste por km no se puede
  /// calcular y nadie sabe por qué.
  ///
  /// No era ni el teléfono ni un cajón abriéndose encima de otro —se reprodujo
  /// igual a 1400 px—, era esta línea:
  ///
  ///     final camiones = await ref.read(camionesProvider.future);
  ///
  /// **Ese `await` no termina nunca.** `camionesProvider` es un `StreamProvider`
  /// y aquí no lo estaba mirando nadie: un `ref.read` suelto lo crea, el
  /// proveedor se apaga en cuanto acaba la microtarea —los proveedores se
  /// apagan solos cuando nadie los escucha— y el `async*` de dentro no llega ni
  /// a soltar su primer valor. El `Future` se queda colgado, y con él toda esta
  /// función: el `pop` del menú ya se había hecho y el `mostrarCajon` de aquí
  /// abajo no se llegaba a ejecutar. Medido en seco: con un `listen` puesto
  /// delante devuelve `[F-350]` al instante; sin él, tres segundos de espera y
  /// nada.
  ///
  /// El arreglo es **mirar la flota en vez de pedirla antes**: el cajón se abre
  /// SIEMPRE y en el acto, y dentro un `Consumer` hace `ref.watch`, que sí es
  /// alguien escuchando. De paso se recupera lo que el 17/09/2026 se vino a
  /// arreglar y este `read` deshacía sin querer: la lista es un `Stream`
  /// precisamente para que los camiones que bajan dos segundos después
  /// aparezcan solos (`CLAUDE.md` §3-ter). Con la base en memoria de la web
  /// —que nace vacía en cada carga— ése es el caso de siempre, no el raro.
  ///
  /// ## Y la pieza es la del kit, no una nueva
  ///
  /// `lib/diseno/selector.dart` acaba de resolver su caso del teléfono abriendo
  /// un `Cajon` por debajo de 1024 px. Aquí ya se abría un `Cajon` —el mismo,
  /// por `mostrarCajon`— en los dos tamaños, que es la excepción aprobada de
  /// delivery del 05/09/2026. Lo que faltaba no era la pieza: era llegar a
  /// abrirla.
  static Future<void> _elegirCamion(
    BuildContext context,
    WidgetRef ref,
    ColumnaTablero columna,
  ) => mostrarCajon<void>(
    context: context,
    titulo: 'Camión previsto para «${columna.nombre}»',
    contenido: (contexto) => _CamionesDeLaZona(
      columna: columna,
      deLaPantalla: context,
      refDeLaPantalla: ref,
    ),
  );

  static Future<void> _elegirDestino(
    BuildContext context,
    WidgetRef ref, {
    required ColumnaTablero columna,
    required Tablero tablero,
    required bool borrarDespues,
  }) async {
    final otras = tablero.columnas.where((c) => c.id != columna.id).toList();
    if (otras.isEmpty) {
      _decir(context, 'No hay otra columna a la que mandarlos.');
      return;
    }
    await mostrarCajon<void>(
      context: context,
      titulo: 'Mandar lo de «${columna.nombre}» a…',
      contenido: (contexto) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final destino in otras)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.view_column_outlined),
              title: Text(destino.nombre),
              subtitle: Text('${destino.pedidos} pedidos'),
              onTap: () {
                Navigator.of(contexto).pop();
                hacer(context, ref, () async {
                  final mando = ref.read(tableroProvider.notifier);
                  if (borrarDespues) {
                    await mando.borrarColumna(
                      columna.id,
                      destinoId: destino.id,
                    );
                  } else {
                    await mando.moverTodo(columna.id, destino.id);
                  }
                });
              },
            ),
        ],
      ),
    );
  }

  /// Borrar.
  ///
  /// Con pedidos dentro **la base se niega**, y lo que se hace no es insistir:
  /// se pregunta que pasa con lo de dentro. Deshacer el trabajo de alguien en
  /// silencio es la unica cosa que este tablero no puede hacer (§7.6).
  static Future<void> _borrar(
    BuildContext context,
    WidgetRef ref, {
    required ColumnaTablero columna,
    required Tablero tablero,
  }) async {
    // UNA COLUMNA VACÍA TAMBIÉN SE PREGUNTA ANTES DE BORRARLA.
    //
    // Antes se borraba en seco: se tocaba «Borrar la columna» y desaparecía sin
    // una palabra. Con pedidos dentro sí preguntaba —qué hacer con ellos—, o
    // sea que el aviso existía sólo cuando había algo que perder. Pero una zona
    // es trabajo: alguien decidió cómo se parte el territorio de su sucursal y
    // le puso nombre, y ese nombre está en los enlaces, en las rutas armadas
    // desde ella y en la cabeza de quien reparte. Rehacerla no es gratis.
    //
    // Jose, 25/09/2026, viéndolo desaparecer de un toque:
    //
    //     «sacame notificaciones emergentes para esto, no me pongas eso asi
    //      borrar por borrar»
    //
    // Se pregunta en un CAJÓN y no en una ventana modal, que es la regla de la
    // casa desde el 05/09/2026. Y el botón de borrar va en rojo y nombra la
    // zona: «Sí, borrar X» dice qué se va; «Aceptar» no dice nada.
    if (columna.pedidos == 0) {
      final seguro = await mostrarCajon<bool>(
        context: context,
        titulo: 'Borrar «${columna.nombre}»',
        contenido: (contexto) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'La zona se va del tablero. No hay ningún pedido dentro, así '
              'que no se pierde trabajo del día, pero la zona hay que volver '
              'a crearla a mano con su nombre.',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: Text('Sí, borrar «${columna.nombre}»'),
              style: FilledButton.styleFrom(backgroundColor: Colores.rojo),
              onPressed: () => Navigator.of(contexto).pop(true),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(contexto).pop(false),
              child: const Text('No, dejarla'),
            ),
          ],
        ),
      );
      if (seguro != true || !context.mounted) return;
      await hacer(
        context,
        ref,
        () => ref.read(tableroProvider.notifier).borrarColumna(columna.id),
      );
      return;
    }
    await mostrarCajon<void>(
      context: context,
      titulo: '«${columna.nombre}» tiene ${columna.pedidos} pedidos puestos',
      contenido: (contexto) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('¿Qué se hace con ellos?'),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.undo),
            title: const Text('Devolverlos a «sin colocar» y borrar'),
            onTap: () {
              Navigator.of(contexto).pop();
              hacer(
                context,
                ref,
                () => ref
                    .read(tableroProvider.notifier)
                    .borrarColumna(columna.id, vaciar: true),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.drive_file_move_outlined),
            title: const Text('Mandarlos a otra columna y borrar'),
            onTap: () {
              Navigator.of(contexto).pop();
              _elegirDestino(
                context,
                ref,
                columna: columna,
                tablero: tablero,
                borrarDespues: true,
              );
            },
          ),
        ],
      ),
    );
  }

  static Future<String?> _pedirNombre(
    BuildContext context,
    String inicial,
  ) async {
    final control = TextEditingController(text: inicial);
    final nombre = await mostrarCajon<String>(
      context: context,
      titulo: inicial.isEmpty ? 'Nueva columna' : 'Renombrar «$inicial»',
      contenido: (contexto) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: control,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nombre de la zona',
              hintText: 'Centro, Vista Alegre, Carretera…',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (texto) => Navigator.of(contexto).pop(texto),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(contexto).pop(control.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    control.dispose();
    return (nombre == null || nombre.trim().isEmpty) ? null : nombre.trim();
  }

  /// LO QUE SE DICE CUANDO EL APARATO NO PUEDE GUARDAR.
  ///
  /// No es un rechazo: no hay nadie al otro lado diciendo que no. Es SQLite
  /// contestando `SQLITE_FULL` —«database or disk is full»— o un
  /// `attempt to write a readonly database`. Un teléfono de repartidor lleva el
  /// día dentro y un paquete de mapa de 100 MB al lado; quedarse sin sitio a
  /// media mañana no es el caso raro.
  ///
  /// Se nombra el aparato y se dice QUÉ HACER. «Ha ocurrido un error» no le
  /// sirve a nadie en el patio de un almacén.
  static const noSePudoGuardar =
      'No se pudo guardar en este aparato, así que este movimiento NO se ha '
      'hecho. Suele ser que no queda espacio: libera sitio en el teléfono y '
      'vuelve a intentarlo.';

  /// Hace algo y **ensena el motivo literal si sale que no**.
  ///
  /// Sin envolver en «Ha ocurrido un error»: ««Centro» tiene 8 pedidos puestos»
  /// le dice a alguien que hacer; «Ha ocurrido un error», no.
  ///
  /// ## Y ATRAPA TAMBIEN LO QUE NO ES UN RECHAZO — 24/09/2026
  ///
  /// Antes esto era `on RechazoDelTablero` y nada mas, o sea que solo sabia
  /// contar los «no» del servidor. Un `SqliteException` —el disco lleno, la
  /// copia sin permisos de escritura— se escapaba entero: se tocaba «Colocar en
  /// «Centro»», la tarjeta se quedaba donde estaba y **no se decia una
  /// palabra**. En un test sale como excepcion no capturada; en la APK no sale
  /// en ningun sitio.
  ///
  /// Es el §4 de la casa: si algo falla, la pantalla no se queda verde. Un
  /// gesto que se cree hecho y no esta en ninguna parte es trabajo perdido, y el
  /// repartidor sigue la jornada creyendo que la zona quedo armada.
  static Future<void> hacer(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() que, {
    String? exito,
  }) async {
    try {
      await que();
      if (exito != null && context.mounted) _decir(context, exito);
    } on RechazoDelTablero catch (e) {
      if (!context.mounted) return;
      _decir(context, [e.mensaje, ...e.detalles].join('\n'), problema: true);
    } on Object catch (e, pila) {
      // Queda en el registro con el error de verdad, que es lo unico con lo que
      // se puede diagnosticar despues; en pantalla va el texto de persona.
      Registro.fallo('tablero: el gesto no se pudo guardar en el aparato', e, pila);
      if (!context.mounted) return;
      _decir(context, noSePudoGuardar, problema: true);
    }
  }

  static void _decir(
    BuildContext context,
    String texto, {
    bool problema = false,
  }) {
    final mensajero = ScaffoldMessenger.maybeOf(context);
    if (mensajero == null) return;
    mensajero
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: problema ? ColoresTablero.rojo : null,
          duration: Duration(seconds: problema ? 6 : 3),
        ),
      );
  }
}

/// LA FLOTA DE LA SUCURSAL, DENTRO DEL CAJÓN Y **MIRADA**, NO PEDIDA.
///
/// El porqué entero está en `AccionesTablero._elegirCamion`. En una frase: un
/// `ref.read(camionesProvider.future)` antes de abrir el cajón no volvía nunca
/// y dejaba el gesto muerto a media escalera. Aquí se hace `ref.watch`, que es
/// alguien escuchando de verdad: el proveedor se mantiene vivo, suelta su
/// primer valor y además repinta esta lista cuando la flota baja un segundo
/// más tarde (§3-ter).
class _CamionesDeLaZona extends ConsumerWidget {
  const _CamionesDeLaZona({
    required this.columna,
    required this.deLaPantalla,
    required this.refDeLaPantalla,
  });

  final ColumnaTablero columna;

  /// El contexto de la PANTALLA, no el del cajón.
  ///
  /// El cajón se cierra antes de guardar, así que su contexto ya está muerto
  /// cuando hay que decir algo: el motivo de un «no se pudo guardar» saldría a
  /// un `ScaffoldMessenger` que ya no existe y **no lo leería nadie**, que es
  /// exactamente el §4 de la casa al revés.
  final BuildContext deLaPantalla;

  /// Y su `ref`, por lo mismo: el del `Consumer` de aquí se va con el cajón.
  final WidgetRef refDeLaPantalla;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flota = ref.watch(camionesProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // «Sin camión» va SIEMPRE y va el primero, pase lo que pase con la
        // flota: quitar el camión que se puso mal es lo único que se puede
        // hacer aquí sin depender de que baje nada.
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.not_interested),
          title: const Text('Sin camión'),
          selected: columna.vehiculoId == null,
          onTap: () => _poner(context, null),
        ),
        const Divider(height: 24),
        ...switch (flota) {
          // Una lista vacía NO es «no hay camiones» a secas: se dice qué se
          // rompe sin uno, que es el §4 —una colección que no bajó se dice, y
          // se dice qué se rompe sin ella—. Sin camión previsto la ruta se
          // arma igual, y el coste por km de esa ruta no sale.
          AsyncData(:final value) when value.isEmpty => [
            const _NadaQueElegir(
              'Esta sucursal no tiene ningún vehículo en este aparato.',
              'Se puede armar la ruta igual, pero sin camión no hay capacidad '
                  'contra la que medir el peso ni coste por km que calcular. '
                  'Los vehículos se dan de alta en Flota y bajan con la '
                  'siguiente sincronización.',
            ),
          ],
          AsyncData(:final value) => [
            // EL CAMION DEL TALLER SALE, Y SALE MARCADO — 28/09/2026.
            //
            // Se OFRECE igual, y es la misma decisión que el paso 3 del
            // asistente de Rutas: aviso, no bloqueo. Un camión en el taller
            // tiene su capacidad y su costo por km, así que el peso de la zona y
            // el coste de su ruta siguen teniendo contra qué medirse — lo que
            // falta es el camión, no el dato. Eso lo separa de la zona SIN
            // camión, que sí se bloquea desde hoy (`tablero/datos/
            // repositorio.dart`, `armarRuta`): allí las dos cuentas se quedan
            // sin denominador y la ruta sale con un peso y un importe que no
            // significan nada.
            //
            // Y bloquear con `maintenance` sería bloquear con un campo que pone
            // una persona y tiene que quitar otra. En producción hay sucursales
            // con UN camión: uno que alguien se olvidó de sacar del taller
            // dejaría esa sucursal sin poder armar ni una zona, y el arreglo
            // está en otra pantalla. Es el caso de los 657 de 686 domicilios sin
            // costo del `CLAUDE.md` §2, con otro nombre.
            //
            // El aviso va en el subtítulo, que es donde ya están la capacidad y
            // la placa: en mayúsculas porque es lo único de esta lista que hace
            // que uno elija otro.
            for (final camion in value)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  camion.status == estadoEnMantenimiento
                      ? Icons.build_outlined
                      : Icons.local_shipping_outlined,
                  color: camion.status == estadoEnMantenimiento
                      ? Colores.ambar
                      : null,
                ),
                title: Text(camion.name),
                subtitle: Text(
                  '${pesoBonito(camion.capacity)}'
                  '${camion.plate == null ? '' : ' · ${camion.plate}'}'
                  '${camion.status == estadoEnMantenimiento ? ' · EN EL TALLER' : ''}',
                  style: camion.status == estadoEnMantenimiento
                      ? TextStyle(color: Colores.ambar)
                      : null,
                ),
                selected: columna.vehiculoId == camion.id,
                onTap: () => _poner(context, camion.id),
              ),
          ],
          // El motivo literal, no «ha ocurrido un error»: es lo único con lo
          // que alguien puede decidir si vuelve a intentarlo o llama.
          AsyncError(:final error) => [
            _NadaQueElegir(
              'No se pudo leer la flota de esta sucursal.',
              '$error',
            ),
          ],
          // La rueda SE VE, y ésa es media reparación: antes, mientras se
          // esperaba, no había ni cajón. Un gesto que no enseña nada se lee
          // como un gesto que no funciona, y se vuelve a pulsar.
          _ => [const Cargando('Buscando los camiones de la sucursal…')],
        },
      ],
    );
  }

  /// Cierra el cajón y guarda. En este orden y no al revés: el cajón tapa media
  /// pantalla, y el aviso de «no se pudo guardar» sale por debajo.
  void _poner(BuildContext contextoDelCajon, String? vehiculoId) {
    Navigator.of(contextoDelCajon).pop();
    unawaited(
      AccionesTablero.hacer(
        deLaPantalla,
        refDeLaPantalla,
        () => refDeLaPantalla
            .read(tableroProvider.notifier)
            .elegirCamion(columna.id, vehiculoId),
      ),
    );
  }
}

/// Lo que se pinta cuando no hay de dónde elegir: el titular y **por qué
/// importa**. Un cajón vacío con un «Sin camión» suelto se lee como que la
/// pantalla está rota.
class _NadaQueElegir extends StatelessWidget {
  const _NadaQueElegir(this.titular, this.porQue);

  final String titular;
  final String porQue;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titular,
            style: tema.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            porQue,
            style: tema.textTheme.bodySmall?.copyWith(
              color: tema.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
