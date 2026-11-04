// LA GUIA DE LA RUTA: lo que hace el distribuidor con una ruta, de principio a fin,
// sin conexion. Iniciar, marcar parada por parada y COMPLETAR SOLA al marcar la
// ultima. Todo pasa por `AccionesDeRuta`, o sea por la base local y la cola de
// siempre: offline queda en cola, en orden (resultados primero, `completed` despues).
//
// El GPS (`RecorridoGps`) es un extra que nunca estorba: un fallo suyo no
// impide marcar ni completar.
import '../nucleo/base/base.dart';
import '../pantallas/rutas/datos/acciones_rutas.dart';
import '../pantallas/rutas/datos/repositorio_rutas.dart';
import 'gps/puntos_locales.dart' show EventoDeRecorrido;
import 'gps/recorrido_gps.dart';
import 'parada_actual.dart';

/// Los dos botones de la parada. «No entregada» viaja como `devuelto` (el servidor
/// solo conoce entregado / devuelto / cancelado) y EXIGE un motivo corto: asi la
/// logistica revisa dos veces en vez de fiarse de una sola palabra.
enum SalidaDeParada {
  entregado('Entregado', ResultadoParada.entregado),
  noEntregada('No entregada', ResultadoParada.devuelto);

  const SalidaDeParada(this.etiqueta, this.resultado);

  final String etiqueta;
  final String resultado;

  bool get exigeMotivo => this == noEntregada;

  String? notaFinal(String? nota) {
    final n = nota?.trim() ?? '';
    return n.isEmpty ? null : n;
  }
}

const msgFaltaElMotivo = 'Escribe el motivo de por qué no se entregó.';

class GuiaDeRuta {
  GuiaDeRuta({
    required AccionesDeRuta acciones,
    required ConsultasRutas consultas,
    RecorridoGps? recorrido,
  }) : _acciones = acciones,
       _consultas = consultas,
       _recorrido = recorrido;

  final AccionesDeRuta _acciones;
  final ConsultasRutas _consultas;
  final RecorridoGps? _recorrido;

  /// El distribuidor INICIA su ruta.
  Future<void> iniciar(String rutaId) async {
    await _acciones.iniciar(rutaId);
    // Despues: con la ruta ya en curso el recorrido se enciende y el punto lleva
    // tambien las demas rutas que ya estuvieran en curso.
    await _recorrido?.evento(EventoDeRecorrido.inicio, rutaId: rutaId);
  }

  /// CANCELA la ruta entera, con motivo (el servidor solo lo permite si no hay ninguna
  /// entregada; el aparato lo comprueba antes).
  Future<void> cancelar(String rutaId, {required String motivo}) async {
    await _acciones.cancelar(rutaId, motivo: motivo);
    await _recorrido?.evento(EventoDeRecorrido.fin, rutaId: rutaId);
  }

  /// Marca la parada [pedidoId] y, si era la ultima, COMPLETA la ruta. Devuelve
  /// `true` si la ruta quedo completada. Si falta una sola parada, no se completa.
  Future<bool> marcar(
    String rutaId,
    String pedidoId,
    SalidaDeParada salida, {
    String? nota,
    required bool cobrado,
  }) async {
    if (salida.exigeMotivo && salida.notaFinal(nota) == null) {
      throw const RechazoLocal(msgFaltaElMotivo);
    }
    await _acciones.marcarParada(
      rutaId,
      pedidoId: pedidoId,
      resultado: salida.resultado,
      nota: salida.notaFinal(nota),
      // Cobrar solo tiene sentido si se entrego.
      cobrado: salida == SalidaDeParada.entregado && cobrado,
    );
    await _recorrido?.evento(
      EventoDeRecorrido.parada,
      rutaId: rutaId,
      pedidoId: pedidoId,
    );
    return completarSiToca(rutaId);
  }

  /// Completa la ruta SI todas sus paradas tienen resultado (y si no, no hace
  /// nada). Tambien sirve para reintentar si la ruta se quedo con todo marcado y
  /// sin completar. `true` = quedo completada.
  Future<bool> completarSiToca(String rutaId) async {
    if (!todasMarcadas(await _consultas.paradasDe(rutaId))) return false;
    await _acciones.completar(rutaId);
    await _recorrido?.evento(EventoDeRecorrido.fin, rutaId: rutaId);
    return true;
  }
}
