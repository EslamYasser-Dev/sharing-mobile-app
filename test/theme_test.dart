import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplefileshare/src/state/theme_controller.dart';
import 'package:simplefileshare/src/theme.dart';

void main() {
  group('themeModeFromStorage', () {
    test('maps the persisted names', () {
      expect(themeModeFromStorage('light'), ThemeMode.light);
      expect(themeModeFromStorage('dark'), ThemeMode.dark);
    });

    test('unknown or missing values follow the system', () {
      expect(themeModeFromStorage(null), ThemeMode.system);
      expect(themeModeFromStorage('system'), ThemeMode.system);
      expect(themeModeFromStorage('solarized'), ThemeMode.system);
    });

    test('names round-trip through ThemeMode.name', () {
      for (final mode in ThemeMode.values) {
        expect(themeModeFromStorage(mode.name), mode);
      }
    });
  });

  group('buildAppTheme', () {
    test('attaches a matching palette for each brightness', () {
      final light = buildAppTheme(Brightness.light);
      final dark = buildAppTheme(Brightness.dark);

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.extension<SfsPalette>(), SfsPalette.light);
      expect(dark.extension<SfsPalette>(), SfsPalette.dark);
    });

    testWidgets('falls back to the dark palette when none is attached', (
      tester,
    ) async {
      SfsPalette? captured;
      await tester.pumpWidget(
        Theme(
          data: ThemeData(),
          child: Builder(
            builder: (context) {
              captured = SfsPalette.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(captured, SfsPalette.dark);
    });
  });

  group('palettes', () {
    test('light and dark actually differ', () {
      expect(SfsPalette.light.background, isNot(SfsPalette.dark.background));
      expect(SfsPalette.light.text, isNot(SfsPalette.dark.text));
      expect(SfsPalette.light.accent, isNot(SfsPalette.dark.accent));
    });

    test('ink on the accent fill stays legible on both', () {
      // White reads on the light palette's blue accent; the dark palette's
      // tan is far too light for white ink, so it flips to near-black.
      expect(SfsPalette.light.onAccent, Colors.white);
      expect(
        SfsPalette.dark.onAccent.computeLuminance(),
        lessThan(SfsPalette.dark.accent.computeLuminance()),
      );
    });
  });
}
