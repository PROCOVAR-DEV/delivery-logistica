package db

import "testing"

// LO QUE VIGILA ESTA PRUEBA, y por qué no es una tontería:
//
// La cuenta que decide si un despliegue levanta o se muere. Si `Faltan` se equivoca por
// arriba, la API no arranca nunca y nadie puede desplegar; si se equivoca por abajo, vuelve
// el 17/09/2026: la API arranca con la base atrasada y la flota se queda congelada mientras
// la web enseña todo verde.
func TestFaltanLasQueLaBaseNoTiene(t *testing.T) {
	esperadas := []Migracion{
		{Version: 1, Nombre: "00001_sync.sql"},
		{Version: 2, Nombre: "00002_loquevenga.sql"},
		{Version: 6, Nombre: "00006_loquevenga.sql"},
	}

	casos := []struct {
		nombre   string
		enLaBase int64
		quiere   []string
	}{
		{"base sin migrar", 0, []string{"00001_sync.sql", "00002_loquevenga.sql", "00006_loquevenga.sql"}},
		{"el caso del 17/09: sólo falta la última", 2, []string{"00006_loquevenga.sql"}},
		{"al día", 6, nil},
		// Volver a una imagen anterior NO puede impedir arrancar: es justo lo que se hace
		// para salir de un despliegue malo, y morirse ahí deja al equipo sin marcha atrás.
		{"la base va por delante del binario", 9, nil},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			faltan := Faltan(esperadas, c.enLaBase)
			if len(faltan) != len(c.quiere) {
				t.Fatalf("con la base en %d se esperaban %d migraciones pendientes y salieron %d: %v",
					c.enLaBase, len(c.quiere), len(faltan), faltan)
			}
			for i, m := range faltan {
				if m.Nombre != c.quiere[i] {
					t.Errorf("pendiente %d: se esperaba %q y salió %q", i, c.quiere[i], m.Nombre)
				}
			}
		})
	}
}

// Las migraciones DE VERDAD, las que van incrustadas en el binario. Sin esto, un fichero
// nuevo con un nombre raro —o una carpeta que no se incrusta— dejaría la comprobación
// mirando una lista vacía, que es exactamente lo mismo que no comprobar nada.
func TestLasMigracionesIncrustadasSeLeen(t *testing.T) {
	esperadas, err := Esperadas()
	if err != nil {
		t.Fatalf("no se pudieron leer las migraciones incrustadas: %v", err)
	}
	if len(esperadas) == 0 {
		t.Fatal("NO HAY NINGUNA MIGRACIÓN INCRUSTADA: la comprobación del arranque no comprueba nada")
	}
	for i := 1; i < len(esperadas); i++ {
		if esperadas[i].Version <= esperadas[i-1].Version {
			t.Fatalf("las migraciones no salen ordenadas ni son únicas: %v antes que %v",
				esperadas[i-1], esperadas[i])
		}
	}
	// La primera es la que crea las tablas del protocolo. Sin ella no hay sincronizador.
	if esperadas[0].Version != 1 {
		t.Errorf("la primera migración incrustada tendría que ser la 00001 y es %v", esperadas[0])
	}
}

func TestUnNombreRaroEsUnErrorYNoUnSalto(t *testing.T) {
	if _, err := deNombre("sin-guion-bajo.sql"); err == nil {
		t.Error("un fichero con nombre raro tiene que dar ERROR: saltárselo daría por buena una base a la que le falta")
	}
}

// La bandeja de revisión (00003) y el tope del nombre del aparato (00004, auditoría M3) van incrustadas: el
// binario las exige al arrancar (`ExigirMigraciones`). Quitar la 00004 dejaría la base sin la restricción y el
// binario arrancando tan tranquilo.
func TestLasMigracionesDeLaBandejaYDelNombreDeAparatoEstanIncrustadas(t *testing.T) {
	esperadas, err := Esperadas()
	if err != nil {
		t.Fatal(err)
	}
	quiere := map[int64]string{3: "00003_la_bandeja_de_revision.sql", 4: "00004_nombre_de_aparato_acotado.sql"}
	for _, m := range esperadas {
		delete(quiere, m.Version)
	}
	if len(quiere) != 0 {
		t.Errorf("faltan migraciones incrustadas: %v", quiere)
	}
	if ultima := esperadas[len(esperadas)-1]; ultima.Version < 4 {
		t.Errorf("la última migración incrustada es la %d y el binario necesita al menos la 4", ultima.Version)
	}
}
