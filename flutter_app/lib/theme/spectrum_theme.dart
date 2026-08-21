// spectrum_theme.dart — Retro-Spectrum colour palette + metrics.
// The ZX-Spectrum's own brand colour is the cyan/magenta/yellow/black
// palette the boot screen paints with, so the launcher sits in that
// neighbourhood (a cool dark blue with hot accent edges) rather than
// the chrome-blue of the Saturn or the muted grey of the C64.

import 'package:flutter/material.dart';

class SpectrumColors {
  static const Color rootBackground = Color(0xFF0A0E16);
  static const Color panelFill = Color(0xFF11151F);
  static const Color panelStroke = Color(0xFF1E2433);
  static const Color sectionLabel = Color(0xFF9AA4B7);
  static const Color sidebarLabelIdle = Color(0xFF9AA4B7);
  static const Color sidebarLabelSelected = Color(0xFFE5E9F0);
  static const Color tabSelected = Color(0xFF50E3C2);
  static const Color tabSelectedBorder = Color(0xFF50E3C2);
}

class SpectrumMetrics {
  static const double sidebarMinWidth = 90.0;
  static const double sidebarMaxWidth = 180.0;
  static const double sidebarButtonHeight = 36.0;
  static const double sidebarButtonTextSize = 12.0;
  static const double sidebarBottomMargin = 4.0;
  static const double sidebarButtonSidePadding = 8.0;
  static const double sidebarButtonVerticalPadding = 6.0;
  static const double sideNavPadding = 10.0;
}
