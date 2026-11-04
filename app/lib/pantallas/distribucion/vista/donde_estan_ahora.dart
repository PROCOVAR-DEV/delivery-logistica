// «DÓNDE ESTÁN AHORA» (tarea 5): el último punto de cada distribuidor con una ruta en curso.
//
// `GET /api/tracking/ahora`. Para cada uno: el nombre, hace cuánto mandó su teléfono el último aviso, y un aviso en ÁMBAR si pasaron
// más de [minutosSinSenalParaAvisar] minutos (el teléfono sin señal, apagado, o sin batería). Se refresca solo cada 30 segundos y
// a mano con «Actualizar». El mapa es el croquis de siempre con un punto numerado por distribuidor.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/colores.dart';
import '../../../nucleo/proveedores.dart';
import '../../pedidos/vista/kit.dart' show EstadoVacio;
import '../../rutas/datos/geo.dart';
import '../../rutas/datos/mapa_en_vivo.dart';
import '../../rutas/datos/recorrido.dart';
import '../../rutas/vista/croquis_de_ruta.dart';
import '../datos/api_distribucion.dart';
import '../datos/modelos.dart';
import 'recorrido_real.dart' show cuantoDura, horaDe;

abstract final class TextosDeDondeEstan {
  static const nadie =
      'Ningún distribuidor tiene una ruta en curso con ubicación ahora. Aparecen aquí cuando inician su ruta y su teléfono manda el GPS.';
  static String sinSenal(int minutos) =>
      'Más de $minutos minutos sin noticias de su teléfono.';
  static String haceCuanto(Duration? d) => d == null
      ? 'Sin hora de su último aviso'
      : d.inMinutes < 1
      ? 'Último aviso hace menos de 1 minuto'
      : 'Último aviso hace ${cuantoDura(d)}';
}

const claveDeActualizarDonde = ValueKey('donde-actualizar');
const claveDeLaListaDeDonde = ValueKey('donde-lista');
Key claveDelDistribuidorAhora(String id) => ValueKey('donde-$id');
Key claveDelAvisoSinSenal(String id) => ValueKey('donde-sin-senal-$id');

class DondeEstanAhora extends ConsumerStatefulWidget {
  const DondeEstanAhora({this.cada = const Duration(seconds: 30), super.key});

  /// Cada cuánto se vuelve a pedir solo.
  final Duration cada;

  @override
  ConsumerState<DondeEstanAhora> createState() => _DondeEstanAhoraState();
}

class _DondeEstanAhoraState extends ConsumerState<DondeEstanAhora> {
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _reloj = Timer.periodic(
      widget.cada,
      (_) => ref.invalidate(dondeEstanAhoraProvider),
    );
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lista = ref.watch(dondeEstanAhoraProvider);
    // Mientras se vuelve a pedir se sigue enseñando lo que había: no parpadea a «Cargando».
    final datos = lista.value;
    final actualizar = Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        key: claveDeActualizarDonde,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Actualizar'),
        onPressed: () => ref.invalidate(dondeEstanAhoraProvider),
      ),
    );
    if (datos == null) {
      return lista.hasError
          ? EstadoVacio(
              'No se pudo saber dónde están: ${motivoDelFallo(lista.error!)}',
              accion: actualizar,
            )
          : const EstadoVacio('Buscando a los distribuidores…');
    }
    if (datos.isEmpty) {
      return EstadoVacio(TextosDeDondeEstan.nadie, accion: actualizar);
    }
    final ahora = ref.watch(relojProvider)();
    final tema = Theme.of(context);
    return ListView(
      key: claveDeLaListaDeDonde,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
      children: [
        actualizar,
        if (lista.hasError)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'No se pudo actualizar (${motivoDelFallo(lista.error!)}). Se ve lo último que se supo.',
              style: tema.textTheme.bodySmall?.copyWith(color: Colores.ambar),
            ),
          ),
        CroquisDeRuta(
          recorrido: Recorrido(
            soloTraza: true,
            paradas: [
              for (final (i, d) in datos.indexed)
                ParadaDelRecorrido(
                  id: d.distribuidorId,
                  numero: i + 1,
                  etiqueta: d.distribuidor ?? 'Distribuidor',
                  factura: TextosDeDondeEstan.haceCuanto(d.haceCuanto(ahora)),
                  punto: Punto(d.lat, d.lng),
                  // El color naranja del mapa = sin noticias hace rato.
                  esRegreso: d.sinSenal(ahora),
                  detalle: d.sinSenal(ahora)
                      ? TextosDeDondeEstan.sinSenal(minutosSinSenalParaAvisar)
                      : 'Con señal',
                ),
            ],
          ),
          fondo: ref.watch(fondoDeCallesProvider),
          porCalles: const SinCallesQueSeguir(),
        ),
        const SizedBox(height: 4),
        Text(
          'Punto azul: con señal. Punto naranja: sin noticias hace más de $minutosSinSenalParaAvisar minutos.',
          style: tema.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final (i, d) in datos.indexed)
          Card(
            key: claveDelDistribuidorAhora(d.distribuidorId),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}. ${d.distribuidor ?? 'Distribuidor'}',
                    style: tema.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      TextosDeDondeEstan.haceCuanto(d.haceCuanto(ahora)),
                      if (d.ultimaNoticia != null)
                        '(${horaDe(d.ultimaNoticia)})',
                      if (d.rutaIds.length > 1)
                        '${d.rutaIds.length} rutas a la vez',
                    ].join(' '),
                    style: tema.textTheme.bodySmall,
                  ),
                  if (d.sinSenal(ahora)) ...[
                    const SizedBox(height: 6),
                    DecoratedBox(
                      key: claveDelAvisoSinSenal(d.distribuidorId),
                      decoration: BoxDecoration(
                        color: Colores.ambarFondo,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Text(
                          TextosDeDondeEstan.sinSenal(
                            minutosSinSenalParaAvisar,
                          ),
                          style: TextStyle(fontSize: 12, color: Colores.tinta),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
