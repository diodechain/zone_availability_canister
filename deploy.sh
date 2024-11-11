#!/bin/bash
#dfx deploy DiodeMessages --argument 'record {zone_id = "0xe18cbbd6bd2babd532b297022533bdb00251ed58"; rpc_host = "lite.prenet.diode.io:8443"; rpc_path = "/";}'
dfx deploy DiodeMessages --argument 'record {zone_id = "0xe18cbbd6bd2babd532b297022533bdb00251ed58"; rpc_host = "prenet.diode.io:8443"; rpc_path = "/";}'
