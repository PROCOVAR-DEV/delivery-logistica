package api

import (
	"reflect"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

// EL CONTADOR TIENE QUE RECIBIR LOS MISMOS FILTROS QUE LA LISTA.
//
// `internal/store/contador_y_lista_test.go` compara los dos `WHERE` y los dos
// `FROM` del SQL, y con eso basta para el SQL. Pero los parámetros se copian a
// mano en Go, y eso no lo miraba nadie: el auditor quitó `Municipio:` el
// 17/09/2026 y `go build && go vet && go test ./...` de `api/` entero quedó en
// verde. Con el filtro de municipio puesto, la lista enseñaría un municipio y el
// número contaría la sucursal entera — el «Sin colocar (722) encima de una lista
// de 293» otra vez, en el fichero de al lado.
//
// Se comprueba POR REFLEXIÓN y no campo por campo escrito a mano, a propósito:
// una lista escrita a mano hay que acordarse de ampliarla, y el día que se
// olvide es el día que vuelve el fallo. Así, un campo nuevo en la consulta entra
// solo — y si de verdad no tiene que copiarse, hay que venir aquí y decir por
// qué, que es justo la conversación que hay que tener.
func TestElContadorRecibeLosMismosFiltrosQueLaLista(t *testing.T) {
	// Los que NO se copian, con su razón. El número de arriba es el TOTAL
	// —«Sin colocar (300)»— y no puede bajar a 100 porque alguien haya pedido la
	// tanda siguiente, así que el cursor se queda fuera.
	noSeCopian := map[string]string{
		"DesdeID":    "el cursor: el total no se pagina, o el número bajaría al desplazarse",
		"DesdeFecha": "el cursor: ídem",
		// La cercanía del cursor (15/10/2026). `PrimeroCodigo` SÍ se copia: es del `WHERE`.
		"DesdeCercania": "el cursor: ídem",
		"Limite":        "el tope es de la lista; el contador cuenta todo",
	}

	lista := reflect.New(reflect.TypeOf(sqlc.ListarPedidosSinColocarParams{})).Elem()

	// Se rellena CADA campo de la lista con un valor distinto de su cero **y
	// distinto del de sus hermanos del mismo tipo**, por el nombre del campo.
	//
	// La primera versión daba el mismo valor a todos los campos del mismo tipo, y
	// así `Municipio: arg.Vendedor, Vendedor: arg.Municipio` —el error de copia y
	// pega más normal que hay— pasaba limpio: toda la api en verde y el mismo
	// número creíble y equivocado. Lo cazó el auditor.
	tipoLista := lista.Type()
	for i := 0; i < lista.NumField(); i++ {
		rellenar(lista.Field(i), tipoLista.Field(i).Name)
	}

	contador := reflect.ValueOf(
		paramsDelContador(lista.Interface().(sqlc.ListarPedidosSinColocarParams)),
	)

	tipo := contador.Type()
	for i := 0; i < tipo.NumField(); i++ {
		nombre := tipo.Field(i).Name
		if razon, esperado := noSeCopian[nombre]; esperado {
			if !contador.Field(i).IsZero() {
				t.Errorf(
					"«%s» NO debía copiarse (%s) y llegó con valor. Si has cambiado "+
						"de idea, cambia también la razón de esta prueba.",
					nombre, razon,
				)
			}
			continue
		}
		deLaLista := lista.FieldByName(nombre)
		if !deLaLista.IsValid() {
			continue // Un campo que sólo tiene el contador; no hay nada que copiar.
		}
		if !reflect.DeepEqual(contador.Field(i).Interface(), deLaLista.Interface()) {
			t.Errorf(
				"«%s» no llega al contador.\n"+
					"  la lista filtra por él y el número NO, así que el número saldría "+
					"por encima de lo que hay debajo — el mismo fallo del «Sin colocar "+
					"(722)» encima de una lista de 293.\n"+
					"  Cópialo en paramsDelContador, o si de verdad no debe copiarse, "+
					"añádelo a `noSeCopian` con su razón.",
				nombre,
			)
		}
	}
}

// rellenar pone en un campo algo que NO es su cero, sea del tipo que sea.
//
// Hace falta porque un cero copiado y un cero olvidado se ven igual: si la lista
// llegara con todo a cero, la prueba pasaría con la función vacía.
func rellenar(campo reflect.Value, nombre string) {
	// El valor sale del NOMBRE del campo, no sólo de su tipo. Si no, dos campos
	// del mismo tipo intercambiados se ven idénticos y el cambiazo pasa limpio.
	huella := huellaDe(nombre)
	switch campo.Interface().(type) {
	case uuid.UUID:
		campo.Set(reflect.ValueOf(uuidCon(huella)))
	case pgtype.UUID:
		campo.Set(reflect.ValueOf(pgtype.UUID{Bytes: uuidCon(huella), Valid: true}))
	case pgtype.Timestamptz:
		campo.Set(reflect.ValueOf(pgtype.Timestamptz{
			Time:  time.Date(2026, 9, 17, 11, 0, 0, 0, time.UTC).Add(time.Duration(huella) * time.Second),
			Valid: true,
		}))
	case *string:
		s := "valor de " + nombre
		campo.Set(reflect.ValueOf(&s))
	case *float64:
		f := 10 + float64(huella)
		campo.Set(reflect.ValueOf(&f))
	case *int32:
		n := int32(100 + huella)
		campo.Set(reflect.ValueOf(&n))
	case float64:
		campo.SetFloat(20 + float64(huella))
	case int32:
		campo.SetInt(int64(100 + huella))
	case string:
		campo.SetString("valor de " + nombre)
	}
	// Un tipo que no se sepa rellenar se queda a cero y el campo no prueba nada.
	// Es preferible a fallar aquí: lo que hay que ver es el campo que falta, y
	// el día que aparezca un tipo nuevo se añade a este `switch`.
}

// huellaDe convierte el nombre del campo en un número pequeño y estable, para
// que cada campo lleve un valor distinto del de sus hermanos del mismo tipo.
func huellaDe(nombre string) int {
	suma := 0
	for _, c := range nombre {
		suma += int(c)
	}
	return suma % 997
}

func uuidCon(huella int) uuid.UUID {
	var u uuid.UUID
	u[0] = byte(huella >> 8)
	u[1] = byte(huella)
	u[15] = 1 // Que nunca sea el uuid cero, que es el valor por defecto.
	return u
}
