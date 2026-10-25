import json, os, sys, time
import importlib.util
spec = importlib.util.spec_from_file_location("lib", os.path.join(os.path.dirname(os.path.abspath(__file__)), "duo-update-lib.py"))
lib = importlib.util.module_from_spec(spec); spec.loader.exec_module(lib)

a = sys.argv[1:]
if len(a) < 2:
    lib.die("usage: duo-update-signers REPO init|list|add NAME PUBLIC.pem|revoke NAME")
repo, cmd = os.path.abspath(a[0]), a[1]
path = os.path.join(repo, "core/lan_update/signers.json")
try:
    cur = json.load(open(path))
except Exception:
    cur = {"format": 1, "issued": 0, "root": lib.ROOT_NAME, "signers": {}}
if cmd == "list":
    print("root:", lib.ROOT_NAME, "(addons/lan_update/root.pub.pem)")
    for n in sorted(cur["signers"]):
        print("signer:", n)
    print("issued:", cur.get("issued"))
    sys.exit(0)
root_pem = open(os.path.join(repo, "addons/lan_update/root.pub.pem")).read().strip()
if lib.my_public_pem() != root_pem:
    lib.die("only the ROOT signer (the Steam Machine's key, pinned in addons/lan_update/root.pub.pem) can change the signer list")
signers = dict(cur["signers"])
if cmd == "add" and len(a) == 4:
    name = a[2]
    if name == lib.ROOT_NAME:
        lib.die("that's the root's name")
    signers[name] = open(a[3]).read().strip()
elif cmd == "revoke" and len(a) == 3:
    if signers.pop(a[2], None) is None:
        lib.die(f"no signer '{a[2]}'")
elif cmd != "init":
    lib.die("usage: duo-update-signers REPO init|list|add NAME PUBLIC.pem|revoke NAME")
issued = int(os.environ.get("DUO_UPDATE_TIMESTAMP", time.time()))
issued = max(issued, int(cur.get("issued", 0)) + 1)
new = {"format": 1, "issued": issued, "root": lib.ROOT_NAME, "signers": signers}
data = lib.canonical(new)
lib.write_atomic(os.path.join(repo, "core/lan_update/signers.sig"), lib.sign(data).encode())
lib.write_atomic(path, data)
print(f"signer list issued {issued}: root {lib.ROOT_NAME} + {sorted(signers) or 'no other signers'}")
