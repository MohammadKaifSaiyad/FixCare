import 'package:dio/dio.dart';
import '../result.dart';

/// A job call answered 403 `TECHNICIAN_NOT_VERIFIED`: ops suspended (or un-verified) this technician while
/// they were using the app. Tell the session to re-check the profile so the home gate shows the right
/// screen instead of a generic error. The response itself is passed through untouched.
class NotVerifiedInterceptor extends Interceptor {
  NotVerifiedInterceptor(this._onNotVerified);
  final void Function() _onNotVerified;

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.statusCode == 403 && errorCodeOf(response.data) == 'TECHNICIAN_NOT_VERIFIED') _onNotVerified();
    handler.next(response);
  }
}
