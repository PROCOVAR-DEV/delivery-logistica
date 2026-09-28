# Las tres formas de la aplicación

Es la misma aplicación en tres sitios, y **no se comportan igual**. Ésta es la
razón de ser del proyecto, así que conviene leerla una vez aunque sólo uses una.

---

## En una tabla

| | Web (navegador) | APK (Android) | Escritorio |
|---|---|---|---|
| **¿Trabaja sin señal?** | **No, nunca** | **Sí, la jornada entera** | **Sí, la jornada entera** |
| ¿Guarda los datos en el aparato? | No | Sí | Sí |
| ¿Hay que «Traer el día»? | No existe | Sí | Sí |
| ¿Hay que «Entregar el día»? | No existe | Sí | Sí |
| ¿Hay franja de estado arriba? | No | Sí | Sí |
| ¿Hay pantalla de Sincronización? | No está en el menú | Sí | Sí |
| ¿Hay Mapa sin conexión? | No está en el menú | Sí | Sí |
| ¿Hay que entrar cada vez? | Según el navegador | No, la sesión aguanta | No, la sesión aguanta |
| ¿Está el canal con PEDIDO? | Sí (sólo 2 roles) | No | No |
| Cada cuánto se pone al día sola | Cada **2 minutos** | Cada **5 minutos** | Cada **5 minutos** |

---

## La web: siempre con internet

La web **está en la nube y siempre saca los datos de la nube**. No guarda nada en
el navegador, y es a propósito.

Qué significa para quien la usa:

- **No hay nada que descargar ni que subir a mano.** Lo que haces, va. Lo que
  hicieron otros, lo ves solo.
- **No hay «datos de las 10:36»** ni «3 sin subir»: no hay ninguna copia tuya de
  la que hablar.
- **Si se cae el internet, se dice, pero no se puede seguir trabajando.** No hay
  base local que aguante el trabajo.
- Al recargar la página, la aplicación empieza de cero y vuelve a pedir los datos.
  Durante ese segundo puede verse una pantalla diciendo que todavía no bajó nada.
  Es normal y se va sola.

Un manual de la web que hable de trabajar sin señal está mintiendo.

---

## La APK de Android: el día entero sin señal

Es la del repartidor y la del logístico que baja al patio del almacén.

- **La primera vez que se abre** hace una configuración inicial con su porcentaje:
  «Configurando Reparto». Sólo pasa una vez.
- **«Traer el día»** carga en el teléfono todo lo del día: pedidos, clientes,
  productos, rutas, vehículos, almacenes. Se hace **donde haya señal**.
- **Con el día dentro, el camino entero funciona sin señal**: armar una zona,
  armar su ruta, iniciarla, marcar las entregas con su motivo.
- **Al volver la señal sube solo.** En una prueba real, en unos 6 segundos y sin
  tocar nada: la ruta `local-3df93810` pasó a llamarse `RT-20260928-004` y la
  franja pasó de «2 sin subir» a «Todo al día».
- **La sesión sobrevive a cerrar la aplicación.** Para **entrar** hace falta
  conexión; una vez dentro, no.

Lo que **no** se puede hacer sin señal está en
[Cuando algo sale mal](cuando-algo-sale-mal.md).

---

## El escritorio: lo mismo, con pantalla grande

Funciona igual que la APK —base en el aparato, traer el día, entregar el día,
mapa descargable— con dos diferencias de uso:

- Hay sitio para ver la lista y el detalle **a la vez**, así que el Tablero y las
  Rutas se trabajan mucho más cómodos.
- En algunos ordenadores con Linux **el almacén de claves del sistema no guarda la
  sesión**. Si es tu caso, la aplicación **te lo dice al entrar**, antes de pedirte
  la contraseña, en vez de prometerte que se acordará y luego no acordarse.

---

## La pregunta que resuelve las dudas

**¿Esto le sirve a alguien que abre un navegador con internet ahora mismo?**

Si la respuesta es «le guarda lo que hizo por si se cae la red», entonces es cosa
de la APK y del escritorio, y en la web no está.
