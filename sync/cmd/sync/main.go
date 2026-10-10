// El sincronizador de reparto.
//
// Cuatro rutas y una idea: que un logístico pueda trabajar un día entero sin conexión y no
// pierda nada. El protocolo está en `docs/sincronizacion.md` y este binario no hace nada
// que no esté allí.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"procovar/reparto-sync/internal/config"
	"procovar/reparto-sync/internal/httpx"
	"procovar/reparto-sync/internal/identidad"
	"procovar/reparto-sync/internal/reparto"
	"procovar/reparto-sync/internal/sesiones"
	"procovar/reparto-sync/internal/sincro"
	"procovar/reparto-sync/internal/store"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(log)

	if err := arrancar(log); err != nil {
		log.Error("no arranca", "err", err)
		os.Exit(1)
	}
}

func arrancar(log *slog.Logger) error {
	cfg, err := config.Cargar()
	if err != nil {
		return err
	}

	ctx, parar := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer parar()

	base, err := store.Abrir(ctx, store.Opciones{
		URL:           cfg.BaseDeDatos,
		MaxConexiones: cfg.MaxConexiones,
	})
	if err != nil {
		return err
	}
	defer base.Cerrar()

	// LA BASE TIENE QUE ESTAR AL DÍA, y si no lo está esto se muere aquí. Ver
	// `db/migraciones.go`: una tabla que falta en el sincronizador se ve como apuntes que
	// no suben, no como un error, y eso no lo mira nadie hasta que alguien reclama.
	if err := base.ExigirMigraciones(ctx); err != nil {
		return err
	}

	cliente := reparto.Nuevo(cfg.RepartoURL, cfg.RepartoClave, cfg.RepartoTiempo)

	servicio := sincro.Nuevo(sincro.Opciones{
		Datos:      base,
		Origen:     cliente,
		Aplicador:  cliente,
		TopeBajada: cfg.TopeBajada,
		Log:        log,
	})

	mux := http.NewServeMux()
	servicio.Rutas(mux)

	// Todo lo del protocolo exige sesión. La salud no, porque la mira el orquestador y
	// tiene que poder decir «está vivo» aunque auth esté caído.
	publico := http.NewServeMux()
	// ACCESOS CORTA SESIONES Y LO EMPUJA (08/10/2026). Sin esto, un token de acceso de 15 minutos
	// seguiría sirviendo la bajada y la subida tras un corte de seguridad. Los cambios llegan por el
	// Redis de la casa (los mismos REDIS_* que el espejo y `reparto-api`); ver `internal/sesiones`.
	//
	// SIN REDIS NO IMPIDE ARRANCAR NI SERVIR, y se dice AQUÍ, que es cuando lo lee quien despliega.
	// Si está caído, el bucle lo dice en cada intento y sigue sirviendo.
	if cfg.Redis.Hay() {
		if len(cfg.Redis.Centinelas) > 0 && cfg.Redis.Maestro == "" {
			log.Warn("REDIS_CENTINELAS sin REDIS_MAESTRO: no se sabrá a qué maestro conectar y el " +
				"empuje de Accesos no llegará (el sincronizador sirve igual)")
		}
		log.Info("empuje de sesiones de Accesos por Redis",
			"centinelas", cfg.Redis.Centinelas, "maestro", cfg.Redis.Maestro,
			"direccion", cfg.Redis.Direccion, "base", sesiones.BaseDeLasMarcas, "canal", sesiones.Canal)
	}
	// LA SUCURSAL DEL TOKEN VIENE COMO CÓDIGO (`CAM`), no como uuid, y aquí no hay tabla de
	// sucursales: la traduce el reparto, y el caché evita una ida y vuelta por cada apunte de una cola
	// de ocho horas. El porqué entero, en `internal/identidad/token.go`.
	//
	// DE DÓNDE SALE QUIÉN LLAMA. Con `token` se verifica aquí el de auth, que es lo que hay que hacer
	// con el servicio publicado en internet; `cabeceras` sólo vale detrás de un proxy que ya lo haya
	// verificado. El porqué largo, en `internal/identidad`. El cableado con el suscriptor de sesiones
	// vive en `identidad.FuenteDeLaCasa`, que es lo que prueba `fuente_de_la_casa_test.go`.
	codigos := identidad.NuevoCache(cliente.SucursalPorCodigo, time.Hour)
	fuente, invalidaciones := identidad.FuenteDeLaCasa(cfg.Identidad, []byte(cfg.JWTSecreto),
		codigos.Resolver, sesiones.DeRedis(cfg.Redis), log)
	// LA ENTREGA A REVISIÓN (`docs/bandeja-de-revision.md`): quien perdió `delivery.entrar` y conserva sesión
	// entrega su cola con un token de ENTREGA de Accesos (10 minutos, un ámbito), que la fuente normal
	// rechaza. Dos fuentes aparte, construidas con el MISMO registro de sesiones que la normal (un corte de
	// Accesos también mata al token de entrega) y cada una detrás de su ruta: `entrega` sólo acepta ese
	// token; `mias` ese o el normal. Ver `identidad.FuentesDeEntrega`.
	fuenteEntrega, fuenteMias := identidad.FuentesDeEntrega(cfg.Identidad, []byte(cfg.JWTSecreto),
		codigos.Resolver, invalidaciones, fuente)
	hiloDeSesiones := make(chan struct{})
	go func() {
		defer close(hiloDeSesiones)
		invalidaciones.Correr(ctx)
	}()
	publico.Handle("/sync/", identidad.Exigir(fuente, mux))
	// Las DOS rutas de la entrega van en el mux público, cada una con su fuente: `ServeMux` elige el patrón
	// más específico, así que ganan a `/sync/` sólo para esos dos métodos y rutas. Todo lo demás —subida,
	// bajada, estado, alta— sigue detrás del `Exigir` de arriba, que RECHAZA el token de entrega.
	servicio.RutasDeRevision(publico, fuenteEntrega, fuenteMias)
	publico.HandleFunc("GET /salud", func(w http.ResponseWriter, r *http.Request) {
		if err := base.Ping(r.Context()); err != nil {
			httpx.Fallo(w, http.StatusServiceUnavailable, "La base no contesta")
			return
		}
		httpx.JSON(w, http.StatusOK, map[string]string{"estado": "bien"})
	})

	servidor := &http.Server{
		Addr:        cfg.Direccion,
		Handler:     httpx.Recuperar(log, httpx.Registro(log, publico)),
		ReadTimeout: cfg.EsperaLectura,
		// La de escritura es larga a propósito: un lote de un día entero se aplica apunte
		// por apunte contra el reparto, y cortarlo a la mitad deja trabajo sin contestar.
		WriteTimeout: cfg.EsperaEscritura,
		IdleTimeout:  2 * time.Minute,
	}
	// El aviso en vivo de la revisión (`GET /sync/revision/eventos`) es un SSE que no queda inactivo nunca:
	// sin esto, `Shutdown` esperaría a los 30 s de abajo a conexiones que no van a terminar solas, y se los
	// quitaría a las colas que se están aplicando. Cierra SÓLO esos canales; las demás peticiones terminan solas.
	servidor.RegisterOnShutdown(servicio.CerrarAvisos)

	fallo := make(chan error, 1)
	go func() {
		log.Info("sincronizador escuchando", "config", cfg.String())
		if err := servidor.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			fallo <- err
		}
	}()

	select {
	case err := <-fallo:
		return err
	case <-ctx.Done():
		// Cierre ordenado: lo que se está aplicando ahora mismo es la cola de alguien que
		// lleva ocho horas sin señal. Se le da tiempo a terminar y a contestar, que es lo
		// que le deja saber qué se aplicó y qué no.
		log.Info("parando")
		cierre, listo := context.WithTimeout(context.Background(), 30*time.Second)
		defer listo()
		err := servidor.Shutdown(cierre)
		// `ctx` ya está cancelado: el bucle de sesiones sale solo y suelta Redis. Con plazo, porque
		// parar no puede depender de que Redis conteste.
		select {
		case <-hiloDeSesiones:
		case <-time.After(2 * time.Second):
			log.Warn("el empuje de sesiones no terminó a tiempo; se sigue con el apagado")
		}
		return err
	}
}
