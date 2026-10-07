import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/links/link_opener.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/opening_hours.dart';
import '../domain/osm_place_details.dart';

/// The clock the opening status is told against. Overridden in tests.
final placeDetailsClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The rows of a place's OpenStreetMap details, each with its icon in the
/// card's icon column.
class PlaceDetailsView extends ConsumerWidget {
  /// Creates the rows for [details].
  const PlaceDetailsView({required this.details, super.key});

  /// What OpenStreetMap knows about the place.
  final OsmPlaceDetails details;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (details.isEmpty) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(start: 36),
        child: Text(
          l10n.placeDetailsNone,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    void open(Uri url) => unawaited(ref.read(linkOpenerProvider)(url));
    final hours = details.openingHours;
    final website = details.website;
    final phone = details.phone;
    final phoneUri = details.phoneUri;
    final wikipedia = details.wikipedia;
    final wheelchair = details.wheelchair;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hours != null)
          _Row(
            icon: Icons.schedule_rounded,
            child: _OpeningHoursText(
              raw: hours,
              now: ref.watch(placeDetailsClockProvider)(),
            ),
          ),
        if (website != null)
          _Row(
            icon: Icons.language_rounded,
            child: _LinkText(_websiteLabel(website), () => open(website)),
          ),
        if (phone != null)
          _Row(
            icon: Icons.phone_outlined,
            child: phoneUri == null
                ? Text(phone)
                : _LinkText(phone, () => open(phoneUri)),
          ),
        if (details.cuisines.isNotEmpty)
          _Row(
            icon: Icons.restaurant_outlined,
            child: Text(l10n.placeDetailsCuisine(details.cuisines.join(', '))),
          ),
        if (wheelchair != null)
          _Row(
            icon: Icons.accessible_rounded,
            child: Text(switch (wheelchair) {
              WheelchairAccess.yes => l10n.placeDetailsWheelchairYes,
              WheelchairAccess.limited => l10n.placeDetailsWheelchairLimited,
              WheelchairAccess.no => l10n.placeDetailsWheelchairNo,
            }),
          ),
        if (details.outdoorSeating)
          _Row(
            icon: Icons.deck_outlined,
            child: Text(l10n.placeDetailsOutdoorSeating),
          ),
        if (wikipedia != null)
          _Row(
            icon: Icons.menu_book_outlined,
            child: _LinkText(
              l10n.placeDetailsWikipedia(details.wikipediaTitle ?? ''),
              () => open(wikipedia),
            ),
          ),
      ],
    );
  }

  /// A web address the way people write it: no scheme, no `www.`, no
  /// trailing slash.
  static String _websiteLabel(Uri url) {
    final text = '${url.host}${url.path}'.replaceFirst(RegExp('^www\\.'), '');
    return text.endsWith('/') ? text.substring(0, text.length - 1) : text;
  }
}

/// One detail: [icon] in the card's icon column, [child] beside it.
class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Icon(
              icon,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DefaultTextStyle.merge(
              style: theme.textTheme.bodyMedium,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Text that opens something when tapped.
class _LinkText extends StatelessWidget {
  const _LinkText(this.text, this.onTap);

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      link: true,
      child: InkWell(
        onTap: onTap,
        child: Text(
          text,
          style: TextStyle(
            color: color,
            decoration: TextDecoration.underline,
            decorationColor: color,
          ),
        ),
      ),
    );
  }
}

/// Whether the place is open at [now], when [raw] can be read, and the
/// rules as written, one per line.
class _OpeningHoursText extends StatelessWidget {
  const _OpeningHoursText({required this.raw, required this.now});

  final String raw;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = OpeningHours.parse(raw)?.status(now);
    final change = status?.change;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (status != null)
          Text(
            switch ((status.open, change)) {
              (true, null) => l10n.placeDetailsOpenNow,
              (true, final DateTime at) => l10n.placeDetailsOpenCloses(
                _when(context, at),
              ),
              (false, null) => l10n.placeDetailsClosed,
              (false, final DateTime at) => l10n.placeDetailsClosedOpens(
                _when(context, at),
              ),
            },
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: status.open
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ),
        for (final line in openingHoursLines(raw)) Text(line),
      ],
    );
  }

  /// [at] as a time of day, with its weekday unless it is today.
  String _when(BuildContext context, DateTime at) {
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(at),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final today =
        at.year == now.year && at.month == now.month && at.day == now.day;
    if (today) return time;
    final day = DateFormat.E(AppLocalizations.of(context).localeName);
    return '${day.format(at)} $time';
  }
}
