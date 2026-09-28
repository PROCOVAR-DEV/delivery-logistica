import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../../nucleo/refresco_en_vivo.dart';
import '../../../nucleo/red/fallos.dart';
import '../../../nucleo/registro/registro.dart';
import '../datos/consultas.dart';
import '../datos/esquema.dart';
import '../datos/modelos.dart';
import '../datos/repositorio.dart';
import '../datos/servicio.dart';
import '../../pedidos/datos/repositorio_pedidos.dart';
import '../../pedidos/estado/proveedores_pedidos.dart';

export '../datos/consultas.dart' show FiltrosSinColocar;

final consultasTableroProvider = Provider<ConsultasTablero>(
  (ref) => ConsultasTablero(ref.watch(baseProvider)),
);

/// Las escrituras del tablero.
///
/// `escrituraEnVivoProvider` es `null` en la APK y en el escritorio —arrastrar
/// no llama a nadie y el apunte espera en la cola— y **no es null en la web**,
/// donde cada gesto va al servidor y se espera su respuesta antes de mover una
/// sola tarjeta (`CLAUDE.md` §1 y §3-quinquies).
final repositorioTableroProvider = Provider<RepositorioTablero>(
  (ref) => RepositorioTablero(
    ref.watch(baseProvider),
    ref.watch(colaProvider),
    reloj: ref.watch(relojProvider),
    enVivo: ref.watch(escrituraEnVivoProvider),
  ),
);

final servicioTableroProvider = Provider<ServicioTablero>(
  (ref) => ServicioTablero(
    ref.watch(baseProvider),
    ref.watch(clienteApiProvider),
    ref.watch(frescuraProvider),
    reloj: ref.watch(relojProvider),
  ),
);

/// QUE SUCURSAL SE ESTA MIRANDO.
///
/// La del Super Admin cuando ha elegido una; si no, la suya. **Si no hay
/// ninguna no se ensena «todo»**: las columnas son de una sucursal y la cercania
/// se mide desde el almacen de una sucursal, asi que un tablero de las diez
/// mezcladas ordenaria los pedidos de Holguin por su distancia al almacen de
/// Santiago (§2).
/// LO QUE EL TOKEN TRAE ES EL CODIGO, NO EL ID — 24/09/2026.
///
/// `Sesion.sucursalId` sale del token de Accesos, y ahi la sucursal va con su
/// CODIGO: `CAM`, `HAB`, `STG` (`nucleo/identidad/sesion.dart`, y del otro lado
/// `apk-tokens.ts`). Aqui, en cambio, todo va por el id del reparto: las
/// columnas, las tarjetas, el nombre de la sucursal, su almacen y los camiones
/// se leen de la base local por `branches.id`, que es un uuid.
///
/// Devolver el codigo tal cual hacia que el Tablero **no se abriera**, y sin
/// decir nada: `GET /api/board?branchId=CAM` contesta 404 —«un id que ni
/// siquiera es un uuid es el mismo caso que uno que ya no esta»— y las lecturas
/// locales no encontraban ni la sucursal ni sus columnas. Desde la silla de
/// quien trabaja: pulsas «Tablero» y no pasa nada. Ni una pantalla de error, ni
/// un aviso, ni una rueda. Se vio el primer dia que se pudo entrar con el
/// Accesos de verdad levantado en el portatil.
///
/// La traduccion se hace igual que en el resto del aparato —«se traduce con
/// `branches.external_id` y no se adivina», `nucleo/almacenes/almacen_de_referencia.dart`—
/// y si no hay con que traducir **no se inventa**: se devuelve `null`, que es
/// «todavia no se sabe cual», y no el codigo, que seria un id falso.
/// SOLO SE TRADUCE LO DE LA SESION, y no lo que se elige arriba.
///
/// Son dos cosas distintas aunque viajen por el mismo hueco:
///
///  * **Lo que elige arriba un Super Admin** sale de la lista de sucursales que
///    sirve el servidor, asi que YA es un id del reparto. Va tal cual: si el
///    aparato todavia no tiene esa sucursal bajada, preguntarsela al servidor es
///    exactamente lo que hay que hacer, y traducirla contra una copia que no la
///    tiene la dejaria en `null` — el tablero se quedaria mudo al cambiar de
///    sucursal, que es justo lo que caza
///    `el_filtro_no_pide_al_servidor_test.dart`.
///  * **La de la sesion** es un CODIGO (`CAM`), y esa si hay que traducirla.
Future<String?> _idDeLaSesion(BaseLocal base, String codigoOId) async {
  // Una sesion guardada de antes —o la de la web— puede traer ya el id. Se
  // respeta: lo que se busca es el id del reparto, venga escrito como venga.
  final porId = await (base.select(
    base.branches,
  )..where((b) => b.id.equals(codigoOId))).getSingleOrNull();
  if (porId != null) return porId.id;

  final porCodigo = await (base.select(
    base.branches,
  )..where((b) => b.externalId.equals(codigoOId))).getSingleOrNull();
  return porCodigo?.id;
}

final sucursalDelTableroProvider = FutureProvider<String?>((ref) async {
  final mirada = ref.watch(sucursalMiradaProvider);
  if (mirada != null && mirada.isNotEmpty) return mirada;
  final sesion = await ref.watch(almacenSesionProvider).leer();
  final suya = sesion?.sucursalId;
  if (suya == null || suya.isEmpty) return null;
  return _idDeLaSesion(ref.watch(baseProvider), suya);
});

/// Los filtros de la mitad izquierda.
class FiltrosTablero extends Notifier<FiltrosSinColocar> {
  @override
  FiltrosSinColocar build() => const FiltrosSinColocar();

  void poner(FiltrosSinColocar filtros) => state = filtros;

  void limpiar() => state = const FiltrosSinColocar();
}

// AQUI VIVIA `loQueElServidorRechazoProvider`, Y SE QUITO EL 24/09/2026.
//
// Leia la tabla `apuntes` buscando un `rechazado` y solo corria en la web (en el
// aparato devolvia `null` a la primera linea). El problema es que **en un
// navegador esa tabla no se llena nunca**: desde que las escrituras van por
// `EscrituraEnVivo`, los seis sitios que escriben mandan al servidor y esperan
// su respuesta, y el unico que marca `rechazado` es `nucleo/cola/cola_salida.
// dart`, que alli no lo llama nadie. Comprobado: todos los `_cola.encolar` de
// `lib/` estan en la rama `enVivo == null`.
//
// O sea, la franja no podia salir jamas. Y sus dos pruebas —
// `la_franja_avisa_del_rechazo_test.dart` y `la_web_avisa_si_no_subio_test.
// dart`— fabricaban el apunte a mano con `ColaDeSalida.encolar` + `resolver`,
// asi que vigilaban un camino que ya no se ejecuta: verdes, y sin poder fallar
// por el motivo bueno. Una red de seguridad que la gente creeria puesta es peor
// que no tenerla, porque nadie va a buscar la de verdad.
//
// **Hoy no se pierde nada, y por eso se quita entera en vez de reapuntarla**
// (§4, «quitar algo es quitarlo ENTERO»: el provider, su `case` de
// `vista/pantalla_tablero.dart` y las dos pruebas). El «no» del servidor sale en
// el acto y **con su motivo literal** en el mismo gesto que lo provoco, que es
// donde de verdad sirve: la tarjeta ni se mueve, porque el envio va dentro de la
// misma transaccion que la escritura local y el rechazo la deshace entera.
//
// LO QUE LO VIGILA, y son guardas que SI pueden fallar:
//
//  * `test/pantallas/tablero/la_web_coloca_de_verdad_test.dart` — por cada gesto
//    del tablero: el motivo literal llega a quien llamo, la fila no se escribe y
//    `apuntes` se queda a CERO.
//  * `test/pantallas/rutas/la_web_escribe_de_verdad_test.dart` — lo mismo para
//    las cinco acciones de rutas y el cierre.
//
// Si algun dia la web vuelve a encolar algo, el aviso hace falta otra vez — pero
// entonces el fallo es que la web esta encolando (§1), y eso se arregla antes.

final filtrosTableroProvider =
    NotifierProvider<FiltrosTablero, FiltrosSinColocar>(FiltrosTablero.new);

/// EL ALMACÉN DESDE EL QUE SE MIDE, ELEGIDO A MANO — 26/09/2026.
///
/// Jose, mirando la cabecera del tablero: «¿aquí me aparecerá lo de escoger los
/// otros almacenes sólo cuando tenga más almacenes? Porque hace falta que
/// aparezca por lo menos y diga que no está configurado el que no tiene la
/// ubicación puesta».
///
/// Hasta hoy no había nada que elegir: cada sucursal tenía un almacén en Accesos
/// y se llamaba como la sucursal. Ahora están dados de alta los 14 de verdad,
/// leídos de Ventra, y cinco sucursales tienen más de uno — Camagüey tiene tres.
/// Cuál se usa deja de ser evidente, y de los kilómetros hasta el cliente sale
/// lo que se le cobra por el domicilio.
///
/// ## POR SUCURSAL, y por eso es un mapa y no un `String?`
///
/// Un solo valor se arrastraría al cambiar de sucursal: se elige «ALM CAMAGUEY»,
/// se pasa a La Habana y el id de un almacén de Camagüey se quedaría puesto. No
/// rompería nada —`almacenDe` lo ignora porque ese almacén no es de esa
/// sucursal— y eso es justo el problema: mediría desde el principal de La Habana
/// mientras la cabecera dice otra cosa, o al contrario. La elección es «desde
/// dónde mido EN esta sucursal», así que se guarda por sucursal.
///
/// ## NO SE GUARDA EN EL APARATO, a propósito (por ahora)
///
/// La sucursal y la moneda sí se recuerdan entre arranques porque quien trabaja
/// en La Habana trabaja en La Habana todos los días. Esto todavía no: los seis
/// almacenes sin ubicación se van a ir configurando estos días, y una elección
/// guardada apuntando a uno que entonces no servía —y que pasado mañana sí— es
/// un almacén que cambia solo entre arranques. Cuando los 14 estén completos,
/// esto se recuerda igual que la sucursal; hasta entonces, cada sesión arranca
/// en el que manda Accesos.
class AlmacenElegido extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const <String, String>{};

  /// Pone [almacenId] como origen de [sucursalId]. Con `null` se vuelve al que
  /// elige Accesos.
  ///
  /// Aquí NO se comprueba si ese almacén sirve para medir, y es deliberado: esa
  /// pregunta tiene un solo dueño —`AlmacenDeReferencia`— y la contesta
  /// `ConsultasTablero.almacenDe`, que es quien de verdad mide. Comprobarlo
  /// también aquí sería la segunda respuesta a la misma pregunta, esperando a
  /// separarse de la primera sin que salte nada (`CLAUDE.md` §3-bis). Lo que sí
  /// hace la pantalla es no ofrecer los que no sirven.
  void elegir(String sucursalId, String? almacenId) {
    final copia = Map<String, String>.of(state);
    if (almacenId == null) {
      copia.remove(sucursalId);
    } else {
      copia[sucursalId] = almacenId;
    }
    state = copia;
  }
}

final almacenElegidoProvider =
    NotifierProvider<AlmacenElegido, Map<String, String>>(AlmacenElegido.new);

/// Los camiones de la sucursal, para el «camion previsto» de la columna.
///
/// **Stream y no Future** — 17/09/2026. Era un `FutureProvider` que leia la
/// flota UNA vez y no lo invalidaba nadie: si se leia antes de que bajaran los
/// camiones —que en la web es siempre, porque la base nace vacia en cada
/// carga—, el cajon de «Camion previsto» se quedaba con «Sin camion» toda la
/// sesion, y aunque la flota llegara dos segundos despues la lista cacheada no
/// cambiaba.
///
/// Es el mismo patron congelado que dejo Pedidos sin sus desplegables y el
/// tablero sin sus tarjetas. Aqui se corta de raiz: se vigila la tabla.
final camionesProvider = StreamProvider<List<Vehiculo>>((ref) {
  final base = ref.watch(baseProvider);

  Future<List<Vehiculo>> mirar() async {
    final sucursalId = await ref.read(sucursalDelTableroProvider.future);
    final todos = await base.select(base.vehicles).get();
    return todos
        .where((v) => sucursalId == null || v.branchId == sucursalId)
        .toList(growable: false);
  }

  return () async* {
    yield await mirar();
    yield* base
        .tableUpdates(TableUpdateQuery.onTable(base.vehicles))
        .asyncMap((_) => mirar());
  }();
});

/// De cuando son los datos del tablero. Va arriba, con todas las letras: un
/// tablero que parece vivo y lleva seis horas congelado es peor que uno que
/// avisa (§6).
final vistoAtProvider = StreamProvider<DateTime?>(
  (ref) => ref.watch(frescuraProvider).laMasVieja(const [
    EsquemaTablero.coleccionColumnas,
    EsquemaTablero.coleccionColocaciones,
  ]),
);

/// LO QUE PASÓ AL PULSAR «TRAER LO DEL SERVIDOR».
///
/// Existe para que el gesto **conteste**. Antes `bajarDelServidor` devolvía
/// `void` y se tragaba el «sin señal»: se pulsaba, no pasaba nada, y la única
/// huella quedaba en un registro que no lee nadie (28/09/2026, §4).
///
/// El motivo va **literal y en minúscula**, para que la pantalla lo pueda meter
/// dentro de una frase suya sin recortarlo: «No se trajo nada: $motivo.» Lo que
/// no se hace nunca es envolverlo en un «ha ocurrido un error», que es
/// exactamente lo que el §3-quinquies prohíbe.
class LoQuePasoAlTraer {
  /// Se trajo la foto del servidor y el tablero está al día.
  const LoQuePasoAlTraer.seTrajo() : motivo = null;

  /// No se trajo nada, y por esto.
  const LoQuePasoAlTraer.noSePudo(String this.motivo);

  /// `null` sólo cuando se trajo de verdad.
  final String? motivo;

  bool get seTrajo => motivo == null;
}

/// EL TABLERO. Siempre desde la base local, con red y sin ella.
class TableroDelDia extends AsyncNotifier<Tablero> {
  /// La lectura que esta en curso, si la hay.
  Future<void>? _enCurso;

  /// Llego un aviso mientras se leia: hay que volver a leer al terminar.
  bool _otraVez = false;

  @override
  Future<Tablero> build() async {
    final sucursalId = await ref.watch(sucursalDelTableroProvider.future);
    if (sucursalId == null) {
      return const Tablero.imposible('Elige una sucursal para ver su tablero');
    }
    final filtros = ref.watch(filtrosTableroProvider);
    // El almacén elegido a mano. Se MIRA aquí para que cambiarlo vuelva a leer
    // el tablero entero: de ese punto salen los kilómetros de cada tarjeta y el
    // orden de la lista de sin colocar, así que no basta con repintar la
    // cabecera.
    ref.watch(almacenElegidoProvider);
    final base = ref.watch(baseProvider);

    // CON CONEXION, DEL SERVIDOR. Al abrir el tablero y al cambiar de sucursal —
    // y SOLO entonces.
    //
    // **La APK conectada hace lo mismo que la web.** Esa es la arquitectura
    // entera, en una frase de Jose: «cuando las apk estén conectadas deben hacer
    // lo mismo, estar directas a la base de datos del servidor; esto [la copia]
    // es sólo para cuando se quiten de una red y no puedan ver la base de datos
    // del servidor: ahí es donde entra el sync».
    //
    // ## POR SUCURSAL Y NO POR CADA `build`
    //
    // `build` mira tambien `filtrosTableroProvider`, asi que **cada filtro lo
    // vuelve a ejecutar**. Sin esta guarda, abrir el cajon de filtros y tocar
    // cuatro cosas eran cuatro descargas completas del tablero: la pantalla en
    // blanco, la rueda girando y una ida y vuelta por la conexion de alla —que el
    // propio cliente documenta en 55 s en el caso normal y 115 s en el peor—
    // **por un filtro que es local y no necesita servidor para nada**.
    //
    // ## AQUI Y NO EN `_leer`, o es un bucle
    //
    // `descargar` ESCRIBE en las tablas del tablero, y ahi abajo hay un
    // `tableUpdates` que llama a `refrescar()` con cada escritura. Pidiendolo en
    // cada lectura: descargar → cambian las tablas → refrescar → leer →
    // descargar… sin parar.
    //
    // Lo demas ya esta cubierto: el ciclo del sincronizador, el canal en vivo y
    // el boton de refrescar.
    if (sucursalId != _sucursalYaBajada) {
      _sucursalYaBajada = sucursalId;
      // El aviso de la sucursal anterior se va: «hay 1 zona sin subir» de Holguin
      // no es verdad en el tablero de La Habana.
      _porQueNoSeRefresca = null;
      _yaSeReintento = false;
      await _traerDelServidor(sucursalId);
    }

    // Y EL AVISO EN VIVO DEL SERVIDOR.
    //
    // Sin esto el canal funcionaba y no servia de nada. El aviso disparaba el
    // ciclo de sincronizacion, y **el tablero no viaja en el ciclo**: la bajada
    // por diferencias sirve pedidos, clientes, rutas y catalogo, y las zonas se
    // piden aparte con `GET /api/board`, que sólo se llamaba al abrir la
    // pantalla. Se vio con el telefono delante: la zona subia con un 201, el
    // servidor registraba la conexion abierta, y la web seguia igual hasta que
    // pasaba el temporizador de dos minutos.
    //
    // Se mira el TIPO: un cambio de clientes o de catalogo no tiene por que
    // costar una foto entera del tablero.
    //
    // `descargar` trae y escribe, y esa escritura despierta al `tableUpdates` de
    // aqui abajo, que repinta. No hay bucle: la bajada no cambia nada de lo que
    // `build` observa.
    final enVivo = ref
        .watch(avisosDelServidorProvider)
        // La constante, no el literal. Era el ultimo sitio de `app/lib` que
        // comparaba a mano, y el docstring de `CambioEnVivo` ya lo nombraba
        // como el motivo por el que se creo — o sea, un comentario que daba por
        // hecho un cambio que no se habia hecho.
        .where((tipo) => tipo == CambioEnVivo.tablero)
        .listen((_) async {
          await _traerDelServidor(sucursalId);
          await refrescar();
        });
    ref.onDispose(enVivo.cancel);

    final sub = base
        .tableUpdates(
          TableUpdateQuery.allOf([
            TableUpdateQuery.onTableName(EsquemaTablero.columnas),
            TableUpdateQuery.onTableName(EsquemaTablero.colocaciones),
            TableUpdateQuery.onTable(base.orders),
            // ALMACENES Y SUCURSALES, que faltaban y dejaban la pantalla muerta.
            //
            // El tablero se ordena desde el punto del que sale la mercancia. Si
            // ese almacen todavia no esta en la copia, `_leer` devuelve «La
            // Habana no tiene ningun almacen con coordenadas» — que ademas es
            // FALSO: lo tiene, lo que pasa es que todavia no habia bajado.
            //
            // Mientras la copia era un fichero que sobrevivia, eso casi nunca se
            // veia: los almacenes ya estaban de la vez anterior. **En la web ya
            // no**: desde que su base es en memoria, cada carga empieza vacia, y
            // sin esto la pantalla se quedaba con ese mensaje **para siempre** —
            // `build` no se vuelve a ejecutar solo, y los almacenes llegan por el
            // ciclo, que toca otra tabla.
            TableUpdateQuery.onTable(base.warehouses),
            TableUpdateQuery.onTable(base.branches),
            // LA COLA, para enterarse de cuando deja de haber trabajo sin subir.
            //
            // El tablero se niega a bajar mientras quede algo sin subir —para no
            // pisarlo, que es la regla que no se negocia— y lo DICE arriba: «No
            // se actualiza: hay 1 cambio sin subir». Ese texto se escribia al
            // intentar la bajada y **no lo recalculaba nadie**: el apunte subia
            // cuatro segundos despues y el cartel se quedaba puesto.
            //
            // Jose, 17/09/2026, con el telefono delante: «ahi en el movil me
            // sale como que no se ha subido aun, ¿por que razon me sale eso si
            // ya esta?».
            TableUpdateQuery.onTable(base.apuntes),
          ]),
        )
        .listen((_) => unawaited(_alCambiarLasTablas(sucursalId)));
    ref.onDispose(sub.cancel);

    return _leer(sucursalId, filtros);
  }

  /// Algo cambio en las tablas que pinta el tablero. Casi siempre es repintar y
  /// ya; la excepcion es la carrera de la web.
  ///
  /// **La carrera:** la web abre con la base vacia, el tablero pide `/board`
  /// nada mas pintarse y los pedidos llegan despues por el ciclo, que es otro
  /// camino. Las tarjetas llegan primero y se caen todas —una colocacion
  /// necesita su pedido—, y como la foto no se vuelve a pedir, la zona se queda
  /// a cero con sus pedidos en «Sin colocar». Eso es lo que vio Jose: «Vista»
  /// con 6 pedidos en el telefono y «Vista (0)» en la web.
  ///
  /// Aqui es donde se cierra: la llegada de los pedidos ES una escritura en la
  /// tabla `orders`, o sea este mismo aviso. Se vuelve a pedir la foto **una
  /// sola vez por sucursal**, que es lo que hace falta y no mas.
  Future<void> _alCambiarLasTablas(String sucursalId) async {
    // YA NO QUEDA NADA SIN SUBIR: se vuelve a intentar la bajada que se negó.
    //
    // Sin esto el cartel de «no se actualiza» se queda puesto hasta que alguien
    // pulse refrescar o cambie de sucursal, diciendo algo que dejó de ser verdad
    // hace rato. Y el tablero, mientras, sin bajar.
    if (_porQueNoSeRefresca != null && await _yaNoQuedaNadaSinSubir()) {
      Registro.info('tablero: ya subió lo que faltaba; se vuelve a bajar');
      await _traerDelServidor(sucursalId);
    }
    if (_faltabanPedidos && !_yaSeReintento) {
      _yaSeReintento = true;
      Registro.info(
        'tablero: la foto traía tarjetas sin pedido y los pedidos ya están; '
        'se vuelve a pedir',
      );
      await _traerDelServidor(sucursalId);
    }
    await refrescar();
  }

  Future<Tablero> _leer(String sucursalId, FiltrosSinColocar filtros) async {
    final consultas = ref.read(consultasTableroProvider);
    // Antes de leer, los `local-…` que ya tengan id de verdad. Si no, la
    // pantalla sigue ensenando el provisional hasta la proxima bajada.
    await ref.read(repositorioTableroProvider).asentarProvisionales();

    final nombre = await consultas.nombreDeSucursal(sucursalId);
    // TODOS los de la sucursal, también los que no tienen la ubicación puesta:
    // es la lista que se ofrece al tocar la cabecera, y se lee ANTES del `try`
    // porque hace falta igual cuando no hay ninguno con coordenadas — ése es
    // justamente el caso en que quien mira necesita ver que sí tiene almacenes y
    // que lo que les falta es el punto.
    final almacenes = await consultas.almacenesDeLaSucursal(sucursalId);
    final AlmacenOrigen almacen;
    try {
      almacen = await consultas.almacenDe(
        sucursalId,
        preferido: ref.read(almacenElegidoProvider)[sucursalId],
      );
    } on SinAlmacenConCoordenadas catch (e) {
      // Se ordena desde el sitio del que sale la mercancia o no se ordena: no
      // se inventa un punto de partida.
      return Tablero.imposible(
        e.mensaje,
        sucursalId: sucursalId,
        sucursalNombre: nombre,
      );
    }
    return Tablero(
      sucursalId: sucursalId,
      sucursalNombre: nombre,
      almacen: almacen,
      almacenes: almacenes,
      columnas: await consultas.columnas(sucursalId),
      colocados: await consultas.colocados(sucursalId, almacen),
      avisos: await consultas.avisos(sucursalId),
      sinColocar: await consultas.sinColocar(
        sucursalId,
        almacen,
        filtros: filtros,
      ),
      desaparecidos: await consultas.desaparecidos(),
      vistoAt:
          (await ref
                  .read(frescuraProvider)
                  .leer(EsquemaTablero.coleccionColocaciones))
              ?.bajadaAt,
    );
  }

  /// Vuelve a leer la base **sin pintar el cargando**: lo que acaba de moverse
  /// no puede parpadear.
  ///
  /// Si ya hay una lectura en marcha se APUNTA que hay que volver a leer y se
  /// devuelve la misma espera, en vez de descartar el aviso. Descartarlo deja
  /// la pantalla ensenando lo de antes del ultimo cambio, que es exactamente el
  /// fallo que nadie sabe reproducir: «a veces la tarjeta se queda en la
  /// columna vieja». Y devolver la espera buena es lo que hace que quien llama
  /// —un gesto, o una prueba— pueda fiarse de que al volver ya esta puesto.
  /// La sucursal cuya foto ya se pidio. Sin esto, cada filtro era una descarga.
  String? _sucursalYaBajada;

  /// La ultima foto trajo tarjetas que no se pudieron poner: les faltaba el
  /// pedido. Se vuelve a pedir **una vez**, cuando los pedidos lleguen.
  bool _faltabanPedidos = false;

  /// Que ya se reintento por esto en esta sucursal. Es el tope: sin el, una
  /// tarjeta de un pedido que este aparato no va a tener nunca —archivado, de
  /// otra sucursal— pediria la foto entera con cada escritura de la tabla de
  /// pedidos, para siempre.
  bool _yaSeReintento = false;

  /// ¿Se vació la cola? Es la señal de que el motivo por el que no se bajaba ya
  /// no existe.
  ///
  /// Se pregunta por lo MISMO que preguntó la negativa —lo pendiente y lo que
  /// nació aquí y no está arriba—, que es lo que mira `descargar`. Preguntar
  /// sólo por la cola dejaría el cartel puesto cuando lo que queda es una zona
  /// huérfana, y al revés.
  Future<bool> _yaNoQuedaNadaSinSubir() async {
    try {
      return await ref.read(baseProvider).cuantosPendientes() == 0;
    } on Object catch (e) {
      Registro.aviso('tablero: no se pudo mirar si queda algo sin subir: $e');
      return false;
    }
  }

  /// Trae la foto del servidor y **se queda con el porque si no se pudo**.
  ///
  /// ## Lo que se traga y lo que NO — 17/09/2026
  ///
  /// `FalloDeRed` es lo normal sin señal y se sigue con lo de aqui, que es para
  /// lo que esta la copia. Lo demas hay que cogerlo tambien, y faltaba:
  ///
  ///  * un **403** —«esa sucursal no es tuya»— salia de `build` y el future del
  ///    provider **no se completaba nunca**: la pantalla se quedaba con la rueda
  ///    girando para siempre, sin el mensaje del servidor y **sin pintar la copia
  ///    local, que lo tenia todo**;
  ///  * un **401** terminal, igual;
  ///  * y un cuerpo que no se entiende llegaba a la pantalla de error con un
  ///    `type 'Null' is not a subtype of type 'String'`, que no le dice nada a
  ///    nadie.
  ///
  /// Ninguna de esas tres puede impedir ver el tablero: lo que hay en el aparato
  /// se pinta igual, y lo que pasó se DICE arriba.
  Future<void> _traerDelServidor(String sucursalId) async {
    try {
      final r = await ref.read(servicioTableroProvider).descargar(sucursalId);
      // Y si la bajada se NEGO —queda trabajo sin subir—, se dice. Antes se
      // tiraba el resultado y la barra enseñaba «Visto por última vez a las …»
      // con una hora congelada, como si estuviera al día.
      _porQueNoSeRefresca = r.porQue;
      // Tarjetas que el servidor mandó y no se pudieron poner porque su pedido
      // todavía no está en esta base. Se apunta para volver a pedir la foto en
      // cuanto lleguen; el porqué, en `ResultadoDeBajarElTablero`.
      _faltabanPedidos = r.tarjetasSinPedido > 0;
    } on FalloDeRed catch (e) {
      _porQueNoSeRefresca = null;
      Registro.info(
        'tablero: sin conexión al abrir, se sigue con lo de aquí ($e)',
      );
    } on Rechazo catch (e) {
      // El literal del servidor, que es lo único que le dice a alguien qué hacer.
      _porQueNoSeRefresca = e.mensaje;
      Registro.aviso('tablero: el servidor dijo que no al bajar: ${e.mensaje}');
    } on SesionMuerta catch (e) {
      _porQueNoSeRefresca = 'la sesión se perdió: hace falta volver a entrar';
      Registro.aviso('tablero: sesión muerta al bajar ($e)');
    } on Object catch (e, pila) {
      // EL SUELO. Cualquier otra cosa —un cuerpo que no cuadra, un fallo al
      // escribir— deja el tablero con lo que hay, no con una rueda eterna.
      _porQueNoSeRefresca = 'no se pudo traer del servidor';
      Registro.fallo('tablero: no se pudo bajar: $e', e, pila);
    }
  }

  Future<void> refrescar() {
    final enCurso = _enCurso;
    if (enCurso != null) {
      _otraVez = true;
      return enCurso;
    }
    final futuro = _bucleDeLectura();
    _enCurso = futuro;
    return futuro;
  }

  Future<void> _bucleDeLectura() async {
    try {
      do {
        _otraVez = false;
        // El aviso puede llegar cuando la pantalla ya se fue: el `Stream` de
        // Drift no se calla al instante. Escribir en un provider muerto revienta
        // con un error que no dice nada de lo que pasaba.
        if (!ref.mounted) return;
        final sucursalId =
            state.value?.sucursalId ??
            await ref.read(sucursalDelTableroProvider.future);
        if (sucursalId == null || sucursalId.isEmpty) return;
        final tablero = await _leer(
          sucursalId,
          ref.read(filtrosTableroProvider),
        );
        if (!ref.mounted) return;
        state = AsyncValue<Tablero>.data(tablero);
      } while (_otraVez);
    } on Object catch (e, pila) {
      if (ref.mounted) state = AsyncValue<Tablero>.error(e, pila);
    } finally {
      _enCurso = null;
    }
  }

  /// Pide el tablero al servidor. Sin senal **no es un fallo**: se sigue con lo
  /// que hay en el aparato, que es justo para lo que esta.
  /// Lo ultimo que impidio refrescar, para poder DECIRLO. `null` = nada lo
  /// impide.
  ///
  /// Sin esto, pulsar «actualizar» con trabajo sin subir no hacia nada visible:
  /// la negativa se escribia en el registro. Quien estaba delante no sabia si es
  /// que no habia cambios o que la aplicacion se estaba protegiendo, y volvia a
  /// pulsar.
  String? get porQueNoSeRefresca => _porQueNoSeRefresca;
  String? _porQueNoSeRefresca;

  /// PULSAR «TRAER LO DEL SERVIDOR» **CONTESTA**, PASE LO QUE PASE — 28/09/2026.
  ///
  /// Jose, con el teléfono sin señal: se pulsa y «ni error, ni aviso, ni nada».
  /// Los datos se quedan como estaban y quien lo pulsó no tiene forma de saber
  /// si es que no había nada nuevo, si se está trayendo todavía o si no se
  /// pudo. Se vuelve a pulsar, y otra vez nada.
  ///
  /// Estaba escrito a propósito —«sin señal no hay nada que avisar»— y era
  /// verdad a medias: lo que no hay que avisar es el **ciclo** que corre solo
  /// cada dos minutos, y ése sigue callado (`_traerDelServidor`). Un gesto es
  /// otra cosa: alguien puso el dedo ahí esperando algo. El §4 no admite
  /// matices —si algo falla, la pantalla no se queda verde— y el §3-quinquies
  /// sólo pide que el aviso **no salga siempre**: éste sale cuando se pulsa, y
  /// no en cada vuelta del reloj.
  ///
  /// Y se devuelve, no se pinta desde aquí: quien sabe dónde sale un aviso es
  /// la pantalla, no el estado. Aquí se dice QUÉ pasó y con qué motivo literal
  /// —«Sin conexión con el servidor.», «hay 1 cambio sin subir»—, porque «no se
  /// pudo actualizar» no le dice a nadie qué hacer.
  Future<LoQuePasoAlTraer> bajarDelServidor() async {
    final sucursalId = state.value?.sucursalId;
    if (sucursalId == null || sucursalId.isEmpty) {
      // No es un fallo del servidor, pero tampoco se hizo nada, y callarlo es
      // el mismo agujero: el botón existe en la barra y hay que poder pulsarlo
      // sin quedarse sin respuesta.
      return const LoQuePasoAlTraer.noSePudo(
        'todavía no se sabe qué sucursal se está mirando',
      );
    }
    try {
      final r = await ref.read(servicioTableroProvider).descargar(sucursalId);
      _porQueNoSeRefresca = r.porQue;
      await refrescar();
      // NEGARSE A BAJAR **TAMBIÉN ES NO HABER TRAÍDO NADA**, y por eso cuenta
      // como que el gesto no se hizo. Es la protección que no se negocia —la
      // foto del servidor no puede pisar lo que aún no subió— y sale ya en la
      // franja de arriba; lo que faltaba es que contestara al dedo que la
      // acaba de pulsar, en el acto y en el mismo sitio donde salen los demás
      // «no».
      if (r.porQue case final porQue?) {
        return LoQuePasoAlTraer.noSePudo('hay $porQue');
      }
      return const LoQuePasoAlTraer.seTrajo();
    } on FalloDeRed catch (e) {
      // EL CARTEL VIEJO SE VA, PERO EL GESTO SE CONTESTA.
      //
      // Lo primero ya estaba y se queda: la aplicación se negaba una vez con
      // trabajo sin subir, se subía la cola, se volvía a pulsar sin señal, y el
      // cartel seguía en pantalla diciendo algo que ya no era verdad. Un aviso
      // que no se retira deja de ser un aviso.
      //
      // Lo segundo es lo que faltaba: sin señal no se trajo nada, y eso hay que
      // decirlo aquí y ahora. La franja de arriba no sirve para esto —habla de
      // la copia, no del gesto— y encima acaba de quedarse en blanco.
      _porQueNoSeRefresca = null;
      Registro.info('tablero: sin conexion, se sigue con lo de aqui ($e)');
      return const LoQuePasoAlTraer.noSePudo(
        'no hay conexión con el servidor. Se sigue con lo que hay en este '
        'aparato',
      );
    } on Rechazo catch (e) {
      // El literal del servidor: «Esa sucursal no es tuya» le dice a alguien
      // qué hacer; «no se pudo actualizar», no.
      _porQueNoSeRefresca = e.mensaje;
      await refrescar();
      Registro.aviso('tablero: el servidor dijo que no al traer: ${e.mensaje}');
      return LoQuePasoAlTraer.noSePudo(e.mensaje);
    } on SesionMuerta catch (e) {
      _porQueNoSeRefresca = 'la sesión se perdió: hace falta volver a entrar';
      await refrescar();
      Registro.aviso('tablero: sesión muerta al traer ($e)');
      return const LoQuePasoAlTraer.noSePudo(
        'la sesión se perdió: hace falta volver a entrar',
      );
    } on Object catch (e, pila) {
      // EL SUELO, igual que en `_traerDelServidor`. Antes esto ni se cogía: el
      // botón lanzaba un `unawaited` y un cuerpo que no cuadra se iba como
      // error asíncrono sin dueño — o sea, en silencio, que es el fallo que
      // esta función viene a cerrar.
      _porQueNoSeRefresca = 'no se pudo traer del servidor';
      await refrescar();
      Registro.fallo('tablero: no se pudo traer al pulsar: $e', e, pila);
      return const LoQuePasoAlTraer.noSePudo('no se pudo traer del servidor');
    }
  }

  // ---------------------------------------------------------------------
  // Los gestos. Ninguno llama a nadie: escriben aqui y van a la cola.
  // ---------------------------------------------------------------------

  Future<void> colocar({
    required String pedidoId,
    required String columnaId,
    int? posicion,
  }) async {
    await ref
        .read(repositorioTableroProvider)
        .colocar(pedidoId: pedidoId, columnaId: columnaId, posicion: posicion);
    await refrescar();
  }

  Future<void> quitar(String pedidoId) async {
    await ref.read(repositorioTableroProvider).quitar(pedidoId);
    await refrescar();
  }

  Future<String> crearColumna(String nombre, {String? vehiculoId}) async {
    final sucursalId = state.value?.sucursalId;
    if (sucursalId == null || sucursalId.isEmpty) {
      throw const FaltaElegirSucursal();
    }
    final id = await ref
        .read(repositorioTableroProvider)
        .crearColumna(
          sucursalId: sucursalId,
          nombre: nombre,
          vehiculoId: vehiculoId,
        );
    await refrescar();
    return id;
  }

  Future<void> renombrar(String columnaId, String nombre) async {
    await ref
        .read(repositorioTableroProvider)
        .renombrarColumna(columnaId, nombre);
    await refrescar();
  }

  Future<void> elegirCamion(String columnaId, String? vehiculoId) async {
    await ref
        .read(repositorioTableroProvider)
        .elegirCamion(columnaId, vehiculoId);
    await refrescar();
  }

  Future<void> reordenar(List<String> idsEnOrden) async {
    final sucursalId = state.value?.sucursalId;
    if (sucursalId == null || sucursalId.isEmpty) return;
    await ref
        .read(repositorioTableroProvider)
        .reordenarColumnas(sucursalId, idsEnOrden);
    await refrescar();
  }

  Future<int> vaciar(String columnaId) async {
    final cuantos = await ref
        .read(repositorioTableroProvider)
        .vaciarColumna(columnaId);
    await refrescar();
    return cuantos;
  }

  Future<int> moverTodo(String origenId, String destinoId) async {
    final cuantos = await ref
        .read(repositorioTableroProvider)
        .moverTodo(origenId, destinoId);
    await refrescar();
    return cuantos;
  }

  Future<void> borrarColumna(
    String columnaId, {
    bool vaciar = false,
    String? destinoId,
  }) async {
    await ref
        .read(repositorioTableroProvider)
        .borrarColumna(columnaId, vaciar: vaciar, destinoId: destinoId);
    await refrescar();
  }

  Future<String> armarRuta(String columnaId, {String? nombre}) async {
    final tablero = state.value;
    if (tablero == null || tablero.problema != null) {
      throw const FaltaElegirSucursal();
    }
    final rutaId = await ref
        .read(repositorioTableroProvider)
        .armarRuta(
          columnaId: columnaId,
          origen: tablero.almacen,
          sucursalId: tablero.sucursalId,
          nombre: nombre,
        );
    await refrescar();
    return rutaId;
  }

  /// El aviso de los pedidos que ya no estan en PEDIDO se da una vez.
  Future<void> olvidarDesaparecidos() async {
    await ref.read(repositorioTableroProvider).olvidarDesaparecidos();
    await refrescar();
  }
}

final tableroProvider = AsyncNotifierProvider<TableroDelDia, Tablero>(
  TableroDelDia.new,
);

/// LOS RENGLONES DE UN PEDIDO, para el cajón de moverlo — 28/09/2026.
///
/// Jose: «ahi en tablero q cuando le den para mover en ves de solo decir q lo
/// vamos a mover q me salga el detalle de el pedido ok».
///
/// El cajón de mover enseñaba el cliente, el peso y los km, y nada más. Y ese es
/// el instante en el que alguien decide a qué zona va ese bulto: para decidirlo
/// hace falta saber QUÉ bulto es. Lo demás del pedido ya viaja en `TarjetaPedido`
/// —dirección, municipio, vendedor, factura, costo—; lo único que no estaba son
/// los artículos, y son justo lo que se carga en el camión.
///
/// ## POR STREAM Y NO POR FUTURE, que es el §3-ter y ya costó una vez
///
/// Está copiado del molde de `renglonesDePaginaProvider` (Pedidos), y su
/// comentario cuenta el incidente entero: en la bajada `orders` va ANTES que
/// `order_items`, así que una respuesta pedida una sola vez —al abrir el cajón—
/// se queda con lo que hubiera en ese instante. En la web la base nace vacía en
/// cada carga, de modo que el cajón diría **«sin artículos»** sobre un pedido con
/// doce líneas. Y «sin artículos» no se lee como «todavía no ha llegado»: se lee
/// como que ese pedido no lleva nada.
///
/// Se vigilan las DOS tablas de las que sale la lista: `order_items` y
/// `products` —el peso por empaque se resuelve contra el catálogo, que baja aún
/// más tarde—.
///
/// El coste está acotado de sobra: son los renglones de UN pedido, y sólo
/// mientras el cajón está abierto (`autoDispose`).
final renglonesDelPedidoProvider = StreamProvider.autoDispose
    .family<List<RenglonConPeso>, String>((ref, pedidoId) {
      final base = ref.watch(baseProvider);
      final consultas = ref.watch(consultasPedidosProvider);

      Future<List<RenglonConPeso>> mirar() async =>
          (await consultas.renglonesDe([pedidoId]))[pedidoId] ?? const [];

      return () async* {
        // El primero enseguida: `tableUpdates` no emite al suscribirse, y sin
        // esto la lista arrancaría vacía aunque los renglones ya estuvieran.
        yield await mirar();
        yield* base
            .tableUpdates(
              TableUpdateQuery.onAllTables([base.orderItems, base.products]),
            )
            .asyncMap((_) => mirar());
      }();
    });
