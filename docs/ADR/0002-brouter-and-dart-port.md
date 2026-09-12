# 2. BRouter for routing, with a Dart port for the phone

Status: accepted, 2026-09-12.

## Context

Bike routing needs an engine that knows surfaces, bike networks and elevation,
runs worldwide on a small VPS, and can eventually run on the phone so that the
server becomes optional for users and forks.

## Decision

Self-host **BRouter** (MIT): its profiles are the bike-routing quality of the
app, elevation is in its data, it does via points, alternatives and
a round-trip mode (`engineMode=4`), and it runs worldwide in a 128 MB JVM.

In parallel, port its routing runtime to a pure-Dart package,
`app/packages/brouter_dart` (`core`, `mapaccess`, `expressions`, `codec`,
`util`), one file per Java class, in an isolate, on the same rd5 tiles and
profiles. The server is the oracle: the algorithm is deterministic, so parity is
checked at three levels — codec round trips byte-identical, profile evaluation
to 1e-6, geometry, length, ascent and messages identical over 200+ cases.

## Alternatives considered

- **GraphHopper** — wants roughly a 64 GB box for the planet; kept as the
  fallback if scale ever demands it.
- **Public routing servers** — not permitted as an app backend.
- **Kotlin Multiplatform or Rust** — a second toolchain and a native bridge for
  no benefit; a clean reimplementation would leave us without an oracle.

## Consequences

- A `jvm.dart` helper emulates Java integer overflow, `>>>` and 32-bit floats;
  that arithmetic is the main determinism risk, and no behavioural change goes
  into `brouter_dart` until parity is green.
- On-device routing costs the user 125–250 MB per 5° tile, and a server backend
  stays as the fallback for uncovered areas: `CompositeRoutingBackend` never
  routes locally on partial coverage.
