import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings.dart';

export 'strings.dart';

/// Where the organiser's language choice is kept (apart from the data, so a
/// backup or restore never changes it).
abstract interface class LanguageStorage {
  Future<String?> read();

  /// Null forgets the choice (follow the device again).
  Future<void> write(String? code);
}

class MemoryLanguageStorage implements LanguageStorage {
  MemoryLanguageStorage([this.code]);

  String? code;

  @override
  Future<String?> read() async => code;

  @override
  Future<void> write(String? value) async => code = value;
}

class DeviceLanguageStorage implements LanguageStorage {
  static const _key = 'gelanggang.language';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String? code) async {
    final prefs = await SharedPreferences.getInstance();
    if (code == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, code);
    }
  }
}

/// The language the organiser picked, or null to follow the device.
class LanguageSetting extends ChangeNotifier {
  LanguageSetting(this._storage);

  final LanguageStorage _storage;
  AppLanguage? _chosen;

  AppLanguage? get chosen => _chosen;

  /// A saved code the app no longer knows counts as no choice.
  Future<void> load() async {
    _chosen = AppLanguage.fromCode(await _storage.read());
    notifyListeners();
  }

  Future<void> choose(AppLanguage? language) async {
    _chosen = language;
    notifyListeners();
    await _storage.write(language?.code);
  }
}

const supportedLocales = [Locale('en'), Locale('ms'), Locale('zh')];

/// The language for the device's preferred [locales]: the first one the app
/// has, else English.
AppLanguage languageForDevice(Iterable<Locale>? locales) {
  for (final l in locales ?? const <Locale>[]) {
    final found = AppLanguage.fromCode(l.languageCode);
    if (found != null) return found;
  }
  return AppLanguage.en;
}

class StringsDelegate extends LocalizationsDelegate<Strings> {
  const StringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLanguage.fromCode(locale.languageCode) != null;

  @override
  Future<Strings> load(Locale locale) => SynchronousFuture(
    Strings(AppLanguage.fromCode(locale.languageCode) ?? AppLanguage.en),
  );

  @override
  bool shouldReload(StringsDelegate old) => false;
}

extension StringsOf on BuildContext {
  /// The texts in the app's current language.
  Strings get s => Localizations.of<Strings>(this, Strings) ?? Strings.en;
}
