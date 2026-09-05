// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'profile_dtos.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CustomerProfileDto {

 String get id; String get role; String get name; String get status;
/// Create a copy of CustomerProfileDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CustomerProfileDtoCopyWith<CustomerProfileDto> get copyWith => _$CustomerProfileDtoCopyWithImpl<CustomerProfileDto>(this as CustomerProfileDto, _$identity);

  /// Serializes this CustomerProfileDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as CustomerProfileDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CustomerProfileDto&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.role, _this.role) || other.role == _this.role)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.status, _this.status) || other.status == _this.status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as CustomerProfileDto;
  return Object.hash(runtimeType,_this.id,_this.role,_this.name,_this.status);
}

@override
String toString() {
  final _this = this as CustomerProfileDto;
  return 'CustomerProfileDto(id: ${_this.id}, role: ${_this.role}, name: ${_this.name}, status: ${_this.status})';
}


}

/// @nodoc
abstract mixin class $CustomerProfileDtoCopyWith<$Res>  {
  factory $CustomerProfileDtoCopyWith(CustomerProfileDto value, $Res Function(CustomerProfileDto) _then) = _$CustomerProfileDtoCopyWithImpl;
@useResult
$Res call({
 String id, String role, String name, String status
});




}
/// @nodoc
class _$CustomerProfileDtoCopyWithImpl<$Res>
    implements $CustomerProfileDtoCopyWith<$Res> {
  _$CustomerProfileDtoCopyWithImpl(this._self, this._then);

  final CustomerProfileDto _self;
  final $Res Function(CustomerProfileDto) _then;

/// Create a copy of CustomerProfileDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? role = null,Object? name = null,Object? status = null,}) {
  return _then(CustomerProfileDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [CustomerProfileDto].
extension CustomerProfileDtoPatterns on CustomerProfileDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CustomerProfileDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CustomerProfileDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CustomerProfileDto value)  $default,){
final _that = this;
switch (_that) {
case _CustomerProfileDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CustomerProfileDto value)?  $default,){
final _that = this;
switch (_that) {
case _CustomerProfileDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String role,  String name,  String status)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CustomerProfileDto() when $default != null:
return $default(_that.id,_that.role,_that.name,_that.status);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String role,  String name,  String status)  $default,) {final _that = this;
switch (_that) {
case _CustomerProfileDto():
return $default(_that.id,_that.role,_that.name,_that.status);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String role,  String name,  String status)?  $default,) {final _that = this;
switch (_that) {
case _CustomerProfileDto() when $default != null:
return $default(_that.id,_that.role,_that.name,_that.status);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CustomerProfileDto implements CustomerProfileDto {
  const _CustomerProfileDto({required this.id, required this.role, required this.name, required this.status});
  factory _CustomerProfileDto.fromJson(Map<String, dynamic> json) => _$CustomerProfileDtoFromJson(json);

@override final  String id;
@override final  String role;
@override final  String name;
@override final  String status;

/// Create a copy of CustomerProfileDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CustomerProfileDtoCopyWith<_CustomerProfileDto> get copyWith => __$CustomerProfileDtoCopyWithImpl<_CustomerProfileDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CustomerProfileDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CustomerProfileDto&&(identical(other.id, id) || other.id == id)&&(identical(other.role, role) || other.role == role)&&(identical(other.name, name) || other.name == name)&&(identical(other.status, status) || other.status == status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,role,name,status);
}

@override
String toString() {
    return 'CustomerProfileDto(id: $id, role: $role, name: $name, status: $status)';
}


}

/// @nodoc
abstract mixin class _$CustomerProfileDtoCopyWith<$Res> implements $CustomerProfileDtoCopyWith<$Res> {
  factory _$CustomerProfileDtoCopyWith(_CustomerProfileDto value, $Res Function(_CustomerProfileDto) _then) = __$CustomerProfileDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String role, String name, String status
});




}
/// @nodoc
class __$CustomerProfileDtoCopyWithImpl<$Res>
    implements _$CustomerProfileDtoCopyWith<$Res> {
  __$CustomerProfileDtoCopyWithImpl(this._self, this._then);

  final _CustomerProfileDto _self;
  final $Res Function(_CustomerProfileDto) _then;

/// Create a copy of CustomerProfileDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? role = null,Object? name = null,Object? status = null,}) {
  return _then(_CustomerProfileDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
