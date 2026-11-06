package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// LA VERSIÓN DE «REPARTO DISTRIBUIDOR» VA APARTE DE LA DE REPARTO (Jose, 06/11/2026: «son aplicaciones distintas… para poder darle mejor soporte y mejor
// control»). Son dos APK con su `applicationId`, su descarga y su ritmo: sacar una no obliga a sacar la otra, y /api/version anuncia cada una en su clave
// (`ultima` la de Reparto, `distribuidor` la del chofer). Sus variables:
//
//	APP_DISTRIBUIDOR_VERSION      "1.0.0"
//	APP_DISTRIBUIDOR_COMPILACION  57          (el `versionCode` de ESTA app: su propia cuenta, siempre creciente)
//	APP_DISTRIBUIDOR_NOTAS        opcional
//	APP_DISTRIBUIDOR_PUBLICADA    opcional (fecha)
//	APP_DESCARGA_ANDROID_DISTRIBUIDOR, _BYTES y _SHA256   la descarga (las tres)
//
// Todo o nada, como la de Reparto: versión sin descarga, o descarga sin versión, no arranca.
func leerPublicadaDistribuidor() (*Publicada, []error) {
	const url = "APP_DESCARGA_ANDROID_DISTRIBUIDOR"
	p := &Publicada{
		Version:     valor("APP_DISTRIBUIDOR_VERSION", ""),
		Notas:       valor("APP_DISTRIBUIDOR_NOTAS", ""),
		PublicadaAt: valor("APP_DISTRIBUIDOR_PUBLICADA", ""),
		Android:     strings.TrimSpace(os.Getenv(url)),
	}
	compilacion := strings.TrimSpace(os.Getenv("APP_DISTRIBUIDOR_COMPILACION"))

	if p.Version == "" {
		var sueltas []string
		if p.Android != "" {
			sueltas = append(sueltas, url)
		}
		if compilacion != "" {
			sueltas = append(sueltas, "APP_DISTRIBUIDOR_COMPILACION")
		}
		if len(sueltas) > 0 {
			return nil, []error{fmt.Errorf(
				"%s está puesta pero APP_DISTRIBUIDOR_VERSION no: sin número de versión no se anuncia nada a los choferes",
				strings.Join(sueltas, ", "))}
		}
		return nil, nil
	}

	var errs []error
	if p.Android == "" {
		errs = append(errs, errors.New(
			"APP_DISTRIBUIDOR_VERSION está puesta pero falta "+url+": se avisaría a los choferes de una versión nueva sin decir de dónde bajarla"))
	} else {
		if !strings.HasPrefix(p.Android, "http://") && !strings.HasPrefix(p.Android, "https://") {
			errs = append(errs, fmt.Errorf("%s vale %q: tiene que empezar por http:// o https://", url, p.Android))
		}
		fichero, propios := unFicheroPublicado(url)
		if len(propios) > 0 {
			errs = append(errs, propios...)
		} else {
			p.Ficheros = map[string]FicheroPublicado{"android": *fichero}
		}
	}
	if compilacion != "" {
		n, err := strconv.Atoi(compilacion)
		switch {
		case err != nil:
			errs = append(errs, fmt.Errorf("APP_DISTRIBUIDOR_COMPILACION vale %q y no es un número (el `versionCode` de Android)", compilacion))
		case n <= 0:
			errs = append(errs, fmt.Errorf("APP_DISTRIBUIDOR_COMPILACION vale %d: tiene que ser mayor que cero", n))
		default:
			p.Compilacion = n
		}
	}
	if p.PublicadaAt != "" {
		if normal, err := fecha(p.PublicadaAt); err != nil {
			errs = append(errs, err)
		} else {
			p.PublicadaAt = normal
		}
	}
	if len(errs) > 0 {
		return nil, errs
	}
	return p, nil
}
