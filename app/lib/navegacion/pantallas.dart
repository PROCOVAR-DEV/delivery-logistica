import '../pantallas/acceso/registro.dart';
import '../pantallas/almacenes/registro.dart';
import '../pantallas/ayuda/registro.dart';
import '../pantallas/clientes/registro.dart';
import '../pantallas/vehiculos/registro.dart';
import '../pantallas/informes/registro.dart';
import '../pantallas/panel/registro.dart';
import '../pantallas/pedidos/registro.dart';
import '../pantallas/rutas/registro.dart';
import '../pantallas/mapa/registro.dart';
import '../pantallas/sincronizacion/registro.dart';
import '../pantallas/tablero/registro.dart';
import '../pantallas/webhook/registro.dart';
import 'pantalla_registrada.dart';

/// EL REGISTRO. Una linea por pantalla, en el orden en que salen en el menu.
///
/// Este es el unico fichero que un agente de pantalla toca fuera de su carpeta,
/// y toca **una sola linea**: sustituye su `_pendiente(...)` por la llamada a su
/// `registrarX()` y anade el import. El contrato entero esta explicado en
/// `pantalla_registrada.dart`.
///
/// Ya estan las siete mas el tablero: no queda ninguna por montar.
List<PantallaRegistrada> pantallasDeLaAplicacion() => <PantallaRegistrada>[
  // LA PUERTA. No sale en el menu y no lleva armazon: se llega a ella porque el
  // portero manda (`navegacion/portero.dart`) o porque se pulso «Salir». Va la
  // primera porque es por donde se empieza.
  registrarAcceso(),

  registrarPanel(),

  // DECISION A CONFIRMAR CON JOSE: el tablero es una pantalla NUEVA
  // (`docs/tablero.md`, 14/09/2026) y por eso no esta en las 6 entradas del
  // pliego §8.1, que describe la de Next. Se pone en el menu porque es la
  // pantalla del dia del logistico y sin entrada no se llega a ella; si se
  // decide lo contrario, es cambiar `enElMenu` a false.
  registrarTablero(),

  registrarRutas(),
  registrarPedidos(),
  registrarClientes(),
  registrarVehiculos(),
  registrarAlmacenes(),

  // Sincronizacion es otra pantalla NUEVA (`docs/sincronizacion.md` §3): el
  // panel de `GET /sync/estado`, que hasta ahora no consumia nadie. Va en el
  // menu porque sin entrada no se llega a ella, y lo que ensena ya viene
  // acotado por sucursal desde el servidor. El motivo largo esta en su
  // `registro.dart`.
  registrarSincronizacion(),

  // CÓMO VA EL CANAL CON PEDIDO. Fuera del menú, y **sólo en la web**.
  //
  // Devuelve `null` en la APK y en el escritorio, así que allí ni siquiera se
  // registra: el repartidor está en la calle y esto es una pantalla de tuberías
  // entre dos sistemas. Jose, 26/09/2026: «eso me lo dejas en la web solamente»
  // y «que sólo lo pueda ver yo, el desarrollador».
  //
  // El cerrojo que de verdad cierra es el 403 del servidor; esto es para que no
  // estorbe. El rol que lleva el aparato no decide permisos — lo dice `Sesion`.
  ?registrarWebhook(),

  // El mapa de Cuba para trabajar sin conexion. Va en el menu SOLO en la APK y
  // el escritorio —lo decide su propio `registro.dart`, regla 1— y sin entrada
  // no se llega a el. El porque entero, en `docs/mapa-sin-conexion.md`.
  registrarMapaSinConexion(),

  // LA GUIA: el manual del reparto, dentro de la aplicacion. En el menu en las
  // TRES formas —el de la oficina necesita la guia igual que el que se va al
  // patio de un almacen—, y lo que cambia es lo que ensena cada una. Jose,
  // 05/10/2026: «estas tareas me las agregas a el side bar para q puedan ir
  // cuando quieran». El porque entero, en su `registro.dart`.
  registrarGuia(),

  // Reportes SI va en el menu, y es un cambio deliberado respecto al patron: en
  // delivery no esta y se llega solo desde las acciones rapidas del Panel. Asi
  // copiado, Jose no la encontro. El porque entero, en su `registro.dart`.
  registrarInformes(),
];

// Ya NO hay `_pendiente(...)`: con Rutas y Pedidos montadas no queda ninguna
// pantalla sin escribir, y un hueco que no se usa es codigo muerto que hace
// pensar que todavia falta algo. Si hiciera falta otra vez, esta en el historial.
