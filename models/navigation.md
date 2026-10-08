# URL navigation model — issue 770

Executable **proposed contract**, not an implementation or a claim that the current
JavaScript satisfies it. Upstream: https://github.com/commaai/connect/issues/770.
This branch is independent of the playback model branch.

## Design

One pure parser produces one navigation target. Initial load, PUSH, REPLACE and
POP use that same target; UI components emit navigation rather than separately
mutating URL-shaped Redux fields. A serializer is the inverse for supported targets.
Device settings, upload queue, clip menu and add-device are proposed `modal` query
states over their parent page, rather than component-local visibility flags.
Closing a directly linked modal navigates to its parent; closing pushes that parent,
so browser Back can reopen it. The opaque `share` field represents existing share
credentials, preserved when closing a modal or canonicalizing a legacy link.

The model covers home, device dashboard, drive (whole or clipped), Prime, stream,
referrals, and these overlays. `demo` is a first-class device alias. Invalid paths,
unknown overlays, reversed ranges and invalid numeric tokens resolve to not-found.
A range beginning at zero is not confused with an absent range.

Separate lifetimes:

- Navigation epoch changes on every navigation, including history traversal.
- Device data is cached by device identity, not by URL. In-session navigation never
  clears it. A route change can reuse device data.
- The resource epoch changes only when `(device, route)` changes: opening an
  overlay or changing the clip range must not remount the route resource/player.
- Async completions carry their originating epoch. Old results can populate their
  own cache entry but cannot select another device or rewrite a newer URL.
- A successful legacy time-window lookup replaces the current history entry with
  a canonical route URL only if its navigation epoch is still current.

## Executable obligations

`safety` combines URL/state agreement, bounded valid selections, history cursor
validity, cache retention, device isolation and parser/serializer round trips.
Named traces exercise deep links, modal close/back/forward, REPLACE and forward-stack
truncation, route resource reuse, stale data, and stale legacy conversions. The
negative-control test deliberately creates wrong-device data and requires the
isolation invariant to reject it; it is not a transition in `step`.

```sh
npm install --global @informalsystems/quint@0.31.0
quint typecheck models/navigation.qnt
quint test models/navigation.qnt --backend=typescript --seed=770 --max-samples=100
quint run models/navigation.qnt --backend=typescript --invariant=safety --seed=770 --max-samples=10000 --max-steps=50 --verbosity=1
quint verify models/navigation.qnt --invariant=safety --max-steps=5 --verbosity=1
```

The TypeScript simulator avoids a separate Rust evaluator download. The verifier
uses Apalache (default 0.51.1 in this CLI) and Java 17; its first run downloads it.
Simulation is sampled, not exhaustive. `verify --max-steps=5` is bounded checking,
not an unbounded proof. These commands do not execute the React application.

## Refinement into this codebase (next stage)

| Current seam | Obligation |
| --- | --- |
| `src/url.js`, `src/initialState.js` | One parser/serializer, explicit valid/invalid result, absent-vs-zero bounds |
| `src/actions/history.js` | Same reconciliation for PUSH/REPLACE/POP; epoch-guard legacy conversion |
| URL writers in `src/actions/index.js` | Emit navigation intents rather than duplicate URL/state updates |
| `src/reducers/globalState.js` | Retain keyed data; separate route identity from view state |
| `DeviceList`, `Media`, `AddDevice` | Render major overlays from URL state |
| `src/api/backend.js` | Resolve demo links consistently with backend selection |

## Abstractions and remaining checks

- URLs are tokenized paths plus structured query fields, not raw URL strings.
  Percent encoding, duplicate/unknown query parameters, authentication redirects,
  pairing secrets and query sanitization need separate JavaScript tests.
- Three device identities, two routes, and integer bounds 0–4 represent equivalence
  classes. Legacy UTC millisecond windows use the same small symbolic range; a
  successful lookup abstracts choosing a valid route from an API response. Missing,
  failed and ambiguous lookups are not modeled.
- Cache entries represent availability, not payload contents, freshness, Redux
  object identity, memory limits or eviction. Retention applies within one auth
  session; logout/permission changes must invalidate protected data.
- Resource reuse is represented by an epoch plus directed assertions, not React
  mounting behavior. No liveness/fairness claim is made for network responses.
- Overlays are a proposed URL vocabulary, not a promise to expose transient menus,
  payment operations or pairing credentials in a shareable link.
- The JS implementation must be checked against these transitions; passing a model
  alone does not establish refinement or resolve the upstream issue.
