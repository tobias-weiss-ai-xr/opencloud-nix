# SPDX-FileCopyrightText: 2026 opencloud-nix Contributors
# SPDX-License-Identifier: Apache-2.0
#
# opencloud-nix — Nix-based OpenCloud deployment.
#
# This flake ties together:
#   * the Nix-built OpenCloud container image (nix/images/opencloud)
#   * k8s manifest generation for a raw `kubectl apply` path
#   * a dev shell with docker/helm/helmfile/kubectl for the compose + helmfile
#     deployment paths.
{
  description = "opencloud-nix — Nix-built OpenCloud image + k8s manifest generation + dev environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    # The OpenCloud image build lives in its own flake (own lock, own nixpkgs
    # pin) and is reused here as a local path input.
    "opencloud-image" = {
      type = "path";
      path = ./nix/images/opencloud;
    };
  };

  outputs = { self, nixpkgs, flake-utils, opencloud-image, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = import ./nix/lib/k8s.nix { inherit pkgs; };

        # --- deployment config (override via --override-input / -c) -------
        # Where the Nix-built image is pushed to and which tag runs.
        registry = "ghcr.io/tobias-weiss-ai-xr";
        tag = "9.1.0";
        # Ingress host for the raw k8s manifest path.
        host = "cloud.example.com";

        # k8s manifests (JSON -> YAML via yq), one multi-doc file per service.
        opencloudManifest = import ./nix/k8s/opencloud.nix { inherit lib registry tag host; };
        jsonFormat = pkgs.formats.json { };
        manifestYaml = pkgs.runCommand "opencloud-manifests" { buildInputs = [ pkgs.yq-go ]; } ''
          mkdir -p $out
          ${pkgs.yq-go}/bin/yq -P evalall '.' ${jsonFormat.generate "opencloud.json" opencloudManifest} > $out/opencloud.yaml
        '';
      in
      {
        packages = {
          opencloud-image = opencloud-image.packages.${system}.opencloud;
          opencloud-manifest = manifestYaml;
          default = opencloud-image;
        };

        apps.apply = {
          type = "app";
          program = "${pkgs.writeShellScript "apply" ''
            set -euo pipefail
            echo "=== Applying OpenCloud manifests ==="
            kubectl apply -f ${manifestYaml}/
            echo "=== Done ==="
          ''}";
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ docker skopeo helm helmfile kubectl yq-go just curl ];
          shellHook = ''
            echo "opencloud-nix dev shell"
            echo "  nix build .#opencloud-image     — build the Nix OpenCloud image"
            echo "  nix build .#opencloud-manifest  — generate k8s manifests"
            echo "  make compose-up                 — deploy via docker compose (localhost:9200)"
            echo "  make helmfile-apply             — deploy via helmfile (kubernetes)"
          '';
        };
      }
    );
}
