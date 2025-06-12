# Findings

- The Region library is now available and makes accessing simple
    - https://internetcomputer.org/docs/current/motoko/main/base/Region (64gb)
    - https://internetcomputer.org/docs/current/developer-docs/smart-contracts/maintain/storage
    - Documented limits are different:
        - https://forum.dfinity.org/t/heap-vs-stable-memory/30257

- Testing frameworks for Motoko ? Best practices? Vessel dead? 
    https://forum.dfinity.org/t/do-people-actually-use-vessel/9849/5 
    https://github.com/aviate-labs/testing.mo
    https://forum.dfinity.org/t/what-are-the-best-tools-to-test-canisters-written-in-motoko-what-i-ve-tried-so-far-is-surprisingly-big-of-a-pain/16474

- https://mops.one/
    Testing + Packaging
    Testing largely undocumented
    - How to test an actor (required to convert to an actor class)?
    - Very slow like 20+ seconds per test (*NEED TO CHANGE TO POCKET-ID in mops.toml to make it faster*)
    - Mops actor tests don't print Debug.print() output 
    Default github action fails (*NEED TO ADD moc to mops.toml*)

- Stable Hash Map
    Official documentation at: https://internetcomputer.org/docs/current/motoko/main/canister-maintenance/upgrades/ 
        recommends https://github.com/canscale/StableHashMap,
    but Author 
        recommends https://github.com/ZhenyaUsenko/motoko-hash-map at https://forum.dfinity.org/t/day-origyn-motoko-gift-2-a-better-map/14758/2