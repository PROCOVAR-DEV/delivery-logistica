package api

import (
	"context"
	"net/http"
	"os"
	"regexp"
	"strings"
	"testing"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/store/sqlc"
)

// CADA ESCRITURA DEL TABLERO AVISA, para que la otra pantalla se entere sin esperar.
//
// El tablero es la única pantalla que dos personas miran a la vez: una arma zonas en el
// teléfono y otra las ve desde el navegador. Y era la única que no publicaba nada — sólo lo
// hacían el armador de rutas y el lote del espejo—, así que lo que se hacía en el móvil no
// aparecía en la web hasta que pasaba el temporizador de dos minutos o alguien refrescaba.
//
// Jose, 16/09/2026: «hice un tablero en el móvil, moví cosas, y en la web no salió en tiempo
// real, ¿por qué razón si eso debe pasar?».
func TestCadaEscrituraDelTableroAvisa(t *testing.T) {
	casos := []struct {
		nombre string
		hacer  func(t *testing.T, h http.Handler, jwt string)
	}{
		{"crear una zona", func(t *testing.T, h http.Handler, jwt string) {
			pedirTab(t, h, http.MethodPost, "/api/board/columns", jwt,
				`{"nombre":"Reparto Norte"}`)
		}},
		{"renombrarla", func(t *testing.T, h http.Handler, jwt string) {
			pedirTab(t, h, http.MethodPatch, "/api/board/columns/"+colCentro.String(), jwt,
				`{"nombre":"Centro Norte"}`)
		}},
		{"colocar un pedido", func(t *testing.T, h http.Handler, jwt string) {
			pedirTab(t, h, http.MethodPut, "/api/board/placements/"+ped1.String(), jwt,
				`{"columnaId":"`+colCentro.String()+`"}`)
		}},
		{"quitarlo", func(t *testing.T, h http.Handler, jwt string) {
			pedirTab(t, h, http.MethodDelete, "/api/board/placements/"+ped1.String(), jwt, "")
		}},
		{"borrar una zona vacía", func(t *testing.T, h http.Handler, jwt string) {
			pedirTab(t, h, http.MethodDelete, "/api/board/columns/"+colVacia.String(), jwt, "")
		}},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			h := montarTab(t, nuevoTablero())
			jwt := tokenTab(t, sucStg.String())

			var avisos int
			anterior := avisarCambioDelTablero
			avisarCambioDelTablero = func(context.Context, string) { avisos++ }
			t.Cleanup(func() { avisarCambioDelTablero = anterior })

			c.hacer(t, h, jwt)

			if avisos == 0 {
				t.Errorf("no avisó: lo que se hace aquí no aparece en la otra pantalla " +
					"hasta que pasen dos minutos o alguien refresque a mano")
			}
		})
	}
}

// Y lo que NO escribe no avisa: un aviso por cada lectura sería la pantalla recargándose
// sola en bucle.
func TestLeerElTableroNoAvisa(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	jwt := tokenTab(t, sucStg.String())

	var avisos int
	anterior := avisarCambioDelTablero
	avisarCambioDelTablero = func(context.Context, string) { avisos++ }
	t.Cleanup(func() { avisarCambioDelTablero = anterior })

	pedirTab(t, h, http.MethodGet, "/api/board?branchId="+sucStg.String(), jwt, "")
	pedirTab(t, h, http.MethodGet, "/api/board/unplaced?branchId="+sucStg.String(), jwt, "")

	if avisos != 0 {
		t.Errorf("avisó %d veces al LEER: la pantalla se recargaría sola en bucle", avisos)
	}
}

// Una escritura que el servidor RECHAZA tampoco avisa.
//
// Avisar de lo que no pasó manda a todas las pantallas abiertas a volver a pedir la lista
// para encontrarla igual. Con diez repartidores y la conexión de allá, eso no es gratis.
func TestUnaEscrituraRECHAZADANoAvisa(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	jwt := tokenTab(t, sucStg.String())

	var avisos int
	anterior := avisarCambioDelTablero
	avisarCambioDelTablero = func(context.Context, string) { avisos++ }
	t.Cleanup(func() { avisarCambioDelTablero = anterior })

	// «Centro» ya existe: choca con el índice único del nombre.
	w := pedirTab(t, h, http.MethodPost, "/api/board/columns", jwt, `{"nombre":"Centro"}`)
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d, se esperaba 409: %s", w.Code, w.Body.String())
	}
	if avisos != 0 {
		t.Errorf("avisó %d veces de una zona que no se creó", avisos)
	}
}

// NINGUNA ESCRITURA DEL TABLERO SE QUEDA SIN AVISAR.
//
// Se mira el CÓDIGO y no se montan las rutas una por una, a propósito: lo que hay que
// impedir es que alguien añada un gesto nuevo —mover todo a otra columna, reordenar— y se
// le olvide el aviso. Montar los seis que hay hoy no cazaría el séptimo.
func TestNingunaEscrituraDelTableroSeQuedaSinAvisar(t *testing.T) {
	crudo, err := os.ReadFile("tablero.go")
	if err != nil {
		t.Fatal(err)
	}
	fuente := string(crudo)

	// Los manejadores que ESCRIBEN. Los de lectura van aparte y no deben avisar.
	// Los que ESCRIBEN de verdad. `putColumna` no está: sólo reparte entre
	// `reordenarColumnas` y un 405, y quien escribe es el de abajo. Meterlo aquí obligaría
	// a poner un aviso en un sitio donde no pasa nada.
	escriben := []string{
		"crearColumna", "actualizarColumna", "reordenarColumnas", "borrarColumna",
		"colocarPedido", "quitarPedidoDelTablero", "armarRutaDeColumna",
	}
	patron := regexp.MustCompile(`func \(s \*Servidor\) (\w+)\(w http\.ResponseWriter`)
	indices := patron.FindAllStringSubmatchIndex(fuente, -1)

	for i, idx := range indices {
		nombre := fuente[idx[2]:idx[3]]
		fin := len(fuente)
		if i+1 < len(indices) {
			fin = indices[i+1][0]
		}
		cuerpo := fuente[idx[0]:fin]

		var esDeEscritura bool
		for _, e := range escriben {
			if nombre == e {
				esDeEscritura = true
			}
		}
		if !esDeEscritura {
			continue
		}
		if !strings.Contains(cuerpo, "avisarCambioDelTablero(") {
			t.Errorf("%s escribe en el tablero y NO avisa: lo que haga esa persona no "+
				"aparecerá en la pantalla de al lado hasta dentro de dos minutos", nombre)
		}
		// Y AVISA CON LA SUCURSAL DE LA FILA, NO CON EL ALCANCE DE QUIEN LLAMÓ — 01/10/2026.
		//
		// `sucursalDelAlcance` es la fuente que falló en producción: el alcance de quien ve
		// las ocho es «todas», así que el aviso salía PELADO y las otras siete se bajaban el
		// tablero entero. Y para cualquier apunte que suba por la cola del teléfono da lo
		// mismo quién sea, porque el sincronizador no reenvía `X-Sucursal-Id`.
		//
		// Un manejador de este fichero que vuelva a tirar de ahí compila, pasa todas las
		// demás pruebas y deja el fallo puesto otra vez. Aquí no.
		if strings.Contains(cuerpo, "avisarCambioDelTablero(r.Context(), sucursalDelAlcance") {
			t.Errorf("%s avisa con `sucursalDelAlcance` y tiene la sucursal de la fila "+
				"delante.\n"+
				"  Eso es el fallo del 01/10/2026: para un SUPER ADMIN —y para TODO lo que "+
				"sube por la cola del teléfono, que no manda `X-Sucursal-Id`— el alcance es "+
				"«todas» y el aviso sale sin sucursal, así que las ocho se bajan el tablero "+
				"entero por un gesto de una.\n"+
				"  Lo que hay que pasarle es `deLaFila(...)` de la columna o de la tarjeta "+
				"que se acaba de escribir.", nombre)
		}
	}

	// El suelo: si mañana se renombran los manejadores, esta prueba dejaría de mirar lo
	// que cree y se quedaría verde para siempre.
	//
	// El número va A MANO (siete) y no `len(escriben)`: la lista de arriba y este suelo tienen
	// que poder discrepar, que es lo único que delata a alguien que añada un manejador a la
	// lista sin su aviso. Comparar una cosa con la otra siempre cuadra.
	//
	// Y se cuenta la forma CON SUCURSAL —`r.Context(), `—, que es la única válida desde el
	// 01/10/2026: un aviso que vuelva a la forma vieja de un solo argumento ni compila, pero
	// uno que se escriba de otra manera dejaría este suelo dormido.
	if n := strings.Count(fuente, "avisarCambioDelTablero(r.Context(), "); n < 7 {
		t.Errorf("hay %d avisos del tablero con su sucursal y tienen que ser al menos 7, "+
			"uno por manejador de escritura: o falta alguno, o cambió la forma de "+
			"escribirlos y esta prueba dejó de servir", n)
	}
}

var _ = sqlc.BoardColumn{}
var _ = uuid.Nil
