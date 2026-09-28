# Clientes

**Para qué sirve:** consultar a quién le repartimos, dónde vive, qué teléfono
tiene y a qué distancia está del almacén.

Debajo del título:

> «Clientes de PEDIDO (sincronizados, sólo con geo) + los manuales de delivery.
> 1842 en total»

**Esta pantalla es sólo de consulta. Aquí no se crea, ni se edita, ni se borra
nada.**

---

## Los filtros

Los que salen de la base **sólo aparecen si tienen más de una opción**.

| Filtro | Por defecto | Opciones |
|---|---|---|
| **«Municipio del cliente»** | «Todos los municipios» | Cada municipio con cuántos clientes |
| **«Vendedor que lo atiende»** | «Todos los vendedores (37)» | Cada vendedor con cuántos clientes |
| **«A qué distancia del almacén»** | «A cualquier distancia» | «Hasta 5 km», «Hasta 10 km», «Hasta 20 km», «Hasta 50 km» |
| **«Si tiene teléfono»** | «Con y sin teléfono» | «Con teléfono», «Sin teléfono» |
| **«Zona de reparto»** | «Todas las zonas» | Cada zona con cuántos clientes |
| **«De dónde salió el cliente»** | «De PEDIDO y manuales» | «Sólo los de PEDIDO», «Sólo los manuales» |

El **buscador** dice «Buscar por nombre, dirección o municipio…» pero busca en
**siete** sitios: nombre, dirección, municipio, zona, teléfono, código y vendedor.

El botón **«Quitar filtros»** aparece sólo si hay municipio, zona, origen o
búsqueda puestos. **La distancia y el teléfono no lo hacen aparecer.**

**La distancia se mide en línea recta desde el almacén principal de la sucursal**,
con dos decimales.

---

## Las columnas

| Columna | Qué lleva |
|---|---|
| **«Cliente»** | El nombre, el código debajo, y el teléfono o **«sin teléfono»** en ámbar |
| **«Dirección»** | «Calle 5 nº 12 · Songo-La Maya», o «—» |
| **«Vendedor»** | El vendedor, o «—». Debajo los km, **sólo si has filtrado por distancia** |
| **«Origen»** | **«PEDIDO»** (azul) o **«Manual»** (gris) |

**Las filas se pulsan pero no se marcan**: aquí no hay nada que hacer con una
selección de clientes.

En pantalla estrecha, cada cliente es una tarjeta.

---

## La ficha de un cliente

Se abre tocando la fila. **No consulta nada nuevo**: enseña lo que la lista ya
tiene. Nueve datos, en este orden:

1. **«Teléfono»** — el número, o «sin teléfono» en ámbar. Va primero a propósito:
   es lo que más se busca.
2. **«Código»**
3. **«Dirección»** — aquí se lee **entera**, sin recortar
4. **«Municipio»**
5. **«Zona de reparto»**
6. **«Vendedor»**
7. **«Distancia al almacén»** — «4.35 km». Si no se sabe, «—» y la nota: «Esta
   sucursal no tiene ningún almacén con coordenadas.»
8. **«Sucursal»**
9. **«Coordenadas»**

Lo que no se sabe se pinta «—».

---

## De dónde salen los clientes

- Los de **«PEDIDO»** entran solos por sincronización, y **sólo los que tienen
  geolocalización**. Un cliente de PEDIDO sin coordenadas no aparece aquí.
- Los de **«Manual»** son los que se dieron de alta a mano antes del 03/09/2026.
  No llevan sucursal, así que **se ven desde todas**.

---

## Avisos, vacíos y paginación

Si la sucursal no tiene almacén con coordenadas, encima de la lista:

> «Esta sucursal no tiene ningún almacén con coordenadas: aquí no se puede medir la
> distancia.»

Vacíos:

- **Sin filtros**: «Sin clientes todavía. Los de PEDIDO aparecen solos cuando
  tengan geolocalización.»
- **Con filtros**: «Sin resultados.»
- **En la APK, si no bajó**: «Esta pantalla no se ha descargado todavía. Con
  conexión baja sola.»

**50 clientes por página.** Al pie: «51–100 de 1842» a la izquierda, y a la derecha
**«Anterior»**, «2 / 37» y **«Siguiente»**.

Detalle: cuando filtras por distancia, **la última página puede traer menos de
50**. No es un fallo: el total se cuenta antes y la distancia exacta se mide
después, sólo sobre la página.

---

## Lo que Clientes NO hace

- **No se crean clientes.** El alta a mano se retiró el 03/09/2026.
- **No se editan.** La ficha es texto, sin campos ni botón de guardar.
- **No se borran.**
- **No se marcan ni se seleccionan.**
- **No se exporta ni se imprime** desde aquí.
- **No se ve un cliente de PEDIDO sin coordenadas.**

Todo lo de esta pantalla **se mira sin conexión** (en la APK y en el escritorio),
incluidos los kilómetros, que se calculan en el propio aparato.
