import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../diseno/colores.dart';
import '../pantallas/acceso/vista/pantalla_sin_permiso.dart';
import '../pantallas/configuracion_inicial/vista/pantalla_configurando.dart';
import 'armazon.dart';
import 'pantalla_registrada.dart';
import 'pantallas.dart';
import 'portero.dart';

/// La primera pantalla: la de la manana.
const rutaDeInicio = '/dashboard';

/// Monta el enrutador a partir del REGISTRO.
///
/// Aqui no hay ni una ruta escrita a mano: salen todas de
/// `pantallasDeLaAplicacion()`. Por eso anadir una pantalla es una linea en
/// `pantallas.dart` y nada mas, y por eso el menu y las rutas **no pueden
/// desincronizarse**: son la misma lista.
///
/// [pantallas] se puede pasar en los tests para montar el armazon con dos
/// pantallas de mentira, sin arrastrar la base local a un test de widget.
///
/// [portero] es lo que decide si se entra o se va a la pantalla de acceso. Sin
/// el —los tests que montan dos pantallas de mentira— no hay puerta y se entra
/// directo, que es lo que esas pruebas quieren comprobar.
GoRouter crearEnrutador({
  List<PantallaRegistrada>? pantallas,
  String inicial = rutaDeInicio,
  Portero? portero,
}) {
  final lista = pantallas ?? pantallasDeLaAplicacion();

  // Las que van dentro del armazon y las que no. La pantalla de acceso es la
  // unica de las segundas: no puede llevar barra lateral porque no hay a donde
  // ir, ni selector de sucursal porque sale de la sesion que aun no existe.
  final conArmazon = [
    for (final p in lista)
      if (p.conArmazon) p,
  ];
  final sueltas = [
    for (final p in lista)
      if (!p.conArmazon) p,
  ];

  return GoRouter(
    initialLocation: portero == null ? inicial : rutaDeArranque,
    // Lo que hace que el portero funcione sin que ninguna pantalla llame a
    // `context.go`: al cambiar el estado de la sesion, el enrutador vuelve a
    // pasar por `redirect` y la persona aterriza donde toca.
    refreshListenable: portero,
    redirect: portero == null
        ? null
        : (contexto, estado) => porteroDeRutas(estado, portero, inicial),
    routes: <RouteBase>[
      // La raiz al panel. En web alguien escribe el dominio a secas y tiene que
      // caer en algun sitio.
      GoRoute(path: '/', redirect: (_, _) => inicial),

      // La espera del arranque. No es una pantalla del registro porque no es una
      // pantalla: es lo que se ve mientras se mira si la sesion guardada sirve.
      // Sin ella se veria el formulario de contrasena durante un segundo antes
      // de entrar, y ese parpadeo ensena a escribir la contrasena por reflejo.
      GoRoute(
        path: rutaDeArranque,
        builder: (contexto, estado) => const _Esperando(),
      ),

      // «Configurando Reparto»: la primera vez, y solo la primera. Tampoco es
      // una pantalla del registro —no se llega a ella desde el menu, no lleva
      // armazon y no tiene sitio en la barra lateral—: es lo que se ve mientras
      // el aparato se configura. Con datos ya bajados no se ve nunca.
      GoRoute(
        path: rutaDeConfiguracion,
        builder: (contexto, estado) =>
            const Scaffold(body: PantallaConfigurando()),
      ),

      // «No tienes permiso para entrar a Reparto». Tampoco es del registro: no
      // lleva armazon (la barra lateral y el selector de sucursal salen de una
      // sesion que aqui no sirve) y no sale en el menu. `docs/sin-permiso.md`.
      GoRoute(
        path: rutaDeSinPermiso,
        builder: (contexto, estado) =>
            const Scaffold(body: PantallaSinPermiso()),
      ),

      // Las sueltas, FUERA del armazon pero con su `Scaffold`: la regla de «tu
      // pantalla no lleva Scaffold» sigue valiendo para todas.
      for (final p in sueltas)
        GoRoute(
          path: p.ruta,
          builder: (contexto, estado) =>
              Scaffold(body: p.construir(contexto, estado)),
          routes: p.subrutas,
        ),

      ShellRoute(
        builder: (contexto, estado, hijo) => Armazon(
          pantallas: conArmazon,
          // `matchedLocation` y no `uri.toString()`: los filtros van en la URL
          // (`/orders?municipio=…`) y la entrada del menu tiene que seguir
          // marcada con el filtro puesto.
          rutaActual: estado.matchedLocation,
          child: hijo,
        ),
        routes: <RouteBase>[for (final p in conArmazon) p.aGoRoute()],
      ),
    ],
    errorBuilder: (contexto, estado) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No hay ninguna pantalla en ${estado.uri.path}.'),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => contexto.go(inicial),
                child: const Text('Ir al panel'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Lo que se ve mientras se comprueba la sesion guardada. Un segundo, o lo que
/// tarde la red en rendirse.
class _Esperando extends StatelessWidget {
  const _Esperando();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: Colores.primario,
        ),
      ),
    ),
  );
}
