import 'package:freezed_annotation/freezed_annotation.dart';
part 'technician_profile_dto.freezed.dart';
part 'technician_profile_dto.g.dart';

/// A service zone, by id + display name (`GET /catalog/zones` items and the profile's `zones`).
@freezed
abstract class ZoneRefDto with _$ZoneRefDto {
  const factory ZoneRefDto({required String id, required String name}) = _ZoneRefDto;
  factory ZoneRefDto.fromJson(Map<String, dynamic> j) => _$ZoneRefDtoFromJson(j);
}

@freezed
abstract class TechnicianProfileDto with _$TechnicianProfileDto {
  const factory TechnicianProfileDto({
    required String id,
    required String role,
    required String name,
    @Default(<String>[]) List<String> skills,
    required String status,
    @Default(<ZoneRefDto>[]) List<ZoneRefDto> zones,
    /// Ops' reason when the profile was sent back or the account suspended.
    String? reviewNote,
    String? submittedAt,
  }) = _TechnicianProfileDto;
  factory TechnicianProfileDto.fromJson(Map<String, dynamic> j) => _$TechnicianProfileDtoFromJson(j);
}
