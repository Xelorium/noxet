import 'get_interface.dart';

/// Entry point for dependency injection (`Get.put`, `Get.find`, ...) and
/// global configuration such as [GetInterface.smartManagement] and logging.
class _GetImpl extends GetInterface {}

// ignore: non_constant_identifier_names
final Get = _GetImpl();
