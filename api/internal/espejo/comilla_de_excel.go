package espejo

import "strings"

// LA COMILLA QUE PONE EXCEL DELANTE DE UN NÚMERO — 28/09/2026.
//
// Jose, en un SM-A165M, abriendo el cajón de mover un pedido del tablero: el teléfono del
// cliente salía `'+53 5 2675220`, con una comilla simple pegada delante. No es un adorno de
// la pantalla: es el dato, tal cual entró.
//
// De dónde sale: cuando un número se escribe en Excel o se exporta a CSV con una comilla
// simple delante, esa comilla es la orden de «esto es TEXTO, no lo conviertas». Sirve para
// que `+53 5 2675220` no se coma el `+` ni se vuelva `5.32675e+10`, y para que un folio de
// ceros a la izquierda los conserve. La comilla es de la hoja de cálculo y muere ahí — pero
// si alguien pega esa columna en el maestro de PEDIDO, viaja con el dato hasta aquí, y aquí
// nadie la quitaba.
//
// # POR QUÉ ES CONSERVADORA, Y HASTA DÓNDE LLEGA
//
// Quitar la comilla de un teléfono es seguro. Quitar caracteres a lo bruto de cualquier
// texto NO lo es: hay apellidos que empiezan por apóstrofo —`'t Hooft`—, y un nombre de
// cliente roto es un pedido que el chofer no encuentra. Así que la comilla se quita **sólo
// cuando lo que queda detrás no puede ser un nombre**: lo que sobra tiene que ser un número
// —con sus espacios, sus `+`, sus guiones, sus paréntesis, sus puntos y sus barras— y tener
// al menos un dígito.
//
//	`'+53 5 2675220`  -> `+53 5 2675220`   (teléfono)
//	`'0012`           -> `0012`            (folio con ceros delante)
//	`'2026-09-28`     -> `2026-09-28`      (fecha de una columna de Excel)
//	`'t Hooft`        -> `'t Hooft`        (tiene letras: NO se toca)
//	`O'Brien`         -> `O'Brien`         (la comilla no va delante: NO se toca)
//	`'`               -> `'`               (no queda ningún dígito detrás: NO se toca)
//
// Lo que NO cubre, y se sabe: una marca de tiempo ISO —`'2026-09-28T15:03:00Z`— lleva `T` y
// `Z`, o sea letras, así que se queda con su comilla. Es a propósito: ensanchar la regla
// para colar dos letras concretas es el primer paso para que acabe quitando comillas de
// nombres. Si aparece, se arregla nombrando ese caso, no relajando éste.
//
// **Y NO SE APLICA A LAS IDENTIDADES.** El `externalId` del pedido y el del cliente entran
// sin pasar por aquí. Si una identidad llegara sucia, llegaría sucia SIEMPRE y casaría
// consigo misma; limpiarla ahora partiría en dos cada fila ya guardada —la vieja con
// comilla, la nueva sin ella— y duplicaría el padrón. Un dato feo que casa es mejor que un
// dato limpio que no casa.
func SinLaComillaDeExcel(s string) string {
	if !strings.HasPrefix(s, "'") {
		return s
	}
	resto := strings.TrimSpace(s[1:])
	if !pareceUnNumero(resto) {
		return s
	}
	return resto
}

// pareceUnNumero: sólo dígitos y la puntuación con la que se escriben teléfonos, folios y
// fechas. Una sola letra basta para que esto conteste que no.
func pareceUnNumero(s string) bool {
	if s == "" {
		return false
	}
	hayDigito := false
	for _, r := range s {
		switch {
		case r >= '0' && r <= '9':
			hayDigito = true
		case r == ' ' || r == '+' || r == '-' || r == '(' || r == ')' ||
			r == '.' || r == '/' || r == ',':
			// puntuación de números; sigue
		default:
			return false
		}
	}
	return hayDigito
}
