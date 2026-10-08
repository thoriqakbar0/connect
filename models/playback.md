# Video-authoritative playback model — issue 769

Executable **proposed contract**, not an implementation or a claim that the current
player satisfies it. Upstream: https://github.com/commaai/connect/issues/769.
This branch is independent of the navigation model branch.

## Design

The media element owns playback time. Map, timeline and thumbnails consume one
observed route-relative time; they do not advance a second wall clock and repeatedly
seek the player to catch up. A user seek records intent; confirmed media observations
publish the new time. Loading, waiting, pause, play rejection and renders cannot
invent playback progress. Rate remains positive; pause is a command, not rate zero.

The state machine covers source selection/unmount, metadata, play/pause (including
native pause), buffering, time updates, latest-seek-wins, end/replay, zero-based loops,
network/missing/decode errors, explicit retry, mute and rate changes. Source changes
reset route-local state while preserving user rate/mute preferences. Retry keeps the
last confirmed position, creates a fresh source epoch and returns paused after seeking.
Playback begins only after a current `playing` observation; autoplay rejection never
pretends playback started. Initial load does not assume autoplay permission.

Three independent identities prevent races:

1. Source epoch: callbacks from a replaced/retried resource are ignored.
2. Play command ID: an old `play()` promise rejection cannot override newer intent.
3. Seek ID: a replaced seek cannot publish its old target. Pausing while seeking
   invalidates play attempts, **not** the pending seek completion.

## Executable obligations

`safety` requires a media-owned clock, consistent route/video time conversion, bounded
positions and seek targets, honest playback status, valid seek state and positive rate.
Named traces cover buffering, seek/source races, autoplay/pause races, retry, loops
starting at zero, metadata-delayed seek, end/replay and pause-during-seek. The negative
control introduces a synthetic clock advance and requires the invariant to reject it;
it is not a transition in `step`.

```sh
npm install --global @informalsystems/quint@0.31.0
quint typecheck models/playback.qnt
quint test models/playback.qnt --backend=typescript --seed=769 --max-samples=100
quint run models/playback.qnt --backend=typescript --invariant=safety --seed=769 --max-samples=10000 --max-steps=50 --verbosity=1
quint verify models/playback.qnt --invariant=safety --max-steps=5 --verbosity=1
```

The TypeScript simulator avoids a separate Rust evaluator download. The verifier
uses Apalache (default 0.51.1 in this CLI) and Java 17; its first run downloads it.
Simulation is sampled, not exhaustive. `verify --max-steps=5` is bounded checking,
not an unbounded proof. These commands do not execute the React application.

## Refinement into this codebase (next stage)

| Current seam | Obligation |
| --- | --- |
| `src/components/DriveVideo/index.jsx` | Replace periodic drift correction with media events and imperative user commands; isolate native HLS/hls.js behind one adapter |
| `src/timeline/index.js` | Replace `Date.now()` extrapolation with confirmed media time |
| `src/timeline/playback.js` | Separate user intent from observed status; remove rate-zero buffering and synthetic clock resets |
| `DriveView/Media`, `Timeline`, `DriveMap` | Derive dependent views from the same observation; seek only on user/loop commands |

## Abstractions and remaining checks

- Two sources, integer media times 0–4, a one-second video-start offset, and rates
  1/2/4 represent bounded examples, not actual route lengths or timing precision.
- `seeked` assumes a successful seek reached its bounded target. The real adapter
  must read `currentTime`, tolerate seekable-range/frame rounding and report failure,
  not publish the requested time as if it were observed.
- Browser media events do **not** carry these IDs. The adapter must bind callbacks
  to the active resource, serialize/coalesce seeks, read current state on completion,
  and capture command IDs for promises. This is an implementation obligation, not
  an assumed browser guarantee.
- `nativePause` abstracts a genuine external pause, not internal pause events during
  a source change/seek. Adapter tests must distinguish these. `playing` after a
  canceled play must trigger an actual pause, not merely be ignored in app state.
- Loop handling is event-driven and may observe an overshoot before requesting a
  seek. The model does not promise frame-perfect loops, seek latency, seamless
  playback through missing segments, automatic recovery or network progress.
- Mute/rate are preferences. Codec support, audio track behavior, supported rates,
  buffering timeouts and mobile autoplay/background policies are not proved.
- No visual quality, performance, browser compatibility or unbounded liveness claim
  follows from this model. Implementation must still be tested on desktop, iOS and
  Android browsers **and** iOS/Android installed PWAs, with audio/no-audio, native
  HLS/hls.js, interruptions, missing segments and network failures.
