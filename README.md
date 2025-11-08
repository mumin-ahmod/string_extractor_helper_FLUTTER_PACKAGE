# Flutter String Extractor for Localization

🌍 A powerful command-line tool that automatically extracts hardcoded strings from your Flutter project and generates ARB files for internationalization (i18n) and localization (l10n).

## Features

- 🔍 **Automatically scans** your Flutter project for hardcoded strings
- 📝 **Generates ARB files** with extracted strings
- 📝 **Avoid Duplicates** when extracting
- 🔄 **Replaces hardcoded strings** with localization calls (optional)
- 🛠️ **Auto-configures MaterialApp** with localization delegates
- 📋 **Detects string variables** and creates parameterized localizations
- ⚙️ **Generates l10n.yaml** configuration file
- 🔍 **Dependency checking** ensures required packages are installed
- 🎯 **Smart filtering** ignores URLs, asset paths, and other non-localizable strings

## Installation

Add this package as a dev dependency in your `pubspec.yaml`:

```yaml
dev_dependencies:
  string_extractor_intl: ^1.0.3
```

Then run:
```bash
flutter pub get
```

## Prerequisites

Your Flutter project must have these dependencies in `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  intl: ^0.19.0
```
```
The following section is specific to Flutter packages. for future generation
flutter:
uses-material-design: true
generate: true
```
## Usage

### Basic Usage (Extract Only)

Extract strings and generate ARB files without modifying your source code:

```bash
dart pub run string_extractor_intl:extract_strings
```

### Advanced Usage

**Extract and replace in files:**

```bash
dart run string_extractor_intl:extract_strings --replace
```

**Custom configuration:**

```bash
dart run string_extractor_intl:extract_strings \
  --input lib/presentation \
  --output assets/l10n \
  --template-arb strings_en.arb \
  --class-name MyLocalizations \
  --replace
```

**Show help:**

```bash
dart run string_extractor_intl:extract_strings --help
```

### Command Line Options

| Option | Short | Default            | Description |
|--------|-------|--------------------|-------------|
| `--input` | `-i` | `lib/presentation` | Input directory to scan |
| `--output` | `-o` | `lib/l10n`         | Output directory for localization files |
| `--template-arb` | | `app_en.arb`       | Template ARB file name |
| `--class-name` | `-c` | `AppLocalizations` | Name of the localization class |
| `--replace` | `-r` | `false`            | Replace hardcoded strings with localization calls |
| `--check-deps` | | `true`             | Check for required dependencies |
| `--help` | `-h` |                    | Show usage information |

## ⚠️ Suggestion: run the extraction on the Presentation folder only to avoid taking unnecessary strings with: 
```
dart pub run string_extractor_intl:extract_strings \ --input lib/presentation \
```
## ⚠️ CAUTION: Before Running with --replace Flag

**READ THIS CAREFULLY BEFORE USING THE `--replace` OPTION:**

### **🚨 MANDATORY BACKUP**
- **ALWAYS create a backup** of your project before running with `--replace`
- **Commit your changes to Git** or **copy your entire project folder**
- The tool will **modify multiple files** in your project automatically
- **There is no undo feature** - you'll need your backup to revert changes

### **📖 READ INSTRUCTIONS THOROUGHLY**
- **Read this entire README** before using the replacement feature
- **Test the tool on a small project first** to understand how it works
- **Review the generated code** after replacement to ensure it meets your needs

### **🔧 POST-REPLACEMENT REQUIREMENTS**
After running with `--replace`, you **MUST** run these commands:

```bash
# Install/update dependencies
flutter pub get

# Generate localization files
flutter gen-l10n
```

### **⚠️ IMPORTANT WARNINGS before using --replace**
- **Review all changes** before committing to version control
- **Test your app thoroughly** after replacement
- **Some strings may need manual adjustment** after automatic replacement
- **Variables in strings** will be converted to parameterized localizations
- **MaterialApp will be automatically configured** with localization delegates

## How It Works

### 1. String Detection
The tool scans your Dart files and identifies hardcoded strings, excluding:
- Import/export statements
- Asset paths and URLs
- File extensions
- Widget class names
- Single characters and numbers

### 2. Variable Detection
Automatically detects variables in strings:
- `"Hello $_name"` → `S.of(context).hello('$_name')`
- `"Count: ${count}"` → `S.of(context).count('$count')`

### 3. ARB File Generation
Creates structured ARB files with:
- Proper locale annotations
- Parameter definitions for variables
- Descriptive comments
- Sorted keys for consistency

### 4. Code Replacement (Optional)
When using `--replace`:
- Replaces hardcoded strings with localization calls
- Adds necessary import statements
- Configures MaterialApp with localization delegates
- Preserves variable references in parameterized strings

## Example

### Before
```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My App',
      home: Scaffold(
        appBar: AppBar(title: Text('Welcome')),
        body: Text('Hello $_username!'),
      ),
    );
  }
}
```

### After (with --replace)
```dart
import 'l10n/generated/app_localizations.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      title: S.of(context).myApp,
      home: Scaffold(
        appBar: AppBar(title: Text(S.of(context).welcome)),
        body: Text(S.of(context).hello('$_username')),
      ),
    );
  }
}
```

### Generated ARB File (app_en.arb)
```json
{
  "@@locale": "en",
  "hello": "Hello {username}!",
  "@hello": {
    "description": "Localized string with parameters: username",
    "placeholders": {
      "username": {
        "type": "String",
        "example": "John"
      }
    }
  },
  "myApp": "My App",
  "@myApp": {
    "description": "Localized string"
  },
  "welcome": "Welcome",
  "@welcome": {
    "description": "Localized string"
  }
}
```

## Generated Files

The tool creates several files:

1. **ARB File** (`lib/l10n/app_en.arb`) - Contains extracted strings
2. **l10n.yaml** - Configuration for Flutter's localization generator
3. **Modified Dart files** - Updated with localization calls (if using `--replace`)

## Next Steps After Generation

1. **Add additional language ARB files**:
   ```
   lib/l10n/app_es.arb  (Spanish)
   lib/l10n/app_fr.arb  (French)
   lib/l10n/app_de.arb  (German)
   ```

2. **Run Flutter's localization generator**:
   ```bash
   flutter gen-l10n
   ```

3. **Import and use in your app**:
   ```dart
   import 'l10n/generated/app_localizations.dart';
   
   // In your MaterialApp
   MaterialApp(
     localizationsDelegates: S.localizationsDelegates,
     supportedLocales: S.supportedLocales,
     // ...
   )
   ```
For more details, read [this article](https://mumin-ahmod.medium.com/flutter-string-extractor-package-from-hardcoded-strings-to-i18n-in-minutes-automate-flutter-187dc3ce33a5).

## Troubleshooting

### Common Issues

**"pubspec.yaml not found"**
- Ensure you're running the command from your Flutter project root

**"Missing required dependencies"**
- Add `intl` and `flutter_localizations` to your `pubspec.yaml`
- Run `flutter pub get`

**Generated strings not accessible**
- Run `flutter gen-l10n` after generating ARB files
- Check that `l10n.yaml` exists in your project root

**Compilation errors after replacement**
- Ensure you ran `flutter pub get` and `flutter gen-l10n`
- Check that imports were added correctly
- Review replaced strings for accuracy

### Best Practices

- **Start with extraction only** (without `--replace`) to review strings
- **Test on a copy** of your project first
- **Review generated ARB files** before adding translations
- **Use meaningful string content** for better key generation
- **Keep backups** when using the replacement feature

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

If you encounter any issues or have questions:
1. Check the troubleshooting section above
2. Search existing issues on GitHub
3. Create a new issue with detailed information about your problem

---

**Happy Localizing! 🌍**