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

	"github.com/google/uuid"

	"procovar/reparto-api/internal/alcance"
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
	if len(m.Fijos) == 0 {
		t.Fatalf("%s perdió una de las tres listas de `mensajesDelServidor`: una prueba sobre una "+
			"lista vacía sale verde sin haber comprobado nada", rutaDeLosCasosDelArmado)
	}

	// 2. Los literales fijos, contra las constantes del servidor.
	constantes := map[string]string{
		"camion-inactivo":                   msgVehiculoInactivo,
		"borrar-vehiculo-con-rutas":         msgVehiculoConRutas,
		"quitar-parada-ruta-no-planificada": msgSoloRutaPlanificada,
		"quitar-parada-que-no-esta":         msgParadaNoPertenece,
		// 1.0.29: sólo se AÑADE; ninguno de los de arriba cambia de texto.
		"camion-compartido-no-se-toca":    msgVehiculoCompartido,
		"campo-no-se-cambia-en-el-pedido": msgCampoNoSeCambiaAqui,
		"sin-alcance":                     alcance.ErrSinAlcance.Error(),
		"sucursal-sin-alta-en-reparto":    alcance.ErrSucursalSinAlta{Codigo: "MOA"}.Error(),
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
}

// casoDeEntrada es un caso de `reglaDeEntrada`: un pedido y si entra en una ruta.
type casoDeEntrada struct {
	Nombre            string   `json:"nombre"`
	Nota              string   `json:"nota"`
	OperationNumber   string   `json:"operationNumber"`
	FacturaEstado     *string  `json:"facturaEstado"`
	FacturaDomicilio  *float64 `json:"facturaDomicilio"`
	PedidoCosto       *float64 `json:"pedidoCosto"`
	RequiereDomicilio *bool    `json:"requiereDomicilio"`
	Entra             bool     `json:"entra"`
	Mensaje           string   `json:"mensaje"`
}

// leerReglaDeEntrada lee los casos y exige los que no se pueden perder: el caso real del
// issue 10 entrando y, al menos, uno de cada lado.
func leerReglaDeEntrada(t *testing.T) []casoDeEntrada {
	t.Helper()
	b, err := os.ReadFile(rutaDeLosCasosDelArmado)
	if err != nil {
		t.Fatalf("no se pudo leer %s: %v", rutaDeLosCasosDelArmado, err)
	}
	var fichero struct {
		Regla struct {
			Casos []casoDeEntrada `json:"casos"`
		} `json:"reglaDeEntrada"`
	}
	if err := json.Unmarshal(b, &fichero); err != nil {
		t.Fatalf("%s no se puede interpretar: %v", rutaDeLosCasosDelArmado, err)
	}
	entran, noEntran, real := 0, 0, false
	for _, c := range fichero.Regla.Casos {
		if c.Entra {
			entran++
		} else {
			noEntran++
		}
		if c.Nombre == "caso-real-PCC25-261014-1435" && c.Entra {
			real = true
		}
	}
	if entran == 0 || noEntran == 0 || !real {
		t.Fatalf("%s: `reglaDeEntrada` tiene que traer casos que entran (%d), que no entran (%d) y el "+
			"caso real del issue 10 entrando (%v): sin ellos esta prueba sale verde sin mirar nada",
			rutaDeLosCasosDelArmado, entran, noEntran, real)
	}
	return fichero.Regla.Casos
}

// LA REGLA DE ENTRADA DEL SERVIDOR ES LA DEL FICHERO — issue 10 de Amado, 15/10/2026.
//
// Las dos puertas que deciden en Go: el asistente (`rechazoDelArmado`, POST /api/routes) y la
// zona del tablero (`motivoDeCorteDelArmado`, POST /api/board/columns/{id}/route). El aparato
// lee los MISMOS casos (`la_regla_de_entrada_es_la_del_servidor_test.dart`) y el SQL también
// (`TestMotorReal_LaReglaDeEntradaEsLaDelFichero`).
func TestLaReglaDeEntradaEsLaDelFichero(t *testing.T) {
	for _, c := range leerReglaDeEntrada(t) {
		t.Run(c.Nombre, func(t *testing.T) {
			var estado *sqlc.FacturaEstado
			if c.FacturaEstado != nil {
				e := sqlc.FacturaEstado(*c.FacturaEstado)
				estado = &e
			}
			op := c.OperationNumber
			asistente := rechazoDelArmado([]sqlc.PedidosParaArmarRutaRow{{
				OperationNumber: &op, CustomerName: "Cliente", FacturaEstado: estado,
				FacturaDomicilio: c.FacturaDomicilio, PedidoCosto: c.PedidoCosto,
			}})
			if c.Entra && asistente != "" {
				t.Errorf("el asistente lo rechaza y tiene que entrar: %q\n%s", asistente, c.Nota)
			}
			if !c.Entra && asistente != c.Mensaje {
				t.Errorf("el asistente dice:\n  %q\ny el fichero fija:\n  %q\n%s", asistente, c.Mensaje, c.Nota)
			}
			zona, _ := motivoDeCorteDelArmado(sqlc.PedidosDeColumnaParaArmarRutaRow{
				OperationNumber: &op, CustomerName: "Cliente", FacturaEstado: estado,
				FacturaDomicilio: c.FacturaDomicilio, PedidoCosto: c.PedidoCosto,
			})
			if c.Entra != (zona == "") {
				t.Errorf("la zona del tablero dice %q y el fichero dice entra=%v\n%s", zona, c.Entra, c.Nota)
			}
		})
	}
}

// EL COSTO DE LA PARADA ES EL DEL FICHERO — Amado y Jose, 16/10/2026. Sin cotizar y cobrado, la
// parada vale lo cobrado; cotizado, lo cotizado. El aparato lee los mismos casos.
func TestElCostoDeLaParadaEsElDelFichero(t *testing.T) {
	b, err := os.ReadFile(rutaDeLosCasosDelArmado)
	if err != nil {
		t.Fatalf("no se pudo leer %s: %v", rutaDeLosCasosDelArmado, err)
	}
	var fichero struct {
		Costo struct {
			Casos []struct {
				Nombre           string   `json:"nombre"`
				PedidoCosto      *float64 `json:"pedidoCosto"`
				FacturaDomicilio *float64 `json:"facturaDomicilio"`
				Costo            *float64 `json:"costo"`
			} `json:"casos"`
		} `json:"costoDeLaParada"`
	}
	if err := json.Unmarshal(b, &fichero); err != nil {
		t.Fatalf("%s no se puede interpretar: %v", rutaDeLosCasosDelArmado, err)
	}
	if len(fichero.Costo.Casos) < 4 {
		t.Fatalf("%s: `costoDeLaParada` perdió sus casos: una prueba sobre una lista vacía sale verde sin mirar nada", rutaDeLosCasosDelArmado)
	}
	for _, c := range fichero.Costo.Casos {
		t.Run(c.Nombre, func(t *testing.T) {
			got := costoDeLaParada(c.PedidoCosto, c.FacturaDomicilio)
			if (got == nil) != (c.Costo == nil) || (got != nil && *got != *c.Costo) {
				t.Errorf("costoDeLaParada(%v, %v) = %v y el fichero fija %v", c.PedidoCosto, c.FacturaDomicilio, got, c.Costo)
			}
			// La parada que se arma con ese pedido recibe ese costo en `price`.
			id := uuid.New()
			fila := sqlc.PedidosParaArmarRutaRow{ID: id, PedidoCosto: c.PedidoCosto, FacturaDomicilio: c.FacturaDomicilio}
			price := costoDelPedido([]sqlc.PedidosParaArmarRutaRow{fila}, id)
			if (price == nil) != (c.Costo == nil) || (price != nil && *price != *c.Costo) {
				t.Errorf("el price copiado a la parada es %v y el fichero fija %v", price, c.Costo)
			}
		})
	}
}
