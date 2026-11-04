// AÑADIR UNA RUTA con su enlace: reclama la ruta para ESTE telefono y deja el
// acceso y el secreto guardados (almacen seguro, el de siempre).
//
//  * El primer enlace crea la "sesion" del dispositivo y entra (`Portero.entro`).
//  * Los siguientes solo ponen el acceso nuevo y piden un ciclo para bajar la ruta.
//  * El `dispositivoId` (UUIDv7) se genera la primera vez y se guarda en las
//    preferencias; tras reclamar vive tambien dentro de la sesion (`sub`).
import '../../nucleo/cola/provisionales.dart';
import '../../nucleo/identidad/almacen_sesion.dart';
import '../../nucleo/identidad/sesion.dart';
import '../../nucleo/registro/registro.dart';
import '../../nucleo/reloj.dart';
import 'cliente_de_dispositivo.dart';
import 'enlace_de_ruta.dart';
import 'renovador_de_dispositivo.dart';
import 'vinculo.dart';

const claveDelDispositivoId = 'dispositivoId';

class AnadirRuta {
  AnadirRuta({
    required ClienteDeDispositivo cliente,
    required AlmacenDeSesion almacen,
    required Future<String?> Function() leerId,
    required Future<void> Function(String) guardarId,
    required Future<String?> Function() nombreDelTelefono,
    required Future<void> Function() esperarAlArranque,
    required Future<void> Function(Sesion) entrar,
    required Future<void> Function() bajarRutas,
    Future<String?> Function()? leerSecreto,
    Future<void> Function(VinculoDelTelefono)? guardarVinculo,
    Reloj reloj = relojDelAparato,
  }) : _leerSecreto = leerSecreto,
       _guardarVinculo = guardarVinculo,
       _cliente = cliente,
       _almacen = almacen,
       _leerId = leerId,
       _guardarId = guardarId,
       _nombre = nombreDelTelefono,
       _esperar = esperarAlArranque,
       _entrar = entrar,
       _bajar = bajarRutas,
       _reloj = reloj;

  final ClienteDeDispositivo _cliente;
  final AlmacenDeSesion _almacen;
  final Future<String?> Function() _leerId;
  final Future<void> Function(String) _guardarId;
  final Future<String?> Function() _nombre;
  final Future<void> Function() _esperar;
  final Future<void> Function(Sesion) _entrar;
  final Future<void> Function() _bajar;
  final Reloj _reloj;

  /// El secreto del telefono cuando NO hay sesion (tras vaciarse por una
  /// desvinculacion se conserva, junto al id, para seguir siendo el mismo telefono).
  final Future<String?> Function()? _leerSecreto;

  /// Guarda el vehiculo y el distribuidor que trae el enlace (ya en la base del telefono).
  final Future<void> Function(VinculoDelTelefono)? _guardarVinculo;

  /// Devuelve el id de la ruta reclamada. Lanza [EnlaceRechazado] con las palabras
  /// para la persona (o `FalloDeRed` si no hay red: reclamar necesita conexion).
  Future<String> anadir(String texto) async {
    if (texto.trim().isEmpty) {
      throw const EnlaceRechazado('Escribe o pega el código de la ruta.');
    }
    final token = tokenDelEnlace(texto);
    if (token == null) {
      throw const EnlaceRechazado(
        'Eso no parece un enlace de Reparto ni el código de una ruta.',
      );
    }
    // Reclamar mientras el arranque aun comprueba la sesion guardada se pisaria
    // con su resultado («fuera»).
    await _esperar();
    final guardada = await _almacen.leer();
    var id = guardada?.sub;
    if (id == null || id.isEmpty) {
      id = await _leerId();
      if (id == null || id.isEmpty) {
        id = Provisionales.nuevoIdReal();
        await _guardarId(id);
      }
    }
    final pedidoA = _reloj();
    final secretoGuardado = guardada?.refresh ?? await _leerSecreto?.call();
    final nombre = await _nombre() ?? 'Teléfono';
    RutaReclamada r;
    try {
      r = await _cliente.reclamar(token: token, dispositivoId: id, nombre: nombre, secreto: secretoGuardado);
    } on SecretoDelTelefonoNoCuadra {
      // Sin ninguna clave guardada el servidor conoce un id cuya clave nunca nos llegó (el primer reclamo se perdió a medias): se estrena
      // otro id. Con clave guardada es otra cosa (lo dieron de baja): se dice.
      if (secretoGuardado != null && secretoGuardado.isNotEmpty) rethrow;
      id = Provisionales.nuevoIdReal();
      await _guardarId(id);
      r = await _cliente.reclamar(token: token, dispositivoId: id, nombre: nombre);
    }
    final secreto = r.secreto ?? secretoGuardado;
    if (secreto == null || secreto.isEmpty) {
      throw const EnlaceRechazado(
        'El servidor no dio la clave de este teléfono. Inténtalo otra vez.',
      );
    }
    final nueva = sesionDeDispositivo(
      acceso: r.acceso,
      secreto: secreto,
      dispositivoId: id,
      pedidoA: pedidoA,
    );
    if (!await _almacen.guardar(nueva)) {
      Registro.fallo('el acceso del dispositivo no quedo guardado');
      throw const EnlaceRechazado(
        'No se pudo guardar el acceso en este teléfono. Inténtalo otra vez.',
      );
    }
    if (guardada == null) {
      await _entrar(nueva);
    } else {
      await _bajar();
    }
    // Despues de entrar: la base ya es la de este telefono.
    final vinculo = VinculoDelTelefono.deLaRespuesta(r);
    if (vinculo != null) await _guardarVinculo?.call(vinculo);
    return r.rutaId;
  }
}
