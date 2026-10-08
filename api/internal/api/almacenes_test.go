package api

// Orígenes y almacenes. El montaje común está en `clientes_test.go`.

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/store/sqlc"
)

// --------------------------------------------------------------------------- dobles

var errAccesosCaido = errors.New("auth 503: Service Unavailable")

// accesosFalso ocupa el sitio de Accesos. Las pruebas NO salen a la red: un servicio ajeno
// dentro de una prueba la vuelve lenta y, peor, la vuelve verde o roja según el día.
type accesosFalso struct {
	sucursales []SucursalConAlmacenes
	fallo      error
	// Lo que se vio pasar: el cuerpo tiene que llegar a Accesos TAL CUAL.
	guardado []byte
}

func (a *accesosFalso) Almacenes(context.Context) ([]SucursalConAlmacenes, error) {
	if a.fallo != nil {
		return nil, a.fallo
	}
	return a.sucursales, nil
}

func (a *accesosFalso) AlmacenesDeSucursal(_ context.Context, codigo string) ([]Almacen, error) {
	if a.fallo != nil {
		return nil, a.fallo
	}
	for _, s := range a.sucursales {
		if strings.EqualFold(s.Codigo, codigo) {
			return s.Almacenes, nil
		}
	}
	// Una sucursal que Accesos no conoce devuelve la lista vacía, no un error.
	return nil, nil
}

func (a *accesosFalso) GuardarAlmacenes(_ context.Context, cuerpo []byte) (map[string]any, error) {
	if a.fallo != nil {
		return nil, a.fallo
	}
	a.guardado = cuerpo
	return map[string]any{"almacenes": []any{}}, nil
}

func (d *dobleDatos) ListarOrigenes(_ context.Context, sucursal pgtype.UUID) ([]sqlc.ListarOrigenesRow, error) {
	var salida []sqlc.ListarOrigenesRow
	for _, o := range d.origenes {
		if sucursal.Valid && o.BranchID.Bytes != sucursal.Bytes {
			continue
		}
		salida = append(salida, o)
	}
	return salida, nil
}

func (d *dobleDatos) CrearOrigen(_ context.Context, arg sqlc.CrearOrigenParams) (sqlc.SavedOrigin, error) {
	o := sqlc.SavedOrigin{
		ID: uuid.New(), Name: arg.Name, Address: arg.Address, Lat: arg.Lat, Lng: arg.Lng,
		CreadoPor: arg.CreadoPor, BranchID: arg.BranchID,
	}
	d.origenes = append(d.origenes, sqlc.ListarOrigenesRow{
		ID: o.ID, Name: o.Name, Address: o.Address, Lat: o.Lat, Lng: o.Lng,
		CreadoPor: o.CreadoPor, BranchID: o.BranchID,
	})
	return o, nil
}

func (d *dobleDatos) ActualizarOrigen(_ context.Context, arg sqlc.ActualizarOrigenParams) (sqlc.SavedOrigin, error) {
	for i := range d.origenes {
		o := &d.origenes[i]
		if o.ID != arg.ID {
			continue
		}
		if arg.Sucursal.Valid && o.BranchID.Bytes != arg.Sucursal.Bytes {
			return sqlc.SavedOrigin{}, pgx.ErrNoRows
		}
		if arg.Name != nil {
			o.Name = *arg.Name
		}
		if arg.Address != nil {
			o.Address = *arg.Address
		}
		if arg.Lat != nil {
			o.Lat = *arg.Lat
		}
		if arg.Lng != nil {
			o.Lng = *arg.Lng
		}
		return sqlc.SavedOrigin{ID: o.ID, Name: o.Name, Address: o.Address, Lat: o.Lat,
			Lng: o.Lng, CreadoPor: o.CreadoPor, BranchID: o.BranchID}, nil
	}
	return sqlc.SavedOrigin{}, pgx.ErrNoRows
}

func (d *dobleDatos) BorrarOrigen(_ context.Context, arg sqlc.BorrarOrigenParams) (int64, error) {
	for i, o := range d.origenes {
		if o.ID != arg.ID {
			continue
		}
		if arg.Sucursal.Valid && o.BranchID.Bytes != arg.Sucursal.Bytes {
			return 0, nil
		}
		d.origenes = append(d.origenes[:i], d.origenes[i+1:]...)
		return 1, nil
	}
	return 0, nil
}

// conAccesos pone un Accesos de mentira y lo quita al acabar.
func conAccesos(t *testing.T, c ClienteAccesos) *accesosFalso {
	t.Helper()
	anterior := Accesos
	t.Cleanup(func() { Accesos = anterior })
	Accesos = c
	f, _ := c.(*accesosFalso)
	return f
}

// `activo` AUSENTE ES `true`, y el aparato lo lee igual.
//
// El contrato lo da por opcional y Accesos lo guarda con `@default(true)`. Un `bool` pelado
// de Go entendería lo contrario, y desde que `activo` filtra en `cotizar.ElegirAlmacen` eso
// es el 409 «no tiene ningún almacén con coordenadas» en las ocho sucursales a la vez,
// mientras el teléfono sigue armando rutas — porque `app/lib/nucleo/sincro/bajada.dart` lee
// `a['activo'] != false`, o sea ausente = activo.
//
// LO QUE ESTA PRUEBA NO ATA, y hay que saberlo: el lado de Dart. Si alguien cambia ese
// `!= false` por `== true`, esto sigue verde. Lo que sí está atado es la REGLA de selección
// (`docs/almacen-de-origen.casos.json`); esto es sólo cómo se lee el campo.
func TestActivoAusenteEsActivo(t *testing.T) {
	var a Almacen
	if err := json.Unmarshal([]byte(`{"nombre":"Central","latitud":20.0,"longitud":-75.8}`), &a); err != nil {
		t.Fatalf("no se entendió: %v", err)
	}
	if !a.Activo {
		t.Fatal("un almacén sin `activo` en el JSON salió de baja. El aparato lo lee como " +
			"ACTIVO (bajada.dart), así que la web contestaría 409 sobre las sucursales a " +
			"las que el teléfono sí les arma la ruta")
	}

	// Y un `false` explícito sigue siendo `false`: el defecto no puede comerse el dato.
	if err := json.Unmarshal([]byte(`{"nombre":"Viejo","activo":false}`), &a); err != nil {
		t.Fatalf("no se entendió: %v", err)
	}
	if a.Activo {
		t.Fatal("un almacén dado de baja a mano salió activo: el defecto se comió el dato")
	}
}

func almacenesDePrueba() *accesosFalso {
	return &accesosFalso{sucursales: []SucursalConAlmacenes{
		{Codigo: "STG", Nombre: "Santiago", Almacenes: []Almacen{
			{Nombre: "Central", Principal: true, Activo: true,
				Latitud: flotante(20.0), Longitud: flotante(-75.8)},
		}},
		{Codigo: "HOL", Nombre: "Holguín", Almacenes: []Almacen{
			{Nombre: "Nave 2", Activo: true, Latitud: flotante(20.88), Longitud: flotante(-76.26)},
		}},
	}}
}

// --------------------------------------------------------------------------- orígenes

// Un punto de partida es de su sucursal. Uno de Holguín colado en la lista de Santiago es
// una ruta que empieza a 200 km de donde debía, y eso no lo desmiente ninguna pantalla:
// sale un recorrido con números y todo.
func TestOrigenesNoSeVenLosDeOtraSucursal(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())
	w := pedirDeDatos(t, h, http.MethodGet, "/api/origins", logisticoDeSantiago(t), "", nil)

	var lista []OrigenSalida
	leerJSONDeDatos(t, w, &lista)
	if len(lista) != 1 || lista[0].ID != datOrigStg {
		t.Fatalf("Santiago vio orígenes que no son suyos: %s", w.Body.String())
	}
	if lista[0].Branch == nil || lista[0].Branch.Name != "Santiago" {
		t.Fatalf("falta el `branch: {id, name}` del contrato: %s", w.Body.String())
	}
}

// El `branchId` de la query sólo vale cuando NO hay alcance; con alcance no lo amplía.
func TestOrigenesElBranchIdDeLaQueryNoAmpliaElAlcance(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())
	w := pedirDeDatos(t, h, http.MethodGet, "/api/origins?branchId="+datSucHol.String(), logisticoDeSantiago(t), "", nil)

	var lista []OrigenSalida
	leerJSONDeDatos(t, w, &lista)
	if len(lista) != 1 || lista[0].ID != datOrigStg {
		t.Fatalf("con branchId se coló otra sucursal: %s", w.Body.String())
	}
}

// Los literales del contrato del alta, y EN ORDEN: primero qué falta y después qué no es
// un número. Al revés, a quien no manda `lat` le saldría «lat y lng deben ser números».
func TestOrigenesElAltaComprubaLosCamposConLosLiteralesDelContrato(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())

	w := pedirDeDatos(t, h, http.MethodPost, "/api/origins", logisticoDeSantiago(t), `{"name":"Patio"}`, nil)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if got := strings.TrimSpace(w.Body.String()); got != `{"error":"Faltan campos requeridos: name, address, lat, lng"}` {
		t.Fatalf("mensaje %q", got)
	}

	// Una coordenada como TEXTO se rechaza en vez de convertirse: lo que llega como texto
	// suele venir de un campo sin validar, y a veces trae una coma decimal.
	w = pedirDeDatos(t, h, http.MethodPost, "/api/origins", logisticoDeSantiago(t),
		`{"name":"Patio","address":"Calle 1","lat":"20,0","lng":-75.8}`, nil)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if got := strings.TrimSpace(w.Body.String()); got != `{"error":"lat y lng deben ser números"}` {
		t.Fatalf("mensaje %q", got)
	}
}

// El origen NACE en la sucursal del alcance, no en la que diga el cuerpo. Así nadie cuelga
// un punto de partida en la sucursal de otro mandando su id en la petición.
func TestOrigenesElAltaLoCuelgaDeLaSucursalDelAlcance(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())
	w := pedirDeDatos(t, h, http.MethodPost, "/api/origins", logisticoDeSantiago(t),
		`{"name":"Patio","address":"Calle 1","lat":20.0,"lng":-75.8,"branchId":"`+datSucHol.String()+`"}`, nil)
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var o OrigenSalida
	leerJSONDeDatos(t, w, &o)
	if o.BranchID == nil || *o.BranchID != datSucStg {
		t.Fatalf("el origen acabó en otra sucursal: %+v", o)
	}
	// Y queda constancia de quién lo puso. Eso NO filtra nada: sólo se apunta.
	if o.CreadoPor == nil || *o.CreadoPor != "p-stg" {
		t.Fatalf("no se apuntó quién lo creó: %+v", o)
	}
}

// Sin alcance —el Super Admin— sí se elige sucursal, pero tiene que existir.
func TestOrigenesUnaSucursalQueNoExisteEs403ConSuLiteral(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())
	fantasma := uuid.MustParse("99999999-9999-9999-9999-999999999999")

	w := pedirDeDatos(t, h, http.MethodPost, "/api/origins", superAdminDeDatos(t),
		`{"name":"Patio","address":"Calle 1","lat":20.0,"lng":-75.8,"branchId":"`+fantasma.String()+`"}`, nil)
	if w.Code != http.StatusForbidden {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if got := strings.TrimSpace(w.Body.String()); got != `{"error":"Sucursal no válida"}` {
		t.Fatalf("mensaje %q", got)
	}
}

// Corregir y borrar van acotados, y el que no toca es 404 —no 403—: «no es tuyo» y «no
// existe» tienen que verse igual desde fuera.
func TestOrigenesCorregirYBorrarVanAcotados(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())

	for _, caso := range []struct {
		metodo, ruta, cuerpo string
	}{
		{http.MethodPatch, "/api/origins/" + datOrigHol.String(), `{"name":"Mío ahora"}`},
		{http.MethodDelete, "/api/origins/" + datOrigHol.String(), ""},
	} {
		w := pedirDeDatos(t, h, caso.metodo, caso.ruta, logisticoDeSantiago(t), caso.cuerpo, nil)
		if w.Code != http.StatusNotFound {
			t.Fatalf("%s: código %d %s", caso.metodo, w.Code, w.Body.String())
		}
		if got := strings.TrimSpace(w.Body.String()); got != `{"error":"No encontrado"}` {
			t.Fatalf("%s: mensaje %q", caso.metodo, got)
		}
	}

	// El suyo sí.
	w := pedirDeDatos(t, h, http.MethodPatch, "/api/origins/"+datOrigStg.String(), logisticoDeSantiago(t),
		`{"name":"Almacén nuevo","lat":20.5}`, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var o OrigenSalida
	leerJSONDeDatos(t, w, &o)
	if o.Name != "Almacén nuevo" || o.Lat != 20.5 {
		t.Fatalf("no se corrigió: %+v", o)
	}
	// Y lo que no le mandaron sigue donde estaba.
	if o.Address != "x" {
		t.Fatalf("un PATCH del nombre borró la dirección: %+v", o)
	}

	w = pedirDeDatos(t, h, http.MethodDelete, "/api/origins/"+datOrigStg.String(), logisticoDeSantiago(t), "", nil)
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"success":true`) {
		t.Fatalf("%d %s", w.Code, w.Body.String())
	}
}

// La sucursal de un origen NO se cambia por un PATCH: sería la forma de saltarse la
// comprobación del alta y plantarlo en la sucursal de otro.
func TestOrigenesElPatchNoMueveElOrigenDeSucursal(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())
	w := pedirDeDatos(t, h, http.MethodPatch, "/api/origins/"+datOrigStg.String(), logisticoDeSantiago(t),
		`{"branchId":"`+datSucHol.String()+`"}`, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var o OrigenSalida
	leerJSONDeDatos(t, w, &o)
	if o.BranchID == nil || *o.BranchID != datSucStg {
		t.Fatalf("un PATCH movió el origen de sucursal: %+v", o)
	}
}

// --------------------------------------------------------------------------- almacenes

// Accesos devuelve las ocho sucursales porque no sabe nada de nuestro alcance: filtrarlas
// es cosa nuestra, y si no se hace, quien lleva una sucursal ve los almacenes de todas.
func TestAlmacenesSeFiltranPorLasSucursalesVisibles(t *testing.T) {
	conAccesos(t, almacenesDePrueba())
	h := montarDeDatos(t, datosDePrueba())

	w := pedirDeDatos(t, h, http.MethodGet, "/api/almacenes", logisticoDeSantiago(t), "", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var salida struct {
		Sucursales []SucursalConAlmacenes `json:"sucursales"`
	}
	leerJSONDeDatos(t, w, &salida)
	if len(salida.Sucursales) != 1 || salida.Sucursales[0].Codigo != "STG" {
		t.Fatalf("se colaron almacenes de otra sucursal: %s", w.Body.String())
	}

	// El Super Admin sí las ve todas.
	w = pedirDeDatos(t, h, http.MethodGet, "/api/almacenes", superAdminDeDatos(t), "", nil)
	leerJSONDeDatos(t, w, &salida)
	if len(salida.Sucursales) != 2 {
		t.Fatalf("el Super Admin tenía que verlas todas: %s", w.Body.String())
	}
}

// EL SUPER ADMIN MIRANDO UNA SUCURSAL SIGUE VIENDO LOS ALMACENES DE TODAS.
//
// Es el fallo del 26/09/2026, y es la diferencia entre «a cuáles puedo llegar» y «cuál
// estoy mirando». Esta ruta se acotaba con la sucursal del ALCANCE, que para quien ve las
// ocho sale de la cabecera `X-Sucursal-Id`: mirando Camagüey le volvía sólo el almacén de
// Camagüey. Y el aparato reemplaza su copia entera con lo que llega, así que se quedaba
// con ese uno; al cambiar arriba a Holguín el Tablero no encontraba el de `HOL` y ponía
// la pantalla en blanco diciendo que Holguín no tiene almacén. Lo tiene.
//
// LA PRUEBA DE ANTES NO LO CAZABA porque pedía SIN cabecera, que es justo el caso que
// funcionaba: sin cabecera el alcance ya era «todas». Una prueba que no manda lo que
// manda la aplicación no prueba lo que la aplicación hace.
func TestAlmacenesElSuperAdminMirandoUnaLasSigueViendoTodas(t *testing.T) {
	conAccesos(t, almacenesDePrueba())
	h := montarDeDatos(t, datosDePrueba())

	w := pedirDeDatos(t, h, http.MethodGet, "/api/almacenes", superAdminDeDatos(t), "",
		map[string]string{alcance.CabeceraSucursal: datSucHol.String()})
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var salida struct {
		Sucursales []SucursalConAlmacenes `json:"sucursales"`
	}
	leerJSONDeDatos(t, w, &salida)
	if len(salida.Sucursales) != 2 {
		t.Fatalf("mirando Holguín se quedó sin los demás almacenes, y al cambiar de "+
			"sucursal el Tablero acusaría en falso: %s", w.Body.String())
	}
}

// LA OTRA MITAD, y sin ella lo de arriba se «arregla» devolviéndolas siempre todas: quien
// pertenece a UNA sucursal no puede ver los almacenes de las otras ni poniendo la cabecera
// a mano. Es la regla 1 de la casa —el alcance sale de quién pregunta— y ya costó dinero:
// «un operador de Santiago vio los precios de La Habana».
func TestAlmacenesElDeUnaSucursalNoVeLasOtrasNiConLaCabecera(t *testing.T) {
	conAccesos(t, almacenesDePrueba())
	h := montarDeDatos(t, datosDePrueba())

	w := pedirDeDatos(t, h, http.MethodGet, "/api/almacenes", logisticoDeSantiago(t), "",
		map[string]string{alcance.CabeceraSucursal: datSucHol.String()})
	var salida struct {
		Sucursales []SucursalConAlmacenes `json:"sucursales"`
	}
	leerJSONDeDatos(t, w, &salida)
	if len(salida.Sucursales) != 1 || salida.Sucursales[0].Codigo != "STG" {
		t.Fatalf("Santiago se llevó almacenes de otra sucursal pidiéndolos por "+
			"cabecera: %s", w.Body.String())
	}
}

// Si Accesos no contesta es 502 y no 500: el que falla no somos nosotros, y el mensaje lo
// dice para que quien lo lea sepa dónde mirar.
func TestAlmacenesSiAccesosNoContestaEs502ConSuLiteral(t *testing.T) {
	conAccesos(t, &accesosFalso{fallo: errAccesosCaido})
	h := montarDeDatos(t, datosDePrueba())

	w := pedirDeDatos(t, h, http.MethodGet, "/api/almacenes", logisticoDeSantiago(t), "", nil)
	if w.Code != http.StatusBadGateway {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "No se pudieron traer los almacenes de Accesos: auth 503") {
		t.Fatalf("mensaje %s", w.Body.String())
	}
}

// Un cuerpo que no es `{ codigo, almacenes: [...] }` sale con UN solo mensaje, el del
// contrato: no parsea, falta el código o `almacenes` no es una lista, da igual cuál.
func TestAlmacenesElPutComprubaElCuerpoConElLiteralDelContrato(t *testing.T) {
	conAccesos(t, almacenesDePrueba())
	h := montarDeDatos(t, datosDePrueba())

	for _, cuerpo := range []string{`no es json`, `{}`, `{"codigo":"STG"}`, `{"codigo":"STG","almacenes":{}}`} {
		w := pedirDeDatos(t, h, http.MethodPut, "/api/almacenes", logisticoDeSantiago(t), cuerpo, nil)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("%q: código %d %s", cuerpo, w.Code, w.Body.String())
		}
		if got := strings.TrimSpace(w.Body.String()); got != `{"error":"Se espera { codigo, almacenes: [...] }"}` {
			t.Fatalf("%q: mensaje %q", cuerpo, got)
		}
	}
}

// Quien sólo ve una sucursal no toca los almacenes de otra pasando el código a mano. Y
// esto no es sólo ver de más: desde el almacén se mide lo que se le cobra al cliente, así
// que moverle el punto a otra sucursal le cambia el precio a todas sus entregas.
func TestAlmacenesNoSeGuardanLosDeOtraSucursal(t *testing.T) {
	falso := conAccesos(t, almacenesDePrueba())
	h := montarDeDatos(t, datosDePrueba())

	w := pedirDeDatos(t, h, http.MethodPut, "/api/almacenes", logisticoDeSantiago(t),
		`{"codigo":"HOL","almacenes":[]}`, nil)
	if w.Code != http.StatusForbidden {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if got := strings.TrimSpace(w.Body.String()); got != `{"error":"Sin acceso a esa sucursal"}` {
		t.Fatalf("mensaje %q", got)
	}
	if falso.guardado != nil {
		t.Fatalf("se mandó a Accesos un cambio que había que rechazar: %s", falso.guardado)
	}
}

// Un almacén sin coordenadas SE GUARDA —a veces se da de alta antes de tener el punto—
// pero se avisa: sin lat/lng los pedidos de esa sucursal se quedan sin cotizar y nada lo
// dice.
func TestAlmacenesAvisaDeLosQueNoTienenCoordenadas(t *testing.T) {
	falso := conAccesos(t, almacenesDePrueba())
	h := montarDeDatos(t, datosDePrueba())

	cuerpo := `{"codigo":"STG","almacenes":[{"nombre":"Central","latitud":20.0,"longitud":-75.8},{"nombre":"Patio nuevo"}]}`
	w := pedirDeDatos(t, h, http.MethodPut, "/api/almacenes", logisticoDeSantiago(t), cuerpo, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var salida map[string]any
	leerJSONDeDatos(t, w, &salida)
	if salida["aviso"] != "1 almacén(es) sin coordenadas: desde ésos no se puede medir el domicilio." {
		t.Fatalf("aviso %v", salida["aviso"])
	}
	if _, hay := salida["almacenes"]; !hay {
		t.Fatalf("se perdió lo que contestó Accesos: %s", w.Body.String())
	}
	// El cuerpo llega a Accesos TAL CUAL: aquí no se guarda nada ni se reescribe nada.
	if string(falso.guardado) != cuerpo {
		t.Fatalf("el cuerpo no llegó tal cual: %s", falso.guardado)
	}

	// Con todos puestos, el aviso es null: uno vacío en la pantalla se lee como que algo
	// pasó.
	w = pedirDeDatos(t, h, http.MethodPut, "/api/almacenes", logisticoDeSantiago(t),
		`{"codigo":"STG","almacenes":[{"nombre":"Central","latitud":20.0,"longitud":-75.8}]}`, nil)
	leerJSONDeDatos(t, w, &salida)
	if salida["aviso"] != nil {
		t.Fatalf("no había nada que avisar: %v", salida["aviso"])
	}
}

// Si Accesos rechaza el cambio, se dice que fue ÉL: un 500 nuestro manda a mirar el sitio
// equivocado.
func TestAlmacenesSiAccesosRechazaElCambioEs502ConSuLiteral(t *testing.T) {
	conAccesos(t, &accesosFalso{fallo: errAccesosCaido})
	h := montarDeDatos(t, datosDePrueba())

	w := pedirDeDatos(t, h, http.MethodPut, "/api/almacenes", logisticoDeSantiago(t),
		`{"codigo":"STG","almacenes":[]}`, nil)
	if w.Code != http.StatusBadGateway {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "Accesos no aceptó el cambio: auth 503") {
		t.Fatalf("mensaje %s", w.Body.String())
	}
}
