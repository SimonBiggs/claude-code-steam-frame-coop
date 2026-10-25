import json, os, sys, time
import importlib.util
spec = importlib.util.spec_from_file_location("lib", os.path.join(os.path.dirname(os.path.abspath(__file__)), "duo-update-lib.py"))
lib = importlib.util.module_from_spec(spec); spec.loader.exec_module(lib)

if len(sys.argv) != 2:
    lib.die("usage: duo-update-bundle GAME_DIR")
game = os.path.abspath(sys.argv[1])
root_pem_path = os.path.join(game, "addons/lan_update/root.pub.pem")
if not os.path.exists(root_pem_path):
    lib.die(f"{root_pem_path} missing: this game has no LAN updates")
me, my_pem = lib.signer_name(), lib.my_public_pem()
root_pem = open(root_pem_path).read().strip()
if my_pem == root_pem:
    if me != lib.ROOT_NAME:
        lib.die(f"this key is the root key but its signer name is '{me}', not '{lib.ROOT_NAME}'")
else:
    try:
        signers = json.load(open(os.path.join(game, "core/lan_update/signers.json")))["signers"]
    except Exception:
        signers = {}
    if signers.get(me, "").strip() != my_pem:
        lib.die(f"signer '{me}' is not in the game's trusted list (core/lan_update/signers.json): on the Steam Machine run\n"
                f"  duo-update-signers <repo> add {me} <this machine's public.pem>   then pull that change here")
files = {}
total = 0
for rel in lib.bundle_files(game):
    p = os.path.join(game, rel)
    size = os.path.getsize(p)
    if size > lib.MAX_FILE:
        lib.die(f"{rel} is {size} bytes: over the {lib.MAX_FILE} limit for LAN updates")
    total += size
    files[rel] = {"sha256": lib.sha256(p), "size": size}
if len(files) > lib.MAX_FILES or total > lib.MAX_TOTAL:
    lib.die(f"bundle too big: {len(files)} files, {total} bytes")
meta = os.path.join(game, ".update")
ts = int(os.environ.get("DUO_UPDATE_TIMESTAMP", time.time()))
try:  # versions only go up on this machine, even if the clock went back
    prev = json.load(open(os.path.join(meta, "manifest.json")))
    if not os.environ.get("DUO_UPDATE_TIMESTAMP"):
        ts = max(ts, int(prev["timestamp"]) + 1)
except Exception:
    pass
manifest = {"format": 1, "app": "duo-arena", "timestamp": ts, "signer": me, "content": lib.content_hash(files),
            "created": time.strftime("%Y-%m-%d %H:%M:%S %z"), "files": files}
data = lib.canonical(manifest)
sig = lib.sign(data)
lib.write_atomic(os.path.join(meta, "manifest.sig"), sig.encode())
lib.write_atomic(os.path.join(meta, "manifest.json"), data)
print(f"signed LAN update {ts}-{me}-{manifest['content'][:8]}: {len(files)} files, {total // 1024} KB")
