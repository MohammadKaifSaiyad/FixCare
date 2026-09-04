// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_dtos.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_UserDto _$UserDtoFromJson(Map<String, dynamic> json) => _UserDto(
  id: json['id'] as String,
  role: json['role'] as String,
  status: json['status'] as String,
);

Map<String, dynamic> _$UserDtoToJson(_UserDto instance) => <String, dynamic>{
  'id': instance.id,
  'role': instance.role,
  'status': instance.status,
};

_VerifyResponse _$VerifyResponseFromJson(Map<String, dynamic> json) =>
    _VerifyResponse(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      user: UserDto.fromJson(json['user'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$VerifyResponseToJson(_VerifyResponse instance) =>
    <String, dynamic>{
      'accessToken': instance.accessToken,
      'refreshToken': instance.refreshToken,
      'user': instance.user,
    };

_RefreshResponse _$RefreshResponseFromJson(Map<String, dynamic> json) =>
    _RefreshResponse(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
    );

Map<String, dynamic> _$RefreshResponseToJson(_RefreshResponse instance) =>
    <String, dynamic>{
      'accessToken': instance.accessToken,
      'refreshToken': instance.refreshToken,
    };

_SendOtpResponse _$SendOtpResponseFromJson(Map<String, dynamic> json) =>
    _SendOtpResponse(ok: json['ok'] as bool, devOtp: json['devOtp'] as String?);

Map<String, dynamic> _$SendOtpResponseToJson(_SendOtpResponse instance) =>
    <String, dynamic>{'ok': instance.ok, 'devOtp': instance.devOtp};
