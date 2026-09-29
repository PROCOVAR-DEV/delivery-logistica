package api

// «NOT FOUND» NO PUEDE ACABAR EN LA BANDEJA DE UN REPARTIDOR.
//
// Catorce puertas del tablero contestaban `httpx.MsgNotFound` —o sea, literalmente
// **«Not found»**— y son justo las puertas por las que sube un apunte armado sin señal.
// El sincronizador reenvía el cuerpo del 4xx tal cual (`sync/internal/reparto/reparto.go`,
// `motivoDe`), así que ese texto viajaba entero hasta la bandeja del teléfono: en inglés,
// sin decir qué era lo que no estaba y sin decir qué hacer.
//
// Lo encontró la auditoría del 29/09/2026, y lo que más dice de esto es que al cambiarlo
// **no falló ni una prueba de las que había**: nadie vigilaba el texto que lee una persona.
// Este fichero es esa vigilancia.
//
// Las dos mitades que comprueba:
//
//  1. que cada puerta diga en español QUÉ no está;
//  2. que no diga de más. Una zona de otra sucursal contesta lo mismo que una que no
//     existe — decir «existe pero no es tuya» ya es contar algo de otra sucursal, que es
//     la fuga que el §4 prohíbe.

import (
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
)

func TestLasPuertasDelTableroDicenEnEspanolQueNoEsta(t *testing.T) {
	// Un id con la forma buena y que no es de nadie: es el caso de verdad —la zona se
	// borró desde la web mientras el teléfono estaba sin señal— y no un id mal escrito.
	fantasma := uuid.New().String()

	casos := []struct {
		nombre string
		metodo string
		ruta   string
		cuerpo string
		espera string
		porQue string
	}{
		{
			nombre: "renombrar una zona que ya no está",
			metodo: http.MethodPatch,
			ruta:   "/api/board/columns/" + fantasma,
			cuerpo: `{"nombre":"Centro"}`,
			espera: msgZonaNoEsta,
			porQue: "es el apunte de renombrar que sube tras un día sin señal",
		},
		{
			nombre: "borrar una zona que ya no está",
			metodo: http.MethodDelete,
			ruta:   "/api/board/columns/" + fantasma,
			espera: msgZonaNoEsta,
		},
		{
			nombre: "armar la ruta de una zona que ya no está",
			metodo: http.MethodPost,
			ruta:   "/api/board/columns/" + fantasma + "/route",
			cuerpo: `{}`,
			espera: msgZonaNoEsta,
			porQue: "es la puerta del armado sin señal, la que más se reintenta",
		},
		{
			nombre: "colocar un pedido que no existe",
			metodo: http.MethodPut,
			ruta:   "/api/board/placements/" + fantasma,
			cuerpo: `{"columnaId":"` + colCentro.String() + `","posicion":0}`,
			espera: msgPedidoNoEsta,
		},
		// LOS IDS MAL FORMADOS, QUE SON OTRAS CINCO PUERTAS.
		//
		// Van aparte y hacen falta: `idDeRuta` sólo dice su mensaje cuando el id NO es un
		// uuid, así que con un id bien formado esos cinco sitios no se pisan nunca — se
		// comprobó rompiéndolos a propósito y los casos de arriba salieron verdes.
		//
		// Y no es un caso de laboratorio: los ids del delivery viejo eran cuid, así que un
		// enlace guardado o una APK vieja mandan exactamente esto.
		{
			nombre: "una zona con un id que no es un uuid",
			metodo: http.MethodPatch,
			ruta:   "/api/board/columns/ckq7z8x1a0000",
			cuerpo: `{"nombre":"Centro"}`,
			espera: msgZonaNoEsta,
		},
		{
			nombre: "armar la ruta con un id que no es un uuid",
			metodo: http.MethodPost,
			ruta:   "/api/board/columns/ckq7z8x1a0000/route",
			cuerpo: `{}`,
			espera: msgZonaNoEsta,
		},
		{
			nombre: "borrar una zona con un id que no es un uuid",
			metodo: http.MethodDelete,
			ruta:   "/api/board/columns/ckq7z8x1a0000",
			espera: msgZonaNoEsta,
		},
		{
			nombre: "colocar con un id de pedido que no es un uuid",
			metodo: http.MethodPut,
			ruta:   "/api/board/placements/ckq7z8x1a0000",
			cuerpo: `{"columnaId":"` + colCentro.String() + `","posicion":0}`,
			espera: msgPedidoNoEsta,
		},
		{
			nombre: "quitar con un id de pedido que no es un uuid",
			metodo: http.MethodDelete,
			ruta:   "/api/board/placements/ckq7z8x1a0000",
			espera: msgPedidoNoEsta,
		},
		{
			nombre: "pedir el tablero de una sucursal que no es tuya",
			metodo: http.MethodGet,
			ruta:   "/api/board?branchId=" + fantasma,
			espera: msgSucursalNoEsta,
		},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			q := nuevoTablero()
			q.tresPuestas()
			h := montarTab(t, q)
			jwt := tokenTab(t, sucStg.String())

			w := pedirTab(t, h, c.metodo, c.ruta, jwt, c.cuerpo)
			cuerpo := w.Body.String()

			// LO PRIMERO, Y ES LO QUE SE VE EN EL TELÉFONO: nada en inglés.
			if strings.Contains(cuerpo, "Not found") {
				t.Fatalf("contesta «Not found» en inglés, y ese texto acaba tal cual en la "+
					"bandeja de quien reparte. %s\nVolvió: %s", c.porQue, cuerpo)
			}
			m := leerTab(t, w)
			if m["error"] != c.espera {
				t.Fatalf("el motivo no dice qué no está.\n  esperaba: %q\n  volvió:   %q\n"+
					"Un «no encontrado» a secas deja a quien lo lee sin saber si le falta "+
					"la zona, el pedido o la sucursal — y son tres arreglos distintos.",
					c.espera, m["error"])
			}
		})
	}
}

// Y LA MITAD QUE VIGILA QUE NO SE DIGA DE MÁS.
//
// Una zona que SÍ existe pero es de otra sucursal tiene que contestar exactamente lo mismo
// que una que no existe. Cualquier diferencia entre las dos respuestas —el texto, el
// código— convierte esta puerta en una forma de averiguar qué hay en las otras siete
// sucursales, que es la fuga del §4 que ya mordió en delivery.
func TestUnaZonaDeOtraSucursalContestaLoMismoQueUnaQueNoExiste(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	h := montarTab(t, q)
	// HOLGUÍN, QUE EXISTE DE VERDAD, y no una sucursal inventada. Con un uuid que no
	// resuelve, `internal/alcance` abre el alcance a las ocho —lo dice en un aviso de log
	// y contesta 200—, así que la prueba mediría ese camino y no el que quiere medir.
	// `colCentro` es de Santiago.
	jwtDeOtra := tokenTab(t, sucHol.String())

	deOtra := pedirTab(t, h, http.MethodDelete,
		"/api/board/columns/"+colCentro.String(), jwtDeOtra, "")
	fantasma := pedirTab(t, h, http.MethodDelete,
		"/api/board/columns/"+uuid.New().String(), jwtDeOtra, "")

	if deOtra.Code != fantasma.Code {
		t.Fatalf("una zona de otra sucursal contesta %d y una que no existe %d: la "+
			"diferencia ya dice que aquélla existe", deOtra.Code, fantasma.Code)
	}
	if deOtra.Body.String() != fantasma.Body.String() {
		t.Fatalf("las dos respuestas se distinguen y no deberían:\n  de otra: %s\n"+
			"  fantasma: %s", deOtra.Body.String(), fantasma.Body.String())
	}
}
