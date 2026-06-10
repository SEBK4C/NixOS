# Phase 0 — bootstrap identity.
#
# `op-cluster` wraps the 1Password CLI: it loads OP_SERVICE_ACCOUNT_TOKEN
# from /etc/op/token (or an op_token=… kernel parameter as fallback) and
# execs `op`. Every other module fetches its secrets through it, so no
# secret ever lives in this repo or in the Nix store.
{ config, pkgs, lib, ... }:

let
  cfg = config.cluster;

  opCluster = pkgs.writeShellScriptBin "op-cluster" ''
    set -eu
    if [ -z "''${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
      if [ -r ${cfg.tokenFile} ]; then
        OP_SERVICE_ACCOUNT_TOKEN="$(cat ${cfg.tokenFile})"
      else
        OP_SERVICE_ACCOUNT_TOKEN="$(${pkgs.gnused}/bin/sed -n \
          's/.*op_token=\([^ ]*\).*/\1/p' /proc/cmdline)"
      fi
      if [ -z "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
        echo "op-cluster: no token in ${cfg.tokenFile} or kernel cmdline" >&2
        exit 1
      fi
      export OP_SERVICE_ACCOUNT_TOKEN
    fi
    exec ${pkgs._1password-cli}/bin/op "$@"
  '';
  # Rebuild from the private ops flake without persisting a GitHub token
  # on disk: the read-only PAT is fetched from 1Password per invocation
  # and exists only in this process's environment.
  clusterRebuild = pkgs.writeShellScriptBin "cluster-rebuild" ''
    set -eu
    ${lib.optionalString (cfg.opsFlake == "") ''
      echo "cluster-rebuild: cluster.opsFlake is not set" >&2
      exit 1
    ''}
    action="''${1:-switch}"; shift || true
    token="$(${opCluster}/bin/op-cluster read 'op://${cfg.vault}/GitHub/credential')"
    export NIX_CONFIG="access-tokens = github.com=$token"
    exec ${pkgs.nixos-rebuild}/bin/nixos-rebuild "$action" --refresh \
      --flake '${cfg.opsFlake}#'"$(${pkgs.coreutils}/bin/uname -n)" "$@"
  '';
in
{
  # The 1Password CLI is unfree; allow it (and nothing else) explicitly.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "1password-cli" "_1password-cli" ];

  environment.systemPackages = [ pkgs._1password-cli opCluster clusterRebuild ];

  # Gate for everything downstream: succeeds once the token can list vaults.
  systemd.services.op-bootstrap = {
    description = "Validate 1Password service account bootstrap";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for i in $(seq 1 30); do
        if ${opCluster}/bin/op-cluster vault list >/dev/null 2>&1; then
          echo "1Password bootstrap OK"
          exit 0
        fi
        echo "1Password not reachable yet (attempt $i/30), retrying..."
        sleep 5
      done
      echo "1Password bootstrap FAILED — check token, expiry, vault scope" >&2
      exit 1
    '';
  };
}
