# delivery-logistica — lo que hay que saber antes de tocar nada

Este fichero se carga solo al abrir cualquier cosa de este repo. El de
`procovar/CLAUDE.md` sigue mandando sobre lo del servidor y las credenciales;
esto es lo de **este** proyecto.

---

## 1. LA REGLA QUE MANDA SOBRE TODAS: qué trabaja sin conexión y qué no

Son **tres** formas de la misma aplicación y **no se comportan igual**. Esto no
es un detalle de implementación: es la razón de existir del proyecto, y Jose lo
ha tenido que repetir tres veces.

### La web NO trabaja sin conexión. Nunca.

> «el trabajo sin conexion es solo para las aplicaciones cojone la web siempre va
> a estar en internet»
> «la web siempre va a tener el internet por q esta en la nube eso es para la apk
> y la desktop quitame eso de la web»

En la web **no se enseña nada** del aparato de sin-conexión: ni «Configurando
Reparto», ni el botón de traer o entregar el día, ni la franja de «trabajando sin
conexión», ni el aviso de que el aparato no guarda la sesión. Se entra y ya se
está dentro.

### Y NO TIENE BASE LOCAL. Eso también es la regla, no un detalle

Esto estuvo escrito a medias y costó caro. Decía que la base local «sigue ahí por
dentro, como una caché de la que nadie habla». **Mal.** Jose, 16/09/2026:

> «la web es para eso, el desktop y las apks tienen su propia base de datos para
> trabajar sin conexión; la web siempre está con conexión porque está en el
> servidor»
> «la web siempre está en vivo porque saca de la base de datos de la nube, no de
> una extra»

La base local existe **para la APK y el escritorio**, que son los que se van sin
señal. El sincronizador está para eso: subir lo que se hizo sin conexión y dejar
el aparato al día para el siguiente día sin señal. **La web no necesita nada de
eso y no debe tenerlo.**

Lo que pasa si se le deja una caché, y pasó: la web guardó su cola, la cola se
atascó, el tablero **se negó a bajar durante hora y media para no pisar lo que no
había subido**, y la pantalla enseñaba una foto vieja mientras el teléfono subía
sin problema. Refrescar no hacía nada. Una caché en un navegador sólo puede
mentir: no hay ningún caso en el que gane algo.

**La prueba de si algo sobra en la web:** ¿sirve de algo a alguien que tiene
internet ahora mismo? Si la respuesta es «le guarda lo que hizo por si se cae la
red», fuera de la web.

Lo que sí se dice en la web es que **ahora mismo** no hay conexión, si la pierde
a mitad. Lo que se quita es el aparato de **prepararse** para no tenerla.

### La APK de Android y la de escritorio SÍ, y tienen que hacerlo perfecto

> «las apk la de androide y la de desktop»

Ahí está todo: la configuración inicial con su porcentaje, traer el día,
entregarlo, trabajar la jornada entera sin señal, y que la sesión sobreviva a
cerrar la aplicación. **Es su razón de ser y no se negocia.**

La regla de la sesión, de `docs/identidad.md`:

> Para entrar hace falta conexión. Una vez dentro, no.

Y su contrapartida, que hay que tener presente al tocar esto: el par de tokens
dura 30 días (el de acceso, 15 minutos). Pasados ésos, o si Accesos rechaza la
renovación, la sesión muere y se vuelve a la puerta. Quien sea dado de baja deja
de entrar **en cuanto su aparato tenga señal**, no antes.

### Cómo se decide, en una pregunta

**¿Esto le sirve a alguien que abre un navegador con internet?** Si la respuesta
es «le explica algo que en su caso nunca pasa», fuera de la web.

---

## 2. El patrón se sigue SALVO donde se equivoca

`/mnt/datos/Work/procovar/delivery` (Next) es el patrón y casi siempre tiene
razón: sus comentarios largos guardan incidentes de verdad que costaron dinero.
Pero copiarlo con los ojos cerrados también trae sus fallos.

Cuando nos separemos del patrón, **se escribe por qué en el código**, con el caso
concreto. Ya hay tres así:

- **Reportes SÍ va en el menú.** El Next no lo tiene en su barra lateral y sólo
  se llega desde las acciones rápidas del Panel. Copiado fielmente, Jose no
  encontró la pantalla.
- **Un tipo de vehículo sin costo por km se deja VACÍO, no en cero.** El Next
  escribe `0`, y un cero guardado se lee como «el kilómetro es gratis»: un número
  creíble y equivocado. Un hueco se ve y se rellena.
- **Los avisos del armador son aviso, no bloqueo.** Los datos reales tenían 657
  de 686 domicilios sin costo: bloquear habría dejado la aplicación inservible.
- **El estado de cada parada se pregunta AL COMPLETAR la ruta, no después.** El
  Next deja el botón `Cierre` vivo sobre una ruta ya completada, y ahí se
  equivoca: cerrar una ruta *es* cuadrar lo que bajó del camión, así que la
  pregunta va antes, no después. Jose, 17/09/2026, viendo el cierre ofrecido
  sobre una ruta cerrada: «ese estado se pone cuando están en ruta, no
  completados; ahí el cierre ya viene con el estado de cuando le van a dar a
  completado, es que se pregunta ese estado». En una ruta `completed` el cierre
  se mira y no se toca: ni botones de marcar apagados, ni botón de guardar.
  `ModoDelCierre` en `app/lib/pantallas/rutas/vista/cierre_de_ruta.dart`.

---

## 3. Pedir un tope y no comprobar el resultado

**En un día cazamos tres veces el mismo fallo**, y por eso está aquí:

1. La bajada del aparato se quedaba en **2.000 clientes clavados** de 8.034: el
   servidor servía `LIMIT 2000` sin desplazamiento y marcaba `truncado`, y la
   tanda siguiente pedía exactamente lo mismo.
2. El barrido del espejo pedía `limit=5000` y **no miraba cuántos venían**.
   PEDIDO corta sin decirlo: **2.284 pedidos perdidos** en una sola ventana, con
   200 OK.
3. `POST /api/admin/recompute` pedía 5.000 de una ventana de 30 días que hoy son
   ~13.000. **Ya no se lo calla** (21/09/2026): el tope es `TopeDelRecosteo` para poder
   compararlo, y si vuelven justo esos 5.000 la respuesta lleva `truncado` y un aviso que
   dice cuántos días reducir. Paginar no se puede —`/integration/orders` no da cursor—; lo
   que sí se hace es partir la ventana en tramos, y eso ya lo hace `internal/espejo`, que
   es quien barre el histórico. Pruebas en pareja (avisa cuando toca y **no** avisa cuando
   no) en `api/internal/api/sync_tope_test.go`.

La regla: **si pides un tope, comprueba si lo alcanzaste**, y si no puedes seguir
paginando, dilo con un aviso que nombre lo que se quedó fuera. Un truncamiento en
silencio es el fallo que más caro sale aquí, porque no se ve.

Y su pariente: **una respuesta vacía no es una respuesta buena.** Un catálogo de
Ventra vacío es un ERROR, no «no hay productos»: una base caída devuelve `[]` sin
error.

---

## 3-bis. Dos preguntas sobre lo mismo que se separan sin que salte nada

El 17/09/2026 el tablero de La Habana decía **«Sin colocar (722)»** encima de una
lista de **293**. Ni un error, ni una pantalla en blanco, ni un tirón: sólo un
número 429 unidades más alto de lo real. A `ContarPedidosSinColocar` le faltaba
`AND NOT o.archivado`, que `ListarPedidosSinColocar` tenía desde el 15/09. Tres
días así. Encima, el comentario que había sobre el contador ya lo avisaba —«tiene
que ser el mismo o dice 358 encima de una lista de 120»— y no sirvió de nada,
porque **un comentario no falla**.

La regla: cuando dos consultas tienen que contestar lo mismo —una lista y su
contador, un total y su detalle, un aviso y lo que cuenta—, **hay que atarlas con
una prueba, no con un comentario**. Está hecho para ésta en
`api/internal/store/contador_y_lista_test.go`, que compara el `WHERE` **y** el
`FROM` con sus `JOIN` (un `JOIN` filtra igual que un `WHERE`; que se escriba en
otra línea es cosa de SQL, no del contrato).

Lo que esa prueba **todavía no cubre**, y hay que saberlo: los parámetros se
copian a mano en Go (`api/internal/api/tablero.go`, al armar
`ContarPedidosSinColocarParams`). Quitar ahí un `Municipio:` deja toda la suite en
verde y el número vuelve a mentir.

---

## 3-ter. Una respuesta que se pide UNA vez sobre algo que cambia después

En la APK la base sobrevive, así que al pintar una pantalla los datos ya están.
**En la web la base es en memoria y nace vacía en cada carga**, y el ciclo la
llena un segundo más tarde. Ahí, un `FutureProvider` —una sola respuesta, la del
instante en que se pinta— se queda **congelado en el peor momento posible**.

Lo que se veía el 17/09/2026 en `/orders`: la cabecera diciendo «299 pedidos», el
pie diciendo «Mostrando 1-50 de 299», y en medio «Esta pantalla no se ha
descargado todavía». El total y la página eran `Stream` y se enteraban; el cartel
no. Lo mismo en Rutas, en los desplegables de filtros de Pedidos y en la lista de
camiones del Tablero — **cuatro sitios, el mismo patrón**.

La regla: **lo que se pinta y puede cambiar cuando llega la bajada va por
`Stream`**, no por `Future`. `RegistroDeFrescura.mirar` para la frescura, y
`tableUpdates` para lo que sale de una tabla. `seDescargo` sigue ahí para decidir
en seco, donde no hay nada que repintar.

Y la prueba que lo caza tiene una forma concreta, porque las que había no valían:
**montar con la base VACÍA y sembrar DESPUÉS, sin volver a montar la pantalla.**
Sembrar en el `setUp` es justo el caso que un `Future` resuelve bien. Moldes en
`app/test/pantallas/pedidos/llega_la_bajada_test.dart` y su gemelo de rutas.

---

## 3-quater. El proxy se queda con `/api` y con `/sync` antes que la aplicación

En el servidor, Traefik reparte por camino, y lo suyo no llega nunca a la web:

```
Host(`reparto.procovar.cloud`) && PathPrefix(`/api`)   -> el reparto
Host(`reparto.procovar.cloud`) && PathPrefix(`/sync`)  -> el sincronizador
Host(`reparto.procovar.cloud`)                         -> la aplicación
```

La pantalla de Sincronización vivía en `/sync`. Por el menú funcionaba —eso lo
resuelve el enrutador dentro del navegador, sin pedirle nada al servidor— y por
eso nadie lo vio: **el único camino que falla es recargar ahí o abrir el enlace**,
y entonces contesta el sincronizador con un `401` que no tiene nada que ver con la
aplicación. Movida a `/sincronizacion`; el prefijo no se toca, que es la dirección
que ya usan las APK instaladas.

Y es prefijo de **cadena, no de segmento**: `PathPrefix(/sync)` atrapa
`/sync-estado` igual que `/sync`. Lo vigila
`app/test/navegacion/contrato_registro_test.dart`.

---

## 3-quinquies. Quitar un aviso de la web deja un agujero que hay que tapar

El 17/09/2026 se quitaron de la web, y bien quitados, el sello «Datos de las
10:36», el «N sin subir», el «Visto por última vez a las…» y el «conecta y espera
a que suba» de cerrar sesión. Todos hablan de **tu copia** y de **tu cola**, y en
un navegador no hay ninguna de las dos.

Pero ese «N sin subir» era lo único que delataba un gesto que no llegó. Sin él: la
tarjeta se mueve en la pantalla, el servidor dice que no, y **no se entera nadie**
hasta que alguien recarga y la ve volver a su sitio.

La regla: **en la web, lo que el servidor rechaza se dice, y con su motivo
literal.** «Ese pedido ya va en otra ruta» le dice a alguien qué hacer; «no se
pudo guardar» no le dice nada.

Y la trampa de al lado, que casi sale peor que el agujero: el primer intento fue
esperar al ciclo tras cada gesto y mirar si la cola quedaba vacía. **Eso salta en
CADA movimiento**, porque un apunte está legítimamente pendiente ese instante. Un
aviso que sale siempre deja de leerse, y entonces tampoco se lee el día que
importa. Lo único inequívoco es un apunte **rechazado**. Por eso las pruebas de
esto van en pareja: una que el aviso salga cuando toca, y otra que **no salga**
cuando no.

---

## 4. Lo que no puede pasar nunca

- **Nada se descarta en silencio.** Un apunte rechazado se queda a la vista con
  su motivo hasta que una persona decida. Una colección que no bajó se dice, y se
  dice **qué se rompe sin ella**. Si algo falla, la pantalla **no se queda
  verde**.
- **El alcance sale de quién pregunta, no de lo que mande el cliente.** Si
  saliera del parámetro, el logístico de Camagüey vería las otras siete
  cambiándolo. Ya pasó en delivery: un operador de Santiago vio los precios de La
  Habana.
- **La tasa es POR SUCURSAL** y sin la de esa sucursal no se convierte nada: no
  se cae a la de otra ni a un número por defecto. En PEDIDO está contado así:
  «Granma enseñaba los 685 de La Habana como si fueran suyos: un importe así se
  lee bien y está mal, que es lo peor que puede pasarle a un número que alguien
  va a cobrar».
- **Quitar algo es quitarlo ENTERO**: sus tipos, sus llamadas, sus enlaces, su
  entrada de menú y sus pruebas.
- **Cajón siempre**, también en escritorio (excepción aprobada para este
  proyecto el 05/09/2026). Sin emojis en la interfaz.
- **Una decisión de una persona se ESCRIBE, no se borra.** Borrar no es decidir:
  borrar deja un hueco, y otra pieza rellena ese hueco con lo que ella cree.

  El 29/09/2026 costó semanas de «los errores se acumulan y nunca se borran»
  (Jose). El botón «Descartar» de la bandeja existía y **borraba de verdad** —
  ése era el fallo. Al irse el apunte, la fila que iba a subir se quedaba sin
  nada que la nombrara, o sea huérfana, el ciclo la reencolaba, el servidor
  repetía su «no» y el rechazo volvía a la bandeja con clave nueva. Ninguna
  pieza mentía: fallaba la junta de tres.

  Ahora `descartar` marca `EstadoApunte.descartado` y lo huérfano lo lee como
  «esto ya se decidió». Y la segunda mitad, sin la cual se cambia un bucle por un
  atasco: **también hay que soltar lo que protegía esa fila** (`nacio_aqui`), o la
  bajada no la toca nunca más.

  Su pariente, y por eso va aquí: **un aviso sin acción es un aviso que se queda
  puesto para siempre.** «Sólo en este aparato» contaba trabajo que no iba a
  subir y no tenía ni un botón. Si algo espera «hasta que una persona decida»,
  tiene que haber **con qué** decidir desde donde se está mirando.
- **Los botones van SIN FONDO.** Lo que los diferencia es el **color, el borde y
  el icono**, no un rectángulo relleno. Jose lo ha dicho más de una vez y el
  28/09/2026 tuvo que repetirlo —«te dije bien claro q sin background y de
  colores y los bordes y iconos lo diferenciaban»—, así que queda escrito aquí:
  **si no está en este fichero, se pierde**, y perderlo cuesta que lo diga otra
  vez.

  La jerarquía no desaparece, cambia de material: la acción principal se
  distingue por su color y su icono, no por ir rellena. Lo que decide es el
  tema (`app/lib/diseno/tema.dart`), no un `style:` puesto a mano en cada
  pantalla — un relleno suelto en un fichero es lo que hace que dentro de un mes
  haya dos aspectos en la misma aplicación.

  **Y el icono no lo puede poner el tema**, porque es un hijo del widget y no
  una propiedad del estilo: el mismo 28/09/2026 quedaban **25 `FilledButton(`
  sin icono contra 9 con él**, o sea la mayoría de las acciones principales con
  dos rasgos de los tres. Así que lo principal entra por `BotonPrincipal` igual
  que lo destructivo entra por `BotonDestructivo` — **el icono es obligatorio en
  el constructor y no tiene valor por defecto**. Ni `FilledButton(` ni
  `ElevatedButton(` a pelo: los dos cuelgan del mismo nivel y lo vigila
  `app/test/diseno/el_principal_lleva_su_icono_test.dart`, que barre `lib/`.

  Y el icono es **el de SU acción**, uno por uno: guardar, añadir, armar,
  imprimir, traer, entregar, reintentar. El mismo glifo repetido no diferencia
  nada, que es justo lo que se vino a arreglar. Cuando una acción no tenga
  ninguno honesto —una pestaña, por ejemplo, que no es una acción sino dónde
  estás— **no se le pone uno cualquiera**: se escribe aparte y se explica por
  qué, como `_Pestana` en `app/lib/diseno/pestanas.dart`.

---

## 3-sexies. El peso de un renglón son TRES escalones, y un cero no es ninguno

El 28/09/2026 la hoja de pre-despacho enseñaba **el mismo peso para Santiago que para
las ocho sucursales**, idéntico hasta el decimal, con un 68 % más de empaques. Los
empaques y las unidades sí se recalculaban; los kilos se quedaban clavados. Se vio en un
teléfono, no en una prueba.

La causa: la cascada tenía **dos** escalones —`peso_linea_kg` y el catálogo local— y le
faltaba el de en medio, `peso_kg × empaques`, que es lo que pesa UN empaque y viene en el
propio renglón. Como el catálogo local **no trae el peso de ningún producto**, un renglón
con `peso_kg` y sin `peso_linea_kg` no aportaba ni un kilo **y se iba entero al contador
de «sin peso»**: por eso lo que entraba de más al ensanchar el alcance sólo movía el
contador y dejaba la cifra quieta.

Los tres escalones, en este orden:

1. `peso_linea_kg` — lo que pesa la línea entera, ya multiplicado;
2. `peso_kg × empaques` — lo que pesa un empaque, por los que van;
3. el catálogo local — `products.weight × empaques`.

**Y un CERO no es un peso: es «este escalón no lo sabe».** Con un `COALESCE` a secas, un
`peso_linea_kg` guardado en cero tapa los dos escalones de debajo y la celda dice
`0.0 kg` teniendo el dato. Cada escalón pasa por su `> 0`.

### Y la regla vive en UN sitio, no en tres — la misma noche

La regla estaba escrita TRES veces: `api/internal/cotizar/pesos.go` (`PesosDeRenglones`,
§2.1 de `reglas-negocio.md`), la ficha del pedido y el pre-despacho, los dos últimos en
`pantallas/pedidos/datos/repositorio_pedidos.dart`. Y **estuvieron distintos**: la ficha
decía «40,0 kg» y la hoja del almacén ponía «—» sobre los mismos veinte empaques. Jose:
«como q 3 veces lo repetiste mijo era mas facil ponerlo en el api y ya q lo consuman una
cada uno».

Y el proyecto **ya estaba diseñado así**: la `00004_peso_por_renglon.sql` añadió
`peso_linea_kg` y `origen_peso` «precisamente para no tener que recalcular el peso con el
catálogo de hoy sobre un pedido de hace tres meses». Los tres sitios no eran el diseño:
eran una desviación suya, y por eso se desincronizaron.

Así que **el servidor resuelve y el aparato LEE**. La cascada corre una vez, al entrar el
pedido; el resultado se escribe en `order_items.peso_linea_kg`, viaja en `pesoLineaKg` y la
aplicación lo lee de su base local —con señal o sin ella: el trabajo sin conexión no
pierde nada, es la misma columna que ya bajaba—.

Lo único que la aplicación repite es **la regla del cero**, y a propósito: un
`peso_linea_kg` vacío o en cero es «no se sabe» y se pinta «—», nunca «0,0 kg». Está
escrita dos veces —`soloSiPesa` en Dart y `_siPesa` en SQL— y que las dos contesten igual
lo ata `app/test/pantallas/pedidos/el_peso_del_pre_despacho_cambia_de_sucursal_test.dart`,
que es también donde viven las otras tres guardas de esa noche.

**Lo que hay que saber antes de tocar el espejo:** ya no hay red de seguridad. Un renglón
que se escriba sin `peso_linea_kg` sale «—» en la ficha, en la hoja del almacén y en el
papel, y cuenta entero en «sin peso». Y los renglones **viejos** no se arreglan solos: el
espejo sólo vuelve a pedirle a PEDIDO lo que se movió desde la marca de agua, así que un
cambio que sólo afecta al cálculo no llega nunca a las filas de hace tres meses. Hay que
relanzarlas (`internal/espejo`, el barrido del histórico, o `POST /api/admin/recompute` por
tramos). Lo que SÍ funciona sin ayuda es la reescritura: `renglonesIguales` compara
`peso_linea_kg` y `origen_peso`, así que en cuanto un pedido vuelve a pasar por el lote sus
renglones se reescriben aunque la fila del pedido no haya cambiado.

---

## 4-bis. El auditor NO es opcional

Hay un auditor en `.claude/agents/auditor-del-reparto.md` con su skill
`auditar-el-reparto`. **Se lanza antes de cada commit y antes de cada
despliegue**, sin excepción, y se le va contando lo que se hace según se hace —
no se le entrega el código al final.

No es celo. El 16/09/2026 se metieron en producción, todos con «Todo en verde»:
la cola del tablero contestando 401 y sin subir nada; 84 lotes de PEDIDO
rechazados con 403; una mutación de prueba desplegada por un `git add -A`; y una
carga inicial que dejaba 2.000 de 8.103 clientes dándose por completa. Ninguna la
habría visto leer el diff. Todas se cazan ejecutando y rompiendo guardas.

Dos reglas que salieron de ese día:

- **Nunca `git add -A` mientras un agente está mutando el árbol.** Se le lleva la
  mutación al commit. Pasó, y se desplegó.
- **Los tres Dockerfile corren sus pruebas antes de construir.** `Dockerfile.api`
  y `.sync` hacen `go vet && go test`; `Dockerfile.app` hace `flutter analyze` y
  `flutter test`. Poner eso en la imagen de la web costó dos
  intentos y los dos enseñan lo mismo —**una imagen no es esta máquina**—:
  `.dockerignore` excluía los textos generados y `analyze` no los genera (sí lo
  hacía `build web`, que era lo único que había antes), así que hubo que meter un
  `flutter gen-l10n` delante — **ese paso ya no está**: la traducción al inglés se
  quitó entera el 24/09/2026 y con ella los `.arb`, el `l10n.yaml`, la clase
  generada, el `generate: true` del pubspec y la línea del `.dockerignore`
  (`app/lib/idioma.dart`); y las pruebas abren bases
  de verdad con Drift, así que hace falta `libsqlite3-dev` — **el `-dev`, no el
  `-0`**, porque el `-0` instala `libsqlite3.so.0` y Dart abre la biblioteca por
  su nombre sin versión. El de sync sólo compilaba, y por eso la mutación llegó al
  servidor. El de la web se quedó sin arreglar aquel día y estuvo un día entero
  construyendo sin pasar una sola prueba — el mismo agujero, en el otro lado.
- **Con agentes escribiendo a la vez, no se lanza `./comprobar.sh`.** Mide un
  árbol a medio escribir y contesta `FALLA` sobre ficheros que están bien: el
  17/09/2026 dio dos falsos rojos seguidos mientras cuatro agentes trabajaban.
  Cada agente comprueba **lo suyo** (`flutter analyze <carpeta>`, sus pruebas con
  `timeout 300`, o `go build && go vet && go test` en `api/`), y el guion entero
  se pasa **una vez, al final**, cuando todos han soltado los ficheros. Y por lo
  mismo: **no se despliega con agentes vivos.**
- **A cada agente se le dice qué ficheros NO puede tocar**, con la lista de lo que
  tienen los demás. Sin eso se pisan, y el que pierde es el que no se entera.
- **NO SE MUTA UN FICHERO QUE OTRO AGENTE TIENE ABIERTO, aunque el guion
  restaure por hash.** El 17/09/2026 se mutaron seis guardas de
  `detalle_ruta.dart` mientras su agente seguía escribiéndolo. Cinco salieron
  rojas; la sexta salió **verde sin serlo** —a mano fallaba— y, al acabar, el
  `if (false)` de otra de las mutaciones **seguía puesto en el árbol**. El guion
  restauraba, sí, pero el agente escribía encima entre medias y se perdía la
  carrera. Si eso llega a un `git add`, es la mutación desplegada del 16/09 otra
  vez, con la diferencia de que esta vez la puso quien audita.

  Las dos señales de que ha pasado, y las dos hay que mirarlas: **una mutación
  que sale verde** no es una prueba floja hasta que se comprueba a mano, y al
  terminar se barre el árbol —`grep -rn "if (false)\|if (true)\||| true)"` fuera
  de las pruebas— **antes** de tocar git. Se muta cuando el fichero es de uno, y
  si no lo es, se espera.
- **Cada agente muta lo suyo y nadie muta lo del vecino.** Por eso la auditoría
  del final tiene que romper guardas que NO escribió quien las audita. El
  17/09/2026, con todo «en verde» y cinco agentes que habían mutado cada uno su
  parte, la pasada final encontró **tres mutaciones que nadie cazaba**: un
  parámetro del contador quitado (toda la api verde), un tipo de aviso renombrado
  en Go (toda la api verde, y Flutter sin enterarse), y la guarda que evita el
  «Vista (0)» puesta a `false` (853 pruebas verdes).
- **Una guarda que sólo se recalcula al bajar la foto no se entera de lo que pasa
  después.** El aviso de «el servidor rechazó tu cambio» se calculaba dentro de
  la bajada, que corre al cambiar de sucursal y con un aviso del canal — y el
  rechazo llega **después**, con la pantalla ya abierta. No salía nunca. Y la
  prueba no lo cazaba porque sembraba el rechazo ANTES de montar, que es justo la
  forma que prohíbe el §3-ter, escrita aquí y rota el mismo día. **Lo que cambia
  con la pantalla delante se vigila con un stream sobre la tabla**, no
  preguntando cuando uno se acuerda.

## 5. Cómo se comprueba

`./comprobar.sh` desde la raíz: gofmt, vet, test, build y `sqlc diff` en `api/` y
`sync/`, y `analyze` + `test` en `app/`. Tiene que decir **«Todo en verde»**.

- `sqlc` está en `~/go/bin/sqlc`. **El código generado no se escribe a mano.**
- **Pruebas colgadas**, y son DOS trampas hermanas, las dos de lo mismo: dentro
  de un widget test el tiempo lo manda el `tester` y no avanza solo.
  1. Nada de `await` sobre el primer valor de un stream de Drift ahí dentro: la
     prueba **se cuelga en vez de fallar**, que es lo peor que puede hacer una
     prueba.
  2. **Nada de sembrar la base en el `setUp` de un `testWidgets`.** El `setUp`
     corre fuera del reloj falso, y lo que Drift deja empezado allí no avanza
     dentro: el 17/09/2026 un cajón se quedó girando diciendo «no hay ninguna
     zona» encima de un tablero con dos, y la prueba no fallaba, se colgaba. La
     base se abre donde sea, pero **se escribe y se lee dentro del cuerpo**.

  Usa `timeout 300` siempre: es lo único que convierte un cuelgue en un fallo.
- **Una prueba que copia la dirección del código que prueba no comprueba la
  dirección.** Las del Tablero repetían `/api/api/board` y todo salía verde
  mientras las diez llamadas daban 404.
- **Mutación**: rompe la guarda a propósito y comprueba que hay una prueba que la
  caza y que lo dice con un mensaje entendible. Si no la caza, la prueba no vale.

### La regla dura del entorno

`lib/nucleo/red/entorno.dart` tiene las URL de **producción** como `defaultValue`,
así que un `flutter build web` sin `--dart-define` deja una aplicación que llama a
`reparto.procovar.cloud` en cuanto alguien la abre. El `CLAUDE.md` de Procovar
prohíbe cualquier petición a un dominio de Procovar desde este PC —a la oficina le
bloquearon la IP por eso—, así que:

```bash
flutter build web --dart-define=API_URL=http://127.0.0.1:8099/api ...
grep -c "procovar\.cloud" build/web/main.dart.js   # tiene que dar 0
```

Y **cierra las pestañas y para los servidores al terminar**: una aplicación viva
dispara un ciclo de sincronización cada pocos minutos. Ya pasó.
