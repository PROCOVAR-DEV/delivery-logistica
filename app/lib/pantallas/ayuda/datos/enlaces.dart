/// A DONDE LLEVA UN ENLACE DEL MANUAL.
///
/// El manual se escribe con enlaces relativos entre ficheros
/// —`[Glosario](../comun/glosario.md#apunte)`— porque asi se lee igual en el
/// repositorio. Dentro de la aplicacion no hay ficheros ni carpetas, asi que cada
/// enlace se traduce aqui a una de tres cosas, o a nada.
library;

import 'manual.dart';

/// LO QUE UN ENLACE PUEDE SER.
sealed class ADonde {
  const ADonde();
}

/// A otra pagina del manual.
class ALaPagina extends ADonde {
  const ALaPagina(this.camino);

  final String camino;
}

/// A una tarea concreta de otra pagina: el enlace traia `#ancla` y el ancla
/// existe.
class ALaTarea extends ADonde {
  const ALaTarea(this.id);

  final String id;
}

/// A una pantalla de la aplicacion: el destino empieza por `/` y hay una pantalla
/// registrada ahi.
class ALaPantalla extends ADonde {
  const ALaPantalla(this.ruta);

  final String ruta;
}

/// RESUELVE UN ENLACE, o devuelve `null`.
///
/// `null` quiere decir **este enlace no lleva a ningun sitio desde aqui**, y la
/// vista lo pinta como texto llano. Pasa en dos casos, y los dos son honestos:
///
///  * la pagina de destino no se ve en esta forma de la aplicacion. En el
///    telefono, `docs/manual/README.md` enlaza a `escritorio/README.md`, que es
///    justo lo que la APK no puede ensenar (regla 1 de `CLAUDE.md`);
///  * el destino es una direccion de fuera (`https://…`). **No se abre nada por
///    red**: la guia existe para quien no tiene senal, y un enlace que necesita
///    internet en el patio de un almacen es un enlace que miente.
ADonde? resolverElEnlace(
  String destino,
  String desdeLaPagina,
  Manual manual, {
  required bool Function(String ruta) hayPantallaEn,
}) {
  if (destino.isEmpty) return null;

  // 1. UNA PANTALLA DE LA APLICACION. Se comprueba que exista: una pantalla que
  //    en esta forma no se registra —el canal con PEDIDO en la APK— llevaria a
  //    «No hay ninguna pantalla en /webhook», que no explica nada.
  if (destino.startsWith('/')) {
    final sinInterrogante = destino.split('?').first;
    return hayPantallaEn(sinInterrogante) ? ALaPantalla(sinInterrogante) : null;
  }

  // 2. Fuera. Ni se abre ni se ofrece.
  if (destino.contains('://') || destino.startsWith('mailto:')) return null;

  // 3. Dentro del manual. Puede traer `#ancla`.
  final partes = destino.split('#');
  final fichero = partes.first;
  final ancla = partes.length > 1 ? partes[1] : null;

  // Un `#ancla` suelto es un salto dentro de la propia pagina.
  final camino = fichero.isEmpty
      ? desdeLaPagina
      : _resolverElCamino(fichero, desdeLaPagina);

  final pagina = manual.pagina(camino);
  if (pagina == null) return null;

  if (ancla != null) {
    for (final tarea in pagina.tareas) {
      if (tarea.ancla == ancla) return ALaTarea(tarea.id);
    }
    // El ancla apunta a un `###` o a algo que no es una tarea: se abre la pagina
    // entera, que es donde ese trozo esta. Mejor la pagina que nada.
  }
  return ALaPagina(camino);
}

/// `../comun/glosario.md` visto desde `apk/3-tareas.md` es `comun/glosario.md`.
String _resolverElCamino(String destino, String desdeLaPagina) {
  final carpeta = desdeLaPagina.contains('/')
      ? desdeLaPagina.substring(0, desdeLaPagina.lastIndexOf('/')).split('/')
      : <String>[];
  final trozos = <String>[...carpeta];
  for (final trozo in destino.split('/')) {
    if (trozo == '.' || trozo.isEmpty) continue;
    if (trozo == '..') {
      if (trozos.isNotEmpty) trozos.removeLast();
      continue;
    }
    trozos.add(trozo);
  }
  return trozos.join('/');
}
