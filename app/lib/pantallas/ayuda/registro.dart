import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../navegacion/pantalla_registrada.dart';
import '../../nucleo/frescura/colecciones_de_cada_pantalla.dart';
import 'vista/pantalla_guia.dart';

export 'vista/pantalla_guia.dart' show PantallaGuia, TextosDeLaGuia;

/// LA GUIA EN EL REGISTRO. El contrato esta en
/// `navegacion/pantalla_registrada.dart`.
///
/// ## En el menu, en las TRES formas
///
/// A diferencia del mapa sin conexion y de Sincronizacion, esta entrada **no
/// depende del destino**: el logistico de la oficina con su navegador necesita la
/// guia igual que el que se va al patio de un almacen. Lo que cambia es **lo que
/// la guia ensena** —la APK no ensena la guia del escritorio ni al reves—, y eso
/// se decide dentro, en `datos/proveedores.dart`, contra la misma
/// `Destino.trabajaSinConexion` de la regla 1.
///
/// Jose: «estas tareas me las agregas a el side bar para q puedan ir cuando
/// quieran».
///
/// ## `colecciones: ninguna`, y es una decision escrita
///
/// La guia **no lee nada de la copia**: su contenido viaja horneado en
/// `assets/manual/manual.txt` y se lee con `rootBundle`. La hora de la ultima
/// bajada no dice absolutamente nada de si el manual esta al dia, asi que medir la
/// franja contra cualquier coleccion seria poner un aviso ambar sobre una pantalla
/// que no puede estar desactualizada. Igual que Acceso y Sincronizacion, se
/// declara con nombre y no se deja en blanco (§4: «borrar no es decidir»).
PantallaRegistrada registrarGuia() => const PantallaRegistrada(
  ruta: PantallaGuia.ruta,
  titulo: TextosDeLaGuia.titulo,
  // El libro abierto, que es lo que hay detras. No se repite ningun glifo del
  // menu: Panel, Tablero, Rutas, Pedidos, Clientes, Vehiculos, Almacenes,
  // Sincronizacion, Mapa y Reportes llevan cada uno el suyo.
  icono: Icons.menu_book_outlined,
  enElMenu: true,
  colecciones: ColeccionesDePantalla.ninguna,
  construir: _construir,
);

Widget _construir(BuildContext contexto, GoRouterState estado) =>
    const PantallaGuia();
