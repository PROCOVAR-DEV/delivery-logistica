package sesiones

// REDIS COLGADO: acepta la conexión y no contesta nunca (un failover a medias, un firewall que
// descarta). Parar la API no puede esperar a que se acabe el plazo de la conexión (10 s): `main`
// sólo espera 2 s al hilo de sesiones y avisa «no terminó a tiempo». Sin Redis de verdad.

import (
	"context"
	"net"
	"testing"
	"time"

	"procovar/reparto-api/internal/config"
)

func TestConRedisColgadoCorrerVuelveEnCuantoSeCancela(t *testing.T) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	go func() { // acepta y calla, con la conexión abierta
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			t.Cleanup(func() { _ = c.Close() })
		}
	}()

	r := Nuevo(DeRedis(config.Redis{Direccion: l.Addr().String()}), nil)
	ctx, cancelar := context.WithCancel(context.Background())
	hecho := make(chan struct{})
	go func() { defer close(hecho); r.Correr(ctx) }()

	time.Sleep(300 * time.Millisecond) // que Correr ya esté esperando la confirmación de Redis
	inicio := time.Now()
	cancelar()
	select {
	case <-hecho:
		if d := time.Since(inicio); d > time.Second {
			t.Errorf("Correr tardó %v en volver tras cancelar: el apagado de main esperaría en vano", d)
		}
	case <-time.After(3 * time.Second):
		t.Fatalf("Correr no volvió a los 3 s de cancelar con Redis colgado (plazo de conexión: %v)", plazoDeConexion)
	}
}
