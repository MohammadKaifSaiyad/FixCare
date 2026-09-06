// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_tracking_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(BookingTracking)
final bookingTrackingProvider = BookingTrackingFamily._();

final class BookingTrackingProvider
    extends $AsyncNotifierProvider<BookingTracking, BookingDto> {
  BookingTrackingProvider._({
    required BookingTrackingFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'bookingTrackingProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$bookingTrackingHash();

  @override
  String toString() {
    return r'bookingTrackingProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  BookingTracking create() => BookingTracking();

  @override
  bool operator ==(Object other) {
    return other is BookingTrackingProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$bookingTrackingHash() => r'95a4fc020fc6a04a1b943501e44ca16caaf34d94';

final class BookingTrackingFamily extends $Family
    with
        $ClassFamilyOverride<
          BookingTracking,
          AsyncValue<BookingDto>,
          BookingDto,
          FutureOr<BookingDto>,
          String
        > {
  BookingTrackingFamily._()
    : super(
        retry: null,
        name: r'bookingTrackingProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  BookingTrackingProvider call(String bookingId) =>
      BookingTrackingProvider._(argument: bookingId, from: this);

  @override
  String toString() => r'bookingTrackingProvider';
}

abstract class _$BookingTracking extends $AsyncNotifier<BookingDto> {
  late final _$args = ref.$arg as String;
  String get bookingId => _$args;

  FutureOr<BookingDto> build(String bookingId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<BookingDto>, BookingDto>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<BookingDto>, BookingDto>,
              AsyncValue<BookingDto>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
