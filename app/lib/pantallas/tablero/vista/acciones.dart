import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../diseno/cargando.dart';
import '../../../diseno/tema.dart' show BotonDestructivo, BotonPrincipal;
import '../../../nucleo/registro/registro.dart';
import '../../../nucleo/texto_de_fuera.dart' show sinLaComillaDeExcel;
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../../pedidos/datos/formato.dart' show cantidad;
import '../../rutas/datos/repositorio_rutas.dart' show PestanaRutas;
import '../../rutas/estado/proveedores_rutas.dart'
    show pestanaRutasProvider, rutaElegidaProvider;
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
          // EL DETALLE DEL PEDIDO, Y NO SÓLO SU NOMBRE — 28/09/2026.
          //
          // Aquí había un renglón: «cliente · peso · km». Jose: «ahi en tablero
          // q cuando le den para mover en ves de solo decir q lo vamos a mover
          // q me salga el detalle de el pedido ok».
          //
          // Tiene razón por lo que es este cajón: es el instante en el que
          // alguien decide A QUÉ ZONA va ese bulto, y para decidirlo hace falta
          // saber qué bulto es — dónde va, quién lo vende, qué lleva dentro.
          //
          // Sigue siendo CORTO a propósito. Mover es un gesto rápido que se
          // hace muchas veces seguidas, así que el detalle no puede obligar a
          // desplazarse antes de poder elegir la zona: son dos bloques de datos
          // y la lista de artículos acotada, no la ficha entera de Pedidos.
          _DetalleDelPedido(pedido: pedido),
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
            ControlSenalado(
              nombre: Senalado.tableroSubirUnaPosicion,
              child: ListTile(
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
            ControlSenalado(
              nombre: Senalado.tableroDevolverASinColocar,
              child: ListTile(
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
            ),
            const Divider(height: 24),
          ],
          for (final (cual, columna) in tablero.columnas.indexed)
            if (columna.id != columnaActual)
              // Sólo la primera se deja senalar: hay una fila por zona.
              ControlSenalado(
                nombre: Senalado.tableroColocarEnLaZona,
                senalable: cual == 0,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.view_column_outlined),
                  title: Text('Colocar en «${columna.nombre}»'),
                  subtitle: Text(
                    '${columna.pedidos} '
                    '${columna.pedidos == 1 ? 'pedido' : 'pedidos'} · '
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
          ControlSenalado(
            nombre: Senalado.tableroRenombrar,
            child: ListTile(
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
          ),
          ControlSenalado(
            nombre: Senalado.tableroCamionPrevisto,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.local_shipping_outlined),
              title: const Text('Camión previsto'),
              subtitle: Text(columna.vehiculoNombre ?? 'Sin elegir'),
              onTap: () {
                Navigator.of(contexto).pop();
                _elegirCamion(context, ref, columna);
              },
            ),
          ),
          ControlSenalado(
            nombre: Senalado.tableroVaciar,
            child: ListTile(
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
          ControlSenalado(
            nombre: Senalado.tableroBorrarLaZona,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline),
              title: const Text('Borrar la columna'),
              onTap: () {
                Navigator.of(contexto).pop();
                _borrar(context, ref, columna: columna, tablero: tablero);
              },
            ),
          ),
          const Divider(height: 24),
          // EL «NO» SE DICE AQUÍ DENTRO Y NO TE ECHA — 28/09/2026.
          //
          // Esto hacía `Navigator.pop()` ANTES de intentar nada, así que el
          // cajón se cerraba pasara lo que pasara y el motivo salía en una
          // franja abajo, con la pantalla ya cambiada debajo. Jose, el día que
          // se desplegó el bloqueo de «ninguna ruta sin camión»: «ya dio el
          // error pero notifica el campo q hace falta para q relleno no le
          // cierres eso».
          //
          // Tiene razón y es el §4 a medias: el aviso salía —eso estaba bien—
          // pero te sacaba del único sitio donde se arregla. «Camión previsto»
          // está en ESTE cajón, dos dedos más arriba.
          //
          // Ahora: se intenta primero, se cierra SÓLO si sale bien, y si el
          // servidor o el aparato dicen que no, el cajón se queda abierto con el
          // motivo dentro y el campo que falta señalado.
          _ArmarLaRuta(columna: columna, deLaPantalla: context),
        ],
      ),
    );
  }

  /// Crear una columna. El nombre lo pone la persona: las zonas son suyas.
  static Future<void> crearColumna(BuildContext context, WidgetRef ref) async {
    final nombre = await _pedirNombre(context, '');
    if (nombre == null || !context.mounted) return;
    await hacer(context, ref, () async {
      await ref.read(tableroProvider.notifier).crearColumna(nombre);
      RegistroDeControles.completar(Senalado.tableroGuardarLaZona);
    });
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
              subtitle: Text(
                '${destino.pedidos} '
                '${destino.pedidos == 1 ? 'pedido' : 'pedidos'}',
              ),
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
            // SIN RELLENO, como todos — 28/09/2026. Esto era el unico boton de
            // la aplicacion con el fondo cambiado a mano
            // (`backgroundColor: Colores.rojo`), y era eso lo que lo separaba
            // de los demas. Ahora lo separan el color, el contorno de 2 px y la
            // papelera, que es lo que [BotonDestructivo] trae puesto: el estilo
            // no vive aqui, vive en `diseno/tema.dart`.
            BotonDestructivo(
              texto: 'Sí, borrar «${columna.nombre}»',
              alPulsar: () => Navigator.of(contexto).pop(true),
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
      // «1 pedidos puestos» — 28/09/2026. Mismo patrón que las rutas
      // («3 paradas» / «1 parada»).
      //
      // SU GEMELO SIGUE SIN ARREGLAR, y hay que saberlo: `RechazoDelTablero`
      // escribe esta misma frase en `tablero/datos/repositorio.dart`, que es el
      // «no» de la base cuando alguien llega ahí sin pasar por este cajón. Lo
      // tenía abierto otro agente el día que se hizo esto, así que queda
      // apuntado en vez de tocado — y es el §3-bis: dos copias de la misma
      // frase que ya no dicen lo mismo.
      titulo: columna.pedidos == 1
          ? '«${columna.nombre}» tiene 1 pedido puesto'
          : '«${columna.nombre}» tiene ${columna.pedidos} pedidos puestos',
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

  /// EL CAMPO DEL NOMBRE DE UNA ZONA, con su controlador DENTRO — 01/10/2026.
  ///
  /// Aquí el `TextEditingController` se creaba en esta función y se desechaba
  /// en la línea de después del `await`, y las dos cosas estaban mal por la
  /// misma razón: **el `await` de un cajón vuelve cuando se pulsa `pop`, no
  /// cuando el cajón se ha ido.** La salida dura 180 ms
  /// (`abrirPanel.transitionDuration`), y durante esos 180 ms el `TextField`
  /// sigue montado y sigue repintándose contra un controlador ya desechado.
  ///
  /// Lo que Flutter contesta a eso, y no es un aviso suelto:
  ///
  ///     A TextEditingController was used after being disposed.
  ///
  /// y detrás de él otros cinco —`_dependents.isEmpty`, «dirty widget in the
  /// wrong build scope», «looking up a deactivated widget's ancestor»—, o sea
  /// el árbol de widgets roto a media animación cada vez que alguien crea o
  /// renombra una zona.
  ///
  /// Por eso NO HABÍA NINGUNA PRUEBA que entrara el nombre de una zona por la
  /// pantalla: la primera que se escribió reventó aquí
  /// (`el_nombre_de_la_zona_es_lo_tecleado_test.dart`). `columnas_test.dart`
  /// llama a `crearColumna` a pelo y por eso llevaba semanas en verde. Un
  /// camino que no se puede probar es donde se esconde el siguiente fallo —y de
  /// hecho se vino a mirar esto por un aviso de que el nombre se guardaba con
  /// dos letras de más delante.
  ///
  /// El arreglo es el de siempre en este proyecto: **el controlador es del
  /// widget que lo usa**, igual que en la ficha de vehículo, el editor de
  /// almacén o `CajaDeBusqueda`. Este era el único sitio de la aplicación donde
  /// un `TextEditingController` vivía fuera de un `State`.
  static Future<String?> _pedirNombre(
    BuildContext context,
    String inicial,
  ) async {
    final nombre = await mostrarCajon<String>(
      context: context,
      titulo: inicial.isEmpty ? 'Nueva columna' : 'Renombrar «$inicial»',
      contenido: (contexto) => _CampoDelNombreDeLaZona(inicial: inicial),
    );
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
      Registro.fallo(
        'tablero: el gesto no se pudo guardar en el aparato',
        e,
        pila,
      );
      if (!context.mounted) return;
      _decir(context, noSePudoGuardar, problema: true);
    }
  }

  /// El «sí» de un gesto que ya cerró su cajón. Es [_decir] con nombre, para
  /// que desde fuera de esta clase no haya que tocar un privado ni inventarse
  /// un `hacer(() async {})` vacío sólo para enseñar una franja.
  static void decirQueSiSePudo(BuildContext context, String texto) =>
      _decir(context, texto);

  /// El gesto SALIÓ, pero dejando algo fuera. No es un «sí» ni es un «no»: la
  /// ruta existe y hay bultos que no van en ella, así que se pinta como problema
  /// —para que se lea— y se queda el tiempo del problema, no los 3 s del «sí».
  static void decirQueSeQuedoAlgoFuera(BuildContext context, String texto) =>
      _decir(context, texto, problema: true);

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
              'Esta sucursal no tiene vehículos activos en este aparato.',
              'Los vehículos inactivos no se ofrecen para rutas nuevas. Se '
                  'puede armar la ruta igual, pero sin camión no hay capacidad '
                  'contra la que medir el peso ni coste por km que calcular. '
                  'Los vehículos se dan de alta y se activan en Vehículos, y '
                  'bajan con la siguiente sincronización.',
            ),
          ],
          AsyncData(:final value) => [
            // EL CAMION DEL TALLER SALE, Y SALE MARCADO — 28/09/2026, y vuelve el
            // 08/10/2026 (1.0.29).
            //
            // Se OFRECE igual, y es la misma decisión que el paso 3 del
            // asistente de Rutas: aviso, no bloqueo. 1.0.28 lo quitó creyendo que
            // Amado había reemplazado esa decisión; Amado pidió ocultar el
            // INACTIVO (que sigue sin salir: `camionesProvider` filtra con
            // `seOfreceParaRutasNuevas`), y el servidor sigue aceptando un camión
            // en el taller. Un camión en el taller tiene su capacidad y su costo
            // por km, así que el peso de la zona y el coste de su ruta siguen
            // teniendo contra qué medirse — lo que falta es el camión, no el
            // dato. Eso lo separa de la zona SIN camión, que sí se bloquea
            // (`tablero/datos/repositorio.dart`, `armarRuta`).
            //
            // Y bloquear con `maintenance` sería bloquear con un campo que pone
            // una persona y tiene que quitar otra: en producción hay sucursales
            // con UN camión, y uno olvidado en el taller las dejaría sin poder
            // armar ni una zona, con el arreglo en otra pantalla. Un camión de
            // baja que la zona ya tenía puesto lo rechaza `armarRuta` con el
            // literal del servidor.
            //
            // El aviso va en el subtítulo, que es donde ya están la capacidad y
            // la placa: en mayúsculas porque es lo único de esta lista que hace
            // que uno elija otro.
            for (final (cual, camion) in value.indexed)
              // Sólo el primero se deja senalar: hay una fila por camion.
              ControlSenalado(
                nombre: Senalado.tableroElegirCamion,
                senalable: cual == 0,
                child: ListTile(
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

/// EL DETALLE DEL PEDIDO DENTRO DEL CAJÓN DE MOVERLO — 28/09/2026.
///
/// Jose: «ahi en tablero q cuando le den para mover en ves de solo decir q lo
/// vamos a mover q me salga el detalle de el pedido ok».
///
/// ## Por qué no se reutiliza la ficha de Pedidos
///
/// Existe y pinta esto mismo, pero **pide otra cosa**: trabaja sobre el pedido
/// entero de la base, con sus renglones, su ruta y sus acciones, y vive dentro
/// de su propia pantalla. Aquí lo que hay es una `TarjetaPedido` —lo que el
/// tablero ya tiene en la mano— y el cajón tiene que abrirse al instante, sin
/// esperar a ninguna consulta, porque mover es un gesto rápido que se repite.
///
/// Lo que sí se respeta es **el orden en que Jose ya tiene aprendidos los
/// datos** en la ficha de Pedidos: quién, dónde, cuándo, cuánto, y al final lo
/// que lleva dentro. Un segundo sitio que pinte lo mismo en otro orden es un
/// sitio donde hay que volver a aprender a leer.
///
/// ## Lo único que no estaba en la mano: los artículos
///
/// Salen de [renglonesDelPedidoProvider], que es un `Stream` y no un `Future`
/// por el §3-ter — el porqué está escrito allí. Mientras no han llegado se dice
/// **«cargando»** y no «sin artículos»: son dos cosas distintas y la segunda se
/// lee como que el pedido va vacío.
class _DetalleDelPedido extends ConsumerWidget {
  const _DetalleDelPedido({required this.pedido});

  final TarjetaPedido pedido;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final renglones = ref.watch(renglonesDelPedidoProvider(pedido.pedidoId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. DÓNDE VA. Es lo primero porque es lo que decide la zona, que es la
        //    pregunta que se está contestando al abrir este cajón.
        _Dato(
          Icons.place_outlined,
          [
            pedido.address,
            if (pedido.municipio case final m? when m.isNotEmpty) m,
          ].join(' · '),
        ),
        // EL TELÉFONO, SIN LA COMILLA DE EXCEL. Segunda línea de defensa: el dato
        // ya entra limpio por la puerta (`espejo.SinLaComillaDeExcel`, en el
        // servidor), pero lo que bajó ANTES de aquello sigue en la base de este
        // aparato, y aquí es donde Jose lo vio el 28/09/2026 —`'+53 5 2675220`—
        // al abrir este mismo cajón en un SM-A165M.
        if (sinLaComillaDeExcel(pedido.customerPhone ?? '') case final t
            when t.isNotEmpty)
          _Dato(Icons.phone_outlined, t),
        if (pedido.vendedor case final v? when v.isNotEmpty)
          _Dato(Icons.person_outline, v),

        // 2. CUÁNTO. El peso y la distancia mandan sobre si cabe en ese camión;
        //    el costo del domicilio se dice porque `sin cotizar` es un dato y no
        //    un hueco (un cero ahí se leería como «el domicilio es gratis»).
        _Dato(
          Icons.scale_outlined,
          [
            pesoBonito(pedido.weight),
            if (pedido.kmAlAlmacen.isFinite) kmBonito(pedido.kmAlAlmacen),
            pedido.pedidoCosto == null
                ? 'sin cotizar'
                : '\$${pedido.pedidoCosto!.toStringAsFixed(2)}',
          ].join(' · '),
        ),

        // 3. QUÉ LLEVA. Lo último, que es el orden de la ficha de Pedidos.
        const SizedBox(height: 8),
        renglones.when(
          loading: () =>
              Text('Cargando los artículos…', style: tema.textTheme.bodySmall),
          // UN FALLO NO SE PINTA COMO UN PEDIDO VACÍO (§4). Si la consulta se
          // cae, se dice; callarlo deja el cajón diciendo que no lleva nada.
          error: (e, _) => Text(
            'No se pudieron leer los artículos: $e',
            style: tema.textTheme.bodySmall?.copyWith(color: Colores.ambar),
          ),
          data: (lista) => lista.isEmpty
              ? Text(
                  'Este pedido no tiene artículos.',
                  style: tema.textTheme.bodySmall,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final r in lista.take(_cuantosArticulos))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${r.renglon.description} · '
                          '${cantidad(r.renglon.quantity)} uds',
                          style: tema.textTheme.bodySmall,
                        ),
                      ),
                    // LOS QUE NO CABEN SE CUENTAN, NO SE CALLAN. Cortar la
                    // lista sin decirlo deja a alguien creyendo que el camión
                    // lleva cuatro cosas cuando lleva doce.
                    if (lista.length > _cuantosArticulos)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'y ${lista.length - _cuantosArticulos} artículo(s) más',
                          style: tema.textTheme.bodySmall?.copyWith(
                            color: Colores.tintaSuave,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Cuántos artículos caben antes de que el cajón obligue a desplazarse para
  /// llegar a las zonas. Cuatro y el resto contado: mover es un gesto rápido.
  static const _cuantosArticulos = 4;
}

/// Un dato del detalle: su icono y su texto, en una línea que puede envolver.
class _Dato extends StatelessWidget {
  const _Dato(this.icono, this.texto);

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 14, color: Colores.tintaSuave),
        const SizedBox(width: 6),
        Expanded(
          child: Text(texto, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}

/// EL BOTÓN DE ARMAR LA RUTA, QUE SE QUEDA SI DICEN QUE NO — 28/09/2026.
///
/// Jose, el día que se desplegó el bloqueo de «ninguna ruta sin camión»:
///
///     «ya dio el error pero notifica el campo q hace falta para q relleno no le
///      cierres eso»
///
/// Antes esto era un `FilledButton` suelto que hacía `Navigator.pop()` **antes**
/// de intentar nada. O sea: el cajón se cerraba pasara lo que pasara, y el motivo
/// aparecía en una franja abajo con la pantalla ya cambiada debajo.
///
/// El §4 de la casa se cumplía a medias —el aviso salía— y fallaba en lo otro:
/// **te sacaba del único sitio donde se arregla**. «Camión previsto» está en este
/// mismo cajón, dos dedos más arriba.
///
/// Ahora el orden es el correcto: se intenta, y **sólo se cierra si sale bien**.
/// Si dicen que no, el cajón se queda abierto con el motivo dentro y con el campo
/// que falta señalado, para rellenarlo y volver a darle sin repetir el camino.
///
/// El «sí» sigue saliendo por la franja de siempre (`hacer(exito:)`), porque para
/// entonces este cajón ya no está: un mensaje de éxito dentro de algo que se
/// cierra no lo lee nadie.
class _ArmarLaRuta extends ConsumerStatefulWidget {
  const _ArmarLaRuta({required this.columna, required this.deLaPantalla});

  final ColumnaTablero columna;

  /// El contexto de la PANTALLA, no el del cajón. Es el que tiene el
  /// `ScaffoldMessenger` donde sale la franja del «sí», y sigue vivo después de
  /// cerrar el cajón — el del cajón no.
  final BuildContext deLaPantalla;

  @override
  ConsumerState<_ArmarLaRuta> createState() => _ArmarLaRutaState();
}

class _ArmarLaRutaState extends ConsumerState<_ArmarLaRuta> {
  RechazoDelTablero? _no;
  bool _armando = false;

  Future<void> _intentar() async {
    setState(() {
      _armando = true;
      // El «no» de antes se borra al reintentar: dejarlo puesto mientras se
      // vuelve a intentar hace creer que ha vuelto a fallar.
      _no = null;
    });
    try {
      // QUIÉN SE QUEDÓ FUERA, si es que se quedó alguien. El aparato aplica la
      // misma regla que el servidor (`TarjetaPedido.motivoDeNoSubir`), así que lo
      // sabe él mismo en la APK y en el escritorio; en la web se le suma lo que
      // traiga la respuesta. Lo que el servidor cuente luego del apunte de una
      // APK vive en el cajón de entregar el día. Ver `RepositorioTablero.armarRuta`.
      var seQuedaronFuera = const <String>[];
      final rutaId = await ref
          .read(tableroProvider.notifier)
          .armarRuta(
            widget.columna.id,
            alDejarFuera: (fuera) => seQuedaronFuera = fuera,
          );
      if (!mounted) return;
      // Sólo aquí se cierra. Y el «sí» se dice DESPUÉS de cerrar, con el
      // contexto de la pantalla: dentro de algo que se cierra no lo lee nadie.
      final pantalla = widget.deLaPantalla;
      final nombre = widget.columna.nombre;
      Navigator.of(context).pop();
      if (!pantalla.mounted) return;

      // Y DERECHO A LA RUTA, sin pasar por ver cómo se vacía la zona.
      //
      // Jose: «y q cuando cree la ruta nueva por q no voy directo a la ruta por
      // q pierdo el tiempo demostrando q el tablero se vacio mi loco», y
      // después, quitando la duda: «q me lleve directo a rutas con la nueva
      // ruta creada con tablero».
      //
      // Son tres cosas en este orden y las tres hacen falta:
      //
      //  1. **La pestaña.** Una ruta recién armada nace PLANIFICADA, o sea en
      //     `PestanaRutas.activas`. Si Rutas abriera en la que estuviera puesta
      //     —`Historial`, pongamos— se llegaría a una lista donde esa ruta no
      //     está, y eso se lee como que no se creó.
      //  2. **Elegirla.** `RutaElegida.elegir` resuelve el id **en el momento**
      //     contra las equivalencias, y eso es justo lo que hace falta aquí: sin
      //     señal la ruta nace con un `local-…` y, si el ciclo ya la subió, su
      //     id de verdad existe antes de que nadie la mire. El porqué entero
      //     está escrito en ese método, y viene del «Ver paradas (0)» encima de
      //     una ruta recién armada del 21/09/2026.
      //  3. **Ir**, y no `push`: Rutas es una pantalla del armazón, no algo que
      //     se apila encima del Tablero.
      //
      // En un teléfono no hay dos paneles, así que «con ella elegida» es llegar
      // a la lista con su detalle abierto — de eso ya se encarga `ListaDeRutas`
      // con `rutaElegidaProvider`, que es el mismo camino que usar la lista a
      // mano. No hay un segundo camino que mantener.
      ref.read(pestanaRutasProvider.notifier).elegir(PestanaRutas.activas);
      ref.read(rutaElegidaProvider.notifier).elegir(rutaId);
      pantalla.go('/routes');

      // EL «SÍ» DICE LO QUE SE QUEDÓ FUERA, cuando se quedó algo — 28/09/2026.
      //
      // Antes decía sólo «Ruta armada» y el resto de la respuesta se tiraba: la
      // ruta salía con menos pedidos de los que el logístico puso, con un aviso
      // verde encima y sin una palabra de quién faltaba. §4, nada se descarta en
      // silencio, y se dice **qué se rompe sin ello** — aquí, qué bultos NO van
      // en ese camión.
      //
      // Cuando no se cae nadie —lo normal— el mensaje es el de siempre: un aviso
      // que sale en todos los armados deja de leerse (§3-quinquies).
      if (seQuedaronFuera.isEmpty) {
        AccionesTablero.decirQueSiSePudo(
          pantalla,
          'Ruta armada con lo que se puede repartir de «$nombre».',
        );
      } else {
        AccionesTablero.decirQueSeQuedoAlgoFuera(
          pantalla,
          [
            'Ruta armada de «$nombre», pero '
                '${seQuedaronFuera.length} '
                '${seQuedaronFuera.length == 1 ? 'pedido no entró' : 'pedidos no entraron'}:',
            ...seQuedaronFuera,
          ].join('\n'),
        );
      }
    } on RechazoDelTablero catch (no) {
      if (!mounted) return;
      setState(() {
        _armando = false;
        _no = no;
      });
    } on Object catch (e, pila) {
      // Lo que no es un «no» del tablero —el disco lleno, la copia sin
      // permisos— se registra con su error de verdad y en pantalla va el texto
      // de persona. Aquí tampoco se cierra: el gesto no se hizo.
      Registro.fallo('tablero: no se pudo armar la ruta de la zona', e, pila);
      if (!mounted) return;
      setState(() {
        _armando = false;
        _no = const RechazoDelTablero(AccionesTablero.noSePudoGuardar);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final no = _no;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (no != null) ...[
          // EL MOTIVO, ENCIMA DEL BOTÓN Y NO DEBAJO. Se lee de arriba abajo:
          // primero por qué no, y después el botón con el que se reintenta.
          Container(
            key: _claveDelNo,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: ColoresTablero.rojo.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: ColoresTablero.rojo.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  no.mensaje,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                // LO QUE FALTA, NOMBRADO. `detalles` es justo eso: de dónde se
                // cayó cada cosa y dónde se arregla. Sin esto el aviso dice
                // «no» y deja a quien lo lee buscando.
                for (final detalle in no.detalles)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      detalle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
        ControlSenalado(
          nombre: Senalado.tableroArmarLaRuta,
          child: FilledButton.icon(
            icon: _armando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.route_outlined),
            label: Text(
              // Al reintentar, el rótulo lo dice: pulsar lo mismo que acaba de
              // fallar sin que cambie nada se lee como que el botón está roto.
              _armando
                  ? 'Armando…'
                  : no == null
                  ? 'Armar la ruta de esta zona'
                  : 'Volver a intentarlo',
            ),
            onPressed: _armando ? null : _intentar,
          ),
        ),
      ],
    );
  }

  /// Para poder medir en una prueba que el aviso está DENTRO del cajón y no en
  /// una franja de la pantalla de detrás.
  static const _claveDelNo = ValueKey('tablero-no-se-armo');
}

/// El cuerpo del cajón de «Nueva columna» y de «Renombrar»: un campo y su
/// `Guardar`.
///
/// Existe para que el `TextEditingController` **viva y muera con el campo**. El
/// porqué entero está en `AccionesTablero._pedirNombre`: el `await` de un cajón
/// vuelve al pulsar `pop` y el cajón sigue montado 180 ms más, así que
/// desecharlo desde fuera lo deja en uso después de desechado.
class _CampoDelNombreDeLaZona extends StatefulWidget {
  const _CampoDelNombreDeLaZona({required this.inicial});

  /// Vacío al crear; el nombre de ahora al renombrar.
  final String inicial;

  @override
  State<_CampoDelNombreDeLaZona> createState() =>
      _CampoDelNombreDeLaZonaState();
}

class _CampoDelNombreDeLaZonaState extends State<_CampoDelNombreDeLaZona> {
  late final TextEditingController _control = TextEditingController(
    text: widget.inicial,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.inicial.isEmpty) {
        RegistroDeControles.completar(Senalado.tableroNuevaZona);
      }
    });
  }

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  /// Un solo sitio por donde sale el nombre: el `Guardar` y el Intro del teclado
  /// tienen que entregar lo MISMO. Con dos caminos, uno de los dos se queda sin
  /// el `trim` o sin el `pop` el día que se toque esto.
  void _entregar(String texto) => Navigator.of(context).pop(texto);

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ControlSenalado(
        nombre: Senalado.tableroNombreDeLaZona,
        child: TextField(
          controller: _control,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nombre de la zona',
            hintText: 'Centro, Vista Alegre, Carretera…',
            border: OutlineInputBorder(),
          ),
          onSubmitted: _entregar,
        ),
      ),
      const SizedBox(height: 16),
      ControlSenalado(
        nombre: Senalado.tableroGuardarLaZona,
        child: BotonPrincipal(
          icono: Icons.save_outlined,
          texto: 'Guardar',
          alPulsar: () => _entregar(_control.text),
        ),
      ),
    ],
  );
}
