import 'dart:convert';
import 'dart:io';

import 'package:admin/data/services/terminal_server_error.dart';
import 'package:admin/ui/features/terminal/terminal_error_text.dart';
import 'package:admin/ui/features/terminal/view_models/collect_card_payment_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_services/store_services.dart';

/// Every way taking a card can fail has words the person at the counter can
/// act on (docs/in-person-payments.md): each SDK code and each server code
/// maps to a key, and every key exists in English.
void main() {
  final strings = <String, String>{
    ...(jsonDecode(File('assets/i18n/en.json').readAsStringSync()) as Map)
        .cast<String, String>(),
    ...(jsonDecode(File('assets/i18n/_app_pending.json').readAsStringSync())
            as Map)
        .map((k, v) => MapEntry(k as String, '$v')),
  };

  String tr(String key, [Map<String, String>? params]) {
    var text = strings[key];
    expect(text, isNotNull, reason: 'missing string $key');
    for (final e in (params ?? const <String, String>{}).entries) {
      text = text!.replaceAll(':${e.key}', e.value);
    }
    expect(text, isNot(contains(RegExp(r':[a-z]'))), reason: key);
    return text!;
  }

  test('every SDK code has words, on an iPhone and elsewhere', () {
    for (final iPhone in [false, true]) {
      for (final code in TerminalErrorCode.values) {
        expect(
          terminalProblemText(
            CollectProblem(code: code),
            tr,
            name: (_) => iPhone ? 'Tap to Pay on iPhone' : 'Tap to Pay',
            iOS: iPhone,
          ),
          isNotEmpty,
          reason: '$code',
        );
      }
    }
  });

  test('Apple\'s terms each have their own words, and name the feature in '
      'full on an iPhone', () {
    final texts = {
      for (final code in [
        TerminalErrorCode.termsNotAccepted,
        TerminalErrorCode.termsCanceled,
        TerminalErrorCode.termsNeedsAppleAccount,
        TerminalErrorCode.termsFailed,
      ])
        code: terminalProblemText(
          CollectProblem(code: code),
          tr,
          name: (_) => 'Tap to Pay on iPhone',
          iOS: true,
        ),
    };
    expect(texts.values.toSet(), hasLength(4));
    for (final text in texts.values) {
      expect(text, contains('Tap to Pay on iPhone'));
    }
    // App Review 3.8.1: a user who can't accept them is told to ask an admin.
    expect(
      texts[TerminalErrorCode.termsNotAccepted],
      'Ask an admin to turn on Tap to Pay on iPhone.',
    );
  });

  test('an out-of-date iOS says to update it; Android keeps its own words', () {
    expect(
      terminalProblemText(
        const CollectProblem(code: TerminalErrorCode.unsupportedOs),
        tr,
        name: (_) => 'Tap to Pay on iPhone',
        iOS: true,
      ),
      'Tap to Pay on iPhone needs the latest version of iOS. Update in '
      'Settings, General, Software Update.',
    );
    expect(
      terminalProblemText(
        const CollectProblem(code: TerminalErrorCode.unsupportedOs),
        tr,
        name: (_) => 'Tap to Pay',
        iOS: false,
      ),
      'Tap to Pay needs a newer version of Android.',
    );
  });

  test('every server code the app knows has words', () {
    for (final code in TerminalServerError.known) {
      expect(
        terminalProblemText(
          CollectProblem(
            serverCode: code,
            message: code == TerminalServerError.fieldErrors ? 'Too much' : '',
            data: const {'user': 'Sam', 'age': 90},
          ),
          tr,
          name: (_) => 'Tap to Pay on iPhone',
        ),
        isNotEmpty,
        reason: code,
      );
    }
  });

  test('an iPhone or iPad never reads Android\'s words', () {
    for (final code in TerminalErrorCode.values) {
      final text = terminalProblemText(
        CollectProblem(code: code),
        tr,
        name: (_) => 'Tap to Pay on iPhone',
        iOS: true,
      );
      expect(text, isNot(contains('Android')), reason: '$code');
      expect(text, isNot(contains('this phone')), reason: '$code');
    }
    expect(
      terminalProblemText(
        const CollectProblem(code: TerminalErrorCode.insecureEnvironment),
        tr,
        name: (_) => 'Tap to Pay on iPhone',
        iOS: true,
      ),
      'Stop screen recording or mirroring, and disconnect any debugger, then '
      'try again.',
    );
  });

  test('the name each sentence gets is asked for by its own key', () {
    final asked = <String>[];
    terminalProblemText(
      const CollectProblem(code: TerminalErrorCode.passcodeNotEnabled),
      tr,
      name: (key) {
        asked.add(key);
        return 'Tap to Pay on iPhone';
      },
      iOS: true,
    );
    expect(asked, ['terminal_error_passcode_ios']);
  });

  test('the app\'s own Tap to Pay on iPhone refusals have words', () {
    for (final code in ['tap_to_pay_ask_admin', 'connect_stripe_first']) {
      expect(
        terminalProblemText(
          CollectProblem(serverCode: code),
          tr,
          name: (_) => 'Tap to Pay on iPhone',
        ),
        contains('Tap to Pay on iPhone'),
        reason: code,
      );
    }
  });

  test('an open collection names who and how long ago', () {
    expect(
      terminalProblemText(
        const CollectProblem(
          serverCode: TerminalServerError.collectionOpen,
          data: {'user': 'Sam', 'age': 90},
        ),
        tr,
        name: (_) => 'Tap to Pay',
      ),
      'A card payment started 2 min ago by Sam is still open.',
    );
  });

  test('an unknown server code falls back to the server message, never a raw '
      'SDK one', () {
    expect(
      terminalProblemText(
        const CollectProblem(serverCode: 'new_thing', message: 'Server says'),
        tr,
        name: (_) => 'Tap to Pay',
      ),
      'Server says',
    );
    expect(
      terminalProblemText(
        const CollectProblem(
          code: TerminalErrorCode.declined,
          message: 'card_declined: insufficient_funds',
        ),
        tr,
        name: (_) => 'Tap to Pay',
      ),
      isNot(contains('insufficient_funds')),
    );
  });
}
