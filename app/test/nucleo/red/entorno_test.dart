import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/red/entorno.dart';
import 'package:reparto/pantallas/acceso/vista/pantalla_sin_permiso.dart';

/// `--dart-define=AUTH_URL=` explícitamente VACÍO no usa el `defaultValue`: da `''`. Y
/// «el inicio de Accesos» sería `/`, o sea la propia Reparto: la pantalla de «no tienes
/// permiso» de la web se mandaría a sí misma cada 3 s, para siempre.
void main() {
  test('un AUTH_URL vacío (o en blanco) cae en el de producción', () {
    expect(Entorno.authUrlDe(''), 'https://auth.procovar.cloud');
    expect(Entorno.authUrlDe('   '), 'https://auth.procovar.cloud');
  });

  test('PAREJA: un AUTH_URL puesto a mano se respeta tal cual', () {
    expect(Entorno.authUrlDe('http://127.0.0.1:3500'), 'http://127.0.0.1:3500');
  });

  test('sin define, el inicio de Accesos es el dominio de Accesos + «/», '
      'nunca «/»', () {
    expect(inicioDeAccesos, 'https://auth.procovar.cloud/');
    expect(inicioDeAccesos, isNot('/'));
  });
}
