module navigation {
  // Paths are tokenized; percent-decoding and query validation belong to the JS adapter.
  type Target = { device: str, page: str, route: str, start: int, end: int, modal: str }
  type Url = { path: List[str], modal: str, share: str }
  type Request = { device: str, epoch: int }
  type State = {
    history: List[Url], cursor: int, target: Target, epoch: int,
    cache: Set[str], pending: Set[Request], visible: str,
    previousCache: Set[str], resourceEpoch: int
  }
  var s: State

  pure val devices = Set("aaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbb", "demo")
  pure val routeId = "00000000000000000001"
  pure val otherRouteId = "00000000000000000002"
  pure val home: Target = { device: "", page: "home", route: "", start: -1, end: -1, modal: "" }
  pure val missing = { ...home, page: "notFound" }
  pure val tokens = List("0", "1", "2", "3", "4")
  pure def number(token: str): int = tokens.indices().fold(-1, (n, i) => if (tokens[i] == token) i else n)
  pure def deviceTarget(device: str): Target = { ...home, device: device, page: "dashboard" }
  pure def driveTarget(device: str, start: int, end: int): Target = {
    ...deviceTarget(device), page: "drive", route: routeId, start: start, end: end
  }
  pure def validRange(start: int, end: int): bool = start >= 0 and start < end and end <= 4

  pure def parsePath(path: List[str]): Target = {
    val n = path.length()
    if (n == 0) home
    else if (path == List("referrals")) { ...home, page: "referrals" }
    else if (not(devices.contains(path[0]))) missing
    else if (n == 1) deviceTarget(path[0])
    else if (n == 2 and Set("prime", "stream").contains(path[1])) {
      ...deviceTarget(path[0]), page: path[1]
    }
    else if (n == 3) {
      val start = number(path[1])
      val end = number(path[2])
      if (validRange(start, end)) { ...deviceTarget(path[0]), page: "legacy", start: start, end: end } else missing
    }
    else if (not(Set(routeId, otherRouteId).contains(path[1]))) missing
    else if (n == 2) { ...driveTarget(path[0], -1, -1), route: path[1] }
    else if (n == 4) {
      val start = number(path[2])
      val end = number(path[3])
      if (validRange(start, end)) { ...driveTarget(path[0], start, end), route: path[1] } else missing
    }
    else missing
  }

  pure def parse(url: Url): Target = {
    val base = parsePath(url.path)
    val allowed = url.modal == "" or
      (url.modal == "settings" and base.device != "") or
      (Set("uploads", "clip").contains(url.modal) and base.page == "drive") or
      (url.modal == "addDevice" and Set("home", "dashboard").contains(base.page))
    if (allowed) { ...base, modal: url.modal } else missing
  }

  pure def serialize(target: Target, share: str): Url = {
    val path = if (target.page == "home") List()
      else if (target.page == "referrals") List("referrals")
      else if (target.page == "dashboard") List(target.device)
      else if (target.page == "legacy") List(target.device, tokens[target.start], tokens[target.end])
      else if (target.page == "drive") {
        if (target.start == -1) List(target.device, target.route)
        else List(target.device, target.route, tokens[target.start], tokens[target.end])
      }
      else List(target.device, target.page)
    { path: path, modal: target.modal, share: share }
  }

  pure val targets = devices.map(device => Set(
    deviceTarget(device), driveTarget(device, -1, -1),
    driveTarget(device, 0, 2), driveTarget(device, 1, 4),
    { ...driveTarget(device, -1, -1), route: otherRouteId },
    { ...deviceTarget(device), page: "legacy", start: 0, end: 2 },
    { ...deviceTarget(device), page: "prime" },
    { ...deviceTarget(device), page: "stream" },
    { ...deviceTarget(device), modal: "settings" },
    { ...driveTarget(device, 0, 2), modal: "settings" },
    { ...driveTarget(device, 0, 2), modal: "uploads" },
    { ...driveTarget(device, 0, 2), modal: "clip" },
    { ...deviceTarget(device), modal: "addDevice" }
  )).flatten().union(Set(home, { ...home, page: "referrals" }, { ...home, modal: "addDevice" }))
  pure val urls = targets.map(t => serialize(t, "opaque-share-credentials")).union(Set(
    { path: List("bad-device"), modal: "", share: "" },
    { path: List("demo", routeId, "2", "0"), modal: "", share: "" },
    { path: List("demo", routeId, "NaN", "4"), modal: "", share: "" }
  ))

  pure def initial(url: Url): State = {
    history: List(url), cursor: 0, target: parse(url), epoch: 0,
    cache: Set(), pending: Set(), visible: "", previousCache: Set(), resourceEpoch: 0
  }
  action init = s' = initial(serialize(home, ""))
  action boot(url: Url): bool = s' = initial(url)

  // One reconciliation path for PUSH, REPLACE and POP. Resource identity excludes overlays/ranges.
  pure def reconcile(old: State, history: List[Url], cursor: int): State = {
    val target = parse(history[cursor])
    val sameResource = target.device == old.target.device and target.route == old.target.route
    {
      ...old, history: history, cursor: cursor, target: target, epoch: old.epoch + 1,
      previousCache: old.cache,
      visible: if (old.cache.contains(target.device)) target.device else "",
      resourceEpoch: if (sameResource) old.resourceEpoch else old.resourceEpoch + 1
    }
  }
  action navigate(url: Url, replace: bool): bool = s' = reconcile(s,
    if (replace) s.history.replaceAt(s.cursor, url)
    else s.history.slice(0, s.cursor + 1).append(url),
    if (replace) s.cursor else s.cursor + 1)
  action back = all { s.cursor > 0, s' = reconcile(s, s.history, s.cursor - 1) }
  action forward = all { s.cursor + 1 < s.history.length(), s' = reconcile(s, s.history, s.cursor + 1) }
  action closeModal = all {
    s.target.modal != "",
    navigate(serialize({ ...s.target, modal: "" }, s.history[s.cursor].share), false)
  }
  action request = all {
    s.target.device != "",
    s' = { ...s, previousCache: s.cache,
      pending: s.pending.union(Set({ device: s.target.device, epoch: s.epoch })) }
  }
  action resolve(req: Request): bool = all {
    s.pending.contains(req),
    val loaded = { ...s, cache: s.cache.union(Set(req.device)), previousCache: s.cache,
      pending: s.pending.exclude(Set(req)),
      visible: if (req.epoch == s.epoch and req.device == s.target.device) req.device else s.visible }
    // Successful legacy lookup canonicalizes only the navigation that requested it.
    s' = if (req.epoch == s.epoch and s.target.page == "legacy") {
      val url = serialize({ ...driveTarget(req.device, -1, -1), modal: s.target.modal }, s.history[s.cursor].share)
      reconcile(loaded, s.history.replaceAt(s.cursor, url), s.cursor)
    } else loaded
  }
  action step = {
    nondet url = urls.oneOf()
    any {
      navigate(url, false), navigate(url, true), back, forward, closeModal, request,
      all { s.pending.size() > 0, nondet req = s.pending.oneOf(); resolve(req) }
    }
  }

  val urlIsAuthority = s.target == parse(s.history[s.cursor])
  val cacheRetained = s.previousCache.subseteq(s.cache)
  val noWrongDevice = s.visible == "" or s.visible == s.target.device
  val wellFormed = s.cursor >= 0 and s.cursor < s.history.length() and
    (s.target.start == -1 or validRange(s.target.start, s.target.end))
  pure val roundTrips = targets.forall(t => parse(serialize(t, "share")) == t)
  val safety = urlIsAuthority and cacheRetained and noWrongDevice and wellFormed and roundTrips

  run directLinkTest = {
    nondet target = targets.oneOf()
    boot(serialize(target, "share")).then(all { assert(s.target == target), assert(safety), s' = s })
  }
  run historyAndReuseTest = init
    .then(navigate(serialize(driveTarget("demo", 0, 2), "share"), false))
    .then(request).then(resolve({ device: "demo", epoch: 1 }))
    .then(navigate(serialize({ ...driveTarget("demo", 0, 2), modal: "settings" }, "share"), false))
    .then(all { assert(s.resourceEpoch == 1), assert(s.visible == "demo"), s' = s })
    .then(closeModal).then(back)
    .then(all { assert(s.target.modal == "settings"), assert(s.history[s.cursor].share == "share"), s' = s })
    .then(forward).then(all { assert(s.target.modal == ""), assert(safety), s' = s })
  run staleResponseTest = init
    .then(navigate(serialize(deviceTarget("aaaaaaaaaaaaaaaa"), ""), false)).then(request)
    .then(navigate(serialize(deviceTarget("bbbbbbbbbbbbbbbb"), ""), false))
    .then(resolve({ device: "aaaaaaaaaaaaaaaa", epoch: 1 }))
    .then(all { assert(s.visible == ""), assert(s.cache.contains("aaaaaaaaaaaaaaaa")), assert(safety), s' = s })
  run replaceAndBranchTest = init
    .then(navigate(serialize(deviceTarget("demo"), ""), false))
    .then(navigate(serialize(driveTarget("demo", 0, 2), ""), true))
    .then(all { assert(s.history.length() == 2), assert(s.target.start == 0), s' = s })
    .then(back).then(navigate(serialize({ ...home, page: "referrals" }, ""), false))
    .then(all { assert(s.cursor == 1), assert(s.history.length() == 2), assert(safety), s' = s })
  run invalidPathTest = init
    .then(navigate({ path: List("demo", routeId, "4", "0"), modal: "", share: "" }, false))
    .then(all { assert(s.target == missing), assert(safety), s' = s })
  run legacyConversionTest = init
    .then(navigate({ path: List("demo", "0", "2"), modal: "", share: "share" }, false)).then(request)
    .then(resolve({ device: "demo", epoch: 1 }))
    .then(all { assert(s.target == driveTarget("demo", -1, -1)), assert(s.history.length() == 2),
      assert(s.history[s.cursor].share == "share"), assert(safety), s' = s })
  run staleLegacyConversionTest = init
    .then(navigate({ path: List("demo", "0", "2"), modal: "", share: "" }, false)).then(request)
    .then(navigate(serialize({ ...deviceTarget("demo"), page: "prime" }, ""), false))
    .then(resolve({ device: "demo", epoch: 1 }))
    .then(all { assert(s.target.page == "prime"), assert(s.history.length() == 3), assert(safety), s' = s })
  run routeChangeKeepsDeviceDataTest = init
    .then(navigate(serialize(driveTarget("demo", -1, -1), ""), false)).then(request)
    .then(resolve({ device: "demo", epoch: 1 }))
    .then(navigate(serialize({ ...driveTarget("demo", -1, -1), route: otherRouteId }, ""), false))
    .then(all { assert(s.resourceEpoch == 2), assert(s.visible == "demo"), assert(safety), s' = s })
  // Negative control: an unguarded response must fail the data-isolation invariant.
  run rejectsWrongDeviceTest = init.then(navigate(serialize(deviceTarget("demo"), ""), false))
    .then(s' = { ...s, visible: "aaaaaaaaaaaaaaaa" })
    .then(all { assert(not(noWrongDevice)), s' = s })
}
