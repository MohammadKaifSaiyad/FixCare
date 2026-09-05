// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_dtos.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_BookingServiceDto _$BookingServiceDtoFromJson(Map<String, dynamic> json) =>
    _BookingServiceDto(id: json['id'] as String, name: json['name'] as String);

Map<String, dynamic> _$BookingServiceDtoToJson(_BookingServiceDto instance) =>
    <String, dynamic>{'id': instance.id, 'name': instance.name};

_BookingZoneDto _$BookingZoneDtoFromJson(Map<String, dynamic> json) =>
    _BookingZoneDto(id: json['id'] as String, name: json['name'] as String);

Map<String, dynamic> _$BookingZoneDtoToJson(_BookingZoneDto instance) =>
    <String, dynamic>{'id': instance.id, 'name': instance.name};

_BookingAddressRefDto _$BookingAddressRefDtoFromJson(
  Map<String, dynamic> json,
) => _BookingAddressRefDto(id: json['id'] as String);

Map<String, dynamic> _$BookingAddressRefDtoToJson(
  _BookingAddressRefDto instance,
) => <String, dynamic>{'id': instance.id};

_TechnicianRefDto _$TechnicianRefDtoFromJson(Map<String, dynamic> json) =>
    _TechnicianRefDto(
      name: json['name'] as String,
      maskedPhone: json['maskedPhone'] as String,
    );

Map<String, dynamic> _$TechnicianRefDtoToJson(_TechnicianRefDto instance) =>
    <String, dynamic>{
      'name': instance.name,
      'maskedPhone': instance.maskedPhone,
    };

_DiagnosisDto _$DiagnosisDtoFromJson(Map<String, dynamic> json) =>
    _DiagnosisDto(issueName: json['issueName'] as String);

Map<String, dynamic> _$DiagnosisDtoToJson(_DiagnosisDto instance) =>
    <String, dynamic>{'issueName': instance.issueName};

_PartDto _$PartDtoFromJson(Map<String, dynamic> json) => _PartDto(
  id: json['id'] as String,
  sku: json['sku'] as String,
  name: json['name'] as String,
  ceilingPricePaise: (json['ceilingPricePaise'] as num).toInt(),
  qty: (json['qty'] as num).toInt(),
);

Map<String, dynamic> _$PartDtoToJson(_PartDto instance) => <String, dynamic>{
  'id': instance.id,
  'sku': instance.sku,
  'name': instance.name,
  'ceilingPricePaise': instance.ceilingPricePaise,
  'qty': instance.qty,
};

_EstimateDto _$EstimateDtoFromJson(Map<String, dynamic> json) => _EstimateDto(
  laborPaise: (json['laborPaise'] as num).toInt(),
  partsPaise: (json['partsPaise'] as num).toInt(),
  visitFeeCreditPaise: (json['visitFeeCreditPaise'] as num).toInt(),
  totalPayablePaise: (json['totalPayablePaise'] as num).toInt(),
);

Map<String, dynamic> _$EstimateDtoToJson(_EstimateDto instance) =>
    <String, dynamic>{
      'laborPaise': instance.laborPaise,
      'partsPaise': instance.partsPaise,
      'visitFeeCreditPaise': instance.visitFeeCreditPaise,
      'totalPayablePaise': instance.totalPayablePaise,
    };

_PhotoDto _$PhotoDtoFromJson(Map<String, dynamic> json) => _PhotoDto(
  kind: json['kind'] as String,
  capturedAt: json['capturedAt'] as String,
  url: json['url'] as String,
);

Map<String, dynamic> _$PhotoDtoToJson(_PhotoDto instance) => <String, dynamic>{
  'kind': instance.kind,
  'capturedAt': instance.capturedAt,
  'url': instance.url,
};

_PaymentSummaryDto _$PaymentSummaryDtoFromJson(Map<String, dynamic> json) =>
    _PaymentSummaryDto(
      status: json['status'] as String,
      method: json['method'] as String,
      amountPaise: (json['amountPaise'] as num).toInt(),
    );

Map<String, dynamic> _$PaymentSummaryDtoToJson(_PaymentSummaryDto instance) =>
    <String, dynamic>{
      'status': instance.status,
      'method': instance.method,
      'amountPaise': instance.amountPaise,
    };

_DisputeSummaryDto _$DisputeSummaryDtoFromJson(Map<String, dynamic> json) =>
    _DisputeSummaryDto(
      status: json['status'] as String,
      outcome: json['outcome'] as String?,
      refundPaise: (json['refundPaise'] as num?)?.toInt(),
    );

Map<String, dynamic> _$DisputeSummaryDtoToJson(_DisputeSummaryDto instance) =>
    <String, dynamic>{
      'status': instance.status,
      'outcome': instance.outcome,
      'refundPaise': instance.refundPaise,
    };

_BookingDto _$BookingDtoFromJson(Map<String, dynamic> json) => _BookingDto(
  id: json['id'] as String,
  bookingNumber: json['bookingNumber'] as String,
  state: json['state'] as String,
  scheduledSlot: json['scheduledSlot'] as String,
  visitFeePaise: (json['visitFeePaise'] as num).toInt(),
  laborPaise: (json['laborPaise'] as num).toInt(),
  laborTier: json['laborTier'] as String,
  service: BookingServiceDto.fromJson(json['service'] as Map<String, dynamic>),
  zone: BookingZoneDto.fromJson(json['zone'] as Map<String, dynamic>),
  address: BookingAddressRefDto.fromJson(
    json['address'] as Map<String, dynamic>,
  ),
  technician: json['technician'] == null
      ? null
      : TechnicianRefDto.fromJson(json['technician'] as Map<String, dynamic>),
  diagnosis: json['diagnosis'] == null
      ? null
      : DiagnosisDto.fromJson(json['diagnosis'] as Map<String, dynamic>),
  parts:
      (json['parts'] as List<dynamic>?)
          ?.map((e) => PartDto.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <PartDto>[],
  estimate: EstimateDto.fromJson(json['estimate'] as Map<String, dynamic>),
  photos:
      (json['photos'] as List<dynamic>?)
          ?.map((e) => PhotoDto.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <PhotoDto>[],
  payment: json['payment'] == null
      ? null
      : PaymentSummaryDto.fromJson(json['payment'] as Map<String, dynamic>),
  dispute: json['dispute'] == null
      ? null
      : DisputeSummaryDto.fromJson(json['dispute'] as Map<String, dynamic>),
);

Map<String, dynamic> _$BookingDtoToJson(_BookingDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'bookingNumber': instance.bookingNumber,
      'state': instance.state,
      'scheduledSlot': instance.scheduledSlot,
      'visitFeePaise': instance.visitFeePaise,
      'laborPaise': instance.laborPaise,
      'laborTier': instance.laborTier,
      'service': instance.service,
      'zone': instance.zone,
      'address': instance.address,
      'technician': instance.technician,
      'diagnosis': instance.diagnosis,
      'parts': instance.parts,
      'estimate': instance.estimate,
      'photos': instance.photos,
      'payment': instance.payment,
      'dispute': instance.dispute,
    };
