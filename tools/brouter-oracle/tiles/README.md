# Frozen oracle tiles

The two rd5 segment tiles the BRouter parity corpus and the `brouter_dart`
golden vectors were recorded against. They are committed here as plain files
(4.2 MB total, no Git LFS) so that the parity tests are self-contained: nothing
in CI or in a local run downloads a tile.

| File | Area | Bytes | sha256 |
|---|---|---:|---|
| `W20_N30.rd5` | Madeira and Porto Santo (PT) — lon −20..−15, lat 30..35 | 1 527 283 | `1e18289694cc451ae1761a67ed732081b41c5d0b6b570a3d144f9e5bc6fa6a4b` |
| `W25_N60.rd5` | SW Iceland incl. Reykjavík and Reykjanes — lon −25..−20, lat 60..65 | 2 655 536 | `824ef377d3459e92f974f0ce93e880df82a572ce38d5789cc5c347450beb3f6f` |

Both are island tiles, so the road network is fully contained in the tile and no
neighbouring segment is ever needed. They are the two smallest tiles in the
upstream index that still carry a real, connected network.

## Where they come from

Snapshot of <https://brouter.de/brouter/segments4/> taken on **2026-09-12**
(index listing timestamp 12-Sep-2026 01:03 CET; the directory itself was last
written 12-Sep-2026 03:13). brouter.de rebuilds `segments4` every night and can
never serve these exact bytes again — which is the whole reason they live in the
repo.

## Attribution

The rd5 files are derived from OpenStreetMap data, compiled by the BRouter
project (`brouter-map-creator`).

> © OpenStreetMap contributors — <https://www.openstreetmap.org/copyright>

OpenStreetMap data is licensed under the Open Data Commons Open Database License
(ODbL) v1.0: <https://opendatacommons.org/licenses/odbl/1-0/>. The ODbL applies
to these files and to anything derived from them; it does not apply to the rest
of this repository.

## The corpus is bound to exactly these bytes

`../tiles.sha256` pins both files, and `../fetch.sh` verifies every copy against
it before the tests may see it. Everything recorded from them —
`../corpus/requests.json`, `../corpus/index.json`, `../corpus/responses/`,
`../dump/samples/` and the `brouter_dart` mapaccess vectors — is valid only for
these checksums.

So: **replacing a tile means re-recording the corpus.** Never swap a file here
to make a red parity test go green; first decide whether the data changed or the
port did. The full procedure is the runbook "Bumping to a newer upstream
snapshot" in `../README.md` — refresh the tiles, re-pin `../tiles.sha256`,
re-record the corpus and the vectors, and commit the new tiles together with
everything recorded from them in one commit.
