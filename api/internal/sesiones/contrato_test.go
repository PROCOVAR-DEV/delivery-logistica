package sesiones

// EL CONTRATO CON ACCESOS, ATADO SIN REDIS (09/10/2026).
//
// Las pruebas contra un Redis de verdad (`redis_real_test.go`) se saltan sin
// `REPARTO_REDIS_REAL_ADDR`, y la auditoría del 08/10 demostró que tres mutaciones de `redis.go`
// —la DB 6 por la 2, el prefijo del SCAN, el nombre del canal— salían VERDES sin esa variable: un
// typo en el canal se desplegaba en verde y la sesión única no funcionaba. Estas dos pruebas no
// necesitan nada:
//
//  1. la tabla de abajo es la de `auth/src/lib/eventos-de-sesion.ts` COPIADA (`CANAL_DE_EVENTOS`,
//     `claveDeMarca`, la DB 6 de `getRedis('sessions')`, `SEGUNDOS_DE_LA_MARCA`, tipos y alcances);
//  2. un Redis de mentira por TCP (RESP) apunta lo que `redis.go` manda DE VERDAD por el cable, así
//     que no importa si el literal está en una constante o escrito en `redis.go`.
//
// Si Accesos cambia uno de estos valores, se cambia AQUÍ, en `sync/internal/sesiones` y en
// `docs/contratos-api.md`, juntos.

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"net"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"

	"procovar/reparto-api/internal/config"
)

func TestElContratoConAccesosNoSeCambiaSolo(t *testing.T) {
	// auth/src/lib/eventos-de-sesion.ts: CANAL_DE_EVENTOS, claveDeMarca(alcance, id), SEGUNDOS_DE_LA_MARCA.
	// La DB 6 es la de `getRedis('sessions')` de Accesos.
	tabla := []struct {
		que         string
		tiene, debe any
	}{
		{"canal", Canal, "procovar:auth:eventos"},
		{"clave de la marca web", PrefijoDeMarcaWeb + "u1", "procovar:auth:invalida:web:u1"},
		{"clave de la marca todo", PrefijoDeMarcaTodo + "u1", "procovar:auth:invalida:todo:u1"},
		{"base de Redis", BaseDeLasMarcas, 6},
		{"vida de la marca (s)", int(VidaDeUnaMarca / time.Second), 691_200},
		{"tipo sesion-cerrada", TipoSesionCerrada, "sesion-cerrada"},
		{"tipo permisos-cambiados", TipoPermisosCambiados, "permisos-cambiados"},
		{"alcance web", AlcanceWeb, "web"},
		{"alcance todo", AlcanceTodo, "todo"},
		{"versión del mensaje", versionConocida, 1},
	}
	for _, c := range tabla {
		if c.tiene != c.debe {
			t.Errorf("%s: aquí es %v y el contrato de Accesos (eventos-de-sesion.ts) dice %v", c.que, c.tiene, c.debe)
		}
	}
}

// redisDeMentira: acepta conexiones, entiende lo mínimo de RESP y APUNTA cada comando que recibe.
type redisDeMentira struct {
	mu       sync.Mutex
	comandos []string
}

func levantarRedisDeMentira(t *testing.T) (*redisDeMentira, string) {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = l.Close() })
	r := &redisDeMentira{}
	go func() {
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			t.Cleanup(func() { _ = c.Close() })
			go r.atender(c)
		}
	}()
	return r, l.Addr().String()
}

func (r *redisDeMentira) atender(c net.Conn) {
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
			if err != nil {
				return
			}
			largo, _ := strconv.Atoi(strings.TrimSpace(cab[1:]))
			buf := make([]byte, largo+2)
			if _, err := io.ReadFull(rd, buf); err != nil {
				return
			}
			args = append(args, string(buf[:largo]))
		}
		r.mu.Lock()
		r.comandos = append(r.comandos, strings.Join(args, " "))
		r.mu.Unlock()
		switch strings.ToUpper(args[0]) {
		case "SUBSCRIBE":
			fmt.Fprintf(c, "*3\r\n$9\r\nsubscribe\r\n$%d\r\n%s\r\n:1\r\n", len(args[1]), args[1])
		case "SCAN":
			fmt.Fprint(c, "*2\r\n$1\r\n0\r\n*0\r\n")
		case "HELLO":
			fmt.Fprint(c, "-ERR unknown command 'HELLO'\r\n")
		default:
			fmt.Fprint(c, "+OK\r\n")
		}
	}
}

func (r *redisDeMentira) vio(cmd string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, c := range r.comandos {
		if strings.EqualFold(c, cmd) {
			return true
		}
	}
	return false
}

func (r *redisDeMentira) todos() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]string(nil), r.comandos...)
}

// LO QUE `redis.go` MANDA POR EL CABLE: la DB, el canal y los patrones del SCAN. Es lo que las
// tres mutaciones de la auditoría rompían sin que nada se enterase.
func TestElAdaptadorDeRedisHablaLaBaseElCanalYElPrefijoDelContrato(t *testing.T) {
	mentira, addr := levantarRedisDeMentira(t)
	f := DeRedis(config.Redis{Direccion: addr})
	defer f.Cerrar()
	ctx, cancelar := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancelar()

	sus, err := f.Suscribir(ctx)
	if err != nil {
		t.Fatalf("no se pudo suscribir al Redis de mentira: %v (comandos: %q)", err, mentira.todos())
	}
	defer sus.Cerrar()
	if _, err := f.Marcas(ctx); err != nil {
		t.Fatalf("el SCAN falló contra el Redis de mentira: %v (comandos: %q)", err, mentira.todos())
	}

	for _, esperado := range []string{
		"SELECT 6", // la DB de las sesiones de Accesos
		"SUBSCRIBE procovar:auth:eventos",
		"SCAN 0 MATCH procovar:auth:invalida:web:* COUNT " + strconv.Itoa(tamanoDeLote),
		"SCAN 0 MATCH procovar:auth:invalida:todo:* COUNT " + strconv.Itoa(tamanoDeLote),
	} {
		if !mentira.vio(esperado) {
			t.Errorf("el adaptador no mandó %q; mandó %q", esperado, mentira.todos())
		}
	}
}

// POR CENTINELA (producción) la DB también es la 6: ese camino no se puede recorrer con el Redis de
// mentira (haría falta un centinela), pero las opciones con las que se monta el cliente sí se leen.
func TestElClientePorCentinelaTambienVaALaBaseDelContrato(t *testing.T) {
	f := DeRedis(config.Redis{Centinelas: []string{"127.0.0.1:1"}, Maestro: "procovar-master"})
	cliente, ok := f.(*fuenteRedis).c.(*redis.Client)
	if !ok {
		t.Fatalf("el cliente por centinela es un %T, se esperaba *redis.Client", f.(*fuenteRedis).c)
	}
	defer f.Cerrar()
	if db := cliente.Options().DB; db != 6 {
		t.Errorf("el cliente por centinela usa la DB %d, el contrato de Accesos dice 6", db)
	}
}
