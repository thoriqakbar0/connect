module playback {
  // Time is bounded integer seconds; production adapters convert to route-relative milliseconds.
  type Player = {
    source: str, epoch: int, command: int, seekId: int, phase: str, wantsPlay: bool,
    mediaTime: int, routeTime: int, target: int, rate: int, muted: bool,
    loopStart: int, loopEnd: int, error: str,
    previousTime: int, publishedBy: str
  }
  var p: Player
  pure val duration = 4
  pure val videoStartOffset = 1
  pure def clamp(time: int): int = if (time < 0) 0 else if (time > duration) duration else time
  pure val empty: Player = {
    source: "", epoch: 0, command: 0, seekId: 0, phase: "empty", wantsPlay: false,
    mediaTime: 0, routeTime: 0, target: -1, rate: 1, muted: true,
    loopStart: -1, loopEnd: -1, error: "", previousTime: 0, publishedBy: "reset"
  }
  action init = p' = empty
  pure def load(old: Player, source: str): Player = {
    ...empty, source: source, epoch: old.epoch + 1, command: old.command + 1, seekId: old.seekId + 1,
    phase: if (source == "") "empty" else "loading",
    routeTime: if (source == "") 0 else videoStartOffset,
    rate: old.rate, muted: old.muted, previousTime: old.mediaTime
  }
  action selectSource(source: str): bool = p' = load(p, source)
  val active = p.source != "" and p.phase != "error"
  pure def unchanged(old: Player): Player = { ...old, previousTime: old.mediaTime, publishedBy: "none" }
  pure def observed(old: Player, time: int): Player = {
    ...old, mediaTime: time, routeTime: videoStartOffset + time,
    previousTime: old.mediaTime, publishedBy: "media"
  }
  action metadata(epoch: int): bool = p' = if (epoch == p.epoch and p.phase == "loading") {
    ...unchanged(p), phase: if (p.target >= 0) "seeking" else "paused"
  } else unchanged(p)

  // Commands express intent; only observations from the current media resource publish its clock.
  action play = all {
    active,
    p' = { ...unchanged(p), wantsPlay: true, command: p.command + 1,
      phase: if (p.phase == "ended") "seeking" else if (p.phase == "blocked") "paused" else p.phase,
      target: if (p.phase == "ended") 0 else p.target,
      seekId: if (p.phase == "ended") p.seekId + 1 else p.seekId }
  }
  action pause = all {
    active,
    p' = { ...unchanged(p), wantsPlay: false, command: p.command + 1,
      phase: if (Set("playing", "waiting", "blocked").contains(p.phase)) "paused" else p.phase }
  }
  action playing(epoch: int): bool = p' = if (epoch == p.epoch and active and p.wantsPlay and
    Set("paused", "waiting", "playing", "blocked").contains(p.phase)) {
      ...unchanged(p), phase: "playing", error: ""
    } else unchanged(p)
  action rejected(epoch: int, command: int): bool = p' =
    if (epoch == p.epoch and command == p.command and active and p.wantsPlay) {
      ...unchanged(p), phase: if (Set("loading", "seeking").contains(p.phase)) p.phase else "blocked",
      wantsPlay: false, error: "autoplay"
    } else unchanged(p)
  action nativePause(epoch: int): bool = p' = if (epoch == p.epoch and active) {
    ...unchanged(p), wantsPlay: false, command: p.command + 1,
    phase: if (Set("playing", "waiting", "blocked").contains(p.phase)) "paused" else p.phase
  } else unchanged(p)
  action waiting(epoch: int): bool = p' = if (epoch == p.epoch and p.phase == "playing") {
    ...unchanged(p), phase: "waiting"
  } else unchanged(p)
  action timeUpdate(epoch: int, time: int): bool = all {
    time >= 0 and time <= duration,
    p' = if (epoch == p.epoch and p.phase == "playing") observed(p, time) else unchanged(p)
  }
  action seek(routeTime: int): bool = all {
    active,
    p' = { ...unchanged(p), target: clamp(routeTime - videoStartOffset),
      phase: if (p.phase == "loading") "loading" else "seeking", command: p.command + 1,
      seekId: p.seekId + 1 }
  }
  // A completion is a currentTime observation, not a speculative update on seek request.
  action seeked(epoch: int, seekId: int): bool = p' =
    if (epoch == p.epoch and seekId == p.seekId and p.phase == "seeking") {
      ...observed(p, p.target), target: -1, phase: "paused"
    } else unchanged(p)
  action setRate(rate: int): bool = all {
    Set(1, 2, 4).contains(rate), p' = { ...unchanged(p), rate: rate }
  }
  action setMuted(muted: bool): bool = p' = { ...unchanged(p), muted: muted }
  action setLoop(start: int, end: int): bool = all {
    start >= 0 and start < end and end <= duration,
    p' = { ...unchanged(p), loopStart: start, loopEnd: end }
  }
  action clearLoop = p' = { ...unchanged(p), loopStart: -1, loopEnd: -1 }
  action loopBoundary = all {
    p.phase == "playing", p.loopStart >= 0, p.mediaTime >= p.loopEnd,
    seek(p.loopStart + videoStartOffset)
  }
  action ended(epoch: int): bool = p' = if (epoch == p.epoch and p.phase == "playing") {
    ...observed(p, duration),
    phase: if (p.loopStart >= 0) "seeking" else "ended",
    target: if (p.loopStart >= 0) p.loopStart else -1,
    wantsPlay: p.loopStart >= 0, command: p.command + 1, seekId: p.seekId + 1
  } else unchanged(p)
  action failed(epoch: int, reason: str): bool = all {
    Set("network", "missing", "decode").contains(reason),
    p' = if (epoch == p.epoch and p.source != "") {
      ...unchanged(p), phase: "error", wantsPlay: false, target: -1,
      error: reason, command: p.command + 1
    } else unchanged(p)
  }
  action retry = all {
    p.phase == "error",
    p' = { ...unchanged(p), epoch: p.epoch + 1, command: p.command + 1, seekId: p.seekId + 1,
      phase: "loading", error: "", target: p.mediaTime, wantsPlay: false }
  }
  // Wall-clock ticks, renders and dependent components cannot advance playback.
  action tick = p' = unchanged(p)
  action step = {
    nondet source = Set("routeA", "routeB", "").oneOf()
    nondet epoch = Set(p.epoch, p.epoch - 1).oneOf()
    nondet command = Set(p.command, p.command - 1).oneOf()
    nondet seekId = Set(p.seekId, p.seekId - 1).oneOf()
    nondet time = 0.to(duration).oneOf()
    nondet rate = Set(1, 2, 4).oneOf()
    nondet muted = Set(false, true).oneOf()
    nondet reason = Set("network", "missing", "decode").oneOf()
    any {
      selectSource(source), metadata(epoch), play, pause, playing(epoch), rejected(epoch, command),
      nativePause(epoch), waiting(epoch), timeUpdate(epoch, time), seek(time), seeked(epoch, seekId),
      setRate(rate), setMuted(muted), setLoop(0, 2), clearLoop, loopBoundary,
      ended(epoch), failed(epoch, reason), retry, tick
    }
  }

  val mediaOwnsClock = p.publishedBy != "none" or p.mediaTime == p.previousTime
  val synchronized = p.routeTime == (if (p.source == "") 0 else videoStartOffset + p.mediaTime)
  val bounded = p.mediaTime >= 0 and p.mediaTime <= duration and p.target >= -1 and p.target <= duration
  val honestStatus = (p.phase == "playing" implies p.wantsPlay) and
    (Set("error", "ended", "blocked", "empty").contains(p.phase) implies not(p.wantsPlay))
  val validSeek = p.phase != "seeking" or p.target >= 0
  val validRate = Set(1, 2, 4).contains(p.rate)
  val safety = mediaOwnsClock and synchronized and bounded and honestStatus and validSeek and validRate

  run videoClockTest = init.then(selectSource("routeA")).then(metadata(1)).then(play).then(playing(1))
    .then(timeUpdate(1, 2)).then(tick).then(waiting(1)).then(tick)
    .then(all { assert(p.mediaTime == 2), assert(p.routeTime == 3), assert(p.phase == "waiting"), assert(safety), p' = p })
  run latestSeekTest = init.then(selectSource("routeA")).then(metadata(1))
    .then(seek(2)).then(seek(4)).then(seeked(1, 2))
    .then(all { assert(p.mediaTime == 0), assert(p.phase == "seeking"), p' = p })
    .then(seeked(1, 3)).then(all { assert(p.mediaTime == 3), assert(safety), p' = p })
  run staleSourceTest = init.then(selectSource("routeA")).then(metadata(1)).then(play).then(playing(1))
    .then(selectSource("routeB")).then(metadata(1)).then(timeUpdate(1, 4)).then(failed(1, "decode"))
    .then(all { assert(p.phase == "loading"), assert(p.mediaTime == 0), assert(p.error == ""), assert(safety), p' = p })
  run autoplayAndPauseRaceTest = init.then(selectSource("routeA")).then(metadata(1))
    .then(play).then(rejected(1, 2))
    .then(all { assert(p.phase == "blocked"), assert(not(p.wantsPlay)), p' = p })
    .then(play).then(pause).then(playing(1)).then(rejected(1, 3))
    .then(all { assert(p.phase == "paused"), assert(not(p.wantsPlay)), assert(safety), p' = p })
  run errorRetryTest = init.then(selectSource("routeA")).then(metadata(1)).then(play).then(playing(1))
    .then(timeUpdate(1, 2)).then(failed(1, "network")).then(retry).then(metadata(2)).then(seeked(2, 2))
    .then(all { assert(p.mediaTime == 2), assert(p.phase == "paused"), assert(p.error == ""), assert(safety), p' = p })
  run loopFromZeroTest = init.then(selectSource("routeA")).then(metadata(1)).then(setLoop(0, 2))
    .then(play).then(playing(1)).then(timeUpdate(1, 2)).then(loopBoundary)
    .then(all { assert(p.mediaTime == 2), assert(p.target == 0), p' = p })
    .then(seeked(1, 2)).then(playing(1))
    .then(all { assert(p.mediaTime == 0), assert(p.phase == "playing"), assert(safety), p' = p })
  run loadingSeekAndEndTest = init.then(selectSource("routeA")).then(seek(99)).then(metadata(1)).then(seeked(1, 2))
    .then(play).then(playing(1)).then(ended(1))
    .then(all { assert(p.mediaTime == duration), assert(p.phase == "ended"), assert(safety), p' = p })
    .then(play).then(seeked(1, 4)).then(playing(1))
    .then(all { assert(p.mediaTime == 0), assert(p.phase == "playing"), assert(safety), p' = p })
  run pauseDuringSeekTest = init.then(selectSource("routeA")).then(metadata(1)).then(play)
    .then(seek(3)).then(pause).then(seeked(1, 2))
    .then(all { assert(p.mediaTime == 2), assert(p.phase == "paused"), assert(not(p.wantsPlay)), assert(safety), p' = p })
  run nativePauseWhileWaitingTest = init.then(selectSource("routeA")).then(metadata(1)).then(play)
    .then(playing(1)).then(waiting(1)).then(nativePause(1)).then(playing(1))
    .then(all { assert(p.phase == "paused"), assert(not(p.wantsPlay)), assert(safety), p' = p })
  // Negative control: a synthetic clock cannot masquerade as a media observation.
  run rejectsSyntheticClockTest = init.then(selectSource("routeA")).then(metadata(1))
    .then(p' = { ...unchanged(p), mediaTime: 1, routeTime: videoStartOffset + 1 })
    .then(all { assert(synchronized), assert(not(mediaOwnsClock)), p' = p })
}
