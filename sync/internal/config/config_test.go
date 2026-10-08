package config

import (
	"strings"
	"testing"
)

func entornoBueno(t *testing.T) {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("REPARTO_URL", "http://reparto:8080")
	t.Setenv("REPARTO_API_KEY", "la-llave")
	t.Setenv("JWT_SECRET", strings.Repeat("s", 40))
	t.Setenv("SYNC_PERMITIR_CABECERAS", "")
}

// `SYNC_IDENTIDAD=cabeceras` NO comprueba roles (la identidad sale de cabeceras que escribe
// cualquiera que llegue al puerto), así que no se admite sin una variable EXPLÍCITA
// (auditoría, 08/10/2026). En producción es `token`.
func TestCabecerasNoSeAdmiteSinLaVariableExplicita(t *testing.T) {
	entornoBueno(t)
	t.Setenv("SYNC_IDENTIDAD", "cabeceras")

	_, err := Cargar()
	if err == nil {
		t.Fatal("cabeceras arrancó sin SYNC_PERMITIR_CABECERAS=1: el control de roles de Reparto no se aplica en ese modo")
	}
	for _, quiero := range []string{"SYNC_IDENTIDAD=cabeceras", "NO comprueba roles", "SYNC_PERMITIR_CABECERAS=1"} {
		if !strings.Contains(err.Error(), quiero) {
			t.Errorf("el error no dice %q: %v", quiero, err)
		}
	}

	// Cualquier otro valor distinto de «1» tampoco vale.
	t.Setenv("SYNC_PERMITIR_CABECERAS", "true")
	if _, err := Cargar(); err == nil {
		t.Fatal(`SYNC_PERMITIR_CABECERAS=true no es "1": no tenía que valer`)
	}
}

// LA PAREJA: con la variable explícita arranca, y `token` arranca siempre.
func TestCabecerasConLaVariableExplicitaYTokenSiArrancan(t *testing.T) {
	entornoBueno(t)
	t.Setenv("SYNC_IDENTIDAD", "cabeceras")
	t.Setenv("SYNC_PERMITIR_CABECERAS", "1")
	if _, err := Cargar(); err != nil {
		t.Fatalf("cabeceras con SYNC_PERMITIR_CABECERAS=1 tenía que arrancar: %v", err)
	}

	entornoBueno(t)
	t.Setenv("SYNC_IDENTIDAD", "token")
	if c, err := Cargar(); err != nil || c.Identidad != "token" {
		t.Fatalf("token tenía que arrancar sin más: %v", err)
	}

	entornoBueno(t)
	t.Setenv("SYNC_IDENTIDAD", "")
	if _, err := Cargar(); err == nil {
		t.Fatal("sin SYNC_IDENTIDAD tampoco arranca (no hay valor por defecto)")
	}
}
