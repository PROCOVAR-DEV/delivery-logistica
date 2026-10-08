package api

import (
	"net/http"

	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/httpx"
)

// rastroDeQuien deja UNA línea Info con QUIÉN hizo algo que cambia datos de la casa y sobre
// QUÉ ids — 08/10/2026 (auditoría de la 1.0.28).
//
// POR QUÉ. Quitar una parada, borrar una ruta, cerrarla, cambiarle el camión, dar de alta,
// editar o borrar un camión, guardar la tasa o lanzar el recosteo dejaban cambios en la base
// sin decir de quién. Cuando una ruta desaparece o un camión amanece en el taller, la
// pregunta es «¿quién fue?», y el registro del servidor es la única respuesta que va a
// existir (CLAUDE.md §3-septies): la base guarda `creado_por` al crear, pero ni al borrar ni
// al editar.
//
// `actor` es el `sub` de la persona (`auth.Usuario.ID`), que es lo que ya guardan
// `creado_por` y el alcance. **NUNCA el token, ni recortado, ni su firma, ni la cabecera**:
// un registro se pega en un correo y en un chat, y un token de siete días pegado en un chat
// es una sesión regalada. Ver `internal/auth/rastro.go` y `TestElRastroNoEnsenaElToken`; esa
// regla es la del 401, donde ni el `sub` sale porque quien pregunta aún no ha demostrado ser
// nadie. Aquí la persona ya está verificada —la ruta pasó por `Exigir`—, así que su id sí.
//
// No cambia ningún permiso: sólo escribe. `campos` van en pares clave, valor, como slog.
func rastroDeQuien(r *http.Request, accion string, campos ...any) {
	actor, rol := "", ""
	if u := auth.De(r); u != nil {
		actor, rol = u.ID, u.Rol
	}
	httpx.Registro(r).Info(accion, append([]any{"actor", actor, "rol", rol}, campos...)...)
}

// codigoParaElRegistro: el código de sucursal, o «todas» cuando no hay alcance (que es lo que
// un campo vacío en un renglón no dice).
func codigoParaElRegistro(codigo string) string {
	if codigo == "" {
		return "todas"
	}
	return codigo
}
