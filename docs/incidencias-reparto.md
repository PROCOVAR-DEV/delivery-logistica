Incidencias y requerimientos — Reparto Procovar
Módulos involucrados: Rutas, Tableros, Facturas, Vehículos, Pedidos
Fecha: [pendiente]
Responsable: [pendiente]

1. Cierre de ruta no se completa al guardar y completar
Problema
En el proceso de cierre de ruta, al guardar y completar, la ruta no se está cerrando.

Evidencia
Endpoint invocado:
POST https://reparto.procovar.cloud/api/routes/396ebad7-074b-4983-8492-f6649b3965ae/results

Status code: 409 Conflict

Respuesta recibida:

json
{
    "error": "Se guardaron 1 de las 2 paradas de esta hoja. 1 no se pudieron guardar: 8cb90608-76da-4fae-879d-126ff9ab4c3c (ese pedido no va en esta ruta).",
    "aplicados": [
        {
            "orderId": "77c0385c-3900-4497-94fa-945a7dc27da0",
            "resultado": "entregado"
        }
    ],
    "rechazados": [
        {
            "orderId": "8cb90608-76da-4fae-879d-126ff9ab4c3c",
            "motivo": "ese pedido no va en esta ruta"
        }
    ],
    "aPedido": {
        "ok": true,
        "enviados": 1,
        "aplicados": 1,
        "http": 200
    }
}
Comportamiento esperado
Al guardar y completar una ruta, esta debe cerrarse correctamente.

Si una parada es rechazada porque el pedido no pertenece a la ruta, debe mostrarse un error claro y controlado, pero no debe impedir el cierre cuando corresponda.

Revisar la validación que asocia pedidos con rutas, ya que actualmente permite enviar una parada que luego el backend rechaza con 409 Conflict.

Criterios de aceptación
El endpoint POST /api/routes/{id}/results debe responder correctamente cuando las paradas son válidas.

La ruta debe cambiar a estado cerrado/completado cuando el usuario guarda y completa.

No deben enviarse pedidos que no pertenecen a la ruta.

Si existe un rechazo, debe informarse al usuario y permitir corregir sin bloquear todo el flujo.

2. Asociar facturas en tablero sin cotizar domicilio
Problema
Al asociar facturas en un tablero, se está permitiendo incluir facturas sin cotizar el domicilio. Esto no debería permitirse. La validación debe ser obligatoria.

Problema adicional
Si una factura ya fue planificada y se desea sacarla de la ruta, no existe esa opción. Actualmente hay que eliminar toda la ruta planificada.

Comportamiento esperado
No permitir asociar facturas al tablero si no tienen el domicilio cotizado.

Validar esta condición de forma obligatoria.

Permitir quitar una factura individual de una ruta planificada, sin necesidad de eliminar toda la ruta.

Criterios de aceptación
La UI/API debe bloquear facturas sin cotización de domicilio.

Debe mostrarse un mensaje claro al usuario.

Debe existir una acción tipo “Quitar de ruta” para facturas ya planificadas.

No debe ser obligatorio eliminar toda la ruta para sacar una sola factura.

3. Eliminación de ruta completa generada desde tablero
Problema
Si se elimina una ruta completa que fue generada desde el tablero, se elimina la relación de las facturas con el tablero. El tablero queda limpio, lo que obliga a volverlo a crear.

Comportamiento esperado
Al eliminar una ruta completa generada desde el tablero, las facturas deben restaurarse en el panel de la zona escogida.

No debe perderse la relación entre las facturas y el tablero de origen.

Criterios de aceptación
Al eliminar una ruta, las facturas vuelven al tablero/zona correspondiente como disponibles o no planificadas.

No se debe perder la relación factura–tablero.

El usuario debe poder replanificar sin tener que recrear manualmente el tablero.

4. Eliminación de vehículos con rutas históricas
Problema
El sistema permitió eliminar un vehículo que tiene rutas asociadas que ya están en el histórico. Esto no debe permitirse.

Comportamiento esperado
No permitir eliminar un vehículo si tiene rutas asociadas, incluyendo rutas históricas.

Debe existir la opción de INACTIVAR un vehículo si ya ha sido utilizado.

Para nuevas rutas, la selección de vehículos debe mostrar únicamente los vehículos activos.

Criterios de aceptación
La eliminación de un vehículo con rutas asociadas debe ser rechazada con un mensaje claro.

Debe existir un estado activo/inactivo para vehículos.

Los vehículos inactivos no deben aparecer en la selección para nuevas rutas.

La selección de vehículos para nuevas rutas debe filtrar solo activos.

5. Eliminar columna Vehículo de orders
Requerimiento
Eliminar la columna Vehiculo de la tabla orders.

Criterios de aceptación
Crear migración para eliminar la columna Vehiculo de orders.

Actualizar modelos, consultas, endpoints, reportes y UI que hagan uso de esa columna.

Verificar que no se rompa ninguna funcionalidad existente.

6. Creación de nueva ruta: solo pedidos facturados y con domicilio cobrado
Problema
Al crear una nueva ruta, solo deben considerarse los pedidos “facturados” que tengan domicilio, ya que el domicilio ahora es un servicio que se cobra. Si se permite cualquier pedido, es una vulnerabilidad.

Lo mismo ocurre con lo cotizado o no: solo se deben mostrar los pedidos facturados y con domicilio cobrado.

Caso pendiente
Falta contemplar el caso de los cobros a domicilio que salen como conduce.

Comportamiento esperado
Al crear una nueva ruta, mostrar únicamente pedidos:

Facturados.

Con domicilio cobrado.

Con la cotización correspondiente, si aplica.

No permitir pedidos que no cumplan estas condiciones.

Incluir y documentar el caso de cobros a domicilio que salen como conduce.

Criterios de aceptación
La API de creación de ruta debe filtrar solo pedidos elegibles.

No deben mostrarse pedidos no facturados, sin domicilio cobrado o no cotizados.

Debe cubrirse el caso de “cobro a domicilio que sale como conduce”.

La validación debe ser obligatoria para evitar vulnerabilidades.

Notas generales para desarrollo
Revisar relaciones entre rutas, pedidos, facturas, tableros y vehículos.

Validar que las reglas de negocio se apliquen tanto en frontend como en backend.

Agregar pruebas para:

Cierre de ruta.

Asociación y remoción de facturas.

Eliminación/restauración de rutas.

Eliminación e inactivación de vehículos.

Filtros de pedidos elegibles para nuevas rutas.

Actualizar documentación técnica y de usuario si aplica.

