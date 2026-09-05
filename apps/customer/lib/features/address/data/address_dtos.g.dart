// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'address_dtos.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ZoneDto _$ZoneDtoFromJson(Map<String, dynamic> json) => _ZoneDto(
  id: json['id'] as String,
  name: json['name'] as String,
  visitFeePaise: (json['visitFeePaise'] as num).toInt(),
);

Map<String, dynamic> _$ZoneDtoToJson(_ZoneDto instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'visitFeePaise': instance.visitFeePaise,
};

_AddressDto _$AddressDtoFromJson(Map<String, dynamic> json) => _AddressDto(
  id: json['id'] as String,
  label: json['label'] as String,
  line1: json['line1'] as String,
  line2: json['line2'] as String?,
  landmark: json['landmark'] as String?,
  pincode: json['pincode'] as String,
  lat: (json['lat'] as num?)?.toDouble(),
  lng: (json['lng'] as num?)?.toDouble(),
  isDefault: json['isDefault'] as bool,
  status: json['status'] as String,
  serviceable: json['serviceable'] as bool,
  zone: json['zone'] == null
      ? null
      : ZoneDto.fromJson(json['zone'] as Map<String, dynamic>),
  message: json['message'] as String?,
);

Map<String, dynamic> _$AddressDtoToJson(_AddressDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'label': instance.label,
      'line1': instance.line1,
      'line2': instance.line2,
      'landmark': instance.landmark,
      'pincode': instance.pincode,
      'lat': instance.lat,
      'lng': instance.lng,
      'isDefault': instance.isDefault,
      'status': instance.status,
      'serviceable': instance.serviceable,
      'zone': instance.zone,
      'message': instance.message,
    };

_ServiceabilityDto _$ServiceabilityDtoFromJson(Map<String, dynamic> json) =>
    _ServiceabilityDto(
      serviceable: json['serviceable'] as bool,
      zone: json['zone'] == null
          ? null
          : ZoneDto.fromJson(json['zone'] as Map<String, dynamic>),
      message: json['message'] as String?,
    );

Map<String, dynamic> _$ServiceabilityDtoToJson(_ServiceabilityDto instance) =>
    <String, dynamic>{
      'serviceable': instance.serviceable,
      'zone': instance.zone,
      'message': instance.message,
    };
