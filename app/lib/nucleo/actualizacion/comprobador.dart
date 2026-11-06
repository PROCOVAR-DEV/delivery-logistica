import '../base/base.dart';
import '../red/cliente_api.dart';
import '../red/fallos.dart';
import '../registro/registro.dart';
import 'version_publicada.dart';

/// EL AVISO DE VERSIÓN NUEVA. Se mira al arrancar, si hay red.
///
/// Las tres reglas, que no se negocian y están escritas en `comprobar()`:
///
///  1. **No se actualiza con cola pendiente.** Si al logístico le queda el cierre
///     de la tarde sin subir, esto devuelve `PrimeroSube` y la pantalla dice por
///     qué. Instalar encima con trabajo sin subir lo puede borrar entero: en
///     Android, si la firma no coincide hay que desinstalar, y desinstalar se
///     lleva la base local por delante.
///  2. **Nunca se fuerza.** Aquí no se descarga nada, no se instala nada y no se
///     abre nada. Se devuelve un estado; quien decide es la persona, que a lo
///     mejor está en el patio de un almacén y no es el momento.
///  3. **La web no entra.** Se actualiza sola al recargar. `NoAplica` a la
///     primera línea, sin llamar siquiera al servidor.
///
/// No lleva reintentos a propósito (ver `sinEsperas`): esto NO es urgente. Que
/// una comprobación de versión se tire ochenta segundos reintentando mientras
/// alguien espera para entrar a trabajar es exactamente al revés de como tiene
/// que ser. Si no hubo red, se mira mañana.
class ComprobadorDeActualizacion {
  ComprobadorDeActualizacion({
    required ClienteApi cliente,
    required BaseLocal base,
    Plataforma? plataforma,
    Future<VersionInstalada> Function()? instalada,
    this.clave = 'ultima',
  }) : _cliente = cliente,
       _base = base,
       _plataforma = plataforma ?? Plataforma.deEsteAparato(),
       _instalada = instalada ?? VersionInstalada.delPaquete;

  final ClienteApi _cliente;
  final BaseLocal _base;
  final Plataforma _plataforma;
  final Future<VersionInstalada> Function() _instalada;

  /// QUÉ anuncio de `GET /api/version` se mira: `ultima` (Reparto) o `distribuidor` («Reparto Distribuidor», que tiene versión
  /// propia). Las tres reglas son las mismas; cada aplicación solo mira el suyo y nunca el de la otra.
  final String clave;

  /// La ruta es relativa a `API_URL`, que ya trae el `/api`: sale
  /// `https://…/api/version`, la del contrato.
  static const ruta = '/version';

  /// Sin reintentos y sin esperas. Se le pasa a `ClienteApi.montar` cuando se
  /// construye el cliente de esta comprobación (ver `nucleo/proveedores.dart`).
  static const sinEsperas = <Duration>[];

  Future<EstadoDeActualizacion> comprobar() async {
    // Regla 3, y antes que nada: en web no hay nada que comprobar.
    if (_plataforma == Plataforma.ninguna) {
      return const NoAplica(
        'esta plataforma se actualiza sola o no se publica',
      );
    }

    final Map<String, Object?> cuerpo;
    try {
      cuerpo = await _cliente.pedir<Map<String, Object?>>(ruta);
    } on FalloDeRed catch (red) {
      // Sin red al arrancar no se sabe, y no saber no es un problema: se mira la
      // próxima vez. No se enseña nada.
      Registro.info('no se pudo mirar la versión: ${red.mensaje}');
      return const NoSeSupo();
    } on FalloApi catch (otro) {
      // Un 4xx aquí es una ruta que no existe o un proxy por medio. Se anota,
      // porque significa que este aviso no va a funcionar nunca, pero no se le
      // cuenta a nadie que está en la calle.
      Registro.fallo('la comprobación de versión no salió bien', otro);
      return const NoSeSupo();
    }

    final publicada = VersionPublicada.deJson(cuerpo[clave]);
    if (publicada == null) {
      // El servidor no anuncia ninguna. Es lo normal mientras no haya nada
      // colgado; no es un fallo.
      return const AlDia();
    }

    final enlace = publicada.descargaPara(_plataforma);
    if (enlace == null) {
      // Hay versión nueva pero no para esta plataforma —el `.exe` todavía no
      // está subido, por ejemplo—. Avisar sin sitio de donde bajarla sólo sirve
      // para que alguien pregunte.
      Registro.aviso(
        'hay ${publicada.version} pero nada colgado para ${_plataforma.clave}',
      );
      return const NoAplica('no hay descarga para esta plataforma');
    }

    final VersionInstalada mia;
    try {
      mia = await _instalada();
    } on Object catch (e) {
      // Si no se sabe qué hay instalado, no se puede comparar. Callarse es lo
      // correcto: lo otro es avisar siempre, en cada arranque, para siempre.
      Registro.fallo('no se pudo leer la versión instalada', e);
      return const NoSeSupo();
    }

    if (!hayQueActualizar(mia, publicada)) return const AlDia();

    // REGLA 1, y va la ÚLTIMA a propósito: sólo se mira la cola cuando de verdad
    // hay algo que instalar. Decirle a alguien «sube primero» cuando no hay
    // ninguna versión nueva es mandarle a buscar red sin ningún motivo.
    // `cuantosSinSubir` y no `cuantosPendientes` — 24/09/2026. Un apunte
    // RECHAZADO es trabajo que no esta arriba, y actualizar encima puede
    // llevarselo igual que si estuviera esperando en la cola: la diferencia es
    // que ese ademas no se arregla solo, esta esperando a que alguien decida.
    final pendientes = await _base.cuantosSinSubir();
    if (pendientes > 0) {
      return PrimeroSube(publicada: publicada, pendientes: pendientes);
    }

    return SePuedeActualizar(publicada: publicada, enlace: enlace);
  }
}

/// Lo que sale de mirar. Sellado: la pantalla tiene que tratar los cinco casos, y
/// que el compilador lo exija es lo que impide que «no se pudo comprobar» se
/// pinte como «está al día».
sealed class EstadoDeActualizacion {
  const EstadoDeActualizacion();
}

/// No hay nada más nuevo. No se enseña nada.
class AlDia extends EstadoDeActualizacion {
  const AlDia();
}

/// Aquí no se comprueba: web, o una plataforma sin fichero publicado.
class NoAplica extends EstadoDeActualizacion {
  const NoAplica(this.motivo);

  final String motivo;
}

/// No se pudo mirar —sin red, o el servidor contestó algo raro—. **No se enseña
/// nada**: no saber no es una noticia para quien está trabajando.
class NoSeSupo extends EstadoDeActualizacion {
  const NoSeSupo();
}

/// Hay una nueva y se puede instalar. Se **avisa**; no se baja ni se instala.
class SePuedeActualizar extends EstadoDeActualizacion {
  const SePuedeActualizar({required this.publicada, required this.enlace});

  final VersionPublicada publicada;

  /// De dónde se baja, para esta plataforma.
  final String enlace;
}

/// Hay una nueva, pero **primero hay que subir el trabajo** (regla 1).
///
/// Lleva cuántos apuntes quedan para que el aviso pueda decirlo: «te quedan 14
/// cosas por subir» es accionable; «no puedes actualizar», no.
class PrimeroSube extends EstadoDeActualizacion {
  const PrimeroSube({required this.publicada, required this.pendientes});

  final VersionPublicada publicada;
  final int pendientes;
}
