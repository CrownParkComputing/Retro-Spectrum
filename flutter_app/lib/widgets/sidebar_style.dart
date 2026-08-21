import 'sidebar.dart';
import '../theme/spectrum_theme.dart';

/// The Spectrum front end's rail palette. This adapter is the only per-app part of
/// the side nav -- widgets/sidebar.dart itself is identical in every Retro-*
/// app, so a fix there lands everywhere instead of once.
double _maxWidth(double screenWidth) => 180.0;

const SidebarStyle spectrumSidebarStyle = SidebarStyle(
  panelFill: SpectrumColors.panelFill,
  panelStroke: SpectrumColors.panelStroke,
  selectedFill: SpectrumColors.tabSelected,
  selectedStroke: SpectrumColors.tabSelectedBorder,
  labelIdle: SpectrumColors.sidebarLabelIdle,
  labelSelected: SpectrumColors.sidebarLabelSelected,
  minWidth: SpectrumMetrics.sidebarMinWidth,
  buttonHeight: SpectrumMetrics.sidebarButtonHeight,
  buttonTextSize: SpectrumMetrics.sidebarButtonTextSize,
  buttonBottomMargin: SpectrumMetrics.sidebarBottomMargin,
  buttonSidePadding: SpectrumMetrics.sidebarButtonSidePadding,
  buttonVerticalPadding: SpectrumMetrics.sidebarButtonVerticalPadding,
  navPadding: SpectrumMetrics.sideNavPadding,
  maxWidth: _maxWidth,
);
