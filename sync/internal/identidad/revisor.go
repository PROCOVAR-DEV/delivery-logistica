package identidad

// QUIÉN REVISA LA BANDEJA — Jose, 08/10/2026 (`docs/bandeja-de-revision.md`, «Decisiones de Jose»): el
// ADMINISTRADOR de esa sucursal, el SUPER ADMIN y el DESARROLLADOR. LOGISTICO entra a Reparto pero NO revisa
// (no le toca decidir sobre el trabajo de otro logístico), y nadie revisa lo suyo (eso lo pone la consulta de
// `sync`, no esto).
//
// Se decide por el NOMBRE del rol del token, con [mismoRol] —exacto en ASCII, sin el plegado Unicode de
// `strings.EqualFold`, que casaba «ſUPER ADMIN»—, como el resto de Reparto. «Contiene admin» le daría las
// ocho sucursales a un ADMINISTRADOR: la sucursal no sale de aquí sino de [Identidad.Alcance].
//
// Y EXIGE EL TOKEN: aplicar es reenviar al reparto con el token DEL REVISOR. Sin él, el reenvío caería a la
// clave de servicio, que no tiene sucursal ni límite: la autoridad prestada llevada al máximo.
var rolesQueRevisan = []string{"ADMINISTRADOR", "SUPER ADMIN", "DESARROLLADOR"}

// RolDeRevisor devuelve el nombre canónico del rol por el que esta persona puede revisar, o false.
func (i Identidad) RolDeRevisor() (string, bool) {
	if i.Token == "" || i.Ambito != "" {
		return "", false
	}
	for _, r := range i.Roles {
		for _, canonico := range rolesQueRevisan {
			if mismoRol(r, canonico) {
				return canonico, true
			}
		}
	}
	return "", false
}
