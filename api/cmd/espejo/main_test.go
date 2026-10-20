package main

import (
	"go/ast"
	"go/parser"
	"go/token"
	"go/types"
	"strings"
	"testing"

	"procovar/reparto-api/internal/espejo"
)

// LO QUE `main` COSE DEL ESPEJO, PROBADO (auditoría del 20/10/2026: `cmd/espejo` no tenía pruebas y
// dos mutaciones —quitarle a `main` el lector de Ventra y quitarle a la escucha de la cola de PEDIDO
// su condición— salían VERDES).
//
// Todo lo de `internal/espejo` pasa en verde aunque `main` no lo enchufe. Como en
// `TestMainArrancaElOyenteDelAvisoDelCRM` (internal/api), esto ANALIZA `main.go` con go/parser: un
// comentario no cuenta (`// proceso.ConFacturas(…)` pasaría una búsqueda de texto).

func funcionCorrer(t *testing.T) *ast.FuncDecl {
	t.Helper()
	f, err := parser.ParseFile(token.NewFileSet(), "main.go", nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	for _, d := range f.Decls {
		if fn, ok := d.(*ast.FuncDecl); ok && fn.Name.Name == "correr" {
			return fn
		}
	}
	t.Fatal("main.go no tiene `func correr()`")
	return nil
}

// llama dice si el bloque contiene una llamada a `nombre` (p. ej. "proceso.ConFacturas") FUERA de
// un comentario.
func llama(n ast.Node, nombre string) bool {
	hay := false
	ast.Inspect(n, func(m ast.Node) bool {
		if c, ok := m.(*ast.CallExpr); ok && types.ExprString(c.Fun) == nombre {
			hay = true
		}
		return !hay
	})
	return hay
}

// siDe devuelve el `if` de `correr` cuya condición menciona `opciones.<metodo>()`.
func siDe(t *testing.T, fn *ast.FuncDecl, metodo string) *ast.IfStmt {
	t.Helper()
	var si *ast.IfStmt
	ast.Inspect(fn.Body, func(n ast.Node) bool {
		if s, ok := n.(*ast.IfStmt); ok && si == nil && strings.Contains(types.ExprString(s.Cond), "opciones."+metodo+"()") {
			si = s
		}
		return si == nil
	})
	if si == nil {
		t.Fatalf("main.go no tiene un `if` sobre opciones.%s() (¿se quitó la condición?)", metodo)
	}
	return si
}

// evaluar calcula una condición hecha de `&&`, `||`, `!` y llamadas `opciones.X()` con las opciones
// REALES: así lo que se prueba es la condición que de verdad escribió `main`, no una copia suya.
func evaluar(t *testing.T, e ast.Expr, o espejo.Opciones) bool {
	t.Helper()
	switch x := e.(type) {
	case *ast.ParenExpr:
		return evaluar(t, x.X, o)
	case *ast.UnaryExpr:
		if x.Op == token.NOT {
			return !evaluar(t, x.X, o)
		}
	case *ast.BinaryExpr:
		switch x.Op {
		case token.LAND:
			return evaluar(t, x.X, o) && evaluar(t, x.Y, o)
		case token.LOR:
			return evaluar(t, x.X, o) || evaluar(t, x.Y, o)
		}
	case *ast.CallExpr:
		switch types.ExprString(x.Fun) {
		case "opciones.LeePedido":
			return o.LeePedido()
		case "opciones.LeeFactura":
			return o.LeeFactura()
		case "opciones.EscuchaLosAvisos":
			return o.EscuchaLosAvisos()
		}
	}
	t.Fatalf("la condición %q de main.go usa algo que esta prueba no sabe evaluar: añádelo aquí", types.ExprString(e))
	return false
}

func opcionesCon(t *testing.T, fuente string) espejo.Opciones {
	t.Helper()
	env := map[string]string{
		"SERVICE_API_KEY": "k", "SYNC_FUENTE": fuente,
		"REDIS_DIRECCION":   "redis.local:6379", // hay Redis y el interruptor del stream sigue en su valor por defecto
		"WAREHOUSE_API_URL": "http://ventra.local/api/external-api", "WAREHOUSE_API_TOKEN": "t",
	}
	o, err := espejo.Cargar(func(k string) string { return env[k] })
	if err != nil {
		t.Fatalf("SYNC_FUENTE=%s: %v", fuente, err)
	}
	return o
}

func TestMainEnchufaElLectorDeVentraSoloCuandoLaFuenteIncluyeLaFactura(t *testing.T) {
	fn := funcionCorrer(t)
	si := siDe(t, fn, "LeeFactura")
	if !llama(si.Body, "proceso.ConFacturas") {
		t.Fatal("el `if opciones.LeeFactura()` de main.go no llama a proceso.ConFacturas(…): con SYNC_FUENTE=factura|ambas " +
			"el espejo se negaría a arrancar (o, peor, no traería ni una factura)")
	}
	// El lector que se enchufa es el de Ventra de verdad, no un nil ni un doble.
	if !llama(si.Body, "ventra.Nuevo") {
		t.Error("main.go no construye el lector con ventra.Nuevo(…)")
	}
	// Y ConFacturas NO se llama fuera de ese `if` (con la fuente `pedido` no se monta nada).
	fuera := 0
	ast.Inspect(fn.Body, func(n ast.Node) bool {
		if n == si {
			return false
		}
		if c, ok := n.(*ast.CallExpr); ok && types.ExprString(c.Fun) == "proceso.ConFacturas" {
			fuera++
		}
		return true
	})
	if fuera != 0 {
		t.Errorf("proceso.ConFacturas se llama fuera de `if opciones.LeeFactura()` %d vez/veces: con SYNC_FUENTE=pedido no se monta Ventra", fuera)
	}
	// La condición, evaluada con las opciones reales: sólo `factura` y `ambas`.
	for fuente, quiere := range map[string]bool{"pedido": false, "factura": true, "ambas": true} {
		if got := evaluar(t, si.Cond, opcionesCon(t, fuente)); got != quiere {
			t.Errorf("SYNC_FUENTE=%s: el lector de Ventra se enchufa=%v y tenía que ser %v", fuente, got, quiere)
		}
	}
}

func TestMainEscuchaLaColaDePedidoSoloSiPedidoEsFuente(t *testing.T) {
	fn := funcionCorrer(t)
	si := siDe(t, fn, "EscuchaLosAvisos")

	// Lo que cuelga de la condición es de verdad la escucha: el escuchador, en su hilo, leyendo la cola.
	if !llama(si.Body, "espejo.NuevoEscuchador") {
		t.Error("el `if` de la escucha no construye espejo.NuevoEscuchador(…)")
	}
	enSuHilo := false
	ast.Inspect(si.Body, func(n ast.Node) bool {
		if g, ok := n.(*ast.GoStmt); ok && llama(g.Call, "escuchador.Correr") {
			enSuHilo = true
		}
		return true
	})
	if !enSuHilo {
		t.Error("el `if` de la escucha no hace `go … escuchador.Correr(ctx)`: la cola no se leería")
	}
	// Y lo que llega por la cola se atiende con el espejo.
	if !llama(si.Body, "proceso.Atender") {
		t.Error("el escuchador no llama a proceso.Atender: se leería la cola y no se haría nada con los avisos")
	}

	// LA CONDICIÓN DE main.go, evaluada: con SYNC_FUENTE=factura NO se escucha la cola de PEDIDO
	// (sus avisos traerían pedidos de PEDIDO por la puerta de atrás); con `pedido` y `ambas` sí.
	casos := []struct {
		fuente string
		quiere bool
	}{{"pedido", true}, {"ambas", true}, {"factura", false}}
	for _, c := range casos {
		if got := evaluar(t, si.Cond, opcionesCon(t, c.fuente)); got != c.quiere {
			t.Errorf("SYNC_FUENTE=%s (con Redis): se escucha la cola de PEDIDO=%v y tenía que ser %v. Condición de main.go: %s",
				c.fuente, got, c.quiere, types.ExprString(si.Cond))
		}
	}
	// Sin Redis, con ninguna fuente se escucha.
	sinRedis, err := espejo.Cargar(func(k string) string { return map[string]string{"SERVICE_API_KEY": "k"}[k] })
	if err != nil {
		t.Fatal(err)
	}
	if evaluar(t, si.Cond, sinRedis) {
		t.Error("sin Redis configurado no se escucha nada")
	}
}

func TestMainArrancaElCicloDelEspejo(t *testing.T) {
	// El ciclo de facturas lo arranca `proceso.Correr` (y `Ciclo` en --once) y decide por
	// `opciones.LeeFactura()` dentro de internal/espejo (ciclo.go); lo que `main` tiene que hacer es
	// llamarlos, en los dos modos.
	fn := funcionCorrer(t)
	if !llama(fn.Body, "proceso.Correr") {
		t.Error("main.go no llama a proceso.Correr(ctx): el espejo no daría ni una vuelta")
	}
	if !llama(fn.Body, "proceso.Ciclo") {
		t.Error("main.go no llama a proceso.Ciclo(ctx) en el modo --once")
	}
}
