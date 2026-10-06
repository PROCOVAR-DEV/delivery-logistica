/// EL CATALOGO DE CONTROLES QUE EL RECORRIDO SABE SENALAR.
///
/// Un paso del manual nombra su control con un comentario al final del renglon:
///
/// ```md
/// 1. Toca **«Agregar Vehículo»**, arriba a la derecha. <!-- señala: vehiculos-agregar -->
/// ```
///
/// Y ese nombre tiene que estar **las dos veces**: aqui, y envolviendo el control
/// de verdad con `ControlSenalado`. Las dos mitades las ata
/// `test/pantallas/ayuda/los_pasos_senalan_controles_que_existen_test.dart`:
///
///  * un nombre del manual que no este en [todos] ⇒ **rojo**. Sin eso, una letra
///    de mas deja un paso apuntando a nada y el recorrido se queda mudo justo
///    donde hacia falta;
///  * un nombre de [todos] que ninguna pantalla envuelva ⇒ **rojo**. Es el
///    sentido que se olvida: se declara el nombre, se escribe el paso, y nadie
///    pone el envoltorio. Nada falla, y el paso sale sin foco.
///
/// ## Por que los nombres son literales y no las claves de las pantallas
///
/// Las pantallas ya tienen sus `ValueKey` para las pruebas, y se podria haber
/// reusado esas. No, y por una razon: una clave de prueba se cambia sin pensarlo
/// —es de la prueba y de nadie mas—, y si el manual cuelga de ella, cambiarla
/// rompe el recorrido **en silencio**. Un nombre propio en un catalogo con su
/// prueba de las dos direcciones no se puede cambiar a medias.
///
/// ## El nombre lleva su pantalla delante, y hace falta
///
/// `vehiculos-guardar` y `almacenes-guardar` son dos botones que dicen «Guardar».
/// Sin el prefijo, el segundo que se escriba parece un duplicado del primero y
/// alguien lo borra.
library;

/// LOS NOMBRES. En UN sitio: los escribe el manual y los usan las pantallas.
abstract final class Senalado {
  // ---------------------------------------------------------------- EL PANEL
  /// La tarjeta de «lo que falta para poder trabajar».
  static const panelPasoAPaso = 'panel-paso-a-paso';

  /// El boton de «arreglar esto» del primer paso que falta.
  static const panelArreglarElPaso = 'panel-arreglar-el-paso';

  // --------------------------------------------------------------- EL TABLERO
  static const tableroNuevaZona = 'tablero-nueva-zona';
  static const tableroNombreDeLaZona = 'tablero-nombre-de-la-zona';
  static const tableroGuardarLaZona = 'tablero-guardar-la-zona';

  /// Los tres puntos de la cabecera de una zona: de ahi salen renombrar, el
  /// camion, vaciar, mover y borrar.
  static const tableroMenuDeLaZona = 'tablero-menu-de-la-zona';
  static const tableroCamionPrevisto = 'tablero-camion-previsto';
  static const tableroElegirCamion = 'tablero-elegir-camion';
  static const tableroRenombrar = 'tablero-renombrar';
  static const tableroVaciar = 'tablero-vaciar';
  static const tableroBorrarLaZona = 'tablero-borrar-la-zona';
  static const tableroArmarLaRuta = 'tablero-armar-la-ruta';

  static const tableroSinColocarBuscar = 'tablero-sin-colocar-buscar';
  static const tableroSinColocarFiltros = 'tablero-sin-colocar-filtros';
  static const tableroTarjetaDePedido = 'tablero-tarjeta-de-pedido';
  static const tableroColocarEnLaZona = 'tablero-colocar-en-la-zona';
  static const tableroSubirUnaPosicion = 'tablero-subir-una-posicion';
  static const tableroDevolverASinColocar = 'tablero-devolver-a-sin-colocar';

  /// El carrusel con el que se cambia de zona en el telefono. En escritorio las
  /// zonas van en una tira y esto no se monta.
  static const tableroCarruselDeZonas = 'tablero-carrusel-de-zonas';

  /// LA ZONA ENTERA, que es DONDE SE SUELTA lo que se arrastra.
  ///
  /// En la web y en el escritorio el reparto se hace arrastrando, y un gesto de
  /// arrastre tiene dos sitios: de donde se coge —la tarjeta,
  /// [tableroTarjetaDePedido]— y donde se deja. Sin este segundo nombre el paso
  /// «suéltala sobre la zona» no tenia a que apuntar, y el foco se quedaba en la
  /// tarjeta: justo lo que NO hay que mirar al soltar.
  ///
  /// Es tambien el blanco de reordenar zonas: el `DragTarget<ColumnaArrastrada>`
  /// que recoge una cabecera arrastrada es esta misma columna.
  ///
  /// **Sólo la primera se marca** (`ColumnaDelTablero.esLaPrimera`): hay una por
  /// zona. En el telefono la zona es la pagina entera, asi que alli el foco
  /// cubriria todo — y por eso ningun paso de `apk/` lo nombra.
  static const tableroZonaDondeSoltar = 'tablero-zona-donde-soltar';

  /// Reordenar se practica entre dos zonas distintas: la cabecera de la primera
  /// se lleva a la segunda. La primera sigue siendo el destino para un pedido.
  static const tableroSegundaZonaDondeSoltar =
      'tablero-segunda-zona-donde-soltar';

  /// LA CABECERA DE UNA ZONA, que es LO QUE SE AGARRA para reordenarlas.
  ///
  /// Reordenar zonas es arrastrar la cabecera, y **no hay ninguna otra via**: en
  /// el menu de los tres puntos no existe un «mover a la izquierda». Asi que el
  /// paso senala lo que hay que agarrar, que es esto.
  ///
  /// Sólo en pantalla ancha hay algo que reordenar, y por eso lo nombran `web/` y
  /// `escritorio/` y no `apk/`. Se marca la primera, como el ⋮ que lleva dentro.
  static const tableroCabeceraDeLaZona = 'tablero-cabecera-de-la-zona';

  // ----------------------------------------------------------------- PEDIDOS
  static const pedidosBuscar = 'pedidos-buscar';
  static const pedidosFiltroEstado = 'pedidos-filtro-estado';
  static const pedidosFiltroMunicipio = 'pedidos-filtro-municipio';
  static const pedidosOrden = 'pedidos-orden';
  static const pedidosLimpiarFiltros = 'pedidos-limpiar-filtros';
  static const pedidosAbrirElPedido = 'pedidos-abrir-el-pedido';
  static const pedidosMarcarTodos = 'pedidos-marcar-todos';
  static const pedidosMarcarUno = 'pedidos-marcar-uno';
  static const pedidosMandarAUnaZona = 'pedidos-mandar-a-una-zona';
  static const pedidosZonaDestino = 'pedidos-zona-destino';
  static const pedidosMandar = 'pedidos-mandar';
  static const pedidosPreDespachoDeLoFiltrado =
      'pedidos-pre-despacho-de-lo-filtrado';

  // ------------------------------------------------------------------- RUTAS
  static const rutasNuevaRuta = 'rutas-nueva-ruta';
  static const rutasAsistenteSucursal = 'rutas-asistente-sucursal';
  static const rutasAsistenteAlmacen = 'rutas-asistente-almacen';
  static const rutasAsistenteVehiculo = 'rutas-asistente-vehiculo';
  static const rutasAsistenteSiguiente = 'rutas-asistente-siguiente';
  static const rutasAsistenteBuscar = 'rutas-asistente-buscar';
  static const rutasAsistenteGenerar = 'rutas-asistente-generar';
  static const rutasPreDespacho = 'rutas-pre-despacho';

  static const rutasTarjetaDeRuta = 'rutas-tarjeta-de-ruta';
  static const rutasVerParadas = 'rutas-ver-paradas';
  static const rutasIniciar = 'rutas-iniciar';
  static const rutasCierre = 'rutas-cierre';
  static const rutasCompletar = 'rutas-completar';
  static const rutasEliminar = 'rutas-eliminar';
  static const rutasGuardarElCierre = 'rutas-guardar-el-cierre';
  static const rutasPostDespacho = 'rutas-post-despacho';
  static const rutasResultadoDeLaParada = 'rutas-resultado-de-la-parada';

  static const rutasAbrirEnGoogleMaps = 'rutas-abrir-en-google-maps';
  static const rutasWhatsApp = 'rutas-whatsapp';
  static const rutasCompartir = 'rutas-compartir';
  static const rutasCopiar = 'rutas-copiar';

  // --------------------------------------------------------------- VEHICULOS
  static const vehiculosAgregar = 'vehiculos-agregar';
  static const vehiculosTipos = 'vehiculos-tipos';
  static const vehiculosNombre = 'vehiculos-nombre';
  static const vehiculosTipo = 'vehiculos-tipo';
  static const vehiculosPlaca = 'vehiculos-placa';
  static const vehiculosCapacidad = 'vehiculos-capacidad';
  static const vehiculosEstado = 'vehiculos-estado';
  static const vehiculosCostoPorKm = 'vehiculos-costo-por-km';
  static const vehiculosCalculaElDomicilio = 'vehiculos-calcula-el-domicilio';
  static const vehiculosNotas = 'vehiculos-notas';
  static const vehiculosGuardar = 'vehiculos-guardar';
  static const vehiculosEditar = 'vehiculos-editar';
  static const vehiculosEliminar = 'vehiculos-eliminar';
  static const vehiculosMarcarDisponible = 'vehiculos-marcar-disponible';
  static const vehiculosUsarParaDomicilio = 'vehiculos-usar-para-domicilio';
  static const vehiculosTipoNombre = 'vehiculos-tipo-nombre';
  static const vehiculosTipoCosto = 'vehiculos-tipo-costo';
  static const vehiculosAnadirTipo = 'vehiculos-anadir-tipo';
  static const vehiculosGuardarTipos = 'vehiculos-guardar-tipos';

  // --------------------------------------------------------------- ALMACENES
  static const almacenesSucursal = 'almacenes-sucursal';
  static const almacenesNuevo = 'almacenes-nuevo';
  static const almacenesAbrir = 'almacenes-abrir';
  static const almacenesNombre = 'almacenes-nombre';
  static const almacenesPrincipal = 'almacenes-principal';
  static const almacenesActivo = 'almacenes-activo';
  static const almacenesQuitar = 'almacenes-quitar';
  static const almacenesDireccion = 'almacenes-direccion';
  static const almacenesBuscarLaDireccion = 'almacenes-buscar-la-direccion';
  static const almacenesCoordenadas = 'almacenes-coordenadas';
  static const almacenesMapa = 'almacenes-mapa';
  static const almacenesGuardar = 'almacenes-guardar';

  // ------------------------------------------------------- DE TODA LA CASA
  /// El «Sí, borrar «X»» de la pregunta de antes de borrar
  /// (`diseno/preguntar_antes_de_borrar.dart`). Uno para las cinco tareas que
  /// acaban ahi: la ruta, el camion, el almacen y la zona.
  static const confirmarElBorrado = 'confirmar-el-borrado';

  // ------------------------------------------------------- LA BARRA DE ARRIBA
  /// La pastilla de la sucursal. Es la MISMA marca en sus dos formas —el
  /// selector de quien ve varias y la pastilla fija de quien tiene una sola—,
  /// porque el manual habla de «la pastilla con la sucursal» y no de cual de las
  /// dos le toco. Las dos formas son excluyentes, asi que nunca hay dos a la vez.
  static const barraSucursal = 'barra-sucursal';

  /// La PRIMERA opcion de la lista de sucursales, la de «Todas (8)». Solo existe
  /// mientras el cajon del selector esta abierto.
  static const barraElegirSucursal = 'barra-elegir-sucursal';

  /// La pastilla de la moneda, en sus dos formas: el selector cuando hay tasa y
  /// la pastilla ambar de «aqui no se puede ver en CUP» cuando no la hay. El paso
  /// 3 de «Cómo compruebas que ya está» habla justo de la segunda.
  static const barraMoneda = 'barra-moneda';

  /// La opcion de CUP, dentro del cajon de la moneda.
  static const barraElegirMoneda = 'barra-elegir-moneda';

  /// El avatar de la derecha, que abre el menu de la cuenta.
  static const cuentaAvatar = 'cuenta-avatar';

  /// La primera baldosa de «Ir a». Hay una por aplicacion, asi que se marca la
  /// primera.
  static const cuentaIrALaAplicacion = 'cuenta-ir-a-la-aplicacion';

  // -------------------------------------------------------- LA FRANJA DE ABAJO
  /// La franja entera, que es pulsable y lleva a traer el dia.
  ///
  /// **En la web no se monta** (`navegacion/armazon.dart`, `if (hayDiaQueTraer)`):
  /// alli no hay copia que traer. Los pasos que la nombran salen de paginas de
  /// `comun/`, asi que en un navegador el recorrido dice que el control no esta en
  /// esta pantalla — que es la verdad, no un fallo.
  static const franjaDeEstado = 'franja-de-estado';

  /// El boton de la nube con la flecha hacia abajo.
  static const franjaTraerElDia = 'franja-traer-el-dia';

  /// El boton de la nube con la flecha hacia arriba, el que lleva la insignia de
  /// «`<n>` sin subir».
  static const franjaEntregarElDia = 'franja-entregar-el-dia';

  /// El boton de la franja AMBAR de version nueva.
  ///
  /// Es el sitio, no la palabra: ese boton dice «Como instalarla», «Instalar»,
  /// «Dar el permiso» o «Seguir descargando» segun por donde vaya la
  /// actualizacion. Un nombre de control que fuera el texto del boton se
  /// quedaria apuntando a nada en cuatro de los cinco estados.
  static const franjaVersionNueva = 'franja-version-nueva';

  /// El «Descargar e instalar» del cajon de la version nueva.
  ///
  /// Desde el 05/10/2026 la APK se baja y se instala DENTRO. El manual decia
  /// «se abre el navegador», que es lo que se arreglo ese dia: cuando se marco
  /// este control hubo que reescribir los pasos, porque senalar un boton que
  /// hace otra cosa que la que cuenta el renglon es peor que no senalarlo.
  static const cajonDescargarEInstalar = 'cajon-descargar-e-instalar';

  /// El «Descargar» del cajon del ESCRITORIO.
  ///
  /// Dos nombres y no uno porque son dos botones distintos: en la APK baja e
  /// instala dentro; en el escritorio abre el navegador. Un solo nombre para los
  /// dos dejaria al recorrido del escritorio senalando un boton que no existe
  /// alli, o peor, al de la APK contando lo que hace el otro.
  static const cajonDescargarAlNavegador = 'cajon-descargar-al-navegador';

  /// El boton del pie del cajon de traer el dia.
  static const traerElDiaTraer = 'traer-el-dia-traer';

  /// El boton del pie del cajon de entregar el dia.
  static const entregarElDiaEntregar = 'entregar-el-dia-entregar';

  /// El titulo de la bandeja de rechazos, dentro de ese cajon.
  static const entregarElDiaBandeja = 'entregar-el-dia-bandeja';

  /// La primera tarjeta de rechazo, con su motivo literal.
  static const entregarElDiaRechazo = 'entregar-el-dia-rechazo';

  /// El «Reintentar» de esa tarjeta. Vive en `FilaDeRechazo`, que es compartida,
  /// y por eso se marca solo cuando la pantalla lo pide
  /// (`FilaDeRechazo.senalarLosGestos`): en Sincronizacion se ven los rechazos de
  /// los diez aparatos y ahi no se decide nada.
  static const rechazoReintentar = 'rechazo-reintentar';

  // ---------------------------------------------------------------- EL MENU
  /// LAS ENTRADAS DEL MENU que el manual nombra con «Menú → «X»».
  ///
  /// Se marcan en `navegacion/barra_lateral.dart`. En escritorio y en la web
  /// ancha la barra esta fija y el foco cae donde dice el paso; en un telefono
  /// vive dentro del cajon del `Scaffold`, asi que con el cajon cerrado el
  /// recorrido dice «el control de este paso no está en esta pantalla», que es
  /// exactamente lo que pasa. Nunca hay dos a la vez: el armazon pone `drawer:
  /// null` en escritorio.
  static const menuClientes = 'menu-clientes';
  static const menuReportes = 'menu-reportes';
  static const menuSincronizacion = 'menu-sincronizacion';
  static const menuMapa = 'menu-mapa';

  // ---------------------------------------------------------------- CLIENTES
  static const clientesBuscar = 'clientes-buscar';

  /// El primer cliente de la lista, en sus dos formas: la fila de la tabla ancha
  /// y la tarjeta del telefono. Son excluyentes (`TablaClientes.anchoMinimo`).
  static const clientesAbrirElCliente = 'clientes-abrir-el-cliente';

  // ---------------------------------------------------------------- REPORTES
  /// El renglon de encima de las pestanas que dice con que estan cuadrados los
  /// numeros, y el aviso ambar de que tienen mas de un dia.
  static const informesAdvertencia = 'informes-advertencia';
  static const informesDesde = 'informes-desde';
  static const informesPestanas = 'informes-pestanas';

  /// «Exportar a Excel». Es tambien el control del paso siguiente: «Armando el
  /// Excel...» es lo que dice ESE boton mientras trabaja, no otro sitio.
  static const informesExportar = 'informes-exportar';

  // ----------------------------------------------------------- SINCRONIZACION
  static const sincronizacionCifras = 'sincronizacion-cifras';
  static const sincronizacionAparatos = 'sincronizacion-aparatos';
  static const sincronizacionBandeja = 'sincronizacion-bandeja';

  // -------------------------------------------------------------------- MAPA
  /// El primer boton de bajar un nivel del mapa. Hay uno por nivel ofrecido.
  static const mapaBajar = 'mapa-bajar';

  // -------------------------------------------------------- CANAL CON PEDIDO
  static const canalRespira = 'canal-respira';
  static const canalSaliendo = 'canal-saliendo';
  static const canalEntrando = 'canal-entrando';
  static const canalSinTerminar = 'canal-sin-terminar';

  // -------------------------------------------------------------------- GUIA
  /// El propio boton de «Guiarme paso a paso», para el recorrido que ensena a
  /// usar la Guia.
  static const guiaGuiarme = 'guia-guiarme';

  /// La primera fila de la lista de tareas.
  static const guiaPrimeraTarea = 'guia-primera-tarea';

  /// La puerta del Documento, para «y si lo que quieres es leer…».
  static const guiaDocumento = 'guia-documento';

  /// TODOS, para las dos pruebas de contrato.
  ///
  /// Escrito a mano debajo de las constantes porque Dart no sabe enumerar los
  /// miembros de una clase. Que no se quede ninguna fuera lo comprueba
  /// `los_pasos_senalan_controles_que_existen_test.dart`, que cuenta los
  /// `static const` de este fichero y los compara con el tamano de este conjunto:
  /// sin eso, una constante nueva sin su linea aqui deja el manual sin poder
  /// nombrarla y nadie se entera.
  static const todos = <String>{
    panelPasoAPaso,
    panelArreglarElPaso,
    tableroNuevaZona,
    tableroNombreDeLaZona,
    tableroGuardarLaZona,
    tableroMenuDeLaZona,
    tableroCamionPrevisto,
    tableroElegirCamion,
    tableroRenombrar,
    tableroVaciar,
    tableroBorrarLaZona,
    tableroArmarLaRuta,
    tableroSinColocarBuscar,
    tableroSinColocarFiltros,
    tableroTarjetaDePedido,
    tableroColocarEnLaZona,
    tableroSubirUnaPosicion,
    tableroDevolverASinColocar,
    tableroCarruselDeZonas,
    tableroZonaDondeSoltar,
    tableroSegundaZonaDondeSoltar,
    tableroCabeceraDeLaZona,
    pedidosBuscar,
    pedidosFiltroEstado,
    pedidosFiltroMunicipio,
    pedidosOrden,
    pedidosLimpiarFiltros,
    pedidosAbrirElPedido,
    pedidosMarcarTodos,
    pedidosMarcarUno,
    pedidosMandarAUnaZona,
    pedidosZonaDestino,
    pedidosMandar,
    pedidosPreDespachoDeLoFiltrado,
    rutasNuevaRuta,
    rutasAsistenteSucursal,
    rutasAsistenteAlmacen,
    rutasAsistenteVehiculo,
    rutasAsistenteSiguiente,
    rutasAsistenteBuscar,
    rutasAsistenteGenerar,
    rutasPreDespacho,
    rutasTarjetaDeRuta,
    rutasVerParadas,
    rutasIniciar,
    rutasCierre,
    rutasCompletar,
    rutasEliminar,
    rutasGuardarElCierre,
    rutasPostDespacho,
    rutasResultadoDeLaParada,
    rutasAbrirEnGoogleMaps,
    rutasWhatsApp,
    rutasCompartir,
    rutasCopiar,
    vehiculosAgregar,
    vehiculosTipos,
    vehiculosNombre,
    vehiculosTipo,
    vehiculosPlaca,
    vehiculosCapacidad,
    vehiculosEstado,
    vehiculosCostoPorKm,
    vehiculosCalculaElDomicilio,
    vehiculosNotas,
    vehiculosGuardar,
    vehiculosEditar,
    vehiculosEliminar,
    vehiculosMarcarDisponible,
    vehiculosUsarParaDomicilio,
    vehiculosTipoNombre,
    vehiculosTipoCosto,
    vehiculosAnadirTipo,
    vehiculosGuardarTipos,
    almacenesSucursal,
    almacenesNuevo,
    almacenesAbrir,
    almacenesNombre,
    almacenesPrincipal,
    almacenesActivo,
    almacenesQuitar,
    almacenesDireccion,
    almacenesBuscarLaDireccion,
    almacenesCoordenadas,
    almacenesMapa,
    almacenesGuardar,
    confirmarElBorrado,
    barraSucursal,
    barraElegirSucursal,
    barraMoneda,
    barraElegirMoneda,
    cuentaAvatar,
    cuentaIrALaAplicacion,
    franjaDeEstado,
    franjaTraerElDia,
    franjaEntregarElDia,
    franjaVersionNueva,
    cajonDescargarEInstalar,
    cajonDescargarAlNavegador,
    traerElDiaTraer,
    entregarElDiaEntregar,
    entregarElDiaBandeja,
    entregarElDiaRechazo,
    rechazoReintentar,
    menuClientes,
    menuReportes,
    menuSincronizacion,
    menuMapa,
    clientesBuscar,
    clientesAbrirElCliente,
    informesAdvertencia,
    informesDesde,
    informesPestanas,
    informesExportar,
    sincronizacionCifras,
    sincronizacionAparatos,
    sincronizacionBandeja,
    mapaBajar,
    canalRespira,
    canalSaliendo,
    canalEntrando,
    canalSinTerminar,
    guiaGuiarme,
    guiaPrimeraTarea,
    guiaDocumento,
  };
}
