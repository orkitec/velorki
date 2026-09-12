# 1. As much as possible runs on the device

Status: accepted, 2026-09-12.

## Context

Velorki is an open-source app with no funding behind it. A backend that holds
user data would mean accounts, a database, sync, GDPR obligations, backups and
a bill that grows with every install. It would also make every fork depend on
somebody's server. At the same time, a bike app needs a routing graph that is
far too large to ship in an app bundle, and some credentials cannot be put into
an open-source binary.

## Decision

Everything that can run on the phone runs on the phone: routes, rides, the loop
generator, GPX and FIT handling, statistics, offline maps, and eventually the
routing itself. The server side is limited to a routing server and a thin relay
that holds only the OAuth client secrets, the language model key and the store
for share links. No accounts, no cloud database, no sync in v1. This is the rule
every later feature is measured against.

## Alternatives considered

- **A normal app backend with accounts and sync.** Rejected: the operating
  cost, the privacy surface and the store obligations (account deletion, Sign
  in with Apple) are all real, and none of the v1 features need it. Sync is
  parked as a possible later Plus feature.
- **No backend at all**, with routing from a public server. Rejected: public
  BRouter, OpenRouteService and FOSSGIS instances explicitly are not app
  backends, and the OAuth secrets have nowhere to live.

## Consequences

- Routes and rides live in one SQLite database and as exported files. Losing
  the phone loses them, which the UI has to be honest about.
- The data model is local-first: uuids, packed geometry blobs, no server ids.
- Privacy answers are short and the privacy policy is mostly "it stays here".
- Every feature request gets the same first question: can this run on device?
