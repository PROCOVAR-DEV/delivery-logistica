import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/eventos.dart' show PulsoDelCanal;

/// EL CANAL COMPARTIDO: uno solo para los dos que lo escuchan, y que se vuelve a
/// abrir cuando se vuelve a entrar.
///
/// Lo segundo es lo que estaba mal y no se veia: el canal se abria al arrancar
/// la aplicacion y, si alguien cerraba sesion y volvia a entrar **sin cerrar la
/// aplicacion**, ya no se abria nunca mas. Sin error y sin aviso: la pantalla
/// volvia a los cinco minutos del temporizador.
void main() {
  test('un canal para los dos oyentes, y se reabre al volver', () async {
    final falso = _CanalFalso();
    final contenedor = ProviderContainer(
      overrides: [escuchaDeEventosProvider.overrideWithValue(falso.abrir)],
    );
    addTearDown(contenedor.dispose);

    final canal = contenedor.read(avisosDelServidorProvider);
    final delVigia = <String>[];
    final delTablero = <String>[];
    final s1 = canal.listen(delVigia.add);
    final s2 = canal.listen(delTablero.add);
    await _unRespiro();

    expect(
      falso.aperturas,
      1,
      reason: 'dos oyentes NO pueden ser dos conexiones para lo mismo',
    );

    falso.ultimo.add('tablero');
    await _unRespiro();
    expect(delVigia, ['tablero']);
    expect(delTablero, ['tablero']);

    await s1.cancel();
    await _unRespiro();
    expect(
      falso.cierres,
      0,
      reason: 'mientras quede alguien escuchando, el canal no se suelta',
    );

    await s2.cancel();
    await _unRespiro();
    expect(
      falso.cierres,
      1,
      reason: 'al irse el ultimo se suelta la conexión de abajo',
    );

    // Y aqui esta el fallo que esto viene a cerrar: volver a entrar.
    final s3 = canal.listen(delVigia.add);
    await _unRespiro();
    expect(
      falso.aperturas,
      2,
      reason:
          'quien sale y vuelve a entrar sin cerrar la aplicación tiene que '
          'recuperar el canal, no quedarse con el temporizador',
    );
    falso.ultimo.add('pedidos');
    await _unRespiro();
    expect(delVigia, ['tablero', 'pedidos']);
    await s3.cancel();
  });
}

Future<void> _unRespiro() => Future<void>.delayed(Duration.zero);

class _CanalFalso {
  int aperturas = 0;
  int cierres = 0;
  final _controles = <StreamController<String>>[];

  StreamController<String> get ultimo => _controles.last;

  Stream<String> abrir(
    String urlBase,
    Future<String?> Function() token, {
    Future<void> Function()? renovarSesion,
    PulsoDelCanal? pulso,
  }) {
    aperturas++;
    final control = StreamController<String>();
    control.onCancel = () {
      cierres++;
    };
    _controles.add(control);
    return control.stream;
  }
}
