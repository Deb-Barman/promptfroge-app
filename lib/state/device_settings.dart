import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-device preferences (theme, scale, editor look). Stored in SharedPreferences,
/// not in the vault, because they belong to the device rather than the notes.
class DeviceSettings {
  final ThemeMode themeMode;
  final double uiScale; // 0.85 .. 1.3
  final double editorFontSize;
  final String editorFont;
  final int autosaveMs;
  final bool lineNumbers;
  final bool wordWrap;
  final bool highlight;

  /// Spaces inserted per Tab key / indent action in the editor.
  final int tabWidth;

  /// compact | relaxed
  final String lineHeight;

  /// Show a warning bar when a prompt grows past this many words (0 = off).
  final int wordCountWarning;

  /// Show type-ahead suggestions (snippets, variables, phrases learned from your prompts) while typing.
  final bool suggestionsEnabled;

  /// Re-run the analyzer live while typing (off: only when you open the Analyze tab).
  final bool analyzerLive;

  /// First-run welcome has been shown.
  final bool onboardingSeen;

  const DeviceSettings({
    this.themeMode = ThemeMode.dark,
    this.uiScale = 1.0,
    this.editorFontSize = 14,
    this.editorFont = 'jetbrains',
    this.autosaveMs = 900,
    this.lineNumbers = true,
    this.wordWrap = true,
    this.highlight = true,
    this.tabWidth = 2,
    this.lineHeight = 'relaxed',
    this.wordCountWarning = 0,
    this.suggestionsEnabled = true,
    this.analyzerLive = true,
    this.onboardingSeen = false,
  });

  DeviceSettings copyWith({
    ThemeMode? themeMode,
    double? uiScale,
    double? editorFontSize,
    String? editorFont,
    int? autosaveMs,
    bool? lineNumbers,
    bool? wordWrap,
    bool? highlight,
    int? tabWidth,
    String? lineHeight,
    int? wordCountWarning,
    bool? suggestionsEnabled,
    bool? analyzerLive,
    bool? onboardingSeen,
  }) =>
      DeviceSettings(
        themeMode: themeMode ?? this.themeMode,
        uiScale: uiScale ?? this.uiScale,
        editorFontSize: editorFontSize ?? this.editorFontSize,
        editorFont: editorFont ?? this.editorFont,
        autosaveMs: autosaveMs ?? this.autosaveMs,
        lineNumbers: lineNumbers ?? this.lineNumbers,
        wordWrap: wordWrap ?? this.wordWrap,
        highlight: highlight ?? this.highlight,
        tabWidth: tabWidth ?? this.tabWidth,
        lineHeight: lineHeight ?? this.lineHeight,
        wordCountWarning: wordCountWarning ?? this.wordCountWarning,
        suggestionsEnabled: suggestionsEnabled ?? this.suggestionsEnabled,
        analyzerLive: analyzerLive ?? this.analyzerLive,
        onboardingSeen: onboardingSeen ?? this.onboardingSeen,
      );
}

final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('sharedPrefsProvider must be overridden in main()'));

class DeviceSettingsNotifier extends Notifier<DeviceSettings> {
  late SharedPreferences _prefs;

  @override
  DeviceSettings build() {
    _prefs = ref.read(sharedPrefsProvider);
    final theme = _prefs.getString('theme') ?? 'dark';
    return DeviceSettings(
      themeMode: theme == 'light' ? ThemeMode.light : (theme == 'system' ? ThemeMode.system : ThemeMode.dark),
      uiScale: _prefs.getDouble('uiScale') ?? 1.0,
      editorFontSize: _prefs.getDouble('editorFontSize') ?? 14,
      editorFont: _prefs.getString('editorFont') ?? 'jetbrains',
      autosaveMs: _prefs.getInt('autosaveMs') ?? 900,
      lineNumbers: _prefs.getBool('lineNumbers') ?? true,
      wordWrap: _prefs.getBool('wordWrap') ?? true,
      highlight: _prefs.getBool('highlight') ?? true,
      tabWidth: _prefs.getInt('tabWidth') ?? 2,
      lineHeight: _prefs.getString('lineHeight') ?? 'relaxed',
      wordCountWarning: _prefs.getInt('wordCountWarning') ?? 0,
      suggestionsEnabled: _prefs.getBool('suggestionsEnabled') ?? true,
      analyzerLive: _prefs.getBool('analyzerLive') ?? true,
      onboardingSeen: _prefs.getBool('onboardingSeen') ?? false,
    );
  }

  void update(DeviceSettings s) {
    state = s;
    _prefs.setString('theme', s.themeMode == ThemeMode.light ? 'light' : (s.themeMode == ThemeMode.system ? 'system' : 'dark'));
    _prefs.setDouble('uiScale', s.uiScale);
    _prefs.setDouble('editorFontSize', s.editorFontSize);
    _prefs.setString('editorFont', s.editorFont);
    _prefs.setInt('autosaveMs', s.autosaveMs);
    _prefs.setBool('lineNumbers', s.lineNumbers);
    _prefs.setBool('wordWrap', s.wordWrap);
    _prefs.setBool('highlight', s.highlight);
    _prefs.setInt('tabWidth', s.tabWidth);
    _prefs.setString('lineHeight', s.lineHeight);
    _prefs.setInt('wordCountWarning', s.wordCountWarning);
    _prefs.setBool('suggestionsEnabled', s.suggestionsEnabled);
    _prefs.setBool('analyzerLive', s.analyzerLive);
    _prefs.setBool('onboardingSeen', s.onboardingSeen);
  }
}

final deviceSettingsProvider = NotifierProvider<DeviceSettingsNotifier, DeviceSettings>(DeviceSettingsNotifier.new);
