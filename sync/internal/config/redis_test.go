package config

import (
	"reflect"
	"testing"
)

func entornoDe(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

// LOS NOMBRES Y LA FORMA SON LOS DEL ESPEJO (`espejo.Opciones`): copiar las variables de un
// servicio al otro no admite equivocación. La base NO se lee: las marcas de Accesos van en la DB 6.
func TestRedisSeLeeConLosNombresDelEspejo(t *testing.T) {
	r := leerRedis(entornoDe(map[string]string{
		"REDIS_CENTINELAS": " s1:26379, s2:26379 ,, ",
		"REDIS_MAESTRO":    "procovar-master",
		"REDIS_CLAVE":      "secreta",
		"REDIS_BASE":       "2", // la del espejo: aquí no pinta nada
	}))
	if !r.Hay() {
		t.Fatal("con centinelas puestos tenía que haber Redis")
	}
	if !reflect.DeepEqual(r.Centinelas, []string{"s1:26379", "s2:26379"}) {
		t.Errorf("centinelas: %v", r.Centinelas)
	}
	if r.Maestro != "procovar-master" || r.Clave != "secreta" {
		t.Errorf("maestro %q, clave %q", r.Maestro, r.Clave)
	}
}

func TestRedisURLDaHostYClaveYSuBaseSeIgnora(t *testing.T) {
	r := leerRedis(entornoDe(map[string]string{"REDIS_URL": "redis://:secreta@procovar-redis:6379/2"}))
	if r.Direccion != "procovar-redis:6379" || r.Clave != "secreta" {
		t.Errorf("dirección %q, clave %q", r.Direccion, r.Clave)
	}
	// Las sueltas mandan sobre la URL, como en el espejo.
	r = leerRedis(entornoDe(map[string]string{
		"REDIS_URL": "redis://:vieja@a:6379", "REDIS_DIRECCION": "b:6379", "REDIS_CLAVE": "nueva",
	}))
	if r.Direccion != "b:6379" || r.Clave != "nueva" {
		t.Errorf("las sueltas no mandaron sobre la URL: %+v", r)
	}
}

func TestSinRedisNoHayRedis(t *testing.T) {
	if r := leerRedis(entornoDe(nil)); r.Hay() {
		t.Errorf("se inventó un Redis: %+v", r)
	}
}
