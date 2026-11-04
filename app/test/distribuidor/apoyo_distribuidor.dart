// Los falsos de «Reparto Distribuidor». Nada de esto toca el telefono ni la red.
import 'package:reparto/distribuidor/gps/puntos_locales.dart';
import 'package:reparto/distribuidor/gps/servicio_de_ubicacion.dart';
import 'package:reparto/pantallas/rutas/datos/abrir_y_compartir.dart';

/// Un GPS de mentira: guarda si esta encendido y deja empujar posiciones a mano.
class UbicacionFalsa implements ServicioDeUbicacion {
  UbicacionFalsa({this.concede = PermisoDeUbicacion.concedido, this.posicion});

  PermisoDeUbicacion concede;
  Posicion? posicion;
  int arranques = 0;
  int paradas = 0;
  int permisosPedidos = 0;
  void Function(Posicion)? alLlegar;

  bool get encendido => alLlegar != null;

  @override
  Future<PermisoDeUbicacion> permiso() async => concede;

  @override
  Future<PermisoDeUbicacion> pedirPermiso() async {
    permisosPedidos++;
    return concede;
  }

  @override
  Future<void> empezar(void Function(Posicion) alLlegar) async {
    arranques++;
    this.alLlegar = alLlegar;
  }

  @override
  Future<void> parar() async {
    paradas++;
    alLlegar = null;
  }

  @override
  Future<Posicion?> posicionAhora() async => posicion;
}

Posicion posicionEn(DateTime hora, {double lat = 21.4, double lng = -77.9}) =>
    Posicion(
      lat: lat,
      lng: lng,
      precision: 5,
      velocidad: 3,
      rumbo: 90,
      hora: hora,
    );

/// `AbrirYCompartir` que solo apunta lo que se le entrego.
class AparatoFalso implements AbrirYCompartir {
  final List<Uri> abiertos = [];
  bool puede = true;

  @override
  Future<bool> abrir(Uri destino) async {
    abiertos.add(destino);
    return puede;
  }

  @override
  Future<bool> compartir({required String texto, String? asunto}) async => true;

  @override
  Future<bool> copiar(String texto) async => true;
}
