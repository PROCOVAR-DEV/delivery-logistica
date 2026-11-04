// «REPARTO DISTRIBUIDOR»: la segunda entrada de la app para el repartidor
// (`docs/app-distribuidor.md`). Reutiliza TODO el motor (Drift, cola, sincronizador,
// sesion) y enseña solo: Mis rutas -> ruta guiada -> cierre parada por parada, sin
// conexion, subiendo cuando haya red. Compilar:
//
//   ORG_GRADLE_PROJECT_distribuidor=true flutter build apk --release -t lib/main_distribuidor.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'app.dart';
import 'distribuidor/dispositivo/proveedores_dispositivo.dart';
import 'distribuidor/envoltura.dart';
import 'distribuidor/mapa/solo_local.dart';
import 'distribuidor/modo_distribuidor.dart';
import 'distribuidor/pantallas_distribuidor.dart';
import 'distribuidor/proveedores_distribuidor.dart';
import 'nucleo/proveedores.dart';
import 'pantallas/rutas/datos/mapa_en_vivo.dart';

/// Los `override` del modo distribuidor, aparte para poder montarlos en las pruebas.
List<Override> overridesDelDistribuidor() => [
  modoDistribuidorProvider.overrideWithValue(true),
  // Sin usuario ni contrasena: el acceso se renueva con el secreto del telefono.
  renovadorProvider.overrideWith(
    (ref) => ref.watch(renovadorDeDispositivoProvider),
  ),
  // El mapa viene en el APK y NO sale a la red (ni teselas ni OSRM).
  fondoDeCallesProvider.overrideWith(
    (ref) => ref.watch(fondoSoloLocalProvider),
  ),
  recorridoPorCallesProvider.overrideWith(
    (ref) => ref.watch(recorridoSoloLocalProvider),
  ),
  // La oficina desvincula el telefono: la app se vacia y vuelve a «Agregar ruta».
  alDesvincularseProvider.overrideWith(
    (ref) =>
        () => unawaited(ref.read(desvinculadorProvider).vaciar()),
  ),
  // Tras la cola de apuntes, los puntos de GPS.
  despuesDeSubirProvider.overrideWith(
    (ref) => ref.watch(subidaDelRecorridoProvider)?.subir,
  ),
];

/// Si la app se abrio con un enlace (`/r/<token>`), por donde entro.
String? enlaceDeEntrada(String rutaPorDefecto) =>
    rutaPorDefecto.startsWith('/r/') ? rutaPorDefecto : null;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  runApp(
    ProviderScope(
      overrides: overridesDelDistribuidor(),
      child: RepartoApp(
        pantallas: pantallasDelDistribuidor(),
        inicial: '/routes',
        enlaceDeEntrada: enlaceDeEntrada(
          WidgetsBinding.instance.platformDispatcher.defaultRouteName,
        ),
        alrededor: (app) => EnvolturaDelDistribuidor(app: app),
      ),
    ),
  );
}
