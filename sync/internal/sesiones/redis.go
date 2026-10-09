package sesiones

import (
	"context"
	"errors"
	"net"
	"strconv"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"

	"procovar/reparto-sync/internal/config"
)

// Los plazos de la conexión real. Variables para que las pruebas con un Redis de verdad no esperen
// medio minuto.
var (
	// plazoDeConexion: lo que se espera a que Redis confirme la suscripción, o a que termine el SCAN.
	plazoDeConexion = 10 * time.Second
	// latidoDeLectura: cada cuánto, sin recibir nada, se manda un PING por la suscripción. NO ES UN
	// SONDEO de datos: es lo que hace que una conexión muerta a medias (un failover del centinela sin
	// FIN) se note a los ~2 latidos y no se quede "escuchando" para siempre sin oír nada.
	latidoDeLectura = 30 * time.Second
	// tamanoDeLote: cuántas claves por SCAN / MGET.
	tamanoDeLote = 200
)

// DeRedis monta la fuente real contra el Redis de la casa. Devuelve un `nil` de verdad si no hay
// nada configurado. LA MISMA FORMA que el espejo y que `reparto-api`: por centinela si hay
// centinelas, y directo si no (local). La base es SIEMPRE [BaseDeLasMarcas].
func DeRedis(c config.Redis) Fuente {
	if !c.Hay() {
		return nil
	}
	if len(c.Centinelas) > 0 {
		return &fuenteRedis{c: redis.NewFailoverClient(&redis.FailoverOptions{
			MasterName:    c.Maestro,
			SentinelAddrs: c.Centinelas,
			Password:      c.Clave,
			DB:            BaseDeLasMarcas,
		})}
	}
	return &fuenteRedis{c: redis.NewClient(&redis.Options{
		Addr:     c.Direccion,
		Password: c.Clave,
		DB:       BaseDeLasMarcas,
	})}
}

type fuenteRedis struct{ c redis.UniversalClient }

func (f *fuenteRedis) Cerrar() error { return f.c.Close() }

func (f *fuenteRedis) Suscribir(ctx context.Context) (Suscripcion, error) {
	// `Subscribe` y la confirmación corren aparte, y aquí se espera a lo que pase antes: que termine o
	// que se cancele `ctx`. Con un Redis colgado —acepta y no contesta— go-redis hace el saludo de la
	// conexión con el candado del PubSub tomado, ni `ps.Close()` ni cerrar el cliente lo sueltan, y
	// sólo lo deja ir su plazo (hasta `plazoDeConexion`, 10 s) mientras el apagado de `main` espera
	// 2 s. Así `Correr` vuelve en el acto al cancelar, y lo que quede del intento se cierra solo.
	type resultado struct {
		ps  *redis.PubSub
		err error
	}
	salida := make(chan resultado, 1)
	go func() {
		ps := f.c.Subscribe(ctx, Canal)
		espera, cancelar := context.WithTimeout(ctx, plazoDeConexion)
		defer cancelar()
		// `Subscribe` no espera respuesta ni cuenta si falló: la confirmación es lo primero que llega.
		_, err := ps.Receive(espera)
		salida <- resultado{ps, err}
	}()

	select {
	case r := <-salida:
		if r.err != nil {
			_ = r.ps.Close()
			return nil, r.err
		}
		// Cancelar ctx cierra la conexión: sin esto la lectura bloqueada no se enteraría de que hay
		// que salir hasta el siguiente latido.
		parar := context.AfterFunc(ctx, func() { _ = r.ps.Close() })
		return &suscripcionRedis{ps: r.ps, parar: parar}, nil
	case <-ctx.Done():
		go func() { _ = (<-salida).ps.Close() }()
		return nil, ctx.Err()
	}
}

// Marcas: SCAN de las marcas `todo` y MGET de sus valores, por lotes. Un valor que no es un entero
// positivo se salta. La familia `web` NO se carga: no le toca a este servicio.
func (f *fuenteRedis) Marcas(ctx context.Context) (map[string]int64, error) {
	ctx, cancelar := context.WithTimeout(ctx, plazoDeConexion)
	defer cancelar()

	var claves []string
	it := f.c.Scan(ctx, 0, PrefijoDeMarcaTodo+"*", int64(tamanoDeLote)).Iterator()
	for it.Next(ctx) {
		claves = append(claves, it.Val())
	}
	if err := it.Err(); err != nil {
		return nil, err
	}

	salida := make(map[string]int64, len(claves))
	for i := 0; i < len(claves); i += tamanoDeLote {
		lote := claves[i:min(i+tamanoDeLote, len(claves))]
		valores, err := f.c.MGet(ctx, lote...).Result()
		if err != nil {
			return nil, err
		}
		for j, v := range valores {
			texto, _ := v.(string) // nil = la clave caducó entre el SCAN y el MGET
			if tms, err := strconv.ParseInt(texto, 10, 64); err == nil && tms > 0 {
				salida[strings.TrimPrefix(lote[j], PrefijoDeMarcaTodo)] = tms
			}
		}
	}
	return salida, nil
}

type suscripcionRedis struct {
	ps    *redis.PubSub
	parar func() bool
	// sinRespuesta: ya mandé un PING y todavía no ha vuelto nada.
	sinRespuesta bool
}

func (s *suscripcionRedis) Cerrar() error {
	s.parar()
	return s.ps.Close()
}

// Siguiente devuelve el próximo mensaje. Cada `latidoDeLectura` de silencio manda un PING; si ni con
// eso llega nada en otro latido, la conexión se da por muerta.
func (s *suscripcionRedis) Siguiente(ctx context.Context) (string, error) {
	for {
		m, err := s.ps.ReceiveTimeout(ctx, latidoDeLectura)
		if err != nil {
			var red net.Error
			if ctx.Err() == nil && errors.As(err, &red) && red.Timeout() {
				if s.sinRespuesta {
					return "", errors.New("Redis no contesta al PING de la suscripción")
				}
				if err := s.ps.Ping(ctx); err != nil {
					return "", err
				}
				s.sinRespuesta = true
				continue
			}
			return "", err
		}
		s.sinRespuesta = false
		if msg, ok := m.(*redis.Message); ok {
			return msg.Payload, nil
		}
	}
}
