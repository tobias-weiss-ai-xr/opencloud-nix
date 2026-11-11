# SPDX-FileCopyrightText: 2026 opencloud-nix Contributors
# SPDX-License-Identifier: Apache-2.0
#
# Plain-nix entry point (usable without flakes):
#   nix-instantiate --eval nix/default.nix
# Mostly superseded by flake.nix; kept as the reference repo did.

{ pkgs ? import <nixpkgs> {}, libPath ? ./lib/k8s.nix }:

let
  lib = import libPath { inherit pkgs; };
in
{
  inherit lib;
  opencloud = import ./k8s/opencloud.nix { inherit lib; };
}
