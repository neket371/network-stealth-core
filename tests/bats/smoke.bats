#!/usr/bin/env bats

@test "entrypoint exists" {
    [ -f "xray-reality.sh" ]
}

@test "core modules exist" {
    [ -f "lib.sh" ]
    [ -f "install.sh" ]
    [ -f "config.sh" ]
    [ -f "service.sh" ]
    [ -f "health.sh" ]
    [ -f "modules/lib/validation.sh" ]
    [ -f "modules/config/client_artifacts.sh" ]
    [ -f "modules/config/domain_planner.sh" ]
    [ -f "modules/service/uninstall.sh" ]
    [ -f "modules/install/bootstrap.sh" ]
    [ -f "modules/install/output.sh" ]
    [ -f "modules/install/selection.sh" ]
    [ -f "modules/install/xray_runtime.sh" ]
}

@test "data files exist" {
    [ -f "domains.tiers" ]
    [ -f "sni_pools.map" ]
    [ -f "transport_endpoints.map" ]
}

@test "bash syntax is valid" {
    run bash -n xray-reality.sh lib.sh install.sh config.sh service.sh health.sh export.sh \
        modules/lib/validation.sh modules/config/client_artifacts.sh modules/config/domain_planner.sh modules/service/uninstall.sh modules/install/bootstrap.sh modules/install/output.sh modules/install/selection.sh modules/install/xray_runtime.sh
    [ "$status" -eq 0 ]
}
