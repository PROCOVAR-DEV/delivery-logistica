import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../navegacion/pantalla_registrada.dart';
import '../../nucleo/frescura/colecciones_de_cada_pantalla.dart';
import 'vista/pantalla_rutas.dart';

export 'vista/pantalla_rutas.dart' show PantallaRutas;

/// RUTAS EN EL REGISTRO. El contrato esta en
/// `navegacion/pantalla_registrada.dart`.
///
/// La pantalla **no monta `Scaffold` ni `AppBar`**: los pone el armazon. Aqui
/// importa ademas por otra razon: el asistente y el cierre avisan con
/// `ScaffoldMessenger`, y el `Scaffold` al que se cuelgan esos avisos tiene que
/// ser el del armazon —el que se ve entero—, no uno propio metido dentro.
///
/// `ruta_rutas.dart` es de antes del armazon y ya no lo usa nadie: la ruta
/// `/routes` sale de aqui. Se deja mientras se confirma que nada externo lo
/// importa, y entonces se borra.
PantallaRegistrada registrarRutas() => const PantallaRegistrada(
  ruta: '/routes',
  titulo: 'Rutas',
  icono: Icons.route_outlined,
  enElMenu: true,
  colecciones: ColeccionesDePantalla.rutas,
  construir: _construir,
);

Widget _construir(BuildContext contexto, GoRouterState estado) =>
    const PantallaRutas();
