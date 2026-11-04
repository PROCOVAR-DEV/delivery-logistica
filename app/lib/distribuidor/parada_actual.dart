// LA PARADA ACTUAL de una ruta en curso: la primera SIN resultado, por el orden
// de la ruta (`stop_order`). Es lo unico que decide «a donde voy ahora» y por
// eso es una funcion pura y probada suelta.
//
// Las paradas que llegan de `paradasDe` ya vienen ordenadas, pero esto no se
// fia: un orden distinto entre dos pantallas enseñaria dos «siguientes».
import '../nucleo/base/base.dart';

/// Las paradas en el orden de visita: por `stopOrder` (las sin numero, al
/// final) y, a igualdad, por cliente, igual que `ConsultasRutas.paradasDe`.
List<Pedido> enOrdenDeVisita(List<Pedido> paradas) {
  final orden = [...paradas];
  orden.sort((a, b) {
    final x = a.stopOrder, y = b.stopOrder;
    if (x != y) {
      if (x == null) return 1;
      if (y == null) return -1;
      return x.compareTo(y);
    }
    return a.customerName.compareTo(b.customerName);
  });
  return orden;
}

/// La siguiente parada por hacer, o `null` si ya no queda ninguna (o la ruta no
/// tiene paradas).
Pedido? siguienteParada(List<Pedido> paradas) {
  for (final p in enOrdenDeVisita(paradas)) {
    if (p.resultado == null) return p;
  }
  return null;
}

/// Cuantas paradas tienen ya su resultado.
int paradasHechas(List<Pedido> paradas) =>
    paradas.where((p) => p.resultado != null).length;

/// ¿Todas las paradas tienen resultado? Una ruta SIN paradas no se completa
/// sola: no hay nada que lo demuestre y el logistico la tiene que mirar.
bool todasMarcadas(List<Pedido> paradas) =>
    paradas.isNotEmpty && paradas.every((p) => p.resultado != null);

/// Desde cuando corre el cronometro de la parada actual: la hora de la ULTIMA
/// marca hecha en esta ruta, o la salida de la ruta si aun no hay ninguna.
/// Todo con la hora del aparato (`resultadoAt`).
DateTime? inicioDeLaParada(List<Pedido> paradas, DateTime? salidaDeLaRuta) {
  DateTime? ultima;
  for (final p in paradas) {
    final a = p.resultadoAt;
    if (a != null && (ultima == null || a.isAfter(ultima))) ultima = a;
  }
  return ultima ?? salidaDeLaRuta;
}

/// «1:05:09» / «12:03»: para el cronometro. Nunca negativo (un reloj que se
/// atrasa no puede enseñar tiempo al reves).
String cronometro(Duration d) {
  final t = d.isNegative ? Duration.zero : d;
  String dos(int n) => n.toString().padLeft(2, '0');
  final h = t.inHours;
  final m = t.inMinutes.remainder(60);
  final s = t.inSeconds.remainder(60);
  return h > 0 ? '$h:${dos(m)}:${dos(s)}' : '${dos(m)}:${dos(s)}';
}
