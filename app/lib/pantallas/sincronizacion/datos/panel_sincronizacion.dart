/// Lo que devuelve `GET /sync/estado`, leido tal cual.
///
/// **Los campos son los de `sync/internal/sincro/estado.go`**, no los de la
/// consulta. Importa la diferencia: `PanelDeEstado` calcula
/// `segundos_sin_subir` con `-1` para «nunca», pero ese numero NO sale por
/// HTTP. El servicio lo descarta a proposito —la columna generada no admite
/// vacio y el que nunca subio es justo el que no puede venir como `0`— y manda
/// `horas_sin_subir`, **vacio** para ese caso. Aqui se lee lo que el servicio
/// manda.
///
/// Sin tablas de Drift y a proposito, como Vehiculos: esta pantalla es de
/// **solo con conexion**. Guardar una copia local seria poder ensenar «Palma
/// lleva 2 horas sin subir» con datos de anteayer, que es exactamente el
/// engano que esta pantalla existe para impedir.
library;

import '../../../nucleo/plataforma.dart';

DateTime? _fecha(Object? valor) {
  if (valor is! String || valor.isEmpty) return null;
  return DateTime.tryParse(valor)?.toLocal();
}

int _entero(Object? valor) => switch (valor) {
  final num n => n.toInt(),
  final String s => int.tryParse(s) ?? 0,
  _ => 0,
};

int? _enteroONulo(Object? valor) => switch (valor) {
  final num n => n.toInt(),
  final String s => int.tryParse(s),
  _ => null,
};

String _texto(Object? valor) => valor is String ? valor : '';

/// Como de mal esta un aparato. Es lo que decide el COLOR, y por eso vive aqui
/// y no en la vista: el umbral es una regla, no un gusto, y se prueba sola.
enum GravedadSincro {
  /// No ha subido NUNCA. **No es «lleva 0 horas»** y no se pinta igual.
  nunca,

  /// Mas de un dia entero sin subir. Es el «lleva desde el martes».
  tarde,

  /// Mas de una jornada. Cerro el dia y se fue a casa sin subir.
  atencion,

  /// Al dia.
  alDia,
}

/// Una fila de `aparatos`: un aparato con su estado.
class AparatoDelPanel {
  const AparatoDelPanel({
    required this.aparato,
    required this.persona,
    required this.sucursal,
    required this.pendientes,
    required this.rechazados,
    this.nombre,
    this.instalacion,
    this.visto,
    this.alta,
    this.bajada,
    this.bajadaHasta,
    this.subida,
    this.horasSinSubir,
  });

  factory AparatoDelPanel.deJson(Map<String, Object?> j) => AparatoDelPanel(
    aparato: _texto(j['aparato']),
    persona: _texto(j['persona']),
    sucursal: _texto(j['sucursal']),
    nombre: j['nombre'] as String?,
    instalacion: j['instalacion'] as String?,
    visto: _fecha(j['visto']),
    alta: _fecha(j['alta']),
    bajada: _fecha(j['bajada']),
    bajadaHasta: _fecha(j['bajada_hasta']),
    subida: _fecha(j['subida']),
    pendientes: _entero(j['pendientes']),
    rechazados: _entero(j['rechazados']),
    horasSinSubir: _enteroONulo(j['horas_sin_subir']),
  );

  /// A partir de aqui es AMBAR: una jornada entera sin subir es alguien que
  /// cerro el dia y se fue a su casa con el cierre de la ruta en el telefono.
  static const horasDeUnaJornada = 8;

  /// A partir de aqui es ROJO: un dia entero. Es el caso que hay que llamar.
  static const horasDeUnDia = 24;

  final String aparato;
  final String persona;
  final String sucursal;
  final String? nombre;

  /// El `X-Aparato-Id` de Accesos (lo que se ve en «Dispositivos»): de aquí sale «Ver actividad». Vacío = aún no se ha unido.
  final String? instalacion;

  /// La ultima peticion de este aparato, suba o baje. Es lo que distingue «el
  /// telefono esta apagado en un cajon» de «el telefono trabaja pero no sube».
  final DateTime? visto;
  final DateTime? alta;
  final DateTime? bajada;
  final DateTime? bajadaHasta;

  /// La ultima subida. **Vacio quiere decir NUNCA**, y asi es como el servicio
  /// lo distingue (`estado.go`: «El panel distingue "nunca" por `subida_at`»).
  final DateTime? subida;

  final int pendientes;

  /// Los que se le han rechazado en total, atendidos o no. Los que siguen
  /// esperando a una persona salen en la bandeja.
  final int rechazados;

  /// Las horas que lleva sin subir, **vacio si nunca subio**. Las cuenta el
  /// servidor con SU reloj: el del aparato se mueve, y el de este PC tambien.
  final int? horasSinSubir;

  /// **«Nunca ha subido» no es «lleva 0 horas».**
  bool get nuncaSubio => subida == null;

  GravedadSincro get gravedad {
    if (nuncaSubio) return GravedadSincro.nunca;
    final horas = horasSinSubir ?? 0;
    if (horas >= horasDeUnDia) return GravedadSincro.tarde;
    if (horas >= horasDeUnaJornada) return GravedadSincro.atencion;
    return GravedadSincro.alDia;
  }

  /// Lo que se pone donde deberia ir el nombre. Un aparato sin nombre sigue
  /// siendo un aparato: se ensena por su identificador, no se esconde.
  String get comoSeLlama {
    final n = nombre?.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'Aparato ${corto(aparato)}';
  }

  /// Los primeros 8 de un uuid. Un uuid entero en una celda no lo lee nadie.
  static String corto(String id) => id.length <= 8 ? id : id.substring(0, 8);
}

/// Una fila de la bandeja: algo que el servidor rechazo y sigue esperando a que
/// una persona decida.
///
/// `rechazado` no se reintenta y **no se borra**: queda a la vista con su
/// motivo y su hora. Un apunte que desaparece solo es trabajo perdido que nadie
/// sabe que perdio.
class RechazoDelPanel {
  const RechazoDelPanel({
    required this.rechazo,
    required this.aparato,
    required this.persona,
    required this.sucursal,
    required this.clave,
    required this.motivo,
    required this.metodo,
    required this.ruta,
    this.nombre,
    this.hecho,
    this.rechazadoEl,
    this.cuerpo,
  });

  factory RechazoDelPanel.deJson(Map<String, Object?> j) => RechazoDelPanel(
    rechazo: _texto(j['rechazo']),
    aparato: _texto(j['aparato']),
    persona: _texto(j['persona']),
    sucursal: _texto(j['sucursal']),
    nombre: j['nombre'] as String?,
    clave: _texto(j['clave']),
    motivo: _texto(j['motivo']),
    metodo: _texto(j['metodo']),
    ruta: _texto(j['ruta']),
    hecho: _fecha(j['hecho']),
    // La clave del JSON es `rechazado`, no `rechazado_at`. Ver `estado.go`.
    rechazadoEl: _fecha(j['rechazado']),
    cuerpo: j['cuerpo'] as String?,
  );

  final String rechazo;
  final String aparato;
  final String persona;
  final String sucursal;
  final String? nombre;
  final String clave;

  /// El motivo LITERAL del servidor, en espanol. Se pinta tal cual: «3 de los 8
  /// pedidos ya estan en otra ruta. Vuelve a elegirlos.» dice que hacer; «Ha
  /// ocurrido un error», no.
  final String motivo;

  final String metodo;
  final String ruta;

  /// La hora del APARATO: cuando se hizo de verdad.
  final DateTime? hecho;

  /// La hora del SERVIDOR: cuando se rechazo.
  final DateTime? rechazadoEl;

  final String? cuerpo;
}

/// Cuantos rechazos sin atender tiene una sucursal. Es el numero rojo de la
/// cabecera.
class SinAtenderDeSucursal {
  const SinAtenderDeSucursal({required this.sucursal, required this.cuantos});

  factory SinAtenderDeSucursal.deJson(Map<String, Object?> j) =>
      SinAtenderDeSucursal(
        sucursal: _texto(j['sucursal']),
        cuantos: _entero(j['sin_atender']),
      );

  final String sucursal;
  final int cuantos;
}

/// La respuesta entera de `GET /sync/estado`.
class EstadoDelSincronizador {
  const EstadoDelSincronizador({
    required this.aparatos,
    required this.bandeja,
    required this.sinAtender,
  });

  /// **El orden de `aparatos` es el del servidor y no se toca.** Viene por
  /// `subida_at ASC NULLS FIRST`: el que nunca subio sale el primero, que es
  /// justo el que mas importa. Reordenar aqui —por sucursal, por nombre— lo
  /// enterraria entre nueve filas verdes.
  factory EstadoDelSincronizador.deJson(
    Map<String, Object?> j,
  ) => EstadoDelSincronizador(
    aparatos: [
      for (final f in _lista(j['aparatos'])) AparatoDelPanel.deJson(f),
    ],
    bandeja: [for (final f in _lista(j['bandeja'])) RechazoDelPanel.deJson(f)],
    sinAtender: [
      for (final f in _lista(j['sin_atender'])) SinAtenderDeSucursal.deJson(f),
    ],
  );

  static List<Map<String, Object?>> _lista(Object? valor) => [
    if (valor is List<Object?>)
      for (final f in valor)
        if (f is Map<String, Object?>) f,
  ];

  final List<AparatoDelPanel> aparatos;
  final List<RechazoDelPanel> bandeja;
  final List<SinAtenderDeSucursal> sinAtender;

  int get nuncaSubieron =>
      aparatos.where((a) => a.gravedad == GravedadSincro.nunca).length;

  int get llevanMasDeUnDia =>
      aparatos.where((a) => a.gravedad == GravedadSincro.tarde).length;

  int get pendientesEnTotal =>
      aparatos.fold(0, (suma, a) => suma + a.pendientes);

  int get sinAtenderEnTotal =>
      sinAtender.fold(0, (suma, s) => suma + s.cuantos);
}

/// Los textos de esta pantalla. No existen en la de Next —la de Next no tiene
/// sincronizador— y por eso van juntos y marcados (PLAN.md §4.3, regla 5).
abstract final class TextosDeSincronizacion {
  static const titulo = 'Sincronización';

  static const explicacion =
      'Qué aparato lleva sin subir, qué le queda pendiente y qué se le '
      'rechazó. Se lee del servidor cada vez: aquí no se guarda copia.';

  /// **Lo primero que se lee de una fila.** No es «hace 0 horas» y no comparte
  /// ni el color ni la marca con ella.
  static const nunca = 'Nunca ha subido';

  /// Sin red la pantalla dice que NO PUEDE SABERLO. No hay datos viejos que
  /// ensenar, y si los hubiera tampoco se ensenarian: «Palma subió hace 2
  /// horas» con la lectura de anteayer es peor que no decir nada.
  /// LAS MISMAS DOS FRASES, SEGÚN DESDE DÓNDE SE MIRE — 17/09/2026.
  ///
  /// La mitad que no cambia es la buena y es la razón de ser de esta pantalla:
  /// **no se puede saber quién lleva sin subir, y no se enseña una lectura
  /// vieja.** «Palma subió hace 2 horas» con el dato de anteayer es peor que no
  /// decir nada.
  ///
  /// Lo que cambia es qué hacer. En el aparato, esperar a que haya red. En un
  /// navegador no: si la página cargó, conexión hay, y el que no contesta es el
  /// servidor. Mandar a mirar la señal a quien está en la oficina es mandarlo a
  /// mirar donde no es — el mismo razonamiento de `TextosDeCaida.queHacer`.
  static String get sinConexion => Destino.trabajaSinConexion
      ? 'Sin conexión: no se puede saber quién lleva sin subir. Esta pantalla '
            'se lee del servidor y no guarda copia en el aparato, así que no hay '
            'nada viejo que enseñar. Vuelve a intentarlo cuando haya red.'
      : 'El servidor no contesta: no se puede saber quién lleva sin subir. Esta '
            'pantalla se lee del servidor y no guarda copia, así que no hay nada '
            'viejo que enseñar. Prueba otra vez y, si sigue igual, avisa a la '
            'oficina.';

  static const sinAparatos = 'No hay ningún aparato dado de alta todavía.';

  static const bandejaTitulo = 'Rechazados sin atender';

  static const bandejaVacia =
      'No hay nada rechazado esperando. Lo que se rechace sale aquí con su '
      'motivo y su hora, y no se va solo.';

  static const cargando = 'Cargando el estado de los aparatos...';

  /// LO ÚNICO QUE SE VE DE ESTA PANTALLA EN UN NAVEGADOR — 22/09/2026.
  ///
  /// La entrada del menú no está en la web (`registro.dart`, regla 1), pero la
  /// ruta sí: quien tenga el enlace guardado llega, y lo que encuentra es esto y
  /// **ni una petición al sincronizador**. Antes encontraba «Cargando el estado
  /// de los aparatos…» para siempre, con un `401` cada dos segundos por debajo.
  ///
  /// No habla de aparatos ni de cola porque en un navegador no hay ninguna de
  /// las dos: dice de quién es esta pantalla y, sobre todo, **qué pasa aquí en
  /// su lugar**, que es lo que le hace falta saber a quien acaba de aterrizar.
  static const enLaWebTitulo = 'Esto es de la aplicación, no de la web';

  static const enLaWeb =
      'La sincronización es de la aplicación de Android y de la de escritorio, '
      'que son las que se quedan sin señal y guardan el trabajo hasta poder '
      'subirlo. En el navegador no hay ni aparato ni cola: cada cosa que se '
      'hace se guarda en el servidor al momento, y lo que el servidor rechace '
      'se dice ahí mismo, con su motivo.';

  /// Cuanto lleva sin subir, en palabras.
  ///
  /// Las horas son las del SERVIDOR. Recalcularlas aqui con el reloj de este PC
  /// daria un numero distinto en cada maquina para el mismo dato.
  static String sinSubir(AparatoDelPanel aparato) {
    if (aparato.nuncaSubio) return nunca;
    final horas = aparato.horasSinSubir ?? 0;
    if (horas <= 0) return 'Hace menos de una hora';
    if (horas == 1) return 'Hace 1 hora';
    if (horas < AparatoDelPanel.horasDeUnDia) return 'Hace $horas horas';
    final dias = horas ~/ AparatoDelPanel.horasDeUnDia;
    return dias == 1 ? 'Hace 1 día' : 'Hace $dias días';
  }

  static String leidoALas(String hora) => 'Leído del servidor a las $hora.';
}
