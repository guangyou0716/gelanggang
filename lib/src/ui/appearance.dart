import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light, dark, or whatever the device uses.
enum Appearance {
  device('device', ThemeMode.system),
  light('light', ThemeMode.light),
  dark('dark', ThemeMode.dark);

  const Appearance(this.code, this.mode);

  /// How the choice is saved.
  final String code;

  final ThemeMode mode;

  /// A code the app does not know (or none) means "follow the device".
  static Appearance fromCode(String? code) {
    for (final a in values) {
      if (a.code == code) return a;
    }
    return device;
  }
}

/// Where the appearance choice is kept: apart from the data, like the
/// language, so a backup or restore never changes it.
abstract interface class AppearanceStorage {
  Future<String?> read();

  Future<void> write(String code);
}

class MemoryAppearanceStorage implements AppearanceStorage {
  MemoryAppearanceStorage([this.code]);

  String? code;

  @override
  Future<String?> read() async => code;

  @override
  Future<void> write(String value) async => code = value;
}

class DeviceAppearanceStorage implements AppearanceStorage {
  static const _key = 'gelanggang.appearance';

  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    // Something other than a string under the key (written by a future or
    // broken version) counts as no choice rather than crashing the launch.
    final value = prefs.get(_key);
    return value is String ? value : null;
  }

  @override
  Future<void> write(String code) async =>
      (await SharedPreferences.getInstance()).setString(_key, code);
}

/// The organiser's light/dark choice (default: follow the device).
class AppearanceSetting extends ChangeNotifier {
  AppearanceSetting(this._storage);

  final AppearanceStorage _storage;
  Appearance _chosen = Appearance.device;

  Appearance get chosen => _chosen;

  Future<void> load() async {
    _chosen = Appearance.fromCode(await _storage.read());
    notifyListeners();
  }

  Future<void> choose(Appearance appearance) async {
    _chosen = appearance;
    notifyListeners();
    await _storage.write(appearance.code);
  }
}

const _seed = Color(0xFF0F766E);

/// The app's look for [brightness]: the same teal seed in both, so light
/// and dark read as one app.
ThemeData gelanggangTheme(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
);
