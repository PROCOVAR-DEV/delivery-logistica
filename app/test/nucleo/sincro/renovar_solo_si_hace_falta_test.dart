// EL CICLO RENUEVA SÓLO CUANDO HACE FALTA — 15/10/2026.
//
// El logístico de Santiago, escritorio Windows 1.0.35: 142 `POST /refresh` en cinco
// horas, uno por cada `GET /api/sync/cambios`, cada 15–60 s, con un token que dura
// QUINCE MINUTOS. Cada renovación rota el refresh; a las 15:59:57 se perdió una
// respuesta, el reintento llegó cuatro minutos después con el refresh viejo, y
// Accesos lo leyó como robo y le cerró todas las sesiones a media tarde.
//
// Todo en PAREJA: con el token fresco N vueltas no renuevan NI UNA vez, y con el
// token a punto de vencer, vencido, o sin poder saberlo, SÍ (una). Y el 401 sigue
// renovando y reintentando.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/sincro/bajada.dart';
import 'package:reparto/nucleo/sincro/ciclo.dart';
import 'package:reparto/nucleo/sincro/huerfanos.dart';
import 'package:reparto/nucleo/sincro/identidad_del_aparato.dart';
import 'package:reparto/nucleo/sincro/subida.dart';
import 'package:reparto/pantallas/acceso/datos/servicio_acceso.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';

/// El reloj del SERVIDOR va tres horas por delante del aparato: el token se firma
/// con su hora y el aparato no puede compararla con la suya.
const _desfase = Duration(hours: 3);

void main() {
  late BaseLocal base;
  late RelojFalso reloj;
  late ColaDeSalida cola;
  late AlmacenEnMemoria almacen;

  setUp(() {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime(2026, 10, 15, 15, 30));
    cola = ColaDeSalida(base, reloj: reloj.leer);
  });
  setUp(() => aparatoYaDeAlta(base));
  tearDown(() => base.close());

  /// Un par como el de Accesos: token de 15 minutos firmado con la hora del
  /// servidor, pedido por el aparato a [pedidoA] (su hora).
  Sesion par(DateTime pedidoA, {String refresh = 'r0'}) {
    final firmado = pedidoA.add(_desfase).millisecondsSinceEpoch ~/ 1000;
    return Sesion.deJson(<String, Object?>{
      'token': tokenDePrueba(iat: firmado, exp: firmado + 900),
      'refresh_token': refresh,
    }, pedidoA: pedidoA);
  }

  /// Un servidor que va bien. `/refresh` devuelve un par nuevo firmado AHORA.
  /// [subidaQueCaduca] contesta 401 a la primera subida, como un token que se
  /// quedó viejo a mitad de vuelta.
  Future<RespuestaFalsa?> Function(PeticionVista) servidor({
    bool subidaQueCaduca = false,
  }) {
    var subidas = 0;
    var refrescos = 0;
    return (p) async {
      if (p.ruta.endsWith('/refresh')) {
        refrescos++;
        final firmado =
            reloj.ahora.add(_desfase).millisecondsSinceEpoch ~/ 1000;
        return RespuestaFalsa(200, <String, Object?>{
          'token': tokenDePrueba(iat: firmado, exp: firmado + 900),
          'refresh_token': 'r$refrescos',
        });
      }
      if (p.ruta.endsWith('/subida')) {
        subidas++;
        if (subidaQueCaduca && subidas == 1) {
          return RespuestaFalsa(401, <String, Object?>{'error': 'caducado'});
        }
        final apuntes =
            (p.cuerpo! as Map<String, Object?>)['apuntes']! as List<Object?>;
        return RespuestaFalsa(200, <String, Object?>{
          'resultados': [
            for (final a in apuntes)
              {
                'clave': (a! as Map<String, Object?>)['clave'],
                'estado': 'aplicado',
              },
          ],
        });
      }
      if (p.ruta.endsWith('/almacenes')) {
        return RespuestaFalsa(200, <String, Object?>{
          'sucursales': <Object?>[],
        });
      }
      return RespuestaFalsa(200, <String, Object?>{
        'hasta': '2026-10-15T15:30:00Z',
        'completa': true,
        'truncado': false,
        'cambios': <String, Object?>{},
      });
    };
  }

  ({CicloDeSincronizacion ciclo, ServidorFalso red, Renovador renovador})
  montar(Future<RespuestaFalsa?> Function(PeticionVista) responder) {
    final red = ServidorFalso(responder);
    final renovador = Renovador(
      Dio(BaseOptions(baseUrl: 'https://auth.test/api/auth'))
        ..httpClientAdapter = red,
      almacen,
      reloj: reloj.leer,
    );
    ClienteApi contra(String url) {
      final c = ClienteApi.montar(
        baseUrl: url,
        almacen: almacen,
        renovador: renovador,
        esperas: const <Duration>[],
      );
      c.dio.httpClientAdapter = red;
      return c;
    }

    return (
      ciclo: CicloDeSincronizacion(
        almacen: almacen,
        renovador: renovador,
        subida: Subida(
          cliente: contra('https://sync.test'),
          cola: cola,
          aparato: IdentidadDelAparato(base),
          base: base,
          quienEsta: () async => (await almacen.leer())?.sub,
        ),
        bajada: Bajada(
          cliente: contra('https://api.test'),
          base: base,
          frescura: RegistroDeFrescura(base, reloj: reloj.leer),
          reloj: reloj.leer,
        ),
        huerfanos: Huerfanos(base),
        cola: cola,
        haySesion: () => true,
      ),
      red: red,
      renovador: renovador,
    );
  }

  List<String> loQueSalio(ServidorFalso red) => [
    for (final p in red.vistas)
      if (p.ruta.endsWith('/refresh'))
        'renovar'
      else if (p.ruta.endsWith('/subida'))
        'subir'
      else if (p.ruta.endsWith('/sync/cambios'))
        'bajar',
  ];

  test('con el token fresco, diez vueltas seguidas NO renuevan ni una vez', () async {
    almacen = AlmacenEnMemoria(par(reloj.ahora));
    final m = montar(servidor());

    // Una vuelta cada 50 s, como los avisos del canal aquella tarde: 8 min 20 s,
    // y al token le quedan más de 5.
    for (var i = 0; i < 10; i++) {
      final resumen = await m.ciclo.ahora(motivo: 'aviso del canal');
      expect(resumen.bien, isTrue, reason: '$resumen');
      reloj.avanzar(const Duration(seconds: 50));
    }

    expect(
      m.renovador.renovacionesPedidas,
      0,
      reason:
          'un token de quince minutos recién pedido no se renueva en cada vuelta: '
          'cada renovación rota el refresh, y una respuesta perdida por la '
          'conexión de allá le cerró a Santiago todas sus sesiones',
    );
    expect(loQueSalio(m.red), isNot(contains('renovar')));
  });

  test('a punto de vencer (le quedan 4 min) SÍ renueva, una vez, y la vuelta '
      'siguiente ya no', () async {
    almacen = AlmacenEnMemoria(
      par(reloj.ahora.subtract(const Duration(minutes: 11))),
    );
    final m = montar(servidor());

    final primera = await m.ciclo.ahora(motivo: 'tic');
    expect(primera.pasos.first, PasoDelCiclo.renovar);
    reloj.avanzar(const Duration(minutes: 1));
    await m.ciclo.ahora(motivo: 'tic');

    expect(m.renovador.renovacionesPedidas, 1);
    expect((await almacen.leer())!.refresh, 'r1');
  });

  test('ocho horas sin señal: renueva ANTES de subir', () async {
    almacen = AlmacenEnMemoria(
      par(reloj.ahora.subtract(const Duration(hours: 8))),
    );
    await cola.encolar(
      metodo: 'POST',
      ruta: '/api/routes/local-1/results',
      cuerpo: <String, Object?>{'resultado': 'entregado'},
    );
    final m = montar(servidor());

    final resumen = await m.ciclo.ahora(motivo: 'volvió la red');

    expect(resumen.bien, isTrue, reason: '$resumen');
    expect(loQueSalio(m.red), ['renovar', 'subir', 'bajar']);
    expect(m.renovador.renovacionesPedidas, 1);
  });

  test('sin saber cuánto le queda (par guardado sin la hora, o el reloj del '
      'aparato fue hacia atrás) SÍ renueva', () async {
    // Guardado por una versión anterior: no trae `pedidoA`.
    almacen = AlmacenEnMemoria(
      Sesion.deJson(<String, Object?>{
        'token': tokenDePrueba(iat: 1, exp: 901),
        'refresh': 'r0',
      }),
    );
    await montar(servidor()).ciclo.ahora(motivo: 'arranque');
    expect((await almacen.leer())!.refresh, 'r1');

    // Pedido "dentro de una hora": el reloj del aparato se fue hacia atrás.
    almacen = AlmacenEnMemoria(par(reloj.ahora.add(const Duration(hours: 1))));
    final m = montar(servidor());
    await m.ciclo.ahora(motivo: 'tic');
    expect(m.renovador.renovacionesPedidas, 1);
  });

  test('un 401 con el token "fresco" renueva UNA vez y reintenta', () async {
    almacen = AlmacenEnMemoria(par(reloj.ahora));
    await cola.encolar(
      metodo: 'POST',
      ruta: '/api/routes/local-1/results',
      cuerpo: <String, Object?>{'resultado': 'entregado'},
    );
    final m = montar(servidor(subidaQueCaduca: true));

    final resumen = await m.ciclo.ahora(motivo: 'tic');

    expect(resumen.bien, isTrue, reason: '$resumen');
    expect(loQueSalio(m.red), ['subir', 'renovar', 'subir', 'bajar']);
    expect(m.renovador.renovacionesPedidas, 1);
    expect(await base.cuantosPendientes(), 0);
  });

  test('el par de ENTRAR con contraseña también lleva su hora', () async {
    almacen = AlmacenEnMemoria();
    final acceso = await ServicioDeAcceso(
      auth: dioFalso((p) async => RespuestaFalsa(200, parDeTokens())),
      almacen: almacen,
    ).entrar(usuario: 'yasmani', contrasena: 'la-buena');

    expect(
      (await almacen.leer())?.pedidoA,
      isNotNull,
      reason:
          'sin ella, el primer ciclo después de entrar renueva un token de un '
          'minuto: una rotación del refresh regalada',
    );
    expect(acceso.sesion.pedidoA, isNotNull);
  });

  test('la hora a la que se pidió el par sobrevive a cerrar la aplicación', () {
    final antes = par(reloj.ahora);
    final despues = Sesion.deJson(
      jsonDecode(jsonEncode(antes.aJson())) as Map<String, Object?>,
    );
    expect(
      despues.leQueda(reloj.ahora),
      const Duration(minutes: 15),
      reason:
          'los almacenes de verdad guardan en JSON: sin la hora, cada par leído '
          'de vuelta es «no se sabe» y el ciclo vuelve a renovar en cada vuelta',
    );
  });
}
