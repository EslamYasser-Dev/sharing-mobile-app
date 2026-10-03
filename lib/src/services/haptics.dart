import 'package:flutter/services.dart';

/// Tactile accents for the glass UI. Fire-and-forget: haptics never block,
/// and on devices without a vibrator these are silent no-ops.
void sfsTap() {
  HapticFeedback.selectionClick();
}

void sfsConfirm() {
  HapticFeedback.mediumImpact();
}

void sfsToggle(bool on) {
  if (on) {
    HapticFeedback.lightImpact();
  } else {
    HapticFeedback.mediumImpact();
  }
}

void sfsError() {
  HapticFeedback.heavyImpact();
}
