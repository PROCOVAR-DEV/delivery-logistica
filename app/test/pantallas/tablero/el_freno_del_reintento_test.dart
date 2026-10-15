import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart' show sucursalDeLaSesionProvider;
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

/// EL FRENO DEL REINTENTO: se vuelve a pedir la foto UNA VEZ, no para siempre.
///
/// `vuelve_a_pedir_la_foto_test.dart` cubre el caso bueno: la foto llega antes
/// que los pedidos, los pedidos llegan, y la foto se vuelve a pedir. Lo que no
/// cubría nadie es el **tope**, que es la otra mitad de lo mismo:
/// `_yaSeReintento` en `tablero/estado/proveedores.dart`. Quitando esa línea,
/// las 110 pruebas de `test/pantallas/tablero/` pasaban.
///
/// El caso que lo enciende no es raro: una tarjeta cuyo pedido **no llega
/// nunca** —archivado, o de otra sucursal—. Ahí `tarjetasSinPedido` sigue
/// siendo mayor que cero después de cada bajada, y `servicio.dart` termina toda
/// bajada con `EsquemaTablero.avisarDeCambio`, que es justo el aviso que
/// dispara el reintento. Sin freno, la bajada se rearma sola:
///
///     bajada → avisarDeCambio → escritura en las tablas del tablero →
///     _alCambiarLasTablas → faltaban pedidos → bajada → …
///
/// Medido: **1205 `GET /board` en 3 segundos** sin el freno, **2** con él. Es
/// un bucle caliente contra el servidor, no una ineficiencia.
///
/// PRUEBA NORMAL, NO `testWidgets`, y a propósito: aquí hace falta que pase
/// tiempo de verdad para contar peticiones. En un widget test el reloj lo manda
/// el `tester` y esto se colgaría en vez de fallar (`CLAUDE.md` §5). Mismo
/// motivo que su gemela `vuelve_a_pedir_la_foto_test.dart`.
void main() {
  late BaseLocal base;
  late ServidorFalso servidor;

  const zona = '01a0afc9-2be4-7bf6-9bed-e962c212d62b';
  // El pedido de la tarjeta, que NUNCA se siembra: es el archivado, o el de la
  // sucursal de al lado. Este aparato no lo va a tener jamás.
  const elQueNoLlegaNunca = '711fbf5a-a046-4d49-bd59-b30a8fa79fc2';

  setUp(() async {
    base = baseDePrueba();
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    servidor = ServidorFalso(
      (p) async => RespuestaFalsa(200, const {
        'columnas': <Object?>[
          {
            'id': zona,
            'branchId': sucursalStg,
            'nombre': 'Vista',
            'posicion': 1,
          },
        ],
        'colocados': <Object?>[
          {'pedidoId': elQueNoLlegaNunca, 'columnaId': zona, 'posicion': 1},
        ],
      }),
    );
  });

  tearDown(() => base.close());

  ProviderContainer montar() {
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba'))
      ..httpClientAdapter = servidor;
    return ProviderContainer.test(
      overrides: [
        baseProvider.overrideWith((ref) => base),
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
        sucursalDeLaSesionProvider.overrideWithValue(sucursalStg),
      ],
    );
  }

  test('una tarjeta cuyo pedido no llega nunca: se vuelve a pedir la foto UNA '
      'vez y se para, no 1205 veces', () async {
    final contenedor = montar();
    addTearDown(contenedor.dispose);

    // 1. Como abre la web: la foto primero. Su tarjeta se cae porque falta el
    //    pedido, y ese pedido no va a llegar.
    final tablero = await contenedor.read(tableroProvider.future);
    expect(tablero.columnas.single.pedidos, 0);

    // 2. Llega cualquier otro pedido por el ciclo. Eso es una escritura en
    //    `orders`, que es el aviso que dispara el reintento.
    await sembrarPedido(base, id: 'p-otro', operacion: 'SC06-0431');

    // 3. Se deja correr el tiempo de verdad. Si hay bucle, aquí se ve: son
    //    ~400 peticiones por segundo.
    await Future<void>.delayed(const Duration(seconds: 3));

    final fotos = servidor.cuantas('GET', '/board');
    expect(
      fotos,
      lessThanOrEqualTo(5),
      reason:
          'BUCLE DE BAJADAS: se pidieron $fotos veces `GET /board` en tres '
          'segundos y tenían que ser dos.\n'
          'La tarjeta apunta a un pedido que este aparato no va a tener '
          'nunca (archivado, o de otra sucursal), así que cada bajada vuelve '
          'a traerla sin pedido; y como `servicio.dart` termina toda bajada '
          'con `EsquemaTablero.avisarDeCambio`, esa misma bajada dispara el '
          'aviso que pide la siguiente.\n'
          'Lo único que corta la cadena es `_yaSeReintento = true` en '
          '`tablero/estado/proveedores.dart`. Sin esa línea son 1205 '
          'peticiones en tres segundos, contra el servidor y desde cada '
          'pantalla abierta.',
    );

    // Y la otra mitad, para que el tope no se «arregle» a base de no
    // reintentar nunca: la foto SÍ se volvió a pedir una vez.
    expect(
      fotos,
      greaterThanOrEqualTo(2),
      reason:
          'el freno no puede convertirse en «no se reintenta nunca»: eso es '
          'el «Vista (0)» que cubre `vuelve_a_pedir_la_foto_test.dart`',
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}
