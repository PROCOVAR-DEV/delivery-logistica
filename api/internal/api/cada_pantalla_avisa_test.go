package api

// CADA PANTALLA SE ENTERA DE LO SUYO, no sólo el Tablero y las Rutas.
//
// El molde es `el_tablero_avisa_test.go` y se sigue tal cual: se cambia el gancho por uno
// que cuenta, se hace la petición por HTTP con el router montado de verdad, y se mira si
// avisó y CON QUÉ TIPO. El tipo importa tanto como el aviso: quien lo recibe vuelve a
// pedir lo suyo, así que mandar `pedidos` por un cambio de camión son ocho navegadores
// bajándose la lista de pedidos entera por nada, con la conexión de allá.
//
// Jose, 17/09/2026: «¿y por qué probamos con tableros solamente? Son todas, porque todos
// deben ser en tiempo real como el tablero cuando las cosas tienen conexión».
//
// Lo que había antes de esto, contado en el código:
//
//	tablero  — 7 sitios, completo
//	rutas    — 5 sitios, completo
//	pedidos  — UN solo sitio, el lote del espejo. Nada de lo que toca una persona.
//	catalogo — declarado y sin publicar
//	clientes — declarado y sin publicar
//	vehículos y almacenes — ni el tipo existía

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"regexp"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/store/sqlc"
)

// --------------------------------------------------------------------------- el contador

// contadorDeAvisos engancha TODOS los ganchos a la vez y anota qué tipo salió por cada
// uno. Se enganchan todos y no sólo el que interesa a propósito: así una prueba caza
// también el aviso DE MÁS —mandar `pedidos` al tocar un camión— que es lo que hace que la
// oficina entera se baje lo que no ha cambiado.
type contadorDeAvisos struct {
	tipos []string
	// sucursales: LA SUCURSAL DE CADA AVISO, en el mismo orden que `tipos`. Vacía = «de
	// todas», que es lo que el bus reparte a las ocho.
	//
	// Hace falta desde el 01/10/2026, cuando los ganchos acotados pasaron a recibir la
	// sucursal de la FILA que se escribe: sin anotarla, un aviso que saliera PELADO —el fallo
	// medido ese día— se contaba como un aviso correcto y la prueba quedaba verde.
	sucursales []string
}

// sucursalDe: con qué sucursal salió el aviso de ese tipo. El segundo valor es false si no
// salió ninguno, que no es lo mismo que haber salido sin sucursal.
func (c *contadorDeAvisos) sucursalDe(tipo string) (string, bool) {
	for i, t := range c.tipos {
		if t == tipo {
			return c.sucursales[i], true
		}
	}
	return "", false
}

func (c *contadorDeAvisos) tiene(tipo string) int {
	n := 0
	for _, t := range c.tipos {
		if t == tipo {
			n++
		}
	}
	return n
}

func (c *contadorDeAvisos) total() int { return len(c.tipos) }

// contarAvisos sustituye los ganchos y los devuelve a su sitio al acabar.
func contarAvisos(t *testing.T) *contadorDeAvisos {
	t.Helper()
	c := &contadorDeAvisos{}
	// Los ACOTADOS: anotan el tipo Y la sucursal con la que se publicó.
	anotaDe := func(tipo string) func(context.Context, string) {
		return func(_ context.Context, sucursal string) {
			c.tipos = append(c.tipos, tipo)
			c.sucursales = append(c.sucursales, sucursal)
		}
	}
	// Los GLOBALES: no reciben sucursal porque no pueden llevarla, así que se anota vacía.
	anota := func(tipo string) func(context.Context) {
		return func(context.Context) {
			c.tipos = append(c.tipos, tipo)
			c.sucursales = append(c.sucursales, DeTodasLasSucursales)
		}
	}

	antRutas, antTablero := avisarCambioDeRutas, avisarCambioDelTablero
	antPedidos, antCatalogo := avisarCambioDePedidos, avisarCambioDelCatalogo
	antVeh, antAlm := avisarCambioDeVehiculos, avisarCambioDeAlmacenes
	antSuc, antAj := avisarCambioDeSucursales, avisarCambioDeAjustes
	// LOS CUATRO QUE FALTABAN — 29/09/2026. Sin ellos enganchados, `exige` medía sobre un
	// contador ciego: una puerta que avisara de tipos de vehículo, de clientes, del canal o
	// de la tasa salía como «no avisó de nada», y peor, el `total()` que caza el aviso DE
	// MÁS no los contaba. Es el mismo agujero que tenía el propio código.
	antTipos, antClientes := avisarCambioDeTiposDeVehiculo, avisarCambioDeClientes
	antCanal, antTasa := avisarCambioEnElCanal, avisarTasaDeSucursal
	t.Cleanup(func() {
		avisarCambioDeRutas, avisarCambioDelTablero = antRutas, antTablero
		avisarCambioDePedidos, avisarCambioDelCatalogo = antPedidos, antCatalogo
		avisarCambioDeVehiculos, avisarCambioDeAlmacenes = antVeh, antAlm
		avisarCambioDeSucursales, avisarCambioDeAjustes = antSuc, antAj
		avisarCambioDeTiposDeVehiculo, avisarCambioDeClientes = antTipos, antClientes
		avisarCambioEnElCanal, avisarTasaDeSucursal = antCanal, antTasa
	})

	avisarCambioDeRutas = anotaDe(CambioRutas)
	avisarCambioDelTablero = anotaDe(CambioTablero)
	avisarCambioDePedidos = anotaDe(CambioPedidos)
	avisarCambioDelCatalogo = anota(CambioCatalogo)
	avisarCambioDeVehiculos = anotaDe(CambioVehiculos)
	avisarCambioDeAlmacenes = anotaDe(CambioAlmacenes)
	avisarCambioDeSucursales = anota(CambioSucursales)
	avisarCambioDeAjustes = anota(CambioAjustes)
	// Los tipos de vehículo publican el MISMO texto que la flota (`vehiculos`) porque la
	// pantalla es la misma; lo que cambia es a quién le llega, y eso lo vigila
	// `TestLaTablaDeQueAvisoLlevaSucursal`, no esto.
	avisarCambioDeTiposDeVehiculo = anota(CambioVehiculos)
	avisarCambioDeClientes = anotaDe(CambioClientes)
	avisarCambioEnElCanal = anota(CambioCanal)
	avisarTasaDeSucursal = anotaDe(CambioAjustes)
	return c
}

// exige comprueba lo único que importa: que salió SU tipo, y que no salió ningún otro.
func (c *contadorDeAvisos) exige(t *testing.T, puerta string, tipos ...string) {
	t.Helper()
	for _, tipo := range tipos {
		if c.tiene(tipo) == 0 {
			t.Errorf("%s NO avisó de «%s»: lo que hace esa persona no aparece en la "+
				"pantalla de al lado hasta que pasen dos minutos o alguien refresque a "+
				"mano. Salieron: %v", puerta, tipo, c.tipos)
		}
	}
	if c.total() != len(tipos) {
		t.Errorf("%s avisó de %v y se esperaba exactamente %v: un aviso de más manda a "+
			"todas las pantallas abiertas a bajarse una lista que no ha cambiado",
			puerta, c.tipos, tipos)
	}
}

// exigeSilencio es la otra mitad: lo que NO se escribió no se dice.
func (c *contadorDeAvisos) exigeSilencio(t *testing.T, puerta string) {
	t.Helper()
	if c.total() != 0 {
		t.Errorf("%s avisó (%v) de algo que NO se escribió: todas las pantallas abiertas "+
			"vuelven a pedir su lista para encontrarla igual, y con diez repartidores en "+
			"la conexión de allá eso no es gratis", puerta, c.tipos)
	}
}

// --------------------------------------------------------------------------- el doble

var (
	avSucStg = uuid.MustParse("11111111-1111-1111-1111-111111111111")
	avSucHol = uuid.MustParse("22222222-2222-2222-2222-222222222222")

	avVehStg  = uuid.MustParse("a0000000-0000-0000-0000-000000000001")
	avTipoCam = uuid.MustParse("b0000000-0000-0000-0000-000000000001")
)

// errAvFalloDeBase es el fallo que se le mete al doble para probar la otra mitad de la
// regla: si la escritura no salió, no se avisa. No hay ninguna otra forma de que
// `PUT /api/settings` falle —no valida nada—, así que aquí se rompe la base a propósito.
var errAvFalloDeBase = errors.New("la base no contestó")

// dobleAvisos: el Querier de mentira para la flota, los tipos, las sucursales y los
// ajustes. Embebe `sqlc.Querier` sin implementarlo, como los demás dobles de este
// paquete: cualquier consulta que una prueba no haya previsto revienta con un puntero nil
// en vez de devolver un cero que parezca bueno.
type dobleAvisos struct {
	sqlc.Querier

	// falloAlEscribir se devuelve en la escritura de los ajustes. Ver `errAvFalloDeBase`.
	falloAlEscribir error
	// vehiculoEnUso hace que el camión estuviera `in_use` antes del PATCH, que es lo que
	// dispara el cierre de su ruta abierta.
	vehiculoEnUso bool
	// rutasCerradas es lo que devuelve `CompletarRutasDeVehiculo`.
	rutasCerradas int64
	// cierresPedidos cuenta las veces que se LLAMÓ a `CompletarRutasDeVehiculo`.
	//
	// Hace falta porque «no se cerró ninguna ruta» y «no se intentó cerrarla» se ven
	// iguales desde fuera en cuanto el doble devuelve 0, y son dos cosas distintas:
	// mandar un camión al taller no puede ni intentarlo (`estado_del_camion_test.go`).
	cierresPedidos int
}

func (d *dobleAvisos) ResolverSucursal(_ context.Context, id uuid.UUID) (sqlc.ResolverSucursalRow, error) {
	switch id {
	case avSucStg:
		c := "STG"
		return sqlc.ResolverSucursalRow{ID: avSucStg, Name: "Santiago", ExternalID: &c}, nil
	case avSucHol:
		c := "HOL"
		return sqlc.ResolverSucursalRow{ID: avSucHol, Name: "Holguín", ExternalID: &c}, nil
	}
	return sqlc.ResolverSucursalRow{}, pgx.ErrNoRows
}

// --- flota

func (d *dobleAvisos) BuscarTipoDeVehiculoPorNombre(_ context.Context, nombre string) (sqlc.BuscarTipoDeVehiculoPorNombreRow, error) {
	if nombre == "truck" {
		return sqlc.BuscarTipoDeVehiculoPorNombreRow{ID: avTipoCam, Nombre: "truck"}, nil
	}
	return sqlc.BuscarTipoDeVehiculoPorNombreRow{}, pgx.ErrNoRows
}

func (d *dobleAvisos) DesmarcarReferenciaDeDomicilio(context.Context, sqlc.DesmarcarReferenciaDeDomicilioParams) (int64, error) {
	return 0, nil
}

func (d *dobleAvisos) CrearVehiculo(_ context.Context, arg sqlc.CrearVehiculoParams) (sqlc.Vehicle, error) {
	return sqlc.Vehicle{
		ID: uuid.New(), Name: arg.Name, VehicleTypeID: arg.VehicleTypeID,
		Capacity: arg.Capacity, Status: arg.Status, BranchID: arg.BranchID,
	}, nil
}

func (d *dobleAvisos) ObtenerVehiculo(_ context.Context, arg sqlc.ObtenerVehiculoParams) (sqlc.ObtenerVehiculoRow, error) {
	if arg.ID != avVehStg {
		return sqlc.ObtenerVehiculoRow{}, pgx.ErrNoRows
	}
	estado := sqlc.VehicleStatusAvailable
	if d.vehiculoEnUso {
		estado = sqlc.VehicleStatusInUse
	}
	return sqlc.ObtenerVehiculoRow{
		ID: avVehStg, Name: "Camión de Santiago", TipoNombre: "truck",
		Status: estado, BranchID: avPg(avSucStg),
	}, nil
}

func (d *dobleAvisos) ActualizarVehiculo(_ context.Context, arg sqlc.ActualizarVehiculoParams) (sqlc.Vehicle, error) {
	if arg.ID != avVehStg {
		return sqlc.Vehicle{}, pgx.ErrNoRows
	}
	v := sqlc.Vehicle{ID: avVehStg, Name: "Camión de Santiago", VehicleTypeID: avTipoCam,
		Status: sqlc.VehicleStatusAvailable, BranchID: avPg(avSucStg)}
	if arg.Status != nil {
		v.Status = *arg.Status
	}
	return v, nil
}

func (d *dobleAvisos) CompletarRutasDeVehiculo(context.Context, sqlc.CompletarRutasDeVehiculoParams) (int64, error) {
	d.cierresPedidos++
	return d.rutasCerradas, nil
}

func (d *dobleAvisos) DesvincularVehiculoDeRutas(context.Context, sqlc.DesvincularVehiculoDeRutasParams) (int64, error) {
	return 0, nil
}

func (d *dobleAvisos) DesvincularVehiculoDePedidos(context.Context, sqlc.DesvincularVehiculoDePedidosParams) (int64, error) {
	return 0, nil
}

func (d *dobleAvisos) BorrarAsignacionesDeVehiculo(context.Context, uuid.UUID) (int64, error) {
	return 0, nil
}

// BorrarVehiculo devuelve la SUCURSAL del camión borrado, como el `RETURNING branch_id` de
// verdad: es de donde salen los tres avisos de la baja. `pgx.ErrNoRows` es el 404.
func (d *dobleAvisos) BorrarVehiculo(_ context.Context, arg sqlc.BorrarVehiculoParams) (pgtype.UUID, error) {
	if arg.ID != avVehStg {
		return pgtype.UUID{}, pgx.ErrNoRows
	}
	return avPg(avSucStg), nil
}

// --- tipos de vehículo

func (d *dobleAvisos) CrearTipoDeVehiculo(_ context.Context, arg sqlc.CrearTipoDeVehiculoParams) (sqlc.VehicleType, error) {
	return sqlc.VehicleType{ID: uuid.New(), Nombre: arg.Nombre, CostoKmUsd: arg.CostoKmUsd, Activo: arg.Activo}, nil
}

func (d *dobleAvisos) ActualizarTipoDeVehiculo(_ context.Context, arg sqlc.ActualizarTipoDeVehiculoParams) (sqlc.VehicleType, error) {
	if arg.ID != avTipoCam {
		return sqlc.VehicleType{}, pgx.ErrNoRows
	}
	return sqlc.VehicleType{ID: avTipoCam, Nombre: "truck", Activo: true}, nil
}

// BorrarTipoDeVehiculoSinUso devuelve 0 SIEMPRE: el tipo de las pruebas lo usa un camión,
// así que se cae por la rama del retiro, que es la que más se da de verdad.
func (d *dobleAvisos) BorrarTipoDeVehiculoSinUso(context.Context, uuid.UUID) (int64, error) {
	return 0, nil
}

func (d *dobleAvisos) RetirarTipoDeVehiculo(_ context.Context, id uuid.UUID) (int64, error) {
	if id != avTipoCam {
		return 0, nil
	}
	return 1, nil
}

// --- sucursales

func (d *dobleAvisos) CrearSucursal(_ context.Context, arg sqlc.CrearSucursalParams) (sqlc.Branch, error) {
	return sqlc.Branch{ID: uuid.New(), Name: arg.Name, Lat: arg.Lat, Lng: arg.Lng, AreaKm2: arg.AreaKm2}, nil
}

func (d *dobleAvisos) CrearOrigen(_ context.Context, arg sqlc.CrearOrigenParams) (sqlc.SavedOrigin, error) {
	return sqlc.SavedOrigin{ID: uuid.New(), Name: arg.Name, Address: arg.Address,
		Lat: arg.Lat, Lng: arg.Lng, BranchID: arg.BranchID}, nil
}

func (d *dobleAvisos) ActualizarSucursal(_ context.Context, arg sqlc.ActualizarSucursalParams) (sqlc.Branch, error) {
	if arg.ID != avSucStg {
		return sqlc.Branch{}, pgx.ErrNoRows
	}
	return sqlc.Branch{ID: avSucStg, Name: "Santiago", Lat: 20, Lng: -75.8, AreaKm2: 1,
		OriginConfigured: true}, nil
}

func (d *dobleAvisos) ContarOrigenesDeSucursal(context.Context, pgtype.UUID) (int64, error) {
	return 1, nil
}

func (d *dobleAvisos) BorrarSucursal(_ context.Context, arg sqlc.BorrarSucursalParams) (int64, error) {
	if arg.ID != avSucStg {
		return 0, nil
	}
	return 1, nil
}

// --- ajustes

func (d *dobleAvisos) ObtenerAjustes(context.Context) (sqlc.Setting, error) {
	return sqlc.Setting{Currency: "USD", CupRate: 320}, nil
}

func (d *dobleAvisos) ActualizarAjustes(_ context.Context, arg sqlc.ActualizarAjustesParams) (sqlc.Setting, error) {
	if d.falloAlEscribir != nil {
		return sqlc.Setting{}, d.falloAlEscribir
	}
	s := sqlc.Setting{Currency: "USD", CupRate: 320}
	if arg.Currency != nil {
		s.Currency = *arg.Currency
	}
	if arg.CupRate != nil {
		s.CupRate = *arg.CupRate
	}
	return s, nil
}

func (d *dobleAvisos) GuardarMoneda(_ context.Context, arg sqlc.GuardarMonedaParams) (sqlc.Currency, error) {
	return sqlc.Currency{Code: arg.Code, Rate: arg.Rate, Activa: arg.Activa}, nil
}

func (d *dobleAvisos) ListarMonedas(context.Context, *bool) ([]sqlc.Currency, error) {
	return []sqlc.Currency{{Code: "CUP", Rate: 320, Activa: true}}, nil
}

type fuenteDeAvisos struct{ q *dobleAvisos }

func (f fuenteDeAvisos) Consultas() sqlc.Querier { return f.q }
func (f fuenteDeAvisos) EnTx(_ context.Context, fn func(sqlc.Querier) error) error {
	return fn(f.q)
}

// --------------------------------------------------------------------------- montaje

func avPg(id uuid.UUID) pgtype.UUID { return pgtype.UUID{Bytes: [16]byte(id), Valid: true} }

// montarAvisos levanta el router ENTERO, que es como corre de verdad. Las rutas de la
// flota, las sucursales y los ajustes se registran dentro de `Rutas()` y no en un
// `rutasX`, así que no hay forma de montar sólo ésas sin copiar el montaje — y una prueba
// que copia el montaje del código que prueba no comprueba el montaje.
func montarAvisos(t *testing.T, d *dobleAvisos) http.Handler {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoDeDatos)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	return NuevoServidor(cfg, reg,
		alcance.NuevaPorteria(fuenteDeAvisos{q: d}, reg),
		auth.NuevoVerificador([]byte(secretoDeDatos)),
		func(context.Context) error { return nil },
	).Rutas()
}

// pedirAv: la petición, con el token puesto. Devuelve el grabador para poder mirar el
// código: una prueba que no mira el código puede estar comprobando el silencio de un 404
// que ella misma provocó sin querer.
func pedirAv(t *testing.T, h http.Handler, metodo, ruta, jwt, cuerpo string) *httptest.ResponseRecorder {
	t.Helper()
	var lector io.Reader
	if cuerpo != "" {
		lector = strings.NewReader(cuerpo)
	}
	r := httptest.NewRequest(metodo, ruta, lector)
	if jwt != "" {
		r.Header.Set("Authorization", "Bearer "+jwt)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func avOperadorStg(t *testing.T) string {
	t.Helper()
	return tokenDeDatos(t, map[string]any{"sub": "p-stg", "email": "stg@procovar.cu",
		"role": "OPERADOR", "branchId": avSucStg.String()})
}

// avAdmin: un SUPER ADMIN, que es quien pasa por `ExigirAdmin` y además no tiene sucursal,
// que es lo que necesitan las rutas globales (tipos de vehículo, sucursales, ajustes).
func avAdmin(t *testing.T) string {
	t.Helper()
	return tokenDeDatos(t, map[string]any{"sub": "p-super", "email": "super@procovar.cu",
		"role": "SUPER ADMIN"})
}

func avCodigo(t *testing.T, w *httptest.ResponseRecorder, esperado int) {
	t.Helper()
	if w.Code != esperado {
		t.Fatalf("código %d, se esperaba %d: %s", w.Code, esperado, w.Body.String())
	}
}

// --------------------------------------------------------------------------- vehículos

// LA PANTALLA DE VEHÍCULOS es de las que más falta le hacía: no vive de la base local,
// pide `GET /api/vehicles` a la red. El ciclo de sincronización no la repinta, así que sin
// este aviso lo único que la actualizaba era salir de la pantalla y volver a entrar.
func TestCadaEscrituraDeLaFlotaAvisa(t *testing.T) {
	casos := []struct {
		nombre string
		hacer  func(t *testing.T, h http.Handler)
		tipos  []string
	}{
		{"dar de alta un camión", func(t *testing.T, h http.Handler) {
			w := pedirAv(t, h, http.MethodPost, "/api/vehicles", avOperadorStg(t),
				`{"name":"Camión nuevo","type":"truck"}`)
			avCodigo(t, w, http.StatusCreated)
		}, []string{CambioVehiculos}},

		{"editarlo", func(t *testing.T, h http.Handler) {
			w := pedirAv(t, h, http.MethodPatch, "/api/vehicles/"+avVehStg.String(),
				avOperadorStg(t), `{"name":"Camión renombrado"}`)
			avCodigo(t, w, http.StatusOK)
		}, []string{CambioVehiculos}},

		{"darlo de baja", func(t *testing.T, h http.Handler) {
			w := pedirAv(t, h, http.MethodDelete, "/api/vehicles/"+avVehStg.String(),
				avOperadorStg(t), "")
			avCodigo(t, w, http.StatusOK)
			// Este borrado desvincula el camión de sus rutas y de sus pedidos antes de
			// quitarlo: las tres listas cambiaron y las tres se dicen.
		}, []string{CambioVehiculos, CambioRutas, CambioPedidos}},

		{"crear un tipo de vehículo", func(t *testing.T, h http.Handler) {
			w := pedirAv(t, h, http.MethodPost, "/api/vehicle-types", avAdmin(t),
				`{"nombre":"rastra"}`)
			avCodigo(t, w, http.StatusCreated)
		}, []string{CambioVehiculos}},

		{"editar un tipo de vehículo", func(t *testing.T, h http.Handler) {
			w := pedirAv(t, h, http.MethodPatch, "/api/vehicle-types/"+avTipoCam.String(),
				avAdmin(t), `{"costoKmUsd":0.9}`)
			avCodigo(t, w, http.StatusOK)
		}, []string{CambioVehiculos}},

		{"retirar un tipo de vehículo", func(t *testing.T, h http.Handler) {
			// Lo usa un camión, así que se RETIRA en vez de borrarse. Sale del
			// desplegable igual, así que la pantalla cambia igual.
			w := pedirAv(t, h, http.MethodDelete, "/api/vehicle-types/"+avTipoCam.String(),
				avAdmin(t), "")
			avCodigo(t, w, http.StatusOK)
		}, []string{CambioVehiculos}},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			h := montarAvisos(t, &dobleAvisos{})
			avisos := contarAvisos(t)
			c.hacer(t, h)
			avisos.exige(t, c.nombre, c.tipos...)
		})
	}
}

// Liberar un camión CIERRA su ruta abierta, y esa ruta la está mirando otro en la pantalla
// de Rutas. Se avisa de las dos cosas porque cambiaron las dos.
func TestLiberarUnCamionAvisaTambienDeSuRuta(t *testing.T) {
	h := montarAvisos(t, &dobleAvisos{vehiculoEnUso: true, rutasCerradas: 1})
	avisos := contarAvisos(t)

	w := pedirAv(t, h, http.MethodPatch, "/api/vehicles/"+avVehStg.String(),
		avOperadorStg(t), `{"status":"available"}`)
	avCodigo(t, w, http.StatusOK)

	avisos.exige(t, "liberar un camión con ruta abierta", CambioVehiculos, CambioRutas)
}

// Y si no se cerró ninguna ruta, no se dice que cambiaron las rutas. Un aviso de rutas por
// cada PATCH de un camión es la pantalla de Rutas recargándose sola todo el día.
func TestEditarUnCamionSinCerrarRutasNoAvisaDeRutas(t *testing.T) {
	h := montarAvisos(t, &dobleAvisos{})
	avisos := contarAvisos(t)

	w := pedirAv(t, h, http.MethodPatch, "/api/vehicles/"+avVehStg.String(),
		avOperadorStg(t), `{"name":"Otro nombre"}`)
	avCodigo(t, w, http.StatusOK)

	avisos.exige(t, "editar un camión", CambioVehiculos)
}

// --------------------------------------------------------------------------- sucursales

func TestCadaEscrituraDeSucursalesAvisa(t *testing.T) {
	casos := []struct {
		nombre string
		hacer  func(t *testing.T, h http.Handler)
	}{
		{"crear una sucursal", func(t *testing.T, h http.Handler) {
			w := pedirAv(t, h, http.MethodPost, "/api/branches", avAdmin(t),
				`{"name":"Bayamo","lat":20.38,"lng":-76.64}`)
			avCodigo(t, w, http.StatusCreated)
		}},
		{"editarla", func(t *testing.T, h http.Handler) {
			w := pedirAv(t, h, http.MethodPatch, "/api/branches/"+avSucStg.String(),
				avAdmin(t), `{"name":"Santiago de Cuba"}`)
			avCodigo(t, w, http.StatusOK)
		}},
		{"borrarla", func(t *testing.T, h http.Handler) {
			w := pedirAv(t, h, http.MethodDelete, "/api/branches/"+avSucStg.String(),
				avAdmin(t), "")
			avCodigo(t, w, http.StatusOK)
		}},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			h := montarAvisos(t, &dobleAvisos{})
			avisos := contarAvisos(t)
			c.hacer(t, h)
			avisos.exige(t, c.nombre, CambioSucursales)
		})
	}
}

// --------------------------------------------------------------------------- ajustes

// La MONEDA y su TASA: con ellas se convierte todo importe que se pinta. Una tasa vieja en
// la pantalla de al lado no se ve rota, se ve como un número creíble y equivocado.
func TestGuardarLosAjustesAvisa(t *testing.T) {
	h := montarAvisos(t, &dobleAvisos{})
	avisos := contarAvisos(t)

	w := pedirAv(t, h, http.MethodPut, "/api/settings", avAdmin(t),
		`{"currency":"CUP","cupRate":340}`)
	avCodigo(t, w, http.StatusOK)

	avisos.exige(t, "guardar los ajustes", CambioAjustes)
}

// --------------------------------------------------------------------------- almacenes

// LA PANTALLA DE ALMACENES es el otro caso grave: pide `GET /api/almacenes` a la red, y
// los almacenes NI SIQUIERA VIAJAN en `GET /api/sync/cambios` —salen en `faltan`—. Y el
// domicilio se cobra por la distancia DESDE el almacén: dos personas mirando puntos
// distintos cobran precios distintos por la misma entrega.
func TestGuardarLosAlmacenesAvisa(t *testing.T) {
	conAccesos(t, almacenesDePrueba())
	h := montarDeDatos(t, datosDePrueba())
	avisos := contarAvisos(t)

	w := pedirDeDatos(t, h, http.MethodPut, "/api/almacenes", operadorDeSantiago(t),
		`{"codigo":"STG","almacenes":[{"nombre":"Central","latitud":20.0,"longitud":-75.8}]}`, nil)
	avCodigo(t, w, http.StatusOK)

	avisos.exige(t, "guardar los almacenes", CambioAlmacenes)

}

// Y SALE CON LA SUCURSAL DEL CÓDIGO QUE SE GUARDÓ, no con la del alcance de quien llamó.
//
// LO HACE UN SUPER ADMIN, y eso es la prueba, no un detalle: con un operador de Santiago el
// alcance YA es Santiago, así que un aviso que lo saque del alcance sale bien y la mutación no
// se ve. Comprobado el 01/10/2026: sustituido `deLaFila(...)` por `sucursalDelAlcance(...)`,
// `TestGuardarLosAlmacenesAvisa` seguía verde. Con el SUPER ADMIN el alcance es «todas» y el
// aviso sale pelado, que es el fallo de ese día.
func TestGuardarLosAlmacenesAvisaSoloASuSucursal(t *testing.T) {
	// El uuid va A MANO: es el que el doble de datos usa para Santiago. Compararlo con
	// `datSucStg` sería comparar el código consigo mismo.
	const santiagoAMano = "11111111-1111-1111-1111-111111111111"
	if datSucStg.String() != santiagoAMano {
		t.Fatalf("el doble de datos ya no usa %s para Santiago: %s", santiagoAMano, datSucStg)
	}

	conAccesos(t, almacenesDePrueba())
	h := montarDeDatos(t, datosDePrueba())
	avisos := contarAvisos(t)

	w := pedirDeDatos(t, h, http.MethodPut, "/api/almacenes", superAdminDeDatos(t),
		`{"codigo":"STG","almacenes":[{"nombre":"Central","latitud":20.0,"longitud":-75.8}]}`, nil)
	avCodigo(t, w, http.StatusOK)

	suc, hubo := avisos.sucursalDe(CambioAlmacenes)
	if !hubo {
		t.Fatalf("guardar los almacenes no avisó. Salieron: %v", avisos.tipos)
	}
	if suc != santiagoAMano {
		t.Errorf("el aviso de almacenes salió con la sucursal %q y tenía que ser %s, la del "+
			"código `STG` que vino en el cuerpo y que ya se comprobó contra las sucursales "+
			"visibles.\n"+
			"  Sacarlo del alcance manda a las OCHO a pedir `GET /api/almacenes` —que no vive "+
			"de la base local— por un punto que sólo cambió en Santiago. Y el domicilio se "+
			"cobra por la distancia DESDE el almacén.", suc, santiagoAMano)
	}
}

// Y si Accesos NO aceptó el cambio, no se avisa: no se guardó nada.
func TestSiAccesosRechazaLosAlmacenesNoSeAvisa(t *testing.T) {
	conAccesos(t, &accesosFalso{fallo: errAccesosCaido})
	h := montarDeDatos(t, datosDePrueba())
	avisos := contarAvisos(t)

	w := pedirDeDatos(t, h, http.MethodPut, "/api/almacenes", operadorDeSantiago(t),
		`{"codigo":"STG","almacenes":[]}`, nil)
	avCodigo(t, w, http.StatusBadGateway)

	avisos.exigeSilencio(t, "guardar unos almacenes que Accesos rechazó")
}

// --------------------------------------------------------------------------- catálogo

// `CambioCatalogo` estaba declarado desde el principio y NO LO PUBLICABA NADIE, con un
// comentario en `eventos.go` que lo justificaba diciendo que el catálogo cambia «cuando el
// espejo importa, que ya avisa por `CambioPedidos`». Nunca fue verdad: el catálogo se
// corrige a mano desde aquí, y eso no escribe un solo pedido.
func TestCorregirElCatalogoAvisa(t *testing.T) {
	t.Run("editar un producto", func(t *testing.T) {
		h := montarDeDatos(t, datosDePrueba())
		avisos := contarAvisos(t)
		w := pedirDeDatos(t, h, http.MethodPatch, "/api/products/"+datProdStg.String(),
			superAdminDeDatos(t), `{"weight":2.5}`, nil)
		avCodigo(t, w, http.StatusOK)
		avisos.exige(t, "editar un producto", CambioCatalogo)
	})

	t.Run("borrar un producto", func(t *testing.T) {
		h := montarDeDatos(t, datosDePrueba())
		avisos := contarAvisos(t)
		w := pedirDeDatos(t, h, http.MethodDelete, "/api/products/"+datProdStg.String(),
			superAdminDeDatos(t), "", nil)
		avCodigo(t, w, http.StatusOK)
		avisos.exige(t, "borrar un producto", CambioCatalogo)
	})
}

// --------------------------------------------------------------------------- pedidos

// Hasta hoy el ÚNICO `CambioPedidos` del servicio salía del lote del espejo. O sea: los
// pedidos que entran solos avisaban, y los que toca una persona no. Justo al revés de lo
// que hace falta, porque lo que toca una persona es lo que otra está mirando.
func TestCadaEscrituraDePedidosAvisa(t *testing.T) {
	t.Run("editar un pedido", func(t *testing.T) {
		h := servidorDePedidos(t, datosDePedidos())
		avisos := contarAvisos(t)
		w := pedirPedidos(t, h, http.MethodPatch, "/api/orders/"+pedidosStgA.String(),
			tokenDeSantiagoPedidos(t), `{"customerName":"Bar del puerto"}`, nil)
		avCodigo(t, w, http.StatusOK)
		avisos.exige(t, "editar un pedido", CambioPedidos)
	})

	t.Run("borrar un pedido", func(t *testing.T) {
		h := servidorDePedidos(t, datosDePedidos())
		avisos := contarAvisos(t)
		w := pedirPedidos(t, h, http.MethodDelete, "/api/orders/"+pedidosStgA.String(),
			tokenDeSantiagoPedidos(t), "", nil)
		avCodigo(t, w, http.StatusOK)
		avisos.exige(t, "borrar un pedido", CambioPedidos)
	})
}

// --------------------------------------------------------------------------- lo que NO avisa

// UNA ESCRITURA QUE EL SERVIDOR RECHAZA NO AVISA, puerta por puerta.
//
// Avisar de lo que no pasó manda a todas las pantallas abiertas a volver a pedir su lista
// para encontrarla igual. Con diez repartidores y la conexión de allá, eso no es gratis.
func TestUnaEscrituraRECHAZADANoAvisaEnNingunaPuerta(t *testing.T) {
	desconocido := uuid.MustParse("dddddddd-dddd-dddd-dddd-dddddddddddd")

	t.Run("un camión con un tipo que no existe", func(t *testing.T) {
		h := montarAvisos(t, &dobleAvisos{})
		avisos := contarAvisos(t)
		w := pedirAv(t, h, http.MethodPost, "/api/vehicles", avOperadorStg(t),
			`{"name":"Camión","type":"nave espacial"}`)
		avCodigo(t, w, http.StatusBadRequest)
		avisos.exigeSilencio(t, "dar de alta un camión con un tipo que no existe")
	})

	t.Run("editar un camión que no está", func(t *testing.T) {
		h := montarAvisos(t, &dobleAvisos{})
		avisos := contarAvisos(t)
		w := pedirAv(t, h, http.MethodPatch, "/api/vehicles/"+desconocido.String(),
			avOperadorStg(t), `{"name":"x"}`)
		avCodigo(t, w, http.StatusNotFound)
		avisos.exigeSilencio(t, "editar un camión que no está")
	})

	t.Run("borrar un camión que no está", func(t *testing.T) {
		h := montarAvisos(t, &dobleAvisos{})
		avisos := contarAvisos(t)
		w := pedirAv(t, h, http.MethodDelete, "/api/vehicles/"+desconocido.String(),
			avOperadorStg(t), "")
		avCodigo(t, w, http.StatusNotFound)
		avisos.exigeSilencio(t, "borrar un camión que no está")
	})

	t.Run("un tipo de vehículo sin nombre", func(t *testing.T) {
		h := montarAvisos(t, &dobleAvisos{})
		avisos := contarAvisos(t)
		w := pedirAv(t, h, http.MethodPost, "/api/vehicle-types", avAdmin(t), `{"nombre":"  "}`)
		avCodigo(t, w, http.StatusBadRequest)
		avisos.exigeSilencio(t, "crear un tipo de vehículo sin nombre")
	})

	t.Run("editar un tipo que no está", func(t *testing.T) {
		h := montarAvisos(t, &dobleAvisos{})
		avisos := contarAvisos(t)
		w := pedirAv(t, h, http.MethodPatch, "/api/vehicle-types/"+desconocido.String(),
			avAdmin(t), `{"nombre":"x"}`)
		avCodigo(t, w, http.StatusNotFound)
		avisos.exigeSilencio(t, "editar un tipo de vehículo que no está")
	})

	t.Run("retirar un tipo que no está", func(t *testing.T) {
		h := montarAvisos(t, &dobleAvisos{})
		avisos := contarAvisos(t)
		w := pedirAv(t, h, http.MethodDelete, "/api/vehicle-types/"+desconocido.String(),
			avAdmin(t), "")
		avCodigo(t, w, http.StatusNotFound)
		avisos.exigeSilencio(t, "retirar un tipo de vehículo que no está")
	})

	t.Run("una sucursal sin coordenadas", func(t *testing.T) {
		h := montarAvisos(t, &dobleAvisos{})
		avisos := contarAvisos(t)
		w := pedirAv(t, h, http.MethodPost, "/api/branches", avAdmin(t), `{"name":"Bayamo"}`)
		avCodigo(t, w, http.StatusBadRequest)
		avisos.exigeSilencio(t, "crear una sucursal sin coordenadas")
	})

	t.Run("editar una sucursal que no está", func(t *testing.T) {
		h := montarAvisos(t, &dobleAvisos{})
		avisos := contarAvisos(t)
		w := pedirAv(t, h, http.MethodPatch, "/api/branches/"+desconocido.String(),
			avAdmin(t), `{"name":"x"}`)
		avCodigo(t, w, http.StatusNotFound)
		avisos.exigeSilencio(t, "editar una sucursal que no está")
	})

	t.Run("borrar una sucursal que no está", func(t *testing.T) {
		h := montarAvisos(t, &dobleAvisos{})
		avisos := contarAvisos(t)
		w := pedirAv(t, h, http.MethodDelete, "/api/branches/"+desconocido.String(),
			avAdmin(t), "")
		avCodigo(t, w, http.StatusNotFound)
		avisos.exigeSilencio(t, "borrar una sucursal que no está")
	})

	t.Run("unos ajustes que la base no aceptó", func(t *testing.T) {
		h := montarAvisos(t, &dobleAvisos{falloAlEscribir: errAvFalloDeBase})
		avisos := contarAvisos(t)
		w := pedirAv(t, h, http.MethodPut, "/api/settings", avAdmin(t), `{"cupRate":340}`)
		avCodigo(t, w, http.StatusInternalServerError)
		avisos.exigeSilencio(t, "guardar unos ajustes que la base no aceptó")
	})

	t.Run("editar un producto que no está", func(t *testing.T) {
		h := montarDeDatos(t, datosDePrueba())
		avisos := contarAvisos(t)
		w := pedirDeDatos(t, h, http.MethodPatch, "/api/products/"+desconocido.String(),
			superAdminDeDatos(t), `{"weight":1}`, nil)
		avCodigo(t, w, http.StatusNotFound)
		avisos.exigeSilencio(t, "editar un producto que no está")
	})

	t.Run("borrar un producto que no está", func(t *testing.T) {
		h := montarDeDatos(t, datosDePrueba())
		avisos := contarAvisos(t)
		w := pedirDeDatos(t, h, http.MethodDelete, "/api/products/"+desconocido.String(),
			superAdminDeDatos(t), "", nil)
		avCodigo(t, w, http.StatusNotFound)
		avisos.exigeSilencio(t, "borrar un producto que no está")
	})

	t.Run("editar un pedido de otra sucursal", func(t *testing.T) {
		h := servidorDePedidos(t, datosDePedidos())
		avisos := contarAvisos(t)
		// El de Holguín, con el token de Santiago: 404, y por eso no se escribió nada.
		w := pedirPedidos(t, h, http.MethodPatch, "/api/orders/"+pedidosHolA.String(),
			tokenDeSantiagoPedidos(t), `{"customerName":"x"}`, nil)
		avCodigo(t, w, http.StatusNotFound)
		avisos.exigeSilencio(t, "editar un pedido de otra sucursal")
	})

	t.Run("borrar un pedido que no está", func(t *testing.T) {
		h := servidorDePedidos(t, datosDePedidos())
		avisos := contarAvisos(t)
		w := pedirPedidos(t, h, http.MethodDelete, "/api/orders/"+desconocido.String(),
			tokenDeSantiagoPedidos(t), "", nil)
		avCodigo(t, w, http.StatusNotFound)
		avisos.exigeSilencio(t, "borrar un pedido que no está")
	})
}

// LEER NO AVISA. Un aviso por cada lectura sería la pantalla recargándose sola en bucle,
// y cada recarga es otra lectura.
func TestLeerNoAvisaEnNingunaPantalla(t *testing.T) {
	h := montarAvisos(t, &dobleAvisos{})
	avisos := contarAvisos(t)

	pedirAv(t, h, http.MethodGet, "/api/vehicles/"+avVehStg.String(), avOperadorStg(t), "")
	pedirAv(t, h, http.MethodGet, "/api/settings", avAdmin(t), "")

	avisos.exigeSilencio(t, "leer")
}

// datosConPesosQueCambian: un pedido cuyo peso NO cuadra con el catálogo. Sin esto, el
// repaso no actualiza nada y la prueba del aviso pasaría por la razón equivocada.
func datosConPesosQueCambian() *dobleDePedidos {
	d := datosDePedidos()
	d.pesos = []sqlc.PesosDelCatalogoPorFuenteRow{
		{ID: pedidosStgA, PesoGuardado: 10, PesoCatalogo: 12.5}, // cambia
		{ID: pedidosStgB, PesoGuardado: 5, PesoCatalogo: 5},     // igual
	}
	return d
}

// El repaso de pesos SÍ avisa cuando escribe: cambia el peso de pedidos que alguien tiene
// delante, y el peso es con lo que se carga el camión.
func TestElRepasoDePesosQueEscribeAvisa(t *testing.T) {
	h := servidorDePedidos(t, datosConPesosQueCambian())
	avisos := contarAvisos(t)

	w := pedirPedidos(t, h, http.MethodPost, "/api/orders/recompute-weights", "", "",
		map[string]string{"X-Api-Key": llavePedidos})
	avCodigo(t, w, http.StatusOK)

	var salida RecalculoSalida
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatalf("respuesta ilegible: %s", w.Body.String())
	}
	if salida.Updated == 0 {
		t.Fatalf("el repaso no escribió nada: la prueba pasaría por la razón equivocada: %s",
			w.Body.String())
	}
	avisos.exige(t, "el repaso de pesos", CambioPedidos)
}

// El repaso de pesos EN SECO no escribe una fila. Avisar ahí es mandar a toda la oficina a
// bajarse los pedidos por una simulación.
func TestElRepasoDePesosEnSecoNoAvisa(t *testing.T) {
	h := servidorDePedidos(t, datosConPesosQueCambian())
	avisos := contarAvisos(t)

	w := pedirPedidos(t, h, http.MethodPost, "/api/orders/recompute-weights", "",
		`{"dryRun":true}`, map[string]string{"X-Api-Key": llavePedidos})
	avCodigo(t, w, http.StatusOK)

	var salida RecalculoSalida
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatalf("respuesta ilegible: %s", w.Body.String())
	}
	if !salida.DryRun || salida.Updated == 0 {
		t.Fatalf("la prueba no llegó a correr en seco sobre algo que cambiaría: %s",
			w.Body.String())
	}
	avisos.exigeSilencio(t, "el repaso de pesos en seco")
}

// --------------------------------------------------------------------------- el suelo

// NINGUNA ESCRITURA SE QUEDA SIN AVISAR, mirando el CÓDIGO y no las rutas montadas.
//
// Es el mismo molde que `TestNingunaEscrituraDelTableroSeQuedaSinAvisar` y por la misma
// razón: lo que hay que impedir es que alguien añada una puerta nueva —un `PATCH` más, un
// borrado en lote— y se le olvide el aviso. Montar las que hay hoy no cazaría la de
// mañana.
func TestNingunaEscrituraDeNingunaPantallaSeQuedaSinAvisar(t *testing.T) {
	// fichero -> manejadores que ESCRIBEN algo que una pantalla enseña.
	//
	// Lo que NO está aquí, y por qué:
	//
	//   - `altaDeProductoRetirada`: contesta 410 y no escribe nada.
	//   - `crearOrigen`, `actualizarOrigen`, `borrarOrigen` (`almacenes.go`): ninguna
	//     pantalla de la aplicación pide `/api/origins` — se comprobó buscando `origins`
	//     en `app/lib` el 17/09/2026. Son herencia del front de delivery.
	//   - `recomputar` (`espejo.go`): no escribe; el recosteo lo hace `/api/quote/batch`,
	//     que ya avisa por su cuenta. Avisar aquí sería avisar dos veces de lo mismo.
	escriben := map[string][]string{
		"vehiculos.go": {"crearVehiculo", "actualizarVehiculo", "borrarVehiculo"},
		"tipos_vehiculo.go": {
			"crearTipoDeVehiculo", "actualizarTipoDeVehiculo", "borrarTipoDeVehiculo",
		},
		"sucursales.go": {"crearSucursal", "actualizarSucursal", "borrarSucursal"},
		"ajustes.go":    {"guardarAjustes"},
		"almacenes.go":  {"guardarAlmacenes"},
		"productos.go":  {"actualizarProducto", "borrarProducto"},
		"pedidos.go":    {"actualizarPedido", "borrarPedido", "recalcularPesos"},
		"espejo.go":     {"sincronizarProductos"},
	}
	// Qué gancho tiene que aparecer dentro de cada uno.
	gancho := map[string]string{
		"vehiculos.go":      "avisarCambioDeVehiculos(",
		"tipos_vehiculo.go": "avisarCambioDeTiposDeVehiculo(",
		"sucursales.go":     "avisarCambioDeSucursales(",
		"ajustes.go":        "avisarCambioDeAjustes(",
		"almacenes.go":      "avisarCambioDeAlmacenes(",
		"productos.go":      "avisarCambioDelCatalogo(",
		"pedidos.go":        "avisarCambioDePedidos(",
		"espejo.go":         "avisarCambioDelCatalogo(",
	}

	patron := regexp.MustCompile(`func \(s \*Servidor\) (\w+)\(w http\.ResponseWriter`)

	for fichero, manejadores := range escriben {
		crudo, err := os.ReadFile(fichero)
		if err != nil {
			t.Fatal(err)
		}
		fuente := string(crudo)
		indices := patron.FindAllStringSubmatchIndex(fuente, -1)
		vistos := map[string]bool{}

		for i, idx := range indices {
			nombre := fuente[idx[2]:idx[3]]
			fin := len(fuente)
			if i+1 < len(indices) {
				fin = indices[i+1][0]
			}
			cuerpo := fuente[idx[0]:fin]

			esDeEscritura := false
			for _, e := range manejadores {
				if nombre == e {
					esDeEscritura = true
				}
			}
			if !esDeEscritura {
				continue
			}
			vistos[nombre] = true
			if !strings.Contains(cuerpo, gancho[fichero]) {
				t.Errorf("%s: %s escribe algo que una pantalla enseña y NO avisa. "+
					"Lo que haga esa persona no aparecerá en la pantalla de al lado "+
					"hasta dentro de dos minutos (cinco en la APK)", fichero, nombre)
			}
		}

		// EL SUELO: si mañana se renombra un manejador, el bucle de arriba dejaría de
		// mirar lo que cree y esta prueba se quedaría verde para siempre.
		for _, e := range manejadores {
			if !vistos[e] {
				t.Errorf("%s: no se encontró el manejador %s. O se renombró, o se movió, "+
					"y esta prueba ha dejado de comprobar lo que dice que comprueba",
					fichero, e)
			}
		}
	}
}

// Y EL BUS DE VERDAD reparte cada tipo nuevo tal cual, sin tocar el freno ni el latido.
//
// Los ganchos de arriba se prueban sustituidos; esto comprueba el otro extremo: que
// `eventos.go` los enganchó al bus y que el tipo llega escrito como lo espera la pantalla.
func TestLosTiposNuevosLleganPorElBus(t *testing.T) {
	for _, tipo := range []string{CambioVehiculos, CambioAlmacenes, CambioSucursales, CambioAjustes} {
		t.Run(tipo, func(t *testing.T) {
			bus := NuevoDifusor()
			canal, cortar, vivo := bus.Suscribir()
			if !vivo {
				t.Fatal("el bus nació cerrado")
			}
			defer cortar()

			if !bus.Avisar(tipo, nil) {
				t.Fatalf("el bus no repartió «%s»", tipo)
			}
			c := <-canal
			var m map[string]any
			if err := json.Unmarshal(c.datos(), &m); err != nil {
				t.Fatal(err)
			}
			if m["tipo"] != tipo {
				t.Fatalf("llegó el tipo %v y se esperaba %q: la pantalla mira ESE texto, "+
					"y con otro se recibe y se ignora sin que nada falle", m["tipo"], tipo)
			}
		})
	}
}

// Y que los cuatro sean DISTINTOS entre sí y de los que ya había. Dos tipos con el mismo
// texto es una pantalla refrescándose por lo que cambió en otra.
func TestLosTiposDeCambioNoSeRepiten(t *testing.T) {
	todos := []string{
		CambioPedidos, CambioCatalogo, CambioRutas, CambioClientes, CambioTablero,
		CambioVehiculos, CambioAlmacenes, CambioSucursales, CambioAjustes,
	}
	visto := map[string]bool{}
	for _, t2 := range todos {
		if visto[t2] {
			t.Errorf("el tipo «%s» está dos veces: una pantalla se refrescaría por lo que "+
				"cambió en otra", t2)
		}
		visto[t2] = true
	}
}
