import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/cola/cola_salida.dart';
import '../../../nucleo/cola/provisionales.dart';
import '../../../nucleo/red/escritura_en_vivo.dart';
import '../../../nucleo/reloj.dart';
import '../../rutas/datos/geo.dart';
import '../../rutas/datos/importe_de_la_ruta.dart';
import 'consultas.dart';
import 'esquema.dart';
import 'modelos.dart';

/// LAS ESCRITURAS DEL TABLERO.
///
/// La regla que manda sobre todas las demas de esta pantalla, **en la APK y en
/// el escritorio**:
///
/// > **Arrastrar no llama a nadie.** Se escribe en la base local y se encola el
/// > apunte, las dos cosas en LA MISMA transaccion. La subida va por detras,
/// > cuando haya senal.
///
/// El porque no es una preferencia tecnica: preparar el tablero es el trabajo de
/// la tarde, y la tarde es cuando no hay senal. Una pantalla que espera a que el
/// servidor conteste para mover la tarjeta no se puede usar a la hora a la que
/// se usa.
///
/// Y la transaccion unica tampoco es un adorno: si la colocacion se guardara y
/// el apunte no, la tarjeta se habria movido en el aparato y no habria nadie
/// que lo fuera a contar nunca. Al reves —el apunte sin la colocacion— la
/// pantalla ensenaria una cosa y el servidor otra.
///
/// # EN LA WEB, ARRASTRAR SÍ LLAMA — 22/09/2026
///
/// Medido en produccion: se colocaba una tarjeta, la ficha se cerraba, la
/// tarjeta seguia donde estaba y «Vista (0)» seguia en 0. La cola del navegador
/// no subia NADA —`POST /sync/aparato` contestaba 401, porque en un navegador no
/// hay par de tokens que dar de alta— y la base de la web es en memoria, asi que
/// el apunte moria con la pestana. Ni un mensaje.
///
/// `CLAUDE.md` §1: «la web siempre esta en vivo porque saca de la base de datos
/// de la nube, no de una extra». Asi que cuando hay [EscrituraEnVivo] el apunte
/// no se encola: **se manda al servidor y se espera**, y va EN EL MISMO SITIO en
/// el que iba el apunte —dentro de la transaccion—. Eso es lo que sostiene la
/// regla entera: si el servidor dice que no, [_mandarOEncolar] lanza, Drift
/// deshace la transaccion y **la tarjeta no se movio**. No hay un instante en el
/// que la pantalla ensene como hecho algo que el servidor rechazo, y el motivo
/// que sale es el suyo, literal (`CLAUDE.md` §3-quinquies).
///
/// No hizo falta ni un endpoint nuevo: las siete escrituras del tablero ya
/// estaban montadas en `api/internal/api/tablero.go`, y la web ya se autentica
/// contra `/api/*` con la cookie de Accesos (`nucleo/red/escritura_en_vivo.dart`
/// lo cuenta entero).
/// QUIÉN SE CAYÓ Y POR QUÉ, NOMBRADO, venga en un «no» o en un «sí».
///
/// Se sacó aquí fuera el 28/09/2026 porque **hacía falta en los dos sitios y sólo
/// estaba en uno**. El servidor manda `descartados` en el 409 de una zona que no
/// se puede armar —eso ya se leía— y **también en el 201 de una que sí se armó
/// pero dejando tarjetas fuera**, y ese segundo se tiraba entero.
///
/// El daño: en la web la ruta salía con menos pedidos de los que el logístico
/// puso, con un «Ruta armada» verde encima y sin una palabra de quién faltaba.
/// En la APK ya se avisa desde hoy (va al cajón de entregar el día); aquí no.
/// Es el §4: nada se descarta en silencio, y se dice **qué se rompe sin ello**.
///
/// Devuelve una línea por descartado, `folio · cliente: motivo`. Vacía cuando no
/// se cayó nadie, que es lo normal y no se enseña — un aviso que sale siempre
/// deja de leerse (§3-quinquies).
List<String> descartadosDeLaRespuesta(Object? cuerpo) {
  if (cuerpo is! Map<Object?, Object?>) return const [];
  final crudos = cuerpo['descartados'];
  if (crudos is! List) return const [];
  final detalles = <String>[];
  for (final d in crudos) {
    if (d is! Map<Object?, Object?>) continue;
    final quien = d['operationNumber'] ?? d['pedidoId'];
    final cliente = d['customerName'];
    final motivo = d['motivo'];
    detalles.add(
      [
            if (quien is String && quien.isNotEmpty) quien,
            if (cliente is String && cliente.isNotEmpty) cliente,
          ].join(' · ') +
          (motivo is String && motivo.isNotEmpty ? ': $motivo' : ''),
    );
  }
  return detalles;
}

class RepositorioTablero {
  RepositorioTablero(
    this._base,
    this._cola, {
    Reloj reloj = relojDelAparato,
    EscrituraEnVivo? enVivo,
  }) : _reloj = reloj,
       _enVivo = enVivo;

  final BaseLocal _base;
  final ColaDeSalida _cola;
  final Reloj _reloj;

  /// Quien manda el gesto al servidor y espera. `null` en la APK y en el
  /// escritorio, que es donde la cola es la respuesta correcta. Lo decide
  /// `estado/proveedores.dart`, no un `kIsWeb` metido aqui dentro.
  final EscrituraEnVivo? _enVivo;

  /// POR DONDE SALE EL GESTO: al servidor en el acto, o a la cola.
  ///
  /// Se llama exactamente donde se llamaba a `_cola.encolar`, ni una linea antes
  /// ni una despues, y eso es deliberado: dentro de la transaccion que acaba de
  /// escribir la fila. Si el servidor dice que no, esto lanza y Drift deshace
  /// **todo** lo de esa transaccion.
  ///
  /// El «no» sale como [RechazoDelTablero], que es lo que caza
  /// `vista/acciones.dart` y lo que pinta con su texto tal cual, sin envolverlo
  /// en «Ha ocurrido un error».
  Future<Object?> _mandarOEncolar({
    required String metodo,
    required String ruta,
    Map<String, Object?> cuerpo = const <String, Object?>{},
    String? provisional,
  }) async {
    final enVivo = _enVivo;
    if (enVivo == null) {
      await _cola.encolar(
        metodo: metodo,
        ruta: ruta,
        cuerpo: cuerpo,
        provisional: provisional,
      );
      return null;
    }
    try {
      return await enVivo.mandar(metodo: metodo, ruta: ruta, cuerpo: cuerpo);
    } on RechazoDelServidor catch (no) {
      throw _comoRechazo(no);
    }
  }

  /// El «no» del servidor traducido SIN PERDER LO QUE TRAE AL LADO.
  ///
  /// La frase sola no siempre basta y aquí hay dos casos concretos en los que
  /// perderla es perder lo que le dice a la persona qué hacer:
  ///
  ///  * `descartados`, del 409 de armar la ruta de una zona: quién se cayó y por
  ///    qué, uno a uno. «La columna no tiene ningún pedido que se pueda repartir
  ///    hoy» sobre doce tarjetas, sin decir cuáles ni por qué, es el aviso que
  ///    hace que el logístico deje de fiarse del tablero (tablero.md §5.2). Se
  ///    formatea IGUAL que lo formatea el camino de aquí, que es lo que pinta
  ///    `vista/acciones.dart`.
  ///  * `pedidos`, del 409 de borrar una zona: el número que decide si hay que
  ///    vaciar dos tarjetas o mover ochenta.
  static RechazoDelTablero _comoRechazo(RechazoDelServidor no) {
    final cuerpo = no.cuerpo;
    if (cuerpo is! Map<Object?, Object?>) return RechazoDelTablero(no.motivo);

    final cuantos = cuerpo['pedidos'];
    final detalles = descartadosDeLaRespuesta(cuerpo);
    return RechazoDelTablero(
      no.motivo,
      pedidos: cuantos is num ? cuantos.toInt() : null,
      detalles: detalles,
    );
  }

  /// LA MARCA DE «esto de aquí todavía no está arriba»: `1` en el aparato, `0`
  /// en la web.
  ///
  /// `nacio_aqui` existe para una sola cosa: que «actualizar» no borre trabajo
  /// que sólo vive en este aparato. **En un navegador ese trabajo no existe** —
  /// aquí no se escribe una fila hasta que el servidor la ha aceptado— así que
  /// la marca es falsa por definición.
  ///
  /// Y dejarla puesta no era inofensivo, que es lo que la trae aquí: el ciclo
  /// pasa por `Huerfanos.volverAEncolar` ANTES de subir, y ése busca justamente
  /// las filas con `nacio_aqui = 1` que no tienen apunte vivo detrás — o sea,
  /// **todas las de la web**— y las vuelve a encolar. Con eso la cola se llena
  /// otra vez, el ciclo vuelve a pedir `POST /sync/aparato` y vuelve a comerse
  /// su 401: el fallo del 22/09/2026 entero, reconstruido por la espalda.
  ///
  /// La otra mitad de la marca —que la bajada se niegue para no pisar lo que no
  /// subió— ya estaba apagada en la web desde el 16/09/2026 (`datos/servicio.dart`,
  /// «EN LA WEB NO HAY NADA QUE PROTEGER»). Esto la apaga por el otro lado.
  int get _nacioAqui => _enVivo == null ? 1 : 0;

  String get _tablaColumnas => EsquemaTablero.columnas;
  String get _tablaColocaciones => EsquemaTablero.colocaciones;

  Future<void> _listo() => EsquemaTablero.asegurar(_base);

  /// La hora del APARATO, ya en el formato en el que la guarda el resto de la
  /// base.
  ///
  /// Se escribe al hacer el gesto y no al subirlo: lo que se coloca a las
  /// cuatro llega como las cuatro aunque suba a las siete (regla 7). Y la
  /// conversion la hace `typeMapping`, la misma pieza de Drift que escribe las
  /// fechas de las demas tablas: escribirla a mano aqui seria tener dos
  /// formatos de fecha en el mismo fichero.
  Object? get _ahora => _base.typeMapping.mapToSqlVariable(_reloj());

  // -------------------------------------------------------------------------
  // Arrastrar
  // -------------------------------------------------------------------------

  /// Colocar O mover: es la MISMA orden. Soltar una tarjeta en una columna es
  /// decir «este pedido va aqui», venga de la mitad izquierda o de otra columna.
  ///
  /// Los tres pasos son los del servidor, y en el mismo orden, porque tienen
  /// que dar el mismo tablero: se saca de donde estuviera y se cierra su hueco,
  /// se abre hueco en el destino, y se mete. Repetido sobre el tablero que ya
  /// quedo, el paso 1 y el 2 se cancelan: **es reaplicable**, que es lo que hace
  /// falta cuando el lote se reintenta.
  ///
  /// [posicion] empieza en 1. Sin ella, al final de la columna.
  Future<void> colocar({
    required String pedidoId,
    required String columnaId,
    int? posicion,
  }) async {
    await _listo();
    await _base.transaction(() async {
      final anterior = await _base
          .customSelect(
            'SELECT column_id, posicion FROM $_tablaColocaciones '
            'WHERE order_id = ?1',
            variables: [Variable<String>(pedidoId)],
          )
          .getSingleOrNull();

      if (anterior != null) {
        final deColumna = anterior.read<String>('column_id');
        final deposicion = anterior.read<int>('posicion');
        await _base.customStatement(
          'DELETE FROM $_tablaColocaciones WHERE order_id = ?1',
          [pedidoId],
        );
        // Cerrar el hueco no es imprescindible —el orden se lee, no se
        // cuenta— pero sin ello las posiciones se van separando hasta que un
        // dia alguien lee «la parada numero 47» de una columna de nueve.
        await _base.customStatement(
          'UPDATE $_tablaColocaciones SET posicion = posicion - 1 '
          'WHERE column_id = ?1 AND posicion > ?2',
          [deColumna, deposicion],
        );
      }

      final cuantos = await _cuantosEn(columnaId);
      final donde = (posicion ?? cuantos + 1).clamp(1, cuantos + 1).toInt();

      await _base.customStatement(
        'UPDATE $_tablaColocaciones SET posicion = posicion + 1 '
        'WHERE column_id = ?1 AND posicion >= ?2',
        [columnaId, donde],
      );
      await _base.customStatement(
        // Igual que la zona: esta tarjeta se arrastro aqui y todavia no esta
        // arriba. Sin esto, «actualizar» borraba las colocaciones aunque la zona
        // estuviera protegida.
        'INSERT INTO $_tablaColocaciones '
        '(order_id, column_id, posicion, colocado_at, updated_at, nacio_aqui) '
        'VALUES (?1, ?2, ?3, ?4, ?4, ?5)',
        [pedidoId, columnaId, donde, _ahora, _nacioAqui],
      );

      // El apunte va DENTRO de la transaccion. Si la columna todavia es
      // provisional, el `local-…` viaja en el cuerpo y lo sustituye
      // `Provisionales` cuando la creacion de la columna suba: es lo que impide
      // que las doce colocaciones de detras acaben en una columna que no existe
      // en ningun sitio (tablero.md §9).
      await _mandarOEncolar(
        metodo: 'PUT',
        ruta: '/board/placements/$pedidoId',
        cuerpo: <String, Object?>{'columnaId': columnaId, 'posicion': donde},
      );
    });
    EsquemaTablero.avisarDeCambio(_base);
  }

  /// De vuelta a «sin colocar», que es de donde salio. La lista de la izquierda
  /// lo recoloca sola por cercania.
  Future<void> quitar(String pedidoId) async {
    await _listo();
    await _base.transaction(() async {
      final fila = await _base
          .customSelect(
            'SELECT column_id, posicion FROM $_tablaColocaciones '
            'WHERE order_id = ?1',
            variables: [Variable<String>(pedidoId)],
          )
          .getSingleOrNull();
      if (fila == null) return;

      await _base.customStatement(
        'DELETE FROM $_tablaColocaciones WHERE order_id = ?1',
        [pedidoId],
      );
      await _base.customStatement(
        'UPDATE $_tablaColocaciones SET posicion = posicion - 1 '
        'WHERE column_id = ?1 AND posicion > ?2',
        [fila.read<String>('column_id'), fila.read<int>('posicion')],
      );
      await _mandarOEncolar(
        metodo: 'DELETE',
        ruta: '/board/placements/$pedidoId',
        cuerpo: const <String, Object?>{},
      );
    });
    EsquemaTablero.avisarDeCambio(_base);
  }

  // -------------------------------------------------------------------------
  // Las columnas, que las pone el logistico
  // -------------------------------------------------------------------------

  /// Crea una columna al final del tablero.
  ///
  /// El id es provisional (`local-…`) porque sin conexion no hay quien lo
  /// reparta: lo pone la base del servidor. La pantalla necesita uno YA para
  /// poder colocar tarjetas dentro esta misma tarde, y cuando el apunte suba, la
  /// respuesta trae el bueno y `Provisionales` lo sustituye en todo lo que
  /// quede en la cola detras.
  ///
  /// La posicion la calcula el aparato, no viaja en el cuerpo: dos aparatos sin
  /// conexion propondrian el mismo numero y entonces hay dos «tercera» y
  /// ninguna «quinta».
  Future<String> crearColumna({
    required String sucursalId,
    required String nombre,
    String? vehiculoId,
  }) async {
    await _listo();
    final limpio = nombre.trim();
    if (limpio.isEmpty) {
      throw const RechazoDelTablero('La columna necesita un nombre');
    }
    // El id DEFINITIVO, puesto aqui: el servidor lo acepta y lo usa tal cual, asi
    // que reintentar la subida no crea una segunda zona. Ver `nuevoIdReal`.
    final id = Provisionales.nuevoIdReal();
    try {
      await _base.transaction(() async {
        final fila = await _base
            .customSelect(
              'SELECT coalesce(max(posicion), 0) + 1 AS siguiente '
              'FROM $_tablaColumnas WHERE branch_id = ?1',
              variables: [Variable<String>(sucursalId)],
            )
            .getSingle();
        await _base.customStatement(
          // `nacio_aqui = 1`: esta zona existe SOLO en este aparato hasta que
          // suba. Es lo que impide que «actualizar» se la lleve por delante, y
          // se pone aqui porque es el unico sitio que sabe con seguridad que la
          // fila nacio de este lado.
          'INSERT INTO $_tablaColumnas '
          '(id, branch_id, nombre, posicion, vehicle_id, created_at, updated_at, '
          ' nacio_aqui) '
          'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6, ?7)',
          [
            id,
            sucursalId,
            limpio,
            fila.read<int>('siguiente'),
            vehiculoId,
            _ahora,
            _nacioAqui,
          ],
        );
        await _mandarOEncolar(
          metodo: 'POST',
          ruta: '/board/columns?branchId=$sucursalId',
          cuerpo: <String, Object?>{
            // EL ID VIAJA EN EL CUERPO, y con eso subir dos veces deja de crear
            // dos zonas. Lo pone el aparato al crearla —un UUIDv7, aunque este
            // sin senal— y el servidor lo usa tal cual; si la respuesta no llega
            // y se reintenta, el mismo id entra una sola vez.
            //
            // Antes el id lo ponia la base y el aparato se inventaba un
            // `local-…` que habia que sustituir despues. Toda esa maquinaria
            // existia por esto, y con ella una pregunta sin respuesta: si la red
            // se caia justo despues de escribir, el aparato no sabia si la zona
            // existia arriba, y el reintento creaba otra.
            'id': id,
            'nombre': limpio,
            'vehiculoId': ?vehiculoId,
          },
          // Se sigue anotando como `provisional` aunque ya no haya nada que
          // sustituir: es lo que ata este apunte a su fila, y lo que deja saber
          // que a esta zona le falta subir. `sustituir` con los dos ids iguales
          // no hace nada, asi que no estorba.
          provisional: id,
        );
      });
    } on Object catch (e) {
      throw _traducir(e, limpio);
    }
    EsquemaTablero.avisarDeCambio(_base);
    return id;
  }

  /// Renombrar. El mensaje del choque es el literal del contrato.
  Future<void> renombrarColumna(String columnaId, String nombre) async {
    await _listo();
    final limpio = nombre.trim();
    if (limpio.isEmpty) {
      throw const RechazoDelTablero('La columna necesita un nombre');
    }
    try {
      await _base.transaction(() async {
        await _base.customStatement(
          // `nacio_aqui = 1` TAMBIEN al cambiar algo, no solo al crear.
          //
          // La marca dice «esto de aqui no esta arriba», y un renombrado sin
          // senal es exactamente eso: la zona esta arriba, pero con el nombre
          // viejo. Sin marcarlo, «actualizar» traia la foto del servidor y
          // deshacia el renombrado en silencio.
          // MARCA SOLO SI CAMBIA ALGO. Renombrar a lo mismo —o abrir el
          // desplegable del camion y elegir «ninguno» sobre una zona que ya no
          // tenia— no es trabajo sin subir, y marcarlo congela el tablero por
          // nada. Los gestos marcaban por ejecutarse, no por cambiar.
          'UPDATE $_tablaColumnas SET nombre = ?1, updated_at = ?2, '
          'nacio_aqui = CASE WHEN nombre <> ?1 THEN ?4 ELSE nacio_aqui END '
          'WHERE id = ?3',
          [limpio, _ahora, columnaId, _nacioAqui],
        );
        await _mandarOEncolar(
          metodo: 'PATCH',
          ruta: '/board/columns/$columnaId',
          cuerpo: <String, Object?>{'nombre': limpio},
        );
      });
    } on Object catch (e) {
      throw _traducir(e, limpio);
    }
    EsquemaTablero.avisarDeCambio(_base);
  }

  /// El camion PREVISTO de la columna. `null` lo quita.
  ///
  /// Es una intencion, no una decision: a media manana no se sabe cual va a ir y
  /// el de verdad se elige al armar la ruta. Sirve para una sola cosa, saber si
  /// lo que hay puesto cabe.
  Future<void> elegirCamion(String columnaId, String? vehiculoId) async {
    await _listo();
    await _base.transaction(() async {
      await _base.customStatement(
        // Igual que el renombrado: elegir camion sin senal es un cambio de
        // aqui que arriba todavia no esta.
        'UPDATE $_tablaColumnas SET vehicle_id = ?1, updated_at = ?2, '
        'nacio_aqui = CASE WHEN vehicle_id IS NOT ?1 THEN ?4 ELSE nacio_aqui END '
        'WHERE id = ?3',
        [vehiculoId, _ahora, columnaId, _nacioAqui],
      );
      // El campo viaja SIEMPRE, tambien vacio: «no me lo toques» y «quitamelo»
      // son dos ordenes distintas, y el servidor las distingue por que el campo
      // este presente.
      await _mandarOEncolar(
        metodo: 'PATCH',
        ruta: '/board/columns/$columnaId',
        cuerpo: <String, Object?>{'vehiculoId': vehiculoId},
      );
    });
    EsquemaTablero.avisarDeCambio(_base);
  }

  /// Reordena el tablero entero: llega la lista de ids en el orden nuevo.
  ///
  /// De una vez y no una columna por llamada, igual que el contrato: a mitad del
  /// baile hay dos columnas con la misma posicion, y partirlo en trozos deja el
  /// tablero con dos «tercera» y ninguna «quinta» el dia que algo falle por el
  /// medio.
  Future<void> reordenarColumnas(
    String sucursalId,
    List<String> idsEnOrden,
  ) async {
    await _listo();
    if (idsEnOrden.isEmpty) return;
    await _base.transaction(() async {
      for (var i = 0; i < idsEnOrden.length; i++) {
        await _base.customStatement(
          // Y el orden. Es lo que decide por donde empieza el camion.
          'UPDATE $_tablaColumnas SET posicion = ?1, updated_at = ?2, '
          'nacio_aqui = CASE WHEN posicion <> ?1 THEN ?5 ELSE nacio_aqui END '
          'WHERE id = ?3 AND branch_id = ?4',
          [i + 1, _ahora, idsEnOrden[i], sucursalId, _nacioAqui],
        );
      }
      await _mandarOEncolar(
        metodo: 'PUT',
        ruta: '/board/columns/orden?branchId=$sucursalId',
        cuerpo: <String, Object?>{'ids': idsEnOrden},
      );
    });
    EsquemaTablero.avisarDeCambio(_base);
  }

  /// Vacia la columna: las tarjetas vuelven a «sin colocar». La columna se
  /// queda — el distrito sigue existiendo manana.
  Future<int> vaciarColumna(String columnaId) async {
    await _listo();
    final dentro = await _pedidosDe(columnaId);
    if (dentro.isEmpty) return 0;
    await _base.transaction(() async {
      await _base.customStatement(
        'DELETE FROM $_tablaColocaciones WHERE column_id = ?1',
        [columnaId],
      );
      // Un apunte por tarjeta y no uno de «vaciar»: el contrato no tiene esa
      // orden, y quitar tarjeta a tarjeta es ademas reaplicable — quitar dos
      // veces lo que ya no esta no es un error, es el mismo tablero.
      for (final pedidoId in dentro) {
        await _mandarOEncolar(
          metodo: 'DELETE',
          ruta: '/board/placements/$pedidoId',
          cuerpo: const <String, Object?>{},
        );
      }
    });
    EsquemaTablero.avisarDeCambio(_base);
    return dentro.length;
  }

  /// Mueve todo lo de una columna a otra, DETRAS de lo que ya haya y en su
  /// orden. Es la salida natural de «esta columna no cabe en el camion»: se
  /// crea «Vista Alegre 2» y se manda lo que sobra (§7.3).
  Future<int> moverTodo(String origenId, String destinoId) async {
    await _listo();
    if (origenId == destinoId) return 0;
    final dentro = await _pedidosDe(origenId);
    if (dentro.isEmpty) return 0;
    await _base.transaction(() async {
      final base = await _cuantosEn(destinoId);
      for (var i = 0; i < dentro.length; i++) {
        final donde = base + i + 1;
        await _base.customStatement(
          // MOVER TODO es un UPDATE, no un INSERT, asi que las tarjetas que
          // vinieron de arriba se quedaban a 0 y el traslado se deshacia solo al
          // actualizar. Es el flujo de «esta columna no cabe en el camion, creo
          // otra y mando lo que sobra» (§7.3), y por aqui pasa tambien borrar una
          // columna mandando sus tarjetas a otra.
          'UPDATE $_tablaColocaciones SET column_id = ?1, posicion = ?2, '
          'nacio_aqui = CASE WHEN column_id <> ?1 OR posicion <> ?2 '
          '              THEN ?5 ELSE nacio_aqui END, '
          'updated_at = ?3 WHERE order_id = ?4',
          [destinoId, donde, _ahora, dentro[i], _nacioAqui],
        );
        await _mandarOEncolar(
          metodo: 'PUT',
          ruta: '/board/placements/${dentro[i]}',
          cuerpo: <String, Object?>{'columnaId': destinoId, 'posicion': donde},
        );
      }
    });
    EsquemaTablero.avisarDeCambio(_base);
    return dentro.length;
  }

  /// Borra una columna.
  ///
  /// **Con pedidos dentro y sin decir que hacer con ellos, la base se niega** —
  /// `ON DELETE RESTRICT`— y aqui se traduce a algo que se entiende: ««Centro»
  /// tiene 8 pedidos puestos». Con cascade, las tarjetas volverian a «sin
  /// colocar» sin decir nada y quien borro «Centro» creyendola vacia se entera
  /// al dia siguiente, cuando a la ruta le faltan ocho paradas (§7.6).
  Future<void> borrarColumna(
    String columnaId, {
    bool vaciar = false,
    String? destinoId,
  }) async {
    await _listo();
    final dentro = await _cuantosEn(columnaId);
    if (dentro > 0 && !vaciar && destinoId == null) {
      final nombre = await _nombreDe(columnaId);
      throw RechazoDelTablero(
        '«$nombre» tiene $dentro pedidos puestos',
        pedidos: dentro,
      );
    }
    if (destinoId != null) {
      await moverTodo(columnaId, destinoId);
    } else if (vaciar) {
      await vaciarColumna(columnaId);
    }

    await _base.transaction(() async {
      await _base.customStatement('DELETE FROM $_tablaColumnas WHERE id = ?1', [
        columnaId,
      ]);
      final cola = destinoId != null
          ? '?destino=$destinoId'
          : (vaciar ? '?vaciar=1' : '');
      await _mandarOEncolar(
        metodo: 'DELETE',
        ruta: '/board/columns/$columnaId$cola',
        cuerpo: const <String, Object?>{},
      );
    });
    EsquemaTablero.avisarDeCambio(_base);
  }

  // -------------------------------------------------------------------------
  // De una columna sale una ruta
  // -------------------------------------------------------------------------

  /// Arma la ruta de una columna, tambien sin conexion (§5 y §6).
  ///
  /// Lo que hace aqui dentro, todo en una transaccion:
  ///
  ///  1. mira cuales de los puestos SE PUEDEN repartir hoy y **nombra** a los
  ///     que no, con su motivo. Una columna de doce que produce una ruta de
  ///     nueve sin explicacion es la manera mas rapida de que el logistico deje
  ///     de fiarse;
  ///  2. crea la ruta con identificador provisional y **respeta el orden que
  ///     puso el logistico** —el conoce las calles de su distrito, el vecino mas
  ///     proximo no—, asi que nace con `optimized = false`;
  ///  3. se lleva del tablero SOLO las tarjetas que entraron. Las descartadas se
  ///     quedan puestas y marcadas: no desaparece el trabajo de nadie;
  ///  4. encola `POST /api/board/columns/{id}/route`.
  ///
  /// Devuelve el id provisional de la ruta.
  Future<String> armarRuta({
    required String columnaId,
    required AlmacenOrigen origen,
    required String sucursalId,
    String? nombre,

    /// QUIÉN SE QUEDÓ FUERA, cuando el servidor arma la ruta y deja tarjetas
    /// atrás — 28/09/2026.
    ///
    /// Entra por aquí y no por el valor de vuelta a propósito: el valor de
    /// vuelta es el id de la ruta y lo usan siete sitios, así que cambiarlo
    /// obliga a tocarlos todos para un dato que sólo le interesa a uno. Y va
    /// opcional porque **en la APK no hace falta**: allí el apunte sube horas
    /// después, con esta pantalla cerrada, y el aviso vive en el cajón de
    /// entregar el día.
    ///
    /// Sólo se llama **cuando de verdad se cayó alguien**: un aviso que sale
    /// siempre deja de leerse (§3-quinquies).
    void Function(List<String> descartados)? alDejarFuera,
  }) async {
    await _listo();
    final consultas = ConsultasTablero(_base);
    final puestas = (await consultas.colocados(
      sucursalId,
      origen,
    )).where((t) => t.columnaId == columnaId).toList();
    if (puestas.isEmpty) {
      throw const RechazoDelTablero(
        'La columna no tiene ningún pedido que se pueda repartir hoy',
      );
    }

    final buenos = puestas.where((t) => t.pedido.repartible).toList();
    final descartados = <String>[
      for (final t in puestas.where((t) => !t.pedido.repartible))
        '${t.pedido.operationNumber ?? t.pedido.pedidoId} · '
            '${t.pedido.customerName}: '
            '${t.pedido.marcas.firstWhere((m) => m.grave).texto}',
    ];
    if (buenos.isEmpty) {
      // No se crea una ruta vacia, y se dice por que se cayo cada uno.
      throw RechazoDelTablero(
        'La columna no tiene ningún pedido que se pueda repartir hoy',
        detalles: descartados,
      );
    }

    final columna = (await consultas.columnas(sucursalId))
        .where((c) => c.id == columnaId)
        .firstOrNull;

    // -------------------------------------------------------------------------
    // NINGUNA RUTA SIN CAMIÓN — 28/09/2026
    // -------------------------------------------------------------------------
    //
    // Jose, viendo `RT-20260928-001` en producción, «En curso · 3 paradas · Sin
    // vehículo»: «por q se creo una ruta sin vehiculo eso no se puede mi
    // broder». Y no es una pega de forma: sin camión la ruta sale con su
    // `516.5 kg` y su `$2.99` y **no hay nada con que contrastarlos**. La
    // capacidad se mide contra la del camión y el coste por km sale de su
    // `costo_km_usd`; sin camión las dos cuentas se quedan sin denominador y el
    // número que se pinta es creíble y no significa nada — que es el fallo que
    // más caro sale en este proyecto.
    //
    // ## POR QUÉ ESTO SÍ SE BLOQUEA, y el aviso del §5.2 no
    //
    // El CLAUDE.md dice que «los avisos del armador son aviso, no bloqueo»,
    // porque los datos reales tenían 657 de 686 domicilios sin costo y bloquear
    // habría dejado la aplicación inservible. Aquí es al revés, y la diferencia
    // es la que importa: **este hueco se tapa con un gesto, en la propia
    // pantalla donde sale el «no»** —«Camión previsto» en las opciones de la
    // zona—, mientras el del costo por km hay que rellenarlo cliente a cliente
    // en otro sitio.
    //
    // Y los otros DOS caminos que crean rutas ya se niegan igual desde siempre:
    // el asistente de Rutas (`rutas/datos/acciones_rutas.dart`, `armar`: «Se
    // requiere un vehículo para crear la ruta») y `POST /api/routes`
    // (`api/internal/api/rutas.go`, `msgFaltaVehiculo`). El que faltaba era
    // éste, que es **el principal**: así arma Jose el día, por zonas.
    //
    // ## Y por qué no se podía tapar antes de hoy
    //
    // El botón «Camión previsto» de las opciones de una zona **no abría nada**:
    // hacía `await ref.read(camionesProvider.future)` sobre un `StreamProvider`
    // que nadie escuchaba y ese `await` no terminaba jamás
    // (`tablero/vista/acciones.dart`, arreglado el 28/09/2026). Era el ÚNICO
    // sitio desde donde se le pone camión a una zona —`crearColumna` no lo pide
    // y la pantalla no lo manda—, así que hasta hoy toda ruta armada desde el
    // tablero nacía sin camión a la fuerza. Bloquear sin ese arreglo sí habría
    // dejado el tablero inservible; con él, el «no» se arregla en dos toques.
    // **Las dos cosas van juntas o ninguna.**
    //
    // ## El sitio de esta guarda no es casual
    //
    // Va DESPUÉS de los dos «no hay nada repartible» y ANTES de escribir nada,
    // en el mismo orden que el servidor (`api/internal/api/tablero.go`,
    // `armarRutaDeColumna`: primero el 409 de la zona sin nada, luego el camión,
    // luego la capacidad). Si dos fallan a la vez, la persona tiene que leer el
    // mismo mensaje por los dos caminos.
    //
    // Si la columna ya no existe no se habla del camión: eso lo cuenta el
    // `puestas.isEmpty` de arriba, y decir «no tiene camión previsto» de una
    // zona borrada manda a arreglar donde no es.
    if (columna != null && (columna.vehiculoId?.isEmpty ?? true)) {
      throw RechazoDelTablero(
        'La zona «${columna.nombre}» no tiene camión previsto, y sin camión no '
        'se arma su ruta',
        detalles: const [
          'Elige el camión en «Camión previsto», en las opciones de la zona, y '
              'vuelve a armar.',
          'Sin camión no hay capacidad contra la que medir la carga ni costo '
              'por km con el que cotizar el domicilio: la ruta saldría con su '
              'peso y su importe sin nada con que contrastarlos.',
        ],
      );
    }

    // LAS COORDENADAS DE CADA PARADA, para poder medir el recorrido.
    //
    // La tarjeta sólo lleva `kmAlAlmacen`, que es la distancia RADIAL desde el
    // almacén y no sirve para sumar un circuito: tres pedidos a 0,1 km del
    // almacén pueden estar en tres direcciones distintas. El recorrido se mide
    // de parada a parada, y esos puntos están en la base.
    final coordenadas = <String, Punto>{
      for (final o
          in await (_base.select(_base.orders)..where(
                (o) => o.id.isIn([for (final t in buenos) t.pedido.pedidoId]),
              ))
              .get())
        if (o.endLat != null && o.endLng != null)
          o.id: Punto(o.endLat!, o.endLng!),
    };
    // En el ORDEN que puso el logístico, que es el que va a recorrer el camión.
    final paradas = <Parada>[
      for (final t in buenos)
        if (coordenadas[t.pedido.pedidoId] case final p?)
          Parada(t.pedido.pedidoId, p.lat, p.lng),
    ];

    // El cuerpo, UNO SOLO: lo manda la web ahora y lo encola la APK para luego.
    final cuerpo = <String, Object?>{
      'nombre': ?nombre,
      'vehiculoId': ?columna?.vehiculoId,
      // El orden del logistico gana al greedy por defecto (§5.4).
      'optimizar': false,
      // EL DIA DE LA RUTA, Y VIAJA. Antes se escribia aqui abajo en la base
      // local (`deliveryDate: Value(_reloj())`) y NO se mandaba, asi que el
      // servidor la guardaba nula y la siguiente bajada la pisaba con ese nulo:
      // **la ruta nacia con fecha en el telefono y la perdia al subir**. Se vio
      // el 28/09/2026 probando la APK sin señal: «Planificada · 1.7 km ·
      // 28/9/2026» antes de sincronizar y «En curso · 1.7 km · —» despues. Las
      // nueve rutas que habia en produccion tenian `delivery_date` nulo.
      //
      // Va la del APARATO y no la de alla: un apunte hecho sin señal llega
      // horas despues, y la ruta se armo el dia que la armo el logistico, no el
      // dia en que el servidor se entero. Misma razon por la que viajan los
      // `pedidoIds` de aqui abajo.
      'deliveryDate': _reloj().toIso8601String(),
      // LOS PEDIDOS QUE ESTE APARATO ELIGIO. VIAJAN — 28/09/2026.
      //
      // ## Este comentario mintio, y por eso se arregla con una prueba
      //
      // Justo aqui arriba ponia «misma razon por la que viajan los
      // `pedidoIds`», y NO viajaban: el cuerpo eran cuatro campos y ninguno era
      // la lista. El servidor la esperaba desde el 18/09 con su porque escrito
      // largo (`api/internal/api/tablero.go`, `cuerpoArmar.PedidoIds`), y este
      // lado nunca la mando. Un comentario no falla, asi que lo que ata esto es
      // `app/test/pantallas/tablero/la_lista_de_pedidos_viaja_test.dart`.
      //
      // ## Que se rompia sin ella
      //
      // Sin la lista el servidor arma la zona con **lo que EL tenga puesto ahi
      // en el instante en que le llega el apunte**, y un apunte hecho sin señal
      // llega horas despues. Los dos lados del daño, los dos vistos:
      //
      //  · sobra uno — la web coloco una tarjeta en esa zona mientras el
      //    aparato estaba sin señal. Sube a la ruta del servidor un pedido que
      //    **no va en ese camion**, porque nadie lo cargo.
      //  · falta uno — se movio o se lo llevo otra ruta. El servidor arma con
      //    los que queden, devuelve SU peso, y la bajada lo escribe encima del
      //    que calculo el aparato: cabecera con el peso de uno y paradas con
      //    los dos, que es lo que se vio el 28/09/2026 (516,5 kg contra uno).
      //
      // Con la lista, el servidor arma EXACTAMENTE esto y nombra las dos
      // diferencias en `descartados` en vez de callarlas.
      //
      // Va `buenos` y no `puestas`: lo que no es repartible ya se quedo fuera
      // aqui arriba, con su motivo, y no sube a ningun camion.
      'pedidoIds': [for (final t in buenos) t.pedido.pedidoId],
    };

    // EN LA WEB LA RUTA LA CREA EL SERVIDOR, Y SU ID ES EL BUENO.
    //
    // Aqui se ponia un `local-…` de `Provisionales` y se esperaba a que el
    // apunte subiera para sustituirlo. En un navegador ese apunte NO SUBE NUNCA
    // —la cola sale por `/sync` y alli no hay aparato que dar de alta— asi que
    // la sustitucion no llega jamas: la pantalla se iria a `/routes/local-9f3a`,
    // y al recargar no habria ni ruta ni tarjetas, porque la base es en memoria.
    //
    // Se manda ANTES de escribir nada y no dentro de la transaccion como los
    // demas gestos, porque aqui la respuesta **es un dato que hace falta**: sin
    // el id del servidor no se puede ni empezar a escribir la fila.
    final enVivo = _enVivo;
    final String rutaId;
    if (enVivo != null) {
      final respuesta = await _mandarOEncolar(
        metodo: 'POST',
        ruta: '/board/columns/$columnaId/route',
        cuerpo: cuerpo,
      );
      // LOS DESCARTADOS DE UN «SÍ» TAMBIÉN SE DICEN. El 409 ya se leía; éste se
      // tiraba entero, así que en la web la ruta salía con menos pedidos de los
      // que se pusieron, con un «Ruta armada» verde encima. §4.
      final fuera = descartadosDeLaRespuesta(respuesta);
      if (fuera.isNotEmpty) alDejarFuera?.call(fuera);

      final id = respuesta is Map<Object?, Object?> ? respuesta['id'] : null;
      if (id is! String || id.isEmpty) {
        // Dijo que si y no dijo cual. No se inventa un id: dar la ruta por
        // armada con uno que no existe es el fallo de hoy otra vez.
        throw const RechazoDelTablero(
          'La ruta se armó en el servidor, pero la respuesta llegó sin su '
          'identificador. Actualiza el tablero para verla.',
        );
      }
      rutaId = id;
    } else {
      rutaId = Provisionales.nuevoId();
    }

    await _base.transaction(() async {
      await _base
          .into(_base.routes)
          .insert(
            RoutesCompanion.insert(
              id: rutaId,
              name: Value(nombre ?? columna?.nombre),
              status: const Value(EstadoRuta.planificada),
              originLat: Value(origen.lat),
              originLng: Value(origen.lng),
              originAddress: Value(origen.nombre),
              // LOS KILOMETROS, CALCULADOS AQUI — 17/09/2026.
              //
              // Esto no se ponia, asi que una ruta armada desde el tablero nacia
              // con `0.0 km` y la pantalla enseñaba «0.0 km (incl. regreso)»
              // encima de tres paradas. Jose, con el telefono sin señal: «esa
              // ruta como que cero, tiene que calcularlo, si eso se calcula sin
              // necesidad de conexion».
              //
              // Y tiene razon: los datos estan todos aqui. Cada tarjeta ya
              // enseña sus «0,1 km» calculados con la misma formula, y el
              // asistente de Rutas —el OTRO camino que crea rutas— ya lo hacia
              // (`rutas/datos/acciones_rutas.dart:187`). Eran dos caminos para
              // lo mismo y sólo uno calculaba.
              //
              // `kmDelCircuito` son los tramos MAS el regreso al almacen, que es
              // justo lo que dice el rotulo de la pantalla.
              totalDistance: Value(
                kmDelCircuito(Punto(origen.lat, origen.lng), paradas),
              ),
              totalWeight: Value(
                buenos.fold<double>(0, (a, t) => a + t.pedido.weight),
              ),
              // ESTO NO ES EL IMPORTE DE LA RUTA. Es el espejo de la cuenta que
              // hace el servidor (`api/internal/api/rutas.go:810-814`), y la
              // columna es `NOT NULL DEFAULT 0` en los dos lados: no sabe decir
              // «no se sabe». El importe se saca de las paradas con
              // `ImporteDeRuta`, que sí lo sabe. El porqué entero está en
              // `espejoDelTotalDelServidor`, y hay una prueba que se pone roja
              // si alguna pantalla vuelve a leer `totalPrice`.
              totalPrice: Value(
                ImporteDeRuta.espejoDelTotalDelServidor(
                  buenos.map((t) => t.pedido.pedidoCosto),
                ),
              ),
              vehicleId: Value(columna?.vehiculoId),
              branchId: Value(sucursalId),
              deliveryDate: Value(_reloj()),
              // El orden del logistico gana al greedy por defecto (§5.4).
              optimized: const Value(false),
              createdAt: Value(_reloj()),
              updatedAt: Value(_reloj()),
            ),
          );

      for (var i = 0; i < buenos.length; i++) {
        final pedido = buenos[i].pedido;
        final donde = coordenadas[pedido.pedidoId];
        await (_base.update(
          _base.orders,
        )..where((o) => o.id.equals(pedido.pedidoId))).write(
          OrdersCompanion(
            routeId: Value(rutaId),
            // `ultimaRutaId` NO se libera nunca: un devuelto suelta
            // `routeId` pero conserva esta, o desaparece de la hoja de lo
            // que bajo del camion.
            ultimaRutaId: Value(rutaId),
            vehicleId: Value(columna?.vehiculoId),
            stopOrder: Value(i + 1),
            // LA DISTANCIA DE CADA PARADA, QUE AQUI NO SE ESCRIBIA — 28/09/2026.
            //
            // Los otros tres caminos que enganchan una parada la escriben: los
            // dos del servidor (`EngancharPedidoARuta`, en POST /routes y al
            // armar una zona) y el armado local del asistente de Rutas
            // (`rutas/datos/acciones_rutas.dart`). Este no, y **este es el
            // principal**: es como Jose arma el dia, por zonas.
            //
            // Asi que una ruta recien armada tenia `segment_km` nulo en TODAS
            // sus paradas hasta que la siguiente bajada trajera del servidor un
            // numero que el aparato ya podia sacar solo. En pantalla era una
            // raya en las tres paradas de `RT-20260928-001`. Comprobado en
            // produccion el mismo dia: las 24 paradas del servidor tienen su
            // numero, o sea que lo que estaba en blanco era la copia de aqui.
            //
            // Es la RADIAL del punto de partida al cliente, no el tramo: es el
            // numero con el que se cobra el domicilio y se hereda asi de
            // delivery. La misma cuenta que hace el servidor en
            // `api/internal/api/tablero.go` (busca «radial»), con el mismo
            // radio: `radioTierraKm` de `rutas/datos/geo.dart`, que ya es el que
            // usa el resto de esta funcion para medir el circuito.
            //
            // Y **la de `rutas/datos/geo.dart` a proposito**, que es la que ya
            // esta importada aqui: en la aplicacion hay DOS haversine escritas
            // aparte —esa con `atan2` y la de `tablero/datos/geo.dart` con
            // `asin`— y usar una aqui y otra en la pantalla de Rutas daria dos
            // numeros distintos para «cuan lejos esta este cliente».
            //
            // Sin coordenada del cliente no se puede medir, y entonces se deja
            // NULO y no cero: un cero ahi se lee como «el cliente esta en la
            // puerta del almacen», que es un numero creible y equivocado.
            segmentKm: Value(
              donde == null
                  ? null
                  : haversineKm(Punto(origen.lat, origen.lng), donde),
            ),
          ),
        );
        await _base.customStatement(
          'DELETE FROM $_tablaColocaciones WHERE order_id = ?1',
          [pedido.pedidoId],
        );
      }

      // En la web ya esta arriba —y con el id del servidor puesto—, asi que no
      // hay nada que encolar. Lo que quede de distinto entre lo que se escribio
      // aqui y lo que guardo el servidor (un descartado de mas, por ejemplo) lo
      // cuadra la siguiente bajada del tablero, que en la web nunca se niega.
      if (enVivo == null) {
        await _mandarOEncolar(
          metodo: 'POST',
          ruta: '/board/columns/$columnaId/route',
          cuerpo: cuerpo,
          provisional: rutaId,
        );
      }
    });
    EsquemaTablero.avisarDeCambio(_base);
    return rutaId;
  }

  // -------------------------------------------------------------------------
  // Mantenimiento
  // -------------------------------------------------------------------------

  /// Cambia los `local-…` ya resueltos por su id de verdad en las tablas del
  /// tablero.
  ///
  /// `Provisionales` sustituye en la cola y en las tablas del nucleo, pero no
  /// conoce estas dos —son de esta pantalla—. Esto cierra el circulo, y se llama
  /// en cada carga: mientras no se llame, la columna sigue con su `local-…`
  /// puesto, que funciona pero no es lo que el servidor tiene.
  Future<int> asentarProvisionales() async {
    await _listo();
    final equivalencias = await _base.select(_base.equivalencias).get();
    if (equivalencias.isEmpty) return 0;
    var cambiadas = 0;
    await _base.transaction(() async {
      // Cambiar el id de una columna que tiene tarjetas dentro choca con el
      // `ON DELETE RESTRICT` de las colocaciones: durante un instante apuntan a
      // un id que ya no existe. En Postgres la unica es DEFERRABLE; en SQLite
      // se pide lo mismo con este `PRAGMA`, que aplaza la comprobacion al
      // cierre de la transaccion, cuando ya esta todo puesto.
      await _base.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final e in equivalencias) {
        final filas = await _base
            .customSelect(
              'SELECT count(*) AS n FROM $_tablaColumnas WHERE id = ?1',
              variables: [Variable<String>(e.provisional)],
            )
            .getSingle();
        if (filas.read<int>('n') == 0) continue;
        await _base.customStatement(
          'UPDATE $_tablaColumnas SET id = ?1 WHERE id = ?2',
          [e.idReal, e.provisional],
        );
        await _base.customStatement(
          'UPDATE $_tablaColocaciones SET column_id = ?1 WHERE column_id = ?2',
          [e.idReal, e.provisional],
        );
        cambiadas++;
      }
    });
    if (cambiadas > 0) EsquemaTablero.avisarDeCambio(_base);
    return cambiadas;
  }

  /// El aviso de los que se llevo la cascada se da UNA vez (§7.5).
  Future<void> olvidarDesaparecidos() async {
    await _listo();
    await _base.customStatement('DELETE FROM ${EsquemaTablero.desaparecidos}');
    EsquemaTablero.avisarDeCambio(_base);
  }

  // -------------------------------------------------------------------------

  Future<int> _cuantosEn(String columnaId) async {
    final fila = await _base
        .customSelect(
          'SELECT count(*) AS n FROM $_tablaColocaciones WHERE column_id = ?1',
          variables: [Variable<String>(columnaId)],
        )
        .getSingle();
    return fila.read<int>('n');
  }

  Future<List<String>> _pedidosDe(String columnaId) async {
    final filas = await _base
        .customSelect(
          'SELECT order_id FROM $_tablaColocaciones WHERE column_id = ?1 '
          'ORDER BY posicion ASC',
          variables: [Variable<String>(columnaId)],
        )
        .get();
    return filas.map((f) => f.read<String>('order_id')).toList();
  }

  Future<String> _nombreDe(String columnaId) async {
    final fila = await _base
        .customSelect(
          'SELECT nombre FROM $_tablaColumnas WHERE id = ?1',
          variables: [Variable<String>(columnaId)],
        )
        .getSingleOrNull();
    return fila?.read<String>('nombre') ?? 'La columna';
  }

  /// El choque de la unica de nombres, dicho como lo dice el contrato. El error
  /// de clave repetida de SQLite no lo entiende nadie.
  ///
  /// Se mira el TEXTO y no el tipo a proposito: en el aparato la base vive en
  /// otro isolate y lo que llega aqui ya no es la `SqliteException` original,
  /// sino la envoltura que cruzo el puente. Un `on SqliteException` funcionaria
  /// en los tests y no en el telefono, que es el peor de los dos mundos.
  RechazoDelTablero _traducir(Object e, String nombre) {
    if (e is RechazoDelTablero) return e;
    final texto = e.toString().toLowerCase();
    if (texto.contains('unique constraint failed') ||
        texto.contains('constraint failed: board_columns')) {
      return RechazoDelTablero('Ya hay una columna «$nombre» en este tablero');
    }
    return RechazoDelTablero(e.toString());
  }
}
