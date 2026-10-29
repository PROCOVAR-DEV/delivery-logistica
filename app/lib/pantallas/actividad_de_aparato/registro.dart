import 'package:flutter/material.dart';

import '../../navegacion/pantalla_registrada.dart';
import '../../nucleo/frescura/colecciones_de_cada_pantalla.dart';
import 'vista/pantalla_actividad_de_aparato.dart';

/// El registro de «Actividad del aparato». El contrato está en `navegacion/pantalla_registrada.dart`.
///
/// **Fuera del menú**: se llega desde «Ver actividad» de Dispositivos en Accesos (`/dispositivos?aparato=<id>`). Y en las cuatro formas,
/// web incluida: es una lectura de oficina, no la cola de nadie (CLAUDE.md §1, la misma razón que la bandeja de revisión). Lo que el
/// servidor deja ver lo decide `sync` por la sucursal de quien pregunta; esto no es un permiso.
PantallaRegistrada registrarActividadDeAparato() => PantallaRegistrada(
  ruta: PantallaActividadDeAparato.ruta,
  titulo: 'Actividad del aparato',
  icono: Icons.devices_outlined,
  enElMenu: false,
  // NINGUNA: lee EN VIVO de `sync` y habla de lo que hicieron otros aparatos, no de esta copia.
  colecciones: ColeccionesDePantalla.ninguna,
  construir: (contexto, estado) => PantallaActividadDeAparato(
    instalacion: estado.uri.queryParameters['aparato'],
  ),
);
