// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'base.dart';

// ignore_for_file: type=lint
class $BranchesTable extends Branches with TableInfo<$BranchesTable, Sucursal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BranchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lngMeta = const VerificationMeta('lng');
  @override
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
    'lng',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _areaKm2Meta = const VerificationMeta(
    'areaKm2',
  );
  @override
  late final GeneratedColumn<double> areaKm2 = GeneratedColumn<double>(
    'area_km2',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _externalIdMeta = const VerificationMeta(
    'externalId',
  );
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
    'external_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originConfiguredMeta = const VerificationMeta(
    'originConfigured',
  );
  @override
  late final GeneratedColumn<bool> originConfigured = GeneratedColumn<bool>(
    'origin_configured',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("origin_configured" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _creadoPorMeta = const VerificationMeta(
    'creadoPor',
  );
  @override
  late final GeneratedColumn<String> creadoPor = GeneratedColumn<String>(
    'creado_por',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cupRateMeta = const VerificationMeta(
    'cupRate',
  );
  @override
  late final GeneratedColumn<double> cupRate = GeneratedColumn<double>(
    'cup_rate',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cupRateFuenteMeta = const VerificationMeta(
    'cupRateFuente',
  );
  @override
  late final GeneratedColumn<String> cupRateFuente = GeneratedColumn<String>(
    'cup_rate_fuente',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cupRateTraidoAtMeta = const VerificationMeta(
    'cupRateTraidoAt',
  );
  @override
  late final GeneratedColumn<DateTime> cupRateTraidoAt =
      GeneratedColumn<DateTime>(
        'cup_rate_traido_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _cupRateFrescaMeta = const VerificationMeta(
    'cupRateFresca',
  );
  @override
  late final GeneratedColumn<bool> cupRateFresca = GeneratedColumn<bool>(
    'cup_rate_fresca',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("cup_rate_fresca" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    address,
    lat,
    lng,
    areaKm2,
    externalId,
    originConfigured,
    creadoPor,
    createdAt,
    updatedAt,
    cupRate,
    cupRateFuente,
    cupRateTraidoAt,
    cupRateFresca,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'branches';
  @override
  VerificationContext validateIntegrity(
    Insertable<Sucursal> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lng')) {
      context.handle(
        _lngMeta,
        lng.isAcceptableOrUnknown(data['lng']!, _lngMeta),
      );
    } else if (isInserting) {
      context.missing(_lngMeta);
    }
    if (data.containsKey('area_km2')) {
      context.handle(
        _areaKm2Meta,
        areaKm2.isAcceptableOrUnknown(data['area_km2']!, _areaKm2Meta),
      );
    }
    if (data.containsKey('external_id')) {
      context.handle(
        _externalIdMeta,
        externalId.isAcceptableOrUnknown(data['external_id']!, _externalIdMeta),
      );
    }
    if (data.containsKey('origin_configured')) {
      context.handle(
        _originConfiguredMeta,
        originConfigured.isAcceptableOrUnknown(
          data['origin_configured']!,
          _originConfiguredMeta,
        ),
      );
    }
    if (data.containsKey('creado_por')) {
      context.handle(
        _creadoPorMeta,
        creadoPor.isAcceptableOrUnknown(data['creado_por']!, _creadoPorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('cup_rate')) {
      context.handle(
        _cupRateMeta,
        cupRate.isAcceptableOrUnknown(data['cup_rate']!, _cupRateMeta),
      );
    }
    if (data.containsKey('cup_rate_fuente')) {
      context.handle(
        _cupRateFuenteMeta,
        cupRateFuente.isAcceptableOrUnknown(
          data['cup_rate_fuente']!,
          _cupRateFuenteMeta,
        ),
      );
    }
    if (data.containsKey('cup_rate_traido_at')) {
      context.handle(
        _cupRateTraidoAtMeta,
        cupRateTraidoAt.isAcceptableOrUnknown(
          data['cup_rate_traido_at']!,
          _cupRateTraidoAtMeta,
        ),
      );
    }
    if (data.containsKey('cup_rate_fresca')) {
      context.handle(
        _cupRateFrescaMeta,
        cupRateFresca.isAcceptableOrUnknown(
          data['cup_rate_fresca']!,
          _cupRateFrescaMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Sucursal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Sucursal(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      ),
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lng'],
      )!,
      areaKm2: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}area_km2'],
      )!,
      externalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}external_id'],
      ),
      originConfigured: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}origin_configured'],
      )!,
      creadoPor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}creado_por'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
      cupRate: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cup_rate'],
      ),
      cupRateFuente: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cup_rate_fuente'],
      ),
      cupRateTraidoAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cup_rate_traido_at'],
      ),
      cupRateFresca: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}cup_rate_fresca'],
      ),
    );
  }

  @override
  $BranchesTable createAlias(String alias) {
    return $BranchesTable(attachedDatabase, alias);
  }
}

class Sucursal extends DataClass implements Insertable<Sucursal> {
  final String id;
  final String name;
  final String? address;
  final double lat;
  final double lng;
  final double areaKm2;
  final String? externalId;
  final bool originConfigured;
  final String? creadoPor;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// LA TASA DE CAMBIO DE ESTA SUCURSAL, y de ninguna otra.
  ///
  /// Vive aqui, en la sucursal, y no en `settings`. `settings` es GLOBAL —lo dice
  /// la propia API: «son de toda la empresa… la tasa POR SUCURSAL es otra cosa y
  /// vive en Accesos»— y una tasa sola para las ocho es exactamente como Granma
  /// acabo enseñando los 685 de La Habana como si fueran suyos. Un importe asi se
  /// lee bien y esta mal, que es lo peor que le puede pasar a un numero que
  /// alguien va a cobrar.
  ///
  /// **Baja con el dia** (`GET /api/sync/cambios`, coleccion `branches`) porque
  /// esta aplicacion tiene que pintar los importes sin conexion. La cadena entera
  /// es: Entrega pone la tasa → Accesos la guarda por sucursal → la tarea de
  /// fondo de la API la escribe en `branches` → aqui.
  ///
  /// **Los cuatro nacen nulos y no hay ningun 320 por defecto**, al reves que el
  /// `settings.cupRate` viejo. Es la mitad del arreglo: con un valor por defecto,
  /// ver un numero no demuestra que nadie haya puesto la tasa.
  /// Cuantos CUP son 1 USD aqui. `null` = esta sucursal no tiene tasa, que es un
  /// estado normal: hoy, seis de las ocho estan asi.
  final double? cupRate;

  /// De donde salio (`entrega`, `manual`…), tal como lo da Accesos.
  final String? cupRateFuente;

  /// Cuando se puso esa tasa en Entrega — el `traidoAt` de Accesos.
  ///
  /// **LA MARCA DE CUANDO, NO EL NUMERO.** Es lo unico que demuestra que la tasa
  /// existe de verdad, y por eso quien la lee la exige. Se llama `traidoAt` y no
  /// `updatedAt` para que no se confunda con el [updatedAt] de la fila, que es
  /// otra cosa: cuando cambio la sucursal.
  final DateTime? cupRateTraidoAt;

  /// Si ACCESOS la da por fresca (alli son 24 h).
  ///
  /// No se calcula aqui, y eso es deliberado: quien sabe cuando una tasa esta
  /// pasada es quien la mantiene. El aparato copia el booleano y avisa; una
  /// segunda regla de frescura se separaria de la primera el dia que una de las
  /// dos cambie.
  final bool? cupRateFresca;
  const Sucursal({
    required this.id,
    required this.name,
    this.address,
    required this.lat,
    required this.lng,
    required this.areaKm2,
    this.externalId,
    required this.originConfigured,
    this.creadoPor,
    this.createdAt,
    this.updatedAt,
    this.cupRate,
    this.cupRateFuente,
    this.cupRateTraidoAt,
    this.cupRateFresca,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    map['lat'] = Variable<double>(lat);
    map['lng'] = Variable<double>(lng);
    map['area_km2'] = Variable<double>(areaKm2);
    if (!nullToAbsent || externalId != null) {
      map['external_id'] = Variable<String>(externalId);
    }
    map['origin_configured'] = Variable<bool>(originConfigured);
    if (!nullToAbsent || creadoPor != null) {
      map['creado_por'] = Variable<String>(creadoPor);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    if (!nullToAbsent || cupRate != null) {
      map['cup_rate'] = Variable<double>(cupRate);
    }
    if (!nullToAbsent || cupRateFuente != null) {
      map['cup_rate_fuente'] = Variable<String>(cupRateFuente);
    }
    if (!nullToAbsent || cupRateTraidoAt != null) {
      map['cup_rate_traido_at'] = Variable<DateTime>(cupRateTraidoAt);
    }
    if (!nullToAbsent || cupRateFresca != null) {
      map['cup_rate_fresca'] = Variable<bool>(cupRateFresca);
    }
    return map;
  }

  BranchesCompanion toCompanion(bool nullToAbsent) {
    return BranchesCompanion(
      id: Value(id),
      name: Value(name),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      lat: Value(lat),
      lng: Value(lng),
      areaKm2: Value(areaKm2),
      externalId: externalId == null && nullToAbsent
          ? const Value.absent()
          : Value(externalId),
      originConfigured: Value(originConfigured),
      creadoPor: creadoPor == null && nullToAbsent
          ? const Value.absent()
          : Value(creadoPor),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      cupRate: cupRate == null && nullToAbsent
          ? const Value.absent()
          : Value(cupRate),
      cupRateFuente: cupRateFuente == null && nullToAbsent
          ? const Value.absent()
          : Value(cupRateFuente),
      cupRateTraidoAt: cupRateTraidoAt == null && nullToAbsent
          ? const Value.absent()
          : Value(cupRateTraidoAt),
      cupRateFresca: cupRateFresca == null && nullToAbsent
          ? const Value.absent()
          : Value(cupRateFresca),
    );
  }

  factory Sucursal.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Sucursal(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      address: serializer.fromJson<String?>(json['address']),
      lat: serializer.fromJson<double>(json['lat']),
      lng: serializer.fromJson<double>(json['lng']),
      areaKm2: serializer.fromJson<double>(json['areaKm2']),
      externalId: serializer.fromJson<String?>(json['externalId']),
      originConfigured: serializer.fromJson<bool>(json['originConfigured']),
      creadoPor: serializer.fromJson<String?>(json['creadoPor']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
      cupRate: serializer.fromJson<double?>(json['cupRate']),
      cupRateFuente: serializer.fromJson<String?>(json['cupRateFuente']),
      cupRateTraidoAt: serializer.fromJson<DateTime?>(json['cupRateTraidoAt']),
      cupRateFresca: serializer.fromJson<bool?>(json['cupRateFresca']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'address': serializer.toJson<String?>(address),
      'lat': serializer.toJson<double>(lat),
      'lng': serializer.toJson<double>(lng),
      'areaKm2': serializer.toJson<double>(areaKm2),
      'externalId': serializer.toJson<String?>(externalId),
      'originConfigured': serializer.toJson<bool>(originConfigured),
      'creadoPor': serializer.toJson<String?>(creadoPor),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
      'cupRate': serializer.toJson<double?>(cupRate),
      'cupRateFuente': serializer.toJson<String?>(cupRateFuente),
      'cupRateTraidoAt': serializer.toJson<DateTime?>(cupRateTraidoAt),
      'cupRateFresca': serializer.toJson<bool?>(cupRateFresca),
    };
  }

  Sucursal copyWith({
    String? id,
    String? name,
    Value<String?> address = const Value.absent(),
    double? lat,
    double? lng,
    double? areaKm2,
    Value<String?> externalId = const Value.absent(),
    bool? originConfigured,
    Value<String?> creadoPor = const Value.absent(),
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
    Value<double?> cupRate = const Value.absent(),
    Value<String?> cupRateFuente = const Value.absent(),
    Value<DateTime?> cupRateTraidoAt = const Value.absent(),
    Value<bool?> cupRateFresca = const Value.absent(),
  }) => Sucursal(
    id: id ?? this.id,
    name: name ?? this.name,
    address: address.present ? address.value : this.address,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    areaKm2: areaKm2 ?? this.areaKm2,
    externalId: externalId.present ? externalId.value : this.externalId,
    originConfigured: originConfigured ?? this.originConfigured,
    creadoPor: creadoPor.present ? creadoPor.value : this.creadoPor,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    cupRate: cupRate.present ? cupRate.value : this.cupRate,
    cupRateFuente: cupRateFuente.present
        ? cupRateFuente.value
        : this.cupRateFuente,
    cupRateTraidoAt: cupRateTraidoAt.present
        ? cupRateTraidoAt.value
        : this.cupRateTraidoAt,
    cupRateFresca: cupRateFresca.present
        ? cupRateFresca.value
        : this.cupRateFresca,
  );
  Sucursal copyWithCompanion(BranchesCompanion data) {
    return Sucursal(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      address: data.address.present ? data.address.value : this.address,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      areaKm2: data.areaKm2.present ? data.areaKm2.value : this.areaKm2,
      externalId: data.externalId.present
          ? data.externalId.value
          : this.externalId,
      originConfigured: data.originConfigured.present
          ? data.originConfigured.value
          : this.originConfigured,
      creadoPor: data.creadoPor.present ? data.creadoPor.value : this.creadoPor,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      cupRate: data.cupRate.present ? data.cupRate.value : this.cupRate,
      cupRateFuente: data.cupRateFuente.present
          ? data.cupRateFuente.value
          : this.cupRateFuente,
      cupRateTraidoAt: data.cupRateTraidoAt.present
          ? data.cupRateTraidoAt.value
          : this.cupRateTraidoAt,
      cupRateFresca: data.cupRateFresca.present
          ? data.cupRateFresca.value
          : this.cupRateFresca,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Sucursal(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('address: $address, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('areaKm2: $areaKm2, ')
          ..write('externalId: $externalId, ')
          ..write('originConfigured: $originConfigured, ')
          ..write('creadoPor: $creadoPor, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cupRate: $cupRate, ')
          ..write('cupRateFuente: $cupRateFuente, ')
          ..write('cupRateTraidoAt: $cupRateTraidoAt, ')
          ..write('cupRateFresca: $cupRateFresca')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    address,
    lat,
    lng,
    areaKm2,
    externalId,
    originConfigured,
    creadoPor,
    createdAt,
    updatedAt,
    cupRate,
    cupRateFuente,
    cupRateTraidoAt,
    cupRateFresca,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Sucursal &&
          other.id == this.id &&
          other.name == this.name &&
          other.address == this.address &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.areaKm2 == this.areaKm2 &&
          other.externalId == this.externalId &&
          other.originConfigured == this.originConfigured &&
          other.creadoPor == this.creadoPor &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.cupRate == this.cupRate &&
          other.cupRateFuente == this.cupRateFuente &&
          other.cupRateTraidoAt == this.cupRateTraidoAt &&
          other.cupRateFresca == this.cupRateFresca);
}

class BranchesCompanion extends UpdateCompanion<Sucursal> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> address;
  final Value<double> lat;
  final Value<double> lng;
  final Value<double> areaKm2;
  final Value<String?> externalId;
  final Value<bool> originConfigured;
  final Value<String?> creadoPor;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<double?> cupRate;
  final Value<String?> cupRateFuente;
  final Value<DateTime?> cupRateTraidoAt;
  final Value<bool?> cupRateFresca;
  final Value<int> rowid;
  const BranchesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.address = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.areaKm2 = const Value.absent(),
    this.externalId = const Value.absent(),
    this.originConfigured = const Value.absent(),
    this.creadoPor = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cupRate = const Value.absent(),
    this.cupRateFuente = const Value.absent(),
    this.cupRateTraidoAt = const Value.absent(),
    this.cupRateFresca = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BranchesCompanion.insert({
    required String id,
    required String name,
    this.address = const Value.absent(),
    required double lat,
    required double lng,
    this.areaKm2 = const Value.absent(),
    this.externalId = const Value.absent(),
    this.originConfigured = const Value.absent(),
    this.creadoPor = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.cupRate = const Value.absent(),
    this.cupRateFuente = const Value.absent(),
    this.cupRateTraidoAt = const Value.absent(),
    this.cupRateFresca = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       lat = Value(lat),
       lng = Value(lng);
  static Insertable<Sucursal> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? address,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<double>? areaKm2,
    Expression<String>? externalId,
    Expression<bool>? originConfigured,
    Expression<String>? creadoPor,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<double>? cupRate,
    Expression<String>? cupRateFuente,
    Expression<DateTime>? cupRateTraidoAt,
    Expression<bool>? cupRateFresca,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (address != null) 'address': address,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (areaKm2 != null) 'area_km2': areaKm2,
      if (externalId != null) 'external_id': externalId,
      if (originConfigured != null) 'origin_configured': originConfigured,
      if (creadoPor != null) 'creado_por': creadoPor,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (cupRate != null) 'cup_rate': cupRate,
      if (cupRateFuente != null) 'cup_rate_fuente': cupRateFuente,
      if (cupRateTraidoAt != null) 'cup_rate_traido_at': cupRateTraidoAt,
      if (cupRateFresca != null) 'cup_rate_fresca': cupRateFresca,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BranchesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? address,
    Value<double>? lat,
    Value<double>? lng,
    Value<double>? areaKm2,
    Value<String?>? externalId,
    Value<bool>? originConfigured,
    Value<String?>? creadoPor,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<double?>? cupRate,
    Value<String?>? cupRateFuente,
    Value<DateTime?>? cupRateTraidoAt,
    Value<bool?>? cupRateFresca,
    Value<int>? rowid,
  }) {
    return BranchesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      areaKm2: areaKm2 ?? this.areaKm2,
      externalId: externalId ?? this.externalId,
      originConfigured: originConfigured ?? this.originConfigured,
      creadoPor: creadoPor ?? this.creadoPor,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cupRate: cupRate ?? this.cupRate,
      cupRateFuente: cupRateFuente ?? this.cupRateFuente,
      cupRateTraidoAt: cupRateTraidoAt ?? this.cupRateTraidoAt,
      cupRateFresca: cupRateFresca ?? this.cupRateFresca,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (areaKm2.present) {
      map['area_km2'] = Variable<double>(areaKm2.value);
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (originConfigured.present) {
      map['origin_configured'] = Variable<bool>(originConfigured.value);
    }
    if (creadoPor.present) {
      map['creado_por'] = Variable<String>(creadoPor.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (cupRate.present) {
      map['cup_rate'] = Variable<double>(cupRate.value);
    }
    if (cupRateFuente.present) {
      map['cup_rate_fuente'] = Variable<String>(cupRateFuente.value);
    }
    if (cupRateTraidoAt.present) {
      map['cup_rate_traido_at'] = Variable<DateTime>(cupRateTraidoAt.value);
    }
    if (cupRateFresca.present) {
      map['cup_rate_fresca'] = Variable<bool>(cupRateFresca.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BranchesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('address: $address, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('areaKm2: $areaKm2, ')
          ..write('externalId: $externalId, ')
          ..write('originConfigured: $originConfigured, ')
          ..write('creadoPor: $creadoPor, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('cupRate: $cupRate, ')
          ..write('cupRateFuente: $cupRateFuente, ')
          ..write('cupRateTraidoAt: $cupRateTraidoAt, ')
          ..write('cupRateFresca: $cupRateFresca, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VehicleTypesTable extends VehicleTypes
    with TableInfo<$VehicleTypesTable, TipoVehiculo> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VehicleTypesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nombreMeta = const VerificationMeta('nombre');
  @override
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _costoKmUsdMeta = const VerificationMeta(
    'costoKmUsd',
  );
  @override
  late final GeneratedColumn<double> costoKmUsd = GeneratedColumn<double>(
    'costo_km_usd',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activoMeta = const VerificationMeta('activo');
  @override
  late final GeneratedColumn<bool> activo = GeneratedColumn<bool>(
    'activo',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("activo" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    nombre,
    costoKmUsd,
    activo,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vehicle_types';
  @override
  VerificationContext validateIntegrity(
    Insertable<TipoVehiculo> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('nombre')) {
      context.handle(
        _nombreMeta,
        nombre.isAcceptableOrUnknown(data['nombre']!, _nombreMeta),
      );
    } else if (isInserting) {
      context.missing(_nombreMeta);
    }
    if (data.containsKey('costo_km_usd')) {
      context.handle(
        _costoKmUsdMeta,
        costoKmUsd.isAcceptableOrUnknown(
          data['costo_km_usd']!,
          _costoKmUsdMeta,
        ),
      );
    }
    if (data.containsKey('activo')) {
      context.handle(
        _activoMeta,
        activo.isAcceptableOrUnknown(data['activo']!, _activoMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TipoVehiculo map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TipoVehiculo(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      nombre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nombre'],
      )!,
      costoKmUsd: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}costo_km_usd'],
      ),
      activo: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}activo'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $VehicleTypesTable createAlias(String alias) {
    return $VehicleTypesTable(attachedDatabase, alias);
  }
}

class TipoVehiculo extends DataClass implements Insertable<TipoVehiculo> {
  final String id;
  final String nombre;
  final double? costoKmUsd;
  final bool activo;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const TipoVehiculo({
    required this.id,
    required this.nombre,
    this.costoKmUsd,
    required this.activo,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['nombre'] = Variable<String>(nombre);
    if (!nullToAbsent || costoKmUsd != null) {
      map['costo_km_usd'] = Variable<double>(costoKmUsd);
    }
    map['activo'] = Variable<bool>(activo);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  VehicleTypesCompanion toCompanion(bool nullToAbsent) {
    return VehicleTypesCompanion(
      id: Value(id),
      nombre: Value(nombre),
      costoKmUsd: costoKmUsd == null && nullToAbsent
          ? const Value.absent()
          : Value(costoKmUsd),
      activo: Value(activo),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory TipoVehiculo.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TipoVehiculo(
      id: serializer.fromJson<String>(json['id']),
      nombre: serializer.fromJson<String>(json['nombre']),
      costoKmUsd: serializer.fromJson<double?>(json['costoKmUsd']),
      activo: serializer.fromJson<bool>(json['activo']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'nombre': serializer.toJson<String>(nombre),
      'costoKmUsd': serializer.toJson<double?>(costoKmUsd),
      'activo': serializer.toJson<bool>(activo),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  TipoVehiculo copyWith({
    String? id,
    String? nombre,
    Value<double?> costoKmUsd = const Value.absent(),
    bool? activo,
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => TipoVehiculo(
    id: id ?? this.id,
    nombre: nombre ?? this.nombre,
    costoKmUsd: costoKmUsd.present ? costoKmUsd.value : this.costoKmUsd,
    activo: activo ?? this.activo,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  TipoVehiculo copyWithCompanion(VehicleTypesCompanion data) {
    return TipoVehiculo(
      id: data.id.present ? data.id.value : this.id,
      nombre: data.nombre.present ? data.nombre.value : this.nombre,
      costoKmUsd: data.costoKmUsd.present
          ? data.costoKmUsd.value
          : this.costoKmUsd,
      activo: data.activo.present ? data.activo.value : this.activo,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TipoVehiculo(')
          ..write('id: $id, ')
          ..write('nombre: $nombre, ')
          ..write('costoKmUsd: $costoKmUsd, ')
          ..write('activo: $activo, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, nombre, costoKmUsd, activo, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TipoVehiculo &&
          other.id == this.id &&
          other.nombre == this.nombre &&
          other.costoKmUsd == this.costoKmUsd &&
          other.activo == this.activo &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class VehicleTypesCompanion extends UpdateCompanion<TipoVehiculo> {
  final Value<String> id;
  final Value<String> nombre;
  final Value<double?> costoKmUsd;
  final Value<bool> activo;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const VehicleTypesCompanion({
    this.id = const Value.absent(),
    this.nombre = const Value.absent(),
    this.costoKmUsd = const Value.absent(),
    this.activo = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VehicleTypesCompanion.insert({
    required String id,
    required String nombre,
    this.costoKmUsd = const Value.absent(),
    this.activo = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       nombre = Value(nombre);
  static Insertable<TipoVehiculo> custom({
    Expression<String>? id,
    Expression<String>? nombre,
    Expression<double>? costoKmUsd,
    Expression<bool>? activo,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (nombre != null) 'nombre': nombre,
      if (costoKmUsd != null) 'costo_km_usd': costoKmUsd,
      if (activo != null) 'activo': activo,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VehicleTypesCompanion copyWith({
    Value<String>? id,
    Value<String>? nombre,
    Value<double?>? costoKmUsd,
    Value<bool>? activo,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return VehicleTypesCompanion(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      costoKmUsd: costoKmUsd ?? this.costoKmUsd,
      activo: activo ?? this.activo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (nombre.present) {
      map['nombre'] = Variable<String>(nombre.value);
    }
    if (costoKmUsd.present) {
      map['costo_km_usd'] = Variable<double>(costoKmUsd.value);
    }
    if (activo.present) {
      map['activo'] = Variable<bool>(activo.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VehicleTypesCompanion(')
          ..write('id: $id, ')
          ..write('nombre: $nombre, ')
          ..write('costoKmUsd: $costoKmUsd, ')
          ..write('activo: $activo, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VehiclesTable extends Vehicles with TableInfo<$VehiclesTable, Vehiculo> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VehiclesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _vehicleTypeIdMeta = const VerificationMeta(
    'vehicleTypeId',
  );
  @override
  late final GeneratedColumn<String> vehicleTypeId = GeneratedColumn<String>(
    'vehicle_type_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plateMeta = const VerificationMeta('plate');
  @override
  late final GeneratedColumn<String> plate = GeneratedColumn<String>(
    'plate',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _capacityMeta = const VerificationMeta(
    'capacity',
  );
  @override
  late final GeneratedColumn<double> capacity = GeneratedColumn<double>(
    'capacity',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1000),
  );
  static const VerificationMeta _costoKmUsdMeta = const VerificationMeta(
    'costoKmUsd',
  );
  @override
  late final GeneratedColumn<double> costoKmUsd = GeneratedColumn<double>(
    'costo_km_usd',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _usarParaDomicilioMeta = const VerificationMeta(
    'usarParaDomicilio',
  );
  @override
  late final GeneratedColumn<bool> usarParaDomicilio = GeneratedColumn<bool>(
    'usar_para_domicilio',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("usar_para_domicilio" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('available'),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    vehicleTypeId,
    plate,
    capacity,
    costoKmUsd,
    usarParaDomicilio,
    status,
    isActive,
    notes,
    branchId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vehicles';
  @override
  VerificationContext validateIntegrity(
    Insertable<Vehiculo> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('vehicle_type_id')) {
      context.handle(
        _vehicleTypeIdMeta,
        vehicleTypeId.isAcceptableOrUnknown(
          data['vehicle_type_id']!,
          _vehicleTypeIdMeta,
        ),
      );
    }
    if (data.containsKey('plate')) {
      context.handle(
        _plateMeta,
        plate.isAcceptableOrUnknown(data['plate']!, _plateMeta),
      );
    }
    if (data.containsKey('capacity')) {
      context.handle(
        _capacityMeta,
        capacity.isAcceptableOrUnknown(data['capacity']!, _capacityMeta),
      );
    }
    if (data.containsKey('costo_km_usd')) {
      context.handle(
        _costoKmUsdMeta,
        costoKmUsd.isAcceptableOrUnknown(
          data['costo_km_usd']!,
          _costoKmUsdMeta,
        ),
      );
    }
    if (data.containsKey('usar_para_domicilio')) {
      context.handle(
        _usarParaDomicilioMeta,
        usarParaDomicilio.isAcceptableOrUnknown(
          data['usar_para_domicilio']!,
          _usarParaDomicilioMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Vehiculo map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Vehiculo(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      vehicleTypeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vehicle_type_id'],
      ),
      plate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plate'],
      ),
      capacity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}capacity'],
      )!,
      costoKmUsd: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}costo_km_usd'],
      ),
      usarParaDomicilio: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}usar_para_domicilio'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $VehiclesTable createAlias(String alias) {
    return $VehiclesTable(attachedDatabase, alias);
  }
}

class Vehiculo extends DataClass implements Insertable<Vehiculo> {
  final String id;
  final String name;
  final String? vehicleTypeId;
  final String? plate;
  final double capacity;
  final double? costoKmUsd;

  /// El vehiculo de REFERENCIA de su sucursal para calcular el domicilio.
  /// En el servidor lo limita un indice unico parcial; aqui hay que hacer lo
  /// mismo a mano y EN LA MISMA TRANSACCION, o la pantalla ensena dos marcados
  /// hasta la proxima bajada (PLAN.md §3.4).
  final bool usarParaDomicilio;
  final String status;
  final bool isActive;
  final String? notes;
  final String? branchId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const Vehiculo({
    required this.id,
    required this.name,
    this.vehicleTypeId,
    this.plate,
    required this.capacity,
    this.costoKmUsd,
    required this.usarParaDomicilio,
    required this.status,
    required this.isActive,
    this.notes,
    this.branchId,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || vehicleTypeId != null) {
      map['vehicle_type_id'] = Variable<String>(vehicleTypeId);
    }
    if (!nullToAbsent || plate != null) {
      map['plate'] = Variable<String>(plate);
    }
    map['capacity'] = Variable<double>(capacity);
    if (!nullToAbsent || costoKmUsd != null) {
      map['costo_km_usd'] = Variable<double>(costoKmUsd);
    }
    map['usar_para_domicilio'] = Variable<bool>(usarParaDomicilio);
    map['status'] = Variable<String>(status);
    map['is_active'] = Variable<bool>(isActive);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || branchId != null) {
      map['branch_id'] = Variable<String>(branchId);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  VehiclesCompanion toCompanion(bool nullToAbsent) {
    return VehiclesCompanion(
      id: Value(id),
      name: Value(name),
      vehicleTypeId: vehicleTypeId == null && nullToAbsent
          ? const Value.absent()
          : Value(vehicleTypeId),
      plate: plate == null && nullToAbsent
          ? const Value.absent()
          : Value(plate),
      capacity: Value(capacity),
      costoKmUsd: costoKmUsd == null && nullToAbsent
          ? const Value.absent()
          : Value(costoKmUsd),
      usarParaDomicilio: Value(usarParaDomicilio),
      status: Value(status),
      isActive: Value(isActive),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      branchId: branchId == null && nullToAbsent
          ? const Value.absent()
          : Value(branchId),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory Vehiculo.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Vehiculo(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      vehicleTypeId: serializer.fromJson<String?>(json['vehicleTypeId']),
      plate: serializer.fromJson<String?>(json['plate']),
      capacity: serializer.fromJson<double>(json['capacity']),
      costoKmUsd: serializer.fromJson<double?>(json['costoKmUsd']),
      usarParaDomicilio: serializer.fromJson<bool>(json['usarParaDomicilio']),
      status: serializer.fromJson<String>(json['status']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      notes: serializer.fromJson<String?>(json['notes']),
      branchId: serializer.fromJson<String?>(json['branchId']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'vehicleTypeId': serializer.toJson<String?>(vehicleTypeId),
      'plate': serializer.toJson<String?>(plate),
      'capacity': serializer.toJson<double>(capacity),
      'costoKmUsd': serializer.toJson<double?>(costoKmUsd),
      'usarParaDomicilio': serializer.toJson<bool>(usarParaDomicilio),
      'status': serializer.toJson<String>(status),
      'isActive': serializer.toJson<bool>(isActive),
      'notes': serializer.toJson<String?>(notes),
      'branchId': serializer.toJson<String?>(branchId),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  Vehiculo copyWith({
    String? id,
    String? name,
    Value<String?> vehicleTypeId = const Value.absent(),
    Value<String?> plate = const Value.absent(),
    double? capacity,
    Value<double?> costoKmUsd = const Value.absent(),
    bool? usarParaDomicilio,
    String? status,
    bool? isActive,
    Value<String?> notes = const Value.absent(),
    Value<String?> branchId = const Value.absent(),
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => Vehiculo(
    id: id ?? this.id,
    name: name ?? this.name,
    vehicleTypeId: vehicleTypeId.present
        ? vehicleTypeId.value
        : this.vehicleTypeId,
    plate: plate.present ? plate.value : this.plate,
    capacity: capacity ?? this.capacity,
    costoKmUsd: costoKmUsd.present ? costoKmUsd.value : this.costoKmUsd,
    usarParaDomicilio: usarParaDomicilio ?? this.usarParaDomicilio,
    status: status ?? this.status,
    isActive: isActive ?? this.isActive,
    notes: notes.present ? notes.value : this.notes,
    branchId: branchId.present ? branchId.value : this.branchId,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  Vehiculo copyWithCompanion(VehiclesCompanion data) {
    return Vehiculo(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      vehicleTypeId: data.vehicleTypeId.present
          ? data.vehicleTypeId.value
          : this.vehicleTypeId,
      plate: data.plate.present ? data.plate.value : this.plate,
      capacity: data.capacity.present ? data.capacity.value : this.capacity,
      costoKmUsd: data.costoKmUsd.present
          ? data.costoKmUsd.value
          : this.costoKmUsd,
      usarParaDomicilio: data.usarParaDomicilio.present
          ? data.usarParaDomicilio.value
          : this.usarParaDomicilio,
      status: data.status.present ? data.status.value : this.status,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      notes: data.notes.present ? data.notes.value : this.notes,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Vehiculo(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('vehicleTypeId: $vehicleTypeId, ')
          ..write('plate: $plate, ')
          ..write('capacity: $capacity, ')
          ..write('costoKmUsd: $costoKmUsd, ')
          ..write('usarParaDomicilio: $usarParaDomicilio, ')
          ..write('status: $status, ')
          ..write('isActive: $isActive, ')
          ..write('notes: $notes, ')
          ..write('branchId: $branchId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    vehicleTypeId,
    plate,
    capacity,
    costoKmUsd,
    usarParaDomicilio,
    status,
    isActive,
    notes,
    branchId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Vehiculo &&
          other.id == this.id &&
          other.name == this.name &&
          other.vehicleTypeId == this.vehicleTypeId &&
          other.plate == this.plate &&
          other.capacity == this.capacity &&
          other.costoKmUsd == this.costoKmUsd &&
          other.usarParaDomicilio == this.usarParaDomicilio &&
          other.status == this.status &&
          other.isActive == this.isActive &&
          other.notes == this.notes &&
          other.branchId == this.branchId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class VehiclesCompanion extends UpdateCompanion<Vehiculo> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> vehicleTypeId;
  final Value<String?> plate;
  final Value<double> capacity;
  final Value<double?> costoKmUsd;
  final Value<bool> usarParaDomicilio;
  final Value<String> status;
  final Value<bool> isActive;
  final Value<String?> notes;
  final Value<String?> branchId;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const VehiclesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.vehicleTypeId = const Value.absent(),
    this.plate = const Value.absent(),
    this.capacity = const Value.absent(),
    this.costoKmUsd = const Value.absent(),
    this.usarParaDomicilio = const Value.absent(),
    this.status = const Value.absent(),
    this.isActive = const Value.absent(),
    this.notes = const Value.absent(),
    this.branchId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VehiclesCompanion.insert({
    required String id,
    required String name,
    this.vehicleTypeId = const Value.absent(),
    this.plate = const Value.absent(),
    this.capacity = const Value.absent(),
    this.costoKmUsd = const Value.absent(),
    this.usarParaDomicilio = const Value.absent(),
    this.status = const Value.absent(),
    this.isActive = const Value.absent(),
    this.notes = const Value.absent(),
    this.branchId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<Vehiculo> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? vehicleTypeId,
    Expression<String>? plate,
    Expression<double>? capacity,
    Expression<double>? costoKmUsd,
    Expression<bool>? usarParaDomicilio,
    Expression<String>? status,
    Expression<bool>? isActive,
    Expression<String>? notes,
    Expression<String>? branchId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (vehicleTypeId != null) 'vehicle_type_id': vehicleTypeId,
      if (plate != null) 'plate': plate,
      if (capacity != null) 'capacity': capacity,
      if (costoKmUsd != null) 'costo_km_usd': costoKmUsd,
      if (usarParaDomicilio != null) 'usar_para_domicilio': usarParaDomicilio,
      if (status != null) 'status': status,
      if (isActive != null) 'is_active': isActive,
      if (notes != null) 'notes': notes,
      if (branchId != null) 'branch_id': branchId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VehiclesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? vehicleTypeId,
    Value<String?>? plate,
    Value<double>? capacity,
    Value<double?>? costoKmUsd,
    Value<bool>? usarParaDomicilio,
    Value<String>? status,
    Value<bool>? isActive,
    Value<String?>? notes,
    Value<String?>? branchId,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return VehiclesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      vehicleTypeId: vehicleTypeId ?? this.vehicleTypeId,
      plate: plate ?? this.plate,
      capacity: capacity ?? this.capacity,
      costoKmUsd: costoKmUsd ?? this.costoKmUsd,
      usarParaDomicilio: usarParaDomicilio ?? this.usarParaDomicilio,
      status: status ?? this.status,
      isActive: isActive ?? this.isActive,
      notes: notes ?? this.notes,
      branchId: branchId ?? this.branchId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (vehicleTypeId.present) {
      map['vehicle_type_id'] = Variable<String>(vehicleTypeId.value);
    }
    if (plate.present) {
      map['plate'] = Variable<String>(plate.value);
    }
    if (capacity.present) {
      map['capacity'] = Variable<double>(capacity.value);
    }
    if (costoKmUsd.present) {
      map['costo_km_usd'] = Variable<double>(costoKmUsd.value);
    }
    if (usarParaDomicilio.present) {
      map['usar_para_domicilio'] = Variable<bool>(usarParaDomicilio.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VehiclesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('vehicleTypeId: $vehicleTypeId, ')
          ..write('plate: $plate, ')
          ..write('capacity: $capacity, ')
          ..write('costoKmUsd: $costoKmUsd, ')
          ..write('usarParaDomicilio: $usarParaDomicilio, ')
          ..write('status: $status, ')
          ..write('isActive: $isActive, ')
          ..write('notes: $notes, ')
          ..write('branchId: $branchId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductsTable extends Products with TableInfo<$ProductsTable, Producto> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weightMeta = const VerificationMeta('weight');
  @override
  late final GeneratedColumn<double> weight = GeneratedColumn<double>(
    'weight',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _packagingMeta = const VerificationMeta(
    'packaging',
  );
  @override
  late final GeneratedColumn<String> packaging = GeneratedColumn<String>(
    'packaging',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitsPerPackageMeta = const VerificationMeta(
    'unitsPerPackage',
  );
  @override
  late final GeneratedColumn<double> unitsPerPackage = GeneratedColumn<double>(
    'units_per_package',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _skuMeta = const VerificationMeta('sku');
  @override
  late final GeneratedColumn<String> sku = GeneratedColumn<String>(
    'sku',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sucursalCodigoMeta = const VerificationMeta(
    'sucursalCodigo',
  );
  @override
  late final GeneratedColumn<String> sucursalCodigo = GeneratedColumn<String>(
    'sucursal_codigo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
    'price',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stockMeta = const VerificationMeta('stock');
  @override
  late final GeneratedColumn<double> stock = GeneratedColumn<double>(
    'stock',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _traidoAtMeta = const VerificationMeta(
    'traidoAt',
  );
  @override
  late final GeneratedColumn<DateTime> traidoAt = GeneratedColumn<DateTime>(
    'traido_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    weight,
    packaging,
    unitsPerPackage,
    category,
    sku,
    sucursalCodigo,
    price,
    stock,
    unit,
    traidoAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'products';
  @override
  VerificationContext validateIntegrity(
    Insertable<Producto> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('weight')) {
      context.handle(
        _weightMeta,
        weight.isAcceptableOrUnknown(data['weight']!, _weightMeta),
      );
    }
    if (data.containsKey('packaging')) {
      context.handle(
        _packagingMeta,
        packaging.isAcceptableOrUnknown(data['packaging']!, _packagingMeta),
      );
    }
    if (data.containsKey('units_per_package')) {
      context.handle(
        _unitsPerPackageMeta,
        unitsPerPackage.isAcceptableOrUnknown(
          data['units_per_package']!,
          _unitsPerPackageMeta,
        ),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('sku')) {
      context.handle(
        _skuMeta,
        sku.isAcceptableOrUnknown(data['sku']!, _skuMeta),
      );
    }
    if (data.containsKey('sucursal_codigo')) {
      context.handle(
        _sucursalCodigoMeta,
        sucursalCodigo.isAcceptableOrUnknown(
          data['sucursal_codigo']!,
          _sucursalCodigoMeta,
        ),
      );
    }
    if (data.containsKey('price')) {
      context.handle(
        _priceMeta,
        price.isAcceptableOrUnknown(data['price']!, _priceMeta),
      );
    }
    if (data.containsKey('stock')) {
      context.handle(
        _stockMeta,
        stock.isAcceptableOrUnknown(data['stock']!, _stockMeta),
      );
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    }
    if (data.containsKey('traido_at')) {
      context.handle(
        _traidoAtMeta,
        traidoAt.isAcceptableOrUnknown(data['traido_at']!, _traidoAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Producto map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Producto(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      weight: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight'],
      )!,
      packaging: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}packaging'],
      ),
      unitsPerPackage: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}units_per_package'],
      ),
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      sku: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sku'],
      ),
      sucursalCodigo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sucursal_codigo'],
      ),
      price: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}price'],
      ),
      stock: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}stock'],
      ),
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      ),
      traidoAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}traido_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $ProductsTable createAlias(String alias) {
    return $ProductsTable(attachedDatabase, alias);
  }
}

class Producto extends DataClass implements Insertable<Producto> {
  final String id;
  final String name;
  final double weight;
  final String? packaging;
  final double? unitsPerPackage;
  final String? category;
  final String? sku;
  final String? sucursalCodigo;
  final double? price;
  final double? stock;
  final String? unit;

  /// Cuando lo trajo Ventra. No es `updatedAt`: dice si lo que se mira es de hace
  /// diez minutos o de hace tres dias porque la VPN lleva caida desde el lunes.
  final DateTime? traidoAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const Producto({
    required this.id,
    required this.name,
    required this.weight,
    this.packaging,
    this.unitsPerPackage,
    this.category,
    this.sku,
    this.sucursalCodigo,
    this.price,
    this.stock,
    this.unit,
    this.traidoAt,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['weight'] = Variable<double>(weight);
    if (!nullToAbsent || packaging != null) {
      map['packaging'] = Variable<String>(packaging);
    }
    if (!nullToAbsent || unitsPerPackage != null) {
      map['units_per_package'] = Variable<double>(unitsPerPackage);
    }
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    if (!nullToAbsent || sku != null) {
      map['sku'] = Variable<String>(sku);
    }
    if (!nullToAbsent || sucursalCodigo != null) {
      map['sucursal_codigo'] = Variable<String>(sucursalCodigo);
    }
    if (!nullToAbsent || price != null) {
      map['price'] = Variable<double>(price);
    }
    if (!nullToAbsent || stock != null) {
      map['stock'] = Variable<double>(stock);
    }
    if (!nullToAbsent || unit != null) {
      map['unit'] = Variable<String>(unit);
    }
    if (!nullToAbsent || traidoAt != null) {
      map['traido_at'] = Variable<DateTime>(traidoAt);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  ProductsCompanion toCompanion(bool nullToAbsent) {
    return ProductsCompanion(
      id: Value(id),
      name: Value(name),
      weight: Value(weight),
      packaging: packaging == null && nullToAbsent
          ? const Value.absent()
          : Value(packaging),
      unitsPerPackage: unitsPerPackage == null && nullToAbsent
          ? const Value.absent()
          : Value(unitsPerPackage),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      sku: sku == null && nullToAbsent ? const Value.absent() : Value(sku),
      sucursalCodigo: sucursalCodigo == null && nullToAbsent
          ? const Value.absent()
          : Value(sucursalCodigo),
      price: price == null && nullToAbsent
          ? const Value.absent()
          : Value(price),
      stock: stock == null && nullToAbsent
          ? const Value.absent()
          : Value(stock),
      unit: unit == null && nullToAbsent ? const Value.absent() : Value(unit),
      traidoAt: traidoAt == null && nullToAbsent
          ? const Value.absent()
          : Value(traidoAt),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory Producto.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Producto(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      weight: serializer.fromJson<double>(json['weight']),
      packaging: serializer.fromJson<String?>(json['packaging']),
      unitsPerPackage: serializer.fromJson<double?>(json['unitsPerPackage']),
      category: serializer.fromJson<String?>(json['category']),
      sku: serializer.fromJson<String?>(json['sku']),
      sucursalCodigo: serializer.fromJson<String?>(json['sucursalCodigo']),
      price: serializer.fromJson<double?>(json['price']),
      stock: serializer.fromJson<double?>(json['stock']),
      unit: serializer.fromJson<String?>(json['unit']),
      traidoAt: serializer.fromJson<DateTime?>(json['traidoAt']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'weight': serializer.toJson<double>(weight),
      'packaging': serializer.toJson<String?>(packaging),
      'unitsPerPackage': serializer.toJson<double?>(unitsPerPackage),
      'category': serializer.toJson<String?>(category),
      'sku': serializer.toJson<String?>(sku),
      'sucursalCodigo': serializer.toJson<String?>(sucursalCodigo),
      'price': serializer.toJson<double?>(price),
      'stock': serializer.toJson<double?>(stock),
      'unit': serializer.toJson<String?>(unit),
      'traidoAt': serializer.toJson<DateTime?>(traidoAt),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  Producto copyWith({
    String? id,
    String? name,
    double? weight,
    Value<String?> packaging = const Value.absent(),
    Value<double?> unitsPerPackage = const Value.absent(),
    Value<String?> category = const Value.absent(),
    Value<String?> sku = const Value.absent(),
    Value<String?> sucursalCodigo = const Value.absent(),
    Value<double?> price = const Value.absent(),
    Value<double?> stock = const Value.absent(),
    Value<String?> unit = const Value.absent(),
    Value<DateTime?> traidoAt = const Value.absent(),
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => Producto(
    id: id ?? this.id,
    name: name ?? this.name,
    weight: weight ?? this.weight,
    packaging: packaging.present ? packaging.value : this.packaging,
    unitsPerPackage: unitsPerPackage.present
        ? unitsPerPackage.value
        : this.unitsPerPackage,
    category: category.present ? category.value : this.category,
    sku: sku.present ? sku.value : this.sku,
    sucursalCodigo: sucursalCodigo.present
        ? sucursalCodigo.value
        : this.sucursalCodigo,
    price: price.present ? price.value : this.price,
    stock: stock.present ? stock.value : this.stock,
    unit: unit.present ? unit.value : this.unit,
    traidoAt: traidoAt.present ? traidoAt.value : this.traidoAt,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  Producto copyWithCompanion(ProductsCompanion data) {
    return Producto(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      weight: data.weight.present ? data.weight.value : this.weight,
      packaging: data.packaging.present ? data.packaging.value : this.packaging,
      unitsPerPackage: data.unitsPerPackage.present
          ? data.unitsPerPackage.value
          : this.unitsPerPackage,
      category: data.category.present ? data.category.value : this.category,
      sku: data.sku.present ? data.sku.value : this.sku,
      sucursalCodigo: data.sucursalCodigo.present
          ? data.sucursalCodigo.value
          : this.sucursalCodigo,
      price: data.price.present ? data.price.value : this.price,
      stock: data.stock.present ? data.stock.value : this.stock,
      unit: data.unit.present ? data.unit.value : this.unit,
      traidoAt: data.traidoAt.present ? data.traidoAt.value : this.traidoAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Producto(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('weight: $weight, ')
          ..write('packaging: $packaging, ')
          ..write('unitsPerPackage: $unitsPerPackage, ')
          ..write('category: $category, ')
          ..write('sku: $sku, ')
          ..write('sucursalCodigo: $sucursalCodigo, ')
          ..write('price: $price, ')
          ..write('stock: $stock, ')
          ..write('unit: $unit, ')
          ..write('traidoAt: $traidoAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    weight,
    packaging,
    unitsPerPackage,
    category,
    sku,
    sucursalCodigo,
    price,
    stock,
    unit,
    traidoAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Producto &&
          other.id == this.id &&
          other.name == this.name &&
          other.weight == this.weight &&
          other.packaging == this.packaging &&
          other.unitsPerPackage == this.unitsPerPackage &&
          other.category == this.category &&
          other.sku == this.sku &&
          other.sucursalCodigo == this.sucursalCodigo &&
          other.price == this.price &&
          other.stock == this.stock &&
          other.unit == this.unit &&
          other.traidoAt == this.traidoAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProductsCompanion extends UpdateCompanion<Producto> {
  final Value<String> id;
  final Value<String> name;
  final Value<double> weight;
  final Value<String?> packaging;
  final Value<double?> unitsPerPackage;
  final Value<String?> category;
  final Value<String?> sku;
  final Value<String?> sucursalCodigo;
  final Value<double?> price;
  final Value<double?> stock;
  final Value<String?> unit;
  final Value<DateTime?> traidoAt;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const ProductsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.weight = const Value.absent(),
    this.packaging = const Value.absent(),
    this.unitsPerPackage = const Value.absent(),
    this.category = const Value.absent(),
    this.sku = const Value.absent(),
    this.sucursalCodigo = const Value.absent(),
    this.price = const Value.absent(),
    this.stock = const Value.absent(),
    this.unit = const Value.absent(),
    this.traidoAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductsCompanion.insert({
    required String id,
    required String name,
    this.weight = const Value.absent(),
    this.packaging = const Value.absent(),
    this.unitsPerPackage = const Value.absent(),
    this.category = const Value.absent(),
    this.sku = const Value.absent(),
    this.sucursalCodigo = const Value.absent(),
    this.price = const Value.absent(),
    this.stock = const Value.absent(),
    this.unit = const Value.absent(),
    this.traidoAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<Producto> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<double>? weight,
    Expression<String>? packaging,
    Expression<double>? unitsPerPackage,
    Expression<String>? category,
    Expression<String>? sku,
    Expression<String>? sucursalCodigo,
    Expression<double>? price,
    Expression<double>? stock,
    Expression<String>? unit,
    Expression<DateTime>? traidoAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (weight != null) 'weight': weight,
      if (packaging != null) 'packaging': packaging,
      if (unitsPerPackage != null) 'units_per_package': unitsPerPackage,
      if (category != null) 'category': category,
      if (sku != null) 'sku': sku,
      if (sucursalCodigo != null) 'sucursal_codigo': sucursalCodigo,
      if (price != null) 'price': price,
      if (stock != null) 'stock': stock,
      if (unit != null) 'unit': unit,
      if (traidoAt != null) 'traido_at': traidoAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<double>? weight,
    Value<String?>? packaging,
    Value<double?>? unitsPerPackage,
    Value<String?>? category,
    Value<String?>? sku,
    Value<String?>? sucursalCodigo,
    Value<double?>? price,
    Value<double?>? stock,
    Value<String?>? unit,
    Value<DateTime?>? traidoAt,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return ProductsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      weight: weight ?? this.weight,
      packaging: packaging ?? this.packaging,
      unitsPerPackage: unitsPerPackage ?? this.unitsPerPackage,
      category: category ?? this.category,
      sku: sku ?? this.sku,
      sucursalCodigo: sucursalCodigo ?? this.sucursalCodigo,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      unit: unit ?? this.unit,
      traidoAt: traidoAt ?? this.traidoAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (weight.present) {
      map['weight'] = Variable<double>(weight.value);
    }
    if (packaging.present) {
      map['packaging'] = Variable<String>(packaging.value);
    }
    if (unitsPerPackage.present) {
      map['units_per_package'] = Variable<double>(unitsPerPackage.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (sku.present) {
      map['sku'] = Variable<String>(sku.value);
    }
    if (sucursalCodigo.present) {
      map['sucursal_codigo'] = Variable<String>(sucursalCodigo.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (stock.present) {
      map['stock'] = Variable<double>(stock.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (traidoAt.present) {
      map['traido_at'] = Variable<DateTime>(traidoAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('weight: $weight, ')
          ..write('packaging: $packaging, ')
          ..write('unitsPerPackage: $unitsPerPackage, ')
          ..write('category: $category, ')
          ..write('sku: $sku, ')
          ..write('sucursalCodigo: $sucursalCodigo, ')
          ..write('price: $price, ')
          ..write('stock: $stock, ')
          ..write('unit: $unit, ')
          ..write('traidoAt: $traidoAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CustomersTable extends Customers
    with TableInfo<$CustomersTable, Cliente> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _externalIdMeta = const VerificationMeta(
    'externalId',
  );
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
    'external_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _municipioMeta = const VerificationMeta(
    'municipio',
  );
  @override
  late final GeneratedColumn<String> municipio = GeneratedColumn<String>(
    'municipio',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _zonaMeta = const VerificationMeta('zona');
  @override
  late final GeneratedColumn<String> zona = GeneratedColumn<String>(
    'zona',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _codigoMeta = const VerificationMeta('codigo');
  @override
  late final GeneratedColumn<String> codigo = GeneratedColumn<String>(
    'codigo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vendedorMeta = const VerificationMeta(
    'vendedor',
  );
  @override
  late final GeneratedColumn<String> vendedor = GeneratedColumn<String>(
    'vendedor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lngMeta = const VerificationMeta('lng');
  @override
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
    'lng',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sucursalCodigoMeta = const VerificationMeta(
    'sucursalCodigo',
  );
  @override
  late final GeneratedColumn<String> sucursalCodigo = GeneratedColumn<String>(
    'sucursal_codigo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
    'synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    source,
    externalId,
    name,
    phone,
    address,
    municipio,
    zona,
    codigo,
    vendedor,
    lat,
    lng,
    sucursalCodigo,
    syncedAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'customers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Cliente> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('external_id')) {
      context.handle(
        _externalIdMeta,
        externalId.isAcceptableOrUnknown(data['external_id']!, _externalIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    }
    if (data.containsKey('municipio')) {
      context.handle(
        _municipioMeta,
        municipio.isAcceptableOrUnknown(data['municipio']!, _municipioMeta),
      );
    }
    if (data.containsKey('zona')) {
      context.handle(
        _zonaMeta,
        zona.isAcceptableOrUnknown(data['zona']!, _zonaMeta),
      );
    }
    if (data.containsKey('codigo')) {
      context.handle(
        _codigoMeta,
        codigo.isAcceptableOrUnknown(data['codigo']!, _codigoMeta),
      );
    }
    if (data.containsKey('vendedor')) {
      context.handle(
        _vendedorMeta,
        vendedor.isAcceptableOrUnknown(data['vendedor']!, _vendedorMeta),
      );
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lng')) {
      context.handle(
        _lngMeta,
        lng.isAcceptableOrUnknown(data['lng']!, _lngMeta),
      );
    } else if (isInserting) {
      context.missing(_lngMeta);
    }
    if (data.containsKey('sucursal_codigo')) {
      context.handle(
        _sucursalCodigoMeta,
        sucursalCodigo.isAcceptableOrUnknown(
          data['sucursal_codigo']!,
          _sucursalCodigoMeta,
        ),
      );
    }
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Cliente map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Cliente(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      ),
      externalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}external_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      ),
      municipio: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}municipio'],
      ),
      zona: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}zona'],
      ),
      codigo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}codigo'],
      ),
      vendedor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vendedor'],
      ),
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lng'],
      )!,
      sucursalCodigo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sucursal_codigo'],
      ),
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}synced_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $CustomersTable createAlias(String alias) {
    return $CustomersTable(attachedDatabase, alias);
  }
}

class Cliente extends DataClass implements Insertable<Cliente> {
  final String id;
  final String? source;
  final String? externalId;
  final String name;
  final String? phone;
  final String? address;
  final String? municipio;
  final String? zona;
  final String? codigo;
  final String? vendedor;
  final double lat;
  final double lng;
  final String? sucursalCodigo;
  final DateTime? syncedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const Cliente({
    required this.id,
    this.source,
    this.externalId,
    required this.name,
    this.phone,
    this.address,
    this.municipio,
    this.zona,
    this.codigo,
    this.vendedor,
    required this.lat,
    required this.lng,
    this.sucursalCodigo,
    this.syncedAt,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || source != null) {
      map['source'] = Variable<String>(source);
    }
    if (!nullToAbsent || externalId != null) {
      map['external_id'] = Variable<String>(externalId);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    if (!nullToAbsent || municipio != null) {
      map['municipio'] = Variable<String>(municipio);
    }
    if (!nullToAbsent || zona != null) {
      map['zona'] = Variable<String>(zona);
    }
    if (!nullToAbsent || codigo != null) {
      map['codigo'] = Variable<String>(codigo);
    }
    if (!nullToAbsent || vendedor != null) {
      map['vendedor'] = Variable<String>(vendedor);
    }
    map['lat'] = Variable<double>(lat);
    map['lng'] = Variable<double>(lng);
    if (!nullToAbsent || sucursalCodigo != null) {
      map['sucursal_codigo'] = Variable<String>(sucursalCodigo);
    }
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  CustomersCompanion toCompanion(bool nullToAbsent) {
    return CustomersCompanion(
      id: Value(id),
      source: source == null && nullToAbsent
          ? const Value.absent()
          : Value(source),
      externalId: externalId == null && nullToAbsent
          ? const Value.absent()
          : Value(externalId),
      name: Value(name),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      municipio: municipio == null && nullToAbsent
          ? const Value.absent()
          : Value(municipio),
      zona: zona == null && nullToAbsent ? const Value.absent() : Value(zona),
      codigo: codigo == null && nullToAbsent
          ? const Value.absent()
          : Value(codigo),
      vendedor: vendedor == null && nullToAbsent
          ? const Value.absent()
          : Value(vendedor),
      lat: Value(lat),
      lng: Value(lng),
      sucursalCodigo: sucursalCodigo == null && nullToAbsent
          ? const Value.absent()
          : Value(sucursalCodigo),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory Cliente.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Cliente(
      id: serializer.fromJson<String>(json['id']),
      source: serializer.fromJson<String?>(json['source']),
      externalId: serializer.fromJson<String?>(json['externalId']),
      name: serializer.fromJson<String>(json['name']),
      phone: serializer.fromJson<String?>(json['phone']),
      address: serializer.fromJson<String?>(json['address']),
      municipio: serializer.fromJson<String?>(json['municipio']),
      zona: serializer.fromJson<String?>(json['zona']),
      codigo: serializer.fromJson<String?>(json['codigo']),
      vendedor: serializer.fromJson<String?>(json['vendedor']),
      lat: serializer.fromJson<double>(json['lat']),
      lng: serializer.fromJson<double>(json['lng']),
      sucursalCodigo: serializer.fromJson<String?>(json['sucursalCodigo']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'source': serializer.toJson<String?>(source),
      'externalId': serializer.toJson<String?>(externalId),
      'name': serializer.toJson<String>(name),
      'phone': serializer.toJson<String?>(phone),
      'address': serializer.toJson<String?>(address),
      'municipio': serializer.toJson<String?>(municipio),
      'zona': serializer.toJson<String?>(zona),
      'codigo': serializer.toJson<String?>(codigo),
      'vendedor': serializer.toJson<String?>(vendedor),
      'lat': serializer.toJson<double>(lat),
      'lng': serializer.toJson<double>(lng),
      'sucursalCodigo': serializer.toJson<String?>(sucursalCodigo),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  Cliente copyWith({
    String? id,
    Value<String?> source = const Value.absent(),
    Value<String?> externalId = const Value.absent(),
    String? name,
    Value<String?> phone = const Value.absent(),
    Value<String?> address = const Value.absent(),
    Value<String?> municipio = const Value.absent(),
    Value<String?> zona = const Value.absent(),
    Value<String?> codigo = const Value.absent(),
    Value<String?> vendedor = const Value.absent(),
    double? lat,
    double? lng,
    Value<String?> sucursalCodigo = const Value.absent(),
    Value<DateTime?> syncedAt = const Value.absent(),
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => Cliente(
    id: id ?? this.id,
    source: source.present ? source.value : this.source,
    externalId: externalId.present ? externalId.value : this.externalId,
    name: name ?? this.name,
    phone: phone.present ? phone.value : this.phone,
    address: address.present ? address.value : this.address,
    municipio: municipio.present ? municipio.value : this.municipio,
    zona: zona.present ? zona.value : this.zona,
    codigo: codigo.present ? codigo.value : this.codigo,
    vendedor: vendedor.present ? vendedor.value : this.vendedor,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    sucursalCodigo: sucursalCodigo.present
        ? sucursalCodigo.value
        : this.sucursalCodigo,
    syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  Cliente copyWithCompanion(CustomersCompanion data) {
    return Cliente(
      id: data.id.present ? data.id.value : this.id,
      source: data.source.present ? data.source.value : this.source,
      externalId: data.externalId.present
          ? data.externalId.value
          : this.externalId,
      name: data.name.present ? data.name.value : this.name,
      phone: data.phone.present ? data.phone.value : this.phone,
      address: data.address.present ? data.address.value : this.address,
      municipio: data.municipio.present ? data.municipio.value : this.municipio,
      zona: data.zona.present ? data.zona.value : this.zona,
      codigo: data.codigo.present ? data.codigo.value : this.codigo,
      vendedor: data.vendedor.present ? data.vendedor.value : this.vendedor,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      sucursalCodigo: data.sucursalCodigo.present
          ? data.sucursalCodigo.value
          : this.sucursalCodigo,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Cliente(')
          ..write('id: $id, ')
          ..write('source: $source, ')
          ..write('externalId: $externalId, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('address: $address, ')
          ..write('municipio: $municipio, ')
          ..write('zona: $zona, ')
          ..write('codigo: $codigo, ')
          ..write('vendedor: $vendedor, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('sucursalCodigo: $sucursalCodigo, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    source,
    externalId,
    name,
    phone,
    address,
    municipio,
    zona,
    codigo,
    vendedor,
    lat,
    lng,
    sucursalCodigo,
    syncedAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Cliente &&
          other.id == this.id &&
          other.source == this.source &&
          other.externalId == this.externalId &&
          other.name == this.name &&
          other.phone == this.phone &&
          other.address == this.address &&
          other.municipio == this.municipio &&
          other.zona == this.zona &&
          other.codigo == this.codigo &&
          other.vendedor == this.vendedor &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.sucursalCodigo == this.sucursalCodigo &&
          other.syncedAt == this.syncedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CustomersCompanion extends UpdateCompanion<Cliente> {
  final Value<String> id;
  final Value<String?> source;
  final Value<String?> externalId;
  final Value<String> name;
  final Value<String?> phone;
  final Value<String?> address;
  final Value<String?> municipio;
  final Value<String?> zona;
  final Value<String?> codigo;
  final Value<String?> vendedor;
  final Value<double> lat;
  final Value<double> lng;
  final Value<String?> sucursalCodigo;
  final Value<DateTime?> syncedAt;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const CustomersCompanion({
    this.id = const Value.absent(),
    this.source = const Value.absent(),
    this.externalId = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.address = const Value.absent(),
    this.municipio = const Value.absent(),
    this.zona = const Value.absent(),
    this.codigo = const Value.absent(),
    this.vendedor = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.sucursalCodigo = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomersCompanion.insert({
    required String id,
    this.source = const Value.absent(),
    this.externalId = const Value.absent(),
    required String name,
    this.phone = const Value.absent(),
    this.address = const Value.absent(),
    this.municipio = const Value.absent(),
    this.zona = const Value.absent(),
    this.codigo = const Value.absent(),
    this.vendedor = const Value.absent(),
    required double lat,
    required double lng,
    this.sucursalCodigo = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       lat = Value(lat),
       lng = Value(lng);
  static Insertable<Cliente> custom({
    Expression<String>? id,
    Expression<String>? source,
    Expression<String>? externalId,
    Expression<String>? name,
    Expression<String>? phone,
    Expression<String>? address,
    Expression<String>? municipio,
    Expression<String>? zona,
    Expression<String>? codigo,
    Expression<String>? vendedor,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<String>? sucursalCodigo,
    Expression<DateTime>? syncedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (source != null) 'source': source,
      if (externalId != null) 'external_id': externalId,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (address != null) 'address': address,
      if (municipio != null) 'municipio': municipio,
      if (zona != null) 'zona': zona,
      if (codigo != null) 'codigo': codigo,
      if (vendedor != null) 'vendedor': vendedor,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (sucursalCodigo != null) 'sucursal_codigo': sucursalCodigo,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomersCompanion copyWith({
    Value<String>? id,
    Value<String?>? source,
    Value<String?>? externalId,
    Value<String>? name,
    Value<String?>? phone,
    Value<String?>? address,
    Value<String?>? municipio,
    Value<String?>? zona,
    Value<String?>? codigo,
    Value<String?>? vendedor,
    Value<double>? lat,
    Value<double>? lng,
    Value<String?>? sucursalCodigo,
    Value<DateTime?>? syncedAt,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return CustomersCompanion(
      id: id ?? this.id,
      source: source ?? this.source,
      externalId: externalId ?? this.externalId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      municipio: municipio ?? this.municipio,
      zona: zona ?? this.zona,
      codigo: codigo ?? this.codigo,
      vendedor: vendedor ?? this.vendedor,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      sucursalCodigo: sucursalCodigo ?? this.sucursalCodigo,
      syncedAt: syncedAt ?? this.syncedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (municipio.present) {
      map['municipio'] = Variable<String>(municipio.value);
    }
    if (zona.present) {
      map['zona'] = Variable<String>(zona.value);
    }
    if (codigo.present) {
      map['codigo'] = Variable<String>(codigo.value);
    }
    if (vendedor.present) {
      map['vendedor'] = Variable<String>(vendedor.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (sucursalCodigo.present) {
      map['sucursal_codigo'] = Variable<String>(sucursalCodigo.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomersCompanion(')
          ..write('id: $id, ')
          ..write('source: $source, ')
          ..write('externalId: $externalId, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('address: $address, ')
          ..write('municipio: $municipio, ')
          ..write('zona: $zona, ')
          ..write('codigo: $codigo, ')
          ..write('vendedor: $vendedor, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('sucursalCodigo: $sucursalCodigo, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OrdersTable extends Orders with TableInfo<$OrdersTable, Pedido> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OrdersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationNumberMeta = const VerificationMeta(
    'operationNumber',
  );
  @override
  late final GeneratedColumn<String> operationNumber = GeneratedColumn<String>(
    'operation_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customerNameMeta = const VerificationMeta(
    'customerName',
  );
  @override
  late final GeneratedColumn<String> customerName = GeneratedColumn<String>(
    'customer_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endAddressMeta = const VerificationMeta(
    'endAddress',
  );
  @override
  late final GeneratedColumn<String> endAddress = GeneratedColumn<String>(
    'end_address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endLatMeta = const VerificationMeta('endLat');
  @override
  late final GeneratedColumn<double> endLat = GeneratedColumn<double>(
    'end_lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endLngMeta = const VerificationMeta('endLng');
  @override
  late final GeneratedColumn<double> endLng = GeneratedColumn<double>(
    'end_lng',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lngMeta = const VerificationMeta('lng');
  @override
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
    'lng',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _weightMeta = const VerificationMeta('weight');
  @override
  late final GeneratedColumn<double> weight = GeneratedColumn<double>(
    'weight',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _tripLegMeta = const VerificationMeta(
    'tripLeg',
  );
  @override
  late final GeneratedColumn<String> tripLeg = GeneratedColumn<String>(
    'trip_leg',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('outbound'),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _routeIdMeta = const VerificationMeta(
    'routeId',
  );
  @override
  late final GeneratedColumn<String> routeId = GeneratedColumn<String>(
    'route_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ultimaRutaIdMeta = const VerificationMeta(
    'ultimaRutaId',
  );
  @override
  late final GeneratedColumn<String> ultimaRutaId = GeneratedColumn<String>(
    'ultima_ruta_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
    'price',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _segmentKmMeta = const VerificationMeta(
    'segmentKm',
  );
  @override
  late final GeneratedColumn<double> segmentKm = GeneratedColumn<double>(
    'segment_km',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deliveryPriceMeta = const VerificationMeta(
    'deliveryPrice',
  );
  @override
  late final GeneratedColumn<double> deliveryPrice = GeneratedColumn<double>(
    'delivery_price',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deliveryDistanceKmMeta =
      const VerificationMeta('deliveryDistanceKm');
  @override
  late final GeneratedColumn<double> deliveryDistanceKm =
      GeneratedColumn<double>(
        'delivery_distance_km',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _externalIdMeta = const VerificationMeta(
    'externalId',
  );
  @override
  late final GeneratedColumn<String> externalId = GeneratedColumn<String>(
    'external_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _orderDateMeta = const VerificationMeta(
    'orderDate',
  );
  @override
  late final GeneratedColumn<DateTime> orderDate = GeneratedColumn<DateTime>(
    'order_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pedidoUpdatedAtMeta = const VerificationMeta(
    'pedidoUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> pedidoUpdatedAt =
      GeneratedColumn<DateTime>(
        'pedido_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _estadoMeta = const VerificationMeta('estado');
  @override
  late final GeneratedColumn<String> estado = GeneratedColumn<String>(
    'estado',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _archivadoMeta = const VerificationMeta(
    'archivado',
  );
  @override
  late final GeneratedColumn<bool> archivado = GeneratedColumn<bool>(
    'archivado',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archivado" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _fechaComprometidaMeta = const VerificationMeta(
    'fechaComprometida',
  );
  @override
  late final GeneratedColumn<DateTime> fechaComprometida =
      GeneratedColumn<DateTime>(
        'fecha_comprometida',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _requiereDomicilioMeta = const VerificationMeta(
    'requiereDomicilio',
  );
  @override
  late final GeneratedColumn<bool> requiereDomicilio = GeneratedColumn<bool>(
    'requiere_domicilio',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("requiere_domicilio" IN (0, 1))',
    ),
  );
  static const VerificationMeta _pedidoCostoMeta = const VerificationMeta(
    'pedidoCosto',
  );
  @override
  late final GeneratedColumn<double> pedidoCosto = GeneratedColumn<double>(
    'pedido_costo',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _municipioMeta = const VerificationMeta(
    'municipio',
  );
  @override
  late final GeneratedColumn<String> municipio = GeneratedColumn<String>(
    'municipio',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vendedorMeta = const VerificationMeta(
    'vendedor',
  );
  @override
  late final GeneratedColumn<String> vendedor = GeneratedColumn<String>(
    'vendedor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sucursalCodigoMeta = const VerificationMeta(
    'sucursalCodigo',
  );
  @override
  late final GeneratedColumn<String> sucursalCodigo = GeneratedColumn<String>(
    'sucursal_codigo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _facturaEstadoMeta = const VerificationMeta(
    'facturaEstado',
  );
  @override
  late final GeneratedColumn<String> facturaEstado = GeneratedColumn<String>(
    'factura_estado',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _facturaNumeroMeta = const VerificationMeta(
    'facturaNumero',
  );
  @override
  late final GeneratedColumn<String> facturaNumero = GeneratedColumn<String>(
    'factura_numero',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _facturaAtMeta = const VerificationMeta(
    'facturaAt',
  );
  @override
  late final GeneratedColumn<DateTime> facturaAt = GeneratedColumn<DateTime>(
    'factura_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _facturaDomicilioMeta = const VerificationMeta(
    'facturaDomicilio',
  );
  @override
  late final GeneratedColumn<double> facturaDomicilio = GeneratedColumn<double>(
    'factura_domicilio',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _facturaCorregidoAtMeta =
      const VerificationMeta('facturaCorregidoAt');
  @override
  late final GeneratedColumn<DateTime> facturaCorregidoAt =
      GeneratedColumn<DateTime>(
        'factura_corregido_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _itemsOrigenMeta = const VerificationMeta(
    'itemsOrigen',
  );
  @override
  late final GeneratedColumn<String> itemsOrigen = GeneratedColumn<String>(
    'items_origen',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customerPhoneMeta = const VerificationMeta(
    'customerPhone',
  );
  @override
  late final GeneratedColumn<String> customerPhone = GeneratedColumn<String>(
    'customer_phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stopOrderMeta = const VerificationMeta(
    'stopOrder',
  );
  @override
  late final GeneratedColumn<int> stopOrder = GeneratedColumn<int>(
    'stop_order',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deliveredAtMeta = const VerificationMeta(
    'deliveredAt',
  );
  @override
  late final GeneratedColumn<DateTime> deliveredAt = GeneratedColumn<DateTime>(
    'delivered_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resultadoMeta = const VerificationMeta(
    'resultado',
  );
  @override
  late final GeneratedColumn<String> resultado = GeneratedColumn<String>(
    'resultado',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resultadoAtMeta = const VerificationMeta(
    'resultadoAt',
  );
  @override
  late final GeneratedColumn<DateTime> resultadoAt = GeneratedColumn<DateTime>(
    'resultado_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resultadoNotaMeta = const VerificationMeta(
    'resultadoNota',
  );
  @override
  late final GeneratedColumn<String> resultadoNota = GeneratedColumn<String>(
    'resultado_nota',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    operationNumber,
    customerName,
    address,
    endAddress,
    endLat,
    endLng,
    lat,
    lng,
    weight,
    status,
    tripLeg,
    notes,
    routeId,
    ultimaRutaId,
    price,
    segmentKm,
    deliveryPrice,
    deliveryDistanceKm,
    branchId,
    source,
    externalId,
    orderDate,
    pedidoUpdatedAt,
    estado,
    archivado,
    fechaComprometida,
    requiereDomicilio,
    pedidoCosto,
    municipio,
    vendedor,
    sucursalCodigo,
    facturaEstado,
    facturaNumero,
    facturaAt,
    facturaDomicilio,
    facturaCorregidoAt,
    itemsOrigen,
    customerPhone,
    stopOrder,
    deliveredAt,
    resultado,
    resultadoAt,
    resultadoNota,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'orders';
  @override
  VerificationContext validateIntegrity(
    Insertable<Pedido> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('operation_number')) {
      context.handle(
        _operationNumberMeta,
        operationNumber.isAcceptableOrUnknown(
          data['operation_number']!,
          _operationNumberMeta,
        ),
      );
    }
    if (data.containsKey('customer_name')) {
      context.handle(
        _customerNameMeta,
        customerName.isAcceptableOrUnknown(
          data['customer_name']!,
          _customerNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_customerNameMeta);
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    } else if (isInserting) {
      context.missing(_addressMeta);
    }
    if (data.containsKey('end_address')) {
      context.handle(
        _endAddressMeta,
        endAddress.isAcceptableOrUnknown(data['end_address']!, _endAddressMeta),
      );
    }
    if (data.containsKey('end_lat')) {
      context.handle(
        _endLatMeta,
        endLat.isAcceptableOrUnknown(data['end_lat']!, _endLatMeta),
      );
    }
    if (data.containsKey('end_lng')) {
      context.handle(
        _endLngMeta,
        endLng.isAcceptableOrUnknown(data['end_lng']!, _endLngMeta),
      );
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    }
    if (data.containsKey('lng')) {
      context.handle(
        _lngMeta,
        lng.isAcceptableOrUnknown(data['lng']!, _lngMeta),
      );
    }
    if (data.containsKey('weight')) {
      context.handle(
        _weightMeta,
        weight.isAcceptableOrUnknown(data['weight']!, _weightMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('trip_leg')) {
      context.handle(
        _tripLegMeta,
        tripLeg.isAcceptableOrUnknown(data['trip_leg']!, _tripLegMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('route_id')) {
      context.handle(
        _routeIdMeta,
        routeId.isAcceptableOrUnknown(data['route_id']!, _routeIdMeta),
      );
    }
    if (data.containsKey('ultima_ruta_id')) {
      context.handle(
        _ultimaRutaIdMeta,
        ultimaRutaId.isAcceptableOrUnknown(
          data['ultima_ruta_id']!,
          _ultimaRutaIdMeta,
        ),
      );
    }
    if (data.containsKey('price')) {
      context.handle(
        _priceMeta,
        price.isAcceptableOrUnknown(data['price']!, _priceMeta),
      );
    }
    if (data.containsKey('segment_km')) {
      context.handle(
        _segmentKmMeta,
        segmentKm.isAcceptableOrUnknown(data['segment_km']!, _segmentKmMeta),
      );
    }
    if (data.containsKey('delivery_price')) {
      context.handle(
        _deliveryPriceMeta,
        deliveryPrice.isAcceptableOrUnknown(
          data['delivery_price']!,
          _deliveryPriceMeta,
        ),
      );
    }
    if (data.containsKey('delivery_distance_km')) {
      context.handle(
        _deliveryDistanceKmMeta,
        deliveryDistanceKm.isAcceptableOrUnknown(
          data['delivery_distance_km']!,
          _deliveryDistanceKmMeta,
        ),
      );
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('external_id')) {
      context.handle(
        _externalIdMeta,
        externalId.isAcceptableOrUnknown(data['external_id']!, _externalIdMeta),
      );
    }
    if (data.containsKey('order_date')) {
      context.handle(
        _orderDateMeta,
        orderDate.isAcceptableOrUnknown(data['order_date']!, _orderDateMeta),
      );
    }
    if (data.containsKey('pedido_updated_at')) {
      context.handle(
        _pedidoUpdatedAtMeta,
        pedidoUpdatedAt.isAcceptableOrUnknown(
          data['pedido_updated_at']!,
          _pedidoUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('estado')) {
      context.handle(
        _estadoMeta,
        estado.isAcceptableOrUnknown(data['estado']!, _estadoMeta),
      );
    }
    if (data.containsKey('archivado')) {
      context.handle(
        _archivadoMeta,
        archivado.isAcceptableOrUnknown(data['archivado']!, _archivadoMeta),
      );
    }
    if (data.containsKey('fecha_comprometida')) {
      context.handle(
        _fechaComprometidaMeta,
        fechaComprometida.isAcceptableOrUnknown(
          data['fecha_comprometida']!,
          _fechaComprometidaMeta,
        ),
      );
    }
    if (data.containsKey('requiere_domicilio')) {
      context.handle(
        _requiereDomicilioMeta,
        requiereDomicilio.isAcceptableOrUnknown(
          data['requiere_domicilio']!,
          _requiereDomicilioMeta,
        ),
      );
    }
    if (data.containsKey('pedido_costo')) {
      context.handle(
        _pedidoCostoMeta,
        pedidoCosto.isAcceptableOrUnknown(
          data['pedido_costo']!,
          _pedidoCostoMeta,
        ),
      );
    }
    if (data.containsKey('municipio')) {
      context.handle(
        _municipioMeta,
        municipio.isAcceptableOrUnknown(data['municipio']!, _municipioMeta),
      );
    }
    if (data.containsKey('vendedor')) {
      context.handle(
        _vendedorMeta,
        vendedor.isAcceptableOrUnknown(data['vendedor']!, _vendedorMeta),
      );
    }
    if (data.containsKey('sucursal_codigo')) {
      context.handle(
        _sucursalCodigoMeta,
        sucursalCodigo.isAcceptableOrUnknown(
          data['sucursal_codigo']!,
          _sucursalCodigoMeta,
        ),
      );
    }
    if (data.containsKey('factura_estado')) {
      context.handle(
        _facturaEstadoMeta,
        facturaEstado.isAcceptableOrUnknown(
          data['factura_estado']!,
          _facturaEstadoMeta,
        ),
      );
    }
    if (data.containsKey('factura_numero')) {
      context.handle(
        _facturaNumeroMeta,
        facturaNumero.isAcceptableOrUnknown(
          data['factura_numero']!,
          _facturaNumeroMeta,
        ),
      );
    }
    if (data.containsKey('factura_at')) {
      context.handle(
        _facturaAtMeta,
        facturaAt.isAcceptableOrUnknown(data['factura_at']!, _facturaAtMeta),
      );
    }
    if (data.containsKey('factura_domicilio')) {
      context.handle(
        _facturaDomicilioMeta,
        facturaDomicilio.isAcceptableOrUnknown(
          data['factura_domicilio']!,
          _facturaDomicilioMeta,
        ),
      );
    }
    if (data.containsKey('factura_corregido_at')) {
      context.handle(
        _facturaCorregidoAtMeta,
        facturaCorregidoAt.isAcceptableOrUnknown(
          data['factura_corregido_at']!,
          _facturaCorregidoAtMeta,
        ),
      );
    }
    if (data.containsKey('items_origen')) {
      context.handle(
        _itemsOrigenMeta,
        itemsOrigen.isAcceptableOrUnknown(
          data['items_origen']!,
          _itemsOrigenMeta,
        ),
      );
    }
    if (data.containsKey('customer_phone')) {
      context.handle(
        _customerPhoneMeta,
        customerPhone.isAcceptableOrUnknown(
          data['customer_phone']!,
          _customerPhoneMeta,
        ),
      );
    }
    if (data.containsKey('stop_order')) {
      context.handle(
        _stopOrderMeta,
        stopOrder.isAcceptableOrUnknown(data['stop_order']!, _stopOrderMeta),
      );
    }
    if (data.containsKey('delivered_at')) {
      context.handle(
        _deliveredAtMeta,
        deliveredAt.isAcceptableOrUnknown(
          data['delivered_at']!,
          _deliveredAtMeta,
        ),
      );
    }
    if (data.containsKey('resultado')) {
      context.handle(
        _resultadoMeta,
        resultado.isAcceptableOrUnknown(data['resultado']!, _resultadoMeta),
      );
    }
    if (data.containsKey('resultado_at')) {
      context.handle(
        _resultadoAtMeta,
        resultadoAt.isAcceptableOrUnknown(
          data['resultado_at']!,
          _resultadoAtMeta,
        ),
      );
    }
    if (data.containsKey('resultado_nota')) {
      context.handle(
        _resultadoNotaMeta,
        resultadoNota.isAcceptableOrUnknown(
          data['resultado_nota']!,
          _resultadoNotaMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Pedido map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Pedido(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      operationNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_number'],
      ),
      customerName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_name'],
      )!,
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      )!,
      endAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_address'],
      ),
      endLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}end_lat'],
      ),
      endLng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}end_lng'],
      ),
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      ),
      lng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lng'],
      ),
      weight: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      tripLeg: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trip_leg'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      routeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route_id'],
      ),
      ultimaRutaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ultima_ruta_id'],
      ),
      price: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}price'],
      ),
      segmentKm: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}segment_km'],
      ),
      deliveryPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}delivery_price'],
      ),
      deliveryDistanceKm: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}delivery_distance_km'],
      ),
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      ),
      externalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}external_id'],
      ),
      orderDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}order_date'],
      ),
      pedidoUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}pedido_updated_at'],
      ),
      estado: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}estado'],
      ),
      archivado: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archivado'],
      )!,
      fechaComprometida: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fecha_comprometida'],
      ),
      requiereDomicilio: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}requiere_domicilio'],
      ),
      pedidoCosto: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pedido_costo'],
      ),
      municipio: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}municipio'],
      ),
      vendedor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vendedor'],
      ),
      sucursalCodigo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sucursal_codigo'],
      ),
      facturaEstado: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}factura_estado'],
      ),
      facturaNumero: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}factura_numero'],
      ),
      facturaAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}factura_at'],
      ),
      facturaDomicilio: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}factura_domicilio'],
      ),
      facturaCorregidoAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}factura_corregido_at'],
      ),
      itemsOrigen: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}items_origen'],
      ),
      customerPhone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_phone'],
      ),
      stopOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stop_order'],
      ),
      deliveredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}delivered_at'],
      ),
      resultado: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resultado'],
      ),
      resultadoAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}resultado_at'],
      ),
      resultadoNota: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resultado_nota'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $OrdersTable createAlias(String alias) {
    return $OrdersTable(attachedDatabase, alias);
  }
}

class Pedido extends DataClass implements Insertable<Pedido> {
  final String id;
  final String? operationNumber;
  final String customerName;
  final String address;
  final String? endAddress;
  final double? endLat;
  final double? endLng;
  final double? lat;
  final double? lng;
  final double weight;
  final String status;
  final String tripLeg;
  final String? notes;

  /// La ruta que lo lleva AHORA. Con esto puesto el pedido esta ocupado.
  final String? routeId;

  /// En que ruta VIAJO. Esto no se libera nunca — un devuelto suelta `routeId`
  /// pero CONSERVA `ultimaRutaId`, o desaparece de la hoja de lo que bajo del
  /// camion.
  final String? ultimaRutaId;
  final double? price;
  final double? segmentKm;
  final double? deliveryPrice;
  final double? deliveryDistanceKm;
  final String? branchId;
  final String? source;
  final String? externalId;

  /// La FECHA DEL PEDIDO en PEDIDO, que NO es `createdAt`.
  final DateTime? orderDate;
  final DateTime? pedidoUpdatedAt;
  final String? estado;
  final bool archivado;
  final DateTime? fechaComprometida;
  final bool? requiereDomicilio;

  /// El costo que le puso la APK de Entrega EN PEDIDO. En la pantalla es
  /// `Precio`. NO es `price` — confundirlos es cobrar uno por el otro.
  final double? pedidoCosto;
  final String? municipio;
  final String? vendedor;
  final String? sucursalCodigo;
  final String? facturaEstado;
  final String? facturaNumero;
  final DateTime? facturaAt;
  final double? facturaDomicilio;
  final DateTime? facturaCorregidoAt;

  /// DE DÓNDE SON LOS RENGLONES, EL PESO Y LAS UNIDADES: `factura` o `pedido`.
  ///
  /// Cuando un pedido se factura distinto de como se tomó, PEDIDO manda **las
  /// líneas de la factura** —descartando las que se pidieron y no se facturaron,
  /// para que nadie cargue un hueco—. O sea que lo que hay aquí YA es lo que
  /// sube al camión. Comprobado contra producción el 26/09/2026: en
  /// `PAT26-260923-1246` el vendedor tomó dos productos y la factura dice uno,
  /// y aquí hay un renglón con los 60 uds y los 24,194 kg de la factura.
  ///
  /// Lo que faltaba era DECIRLO. Salía «Cambió en la factura» y nada más, así
  /// que quien mira un número no sabe cuál de los dos tiene delante. Jose,
  /// 26/09/2026: «se facturó otra cosa, ese pedido ya no representa la cantidad
  /// total»; y cómo se resuelve: «mantenemos el pedido y sólo le añadimos una
  /// factura a ese pedido para saber si cambió o no».
  ///
  /// **Nulo es «no se sabe»**, y entonces la pantalla no dice nada. No se
  /// deduce de [facturaEstado]: un `cambiado` cuyo cotejo no pudo atar la
  /// factura a ESTE pedido se queda con las del pedido, y un `igual` también
  /// trae las de la factura. Son dos preguntas distintas.
  final String? itemsOrigen;
  final String? customerPhone;
  final int? stopOrder;
  final DateTime? deliveredAt;
  final String? resultado;
  final DateTime? resultadoAt;
  final String? resultadoNota;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const Pedido({
    required this.id,
    this.operationNumber,
    required this.customerName,
    required this.address,
    this.endAddress,
    this.endLat,
    this.endLng,
    this.lat,
    this.lng,
    required this.weight,
    required this.status,
    required this.tripLeg,
    this.notes,
    this.routeId,
    this.ultimaRutaId,
    this.price,
    this.segmentKm,
    this.deliveryPrice,
    this.deliveryDistanceKm,
    this.branchId,
    this.source,
    this.externalId,
    this.orderDate,
    this.pedidoUpdatedAt,
    this.estado,
    required this.archivado,
    this.fechaComprometida,
    this.requiereDomicilio,
    this.pedidoCosto,
    this.municipio,
    this.vendedor,
    this.sucursalCodigo,
    this.facturaEstado,
    this.facturaNumero,
    this.facturaAt,
    this.facturaDomicilio,
    this.facturaCorregidoAt,
    this.itemsOrigen,
    this.customerPhone,
    this.stopOrder,
    this.deliveredAt,
    this.resultado,
    this.resultadoAt,
    this.resultadoNota,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || operationNumber != null) {
      map['operation_number'] = Variable<String>(operationNumber);
    }
    map['customer_name'] = Variable<String>(customerName);
    map['address'] = Variable<String>(address);
    if (!nullToAbsent || endAddress != null) {
      map['end_address'] = Variable<String>(endAddress);
    }
    if (!nullToAbsent || endLat != null) {
      map['end_lat'] = Variable<double>(endLat);
    }
    if (!nullToAbsent || endLng != null) {
      map['end_lng'] = Variable<double>(endLng);
    }
    if (!nullToAbsent || lat != null) {
      map['lat'] = Variable<double>(lat);
    }
    if (!nullToAbsent || lng != null) {
      map['lng'] = Variable<double>(lng);
    }
    map['weight'] = Variable<double>(weight);
    map['status'] = Variable<String>(status);
    map['trip_leg'] = Variable<String>(tripLeg);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || routeId != null) {
      map['route_id'] = Variable<String>(routeId);
    }
    if (!nullToAbsent || ultimaRutaId != null) {
      map['ultima_ruta_id'] = Variable<String>(ultimaRutaId);
    }
    if (!nullToAbsent || price != null) {
      map['price'] = Variable<double>(price);
    }
    if (!nullToAbsent || segmentKm != null) {
      map['segment_km'] = Variable<double>(segmentKm);
    }
    if (!nullToAbsent || deliveryPrice != null) {
      map['delivery_price'] = Variable<double>(deliveryPrice);
    }
    if (!nullToAbsent || deliveryDistanceKm != null) {
      map['delivery_distance_km'] = Variable<double>(deliveryDistanceKm);
    }
    if (!nullToAbsent || branchId != null) {
      map['branch_id'] = Variable<String>(branchId);
    }
    if (!nullToAbsent || source != null) {
      map['source'] = Variable<String>(source);
    }
    if (!nullToAbsent || externalId != null) {
      map['external_id'] = Variable<String>(externalId);
    }
    if (!nullToAbsent || orderDate != null) {
      map['order_date'] = Variable<DateTime>(orderDate);
    }
    if (!nullToAbsent || pedidoUpdatedAt != null) {
      map['pedido_updated_at'] = Variable<DateTime>(pedidoUpdatedAt);
    }
    if (!nullToAbsent || estado != null) {
      map['estado'] = Variable<String>(estado);
    }
    map['archivado'] = Variable<bool>(archivado);
    if (!nullToAbsent || fechaComprometida != null) {
      map['fecha_comprometida'] = Variable<DateTime>(fechaComprometida);
    }
    if (!nullToAbsent || requiereDomicilio != null) {
      map['requiere_domicilio'] = Variable<bool>(requiereDomicilio);
    }
    if (!nullToAbsent || pedidoCosto != null) {
      map['pedido_costo'] = Variable<double>(pedidoCosto);
    }
    if (!nullToAbsent || municipio != null) {
      map['municipio'] = Variable<String>(municipio);
    }
    if (!nullToAbsent || vendedor != null) {
      map['vendedor'] = Variable<String>(vendedor);
    }
    if (!nullToAbsent || sucursalCodigo != null) {
      map['sucursal_codigo'] = Variable<String>(sucursalCodigo);
    }
    if (!nullToAbsent || facturaEstado != null) {
      map['factura_estado'] = Variable<String>(facturaEstado);
    }
    if (!nullToAbsent || facturaNumero != null) {
      map['factura_numero'] = Variable<String>(facturaNumero);
    }
    if (!nullToAbsent || facturaAt != null) {
      map['factura_at'] = Variable<DateTime>(facturaAt);
    }
    if (!nullToAbsent || facturaDomicilio != null) {
      map['factura_domicilio'] = Variable<double>(facturaDomicilio);
    }
    if (!nullToAbsent || facturaCorregidoAt != null) {
      map['factura_corregido_at'] = Variable<DateTime>(facturaCorregidoAt);
    }
    if (!nullToAbsent || itemsOrigen != null) {
      map['items_origen'] = Variable<String>(itemsOrigen);
    }
    if (!nullToAbsent || customerPhone != null) {
      map['customer_phone'] = Variable<String>(customerPhone);
    }
    if (!nullToAbsent || stopOrder != null) {
      map['stop_order'] = Variable<int>(stopOrder);
    }
    if (!nullToAbsent || deliveredAt != null) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt);
    }
    if (!nullToAbsent || resultado != null) {
      map['resultado'] = Variable<String>(resultado);
    }
    if (!nullToAbsent || resultadoAt != null) {
      map['resultado_at'] = Variable<DateTime>(resultadoAt);
    }
    if (!nullToAbsent || resultadoNota != null) {
      map['resultado_nota'] = Variable<String>(resultadoNota);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  OrdersCompanion toCompanion(bool nullToAbsent) {
    return OrdersCompanion(
      id: Value(id),
      operationNumber: operationNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(operationNumber),
      customerName: Value(customerName),
      address: Value(address),
      endAddress: endAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(endAddress),
      endLat: endLat == null && nullToAbsent
          ? const Value.absent()
          : Value(endLat),
      endLng: endLng == null && nullToAbsent
          ? const Value.absent()
          : Value(endLng),
      lat: lat == null && nullToAbsent ? const Value.absent() : Value(lat),
      lng: lng == null && nullToAbsent ? const Value.absent() : Value(lng),
      weight: Value(weight),
      status: Value(status),
      tripLeg: Value(tripLeg),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      routeId: routeId == null && nullToAbsent
          ? const Value.absent()
          : Value(routeId),
      ultimaRutaId: ultimaRutaId == null && nullToAbsent
          ? const Value.absent()
          : Value(ultimaRutaId),
      price: price == null && nullToAbsent
          ? const Value.absent()
          : Value(price),
      segmentKm: segmentKm == null && nullToAbsent
          ? const Value.absent()
          : Value(segmentKm),
      deliveryPrice: deliveryPrice == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveryPrice),
      deliveryDistanceKm: deliveryDistanceKm == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveryDistanceKm),
      branchId: branchId == null && nullToAbsent
          ? const Value.absent()
          : Value(branchId),
      source: source == null && nullToAbsent
          ? const Value.absent()
          : Value(source),
      externalId: externalId == null && nullToAbsent
          ? const Value.absent()
          : Value(externalId),
      orderDate: orderDate == null && nullToAbsent
          ? const Value.absent()
          : Value(orderDate),
      pedidoUpdatedAt: pedidoUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(pedidoUpdatedAt),
      estado: estado == null && nullToAbsent
          ? const Value.absent()
          : Value(estado),
      archivado: Value(archivado),
      fechaComprometida: fechaComprometida == null && nullToAbsent
          ? const Value.absent()
          : Value(fechaComprometida),
      requiereDomicilio: requiereDomicilio == null && nullToAbsent
          ? const Value.absent()
          : Value(requiereDomicilio),
      pedidoCosto: pedidoCosto == null && nullToAbsent
          ? const Value.absent()
          : Value(pedidoCosto),
      municipio: municipio == null && nullToAbsent
          ? const Value.absent()
          : Value(municipio),
      vendedor: vendedor == null && nullToAbsent
          ? const Value.absent()
          : Value(vendedor),
      sucursalCodigo: sucursalCodigo == null && nullToAbsent
          ? const Value.absent()
          : Value(sucursalCodigo),
      facturaEstado: facturaEstado == null && nullToAbsent
          ? const Value.absent()
          : Value(facturaEstado),
      facturaNumero: facturaNumero == null && nullToAbsent
          ? const Value.absent()
          : Value(facturaNumero),
      facturaAt: facturaAt == null && nullToAbsent
          ? const Value.absent()
          : Value(facturaAt),
      facturaDomicilio: facturaDomicilio == null && nullToAbsent
          ? const Value.absent()
          : Value(facturaDomicilio),
      facturaCorregidoAt: facturaCorregidoAt == null && nullToAbsent
          ? const Value.absent()
          : Value(facturaCorregidoAt),
      itemsOrigen: itemsOrigen == null && nullToAbsent
          ? const Value.absent()
          : Value(itemsOrigen),
      customerPhone: customerPhone == null && nullToAbsent
          ? const Value.absent()
          : Value(customerPhone),
      stopOrder: stopOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(stopOrder),
      deliveredAt: deliveredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveredAt),
      resultado: resultado == null && nullToAbsent
          ? const Value.absent()
          : Value(resultado),
      resultadoAt: resultadoAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resultadoAt),
      resultadoNota: resultadoNota == null && nullToAbsent
          ? const Value.absent()
          : Value(resultadoNota),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory Pedido.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Pedido(
      id: serializer.fromJson<String>(json['id']),
      operationNumber: serializer.fromJson<String?>(json['operationNumber']),
      customerName: serializer.fromJson<String>(json['customerName']),
      address: serializer.fromJson<String>(json['address']),
      endAddress: serializer.fromJson<String?>(json['endAddress']),
      endLat: serializer.fromJson<double?>(json['endLat']),
      endLng: serializer.fromJson<double?>(json['endLng']),
      lat: serializer.fromJson<double?>(json['lat']),
      lng: serializer.fromJson<double?>(json['lng']),
      weight: serializer.fromJson<double>(json['weight']),
      status: serializer.fromJson<String>(json['status']),
      tripLeg: serializer.fromJson<String>(json['tripLeg']),
      notes: serializer.fromJson<String?>(json['notes']),
      routeId: serializer.fromJson<String?>(json['routeId']),
      ultimaRutaId: serializer.fromJson<String?>(json['ultimaRutaId']),
      price: serializer.fromJson<double?>(json['price']),
      segmentKm: serializer.fromJson<double?>(json['segmentKm']),
      deliveryPrice: serializer.fromJson<double?>(json['deliveryPrice']),
      deliveryDistanceKm: serializer.fromJson<double?>(
        json['deliveryDistanceKm'],
      ),
      branchId: serializer.fromJson<String?>(json['branchId']),
      source: serializer.fromJson<String?>(json['source']),
      externalId: serializer.fromJson<String?>(json['externalId']),
      orderDate: serializer.fromJson<DateTime?>(json['orderDate']),
      pedidoUpdatedAt: serializer.fromJson<DateTime?>(json['pedidoUpdatedAt']),
      estado: serializer.fromJson<String?>(json['estado']),
      archivado: serializer.fromJson<bool>(json['archivado']),
      fechaComprometida: serializer.fromJson<DateTime?>(
        json['fechaComprometida'],
      ),
      requiereDomicilio: serializer.fromJson<bool?>(json['requiereDomicilio']),
      pedidoCosto: serializer.fromJson<double?>(json['pedidoCosto']),
      municipio: serializer.fromJson<String?>(json['municipio']),
      vendedor: serializer.fromJson<String?>(json['vendedor']),
      sucursalCodigo: serializer.fromJson<String?>(json['sucursalCodigo']),
      facturaEstado: serializer.fromJson<String?>(json['facturaEstado']),
      facturaNumero: serializer.fromJson<String?>(json['facturaNumero']),
      facturaAt: serializer.fromJson<DateTime?>(json['facturaAt']),
      facturaDomicilio: serializer.fromJson<double?>(json['facturaDomicilio']),
      facturaCorregidoAt: serializer.fromJson<DateTime?>(
        json['facturaCorregidoAt'],
      ),
      itemsOrigen: serializer.fromJson<String?>(json['itemsOrigen']),
      customerPhone: serializer.fromJson<String?>(json['customerPhone']),
      stopOrder: serializer.fromJson<int?>(json['stopOrder']),
      deliveredAt: serializer.fromJson<DateTime?>(json['deliveredAt']),
      resultado: serializer.fromJson<String?>(json['resultado']),
      resultadoAt: serializer.fromJson<DateTime?>(json['resultadoAt']),
      resultadoNota: serializer.fromJson<String?>(json['resultadoNota']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'operationNumber': serializer.toJson<String?>(operationNumber),
      'customerName': serializer.toJson<String>(customerName),
      'address': serializer.toJson<String>(address),
      'endAddress': serializer.toJson<String?>(endAddress),
      'endLat': serializer.toJson<double?>(endLat),
      'endLng': serializer.toJson<double?>(endLng),
      'lat': serializer.toJson<double?>(lat),
      'lng': serializer.toJson<double?>(lng),
      'weight': serializer.toJson<double>(weight),
      'status': serializer.toJson<String>(status),
      'tripLeg': serializer.toJson<String>(tripLeg),
      'notes': serializer.toJson<String?>(notes),
      'routeId': serializer.toJson<String?>(routeId),
      'ultimaRutaId': serializer.toJson<String?>(ultimaRutaId),
      'price': serializer.toJson<double?>(price),
      'segmentKm': serializer.toJson<double?>(segmentKm),
      'deliveryPrice': serializer.toJson<double?>(deliveryPrice),
      'deliveryDistanceKm': serializer.toJson<double?>(deliveryDistanceKm),
      'branchId': serializer.toJson<String?>(branchId),
      'source': serializer.toJson<String?>(source),
      'externalId': serializer.toJson<String?>(externalId),
      'orderDate': serializer.toJson<DateTime?>(orderDate),
      'pedidoUpdatedAt': serializer.toJson<DateTime?>(pedidoUpdatedAt),
      'estado': serializer.toJson<String?>(estado),
      'archivado': serializer.toJson<bool>(archivado),
      'fechaComprometida': serializer.toJson<DateTime?>(fechaComprometida),
      'requiereDomicilio': serializer.toJson<bool?>(requiereDomicilio),
      'pedidoCosto': serializer.toJson<double?>(pedidoCosto),
      'municipio': serializer.toJson<String?>(municipio),
      'vendedor': serializer.toJson<String?>(vendedor),
      'sucursalCodigo': serializer.toJson<String?>(sucursalCodigo),
      'facturaEstado': serializer.toJson<String?>(facturaEstado),
      'facturaNumero': serializer.toJson<String?>(facturaNumero),
      'facturaAt': serializer.toJson<DateTime?>(facturaAt),
      'facturaDomicilio': serializer.toJson<double?>(facturaDomicilio),
      'facturaCorregidoAt': serializer.toJson<DateTime?>(facturaCorregidoAt),
      'itemsOrigen': serializer.toJson<String?>(itemsOrigen),
      'customerPhone': serializer.toJson<String?>(customerPhone),
      'stopOrder': serializer.toJson<int?>(stopOrder),
      'deliveredAt': serializer.toJson<DateTime?>(deliveredAt),
      'resultado': serializer.toJson<String?>(resultado),
      'resultadoAt': serializer.toJson<DateTime?>(resultadoAt),
      'resultadoNota': serializer.toJson<String?>(resultadoNota),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  Pedido copyWith({
    String? id,
    Value<String?> operationNumber = const Value.absent(),
    String? customerName,
    String? address,
    Value<String?> endAddress = const Value.absent(),
    Value<double?> endLat = const Value.absent(),
    Value<double?> endLng = const Value.absent(),
    Value<double?> lat = const Value.absent(),
    Value<double?> lng = const Value.absent(),
    double? weight,
    String? status,
    String? tripLeg,
    Value<String?> notes = const Value.absent(),
    Value<String?> routeId = const Value.absent(),
    Value<String?> ultimaRutaId = const Value.absent(),
    Value<double?> price = const Value.absent(),
    Value<double?> segmentKm = const Value.absent(),
    Value<double?> deliveryPrice = const Value.absent(),
    Value<double?> deliveryDistanceKm = const Value.absent(),
    Value<String?> branchId = const Value.absent(),
    Value<String?> source = const Value.absent(),
    Value<String?> externalId = const Value.absent(),
    Value<DateTime?> orderDate = const Value.absent(),
    Value<DateTime?> pedidoUpdatedAt = const Value.absent(),
    Value<String?> estado = const Value.absent(),
    bool? archivado,
    Value<DateTime?> fechaComprometida = const Value.absent(),
    Value<bool?> requiereDomicilio = const Value.absent(),
    Value<double?> pedidoCosto = const Value.absent(),
    Value<String?> municipio = const Value.absent(),
    Value<String?> vendedor = const Value.absent(),
    Value<String?> sucursalCodigo = const Value.absent(),
    Value<String?> facturaEstado = const Value.absent(),
    Value<String?> facturaNumero = const Value.absent(),
    Value<DateTime?> facturaAt = const Value.absent(),
    Value<double?> facturaDomicilio = const Value.absent(),
    Value<DateTime?> facturaCorregidoAt = const Value.absent(),
    Value<String?> itemsOrigen = const Value.absent(),
    Value<String?> customerPhone = const Value.absent(),
    Value<int?> stopOrder = const Value.absent(),
    Value<DateTime?> deliveredAt = const Value.absent(),
    Value<String?> resultado = const Value.absent(),
    Value<DateTime?> resultadoAt = const Value.absent(),
    Value<String?> resultadoNota = const Value.absent(),
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => Pedido(
    id: id ?? this.id,
    operationNumber: operationNumber.present
        ? operationNumber.value
        : this.operationNumber,
    customerName: customerName ?? this.customerName,
    address: address ?? this.address,
    endAddress: endAddress.present ? endAddress.value : this.endAddress,
    endLat: endLat.present ? endLat.value : this.endLat,
    endLng: endLng.present ? endLng.value : this.endLng,
    lat: lat.present ? lat.value : this.lat,
    lng: lng.present ? lng.value : this.lng,
    weight: weight ?? this.weight,
    status: status ?? this.status,
    tripLeg: tripLeg ?? this.tripLeg,
    notes: notes.present ? notes.value : this.notes,
    routeId: routeId.present ? routeId.value : this.routeId,
    ultimaRutaId: ultimaRutaId.present ? ultimaRutaId.value : this.ultimaRutaId,
    price: price.present ? price.value : this.price,
    segmentKm: segmentKm.present ? segmentKm.value : this.segmentKm,
    deliveryPrice: deliveryPrice.present
        ? deliveryPrice.value
        : this.deliveryPrice,
    deliveryDistanceKm: deliveryDistanceKm.present
        ? deliveryDistanceKm.value
        : this.deliveryDistanceKm,
    branchId: branchId.present ? branchId.value : this.branchId,
    source: source.present ? source.value : this.source,
    externalId: externalId.present ? externalId.value : this.externalId,
    orderDate: orderDate.present ? orderDate.value : this.orderDate,
    pedidoUpdatedAt: pedidoUpdatedAt.present
        ? pedidoUpdatedAt.value
        : this.pedidoUpdatedAt,
    estado: estado.present ? estado.value : this.estado,
    archivado: archivado ?? this.archivado,
    fechaComprometida: fechaComprometida.present
        ? fechaComprometida.value
        : this.fechaComprometida,
    requiereDomicilio: requiereDomicilio.present
        ? requiereDomicilio.value
        : this.requiereDomicilio,
    pedidoCosto: pedidoCosto.present ? pedidoCosto.value : this.pedidoCosto,
    municipio: municipio.present ? municipio.value : this.municipio,
    vendedor: vendedor.present ? vendedor.value : this.vendedor,
    sucursalCodigo: sucursalCodigo.present
        ? sucursalCodigo.value
        : this.sucursalCodigo,
    facturaEstado: facturaEstado.present
        ? facturaEstado.value
        : this.facturaEstado,
    facturaNumero: facturaNumero.present
        ? facturaNumero.value
        : this.facturaNumero,
    facturaAt: facturaAt.present ? facturaAt.value : this.facturaAt,
    facturaDomicilio: facturaDomicilio.present
        ? facturaDomicilio.value
        : this.facturaDomicilio,
    facturaCorregidoAt: facturaCorregidoAt.present
        ? facturaCorregidoAt.value
        : this.facturaCorregidoAt,
    itemsOrigen: itemsOrigen.present ? itemsOrigen.value : this.itemsOrigen,
    customerPhone: customerPhone.present
        ? customerPhone.value
        : this.customerPhone,
    stopOrder: stopOrder.present ? stopOrder.value : this.stopOrder,
    deliveredAt: deliveredAt.present ? deliveredAt.value : this.deliveredAt,
    resultado: resultado.present ? resultado.value : this.resultado,
    resultadoAt: resultadoAt.present ? resultadoAt.value : this.resultadoAt,
    resultadoNota: resultadoNota.present
        ? resultadoNota.value
        : this.resultadoNota,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  Pedido copyWithCompanion(OrdersCompanion data) {
    return Pedido(
      id: data.id.present ? data.id.value : this.id,
      operationNumber: data.operationNumber.present
          ? data.operationNumber.value
          : this.operationNumber,
      customerName: data.customerName.present
          ? data.customerName.value
          : this.customerName,
      address: data.address.present ? data.address.value : this.address,
      endAddress: data.endAddress.present
          ? data.endAddress.value
          : this.endAddress,
      endLat: data.endLat.present ? data.endLat.value : this.endLat,
      endLng: data.endLng.present ? data.endLng.value : this.endLng,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      weight: data.weight.present ? data.weight.value : this.weight,
      status: data.status.present ? data.status.value : this.status,
      tripLeg: data.tripLeg.present ? data.tripLeg.value : this.tripLeg,
      notes: data.notes.present ? data.notes.value : this.notes,
      routeId: data.routeId.present ? data.routeId.value : this.routeId,
      ultimaRutaId: data.ultimaRutaId.present
          ? data.ultimaRutaId.value
          : this.ultimaRutaId,
      price: data.price.present ? data.price.value : this.price,
      segmentKm: data.segmentKm.present ? data.segmentKm.value : this.segmentKm,
      deliveryPrice: data.deliveryPrice.present
          ? data.deliveryPrice.value
          : this.deliveryPrice,
      deliveryDistanceKm: data.deliveryDistanceKm.present
          ? data.deliveryDistanceKm.value
          : this.deliveryDistanceKm,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      source: data.source.present ? data.source.value : this.source,
      externalId: data.externalId.present
          ? data.externalId.value
          : this.externalId,
      orderDate: data.orderDate.present ? data.orderDate.value : this.orderDate,
      pedidoUpdatedAt: data.pedidoUpdatedAt.present
          ? data.pedidoUpdatedAt.value
          : this.pedidoUpdatedAt,
      estado: data.estado.present ? data.estado.value : this.estado,
      archivado: data.archivado.present ? data.archivado.value : this.archivado,
      fechaComprometida: data.fechaComprometida.present
          ? data.fechaComprometida.value
          : this.fechaComprometida,
      requiereDomicilio: data.requiereDomicilio.present
          ? data.requiereDomicilio.value
          : this.requiereDomicilio,
      pedidoCosto: data.pedidoCosto.present
          ? data.pedidoCosto.value
          : this.pedidoCosto,
      municipio: data.municipio.present ? data.municipio.value : this.municipio,
      vendedor: data.vendedor.present ? data.vendedor.value : this.vendedor,
      sucursalCodigo: data.sucursalCodigo.present
          ? data.sucursalCodigo.value
          : this.sucursalCodigo,
      facturaEstado: data.facturaEstado.present
          ? data.facturaEstado.value
          : this.facturaEstado,
      facturaNumero: data.facturaNumero.present
          ? data.facturaNumero.value
          : this.facturaNumero,
      facturaAt: data.facturaAt.present ? data.facturaAt.value : this.facturaAt,
      facturaDomicilio: data.facturaDomicilio.present
          ? data.facturaDomicilio.value
          : this.facturaDomicilio,
      facturaCorregidoAt: data.facturaCorregidoAt.present
          ? data.facturaCorregidoAt.value
          : this.facturaCorregidoAt,
      itemsOrigen: data.itemsOrigen.present
          ? data.itemsOrigen.value
          : this.itemsOrigen,
      customerPhone: data.customerPhone.present
          ? data.customerPhone.value
          : this.customerPhone,
      stopOrder: data.stopOrder.present ? data.stopOrder.value : this.stopOrder,
      deliveredAt: data.deliveredAt.present
          ? data.deliveredAt.value
          : this.deliveredAt,
      resultado: data.resultado.present ? data.resultado.value : this.resultado,
      resultadoAt: data.resultadoAt.present
          ? data.resultadoAt.value
          : this.resultadoAt,
      resultadoNota: data.resultadoNota.present
          ? data.resultadoNota.value
          : this.resultadoNota,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Pedido(')
          ..write('id: $id, ')
          ..write('operationNumber: $operationNumber, ')
          ..write('customerName: $customerName, ')
          ..write('address: $address, ')
          ..write('endAddress: $endAddress, ')
          ..write('endLat: $endLat, ')
          ..write('endLng: $endLng, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('weight: $weight, ')
          ..write('status: $status, ')
          ..write('tripLeg: $tripLeg, ')
          ..write('notes: $notes, ')
          ..write('routeId: $routeId, ')
          ..write('ultimaRutaId: $ultimaRutaId, ')
          ..write('price: $price, ')
          ..write('segmentKm: $segmentKm, ')
          ..write('deliveryPrice: $deliveryPrice, ')
          ..write('deliveryDistanceKm: $deliveryDistanceKm, ')
          ..write('branchId: $branchId, ')
          ..write('source: $source, ')
          ..write('externalId: $externalId, ')
          ..write('orderDate: $orderDate, ')
          ..write('pedidoUpdatedAt: $pedidoUpdatedAt, ')
          ..write('estado: $estado, ')
          ..write('archivado: $archivado, ')
          ..write('fechaComprometida: $fechaComprometida, ')
          ..write('requiereDomicilio: $requiereDomicilio, ')
          ..write('pedidoCosto: $pedidoCosto, ')
          ..write('municipio: $municipio, ')
          ..write('vendedor: $vendedor, ')
          ..write('sucursalCodigo: $sucursalCodigo, ')
          ..write('facturaEstado: $facturaEstado, ')
          ..write('facturaNumero: $facturaNumero, ')
          ..write('facturaAt: $facturaAt, ')
          ..write('facturaDomicilio: $facturaDomicilio, ')
          ..write('facturaCorregidoAt: $facturaCorregidoAt, ')
          ..write('itemsOrigen: $itemsOrigen, ')
          ..write('customerPhone: $customerPhone, ')
          ..write('stopOrder: $stopOrder, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('resultado: $resultado, ')
          ..write('resultadoAt: $resultadoAt, ')
          ..write('resultadoNota: $resultadoNota, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    operationNumber,
    customerName,
    address,
    endAddress,
    endLat,
    endLng,
    lat,
    lng,
    weight,
    status,
    tripLeg,
    notes,
    routeId,
    ultimaRutaId,
    price,
    segmentKm,
    deliveryPrice,
    deliveryDistanceKm,
    branchId,
    source,
    externalId,
    orderDate,
    pedidoUpdatedAt,
    estado,
    archivado,
    fechaComprometida,
    requiereDomicilio,
    pedidoCosto,
    municipio,
    vendedor,
    sucursalCodigo,
    facturaEstado,
    facturaNumero,
    facturaAt,
    facturaDomicilio,
    facturaCorregidoAt,
    itemsOrigen,
    customerPhone,
    stopOrder,
    deliveredAt,
    resultado,
    resultadoAt,
    resultadoNota,
    createdAt,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Pedido &&
          other.id == this.id &&
          other.operationNumber == this.operationNumber &&
          other.customerName == this.customerName &&
          other.address == this.address &&
          other.endAddress == this.endAddress &&
          other.endLat == this.endLat &&
          other.endLng == this.endLng &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.weight == this.weight &&
          other.status == this.status &&
          other.tripLeg == this.tripLeg &&
          other.notes == this.notes &&
          other.routeId == this.routeId &&
          other.ultimaRutaId == this.ultimaRutaId &&
          other.price == this.price &&
          other.segmentKm == this.segmentKm &&
          other.deliveryPrice == this.deliveryPrice &&
          other.deliveryDistanceKm == this.deliveryDistanceKm &&
          other.branchId == this.branchId &&
          other.source == this.source &&
          other.externalId == this.externalId &&
          other.orderDate == this.orderDate &&
          other.pedidoUpdatedAt == this.pedidoUpdatedAt &&
          other.estado == this.estado &&
          other.archivado == this.archivado &&
          other.fechaComprometida == this.fechaComprometida &&
          other.requiereDomicilio == this.requiereDomicilio &&
          other.pedidoCosto == this.pedidoCosto &&
          other.municipio == this.municipio &&
          other.vendedor == this.vendedor &&
          other.sucursalCodigo == this.sucursalCodigo &&
          other.facturaEstado == this.facturaEstado &&
          other.facturaNumero == this.facturaNumero &&
          other.facturaAt == this.facturaAt &&
          other.facturaDomicilio == this.facturaDomicilio &&
          other.facturaCorregidoAt == this.facturaCorregidoAt &&
          other.itemsOrigen == this.itemsOrigen &&
          other.customerPhone == this.customerPhone &&
          other.stopOrder == this.stopOrder &&
          other.deliveredAt == this.deliveredAt &&
          other.resultado == this.resultado &&
          other.resultadoAt == this.resultadoAt &&
          other.resultadoNota == this.resultadoNota &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class OrdersCompanion extends UpdateCompanion<Pedido> {
  final Value<String> id;
  final Value<String?> operationNumber;
  final Value<String> customerName;
  final Value<String> address;
  final Value<String?> endAddress;
  final Value<double?> endLat;
  final Value<double?> endLng;
  final Value<double?> lat;
  final Value<double?> lng;
  final Value<double> weight;
  final Value<String> status;
  final Value<String> tripLeg;
  final Value<String?> notes;
  final Value<String?> routeId;
  final Value<String?> ultimaRutaId;
  final Value<double?> price;
  final Value<double?> segmentKm;
  final Value<double?> deliveryPrice;
  final Value<double?> deliveryDistanceKm;
  final Value<String?> branchId;
  final Value<String?> source;
  final Value<String?> externalId;
  final Value<DateTime?> orderDate;
  final Value<DateTime?> pedidoUpdatedAt;
  final Value<String?> estado;
  final Value<bool> archivado;
  final Value<DateTime?> fechaComprometida;
  final Value<bool?> requiereDomicilio;
  final Value<double?> pedidoCosto;
  final Value<String?> municipio;
  final Value<String?> vendedor;
  final Value<String?> sucursalCodigo;
  final Value<String?> facturaEstado;
  final Value<String?> facturaNumero;
  final Value<DateTime?> facturaAt;
  final Value<double?> facturaDomicilio;
  final Value<DateTime?> facturaCorregidoAt;
  final Value<String?> itemsOrigen;
  final Value<String?> customerPhone;
  final Value<int?> stopOrder;
  final Value<DateTime?> deliveredAt;
  final Value<String?> resultado;
  final Value<DateTime?> resultadoAt;
  final Value<String?> resultadoNota;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const OrdersCompanion({
    this.id = const Value.absent(),
    this.operationNumber = const Value.absent(),
    this.customerName = const Value.absent(),
    this.address = const Value.absent(),
    this.endAddress = const Value.absent(),
    this.endLat = const Value.absent(),
    this.endLng = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.weight = const Value.absent(),
    this.status = const Value.absent(),
    this.tripLeg = const Value.absent(),
    this.notes = const Value.absent(),
    this.routeId = const Value.absent(),
    this.ultimaRutaId = const Value.absent(),
    this.price = const Value.absent(),
    this.segmentKm = const Value.absent(),
    this.deliveryPrice = const Value.absent(),
    this.deliveryDistanceKm = const Value.absent(),
    this.branchId = const Value.absent(),
    this.source = const Value.absent(),
    this.externalId = const Value.absent(),
    this.orderDate = const Value.absent(),
    this.pedidoUpdatedAt = const Value.absent(),
    this.estado = const Value.absent(),
    this.archivado = const Value.absent(),
    this.fechaComprometida = const Value.absent(),
    this.requiereDomicilio = const Value.absent(),
    this.pedidoCosto = const Value.absent(),
    this.municipio = const Value.absent(),
    this.vendedor = const Value.absent(),
    this.sucursalCodigo = const Value.absent(),
    this.facturaEstado = const Value.absent(),
    this.facturaNumero = const Value.absent(),
    this.facturaAt = const Value.absent(),
    this.facturaDomicilio = const Value.absent(),
    this.facturaCorregidoAt = const Value.absent(),
    this.itemsOrigen = const Value.absent(),
    this.customerPhone = const Value.absent(),
    this.stopOrder = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.resultado = const Value.absent(),
    this.resultadoAt = const Value.absent(),
    this.resultadoNota = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OrdersCompanion.insert({
    required String id,
    this.operationNumber = const Value.absent(),
    required String customerName,
    required String address,
    this.endAddress = const Value.absent(),
    this.endLat = const Value.absent(),
    this.endLng = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.weight = const Value.absent(),
    this.status = const Value.absent(),
    this.tripLeg = const Value.absent(),
    this.notes = const Value.absent(),
    this.routeId = const Value.absent(),
    this.ultimaRutaId = const Value.absent(),
    this.price = const Value.absent(),
    this.segmentKm = const Value.absent(),
    this.deliveryPrice = const Value.absent(),
    this.deliveryDistanceKm = const Value.absent(),
    this.branchId = const Value.absent(),
    this.source = const Value.absent(),
    this.externalId = const Value.absent(),
    this.orderDate = const Value.absent(),
    this.pedidoUpdatedAt = const Value.absent(),
    this.estado = const Value.absent(),
    this.archivado = const Value.absent(),
    this.fechaComprometida = const Value.absent(),
    this.requiereDomicilio = const Value.absent(),
    this.pedidoCosto = const Value.absent(),
    this.municipio = const Value.absent(),
    this.vendedor = const Value.absent(),
    this.sucursalCodigo = const Value.absent(),
    this.facturaEstado = const Value.absent(),
    this.facturaNumero = const Value.absent(),
    this.facturaAt = const Value.absent(),
    this.facturaDomicilio = const Value.absent(),
    this.facturaCorregidoAt = const Value.absent(),
    this.itemsOrigen = const Value.absent(),
    this.customerPhone = const Value.absent(),
    this.stopOrder = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.resultado = const Value.absent(),
    this.resultadoAt = const Value.absent(),
    this.resultadoNota = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       customerName = Value(customerName),
       address = Value(address);
  static Insertable<Pedido> custom({
    Expression<String>? id,
    Expression<String>? operationNumber,
    Expression<String>? customerName,
    Expression<String>? address,
    Expression<String>? endAddress,
    Expression<double>? endLat,
    Expression<double>? endLng,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<double>? weight,
    Expression<String>? status,
    Expression<String>? tripLeg,
    Expression<String>? notes,
    Expression<String>? routeId,
    Expression<String>? ultimaRutaId,
    Expression<double>? price,
    Expression<double>? segmentKm,
    Expression<double>? deliveryPrice,
    Expression<double>? deliveryDistanceKm,
    Expression<String>? branchId,
    Expression<String>? source,
    Expression<String>? externalId,
    Expression<DateTime>? orderDate,
    Expression<DateTime>? pedidoUpdatedAt,
    Expression<String>? estado,
    Expression<bool>? archivado,
    Expression<DateTime>? fechaComprometida,
    Expression<bool>? requiereDomicilio,
    Expression<double>? pedidoCosto,
    Expression<String>? municipio,
    Expression<String>? vendedor,
    Expression<String>? sucursalCodigo,
    Expression<String>? facturaEstado,
    Expression<String>? facturaNumero,
    Expression<DateTime>? facturaAt,
    Expression<double>? facturaDomicilio,
    Expression<DateTime>? facturaCorregidoAt,
    Expression<String>? itemsOrigen,
    Expression<String>? customerPhone,
    Expression<int>? stopOrder,
    Expression<DateTime>? deliveredAt,
    Expression<String>? resultado,
    Expression<DateTime>? resultadoAt,
    Expression<String>? resultadoNota,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (operationNumber != null) 'operation_number': operationNumber,
      if (customerName != null) 'customer_name': customerName,
      if (address != null) 'address': address,
      if (endAddress != null) 'end_address': endAddress,
      if (endLat != null) 'end_lat': endLat,
      if (endLng != null) 'end_lng': endLng,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (weight != null) 'weight': weight,
      if (status != null) 'status': status,
      if (tripLeg != null) 'trip_leg': tripLeg,
      if (notes != null) 'notes': notes,
      if (routeId != null) 'route_id': routeId,
      if (ultimaRutaId != null) 'ultima_ruta_id': ultimaRutaId,
      if (price != null) 'price': price,
      if (segmentKm != null) 'segment_km': segmentKm,
      if (deliveryPrice != null) 'delivery_price': deliveryPrice,
      if (deliveryDistanceKm != null)
        'delivery_distance_km': deliveryDistanceKm,
      if (branchId != null) 'branch_id': branchId,
      if (source != null) 'source': source,
      if (externalId != null) 'external_id': externalId,
      if (orderDate != null) 'order_date': orderDate,
      if (pedidoUpdatedAt != null) 'pedido_updated_at': pedidoUpdatedAt,
      if (estado != null) 'estado': estado,
      if (archivado != null) 'archivado': archivado,
      if (fechaComprometida != null) 'fecha_comprometida': fechaComprometida,
      if (requiereDomicilio != null) 'requiere_domicilio': requiereDomicilio,
      if (pedidoCosto != null) 'pedido_costo': pedidoCosto,
      if (municipio != null) 'municipio': municipio,
      if (vendedor != null) 'vendedor': vendedor,
      if (sucursalCodigo != null) 'sucursal_codigo': sucursalCodigo,
      if (facturaEstado != null) 'factura_estado': facturaEstado,
      if (facturaNumero != null) 'factura_numero': facturaNumero,
      if (facturaAt != null) 'factura_at': facturaAt,
      if (facturaDomicilio != null) 'factura_domicilio': facturaDomicilio,
      if (facturaCorregidoAt != null)
        'factura_corregido_at': facturaCorregidoAt,
      if (itemsOrigen != null) 'items_origen': itemsOrigen,
      if (customerPhone != null) 'customer_phone': customerPhone,
      if (stopOrder != null) 'stop_order': stopOrder,
      if (deliveredAt != null) 'delivered_at': deliveredAt,
      if (resultado != null) 'resultado': resultado,
      if (resultadoAt != null) 'resultado_at': resultadoAt,
      if (resultadoNota != null) 'resultado_nota': resultadoNota,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OrdersCompanion copyWith({
    Value<String>? id,
    Value<String?>? operationNumber,
    Value<String>? customerName,
    Value<String>? address,
    Value<String?>? endAddress,
    Value<double?>? endLat,
    Value<double?>? endLng,
    Value<double?>? lat,
    Value<double?>? lng,
    Value<double>? weight,
    Value<String>? status,
    Value<String>? tripLeg,
    Value<String?>? notes,
    Value<String?>? routeId,
    Value<String?>? ultimaRutaId,
    Value<double?>? price,
    Value<double?>? segmentKm,
    Value<double?>? deliveryPrice,
    Value<double?>? deliveryDistanceKm,
    Value<String?>? branchId,
    Value<String?>? source,
    Value<String?>? externalId,
    Value<DateTime?>? orderDate,
    Value<DateTime?>? pedidoUpdatedAt,
    Value<String?>? estado,
    Value<bool>? archivado,
    Value<DateTime?>? fechaComprometida,
    Value<bool?>? requiereDomicilio,
    Value<double?>? pedidoCosto,
    Value<String?>? municipio,
    Value<String?>? vendedor,
    Value<String?>? sucursalCodigo,
    Value<String?>? facturaEstado,
    Value<String?>? facturaNumero,
    Value<DateTime?>? facturaAt,
    Value<double?>? facturaDomicilio,
    Value<DateTime?>? facturaCorregidoAt,
    Value<String?>? itemsOrigen,
    Value<String?>? customerPhone,
    Value<int?>? stopOrder,
    Value<DateTime?>? deliveredAt,
    Value<String?>? resultado,
    Value<DateTime?>? resultadoAt,
    Value<String?>? resultadoNota,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return OrdersCompanion(
      id: id ?? this.id,
      operationNumber: operationNumber ?? this.operationNumber,
      customerName: customerName ?? this.customerName,
      address: address ?? this.address,
      endAddress: endAddress ?? this.endAddress,
      endLat: endLat ?? this.endLat,
      endLng: endLng ?? this.endLng,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      weight: weight ?? this.weight,
      status: status ?? this.status,
      tripLeg: tripLeg ?? this.tripLeg,
      notes: notes ?? this.notes,
      routeId: routeId ?? this.routeId,
      ultimaRutaId: ultimaRutaId ?? this.ultimaRutaId,
      price: price ?? this.price,
      segmentKm: segmentKm ?? this.segmentKm,
      deliveryPrice: deliveryPrice ?? this.deliveryPrice,
      deliveryDistanceKm: deliveryDistanceKm ?? this.deliveryDistanceKm,
      branchId: branchId ?? this.branchId,
      source: source ?? this.source,
      externalId: externalId ?? this.externalId,
      orderDate: orderDate ?? this.orderDate,
      pedidoUpdatedAt: pedidoUpdatedAt ?? this.pedidoUpdatedAt,
      estado: estado ?? this.estado,
      archivado: archivado ?? this.archivado,
      fechaComprometida: fechaComprometida ?? this.fechaComprometida,
      requiereDomicilio: requiereDomicilio ?? this.requiereDomicilio,
      pedidoCosto: pedidoCosto ?? this.pedidoCosto,
      municipio: municipio ?? this.municipio,
      vendedor: vendedor ?? this.vendedor,
      sucursalCodigo: sucursalCodigo ?? this.sucursalCodigo,
      facturaEstado: facturaEstado ?? this.facturaEstado,
      facturaNumero: facturaNumero ?? this.facturaNumero,
      facturaAt: facturaAt ?? this.facturaAt,
      facturaDomicilio: facturaDomicilio ?? this.facturaDomicilio,
      facturaCorregidoAt: facturaCorregidoAt ?? this.facturaCorregidoAt,
      itemsOrigen: itemsOrigen ?? this.itemsOrigen,
      customerPhone: customerPhone ?? this.customerPhone,
      stopOrder: stopOrder ?? this.stopOrder,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      resultado: resultado ?? this.resultado,
      resultadoAt: resultadoAt ?? this.resultadoAt,
      resultadoNota: resultadoNota ?? this.resultadoNota,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (operationNumber.present) {
      map['operation_number'] = Variable<String>(operationNumber.value);
    }
    if (customerName.present) {
      map['customer_name'] = Variable<String>(customerName.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (endAddress.present) {
      map['end_address'] = Variable<String>(endAddress.value);
    }
    if (endLat.present) {
      map['end_lat'] = Variable<double>(endLat.value);
    }
    if (endLng.present) {
      map['end_lng'] = Variable<double>(endLng.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (weight.present) {
      map['weight'] = Variable<double>(weight.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (tripLeg.present) {
      map['trip_leg'] = Variable<String>(tripLeg.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (routeId.present) {
      map['route_id'] = Variable<String>(routeId.value);
    }
    if (ultimaRutaId.present) {
      map['ultima_ruta_id'] = Variable<String>(ultimaRutaId.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (segmentKm.present) {
      map['segment_km'] = Variable<double>(segmentKm.value);
    }
    if (deliveryPrice.present) {
      map['delivery_price'] = Variable<double>(deliveryPrice.value);
    }
    if (deliveryDistanceKm.present) {
      map['delivery_distance_km'] = Variable<double>(deliveryDistanceKm.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (externalId.present) {
      map['external_id'] = Variable<String>(externalId.value);
    }
    if (orderDate.present) {
      map['order_date'] = Variable<DateTime>(orderDate.value);
    }
    if (pedidoUpdatedAt.present) {
      map['pedido_updated_at'] = Variable<DateTime>(pedidoUpdatedAt.value);
    }
    if (estado.present) {
      map['estado'] = Variable<String>(estado.value);
    }
    if (archivado.present) {
      map['archivado'] = Variable<bool>(archivado.value);
    }
    if (fechaComprometida.present) {
      map['fecha_comprometida'] = Variable<DateTime>(fechaComprometida.value);
    }
    if (requiereDomicilio.present) {
      map['requiere_domicilio'] = Variable<bool>(requiereDomicilio.value);
    }
    if (pedidoCosto.present) {
      map['pedido_costo'] = Variable<double>(pedidoCosto.value);
    }
    if (municipio.present) {
      map['municipio'] = Variable<String>(municipio.value);
    }
    if (vendedor.present) {
      map['vendedor'] = Variable<String>(vendedor.value);
    }
    if (sucursalCodigo.present) {
      map['sucursal_codigo'] = Variable<String>(sucursalCodigo.value);
    }
    if (facturaEstado.present) {
      map['factura_estado'] = Variable<String>(facturaEstado.value);
    }
    if (facturaNumero.present) {
      map['factura_numero'] = Variable<String>(facturaNumero.value);
    }
    if (facturaAt.present) {
      map['factura_at'] = Variable<DateTime>(facturaAt.value);
    }
    if (facturaDomicilio.present) {
      map['factura_domicilio'] = Variable<double>(facturaDomicilio.value);
    }
    if (facturaCorregidoAt.present) {
      map['factura_corregido_at'] = Variable<DateTime>(
        facturaCorregidoAt.value,
      );
    }
    if (itemsOrigen.present) {
      map['items_origen'] = Variable<String>(itemsOrigen.value);
    }
    if (customerPhone.present) {
      map['customer_phone'] = Variable<String>(customerPhone.value);
    }
    if (stopOrder.present) {
      map['stop_order'] = Variable<int>(stopOrder.value);
    }
    if (deliveredAt.present) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt.value);
    }
    if (resultado.present) {
      map['resultado'] = Variable<String>(resultado.value);
    }
    if (resultadoAt.present) {
      map['resultado_at'] = Variable<DateTime>(resultadoAt.value);
    }
    if (resultadoNota.present) {
      map['resultado_nota'] = Variable<String>(resultadoNota.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OrdersCompanion(')
          ..write('id: $id, ')
          ..write('operationNumber: $operationNumber, ')
          ..write('customerName: $customerName, ')
          ..write('address: $address, ')
          ..write('endAddress: $endAddress, ')
          ..write('endLat: $endLat, ')
          ..write('endLng: $endLng, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('weight: $weight, ')
          ..write('status: $status, ')
          ..write('tripLeg: $tripLeg, ')
          ..write('notes: $notes, ')
          ..write('routeId: $routeId, ')
          ..write('ultimaRutaId: $ultimaRutaId, ')
          ..write('price: $price, ')
          ..write('segmentKm: $segmentKm, ')
          ..write('deliveryPrice: $deliveryPrice, ')
          ..write('deliveryDistanceKm: $deliveryDistanceKm, ')
          ..write('branchId: $branchId, ')
          ..write('source: $source, ')
          ..write('externalId: $externalId, ')
          ..write('orderDate: $orderDate, ')
          ..write('pedidoUpdatedAt: $pedidoUpdatedAt, ')
          ..write('estado: $estado, ')
          ..write('archivado: $archivado, ')
          ..write('fechaComprometida: $fechaComprometida, ')
          ..write('requiereDomicilio: $requiereDomicilio, ')
          ..write('pedidoCosto: $pedidoCosto, ')
          ..write('municipio: $municipio, ')
          ..write('vendedor: $vendedor, ')
          ..write('sucursalCodigo: $sucursalCodigo, ')
          ..write('facturaEstado: $facturaEstado, ')
          ..write('facturaNumero: $facturaNumero, ')
          ..write('facturaAt: $facturaAt, ')
          ..write('facturaDomicilio: $facturaDomicilio, ')
          ..write('facturaCorregidoAt: $facturaCorregidoAt, ')
          ..write('itemsOrigen: $itemsOrigen, ')
          ..write('customerPhone: $customerPhone, ')
          ..write('stopOrder: $stopOrder, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('resultado: $resultado, ')
          ..write('resultadoAt: $resultadoAt, ')
          ..write('resultadoNota: $resultadoNota, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OrderItemsTable extends OrderItems
    with TableInfo<$OrderItemsTable, RenglonPedido> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OrderItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderIdMeta = const VerificationMeta(
    'orderId',
  );
  @override
  late final GeneratedColumn<String> orderId = GeneratedColumn<String>(
    'order_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lineaMeta = const VerificationMeta('linea');
  @override
  late final GeneratedColumn<int> linea = GeneratedColumn<int>(
    'linea',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<double> quantity = GeneratedColumn<double>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _packsMeta = const VerificationMeta('packs');
  @override
  late final GeneratedColumn<double> packs = GeneratedColumn<double>(
    'packs',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pesoKgMeta = const VerificationMeta('pesoKg');
  @override
  late final GeneratedColumn<double> pesoKg = GeneratedColumn<double>(
    'peso_kg',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pesoLineaKgMeta = const VerificationMeta(
    'pesoLineaKg',
  );
  @override
  late final GeneratedColumn<double> pesoLineaKg = GeneratedColumn<double>(
    'peso_linea_kg',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orderId,
    linea,
    description,
    quantity,
    packs,
    pesoKg,
    pesoLineaKg,
    productId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'order_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<RenglonPedido> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('order_id')) {
      context.handle(
        _orderIdMeta,
        orderId.isAcceptableOrUnknown(data['order_id']!, _orderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orderIdMeta);
    }
    if (data.containsKey('linea')) {
      context.handle(
        _lineaMeta,
        linea.isAcceptableOrUnknown(data['linea']!, _lineaMeta),
      );
    } else if (isInserting) {
      context.missing(_lineaMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('packs')) {
      context.handle(
        _packsMeta,
        packs.isAcceptableOrUnknown(data['packs']!, _packsMeta),
      );
    }
    if (data.containsKey('peso_kg')) {
      context.handle(
        _pesoKgMeta,
        pesoKg.isAcceptableOrUnknown(data['peso_kg']!, _pesoKgMeta),
      );
    }
    if (data.containsKey('peso_linea_kg')) {
      context.handle(
        _pesoLineaKgMeta,
        pesoLineaKg.isAcceptableOrUnknown(
          data['peso_linea_kg']!,
          _pesoLineaKgMeta,
        ),
      );
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RenglonPedido map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RenglonPedido(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_id'],
      )!,
      linea: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}linea'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}quantity'],
      )!,
      packs: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}packs'],
      ),
      pesoKg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}peso_kg'],
      ),
      pesoLineaKg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}peso_linea_kg'],
      ),
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $OrderItemsTable createAlias(String alias) {
    return $OrderItemsTable(attachedDatabase, alias);
  }
}

class RenglonPedido extends DataClass implements Insertable<RenglonPedido> {
  final String id;
  final String orderId;
  final int linea;
  final String description;
  final double quantity;

  /// Los bultos, cuando la factura los distingue de las unidades. El numero de
  /// una linea son sus `packs` y si no los trae sus `quantity`, nunca cero
  /// (reglas-negocio §12).
  final double? packs;

  /// Lo que pesa UN empaque, tal como quedo cuando el pedido entro.
  ///
  /// **ES CONSTANCIA, NO UN ESCALON DEL PESO** — 28/09/2026. El aparato no
  /// calcula con esto: la cascada del peso corre UNA vez, en el servidor
  /// (`PesosDeRenglones`, `api/internal/cotizar/pesos.go`), y lo que se lee es
  /// [pesoLineaKg]. Esta columna se guarda porque es el dato con el que se
  /// facturo —para eso la puso la `00004_peso_por_renglon.sql`— y porque es lo
  /// que permite comprobar despues de donde salio un kilo.
  ///
  /// SON DOS COLUMNAS Y CON NOMBRES DISTINTOS A PROPOSITO: esta es la de un
  /// empaque y [pesoLineaKg] la de la linea entera. Guardar solo la primera
  /// llamandola «el peso» es pedir que alguien se acuerde de multiplicar por los
  /// empaques, y el dia que se olvide el camion sale dividido entre treinta sin
  /// que falle nada.
  ///
  /// HASTA EL 26/09/2026 NO EXISTIAN, y la ficha resolvia el peso contra el
  /// CATALOGO LOCAL. Lo que se veia: un renglon diciendo «sin peso» mientras el
  /// total del mismo pedido decia 72,6 kg, y el pre-despacho —la hoja con la que
  /// se carga el camion— con las catorce filas en raya y «sin peso en el
  /// catalogo» encima de 7.446 empaques. Inservible.
  ///
  /// El peso no es del catalogo de hoy: es el que tenia la mercancia cuando se
  /// facturo. Un producto que hoy no este en el catalogo de esa sucursal no
  /// tiene por que perderlo.
  ///
  /// `null` = **no se sabe**, y la pantalla lo dice con esas palabras. No es
  /// cero: un cero se suma, se ordena y se lee como «no pesa nada».
  final double? pesoKg;

  /// Lo que pesa la LINEA entera. Ver [pesoKg].
  final double? pesoLineaKg;
  final String? productId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const RenglonPedido({
    required this.id,
    required this.orderId,
    required this.linea,
    required this.description,
    required this.quantity,
    this.packs,
    this.pesoKg,
    this.pesoLineaKg,
    this.productId,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['order_id'] = Variable<String>(orderId);
    map['linea'] = Variable<int>(linea);
    map['description'] = Variable<String>(description);
    map['quantity'] = Variable<double>(quantity);
    if (!nullToAbsent || packs != null) {
      map['packs'] = Variable<double>(packs);
    }
    if (!nullToAbsent || pesoKg != null) {
      map['peso_kg'] = Variable<double>(pesoKg);
    }
    if (!nullToAbsent || pesoLineaKg != null) {
      map['peso_linea_kg'] = Variable<double>(pesoLineaKg);
    }
    if (!nullToAbsent || productId != null) {
      map['product_id'] = Variable<String>(productId);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  OrderItemsCompanion toCompanion(bool nullToAbsent) {
    return OrderItemsCompanion(
      id: Value(id),
      orderId: Value(orderId),
      linea: Value(linea),
      description: Value(description),
      quantity: Value(quantity),
      packs: packs == null && nullToAbsent
          ? const Value.absent()
          : Value(packs),
      pesoKg: pesoKg == null && nullToAbsent
          ? const Value.absent()
          : Value(pesoKg),
      pesoLineaKg: pesoLineaKg == null && nullToAbsent
          ? const Value.absent()
          : Value(pesoLineaKg),
      productId: productId == null && nullToAbsent
          ? const Value.absent()
          : Value(productId),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory RenglonPedido.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RenglonPedido(
      id: serializer.fromJson<String>(json['id']),
      orderId: serializer.fromJson<String>(json['orderId']),
      linea: serializer.fromJson<int>(json['linea']),
      description: serializer.fromJson<String>(json['description']),
      quantity: serializer.fromJson<double>(json['quantity']),
      packs: serializer.fromJson<double?>(json['packs']),
      pesoKg: serializer.fromJson<double?>(json['pesoKg']),
      pesoLineaKg: serializer.fromJson<double?>(json['pesoLineaKg']),
      productId: serializer.fromJson<String?>(json['productId']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orderId': serializer.toJson<String>(orderId),
      'linea': serializer.toJson<int>(linea),
      'description': serializer.toJson<String>(description),
      'quantity': serializer.toJson<double>(quantity),
      'packs': serializer.toJson<double?>(packs),
      'pesoKg': serializer.toJson<double?>(pesoKg),
      'pesoLineaKg': serializer.toJson<double?>(pesoLineaKg),
      'productId': serializer.toJson<String?>(productId),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  RenglonPedido copyWith({
    String? id,
    String? orderId,
    int? linea,
    String? description,
    double? quantity,
    Value<double?> packs = const Value.absent(),
    Value<double?> pesoKg = const Value.absent(),
    Value<double?> pesoLineaKg = const Value.absent(),
    Value<String?> productId = const Value.absent(),
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => RenglonPedido(
    id: id ?? this.id,
    orderId: orderId ?? this.orderId,
    linea: linea ?? this.linea,
    description: description ?? this.description,
    quantity: quantity ?? this.quantity,
    packs: packs.present ? packs.value : this.packs,
    pesoKg: pesoKg.present ? pesoKg.value : this.pesoKg,
    pesoLineaKg: pesoLineaKg.present ? pesoLineaKg.value : this.pesoLineaKg,
    productId: productId.present ? productId.value : this.productId,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  RenglonPedido copyWithCompanion(OrderItemsCompanion data) {
    return RenglonPedido(
      id: data.id.present ? data.id.value : this.id,
      orderId: data.orderId.present ? data.orderId.value : this.orderId,
      linea: data.linea.present ? data.linea.value : this.linea,
      description: data.description.present
          ? data.description.value
          : this.description,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      packs: data.packs.present ? data.packs.value : this.packs,
      pesoKg: data.pesoKg.present ? data.pesoKg.value : this.pesoKg,
      pesoLineaKg: data.pesoLineaKg.present
          ? data.pesoLineaKg.value
          : this.pesoLineaKg,
      productId: data.productId.present ? data.productId.value : this.productId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RenglonPedido(')
          ..write('id: $id, ')
          ..write('orderId: $orderId, ')
          ..write('linea: $linea, ')
          ..write('description: $description, ')
          ..write('quantity: $quantity, ')
          ..write('packs: $packs, ')
          ..write('pesoKg: $pesoKg, ')
          ..write('pesoLineaKg: $pesoLineaKg, ')
          ..write('productId: $productId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orderId,
    linea,
    description,
    quantity,
    packs,
    pesoKg,
    pesoLineaKg,
    productId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RenglonPedido &&
          other.id == this.id &&
          other.orderId == this.orderId &&
          other.linea == this.linea &&
          other.description == this.description &&
          other.quantity == this.quantity &&
          other.packs == this.packs &&
          other.pesoKg == this.pesoKg &&
          other.pesoLineaKg == this.pesoLineaKg &&
          other.productId == this.productId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class OrderItemsCompanion extends UpdateCompanion<RenglonPedido> {
  final Value<String> id;
  final Value<String> orderId;
  final Value<int> linea;
  final Value<String> description;
  final Value<double> quantity;
  final Value<double?> packs;
  final Value<double?> pesoKg;
  final Value<double?> pesoLineaKg;
  final Value<String?> productId;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const OrderItemsCompanion({
    this.id = const Value.absent(),
    this.orderId = const Value.absent(),
    this.linea = const Value.absent(),
    this.description = const Value.absent(),
    this.quantity = const Value.absent(),
    this.packs = const Value.absent(),
    this.pesoKg = const Value.absent(),
    this.pesoLineaKg = const Value.absent(),
    this.productId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OrderItemsCompanion.insert({
    required String id,
    required String orderId,
    required int linea,
    required String description,
    required double quantity,
    this.packs = const Value.absent(),
    this.pesoKg = const Value.absent(),
    this.pesoLineaKg = const Value.absent(),
    this.productId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orderId = Value(orderId),
       linea = Value(linea),
       description = Value(description),
       quantity = Value(quantity);
  static Insertable<RenglonPedido> custom({
    Expression<String>? id,
    Expression<String>? orderId,
    Expression<int>? linea,
    Expression<String>? description,
    Expression<double>? quantity,
    Expression<double>? packs,
    Expression<double>? pesoKg,
    Expression<double>? pesoLineaKg,
    Expression<String>? productId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orderId != null) 'order_id': orderId,
      if (linea != null) 'linea': linea,
      if (description != null) 'description': description,
      if (quantity != null) 'quantity': quantity,
      if (packs != null) 'packs': packs,
      if (pesoKg != null) 'peso_kg': pesoKg,
      if (pesoLineaKg != null) 'peso_linea_kg': pesoLineaKg,
      if (productId != null) 'product_id': productId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OrderItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? orderId,
    Value<int>? linea,
    Value<String>? description,
    Value<double>? quantity,
    Value<double?>? packs,
    Value<double?>? pesoKg,
    Value<double?>? pesoLineaKg,
    Value<String?>? productId,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return OrderItemsCompanion(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      linea: linea ?? this.linea,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      packs: packs ?? this.packs,
      pesoKg: pesoKg ?? this.pesoKg,
      pesoLineaKg: pesoLineaKg ?? this.pesoLineaKg,
      productId: productId ?? this.productId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orderId.present) {
      map['order_id'] = Variable<String>(orderId.value);
    }
    if (linea.present) {
      map['linea'] = Variable<int>(linea.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<double>(quantity.value);
    }
    if (packs.present) {
      map['packs'] = Variable<double>(packs.value);
    }
    if (pesoKg.present) {
      map['peso_kg'] = Variable<double>(pesoKg.value);
    }
    if (pesoLineaKg.present) {
      map['peso_linea_kg'] = Variable<double>(pesoLineaKg.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OrderItemsCompanion(')
          ..write('id: $id, ')
          ..write('orderId: $orderId, ')
          ..write('linea: $linea, ')
          ..write('description: $description, ')
          ..write('quantity: $quantity, ')
          ..write('packs: $packs, ')
          ..write('pesoKg: $pesoKg, ')
          ..write('pesoLineaKg: $pesoLineaKg, ')
          ..write('productId: $productId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RoutesTable extends Routes with TableInfo<$RoutesTable, Ruta> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoutesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _routeCodeMeta = const VerificationMeta(
    'routeCode',
  );
  @override
  late final GeneratedColumn<String> routeCode = GeneratedColumn<String>(
    'route_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('planned'),
  );
  static const VerificationMeta _originAddressMeta = const VerificationMeta(
    'originAddress',
  );
  @override
  late final GeneratedColumn<String> originAddress = GeneratedColumn<String>(
    'origin_address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originLatMeta = const VerificationMeta(
    'originLat',
  );
  @override
  late final GeneratedColumn<double> originLat = GeneratedColumn<double>(
    'origin_lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originLngMeta = const VerificationMeta(
    'originLng',
  );
  @override
  late final GeneratedColumn<double> originLng = GeneratedColumn<double>(
    'origin_lng',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalDistanceMeta = const VerificationMeta(
    'totalDistance',
  );
  @override
  late final GeneratedColumn<double> totalDistance = GeneratedColumn<double>(
    'total_distance',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalWeightMeta = const VerificationMeta(
    'totalWeight',
  );
  @override
  late final GeneratedColumn<double> totalWeight = GeneratedColumn<double>(
    'total_weight',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalPriceMeta = const VerificationMeta(
    'totalPrice',
  );
  @override
  late final GeneratedColumn<double> totalPrice = GeneratedColumn<double>(
    'total_price',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deliveryDateMeta = const VerificationMeta(
    'deliveryDate',
  );
  @override
  late final GeneratedColumn<DateTime> deliveryDate = GeneratedColumn<DateTime>(
    'delivery_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vehicleIdMeta = const VerificationMeta(
    'vehicleId',
  );
  @override
  late final GeneratedColumn<String> vehicleId = GeneratedColumn<String>(
    'vehicle_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _creadoPorMeta = const VerificationMeta(
    'creadoPor',
  );
  @override
  late final GeneratedColumn<String> creadoPor = GeneratedColumn<String>(
    'creado_por',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _finishedAtMeta = const VerificationMeta(
    'finishedAt',
  );
  @override
  late final GeneratedColumn<DateTime> finishedAt = GeneratedColumn<DateTime>(
    'finished_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _optimizedMeta = const VerificationMeta(
    'optimized',
  );
  @override
  late final GeneratedColumn<bool> optimized = GeneratedColumn<bool>(
    'optimized',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("optimized" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    routeCode,
    status,
    originAddress,
    originLat,
    originLng,
    totalDistance,
    totalWeight,
    totalPrice,
    deliveryDate,
    vehicleId,
    creadoPor,
    branchId,
    startedAt,
    finishedAt,
    optimized,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'routes';
  @override
  VerificationContext validateIntegrity(
    Insertable<Ruta> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('route_code')) {
      context.handle(
        _routeCodeMeta,
        routeCode.isAcceptableOrUnknown(data['route_code']!, _routeCodeMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('origin_address')) {
      context.handle(
        _originAddressMeta,
        originAddress.isAcceptableOrUnknown(
          data['origin_address']!,
          _originAddressMeta,
        ),
      );
    }
    if (data.containsKey('origin_lat')) {
      context.handle(
        _originLatMeta,
        originLat.isAcceptableOrUnknown(data['origin_lat']!, _originLatMeta),
      );
    }
    if (data.containsKey('origin_lng')) {
      context.handle(
        _originLngMeta,
        originLng.isAcceptableOrUnknown(data['origin_lng']!, _originLngMeta),
      );
    }
    if (data.containsKey('total_distance')) {
      context.handle(
        _totalDistanceMeta,
        totalDistance.isAcceptableOrUnknown(
          data['total_distance']!,
          _totalDistanceMeta,
        ),
      );
    }
    if (data.containsKey('total_weight')) {
      context.handle(
        _totalWeightMeta,
        totalWeight.isAcceptableOrUnknown(
          data['total_weight']!,
          _totalWeightMeta,
        ),
      );
    }
    if (data.containsKey('total_price')) {
      context.handle(
        _totalPriceMeta,
        totalPrice.isAcceptableOrUnknown(data['total_price']!, _totalPriceMeta),
      );
    }
    if (data.containsKey('delivery_date')) {
      context.handle(
        _deliveryDateMeta,
        deliveryDate.isAcceptableOrUnknown(
          data['delivery_date']!,
          _deliveryDateMeta,
        ),
      );
    }
    if (data.containsKey('vehicle_id')) {
      context.handle(
        _vehicleIdMeta,
        vehicleId.isAcceptableOrUnknown(data['vehicle_id']!, _vehicleIdMeta),
      );
    }
    if (data.containsKey('creado_por')) {
      context.handle(
        _creadoPorMeta,
        creadoPor.isAcceptableOrUnknown(data['creado_por']!, _creadoPorMeta),
      );
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('finished_at')) {
      context.handle(
        _finishedAtMeta,
        finishedAt.isAcceptableOrUnknown(data['finished_at']!, _finishedAtMeta),
      );
    }
    if (data.containsKey('optimized')) {
      context.handle(
        _optimizedMeta,
        optimized.isAcceptableOrUnknown(data['optimized']!, _optimizedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Ruta map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Ruta(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      routeCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route_code'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      originAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_address'],
      ),
      originLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}origin_lat'],
      ),
      originLng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}origin_lng'],
      ),
      totalDistance: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_distance'],
      )!,
      totalWeight: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_weight'],
      )!,
      totalPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_price'],
      )!,
      deliveryDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}delivery_date'],
      ),
      vehicleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vehicle_id'],
      ),
      creadoPor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}creado_por'],
      ),
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      ),
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      ),
      finishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}finished_at'],
      ),
      optimized: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}optimized'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $RoutesTable createAlias(String alias) {
    return $RoutesTable(attachedDatabase, alias);
  }
}

class Ruta extends DataClass implements Insertable<Ruta> {
  final String id;
  final String? name;
  final String? routeCode;
  final String status;
  final String? originAddress;
  final double? originLat;
  final double? originLng;
  final double totalDistance;
  final double totalWeight;
  final double totalPrice;
  final DateTime? deliveryDate;
  final String? vehicleId;
  final String? creadoPor;
  final String? branchId;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final bool optimized;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const Ruta({
    required this.id,
    this.name,
    this.routeCode,
    required this.status,
    this.originAddress,
    this.originLat,
    this.originLng,
    required this.totalDistance,
    required this.totalWeight,
    required this.totalPrice,
    this.deliveryDate,
    this.vehicleId,
    this.creadoPor,
    this.branchId,
    this.startedAt,
    this.finishedAt,
    required this.optimized,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || routeCode != null) {
      map['route_code'] = Variable<String>(routeCode);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || originAddress != null) {
      map['origin_address'] = Variable<String>(originAddress);
    }
    if (!nullToAbsent || originLat != null) {
      map['origin_lat'] = Variable<double>(originLat);
    }
    if (!nullToAbsent || originLng != null) {
      map['origin_lng'] = Variable<double>(originLng);
    }
    map['total_distance'] = Variable<double>(totalDistance);
    map['total_weight'] = Variable<double>(totalWeight);
    map['total_price'] = Variable<double>(totalPrice);
    if (!nullToAbsent || deliveryDate != null) {
      map['delivery_date'] = Variable<DateTime>(deliveryDate);
    }
    if (!nullToAbsent || vehicleId != null) {
      map['vehicle_id'] = Variable<String>(vehicleId);
    }
    if (!nullToAbsent || creadoPor != null) {
      map['creado_por'] = Variable<String>(creadoPor);
    }
    if (!nullToAbsent || branchId != null) {
      map['branch_id'] = Variable<String>(branchId);
    }
    if (!nullToAbsent || startedAt != null) {
      map['started_at'] = Variable<DateTime>(startedAt);
    }
    if (!nullToAbsent || finishedAt != null) {
      map['finished_at'] = Variable<DateTime>(finishedAt);
    }
    map['optimized'] = Variable<bool>(optimized);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  RoutesCompanion toCompanion(bool nullToAbsent) {
    return RoutesCompanion(
      id: Value(id),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      routeCode: routeCode == null && nullToAbsent
          ? const Value.absent()
          : Value(routeCode),
      status: Value(status),
      originAddress: originAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(originAddress),
      originLat: originLat == null && nullToAbsent
          ? const Value.absent()
          : Value(originLat),
      originLng: originLng == null && nullToAbsent
          ? const Value.absent()
          : Value(originLng),
      totalDistance: Value(totalDistance),
      totalWeight: Value(totalWeight),
      totalPrice: Value(totalPrice),
      deliveryDate: deliveryDate == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveryDate),
      vehicleId: vehicleId == null && nullToAbsent
          ? const Value.absent()
          : Value(vehicleId),
      creadoPor: creadoPor == null && nullToAbsent
          ? const Value.absent()
          : Value(creadoPor),
      branchId: branchId == null && nullToAbsent
          ? const Value.absent()
          : Value(branchId),
      startedAt: startedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startedAt),
      finishedAt: finishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(finishedAt),
      optimized: Value(optimized),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory Ruta.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Ruta(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String?>(json['name']),
      routeCode: serializer.fromJson<String?>(json['routeCode']),
      status: serializer.fromJson<String>(json['status']),
      originAddress: serializer.fromJson<String?>(json['originAddress']),
      originLat: serializer.fromJson<double?>(json['originLat']),
      originLng: serializer.fromJson<double?>(json['originLng']),
      totalDistance: serializer.fromJson<double>(json['totalDistance']),
      totalWeight: serializer.fromJson<double>(json['totalWeight']),
      totalPrice: serializer.fromJson<double>(json['totalPrice']),
      deliveryDate: serializer.fromJson<DateTime?>(json['deliveryDate']),
      vehicleId: serializer.fromJson<String?>(json['vehicleId']),
      creadoPor: serializer.fromJson<String?>(json['creadoPor']),
      branchId: serializer.fromJson<String?>(json['branchId']),
      startedAt: serializer.fromJson<DateTime?>(json['startedAt']),
      finishedAt: serializer.fromJson<DateTime?>(json['finishedAt']),
      optimized: serializer.fromJson<bool>(json['optimized']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String?>(name),
      'routeCode': serializer.toJson<String?>(routeCode),
      'status': serializer.toJson<String>(status),
      'originAddress': serializer.toJson<String?>(originAddress),
      'originLat': serializer.toJson<double?>(originLat),
      'originLng': serializer.toJson<double?>(originLng),
      'totalDistance': serializer.toJson<double>(totalDistance),
      'totalWeight': serializer.toJson<double>(totalWeight),
      'totalPrice': serializer.toJson<double>(totalPrice),
      'deliveryDate': serializer.toJson<DateTime?>(deliveryDate),
      'vehicleId': serializer.toJson<String?>(vehicleId),
      'creadoPor': serializer.toJson<String?>(creadoPor),
      'branchId': serializer.toJson<String?>(branchId),
      'startedAt': serializer.toJson<DateTime?>(startedAt),
      'finishedAt': serializer.toJson<DateTime?>(finishedAt),
      'optimized': serializer.toJson<bool>(optimized),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  Ruta copyWith({
    String? id,
    Value<String?> name = const Value.absent(),
    Value<String?> routeCode = const Value.absent(),
    String? status,
    Value<String?> originAddress = const Value.absent(),
    Value<double?> originLat = const Value.absent(),
    Value<double?> originLng = const Value.absent(),
    double? totalDistance,
    double? totalWeight,
    double? totalPrice,
    Value<DateTime?> deliveryDate = const Value.absent(),
    Value<String?> vehicleId = const Value.absent(),
    Value<String?> creadoPor = const Value.absent(),
    Value<String?> branchId = const Value.absent(),
    Value<DateTime?> startedAt = const Value.absent(),
    Value<DateTime?> finishedAt = const Value.absent(),
    bool? optimized,
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => Ruta(
    id: id ?? this.id,
    name: name.present ? name.value : this.name,
    routeCode: routeCode.present ? routeCode.value : this.routeCode,
    status: status ?? this.status,
    originAddress: originAddress.present
        ? originAddress.value
        : this.originAddress,
    originLat: originLat.present ? originLat.value : this.originLat,
    originLng: originLng.present ? originLng.value : this.originLng,
    totalDistance: totalDistance ?? this.totalDistance,
    totalWeight: totalWeight ?? this.totalWeight,
    totalPrice: totalPrice ?? this.totalPrice,
    deliveryDate: deliveryDate.present ? deliveryDate.value : this.deliveryDate,
    vehicleId: vehicleId.present ? vehicleId.value : this.vehicleId,
    creadoPor: creadoPor.present ? creadoPor.value : this.creadoPor,
    branchId: branchId.present ? branchId.value : this.branchId,
    startedAt: startedAt.present ? startedAt.value : this.startedAt,
    finishedAt: finishedAt.present ? finishedAt.value : this.finishedAt,
    optimized: optimized ?? this.optimized,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  Ruta copyWithCompanion(RoutesCompanion data) {
    return Ruta(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      routeCode: data.routeCode.present ? data.routeCode.value : this.routeCode,
      status: data.status.present ? data.status.value : this.status,
      originAddress: data.originAddress.present
          ? data.originAddress.value
          : this.originAddress,
      originLat: data.originLat.present ? data.originLat.value : this.originLat,
      originLng: data.originLng.present ? data.originLng.value : this.originLng,
      totalDistance: data.totalDistance.present
          ? data.totalDistance.value
          : this.totalDistance,
      totalWeight: data.totalWeight.present
          ? data.totalWeight.value
          : this.totalWeight,
      totalPrice: data.totalPrice.present
          ? data.totalPrice.value
          : this.totalPrice,
      deliveryDate: data.deliveryDate.present
          ? data.deliveryDate.value
          : this.deliveryDate,
      vehicleId: data.vehicleId.present ? data.vehicleId.value : this.vehicleId,
      creadoPor: data.creadoPor.present ? data.creadoPor.value : this.creadoPor,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
      optimized: data.optimized.present ? data.optimized.value : this.optimized,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Ruta(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('routeCode: $routeCode, ')
          ..write('status: $status, ')
          ..write('originAddress: $originAddress, ')
          ..write('originLat: $originLat, ')
          ..write('originLng: $originLng, ')
          ..write('totalDistance: $totalDistance, ')
          ..write('totalWeight: $totalWeight, ')
          ..write('totalPrice: $totalPrice, ')
          ..write('deliveryDate: $deliveryDate, ')
          ..write('vehicleId: $vehicleId, ')
          ..write('creadoPor: $creadoPor, ')
          ..write('branchId: $branchId, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('optimized: $optimized, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    routeCode,
    status,
    originAddress,
    originLat,
    originLng,
    totalDistance,
    totalWeight,
    totalPrice,
    deliveryDate,
    vehicleId,
    creadoPor,
    branchId,
    startedAt,
    finishedAt,
    optimized,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Ruta &&
          other.id == this.id &&
          other.name == this.name &&
          other.routeCode == this.routeCode &&
          other.status == this.status &&
          other.originAddress == this.originAddress &&
          other.originLat == this.originLat &&
          other.originLng == this.originLng &&
          other.totalDistance == this.totalDistance &&
          other.totalWeight == this.totalWeight &&
          other.totalPrice == this.totalPrice &&
          other.deliveryDate == this.deliveryDate &&
          other.vehicleId == this.vehicleId &&
          other.creadoPor == this.creadoPor &&
          other.branchId == this.branchId &&
          other.startedAt == this.startedAt &&
          other.finishedAt == this.finishedAt &&
          other.optimized == this.optimized &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class RoutesCompanion extends UpdateCompanion<Ruta> {
  final Value<String> id;
  final Value<String?> name;
  final Value<String?> routeCode;
  final Value<String> status;
  final Value<String?> originAddress;
  final Value<double?> originLat;
  final Value<double?> originLng;
  final Value<double> totalDistance;
  final Value<double> totalWeight;
  final Value<double> totalPrice;
  final Value<DateTime?> deliveryDate;
  final Value<String?> vehicleId;
  final Value<String?> creadoPor;
  final Value<String?> branchId;
  final Value<DateTime?> startedAt;
  final Value<DateTime?> finishedAt;
  final Value<bool> optimized;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const RoutesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.routeCode = const Value.absent(),
    this.status = const Value.absent(),
    this.originAddress = const Value.absent(),
    this.originLat = const Value.absent(),
    this.originLng = const Value.absent(),
    this.totalDistance = const Value.absent(),
    this.totalWeight = const Value.absent(),
    this.totalPrice = const Value.absent(),
    this.deliveryDate = const Value.absent(),
    this.vehicleId = const Value.absent(),
    this.creadoPor = const Value.absent(),
    this.branchId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.optimized = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RoutesCompanion.insert({
    required String id,
    this.name = const Value.absent(),
    this.routeCode = const Value.absent(),
    this.status = const Value.absent(),
    this.originAddress = const Value.absent(),
    this.originLat = const Value.absent(),
    this.originLng = const Value.absent(),
    this.totalDistance = const Value.absent(),
    this.totalWeight = const Value.absent(),
    this.totalPrice = const Value.absent(),
    this.deliveryDate = const Value.absent(),
    this.vehicleId = const Value.absent(),
    this.creadoPor = const Value.absent(),
    this.branchId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.optimized = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<Ruta> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? routeCode,
    Expression<String>? status,
    Expression<String>? originAddress,
    Expression<double>? originLat,
    Expression<double>? originLng,
    Expression<double>? totalDistance,
    Expression<double>? totalWeight,
    Expression<double>? totalPrice,
    Expression<DateTime>? deliveryDate,
    Expression<String>? vehicleId,
    Expression<String>? creadoPor,
    Expression<String>? branchId,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? finishedAt,
    Expression<bool>? optimized,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (routeCode != null) 'route_code': routeCode,
      if (status != null) 'status': status,
      if (originAddress != null) 'origin_address': originAddress,
      if (originLat != null) 'origin_lat': originLat,
      if (originLng != null) 'origin_lng': originLng,
      if (totalDistance != null) 'total_distance': totalDistance,
      if (totalWeight != null) 'total_weight': totalWeight,
      if (totalPrice != null) 'total_price': totalPrice,
      if (deliveryDate != null) 'delivery_date': deliveryDate,
      if (vehicleId != null) 'vehicle_id': vehicleId,
      if (creadoPor != null) 'creado_por': creadoPor,
      if (branchId != null) 'branch_id': branchId,
      if (startedAt != null) 'started_at': startedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (optimized != null) 'optimized': optimized,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RoutesCompanion copyWith({
    Value<String>? id,
    Value<String?>? name,
    Value<String?>? routeCode,
    Value<String>? status,
    Value<String?>? originAddress,
    Value<double?>? originLat,
    Value<double?>? originLng,
    Value<double>? totalDistance,
    Value<double>? totalWeight,
    Value<double>? totalPrice,
    Value<DateTime?>? deliveryDate,
    Value<String?>? vehicleId,
    Value<String?>? creadoPor,
    Value<String?>? branchId,
    Value<DateTime?>? startedAt,
    Value<DateTime?>? finishedAt,
    Value<bool>? optimized,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return RoutesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      routeCode: routeCode ?? this.routeCode,
      status: status ?? this.status,
      originAddress: originAddress ?? this.originAddress,
      originLat: originLat ?? this.originLat,
      originLng: originLng ?? this.originLng,
      totalDistance: totalDistance ?? this.totalDistance,
      totalWeight: totalWeight ?? this.totalWeight,
      totalPrice: totalPrice ?? this.totalPrice,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      vehicleId: vehicleId ?? this.vehicleId,
      creadoPor: creadoPor ?? this.creadoPor,
      branchId: branchId ?? this.branchId,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      optimized: optimized ?? this.optimized,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (routeCode.present) {
      map['route_code'] = Variable<String>(routeCode.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (originAddress.present) {
      map['origin_address'] = Variable<String>(originAddress.value);
    }
    if (originLat.present) {
      map['origin_lat'] = Variable<double>(originLat.value);
    }
    if (originLng.present) {
      map['origin_lng'] = Variable<double>(originLng.value);
    }
    if (totalDistance.present) {
      map['total_distance'] = Variable<double>(totalDistance.value);
    }
    if (totalWeight.present) {
      map['total_weight'] = Variable<double>(totalWeight.value);
    }
    if (totalPrice.present) {
      map['total_price'] = Variable<double>(totalPrice.value);
    }
    if (deliveryDate.present) {
      map['delivery_date'] = Variable<DateTime>(deliveryDate.value);
    }
    if (vehicleId.present) {
      map['vehicle_id'] = Variable<String>(vehicleId.value);
    }
    if (creadoPor.present) {
      map['creado_por'] = Variable<String>(creadoPor.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<DateTime>(finishedAt.value);
    }
    if (optimized.present) {
      map['optimized'] = Variable<bool>(optimized.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoutesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('routeCode: $routeCode, ')
          ..write('status: $status, ')
          ..write('originAddress: $originAddress, ')
          ..write('originLat: $originLat, ')
          ..write('originLng: $originLng, ')
          ..write('totalDistance: $totalDistance, ')
          ..write('totalWeight: $totalWeight, ')
          ..write('totalPrice: $totalPrice, ')
          ..write('deliveryDate: $deliveryDate, ')
          ..write('vehicleId: $vehicleId, ')
          ..write('creadoPor: $creadoPor, ')
          ..write('branchId: $branchId, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('optimized: $optimized, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WarehousesTable extends Warehouses
    with TableInfo<$WarehousesTable, Almacen> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WarehousesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sucursalCodigoMeta = const VerificationMeta(
    'sucursalCodigo',
  );
  @override
  late final GeneratedColumn<String> sucursalCodigo = GeneratedColumn<String>(
    'sucursal_codigo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nombreMeta = const VerificationMeta('nombre');
  @override
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _direccionMeta = const VerificationMeta(
    'direccion',
  );
  @override
  late final GeneratedColumn<String> direccion = GeneratedColumn<String>(
    'direccion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lngMeta = const VerificationMeta('lng');
  @override
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
    'lng',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _principalMeta = const VerificationMeta(
    'principal',
  );
  @override
  late final GeneratedColumn<bool> principal = GeneratedColumn<bool>(
    'principal',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("principal" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _activoMeta = const VerificationMeta('activo');
  @override
  late final GeneratedColumn<bool> activo = GeneratedColumn<bool>(
    'activo',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("activo" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sucursalCodigo,
    nombre,
    direccion,
    lat,
    lng,
    principal,
    activo,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'warehouses';
  @override
  VerificationContext validateIntegrity(
    Insertable<Almacen> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('sucursal_codigo')) {
      context.handle(
        _sucursalCodigoMeta,
        sucursalCodigo.isAcceptableOrUnknown(
          data['sucursal_codigo']!,
          _sucursalCodigoMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sucursalCodigoMeta);
    }
    if (data.containsKey('nombre')) {
      context.handle(
        _nombreMeta,
        nombre.isAcceptableOrUnknown(data['nombre']!, _nombreMeta),
      );
    } else if (isInserting) {
      context.missing(_nombreMeta);
    }
    if (data.containsKey('direccion')) {
      context.handle(
        _direccionMeta,
        direccion.isAcceptableOrUnknown(data['direccion']!, _direccionMeta),
      );
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    }
    if (data.containsKey('lng')) {
      context.handle(
        _lngMeta,
        lng.isAcceptableOrUnknown(data['lng']!, _lngMeta),
      );
    }
    if (data.containsKey('principal')) {
      context.handle(
        _principalMeta,
        principal.isAcceptableOrUnknown(data['principal']!, _principalMeta),
      );
    }
    if (data.containsKey('activo')) {
      context.handle(
        _activoMeta,
        activo.isAcceptableOrUnknown(data['activo']!, _activoMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Almacen map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Almacen(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sucursalCodigo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sucursal_codigo'],
      )!,
      nombre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nombre'],
      )!,
      direccion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direccion'],
      ),
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      ),
      lng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lng'],
      ),
      principal: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}principal'],
      )!,
      activo: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}activo'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $WarehousesTable createAlias(String alias) {
    return $WarehousesTable(attachedDatabase, alias);
  }
}

class Almacen extends DataClass implements Insertable<Almacen> {
  final String id;
  final String sucursalCodigo;
  final String nombre;
  final String? direccion;
  final double? lat;
  final double? lng;

  /// El principal de la sucursal: es el punto de partida y el origen desde el
  /// que se miden los km de los clientes.
  final bool principal;
  final bool activo;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const Almacen({
    required this.id,
    required this.sucursalCodigo,
    required this.nombre,
    this.direccion,
    this.lat,
    this.lng,
    required this.principal,
    required this.activo,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['sucursal_codigo'] = Variable<String>(sucursalCodigo);
    map['nombre'] = Variable<String>(nombre);
    if (!nullToAbsent || direccion != null) {
      map['direccion'] = Variable<String>(direccion);
    }
    if (!nullToAbsent || lat != null) {
      map['lat'] = Variable<double>(lat);
    }
    if (!nullToAbsent || lng != null) {
      map['lng'] = Variable<double>(lng);
    }
    map['principal'] = Variable<bool>(principal);
    map['activo'] = Variable<bool>(activo);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  WarehousesCompanion toCompanion(bool nullToAbsent) {
    return WarehousesCompanion(
      id: Value(id),
      sucursalCodigo: Value(sucursalCodigo),
      nombre: Value(nombre),
      direccion: direccion == null && nullToAbsent
          ? const Value.absent()
          : Value(direccion),
      lat: lat == null && nullToAbsent ? const Value.absent() : Value(lat),
      lng: lng == null && nullToAbsent ? const Value.absent() : Value(lng),
      principal: Value(principal),
      activo: Value(activo),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory Almacen.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Almacen(
      id: serializer.fromJson<String>(json['id']),
      sucursalCodigo: serializer.fromJson<String>(json['sucursalCodigo']),
      nombre: serializer.fromJson<String>(json['nombre']),
      direccion: serializer.fromJson<String?>(json['direccion']),
      lat: serializer.fromJson<double?>(json['lat']),
      lng: serializer.fromJson<double?>(json['lng']),
      principal: serializer.fromJson<bool>(json['principal']),
      activo: serializer.fromJson<bool>(json['activo']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sucursalCodigo': serializer.toJson<String>(sucursalCodigo),
      'nombre': serializer.toJson<String>(nombre),
      'direccion': serializer.toJson<String?>(direccion),
      'lat': serializer.toJson<double?>(lat),
      'lng': serializer.toJson<double?>(lng),
      'principal': serializer.toJson<bool>(principal),
      'activo': serializer.toJson<bool>(activo),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  Almacen copyWith({
    String? id,
    String? sucursalCodigo,
    String? nombre,
    Value<String?> direccion = const Value.absent(),
    Value<double?> lat = const Value.absent(),
    Value<double?> lng = const Value.absent(),
    bool? principal,
    bool? activo,
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => Almacen(
    id: id ?? this.id,
    sucursalCodigo: sucursalCodigo ?? this.sucursalCodigo,
    nombre: nombre ?? this.nombre,
    direccion: direccion.present ? direccion.value : this.direccion,
    lat: lat.present ? lat.value : this.lat,
    lng: lng.present ? lng.value : this.lng,
    principal: principal ?? this.principal,
    activo: activo ?? this.activo,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  Almacen copyWithCompanion(WarehousesCompanion data) {
    return Almacen(
      id: data.id.present ? data.id.value : this.id,
      sucursalCodigo: data.sucursalCodigo.present
          ? data.sucursalCodigo.value
          : this.sucursalCodigo,
      nombre: data.nombre.present ? data.nombre.value : this.nombre,
      direccion: data.direccion.present ? data.direccion.value : this.direccion,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      principal: data.principal.present ? data.principal.value : this.principal,
      activo: data.activo.present ? data.activo.value : this.activo,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Almacen(')
          ..write('id: $id, ')
          ..write('sucursalCodigo: $sucursalCodigo, ')
          ..write('nombre: $nombre, ')
          ..write('direccion: $direccion, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('principal: $principal, ')
          ..write('activo: $activo, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sucursalCodigo,
    nombre,
    direccion,
    lat,
    lng,
    principal,
    activo,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Almacen &&
          other.id == this.id &&
          other.sucursalCodigo == this.sucursalCodigo &&
          other.nombre == this.nombre &&
          other.direccion == this.direccion &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.principal == this.principal &&
          other.activo == this.activo &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class WarehousesCompanion extends UpdateCompanion<Almacen> {
  final Value<String> id;
  final Value<String> sucursalCodigo;
  final Value<String> nombre;
  final Value<String?> direccion;
  final Value<double?> lat;
  final Value<double?> lng;
  final Value<bool> principal;
  final Value<bool> activo;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const WarehousesCompanion({
    this.id = const Value.absent(),
    this.sucursalCodigo = const Value.absent(),
    this.nombre = const Value.absent(),
    this.direccion = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.principal = const Value.absent(),
    this.activo = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WarehousesCompanion.insert({
    required String id,
    required String sucursalCodigo,
    required String nombre,
    this.direccion = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.principal = const Value.absent(),
    this.activo = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sucursalCodigo = Value(sucursalCodigo),
       nombre = Value(nombre);
  static Insertable<Almacen> custom({
    Expression<String>? id,
    Expression<String>? sucursalCodigo,
    Expression<String>? nombre,
    Expression<String>? direccion,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<bool>? principal,
    Expression<bool>? activo,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sucursalCodigo != null) 'sucursal_codigo': sucursalCodigo,
      if (nombre != null) 'nombre': nombre,
      if (direccion != null) 'direccion': direccion,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (principal != null) 'principal': principal,
      if (activo != null) 'activo': activo,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WarehousesCompanion copyWith({
    Value<String>? id,
    Value<String>? sucursalCodigo,
    Value<String>? nombre,
    Value<String?>? direccion,
    Value<double?>? lat,
    Value<double?>? lng,
    Value<bool>? principal,
    Value<bool>? activo,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return WarehousesCompanion(
      id: id ?? this.id,
      sucursalCodigo: sucursalCodigo ?? this.sucursalCodigo,
      nombre: nombre ?? this.nombre,
      direccion: direccion ?? this.direccion,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      principal: principal ?? this.principal,
      activo: activo ?? this.activo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sucursalCodigo.present) {
      map['sucursal_codigo'] = Variable<String>(sucursalCodigo.value);
    }
    if (nombre.present) {
      map['nombre'] = Variable<String>(nombre.value);
    }
    if (direccion.present) {
      map['direccion'] = Variable<String>(direccion.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (principal.present) {
      map['principal'] = Variable<bool>(principal.value);
    }
    if (activo.present) {
      map['activo'] = Variable<bool>(activo.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WarehousesCompanion(')
          ..write('id: $id, ')
          ..write('sucursalCodigo: $sucursalCodigo, ')
          ..write('nombre: $nombre, ')
          ..write('direccion: $direccion, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('principal: $principal, ')
          ..write('activo: $activo, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Ajustes> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncBarridoDiaMeta = const VerificationMeta(
    'syncBarridoDia',
  );
  @override
  late final GeneratedColumn<int> syncBarridoDia = GeneratedColumn<int>(
    'sync_barrido_dia',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _catalogoTraidoAtMeta = const VerificationMeta(
    'catalogoTraidoAt',
  );
  @override
  late final GeneratedColumn<DateTime> catalogoTraidoAt =
      GeneratedColumn<DateTime>(
        'catalogo_traido_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('USD'),
  );
  static const VerificationMeta _cupRateMeta = const VerificationMeta(
    'cupRate',
  );
  @override
  late final GeneratedColumn<double> cupRate = GeneratedColumn<double>(
    'cup_rate',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(320),
  );
  static const VerificationMeta _cupRateUpdatedAtMeta = const VerificationMeta(
    'cupRateUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cupRateUpdatedAt =
      GeneratedColumn<DateTime>(
        'cup_rate_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    syncBarridoDia,
    catalogoTraidoAt,
    currency,
    cupRate,
    cupRateUpdatedAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Ajustes> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sync_barrido_dia')) {
      context.handle(
        _syncBarridoDiaMeta,
        syncBarridoDia.isAcceptableOrUnknown(
          data['sync_barrido_dia']!,
          _syncBarridoDiaMeta,
        ),
      );
    }
    if (data.containsKey('catalogo_traido_at')) {
      context.handle(
        _catalogoTraidoAtMeta,
        catalogoTraidoAt.isAcceptableOrUnknown(
          data['catalogo_traido_at']!,
          _catalogoTraidoAtMeta,
        ),
      );
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    }
    if (data.containsKey('cup_rate')) {
      context.handle(
        _cupRateMeta,
        cupRate.isAcceptableOrUnknown(data['cup_rate']!, _cupRateMeta),
      );
    }
    if (data.containsKey('cup_rate_updated_at')) {
      context.handle(
        _cupRateUpdatedAtMeta,
        cupRateUpdatedAt.isAcceptableOrUnknown(
          data['cup_rate_updated_at']!,
          _cupRateUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Ajustes map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Ajustes(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      syncBarridoDia: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_barrido_dia'],
      )!,
      catalogoTraidoAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}catalogo_traido_at'],
      ),
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      cupRate: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cup_rate'],
      )!,
      cupRateUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cup_rate_updated_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Ajustes extends DataClass implements Insertable<Ajustes> {
  final int id;
  final int syncBarridoDia;
  final DateTime? catalogoTraidoAt;
  final String currency;
  final double cupRate;
  final DateTime? cupRateUpdatedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const Ajustes({
    required this.id,
    required this.syncBarridoDia,
    this.catalogoTraidoAt,
    required this.currency,
    required this.cupRate,
    this.cupRateUpdatedAt,
    this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['sync_barrido_dia'] = Variable<int>(syncBarridoDia);
    if (!nullToAbsent || catalogoTraidoAt != null) {
      map['catalogo_traido_at'] = Variable<DateTime>(catalogoTraidoAt);
    }
    map['currency'] = Variable<String>(currency);
    map['cup_rate'] = Variable<double>(cupRate);
    if (!nullToAbsent || cupRateUpdatedAt != null) {
      map['cup_rate_updated_at'] = Variable<DateTime>(cupRateUpdatedAt);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      id: Value(id),
      syncBarridoDia: Value(syncBarridoDia),
      catalogoTraidoAt: catalogoTraidoAt == null && nullToAbsent
          ? const Value.absent()
          : Value(catalogoTraidoAt),
      currency: Value(currency),
      cupRate: Value(cupRate),
      cupRateUpdatedAt: cupRateUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(cupRateUpdatedAt),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory Ajustes.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Ajustes(
      id: serializer.fromJson<int>(json['id']),
      syncBarridoDia: serializer.fromJson<int>(json['syncBarridoDia']),
      catalogoTraidoAt: serializer.fromJson<DateTime?>(
        json['catalogoTraidoAt'],
      ),
      currency: serializer.fromJson<String>(json['currency']),
      cupRate: serializer.fromJson<double>(json['cupRate']),
      cupRateUpdatedAt: serializer.fromJson<DateTime?>(
        json['cupRateUpdatedAt'],
      ),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'syncBarridoDia': serializer.toJson<int>(syncBarridoDia),
      'catalogoTraidoAt': serializer.toJson<DateTime?>(catalogoTraidoAt),
      'currency': serializer.toJson<String>(currency),
      'cupRate': serializer.toJson<double>(cupRate),
      'cupRateUpdatedAt': serializer.toJson<DateTime?>(cupRateUpdatedAt),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  Ajustes copyWith({
    int? id,
    int? syncBarridoDia,
    Value<DateTime?> catalogoTraidoAt = const Value.absent(),
    String? currency,
    double? cupRate,
    Value<DateTime?> cupRateUpdatedAt = const Value.absent(),
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => Ajustes(
    id: id ?? this.id,
    syncBarridoDia: syncBarridoDia ?? this.syncBarridoDia,
    catalogoTraidoAt: catalogoTraidoAt.present
        ? catalogoTraidoAt.value
        : this.catalogoTraidoAt,
    currency: currency ?? this.currency,
    cupRate: cupRate ?? this.cupRate,
    cupRateUpdatedAt: cupRateUpdatedAt.present
        ? cupRateUpdatedAt.value
        : this.cupRateUpdatedAt,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  Ajustes copyWithCompanion(SettingsCompanion data) {
    return Ajustes(
      id: data.id.present ? data.id.value : this.id,
      syncBarridoDia: data.syncBarridoDia.present
          ? data.syncBarridoDia.value
          : this.syncBarridoDia,
      catalogoTraidoAt: data.catalogoTraidoAt.present
          ? data.catalogoTraidoAt.value
          : this.catalogoTraidoAt,
      currency: data.currency.present ? data.currency.value : this.currency,
      cupRate: data.cupRate.present ? data.cupRate.value : this.cupRate,
      cupRateUpdatedAt: data.cupRateUpdatedAt.present
          ? data.cupRateUpdatedAt.value
          : this.cupRateUpdatedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Ajustes(')
          ..write('id: $id, ')
          ..write('syncBarridoDia: $syncBarridoDia, ')
          ..write('catalogoTraidoAt: $catalogoTraidoAt, ')
          ..write('currency: $currency, ')
          ..write('cupRate: $cupRate, ')
          ..write('cupRateUpdatedAt: $cupRateUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    syncBarridoDia,
    catalogoTraidoAt,
    currency,
    cupRate,
    cupRateUpdatedAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Ajustes &&
          other.id == this.id &&
          other.syncBarridoDia == this.syncBarridoDia &&
          other.catalogoTraidoAt == this.catalogoTraidoAt &&
          other.currency == this.currency &&
          other.cupRate == this.cupRate &&
          other.cupRateUpdatedAt == this.cupRateUpdatedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SettingsCompanion extends UpdateCompanion<Ajustes> {
  final Value<int> id;
  final Value<int> syncBarridoDia;
  final Value<DateTime?> catalogoTraidoAt;
  final Value<String> currency;
  final Value<double> cupRate;
  final Value<DateTime?> cupRateUpdatedAt;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  const SettingsCompanion({
    this.id = const Value.absent(),
    this.syncBarridoDia = const Value.absent(),
    this.catalogoTraidoAt = const Value.absent(),
    this.currency = const Value.absent(),
    this.cupRate = const Value.absent(),
    this.cupRateUpdatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  SettingsCompanion.insert({
    this.id = const Value.absent(),
    this.syncBarridoDia = const Value.absent(),
    this.catalogoTraidoAt = const Value.absent(),
    this.currency = const Value.absent(),
    this.cupRate = const Value.absent(),
    this.cupRateUpdatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  static Insertable<Ajustes> custom({
    Expression<int>? id,
    Expression<int>? syncBarridoDia,
    Expression<DateTime>? catalogoTraidoAt,
    Expression<String>? currency,
    Expression<double>? cupRate,
    Expression<DateTime>? cupRateUpdatedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (syncBarridoDia != null) 'sync_barrido_dia': syncBarridoDia,
      if (catalogoTraidoAt != null) 'catalogo_traido_at': catalogoTraidoAt,
      if (currency != null) 'currency': currency,
      if (cupRate != null) 'cup_rate': cupRate,
      if (cupRateUpdatedAt != null) 'cup_rate_updated_at': cupRateUpdatedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  SettingsCompanion copyWith({
    Value<int>? id,
    Value<int>? syncBarridoDia,
    Value<DateTime?>? catalogoTraidoAt,
    Value<String>? currency,
    Value<double>? cupRate,
    Value<DateTime?>? cupRateUpdatedAt,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
  }) {
    return SettingsCompanion(
      id: id ?? this.id,
      syncBarridoDia: syncBarridoDia ?? this.syncBarridoDia,
      catalogoTraidoAt: catalogoTraidoAt ?? this.catalogoTraidoAt,
      currency: currency ?? this.currency,
      cupRate: cupRate ?? this.cupRate,
      cupRateUpdatedAt: cupRateUpdatedAt ?? this.cupRateUpdatedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (syncBarridoDia.present) {
      map['sync_barrido_dia'] = Variable<int>(syncBarridoDia.value);
    }
    if (catalogoTraidoAt.present) {
      map['catalogo_traido_at'] = Variable<DateTime>(catalogoTraidoAt.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (cupRate.present) {
      map['cup_rate'] = Variable<double>(cupRate.value);
    }
    if (cupRateUpdatedAt.present) {
      map['cup_rate_updated_at'] = Variable<DateTime>(cupRateUpdatedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('id: $id, ')
          ..write('syncBarridoDia: $syncBarridoDia, ')
          ..write('catalogoTraidoAt: $catalogoTraidoAt, ')
          ..write('currency: $currency, ')
          ..write('cupRate: $cupRate, ')
          ..write('cupRateUpdatedAt: $cupRateUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ApuntesTable extends Apuntes with TableInfo<$ApuntesTable, Apunte> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ApuntesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ordenMeta = const VerificationMeta('orden');
  @override
  late final GeneratedColumn<int> orden = GeneratedColumn<int>(
    'orden',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _claveMeta = const VerificationMeta('clave');
  @override
  late final GeneratedColumn<String> clave = GeneratedColumn<String>(
    'clave',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _hechoAtMeta = const VerificationMeta(
    'hechoAt',
  );
  @override
  late final GeneratedColumn<DateTime> hechoAt = GeneratedColumn<DateTime>(
    'hecho_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metodoMeta = const VerificationMeta('metodo');
  @override
  late final GeneratedColumn<String> metodo = GeneratedColumn<String>(
    'metodo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rutaMeta = const VerificationMeta('ruta');
  @override
  late final GeneratedColumn<String> ruta = GeneratedColumn<String>(
    'ruta',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cuerpoMeta = const VerificationMeta('cuerpo');
  @override
  late final GeneratedColumn<String> cuerpo = GeneratedColumn<String>(
    'cuerpo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _provisionalMeta = const VerificationMeta(
    'provisional',
  );
  @override
  late final GeneratedColumn<String> provisional = GeneratedColumn<String>(
    'provisional',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<EstadoApunte, String> estado =
      GeneratedColumn<String>(
        'estado',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('pendiente'),
      ).withConverter<EstadoApunte>($ApuntesTable.$converterestado);
  static const VerificationMeta _motivoMeta = const VerificationMeta('motivo');
  @override
  late final GeneratedColumn<String> motivo = GeneratedColumn<String>(
    'motivo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resueltoAtMeta = const VerificationMeta(
    'resueltoAt',
  );
  @override
  late final GeneratedColumn<DateTime> resueltoAt = GeneratedColumn<DateTime>(
    'resuelto_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _intentosMeta = const VerificationMeta(
    'intentos',
  );
  @override
  late final GeneratedColumn<int> intentos = GeneratedColumn<int>(
    'intentos',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<String> revision = GeneratedColumn<String>(
    'revision',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revisadoPorMeta = const VerificationMeta(
    'revisadoPor',
  );
  @override
  late final GeneratedColumn<String> revisadoPor = GeneratedColumn<String>(
    'revisado_por',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revisadoAtMeta = const VerificationMeta(
    'revisadoAt',
  );
  @override
  late final GeneratedColumn<DateTime> revisadoAt = GeneratedColumn<DateTime>(
    'revisado_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _motivoRevisionMeta = const VerificationMeta(
    'motivoRevision',
  );
  @override
  late final GeneratedColumn<String> motivoRevision = GeneratedColumn<String>(
    'motivo_revision',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    orden,
    clave,
    hechoAt,
    metodo,
    ruta,
    cuerpo,
    provisional,
    estado,
    motivo,
    resueltoAt,
    intentos,
    revision,
    revisadoPor,
    revisadoAt,
    motivoRevision,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'apuntes';
  @override
  VerificationContext validateIntegrity(
    Insertable<Apunte> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('orden')) {
      context.handle(
        _ordenMeta,
        orden.isAcceptableOrUnknown(data['orden']!, _ordenMeta),
      );
    }
    if (data.containsKey('clave')) {
      context.handle(
        _claveMeta,
        clave.isAcceptableOrUnknown(data['clave']!, _claveMeta),
      );
    } else if (isInserting) {
      context.missing(_claveMeta);
    }
    if (data.containsKey('hecho_at')) {
      context.handle(
        _hechoAtMeta,
        hechoAt.isAcceptableOrUnknown(data['hecho_at']!, _hechoAtMeta),
      );
    } else if (isInserting) {
      context.missing(_hechoAtMeta);
    }
    if (data.containsKey('metodo')) {
      context.handle(
        _metodoMeta,
        metodo.isAcceptableOrUnknown(data['metodo']!, _metodoMeta),
      );
    } else if (isInserting) {
      context.missing(_metodoMeta);
    }
    if (data.containsKey('ruta')) {
      context.handle(
        _rutaMeta,
        ruta.isAcceptableOrUnknown(data['ruta']!, _rutaMeta),
      );
    } else if (isInserting) {
      context.missing(_rutaMeta);
    }
    if (data.containsKey('cuerpo')) {
      context.handle(
        _cuerpoMeta,
        cuerpo.isAcceptableOrUnknown(data['cuerpo']!, _cuerpoMeta),
      );
    } else if (isInserting) {
      context.missing(_cuerpoMeta);
    }
    if (data.containsKey('provisional')) {
      context.handle(
        _provisionalMeta,
        provisional.isAcceptableOrUnknown(
          data['provisional']!,
          _provisionalMeta,
        ),
      );
    }
    if (data.containsKey('motivo')) {
      context.handle(
        _motivoMeta,
        motivo.isAcceptableOrUnknown(data['motivo']!, _motivoMeta),
      );
    }
    if (data.containsKey('resuelto_at')) {
      context.handle(
        _resueltoAtMeta,
        resueltoAt.isAcceptableOrUnknown(data['resuelto_at']!, _resueltoAtMeta),
      );
    }
    if (data.containsKey('intentos')) {
      context.handle(
        _intentosMeta,
        intentos.isAcceptableOrUnknown(data['intentos']!, _intentosMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('revisado_por')) {
      context.handle(
        _revisadoPorMeta,
        revisadoPor.isAcceptableOrUnknown(
          data['revisado_por']!,
          _revisadoPorMeta,
        ),
      );
    }
    if (data.containsKey('revisado_at')) {
      context.handle(
        _revisadoAtMeta,
        revisadoAt.isAcceptableOrUnknown(data['revisado_at']!, _revisadoAtMeta),
      );
    }
    if (data.containsKey('motivo_revision')) {
      context.handle(
        _motivoRevisionMeta,
        motivoRevision.isAcceptableOrUnknown(
          data['motivo_revision']!,
          _motivoRevisionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {orden};
  @override
  Apunte map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Apunte(
      orden: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}orden'],
      )!,
      clave: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clave'],
      )!,
      hechoAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}hecho_at'],
      )!,
      metodo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metodo'],
      )!,
      ruta: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ruta'],
      )!,
      cuerpo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cuerpo'],
      )!,
      provisional: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provisional'],
      ),
      estado: $ApuntesTable.$converterestado.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}estado'],
        )!,
      ),
      motivo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}motivo'],
      ),
      resueltoAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}resuelto_at'],
      ),
      intentos: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}intentos'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}revision'],
      ),
      revisadoPor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}revisado_por'],
      ),
      revisadoAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}revisado_at'],
      ),
      motivoRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}motivo_revision'],
      ),
    );
  }

  @override
  $ApuntesTable createAlias(String alias) {
    return $ApuntesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<EstadoApunte, String, String> $converterestado =
      const EnumNameConverter<EstadoApunte>(EstadoApunte.values);
}

class Apunte extends DataClass implements Insertable<Apunte> {
  final int orden;

  /// ULID, la pone el aparato, una por apunte. Es la idempotencia: si la subida
  /// se corto DESPUES de que el servidor guardara, el reintento devuelve
  /// `repetido` y no se duplica (caso S5).
  final String clave;

  /// La hora del APARATO, escrita al encolar y NO tocada al subir. Lo que se
  /// marca a las cuatro llega como las cuatro, aunque suba a las siete
  /// (regla 7, caso S2).
  final DateTime hechoAt;
  final String metodo;
  final String ruta;

  /// El cuerpo, como JSON en texto. Se guarda serializado porque tiene que poder
  /// REESCRIBIRSE cuando un `local-…` se convierte en un id de verdad.
  final String cuerpo;

  /// `local-…` si este apunte CREA algo. Es la bisagra de la sustitucion (§2.2.5).
  final String? provisional;
  final EstadoApunte estado;
  final String? motivo;
  final DateTime? resueltoAt;
  final int intentos;

  /// El id de la ENTREGA (una pulsacion del boton) en la que se mando.
  final String? revision;

  /// El NOMBRE de quien decidio (el revisor), para pintarlo; no un uuid.
  final String? revisadoPor;

  /// Cuando decidio, segun el servidor.
  final DateTime? revisadoAt;

  /// Lo que dice la bandeja de este apunte: el motivo escrito del descarte o el
  /// literal del reparto cuando no pudo aplicarlo.
  final String? motivoRevision;
  const Apunte({
    required this.orden,
    required this.clave,
    required this.hechoAt,
    required this.metodo,
    required this.ruta,
    required this.cuerpo,
    this.provisional,
    required this.estado,
    this.motivo,
    this.resueltoAt,
    required this.intentos,
    this.revision,
    this.revisadoPor,
    this.revisadoAt,
    this.motivoRevision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['orden'] = Variable<int>(orden);
    map['clave'] = Variable<String>(clave);
    map['hecho_at'] = Variable<DateTime>(hechoAt);
    map['metodo'] = Variable<String>(metodo);
    map['ruta'] = Variable<String>(ruta);
    map['cuerpo'] = Variable<String>(cuerpo);
    if (!nullToAbsent || provisional != null) {
      map['provisional'] = Variable<String>(provisional);
    }
    {
      map['estado'] = Variable<String>(
        $ApuntesTable.$converterestado.toSql(estado),
      );
    }
    if (!nullToAbsent || motivo != null) {
      map['motivo'] = Variable<String>(motivo);
    }
    if (!nullToAbsent || resueltoAt != null) {
      map['resuelto_at'] = Variable<DateTime>(resueltoAt);
    }
    map['intentos'] = Variable<int>(intentos);
    if (!nullToAbsent || revision != null) {
      map['revision'] = Variable<String>(revision);
    }
    if (!nullToAbsent || revisadoPor != null) {
      map['revisado_por'] = Variable<String>(revisadoPor);
    }
    if (!nullToAbsent || revisadoAt != null) {
      map['revisado_at'] = Variable<DateTime>(revisadoAt);
    }
    if (!nullToAbsent || motivoRevision != null) {
      map['motivo_revision'] = Variable<String>(motivoRevision);
    }
    return map;
  }

  ApuntesCompanion toCompanion(bool nullToAbsent) {
    return ApuntesCompanion(
      orden: Value(orden),
      clave: Value(clave),
      hechoAt: Value(hechoAt),
      metodo: Value(metodo),
      ruta: Value(ruta),
      cuerpo: Value(cuerpo),
      provisional: provisional == null && nullToAbsent
          ? const Value.absent()
          : Value(provisional),
      estado: Value(estado),
      motivo: motivo == null && nullToAbsent
          ? const Value.absent()
          : Value(motivo),
      resueltoAt: resueltoAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resueltoAt),
      intentos: Value(intentos),
      revision: revision == null && nullToAbsent
          ? const Value.absent()
          : Value(revision),
      revisadoPor: revisadoPor == null && nullToAbsent
          ? const Value.absent()
          : Value(revisadoPor),
      revisadoAt: revisadoAt == null && nullToAbsent
          ? const Value.absent()
          : Value(revisadoAt),
      motivoRevision: motivoRevision == null && nullToAbsent
          ? const Value.absent()
          : Value(motivoRevision),
    );
  }

  factory Apunte.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Apunte(
      orden: serializer.fromJson<int>(json['orden']),
      clave: serializer.fromJson<String>(json['clave']),
      hechoAt: serializer.fromJson<DateTime>(json['hechoAt']),
      metodo: serializer.fromJson<String>(json['metodo']),
      ruta: serializer.fromJson<String>(json['ruta']),
      cuerpo: serializer.fromJson<String>(json['cuerpo']),
      provisional: serializer.fromJson<String?>(json['provisional']),
      estado: $ApuntesTable.$converterestado.fromJson(
        serializer.fromJson<String>(json['estado']),
      ),
      motivo: serializer.fromJson<String?>(json['motivo']),
      resueltoAt: serializer.fromJson<DateTime?>(json['resueltoAt']),
      intentos: serializer.fromJson<int>(json['intentos']),
      revision: serializer.fromJson<String?>(json['revision']),
      revisadoPor: serializer.fromJson<String?>(json['revisadoPor']),
      revisadoAt: serializer.fromJson<DateTime?>(json['revisadoAt']),
      motivoRevision: serializer.fromJson<String?>(json['motivoRevision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'orden': serializer.toJson<int>(orden),
      'clave': serializer.toJson<String>(clave),
      'hechoAt': serializer.toJson<DateTime>(hechoAt),
      'metodo': serializer.toJson<String>(metodo),
      'ruta': serializer.toJson<String>(ruta),
      'cuerpo': serializer.toJson<String>(cuerpo),
      'provisional': serializer.toJson<String?>(provisional),
      'estado': serializer.toJson<String>(
        $ApuntesTable.$converterestado.toJson(estado),
      ),
      'motivo': serializer.toJson<String?>(motivo),
      'resueltoAt': serializer.toJson<DateTime?>(resueltoAt),
      'intentos': serializer.toJson<int>(intentos),
      'revision': serializer.toJson<String?>(revision),
      'revisadoPor': serializer.toJson<String?>(revisadoPor),
      'revisadoAt': serializer.toJson<DateTime?>(revisadoAt),
      'motivoRevision': serializer.toJson<String?>(motivoRevision),
    };
  }

  Apunte copyWith({
    int? orden,
    String? clave,
    DateTime? hechoAt,
    String? metodo,
    String? ruta,
    String? cuerpo,
    Value<String?> provisional = const Value.absent(),
    EstadoApunte? estado,
    Value<String?> motivo = const Value.absent(),
    Value<DateTime?> resueltoAt = const Value.absent(),
    int? intentos,
    Value<String?> revision = const Value.absent(),
    Value<String?> revisadoPor = const Value.absent(),
    Value<DateTime?> revisadoAt = const Value.absent(),
    Value<String?> motivoRevision = const Value.absent(),
  }) => Apunte(
    orden: orden ?? this.orden,
    clave: clave ?? this.clave,
    hechoAt: hechoAt ?? this.hechoAt,
    metodo: metodo ?? this.metodo,
    ruta: ruta ?? this.ruta,
    cuerpo: cuerpo ?? this.cuerpo,
    provisional: provisional.present ? provisional.value : this.provisional,
    estado: estado ?? this.estado,
    motivo: motivo.present ? motivo.value : this.motivo,
    resueltoAt: resueltoAt.present ? resueltoAt.value : this.resueltoAt,
    intentos: intentos ?? this.intentos,
    revision: revision.present ? revision.value : this.revision,
    revisadoPor: revisadoPor.present ? revisadoPor.value : this.revisadoPor,
    revisadoAt: revisadoAt.present ? revisadoAt.value : this.revisadoAt,
    motivoRevision: motivoRevision.present
        ? motivoRevision.value
        : this.motivoRevision,
  );
  Apunte copyWithCompanion(ApuntesCompanion data) {
    return Apunte(
      orden: data.orden.present ? data.orden.value : this.orden,
      clave: data.clave.present ? data.clave.value : this.clave,
      hechoAt: data.hechoAt.present ? data.hechoAt.value : this.hechoAt,
      metodo: data.metodo.present ? data.metodo.value : this.metodo,
      ruta: data.ruta.present ? data.ruta.value : this.ruta,
      cuerpo: data.cuerpo.present ? data.cuerpo.value : this.cuerpo,
      provisional: data.provisional.present
          ? data.provisional.value
          : this.provisional,
      estado: data.estado.present ? data.estado.value : this.estado,
      motivo: data.motivo.present ? data.motivo.value : this.motivo,
      resueltoAt: data.resueltoAt.present
          ? data.resueltoAt.value
          : this.resueltoAt,
      intentos: data.intentos.present ? data.intentos.value : this.intentos,
      revision: data.revision.present ? data.revision.value : this.revision,
      revisadoPor: data.revisadoPor.present
          ? data.revisadoPor.value
          : this.revisadoPor,
      revisadoAt: data.revisadoAt.present
          ? data.revisadoAt.value
          : this.revisadoAt,
      motivoRevision: data.motivoRevision.present
          ? data.motivoRevision.value
          : this.motivoRevision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Apunte(')
          ..write('orden: $orden, ')
          ..write('clave: $clave, ')
          ..write('hechoAt: $hechoAt, ')
          ..write('metodo: $metodo, ')
          ..write('ruta: $ruta, ')
          ..write('cuerpo: $cuerpo, ')
          ..write('provisional: $provisional, ')
          ..write('estado: $estado, ')
          ..write('motivo: $motivo, ')
          ..write('resueltoAt: $resueltoAt, ')
          ..write('intentos: $intentos, ')
          ..write('revision: $revision, ')
          ..write('revisadoPor: $revisadoPor, ')
          ..write('revisadoAt: $revisadoAt, ')
          ..write('motivoRevision: $motivoRevision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    orden,
    clave,
    hechoAt,
    metodo,
    ruta,
    cuerpo,
    provisional,
    estado,
    motivo,
    resueltoAt,
    intentos,
    revision,
    revisadoPor,
    revisadoAt,
    motivoRevision,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Apunte &&
          other.orden == this.orden &&
          other.clave == this.clave &&
          other.hechoAt == this.hechoAt &&
          other.metodo == this.metodo &&
          other.ruta == this.ruta &&
          other.cuerpo == this.cuerpo &&
          other.provisional == this.provisional &&
          other.estado == this.estado &&
          other.motivo == this.motivo &&
          other.resueltoAt == this.resueltoAt &&
          other.intentos == this.intentos &&
          other.revision == this.revision &&
          other.revisadoPor == this.revisadoPor &&
          other.revisadoAt == this.revisadoAt &&
          other.motivoRevision == this.motivoRevision);
}

class ApuntesCompanion extends UpdateCompanion<Apunte> {
  final Value<int> orden;
  final Value<String> clave;
  final Value<DateTime> hechoAt;
  final Value<String> metodo;
  final Value<String> ruta;
  final Value<String> cuerpo;
  final Value<String?> provisional;
  final Value<EstadoApunte> estado;
  final Value<String?> motivo;
  final Value<DateTime?> resueltoAt;
  final Value<int> intentos;
  final Value<String?> revision;
  final Value<String?> revisadoPor;
  final Value<DateTime?> revisadoAt;
  final Value<String?> motivoRevision;
  const ApuntesCompanion({
    this.orden = const Value.absent(),
    this.clave = const Value.absent(),
    this.hechoAt = const Value.absent(),
    this.metodo = const Value.absent(),
    this.ruta = const Value.absent(),
    this.cuerpo = const Value.absent(),
    this.provisional = const Value.absent(),
    this.estado = const Value.absent(),
    this.motivo = const Value.absent(),
    this.resueltoAt = const Value.absent(),
    this.intentos = const Value.absent(),
    this.revision = const Value.absent(),
    this.revisadoPor = const Value.absent(),
    this.revisadoAt = const Value.absent(),
    this.motivoRevision = const Value.absent(),
  });
  ApuntesCompanion.insert({
    this.orden = const Value.absent(),
    required String clave,
    required DateTime hechoAt,
    required String metodo,
    required String ruta,
    required String cuerpo,
    this.provisional = const Value.absent(),
    this.estado = const Value.absent(),
    this.motivo = const Value.absent(),
    this.resueltoAt = const Value.absent(),
    this.intentos = const Value.absent(),
    this.revision = const Value.absent(),
    this.revisadoPor = const Value.absent(),
    this.revisadoAt = const Value.absent(),
    this.motivoRevision = const Value.absent(),
  }) : clave = Value(clave),
       hechoAt = Value(hechoAt),
       metodo = Value(metodo),
       ruta = Value(ruta),
       cuerpo = Value(cuerpo);
  static Insertable<Apunte> custom({
    Expression<int>? orden,
    Expression<String>? clave,
    Expression<DateTime>? hechoAt,
    Expression<String>? metodo,
    Expression<String>? ruta,
    Expression<String>? cuerpo,
    Expression<String>? provisional,
    Expression<String>? estado,
    Expression<String>? motivo,
    Expression<DateTime>? resueltoAt,
    Expression<int>? intentos,
    Expression<String>? revision,
    Expression<String>? revisadoPor,
    Expression<DateTime>? revisadoAt,
    Expression<String>? motivoRevision,
  }) {
    return RawValuesInsertable({
      if (orden != null) 'orden': orden,
      if (clave != null) 'clave': clave,
      if (hechoAt != null) 'hecho_at': hechoAt,
      if (metodo != null) 'metodo': metodo,
      if (ruta != null) 'ruta': ruta,
      if (cuerpo != null) 'cuerpo': cuerpo,
      if (provisional != null) 'provisional': provisional,
      if (estado != null) 'estado': estado,
      if (motivo != null) 'motivo': motivo,
      if (resueltoAt != null) 'resuelto_at': resueltoAt,
      if (intentos != null) 'intentos': intentos,
      if (revision != null) 'revision': revision,
      if (revisadoPor != null) 'revisado_por': revisadoPor,
      if (revisadoAt != null) 'revisado_at': revisadoAt,
      if (motivoRevision != null) 'motivo_revision': motivoRevision,
    });
  }

  ApuntesCompanion copyWith({
    Value<int>? orden,
    Value<String>? clave,
    Value<DateTime>? hechoAt,
    Value<String>? metodo,
    Value<String>? ruta,
    Value<String>? cuerpo,
    Value<String?>? provisional,
    Value<EstadoApunte>? estado,
    Value<String?>? motivo,
    Value<DateTime?>? resueltoAt,
    Value<int>? intentos,
    Value<String?>? revision,
    Value<String?>? revisadoPor,
    Value<DateTime?>? revisadoAt,
    Value<String?>? motivoRevision,
  }) {
    return ApuntesCompanion(
      orden: orden ?? this.orden,
      clave: clave ?? this.clave,
      hechoAt: hechoAt ?? this.hechoAt,
      metodo: metodo ?? this.metodo,
      ruta: ruta ?? this.ruta,
      cuerpo: cuerpo ?? this.cuerpo,
      provisional: provisional ?? this.provisional,
      estado: estado ?? this.estado,
      motivo: motivo ?? this.motivo,
      resueltoAt: resueltoAt ?? this.resueltoAt,
      intentos: intentos ?? this.intentos,
      revision: revision ?? this.revision,
      revisadoPor: revisadoPor ?? this.revisadoPor,
      revisadoAt: revisadoAt ?? this.revisadoAt,
      motivoRevision: motivoRevision ?? this.motivoRevision,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (orden.present) {
      map['orden'] = Variable<int>(orden.value);
    }
    if (clave.present) {
      map['clave'] = Variable<String>(clave.value);
    }
    if (hechoAt.present) {
      map['hecho_at'] = Variable<DateTime>(hechoAt.value);
    }
    if (metodo.present) {
      map['metodo'] = Variable<String>(metodo.value);
    }
    if (ruta.present) {
      map['ruta'] = Variable<String>(ruta.value);
    }
    if (cuerpo.present) {
      map['cuerpo'] = Variable<String>(cuerpo.value);
    }
    if (provisional.present) {
      map['provisional'] = Variable<String>(provisional.value);
    }
    if (estado.present) {
      map['estado'] = Variable<String>(
        $ApuntesTable.$converterestado.toSql(estado.value),
      );
    }
    if (motivo.present) {
      map['motivo'] = Variable<String>(motivo.value);
    }
    if (resueltoAt.present) {
      map['resuelto_at'] = Variable<DateTime>(resueltoAt.value);
    }
    if (intentos.present) {
      map['intentos'] = Variable<int>(intentos.value);
    }
    if (revision.present) {
      map['revision'] = Variable<String>(revision.value);
    }
    if (revisadoPor.present) {
      map['revisado_por'] = Variable<String>(revisadoPor.value);
    }
    if (revisadoAt.present) {
      map['revisado_at'] = Variable<DateTime>(revisadoAt.value);
    }
    if (motivoRevision.present) {
      map['motivo_revision'] = Variable<String>(motivoRevision.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ApuntesCompanion(')
          ..write('orden: $orden, ')
          ..write('clave: $clave, ')
          ..write('hechoAt: $hechoAt, ')
          ..write('metodo: $metodo, ')
          ..write('ruta: $ruta, ')
          ..write('cuerpo: $cuerpo, ')
          ..write('provisional: $provisional, ')
          ..write('estado: $estado, ')
          ..write('motivo: $motivo, ')
          ..write('resueltoAt: $resueltoAt, ')
          ..write('intentos: $intentos, ')
          ..write('revision: $revision, ')
          ..write('revisadoPor: $revisadoPor, ')
          ..write('revisadoAt: $revisadoAt, ')
          ..write('motivoRevision: $motivoRevision')
          ..write(')'))
        .toString();
  }
}

class $EquivalenciasTable extends Equivalencias
    with TableInfo<$EquivalenciasTable, Equivalencia> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EquivalenciasTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _provisionalMeta = const VerificationMeta(
    'provisional',
  );
  @override
  late final GeneratedColumn<String> provisional = GeneratedColumn<String>(
    'provisional',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idRealMeta = const VerificationMeta('idReal');
  @override
  late final GeneratedColumn<String> idReal = GeneratedColumn<String>(
    'real',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<DateTime> at = GeneratedColumn<DateTime>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [provisional, idReal, at];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'equivalencias';
  @override
  VerificationContext validateIntegrity(
    Insertable<Equivalencia> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('provisional')) {
      context.handle(
        _provisionalMeta,
        provisional.isAcceptableOrUnknown(
          data['provisional']!,
          _provisionalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_provisionalMeta);
    }
    if (data.containsKey('real')) {
      context.handle(
        _idRealMeta,
        idReal.isAcceptableOrUnknown(data['real']!, _idRealMeta),
      );
    } else if (isInserting) {
      context.missing(_idRealMeta);
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    } else if (isInserting) {
      context.missing(_atMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {provisional};
  @override
  Equivalencia map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Equivalencia(
      provisional: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provisional'],
      )!,
      idReal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}real'],
      )!,
      at: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}at'],
      )!,
    );
  }

  @override
  $EquivalenciasTable createAlias(String alias) {
    return $EquivalenciasTable(attachedDatabase, alias);
  }
}

class Equivalencia extends DataClass implements Insertable<Equivalencia> {
  final String provisional;

  /// El id de verdad. En Dart se llama `idReal` y en SQL `real`: `real` a secas
  /// choca con `Table.real`, el constructor de columnas de Drift.
  final String idReal;
  final DateTime at;
  const Equivalencia({
    required this.provisional,
    required this.idReal,
    required this.at,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['provisional'] = Variable<String>(provisional);
    map['real'] = Variable<String>(idReal);
    map['at'] = Variable<DateTime>(at);
    return map;
  }

  EquivalenciasCompanion toCompanion(bool nullToAbsent) {
    return EquivalenciasCompanion(
      provisional: Value(provisional),
      idReal: Value(idReal),
      at: Value(at),
    );
  }

  factory Equivalencia.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Equivalencia(
      provisional: serializer.fromJson<String>(json['provisional']),
      idReal: serializer.fromJson<String>(json['idReal']),
      at: serializer.fromJson<DateTime>(json['at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'provisional': serializer.toJson<String>(provisional),
      'idReal': serializer.toJson<String>(idReal),
      'at': serializer.toJson<DateTime>(at),
    };
  }

  Equivalencia copyWith({String? provisional, String? idReal, DateTime? at}) =>
      Equivalencia(
        provisional: provisional ?? this.provisional,
        idReal: idReal ?? this.idReal,
        at: at ?? this.at,
      );
  Equivalencia copyWithCompanion(EquivalenciasCompanion data) {
    return Equivalencia(
      provisional: data.provisional.present
          ? data.provisional.value
          : this.provisional,
      idReal: data.idReal.present ? data.idReal.value : this.idReal,
      at: data.at.present ? data.at.value : this.at,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Equivalencia(')
          ..write('provisional: $provisional, ')
          ..write('idReal: $idReal, ')
          ..write('at: $at')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(provisional, idReal, at);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Equivalencia &&
          other.provisional == this.provisional &&
          other.idReal == this.idReal &&
          other.at == this.at);
}

class EquivalenciasCompanion extends UpdateCompanion<Equivalencia> {
  final Value<String> provisional;
  final Value<String> idReal;
  final Value<DateTime> at;
  final Value<int> rowid;
  const EquivalenciasCompanion({
    this.provisional = const Value.absent(),
    this.idReal = const Value.absent(),
    this.at = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EquivalenciasCompanion.insert({
    required String provisional,
    required String idReal,
    required DateTime at,
    this.rowid = const Value.absent(),
  }) : provisional = Value(provisional),
       idReal = Value(idReal),
       at = Value(at);
  static Insertable<Equivalencia> custom({
    Expression<String>? provisional,
    Expression<String>? idReal,
    Expression<DateTime>? at,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (provisional != null) 'provisional': provisional,
      if (idReal != null) 'real': idReal,
      if (at != null) 'at': at,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EquivalenciasCompanion copyWith({
    Value<String>? provisional,
    Value<String>? idReal,
    Value<DateTime>? at,
    Value<int>? rowid,
  }) {
    return EquivalenciasCompanion(
      provisional: provisional ?? this.provisional,
      idReal: idReal ?? this.idReal,
      at: at ?? this.at,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (provisional.present) {
      map['provisional'] = Variable<String>(provisional.value);
    }
    if (idReal.present) {
      map['real'] = Variable<String>(idReal.value);
    }
    if (at.present) {
      map['at'] = Variable<DateTime>(at.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EquivalenciasCompanion(')
          ..write('provisional: $provisional, ')
          ..write('idReal: $idReal, ')
          ..write('at: $at, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FrescuraTable extends Frescura
    with TableInfo<$FrescuraTable, FilaFrescura> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FrescuraTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _coleccionMeta = const VerificationMeta(
    'coleccion',
  );
  @override
  late final GeneratedColumn<String> coleccion = GeneratedColumn<String>(
    'coleccion',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bajadaAtMeta = const VerificationMeta(
    'bajadaAt',
  );
  @override
  late final GeneratedColumn<DateTime> bajadaAt = GeneratedColumn<DateTime>(
    'bajada_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hastaMeta = const VerificationMeta('hasta');
  @override
  late final GeneratedColumn<String> hasta = GeneratedColumn<String>(
    'hasta',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completaMeta = const VerificationMeta(
    'completa',
  );
  @override
  late final GeneratedColumn<bool> completa = GeneratedColumn<bool>(
    'completa',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completa" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [coleccion, bajadaAt, hasta, completa];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'frescura';
  @override
  VerificationContext validateIntegrity(
    Insertable<FilaFrescura> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('coleccion')) {
      context.handle(
        _coleccionMeta,
        coleccion.isAcceptableOrUnknown(data['coleccion']!, _coleccionMeta),
      );
    } else if (isInserting) {
      context.missing(_coleccionMeta);
    }
    if (data.containsKey('bajada_at')) {
      context.handle(
        _bajadaAtMeta,
        bajadaAt.isAcceptableOrUnknown(data['bajada_at']!, _bajadaAtMeta),
      );
    }
    if (data.containsKey('hasta')) {
      context.handle(
        _hastaMeta,
        hasta.isAcceptableOrUnknown(data['hasta']!, _hastaMeta),
      );
    }
    if (data.containsKey('completa')) {
      context.handle(
        _completaMeta,
        completa.isAcceptableOrUnknown(data['completa']!, _completaMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {coleccion};
  @override
  FilaFrescura map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FilaFrescura(
      coleccion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coleccion'],
      )!,
      bajadaAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}bajada_at'],
      ),
      hasta: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hasta'],
      ),
      completa: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completa'],
      )!,
    );
  }

  @override
  $FrescuraTable createAlias(String alias) {
    return $FrescuraTable(attachedDatabase, alias);
  }
}

class FilaFrescura extends DataClass implements Insertable<FilaFrescura> {
  final String coleccion;
  final DateTime? bajadaAt;

  /// La marca del servidor, TAL CUAL vino, en texto.
  ///
  /// No se parsea ni se recalcula: `hasta` lo pone el servidor y un `DateTime`
  /// de ida y vuelta puede perder precision. Lo unico que hacemos con ella es
  /// devolversela en el siguiente `?desde=`.
  final String? hasta;

  /// `true` si la ultima bajada fue la carga inicial completa.
  final bool completa;
  const FilaFrescura({
    required this.coleccion,
    this.bajadaAt,
    this.hasta,
    required this.completa,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['coleccion'] = Variable<String>(coleccion);
    if (!nullToAbsent || bajadaAt != null) {
      map['bajada_at'] = Variable<DateTime>(bajadaAt);
    }
    if (!nullToAbsent || hasta != null) {
      map['hasta'] = Variable<String>(hasta);
    }
    map['completa'] = Variable<bool>(completa);
    return map;
  }

  FrescuraCompanion toCompanion(bool nullToAbsent) {
    return FrescuraCompanion(
      coleccion: Value(coleccion),
      bajadaAt: bajadaAt == null && nullToAbsent
          ? const Value.absent()
          : Value(bajadaAt),
      hasta: hasta == null && nullToAbsent
          ? const Value.absent()
          : Value(hasta),
      completa: Value(completa),
    );
  }

  factory FilaFrescura.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FilaFrescura(
      coleccion: serializer.fromJson<String>(json['coleccion']),
      bajadaAt: serializer.fromJson<DateTime?>(json['bajadaAt']),
      hasta: serializer.fromJson<String?>(json['hasta']),
      completa: serializer.fromJson<bool>(json['completa']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'coleccion': serializer.toJson<String>(coleccion),
      'bajadaAt': serializer.toJson<DateTime?>(bajadaAt),
      'hasta': serializer.toJson<String?>(hasta),
      'completa': serializer.toJson<bool>(completa),
    };
  }

  FilaFrescura copyWith({
    String? coleccion,
    Value<DateTime?> bajadaAt = const Value.absent(),
    Value<String?> hasta = const Value.absent(),
    bool? completa,
  }) => FilaFrescura(
    coleccion: coleccion ?? this.coleccion,
    bajadaAt: bajadaAt.present ? bajadaAt.value : this.bajadaAt,
    hasta: hasta.present ? hasta.value : this.hasta,
    completa: completa ?? this.completa,
  );
  FilaFrescura copyWithCompanion(FrescuraCompanion data) {
    return FilaFrescura(
      coleccion: data.coleccion.present ? data.coleccion.value : this.coleccion,
      bajadaAt: data.bajadaAt.present ? data.bajadaAt.value : this.bajadaAt,
      hasta: data.hasta.present ? data.hasta.value : this.hasta,
      completa: data.completa.present ? data.completa.value : this.completa,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FilaFrescura(')
          ..write('coleccion: $coleccion, ')
          ..write('bajadaAt: $bajadaAt, ')
          ..write('hasta: $hasta, ')
          ..write('completa: $completa')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(coleccion, bajadaAt, hasta, completa);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FilaFrescura &&
          other.coleccion == this.coleccion &&
          other.bajadaAt == this.bajadaAt &&
          other.hasta == this.hasta &&
          other.completa == this.completa);
}

class FrescuraCompanion extends UpdateCompanion<FilaFrescura> {
  final Value<String> coleccion;
  final Value<DateTime?> bajadaAt;
  final Value<String?> hasta;
  final Value<bool> completa;
  final Value<int> rowid;
  const FrescuraCompanion({
    this.coleccion = const Value.absent(),
    this.bajadaAt = const Value.absent(),
    this.hasta = const Value.absent(),
    this.completa = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FrescuraCompanion.insert({
    required String coleccion,
    this.bajadaAt = const Value.absent(),
    this.hasta = const Value.absent(),
    this.completa = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : coleccion = Value(coleccion);
  static Insertable<FilaFrescura> custom({
    Expression<String>? coleccion,
    Expression<DateTime>? bajadaAt,
    Expression<String>? hasta,
    Expression<bool>? completa,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (coleccion != null) 'coleccion': coleccion,
      if (bajadaAt != null) 'bajada_at': bajadaAt,
      if (hasta != null) 'hasta': hasta,
      if (completa != null) 'completa': completa,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FrescuraCompanion copyWith({
    Value<String>? coleccion,
    Value<DateTime?>? bajadaAt,
    Value<String?>? hasta,
    Value<bool>? completa,
    Value<int>? rowid,
  }) {
    return FrescuraCompanion(
      coleccion: coleccion ?? this.coleccion,
      bajadaAt: bajadaAt ?? this.bajadaAt,
      hasta: hasta ?? this.hasta,
      completa: completa ?? this.completa,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (coleccion.present) {
      map['coleccion'] = Variable<String>(coleccion.value);
    }
    if (bajadaAt.present) {
      map['bajada_at'] = Variable<DateTime>(bajadaAt.value);
    }
    if (hasta.present) {
      map['hasta'] = Variable<String>(hasta.value);
    }
    if (completa.present) {
      map['completa'] = Variable<bool>(completa.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FrescuraCompanion(')
          ..write('coleccion: $coleccion, ')
          ..write('bajadaAt: $bajadaAt, ')
          ..write('hasta: $hasta, ')
          ..write('completa: $completa, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PreferenciasTable extends Preferencias
    with TableInfo<$PreferenciasTable, Preferencia> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PreferenciasTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _claveMeta = const VerificationMeta('clave');
  @override
  late final GeneratedColumn<String> clave = GeneratedColumn<String>(
    'clave',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valorMeta = const VerificationMeta('valor');
  @override
  late final GeneratedColumn<String> valor = GeneratedColumn<String>(
    'valor',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [clave, valor];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'preferencias';
  @override
  VerificationContext validateIntegrity(
    Insertable<Preferencia> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('clave')) {
      context.handle(
        _claveMeta,
        clave.isAcceptableOrUnknown(data['clave']!, _claveMeta),
      );
    } else if (isInserting) {
      context.missing(_claveMeta);
    }
    if (data.containsKey('valor')) {
      context.handle(
        _valorMeta,
        valor.isAcceptableOrUnknown(data['valor']!, _valorMeta),
      );
    } else if (isInserting) {
      context.missing(_valorMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clave};
  @override
  Preferencia map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Preferencia(
      clave: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clave'],
      )!,
      valor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}valor'],
      )!,
    );
  }

  @override
  $PreferenciasTable createAlias(String alias) {
    return $PreferenciasTable(attachedDatabase, alias);
  }
}

class Preferencia extends DataClass implements Insertable<Preferencia> {
  final String clave;
  final String valor;
  const Preferencia({required this.clave, required this.valor});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['clave'] = Variable<String>(clave);
    map['valor'] = Variable<String>(valor);
    return map;
  }

  PreferenciasCompanion toCompanion(bool nullToAbsent) {
    return PreferenciasCompanion(clave: Value(clave), valor: Value(valor));
  }

  factory Preferencia.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Preferencia(
      clave: serializer.fromJson<String>(json['clave']),
      valor: serializer.fromJson<String>(json['valor']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clave': serializer.toJson<String>(clave),
      'valor': serializer.toJson<String>(valor),
    };
  }

  Preferencia copyWith({String? clave, String? valor}) =>
      Preferencia(clave: clave ?? this.clave, valor: valor ?? this.valor);
  Preferencia copyWithCompanion(PreferenciasCompanion data) {
    return Preferencia(
      clave: data.clave.present ? data.clave.value : this.clave,
      valor: data.valor.present ? data.valor.value : this.valor,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Preferencia(')
          ..write('clave: $clave, ')
          ..write('valor: $valor')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(clave, valor);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Preferencia &&
          other.clave == this.clave &&
          other.valor == this.valor);
}

class PreferenciasCompanion extends UpdateCompanion<Preferencia> {
  final Value<String> clave;
  final Value<String> valor;
  final Value<int> rowid;
  const PreferenciasCompanion({
    this.clave = const Value.absent(),
    this.valor = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PreferenciasCompanion.insert({
    required String clave,
    required String valor,
    this.rowid = const Value.absent(),
  }) : clave = Value(clave),
       valor = Value(valor);
  static Insertable<Preferencia> custom({
    Expression<String>? clave,
    Expression<String>? valor,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clave != null) 'clave': clave,
      if (valor != null) 'valor': valor,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PreferenciasCompanion copyWith({
    Value<String>? clave,
    Value<String>? valor,
    Value<int>? rowid,
  }) {
    return PreferenciasCompanion(
      clave: clave ?? this.clave,
      valor: valor ?? this.valor,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clave.present) {
      map['clave'] = Variable<String>(clave.value);
    }
    if (valor.present) {
      map['valor'] = Variable<String>(valor.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PreferenciasCompanion(')
          ..write('clave: $clave, ')
          ..write('valor: $valor, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$BaseLocal extends GeneratedDatabase {
  _$BaseLocal(QueryExecutor e) : super(e);
  $BaseLocalManager get managers => $BaseLocalManager(this);
  late final $BranchesTable branches = $BranchesTable(this);
  late final $VehicleTypesTable vehicleTypes = $VehicleTypesTable(this);
  late final $VehiclesTable vehicles = $VehiclesTable(this);
  late final $ProductsTable products = $ProductsTable(this);
  late final $CustomersTable customers = $CustomersTable(this);
  late final $OrdersTable orders = $OrdersTable(this);
  late final $OrderItemsTable orderItems = $OrderItemsTable(this);
  late final $RoutesTable routes = $RoutesTable(this);
  late final $WarehousesTable warehouses = $WarehousesTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $ApuntesTable apuntes = $ApuntesTable(this);
  late final $EquivalenciasTable equivalencias = $EquivalenciasTable(this);
  late final $FrescuraTable frescura = $FrescuraTable(this);
  late final $PreferenciasTable preferencias = $PreferenciasTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    branches,
    vehicleTypes,
    vehicles,
    products,
    customers,
    orders,
    orderItems,
    routes,
    warehouses,
    settings,
    apuntes,
    equivalencias,
    frescura,
    preferencias,
  ];
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$BranchesTableCreateCompanionBuilder =
    BranchesCompanion Function({
      required String id,
      required String name,
      Value<String?> address,
      required double lat,
      required double lng,
      Value<double> areaKm2,
      Value<String?> externalId,
      Value<bool> originConfigured,
      Value<String?> creadoPor,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<double?> cupRate,
      Value<String?> cupRateFuente,
      Value<DateTime?> cupRateTraidoAt,
      Value<bool?> cupRateFresca,
      Value<int> rowid,
    });
typedef $$BranchesTableUpdateCompanionBuilder =
    BranchesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> address,
      Value<double> lat,
      Value<double> lng,
      Value<double> areaKm2,
      Value<String?> externalId,
      Value<bool> originConfigured,
      Value<String?> creadoPor,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<double?> cupRate,
      Value<String?> cupRateFuente,
      Value<DateTime?> cupRateTraidoAt,
      Value<bool?> cupRateFresca,
      Value<int> rowid,
    });

class $$BranchesTableFilterComposer
    extends Composer<_$BaseLocal, $BranchesTable> {
  $$BranchesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get areaKm2 => $composableBuilder(
    column: $table.areaKm2,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get originConfigured => $composableBuilder(
    column: $table.originConfigured,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get creadoPor => $composableBuilder(
    column: $table.creadoPor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cupRate => $composableBuilder(
    column: $table.cupRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cupRateFuente => $composableBuilder(
    column: $table.cupRateFuente,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cupRateTraidoAt => $composableBuilder(
    column: $table.cupRateTraidoAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get cupRateFresca => $composableBuilder(
    column: $table.cupRateFresca,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BranchesTableOrderingComposer
    extends Composer<_$BaseLocal, $BranchesTable> {
  $$BranchesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get areaKm2 => $composableBuilder(
    column: $table.areaKm2,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get originConfigured => $composableBuilder(
    column: $table.originConfigured,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get creadoPor => $composableBuilder(
    column: $table.creadoPor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cupRate => $composableBuilder(
    column: $table.cupRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cupRateFuente => $composableBuilder(
    column: $table.cupRateFuente,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cupRateTraidoAt => $composableBuilder(
    column: $table.cupRateTraidoAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get cupRateFresca => $composableBuilder(
    column: $table.cupRateFresca,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BranchesTableAnnotationComposer
    extends Composer<_$BaseLocal, $BranchesTable> {
  $$BranchesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lng =>
      $composableBuilder(column: $table.lng, builder: (column) => column);

  GeneratedColumn<double> get areaKm2 =>
      $composableBuilder(column: $table.areaKm2, builder: (column) => column);

  GeneratedColumn<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get originConfigured => $composableBuilder(
    column: $table.originConfigured,
    builder: (column) => column,
  );

  GeneratedColumn<String> get creadoPor =>
      $composableBuilder(column: $table.creadoPor, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<double> get cupRate =>
      $composableBuilder(column: $table.cupRate, builder: (column) => column);

  GeneratedColumn<String> get cupRateFuente => $composableBuilder(
    column: $table.cupRateFuente,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get cupRateTraidoAt => $composableBuilder(
    column: $table.cupRateTraidoAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get cupRateFresca => $composableBuilder(
    column: $table.cupRateFresca,
    builder: (column) => column,
  );
}

class $$BranchesTableTableManager
    extends
        RootTableManager<
          _$BaseLocal,
          $BranchesTable,
          Sucursal,
          $$BranchesTableFilterComposer,
          $$BranchesTableOrderingComposer,
          $$BranchesTableAnnotationComposer,
          $$BranchesTableCreateCompanionBuilder,
          $$BranchesTableUpdateCompanionBuilder,
          (Sucursal, BaseReferences<_$BaseLocal, $BranchesTable, Sucursal>),
          Sucursal,
          PrefetchHooks Function()
        > {
  $$BranchesTableTableManager(_$BaseLocal db, $BranchesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BranchesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BranchesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BranchesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<double> lat = const Value.absent(),
                Value<double> lng = const Value.absent(),
                Value<double> areaKm2 = const Value.absent(),
                Value<String?> externalId = const Value.absent(),
                Value<bool> originConfigured = const Value.absent(),
                Value<String?> creadoPor = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<double?> cupRate = const Value.absent(),
                Value<String?> cupRateFuente = const Value.absent(),
                Value<DateTime?> cupRateTraidoAt = const Value.absent(),
                Value<bool?> cupRateFresca = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BranchesCompanion(
                id: id,
                name: name,
                address: address,
                lat: lat,
                lng: lng,
                areaKm2: areaKm2,
                externalId: externalId,
                originConfigured: originConfigured,
                creadoPor: creadoPor,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cupRate: cupRate,
                cupRateFuente: cupRateFuente,
                cupRateTraidoAt: cupRateTraidoAt,
                cupRateFresca: cupRateFresca,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> address = const Value.absent(),
                required double lat,
                required double lng,
                Value<double> areaKm2 = const Value.absent(),
                Value<String?> externalId = const Value.absent(),
                Value<bool> originConfigured = const Value.absent(),
                Value<String?> creadoPor = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<double?> cupRate = const Value.absent(),
                Value<String?> cupRateFuente = const Value.absent(),
                Value<DateTime?> cupRateTraidoAt = const Value.absent(),
                Value<bool?> cupRateFresca = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BranchesCompanion.insert(
                id: id,
                name: name,
                address: address,
                lat: lat,
                lng: lng,
                areaKm2: areaKm2,
                externalId: externalId,
                originConfigured: originConfigured,
                creadoPor: creadoPor,
                createdAt: createdAt,
                updatedAt: updatedAt,
                cupRate: cupRate,
                cupRateFuente: cupRateFuente,
                cupRateTraidoAt: cupRateTraidoAt,
                cupRateFresca: cupRateFresca,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BranchesTableProcessedTableManager =
    ProcessedTableManager<
      _$BaseLocal,
      $BranchesTable,
      Sucursal,
      $$BranchesTableFilterComposer,
      $$BranchesTableOrderingComposer,
      $$BranchesTableAnnotationComposer,
      $$BranchesTableCreateCompanionBuilder,
      $$BranchesTableUpdateCompanionBuilder,
      (Sucursal, BaseReferences<_$BaseLocal, $BranchesTable, Sucursal>),
      Sucursal,
      PrefetchHooks Function()
    >;
typedef $$VehicleTypesTableCreateCompanionBuilder =
    VehicleTypesCompanion Function({
      required String id,
      required String nombre,
      Value<double?> costoKmUsd,
      Value<bool> activo,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$VehicleTypesTableUpdateCompanionBuilder =
    VehicleTypesCompanion Function({
      Value<String> id,
      Value<String> nombre,
      Value<double?> costoKmUsd,
      Value<bool> activo,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$VehicleTypesTableFilterComposer
    extends Composer<_$BaseLocal, $VehicleTypesTable> {
  $$VehicleTypesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get costoKmUsd => $composableBuilder(
    column: $table.costoKmUsd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get activo => $composableBuilder(
    column: $table.activo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VehicleTypesTableOrderingComposer
    extends Composer<_$BaseLocal, $VehicleTypesTable> {
  $$VehicleTypesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get costoKmUsd => $composableBuilder(
    column: $table.costoKmUsd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get activo => $composableBuilder(
    column: $table.activo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VehicleTypesTableAnnotationComposer
    extends Composer<_$BaseLocal, $VehicleTypesTable> {
  $$VehicleTypesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get nombre =>
      $composableBuilder(column: $table.nombre, builder: (column) => column);

  GeneratedColumn<double> get costoKmUsd => $composableBuilder(
    column: $table.costoKmUsd,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get activo =>
      $composableBuilder(column: $table.activo, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$VehicleTypesTableTableManager
    extends
        RootTableManager<
          _$BaseLocal,
          $VehicleTypesTable,
          TipoVehiculo,
          $$VehicleTypesTableFilterComposer,
          $$VehicleTypesTableOrderingComposer,
          $$VehicleTypesTableAnnotationComposer,
          $$VehicleTypesTableCreateCompanionBuilder,
          $$VehicleTypesTableUpdateCompanionBuilder,
          (
            TipoVehiculo,
            BaseReferences<_$BaseLocal, $VehicleTypesTable, TipoVehiculo>,
          ),
          TipoVehiculo,
          PrefetchHooks Function()
        > {
  $$VehicleTypesTableTableManager(_$BaseLocal db, $VehicleTypesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VehicleTypesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VehicleTypesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VehicleTypesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> nombre = const Value.absent(),
                Value<double?> costoKmUsd = const Value.absent(),
                Value<bool> activo = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VehicleTypesCompanion(
                id: id,
                nombre: nombre,
                costoKmUsd: costoKmUsd,
                activo: activo,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String nombre,
                Value<double?> costoKmUsd = const Value.absent(),
                Value<bool> activo = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VehicleTypesCompanion.insert(
                id: id,
                nombre: nombre,
                costoKmUsd: costoKmUsd,
                activo: activo,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VehicleTypesTableProcessedTableManager =
    ProcessedTableManager<
      _$BaseLocal,
      $VehicleTypesTable,
      TipoVehiculo,
      $$VehicleTypesTableFilterComposer,
      $$VehicleTypesTableOrderingComposer,
      $$VehicleTypesTableAnnotationComposer,
      $$VehicleTypesTableCreateCompanionBuilder,
      $$VehicleTypesTableUpdateCompanionBuilder,
      (
        TipoVehiculo,
        BaseReferences<_$BaseLocal, $VehicleTypesTable, TipoVehiculo>,
      ),
      TipoVehiculo,
      PrefetchHooks Function()
    >;
typedef $$VehiclesTableCreateCompanionBuilder =
    VehiclesCompanion Function({
      required String id,
      required String name,
      Value<String?> vehicleTypeId,
      Value<String?> plate,
      Value<double> capacity,
      Value<double?> costoKmUsd,
      Value<bool> usarParaDomicilio,
      Value<String> status,
      Value<bool> isActive,
      Value<String?> notes,
      Value<String?> branchId,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$VehiclesTableUpdateCompanionBuilder =
    VehiclesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> vehicleTypeId,
      Value<String?> plate,
      Value<double> capacity,
      Value<double?> costoKmUsd,
      Value<bool> usarParaDomicilio,
      Value<String> status,
      Value<bool> isActive,
      Value<String?> notes,
      Value<String?> branchId,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$VehiclesTableFilterComposer
    extends Composer<_$BaseLocal, $VehiclesTable> {
  $$VehiclesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vehicleTypeId => $composableBuilder(
    column: $table.vehicleTypeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plate => $composableBuilder(
    column: $table.plate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get capacity => $composableBuilder(
    column: $table.capacity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get costoKmUsd => $composableBuilder(
    column: $table.costoKmUsd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get usarParaDomicilio => $composableBuilder(
    column: $table.usarParaDomicilio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VehiclesTableOrderingComposer
    extends Composer<_$BaseLocal, $VehiclesTable> {
  $$VehiclesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehicleTypeId => $composableBuilder(
    column: $table.vehicleTypeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plate => $composableBuilder(
    column: $table.plate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get capacity => $composableBuilder(
    column: $table.capacity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get costoKmUsd => $composableBuilder(
    column: $table.costoKmUsd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get usarParaDomicilio => $composableBuilder(
    column: $table.usarParaDomicilio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VehiclesTableAnnotationComposer
    extends Composer<_$BaseLocal, $VehiclesTable> {
  $$VehiclesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get vehicleTypeId => $composableBuilder(
    column: $table.vehicleTypeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get plate =>
      $composableBuilder(column: $table.plate, builder: (column) => column);

  GeneratedColumn<double> get capacity =>
      $composableBuilder(column: $table.capacity, builder: (column) => column);

  GeneratedColumn<double> get costoKmUsd => $composableBuilder(
    column: $table.costoKmUsd,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get usarParaDomicilio => $composableBuilder(
    column: $table.usarParaDomicilio,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$VehiclesTableTableManager
    extends
        RootTableManager<
          _$BaseLocal,
          $VehiclesTable,
          Vehiculo,
          $$VehiclesTableFilterComposer,
          $$VehiclesTableOrderingComposer,
          $$VehiclesTableAnnotationComposer,
          $$VehiclesTableCreateCompanionBuilder,
          $$VehiclesTableUpdateCompanionBuilder,
          (Vehiculo, BaseReferences<_$BaseLocal, $VehiclesTable, Vehiculo>),
          Vehiculo,
          PrefetchHooks Function()
        > {
  $$VehiclesTableTableManager(_$BaseLocal db, $VehiclesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VehiclesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VehiclesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VehiclesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> vehicleTypeId = const Value.absent(),
                Value<String?> plate = const Value.absent(),
                Value<double> capacity = const Value.absent(),
                Value<double?> costoKmUsd = const Value.absent(),
                Value<bool> usarParaDomicilio = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> branchId = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VehiclesCompanion(
                id: id,
                name: name,
                vehicleTypeId: vehicleTypeId,
                plate: plate,
                capacity: capacity,
                costoKmUsd: costoKmUsd,
                usarParaDomicilio: usarParaDomicilio,
                status: status,
                isActive: isActive,
                notes: notes,
                branchId: branchId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> vehicleTypeId = const Value.absent(),
                Value<String?> plate = const Value.absent(),
                Value<double> capacity = const Value.absent(),
                Value<double?> costoKmUsd = const Value.absent(),
                Value<bool> usarParaDomicilio = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> branchId = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VehiclesCompanion.insert(
                id: id,
                name: name,
                vehicleTypeId: vehicleTypeId,
                plate: plate,
                capacity: capacity,
                costoKmUsd: costoKmUsd,
                usarParaDomicilio: usarParaDomicilio,
                status: status,
                isActive: isActive,
                notes: notes,
                branchId: branchId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VehiclesTableProcessedTableManager =
    ProcessedTableManager<
      _$BaseLocal,
      $VehiclesTable,
      Vehiculo,
      $$VehiclesTableFilterComposer,
      $$VehiclesTableOrderingComposer,
      $$VehiclesTableAnnotationComposer,
      $$VehiclesTableCreateCompanionBuilder,
      $$VehiclesTableUpdateCompanionBuilder,
      (Vehiculo, BaseReferences<_$BaseLocal, $VehiclesTable, Vehiculo>),
      Vehiculo,
      PrefetchHooks Function()
    >;
typedef $$ProductsTableCreateCompanionBuilder =
    ProductsCompanion Function({
      required String id,
      required String name,
      Value<double> weight,
      Value<String?> packaging,
      Value<double?> unitsPerPackage,
      Value<String?> category,
      Value<String?> sku,
      Value<String?> sucursalCodigo,
      Value<double?> price,
      Value<double?> stock,
      Value<String?> unit,
      Value<DateTime?> traidoAt,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$ProductsTableUpdateCompanionBuilder =
    ProductsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<double> weight,
      Value<String?> packaging,
      Value<double?> unitsPerPackage,
      Value<String?> category,
      Value<String?> sku,
      Value<String?> sucursalCodigo,
      Value<double?> price,
      Value<double?> stock,
      Value<String?> unit,
      Value<DateTime?> traidoAt,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$ProductsTableFilterComposer
    extends Composer<_$BaseLocal, $ProductsTable> {
  $$ProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packaging => $composableBuilder(
    column: $table.packaging,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get unitsPerPackage => $composableBuilder(
    column: $table.unitsPerPackage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sucursalCodigo => $composableBuilder(
    column: $table.sucursalCodigo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get stock => $composableBuilder(
    column: $table.stock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get traidoAt => $composableBuilder(
    column: $table.traidoAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProductsTableOrderingComposer
    extends Composer<_$BaseLocal, $ProductsTable> {
  $$ProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packaging => $composableBuilder(
    column: $table.packaging,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get unitsPerPackage => $composableBuilder(
    column: $table.unitsPerPackage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sucursalCodigo => $composableBuilder(
    column: $table.sucursalCodigo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get stock => $composableBuilder(
    column: $table.stock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get traidoAt => $composableBuilder(
    column: $table.traidoAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProductsTableAnnotationComposer
    extends Composer<_$BaseLocal, $ProductsTable> {
  $$ProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get weight =>
      $composableBuilder(column: $table.weight, builder: (column) => column);

  GeneratedColumn<String> get packaging =>
      $composableBuilder(column: $table.packaging, builder: (column) => column);

  GeneratedColumn<double> get unitsPerPackage => $composableBuilder(
    column: $table.unitsPerPackage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get sku =>
      $composableBuilder(column: $table.sku, builder: (column) => column);

  GeneratedColumn<String> get sucursalCodigo => $composableBuilder(
    column: $table.sucursalCodigo,
    builder: (column) => column,
  );

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<double> get stock =>
      $composableBuilder(column: $table.stock, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<DateTime> get traidoAt =>
      $composableBuilder(column: $table.traidoAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ProductsTableTableManager
    extends
        RootTableManager<
          _$BaseLocal,
          $ProductsTable,
          Producto,
          $$ProductsTableFilterComposer,
          $$ProductsTableOrderingComposer,
          $$ProductsTableAnnotationComposer,
          $$ProductsTableCreateCompanionBuilder,
          $$ProductsTableUpdateCompanionBuilder,
          (Producto, BaseReferences<_$BaseLocal, $ProductsTable, Producto>),
          Producto,
          PrefetchHooks Function()
        > {
  $$ProductsTableTableManager(_$BaseLocal db, $ProductsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> weight = const Value.absent(),
                Value<String?> packaging = const Value.absent(),
                Value<double?> unitsPerPackage = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<String?> sku = const Value.absent(),
                Value<String?> sucursalCodigo = const Value.absent(),
                Value<double?> price = const Value.absent(),
                Value<double?> stock = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<DateTime?> traidoAt = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductsCompanion(
                id: id,
                name: name,
                weight: weight,
                packaging: packaging,
                unitsPerPackage: unitsPerPackage,
                category: category,
                sku: sku,
                sucursalCodigo: sucursalCodigo,
                price: price,
                stock: stock,
                unit: unit,
                traidoAt: traidoAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<double> weight = const Value.absent(),
                Value<String?> packaging = const Value.absent(),
                Value<double?> unitsPerPackage = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<String?> sku = const Value.absent(),
                Value<String?> sucursalCodigo = const Value.absent(),
                Value<double?> price = const Value.absent(),
                Value<double?> stock = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<DateTime?> traidoAt = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductsCompanion.insert(
                id: id,
                name: name,
                weight: weight,
                packaging: packaging,
                unitsPerPackage: unitsPerPackage,
                category: category,
                sku: sku,
                sucursalCodigo: sucursalCodigo,
                price: price,
                stock: stock,
                unit: unit,
                traidoAt: traidoAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProductsTableProcessedTableManager =
    ProcessedTableManager<
      _$BaseLocal,
      $ProductsTable,
      Producto,
      $$ProductsTableFilterComposer,
      $$ProductsTableOrderingComposer,
      $$ProductsTableAnnotationComposer,
      $$ProductsTableCreateCompanionBuilder,
      $$ProductsTableUpdateCompanionBuilder,
      (Producto, BaseReferences<_$BaseLocal, $ProductsTable, Producto>),
      Producto,
      PrefetchHooks Function()
    >;
typedef $$CustomersTableCreateCompanionBuilder =
    CustomersCompanion Function({
      required String id,
      Value<String?> source,
      Value<String?> externalId,
      required String name,
      Value<String?> phone,
      Value<String?> address,
      Value<String?> municipio,
      Value<String?> zona,
      Value<String?> codigo,
      Value<String?> vendedor,
      required double lat,
      required double lng,
      Value<String?> sucursalCodigo,
      Value<DateTime?> syncedAt,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$CustomersTableUpdateCompanionBuilder =
    CustomersCompanion Function({
      Value<String> id,
      Value<String?> source,
      Value<String?> externalId,
      Value<String> name,
      Value<String?> phone,
      Value<String?> address,
      Value<String?> municipio,
      Value<String?> zona,
      Value<String?> codigo,
      Value<String?> vendedor,
      Value<double> lat,
      Value<double> lng,
      Value<String?> sucursalCodigo,
      Value<DateTime?> syncedAt,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$CustomersTableFilterComposer
    extends Composer<_$BaseLocal, $CustomersTable> {
  $$CustomersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get municipio => $composableBuilder(
    column: $table.municipio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get zona => $composableBuilder(
    column: $table.zona,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vendedor => $composableBuilder(
    column: $table.vendedor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sucursalCodigo => $composableBuilder(
    column: $table.sucursalCodigo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CustomersTableOrderingComposer
    extends Composer<_$BaseLocal, $CustomersTable> {
  $$CustomersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get municipio => $composableBuilder(
    column: $table.municipio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get zona => $composableBuilder(
    column: $table.zona,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get codigo => $composableBuilder(
    column: $table.codigo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vendedor => $composableBuilder(
    column: $table.vendedor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sucursalCodigo => $composableBuilder(
    column: $table.sucursalCodigo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CustomersTableAnnotationComposer
    extends Composer<_$BaseLocal, $CustomersTable> {
  $$CustomersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get municipio =>
      $composableBuilder(column: $table.municipio, builder: (column) => column);

  GeneratedColumn<String> get zona =>
      $composableBuilder(column: $table.zona, builder: (column) => column);

  GeneratedColumn<String> get codigo =>
      $composableBuilder(column: $table.codigo, builder: (column) => column);

  GeneratedColumn<String> get vendedor =>
      $composableBuilder(column: $table.vendedor, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lng =>
      $composableBuilder(column: $table.lng, builder: (column) => column);

  GeneratedColumn<String> get sucursalCodigo => $composableBuilder(
    column: $table.sucursalCodigo,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CustomersTableTableManager
    extends
        RootTableManager<
          _$BaseLocal,
          $CustomersTable,
          Cliente,
          $$CustomersTableFilterComposer,
          $$CustomersTableOrderingComposer,
          $$CustomersTableAnnotationComposer,
          $$CustomersTableCreateCompanionBuilder,
          $$CustomersTableUpdateCompanionBuilder,
          (Cliente, BaseReferences<_$BaseLocal, $CustomersTable, Cliente>),
          Cliente,
          PrefetchHooks Function()
        > {
  $$CustomersTableTableManager(_$BaseLocal db, $CustomersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<String?> externalId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> municipio = const Value.absent(),
                Value<String?> zona = const Value.absent(),
                Value<String?> codigo = const Value.absent(),
                Value<String?> vendedor = const Value.absent(),
                Value<double> lat = const Value.absent(),
                Value<double> lng = const Value.absent(),
                Value<String?> sucursalCodigo = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomersCompanion(
                id: id,
                source: source,
                externalId: externalId,
                name: name,
                phone: phone,
                address: address,
                municipio: municipio,
                zona: zona,
                codigo: codigo,
                vendedor: vendedor,
                lat: lat,
                lng: lng,
                sucursalCodigo: sucursalCodigo,
                syncedAt: syncedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> source = const Value.absent(),
                Value<String?> externalId = const Value.absent(),
                required String name,
                Value<String?> phone = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> municipio = const Value.absent(),
                Value<String?> zona = const Value.absent(),
                Value<String?> codigo = const Value.absent(),
                Value<String?> vendedor = const Value.absent(),
                required double lat,
                required double lng,
                Value<String?> sucursalCodigo = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomersCompanion.insert(
                id: id,
                source: source,
                externalId: externalId,
                name: name,
                phone: phone,
                address: address,
                municipio: municipio,
                zona: zona,
                codigo: codigo,
                vendedor: vendedor,
                lat: lat,
                lng: lng,
                sucursalCodigo: sucursalCodigo,
                syncedAt: syncedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CustomersTableProcessedTableManager =
    ProcessedTableManager<
      _$BaseLocal,
      $CustomersTable,
      Cliente,
      $$CustomersTableFilterComposer,
      $$CustomersTableOrderingComposer,
      $$CustomersTableAnnotationComposer,
      $$CustomersTableCreateCompanionBuilder,
      $$CustomersTableUpdateCompanionBuilder,
      (Cliente, BaseReferences<_$BaseLocal, $CustomersTable, Cliente>),
      Cliente,
      PrefetchHooks Function()
    >;
typedef $$OrdersTableCreateCompanionBuilder =
    OrdersCompanion Function({
      required String id,
      Value<String?> operationNumber,
      required String customerName,
      required String address,
      Value<String?> endAddress,
      Value<double?> endLat,
      Value<double?> endLng,
      Value<double?> lat,
      Value<double?> lng,
      Value<double> weight,
      Value<String> status,
      Value<String> tripLeg,
      Value<String?> notes,
      Value<String?> routeId,
      Value<String?> ultimaRutaId,
      Value<double?> price,
      Value<double?> segmentKm,
      Value<double?> deliveryPrice,
      Value<double?> deliveryDistanceKm,
      Value<String?> branchId,
      Value<String?> source,
      Value<String?> externalId,
      Value<DateTime?> orderDate,
      Value<DateTime?> pedidoUpdatedAt,
      Value<String?> estado,
      Value<bool> archivado,
      Value<DateTime?> fechaComprometida,
      Value<bool?> requiereDomicilio,
      Value<double?> pedidoCosto,
      Value<String?> municipio,
      Value<String?> vendedor,
      Value<String?> sucursalCodigo,
      Value<String?> facturaEstado,
      Value<String?> facturaNumero,
      Value<DateTime?> facturaAt,
      Value<double?> facturaDomicilio,
      Value<DateTime?> facturaCorregidoAt,
      Value<String?> itemsOrigen,
      Value<String?> customerPhone,
      Value<int?> stopOrder,
      Value<DateTime?> deliveredAt,
      Value<String?> resultado,
      Value<DateTime?> resultadoAt,
      Value<String?> resultadoNota,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$OrdersTableUpdateCompanionBuilder =
    OrdersCompanion Function({
      Value<String> id,
      Value<String?> operationNumber,
      Value<String> customerName,
      Value<String> address,
      Value<String?> endAddress,
      Value<double?> endLat,
      Value<double?> endLng,
      Value<double?> lat,
      Value<double?> lng,
      Value<double> weight,
      Value<String> status,
      Value<String> tripLeg,
      Value<String?> notes,
      Value<String?> routeId,
      Value<String?> ultimaRutaId,
      Value<double?> price,
      Value<double?> segmentKm,
      Value<double?> deliveryPrice,
      Value<double?> deliveryDistanceKm,
      Value<String?> branchId,
      Value<String?> source,
      Value<String?> externalId,
      Value<DateTime?> orderDate,
      Value<DateTime?> pedidoUpdatedAt,
      Value<String?> estado,
      Value<bool> archivado,
      Value<DateTime?> fechaComprometida,
      Value<bool?> requiereDomicilio,
      Value<double?> pedidoCosto,
      Value<String?> municipio,
      Value<String?> vendedor,
      Value<String?> sucursalCodigo,
      Value<String?> facturaEstado,
      Value<String?> facturaNumero,
      Value<DateTime?> facturaAt,
      Value<double?> facturaDomicilio,
      Value<DateTime?> facturaCorregidoAt,
      Value<String?> itemsOrigen,
      Value<String?> customerPhone,
      Value<int?> stopOrder,
      Value<DateTime?> deliveredAt,
      Value<String?> resultado,
      Value<DateTime?> resultadoAt,
      Value<String?> resultadoNota,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$OrdersTableFilterComposer extends Composer<_$BaseLocal, $OrdersTable> {
  $$OrdersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationNumber => $composableBuilder(
    column: $table.operationNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerName => $composableBuilder(
    column: $table.customerName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endAddress => $composableBuilder(
    column: $table.endAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get endLat => $composableBuilder(
    column: $table.endLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get endLng => $composableBuilder(
    column: $table.endLng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tripLeg => $composableBuilder(
    column: $table.tripLeg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get routeId => $composableBuilder(
    column: $table.routeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ultimaRutaId => $composableBuilder(
    column: $table.ultimaRutaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get segmentKm => $composableBuilder(
    column: $table.segmentKm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get deliveryPrice => $composableBuilder(
    column: $table.deliveryPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get deliveryDistanceKm => $composableBuilder(
    column: $table.deliveryDistanceKm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get orderDate => $composableBuilder(
    column: $table.orderDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get pedidoUpdatedAt => $composableBuilder(
    column: $table.pedidoUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get estado => $composableBuilder(
    column: $table.estado,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archivado => $composableBuilder(
    column: $table.archivado,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fechaComprometida => $composableBuilder(
    column: $table.fechaComprometida,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get requiereDomicilio => $composableBuilder(
    column: $table.requiereDomicilio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pedidoCosto => $composableBuilder(
    column: $table.pedidoCosto,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get municipio => $composableBuilder(
    column: $table.municipio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vendedor => $composableBuilder(
    column: $table.vendedor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sucursalCodigo => $composableBuilder(
    column: $table.sucursalCodigo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get facturaEstado => $composableBuilder(
    column: $table.facturaEstado,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get facturaNumero => $composableBuilder(
    column: $table.facturaNumero,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get facturaAt => $composableBuilder(
    column: $table.facturaAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get facturaDomicilio => $composableBuilder(
    column: $table.facturaDomicilio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get facturaCorregidoAt => $composableBuilder(
    column: $table.facturaCorregidoAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemsOrigen => $composableBuilder(
    column: $table.itemsOrigen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerPhone => $composableBuilder(
    column: $table.customerPhone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stopOrder => $composableBuilder(
    column: $table.stopOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resultado => $composableBuilder(
    column: $table.resultado,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get resultadoAt => $composableBuilder(
    column: $table.resultadoAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resultadoNota => $composableBuilder(
    column: $table.resultadoNota,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OrdersTableOrderingComposer
    extends Composer<_$BaseLocal, $OrdersTable> {
  $$OrdersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationNumber => $composableBuilder(
    column: $table.operationNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerName => $composableBuilder(
    column: $table.customerName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endAddress => $composableBuilder(
    column: $table.endAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get endLat => $composableBuilder(
    column: $table.endLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get endLng => $composableBuilder(
    column: $table.endLng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tripLeg => $composableBuilder(
    column: $table.tripLeg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get routeId => $composableBuilder(
    column: $table.routeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ultimaRutaId => $composableBuilder(
    column: $table.ultimaRutaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get segmentKm => $composableBuilder(
    column: $table.segmentKm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get deliveryPrice => $composableBuilder(
    column: $table.deliveryPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get deliveryDistanceKm => $composableBuilder(
    column: $table.deliveryDistanceKm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get orderDate => $composableBuilder(
    column: $table.orderDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get pedidoUpdatedAt => $composableBuilder(
    column: $table.pedidoUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get estado => $composableBuilder(
    column: $table.estado,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archivado => $composableBuilder(
    column: $table.archivado,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fechaComprometida => $composableBuilder(
    column: $table.fechaComprometida,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get requiereDomicilio => $composableBuilder(
    column: $table.requiereDomicilio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pedidoCosto => $composableBuilder(
    column: $table.pedidoCosto,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get municipio => $composableBuilder(
    column: $table.municipio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vendedor => $composableBuilder(
    column: $table.vendedor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sucursalCodigo => $composableBuilder(
    column: $table.sucursalCodigo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get facturaEstado => $composableBuilder(
    column: $table.facturaEstado,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get facturaNumero => $composableBuilder(
    column: $table.facturaNumero,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get facturaAt => $composableBuilder(
    column: $table.facturaAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get facturaDomicilio => $composableBuilder(
    column: $table.facturaDomicilio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get facturaCorregidoAt => $composableBuilder(
    column: $table.facturaCorregidoAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemsOrigen => $composableBuilder(
    column: $table.itemsOrigen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerPhone => $composableBuilder(
    column: $table.customerPhone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stopOrder => $composableBuilder(
    column: $table.stopOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resultado => $composableBuilder(
    column: $table.resultado,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get resultadoAt => $composableBuilder(
    column: $table.resultadoAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resultadoNota => $composableBuilder(
    column: $table.resultadoNota,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OrdersTableAnnotationComposer
    extends Composer<_$BaseLocal, $OrdersTable> {
  $$OrdersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get operationNumber => $composableBuilder(
    column: $table.operationNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customerName => $composableBuilder(
    column: $table.customerName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get endAddress => $composableBuilder(
    column: $table.endAddress,
    builder: (column) => column,
  );

  GeneratedColumn<double> get endLat =>
      $composableBuilder(column: $table.endLat, builder: (column) => column);

  GeneratedColumn<double> get endLng =>
      $composableBuilder(column: $table.endLng, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lng =>
      $composableBuilder(column: $table.lng, builder: (column) => column);

  GeneratedColumn<double> get weight =>
      $composableBuilder(column: $table.weight, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get tripLeg =>
      $composableBuilder(column: $table.tripLeg, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get routeId =>
      $composableBuilder(column: $table.routeId, builder: (column) => column);

  GeneratedColumn<String> get ultimaRutaId => $composableBuilder(
    column: $table.ultimaRutaId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<double> get segmentKm =>
      $composableBuilder(column: $table.segmentKm, builder: (column) => column);

  GeneratedColumn<double> get deliveryPrice => $composableBuilder(
    column: $table.deliveryPrice,
    builder: (column) => column,
  );

  GeneratedColumn<double> get deliveryDistanceKm => $composableBuilder(
    column: $table.deliveryDistanceKm,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get externalId => $composableBuilder(
    column: $table.externalId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get orderDate =>
      $composableBuilder(column: $table.orderDate, builder: (column) => column);

  GeneratedColumn<DateTime> get pedidoUpdatedAt => $composableBuilder(
    column: $table.pedidoUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get estado =>
      $composableBuilder(column: $table.estado, builder: (column) => column);

  GeneratedColumn<bool> get archivado =>
      $composableBuilder(column: $table.archivado, builder: (column) => column);

  GeneratedColumn<DateTime> get fechaComprometida => $composableBuilder(
    column: $table.fechaComprometida,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get requiereDomicilio => $composableBuilder(
    column: $table.requiereDomicilio,
    builder: (column) => column,
  );

  GeneratedColumn<double> get pedidoCosto => $composableBuilder(
    column: $table.pedidoCosto,
    builder: (column) => column,
  );

  GeneratedColumn<String> get municipio =>
      $composableBuilder(column: $table.municipio, builder: (column) => column);

  GeneratedColumn<String> get vendedor =>
      $composableBuilder(column: $table.vendedor, builder: (column) => column);

  GeneratedColumn<String> get sucursalCodigo => $composableBuilder(
    column: $table.sucursalCodigo,
    builder: (column) => column,
  );

  GeneratedColumn<String> get facturaEstado => $composableBuilder(
    column: $table.facturaEstado,
    builder: (column) => column,
  );

  GeneratedColumn<String> get facturaNumero => $composableBuilder(
    column: $table.facturaNumero,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get facturaAt =>
      $composableBuilder(column: $table.facturaAt, builder: (column) => column);

  GeneratedColumn<double> get facturaDomicilio => $composableBuilder(
    column: $table.facturaDomicilio,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get facturaCorregidoAt => $composableBuilder(
    column: $table.facturaCorregidoAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get itemsOrigen => $composableBuilder(
    column: $table.itemsOrigen,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customerPhone => $composableBuilder(
    column: $table.customerPhone,
    builder: (column) => column,
  );

  GeneratedColumn<int> get stopOrder =>
      $composableBuilder(column: $table.stopOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resultado =>
      $composableBuilder(column: $table.resultado, builder: (column) => column);

  GeneratedColumn<DateTime> get resultadoAt => $composableBuilder(
    column: $table.resultadoAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resultadoNota => $composableBuilder(
    column: $table.resultadoNota,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$OrdersTableTableManager
    extends
        RootTableManager<
          _$BaseLocal,
          $OrdersTable,
          Pedido,
          $$OrdersTableFilterComposer,
          $$OrdersTableOrderingComposer,
          $$OrdersTableAnnotationComposer,
          $$OrdersTableCreateCompanionBuilder,
          $$OrdersTableUpdateCompanionBuilder,
          (Pedido, BaseReferences<_$BaseLocal, $OrdersTable, Pedido>),
          Pedido,
          PrefetchHooks Function()
        > {
  $$OrdersTableTableManager(_$BaseLocal db, $OrdersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OrdersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OrdersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OrdersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> operationNumber = const Value.absent(),
                Value<String> customerName = const Value.absent(),
                Value<String> address = const Value.absent(),
                Value<String?> endAddress = const Value.absent(),
                Value<double?> endLat = const Value.absent(),
                Value<double?> endLng = const Value.absent(),
                Value<double?> lat = const Value.absent(),
                Value<double?> lng = const Value.absent(),
                Value<double> weight = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> tripLeg = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> routeId = const Value.absent(),
                Value<String?> ultimaRutaId = const Value.absent(),
                Value<double?> price = const Value.absent(),
                Value<double?> segmentKm = const Value.absent(),
                Value<double?> deliveryPrice = const Value.absent(),
                Value<double?> deliveryDistanceKm = const Value.absent(),
                Value<String?> branchId = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<String?> externalId = const Value.absent(),
                Value<DateTime?> orderDate = const Value.absent(),
                Value<DateTime?> pedidoUpdatedAt = const Value.absent(),
                Value<String?> estado = const Value.absent(),
                Value<bool> archivado = const Value.absent(),
                Value<DateTime?> fechaComprometida = const Value.absent(),
                Value<bool?> requiereDomicilio = const Value.absent(),
                Value<double?> pedidoCosto = const Value.absent(),
                Value<String?> municipio = const Value.absent(),
                Value<String?> vendedor = const Value.absent(),
                Value<String?> sucursalCodigo = const Value.absent(),
                Value<String?> facturaEstado = const Value.absent(),
                Value<String?> facturaNumero = const Value.absent(),
                Value<DateTime?> facturaAt = const Value.absent(),
                Value<double?> facturaDomicilio = const Value.absent(),
                Value<DateTime?> facturaCorregidoAt = const Value.absent(),
                Value<String?> itemsOrigen = const Value.absent(),
                Value<String?> customerPhone = const Value.absent(),
                Value<int?> stopOrder = const Value.absent(),
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<String?> resultado = const Value.absent(),
                Value<DateTime?> resultadoAt = const Value.absent(),
                Value<String?> resultadoNota = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OrdersCompanion(
                id: id,
                operationNumber: operationNumber,
                customerName: customerName,
                address: address,
                endAddress: endAddress,
                endLat: endLat,
                endLng: endLng,
                lat: lat,
                lng: lng,
                weight: weight,
                status: status,
                tripLeg: tripLeg,
                notes: notes,
                routeId: routeId,
                ultimaRutaId: ultimaRutaId,
                price: price,
                segmentKm: segmentKm,
                deliveryPrice: deliveryPrice,
                deliveryDistanceKm: deliveryDistanceKm,
                branchId: branchId,
                source: source,
                externalId: externalId,
                orderDate: orderDate,
                pedidoUpdatedAt: pedidoUpdatedAt,
                estado: estado,
                archivado: archivado,
                fechaComprometida: fechaComprometida,
                requiereDomicilio: requiereDomicilio,
                pedidoCosto: pedidoCosto,
                municipio: municipio,
                vendedor: vendedor,
                sucursalCodigo: sucursalCodigo,
                facturaEstado: facturaEstado,
                facturaNumero: facturaNumero,
                facturaAt: facturaAt,
                facturaDomicilio: facturaDomicilio,
                facturaCorregidoAt: facturaCorregidoAt,
                itemsOrigen: itemsOrigen,
                customerPhone: customerPhone,
                stopOrder: stopOrder,
                deliveredAt: deliveredAt,
                resultado: resultado,
                resultadoAt: resultadoAt,
                resultadoNota: resultadoNota,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> operationNumber = const Value.absent(),
                required String customerName,
                required String address,
                Value<String?> endAddress = const Value.absent(),
                Value<double?> endLat = const Value.absent(),
                Value<double?> endLng = const Value.absent(),
                Value<double?> lat = const Value.absent(),
                Value<double?> lng = const Value.absent(),
                Value<double> weight = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> tripLeg = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> routeId = const Value.absent(),
                Value<String?> ultimaRutaId = const Value.absent(),
                Value<double?> price = const Value.absent(),
                Value<double?> segmentKm = const Value.absent(),
                Value<double?> deliveryPrice = const Value.absent(),
                Value<double?> deliveryDistanceKm = const Value.absent(),
                Value<String?> branchId = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<String?> externalId = const Value.absent(),
                Value<DateTime?> orderDate = const Value.absent(),
                Value<DateTime?> pedidoUpdatedAt = const Value.absent(),
                Value<String?> estado = const Value.absent(),
                Value<bool> archivado = const Value.absent(),
                Value<DateTime?> fechaComprometida = const Value.absent(),
                Value<bool?> requiereDomicilio = const Value.absent(),
                Value<double?> pedidoCosto = const Value.absent(),
                Value<String?> municipio = const Value.absent(),
                Value<String?> vendedor = const Value.absent(),
                Value<String?> sucursalCodigo = const Value.absent(),
                Value<String?> facturaEstado = const Value.absent(),
                Value<String?> facturaNumero = const Value.absent(),
                Value<DateTime?> facturaAt = const Value.absent(),
                Value<double?> facturaDomicilio = const Value.absent(),
                Value<DateTime?> facturaCorregidoAt = const Value.absent(),
                Value<String?> itemsOrigen = const Value.absent(),
                Value<String?> customerPhone = const Value.absent(),
                Value<int?> stopOrder = const Value.absent(),
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<String?> resultado = const Value.absent(),
                Value<DateTime?> resultadoAt = const Value.absent(),
                Value<String?> resultadoNota = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OrdersCompanion.insert(
                id: id,
                operationNumber: operationNumber,
                customerName: customerName,
                address: address,
                endAddress: endAddress,
                endLat: endLat,
                endLng: endLng,
                lat: lat,
                lng: lng,
                weight: weight,
                status: status,
                tripLeg: tripLeg,
                notes: notes,
                routeId: routeId,
                ultimaRutaId: ultimaRutaId,
                price: price,
                segmentKm: segmentKm,
                deliveryPrice: deliveryPrice,
                deliveryDistanceKm: deliveryDistanceKm,
                branchId: branchId,
                source: source,
                externalId: externalId,
                orderDate: orderDate,
                pedidoUpdatedAt: pedidoUpdatedAt,
                estado: estado,
                archivado: archivado,
                fechaComprometida: fechaComprometida,
                requiereDomicilio: requiereDomicilio,
                pedidoCosto: pedidoCosto,
                municipio: municipio,
                vendedor: vendedor,
                sucursalCodigo: sucursalCodigo,
                facturaEstado: facturaEstado,
                facturaNumero: facturaNumero,
                facturaAt: facturaAt,
                facturaDomicilio: facturaDomicilio,
                facturaCorregidoAt: facturaCorregidoAt,
                itemsOrigen: itemsOrigen,
                customerPhone: customerPhone,
                stopOrder: stopOrder,
                deliveredAt: deliveredAt,
                resultado: resultado,
                resultadoAt: resultadoAt,
                resultadoNota: resultadoNota,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OrdersTableProcessedTableManager =
    ProcessedTableManager<
      _$BaseLocal,
      $OrdersTable,
      Pedido,
      $$OrdersTableFilterComposer,
      $$OrdersTableOrderingComposer,
      $$OrdersTableAnnotationComposer,
      $$OrdersTableCreateCompanionBuilder,
      $$OrdersTableUpdateCompanionBuilder,
      (Pedido, BaseReferences<_$BaseLocal, $OrdersTable, Pedido>),
      Pedido,
      PrefetchHooks Function()
    >;
typedef $$OrderItemsTableCreateCompanionBuilder =
    OrderItemsCompanion Function({
      required String id,
      required String orderId,
      required int linea,
      required String description,
      required double quantity,
      Value<double?> packs,
      Value<double?> pesoKg,
      Value<double?> pesoLineaKg,
      Value<String?> productId,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$OrderItemsTableUpdateCompanionBuilder =
    OrderItemsCompanion Function({
      Value<String> id,
      Value<String> orderId,
      Value<int> linea,
      Value<String> description,
      Value<double> quantity,
      Value<double?> packs,
      Value<double?> pesoKg,
      Value<double?> pesoLineaKg,
      Value<String?> productId,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$OrderItemsTableFilterComposer
    extends Composer<_$BaseLocal, $OrderItemsTable> {
  $$OrderItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get linea => $composableBuilder(
    column: $table.linea,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get packs => $composableBuilder(
    column: $table.packs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pesoKg => $composableBuilder(
    column: $table.pesoKg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pesoLineaKg => $composableBuilder(
    column: $table.pesoLineaKg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OrderItemsTableOrderingComposer
    extends Composer<_$BaseLocal, $OrderItemsTable> {
  $$OrderItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get linea => $composableBuilder(
    column: $table.linea,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get packs => $composableBuilder(
    column: $table.packs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pesoKg => $composableBuilder(
    column: $table.pesoKg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pesoLineaKg => $composableBuilder(
    column: $table.pesoLineaKg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OrderItemsTableAnnotationComposer
    extends Composer<_$BaseLocal, $OrderItemsTable> {
  $$OrderItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orderId =>
      $composableBuilder(column: $table.orderId, builder: (column) => column);

  GeneratedColumn<int> get linea =>
      $composableBuilder(column: $table.linea, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<double> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<double> get packs =>
      $composableBuilder(column: $table.packs, builder: (column) => column);

  GeneratedColumn<double> get pesoKg =>
      $composableBuilder(column: $table.pesoKg, builder: (column) => column);

  GeneratedColumn<double> get pesoLineaKg => $composableBuilder(
    column: $table.pesoLineaKg,
    builder: (column) => column,
  );

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$OrderItemsTableTableManager
    extends
        RootTableManager<
          _$BaseLocal,
          $OrderItemsTable,
          RenglonPedido,
          $$OrderItemsTableFilterComposer,
          $$OrderItemsTableOrderingComposer,
          $$OrderItemsTableAnnotationComposer,
          $$OrderItemsTableCreateCompanionBuilder,
          $$OrderItemsTableUpdateCompanionBuilder,
          (
            RenglonPedido,
            BaseReferences<_$BaseLocal, $OrderItemsTable, RenglonPedido>,
          ),
          RenglonPedido,
          PrefetchHooks Function()
        > {
  $$OrderItemsTableTableManager(_$BaseLocal db, $OrderItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OrderItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OrderItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OrderItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orderId = const Value.absent(),
                Value<int> linea = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<double> quantity = const Value.absent(),
                Value<double?> packs = const Value.absent(),
                Value<double?> pesoKg = const Value.absent(),
                Value<double?> pesoLineaKg = const Value.absent(),
                Value<String?> productId = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OrderItemsCompanion(
                id: id,
                orderId: orderId,
                linea: linea,
                description: description,
                quantity: quantity,
                packs: packs,
                pesoKg: pesoKg,
                pesoLineaKg: pesoLineaKg,
                productId: productId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orderId,
                required int linea,
                required String description,
                required double quantity,
                Value<double?> packs = const Value.absent(),
                Value<double?> pesoKg = const Value.absent(),
                Value<double?> pesoLineaKg = const Value.absent(),
                Value<String?> productId = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OrderItemsCompanion.insert(
                id: id,
                orderId: orderId,
                linea: linea,
                description: description,
                quantity: quantity,
                packs: packs,
                pesoKg: pesoKg,
                pesoLineaKg: pesoLineaKg,
                productId: productId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OrderItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$BaseLocal,
      $OrderItemsTable,
      RenglonPedido,
      $$OrderItemsTableFilterComposer,
      $$OrderItemsTableOrderingComposer,
      $$OrderItemsTableAnnotationComposer,
      $$OrderItemsTableCreateCompanionBuilder,
      $$OrderItemsTableUpdateCompanionBuilder,
      (
        RenglonPedido,
        BaseReferences<_$BaseLocal, $OrderItemsTable, RenglonPedido>,
      ),
      RenglonPedido,
      PrefetchHooks Function()
    >;
typedef $$RoutesTableCreateCompanionBuilder =
    RoutesCompanion Function({
      required String id,
      Value<String?> name,
      Value<String?> routeCode,
      Value<String> status,
      Value<String?> originAddress,
      Value<double?> originLat,
      Value<double?> originLng,
      Value<double> totalDistance,
      Value<double> totalWeight,
      Value<double> totalPrice,
      Value<DateTime?> deliveryDate,
      Value<String?> vehicleId,
      Value<String?> creadoPor,
      Value<String?> branchId,
      Value<DateTime?> startedAt,
      Value<DateTime?> finishedAt,
      Value<bool> optimized,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$RoutesTableUpdateCompanionBuilder =
    RoutesCompanion Function({
      Value<String> id,
      Value<String?> name,
      Value<String?> routeCode,
      Value<String> status,
      Value<String?> originAddress,
      Value<double?> originLat,
      Value<double?> originLng,
      Value<double> totalDistance,
      Value<double> totalWeight,
      Value<double> totalPrice,
      Value<DateTime?> deliveryDate,
      Value<String?> vehicleId,
      Value<String?> creadoPor,
      Value<String?> branchId,
      Value<DateTime?> startedAt,
      Value<DateTime?> finishedAt,
      Value<bool> optimized,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$RoutesTableFilterComposer extends Composer<_$BaseLocal, $RoutesTable> {
  $$RoutesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get routeCode => $composableBuilder(
    column: $table.routeCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originAddress => $composableBuilder(
    column: $table.originAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get originLat => $composableBuilder(
    column: $table.originLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get originLng => $composableBuilder(
    column: $table.originLng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalDistance => $composableBuilder(
    column: $table.totalDistance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalWeight => $composableBuilder(
    column: $table.totalWeight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalPrice => $composableBuilder(
    column: $table.totalPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deliveryDate => $composableBuilder(
    column: $table.deliveryDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vehicleId => $composableBuilder(
    column: $table.vehicleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get creadoPor => $composableBuilder(
    column: $table.creadoPor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get optimized => $composableBuilder(
    column: $table.optimized,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RoutesTableOrderingComposer
    extends Composer<_$BaseLocal, $RoutesTable> {
  $$RoutesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get routeCode => $composableBuilder(
    column: $table.routeCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originAddress => $composableBuilder(
    column: $table.originAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get originLat => $composableBuilder(
    column: $table.originLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get originLng => $composableBuilder(
    column: $table.originLng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalDistance => $composableBuilder(
    column: $table.totalDistance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalWeight => $composableBuilder(
    column: $table.totalWeight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalPrice => $composableBuilder(
    column: $table.totalPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deliveryDate => $composableBuilder(
    column: $table.deliveryDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehicleId => $composableBuilder(
    column: $table.vehicleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get creadoPor => $composableBuilder(
    column: $table.creadoPor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get optimized => $composableBuilder(
    column: $table.optimized,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RoutesTableAnnotationComposer
    extends Composer<_$BaseLocal, $RoutesTable> {
  $$RoutesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get routeCode =>
      $composableBuilder(column: $table.routeCode, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get originAddress => $composableBuilder(
    column: $table.originAddress,
    builder: (column) => column,
  );

  GeneratedColumn<double> get originLat =>
      $composableBuilder(column: $table.originLat, builder: (column) => column);

  GeneratedColumn<double> get originLng =>
      $composableBuilder(column: $table.originLng, builder: (column) => column);

  GeneratedColumn<double> get totalDistance => $composableBuilder(
    column: $table.totalDistance,
    builder: (column) => column,
  );

  GeneratedColumn<double> get totalWeight => $composableBuilder(
    column: $table.totalWeight,
    builder: (column) => column,
  );

  GeneratedColumn<double> get totalPrice => $composableBuilder(
    column: $table.totalPrice,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deliveryDate => $composableBuilder(
    column: $table.deliveryDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get vehicleId =>
      $composableBuilder(column: $table.vehicleId, builder: (column) => column);

  GeneratedColumn<String> get creadoPor =>
      $composableBuilder(column: $table.creadoPor, builder: (column) => column);

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get optimized =>
      $composableBuilder(column: $table.optimized, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RoutesTableTableManager
    extends
        RootTableManager<
          _$BaseLocal,
          $RoutesTable,
          Ruta,
          $$RoutesTableFilterComposer,
          $$RoutesTableOrderingComposer,
          $$RoutesTableAnnotationComposer,
          $$RoutesTableCreateCompanionBuilder,
          $$RoutesTableUpdateCompanionBuilder,
          (Ruta, BaseReferences<_$BaseLocal, $RoutesTable, Ruta>),
          Ruta,
          PrefetchHooks Function()
        > {
  $$RoutesTableTableManager(_$BaseLocal db, $RoutesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoutesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoutesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoutesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<String?> routeCode = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> originAddress = const Value.absent(),
                Value<double?> originLat = const Value.absent(),
                Value<double?> originLng = const Value.absent(),
                Value<double> totalDistance = const Value.absent(),
                Value<double> totalWeight = const Value.absent(),
                Value<double> totalPrice = const Value.absent(),
                Value<DateTime?> deliveryDate = const Value.absent(),
                Value<String?> vehicleId = const Value.absent(),
                Value<String?> creadoPor = const Value.absent(),
                Value<String?> branchId = const Value.absent(),
                Value<DateTime?> startedAt = const Value.absent(),
                Value<DateTime?> finishedAt = const Value.absent(),
                Value<bool> optimized = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoutesCompanion(
                id: id,
                name: name,
                routeCode: routeCode,
                status: status,
                originAddress: originAddress,
                originLat: originLat,
                originLng: originLng,
                totalDistance: totalDistance,
                totalWeight: totalWeight,
                totalPrice: totalPrice,
                deliveryDate: deliveryDate,
                vehicleId: vehicleId,
                creadoPor: creadoPor,
                branchId: branchId,
                startedAt: startedAt,
                finishedAt: finishedAt,
                optimized: optimized,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> name = const Value.absent(),
                Value<String?> routeCode = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> originAddress = const Value.absent(),
                Value<double?> originLat = const Value.absent(),
                Value<double?> originLng = const Value.absent(),
                Value<double> totalDistance = const Value.absent(),
                Value<double> totalWeight = const Value.absent(),
                Value<double> totalPrice = const Value.absent(),
                Value<DateTime?> deliveryDate = const Value.absent(),
                Value<String?> vehicleId = const Value.absent(),
                Value<String?> creadoPor = const Value.absent(),
                Value<String?> branchId = const Value.absent(),
                Value<DateTime?> startedAt = const Value.absent(),
                Value<DateTime?> finishedAt = const Value.absent(),
                Value<bool> optimized = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoutesCompanion.insert(
                id: id,
                name: name,
                routeCode: routeCode,
                status: status,
                originAddress: originAddress,
                originLat: originLat,
                originLng: originLng,
                totalDistance: totalDistance,
                totalWeight: totalWeight,
                totalPrice: totalPrice,
                deliveryDate: deliveryDate,
                vehicleId: vehicleId,
                creadoPor: creadoPor,
                branchId: branchId,
                startedAt: startedAt,
                finishedAt: finishedAt,
                optimized: optimized,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RoutesTableProcessedTableManager =
    ProcessedTableManager<
      _$BaseLocal,
      $RoutesTable,
      Ruta,
      $$RoutesTableFilterComposer,
      $$RoutesTableOrderingComposer,
      $$RoutesTableAnnotationComposer,
      $$RoutesTableCreateCompanionBuilder,
      $$RoutesTableUpdateCompanionBuilder,
      (Ruta, BaseReferences<_$BaseLocal, $RoutesTable, Ruta>),
      Ruta,
      PrefetchHooks Function()
    >;
typedef $$WarehousesTableCreateCompanionBuilder =
    WarehousesCompanion Function({
      required String id,
      required String sucursalCodigo,
      required String nombre,
      Value<String?> direccion,
      Value<double?> lat,
      Value<double?> lng,
      Value<bool> principal,
      Value<bool> activo,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$WarehousesTableUpdateCompanionBuilder =
    WarehousesCompanion Function({
      Value<String> id,
      Value<String> sucursalCodigo,
      Value<String> nombre,
      Value<String?> direccion,
      Value<double?> lat,
      Value<double?> lng,
      Value<bool> principal,
      Value<bool> activo,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

class $$WarehousesTableFilterComposer
    extends Composer<_$BaseLocal, $WarehousesTable> {
  $$WarehousesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sucursalCodigo => $composableBuilder(
    column: $table.sucursalCodigo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direccion => $composableBuilder(
    column: $table.direccion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get principal => $composableBuilder(
    column: $table.principal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get activo => $composableBuilder(
    column: $table.activo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WarehousesTableOrderingComposer
    extends Composer<_$BaseLocal, $WarehousesTable> {
  $$WarehousesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sucursalCodigo => $composableBuilder(
    column: $table.sucursalCodigo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direccion => $composableBuilder(
    column: $table.direccion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get principal => $composableBuilder(
    column: $table.principal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get activo => $composableBuilder(
    column: $table.activo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WarehousesTableAnnotationComposer
    extends Composer<_$BaseLocal, $WarehousesTable> {
  $$WarehousesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sucursalCodigo => $composableBuilder(
    column: $table.sucursalCodigo,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nombre =>
      $composableBuilder(column: $table.nombre, builder: (column) => column);

  GeneratedColumn<String> get direccion =>
      $composableBuilder(column: $table.direccion, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lng =>
      $composableBuilder(column: $table.lng, builder: (column) => column);

  GeneratedColumn<bool> get principal =>
      $composableBuilder(column: $table.principal, builder: (column) => column);

  GeneratedColumn<bool> get activo =>
      $composableBuilder(column: $table.activo, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$WarehousesTableTableManager
    extends
        RootTableManager<
          _$BaseLocal,
          $WarehousesTable,
          Almacen,
          $$WarehousesTableFilterComposer,
          $$WarehousesTableOrderingComposer,
          $$WarehousesTableAnnotationComposer,
          $$WarehousesTableCreateCompanionBuilder,
          $$WarehousesTableUpdateCompanionBuilder,
          (Almacen, BaseReferences<_$BaseLocal, $WarehousesTable, Almacen>),
          Almacen,
          PrefetchHooks Function()
        > {
  $$WarehousesTableTableManager(_$BaseLocal db, $WarehousesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WarehousesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WarehousesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WarehousesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sucursalCodigo = const Value.absent(),
                Value<String> nombre = const Value.absent(),
                Value<String?> direccion = const Value.absent(),
                Value<double?> lat = const Value.absent(),
                Value<double?> lng = const Value.absent(),
                Value<bool> principal = const Value.absent(),
                Value<bool> activo = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WarehousesCompanion(
                id: id,
                sucursalCodigo: sucursalCodigo,
                nombre: nombre,
                direccion: direccion,
                lat: lat,
                lng: lng,
                principal: principal,
                activo: activo,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sucursalCodigo,
                required String nombre,
                Value<String?> direccion = const Value.absent(),
                Value<double?> lat = const Value.absent(),
                Value<double?> lng = const Value.absent(),
                Value<bool> principal = const Value.absent(),
                Value<bool> activo = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WarehousesCompanion.insert(
                id: id,
                sucursalCodigo: sucursalCodigo,
                nombre: nombre,
                direccion: direccion,
                lat: lat,
                lng: lng,
                principal: principal,
                activo: activo,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WarehousesTableProcessedTableManager =
    ProcessedTableManager<
      _$BaseLocal,
      $WarehousesTable,
      Almacen,
      $$WarehousesTableFilterComposer,
      $$WarehousesTableOrderingComposer,
      $$WarehousesTableAnnotationComposer,
      $$WarehousesTableCreateCompanionBuilder,
      $$WarehousesTableUpdateCompanionBuilder,
      (Almacen, BaseReferences<_$BaseLocal, $WarehousesTable, Almacen>),
      Almacen,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      Value<int> id,
      Value<int> syncBarridoDia,
      Value<DateTime?> catalogoTraidoAt,
      Value<String> currency,
      Value<double> cupRate,
      Value<DateTime?> cupRateUpdatedAt,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<int> id,
      Value<int> syncBarridoDia,
      Value<DateTime?> catalogoTraidoAt,
      Value<String> currency,
      Value<double> cupRate,
      Value<DateTime?> cupRateUpdatedAt,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$BaseLocal, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncBarridoDia => $composableBuilder(
    column: $table.syncBarridoDia,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get catalogoTraidoAt => $composableBuilder(
    column: $table.catalogoTraidoAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cupRate => $composableBuilder(
    column: $table.cupRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cupRateUpdatedAt => $composableBuilder(
    column: $table.cupRateUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$BaseLocal, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncBarridoDia => $composableBuilder(
    column: $table.syncBarridoDia,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get catalogoTraidoAt => $composableBuilder(
    column: $table.catalogoTraidoAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cupRate => $composableBuilder(
    column: $table.cupRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cupRateUpdatedAt => $composableBuilder(
    column: $table.cupRateUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$BaseLocal, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get syncBarridoDia => $composableBuilder(
    column: $table.syncBarridoDia,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get catalogoTraidoAt => $composableBuilder(
    column: $table.catalogoTraidoAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<double> get cupRate =>
      $composableBuilder(column: $table.cupRate, builder: (column) => column);

  GeneratedColumn<DateTime> get cupRateUpdatedAt => $composableBuilder(
    column: $table.cupRateUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$BaseLocal,
          $SettingsTable,
          Ajustes,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Ajustes, BaseReferences<_$BaseLocal, $SettingsTable, Ajustes>),
          Ajustes,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$BaseLocal db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> syncBarridoDia = const Value.absent(),
                Value<DateTime?> catalogoTraidoAt = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<double> cupRate = const Value.absent(),
                Value<DateTime?> cupRateUpdatedAt = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
              }) => SettingsCompanion(
                id: id,
                syncBarridoDia: syncBarridoDia,
                catalogoTraidoAt: catalogoTraidoAt,
                currency: currency,
                cupRate: cupRate,
                cupRateUpdatedAt: cupRateUpdatedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> syncBarridoDia = const Value.absent(),
                Value<DateTime?> catalogoTraidoAt = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<double> cupRate = const Value.absent(),
                Value<DateTime?> cupRateUpdatedAt = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
              }) => SettingsCompanion.insert(
                id: id,
                syncBarridoDia: syncBarridoDia,
                catalogoTraidoAt: catalogoTraidoAt,
                currency: currency,
                cupRate: cupRate,
                cupRateUpdatedAt: cupRateUpdatedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$BaseLocal,
      $SettingsTable,
      Ajustes,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Ajustes, BaseReferences<_$BaseLocal, $SettingsTable, Ajustes>),
      Ajustes,
      PrefetchHooks Function()
    >;
typedef $$ApuntesTableCreateCompanionBuilder =
    ApuntesCompanion Function({
      Value<int> orden,
      required String clave,
      required DateTime hechoAt,
      required String metodo,
      required String ruta,
      required String cuerpo,
      Value<String?> provisional,
      Value<EstadoApunte> estado,
      Value<String?> motivo,
      Value<DateTime?> resueltoAt,
      Value<int> intentos,
      Value<String?> revision,
      Value<String?> revisadoPor,
      Value<DateTime?> revisadoAt,
      Value<String?> motivoRevision,
    });
typedef $$ApuntesTableUpdateCompanionBuilder =
    ApuntesCompanion Function({
      Value<int> orden,
      Value<String> clave,
      Value<DateTime> hechoAt,
      Value<String> metodo,
      Value<String> ruta,
      Value<String> cuerpo,
      Value<String?> provisional,
      Value<EstadoApunte> estado,
      Value<String?> motivo,
      Value<DateTime?> resueltoAt,
      Value<int> intentos,
      Value<String?> revision,
      Value<String?> revisadoPor,
      Value<DateTime?> revisadoAt,
      Value<String?> motivoRevision,
    });

class $$ApuntesTableFilterComposer
    extends Composer<_$BaseLocal, $ApuntesTable> {
  $$ApuntesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get orden => $composableBuilder(
    column: $table.orden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clave => $composableBuilder(
    column: $table.clave,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get hechoAt => $composableBuilder(
    column: $table.hechoAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metodo => $composableBuilder(
    column: $table.metodo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ruta => $composableBuilder(
    column: $table.ruta,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cuerpo => $composableBuilder(
    column: $table.cuerpo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provisional => $composableBuilder(
    column: $table.provisional,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<EstadoApunte, EstadoApunte, String>
  get estado => $composableBuilder(
    column: $table.estado,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get motivo => $composableBuilder(
    column: $table.motivo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get resueltoAt => $composableBuilder(
    column: $table.resueltoAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get intentos => $composableBuilder(
    column: $table.intentos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get revisadoPor => $composableBuilder(
    column: $table.revisadoPor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get revisadoAt => $composableBuilder(
    column: $table.revisadoAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get motivoRevision => $composableBuilder(
    column: $table.motivoRevision,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ApuntesTableOrderingComposer
    extends Composer<_$BaseLocal, $ApuntesTable> {
  $$ApuntesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get orden => $composableBuilder(
    column: $table.orden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clave => $composableBuilder(
    column: $table.clave,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get hechoAt => $composableBuilder(
    column: $table.hechoAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metodo => $composableBuilder(
    column: $table.metodo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ruta => $composableBuilder(
    column: $table.ruta,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cuerpo => $composableBuilder(
    column: $table.cuerpo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provisional => $composableBuilder(
    column: $table.provisional,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get estado => $composableBuilder(
    column: $table.estado,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get motivo => $composableBuilder(
    column: $table.motivo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get resueltoAt => $composableBuilder(
    column: $table.resueltoAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get intentos => $composableBuilder(
    column: $table.intentos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get revisadoPor => $composableBuilder(
    column: $table.revisadoPor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get revisadoAt => $composableBuilder(
    column: $table.revisadoAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get motivoRevision => $composableBuilder(
    column: $table.motivoRevision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ApuntesTableAnnotationComposer
    extends Composer<_$BaseLocal, $ApuntesTable> {
  $$ApuntesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get orden =>
      $composableBuilder(column: $table.orden, builder: (column) => column);

  GeneratedColumn<String> get clave =>
      $composableBuilder(column: $table.clave, builder: (column) => column);

  GeneratedColumn<DateTime> get hechoAt =>
      $composableBuilder(column: $table.hechoAt, builder: (column) => column);

  GeneratedColumn<String> get metodo =>
      $composableBuilder(column: $table.metodo, builder: (column) => column);

  GeneratedColumn<String> get ruta =>
      $composableBuilder(column: $table.ruta, builder: (column) => column);

  GeneratedColumn<String> get cuerpo =>
      $composableBuilder(column: $table.cuerpo, builder: (column) => column);

  GeneratedColumn<String> get provisional => $composableBuilder(
    column: $table.provisional,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<EstadoApunte, String> get estado =>
      $composableBuilder(column: $table.estado, builder: (column) => column);

  GeneratedColumn<String> get motivo =>
      $composableBuilder(column: $table.motivo, builder: (column) => column);

  GeneratedColumn<DateTime> get resueltoAt => $composableBuilder(
    column: $table.resueltoAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get intentos =>
      $composableBuilder(column: $table.intentos, builder: (column) => column);

  GeneratedColumn<String> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<String> get revisadoPor => $composableBuilder(
    column: $table.revisadoPor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get revisadoAt => $composableBuilder(
    column: $table.revisadoAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get motivoRevision => $composableBuilder(
    column: $table.motivoRevision,
    builder: (column) => column,
  );
}

class $$ApuntesTableTableManager
    extends
        RootTableManager<
          _$BaseLocal,
          $ApuntesTable,
          Apunte,
          $$ApuntesTableFilterComposer,
          $$ApuntesTableOrderingComposer,
          $$ApuntesTableAnnotationComposer,
          $$ApuntesTableCreateCompanionBuilder,
          $$ApuntesTableUpdateCompanionBuilder,
          (Apunte, BaseReferences<_$BaseLocal, $ApuntesTable, Apunte>),
          Apunte,
          PrefetchHooks Function()
        > {
  $$ApuntesTableTableManager(_$BaseLocal db, $ApuntesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ApuntesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ApuntesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ApuntesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> orden = const Value.absent(),
                Value<String> clave = const Value.absent(),
                Value<DateTime> hechoAt = const Value.absent(),
                Value<String> metodo = const Value.absent(),
                Value<String> ruta = const Value.absent(),
                Value<String> cuerpo = const Value.absent(),
                Value<String?> provisional = const Value.absent(),
                Value<EstadoApunte> estado = const Value.absent(),
                Value<String?> motivo = const Value.absent(),
                Value<DateTime?> resueltoAt = const Value.absent(),
                Value<int> intentos = const Value.absent(),
                Value<String?> revision = const Value.absent(),
                Value<String?> revisadoPor = const Value.absent(),
                Value<DateTime?> revisadoAt = const Value.absent(),
                Value<String?> motivoRevision = const Value.absent(),
              }) => ApuntesCompanion(
                orden: orden,
                clave: clave,
                hechoAt: hechoAt,
                metodo: metodo,
                ruta: ruta,
                cuerpo: cuerpo,
                provisional: provisional,
                estado: estado,
                motivo: motivo,
                resueltoAt: resueltoAt,
                intentos: intentos,
                revision: revision,
                revisadoPor: revisadoPor,
                revisadoAt: revisadoAt,
                motivoRevision: motivoRevision,
              ),
          createCompanionCallback:
              ({
                Value<int> orden = const Value.absent(),
                required String clave,
                required DateTime hechoAt,
                required String metodo,
                required String ruta,
                required String cuerpo,
                Value<String?> provisional = const Value.absent(),
                Value<EstadoApunte> estado = const Value.absent(),
                Value<String?> motivo = const Value.absent(),
                Value<DateTime?> resueltoAt = const Value.absent(),
                Value<int> intentos = const Value.absent(),
                Value<String?> revision = const Value.absent(),
                Value<String?> revisadoPor = const Value.absent(),
                Value<DateTime?> revisadoAt = const Value.absent(),
                Value<String?> motivoRevision = const Value.absent(),
              }) => ApuntesCompanion.insert(
                orden: orden,
                clave: clave,
                hechoAt: hechoAt,
                metodo: metodo,
                ruta: ruta,
                cuerpo: cuerpo,
                provisional: provisional,
                estado: estado,
                motivo: motivo,
                resueltoAt: resueltoAt,
                intentos: intentos,
                revision: revision,
                revisadoPor: revisadoPor,
                revisadoAt: revisadoAt,
                motivoRevision: motivoRevision,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ApuntesTableProcessedTableManager =
    ProcessedTableManager<
      _$BaseLocal,
      $ApuntesTable,
      Apunte,
      $$ApuntesTableFilterComposer,
      $$ApuntesTableOrderingComposer,
      $$ApuntesTableAnnotationComposer,
      $$ApuntesTableCreateCompanionBuilder,
      $$ApuntesTableUpdateCompanionBuilder,
      (Apunte, BaseReferences<_$BaseLocal, $ApuntesTable, Apunte>),
      Apunte,
      PrefetchHooks Function()
    >;
typedef $$EquivalenciasTableCreateCompanionBuilder =
    EquivalenciasCompanion Function({
      required String provisional,
      required String idReal,
      required DateTime at,
      Value<int> rowid,
    });
typedef $$EquivalenciasTableUpdateCompanionBuilder =
    EquivalenciasCompanion Function({
      Value<String> provisional,
      Value<String> idReal,
      Value<DateTime> at,
      Value<int> rowid,
    });

class $$EquivalenciasTableFilterComposer
    extends Composer<_$BaseLocal, $EquivalenciasTable> {
  $$EquivalenciasTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get provisional => $composableBuilder(
    column: $table.provisional,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idReal => $composableBuilder(
    column: $table.idReal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EquivalenciasTableOrderingComposer
    extends Composer<_$BaseLocal, $EquivalenciasTable> {
  $$EquivalenciasTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get provisional => $composableBuilder(
    column: $table.provisional,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idReal => $composableBuilder(
    column: $table.idReal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EquivalenciasTableAnnotationComposer
    extends Composer<_$BaseLocal, $EquivalenciasTable> {
  $$EquivalenciasTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get provisional => $composableBuilder(
    column: $table.provisional,
    builder: (column) => column,
  );

  GeneratedColumn<String> get idReal =>
      $composableBuilder(column: $table.idReal, builder: (column) => column);

  GeneratedColumn<DateTime> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);
}

class $$EquivalenciasTableTableManager
    extends
        RootTableManager<
          _$BaseLocal,
          $EquivalenciasTable,
          Equivalencia,
          $$EquivalenciasTableFilterComposer,
          $$EquivalenciasTableOrderingComposer,
          $$EquivalenciasTableAnnotationComposer,
          $$EquivalenciasTableCreateCompanionBuilder,
          $$EquivalenciasTableUpdateCompanionBuilder,
          (
            Equivalencia,
            BaseReferences<_$BaseLocal, $EquivalenciasTable, Equivalencia>,
          ),
          Equivalencia,
          PrefetchHooks Function()
        > {
  $$EquivalenciasTableTableManager(_$BaseLocal db, $EquivalenciasTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EquivalenciasTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EquivalenciasTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EquivalenciasTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> provisional = const Value.absent(),
                Value<String> idReal = const Value.absent(),
                Value<DateTime> at = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EquivalenciasCompanion(
                provisional: provisional,
                idReal: idReal,
                at: at,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String provisional,
                required String idReal,
                required DateTime at,
                Value<int> rowid = const Value.absent(),
              }) => EquivalenciasCompanion.insert(
                provisional: provisional,
                idReal: idReal,
                at: at,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EquivalenciasTableProcessedTableManager =
    ProcessedTableManager<
      _$BaseLocal,
      $EquivalenciasTable,
      Equivalencia,
      $$EquivalenciasTableFilterComposer,
      $$EquivalenciasTableOrderingComposer,
      $$EquivalenciasTableAnnotationComposer,
      $$EquivalenciasTableCreateCompanionBuilder,
      $$EquivalenciasTableUpdateCompanionBuilder,
      (
        Equivalencia,
        BaseReferences<_$BaseLocal, $EquivalenciasTable, Equivalencia>,
      ),
      Equivalencia,
      PrefetchHooks Function()
    >;
typedef $$FrescuraTableCreateCompanionBuilder =
    FrescuraCompanion Function({
      required String coleccion,
      Value<DateTime?> bajadaAt,
      Value<String?> hasta,
      Value<bool> completa,
      Value<int> rowid,
    });
typedef $$FrescuraTableUpdateCompanionBuilder =
    FrescuraCompanion Function({
      Value<String> coleccion,
      Value<DateTime?> bajadaAt,
      Value<String?> hasta,
      Value<bool> completa,
      Value<int> rowid,
    });

class $$FrescuraTableFilterComposer
    extends Composer<_$BaseLocal, $FrescuraTable> {
  $$FrescuraTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get coleccion => $composableBuilder(
    column: $table.coleccion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get bajadaAt => $composableBuilder(
    column: $table.bajadaAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hasta => $composableBuilder(
    column: $table.hasta,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completa => $composableBuilder(
    column: $table.completa,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FrescuraTableOrderingComposer
    extends Composer<_$BaseLocal, $FrescuraTable> {
  $$FrescuraTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get coleccion => $composableBuilder(
    column: $table.coleccion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get bajadaAt => $composableBuilder(
    column: $table.bajadaAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hasta => $composableBuilder(
    column: $table.hasta,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completa => $composableBuilder(
    column: $table.completa,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FrescuraTableAnnotationComposer
    extends Composer<_$BaseLocal, $FrescuraTable> {
  $$FrescuraTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get coleccion =>
      $composableBuilder(column: $table.coleccion, builder: (column) => column);

  GeneratedColumn<DateTime> get bajadaAt =>
      $composableBuilder(column: $table.bajadaAt, builder: (column) => column);

  GeneratedColumn<String> get hasta =>
      $composableBuilder(column: $table.hasta, builder: (column) => column);

  GeneratedColumn<bool> get completa =>
      $composableBuilder(column: $table.completa, builder: (column) => column);
}

class $$FrescuraTableTableManager
    extends
        RootTableManager<
          _$BaseLocal,
          $FrescuraTable,
          FilaFrescura,
          $$FrescuraTableFilterComposer,
          $$FrescuraTableOrderingComposer,
          $$FrescuraTableAnnotationComposer,
          $$FrescuraTableCreateCompanionBuilder,
          $$FrescuraTableUpdateCompanionBuilder,
          (
            FilaFrescura,
            BaseReferences<_$BaseLocal, $FrescuraTable, FilaFrescura>,
          ),
          FilaFrescura,
          PrefetchHooks Function()
        > {
  $$FrescuraTableTableManager(_$BaseLocal db, $FrescuraTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FrescuraTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FrescuraTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FrescuraTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> coleccion = const Value.absent(),
                Value<DateTime?> bajadaAt = const Value.absent(),
                Value<String?> hasta = const Value.absent(),
                Value<bool> completa = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FrescuraCompanion(
                coleccion: coleccion,
                bajadaAt: bajadaAt,
                hasta: hasta,
                completa: completa,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String coleccion,
                Value<DateTime?> bajadaAt = const Value.absent(),
                Value<String?> hasta = const Value.absent(),
                Value<bool> completa = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FrescuraCompanion.insert(
                coleccion: coleccion,
                bajadaAt: bajadaAt,
                hasta: hasta,
                completa: completa,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FrescuraTableProcessedTableManager =
    ProcessedTableManager<
      _$BaseLocal,
      $FrescuraTable,
      FilaFrescura,
      $$FrescuraTableFilterComposer,
      $$FrescuraTableOrderingComposer,
      $$FrescuraTableAnnotationComposer,
      $$FrescuraTableCreateCompanionBuilder,
      $$FrescuraTableUpdateCompanionBuilder,
      (FilaFrescura, BaseReferences<_$BaseLocal, $FrescuraTable, FilaFrescura>),
      FilaFrescura,
      PrefetchHooks Function()
    >;
typedef $$PreferenciasTableCreateCompanionBuilder =
    PreferenciasCompanion Function({
      required String clave,
      required String valor,
      Value<int> rowid,
    });
typedef $$PreferenciasTableUpdateCompanionBuilder =
    PreferenciasCompanion Function({
      Value<String> clave,
      Value<String> valor,
      Value<int> rowid,
    });

class $$PreferenciasTableFilterComposer
    extends Composer<_$BaseLocal, $PreferenciasTable> {
  $$PreferenciasTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clave => $composableBuilder(
    column: $table.clave,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valor => $composableBuilder(
    column: $table.valor,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PreferenciasTableOrderingComposer
    extends Composer<_$BaseLocal, $PreferenciasTable> {
  $$PreferenciasTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clave => $composableBuilder(
    column: $table.clave,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valor => $composableBuilder(
    column: $table.valor,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PreferenciasTableAnnotationComposer
    extends Composer<_$BaseLocal, $PreferenciasTable> {
  $$PreferenciasTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clave =>
      $composableBuilder(column: $table.clave, builder: (column) => column);

  GeneratedColumn<String> get valor =>
      $composableBuilder(column: $table.valor, builder: (column) => column);
}

class $$PreferenciasTableTableManager
    extends
        RootTableManager<
          _$BaseLocal,
          $PreferenciasTable,
          Preferencia,
          $$PreferenciasTableFilterComposer,
          $$PreferenciasTableOrderingComposer,
          $$PreferenciasTableAnnotationComposer,
          $$PreferenciasTableCreateCompanionBuilder,
          $$PreferenciasTableUpdateCompanionBuilder,
          (
            Preferencia,
            BaseReferences<_$BaseLocal, $PreferenciasTable, Preferencia>,
          ),
          Preferencia,
          PrefetchHooks Function()
        > {
  $$PreferenciasTableTableManager(_$BaseLocal db, $PreferenciasTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PreferenciasTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PreferenciasTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PreferenciasTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> clave = const Value.absent(),
                Value<String> valor = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PreferenciasCompanion(
                clave: clave,
                valor: valor,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String clave,
                required String valor,
                Value<int> rowid = const Value.absent(),
              }) => PreferenciasCompanion.insert(
                clave: clave,
                valor: valor,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PreferenciasTableProcessedTableManager =
    ProcessedTableManager<
      _$BaseLocal,
      $PreferenciasTable,
      Preferencia,
      $$PreferenciasTableFilterComposer,
      $$PreferenciasTableOrderingComposer,
      $$PreferenciasTableAnnotationComposer,
      $$PreferenciasTableCreateCompanionBuilder,
      $$PreferenciasTableUpdateCompanionBuilder,
      (
        Preferencia,
        BaseReferences<_$BaseLocal, $PreferenciasTable, Preferencia>,
      ),
      Preferencia,
      PrefetchHooks Function()
    >;

class $BaseLocalManager {
  final _$BaseLocal _db;
  $BaseLocalManager(this._db);
  $$BranchesTableTableManager get branches =>
      $$BranchesTableTableManager(_db, _db.branches);
  $$VehicleTypesTableTableManager get vehicleTypes =>
      $$VehicleTypesTableTableManager(_db, _db.vehicleTypes);
  $$VehiclesTableTableManager get vehicles =>
      $$VehiclesTableTableManager(_db, _db.vehicles);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db, _db.products);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db, _db.customers);
  $$OrdersTableTableManager get orders =>
      $$OrdersTableTableManager(_db, _db.orders);
  $$OrderItemsTableTableManager get orderItems =>
      $$OrderItemsTableTableManager(_db, _db.orderItems);
  $$RoutesTableTableManager get routes =>
      $$RoutesTableTableManager(_db, _db.routes);
  $$WarehousesTableTableManager get warehouses =>
      $$WarehousesTableTableManager(_db, _db.warehouses);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$ApuntesTableTableManager get apuntes =>
      $$ApuntesTableTableManager(_db, _db.apuntes);
  $$EquivalenciasTableTableManager get equivalencias =>
      $$EquivalenciasTableTableManager(_db, _db.equivalencias);
  $$FrescuraTableTableManager get frescura =>
      $$FrescuraTableTableManager(_db, _db.frescura);
  $$PreferenciasTableTableManager get preferencias =>
      $$PreferenciasTableTableManager(_db, _db.preferencias);
}
