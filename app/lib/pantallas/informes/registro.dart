import 'package:flutter/material.dart';

import '../../navegacion/pantalla_registrada.dart';
import '../../nucleo/frescura/colecciones_de_cada_pantalla.dart';
import 'vista/pantalla_informes.dart';

/// El registro de Reportes. El contrato esta en
/// `navegacion/pantalla_registrada.dart`.
///
/// EN EL MENU, y es un cambio deliberado respecto al patron.
///
/// Estaba en `false` citando el pliego (§8.1): en delivery la barra lateral
/// tiene seis entradas —Panel, Rutas, Pedidos, Clientes, Vehiculos, Almacenes—
/// y Reportes no esta en ninguna; se llega desde «Ver Reportes» de las acciones
/// rapidas del Panel. Se copio fielmente.
///
/// Y fielmente copiado, **Jose no la encontro**: «esa vista de reportes no sale
/// en los links para moverse». Una pantalla entera escondida detras de un atajo
/// del Panel es una pantalla que nadie abre — y esta es la que se usa para
/// cuadrar la caja.
///
/// Asi que el patron se sigue salvo donde se equivoca, y aqui se equivocaba. Si
/// alguna vez hay que quitarla del menu, que sea por una razon y no por copiar.
PantallaRegistrada registrarInformes() => PantallaRegistrada(
  ruta: '/reports',
  titulo: 'Reportes',
  icono: Icons.assessment_outlined,
  enElMenu: true,
  colecciones: ColeccionesDePantalla.informes,
  construir: (contexto, estado) => const PantallaInformes(),
);
