import '../base/base.dart';

export '../base/base.dart' show Apunte, EstadoApunte;

/// Lo que el servidor contesta de UN apunte, en `POST /sync/subida`.
/// Ver ../../../docs/sincronizacion.md §2.
enum EstadoResultado {
  /// Se aplico ahora.
  aplicado,

  /// Ya estaba aplicado de un intento anterior que se corto antes de contestar.
  /// **No es un error**: es exactamente para lo que existe la `clave`.
  repetido,

  /// El servidor dijo que no. Final: ni se reintenta ni se borra.
  rechazado,

  /// **Esa clave ya esta en la bandeja de revision** (`en_revision`): el
  /// servidor la tiene, tal cual, esperando a que un administrador decida. No
  /// es un rechazo —ni se reintenta ni se descarta— y tampoco un aplicado.
  ///
  /// Solo puede llegar a una instalacion que ya entrego ese apunte y no se
  /// entero (se perdio la respuesta) y que despues recupero el permiso. Sin
  /// este caso, `deJson` lanzaba `FormatException` en cada ciclo, o peor: el
  /// `else` de `ColaDeSalida.resolver` lo habria dejado `rechazado`.
  enRevision,
}

/// La respuesta del servidor para un apunte.
class ResultadoApunte {
  const ResultadoApunte({
    required this.estado,
    this.id,
    this.motivo,
    this.descartados = const <DescartadoDelServidor>[],
    this.revision,
  });

  ResultadoApunte.deJson(Map<String, Object?> json)
    : estado = switch (json['estado']) {
        'aplicado' => EstadoResultado.aplicado,
        'repetido' => EstadoResultado.repetido,
        'rechazado' => EstadoResultado.rechazado,
        'en_revision' => EstadoResultado.enRevision,
        final otro => throw FormatException('estado desconocido: $otro'),
      },
      id = json['id'] as String?,
      motivo = json['motivo'] as String?,
      revision = json['revision'] as String?,
      descartados = DescartadoDelServidor.deLista(json['descartados']);

  final EstadoResultado estado;

  /// El id de la entrega a revision, cuando el estado es `en_revision`.
  final String? revision;

  /// El id de verdad de lo que este apunte creo. Es lo que sustituye al
  /// `local-…`.
  final String? id;

  /// El motivo literal del servidor. Se ensena TAL CUAL, en espanol, sin
  /// envolver en «Ha ocurrido un error».
  final String? motivo;

  /// QUIEN SE CAYO DE LO QUE ESTE APUNTE MANDABA, y por que.
  ///
  /// Existe aunque el apunte se **aplique**, y esa es la razon de que este aqui
  /// y no dentro de [motivo]: armar una zona de doce puede salir bien y dejar
  /// tres fuera. El servidor lo dice —con nombre, motivo y que hacer— desde el
  /// 18/09/2026, y hasta el 28/09 nadie lo leia: la ruta salia con menos
  /// pedidos de los que el logistico puso y no habia ni un aviso en ningun
  /// sitio. Es el §4 literal, «nada se descarta en silencio».
  ///
  /// Vacia casi siempre, que es lo que tiene que ser: un aviso que sale en cada
  /// armado deja de leerse (§3-quinquies).
  final List<DescartadoDelServidor> descartados;

  /// UN `repetido` CON MOTIVO **NO** ES UN APUNTE APLICADO — 01/10/2026.
  ///
  /// `repetido` significa «esta clave ya la vi», y el servidor contesta eso
  /// **tanto si entro como si se rechazo**: cuando se rechazo, **reenvia el
  /// motivo de entonces a proposito** (`sync/internal/sincro/subida.go`). Aqui
  /// ese motivo se tiraba a la basura y el apunte pasaba a `aplicado`.
  ///
  /// Lo que se veia, probado en el telefono de Jose ese dia: un pedido movido
  /// sin red que el servidor rechazo porque ya iba en otra ruta; se pulsa
  /// **«Reintentar»** en la bandeja —que es el boton que pulsa cualquiera, «a lo
  /// mejor ahora pasa»— y la aplicacion dice **«1 apunte subido»** de algo que
  /// NO subio. El rechazo desaparece de la bandeja, la insignia se va de la
  /// tarjeta, y **no queda constancia de que decidio nadie**.
  ///
  /// Es el `CLAUDE.md` §4 por los dos lados a la vez: «nada se descarta en
  /// silencio» y «una decision de una persona se ESCRIBE, no se borra». Y es el
  /// mismo patron que costo semanas el 29/09/2026 con el boton «Descartar».
  ///
  /// Un `repetido` **sin** motivo si es una aplicacion: es el caso para el que
  /// se invento —la respuesta se perdio por el camino y se reintenta—, y ahi la
  /// clave es justo lo que impide duplicar la ruta.
  bool get seAplico =>
      estado == EstadoResultado.aplicado ||
      (estado == EstadoResultado.repetido && motivo == null);
}

/// En que esta, PARA EL SERVIDOR, un apunte entregado a revision
/// (`GET /sync/revision/mias`, `docs/bandeja-de-revision.md` B.2).
///
/// No es [EstadoApunte]: el aparato guarda menos estados que el servidor
/// (`aplicando` es «alguien lo esta aplicando ahora» y `rechazado` es «el
/// reparto no pudo», y ninguno de los dos es una decision firme).
enum EstadoEnRevision { enRevision, aplicando, aplicado, rechazado, descartado }

/// Lo que el servidor dice de UN apunte entregado: lo que lee la persona.
class DecisionDeRevision {
  const DecisionDeRevision({
    required this.estado,
    this.por,
    this.cuando,
    this.motivo,
    this.idCreado,
    this.entrega,
    this.descartados = const <DescartadoDelServidor>[],
  });

  /// Una entrada de `mias` (o de la respuesta de la entrega). Un estado que no
  /// conoce LANZA, igual que [ResultadoApunte.deJson]: quien llama lo atrapa
  /// por apunte y deja ese como esta, sin tumbar el resto.
  DecisionDeRevision.deJson(Map<String, Object?> json)
    : estado = switch (json['estado']) {
        'en_revision' => EstadoEnRevision.enRevision,
        'aplicando' => EstadoEnRevision.aplicando,
        'aplicado' => EstadoEnRevision.aplicado,
        'rechazado' => EstadoEnRevision.rechazado,
        'descartado' => EstadoEnRevision.descartado,
        final otro => throw FormatException('estado de revision desconocido: $otro'),
      },
      por = json['decididoPorNombre'] as String?,
      cuando = json['decididoAt'] is String
          ? DateTime.tryParse(json['decididoAt']! as String)?.toLocal()
          : null,
      motivo = json['motivo'] as String?,
      idCreado = json['idCreado'] as String?,
      entrega = json['revision'] as String?,
      descartados = DescartadoDelServidor.deLista(json['descartados']);

  final EstadoEnRevision estado;

  /// El NOMBRE de quien decidio (o intento aplicar), tal como lo da el servidor.
  final String? por;
  final DateTime? cuando;

  /// El motivo escrito del descarte, o el literal del reparto si no pudo aplicar.
  final String? motivo;

  /// El id de verdad de lo que ese apunte creo, si creaba algo.
  final String? idCreado;

  /// El id de la entrega, si el servidor lo manda.
  final String? entrega;

  /// Quien se cayo de lo que este apunte mandaba aunque se APLICARA (el mismo
  /// aviso que la subida normal: «salio con menos de lo que pusiste»).
  final List<DescartadoDelServidor> descartados;
}

/// Un apunte, tal y como sale hacia `POST /sync/subida`.
extension ApunteAJson on Apunte {
  Map<String, Object?> aJson(Object? cuerpoDecodificado) => <String, Object?>{
    'clave': clave,
    // La hora del APARATO, en UTC con su marca, no la de la subida.
    'hecho': hechoAt.toUtc().toIso8601String(),
    'metodo': metodo,
    'ruta': ruta,
    'cuerpo': cuerpoDecodificado,
    if (provisional != null) 'provisional': provisional,
  };
}

/// UN PEDIDO QUE EL SERVIDOR DEJO FUERA, con su nombre y su motivo.
///
/// Lo manda `POST /api/board/columns/{id}/route` en `descartados`, tanto en el
/// 201 como en el 409 (`api/internal/api/tablero.go`, `DescartadoSalida`), y
/// llega hasta aqui por la subida: `sync/internal/sincro/subida.go` lo reenvia
/// tal cual dentro del resultado del apunte.
///
/// **`queHacer` no es un adorno.** El 409 que esto sustituyo decia «1 de los 2
/// pedidos ya están en otra ruta. Vuelve a elegirlos.» sobre una tarjeta que se
/// habia quedado sin coordenadas: motivo falso, sin nombrar la tarjeta, y
/// «vuelve a elegirlos» no arreglaba nada. Un rechazo permanente que pide que se
/// reintente es la peor forma de no dejar salir a nadie.
class DescartadoDelServidor {
  const DescartadoDelServidor({
    required this.pedidoId,
    required this.motivo,
    this.operationNumber,
    this.customerName,
    this.queHacer,
  });

  /// Lo que se puede leer. Un elemento que no sea un mapa —o que venga sin
  /// `pedidoId`— se deja fuera: es basura de protocolo, no un descarte.
  static List<DescartadoDelServidor> deLista(Object? crudo) {
    if (crudo is! List) return const <DescartadoDelServidor>[];
    final leidos = <DescartadoDelServidor>[];
    for (final uno in crudo) {
      if (uno is! Map) continue;
      final pedidoId = uno['pedidoId'];
      if (pedidoId is! String || pedidoId.isEmpty) continue;
      leidos.add(
        DescartadoDelServidor(
          pedidoId: pedidoId,
          motivo: uno['motivo'] as String? ?? '',
          operationNumber: uno['operationNumber'] as String?,
          customerName: uno['customerName'] as String?,
          queHacer: uno['queHacer'] as String?,
        ),
      );
    }
    return leidos;
  }

  final String pedidoId;

  /// El motivo LITERAL del servidor. Se pinta tal cual.
  final String motivo;

  /// El folio, si lo tiene. **Con su sufijo**: `X-2992` y `X-2992-2` son dos
  /// pedidos distintos.
  final String? operationNumber;

  final String? customerName;

  /// Que tiene que hacer quien lo lea. Puede no venir: los descartes que el
  /// servidor nombra sin tarjeta —«ya no estaba en esa zona»— si lo traen.
  final String? queHacer;

  /// Como se nombra en una linea: folio, cliente y motivo.
  ///
  /// Se nombra por el FOLIO y no por el uuid: el uuid no le dice nada a nadie y
  /// no se puede buscar en PEDIDO. Si no hay folio se cae al pedidoId, que es
  /// feo pero es un dato; callarse cual fue seria el descarte en silencio otra
  /// vez.
  String get comoSeLee {
    final quien = <String>[
      operationNumber ?? pedidoId,
      if (customerName != null && customerName!.isNotEmpty) customerName!,
    ].join(' · ');
    return motivo.isEmpty ? quien : '$quien: $motivo';
  }

  @override
  String toString() => 'DescartadoDelServidor($comoSeLee)';
}

/// EL AVISO ENTERO, ya escrito, tal y como lo va a leer una persona.
///
/// Vive aqui —y no en la pantalla— por lo mismo que `PersonaEnElAparato.
/// queSePierde`: es lo que hay que poner delante de alguien, y escrito en la
/// pantalla se olvida la mitad. Ademas lo guarda la cola en `apuntes.motivo`,
/// que es texto.
String textoDeLosDescartados(List<DescartadoDelServidor> descartados) {
  if (descartados.isEmpty) return '';
  final cuantos = descartados.length;
  return <String>[
    cuantos == 1
        ? 'Un pedido de los que armaste NO subió a ese camión:'
        : '$cuantos pedidos de los que armaste NO subieron a ese camión:',
    for (final d in descartados)
      [d.comoSeLee, if (d.queHacer != null) d.queHacer].join(' — '),
  ].join('\n');
}
