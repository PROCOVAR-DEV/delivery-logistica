package config

import (
	"strings"
	"testing"
)

func ponerDistribuidor(t *testing.T, kv map[string]string) {
	t.Helper()
	for _, k := range []string{"APP_DISTRIBUIDOR_VERSION", "APP_DISTRIBUIDOR_COMPILACION", "APP_DISTRIBUIDOR_NOTAS", "APP_DISTRIBUIDOR_PUBLICADA",
		"APP_DESCARGA_ANDROID_DISTRIBUIDOR", "APP_DESCARGA_ANDROID_DISTRIBUIDOR_BYTES", "APP_DESCARGA_ANDROID_DISTRIBUIDOR_SHA256"} {
		t.Setenv(k, "")
	}
	for k, v := range kv {
		t.Setenv(k, v)
	}
}

const huella = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

func TestLaVersionDelDistribuidorVaAparteYSeLee(t *testing.T) {
	ponerDistribuidor(t, map[string]string{
		"APP_DISTRIBUIDOR_VERSION": "1.0.0", "APP_DISTRIBUIDOR_COMPILACION": "57",
		"APP_DESCARGA_ANDROID_DISTRIBUIDOR":       "https://archivos.procovar.cloud/reparto/apk/reparto-distribuidor-1.0.0-261106.apk",
		"APP_DESCARGA_ANDROID_DISTRIBUIDOR_BYTES": "180000000", "APP_DESCARGA_ANDROID_DISTRIBUIDOR_SHA256": huella,
	})
	p, errs := leerPublicadaDistribuidor()
	if len(errs) > 0 || p == nil || p.Version != "1.0.0" || p.Compilacion != 57 || p.Ficheros["android"].Bytes != 180000000 {
		t.Fatalf("p=%+v errs=%v", p, errs)
	}
}

func TestSinNadaDelDistribuidorNoAnunciaNada(t *testing.T) {
	ponerDistribuidor(t, nil)
	if p, errs := leerPublicadaDistribuidor(); p != nil || len(errs) > 0 {
		t.Fatalf("vacío = nada anunciado, sin error: %v %v", p, errs)
	}
}

func TestLaMitadDeLaVersionDelDistribuidorNoArranca(t *testing.T) {
	casos := map[string]map[string]string{
		"descarga sin versión":         {"APP_DESCARGA_ANDROID_DISTRIBUIDOR": "https://x/y.apk"},
		"compilación sin versión":      {"APP_DISTRIBUIDOR_COMPILACION": "57"},
		"versión sin descarga":         {"APP_DISTRIBUIDOR_VERSION": "1.0.0"},
		"descarga sin bytes ni huella": {"APP_DISTRIBUIDOR_VERSION": "1.0.0", "APP_DESCARGA_ANDROID_DISTRIBUIDOR": "https://x/y.apk"},
		"compilación que no es número": {"APP_DISTRIBUIDOR_VERSION": "1.0.0", "APP_DISTRIBUIDOR_COMPILACION": "abc",
			"APP_DESCARGA_ANDROID_DISTRIBUIDOR": "https://x/y.apk", "APP_DESCARGA_ANDROID_DISTRIBUIDOR_BYTES": "10", "APP_DESCARGA_ANDROID_DISTRIBUIDOR_SHA256": huella},
		"url sin esquema": {"APP_DISTRIBUIDOR_VERSION": "1.0.0", "APP_DESCARGA_ANDROID_DISTRIBUIDOR": "x/y.apk",
			"APP_DESCARGA_ANDROID_DISTRIBUIDOR_BYTES": "10", "APP_DESCARGA_ANDROID_DISTRIBUIDOR_SHA256": huella},
	}
	for nombre, env := range casos {
		ponerDistribuidor(t, env)
		p, errs := leerPublicadaDistribuidor()
		if p != nil || len(errs) == 0 {
			t.Errorf("%s: tenía que ser un error y fue p=%+v errs=%v", nombre, p, errs)
		}
		for _, e := range errs {
			if strings.TrimSpace(e.Error()) == "" {
				t.Errorf("%s: error sin texto", nombre)
			}
		}
	}
}
