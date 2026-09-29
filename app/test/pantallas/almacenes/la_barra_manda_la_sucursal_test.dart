// LA PANTALLA DE ALMACENES CONFIGURA LA SUCURSAL QUE DICE LA BARRA.
//
// Jose, 29/09/2026: «los almacenes tengo seleccionado santiago, por que razon me
// salio camaguey en la web».
//
// No era la API. `GET /api/almacenes` devuelve **las ocho** sucursales a quien ve
// las ocho, y a propósito: el aparato reemplaza su copia entera con lo que llega,
// así que servirle sólo la mirada lo dejaba sin el almacén de la siguiente y el
// Tablero salía en blanco acusando en falso (`api/internal/api/almacenes.go`,
// 26/09/2026).
//
// Era la pantalla: su desplegable arrancaba vacío y caía en «la primera de la
// lista», y la primera de la lista es la primera que devuelve Accesos —Camagüey—,
// no la de nadie. Ni un error, ni una pantalla en blanco: la sucursal equivocada
// con su nombre escrito arriba.
//
// Y no es cosmético. El domicilio se cobra por la distancia DESDE el almacén:
// editar ahí es mover el punto de cobro de otra provincia.
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/almacenes/datos/almacen_api.dart';
import 'package:reparto/pantallas/almacenes/estado/estado_almacenes.dart';

SucursalDeAccesos _s(String codigo, String nombre) =>
    SucursalDeAccesos(codigo: codigo, nombre: nombre, almacenes: const []);

/// El orden es el de Accesos: Camagüey primero. Es lo que hace que el fallo se
/// vea — con Santiago de primero, «la primera de la lista» acertaba por azar.
final _lasOcho = [
  _s('CAM', 'Camagüey'),
  _s('GR', 'Granma'),
  _s('GTO', 'Guantánamo'),
  _s('HAB', 'La Habana'),
  _s('HOL', 'Holguín'),
  _s('SS', 'Sancti Spíritus'),
  _s('STG', 'Santiago'),
  _s('TUN', 'Las Tunas'),
];

void main() {
  test('con Santiago en la barra se configura Santiago, no la primera', () {
    final elegida = cualSeConfigura(
      _lasOcho,
      elegidaEnLaPantalla: null,
      codigoDeLaBarra: 'STG',
    );
    expect(
      elegida?.codigo,
      'STG',
      reason: 'con Santiago arriba salió ${elegida?.nombre}: es el fallo del '
          '29/09/2026, y se cobra el domicilio desde ese punto',
    );
  });

  test('lo que se elige a mano en la pantalla manda sobre la barra', () {
    // Un Super Admin puede estar mirando Santiago y querer configurar Holguín
    // sin cambiar la barra. Eso tiene que seguir funcionando.
    final elegida = cualSeConfigura(
      _lasOcho,
      elegidaEnLaPantalla: 'HOL',
      codigoDeLaBarra: 'STG',
    );
    expect(elegida?.codigo, 'HOL');
  });

  test('con «Todas» arriba se enseña la primera, que es lo único que queda', () {
    // Aquí no hay respuesta correcta: la pantalla configura UNA sucursal cada
    // vez y la barra no ha nombrado ninguna. Se enseña la primera y el
    // desplegable queda a mano.
    final elegida = cualSeConfigura(
      _lasOcho,
      elegidaEnLaPantalla: null,
      codigoDeLaBarra: null,
    );
    expect(elegida?.codigo, 'CAM');
  });

  test('una sucursal que ya no está en la lista no deja la pantalla vacía', () {
    // Accesos puede dejar de devolver una sucursal, o la barra puede tener una
    // que Accesos no conoce. Lo que NO puede pasar es que la pantalla se quede
    // sin nada que configurar y parezca que no hay almacenes.
    final elegida = cualSeConfigura(
      _lasOcho,
      elegidaEnLaPantalla: 'NO-EXISTE',
      codigoDeLaBarra: 'TAMPOCO',
    );
    expect(elegida?.codigo, 'CAM');
  });

  test('sin sucursales no se inventa ninguna', () {
    expect(
      cualSeConfigura(
        const [],
        elegidaEnLaPantalla: 'STG',
        codigoDeLaBarra: 'STG',
      ),
      isNull,
    );
  });
}
