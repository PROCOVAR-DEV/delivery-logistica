package store

import (
	"strings"
	"testing"
)

// LA PRUEBA QUE VIGILA A LA PRUEBA.
//
// `contador_y_lista_test.go` compara el `WHERE` del contador con el de la lista, y para
// eso lee cada consulta «desde su `-- name:` hasta el punto y coma que la cierra». Eso deja
// una trampa que no avisa: un punto y coma DENTRO DE UN COMENTARIO —y los comentarios de
// este proyecto son largos y en castellano, donde el punto y coma es normal— le corta el
// cuerpo por ahí, y todo lo que venga después deja de compararse. En verde. Sin decir nada.
//
// No es hipotético: pasó el 18/09/2026, al escribir el cursor de la mitad izquierda. Las
// cuatro líneas que explican la terna del cursor llevaban «; o» al final, el cuerpo se
// cortaba justo antes del `AND (...)` del cursor, y se pudo QUITAR ESE TROZO ENTERO DEL
// CONTADOR sin que la comparación se enterara. Dicho de otro modo: la prueba que existe
// para que el número no se separe de la lista se había quedado dormida, y el fallo que
// vigila —«722» encima de una lista de 293— habría vuelto a pasar igual.
//
// Así que se comprueba lo que la otra prueba da por hecho: que cada consulta se lee ENTERA.
// El corte de verdad está al final del `WHERE`, y la última condición de las dos es la de
// `km_max`. Si el cuerpo no llega hasta ahí, alguien metió un punto y coma por el camino.
func TestLasDosConsultasSeLeenEnteras(t *testing.T) {
	sql := leerConsultas(t)

	for _, nombre := range []string{"ListarPedidosSinColocar", "ContarPedidosSinColocar"} {
		cuerpo := cuerpoDe(t, sql, nombre)

		// El final de verdad del `WHERE`. Si esto no está, el cuerpo se cortó antes.
		for _, imprescindible := range []string{"km_max", "desde_id", "o.branch_id"} {
			if !strings.Contains(cuerpo, imprescindible) {
				t.Errorf(
					"el cuerpo de %s se corta antes de «%s».\n"+
						"Casi seguro que hay un PUNTO Y COMA dentro de un comentario de esa "+
						"consulta: la comparación entre el contador y la lista lee hasta el "+
						"primero que encuentra, así que desde ahí deja de comparar y se queda "+
						"en verde pase lo que pase. Quítalo del comentario.\n"+
						"Leído: ...%s",
					nombre, imprescindible, cola(cuerpo, 200),
				)
			}
		}
	}
}

// Y LAS DOS TIENEN QUE LLEVAR EL CURSOR, no sólo la lista.
//
// El cursor no está en el contador porque haga falta para contar —quien llama le pasa
// siempre nulo, porque el número de arriba es el TOTAL y no lo que queda de la tanda—, sino
// para que los dos `WHERE` sigan siendo el MISMO TEXTO. Ése es el único vigilante que tiene
// el número. Quitarlo de uno de los dos rompe el contrato aunque el SQL siga siendo válido.
func TestElCursorEstaEnLasDosConsultas(t *testing.T) {
	sql := leerConsultas(t)

	for _, nombre := range []string{"ListarPedidosSinColocar", "ContarPedidosSinColocar"} {
		cuerpo := cuerpoDe(t, sql, nombre)
		for _, trozo := range []string{"desde_id", "desde_fecha"} {
			if !strings.Contains(cuerpo, trozo) {
				t.Errorf("a %s le falta «%s» del cursor.\n"+
					"Los dos `WHERE` tienen que ser el mismo texto o el número de arriba "+
					"puede volver a separarse de la lista sin que nadie se entere.",
					nombre, trozo)
			}
		}
	}
}

func cola(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[len(s)-n:]
}
