import 'dart:convert';
import 'dart:io';

import 'package:string_extractor_intl/string_extractor_intl.dart';
import 'package:test/test.dart';

void main() {
  group('Semantics identifier extraction', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'string_extractor_intl_test_',
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'does not extract Semantics.identifier but extracts visible Text',
      () async {
        // Arrange
        final inputDir = Directory('${tempDir.path}/lib')
          ..createSync(recursive: true);

        final outputDir = '${tempDir.path}/lib/l10n';

        final sourceFile = File('${inputDir.path}/main.dart');

        await sourceFile.writeAsString(r'''
import 'package:flutter/material.dart';

void buildExample() {
  Semantics(
    identifier: 'dashboard_attention_title',
    child: Text(
      'NEEDS ATTENTION',
    ),
  );
}
''');

        final extractor = LocalizationStringExtractor();

        // Act
        await extractor.extractStrings(
          inputDirectory: inputDir.path,
          outputDirectory: outputDir,
          templateArbFile: 'app_en.arb',
          className: 'AppLocalizations',

          // Avoid requiring this temporary fixture to have its own pubspec.yaml.
          checkDependencies: false,

          // We only want to test extraction, not source replacement.
          replaceInFiles: false,
        );

        // Assert
        final arbFile = File('$outputDir/app_en.arb');

        expect(
          arbFile.existsSync(),
          isTrue,
          reason: 'The extractor should generate app_en.arb',
        );

        final arbData =
            jsonDecode(await arbFile.readAsString()) as Map<String, dynamic>;

        // The visible UI text should be extracted.
        expect(arbData.values, contains('NEEDS ATTENTION'));

        // The programmatic Semantics identifier should NOT be extracted.
        expect(arbData.values, isNot(contains('dashboard_attention_title')));
      },
    );
  });
}
