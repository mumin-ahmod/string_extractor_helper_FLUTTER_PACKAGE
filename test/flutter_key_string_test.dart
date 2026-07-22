import 'dart:convert';
import 'dart:io';

import 'package:string_extractor_intl/string_extractor_intl.dart';
import 'package:test/test.dart';

void main() {
  group('Flutter Key string extraction', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'string_extractor_intl_key_test_',
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'does not extract programmatic strings from supported Flutter Key forms',
      () async {
        final inputDir = Directory('${tempDir.path}/lib')
          ..createSync(recursive: true);

        final outputDir = '${tempDir.path}/lib/l10n';

        final sourceFile = File('${inputDir.path}/main.dart');

        await sourceFile.writeAsString(r'''
import 'package:flutter/material.dart';

void buildExample(int i) {
  // Key
  const Key('plain_key');
  Key('plain_key_interpolated_\$i');

  // ValueKey
  const ValueKey('value_key');
  const ValueKey<String>('typed_value_key');
  ValueKey<String>('typed_value_key_interpolated_\$i');

  // PageStorageKey
  const PageStorageKey('page_storage_key');
  const PageStorageKey<String>('typed_page_storage_key');
  PageStorageKey<String>('typed_page_storage_key_interpolated_\$i');

  // ObjectKey
  const ObjectKey('object_key');
  ObjectKey('object_key_interpolated_\$i');

  // GlobalObjectKey
  const GlobalObjectKey('global_object_key');
  const GlobalObjectKey<String>('typed_global_object_key');
  GlobalObjectKey<String>('typed_global_object_key_interpolated_\$i');

  // GlobalKey debugLabel
  GlobalKey(
    debugLabel: 'global_key_debug_label',
  );

  GlobalKey<State>(
    debugLabel: 'typed_global_key_debug_label',
  );

  GlobalKey<State>(
    debugLabel: 'typed_global_key_debug_label_\$i',
  );

  // Real-world regression case.
  GestureDetector(
    key: Key('dashboard_carousel_dot_\$i'),
    child: const Text('VISIBLE TEXT'),
  );

  // These are normal user-facing strings and MUST still be extracted.
  const Text('ANOTHER VISIBLE TEXT');

  const Tooltip(
    message: 'VISIBLE TOOLTIP',
    child: SizedBox(),
  );
}
''');

        final extractor = LocalizationStringExtractor();

        await extractor.extractStrings(
          inputDirectory: inputDir.path,
          outputDirectory: outputDir,
          templateArbFile: 'app_en.arb',
          className: 'AppLocalizations',
          checkDependencies: false,
          replaceInFiles: false,
        );

        final arbFile = File('$outputDir/app_en.arb');

        expect(
          arbFile.existsSync(),
          isTrue,
          reason: 'The extractor should generate app_en.arb',
        );

        final arbData = jsonDecode(
          await arbFile.readAsString(),
        ) as Map<String, dynamic>;

        final extractedValues = arbData.values.toList();

        // Normal user-facing strings must still be extracted.
        expect(extractedValues, contains('VISIBLE TEXT'));
        expect(extractedValues, contains('ANOTHER VISIBLE TEXT'));
        expect(extractedValues, contains('VISIBLE TOOLTIP'));

        // Key
        expect(extractedValues, isNot(contains('plain_key')));
        expect(
          extractedValues,
          isNot(contains('plain_key_interpolated_\$i')),
        );

        // ValueKey
        expect(extractedValues, isNot(contains('value_key')));
        expect(extractedValues, isNot(contains('typed_value_key')));
        expect(
          extractedValues,
          isNot(contains('typed_value_key_interpolated_\$i')),
        );

        // PageStorageKey
        expect(extractedValues, isNot(contains('page_storage_key')));
        expect(
          extractedValues,
          isNot(contains('typed_page_storage_key')),
        );
        expect(
          extractedValues,
          isNot(contains('typed_page_storage_key_interpolated_\$i')),
        );

        // ObjectKey
        expect(extractedValues, isNot(contains('object_key')));
        expect(
          extractedValues,
          isNot(contains('object_key_interpolated_\$i')),
        );

        // GlobalObjectKey
        expect(extractedValues, isNot(contains('global_object_key')));
        expect(
          extractedValues,
          isNot(contains('typed_global_object_key')),
        );
        expect(
          extractedValues,
          isNot(contains('typed_global_object_key_interpolated_\$i')),
        );

        // GlobalKey debugLabel
        expect(
          extractedValues,
          isNot(contains('global_key_debug_label')),
        );
        expect(
          extractedValues,
          isNot(contains('typed_global_key_debug_label')),
        );
        expect(
          extractedValues,
          isNot(contains('typed_global_key_debug_label_\$i')),
        );

        // Exact production regression case.
        expect(
          extractedValues,
          isNot(contains('dashboard_carousel_dot_\$i')),
        );
      },
    );
  });
}