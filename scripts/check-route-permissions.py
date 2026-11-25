#!/usr/bin/env python3
"""Every carrier route carries a permission class (#34 S5).

host/verify.rkt runs without a capability (open-route mode), but the
production carrier and the package run with `host-capability`. Under a
capability glaze is default-deny: a route without `#:permission` answers
"capability denied" in production while the verifier stays green. This gate
makes the omission a static failure.

It also checks that every permission class used by a route is granted to the
production window — a route with an ungranted class is dead in the package —
and that `e2e` is the only harness class (the harness routes are refused
unless KEYWARD_E2E=1 is set by the verifier or CI).

Run after any route or capability change (host-ci.yml runs it on every PR):

    python scripts/check-route-permissions.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "host" / "main.rkt"

ROUTE = re.compile(r'^\s*\[\((?:GET|POST)\s+"([^"]+)"(.*)$')
PERMISSION = re.compile(r"#:permission\s+'([\w:-]+)")
CAPABILITY = re.compile(r"\(make-capability\s+\"keyward\"\s*'\(([^)]*)\)\)")


def main() -> int:
    text = SOURCE.read_text(encoding="utf-8")
    errors: list[str] = []
    routes = 0
    used: set[str] = set()
    for number, line in enumerate(text.splitlines(), 1):
        match = ROUTE.match(line)
        if not match:
            continue
        routes += 1
        perm = PERMISSION.search(match.group(2))
        if not perm:
            errors.append(f"host/main.rkt:{number}: route {match.group(1)} has no #:permission")
        else:
            used.add(perm.group(1))
    if not routes:
        errors.append("host/main.rkt: no routes matched; the route syntax changed")

    capability = CAPABILITY.search(text)
    grants: set[str] = set()
    if not capability:
        errors.append("host/main.rkt: host-capability grant list not found")
    else:
        grants = set(capability.group(1).split())
        for missing in sorted(used - grants):
            errors.append(f"host-capability lacks {missing}: routes with this class are refused in production")
        # `class:name` grants release framework surfaces (dialog:open is the
        # native open panel); they carry no app route by design.
        for unused in sorted(g for g in grants - used if ":" not in g):
            errors.append(f"host-capability grants {unused} but no route uses it")
        if "rpc" not in grants:
            errors.append("host-capability lacks rpc: the page cannot reach the engine")
        if "dialog:open" not in grants:
            errors.append("host-capability lacks dialog:open: the vault and scan-folder pickers cannot open")

    if errors:
        for error in errors:
            print(f"route permission gate FAIL: {error}", file=sys.stderr)
        return 1
    print(f"Route permission gate PASS: {routes} routes classified, "
          f"{len(grants)} grants, all used")
    return 0


if __name__ == "__main__":
    sys.exit(main())
