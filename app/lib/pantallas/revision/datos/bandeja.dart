/// LO QUE EL REVISOR VE DE LO QUE OTRO ENTREGO: el modelo de la bandeja.
///
/// **Esta es LA capa donde vive la forma de las respuestas de `sync`.** Es el
/// contrato REAL de S2 (`sync/internal/sincro/revision_revisor.go` y
/// `revision_aplicar.go`, cuaderno G-SYNC2, 09/10/2026), ya reconciliado: todo lo
/// que se sabe del JSON esta aqui y en `repositorio_revision.dart`, y en ningun
/// otro sitio. Si el servidor cambia, se ajusta aqui y la pantalla no se entera.
///
/// Las claves se leen en camelCase (que es lo que escribe S2); [_campo] admite
/// tambien la snake_case por si algun dia el resto de `sync` (`horas_sin_subir`)
/// manda: es una linea y no cambia lo que significa nada.
library;

import 'dart:convert';

Object? _campo(Map<String, Object?> json, String clave) {
  final snake = clave.replaceAllMapped(
    RegExp('[A-Z]'),
    (m) => '_${m[0]!.toLowerCase()}',
  );
  return json[clave] ?? json[snake];
}

String? _texto(Object? valor) {
  final t = valor is String ? valor.trim() : null;
  return (t == null || t.isEmpty) ? null : t;
}

DateTime? _fecha(Object? valor) =>
    valor is String ? DateTime.tryParse(valor)?.toLocal() : null;

int _entero(Object? valor) => valor is num ? valor.toInt() : 0;

/// El estado de un apunte entregado (`revision_estado` en `sync`, B.2).
enum EstadoDelApunte {
  enRevision('en_revision'),

  /// Alguien lo esta aplicando AHORA, o se interrumpio con la fila a medias. Pasados
  /// 10 minutos el servidor lo marca `interrumpido` ([ApunteEnRevision.interrumpido]);
  /// solo entonces se ofrece reintentarlo, y confirmando que se comprobo a mano.
  aplicando('aplicando'),
  aplicado('aplicado'),

  /// El reparto dijo que no al aplicar. SIGUE esperando decision.
  rechazado('rechazado'),
  descartado('descartado'),

  /// Un estado que esta version no conoce. Se pinta con su texto y sin acciones:
  /// no se esconde (lo desconocido se ensena) y tampoco se actua sobre el.
  desconocido('');

  const EstadoDelApunte(this.clave);

  final String clave;

  static EstadoDelApunte deTexto(String? texto) => values.firstWhere(
    (e) => e.clave.isNotEmpty && e.clave == texto,
    orElse: () => desconocido,
  );

  /// ¿Espera a que una persona decida? Solo estos dos se pueden aplicar o
  /// descartar (el candado del servidor es `estado IN ('en_revision',
  /// 'rechazado')`, B.2 «Aplicar» punto 1).
  bool get esperaDecision => this == enRevision || this == rechazado;
}

/// Un apunte de la cola de otra persona, TAL COMO LLEGO.
class ApunteEnRevision {
  const ApunteEnRevision({
    required this.aparato,
    required this.clave,
    required this.orden,
    required this.metodo,
    required this.ruta,
    required this.cuerpo,
    required this.hechoAt,
    required this.estado,
    required this.estadoTexto,
    this.motivo,
    this.decididoPorNombre,
    this.decididoAt,
    this.intentos = 0,
    this.interrumpido = false,
  });

  factory ApunteEnRevision.deJson(Map<String, Object?> json) {
    final cuerpo = _campo(json, 'cuerpo');
    final estadoTexto = _texto(_campo(json, 'estado')) ?? '';
    return ApunteEnRevision(
      aparato: _texto(_campo(json, 'aparato')) ?? '',
      clave: _texto(_campo(json, 'clave')) ?? '',
      orden: _entero(_campo(json, 'orden')),
      metodo: _texto(_campo(json, 'metodo')) ?? '',
      ruta: _texto(_campo(json, 'ruta')) ?? '',
      // EL CUERPO EXACTO: el texto que llego, sin volver a serializarlo. Un
      // `jsonEncode(jsonDecode(x))` cambia el orden de espacios y de claves, y
      // entonces el revisor mira algo distinto de lo que se va a aplicar. Solo
      // si el servidor lo mandara ya como objeto no hay mas remedio.
      cuerpo: cuerpo is String
          ? cuerpo
          : (cuerpo == null ? null : jsonEncode(cuerpo)),
      hechoAt: _fecha(_campo(json, 'hechoAt') ?? json['hecho']),
      estado: EstadoDelApunte.deTexto(estadoTexto),
      estadoTexto: estadoTexto,
      motivo: _texto(_campo(json, 'motivo')),
      decididoPorNombre: _texto(_campo(json, 'decididoPorNombre')),
      decididoAt: _fecha(_campo(json, 'decididoAt')),
      intentos: _entero(_campo(json, 'intentos')),
      interrumpido: _campo(json, 'interrumpido') == true,
    );
  }

  final String aparato;
  final String clave;
  final int orden;
  final String metodo;
  final String ruta;

  /// El cuerpo tal cual llego, o `null` si el apunte no llevaba.
  final String? cuerpo;

  /// La hora del APARATO (cuando se hizo de verdad), no la de la entrega.
  final DateTime? hechoAt;

  final EstadoDelApunte estado;

  /// El texto del estado como lo mando el servidor (para el `desconocido`).
  final String estadoTexto;

  /// Rechazado: el LITERAL del reparto. Descartado: el motivo de quien decidio.
  final String? motivo;
  final String? decididoPorNombre;
  final DateTime? decididoAt;
  final int intentos;

  /// `aplicando` desde hace mas de 10 minutos: la orden se corto a medias. Es lo
  /// unico que habilita "Reintentar" y exige confirmar que se comprobo la ruta.
  final bool interrumpido;
}

/// Una entrega: lo que una persona dejo en revision con UNA pulsacion.
class EntregaEnRevision {
  const EntregaEnRevision({
    required this.id,
    required this.aparato,
    required this.persona,
    required this.sucursal,
    this.aparatoNombre,
    this.personaNombre,
    this.entregadaAt,
    this.versionApp,
    this.enRevision = 0,
    this.aplicando = 0,
    this.rechazados = 0,
    this.aplicados = 0,
    this.descartados = 0,
    this.apuntes = const <ApunteEnRevision>[],
  });

  /// Lee la entrega. Sirve para una fila de la lista y para la cabecera del
  /// detalle (que trae ademas los [apuntes]).
  factory EntregaEnRevision.deJson(Map<String, Object?> json) {
    final apuntes = _campo(json, 'apuntes');
    return EntregaEnRevision(
      id: _texto(_campo(json, 'id')) ?? '',
      aparato: _texto(_campo(json, 'aparato')) ?? '',
      aparatoNombre: _texto(_campo(json, 'aparatoNombre')),
      persona: _texto(_campo(json, 'persona')) ?? '',
      personaNombre: _texto(_campo(json, 'personaNombre')),
      sucursal: _texto(_campo(json, 'sucursal')) ?? '',
      entregadaAt: _fecha(_campo(json, 'entregadaAt')),
      versionApp: _texto(_campo(json, 'versionApp')),
      enRevision: _entero(_campo(json, 'enRevision')),
      aplicando: _entero(_campo(json, 'aplicando')),
      rechazados: _entero(_campo(json, 'rechazados')),
      aplicados: _entero(_campo(json, 'aplicados')),
      descartados: _entero(_campo(json, 'descartados')),
      apuntes: apuntes is List
          ? [
              for (final a in apuntes.whereType<Map<String, Object?>>())
                ApunteEnRevision.deJson(a),
            ]
          : const <ApunteEnRevision>[],
    );
  }

  final String id;
  final String aparato;
  final String? aparatoNombre;

  /// El `sub` verificado de quien entrego. Con el se decide «nadie revisa lo
  /// suyo» en la pantalla; el cerrojo de verdad es el del servidor.
  final String persona;
  final String? personaNombre;

  /// El uuid de la sucursal: el servidor NO manda su nombre. Se muestra el que ya
  /// conoce la app (su copia de sucursales) o, si no, el principio del uuid.
  final String sucursal;
  final DateTime? entregadaAt;
  final String? versionApp;

  /// Contadores del servidor. «Pendientes de decidir» = [enRevision] +
  /// [rechazados].
  final int enRevision;
  final int aplicando;
  final int rechazados;
  final int aplicados;
  final int descartados;

  /// Solo en el detalle; en la lista llega vacio.
  final List<ApunteEnRevision> apuntes;

  int get porDecidir => enRevision + rechazados;
}

/// La respuesta de `GET /sync/revision`.
class BandejaDelRevisor {
  const BandejaDelRevisor(this.entregas, {this.truncado = false});

  factory BandejaDelRevisor.deJson(Map<String, Object?> json) {
    final lista = _campo(json, 'entregas');
    return BandejaDelRevisor([
      if (lista is List)
        for (final e in lista.whereType<Map<String, Object?>>())
          EntregaEnRevision.deJson(e),
    ], truncado: _campo(json, 'truncado') == true);
  }

  final List<EntregaEnRevision> entregas;

  /// El servidor corto la lista en su tope (500): hay mas de las que se ven. Un
  /// tope que se alcanza se DICE (CLAUDE.md §3), no se calla.
  final bool truncado;

  /// El contador que ve el revisor: apuntes que esperan decision.
  int get porDecidir => entregas.fold(0, (suma, e) => suma + e.porDecidir);
}

/// El resultado de UN apunte al aplicar: `aplicado` o `rechazado` con el LITERAL
/// del reparto (o un estado que esta version no conoce).
class ResultadoDeAplicar {
  const ResultadoDeAplicar(this.clave, this.estado, this.motivo);

  final String clave;
  final EstadoDelApunte estado;

  /// Si el reparto dijo que no, su LITERAL.
  final String? motivo;
}

/// Lo que contesta el servidor a aplicar: SIEMPRE `{resultados:[…]}` (nunca un
/// objeto suelto), y para «Aplicar todo en orden» ademas, si se paro:
/// `{detenido, detenidoEn, detenidoPorque, sinProcesar}`.
///
/// «Aplicar todo en orden» SE DETIENE en el primer apunte que no queda aplicado
/// (lo de detras puede depender de el): dice cual, por que y cuantos quedaron sin
/// tocar. Salta lo ya `aplicado` o `descartado` y reintenta una vez cada
/// `rechazado`.
class RespuestaDeAplicar {
  const RespuestaDeAplicar(
    this.resultados, {
    this.detenido = false,
    this.detenidoEn,
    this.detenidoPorque,
    this.sinProcesar = 0,
  });

  factory RespuestaDeAplicar.deJson(Object? cuerpo) {
    if (cuerpo is! Map<String, Object?>) return const RespuestaDeAplicar([]);
    final lista = _campo(cuerpo, 'resultados');
    return RespuestaDeAplicar(
      [
        if (lista is List)
          for (final f in lista.whereType<Map<String, Object?>>())
            ResultadoDeAplicar(
              _texto(_campo(f, 'clave')) ?? '',
              EstadoDelApunte.deTexto(_texto(_campo(f, 'estado'))),
              _texto(_campo(f, 'motivo')),
            ),
      ],
      detenido: _campo(cuerpo, 'detenido') == true,
      detenidoEn: _texto(_campo(cuerpo, 'detenidoEn')),
      detenidoPorque: _texto(_campo(cuerpo, 'detenidoPorque')),
      sinProcesar: _entero(_campo(cuerpo, 'sinProcesar')),
    );
  }

  final List<ResultadoDeAplicar> resultados;
  final bool detenido;

  /// La clave del apunte donde se paro.
  final String? detenidoEn;

  /// El motivo LITERAL por el que se paro.
  final String? detenidoPorque;
  final int sinProcesar;
}
