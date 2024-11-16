#!/bin/bash
#dfx deploy DiodeMessages --argument 'record {zone_id = "0xe18cbbd6bd2babd532b297022533bdb00251ed58"; rpc_host = "lite.prenet.diode.io:8443"; rpc_path = "/";}'
# Zone ID from ./run2 on mac's Testing1234 Zone
dfx deploy DiodeMessages --argument 'record {zone_id = "0xcd0afb71cb7ea9d16c719869682a399428eec34a"; rpc_host = "prenet.diode.io:8443"; rpc_path = "/";}'
