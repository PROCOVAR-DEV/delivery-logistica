// LA ACTUALIZACIÓN SE BAJA DENTRO: cortada, reanudada y comprobada.
//
// **Aquí no sale ni una petición de red.** El servidor es un doble que vive en
// este fichero y sirve bytes de una lista, igual que en `test/mapa/descarga_test
// .dart`: es lo que permite ejercitar el reanudado, la huella que no cuadra y el
// permiso que falta sin depender de ninguna conexión — ni de la de Cuba, ni de la
// de nadie.
//
// Las dos que pidió Jose están aquí con su nombre:
//
//  * «una descarga que se corta a la mitad y, al reintentar, sigue desde donde
//    iba» — y **contando los bytes pedidos**, no confiando en que funciona: la
//    segunda vuelta tiene que pedir `bytes=N-` y servir exactamente lo que
//    faltaba.
//  * «una descarga que llega con la huella equivocada NO se instala y lo dice» —
//    y lo que lo ata no es sólo el estado: es que **el instalador no se llama ni
//    una vez**.

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/actualizacion/bajada_de_la_actualizacion.dart';
import 'package:reparto/nucleo/actualizacion/instalador.dart';
import 'package:reparto/nucleo/actualizacion/version_publicada.dart';
import 'package:reparto/nucleo/descarga/almacen_de_bajadas.dart';

/// El APK de mentira: 40.000 bytes con un patrón, para que un trozo puesto en el
/// sitio equivocado se note en el `sha256`.
final elApk = Uint8List.fromList(
  List.generate(40000, (i) => (i * 37 + 11) % 251),
);
final suHuella = sha256.convert(elApk).toString();

const laUrl = 'https://archivos.procovar.cloud/reparto/apk/reparto-1.5.0.apk';

FicheroPublicado elFichero({int? bytes, String? huella}) =>
    FicheroPublicado(bytes: bytes ?? elApk.length, sha256: huella ?? suHuella);

/// UN SERVIDOR DE MENTIRA que se porta como el de verdad, medido el 05/10/2026
/// contra producción: **la respuesta completa NO lleva `content-length`** —lo
/// quita Cloudflare— y en cambio **sí contesta `206` a un rango**.
class ServidorDeMentira implements HttpClientAdapter {
  ServidorDeMentira({this.cortaEn, this.codigo = 200, this.entiendeRange = true});

  /// Cuántos bytes sirve antes de cortar, contados desde el principio del
  /// fichero. `null` los sirve todos.
  final int? cortaEn;
  final int codigo;
  final bool entiendeRange;

  /// Lo que se pidió, cabecera `Range` incluida (`null` = sin rango).
  final peticiones = <String?>[];

  /// Cuántos bytes salió de aquí en cada petición. Es lo que convierte «parece
  /// que reanudó» en «reanudó»: si volviera a bajarlo todo, aquí se vería.
  final servidos = <int>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions opciones,
    Stream<Uint8List>? cuerpo,
    Future<void>? cancelar,
  ) async {
    final rango = opciones.headers['Range'] as String?;
    peticiones.add(rango);

    if (codigo != 200) {
      servidos.add(0);
      return ResponseBody.fromString('no', codigo);
    }

    var desde = 0;
    if (rango != null && entiendeRange) {
      desde = int.parse(rango.replaceAll(RegExp(r'[^0-9]'), ''));
    }
    final hasta = cortaEn ?? elApk.length;
    final trozo = Uint8List.sublistView(
      elApk,
      desde,
      hasta > desde ? hasta : desde,
    );
    servidos.add(trozo.length);

    final cabeceras = <String, List<String>>{};
    if (rango != null && entiendeRange) {
      cabeceras['content-range'] = [
        'bytes $desde-${elApk.length - 1}/${elApk.length}',
      ];
    }
    // SIN `content-length`, a propósito: es justo lo que no llega, y es la razón
    // de que el tamaño salga del anuncio de la api.
    return ResponseBody(
      Stream<Uint8List>.fromIterable([
        for (var i = 0; i < trozo.length; i += 4096)
          Uint8List.sublistView(
            trozo,
            i,
            i + 4096 > trozo.length ? trozo.length : i + 4096,
          ),
      ]),
      rango != null && entiendeRange ? 206 : 200,
      headers: cabeceras,
    );
  }

  @override
  void close({bool force = false}) {}
}

/// UN INSTALADOR DE MENTIRA que apunta lo que le piden.
class InstaladorDeMentira implements Instalador {
  InstaladorDeMentira({this.hayPermiso = true, this.contesta});

  bool hayPermiso;

  /// Qué contesta a `instalar`. Por defecto, que la pantalla se abrió.
  ComoFueInstalar? contesta;

  /// Las rutas que se le pasaron. **Vacía es la prueba de que no se instaló
  /// nada**, que es la mitad importante del caso de la huella mala.
  final rutas = <String>[];
  var vecesQueSeAbrioElAjuste = 0;

  @override
  Future<bool> sePuedeInstalarDesdeAqui() async => hayPermiso;

  @override
  Future<ComoFueInstalar> instalar(String ruta) async {
    rutas.add(ruta);
    if (!hayPermiso) return const FaltaElPermisoDeInstalar();
    return contesta ?? const ElInstaladorEstaDelante();
  }

  @override
  Future<void> abrirElAjusteDelPermiso() async => vecesQueSeAbrioElAjuste++;
}

({
  ProviderContainer caja,
  AlmacenEnMemoria almacen,
  InstaladorDeMentira instalador,
  Dio dio,
})
montar({AlmacenEnMemoria? almacen, InstaladorDeMentira? instalador}) {
  final elAlmacen = almacen ?? AlmacenEnMemoria();
  final elInstalador = instalador ?? InstaladorDeMentira();
  final dio = Dio();
  final caja = ProviderContainer(
    overrides: [
      carpetaDeLaActualizacionProvider.overrideWith((ref) async => elAlmacen),
      dioDeLaActualizacionProvider.overrideWithValue(dio),
      instaladorProvider.overrideWithValue(elInstalador),
    ],
  );
  addTearDown(caja.dispose);
  return (
    caja: caja,
    almacen: elAlmacen,
    instalador: elInstalador,
    dio: dio,
  );
}

Future<void> bajar(
  ProviderContainer caja, {
  FicheroPublicado? fichero,
  String version = '1.5.0',
}) => caja
    .read(bajadaDeLaActualizacionProvider.notifier)
    .bajar(enlace: laUrl, fichero: fichero ?? elFichero(), version: version);

void main() {
  test('la bajada entera deja el APK comprobado y listo para instalar', () async {
    final m = montar();
    m.dio.httpClientAdapter = ServidorDeMentira();
    // Se escucha el proveedor para que el `Notifier` viva, igual que cuando la
    // franja lo mira desde las siete pantallas.
    final vistos = <ComoVaLaActualizacion>[];
    m.caja.listen(bajadaDeLaActualizacionProvider, (_, ahora) => vistos.add(ahora),
        fireImmediately: true);

    await bajar(m.caja);

    expect(m.caja.read(bajadaDeLaActualizacionProvider), isA<BajadaComprobada>());
    expect(await m.almacen.bytes('reparto.apk'), elApk.length);
    // El `.parcial` desaparece: si se quedara, la próxima vez se reanudaría sobre
    // un fichero ya completo.
    expect(m.almacen.tiene('reparto.apk.parcial'), isFalse);

    // LA BARRA SABE CUÁNTO FALTA, y lo sabe desde el anuncio de la api: el
    // servidor de mentira no manda `content-length`, como el de verdad.
    final bajando = vistos.whereType<BajandoLaActualizacion>().toList();
    expect(bajando, isNotEmpty);
    expect(
      bajando.every((b) => b.total == elApk.length),
      isTrue,
      reason:
          'el total tiene que salir de FicheroPublicado.bytes; si saliera del '
          'Content-Length sería cero o nulo, que es lo que enseñaba «30 MB/?» '
          'el 22/09/2026',
    );
    expect(bajando.last.parte, 1.0);
  });

  test(
    'LA DE JOSE: se corta a la mitad y al reintentar SIGUE desde donde iba',
    () async {
      final m = montar();
      final primero = ServidorDeMentira(cortaEn: 16000);
      m.dio.httpClientAdapter = primero;

      await bajar(m.caja);

      final fallo = m.caja.read(bajadaDeLaActualizacionProvider);
      expect(fallo, isA<FalloLaBajada>());
      expect((fallo as FalloLaBajada).bajados, 16000);
      expect(fallo.sePuedeReanudar, isTrue);
      expect(
        fallo.motivo,
        contains('Seguir descargando'),
        reason:
            'el motivo tiene que decir qué hacer: «se cortó la conexión, toca '
            'para seguir desde donde iba» sirve, «error al descargar» no',
      );
      // Y el navegador NO se ofrece al primer corte: en la conexión de allá un
      // corte es lo normal y lo que hay que hacer es seguir.
      expect(fallo.seOfreceElNavegador, isFalse);
      expect(await m.almacen.bytes('reparto.apk.parcial'), 16000);

      // ── SEGUNDA VUELTA, con un servidor que se porta.
      final segundo = ServidorDeMentira();
      m.dio.httpClientAdapter = segundo;

      await bajar(m.caja);

      expect(
        segundo.peticiones.single,
        'bytes=16000-',
        reason:
            'se pidió ${segundo.peticiones}: sin el Range se vuelven a bajar los '
            '16 kB que ya estaban, y en la conexión de allá eso es la diferencia '
            'entre terminar y no terminar',
      );
      expect(
        segundo.servidos.single,
        elApk.length - 16000,
        reason:
            'salieron ${segundo.servidos} bytes del servidor. Lo que se cuenta '
            'son los bytes PEDIDOS, no que el fichero acabe del tamaño justo: un '
            'reanudado falso también acaba del tamaño justo y gasta la descarga '
            'entera',
      );
      expect(
        m.caja.read(bajadaDeLaActualizacionProvider),
        isA<BajadaComprobada>(),
      );
      expect(await m.almacen.bytes('reparto.apk'), elApk.length);
    },
  );

  test(
    'LA OTRA DE JOSE: con la huella equivocada NO se instala, y lo dice',
    () async {
      final m = montar();
      m.dio.httpClientAdapter = ServidorDeMentira();

      // Llega entera —los bytes cuadran— y el contenido no es el anunciado.
      await bajar(m.caja, fichero: elFichero(huella: 'a' * 64));

      final fallo = m.caja.read(bajadaDeLaActualizacionProvider);
      expect(fallo, isA<FalloLaBajada>());
      expect((fallo as FalloLaBajada).motivo, contains('huella'));
      expect(
        fallo.motivo,
        contains('No se instala a medias'),
        reason:
            'un APK cortado se baja bien y luego no instala, y lo que ve la '
            'persona es «no se pudo instalar la aplicación»: hay que decirle qué '
            'pasó',
      );
      // Reanudar encima de un fichero envenenado no lo arregla nunca.
      expect(fallo.sePuedeReanudar, isFalse);
      expect(m.almacen.tiene('reparto.apk.parcial'), isFalse);
      expect(m.almacen.tiene('reparto.apk'), isFalse);

      // ── LA MITAD QUE IMPORTA: no se intentó instalar NADA.
      expect(
        m.instalador.rutas,
        isEmpty,
        reason:
            'se le pasó al instalador de Android un fichero cuya huella no '
            'cuadra: eso es exactamente lo que no puede pasar',
      );
    },
  );

  test('instalar un estado que no está comprobado no llama al instalador', () async {
    final m = montar();
    m.dio.httpClientAdapter = ServidorDeMentira(cortaEn: 16000);
    await bajar(m.caja);
    expect(m.caja.read(bajadaDeLaActualizacionProvider), isA<FalloLaBajada>());

    // Alguien pulsa «Instalar» con la descarga a medias —un botón mal cableado,
    // una franja vieja en pantalla—. No se instala un `.parcial`.
    await m.caja.read(bajadaDeLaActualizacionProvider.notifier).instalar();

    expect(m.instalador.rutas, isEmpty);
  });

  test('sin el permiso del sistema no se ofrece instalar: se dice', () async {
    final m = montar(instalador: InstaladorDeMentira(hayPermiso: false));
    m.dio.httpClientAdapter = ServidorDeMentira();

    await bajar(m.caja);

    final estado = m.caja.read(bajadaDeLaActualizacionProvider);
    expect(
      estado,
      isA<FaltaElPermisoParaInstalar>(),
      reason:
          'la primera vez el ajuste de «instalar aplicaciones desconocidas» no '
          'está dado en NINGÚN teléfono: si eso se pinta como «listo para '
          'instalar», el botón lleva a una pantalla que no sale',
    );
    // Y lo bajado se conserva: no hay que volver a gastarse los megas.
    expect(await m.almacen.bytes('reparto.apk'), elApk.length);
    expect(
      (estado as FaltaElPermisoParaInstalar).ruta,
      '/memoria/reparto.apk',
      reason: 'la ruta que se le pasará al instalador es la del fichero bueno',
    );

    // El ajuste se abre cuando se pide, y no concede nada por sí mismo.
    await m.caja.read(bajadaDeLaActualizacionProvider.notifier).pedirElPermiso();
    expect(m.instalador.vecesQueSeAbrioElAjuste, 1);
  });

  test('instalar le pasa la ruta del fichero BUENO, no la del parcial', () async {
    final m = montar();
    m.dio.httpClientAdapter = ServidorDeMentira();
    await bajar(m.caja);

    await m.caja.read(bajadaDeLaActualizacionProvider.notifier).instalar();

    expect(m.instalador.rutas, ['/memoria/reparto.apk']);
    expect(
      m.caja.read(bajadaDeLaActualizacionProvider),
      isA<ElInstaladorEstaEnPantalla>(),
    );
  });

  test(
    'si se cierra la pantalla de Android sin instalar, se puede volver a pulsar',
    () async {
      final m = montar();
      m.dio.httpClientAdapter = ServidorDeMentira();
      await bajar(m.caja);
      final mando = m.caja.read(bajadaDeLaActualizacionProvider.notifier);
      await mando.instalar();
      expect(
        m.caja.read(bajadaDeLaActualizacionProvider),
        isA<ElInstaladorEstaEnPantalla>(),
      );

      // La persona cerró esa pantalla del sistema sin instalar —pasa: se cancela
      // sin querer, o está conduciendo— y vuelve a pulsar «Instalar».
      await mando.instalar();

      expect(
        m.instalador.rutas,
        ['/memoria/reparto.apk', '/memoria/reparto.apk'],
        reason:
            'el segundo toque no llegó al instalador: el botón se queda puesto en '
            'la franja y en el cajón, se pulsa y no pasa NADA. Un botón muerto es '
            'peor que no tener botón',
      );
    },
  );

  test('tres fallos seguidos ofrecen el navegador; uno no', () async {
    final m = montar();
    m.dio.httpClientAdapter = ServidorDeMentira(codigo: 503);

    final ofrecidos = <bool>[];
    for (var vuelta = 0; vuelta < 3; vuelta++) {
      await bajar(m.caja);
      final estado = m.caja.read(bajadaDeLaActualizacionProvider);
      ofrecidos.add((estado as FalloLaBajada).seOfreceElNavegador);
    }

    expect(
      ofrecidos,
      [false, false, true],
      reason:
          'el navegador es la salida cuando lo de dentro no funciona, pero '
          'ofrecerlo al primer corte sería mandar a alguien a empezar de cero '
          'teniendo la mitad bajada',
    );
  });

  test('lo que ya está bajado NO se vuelve a bajar', () async {
    final m = montar();
    final servidor = ServidorDeMentira();
    m.dio.httpClientAdapter = servidor;
    await bajar(m.caja);
    expect(servidor.peticiones, hasLength(1));

    // La persona canceló la pantalla de Android porque estaba conduciendo y
    // vuelve por la tarde.
    await bajar(m.caja);

    expect(
      servidor.peticiones,
      hasLength(1),
      reason:
          'se volvieron a pedir los bytes de un APK que ya estaba bajado y '
          'comprobado: son 75 MB de la conexión de allá por nada',
    );
    expect(m.caja.read(bajadaDeLaActualizacionProvider), isA<BajadaComprobada>());
  });

  test('un parcial de OTRA versión se tira antes de pedir un solo byte', () async {
    final almacen = AlmacenEnMemoria()
      // Lo que dejó una descarga a medias de la versión anterior.
      ..sembrar('reparto.apk.parcial', List.filled(16000, 7))
      ..sembrar(
        'reparto.json',
        ApunteDeLaBajada(
          version: '1.4.0',
          sha256: 'b' * 64,
          bytes: 39000,
        ).aJson().codeUnits,
      );
    final m = montar(almacen: almacen);
    final servidor = ServidorDeMentira();
    m.dio.httpClientAdapter = servidor;

    await bajar(m.caja);

    expect(
      servidor.peticiones.single,
      isNull,
      reason:
          'se pidió «${servidor.peticiones.single}»: reanudar la 1.5.0 encima de '
          'un parcial de la 1.4.0 acaba en una huella que no cuadra DESPUÉS de '
          'haber gastado la descarga entera',
    );
    expect(m.caja.read(bajadaDeLaActualizacionProvider), isA<BajadaComprobada>());
    expect(await m.almacen.bytes('reparto.apk'), elApk.length);
  });

  test('el apunte que se escribe se vuelve a leer igual', () async {
    final m = montar();
    m.dio.httpClientAdapter = ServidorDeMentira();
    await bajar(m.caja);

    final apunte = ApunteDeLaBajada.deJson(
      await m.almacen.leerTexto('reparto.json'),
    );
    expect(apunte, isNotNull);
    expect(apunte!.version, '1.5.0');
    expect(apunte.sha256, suHuella);
    expect(apunte.bytes, elApk.length);
  });

  test('dos toques no son dos descargas', () async {
    final m = montar();
    final servidor = ServidorDeMentira();
    m.dio.httpClientAdapter = servidor;

    // Los dos toques de un doble toque caen en el mismo fotograma: se llama dos
    // veces sin esperar a la primera.
    final mando = m.caja.read(bajadaDeLaActualizacionProvider.notifier);
    final uno = mando.bajar(
      enlace: laUrl,
      fichero: elFichero(),
      version: '1.5.0',
    );
    final dos = mando.bajar(
      enlace: laUrl,
      fichero: elFichero(),
      version: '1.5.0',
    );
    await Future.wait([uno, dos]);

    expect(
      servidor.peticiones,
      hasLength(1),
      reason:
          'son 75 MB por descarga: es el fallo del 25/09/2026, cuando un doble '
          'toque disparaba dos bajadas del mismo APK',
    );
  });
}
