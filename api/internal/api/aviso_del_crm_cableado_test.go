package api

import (
	"go/ast"
	"go/parser"
	"go/token"
	"go/types"
	"testing"
)

// EL OYENTE DEL AVISO DEL CRM ESTÁ COSIDO EN `main`, PROBADO.
//
// `cmd/api` no tiene pruebas, y todo lo de `internal/avisoscrm` y `CambiaronLosAlmacenes` pasa en verde
// aunque `main` no arranque el oyente: sin esa línea, un punto de almacén corregido en el CRM se seguiría
// midiendo —y cobrando— desde el viejo hasta que caduque el recuerdo de 5 minutos, y ninguna prueba lo
// notaría. Igual que `TestMainConstruyeElServidorConElEmpujeDeAccesos`, esto ANALIZA `main.go` con
// go/parser: un comentario no cuenta (`// go avisoscrm.Correr(…)` pasaría una búsqueda de texto).
func TestMainArrancaElOyenteDelAvisoDelCRM(t *testing.T) {
	f, err := parser.ParseFile(token.NewFileSet(), "../../cmd/api/main.go", nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	correEnSuHilo, conRedisReal, avisaALosAlmacenes := false, false, false
	ast.Inspect(f, func(n ast.Node) bool {
		g, ok := n.(*ast.GoStmt)
		if !ok || types.ExprString(g.Call.Fun) != "avisoscrm.Correr" {
			return true
		}
		correEnSuHilo = true
		for _, a := range g.Call.Args {
			// La fuente: una LLAMADA a DeRedis con la configuración de verdad (ni nil ni una de memoria).
			if c, ok := a.(*ast.CallExpr); ok && types.ExprString(c) == "avisoscrm.DeRedis(cfg.Redis)" {
				conRedisReal = true
			}
			// El efecto: la función que se le pasa tiene que llamar a api.CambiaronLosAlmacenes.
			if fn, ok := a.(*ast.FuncLit); ok {
				ast.Inspect(fn.Body, func(m ast.Node) bool {
					if c, ok := m.(*ast.CallExpr); ok && types.ExprString(c.Fun) == "api.CambiaronLosAlmacenes" {
						avisaALosAlmacenes = true
					}
					return true
				})
			}
		}
		return true
	})
	if !correEnSuHilo {
		t.Error("cmd/api/main.go no hace `go avisoscrm.Correr(...)` (¿comentado, o sin `go`?): " +
			"el aviso del CRM nunca se escucharía")
	}
	if !conRedisReal {
		t.Error("cmd/api/main.go no pasa avisoscrm.DeRedis(cfg.Redis) a avisoscrm.Correr (¿nil, un comentario?)")
	}
	if !avisaALosAlmacenes {
		t.Error("la función que main le pasa a avisoscrm.Correr no llama a api.CambiaronLosAlmacenes: " +
			"se oiría el aviso y no se tiraría la caché ni se avisaría a las pantallas")
	}
}
