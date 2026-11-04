// EL MAPA QUE VIENE DENTRO DEL APK: se copia al primer arranque, sin red, y el resto del
// codigo lo ve como «descargado». Contra un copiador de mentira (nunca el asset de verdad).
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/distribuidor/mapa/instalador_del_mapa.dart';
import 'package:reparto/mapa/anuncio_de_mapa.dart' show PaqueteGuardado;
import 'package:reparto/nucleo/descarga/almacen_de_bajadas.dart';

/// El «asset» del APK, y un copiador que lo pasa a la carpeta por trozos.
class CopiadorFalso implements CopiadorDeAsset {
  CopiadorFalso(this.carpeta, this.contenido, {String version = '260922'})
    : manifiesto = jsonEncode({
        'nivel': 'detallado',
        'version': version,
        'bytes': contenido.length,
        'sha256': sha256.convert(contenido).toString(),
      });

  final AlmacenEnMemoria carpeta;
  List<int> contenido;
  String manifiesto;

  int copias = 0;
  List<int> desdes = [];

  /// Si es >0, la copia se corta (como si mataran la app) tras copiar tantos bytes.
  int cortarEn = 0;

  /// Corrompe lo copiado (huella mala).
  bool danar = false;

  @override
  Future<String?> leerTexto(String asset) async => manifiesto;

  @override
  Future<void> copiar({
    required String asset,
    required String destino,
    required int desde,
    required void Function(int copiados) alAvanzar,
  }) async {
    copias++;
    desdes.add(desde);
    final nombre = destino.split('/').last;
    var fin = contenido.length;
    if (cortarEn > 0) fin = (desde + cortarEn).clamp(0, contenido.length);
    final trozo = [...contenido.sublist(desde, fin)];
    if (danar && trozo.isNotEmpty) trozo[0] = trozo[0] ^ 0xff;
    await carpeta.anadir(nombre, trozo);
    alAvanzar(trozo.length);
    if (cortarEn > 0 && fin < contenido.length) {
      cortarEn = 0;
      throw const MapaIncluidoFallo('se mato la app a medias');
    }
  }
}

void main() {
  late AlmacenEnMemoria carpeta;
  late CopiadorFalso copiador;
  late InstaladorDelMapa instalador;
  final mapa = Uint8List.fromList(
    List.generate(50000, (i) => (i * 7 + 3) % 251),
  );

  setUp(() {
    carpeta = AlmacenEnMemoria();
    copiador = CopiadorFalso(carpeta, mapa);
    instalador = InstaladorDelMapa(
      carpeta,
      copiador,
      reloj: () => DateTime(2026, 11, 4, 9),
    );
  });

  test(
    'el primer arranque lo instala, con el apunte que lee el resto del codigo',
    () async {
      final avances = <int>[];
      final r = await instalador.instalar(alAvanzar: (c, t) => avances.add(c));
      expect(r, ResultadoDeLaInstalacion.instalado);
      expect(carpeta.bytesCrudos('cuba-detallado.pmtiles'), mapa);
      expect(carpeta.tiene('cuba-detallado.pmtiles.parcial'), isFalse);
      final apunte = PaqueteGuardado.deJson(
        await carpeta.leerTexto('cuba-detallado.json'),
      )!;
      expect(apunte.nivel, 'detallado');
      expect(apunte.version, '260922');
      expect(apunte.bytes, mapa.length);
      expect(apunte.sha256, sha256.convert(mapa).toString());
      expect(avances.last, mapa.length);
    },
  );

  test('el segundo arranque no repite nada', () async {
    await instalador.instalar();
    expect(copiador.copias, 1);
    expect(await instalador.instalar(), ResultadoDeLaInstalacion.yaEstaba);
    expect(copiador.copias, 1);
  });

  test(
    'con la huella mal: error claro y NO queda un .pmtiles bueno a medias',
    () async {
      copiador.danar = true;
      await expectLater(
        instalador.instalar(),
        throwsA(
          isA<MapaIncluidoFallo>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('dañado'),
          ),
        ),
      );
      expect(carpeta.tiene('cuba-detallado.pmtiles'), isFalse);
      expect(carpeta.tiene('cuba-detallado.json'), isFalse);
      expect(carpeta.tiene('cuba-detallado.pmtiles.parcial'), isFalse);
    },
  );

  test('reanuda tras un corte: sigue donde se quedo y acaba bien', () async {
    copiador.cortarEn = 20000;
    await expectLater(instalador.instalar(), throwsA(isA<MapaIncluidoFallo>()));
    expect(await carpeta.bytes('cuba-detallado.pmtiles.parcial'), 20000);
    expect(
      carpeta.tiene('cuba-detallado.pmtiles'),
      isFalse,
      reason: 'aun no vale',
    );

    await instalador.instalar();
    expect(copiador.desdes, [0, 20000]);
    expect(carpeta.bytesCrudos('cuba-detallado.pmtiles'), mapa);
  });

  test(
    'un parcial de OTRA version no se reanuda: se empieza de cero',
    () async {
      copiador.cortarEn = 20000;
      await expectLater(
        instalador.instalar(),
        throwsA(isA<MapaIncluidoFallo>()),
      );

      final nuevo = Uint8List.fromList(
        List.generate(40000, (i) => (i * 5) % 253),
      );
      final otro = CopiadorFalso(carpeta, nuevo, version: '261101');
      await InstaladorDelMapa(carpeta, otro).instalar();
      expect(otro.desdes, [0]);
      expect(carpeta.bytesCrudos('cuba-detallado.pmtiles'), nuevo);
    },
  );

  test('una version nueva en una actualizacion reemplaza a la vieja', () async {
    await instalador.instalar();
    final nuevo = Uint8List.fromList(
      List.generate(40000, (i) => (i * 5) % 253),
    );
    final otro = CopiadorFalso(carpeta, nuevo, version: '261101');
    expect(
      await InstaladorDelMapa(carpeta, otro).instalar(),
      ResultadoDeLaInstalacion.instalado,
    );
    expect(carpeta.bytesCrudos('cuba-detallado.pmtiles'), nuevo);
    expect(
      PaqueteGuardado.deJson(await carpeta.leerTexto('cuba-detallado.json'))!
          .version,
      '261101',
    );
  });

  test('un APK sin mapa lo dice', () async {
    copiador.manifiesto = '';
    await expectLater(
      instalador.instalar(),
      throwsA(
        isA<MapaIncluidoFallo>().having(
          (e) => e.mensaje,
          'm',
          contains('no trae el mapa'),
        ),
      ),
    );
  });
}
