{
  description = "NixOS Docker Swarm cluster framework — 1Password bootstrap, Tailscale mesh, Ceph storage, Portainer management";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;

      # The complete node baseline, importable by a private inventory flake
      # (deployment values come from that flake's cluster-settings.nix).
      clusterModule = {
        imports = [
          ./modules/cluster.nix
          ./modules/common.nix
          ./modules/onepassword.nix
          ./modules/tailscale.nix
          ./modules/ceph.nix
          ./modules/swarm.nix
          ./modules/portainer.nix
          ./modules/logging.nix
        ];
      };

      # Example/template configurations. Real deployments live in the private
      # ops repo, which composes nixosModules.cluster with its own
      # cluster-settings.nix and committed hardware configs.
      mkNode = name: role:
        lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            clusterModule
            ./cluster-settings.nix
            (./hosts + "/${name}/hardware-configuration.nix")
            {
              networking.hostName = name;
              cluster.role = role;
            }
          ] ++ lib.optional (builtins.pathExists (./hosts + "/${name}/extra.nix"))
            (./hosts + "/${name}/extra.nix");
        };

      managers = [ "node01" "node02" "node03" ];
      workers = [ "node04" "node05" "node06" "node07" "node08" "node09" "node10" ];
    in
    {
      nixosModules.cluster = clusterModule;

      nixosConfigurations =
        lib.genAttrs managers (name: mkNode name "manager")
        // lib.genAttrs workers (name: mkNode name "worker");
    };
}
