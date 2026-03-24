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
    [ -f "modules/lib/ui_logging.sh" ]
    [ -f "modules/lib/system_runtime.sh" ]
    [ -f "modules/lib/downloads.sh" ]
    [ -f "modules/lib/config_loading.sh" ]
    [ -f "modules/lib/path_safety.sh" ]
    [ -f "modules/lib/runtime_inputs.sh" ]
    [ -f "modules/lib/validation.sh" ]
    [ -f "modules/lib/legacy_transport_contract.sh" ]
    [ -f "modules/config/client_artifacts.sh" ]
    [ -f "modules/config/client_formats.sh" ]
    [ -f "modules/config/client_state.sh" ]
    [ -f "modules/config/domain_planner.sh" ]
    [ -f "modules/config/runtime_profiles.sh" ]
    [ -f "modules/config/runtime_contract.sh" ]
    [ -f "modules/config/runtime_apply.sh" ]
    [ -f "modules/service/uninstall.sh" ]
    [ -f "modules/service/runtime.sh" ]
    [ -f "modules/install/bootstrap.sh" ]
    [ -f "modules/install/output.sh" ]
    [ -f "modules/install/selection.sh" ]
    [ -f "modules/install/xray_runtime.sh" ]
    [ -f "scripts/generate-domain-fallbacks.sh" ]
    [ -f "scripts/lab/generate-vm-proof-pack.sh" ]
}

@test "data files exist" {
    [ -f "domains.tiers" ]
    [ -f "sni_pools.map" ]
    [ -f "transport_endpoints.map" ]
}

@test "bash syntax is valid" {
    run bash -n xray-reality.sh lib.sh install.sh config.sh service.sh health.sh export.sh \
        modules/lib/ui_logging.sh modules/lib/system_runtime.sh modules/lib/downloads.sh modules/lib/config_loading.sh modules/lib/path_safety.sh modules/lib/runtime_inputs.sh modules/lib/validation.sh modules/lib/legacy_transport_contract.sh modules/config/client_artifacts.sh modules/config/client_formats.sh modules/config/client_state.sh modules/config/domain_planner.sh modules/config/runtime_profiles.sh modules/config/runtime_contract.sh modules/config/runtime_apply.sh modules/service/uninstall.sh modules/service/runtime.sh modules/install/bootstrap.sh modules/install/output.sh modules/install/selection.sh modules/install/xray_runtime.sh scripts/generate-domain-fallbacks.sh scripts/lab/generate-vm-proof-pack.sh
    [ "$status" -eq 0 ]
}
