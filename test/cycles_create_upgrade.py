#!/usr/bin/env python3
"""Measure ZAC create + factory-style upgrade cycle consumption.

Create: Motoko mops test using the same actor-class path as
  CanisterFactory.create_zone_availability_canister (1.5T attach).

Upgrade: PocketIC stop + install_code #upgrade (wasm_memory_persistence=#keep)
  + start — same sequence as CanisterFactory.upgrade_code — upgrading a v414
  ZAC to the current v415 wasm (the migration the factory ships).

Usage (from repo root):
  python3 test/cycles_create_upgrade.py
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

from ic.candid import Types, decode, encode
from ic.principal import Principal
from pocket_ic import PocketIC

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".dfx" / "pocket-ic" / "cycles_measure"
POCKET_IC_BIN = Path.home() / ".cache" / "mops" / "pocket-ic" / "15.0.0" / "pocket-ic"
V414_COMMIT = "cbcf30b"
CREATE_CYCLES = 1_500_000_000_000


def format_cycles(n: int) -> str:
    if n >= 1_000_000_000_000:
        return f"{n / 1_000_000_000_000:.6f}T ({n:,})"
    if n >= 1_000_000_000:
        return f"{n / 1_000_000_000:.6f}B ({n:,})"
    if n >= 1_000_000:
        return f"{n / 1_000_000:.6f}M ({n:,})"
    return f"{n:,}"


def moc() -> str:
    return str(Path.home() / ".cache" / "mops" / "moc" / "0.15.1" / "moc")


def compile_current_zac() -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    out = OUT / "ZoneAvailabilityCanister.wasm"
    sources = subprocess.check_output(
        ["npx", "mops", "sources"], cwd=ROOT, text=True
    ).split()
    subprocess.run(
        [
            moc(),
            *sources,
            "--enhanced-orthogonal-persistence",
            str(ROOT / "src" / "ZoneAvailabilityCanister.mo"),
            "-o",
            str(out),
        ],
        cwd=ROOT,
        check=True,
    )
    return out


def compile_v414_zac() -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    out = OUT / "ZoneAvailabilityCanister_v414.wasm"
    v414 = Path("/tmp/zac_v414")
    if not (v414 / "src" / "ZoneAvailabilityCanister.mo").exists():
        v414.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            f"git archive {V414_COMMIT} | tar -x -C {v414}",
            cwd=ROOT,
            shell=True,
            check=True,
        )
    mops_link = v414 / ".mops"
    if not mops_link.exists():
        mops_link.symlink_to(ROOT / ".mops")
    nm_link = v414 / "node_modules"
    if not nm_link.exists():
        nm_link.symlink_to(ROOT / "node_modules")

    sources = subprocess.check_output(
        ["npx", "mops", "sources"], cwd=v414, text=True
    ).split()
    # cycles-manager needs btree even though v414 mops.toml did not declare it
    btree = ROOT / ".mops" / "_github" / "btree#v0.3.2" / "src"
    cmd = [
        moc(),
        *sources,
        "--package",
        "btree",
        str(btree),
        "--enhanced-orthogonal-persistence",
        "src/ZoneAvailabilityCanister.mo",
        "-o",
        str(out),
    ]
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=v414, check=True)
    return out


def run_create_test() -> dict[str, int]:
    print("+ npx mops test cycles_create_upgrade", flush=True)
    r = subprocess.run(
        ["npx", "mops", "test", "cycles_create_upgrade"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    out = r.stdout + "\n" + r.stderr
    print(out)
    if r.returncode != 0:
        raise SystemExit(r.returncode)

    def req(name: str) -> int:
        m = re.search(rf"{name}=(\d+)", out)
        if not m:
            raise SystemExit(f"missing metric {name}")
        return int(m.group(1))

    return {
        "factory_spent": req("CREATE factory_spent"),
        "child_balance": req("CREATE child_balance"),
        "overhead": req("CREATE overhead"),
        "attach_burn": req("CREATE attach_burn"),
        "factory_call_cost": req("CREATE factory_call_cost"),
    }


def encode_init_arg() -> bytes:
    record = Types.Record(
        {
            "zone_id": Types.Text,
            "rpc_host": Types.Text,
            "rpc_path": Types.Text,
            "cycles_requester_id": Types.Principal,
            "call_token": Types.Opt(Types.Vec(Types.Nat8)),
        }
    )
    return encode(
        [
            {
                "type": record,
                "value": {
                    "zone_id": "0xcd0afb71cb7ea9d16c719869682a399428eec34a",
                    "rpc_host": "mainnet.base.org",
                    "rpc_path": "/",
                    "cycles_requester_id": Principal.anonymous().bytes,
                    "call_token": [],
                },
            }
        ]
    )


def install_code_payload(canister_id: Principal, wasm: bytes, arg: bytes, mode: dict) -> bytes:
    upgrade_opts = Types.Record(
        {
            "wasm_memory_persistence": Types.Opt(
                Types.Variant({"keep": Types.Null, "replace": Types.Null})
            ),
            "skip_pre_upgrade": Types.Opt(Types.Bool),
        }
    )
    install_code_arg = Types.Record(
        {
            "wasm_module": Types.Vec(Types.Nat8),
            "canister_id": Types.Principal,
            "arg": Types.Vec(Types.Nat8),
            "mode": Types.Variant(
                {
                    "install": Types.Null,
                    "reinstall": Types.Null,
                    "upgrade": Types.Opt(upgrade_opts),
                }
            ),
            "sender_canister_version": Types.Opt(Types.Nat64),
        }
    )
    return encode(
        [
            {
                "type": install_code_arg,
                "value": {
                    "wasm_module": list(wasm),
                    "arg": list(arg),
                    "canister_id": canister_id.bytes,
                    "mode": mode,
                    "sender_canister_version": [],
                },
            }
        ]
    )


def measure_upgrade(wasm_v414: Path, wasm_v415: Path) -> dict[str, int]:
    os.environ["POCKET_IC_BIN"] = str(POCKET_IC_BIN)
    pic = PocketIC()
    canister_id = pic.create_canister()
    # PocketIC seeds canisters with a large default balance; add a cushion for install burn.
    pic.add_cycles(canister_id, CREATE_CYCLES)

    init_arg = encode_init_arg()
    pic.update_call(
        None,
        "install_code",
        install_code_payload(canister_id, wasm_v414.read_bytes(), init_arg, {"install": None}),
    )
    version = decode(pic.query_call(canister_id, "get_version", encode([])))[0]["value"]
    assert int(version) == 414, version

    bal = pic.get_cycles_balance(canister_id)
    if bal < CREATE_CYCLES:
        pic.add_cycles(canister_id, CREATE_CYCLES - bal)

    child_before = pic.get_cycles_balance(canister_id)

    pic.update_call(
        None,
        "stop_canister",
        encode(
            [
                {
                    "type": Types.Record({"canister_id": Types.Principal}),
                    "value": {"canister_id": canister_id.bytes},
                }
            ]
        ),
    )

    upgrade_mode = {
        "upgrade": [
            {
                "wasm_memory_persistence": [{"keep": None}],
                "skip_pre_upgrade": [],
            }
        ]
    }
    pic.update_call(
        None,
        "install_code",
        install_code_payload(
            canister_id, wasm_v415.read_bytes(), init_arg, upgrade_mode
        ),
    )

    pic.update_call(
        None,
        "start_canister",
        encode(
            [
                {
                    "type": Types.Record({"canister_id": Types.Principal}),
                    "value": {"canister_id": canister_id.bytes},
                }
            ]
        ),
    )

    version = decode(pic.query_call(canister_id, "get_version", encode([])))[0]["value"]
    assert int(version) == 415, version
    child_after = pic.get_cycles_balance(canister_id)

    return {
        "child_before": child_before,
        "child_after": child_after,
        "child_spent": child_before - child_after,
    }


def main() -> int:
    if not POCKET_IC_BIN.exists():
        print(f"Missing pocket-ic binary at {POCKET_IC_BIN}", file=sys.stderr)
        return 1

    create = run_create_test()
    wasm415 = compile_current_zac()
    wasm414 = compile_v414_zac()
    print(
        f"Measuring upgrade {wasm414.name} ({wasm414.stat().st_size:,} bytes) -> "
        f"{wasm415.name} ({wasm415.stat().st_size:,} bytes)",
        flush=True,
    )
    upgrade = measure_upgrade(wasm414, wasm415)

    print()
    print("=== ZAC cycle consumption ===")
    print("Create (CanisterFactory.create_zone_availability_canister)")
    print(f"  Endowment attached:                {format_cycles(CREATE_CYCLES)}")
    print(f"  Factory spent:                     {format_cycles(create['factory_spent'])}")
    print(f"  Child balance after create:        {format_cycles(create['child_balance'])}")
    print(f"  Create overhead (spent − child):   {format_cycles(create['overhead'])}")
    print(f"    attach surplus burned on child:  {format_cycles(create['attach_burn'])}")
    print(f"    factory call cost beyond attach: {format_cycles(create['factory_call_cost'])}")
    print("Upgrade (CanisterFactory.upgrade_code: stop + #upgrade #keep + start)")
    print(f"  Path:                              v414 → v415 (EOP keep)")
    print(f"  Child balance before:              {format_cycles(upgrade['child_before'])}")
    print(f"  Child balance after:               {format_cycles(upgrade['child_after'])}")
    print(f"  Upgrade child spent:               {format_cycles(upgrade['child_spent'])}")
    print("OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
