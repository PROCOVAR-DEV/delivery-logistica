import 'dart:async';

import '../identidad/almacen_sesion.dart';
import '../identidad/renovador.dart';
import '../identidad/sesion.dart';
import '../red/fallos.dart';
import '../registro/registro.dart';
import '../cola/cola_salida.dart';
import 'bajada.dart';
import 'huerfanos.dart';
import 'subida.dart';

/// Los tres pasos, en el orden en que TIENEN que ir.
///
/// El orden no es una preferencia de estilo, es lo que decide si el logistico
/// pierde el dia (`docs/sincronizacion.md`, «Orden al recuperar la senal»):
///
///  * **renovar antes de subir**: ocho horas sin cobertura dejan el token de
///    acceso caducado. Si la cola sale con el viejo, todo responde 401 y se para
///    con el trabajo del dia dentro.
///  * **subir antes de bajar**: bajar primero mete en la base la foto del
///    servidor, que todavia no sabe nada de lo que se hizo por la tarde, y pisa
///    lo que el aparato tiene sin subir.
enum PasoDelCiclo { renovar, subir, bajar }

/// POR DONDE VA EL CICLO, para quien lo este mirando.
///
/// Vive aqui y no en la pantalla porque el ciclo es el unico que lo sabe: el
/// candado de «uno en vuelo» hace que dos pantallas puedan estar mirando el
/// MISMO ciclo, y si cada una se inventara su propio progreso ensenarian dos
/// cosas distintas de lo mismo.
///
/// Se avisa al **empezar** cada paso, no al acabarlo: lo que hay que ver es en
/// que se esta ahora, no lo ultimo que se termino.
class AvanceDelCiclo {
  const AvanceDelCiclo(this.paso, {this.coleccion, this.tanda = 1});

  final PasoDelCiclo paso;

  /// La coleccion que se esta bajando, cuando [paso] es `bajar`. En los otros
  /// dos pasos es `null` y no hay nada que decir.
  final String? coleccion;

  /// En que tanda va la bajada, desde 1.
  final int tanda;

  @override
  String toString() => 'AvanceDelCiclo($paso, $coleccion, tanda: $tanda)';
}

/// LA MARCHA del ciclo que corre ahora mismo: desde cuando y por donde va.
///
/// Es una pieza sola y no dos porque las dos mitades se leen juntas —«va por
/// clientes, lleva 12 s»— y separarlas deja un fotograma en el que una ya se
/// actualizo y la otra no.
///
/// **Uno solo para toda la aplicacion**, como el candado: con dos pantallas
/// mirando el MISMO ciclo, dos marchas distintas ensenarian dos progresos
/// distintos de lo mismo.
class Marcha {
  const Marcha({this.empezadoA, this.avance});

  /// Quieto, sin ningun ciclo en vuelo.
  static const quieto = Marcha();

  /// Cuando arranco el ciclo que corre. `null` es que no corre ninguno.
  final DateTime? empezadoA;

  /// Por donde va. `null` mientras no haya dado el primer paso.
  final AvanceDelCiclo? avance;

  bool get enVuelo => empezadoA != null;

  @override
  String toString() => 'Marcha(empezadoA: $empezadoA, avance: $avance)';
}

/// Como quedo un ciclo. Nunca lanza: lo que salio mal viaja en [fallo].
///
/// Que no lance es deliberado. Al ciclo lo disparan un aviso de red y un
/// temporizador, dos sitios donde nadie esta esperando el resultado; una
/// excepcion que sale de ahi es un error asincrono sin duenno que en web acaba
/// en la consola y en la APK no acaba en ningun sitio.
class ResumenDelCiclo {
  const ResumenDelCiclo({
    this.pasos = const <PasoDelCiclo>[],
    this.subidos = 0,
    this.bajada = ResumenDeBajada.nada,
    this.fallo,
    this.sinSesion = false,
  });

  /// Sin sesion no se intenta NADA: ni ciclo, ni reintentos, ni temporizador.
  static const sinNadaQueHacer = ResumenDelCiclo(sinSesion: true);

  /// Los pasos que se llegaron a dar, EN ORDEN. Es lo que se mira para saber que
  /// no se salto ninguno ni se adelanto la bajada.
  final List<PasoDelCiclo> pasos;

  final int subidos;
  final ResumenDeBajada bajada;

  /// `FalloDeRed`, `SesionMuerta` o lo que fuera. `null` es que salio entero.
  final Object? fallo;

  /// `true` cuando no habia sesion y no se intento nada. **No es un fallo.**
  final bool sinSesion;

  bool get bien => fallo == null && !sinSesion;

  @override
  String toString() =>
      'ResumenDelCiclo(pasos: $pasos, subidos: $subidos, bajada: $bajada, '
      'fallo: $fallo, sinSesion: $sinSesion)';
}

/// EL CICLO DE SINCRONIZACION: renovar → subir → bajar.
///
/// Es lo que hace que el trabajo de una mannana sin cobertura suba solo cuando
/// el logistico llega a donde hay senal, sin que tenga que acordarse de recargar
/// la pagina. El dia que se le olvide, el trabajo se queda en el telefono.
///
/// ## Las reglas que sostiene esta clase
///
///  * **Un solo ciclo en vuelo.** Si llega un aviso de red mientras uno corre,
///    NO se lanza otro: quien llega se engancha al que ya va. Dos ciclos a la
///    vez son dos subidas del mismo lote y dos bajadas pisandose.
///  * **Una sola renovacion en vuelo.** Eso ya esta resuelto en [Renovador] con
///    su candado y aqui NO se reimplementa: se llama y ya. Dos renovaciones a la
///    vez con el mismo refresh el servidor las lee como robo y revoca todas las
///    sesiones de la cuenta, justo en el momento en que el logistico iba a subir
///    el dia (`docs/identidad.md`, regla 2).
///  * **Sin sesion no se intenta nada.** Entrar exige conexion y ahi manda el
///    portero; el ciclo le pregunta y se calla.
///  * **Si el ciclo falla, la cola NO se toca.** Lo que no subio sigue
///    pendiente. Quien resuelve apuntes es la cola, con la respuesta del
///    servidor en la mano, y nadie mas.
class CicloDeSincronizacion {
  CicloDeSincronizacion({
    required AlmacenDeSesion almacen,
    required Renovador renovador,
    required Subida subida,
    required Bajada bajada,
    required Huerfanos huerfanos,
    required ColaDeSalida cola,
    required bool Function() haySesion,
    void Function()? alMorirLaSesion,
    void Function()? alEmpezar,
    void Function()? alTerminar,
    void Function(AvanceDelCiclo)? alAvanzar,
    void Function(ResumenDelCiclo)? alAcabar,
  }) : _alAvanzar = alAvanzar,
       _alAcabar = alAcabar,
       _almacen = almacen,
       _renovador = renovador,
       _subida = subida,
       _bajada = bajada,
       _huerfanos = huerfanos,
       _cola = cola,
       _haySesion = haySesion,
       _alMorirLaSesion = alMorirLaSesion,
       _alEmpezar = alEmpezar,
       _alTerminar = alTerminar;

  final AlmacenDeSesion _almacen;
  final Renovador _renovador;
  final Subida _subida;
  final Bajada _bajada;

  /// Quien mira lo que este aparato tiene y arriba no. Ver `huerfanos.dart`.
  final Huerfanos _huerfanos;
  final ColaDeSalida _cola;
  final bool Function() _haySesion;
  final void Function()? _alMorirLaSesion;
  final void Function()? _alEmpezar;
  final void Function()? _alTerminar;

  /// Quien pinta «va por clientes». Opcional a proposito: el vigia y el
  /// temporizador disparan ciclos que no esta mirando nadie.
  final void Function(AvanceDelCiclo)? _alAvanzar;

  /// COMO QUEDO, para quien lleve la cuenta de si las peticiones llegan.
  ///
  /// Se avisa de TODOS los ciclos, tambien de los que dispara el vigia sin que
  /// nadie mire: son justamente los que dicen si la conexion sirve, porque
  /// ocurren solos cada cinco minutos.
  final void Function(ResumenDelCiclo)? _alAcabar;

  /// EL CANDADO del ciclo. Mientras no sea `null` hay uno corriendo.
  Future<ResumenDelCiclo>? _enVuelo;

  bool get enVuelo => _enVuelo != null;

  /// Corre el ciclo, o devuelve el que ya va.
  ///
  /// [motivo] sale en el registro y es lo unico que distingue «volvio la red» de
  /// «toco el reloj» cuando hay que entender despues por que subio algo a las
  /// once y veinte.
  ///
  /// **El aviso de red dispara un INTENTO, no da por hecho que hay red**
  /// (`pubspec.yaml`: «PISTA de que hay red, nunca la verdad»). En Cuba el
  /// aparato dice que hay wifi y no sale un paquete. Por eso un ciclo que falla
  /// no marca nada como hecho: la cola se queda entera y se vuelve a intentar.
  ///
  /// [yaSeRenovo] se pasa **sólo** desde donde acaba de haber un par nuevo en la
  /// mano: el arranque, que renueva antes de dejar entrar, y la pantalla de
  /// acceso, que acaba de recibir el par de `POST /token`. Renovar otra vez dos
  /// dedos despues es una ida y vuelta regalada por la conexion de alla y una
  /// rotacion del refresh que no hacia falta. En cualquier otro sitio va a
  /// `false` y el paso 1 se hace, que es la regla.
  /// [avisoDe] es el TIPO del aviso que disparo este ciclo, si lo disparo uno.
  ///
  /// Hoy lo usa una sola cosa y por un motivo medido: los almacenes ya no se
  /// piden en cada vuelta —eran el 82 % de lo que se gastaba en reposo— sino
  /// cada hora. Sin esto, alguien que cambia un almacen desde el reparto
  /// tendria que esperarse esa hora aunque el aviso llegara al instante.
  ///
  /// Va como tipo y no colado dentro de [motivo] a proposito: `motivo` es un
  /// texto para el registro, y decidir mirando un texto que alguien puede
  /// reescribir es la clase de atadura que se rompe sin que nada falle.
  Future<ResumenDelCiclo> ahora({
    String motivo = 'a mano',
    bool yaSeRenovo = false,
    String? avisoDe,
  }) {
    final yaVa = _enVuelo;
    if (yaVa != null) {
      // SE APUNTA QUE HAY QUE VOLVER A DARLA — 17/09/2026.
      //
      // Aqui ponia «ni se encola ni se descarta el trabajo: quien llega se
      // engancha al que ya corre». Lo segundo era mentira: **si se descartaba**.
      //
      // El ciclo es renovar → subir → bajar. Si llega un gesto cuando el ciclo
      // en vuelo ya pasó por «subir», ese ciclo NO lleva el gesto dentro — subio
      // lo que habia antes—, asi que engancharse a el es esperar al temporizador:
      // dos minutos en la web, cinco en la APK.
      //
      // Medido en produccion: un arrastre en la web tardo **50 segundos** en
      // llegar al servidor. Jose: «¿por que se demora en traer esas cosas tanto
      // tiempo si debe ser en tiempo real todo esto cuando tenga internet?».
      //
      // Es el mismo apaño que ya tiene `refrescar()` del tablero con su
      // `_otraVez`, y por el mismo motivo: descartar el aviso deja la pantalla
      // —o la cola— en lo de antes del ultimo cambio, que es el fallo que nadie
      // sabe reproducir.
      // No se marca nada aqui: si este aviso traia trabajo, al terminar la
      // vuelta quedara en la cola y de eso se encarga `_haceFaltaOtraVuelta`.
      // Marcarlo aqui daria una vuelta de mas por cada aviso repetido —la
      // antena que coge y suelta dos veces— y cada vuelta es una renovacion.
      Registro.info('ciclo: ya hay uno en vuelo, no se lanza otro ($motivo)');
      return yaVa;
    }

    // Sin sesion no se intenta NADA. Va ANTES de tocar la red, el reloj o la
    // cola: un ciclo sobre una sesion muerta son peticiones que van a dar 401 y
    // trabajo corriendo sobre alguien que ya se fue.
    if (!_haySesion()) {
      Registro.info('ciclo: sin sesion, no se intenta nada ($motivo)');
      return Future<ResumenDelCiclo>.value(ResumenDelCiclo.sinNadaQueHacer);
    }

    // `_correr` es `async`, asi que devuelve en el primer `await` y esta
    // asignacion pasa antes de que nadie pueda volver a entrar aqui.
    final futuro = _correr(motivo, yaSeRenovo: yaSeRenovo, avisoDe: avisoDe);
    _enVuelo = futuro;
    futuro
        .then((resumen) async {
          _enVuelo = null;
          if (await _haceFaltaOtraVuelta(resumen)) {
            // `yaSeRenovo`: el par es de hace un instante, el de la vuelta que
            // acaba de terminar. Renovar otra vez seria una rotacion del refresh
            // que no hace falta — y dos con el mismo el servidor las lee como
            // robo (`identidad.md`).
            ahora(motivo: 'quedó trabajo de mitad de ciclo', yaSeRenovo: true)
                .ignore();
          }
        })
        .catchError((_) => _enVuelo = null)
        .ignore();
    return futuro;
  }

  /// ¿Se quedo trabajo fuera de la vuelta que acaba de terminar?
  ///
  /// El ciclo es renovar → subir → bajar. Un gesto que llega **despues** del
  /// paso de subir no viaja en esa vuelta: se engancha a ella, se entera de su
  /// resultado, y su apunte se queda en la cola esperando al temporizador —dos
  /// minutos en la web, cinco en la APK—. Medido en produccion el 17/09/2026:
  /// un arrastre en la web tardo **50 segundos** en llegar al servidor.
  ///
  /// La señal de que paso eso es exacta: **la vuelta fue bien y aun asi queda
  /// algo pendiente**. Si hubiera ido mal, lo pendiente seria lo que no se pudo
  /// subir y volver a intentarlo al instante seria machacar; para eso esta el
  /// temporizador.
  ///
  /// Y no hace bucle: la segunda vuelta sube lo que quedaba y deja la cola
  /// vacia, asi que no pide una tercera.
  Future<bool> _haceFaltaOtraVuelta(ResumenDelCiclo resumen) async {
    if (!resumen.bien) return false;
    try {
      return (await _cola.lote(maximo: 1)).isNotEmpty;
    } on Object catch (e) {
      Registro.aviso('ciclo: no se pudo mirar si quedaba trabajo: $e');
      return false;
    }
  }

  ResumenDelCiclo _contar(ResumenDelCiclo resumen) {
    _alAcabar?.call(resumen);
    return resumen;
  }

  /// EL TIPO DE AVISO QUE OBLIGA A PEDIR LOS ALMACENES AL MOMENTO.
  ///
  /// Es el literal de `CambioEnVivo.almacenes`, y **no se importa** a proposito:
  /// esa constante vive en `nucleo/refresco_en_vivo.dart`, que arrastra Riverpod,
  /// y el ciclo de sincronizacion no depende de Riverpod ni debe empezar a
  /// hacerlo.
  ///
  /// Que sean el mismo texto lo ata una prueba y **no este comentario** (§3-bis
  /// del `CLAUDE.md`): un comentario no falla, y si alguien renombra el aviso,
  /// esto deja de forzar nada y los almacenes tardan una hora en llegar sin que
  /// nada avise.
  ///
  /// Ojo, que no es el nombre de la coleccion: el aviso se llama `almacenes` y la
  /// coleccion `warehouses`.
  static const avisoQueFuerzaLosAlmacenes = 'almacenes';

  Future<ResumenDelCiclo> _correr(
    String motivo, {
    required bool yaSeRenovo,
    String? avisoDe,
  }) async {
    final pasos = <PasoDelCiclo>[];
    var subidos = 0;
    var bajada = ResumenDeBajada.nada;

    _alEmpezar?.call();
    try {
      // 1 · RENOVAR. Primero, SIEMPRE.
      _alAvanzar?.call(const AvanceDelCiclo(PasoDelCiclo.renovar));
      if (yaSeRenovo) {
        Registro.info('ciclo: el par es de hace un instante, no se renueva');
      } else {
        final Sesion? guardada = await _almacen.leer();
        if (guardada != null) {
          await _renovador.renovar(guardada);
        } else {
          // En web el almacen devuelve `null` siempre: alli la sesion es la
          // cookie y quien la renueva es auth por su cuenta (`identidad.md`).
          // No es un fallo y no para el ciclo — pararlo dejaria la web sin
          // subir nunca.
          Registro.info('ciclo: sin par guardado, manda la cookie (web)');
        }
        pasos.add(PasoDelCiclo.renovar);
      }

      // 2 · COMPROBAR LA DIFERENCIA antes de subir: lo que este aparato tiene y
      // arriba no existe, y que no le queda ningun apunte que lo suba.
      //
      // El sincronizador no es un reenviador de cola: **es el que controla la
      // diferencia entre los dos lados**. Sin esto, un apunte que desaparece
      // —descartado a mano, o perdido— deja el dato local huerfano para siempre,
      // a la vista en su pantalla y en ningun otro sitio, mientras el Panel dice
      // «Todo al dia». Pasó con la zona «Vista» y sus cinco pedidos.
      //
      // Va ANTES de subir a proposito: lo que se vuelva a encolar aqui sale en
      // esta misma vuelta, no en la siguiente. Y no hace bucle: si el servidor
      // dice que no, el apunte queda `rechazado` —que cuenta como vivo— y la
      // vuelta de despues ya no lo ve huerfano.
      final reencolados = await _huerfanos.volverAEncolar(_cola);
      if (reencolados > 0) {
        Registro.aviso(
          'el aparato tenía trabajo que no iba a subir solo: se volvieron a '
          'encolar $reencolados apuntes',
        );
      }

      // 3 · SUBIR la cola, con el token ya fresco.
      //
      // SE CUENTA SEGUN SUBEN, no al final. La subida va de uno en uno
      // (`subida.dart`, 01/10/2026), asi que un corte a mitad de cola deja
      // apuntes arriba y lanza: con `subidos = await ...` a secas, esa
      // asignacion no llega a pasar y el cajon de «Entregar el dia» pintaria
      // «Subieron 0 apuntes» encima de dos que SI subieron. El `quedan` de esa
      // misma pantalla sale de la base y diria la verdad, asi que las dos
      // mitades del mismo cartel se contradirian.
      _alAvanzar?.call(const AvanceDelCiclo(PasoDelCiclo.subir));
      subidos = await _subida.ciclo(alSubirUno: (van) => subidos = van);
      pasos.add(PasoDelCiclo.subir);

      // 4 · BAJAR las diferencias, ya sin nada del aparato pendiente que pisar.
      _alAvanzar?.call(const AvanceDelCiclo(PasoDelCiclo.bajar));
      final avisar = _alAvanzar == null
          ? null
          : (AvanceDeBajada a) => _alAvanzar.call(
              AvanceDelCiclo(
                PasoDelCiclo.bajar,
                coleccion: a.coleccion,
                tanda: a.tanda,
              ),
            );
      bajada = await _bajada.ciclo(avisar: avisar);
      // Los almacenes son la ULTIMA peticion del ciclo y van fuera de la
      // transaccion de las diferencias, asi que son justo las que se quedan sin
      // bajar cuando la senal se va a mitad de gesto. Que avisen tambien es lo
      // que deja decir «faltan los almacenes» en vez de «hubo un error».
      // LOS ALMACENES, y ya NO en cada vuelta: eran el 82 % de lo que se
      // gastaba en reposo (2.671 de 3.255 bytes, medido el 29/09/2026). Se piden
      // cada hora, la primera vez, y **al momento si el aviso es suyo** — que es
      // el caso de alguien cambiandolos desde el reparto. El porque entero, en
      // `Bajada.almacenes`.
      await _bajada.almacenes(
        avisar: avisar,
        tanda: bajada.tandas,
        forzar: avisoDe == avisoQueFuerzaLosAlmacenes,
      );
      pasos.add(PasoDelCiclo.bajar);

      Registro.info('ciclo hecho ($motivo): $subidos apuntes subidos, $bajada');
      return _contar(
        ResumenDelCiclo(pasos: pasos, subidos: subidos, bajada: bajada),
      );
    } on SesionMuerta catch (e) {
      // Un 401 que sigue siendo 401 despues de renovar. Los tokens ya los borro
      // el renovador; lo que falta es sacar a la persona, porque si no el
      // temporizador seguiria disparando ciclos contra una sesion que no existe.
      Registro.aviso('ciclo: la sesion murio ($motivo): $e');
      _alMorirLaSesion?.call();
      return _contar(
        ResumenDelCiclo(
          pasos: pasos,
          subidos: subidos,
          bajada: bajada,
          fallo: e,
        ),
      );
    } on Object catch (e, pila) {
      // `FalloDeRed` y cualquier otra cosa. **La cola no se toca**: lo que no
      // subio sigue pendiente y se vuelve a intentar al proximo aviso o al
      // proximo tic. Nunca se descarta un apunte porque una subida fallara.
      Registro.fallo('ciclo: no se pudo completar ($motivo)', e, pila);
      return _contar(
        ResumenDelCiclo(
          pasos: pasos,
          subidos: subidos,
          bajada: bajada,
          fallo: e,
        ),
      );
    } finally {
      _alTerminar?.call();
    }
  }
}
