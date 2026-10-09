// ENTREGAR A REVISION: EL SERVICIO.
//
// `docs/bandeja-de-revision.md`, B.1/B.2/B.5. Quien pierde `delivery.entrar` conserva su cola
// pero no puede subirla. Pide a Accesos un token de entrega (10 minutos, un solo ámbito) y
// deja cada apunte en la bandeja de `sync/`, de uno en uno, SIN aplicarlo.
//
// Lo que estas pruebas defienden, y cada una tiene su pareja:
//
//  * solo se entrega lo `pendiente` (no un rechazado, no un descartado);
//  * se marca `enRevision` CON LA RESPUESTA en la mano, nunca antes;
//  * nada se borra, ni se reescribe: el apunte es el mismo;
//  * el token que viaja es el de ENTREGA, nunca el de la sesión;
//  * el token caducado se pide OTRO una sola vez;
//  * un 404 de aparato no se arregla dando de alta otro;
//  * un 401 o un 409 de Accesos dejan la cola exactamente como estaba;
//  * un fallo de red no deja nada a medias.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/sincro/entrega_a_revision.dart';
import 'package:reparto/nucleo/sincro/identidad_del_aparato.dart';
import 'package:reparto/navegacion/portero.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';

const _aparato = 'ap-1';

RespuestaFalsa _token(String t) => RespuestaFalsa(200, {
  'token': t,
  'token_type': 'Bearer',
  'expires_in': 600,
  'ambito': 'reparto.entrega',
});

/// La respuesta de la entrega para el apunte que viene dentro.
RespuestaFalsa _enRevision(PeticionVista p, {String revision = 'ent-1'}) {
  final a = _apunteDe(p);
  return RespuestaFalsa(200, {
    'resultados': [
      {'clave': a['clave'], 'estado': 'en_revision', 'revision': revision},
    ],
  });
}

Map<String, Object?> _apunteDe(PeticionVista p) =>
    ((p.cuerpo! as Map<String, Object?>)['apuntes']! as List<Object?>).single
        as Map<String, Object?>;

String? _bearer(PeticionVista p) => p.cabeceras['Authorization'] as String?;

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late RelojFalso reloj;
  late AlmacenEnMemoria almacen;
  late ServidorFalso auth;
  late ServidorFalso sync;
  late EntregaARevision servicio;

  // Lo que contestan los dos servidores. Cada prueba cambia el que le toca.
  late Future<RespuestaFalsa?> Function(PeticionVista) enAuth;
  late Future<RespuestaFalsa?> Function(PeticionVista) enSync;

  const sesion = Sesion(token: 'token-normal', refresh: 'r0', sub: 'u1');

  EntregaARevision montar({bool aparatoDeAlta = true, bool enAparato = true}) {
    return EntregaARevision(
      auth: Dio(BaseOptions(baseUrl: 'https://auth.test/api/auth'))
        ..httpClientAdapter = auth,
      sync: EntregaARevision.dioDeSync(baseUrl: 'https://sync.test')
        ..httpClientAdapter = sync,
      cola: cola,
      base: base,
      aparato: IdentidadDelAparato(base),
      almacen: almacen,
      trabajaSinConexion: () => enAparato,
    );
  }

  setUp(() async {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime(2026, 10, 8, 14, 32));
    cola = ColaDeSalida(base, reloj: reloj.leer);
    almacen = AlmacenEnMemoria(sesion);
    enAuth = (p) async => _token('tok-entrega');
    enSync = (p) async => _enRevision(p);
    auth = ServidorFalso((p) => enAuth(p));
    sync = ServidorFalso((p) => enSync(p));
    await aparatoYaDeAlta(base, id: _aparato);
    servicio = montar();
  });

  tearDown(() => base.close());

  Future<String> encolar(
    String ruta, {
    String metodo = 'POST',
    Map<String, Object?> cuerpo = const {'a': 1},
  }) => cola.encolar(metodo: metodo, ruta: ruta, cuerpo: cuerpo);

  Future<List<String>> cuatroApuntes() async => [
    await encolar('/routes/r-1/results'),
    await encolar('/routes/r-2/results'),
    await encolar('/routes/r-3/results'),
  ];

  Future<EstadoApunte> estadoDe(String clave) async =>
      (await cola.porClave(clave))!.estado;

  /// La cola tal cual: ni un apunte menos ni uno cambiado.
  Future<List<(String, EstadoApunte, String, String)>> foto() async =>
      (await base.select(base.apuntes).get())
          .map((a) => (a.clave, a.estado, a.ruta, a.cuerpo))
          .toList();

  group('la entrega', () {
    test('de uno en uno, con el token de ENTREGA, y marca tras cada respuesta', () async {
      final claves = await cuatroApuntes();
      final antes = await foto();

      final r = await servicio.entregar();

      expect(r.resultado, ResultadoDeEntrega.entregado);
      expect(r.entregados, 3);
      expect(r.sinEntregar, 0);
      expect(r.error, isNull);

      // A Accesos: UNA vez, con el refresh (alias de B.1), y jamás a /refresh.
      expect(auth.vistas.map((v) => '${v.metodo} ${v.ruta}'), ['POST /entrega']);
      expect(
        (auth.vistas.single.cuerpo! as Map<String, Object?>)['refresh_token'],
        'r0',
      );

      // A sync: tres peticiones, UN apunte cada una, en el orden de la cola, y
      // todas con el token de entrega. El token de la sesión no sale NUNCA.
      expect(sync.vistas.map((v) => v.ruta), everyElement('/revision/entrega'));
      expect(sync.vistas.map((v) => _apunteDe(v)['clave']), claves);
      expect(
        sync.vistas.map(_bearer),
        everyElement('Bearer tok-entrega'),
        reason: 'con el token normal se presentaría con una autoridad que ya no tiene',
      );
      expect(sync.vistas.any((v) => '${v.cabeceras}'.contains('token-normal')), isFalse);
      for (final v in sync.vistas) {
        expect((v.cuerpo! as Map<String, Object?>)['aparato'], _aparato);
      }

      // En la cola: enRevision, con la entrega, y NADA más cambió.
      for (final c in claves) {
        final a = (await cola.porClave(c))!;
        expect(a.estado, EstadoApunte.enRevision);
        expect(a.revision, 'ent-1');
      }
      final despues = await foto();
      expect(despues.length, antes.length, reason: 'no se borró nada al entregarlo');
      expect(
        despues.map((f) => (f.$1, f.$3, f.$4)),
        antes.map((f) => (f.$1, f.$3, f.$4)),
        reason: 'la clave, la ruta y el cuerpo son los del original, byte a byte',
      );
      expect(await base.cuantosEnRevision(), 3);
      expect(await cola.lote(), isEmpty);
    });

    test('NO entrega un rechazado ni un descartado, y los deja como estaban', () async {
      final pendiente = await encolar('/routes/r-1/results');
      final rechazado = await encolar('/routes/r-2/results');
      await cola.resolver(
        rechazado,
        const ResultadoApunte(estado: EstadoResultado.rechazado, motivo: 'no'),
      );
      final descartado = await encolar('/routes/r-3/results');
      await cola.resolver(
        descartado,
        const ResultadoApunte(estado: EstadoResultado.rechazado, motivo: 'no'),
      );
      await cola.descartar(descartado);

      final r = await servicio.entregar();

      expect(r.entregados, 1);
      expect(sync.vistas.map((v) => _apunteDe(v)['clave']), [pendiente]);
      expect(await estadoDe(rechazado), EstadoApunte.rechazado);
      expect(await estadoDe(descartado), EstadoApunte.descartado);
    });

    test('marca DESPUÉS de la respuesta: durante la petición sigue pendiente', () async {
      final claves = await cuatroApuntes();
      final visto = <String, EstadoApunte>{};
      enSync = (p) async {
        final clave = _apunteDe(p)['clave']! as String;
        visto[clave] = await estadoDe(clave);
        return _enRevision(p);
      };

      await servicio.entregar();

      expect(
        visto.values,
        everyElement(EstadoApunte.pendiente),
        reason:
            'marcarlo al mandar deja un apunte que ni sube ni está arriba si la '
            'respuesta no llega',
      );
      expect(visto.keys, claves);
    });

    test('un fallo de red a mitad: lo entregado queda, lo demás PENDIENTE y se para', () async {
      final claves = await cuatroApuntes();
      var n = 0;
      enSync = (p) async => ++n == 2 ? null : _enRevision(p);

      final r = await servicio.entregar();

      expect(r.resultado, ResultadoDeEntrega.parcial);
      expect(r.entregados, 1);
      expect(r.sinEntregar, 2);
      expect(r.error, TextosDeEntrega.sinConexion);
      expect(await estadoDe(claves[0]), EstadoApunte.enRevision);
      expect(await estadoDe(claves[1]), EstadoApunte.pendiente);
      expect(await estadoDe(claves[2]), EstadoApunte.pendiente);
      expect(n, 2, reason: 'sin red no se insiste con los demás');
      expect(
        (await cola.lote()).map((a) => a.estado),
        everyElement(EstadoApunte.pendiente),
        reason: 'ningún estado intermedio: se puede volver a pulsar',
      );
    });

    test('la segunda pulsación termina lo que quedaba', () async {
      final claves = await cuatroApuntes();
      var n = 0;
      enSync = (p) async => ++n == 2 ? null : _enRevision(p);
      await servicio.entregar();
      sync.vistas.clear();

      final r = await servicio.entregar();

      expect(r.resultado, ResultadoDeEntrega.entregado);
      expect(sync.vistas.map((v) => _apunteDe(v)['clave']), [claves[1], claves[2]]);
    });

    test('sin nada pendiente no se pide ni un token', () async {
      final r = await servicio.entregar();
      expect(r.resultado, ResultadoDeEntrega.nadaQueEntregar);
      expect(auth.vistas, isEmpty);
      expect(sync.vistas, isEmpty);
    });

    test('en la WEB no hace nada: ni token ni petición', () async {
      await cuatroApuntes();
      final web = montar(enAparato: false);

      final r = await web.entregar();

      expect(r.resultado, ResultadoDeEntrega.noAplica);
      expect(auth.vistas, isEmpty);
      expect(sync.vistas, isEmpty);
      expect((await cola.lote()).length, 3);
    });

    test('dos pulsaciones a la vez son UNA pasada', () async {
      await cuatroApuntes();
      final a = servicio.entregar();
      final b = servicio.entregar();
      await Future.wait([a, b]);
      expect(auth.vistas.length, 1);
      expect(sync.vistas.length, 3);
    });
  });

  group('el token de 10 minutos', () {
    test('caduca a mitad: se pide OTRO una vez y se sigue', () async {
      final claves = await cuatroApuntes();
      var tokens = 0;
      enAuth = (p) async => _token('tok-${++tokens}');
      var n = 0;
      enSync = (p) async =>
          ++n == 2 ? RespuestaFalsa(401, const {'error': 'token caducado'}) : _enRevision(p);

      final r = await servicio.entregar();

      expect(r.resultado, ResultadoDeEntrega.entregado);
      expect(auth.cuantas('POST', '/entrega'), 2);
      expect(
        sync.vistas.map(_bearer).toList(),
        ['Bearer tok-1', 'Bearer tok-1', 'Bearer tok-2', 'Bearer tok-2'],
        reason: 'el apunte que dio 401 se reintenta con el token nuevo',
      );
      for (final c in claves) {
        expect(await estadoDe(c), EstadoApunte.enRevision);
      }
    });

    test('la pareja: si siguen los 401 NO se insiste sin fin, y la cola queda entera', () async {
      await cuatroApuntes();
      var tokens = 0;
      enAuth = (p) async => _token('tok-${++tokens}');
      enSync = (p) async => RespuestaFalsa(401, const {'error': 'no'});
      final antes = await foto();

      final r = await servicio.entregar();

      expect(auth.cuantas('POST', '/entrega'), 2, reason: 'UNA renovación por entrega');
      expect(r.resultado, ResultadoDeEntrega.sesionTerminada);
      expect(r.entregados, 0);
      expect(await foto(), antes);
    });

    test('UNA sola renovación por entrega, aunque el token caduque otra vez', () async {
      final claves = await cuatroApuntes();
      var tokens = 0;
      enAuth = (p) async => _token('tok-${++tokens}');
      var n = 0;
      // 1.º apunte: 401 → se renueva → entra. 2.º apunte: 401 otra vez (con el token
      // nuevo): ya no se renueva más, se para.
      enSync = (p) async {
        n++;
        return (n == 1 || n == 3)
            ? RespuestaFalsa(401, const {'error': 'caducado'})
            : _enRevision(p);
      };

      final r = await servicio.entregar();

      expect(auth.cuantas('POST', '/entrega'), 2);
      expect(r.resultado, ResultadoDeEntrega.parcial);
      expect(r.entregados, 1);
      expect(await estadoDe(claves[0]), EstadoApunte.enRevision);
      expect(await estadoDe(claves[1]), EstadoApunte.pendiente);
      expect(await estadoDe(claves[2]), EstadoApunte.pendiente);
    });

    test('Accesos devuelve algo que no es un token de entrega: no se usa', () async {
      await cuatroApuntes();
      enAuth = (p) async => RespuestaFalsa(200, {
        'token': 'tok-normal',
        'ambito': null,
        'refresh_token': 'otro',
      });

      final r = await servicio.entregar();

      expect(sync.vistas, isEmpty);
      expect(r.entregados, 0);
      expect(r.sinEntregar, 3);
    });
  });

  group('lo que dice Accesos', () {
    test('401: «Tu sesión terminó», la cola EXACTAMENTE igual y la sesión sin tocar', () async {
      await cuatroApuntes();
      enAuth = (p) async => RespuestaFalsa(401, const {'error': 'invalid_refresh'});
      final antes = await foto();

      final r = await servicio.entregar();

      expect(r.resultado, ResultadoDeEntrega.sesionTerminada);
      expect(r.error, TextosDeEntrega.sesionTerminada);
      expect(sync.vistas, isEmpty);
      expect(
        await foto(),
        antes,
        reason: 'un 401 de Accesos no borra ni cambia ni un apunte: es la persona, no el trabajo',
      );
      expect(await almacen.leer(), isNotNull);
    });

    test('409 tiene_permiso: se dice y NO se entrega nada', () async {
      await cuatroApuntes();
      enAuth = (p) async => RespuestaFalsa(409, const {
        'error': 'tiene_permiso',
        'codigo': 'tiene_permiso',
      });
      final antes = await foto();

      final r = await servicio.entregar();

      expect(r.resultado, ResultadoDeEntrega.yaTienePermiso);
      expect(r.error, TextosDeEntrega.yaTienePermiso);
      expect(sync.vistas, isEmpty, reason: 'quien SÍ tiene permiso no usa la revisión');
      expect(await foto(), antes);
    });

    test('503 (comprobación no disponible): red, no «sin permiso»; todo pendiente', () async {
      await cuatroApuntes();
      enAuth = (p) async =>
          RespuestaFalsa(503, const {'error': 'comprobacion_no_disponible'});

      final r = await servicio.entregar();

      expect(r.resultado, ResultadoDeEntrega.sinConexion);
      expect(r.sinEntregar, 3);
      expect(sync.vistas, isEmpty);
    });

    test('403 sin_sucursal: la frase, no el código', () async {
      await cuatroApuntes();
      enAuth = (p) async => RespuestaFalsa(403, const {'error': 'sin_sucursal'});

      final r = await servicio.entregar();

      expect(r.resultado, ResultadoDeEntrega.rechazado);
      expect(r.error, TextosDeEntrega.sinSucursal);
      expect(sync.vistas, isEmpty);
    });

    test('429 rate_limited: se dice que espere y NO se reintenta', () async {
      await cuatroApuntes();
      enAuth = (p) async => RespuestaFalsa(429, const {'error': 'rate_limited'});

      final r = await servicio.entregar();

      expect(r.error, TextosDeEntrega.demasiadosIntentos);
      expect(auth.vistas.length, 1, reason: 'sin reintento ciego');
      expect(sync.vistas, isEmpty);
      expect(r.sinEntregar, 3);
    });

    test('un 409 tiene_permiso al RENOVAR el token a mitad también para la entrega', () async {
      final claves = await cuatroApuntes();
      var tokens = 0;
      enAuth = (p) async => ++tokens == 1
          ? _token('tok-1')
          : RespuestaFalsa(409, const {'error': 'tiene_permiso', 'codigo': 'tiene_permiso'});
      enSync = (p) async => RespuestaFalsa(401, const {'error': 'caducado'});

      final r = await servicio.entregar();

      expect(r.resultado, ResultadoDeEntrega.yaTienePermiso);
      expect(sync.vistas.length, 1, reason: 'no se sigue con los demás apuntes');
      for (final c in claves) {
        expect(await estadoDe(c), EstadoApunte.pendiente);
      }
    });

    test('el refresh que se presenta es el VIGENTE del almacén, no el del principio', () async {
      await cuatroApuntes();
      var tokens = 0;
      enAuth = (p) async {
        // Entre las dos peticiones de token alguien renovó la sesión.
        if (++tokens == 1) {
          await almacen.guardar(const Sesion(token: 'n', refresh: 'r1', sub: 'u1'));
        }
        return _token('tok-$tokens');
      };
      var n = 0;
      enSync = (p) async =>
          ++n == 1 ? RespuestaFalsa(401, const {'error': 'caducado'}) : _enRevision(p);

      await servicio.entregar();

      expect(
        auth.vistas.map((v) => (v.cuerpo! as Map<String, Object?>)['refresh_token']),
        ['r0', 'r1'],
      );
    });
  });

  group('lo que dice sync', () {
    test('404 aparato_no_registrado: se dice y NO se da de alta otro', () async {
      await cuatroApuntes();
      enSync = (p) async => RespuestaFalsa(404, const {
        'error': 'Ese aparato no está registrado.',
        'codigo': 'aparato_no_registrado',
      });
      final antes = await foto();

      final r = await servicio.entregar();

      expect(r.resultado, ResultadoDeEntrega.aparatoSinAlta);
      expect(r.error, TextosDeEntrega.aparatoSinAlta);
      expect(sync.vistas.where((v) => v.ruta == '/aparato'), isEmpty);
      expect(sync.vistas.length, 1, reason: 'no se reintenta ni se da de alta');
      expect(
        await IdentidadDelAparato(base).leer(),
        _aparato,
        reason: 'darlo de alta exige un token normal que esta persona ya no tiene',
      );
      expect(await foto(), antes);
    });

    test('sin alta guardada no se pide ni un token', () async {
      await cuatroApuntes();
      await IdentidadDelAparato(base).olvidar();

      final r = await servicio.entregar();

      expect(r.resultado, ResultadoDeEntrega.aparatoSinAlta);
      expect(auth.vistas, isEmpty);
      expect(sync.vistas, isEmpty);
    });

    test('409 huella_distinta o 422: ese apunte sigue pendiente con su literal y los demás pasan', () async {
      final claves = await cuatroApuntes();
      var n = 0;
      enSync = (p) async => ++n == 2
          ? RespuestaFalsa(422, const {
              'error': 'Esa ruta no se puede entregar.',
              'codigo': 'entrega_no_admitida',
            })
          : _enRevision(p);

      final r = await servicio.entregar();

      expect(r.resultado, ResultadoDeEntrega.parcial);
      expect(r.entregados, 2);
      expect(r.sinEntregar, 1);
      expect(r.errores, ['Esa ruta no se puede entregar.']);
      expect(await estadoDe(claves[0]), EstadoApunte.enRevision);
      expect(await estadoDe(claves[1]), EstadoApunte.pendiente);
      expect(await estadoDe(claves[2]), EstadoApunte.enRevision);
    });

    test('429 cupo_de_revision: se para, con el literal, y el resto pendiente', () async {
      final claves = await cuatroApuntes();
      var n = 0;
      enSync = (p) async => ++n == 2
          ? RespuestaFalsa(429, const {
              'error': 'La bandeja de tu sucursal está llena.',
              'codigo': 'cupo_de_revision',
            })
          : _enRevision(p);

      final r = await servicio.entregar();

      expect(r.error, 'La bandeja de tu sucursal está llena.');
      expect(n, 2, reason: 'con el cupo lleno no se sigue llamando');
      expect(await estadoDe(claves[0]), EstadoApunte.enRevision);
      expect(await estadoDe(claves[1]), EstadoApunte.pendiente);
      expect(await estadoDe(claves[2]), EstadoApunte.pendiente);
    });

    // `repetido` puede venir de DOS sitios, y no es lo mismo (revision_entrega.go):
    //  * con `revision`: está en la bandeja. Si ya lo decidieron, quién/cuándo/id vienen
    //    en `mias` (el `motivo` de un descarte lleva «por X» dentro).
    //  * sin `revision` y aplicado/rechazado: lo resolvió ANTES la subida normal.
    RespuestaFalsa repetido(PeticionVista p, String actual, {String? revision, String? motivo}) =>
        RespuestaFalsa(200, {
          'resultados': [
            {
              'clave': _apunteDe(p)['clave'],
              'estado': 'repetido',
              'estadoActual': actual,
              'revision': ?revision,
              'motivo': ?motivo,
            },
          ],
        });

    test('«repetido» ya decidido en la bandeja: se marca y se lee quién en `mias`', () async {
      final clave = await encolar('/routes/r-1/results');
      enSync = (p) async => p.metodo == 'GET'
          ? RespuestaFalsa(200, {
              'entregas': [
                {
                  'clave': clave,
                  'estado': 'descartado',
                  'revision': 'ent-9',
                  'decididoPorNombre': 'Marta Pérez',
                  'decididoAt': '2026-10-09T13:10:00Z',
                  'motivo': 'Se rehízo en la web',
                  'idCreado': null,
                },
              ],
              'truncado': false,
            })
          : repetido(
              p,
              'descartado',
              revision: 'ent-9',
              motivo: 'Descartado en la revisión por Marta Pérez: Se rehízo en la web',
            );

      final r = await servicio.entregar();

      expect(r.resultado, ResultadoDeEntrega.entregado);
      expect(r.entregados, 1);
      final a = (await cola.porClave(clave))!;
      expect(a.estado, EstadoApunte.descartadoPorRevisor);
      expect(a.revisadoPor, 'Marta Pérez');
      expect(
        a.motivoRevision,
        'Se rehízo en la web',
        reason: 'el motivo es el escrito, no la frase con «por X» ya montada',
      );
      expect(sync.vistas.map((v) => '${v.metodo} ${v.ruta}'), [
        'POST /revision/entrega',
        'GET /revision/mias',
      ]);
    });

    test('«repetido» descartado CON quién, cuándo y el texto: se anota SIN ir a `mias`', () async {
      final clave = await encolar('/routes/r-1/results');
      enSync = (p) async => RespuestaFalsa(200, {
        'resultados': [
          {
            'clave': _apunteDe(p)['clave'],
            'estado': 'repetido',
            'estadoActual': 'descartado',
            'revision': 'ent-9',
            'motivo': 'Descartado en la revisión por Marta Pérez: Se rehízo en la web',
            'decididoPorNombre': 'Marta Pérez',
            'decididoAt': '2026-10-09T13:12:00Z',
            'motivoDelDescarte': 'Se rehízo en la web',
          },
        ],
      });

      await servicio.entregar();

      final a = (await cola.porClave(clave))!;
      expect(a.estado, EstadoApunte.descartadoPorRevisor);
      expect(a.revisadoPor, 'Marta Pérez');
      expect(a.motivoRevision, 'Se rehízo en la web', reason: 'el texto suelto, no la frase montada');
      expect(sync.vistas.length, 1, reason: 'la respuesta bastaba: ni una petición más');
    });

    test('«repetido» aplicado por el revisor CON su id: sustituye el local-… y deja el aviso', () async {
      await base.into(base.routes).insert(RoutesCompanion.insert(id: 'local-ruta'));
      final clave = await cola.encolar(
        metodo: 'POST',
        ruta: '/routes',
        cuerpo: const {'nombre': 'Ruta'},
        provisional: 'local-ruta',
      );
      enSync = (p) async => RespuestaFalsa(200, {
        'resultados': [
          {
            'clave': clave,
            'estado': 'repetido',
            'estadoActual': 'aplicado',
            'revision': 'ent-9',
            'id': 'ruta-de-verdad',
            'decididoPorNombre': 'Marta Pérez',
            'decididoAt': '2026-10-09T13:10:00Z',
            'descartados': [
              {'pedidoId': 'p-9', 'operationNumber': 'X-2992', 'motivo': 'ya va en otra ruta'},
            ],
          },
        ],
      });

      await servicio.entregar();

      final a = (await cola.porClave(clave))!;
      expect(a.estado, EstadoApunte.aplicado);
      expect(a.revisadoPor, 'Marta Pérez');
      expect(a.motivo, contains('X-2992'));
      expect((await base.select(base.routes).get()).single.id, 'ruta-de-verdad');
      expect(sync.vistas.length, 1);
    });

    test('«repetido» aplicado por la SUBIDA NORMAL con id: sustituye el local-… (no deja huérfano)', () async {
      await base.into(base.routes).insert(RoutesCompanion.insert(id: 'local-ruta'));
      final clave = await cola.encolar(
        metodo: 'POST',
        ruta: '/routes',
        cuerpo: const {'nombre': 'Ruta'},
        provisional: 'local-ruta',
      );
      enSync = (p) async => RespuestaFalsa(200, {
        'resultados': [
          {
            'clave': clave,
            'estado': 'repetido',
            'estadoActual': 'aplicado',
            'id': 'ruta-de-verdad',
            'descartados': [
              {'pedidoId': 'p-9', 'operationNumber': 'X-2992', 'motivo': 'ya va en otra ruta'},
            ],
          },
        ],
      });

      final r = await servicio.entregar();

      expect(r.yaResueltos, 1);
      expect((await cola.porClave(clave))!.estado, EstadoApunte.aplicado);
      expect(
        (await cola.porClave(clave))!.motivo,
        contains('X-2992'),
        reason: 'lo que se cayó aquella vez también se lee: el aviso «salió con menos»',
      );
      expect((await base.select(base.routes).get()).single.id, 'ruta-de-verdad');
      expect((await base.select(base.equivalencias).get()).single.provisional, 'local-ruta');
    });

    test('R3: respuesta perdida → un revisor aplica k1 → la reentrega NO choca y k2 sale con su cuerpo ORIGINAL', () async {
      // Los dos apuntes ya están guardados en `sync` (la respuesta de la primera
      // entrega se perdió: aquí siguen `pendiente`). Un revisor aplica k1, que crea una
      // ruta con `local-ruta`. `sync` guarda el original con `local-…` y lo traduce él
      // al aplicar: si la app reescribe k2 al ver el `repetido` de k1, k2 llega con
      // OTRO cuerpo → 409 huella_distinta y se atasca para siempre.
      await base.into(base.routes).insert(RoutesCompanion.insert(id: 'local-ruta'));
      final k1 = await cola.encolar(
        metodo: 'POST',
        ruta: '/routes',
        cuerpo: const {'nombre': 'Ruta'},
        provisional: 'local-ruta',
      );
      final k2 = await cola.encolar(
        metodo: 'PATCH',
        ruta: '/routes/local-ruta',
        cuerpo: const {'status': 'in_progress', 'rutaId': 'local-ruta'},
      );
      String huella(Map<String, Object?> a) =>
          '${a['metodo']}|${a['ruta']}|${a['cuerpo']}|${a['provisional']}';
      final guardado = <String, String>{
        for (final c in [k1, k2])
          c: huella((await cola.porClave(c))!.aJson(ColaDeSalida.cuerpoDe((await cola.porClave(c))!))),
      };
      enSync = (p) async {
        final a = _apunteDe(p);
        final clave = a['clave']! as String;
        if (guardado[clave] != huella(a)) {
          return RespuestaFalsa(409, const {
            'error': 'El apunte ya se entregó con otro contenido.',
            'codigo': 'huella_distinta',
          });
        }
        return RespuestaFalsa(200, {
          'resultados': [
            if (clave == k1)
              {
                'clave': clave,
                'estado': 'repetido',
                'estadoActual': 'aplicado',
                'revision': 'ent-1',
                'id': 'ruta-real',
                'decididoPorNombre': 'Marta Pérez',
                'decididoAt': '2026-10-09T13:10:00Z',
              }
            else
              {
                'clave': clave,
                'estado': 'repetido',
                'estadoActual': 'en_revision',
                'revision': 'ent-1',
              },
          ],
        });
      };
      final k2Antes = (await cola.porClave(k2))!;

      final r = await servicio.entregar();

      expect(r.errores, isEmpty, reason: 'ningún 409 huella_distinta');
      expect(r.resultado, ResultadoDeEntrega.entregado);
      final a1 = (await cola.porClave(k1))!;
      expect(a1.estado, EstadoApunte.aplicado);
      expect(a1.revisadoPor, 'Marta Pérez');
      final a2 = (await cola.porClave(k2))!;
      expect(a2.estado, EstadoApunte.enRevision, reason: 'no se queda pendiente para siempre');
      expect((a2.ruta, a2.cuerpo), (k2Antes.ruta, k2Antes.cuerpo));
      expect(
        (await base.select(base.routes).get()).single.id,
        'ruta-real',
        reason: 'la fila local sí pasa al id de verdad',
      );
    });

    test('un apunte que se resuelve MIENTRAS se entrega no se manda (se vuelve a leer)', () async {
      final claves = await cuatroApuntes();
      enSync = (p) async {
        // Mientras viaja el primero, el tercero se resuelve por otro lado.
        if (_apunteDe(p)['clave'] == claves[0]) {
          await cola.resolver(
            claves[2],
            const ResultadoApunte(estado: EstadoResultado.rechazado, motivo: 'no'),
          );
        }
        return _enRevision(p);
      };

      await servicio.entregar();

      expect(sync.vistas.map((v) => _apunteDe(v)['clave']), [claves[0], claves[1]]);
      expect(await estadoDe(claves[2]), EstadoApunte.rechazado, reason: 'ni se manda ni se pisa');
    });

    test('la pareja: «repetido» aún esperando NO pregunta `mias`', () async {
      final clave = await encolar('/routes/r-1/results');
      enSync = (p) async => repetido(p, 'en_revision', revision: 'ent-9');

      final r = await servicio.entregar();

      expect(r.resultado, ResultadoDeEntrega.entregado);
      expect((await cola.porClave(clave))!.estado, EstadoApunte.enRevision);
      expect(sync.vistas.length, 1);
    });

    test('«repetido» aplicado por la SUBIDA NORMAL (sin revision): aplicado, nunca enRevision', () async {
      final clave = await encolar('/routes/r-1/results');
      enSync = (p) async => repetido(p, 'aplicado');

      final r = await servicio.entregar();

      expect(r.entregados, 0, reason: 'no fue una entrega');
      expect(r.yaResueltos, 1);
      final a = (await cola.porClave(clave))!;
      expect(a.estado, EstadoApunte.aplicado);
      expect(a.revisadoPor, isNull);
      expect(await base.cuantosEnRevision(), 0);
    });

    test('«repetido» rechazado por la SUBIDA NORMAL: rechazado con su literal', () async {
      final clave = await encolar('/routes/r-1/results');
      enSync = (p) async => repetido(p, 'rechazado', motivo: 'Ese pedido ya va en otra ruta');

      await servicio.entregar();

      final a = (await cola.porClave(clave))!;
      expect(a.estado, EstadoApunte.rechazado);
      expect(a.motivo, 'Ese pedido ya va en otra ruta');
    });

    test('una respuesta que no nombra la clave deja el apunte pendiente', () async {
      final clave = await encolar('/routes/r-1/results');
      enSync = (p) async => RespuestaFalsa(200, const {'resultados': <Object?>[]});

      final r = await servicio.entregar();

      expect(r.entregados, 0);
      expect(await estadoDe(clave), EstadoApunte.pendiente);
    });

    test('si la hoja de resultados no llega, el completed de esa ruta tampoco sale', () async {
      final hoja = await encolar('/routes/r-1/results');
      final completa = await encolar(
        '/routes/r-1',
        metodo: 'PATCH',
        cuerpo: const {'status': 'completed'},
      );
      final otra = await encolar(
        '/routes/r-2',
        metodo: 'PATCH',
        cuerpo: const {'status': 'completed'},
      );
      enSync = (p) async => _apunteDe(p)['ruta'] == '/routes/r-1/results'
          ? RespuestaFalsa(422, const {'error': 'no', 'codigo': 'entrega_no_admitida'})
          : _enRevision(p);

      await servicio.entregar();

      expect(await estadoDe(hoja), EstadoApunte.pendiente);
      expect(
        await estadoDe(completa),
        EstadoApunte.pendiente,
        reason: 'completar la ruta sin sus resultados la congela mal',
      );
      expect(await estadoDe(otra), EstadoApunte.enRevision, reason: 'otra ruta no depende de ella');
    });

    test('el provisional viaja SIEMPRE que el apunte lo tenga: `local-…` y el UUID de una zona', () async {
      await cola.encolar(
        metodo: 'POST',
        ruta: '/routes',
        cuerpo: const {'nombre': 'Ruta'},
        provisional: 'local-9f3a',
      );
      await cola.encolar(
        metodo: 'POST',
        ruta: '/board/columns?branchId=hab-1',
        cuerpo: const {'id': '018f2c7e-0000-7000-8000-000000000001', 'nombre': 'Vista'},
        provisional: '018f2c7e-0000-7000-8000-000000000001',
      );
      await encolar('/routes/r-1/results');

      await servicio.entregar();

      final apuntes = sync.vistas.map(_apunteDe).toList();
      expect(apuntes[0]['provisional'], 'local-9f3a');
      expect(
        apuntes[1]['provisional'],
        '018f2c7e-0000-7000-8000-000000000001',
        reason:
            'un revisor que aplica la creación de la zona deja anotado el provisional '
            'del id creado: sin él se pierde la bisagra',
      );
      expect(apuntes[2].containsKey('provisional'), isFalse, reason: 'el que no tiene, no lo inventa');
    });

    test('lo que se manda es lo que el servidor espera: aparato y apunte con sus campos', () async {
      await encolar('/routes/r-1/results');

      await servicio.entregar();

      final cuerpo = sync.vistas.single.cuerpo! as Map<String, Object?>;
      expect(cuerpo.keys.toSet(), {'aparato', 'apuntes'});
      expect(
        _apunteDe(sync.vistas.single).keys.toSet(),
        {'clave', 'hecho', 'metodo', 'ruta', 'cuerpo'},
      );
    });

    test('403 sin_permiso_reparto (token que no es de entrega): no se dice «no tienes permiso»', () async {
      await cuatroApuntes();
      enSync = (p) async => RespuestaFalsa(403, const {
        'error': 'No tienes permiso para entrar a Reparto.',
        'codigo': 'sin_permiso_reparto',
      });

      final r = await servicio.entregar();

      expect(r.resultado, ResultadoDeEntrega.rechazado);
      expect(r.error, TextosDeEntrega.noAceptoElToken);
      expect(sync.vistas.length, 1, reason: 'no se insiste');
    });

    test('403 aparato_ajeno y 400: se para con el literal del servidor', () async {
      await cuatroApuntes();
      enSync = (p) async => RespuestaFalsa(403, const {
        'error': 'Ese aparato no es tuyo.',
        'codigo': 'aparato_ajeno',
      });

      final r = await servicio.entregar();

      expect(r.error, 'Ese aparato no es tuyo.');
      expect(sync.vistas.length, 1);
      expect(r.sinEntregar, 3);
    });

    test('429 tasa_de_revision con Retry-After: se para y se guarda cuánto esperar', () async {
      await cuatroApuntes();
      enSync = (p) async => RespuestaFalsa.conCabeceras(429, const {
        'error': 'Demasiadas peticiones seguidas. Espera un minuto y vuelve a intentarlo.',
        'codigo': 'tasa_de_revision',
      }, const {'retry-after': '37'});

      final r = await servicio.entregar();

      expect(r.error, startsWith('Demasiadas peticiones seguidas'));
      expect(r.esperar, const Duration(seconds: 37));
      expect(sync.vistas.length, 1, reason: 'sin reintento ciego');
    });

    test('un 422 por la hora del aparato (más de 60 días) deja ese apunte pendiente con su literal', () async {
      final claves = await cuatroApuntes();
      var n = 0;
      enSync = (p) async => ++n == 1
          ? RespuestaFalsa(422, const {
              'error': 'El apunte: la hora del aparato tiene más de 60 días.',
              'codigo': 'entrega_no_admitida',
            })
          : _enRevision(p);

      final r = await servicio.entregar();

      expect(r.errores.single, contains('más de 60 días'));
      expect(await estadoDe(claves[0]), EstadoApunte.pendiente);
      expect(await estadoDe(claves[1]), EstadoApunte.enRevision);
    });

    test('la cola de otra persona no sale con esta sesión', () async {
      await cuatroApuntes();
      await base
          .into(base.preferencias)
          .insertOnConflictUpdate(
            PreferenciasCompanion.insert(clave: ClaveDePreferencia.dueno, valor: 'otra'),
          );

      final r = await servicio.entregar();

      expect(r.resultado, ResultadoDeEntrega.colaDeOtraPersona);
      expect(auth.vistas, isEmpty);
      expect(sync.vistas, isEmpty);
    });
  });

  group('preguntar qué pasó', () {
    Future<List<String>> tresEntregados() async {
      final claves = await cuatroApuntes();
      await servicio.entregar();
      auth.vistas.clear();
      sync.vistas.clear();
      return claves;
    }

    test('«Actualizar estados»: aplica lo que dijo el servidor, y NADA más', () async {
      final claves = await tresEntregados();
      enSync = (p) async => RespuestaFalsa(200, {
        'entregas': [
          {
            'clave': claves[0],
            'estado': 'aplicado',
            'decididoPorNombre': 'Marta Pérez',
            'decididoAt': '2026-10-09T13:10:00Z',
          },
          {
            'clave': claves[1],
            'estado': 'descartado',
            'decididoPorNombre': 'Marta Pérez',
            'decididoAt': '2026-10-09T13:11:00Z',
            'motivo': 'Se rehízo en la web',
          },
          {
            'clave': claves[2],
            'estado': 'rechazado',
            'motivo': 'Ese pedido ya va en otra ruta',
          },
          // Una que el aparato no tiene, y una que no se entiende: ni caen ni tumban.
          {'clave': 'ajena', 'estado': 'aplicado'},
        ],
      });

      final r = await servicio.actualizarEstados();

      expect(r.bien, isTrue);
      expect(r.cambiaron, 3);
      expect(sync.vistas.single.ruta, '/revision/mias');
      expect(sync.vistas.single.parametros['aparato'], _aparato);
      expect(_bearer(sync.vistas.single), 'Bearer tok-entrega');
      expect(auth.cuantas('POST', '/entrega'), 1);

      expect(await estadoDe(claves[0]), EstadoApunte.aplicado);
      final descartado = (await cola.porClave(claves[1]))!;
      expect(descartado.estado, EstadoApunte.descartadoPorRevisor);
      expect(descartado.motivoRevision, 'Se rehízo en la web');
      final rechazado = (await cola.porClave(claves[2]))!;
      expect(rechazado.estado, EstadoApunte.enRevision);
      expect(rechazado.motivoRevision, 'Ese pedido ya va en otra ruta');
    });

    test('`truncado` se DICE, y aplicado con descartados deja el aviso de «salió con menos»', () async {
      final claves = await tresEntregados();
      enSync = (p) async => RespuestaFalsa(200, {
        'entregas': [
          {
            'clave': claves[0],
            'estado': 'aplicado',
            'decididoPorNombre': 'Marta',
            'descartados': [
              {'pedidoId': 'p-9', 'operationNumber': 'X-2992', 'motivo': 'ya va en otra ruta'},
            ],
          },
        ],
        'truncado': true,
      });

      final r = await servicio.actualizarEstados();

      expect(r.truncado, isTrue);
      final a = (await cola.porClave(claves[0]))!;
      expect(a.estado, EstadoApunte.aplicado);
      expect(a.motivo, contains('X-2992'), reason: 'el mismo aviso que la subida normal');
      expect(
        (await cola.descartesSinLeer().first).map((x) => x.clave),
        [claves[0]],
      );
    });

    test('la pareja: sin `truncado` no se avisa', () async {
      await tresEntregados();
      enSync = (p) async => RespuestaFalsa(200, {'entregas': <Object?>[], 'truncado': false});
      expect((await servicio.actualizarEstados()).truncado, isFalse);
    });

    test('429 al preguntar: el literal y cuánto esperar, sin reintento', () async {
      await tresEntregados();
      enSync = (p) async => RespuestaFalsa.conCabeceras(429, const {
        'error': 'Demasiadas peticiones seguidas.',
        'codigo': 'tasa_de_revision',
      }, const {'retry-after': '12'});

      final r = await servicio.actualizarEstados();

      expect(r.bien, isFalse);
      expect(r.esperar, const Duration(seconds: 12));
      expect(sync.vistas.length, 1);
    });

    test('un estado que no entiende no tumba a los demás', () async {
      final claves = await tresEntregados();
      enSync = (p) async => RespuestaFalsa(200, {
        'entregas': [
          {'clave': claves[0], 'estado': 'inventado'},
          {'clave': claves[1], 'estado': 'aplicado', 'decididoPorNombre': 'Marta'},
        ],
      });

      final r = await servicio.actualizarEstados();

      expect(r.bien, isTrue);
      expect(await estadoDe(claves[0]), EstadoApunte.enRevision);
      expect(await estadoDe(claves[1]), EstadoApunte.aplicado);
    });

    test('en la WEB «actualizar estados» tampoco hace nada', () async {
      await tresEntregados();
      final web = montar(enAparato: false);

      final r = await web.actualizarEstados();

      expect(r.resultado, ResultadoDeEntrega.nadaQueEntregar);
      expect(auth.vistas, isEmpty);
      expect(sync.vistas, isEmpty);
    });

    test('sin nada en revisión NO hay ni una petición', () async {
      await cuatroApuntes();

      final r = await servicio.actualizarEstados();

      expect(r.resultado, ResultadoDeEntrega.nadaQueEntregar);
      expect(auth.vistas, isEmpty);
      expect(sync.vistas, isEmpty);
    });

    test('con permiso (el ciclo): consulta con la llamada normal y SOLO si hay algo', () async {
      var llamadas = 0;
      Future<Map<String, Object?>> pedir(String ruta, Map<String, Object?> params) async {
        llamadas++;
        return {'entregas': <Object?>[]};
      }

      expect(await servicio.consultarConSesion(pedir), 0);
      expect(llamadas, 0, reason: 'nada en revisión: ni una petición');

      await tresEntregados();
      await servicio.consultarConSesion(pedir);
      expect(llamadas, 1);
    });
  });

  group('el ciclo, con los proveedores de verdad', () {
    // El cableado: `cicloProvider` llama al servicio con la llamada de `sync`. Quitarlo
    // no rompe nada visible, así que lo ata esta prueba.
    ProviderContainer ciclo(
      Future<RespuestaFalsa?> Function(PeticionVista) responder,
    ) {
      final c = ProviderContainer.test(
        overrides: [
          trabajaSinConexionProvider.overrideWithValue(true),
          almacenSesionProvider.overrideWithValue(almacen),
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 10, 9, 8)),
          dioAuthProvider.overrideWithValue(
            Dio()
              ..httpClientAdapter = ServidorFalso(
                (p) async => RespuestaFalsa(200, {
                  'token': 'nuevo',
                  'refresh_token': 'r1',
                  'token_type': 'Bearer',
                  'expires_in': 900,
                  'refresh_expires_in': 2592000,
                }),
              ),
          ),
        ],
      );
      addTearDown(c.dispose);
      for (final cliente in [c.read(clienteApiProvider), c.read(clienteSyncProvider)]) {
        cliente.dio.httpClientAdapter = ServidorFalso(responder);
      }
      return c;
    }

    final vacia = RespuestaFalsa(200, const {
      'hasta': '2026-10-09T08:00:00Z',
      'completa': true,
      'truncado': false,
      'cambios': <String, Object?>{},
      'sucursales': <Object?>[],
    });

    Future<int> cuantasVecesPregunta(ProviderContainer c, {required bool conRevision}) async {
      if (conRevision) {
        final clave = await encolar('/routes/r-1/results');
        await cola.marcarEnRevision(clave, entrega: 'ent-1');
      }
      var mias = 0;
      c.read(clienteSyncProvider).dio.httpClientAdapter = ServidorFalso((p) async {
        if (p.ruta == '/revision/mias') {
          mias++;
          return RespuestaFalsa(200, const {'entregas': <Object?>[]});
        }
        return vacia;
      });
      final portero = c.read(porteroProvider);
      await portero.entro(sesion);
      // Entrar ya dispara un ciclo por su cuenta: se espera a que acabe y se cuenta
      // SOLO el que se pide aquí.
      for (var i = 0; i < 200 && (i < 40 || c.read(cicloProvider).enVuelo); i++) {
        await Future<void>.delayed(Duration.zero);
      }
      mias = 0;
      await c.read(cicloProvider).ahora(motivo: 'prueba');
      return mias;
    }

    test('con algo en revisión pregunta UNA vez por vuelta', () async {
      final c = ciclo((p) async => vacia);
      expect(await cuantasVecesPregunta(c, conRevision: true), 1);
    });

    test('la pareja: sin nada en revisión NO pregunta', () async {
      final c = ciclo((p) async => vacia);
      expect(await cuantasVecesPregunta(c, conRevision: false), 0);
    });
  });
}
