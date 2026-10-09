package sesiones

// La conexión REAL, contra un Redis de verdad. Sólo corre si se pide —igual que
// `REPARTO_MOTOR_REAL_DSN` para Postgres— y se SALTA EN SILENCIO sin él:
//
//	docker run -d --rm --name reparto-redis-prueba -p 127.0.0.1:6390:6379 redis:7-alpine
//	REPARTO_REDIS_REAL_ADDR=127.0.0.1:6390 go test -count=1 ./internal/sesiones -run Real
//
// Sin centinela: lo que se ejercita es el SCAN, la suscripción, el PING y la reconexión; el
// FailoverClient de go-redis sólo cambia cómo se encuentra el maestro.

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"

	"procovar/reparto-api/internal/config"
)

func redisReal(t *testing.T) (config.Redis, *redis.Client) {
	t.Helper()
	addr := os.Getenv("REPARTO_REDIS_REAL_ADDR")
	if addr == "" {
		t.Skip("sin REPARTO_REDIS_REAL_ADDR: se salta la prueba contra un Redis de verdad")
	}
	// Un cliente aparte, en la DB 6, que hace de Accesos.
	accesos := redis.NewClient(&redis.Options{Addr: addr, DB: BaseDeLasMarcas})
	ctx := context.Background()
	if err := accesos.Ping(ctx).Err(); err != nil {
		t.Fatalf("no hay Redis en %s: %v", addr, err)
	}
	limpiar := func() {
		claves, _ := accesos.Keys(ctx, "procovar:auth:invalida:*").Result()
		if len(claves) > 0 {
			accesos.Del(ctx, claves...)
		}
	}
	limpiar()
	t.Cleanup(func() { limpiar(); accesos.Close() })
	return config.Redis{Direccion: addr}, accesos
}

func TestRealScanSuscripcionYPing(t *testing.T) {
	cfg, accesos := redisReal(t)
	ctx, cancelar := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancelar()

	accesos.Set(ctx, PrefijoDeMarcaWeb+"ana", "100", VidaDeUnaMarca)
	accesos.Set(ctx, PrefijoDeMarcaTodo+"beto", "200", VidaDeUnaMarca)
	accesos.Set(ctx, PrefijoDeMarcaTodo+"roto", "no-es-un-numero", VidaDeUnaMarca)
	accesos.Set(ctx, "procovar:auth:invalida:antigua", "300", VidaDeUnaMarca) // familia que ya no existe
	// Más de un lote, para ejercitar el MGET por tandas.
	for i := 0; i < 2*tamanoDeLote+5; i++ {
		accesos.Set(ctx, PrefijoDeMarcaWeb+"masa-"+string(rune('a'+i%26))+string(rune('a'+i/26)), "400", VidaDeUnaMarca)
	}

	f := DeRedis(cfg)
	defer f.Cerrar()

	m, err := f.Marcas(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if m.Web["ana"] != 100 || m.Todo["beto"] != 200 {
		t.Errorf("el SCAN no trajo las marcas: web=%v todo=%v", m.Web["ana"], m.Todo["beto"])
	}
	if _, hay := m.Todo["roto"]; hay {
		t.Error("una marca con un valor que no es número se coló")
	}
	if _, hay := m.Web["antigua"]; hay {
		t.Error("la familia vieja sin alcance se leyó como `web`")
	}
	if len(m.Web) != 1+2*tamanoDeLote+5 {
		t.Errorf("el SCAN por lotes trajo %d marcas web, se esperaban %d", len(m.Web), 1+2*tamanoDeLote+5)
	}

	// El silencio NO mata la suscripción: con un latido corto hay varios PING sin mensajes.
	original := latidoDeLectura
	latidoDeLectura = 40 * time.Millisecond
	defer func() { latidoDeLectura = original }()

	sus, err := f.Suscribir(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer sus.Cerrar()
	go func() {
		time.Sleep(400 * time.Millisecond) // diez latidos de silencio
		accesos.Publish(ctx, Canal, mensaje("web", TipoSesionCerrada, 777, "ana"))
	}()
	crudo, err := sus.Siguiente(ctx)
	if err != nil {
		t.Fatalf("el silencio mató la suscripción (el PING no la mantuvo): %v", err)
	}
	if crudo != mensaje("web", TipoSesionCerrada, 777, "ana") {
		t.Errorf("llegó %q", crudo)
	}
}

// El camino entero con un Redis de verdad: arranque, mensaje, caída de la conexión y reconexión
// recargando lo que se escribió mientras no se oía.
func TestRealCorrerSobrevivePerderLaConexion(t *testing.T) {
	cfg, accesos := redisReal(t)
	ctx := context.Background()
	accesos.Set(ctx, PrefijoDeMarcaWeb+"ana", "100", VidaDeUnaMarca)

	r, _, _, _ := arrancar(t, DeRedis(cfg))
	esperarA(t, func() bool { return r.Activo() && r.LaCookieNoVale("ana", 50) }, "no arrancó con la marca de Ana")

	accesos.Publish(ctx, Canal, mensaje("todo", TipoPermisosCambiados, 500, "beto"))
	esperarA(t, func() bool { return r.ElBearerNoVale("beto", 0, 0) }, "el mensaje real no llegó")

	// Se corta la conexión de suscripción (como un failover) y, SIN publicar nada, se escribe una
	// marca nueva: sólo puede enterarse el SCAN de la reconexión.
	if err := accesos.Do(ctx, "CLIENT", "KILL", "TYPE", "pubsub").Err(); err != nil {
		t.Fatal(err)
	}
	accesos.Set(ctx, PrefijoDeMarcaTodo+"carla", "900", VidaDeUnaMarca)
	esperarA(t, func() bool { return r.LaCookieNoVale("carla", 800) },
		"tras perder la conexión no se reconectó recargando las marcas")

	// Y tras reconectar el canal vuelve a funcionar.
	accesos.Publish(ctx, Canal, mensaje("web", TipoSesionCerrada, 1000, "dani"))
	esperarA(t, func() bool { return r.LaCookieNoVale("dani", 999) }, "reconectó pero no oye el canal")
}
