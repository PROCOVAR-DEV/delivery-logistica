import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
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

/// «VISTA (0)» EN LA WEB CON SEIS TARJETAS BIEN PUESTAS EN EL SERVIDOR.
///
/// La carrera: la web abre con la base vacía, el Tablero pide `/board` nada más
/// pintarse y los pedidos llegan después, por el ciclo, que es otro camino. Una
/// colocación necesita su pedido (`order_id REFERENCES orders(id)`), así que las
/// tarjetas llegan primero y se caen todas. Luego llegan los pedidos y la foto
/// **ya no se vuelve a pedir**: está guardada para no bajar dos veces por
/// sucursal. La zona se queda a cero con sus pedidos en «Sin colocar».
///
/// La salida es volver a pedirla en cuanto los pedidos llegan — y **eso no lo
/// sujetaba nadie**. El auditor puso `_faltabanPedidos = false` a mano y las 853
/// pruebas de la suite siguieron verdes: `tarjetas_antes_que_pedidos_test.dart`
/// cubre el servicio (que devuelve el número), no la reacción del proveedor.
///
/// Esta prueba cubre la reacción, y en el orden de la vida real: primero la
/// foto con la base sin pedidos, después los pedidos.
void main() {
  late BaseLocal base;
  late ServidorFalso servidor;

  const zona = '01a0afc9-2be4-7bf6-9bed-e962c212d62b';
  const pedido = '711fbf5a-a046-4d49-bd59-b30a8fa79fc2';

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
          {'pedidoId': pedido, 'columnaId': zona, 'posicion': 1},
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

  // PRUEBA NORMAL, NO `testWidgets`. En un widget test el tiempo lo manda el
  // `tester` y no avanza solo, así que esperar aquí a un stream de Drift la
  // cuelga en vez de fallar — está avisado en el `CLAUDE.md` §5 y caí igual.
  test(
    'la foto llega antes que los pedidos: cuando llegan, se vuelve a pedir y '
    'la zona recupera su tarjeta',
    () async {
      final contenedor = montar();
      addTearDown(contenedor.dispose);

      // 1. Como abre la web: la foto primero, sin pedidos en la base.
      var tablero = await contenedor.read(tableroProvider.future);
      expect(tablero.columnas.single.nombre, 'Vista');
      expect(
        tablero.columnas.single.pedidos,
        0,
        reason: 'la tarjeta no se puede poner todavía: falta su pedido',
      );
      final fotosAlPrincipio = servidor.cuantas('GET', '/board');

      // 2. Llegan los pedidos por el ciclo, que es el otro camino. Nadie
      //    recarga y nadie cambia de sucursal.
      await base
          .into(base.orders)
          .insert(
            OrdersCompanion.insert(
              id: pedido,
              customerName: 'TCP ROLANDO',
              address: 'avenida del puerto y via blanca',
              branchId: const Value(sucursalStg),
              endLat: const Value(almacenLat + 0.01),
              endLng: const Value(almacenLng),
            ),
          );

      // El aviso de Drift y la bajada que dispara son asíncronos.
      for (
        var i = 0;
        i < 50 && servidor.cuantas('GET', '/board') == fotosAlPrincipio;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }

      expect(
        servidor.cuantas('GET', '/board'),
        greaterThan(fotosAlPrincipio),
        reason:
            'sin esto la zona se queda a cero para siempre: los pedidos ya '
            'están, pero nadie vuelve a preguntar por las tarjetas',
      );

      // 3. Y la tarjeta acaba en su sitio.
      tablero = await contenedor.read(tableroProvider.future);
      expect(
        tablero.columnas.single.pedidos,
        1,
        reason: 'es el «Vista (0)» que vio Jose con 6 tarjetas en el servidor',
      );
    },
  );
}
