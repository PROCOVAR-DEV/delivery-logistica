// EL ALCANCE POR SUCURSAL. La regla de seguridad del sistema.
//
// POR SUCURSAL, NUNCA POR CUENTA. Aquí nada pertenece a una persona: los pedidos entran
// solos desde PEDIDO y son de la sucursal que los originó. Filtrar por «quien lo creó»
// fue el fallo de delivery —las ocho sucursales las dio de alta el Super Admin, así que
// los 3.528 pedidos importados quedaron a su nombre y los compañeros de Holguín no veían
// lo de Holguín—. Eso no se repite: el único campo que decide es `branch_id`.
//
// # Por qué es un paquete y no una función de ayuda
//
// Porque tiene que ser IMPOSIBLE llamar a una consulta sin pasar por aquí. El envoltorio
// `Acotado` es lo único que sabe llegar al `Querier`, y cada consulta con alcance se
// expone como un método suyo que RELLENA ÉL el parámetro de sucursal. El manejador no lo
// escribe; por tanto no puede olvidarlo, ni pasar el de otra, ni poner NULL «mientras
// pruebo». Quien añada un recurso nuevo añade su método en `consultas.go` y hereda la
// regla sin tener que acordarse de nada.
//
// # El modo de fallo que hay que evitar (visto en producción)
//
// Una sucursal que YA NO EXISTE acota a CERO: cero pedidos, cero clientes, cero rutas,
// cero vehículos y hasta cero sucursales —con lo que desaparece el selector con el que se
// podría arreglar—, todo con 200 y sin una sola traza. Desde dentro es indistinguible de
// «todavía no hay nada».
//
// Pasa de verdad: el id llega por dos sitios y los dos pueden traer uno viejo. El token
// del login único dura siete días y lleva dentro la sucursal que la persona tenía CUANDO
// entró; la cabecera sale de lo que el navegador guardó. Y las sucursales se recrearon en
// algún momento —unas con id cuid y otras hexadecimal—.
//
// Por eso, si la sucursal pedida no existe: PARA QUIEN ADMINISTRA (SUPER ADMIN y
// DESARROLLADOR) se comporta como «todas» y DEJA UN AVISO EN EL REGISTRO —abrir a todas es
// lo correcto para quien ya lo ve todo y, sobre todo, enseña el problema en vez de
// esconderlo—. Para CUALQUIER OTRO ROL es un 403 que dice cuál es el código que Reparto no
// conoce (`ErrSucursalSinAlta`): «todas» para él sería el fallo de delivery —un operador
// de Santiago viendo los precios de La Habana— disparado por un dato que no cuadra.
package alcance

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// CabeceraSucursal es por donde el Super Admin elige qué sucursal está mirando.
const CabeceraSucursal = "X-Sucursal-Id"

// Fuente es de dónde salen las consultas. La implementa el almacén de verdad (el pool de
// pgx) y también el doble de las pruebas, que por eso no necesitan base de datos.
type Fuente interface {
	Consultas() sqlc.Querier
	// EnTx corre f dentro de una transacción. Hace falta aquí y no en el manejador
	// porque hay operaciones que son varias consultas y todas tienen que ir con el
	// mismo alcance: marcar el vehículo de referencia son dos UPDATE, y a medias deja
	// la sucursal con dos camiones de referencia o con ninguno.
	EnTx(ctx context.Context, f func(sqlc.Querier) error) error
}

// Porteria resuelve el alcance de cada petición. Una sola por servicio.
type Porteria struct {
	fuente Fuente
	reg    *slog.Logger
}

func NuevaPorteria(f Fuente, reg *slog.Logger) *Porteria {
	if reg == nil {
		reg = slog.Default()
	}
	return &Porteria{fuente: f, reg: reg}
}

// Acotado es el permiso ya resuelto MÁS la puerta a las consultas. No hay forma de
// construirlo fuera de este paquete, y no hay forma de consultar sin él.
type Acotado struct {
	fuente Fuente
	q      sqlc.Querier

	actor    string     // quién pide; sólo para dejar constancia de quién creó algo
	sucursal *uuid.UUID // nil = todas
	codigo   *string    // el `external_id` de esa sucursal (CAM, HAB, STG...)
	persona  *uuid.UUID // la sucursal DE LA PERSONA, ignorando la cabecera
}

// ErrSinAlcance: no pertenece a ninguna sucursal y tampoco tiene un rol que las vea
// todas, así que no hay nada que pueda ver. Sale como 403 con este texto: dice qué falta y
// quién lo arregla.
var ErrSinAlcance = errors.New(
	"esta cuenta no está dada de alta en ninguna sucursal: pide en la oficina que te " +
		"asignen la tuya")

// ErrSucursalSinAlta: la persona SÍ trae una sucursal en su token, pero Reparto no la
// conoce. Es un `ErrSinAlcance` (`errors.Is` lo reconoce y sale como 403), con un texto
// propio que NOMBRA el código.
//
// POR QUÉ NO «TODAS». Hasta la entrega 1.0.28 una sucursal que no se resolvía abría el
// alcance a las ocho para cualquier rol, con un aviso en el registro que nadie lee. El
// caso real que lo hace explotar: Accesos conoce sucursales que Reparto no —`MOA`, `PLS`—
// y firma su código en el token de quien trabaja allí. Ese OPERADOR de Moa entraba y veía
// los pedidos, los precios y las rutas de las OCHO, con 200 y sin un error. Es la regla 1
// de la casa («el alcance sale de quién pregunta») fallando abierta, y la auditoría del
// 08/10/2026 la marcó como lo más grave del backlog.
//
// El fallo barato es dejarlo fuera con un mensaje que dice QUÉ falta («tu sucursal MOA no
// está dada de alta en Reparto») y a quién pedírselo; el caro es enseñarle las ocho.
//
// El texto de `ErrSinAlcance` NO cambia —la app y el canal de eventos lo comparan—; éste
// es otro caso con otro texto.
type ErrSucursalSinAlta struct{ Codigo string }

func (e ErrSucursalSinAlta) Error() string {
	return "tu sucursal " + e.Codigo + " no está dada de alta en Reparto: pide en la " +
		"oficina que la den de alta"
}

// Is hace que `errors.Is(err, ErrSinAlcance)` sea cierto: quien ya trata el 403 de «cuenta
// sin sucursal» (el middleware, el canal de eventos) trata también éste, y sólo cambia el
// texto que se escribe.
func (e ErrSucursalSinAlta) Is(destino error) bool { return destino == ErrSinAlcance }

// codigoParaElMensaje acota lo que viene del token antes de meterlo en un texto que sale
// al cliente: un código de sucursal son tres letras, y un valor largo o con saltos de línea
// es basura que no tiene por qué viajar.
func codigoParaElMensaje(pedida string) string {
	pedida = strings.Map(func(r rune) rune {
		if r < 0x20 || r == 0x7f {
			return -1
		}
		return r
	}, pedida)
	if r := []rune(pedida); len(r) > 40 {
		pedida = string(r[:40]) + "…"
	}
	return pedida
}

// LOS DOS ROLES QUE VEN LAS OCHO SUCURSALES, y no hay más.
//
// Salen de la tabla `role` de Accesos, leída el 16/09/2026, que tiene SIETE:
// ADMINISTRADOR, DESARROLLADOR, GERENTE, GESTOR, OPERADOR, SUPER ADMIN y SUPERVISOR.
//
//   - `SUPER ADMIN` administra todo Procovar.
//   - `DESARROLLADOR` está por encima todavía.
//
// Los otros cinco pertenecen a UNA sucursal, `ADMINISTRADOR` incluido — y por eso la
// comparación es contra el texto exacto y no «contiene admin»: un ADMINISTRADOR sin su
// sucursal se llevaría las ocho, que es justo la fuga que se está tapando. PEDIDO, que es
// la fuente de los roles, también los compara como texto.
// Es la misma pregunta que `auth.Usuario.EsSuperAdmin`, y por eso se delega en vez de
// repetirla: dos copias de una regla de permisos acaban diciendo cosas distintas, y la que
// se olvide de actualizar es por donde se cuela alguien.
func VeTodasLasSucursales(u *auth.Usuario) bool { return u.EsSuperAdmin() }

// Resolver aplica la regla, en el orden del contrato.
//
//  1. pedida = la sucursal de la persona. Sólo si NO tiene, y SÓLO si su rol ve todas
//     (`VeTodasLasSucursales`), vale la cabecera `X-Sucursal-Id`. LA DE LA PERSONA MANDA
//     SOBRE LA CABECERA: quien pertenece a una sucursal no puede pedir otra, y ésa es toda
//     la seguridad del sistema. Si se leyera antes la cabecera, cualquiera vería cualquier
//     sucursal cambiando una línea en el navegador.
//  2. Sin pedida -> todas, pero sólo para quien ve todas; el resto, `ErrSinAlcance`.
//  3. Con pedida, SE COMPRUEBA QUE EXISTA. Si no existe: quien ve todas -> aviso y todas;
//     cualquier otro rol -> `ErrSucursalSinAlta` (403 que nombra el código).
func (p *Porteria) Resolver(ctx context.Context, u *auth.Usuario, cabecera string) (*Acotado, error) {
	a := &Acotado{fuente: p.fuente, q: p.fuente.Consultas()}
	if u == nil {
		// Sin persona no hay alcance que resolver. Llegar aquí es un fallo de montaje
		// (falta `Exigir` delante), no una petición legítima.
		return nil, errors.New("alcance: no hay persona en la petición")
	}
	a.actor = u.ID

	veTodas := VeTodasLasSucursales(u)
	pedida := strings.TrimSpace(u.Sucursal)
	deLaPersona := pedida != ""
	if pedida == "" && veTodas {
		// LA CABECERA SÓLO LA LEE QUIEN PUEDE ELEGIR — 08/10/2026.
		//
		// Antes se leía para cualquiera sin sucursal: un OPERADOR cuyo token llegaba sin
		// ella (todavía sin asignar, o mal dado de alta) mandaba `X-Sucursal-Id: STG` y
		// pasaba a ver Santiago, o `X-Sucursal-Id: basura` y —por el «no existe -> todas»
		// de abajo— las ocho. La cabecera es lo que manda el cliente, y el alcance sale de
		// quién pregunta, no de lo que mande (CLAUDE.md §4). Elegir sucursal arriba es una
		// prerrogativa de SUPER ADMIN y DESARROLLADOR; para el resto la cabecera ni se mira.
		pedida = strings.TrimSpace(cabecera)
	}
	if pedida == "" {
		// SIN SUCURSAL **NO** SIGNIFICA «TODAS». Sólo lo significa para quien administra.
		//
		// Esto decía «Super Admin: todas» y NO MIRABA EL ROL: cualquiera cuyo token
		// llegara sin sucursal —alguien a quien todavía no le han dado la suya, o mal
		// dado de alta— veía las ocho. Es la regla 1 de la casa al revés, y ya costó
		// dinero una vez: «un operador de Santiago vio los precios de La Habana».
		//
		// Jose, 16/09/2026: «sin sucursal no es por el tipo de usuario no hagas eso por q
		// entonces un usuario sin sucursal ve todas eso esta malisimo».
		//
		// El fallo barato es dejar fuera a quien no tiene sucursal: se arregla dándosela,
		// y el mensaje lo dice. El caro es enseñarle las ocho, que no se ve.
		if !veTodas {
			return nil, ErrSinAlcance
		}
		return a, nil
	}

	id, err := uuid.Parse(pedida)
	if err != nil {
		// NO ES UN UUID. Antes de nada: casi siempre es el CÓDIGO de la sucursal.
		//
		// Accesos firma `sucursal`/`branch_id` con el CÓDIGO —`CAM`, `HOL`, `STG`—,
		// y lo hace en las dos puertas: el token de la APK y del escritorio
		// (`apk-tokens.ts`, `firmarAcceso`) y el token de la web que emite
		// `auth_web.go`, cuyo propio comentario dice «el CÓDIGO de la sucursal
		// (CAM, HOL…), que es lo que lee el alcance». Aquí no se leía: se hacía
		// `uuid.Parse("CAM")`, fallaba, y se caía en el «no existe -> todas».
		//
		// O sea que CUALQUIER persona que entrara con un token de Accesos de verdad
		// —web o escritorio, ADMINISTRADOR, SUPERVISOR, GESTOR u OPERADOR— veía las
		// OCHO sucursales. Comprobado el 24/09/2026 con Accesos levantado en el
		// portátil: un ADMINISTRADOR de Camagüey pedía `/api/orders` y le volvían
		// los 46 pedidos de las tres sucursales en vez de sus 19. Con 200, sin un
		// solo error, y con la pantalla enseñando un número creíble y equivocado.
		//
		// Es la regla 1 de la casa —«el alcance sale de quién pregunta»— y es el
		// mismo fallo que ya costó dinero en delivery: «un operador de Santiago vio
		// los precios de La Habana».
		//
		// No se vio antes porque las pruebas de este paquete meten un `uuid` en
		// `Usuario.Sucursal` (`stg.String()`), que es justo lo que el código suponía
		// y nunca lo que llega: una prueba que copia la suposición que prueba no
		// prueba nada. Ahora hay una que entra con el código, como Accesos.
		fila, errCodigo := a.q.BuscarSucursalPorCodigo(ctx, &pedida)
		switch {
		case errCodigo == nil:
			a.sucursal = &fila.ID
			a.codigo = fila.ExternalID
			if deLaPersona {
				a.persona = &fila.ID
			}
			return a, nil
		case errors.Is(errCodigo, pgx.ErrNoRows):
			// Ni uuid ni código conocido. Es el mismo caso que un id que ya no
			// está —los ids viejos de delivery eran cuid—: mismo trato.
			if err := p.sucursalQueNoExiste(deLaPersona, veTodas, pedida, u); err != nil {
				return nil, err
			}
			return a, nil
		default:
			// Igual que abajo: «no pude comprobarlo» NO es «no existe». Un fallo de
			// la base no puede abrir el alcance a las ocho.
			return nil, errCodigo
		}
	}

	fila, err := a.q.ResolverSucursal(ctx, id)
	switch {
	case err == nil:
		a.sucursal = &id
		a.codigo = fila.ExternalID
		if deLaPersona {
			a.persona = &id
		}
		return a, nil
	case errors.Is(err, pgx.ErrNoRows):
		if err := p.sucursalQueNoExiste(deLaPersona, veTodas, pedida, u); err != nil {
			return nil, err
		}
		return a, nil
	default:
		// OJO: un fallo de la base NO abre el alcance. «No pude comprobarlo» no es «no
		// existe»: si la base se cae medio segundo, abrir a todas enseñaría las ocho
		// sucursales a un operador de una. Se responde 500.
		return nil, err
	}
}

// sucursalQueNoExiste decide qué pasa cuando la sucursal pedida no se resuelve: nil (el
// alcance se queda en «todas», que es como nace) sólo para quien ve todas, y
// `ErrSucursalSinAlta` para el resto. Quien lo llama devuelve entonces `nil, err`: un
// alcance abierto NUNCA viaja junto a un error.
func (p *Porteria) sucursalQueNoExiste(deLaPersona, veTodas bool, id string, u *auth.Usuario) error {
	if !veTodas {
		p.avisarRechazo(id, u)
		return ErrSucursalSinAlta{Codigo: codigoParaElMensaje(id)}
	}
	p.avisar(deLaPersona, id, u)
	return nil
}

func (p *Porteria) avisarRechazo(id string, u *auth.Usuario) {
	quien := u.Email
	if quien == "" {
		quien = u.ID
	}
	p.reg.Warn("[alcance] la sucursal "+id+" de "+quien+" no existe en Reparto: se le niega el acceso (403)",
		"sucursal", id, "persona", quien, "rol", u.Rol)
}

func (p *Porteria) avisar(deLaPersona bool, id string, u *auth.Usuario) {
	if deLaPersona {
		quien := u.Email
		if quien == "" {
			quien = u.ID
		}
		p.reg.Warn("[alcance] la sucursal "+id+" de "+quien+" no existe: se le enseñan todas",
			"sucursal", id, "persona", quien)
		return
	}
	p.reg.Warn("[alcance] la sucursal "+id+" no existe: se pasa a todas", "sucursal", id)
}

type claveCtx int

const claveAcotado claveCtx = iota

// Exigir es el middleware. Va DESPUÉS del de la sesión: sin persona no hay alcance.
//
// Se monta una vez, en el router, sobre todas las rutas con datos. Que el alcance sea un
// escalón del montaje y no una llamada dentro de cada manejador es la diferencia entre
// «se nos olvidó en un endpoint» y «no se puede olvidar».
func (p *Porteria) Exigir(siguiente http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		u := auth.De(r)
		if u == nil {
			httpx.Registro(r).Error("alcance sin sesión delante", "ruta", r.URL.Path)
			httpx.NoAutorizado(w, r)
			return
		}
		a, err := p.Resolver(r.Context(), u, r.Header.Get(CabeceraSucursal))
		switch {
		case errors.Is(err, ErrSinAlcance):
			// 403 y no 500: no es una avería, es que a esta cuenta le falta algo que se
			// arregla en la oficina. El texto lo dice y sale tal cual en la pantalla.
			//
			// `err.Error()` y no `ErrSinAlcance.Error()`: el caso de la sucursal que Reparto
			// no conoce (`ErrSucursalSinAlta`) es el mismo 403 con un texto que nombra el
			// código — «tu sucursal MOA no está dada de alta en Reparto».
			httpx.Error(w, r, http.StatusForbidden, err.Error())
			return
		case err != nil:
			httpx.ErrorInterno(w, r, err)
			return
		}
		siguiente.ServeHTTP(w, r.WithContext(Con(r.Context(), a)))
	})
}

// De saca el alcance de la petición. nil si el middleware no se montó.
func De(r *http.Request) *Acotado { return DelContexto(r.Context()) }

// DelContexto es lo mismo pero sin la petición delante.
//
// Hace falta para los avisos en vivo: los ganchos `avisarCambio…` reciben un
// `context.Context` a secas —los llaman desde dentro del manejador, ya escrito el cambio—
// y necesitan saber DE QUÉ SUCURSAL es lo que acaba de cambiar para no mandarle el aviso
// a las otras siete. Ver `internal/api/eventos.go`.
//
// Devuelve nil donde no hay alcance, y eso NO es «de ninguna sucursal»: es «no se sabe».
// Quien lo use tiene que tratarlo como un aviso global, o el aviso no le llega a nadie.
func DelContexto(ctx context.Context) *Acotado {
	a, _ := ctx.Value(claveAcotado).(*Acotado)
	return a
}

// Con mete un alcance en el contexto. Para el middleware y para las pruebas.
func Con(ctx context.Context, a *Acotado) context.Context {
	return context.WithValue(ctx, claveAcotado, a)
}

// ---------------------------------------------------------------------------
// Lo que el alcance deja ver de sí mismo
// ---------------------------------------------------------------------------

// Todas dice si esta petición ve todas las sucursales.
func (a *Acotado) Todas() bool { return a.sucursal == nil }

// Sucursal es el uuid al que se está acotando, o nil.
func (a *Acotado) Sucursal() *uuid.UUID { return a.sucursal }

// Codigo es el `external_id` de la sucursal del alcance (CAM, HAB, STG...). Clientes y
// catálogo se acotan por CÓDIGO y no por uuid, y sin esta traducción no se puede armar
// el filtro.
func (a *Acotado) Codigo() *string { return a.codigo }

// Actor es quién pide. SÓLO sirve para dejar constancia de quién creó algo: NO FILTRA
// NADA. Si algún día aparece un `WHERE creado_por = actor`, es este fallo otra vez.
func (a *Acotado) Actor() string { return a.actor }

// ActorRef es el Actor como puntero, que es lo que esperan las columnas `creado_por`.
func (a *Acotado) ActorRef() *string {
	if a.actor == "" {
		return nil
	}
	v := a.actor
	return &v
}

// sucursalPg es el parámetro que espera sqlc: NULL cuando son todas.
func (a *Acotado) sucursalPg() pgtype.UUID { return aPg(a.sucursal) }

// personaPg es la sucursal DE LA PERSONA, sin la elegida por cabecera.
//
// POR QUÉ ES DISTINTA DEL ALCANCE: el alcance mezcla el permiso con la sucursal elegida
// arriba. En la LISTA de sucursales no se pregunta «qué estoy mirando» sino «a cuáles
// puedo llegar», que sólo depende de la persona. Si se acotara por la elegida, elegir una
// devolvería una sola, el selector se volvería una etiqueta fija y no habría forma de
// cambiar a otra: la elección se comería la lista con la que se elige.
func (a *Acotado) personaPg() pgtype.UUID { return aPg(a.persona) }

func aPg(id *uuid.UUID) pgtype.UUID {
	if id == nil {
		return pgtype.UUID{}
	}
	return pgtype.UUID{Bytes: [16]byte(*id), Valid: true}
}

// EnTx repite la operación dentro de una transacción CON EL MISMO ALCANCE. El `*Acotado`
// que recibe f consulta por la transacción, así que las consultas de dentro siguen
// llevando la sucursal puesta.
func (a *Acotado) EnTx(ctx context.Context, f func(*Acotado) error) error {
	return a.fuente.EnTx(ctx, func(q sqlc.Querier) error {
		dentro := *a
		dentro.q = q
		return f(&dentro)
	})
}
