package sesiones

// REDIS COLGADO: acepta la conexión y no contesta nunca (un failover a medias, un firewall que
// descarta). Parar la API no puede esperar a que se acabe el plazo de la conexión (10 s): `main`
// sólo espera 2 s al hilo de sesiones y avisa «no terminó a tiempo». Sin Redis de verdad.

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"net"
	"strconv"
	"strings"
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

// REDIS QUE CONFIRMA EL SUBSCRIBE Y SE CUELGA EN EL SCAN (re-auditoria 09/10/2026): el caso de
// arriba no lo cubre, porque ahi el saludo ni siquiera se completa. Aqui la suscripcion queda hecha
// y lo que no contesta es la carga de marcas (SCAN): go-redis no mira la CANCELACION de un contexto
// durante una lectura (solo su plazo), asi que `Marcas` tardaba el ReadTimeout (~3 s) + reintentos
// en volver (4,5 s medidos) y el apagado de `main` (2 s) daba «no termino a tiempo».
func TestConRedisQueSeCuelgaEnElScanCorrerVuelveEnCuantoSeCancela(t *testing.T) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	go func() {
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			t.Cleanup(func() { _ = c.Close() })
			go respondeHastaElScan(c)
		}
	}()

	r := Nuevo(DeRedis(config.Redis{Direccion: l.Addr().String()}), nil)
	ctx, cancelar := context.WithCancel(context.Background())
	hecho := make(chan struct{})
	go func() { defer close(hecho); r.Correr(ctx) }()

	time.Sleep(500 * time.Millisecond) // suscrito, y ya colgado en el SCAN
	inicio := time.Now()
	cancelar()
	select {
	case <-hecho:
		if d := time.Since(inicio); d > time.Second {
			t.Errorf("Correr tardó %v en volver tras cancelar con Redis colgado en el SCAN: el apagado de main esperaría en vano", d)
		}
	case <-time.After(12 * time.Second):
		t.Fatal("Correr no volvió a los 12 s de cancelar con Redis colgado en el SCAN")
	}
}

// respondeHastaElScan habla el mínimo de RESP: confirma el SUBSCRIBE, rechaza el HELLO (go-redis
// cae a RESP2) y calla en cuanto llega un SCAN.
func respondeHastaElScan(c net.Conn) {
	rd := bufio.NewReader(c)
	for {
		linea, err := rd.ReadString('\n')
		if err != nil || !strings.HasPrefix(linea, "*") {
			return
		}
		n, _ := strconv.Atoi(strings.TrimSpace(linea[1:]))
		args := make([]string, 0, n)
		for i := 0; i < n; i++ {
			cab, err := rd.ReadString('\n')
			if err != nil || len(cab) < 2 {
				return
			}
			largo, _ := strconv.Atoi(strings.TrimSpace(cab[1:]))
			buf := make([]byte, largo+2)
			if _, err := io.ReadFull(rd, buf); err != nil {
				return
			}
			args = append(args, string(buf[:largo]))
		}
		switch strings.ToUpper(args[0]) {
		case "SUBSCRIBE":
			fmt.Fprintf(c, "*3\r\n$9\r\nsubscribe\r\n$%d\r\n%s\r\n:1\r\n", len(args[1]), args[1])
		case "HELLO":
			fmt.Fprint(c, "-ERR unknown command 'HELLO'\r\n")
		case "SCAN":
			// se cuelga: no contesta
		default:
			fmt.Fprint(c, "+OK\r\n")
		}
	}
}
