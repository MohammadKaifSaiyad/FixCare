import 'package:freezed_annotation/freezed_annotation.dart';
part 'address_dtos.freezed.dart';
part 'address_dtos.g.dart';

@freezed
abstract class ZoneDto with _$ZoneDto {
  const factory ZoneDto({required String id, required String name, required int visitFeePaise}) = _ZoneDto;
  factory ZoneDto.fromJson(Map<String, dynamic> j) => _$ZoneDtoFromJson(j);
}

@freezed
abstract class AddressDto with _$AddressDto {
  const factory AddressDto({
    required String id,
    required String label,
    required String line1,
    String? line2,
    String? landmark,
    required String pincode,
    double? lat,
    double? lng,
    required bool isDefault,
    required String status,
    required bool serviceable,
    ZoneDto? zone,
    String? message,
  }) = _AddressDto;
  factory AddressDto.fromJson(Map<String, dynamic> j) => _$AddressDtoFromJson(j);
}

@freezed
abstract class ServiceabilityDto with _$ServiceabilityDto {
  const factory ServiceabilityDto({required bool serviceable, ZoneDto? zone, String? message}) = _ServiceabilityDto;
  factory ServiceabilityDto.fromJson(Map<String, dynamic> j) => _$ServiceabilityDtoFromJson(j);
}

/// Picks the address to resolve the catalog/booking zone against: the default
/// address IF it's serviceable (has a zone), else the first serviceable
/// address, else null. Shared by Home (catalog zone) and the booking wizard
/// (preselect) so neither ever lands on a non-serviceable default — that would
/// either hide a bookable catalog (Home) or preselect an address that is
/// guaranteed to 422 on booking confirm (wizard).
AddressDto? defaultServiceableAddress(List<AddressDto> addresses) {
  if (addresses.isEmpty) return null;
  final def = addresses.firstWhere((a) => a.isDefault, orElse: () => addresses.first);
  if (def.serviceable && def.zone != null) return def;
  for (final a in addresses) {
    if (a.serviceable && a.zone != null) return a;
  }
  return null;
}
