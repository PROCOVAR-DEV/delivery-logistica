import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../navegacion/pantalla_registrada.dart';
import '../../nucleo/frescura/colecciones_de_cada_pantalla.dart';
import 'vista/pantalla_pedidos.dart';

export 'vista/pantalla_pedidos.dart' show PantallaPedidos;

/// PEDIDOS EN EL REGISTRO. El contrato esta en
/// `navegacion/pantalla_registrada.dart`.
///
/// La pantalla **no monta `Scaffold` ni `AppBar`**: el armazon ya pone la barra
/// lateral, la barra superior con este mismo titulo y la franja de estado. Aqui
/// solo se declara donde vive y como se llama.
///
/// `ruta_pedidos.dart` es de antes del armazon y ya no lo usa nadie: la ruta
/// `/orders` sale de aqui. Se deja mientras se confirma que nada externo lo
/// importa, y entonces se borra.
PantallaRegistrada registrarPedidos() => const PantallaRegistrada(
  ruta: '/orders',
  titulo: 'Pedidos',
  icono: Icons.inventory_2_outlined,
  enElMenu: true,
  colecciones: ColeccionesDePantalla.pedidos,
  construir: _construir,
);

/// LOS FILTROS SALEN DE LA DIRECCIÓN, y por eso `estado` ya no se tira.
///
/// Aquí ponía `const PantallaPedidos()` y el `GoRouterState` entero se perdía,
/// contra el contrato de `pantalla_registrada.dart`. Lo que costaba:
/// `/orders?municipio=Centro` abría la lista SIN acotar y sin decirlo, y
/// recargar dentro de la pantalla borraba los nueve filtros. El porqué entero y
/// lo que pasa con un valor que no se entiende, en
/// `datos/filtros_en_la_url.dart`.
Widget _construir(BuildContext contexto, GoRouterState estado) =>
    PantallaPedidos(consulta: estado.uri.queryParameters);
