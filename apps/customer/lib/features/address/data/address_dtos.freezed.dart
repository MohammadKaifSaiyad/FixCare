// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'address_dtos.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ZoneDto {

 String get id; String get name; int get visitFeePaise;
/// Create a copy of ZoneDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ZoneDtoCopyWith<ZoneDto> get copyWith => _$ZoneDtoCopyWithImpl<ZoneDto>(this as ZoneDto, _$identity);

  /// Serializes this ZoneDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ZoneDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ZoneDto&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.visitFeePaise, _this.visitFeePaise) || other.visitFeePaise == _this.visitFeePaise));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ZoneDto;
  return Object.hash(runtimeType,_this.id,_this.name,_this.visitFeePaise);
}

@override
String toString() {
  final _this = this as ZoneDto;
  return 'ZoneDto(id: ${_this.id}, name: ${_this.name}, visitFeePaise: ${_this.visitFeePaise})';
}


}

/// @nodoc
abstract mixin class $ZoneDtoCopyWith<$Res>  {
  factory $ZoneDtoCopyWith(ZoneDto value, $Res Function(ZoneDto) _then) = _$ZoneDtoCopyWithImpl;
@useResult
$Res call({
 String id, String name, int visitFeePaise
});




}
/// @nodoc
class _$ZoneDtoCopyWithImpl<$Res>
    implements $ZoneDtoCopyWith<$Res> {
  _$ZoneDtoCopyWithImpl(this._self, this._then);

  final ZoneDto _self;
  final $Res Function(ZoneDto) _then;

/// Create a copy of ZoneDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? visitFeePaise = null,}) {
  return _then(ZoneDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,visitFeePaise: null == visitFeePaise ? _self.visitFeePaise : visitFeePaise // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ZoneDto].
extension ZoneDtoPatterns on ZoneDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ZoneDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ZoneDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ZoneDto value)  $default,){
final _that = this;
switch (_that) {
case _ZoneDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ZoneDto value)?  $default,){
final _that = this;
switch (_that) {
case _ZoneDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  int visitFeePaise)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ZoneDto() when $default != null:
return $default(_that.id,_that.name,_that.visitFeePaise);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  int visitFeePaise)  $default,) {final _that = this;
switch (_that) {
case _ZoneDto():
return $default(_that.id,_that.name,_that.visitFeePaise);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  int visitFeePaise)?  $default,) {final _that = this;
switch (_that) {
case _ZoneDto() when $default != null:
return $default(_that.id,_that.name,_that.visitFeePaise);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ZoneDto implements ZoneDto {
  const _ZoneDto({required this.id, required this.name, required this.visitFeePaise});
  factory _ZoneDto.fromJson(Map<String, dynamic> json) => _$ZoneDtoFromJson(json);

@override final  String id;
@override final  String name;
@override final  int visitFeePaise;

/// Create a copy of ZoneDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ZoneDtoCopyWith<_ZoneDto> get copyWith => __$ZoneDtoCopyWithImpl<_ZoneDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ZoneDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ZoneDto&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.visitFeePaise, visitFeePaise) || other.visitFeePaise == visitFeePaise));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,name,visitFeePaise);
}

@override
String toString() {
    return 'ZoneDto(id: $id, name: $name, visitFeePaise: $visitFeePaise)';
}


}

/// @nodoc
abstract mixin class _$ZoneDtoCopyWith<$Res> implements $ZoneDtoCopyWith<$Res> {
  factory _$ZoneDtoCopyWith(_ZoneDto value, $Res Function(_ZoneDto) _then) = __$ZoneDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, int visitFeePaise
});




}
/// @nodoc
class __$ZoneDtoCopyWithImpl<$Res>
    implements _$ZoneDtoCopyWith<$Res> {
  __$ZoneDtoCopyWithImpl(this._self, this._then);

  final _ZoneDto _self;
  final $Res Function(_ZoneDto) _then;

/// Create a copy of ZoneDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? visitFeePaise = null,}) {
  return _then(_ZoneDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,visitFeePaise: null == visitFeePaise ? _self.visitFeePaise : visitFeePaise // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$AddressDto {

 String get id; String get label; String get line1; String? get line2; String? get landmark; String get pincode; double? get lat; double? get lng; bool get isDefault; String get status; bool get serviceable; ZoneDto? get zone; String? get message;
/// Create a copy of AddressDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddressDtoCopyWith<AddressDto> get copyWith => _$AddressDtoCopyWithImpl<AddressDto>(this as AddressDto, _$identity);

  /// Serializes this AddressDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as AddressDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddressDto&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.line1, _this.line1) || other.line1 == _this.line1)&&(identical(other.line2, _this.line2) || other.line2 == _this.line2)&&(identical(other.landmark, _this.landmark) || other.landmark == _this.landmark)&&(identical(other.pincode, _this.pincode) || other.pincode == _this.pincode)&&(identical(other.lat, _this.lat) || other.lat == _this.lat)&&(identical(other.lng, _this.lng) || other.lng == _this.lng)&&(identical(other.isDefault, _this.isDefault) || other.isDefault == _this.isDefault)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.serviceable, _this.serviceable) || other.serviceable == _this.serviceable)&&(identical(other.zone, _this.zone) || other.zone == _this.zone)&&(identical(other.message, _this.message) || other.message == _this.message));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as AddressDto;
  return Object.hash(runtimeType,_this.id,_this.label,_this.line1,_this.line2,_this.landmark,_this.pincode,_this.lat,_this.lng,_this.isDefault,_this.status,_this.serviceable,_this.zone,_this.message);
}

@override
String toString() {
  final _this = this as AddressDto;
  return 'AddressDto(id: ${_this.id}, label: ${_this.label}, line1: ${_this.line1}, line2: ${_this.line2}, landmark: ${_this.landmark}, pincode: ${_this.pincode}, lat: ${_this.lat}, lng: ${_this.lng}, isDefault: ${_this.isDefault}, status: ${_this.status}, serviceable: ${_this.serviceable}, zone: ${_this.zone}, message: ${_this.message})';
}


}

/// @nodoc
abstract mixin class $AddressDtoCopyWith<$Res>  {
  factory $AddressDtoCopyWith(AddressDto value, $Res Function(AddressDto) _then) = _$AddressDtoCopyWithImpl;
@useResult
$Res call({
 String id, String label, String line1, String? line2, String? landmark, String pincode, double? lat, double? lng, bool isDefault, String status, bool serviceable, ZoneDto? zone, String? message
});


$ZoneDtoCopyWith<$Res>? get zone;

}
/// @nodoc
class _$AddressDtoCopyWithImpl<$Res>
    implements $AddressDtoCopyWith<$Res> {
  _$AddressDtoCopyWithImpl(this._self, this._then);

  final AddressDto _self;
  final $Res Function(AddressDto) _then;

/// Create a copy of AddressDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? label = null,Object? line1 = null,Object? line2 = freezed,Object? landmark = freezed,Object? pincode = null,Object? lat = freezed,Object? lng = freezed,Object? isDefault = null,Object? status = null,Object? serviceable = null,Object? zone = freezed,Object? message = freezed,}) {
  return _then(AddressDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,line1: null == line1 ? _self.line1 : line1 // ignore: cast_nullable_to_non_nullable
as String,line2: freezed == line2 ? _self.line2 : line2 // ignore: cast_nullable_to_non_nullable
as String?,landmark: freezed == landmark ? _self.landmark : landmark // ignore: cast_nullable_to_non_nullable
as String?,pincode: null == pincode ? _self.pincode : pincode // ignore: cast_nullable_to_non_nullable
as String,lat: freezed == lat ? _self.lat : lat // ignore: cast_nullable_to_non_nullable
as double?,lng: freezed == lng ? _self.lng : lng // ignore: cast_nullable_to_non_nullable
as double?,isDefault: null == isDefault ? _self.isDefault : isDefault // ignore: cast_nullable_to_non_nullable
as bool,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,serviceable: null == serviceable ? _self.serviceable : serviceable // ignore: cast_nullable_to_non_nullable
as bool,zone: freezed == zone ? _self.zone : zone // ignore: cast_nullable_to_non_nullable
as ZoneDto?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of AddressDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ZoneDtoCopyWith<$Res>? get zone {
    if (_self.zone == null) {
    return null;
  }

  return $ZoneDtoCopyWith<$Res>(_self.zone!, (value) {
    return _then(_self.copyWith(zone: value));
  });
}
}


/// Adds pattern-matching-related methods to [AddressDto].
extension AddressDtoPatterns on AddressDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AddressDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AddressDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AddressDto value)  $default,){
final _that = this;
switch (_that) {
case _AddressDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AddressDto value)?  $default,){
final _that = this;
switch (_that) {
case _AddressDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String label,  String line1,  String? line2,  String? landmark,  String pincode,  double? lat,  double? lng,  bool isDefault,  String status,  bool serviceable,  ZoneDto? zone,  String? message)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AddressDto() when $default != null:
return $default(_that.id,_that.label,_that.line1,_that.line2,_that.landmark,_that.pincode,_that.lat,_that.lng,_that.isDefault,_that.status,_that.serviceable,_that.zone,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String label,  String line1,  String? line2,  String? landmark,  String pincode,  double? lat,  double? lng,  bool isDefault,  String status,  bool serviceable,  ZoneDto? zone,  String? message)  $default,) {final _that = this;
switch (_that) {
case _AddressDto():
return $default(_that.id,_that.label,_that.line1,_that.line2,_that.landmark,_that.pincode,_that.lat,_that.lng,_that.isDefault,_that.status,_that.serviceable,_that.zone,_that.message);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String label,  String line1,  String? line2,  String? landmark,  String pincode,  double? lat,  double? lng,  bool isDefault,  String status,  bool serviceable,  ZoneDto? zone,  String? message)?  $default,) {final _that = this;
switch (_that) {
case _AddressDto() when $default != null:
return $default(_that.id,_that.label,_that.line1,_that.line2,_that.landmark,_that.pincode,_that.lat,_that.lng,_that.isDefault,_that.status,_that.serviceable,_that.zone,_that.message);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AddressDto implements AddressDto {
  const _AddressDto({required this.id, required this.label, required this.line1, this.line2, this.landmark, required this.pincode, this.lat, this.lng, required this.isDefault, required this.status, required this.serviceable, this.zone, this.message});
  factory _AddressDto.fromJson(Map<String, dynamic> json) => _$AddressDtoFromJson(json);

@override final  String id;
@override final  String label;
@override final  String line1;
@override final  String? line2;
@override final  String? landmark;
@override final  String pincode;
@override final  double? lat;
@override final  double? lng;
@override final  bool isDefault;
@override final  String status;
@override final  bool serviceable;
@override final  ZoneDto? zone;
@override final  String? message;

/// Create a copy of AddressDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AddressDtoCopyWith<_AddressDto> get copyWith => __$AddressDtoCopyWithImpl<_AddressDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AddressDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AddressDto&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label)&&(identical(other.line1, line1) || other.line1 == line1)&&(identical(other.line2, line2) || other.line2 == line2)&&(identical(other.landmark, landmark) || other.landmark == landmark)&&(identical(other.pincode, pincode) || other.pincode == pincode)&&(identical(other.lat, lat) || other.lat == lat)&&(identical(other.lng, lng) || other.lng == lng)&&(identical(other.isDefault, isDefault) || other.isDefault == isDefault)&&(identical(other.status, status) || other.status == status)&&(identical(other.serviceable, serviceable) || other.serviceable == serviceable)&&(identical(other.zone, zone) || other.zone == zone)&&(identical(other.message, message) || other.message == message));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,label,line1,line2,landmark,pincode,lat,lng,isDefault,status,serviceable,zone,message);
}

@override
String toString() {
    return 'AddressDto(id: $id, label: $label, line1: $line1, line2: $line2, landmark: $landmark, pincode: $pincode, lat: $lat, lng: $lng, isDefault: $isDefault, status: $status, serviceable: $serviceable, zone: $zone, message: $message)';
}


}

/// @nodoc
abstract mixin class _$AddressDtoCopyWith<$Res> implements $AddressDtoCopyWith<$Res> {
  factory _$AddressDtoCopyWith(_AddressDto value, $Res Function(_AddressDto) _then) = __$AddressDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String label, String line1, String? line2, String? landmark, String pincode, double? lat, double? lng, bool isDefault, String status, bool serviceable, ZoneDto? zone, String? message
});


@override $ZoneDtoCopyWith<$Res>? get zone;

}
/// @nodoc
class __$AddressDtoCopyWithImpl<$Res>
    implements _$AddressDtoCopyWith<$Res> {
  __$AddressDtoCopyWithImpl(this._self, this._then);

  final _AddressDto _self;
  final $Res Function(_AddressDto) _then;

/// Create a copy of AddressDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? label = null,Object? line1 = null,Object? line2 = freezed,Object? landmark = freezed,Object? pincode = null,Object? lat = freezed,Object? lng = freezed,Object? isDefault = null,Object? status = null,Object? serviceable = null,Object? zone = freezed,Object? message = freezed,}) {
  return _then(_AddressDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,line1: null == line1 ? _self.line1 : line1 // ignore: cast_nullable_to_non_nullable
as String,line2: freezed == line2 ? _self.line2 : line2 // ignore: cast_nullable_to_non_nullable
as String?,landmark: freezed == landmark ? _self.landmark : landmark // ignore: cast_nullable_to_non_nullable
as String?,pincode: null == pincode ? _self.pincode : pincode // ignore: cast_nullable_to_non_nullable
as String,lat: freezed == lat ? _self.lat : lat // ignore: cast_nullable_to_non_nullable
as double?,lng: freezed == lng ? _self.lng : lng // ignore: cast_nullable_to_non_nullable
as double?,isDefault: null == isDefault ? _self.isDefault : isDefault // ignore: cast_nullable_to_non_nullable
as bool,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,serviceable: null == serviceable ? _self.serviceable : serviceable // ignore: cast_nullable_to_non_nullable
as bool,zone: freezed == zone ? _self.zone : zone // ignore: cast_nullable_to_non_nullable
as ZoneDto?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of AddressDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ZoneDtoCopyWith<$Res>? get zone {
    if (_self.zone == null) {
    return null;
  }

  return $ZoneDtoCopyWith<$Res>(_self.zone!, (value) {
    return _then(_self.copyWith(zone: value));
  });
}
}


/// @nodoc
mixin _$ServiceabilityDto {

 bool get serviceable; ZoneDto? get zone; String? get message;
/// Create a copy of ServiceabilityDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ServiceabilityDtoCopyWith<ServiceabilityDto> get copyWith => _$ServiceabilityDtoCopyWithImpl<ServiceabilityDto>(this as ServiceabilityDto, _$identity);

  /// Serializes this ServiceabilityDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ServiceabilityDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ServiceabilityDto&&(identical(other.serviceable, _this.serviceable) || other.serviceable == _this.serviceable)&&(identical(other.zone, _this.zone) || other.zone == _this.zone)&&(identical(other.message, _this.message) || other.message == _this.message));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ServiceabilityDto;
  return Object.hash(runtimeType,_this.serviceable,_this.zone,_this.message);
}

@override
String toString() {
  final _this = this as ServiceabilityDto;
  return 'ServiceabilityDto(serviceable: ${_this.serviceable}, zone: ${_this.zone}, message: ${_this.message})';
}


}

/// @nodoc
abstract mixin class $ServiceabilityDtoCopyWith<$Res>  {
  factory $ServiceabilityDtoCopyWith(ServiceabilityDto value, $Res Function(ServiceabilityDto) _then) = _$ServiceabilityDtoCopyWithImpl;
@useResult
$Res call({
 bool serviceable, ZoneDto? zone, String? message
});


$ZoneDtoCopyWith<$Res>? get zone;

}
/// @nodoc
class _$ServiceabilityDtoCopyWithImpl<$Res>
    implements $ServiceabilityDtoCopyWith<$Res> {
  _$ServiceabilityDtoCopyWithImpl(this._self, this._then);

  final ServiceabilityDto _self;
  final $Res Function(ServiceabilityDto) _then;

/// Create a copy of ServiceabilityDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? serviceable = null,Object? zone = freezed,Object? message = freezed,}) {
  return _then(ServiceabilityDto(
serviceable: null == serviceable ? _self.serviceable : serviceable // ignore: cast_nullable_to_non_nullable
as bool,zone: freezed == zone ? _self.zone : zone // ignore: cast_nullable_to_non_nullable
as ZoneDto?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of ServiceabilityDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ZoneDtoCopyWith<$Res>? get zone {
    if (_self.zone == null) {
    return null;
  }

  return $ZoneDtoCopyWith<$Res>(_self.zone!, (value) {
    return _then(_self.copyWith(zone: value));
  });
}
}


/// Adds pattern-matching-related methods to [ServiceabilityDto].
extension ServiceabilityDtoPatterns on ServiceabilityDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ServiceabilityDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ServiceabilityDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ServiceabilityDto value)  $default,){
final _that = this;
switch (_that) {
case _ServiceabilityDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ServiceabilityDto value)?  $default,){
final _that = this;
switch (_that) {
case _ServiceabilityDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool serviceable,  ZoneDto? zone,  String? message)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ServiceabilityDto() when $default != null:
return $default(_that.serviceable,_that.zone,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool serviceable,  ZoneDto? zone,  String? message)  $default,) {final _that = this;
switch (_that) {
case _ServiceabilityDto():
return $default(_that.serviceable,_that.zone,_that.message);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool serviceable,  ZoneDto? zone,  String? message)?  $default,) {final _that = this;
switch (_that) {
case _ServiceabilityDto() when $default != null:
return $default(_that.serviceable,_that.zone,_that.message);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ServiceabilityDto implements ServiceabilityDto {
  const _ServiceabilityDto({required this.serviceable, this.zone, this.message});
  factory _ServiceabilityDto.fromJson(Map<String, dynamic> json) => _$ServiceabilityDtoFromJson(json);

@override final  bool serviceable;
@override final  ZoneDto? zone;
@override final  String? message;

/// Create a copy of ServiceabilityDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ServiceabilityDtoCopyWith<_ServiceabilityDto> get copyWith => __$ServiceabilityDtoCopyWithImpl<_ServiceabilityDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ServiceabilityDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ServiceabilityDto&&(identical(other.serviceable, serviceable) || other.serviceable == serviceable)&&(identical(other.zone, zone) || other.zone == zone)&&(identical(other.message, message) || other.message == message));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,serviceable,zone,message);
}

@override
String toString() {
    return 'ServiceabilityDto(serviceable: $serviceable, zone: $zone, message: $message)';
}


}

/// @nodoc
abstract mixin class _$ServiceabilityDtoCopyWith<$Res> implements $ServiceabilityDtoCopyWith<$Res> {
  factory _$ServiceabilityDtoCopyWith(_ServiceabilityDto value, $Res Function(_ServiceabilityDto) _then) = __$ServiceabilityDtoCopyWithImpl;
@override @useResult
$Res call({
 bool serviceable, ZoneDto? zone, String? message
});


@override $ZoneDtoCopyWith<$Res>? get zone;

}
/// @nodoc
class __$ServiceabilityDtoCopyWithImpl<$Res>
    implements _$ServiceabilityDtoCopyWith<$Res> {
  __$ServiceabilityDtoCopyWithImpl(this._self, this._then);

  final _ServiceabilityDto _self;
  final $Res Function(_ServiceabilityDto) _then;

/// Create a copy of ServiceabilityDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? serviceable = null,Object? zone = freezed,Object? message = freezed,}) {
  return _then(_ServiceabilityDto(
serviceable: null == serviceable ? _self.serviceable : serviceable // ignore: cast_nullable_to_non_nullable
as bool,zone: freezed == zone ? _self.zone : zone // ignore: cast_nullable_to_non_nullable
as ZoneDto?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of ServiceabilityDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ZoneDtoCopyWith<$Res>? get zone {
    if (_self.zone == null) {
    return null;
  }

  return $ZoneDtoCopyWith<$Res>(_self.zone!, (value) {
    return _then(_self.copyWith(zone: value));
  });
}
}

// dart format on
