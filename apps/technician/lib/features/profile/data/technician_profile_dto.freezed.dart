// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'technician_profile_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TechnicianProfileDto {

 String get id; String get role; String get name; List<String> get skills; String get status;
/// Create a copy of TechnicianProfileDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TechnicianProfileDtoCopyWith<TechnicianProfileDto> get copyWith => _$TechnicianProfileDtoCopyWithImpl<TechnicianProfileDto>(this as TechnicianProfileDto, _$identity);

  /// Serializes this TechnicianProfileDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as TechnicianProfileDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TechnicianProfileDto&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.role, _this.role) || other.role == _this.role)&&(identical(other.name, _this.name) || other.name == _this.name)&&const DeepCollectionEquality().equals(other.skills, _this.skills)&&(identical(other.status, _this.status) || other.status == _this.status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as TechnicianProfileDto;
  return Object.hash(runtimeType,_this.id,_this.role,_this.name,const DeepCollectionEquality().hash(_this.skills),_this.status);
}

@override
String toString() {
  final _this = this as TechnicianProfileDto;
  return 'TechnicianProfileDto(id: ${_this.id}, role: ${_this.role}, name: ${_this.name}, skills: ${_this.skills}, status: ${_this.status})';
}


}

/// @nodoc
abstract mixin class $TechnicianProfileDtoCopyWith<$Res>  {
  factory $TechnicianProfileDtoCopyWith(TechnicianProfileDto value, $Res Function(TechnicianProfileDto) _then) = _$TechnicianProfileDtoCopyWithImpl;
@useResult
$Res call({
 String id, String role, String name, List<String> skills, String status
});




}
/// @nodoc
class _$TechnicianProfileDtoCopyWithImpl<$Res>
    implements $TechnicianProfileDtoCopyWith<$Res> {
  _$TechnicianProfileDtoCopyWithImpl(this._self, this._then);

  final TechnicianProfileDto _self;
  final $Res Function(TechnicianProfileDto) _then;

/// Create a copy of TechnicianProfileDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? role = null,Object? name = null,Object? skills = null,Object? status = null,}) {
  return _then(TechnicianProfileDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,skills: null == skills ? _self.skills : skills // ignore: cast_nullable_to_non_nullable
as List<String>,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [TechnicianProfileDto].
extension TechnicianProfileDtoPatterns on TechnicianProfileDto {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TechnicianProfileDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TechnicianProfileDto() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TechnicianProfileDto value)  $default,){
final _that = this;
switch (_that) {
case _TechnicianProfileDto():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TechnicianProfileDto value)?  $default,){
final _that = this;
switch (_that) {
case _TechnicianProfileDto() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String role,  String name,  List<String> skills,  String status)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TechnicianProfileDto() when $default != null:
return $default(_that.id,_that.role,_that.name,_that.skills,_that.status);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String role,  String name,  List<String> skills,  String status)  $default,) {final _that = this;
switch (_that) {
case _TechnicianProfileDto():
return $default(_that.id,_that.role,_that.name,_that.skills,_that.status);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String role,  String name,  List<String> skills,  String status)?  $default,) {final _that = this;
switch (_that) {
case _TechnicianProfileDto() when $default != null:
return $default(_that.id,_that.role,_that.name,_that.skills,_that.status);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TechnicianProfileDto implements TechnicianProfileDto {
  const _TechnicianProfileDto({required this.id, required this.role, required this.name,  List<String> skills = const <String>[], required this.status}): _skills = skills;
  factory _TechnicianProfileDto.fromJson(Map<String, dynamic> json) => _$TechnicianProfileDtoFromJson(json);

@override final  String id;
@override final  String role;
@override final  String name;
 final  List<String> _skills;
@override@JsonKey() List<String> get skills {
  if (_skills is EqualUnmodifiableListView) return _skills;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_skills);
}

@override final  String status;

/// Create a copy of TechnicianProfileDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TechnicianProfileDtoCopyWith<_TechnicianProfileDto> get copyWith => __$TechnicianProfileDtoCopyWithImpl<_TechnicianProfileDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TechnicianProfileDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TechnicianProfileDto&&(identical(other.id, id) || other.id == id)&&(identical(other.role, role) || other.role == role)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.skills, _skills)&&(identical(other.status, status) || other.status == status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,role,name,const DeepCollectionEquality().hash(_skills),status);
}

@override
String toString() {
    return 'TechnicianProfileDto(id: $id, role: $role, name: $name, skills: $skills, status: $status)';
}


}

/// @nodoc
abstract mixin class _$TechnicianProfileDtoCopyWith<$Res> implements $TechnicianProfileDtoCopyWith<$Res> {
  factory _$TechnicianProfileDtoCopyWith(_TechnicianProfileDto value, $Res Function(_TechnicianProfileDto) _then) = __$TechnicianProfileDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String role, String name, List<String> skills, String status
});




}
/// @nodoc
class __$TechnicianProfileDtoCopyWithImpl<$Res>
    implements _$TechnicianProfileDtoCopyWith<$Res> {
  __$TechnicianProfileDtoCopyWithImpl(this._self, this._then);

  final _TechnicianProfileDto _self;
  final $Res Function(_TechnicianProfileDto) _then;

/// Create a copy of TechnicianProfileDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? role = null,Object? name = null,Object? skills = null,Object? status = null,}) {
  return _then(_TechnicianProfileDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,skills: null == skills ? _self._skills : skills // ignore: cast_nullable_to_non_nullable
as List<String>,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
