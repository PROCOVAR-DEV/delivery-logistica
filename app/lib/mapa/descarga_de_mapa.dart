// BAJAR EL PAQUETE DEL MAPA: una sola vez, entero, y reanudable.
//
// Jose: «que se descargue el mapa en la aplicación de Cuba para que tenga el
// mapa ya siempre funcional; cuando cargue sólo una vez, para que pueda
// trabajar».
//
// ## AQUÍ YA NO ESTÁ EL MOTOR — 05/10/2026
//
// El motor de bajar vive en `nucleo/descarga/descarga_reanudable.dart`, con todo
// lo que explicaba este fichero: el `.parcial`, el `Range`, la comprobación de
// que el servidor **de verdad** reanudó, el tope y el `sha256`. Lo que queda aquí
// son las dos cosas que son del mapa y de nadie más: **sus palabras** y **su
// apunte**.
//
// Se movió al hacer que la actualización de la APK se baje dentro de la
// aplicación igual que esto (`nucleo/actualizacion/bajada_de_la_actualizacion.dart`),
// y el motivo es el de siempre en esta casa: dos descargadores que se separan. El
// día que uno aprenda algo, el otro no lo sabrá, y el que no lo sepa será el que
// corre en el teléfono de quien está repartiendo.
//
// **Lo que ve el resto del proyecto no cambió ni una letra**: `DescargaDeMapa`,
// `bajar`, `DescargaLista` y `DescargaFallida` son los mismos de antes, con los
// mismos motivos literales. La pantalla del mapa y sus pruebas no se tocaron.

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../nucleo/descarga/descarga_reanudable.dart';
import '../nucleo/reloj.dart';
import 'anuncio_de_mapa.dart';
import 'carpeta_del_mapa.dart';

/// Cómo va la descarga. Se reporta hacia arriba para que la pantalla lo diga con
/// un número, no con una rueda.
///
/// Es el mismo de [DescargaReanudable], re-exportado aquí para no cambiarle el
/// nombre a quien ya lo usaba.
typedef ComoVa = ComoVaLaBajada;

/// Lo que sale de bajar.
sealed class ResultadoDeDescarga {
  const ResultadoDeDescarga();
}

class DescargaLista extends ResultadoDeDescarga {
  const DescargaLista(this.guardado);

  final PaqueteGuardado guardado;
}

/// FALLÓ, **y se dice qué faltó y qué se pierde sin ello** (`CLAUDE.md` §4).
class DescargaFallida extends ResultadoDeDescarga {
  const DescargaFallida(
    this.motivo, {
    required this.bajados,
    required this.total,
    required this.sePuedeReanudar,
  });

  /// El motivo literal, para la pantalla. «No se pudo descargar» no le dice a
  /// nadie qué hacer.
  final String motivo;
  final int bajados;
  final int total;

  /// `true` cuando lo bajado sigue sirviendo y la próxima vez continúa donde se
  /// quedó. `false` cuando hubo que tirarlo, y entonces la pantalla lo dice en
  /// vez de dejar creer que se conserva.
  final bool sePuedeReanudar;

  String get loQueFalta =>
      'Faltan ${enMegas(total - bajados)} de ${enMegas(total)}.';
}

/// LAS PALABRAS DEL MAPA. Son las que estaban escritas aquí desde el principio y
/// no han cambiado: las pruebas de `test/mapa/descarga_test.dart` comprueban
/// varias letra a letra.
class _PalabrasDelMapa extends PalabrasDeLaDescarga {
  const _PalabrasDelMapa();

  @override
  String noSePudoConectar(String motivo) =>
      'No se pudo conectar para bajar el mapa: $motivo. Lo bajado se guarda.';

  @override
  String elServidorContesto(int codigo) =>
      'El servidor contestó $codigo al pedir el mapa. Es un problema del '
      'servidor, no de la señal: avisa a la oficina.';

  @override
  String noContinuoDondeSePidio(String? rango, int desde) =>
      'El servidor no continuó donde se le pidió (mandó «$rango» y se le '
      'pidió desde $desde). Se ha descartado lo bajado; al volver a '
      'intentarlo empieza de cero.';

  @override
  String seCortoLaConexion() =>
      'Se cortó la conexión bajando el mapa. Lo bajado se guarda y continúa '
      'donde se quedó.';

  @override
  String detenida() =>
      'Descarga detenida. Lo bajado se guarda y continúa donde se quedó.';

  @override
  String llegoCortada(int bajados, int total) =>
      'La descarga se cortó: llegaron ${enMegas(bajados)} de los '
      '${enMegas(total)} del mapa. Lo bajado se guarda; al volver a '
      'intentarlo continúa donde se quedó.';

  @override
  String laHuellaNoCuadra() =>
      'El mapa llegó completo pero no es el que el servidor dice tener '
      '(la huella no cuadra). Se ha borrado lo bajado: hay que empezar de '
      'nuevo. Si vuelve a pasar, avisa a la oficina.';
}

/// QUIEN BAJA EL MAPA.
class DescargaDeMapa {
  DescargaDeMapa(Dio cliente, this._carpeta, {Reloj? reloj})
    : _motor = DescargaReanudable(cliente, _carpeta, const _PalabrasDelMapa()),
      _reloj = reloj ?? relojDelAparato;

  final DescargaReanudable _motor;
  final CarpetaDelMapa _carpeta;
  final Reloj _reloj;

  /// Baja [nivel] entero, continuando lo que hubiera.
  ///
  /// [cancelar] deja el `.parcial` donde está: cancelar no es tirar lo bajado.
  Future<ResultadoDeDescarga> bajar(
    NivelDeMapa nivel, {
    ComoVa? comoVa,
    CancelToken? cancelar,
  }) async {
    final fin = await _motor.bajar(
      LoQueSeBaja(
        url: nivel.url,
        bytes: nivel.bytes,
        sha256: nivel.sha256,
        fichero: nivel.fichero,
      ),
      comoVa: comoVa,
      cancelar: cancelar,
    );

    switch (fin) {
      case BajadaCortada(
        :final motivo,
        :final bajados,
        :final total,
        :final sePuedeReanudar,
      ):
        return DescargaFallida(
          motivo,
          bajados: bajados,
          total: total,
          sePuedeReanudar: sePuedeReanudar,
        );
      case BajadaCompleta():
        // EL APUNTE es lo del mapa: dice qué nivel hay guardado, de qué versión y
        // con qué huella, para poder comparar contra lo que el servidor anuncie
        // mañana (`anuncio_de_mapa.dart`).
        final guardado = PaqueteGuardado(
          nivel: nivel.nivel,
          version: nivel.version,
          bytes: nivel.bytes,
          sha256: nivel.sha256,
          guardadoAt: _reloj(),
        );
        await _carpeta.escribirTexto(nivel.apunte, _comoJson(guardado));
        return DescargaLista(guardado);
    }
  }
}

String _comoJson(PaqueteGuardado g) {
  final m = g.aJson();
  final partes = m.entries.map((e) {
    final v = e.value;
    return '"${e.key}":${v is num ? v : '"$v"'}';
  });
  return '{${partes.join(',')}}';
}

/// Para que las pruebas puedan inyectar bytes sin red.
Uint8List bytesDe(List<int> l) => Uint8List.fromList(l);
