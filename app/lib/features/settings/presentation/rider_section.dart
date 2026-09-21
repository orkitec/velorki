import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../recording/data/rider_profile_settings.dart';
import '../../recording/domain/rider_profile.dart';
import '../data/units.dart';

/// Kilograms in a pound, for the weight field on imperial units.
const double kgPerPound = 0.45359237;

/// The weight field, for a test to find it by.
const Key riderWeightFieldKey = Key('rider.weight');

/// The year of birth field, for a test to find it by.
const Key riderBirthYearFieldKey = Key('rider.birthYear');

/// The maximum heart rate field, for a test to find it by.
const Key riderMaxHeartRateFieldKey = Key('rider.maxHeartRate');

/// Settings → Rider: the two estimates a ride page can show, and what the
/// rider has to say about themselves for either to be made.
///
/// The fields only appear once a switch is on: nobody is asked their weight
/// for a figure they never turned on.
class RiderSection extends ConsumerWidget {
  /// Creates the section.
  const RiderSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final profile = ref.watch(riderProfileProvider);
    final controller = ref.read(riderProfileProvider.notifier);
    final system = ref.watch(unitSystemProvider);
    final asked = profile.calories || profile.zones;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          value: profile.calories,
          title: Text(l10n.settingsRiderCalories),
          subtitle: Text(l10n.settingsRiderCaloriesHint),
          onChanged: (value) => unawaited(controller.setCalories(value)),
        ),
        SwitchListTile(
          value: profile.zones,
          title: Text(l10n.settingsRiderZones),
          subtitle: Text(l10n.settingsRiderZonesHint),
          onChanged: (value) => unawaited(controller.setZones(value)),
        ),
        if (asked) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _WeightField(
                    // A new field when the units change, so the number in it
                    // is the one the suffix says.
                    key: ValueKey<UnitSystem>(system),
                    system: system,
                    weightKg: profile.weightKg,
                    onChanged: controller.setWeightKg,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _IntField(
                    fieldKey: riderBirthYearFieldKey,
                    label: l10n.settingsRiderBirthYear,
                    value: profile.birthYear,
                    min: minRiderBirthYear,
                    max: DateTime.now().year,
                    digits: 4,
                    onChanged: controller.setBirthYear,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.settingsRiderSex, style: theme.textTheme.titleSmall),
                const SizedBox(height: 10),
                SegmentedButton<RiderSex>(
                  showSelectedIcon: false,
                  segments: [
                    for (final sex in RiderSex.values)
                      ButtonSegment(
                        value: sex,
                        label: Text(riderSexLabel(l10n, sex)),
                      ),
                  ],
                  selected: {profile.sex},
                  onSelectionChanged: (selection) =>
                      unawaited(controller.setSex(selection.single)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _IntField(
              fieldKey: riderMaxHeartRateFieldKey,
              label: l10n.settingsRiderMaxHeartRate,
              helper: l10n.settingsRiderMaxHeartRateHint,
              suffix: l10n.settingsRiderMaxHeartRateUnit,
              value: profile.maxHeartRateBpm,
              min: minRiderMaxHeartRateBpm,
              max: maxRiderMaxHeartRateBpm,
              digits: 3,
              onChanged: controller.setMaxHeartRate,
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n.settingsRiderPrivacy,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// The localised name of a [RiderSex] choice.
String riderSexLabel(AppLocalizations l10n, RiderSex sex) => switch (sex) {
  RiderSex.unspecified => l10n.riderSexUnspecified,
  RiderSex.female => l10n.riderSexFemale,
  RiderSex.male => l10n.riderSexMale,
};

/// The rider's weight, typed in the rider's own units and stored in
/// kilograms.
class _WeightField extends StatefulWidget {
  const _WeightField({
    required this.system,
    required this.weightKg,
    required this.onChanged,
    super.key,
  });

  final UnitSystem system;
  final double? weightKg;
  final Future<void> Function(double?) onChanged;

  @override
  State<_WeightField> createState() => _WeightFieldState();
}

class _WeightFieldState extends State<_WeightField> {
  late final TextEditingController _controller = TextEditingController(
    text: _display(widget.weightKg),
  );

  double get _kgPerUnit => widget.system == UnitSystem.metric ? 1 : kgPerPound;

  /// The stored weight in the field's units, with the decimal only when it
  /// has one: `75`, not `75.0`.
  String _display(double? kg) {
    if (kg == null) return '';
    final value = (kg / _kgPerUnit * 10).round() / 10;
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      key: riderWeightFieldKey,
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        LengthLimitingTextInputFormatter(5),
      ],
      decoration: InputDecoration(
        labelText: l10n.settingsRiderWeight,
        suffixText: widget.system == UnitSystem.metric
            ? l10n.settingsRiderWeightKg
            : l10n.settingsRiderWeightLb,
        border: const OutlineInputBorder(),
      ),
      // Saved as it is typed, once the number could be a rider: a half-typed
      // "7" is not a rider of seven kilograms. Empty clears the weight.
      onChanged: (value) {
        if (value.trim().isEmpty) {
          unawaited(widget.onChanged(null));
          return;
        }
        final typed = double.tryParse(value.replaceAll(',', '.'));
        if (typed == null) return;
        final kg = typed * _kgPerUnit;
        if (kg < minRiderWeightKg || kg > maxRiderWeightKg) return;
        unawaited(widget.onChanged(kg));
      },
    );
  }
}

/// A whole number the rider types: a year, a heart rate.
class _IntField extends StatefulWidget {
  const _IntField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.digits,
    required this.onChanged,
    this.helper,
    this.suffix,
  });

  /// The key of the text field itself, for a test to find it by.
  final Key fieldKey;

  final String label;
  final String? helper;
  final String? suffix;
  final int? value;
  final int min;
  final int max;
  final int digits;
  final Future<void> Function(int?) onChanged;

  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value?.toString() ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    key: widget.fieldKey,
    controller: _controller,
    keyboardType: TextInputType.number,
    inputFormatters: <TextInputFormatter>[
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(widget.digits),
    ],
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helper,
      helperMaxLines: 2,
      suffixText: widget.suffix,
      border: const OutlineInputBorder(),
    ),
    // Saved as it is typed, once the number is in range; empty clears it.
    onChanged: (value) {
      if (value.trim().isEmpty) {
        unawaited(widget.onChanged(null));
        return;
      }
      final typed = int.tryParse(value);
      if (typed == null || typed < widget.min || typed > widget.max) return;
      unawaited(widget.onChanged(typed));
    },
  );
}
