/// ELEGIR UNA ZONA DEL TABLERO DESDE EL ASISTENTE, con su camion detras.
///
/// El camino contrario ya existe y funciona: desde el tablero, el menu ⋮ de una
/// zona tiene «Armar la ruta de esta zona». Esto es el mismo gesto **desde el
/// otro lado**, para quien ya esta dentro del asistente. Jose, 22/09/2026:
///
/// > «recuerda desde la ruta poder utilizar estos tableros q sean como los
/// > pedidos pero q tengo un seleccionar con dropdown q tenga todos los pedidos
/// > y de ahi selecciono el tablero y ya selecciono los pedidos de ese tablero
/// > ya tendria el camion preparado»
///
/// **El reparto de la zona NO se vuelve a escribir aqui.** Quien decide que
/// entra y que no —y por que no— es `repartirLaZona`, en `meter_la_zona.dart`,
/// el mismo que usan las fichas. Dos maneras de sacar los pedidos de una zona
/// son dos resultados distintos el dia que una se quede atras, y la que se
/// quede atras sera la que nadie mire.
///
/// Lo de aqui es lo que ese reparto NO cubre y este gesto necesita:
///
/// 1. **que zonas se pueden ofrecer** (`zonasParaArmar`),
/// 2. **acotar la lista de disponibles a una de ellas** (`soloDeLaZona`), y
/// 3. **que camion queda puesto** cuando la zona trae uno (`camionDeLaZona`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/numeros.dart';
import '../../../nucleo/base/base.dart';
import '../../tablero/datos/modelos.dart';
import '../../tablero/estado/proveedores.dart';

/// Una zona del tablero, vista desde el asistente.
class ZonaParaArmar {
  const ZonaParaArmar({
    required this.id,
    required this.nombre,
    required this.ids,
    required this.pesoKg,
    this.vehiculoId,
    this.vehiculoNombre,
  });

  final String id;
  final String nombre;

  /// Los pedidos puestos en la zona, **en el orden que dejo el logistico**: es
  /// el orden de visita que el propone, y el que conoce las calles es el, no el
  /// vecino mas proximo (`docs/tablero.md` §5.4).
  final List<String> ids;

  /// El peso que da la base para la zona, **no la suma de lo pintado**: la
  /// pantalla pagina y el camion no (`docs/tablero.md` §3).
  final double pesoKg;

  /// El camion previsto de la zona, si se eligio uno. Es lo que la columna
  /// ensena como «Camión: Vehiculo HAB».
  final String? vehiculoId;
  final String? vehiculoNombre;

  int get pedidos => ids.length;

  /// LO QUE SE LEE EN EL DESPLEGABLE: «Vista · 12 pedidos · 340 kg».
  ///
  /// La zona **dice lo que lleva**. Un desplegable con doce nombres de barrio y
  /// nada mas obliga a salir del asistente, abrir el tablero y volver para
  /// saber cual es la que tenia el dia entero preparado.
  ///
  /// El numero son los pedidos **puestos**, no los que van a entrar: cuantos de
  /// estos se pueden meter ahora mismo lo dice el parte de `repartirLaZona` al
  /// elegirla, con su motivo, que es donde se puede decir por que faltan.
  String get etiqueta =>
      '$nombre · $pedidos ${pedidos == 1 ? 'pedido' : 'pedidos'} · '
      '${Numeros.kgRedondeado(pesoKg)}';
}

/// LAS ZONAS QUE SE PUEDEN OFRECER EN ESTE ASISTENTE.
///
/// Sale la lista **solo si el tablero cargado es el de la sucursal del paso 1**.
/// Ensenar las zonas de Santiago mientras se arma una ruta de La Habana seria
/// ofrecer pedidos que no son de esta ruta, y aceptarlos es un rechazo al
/// guardar.
///
/// Las zonas vacias no salen: elegir una que no tiene nada dentro solo puede
/// dejar la lista de disponibles en blanco.
List<ZonaParaArmar> zonasParaArmar(Tablero? tablero, String? sucursalId) {
  if (tablero == null ||
      tablero.problema != null ||
      sucursalId == null ||
      tablero.sucursalId != sucursalId) {
    return const <ZonaParaArmar>[];
  }

  final zonas = <ZonaParaArmar>[];
  for (final columna in tablero.columnas) {
    final puestas = tablero.deColumna(columna.id);
    if (puestas.isEmpty) continue;
    zonas.add(
      ZonaParaArmar(
        id: columna.id,
        nombre: columna.nombre,
        ids: [for (final t in puestas) t.pedido.pedidoId],
        pesoKg: columna.pesoKg,
        vehiculoId: columna.vehiculoId,
        vehiculoNombre: columna.vehiculoNombre,
      ),
    );
  }
  return zonas;
}

/// LA LISTA DE DISPONIBLES, ACOTADA A UNA ZONA.
///
/// Con zona elegida la lista de abajo deja de ser «todo lo que se puede
/// repartir» y pasa a ser «lo de esta zona», que es lo que se va a marcar. Sin
/// zona no toca nada: la misma lista de siempre.
///
/// **Se respeta el orden de la zona**, no el de la consulta de disponibles: la
/// zona viene ordenada por el orden de visita que propuso el logistico, y verla
/// aqui en otro orden es perder ese trabajo en el ultimo paso.
///
/// Lo que esta en la zona y no esta disponible **no se inventa**: no sale, por
/// lo mismo que no entra en el reparto —ya se lo llevo otra ruta, o se
/// archivo—. Cuantos son y por que se dice en el parte de `repartirLaZona`.
List<Pedido> soloDeLaZona(List<Pedido> disponibles, ZonaParaArmar? zona) {
  if (zona == null) return disponibles;
  final porId = {for (final p in disponibles) p.id: p};
  return [
    for (final id in zona.ids)
      if (porId[id] != null) porId[id]!,
  ];
}

/// QUE PASA CON EL CAMION AL ELEGIR UNA ZONA.
class CamionDeLaZona {
  const CamionDeLaZona({
    required this.vehiculoId,
    required this.cambia,
    required this.choca,
    required this.parte,
    this.devuelve,
  });

  /// El vehiculo que queda puesto en el paso 3 despues del gesto.
  final String? vehiculoId;

  /// ¿Hay que tocar el paso 3?
  final bool cambia;

  /// La zona trae un camion y la persona habia elegido otro **a mano**. Se
  /// cambia igual —para eso se elige la zona— pero **se dice**, y se le deja
  /// deshacerlo de un toque.
  final bool choca;

  /// Lo que se le anade al parte de la zona. `null` = no hay nada que decir.
  final String? parte;

  /// El camion que la persona habia elegido a mano, para el boton de «Dejar el
  /// mío». Solo cuando [choca].
  final String? devuelve;
}

/// EL CAMION VIENE PREPARADO — y nada cambia en silencio.
///
/// «ya tendria el camion preparado» es media peticion: una zona del tablero ya
/// lleva camion previsto, y traerlo es el ahorro entero de este gesto.
///
/// Las cuatro situaciones, y por que cada una:
///
/// - **La zona no trae camion.** No se toca nada. Sin camion previsto el
///   tablero no dice «ninguno», dice «todavia no se sabe» (`docs/tablero.md`
///   §7.3), y borrar con un «no se sabe» lo que alguien ya eligio es perder un
///   dato a cambio de nada.
/// - **El camion previsto no es de los que ofrece el paso 3.** No se trae, y se
///   dice por que. Ver [vehiculosDeLaRuta] abajo.
/// - **Es el mismo, o todavia no habia ninguno.** Se pone el de la zona y no
///   hay nada que advertir.
/// - **Habia otro.** *Se cambia igual*, y **se dice**, con los dos nombres y un
///   boton de «Dejar el mío» al lado.
///
///   Por que se cambia y no al reves, que fue el primer intento: **al paso 4 no
///   se llega sin camion**. El paso 3 no deja pasar sin elegir uno, asi que
///   cuando alguien abre este desplegable SIEMPRE hay uno puesto a mano, y una
///   regla de «lo que puso la persona no se toca» dejaria el camion de la zona
///   sin traerse nunca — es decir, sin hacer lo que Jose pidio.
///
///   Y elegir la zona **es** una decision de una persona, posterior y mas
///   concreta que la del paso 3: dice «esto es lo que yo preparé». El camion
///   previsto de la zona es una intencion de media manana (`docs/tablero.md`
///   §7.3), pero es la intencion de quien esta armando y sobre los pedidos que
///   esta metiendo ahora.
///
///   Lo que no puede pasar —y esto es lo que sostiene la decision— es que
///   cambie **sin decirlo**: la capacidad del camion es la regla que decide que
///   pedidos caben (`repartirLaZona` la usa, la barra de peso la pinta y las
///   filas que no caben se apagan con el motivo delante). Por eso el cambio
///   viaja con su parte —los dos nombres— y con la vuelta atras de un toque. Y
///   por eso el camion se pone **antes** de repartir: repartir con el de antes
///   para cambiarlo despues deja fuera pedidos que si cabian.
///
///   El camion que trajo una zona anterior ([elegidoAMano] `false`) se cambia
///   sin decir nada: no era la decision de nadie, era el camion de la zona que
///   acaba de dejar de estar elegida.
///
/// [vehiculosDeLaRuta] son los vehiculos que el paso 3 ofrece de verdad (los de
/// **esta** sucursal y activos). Un camion previsto que no este
/// entre ellos no se trae: el selector no podria ensenarlo y quedaria un id
/// puesto que nadie ve. Pasa con un camion de otra sucursal, y un camion de
/// Granma en una ruta de La Habana es un camion que no esta donde sale la ruta.
///
/// [noSeOfrecen] son los ids de los camiones que el paso 3 NO ofrece **aunque
/// sean de esta sucursal**: los dados de baja. Sirve para una
/// sola cosa, decir el motivo de verdad: una zona con un camion inactivo no es
/// una zona de «otra sucursal», y decirlo asi manda a buscar donde no es.
CamionDeLaZona camionDeLaZona({
  required ZonaParaArmar? zona,
  required String? elegidoId,
  required String? elegidoNombre,
  required bool elegidoAMano,
  required List<Vehiculo> vehiculosDeLaRuta,
  Set<String> noSeOfrecen = const <String>{},
}) {
  final deLaZona = zona?.vehiculoId;
  if (zona == null || deLaZona == null) {
    return CamionDeLaZona(
      vehiculoId: elegidoId,
      cambia: false,
      choca: false,
      parte: null,
    );
  }

  final enLaLista = vehiculosDeLaRuta
      .where((v) => v.id == deLaZona)
      .firstOrNull;
  if (enLaLista == null) {
    return CamionDeLaZona(
      vehiculoId: elegidoId,
      cambia: false,
      choca: false,
      parte: noSeOfrecen.contains(deLaZona)
          ? 'El camión de «${zona.nombre}» está inactivo y no '
                'se ofrece para rutas nuevas: se queda el que elegiste'
          : 'El camión de «${zona.nombre}» no es de esta sucursal: se queda el '
                'que elegiste',
    );
  }

  final nombre = zona.vehiculoNombre ?? enLaLista.name;

  if (elegidoId == deLaZona) {
    return CamionDeLaZona(
      vehiculoId: elegidoId,
      cambia: false,
      choca: false,
      parte: null,
    );
  }

  if (elegidoId == null || !elegidoAMano) {
    return CamionDeLaZona(
      vehiculoId: deLaZona,
      cambia: true,
      choca: false,
      parte: 'camión $nombre, el de la zona',
    );
  }

  return CamionDeLaZona(
    vehiculoId: deLaZona,
    cambia: true,
    choca: true,
    devuelve: elegidoId,
    parte:
        'el camión pasa de ${elegidoNombre ?? 'el que elegiste'} a $nombre, '
        'el de «${zona.nombre}»',
  );
}

/// Las zonas ofrecibles para la sucursal del paso 1.
///
/// Cuelga de `tableroProvider`, que es **el mismo tablero de la pantalla del
/// tablero**: la foto de la ultima bajada, con sus columnas y sus tarjetas. No
/// hay una segunda consulta de zonas, por lo de siempre: dos consultas sobre lo
/// mismo son dos respuestas distintas el dia que una se quede atras.
final zonasParaArmarProvider = Provider.family<List<ZonaParaArmar>, String?>(
  (ref, sucursalId) =>
      zonasParaArmar(ref.watch(tableroProvider).value, sucursalId),
);
