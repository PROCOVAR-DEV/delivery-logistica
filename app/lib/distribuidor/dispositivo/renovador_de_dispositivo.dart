// RENOVAR EL ACCESO DE UN DISPOSITIVO (sin usuario ni contrasena).
//
// Es un `Renovador` por dentro del mismo motor: el interceptor (401), el ciclo y el
// arranque lo llaman igual. Lo que cambia es la puerta: `POST /api/d/renovar` con
// `{dispositivoId, secreto}`. En el `Sesion` guardado, `sub` es el dispositivoId y
// `refresh` es el SECRETO (que NO cambia al renovar: lo que se renueva es el `acceso`).
//
// El acceso dura meses: al arrancar solo se renueva si le quedan menos de 30 dias;
// si el servidor contesta 401 en una llamada normal, se renueva siempre.
// ignore_for_file: use_super_parameters (el padre guarda su reloj en privado)
import 'package:dio/dio.dart';
import 'package:synchronized/synchronized.dart';

import '../../nucleo/identidad/almacen_sesion.dart';
import '../../nucleo/identidad/renovador.dart';
import '../../nucleo/identidad/sesion.dart';
import '../../nucleo/red/fallos.dart';
import '../../nucleo/registro/registro.dart';
import '../../nucleo/reloj.dart';
import 'cliente_de_dispositivo.dart';

class RenovadorDeDispositivo extends Renovador {
  RenovadorDeDispositivo(
    ClienteDeDispositivo cliente,
    AlmacenDeSesion almacen, {
    Reloj reloj = relojDelAparato,
    void Function()? alDesvincular,
  }) : _alDesvincular = alDesvincular,
       _cliente = cliente,
       _almacen = almacen,
       _reloj = reloj,
       super(Dio(), almacen, reloj: reloj);

  static const margenDelArranque = Duration(days: 30);

  final void Function()? _alDesvincular;
  final ClienteDeDispositivo _cliente;
  final AlmacenDeSesion _almacen;
  final Reloj _reloj;
  final _candado = Lock();

  @override
  Future<Sesion> renovar(Sesion vista) => _candado.synchronized(() async {
    final actual = await _almacen.leer();
    if (actual == null) throw const SesionMuerta('no hay sesion guardada');
    // Otro ya renovo mientras esperaba el candado: se usa lo suyo.
    if (actual.token != vista.token) return actual;
    final pedidoA = _reloj();
    try {
      final r = await _cliente.renovar(
        dispositivoId: actual.sub,
        secreto: actual.refresh,
      );
      final nueva = sesionDeDispositivo(
        acceso: r.acceso,
        secreto: actual.refresh,
        dispositivoId: actual.sub,
        pedidoA: pedidoA,
      );
      if (!await _almacen.guardar(nueva)) {
        Registro.fallo('el acceso nuevo no quedo guardado');
      }
      return nueva;
    } on DispositivoDesvinculado {
      // La oficina lo desvinculo: la app se vacia (y borra el acceso ella misma).
      _alDesvincular?.call();
      rethrow;
    } on SesionMuerta {
      await _almacen.borrar();
      rethrow;
    }
  });

  @override
  Future<bool> renovarSiHaceFalta(Sesion vista) async {
    final queda = vista.leQueda(_reloj());
    if (queda != null && queda > margenDelArranque) return false;
    await renovar(vista);
    return true;
  }

  @override
  Future<Sesion> alArrancar(Sesion guardada) async {
    final queda = guardada.leQueda(_reloj());
    if (queda != null && queda > margenDelArranque) return guardada;
    return renovar(guardada);
  }
}

/// La sesion de un dispositivo. `sub` = dispositivoId (la base local es suya) y
/// `refresh` = el secreto.
Sesion sesionDeDispositivo({
  required String acceso,
  required String secreto,
  required String dispositivoId,
  DateTime? pedidoA,
}) => Sesion.deJson(<String, Object?>{
  'token': acceso,
  'refresh': secreto,
  'sub': dispositivoId,
  'roles': const ['DISTRIBUIDOR'],
  'rol': 'DISTRIBUIDOR',
  'nombre': 'Distribuidor',
}, pedidoA: pedidoA);
