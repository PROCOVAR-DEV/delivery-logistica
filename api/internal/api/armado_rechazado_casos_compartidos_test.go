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

	"procovar/reparto-api/internal/store/sqlc"
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

// LOS «NO» NUEVOS DEL 07/10/2026 TAMBIÉN SE ATAN AL FICHERO, no sólo la cabecera.
//
// La cabecera se redacta dos veces (servidor y aparato). Estos otros mensajes los escribe SÓLO
// el servidor y el aparato los copia tal cual de la respuesta, así que el riesgo no es que dos
// redacciones se separen sino que el texto que ve la persona cambie sin que nadie se entere:
// el aparato guarda el rechazo en su bandeja con ese literal y el manual lo cita. El fichero
// los fija, y esta prueba comprueba que el servidor sigue diciendo EXACTAMENTE eso.
func TestLosMensajesNuevosDelServidorSonLosDelFichero(t *testing.T) {
	b, err := os.ReadFile(rutaDeLosCasosDelArmado)
	if err != nil {
		t.Fatalf("no se pudo leer %s: %v", rutaDeLosCasosDelArmado, err)
	}
	var fichero struct {
		Mensajes struct {
			Armado []struct {
				Nombre          string `json:"nombre"`
				OperationNumber string `json:"operationNumber"`
				Mensaje         string `json:"mensaje"`
			} `json:"armadoDeRuta"`
			Fijos []struct {
				Nombre  string `json:"nombre"`
				Literal string `json:"literal"`
			} `json:"literalesFijos"`
			Descartados []struct {
				Nombre   string `json:"nombre"`
				Motivo   string `json:"motivo"`
				QueHacer string `json:"queHacer"`
			} `json:"descartadosDelTablero"`
		} `json:"mensajesDelServidor"`
	}
	if err := json.Unmarshal(b, &fichero); err != nil {
		t.Fatalf("%s no se puede interpretar: %v", rutaDeLosCasosDelArmado, err)
	}
	m := fichero.Mensajes
	if len(m.Armado) == 0 || len(m.Fijos) == 0 || len(m.Descartados) == 0 {
		t.Fatalf("%s perdió una de las tres listas de `mensajesDelServidor`: una prueba sobre una "+
			"lista vacía sale verde sin haber comprobado nada", rutaDeLosCasosDelArmado)
	}

	// 1. Armar una ruta: los dos mensajes con un pedido nombrado por su número de operación.
	for _, c := range m.Armado {
		t.Run("armado/"+c.Nombre, func(t *testing.T) {
			fila := sqlc.PedidosParaArmarRutaRow{CustomerName: "Cliente", OperationNumber: &c.OperationNumber}
			var salio string
			switch c.Nombre {
			case "sin-domicilio-cobrado-uno":
				salio = mensajeDomicilioSinCobrar([]sqlc.PedidosParaArmarRutaRow{fila})
			case "sin-cotizar-uno":
				cobrado := 9.0
				fila.FacturaDomicilio = &cobrado
				salio = mensajeSinCalcular([]sqlc.PedidosParaArmarRutaRow{fila})
			default:
				t.Fatalf("caso %q sin comprobación: añádela aquí o el fichero miente", c.Nombre)
			}
			if salio != c.Mensaje {
				t.Errorf("el servidor dice:\n  %q\ny el fichero fija:\n  %q", salio, c.Mensaje)
			}
		})
	}

	// 2. Los literales fijos, contra las constantes del servidor.
	constantes := map[string]string{
		"camion-inactivo":                   msgVehiculoInactivo,
		"colocar-sin-domicilio-cobrado":     msgTableroSinDomicilioCobrado,
		"colocar-sin-cotizar":               msgTableroSinCotizar,
		"borrar-vehiculo-con-rutas":         msgVehiculoConRutas,
		"quitar-parada-ruta-no-planificada": msgSoloRutaPlanificada,
		"quitar-parada-que-no-esta":         msgParadaNoPertenece,
	}
	for _, c := range m.Fijos {
		t.Run("fijo/"+c.Nombre, func(t *testing.T) {
			quiere, hay := constantes[c.Nombre]
			if !hay {
				t.Fatalf("literal %q sin constante que comprobar: añádela aquí o el fichero miente", c.Nombre)
			}
			if quiere != c.Literal {
				t.Errorf("el servidor dice:\n  %q\ny el fichero fija:\n  %q", quiere, c.Literal)
			}
		})
	}
	if len(constantes) != len(m.Fijos) {
		t.Errorf("hay %d constantes comprobadas y %d literales en el fichero: tienen que ser las mismas",
			len(constantes), len(m.Fijos))
	}

	// 3. Los descartados del tablero, a través del manejador de verdad: una zona con una
	// tarjeta sin cobrar y otra sin cotizar tiene que nombrarlas con esos textos.
	q := nuevoTablero()
	q.tresPuestas()
	q.capacidad = 1000
	a, c := q.pedidos[ped2], q.pedidos[ped3]
	a.sinCobrar, c.sinCotizar = true, true
	q.pedidos[ped2], q.pedidos[ped3] = a, c
	w := pedirTab(t, montarTab(t, q), "POST", "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)
	resp := leerTab(t, w)
	porNombre := map[string]string{"zona-sin-domicilio-cobrado": "Beto", "zona-sin-cotizar": "Ana"}
	for _, d := range m.Descartados {
		cliente, hay := porNombre[d.Nombre]
		if !hay {
			t.Fatalf("descartado %q sin comprobación", d.Nombre)
		}
		got := descartadoPorNombre(t, resp, cliente)
		if got["motivo"] != d.Motivo || got["queHacer"] != d.QueHacer {
			t.Errorf("%s: el servidor dice motivo=%q queHacer=%q y el fichero fija motivo=%q queHacer=%q",
				d.Nombre, got["motivo"], got["queHacer"], d.Motivo, d.QueHacer)
		}
	}
}
