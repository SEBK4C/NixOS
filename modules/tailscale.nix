# Phase 2 — join the tailnet.
#
# Fetches the Tailscale auth key from op://<vault>/Tailscale/credential
# at boot and joins. Idempotent: skips if the node is already logged in.
{ config, pkgs, ... }:

let
  cfg = config.cluster;
in
{
  services.tailscale.enable = true;

  systemd.services.tailscale-join = {
    description = "Join the Tailscale mesh using a 1Password-stored auth key";
    wantedBy = [ "multi-user.target" ];
    wants = [ "op-bootstrap.service" ];
    after = [ "tailscaled.service" "op-bootstrap.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.tailscale pkgs.jq ];
    script = ''
      state="$(tailscale status --json | jq -r .BackendState)"
      if [ "$state" = "Running" ]; then
        echo "Already joined tailnet"
        exit 0
      fi
      tailscale up \
        --authkey "$(/run/current-system/sw/bin/op-cluster read \
          'op://${cfg.vault}/Tailscale/credential')" \
        --hostname "${config.networking.hostName}"
    '';
  };
}
