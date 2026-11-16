import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CI lint: the Linux runner links libgcc_s ahead of everything else.
///
/// Flutter 3.50's `libflutter_linux_gtk.so` exports LLVM libunwind's
/// `_Unwind_*` functions. The dynamic linker binds a symbol to the first
/// library in load order that defines it, so unless libgcc_s is loaded before
/// the engine, a C++ `throw` inside a plugin is unwound by the engine's
/// unwinder, its `catch` is never found, and the process aborts.
/// `flutter_secure_storage_linux` throws on every keyring failure, so the app
/// closed before its first frame wherever the keyring was locked or
/// unreachable (invoiceninja/app#194) instead of showing the keyring screen.
///
/// Nothing else notices if the line goes: the app builds, and it runs wherever
/// the keyring answers. See `docs/upstream-workarounds.md` entry 23 for the
/// revert condition.
void main() {
  test('the Linux runner loads libgcc_s before the Flutter engine', () {
    final cmake = File('linux/runner/CMakeLists.txt').readAsStringSync();

    final option = cmake.indexOf(
      'target_link_options(\${BINARY_NAME} PRIVATE\n'
      '  "LINKER:--push-state,--no-as-needed,-lgcc_s,--pop-state")',
    );
    expect(
      option,
      isNot(-1),
      reason:
          'linux/runner/CMakeLists.txt must link libgcc_s with '
          '--no-as-needed through target_link_options '
          '(docs/upstream-workarounds.md entry 23).',
    );

    // A link *option* lands before the libraries on the link line whatever
    // the order here, but a later edit that turns it into a link library
    // would depend on this order.
    final firstLibrary = cmake.indexOf('target_link_libraries(');
    expect(option, lessThan(firstLibrary));
  });

  // The source line above only says what was asked of the linker. What proves
  // it is `tools/check_linux_keyring_failure.sh`, which launches the built
  // bundle with no keyring and fails unless the app survives. It has to run
  // wherever a Linux build is made: the compile gate, and both workflows that
  // publish one (the Flatpak is built by Flathub from the same tag).
  test('every workflow that builds Linux launches it with no keyring', () {
    const script = 'tools/check_linux_keyring_failure.sh';
    expect(File(script).existsSync(), isTrue);
    for (final workflow in ['ci.yaml', 'appimage.yml', 'snapcraft.yml']) {
      final yaml = File('.github/workflows/$workflow').readAsStringSync();
      final build = yaml.indexOf(
        workflow == 'appimage.yml'
            ? 'run: tools/build_appimage.sh'
            : 'flutter build linux --release',
      );
      final check = yaml.indexOf('run: $script');
      expect(build, isNot(-1), reason: '$workflow builds Linux');
      expect(
        check,
        greaterThan(build),
        reason: '$workflow must run $script after its Linux build',
      );
    }
  });
}
