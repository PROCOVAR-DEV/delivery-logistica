package api

// LA CABECERA DEL «NO» DEL ARMADO, Y QUE SEA LA MISMA QUE LA DEL APARATO.
//
// La ruta se arma en el patio del almacén sin señal, así que el rechazo lo redacta el
// teléfono; con cobertura lo redacta la nube. Son dos frases escritas a mano en dos
// lenguajes y, si se separan, el mismo «no» se lee de dos maneras según haya red — y eso no
// falla en ningún sitio, no hay pantalla que lo enseñe ni registro que lo diga.
//
// Ya pasó con el plural: «1 de los 1 pedidos elegidos no pueden ir en esta ruta» estuvo mal
// **en los dos lados a la vez y a propósito**, porque arreglarlo en uno solo era peor. Eso
// significa que había un contrato y nadie lo vigilaba: lo único que lo sostenía era un
// comentario en cada fichero pidiendo que no se tocara. Un comentario no falla
// (`CLAUDE.md` §3-bis).
//
// `docs/armado-rechazado.casos.json` lo leen esta prueba y
// `app/test/pantallas/rutas/encabezado_del_armado_test.dart`. Es EL MISMO fichero, no una
// copia: una copia se desincroniza y entonces las dos pruebas salen verdes diciendo cosas
// distintas.

import (
	"encoding/json"
	"os"
	"testing"
)

type casoDeEncabezado struct {
	Nombre      string `json:"nombre"`
	Nota        string `json:"nota"`
	SeCaen      int    `json:"seCaen"`
	SeEligieron int    `json:"seEligieron"`
	Encabezado  string `json:"encabezado"`
}

// La ruta es la que espera el `COPY` de `deploy/Dockerfile.api`: desde `/src/internal/api`,
// `../../../docs/…` cae en `/docs/…`. Si falta, esto hace `Fatalf` y la imagen no se
// construye, que es lo que se quiere.
const rutaDeLosCasosDelArmado = "../../../docs/armado-rechazado.casos.json"

func TestElEncabezadoDelArmadoEsElDelAparato(t *testing.T) {
	b, err := os.ReadFile(rutaDeLosCasosDelArmado)
	if err != nil {
		t.Fatalf("no se pudo leer %s: %v\n"+
			"Es el fichero que ata esta redacción con la del aparato. Sin él, esta prueba "+
			"no comprueba nada y el contrato se queda sin vigilante.",
			rutaDeLosCasosDelArmado, err)
	}
	var fichero struct {
		Casos []casoDeEncabezado `json:"casos"`
	}
	if err := json.Unmarshal(b, &fichero); err != nil {
		t.Fatalf("%s no se puede interpretar: %v", rutaDeLosCasosDelArmado, err)
	}
	if len(fichero.Casos) == 0 {
		t.Fatalf("%s no tiene ni un caso: una prueba sobre una lista vacía sale verde sin "+
			"haber comprobado nada", rutaDeLosCasosDelArmado)
	}

	// Y que el caso que motivó todo esto siga estando. Sin esta comprobación, quitarlo del
	// JSON deja la suite en verde y devuelve el «1 de los 1» por la puerta de al lado.
	hayUnoSolo := false

	for _, c := range fichero.Casos {
		t.Run(c.Nombre, func(t *testing.T) {
			salio := encabezadoDelArmado(c.SeCaen, c.SeEligieron)
			if salio != c.Encabezado {
				t.Errorf("con %d de %d elegidos la cabecera tiene que ser:\n"+
					"  %q\ny salió:\n  %q\n"+
					"El aparato escribe la del fichero letra por letra "+
					"(`encabezadoDelArmado` en app/lib/pantallas/rutas/datos/"+
					"acciones_rutas.dart). Si la redacción tiene que cambiar, se cambian "+
					"los DOS lados y se regenera %s.\n%s",
					c.SeCaen, c.SeEligieron, c.Encabezado, salio,
					rutaDeLosCasosDelArmado, c.Nota)
			}
		})
		if c.SeCaen == 1 && c.SeEligieron == 1 {
			hayUnoSolo = true
		}
	}

	if !hayUnoSolo {
		t.Errorf("%s ya no tiene el caso de UN pedido elegido que se cae.\n"+
			"Es el que salía «1 de los 1 pedidos elegidos no pueden ir en esta ruta» —tres "+
			"faltas en siete palabras— y el más común de todos. Sin él en la lista, esta "+
			"prueba deja de mirar justo lo que vino a vigilar.", rutaDeLosCasosDelArmado)
	}
}
