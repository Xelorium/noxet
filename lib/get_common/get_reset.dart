import '../get_core/get_core.dart';
import '../get_instance/get_instance.dart';

extension GetResetExt on GetInterface {
  /// Removes every registered instance. Useful in `tearDown` of tests.
  void reset(
      {@Deprecated('Has no effect without route management')
      bool clearRouteBindings = true}) {
    Get.resetInstance();
  }
}
