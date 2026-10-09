import 'package:flutter/material.dart';

import '../../navegacion/pantalla_registrada.dart';
import '../../nucleo/frescura/colecciones_de_cada_pantalla.dart';
import 'datos/quien_revisa.dart';
import 'vista/pantalla_revision.dart';

/// El registro de Revision. El contrato esta en
/// `navegacion/pantalla_registrada.dart`.
///
/// **En el menu solo para quien revisa** ([rolesQueRevisan]): ADMINISTRADOR,
/// SUPER ADMIN y DESARROLLADOR (Jose, 08/10/2026). A un logistico no se le ofrece
/// una bandeja sobre la que no puede decidir. Eso **no es un permiso** —el rol
/// viaja en el token—: el cerrojo es de `sync`, que contesta 403 al aplicar si
/// quien llama es el autor o no ve esa sucursal.
///
/// **En las cuatro formas, web incluida.** No es la cola de nadie: es un buzon de
/// oficina, y el administrador de oficina trabaja en el navegador. Pasa la prueba
/// de `CLAUDE.md` §1 («¿sirve de algo a alguien que tiene internet ahora
/// mismo?»): si, es justo para quien tiene internet.
PantallaRegistrada registrarRevision() => PantallaRegistrada(
  ruta: PantallaRevision.ruta,
  titulo: TextosDeRevision.titulo,
  icono: Icons.fact_check_outlined,
  enElMenu: true,
  soloParaRoles: rolesQueRevisan,
  // NINGUNA: lee EN VIVO de `sync` y habla de lo que hicieron otros aparatos,
  // no de esta copia. La hora de una bajada aqui no dice nada.
  colecciones: ColeccionesDePantalla.ninguna,
  construir: (contexto, estado) => const PantallaRevision(),
);
