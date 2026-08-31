# Diode Zone Availability

Diode is a serverless P2P collaboration suite. It offers chat, file sharing, network sharing and more features usually found in centralized cloud applications such as slack, microsoft teams or discord. With it's peer to peer model similiar to BitTorrent it's decentralized and resilient. But it also has a unique availability problem compared to centralized applications when no peers are online.

This project addresses this issue by defining the Diode Zone Availability canisters to keep Diode zones data available even if no diode peer is online. For this it's using the [IC](https://internetcomputer.org/) decentralized large storage capabilities.

Currently the cost for Storing 1GiB of data on the IC is ($5.36 USD/year)[https://internetcomputer.org/docs/current/developer-docs/gas-cost#storage]. With just a fraction of this cost availability for encrypted messages can be achieved for zones improving the Diode user experience by quite a lot.

It might also be interesting to store additional file data encrypted on the IC for zones. Zone metadata like avatar pictures, zone info, etc. would add to the user experience a lot while being small enough to be stored for a long time. 

Further we would like to investigate the usage of the IC for storing all files and folders of a file sharing Diode zone. This would increase the cost quite a bit more but again might be useful for certain use cases.

# Architecture

The Diode App is structured into "Zones" each zone has it's own set of owners, members, messages, files, etc. Zones are fully isolated from each other. To map this correspondingly to the IC we define one Zone Availability Canister (ZAC) per zone. This ZAC is storing all the data for one zone.

![Diode Zone Availability Architecture](docs/diode_drive.png)

Diagram showing the zone availability canister and multiple client apps uploading and downloading zone data:

```mermaid
graph TD
    subgraph IC[Internet Computer]
        ZAC1[Zone 1 Availability Canister]
        ZAC2[Zone 2 Availability Canister]
    end
    
    C1[Client App 1] <-->|Upload/Download| ZAC1
    C2[Client App 2] <-->|Upload/Download| ZAC1
    C3[Client App 3] <-->|Upload/Download| ZAC1

    C3[Client App 3] <-->|Upload/Download| ZAC2
    C5[Client App 2] <-->|Upload/Download| ZAC2
    C6[Client App 3] <-->|Upload/Download| ZAC2
```

Detailed descrptions of the Architecture in each development milestone:

- [Diode Message Cache](./docs/messages/ARCHITECTURE_MS1.md) storing 100k encrytped messages in a canister and retrieving them. 
- [Diode VetKD Store](./docs/MS1.md)

## Build Prerequisites
This project requires an installation of:

- nodejs >= 22.9
- mops https://cli.mops.one/
- DFX version 0.25.1
- The [Internet Computer SDK](https://internetcomputer.org/docs/current/developer-docs/setup/install/).

### Run the tests

```shell
$ cd diode_messages
$ . ./install_deps.sh
$ mops test
```

Cycle consumption for ZAC **create** (factory actor-class path) and **upgrade**
(`upgrade_code`: stop + `#upgrade` with `wasm_memory_persistence=#keep` + start, v414→v415):

```shell
$ python3 test/cycles_create_upgrade.py
```

Requires the `pocket-ic` binary from mops (`mops.toml` toolchain) and `pip install pocket-ic`.

### Local Development & Debugging

```shell
$ dfx start --background
$ dfx deploy
```

### Production Upgrade

Deploy the factory first so new ZACs always spawn wasm **v415**, then upgrade existing children.

```shell
# 1) Deploy updated CanisterFactory (embeds new ZoneAvailabilityCanister actor class)
dfx canister --ic stop CanisterFactory
dfx deploy --ic CanisterFactory
dfx canister --ic start CanisterFactory

# 2) Fleet upgrade (Moonbeam→Base migration runs inside Motoko upgrade migration)
./scripts/list_canisters.exs --upgrade
```

Upgrade a specific ZAC (only possible as long as the Factory is still a controller):

```shell
$ ./scripts/upgrade_canister.exs ic avjhi-uqaaa-aaaao-qj4ga-cai
```

#### v415: Moonbeam → Base + Chain Fusion

On upgrade to ZAC **v415**:

- Embedded `MoonbeamZoneMap` remaps known Moonbeam `zone_id` values to Base and switches the EVM backend to ICP **Chain Fusion** (`#BaseMainnet` via EVM RPC canister `7hfb6-caaaa-aaaar-qadga-cai`).
- Member role cache is cleared for remapped zones so roles re-fetch on Base.
- Existing Base canisters that still used HTTPS `mainnet.base.org` also switch to Chain Fusion; member cache is kept.
- Diode / Oasis continue to use HTTPS outcalls.

**Owner-only `rebind(zone_id, backend)`** is for *future* RPC/backend changes (not the initial Moonbeam→Base fleet move). Callers must have role ≥ 500. Query `get_rpc_backend` to verify.

Create candid stays `(zone_id, rpc_host, rpc_path[, call_token])` for ddrive compatibility; factory/ZAC map `mainnet.base.org` → Chain Fusion internally.

Keep `src/MoonbeamZoneMap.mo` in sync with ddrive `Model.MoonbeamZoneMap` when the restore CSV changes.
