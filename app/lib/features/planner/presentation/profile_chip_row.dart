import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';
import '../domain/route_profile.dart';
import 'route_format.dart';

/// The five routing profiles as one row of chips that shares the width it
/// is given, a fifth each, so it lines up with the chrome around it and
/// never scrolls sideways.
///
/// Tight chip padding keeps the longest label inside its fifth on a 360 dp
/// phone, and a label that is longer in another language shrinks into its
/// fifth rather than ending in an ellipsis: German "Trekking" and "Rennrad"
/// do not fit at 360 dp otherwise.
///
/// Over the map ([glass]) the chips are chrome, so they are opaque glass
/// whatever the chip theme says; on a sheet, which is a surface already, the
/// chip theme's fills are left alone. The label colour is set here in both
/// cases, from the same scheme as the fill: a label style without one kept
/// the text theme's own colour, white in the dark theme, on the accent.
class ProfileChipRow extends StatelessWidget {
  /// Creates the row.
  const ProfileChipRow({
    required this.selected,
    required this.onSelected,
    this.glass = false,
    super.key,
  });

  /// The profile that is on.
  final RouteProfile selected;

  /// Called with the profile the rider tapped.
  final ValueChanged<RouteProfile> onSelected;

  /// Whether the row floats over the map and needs opaque chips.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profiles = RouteProfile.values;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          for (final (index, profile) in profiles.indexed)
            Expanded(
              child: Padding(
                // Gaps between the chips only, so the first and the last
                // sit flush with the edges of whatever is above.
                padding: EdgeInsets.only(
                  right: index == profiles.length - 1 ? 0 : 6,
                ),
                child: ChoiceChip(
                  label: SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        profileLabel(l10n, profile),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                      ),
                    ),
                  ),
                  selected: profile == selected,
                  onSelected: (_) => onSelected(profile),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  labelPadding: EdgeInsets.zero,
                  backgroundColor: glass ? theme.velorki.glass : null,
                  selectedColor: glass ? scheme.primary : null,
                  side: glass
                      ? BorderSide(
                          color: profile == selected
                              ? scheme.primary
                              : theme.velorki.glassBorder,
                        )
                      : null,
                  labelStyle: theme.textTheme.labelLarge?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: profile == selected
                        ? scheme.onPrimary
                        : scheme.onSurface,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The routing profile as one button beside the search field, for a phone
/// turned sideways: the chips' row would take a height the map cannot spare
/// there. It shows the profile that is on and opens the five as a menu.
class ProfileDropdown extends StatelessWidget {
  /// Creates the button.
  const ProfileDropdown({
    required this.selected,
    required this.onSelected,
    this.dense = false,
    super.key,
  });

  /// Lower than the search field: for a row of its own under it, where its
  /// height is the chrome's.
  final bool dense;

  /// The profile that is on.
  final RouteProfile selected;

  /// Called with the profile the rider picked.
  final ValueChanged<RouteProfile> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      menuChildren: [
        for (final profile in RouteProfile.values)
          MenuItemButton(
            leadingIcon: Icon(
              Icons.check_rounded,
              color: profile == selected ? scheme.primary : Colors.transparent,
            ),
            onPressed: () => onSelected(profile),
            child: Text(profileLabel(l10n, profile)),
          ),
      ],
      builder: (context, menu, _) => GlassPanel(
        radius: 28,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            child: Padding(
              padding: dense
                  ? const EdgeInsets.fromLTRB(16, 8, 10, 8)
                  : const EdgeInsets.fromLTRB(20, 16, 14, 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    profileLabel(l10n, selected),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more_rounded, color: scheme.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
