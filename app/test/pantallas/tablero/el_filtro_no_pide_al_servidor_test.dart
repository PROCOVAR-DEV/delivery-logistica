import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';
import 'package:reparto/nucleo/red/eventos.dart' show avisoDeQueVolvimos;

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

/// UN FILTRO ES LOCAL: no se le pregunta al servidor.
///
/// El tablero pide la foto del servidor al abrirse —con conexión manda el servidor y no la
/// copia—, y eso está bien. Lo que NO puede pasar es que la pida otra vez por cambiar un
/// filtro: `build` mira también `filtrosTableroProvider`, así que sin una guarda cada
/// filtro era una descarga completa, con la pantalla en blanco y la rueda girando.
///
/// Abrir el cajón de filtros y tocar cuatro cosas eran cuatro idas y vueltas por la
/// conexión de allá — que el propio cliente documenta en 55 s en el caso normal y 115 s en
/// el peor— para filtrar unos datos que ya están en el aparato.
void main() {
  late BaseLocal base;
  late ServidorFalso servidor;
  late ProviderContainer contenedor;
  late List<PeticionVista> vistas;
  late StreamController<String> enVivo;

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
    base = baseDePrueba();
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarPedido(base, id: 'p1');
    servidor = ServidorFalso(
      (p) async => RespuestaFalsa(200, const {
        'columnas': <Object?>[],
        'colocados': <Object?>[],
      }),
    );
    vistas = servidor.vistas;
    contenedor = montar();
  });

  tearDown(() async {
    contenedor.dispose();
    await enVivo.close();
    await base.close();
  });

  int peticionesDelTablero() =>
      vistas.where((p) => p.ruta.contains('/board')).length;

  test('abrir pide la foto UNA vez; cambiar filtros, ninguna más', () async {
    await contenedor.read(tableroProvider.future);
    expect(peticionesDelTablero(), 1, reason: 'al abrir sí: manda el servidor');

    final filtros = contenedor.read(filtrosTableroProvider.notifier);
    filtros.poner(const FiltrosSinColocar(municipio: 'Santiago de Cuba'));
    await contenedor.read(tableroProvider.future);
    filtros.poner(const FiltrosSinColocar(conCobroDeDomicilio: true));
    await contenedor.read(tableroProvider.future);
    filtros.poner(const FiltrosSinColocar());
    await contenedor.read(tableroProvider.future);

    expect(
      peticionesDelTablero(),
      1,
      reason:
          'tres filtros son tres idas y vueltas de balde: los datos ya están '
          'en el aparato y la pantalla se queda en blanco mientras tanto',
    );
  });

  // EL TABLERO SE PONE AL DÍA CUANDO VUELVE EL CANAL — 29/09/2026.
  //
  // Es el fallo que se vio probando la web y el teléfono a la vez. Se creó una
  // zona desde el teléfono, entró en el servidor a las 17:34:55, y la web siguió
  // diciendo «las zonas las pones tú» **tres minutos después**. Jose: «cómo que
  // la web no se entera de lo que pasa en otro aparato».
  //
  // Esta pantalla es la que más caro lo paga, y por una razón que está escrita
  // en su propio código: **no viaja en el ciclo de sincronización**. La bajada
  // por diferencias trae pedidos, clientes, rutas y catálogo; las zonas se piden
  // aparte con `GET /api/board`, y sólo al abrir la pantalla, al pulsar el
  // refresco, o cuando llega un aviso. No hay temporizador detrás.
  //
  // Así que un aviso perdido no la deja vieja «hasta la vuelta siguiente»: la
  // deja vieja **para siempre**. Y perderlo es lo normal, no lo raro — de los
  // registros de la api de ese día:
  //
  //     17:35:22  /api/eventos  200  299 999 ms   ← cortado a los 300 s exactos
  //     17:40:23  /api/eventos  200  299 998 ms   ← y otra vez
  //
  // El proxy corta cada cinco minutos y la web tarda ~50 s en abrir el canal
  // desde que carga. Todo lo que pase en esas ventanas se pierde.
  test('al volver el canal vuelve a pedir la foto, aunque no llegue su aviso',
      () async {
    await contenedor.read(tableroProvider.future);
    expect(peticionesDelTablero(), 1, reason: 'al abrir sí: manda el servidor');

    // MIENTRAS EL CANAL ESTABA CAÍDO alguien creó una zona desde el teléfono. Su
    // aviso de «tablero» salió y no lo recibió nadie: no se simula, porque el
    // caso real es exactamente ése — no llega.
    //
    // Y el canal vuelve.
    enVivo.add(avisoDeQueVolvimos);
    // 400 ms Y NO 50: desde el 01/10/2026 los avisos pasan por la ventana de
    // junta de 150 ms antes de costar una bajada (`TableroDelDia.ventanaDeJunta`
    // — cuatro avisos pegados costaban cuatro fotos de 89.495 bytes). La bajada
    // SIGUE SALIENDO, que es lo que esta prueba vigila; lo único que cambia es
    // que sale un pelo más tarde. Esperar aquí menos que la ventana sería medir
    // el reloj, no la guarda.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(
      peticionesDelTablero(),
      greaterThan(1),
      reason:
          'volvió el canal y el tablero no volvió a pedir la foto. Lo que se '
          'creara mientras estuvo caído no lo ve nadie, y aquí no hay ningún '
          'temporizador que lo arregle después: la pantalla se queda mal hasta '
          'que una persona pulse el refresco, con la misma cara que si '
          'estuviera bien',
    );
  });

  test('cambiar de SUCURSAL sí pide: es otro tablero', () async {
    await contenedor.read(tableroProvider.future);
    expect(peticionesDelTablero(), 1);

    // Otra sucursal cualquiera: lo que importa es que NO sea la de antes.
    contenedor.read(sucursalMiradaProvider.notifier).mirar('suc-hol');
    await contenedor.read(tableroProvider.future);

    expect(
      peticionesDelTablero(),
      2,
      reason: 'la foto de otra sucursal no está en esta copia',
    );
  });

  test(
    'un 403 NO deja la pantalla girando: se pinta lo que hay y se dice',
    () async {
      // `on FalloDeRed` sólo tapa red y 5xx. Un 403 —«esa sucursal no es tuya»— salía de
      // `build` y el future del provider no se completaba NUNCA: la rueda para siempre, sin
      // el mensaje del servidor y sin pintar la copia local, que lo tenía todo.
      servidor = ServidorFalso(
        (p) async =>
            RespuestaFalsa(403, const {'error': 'Esa sucursal no es tuya.'}),
      );
      vistas = servidor.vistas;
      contenedor.dispose();
      contenedor = montar();

      final tablero = await contenedor
          .read(tableroProvider.future)
          .timeout(const Duration(seconds: 5));

      expect(tablero.sucursalId, sucursalStg, reason: 'se pinta lo de aquí');
      expect(
        contenedor.read(tableroProvider.notifier).porQueNoSeRefresca,
        contains('sucursal'),
        reason: 'y se dice el literal del servidor, que es lo único que dice qué hacer',
      );
    },
  );

  test('un cuerpo que no se entiende tampoco cuelga la pantalla', () async {
    servidor = ServidorFalso(
      (p) async =>
          RespuestaFalsa(200, const {'columnas': 'esto no es una lista'}),
    );
    vistas = servidor.vistas;
    contenedor.dispose();
    contenedor = montar();

    final tablero = await contenedor
        .read(tableroProvider.future)
        .timeout(const Duration(seconds: 5));

    expect(tablero.sucursalId, sucursalStg);
    expect(
      contenedor.read(tableroProvider.notifier).porQueNoSeRefresca,
      isNotNull,
      reason: 'se dice algo, aunque sea «no se pudo traer»',
    );
  });

  test('sin señal se sigue con lo de aquí, y sin cartel', () async {
    servidor = ServidorFalso((p) async => null);
    vistas = servidor.vistas;
    contenedor.dispose();
    contenedor = montar();

    final tablero = await contenedor
        .read(tableroProvider.future)
        .timeout(const Duration(seconds: 5));

    expect(tablero.sucursalId, sucursalStg);
    expect(
      contenedor.read(tableroProvider.notifier).porQueNoSeRefresca,
      isNull,
      reason: 'no hay nada que decir: la barra de arriba ya avisa de que no hay red',
    );
  });

  test('al ABRIR con trabajo sin subir, la bajada se niega y SE DICE', () async {
    // La guarda ya existía y funcionaba, pero `build` tiraba el resultado de `descargar`:
    // la barra de arriba caía al «Visto por última vez a las …» con una hora congelada,
    // como si estuviera al día. El aviso sólo aparecía si pulsabas «actualizar» a mano —y
    // se borraba al tocar un filtro.
    //
    // Jose pidió exactamente esto el 16/09: «debería de informarme o algo para decirme lo
    // que voy a perder si le doy al botón».
    // Las tablas del tablero no son de Drift: las crea la propia pantalla.
    await EsquemaTablero.asegurar(base);
    await base.customStatement(
      'INSERT INTO board_columns (id, branch_id, nombre, posicion, created_at, '
      'updated_at, nacio_aqui) '
      "VALUES ('local-vista', ?1, 'Vista', 1, '2026-09-17T09:00:00.000', "
      "'2026-09-17T09:00:00.000', 1)",
      [sucursalStg],
    );

    await contenedor.read(tableroProvider.future);

    final mando = contenedor.read(tableroProvider.notifier);
    expect(
      mando.porQueNoSeRefresca,
      contains('zona del tablero'),
      reason: 'sin esto, la barra dice «visto a las …» con una hora congelada',
    );
    expect(peticionesDelTablero(), 0, reason: 'se corta antes de preguntar');

    // Y un filtro NO se lo lleva por delante.
    contenedor
        .read(filtrosTableroProvider.notifier)
        .poner(const FiltrosSinColocar(conCobroDeDomicilio: true));
    await contenedor.read(tableroProvider.future);

    expect(
      mando.porQueNoSeRefresca,
      isNotNull,
      reason:
          'el aviso que costó el incidente del 16/09 no puede irse solo al '
          'tocar un desplegable',
    );
  });

  /// UN AVISO DEL SERVIDOR VUELVE A PEDIR LA FOTO. Es para lo que está el canal.
  ///
  /// Sin esto el canal funcionaba y no servía de nada: el aviso disparaba el ciclo de
  /// sincronización, y **el tablero no viaja en el ciclo** —la bajada por diferencias
  /// sirve pedidos, clientes, rutas y catálogo; las zonas se piden aparte—. Se vio con el
  /// teléfono delante: la zona subía con un 201, el servidor registraba la conexión
  /// abierta, y la web seguía igual hasta que pasaban los dos minutos del temporizador.
  group('el aviso en vivo', () {
    test('un «tablero» vuelve a pedir la foto', () async {
      await contenedor.read(tableroProvider.future);
      expect(peticionesDelTablero(), 1);

      enVivo.add('tablero');
      // 400 ms: la ventana de junta de 150 ms va delante. Ver arriba.
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        peticionesDelTablero(),
        2,
        reason:
            'lo que hizo el otro en su teléfono tiene que aparecer aquí solo',
      );
    });

    test('un aviso de OTRA cosa no cuesta una foto del tablero', () async {
      await contenedor.read(tableroProvider.future);
      expect(peticionesDelTablero(), 1);

      enVivo.add('clientes');
      enVivo.add('catalogo');
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        peticionesDelTablero(),
        1,
        reason:
            'un cambio de clientes no tiene por qué costar una ida y vuelta '
            'por la conexión de allá',
      );
    });
  });

  /// LA COPIA ARRANCA VACÍA Y LA PANTALLA TIENE QUE RECUPERARSE SOLA.
  ///
  /// El tablero se ordena desde el punto del que sale la mercancía. Si ese almacén todavía
  /// no está en la copia, se pinta «La Habana no tiene ningún almacén con coordenadas» —que
  /// además es falso: lo tiene, lo que pasa es que no había bajado todavía—.
  ///
  /// Mientras la copia era un fichero que sobrevivía, eso casi nunca se veía. **En la web ya
  /// no**: desde que su base es en memoria, cada carga empieza vacía. Y sin escuchar esa
  /// tabla la pantalla se quedaba con ese mensaje PARA SIEMPRE: `build` no se vuelve a
  /// ejecutar solo, y los almacenes llegan por el ciclo, que toca otra tabla.
  test('cuando baja el almacén, el tablero se repinta solo', () async {
    final vacia = baseDePrueba();
    addTearDown(vacia.close);
    await sembrarSucursal(vacia);
    // SIN almacén: es como arranca la web.

    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.invalido'))
      ..httpClientAdapter = servidor;
    final c = ProviderContainer.test(
      overrides: [
        baseProvider.overrideWith((ref) => vacia),
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
    addTearDown(c.dispose);

    final primero = await c.read(tableroProvider.future);
    expect(
      primero.problema,
      isNotNull,
      reason: 'sin almacén no se puede ordenar nada, y se dice',
    );

    // Llega el almacén por el ciclo, que toca OTRA tabla.
    await sembrarAlmacen(vacia);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final despues = await c.read(tableroProvider.future);
    expect(
      despues.problema,
      isNull,
      reason: 'sin esto la pantalla se queda con el mensaje para siempre',
    );
  });
}
