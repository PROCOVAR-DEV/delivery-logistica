import 'dart:convert';
import 'dart:io';

import 'package:android_id/android_id.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../registro/registro.dart';

/// Un UUID v7 bien formado: lo único que Accesos acepta para CREAR un aparato.
final _v7 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

Future<String?>? _id;

/// Un fichero en la carpeta de datos de la aplicación, NO en la base de la
/// persona: el aparato es el mismo aunque cambien las cuentas que entran, y
/// olvidar una cuenta no puede darle otro id.
Future<File> _fichero() async =>
    File('${(await getApplicationSupportDirectory()).path}/aparato-id');

/// El id de este aparato. **Se guarda el `Future`, no el valor**: con varias
/// peticiones a la vez en el primer arranque (cada una lo pide), guardar solo
/// el valor creaba un id por petición y se quedaba el último, o sea un aparato
/// fantasma en «Dispositivos». Un fallo (`null`) también se recuerda: no se
/// vuelve a tocar el disco en cada petición a Accesos.
Future<String?> idDelAparato() =>
    _enPruebas ? Future.value() : _id ??= _leerOCrearId(_fichero);

/// En `flutter test` no hay aparato: el disco y el registro reales dentro del reloj falso de un `testWidgets` cuelgan la prueba
/// (CLAUDE.md §5, «pruebas colgadas»). Las pruebas de esto inyectan sus propias lecturas o llaman a [leerOCrearId] con un fichero suyo.
bool get _enPruebas => Platform.environment.containsKey('FLUTTER_TEST');

/// Lee el id guardado o crea uno nuevo (v7) y lo guarda. Pública para probarla
/// con un fichero de prueba.
Future<String?> leerOCrearId(Future<File> Function() fichero) =>
    _leerOCrearId(fichero);

Future<String?> _leerOCrearId(Future<File> Function() fichero) async {
  try {
    final f = await fichero();
    if (await f.exists()) {
      final leido = (await f.readAsString()).trim().toLowerCase();
      if (_v7.hasMatch(leido)) return leido;
    }
    final nuevo = const Uuid().v7();
    await f.writeAsString(nuevo, flush: true);
    return nuevo;
  } on Object catch (e) {
    // Sin id la petición sale como siempre: un id no vale una renovación que no sale.
    Registro.aviso('no se pudo leer ni crear el id del aparato: $e');
    return null;
  }
}

Future<String?>? _nombre;

/// Solo ASCII imprimible: va en una cabecera HTTP (nada de saltos de línea ni
/// de letras que la cabecera no admite). Las tildes y la eñe pierden la marca,
/// no la letra: «MÁQUINA» sale «MAQUINA», no «MQUINA».
String nombreParaCabecera(String crudo) {
  const de = 'áéíóúüñÁÉÍÓÚÜÑ';
  const a = 'aeiouunAEIOUUN';
  final sb = StringBuffer();
  for (final r in crudo.runes) {
    final c = String.fromCharCode(r);
    final i = de.indexOf(c);
    sb.write(i >= 0 ? a[i] : c);
  }
  return sb.toString().replaceAll(RegExp(r'[^\x20-\x7e]'), '').trim();
}

Future<String?> nombreDelAparato() =>
    _enPruebas ? Future.value() : _nombre ??= _leerNombre();

Future<String?> _leerNombre() async {
  try {
    final info = DeviceInfoPlugin();
    final n = Platform.isAndroid
        ? await info.androidInfo.then((a) => '${a.manufacturer} ${a.model}')
        : Platform.isWindows
        ? await info.windowsInfo.then((w) => w.computerName)
        : Platform.isLinux
        ? await info.linuxInfo.then((l) => l.prettyName)
        : null;
    final limpio = n == null ? null : nombreParaCabecera(n);
    return (limpio == null || limpio.isEmpty) ? null : limpio;
  } on Object catch (e) {
    Registro.aviso('no se pudo leer el nombre del aparato: $e');
    return null;
  }
}

/// El hash que se manda: `sha256("procovar:" + idDeLaMaquina)` en hexadecimal minúsculas.
/// Pública para probar que sale EXACTAMENTE como lo calcula el CRM.
String huellaDe(String idDeLaMaquina) =>
    sha256.convert(utf8.encode('procovar:$idDeLaMaquina')).toString();

Future<String?>? _huella;

/// El id de la máquina, según el sistema. `null` si no se sabe: sin huella, la
/// instalación sale igual y Accesos solo no la puede juntar sola con las demás.
Future<String?> _idDeLaMaquina() async {
  if (Platform.isAndroid) return const AndroidId().getId();
  if (Platform.isWindows) {
    // Ruta absoluta: no se busca `reg` en el PATH de quien sea. Y con tope: un
    // `reg` colgado no puede dejar sin salir la renovación de la sesión.
    final raiz = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final r = await Process.run('$raiz\\System32\\reg.exe', [
      'query',
      r'HKLM\SOFTWARE\Microsoft\Cryptography',
      '/v',
      'MachineGuid',
    ]).timeout(const Duration(seconds: 5));
    return RegExp(r'MachineGuid\s+REG_SZ\s+(\S+)')
        .firstMatch('${r.stdout}')
        ?.group(1);
  }
  if (Platform.isLinux) {
    return (await File('/etc/machine-id').readAsString()).trim();
  }
  return null;
}

/// Se guarda el `Future` (también el fallo): si `reg` falla o devuelve vacío no
/// se vuelve a lanzar un proceso en cada petición a Accesos.
Future<String?> huellaDelAparato() =>
    _enPruebas ? Future.value() : _huella ??= _calcularHuella();

Future<String?> _calcularHuella() async {
  try {
    final id = await _idDeLaMaquina();
    if (id == null || id.trim().isEmpty) return null;
    return huellaDe(id.trim());
  } on Object catch (e) {
    Registro.aviso('no se pudo calcular la huella del aparato: $e');
    return null;
  }
}
