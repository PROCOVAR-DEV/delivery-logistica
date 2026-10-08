package reparto

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/sincro"
)

// LA DIRECCIÓN A LA QUE SE REENVÍA UN APUNTE, que es lo que tiró el día entero.
//
// El aparato encola la ruta SIN prefijo —`/board/columns`— porque es la que usa contra su
// propia base. `reparto-api` las sirve todas bajo `/api`. Reenviarlas tal cual daba 404 en
// cada apunte, y un 4xx aquí es «rechazo de negocio»: acababan en la bandeja como si el
// reparto hubiera dicho que no.
//
// Y lo peor era el efecto dominó: el apunte rechazado era el que CREA la zona del tablero,
// así que los cinco que colocaban pedidos dentro se caían detrás con «el identificador
// provisional todavía no corresponde a nada». Seis apuntes de trabajo real, perdidos por
// una barra, el 16/09/2026.
//
// Este paquete no tenía NI UNA prueba. Por eso sobrevivió.
func TestElApunteSeReenviaBajoApi(t *testing.T) {
	var vistas []string
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			// La ruta ENTERA, con su query: si se perdiera el `branchId` el reparto no
			// sabría de qué sucursal es la zona.
			vistas = append(vistas, r.URL.RequestURI())
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"id":"` + uuid.NewString() + `"}`))
		}))
	defer servidor.Close()

	c := Nuevo(servidor.URL, "clave-de-prueba", 5*time.Second)

	casos := []struct {
		ruta     string
		esperada string
	}{
		{"/board/columns?branchId=abc", "/api/board/columns?branchId=abc"},
		{"/board/placements/p-1", "/api/board/placements/p-1"},
		{"/routes/r-1/results", "/api/routes/r-1/results"},
	}
	for _, caso := range casos {
		vistas = nil
		_, err := c.Aplicar(context.Background(), sincro.Peticion{
			Metodo:   http.MethodPost,
			Ruta:     caso.ruta,
			Cuerpo:   json.RawMessage(`{"nombre":"Vista"}`),
			Hecho:    time.Now(),
			Sucursal: uuid.New(),
			Persona:  "quien-sea",
			Clave:    "k",
		})
		if err != nil {
			t.Fatalf("%s: no tenía que fallar: %v", caso.ruta, err)
		}
		if len(vistas) != 1 || vistas[0] != caso.esperada {
			t.Errorf("se llamó a %v, se esperaba %q — sin el `/api` el reparto contesta "+
				"404 y el apunte acaba en la bandeja de rechazos", vistas, caso.esperada)
		}
	}
}

// Y el `/api` se pone UNA sola vez: si `REPARTO_URL` ya lo trajera, `/api/api/...` sería
// el mismo fallo por el otro lado. Es exactamente lo que le pasó al Tablero en la web.
func TestNoSeDuplicaElApi(t *testing.T) {
	var vista string
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			vista = r.URL.Path
			_, _ = w.Write([]byte(`{}`))
		}))
	defer servidor.Close()

	_, err := Nuevo(servidor.URL, "k", 5*time.Second).Aplicar(
		context.Background(), sincro.Peticion{
			Metodo: http.MethodPost, Ruta: "/board/columns",
			Hecho: time.Now(), Sucursal: uuid.New(), Persona: "x", Clave: "k",
		})
	if err != nil {
		t.Fatalf("no tenía que fallar: %v", err)
	}
	if vista != "/api/board/columns" {
		t.Errorf("ruta = %q, se esperaba /api/board/columns", vista)
	}
}

// UN 404 DE PUERTA EQUIVOCADA NO ES UN RECHAZO, y la diferencia se paga cara.
//
// El reparto contesta sus «no encontrado» con un JSON suyo. Un 404 con otra cosa dentro
// —el `404 page not found` del enrutador de Go— dice que se llamó a una puerta que no
// existe: un fallo de despliegue. Tratarlo como rechazo deja el apunte muerto en la
// bandeja pidiendo que una persona decida sobre algo que ninguna persona puede arreglar,
// y arrastra a todos los que dependían de lo que iba a crear.
func Test404DeRutaEsCaidaYNoRechazo(t *testing.T) {
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			// Exactamente lo que escribe el enrutador de Go.
			http.NotFound(w, r)
		}))
	defer servidor.Close()

	_, err := Nuevo(servidor.URL, "k", 5*time.Second).Aplicar(
		context.Background(), sincro.Peticion{
			Metodo: http.MethodPost, Ruta: "/board/columns",
			Hecho: time.Now(), Sucursal: uuid.New(), Persona: "x", Clave: "k",
		})
	if err == nil {
		t.Fatal("tenía que fallar")
	}
	var rechazo *sincro.Rechazo
	if errors.As(err, &rechazo) {
		t.Fatalf("un 404 de ruta NO puede ser un rechazo: se queda muerto en la bandeja "+
			"y arrastra a los que dependen de él. Salió: %v", err)
	}
}

// Y un 404 QUE SÍ VIENE DEL REPARTO sigue siendo un rechazo: «ese pedido ya no está» es
// una respuesta de negocio y la tiene que mirar una persona.
func Test404DelRepartoSigueSiendoRechazo(t *testing.T) {
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"error":"Ese pedido ya no existe"}`))
		}))
	defer servidor.Close()

	_, err := Nuevo(servidor.URL, "k", 5*time.Second).Aplicar(
		context.Background(), sincro.Peticion{
			Metodo: http.MethodPut, Ruta: "/board/placements/p-1",
			Hecho: time.Now(), Sucursal: uuid.New(), Persona: "x", Clave: "k",
		})
	var rechazo *sincro.Rechazo
	if !errors.As(err, &rechazo) {
		t.Fatalf("tenía que ser un rechazo con su motivo: %v", err)
	}
	if rechazo.Motivo != "Ese pedido ya no existe" {
		t.Errorf("motivo = %q: se enseña LITERAL lo que dijo el reparto", rechazo.Motivo)
	}
}

// EL APUNTE VIAJA FIRMADO POR LA PERSONA QUE LO HIZO, no por este servicio.
//
// Segundo acto del mismo día. Con el `/api` ya puesto, la zona creada desde la web seguía
// sin llegar: `reparto-api` registraba **401 «no viene token» en POST /api/board/columns**.
// Este servicio reenviaba con la clave de servicio más `X-Persona` y `X-Sucursal`, y ahí
// había dos agujeros: el reparto **no lee esas dos cabeceras** —las ponía éste y no las
// miraba nadie— y las rutas del aparato exigen sesión de persona, que la clave no abre.
//
// Resultado: el apunte que crea la zona se quedaba en la cola para siempre. Es lo que dejó
// la zona «Vista» dentro de un teléfono, con sus cinco pedidos colocados, sin que la viera
// nadie más. Comprobado contra producción el 16/09/2026: `board_columns` estaba a 0.
func TestElApunteViajaConElTokenDeLaPersona(t *testing.T) {
	var autorizacion, clave string
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			autorizacion = r.Header.Get("Authorization")
			clave = r.Header.Get("x-api-key")
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"id":"` + uuid.NewString() + `"}`))
		}))
	defer servidor.Close()

	c := Nuevo(servidor.URL, "clave-de-prueba", 5*time.Second)
	_, err := c.Aplicar(context.Background(), sincro.Peticion{
		Metodo:   http.MethodPost,
		Ruta:     "/board/columns?branchId=abc",
		Cuerpo:   json.RawMessage(`{"nombre":"Vista"}`),
		Hecho:    time.Now(),
		Sucursal: uuid.New(),
		Persona:  "u-1",
		Clave:    "k",
		Token:    "el.token.de.la.persona",
	})
	if err != nil {
		t.Fatalf("no tenía que fallar: %v", err)
	}

	if autorizacion != "Bearer el.token.de.la.persona" {
		t.Errorf("se reenvió con Authorization %q: sin el token de la persona, "+
			"/api/board/columns contesta 401 «no viene token» y el apunte se queda en la "+
			"cola para siempre", autorizacion)
	}
	// Y la clave de servicio SE QUITA. En el reparto hay rutas que, al ver `x-api-key`,
	// se cuelgan un Super Admin sin sucursal: correcto para su temporizador, inaceptable
	// para el trabajo de una persona. Mandar las dos sería dejar que un apunte de
	// Camagüey se ejecutara con permiso sobre las ocho.
	if clave != "" {
		t.Errorf("se reenvió además la clave de servicio (%q): un apunte de una persona "+
			"no puede llevar con qué convertirse en Super Admin", clave)
	}
}

// Sin token —el modo viejo de `SYNC_IDENTIDAD=cabeceras`, donde la identidad viene de una
// cabecera y no hay token que reenviar— se sigue mandando la clave. Es lo único que queda
// ahí, y quitarla dejaría ese modo sin ninguna credencial.
func TestSinTokenSeSigueMandandoLaClave(t *testing.T) {
	var autorizacion, clave string
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			autorizacion = r.Header.Get("Authorization")
			clave = r.Header.Get("x-api-key")
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{}`))
		}))
	defer servidor.Close()

	c := Nuevo(servidor.URL, "clave-de-prueba", 5*time.Second)
	if _, err := c.Aplicar(context.Background(), sincro.Peticion{
		Metodo: http.MethodPost, Ruta: "/board/columns", Hecho: time.Now(),
		Sucursal: uuid.New(), Persona: "u-1", Clave: "k",
	}); err != nil {
		t.Fatalf("no tenía que fallar: %v", err)
	}
	if clave != "clave-de-prueba" {
		t.Errorf("sin token hay que mandar la clave, y se mandó %q", clave)
	}
	if autorizacion != "" {
		t.Errorf("sin token no se inventa un Authorization: %q", autorizacion)
	}
}

// UN 401 ES CAÍDA, NO RECHAZO. Y un 403 sí es rechazo.
//
// Tercer acto del 16/09/2026, y el que explica por qué los dos arreglos anteriores no
// rescataron nada por sí solos. `POST /api/board/columns` contestaba 401; este servicio
// metía todo 4xx en el mismo saco («el reparto dijo que no»), así que el apunte que CREA
// la zona se marcó RECHAZADO y detrás se cayeron los cinco que colocaban pedidos dentro.
// Seis apuntes de trabajo real esperando a que «una persona decida» sobre una credencial
// que no viajó — que es algo que ninguna persona delante de un teléfono puede decidir.
//
// Y un rechazo no se reintenta solo: arreglado el reenvío del token, los seis SEGUÍAN
// muertos en la bandeja. El segundo fallo tapaba al primero.
//
// La línea es si el reparto entendió QUIÉN preguntaba. Con 401 no lo sabía: es nuestro y
// se reintenta. Con 403 sí lo sabía y dijo que no puede: eso lo decide una persona, y
// reintentarlo para siempre sería un bucle.
func TestUn401EsCaidaYUn403EsRechazo(t *testing.T) {
	var codigo int
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(codigo)
			_, _ = w.Write([]byte(`{"error":"Unauthorized"}`))
		}))
	defer servidor.Close()

	c := Nuevo(servidor.URL, "clave-de-prueba", 5*time.Second)
	aplicar := func() error {
		_, err := c.Aplicar(context.Background(), sincro.Peticion{
			Metodo: http.MethodPost, Ruta: "/board/columns", Hecho: time.Now(),
			Sucursal: uuid.New(), Persona: "u-1", Clave: "k", Token: "t",
		})
		return err
	}

	codigo = http.StatusUnauthorized
	err := aplicar()
	var rechazo *sincro.Rechazo
	if errors.As(err, &rechazo) {
		t.Errorf("un 401 se trató como rechazo (%q): el apunte se queda muerto en la "+
			"bandeja pidiendo que alguien decida sobre una credencial que no viajó, y "+
			"detrás se caen todos los que dependen de lo que iba a crear",
			rechazo.Motivo)
	}
	if err == nil {
		t.Error("un 401 tampoco es un éxito: el apunte no se escribió")
	}

	codigo = http.StatusForbidden
	if err := aplicar(); !errors.As(err, &rechazo) {
		t.Errorf("un 403 SÍ es rechazo —el reparto supo quién preguntaba y dijo que no—, "+
			"y salió %v: reintentarlo para siempre es un bucle", err)
	}
}

// NO SE MANDA NINGUNA CABECERA QUE NADIE LEA.
//
// `X-Persona` y `X-Sucursal` se escribieron en cada apunte desde el primer día y el
// reparto **nunca las miró** — cero lectores en `api/`. Medio protocolo, con nadie al otro
// lado, dando la impresión de que la identidad viajaba cuando no viajaba: es lo que hizo
// tardar en ver por qué `/api/board/columns` contestaba 401 «no viene token».
//
// Se quedan las que sí tienen lector, y la prueba las nombra para que quitar una de ellas
// por descuido se vea aquí.
func TestNoSeMandanCabecerasQueNadieLee(t *testing.T) {
	var vistas http.Header
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			vistas = r.Header.Clone()
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{}`))
		}))
	defer servidor.Close()

	hecho := time.Now().Add(-3 * time.Hour)
	c := Nuevo(servidor.URL, "clave-de-prueba", 5*time.Second)
	if _, err := c.Aplicar(context.Background(), sincro.Peticion{
		Metodo: http.MethodPost, Ruta: "/board/columns", Hecho: hecho,
		Sucursal: uuid.New(), Persona: "u-1", Clave: "k", Token: "t",
	}); err != nil {
		t.Fatalf("no tenía que fallar: %v", err)
	}

	for _, muerta := range []string{"X-Persona", "X-Sucursal", "X-Super-Admin"} {
		if v := vistas.Get(muerta); v != "" {
			t.Errorf("se sigue mandando %s (%q) y el reparto no la lee: es medio "+
				"protocolo escrito, y hace creer que la identidad viaja por ahí",
				muerta, v)
		}
	}
	// Y las que SÍ se leen siguen yendo. `X-Hecho-At` la lee `api/internal/api/rutas.go`
	// para guardar cuándo se hizo el trabajo y no cuándo llegó: lo que se marcó a las
	// cuatro tiene que constar como las cuatro.
	if vistas.Get("X-Hecho-At") == "" {
		t.Error("falta X-Hecho-At: sin ella el reparto fecha el trabajo cuando llega, " +
			"no cuando se hizo")
	}
	if vistas.Get("X-Apunte") != "k" {
		t.Errorf("falta X-Apunte: %q", vistas.Get("X-Apunte"))
	}
}

// EL `hasta` Y EL `continuar` DE LA RESPUESTA SE LEEN, y el cursor además se reenvía.
//
// Aquí estuvo el agujero del §3 visto desde este lado: `sobreCambios` tenía dos campos
// —`cambios` y `truncado`— y los otros dos se tiraban al decodificar. Sin `hasta`, quien
// llama no tiene más marca que la que él mismo mandó, así que una tanda cortada se anota
// como si hubiera llegado hasta el reloj y **lo que no cupo no lo vuelve a pedir nadie**.
// Sin `continuar`, el catálogo y el padrón no se pueden continuar cuando miles de filas
// comparten la misma marca, que es lo que hay en producción desde el traspaso.
func TestSeLeenElHastaYElCursorDeLaRespuesta(t *testing.T) {
	servido := "2026-09-14T10:41:07.5Z"
	var vista string
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			vista = r.URL.RequestURI()
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{
				"hasta": "` + servido + `",
				"completa": false,
				"truncado": true,
				"continuar": "elCursorDelReparto",
				"cambios": {"customers": {"puestos": [], "quitados": []}}
			}`))
		}))
	defer servidor.Close()

	c := Nuevo(servidor.URL, "clave-de-prueba", 5*time.Second)
	desde := time.Date(2026, 9, 14, 8, 0, 0, 0, time.UTC)
	techo := time.Date(2026, 9, 14, 11, 2, 31, 0, time.UTC)

	b, err := c.Diferencias(context.Background(), sincro.Ventana{
		Sucursal:  uuid.New(),
		Desde:     &desde,
		Hasta:     techo,
		Tope:      500,
		Continuar: "elCursorDelAparato",
	})
	if err != nil {
		t.Fatalf("no tenía que fallar: %v", err)
	}

	esperado, _ := time.Parse(time.RFC3339Nano, servido)
	if !b.Hasta.Equal(esperado) {
		t.Fatalf("no se leyó el «hasta» de la respuesta: %v. Sin él, quien llama anota la "+
			"marca que mandó y se salta lo que el reparto no llegó a servir", b.Hasta)
	}
	if !b.Truncado {
		t.Fatalf("no se leyó «truncado»")
	}
	if b.Continuar != "elCursorDelReparto" {
		t.Fatalf("no se leyó «continuar»: %q", b.Continuar)
	}
	if _, hay := b.Cambios["customers"]; !hay {
		t.Fatalf("no se leyeron los cambios: %v", b.Cambios)
	}
	if !strings.Contains(vista, "continuar=elCursorDelAparato") {
		t.Fatalf("el cursor del aparato no se reenvió al reparto: %s", vista)
	}
}

// Y sin cursor no se manda el parámetro vacío: un `continuar=` vacío no es «empieza de
// cero» por casualidad, lo es porque el reparto lo trata así, y mandarlo sólo confunde al
// leer un registro.
func TestSinCursorNoSeMandaElParametro(t *testing.T) {
	var vista string
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			vista = r.URL.RequestURI()
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"hasta":"2026-09-14T11:02:31Z","cambios":{}}`))
		}))
	defer servidor.Close()

	c := Nuevo(servidor.URL, "clave-de-prueba", 5*time.Second)
	if _, err := c.Diferencias(context.Background(), sincro.Ventana{
		Sucursal: uuid.New(),
		Hasta:    time.Date(2026, 9, 14, 11, 2, 31, 0, time.UTC),
		Tope:     500,
	}); err != nil {
		t.Fatalf("no tenía que fallar: %v", err)
	}
	if strings.Contains(vista, "continuar") {
		t.Fatalf("se mandó el cursor sin tenerlo: %s", vista)
	}
}

// EL ID DE UNA RUTA RECIÉN CREADA VIENE DENTRO DE `ruta`, NO EN LA RAÍZ.
//
// Ésta es la prueba del fallo que se pasó una tarde escondido el 21/09/2026: se armaba una
// ruta con sus paradas, subía bien, el servidor la guardaba entera —comprobado en su base:
// 5 paradas— y el teléfono enseñaba «Ver paradas (0)» con los kilómetros al lado.
//
// La causa era de una línea: aquí se leía sólo `id` en la raíz, y el reparto contesta al
// crear una ruta con `{"ruta": {...}, "avisos": {...}}`. Sin id no hay equivalencia, el
// `local-…` del aparato no se sustituye nunca, y los pedidos —que sí bajan enganchados al
// id de verdad— dejan de verse en la ruta que el aparato sigue mirando.
//
// Las dos formas van juntas a propósito: leer sólo una de las dos es justo el fallo.
func TestElIDDeLoCreadoSeLeeDeLasDosFormas(t *testing.T) {
	t.Parallel()

	const real = "0199b1f0-4444-7000-8000-000000000004"

	for _, caso := range []struct {
		nombre string
		cuerpo string
		quiere string
	}{
		{"en la raíz, como contestan los demás", `{"id":"` + real + `"}`, real},
		{
			"dentro de `ruta`, como contesta crear una ruta",
			`{"ruta":{"id":"` + real + `","routeCode":"RT-20260921-009"},"avisos":{}}`,
			real,
		},
		{"sin id: hay apuntes que no crean nada", `{"ok":true}`, ""},
	} {
		t.Run(caso.nombre, func(t *testing.T) {
			t.Parallel()
			srv := httptest.NewServer(http.HandlerFunc(
				func(w http.ResponseWriter, _ *http.Request) {
					w.Header().Set("Content-Type", "application/json")
					w.WriteHeader(http.StatusCreated)
					_, _ = w.Write([]byte(caso.cuerpo))
				}))
			defer srv.Close()

			aplicado, err := Nuevo(srv.URL, "clave", time.Second).
				Aplicar(context.Background(), sincro.Peticion{
					Metodo: http.MethodPost,
					Ruta:   "/routes",
					Cuerpo: []byte(`{}`),
					Clave:  "k1",
				})
			if err != nil {
				t.Fatalf("no debería fallar: %v", err)
			}
			salio := ""
			if aplicado.ID != nil {
				salio = aplicado.ID.String()
			}
			if salio != caso.quiere {
				t.Errorf("EL ID DE LO CREADO NO VUELVE AL APARATO: se esperaba %q y salió %q. "+
					"Sin él, el aparato se queda con su `local-…` y la ruta se le ve vacía "+
					"aunque arriba tenga todas sus paradas.", caso.quiere, salio)
			}
		})
	}
}

// EL 409 DEL ARMADO LLEGA ENTERO, CON EL PEDIDO Y LA RUTA QUE LO NOMBRAN.
//
// Es lo que pidió Jose el 21/09/2026: «esto ocurriría cuando la ruta se haya creado con
// pedidos que ya estuvieran en otra ruta, pero hay que notificarlo para eso». Una ruta que
// se arma sin señal sube por aquí, el reparto la rechaza, y el motivo tiene que llegar
// hasta la bandeja de «Rechazados, esperando a una persona» SIN recortarse y SIN volverse
// un «no se pudo guardar»: el pedido nombrado y la ruta en la que está es lo único que le
// dice al logístico qué tarjeta quitar.
//
// La frase se conserva LITERAL: aquí no se resume, no se traduce y no se acorta.
func TestEl409DelArmadoLlegaConElPedidoYLaRuta(t *testing.T) {
	const motivo = "1 de los 3 pedidos elegidos no pueden ir en esta ruta: " +
		"X-2992 (ya va en la ruta RT-20260921-002)."
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusConflict)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": motivo})
		}))
	defer servidor.Close()

	_, err := Nuevo(servidor.URL, "k", 5*time.Second).Aplicar(
		context.Background(), sincro.Peticion{
			Metodo: http.MethodPost, Ruta: "/routes",
			Cuerpo: json.RawMessage(`{"orderIds":["p1","p2","p3"]}`),
			Hecho:  time.Now(), Sucursal: uuid.New(), Persona: "x", Clave: "01J9A001",
		})
	var rechazo *sincro.Rechazo
	if !errors.As(err, &rechazo) {
		t.Fatalf("un 409 del reparto es un rechazo de negocio y lo mira una persona: %v", err)
	}
	if rechazo.Motivo != motivo {
		t.Fatalf("el motivo se recortó o se cambió:\n  %q\nse esperaba:\n  %q", rechazo.Motivo, motivo)
	}
	if !strings.Contains(rechazo.Motivo, "X-2992") || !strings.Contains(rechazo.Motivo, "RT-20260921-002") {
		t.Fatalf("el motivo tiene que nombrar el pedido Y su ruta: %q", rechazo.Motivo)
	}
}

// LA PAREJA: la ruta que SÍ se arma no deja ningún rechazo.
//
// Un aviso que sale siempre deja de leerse, y entonces tampoco se lee el día que importa
// (`CLAUDE.md` del repo, §3-quinquies). Sin esta prueba, «devolver Rechazo siempre» pasaría
// la de arriba.
func TestLaRutaQueSeArmaNoDejaRechazo(t *testing.T) {
	creada := uuid.New()
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusCreated)
			_ = json.NewEncoder(w).Encode(map[string]any{"id": creada})
		}))
	defer servidor.Close()

	aplicado, err := Nuevo(servidor.URL, "k", 5*time.Second).Aplicar(
		context.Background(), sincro.Peticion{
			Metodo: http.MethodPost, Ruta: "/routes",
			Cuerpo: json.RawMessage(`{"orderIds":["p1"]}`),
			Hecho:  time.Now(), Sucursal: uuid.New(), Persona: "x", Clave: "01J9A002",
		})
	if err != nil {
		t.Fatalf("no tenía que fallar: %v", err)
	}
	if aplicado.ID == nil || *aplicado.ID != creada {
		t.Fatalf("el id de la ruta creada tiene que volver al aparato: %v", aplicado.ID)
	}
}

// ---------------------------------------------------------------------------
// EL 4xx DEL REPARTO AL CERRAR UNA HOJA (`POST /routes/{id}/results`)
// ---------------------------------------------------------------------------
//
// Hasta el 08/10/2026 NADA ataba lo que este servicio hace con el 409 PARCIAL del cierre,
// y es una decisión de Jose, no un descuido: el reparto guarda las paradas que puede y
// rechaza las otras con `409 {error, aplicados[], rechazados[]}`; la WEB lee las dos
// listas y deja completar (CLAUDE.md §1, «Cerrar con rechazo parcial»), pero en la APK y el
// escritorio este servicio convierte CUALQUIER 4xx en un `Rechazo` del apunte entero con el
// texto de `error`, sin mirar `aplicados` ni `rechazados`. Resultado a propósito: la hoja
// queda `rechazada` en la bandeja con su motivo, y retiene el `completed` hasta que una
// persona decida allí (Reintentar/Descartar).
//
// Un comportamiento deliberado y sin prueba es un comportamiento que el próximo que «lo
// arregle» cambia sin saberlo —y entonces una hoja a medias se da por buena y se completa
// la ruta con paradas que el servidor no guardó—. Estas pruebas lo fijan tal cual ESTÁ. Si
// algún día el sincronizador pasa a leer `aplicados`, tienen que ponerse rojas, y quien lo
// haga las cambia A PROPÓSITO, con el CLAUDE.md delante.

// motivoDel409Parcial es el `error` REAL del reparto, con el conduce (el número de
// operación de la factura) ya interpolado. Su gramática la fija `motivoDelCierreIncompleto`
// en `api/internal/api/rutas.go`.
const motivoDel409Parcial = "Se guardaron 1 de las 2 paradas de esta hoja. 1 no se pudieron " +
	"guardar: PTB25-261005-1480 (ese pedido no va en esta ruta)."

// cuerpoDel409Parcial es la respuesta ENTERA: el `error` que lee este servicio más las dos
// listas que NO lee. Las dos listas van a propósito, para que la prueba falle si alguien
// empieza a tirar de ellas sin querer.
const cuerpoDel409Parcial = `{
	"error": "` + motivoDel409Parcial + `",
	"aplicados": [{"orderId": "A", "resultado": "entregado"}],
	"rechazados": [{
		"orderId": "B",
		"numeroOperacion": "PTB25-261005-1480",
		"motivo": "ese pedido no va en esta ruta"
	}]
}`

// cerrarHoja manda el apunte de resultados de una hoja a un servidor de mentira.
func cerrarHoja(t *testing.T, url string) (sincro.Aplicado, error) {
	t.Helper()
	return Nuevo(url, "k", 5*time.Second).Aplicar(context.Background(), sincro.Peticion{
		Metodo: http.MethodPost, Ruta: "/routes/r-1/results",
		Cuerpo: json.RawMessage(`{"resultados":[` +
			`{"orderId":"A","resultado":"entregado"},{"orderId":"B","resultado":"entregado"}]}`),
		Hecho: time.Now(), Sucursal: uuid.New(), Persona: "x", Clave: "01J9R001", Token: "t",
	})
}

// El servidor de mentira que contesta siempre lo mismo.
func conRespuesta(t *testing.T, codigo int, cuerpo string) (*httptest.Server, *[]string) {
	t.Helper()
	var vistas []string
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			vistas = append(vistas, r.Method+" "+r.URL.RequestURI())
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(codigo)
			_, _ = w.Write([]byte(cuerpo))
		}))
	t.Cleanup(servidor.Close)
	return servidor, &vistas
}

// EL 409 PARCIAL ES UN RECHAZO CON EL TEXTO DE `error`, ENTERO Y LITERAL.
//
// Ni un «no se pudo guardar» genérico, ni el `motivo` de la primera parada rechazada, ni el
// JSON crudo: lo que la persona lee en la bandeja es la frase que escribió el reparto, que
// dice cuántas entraron, cuáles no y por qué. Y no se aplica NADA a medias aquí: el
// resultado de un rechazo es un `Aplicado` vacío, o sea que la parada que SÍ se guardó
// (`aplicados`) no cambia nada de este lado.
func TestEl409ParcialDeLosResultadosEsRechazoConElTextoDeError(t *testing.T) {
	servidor, vistas := conRespuesta(t, http.StatusConflict, cuerpoDel409Parcial)

	aplicado, err := cerrarHoja(t, servidor.URL)

	var rechazo *sincro.Rechazo
	if !errors.As(err, &rechazo) {
		t.Fatalf("un 409 parcial tiene que ser un *sincro.Rechazo —la hoja se queda en la "+
			"bandeja y retiene el completed hasta que una persona decida—, y salió: %v", err)
	}
	if rechazo.Motivo != motivoDel409Parcial {
		t.Fatalf("el motivo tiene que ser EXACTAMENTE el `error` del reparto:\n  %q\nse esperaba:\n  %q",
			rechazo.Motivo, motivoDel409Parcial)
	}
	// Los dos sustitutos que alguien podría poner «por mejorar» y que dejan a la persona sin
	// saber qué tarjeta quitar: el `motivo` suelto de la parada, o el JSON a pelo.
	if rechazo.Motivo == "ese pedido no va en esta ruta" || strings.Contains(rechazo.Motivo, `"aplicados"`) {
		t.Fatalf("el motivo salió de las listas y no del `error`: %q", rechazo.Motivo)
	}
	if !strings.Contains(rechazo.Motivo, "PTB25-261005-1480") {
		t.Fatalf("el motivo tiene que nombrar el pedido por su número de operación: %q", rechazo.Motivo)
	}
	// Y lo guardado NO cuenta: este servicio no lee `aplicados`, ni siquiera para decir que
	// una parada entró. Es lo que hace que la hoja entera quede rechazada.
	if aplicado.ID != nil || len(aplicado.Descartados) != 0 {
		t.Fatalf("un rechazo no devuelve nada aplicado: %+v", aplicado)
	}
	// Una sola llamada: el rechazo no se reintenta dentro de `Aplicar`.
	if len(*vistas) != 1 || (*vistas)[0] != "POST /api/routes/r-1/results" {
		t.Fatalf("se esperaba una sola llamada a POST /api/routes/r-1/results: %v", *vistas)
	}
}

// LA PAREJA: UNA CAÍDA NO ES UN RECHAZO, y por eso se reintenta.
//
// El 5xx y el corte de red tienen que salir como error NORMAL: arriba (`sincro.unApunte`)
// un error que no es `*Rechazo` corta el lote y el apunte SE QUEDA EN LA COLA del aparato,
// que lo vuelve a mandar. Tratarlo como rechazo llenaría la bandeja de «el reparto dijo
// que no» el día que el reparto se reinicie, con hojas buenas que una persona tendría que
// reintentar a mano; y no tratarlo como error —darlo por aplicado— sería descartar en
// silencio (§4). Ninguno de los dos pasa.
//
// El cuerpo de los 5xx es A PROPÓSITO el del 409 parcial: aunque el texto diga «Se guardaron
// 1 de las 2», si el código es 5xx no es una respuesta de negocio.
func TestUn5xxOUnCorteDeRedNoSonRechazoYSeReintentan(t *testing.T) {
	t.Run("5xx", func(t *testing.T) {
		for _, codigo := range []int{
			http.StatusInternalServerError, http.StatusBadGateway,
			http.StatusServiceUnavailable, http.StatusGatewayTimeout,
		} {
			servidor, _ := conRespuesta(t, codigo, cuerpoDel409Parcial)
			aplicado, err := cerrarHoja(t, servidor.URL)
			if err == nil {
				t.Fatalf("%d: una caída del reparto no puede darse por aplicada: %+v", codigo, aplicado)
			}
			var rechazo *sincro.Rechazo
			if errors.As(err, &rechazo) {
				t.Errorf("%d se trató como rechazo (%q): se quedaría muerto en la bandeja en "+
					"vez de reintentarse", codigo, rechazo.Motivo)
			}
		}
	})

	t.Run("el reparto no contesta", func(t *testing.T) {
		servidor := httptest.NewServer(http.NotFoundHandler())
		url := servidor.URL
		servidor.Close() // conexión rechazada: el reparto está apagado.

		_, err := cerrarHoja(t, url)
		var rechazo *sincro.Rechazo
		if err == nil || errors.As(err, &rechazo) {
			t.Fatalf("un reparto apagado es una caída que se reintenta, no un rechazo: %v", err)
		}
	})

	t.Run("la conexión se corta a mitad", func(t *testing.T) {
		servidor := httptest.NewServer(http.HandlerFunc(
			func(w http.ResponseWriter, _ *http.Request) {
				conexion, _, err := w.(http.Hijacker).Hijack()
				if err == nil {
					_ = conexion.Close() // sin una sola línea de respuesta.
				}
			}))
		defer servidor.Close()

		_, err := cerrarHoja(t, servidor.URL)
		var rechazo *sincro.Rechazo
		if err == nil || errors.As(err, &rechazo) {
			t.Fatalf("un corte de red es una caída que se reintenta, no un rechazo: %v", err)
		}
	})
}

// TODO 4xx CON SU MOTIVO LITERAL, Y UN 4xx QUE NO ES DEL REPARTO NO ES RECHAZO.
//
// Tabla de lo que hay HOY (no de lo que debería haber): el 409 sin listas —«La ruta está
// completada», que es el que contesta cuando la hoja llega tarde—, el 400 de cuerpo mal
// formado, el 403 de alcance y el 404 CON `error` (que es el del reparto) son rechazos con su
// frase; el 401 y el 404 sin `error` son nuestros y son caída (ver `Test404DeRutaEsCaida…` y
// `TestUn401EsCaida…`, que cubren el resto de la línea).
//
// El caso del 409 vacío fija otra cosa: un rechazo SIEMPRE lleva motivo, porque un apunte
// rechazado sin motivo en la bandeja es el descarte en silencio.
func TestCadaCuatroXXLlevaSuMotivoLiteralYSoloElDelRepartoEsRechazo(t *testing.T) {
	for _, caso := range []struct {
		nombre  string
		codigo  int
		cuerpo  string
		rechazo bool
		motivo  string
	}{
		{
			"409 sin aplicados ni rechazados: la ruta ya está completada",
			http.StatusConflict,
			`{"error":"La ruta está completada y no se puede modificar ni eliminar: se conserva como histórico."}`,
			true,
			"La ruta está completada y no se puede modificar ni eliminar: se conserva como histórico.",
		},
		{
			"400 con error", http.StatusBadRequest,
			`{"error":"El cuerpo no es un JSON válido"}`,
			true, "El cuerpo no es un JSON válido",
		},
		{
			"403 con error", http.StatusForbidden,
			`{"error":"esta cuenta no está dada de alta en ninguna sucursal: pide en la oficina que te asignen la tuya"}`,
			true,
			"esta cuenta no está dada de alta en ninguna sucursal: pide en la oficina que te asignen la tuya",
		},
		{
			"404 con error: la ruta no existe PARA EL REPARTO", http.StatusNotFound,
			`{"error":"No encontrada"}`,
			true, "No encontrada",
		},
		{
			"409 sin cuerpo: aun así lleva motivo", http.StatusConflict, ``,
			true, "El reparto no dijo por qué",
		},
		{
			"404 sin `error` (nuestro, no del reparto)", http.StatusNotFound,
			`{"mensaje":"nada por aquí"}`,
			false, "",
		},
		{
			"401 (la credencial no llegó)", http.StatusUnauthorized,
			`{"error":"no viene token"}`,
			false, "",
		},
	} {
		t.Run(caso.nombre, func(t *testing.T) {
			servidor, _ := conRespuesta(t, caso.codigo, caso.cuerpo)
			_, err := cerrarHoja(t, servidor.URL)
			if err == nil {
				t.Fatalf("un %d no puede darse por aplicado", caso.codigo)
			}
			var rechazo *sincro.Rechazo
			es := errors.As(err, &rechazo)
			if es != caso.rechazo {
				t.Fatalf("%d: rechazo = %v, se esperaba %v (%v)", caso.codigo, es, caso.rechazo, err)
			}
			if es && rechazo.Motivo != caso.motivo {
				t.Errorf("motivo = %q, se esperaba el literal %q", rechazo.Motivo, caso.motivo)
			}
		})
	}
}

// CREAR UNA RUTA: EL ID SE LEE DE LA RUTA SOLA Y DE LA FORMA ANTIGUA.
//
// La 1.0.28 de la API ya NO envuelve: `POST /api/routes` contesta la ruta sola, con su `id`
// en la raíz (`responderConLaRuta`). Las APK viejas y los reparto viejos todavía conocen el
// envoltorio `{ruta: {id}, avisos: []}`, y un sincronizador que sólo supiera una de las
// dos dejaría al aparato sin el id de lo que creó: sin id no hay equivalencia, el `local-…`
// no se sustituye nunca y la ruta se ve vacía aunque arriba tenga todas sus paradas
// (el «Ver paradas (0)» del 21/09/2026).
//
// La ruta sola trae además sus paradas, y CADA UNA TIENE SU `id`: la prueba comprueba que el
// que vuelve es el de la ruta y no el de una parada. `TestElIDDeLoCreadoSeLeeDeLasDosFormas`
// cubre los cuerpos mínimos; ésta, la forma real.
func TestElIDDeLaRutaSolaYDeLaFormaAntiguaSeLeenAmbos(t *testing.T) {
	const (
		ruta     = "0199b1f0-4444-7000-8000-000000000004"
		parada   = "0199b1f0-5555-7000-8000-000000000005"
		otraRuta = "0199b1f0-6666-7000-8000-000000000006"
	)
	for _, caso := range []struct {
		nombre string
		cuerpo string
		quiere string
	}{
		{
			"la ruta sola, con su id en la raíz y paradas con id propio",
			`{"id":"` + ruta + `","name":null,"routeCode":"RT-20261008-001","status":"planned",` +
				`"totalDistance":12.5,"orders":[{"id":"` + parada + `","operationNumber":"PTB25-261005-1480"}]}`,
			ruta,
		},
		{
			"la forma antigua: {ruta:{id}, avisos:[]}",
			`{"ruta":{"id":"` + ruta + `","routeCode":"RT-20261008-001",` +
				`"orders":[{"id":"` + parada + `"}]},"avisos":[]}`,
			ruta,
		},
		{
			// La raíz manda: es la forma nueva, y una respuesta con las dos no puede dar
			// el id de la que se está dejando.
			"las dos a la vez: manda la raíz",
			`{"id":"` + ruta + `","ruta":{"id":"` + otraRuta + `"},"avisos":[]}`,
			ruta,
		},
		{
			// Sólo la parada tiene id: no es el id de lo creado.
			"sin id de ruta, sólo el de una parada anidada: no se inventa",
			`{"orders":[{"id":"` + parada + `"}],"avisos":[]}`,
			"",
		},
	} {
		t.Run(caso.nombre, func(t *testing.T) {
			servidor, vistas := conRespuesta(t, http.StatusCreated, caso.cuerpo)
			aplicado, err := Nuevo(servidor.URL, "k", 5*time.Second).Aplicar(
				context.Background(), sincro.Peticion{
					Metodo: http.MethodPost, Ruta: "/routes", Cuerpo: []byte(`{"orderIds":["p1"]}`),
					Hecho: time.Now(), Sucursal: uuid.New(), Persona: "x", Clave: "01J9R002", Token: "t",
				})
			if err != nil {
				t.Fatalf("un 201 no puede fallar: %v", err)
			}
			salio := ""
			if aplicado.ID != nil {
				salio = aplicado.ID.String()
			}
			if salio != caso.quiere {
				t.Errorf("el id que vuelve al aparato es %q y se esperaba %q: sin el de la ruta, el "+
					"`local-…` no se sustituye y la ruta se le ve vacía", salio, caso.quiere)
			}
			if len(*vistas) != 1 || (*vistas)[0] != "POST /api/routes" {
				t.Errorf("llamada inesperada: %v", *vistas)
			}
		})
	}
}

// UN 403 CON `codigo: "sin_permiso_reparto"` NO ES UN RECHAZO DEL APUNTE (08/10/2026).
//
// Quien dice que no es el ROL de la persona. Convertirlo en `*Rechazo` marcaría `rechazado`
// toda su cola y la retendría en la bandeja hasta que alguien decidiera, por algo que se
// arregla en Accesos. Tiene que salir un error APARTE (`*sincro.SinPermiso`) para que la
// subida conteste 403 sin anotar nada.
//
// LA PAREJA es la de arriba (`TestUn401EsCaidaYUn403EsRechazo` y la tabla de 4xx): el 403 del
// alcance de sucursal NO lleva `codigo` y sigue siendo rechazo. Sin la pareja, «devolver
// SinPermiso con cualquier 403» pasaría ésta con nota.
func TestUn403ConCodigoDeSinPermisoNoEsRechazoPeroUnoSinCodigoSi(t *testing.T) {
	for _, caso := range []struct {
		nombre     string
		cuerpo     string
		sinPermiso bool
	}{
		{"403 del rol, con codigo",
			`{"error":"No tienes permiso para entrar a Reparto.","codigo":"sin_permiso_reparto"}`, true},
		{"403 del alcance de sucursal, sin codigo",
			`{"error":"tu sucursal MOA no está dada de alta en Reparto: pide en la oficina que la den de alta"}`, false},
		{"403 con OTRO codigo",
			`{"error":"algo","codigo":"otra_cosa"}`, false},
	} {
		t.Run(caso.nombre, func(t *testing.T) {
			servidor, _ := conRespuesta(t, http.StatusForbidden, caso.cuerpo)
			_, err := cerrarHoja(t, servidor.URL)
			if err == nil {
				t.Fatal("un 403 no puede darse por aplicado")
			}
			var sin *sincro.SinPermiso
			var rechazo *sincro.Rechazo
			if got := errors.As(err, &sin); got != caso.sinPermiso {
				t.Fatalf("SinPermiso = %v, se esperaba %v (%v)", got, caso.sinPermiso, err)
			}
			if got := errors.As(err, &rechazo); got == caso.sinPermiso {
				t.Fatalf("Rechazo = %v: tiene que ser lo contrario de SinPermiso (%v)", got, err)
			}
		})
	}
}
