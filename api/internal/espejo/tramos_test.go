package espejo

import (
	"context"
	"testing"
	"time"
)

// EL RELOJ DE LAS PRUEBAS ES FIJO. Los tramos son fechas contadas hacia atrás desde hoy, y
// una prueba que dependa del día en que se corra es una prueba que falla sola algún martes
// y que nadie sabe por qué.
var hoy = time.Date(2026, 9, 14, 11, 0, 0, 0, time.UTC)

// conPlazo corre `f` con un plazo y hace que un bucle infinito sea un FALLO y no un cuelgue.
//
// `Tramos` y `Trozos` son bucles que avanzan sumando un paso: si alguien rompe el paso (`d += 0`),
// se quedan dando vueltas y añadiendo a una lista para siempre. La mutación de la auditoría del
// 20/10/2026 (v-tramo-sin-siguiente) dejó la suite colgada 255 s con la memoria creciendo. Una
// función pura no se puede interrumpir desde fuera, así que se corre en su hilo y se espera con
// un temporizador; si vence, la prueba falla con un mensaje que dice qué pasó.
func conPlazo(t *testing.T, que string, f func()) {
	t.Helper()
	plazo := 500 * time.Millisecond
	if d, ok := t.Deadline(); ok {
		if resto := time.Until(d) / 2; resto < plazo {
			plazo = resto
		}
	}
	ctx, cancelar := context.WithTimeout(context.Background(), plazo)
	defer cancelar()
	hecho := make(chan struct{})
	go func() {
		defer close(hecho)
		f()
	}()
	select {
	case <-hecho:
	case <-ctx.Done():
		t.Fatalf("%s no terminó en %v: un bucle que no avanza (¿se rompió el paso `+= tramoDias`/`+= tamano`?)", que, plazo)
	}
}

func TestTramosVanDeLoNuevoALoViejo(t *testing.T) {
	// Es la propiedad que importa: si el proceso se para a mitad del recorrido, lo que ya
	// está traído tiene que ser lo RECIENTE, que es con lo que se trabaja hoy.
	var tramos []Tramo
	conPlazo(t, "Tramos(9, 0, 3)", func() { tramos = Tramos(hoy, 9, 0, 3) })
	if len(tramos) != 4 {
		t.Fatalf("se esperaban 4 tramos, salieron %d: %+v", len(tramos), tramos)
	}
	if tramos[0].Hasta != "2026-09-14" {
		t.Errorf("el primer tramo tiene que llegar hasta hoy; llegó a %s", tramos[0].Hasta)
	}
	for i := 1; i < len(tramos); i++ {
		if tramos[i].Hasta >= tramos[i-1].Hasta {
			t.Fatalf("el tramo %d (%s) no es más viejo que el anterior (%s)",
				i, tramos[i].Hasta, tramos[i-1].Hasta)
		}
	}
}

func TestElUltimoTramoNoSePasaDelHistoricoPedido(t *testing.T) {
	// Sin el recorte, el barrido traería días que nadie pidió — y al final del histórico
	// eso es pedirle a PEDIDO un año más de golpe.
	var tramos []Tramo
	conPlazo(t, "Tramos(4, 0, 3)", func() { tramos = Tramos(hoy, 4, 0, 3) })
	ultimo := tramos[len(tramos)-1]
	quiero := hoy.AddDate(0, 0, -4).Format(FormatoDeFecha)
	if ultimo.Desde != quiero {
		t.Errorf("el último tramo empieza en %s y tenía que empezar en %s (4 días atrás)", ultimo.Desde, quiero)
	}
}

func TestUnTramoDeUnSoloDiaTieneLosDosBordesIguales(t *testing.T) {
	var tramos []Tramo
	conPlazo(t, "Tramos(0, 0, 3)", func() { tramos = Tramos(hoy, 0, 0, 3) })
	if len(tramos) != 1 {
		t.Fatalf("se esperaba un tramo, salieron %d", len(tramos))
	}
	if tramos[0].Desde != tramos[0].Hasta {
		t.Errorf("un solo día tenía que ser %s..%s", tramos[0].Desde, tramos[0].Desde)
	}
}

func TestUnIntervaloAlRevesNoDevuelveNada(t *testing.T) {
	// Al revés significa que alguien se equivocó de orden en los argumentos. Devolver
	// «nada» es lo correcto: lo otro es recorrer el año entero sin que nadie lo pidiera.
	conPlazo(t, "Tramos al revés", func() {
		if tramos := Tramos(hoy, 0, 30, 3); tramos != nil {
			t.Errorf("un intervalo al revés tenía que dar nada; dio %+v", tramos)
		}
		if tramos := Tramos(hoy, 30, 0, 0); tramos != nil {
			t.Errorf("un tramo de cero días tenía que dar nada; dio %+v", tramos)
		}
	})
}

func TestElBarridoNoPisaElRepasoCorto(t *testing.T) {
	// El repaso corto ya trae los últimos días en CADA vuelta. Que el barrido empiece ahí
	// sería pedir dos veces lo mismo con la conexión de Cuba.
	desde, _ := SiguienteBarrido(0, 3, 30, 420)
	if desde != 3 {
		t.Errorf("el barrido tenía que arrancar en el día 3 (el del repaso), arrancó en %d", desde)
	}
}

func TestElBarridoSigueDondeLoDejo(t *testing.T) {
	// LA POSICIÓN SE GUARDA Y NO SE DEDUCE. Deducirla de los datos —«empieza por el pedido
	// más antiguo que tengo»— fue el fallo: el espejo ya tenía pedidos sueltos de hace un
	// año, así que arrancaba a 357 días y se saltaba entero el año de en medio.
	desde, hasta := SiguienteBarrido(120, 3, 30, 420)
	if desde != 120 || hasta != 150 {
		t.Errorf("tenía que seguir en 120..150; siguió en %d..%d", desde, hasta)
	}
}

func TestElBarridoSeParaEnElBordeDelHistorico(t *testing.T) {
	_, hasta := SiguienteBarrido(400, 3, 30, 420)
	if hasta != 420 {
		t.Errorf("no podía pasar de 420 días; llegó a %d", hasta)
	}
}

func TestAlLlegarAlFinalElBarridoVuelveAEmpezar(t *testing.T) {
	// El histórico se repasa EN BUCLE: así cualquier hueco —un tramo que falló, un día que
	// PEDIDO tocó sin avisar— se acaba tapando solo sin que nadie se dé cuenta.
	if v := AvanzarBarrido(420, 420); v != 0 {
		t.Errorf("al llegar al final tenía que volver a 0; quedó en %d", v)
	}
	if v := AvanzarBarrido(150, 420); v != 150 {
		t.Errorf("a mitad del recorrido tenía que quedarse en 150; quedó en %d", v)
	}
}

func TestMasNuevoEsLoQuePaginaElIncremental(t *testing.T) {
	// Sin esto, una tanda de más de `limit` pedidos devolvería siempre los mismos y el
	// bucle no avanzaría NUNCA: el espejo se quedaría pidiendo la misma página toda la
	// noche sin dar un solo error.
	pedidos := []PedidoDeFuera{
		{UpdatedAt: "2026-09-10T08:00:00Z"},
		{UpdatedAt: "2026-09-12T09:30:00Z"},
		{UpdatedAt: "2026-09-11T23:59:59Z"},
	}
	t1, hay := MasNuevo(pedidos)
	if !hay || !t1.Equal(time.Date(2026, 9, 12, 9, 30, 0, 0, time.UTC)) {
		t.Errorf("el más nuevo tenía que ser el del 12; salió %v (hay=%v)", t1, hay)
	}
}

func TestUnUpdatedAtIlegibleNoMueveLaMarca(t *testing.T) {
	// Adelantar la marca con una fecha que no se entiende sería saltarse pedidos para
	// siempre y sin un solo error. El pedido se guarda igual; la marca la mueve otro.
	if _, hay := MasNuevo([]PedidoDeFuera{{UpdatedAt: "ayer por la tarde"}, {UpdatedAt: ""}}); hay {
		t.Error("una fecha ilegible no puede mover la marca de agua")
	}
}

func TestTrozosParteLaTandaSinPerderNiRepetir(t *testing.T) {
	todos := make([]int, 0, 7)
	for i := range 7 {
		todos = append(todos, i)
	}
	var trozos [][]int
	conPlazo(t, "Trozos(7, 3)", func() { trozos = Trozos(todos, 3) })
	if len(trozos) != 3 || len(trozos[2]) != 1 {
		t.Fatalf("7 en trozos de 3 son 3 trozos y el último de 1; salió %+v", trozos)
	}
	visto := 0
	for _, tr := range trozos {
		visto += len(tr)
	}
	if visto != len(todos) {
		t.Errorf("se perdieron elementos: %d de %d", visto, len(todos))
	}
	conPlazo(t, "Trozos de tamaño cero o tanda vacía", func() {
		if Trozos(todos, 0) != nil || Trozos([]int{}, 3) != nil {
			t.Error("ni un tamaño de cero ni una tanda vacía pueden devolver trozos")
		}
	})
}

func TestDiaMasViejoEsElBordePorElQueSeSiguePidiendo(t *testing.T) {
	// `/integration/orders` ordena por fecha descendente y recorta por arriba, asi que lo
	// que queda por traer empieza en el mas VIEJO de lo que llego. Con el mas nuevo, o con
	// el primero de la lista, la siguiente peticion volveria a traer lo mismo.
	pedidos := []PedidoDeFuera{
		{ID: "a", Fecha: "2026-08-28T14:00:00.000Z"},
		{ID: "b", Fecha: "2026-08-26T09:30:00.000Z"},
		{ID: "c", Fecha: "2026-08-27T23:59:00.000Z"},
	}
	dia, hay := DiaMasViejo(pedidos)
	if !hay || dia != "2026-08-26" {
		t.Fatalf("el borde tenia que ser 2026-08-26; salio %q (hay=%v)", dia, hay)
	}
}

func TestSinFechaLegibleNoHayPorDondeSeguirYSeDice(t *testing.T) {
	// Devolver un dia inventado seria peor que no devolver ninguno: quien encadena se lo
	// creeria y saltaria el resto del tramo sin avisar. Aqui se dice que no hay, y el que
	// llama avisa de que el tramo se queda a medias.
	if dia, hay := DiaMasViejo([]PedidoDeFuera{{ID: "a"}, {ID: "b", Fecha: "ayer"}}); hay {
		t.Fatalf("no habia ni una fecha legible y devolvio %q", dia)
	}
	// Una sola legible entre ilegibles SI vale: las que no se entienden no estorban.
	if dia, hay := DiaMasViejo([]PedidoDeFuera{{ID: "a"}, {ID: "b", Fecha: "2026-08-26T09:30:00Z"}}); !hay || dia != "2026-08-26" {
		t.Fatalf("una fecha legible basta; salio %q (hay=%v)", dia, hay)
	}
}
