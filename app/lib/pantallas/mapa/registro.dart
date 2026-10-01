import 'package:flutter/material.dart';

import '../../navegacion/pantalla_registrada.dart';
import '../../nucleo/frescura/colecciones_de_cada_pantalla.dart';
import '../../nucleo/plataforma.dart';
import 'pantalla_mapa_sin_conexion.dart';

/// El registro del Mapa sin conexión. El contrato está en
/// `navegacion/pantalla_registrada.dart`.
///
/// **`enElMenu` depende del destino, y es la regla 1 de `CLAUDE.md`.** En la web
/// no se enseña: quien abre un navegador tiene servidor detrás, siempre, así que
/// una entrada de menú que lleva a «descarga el mapa de Cuba» le explicaría algo
/// que en su caso nunca pasa — que es exactamente lo que Jose ha tenido que
/// pedir que se quite tres veces.
///
/// **La ruta sí existe en los cuatro destinos**, y a propósito: si la entrada se
/// quita pero la ruta también, abrir el enlace en la web daría un 404 de la
/// aplicación en vez de una pantalla que explica por qué eso no va con ella. La
/// pantalla trata el caso (`MapaNoAplica`) y lo dice con palabras.
/// El camino de la pantalla, en UN SOLO SITIO.
///
/// Lo usa también el aviso del detalle de la ruta («Sin el mapa de Cuba
/// descargado…»), y una cadena repetida a mano en dos pantallas es como se
/// acaba navegando a una ruta que se movió — el §3-quater de `CLAUDE.md` con
/// otra cara.
const caminoDelMapaSinConexion = '/mapa-sin-conexion';

PantallaRegistrada registrarMapaSinConexion() => PantallaRegistrada(
  ruta: caminoDelMapaSinConexion,
  titulo: TextosDelMapaGuardado.titulo,
  icono: Icons.map_outlined,
  enElMenu: Destino.trabajaSinConexion,
  // NINGUNA: el mapa son teselas en disco, no una coleccion de la
  // sincronizacion. De cuando es lo guardado lo dice la propia pantalla.
  colecciones: ColeccionesDePantalla.ninguna,
  construir: (contexto, estado) => const PantallaMapaSinConexion(),
);
