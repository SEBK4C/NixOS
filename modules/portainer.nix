# Phase 5 — Portainer management.
#
# Ships the official Portainer Swarm stack (server on a manager, agent as
# a global service) plus a one-shot deploy command. Run once, on any
# manager, after the swarm is up:
#
#   cluster-deploy-portainer
#
# Then open https://<manager-tailnet-ip>:9443 from your admin workstation.
{ config, pkgs, lib, ... }:

let
  cfg = config.cluster;

  stackFile = pkgs.writeText "portainer-stack.yml" ''
    version: "3.8"

    services:
      agent:
        image: portainer/agent:lts
        environment:
          AGENT_CLUSTER_ADDR: tasks.agent
        volumes:
          - /var/run/docker.sock:/var/run/docker.sock
          - /var/lib/docker/volumes:/var/lib/docker/volumes
        networks:
          - agent_network
        deploy:
          mode: global

      portainer:
        image: portainer/portainer-ce:lts
        command: -H tcp://tasks.agent:9001 --tlsskipverify
        ports:
          - "9443:9443"
        volumes:
          - portainer_data:/data
        networks:
          - agent_network
        deploy:
          mode: replicated
          replicas: 1
          placement:
            constraints:
              - node.role == manager

    networks:
      agent_network:
        driver: overlay
        attachable: true

    volumes:
      portainer_data:
  '';

  deployScript = pkgs.writeShellScriptBin "cluster-deploy-portainer" ''
    set -eu
    exec ${config.virtualisation.docker.package}/bin/docker stack deploy \
      --compose-file ${stackFile} portainer
  '';
in
{
  # The deploy command only exists on managers; agents are scheduled by
  # the swarm itself, so workers need nothing here.
  environment.systemPackages = lib.mkIf (cfg.role == "manager") [ deployScript ];
}
