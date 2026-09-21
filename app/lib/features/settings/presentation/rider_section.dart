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

/// The bike weight field, for a test to find it by.
const Key riderBikeWeightFieldKey = Key('rider.bikeWeight');

/// The threshold power field, for a test to find it by.
const Key riderThresholdPowerFieldKey = Key('rider.thresholdPower');

/// Settings → Rider: the figures a ride page can show beyond what was
/// measured, and what the rider has to say about themselves for any of them
/// to be made.
///
/// The fields only appear once a switch is on: nobody is asked their weight
/// for a figure they never turned on, nobody is asked about their bike unless
/// the power estimate is on, and the power zones ask for the threshold power
/// alone.
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
    final asked = profile.calories || profile.zones || profile.estimatePower;
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
        SwitchListTile(
          value: profile.estimatePower,
          title: Text(l10n.settingsRiderEstimatePower),
          subtitle: Text(l10n.settingsRiderEstimatePowerHint),
          onChanged: (value) => unawaited(controller.setEstimatePower(value)),
        ),
        SwitchListTile(
          value: profile.powerZones,
          title: Text(l10n.settingsRiderPowerZones),
          subtitle: Text(l10n.settingsRiderPowerZonesHint),
          onChanged: (value) => unawaited(controller.setPowerZones(value)),
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
                    fieldKey: riderWeightFieldKey,
                    label: l10n.settingsRiderWeight,
                    system: system,
                    weightKg: profile.weightKg,
                    minKg: minRiderWeightKg,
                    maxKg: maxRiderWeightKg,
                    onChanged: controller.setWeightKg,
                    helper: l10n.settingsRiderWeightHint,
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
        if (profile.estimatePower) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _WeightField(
              key: ValueKey<String>('bike-${system.name}'),
              fieldKey: riderBikeWeightFieldKey,
              label: l10n.settingsRiderBikeWeight,
              system: system,
              weightKg: profile.bikeWeightKg,
              minKg: minBikeWeightKg,
              maxKg: maxBikeWeightKg,
              onChanged: controller.setBikeWeightKg,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.settingsRiderBike, style: theme.textTheme.titleSmall),
                const SizedBox(height: 10),
                SegmentedButton<RiderBike>(
                  showSelectedIcon: false,
                  segments: [
                    for (final bike in RiderBike.values)
                      ButtonSegment(
                        value: bike,
                        label: Text(riderBikeLabel(l10n, bike)),
                      ),
                  ],
                  selected: {profile.bike},
                  onSelectionChanged: (selection) =>
                      unawaited(controller.setBike(selection.single)),
                ),
              ],
            ),
          ),
        ],
        if (profile.powerZones)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _IntField(
              fieldKey: riderThresholdPowerFieldKey,
              label: l10n.settingsRiderThresholdPower,
              suffix: l10n.settingsRiderThresholdPowerUnit,
              value: profile.thresholdPowerW,
              min: minRiderThresholdPowerW,
              max: maxRiderThresholdPowerW,
              digits: 3,
              onChanged: controller.setThresholdPower,
              helper: l10n.settingsRiderThresholdPowerHint,
            ),
          ),
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

/// The localised name of a [RiderBike] choice.
String riderBikeLabel(AppLocalizations l10n, RiderBike bike) => switch (bike) {
  RiderBike.road => l10n.riderBikeRoad,
  RiderBike.touring => l10n.riderBikeTouring,
  RiderBike.mountain => l10n.riderBikeMountain,
};

/// A weight, the rider's or the bike's, typed in the rider's own units and
/// stored in kilograms.
class _WeightField extends StatefulWidget {
  const _WeightField({
    required this.fieldKey,
    required this.label,
    required this.system,
    required this.weightKg,
    required this.minKg,
    required this.maxKg,
    required this.onChanged,
    this.helper,
    super.key,
  });

  /// The key of the text field itself, for a test to find it by.
  final Key fieldKey;

  final String label;
  final UnitSystem system;
  final double? weightKg;
  final double minKg;
  final double maxKg;
  final Future<void> Function(double?) onChanged;

  /// A line under the field, or nothing.
  final String? helper;

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
      key: widget.fieldKey,
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        LengthLimitingTextInputFormatter(5),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.system == UnitSystem.metric
            ? l10n.settingsRiderWeightKg
            : l10n.settingsRiderWeightLb,
        helperText: widget.helper,
        helperMaxLines: 4,
        border: const OutlineInputBorder(),
      ),
      // Saved as it is typed, once the number could be a rider or a bike: a
      // half-typed "7" is not a rider of seven kilograms. Empty clears the
      // weight.
      onChanged: (value) {
        if (value.trim().isEmpty) {
          unawaited(widget.onChanged(null));
          return;
        }
        final typed = double.tryParse(value.replaceAll(',', '.'));
        if (typed == null) return;
        final kg = typed * _kgPerUnit;
        if (kg < widget.minKg || kg > widget.maxKg) return;
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
      helperMaxLines: 4,
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
