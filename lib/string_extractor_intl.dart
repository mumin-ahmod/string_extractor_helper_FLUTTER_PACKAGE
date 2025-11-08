import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'dart:math' as math;
import 'package:yaml/yaml.dart';

class LocalizationStringExtractor {
  // Map to store unique strings and their generated keys to prevent duplicates
  final Map<String, String> _uniqueStrings = {};
  // Map to store extracted strings with their full ARB data
  final Map<String, Map<String, dynamic>> _extractedStrings = {};
  // Keep track of processed files for replacement
  final Set<String> _processedFiles = {};
  // Counter for generic keys if needed (though we'll try to avoid it now)
  int _stringCounter = 0;

  Future<void> extractStrings({
    required String inputDirectory,
    required String outputDirectory,
    required String templateArbFile,
    required String className, // This will now be used to configure the output class in l10n.yaml
    bool replaceInFiles = false,
    bool checkDependencies = true,
  }) async {
    final inputDir = Directory(inputDirectory);

    if (!inputDir.existsSync()) {
      throw Exception('Input directory does not exist: $inputDirectory');
    }

    if (checkDependencies) {
      await _checkDependencies();
    }

    print('🔍 Scanning for Dart files...');
    // Pass the actual class name provided by the user
    await _scanDirectory(inputDir, className, replaceInFiles);

    if (_extractedStrings.isEmpty) {
      print('ℹ️  No hardcoded strings found.');
      return;
    }

    print('📝 Found ${_extractedStrings.length} unique localizable strings');
    await _generateArbFile(outputDirectory, templateArbFile);
    await _generateL10nYaml(outputDirectory, className); // Use the provided className here

    if (replaceInFiles) {
      print('🔄 Updated ${_processedFiles.length} files with localization calls');

      // Automatically run flutter gen-l10n after replacement
      print('🏗️  Running flutter gen-l10n...');
      await _runFlutterGenL10n();
    }
  }

  Future<void> _checkDependencies() async {
    final pubspecFile = File('pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      throw Exception('pubspec.yaml not found. Make sure you\'re in a Flutter project root.');
    }

    final pubspecContent = await pubspecFile.readAsString();
    final pubspec = loadYaml(pubspecContent);

    final dependencies = pubspec['dependencies'] as Map?;

    bool hasIntl = false;
    bool hasFlutterLocalizations = false;

    if (dependencies != null) {
      hasIntl = dependencies.containsKey('intl');
      hasFlutterLocalizations = dependencies.containsKey('flutter_localizations');
    }

    final List<String> missingDeps = [];

    if (!hasIntl) {
      missingDeps.add('intl: ^0.19.0');
    }

    if (!hasFlutterLocalizations) {
      missingDeps.add('flutter_localizations:\n    sdk: flutter');
    }

    if (missingDeps.isNotEmpty) {
      print('⚠️  Missing required dependencies in pubspec.yaml:');
      print('Add these to your dependencies section:');
      for (final dep in missingDeps) {
        print('  $dep');
      }
      print('');
      print('Run: flutter pub get');
      print('');
    }
  }

  Future<void> _scanDirectory(Directory dir, String className, bool replaceInFiles) async {
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        await _processFile(entity, className, replaceInFiles);
      }
    }
  }

  Future<void> _processFile(File file, String className, bool replaceInFiles) async {
    final content = await file.readAsString();
    final strings = _extractStringsFromContent(content);

    if (strings.isEmpty) return;

    String updatedContent = content;
    bool fileModified = false;
    bool needsImport = false;

    for (final stringData in strings) {
      final originalString = stringData['original'] as String;
      final cleanString = stringData['clean'] as String;
      final context = stringData['context'] as String;

      if (_shouldIgnoreString(cleanString)) continue;

      // New logic for duplicate strings:
      // Check if this exact cleanString (without variables processed yet) already has a key
      String? existingKey = _uniqueStrings[cleanString];
      String keyName;
      if (existingKey != null) {
        keyName = existingKey; // Use the already generated key for this string
      } else {
        // If not, generate a new key and store it
        keyName = _generateKeyName(cleanString);
        _uniqueStrings[cleanString] = keyName;
      }

      final hasVariables = _detectVariables(cleanString);

      String replacement;
      if (hasVariables['hasVars']) {
        final methodCall = _generateMethodCall(className, keyName, hasVariables['variables'], context);
        replacement = methodCall;
        // Only add to _extractedStrings if it's a new unique key or needs updating with placeholders
        if (!_extractedStrings.containsKey(keyName) || (_extractedStrings[keyName]?['placeholders'] == null && hasVariables['variables'].isNotEmpty)) {
          _extractedStrings[keyName] = {
            'value': hasVariables['template'],
            'description': 'Localized string with parameters: ${hasVariables['variables'].join(', ')}',
            'placeholders': _generatePlaceholders(hasVariables['variables']),
          };
        }
      } else {
        replacement = _generateSimpleCall(className, keyName, context);
        // Only add to _extractedStrings if it's a new unique key
        if (!_extractedStrings.containsKey(keyName)) {
          _extractedStrings[keyName] = {
            'value': cleanString,
            'description': 'Localized string',
          };
        }
      }

      if (replaceInFiles) {
        // Replace the hardcoded string with localization call
        updatedContent = updatedContent.replaceAll(originalString, replacement);
        fileModified = true;
        needsImport = true;
      }
    }

    if (replaceInFiles && fileModified) {
      if (needsImport) {
        // Use the dynamic class name for the import path
        updatedContent = _addImportIfNeeded(updatedContent, className);
      }
      // Add MaterialApp localization configuration if needed
      updatedContent = _addMaterialAppLocalization(updatedContent, className);
      await file.writeAsString(updatedContent);
      _processedFiles.add(file.path);
    }
  }

  bool _isInMaterialAppTitle(String content, int position) {
    // Look backwards from the string position to see if we're in a MaterialApp title
    int start = math.max(0, position - 200);
    String contextStr = content.substring(start, position);

    // Check if we're within a MaterialApp context and specifically in title property
    if (contextStr.contains('MaterialApp(') || contextStr.contains('CupertinoApp(')) {
      // Look for title: pattern before our string
      final titlePattern = RegExp(r'title\s*:\s*$');
      final lines = contextStr.split('\n');
      final lastLine = lines.isNotEmpty ? lines.last : '';

      return titlePattern.hasMatch(lastLine.trim());
    }

    return false;
  }

  List<Map<String, String>> _extractStringsFromContent(String content) {
    final List<Map<String, String>> strings = [];
    final stringPatterns = [
      RegExp(r'"([^"\\]*(\\.[^"\\]*)*)"'), // Double quotes
      RegExp(r"'([^'\\]*(\\.[^'\\]*)*)'"), // Single quotes
    ];

    for (final pattern in stringPatterns) {
      final matches = pattern.allMatches(content);
      for (final match in matches) {
        final fullMatch = match.group(0)!;
        final innerString = match.group(1)!;

        // Skip if it's likely a import/export statement
        if (_isImportExportStatement(content, match.start)) continue;

        // Skip if it's in MaterialApp title (no context available)
        if (_isInMaterialAppTitle(content, match.start)) continue;

        // Get context (Text widget, etc.)
        final context = _getStringContext(content, match.start);

        strings.add({
          'original': fullMatch,
          'clean': innerString,
          'context': context,
        });
      }
    }

    return strings;
  }

  String _getStringContext(String content, int position) {
    // Look backwards to find the widget context
    int start = math.max(0, position - 100);
    String contextStr = content.substring(start, position);

    if (contextStr.contains('Text(')) return 'text';
    if (contextStr.contains('title:')) return 'title';
    if (contextStr.contains('AppBar(')) return 'appbar';
    if (contextStr.contains('SnackBar(')) return 'snackbar';
    if (contextStr.contains('AlertDialog(')) return 'dialog';
    // Add more context clues as needed
    if (contextStr.contains('hintText:')) return 'hintText';
    if (contextStr.contains('labelText:')) return 'labelText';
    if (contextStr.contains('buttonText:')) return 'buttonText';


    return 'general';
  }

  Map<String, dynamic> _detectVariables(String str) {
    final Set<String> variables = {};
    String template = str;

    // Check for ${} pattern
    final braceMatches = RegExp(r'\$\{([^}]+)\}').allMatches(str);
    for (final match in braceMatches) {
      final varName = match.group(1)!;
      variables.add(varName);
      template = template.replaceAll(match.group(0)!, '{$varName}');
    }

    // Check for $ pattern (ensure it's not part of a longer string or a number)
    final dollarMatches = RegExp(r'(?<![a-zA-Z0-9_])\$([a-zA-Z_][a-zA-Z0-9_]*)\b').allMatches(template);
    for (final match in dollarMatches) {
      final varName = match.group(1)!;
      // Make sure this isn't a false positive for things like "$100"
      if (!RegExp(r'^\d+$').hasMatch(varName)) {
        variables.add(varName);
        template = template.replaceAll(match.group(0)!, '{$varName}');
      }
    }

    return {
      'hasVars': variables.isNotEmpty,
      'variables': variables.toList(),
      'template': template,
    };
  }

  String _generateMethodCall(String className, String keyName, List<String> variables, String context) {
    // Use the class name from the command line argument
    final params = variables.map((v) => '$v').join(', '); // Removed `as String` as it's not always needed and can cause issues
    return '$className.of(context).$keyName($params)';
  }

  String _generateSimpleCall(String className, String keyName, String context) {
    // Use the class name from the command line argument
    return '$className.of(context).$keyName';
  }

  Map<String, Map<String, String>> _generatePlaceholders(List<String> variables) {
    final Map<String, Map<String, String>> placeholders = {};
    for (final variable in variables) {
      placeholders[variable] = {
        'type': 'String',
        'example': variable == 'username' ? 'John' : variable, // Use variable name as example
      };
    }
    return placeholders;
  }

  bool _isImportExportStatement(String content, int position) {
    int lineStart = content.lastIndexOf('\n', position - 1) + 1;
    String linePrefix = content.substring(lineStart, position);

    return linePrefix.startsWith('import ') ||
        linePrefix.startsWith('export ') ||
        linePrefix.startsWith('part ');
  }

  bool _shouldIgnoreString(String str) {
    if (str.length <= 1) return true;
    if (RegExp(r'^\d+\.?\d*$').hasMatch(str)) return true; // Pure numbers
    if (RegExp(r'^[a-zA-Z]$').hasMatch(str)) return true; // Single letters
    if (str.startsWith('http://') || str.startsWith('https://')) return true; // URLs
    if (str.contains('/') && str.split('/').length > 2 && !str.contains(' ')) return true; // File paths like "path/to/file.ext"

    final ignoredPatterns = [
      'assets/', 'fonts/', 'images/', '.png', '.jpg', '.jpeg', '.svg', '.json', '.dart',
      '.com', '.org', '.net', '.io', '.app', 'www.', 'Key(', 'MaterialApp', 'StatelessWidget',
      'StatefulWidget', 'key:', 'const ', 'super.key', 'DateTime.now()', 'Colors.', 'EdgeInsets.',
      'BorderRadius.', 'BoxShadow(', 'FontWeight.', 'TextStyle(', 'IconData(', 'Alignment.',
      'MainAxisAlignment.', 'CrossAxisAlignment.', 'TextDirection.', 'FlexFit.', 'Clip.', 'BlendMode.',
      'BoxFit.', 'FilterQuality.', 'ImageRepeat.', 'Locale(', 'TargetPlatform.', 'Brightness.',
      'ThemeMode.', 'FloatingActionButtonLocation.', 'TextCapitalization.', 'TextInputAction.',
      'TextInputType.', 'Overflow.', 'StackFit.', 'WrapAlignment.', 'WrapCrossAlignment.',
      'VerticalDirection.', 'Axis.', 'BoxShape.', 'BoxBorder.', 'BorderStyle.', 'TableBorder.',
      'TableCellVerticalAlignment.', 'TableRowInkDecoration.', 'HitTestBehavior.', 'MaterialType.',
      'MaterialTapTargetSize.', 'SnackBarBehavior.', 'SnackBarClosedReason.',
      'TooltipTriggerMode.', 'AdaptiveTextSelectionToolbar.buttonItems','print('
    ];

    return ignoredPatterns.any((pattern) => str.contains(pattern));
  }


  String _generateKeyName(String str) {
    // Basic cleaning: remove non-alphanumeric, replace spaces with single underscore
    String cleaned = str
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ') // Replace non-alphanumeric (except spaces) with space
        .trim() // Trim leading/trailing spaces
        .replaceAll(RegExp(r'\s+'), '_'); // Replace multiple spaces with single underscore

    // Convert to camelCase
    List<String> parts = cleaned.split('_');
    String keyName = parts.first.toLowerCase();
    for (int i = 1; i < parts.length; i++) {
      keyName += parts[i][0].toUpperCase() + parts[i].substring(1).toLowerCase();
    }

    // Handle empty or starting with number
    if (keyName.isEmpty || RegExp(r'^\d').hasMatch(keyName)) {
      // Fallback to a generic name, but this should be rare now with improved key generation
      keyName = 'stringKey${_stringCounter++}';
    }

    // Ensure the key is unique among all extracted strings
    // This loop ensures that even if two different raw strings normalize to the same key,
    // they still get unique keys in _extractedStrings.
    String finalName = keyName;
    int counter = 1;
    while (_extractedStrings.containsKey(finalName)) {
      finalName = '${keyName}_$counter';
      counter++;
    }

    return finalName;
  }


  String _addImportIfNeeded(String content, String className) {
    // The import path is 'l10n/generated/app_localizations.dart' by default,
    // where 'app_localizations.dart' is the output-localization-file in l10n.yaml.
    // This file uses the output-class name (e.g., S).
    final importStatement = "import 'package:${Platform.resolvedExecutable.split('/').last.split('\\').first}_package_name/l10n/generated/app_localizations.dart';";
    // dynamic package name, assuming this package is named 'string_extractor_intl'
    // If your package has a different name, replace `string_extractor_intl` below
    // or make it configurable if this tool is used within another package.
    final packageName = 'rental_service'; // Replace with your actual package name

    // Construct the import statement dynamically based on the package name
    final dynamicImportStatement = "import 'package:$packageName/l10n/generated/app_localizations.dart';";


    if (content.contains(dynamicImportStatement)) {
      return content;
    }

    // Find the last import statement
    final lines = content.split('\n');
    int lastImportIndex = -1;

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith('import ')) {
        lastImportIndex = i;
      }
    }

    if (lastImportIndex != -1) {
      lines.insert(lastImportIndex + 1, dynamicImportStatement);
    } else {
      // No imports found, add at the top
      lines.insert(0, dynamicImportStatement);
      lines.insert(1, '');
    }

    return lines.join('\n');
  }

  // Fix: Add MaterialApp localization configuration
  String _addMaterialAppLocalization(String content, String className) {
    // Check if MaterialApp exists and doesn't already have localization config
    if (!content.contains('MaterialApp(')) {
      return content;
    }

    // Check if localization config already exists
    if (content.contains('localizationsDelegates:') || content.contains('supportedLocales:')) {
      return content;
    }

    // Find MaterialApp( and add localization config
    final materialAppPattern = RegExp(r'MaterialApp\s*\(');
    final match = materialAppPattern.firstMatch(content);

    if (match != null) {
      final insertPosition = match.end;
      final beforeInsertion = content.substring(0, insertPosition);
      final afterInsertion = content.substring(insertPosition);

      // Add localization delegates and supported locales using the provided className
      final localizationConfig = '''
      localizationsDelegates: $className.localizationsDelegates,
      supportedLocales: $className.supportedLocales,''';

      return beforeInsertion + localizationConfig + afterInsertion;
    }

    return content;
  }

  Future<void> _runFlutterGenL10n() async {
    try {
      final result = await Process.run('flutter', ['gen-l10n']);

      if (result.exitCode == 0) {
        print('✅ flutter gen-l10n completed successfully');
        if (result.stdout.toString().isNotEmpty) {
          print(result.stdout);
        }
      } else {
        print('⚠️  flutter gen-l10n completed with warnings');
        if (result.stderr.toString().isNotEmpty) {
          print('Error output: ${result.stderr}');
        }
        if (result.stdout.toString().isNotEmpty) {
          print('Standard output: ${result.stdout}');
        }
      }
    } catch (e) {
      print('❌ Failed to run flutter gen-l10n: $e');
      print('Please run "flutter gen-l10n" manually after the process completes.');
    }
  }

  Future<void> _generateArbFile(String outputDirectory, String templateArbFile) async {
    final outputDir = Directory(outputDirectory);
    await outputDir.create(recursive: true);

    final arbFile = File(path.join(outputDirectory, templateArbFile));
    final Map<String, dynamic> arbData = {};

    // Add locale annotation at the beginning
    arbData['@@locale'] = 'en';

    final sortedKeys = _extractedStrings.keys.toList()..sort();

    for (final key in sortedKeys) {
      final stringData = _extractedStrings[key]!;
      arbData[key] = stringData['value'];

      if (stringData['description'] != null) {
        arbData['@$key'] = {
          'description': stringData['description'],
        };

        if (stringData['placeholders'] != null) {
          arbData['@$key']['placeholders'] = stringData['placeholders'];
        }
      }
    }

    const encoder = JsonEncoder.withIndent('  ');
    await arbFile.writeAsString(encoder.convert(arbData));
    print('📄 Generated: ${arbFile.path}');
  }

  Future<void> _generateL10nYaml(String outputDirectory, String className) async {
    final l10nFile = File('l10n.yaml');

    // Always overwrite l10n.yaml to ensure the correct className is set
    // if (l10nFile.existsSync()) {
    //   print('ℹ️  l10n.yaml already exists, skipping generation');
    //   return;
    // }

    final l10nConfig = '''arb-dir: $outputDirectory
template-arb-file: app_en.arb
output-class: $className
output-localization-file: app_localizations.dart
output-dir: $outputDirectory/generated
nullable-getter: false
synthetic-package: false
''';

    await l10nFile.writeAsString(l10nConfig);
    print('📄 Generated: l10n.yaml');
  }
}