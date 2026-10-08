package api

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// QUIÉN VE LA PANTALLA DEL WEBHOOK: DOS ROLES DE LOS SIETE.
//
// Jose, 26/09/2026, por este orden: «esto es para administración, esta vista no la puede
// ver nadie», luego «que sólo lo pueda ver yo, eso no lo puede ver más nadie, sólo yo, el
// desarrollador» —y se cerró a `DESARROLLADOR` a secas— y esa misma tarde, al ver que su
// propia cuenta es `SUPER ADMIN` por defecto y se quedaba fuera: **«ponle para super admin
// también, de todas formas yo limpiaré eso después»**.
//
// Así que son dos, y los otros CINCO siguen fuera. Eso último es lo que esta prueba
// defiende, porque es lo que se pierde por descuido: basta con que alguien escriba
// `ExigirAdmin` —lo primero que se puso aquí— para que entren también ADMINISTRADOR, que
// administra UNA sucursal, y el `admin` heredado de la web vieja. Ninguno de los dos tiene
// nada que hacer en una pantalla de colas, reintentos, códigos HTTP y motivos de error de
// otro sistema.
//
// LA FORMA: los SIETE roles de la casa, uno a uno, y no «un admin sí y un operador no». Con
// dos casos, cambiar `PuedeMirarElCanal` por `EsAdmin` sale verde y la pantalla se le abre a
// medio Procovar sin que nada falle.
//
// Y CUANDO JOSE LO LIMPIE —quitar `rolSuperAdmin` de `PuedeMirarElCanal`—, esta prueba
// falla en el caso `SUPER ADMIN` y basta con moverlo de una lista a la otra. Que falle es
// justo lo que se quiere: dice dónde está escrito el permiso.

func TestQuienVeElEstadoDelWebhook(t *testing.T) {
	// Los siete de `procovar/CLAUDE.md`, escritos EXACTAMENTE así: PEDIDO los compara
	// como texto y aquí también.
	entran := []string{"DESARROLLADOR", "SUPER ADMIN"}
	seQuedanFuera := []string{
		"GERENTE", "ADMINISTRADOR", "SUPERVISOR", "GESTOR", "OPERADOR", "LOGISTICO",
	}

	h, _ := montarRutasDelWebhook(t)

	for _, rol := range seQuedanFuera {
		t.Run("fuera/"+rol, func(t *testing.T) {
			w := llamarRutas(t, h, http.MethodGet, "/api/admin/webhook",
				tokenConRol(t, rol), "")
			if w.Code != http.StatusForbidden {
				t.Fatalf(
					"%s entró en la pantalla del webhook: %d %s",
					rol, w.Code, w.Body.String(),
				)
			}
		})
	}

	// LA OTRA MITAD, y no sobra: sin ella, «los cinco no entran» se cumple con la ruta
	// cerrada a todo el mundo, y Jose se queda mirando un 403 en su propia pantalla —que
	// es exactamente lo que pasó y por lo que ahora son dos roles y no uno.
	for _, rol := range entran {
		t.Run("entra/"+rol, func(t *testing.T) {
			w := llamarRutas(t, h, http.MethodGet, "/api/admin/webhook",
				tokenConRol(t, rol), "")
			if w.Code != http.StatusOK {
				t.Fatalf(
					"%s NO pudo entrar, y tiene que poder: %d %s",
					rol, w.Code, w.Body.String(),
				)
			}
		})
	}
}

// Y SIN SESIÓN, NI ESO. Va aparte porque es otro middleware el que lo para —`Exigir`, no
// `ExigirQuienMiraElCanal`— y por tanto otra cosa que se puede romper por su cuenta.
func TestSinSesionElEstadoDelWebhookNoSeSirve(t *testing.T) {
	h, _ := montarRutasDelWebhook(t)

	w := llamarRutas(t, h, http.MethodGet, "/api/admin/webhook", "", "")

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("se sirvió sin sesión: %d %s", w.Code, w.Body.String())
	}
}

// --------------------------------------------------------------------------- el montaje

// montarRutasDelWebhook monta SÓLO las del espejo, que es donde vive la del webhook.
//
// Se monta con los mismos middlewares que en producción —`sesion` y `admin` armados
// igual—, porque lo que se prueba es justo cuál de los dos acaba delante de esta ruta.
func montarRutasDelWebhook(t *testing.T) (http.Handler, *Servidor) {
	return montarRutasDelWebhookCon(t, &dobleDelWebhook{})
}

// montarRutasDelWebhookCon es lo mismo con el doble puesto desde fuera, para las pruebas que
// tienen que MIRAR lo que se le pidió a la base y no sólo lo que salió por el JSON.
func montarRutasDelWebhookCon(t *testing.T, q *dobleDelWebhook) (http.Handler, *Servidor) {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoDeRutas)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	reg := slog.New(slog.DiscardHandler)
	porteria := alcance.NuevaPorteria(fuenteDelWebhook{q: q}, reg)
	verif := auth.NuevoVerificador([]byte(secretoDeRutas))
	s := NuevoServidor(cfg, reg, porteria, verif, func(context.Context) error { return nil })

	rt := httpx.NuevoRouter(httpx.IDDePeticion, httpx.ConRegistro(reg),
		httpx.RecuperarPanico, httpx.SinCache)
	sesion := []httpx.Medio{verif.Exigir, porteria.Exigir}
	admin := []httpx.Medio{verif.Exigir, auth.ExigirAdmin, porteria.Exigir}
	s.rutasEspejo(rt, sesion, admin)
	return rt.Handler(), s
}

func tokenConRol(t *testing.T, rol string) string {
	t.Helper()
	// SIN SUCURSAL a propósito: lo que se prueba es el ROL, y darle una metería además el
	// alcance en la ecuación. Los cinco roles de una sola sucursal se quedan fuera por
	// `ErrSinAlcance` antes de llegar al rol… así que se les da la suya, y a los dos que
	// ven las ocho, ninguna.
	carga := map[string]any{"sub": "p-" + rol, "role": rol}
	if rol != "SUPER ADMIN" && rol != "DESARROLLADOR" {
		carga["branchId"] = stgDeRutas.String()
	}
	return tokenDeRutas(t, carga)
}

type fuenteDelWebhook struct{ q sqlc.Querier }

func (f fuenteDelWebhook) Consultas() sqlc.Querier { return f.q }
func (f fuenteDelWebhook) EnTx(ctx context.Context, fn func(sqlc.Querier) error) error {
	return fn(f.q)
}

// dobleDelWebhook contesta lo justo para que la pantalla se pinte: lo que se prueba aquí
// es quién entra, no qué ve.
type dobleDelWebhook struct {
	sqlc.Querier

	// Lo que se vio pasar a la consulta de almacenes sin medir. ES LO QUE SE COMPRUEBA en
	// `TestLaListaDeAlmacenesSinMedirVaAcotada`: qué sucursales se le pidieron.
	sucursalesPedidas [][]string
	topePedido        int32
}

func (d *dobleDelWebhook) ResumenDelWebhook(context.Context) (sqlc.ResumenDelWebhookRow, error) {
	return sqlc.ResumenDelWebhookRow{}, nil
}

func (d *dobleDelWebhook) ListarEnviosDelWebhook(context.Context, int32) ([]sqlc.EnviosDelWebhook, error) {
	return nil, nil
}

func (d *dobleDelWebhook) ListarRecepcionesDelWebhook(context.Context, int32) ([]sqlc.RecepcionesDelWebhook, error) {
	return nil, nil
}

func (d *dobleDelWebhook) ListarAvisosAPedido(context.Context, sqlc.ListarAvisosAPedidoParams) ([]sqlc.ListarAvisosAPedidoRow, error) {
	return nil, nil
}

func (d *dobleDelWebhook) ResolverSucursal(context.Context, uuid.UUID) (sqlc.ResolverSucursalRow, error) {
	return sqlc.ResolverSucursalRow{}, pgx.ErrNoRows
}

// LOS ALMACENES DESDE LOS QUE NO SE MIDIÓ, la cuarta lista de esta pantalla (26/09/2026).
//
// Se devuelven DOS filas y no ninguna a propósito: `estadoDelWebhook` pide `tope + 1` para
// saber si el tope se comió algo (`CLAUDE.md` §3), y con una lista vacía ese camino no se
// recorre nunca. La que comprueba el corte de verdad es
// `TestLaListaDeAlmacenesSinMedirDiceSiSeTruncó`.
func (d *dobleDelWebhook) AlmacenesDelPedidoSinMedir(
	_ context.Context, arg sqlc.AlmacenesDelPedidoSinMedirParams,
) ([]sqlc.AlmacenesDelPedidoSinMedirRow, error) {
	d.sucursalesPedidas = append(d.sucursalesPedidas, arg.Sucursales)
	d.topePedido = arg.Tope
	stg, motivo, cod, nom := "STG", "almacen-no-dado-de-alta", "28", "PTO MONEDERO"
	return []sqlc.AlmacenesDelPedidoSinMedirRow{
		{SucursalCodigo: &stg, Motivo: &motivo, Codigo: &cod, Nombre: &nom, Cuantos: 11},
		{SucursalCodigo: &stg, Motivo: &motivo, Codigo: &cod, Nombre: &nom, Cuantos: 1},
	}, nil
}

func (d *dobleDelWebhook) CodigosDeSucursalesVisibles(
	context.Context, pgtype.UUID,
) ([]sqlc.CodigosDeSucursalesVisiblesRow, error) {
	c := "STG"
	return []sqlc.CodigosDeSucursalesVisiblesRow{{ExternalID: &c}}, nil
}

// ---------------------------------------------------------------------------
// La lista de «no se midió desde su almacén»
// ---------------------------------------------------------------------------

// PIDE UN TOPE Y COMPRUEBA SI LO ALCANZÓ (`CLAUDE.md` §3).
//
// Es la regla que este proyecto ha cazado tres veces en un día, y aquí está en el peor sitio
// posible: la lista va ordenada por CUENTA DESCENDENTE, así que lo que el tope se come son los
// almacenes de uno o dos pedidos — precisamente el que acaba de aparecer y hay que cazar antes
// de que sean mil. Una lista cuyo único trabajo es que no falte ninguno puede faltarle alguno,
// y en silencio: eso no es una lista incompleta, es la regla de «nada se descarta» dándose la
// vuelta.
//
// Se hace con la FILA DE MÁS: se pide `tope + 1`, se corta a `tope` y si volvió la de más se
// dice. Es el molde de `tablero.go`.
func TestLaListaDeAlmacenesSinMedirDiceSiSeTrunco(t *testing.T) {
	// El doble devuelve DOS filas. Con `?tope=1` la segunda no cabe y hay que decirlo; con
	// `?tope=2` caben las dos y NO hay que decirlo. La pareja completa: un `truncado` que sale
	// siempre no informa de nada, igual que uno que no sale nunca.
	casos := []struct {
		tope     string
		quiere   int
		truncado bool
		porQue   string
	}{
		{tope: "1", quiere: 1, truncado: true,
			porQue: "sin esto, el almacén que aparece hoy con un pedido se cae por debajo " +
				"del corte y nadie lo echa en falta"},
		{tope: "2", quiere: 2, truncado: false,
			porQue: "un aviso que sale siempre deja de leerse, y entonces tampoco se lee el " +
				"día que importa"},
	}
	for _, c := range casos {
		t.Run("tope="+c.tope, func(t *testing.T) {
			d := &dobleDelWebhook{}
			h, _ := montarRutasDelWebhookCon(t, d)
			w := llamarRutas(t, h, http.MethodGet, "/api/admin/webhook?tope="+c.tope,
				tokenConRol(t, "DESARROLLADOR"), "")
			if w.Code != http.StatusOK {
				t.Fatalf("contestó %d: %s", w.Code, w.Body.String())
			}

			var salida EstadoDelWebhookSalida
			if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
				t.Fatalf("la respuesta no se entiende: %v — %s", err, w.Body.String())
			}
			if len(salida.SinMedir) != c.quiere {
				t.Errorf("salieron %d filas y el tope era %s: se esperaban %d",
					len(salida.SinMedir), c.tope, c.quiere)
			}
			if salida.SinMedirTruncado != c.truncado {
				t.Errorf("sinMedirTruncado = %v, se esperaba %v\n  por qué importa: %s",
					salida.SinMedirTruncado, c.truncado, c.porQue)
			}
			// Y LA FILA DE MÁS SE PIDE DE VERDAD. Sin esto, «truncado» sería una sospecha:
			// con el tope justo nunca se sabría si había otra.
			if d.topePedido != int32(c.quiere)+1 {
				t.Errorf("a la consulta se le pidió tope=%d y tenía que pedir %d (una fila "+
					"de más, que es lo que convierte «truncado» en un dato)",
					d.topePedido, c.quiere+1)
			}
		})
	}
}

// QUIEN MIRA ESTA PANTALLA VE LAS OCHO SUCURSALES, y eso es a propósito.
//
// Un almacén sin dar de alta es un problema de la casa y no de una sucursal: quien lo arregla
// necesita ver las ocho para no dejarse ninguna. Y la ruta ya está cerrada a los dos únicos
// roles que ven las ocho —`DESARROLLADOR` y `SUPER ADMIN`, lo fija
// `TestQuienVeElEstadoDelWebhook`—, así que «todas» aquí no es una fuga: es lo mismo que ya
// puede ver quien entra.
//
// LO QUE ESTA PRUEBA **NO** CUBRE, Y HAY QUE SABERLO: el manejador lleva además una rama que
// acota por `CodigosDeSucursalesVisibles` cuando quien pregunta NO ve las ocho. Hoy esa rama
// **no se puede alcanzar por esta ruta**, porque los cinco roles de una sola sucursal reciben
// 403 antes de llegar. Está puesta a propósito y no se quita: el día que Jose «limpie eso»
// —sus palabras al abrirla a `SUPER ADMIN`— y la pantalla se abra a un `ADMINISTRADOR`, que es
// de UNA sucursal, sin esa rama estaría enseñándole Santiago al de Camagüey. Es la regla 1 de
// la casa, la que en delivery dejó a un operador de Santiago viendo los precios de La Habana.
// Mientras la ruta siga cerrada a dos roles, esa rama es una guarda sin prueba: queda dicho
// aquí en vez de fingir que se comprueba.
func TestQuienMiraLosAlmacenesSinMedirVeLasOcho(t *testing.T) {
	for _, rol := range []string{"DESARROLLADOR", "SUPER ADMIN"} {
		t.Run(rol, func(t *testing.T) {
			d := &dobleDelWebhook{}
			h, _ := montarRutasDelWebhookCon(t, d)

			w := llamarRutas(t, h, http.MethodGet, "/api/admin/webhook", tokenConRol(t, rol), "")
			if w.Code != http.StatusOK {
				t.Fatalf("%s no pudo entrar: %d %s", rol, w.Code, w.Body.String())
			}
			if len(d.sucursalesPedidas) != 1 {
				t.Fatalf("se consultó %d veces y tenía que ser una", len(d.sucursalesPedidas))
			}
			// `nil` es «todas» en la consulta. Una lista vacía sería «ninguna», y entonces la
			// pantalla de administración saldría vacía justo para quien tiene que arreglarlo.
			if d.sucursalesPedidas[0] != nil {
				t.Fatalf("se acotó a %v y %s ve las ocho", d.sucursalesPedidas[0], rol)
			}
		})
	}
}
