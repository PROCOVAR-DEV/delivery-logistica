// «ESTE TELEFONO FUE DESVINCULADO DE SU VEHICULO»: la oficina lo desvinculo desde
// Reparto y el servidor contesta 403 `dispositivo_desvinculado` a cualquier llamada.
// La app se VACIA: rutas, paradas, marcas, historial, puntos de GPS, cola, vinculo
// guardado y accesos. Se CONSERVA solo la identidad del telefono (id de dispositivo y
// secreto): el servidor guarda su historia con ese id y el telefono puede vincularse a
// otro vehiculo despues con un enlace nuevo.
//
// Lo que estuviera sin enviar se cuenta (UNA vez, en el mensaje) porque el servidor ya
// no lo acepta.
import 'dart:convert';

import '../../nucleo/base/base.dart';
import '../../nucleo/identidad/almacen_sesion.dart';
import '../../nucleo/registro/registro.dart';

const claveDelSecretoDelTelefono = 'secretoDelDispositivo';

const textoDesvinculado =
    'Este teléfono fue desvinculado de su vehículo. Pide a tu logístico un enlace nuevo.';

/// Lo que se perdio por no estar enviado.
class LoDescartado {
  const LoDescartado({this.marcas = 0, this.otrosGestos = 0, this.puntos = 0});

  final int marcas;
  final int otrosGestos;
  final int puntos;

  bool get hayAlgo => marcas + otrosGestos + puntos > 0;

  String get frase {
    final partes = [
      if (marcas > 0) '$marcas ${marcas == 1 ? 'marca' : 'marcas'}',
      if (otrosGestos > 0)
        '$otrosGestos ${otrosGestos == 1 ? 'cambio de ruta' : 'cambios de ruta'}',
      if (puntos > 0) '$puntos ${puntos == 1 ? 'punto' : 'puntos'} de GPS',
    ];
    return partes.isEmpty
        ? ''
        : ' Se descartaron ${partes.join(', ')} sin enviar: el servidor ya no los acepta.';
  }
}

class Desvinculador {
  Desvinculador({
    required BaseLocal Function() baseActual,
    required AlmacenDeSesion almacen,
    required Future<void> Function(String aviso) cambiarAVacio,
    required Future<void> Function(String id, String secreto) guardarIdentidad,
  }) : _baseActual = baseActual,
       _almacen = almacen,
       _cambiarAVacio = cambiarAVacio,
       _guardarIdentidad = guardarIdentidad;

  final BaseLocal Function() _baseActual;
  final AlmacenDeSesion _almacen;

  /// Deja la app en la pantalla vacia (sin sesion, base neutra) con este aviso.
  final Future<void> Function(String aviso) _cambiarAVacio;

  /// Escribe el id y el secreto donde los encuentra `AnadirRuta` sin sesion.
  final Future<void> Function(String id, String secreto) _guardarIdentidad;

  bool _vaciando = false;

  /// Varias llamadas pueden ver el 403 a la vez: se vacia UNA vez. Nunca lanza.
  Future<void> vaciar() async {
    if (_vaciando) return;
    _vaciando = true;
    try {
      final guardada = await _almacen.leer();
      final base = _baseActual();
      final descartado = await _contar(base);
      await base.transaction(() async {
        for (final tabla in base.allTables) {
          await base.delete(tabla).go();
        }
      });
      await _almacen.borrar();
      await _cambiarAVacio('$textoDesvinculado${descartado.frase}');
      if (guardada != null) {
        await _guardarIdentidad(guardada.sub, guardada.refresh);
      }
    } on Object catch (e, pila) {
      Registro.fallo('no se pudo vaciar el telefono desvinculado', e, pila);
    } finally {
      _vaciando = false;
    }
  }

  Future<LoDescartado> _contar(BaseLocal base) async {
    try {
      final apuntes =
          await (base.select(base.apuntes)..where(
                (a) => a.estado.isIn([
                  EstadoApunte.pendiente.name,
                  EstadoApunte.rechazado.name,
                ]),
              ))
              .get();
      var marcas = 0;
      var otros = 0;
      for (final a in apuntes) {
        if (a.ruta.endsWith('/results')) {
          try {
            final cuerpo = jsonDecode(a.cuerpo) as Map<String, Object?>;
            marcas += (cuerpo['resultados'] as List?)?.length ?? 1;
          } on Object {
            marcas += 1;
          }
        } else {
          otros += 1;
        }
      }
      final puntos = await (base.select(
        base.puntosGps,
      )..where((p) => p.subido.equals(false))).get();
      return LoDescartado(
        marcas: marcas,
        otrosGestos: otros,
        puntos: puntos.length,
      );
    } on Object catch (e) {
      Registro.aviso('no se pudo contar lo que quedaba sin enviar: $e');
      return const LoDescartado();
    }
  }
}
