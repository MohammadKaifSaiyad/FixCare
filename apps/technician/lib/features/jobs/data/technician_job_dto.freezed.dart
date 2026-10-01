// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'technician_job_dto.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$JobServiceDto {

 String get name; String get requiredSkill;
/// Create a copy of JobServiceDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JobServiceDtoCopyWith<JobServiceDto> get copyWith => _$JobServiceDtoCopyWithImpl<JobServiceDto>(this as JobServiceDto, _$identity);

  /// Serializes this JobServiceDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as JobServiceDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobServiceDto&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.requiredSkill, _this.requiredSkill) || other.requiredSkill == _this.requiredSkill));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as JobServiceDto;
  return Object.hash(runtimeType,_this.name,_this.requiredSkill);
}

@override
String toString() {
  final _this = this as JobServiceDto;
  return 'JobServiceDto(name: ${_this.name}, requiredSkill: ${_this.requiredSkill})';
}


}

/// @nodoc
abstract mixin class $JobServiceDtoCopyWith<$Res>  {
  factory $JobServiceDtoCopyWith(JobServiceDto value, $Res Function(JobServiceDto) _then) = _$JobServiceDtoCopyWithImpl;
@useResult
$Res call({
 String name, String requiredSkill
});




}
/// @nodoc
class _$JobServiceDtoCopyWithImpl<$Res>
    implements $JobServiceDtoCopyWith<$Res> {
  _$JobServiceDtoCopyWithImpl(this._self, this._then);

  final JobServiceDto _self;
  final $Res Function(JobServiceDto) _then;

/// Create a copy of JobServiceDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? requiredSkill = null,}) {
  return _then(JobServiceDto(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,requiredSkill: null == requiredSkill ? _self.requiredSkill : requiredSkill // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [JobServiceDto].
extension JobServiceDtoPatterns on JobServiceDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _JobServiceDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _JobServiceDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _JobServiceDto value)  $default,){
final _that = this;
switch (_that) {
case _JobServiceDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _JobServiceDto value)?  $default,){
final _that = this;
switch (_that) {
case _JobServiceDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String requiredSkill)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _JobServiceDto() when $default != null:
return $default(_that.name,_that.requiredSkill);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String requiredSkill)  $default,) {final _that = this;
switch (_that) {
case _JobServiceDto():
return $default(_that.name,_that.requiredSkill);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String requiredSkill)?  $default,) {final _that = this;
switch (_that) {
case _JobServiceDto() when $default != null:
return $default(_that.name,_that.requiredSkill);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _JobServiceDto implements JobServiceDto {
  const _JobServiceDto({required this.name, required this.requiredSkill});
  factory _JobServiceDto.fromJson(Map<String, dynamic> json) => _$JobServiceDtoFromJson(json);

@override final  String name;
@override final  String requiredSkill;

/// Create a copy of JobServiceDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$JobServiceDtoCopyWith<_JobServiceDto> get copyWith => __$JobServiceDtoCopyWithImpl<_JobServiceDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$JobServiceDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _JobServiceDto&&(identical(other.name, name) || other.name == name)&&(identical(other.requiredSkill, requiredSkill) || other.requiredSkill == requiredSkill));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,name,requiredSkill);
}

@override
String toString() {
    return 'JobServiceDto(name: $name, requiredSkill: $requiredSkill)';
}


}

/// @nodoc
abstract mixin class _$JobServiceDtoCopyWith<$Res> implements $JobServiceDtoCopyWith<$Res> {
  factory _$JobServiceDtoCopyWith(_JobServiceDto value, $Res Function(_JobServiceDto) _then) = __$JobServiceDtoCopyWithImpl;
@override @useResult
$Res call({
 String name, String requiredSkill
});




}
/// @nodoc
class __$JobServiceDtoCopyWithImpl<$Res>
    implements _$JobServiceDtoCopyWith<$Res> {
  __$JobServiceDtoCopyWithImpl(this._self, this._then);

  final _JobServiceDto _self;
  final $Res Function(_JobServiceDto) _then;

/// Create a copy of JobServiceDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? requiredSkill = null,}) {
  return _then(_JobServiceDto(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,requiredSkill: null == requiredSkill ? _self.requiredSkill : requiredSkill // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$JobZoneDto {

 String get name;
/// Create a copy of JobZoneDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JobZoneDtoCopyWith<JobZoneDto> get copyWith => _$JobZoneDtoCopyWithImpl<JobZoneDto>(this as JobZoneDto, _$identity);

  /// Serializes this JobZoneDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as JobZoneDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobZoneDto&&(identical(other.name, _this.name) || other.name == _this.name));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as JobZoneDto;
  return Object.hash(runtimeType,_this.name);
}

@override
String toString() {
  final _this = this as JobZoneDto;
  return 'JobZoneDto(name: ${_this.name})';
}


}

/// @nodoc
abstract mixin class $JobZoneDtoCopyWith<$Res>  {
  factory $JobZoneDtoCopyWith(JobZoneDto value, $Res Function(JobZoneDto) _then) = _$JobZoneDtoCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$JobZoneDtoCopyWithImpl<$Res>
    implements $JobZoneDtoCopyWith<$Res> {
  _$JobZoneDtoCopyWithImpl(this._self, this._then);

  final JobZoneDto _self;
  final $Res Function(JobZoneDto) _then;

/// Create a copy of JobZoneDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,}) {
  return _then(JobZoneDto(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [JobZoneDto].
extension JobZoneDtoPatterns on JobZoneDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _JobZoneDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _JobZoneDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _JobZoneDto value)  $default,){
final _that = this;
switch (_that) {
case _JobZoneDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _JobZoneDto value)?  $default,){
final _that = this;
switch (_that) {
case _JobZoneDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _JobZoneDto() when $default != null:
return $default(_that.name);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name)  $default,) {final _that = this;
switch (_that) {
case _JobZoneDto():
return $default(_that.name);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name)?  $default,) {final _that = this;
switch (_that) {
case _JobZoneDto() when $default != null:
return $default(_that.name);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _JobZoneDto implements JobZoneDto {
  const _JobZoneDto({required this.name});
  factory _JobZoneDto.fromJson(Map<String, dynamic> json) => _$JobZoneDtoFromJson(json);

@override final  String name;

/// Create a copy of JobZoneDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$JobZoneDtoCopyWith<_JobZoneDto> get copyWith => __$JobZoneDtoCopyWithImpl<_JobZoneDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$JobZoneDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _JobZoneDto&&(identical(other.name, name) || other.name == name));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,name);
}

@override
String toString() {
    return 'JobZoneDto(name: $name)';
}


}

/// @nodoc
abstract mixin class _$JobZoneDtoCopyWith<$Res> implements $JobZoneDtoCopyWith<$Res> {
  factory _$JobZoneDtoCopyWith(_JobZoneDto value, $Res Function(_JobZoneDto) _then) = __$JobZoneDtoCopyWithImpl;
@override @useResult
$Res call({
 String name
});




}
/// @nodoc
class __$JobZoneDtoCopyWithImpl<$Res>
    implements _$JobZoneDtoCopyWith<$Res> {
  __$JobZoneDtoCopyWithImpl(this._self, this._then);

  final _JobZoneDto _self;
  final $Res Function(_JobZoneDto) _then;

/// Create a copy of JobZoneDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(_JobZoneDto(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$JobAddressDto {

 String get line1; String? get line2; String? get landmark; String get pincode;
/// Create a copy of JobAddressDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JobAddressDtoCopyWith<JobAddressDto> get copyWith => _$JobAddressDtoCopyWithImpl<JobAddressDto>(this as JobAddressDto, _$identity);

  /// Serializes this JobAddressDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as JobAddressDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobAddressDto&&(identical(other.line1, _this.line1) || other.line1 == _this.line1)&&(identical(other.line2, _this.line2) || other.line2 == _this.line2)&&(identical(other.landmark, _this.landmark) || other.landmark == _this.landmark)&&(identical(other.pincode, _this.pincode) || other.pincode == _this.pincode));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as JobAddressDto;
  return Object.hash(runtimeType,_this.line1,_this.line2,_this.landmark,_this.pincode);
}

@override
String toString() {
  final _this = this as JobAddressDto;
  return 'JobAddressDto(line1: ${_this.line1}, line2: ${_this.line2}, landmark: ${_this.landmark}, pincode: ${_this.pincode})';
}


}

/// @nodoc
abstract mixin class $JobAddressDtoCopyWith<$Res>  {
  factory $JobAddressDtoCopyWith(JobAddressDto value, $Res Function(JobAddressDto) _then) = _$JobAddressDtoCopyWithImpl;
@useResult
$Res call({
 String line1, String? line2, String? landmark, String pincode
});




}
/// @nodoc
class _$JobAddressDtoCopyWithImpl<$Res>
    implements $JobAddressDtoCopyWith<$Res> {
  _$JobAddressDtoCopyWithImpl(this._self, this._then);

  final JobAddressDto _self;
  final $Res Function(JobAddressDto) _then;

/// Create a copy of JobAddressDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? line1 = null,Object? line2 = freezed,Object? landmark = freezed,Object? pincode = null,}) {
  return _then(JobAddressDto(
line1: null == line1 ? _self.line1 : line1 // ignore: cast_nullable_to_non_nullable
as String,line2: freezed == line2 ? _self.line2 : line2 // ignore: cast_nullable_to_non_nullable
as String?,landmark: freezed == landmark ? _self.landmark : landmark // ignore: cast_nullable_to_non_nullable
as String?,pincode: null == pincode ? _self.pincode : pincode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [JobAddressDto].
extension JobAddressDtoPatterns on JobAddressDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _JobAddressDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _JobAddressDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _JobAddressDto value)  $default,){
final _that = this;
switch (_that) {
case _JobAddressDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _JobAddressDto value)?  $default,){
final _that = this;
switch (_that) {
case _JobAddressDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String line1,  String? line2,  String? landmark,  String pincode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _JobAddressDto() when $default != null:
return $default(_that.line1,_that.line2,_that.landmark,_that.pincode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String line1,  String? line2,  String? landmark,  String pincode)  $default,) {final _that = this;
switch (_that) {
case _JobAddressDto():
return $default(_that.line1,_that.line2,_that.landmark,_that.pincode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String line1,  String? line2,  String? landmark,  String pincode)?  $default,) {final _that = this;
switch (_that) {
case _JobAddressDto() when $default != null:
return $default(_that.line1,_that.line2,_that.landmark,_that.pincode);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _JobAddressDto implements JobAddressDto {
  const _JobAddressDto({required this.line1, this.line2, this.landmark, required this.pincode});
  factory _JobAddressDto.fromJson(Map<String, dynamic> json) => _$JobAddressDtoFromJson(json);

@override final  String line1;
@override final  String? line2;
@override final  String? landmark;
@override final  String pincode;

/// Create a copy of JobAddressDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$JobAddressDtoCopyWith<_JobAddressDto> get copyWith => __$JobAddressDtoCopyWithImpl<_JobAddressDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$JobAddressDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _JobAddressDto&&(identical(other.line1, line1) || other.line1 == line1)&&(identical(other.line2, line2) || other.line2 == line2)&&(identical(other.landmark, landmark) || other.landmark == landmark)&&(identical(other.pincode, pincode) || other.pincode == pincode));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,line1,line2,landmark,pincode);
}

@override
String toString() {
    return 'JobAddressDto(line1: $line1, line2: $line2, landmark: $landmark, pincode: $pincode)';
}


}

/// @nodoc
abstract mixin class _$JobAddressDtoCopyWith<$Res> implements $JobAddressDtoCopyWith<$Res> {
  factory _$JobAddressDtoCopyWith(_JobAddressDto value, $Res Function(_JobAddressDto) _then) = __$JobAddressDtoCopyWithImpl;
@override @useResult
$Res call({
 String line1, String? line2, String? landmark, String pincode
});




}
/// @nodoc
class __$JobAddressDtoCopyWithImpl<$Res>
    implements _$JobAddressDtoCopyWith<$Res> {
  __$JobAddressDtoCopyWithImpl(this._self, this._then);

  final _JobAddressDto _self;
  final $Res Function(_JobAddressDto) _then;

/// Create a copy of JobAddressDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? line1 = null,Object? line2 = freezed,Object? landmark = freezed,Object? pincode = null,}) {
  return _then(_JobAddressDto(
line1: null == line1 ? _self.line1 : line1 // ignore: cast_nullable_to_non_nullable
as String,line2: freezed == line2 ? _self.line2 : line2 // ignore: cast_nullable_to_non_nullable
as String?,landmark: freezed == landmark ? _self.landmark : landmark // ignore: cast_nullable_to_non_nullable
as String?,pincode: null == pincode ? _self.pincode : pincode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$JobCustomerDto {

 String get maskedPhone;
/// Create a copy of JobCustomerDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JobCustomerDtoCopyWith<JobCustomerDto> get copyWith => _$JobCustomerDtoCopyWithImpl<JobCustomerDto>(this as JobCustomerDto, _$identity);

  /// Serializes this JobCustomerDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as JobCustomerDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobCustomerDto&&(identical(other.maskedPhone, _this.maskedPhone) || other.maskedPhone == _this.maskedPhone));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as JobCustomerDto;
  return Object.hash(runtimeType,_this.maskedPhone);
}

@override
String toString() {
  final _this = this as JobCustomerDto;
  return 'JobCustomerDto(maskedPhone: ${_this.maskedPhone})';
}


}

/// @nodoc
abstract mixin class $JobCustomerDtoCopyWith<$Res>  {
  factory $JobCustomerDtoCopyWith(JobCustomerDto value, $Res Function(JobCustomerDto) _then) = _$JobCustomerDtoCopyWithImpl;
@useResult
$Res call({
 String maskedPhone
});




}
/// @nodoc
class _$JobCustomerDtoCopyWithImpl<$Res>
    implements $JobCustomerDtoCopyWith<$Res> {
  _$JobCustomerDtoCopyWithImpl(this._self, this._then);

  final JobCustomerDto _self;
  final $Res Function(JobCustomerDto) _then;

/// Create a copy of JobCustomerDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? maskedPhone = null,}) {
  return _then(JobCustomerDto(
maskedPhone: null == maskedPhone ? _self.maskedPhone : maskedPhone // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [JobCustomerDto].
extension JobCustomerDtoPatterns on JobCustomerDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _JobCustomerDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _JobCustomerDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _JobCustomerDto value)  $default,){
final _that = this;
switch (_that) {
case _JobCustomerDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _JobCustomerDto value)?  $default,){
final _that = this;
switch (_that) {
case _JobCustomerDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String maskedPhone)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _JobCustomerDto() when $default != null:
return $default(_that.maskedPhone);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String maskedPhone)  $default,) {final _that = this;
switch (_that) {
case _JobCustomerDto():
return $default(_that.maskedPhone);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String maskedPhone)?  $default,) {final _that = this;
switch (_that) {
case _JobCustomerDto() when $default != null:
return $default(_that.maskedPhone);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _JobCustomerDto implements JobCustomerDto {
  const _JobCustomerDto({required this.maskedPhone});
  factory _JobCustomerDto.fromJson(Map<String, dynamic> json) => _$JobCustomerDtoFromJson(json);

@override final  String maskedPhone;

/// Create a copy of JobCustomerDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$JobCustomerDtoCopyWith<_JobCustomerDto> get copyWith => __$JobCustomerDtoCopyWithImpl<_JobCustomerDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$JobCustomerDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _JobCustomerDto&&(identical(other.maskedPhone, maskedPhone) || other.maskedPhone == maskedPhone));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,maskedPhone);
}

@override
String toString() {
    return 'JobCustomerDto(maskedPhone: $maskedPhone)';
}


}

/// @nodoc
abstract mixin class _$JobCustomerDtoCopyWith<$Res> implements $JobCustomerDtoCopyWith<$Res> {
  factory _$JobCustomerDtoCopyWith(_JobCustomerDto value, $Res Function(_JobCustomerDto) _then) = __$JobCustomerDtoCopyWithImpl;
@override @useResult
$Res call({
 String maskedPhone
});




}
/// @nodoc
class __$JobCustomerDtoCopyWithImpl<$Res>
    implements _$JobCustomerDtoCopyWith<$Res> {
  __$JobCustomerDtoCopyWithImpl(this._self, this._then);

  final _JobCustomerDto _self;
  final $Res Function(_JobCustomerDto) _then;

/// Create a copy of JobCustomerDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? maskedPhone = null,}) {
  return _then(_JobCustomerDto(
maskedPhone: null == maskedPhone ? _self.maskedPhone : maskedPhone // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$JobPhotoDto {

 String get kind; String get capturedAt; String get url;
/// Create a copy of JobPhotoDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JobPhotoDtoCopyWith<JobPhotoDto> get copyWith => _$JobPhotoDtoCopyWithImpl<JobPhotoDto>(this as JobPhotoDto, _$identity);

  /// Serializes this JobPhotoDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as JobPhotoDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobPhotoDto&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.capturedAt, _this.capturedAt) || other.capturedAt == _this.capturedAt)&&(identical(other.url, _this.url) || other.url == _this.url));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as JobPhotoDto;
  return Object.hash(runtimeType,_this.kind,_this.capturedAt,_this.url);
}

@override
String toString() {
  final _this = this as JobPhotoDto;
  return 'JobPhotoDto(kind: ${_this.kind}, capturedAt: ${_this.capturedAt}, url: ${_this.url})';
}


}

/// @nodoc
abstract mixin class $JobPhotoDtoCopyWith<$Res>  {
  factory $JobPhotoDtoCopyWith(JobPhotoDto value, $Res Function(JobPhotoDto) _then) = _$JobPhotoDtoCopyWithImpl;
@useResult
$Res call({
 String kind, String capturedAt, String url
});




}
/// @nodoc
class _$JobPhotoDtoCopyWithImpl<$Res>
    implements $JobPhotoDtoCopyWith<$Res> {
  _$JobPhotoDtoCopyWithImpl(this._self, this._then);

  final JobPhotoDto _self;
  final $Res Function(JobPhotoDto) _then;

/// Create a copy of JobPhotoDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? capturedAt = null,Object? url = null,}) {
  return _then(JobPhotoDto(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,capturedAt: null == capturedAt ? _self.capturedAt : capturedAt // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [JobPhotoDto].
extension JobPhotoDtoPatterns on JobPhotoDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _JobPhotoDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _JobPhotoDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _JobPhotoDto value)  $default,){
final _that = this;
switch (_that) {
case _JobPhotoDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _JobPhotoDto value)?  $default,){
final _that = this;
switch (_that) {
case _JobPhotoDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String kind,  String capturedAt,  String url)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _JobPhotoDto() when $default != null:
return $default(_that.kind,_that.capturedAt,_that.url);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String kind,  String capturedAt,  String url)  $default,) {final _that = this;
switch (_that) {
case _JobPhotoDto():
return $default(_that.kind,_that.capturedAt,_that.url);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String kind,  String capturedAt,  String url)?  $default,) {final _that = this;
switch (_that) {
case _JobPhotoDto() when $default != null:
return $default(_that.kind,_that.capturedAt,_that.url);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _JobPhotoDto implements JobPhotoDto {
  const _JobPhotoDto({required this.kind, required this.capturedAt, required this.url});
  factory _JobPhotoDto.fromJson(Map<String, dynamic> json) => _$JobPhotoDtoFromJson(json);

@override final  String kind;
@override final  String capturedAt;
@override final  String url;

/// Create a copy of JobPhotoDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$JobPhotoDtoCopyWith<_JobPhotoDto> get copyWith => __$JobPhotoDtoCopyWithImpl<_JobPhotoDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$JobPhotoDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _JobPhotoDto&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.capturedAt, capturedAt) || other.capturedAt == capturedAt)&&(identical(other.url, url) || other.url == url));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,kind,capturedAt,url);
}

@override
String toString() {
    return 'JobPhotoDto(kind: $kind, capturedAt: $capturedAt, url: $url)';
}


}

/// @nodoc
abstract mixin class _$JobPhotoDtoCopyWith<$Res> implements $JobPhotoDtoCopyWith<$Res> {
  factory _$JobPhotoDtoCopyWith(_JobPhotoDto value, $Res Function(_JobPhotoDto) _then) = __$JobPhotoDtoCopyWithImpl;
@override @useResult
$Res call({
 String kind, String capturedAt, String url
});




}
/// @nodoc
class __$JobPhotoDtoCopyWithImpl<$Res>
    implements _$JobPhotoDtoCopyWith<$Res> {
  __$JobPhotoDtoCopyWithImpl(this._self, this._then);

  final _JobPhotoDto _self;
  final $Res Function(_JobPhotoDto) _then;

/// Create a copy of JobPhotoDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? capturedAt = null,Object? url = null,}) {
  return _then(_JobPhotoDto(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,capturedAt: null == capturedAt ? _self.capturedAt : capturedAt // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$TechnicianJobDto {

 String get id; String get bookingNumber; String get state; String get scheduledSlot; JobServiceDto get service; JobZoneDto get zone; int get visitFeePaise; int get laborPaise; JobAddressDto get address; JobCustomerDto get customer; List<JobPhotoDto> get photos;
/// Create a copy of TechnicianJobDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TechnicianJobDtoCopyWith<TechnicianJobDto> get copyWith => _$TechnicianJobDtoCopyWithImpl<TechnicianJobDto>(this as TechnicianJobDto, _$identity);

  /// Serializes this TechnicianJobDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as TechnicianJobDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TechnicianJobDto&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.bookingNumber, _this.bookingNumber) || other.bookingNumber == _this.bookingNumber)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.scheduledSlot, _this.scheduledSlot) || other.scheduledSlot == _this.scheduledSlot)&&(identical(other.service, _this.service) || other.service == _this.service)&&(identical(other.zone, _this.zone) || other.zone == _this.zone)&&(identical(other.visitFeePaise, _this.visitFeePaise) || other.visitFeePaise == _this.visitFeePaise)&&(identical(other.laborPaise, _this.laborPaise) || other.laborPaise == _this.laborPaise)&&(identical(other.address, _this.address) || other.address == _this.address)&&(identical(other.customer, _this.customer) || other.customer == _this.customer)&&const DeepCollectionEquality().equals(other.photos, _this.photos));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as TechnicianJobDto;
  return Object.hash(runtimeType,_this.id,_this.bookingNumber,_this.state,_this.scheduledSlot,_this.service,_this.zone,_this.visitFeePaise,_this.laborPaise,_this.address,_this.customer,const DeepCollectionEquality().hash(_this.photos));
}

@override
String toString() {
  final _this = this as TechnicianJobDto;
  return 'TechnicianJobDto(id: ${_this.id}, bookingNumber: ${_this.bookingNumber}, state: ${_this.state}, scheduledSlot: ${_this.scheduledSlot}, service: ${_this.service}, zone: ${_this.zone}, visitFeePaise: ${_this.visitFeePaise}, laborPaise: ${_this.laborPaise}, address: ${_this.address}, customer: ${_this.customer}, photos: ${_this.photos})';
}


}

/// @nodoc
abstract mixin class $TechnicianJobDtoCopyWith<$Res>  {
  factory $TechnicianJobDtoCopyWith(TechnicianJobDto value, $Res Function(TechnicianJobDto) _then) = _$TechnicianJobDtoCopyWithImpl;
@useResult
$Res call({
 String id, String bookingNumber, String state, String scheduledSlot, JobServiceDto service, JobZoneDto zone, int visitFeePaise, int laborPaise, JobAddressDto address, JobCustomerDto customer, List<JobPhotoDto> photos
});


$JobServiceDtoCopyWith<$Res> get service;$JobZoneDtoCopyWith<$Res> get zone;$JobAddressDtoCopyWith<$Res> get address;$JobCustomerDtoCopyWith<$Res> get customer;

}
/// @nodoc
class _$TechnicianJobDtoCopyWithImpl<$Res>
    implements $TechnicianJobDtoCopyWith<$Res> {
  _$TechnicianJobDtoCopyWithImpl(this._self, this._then);

  final TechnicianJobDto _self;
  final $Res Function(TechnicianJobDto) _then;

/// Create a copy of TechnicianJobDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? bookingNumber = null,Object? state = null,Object? scheduledSlot = null,Object? service = null,Object? zone = null,Object? visitFeePaise = null,Object? laborPaise = null,Object? address = null,Object? customer = null,Object? photos = null,}) {
  return _then(TechnicianJobDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,bookingNumber: null == bookingNumber ? _self.bookingNumber : bookingNumber // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,scheduledSlot: null == scheduledSlot ? _self.scheduledSlot : scheduledSlot // ignore: cast_nullable_to_non_nullable
as String,service: null == service ? _self.service : service // ignore: cast_nullable_to_non_nullable
as JobServiceDto,zone: null == zone ? _self.zone : zone // ignore: cast_nullable_to_non_nullable
as JobZoneDto,visitFeePaise: null == visitFeePaise ? _self.visitFeePaise : visitFeePaise // ignore: cast_nullable_to_non_nullable
as int,laborPaise: null == laborPaise ? _self.laborPaise : laborPaise // ignore: cast_nullable_to_non_nullable
as int,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as JobAddressDto,customer: null == customer ? _self.customer : customer // ignore: cast_nullable_to_non_nullable
as JobCustomerDto,photos: null == photos ? _self.photos : photos // ignore: cast_nullable_to_non_nullable
as List<JobPhotoDto>,
  ));
}
/// Create a copy of TechnicianJobDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JobServiceDtoCopyWith<$Res> get service {
  
  return $JobServiceDtoCopyWith<$Res>(_self.service, (value) {
    return _then(_self.copyWith(service: value));
  });
}/// Create a copy of TechnicianJobDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JobZoneDtoCopyWith<$Res> get zone {
  
  return $JobZoneDtoCopyWith<$Res>(_self.zone, (value) {
    return _then(_self.copyWith(zone: value));
  });
}/// Create a copy of TechnicianJobDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JobAddressDtoCopyWith<$Res> get address {
  
  return $JobAddressDtoCopyWith<$Res>(_self.address, (value) {
    return _then(_self.copyWith(address: value));
  });
}/// Create a copy of TechnicianJobDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JobCustomerDtoCopyWith<$Res> get customer {
  
  return $JobCustomerDtoCopyWith<$Res>(_self.customer, (value) {
    return _then(_self.copyWith(customer: value));
  });
}
}


/// Adds pattern-matching-related methods to [TechnicianJobDto].
extension TechnicianJobDtoPatterns on TechnicianJobDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TechnicianJobDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TechnicianJobDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TechnicianJobDto value)  $default,){
final _that = this;
switch (_that) {
case _TechnicianJobDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TechnicianJobDto value)?  $default,){
final _that = this;
switch (_that) {
case _TechnicianJobDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String bookingNumber,  String state,  String scheduledSlot,  JobServiceDto service,  JobZoneDto zone,  int visitFeePaise,  int laborPaise,  JobAddressDto address,  JobCustomerDto customer,  List<JobPhotoDto> photos)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TechnicianJobDto() when $default != null:
return $default(_that.id,_that.bookingNumber,_that.state,_that.scheduledSlot,_that.service,_that.zone,_that.visitFeePaise,_that.laborPaise,_that.address,_that.customer,_that.photos);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String bookingNumber,  String state,  String scheduledSlot,  JobServiceDto service,  JobZoneDto zone,  int visitFeePaise,  int laborPaise,  JobAddressDto address,  JobCustomerDto customer,  List<JobPhotoDto> photos)  $default,) {final _that = this;
switch (_that) {
case _TechnicianJobDto():
return $default(_that.id,_that.bookingNumber,_that.state,_that.scheduledSlot,_that.service,_that.zone,_that.visitFeePaise,_that.laborPaise,_that.address,_that.customer,_that.photos);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String bookingNumber,  String state,  String scheduledSlot,  JobServiceDto service,  JobZoneDto zone,  int visitFeePaise,  int laborPaise,  JobAddressDto address,  JobCustomerDto customer,  List<JobPhotoDto> photos)?  $default,) {final _that = this;
switch (_that) {
case _TechnicianJobDto() when $default != null:
return $default(_that.id,_that.bookingNumber,_that.state,_that.scheduledSlot,_that.service,_that.zone,_that.visitFeePaise,_that.laborPaise,_that.address,_that.customer,_that.photos);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TechnicianJobDto implements TechnicianJobDto {
  const _TechnicianJobDto({required this.id, required this.bookingNumber, required this.state, required this.scheduledSlot, required this.service, required this.zone, required this.visitFeePaise, required this.laborPaise, required this.address, required this.customer,  List<JobPhotoDto> photos = const <JobPhotoDto>[]}): _photos = photos;
  factory _TechnicianJobDto.fromJson(Map<String, dynamic> json) => _$TechnicianJobDtoFromJson(json);

@override final  String id;
@override final  String bookingNumber;
@override final  String state;
@override final  String scheduledSlot;
@override final  JobServiceDto service;
@override final  JobZoneDto zone;
@override final  int visitFeePaise;
@override final  int laborPaise;
@override final  JobAddressDto address;
@override final  JobCustomerDto customer;
 final  List<JobPhotoDto> _photos;
@override@JsonKey() List<JobPhotoDto> get photos {
  if (_photos is EqualUnmodifiableListView) return _photos;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_photos);
}


/// Create a copy of TechnicianJobDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TechnicianJobDtoCopyWith<_TechnicianJobDto> get copyWith => __$TechnicianJobDtoCopyWithImpl<_TechnicianJobDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TechnicianJobDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TechnicianJobDto&&(identical(other.id, id) || other.id == id)&&(identical(other.bookingNumber, bookingNumber) || other.bookingNumber == bookingNumber)&&(identical(other.state, state) || other.state == state)&&(identical(other.scheduledSlot, scheduledSlot) || other.scheduledSlot == scheduledSlot)&&(identical(other.service, service) || other.service == service)&&(identical(other.zone, zone) || other.zone == zone)&&(identical(other.visitFeePaise, visitFeePaise) || other.visitFeePaise == visitFeePaise)&&(identical(other.laborPaise, laborPaise) || other.laborPaise == laborPaise)&&(identical(other.address, address) || other.address == address)&&(identical(other.customer, customer) || other.customer == customer)&&const DeepCollectionEquality().equals(other.photos, _photos));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,bookingNumber,state,scheduledSlot,service,zone,visitFeePaise,laborPaise,address,customer,const DeepCollectionEquality().hash(_photos));
}

@override
String toString() {
    return 'TechnicianJobDto(id: $id, bookingNumber: $bookingNumber, state: $state, scheduledSlot: $scheduledSlot, service: $service, zone: $zone, visitFeePaise: $visitFeePaise, laborPaise: $laborPaise, address: $address, customer: $customer, photos: $photos)';
}


}

/// @nodoc
abstract mixin class _$TechnicianJobDtoCopyWith<$Res> implements $TechnicianJobDtoCopyWith<$Res> {
  factory _$TechnicianJobDtoCopyWith(_TechnicianJobDto value, $Res Function(_TechnicianJobDto) _then) = __$TechnicianJobDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String bookingNumber, String state, String scheduledSlot, JobServiceDto service, JobZoneDto zone, int visitFeePaise, int laborPaise, JobAddressDto address, JobCustomerDto customer, List<JobPhotoDto> photos
});


@override $JobServiceDtoCopyWith<$Res> get service;@override $JobZoneDtoCopyWith<$Res> get zone;@override $JobAddressDtoCopyWith<$Res> get address;@override $JobCustomerDtoCopyWith<$Res> get customer;

}
/// @nodoc
class __$TechnicianJobDtoCopyWithImpl<$Res>
    implements _$TechnicianJobDtoCopyWith<$Res> {
  __$TechnicianJobDtoCopyWithImpl(this._self, this._then);

  final _TechnicianJobDto _self;
  final $Res Function(_TechnicianJobDto) _then;

/// Create a copy of TechnicianJobDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? bookingNumber = null,Object? state = null,Object? scheduledSlot = null,Object? service = null,Object? zone = null,Object? visitFeePaise = null,Object? laborPaise = null,Object? address = null,Object? customer = null,Object? photos = null,}) {
  return _then(_TechnicianJobDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,bookingNumber: null == bookingNumber ? _self.bookingNumber : bookingNumber // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,scheduledSlot: null == scheduledSlot ? _self.scheduledSlot : scheduledSlot // ignore: cast_nullable_to_non_nullable
as String,service: null == service ? _self.service : service // ignore: cast_nullable_to_non_nullable
as JobServiceDto,zone: null == zone ? _self.zone : zone // ignore: cast_nullable_to_non_nullable
as JobZoneDto,visitFeePaise: null == visitFeePaise ? _self.visitFeePaise : visitFeePaise // ignore: cast_nullable_to_non_nullable
as int,laborPaise: null == laborPaise ? _self.laborPaise : laborPaise // ignore: cast_nullable_to_non_nullable
as int,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as JobAddressDto,customer: null == customer ? _self.customer : customer // ignore: cast_nullable_to_non_nullable
as JobCustomerDto,photos: null == photos ? _self._photos : photos // ignore: cast_nullable_to_non_nullable
as List<JobPhotoDto>,
  ));
}

/// Create a copy of TechnicianJobDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JobServiceDtoCopyWith<$Res> get service {
  
  return $JobServiceDtoCopyWith<$Res>(_self.service, (value) {
    return _then(_self.copyWith(service: value));
  });
}/// Create a copy of TechnicianJobDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JobZoneDtoCopyWith<$Res> get zone {
  
  return $JobZoneDtoCopyWith<$Res>(_self.zone, (value) {
    return _then(_self.copyWith(zone: value));
  });
}/// Create a copy of TechnicianJobDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JobAddressDtoCopyWith<$Res> get address {
  
  return $JobAddressDtoCopyWith<$Res>(_self.address, (value) {
    return _then(_self.copyWith(address: value));
  });
}/// Create a copy of TechnicianJobDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JobCustomerDtoCopyWith<$Res> get customer {
  
  return $JobCustomerDtoCopyWith<$Res>(_self.customer, (value) {
    return _then(_self.copyWith(customer: value));
  });
}
}


/// @nodoc
mixin _$ArriveResultDto {

 String get arrivalCode; bool? get withinGeofence;
/// Create a copy of ArriveResultDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ArriveResultDtoCopyWith<ArriveResultDto> get copyWith => _$ArriveResultDtoCopyWithImpl<ArriveResultDto>(this as ArriveResultDto, _$identity);

  /// Serializes this ArriveResultDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ArriveResultDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ArriveResultDto&&(identical(other.arrivalCode, _this.arrivalCode) || other.arrivalCode == _this.arrivalCode)&&(identical(other.withinGeofence, _this.withinGeofence) || other.withinGeofence == _this.withinGeofence));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ArriveResultDto;
  return Object.hash(runtimeType,_this.arrivalCode,_this.withinGeofence);
}

@override
String toString() {
  final _this = this as ArriveResultDto;
  return 'ArriveResultDto(arrivalCode: ${_this.arrivalCode}, withinGeofence: ${_this.withinGeofence})';
}


}

/// @nodoc
abstract mixin class $ArriveResultDtoCopyWith<$Res>  {
  factory $ArriveResultDtoCopyWith(ArriveResultDto value, $Res Function(ArriveResultDto) _then) = _$ArriveResultDtoCopyWithImpl;
@useResult
$Res call({
 String arrivalCode, bool? withinGeofence
});




}
/// @nodoc
class _$ArriveResultDtoCopyWithImpl<$Res>
    implements $ArriveResultDtoCopyWith<$Res> {
  _$ArriveResultDtoCopyWithImpl(this._self, this._then);

  final ArriveResultDto _self;
  final $Res Function(ArriveResultDto) _then;

/// Create a copy of ArriveResultDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? arrivalCode = null,Object? withinGeofence = freezed,}) {
  return _then(ArriveResultDto(
arrivalCode: null == arrivalCode ? _self.arrivalCode : arrivalCode // ignore: cast_nullable_to_non_nullable
as String,withinGeofence: freezed == withinGeofence ? _self.withinGeofence : withinGeofence // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

}


/// Adds pattern-matching-related methods to [ArriveResultDto].
extension ArriveResultDtoPatterns on ArriveResultDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ArriveResultDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ArriveResultDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ArriveResultDto value)  $default,){
final _that = this;
switch (_that) {
case _ArriveResultDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ArriveResultDto value)?  $default,){
final _that = this;
switch (_that) {
case _ArriveResultDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String arrivalCode,  bool? withinGeofence)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ArriveResultDto() when $default != null:
return $default(_that.arrivalCode,_that.withinGeofence);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String arrivalCode,  bool? withinGeofence)  $default,) {final _that = this;
switch (_that) {
case _ArriveResultDto():
return $default(_that.arrivalCode,_that.withinGeofence);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String arrivalCode,  bool? withinGeofence)?  $default,) {final _that = this;
switch (_that) {
case _ArriveResultDto() when $default != null:
return $default(_that.arrivalCode,_that.withinGeofence);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ArriveResultDto implements ArriveResultDto {
  const _ArriveResultDto({required this.arrivalCode, this.withinGeofence});
  factory _ArriveResultDto.fromJson(Map<String, dynamic> json) => _$ArriveResultDtoFromJson(json);

@override final  String arrivalCode;
@override final  bool? withinGeofence;

/// Create a copy of ArriveResultDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ArriveResultDtoCopyWith<_ArriveResultDto> get copyWith => __$ArriveResultDtoCopyWithImpl<_ArriveResultDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ArriveResultDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ArriveResultDto&&(identical(other.arrivalCode, arrivalCode) || other.arrivalCode == arrivalCode)&&(identical(other.withinGeofence, withinGeofence) || other.withinGeofence == withinGeofence));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,arrivalCode,withinGeofence);
}

@override
String toString() {
    return 'ArriveResultDto(arrivalCode: $arrivalCode, withinGeofence: $withinGeofence)';
}


}

/// @nodoc
abstract mixin class _$ArriveResultDtoCopyWith<$Res> implements $ArriveResultDtoCopyWith<$Res> {
  factory _$ArriveResultDtoCopyWith(_ArriveResultDto value, $Res Function(_ArriveResultDto) _then) = __$ArriveResultDtoCopyWithImpl;
@override @useResult
$Res call({
 String arrivalCode, bool? withinGeofence
});




}
/// @nodoc
class __$ArriveResultDtoCopyWithImpl<$Res>
    implements _$ArriveResultDtoCopyWith<$Res> {
  __$ArriveResultDtoCopyWithImpl(this._self, this._then);

  final _ArriveResultDto _self;
  final $Res Function(_ArriveResultDto) _then;

/// Create a copy of ArriveResultDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? arrivalCode = null,Object? withinGeofence = freezed,}) {
  return _then(_ArriveResultDto(
arrivalCode: null == arrivalCode ? _self.arrivalCode : arrivalCode // ignore: cast_nullable_to_non_nullable
as String,withinGeofence: freezed == withinGeofence ? _self.withinGeofence : withinGeofence // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}


/// @nodoc
mixin _$CashResultDto {

 String get id; String get state; int get cashDebtPaise;
/// Create a copy of CashResultDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CashResultDtoCopyWith<CashResultDto> get copyWith => _$CashResultDtoCopyWithImpl<CashResultDto>(this as CashResultDto, _$identity);

  /// Serializes this CashResultDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as CashResultDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CashResultDto&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.cashDebtPaise, _this.cashDebtPaise) || other.cashDebtPaise == _this.cashDebtPaise));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as CashResultDto;
  return Object.hash(runtimeType,_this.id,_this.state,_this.cashDebtPaise);
}

@override
String toString() {
  final _this = this as CashResultDto;
  return 'CashResultDto(id: ${_this.id}, state: ${_this.state}, cashDebtPaise: ${_this.cashDebtPaise})';
}


}

/// @nodoc
abstract mixin class $CashResultDtoCopyWith<$Res>  {
  factory $CashResultDtoCopyWith(CashResultDto value, $Res Function(CashResultDto) _then) = _$CashResultDtoCopyWithImpl;
@useResult
$Res call({
 String id, String state, int cashDebtPaise
});




}
/// @nodoc
class _$CashResultDtoCopyWithImpl<$Res>
    implements $CashResultDtoCopyWith<$Res> {
  _$CashResultDtoCopyWithImpl(this._self, this._then);

  final CashResultDto _self;
  final $Res Function(CashResultDto) _then;

/// Create a copy of CashResultDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? state = null,Object? cashDebtPaise = null,}) {
  return _then(CashResultDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,cashDebtPaise: null == cashDebtPaise ? _self.cashDebtPaise : cashDebtPaise // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [CashResultDto].
extension CashResultDtoPatterns on CashResultDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CashResultDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CashResultDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CashResultDto value)  $default,){
final _that = this;
switch (_that) {
case _CashResultDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CashResultDto value)?  $default,){
final _that = this;
switch (_that) {
case _CashResultDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String state,  int cashDebtPaise)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CashResultDto() when $default != null:
return $default(_that.id,_that.state,_that.cashDebtPaise);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String state,  int cashDebtPaise)  $default,) {final _that = this;
switch (_that) {
case _CashResultDto():
return $default(_that.id,_that.state,_that.cashDebtPaise);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String state,  int cashDebtPaise)?  $default,) {final _that = this;
switch (_that) {
case _CashResultDto() when $default != null:
return $default(_that.id,_that.state,_that.cashDebtPaise);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CashResultDto implements CashResultDto {
  const _CashResultDto({required this.id, required this.state, required this.cashDebtPaise});
  factory _CashResultDto.fromJson(Map<String, dynamic> json) => _$CashResultDtoFromJson(json);

@override final  String id;
@override final  String state;
@override final  int cashDebtPaise;

/// Create a copy of CashResultDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CashResultDtoCopyWith<_CashResultDto> get copyWith => __$CashResultDtoCopyWithImpl<_CashResultDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CashResultDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CashResultDto&&(identical(other.id, id) || other.id == id)&&(identical(other.state, state) || other.state == state)&&(identical(other.cashDebtPaise, cashDebtPaise) || other.cashDebtPaise == cashDebtPaise));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,state,cashDebtPaise);
}

@override
String toString() {
    return 'CashResultDto(id: $id, state: $state, cashDebtPaise: $cashDebtPaise)';
}


}

/// @nodoc
abstract mixin class _$CashResultDtoCopyWith<$Res> implements $CashResultDtoCopyWith<$Res> {
  factory _$CashResultDtoCopyWith(_CashResultDto value, $Res Function(_CashResultDto) _then) = __$CashResultDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String state, int cashDebtPaise
});




}
/// @nodoc
class __$CashResultDtoCopyWithImpl<$Res>
    implements _$CashResultDtoCopyWith<$Res> {
  __$CashResultDtoCopyWithImpl(this._self, this._then);

  final _CashResultDto _self;
  final $Res Function(_CashResultDto) _then;

/// Create a copy of CashResultDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? state = null,Object? cashDebtPaise = null,}) {
  return _then(_CashResultDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,cashDebtPaise: null == cashDebtPaise ? _self.cashDebtPaise : cashDebtPaise // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$PhotoSignDto {

 String get url; String get key; String get expiresAt;
/// Create a copy of PhotoSignDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PhotoSignDtoCopyWith<PhotoSignDto> get copyWith => _$PhotoSignDtoCopyWithImpl<PhotoSignDto>(this as PhotoSignDto, _$identity);

  /// Serializes this PhotoSignDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PhotoSignDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PhotoSignDto&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.expiresAt, _this.expiresAt) || other.expiresAt == _this.expiresAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PhotoSignDto;
  return Object.hash(runtimeType,_this.url,_this.key,_this.expiresAt);
}

@override
String toString() {
  final _this = this as PhotoSignDto;
  return 'PhotoSignDto(url: ${_this.url}, key: ${_this.key}, expiresAt: ${_this.expiresAt})';
}


}

/// @nodoc
abstract mixin class $PhotoSignDtoCopyWith<$Res>  {
  factory $PhotoSignDtoCopyWith(PhotoSignDto value, $Res Function(PhotoSignDto) _then) = _$PhotoSignDtoCopyWithImpl;
@useResult
$Res call({
 String url, String key, String expiresAt
});




}
/// @nodoc
class _$PhotoSignDtoCopyWithImpl<$Res>
    implements $PhotoSignDtoCopyWith<$Res> {
  _$PhotoSignDtoCopyWithImpl(this._self, this._then);

  final PhotoSignDto _self;
  final $Res Function(PhotoSignDto) _then;

/// Create a copy of PhotoSignDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? url = null,Object? key = null,Object? expiresAt = null,}) {
  return _then(PhotoSignDto(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,expiresAt: null == expiresAt ? _self.expiresAt : expiresAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [PhotoSignDto].
extension PhotoSignDtoPatterns on PhotoSignDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PhotoSignDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PhotoSignDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PhotoSignDto value)  $default,){
final _that = this;
switch (_that) {
case _PhotoSignDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PhotoSignDto value)?  $default,){
final _that = this;
switch (_that) {
case _PhotoSignDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String url,  String key,  String expiresAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PhotoSignDto() when $default != null:
return $default(_that.url,_that.key,_that.expiresAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String url,  String key,  String expiresAt)  $default,) {final _that = this;
switch (_that) {
case _PhotoSignDto():
return $default(_that.url,_that.key,_that.expiresAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String url,  String key,  String expiresAt)?  $default,) {final _that = this;
switch (_that) {
case _PhotoSignDto() when $default != null:
return $default(_that.url,_that.key,_that.expiresAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PhotoSignDto implements PhotoSignDto {
  const _PhotoSignDto({required this.url, required this.key, required this.expiresAt});
  factory _PhotoSignDto.fromJson(Map<String, dynamic> json) => _$PhotoSignDtoFromJson(json);

@override final  String url;
@override final  String key;
@override final  String expiresAt;

/// Create a copy of PhotoSignDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PhotoSignDtoCopyWith<_PhotoSignDto> get copyWith => __$PhotoSignDtoCopyWithImpl<_PhotoSignDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PhotoSignDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PhotoSignDto&&(identical(other.url, url) || other.url == url)&&(identical(other.key, key) || other.key == key)&&(identical(other.expiresAt, expiresAt) || other.expiresAt == expiresAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,url,key,expiresAt);
}

@override
String toString() {
    return 'PhotoSignDto(url: $url, key: $key, expiresAt: $expiresAt)';
}


}

/// @nodoc
abstract mixin class _$PhotoSignDtoCopyWith<$Res> implements $PhotoSignDtoCopyWith<$Res> {
  factory _$PhotoSignDtoCopyWith(_PhotoSignDto value, $Res Function(_PhotoSignDto) _then) = __$PhotoSignDtoCopyWithImpl;
@override @useResult
$Res call({
 String url, String key, String expiresAt
});




}
/// @nodoc
class __$PhotoSignDtoCopyWithImpl<$Res>
    implements _$PhotoSignDtoCopyWith<$Res> {
  __$PhotoSignDtoCopyWithImpl(this._self, this._then);

  final _PhotoSignDto _self;
  final $Res Function(_PhotoSignDto) _then;

/// Create a copy of PhotoSignDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? url = null,Object? key = null,Object? expiresAt = null,}) {
  return _then(_PhotoSignDto(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,expiresAt: null == expiresAt ? _self.expiresAt : expiresAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$PhotoConfirmDto {

 String get id; String get kind; String get capturedAt;
/// Create a copy of PhotoConfirmDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PhotoConfirmDtoCopyWith<PhotoConfirmDto> get copyWith => _$PhotoConfirmDtoCopyWithImpl<PhotoConfirmDto>(this as PhotoConfirmDto, _$identity);

  /// Serializes this PhotoConfirmDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PhotoConfirmDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PhotoConfirmDto&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.capturedAt, _this.capturedAt) || other.capturedAt == _this.capturedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PhotoConfirmDto;
  return Object.hash(runtimeType,_this.id,_this.kind,_this.capturedAt);
}

@override
String toString() {
  final _this = this as PhotoConfirmDto;
  return 'PhotoConfirmDto(id: ${_this.id}, kind: ${_this.kind}, capturedAt: ${_this.capturedAt})';
}


}

/// @nodoc
abstract mixin class $PhotoConfirmDtoCopyWith<$Res>  {
  factory $PhotoConfirmDtoCopyWith(PhotoConfirmDto value, $Res Function(PhotoConfirmDto) _then) = _$PhotoConfirmDtoCopyWithImpl;
@useResult
$Res call({
 String id, String kind, String capturedAt
});




}
/// @nodoc
class _$PhotoConfirmDtoCopyWithImpl<$Res>
    implements $PhotoConfirmDtoCopyWith<$Res> {
  _$PhotoConfirmDtoCopyWithImpl(this._self, this._then);

  final PhotoConfirmDto _self;
  final $Res Function(PhotoConfirmDto) _then;

/// Create a copy of PhotoConfirmDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? kind = null,Object? capturedAt = null,}) {
  return _then(PhotoConfirmDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,capturedAt: null == capturedAt ? _self.capturedAt : capturedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [PhotoConfirmDto].
extension PhotoConfirmDtoPatterns on PhotoConfirmDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PhotoConfirmDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PhotoConfirmDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PhotoConfirmDto value)  $default,){
final _that = this;
switch (_that) {
case _PhotoConfirmDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PhotoConfirmDto value)?  $default,){
final _that = this;
switch (_that) {
case _PhotoConfirmDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String kind,  String capturedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PhotoConfirmDto() when $default != null:
return $default(_that.id,_that.kind,_that.capturedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String kind,  String capturedAt)  $default,) {final _that = this;
switch (_that) {
case _PhotoConfirmDto():
return $default(_that.id,_that.kind,_that.capturedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String kind,  String capturedAt)?  $default,) {final _that = this;
switch (_that) {
case _PhotoConfirmDto() when $default != null:
return $default(_that.id,_that.kind,_that.capturedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PhotoConfirmDto implements PhotoConfirmDto {
  const _PhotoConfirmDto({required this.id, required this.kind, required this.capturedAt});
  factory _PhotoConfirmDto.fromJson(Map<String, dynamic> json) => _$PhotoConfirmDtoFromJson(json);

@override final  String id;
@override final  String kind;
@override final  String capturedAt;

/// Create a copy of PhotoConfirmDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PhotoConfirmDtoCopyWith<_PhotoConfirmDto> get copyWith => __$PhotoConfirmDtoCopyWithImpl<_PhotoConfirmDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PhotoConfirmDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PhotoConfirmDto&&(identical(other.id, id) || other.id == id)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.capturedAt, capturedAt) || other.capturedAt == capturedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,kind,capturedAt);
}

@override
String toString() {
    return 'PhotoConfirmDto(id: $id, kind: $kind, capturedAt: $capturedAt)';
}


}

/// @nodoc
abstract mixin class _$PhotoConfirmDtoCopyWith<$Res> implements $PhotoConfirmDtoCopyWith<$Res> {
  factory _$PhotoConfirmDtoCopyWith(_PhotoConfirmDto value, $Res Function(_PhotoConfirmDto) _then) = __$PhotoConfirmDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String kind, String capturedAt
});




}
/// @nodoc
class __$PhotoConfirmDtoCopyWithImpl<$Res>
    implements _$PhotoConfirmDtoCopyWith<$Res> {
  __$PhotoConfirmDtoCopyWithImpl(this._self, this._then);

  final _PhotoConfirmDto _self;
  final $Res Function(_PhotoConfirmDto) _then;

/// Create a copy of PhotoConfirmDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? kind = null,Object? capturedAt = null,}) {
  return _then(_PhotoConfirmDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,capturedAt: null == capturedAt ? _self.capturedAt : capturedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
