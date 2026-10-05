/// DE DONDE SACA LA GUIA LO QUE ENSENA. **De los assets, nunca de la red.**
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../navegacion/pantalla_registrada.dart';
import '../../../navegacion/pantallas.dart';
import '../../../nucleo/plataforma.dart';
import 'empaquetado.dart';
import 'manual.dart';

/// EN QUE FORMA DE LA APLICACION ESTAMOS.
///
/// La mitad web / no-web **se le pregunta a `Destino`** y no se vuelve a decidir
/// aqui: es la misma pregunta que ya contesta `nucleo/plataforma.dart`, y dos
/// sitios contestandola es el §3-bis. Lo unico propio de la guia es partir en dos
/// lo que `Destino` deja junto, porque es la primera pieza del proyecto que
/// necesita distinguir **la APK del escritorio** — la guia del telefono y la del
/// ordenador son dos documentos distintos y no se pueden cruzar.
FormaDeLaAplicacion formaDeAhora() {
  if (!Destino.trabajaSinConexion) return FormaDeLaAplicacion.web;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => FormaDeLaAplicacion.apk,
    _ => FormaDeLaAplicacion.escritorio,
  };
}

/// Por proveedor y no llamando a [formaDeAhora] desde la pantalla, igual que
/// `trabajaSinConexionProvider`: asi una prueba monta la guia de las tres formas
/// sin compilar tres veces, que es lo unico que hace comprobable «la APK no
/// ensena la guia del escritorio».
final formaDeLaAplicacionProvider = Provider<FormaDeLaAplicacion>(
  (ref) => formaDeAhora(),
);

/// LAS PANTALLAS QUE EXISTEN **EN ESTA FORMA**, con su etiqueta del menu.
///
/// De aqui sale el boton de «llévame ahí»: el manual nombra la pantalla como la
/// nombra el menu —«Menú → «Vehículos»»— y esta lista es la que dice a donde va
/// eso. Sale del registro de verdad (`pantallasDeLaAplicacion()`), no de una
/// tabla escrita aparte, que es lo que hace que una pantalla que se mueva se note.
///
/// Y es **la de esta forma**: el canal con PEDIDO no se registra en la APK ni en
/// el escritorio, asi que alli su tarea se queda sin boton en vez de llevar a «No
/// hay ninguna pantalla en /webhook».
List<PantallaDelMenu> pantallasParaLaGuia([
  List<PantallaRegistrada>? registradas,
]) => [
  for (final p in registradas ?? pantallasDeLaAplicacion())
    PantallaDelMenu(p.ruta, p.titulo),
];

/// EL MANUAL, LEIDO DEL ASSET.
///
/// ## Un `Future` aqui SI vale, y el §3-ter explica por que
///
/// La regla es que lo que se pinta y **puede cambiar** cuando llega la bajada va
/// por `Stream`. Esto no puede cambiar: el manual viene horneado en el paquete de
/// la aplicacion, se lee una vez y es el mismo hasta que alguien instale otra
/// version. No hay una segunda respuesta que esperar, asi que no hay nada que se
/// pueda quedar congelado.
///
/// ## Y no se pide nada a la red, ni aqui ni en ningun sitio
///
/// `rootBundle` lee de dentro del propio paquete: en Android del APK, en el
/// escritorio del fichero de la aplicacion y en web del `assets/` que ya bajo con
/// la pagina. **Sin conexion funciona igual**, que es la condicion que decide
/// todo esto.
final manualProvider = FutureProvider<Manual>((ref) async {
  final forma = ref.watch(formaDeLaAplicacionProvider);
  final paquete = await rootBundle.loadString(assetDelManual);
  return Manual.desdeElPaquete(
    paquete,
    pantallas: pantallasParaLaGuia(),
  ).paraLaForma(forma);
});
