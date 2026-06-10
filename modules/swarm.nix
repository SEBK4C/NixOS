# Phase 4 — join the Swarm.
#
# The first manager (cluster.firstManager) runs `docker swarm init` and
# prints the join tokens for you to store in 1Password. Every other node
# reads its role's token from op://<vault>/Swarm/{manager,worker}-token
# and joins over the tailnet. Idempotent: skips if already in a swarm.
{ config, pkgs, ... }:

let
  cfg = config.cluster;
  tokenField = if cfg.role == "manager" then "manager-token" else "worker-token";
  isFirstManager = config.networking.hostName == cfg.firstManager;
in
{
  virtualisation.docker = {
    enable = true;
    liveRestore = false; # Swarm mode requires live-restore disabled
  };

  systemd.services.swarm-join = {
    description = "Initialize or join the Docker Swarm over the tailnet";
    wantedBy = [ "multi-user.target" ];
    wants = [ "docker.service" "tailscale-join.service" ];
    after = [ "docker.service" "tailscale-join.service" "op-bootstrap.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ config.virtualisation.docker.package pkgs.tailscale ];
    script =
      if isFirstManager then ''
        if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" = "active" ]; then
          echo "Already part of a swarm"
          exit 0
        fi
        ip="$(tailscale ip -4)"
        docker swarm init --advertise-addr "$ip" --listen-addr "$ip"
        echo "Swarm initialized. NOW store these tokens in 1Password" \
             "(item 'Swarm', fields 'manager-token' and 'worker-token'):"
        docker swarm join-token manager
        docker swarm join-token worker
      '' else ''
        if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" = "active" ]; then
          echo "Already part of a swarm"
          exit 0
        fi
        ip="$(tailscale ip -4)"
        token="$(/run/current-system/sw/bin/op-cluster read \
          'op://${cfg.vault}/Swarm/${tokenField}')"

        for i in $(seq 1 30); do
          if docker swarm join --token "$token" --advertise-addr "$ip" \
               "${cfg.swarm.managerAddress}:2377"; then
            echo "Joined swarm as ${cfg.role}"
            exit 0
          fi
          echo "Manager not reachable yet (attempt $i/30), retrying..."
          sleep 10
        done
        echo "Swarm join FAILED — check token, manager, tailnet reachability" >&2
        exit 1
      '';
  };
}
