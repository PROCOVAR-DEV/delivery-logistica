// LAS PANTALLAS DE «REPARTO DISTRIBUIDOR»: la lista minima. Nada de tablero,
// pedidos, clientes, vehiculos, informes ni ajustes; y nada de descargar mapas.
import 'package:flutter/material.dart';

import '../navegacion/pantalla_registrada.dart';
import '../navegacion/portero.dart' show rutaDeAcceso;
import '../nucleo/frescura/colecciones_de_cada_pantalla.dart';
import '../pantallas/rutas/registro.dart';
import 'dispositivo/pantalla_anadir_ruta.dart';

const rutaDelEnlace = '/r/:token';
const rutaDeAnadirRuta = '/anadir-ruta';

List<PantallaRegistrada> pantallasDelDistribuidor() => <PantallaRegistrada>[
  // LA PUERTA: no hay usuario ni contrasena. Sin ninguna ruta, solo se puede pegar el
  // enlace; si se llego por un enlace (`volverA`), se reclama solo.
  PantallaRegistrada(
    ruta: rutaDeAcceso,
    titulo: 'Añadir ruta',
    enElMenu: false,
    conArmazon: false,
    colecciones: ColeccionesDePantalla.ninguna,
    construir: (contexto, estado) => PantallaAnadirRuta(
      enlaceInicial: estado.uri.queryParameters['volverA'],
    ),
  ),
  // Un enlace abierto con la app ya dentro (otra ruta del mismo distribuidor).
  PantallaRegistrada(
    ruta: rutaDelEnlace,
    titulo: 'Añadir ruta',
    enElMenu: false,
    conArmazon: false,
    colecciones: ColeccionesDePantalla.ninguna,
    construir: (contexto, estado) =>
        PantallaAnadirRuta(enlaceInicial: estado.pathParameters['token']),
  ),
  registrarRutas(),
  PantallaRegistrada(
    ruta: rutaDeAnadirRuta,
    titulo: tituloAgregarRuta,
    icono: Icons.add_road,
    enElMenu: true,
    colecciones: ColeccionesDePantalla.ninguna,
    construir: (contexto, estado) => const PantallaAnadirRuta(),
  ),
];
