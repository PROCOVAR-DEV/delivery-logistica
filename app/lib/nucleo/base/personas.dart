import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../proveedores.dart';
import '../registro/registro.dart';
import '../sincro/huerfanos.dart';
import 'base.dart';
import 'conexion/conexion.dart';

/// QUIEN TIENE DATOS EN ESTE APARATO, y cuánto trabajo sin subir le queda.
///
/// ## Son TRES cosas, no una — 24/09/2026
///
/// Esto preguntaba sólo por [pendientes], o sea por las filas de `apuntes` en
/// estado `pendiente`. Y ésa es **la única pregunta que se hace antes de borrar
/// la copia de alguien**, así que lo que no entraba en ella se borraba en
/// silencio:
///
///  * **Un rechazado.** Por regla de la casa se queda a la vista con su motivo
///    hasta que una persona decida, y es lo único que queda de un cierre que
///    nunca llegó al servidor. No es `pendiente`, así que contaba cero.
///  * **Trabajo huérfano.** Una ruta armada sin señal cuyo apunte se perdió: no
///    le queda ningún apunte, así que para la cola no existe — y en cambio la
///    fila sigue ahí, y nadie la va a subir nunca
///    (`nucleo/sincro/huerfanos.dart`).
///
/// Es, palabra por palabra, el agujero que el tablero cerró el 16/09/2026 con
/// la zona «Vista»: su guarda preguntaba por la cola y el `DELETE` se llevó lo
/// que la cola no veía. `pantallas/tablero/datos/servicio.dart` lo dice entero.
/// Aquí seguía sin cerrar, y con la diferencia de que esto **borra el fichero**.
class PersonaEnElAparato {
  const PersonaEnElAparato({
    required this.sub,
    required this.nombre,
    required this.pendientes,
    this.rechazados = 0,
    this.enRevision = 0,
    this.colgado = const <TrabajoHuerfano>[],
  });

  /// El `sub` de su token. Es lo que nombra su copia.
  final String sub;

  /// El nombre para PINTAR. Nunca el `sub`: ese es el identificador de la fila
  /// en la base de auth y enseñárselo al logístico es sacar la base a la cara
  /// (ver `identidad/sesion.dart`). Vacío cuando la copia es de antes de que
  /// esto se guardara.
  final String nombre;

  /// Apuntes suyos **en la cola**, esperando a subir.
  final int pendientes;

  /// Apuntes suyos que el servidor **rechazó** y siguen esperando a que alguien
  /// decida. Borrarlos es borrar la única constancia de lo que no llegó.
  final int rechazados;

  /// Apuntes suyos **entregados a revisión** que nadie ha decidido todavía
  /// (`EstadoApunte.enRevision`, `docs/bandeja-de-revision.md`).
  ///
  /// No están en [pendientes] —no suben— ni en [rechazados], pero **olvidar la
  /// copia se los lleva igual**: el apunte local es lo único que le dice a esa
  /// persona qué entregó, y que fue «Aplicado» o «Descartado» el día que lo
  /// mire. Un aparato que se «olvida» con trabajo en revisión sin avisar es el
  /// mismo agujero de los rechazados (24/09/2026).
  final int enRevision;

  /// Lo que está en su copia, no está arriba y **no lo va a subir nadie**: una
  /// ruta armada sin señal que se quedó sin su apunte, por ejemplo.
  final List<TrabajoHuerfano> colgado;

  /// LO QUE LLEVA UNA COPIA, contado en un solo sitio: las cuatro preguntas que se
  /// hacen antes de borrarla. Las usan [Personas.listar] y [Personas.olvidar]; que
  /// cada una las escribiera a mano es como se olvido una la ultima vez.
  static Future<PersonaEnElAparato> deLaBase(
    BaseLocal base, {
    String sub = '',
    String nombre = '',
  }) async => PersonaEnElAparato(
    sub: sub,
    nombre: nombre,
    pendientes: await base.cuantosPendientes(),
    // Las otras, que son las que no contaba nadie. Sin ellas, la pantalla que
    // ofrece el gesto ensena «no le queda nada» encima de un cierre rechazado.
    rechazados: await base.cuantosRechazados(),
    enRevision: await base.cuantosEnRevision(),
    colgado: await Huerfanos(base).mirar(),
  );

  String get nombreParaVer =>
      nombre.isNotEmpty ? nombre : 'Una cuenta anterior';

  bool get tieneTrabajoSinSubir =>
      pendientes > 0 || rechazados > 0 || enRevision > 0 || colgado.hayAlguno;

  /// **QUÉ SE PIERDE SI SE BORRA ESTA COPIA**, nombrado cosa por cosa.
  ///
  /// Vive aquí y no en la pantalla a propósito: es lo que hay que poner delante
  /// de alguien ANTES de borrar, y escrito en la pantalla se olvida la mitad —
  /// que es exactamente lo que pasó. Vacío cuando no se pierde nada.
  ///
  /// Se nombra CADA cosa porque no son la misma: «3 apuntes sin subir» se
  /// arregla con señal, «1 rechazado» hace falta que alguien decida, y «1 ruta
  /// que sólo existe aquí» no se arregla sola de ninguna manera. «4 cosas» no
  /// le dice a nadie cuál de las tres tiene delante.
  String get queSePierde {
    final partes = <String>[
      if (pendientes > 0)
        '$pendientes ${pendientes == 1 ? 'apunte' : 'apuntes'} sin subir',
      if (rechazados > 0)
        '$rechazados ${rechazados == 1 ? 'rechazado esperando a que alguien '
                  'decida' : 'rechazados esperando a que alguien decida'}',
      if (enRevision > 0)
        '$enRevision ${enRevision == 1 ? 'entregado a revisión que nadie ha '
                  'decidido' : 'entregados a revisión que nadie ha decidido'}',
      if (colgado.hayAlguno) '${colgado.texto} que sólo existe en este aparato',
    ];
    if (partes.isEmpty) return '';
    if (partes.length == 1) return partes.first;
    final ultimo = partes.removeLast();
    return '${partes.join(', ')} y $ultimo';
  }

  @override
  String toString() =>
      'PersonaEnElAparato($nombreParaVer, pendientes: $pendientes, '
      'rechazados: $rechazados, enRevision: $enRevision, colgado: ${colgado.hayAlguno ? colgado.texto : "nada"})';
}

/// LAS COPIAS DEL APARATO: listarlas y **olvidar** una.
///
/// ## Por qué olvidar es un gesto aparte
///
/// Cerrar sesión **cambia de copia** y no borra nada, que es lo que hace posible
/// que dos personas se alternen en una tablet sin perder el día y sin que la
/// cola de una suba con el token de la otra
/// (`conexion/nombre.dart`). El precio es que los datos de quien salió siguen en
/// el disco, y eso hay que poder deshacerlo a mano.
///
/// Se hace a mano y no al salir porque **salir es lo que hacen diez veces al
/// día** dos personas que comparten el aparato: borrar ahí es tirar el día de
/// alguien sin decírselo, que es exactamente lo que el proyecto no puede
/// permitirse. Olvidar, en cambio, se pide una vez, se avisa antes si esa
/// persona tiene trabajo sin subir, y entonces sí se borra entero.
class Personas {
  const Personas();

  /// Las copias que hay, con su nombre y su cuenta de pendientes.
  ///
  /// **Sin la de quien está dentro ahora mismo**: esa copia está abierta, y
  /// ofrecerse a borrarla mientras se usa es un gesto que no puede acabar bien.
  /// Para irse está «Cerrar sesión».
  Future<List<PersonaEnElAparato>> listar({String? excepto}) async {
    final salida = <PersonaEnElAparato>[];
    for (final fichero in await copiasEnElAparato()) {
      final persona = await _mirar(fichero);
      if (persona == null) continue;
      if (persona.sub == excepto) continue;
      salida.add(persona);
    }
    salida.sort((a, b) => a.nombreParaVer.compareTo(b.nombreParaVer));
    return salida;
  }

  /// Borra la copia de [sub]: su dominio, **su cola** y su fichero.
  ///
  /// No pregunta nada: quien llama ya preguntó, con [listar] en la mano y con
  /// `tieneTrabajoSinSubir` y [PersonaEnElAparato.queSePierde] delante — ése es
  /// el texto que hay que enseñar, y nombra cada cosa. Esto es el gesto, no la
  /// decisión.
  Future<void> olvidar(String sub) async {
    final base = BaseLocal(dueno: sub);
    try {
      // SE MIRA ANTES DE BORRAR, y las tres cosas. Después no hay forma de
      // saberlo: el fichero ya no está.
      final queSePierde = await _queHayDentro(base);
      await base.olvidar();
      // **SE ANOTA SIEMPRE**, haya o no haya algo. Antes la línea sólo se
      // escribía `if (quedaban > 0)`, con `quedaban` contando únicamente los
      // pendientes: un cierre rechazado y una ruta huérfana se iban sin dejar
      // ni una línea, y al día siguiente no había forma de saber qué se llevó
      // por delante. Un borrado que no deja rastro es lo contrario de «nada se
      // descarta en silencio» (§4).
      Registro.aviso(
        queSePierde.isEmpty
            ? 'olvidada la copia de $sub: no le quedaba trabajo sin subir'
            : 'olvidada la copia de $sub CON TRABAJO SIN SUBIR: $queSePierde',
      );
    } finally {
      await _cerrarSinRuido(base);
    }
    await borrarLaCopia(sub);
    Registro.info('copia olvidada: $sub');
  }

  /// Lo que se va a llevar por delante, ya escrito. Vacío = no se pierde nada.
  Future<String> _queHayDentro(BaseLocal base) async {
    try {
      return (await PersonaEnElAparato.deLaBase(base)).queSePierde;
    } on Object catch (e) {
      // Que no se pueda contar NO puede impedir el gesto, pero tampoco puede
      // pasar callando: se anota que se borró sin saber qué había.
      Registro.aviso('no se pudo contar lo que llevaba la copia: $e');
      return 'no se pudo contar qué llevaba dentro';
    }
  }

  /// Abre una copia sólo para preguntarle quién es y qué le queda.
  Future<PersonaEnElAparato?> _mirar(String fichero) async {
    // El nombre del fichero no dice el `sub` —lleva la parte legible recortada y
    // una huella—, así que se le pregunta a la base, que lo tiene anotado.
    final base = BaseLocal.con(abrirConexionDeFichero(fichero));
    try {
      final sub = await base.duenoGuardado();
      if (sub == null) return null;
      // `await` ANTES del `finally`: el `finally` cierra la base, y devolver el
      // Future a secas la cerraria antes de contar.
      return await PersonaEnElAparato.deLaBase(
        base,
        sub: sub,
        nombre: await base.nombreDelDueno() ?? '',
      );
    } on Object catch (e) {
      Registro.aviso('no se pudo mirar la copia $fichero: $e');
      return null;
    } finally {
      await _cerrarSinRuido(base);
    }
  }
}

/// CERRAR UNA COPIA SIN QUE UN FALLO DE DRIFT SE LLEVE LA PANTALLA POR DELANTE.
///
/// `GeneratedDatabase.close()` recorre sus consultas vivas para cerrarlas, y si
/// alguna se apunta mientras recorre, revienta con «Concurrent modification
/// during iteration» (`drift/src/runtime/executor/stream_queries.dart:180`).
/// Aquí pasa de verdad y a diario: estas copias se abren **sólo para preguntar
/// quién es el dueño** en la propia pantalla de acceso, o sea mientras el resto
/// de la aplicación está montándose y pidiendo cosas.
///
/// Visto el 16/09/2026 en un Galaxy A16, en el log del teléfono:
///
/// ```
/// Unhandled Exception: Concurrent modification during iteration: _Map len:4.
///   StreamQueryStore.close   GeneratedDatabase.close
/// ```
///
/// Sin este `try`, eso sale como excepción NO CAPTURADA: no la ve nadie, no
/// aparece en pantalla, y lo que deja detrás es el `finally` a medias.
///
/// Se traga a propósito y se anota. Esto es cerrar un fichero del que ya se sacó
/// lo que se quería: si el cierre falla, no hay ningún dato en juego —el sistema
/// suelta el descriptor igual cuando muera el proceso—, y en cambio dejar que el
/// fallo suba sí rompe el gesto de quien está entrando.
Future<void> _cerrarSinRuido(BaseLocal base) async {
  try {
    await base.close();
  } on Object catch (e) {
    Registro.aviso('no se pudo cerrar una copia mirada de paso: $e');
  }
}

final personasProvider = Provider<Personas>((ref) => const Personas());

/// Quién más tiene datos en este aparato. Lo mira quien ofrezca el gesto de
/// olvidar; se recalcula al invalidarlo.
final personasEnElAparatoProvider = FutureProvider<List<PersonaEnElAparato>>(
  // `excepto`: la copia de quien está dentro está abierta, y ofrecerse a
  // borrarla mientras se usa es un gesto que no puede acabar bien. Para irse
  // está «Cerrar sesión».
  (ref) => ref
      .watch(personasProvider)
      .listar(excepto: ref.watch(duenoDeLaBaseProvider)),
);
