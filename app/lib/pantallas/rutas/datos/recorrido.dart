// EL RECORRIDO: la ruta reducida a lo justo para DIBUJARLA y para ARMAR EL
// ENLACE — el almacen de salida, las paradas en su orden y sus coordenadas.
//
// ## Por que hay un modelo aparte y no se pinta desde `RutaConTodo`
//
// `RutaConTodo` son filas de Drift: para montar una en una prueba hay que
// rellenar las cuarenta columnas de `orders`. El croquis y el enlace no
// necesitan ninguna de ellas salvo cuatro numeros y un nombre. Con un modelo
// propio, el dibujo y el enlace se prueban EN SECO —sin base, sin reloj falso y
// sin los cuelgues del §5 del `CLAUDE.md`—, y lo unico que toca Drift es
// [recorridoDe], que tiene su propia prueba contra una base de verdad.
//
// ## Las paradas SIN coordenadas siguen dentro
//
// Podrian filtrarse aqui y ahorrarse un nulo. No se hace, y es a proposito:
//
//  * el numero que se pinta en el croquis tiene que ser el mismo que el de la
//    hoja de cierre. Si las que no se pueden dibujar se saltaran, el «3» del
//    croquis seria el «4» de la hoja, y nadie sabria por que;
//  * hay que poder DECIR cuantas quedan fuera. Una parada que desaparece del
//    dibujo sin que nadie lo cuente es exactamente lo que prohibe la regla 4
//    («nada se descarta en silencio»).

import '../../../nucleo/base/base.dart';
import '../../informes/datos/consultas_informes.dart';
import '../../pedidos/datos/formato.dart' show facturaConFecha;
import 'geo.dart';
import 'repositorio_rutas.dart';

/// Una parada tal y como se dibuja y se enlaza.
class ParadaDelRecorrido {
  const ParadaDelRecorrido({
    required this.id,
    required this.numero,
    required this.etiqueta,
    this.factura,
    this.punto,
    this.importe,
    this.entregada = false,
    this.esRegreso = false,
  });

  final String id;

  /// El numero que se pinta: 1-based y **sobre TODAS las paradas**, tengan
  /// coordenadas o no (ver la cabecera del fichero).
  final int numero;

  /// Lo que se lee en el globo: el nombre del cliente.
  final String etiqueta;

  /// «Factura 47061 · 15/10/2026» (`facturaConFecha`), la primera línea del globo (issue 17
  /// de Amado), o `null` = el pedido no tiene número: el globo dice «Sin número de factura».
  final String? factura;

  /// `null` = esta parada no tiene coordenadas guardadas. Ni se dibuja ni entra
  /// en el enlace, y las dos cosas se dicen.
  final Punto? punto;

  /// Lo que se cobra por este domicilio. Va en el globo de la parada, como el
  /// `priceLabel` del `MapComponent.tsx` del patron.
  ///
  /// **`null` no es cero.** Un cero se lee como «este domicilio es gratis», que
  /// es un numero creible y equivocado (`formato.dart` lo dice con estas mismas
  /// palabras, y el `CLAUDE.md` §2 lo tiene como una de las tres veces que hay
  /// que separarse del patron).
  final double? importe;

  /// Ya cerrada como entregada. Se pinta distinto para que de un vistazo se vea
  /// por donde va el camion.
  final bool entregada;

  /// Va en el tramo de vuelta (`orders.trip_leg = 'return'`), como el
  /// `tripLeg === 'return'` del `MapComponent.tsx` del patron.
  final bool esRegreso;

  bool get seDibuja => punto != null;
}

/// La ruta lista para dibujar: de donde sale, por donde pasa y en que orden.
class Recorrido {
  const Recorrido({required this.paradas, this.origen, this.nombreDelOrigen});

  /// EL ALMACEN DE SALIDA, que es tambien el de llegada: el camion vuelve. Es
  /// lo mismo que pinta el patron con la estrella verde y `isOrigin`.
  ///
  /// `null` cuando la ruta se guardo sin coordenadas de origen. Entonces el
  /// croquis se dibuja igual —con lo que hay— pero **no hay enlace de Google
  /// Maps**, porque un enlace sin origen es un enlace roto.
  final Punto? origen;

  final String? nombreDelOrigen;

  /// EN ORDEN DE VISITA. Viene ya ordenado por `stopOrder` de
  /// `ConsultasRutas.mirarParadasDe`; aqui no se reordena nada.
  final List<ParadaDelRecorrido> paradas;

  /// Las que tienen coordenadas, en el mismo orden.
  List<ParadaDelRecorrido> get dibujables => [
    for (final p in paradas)
      if (p.seDibuja) p,
  ];

  /// Cuantas se quedan fuera del dibujo y del enlace por no tener coordenadas.
  int get sinCoordenadas => paradas.length - dibujables.length;

  /// Hay algo que pintar cuando hay al menos un punto: una parada, o el almacen
  /// solo (que ya dice donde arranca el dia).
  bool get hayAlgoQueDibujar => dibujables.isNotEmpty || origen != null;
}

/// De las filas de Drift al modelo dibujable. **Lo unico de este fichero que
/// sabe que existe una base.**
Recorrido recorridoDe(RutaConTodo ruta) {
  final origenLat = ruta.ruta.originLat;
  final origenLng = ruta.ruta.originLng;
  return Recorrido(
    origen: (origenLat == null || origenLng == null)
        ? null
        : Punto(origenLat, origenLng),
    nombreDelOrigen: ruta.sucursal?.name,
    paradas: [
      for (final (indice, parada) in ruta.paradas.indexed)
        ParadaDelRecorrido(
          id: parada.id,
          numero: indice + 1,
          etiqueta: parada.customerName,
          factura: facturaConFecha(parada.facturaNumero, parada.facturaAt),
          punto: (parada.endLat == null || parada.endLng == null)
              ? null
              : Punto(parada.endLat!, parada.endLng!),
          // EL GLOBO Y LA HOJA DE PARADAS CONTABAN DOS COSAS DISTINTAS.
          //
          // Aqui se leia `parada.price` a secas y el detalle pinta
          // `pedidoCosto`: dos columnas llamadas «el importe» de la misma
          // parada, y **no era a proposito**. `orders.price` es una COPIA de
          // `pedidoCosto` que se hace al enganchar el pedido a la ruta, y esa
          // copia PIERDE EL NULO: el servidor la guarda con
          // `price = coalesce(sqlc.narg('price'), 0)`
          // (`api/db/queries/routes.sql:283`; lo dice tambien
          // `api/internal/api/rutas.go:958`). O sea que una parada sin cotizar
          // acaba con `price = 0` y el globo decia **`$0.00`** mientras la hoja
          // de al lado decia «sin cotizar», sobre la misma parada.
          //
          // La regla es la que ya quedo fijada para Informes el 22/09/2026 y se
          // usa DE ALLI, no copiada: dos respuestas a lo mismo se separan sin
          // que salte nada si cada una tiene su copia (`CLAUDE.md` §3-bis), y
          // `ingresoDe` dice de si misma que se calcula «aqui y en ningun otro
          // sitio». Un `price` de cero sin `pedidoCosto` es ese `coalesce`, no
          // un precio; un `price` distinto de cero si es un cobro de verdad y
          // se respeta.
          importe: ConsultasInformes.ingresoDe(
            precio: parada.price,
            costo: parada.pedidoCosto,
          ),
          entregada: parada.resultado == ResultadoParada.entregado,
          esRegreso: parada.tripLeg == Tramo.regreso,
        ),
    ],
  );
}
