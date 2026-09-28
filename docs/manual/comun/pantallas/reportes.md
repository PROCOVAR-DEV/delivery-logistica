# Reportes

**Para qué sirve:** cuadrar la caja. Cuántas órdenes, cuánto se ingresó, cuánto
pesó y qué camión hizo qué.

Está en el menú, con el nombre «Reportes».

---

## Los filtros

Tarjeta **«Filtros»**:

- **«Desde»** y **«Hasta»** (fechas). Con una puesta sale una equis de quitar («Quitar Desde»).
- **«Vehículo»** — por defecto **«Todos los vehículos»**. Sólo los de la sucursal
  que estás mirando.
- **«Limpiar»** — sólo si hay algo puesto.
- **«Exportar a Excel»** al final de la fila.

Arranca **sin rango y sin vehículo**.

---

## De cuándo son estos datos

Encima de las pestañas siempre se dice, porque es lo que decide si esto sirve para
cerrar o no:

- En la APK y el escritorio: «Cuadrado con los datos del aparato, del 28/9/2026,
  10:36. Con conexión sale el del servidor.»
- En la web: «Cuadrado con lo último que bajó, de las 10:36.»

**Y si los datos tienen más de un día, un aviso en ámbar:**

> «Estos datos tienen más de un día: el informe no cuadra con el servidor y no sirve
> para cerrar. Conéctate y deja que baje.»

**Y si la última bajada volvió a medias** (esto manda sobre todo lo demás):

> «La última bajada no está entera, así que este informe está cuadrado con sólo una
> parte de los datos y los totales salen por debajo: no sirve para cerrar. …»

**Léelo antes de dar un número por bueno.**

---

## Las tres pestañas

### «Resumen»

Cuatro cifras:

| Tarjeta | Qué es |
|---|---|
| **«Total Órdenes»** | Cuántos pedidos entran en el filtro |
| **«Ingresos Totales»** | La suma de los importes, en la moneda que estés mirando |
| **«Precio Promedio»** | Ingresos dividido entre órdenes |
| **«Peso Total»** | La suma de kilos |

**Si falta el importe de alguna orden, no se pinta un cero.** Sale en ámbar:

```
— (3 sin cotizar)
```

Y debajo de «Ingresos Totales»: «Faltan cotizar 3 órdenes: sin ellas no hay
total.»

Debajo, **«Top vehículos»**: los tres primeros, con «$412.50 · 28 órdenes».

Si no hay nada: «No hay órdenes para los filtros seleccionados.»

### «Por Vehículo»

Tabla: **«Vehículo» | «Placa» | «Órdenes» | «Ingresos» | «Peso Total» |
«Promedio/Orden»**.

La fila de abajo es **«Totales»**, o **«Totales (3 sin cotizar)»** si falta algún
importe.

### «Detalle de Órdenes»

Tabla: **«Fecha» | «Cliente» | «Ruta» | «Destino» | «Vehículo» | «Peso» |
«Precio»**.

El precio sin cotización pone **«sin cotizar»**, nunca `0,00`.

La fila de abajo es **«Totales:»**, o **«Totales: (3 sin cotizar)»**.

Al lado del nombre de la pestaña sale una insignia con el número de filas.

---

## Cómo se calcula el ingreso de un pedido

Se toma **el precio guardado en la ruta si lo tiene** y, si no, **el costo que puso
Entrega**. Si no hay ninguno de los dos, **el importe no se sabe y no se suma** — y
de ahí sale el «sin cotizar».

---

## Exportar a Excel

Botón **«Exportar a Excel»**. El tooltip te dice en qué moneda va a salir:
«Exportar a Excel, con los importes en CUP».

Cuando está apagado, el tooltip dice por qué:

- «Esperá a que termine de cargar el reporte.»
- «No hay ninguna orden que exportar con estos filtros.»
- «No hay nada descargado todavía: no hay nada que exportar.»
- «Los datos del reporte no bajaron: no hay nada que exportar.»
- «El reporte no se pudo armar, así que no hay nada que exportar.»

Mientras lo arma: **«Armando el Excel...»**, y no se puede volver a pulsar.

### Qué sale

Un fichero llamado `reporte-procovar-2026-09-28.xlsx` con **tres hojas**:
**«Resumen»**, **«Por Vehículo»** y **«Detalle de Órdenes»**.

La hoja «Resumen» lleva arriba: «Reporte de transportación — ProCovar», cuándo se
generó, el filtro de fechas y la moneda. Y si falta cotizar algo, una fila más:

> **Órdenes sin cotizar** · 3 · «Ingresos Totales y Precio Promedio van vacíos a
> propósito: no se suma lo que falta.»

**Reglas del fichero:**

- Los importes van **en la moneda que estás mirando**. En CUP sin decimales, en USD
  con dos.
- **Un importe que no se sabe deja la celda vacía**, nunca un cero. Lo mismo con los
  kilómetros.
- **Si pides CUP y esa sucursal no tiene tasa, no se escribe nada**, y te lo dice:
  «Se pidió el Excel en CUP y esta sucursal no tiene tasa de cambio: no se convierte
  ningún importe con la tasa de otra.»

### Dónde acaba el fichero

| Dónde | Qué pasa |
|---|---|
| **Web** | Lo descarga el navegador: «Se descargó reporte-procovar-2026-09-28.xlsx» |
| **APK (Android)** | Se escribe y **se abre el cajón de compartir**: «Excel listo: elegí dónde mandarlo o guardarlo.» Puedes mandarlo por WhatsApp, Telegram, correo o guardarlo en Archivos |
| **Escritorio** | Se **guarda en la carpeta de descargas** y te dice dónde: «Excel guardado en /home/jose/Descargas/reporte-procovar-2026-09-28.xlsx» |

Se escribe primero y se comparte después, así que **aunque el cajón de compartir no
salga, el fichero ya está guardado**.

---

## Lo que esta pantalla NO hace

- **No pregunta al servidor en directo.** Cuadra con lo que hay bajado, y te dice de
  cuándo es.
- **No escribe ceros donde falta un dato.** Ni en pantalla ni en el Excel.
- **No convierte a CUP con la tasa de otra sucursal.**
- **No se manda por correo desde aquí** (en Android se puede compartir con el cajón
  del sistema).
