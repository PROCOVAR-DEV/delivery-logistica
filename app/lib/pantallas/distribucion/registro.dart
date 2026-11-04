import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../navegacion/pantalla_registrada.dart';
import '../../nucleo/frescura/colecciones_de_cada_pantalla.dart';
import 'vista/pantalla_distribucion.dart';

/// DISTRIBUCIÓN en el menú: dónde están los distribuidores ahora y las rutas por revisar.
///
/// Lo que enseña sale del servidor en vivo (GPS y revisión viven allí), no de la copia del aparato: por eso no mide la frescura de
/// ninguna colección. Es de la oficina como el resto de Rutas; el cerrojo es el del servidor (403 a quien no corresponda).
PantallaRegistrada registrarDistribucion() => const PantallaRegistrada(
  ruta: PantallaDistribucion.ruta,
  titulo: 'Distribución',
  icono: Icons.my_location_outlined,
  enElMenu: true,
  colecciones: ColeccionesDePantalla.ninguna,
  construir: _construir,
);

Widget _construir(BuildContext contexto, GoRouterState estado) =>
    const PantallaDistribucion();
