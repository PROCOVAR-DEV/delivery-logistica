// El arranque del servicio de reparto.
//
// Tres cosas y en este orden, que importa:
//
//  1. Configuración. Si falta algo, se muere AQUÍ, con un mensaje que dice qué falta.
//     Nunca un 500 a media tarde en la pantalla de alguien que está cargando un camión.
//  2. Base de datos, con ping. Un proceso vivo que no llega a Postgres está caído.
//     2-bis. Y AL DÍA: con la base atrasada no se arranca. Un contenedor que no levanta se ve
//     en el despliegue; una flota congelada con la web en verde, no.
//  3. Servidor, con apagado ordenado.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/api"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/sesiones"
	"procovar/reparto-api/internal/store"
	"procovar/reparto-api/internal/ventra"
)

// version la incrusta el compilador:
//
//	go build -ldflags "-X main.version=$(git describe --tags --always)" ./cmd/api
//
// No se lee de un fichero ni se pregunta a nadie: /version la consulta cada aparato al
// arrancar, y la APK decide con ella si tiene que actualizarse.
var version = "dev"

func main() {
	if err := correr(); err != nil {
		// A stderr y sin el registro estructurado: esto lo lee una persona mirando el
		// despliegue, no un agregador de logs.
		fmt.Fprintf(os.Stderr, "\nreparto-api no puede arrancar:\n%v\n\n", err)
		os.Exit(1)
	}
}

func correr() error {
	cfg, err := config.Cargar(version)
	if err != nil {
		return err
	}
	reg := registro(cfg)

	// El contexto se cancela con la primera señal. SIGTERM es lo que manda Docker al
	// parar el contenedor; SIGINT es Ctrl+C en desarrollo.
	ctx, parar := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer parar()

	almacen, err := store.Abrir(ctx, cfg)
	if err != nil {
		return err
	}
	defer almacen.Cerrar()

	// LA BASE TIENE QUE ESTAR AL DÍA, y si no lo está esto se muere aquí.
	//
	// Es el paso 2-bis y va justo detrás del ping, antes de servir nada. El 17/09/2026 la
	// API se desplegó con la 00006 sin aplicar y estuvo un día entero «arrancada»:
	// instalaciones nuevas y la web, verdes; la flota que ya estaba en la calle, congelada
	// con un 500 en la bajada por diferencias que no vio nadie. Ver `db/migraciones.go`.
	if err := almacen.ExigirMigraciones(ctx); err != nil {
		return err
	}

	reg.Info("arrancando",
		"version", cfg.Version,
		"entorno", cfg.Entorno,
		"puerto", cfg.Puerto,
		"conexiones", cfg.PoolMaxConns,
	)
	if cfg.ServiceAPIKey == "" {
		// No impide arrancar —la API de personas funciona igual— pero el espejo de
		// PEDIDO no va a poder entrar, y eso desde fuera parece que PEDIDO no manda nada.
		reg.Warn("SERVICE_API_KEY vacía: las rutas de servicio quedan cerradas (el espejo de PEDIDO no podrá entrar)")
	}
	if len(cfg.OrigenesPermitidos) == 0 {
		reg.Warn("ORIGENES_PERMITIDOS vacío: el navegador no podrá llamar a esta API desde otro dominio")
	}
	// Tampoco impide arrancar, pero tiene que verse AL DESPLEGAR y no la tarde que
	// alguien pregunte por qué el vendedor no ve que su pedido salió. Sin esto, el canal
	// hacia PEDIDO queda mudo: no se rompe nada, pero el vendedor no se entera de nada.
	if cfg.PedidoAPIURL == "" {
		reg.Warn("PEDIDO_API_URL vacía: no se le podrá contar a PEDIDO en qué punto va cada pedido " +
			"(el reparto funciona igual, pero el vendedor no verá los cambios de estado)")
	}
	// LOS AVISOS POR NOTIFY, que es lo único que hace que un canal roto se vea sin que nadie
	// abra `/admin/webhook`. Tiene que verse AL DESPLEGAR y no la tarde que alguien pregunte
	// por qué no llegó ningún correo: sin esto, el reparto funciona igual y el fallo del
	// canal vuelve a ser invisible, que es exactamente lo que se vino a arreglar.
	if falta := cfg.Notify.Falta(); falta != "" {
		reg.Warn("falta la configuración de notify: NADIE se enterará de que el canal con PEDIDO "+
			"se rompió (avisos atascados, rechazos de PEDIDO, o PEDIDO dejando de empujar). "+
			"El reparto funciona igual, pero el fallo vuelve a verse sólo abriendo /admin/webhook",
			"falta", falta)
	} else {
		reg.Info("avisos por notify enchufados",
			"url", cfg.Notify.URL, "tipo", cfg.Notify.Tipo, "destino", cfg.Notify.Destino)
	}
	if cfg.AuthSigningKey == "" {
		reg.Warn("PROCOVAR_AUTH_SIGNING_KEY vacía: no se podrá preguntar a Accesos por los almacenes " +
			"ni por las tasas, así que no se podrán cotizar domicilios")
	}
	// EN PRODUCCIÓN ESTO YA NO LLEGA AQUÍ: desde el 24/09/2026 `APP_ULTIMA_VERSION` vacía
	// con `ENTORNO=produccion` para el arranque en `config.Cargar` (salvo que se diga a
	// propósito con `APP_SIN_ANUNCIO=si`). Un `Warn` en el registro de un contenedor no lo
	// lee nadie, y el canal de actualización estuvo muerto por eso: la api verde,
	// `/api/version` contestando `ultima: null`, y diez aparatos que pasan el día sin señal
	// sin enterarse nunca de que había una versión nueva.
	//
	// En desarrollo sigue siendo un aviso, que es lo correcto: levantar el reparto en el
	// portátil no puede depender de que haya un APK publicado.
	if !cfg.Publicada.HayAlguna() {
		reg.Warn("APP_ULTIMA_VERSION vacía: /api/version no anuncia ninguna versión de la aplicación, " +
			"así que ningún aparato avisará de que hay una nueva (docs/actualizaciones.md)")
	} else {
		reg.Info("versión de la aplicación publicada",
			"version", cfg.Publicada.Version,
			"compilacion", cfg.Publicada.Compilacion,
		)
	}

	// El servidor Y el empuje de Accesos se construyen juntos, con la función que prueba
	// `internal/api/sesion_cableada_test.go`: lo que se cose aquí es lo que se prueba allí.
	servicio, inv := api.NuevoServidorConSesiones(
		cfg, reg,
		alcance.NuevaPorteria(almacen, reg),
		auth.NuevoVerificador(cfg.JWTSecret),
		almacen.Salud,
		sesiones.DeRedis(cfg.Redis),
	)

	// ACCESOS INVALIDA LA SESIÓN DE LA WEB, Y LO EMPUJA (08/10/2026). Jose: «si cierro sesión o me
	// cambian un permiso en Accesos se refleja en todas. Nada de polling: para eso tenemos SSE y
	// Sentinel». Accesos publica en el Redis de la casa (el mismo del espejo, mismas REDIS_*); esto
	// escucha y mantiene en memoria quién tiene la sesión invalidada (`internal/sesiones`).
	//
	// SIN REDIS NO IMPIDE ARRANCAR NI SERVIR, y se dice AQUÍ, que es cuando lo lee quien despliega:
	// la API funciona como siempre, pero una sesión cerrada en Accesos sigue valiendo en la web
	// hasta que caduque su cookie (7 días). Con Redis puesto pero caído, el bucle lo dice en cada
	// intento y sigue sirviendo.
	if cfg.Redis.Hay() {
		if len(cfg.Redis.Centinelas) > 0 && cfg.Redis.Maestro == "" {
			reg.Warn("REDIS_CENTINELAS sin REDIS_MAESTRO: no se sabrá a qué maestro conectar y el " +
				"empuje de Accesos no llegará (la API sirve igual)")
		}
		reg.Info("empuje de sesiones de Accesos por Redis",
			"centinelas", cfg.Redis.Centinelas, "maestro", cfg.Redis.Maestro,
			"direccion", cfg.Redis.Direccion, "base", sesiones.BaseDeLasMarcas, "canal", sesiones.Canal)
	}
	hiloDeSesiones := make(chan struct{})
	go func() {
		defer close(hiloDeSesiones)
		inv.Correr(ctx)
	}()

	// EL LECTOR DE VENTRA, sólo si están LAS DOS variables.
	//
	// Sin ellas no se enchufa nada y el lector se queda en nil, que es lo que hace que
	// `POST /api/products/sync` conteste 502 diciendo que no está configurado. Montar el
	// cliente igualmente daría un lector que falla en cada llamada con un error de red —y
	// «no llego a Ventra» y «nadie me dijo dónde está Ventra» se arreglan de formas muy
	// distintas—. El aviso se da al ARRANCAR, que es cuando lo lee quien despliega, y no
	// la tarde que alguien se pregunte por qué el catálogo es de hace tres semanas.
	switch {
	case cfg.VentraURL != "" && cfg.VentraToken != "":
		servicio.PonerLectorDeVentra(ventra.Nuevo(cfg, reg))
		reg.Info("lector de Ventra enchufado", "url", cfg.VentraURL, "plazo", cfg.VentraPlazo)
	case cfg.VentraURL == "" && cfg.VentraToken == "":
		reg.Warn("WAREHOUSE_API_URL y WAREHOUSE_API_TOKEN vacías: no se podrá bajar el catálogo de " +
			"Ventra. POST /api/products/sync contestará 502 y los productos se quedarán con el peso, " +
			"el precio y las existencias de la última bajada buena")
	default:
		// Media configuración es la peor de las tres: se ve como si estuviera puesta.
		falta := "WAREHOUSE_API_TOKEN"
		if cfg.VentraURL == "" {
			falta = "WAREHOUSE_API_URL"
		}
		reg.Warn("falta la mitad de la configuración de Ventra: el catálogo NO se va a poder bajar",
			"falta", falta)
	}

	// EL REFRESCO DE LA TASA DE CAMBIO, sólo si se puede firmar contra Accesos.
	//
	// Sin `PROCOVAR_AUTH_SIGNING_KEY` no hay forma de preguntarle nada a Accesos, así que
	// arrancar la tarea sería un aviso de fallo cada hora en el registro y ni una tasa
	// guardada. Se dice al arrancar —que es cuando lo lee quien despliega— y no la tarde
	// que alguien pregunte por qué el aparato sigue enseñando los importes en USD.
	//
	// Corre en su propia gorutina y muere con el contexto, igual que el servidor: la
	// primera señal para las dos cosas.
	if cfg.AuthSigningKey != "" {
		refresco := api.NuevoRefrescoDeTasas(almacen, nil, reg, cfg.TasaRefresco)
		go refresco.Correr(ctx)
		reg.Info("refresco de la tasa de cambio arrancado", "cada", cfg.TasaRefresco)
	} else {
		reg.Warn("sin PROCOVAR_AUTH_SIGNING_KEY no se refresca la tasa de cambio: " +
			"`branches.cup_rate` se queda como esté y los aparatos sólo podrán ver los " +
			"importes en USD")
	}

	// EL DRENAJE DEL BUZÓN HACIA PEDIDO.
	//
	// El cierre de ruta ya intenta mandar el aviso en el acto —el vendedor tiene que
	// verlo ya—, pero si PEDIDO no contesta el aviso se queda en `avisos_a_pedido`. Esto
	// es quien vuelve a por él: sin este trabajador el buzón sería una lista de cosas
	// perdidas mejor apuntada, que no es el arreglo.
	//
	// Corre en su propia gorutina y muere con el contexto, igual que el refresco de tasas.
	// El alcance se abre en cada vuelta y va SIN sucursal: un aviso encolado es un hecho
	// que ya pasó, y quien lo drena no tiene sucursal ni persona detrás.
	porteriaDelBuzon := alcance.NuevaPorteria(almacen, reg)
	drenador := api.NuevoDrenadorDelBuzon(servicio, func(c context.Context) (*alcance.Acotado, error) {
		return porteriaDelBuzon.Resolver(c, &auth.Usuario{
			ID: "servicio:buzon", Rol: "SUPER ADMIN",
		}, "")
	}, api.CadaCuantoSeDrena)
	go drenador.Correr(ctx)
	reg.Info("drenaje del buzón hacia PEDIDO arrancado", "cada", api.CadaCuantoSeDrena)

	servidor := &http.Server{
		Addr:              cfg.Direccion(),
		Handler:           servicio.Rutas(),
		ReadHeaderTimeout: cfg.TiempoLectura,
		ReadTimeout:       cfg.TiempoLectura,
		WriteTimeout:      cfg.TiempoEscritura,
		ErrorLog:          slog.NewLogLogger(reg.Handler(), slog.LevelError),
	}

	fallo := make(chan error, 1)
	go func() {
		if err := servidor.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			fallo <- err
		}
	}()

	select {
	case err := <-fallo:
		return fmt.Errorf("el servidor se cayó: %w", err)
	case <-ctx.Done():
	}

	// APAGADO ORDENADO. Un corte seco tira las peticiones en vuelo: en reparto eso es un
	// logístico que le dio a guardar y no sabe si se guardó. Shutdown deja de aceptar
	// conexiones nuevas y espera a que terminen las que hay, con un plazo — pasado el
	// plazo se corta igual, porque quien nos está parando tampoco espera para siempre.
	reg.Info("parando: se espera a las peticiones en vuelo", "plazo", cfg.TiempoApagado)
	parar() // se deja de atender la señal: un segundo Ctrl+C mata de verdad

	ctxApagado, cancelar := context.WithTimeout(context.Background(), cfg.TiempoApagado)
	defer cancelar()
	if err := servidor.Shutdown(ctxApagado); err != nil {
		// Se fuerza el cierre, pero se dice: son peticiones cortadas y tienen que verse.
		_ = servidor.Close()
		return fmt.Errorf("no dio tiempo a terminar las peticiones en vuelo: %w", err)
	}
	// `ctx` ya está cancelado: el bucle de sesiones sale solo y suelta la conexión a Redis. Con
	// plazo, porque parar no puede depender de que Redis conteste.
	select {
	case <-hiloDeSesiones:
	case <-time.After(2 * time.Second):
		reg.Warn("el empuje de sesiones no terminó a tiempo; se sigue con el apagado")
	}
	reg.Info("parado")
	return nil
}

// registro: JSON en producción —que es lo que sabe leer el agregador— y texto en
// desarrollo, que es lo que sabe leer una persona.
func registro(cfg *config.Config) *slog.Logger {
	opciones := &slog.HandlerOptions{Level: slog.LevelInfo}
	var h slog.Handler
	if cfg.EnProduccion() {
		h = slog.NewJSONHandler(os.Stdout, opciones)
	} else {
		opciones.Level = slog.LevelDebug
		h = slog.NewTextHandler(os.Stdout, opciones)
	}
	reg := slog.New(h).With("servicio", "reparto-api")
	// También el de por defecto: lo usa cualquier sitio que escriba sin tener el suyo.
	slog.SetDefault(reg)
	return reg
}
