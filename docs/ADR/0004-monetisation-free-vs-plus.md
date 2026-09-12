# 4. Free is what runs on the phone; Plus is what needs a server

Status: accepted, 2026-09-12.

## Context

The app is free and its source is public, but the routing server, the relay, the
model and the partner applications cost money. The paid line has to be
explainable in one sentence.

## Decision

**Free is everything that runs on the phone. Velorki Plus is everything that
needs our servers or a partner account.** Free: map, planning, profiles,
alternatives, elevation, search, smart loops (algorithmic, no model), recording,
library, statistics, GPX and FIT files, offline map regions, on-device routing
tiles. Plus: the AI assistant, the Strava and RideWithGPS connections, link
sharing, later cloud sync.

One `PlusGate` configuration lists the gated features, so moving an item across
the line is a one-line change. A 7-day store trial lets the integrations be
tried. RevenueCat is checked server-side on the AI and OAuth endpoints, which
doubles as their authentication.

## Alternatives considered

- **Gating the routing server** — would make the free app useless, and gating
  offline maps or recording would contradict the on-device-first rule.
- **Ads, a one-off price, or link-out payments** — ads conflict with the privacy
  story, one-off pricing does not match a recurring cost, and link-out regimes
  are not worth it at this scale.

## Consequences

- The free tier keeps a full path into Strava, Komoot and Garmin: export a file
  and share it. That is deliberate.
- A lapsed subscription hides the integrations but keeps all data.
- Forks unlocking everything is expected: the subscription buys the official
  client ids, the relay and the trademark, not the code.
