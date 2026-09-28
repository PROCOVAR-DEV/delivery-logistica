/// LO QUE LLEGA SUCIO DE FUERA, limpiado en el último momento antes de pintarlo.
///
/// **Esto es la SEGUNDA línea de defensa, no la primera.** La primera está en el servidor
/// (`api/internal/espejo/comilla_de_excel.go`, `SinLaComillaDeExcel`), que es donde se
/// arregla para todos los consumidores de una vez: el tablero, la ficha, el papel del
/// pre-despacho, el mensaje al chofer y cualquier informe que salga mañana. Si la limpieza
/// viviera sólo aquí, el dato seguiría sucio en la base y en el PDF, y el día que alguien
/// pinte una pantalla nueva volvería a salir.
///
/// Está de todas formas porque la base local ya tiene dentro lo que bajó antes del arreglo,
/// y quien mira un teléfono en el cajón de mover un pedido no tiene por qué esperar a que
/// pase un ciclo.
library;

/// Quita la comilla simple que Excel y los CSV ponen DELANTE de un número para que no lo
/// conviertan — `'+53 5 2675220` sale como `+53 5 2675220`.
///
/// **Es la MISMA regla que la del servidor**, a propósito y letra por letra: la comilla se
/// quita sólo cuando lo que queda detrás no puede ser un nombre, o sea cuando son dígitos y
/// la puntuación con la que se escriben teléfonos, folios y fechas, y hay al menos un
/// dígito. Un apellido que empieza por apóstrofo —`'t Hooft`— no se toca, y un `O'Brien`
/// tampoco, porque ahí la comilla no va delante.
///
/// Que las dos copias digan lo mismo está atado con una prueba y no con este comentario
/// (§3-bis): `test/nucleo/la_comilla_de_excel_test.dart` repite los mismos casos que
/// `api/internal/espejo/la_comilla_de_excel_test.go`.
String sinLaComillaDeExcel(String texto) {
  if (!texto.startsWith("'")) return texto;
  final resto = texto.substring(1).trim();
  return _pareceUnNumero(resto) ? resto : texto;
}

/// [sinLaComillaDeExcel] sobre algo que puede no estar. `null` se queda `null`: «no vino» y
/// «vino vacío» no son lo mismo.
String? sinLaComillaDeExcelODejarlo(String? texto) =>
    texto == null ? null : sinLaComillaDeExcel(texto);

/// Sólo dígitos y la puntuación de un número. Una sola letra basta para que conteste que no,
/// y eso es lo que protege los nombres de cliente de verdad.
bool _pareceUnNumero(String texto) {
  if (texto.isEmpty) return false;
  var hayDigito = false;
  for (final unidad in texto.codeUnits) {
    const cero = 0x30, nueve = 0x39;
    if (unidad >= cero && unidad <= nueve) {
      hayDigito = true;
      continue;
    }
    // espacio + - ( ) . / ,
    const puntuacion = <int>{0x20, 0x2B, 0x2D, 0x28, 0x29, 0x2E, 0x2F, 0x2C};
    if (!puntuacion.contains(unidad)) return false;
  }
  return hayDigito;
}
