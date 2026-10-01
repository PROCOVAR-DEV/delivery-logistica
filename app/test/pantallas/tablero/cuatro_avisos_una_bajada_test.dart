import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/eventos.dart' show avisoDeQueVolvimos;
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

/// CUATRO AVISOS PEGADOS NO SON CUATRO TABLEROS — 01/10/2026.
///
/// Medido en producción con el navegador delante. Por **un solo gesto de una
/// persona** entraron cuatro avisos de tipo `tablero` en 32 milisegundos:
///
///     12:59:39.581  {"cuando":"…465Z","tipo":"tablero"}
///     12:59:39.606  {"cuando":"…477Z","tipo":"tablero"}
///     12:59:39.607  {"cuando":"…489Z","tipo":"tablero"}
///     12:59:39.612  {"cuando":"…497Z","tipo":"tablero"}
///
/// Y el cliente contestó con **cuatro `GET /api/board` enteros** en 387 ms:
/// 39.896 · 40.013 · 40.116 · 40.283. En otra prueba del mismo día, **dos
/// bajadas de 89.495 bytes en 175 ms**. Cientos de kilobytes de más contra la
/// conexión de allá, en cada aparato que tenga el tablero abierto.
///
/// El ciclo de sincronización ya sabía decir «ya hay uno en vuelo, no se lanza
/// otro»; el Tablero no. Esto ata las tres mitades del arreglo, y las tres por
/// separado:
///
///  1. **la ventana de junta** — la racha entera sale en UNA bajada;
///  2. **juntar no es descartar** — un cambio que llega con la bajada a medio
///     camino trae otra detrás, porque esa foto no lo lleva dentro;
///  3. **el candado** — mientras una está en vuelo no se lanzan más, aunque
///     lleguen avisos en ventanas distintas.
///
/// Y la cuarta, que es una red de seguridad que no se puede romper: el
/// `al-volver` sigue disparando su bajada.
void main() {
  late BaseLocal base;
  late ServidorFalso servidor;
  late ProviderContainer contenedor;
  late List<PeticionVista> vistas;
  late StreamController<String> enVivo;

  /// Lo que tarda el servidor falso en contestar la foto. Se mueve en las
  /// pruebas que necesitan una bajada **a medio camino**.
  late Duration loQueTardaElServidor;

  ProviderContainer montar() {
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.invalido'))
      ..httpClientAdapter = servidor;
    return ProviderContainer.test(
      overrides: [
        baseProvider.overrideWith((ref) => base),
        avisosDelServidorProvider.overrideWithValue(enVivo.stream),
        clienteApiProvider.overrideWithValue(
          ClienteApi(dio: dio, esperas: const <Duration>[]),
        ),
        almacenSesionProvider.overrideWithValue(
          AlmacenEnMemoria(
            const Sesion(
              token: 't',
              refresh: 'r',
              sub: 'logistico',
              sucursalId: sucursalStg,
            ),
          ),
        ),
      ],
    );
  }

  setUp(() async {
    enVivo = StreamController<String>.broadcast();
    loQueTardaElServidor = Duration.zero;
    base = baseDePrueba();
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarPedido(base, id: 'p1');
    servidor = ServidorFalso((p) async {
      if (loQueTardaElServidor > Duration.zero) {
        await Future<void>.delayed(loQueTardaElServidor);
      }
      return RespuestaFalsa(200, const {
        'columnas': <Object?>[],
        'colocados': <Object?>[],
      });
    });
    vistas = servidor.vistas;
    contenedor = montar();
  });

  tearDown(() async {
    contenedor.dispose();
    await enVivo.close();
    await base.close();
  });

  int bajadasDelTablero() =>
      vistas.where((p) => p.ruta.contains('/board')).length;

  /// La racha tal como llegó: cuatro avisos repartidos en ~32 ms.
  ///
  /// **Se reparten y no se meten de golpe a propósito.** Metidos en el mismo
  /// turno del bucle de sucesos, los cuatro quedarían contados antes de que
  /// ningún temporizador llegue a correr, y entonces la prueba saldría verde con
  /// la ventana de junta quitada: mediría el candado dos veces y la ventana
  /// ninguna.
  Future<void> laRachaDeLosCuatro() async {
    for (var i = 0; i < 4; i++) {
      enVivo.add('tablero');
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
  }

  test('cuatro avisos pegados = UNA sola bajada', () async {
    await contenedor.read(tableroProvider.future);
    expect(bajadasDelTablero(), 1, reason: 'al abrir sí: manda el servidor');

    await laRachaDeLosCuatro();
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(
      bajadasDelTablero(),
      2,
      reason:
          'un gesto de una persona costó ${bajadasDelTablero() - 1} fotos del '
          'tablero de 89.495 bytes cada una. Tienen que salir en UNA: los '
          'cuatro avisos caben en 32 ms y la ventana de junta es de 150 ms '
          '(TableroDelDia.ventanaDeJunta)',
    );
  });

  test('la racha trae el estado final: se junta, no se descarta', () async {
    // La foto tarda 300 ms, así que el aviso de en medio llega con la bajada a
    // MEDIO CAMINO: esa foto ya salió y no lo lleva dentro.
    loQueTardaElServidor = const Duration(milliseconds: 300);
    await contenedor.read(tableroProvider.future);
    expect(bajadasDelTablero(), 1);

    // El primero abre la ventana; la bajada sale a los 150 ms y acaba a los 450.
    enVivo.add('tablero');
    // Y a los 250 ms, con la bajada en vuelo, entra otro cambio.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    enVivo.add('tablero');

    await Future<void>.delayed(const Duration(milliseconds: 800));

    expect(
      bajadasDelTablero(),
      3,
      reason:
          'el aviso llegó cuando la bajada ya iba por el aire, así que esa foto '
          'NO lo trae dentro. Juntar no es descartar: hace falta UNA detrás, o '
          'ese cambio no lo ve nadie hasta que una persona pulse el refresco — '
          'esta pantalla no se vuelve a pedir sola nunca',
    );
  });

  test('con una en vuelo no se lanzan más, aunque sean ventanas distintas',
      () async {
    // Medio segundo de foto: dentro de ella caben dos ventanas de junta enteras.
    loQueTardaElServidor = const Duration(milliseconds: 500);
    await contenedor.read(tableroProvider.future);
    expect(bajadasDelTablero(), 1);

    // Tres avisos en tres ventanas distintas —200 ms de separación, y la ventana
    // es de 150— mientras la primera foto sigue por el aire.
    enVivo.add('tablero');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    enVivo.add('tablero');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    enVivo.add('tablero');

    await Future<void>.delayed(const Duration(milliseconds: 1200));

    expect(
      bajadasDelTablero(),
      3,
      reason:
          'tres avisos en tres ventanas distintas tienen que acabar en dos '
          'bajadas: la que ya iba y UNA detrás que las trae todas. '
          '${bajadasDelTablero() - 1} son fotos pisándose unas a otras por la '
          'conexión de allá',
    );
  });

  /// LA RED DE SEGURIDAD DEL HUECO DE RECONEXIÓN. **No se puede romper.**
  ///
  /// El proxy corta el canal cada 300 s y la web tarda ~50 s en abrirlo desde
  /// que carga. Lo que pase en esas ventanas no llega como aviso: lo único que
  /// lo recupera es este `al-volver`. Y esta pantalla no viaja en el ciclo, así
  /// que sin él se queda mal **para siempre**, no «hasta la vuelta siguiente».
  test('el aviso de al-volver sigue disparando su bajada', () async {
    await contenedor.read(tableroProvider.future);
    expect(bajadasDelTablero(), 1);

    enVivo.add(avisoDeQueVolvimos);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(
      bajadasDelTablero(),
      2,
      reason:
          'volvió el canal y el tablero no volvió a pedir la foto. Lo que se '
          'creara mientras estuvo caído no lo ve nadie, y aquí no hay ningún '
          'temporizador que lo arregle después',
    );
  });

  /// La ventana no puede aplazarse sola: el primero de la racha la abre y los
  /// demás entran en ella. Si se re-armara con cada aviso, un goteo la
  /// empujaría para siempre y el tablero no bajaría nunca.
  test('un goteo de avisos no aplaza la bajada para siempre', () async {
    await contenedor.read(tableroProvider.future);
    expect(bajadasDelTablero(), 1);

    // Diez avisos cada 50 ms: nueve de ellos caen dentro de ventanas ya
    // abiertas, y la ventana es de 150.
    for (var i = 0; i < 10; i++) {
      enVivo.add('tablero');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(
      bajadasDelTablero(),
      greaterThan(1),
      reason:
          'medio segundo de avisos y el tablero no ha bajado ni una vez: la '
          'ventana de junta se está re-armando con cada aviso en vez de '
          'cerrarse a los 150 ms del primero',
    );
  });
}
