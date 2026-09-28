import 'package:dio/dio.dart';

import '../identidad/almacen_sesion.dart';
import '../identidad/renovador.dart';
import '../registro/registro.dart';
import 'de_quien_viene.dart';
import 'fallos.dart';
import 'interceptor_fallos.dart';
import 'interceptor_sesion.dart';

/// Cuanto se espera entre reintentos, y sólo para `FalloDeRed`.
///
/// Creciente a proposito: en la conexion de alla un reintento inmediato sólo
/// anade ruido a un enlace que ya va justo. Un `Rechazo` **no se reintenta
/// jamas**: el servidor ya dijo que no y repetirlo no lo va a cambiar.
///
/// ## CUANTO PUEDE TARDAR UNA PETICION EN RENDIRSE — 15/09/2026
///
/// Hasta hoy esto era `[1, 4, 15, 60]` con 30 s de recepcion, o sea cinco
/// intentos de hasta 40 s mas 80 s de esperas: **casi cuatro minutos** mirando
/// una rueda antes de que la aplicacion dijera una palabra. Con la conexion de
/// alla ese no es el caso raro, es el de todos los dias, y cuatro minutos
/// delante de una rueda es la aplicacion rota aunque acabe contestando.
///
/// Con `[1, 4, 10]` y los plazos de abajo son **cuatro intentos y 15 s de
/// esperas**, y la cuenta sale asi:
///
/// | Como se cae | Cuanto tarda cada intento | Peor caso |
/// |---|---|---|
/// | no hay ruta / el puerto no abre (lo normal sin senal) | el sistema falla al momento | **segundos** |
/// | la conexion no llega a establecerse (lo normal con senal mala) | 10 s de `connect` | 4×10 + 15 = **55 s** |
/// | el servidor acepta y despues se queda mudo | 10 + 15 s | 4×25 + 15 = **115 s** |
///
/// El de en medio es el que se vive en Cuba y es el que Jose queria en un
/// minuto. El ultimo —que el servidor coja la conexion y no conteste nada, las
/// cuatro veces— sigue siendo el doble de eso, y esta escrito aqui en vez de
/// redondeado a «un minuto» porque el numero que importa es el que ve quien
/// espera.
///
/// Bajar mas la recepcion no se puede: la primera bajada de una sucursal
/// grande por la conexion de alla tarda mas de 15 s de cuerpo, y para eso
/// existe `truncado` en el protocolo. Lo que se acorta es cuanto se insiste,
/// no cuanto se deja hablar al servidor.
const esperasPorDefecto = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 4),
  Duration(seconds: 10),
];

/// Un `Dio` por destino (`api`, `sync`, `auth`) con los interceptores de la
/// casa.
///
/// Envuelve a Dio en vez de exponerlo para que ninguna pantalla pueda hacer un
/// `dio.get` sin pasar por la sesion y por la tabla de la regla 5.
class ClienteApi {
  ClienteApi({
    required Dio dio,
    List<Duration> esperas = esperasPorDefecto,
    Future<void> Function(Duration)? esperar,
    void Function({required bool llego})? alIntentar,
  }) : _dio = dio,
       _esperas = esperas,
       _esperar = esperar ?? Future<void>.delayed,
       _alIntentar = alIntentar;

  /// El montaje de verdad: crea el Dio, le pone los interceptores EN ORDEN y
  /// devuelve el cliente.
  factory ClienteApi.montar({
    required String baseUrl,
    required AlmacenDeSesion almacen,
    required Renovador renovador,
    String? Function()? sucursalMirada,
    void Function()? alMorirLaSesion,
    List<Duration> esperas = esperasPorDefecto,
    Future<void> Function(Duration)? esperar,
    void Function({required bool llego})? alIntentar,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        // 10 s para conectar y 15 s para recibir. Los 30 s de recepcion de
        // antes, multiplicados por los cinco intentos que habia, eran los
        // cuatro minutos de rueda que se cuentan arriba en `esperasPorDefecto`.
        //
        // Los 10 s de `connect` se quedan: establecer la conexion con una
        // senal mala tarda, y ahi el TLS todavia no ha empezado. Lo que se
        // acorto es la ESPERA A QUE CONTESTE, que es donde se iba el tiempo.
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        contentType: Headers.jsonContentType,
      ),
    );
    dio.interceptors.addAll([
      InterceptorSesion(
        almacen: almacen,
        renovador: renovador,
        dio: dio,
        sucursalMirada: sucursalMirada,
        alMorirLaSesion: alMorirLaSesion,
      ),
      const InterceptorFallos(),
    ]);
    return ClienteApi(
      dio: dio,
      esperas: esperas,
      esperar: esperar,
      alIntentar: alIntentar,
    );
  }

  final Dio _dio;
  final List<Duration> _esperas;
  final Future<void> Function(Duration) _esperar;

  /// SE AVISA DE CADA INTENTO, no de cada ciclo. `llego` dice si la peticion
  /// llego al servidor (aunque contestara un 4xx: eso significa que llego).
  ///
  /// Existe porque la salud de la red se contaba POR CICLO, y un ciclo tarda:
  /// hacian falta tres seguidos para decir «sin conexion», o sea minutos. El
  /// 16/09/2026, con el telefono sin salida a internet —comprobado, 100 % de
  /// paquetes perdidos y ni siquiera resolvia el nombre del servidor—, la
  /// aplicacion seguia sin decirlo. Palabras de Jose: «ahora mismo estoy sin
  /// conexion y el movil me dice q tengo internet por q razon».
  ///
  /// Contando intentos, los tres fallos que hacen falta caben dentro de UN
  /// ciclo —cada peticion reintenta a 1 s, 4 s y 10 s—, asi que el aviso sale
  /// en menos de medio minuto en vez de en varios.
  final void Function({required bool llego})? _alIntentar;

  Dio get dio => _dio;

  Future<T> pedir<T>(String ruta, {Map<String, Object?>? params}) =>
      _conReintento(
        () => _dio.get<T>(ruta, queryParameters: params),
        '$ruta GET',
      );

  Future<T> mandar<T>(String metodo, String ruta, Object? cuerpo) =>
      _conReintento(
        () => _dio.request<T>(
          ruta,
          data: cuerpo,
          options: Options(method: metodo),
        ),
        '$ruta $metodo',
      );

  /// Reintenta **sólo** lo que es red o 5xx.
  ///
  /// Un `Rechazo` sale a la primera y un `SesionMuerta` tambien: reintentar
  /// cualquiera de los dos es perder tiempo y, en el caso del 401, arriesgarse a
  /// una tanda de renovaciones.
  Future<T> _conReintento<T>(
    Future<Response<T>> Function() intento,
    String que,
  ) async {
    var vuelta = 0;
    while (true) {
      // No es `final` porque se le asigna desde las dos ramas del `try`, y ahi
      // el analizador no sabe que la del `catch` solo corre si la otra no
      // llego a terminar.
      FalloApi fallo;
      try {
        final respuesta = await intento();

        // UN 200 NO ES PRUEBA DE NADA SI NO LO FIRMA NUESTRO SERVIDOR
        // — 28/09/2026.
        //
        // Algo por el camino —un router, un proxy, un filtro de la red—
        // contesta 200 con su pagina dentro. Por aqui se contaba `llego: true`
        // —hay respuesta, luego la red va—, la salud se ponia en verde y la
        // franja decia «Todo al dia». Y encima el `as T` de abajo
        // reventaba con un `TypeError` (Dio deja el HTML como `String` porque
        // no es JSON), o sea que el aviso de red se daba por bueno JUSTO antes
        // de estrellarse. Ver `de_quien_viene.dart`.
        //
        // El aviso va con lo que de verdad se sabe, y despues se decide.
        final deLaCasa = contestoLoNuestro(respuesta);
        _alIntentar?.call(llego: deLaCasa);
        if (deLaCasa) {
          // Llego. Una sola buena basta para dar la red por sana otra vez:
          // dejar el aviso puesto delante de alguien que ya tiene senal es
          // mentir en la otra direccion.
          return respuesta.data as T;
        }

        // Y se trata como lo que es: red que no llega. Se reintenta con las
        // mismas esperas —lo que se cruzo en medio puede quitarse de en medio
        // y entonces la siguiente vuelta pasa— y los tokens se quedan.
        fallo = ContestoOtroServidor(
          codigo: respuesta.statusCode,
          tipo: tipoDeContenido(respuesta),
          detalle: 'respuesta que no es de nuestra API en $que',
        );
      } on DioException catch (e) {
        final traducido = e.error is FalloApi
            ? e.error! as FalloApi
            : InterceptorFallos.traducir(e);

        // Un `Rechazo` o una `SesionMuerta` significan que la peticion SI
        // llego: el servidor contesto. Eso no dice nada malo de la red.
        //
        // La regla es la misma de arriba y no hay que repetirla aqui:
        // `InterceptorFallos.traducir` ya devuelve `ContestoOtroServidor` —que
        // ES un `FalloDeRed`— cuando la respuesta con codigo no la firmo
        // nuestra API, asi que un 403 de un proxy cuenta como caida.
        _alIntentar?.call(llego: traducido is! FalloDeRed);
        fallo = traducido;
      }

      if (fallo is! FalloDeRed || vuelta >= _esperas.length) throw fallo;

      Registro.aviso(
        'reintento ${vuelta + 1} de $que en ${_esperas[vuelta].inSeconds}s',
      );
      await _esperar(_esperas[vuelta]);
      vuelta++;
    }
  }
}
