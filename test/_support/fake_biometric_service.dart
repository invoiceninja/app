import 'package:admin/data/services/biometric_service.dart';

/// Deterministic in-test fake. Queue `outcomes` ahead of each call;
/// `reasons` records the prompts so tests can assert the right copy was
/// passed. `available` controls what `isAvailable()` returns;
/// `ownerAvailable` what `canAuthenticateOwner()` does.
class FakeBiometricService implements BiometricService {
  final List<bool> outcomes = [];
  final List<String> reasons = [];
  bool available = true;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({required String reason}) async {
    reasons.add(reason);
    if (outcomes.isEmpty) return true;
    return outcomes.removeAt(0);
  }

  /// What `canAuthenticateOwner()` returns — the device passcode counts.
  bool ownerAvailable = true;

  /// How many times [authenticateOwner] was asked (the soft lock's prompt).
  int ownerPrompts = 0;

  @override
  Future<bool> canAuthenticateOwner() async => ownerAvailable;

  @override
  Future<bool> authenticateOwner({required String reason}) async {
    ownerPrompts++;
    return authenticate(reason: reason);
  }
}
