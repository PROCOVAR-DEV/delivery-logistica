package api

import (
	"context"
	"errors"
	"regexp"
	"testing"

	"github.com/google/uuid"
)

// EL CÓDIGO DE UNA RUTA SALE DE SU UUIDv7 (04/11/2026). Se ata: el formato corto y sin prefijo, que sale del id, que el id que manda el
// aparato manda (y su código es el mismo en los dos lados), que un id que no es v7 se rechaza, y que un choque no repite nunca un código.

var formatoDelCodigo = regexp.MustCompile(`^[0-9A-HJKMNP-TV-Z]{6}$`)

func codigoCortoValido(c string) bool { return formatoDelCodigo.MatchString(c) }

func TestElCodigoEsCortoSinPrefijoYSaleDelId(t *testing.T) {
	id, _ := uuid.NewV7()
	c := codigoDeRutaDe(id)
	if !codigoCortoValido(c) {
		t.Fatalf("el código %q no son 6 caracteres de Crockford", c)
	}
	if codigoDeRutaDe(id) != c {
		t.Fatalf("el código tiene que salir SIEMPRE del mismo id")
	}
	// un valor conocido: los últimos 4 bytes 0x0000_0000 -> 000000 y 0x3FFF_FFFF -> ZZZZZZ (solo cuentan 30 bits)
	var cero, lleno uuid.UUID
	copy(lleno[12:], []byte{0xff, 0xff, 0xff, 0xff})
	if codigoDeRutaDe(cero) != "000000" || codigoDeRutaDe(lleno) != "ZZZZZZ" {
		t.Fatalf("extremos: %q y %q", codigoDeRutaDe(cero), codigoDeRutaDe(lleno))
	}
}

func TestSinIdDelAparatoElServidorPoneUnUUIDv7(t *testing.T) {
	id, codigo, _, err := idYCodigoDeRuta(context.Background(), func(context.Context, string) (bool, error) { return false, nil }, uuid.Nil)
	if err != nil || id.Version() != 7 || codigo != codigoDeRutaDe(id) {
		t.Fatalf("id=%v código=%q err=%v", id, codigo, err)
	}
}

func TestElIdDelAparatoManda(t *testing.T) {
	propio, _ := uuid.NewV7()
	id, codigo, _, err := idYCodigoDeRuta(context.Background(), func(context.Context, string) (bool, error) { return false, nil }, propio)
	if err != nil || id != propio || codigo != codigoDeRutaDe(propio) {
		t.Fatalf("el aparato y el servidor tienen que coincidir: id=%v código=%q err=%v", id, codigo, err)
	}
}

func TestSiElCodigoDelAparatoChocaConservaElIdYDaOtroCodigo(t *testing.T) {
	propio, _ := uuid.NewV7()
	ocupado := codigoDeRutaDe(propio)
	id, codigo, _, err := idYCodigoDeRuta(context.Background(), func(_ context.Context, c string) (bool, error) { return c == ocupado, nil }, propio)
	if err != nil || id != propio {
		t.Fatalf("el id es del aparato y no se toca: id=%v err=%v", id, err)
	}
	if codigo == ocupado || !codigoCortoValido(codigo) {
		t.Fatalf("tenía que dar OTRO código libre y salió %q (ocupado %q)", codigo, ocupado)
	}
}

func TestAvisaSoloCuandoElCodigoDelAparatoCambio(t *testing.T) {
	propio, _ := uuid.NewV7()
	libre := func(context.Context, string) (bool, error) { return false, nil }
	if _, _, cambio, _ := idYCodigoDeRuta(context.Background(), libre, propio); cambio {
		t.Fatalf("si el código del aparato estaba libre se RESPETA y no hay nada que avisar")
	}
	ocupado := codigoDeRutaDe(propio)
	if _, _, cambio, _ := idYCodigoDeRuta(context.Background(), func(_ context.Context, c string) (bool, error) { return c == ocupado, nil }, propio); !cambio {
		t.Fatalf("si coincidió y se le dio otro, tiene que avisar")
	}
	if _, _, cambio, _ := idYCodigoDeRuta(context.Background(), libre, uuid.Nil); cambio {
		t.Fatalf("sin id del aparato no hay nada que cambiarle")
	}
}

func TestSinIdPropuestoUnChoqueProbaConOtroUUID(t *testing.T) {
	llamadas := 0
	id, codigo, _, err := idYCodigoDeRuta(context.Background(), func(context.Context, string) (bool, error) {
		llamadas++
		return llamadas < 3, nil // los dos primeros códigos están ocupados
	}, uuid.Nil)
	if err != nil || llamadas != 3 || codigo != codigoDeRutaDe(id) {
		t.Fatalf("llamadas=%d id=%v código=%q err=%v", llamadas, id, codigo, err)
	}
}

func TestSiTodoEstaOcupadoSeRindeSinRepetir(t *testing.T) {
	_, _, _, err := idYCodigoDeRuta(context.Background(), func(context.Context, string) (bool, error) { return true, nil }, uuid.Nil)
	if err == nil {
		t.Fatalf("con todos los códigos ocupados tiene que fallar, no repetir")
	}
}

func TestUnErrorDeLaBaseSePropaga(t *testing.T) {
	roto := errors.New("base caída")
	_, _, _, err := idYCodigoDeRuta(context.Background(), func(context.Context, string) (bool, error) { return false, roto }, uuid.Nil)
	if !errors.Is(err, roto) {
		t.Fatalf("err=%v", err)
	}
}

func TestElIdDelAparatoTieneQueSerV7(t *testing.T) {
	v7, _ := uuid.NewV7()
	if id, err := idDeRutaDelAparato(v7.String()); err != nil || id != v7 {
		t.Fatalf("un v7 vale: %v %v", id, err)
	}
	if id, err := idDeRutaDelAparato(""); err != nil || id != uuid.Nil {
		t.Fatalf("vacío = no mandó: %v %v", id, err)
	}
	for _, malo := range []string{uuid.New().String(), "local-9f3a2b7c", "no-es-un-uuid", "RT-ABC123"} {
		if _, err := idDeRutaDelAparato(malo); !errors.Is(err, errIdNoEsV7) {
			t.Fatalf("%q tenía que rechazarse como no-v7, y dio %v", malo, err)
		}
	}
}

func TestSinCodigosRepetidosEnMuchosIds(t *testing.T) {
	// 20.000 rutas: con 30 bits habrá algún choque (cumpleaños) y por eso se MIRA contra la base; aquí se comprueba que el
	// generador, con esa comprobación, nunca entrega dos códigos iguales.
	vistos := map[string]bool{}
	existe := func(_ context.Context, c string) (bool, error) { return vistos[c], nil }
	for i := 0; i < 20000; i++ {
		_, c, _, err := idYCodigoDeRuta(context.Background(), existe, uuid.Nil)
		if err != nil {
			t.Fatal(err)
		}
		if vistos[c] {
			t.Fatalf("código repetido %q en la ruta %d", c, i)
		}
		vistos[c] = true
	}
}
