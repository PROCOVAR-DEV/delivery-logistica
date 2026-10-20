package avisoscrm

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"

	"procovar/reparto-api/internal/config"
)

// CONTRA UN REDIS DE VERDAD. Se salta SIN su variable, y `./comprobar.sh` lo dice a gritos
// (`REPARTO_REDIS_REAL_ADDR`, docs/entorno-local.md §7-bis): un typo en el nombre del canal pasaría
// todas las pruebas con la fuente falsa y se desplegaría un oyente que no oye nada.
func redisReal(t *testing.T) string {
	t.Helper()
	dir := os.Getenv("REPARTO_REDIS_REAL_ADDR")
	if dir == "" {
		t.Skip("sin REPARTO_REDIS_REAL_ADDR")
	}
	return dir
}

func TestRedisReal_LoQueSePublicaEnElCanalDelCRMLlegaConSuSucursal(t *testing.T) {
	dir := redisReal(t)
	fuente := DeRedis(config.Redis{Direccion: dir})
	if fuente == nil {
		t.Fatal("con una dirección, DeRedis tiene que devolver una fuente")
	}
	ctx, parar := context.WithTimeout(context.Background(), 20*time.Second)
	defer parar()

	llegan := make(chan string, 4)
	go Correr(ctx, fuente, logMudo(), func(_ context.Context, codigo string) { llegan <- codigo })

	pub := redis.NewClient(&redis.Options{Addr: dir})
	defer pub.Close()
	// El suscriptor tarda un instante en estar vivo: se publica hasta que llegue, que es lo que haría
	// cualquier aviso real tras una reconexión.
	hasta := time.Now().Add(10 * time.Second)
	for time.Now().Before(hasta) {
		_ = pub.Publish(ctx, Canal, `{"v":1,"tipo":"almacenes-cambiados","sucursal":"stg","tms":1792512000000}`).Err()
		select {
		case got := <-llegan:
			if got != "STG" {
				t.Fatalf("llegó %q; quería STG", got)
			}
			return
		case <-time.After(200 * time.Millisecond):
		}
	}
	t.Fatal("lo publicado en " + Canal + " no llegó al oyente")
}

// El canal es el contrato con la sesión del CRM: cambiarlo en un lado y no en el otro deja a Reparto
// sin oír nada y sin ningún error. Lo ata este literal.
func TestElCanalEsElDelContratoConElCRM(t *testing.T) {
	if Canal != "procovar:crm:almacenes" {
		t.Fatalf("Canal = %q; el contrato con el CRM es procovar:crm:almacenes", Canal)
	}
}
