"""Shared helpers for the LAN update tools (duo-update-bundle, duo-update-signers). Run with python3 -I."""
import base64, hashlib, json, os, subprocess, sys, tempfile, time

ROOTS = ["core", "games", "arcade", "tests"]
ROOT_FILES = ["arcade.tscn"]
# Carried separately (root-signed on their own) and never part of a bundle's file list.
PROTECTED = {"core/lan_update/signers.json", "core/lan_update/signers.sig"}
MAX_FILES, MAX_FILE, MAX_TOTAL = 4000, 8 << 20, 64 << 20
ROOT_NAME = "steam-machine"


def key_dir():
    return os.environ.get("DUO_UPDATE_KEY_DIR", os.path.expanduser("~/.config/duo-arena/update-key"))


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def sign(data: bytes) -> str:
    d = key_dir()
    priv = os.path.join(d, "private.pem")
    if not os.path.exists(priv):
        die(f"no signing key in {d}: this machine is not an update signer (duo-update-keygen NAME)")
    st = os.stat(priv)
    if st.st_mode & 0o077:
        die(f"{priv} is readable by others (mode {oct(st.st_mode & 0o777)}): chmod 600 it first")
    with tempfile.NamedTemporaryFile() as f:
        f.write(data)
        f.flush()
        sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", priv, f.name], check=True, capture_output=True).stdout
    return base64.b64encode(sig).decode()


def signer_name():
    with open(os.path.join(key_dir(), "signer")) as f:
        return f.read().strip()


def my_public_pem():
    with open(os.path.join(key_dir(), "public.pem")) as f:
        return f.read().strip()


def write_atomic(path, data: bytes):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)


def bundle_files(game):
    """Every file an update carries: core/ games/ arcade/ tests/ + arcade.tscn, without .uid/.import, dotfiles and temps."""
    out = []
    for r in ROOTS:
        for dp, dns, fns in os.walk(os.path.join(game, r)):
            dns[:] = sorted(d for d in dns if not d.startswith("."))
            for fn in fns:
                if fn.startswith(".") or fn.endswith((".uid", ".import", ".tmp")):
                    continue
                rel = os.path.relpath(os.path.join(dp, fn), game)
                if rel not in PROTECTED:
                    out.append(rel)
    out += [f for f in ROOT_FILES if os.path.exists(os.path.join(game, f))]
    return sorted(out)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 16), b""):
            h.update(b)
    return h.hexdigest()


def content_hash(files: dict) -> str:
    """Hash of the whole file list (path + sha256), so two bundles with the same code compare equal."""
    return hashlib.sha256("".join(f"{p} {files[p]['sha256']}\n" for p in sorted(files)).encode()).hexdigest()


def canonical(obj) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":")).encode()
