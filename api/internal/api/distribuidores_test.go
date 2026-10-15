package api

// LOS DISTRIBUIDORES SON UN NOMENCLADOR POR SUCURSAL — issue 7 de Amado, 14/10/2026 (migración 00019).
//
// Es la persona responsable de la entrega y de devolver las facturas entregadas. Cada sucursal tiene
// los suyos: quien trabaja en una ve y toca sólo los suyos (los de otra son un 404, no un 403), y se
// asocian a la ruta AL CREARLA, con la validación de que sea de la MISMA sucursal que la ruta y que
// siga en activo.
//
// QUÉ PRUEBA ESTO Y QUÉ NO. Va contra `dobleDeDistribuidores`, que reimplementa el SQL de
// `distribuidores.sql` en Go: comprueba que el manejador y `alcance.Acotado` PASAN la sucursal que toca
// (quien la quite de `Acotado` pone esto en rojo). Que el SQL de verdad la use lo prueba
// `store/sqlc/distribuidores_motor_real_test.go` contra Postgres, que es lo único que ve la base.
//
// TODO VA EN PAREJA: cada «no» tiene su «sí» al lado, para que una prueba que dice 404 no pase con el
// recurso roto del todo.

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
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

var (
	// Los cuatro de las pruebas: dos de Santiago (uno con una ruta a su nombre), uno RETIRADO de
	// Santiago y uno de Holguín. «Juan Pérez» existe en las dos sucursales a propósito.
	distJuanStg   = uuid.MustParse("d1000000-0000-0000-0000-000000000001")
	distMariaStg  = uuid.MustParse("d1000000-0000-0000-0000-000000000002")
	distPedroStg  = uuid.MustParse("d1000000-0000-0000-0000-000000000003") // retirado
	distJuanHol   = uuid.MustParse("d1000000-0000-0000-0000-000000000004")
	rutaHistorica = uuid.MustParse("e1000000-0000-0000-0000-000000000001")
)

// --------------------------------------------------------------------------- el doble

type distribuidorDePrueba struct {
	sqlc.Distribuidore
	// rutas: cuántas rutas lo usan YA al empezar la prueba (además de las que arme la prueba).
	rutas int64
}

// dobleDeDistribuidores añade al doble de las rutas el nomenclador y lo que las rutas guardan de él.
type dobleDeDistribuidores struct {
	*dobleDeRutas

	lista []distribuidorDePrueba
	// escritos cuenta las escrituras que de verdad llegaron al nomenclador.
	escritos int
	// distribuidorDe: el distribuidor de cada ruta, que el doble de rutas no sabe guardar.
	distribuidorDe map[uuid.UUID]pgtype.UUID
	// tocadas: las veces que una escritura de ruta llegó con `tocar_distribuidor` puesto.
	tocadas int
	// falloAlEscribir se devuelve en el alta y en el cambio (una avería, que no es el 23505).
	falloAlEscribir error
}

func nuevoDobleDeDistribuidores() (*dobleDeDistribuidores, [3]uuid.UUID, uuid.UUID) {
	base, pedidos, ajeno := datosDeReparto()
	ahora := time.Now()
	hecho := func(id, sucursal uuid.UUID, nombre string, activo bool, rutas int64) distribuidorDePrueba {
		return distribuidorDePrueba{rutas: rutas, Distribuidore: sqlc.Distribuidore{
			ID: id, BranchID: sucursal, Nombre: nombre, Activo: activo,
			CreatedAt: pgtype.Timestamptz{Time: ahora, Valid: true},
			UpdatedAt: pgtype.Timestamptz{Time: ahora, Valid: true},
		}}
	}
	return &dobleDeDistribuidores{
		dobleDeRutas: base,
		lista: []distribuidorDePrueba{
			hecho(distJuanStg, stgDeRutas, "Juan Pérez", true, 1),
			hecho(distMariaStg, stgDeRutas, "María López", true, 0),
			hecho(distPedroStg, stgDeRutas, "Pedro Gil", false, 0),
			hecho(distJuanHol, holDeRutas, "Juan Pérez", true, 0),
		},
		distribuidorDe: map[uuid.UUID]pgtype.UUID{},
	}, pedidos, ajeno
}

// alcanzaDist es el `(sucursal IS NULL OR branch_id = sucursal)` del SQL.
func alcanzaDist(sucursal pgtype.UUID, branch uuid.UUID) bool {
	return !sucursal.Valid || sucursal.Bytes == [16]byte(branch)
}

func nombreClave(n string) string { return strings.ToLower(strings.TrimSpace(n)) }

func (d *dobleDeDistribuidores) usos(id uuid.UUID, inicial int64) int64 {
	n := inicial
	for _, dist := range d.distribuidorDe {
		if dist.Valid && dist.Bytes == [16]byte(id) {
			n++
		}
	}
	return n
}

func (d *dobleDeDistribuidores) buscar(id uuid.UUID, sucursal pgtype.UUID) (int, bool) {
	for i, x := range d.lista {
		if x.ID == id && alcanzaDist(sucursal, x.BranchID) {
			return i, true
		}
	}
	return 0, false
}

// repetida es el índice único `(branch_id, lower(btrim(nombre)))`.
func (d *dobleDeDistribuidores) repetida(nombre string, sucursal uuid.UUID, excepto uuid.UUID) bool {
	for _, x := range d.lista {
		if x.ID != excepto && x.BranchID == sucursal && nombreClave(x.Nombre) == nombreClave(nombre) {
			return true
		}
	}
	return false
}

func nombreDeSucursalDeRutas(id uuid.UUID) string {
	if id == holDeRutas {
		return "Holguín"
	}
	return "Santiago"
}

func (d *dobleDeDistribuidores) ListarDistribuidores(_ context.Context, arg sqlc.ListarDistribuidoresParams) ([]sqlc.ListarDistribuidoresRow, error) {
	filas := []sqlc.ListarDistribuidoresRow{}
	for _, x := range d.lista {
		if !alcanzaDist(arg.Sucursal, x.BranchID) {
			continue
		}
		if arg.SoloActivos != nil && *arg.SoloActivos && !x.Activo {
			continue
		}
		filas = append(filas, sqlc.ListarDistribuidoresRow{
			ID: x.ID, BranchID: x.BranchID, Nombre: x.Nombre, Activo: x.Activo,
			CreatedAt: x.CreatedAt, UpdatedAt: x.UpdatedAt,
			SucursalNombre: nombreDeSucursalDeRutas(x.BranchID), Rutas: d.usos(x.ID, x.rutas),
		})
	}
	return filas, nil
}

func (d *dobleDeDistribuidores) ObtenerDistribuidor(_ context.Context, arg sqlc.ObtenerDistribuidorParams) (sqlc.ObtenerDistribuidorRow, error) {
	i, ok := d.buscar(arg.ID, arg.Sucursal)
	if !ok {
		return sqlc.ObtenerDistribuidorRow{}, pgx.ErrNoRows
	}
	x := d.lista[i]
	return sqlc.ObtenerDistribuidorRow{ID: x.ID, BranchID: x.BranchID, Nombre: x.Nombre, Activo: x.Activo}, nil
}

func (d *dobleDeDistribuidores) CrearDistribuidor(_ context.Context, arg sqlc.CrearDistribuidorParams) (sqlc.Distribuidore, error) {
	if d.falloAlEscribir != nil {
		return sqlc.Distribuidore{}, d.falloAlEscribir
	}
	if d.repetida(arg.Nombre, arg.BranchID, uuid.Nil) {
		return sqlc.Distribuidore{}, &pgconn.PgError{Code: "23505"}
	}
	x := sqlc.Distribuidore{ID: uuid.New(), BranchID: arg.BranchID, Nombre: arg.Nombre, Activo: arg.Activo}
	d.lista = append(d.lista, distribuidorDePrueba{Distribuidore: x})
	d.escritos++
	return x, nil
}

func (d *dobleDeDistribuidores) ActualizarDistribuidor(_ context.Context, arg sqlc.ActualizarDistribuidorParams) (sqlc.Distribuidore, error) {
	if d.falloAlEscribir != nil {
		return sqlc.Distribuidore{}, d.falloAlEscribir
	}
	i, ok := d.buscar(arg.ID, arg.Sucursal)
	if !ok {
		return sqlc.Distribuidore{}, pgx.ErrNoRows
	}
	x := &d.lista[i]
	if arg.Nombre != nil {
		if d.repetida(*arg.Nombre, x.BranchID, x.ID) {
			return sqlc.Distribuidore{}, &pgconn.PgError{Code: "23505"}
		}
		x.Nombre = *arg.Nombre
	}
	if arg.Activo != nil {
		x.Activo = *arg.Activo
	}
	d.escritos++
	return x.Distribuidore, nil
}

func (d *dobleDeDistribuidores) RetirarDistribuidor(_ context.Context, arg sqlc.RetirarDistribuidorParams) (uuid.UUID, error) {
	i, ok := d.buscar(arg.ID, arg.Sucursal)
	if !ok {
		return uuid.Nil, pgx.ErrNoRows
	}
	d.lista[i].Activo = false
	d.escritos++
	return d.lista[i].BranchID, nil
}

func (d *dobleDeDistribuidores) BorrarDistribuidorSinUso(_ context.Context, arg sqlc.BorrarDistribuidorSinUsoParams) (uuid.UUID, error) {
	i, ok := d.buscar(arg.ID, arg.Sucursal)
	if !ok || d.usos(d.lista[i].ID, d.lista[i].rutas) > 0 {
		return uuid.Nil, pgx.ErrNoRows
	}
	rama := d.lista[i].BranchID
	d.lista = append(d.lista[:i], d.lista[i+1:]...)
	d.escritos++
	return rama, nil
}

// --- lo que las rutas guardan del distribuidor

func (d *dobleDeDistribuidores) nombreDe(id pgtype.UUID) *string {
	if !id.Valid {
		return nil
	}
	for _, x := range d.lista {
		if [16]byte(x.ID) == id.Bytes {
			n := x.Nombre
			return &n
		}
	}
	return nil
}

func (d *dobleDeDistribuidores) CrearRuta(ctx context.Context, arg sqlc.CrearRutaParams) (sqlc.CrearRutaRow, error) {
	fila, err := d.dobleDeRutas.CrearRuta(ctx, arg)
	if err == nil && arg.DistribuidorID.Valid {
		d.distribuidorDe[fila.ID] = arg.DistribuidorID
	}
	return fila, err
}

func (d *dobleDeDistribuidores) ObtenerRuta(ctx context.Context, arg sqlc.ObtenerRutaParams) (sqlc.ObtenerRutaRow, error) {
	fila, err := d.dobleDeRutas.ObtenerRuta(ctx, arg)
	if err == nil {
		fila.DistribuidorID = d.distribuidorDe[fila.ID]
		fila.DistribuidorNombre = d.nombreDe(fila.DistribuidorID)
	}
	return fila, err
}

func (d *dobleDeDistribuidores) ListarRutas(ctx context.Context, arg sqlc.ListarRutasParams) ([]sqlc.ListarRutasRow, error) {
	filas, err := d.dobleDeRutas.ListarRutas(ctx, arg)
	for i := range filas {
		filas[i].DistribuidorID = d.distribuidorDe[filas[i].ID]
		filas[i].DistribuidorNombre = d.nombreDe(filas[i].DistribuidorID)
	}
	return filas, err
}

// tocarDistribuidor repite el `CASE WHEN tocar_distribuidor THEN distribuidor_id ELSE distribuidor_id END`.
func (d *dobleDeDistribuidores) tocarDistribuidor(ruta uuid.UUID, tocar bool, nuevo pgtype.UUID) {
	if !tocar {
		return
	}
	d.tocadas++
	if nuevo.Valid {
		d.distribuidorDe[ruta] = nuevo
	} else {
		delete(d.distribuidorDe, ruta)
	}
}

func (d *dobleDeDistribuidores) ActualizarEstadoDeRuta(ctx context.Context, arg sqlc.ActualizarEstadoDeRutaParams) (sqlc.ActualizarEstadoDeRutaRow, error) {
	fila, err := d.dobleDeRutas.ActualizarEstadoDeRuta(ctx, arg)
	if err == nil {
		d.tocarDistribuidor(arg.ID, arg.TocarDistribuidor, arg.DistribuidorID)
	}
	return fila, err
}

func (d *dobleDeDistribuidores) CambiarVehiculoDeRuta(ctx context.Context, arg sqlc.CambiarVehiculoDeRutaParams) (sqlc.CambiarVehiculoDeRutaRow, error) {
	fila, err := d.dobleDeRutas.CambiarVehiculoDeRuta(ctx, arg)
	if err == nil {
		d.tocarDistribuidor(arg.ID, arg.TocarDistribuidor, arg.DistribuidorID)
	}
	return fila, err
}

// ObtenerSucursal: el nombre de la sucursal de un distribuidor recién escrito (`nombreDeLaSucursal`).
func (d *dobleDeDistribuidores) ObtenerSucursal(_ context.Context, arg sqlc.ObtenerSucursalParams) (sqlc.Branch, error) {
	if arg.ID != stgDeRutas && arg.ID != holDeRutas {
		return sqlc.Branch{}, pgx.ErrNoRows
	}
	if arg.Sucursal.Valid && arg.Sucursal.Bytes != [16]byte(arg.ID) {
		return sqlc.Branch{}, pgx.ErrNoRows
	}
	return sqlc.Branch{ID: arg.ID, Name: nombreDeSucursalDeRutas(arg.ID)}, nil
}

type fuenteDeDist struct{ q *dobleDeDistribuidores }

func (f fuenteDeDist) Consultas() sqlc.Querier { return f.q }
func (f fuenteDeDist) EnTx(_ context.Context, fn func(sqlc.Querier) error) error {
	copia := f.q.clonar()
	if err := fn(f.q); err != nil {
		f.q.restaurar(copia)
		return err
	}
	return nil
}

// montarDist monta lo mismo que `montarRutas` MÁS las cuatro rutas del nomenclador, con el servidor
// de verdad (`NuevoServidor`) y sus mismos medios.
func montarDist(t *testing.T, q *dobleDeDistribuidores) http.Handler {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoDeRutas)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	porteria := alcance.NuevaPorteria(fuenteDeDist{q: q}, reg)
	verif := auth.NuevoVerificador([]byte(secretoDeRutas))
	s := NuevoServidor(cfg, reg, porteria, verif, func(context.Context) error { return nil })

	rt := httpx.NuevoRouter(httpx.IDDePeticion, httpx.ConRegistro(reg), httpx.RecuperarPanico, httpx.RegistrarPeticiones, httpx.SinCache)
	sesion := []httpx.Medio{verif.Exigir, porteria.Exigir}
	admin := []httpx.Medio{verif.Exigir, auth.ExigirAdmin, porteria.Exigir}
	s.rutasDeReparto(rt, sesion, admin)
	s.rutasDeDistribuidores(rt, sesion)
	return rt.Handler()
}

// --------------------------------------------------------------------------- personas y peticiones

func logisticoDe(t *testing.T, sucursal uuid.UUID) string {
	t.Helper()
	return tokenDeRutas(t, map[string]any{"sub": "p-" + sucursal.String(), "email": "log@procovar.cu",
		"role": "LOGISTICO", "branchId": sucursal.String(), "entradas": []string{"delivery.entrar"}})
}

func superSinSucursalDeDist(t *testing.T) string {
	t.Helper()
	return tokenDeRutas(t, map[string]any{"sub": "p-super", "email": "super@procovar.cu",
		"role": "SUPER ADMIN", "entradas": []string{"delivery.entrar"}})
}

// llamarDist es `llamarRutas` con la cabecera de sucursal, que es como un SUPER ADMIN elige cuál mira.
func llamarDist(t *testing.T, h http.Handler, metodo, ruta, jwt, sucursal, cuerpo string) *httptest.ResponseRecorder {
	t.Helper()
	var lector io.Reader
	if cuerpo != "" {
		lector = strings.NewReader(cuerpo)
	}
	r := httptest.NewRequest(metodo, ruta, lector)
	if jwt != "" {
		r.Header.Set("Authorization", "Bearer "+jwt)
	}
	if cuerpo != "" {
		r.Header.Set("Content-Type", "application/json")
	}
	if sucursal != "" {
		r.Header.Set("X-Sucursal-Id", sucursal)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func codigoDist(t *testing.T, w *httptest.ResponseRecorder, esperado int) {
	t.Helper()
	if w.Code != esperado {
		t.Fatalf("código %d, se esperaba %d: %s", w.Code, esperado, w.Body.String())
	}
}

func listaDeDist(t *testing.T, w *httptest.ResponseRecorder) []DistribuidorSalida {
	t.Helper()
	codigoDist(t, w, http.StatusOK)
	var lista []DistribuidorSalida
	if err := json.Unmarshal(w.Body.Bytes(), &lista); err != nil {
		t.Fatalf("la lista no es JSON: %v: %s", err, w.Body.String())
	}
	return lista
}

func idsDeDist(lista []DistribuidorSalida) map[uuid.UUID]bool {
	ids := map[uuid.UUID]bool{}
	for _, d := range lista {
		ids[d.ID] = true
	}
	return ids
}

func distribuidorDeRespuesta(t *testing.T, w *httptest.ResponseRecorder, codigo int) DistribuidorSalida {
	t.Helper()
	codigoDist(t, w, codigo)
	var d DistribuidorSalida
	if err := json.Unmarshal(w.Body.Bytes(), &d); err != nil {
		t.Fatalf("la respuesta no es un distribuidor: %v: %s", err, w.Body.String())
	}
	return d
}

// --------------------------------------------------------------------------- listar

// CADA SUCURSAL VE SÓLO LOS SUYOS. «Juan Pérez» existe en Santiago y en Holguín y ninguna lista
// trae el de la otra. El modo «todas» ve las listas de todas, cada fila con su sucursal (en una ruta
// se elige la sucursal en el primer paso y el selector tiene que poder ofrecer los de ESA).
func TestCadaSucursalVeSoloSusDistribuidores(t *testing.T) {
	h := montarDist(t, func() *dobleDeDistribuidores { d, _, _ := nuevoDobleDeDistribuidores(); return d }())

	t.Run("Santiago ve los suyos (también el retirado) y no el de Holguín", func(t *testing.T) {
		lista := listaDeDist(t, llamarDist(t, h, http.MethodGet, "/api/distribuidores", logisticoDe(t, stgDeRutas), "", ""))
		ids := idsDeDist(lista)
		if len(lista) != 3 || !ids[distJuanStg] || !ids[distMariaStg] || !ids[distPedroStg] || ids[distJuanHol] {
			t.Fatalf("Santiago tenía que ver sólo sus tres y vio %+v", lista)
		}
		for _, d := range lista {
			if d.SucursalID != stgDeRutas || d.Sucursal == nil || *d.Sucursal != "Santiago" {
				t.Fatalf("el distribuidor tiene que decir de quién es: %+v", d)
			}
		}
	})

	t.Run("con activos=1 salen sólo los que se pueden elegir", func(t *testing.T) {
		lista := listaDeDist(t, llamarDist(t, h, http.MethodGet, "/api/distribuidores?activos=1", logisticoDe(t, stgDeRutas), "", ""))
		ids := idsDeDist(lista)
		if len(lista) != 2 || ids[distPedroStg] {
			t.Fatalf("con activos=1 no puede salir el retirado: %+v", lista)
		}
	})

	t.Run("Holguín ve el suyo, no los de Santiago", func(t *testing.T) {
		lista := listaDeDist(t, llamarDist(t, h, http.MethodGet, "/api/distribuidores", logisticoDe(t, holDeRutas), "", ""))
		if len(lista) != 1 || lista[0].ID != distJuanHol {
			t.Fatalf("Holguín tenía que ver sólo el suyo y vio %+v", lista)
		}
	})

	t.Run("un SUPER ADMIN sin sucursal (modo «todas») ve las de todas, cada una con su sucursal", func(t *testing.T) {
		lista := listaDeDist(t, llamarDist(t, h, http.MethodGet, "/api/distribuidores", superSinSucursalDeDist(t), "", ""))
		if len(lista) != 4 {
			t.Fatalf("en modo «todas» tenía que ver los cuatro y vio %+v", lista)
		}
		for _, d := range lista {
			if d.Sucursal == nil || *d.Sucursal == "" {
				t.Fatalf("en modo «todas» cada fila tiene que decir su sucursal: %+v", d)
			}
		}
	})

	t.Run("un SUPER ADMIN que mira Holguín ve sólo lo de Holguín", func(t *testing.T) {
		lista := listaDeDist(t, llamarDist(t, h, http.MethodGet, "/api/distribuidores", superSinSucursalDeDist(t), holDeRutas.String(), ""))
		if len(lista) != 1 || lista[0].ID != distJuanHol {
			t.Fatalf("mirando Holguín tenía que ver sólo el suyo y vio %+v", lista)
		}
	})

	t.Run("sin sesión: 401", func(t *testing.T) {
		codigoDist(t, llamarDist(t, h, http.MethodGet, "/api/distribuidores", "", "", ""), http.StatusUnauthorized)
	})
}

// --------------------------------------------------------------------------- editar y borrar

// SANTIAGO NO TOCA AL DE HOLGUÍN: 404 —no 403— y no se escribe nada. En PAREJA: los suyos sí.
func TestSantiagoNoTocaLosDistribuidoresDeHolguin(t *testing.T) {
	santiago := logisticoDe(t, stgDeRutas)

	for _, p := range []struct{ metodo, cuerpo string }{
		{http.MethodPatch, `{"nombre":"Otro"}`},
		{http.MethodDelete, ``},
	} {
		t.Run(p.metodo+" de Santiago sobre el de Holguín: 404 y no escribe", func(t *testing.T) {
			d, _, _ := nuevoDobleDeDistribuidores()
			w := llamarDist(t, montarDist(t, d), p.metodo, "/api/distribuidores/"+distJuanHol.String(), santiago, "", p.cuerpo)
			codigoDist(t, w, http.StatusNotFound)
			if d.escritos != 0 {
				t.Fatalf("el 404 llegó DESPUÉS de escribir: %d escrituras", d.escritos)
			}
		})
	}

	t.Run("PATCH de Santiago sobre uno suyo: pasa", func(t *testing.T) {
		d, _, _ := nuevoDobleDeDistribuidores()
		w := llamarDist(t, montarDist(t, d), http.MethodPatch, "/api/distribuidores/"+distMariaStg.String(), santiago, "", `{"nombre":"María del Carmen"}`)
		got := distribuidorDeRespuesta(t, w, http.StatusOK)
		if got.Nombre != "María del Carmen" || d.escritos != 1 {
			t.Fatalf("tenía que renombrar y escribir una vez: %+v, %d", got, d.escritos)
		}
	})

	t.Run("PATCH que RETIRA a uno suyo: pasa y deja de ofrecerse", func(t *testing.T) {
		d, _, _ := nuevoDobleDeDistribuidores()
		h := montarDist(t, d)
		codigoDist(t, llamarDist(t, h, http.MethodPatch, "/api/distribuidores/"+distMariaStg.String(), santiago, "", `{"activo":false}`), http.StatusOK)
		lista := listaDeDist(t, llamarDist(t, h, http.MethodGet, "/api/distribuidores?activos=1", santiago, "", ""))
		if idsDeDist(lista)[distMariaStg] {
			t.Fatalf("retirada, María seguía ofreciéndose: %+v", lista)
		}
	})

	t.Run("DELETE de uno suyo SIN rutas: se borra de verdad", func(t *testing.T) {
		d, _, _ := nuevoDobleDeDistribuidores()
		w := llamarDist(t, montarDist(t, d), http.MethodDelete, "/api/distribuidores/"+distMariaStg.String(), santiago, "", "")
		codigoDist(t, w, http.StatusOK)
		if !strings.Contains(w.Body.String(), `"retirado":false`) {
			t.Fatalf("no lo usa ninguna ruta, así que se borra y no se retira: %s", w.Body.String())
		}
		if _, hay := d.buscar(distMariaStg, pgtype.UUID{}); hay {
			t.Fatal("se dijo que se borró y sigue en la lista")
		}
	})

	t.Run("DELETE de uno suyo CON rutas: se RETIRA, no se borra", func(t *testing.T) {
		d, _, _ := nuevoDobleDeDistribuidores()
		w := llamarDist(t, montarDist(t, d), http.MethodDelete, "/api/distribuidores/"+distJuanStg.String(), santiago, "", "")
		codigoDist(t, w, http.StatusOK)
		if !strings.Contains(w.Body.String(), `"retirado":true`) {
			t.Fatalf("lo usa una ruta, así que se retira y no se borra: %s", w.Body.String())
		}
		i, hay := d.buscar(distJuanStg, pgtype.UUID{})
		if !hay || d.lista[i].Activo {
			t.Fatal("tenía que seguir en la lista, retirado: borrarlo dejaría la ruta sin quién la repartió")
		}
	})

	// ELEGIR SUCURSAL ACOTA, NO ABRE: un SUPER ADMIN que mira Santiago tampoco toca el de Holguín.
	t.Run("un SUPER ADMIN que mira Santiago no toca el de Holguín", func(t *testing.T) {
		d, _, _ := nuevoDobleDeDistribuidores()
		w := llamarDist(t, montarDist(t, d), http.MethodPatch, "/api/distribuidores/"+distJuanHol.String(),
			superSinSucursalDeDist(t), stgDeRutas.String(), `{"nombre":"Otro"}`)
		codigoDist(t, w, http.StatusNotFound)
		if d.escritos != 0 {
			t.Fatalf("el 404 llegó DESPUÉS de escribir: %d", d.escritos)
		}
	})

	t.Run("un SUPER ADMIN que mira Holguín toca el de Holguín", func(t *testing.T) {
		d, _, _ := nuevoDobleDeDistribuidores()
		w := llamarDist(t, montarDist(t, d), http.MethodPatch, "/api/distribuidores/"+distJuanHol.String(),
			superSinSucursalDeDist(t), holDeRutas.String(), `{"nombre":"Luis"}`)
		codigoDist(t, w, http.StatusOK)
	})

	// EN MODO «TODAS» SE VEN LAS LISTAS DE TODAS Y, COMO EN LAS RUTAS, SE TOCA LO QUE SE VE: no hay
	// «de todas» que confundir con el de una sucursal (cada fila dice la suya).
	t.Run("un SUPER ADMIN en modo «todas» toca el de cualquier sucursal", func(t *testing.T) {
		d, _, _ := nuevoDobleDeDistribuidores()
		codigoDist(t, llamarDist(t, montarDist(t, d), http.MethodPatch, "/api/distribuidores/"+distJuanHol.String(),
			superSinSucursalDeDist(t), "", `{"nombre":"Luis"}`), http.StatusOK)
	})

	t.Run("un id que no es un uuid o no existe: 404", func(t *testing.T) {
		d, _, _ := nuevoDobleDeDistribuidores()
		h := montarDist(t, d)
		codigoDist(t, llamarDist(t, h, http.MethodPatch, "/api/distribuidores/no-es-un-id", santiago, "", `{"nombre":"X"}`), http.StatusNotFound)
		codigoDist(t, llamarDist(t, h, http.MethodDelete, "/api/distribuidores/"+uuid.NewString(), santiago, "", ""), http.StatusNotFound)
	})
}

// --------------------------------------------------------------------------- crear

// UN DISTRIBUIDOR NUEVO NACE EN LA SUCURSAL DE QUIEN LO CREA, y no en la que mande el cliente.
func TestUnDistribuidorNuevoNaceEnLaSucursalDeQuienLoCrea(t *testing.T) {
	d, _, _ := nuevoDobleDeDistribuidores()
	h := montarDist(t, d)

	t.Run("Santiago", func(t *testing.T) {
		got := distribuidorDeRespuesta(t, llamarDist(t, h, http.MethodPost, "/api/distribuidores", logisticoDe(t, stgDeRutas),
			"", `{"nombre":"Ana Torres"}`), http.StatusCreated)
		if got.SucursalID != stgDeRutas || got.Sucursal == nil || *got.Sucursal != "Santiago" || !got.Activo {
			t.Fatalf("tenía que nacer en Santiago y en activo: %+v", got)
		}
	})

	t.Run("el cuerpo no elige la sucursal", func(t *testing.T) {
		got := distribuidorDeRespuesta(t, llamarDist(t, h, http.MethodPost, "/api/distribuidores", logisticoDe(t, stgDeRutas), "",
			`{"nombre":"Rosa","sucursalId":"`+holDeRutas.String()+`","branchId":"`+holDeRutas.String()+`"}`), http.StatusCreated)
		if got.SucursalID != stgDeRutas {
			t.Fatalf("el cuerpo movió el distribuidor de sucursal: %+v", got)
		}
	})

	t.Run("un SUPER ADMIN que mira Holguín lo crea en Holguín", func(t *testing.T) {
		got := distribuidorDeRespuesta(t, llamarDist(t, h, http.MethodPost, "/api/distribuidores", superSinSucursalDeDist(t),
			holDeRutas.String(), `{"nombre":"Sara"}`), http.StatusCreated)
		if got.SucursalID != holDeRutas {
			t.Fatalf("tenía que nacer en Holguín: %+v", got)
		}
	})

	// EN MODO «TODAS» NO SE CREA NADA: nacería sin dueño. El mensaje dice qué hacer.
	desarrollador := tokenDeRutas(t, map[string]any{"sub": "p-dev", "role": "DESARROLLADOR", "entradas": []string{"delivery.entrar"}})
	for nombre, jwt := range map[string]string{"SUPER ADMIN": superSinSucursalDeDist(t), "DESARROLLADOR": desarrollador} {
		t.Run(nombre+" sin sucursal elegida: 400 y no crea ninguno", func(t *testing.T) {
			d, _, _ := nuevoDobleDeDistribuidores()
			antes := len(d.lista)
			w := llamarDist(t, montarDist(t, d), http.MethodPost, "/api/distribuidores", jwt, "", `{"nombre":"Fulano"}`)
			codigoDist(t, w, http.StatusBadRequest)
			if !strings.Contains(w.Body.String(), msgDistribuidorSinSucursal) {
				t.Fatalf("el 400 tiene que decir qué hacer: %s", w.Body.String())
			}
			if d.escritos != 0 || len(d.lista) != antes {
				t.Fatalf("el 400 llegó DESPUÉS de crear: %d escrituras", d.escritos)
			}
		})
	}
}

// EL NOMBRE ES ÚNICO DENTRO DE LA SUCURSAL —sin distinguir mayúsculas ni espacios— Y SE REPITE ENTRE SUCURSALES.
func TestUnNombreRepetidoEnLaSucursalEsUn409(t *testing.T) {
	santiago := logisticoDe(t, stgDeRutas)

	for nombre, cuerpo := range map[string]string{
		"el mismo":                      `{"nombre":"Juan Pérez"}`,
		"con otras mayúsculas":          `{"nombre":"JUAN PÉREZ"}`,
		"con espacios de más":           `{"nombre":"  Juan   Pérez  "}`,
		"el de un RETIRADO de la misma": `{"nombre":"pedro gil"}`,
	} {
		t.Run("crear "+nombre+": 409", func(t *testing.T) {
			d, _, _ := nuevoDobleDeDistribuidores()
			antes := len(d.lista)
			w := llamarDist(t, montarDist(t, d), http.MethodPost, "/api/distribuidores", santiago, "", cuerpo)
			codigoDist(t, w, http.StatusConflict)
			if !strings.Contains(w.Body.String(), msgDistribuidorRepetido) {
				t.Fatalf("el 409 tiene que decir por qué: %s", w.Body.String())
			}
			if len(d.lista) != antes {
				t.Fatal("el 409 llegó DESPUÉS de crear")
			}
		})
	}

	t.Run("el mismo nombre en OTRA sucursal no es un choque", func(t *testing.T) {
		d, _, _ := nuevoDobleDeDistribuidores()
		// «María López» es de Santiago; Holguín puede tener la suya.
		codigoDist(t, llamarDist(t, montarDist(t, d), http.MethodPost, "/api/distribuidores", logisticoDe(t, holDeRutas), "",
			`{"nombre":"María López"}`), http.StatusCreated)
	})

	t.Run("renombrar a uno que ya existe: 409; a uno libre: pasa", func(t *testing.T) {
		d, _, _ := nuevoDobleDeDistribuidores()
		h := montarDist(t, d)
		w := llamarDist(t, h, http.MethodPatch, "/api/distribuidores/"+distMariaStg.String(), santiago, "", `{"nombre":"juan pérez"}`)
		codigoDist(t, w, http.StatusConflict)
		if !strings.Contains(w.Body.String(), msgDistribuidorRepetido) {
			t.Fatalf("el 409 del PATCH tiene que decir lo mismo que el del POST: %s", w.Body.String())
		}
		codigoDist(t, llamarDist(t, h, http.MethodPatch, "/api/distribuidores/"+distMariaStg.String(), santiago, "", `{"nombre":"María Elena"}`), http.StatusOK)
	})

	t.Run("un fallo cualquiera de la base sigue siendo un 500", func(t *testing.T) {
		// El 409 no puede tragarse las averías: sólo el 23505 es «ya existe».
		d, _, _ := nuevoDobleDeDistribuidores()
		d.falloAlEscribir = errAvFalloDeBase
		h := montarDist(t, d)
		codigoDist(t, llamarDist(t, h, http.MethodPost, "/api/distribuidores", santiago, "", `{"nombre":"Nuevo"}`), http.StatusInternalServerError)
		codigoDist(t, llamarDist(t, h, http.MethodPatch, "/api/distribuidores/"+distMariaStg.String(), santiago, "", `{"nombre":"Otro"}`), http.StatusInternalServerError)
	})
}

// EL NOMBRE SE LIMPIA y no puede quedar vacío.
func TestElNombreDelDistribuidorSeLimpiaYNoSeAdmiteVacio(t *testing.T) {
	santiago := logisticoDe(t, stgDeRutas)
	d, _, _ := nuevoDobleDeDistribuidores()
	h := montarDist(t, d)

	got := distribuidorDeRespuesta(t, llamarDist(t, h, http.MethodPost, "/api/distribuidores", santiago, "", `{"nombre":"  Ana    María   Torres "}`), http.StatusCreated)
	if got.Nombre != "Ana María Torres" {
		t.Fatalf("el nombre tenía que quedar limpio: %q", got.Nombre)
	}

	for nombre, cuerpo := range map[string]string{"sin nombre": `{}`, "vacío": `{"nombre":""}`, "sólo espacios": `{"nombre":"   "}`} {
		t.Run("crear "+nombre+": 400", func(t *testing.T) {
			antes := d.escritos
			codigoDist(t, llamarDist(t, h, http.MethodPost, "/api/distribuidores", santiago, "", cuerpo), http.StatusBadRequest)
			if d.escritos != antes {
				t.Fatal("el 400 llegó DESPUÉS de escribir")
			}
		})
	}
	t.Run("renombrar a vacío: 400 y no escribe", func(t *testing.T) {
		antes := d.escritos
		codigoDist(t, llamarDist(t, h, http.MethodPatch, "/api/distribuidores/"+distMariaStg.String(), santiago, "", `{"nombre":"   "}`), http.StatusBadRequest)
		if d.escritos != antes {
			t.Fatal("el 400 llegó DESPUÉS de escribir")
		}
	})
	t.Run("un PATCH sin nombre (sólo el estado) no lo toca", func(t *testing.T) {
		codigoDist(t, llamarDist(t, h, http.MethodPatch, "/api/distribuidores/"+distMariaStg.String(), santiago, "", `{"activo":false}`), http.StatusOK)
		i, _ := d.buscar(distMariaStg, pgtype.UUID{})
		if d.lista[i].Nombre != "María López" {
			t.Fatalf("un PATCH sin nombre cambió el nombre: %q", d.lista[i].Nombre)
		}
	})
}

func TestNombreDeDistribuidorUnEspacioEntrePalabras(t *testing.T) {
	for entrada, quiere := range map[string]string{
		"Juan":             "Juan",
		"  Juan   Pérez\t": "Juan Pérez",
		"Ana\n María":      "Ana María",
		"":                 "",
		"   \t ":           "",
	} {
		got, hay := nombreDeDistribuidor(entrada)
		if got != quiere || hay != (quiere != "") {
			t.Errorf("%q dio (%q, %v) y se esperaba (%q, %v)", entrada, got, hay, quiere, quiere != "")
		}
	}
}

// CUALQUIER SESIÓN DE REPARTO LO MANTIENE, también LOGISTICO («la APK es completa para el logístico»,
// Jose): no son de admin, como los tipos de vehículo. En pareja con la puerta: sin sesión, 401.
func TestUnLogisticoGestionaLosDistribuidoresDeSuSucursal(t *testing.T) {
	d, _, _ := nuevoDobleDeDistribuidores()
	h := montarDist(t, d)
	log := logisticoDe(t, stgDeRutas)

	got := distribuidorDeRespuesta(t, llamarDist(t, h, http.MethodPost, "/api/distribuidores", log, "", `{"nombre":"Nuevo"}`), http.StatusCreated)
	codigoDist(t, llamarDist(t, h, http.MethodPatch, "/api/distribuidores/"+got.ID.String(), log, "", `{"nombre":"Nuevo Nombre"}`), http.StatusOK)
	codigoDist(t, llamarDist(t, h, http.MethodDelete, "/api/distribuidores/"+got.ID.String(), log, "", ""), http.StatusOK)

	for _, p := range []struct{ metodo, ruta string }{
		{http.MethodPost, "/api/distribuidores"},
		{http.MethodPatch, "/api/distribuidores/" + distMariaStg.String()},
		{http.MethodDelete, "/api/distribuidores/" + distMariaStg.String()},
	} {
		escritos := d.escritos
		codigoDist(t, llamarDist(t, h, p.metodo, p.ruta, "", "", `{"nombre":"X"}`), http.StatusUnauthorized)
		if d.escritos != escritos {
			t.Fatalf("%s %s sin sesión escribió", p.metodo, p.ruta)
		}
	}
}

// LAS CUATRO RUTAS ESTÁN MONTADAS EN EL ROUTER DE VERDAD (`Rutas()`), no sólo en el montaje de arriba.
// Una prueba que monta `rutasDeDistribuidores` ella misma no vería que alguien quitó la línea de
// `servidor.go`: el recurso desaparecería con toda la suite en verde. Sin sesión se contesta 401 (la ruta
// existe y pide sesión); si no estuviera montada sería un 404.
func TestLasRutasDeDistribuidoresEstanEnElRouterDeVerdad(t *testing.T) {
	h := montarAvisos(t, &dobleAvisos{})
	for _, p := range []struct{ metodo, ruta string }{
		{http.MethodGet, "/api/distribuidores"},
		{http.MethodPost, "/api/distribuidores"},
		{http.MethodPatch, "/api/distribuidores/" + distJuanStg.String()},
		{http.MethodDelete, "/api/distribuidores/" + distJuanStg.String()},
	} {
		t.Run(p.metodo+" "+p.ruta, func(t *testing.T) {
			w := pedirAv(t, h, p.metodo, p.ruta, "", `{"nombre":"X"}`)
			if w.Code != http.StatusUnauthorized {
				t.Fatalf("sin sesión se esperaba 401 (la ruta existe y pide sesión) y salió %d: %s", w.Code, w.Body.String())
			}
		})
	}
}
