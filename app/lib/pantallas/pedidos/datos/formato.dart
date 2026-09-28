// Numeros y fechas, en un solo sitio.
//
// **Por que vive aqui:** `lib/nucleo/formato/` (Dinero, Peso, Fechas) es de otra
// ola y todavia no existe; esta tarea sólo escribe en `lib/pantallas/`. Cuando se
// cree, esto se mueve y sólo cambian los `import`. Se deja lo minimo —lo que las
// dos pantallas pintan— para no adelantar decisiones de moneda que son de otro
// sitio.
//
// Los formatos van SIN locale explicito y con patron numerico (`d/M/y`) a
// proposito: es el mismo resultado en `es` y en `en`, y asi una prueba de widget
// no depende de que alguien haya cargado los datos de localizacion antes.

import 'package:intl/intl.dart';

final _fechaCorta = DateFormat('d/M/y');
final _fechaYHora = DateFormat('d/M/y, H:mm');

String fechaCorta(DateTime? cuando) =>
    cuando == null ? '—' : _fechaCorta.format(cuando);

String fechaYHora(DateTime? cuando) =>
    cuando == null ? '—' : _fechaYHora.format(cuando);

/// Kilos con un decimal: es lo que se lee en el almacen y lo que usa el mensaje
/// literal de sobrepeso del servidor.
String kg(double? valor) =>
    valor == null ? '—' : '${valor.toStringAsFixed(1)} kg';

/// Kilometros con dos decimales, como la distancia de los clientes.
String km(double? valor) =>
    valor == null ? '—' : '${valor.toStringAsFixed(2)} km';

/// Importes en USD. **`null` no es cero**: un cero es un precio y se lee como
/// «este domicilio es gratis», asi que quien no tiene precio lo dice con
/// palabras, no con un `0.00`.
String usd(double? valor) =>
    valor == null ? 'sin cotizar' : '\$${valor.toStringAsFixed(2)}';

/// Un numero de cuenta (empaques, unidades) sin decimales cuando es entero.
String cantidad(double valor) => valor == valor.roundToDouble()
    ? valor.round().toString()
    : valor.toStringAsFixed(2);

/// La duracion de una ruta: `3 h 20 min`.
///
/// **Una hora exacta se escribe `1 h`, no `1 h 0 min`.** Ese `0 min` colgando se
/// leyo en pantalla el 22/09/2026 y no es una errata de estilo: el unico sitio
/// donde esto se pinta es el renglon de datos del detalle, pegado por puntos a
/// los kilometros, el peso y el importe, y un cero suelto ahi dentro se lee como
/// un dato que falta. Los minutos se escriben cuando los hay.
String duracion(DateTime? desde, DateTime? hasta) {
  if (desde == null || hasta == null) return '—';
  final cuanto = hasta.difference(desde);
  if (cuanto.isNegative) return '—';
  final horas = cuanto.inHours;
  final minutos = cuanto.inMinutes % 60;
  if (horas == 0) return '$minutos min';
  return minutos == 0 ? '$horas h' : '$horas h $minutos min';
}

/// LO QUE LLEVA UNA RUTA, no sólo lo que duró — 28/09/2026.
///
/// [duracion] necesita las dos puntas, así que una ruta **en curso** —que es
/// justo la que alguien está mirando— salía `—`. Jose, viendo `RT-20260928-001`
/// con tres paradas en la calle: «mira todos los — que hay en la ruta y esos
/// datos debemos de tenerlo».
///
/// Y es un dato que sí se sabe: arrancó a una hora y son las que son. Va con su
/// palabra al lado —`2 h 15 min en ruta`— porque un número suelto ahí se leería
/// como lo que tardó, y la ruta no ha terminado.
///
/// El `ahora` entra por parámetro y no de `DateTime.now()`: así esto se prueba
/// con una hora fija, y la cabecera del detalle sigue sin necesitar un
/// `ProviderScope` para montarse.
String tiempoDeLaRuta({DateTime? arranco, DateTime? termino, DateTime? ahora}) {
  if (termino != null) return duracion(arranco, termino);
  if (arranco == null || ahora == null) return '—';
  final llevando = duracion(arranco, ahora);
  return llevando == '—' ? '—' : '$llevando en ruta';
}
