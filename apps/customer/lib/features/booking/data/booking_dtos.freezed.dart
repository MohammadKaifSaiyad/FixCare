// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'booking_dtos.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$BookingServiceDto {

 String get id; String get name;
/// Create a copy of BookingServiceDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BookingServiceDtoCopyWith<BookingServiceDto> get copyWith => _$BookingServiceDtoCopyWithImpl<BookingServiceDto>(this as BookingServiceDto, _$identity);

  /// Serializes this BookingServiceDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as BookingServiceDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BookingServiceDto&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as BookingServiceDto;
  return Object.hash(runtimeType,_this.id,_this.name);
}

@override
String toString() {
  final _this = this as BookingServiceDto;
  return 'BookingServiceDto(id: ${_this.id}, name: ${_this.name})';
}


}

/// @nodoc
abstract mixin class $BookingServiceDtoCopyWith<$Res>  {
  factory $BookingServiceDtoCopyWith(BookingServiceDto value, $Res Function(BookingServiceDto) _then) = _$BookingServiceDtoCopyWithImpl;
@useResult
$Res call({
 String id, String name
});




}
/// @nodoc
class _$BookingServiceDtoCopyWithImpl<$Res>
    implements $BookingServiceDtoCopyWith<$Res> {
  _$BookingServiceDtoCopyWithImpl(this._self, this._then);

  final BookingServiceDto _self;
  final $Res Function(BookingServiceDto) _then;

/// Create a copy of BookingServiceDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,}) {
  return _then(BookingServiceDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BookingServiceDto].
extension BookingServiceDtoPatterns on BookingServiceDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BookingServiceDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BookingServiceDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BookingServiceDto value)  $default,){
final _that = this;
switch (_that) {
case _BookingServiceDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BookingServiceDto value)?  $default,){
final _that = this;
switch (_that) {
case _BookingServiceDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BookingServiceDto() when $default != null:
return $default(_that.id,_that.name);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name)  $default,) {final _that = this;
switch (_that) {
case _BookingServiceDto():
return $default(_that.id,_that.name);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name)?  $default,) {final _that = this;
switch (_that) {
case _BookingServiceDto() when $default != null:
return $default(_that.id,_that.name);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BookingServiceDto implements BookingServiceDto {
  const _BookingServiceDto({required this.id, required this.name});
  factory _BookingServiceDto.fromJson(Map<String, dynamic> json) => _$BookingServiceDtoFromJson(json);

@override final  String id;
@override final  String name;

/// Create a copy of BookingServiceDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BookingServiceDtoCopyWith<_BookingServiceDto> get copyWith => __$BookingServiceDtoCopyWithImpl<_BookingServiceDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BookingServiceDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BookingServiceDto&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,name);
}

@override
String toString() {
    return 'BookingServiceDto(id: $id, name: $name)';
}


}

/// @nodoc
abstract mixin class _$BookingServiceDtoCopyWith<$Res> implements $BookingServiceDtoCopyWith<$Res> {
  factory _$BookingServiceDtoCopyWith(_BookingServiceDto value, $Res Function(_BookingServiceDto) _then) = __$BookingServiceDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String name
});




}
/// @nodoc
class __$BookingServiceDtoCopyWithImpl<$Res>
    implements _$BookingServiceDtoCopyWith<$Res> {
  __$BookingServiceDtoCopyWithImpl(this._self, this._then);

  final _BookingServiceDto _self;
  final $Res Function(_BookingServiceDto) _then;

/// Create a copy of BookingServiceDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,}) {
  return _then(_BookingServiceDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$BookingZoneDto {

 String get id; String get name;
/// Create a copy of BookingZoneDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BookingZoneDtoCopyWith<BookingZoneDto> get copyWith => _$BookingZoneDtoCopyWithImpl<BookingZoneDto>(this as BookingZoneDto, _$identity);

  /// Serializes this BookingZoneDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as BookingZoneDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BookingZoneDto&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as BookingZoneDto;
  return Object.hash(runtimeType,_this.id,_this.name);
}

@override
String toString() {
  final _this = this as BookingZoneDto;
  return 'BookingZoneDto(id: ${_this.id}, name: ${_this.name})';
}


}

/// @nodoc
abstract mixin class $BookingZoneDtoCopyWith<$Res>  {
  factory $BookingZoneDtoCopyWith(BookingZoneDto value, $Res Function(BookingZoneDto) _then) = _$BookingZoneDtoCopyWithImpl;
@useResult
$Res call({
 String id, String name
});




}
/// @nodoc
class _$BookingZoneDtoCopyWithImpl<$Res>
    implements $BookingZoneDtoCopyWith<$Res> {
  _$BookingZoneDtoCopyWithImpl(this._self, this._then);

  final BookingZoneDto _self;
  final $Res Function(BookingZoneDto) _then;

/// Create a copy of BookingZoneDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,}) {
  return _then(BookingZoneDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BookingZoneDto].
extension BookingZoneDtoPatterns on BookingZoneDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BookingZoneDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BookingZoneDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BookingZoneDto value)  $default,){
final _that = this;
switch (_that) {
case _BookingZoneDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BookingZoneDto value)?  $default,){
final _that = this;
switch (_that) {
case _BookingZoneDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BookingZoneDto() when $default != null:
return $default(_that.id,_that.name);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name)  $default,) {final _that = this;
switch (_that) {
case _BookingZoneDto():
return $default(_that.id,_that.name);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name)?  $default,) {final _that = this;
switch (_that) {
case _BookingZoneDto() when $default != null:
return $default(_that.id,_that.name);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BookingZoneDto implements BookingZoneDto {
  const _BookingZoneDto({required this.id, required this.name});
  factory _BookingZoneDto.fromJson(Map<String, dynamic> json) => _$BookingZoneDtoFromJson(json);

@override final  String id;
@override final  String name;

/// Create a copy of BookingZoneDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BookingZoneDtoCopyWith<_BookingZoneDto> get copyWith => __$BookingZoneDtoCopyWithImpl<_BookingZoneDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BookingZoneDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BookingZoneDto&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,name);
}

@override
String toString() {
    return 'BookingZoneDto(id: $id, name: $name)';
}


}

/// @nodoc
abstract mixin class _$BookingZoneDtoCopyWith<$Res> implements $BookingZoneDtoCopyWith<$Res> {
  factory _$BookingZoneDtoCopyWith(_BookingZoneDto value, $Res Function(_BookingZoneDto) _then) = __$BookingZoneDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String name
});




}
/// @nodoc
class __$BookingZoneDtoCopyWithImpl<$Res>
    implements _$BookingZoneDtoCopyWith<$Res> {
  __$BookingZoneDtoCopyWithImpl(this._self, this._then);

  final _BookingZoneDto _self;
  final $Res Function(_BookingZoneDto) _then;

/// Create a copy of BookingZoneDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,}) {
  return _then(_BookingZoneDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$BookingAddressRefDto {

 String get id;
/// Create a copy of BookingAddressRefDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BookingAddressRefDtoCopyWith<BookingAddressRefDto> get copyWith => _$BookingAddressRefDtoCopyWithImpl<BookingAddressRefDto>(this as BookingAddressRefDto, _$identity);

  /// Serializes this BookingAddressRefDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as BookingAddressRefDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BookingAddressRefDto&&(identical(other.id, _this.id) || other.id == _this.id));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as BookingAddressRefDto;
  return Object.hash(runtimeType,_this.id);
}

@override
String toString() {
  final _this = this as BookingAddressRefDto;
  return 'BookingAddressRefDto(id: ${_this.id})';
}


}

/// @nodoc
abstract mixin class $BookingAddressRefDtoCopyWith<$Res>  {
  factory $BookingAddressRefDtoCopyWith(BookingAddressRefDto value, $Res Function(BookingAddressRefDto) _then) = _$BookingAddressRefDtoCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$BookingAddressRefDtoCopyWithImpl<$Res>
    implements $BookingAddressRefDtoCopyWith<$Res> {
  _$BookingAddressRefDtoCopyWithImpl(this._self, this._then);

  final BookingAddressRefDto _self;
  final $Res Function(BookingAddressRefDto) _then;

/// Create a copy of BookingAddressRefDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,}) {
  return _then(BookingAddressRefDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BookingAddressRefDto].
extension BookingAddressRefDtoPatterns on BookingAddressRefDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BookingAddressRefDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BookingAddressRefDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BookingAddressRefDto value)  $default,){
final _that = this;
switch (_that) {
case _BookingAddressRefDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BookingAddressRefDto value)?  $default,){
final _that = this;
switch (_that) {
case _BookingAddressRefDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BookingAddressRefDto() when $default != null:
return $default(_that.id);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id)  $default,) {final _that = this;
switch (_that) {
case _BookingAddressRefDto():
return $default(_that.id);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id)?  $default,) {final _that = this;
switch (_that) {
case _BookingAddressRefDto() when $default != null:
return $default(_that.id);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BookingAddressRefDto implements BookingAddressRefDto {
  const _BookingAddressRefDto({required this.id});
  factory _BookingAddressRefDto.fromJson(Map<String, dynamic> json) => _$BookingAddressRefDtoFromJson(json);

@override final  String id;

/// Create a copy of BookingAddressRefDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BookingAddressRefDtoCopyWith<_BookingAddressRefDto> get copyWith => __$BookingAddressRefDtoCopyWithImpl<_BookingAddressRefDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BookingAddressRefDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BookingAddressRefDto&&(identical(other.id, id) || other.id == id));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id);
}

@override
String toString() {
    return 'BookingAddressRefDto(id: $id)';
}


}

/// @nodoc
abstract mixin class _$BookingAddressRefDtoCopyWith<$Res> implements $BookingAddressRefDtoCopyWith<$Res> {
  factory _$BookingAddressRefDtoCopyWith(_BookingAddressRefDto value, $Res Function(_BookingAddressRefDto) _then) = __$BookingAddressRefDtoCopyWithImpl;
@override @useResult
$Res call({
 String id
});




}
/// @nodoc
class __$BookingAddressRefDtoCopyWithImpl<$Res>
    implements _$BookingAddressRefDtoCopyWith<$Res> {
  __$BookingAddressRefDtoCopyWithImpl(this._self, this._then);

  final _BookingAddressRefDto _self;
  final $Res Function(_BookingAddressRefDto) _then;

/// Create a copy of BookingAddressRefDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(_BookingAddressRefDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$TechnicianRefDto {

 String get name; String get maskedPhone;
/// Create a copy of TechnicianRefDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TechnicianRefDtoCopyWith<TechnicianRefDto> get copyWith => _$TechnicianRefDtoCopyWithImpl<TechnicianRefDto>(this as TechnicianRefDto, _$identity);

  /// Serializes this TechnicianRefDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as TechnicianRefDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TechnicianRefDto&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.maskedPhone, _this.maskedPhone) || other.maskedPhone == _this.maskedPhone));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as TechnicianRefDto;
  return Object.hash(runtimeType,_this.name,_this.maskedPhone);
}

@override
String toString() {
  final _this = this as TechnicianRefDto;
  return 'TechnicianRefDto(name: ${_this.name}, maskedPhone: ${_this.maskedPhone})';
}


}

/// @nodoc
abstract mixin class $TechnicianRefDtoCopyWith<$Res>  {
  factory $TechnicianRefDtoCopyWith(TechnicianRefDto value, $Res Function(TechnicianRefDto) _then) = _$TechnicianRefDtoCopyWithImpl;
@useResult
$Res call({
 String name, String maskedPhone
});




}
/// @nodoc
class _$TechnicianRefDtoCopyWithImpl<$Res>
    implements $TechnicianRefDtoCopyWith<$Res> {
  _$TechnicianRefDtoCopyWithImpl(this._self, this._then);

  final TechnicianRefDto _self;
  final $Res Function(TechnicianRefDto) _then;

/// Create a copy of TechnicianRefDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? maskedPhone = null,}) {
  return _then(TechnicianRefDto(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,maskedPhone: null == maskedPhone ? _self.maskedPhone : maskedPhone // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [TechnicianRefDto].
extension TechnicianRefDtoPatterns on TechnicianRefDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TechnicianRefDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TechnicianRefDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TechnicianRefDto value)  $default,){
final _that = this;
switch (_that) {
case _TechnicianRefDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TechnicianRefDto value)?  $default,){
final _that = this;
switch (_that) {
case _TechnicianRefDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String maskedPhone)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TechnicianRefDto() when $default != null:
return $default(_that.name,_that.maskedPhone);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String maskedPhone)  $default,) {final _that = this;
switch (_that) {
case _TechnicianRefDto():
return $default(_that.name,_that.maskedPhone);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String maskedPhone)?  $default,) {final _that = this;
switch (_that) {
case _TechnicianRefDto() when $default != null:
return $default(_that.name,_that.maskedPhone);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TechnicianRefDto implements TechnicianRefDto {
  const _TechnicianRefDto({required this.name, required this.maskedPhone});
  factory _TechnicianRefDto.fromJson(Map<String, dynamic> json) => _$TechnicianRefDtoFromJson(json);

@override final  String name;
@override final  String maskedPhone;

/// Create a copy of TechnicianRefDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TechnicianRefDtoCopyWith<_TechnicianRefDto> get copyWith => __$TechnicianRefDtoCopyWithImpl<_TechnicianRefDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TechnicianRefDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TechnicianRefDto&&(identical(other.name, name) || other.name == name)&&(identical(other.maskedPhone, maskedPhone) || other.maskedPhone == maskedPhone));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,name,maskedPhone);
}

@override
String toString() {
    return 'TechnicianRefDto(name: $name, maskedPhone: $maskedPhone)';
}


}

/// @nodoc
abstract mixin class _$TechnicianRefDtoCopyWith<$Res> implements $TechnicianRefDtoCopyWith<$Res> {
  factory _$TechnicianRefDtoCopyWith(_TechnicianRefDto value, $Res Function(_TechnicianRefDto) _then) = __$TechnicianRefDtoCopyWithImpl;
@override @useResult
$Res call({
 String name, String maskedPhone
});




}
/// @nodoc
class __$TechnicianRefDtoCopyWithImpl<$Res>
    implements _$TechnicianRefDtoCopyWith<$Res> {
  __$TechnicianRefDtoCopyWithImpl(this._self, this._then);

  final _TechnicianRefDto _self;
  final $Res Function(_TechnicianRefDto) _then;

/// Create a copy of TechnicianRefDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? maskedPhone = null,}) {
  return _then(_TechnicianRefDto(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,maskedPhone: null == maskedPhone ? _self.maskedPhone : maskedPhone // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$DiagnosisDto {

 String get issueName;
/// Create a copy of DiagnosisDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiagnosisDtoCopyWith<DiagnosisDto> get copyWith => _$DiagnosisDtoCopyWithImpl<DiagnosisDto>(this as DiagnosisDto, _$identity);

  /// Serializes this DiagnosisDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as DiagnosisDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiagnosisDto&&(identical(other.issueName, _this.issueName) || other.issueName == _this.issueName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as DiagnosisDto;
  return Object.hash(runtimeType,_this.issueName);
}

@override
String toString() {
  final _this = this as DiagnosisDto;
  return 'DiagnosisDto(issueName: ${_this.issueName})';
}


}

/// @nodoc
abstract mixin class $DiagnosisDtoCopyWith<$Res>  {
  factory $DiagnosisDtoCopyWith(DiagnosisDto value, $Res Function(DiagnosisDto) _then) = _$DiagnosisDtoCopyWithImpl;
@useResult
$Res call({
 String issueName
});




}
/// @nodoc
class _$DiagnosisDtoCopyWithImpl<$Res>
    implements $DiagnosisDtoCopyWith<$Res> {
  _$DiagnosisDtoCopyWithImpl(this._self, this._then);

  final DiagnosisDto _self;
  final $Res Function(DiagnosisDto) _then;

/// Create a copy of DiagnosisDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? issueName = null,}) {
  return _then(DiagnosisDto(
issueName: null == issueName ? _self.issueName : issueName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [DiagnosisDto].
extension DiagnosisDtoPatterns on DiagnosisDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DiagnosisDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DiagnosisDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DiagnosisDto value)  $default,){
final _that = this;
switch (_that) {
case _DiagnosisDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DiagnosisDto value)?  $default,){
final _that = this;
switch (_that) {
case _DiagnosisDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String issueName)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DiagnosisDto() when $default != null:
return $default(_that.issueName);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String issueName)  $default,) {final _that = this;
switch (_that) {
case _DiagnosisDto():
return $default(_that.issueName);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String issueName)?  $default,) {final _that = this;
switch (_that) {
case _DiagnosisDto() when $default != null:
return $default(_that.issueName);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DiagnosisDto implements DiagnosisDto {
  const _DiagnosisDto({required this.issueName});
  factory _DiagnosisDto.fromJson(Map<String, dynamic> json) => _$DiagnosisDtoFromJson(json);

@override final  String issueName;

/// Create a copy of DiagnosisDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DiagnosisDtoCopyWith<_DiagnosisDto> get copyWith => __$DiagnosisDtoCopyWithImpl<_DiagnosisDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DiagnosisDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DiagnosisDto&&(identical(other.issueName, issueName) || other.issueName == issueName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,issueName);
}

@override
String toString() {
    return 'DiagnosisDto(issueName: $issueName)';
}


}

/// @nodoc
abstract mixin class _$DiagnosisDtoCopyWith<$Res> implements $DiagnosisDtoCopyWith<$Res> {
  factory _$DiagnosisDtoCopyWith(_DiagnosisDto value, $Res Function(_DiagnosisDto) _then) = __$DiagnosisDtoCopyWithImpl;
@override @useResult
$Res call({
 String issueName
});




}
/// @nodoc
class __$DiagnosisDtoCopyWithImpl<$Res>
    implements _$DiagnosisDtoCopyWith<$Res> {
  __$DiagnosisDtoCopyWithImpl(this._self, this._then);

  final _DiagnosisDto _self;
  final $Res Function(_DiagnosisDto) _then;

/// Create a copy of DiagnosisDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? issueName = null,}) {
  return _then(_DiagnosisDto(
issueName: null == issueName ? _self.issueName : issueName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$PartDto {

 String get id; String get sku; String get name; int get ceilingPricePaise; int get qty;
/// Create a copy of PartDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PartDtoCopyWith<PartDto> get copyWith => _$PartDtoCopyWithImpl<PartDto>(this as PartDto, _$identity);

  /// Serializes this PartDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PartDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PartDto&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.sku, _this.sku) || other.sku == _this.sku)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.ceilingPricePaise, _this.ceilingPricePaise) || other.ceilingPricePaise == _this.ceilingPricePaise)&&(identical(other.qty, _this.qty) || other.qty == _this.qty));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PartDto;
  return Object.hash(runtimeType,_this.id,_this.sku,_this.name,_this.ceilingPricePaise,_this.qty);
}

@override
String toString() {
  final _this = this as PartDto;
  return 'PartDto(id: ${_this.id}, sku: ${_this.sku}, name: ${_this.name}, ceilingPricePaise: ${_this.ceilingPricePaise}, qty: ${_this.qty})';
}


}

/// @nodoc
abstract mixin class $PartDtoCopyWith<$Res>  {
  factory $PartDtoCopyWith(PartDto value, $Res Function(PartDto) _then) = _$PartDtoCopyWithImpl;
@useResult
$Res call({
 String id, String sku, String name, int ceilingPricePaise, int qty
});




}
/// @nodoc
class _$PartDtoCopyWithImpl<$Res>
    implements $PartDtoCopyWith<$Res> {
  _$PartDtoCopyWithImpl(this._self, this._then);

  final PartDto _self;
  final $Res Function(PartDto) _then;

/// Create a copy of PartDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? sku = null,Object? name = null,Object? ceilingPricePaise = null,Object? qty = null,}) {
  return _then(PartDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sku: null == sku ? _self.sku : sku // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,ceilingPricePaise: null == ceilingPricePaise ? _self.ceilingPricePaise : ceilingPricePaise // ignore: cast_nullable_to_non_nullable
as int,qty: null == qty ? _self.qty : qty // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PartDto].
extension PartDtoPatterns on PartDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PartDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PartDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PartDto value)  $default,){
final _that = this;
switch (_that) {
case _PartDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PartDto value)?  $default,){
final _that = this;
switch (_that) {
case _PartDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String sku,  String name,  int ceilingPricePaise,  int qty)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PartDto() when $default != null:
return $default(_that.id,_that.sku,_that.name,_that.ceilingPricePaise,_that.qty);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String sku,  String name,  int ceilingPricePaise,  int qty)  $default,) {final _that = this;
switch (_that) {
case _PartDto():
return $default(_that.id,_that.sku,_that.name,_that.ceilingPricePaise,_that.qty);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String sku,  String name,  int ceilingPricePaise,  int qty)?  $default,) {final _that = this;
switch (_that) {
case _PartDto() when $default != null:
return $default(_that.id,_that.sku,_that.name,_that.ceilingPricePaise,_that.qty);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PartDto implements PartDto {
  const _PartDto({required this.id, required this.sku, required this.name, required this.ceilingPricePaise, required this.qty});
  factory _PartDto.fromJson(Map<String, dynamic> json) => _$PartDtoFromJson(json);

@override final  String id;
@override final  String sku;
@override final  String name;
@override final  int ceilingPricePaise;
@override final  int qty;

/// Create a copy of PartDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PartDtoCopyWith<_PartDto> get copyWith => __$PartDtoCopyWithImpl<_PartDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PartDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PartDto&&(identical(other.id, id) || other.id == id)&&(identical(other.sku, sku) || other.sku == sku)&&(identical(other.name, name) || other.name == name)&&(identical(other.ceilingPricePaise, ceilingPricePaise) || other.ceilingPricePaise == ceilingPricePaise)&&(identical(other.qty, qty) || other.qty == qty));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,sku,name,ceilingPricePaise,qty);
}

@override
String toString() {
    return 'PartDto(id: $id, sku: $sku, name: $name, ceilingPricePaise: $ceilingPricePaise, qty: $qty)';
}


}

/// @nodoc
abstract mixin class _$PartDtoCopyWith<$Res> implements $PartDtoCopyWith<$Res> {
  factory _$PartDtoCopyWith(_PartDto value, $Res Function(_PartDto) _then) = __$PartDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String sku, String name, int ceilingPricePaise, int qty
});




}
/// @nodoc
class __$PartDtoCopyWithImpl<$Res>
    implements _$PartDtoCopyWith<$Res> {
  __$PartDtoCopyWithImpl(this._self, this._then);

  final _PartDto _self;
  final $Res Function(_PartDto) _then;

/// Create a copy of PartDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? sku = null,Object? name = null,Object? ceilingPricePaise = null,Object? qty = null,}) {
  return _then(_PartDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sku: null == sku ? _self.sku : sku // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,ceilingPricePaise: null == ceilingPricePaise ? _self.ceilingPricePaise : ceilingPricePaise // ignore: cast_nullable_to_non_nullable
as int,qty: null == qty ? _self.qty : qty // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$EstimateDto {

 int get laborPaise; int get partsPaise; int get visitFeeCreditPaise; int get totalPayablePaise;
/// Create a copy of EstimateDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EstimateDtoCopyWith<EstimateDto> get copyWith => _$EstimateDtoCopyWithImpl<EstimateDto>(this as EstimateDto, _$identity);

  /// Serializes this EstimateDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as EstimateDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EstimateDto&&(identical(other.laborPaise, _this.laborPaise) || other.laborPaise == _this.laborPaise)&&(identical(other.partsPaise, _this.partsPaise) || other.partsPaise == _this.partsPaise)&&(identical(other.visitFeeCreditPaise, _this.visitFeeCreditPaise) || other.visitFeeCreditPaise == _this.visitFeeCreditPaise)&&(identical(other.totalPayablePaise, _this.totalPayablePaise) || other.totalPayablePaise == _this.totalPayablePaise));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as EstimateDto;
  return Object.hash(runtimeType,_this.laborPaise,_this.partsPaise,_this.visitFeeCreditPaise,_this.totalPayablePaise);
}

@override
String toString() {
  final _this = this as EstimateDto;
  return 'EstimateDto(laborPaise: ${_this.laborPaise}, partsPaise: ${_this.partsPaise}, visitFeeCreditPaise: ${_this.visitFeeCreditPaise}, totalPayablePaise: ${_this.totalPayablePaise})';
}


}

/// @nodoc
abstract mixin class $EstimateDtoCopyWith<$Res>  {
  factory $EstimateDtoCopyWith(EstimateDto value, $Res Function(EstimateDto) _then) = _$EstimateDtoCopyWithImpl;
@useResult
$Res call({
 int laborPaise, int partsPaise, int visitFeeCreditPaise, int totalPayablePaise
});




}
/// @nodoc
class _$EstimateDtoCopyWithImpl<$Res>
    implements $EstimateDtoCopyWith<$Res> {
  _$EstimateDtoCopyWithImpl(this._self, this._then);

  final EstimateDto _self;
  final $Res Function(EstimateDto) _then;

/// Create a copy of EstimateDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? laborPaise = null,Object? partsPaise = null,Object? visitFeeCreditPaise = null,Object? totalPayablePaise = null,}) {
  return _then(EstimateDto(
laborPaise: null == laborPaise ? _self.laborPaise : laborPaise // ignore: cast_nullable_to_non_nullable
as int,partsPaise: null == partsPaise ? _self.partsPaise : partsPaise // ignore: cast_nullable_to_non_nullable
as int,visitFeeCreditPaise: null == visitFeeCreditPaise ? _self.visitFeeCreditPaise : visitFeeCreditPaise // ignore: cast_nullable_to_non_nullable
as int,totalPayablePaise: null == totalPayablePaise ? _self.totalPayablePaise : totalPayablePaise // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [EstimateDto].
extension EstimateDtoPatterns on EstimateDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EstimateDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EstimateDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EstimateDto value)  $default,){
final _that = this;
switch (_that) {
case _EstimateDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EstimateDto value)?  $default,){
final _that = this;
switch (_that) {
case _EstimateDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int laborPaise,  int partsPaise,  int visitFeeCreditPaise,  int totalPayablePaise)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EstimateDto() when $default != null:
return $default(_that.laborPaise,_that.partsPaise,_that.visitFeeCreditPaise,_that.totalPayablePaise);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int laborPaise,  int partsPaise,  int visitFeeCreditPaise,  int totalPayablePaise)  $default,) {final _that = this;
switch (_that) {
case _EstimateDto():
return $default(_that.laborPaise,_that.partsPaise,_that.visitFeeCreditPaise,_that.totalPayablePaise);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int laborPaise,  int partsPaise,  int visitFeeCreditPaise,  int totalPayablePaise)?  $default,) {final _that = this;
switch (_that) {
case _EstimateDto() when $default != null:
return $default(_that.laborPaise,_that.partsPaise,_that.visitFeeCreditPaise,_that.totalPayablePaise);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _EstimateDto implements EstimateDto {
  const _EstimateDto({required this.laborPaise, required this.partsPaise, required this.visitFeeCreditPaise, required this.totalPayablePaise});
  factory _EstimateDto.fromJson(Map<String, dynamic> json) => _$EstimateDtoFromJson(json);

@override final  int laborPaise;
@override final  int partsPaise;
@override final  int visitFeeCreditPaise;
@override final  int totalPayablePaise;

/// Create a copy of EstimateDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EstimateDtoCopyWith<_EstimateDto> get copyWith => __$EstimateDtoCopyWithImpl<_EstimateDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$EstimateDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _EstimateDto&&(identical(other.laborPaise, laborPaise) || other.laborPaise == laborPaise)&&(identical(other.partsPaise, partsPaise) || other.partsPaise == partsPaise)&&(identical(other.visitFeeCreditPaise, visitFeeCreditPaise) || other.visitFeeCreditPaise == visitFeeCreditPaise)&&(identical(other.totalPayablePaise, totalPayablePaise) || other.totalPayablePaise == totalPayablePaise));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,laborPaise,partsPaise,visitFeeCreditPaise,totalPayablePaise);
}

@override
String toString() {
    return 'EstimateDto(laborPaise: $laborPaise, partsPaise: $partsPaise, visitFeeCreditPaise: $visitFeeCreditPaise, totalPayablePaise: $totalPayablePaise)';
}


}

/// @nodoc
abstract mixin class _$EstimateDtoCopyWith<$Res> implements $EstimateDtoCopyWith<$Res> {
  factory _$EstimateDtoCopyWith(_EstimateDto value, $Res Function(_EstimateDto) _then) = __$EstimateDtoCopyWithImpl;
@override @useResult
$Res call({
 int laborPaise, int partsPaise, int visitFeeCreditPaise, int totalPayablePaise
});




}
/// @nodoc
class __$EstimateDtoCopyWithImpl<$Res>
    implements _$EstimateDtoCopyWith<$Res> {
  __$EstimateDtoCopyWithImpl(this._self, this._then);

  final _EstimateDto _self;
  final $Res Function(_EstimateDto) _then;

/// Create a copy of EstimateDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? laborPaise = null,Object? partsPaise = null,Object? visitFeeCreditPaise = null,Object? totalPayablePaise = null,}) {
  return _then(_EstimateDto(
laborPaise: null == laborPaise ? _self.laborPaise : laborPaise // ignore: cast_nullable_to_non_nullable
as int,partsPaise: null == partsPaise ? _self.partsPaise : partsPaise // ignore: cast_nullable_to_non_nullable
as int,visitFeeCreditPaise: null == visitFeeCreditPaise ? _self.visitFeeCreditPaise : visitFeeCreditPaise // ignore: cast_nullable_to_non_nullable
as int,totalPayablePaise: null == totalPayablePaise ? _self.totalPayablePaise : totalPayablePaise // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$PhotoDto {

 String get kind; String get capturedAt; String get url;
/// Create a copy of PhotoDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PhotoDtoCopyWith<PhotoDto> get copyWith => _$PhotoDtoCopyWithImpl<PhotoDto>(this as PhotoDto, _$identity);

  /// Serializes this PhotoDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PhotoDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PhotoDto&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.capturedAt, _this.capturedAt) || other.capturedAt == _this.capturedAt)&&(identical(other.url, _this.url) || other.url == _this.url));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PhotoDto;
  return Object.hash(runtimeType,_this.kind,_this.capturedAt,_this.url);
}

@override
String toString() {
  final _this = this as PhotoDto;
  return 'PhotoDto(kind: ${_this.kind}, capturedAt: ${_this.capturedAt}, url: ${_this.url})';
}


}

/// @nodoc
abstract mixin class $PhotoDtoCopyWith<$Res>  {
  factory $PhotoDtoCopyWith(PhotoDto value, $Res Function(PhotoDto) _then) = _$PhotoDtoCopyWithImpl;
@useResult
$Res call({
 String kind, String capturedAt, String url
});




}
/// @nodoc
class _$PhotoDtoCopyWithImpl<$Res>
    implements $PhotoDtoCopyWith<$Res> {
  _$PhotoDtoCopyWithImpl(this._self, this._then);

  final PhotoDto _self;
  final $Res Function(PhotoDto) _then;

/// Create a copy of PhotoDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? capturedAt = null,Object? url = null,}) {
  return _then(PhotoDto(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,capturedAt: null == capturedAt ? _self.capturedAt : capturedAt // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [PhotoDto].
extension PhotoDtoPatterns on PhotoDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PhotoDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PhotoDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PhotoDto value)  $default,){
final _that = this;
switch (_that) {
case _PhotoDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PhotoDto value)?  $default,){
final _that = this;
switch (_that) {
case _PhotoDto() when $default != null:
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
case _PhotoDto() when $default != null:
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
case _PhotoDto():
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
case _PhotoDto() when $default != null:
return $default(_that.kind,_that.capturedAt,_that.url);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PhotoDto implements PhotoDto {
  const _PhotoDto({required this.kind, required this.capturedAt, required this.url});
  factory _PhotoDto.fromJson(Map<String, dynamic> json) => _$PhotoDtoFromJson(json);

@override final  String kind;
@override final  String capturedAt;
@override final  String url;

/// Create a copy of PhotoDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PhotoDtoCopyWith<_PhotoDto> get copyWith => __$PhotoDtoCopyWithImpl<_PhotoDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PhotoDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PhotoDto&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.capturedAt, capturedAt) || other.capturedAt == capturedAt)&&(identical(other.url, url) || other.url == url));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,kind,capturedAt,url);
}

@override
String toString() {
    return 'PhotoDto(kind: $kind, capturedAt: $capturedAt, url: $url)';
}


}

/// @nodoc
abstract mixin class _$PhotoDtoCopyWith<$Res> implements $PhotoDtoCopyWith<$Res> {
  factory _$PhotoDtoCopyWith(_PhotoDto value, $Res Function(_PhotoDto) _then) = __$PhotoDtoCopyWithImpl;
@override @useResult
$Res call({
 String kind, String capturedAt, String url
});




}
/// @nodoc
class __$PhotoDtoCopyWithImpl<$Res>
    implements _$PhotoDtoCopyWith<$Res> {
  __$PhotoDtoCopyWithImpl(this._self, this._then);

  final _PhotoDto _self;
  final $Res Function(_PhotoDto) _then;

/// Create a copy of PhotoDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? capturedAt = null,Object? url = null,}) {
  return _then(_PhotoDto(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,capturedAt: null == capturedAt ? _self.capturedAt : capturedAt // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$PaymentSummaryDto {

 String get status; String get method; int get amountPaise;
/// Create a copy of PaymentSummaryDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PaymentSummaryDtoCopyWith<PaymentSummaryDto> get copyWith => _$PaymentSummaryDtoCopyWithImpl<PaymentSummaryDto>(this as PaymentSummaryDto, _$identity);

  /// Serializes this PaymentSummaryDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PaymentSummaryDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PaymentSummaryDto&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.method, _this.method) || other.method == _this.method)&&(identical(other.amountPaise, _this.amountPaise) || other.amountPaise == _this.amountPaise));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PaymentSummaryDto;
  return Object.hash(runtimeType,_this.status,_this.method,_this.amountPaise);
}

@override
String toString() {
  final _this = this as PaymentSummaryDto;
  return 'PaymentSummaryDto(status: ${_this.status}, method: ${_this.method}, amountPaise: ${_this.amountPaise})';
}


}

/// @nodoc
abstract mixin class $PaymentSummaryDtoCopyWith<$Res>  {
  factory $PaymentSummaryDtoCopyWith(PaymentSummaryDto value, $Res Function(PaymentSummaryDto) _then) = _$PaymentSummaryDtoCopyWithImpl;
@useResult
$Res call({
 String status, String method, int amountPaise
});




}
/// @nodoc
class _$PaymentSummaryDtoCopyWithImpl<$Res>
    implements $PaymentSummaryDtoCopyWith<$Res> {
  _$PaymentSummaryDtoCopyWithImpl(this._self, this._then);

  final PaymentSummaryDto _self;
  final $Res Function(PaymentSummaryDto) _then;

/// Create a copy of PaymentSummaryDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? method = null,Object? amountPaise = null,}) {
  return _then(PaymentSummaryDto(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as String,amountPaise: null == amountPaise ? _self.amountPaise : amountPaise // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PaymentSummaryDto].
extension PaymentSummaryDtoPatterns on PaymentSummaryDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PaymentSummaryDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PaymentSummaryDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PaymentSummaryDto value)  $default,){
final _that = this;
switch (_that) {
case _PaymentSummaryDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PaymentSummaryDto value)?  $default,){
final _that = this;
switch (_that) {
case _PaymentSummaryDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String status,  String method,  int amountPaise)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PaymentSummaryDto() when $default != null:
return $default(_that.status,_that.method,_that.amountPaise);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String status,  String method,  int amountPaise)  $default,) {final _that = this;
switch (_that) {
case _PaymentSummaryDto():
return $default(_that.status,_that.method,_that.amountPaise);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String status,  String method,  int amountPaise)?  $default,) {final _that = this;
switch (_that) {
case _PaymentSummaryDto() when $default != null:
return $default(_that.status,_that.method,_that.amountPaise);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PaymentSummaryDto implements PaymentSummaryDto {
  const _PaymentSummaryDto({required this.status, required this.method, required this.amountPaise});
  factory _PaymentSummaryDto.fromJson(Map<String, dynamic> json) => _$PaymentSummaryDtoFromJson(json);

@override final  String status;
@override final  String method;
@override final  int amountPaise;

/// Create a copy of PaymentSummaryDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PaymentSummaryDtoCopyWith<_PaymentSummaryDto> get copyWith => __$PaymentSummaryDtoCopyWithImpl<_PaymentSummaryDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PaymentSummaryDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PaymentSummaryDto&&(identical(other.status, status) || other.status == status)&&(identical(other.method, method) || other.method == method)&&(identical(other.amountPaise, amountPaise) || other.amountPaise == amountPaise));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,status,method,amountPaise);
}

@override
String toString() {
    return 'PaymentSummaryDto(status: $status, method: $method, amountPaise: $amountPaise)';
}


}

/// @nodoc
abstract mixin class _$PaymentSummaryDtoCopyWith<$Res> implements $PaymentSummaryDtoCopyWith<$Res> {
  factory _$PaymentSummaryDtoCopyWith(_PaymentSummaryDto value, $Res Function(_PaymentSummaryDto) _then) = __$PaymentSummaryDtoCopyWithImpl;
@override @useResult
$Res call({
 String status, String method, int amountPaise
});




}
/// @nodoc
class __$PaymentSummaryDtoCopyWithImpl<$Res>
    implements _$PaymentSummaryDtoCopyWith<$Res> {
  __$PaymentSummaryDtoCopyWithImpl(this._self, this._then);

  final _PaymentSummaryDto _self;
  final $Res Function(_PaymentSummaryDto) _then;

/// Create a copy of PaymentSummaryDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? method = null,Object? amountPaise = null,}) {
  return _then(_PaymentSummaryDto(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as String,amountPaise: null == amountPaise ? _self.amountPaise : amountPaise // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$DisputeSummaryDto {

 String get status; String get outcome; int? get refundPaise;
/// Create a copy of DisputeSummaryDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DisputeSummaryDtoCopyWith<DisputeSummaryDto> get copyWith => _$DisputeSummaryDtoCopyWithImpl<DisputeSummaryDto>(this as DisputeSummaryDto, _$identity);

  /// Serializes this DisputeSummaryDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as DisputeSummaryDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DisputeSummaryDto&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.outcome, _this.outcome) || other.outcome == _this.outcome)&&(identical(other.refundPaise, _this.refundPaise) || other.refundPaise == _this.refundPaise));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as DisputeSummaryDto;
  return Object.hash(runtimeType,_this.status,_this.outcome,_this.refundPaise);
}

@override
String toString() {
  final _this = this as DisputeSummaryDto;
  return 'DisputeSummaryDto(status: ${_this.status}, outcome: ${_this.outcome}, refundPaise: ${_this.refundPaise})';
}


}

/// @nodoc
abstract mixin class $DisputeSummaryDtoCopyWith<$Res>  {
  factory $DisputeSummaryDtoCopyWith(DisputeSummaryDto value, $Res Function(DisputeSummaryDto) _then) = _$DisputeSummaryDtoCopyWithImpl;
@useResult
$Res call({
 String status, String outcome, int? refundPaise
});




}
/// @nodoc
class _$DisputeSummaryDtoCopyWithImpl<$Res>
    implements $DisputeSummaryDtoCopyWith<$Res> {
  _$DisputeSummaryDtoCopyWithImpl(this._self, this._then);

  final DisputeSummaryDto _self;
  final $Res Function(DisputeSummaryDto) _then;

/// Create a copy of DisputeSummaryDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? outcome = null,Object? refundPaise = freezed,}) {
  return _then(DisputeSummaryDto(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as String,refundPaise: freezed == refundPaise ? _self.refundPaise : refundPaise // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [DisputeSummaryDto].
extension DisputeSummaryDtoPatterns on DisputeSummaryDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DisputeSummaryDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DisputeSummaryDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DisputeSummaryDto value)  $default,){
final _that = this;
switch (_that) {
case _DisputeSummaryDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DisputeSummaryDto value)?  $default,){
final _that = this;
switch (_that) {
case _DisputeSummaryDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String status,  String outcome,  int? refundPaise)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DisputeSummaryDto() when $default != null:
return $default(_that.status,_that.outcome,_that.refundPaise);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String status,  String outcome,  int? refundPaise)  $default,) {final _that = this;
switch (_that) {
case _DisputeSummaryDto():
return $default(_that.status,_that.outcome,_that.refundPaise);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String status,  String outcome,  int? refundPaise)?  $default,) {final _that = this;
switch (_that) {
case _DisputeSummaryDto() when $default != null:
return $default(_that.status,_that.outcome,_that.refundPaise);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DisputeSummaryDto implements DisputeSummaryDto {
  const _DisputeSummaryDto({required this.status, required this.outcome, this.refundPaise});
  factory _DisputeSummaryDto.fromJson(Map<String, dynamic> json) => _$DisputeSummaryDtoFromJson(json);

@override final  String status;
@override final  String outcome;
@override final  int? refundPaise;

/// Create a copy of DisputeSummaryDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DisputeSummaryDtoCopyWith<_DisputeSummaryDto> get copyWith => __$DisputeSummaryDtoCopyWithImpl<_DisputeSummaryDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DisputeSummaryDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DisputeSummaryDto&&(identical(other.status, status) || other.status == status)&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.refundPaise, refundPaise) || other.refundPaise == refundPaise));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,status,outcome,refundPaise);
}

@override
String toString() {
    return 'DisputeSummaryDto(status: $status, outcome: $outcome, refundPaise: $refundPaise)';
}


}

/// @nodoc
abstract mixin class _$DisputeSummaryDtoCopyWith<$Res> implements $DisputeSummaryDtoCopyWith<$Res> {
  factory _$DisputeSummaryDtoCopyWith(_DisputeSummaryDto value, $Res Function(_DisputeSummaryDto) _then) = __$DisputeSummaryDtoCopyWithImpl;
@override @useResult
$Res call({
 String status, String outcome, int? refundPaise
});




}
/// @nodoc
class __$DisputeSummaryDtoCopyWithImpl<$Res>
    implements _$DisputeSummaryDtoCopyWith<$Res> {
  __$DisputeSummaryDtoCopyWithImpl(this._self, this._then);

  final _DisputeSummaryDto _self;
  final $Res Function(_DisputeSummaryDto) _then;

/// Create a copy of DisputeSummaryDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? outcome = null,Object? refundPaise = freezed,}) {
  return _then(_DisputeSummaryDto(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as String,refundPaise: freezed == refundPaise ? _self.refundPaise : refundPaise // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}


/// @nodoc
mixin _$BookingDto {

 String get id; String get bookingNumber; String get state; String get scheduledSlot; int get visitFeePaise; int get laborPaise; String? get laborTier; BookingServiceDto get service; BookingZoneDto get zone; BookingAddressRefDto get address; TechnicianRefDto? get technician; DiagnosisDto? get diagnosis; List<PartDto> get parts; EstimateDto get estimate; List<PhotoDto> get photos; PaymentSummaryDto? get payment; DisputeSummaryDto? get dispute;
/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BookingDtoCopyWith<BookingDto> get copyWith => _$BookingDtoCopyWithImpl<BookingDto>(this as BookingDto, _$identity);

  /// Serializes this BookingDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as BookingDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BookingDto&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.bookingNumber, _this.bookingNumber) || other.bookingNumber == _this.bookingNumber)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.scheduledSlot, _this.scheduledSlot) || other.scheduledSlot == _this.scheduledSlot)&&(identical(other.visitFeePaise, _this.visitFeePaise) || other.visitFeePaise == _this.visitFeePaise)&&(identical(other.laborPaise, _this.laborPaise) || other.laborPaise == _this.laborPaise)&&(identical(other.laborTier, _this.laborTier) || other.laborTier == _this.laborTier)&&(identical(other.service, _this.service) || other.service == _this.service)&&(identical(other.zone, _this.zone) || other.zone == _this.zone)&&(identical(other.address, _this.address) || other.address == _this.address)&&(identical(other.technician, _this.technician) || other.technician == _this.technician)&&(identical(other.diagnosis, _this.diagnosis) || other.diagnosis == _this.diagnosis)&&const DeepCollectionEquality().equals(other.parts, _this.parts)&&(identical(other.estimate, _this.estimate) || other.estimate == _this.estimate)&&const DeepCollectionEquality().equals(other.photos, _this.photos)&&(identical(other.payment, _this.payment) || other.payment == _this.payment)&&(identical(other.dispute, _this.dispute) || other.dispute == _this.dispute));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as BookingDto;
  return Object.hash(runtimeType,_this.id,_this.bookingNumber,_this.state,_this.scheduledSlot,_this.visitFeePaise,_this.laborPaise,_this.laborTier,_this.service,_this.zone,_this.address,_this.technician,_this.diagnosis,const DeepCollectionEquality().hash(_this.parts),_this.estimate,const DeepCollectionEquality().hash(_this.photos),_this.payment,_this.dispute);
}

@override
String toString() {
  final _this = this as BookingDto;
  return 'BookingDto(id: ${_this.id}, bookingNumber: ${_this.bookingNumber}, state: ${_this.state}, scheduledSlot: ${_this.scheduledSlot}, visitFeePaise: ${_this.visitFeePaise}, laborPaise: ${_this.laborPaise}, laborTier: ${_this.laborTier}, service: ${_this.service}, zone: ${_this.zone}, address: ${_this.address}, technician: ${_this.technician}, diagnosis: ${_this.diagnosis}, parts: ${_this.parts}, estimate: ${_this.estimate}, photos: ${_this.photos}, payment: ${_this.payment}, dispute: ${_this.dispute})';
}


}

/// @nodoc
abstract mixin class $BookingDtoCopyWith<$Res>  {
  factory $BookingDtoCopyWith(BookingDto value, $Res Function(BookingDto) _then) = _$BookingDtoCopyWithImpl;
@useResult
$Res call({
 String id, String bookingNumber, String state, String scheduledSlot, int visitFeePaise, int laborPaise, String? laborTier, BookingServiceDto service, BookingZoneDto zone, BookingAddressRefDto address, TechnicianRefDto? technician, DiagnosisDto? diagnosis, List<PartDto> parts, EstimateDto estimate, List<PhotoDto> photos, PaymentSummaryDto? payment, DisputeSummaryDto? dispute
});


$BookingServiceDtoCopyWith<$Res> get service;$BookingZoneDtoCopyWith<$Res> get zone;$BookingAddressRefDtoCopyWith<$Res> get address;$TechnicianRefDtoCopyWith<$Res>? get technician;$DiagnosisDtoCopyWith<$Res>? get diagnosis;$EstimateDtoCopyWith<$Res> get estimate;$PaymentSummaryDtoCopyWith<$Res>? get payment;$DisputeSummaryDtoCopyWith<$Res>? get dispute;

}
/// @nodoc
class _$BookingDtoCopyWithImpl<$Res>
    implements $BookingDtoCopyWith<$Res> {
  _$BookingDtoCopyWithImpl(this._self, this._then);

  final BookingDto _self;
  final $Res Function(BookingDto) _then;

/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? bookingNumber = null,Object? state = null,Object? scheduledSlot = null,Object? visitFeePaise = null,Object? laborPaise = null,Object? laborTier = freezed,Object? service = null,Object? zone = null,Object? address = null,Object? technician = freezed,Object? diagnosis = freezed,Object? parts = null,Object? estimate = null,Object? photos = null,Object? payment = freezed,Object? dispute = freezed,}) {
  return _then(BookingDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,bookingNumber: null == bookingNumber ? _self.bookingNumber : bookingNumber // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,scheduledSlot: null == scheduledSlot ? _self.scheduledSlot : scheduledSlot // ignore: cast_nullable_to_non_nullable
as String,visitFeePaise: null == visitFeePaise ? _self.visitFeePaise : visitFeePaise // ignore: cast_nullable_to_non_nullable
as int,laborPaise: null == laborPaise ? _self.laborPaise : laborPaise // ignore: cast_nullable_to_non_nullable
as int,laborTier: freezed == laborTier ? _self.laborTier : laborTier // ignore: cast_nullable_to_non_nullable
as String?,service: null == service ? _self.service : service // ignore: cast_nullable_to_non_nullable
as BookingServiceDto,zone: null == zone ? _self.zone : zone // ignore: cast_nullable_to_non_nullable
as BookingZoneDto,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as BookingAddressRefDto,technician: freezed == technician ? _self.technician : technician // ignore: cast_nullable_to_non_nullable
as TechnicianRefDto?,diagnosis: freezed == diagnosis ? _self.diagnosis : diagnosis // ignore: cast_nullable_to_non_nullable
as DiagnosisDto?,parts: null == parts ? _self.parts : parts // ignore: cast_nullable_to_non_nullable
as List<PartDto>,estimate: null == estimate ? _self.estimate : estimate // ignore: cast_nullable_to_non_nullable
as EstimateDto,photos: null == photos ? _self.photos : photos // ignore: cast_nullable_to_non_nullable
as List<PhotoDto>,payment: freezed == payment ? _self.payment : payment // ignore: cast_nullable_to_non_nullable
as PaymentSummaryDto?,dispute: freezed == dispute ? _self.dispute : dispute // ignore: cast_nullable_to_non_nullable
as DisputeSummaryDto?,
  ));
}
/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BookingServiceDtoCopyWith<$Res> get service {
  
  return $BookingServiceDtoCopyWith<$Res>(_self.service, (value) {
    return _then(_self.copyWith(service: value));
  });
}/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BookingZoneDtoCopyWith<$Res> get zone {
  
  return $BookingZoneDtoCopyWith<$Res>(_self.zone, (value) {
    return _then(_self.copyWith(zone: value));
  });
}/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BookingAddressRefDtoCopyWith<$Res> get address {
  
  return $BookingAddressRefDtoCopyWith<$Res>(_self.address, (value) {
    return _then(_self.copyWith(address: value));
  });
}/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TechnicianRefDtoCopyWith<$Res>? get technician {
    if (_self.technician == null) {
    return null;
  }

  return $TechnicianRefDtoCopyWith<$Res>(_self.technician!, (value) {
    return _then(_self.copyWith(technician: value));
  });
}/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DiagnosisDtoCopyWith<$Res>? get diagnosis {
    if (_self.diagnosis == null) {
    return null;
  }

  return $DiagnosisDtoCopyWith<$Res>(_self.diagnosis!, (value) {
    return _then(_self.copyWith(diagnosis: value));
  });
}/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EstimateDtoCopyWith<$Res> get estimate {
  
  return $EstimateDtoCopyWith<$Res>(_self.estimate, (value) {
    return _then(_self.copyWith(estimate: value));
  });
}/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PaymentSummaryDtoCopyWith<$Res>? get payment {
    if (_self.payment == null) {
    return null;
  }

  return $PaymentSummaryDtoCopyWith<$Res>(_self.payment!, (value) {
    return _then(_self.copyWith(payment: value));
  });
}/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DisputeSummaryDtoCopyWith<$Res>? get dispute {
    if (_self.dispute == null) {
    return null;
  }

  return $DisputeSummaryDtoCopyWith<$Res>(_self.dispute!, (value) {
    return _then(_self.copyWith(dispute: value));
  });
}
}


/// Adds pattern-matching-related methods to [BookingDto].
extension BookingDtoPatterns on BookingDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BookingDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BookingDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BookingDto value)  $default,){
final _that = this;
switch (_that) {
case _BookingDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BookingDto value)?  $default,){
final _that = this;
switch (_that) {
case _BookingDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String bookingNumber,  String state,  String scheduledSlot,  int visitFeePaise,  int laborPaise,  String? laborTier,  BookingServiceDto service,  BookingZoneDto zone,  BookingAddressRefDto address,  TechnicianRefDto? technician,  DiagnosisDto? diagnosis,  List<PartDto> parts,  EstimateDto estimate,  List<PhotoDto> photos,  PaymentSummaryDto? payment,  DisputeSummaryDto? dispute)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BookingDto() when $default != null:
return $default(_that.id,_that.bookingNumber,_that.state,_that.scheduledSlot,_that.visitFeePaise,_that.laborPaise,_that.laborTier,_that.service,_that.zone,_that.address,_that.technician,_that.diagnosis,_that.parts,_that.estimate,_that.photos,_that.payment,_that.dispute);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String bookingNumber,  String state,  String scheduledSlot,  int visitFeePaise,  int laborPaise,  String? laborTier,  BookingServiceDto service,  BookingZoneDto zone,  BookingAddressRefDto address,  TechnicianRefDto? technician,  DiagnosisDto? diagnosis,  List<PartDto> parts,  EstimateDto estimate,  List<PhotoDto> photos,  PaymentSummaryDto? payment,  DisputeSummaryDto? dispute)  $default,) {final _that = this;
switch (_that) {
case _BookingDto():
return $default(_that.id,_that.bookingNumber,_that.state,_that.scheduledSlot,_that.visitFeePaise,_that.laborPaise,_that.laborTier,_that.service,_that.zone,_that.address,_that.technician,_that.diagnosis,_that.parts,_that.estimate,_that.photos,_that.payment,_that.dispute);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String bookingNumber,  String state,  String scheduledSlot,  int visitFeePaise,  int laborPaise,  String? laborTier,  BookingServiceDto service,  BookingZoneDto zone,  BookingAddressRefDto address,  TechnicianRefDto? technician,  DiagnosisDto? diagnosis,  List<PartDto> parts,  EstimateDto estimate,  List<PhotoDto> photos,  PaymentSummaryDto? payment,  DisputeSummaryDto? dispute)?  $default,) {final _that = this;
switch (_that) {
case _BookingDto() when $default != null:
return $default(_that.id,_that.bookingNumber,_that.state,_that.scheduledSlot,_that.visitFeePaise,_that.laborPaise,_that.laborTier,_that.service,_that.zone,_that.address,_that.technician,_that.diagnosis,_that.parts,_that.estimate,_that.photos,_that.payment,_that.dispute);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BookingDto implements BookingDto {
  const _BookingDto({required this.id, required this.bookingNumber, required this.state, required this.scheduledSlot, required this.visitFeePaise, required this.laborPaise, this.laborTier, required this.service, required this.zone, required this.address, this.technician, this.diagnosis,  List<PartDto> parts = const <PartDto>[], required this.estimate,  List<PhotoDto> photos = const <PhotoDto>[], this.payment, this.dispute}): _parts = parts,_photos = photos;
  factory _BookingDto.fromJson(Map<String, dynamic> json) => _$BookingDtoFromJson(json);

@override final  String id;
@override final  String bookingNumber;
@override final  String state;
@override final  String scheduledSlot;
@override final  int visitFeePaise;
@override final  int laborPaise;
@override final  String? laborTier;
@override final  BookingServiceDto service;
@override final  BookingZoneDto zone;
@override final  BookingAddressRefDto address;
@override final  TechnicianRefDto? technician;
@override final  DiagnosisDto? diagnosis;
 final  List<PartDto> _parts;
@override@JsonKey() List<PartDto> get parts {
  if (_parts is EqualUnmodifiableListView) return _parts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_parts);
}

@override final  EstimateDto estimate;
 final  List<PhotoDto> _photos;
@override@JsonKey() List<PhotoDto> get photos {
  if (_photos is EqualUnmodifiableListView) return _photos;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_photos);
}

@override final  PaymentSummaryDto? payment;
@override final  DisputeSummaryDto? dispute;

/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BookingDtoCopyWith<_BookingDto> get copyWith => __$BookingDtoCopyWithImpl<_BookingDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BookingDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BookingDto&&(identical(other.id, id) || other.id == id)&&(identical(other.bookingNumber, bookingNumber) || other.bookingNumber == bookingNumber)&&(identical(other.state, state) || other.state == state)&&(identical(other.scheduledSlot, scheduledSlot) || other.scheduledSlot == scheduledSlot)&&(identical(other.visitFeePaise, visitFeePaise) || other.visitFeePaise == visitFeePaise)&&(identical(other.laborPaise, laborPaise) || other.laborPaise == laborPaise)&&(identical(other.laborTier, laborTier) || other.laborTier == laborTier)&&(identical(other.service, service) || other.service == service)&&(identical(other.zone, zone) || other.zone == zone)&&(identical(other.address, address) || other.address == address)&&(identical(other.technician, technician) || other.technician == technician)&&(identical(other.diagnosis, diagnosis) || other.diagnosis == diagnosis)&&const DeepCollectionEquality().equals(other.parts, _parts)&&(identical(other.estimate, estimate) || other.estimate == estimate)&&const DeepCollectionEquality().equals(other.photos, _photos)&&(identical(other.payment, payment) || other.payment == payment)&&(identical(other.dispute, dispute) || other.dispute == dispute));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,bookingNumber,state,scheduledSlot,visitFeePaise,laborPaise,laborTier,service,zone,address,technician,diagnosis,const DeepCollectionEquality().hash(_parts),estimate,const DeepCollectionEquality().hash(_photos),payment,dispute);
}

@override
String toString() {
    return 'BookingDto(id: $id, bookingNumber: $bookingNumber, state: $state, scheduledSlot: $scheduledSlot, visitFeePaise: $visitFeePaise, laborPaise: $laborPaise, laborTier: $laborTier, service: $service, zone: $zone, address: $address, technician: $technician, diagnosis: $diagnosis, parts: $parts, estimate: $estimate, photos: $photos, payment: $payment, dispute: $dispute)';
}


}

/// @nodoc
abstract mixin class _$BookingDtoCopyWith<$Res> implements $BookingDtoCopyWith<$Res> {
  factory _$BookingDtoCopyWith(_BookingDto value, $Res Function(_BookingDto) _then) = __$BookingDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String bookingNumber, String state, String scheduledSlot, int visitFeePaise, int laborPaise, String? laborTier, BookingServiceDto service, BookingZoneDto zone, BookingAddressRefDto address, TechnicianRefDto? technician, DiagnosisDto? diagnosis, List<PartDto> parts, EstimateDto estimate, List<PhotoDto> photos, PaymentSummaryDto? payment, DisputeSummaryDto? dispute
});


@override $BookingServiceDtoCopyWith<$Res> get service;@override $BookingZoneDtoCopyWith<$Res> get zone;@override $BookingAddressRefDtoCopyWith<$Res> get address;@override $TechnicianRefDtoCopyWith<$Res>? get technician;@override $DiagnosisDtoCopyWith<$Res>? get diagnosis;@override $EstimateDtoCopyWith<$Res> get estimate;@override $PaymentSummaryDtoCopyWith<$Res>? get payment;@override $DisputeSummaryDtoCopyWith<$Res>? get dispute;

}
/// @nodoc
class __$BookingDtoCopyWithImpl<$Res>
    implements _$BookingDtoCopyWith<$Res> {
  __$BookingDtoCopyWithImpl(this._self, this._then);

  final _BookingDto _self;
  final $Res Function(_BookingDto) _then;

/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? bookingNumber = null,Object? state = null,Object? scheduledSlot = null,Object? visitFeePaise = null,Object? laborPaise = null,Object? laborTier = freezed,Object? service = null,Object? zone = null,Object? address = null,Object? technician = freezed,Object? diagnosis = freezed,Object? parts = null,Object? estimate = null,Object? photos = null,Object? payment = freezed,Object? dispute = freezed,}) {
  return _then(_BookingDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,bookingNumber: null == bookingNumber ? _self.bookingNumber : bookingNumber // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,scheduledSlot: null == scheduledSlot ? _self.scheduledSlot : scheduledSlot // ignore: cast_nullable_to_non_nullable
as String,visitFeePaise: null == visitFeePaise ? _self.visitFeePaise : visitFeePaise // ignore: cast_nullable_to_non_nullable
as int,laborPaise: null == laborPaise ? _self.laborPaise : laborPaise // ignore: cast_nullable_to_non_nullable
as int,laborTier: freezed == laborTier ? _self.laborTier : laborTier // ignore: cast_nullable_to_non_nullable
as String?,service: null == service ? _self.service : service // ignore: cast_nullable_to_non_nullable
as BookingServiceDto,zone: null == zone ? _self.zone : zone // ignore: cast_nullable_to_non_nullable
as BookingZoneDto,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as BookingAddressRefDto,technician: freezed == technician ? _self.technician : technician // ignore: cast_nullable_to_non_nullable
as TechnicianRefDto?,diagnosis: freezed == diagnosis ? _self.diagnosis : diagnosis // ignore: cast_nullable_to_non_nullable
as DiagnosisDto?,parts: null == parts ? _self._parts : parts // ignore: cast_nullable_to_non_nullable
as List<PartDto>,estimate: null == estimate ? _self.estimate : estimate // ignore: cast_nullable_to_non_nullable
as EstimateDto,photos: null == photos ? _self._photos : photos // ignore: cast_nullable_to_non_nullable
as List<PhotoDto>,payment: freezed == payment ? _self.payment : payment // ignore: cast_nullable_to_non_nullable
as PaymentSummaryDto?,dispute: freezed == dispute ? _self.dispute : dispute // ignore: cast_nullable_to_non_nullable
as DisputeSummaryDto?,
  ));
}

/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BookingServiceDtoCopyWith<$Res> get service {
  
  return $BookingServiceDtoCopyWith<$Res>(_self.service, (value) {
    return _then(_self.copyWith(service: value));
  });
}/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BookingZoneDtoCopyWith<$Res> get zone {
  
  return $BookingZoneDtoCopyWith<$Res>(_self.zone, (value) {
    return _then(_self.copyWith(zone: value));
  });
}/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BookingAddressRefDtoCopyWith<$Res> get address {
  
  return $BookingAddressRefDtoCopyWith<$Res>(_self.address, (value) {
    return _then(_self.copyWith(address: value));
  });
}/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TechnicianRefDtoCopyWith<$Res>? get technician {
    if (_self.technician == null) {
    return null;
  }

  return $TechnicianRefDtoCopyWith<$Res>(_self.technician!, (value) {
    return _then(_self.copyWith(technician: value));
  });
}/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DiagnosisDtoCopyWith<$Res>? get diagnosis {
    if (_self.diagnosis == null) {
    return null;
  }

  return $DiagnosisDtoCopyWith<$Res>(_self.diagnosis!, (value) {
    return _then(_self.copyWith(diagnosis: value));
  });
}/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EstimateDtoCopyWith<$Res> get estimate {
  
  return $EstimateDtoCopyWith<$Res>(_self.estimate, (value) {
    return _then(_self.copyWith(estimate: value));
  });
}/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PaymentSummaryDtoCopyWith<$Res>? get payment {
    if (_self.payment == null) {
    return null;
  }

  return $PaymentSummaryDtoCopyWith<$Res>(_self.payment!, (value) {
    return _then(_self.copyWith(payment: value));
  });
}/// Create a copy of BookingDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DisputeSummaryDtoCopyWith<$Res>? get dispute {
    if (_self.dispute == null) {
    return null;
  }

  return $DisputeSummaryDtoCopyWith<$Res>(_self.dispute!, (value) {
    return _then(_self.copyWith(dispute: value));
  });
}
}

// dart format on
