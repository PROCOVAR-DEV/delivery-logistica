package identidad

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"
)

// EL VERIFICADOR DEL TOKEN, que es lo que faltaba para que este servicio aceptara a nadie.
//
// Sin él, `X-Persona` llegaba vacía —el proxy que debía ponerla no existe— y esto
// contestaba 401 a TODO. Nada se subió nunca, y el cliente trataba ese 401 como «la sesión
// murió»: echaba a la persona justo cuando volvía la señal.

const secreto = "0123456789012345678901234567890123456789"

func firmar(t *testing.T, cuerpo map[string]any, alg string) string {
	t.Helper()
	cabecera, _ := json.Marshal(map[string]string{"alg": alg, "typ": "JWT"})
	carga, _ := json.Marshal(cuerpo)
	b := func(v []byte) string { return base64.RawURLEncoding.EncodeToString(v) }
	sinFirma := b(cabecera) + "." + b(carga)
	mac := hmac.New(sha256.New, []byte(secreto))
	mac.Write([]byte(sinFirma))
	return sinFirma + "." + b(mac.Sum(nil))
}

// conToken entra SIN resolutor: es lo correcto para las pruebas de firma, de `exp` y de
// rol, donde la sucursal ya viene como uuid y no hay nada que traducir. Las que sí traen
// un código usan `conTokenY`.
func conToken(t *testing.T, token string) (Identidad, error) {
	t.Helper()
	return conTokenY(t, token, nil)
}

func conTokenY(t *testing.T, token string, resolutor Resolutor) (Identidad, error) {
	t.Helper()
	r := httptest.NewRequest(http.MethodPost, "/sync/aparato", nil)
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	return DeToken([]byte(secreto), resolutor)(r)
}

func TestUnTokenBuenoEntraConSuSucursal(t *testing.T) {
	suc := uuid.New()
	id, err := conToken(t, firmar(t, map[string]any{
		"sub":      "persona-1",
		"role":     "LOGISTICO",
		"branchId": suc.String(),
		"exp":      time.Now().Add(time.Hour).Unix(),
	}, "HS256"))
	if err != nil {
		t.Fatalf("un token bueno tenía que entrar: %v", err)
	}
	if id.Persona != "persona-1" {
		t.Errorf("persona = %q", id.Persona)
	}
	if id.Sucursal != suc {
		t.Errorf("sucursal = %v, se esperaba %v", id.Sucursal, suc)
	}
	if id.EsSuperAdmin {
		t.Error("con sucursal en el token NO es Super Admin: vería las ocho")
	}
}

func TestLosDosRolesQueVenTodoEntranSinSucursal(t *testing.T) {
	// Jose, 16/09/2026: «los super administradores pueden tocar en todos lados y el
	// desarrollador mucho mas arriba aun». Los dos, y nadie más.
	for _, rol := range []string{"SUPER ADMIN", "DESARROLLADOR"} {
		id, err := conToken(t, firmar(t, map[string]any{
			"sub":      "jefe",
			"branchId": nil,
			"role":     rol,
			"exp":      time.Now().Add(time.Hour).Unix(),
		}, "HS256"))
		if err != nil {
			t.Fatalf("%s tenía que entrar: %v", rol, err)
		}
		if !id.EsSuperAdmin {
			t.Errorf("%s sin sucursal ve las ocho", rol)
		}
	}
}

func TestSinSucursalYSinSerSuperAdminNoSeVeNada(t *testing.T) {
	// LA REGLA 1 DE LA CASA, y ya costó dinero una vez: «un operador de Santiago vio los
	// precios de La Habana». Un token sin sucursal lo puede tener alguien a quien no le
	// han dado la suya todavía; tratar ese hueco como «las ocho» convierte un dato que
	// FALTA en el permiso más grande que hay.
	//
	// Jose, 16/09/2026: «sin sucursal no es por el tipo de usuario no hagas eso por q
	// entonces un usuario sin sucursal ve todas eso esta malisimo».
	// Los cinco roles de la tabla `role` de Accesos que pertenecen a UNA sucursal.
	for _, rol := range []string{
		"", "OPERADOR", "GESTOR", "SUPERVISOR", "ADMINISTRADOR", "GERENTE", "LOGISTICO",
	} {
		cuerpo := map[string]any{
			"sub":      "alguien",
			"branchId": nil,
			"exp":      time.Now().Add(time.Hour).Unix(),
		}
		if rol != "" {
			cuerpo["role"] = rol
		}
		if _, err := conToken(t, firmar(t, cuerpo, "HS256")); err == nil {
			t.Errorf("rol %q sin sucursal NO puede ver las ocho", rol)
		}
	}
}

func TestAdministradorNoEsSuperAdmin(t *testing.T) {
	// `ADMINISTRADOR` es de UNA sucursal. Comparar con «contiene admin» lo dejaría pasar
	// y le daría las ocho.
	if _, err := conToken(t, firmar(t, map[string]any{
		"sub":      "admin-de-una",
		"branchId": nil,
		"role":     "ADMINISTRADOR",
		"exp":      time.Now().Add(time.Hour).Unix(),
	}, "HS256")); err == nil {
		t.Fatal("un ADMINISTRADOR sin sucursal no puede ver las ocho")
	}
}

func TestUnaSucursalQueNoSeEntiendeNoAbreTodO(t *testing.T) {
	// Lo peligroso sería tratarla como «ninguna»: un dato roto se convertiría en permiso
	// para verlo todo. Es la regla 1 de la casa.
	//
	// Desde el 24/09/2026 una sucursal que no es un uuid es el CÓDIGO de Accesos y se
	// manda a traducir; lo que esta prueba sigue exigiendo es que, si no hay quien lo
	// traduzca o el reparto no lo conoce, **no se pase**.
	if _, err := conToken(t, firmar(t, map[string]any{
		"sub":      "x",
		"branchId": "esto-no-es-un-uuid",
		"exp":      time.Now().Add(time.Hour).Unix(),
	}, "HS256")); err == nil {
		t.Fatal("una sucursal ilegible tiene que rechazarse, no abrirlo todo")
	}
}

func TestLaFirmaSeComprueba(t *testing.T) {
	bueno := firmar(t, map[string]any{
		"sub": "x", "branchId": uuid.New().String(),
		"exp": time.Now().Add(time.Hour).Unix(),
	}, "HS256")
	// Se cambia un carácter de la firma.
	malo := bueno[:len(bueno)-1] + "A"
	if malo == bueno {
		t.Skip("la firma acababa en A")
	}
	if _, err := conToken(t, malo); err == nil {
		t.Fatal("una firma que no cuadra tiene que rechazarse")
	}
}

func TestUnTokenSinExpNoVale(t *testing.T) {
	// Sin `exp` no hay sesión que muera nunca.
	if _, err := conToken(t, firmar(t, map[string]any{
		"sub": "x", "branchId": uuid.New().String(),
	}, "HS256")); err == nil {
		t.Fatal("un token sin caducidad tiene que rechazarse")
	}
}

func TestUnTokenCaducadoNoVale(t *testing.T) {
	if _, err := conToken(t, firmar(t, map[string]any{
		"sub": "x", "branchId": uuid.New().String(),
		"exp": time.Now().Add(-2 * time.Hour).Unix(),
	}, "HS256")); err == nil {
		t.Fatal("un token caducado tiene que rechazarse")
	}
}

func TestElAlgNoElige(t *testing.T) {
	// Un token que diga `none` se cae ANTES de mirar la firma. Es el ataque clásico.
	cabecera, _ := json.Marshal(map[string]string{"alg": "none", "typ": "JWT"})
	carga, _ := json.Marshal(map[string]any{
		"sub": "x", "exp": time.Now().Add(time.Hour).Unix(),
	})
	b := func(v []byte) string { return base64.RawURLEncoding.EncodeToString(v) }
	if _, err := conToken(t, b(cabecera)+"."+b(carga)+"."); err == nil {
		t.Fatal("`alg: none` tiene que rechazarse")
	}
}

func TestSinCabeceraNoHaySesion(t *testing.T) {
	if _, err := conToken(t, ""); err == nil {
		t.Fatal("sin Authorization no hay identidad")
	}
}

// EL TOKEN SE GUARDA PARA REENVIARLO, y sólo si pasó la verificación.
//
// Este servicio no escribe los datos: se los manda a `reparto-api`, y esa llamada la tiene
// que firmar LA MISMA PERSONA. Con la clave de servicio, `/api/board/columns` contestaba
// 401 «no viene token» y el apunte se quedaba en la cola para siempre — así se quedó la
// zona «Vista» dentro de un teléfono. Ver `identidad.Identidad.Token`.
func TestElTokenVerificadoSeGuardaParaReenviarlo(t *testing.T) {
	token := firmar(t, map[string]any{
		"sub":      "persona-1",
		"role":     "LOGISTICO",
		"branchId": uuid.New().String(),
		"exp":      time.Now().Add(time.Hour).Unix(),
	}, "HS256")

	id, err := conToken(t, token)
	if err != nil {
		t.Fatalf("un token bueno tenía que entrar: %v", err)
	}
	if id.Token != token {
		t.Errorf("no se guardó el token para reenviarlo: %q", id.Token)
	}
}

// Y un token QUE NO PASA no deja nada detrás. Guardarlo antes de comprobar la firma sería
// reenviarle al reparto un token que aquí se rechazó, que es peor que no comprobarlo.
func TestUnTokenQueNoPasaNoDejaTokenQueReenviar(t *testing.T) {
	casos := map[string]string{
		"firma cambiada": firmar(t, map[string]any{
			"sub": "x", "branchId": uuid.New().String(),
			"exp": time.Now().Add(time.Hour).Unix(),
		}, "HS256") + "roto",
		"caducado": firmar(t, map[string]any{
			"sub": "x", "branchId": uuid.New().String(),
			"exp": time.Now().Add(-2 * time.Hour).Unix(),
		}, "HS256"),
		"sin sucursal y sin rol que vea todo": firmar(t, map[string]any{
			"sub": "x", "role": "LOGISTICO",
			"exp": time.Now().Add(time.Hour).Unix(),
		}, "HS256"),
	}
	for nombre, token := range casos {
		t.Run(nombre, func(t *testing.T) {
			id, err := conToken(t, token)
			if err == nil {
				t.Fatal("tenía que rechazarse")
			}
			if id.Token != "" {
				t.Errorf("un token rechazado no puede salir de aquí para reenviarse: %q",
					id.Token)
			}
		})
	}
}

// ---------------------------------------------------------------------------
// EL CÓDIGO DE LA SUCURSAL — 24/09/2026
//
// Accesos firma `sucursal: "CAM"`, no un uuid. Aquí se hacía `uuid.Parse` y se rechazaba,
// así que TODO el protocolo contestaba 401 con un token perfectamente bueno: sin
// `POST /sync/aparato` no hay alta, y sin alta `POST /sync/subida` contesta 404. La cola
// del día no subía nunca.
//
// Las pruebas van en TRES, y las tres hacen falta:
//   1. el código bueno entra y trae SU sucursal;
//   2. un código que el reparto no conoce NO entra —y no entra como «todas»—;
//   3. un reparto que no contesta NO mata la sesión: sale `ErrNoSePudoComprobar`, que
//      arriba es un 503 y no un 401.
// Sin la 3, «traducir» se podría escribir devolviendo 401 ante cualquier tropiezo, y eso
// es exactamente el fallo que se está arreglando, con otro disfraz.
// ---------------------------------------------------------------------------

func tokenDeCam(t *testing.T) string {
	t.Helper()
	return firmar(t, map[string]any{
		"sub":       "cmuftlkbc0000",
		"role":      "ADMINISTRADOR",
		"sucursal":  "CAM",
		"branch_id": "CAM",
		"exp":       time.Now().Add(time.Hour).Unix(),
	}, "HS256")
}

func TestElCodigoDeAccesosSeTraduceYEntra(t *testing.T) {
	cam := uuid.MustParse("b0000000-0000-4000-8000-00000000000a")
	pedidos := 0
	id, err := conTokenY(t, tokenDeCam(t), func(_ context.Context, codigo string) (uuid.UUID, error) {
		pedidos++
		if codigo != "CAM" {
			t.Fatalf("le llegó %q al traductor, y tenía que llegarle CAM", codigo)
		}
		return cam, nil
	})
	if err != nil {
		t.Fatalf("un token bueno de Accesos tiene que entrar: %v", err)
	}
	if id.Sucursal != cam {
		t.Fatalf("entró con la sucursal %s y tenía que ser %s", id.Sucursal, cam)
	}
	if id.EsSuperAdmin {
		t.Fatal("un ADMINISTRADOR de Camagüey NO es Super Admin: vería las ocho")
	}
	if pedidos != 1 {
		t.Fatalf("se preguntó %d veces por el código, y es una", pedidos)
	}
}

func TestUnCodigoQueElRepartoNoConoceNoEntra(t *testing.T) {
	id, err := conTokenY(t, tokenDeCam(t), func(_ context.Context, _ string) (uuid.UUID, error) {
		return uuid.Nil, fmt.Errorf("%w: la sucursal %q no existe en el reparto", ErrSinSesion, "CAM")
	})
	if err == nil {
		t.Fatalf("un código que no es de ninguna sucursal no puede entrar; entró con %v", id)
	}
	if !errors.Is(err, ErrSinSesion) {
		t.Fatalf("tenía que ser sin sesión (401) y fue %v", err)
	}
	if errors.Is(err, ErrNoSePudoComprobar) {
		t.Fatal("«no existe» no es «no pude comprobarlo»: se contestan distinto")
	}
	if id.Sucursal != uuid.Nil || id.EsSuperAdmin {
		t.Fatalf("un código desconocido no puede acabar en «todas»: %+v", id)
	}
}

// LA QUE DE VERDAD IMPORTA. Un tropiezo del reparto no puede salir como 401: el cliente
// trata un 401 que sobrevive a renovar como «la sesión murió» y echa a la persona a la
// pantalla de acceso, con la cola del día dentro del aparato.
func TestSiElRepartoNoContestaNoSeMataLaSesion(t *testing.T) {
	_, err := conTokenY(t, tokenDeCam(t), func(_ context.Context, _ string) (uuid.UUID, error) {
		return uuid.Nil, fmt.Errorf("%w: connection refused", ErrNoSePudoComprobar)
	})
	if err == nil {
		t.Fatal("sin poder comprobar la sucursal no se pasa")
	}
	if !errors.Is(err, ErrNoSePudoComprobar) {
		t.Fatalf("un fallo de red tiene que salir como «no se pudo comprobar» (503 arriba), y salió: %v", err)
	}
}

// El caché guarda el acierto y NO guarda el fallo: un tropiezo de un segundo no puede
// dejar media hora de aparatos rechazados.
func TestElCacheGuardaElAciertoYNoElFallo(t *testing.T) {
	cam := uuid.MustParse("b0000000-0000-4000-8000-00000000000a")
	veces := 0
	fallar := true
	c := NuevoCache(func(_ context.Context, _ string) (uuid.UUID, error) {
		veces++
		if fallar {
			return uuid.Nil, fmt.Errorf("%w: caído", ErrNoSePudoComprobar)
		}
		return cam, nil
	}, time.Hour)

	if _, err := c.Resolver(context.Background(), "CAM"); err == nil {
		t.Fatal("tenía que fallar")
	}
	if _, err := c.Resolver(context.Background(), "CAM"); err == nil {
		t.Fatal("tenía que fallar la segunda también")
	}
	if veces != 2 {
		t.Fatalf("el fallo se guardó en el caché: se preguntó %d veces en vez de 2", veces)
	}

	fallar = false
	for i := 0; i < 3; i++ {
		id, err := c.Resolver(context.Background(), "CAM")
		if err != nil || id != cam {
			t.Fatalf("vuelta %d: %v / %s", i, err, id)
		}
	}
	if veces != 3 {
		t.Fatalf("el acierto NO se guardó: se preguntó %d veces y tenían que ser 3", veces)
	}
}
