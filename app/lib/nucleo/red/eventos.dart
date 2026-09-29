import 'eventos_stub.dart'
    if (dart.library.js_interop) 'eventos_web.dart'
    if (dart.library.io) 'eventos_io.dart'
    as destino;

import '../reloj.dart';

// EL ORDEN DE LAS CLAUSULAS IMPORTA: Dart se queda con la PRIMERA que se cumple.
// `dart.library.js_interop` va delante para que la web siga eligiendo la suya
// pase lo que pase; `dart.library.io` coge la APK, el escritorio y las pruebas
// —que corren en la maquina virtual—. El `eventos_stub.dart` de la izquierda es
// lo que queda para un destino que no sea ninguno de los dos, y hoy no hay
// ninguno.

/// LO QUE CAMBIO EN EL SERVIDOR, en cuanto cambia.
///
/// ## Por que existe
///
/// Hasta hoy, lo que hacia una persona no aparecia en la pantalla de otra hasta
/// que pasaba el temporizador: **dos minutos en la web, cinco en la APK**. Con
/// dos personas trabajando el mismo tablero —una armando zonas en el telefono y
/// otra mirandolas desde el navegador— eso no es trabajar juntos, es trabajar
/// por turnos sin saberlo.
///
/// Jose, 16/09/2026: «hice un tablero en el movil, movi cosas, y en la web no
/// salio en tiempo real, ¿por que razon si eso debe pasar?».
///
/// El canal ya existia en el servidor (`GET /api/eventos`, SSE) desde el
/// principio. Lo que no habia era **nadie escuchandolo**: ni la web ni la APK.
/// Medio protocolo, otra vez.
///
/// ## Que NO hace
///
/// **No trae datos.** El aviso dice «los pedidos cambiaron», no cuales. Quien lo
/// recibe vuelve a pedir su lista, y esa si va acotada a su sucursal — si el
/// aviso llevara las filas dentro, habria que acotarlas aqui y seria un segundo
/// sitio donde equivocarse con el alcance.
///
/// **No sustituye al temporizador.** Es una mejora, no un cimiento: si el canal
/// se cae —un proxy que corta, una red que se va— el reloj sigue ahi y el trabajo
/// llega igual, sólo que mas tarde. Por eso esto nunca lanza: un aviso que no
/// llega no puede dejar a nadie sin sincronizar.
/// EL AVISO QUE **NO** VIENE DEL SERVIDOR: «acabo de (re)conectar, ponte al dia».
///
/// ## El agujero que tapa, medido el 29/09/2026
///
/// Se creo una zona desde el telefono. Subio al servidor al instante —esta en la
/// base a las 17:34:55— y **la web siguio diciendo «las zonas las pones tu»
/// pasados tres minutos**, sin un aviso, sin un error: un tablero vacio se pinta
/// igual que uno correcto. Jose: «como que la web no se entera de lo que pasa en
/// otro aparato, si eso te dije que tiene que saberse en todos».
///
/// De los registros de la api salio el mecanismo, y son TRES cosas que solo
/// juntas hacen el fallo:
///
/// ```
/// 17:23:17  /api/eventos  200      65 s
/// 17:35:22  /api/eventos  200  299 999 ms   <- cortado a los 300 s exactos
/// 17:40:23  /api/eventos  200  299 998 ms   <- y otra vez
/// ```
///
///  1. la web tarda ~50 s desde que carga hasta que abre el canal — la zona se
///     creo a las 17:34:55 y el canal se abrio a las 17:35:22, o sea **27
///     segundos tarde**;
///  2. el canal **se corta cada 300 s**. No es la api ni el aparato: lo pone el
///     proxy, y volvera a ponerlo aunque se suba el numero;
///  3. y el Tablero **no se vuelve a pedir nunca por su cuenta**: solo al abrir
///     la pantalla, al pulsar el refresco, o cuando llega un aviso. No viaja en
///     el ciclo de sincronizacion.
///
/// O sea que **un aviso perdido deja la pantalla mal para siempre**. Y el propio
/// canal se describe como «una mejora, no un cimiento»; el Tablero lo estaba
/// usando como cimiento.
///
/// ## Por que esto es la pieza que faltaba
///
/// El transporte YA sabia cuando volvia: el `listo` del servidor se usaba para
/// soltar los frenos del 401 y para reiniciar la espera, y **se tiraba** con este
/// comentario, que estaba escrito aqui mismo: «el `listo` del principio y los
/// latidos no salen por aqui: son del transporte y no le dicen nada a una
/// pantalla».
///
/// Si le dicen: **«estuve desconectado, lo que pasara mientras no lo viste»**. Con
/// eso, cada pantalla vuelve a pedir lo suyo al reconectar — y como el proxy corta
/// cada cinco minutos, eso le pone ademas un suelo de cinco minutos a lo que antes
/// no tenia ninguno.
///
/// ## Por que va aqui y NO en `CambioEnVivo`
///
/// `CambioEnVivo` es **lo que publica el servidor**, y hay una prueba de Go que
/// compara esa lista con la de `eventos.go` en los dos sentidos
/// (`protocolo_avisos_test.go`). Esto no lo publica nadie: lo pone el transporte.
/// Meterlo alli romperia esa prueba con razon, y de paso convertiria «el servidor
/// dice que cambio X» y «me reconecte» en la misma clase de cosa, que no lo son.
///
/// El valor lleva guion a proposito: ningun tipo del servidor lo usa, asi que no
/// puede chocar con uno. Lo ata `app/test/nucleo/red/al_volver_no_choca_test.dart`.
const avisoDeQueVolvimos = 'al-volver';

/// LO MÍNIMO ENTRE DOS «volví» SEGUIDOS, y por qué hace falta un suelo.
///
/// El aviso cuesta: cada uno dispara un ciclo de sincronizacion entero, un
/// `GET /api/board` por tablero abierto y un `GET /vehicles` + `GET /settings`
/// por pantalla de flota abierta. Con el corte normal del proxy —cada 300 s—
/// eso esta bien pagado. El problema es otro caso:
///
/// **un servidor que acepta, manda el `listo` y se muere**, que es justo lo que
/// pasa en un reinicio o con un contenedor que no levanta. El `listo` reinicia
/// la espera creciente (`eventos_io.dart`, `intentos = 0`), asi que la
/// reconexion siguiente va al segundo — y sin suelo, cada una de esas vueltas
/// seria un ciclo completo. Eso son **cientos de peticiones por minuto** contra
/// un servidor que ya se esta cayendo, desde cada aparato a la vez, por la
/// conexion de alla y con la bateria del repartidor.
///
/// Treinta segundos: mucho mas que el segundo del bucle, y mucho menos que los
/// 300 s del corte normal, asi que **la reconexion de verdad siempre pasa**.
///
/// No se descarta en silencio: lo que se salta queda en el registro.
const sueloEntreVolver = Duration(seconds: 30);

/// EL PULSO DEL CANAL: «sigo vivo», y **nada mas**.
///
/// ## El agujero que tapa — 29/09/2026
///
/// El reloj del vigia dejo de ser el mecanismo y paso a ser la red de seguridad:
/// mientras se sepa del canal, el tic no dispara nada
/// (`VigiaDeSincronizacion.elCanalSeDaPorVivo`). Pero «saberse del canal» se
/// apuntaba **solo cuando llegaba un aviso a una pantalla** —un `cambio`, o el
/// `al-volver` de cada reconexion—, y eso NO es lo que dice si el canal vive.
///
/// El canal manda un latido cada **veinte segundos** (`api/internal/api/
/// eventos.go`, `latidoSSE`). Un canal perfectamente sano por el que no ha
/// cambiado nada en seis minutos —una oficina en calma, la hora del almuerzo— se
/// leia como canal muerto, y el reloj pedia la vuelta entera. O sea que el
/// polling seguia ahi, solo que mas espaciado: medido en la web ese dia, clavado
/// a su periodo, 20:07:42 → 20:09:40 → 20:11:41 → 20:13:40.
///
/// Lo unico que sostenia el invento era que **el proxy corta cada 300 s** y cada
/// reconexion manda `al-volver`: o sea que la prueba de vida era un corte de la
/// infraestructura. El dia que ese corte se alargue —o en local, donde no hay
/// proxy ninguno— el reloj vuelve a pedir contra un canal sano.
///
/// ## Por que NO viaja por el `Stream<String>` de los avisos
///
/// Porque **un latido no es un cambio**. Por ese stream van los dos que le dicen
/// algo a una pantalla —el tipo que cambio y el `al-volver`—, y cada uno cuesta un
/// ciclo de sincronizacion entero, un `GET /api/board` por tablero abierto y la
/// flota por cada pantalla de vehiculos abierta. Un latido metido ahi seria eso
/// **cada veinte segundos**: justo lo contrario de lo que se vino a arreglar.
///
/// Se podria filtrar en cada oyente, pero olvidarse de filtrar **no falla**: deja
/// una bajada cada veinte segundos que nadie relaciona con esto. Asi que el
/// latido no llega a ser un evento en ningun momento: el transporte marca aqui y
/// el vigia lee de aqui. No hay ninguna forma de que dispare nada.
///
/// ## Quien lo marca
///
/// **La APK y el escritorio** (`eventos_io.dart`) lo marcan con *cualquier* byte
/// que llegue por el socket, latido incluido: si llegan bytes, el canal esta.
///
/// **La web** (`eventos_web.dart`) no puede ver el latido: `EventSource` tira los
/// comentarios SSE (`: latido`) sin avisar a nadie, y no hay forma de pedirselos.
/// Alli el pulso lo marcan el `listo` de cada (re)conexion y los cambios. Esta
/// escrito con todo el detalle en ese fichero.
class PulsoDelCanal {
  PulsoDelCanal({Reloj reloj = relojDelAparato}) : _reloj = reloj;

  final Reloj _reloj;
  DateTime? _ultimo;

  /// Cuando se supo del canal por ultima vez. `null` es **nunca**, que no es
  /// «hace mucho»: es el aparato al que el canal no le ha abierto, y ahi es
  /// donde mas falta hace el reloj.
  DateTime? get ultimo => _ultimo;

  /// Llego algo por el canal. No dice QUE llego, y a proposito: aqui no hay
  /// ningun dato, solo la hora.
  void latio() => _ultimo = _reloj();
}

typedef EscuchaDeEventos =
    Stream<String> Function(
      String urlBase,
      Future<String?> Function() token, {
      Future<void> Function()? renovarSesion,
      PulsoDelCanal? pulso,
    });

/// Abre el canal y devuelve el TIPO de cada cambio: `pedidos`, `rutas`,
/// `tablero`, `catalogo`, `clientes`.
///
/// Los latidos no salen por aqui: no le dicen nada a una pantalla y, si salieran,
/// cada uno costaria una bajada cada veinte segundos. Lo que hacen es marcar
/// [pulso], que es lo que mira el vigia para callar el reloj. El `listo` SI sale,
/// como `avisoDeQueVolvimos`.
///
/// [pulso] es opcional: sin el, el canal funciona igual y el vigia se queda con
/// lo que ya sabia —los cambios y el `al-volver`—, que es exactamente lo de antes.
///
/// En los destinos donde todavia no hay implementacion devuelve un stream vacio,
/// y entonces manda el temporizador, que es exactamente lo de antes.
///
/// [token] se pide AL ABRIR, no antes, y otra vez en cada reconexion: el par de
/// tokens se renueva cada quince minutos y uno cogido al construir el proveedor
/// estaria caducado a la tercera vuelta.
///
/// [renovarSesion] es lo que se llama cuando el servidor contesta **401**, que
/// es lo que pasa cuando ese token de quince minutos caduca con el canal ya
/// abierto. No es un rechazo permanente y por eso no cierra el canal: se renueva
/// y se vuelve a abrir. Un 403 o un 404 si lo cierran para siempre. Por dentro es
/// el `Renovador`, con su candado de una sola renovacion en vuelo. Si no se
/// pasa, un 401 cierra el canal como cualquier otro 4xx.
///
/// Esto importa mas de lo que parece: el consuelo de «queda el temporizador» es
/// FALSO para Vehiculos y para Almacenes, que piden a la red y no viven de la
/// base local, asi que el ciclo no las repinta. Con el canal caido se quedan
/// clavadas hasta salir y volver a entrar.
///
/// **Como viaja ese token es lo unico distinto entre los dos destinos.** En la
/// web va por la cookie porque `EventSource` no sabe mandar cabeceras; en la APK
/// y el escritorio va en `Authorization: Bearer …`, que es lo normal y lo que ya
/// hace el resto de la aplicacion.
Stream<String> escucharEventos(
  String urlBase,
  Future<String?> Function() token, {
  Future<void> Function()? renovarSesion,
  PulsoDelCanal? pulso,
}) => destino.escucharEventos(
  urlBase,
  token,
  renovarSesion: renovarSesion,
  pulso: pulso,
);

/// `true` donde el canal esta implementado. Sirve para poder DECIRLO —y para que
/// una prueba no compruebe algo que en ese destino no existe—.
bool get hayCanalDeEventos => destino.hayCanalDeEventos;
