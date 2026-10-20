// ALMACENES ES DE SOLO LECTURA (Jose, 20/10/2026): la matriz esta en el CRM.
//
// Tres cosas que no se pueden perder y que NINGUNA otra prueba fija:
//
//  a. **No hay ningun control de escritura.** Ni crear, ni editar, ni eliminar,
//     ni marcar principal, ni activar/desactivar. LISTA BLANCA, no negra: se
//     cuenta TODO lo que reacciona a un toque (`InkWell`, `GestureDetector`,
//     botones, chips, interruptores, `ListTile` con `onTap`...) y solo se deja
//     pasar el selector de sucursal y el enlace «Abrir el CRM». Un widget
//     tocable de una forma que nadie imaginaba tambien la pone en rojo (la
//     auditoria del 20/10/2026 colo un `ActionChip` y un `InkWell`). Ademas, por
//     tipo (Switch, Checkbox, TextField...) ni uno, ni apagado; por icono y texto.
//  b. **El aviso del CRM sale siempre**; con enlace si `CRM_URL` tiene valor (por
//     defecto la del CRM de produccion) y SIN enlace si se vacia explicitamente.
//  c. **Se repinta sola** cuando llega `CambioEnVivo.almacenes`, con la pantalla
//     ya abierta y la lista vacia al principio (el molde de
//     `pedidos/llega_la_bajada_test.dart`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/selector.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/entorno.dart';
import 'package:reparto/nucleo/refresco_en_vivo.dart';
import 'package:reparto/pantallas/almacenes/estado/estado_almacenes.dart';
import 'package:reparto/pantallas/almacenes/vista/pantalla_almacenes.dart';
import 'package:reparto/pantallas/rutas/datos/abrir_y_compartir.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo_almacenes.dart';

class _Aparato implements AbrirYCompartir {
  final abiertos = <Uri>[];

  @override
  Future<bool> abrir(Uri destino) async {
    abiertos.add(destino);
    return true;
  }

  @override
  Future<bool> compartir({required String texto, String? asunto}) async => true;

  @override
  Future<bool> copiar(String texto) async => true;
}

Map<String, Object?> _dosSucursales() => {
  'sucursales': [
    {
      'codigo': 'STG',
      'nombre': 'Santiago',
      'almacenes': [
        {
          'id': 'w1',
          'nombre': 'Central',
          'codigo': 'C1',
          'direccion': 'Calle 1',
          'principal': true,
          'latitud': 20.0,
          'longitud': -75.8,
        },
        {'id': 'w2', 'nombre': 'Patio sur', 'activo': false},
      ],
    },
    {'codigo': 'HAB', 'nombre': 'La Habana', 'almacenes': <Object?>[]},
  ],
};

/// Todo lo que reacciona a un toque, mire por donde mire: widgets de gesto,
/// botones, chips, interruptores, filas con `onTap`. Solo cuenta el que de
/// verdad tiene manejador (un `InkWell` con `onTap: null` es el de dentro de un
/// `ListTile` y no se toca).
bool _reaccionaAlToque(Widget w) => switch (w) {
  InkWell(
    :final onTap,
    :final onLongPress,
    :final onDoubleTap,
    :final onSecondaryTap,
    :final onTapDown,
  ) =>
    onTap != null ||
        onLongPress != null ||
        onDoubleTap != null ||
        onSecondaryTap != null ||
        onTapDown != null,
  InkResponse(
    :final onTap,
    :final onLongPress,
    :final onDoubleTap,
    :final onSecondaryTap,
    :final onTapDown,
  ) =>
    onTap != null ||
        onLongPress != null ||
        onDoubleTap != null ||
        onSecondaryTap != null ||
        onTapDown != null,
  GestureDetector(
    :final onTap,
    :final onTapDown,
    :final onTapUp,
    :final onLongPress,
    :final onDoubleTap,
    :final onSecondaryTap,
    :final onPanUpdate,
    :final onHorizontalDragUpdate,
    :final onVerticalDragUpdate,
  ) =>
    onTap != null ||
        onTapDown != null ||
        onTapUp != null ||
        onLongPress != null ||
        onDoubleTap != null ||
        onSecondaryTap != null ||
        onPanUpdate != null ||
        onHorizontalDragUpdate != null ||
        onVerticalDragUpdate != null,
  ButtonStyleButton(:final onPressed, :final onLongPress) =>
    onPressed != null || onLongPress != null,
  IconButton(:final onPressed) => onPressed != null,
  ActionChip(:final onPressed) => onPressed != null,
  ChoiceChip(:final onSelected) => onSelected != null,
  FilterChip(:final onSelected) => onSelected != null,
  InputChip(:final onPressed, :final onSelected, :final onDeleted) =>
    onPressed != null || onSelected != null || onDeleted != null,
  Checkbox(:final onChanged) => onChanged != null,
  Switch(:final onChanged) => onChanged != null,
  ListTile(:final onTap, :final onLongPress) =>
    onTap != null || onLongPress != null,
  _ => false,
};

List<Element> _tocables(WidgetTester tester) => find
    .byWidgetPredicate(_reaccionaAlToque)
    .evaluate()
    .toList();

/// Lo unico permitido: lo que cuelga del selector de sucursal (armazon) o del
/// enlace «Abrir el CRM» (el unico `TextButton` de la pantalla).
bool _esDelSelectorODelEnlace(Element e) {
  var permitido = e.widget is TextButton || e.widget is Selector<String>;
  e.visitAncestorElements((a) {
    if (a.widget is TextButton || a.widget is Selector<String>) {
      permitido = true;
      return false;
    }
    return true;
  });
  return permitido;
}

void main() {
  late StreamController<String> enVivo;
  setUp(() => enVivo = StreamController<String>.broadcast());
  tearDown(() => enVivo.close());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pintar(
    WidgetTester tester,
    Banco banco, {
    String? crmUrl,
    _Aparato? aparato,
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(banco.base),
          clienteApiProvider.overrideWithValue(
            banco.contenedor.read(clienteApiProvider),
          ),
          avisosDelServidorProvider.overrideWithValue(enVivo.stream),
          if (crmUrl != null) crmUrlProvider.overrideWithValue(crmUrl),
          if (aparato != null)
            abrirYCompartirProvider.overrideWithValue(aparato),
        ],
        child: const MaterialApp(home: Scaffold(body: PantallaAlmacenes())),
      ),
    );
    await asentar(tester);
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('a. NO hay ningun control de escritura, y las filas no se tocan', (
    tester,
  ) async {
    final banco = Banco((_) async => RespuestaFalsa(200, _dosSucursales()));
    addTearDown(banco.cerrar);
    await pintar(tester, banco, crmUrl: 'https://crm.prueba');

    // Se ve lo que hay (si no, lo de abajo pasaria en una pantalla vacia).
    expect(find.text('Central'), findsOneWidget);
    expect(
      find.textContaining('sin punto'),
      findsOneWidget,
      reason: 'Patio sur',
    );
    expect(find.textContaining('inactivo'), findsOneWidget);

    // Por TIPO: ni uno solo de estos, ni siquiera apagado (una pantalla de
    // solo lectura no tiene interruptores que "no hacen nada").
    for (final tipo in <Type>[
      FloatingActionButton,
      PopupMenuButton<Object?>,
      PopupMenuButton<String>,
      Switch,
      Checkbox,
      Radio<Object?>,
      Radio<String>,
      Dismissible,
      BotonPrincipal,
      BotonDestructivo,
      TextField,
      TextFormField,
    ]) {
      expect(find.byType(tipo), findsNothing, reason: '$tipo es de escritura');
    }

    // LISTA BLANCA (20/10/2026): la auditoria metio un `ActionChip` y un
    // `InkWell(onTap)` en la fila y la lista negra de arriba seguia en verde. Aqui
    // se cuenta TODO lo tocable de la pantalla y solo se deja pasar lo del
    // armazon: lo de dentro del selector de sucursal y el enlace «Abrir el CRM».
    final sobran = _tocables(tester)
        .where((e) => !_esDelSelectorODelEnlace(e))
        .map((e) => '${e.widget.runtimeType}')
        .toList();
    expect(
      sobran,
      isEmpty,
      reason: 'solo el selector de sucursal y el enlace al CRM se tocan',
    );
    // Y lo permitido existe de verdad (si no, la lista blanca estaria vacia
    // por haberse roto el predicado y no por que la pantalla este limpia).
    expect(_tocables(tester).where(_esDelSelectorODelEnlace), isNotEmpty);

    // Por ICONO.
    for (final icono in <IconData>[
      Icons.add,
      Icons.add_circle_outline,
      Icons.edit,
      Icons.edit_outlined,
      Icons.delete,
      Icons.delete_outline,
      Icons.save,
      Icons.save_outlined,
      Icons.star_border,
      Icons.chevron_right,
    ]) {
      expect(find.byIcon(icono), findsNothing, reason: 'icono de escritura');
    }

    // Por TEXTO (el «principal» de una fila es un dato, no un boton: por eso se
    // busca la ACCION, no la palabra).
    expect(
      find.textContaining(
        RegExp(
          r'Nuevo|Añadir|Agregar|Crear|Editar|Eliminar|Quitar|Borrar|Guardar|'
          r'Activar|Desactivar|(Marcar|Hacer|Poner) (como )?principal',
          caseSensitive: false,
        ),
      ),
      findsNothing,
    );

    // Las filas son solo para mirar.
    for (final fila in tester.widgetList<ListTile>(find.byType(ListTile))) {
      expect(fila.onTap, isNull);
      expect(fila.onLongPress, isNull);
      expect(fila.trailing, isNull);
    }

    // Lo unico pulsable: el selector de sucursal y el enlace al CRM.
    expect(
      find.descendant(
        of: find.byType(Selector<String>),
        matching: find.byType(OutlinedButton),
      ),
      findsOneWidget,
    );
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);

    // Y por la red: lo unico que sale es leer.
    expect(
      banco.servidor.vistas.where((p) => p.metodo != 'GET'),
      isEmpty,
      reason: 'Reparto ya no escribe almacenes',
    );

    await desmontar(tester);
  });

  testWidgets('b. el aviso del CRM sale SIN enlace si CRM_URL esta vacia', (
    tester,
  ) async {
    final banco = Banco((_) async => RespuestaFalsa(200, _dosSucursales()));
    addTearDown(banco.cerrar);
    await pintar(tester, banco, crmUrl: '');

    expect(
      find.text('Los almacenes se editan en el CRM. Aquí solo se consultan.'),
      findsOneWidget,
    );
    expect(find.byType(TextButton), findsNothing);
    expect(find.text('Abrir el CRM'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('b. por defecto (sin --dart-define) el enlace es el del CRM', (
    tester,
  ) async {
    final banco = Banco((_) async => RespuestaFalsa(200, _dosSucursales()));
    addTearDown(banco.cerrar);
    await pintar(tester, banco);

    // El APK y el instalador de Windows se compilan sin --dart-define: si el defecto se
    // vacia, la pantalla vuelve a salir sin enlace y nada lo avisa.
    expect(
      Entorno.crmUrl,
      'https://crm.procovar.cloud/catalogos/almacenes',
      reason: 'la direccion que dio Jose el 20/10/2026',
    );
    expect(find.textContaining('se editan en el CRM'), findsOneWidget);
    expect(find.text('Abrir el CRM'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('b. con CRM_URL el aviso lleva su enlace y abre ESA direccion', (
    tester,
  ) async {
    final banco = Banco((_) async => RespuestaFalsa(200, _dosSucursales()));
    addTearDown(banco.cerrar);
    final aparato = _Aparato();
    await pintar(
      tester,
      banco,
      crmUrl: 'https://crm.prueba/almacenes',
      aparato: aparato,
    );

    expect(find.textContaining('se editan en el CRM'), findsOneWidget);
    expect(find.text('Abrir el CRM'), findsOneWidget);

    await tester.tap(find.text('Abrir el CRM'));
    await asentar(tester);
    expect(aparato.abiertos, [Uri.parse('https://crm.prueba/almacenes')]);

    await desmontar(tester);
  });

  testWidgets('b. el aviso sale tambien con la lista vacia', (tester) async {
    final banco = Banco(
      (_) async => RespuestaFalsa(200, const <String, Object?>{
        'sucursales': <Object?>[],
      }),
    );
    addTearDown(banco.cerrar);
    await pintar(tester, banco);
    expect(find.textContaining('se editan en el CRM'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('b. el aviso sale tambien cuando la carga falla', (tester) async {
    final banco = Banco.sinRed();
    addTearDown(banco.cerrar);
    await pintar(tester, banco);
    expect(find.textContaining('se editan en el CRM'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('c. llega CambioEnVivo.almacenes con la pantalla abierta y el '
      'cambio sale sin volver a montar', (tester) async {
    // 1. Como abre la pantalla: la sucursal todavia sin ninguno.
    var respuesta = <String, Object?>{
      'sucursales': [
        {'codigo': 'STG', 'nombre': 'Santiago', 'almacenes': <Object?>[]},
      ],
    };
    final banco = Banco((_) async => RespuestaFalsa(200, respuesta));
    addTearDown(banco.cerrar);
    await pintar(tester, banco);

    expect(find.text('Sin almacenes en Santiago'), findsOneWidget);
    expect(find.text('Almacén del CRM'), findsNothing);
    final antes = banco.servidor.cuantas('GET', '/almacenes');

    // 2. El CRM da de alta un almacen y avisa. Nadie recarga ni vuelve a montar.
    respuesta = {
      'sucursales': [
        {
          'codigo': 'STG',
          'nombre': 'Santiago',
          'almacenes': [
            {
              'id': 'w9',
              'nombre': 'Almacén del CRM',
              'latitud': 20.0,
              'longitud': -75.8,
            },
          ],
        },
      ],
    };
    enVivo.add(CambioEnVivo.almacenes);
    await asentar(tester);

    // 3. La pantalla se entera.
    expect(banco.servidor.cuantas('GET', '/almacenes'), greaterThan(antes));
    expect(find.text('Almacén del CRM'), findsOneWidget);
    expect(find.text('Sin almacenes en Santiago'), findsNothing);

    await desmontar(tester);
  });
}
