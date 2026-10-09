import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';

/// El uuid de la sucursal de las entregas de prueba. `sync` NO manda su nombre.
const sucursalDePrueba = '5d6e7f80-1111-4222-8333-444455556666';

/// Quien revisa en las pruebas: una ADMINISTRADORA. Su `sub` es `marta`.
const revisora = Sesion(
  token: 'tok-marta',
  refresh: 'r0',
  sub: 'marta',
  nombre: 'Marta Pérez',
  rol: 'ADMINISTRADOR',
  roles: ['ADMINISTRADOR'],
  sucursalId: 'CAM',
);

Sesion conRol(String rol, {String sub = 'marta'}) => Sesion(
  token: 'tok-$sub',
  refresh: 'r0',
  sub: sub,
  nombre: 'Marta Pérez',
  rol: rol,
  roles: [rol],
  sucursalId: 'CAM',
);

/// El cuerpo de un apunte, **con espacios y orden raros a proposito**: lo que el
/// revisor ve tiene que ser el texto exacto que llego, no uno reformateado.
const cuerpoExacto =
    '{"results":  [{"orderId":"o-1","resultado":"entregado"}],'
    ' "nota":"dejado en porteria"}';

Map<String, Object?> apunteJson({
  required String clave,
  int orden = 1,
  String metodo = 'POST',
  String ruta = '/api/routes/r-1/results',
  String? cuerpo = cuerpoExacto,
  String estado = 'en_revision',
  String? motivo,
  String? decididoPorNombre,
  bool interrumpido = false,
  String hechoAt = '2026-10-08T14:32:00Z',
}) => <String, Object?>{
  'aparato': 'ap-1',
  'clave': clave,
  'orden': orden,
  'metodo': metodo,
  'ruta': ruta,
  'cuerpo': cuerpo,
  'hechoAt': hechoAt,
  'estado': estado,
  'motivo': motivo,
  'decididoPorNombre': decididoPorNombre,
  if (interrumpido) 'interrumpido': true,
};

Map<String, Object?> entregaJson({
  String id = 'e-1',
  String persona = 'yasmani',
  String personaNombre = 'Yasmani Cruz',
  String sucursal = sucursalDePrueba,
  List<Map<String, Object?>> apuntes = const [],
}) => <String, Object?>{
  'id': id,
  'aparato': 'ap-1',
  'aparatoNombre': 'Teléfono de Yasmani',
  'persona': persona,
  'personaNombre': personaNombre,
  'sucursal': sucursal,
  'entregadaAt': '2026-10-08T20:10:00Z',
  'apuntes': apuntes,
};

/// Una petición que llegó a `sync`.
class Pedida {
  Pedida(this.metodo, this.ruta, this.cuerpo, this.cabeceras, this.extra);

  final String metodo;
  final String ruta;
  final Object? cuerpo;
  final Map<String, Object?> cabeceras;
  final Map<String, Object?> extra;

  @override
  String toString() => '$metodo $ruta';
}

/// El `sync` del REVISOR, de mentira y **con estado**: aplicar, descartar y
/// releer dan lo que daria el servidor de verdad (un apunte aplicado sale
/// aplicado en la siguiente lectura).
///
/// Las rutas son las de `docs/bandeja-de-revision.md` B.2, con el prefijo `/sync`
/// que pone `Entorno.syncUrl`: si alguien cambia una direccion en el
/// repositorio, esta prueba la ve.
class SyncDeRevisionFalso implements HttpClientAdapter {
  SyncDeRevisionFalso(List<Map<String, Object?>> entregas)
    : entregas = [for (final e in entregas) Map<String, Object?>.of(e)];

  final List<Map<String, Object?>> entregas;
  final List<Pedida> pedidas = <Pedida>[];

  /// `clave` de apunte → literal con el que el REPARTO lo rechaza al aplicar. Es un
  /// 4xx del reparto: `sync` lo contesta como 200 con `estado: rechazado`.
  final Map<String, String> rechazaConElLiteral = <String, String>{};

  /// `clave` de apunte → el reparto NO contesta (5xx o red): `sync` contesta 502
  /// `reparto_no_disponible` y el apunte VUELVE a `en_revision`.
  final Set<String> repartoCaido = <String>{};

  /// `clave` de apunte → se aplico en el reparto pero la base no lo anoto: 500
  /// `no_se_pudo_anotar`.
  final Set<String> noSePudoAnotar = <String>{};

  /// Si se pone, la lista sale con `truncado: true`.
  bool listaTruncada = false;

  /// Mientras haya una puerta, las peticiones que MUTAN esperan a que se abra:
  /// es como se ve la pantalla "mientras vuela" la orden.
  Completer<void>? puerta;

  /// Sin red: la peticion ni sale.
  bool sinRed = false;

  /// Si se pone, TODA peticion se contesta con este codigo y un `mensaje`.
  int? contestaTodoCon;

  /// Si se pone, el servidor NO deja descartar y lo dice con este literal (403).
  String? noDejaDescartar;

  int cuantas(String metodo, String contiene) => pedidas
      .where((p) => p.metodo == metodo && p.ruta.contains(contiene))
      .length;

  Iterable<Pedida> get quePidieron => pedidas;

  List<Map<String, Object?>> _apuntesDe(Map<String, Object?> e) =>
      (e['apuntes']! as List<Object?>).cast<Map<String, Object?>>();

  int _contar(Map<String, Object?> e, String estado) =>
      _apuntesDe(e).where((a) => a['estado'] == estado).length;

  Map<String, Object?> _resumen(Map<String, Object?> e) => <String, Object?>{
    for (final k in e.keys)
      if (k != 'apuntes') k: e[k],
    'enRevision': _contar(e, 'en_revision'),
    'aplicando': _contar(e, 'aplicando'),
    'rechazados': _contar(e, 'rechazado'),
    'aplicados': _contar(e, 'aplicado'),
    'descartados': _contar(e, 'descartado'),
  };

  ResponseBody _json(Object cuerpo, [int codigo = 200]) =>
      ResponseBody.fromString(
        jsonEncode(cuerpo),
        codigo,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  Map<String, Object?>? _apunte(String aparato, String clave) {
    for (final e in entregas) {
      for (final a in _apuntesDe(e)) {
        if (a['aparato'] == aparato && a['clave'] == clave) return a;
      }
    }
    return null;
  }

  /// Aplica uno: devuelve el resultado, y deja el estado como lo dejaria el
  /// servidor. `null` = una CAIDA (el servidor contesta 502/500, no 200).
  Map<String, Object?>? _aplicar(Map<String, Object?> a) {
    final clave = a['clave'];
    if (repartoCaido.contains(clave)) {
      a['estado'] = 'en_revision'; // vuelve a en_revision, NO a rechazado
      return null;
    }
    final literal = rechazaConElLiteral[clave];
    if (literal != null) {
      a['estado'] = 'rechazado';
      a['motivo'] = literal;
      return <String, Object?>{
        'clave': clave,
        'estado': 'rechazado',
        'motivo': literal,
      };
    }
    a['estado'] = 'aplicado';
    a.remove('interrumpido');
    a['decididoPorNombre'] = 'Marta Pérez';
    a['decididoAt'] = '2026-10-09T09:10:00Z';
    return <String, Object?>{'clave': clave, 'estado': 'aplicado'};
  }

  ResponseBody _error(int codigo, String codigoDeError, String frase) =>
      _json(<String, Object?>{'error': frase, 'codigo': codigoDeError}, codigo);

  @override
  Future<ResponseBody> fetch(
    RequestOptions opciones,
    Stream<Uint8List>? cuerpoStream,
    Future<void>? cancelar,
  ) async {
    pedidas.add(
      Pedida(
        opciones.method,
        opciones.uri.path,
        opciones.data,
        Map<String, Object?>.from(opciones.headers),
        Map<String, Object?>.from(opciones.extra),
      ),
    );
    if (sinRed) {
      throw DioException.connectionError(
        requestOptions: opciones,
        reason: 'sin red (sync de revision falso)',
      );
    }
    if (contestaTodoCon != null) {
      return _json(<String, Object?>{
        'error': 'no',
        'codigo': 'x',
      }, contestaTodoCon!);
    }
    final partes = opciones.uri.pathSegments; // [sync, revision, …]
    final resto = partes.skip(2).toList();

    if (opciones.method == 'GET') {
      if (resto.isEmpty) {
        return _json(<String, Object?>{
          'entregas': [for (final e in entregas) _resumen(e)],
          'truncado': listaTruncada,
        });
      }
      final e = entregas.firstWhere((e) => e['id'] == resto.first);
      return _json(<String, Object?>{
        'entrega': _resumen(e),
        'apuntes': _apuntesDe(e),
      });
    }

    if (puerta != null) await puerta!.future;

    // POST /sync/revision/{entrega}/aplicar: EN ORDEN y SE DETIENE en el primer
    // apunte que no queda aplicado. Salta aplicado/descartado.
    if (resto.length == 2 && resto[1] == 'aplicar') {
      final e = entregas.firstWhere((e) => e['id'] == resto.first);
      final resultados = <Map<String, Object?>>[];
      final pendientes = _apuntesDe(e)
          .where(
            (a) => a['estado'] == 'en_revision' || a['estado'] == 'rechazado',
          )
          .toList();
      for (var i = 0; i < pendientes.length; i++) {
        final a = pendientes[i];
        final r = _aplicar(a);
        if (r != null) resultados.add(r);
        if (r == null || r['estado'] != 'aplicado') {
          return _json(<String, Object?>{
            'resultados': resultados,
            'detenido': true,
            'detenidoEn': a['clave'],
            'detenidoPorque': r?['motivo'] ?? 'El reparto no contestó.',
            'sinProcesar': pendientes.length - i - 1,
          });
        }
      }
      return _json(<String, Object?>{'resultados': resultados});
    }

    // POST /sync/revision/{aparato}/{clave}/aplicar|descartar
    final a = _apunte(resto[0], resto[1])!;
    if (resto[2] == 'aplicar') {
      final reintento =
          (opciones.data as Map?)?['reintentarInterrumpido'] == true;
      if (a['estado'] == 'aplicando' && !reintento) {
        return _error(
          409,
          'ya_se_esta_aplicando',
          'Lo está aplicando Marta Pérez desde las 8:50.',
        );
      }
      if (a['estado'] == 'aplicado' || a['estado'] == 'descartado') {
        return _error(409, 'ya_decidido', 'Ese apunte ya está decidido.');
      }
      if (noSePudoAnotar.contains(a['clave'])) {
        a['estado'] = 'aplicando';
        return _error(
          500,
          'no_se_pudo_anotar',
          'Se aplicó en el reparto pero no se pudo anotar.',
        );
      }
      final r = _aplicar(a);
      if (r == null) {
        return _error(
          502,
          'reparto_no_disponible',
          'El reparto no está disponible.',
        );
      }
      return _json(<String, Object?>{
        'resultados': [r],
      });
    }

    if (noDejaDescartar != null) {
      return _json(<String, Object?>{
        'error': noDejaDescartar!,
        'codigo': 'no_revisa',
      }, 403);
    }
    final motivo = ((opciones.data as Map?)?['motivo'] as String?) ?? '';
    if (motivo.trim().length < 5) {
      return _error(
        422,
        'motivo_obligatorio',
        'Descartar necesita un motivo escrito de al menos 5 caracteres.',
      );
    }
    a['estado'] = 'descartado';
    a['motivo'] = motivo;
    a['decididoPorNombre'] = 'Marta Pérez';
    a['decididoAt'] = '2026-10-09T09:12:00Z';
    return _json(<String, Object?>{
      'resultados': [
        {'clave': a['clave'], 'estado': 'descartado', 'motivo': motivo},
      ],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Un `ClienteApi` de `sync` enchufado al falso. Base `…/sync`, igual que
/// `Entorno.syncUrl`. **Sin esperas**: lo que se prueba no es el reloj.
ClienteApi clienteDeRevision(SyncDeRevisionFalso servidor) {
  final almacen = AlmacenEnMemoria(revisora);
  final auth = Dio(BaseOptions(baseUrl: 'https://auth.test'))
    ..httpClientAdapter = servidor;
  final cliente = ClienteApi.montar(
    baseUrl: 'https://sync.test/sync',
    almacen: almacen,
    renovador: Renovador(auth, almacen),
    esperar: (_) async {},
  );
  cliente.dio.httpClientAdapter = servidor;
  return cliente;
}
