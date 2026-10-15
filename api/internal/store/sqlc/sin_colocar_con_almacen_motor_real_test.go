package sqlc

// «SIN COLOCAR» CON UN ALMACÉN ELEGIDO ARRIBA, CONTRA POSTGRES DE VERDAD (Jose, 15/10/2026).
//
// Con un almacén elegido en la cabecera del tablero (que no sea el de por defecto) van
// PRIMERO los pedidos de ese almacén, del más cercano al más lejano, y DESPUÉS los demás por
// la fecha de su factura. Los casos son los de `docs/orden-sin-colocar.casos.json`, el MISMO
// fichero que lee el aparato (`orden_sin_colocar_con_almacen_test.dart`): si el SQL y la
// lista local se separan, se separan contra el mismo fichero y salta uno de los dos.
//
// Lo que se mira, por caso: la lista entera sale en el orden `esperado`, el contador dice lo
// mismo que la lista (el orden no cambia cuántos son), y paginando de 1 en 1, de 2 en 2… por el
// cursor (`cercania|fecha|id`) sale la lista entera, sin repetir ni saltar, también donde la
// tanda se corta justo entre el último del almacén y el primero de los demás.
//
// De qué almacén van primero (`primeroLosDe`) lo decide `almacenDeLaCabecera` en
// `internal/api`, y eso lo ata `orden_sin_colocar_casos_compartidos_test.go` con el mismo
// fichero. Aquí se toma del caso.
//
// Mismas reglas que el resto de este paquete: sólo con `REPARTO_MOTOR_REAL_DSN`, una
// transacción por prueba y se revierte.

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
)

type casosDelOrdenSinColocar struct {
	Almacenes []struct {
		ID        string  `json:"id"`
		Codigo    *string `json:"codigo"`
		Principal bool    `json:"principal"`
		Latitud   float64 `json:"latitud"`
		Longitud  float64 `json:"longitud"`
	} `json:"almacenes"`
	Pedidos []struct {
		Nombre        string     `json:"nombre"`
		ID            string     `json:"id"`
		AlmacenCodigo *string    `json:"almacenCodigo"`
		Mezclado      bool       `json:"mezclado"`
		Latitud       float64    `json:"latitud"`
		Longitud      float64    `json:"longitud"`
		FacturaAt     *time.Time `json:"facturaAt"`
		OrderDate     *time.Time `json:"orderDate"`
	} `json:"pedidos"`
	Casos []struct {
		Nombre       string   `json:"nombre"`
		Elegido      *string  `json:"elegido"`
		PrimeroLosDe *string  `json:"primeroLosDe"`
		Esperado     []string `json:"esperado"`
	} `json:"casos"`
}

func leerCasosDelOrdenSinColocar(t *testing.T) casosDelOrdenSinColocar {
	t.Helper()
	ruta := filepath.Join("..", "..", "..", "..", "docs", "orden-sin-colocar.casos.json")
	b, err := os.ReadFile(ruta)
	if err != nil {
		t.Fatalf("no se pudo leer %s: %v", ruta, err)
	}
	var c casosDelOrdenSinColocar
	if err := json.Unmarshal(b, &c); err != nil {
		t.Fatalf("%s no se entiende: %v", ruta, err)
	}
	if len(c.Casos) == 0 || len(c.Pedidos) == 0 {
		t.Fatalf("%s viene sin casos o sin pedidos: una prueba sin casos sale verde sin probar nada", ruta)
	}
	return c
}

func TestMotorReal_SinColocarConAlmacenElegido(t *testing.T) {
	pool := motorReal(t)
	casos := leerCasosDelOrdenSinColocar(t)
	b := nuevoBanco(t, pool)
	suc := b.sucursal()

	nombreDe := map[uuid.UUID]string{}
	for _, p := range casos.Pedidos {
		creado := b.pedido(listo(p.Nombre, suc))
		id := uuid.MustParse(p.ID)
		b.exec(`UPDATE orders SET id = $2, end_lat = $3, end_lng = $4, almacen_salida_codigo = $5,
		        almacen_salida_mezclado = $6, factura_at = $7, order_date = $8 WHERE id = $1`,
			creado, id, p.Latitud, p.Longitud, p.AlmacenCodigo, p.Mezclado, p.FacturaAt, p.OrderDate)
		nombreDe[id] = p.Nombre
	}

	// Se mide desde el elegido; sin elegir, desde el de por defecto (el principal).
	origen := func(elegido *string) (float64, float64) {
		for _, a := range casos.Almacenes {
			if (elegido != nil && a.ID == *elegido) || (elegido == nil && a.Principal) {
				return a.Latitud, a.Longitud
			}
		}
		t.Fatalf("el caso elige %v y no está entre los almacenes del fichero", *elegido)
		return 0, 0
	}

	for _, caso := range casos.Casos {
		t.Run(caso.Nombre, func(t *testing.T) {
			lat, lng := origen(caso.Elegido)
			pedir := func(limite int32, desde *FilaDeCursor) []ListarPedidosSinColocarRow {
				arg := ListarPedidosSinColocarParams{
					OrigenLat: lat, OrigenLng: lng, PrimeroCodigo: caso.PrimeroLosDe,
					BranchID: suc, Sucursal: sinAlcance, Limite: limite,
				}
				if desde != nil {
					arg.DesdeID = pgtype.UUID{Bytes: desde.id, Valid: true}
					arg.DesdeCercania = &desde.cercania
					arg.DesdeFecha = desde.fecha
				}
				filas, err := b.q.ListarPedidosSinColocar(b.ctx, arg)
				if err != nil {
					t.Fatal(err)
				}
				return filas
			}
			nombres := func(filas []ListarPedidosSinColocarRow) []string {
				var salida []string
				for _, f := range filas {
					salida = append(salida, nombreDe[f.ID])
				}
				return salida
			}

			entera := pedir(100, nil)
			igualesTxt(t, "ListarPedidosSinColocar", nombres(entera), caso.Esperado)

			total, err := b.q.ContarPedidosSinColocar(b.ctx, ContarPedidosSinColocarParams{
				OrigenLat: lat, OrigenLng: lng, PrimeroCodigo: caso.PrimeroLosDe,
				BranchID: suc, Sucursal: sinAlcance,
			})
			if err != nil {
				t.Fatal(err)
			}
			if int(total) != len(entera) {
				t.Errorf("ContarPedidosSinColocar = %d y la lista trae %d: el orden no puede cambiar cuántos son",
					total, len(entera))
			}

			// TODAS las tandas posibles: alguna corta justo en la frontera entre los del
			// almacén y los demás, que es donde un cursor sin la cercanía repite o salta.
			for limite := int32(1); limite <= int32(len(caso.Esperado)); limite++ {
				var salida []string
				var desde *FilaDeCursor
				for vuelta := 0; ; vuelta++ {
					if vuelta > 20 {
						t.Fatalf("de %d en %d: el cursor no avanza, van %v", limite, limite, salida)
					}
					filas := pedir(limite, desde)
					if len(filas) == 0 {
						break
					}
					salida = append(salida, nombres(filas)...)
					u := filas[len(filas)-1]
					desde = &FilaDeCursor{id: u.ID, cercania: u.CercaniaDeOrden, fecha: u.FechaCronologica}
				}
				igualesTxt(t, fmt.Sprintf("las tandas de %d unidas", limite), salida, caso.Esperado)
			}
		})
	}
}
