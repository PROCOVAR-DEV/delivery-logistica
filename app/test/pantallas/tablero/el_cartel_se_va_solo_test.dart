import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart' show sucursalDeLaSesionProvider;
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

/// «NO SE ACTUALIZA: HAY 1 CAMBIO SIN SUBIR» — Y YA ESTABA SUBIDO.
///
/// El tablero se niega a bajar mientras quede algo sin subir, para no pisarlo.
/// Eso está bien y no se toca. Lo que estaba mal es que el motivo se escribía al
/// intentar la bajada y **no lo recalculaba nadie**: el apunte subía cuatro
/// segundos después y el cartel se quedaba puesto, diciendo algo que había
/// dejado de ser verdad, y el tablero sin bajar hasta que alguien pulsara
/// refrescar o cambiara de sucursal.
///
/// Jose, 17/09/2026, con el teléfono delante: «ahí en el móvil me sale como que
/// no se ha subido aún, ¿por qué razón me sale eso si ya está?».
///
/// Es la misma familia que el aviso de lo rechazado: un valor calculado en un
/// momento que no se entera de lo que pasa después. Por eso la prueba va en el
/// orden de la vida real — primero la negativa, DESPUÉS la subida.
void main() {
  late BaseLocal base;
  late ServidorFalso servidor;

  setUp(() async {
    base = baseDePrueba();
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarPedido(base, id: 'p-1', aGrados: 0.01);
    servidor = ServidorFalso(
      (p) async => RespuestaFalsa(200, const {
        'columnas': <Object?>[],
        'colocados': <Object?>[],
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

  test('el cartel de «hay un cambio sin subir» se va SOLO cuando ese cambio sube', () async {
    // 1. Hay trabajo sin subir, así que el tablero se niega a bajar y lo dice.
    final cola = ColaDeSalida(base);
    final clave = await cola.encolar(
      metodo: 'PUT',
      ruta: '/board/placements/p-1',
      cuerpo: const {'columnaId': 'c-1', 'posicion': 1},
    );

    final contenedor = montar();
    addTearDown(contenedor.dispose);
    await contenedor.read(tableroProvider.future);
    final mando = contenedor.read(tableroProvider.notifier);

    expect(
      mando.porQueNoSeRefresca,
      isNotNull,
      reason:
          'con trabajo sin subir el tablero NO baja, para no pisarlo. Eso '
          'está bien y no se toca',
    );

    // 2. El apunte sube. Nadie pulsa nada, nadie cambia de sucursal: es el
    //    ciclo, por detrás, cuatro segundos después del gesto.
    await cola.resolver(
      clave,
      const ResultadoApunte(estado: EstadoResultado.aplicado),
    );

    for (var i = 0; i < 50 && mando.porQueNoSeRefresca != null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }

    // 3. Y el cartel se va solo.
    expect(
      mando.porQueNoSeRefresca,
      isNull,
      reason:
          'ya no queda nada sin subir: dejar el cartel puesto es decirle a '
          'quien está delante algo que dejó de ser verdad, y encima deja el '
          'tablero sin bajar hasta que pulse refrescar',
    );
  });

  test('mientras siga sin subir, el cartel se queda: la guarda no se ha '
      'aflojado', () async {
    // La otra mitad. Quitar el cartel en cuanto moleste sería peor que el
    // fallo: la bajada pisaría trabajo que no está arriba.
    await ColaDeSalida(base).encolar(
      metodo: 'PUT',
      ruta: '/board/placements/p-1',
      cuerpo: const {'columnaId': 'c-1', 'posicion': 1},
    );

    final contenedor = montar();
    addTearDown(contenedor.dispose);
    await contenedor.read(tableroProvider.future);
    final mando = contenedor.read(tableroProvider.notifier);

    // Se escribe algo en una tabla que el tablero vigila, para despertar al
    // oyente sin que el apunte se haya resuelto.
    await sembrarPedido(base, id: 'p-2', aGrados: 0.02);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(
      mando.porQueNoSeRefresca,
      isNotNull,
      reason:
          'sigue habiendo trabajo sin subir: la foto del servidor lo pisaría',
    );
  });
}
