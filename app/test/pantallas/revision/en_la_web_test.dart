// LA BANDEJA EN LA WEB (Jose, 08/10/2026: «la bandeja del revisor tambien en la
// web»): el cliente de `sync` lleva el token de `/api/me` como Bearer explicito,
// no la cookie.
//
// Aqui se prueba el CABLEADO del proveedor (`clienteDeRevisionProvider`), que es
// donde se decide: que en la web monte un cliente con `bearerExplicito` y que en
// la APK y el escritorio use el `sync` de siempre. La mitad de bajo nivel —que con
// bearer explicito no hay `withCredentials`— esta en
// `test/nucleo/red/bearer_explicito_test.dart`.
//
// NADA de red: al cliente de verdad se le cambia el adaptador ANTES de usarlo
// (apunta a `reparto.procovar.cloud` y este codigo corre en el ordenador de Jose).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/pantallas/revision/estado/proveedores_revision.dart';

import 'apoyo_revision.dart';

/// Un portero que ya sabe quien es, como la web despues de `GET /api/me`.
class _PorteroConSesion extends Portero {
  _PorteroConSesion(super.ref, this._sesion);

  final Sesion _sesion;

  /// Cuantas veces se le dijo que la sesion murio.
  int vecesQueMurio = 0;

  @override
  Sesion? get sesion => _sesion;

  @override
  void murio() => vecesQueMurio++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const deApiMe = Sesion(token: 'jwt-de-api-me', refresh: '', sub: 'marta');

  ProviderContainer contenedor({
    required bool comoAparato,
    required SyncDeRevisionFalso servidor,
  }) {
    final c = ProviderContainer(
      overrides: [
        trabajaSinConexionProvider.overrideWithValue(comoAparato),
        // La web: la sesion es la cookie, el almacen no guarda nada.
        almacenSesionProvider.overrideWithValue(AlmacenEnMemoria()),
        porteroProvider.overrideWith((ref) => _PorteroConSesion(ref, deApiMe)),
        // El `sync` de siempre (APK y escritorio), ya con su servidor falso.
        clienteSyncProvider.overrideWithValue(clienteDeRevision(servidor)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('EN LA WEB el cliente manda el token de /api/me como Bearer', () async {
    final servidor = SyncDeRevisionFalso(const []);
    final c = contenedor(comoAparato: false, servidor: servidor);
    // Sin esto saldria a internet de verdad.
    c.read(clienteDeRevisionProvider).dio.httpClientAdapter = servidor;

    await c.read(repositorioRevisionProvider).bandeja();

    final salida = servidor.pedidas.single;
    expect(salida.ruta, '/sync/revision');
    expect(salida.cabeceras['Authorization'], 'Bearer jwt-de-api-me');
    expect(salida.extra['withCredentials'], isNot(true));
  });

  test('un 401 de sync en la web se DICE, pero no echa a nadie a Accesos '
      '(seria el bucle del 22/09/2026)', () async {
    final servidor = SyncDeRevisionFalso(const [])..contestaTodoCon = 401;
    final c = contenedor(comoAparato: false, servidor: servidor);
    c.read(clienteDeRevisionProvider).dio.httpClientAdapter = servidor;

    await expectLater(
      c.read(repositorioRevisionProvider).bandeja(),
      throwsA(isA<SesionMuerta>()),
    );

    expect((c.read(porteroProvider) as _PorteroConSesion).vecesQueMurio, 0);
  });

  test('EN PAREJA: en la APK y el escritorio usa el sync de siempre, con el '
      'token del aparato', () async {
    final servidor = SyncDeRevisionFalso(const []);
    final c = contenedor(comoAparato: true, servidor: servidor);

    await c.read(repositorioRevisionProvider).bandeja();

    expect(
      servidor.pedidas.single.cabeceras['Authorization'],
      'Bearer ${revisora.token}',
    );
  });
}
