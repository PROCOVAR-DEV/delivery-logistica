import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../navegacion/pantalla_registrada.dart';
import '../../nucleo/frescura/colecciones_de_cada_pantalla.dart';
import 'vista/pantalla_clientes.dart';

/// Clientes en el menu.
///
/// Se escribio como `GoRoute` suelto en `ruta.dart` porque esta pantalla es anterior al
/// contrato del armazon. Aqui se adapta: el armazon quiere una `PantallaRegistrada`, que
/// ademas es lo que le pone el titulo a la barra de arriba y la entrada en el menu.
///
/// `ruta.dart` se queda de momento —lo usan sus pruebas— y se retira cuando pasen a
/// montar la pantalla por aqui.
PantallaRegistrada registrarClientes() => const PantallaRegistrada(
  ruta: '/customers',
  titulo: 'Clientes',
  icono: Icons.people_outline,
  enElMenu: true,
  colecciones: ColeccionesDePantalla.clientes,
  construir: _construir,
);

Widget _construir(BuildContext contexto, GoRouterState estado) =>
    const PantallaClientes();
