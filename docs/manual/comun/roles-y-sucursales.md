# Roles y sucursales

## Las ocho sucursales

`CAM` Camagüey · `GR` Granma · `GTO` Guantánamo · `HAB` La Habana · `HOL` Holguín
· `SS` Sancti Spíritus · `STG` Santiago · `TUN` Las Tunas.

**La sucursal que tengas puesta arriba manda sobre todo lo que ves.** Panel,
Tablero, Pedidos, Rutas, Clientes, Vehículos, Almacenes y Reportes enseñan lo de
esa sucursal y nada más.

Si un pedido «no aparece», lo primero que hay que mirar es la sucursal de arriba.

---

## Los siete roles

Se escriben exactamente así:

`DESARROLLADOR` · `SUPER ADMIN` · `GERENTE` · `ADMINISTRADOR` · `SUPERVISOR` ·
`GESTOR` · `OPERADOR`

### Quién ve cuántas sucursales

| Rol | Sucursales |
|---|---|
| `DESARROLLADOR` | Las **ocho**, y puede cambiar de una a otra |
| `SUPER ADMIN` | Las **ocho**, y puede cambiar de una a otra |
| `GERENTE` | **Una**, la suya |
| `ADMINISTRADOR` | **Una**, la suya |
| `SUPERVISOR` | **Una**, la suya |
| `GESTOR` | **Una**, la suya |
| `OPERADOR` | **Una**, la suya |

**Cuidado con `ADMINISTRADOR`**: pese al nombre, es de **una** sucursal, no de
todas. Un administrador de Camagüey no ve Santiago y no debe verlo.

Si tienes uno de los cinco roles de una sola sucursal, el selector de sucursal de
arriba no te deja elegir otra. No es que esté roto: es que no te toca.

### Si tu sucursal no está dada de alta en Reparto

Accesos conoce más sucursales de las ocho que trabajan en Reparto (por ejemplo **Moa** o
**Palma Soriano**). Si el administrador te asigna una de ésas, **el acceso a los datos se
te niega**: entrar con tu usuario y contraseña funciona, pero **cada pantalla** de Reparto
se niega con un mensaje que nombra tu sucursal (el código que traiga tu cuenta, aquí
MOA):

> «tu sucursal MOA no está dada de alta en Reparto: pide en la oficina que la den de
> alta»

**No es tu contraseña ni un fallo de la aplicación**: tu cuenta es buena, pero Reparto
no tiene esa sucursal. Se arregla en la oficina, dando de alta la sucursal en Reparto o
asignándote una de las ocho. **Ya no se te abren las ocho sucursales** como pasaba
antes: abrir todas por una sucursal que no cuadra era enseñarle a un operador de una
sucursal los pedidos y los precios de las otras siete.

Si tu cuenta **no tiene ninguna sucursal**, el mensaje es otro y tampoco ha cambiado:
«esta cuenta no está dada de alta en ninguna sucursal: pide en la oficina que te
asignen la tuya». Y a quien no ve todas las sucursales ya no le vale pedir otra
cambiando algo en la dirección: la sucursal sale de tu cuenta, no de lo que mande el
navegador.

**Las cuentas que ven todas las sucursales (`SUPER ADMIN` y `DESARROLLADOR`) no
cambian**: siguen viendo las ocho y pudiendo elegir una.

### Por qué no se puede saltar

El alcance sale de **quién pregunta**, no de lo que se le pida al servidor.
Cambiar algo en la pantalla o en la dirección no da acceso a otra sucursal: el
servidor contesta que no. Ya pasó una vez en la aplicación anterior —un operador
de Santiago vio los precios de La Habana— y por eso está cerrado así.

---

## Lo que cada rol puede tocar

Esconder una entrada del menú **no es un permiso**: el candado está en el
servidor, que es quien dice que no. Lo que sí cambia de rol a rol es lo que se
ve en el menú.

### El canal con PEDIDO

En el menú lo ven **sólo** `DESARROLLADOR` y `SUPER ADMIN`. Los otros cinco roles
—`GERENTE`, `ADMINISTRADOR`, `SUPERVISOR`, `GESTOR`, `OPERADOR`— no lo ven.

Además, esa pantalla **existe sólo en la web**. En el teléfono y en el escritorio
no está.

### El resto del menú

Panel, Tablero, Rutas, Pedidos, Clientes, Vehículos, Almacenes y Reportes están en
el menú para todos los roles.

Dos entradas más aparecen **sólo en la APK y en el escritorio**, porque son del
aparato de trabajar sin señal y en un navegador no significan nada:

- **Sincronización**
- **Mapa sin conexión**

---

## Lo que esta aplicación NO hace con los usuarios

- **No se dan de alta usuarios aquí.** Ni se cambian contraseñas, ni se cambian
  roles, ni se asigna una sucursal a nadie. Todo eso vive en Accesos.
- **No se cambia la sucursal de un aparato desde el menú.** En la APK y en el
  escritorio se pregunta una vez, la primera vez que hay algo que subir, y es una
  pregunta distinta de la sucursal que estás mirando: es **dónde está el
  aparato**.
- Quien sea dado de baja deja de entrar **en cuanto su aparato tenga señal**, no
  antes. Si ya estaba dentro y sin señal, sigue trabajando hasta que la recupere.
