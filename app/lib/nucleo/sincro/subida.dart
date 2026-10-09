import 'package:drift/drift.dart';

import '../base/base.dart';
import '../cola/apunte.dart';
import '../cola/cola_salida.dart';
import '../red/cliente_api.dart';
import '../red/fallos.dart';
import '../registro/registro.dart';
import 'identidad_del_aparato.dart';

/// LA COLA DE OTRO. Se intento subir la cola de una persona con el token de la
/// que esta delante.
///
/// Nunca deberia lanzarse, y por eso existe: cada persona tiene su fichero de
/// base (`nucleo/base/conexion/nombre.dart`), asi que con B delante la cola de A
/// ni siquiera esta abierta. Esta es la segunda cerradura, la que sigue valiendo
/// el dia que alguien cambie como se abren las bases.
///
/// Lo que pasa cuando salta: **no se manda nada y la cola no se toca**. Los
/// apuntes de A siguen enteros y suben el dia que entre A, con SU token. Subir
/// con el token de quien esta delante seria el trabajo de una sucursal
/// apareciendo en otra, y eso no se ve en ningun sitio hasta que no cuadra el
/// inventario.
class ColaDeOtraPersona implements Exception {
  const ColaDeOtraPersona({
    required this.duenoDeLaCola,
    required this.quienEsta,
  });

  /// El `sub` de quien hizo los apuntes.
  final String duenoDeLaCola;

  /// El `sub` de quien tiene la sesion abierta ahora mismo.
  final String? quienEsta;

  @override
  String toString() =>
      'ColaDeOtraPersona(la cola es de $duenoDeLaCola y quien esta es '
      '${quienEsta ?? "nadie"}; no se sube nada)';
}

/// `POST /sync/subida` — la cola del aparato, DE UNO EN UNO y en el orden en que
/// se hizo.
///
/// ## Un apunte, una peticion, una detras de otra — 01/10/2026
///
/// Hasta hoy esto mandaba **un solo lote**: hasta 200 apuntes dentro de una
/// unica peticion. Jose: «las subidas sin conexion es por cola para q no caiga
/// todo de una y suba uno a uno las cosas q se hicieron».
///
/// Y tiene razon, porque el que paga la diferencia es el reparto en Cuba: **una
/// peticion grande que se corta al 90 % no deja nada**. Medido en su telefono el
/// 01/10/2026: tres gestos hechos sin cobertura salieron en UNA peticion de 6.368
/// bytes. Si esa peticion se cae, los tres se quedan abajo y hay que volver a
/// empezar por el primero. De uno en uno, lo que ya paso **se queda arriba** y
/// solo se reintenta lo que falta. Con una jornada entera de trabajo dentro del
/// telefono, esa diferencia es el dia.
///
/// ## LO QUE SIGUE PROHIBIDO, que no es lo mismo
///
/// Son TRES disenos distintos y confundirlos cuesta el candado de renovacion:
///
///  1. **un solo lote** — lo que habia;
///  2. **N en paralelo** — veinte peticiones A LA VEZ al recuperar la senal es
///     lo que dispara veinte 401 a la vez, y eso es lo que el candado de
///     renovacion tiene que aguantar (caso I1). **Esto sigue prohibido.**
///  3. **N secuenciales**, cada una esperando su respuesta antes de mandar la
///     siguiente — lo que hay ahora.
///
/// El 3 no es el 2: en el bucle de [Subida.ciclo] hay un `await` por apunte, asi
/// que **nunca hay dos peticiones de esta cola en vuelo a la vez**. Un 401 a
/// mitad de cola es UN 401, lo renueva el cliente y la cola sigue. Lo que el caso
/// I1 prohibe es la simultaneidad, no la cantidad.
///
/// ## Lo que cuesta, dicho con el numero
///
/// El sobre de cada `POST /sync/subida` son ~579 bytes medidos (la vuelta vacia).
/// Pagarlo 200 veces en vez de una son ~116 KB de mas en el peor dia imaginable.
/// Es caro y se paga a gusto: la alternativa es que un corte deje 0 bytes de
/// progreso. En un dia normal son ~12 apuntes (`jornada_entera_sin_senal_test`),
/// o sea unos 7 KB de sobres.
/// LA MARCA DEL UNICO 404 QUE SIGNIFICA «date de alta otra vez».
///
/// La manda `sync/internal/httpx` (`CodigoAparatoNoRegistrado`). Las dos partes
/// tienen que decir lo mismo: lo ata
/// `test/nucleo/sincro/solo_un_404_tira_el_aparato_test.dart`.
const marcaDeAparatoNoRegistrado = 'aparato_no_registrado';

/// CUANTOS APUNTES COMO MAXIMO SALEN EN UNA VUELTA DEL CICLO. **Doscientos.**
///
/// Con el lote unico este numero era «cuantos caben en una peticion»; ahora es
/// **cuantas peticiones se hacen seguidas**, asi que hay que justificarlo otra
/// vez (§3 del `CLAUDE.md`: un tope que no se comprueba es el fallo que mas caro
/// sale aqui).
///
/// Sigue siendo 200, y el tope **no se quita**, por dos razones:
///
///  * Una vuelta tiene que terminar. Despues de subir viene BAJAR, y una cola de
///    mil apuntes sin tope dejaria al aparato sin bajar el tablero durante toda
///    la subida. El tope es lo que acota la vuelta.
///  * Lo que sobra NO se pierde ni espera al temporizador: la vuelta acaba
///    `bien`, queda cola, y `CicloDeSincronizacion._haceFaltaOtraVuelta` lanza
///    otra en el acto —**sin renovar otra vez**, que es lo que haria dano—.
///
/// Y 200 es un techo, no una medida: una jornada entera sin senal son ~12
/// apuntes. Si alguna vez se alcanza de verdad, se ve, porque la vuelta siguiente
/// sale sola y el registro la nombra.
const topeDeLaVuelta = 200;

class Subida {
  Subida({
    required ClienteApi cliente,
    required ColaDeSalida cola,
    required IdentidadDelAparato aparato,
    required BaseLocal base,
    required Future<String?> Function() quienEsta,
    void Function()? alFaltarPermiso,
  }) : _alFaltarPermiso = alFaltarPermiso,
       _cliente = cliente,
       _cola = cola,
       _aparato = aparato,
       _base = base,
       _quienEsta = quienEsta;

  final ClienteApi _cliente;
  final ColaDeSalida _cola;

  /// La base de donde sale la cola. Se le pregunta de quien es.
  final BaseLocal _base;

  /// El `sub` de quien tiene la sesion abierta. Es lo que se compara con el
  /// dueno de la cola antes de mandar un solo apunte.
  final Future<String?> Function() _quienEsta;

  /// Se avisa si el servidor devuelve, DENTRO de un 200, el rechazo de «no tienes
  /// permiso para entrar a Reparto». Ver [_aplicar].
  final void Function()? _alFaltarPermiso;

  /// Quien sabe el identificador de esta instalacion y sabe darla de alta.
  final IdentidadDelAparato _aparato;

  /// Sube la cola **de uno en uno** y aplica cada resultado en cuanto llega.
  /// Devuelve cuantos apuntes **aceptó el servidor**.
  ///
  /// Aceptados, no resueltos: un rechazado tambien se resuelve —queda en la
  /// bandeja con su motivo— pero **no subio**, y contarlo aqui hace que la
  /// pantalla diga «Subieron 1 apunte» justo encima de «1 rechazado esperando a
  /// que alguien decida». Visto en el navegador el 15/09/2026, y es la clase de
  /// contradiccion que le quita el valor a todo lo demas que diga la pantalla.
  ///
  /// ## Lo que lanza, y lo que YA subio cuando lanza
  ///
  /// Lo que lance sale tal cual: si es `FalloDeRed`, lo que no se mando sigue
  /// pendiente y se reintenta luego; si es `SesionMuerta`, quien llama manda a la
  /// pantalla de acceso. En ningun caso se borra un apunte por no haber podido
  /// subirlo.
  ///
  /// **Pero ahora un corte a mitad deja apuntes arriba**, y eso es justamente lo
  /// que se venia a ganar. Por eso existe [alSubirUno]: una excepcion no puede
  /// devolver un numero, y sin ella el cajon de «Entregar el dia» pintaria
  /// «Subieron 0 apuntes» encima de dos que SI subieron. Un numero que se lee
  /// bien y esta mal es el peor fallo de esta casa.
  ///
  /// [alSubirUno] se llama con el total que va aceptado, despues de cada apunte
  /// que el servidor acepta y que la cola ya ha marcado. No se llama por un
  /// rechazado: ese se resuelve pero no sube.
  Future<int> ciclo({
    int maximo = topeDeLaVuelta,
    void Function(int yaSubieron)? alSubirUno,
  }) async {
    final lote = await _cola.lote(maximo: maximo);
    if (lote.isEmpty) return 0;

    // LA GUARDA: esta cola tiene que ser de quien esta delante.
    //
    // Va ANTES del alta del aparato y antes de tocar la red, porque lo que no
    // puede pasar de ninguna manera es que un apunte de A salga firmado con el
    // token de B. Ver [ColaDeOtraPersona].
    await _laColaEsDeQuienEsta();

    var aceptados = 0;
    for (var i = 0; i < lote.length; i++) {
      // EL ALTA, ANTES DEL PRIMER ENVIO. Si falla, lo que lance sale de aqui tal
      // cual y la cola no se toca: sin aparato registrado el servidor contesta
      // 404 y no se sube nada, asi que dar el apunte por bueno seria tirar el
      // dia.
      //
      // Va DENTRO del bucle y no antes, y no cuesta nada: `asegurar()` se cachea
      // en memoria, asi que del segundo apunte en adelante no toca ni la base.
      // Lo que gana es que si uno de los de en medio se come el 404 de «date de
      // alta otra vez», los que quedan detras salen ya con el identificador
      // nuevo.
      final aparato = await _aparato.asegurar();

      // SE VUELVE A LEER EL APUNTE JUSTO ANTES DE MANDARLO, y no es paranoia.
      //
      // El apunte de delante pudo traer el id de verdad de un `local-…`, y
      // `Provisionales.sustituir` reescribe con el la ruta y el cuerpo de **los
      // que quedan en la cola**. Con el lote unico eso daba igual —los cuerpos se
      // serializaban todos a la vez y traducia el servidor—; de uno en uno,
      // mandar la copia que se leyo al principio seria mandar `local-9f3a…`
      // teniendo ya el `cm2x…` en la mano. Es el caso S4 por el lado nuevo.
      final apunte = await _cola.porClave(lote[i].clave);
      if (apunte == null || apunte.estado != EstadoApunte.pendiente) {
        // No se descarta nada en silencio (§4): esto no deberia pasar nunca
        // —nada saca un apunte de `pendiente` mientras este bucle corre— y si
        // pasa, se dice y se sigue con los demas.
        Registro.aviso(
          'el apunte ${lote[i].clave} dejo de estar pendiente mientras subia la '
          'cola (${apunte?.estado}): no se manda',
        );
        continue;
      }

      // Una hoja rechazada o sin acuse no permite congelar esa ruta como
      // histórico. Se consulta la cola persistente: también vale en la próxima
      // vuelta o después de reiniciar. Los apuntes independientes sí siguen.
      if (await _cierreSinAceptar(apunte)) {
        Registro.aviso(
          'no se completa ${apunte.ruta}: sus resultados siguen pendientes '
          'o rechazados en la bandeja',
        );
        continue;
      }

      final Map<String, Object?> respuesta;
      try {
        respuesta = await _mandarUno(aparato, apunte);
      } on Object {
        // EL CORTE A MITAD DE COLA, DICHO CON LOS DOS NUMEROS.
        //
        // Lo de antes ya esta arriba y no se vuelve a mandar; este y los de
        // detras siguen pendientes. Esto es lo unico que deja entender manana
        // por que de doce gestos aparecieron siete.
        final quedan = lote.length - i;
        Registro.aviso(
          'la subida se corto en el apunte ${i + 1} de ${lote.length}: '
          '$aceptados ya estan arriba y $quedan '
          '${quedan == 1 ? "sigue pendiente" : "siguen pendientes"}',
        );
        rethrow;
      }

      if (await _aplicar(apunte, respuesta)) {
        aceptados++;
        alSubirUno?.call(aceptados);
      }
    }
    return aceptados;
  }

  Future<bool> _cierreSinAceptar(Apunte apunte) async {
    final cuerpo = ColaDeSalida.cuerpoDe(apunte);
    if (apunte.metodo != 'PATCH' ||
        !RegExp(r'^/routes/[^/]+$').hasMatch(apunte.ruta) ||
        cuerpo is! Map ||
        cuerpo['status'] != 'completed') {
      return false;
    }
    final bloqueantes =
        await (_base.select(_base.apuntes)
              ..where(
                (a) =>
                    a.orden.isSmallerThanValue(apunte.orden) &
                    a.ruta.equals('${apunte.ruta}/results') &
                    // `enRevision` TAMBIEN retiene el cierre: sus resultados
                    // estan entregados pero NO aplicados, y completar la ruta la
                    // congela como historico — el revisor aplicaria despues
                    // unos resultados sobre una ruta que ya no admite cambios.
                    (a.estado.equalsValue(EstadoApunte.pendiente) |
                        a.estado.equalsValue(EstadoApunte.rechazado) |
                        a.estado.equalsValue(EstadoApunte.enRevision)),
              )
              ..limit(1))
            .get();
    return bloqueantes.isNotEmpty;
  }

  /// Aplica la respuesta de UN apunte. Devuelve `true` si el servidor lo acepto.
  ///
  /// Se casa por `clave`, NO por posicion, y de uno en uno eso vale MAS que
  /// antes: la respuesta de esta peticion solo puede hablar del apunte que iba
  /// dentro. Una respuesta que nombra otra clave es un servidor equivocado o una
  /// respuesta de otra peticion, y resolver con ella marcaria como rechazado un
  /// apunte que nadie mando — trabajo perdido en el sitio que no es, sin un solo
  /// error por ningun lado.
  Future<bool> _aplicar(Apunte apunte, Map<String, Object?> respuesta) async {
    final crudos = respuesta['resultados'];
    if (crudos is! List) {
      throw const FormatException('la subida no devolvio `resultados`');
    }

    for (final crudo in crudos) {
      if (crudo is! Map<String, Object?>) continue;
      final clave = crudo['clave'] as String?;
      if (clave == null) {
        Registro.fallo('resultado de subida sin clave: $crudo');
        continue;
      }
      if (clave != apunte.clave) {
        Registro.fallo(
          'se mando ${apunte.clave} y la respuesta habla de $clave: no se '
          'resuelve ninguno de los dos',
        );
        continue;
      }
      final resultado = ResultadoApunte.deJson(crudo);
      // «NO TIENES PERMISO PARA ENTRAR A REPARTO» NO ES UN RECHAZO DE ESTE APUNTE.
      //
      // Es la PERSONA la que no entra, y resolver el apunte como rechazado
      // convertiria su cola entera en rechazos: trabajo destruido por algo que
      // arregla un administrador dandole el rol. Un 403 con ese `codigo` en la
      // respuesta HTTP ya lo ataja el interceptor; esta es la SEGUNDA CERRADURA,
      // para un sync que lo reenvie como rechazo dentro de un 200 (hoy lo hace:
      // `sync/internal/reparto`, «cualquier 4xx es rechazo»). Como el 401: no se
      // resuelve nada, el apunte sigue `pendiente` y el ciclo para.
      if (resultado.motivo == textoSinPermisoDeReparto) {
        _alFaltarPermiso?.call();
        throw const Rechazo(
          403,
          textoSinPermisoDeReparto,
          marca: marcaSinPermisoDeReparto,
        );
      }
      await _cola.resolver(clave, resultado);
      return resultado.seAplico;
    }

    // Subio y no se sabe como quedo. Se queda pendiente y se reintenta: la
    // `clave` es lo que hace que ese reintento vuelva `repetido` en vez de
    // duplicar el cierre de la ruta.
    Registro.aviso(
      'el apunte ${apunte.clave} subio sin respuesta; se queda pendiente',
    );
    return false;
  }

  /// Comprueba que la cola que se va a subir es de quien tiene la sesion.
  ///
  /// Una base **sin dueno anotado** pasa: es la de las pruebas y la de un
  /// aparato que viene de antes de que esto existiera, y ahi no hay nada que
  /// comparar. Lo que no pasa es un dueno anotado que no sea el de la sesion.
  /// ## «No sé quién está» NO es «está otro» — 16/09/2026
  ///
  /// Esta guarda impide que la cola de A suba firmada con el token de B. Bien.
  /// Pero comparaba `null` con un `sub` y trataba la diferencia como una prueba
  /// de que hay otra persona delante, y `null` no prueba nada: **es la ausencia
  /// del dato, no un dato distinto.**
  ///
  /// En la web `_quienEsta()` devuelve `null` SIEMPRE, porque alli la sesion es
  /// la cookie del acceso unico y no se guarda ningun token en el aparato. Y
  /// `duenoGuardado()` si devuelve el `sub`, que se anota al entrar. Asi que la
  /// comparacion no cuadraba nunca y esto **lanzaba en cada ciclo**: la web no ha
  /// podido subir ni un apunte desde que existe.
  ///
  /// Lo que encadenaba detras es lo que se veia: la cola se quedaba llena para
  /// siempre, y el tablero se niega a bajar mientras haya cola —con razon, para
  /// no pisar lo que no ha subido—, asi que **la pantalla se congelaba a la hora
  /// en que alguien hizo el primer gesto** y refrescar no hacia nada. Visto el
  /// 16/09/2026: el tablero de la web llevaba hora y media parado y lo que subia
  /// el telefono no aparecia nunca.
  ///
  /// El comentario de `proveedores.dart` decia que «en web el almacen devuelve
  /// null siempre: ahi no hay con que comparar y la guarda deja pasar, que es lo
  /// correcto». Describia lo que tenia que pasar, no lo que pasaba.
  ///
  /// Se bloquea solo con una CONTRADICCION de verdad: se sabe quien esta, y no es
  /// el dueno de la cola. En el movil eso sigue intacto, que es donde hay dos
  /// personas compartiendo un aparato. En un navegador no las hay.
  Future<void> _laColaEsDeQuienEsta() async {
    final deQuienEs = await _base.duenoGuardado();
    if (deQuienEs == null) return;
    final quienEsta = await _quienEsta();
    if (quienEsta == null || quienEsta == deQuienEs) return;
    final fallo = ColaDeOtraPersona(
      duenoDeLaCola: deQuienEs,
      quienEsta: quienEsta,
    );
    Registro.fallo('$fallo');
    throw fallo;
  }

  /// Manda UN apunte, y si el servidor dice que este aparato **no esta
  /// registrado**, se da de alta otra vez y lo manda UNA sola vez mas.
  ///
  /// Ese 404 es un caso real y no una rareza: al aparato lo borraron del
  /// registro, o se restauro una copia de la base local con un alta que ya no
  /// existe. El servidor lo contesta con 404 y no con 401 justamente para que el
  /// aparato pueda distinguirlo de una sesion caducada y arreglarlo solo
  /// (`sync/internal/sincro/bajada.go`).
  ///
  /// **UNA sola vez**, y no en bucle: si el alta nueva tampoco sirve, lo que
  /// toca es que el fallo suba y se vea, no gastarle la bateria y los datos al
  /// logistico reintentando contra algo que no va a cambiar.
  ///
  /// El cuerpo sigue siendo el del protocolo —una lista `apuntes`— con **uno
  /// dentro**. No se cambia la forma: la firman las dos partes
  /// (`sync/internal/sincro/subida.go`), las APK instaladas la usan, y un
  /// servidor que un dia reciba un lote de dos de una version vieja tiene que
  /// seguir sabiendo leerlo.
  Future<Map<String, Object?>> _mandarUno(
    String aparato,
    Apunte apunte, {
    bool reintentar = true,
  }) async {
    try {
      return await _cliente.mandar<Map<String, Object?>>('POST', '/subida', <
        String,
        Object?
      >{
        'aparato': aparato,
        // Cuantos quedan DESPUES de este envio. Lo dice el aparato porque la
        // cola vive en el telefono: lo que no ha subido no existe en el
        // servidor, y sin este numero el panel ensenaria a Palma en verde
        // justo el dia que se le corto la subida a la mitad (`subida.go`).
        //
        // **UNO, no `lote.length`.** Con el lote unico se restaba el lote
        // entero porque el lote entero se iba en esa peticion. Ahora se va uno:
        // los que ya subieron han dejado de ser `pendiente` en la base, asi que
        // `cuantosPendientes()` ya los ha descontado y lo unico que falta por
        // descontar es ESTE. Restar el lote aqui dejaria al panel con
        // `pendientes` en cero desde la primera peticion de una cola de doce —y
        // ese cero es la pinta exacta de «Palma esta al dia» mientras no lo
        // esta.
        'pendientes': await _cola.cuantosQuedanTras(1),
        'apuntes': [apunte.aJson(ColaDeSalida.cuerpoDe(apunte))],
      });
    } on Rechazo catch (e) {
      // UN 404 NO BASTA: HACE FALTA QUE SEA **ESTE** 404.
      //
      // Tirar el identificador es destructivo —el aparato pierde su sitio en el
      // panel y nace uno nuevo—, asi que se hace **sólo** cuando el servidor lo
      // dice con su marca. Un 404 sin marca es de otro: de Traefik durante un
      // redespliegue, de un camino mal escrito, de un proxy por el medio. Esos
      // ni siquiera son JSON nuestro.
      //
      // Lo que pasaba hasta el 21/09/2026, medido en produccion: **12 aparatos
      // para un solo telefono**, once fantasmas, dos dados de alta de madrugada
      // sin nadie delante. Y cada fantasma se queda en el panel en rojo como
      // «lleva dias sin subir», que es justo lo unico que ese panel sirve para
      // ver. Con diez repartidores, inservible en una semana.
      //
      // Se falla CERRADO: sin marca, se relanza. Lo peor que puede pasar
      // entonces es que un aparato de verdad borrado del registro deje de subir
      // y lo diga —y eso una persona lo arregla—; lo otro llenaba la lista de
      // fantasmas en silencio.
      //
      // Es la misma trampa que el servidor ya tiene resuelta en el otro
      // sentido: `sync/internal/reparto/reparto.go` —«UN 404 QUE NO VIENE DEL
      // REPARTO ES NUESTRO, NO UN RECHAZO»—.
      if (!reintentar ||
          e.codigo != 404 ||
          e.marca != marcaDeAparatoNoRegistrado) {
        rethrow;
      }
      Registro.aviso(
        'el aparato ya no esta registrado: se da de alta otra vez',
      );
      await _aparato.olvidar();
      final nuevo = await _aparato.asegurar();
      return _mandarUno(nuevo, apunte, reintentar: false);
    }
  }
}
