package avisoscrm

import (
	"context"
	"errors"
	"net"
	"time"

	"github.com/redis/go-redis/v9"

	"procovar/reparto-api/internal/config"
)

// plazoDeConexion y latidoDeLectura: lo mismo que `internal/sesiones` y por lo mismo (un Redis que
// acepta y no contesta, o una conexión muerta a medias tras un failover del centinela, no pueden
// dejar esto «escuchando» para siempre sin oír nada). Variables para que las pruebas no esperen.
var (
	plazoDeConexion = 10 * time.Second
	latidoDeLectura = 30 * time.Second
)

// DeRedis monta la fuente real contra el Redis de la casa, con LAS MISMAS `REDIS_*` que el espejo y
// las sesiones: por centinela si hay centinelas y directo si no. Devuelve un `nil` de verdad (no un
// puntero nulo dentro de la interfaz) si no hay nada configurado.
//
// LA BASE NO IMPORTA: el pub/sub de Redis no pertenece a ninguna base. Se usa la 0.
func DeRedis(c config.Redis) Fuente {
	if !c.Hay() {
		return nil
	}
	if len(c.Centinelas) > 0 {
		return &fuenteRedis{c: redis.NewFailoverClient(&redis.FailoverOptions{
			MasterName:    c.Maestro,
			SentinelAddrs: c.Centinelas,
			Password:      c.Clave,
		})}
	}
	return &fuenteRedis{c: redis.NewClient(&redis.Options{Addr: c.Direccion, Password: c.Clave})}
}

type fuenteRedis struct{ c redis.UniversalClient }

func (f *fuenteRedis) Cerrar() error { return f.c.Close() }

// Suscribir: la suscripción y su confirmación corren aparte y aquí se espera a lo que pase antes, o a
// que se cancele ctx. Ver el porqué entero en `sesiones.fuenteRedis.Suscribir`: con un Redis colgado,
// go-redis hace el saludo con el candado del PubSub tomado y ni cerrarlo lo suelta.
func (f *fuenteRedis) Suscribir(ctx context.Context) (Suscripcion, error) {
	type resultado struct {
		ps  *redis.PubSub
		err error
	}
	salida := make(chan resultado, 1)
	go func() {
		ps := f.c.Subscribe(ctx, Canal)
		espera, cancelar := context.WithTimeout(ctx, plazoDeConexion)
		defer cancelar()
		_, err := ps.Receive(espera) // la confirmación del SUBSCRIBE es lo primero que llega
		salida <- resultado{ps, err}
	}()

	select {
	case r := <-salida:
		if r.err != nil {
			_ = r.ps.Close()
			return nil, r.err
		}
		parar := context.AfterFunc(ctx, func() { _ = r.ps.Close() })
		return &suscripcionRedis{ps: r.ps, parar: parar}, nil
	case <-ctx.Done():
		go func() { _ = (<-salida).ps.Close() }()
		return nil, ctx.Err()
	}
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
// eso llega nada en otro latido, la conexión se da por muerta. No es un sondeo de datos.
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
