import 'package:velorki_api/velorki_api.dart' show RelayException;
import 'package:velorki_brouter/velorki_brouter.dart'
    show RoutingErrorKind, RoutingException;

import '../../../core/l10n/localized_text.dart';
import '../../../core/l10n/relay_error_text.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../import_export/data/track_decoder.dart' show ImportException;
import '../../import_export/presentation/import_file_action.dart'
    show importFailureMessage;
import '../../subscription/domain/plus_subscription.dart';

/// One sentence for the rider about [error], in [l10n]'s language.
///
/// Every message the app shows for a failure goes through here, so no
/// exception's English `message` or `toString()` reaches the screen. What the
/// app has no words for (a database or file error) is "Something went
/// wrong"; the detail is in the log.
String errorText(AppLocalizations l10n, Object error) => switch (error) {
  LocalizedException() => error.describe(l10n),
  RoutingException() => routingErrorText(l10n, error),
  RelayException() => relayErrorText(l10n, error.error),
  SubscriptionException() => subscriptionErrorText(l10n, error),
  ImportException() => importFailureMessage(l10n, error.failure),
  _ => l10n.errorUnexpected,
};

/// What the rider reads when routing failed, by the kind of failure.
String routingErrorText(AppLocalizations l10n, RoutingException error) =>
    switch (error.kind) {
      RoutingErrorKind.network => l10n.routingErrorNetwork,
      RoutingErrorKind.noRoute => l10n.routingErrorNoRoute,
      RoutingErrorKind.invalid => l10n.routingErrorInvalid,
      RoutingErrorKind.cancelled => l10n.routingErrorCancelled,
      RoutingErrorKind.missingTiles => l10n.routingErrorMissingTiles,
    };

/// What the rider reads when the store failed, by the kind of failure.
String subscriptionErrorText(
  AppLocalizations l10n,
  SubscriptionException error,
) => switch (error.failure) {
  SubscriptionFailure.unavailable => l10n.plusErrorUnavailable,
  SubscriptionFailure.cancelled => l10n.plusErrorCancelled,
  SubscriptionFailure.storeProblem => l10n.plusErrorStore,
  SubscriptionFailure.notAllowed => l10n.plusErrorNotAllowed,
  SubscriptionFailure.unknown => l10n.plusErrorUnknown,
};
