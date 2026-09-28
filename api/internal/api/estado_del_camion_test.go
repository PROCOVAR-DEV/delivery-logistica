package api

// EL CAMIÓN EN EL TALLER — 28/09/2026.
//
// Jose dijo que sí a «en mantenimiento». Es lo ÚNICO del estado de la flota que se guarda,
// porque es lo único que no se puede deducir: un camión en el taller no tiene ruta,
// exactamente igual que uno libre. Lo demás —`libre`, `asignado`, `enRuta`— sale de las
// rutas abiertas del camión y no de `vehicles.status` (`db/queries/vehicles.sql`).
//
// Hasta hoy la ficha del vehículo ofrecía «En mantenimiento» en un desplegable y
// `estadoValido` contestaba **400 siempre**: no guardaba nada nunca, y el aviso decía «no
// se pudo guardar» sin decir por qué. Lo que faltaba estaba en la base — el enum
// `vehicle_status` sólo tenía dos valores— y entró con la 00013.
//
// LAS PRUEBAS VAN EN PAREJA, como todo aquí: `maintenance` entra, y lo que no existe sigue
// siendo un 400 **con su motivo dentro**. Sin la segunda mitad, abrir la guarda del todo
// —devolver siempre true— dejaría la primera en verde y un `status: "roto"` llegaría hasta
// Postgres para volver como un 500 con la jerga del motor.

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// ---------------------------------------------------------------------------
// 1 · Se puede mandar al taller, por las dos puertas
// ---------------------------------------------------------------------------

// Las DOS puertas a la misma fila. Validar sólo el alta deja el agujero abierto a un botón
// de distancia, que es lo que ya estaba escrito para la capacidad y el costo por km.
func TestUnCamionSePuedeMandarAlTallerPorLasDosPuertas(t *testing.T) {
	t.Run("al darlo de alta", func(t *testing.T) {
		h := montarAvisos(t, &dobleAvisos{})
		w := pedirAv(t, h, http.MethodPost, "/api/vehicles", avOperadorStg(t),
			`{"name":"Camión #9","status":"maintenance"}`)
		avCodigo(t, w, http.StatusCreated)
		if estadoDelCamion(t, w) != "maintenance" {
			t.Fatalf("se dio de alta en el taller y volvió como %q: %s", estadoDelCamion(t, w), w.Body.String())
		}
	})

	t.Run("y editándolo", func(t *testing.T) {
		h := montarAvisos(t, &dobleAvisos{})
		w := pedirAv(t, h, http.MethodPatch, "/api/vehicles/"+avVehStg.String(), avOperadorStg(t),
			`{"status":"maintenance"}`)
		avCodigo(t, w, http.StatusOK)
		if estadoDelCamion(t, w) != "maintenance" {
			t.Fatalf("el camión se mandó al taller y volvió como %q.\n"+
				"Esto es EL fallo que se viene a arreglar: el desplegable ofrecía "+
				"«En mantenimiento» y no guardaba nada nunca. %s",
				estadoDelCamion(t, w), w.Body.String())
		}
	})

	// Y los dos de siempre siguen entrando. Es la mitad que caza una guarda escrita al
	// revés —«sólo maintenance»— que dejaría la flota sin poder marcarse disponible.
	for _, estado := range []string{"available", "in_use"} {
		t.Run("y sigue valiendo "+estado, func(t *testing.T) {
			h := montarAvisos(t, &dobleAvisos{})
			w := pedirAv(t, h, http.MethodPost, "/api/vehicles", avOperadorStg(t),
				`{"name":"C","status":"`+estado+`"}`)
			avCodigo(t, w, http.StatusCreated)
			if estadoDelCamion(t, w) != estado {
				t.Fatalf("%q volvió como %q", estado, estadoDelCamion(t, w))
			}
		})
	}
}

// ---------------------------------------------------------------------------
// 2 · Y NO MÁS: un estado que no existe sigue siendo un 400 con su motivo
// ---------------------------------------------------------------------------

// El motivo LITERAL importa tanto como el código. Un 400 mudo delante de un desplegable
// deja a quien lo pulsa sin saber si el problema es lo que eligió, la red o su cuenta —y
// entonces vuelve a pulsar, que es lo que pasaba con «En mantenimiento» antes de hoy.
func TestUnEstadoQueNoExisteSigueSiendoUn400ConSuMotivo(t *testing.T) {
	inventados := []struct{ nombre, valor string }{
		// El que más cerca está de colarse: es el que el pliego escribía y el que el
		// desplegable de la ficha llegó a mandar. No está en el enum.
		{"el `in_route` del pliego", "in_route"},
		// Las mayúsculas son otro valor: Postgres compara el enum tal cual.
		{"maintenance en mayúsculas", "MAINTENANCE"},
		{"un estado inventado", "roto"},
		{"la cadena vacía", ""},
		// El nombre en español. Lo teclea quien mira la pantalla y no el contrato.
		{"el nombre en español", "mantenimiento"},
	}
	for _, caso := range inventados {
		t.Run(caso.nombre, func(t *testing.T) {
			h := montarAvisos(t, &dobleAvisos{})
			cuerpo, _ := json.Marshal(map[string]any{"name": "C", "status": caso.valor})
			w := pedirAv(t, h, http.MethodPost, "/api/vehicles", avOperadorStg(t), string(cuerpo))
			if w.Code != http.StatusBadRequest {
				t.Fatalf("`status: %q` tiene que ser un 400 y fue %d: %s",
					caso.valor, w.Code, w.Body.String())
			}
			dice := w.Body.String()
			if !strings.Contains(dice, "Estado de vehículo no válido") {
				t.Fatalf("el 400 no dice qué está mal: %s", dice)
			}
			// Y dice CUÁLES valen. Sin eso, quien lo lea sabe que no puede y no sabe qué
			// puede, que es medio mensaje.
			for _, bueno := range []string{"available", "in_use", "maintenance"} {
				if !strings.Contains(dice, bueno) {
					t.Errorf("el 400 no nombra %q entre los que sí valen: %s", bueno, dice)
				}
			}
		})
	}

	// Y por la otra puerta, igual.
	t.Run("y tampoco por un PATCH", func(t *testing.T) {
		h := montarAvisos(t, &dobleAvisos{})
		w := pedirAv(t, h, http.MethodPatch, "/api/vehicles/"+avVehStg.String(), avOperadorStg(t),
			`{"status":"in_route"}`)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("código %d, se esperaba 400: %s", w.Code, w.Body.String())
		}
	})
}

// ---------------------------------------------------------------------------
// 3 · Mandarlo al taller NO cierra su ruta
// ---------------------------------------------------------------------------

// Liberar un camión (`in_use` -> `available`) SÍ cierra su ruta abierta, y eso lo vigila
// `TestLiberarUnCamionAvisaTambienDeSuRuta`. Mandarlo al taller no, y es a propósito:
// cerrar la ruta sería darla por repartida, y una ruta `completed` es la que llegó — el
// cierre es donde se cuadra qué bajó del camión. Un camión que se rompe a mitad de ruta
// deja un reparto A MEDIAS, que alguien tiene que repartirse.
//
// Así que `maintenance` con una ruta abierta es una contradicción que se queda en pie, y
// quien la dice es la tarjeta del camión, con la ruta nombrada. Se mira por los AVISOS
// porque es la señal que delata la rama: el aviso de rutas sólo sale si se cerró alguna.
func TestMandarUnCamionAlTallerNoCierraSuRuta(t *testing.T) {
	// El camión estaba `in_use` y el doble está preparado para decir que cerró una ruta:
	// si se tomara la rama de liberar, se vería por los dos lados.
	d := &dobleAvisos{vehiculoEnUso: true, rutasCerradas: 1}
	h := montarAvisos(t, d)
	avisos := contarAvisos(t)

	w := pedirAv(t, h, http.MethodPatch, "/api/vehicles/"+avVehStg.String(),
		avOperadorStg(t), `{"status":"maintenance"}`)
	avCodigo(t, w, http.StatusOK)

	// LO PRIMERO, la consulta: ni se intenta. «No se cerró ninguna» y «no se intentó» se
	// ven iguales en cuanto el doble devuelve 0, y aquí lo que importa es que no se llame.
	if d.cierresPedidos != 0 {
		t.Fatalf("mandar el camión al taller intentó cerrar su ruta (%d llamadas).\n"+
			"Cerrarla sería darla por REPARTIDA: una ruta completada es la que llegó, y el "+
			"cierre es donde se cuadra qué bajó del camión. Un camión que se rompe a mitad "+
			"de ruta deja un reparto a medias, que alguien tiene que repartirse.",
			d.cierresPedidos)
	}
	// Y de rebote: sin ruta cerrada no se avisa a la pantalla de Rutas.
	avisos.exige(t, "mandar al taller un camión que estaba en ruta", CambioVehiculos)
}

// ---------------------------------------------------------------------------
// 4 · El enum de la base y `estadoValido` son LA MISMA LISTA
// ---------------------------------------------------------------------------

// Esto no se ata con un comentario, y el CLAUDE.md §3-bis lo tiene escrito con el caso de
// «Sin colocar (722)» encima de una lista de 293: **un comentario no falla**.
//
// Las dos formas de que se separen tienen víctima distinta y las dos son silenciosas:
//
//   - un valor en el enum que `estadoValido` no conoce -> la api contesta 400 a algo que
//     la base guarda tan tranquila, que es el fallo que se arregla hoy;
//   - un valor en `estadoValido` que el enum no tiene -> llega a Postgres y vuelve como un
//     500 con la jerga del motor dentro, en una pantalla donde alguien estaba dando de
//     alta un camión.
//
// La lista de la base se lee de las MIGRACIONES, que es lo que se aplica de verdad, y sólo
// de su sección `Up`: la `Down` de la 00013 nombra `maintenance` a propósito, dentro del
// error que se niega a borrar camiones del taller.
func TestElEnumDeLaBaseYEstadoValidoSonLaMismaLista(t *testing.T) {
	deLaBase := estadosDelEnumEnLasMigraciones(t)
	if len(deLaBase) < 2 {
		t.Fatalf("de las migraciones salieron %v: esta prueba se quedó mirando otra cosa", deLaBase)
	}

	// (a) TODO lo que la base admite, la api lo deja entrar.
	for _, estado := range deLaBase {
		if _, vale := estadoValido(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/", nil), estado); !vale {
			t.Errorf("el enum `vehicle_status` tiene %q y `estadoValido` lo rechaza con un 400.\n"+
				"La base lo guardaría sin pestañear y la pantalla dice «no se pudo guardar» "+
				"sin decir por qué: es exactamente lo que pasaba con «maintenance» hasta el "+
				"28/09/2026.", estado)
		}
	}

	// (b) Y la api no deja entrar nada que la base no tenga. Se lee del propio `switch`,
	// resolviendo cada constante contra el fichero que genera sqlc desde estas mismas
	// migraciones (`sqlc diff` es quien mantiene ese fichero honrado).
	deLaApi := estadosQueAceptaElSwitch(t)
	if !mismosEstados(deLaBase, deLaApi) {
		t.Fatalf("`estadoValido` acepta %v y el enum de la base tiene %v.\n"+
			"Las dos direcciones son silenciosas y tienen víctima distinta: lo que la api deja "+
			"pasar y el tipo de Postgres no conoce llega hasta el motor y vuelve como un 500 "+
			"con su jerga dentro; y lo que el tipo admite y la api rechaza es un 400 sobre algo "+
			"que la base guardaría, con la pantalla diciendo «no se pudo guardar» sin decir por "+
			"qué — que es lo que pasaba con «maintenance» hasta el 28/09/2026.",
			deLaApi, deLaBase)
	}
}

// --------------------------------------------------------------------------- ayudantes

func estadoDelCamion(t *testing.T, w *httptest.ResponseRecorder) string {
	t.Helper()
	var v VehiculoSalida
	if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
		t.Fatalf("respuesta ilegible: %v — %s", err, w.Body.String())
	}
	return v.Status
}

// sinComentariosSQL quita los `--` de una línea. Sin esto, la cabecera de la 00013 —que
// explica por qué no existe `ALTER TYPE ... DROP VALUE`— se leería como SQL.
func sinComentariosSQL(s string) string {
	var b strings.Builder
	for _, linea := range strings.Split(s, "\n") {
		if i := strings.Index(linea, "--"); i >= 0 {
			linea = linea[:i]
		}
		b.WriteString(linea)
		b.WriteByte('\n')
	}
	return b.String()
}

var (
	creaElTipo = regexp.MustCompile(`(?is)create\s+type\s+vehicle_status\s+as\s+enum\s*\(([^)]*)\)`)
	anadeValor = regexp.MustCompile(`(?is)alter\s+type\s+vehicle_status\s+add\s+value\s+(?:if\s+not\s+exists\s+)?'([^']+)'`)
	literal    = regexp.MustCompile(`'([^']+)'`)
)

// estadosDelEnumEnLasMigraciones reconstruye el tipo leyendo los `.sql` en su orden.
func estadosDelEnumEnLasMigraciones(t *testing.T) []string {
	t.Helper()
	ficheros, err := filepath.Glob(filepath.Join("..", "..", "db", "migrations", "*.sql"))
	if err != nil || len(ficheros) == 0 {
		t.Fatalf("no se pudieron listar las migraciones: %v", err)
	}
	sort.Strings(ficheros) // 00001, 00002, … el orden en que se aplican

	var estados []string
	visto := map[string]bool{}
	anadir := func(v string) {
		if !visto[v] {
			visto[v] = true
			estados = append(estados, v)
		}
	}
	for _, f := range ficheros {
		b, err := os.ReadFile(f)
		if err != nil {
			t.Fatalf("%s: %v", f, err)
		}
		texto := sinComentariosSQL(string(b))
		// SÓLO LA SECCIÓN `Up`. La `Down` de la 00013 nombra `maintenance` dentro del
		// error que impide borrar camiones del taller, y la de la 00001 tira el tipo.
		if i := strings.Index(texto, "+goose Down"); i >= 0 {
			texto = texto[:i]
		}
		for _, m := range creaElTipo.FindAllStringSubmatch(texto, -1) {
			for _, v := range literal.FindAllStringSubmatch(m[1], -1) {
				anadir(v[1])
			}
		}
		for _, m := range anadeValor.FindAllStringSubmatch(texto, -1) {
			anadir(m[1])
		}
	}
	return estados
}

var (
	elSwitch  = regexp.MustCompile(`(?s)func estadoValido\(.*?case ([^:]+):`)
	laConstan = regexp.MustCompile(`sqlc\.(VehicleStatus\w+)`)
	elValor   = regexp.MustCompile(`(?m)^\s*(VehicleStatus\w+)\s+VehicleStatus\s*=\s*"([^"]+)"`)
)

// estadosQueAceptaElSwitch lee el `case` de `estadoValido` y traduce cada constante a su
// literal con el fichero que genera sqlc.
//
// Leer el código fuente en una prueba es feo y aquí hace falta: un `switch` no se puede
// enumerar desde dentro de Go, y la alternativa —probar «un puñado de valores raros»— deja
// pasar justo el caso que importa, una constante de más apuntando a un valor que el tipo de
// Postgres no tiene.
func estadosQueAceptaElSwitch(t *testing.T) []string {
	t.Helper()
	fuente, err := os.ReadFile("vehiculos.go")
	if err != nil {
		t.Fatalf("no se pudo leer vehiculos.go: %v", err)
	}
	m := elSwitch.FindSubmatch(fuente)
	if m == nil {
		t.Fatal("no se encontró el `case` de `estadoValido`: esta prueba se quedó mirando otra cosa")
	}
	constantes := laConstan.FindAllStringSubmatch(string(m[1]), -1)
	if len(constantes) == 0 {
		t.Fatalf("el `case` de `estadoValido` no usa constantes de sqlc: %q.\n"+
			"Escritas a mano no hay nada que las ate al enum de la base.", m[1])
	}

	modelos, err := os.ReadFile(filepath.Join("..", "store", "sqlc", "models.go"))
	if err != nil {
		t.Fatalf("no se pudo leer el modelo generado: %v", err)
	}
	porNombre := map[string]string{}
	for _, v := range elValor.FindAllStringSubmatch(string(modelos), -1) {
		porNombre[v[1]] = v[2]
	}

	var estados []string
	for _, c := range constantes {
		valor, hay := porNombre[c[1]]
		if !hay {
			t.Fatalf("`estadoValido` acepta `sqlc.%s` y esa constante no existe en el modelo "+
				"generado: %v", c[1], porNombre)
		}
		estados = append(estados, valor)
	}
	return estados
}

func mismosEstados(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	x, y := append([]string(nil), a...), append([]string(nil), b...)
	sort.Strings(x)
	sort.Strings(y)
	for i := range x {
		if x[i] != y[i] {
			return false
		}
	}
	return true
}
