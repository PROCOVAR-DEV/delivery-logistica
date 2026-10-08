package store

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// LA MIGRACION 00016 ESTA ATADA A LO QUE HACE, NO SOLO A QUE EXISTE.
//
// La auditoría del 08/10/2026 mutó `ON DELETE CASCADE` a `ON DELETE RESTRICT` en
// `db/migrations/00016_origenes_ruta_tablero.sql` y TODO siguió en verde: las pruebas de
// motor real (`consultas_motor_real_test.go`) corren contra una base que ya está
// migrada, no contra el fichero, y sin `REPARTO_MOTOR_REAL_DSN` ni siquiera corren. Nada
// ataba el `.sql` al comportamiento.
//
// Lo que está en juego: con `RESTRICT`, borrar una zona VACÍA que tiene una ruta
// planificada nacida de ella sale como el 409 «tiene 0 pedidos puestos», que es falso y
// no se puede resolver (`esRestriccionDeColumna`, `tablero.go`). Con `CASCADE` la zona se
// borra y su origen se va con ella; borrar la ruta después sólo no restaura a una zona que
// ya no existe, que es lo correcto.
//
// Es una prueba de TEXTO: no ejecuta la migración. Lo hace la de motor real. Aquí sólo se
// vigila que nadie vuelva a escribir `RESTRICT` sin que algo lo diga.
func TestOrigenesDeRutaSeVanConSuZona(t *testing.T) {
	b, err := os.ReadFile(filepath.Join("..", "..", "db", "migrations", "00016_origenes_ruta_tablero.sql"))
	if err != nil {
		t.Fatal(err)
	}
	// Sólo la sección Up: el Down no declara claves ajenas.
	sql := string(b)
	if i := strings.Index(sql, "-- +goose Down"); i >= 0 {
		sql = sql[:i]
	}
	re := regexp.MustCompile(`column_id\s+uuid\s+NOT NULL\s+REFERENCES\s+board_columns\s*\(id\)\s+ON DELETE\s+(\w+)`)
	m := re.FindStringSubmatch(sql)
	if m == nil {
		t.Fatalf("no se encontró la clave ajena `column_id … REFERENCES board_columns(id) ON DELETE …` " +
			"en 00016_origenes_ruta_tablero.sql: si la reescribiste, actualiza esta prueba")
	}
	if !strings.EqualFold(m[1], "CASCADE") {
		t.Fatalf("board_route_origins.column_id es ON DELETE %s y tiene que ser CASCADE: con %s, borrar una "+
			"zona vacía con una ruta planificada da el 409 falso «tiene 0 pedidos puestos»", m[1], m[1])
	}
	// Y la pareja: las otras dos claves ajenas siguen en CASCADE, para que borrar la ruta o
	// el pedido no deje orígenes huérfanos.
	for _, tabla := range []string{"routes", "orders"} {
		pat := regexp.MustCompile(`REFERENCES\s+` + tabla + `\s*\(id\)\s+ON DELETE\s+CASCADE`)
		if !pat.MatchString(sql) {
			t.Errorf("falta `REFERENCES %s(id) ON DELETE CASCADE` en 00016: un origen se quedaría huérfano", tabla)
		}
	}
}
