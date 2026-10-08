package api

// EL AVISO SALE DE SU SUCURSAL, Y EL CORTE LO HACE EL SERVIDOR.
//
// Jose, 29/09/2026: «el aviso por sucursales, ese evento debe de salir de su sucursal, no
// puede dar una bajada a las otras 7». Y la decisión de cómo: «la decisión, dale, para que
// haga correcto: más trabajo y sin fugas, exactamente eso» — o sea que el aviso **no le
// llega** a quien no le toca, no que le llegue y lo tire. Saber que «en Camagüey pasó algo»
// ya es contar algo de Camagüey.
//
// Lo que estas pruebas vigilan, y las tres primeras son las que importan:
//
//  1. un gesto de UNA sucursal no le cuesta una bajada a las otras SIETE (con el número
//     medido antes y después, en el propio mensaje de la prueba);
//  2. **un aviso SIN sucursal le sigue llegando a TODOS** — el catálogo, los ajustes, la
//     lista de sucursales y el canal con PEDIDO. Éste es el fallo peor de los dos, porque
//     no falla: la pantalla se queda vieja, no hay error y no sale en ningún registro;
//  3. a un LOGISTICO de Holguín no le llega lo de Santiago, comprobado contra el canal HTTP
//     de verdad y no leyendo el código; y su gemela en positivo, que lo suyo SÍ le llega.
//
// Y la trampa que casi se cuela al escribir esto: **el freno de quince segundos era por
// tipo**, así que acotar por sucursal sin tocarlo habría hecho que el tablero de Holguín se
// comiera el de Camagüey dentro de la misma ventana. Arreglando el ruido se habría abierto
// justo el fallo que se venía a evitar. Ver `TestElFrenoNoSeCruzaEntreSucursales`.

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// --------------------------------------------------------------------------- las ocho

// LAS OCHO SUCURSALES, con su código de verdad (`../../CLAUDE.md` §5). Se usan las ocho y
// no dos porque el número que hay que medir es «a cuántas de las OTRAS SIETE les cuesta
// una bajada un gesto de la primera», y con dos ese número no se ve.
var lasOchoSucursales = []struct {
	codigo string
	id     uuid.UUID
}{
	{"CAM", uuid.MustParse("0a000001-0000-0000-0000-000000000001")},
	{"GR", uuid.MustParse("0a000002-0000-0000-0000-000000000002")},
	{"GTO", uuid.MustParse("0a000003-0000-0000-0000-000000000003")},
	{"HAB", uuid.MustParse("0a000004-0000-0000-0000-000000000004")},
	{"HOL", uuid.MustParse("0a000005-0000-0000-0000-000000000005")},
	{"SS", uuid.MustParse("0a000006-0000-0000-0000-000000000006")},
	{"STG", uuid.MustParse("0a000007-0000-0000-0000-000000000007")},
	{"TUN", uuid.MustParse("0a000008-0000-0000-0000-000000000008")},
}

func idDeSucursal(t *testing.T, codigo string) uuid.UUID {
	t.Helper()
	for _, s := range lasOchoSucursales {
		if s.codigo == codigo {
			return s.id
		}
	}
	t.Fatalf("%q no es una de las ocho sucursales", codigo)
	return uuid.Nil
}

// --------------------------------------------------------------------------- el doble

// dobleDeLasOcho resuelve las ocho por CÓDIGO y por id.
//
// Por código porque **es lo que manda Accesos de verdad**: sus tokens firman `CAM`, `HOL`,
// `STG`… y no un uuid. Una prueba que meta el uuid en `branchId` copia la suposición que
// el código ya tuvo una vez, y con ella toda la api se creyó acotada mientras un
// ADMINISTRADOR de Camagüey veía las tres sucursales (24/09/2026, `internal/alcance`).
type dobleDeLasOcho struct{ sqlc.Querier }

func (dobleDeLasOcho) BuscarSucursalPorCodigo(_ context.Context, codigo *string) (sqlc.BuscarSucursalPorCodigoRow, error) {
	if codigo != nil {
		for _, s := range lasOchoSucursales {
			if s.codigo == *codigo {
				c := s.codigo
				return sqlc.BuscarSucursalPorCodigoRow{ID: s.id, ExternalID: &c}, nil
			}
		}
	}
	return sqlc.BuscarSucursalPorCodigoRow{}, pgx.ErrNoRows
}

func (dobleDeLasOcho) ResolverSucursal(_ context.Context, id uuid.UUID) (sqlc.ResolverSucursalRow, error) {
	for _, s := range lasOchoSucursales {
		if s.id == id {
			c := s.codigo
			return sqlc.ResolverSucursalRow{ID: s.id, ExternalID: &c}, nil
		}
	}
	return sqlc.ResolverSucursalRow{}, pgx.ErrNoRows
}

type fuenteDeLasOcho struct{ q dobleDeLasOcho }

func (f fuenteDeLasOcho) Consultas() sqlc.Querier { return f.q }
func (f fuenteDeLasOcho) EnTx(_ context.Context, fn func(sqlc.Querier) error) error {
	return fn(f.q)
}

func porteriaDeLasOcho(t *testing.T) *alcance.Porteria {
	t.Helper()
	return alcance.NuevaPorteria(fuenteDeLasOcho{}, slog.New(slog.NewTextHandler(io.Discard, nil)))
}

// alcanceDe monta el alcance de una persona igual que lo monta la portería en cada
// petición: mismo camino, misma regla. No se fabrica a mano a propósito — un `Acotado`
// escrito en la prueba sería una segunda copia de la regla de permisos, y la que se olvide
// de actualizar es por donde se cuela alguien.
func alcanceDe(t *testing.T, rol, sucursal string) context.Context {
	t.Helper()
	a, err := porteriaDeLasOcho(t).Resolver(context.Background(),
		&auth.Usuario{ID: "u", Rol: rol, Sucursal: sucursal}, "")
	if err != nil {
		t.Fatalf("no se pudo resolver el alcance de %s/%s: %v", rol, sucursal, err)
	}
	return alcance.Con(context.Background(), a)
}

// --------------------------------------------------------------------------- lo medido

// recibio dice si a ese abonado le llegó algo antes del plazo. El plazo es corto porque el
// reparto es síncrono: si no llegó ya, no va a llegar.
func recibio(canal <-chan Cambio) (Cambio, bool) {
	select {
	case c, abierto := <-canal:
		return c, abierto
	case <-time.After(150 * time.Millisecond):
		return Cambio{}, false
	}
}

// LO QUE CUESTA HOY UN GESTO DE UNA SOLA SUCURSAL, con el número delante.
//
// Se miden las DOS formas en la misma prueba y contra el mismo bus, que es la única manera
// de que el «antes» y el «después» sean comparables: `Suscribir()` es exactamente lo que
// hacía cada conexión hasta el 29/09/2026 —se lo lleva todo—, y `SuscribirDe(suya)` es lo
// que hace ahora.
func TestUnGestoDeUnaSucursalNoBajaLasOtrasSiete(t *testing.T) {
	cam := idDeSucursal(t, "CAM").String()

	// --- ANTES: ocho conexiones sin acotar -----------------------------------------
	antes := NuevoDifusor()
	canalesAntes := make([]<-chan Cambio, 0, len(lasOchoSucursales))
	for range lasOchoSucursales {
		ch, cortar, vivo := antes.Suscribir()
		if !vivo {
			t.Fatal("el bus tendría que estar abierto")
		}
		defer cortar()
		canalesAntes = append(canalesAntes, ch)
	}
	antes.AvisarDe(CambioTablero, cam, nil)
	tocadosAntes := 0
	for _, ch := range canalesAntes {
		if _, hay := recibio(ch); hay {
			tocadosAntes++
		}
	}

	// --- DESPUÉS: cada conexión con la suya ----------------------------------------
	despues := NuevoDifusor()
	canales := map[string]<-chan Cambio{}
	for _, s := range lasOchoSucursales {
		ch, cortar, vivo := despues.SuscribirDe(s.id.String())
		if !vivo {
			t.Fatal("el bus tendría que estar abierto")
		}
		defer cortar()
		canales[s.codigo] = ch
	}
	despues.AvisarDe(CambioTablero, cam, nil)

	tocados := []string{}
	for _, s := range lasOchoSucursales {
		if _, hay := recibio(canales[s.codigo]); hay {
			tocados = append(tocados, s.codigo)
		}
	}

	t.Logf("un gesto en el tablero de CAM toca: ANTES %d de 8 conexiones, DESPUÉS %d de 8 (%v)",
		tocadosAntes, len(tocados), tocados)

	if tocadosAntes != len(lasOchoSucursales) {
		t.Fatalf("la medida del ANTES no vale: tocó %d de %d, y sin acotar tiene que "+
			"tocarlas todas. Si esto cambia, el número del DESPUÉS no se puede comparar "+
			"con nada", tocadosAntes, len(lasOchoSucursales))
	}
	if len(tocados) != 1 || tocados[0] != "CAM" {
		t.Errorf("un cambio del tablero de CAM llegó a %v.\n"+
			"  Tenía que llegar SÓLO a CAM: cada una de las otras se baja su tablero "+
			"entero por nada, y son ocho navegadores en la oficina más los teléfonos, "+
			"por la conexión de allá.", tocados)
	}
}

// EL OTRO LADO, Y ES EL QUE MÁS DUELE SI SE ROMPE.
//
// El catálogo, los ajustes, la lista de sucursales y el canal con PEDIDO no son de ninguna
// sucursal en concreto: son de las ocho. Si al acotar se leyeran como «de ninguna», no le
// llegarían a nadie — y eso no falla, no da error y no sale en ningún registro: la tasa se
// queda vieja y con ella se convierte TODO importe que se pinta.
func TestUnAvisoSinSucursalLlegaALasOcho(t *testing.T) {
	for _, tipo := range []string{CambioCatalogo, CambioAjustes, CambioSucursales, CambioCanal, CambioVehiculos} {
		t.Run(tipo, func(t *testing.T) {
			d := NuevoDifusor()
			canales := map[string]<-chan Cambio{}
			for _, s := range lasOchoSucursales {
				ch, cortar, _ := d.SuscribirDe(s.id.String())
				defer cortar()
				canales[s.codigo] = ch
			}
			// Y quien ve las ocho, que también tiene que enterarse.
			todas, cortarTodas, _ := d.Suscribir()
			defer cortarTodas()

			if !d.Avisar(tipo, nil) {
				t.Fatalf("el aviso %q no salió del bus", tipo)
			}

			faltan := []string{}
			for _, s := range lasOchoSucursales {
				if _, hay := recibio(canales[s.codigo]); !hay {
					faltan = append(faltan, s.codigo)
				}
			}
			if len(faltan) > 0 {
				t.Errorf("el aviso %q NO llegó a %v.\n"+
					"  Ese aviso no es de ninguna sucursal: es de las ocho. Que no llegue "+
					"no falla y no se ve — la pantalla se queda con lo que pintó al "+
					"abrirse y nadie sabe por qué.", tipo, faltan)
			}
			if _, hay := recibio(todas); !hay {
				t.Errorf("el aviso %q no le llegó a quien ve las ocho sucursales", tipo)
			}
		})
	}
}

// DESARROLLADOR y SUPER ADMIN se enteran de las OCHO, una por una.
func TestQuienVeLasOchoSeEnteraDeTodas(t *testing.T) {
	d := NuevoDifusor()
	// El freno es por tipo y sucursal, así que ocho sucursales seguidas salen las ocho;
	// aun así se usa un tipo distinto por vuelta para que esta prueba no dependa de eso.
	todas, cortar, _ := d.Suscribir()
	defer cortar()

	for _, s := range lasOchoSucursales {
		d.AvisarDe(CambioTablero, s.id.String(), nil)
		c, hay := recibio(todas)
		if !hay {
			t.Fatalf("a quien ve las ocho no le llegó el tablero de %s", s.codigo)
		}
		if c.Sucursal != s.id.String() {
			t.Errorf("le llegó el tablero de %q y se esperaba el de %s", c.Sucursal, s.codigo)
		}
	}
}

// LA TRAMPA DEL FRENO. Era por tipo; con el aviso acotado tiene que ser por tipo Y
// sucursal, o Holguín se come el aviso de Camagüey dentro de la misma ventana de quince
// segundos y esa pantalla se queda quieta hasta el temporizador.
//
// SE PRUEBA CON `pedidos` Y NO CON `tablero` — 29/09/2026. Esta prueba estaba escrita con
// `tablero`, que era el ejemplo vivo mientras TODOS los tipos se frenaban. Ya no: desde hoy
// el freno es sólo de los tres que nombra `tiposFrenados` y `tablero` sale al momento. Lo
// que esta prueba comprueba —que la clave del freno lleva la sucursal— no ha cambiado, así
// que se muda al tipo frenado que más volumen tiene.
func TestElFrenoNoSeCruzaEntreSucursales(t *testing.T) {
	cam, hol := idDeSucursal(t, "CAM").String(), idDeSucursal(t, "HOL").String()

	d := NuevoDifusor()
	reloj := time.Now()
	d.ahora = func() time.Time { return reloj }
	sinDespertadores(d)

	todas, cortar, _ := d.Suscribir()
	defer cortar()

	if !d.AvisarDe(CambioPedidos, cam, nil) {
		t.Fatal("el primero tenía que salir")
	}
	// DENTRO del freno, pero de OTRA sucursal: tiene que salir igual.
	reloj = reloj.Add(time.Second)
	if !d.AvisarDe(CambioPedidos, hol, nil) {
		t.Error("los pedidos de Holguín se quedaron frenados por los de Camagüey.\n" +
			"  El freno tiene que ser por tipo Y sucursal: si no, el aviso de una se come " +
			"el de la otra y esa pantalla no se entera hasta el temporizador.")
	}
	// Y dentro del freno de la MISMA: ése sí se para (y se guarda como pendiente).
	reloj = reloj.Add(time.Second)
	if d.AvisarDe(CambioPedidos, cam, nil) {
		t.Error("dos avisos de la misma sucursal en dos segundos: el segundo tenía que " +
			"quedarse dentro del freno")
	}

	recibidas := map[string]bool{}
	for i := 0; i < 2; i++ {
		c, hay := recibio(todas)
		if !hay {
			t.Fatalf("sólo salieron %d avisos de los 2 que tenían que salir", i)
		}
		recibidas[c.Sucursal] = true
	}
	if !recibidas[cam] || !recibidas[hol] {
		t.Errorf("salieron %v; tenían que salir el de CAM y el de HOL", recibidas)
	}

	// Y el pendiente de CAM sale al vencer el freno, no se pierde.
	reloj = reloj.Add(FrenoAvisos + time.Second)
	d.SoltarPendientes()
	if c, hay := recibio(todas); !hay || c.Sucursal != cam {
		t.Errorf("el aviso de CAM que se quedó dentro del freno no salió al vencer "+
			"(llegó %+v, %v)", c, hay)
	}
}

// --------------------------------------------------------------------------- la tabla

// QUÉ AVISO PUEDE LLEVAR SUCURSAL Y CUÁL NO. La tabla está escrita en `eventos.go`, encima
// del `init()`, con el porqué de cada uno; esto la fija para que cambiar de lado uno de los
// ganchos obligue a venir aquí — y de paso a leer ese porqué.
//
// LOS SEIS ACOTADOS RECIBEN LA SUCURSAL, no la adivinan — 01/10/2026. Hasta hoy la sacaba el
// bus del alcance de la petición, y esta prueba comprobaba eso; era justo la mitad que
// fallaba en producción, porque el alcance de quien ve las ocho es «todas» y entonces el
// aviso salía pelado. Ahora se les pasa la de la FILA, así que lo que esto fija es otra cosa
// y más dura: **que el gancho publica la sucursal que le dan, tal cual, sin tocarla**.
//
// Los cinco GLOBALES ni la aceptan: su firma no tiene dónde ponerla. Eso no es un descuido,
// es lo que impide que alguien los acote sin querer y deje a las otras siete sin enterarse de
// un producto nuevo o de un cambio de tasa.
func TestLaTablaDeQueAvisoLlevaSucursal(t *testing.T) {
	acotados := []struct {
		nombre string
		gancho func(context.Context, string)
		tipo   string
		porque string
	}{
		{"tablero", avisarCambioDelTablero, CambioTablero, "board_columns.branch_id"},
		{"rutas", avisarCambioDeRutas, CambioRutas, "routes.branch_id"},
		{"pedidos", avisarCambioDePedidos, CambioPedidos, "orders.branch_id"},
		{"almacenes", avisarCambioDeAlmacenes, CambioAlmacenes,
			"el código de sucursal viene en el cuerpo y se comprueba contra las visibles"},
		// LOS DOS DE LA FLOTA, Y VAN EN LADOS DISTINTOS. Era UN solo gancho global hasta el
		// 29/09/2026, y por eso dar de alta un camión en Camagüey costaba a las otras siete
		// una petición de `/api/vehicles` y otra de `/api/settings` para pintar lo mismo.
		{"vehiculos", avisarCambioDeVehiculos, CambioVehiculos, "vehicles.branch_id"},
		{"clientes", avisarCambioDeClientes, CambioClientes,
			"la coordenada del cliente es la que ordena las paradas de SU sucursal"},
		// LA TASA. Mismo tipo que los ajustes globales y acotada: el tipo dice QUÉ volver a
		// pedir, la sucursal dice A QUIÉN le cambió.
		{"tasa de una sucursal", avisarTasaDeSucursal, CambioAjustes, "settings_por_sucursal"},
	}
	globales := []struct {
		nombre string
		gancho func(context.Context)
		tipo   string
		porque string
	}{
		{"catalogo", avisarCambioDelCatalogo, CambioCatalogo,
			"POST /api/products/sync trae el catálogo de VARIAS sucursales y avisa una vez, " +
				"y corregir un producto es sólo del SUPER ADMIN"},
		{"tipos de vehiculo", avisarCambioDeTiposDeVehiculo, CambioVehiculos,
			"vehicle_types no tiene columna de sucursal ninguna: es de toda la empresa"},
		{"sucursales", avisarCambioDeSucursales, CambioSucursales, "la lista es de todos"},
		{"ajustes", avisarCambioDeAjustes, CambioAjustes, "la moneda y la tasa son de toda la empresa"},
		{"canal", avisarCambioEnElCanal, CambioCanal, "la pantalla del canal mira la cola entera"},
	}

	// SE MIRA CONTRA UN BUS DE PRUEBAS. Los ganchos publican en `busEventos`, que es del
	// paquete; se cambia por uno limpio para que el freno de quince segundos de otra
	// prueba no se coma éstos.
	anterior := busEventos
	t.Cleanup(func() { busEventos = anterior })

	// EL UUID VA A MANO, no `idDeSucursal(...)`: una prueba que compara contra lo que el
	// código le dio no comprueba nada. Es el de Camagüey de `lasOchoSucursales`.
	const camAMano = "0a000001-0000-0000-0000-000000000001"
	// Y EL ALCANCE ES DE OTRA SUCURSAL A PROPÓSITO —Holguín— para que se vea que el gancho
	// publica lo que le PASAN y no lo que diga el contexto. Con el alcance de Camagüey, un
	// gancho que siguiera leyendo el contexto saldría verde.
	ctx := alcanceDe(t, "ADMINISTRADOR", "HOL")

	for _, c := range acotados {
		t.Run(c.nombre, func(t *testing.T) {
			busEventos = NuevoDifusor()
			canal, cortar, _ := busEventos.Suscribir()
			defer cortar()

			c.gancho(ctx, camAMano)

			cambio, hay := recibio(canal)
			if !hay {
				t.Fatalf("el gancho de %s no publicó nada", c.nombre)
			}
			if cambio.Tipo != c.tipo {
				t.Errorf("publicó el tipo %q y le toca %q", cambio.Tipo, c.tipo)
			}
			if cambio.Sucursal != camAMano {
				t.Errorf("el aviso %q se publicó para la sucursal %s y salió con %q.\n"+
					"  El gancho tiene que publicar LA QUE LE DAN —la de la fila que se "+
					"escribió— y no la del alcance de quien llamó, que aquí es Holguín.\n"+
					"  Motivo por el que este aviso va acotado: %s",
					c.tipo, camAMano, cambio.Sucursal, c.porque)
			}
		})
	}

	for _, c := range globales {
		t.Run(c.nombre, func(t *testing.T) {
			busEventos = NuevoDifusor()
			canal, cortar, _ := busEventos.Suscribir()
			defer cortar()

			c.gancho(ctx)

			cambio, hay := recibio(canal)
			if !hay {
				t.Fatalf("el gancho de %s no publicó nada", c.nombre)
			}
			if cambio.Tipo != c.tipo {
				t.Errorf("publicó el tipo %q y le toca %q", cambio.Tipo, c.tipo)
			}
			if cambio.Sucursal != "" {
				t.Errorf("el aviso %q salió acotado a %q y tiene que ir a TODAS.\n"+
					"  Motivo: %s.\n"+
					"  Acotarlo deja a las otras siete sin enterarse, y eso no falla, no "+
					"da error y no sale en ningún registro.",
					c.tipo, cambio.Sucursal, c.porque)
			}
		})
	}
}

// «NO SE SABE» NO ES «DE NINGUNA». Un aviso publicado sin sucursal —porque quien avisa no la
// tiene: el webhook de PEDIDO, el catálogo, los ajustes— le llega a TODOS, no a nadie.
//
// Es la mitad de este trabajo que más fácil se rompe «arreglando» la otra, y la que no falla
// cuando se rompe: la pantalla se queda vieja, sin error y sin una línea en ningún registro.
func TestUnAvisoSinSucursalEsDeTodasYNoDeNinguna(t *testing.T) {
	anterior := busEventos
	t.Cleanup(func() { busEventos = anterior })
	busEventos = NuevoDifusor()

	canal, cortar, _ := busEventos.SuscribirDe(idDeSucursal(t, "HOL").String())
	defer cortar()

	avisarCambioDelTablero(context.Background(), DeTodasLasSucursales)

	if _, hay := recibio(canal); !hay {
		t.Error("un aviso publicado sin sucursal no le llegó a Holguín.\n" +
			"  «No se sabe de qué sucursal es» tiene que leerse como «de todas». Al revés " +
			"es un aviso que no le llega a nadie, que es el fallo que no se ve.")
	}
}

// Y `DeTodasLasSucursales` ES el texto vacío. La constante tiene nombre para que pasarla sea
// un acto y no parezca un olvido, pero el valor es el que el bus lee como «no lo acota»: si
// alguien le pusiera cualquier otra cosa, todos los avisos globales se convertirían en avisos
// de una sucursal que no existe y no le llegarían a nadie.
//
// El valor va A MANO. Comparar la constante consigo misma no comprueba nada.
func TestDeTodasLasSucursalesEsElTextoVacio(t *testing.T) {
	if DeTodasLasSucursales != "" {
		t.Errorf("DeTodasLasSucursales vale %q y tiene que ser el texto vacío.\n"+
			"  Es lo que `repartir` lee como «este aviso no dice de qué sucursal es» para "+
			"mandárselo a las ocho. Con cualquier otro valor, el catálogo, los ajustes, la "+
			"lista de sucursales y el canal dejan de llegarle a todo el mundo.",
			DeTodasLasSucursales)
	}
}

// --------------------------------------------------------------------------- por el cable

// manejadorDeEventosDeLasOcho monta `/api/eventos` con la portería de las ocho sucursales.
func manejadorDeEventosDeLasOcho(t *testing.T, bus *Difusor) http.Handler {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoDePanel)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	s := NuevoServidor(cfg, reg, porteriaDeLasOcho(t),
		auth.NuevoVerificador([]byte(secretoDePanel)), nil)

	rt := httpx.NuevoRouter(httpx.ConRegistro(reg), httpx.SinCache)
	rt.ManejarFunc(http.MethodGet, "/api/eventos", func(w http.ResponseWriter, r *http.Request) {
		s.servirEventos(w, r, bus)
	})
	return rt.Handler()
}

// abrirElCanal abre una conexión de verdad con el token de esa persona y devuelve sus
// líneas. Espera al `listo`, que es lo que dice que ya está abonada: sin eso, avisar antes
// de que el abono exista haría pasar cualquier prueba de «no me llegó».
func abrirElCanal(t *testing.T, url, rol, sucursal string) <-chan string {
	t.Helper()
	r, err := http.NewRequest(http.MethodGet, url+"/api/eventos", nil)
	if err != nil {
		t.Fatal(err)
	}
	reclamos := map[string]any{"sub": "u-" + sucursal, "role": rol}
	if sucursal != "" {
		reclamos["branchId"] = sucursal // EL CÓDIGO, que es lo que firma Accesos
	}
	r.Header.Set("Authorization", "Bearer "+tokenDePanel(t, reclamos))
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = resp.Body.Close() })
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("el canal de %s/%s contestó %d", rol, sucursal, resp.StatusCode)
	}
	lineas := lineasDeEventos(resp.Body)
	// Se espera al `listo` Y A SU `data:`. El bloque son dos líneas, y quedarse en la
	// primera deja la segunda en la cola: las pruebas en negativo la leerían como «me llegó
	// un aviso que no era mío» y las positivas la leerían en vez del aviso. Las dos
	// fallarían por el motivo equivocado.
	esperarLinea(t, lineas, "event: listo", 2*time.Second)
	esperarLinea(t, lineas, "data:", 2*time.Second)
	return lineas
}

// nadaPorElCable vacía lo que salga durante el plazo y falla si sale UN SOLO aviso.
//
// ## POR QUÉ NO VALE LEER UNA LÍNEA Y YA — cazado mutando, 29/09/2026
//
// Así estaba escrito, y **salía verde con el corte por sucursal roto a propósito**. Un
// bloque SSE son TRES líneas —`event: …`, `data: …` y una VACÍA que lo cierra—, así que
// después de consumir el `listo` y su `data` lo primero que queda en la cola es la línea
// vacía. Un `select` que lee una sola línea se llevaba ésa, no casaba con ningún prefijo, y
// la prueba daba por bueno que no había llegado nada… con el aviso de la otra sucursal
// esperando detrás.
//
// Es justo el fallo de la casa: una prueba en negativo que no puede fallar. Pasaba la
// mutación «quitar el filtro de `repartir`» sin enterarse.
//
// Ahora se vacía TODO el plazo y se mira línea por línea.
func nadaPorElCable(t *testing.T, lineas <-chan string, plazo time.Duration, queSeria string) {
	t.Helper()
	limite := time.After(plazo)
	// EL LATIDO NO CUENTA, y desde el 29/09/2026 hay que decirlo: dejó de ser un comentario
	// SSE y ahora es `event: latido` con su `data: {}`. Sin esta salvedad, un latido que
	// cayera dentro del plazo se leería como «salió un aviso que no era mío» y esta prueba
	// daría un rojo que no es. Se mira la trama entera —el `data:` sólo se salta si venía
	// detrás de un `event: latido`—, que es distinto de saltarse todos los `data: {}`.
	latiendo := false
	for {
		select {
		case l, abierto := <-lineas:
			if !abierto {
				return
			}
			if strings.HasPrefix(l, "event: "+NombreDelLatido) {
				latiendo = true
				continue
			}
			if latiendo {
				// La línea del latido y la vacía que cierra su trama.
				if strings.HasPrefix(l, "data:") {
					continue
				}
				latiendo = false
			}
			if strings.HasPrefix(l, "event: cambio") || strings.HasPrefix(l, "data:") {
				t.Fatalf("por este canal salió %q.\n"+
					"  %s\n"+
					"  El corte lo tiene que hacer el SERVIDOR: no es que llegue y el "+
					"aparato lo tire, es que no llega.", l, queSeria)
			}
		case <-limite:
			return
		}
	}
}

// LA PRUEBA QUE MÁS IMPORTA, y va contra el canal de verdad.
//
// Un OPERADOR de Holguín tiene el canal abierto. Se mueve el tablero de Santiago. Por su
// cable no puede salir NADA: no es que llegue y lo descarte el aparato — es que no llega.
func TestAUnOperadorDeHolguinNoLeLlegaElAvisoDeSantiago(t *testing.T) {
	bus := NuevoDifusor()
	srv := httptest.NewServer(manejadorDeEventosDeLasOcho(t, bus))
	// `t.Cleanup` y NO `defer`: los `Cleanup` corren al revés de como se apuntan, así que
	// el cuerpo de la respuesta —que lo apunta `abrirElCanal`, después— se cierra ANTES que
	// el servidor. Cerrando el servidor con un `defer`, la prueba se queda colgada para
	// siempre: `httptest.Server.Close` espera a que terminen las peticiones en vuelo, y una
	// conexión de eventos no termina nunca por su cuenta. Es la trampa de la casa —una
	// prueba que se cuelga en vez de fallar— en su versión de Go.
	t.Cleanup(srv.Close)

	hol := abrirElCanal(t, srv.URL, "LOGISTICO", "HOL")
	bus.AvisarDe(CambioTablero, idDeSucursal(t, "STG").String(), nil)

	// El latido normal son veinte segundos, así que en medio segundo por este cable no
	// puede salir nada si el corte está bien hecho.
	nadaPorElCable(t, hol, 500*time.Millisecond,
		"Es el tablero de Santiago, y quien escucha es un LOGISTICO de Holguín. Saber que "+
			"«en Santiago pasó algo» ya es contar algo de Santiago, y además le cuesta "+
			"una bajada del tablero entero por la conexión de allá.")
}

// LA GEMELA EN POSITIVO, sin la cual la de arriba pasaría con el canal roto.
//
// Un corte que no deje pasar NADA es tan malo como no cortar, y además no se ve: la
// pantalla se queda vieja sin un error. Aquí se comprueba que lo suyo sí le llega, y con
// la sucursal dentro.
func TestAlMismoOperadorSiLeLlegaLoDeSuSucursal(t *testing.T) {
	bus := NuevoDifusor()
	srv := httptest.NewServer(manejadorDeEventosDeLasOcho(t, bus))
	// `t.Cleanup` y NO `defer`: los `Cleanup` corren al revés de como se apuntan, así que
	// el cuerpo de la respuesta —que lo apunta `abrirElCanal`, después— se cierra ANTES que
	// el servidor. Cerrando el servidor con un `defer`, la prueba se queda colgada para
	// siempre: `httptest.Server.Close` espera a que terminen las peticiones en vuelo, y una
	// conexión de eventos no termina nunca por su cuenta. Es la trampa de la casa —una
	// prueba que se cuelga en vez de fallar— en su versión de Go.
	t.Cleanup(srv.Close)

	hol := abrirElCanal(t, srv.URL, "LOGISTICO", "HOL")
	bus.AvisarDe(CambioTablero, idDeSucursal(t, "HOL").String(), nil)

	linea := esperarLinea(t, hol, "data:", 2*time.Second)
	var cuerpo map[string]any
	if err := json.Unmarshal([]byte(strings.TrimPrefix(linea, "data: ")), &cuerpo); err != nil {
		t.Fatalf("el cuerpo del aviso no es JSON: %v (%q)", err, linea)
	}
	if cuerpo["tipo"] != CambioTablero {
		t.Errorf("llegó el tipo %v y se esperaba %q", cuerpo["tipo"], CambioTablero)
	}
	if cuerpo["sucursal"] != idDeSucursal(t, "HOL").String() {
		t.Errorf("el aviso llegó con la sucursal %v y es el tablero de Holguín (%s)",
			cuerpo["sucursal"], idDeSucursal(t, "HOL"))
	}
}

// Y LO QUE NO ES DE NADIE LE LLEGA A ESE MISMO LOGISTICO, por el mismo cable.
func TestAlOperadorLeLleganLosAvisosQueNoSonDeNingunaSucursal(t *testing.T) {
	bus := NuevoDifusor()
	srv := httptest.NewServer(manejadorDeEventosDeLasOcho(t, bus))
	// `t.Cleanup` y NO `defer`: los `Cleanup` corren al revés de como se apuntan, así que
	// el cuerpo de la respuesta —que lo apunta `abrirElCanal`, después— se cierra ANTES que
	// el servidor. Cerrando el servidor con un `defer`, la prueba se queda colgada para
	// siempre: `httptest.Server.Close` espera a que terminen las peticiones en vuelo, y una
	// conexión de eventos no termina nunca por su cuenta. Es la trampa de la casa —una
	// prueba que se cuelga en vez de fallar— en su versión de Go.
	t.Cleanup(srv.Close)

	hol := abrirElCanal(t, srv.URL, "LOGISTICO", "HOL")
	bus.Avisar(CambioAjustes, nil)

	linea := esperarLinea(t, hol, "data:", 2*time.Second)
	var cuerpo map[string]any
	if err := json.Unmarshal([]byte(strings.TrimPrefix(linea, "data: ")), &cuerpo); err != nil {
		t.Fatalf("el cuerpo del aviso no es JSON: %v (%q)", err, linea)
	}
	if cuerpo["tipo"] != CambioAjustes {
		t.Errorf("llegó %v y se esperaba %q: la tasa y la moneda son de las ocho",
			cuerpo["tipo"], CambioAjustes)
	}
	if _, hay := cuerpo["sucursal"]; hay {
		t.Errorf("el aviso de ajustes llegó con sucursal (%v) y no es de ninguna.\n"+
			"  Un `sucursal` puesto en un aviso global es lo que haría que alguien lo "+
			"comparara con el suyo y lo tirara.", cuerpo["sucursal"])
	}
}

// `ADMINISTRADOR` ES DE UNA SOLA SUCURSAL, y ésa es la fuga clásica de la casa: una
// comprobación del tipo «¿contiene admin?» le daría las ocho. Aquí no se pregunta por el
// rol a mano —lo resuelve la portería— y esta prueba es la que lo sostiene.
func TestUnAdministradorNoVeElCanalDeOtraSucursal(t *testing.T) {
	bus := NuevoDifusor()
	srv := httptest.NewServer(manejadorDeEventosDeLasOcho(t, bus))
	// `t.Cleanup` y NO `defer`: los `Cleanup` corren al revés de como se apuntan, así que
	// el cuerpo de la respuesta —que lo apunta `abrirElCanal`, después— se cierra ANTES que
	// el servidor. Cerrando el servidor con un `defer`, la prueba se queda colgada para
	// siempre: `httptest.Server.Close` espera a que terminen las peticiones en vuelo, y una
	// conexión de eventos no termina nunca por su cuenta. Es la trampa de la casa —una
	// prueba que se cuelga en vez de fallar— en su versión de Go.
	t.Cleanup(srv.Close)

	cam := abrirElCanal(t, srv.URL, "ADMINISTRADOR", "CAM")
	bus.AvisarDe(CambioPedidos, idDeSucursal(t, "HAB").String(), nil)

	nadaPorElCable(t, cam, 500*time.Millisecond,
		"Es un cambio de pedidos de La Habana y quien escucha es un ADMINISTRADOR de "+
			"Camagüey, que pertenece a UNA sucursal. Si le llegan las ocho es que alguien "+
			"volvió a preguntar «¿contiene admin?», que es la fuga de siempre.")
}

// Y EL SUPER ADMIN SÍ, por el mismo cable y con el mismo aviso.
func TestUnSuperAdminRecibeElCanalDeCualquierSucursal(t *testing.T) {
	bus := NuevoDifusor()
	srv := httptest.NewServer(manejadorDeEventosDeLasOcho(t, bus))
	// `t.Cleanup` y NO `defer`: los `Cleanup` corren al revés de como se apuntan, así que
	// el cuerpo de la respuesta —que lo apunta `abrirElCanal`, después— se cierra ANTES que
	// el servidor. Cerrando el servidor con un `defer`, la prueba se queda colgada para
	// siempre: `httptest.Server.Close` espera a que terminen las peticiones en vuelo, y una
	// conexión de eventos no termina nunca por su cuenta. Es la trampa de la casa —una
	// prueba que se cuelga en vez de fallar— en su versión de Go.
	t.Cleanup(srv.Close)

	sa := abrirElCanal(t, srv.URL, "SUPER ADMIN", "")
	bus.AvisarDe(CambioPedidos, idDeSucursal(t, "HAB").String(), nil)

	linea := esperarLinea(t, sa, "data:", 2*time.Second)
	if !strings.Contains(linea, idDeSucursal(t, "HAB").String()) {
		t.Errorf("al SUPER ADMIN le llegó %q y tenía que llevar la sucursal de La Habana",
			linea)
	}
}

// UNA CUENTA SIN SUCURSAL Y SIN ROL DE LOS DOS ALTOS NO ABRE EL CANAL.
//
// Es la misma respuesta que le da el resto de la api (403 con el literal que dice qué
// falta y quién lo arregla), y aquí en texto plano por lo mismo que el 401: el
// `EventSource` del navegador no lee JSON.
func TestUnaCuentaSinSucursalNoAbreElCanal(t *testing.T) {
	srv := httptest.NewServer(manejadorDeEventosDeLasOcho(t, NuevoDifusor()))
	t.Cleanup(srv.Close)

	r, _ := http.NewRequest(http.MethodGet, srv.URL+"/api/eventos", nil)
	r.Header.Set("Authorization", "Bearer "+tokenDePanel(t, map[string]any{
		"sub": "u-suelto", "role": "LOGISTICO",
	}))
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("contestó %d y tenía que ser 403: sin sucursal no ve ninguna pantalla, "+
			"así que un canal abierto sólo le mandaría los uuid de las ocho", resp.StatusCode)
	}
	cuerpo, _ := io.ReadAll(resp.Body)
	if !strings.Contains(string(cuerpo), "no está dada de alta en ninguna sucursal") {
		t.Errorf("el cuerpo es %q y tenía que decir qué falta y quién lo arregla", cuerpo)
	}
}
