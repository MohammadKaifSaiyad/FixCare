import 'package:freezed_annotation/freezed_annotation.dart';
part 'technician_profile_dto.freezed.dart';
part 'technician_profile_dto.g.dart';

@freezed
abstract class TechnicianProfileDto with _$TechnicianProfileDto {
  const factory TechnicianProfileDto({
    required String id,
    required String role,
    required String name,
    @Default(<String>[]) List<String> skills,
    required String status,
  }) = _TechnicianProfileDto;
  factory TechnicianProfileDto.fromJson(Map<String, dynamic> j) => _$TechnicianProfileDtoFromJson(j);
}
