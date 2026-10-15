// DESCARTAR EL CAMBIO DE UNA ZONA SUELTA LA ZONA — 15/10/2026, auditoría de la 1.0.37.
//
// Lo que se ejecutó y salió mal: un aparato sin señal le pone a una zona que ya
// estaba arriba el punto AURORA (activo en su copia); al subir, el servidor dice
// 400 «dado de baja»; la persona pulsa «Descartar». La zona se quedaba con
// `nacio_aqui = 1` y `almacen_id = 'alm-aurora'`, la bajada del tablero decía
// «1 zona del tablero que no está en el servidor» PARA SIEMPRE y la cabecera
// seguía pintando «desde AURORA» con el servidor en nulo.
//
// Es el §4 del CLAUDE.md, «Una decisión de una persona se ESCRIBE», segunda mitad:
// «también hay que soltar lo que protegía esa fila». Se hacía para la zona que el
// apunte CREA y para la tarjeta que COLOCA; no para el PATCH que la cambia.
//
// Y en pareja: mientras ese PATCH está PENDIENTE o RECHAZADO SIN DECIDIR, la zona
// sigue protegida — ni la bajada la pisa ni el desatascador de huérfanos la vuelve
// a mandar como si nadie la nombrara (sería insistirle a un servidor que ya dijo
// que no, y el rechazo volvería a la bandeja con clave nueva: el 29/09/2026).

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/sincro/huerfanos.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';
import 'package:reparto/pantallas/tablero/datos/servicio.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import '../../pantallas/tablero/apoyo.dart';

const _elNo = '«AURORA» está dado de baja en Accesos';

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late RepositorioTablero aparato;
  late ServicioTablero servicio;

  setUp(() async {
    base = baseDePrueba();
    cola = ColaDeSalida(base);
    aparato = RepositorioTablero(base, cola);
    await sembrarSucursal(base);
    await sembrarAlmacen(base, id: 'alm-pv', nombre: 'PV-STGO');
    await sembrarAlmacen(
      base,
      id: 'alm-aurora',
      nombre: 'AURORA',
      lat: 20.0311,
      lng: -75.7902,
      principal: false,
    );
    // LA VERDAD DEL SERVIDOR: la zona existe y sale del principal (nulo).
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba/api'))
      ..httpClientAdapter = ServidorFalso(
        (_) async => RespuestaFalsa(200, const <String, Object?>{
          'columnas': [
            {'id': 'z1', 'nombre': 'Centro', 'posicion': 1, 'almacenId': null},
          ],
          'colocados': <Object?>[],
        }),
      );
    servicio = ServicioTablero(
      base,
      ClienteApi(dio: dio, esperas: const <Duration>[]),
      RegistroDeFrescura(base),
    );
    final primera = await servicio.descargar(sucursalStg);
    expect(
      primera.porQue,
      isNull,
      reason: 'la zona tiene que bajar del servidor',
    );
  });

  tearDown(() => base.close());

  Future<(String?, int)> zona() async {
    final f = await base
        .customSelect(
          "SELECT almacen_id, nacio_aqui FROM board_columns WHERE id = 'z1'",
        )
        .getSingle();
    return (f.read<String?>('almacen_id'), f.read<int>('nacio_aqui'));
  }

  /// El aparato sin señal le pone AURORA; devuelve la clave del PATCH.
  Future<String> ponerAuroraSinSenal() async {
    await aparato.elegirPuntoDeSalida('z1', 'alm-aurora');
    final apunte = (await cola.lote()).single;
    expect((apunte.metodo, apunte.ruta), ('PATCH', '/board/columns/z1'));
    expect(await zona(), ('alm-aurora', 1));
    return apunte.clave;
  }

  Future<void> rechazar(String clave) => cola.resolver(
    clave,
    const ResultadoApunte(estado: EstadoResultado.rechazado, motivo: _elNo),
  );

  test('el escenario entero: tras DESCARTAR el PATCH, la bajada vuelve a '
      'funcionar y la zona sale sin punto', () async {
    final clave = await ponerAuroraSinSenal();
    await rechazar(clave);
    await cola.descartar(clave);

    final bajada = await servicio.descargar(sucursalStg);
    expect(
      bajada.porQue,
      isNull,
      reason:
          'se descartó el único cambio de la zona y la bajada sigue negándose '
          '(«${bajada.porQue}»): nada suelta la zona y el tablero de este '
          'aparato no se actualiza nunca más',
    );
    expect(
      await zona(),
      (null, 0),
      reason:
          'tenía que quedar la verdad del servidor (sin punto): si no, la '
          'cabecera sigue diciendo «desde AURORA» y la ruta sale de otro sitio',
    );
    expect(await Huerfanos(base).mirar(), isEmpty);
  });

  test('en pareja: un PATCH PENDIENTE o RECHAZADO SIN DECIDIR sigue protegiendo '
      'la zona, y no se reencola por detrás', () async {
    final clave = await ponerAuroraSinSenal();

    // PENDIENTE: no se baja y la zona no se toca.
    var bajada = await servicio.descargar(sucursalStg);
    expect(
      bajada.porQue,
      isNotNull,
      reason: 'la bajada pisó un cambio sin subir',
    );
    expect(await zona(), ('alm-aurora', 1));
    expect(
      await Huerfanos(base).volverAEncolar(cola),
      0,
      reason:
          'el PATCH pendiente ya nombra a la zona: darla por huérfana manda '
          'además un POST que no pidió nadie',
    );

    // RECHAZADO, SIN DECIDIR: sigue protegida hasta que una persona decida.
    await rechazar(clave);
    bajada = await servicio.descargar(sucursalStg);
    expect(
      bajada.porQue,
      '1 zona del tablero que no está en el servidor',
      reason: 'un rechazo sin decidir no suelta la zona: la bajada la pisaría',
    );
    expect(await zona(), ('alm-aurora', 1));
    expect(
      await Huerfanos(base).volverAEncolar(cola),
      0,
      reason:
          'reencolar la zona con su AURORA es insistirle a un servidor que ya '
          'dijo que no: el rechazo volvería a la bandeja con clave nueva',
    );
    expect(await base.cuantosPendientes(), 0);
    expect(await base.cuantosRechazados(), 1);
  });

  test(
    'y si SUBE, también la suelta: la bajada siguiente ya no se niega',
    () async {
      final clave = await ponerAuroraSinSenal();
      await cola.resolver(
        clave,
        const ResultadoApunte(estado: EstadoResultado.aplicado, id: 'z1'),
      );
      expect(
        (await zona()).$2,
        0,
        reason: 'el servidor dijo que sí: la zona ya no tiene nada sin subir',
      );
    },
  );

  // Y LA OTRA MITAD DE LA PAREJA: descartar UN apunte de la zona no la suelta si
  // OTRO suyo sigue vivo. Aquí es la zona creada sin señal: su alta rechazada sin
  // decidir es lo único que la tiene; soltarla al descartar su punto deja que la
  // bajada borre una zona que sólo existe en este aparato.
  test(
    'descartar su PATCH NO suelta una zona cuya alta sigue sin decidir',
    () async {
      final nueva = await aparato.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Vista',
      );
      await aparato.elegirPuntoDeSalida(nueva, 'alm-aurora');
      final [alta, cambio] = await cola.lote();
      await rechazar(alta.clave);
      await rechazar(cambio.clave);

      await cola.descartar(cambio.clave);
      var bajada = await servicio.descargar(sucursalStg);
      expect(
        bajada.porQue,
        '1 zona del tablero que no está en el servidor',
        reason:
            'se soltó la zona con su alta todavía rechazada y sin decidir: la '
            'bajada la ha borrado',
      );
      expect(
        await base
            .customSelect(
              'SELECT 1 FROM board_columns WHERE id = ?1',
              variables: [Variable<String>(nueva)],
            )
            .get(),
        hasLength(1),
      );

      // Decidida también el alta, ya no queda nada que la proteja.
      await cola.descartar(alta.clave);
      bajada = await servicio.descargar(sucursalStg);
      expect(bajada.porQue, isNull);
    },
  );
}
