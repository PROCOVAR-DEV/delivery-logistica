import '../../../nucleo/cola/apunte.dart';
import '../../../nucleo/sincro/entrega_a_revision.dart';

/// LO QUE LEE LA PERSONA SIN PERMISO sobre su trabajo (`docs/bandeja-de-revision.md`,
/// B.5). Aqui y no en la pantalla: la pantalla pinta, esto es lo que SE DICE, y se
/// ata con pruebas que comparan el literal.
abstract final class TextosDelPanel {
  static String cambiosSinEnviar(int n) =>
      'Tienes $n ${n == 1 ? "cambio" : "cambios"} sin enviar. No se han '
      'perdido ni se han aplicado. Puedes entregarlos a revisión: un '
      'administrador de tu sucursal los mirará y decidirá si se aplican.';

  static const entregar = 'Entregar a revisión';
  static const actualizar = 'Actualizar estados';
  static const reentrar = 'Cerrar sesión y entrar de nuevo';

  /// Debajo de «Entregar»: lo que NO pasa.
  static const aviso =
      'Entregar no aplica nada: tus cambios quedan en revisión hasta que '
      'alguien los decida.';

  // --- «Cerrar sesión» con cola: las tres opciones.
  static const salirTitulo = 'Queda trabajo sin subir';
  static const entregarYSalir = 'Entregar a revisión y salir';
  static const salirSinEntregar = 'Salir sin entregar';
  static const meQuedo = 'Me quedo';

  static String salirCuerpo(int pendientes) =>
      'Hay $pendientes ${pendientes == 1 ? "apunte" : "apuntes"} sin subir al '
      'servidor. Salir NO los borra: se quedan en este aparato.\n\n'
      'Puedes entregarlos a revisión antes de salir: un administrador de tu '
      'sucursal los mirará y decidirá si se aplican.\n\n'
      'Si sales SIN entregar, quedan varados en este aparato: nadie los ve y '
      'solo subirán si te devuelven el acceso a Reparto y vuelves a entrar.';

  /// «8/10, 14:32». A mano: `DateFormat` con un locale sin cargar lanza, y esto
  /// se pinta antes de que nadie haya mirado eso.
  static String fecha(DateTime d) {
    final l = d.toLocal();
    final min = l.minute.toString().padLeft(2, '0');
    return '${l.day}/${l.month}, ${l.hour}:$min';
  }

  /// «9/10»: el descarte se dice con el dia, sin la hora (B.5).
  static String dia(DateTime d) {
    final l = d.toLocal();
    return '${l.day}/${l.month}';
  }

  /// Que es un apunte, en palabras. No es el `resumen` del aparato (no existe):
  /// sale de la ruta, que es lo unico que dice que cosa se hizo.
  static String queEs(Apunte a) {
    final ruta = a.ruta.split('?').first;
    if (RegExp(r'^/routes/[^/]+/results$').hasMatch(ruta)) {
      return 'Resultados de entrega de una ruta';
    }
    if (RegExp(r'^/routes/[^/]+/stops/[^/]+$').hasMatch(ruta)) {
      return 'Parada quitada de una ruta';
    }
    if (ruta == '/routes') return 'Ruta nueva';
    if (RegExp(r'^/routes/[^/]+$').hasMatch(ruta)) {
      if (a.metodo == 'DELETE') return 'Ruta eliminada';
      return a.cuerpo.contains('"completed"')
          ? 'Cierre de una ruta'
          : 'Cambio en una ruta';
    }
    if (ruta.startsWith('/board/placements')) return 'Pedido movido en el tablero';
    if (ruta.endsWith('/route')) return 'Ruta armada desde una zona';
    if (ruta.startsWith('/board/columns')) return 'Cambio en una zona del tablero';
    return 'Un cambio';
  }

  /// Lo que dice el estado de UN apunte entregado (B.5), o `null` si no es de la
  /// bandeja.
  static String? estadoDe(Apunte a) {
    final por = a.revisadoPor ?? 'un administrador';
    switch (a.estado) {
      case EstadoApunte.enRevision:
        final motivo = a.motivoRevision;
        if (motivo != null) {
          return 'No se pudo aplicar: $motivo. Sigue en revisión.';
        }
        final cuando = a.resueltoAt;
        return 'Entregado a revisión${cuando == null ? "" : " el ${fecha(cuando)}"}. '
            'Todavía no está aplicado: un administrador de tu sucursal tiene '
            'que revisarlo.';
      case EstadoApunte.aplicado:
        if (a.revisadoPor == null) return null;
        final cuando = a.revisadoAt;
        return 'Aplicado por $por${cuando == null ? "" : " el ${fecha(cuando)}"}.';
      case EstadoApunte.descartadoPorRevisor:
        final cuando = a.revisadoAt;
        return 'Descartado por $por${cuando == null ? "" : " el ${dia(cuando)}"}: '
            '${a.motivoRevision ?? "sin motivo"}.';
      case EstadoApunte.pendiente:
      case EstadoApunte.rechazado:
      case EstadoApunte.descartado:
        return null;
    }
  }

  /// Lo que se dice tras pulsar «Entregar», o `null` si no hay nada que decir.
  static String? resultado(ResumenDeEntrega r) {
    final espera = r.esperar == null
        ? ''
        : ' Vuelve a intentarlo en ${r.esperar!.inSeconds} s.';
    switch (r.resultado) {
      case ResultadoDeEntrega.entregado:
        final n = r.entregados;
        return n == 0
            ? null
            : 'Entregado: $n ${n == 1 ? "cambio está" : "cambios están"} en '
                  'revisión. Todavía no se ha aplicado nada.';
      case ResultadoDeEntrega.parcial:
        return 'Se entregaron ${r.entregados} y quedan ${r.sinEntregar} sin '
            'entregar, intactos. ${r.error ?? ""}$espera'.trim();
      case ResultadoDeEntrega.nadaQueEntregar:
        return 'No hay nada que entregar.';
      case ResultadoDeEntrega.noAplica:
        return null;
      case ResultadoDeEntrega.sinConexion:
      case ResultadoDeEntrega.sesionTerminada:
      case ResultadoDeEntrega.yaTienePermiso:
      case ResultadoDeEntrega.aparatoSinAlta:
      case ResultadoDeEntrega.colaDeOtraPersona:
      case ResultadoDeEntrega.rechazado:
        return '${r.error ?? ""}$espera'.trim();
    }
  }

  /// ¿Es de los que se arreglan volviendo a entrar? Entonces el panel ofrece el
  /// botón, no solo el texto.
  static bool seArreglaEntrandoDeNuevo(ResultadoDeEntrega r) =>
      r == ResultadoDeEntrega.sesionTerminada ||
      r == ResultadoDeEntrega.yaTienePermiso;
}
