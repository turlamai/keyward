#!/usr/bin/env python3
"""Gate the glaze route surface against rivet-schema.json (#34 S1).

rivet-schema.json is the single source of the RPC contract. The glaze
carrier (host/main.rkt) must expose every page-reachable RPC 1:1 — same
names, same argument order, camelCase DTO keys, matching scalar types — and
nothing else. Structured DTOs (records/lists) ride the transport's Value
boundary; their shapes are enforced by rivet/bridge's schema codec from the
same file.

HOST_ONLY RPCs answer a value (entry-get, keypair-export): the carrier calls
them internally for the clipboard path and must never route them to the page,
because page code could then read signing keys. The gate fails on a missing
page RPC, on an extra route, and on a routed HOST_ONLY RPC.

Boundary conventions (declared on #13):
  * Bytes arguments/results ride base64 strings  -> glaze scalar String
  * enums project as record kinds in the schema  -> glaze scalar String
  * Void / record / list / Any                   -> glaze scalar Value

Run after any schema/route change (host-ci.yml runs it on every PR):

    python scripts/check-rpc-surface.py
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# RPCs that return secret material. The carrier is their only caller.
HOST_ONLY = {"entry-get", "keypair-export"}


def camel(name: str) -> str:
    parts = name.split("-")
    return parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])


def main() -> int:
    rivet = json.loads((ROOT / "rivet-schema.json").read_text(encoding="utf-8"))
    glaze = json.loads((ROOT / "glaze-schema.json").read_text(encoding="utf-8"))
    errors: list[str] = []
    enum_names = {e["name"] for e in rivet.get("enums", [])}

    def type_ok(rivet_t: dict, glaze_t: dict, where: str) -> None:
        rk = rivet_t["kind"]
        gk = glaze_t.get("kind")
        if rk == "scalar" and rivet_t["name"] in ("String", "Int64", "Bool"):
            if gk != "scalar" or glaze_t.get("name") != rivet_t["name"]:
                errors.append(f"{where}: expected scalar {rivet_t['name']}, got {glaze_t}")
            return
        if rk == "scalar" and rivet_t["name"] == "Bytes":
            if gk != "scalar" or glaze_t.get("name") != "String":
                errors.append(f"{where}: Bytes must ride base64 String, got {glaze_t}")
            return
        if rk == "record" and rivet_t["name"] in enum_names:
            if gk != "scalar" or glaze_t.get("name") != "String":
                errors.append(f"{where}: enum must ride String, got {glaze_t}")
            return
        if rk == "optional":
            if gk != "optional":
                errors.append(f"{where}: expected optional, got {glaze_t}")
                return
            type_ok(rivet_t["element"], glaze_t["element"], where + ".element")
            return
        # record / list / Any / Void ride GValue at the boundary.
        if gk != "scalar" or glaze_t.get("name") != "Value":
            errors.append(f"{where}: expected Value boundary for {rivet_t}, got {glaze_t}")

    rpc_names = {r["name"] for r in rivet["rpcs"]}
    route_paths = {
        r["path"].lstrip("/")
        for r in glaze["routes"]
        if r["method"] == "POST" and r["path"].startswith("/api/rpc/")
    }
    expected_paths = {f"api/rpc/{n}" for n in rpc_names - HOST_ONLY}
    for missing in sorted(expected_paths - route_paths):
        errors.append(f"missing glaze route: {missing}")
    for extra in sorted(route_paths - expected_paths):
        errors.append(f"glaze route not in rivet-schema.json: {extra}")
    for leaked in sorted(route_paths & {f"api/rpc/{n}" for n in HOST_ONLY}):
        errors.append(f"HOST_ONLY RPC routed to the page: {leaked}")
    for unknown in sorted(HOST_ONLY - rpc_names):
        errors.append(f"HOST_ONLY names an RPC that is not in rivet-schema.json: {unknown}")

    commands = {c["name"]: c for c in glaze["schema"]["commands"]}
    for rpc in rivet["rpcs"]:
        name = rpc["name"]
        if name in HOST_ONLY:
            binding = "rpc" + camel(name)[:1].upper() + camel(name)[1:]
            if binding in commands:
                errors.append(f"{name}: HOST_ONLY RPC has a page command binding {binding}")
            continue
        joined = camel(name)
        binding = "rpc" + joined[:1].upper() + joined[1:]
        cmd = commands.get(binding)
        if cmd is None:
            errors.append(f"{name}: no glaze command binding {binding}")
            continue
        params = cmd["parameters"]
        args = rpc["arguments"]
        if len(params) != len(args):
            errors.append(f"{name}: arity {len(params)} != schema {len(args)}")
            continue
        for a, p in zip(args, params):
            want = camel(a["name"])
            if p["name"] != want:
                errors.append(f"{name}: parameter {p['name']} != {want}")
            type_ok(a["type"], p["type"], f"{name}.{want}")
        type_ok(rpc["result"], cmd["result"], f"{name} result")

    if errors:
        print("RPC SURFACE GATE FAILED:")
        for e in errors:
            print(" -", e)
        return 1
    print(f"RPC surface gate PASS: {len(rpc_names - HOST_ONLY)} page RPCs aligned "
          f"(routes + typed commands), {len(HOST_ONLY)} carrier-only")
    return 0


if __name__ == "__main__":
    sys.exit(main())
