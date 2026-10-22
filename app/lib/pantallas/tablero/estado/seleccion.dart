import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Las facturas de «Sin colocar» marcadas para colocarlas en una zona de un
/// golpe (issue 21 de Maikel, Santiago: «cuando son los municipios es poco
/// práctico añadir de 1 en 1»).
///
/// Es LOCAL y no se guarda, como `seleccionPedidosProvider`. Guarda ids; lo que
/// se coloca es siempre esto CRUZADO con lo que la lista enseña ahora
/// (`PanelSinColocar`), así que una marca que un filtro esconde no viaja.
class SeleccionTablero extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void alternar(String id) {
    final copia = {...state};
    if (!copia.remove(id)) copia.add(id);
    state = copia;
  }

  /// La casilla de la cabecera: marca o desmarca **las que se ven**.
  void marcar(Iterable<String> ids, {required bool marcar}) =>
      state = marcar ? {...state, ...ids} : ({...state}..removeAll(ids));

  void quitar(Iterable<String> ids) => state = {...state}..removeAll(ids);

  void limpiar() => state = <String>{};
}

final seleccionTableroProvider =
    NotifierProvider<SeleccionTablero, Set<String>>(SeleccionTablero.new);
