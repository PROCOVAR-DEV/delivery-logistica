import 'package:flutter/material.dart';

import '../../navegacion/pantalla_registrada.dart';
import '../../nucleo/frescura/colecciones_de_cada_pantalla.dart';
import 'vista/pantalla_panel.dart';

/// El registro del Panel. El contrato esta en
/// `navegacion/pantalla_registrada.dart`.
PantallaRegistrada registrarPanel() => PantallaRegistrada(
  ruta: '/dashboard',
  titulo: 'Panel',
  icono: Icons.dashboard_outlined,
  enElMenu: true,
  // LAS NUEVE, Y A PROPOSITO. La pregunta del Panel es «¿le falta algo a
  // este aparato?», asi que ahi manda la bajada mas vieja de todas: es la
  // que decide si hay que traer el dia antes de salir a la calle.
  colecciones: ColeccionesDePantalla.panel,
  construir: (contexto, estado) => const PantallaPanel(),
);
