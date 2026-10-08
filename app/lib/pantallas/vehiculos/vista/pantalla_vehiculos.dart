import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reparto/nucleo/frescura/copia_bajada.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/red/fallos.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/barra_de_filtros.dart';
import '../../../diseno/caja_de_busqueda.dart';
import '../../../diseno/cajon.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/estado_vacio.dart';
import '../../../diseno/preguntar_antes_de_borrar.dart';
import '../../../diseno/tema.dart';
import '../../../navegacion/estado_navegacion.dart';
import '../../ayuda/datos/controles_senalados.dart';
import '../../ayuda/vista/control_senalado.dart';
import '../datos/vehiculo_api.dart';
import '../estado/estado_vehiculos.dart';
import 'ficha_vehiculo.dart';
import 'tarjeta_vehiculo.dart';
import 'tipos_vehiculo.dart';

/// Vehiculos — `/vehicles`. Pliego: `pantallas.md` §5.
///
/// **Sólo con conexion, y se dice.** La flota se configura una vez, en la
/// oficina: no hay base local ni cola. Sin red esta pantalla no ensena una
/// flota vieja ni acepta cambios que luego se perderian — avisa y se queda
/// quieta.
class PantallaVehiculos extends ConsumerStatefulWidget {
  const PantallaVehiculos({super.key});

  static const ruta = '/vehicles';

  @override
  ConsumerState<PantallaVehiculos> createState() => _PantallaVehiculosState();
}

class _PantallaVehiculosState extends ConsumerState<PantallaVehiculos> {
  bool _guardando = false;

  AjustesDeLaApi get _ajustes =>
      ref.read(ajustesVehiculosProvider).value ??
      const AjustesDeLaApi(tipos: [], cupRate: 320);

  List<VehiculoDeLaApi> get _flota =>
      ref.read(vehiculosProvider).value ?? const [];

  /// Los tipos que se enseñan: los de ajustes MAS los que ya usan los
  /// vehiculos. Ver `TipoDeVehiculo.paraElCajon`.
  List<TipoDeVehiculo> _tiposVisibles(AjustesDeLaApi ajustes) =>
      TipoDeVehiculo.paraElCajon(deAjustes: ajustes.tipos, vehiculos: _flota);

  /// Mete un tipo nuevo en el catalogo y lo GUARDA (`PUT /api/settings`).
  ///
  /// Se manda la lista entera, que es como el servidor guarda `tiposVehiculo`:
  /// los que ya estaban mas el nuevo.
  Future<bool> _crearTipo(TipoDeVehiculo nuevo) async {
    final ajustes = _ajustes;
    if (ajustes.tipos.any((t) => t.nombre == nuevo.nombre)) return true;
    return ref.read(controlVehiculosProvider.notifier).guardarTipos([
      ...ajustes.tipos,
      nuevo,
    ]);
  }

  Future<void> _abrirFicha([VehiculoDeLaApi? vehiculo]) async {
    await abrirPanel<void>(
      context,
      // `Consumer` y no los ajustes leidos una vez: al crear un tipo desde la
      // propia ficha, `ajustesVehiculosProvider` se invalida y el desplegable
      // tiene que traerlo ya. Con una copia congelada el tipo recien guardado
      // no aparecia hasta cerrar y volver a abrir.
      (contexto) => Consumer(
        builder: (contexto, ref, _) {
          final ajustes = ref.watch(ajustesVehiculosProvider).value ?? _ajustes;
          return StatefulBuilder(
            builder: (contexto, repintar) => FichaVehiculo(
              vehiculo: vehiculo,
              tipos: _tiposVisibles(ajustes),
              cupRate: ajustes.cupRate,
              guardando: _guardando,
              alCrearTipo: _crearTipo,
              alGuardar: (datos) async {
                repintar(() => _guardando = true);
                final control = ref.read(controlVehiculosProvider.notifier);
                final bien = vehiculo == null
                    ? await control.crear(datos)
                    : await control.editar(vehiculo.id, datos);
                if (!contexto.mounted) return;
                repintar(() => _guardando = false);
                // Sólo se cierra si de verdad se guardo. Si no hubo red, el
                // panel se queda con lo escrito y el aviso lo explica:
                // cerrarlo seria dar por hecho que se guardo.
                if (bien) Navigator.of(contexto).pop();
              },
            ),
          );
        },
      ),
    );
    _guardando = false;
  }

  Future<void> _abrirTipos() async {
    final ajustes = _ajustes;
    await abrirPanel<void>(
      context,
      (contexto) => StatefulBuilder(
        builder: (contexto, repintar) => TiposDeVehiculo(
          tipos: _tiposVisibles(ajustes),
          guardando: _guardando,
          alGuardar: (tipos) async {
            repintar(() => _guardando = true);
            final bien = await ref
                .read(controlVehiculosProvider.notifier)
                .guardarTipos(tipos);
            if (!contexto.mounted) return;
            repintar(() => _guardando = false);
            if (bien) Navigator.of(contexto).pop();
          },
        ),
      ),
    );
    _guardando = false;
  }

  @override
  Widget build(BuildContext context) {
    final lista = ref.watch(vehiculosProvider);
    // SE MIRAN LOS AJUSTES AUNQUE NO SE PINTEN AQUI.
    //
    // De ellos salen los tipos de vehiculo y la tasa del ayudante del costo por
    // km. Se leian con `ref.read` desde los dos cajones y nada mas, y como el
    // provider es `autoDispose` eso significaba que **nadie lo mantenia vivo**:
    // cada lectura arrancaba una peticion nueva, devolvia `null` en el acto y la
    // pantalla se quedaba con el respaldo vacio. Asi, el catalogo de tipos salia
    // vacio siempre y un tipo recien guardado no aparecia al reabrir el cajon.
    ref.watch(ajustesVehiculosProvider);
    final busqueda = ref.watch(busquedaVehiculosProvider);
    final porPagina = ref.watch(porPaginaVehiculosProvider);
    final pagina = ref.watch(paginaVehiculosProvider);
    final filtro = ref.watch(filtroAndarProvider);

    // Los avisos de escritura salen en la barra de abajo, no en el sitio de la
    // lista: la lista no cambio.
    ref.listen<AvisoVehiculos?>(controlVehiculosProvider, (_, aviso) {
      if (aviso == null) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(aviso.texto),
            backgroundColor: aviso.esFallo
                ? Theme.of(context).colorScheme.error
                : null,
          ),
        );
    });

    // SIN `Scaffold` propio: lo pone el armazon.
    //
    // Esta pantalla se escribio antes de que existiera el armazon, que ya trae barra
    // lateral, barra superior con el titulo y la franja de estado. Un `Scaffold` dentro de
    // otro apila dos superficies de Material y deja los avisos emergentes colgando del de
    // dentro, que es el que no se ve entero.
    //
    // Ver el contrato en `lib/navegacion/pantalla_registrada.dart`.
    return SafeArea(
      child: ListView(
        // 12 en el teléfono y 24 en pantalla grande, que es la regla de `Aire`
        // y lo que ya hacían Clientes, Pedidos e Informes. Estaba clavado en 24
        // y en un móvil de 390 dejaba 342 útiles contra los 366 de Clientes:
        // dos listas hermanas con márgenes distintos.
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < Anchos.idioma ? Aire.md : Aire.xl,
        ),
        children: [
          Text('Vehículos', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          // MANDABA A UNA PANTALLA QUE NO EXISTE — 05/10/2026.
          //
          // Decia «las tarifas se configuran globalmente en **Configuracion**»
          // y en esta aplicacion **no hay ninguna entrada «Configuracion» en el
          // menu**: comprobado en los doce `registro.dart`. Es un resto del
          // front de Next, de donde vino el patron.
          //
          // Lo caza quien escribe el manual, no una prueba: al contar «donde se
          // ponen las tarifas» hubo que escribir «si buscas una pantalla de
          // Configuracion, no la busques», que es justo el parrafo que no
          // deberia existir. Y el logistico de Santiago la habria buscado solo,
          // sin nadie al lado a quien preguntar.
          //
          // El sitio bueno estaba **en esta misma pantalla**, a dos dedos: el
          // boton «Tipos de vehiculo». Ahora lo dice.
          Text(
            'Gestiona tu flota. El costo por kilómetro de cada tipo de camión '
            'se pone en «Tipos de vehículo», aquí al lado.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          // La misma colocación que Pedidos, Clientes y el Tablero: la manda
          // `BarraDeFiltros`. Antes era un `Wrap` propio de 8/8 —Clientes usaba
          // 12/12 y Almacenes 12/8— con la caja de buscar clavada en 220 px, y
          // a 390 el buscador y los dos botones salían en tres escalones
          // desiguales. Ver `lib/diseno/barra_de_filtros.dart`.
          BarraDeFiltros(
            margen: EdgeInsets.zero,
            // La caja de la casa. Antes consultaba en CADA letra y no tenia
            // respiro ninguno: la misma caja en cinco pantallas y cinco
            // comportamientos distintos.
            busqueda: CajaDeBusqueda(
              valor: ref.watch(busquedaVehiculosProvider),
              alBuscar: (t) {
                ref.read(busquedaVehiculosProvider.notifier).poner(t);
                ref.read(paginaVehiculosProvider.notifier).poner(1);
              },
            ),
            // Van en `acciones` y no en `filtros` porque no filtran nada: se
            // colocan igual, pero el nombre no engaña a quien lea esto luego.
            acciones: [
              // ENVUELTOS PARA QUE LA GUIA LOS PUEDA SENALAR. El envoltorio no
              // pinta nada ni cambia el tamano: sólo dice donde esta el control
              // para que el recorrido guiado le ponga el foco encima
              // (`pantallas/ayuda/vista/control_senalado.dart`).
              ControlSenalado(
                nombre: Senalado.vehiculosTipos,
                child: OutlinedButton(
                  onPressed: _abrirTipos,
                  child: const Text('Tipos de vehículo'),
                ),
              ),
              ControlSenalado(
                nombre: Senalado.vehiculosAgregar,
                child: BotonPrincipal(
                  icono: Icons.add,
                  texto: 'Agregar Vehículo',
                  alPulsar: () => _abrirFicha(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (lista.error case final fallo?)
            _Fallo(
              fallo: fallo,
              // QUE TIENE EL APARATO DENTRO. Sin esto, «Sin conexión» deja sin
              // contestar la pregunta que de verdad importa: si el aparato
              // bajo la flota alguna vez o no la ha bajado nunca. Son dos
              // situaciones que hoy se ven iguales y se arreglan al reves.
              //
              // **En la web, nada de esto.** Alli la base nace vacia en cada
              // carga de la pagina, asi que «este aparato no ha descargado la
              // flota todavia» es verdad siempre y no significa nada: ni hay
              // aparato al que traerle el dia ni copia del lunes con la que
              // armar una ruta (`nucleo/plataforma.dart`, regla 1).
              enElAparato: ref.watch(trabajaSinConexionProvider)
                  ? ref.watch(flotaEnElAparatoProvider).value
                  : null,
              enWeb: !ref.watch(trabajaSinConexionProvider),
              alReintentar: () => ref.invalidate(vehiculosProvider),
            )
          else if (lista.value case final vehiculos?) ...[
            // DE UN VISTAZO, QUE HAY LIBRE Y QUE NO — 28/09/2026.
            //
            // Jose: «saber de la flota». Hasta hoy esta pantalla listaba
            // camiones y no decia en que andaba ninguno: habia que abrir tarjeta
            // por tarjeta, y ni asi, porque la caja de «Ruta activa» no salia
            // nunca (el servidor no mandaba el campo).
            //
            // Los contadores van SOBRE LA FLOTA ENTERA y no sobre lo buscado ni
            // sobre la pagina: la pregunta es «¿tengo camion para esta ruta?», y
            // contarla sobre lo que se esta mirando contesta otra cosa. Es el
            // mismo cuidado con el denominador que costo los dias 25 y 26/09.
            _ResumenDeLaFlota(flota: vehiculos),
            const SizedBox(height: 12),
            _Rejilla(
              vehiculos: vehiculos
                  .where((v) => v.cuadraCon(busqueda))
                  .where((v) => filtro == null || v.andar == filtro)
                  .toList(),
              pagina: pagina,
              porPagina: porPagina,
              alAgregar: () => _abrirFicha(),
              alEditar: _abrirFicha,
              alIr: (n) => ref.read(paginaVehiculosProvider.notifier).poner(n),
              alCambiarTamano: (n) {
                ref.read(porPaginaVehiculosProvider.notifier).poner(n);
                ref.read(paginaVehiculosProvider.notifier).poner(1);
              },
            ),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('Cargando vehículos...')),
            ),
        ],
      ),
    );
  }
}

/// LA FLOTA DE UN VISTAZO: cuantos libres, cuantos cogidos y cuantos fuera.
///
/// Los tres numeros salen de `VehiculoDeLaApi.andar`, o sea de las RUTAS de cada
/// camion, no de `vehicles.status`. El porque esta escrito en `vehiculo_api.dart`
/// y viene del propio servidor: un campo que alguien pone a mano y nadie quita se
/// queda en `in_use` con la ruta ya cerrada.
///
/// Y son TRES y no dos porque «cogido para mañana» no es «fuera ahora». Juntarlos
/// en «ocupado» manda a buscar otro camion a quien tenia uno disponible hasta que
/// salga esa ruta.
class _ResumenDeLaFlota extends ConsumerWidget {
  const _ResumenDeLaFlota({required this.flota});

  final List<VehiculoDeLaApi> flota;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtro = ref.watch(filtroAndarProvider);
    int cuantos(AndarDelCamion cual) =>
        flota.where((v) => v.andar == cual).length;

    // El de mantenimiento sólo se enseña SI HAY ALGUNO, y ésa es la diferencia
    // con los otros tres: los otros tres contestan «¿tengo camión para esta
    // ruta?» y un cero ahí es una respuesta —«no queda ninguno libre»—, mientras
    // que un «Mantenimiento 0» es una pregunta que nadie ha hecho ocupando sitio
    // en un móvil de 390. Lo normal es que no haya ninguno en el taller.
    //
    // LOS CUATRO PARTEN LA FLOTA UNA SOLA VEZ, y eso hay que mantenerlo: salen
    // todos de `andar`, que devuelve un único valor por camión. Un camión en el
    // taller **con una ruta abierta** cuenta aquí y NO en «En ruta» —el taller
    // manda, el porqué está en `VehiculoDeLaApi.andar`—, así que los cuatro
    // siguen sumando la flota entera y ninguno cuenta a nadie dos veces. Es el
    // mismo cuidado con el denominador que costó los días 25 y 26/09.
    final enTaller = cuantos(AndarDelCamion.enMantenimiento);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Contador(
          etiqueta: 'Libres',
          cuantos: cuantos(AndarDelCamion.libre),
          color: Colores.verde,
          fondo: Colores.verdeFondo,
          cual: AndarDelCamion.libre,
          puesto: filtro,
        ),
        _Contador(
          etiqueta: 'En ruta',
          cuantos: cuantos(AndarDelCamion.enRuta),
          color: Colores.enCurso,
          fondo: Colores.enCursoFondo,
          cual: AndarDelCamion.enRuta,
          puesto: filtro,
        ),
        _Contador(
          etiqueta: 'Con ruta planificada',
          cuantos: cuantos(AndarDelCamion.asignado),
          color: Colores.ambar,
          fondo: Colores.ambarFondo,
          cual: AndarDelCamion.asignado,
          puesto: filtro,
        ),
        if (enTaller > 0)
          _Contador(
            etiqueta: 'Mantenimiento',
            cuantos: enTaller,
            color: Colores.ambar,
            fondo: Colores.ambarFondo,
            cual: AndarDelCamion.enMantenimiento,
            puesto: filtro,
          ),
      ],
    );
  }
}

/// Un contador de la franja. Se toca para quedarse con ese grupo, y se vuelve a
/// tocar para soltarlo.
class _Contador extends ConsumerWidget {
  const _Contador({
    required this.etiqueta,
    required this.cuantos,
    required this.color,
    required this.fondo,
    required this.cual,
    required this.puesto,
  });

  final String etiqueta;
  final int cuantos;
  final Color color;
  final Color fondo;
  final AndarDelCamion cual;
  final AndarDelCamion? puesto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elegido = puesto == cual;
    return InkWell(
      borderRadius: BorderRadius.circular(Radios.md),
      onTap: () {
        ref.read(filtroAndarProvider.notifier).alternar(cual);
        // A la primera pagina: si estabas en la 3 de 25 camiones y te quedas con
        // los 2 libres, la pagina 3 no existe y la pantalla sale vacia teniendo
        // dos.
        ref.read(paginaVehiculosProvider.notifier).poner(1);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Aire.md,
          vertical: Aire.sm,
        ),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(Radios.md),
          // El elegido se marca con un borde y no sólo con el fondo: los cuatro
          // fondos ya son de colores distintos, así que un fondo más fuerte no
          // se lee como «éste está puesto».
          border: Border.all(
            color: elegido ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // La cifra en mono, como las cajas de la tarjeta: estos cuatro
            // números se comparan entre sí de un golpe de vista.
            Text(
              '$cuantos',
              style: Tipos.mono(
                tamano: 16,
                peso: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              etiqueta,
              style: Tipos.texto(
                tamano: 12,
                peso: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lo que se ve cuando la lista no pudo bajar.
///
/// Un `FalloDeRed` no es «no hay vehiculos»: son dos cosas distintas y pintarlas
/// igual hace que alguien crea que la flota se borro.
class _Fallo extends StatelessWidget {
  const _Fallo({
    required this.fallo,
    required this.alReintentar,
    this.enElAparato,
    this.enWeb = false,
  });

  final Object fallo;
  final VoidCallback alReintentar;

  /// Lo que la bajada del dia dejo en la base. `null` mientras se mira, y
  /// siempre `null` en la web: alli no hay copia de la que hablar.
  final CopiaBajada? enElAparato;

  /// Si esto se esta viendo en un navegador. Cambia las PALABRAS, no la regla:
  /// el fallo se cuenta igual, pero sin mandar a mirar una señal que quien esta
  /// sentado en la oficina ya tiene (`nucleo/plataforma.dart`, `TextosDeCaida`).
  final bool enWeb;

  @override
  Widget build(BuildContext context) {
    final texto = switch (fallo) {
      // Literal NUEVO: dice que es de ahora y que no se guarda nada aqui, para
      // que nadie se ponga a dar de alta camiones que no van a existir.
      //
      // En la web el titular cambia entero: si la pagina cargo, conexion hay, y
      // el que no contesta es el servidor. Mandar a mirar la señal a quien esta
      // en la oficina es mandarlo a mirar donde no es.
      FalloDeRed() when enWeb =>
        'El servidor no contesta. La página cargó, así que conexión hay: el '
            'que no responde es el servidor. Prueba otra vez y, si sigue '
            'igual, avisa a la oficina.',
      FalloDeRed() =>
        'Sin conexión. Los vehículos se configuran con conexión: aquí no se '
            'guarda nada en el aparato. Vuelve a intentarlo cuando haya red.',
      final FalloApi f => f.mensaje,
      _ => 'No se pudo traer la flota. $fallo',
    };

    // LO QUE HAY DENTRO DEL TELEFONO, y **sólo cuando el fallo es de red**: si
    // el servidor contesto y dijo que no, la copia local no viene al caso y
    // anadirla sería ruido encima de un mensaje que ya es claro.
    final copia = enElAparato;
    final Widget? dentro = (fallo is! FalloDeRed || copia == null)
        ? null
        : copia.seDescargo
        ? LoQueTieneElAparato(
            texto: copia.cuantos == 0
                // Se bajo y no habia ninguno: eso SI es un vacio, y se dice
                // como tal aunque ahora mismo no haya red para confirmarlo.
                ? 'La última bajada tampoco trajo ningún vehículo: la flota '
                      'está vacía, no sin descargar.'
                : 'El aparato tiene ${copia.cuantos} vehículo(s) de la última '
                      'bajada: con ésos se puede armar la ruta aunque esta '
                      'pantalla no cargue.',
            enAmbar: copia.cuantos == 0,
          )
        : const LoQueTieneElAparato(
            // El caso que importa: no es que no haya camiones, es que este
            // aparato no los ha descargado. Se arregla trayendo el día.
            texto:
                'Este aparato no ha descargado la flota todavía. No es que no '
                'haya vehículos: es que no están aquí. Baja sola al traer el '
                'día desde el Panel.',
            enAmbar: true,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Text(texto, textAlign: TextAlign.center),
          ?dentro,
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: alReintentar,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _Rejilla extends ConsumerWidget {
  const _Rejilla({
    required this.vehiculos,
    required this.pagina,
    required this.porPagina,
    required this.alAgregar,
    required this.alEditar,
    required this.alIr,
    required this.alCambiarTamano,
  });

  final List<VehiculoDeLaApi> vehiculos;
  final int pagina;
  final int porPagina;
  final VoidCallback alAgregar;
  final ValueChanged<VehiculoDeLaApi> alEditar;
  final ValueChanged<int> alIr;
  final ValueChanged<int> alCambiarTamano;

  /// BORRAR UN CAMIÓN PREGUNTA ANTES — 01/10/2026.
  ///
  /// Hasta hoy no preguntaba nada: un toque y el camión desaparecía. El
  /// comentario que había en la tarjeta decía que era «sin confirmación, como la
  /// de Next», y que cambiarlo aquí y no allá haría que la misma acción se
  /// comportara distinto según por dónde entres. Eso vale cuando las dos son
  /// igual de defendibles, y ésta no lo era: la casa **ya había decidido lo
  /// contrario** el 25/09/2026 con «Borrar la columna» del tablero, cuando Jose
  /// vio una zona irse de un toque. Lo que quedaba aquí no era una decisión, era
  /// un descuido: se le escapó.
  ///
  /// Y el precio no es el mismo que el de una zona. La semana que viene el
  /// logístico de Santiago prueba esto solo delante de la pantalla, a 900 km: un
  /// camión borrado por error ahí es una llamada de teléfono y una tarde perdida.
  ///
  /// La pieza es la misma y el literal es el mismo —[preguntarAntesDeBorrar]—,
  /// no uno inventado. Lo único propio es **qué se pierde**, y sale del servidor.
  ///
  /// # LO QUE DECÍA ESTO YA NO ES VERDAD — 07/10/2026 (Amado, incidencia 4)
  ///
  /// Decía que las rutas «se quedan sin camión». Ya no: `borrarVehiculo` se
  /// niega con un 409 si el camión tiene rutas, **incluso históricas**, para no
  /// romper la trazabilidad («No se puede eliminar este vehículo porque tiene
  /// rutas asociadas, incluso históricas. Márcalo como inactivo para impedir que
  /// se use en nuevas rutas.»). Lo que se puede borrar es el que nunca se usó. La
  /// pregunta lo dice antes de que el servidor tenga que decirlo, y apunta a la
  /// salida: **marcarlo inactivo** (en «Editar»), que es lo que quita un camión
  /// de la selección de rutas nuevas sin perder su historia.
  Future<void> _borrarPreguntando(
    BuildContext contexto,
    ControlVehiculos control,
    VehiculoDeLaApi vehiculo,
  ) async {
    final seguro = await preguntarAntesDeBorrar(
      contexto,
      queSeVa: vehiculo.nombre,
      loQuePasa:
          'El camión se va de la flota y hay que volver a darlo de alta a '
          'mano, con su placa, su capacidad y su costo por km.\n\n'
          'Un camión que ya tiene rutas —aunque sean del histórico— NO se '
          'puede borrar: el servidor lo rechaza para no perder qué camión hizo '
          'cada reparto. Si ese es el caso, no lo borres: ábrelo con «Editar» y '
          'márcalo como inactivo. Así deja de ofrecerse en las rutas nuevas y su '
          'historial se queda intacto.',
      // «dejarla» es el de la zona; aquí es un camión.
      noLoBorres: 'No, dejarlo',
    );
    if (!seguro) return;
    await control.eliminar(vehiculo.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // El dinero de esta pantalla —el costo por km del vehiculo de calculo— va
    // en la moneda que se esta mirando, igual que en Panel e Informes.
    final tasa = ref.watch(tasaDeLaMiradaProvider);
    final moneda = ref.watch(monedaEfectivaProvider);
    String importe(double? usd) => tasa.importe(usd, moneda);

    if (vehiculos.isEmpty) {
      // EL VACIO ES UNA INVITACION, no un callejon.
      //
      // Aqui se llega con el servidor contestando y diciendo que no hay
      // ninguno: es un VACIO DE VERDAD, y por eso se puede invitar a dar de
      // alta. El «no se ha descargado» vive en `_Fallo`, que es el otro camino,
      // y dice otra cosa.
      //
      // Los dos literales del pliego (§5) se conservan: `Sin vehículos` es el
      // titulo y `Agrega tu primer vehículo para asignarlo a rutas` es el botón
      // de siempre. Lo que se añade es lo que faltaba: **que es esto** y **qué
      // se rompe mientras siga vacío**.
      return Invitacion(
        icono: Icons.local_shipping_outlined,
        titulo: 'Sin vehículos',
        queEs:
            'Aquí van los camiones con los que se reparte: cuánto carga cada '
            'uno, qué cuesta su kilómetro y cuál está hoy en ruta.',
        siNoEsta:
            'Mientras no haya ninguno no se puede terminar de armar una ruta '
            '—el asistente se para en el paso del vehículo— y las columnas del '
            'tablero se quedan sin camión.',
        llamada: 'Agrega tu primer vehículo para asignarlo a rutas',
        textoDelBoton: 'Agregar Vehículo',
        iconoDelBoton: Icons.add,
        alPulsar: alAgregar,
      );
    }

    final paginas = math.max(1, (vehiculos.length / porPagina).ceil());
    final actual = pagina.clamp(1, paginas);
    final desde = (actual - 1) * porPagina;
    final trozo = vehiculos.skip(desde).take(porPagina).toList();
    final control = ref.read(controlVehiculosProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, medidas) {
            // 1 / 2 / 3 columnas, como el pliego.
            final columnas = medidas.maxWidth >= 1024
                ? 3
                : medidas.maxWidth >= 640
                ? 2
                : 1;
            const hueco = 12.0;
            final ancho =
                (medidas.maxWidth - hueco * (columnas - 1)) / columnas;
            // `Wrap` y no `GridView`: las tarjetas no miden todas lo mismo
            // —las que estan en uso traen la caja de `Ruta activa` y algunas
            // llevan notas—, y una rejilla de alto fijo recorta justo eso. Con
            // `Wrap` cada una ocupa lo que necesita y no se pierde nada por
            // debajo del borde.
            return Wrap(
              spacing: hueco,
              runSpacing: hueco,
              children: [
                for (final (indice, v) in trozo.indexed)
                  SizedBox(
                    width: ancho,
                    child: TarjetaVehiculo(
                      // Sólo la primera se deja senalar por la Guia: ver
                      // `TarjetaVehiculo.esLaPrimera`.
                      esLaPrimera: indice == 0,
                      vehiculo: v,
                      importe: importe,
                      alEditar: () => alEditar(v),
                      alEliminar: () => _borrarPreguntando(context, control, v),
                      alMarcarDisponible: () => control.marcarDisponible(v.id),
                      alUsarParaDomicilio: () =>
                          control.usarParaDomicilio(v.id),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Mostrando ${desde + 1}–${desde + trozo.length} de '
              '${vehiculos.length}',
            ),
            DropdownButton<int>(
              value: porPagina,
              items: const [
                DropdownMenuItem(value: 25, child: Text('25 / pág.')),
                DropdownMenuItem(value: 50, child: Text('50 / pág.')),
                DropdownMenuItem(value: 100, child: Text('100 / pág.')),
              ],
              onChanged: (v) => alCambiarTamano(v ?? 25),
            ),
            if (paginas > 1)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Primera',
                    onPressed: actual > 1 ? () => alIr(1) : null,
                    icon: const Text('«'),
                  ),
                  IconButton(
                    tooltip: 'Anterior',
                    onPressed: actual > 1 ? () => alIr(actual - 1) : null,
                    icon: const Text('‹'),
                  ),
                  Text('$actual / $paginas'),
                  IconButton(
                    tooltip: 'Siguiente',
                    onPressed: actual < paginas ? () => alIr(actual + 1) : null,
                    icon: const Text('›'),
                  ),
                  IconButton(
                    tooltip: 'Última',
                    onPressed: actual < paginas ? () => alIr(paginas) : null,
                    icon: const Text('»'),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
