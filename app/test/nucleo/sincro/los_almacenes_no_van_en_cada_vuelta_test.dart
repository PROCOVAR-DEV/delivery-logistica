// LOS ALMACENES NO SE PIDEN EN CADA VUELTA. ERAN EL 82 % DEL GASTO EN REPOSO.
//
// Medido el 29/09/2026 en el teléfono de Jose, con la aplicación abierta y sin
// tocar nada, leyendo el registro de la api:
//
//     GET /api/sync/cambios    584 bytes   <- las OCHO colecciones, en vacío
//     GET /api/almacenes     2.671 bytes   <- en CADA vuelta, cambien o no
//
// O sea 3.255 bytes por ciclo sin que haya cambiado nada, y **2.671 de ellos son
// los almacenes**, que son ocho filas que no se mueven casi nunca. Con la
// conexión de allá y un ciclo cada pocos minutos, eso es más de un mega por hora
// y por aparato para traer lo mismo una y otra vez.
//
// Jose lo vio antes que nadie: «en el móvil cada 1 min me hace la cosa de
// sincronización, ¿por qué razón si no ha cambiado nada?».
//
// # Las tres condiciones, y por qué hacen falta las tres
//
//  1. **La primera vez** — sin almacén no hay desde dónde medir, o sea que no hay
//     Tablero. Eso no puede esperar a ningún plazo.
//  2. **Cuando llega su aviso** — quien los cambia desde el reparto tiene que
//     verlos al momento, no dentro de una hora.
//  3. **Cada hora** — y ésta es la que no se puede quitar: **los almacenes viven
//     en Accesos**, y un almacén creado o movido allí NO publica ningún aviso del
//     reparto. Sin ese suelo no llegaría nunca a un aparato que ya tiene los
//     suyos.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/sincro/bajada.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

void main() {
  late BaseLocal base;
  late DateTime ahora;

  setUp(() {
    base = baseDePrueba();
    ahora = DateTime(2026, 9, 29, 15, 0);
  });

  tearDown(() => base.close());

  var pedidas = 0;

  Bajada montar() {
    pedidas = 0;
    return Bajada(
      cliente: clienteFalso((p) async {
        if (!p.ruta.endsWith('/almacenes')) return null;
        pedidas++;
        return RespuestaFalsa(200, const <String, Object?>{
          'sucursales': <Object?>[
            <String, Object?>{
              'codigo': 'STG',
              'almacenes': <Object?>[
                <String, Object?>{
                  'id': 'alm-1',
                  'nombre': 'PV-STGO',
                  'latitud': 20.02,
                  'longitud': -75.82,
                  'principal': true,
                  'activo': true,
                },
              ],
            },
          ],
        });
      }),
      base: base,
      frescura: RegistroDeFrescura(base, reloj: () => ahora),
      reloj: () => ahora,
    );
  }

  int pedidasDeAlmacenes() => pedidas;

  test('la primera vez SÍ se piden: sin almacén no hay Tablero', () async {
    final bajada = montar();

    await bajada.almacenes();

    expect(
      pedidasDeAlmacenes(),
      1,
      reason:
          'la copia está vacía y no se pidieron. Sin almacén no hay desde dónde '
          'medir, o sea que el Tablero no abre',
    );
  });

  test('y a los dos minutos NO se vuelven a pedir', () async {
    final bajada = montar();
    await bajada.almacenes();
    final tras1a = pedidasDeAlmacenes();

    ahora = ahora.add(const Duration(minutes: 2));
    await bajada.almacenes();

    expect(
      pedidasDeAlmacenes(),
      tras1a,
      reason:
          'se volvieron a pedir a los dos minutos. Son 2.671 bytes por vuelta '
          'para traer ocho filas iguales, por la conexión de allá: más de un '
          'mega por hora y por aparato',
    );
  });

  test('pero con su aviso se piden al momento, sin esperar el plazo', () async {
    final bajada = montar();
    await bajada.almacenes();
    final tras1a = pedidasDeAlmacenes();

    ahora = ahora.add(const Duration(seconds: 30));
    await bajada.almacenes(forzar: true);

    expect(
      pedidasDeAlmacenes(),
      greaterThan(tras1a),
      reason:
          'llegó el aviso de almacenes y no se pidieron. Quien acaba de mover '
          'un almacén desde el reparto tendría que esperarse una hora a verlo',
    );
  });

  // LA CONDICIÓN QUE NO SE PUEDE QUITAR.
  test('y pasada la hora se piden solos, aunque nadie avise', () async {
    final bajada = montar();
    await bajada.almacenes();
    final tras1a = pedidasDeAlmacenes();

    ahora = ahora.add(Bajada.cadaCuantoLosAlmacenes + const Duration(minutes: 1));
    await bajada.almacenes();

    expect(
      pedidasDeAlmacenes(),
      greaterThan(tras1a),
      reason:
          'pasada la hora no se pidieron. Los almacenes viven en ACCESOS: uno '
          'creado allí no publica ningún aviso del reparto, así que sin este '
          'plazo no llegaría nunca a un aparato que ya tiene los suyos',
    );
  });
}
