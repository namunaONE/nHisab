# 05 - Design System (Fidelity + Components)

Seeds: Primary #002C6D navy depth, Secondary #4FD166 growth green.
Implementation: `app/lib/src/core/theme/app_theme.dart` via `ColorScheme.fromSeed`, `useMaterial3: true`, no dynamic color. Gap: textTheme, cardTheme, button themes not customized yet, defaults in use.

## 1. Color Roles - How It Works
M3 generates tonal palettes 0-100 from seeds. Light primary ~tone 40 navy, dark primary ~tone 80 light blue. Fixed roles stay same across modes. Surfaces replace elevation overlays. Every onX needs 4.5:1 vs base.

Mapping:
- primary #002C6D: AppBar bg, table header bg, Total text, nav active. onPrimary #FFFFFF.
- primaryContainer ~#D8E2F3 generated: selected row, filter chip. onPrimaryContainer #001D4B.
- primaryFixed/Dim: stable chip for BS pill and status that must not flip light/dark.
- secondary #4FD166: Record Payment CTA, Amount Paid, success badge. onSecondary must be dark #00210A - white fails contrast on this green, verify with checker.
- secondaryContainer light green tint: paid pills. tertiary generated only: info hints.
- surface set: surface app bg, surfaceContainerLow/Lowest cards, surfaceContainer/High header + totals footer, surfaceContainerHighest dialogs, surfaceDim darkest, surfaceBright lightest.
- outline table outer, outlineVariant grid lines/dividers 3:1 not required.
- error #BA1A1A + onError + errorContainer: Dues, overdue, validation. Never green for dues, never error for info.
- inverseSurface/onInverseSurface/inversePrimary: snackbar payment saved, tooltips.
- scrim modal dim, shadow elevation, surfaceTint overlay indicator.

Guidelines: roles not hex except seeds. One CTA per screen in secondary. Secondary actions text buttons in primary. Destructive archive uses error text button with confirm dialog.

## 2. Typography - 15 M3 Roles
M3 scale: displayLarge/Medium/Small, headlineLarge/Medium/Small, titleLarge/Medium/Small, bodyLarge/Medium/Small, labelLarge/Medium/Small + 2025 emphasized variants for highlighted moments. Flutter exposes via ThemeData.textTheme, read via TextTheme.of(context), honors textScaleFactor automatically. Do not hardcode TextStyle sizes.

nHisab mapping:
- titleLarge bold primary: portfolio totals footer e.g. 99,60,000.00.
- titleMedium: page titles Ledger/Parties.
- bodyMedium tabular: ledger cells, right-aligned numerics. Use fontFeatures tabular figures where available.
- bodySmall onSurfaceVariant: Remarks, address subtitles.
- labelSmall tertiary pill: dual date AD | BS.
- labelLarge: button labels 5 M3 sizes default 40dp height, fully rounded.

Rules: system font for functional UI buttons/inputs/status for OS alignment and performance, reserve brand weight for display/headline only. Support 200% text scale without overflow - test ledger horizontal scroll minWidth 1400 + wrap filter row. Never truncate amounts, allow scroll.

## 3. Buttons
M3 types: Elevated, Filled, FilledTonal, Outlined, Text + IconButton, SegmentedButton, FAB small/regular/extended. M3 default 40dp tall fully rounded, icons 20dp leading/trailing sharing label color. Neutral text button not recommended.

nHisab:
- FilledButton secondary green dark text: Record Payment, Seed 21 rows.
- ElevatedButton primary: Change Today.
- OutlinedButton: Set 2026-10-15, Export/Import.
- TextButton: Cancel, Pick date.
- SegmentedButton: Lent/Borrowed toggle.
- FAB stack on Ledger: small person_add + add_card + regular add payment, distinct heroTag.
- IconButton 18-20dp: archive/delete with tooltip, confirm before destructive.

Rules: one primary action per dialog Save loan/Save payment, disable while busy with Please wait label, show inline error in error color, not snackbar for form errors.

## 4. Cards, Dialogs, Sheets
M3 cards: Elevated, Filled, Outlined. Prefer Outlined for dense financial lists, simpler than Elevated. Shape via theme shape parameter, reference Theme.of(context).cardTheme.shape, do not hardcode per card.

nHisab: login Card maxWidth 400 centered, party/loan/payment AlertDialog width 400-480 with SingleChildScrollView for small screens, bottom NavigationBar 4 destinations, DataTable2 header primary/onPrimary white bold, footer surfaceContainerHigh bold.

Rules: dialogs dismissible Cancel, destructive needs explicit Archive confirm. Sheets 16dp radius, cells 4dp, cards 8dp. Avoid RenderFlex overflow: Expanded + ListView or SingleChildScrollView in dialogs, tested on small phones.

## 5. Iconography and Symbols
M3 default is Material Symbols, Flutter commonly uses Material Icons via cupertino_icons + material Icons class. Standard leading/trailing 20dp. Use semantic icons: table_chart ledger, people parties, payments payments, upload import, person_add/add_card/add forms, archive_outlined soft delete, account_circle user menu.

Rules: icon + label share color from role, 20dp standard, tooltip every IconButton, never icon-only destructive without confirm. When migrating to Symbols, update pubspec + font, keep names stable.

## 6. Themes Light/Dark + Assets
ThemeData light + dark from same seeds, MaterialApp theme/darkTheme/themeMode.system. ColorScheme.of(context) resolves per mode. Dark: navy text becomes light tint, never #002C6D on black.

Assets: flutter uses-material-design true, tree-shaking verified 99% icon reduction in build. Images via excel/pdf/printing only now. Future: place under assets/images with variants per density, declare in pubspec, use asset-from-package rules. No custom fonts yet, add only for display roles with fontFamilyFallback.

## 7. Verification Checklist
- [ ] Customize textTheme, cardTheme outlined, button shapes in app_theme.dart.
- [ ] Contrast check onSecondary vs #4FD166 record result.
- [ ] 200% text scale pass on ledger + dialogs.
- [ ] Dark mode screenshot review for navy-on-black violations.
- [ ] Migrate Icons to Symbols when stable in material_ui decoupling.
