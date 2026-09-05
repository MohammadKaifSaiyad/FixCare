// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_wizard_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(BookingWizard)
final bookingWizardProvider = BookingWizardFamily._();

final class BookingWizardProvider
    extends $NotifierProvider<BookingWizard, BookingWizardState> {
  BookingWizardProvider._({
    required BookingWizardFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'bookingWizardProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$bookingWizardHash();

  @override
  String toString() {
    return r'bookingWizardProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  BookingWizard create() => BookingWizard();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BookingWizardState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BookingWizardState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BookingWizardProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$bookingWizardHash() => r'650636020dbf809462345c196e50469d42a7d896';

final class BookingWizardFamily extends $Family
    with
        $ClassFamilyOverride<
          BookingWizard,
          BookingWizardState,
          BookingWizardState,
          BookingWizardState,
          String
        > {
  BookingWizardFamily._()
    : super(
        retry: null,
        name: r'bookingWizardProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  BookingWizardProvider call(String serviceId) =>
      BookingWizardProvider._(argument: serviceId, from: this);

  @override
  String toString() => r'bookingWizardProvider';
}

abstract class _$BookingWizard extends $Notifier<BookingWizardState> {
  late final _$args = ref.$arg as String;
  String get serviceId => _$args;

  BookingWizardState build(String serviceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<BookingWizardState, BookingWizardState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BookingWizardState, BookingWizardState>,
              BookingWizardState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
