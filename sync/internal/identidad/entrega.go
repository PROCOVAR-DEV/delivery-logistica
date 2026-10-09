package identidad

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
)

// EL TOKEN DE ENTREGA A REVISIÓN — `docs/bandeja-de-revision.md`, B.1, paquete V.
//
// Quien pierde `delivery.entrar` conserva su cola en el aparato, pero sin llave no hay token con el
// que subirla. Accesos le firma, SI Y SÓLO SI la sesión sigue viva, la persona está activa y de verdad
// no tiene la llave, un token de DIEZ MINUTOS y UN ÁMBITO: `ambito:"reparto.entrega"`,
// `purpose:"apk:entrega"`, `entradas:[]`, sin roles. Con él, `sync` deja cada apunte en una tabla
// aparte, tal como vino, para que una persona lo APLIQUE o lo DESCARTE. **No toca datos del negocio.**
//
// # Qué NO es este verificador
//
// No es un permiso: devuelve una [Identidad] SIN roles y sin `EsSuperAdmin`, con el [Identidad.Ambito]
// puesto, y **no guarda el token en [Identidad.Token]**: lo que se reenvía al reparto tiene que ser un
// token de persona con llave, y este jamás. Sólo abre dos rutas de `sync`
// (`POST /sync/revision/entrega` y `GET /sync/revision/mias`); en el resto, [Exigir] contesta 403.
//
// # Qué exige, y por qué cada cosa
//
//   - La firma, `exp` obligatorio, `nbf` y `sub`: lo mismo que cualquier token ([abrir]), con el
//     mismo corte de sesiones de Accesos. Un cierre `todo` DESPUÉS de emitirlo lo mata (401).
//   - `ambito` y `purpose` EXACTOS. Un token normal, o de otro ámbito, no es de entrega
//     ([ErrNoEsDeEntrega], que cuelga de [ErrSinPermisoDeReparto]: 403).
//   - `entradas` PRESENTE, array, y SIN `delivery.entrar`. Si trae la llave NO es un token de entrega
//     (lo emite Accesos para quien no la tiene), y dejarlo pasar sería un token que a la vez abre la
//     SUBIDA con la autoridad de la persona y entrega a revisión: la autoridad prestada.
//   - Ningún rol (`role`, `rol`, `roles`): «sin roles a propósito: nada que un verificador pueda tomar
//     por un permiso».
//   - `jti` (queda como constancia de qué token entregó), `iat` y una vida de a lo sumo
//     [topeDeVidaDeEntrega] más un minuto de holgura (Accesos firma 600 s): si Accesos se equivocara y firmara uno de
//     un día, aquí no valdría.
//   - Sucursal: el código que firma Accesos (`STG`), traducido por el resolutor. Sin sucursal no hay
//     alcance, y «sin alcance» no es «todas».
//
// Las dos mitades de Go (aquí y `api/internal/auth`) se atan con `docs/ambito-de-entrega.casos.json`.

const (
	// AmbitoEntrega es el único ámbito que [DeTokenDeEntrega] acepta.
	AmbitoEntrega = "reparto.entrega"
	// PropositoEntrega es el `purpose` que Accesos pone a ese token.
	PropositoEntrega = "apk:entrega"

	// topeDeVidaDeEntrega: Accesos firma `exp = iat + 600` (A1, confirmado). Se admite [margen] (un minuto)
	// de holgura para relojes y redondeos y nada más: un token de entrega con más vida que esto no lo
	// emitió Accesos como está diseñado.
	topeDeVidaDeEntrega = 10 * time.Minute
)

// ErrNoEsDeEntrega: el token es de verdad (firma, fecha y sesión valen) pero no es el de entrega.
//
// Cuelga de [ErrSinPermisoDeReparto] a propósito: para las dos rutas de entrega, quien llega con un
// token normal recibe el 403 `sin_permiso_reparto` de siempre —el contrato de S1—, no un 401 que el
// cliente leería como «la sesión murió». Va aparte para que [entregaONormal] sepa cuándo probar el
// verificador normal: sólo ante ESTE error, nunca ante una firma rota.
var ErrNoEsDeEntrega = fmt.Errorf("%w: no es un token de entrega a revisión", ErrSinPermisoDeReparto)

// DeTokenDeEntrega construye la fuente que sólo acepta el token de entrega. Misma firma que
// [DeTokenConInvalidaciones]: `resolutor` traduce el código de la sucursal e `inv` (puede ser nil)
// es el registro de cortes de Accesos.
func DeTokenDeEntrega(secreto []byte, resolutor Resolutor, inv Invalidaciones) Fuente {
	return func(r *http.Request) (Identidad, error) {
		crudo := bearerDe(r)
		if strings.TrimSpace(crudo) == "" {
			return Identidad{}, ErrSinSesion
		}
		c, id, err := abrir(crudo, secreto, inv)
		if err != nil {
			return Identidad{}, err
		}

		// ¿Es de entrega? Un texto EXACTO: «REPARTO.ENTREGA» o un array no lo son.
		var ambito string
		if !c.TieneAmbito || json.Unmarshal(c.Ambito, &ambito) != nil || ambito != AmbitoEntrega {
			return Identidad{}, ErrNoEsDeEntrega
		}
		if c.Purpose != PropositoEntrega {
			return Identidad{}, fmt.Errorf("%w: el ámbito es de entrega pero el purpose no", ErrSinSesion)
		}

		llaves, hay := entradasEstrictas(c)
		if !hay {
			return Identidad{}, fmt.Errorf("%w: un token de entrega trae `entradas` como array", ErrSinSesion)
		}
		for _, l := range llaves {
			if l == llaveEntrarReparto {
				return Identidad{}, fmt.Errorf("%w: trae %s, así que no es un token de entrega", ErrSinSesion, llaveEntrarReparto)
			}
		}
		for _, rol := range rolesDelToken(c) {
			if strings.TrimSpace(rol) != "" {
				return Identidad{}, fmt.Errorf("%w: un token de entrega no lleva roles", ErrSinSesion)
			}
		}

		if strings.TrimSpace(c.Jti) == "" {
			return Identidad{}, fmt.Errorf("%w: el token de entrega no trae jti", ErrSinSesion)
		}
		if c.Iat == nil {
			return Identidad{}, fmt.Errorf("%w: el token de entrega no trae iat", ErrSinSesion)
		}
		vida := time.Duration((*c.Exp - *c.Iat) * float64(time.Second))
		if vida > topeDeVidaDeEntrega+margen {
			return Identidad{}, fmt.Errorf("%w: el token de entrega vive %s y el tope es %s",
				ErrSinSesion, vida, topeDeVidaDeEntrega+margen)
		}

		// Y lo que le QUEDA, no sólo lo que dice vivir: un `iat` en el futuro alargaría la vida real.
		if resta := time.Until(time.Unix(int64(*c.Exp), 0)); resta > topeDeVidaDeEntrega+margen {
			return Identidad{}, fmt.Errorf("%w: al token de entrega le quedan %s y el tope es %s",
				ErrSinSesion, resta.Round(time.Second), topeDeVidaDeEntrega)
		}

		sucursal := strings.TrimSpace(primero(c.BranchID, c.BranchIDSnake, c.Sucursal))
		if sucursal == "" {
			return Identidad{}, fmt.Errorf("%w: el token de entrega no trae sucursal", ErrSinSesion)
		}
		if s, err := uuid.Parse(sucursal); err == nil {
			id.Sucursal = s
		} else {
			if resolutor == nil {
				return Identidad{}, fmt.Errorf("%w: el token trae el código %q y no hay con qué traducirlo", ErrSinSesion, sucursal)
			}
			s, err := resolutor(r.Context(), sucursal)
			if err != nil {
				return Identidad{}, err // ErrSinSesion o ErrNoSePudoComprobar, tal cual
			}
			id.Sucursal = s
		}

		id.Nombre, id.Jti, id.Ambito = strings.TrimSpace(c.Nombre), c.Jti, AmbitoEntrega
		// NO se guarda id.Token: ver el comentario del fichero. NO es Super Admin, nunca.
		id.EsSuperAdmin = false
		return id, nil
	}
}

// entradasEstrictas: `entradas` tiene que venir y ser un array JSON (de textos; otros elementos se
// ignoran). `null`, un texto o un objeto NO valen: a diferencia de [entradasDelToken], que los cuenta
// como «presente y vacío» para fallar cerrado, aquí «vacío» es justo lo que se exige, y un valor roto
// no puede pasar por tal.
func entradasEstrictas(c reclamos) (llaves []string, hay bool) {
	crudo := strings.TrimSpace(string(c.Entradas))
	if !strings.HasPrefix(crudo, "[") {
		return nil, false
	}
	var v []any
	if err := json.Unmarshal(c.Entradas, &v); err != nil {
		return nil, false
	}
	llaves = []string{}
	for _, e := range v {
		if t, ok := e.(string); ok {
			llaves = append(llaves, t)
		}
	}
	return llaves, true
}

// entregaONormal es la fuente de `GET /sync/revision/mias`: acepta el token de entrega O el normal.
// Prueba el normal SÓLO si el de entrega dijo [ErrNoEsDeEntrega] (el token es válido pero no es de
// entrega); una firma rota, un token caducado o un corte de Accesos se contestan tal cual, sin
// una segunda verificación. «De la misma persona del aparato» lo comprueba el manejador.
func entregaONormal(entrega, normal Fuente) Fuente {
	return func(r *http.Request) (Identidad, error) {
		id, err := entrega(r)
		if err == nil {
			return id, nil
		}
		if errors.Is(err, ErrNoEsDeEntrega) {
			return normal(r)
		}
		return Identidad{}, err
	}
}

// FuentesDeEntrega es lo que `cmd/sync` monta para las dos rutas de entrega, junto a
// [FuenteDeLaCasa] (de la que sale `normal` e `inv`): `entrega` sólo acepta el token de entrega y
// `mias` acepta ese o el normal. Con `modo` distinto de `token` NO hay token de entrega posible
// (las cabeceras de un proxy no llevan ámbito): `entrega` rechaza siempre. Existe, como
// [FuenteDeLaCasa], para que una prueba construya EXACTAMENTE lo que arma `main`.
func FuentesDeEntrega(modo string, secreto []byte, resolutor Resolutor, inv Invalidaciones, normal Fuente) (entrega, mias Fuente) {
	if modo != "token" {
		sinEntrega := func(*http.Request) (Identidad, error) { return Identidad{}, ErrSinSesion }
		return sinEntrega, normal
	}
	entrega = DeTokenDeEntrega(secreto, resolutor, inv)
	return entrega, entregaONormal(entrega, normal)
}
