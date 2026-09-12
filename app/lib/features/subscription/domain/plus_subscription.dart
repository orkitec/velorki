/// The subscription domain, in the app's own words.
///
/// Nothing here imports `purchases_flutter`: the store SDK stays behind
/// [SubscriptionService], so the paywall, the settings tile and every test can
/// work with plain Dart objects. The RevenueCat implementation maps its
/// wrappers onto these types once, in one file.
library;

/// The RevenueCat entitlement that unlocks Velorki Plus.
///
/// The relay checks the same string (`REVENUECAT_ENTITLEMENT`, default
/// `plus`), so the two sides agree on what "subscribed" means.
const String plusEntitlementId = 'plus';

/// What RevenueCat knows about this installation's purchases.
class PlusCustomerInfo {
  /// Creates customer info.
  const PlusCustomerInfo({
    required this.entitled,
    this.expiresAt,
    this.willRenew = false,
    this.managementUrl,
    this.productIdentifier,
  });

  /// Nobody has bought anything (yet), which is also what a build without a
  /// RevenueCat key reports.
  static const PlusCustomerInfo none = PlusCustomerInfo(entitled: false);

  /// Whether the [plusEntitlementId] entitlement is active right now.
  final bool entitled;

  /// When the current period ends; `null` for a lifetime purchase or when
  /// nothing is owned.
  final DateTime? expiresAt;

  /// Whether the store will charge again at [expiresAt].
  final bool willRenew;

  /// The store's own subscription management page, when it named one.
  final String? managementUrl;

  /// The store product behind the entitlement, for the settings tile.
  final String? productIdentifier;

  @override
  bool operator ==(Object other) =>
      other is PlusCustomerInfo &&
      other.entitled == entitled &&
      other.expiresAt == expiresAt &&
      other.willRenew == willRenew &&
      other.managementUrl == managementUrl &&
      other.productIdentifier == productIdentifier;

  @override
  int get hashCode => Object.hash(
    entitled,
    expiresAt,
    willRenew,
    managementUrl,
    productIdentifier,
  );

  @override
  String toString() =>
      'PlusCustomerInfo(entitled: $entitled, expiresAt: $expiresAt)';
}

/// How long one subscription period lasts.
enum PlusPeriod {
  /// Billed weekly.
  weekly,

  /// Billed monthly.
  monthly,

  /// Billed every two months.
  twoMonthly,

  /// Billed quarterly.
  threeMonthly,

  /// Billed every six months.
  sixMonthly,

  /// Billed once a year.
  annual,

  /// Bought once, kept forever.
  lifetime,

  /// Anything the store calls something else.
  other,
}

/// A free or reduced-price introductory phase, which is how the 7-day trial
/// reaches the paywall.
class PlusIntroOffer {
  /// Creates an introductory offer.
  const PlusIntroOffer({
    required this.priceString,
    required this.periodUnit,
    required this.periodCount,
    required this.isFree,
  });

  /// The price of the introductory phase, formatted by the store.
  final String priceString;

  /// `day`, `week`, `month` or `year`, as the store reported it.
  final String periodUnit;

  /// How many [periodUnit]s the phase lasts, e.g. 7 days.
  final int periodCount;

  /// Whether the phase costs nothing, i.e. it is a free trial.
  final bool isFree;

  /// The trial length in days, when it can be worked out.
  int? get days => switch (periodUnit) {
    'day' => periodCount,
    'week' => periodCount * 7,
    'month' => periodCount * 30,
    'year' => periodCount * 365,
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is PlusIntroOffer &&
      other.priceString == priceString &&
      other.periodUnit == periodUnit &&
      other.periodCount == periodCount &&
      other.isFree == isFree;

  @override
  int get hashCode => Object.hash(priceString, periodUnit, periodCount, isFree);

  @override
  String toString() => 'PlusIntroOffer($priceString, $periodCount $periodUnit)';
}

/// One purchasable option as the paywall shows it.
class PlusPackage {
  /// Creates a package.
  const PlusPackage({
    required this.id,
    required this.title,
    required this.priceString,
    required this.period,
    this.introOffer,
    this.native,
  });

  /// The package identifier in the offering, e.g. `$rc_annual`.
  final String id;

  /// The store product's title.
  final String title;

  /// The price, formatted by the store in the user's currency.
  final String priceString;

  /// How long one period lasts.
  final PlusPeriod period;

  /// The free or reduced introductory phase, when the product has one.
  final PlusIntroOffer? introOffer;

  /// The store SDK's own package object, handed back to
  /// [SubscriptionService.purchase]. `null` in tests and in the no-op service.
  final Object? native;

  /// Whether this package starts with a free trial.
  bool get hasFreeTrial => introOffer?.isFree ?? false;

  @override
  String toString() => 'PlusPackage($id, $priceString, ${period.name})';
}

/// The offering the paywall renders.
class PlusOffering {
  /// Creates an offering.
  const PlusOffering({required this.id, required this.packages});

  /// The offering identifier configured in RevenueCat.
  final String id;

  /// What can be bought, in the order the store returned.
  final List<PlusPackage> packages;

  @override
  String toString() => 'PlusOffering($id, ${packages.length} packages)';
}

/// Why a subscription call did not work.
enum SubscriptionFailure {
  /// This build has no RevenueCat key, so there is nothing to buy.
  unavailable,

  /// The rider dismissed the store sheet. Not worth an error message.
  cancelled,

  /// The store said no: billing unavailable, product missing, network down.
  storeProblem,

  /// Purchases are not allowed on this device (parental controls).
  notAllowed,

  /// Anything else the SDK reported.
  unknown,
}

/// A subscription operation that failed.
class SubscriptionException implements Exception {
  /// Creates the exception.
  const SubscriptionException(this.failure, this.message, {this.cause});

  /// What kind of failure it was.
  final SubscriptionFailure failure;

  /// A message safe to show the rider.
  final String message;

  /// The underlying error, for the log.
  final Object? cause;

  @override
  String toString() => 'SubscriptionException(${failure.name}: $message)';
}
