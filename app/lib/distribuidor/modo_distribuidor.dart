// EL MODO DISTRIBUIDOR: «Reparto Distribuidor», la segunda entrada de la app
// (`lib/main_distribuidor.dart`, `docs/app-distribuidor.md`).
//
// Es una constante de la aplicacion y no un ajuste: se decide en el `main` con
// un `override` y no cambia mientras la app esta abierta. Con el valor por
// defecto (`false`) Reparto se comporta EXACTAMENTE como siempre.
//
// Lo que cambia con `true` en las pantallas de Rutas que se reutilizan:
//  - no hay «+ Nueva Ruta», ni filtros, ni «Eliminar», ni «Quitar de ruta», ni
//    reordenar paradas, ni pre-despacho, ni importes (decision A del plan: la app
//    no sabe importes de factura);
//  - la ruta se completa SOLA al marcar la ultima parada (no hay «Marcar como
//    completada»);
//  - una ruta en curso se enseña guiada: la parada actual y nada mas.
//
// El servidor es quien manda de verdad (403 `no_es_para_el_distribuidor`); esto
// solo evita enseñar botones que daran un «no».
import 'package:flutter_riverpod/flutter_riverpod.dart';

final modoDistribuidorProvider = Provider<bool>((ref) => false);
