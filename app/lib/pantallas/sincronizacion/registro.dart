import 'package:flutter/material.dart';

import '../../navegacion/pantalla_registrada.dart';
import '../../nucleo/frescura/colecciones_de_cada_pantalla.dart';
import '../../nucleo/plataforma.dart';
import 'datos/panel_sincronizacion.dart';
import 'vista/pantalla_sincronizacion.dart';

/// El registro de Sincronización. El contrato está en
/// `navegacion/pantalla_registrada.dart`.
///
/// **`enElMenu` depende del destino, y es la regla 1 de `CLAUDE.md`.** Aquí
/// estuvo en `true` fijo, con su motivo escrito, y el motivo estaba mal: lo que
/// esta pantalla enseña son **aparatos y su cola** —quién lleva sin subir, qué
/// le queda pendiente y qué se le rechazó—, o sea el aparato de prepararse para
/// quedarse sin señal. Eso es de la APK y del escritorio.
///
/// > «el trabajo sin conexion es solo para las aplicaciones cojone la web
/// > siempre va a estar en internet»
///
/// Y no era sólo una regla escrita: medido en producción el 22/09/2026, la
/// entrada del menú en la web no llegaba ni a abrirse. `GET /sync/estado`
/// contestaba `401` —el sincronizador habla con aparatos dados de alta, y un
/// navegador no lo es—, el cliente daba la sesión por muerta y el portero
/// mandaba a `/acceso?volverA=/sincronizacion`, que volvía a entrar y volvía a
/// pedir: treinta peticiones en poco más de un minuto. **Un rechazo permanente
/// contra un reintentador es un bucle, no una defensa.**
///
/// **La ruta sí sigue existiendo en los cuatro destinos**, y a propósito, igual
/// que el mapa sin conexión (`pantallas/mapa/registro.dart`): quitar la ruta
/// dejaría a quien tenga el enlace guardado delante de un «No hay ninguna
/// pantalla en /sincronizacion», que no explica nada. La pantalla trata el caso
/// y lo dice con palabras — y, sobre todo, **en la web no pide nada al
/// servidor**, que es lo que corta el bucle.
PantallaRegistrada registrarSincronizacion() => PantallaRegistrada(
  ruta: PantallaSincronizacion.ruta,
  titulo: TextosDeSincronizacion.titulo,
  icono: Icons.sync_outlined,
  enElMenu: Destino.trabajaSinConexion,
  // NINGUNA: esta pantalla lee EN VIVO del servidor (`GET /sync/estado`) y
  // habla de los telefonos, no de esta copia. La hora de una bajada de aqui
  // no dice nada de lo que se esta mirando.
  colecciones: ColeccionesDePantalla.ninguna,
  construir: (contexto, estado) => const PantallaSincronizacion(),
);
