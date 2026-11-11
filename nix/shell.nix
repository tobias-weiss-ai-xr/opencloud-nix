# SPDX-FileCopyrightText: 2026 opencloud-nix Contributors
# SPDX-License-Identifier: Apache-2.0
#
# Legacy shell (usable without flakes); prefer `nix develop` from the root
# flake, which provides the same tools plus docker/helm/helmfile.
{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = with pkgs; [ kubectl yq-go just helm helmfile docker skopeo ];
  shellHook = ''
    echo "opencloud-nix development shell (nix/shell.nix)"
    echo "  make compose-up    — docker compose (localhost:9200)"
    echo "  make helmfile-apply — helmfile (kubernetes)"
  '';
}
