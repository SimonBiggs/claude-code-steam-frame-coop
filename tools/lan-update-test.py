"""LAN update multi-machine tests (core/lan_update.gd). Run: tools/lan-update-test [test ...]  (python3 -I)

Each simulated machine is its own headless `godot-test` process with its OWN temp copy of the game directory and its own
user data, all on one private random DUO_PORT (never the family's 7777). Never touches ~/DuoArena, the live game or
real devices. Test signing keys are made in the temp dir (never the real ~/.config/duo-arena/update-key).
Machines: at most 3 at once. "Attacker" machines run a patched copy of core/lan_update.gd that skips its own checks
(what a malicious machine on the network would do) so the RECEIVER's checks are what's tested.
"""
import hashlib, json, os, random, re, shutil, signal, subprocess, sys, time

TOOLS = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(TOOLS)
PORT = int(os.environ.get("DUO_PORT", random.randint(20000, 29990)))
W = f"/tmp/lanupd-{PORT}"
NOW = int(time.time())
results = []
OLD_FILE = "games/duo_arena/lan_update_old_note.md"
procs = []


def sh(*a, env=None, check=True):
    e = dict(os.environ)
    e.update(env or {})
    r = subprocess.run(a, env=e, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise SystemExit(f"FAILED: {' '.join(a)}\n{r.stdout}{r.stderr}")
    return r.stdout + r.stderr


def keys(name):
    d = f"{W}/keys/{name}"
    if not os.path.exists(d + "/private.pem"):
        sh(f"{TOOLS}/duo-update-keygen", name, env={"DUO_UPDATE_KEY_DIR": d})
    return d


def sign(game, signer, ts):
    return sh(f"{TOOLS}/duo-update-bundle", game, env={"DUO_UPDATE_KEY_DIR": keys(signer), "DUO_UPDATE_TIMESTAMP": str(ts)})


def signers(game, cmd, *args, ts):
    return sh(f"{TOOLS}/duo-update-signers", game, cmd, *args, env={"DUO_UPDATE_KEY_DIR": keys("steam-machine"), "DUO_UPDATE_TIMESTAMP": str(ts)})


def copy(src, dst):
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst, symlinks=True)
    return dst


def tree_hash(game):
    """Hash of everything an update may touch (to prove 'nothing written')."""
    h = hashlib.sha256()
    for root in ["core", "games", "arcade", "tests", "addons"]:
        for dp, dns, fns in sorted(os.walk(os.path.join(game, root))):
            dns.sort()
            for fn in sorted(fns):
                p = os.path.join(dp, fn)
                h.update(os.path.relpath(p, game).encode())
                h.update(open(p, "rb").read())
    for f in ["arcade.tscn", "project.godot"]:
        h.update(open(os.path.join(game, f), "rb").read())
    return h.hexdigest()


def manifest_ver(game):
    try:
        m = json.load(open(os.path.join(game, ".update/manifest.json")))
        return f"{m['timestamp']}-{m['signer']}-{m['content'][:8]}"
    except Exception:
        return "none"


def start(name, game, host, scene=None, env=None):
    e = {"DUO_PORT": str(PORT), "XDG_DATA_HOME": f"{W}/xdg-{name}", "DUO_MACHINE_KIND": "deck", "DUO_UPDATE_RECEIVE": "1"}
    if host:
        e["DUO_HOST"] = "1"
    else:
        e["DUO_JOIN"] = "127.0.0.1"
    e.update(env or {})
    full = dict(os.environ)
    for k in ["DUO_HOST", "DUO_JOIN", "DUO_SOLO", "ARCADE_GAME"]:
        full.pop(k, None)
    full.update(e)
    full = {k: v for k, v in full.items() if v is not None}
    log = open(f"{W}/{name}.log", "w")
    args = ["timeout", "150", "godot-test", "--headless", "--path", game] + ([scene] if scene else [])
    p = subprocess.Popen(args, env=full, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    p.name, p.logpath = name, f"{W}/{name}.log"
    procs.append(p)
    return p


def stop(*ps):
    for p in ps:
        if p.poll() is None:
            try:
                os.killpg(p.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    for p in ps:
        try:
            p.wait(10)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)
        if p in procs:
            procs.remove(p)


def log(p):
    return open(p.logpath, errors="replace").read()


def wait_for(p, pattern, secs=60):
    end = time.time() + secs
    while time.time() < end:
        m = re.search(pattern, log(p))
        if m:
            return m.group(0)
        if p.poll() is not None:
            break
        time.sleep(0.5)
    return None


def ok(test, cond, what, proof=""):
    results.append((test, bool(cond), what, proof))
    print(f"  {'PASS' if cond else 'FAIL'} {what}" + (f"\n        {proof}" if proof else ""))


def script_errors(p):
    return [l for l in log(p).splitlines() if "SCRIPT ERROR" in l]


# --- Fixtures -------------------------------------------------------------------

def setup():
    if os.path.exists(W):
        shutil.rmtree(W)
    os.makedirs(W)
    base = f"{W}/base"
    shutil.copytree(REPO, base, ignore=shutil.ignore_patterns(".git", ".dev", ".update", ".claude", "tools", "docs"))
    # The test copies trust the TEST root key (never the real one) and list the test Deck key as a code signer.
    shutil.copy(keys("steam-machine") + "/public.pem", base + "/addons/lan_update/root.pub.pem")
    signers(base, "init", ts=NOW - 5000)
    signers(base, "add", "simon-deck", keys("simon-deck") + "/public.pem", ts=NOW - 4900)
    keys("evil")
    with open(base + "/" + OLD_FILE, "w") as f:  # version N+1 deletes it
        f.write("old note\n")
    sign(base, "steam-machine", NOW - 3000)  # version N
    return base


def make_newer(src, dst, signer, ts, tag):
    """A copy of src with changed, added and deleted files, signed as a newer version."""
    g = copy(src, dst)
    with open(g + "/arcade/arcade.gd", "a") as f:
        f.write(f"\n# lan-update-test {tag}\n")
    with open(g + "/core/lan_update_test_marker.gd", "w") as f:
        f.write(f'extends RefCounted\nconst TAG := "{tag}"\n')
    os.remove(g + "/" + OLD_FILE)
    sign(g, signer, ts)
    return g


def attacker(g):
    """Patch a copy so it serves whatever is in its folder without checking it (a malicious machine)."""
    p = g + "/core/lan_update.gd"
    s = open(p).read()
    s = s.replace("func check_manifest(text: String, sig: String, keys: Dictionary) -> Dictionary:\n",
                  "func check_manifest(text: String, sig: String, keys: Dictionary) -> Dictionary:\n"
                  "\tif OS.has_environment(\"EVIL\"):\n\t\treturn {\"m\": JSON.parse_string(text)}\n", 1)
    s = s.replace("\t\t\tif FileAccess.get_sha256(path) != str(mine.m.files[rel].sha256):",
                  "\t\t\tif not OS.has_environment(\"EVIL\") and FileAccess.get_sha256(path) != str(mine.m.files[rel].sha256):", 1)
    assert "EVIL" in s
    open(p, "w").write(s)
    return g


def same_code(a, b):
    """Every bundle file identical."""
    ma = json.load(open(a + "/.update/manifest.json"))["files"]
    for rel, e in ma.items():
        p = os.path.join(b, rel)
        if not os.path.exists(p) or hashlib.sha256(open(p, "rb").read()).hexdigest() != e["sha256"]:
            return f"{rel} differs"
    return ""


# --- Tests ----------------------------------------------------------------------

def t_update(base):
    """(a) host has N+1, joiner N: joiner fetches only the changed files, verifies, applies, hot-reloads."""
    print("(a) host N+1 -> joiner N")
    h = make_newer(base, f"{W}/a-host", "steam-machine", NOW - 2000, "a")
    j = copy(base, f"{W}/a-join")
    ph = start("a-host", h, True)
    time.sleep(3)
    pj = start("a-join", j, False)
    line = wait_for(pj, r"LanUpdate: UPDATED to \S+.*", 60)
    ok("a", line, "joiner updated", line or log(pj)[-800:])
    ok("a", manifest_ver(j) == manifest_ver(h), f"same version on both ({manifest_ver(j)})")
    ok("a", same_code(h, j) == "", "every file identical, the deleted file removed: " + (same_code(h, j) or "yes"))
    ok("a", not os.path.exists(j + "/" + OLD_FILE) and "1 removed" in (line or ""), "file deleted in N+1 removed")
    fetched = wait_for(pj, r"\d+ of \d+ files to fetch", 1)
    ok("a", fetched and int(fetched.split()[0]) <= 3, f"only changed files fetched ({fetched})")
    rl = wait_for(pj, r"reloaded res://arcade/arcade.gd", 15)
    ok("a", rl, "gdev bridge hot-reloaded the new arcade.gd", rl or "")
    ok("a", os.path.exists(j + "/.update/backup/files/arcade/arcade.gd"), "previous version kept for rollback")
    ok("a", not script_errors(pj) and not script_errors(ph), "no SCRIPT ERRORs")
    stop(ph, pj)


def refusal(test, label, host_dir, expect, env_host=None, env_join=None, join_dir=None):
    j = copy(join_dir or f"{W}/base", f"{W}/{test}-join")
    before = tree_hash(j)
    vbefore = manifest_ver(j)
    ph = start(f"{test}-host", host_dir, True, env=env_host)
    time.sleep(3)
    pj = start(f"{test}-join", j, False, env=env_join)
    line = wait_for(pj, r"LanUpdate: REFUSED .*" + expect + ".*", 45)
    time.sleep(2)
    ok(test, line, label, line or log(pj)[-600:])
    ok(test, tree_hash(j) == before and manifest_ver(j) == vbefore, "nothing written to the joiner's game")
    ok(test, not os.path.exists(j + "/.update/staging"), "staged files dropped")
    ok(test, "UPDATED" not in log(pj), "joiner did not update")
    stop(ph, pj)


def t_tamper(base):
    """(b) tampered file / bad signature / unknown signer / forged signer list / file outside the game: refused."""
    print("(b) tampered and forged updates")
    g = attacker(make_newer(base, f"{W}/b1-host", "steam-machine", NOW - 2000, "b1"))
    data = bytearray(open(g + "/arcade/arcade.gd", "rb").read())  # same size, one byte different
    data[-2] = ord("X") if data[-2] != ord("X") else ord("Y")
    open(g + "/arcade/arcade.gd", "wb").write(bytes(data))
    refusal("b1", "file changed after signing: refused", g, "doesn't match its signed hash", env_host={"EVIL": "1"})
    g = attacker(make_newer(base, f"{W}/b2-host", "steam-machine", NOW - 2000, "b2"))
    sig = open(g + "/.update/manifest.sig").read()
    open(g + "/.update/manifest.sig", "w").write(sig[:40] + ("A" if sig[40] != "A" else "B") + sig[41:])
    refusal("b2", "bad signature: refused", g, "bad signature", env_host={"EVIL": "1"})
    g = attacker(make_newer(base, f"{W}/b3-host", "steam-machine", NOW - 2000, "b3"))
    m = json.load(open(g + "/.update/manifest.json"))
    m["signer"] = "evil"
    open(g + "/.update/manifest.json", "w").write(json.dumps(m, sort_keys=True, separators=(",", ":")))
    sh("bash", "-c", f"openssl dgst -sha256 -sign {keys('evil')}/private.pem {g}/.update/manifest.json | base64 -w0 > {g}/.update/manifest.sig")
    refusal("b3", "signed by an unknown key: refused", g, "unknown or revoked signer 'evil'", env_host={"EVIL": "1"})
    # A Deck (code signer) tries to add a signer: it rewrites the signer list and signs it with its own key.
    g = attacker(make_newer(base, f"{W}/b4-host", "simon-deck", NOW - 2000, "b4"))
    lst = json.load(open(g + "/core/lan_update/signers.json"))
    lst["signers"]["evil"] = open(keys("evil") + "/public.pem").read().strip()
    lst["issued"] += 100
    open(g + "/core/lan_update/signers.json", "w").write(json.dumps(lst, sort_keys=True, separators=(",", ":")))
    sh("bash", "-c", f"openssl dgst -sha256 -sign {keys('simon-deck')}/private.pem {g}/core/lan_update/signers.json | base64 -w0 > {g}/core/lan_update/signers.sig")
    refusal("b4", "Deck key changing the signer list: refused", g, "signer list is not signed by the root", env_host={"EVIL": "1"})
    # A correctly signed manifest that reaches outside the game code (the gdev addon): refused by the receiver.
    g = attacker(copy(base, f"{W}/b5-host"))
    m = json.load(open(g + "/.update/manifest.json"))
    p = g + "/addons/gdev/bridge.gd"
    m["files"]["addons/gdev/bridge.gd"] = {"sha256": hashlib.sha256(open(p, "rb").read()).hexdigest(), "size": os.path.getsize(p)}
    m["timestamp"] = NOW - 2000
    lines = sorted(f"{k} {v['sha256']}\n" for k, v in m["files"].items())
    m["content"] = hashlib.sha256("".join(lines).encode()).hexdigest()
    open(g + "/.update/manifest.json", "w").write(json.dumps(m, sort_keys=True, separators=(",", ":")))
    sh("bash", "-c", f"openssl dgst -sha256 -sign {keys('steam-machine')}/private.pem {g}/.update/manifest.json | base64 -w0 > {g}/.update/manifest.sig")
    refusal("b5", "signed manifest touching addons/gdev: refused", g, "file outside the game code: addons/gdev/bridge.gd", env_host={"EVIL": "1"})


def t_source(base):
    """(c) offers from a non-host machine, and from a public address: refused."""
    print("(c) offers from the wrong machine / a public address")
    # Public address: the joiner sees its host as 8.8.8.8.
    g = make_newer(base, f"{W}/c1-host", "steam-machine", NOW - 2000, "c1")
    refusal("c1", "update from a public address (8.8.8.8): refused", g, "not a home-network address",
            env_join={"DUO_UPDATE_TEST_PEER_IP": "8.8.8.8"})
    # Non-host: an attacker JOINER sends version offers and an unasked-for manifest straight to another joiner.
    h = copy(base, f"{W}/c2-host")
    ev = attacker(make_newer(base, f"{W}/c2-evil", "steam-machine", NOW - 2000, "c2"))
    p = ev + "/core/lan_update.gd"
    s = open(p).read()
    s = s.replace("func _process(delta: float) -> void:\n",
                  "func _process(delta: float) -> void:\n"
                  "\tif OS.has_environment(\"EVIL\") and _enet() != null and Engine.get_process_frames() % 60 == 0 and not mine.is_empty():\n"
                  "\t\tfor p in multiplayer.get_peers():\n"
                  "\t\t\tif p != 1:\n"
                  "\t\t\t\t_u_ver.rpc_id(p, int(my_ver()[0]), str(my_ver()[1]), str(my_ver()[2]))\n"
                  "\t\t\t\t_u_manifest.rpc_id(p, mine.text, mine.sig, \"\", \"\")\n", 1)
    open(p, "w").write(s)
    j = copy(base, f"{W}/c2-join")
    before = tree_hash(j)
    ph = start("c2-host", h, True, env={"DUO_UPDATE_RECEIVE": "0"})  # the host keeps N (it would take a joiner's newer version)
    time.sleep(3)
    pj = start("c2-join", j, False)
    time.sleep(3)
    pe = start("c2-evil", ev, False, env={"EVIL": "1"})
    l1 = wait_for(pj, r"LanUpdate: REFUSED update offer .*not the lobby host", 45)
    l2 = wait_for(pj, r"LanUpdate: REFUSED unasked-for manifest .*", 10)
    ok("c2", l1, "version offer from another joiner (not the host): refused", l1 or log(pj)[-600:])
    ok("c2", l2, "unasked-for manifest from another joiner: refused", l2 or "")
    ok("c2", tree_hash(j) == before and "UPDATED" not in log(pj), "nothing written to the joiner's game")
    stop(ph, pj, pe)


def t_three_decks(base):
    """(d) + Simon's 'Deck hosts, Steam Machine off': 3 Decks, no Steam Machine process. A has N+1 signed by the DECK
    key; B hosts with N; A joins -> B updates from A (newest wins); C joins -> C updates from B (relay)."""
    print("(d) three Decks, no Steam Machine: newest wins + relay of a Deck-signed update")
    a = make_newer(base, f"{W}/d-A", "simon-deck", NOW - 1500, "d")
    b = copy(base, f"{W}/d-B")
    c = copy(base, f"{W}/d-C")
    pb = start("d-B", b, True)
    time.sleep(3)
    pa = start("d-A", a, False)
    lb = wait_for(pb, r"LanUpdate: UPDATED to \S+ \(signed by simon-deck\) from \S+.*", 60)
    ok("d", lb, "host B updated from joiner A (newer wins)", lb or log(pb)[-800:])
    pc = start("d-C", c, False)
    lc = wait_for(pc, r"LanUpdate: UPDATED to \S+ \(signed by simon-deck\) from \S+.*", 60)
    ok("d", lc, "joiner C updated from host B (B relays the Deck-signed update it received)", lc or log(pc)[-800:])
    ok("d", manifest_ver(a) == manifest_ver(b) == manifest_ver(c), f"all three on {manifest_ver(a)}")
    ok("d", same_code(a, b) == "" and same_code(a, c) == "", "same code on all three")
    ok("d", "fetching update" not in log(pa), "A (newest) fetched nothing")
    ok("d", not any(script_errors(p) for p in (pa, pb, pc)), "no SCRIPT ERRORs")
    stop(pa, pb, pc)


def t_revoke(base):
    """Root revokes the Deck key: once a machine has the root's newer signer list, Deck-signed updates are refused,
    even a newer one that still carries the old list."""
    print("(g) the root revokes the Deck key")
    r = copy(base, f"{W}/g-root")
    deck_old = make_newer(base, f"{W}/g-deck", "simon-deck", NOW - 500, "g-deck")  # made before the revocation, newer stamp
    signers(r, "revoke", "simon-deck", ts=NOW - 1000)
    with open(r + "/core/lan_update_test_marker.gd", "w") as f:
        f.write('extends RefCounted\nconst TAG := "revoked"\n')
    sign(r, "steam-machine", NOW - 1000)
    j = copy(base, f"{W}/g-join")
    pr = start("g-root", r, True)
    time.sleep(3)
    pj = start("g-join", j, False)
    l1 = wait_for(pj, r"LanUpdate: adopted the root's signer list.*", 60)
    ok("g", l1 and wait_for(pj, r"UPDATED to", 5), "joiner took the root's update and its new signer list", l1 or log(pj)[-600:])
    stop(pr, pj)
    refusal("g2", "Deck-signed update after the revocation: refused", deck_old, "unknown or revoked signer 'simon-deck'",
            join_dir=j)


def t_rollback(base):
    """(e) a signed update with a broken script: applied, the script check fails, everything is rolled back, and the
    bad version isn't fetched again. Plus the boot guard: a crash loop after an update rolls back on its own."""
    print("(e) broken update -> rollback")
    h = make_newer(base, f"{W}/e-host", "steam-machine", NOW - 2000, "e")
    with open(h + "/core/lan_update_test_marker.gd", "w") as f:
        f.write("extends RefCounted\nfunc broken(:\n")
    sign(h, "steam-machine", NOW - 2000)
    j = copy(base, f"{W}/e-join")
    before, vbefore = tree_hash(j), manifest_ver(j)
    ph = start("e-host", h, True)
    time.sleep(3)
    pj = start("e-join", j, False)
    line = wait_for(pj, r"LanUpdate: ROLLED BACK .*", 60)
    ok("e", line, "broken update rolled back", line or log(pj)[-800:])
    time.sleep(8)
    ok("e", tree_hash(j) == before and manifest_ver(j) == vbefore, "joiner's game is exactly the old version again")
    ok("e", log(pj).count("fetching update") == 1, "the bad version is not fetched again")
    stop(ph, pj)
    # Boot guard: the arcade itself was broken by an update and the game restarted.
    g = copy(base, f"{W}/e2")
    os.makedirs(g + "/.update/backup/files/arcade", exist_ok=True)
    shutil.copy(g + "/arcade/arcade.gd", g + "/.update/backup/files/arcade/arcade.gd")
    open(g + "/arcade/arcade.gd", "w").write("extends Node\nfunc broken(:\n")
    json.dump({"from": "good", "to": "broken", "replaced": ["arcade/arcade.gd"], "added": []}, open(g + "/.update/backup/restore.json", "w"))
    json.dump({"to": "broken", "attempts": 0}, open(g + "/.update/boot_pending.json", "w"))
    p = start("e2", g, True)
    line = wait_for(p, r"LanUpdate: ROLLED BACK .*", 40)
    ok("e2", line, "boot guard: arcade not running after an update -> rolled back", line or log(p)[-800:])
    ok("e2", open(g + "/arcade/arcade.gd").read() == open(base + "/arcade/arcade.gd").read(), "arcade.gd restored")
    ok("e2", wait_for(p, r"LanUpdate: ready: version", 20), "arcade starts after the rollback")
    stop(p)


def t_midgame(base):
    """(f) an update verified while a game starts is applied only back in the arcade menu."""
    print("(f) mid-game -> deferred to the menu")
    h = make_newer(base, f"{W}/f-host", "steam-machine", NOW - 2000, "f")
    j = copy(base, f"{W}/f-join")
    ph = start("f-host", h, True)
    time.sleep(3)
    pj = start("f-join", j, False, scene="res://tests/lan_update_bot.tscn")
    res = wait_for(pj, r"BOT RESULT: \w+.*", 90)
    ok("f", res and "PASS" in res, "deferred during the game, applied in the menu",
       " / ".join(l for l in log(pj).splitlines() if l.startswith("BOT")))
    stop(ph, pj)


def t_dev(base):
    """A git checkout (the TV's live copy) serves but never takes updates."""
    print("(h) dev checkout never receives")
    h = make_newer(base, f"{W}/h-host", "steam-machine", NOW - 2000, "h")
    j = copy(base, f"{W}/h-join")
    os.makedirs(j + "/.git")
    before = tree_hash(j)
    ph = start("h-host", h, True)
    time.sleep(3)
    pj = start("h-join", j, False, env={"DUO_UPDATE_RECEIVE": None})
    line = wait_for(pj, r"LanUpdate: peer \d+ has \S+, but this is a dev checkout.*", 45)
    ok("h", line and tree_hash(j) == before, "dev checkout left alone", line or log(pj)[-500:])
    stop(ph, pj)


TESTS = {"a": t_update, "b": t_tamper, "c": t_source, "d": t_three_decks, "e": t_rollback, "f": t_midgame,
         "g": t_revoke, "h": t_dev}

if __name__ == "__main__":
    want = sys.argv[1:] or list(TESTS)
    print(f"LAN update tests on private DUO_PORT {PORT}, work dir {W}")
    base = setup()
    try:
        for t in want:
            TESTS[t](base)
    finally:
        stop(*list(procs))
    bad = [r for r in results if not r[1]]
    print(f"\nBOT RESULT: {'PASS' if not bad else 'FAIL'} ({len(results) - len(bad)}/{len(results)} checks)")
    for r in bad:
        print("  FAILED:", r[0], r[2])
    sys.exit(1 if bad else 0)
