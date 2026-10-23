// EL ESPEJO DE PEDIDO: el proceso que trae los datos.
//
// Sin esto, la base del reparto está vacía. No hay alta de pedidos a mano en ninguna
// pantalla: los pedidos y los clientes son de PEDIDO, y este proceso los copia.
//
// Corre APARTE de la API, con su propio contenedor, y así tiene que seguir:
//
//   - Un barrido del histórico puede tardar minutos. Dentro de la API compartiría el plazo
//     de las peticiones y la tumbaría cuando más se usa, que es de día.
//   - Si el espejo se cae, la API sigue atendiendo a quien está cargando un camión — con
//     los pedidos de hasta ese momento, que es mucho mejor que una pantalla caída.
//   - Y al revés: reiniciar la API no interrumpe un barrido a medias.
//
// Uso:
//
//	espejo            da vueltas hasta que lo paren
//	espejo --once     una pasada y se va (para probar y para un cron)
//
// Lo que necesita del entorno: `DATABASE_URL`, `SERVICE_API_KEY`, `PEDIDO_API_URL` y
// `DELIVERY_URL`. El resto tiene valores por defecto medidos (ver `internal/espejo`).
//
// Y SÓLO SI `SYNC_FUENTE` es `factura` o `ambas` (issue 20): `WAREHOUSE_API_URL` y
// `WAREHOUSE_API_TOKEN` (las mismas que la API), y opcionalmente `VENTRA_BASES` y
// `WAREHOUSE_TIMEOUT_MS`. Por defecto la fuente es `pedido` y nada de esto hace falta.
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/espejo"
	"procovar/reparto-api/internal/store"
	"procovar/reparto-api/internal/ventra"
)

func main() {
	if err := correr(); err != nil {
		// A stderr y sin el registro estructurado: esto lo lee una persona mirando el
		// despliegue, no un agregador de logs.
		fmt.Fprintf(os.Stderr, "\nel espejo no puede arrancar:\n%v\n\n", err)
		os.Exit(1)
	}
}

func correr() error {
	unaVez := flag.Bool("once", false, "una sola pasada y salir")
	flag.Parse()

	opciones, err := espejo.Cargar(os.Getenv)
	if err != nil {
		return err
	}
	reg := registro()

	// El contexto se cancela con la primera señal. SIGTERM es lo que manda Docker al parar
	// el contenedor; SIGINT es Ctrl+C en desarrollo.
	ctx, parar := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer parar()

	cfg, err := configDeLaBase()
	if err != nil {
		return err
	}
	almacen, err := store.Abrir(ctx, cfg)
	if err != nil {
		return err
	}
	defer almacen.Cerrar()

	// EL ESPEJO NO TIENE PERSONA, y su alcance es «todas»: trae las ocho sucursales de una
	// pasada. Aun así se pasa por la portería y no por el `Querier` pelado — la regla del
	// sistema es que a la base se llega por `alcance`, y una excepción «porque esto es un
	// proceso de fondo» es exactamente como se acaban colando las consultas sin sucursal.
	//
	// EL ROL VA EXPLÍCITO. Ésta es la CUARTA puerta de servicio, y la última en enterarse.
	//
	// El 16/09/2026 `VeTodasLasSucursales` dejó de ser «no tiene sucursal» y pasó a mirar
	// el ROL. Se actualizaron las tres de `internal/api` y ésta se quedó atrás: sin rol,
	// la portería devuelve `ErrSinAlcance` y **este proceso no arranca**. Sin espejo no
	// entran ni clientes, ni catálogo, ni los pedidos de PEDIDO.
	//
	// No se vio ese día porque la imagen desplegada era anterior al cambio: el binario en
	// marcha no tenía la regla nueva. Habría muerto en el siguiente despliegue del espejo,
	// que es la peor forma de encontrarlo — un despliegue que no cambia nada y rompe algo.
	//
	// Y como en las otras tres: esto NO es «un usuario sin sucursal». La regla de Jose es
	// sobre personas; esto es el propio espejo, que por definición recorre las ocho.
	acotado, err := alcance.NuevaPorteria(almacen, reg).Resolver(ctx,
		&auth.Usuario{ID: "servicio:espejo", Nombre: "espejo", Rol: "SUPER ADMIN"}, "")
	if err != nil {
		return fmt.Errorf("no se pudo resolver el alcance del espejo: %w", err)
	}

	proceso := espejo.Nuevo(opciones, espejo.BaseDelReparto{Acotado: acotado}, reg)

	// UNA FACTURA CANCELADA EN VENTRA SE AVISA A PEDIDO como `cancelado` (por folio y factura), por el
	// mismo buzón y con los mismos reintentos que el cierre de ruta (Jose, 23/10/2026: el estado de cada
	// factura va a PEDIDO en todos sus cambios, no sólo al completar la ruta). Sin folio no hay a quién
	// avisar y no se hace ruido. Un fallo se registra: el ciclo siguiente lo repite (el aviso es idempotente).
	proceso.AvisarCancelada = func(ctx context.Context, c espejo.EntregaCancelada) {
		if _, err := acotado.AvisarFacturasCanceladas(ctx, []uuid.UUID{c.ID}, proceso.Ahora()); err != nil {
			reg.Error("no se pudo avisar a PEDIDO de una factura cancelada", "externalId", c.ExternalID, "err", err)
		}
	}

	// LA FACTURA DE VENTRA COMO FUENTE (issue 20, Fase A), sólo si `SYNC_FUENTE` la incluye. Por
	// defecto es `pedido` y no se monta nada: desplegar esto no cambia el espejo. El lector es
	// el MISMO cliente de Ventra que usa la API para el catálogo, con la misma URL, el mismo
	// token y los mismos emparejamientos de bases (`VENTRA_BASES`). NO se pasa por `config.Cargar`
	// por lo de siempre: exige `JWT_SECRET`, que aquí no se usa.
	if opciones.LeeFactura() {
		proceso.ConFacturas(ventra.Nuevo(&config.Config{
			VentraURL:   opciones.VentraURL,
			VentraToken: opciones.VentraToken,
			VentraPlazo: opciones.VentraPlazo,
			VentraBases: opciones.VentraBases,
		}, reg))
		reg.Info("la factura de Ventra es fuente del espejo", "fuente", opciones.Fuente,
			"ventra", opciones.VentraURL, "plazo", opciones.VentraPlazo)
	}

	if *unaVez {
		return proceso.Ciclo(ctx)
	}

	// EL ESCUCHADOR DE AVISOS, EN PARALELO CON EL CICLO.
	//
	// PEDIDO deja un aviso en un stream de Redis cada vez que un pedido pasa a importarle
	// al reparto, y esto lo lee BLOQUEADO: entra en cuanto lo sueltan, sin sondeo. Jose,
	// 26/09/2026: «que notifique ya cada vez que salga uno, así entra directo; nada de
	// polling».
	//
	// SIN REDIS CONFIGURADO NO SE ENCHUFA y el espejo sigue con su ciclo de siempre. Es
	// deliberado: así esto se puede desplegar antes de tocar el Redis, y un Redis caído no
	// impide arrancar. El aviso va al ARRANCAR, que es cuando lo lee quien despliega, y no
	// la tarde que alguien se pregunte por qué los pedidos tardan quince minutos.
	// SIN PEDIDO COMO FUENTE (`SYNC_FUENTE=factura`) tampoco se escucha su cola: sus avisos
	// traerían pedidos de PEDIDO por la puerta de atrás. Apagar el webhook de la API es parte del
	// CORTE, no de esto.
	if opciones.EscuchaLosAvisos() && opciones.LeePedido() {
		base := espejo.BaseDelReparto{Acotado: acotado}
		escuchador := espejo.NuevoEscuchador(
			espejo.NuevoRedisDeAvisos(opciones), opciones, reg,
			func(c context.Context, q espejo.QueHaceFaltaTraer) error {
				return proceso.Atender(c, q)
			},
			// LA CONSTANCIA DE CADA TANDA. Lo pidió la sesión de PEDIDO: desde allá, un
			// aviso que sale y no lleva a nada se ve exactamente igual que uno que
			// funcionó. Va a la MISMA tabla que las tandas que entran por HTTP, con el
			// `origen` distinguiéndolas, para no tener que mirar en dos sitios la
			// pregunta «¿está entrando algo?».
		).ConApunte(base.ApuntarTandaDeAvisos)
		go func() {
			if err := escuchador.Correr(ctx); err != nil {
				reg.Error("el escuchador de avisos de PEDIDO se paró", "err", err)
			}
		}()
	} else {
		reg.Warn("sin REDIS_DIRECCION ni REDIS_CENTINELAS no se escuchan los avisos de " +
			"PEDIDO: el espejo se entera de los cambios por su ciclo, y el ciclo tarda " +
			"lo que diga SYNC_POLL_MS")
	}

	return proceso.Correr(ctx)
}

// configDeLaBase arma lo justo para abrir el pool. NO pasa por `config.Cargar` a propósito:
// eso exige `JWT_SECRET`, que es para validar personas, y aquí no entra ninguna. Pedirlo
// sería no arrancar el espejo por un secreto que no va a usar.
func configDeLaBase() (*config.Config, error) {
	url := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if url == "" {
		return nil, fmt.Errorf("falta DATABASE_URL: el espejo guarda los clientes y lee su marca de agua en la base del reparto")
	}
	return &config.Config{
		DatabaseURL: url,
		// Pocas conexiones: el espejo hace una consulta cada vez y no puede quedarse con
		// las que necesita la API para atender a quien está cargando un camión.
		PoolMaxConns:    4,
		PoolMinConns:    1,
		PoolMaxIdleTime: 5 * time.Minute,
	}, nil
}

func registro() *slog.Logger {
	opciones := &slog.HandlerOptions{Level: slog.LevelInfo}
	var h slog.Handler
	if os.Getenv("ENTORNO") == "produccion" {
		h = slog.NewJSONHandler(os.Stdout, opciones)
	} else {
		opciones.Level = slog.LevelDebug
		h = slog.NewTextHandler(os.Stdout, opciones)
	}
	reg := slog.New(h).With("servicio", "espejo")
	slog.SetDefault(reg)
	return reg
}
