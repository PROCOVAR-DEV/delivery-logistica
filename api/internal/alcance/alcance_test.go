package alcance_test

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/store/sqlc"
)

// Las dos sucursales de las pruebas. Santiago es donde iba el piloto; Holguín es la de
// al lado, y la pregunta de todas estas pruebas es siempre la misma: ¿llega Santiago a
// los datos de Holguín?
var (
	stg = uuid.MustParse("11111111-1111-1111-1111-111111111111")
	hol = uuid.MustParse("22222222-2222-2222-2222-222222222222")
	// Una que YA NO ESTÁ. El caso de producción: el token dura siete días y lleva
	// dentro la sucursal que la persona tenía al entrar.
	fantasma = uuid.MustParse("99999999-9999-9999-9999-999999999999")
)

func base() *querierFalso {
	codStg, codHol := "STG", "HOL"
	return &querierFalso{
		sucursales: map[uuid.UUID]sqlc.ResolverSucursalRow{
			stg: {ID: stg, Name: "Santiago", ExternalID: &codStg},
			hol: {ID: hol, Name: "Holguín", ExternalID: &codHol},
		},
		vehiculos: []sqlc.ListarVehiculosRow{
			{ID: uuid.New(), Name: "Camión de Santiago", BranchID: pg(stg)},
			{ID: uuid.New(), Name: "Camión de Holguín", BranchID: pg(hol)},
			{ID: uuid.New(), Name: "Camión compartido"}, // sin sucursal: «de todas»
		},
	}
}

func pg(id uuid.UUID) pgtype.UUID { return pgtype.UUID{Bytes: [16]byte(id), Valid: true} }

// porteria monta el alcance sobre el doble y devuelve además lo que se escriba en el
// registro, que en este paquete es parte del comportamiento: el aviso de la sucursal que
// no existe es lo ÚNICO que delata el fallo.
func porteria(q *querierFalso) (*alcance.Porteria, *bytes.Buffer) {
	var buf bytes.Buffer
	reg := slog.New(slog.NewTextHandler(&buf, &slog.HandlerOptions{Level: slog.LevelDebug}))
	return alcance.NuevaPorteria(fuenteFalsa{q: q}, reg), &buf
}

func nombres(vs []sqlc.ListarVehiculosRow) []string {
	var salida []string
	for _, v := range vs {
		salida = append(salida, v.Name)
	}
	return salida
}

// ---------------------------------------------------------------------------
// LA PRUEBA QUE IMPORTA: un operador de una sucursal no llega a los datos de otra.
// ---------------------------------------------------------------------------

func TestOperadorNoVeLosDatosDeOtraSucursal(t *testing.T) {
	q := base()
	p, _ := porteria(q)

	u := &auth.Usuario{ID: "p-1", Email: "stg@procovar.cu", Rol: "OPERADOR", Sucursal: stg.String()}
	a, err := p.Resolver(context.Background(), u, "")
	if err != nil {
		t.Fatalf("resolver: %v", err)
	}
	if a.Todas() {
		t.Fatal("un operador con sucursal NO puede tener alcance de todas")
	}

	vs, err := a.ListarVehiculos(context.Background())
	if err != nil {
		t.Fatalf("listar: %v", err)
	}
	for _, v := range vs {
		if v.BranchID.Valid && v.BranchID.Bytes == [16]byte(hol) {
			t.Fatalf("Santiago está viendo un camión de Holguín: %v", nombres(vs))
		}
	}
	// Y el compartido sí tiene que verse: un camión sin sucursal es «de todas», y uno
	// que no sale en la lista de nadie es un camión que no se puede usar.
	if len(vs) != 2 {
		t.Fatalf("se esperaban el de Santiago y el compartido; salieron %v", nombres(vs))
	}
}

// La del usuario MANDA sobre la cabecera. Si fuera al revés, cualquiera vería cualquier
// sucursal cambiando una línea en el navegador: ahí se acaba la seguridad del sistema.
func TestLaSucursalDelUsuarioPisaLaCabecera(t *testing.T) {
	q := base()
	p, _ := porteria(q)

	u := &auth.Usuario{ID: "p-1", Rol: "OPERADOR", Sucursal: stg.String()}
	a, err := p.Resolver(context.Background(), u, hol.String()) // pide Holguín por cabecera
	if err != nil {
		t.Fatalf("resolver: %v", err)
	}
	if a.Sucursal() == nil || *a.Sucursal() != stg {
		t.Fatalf("el alcance tenía que seguir siendo Santiago, y es %v", a.Sucursal())
	}

	vs, _ := a.ListarVehiculos(context.Background())
	for _, v := range vs {
		if v.BranchID.Valid && v.BranchID.Bytes == [16]byte(hol) {
			t.Fatalf("la cabecera se saltó el alcance: %v", nombres(vs))
		}
	}
	if len(q.sucursalPedida) != 1 || q.sucursalPedida[0].Bytes != [16]byte(stg) {
		t.Fatalf("a la consulta le llegó %v, no Santiago", q.sucursalPedida)
	}
}

// Un administrador CON sucursal sigue viendo sólo la suya. Ser admin no ensancha el
// alcance: lo que lo ensancha es no pertenecer a ninguna.
func TestAdminConSucursalSigueAcotado(t *testing.T) {
	q := base()
	p, _ := porteria(q)

	u := &auth.Usuario{ID: "p-2", Rol: "ADMINISTRADOR", Sucursal: hol.String()}
	a, err := p.Resolver(context.Background(), u, "")
	if err != nil {
		t.Fatalf("resolver: %v", err)
	}
	if a.Todas() {
		t.Fatal("un administrador con sucursal no puede ver todas")
	}
}

// ---------------------------------------------------------------------------
// EL MODO DE FALLO VISTO EN PRODUCCIÓN: una sucursal que no existe NO acota a cero.
// ---------------------------------------------------------------------------

func TestSucursalInexistenteNoAcotaACeroYDejaAviso(t *testing.T) {
	q := base()
	p, registro := porteria(q)

	// QUIEN VE TODAS (SUPER ADMIN, DESARROLLADOR): una sucursal que ya no está se comporta
	// como «todas», con aviso. Es la mitad que se conserva de la regla vieja.
	u := &auth.Usuario{ID: "p-3", Email: "vieja@procovar.cu", Rol: "SUPER ADMIN", Sucursal: fantasma.String()}
	a, err := p.Resolver(context.Background(), u, "")
	if err != nil {
		t.Fatalf("resolver: %v", err)
	}
	if !a.Todas() {
		t.Fatal("una sucursal que no existe tiene que comportarse como «todas» para quien las ve todas, no acotar")
	}

	vs, err := a.ListarVehiculos(context.Background())
	if err != nil {
		t.Fatalf("listar: %v", err)
	}
	// LO QUE NO PUEDE PASAR: cero filas con un 200 y sin trazas. Desde dentro es
	// indistinguible de «todavía no hay nada», y con la lista de sucursales a cero
	// desaparece hasta el selector con el que se podría arreglar.
	if len(vs) != 3 {
		t.Fatalf("una sucursal inexistente acotó la lista a %d: %v", len(vs), nombres(vs))
	}
	if q.sucursalPedida[0].Valid {
		t.Fatalf("a la consulta le llegó una sucursal (%v) que no existe, en vez de NULL", q.sucursalPedida[0])
	}

	// Y el aviso, que es lo único que delata el problema.
	traza := registro.String()
	if !strings.Contains(traza, "[alcance] la sucursal "+fantasma.String()+" de vieja@procovar.cu no existe: se le enseñan todas") {
		t.Fatalf("falta el aviso en el registro; quedó: %q", traza)
	}
}

// LA PAREJA, Y LA QUE IMPORTA (08/10/2026): el mismo token con una sucursal que Reparto no
// resuelve, pero de un rol que NO ve todas, NO abre el alcance: 403, con el código en el
// texto y sin entregar un alcance junto al error. Hasta la 1.0.28 esto era «todas».
func TestSucursalInexistenteDeQuienNoVeTodasEsUn403QueNombraElCodigo(t *testing.T) {
	for _, rol := range []string{"ADMINISTRADOR", "GERENTE", "SUPERVISOR", "GESTOR", "OPERADOR", ""} {
		for _, pedida := range []string{fantasma.String(), "cmf3k2h9a000008l5abcd1234", "MOA", "PLS"} {
			q := base()
			p, registro := porteria(q)
			u := &auth.Usuario{ID: "p-3", Email: "moa@procovar.cu", Rol: rol, Sucursal: pedida}
			a, err := p.Resolver(context.Background(), u, "")
			if err == nil || a != nil {
				t.Fatalf("rol %q con la sucursal %q desconocida: tenía que ser error SIN alcance, y salió a=%v err=%v",
					rol, pedida, a, err)
			}
			if !errors.Is(err, alcance.ErrSinAlcance) {
				t.Fatalf("rol %q, %q: tiene que ser un ErrSinAlcance (el 403): %v", rol, pedida, err)
			}
			if !strings.Contains(err.Error(), "tu sucursal "+pedida+" no está dada de alta en Reparto") {
				t.Fatalf("rol %q: el mensaje tiene que nombrar el código %q; dice: %q", rol, pedida, err.Error())
			}
			if len(q.sucursalPedida) != 0 {
				t.Fatalf("no se podía haber consultado nada con ese alcance: %v", q.sucursalPedida)
			}
			// Y se deja constancia en el registro, como siempre que el alcance no cuadra.
			if !strings.Contains(registro.String(), "[alcance] la sucursal "+pedida) {
				t.Fatalf("falta la línea en el registro; quedó: %q", registro.String())
			}
		}
	}
}

func TestSucursalInexistentePorCabeceraTambienAvisa(t *testing.T) {
	q := base()
	p, registro := porteria(q)

	u := &auth.Usuario{ID: "p-4", Rol: "SUPER ADMIN"} // sin sucursal
	a, err := p.Resolver(context.Background(), u, "  "+fantasma.String()+"  ")
	if err != nil {
		t.Fatalf("resolver: %v", err)
	}
	if !a.Todas() {
		t.Fatal("tenía que pasar a todas")
	}
	if !strings.Contains(registro.String(), "[alcance] la sucursal "+fantasma.String()+" no existe: se pasa a todas") {
		t.Fatalf("falta el aviso; quedó: %q", registro.String())
	}
}

// Los ids viejos de delivery eran cuid, no uuid. Uno de ésos es el mismo caso que uno que
// ya no está: ni revienta ni acota a cero.
func TestIdQueNiSiquieraEsUnUuidSeTrataIgual(t *testing.T) {
	q := base()
	p, registro := porteria(q)

	// Quien lo ve todo: ni revienta ni acota a cero; todas y aviso.
	u := &auth.Usuario{ID: "p-5", Rol: "DESARROLLADOR", Sucursal: "cmf3k2h9a000008l5abcd1234"}
	a, err := p.Resolver(context.Background(), u, "")
	if err != nil {
		t.Fatalf("resolver: %v", err)
	}
	if !a.Todas() {
		t.Fatal("un id con formato viejo tiene que comportarse como «todas» para quien las ve todas")
	}
	if !strings.Contains(registro.String(), "no existe") {
		t.Fatal("falta el aviso del id viejo")
	}

	// Cualquier otro rol: 403 (la pareja está en la prueba de arriba, con los cuid dentro).
	_, err = p.Resolver(context.Background(),
		&auth.Usuario{ID: "p-5b", Rol: "ADMINISTRADOR", Sucursal: "cmf3k2h9a000008l5abcd1234"}, "")
	if !errors.Is(err, alcance.ErrSinAlcance) {
		t.Fatalf("un ADMINISTRADOR con un id viejo no puede abrirse a las ocho: %v", err)
	}
}

// Un fallo de la base NO abre el alcance. «No pude comprobarlo» no es «no existe»: si se
// abriera, medio segundo de Postgres caído enseñaría las ocho sucursales a un operador.
func TestFalloDeLaBaseNoAbreElAlcance(t *testing.T) {
	q := base()
	q.falloAlResolver = errBaseCaida
	p, _ := porteria(q)

	u := &auth.Usuario{ID: "p-6", Rol: "OPERADOR", Sucursal: stg.String()}
	a, err := p.Resolver(context.Background(), u, "")
	if err == nil {
		t.Fatalf("un fallo de la base tiene que ser un 500, y devolvió alcance todas=%v", a.Todas())
	}
}

// ---------------------------------------------------------------------------
// Super Admin
// ---------------------------------------------------------------------------

func TestSuperAdminSinCabeceraVeTodas(t *testing.T) {
	q := base()
	p, _ := porteria(q)

	a, err := p.Resolver(context.Background(), &auth.Usuario{ID: "p-7", Rol: "SUPER ADMIN"}, "")
	if err != nil {
		t.Fatalf("resolver: %v", err)
	}
	if !a.Todas() {
		t.Fatal("quien no pertenece a ninguna sucursal las ve todas")
	}
	vs, _ := a.ListarVehiculos(context.Background())
	if len(vs) != 3 {
		t.Fatalf("tenía que ver los tres camiones; vio %v", nombres(vs))
	}
}

func TestSuperAdminEligeSucursalPorCabecera(t *testing.T) {
	q := base()
	p, _ := porteria(q)

	a, err := p.Resolver(context.Background(), &auth.Usuario{ID: "p-8", Rol: "SUPER ADMIN"}, hol.String())
	if err != nil {
		t.Fatalf("resolver: %v", err)
	}
	if a.Sucursal() == nil || *a.Sucursal() != hol {
		t.Fatalf("tenía que quedarse en Holguín, y quedó en %v", a.Sucursal())
	}
	if a.Codigo() == nil || *a.Codigo() != "HOL" {
		t.Fatalf("el código de la sucursal tiene que venir resuelto (clientes y catálogo se acotan por código); vino %v", a.Codigo())
	}
	vs, _ := a.ListarVehiculos(context.Background())
	if len(vs) != 2 { // el de Holguín y el compartido
		t.Fatalf("vio %v", nombres(vs))
	}
}

// LA ELECCIÓN NO SE PUEDE COMER LA LISTA CON LA QUE SE ELIGE. Si la lista de sucursales
// se acotara por la elegida, elegir una devolvería una sola y el selector se volvería una
// etiqueta fija: no habría forma de volver a cambiar.
func TestLaListaDeSucursalesNoSeAcotaPorLaElegida(t *testing.T) {
	q := base()
	p, _ := porteria(q)

	a, err := p.Resolver(context.Background(), &auth.Usuario{ID: "p-9", Rol: "SUPER ADMIN"}, stg.String())
	if err != nil {
		t.Fatalf("resolver: %v", err)
	}

	lista, err := a.ListarSucursalesVisibles(context.Background())
	if err != nil {
		t.Fatalf("listar sucursales: %v", err)
	}
	if len(lista) != 2 {
		t.Fatalf("el Super Admin tiene que seguir viendo las dos aunque esté mirando una; vio %d", len(lista))
	}
	if q.personaPedida[0].Valid {
		t.Fatal("a la lista de sucursales le llegó la elegida por cabecera: eso mata el selector")
	}
	// Mientras tanto, el resto de consultas sí van acotadas a la elegida.
	if _, err := a.ListarVehiculos(context.Background()); err != nil {
		t.Fatalf("listar vehículos: %v", err)
	}
	if !q.sucursalPedida[0].Valid || q.sucursalPedida[0].Bytes != [16]byte(stg) {
		t.Fatal("el resto de consultas sí tienen que ir acotadas a la elegida")
	}
}

// A quien pertenece a una sucursal, la lista le devuelve la suya y sólo la suya.
func TestLaListaDeSucursalesDeUnOperadorEsLaSuya(t *testing.T) {
	q := base()
	p, _ := porteria(q)

	a, err := p.Resolver(context.Background(), &auth.Usuario{ID: "p-10", Rol: "OPERADOR", Sucursal: stg.String()}, hol.String())
	if err != nil {
		t.Fatalf("resolver: %v", err)
	}
	lista, err := a.ListarSucursalesVisibles(context.Background())
	if err != nil {
		t.Fatalf("listar: %v", err)
	}
	if len(lista) != 1 || lista[0].ID != stg {
		t.Fatalf("tenía que ver sólo Santiago; vio %d", len(lista))
	}
}

// ---------------------------------------------------------------------------
// El actor deja constancia, NO filtra
// ---------------------------------------------------------------------------
//
// Éste es el fallo de delivery: filtraba por «quien lo creó». Como las ocho sucursales
// las dio de alta el Super Admin, los 3.528 pedidos importados quedaron a su nombre y los
// compañeros de Holguín no veían lo de Holguín.

func TestElActorSoloDejaConstancia(t *testing.T) {
	q := base()
	p, _ := porteria(q)

	a, err := p.Resolver(context.Background(), &auth.Usuario{ID: "persona-42", Rol: "SUPER ADMIN"}, "")
	if err != nil {
		t.Fatalf("resolver: %v", err)
	}
	if _, err := a.CrearSucursal(context.Background(), sqlc.CrearSucursalParams{Name: "Nueva"}); err != nil {
		t.Fatalf("crear: %v", err)
	}
	if q.sucursalCreadaPor == nil || *q.sucursalCreadaPor != "persona-42" {
		t.Fatalf("no quedó constancia de quién la creó: %v", q.sucursalCreadaPor)
	}
	// Y ninguna consulta de lectura recibió al actor: si algún día aparece un
	// `WHERE creado_por = actor`, es ese fallo otra vez.
	if _, err := a.ListarVehiculos(context.Background()); err != nil {
		t.Fatalf("listar: %v", err)
	}
	if q.sucursalPedida[0].Valid {
		t.Fatal("el alcance del Super Admin tiene que ser NULL, no depender de quién es")
	}
}

// Sin persona no hay alcance que resolver: llegar ahí es un fallo de montaje y tiene que
// doler, no devolver un alcance de «todas» por descuido.
func TestSinPersonaNoHayAlcance(t *testing.T) {
	q := base()
	p, _ := porteria(q)
	if _, err := p.Resolver(context.Background(), nil, ""); err == nil {
		t.Fatal("resolver sin persona tenía que fallar")
	}
}

// El alcance se hereda dentro de la transacción. Si no, la mitad de una operación de dos
// escrituras iría sin acotar.
func TestLaTransaccionHeredaElAlcance(t *testing.T) {
	q := base()
	p, _ := porteria(q)

	a, err := p.Resolver(context.Background(), &auth.Usuario{ID: "p-11", Rol: "OPERADOR", Sucursal: stg.String()}, "")
	if err != nil {
		t.Fatalf("resolver: %v", err)
	}
	err = a.EnTx(context.Background(), func(tx *alcance.Acotado) error {
		_, err := tx.ListarVehiculos(context.Background())
		return err
	})
	if err != nil {
		t.Fatalf("en tx: %v", err)
	}
	if !q.sucursalPedida[0].Valid || q.sucursalPedida[0].Bytes != [16]byte(stg) {
		t.Fatalf("dentro de la transacción se perdió el alcance: %v", q.sucursalPedida)
	}
}

// ---------------------------------------------------------------------------
// EL TOKEN DE ACCESOS TRAE EL CÓDIGO, NO EL UUID — 24/09/2026
//
// Las pruebas de arriba meten un `uuid` en `Usuario.Sucursal` porque eso es lo que el
// código suponía. Lo que llega de verdad es el CÓDIGO: Accesos firma `sucursal: "CAM"`
// tanto en el token de la APK y del escritorio (`apk-tokens.ts`) como en el de la web
// (`auth_web.go`). Con `uuid.Parse("CAM")` fallando, el alcance se iba al «no existe ->
// todas» y un ADMINISTRADOR de Camagüey veía las tres sucursales de la base local —46
// pedidos en vez de sus 19—, con 200 y sin un error en ningún sitio.
//
// Van EN PAREJA a propósito: una que acota cuando el código es bueno, y otra que NO
// acota —y avisa— cuando no lo es. Sin la segunda, «devolver siempre la primera
// sucursal» pasaría la primera.
// ---------------------------------------------------------------------------

func TestElCodigoDeSucursalDeAccesosAcota(t *testing.T) {
	q := base()
	p, registro := porteria(q)

	// Tal cual lo firma Accesos: el código, no el uuid.
	u := &auth.Usuario{ID: "p-20", Email: "stg@procovar.cu", Rol: "ADMINISTRADOR", Sucursal: "STG"}
	a, err := p.Resolver(context.Background(), u, "")
	if err != nil {
		t.Fatalf("resolver: %v", err)
	}
	if a.Todas() {
		t.Fatal("un ADMINISTRADOR con su código de sucursal NO puede ver las ocho: es la regla 1 de la casa")
	}

	vs, err := a.ListarVehiculos(context.Background())
	if err != nil {
		t.Fatalf("listar: %v", err)
	}
	// El de Santiago y el compartido. El de Holguín NO.
	for _, n := range nombres(vs) {
		if strings.Contains(n, "Holguín") {
			t.Fatalf("Santiago llegó a un vehículo de Holguín: %v", nombres(vs))
		}
	}
	if len(vs) != 2 {
		t.Fatalf("esperaba 2 vehículos (el suyo y el compartido), salieron %d: %v", len(vs), nombres(vs))
	}
	// Y la consulta tiene que haber recibido el UUID de Santiago, no un NULL ni otro.
	if !q.sucursalPedida[0].Valid || uuid.UUID(q.sucursalPedida[0].Bytes) != stg {
		t.Fatalf("a la consulta le llegó %v, y tenía que llegarle %s", q.sucursalPedida[0], stg)
	}
	if strings.Contains(registro.String(), "no existe") {
		t.Fatalf("un código bueno no puede dejar el aviso de «no existe»: %q", registro.String())
	}
}

func TestUnCodigoQueNoEsDeNadieAvisaYNoAcotaACero(t *testing.T) {
	q := base()
	p, registro := porteria(q)

	u := &auth.Usuario{ID: "p-21", Email: "nadie@procovar.cu", Rol: "SUPER ADMIN", Sucursal: "XXX"}
	a, err := p.Resolver(context.Background(), u, "")
	if err != nil {
		t.Fatalf("resolver: %v", err)
	}
	if !a.Todas() {
		t.Fatal("un código desconocido se trata, para quien las ve todas, como una sucursal que ya no está: todas y aviso, nunca cero")
	}
	if !strings.Contains(registro.String(), "[alcance] la sucursal XXX de nadie@procovar.cu no existe: se le enseñan todas") {
		t.Fatalf("falta el aviso; quedó: %q", registro.String())
	}
}

// La pareja de la de arriba, con el caso real: Accesos conoce `MOA` y Reparto no.
func TestUnCodigoQueRepartoNoConoceNoAbreLasOchoAUnOperador(t *testing.T) {
	q := base()
	p, _ := porteria(q)

	u := &auth.Usuario{ID: "p-21b", Email: "moa@procovar.cu", Rol: "OPERADOR", Sucursal: "MOA"}
	a, err := p.Resolver(context.Background(), u, "")
	if !errors.Is(err, alcance.ErrSinAlcance) || a != nil {
		t.Fatalf("un OPERADOR de MOA (que Reparto no conoce) no puede ver nada: a=%v err=%v", a, err)
	}
	if got := err.Error(); got != "tu sucursal MOA no está dada de alta en Reparto: pide en la oficina que la den de alta" {
		t.Fatalf("el mensaje cambió: %q", got)
	}
	// Y el texto del otro 403 NO se tocó: la app y el canal de eventos lo comparan.
	if !strings.Contains(alcance.ErrSinAlcance.Error(), "no está dada de alta en ninguna sucursal") {
		t.Fatalf("el literal de ErrSinAlcance es compartido y no se cambia: %q", alcance.ErrSinAlcance.Error())
	}
}

// ---------------------------------------------------------------------------
// LA CABECERA SÓLO LA LEE QUIEN PUEDE ELEGIR — 08/10/2026
// ---------------------------------------------------------------------------

// Sin sucursal y sin un rol que vea todas, ninguna cabecera lo arregla: ni basura (que
// antes caía en «no existe -> todas»), ni un id real (que antes lo dejaba ver esa sucursal).
func TestLaCabeceraNoLeAbreNadaAQuienNoTieneSucursalNiVeTodas(t *testing.T) {
	for _, rol := range []string{"OPERADOR", "ADMINISTRADOR", "GERENTE", "SUPERVISOR", "GESTOR", ""} {
		for _, cab := range []string{"basura", fantasma.String(), stg.String(), "HOL", "  "} {
			q := base()
			p, _ := porteria(q)
			a, err := p.Resolver(context.Background(), &auth.Usuario{ID: "x", Rol: rol}, cab)
			if err != alcance.ErrSinAlcance || a != nil {
				t.Fatalf("rol %q con la cabecera %q: tenía que ser ErrSinAlcance a secas, y salió a=%v err=%v",
					rol, cab, a, err)
			}
			if len(q.sucursalPedida) != 0 {
				t.Fatalf("no se podía haber consultado nada: %v", q.sucursalPedida)
			}
		}
	}
}

// La pareja: quien SÍ puede elegir sigue eligiendo (id o código), y basura sigue siendo
// «todas con aviso» para él.
func TestLaCabeceraSigueValiendoParaQuienVeTodas(t *testing.T) {
	for _, rol := range []string{"SUPER ADMIN", "DESARROLLADOR"} {
		q := base()
		p, registro := porteria(q)
		a, err := p.Resolver(context.Background(), &auth.Usuario{ID: "s", Rol: rol}, hol.String())
		if err != nil || a.Sucursal() == nil || *a.Sucursal() != hol {
			t.Fatalf("%s tenía que poder elegir Holguín: a=%v err=%v", rol, a, err)
		}
		a, err = p.Resolver(context.Background(), &auth.Usuario{ID: "s", Rol: rol}, "basura")
		if err != nil || !a.Todas() {
			t.Fatalf("%s con una cabecera que no existe: todas y aviso, no error: a=%v err=%v", rol, a, err)
		}
		if !strings.Contains(registro.String(), "[alcance] la sucursal basura no existe") {
			t.Fatalf("falta el aviso: %q", registro.String())
		}
	}
}

// Y quien tiene sucursal VÁLIDA sigue acotado a ella, mande la cabecera lo que mande (la
// pareja de las dos de arriba: el cierre del hueco no puede dejar fuera a quien está bien).
func TestUnOperadorConSuSucursalValidaSigueAcotado(t *testing.T) {
	for _, cab := range []string{"", "basura", hol.String(), "HOL"} {
		q := base()
		p, _ := porteria(q)
		a, err := p.Resolver(context.Background(),
			&auth.Usuario{ID: "p-ok", Rol: "OPERADOR", Sucursal: "STG"}, cab)
		if err != nil {
			t.Fatalf("cabecera %q: %v", cab, err)
		}
		if a.Todas() || a.Sucursal() == nil || *a.Sucursal() != stg {
			t.Fatalf("cabecera %q: tenía que seguir acotado a Santiago, y es %v", cab, a.Sucursal())
		}
	}
}

// «No pude comprobarlo» no es «no existe», también por este camino. Si un fallo de la
// base al buscar el código abriera el alcance, medio segundo de Postgres caído enseñaría
// las ocho sucursales a un operador — que es justo lo que la prueba hermana del uuid ya
// impide.
func TestFalloDeLaBaseAlBuscarElCodigoNoAbreElAlcance(t *testing.T) {
	q := base()
	q.falloAlBuscarPorCodigo = errBaseCaida
	p, _ := porteria(q)

	u := &auth.Usuario{ID: "p-22", Rol: "OPERADOR", Sucursal: "STG"}
	a, err := p.Resolver(context.Background(), u, "")
	if err == nil {
		t.Fatalf("un fallo de la base tiene que ser un 500, y devolvió alcance todas=%v", a.Todas())
	}
}

// El Super Admin que elige sucursal ARRIBA manda un código por la cabecera, no un uuid:
// es el mismo selector que pinta `/api/branches`, y lo que la aplicación guarda es lo
// que Accesos le dio. Si sólo se resolviera el código de la persona, elegir Holguín
// seguiría enseñándolo todo.
func TestElSuperAdminTambienPuedeElegirPorCodigo(t *testing.T) {
	q := base()
	p, _ := porteria(q)

	u := &auth.Usuario{ID: "p-23", Rol: "SUPER ADMIN"} // sin sucursal propia
	a, err := p.Resolver(context.Background(), u, "HOL")
	if err != nil {
		t.Fatalf("resolver: %v", err)
	}
	if a.Todas() {
		t.Fatal("eligió Holguín y siguió viéndolas todas")
	}
	vs, err := a.ListarVehiculos(context.Background())
	if err != nil {
		t.Fatalf("listar: %v", err)
	}
	for _, n := range nombres(vs) {
		if strings.Contains(n, "Santiago") {
			t.Fatalf("eligiendo Holguín salió un camión de Santiago: %v", nombres(vs))
		}
	}
}
