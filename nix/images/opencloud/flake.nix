# SPDX-FileCopyrightText: 2026 opencloud-nix Contributors
# SPDX-License-Identifier: Apache-2.0
#
# OpenCloud server container image — Nix-built from the pinned upstream release
# binary. Reproducible: pinned SRI hash from the release .sha256 sidecar,
# locked nixpkgs (see flake.lock).
#
# OpenCloud ships as a single static Go binary per release; we vendor the
# upstream linux-amd64 binary, pin it by hash, and wrap it in a minimal
# layered image (non-root user, tini init, CA/timezone data).
#
# Version bump recipe (e.g. 9.1.0 -> 9.2.0):
#   1. set `version` below
#   2. fetch the new sha256:
#        curl -L https://github.com/opencloud-eu/opencloud/releases/download/v<ver>/opencloud-<ver>-linux-amd64.sha256
#   3. update the lock:   nix flake lock --update-input nixpkgs
#   4. rebuild + push:
#        nix build .#opencloud --print-build-logs
#        skopeo copy docker-archive:result docker://<registry>/opencloud:<ver>
{
  description = "OpenCloud server container image, Nix-built from the pinned upstream release binary";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # --- image configuration (tune for your deployment) -----------------
        # Upstream release version (rolling release train).
        version = "9.1.0";
        # SRI sha256 of `opencloud-${version}-linux-amd64`, from the release
        # .sha256 sidecar on github.com/opencloud-eu/opencloud.
        sha256 = "183d95c3a77ccb520dabaa106e08d1037afcaa8af6403c22eb6ac9a565de777e";
        # Registry the image is pushed to (used by the dev shell hint only).
        registry = "ghcr.io/tobias-weiss-ai-xr";
        timezone = "UTC";
        runtimeUser = 1000;   # must match securityContext.runAsUser in helm/k8s
        maintainer = "opencloud-nix maintainers <dev@example.com>";
        source = "https://github.com/example/opencloud-nix";

        # Upstream linux binary (pinned hash from release .sha256)
        src = pkgs.fetchurl {
          url = "https://github.com/opencloud-eu/opencloud/releases/download/v${version}/opencloud-${version}-linux-amd64";
          sha256 = sha256;
        };

        opencloud = pkgs.stdenv.mkDerivation {
          pname = "opencloud";
          inherit version src;
          dontUnpack = true;
          dontConfigure = true;
          dontBuild = true;
          installPhase = ''
            runHook preInstall
            install -Dm755 $src $out/bin/opencloud
            runHook postInstall
          '';
          meta = with pkgs.lib; {
            description = "OpenCloud – scalable file sync & share (ownCloud Infinite Scale successor)";
            homepage = "https://opencloud.eu";
            license = licenses.agpl3Plus;
            mainProgram = "opencloud";
            maintainers = [ ];
          };
        };

        labels = {
          maintainer = maintainer;
          vendor = "opencloud-nix";
          license = "Apache-2.0";
          "org.opencontainers.image.vendor" = "opencloud-nix";
          "org.opencontainers.image.license" = "Apache-2.0";
          "org.opencontainers.image.source" = source;
          "org.opencontainers.image.title" = "OpenCloud";
          "org.opencontainers.image.description" =
            "OpenCloud server – file sync & share, AGPL-3.0-only, built reproducibly with Nix";
          "org.opencontainers.image.version" = version;
        };

        image = pkgs.dockerTools.buildLayeredImage {
          name = "opencloud";
          tag = version;
          created = "now";
          maxLayers = 60;

          contents = [
            opencloud
            pkgs.cacert
            pkgs.tzdata
            pkgs.tini
            pkgs.bash
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.curl
            # deterministic /etc/passwd + /etc/group (non-root user)
            (pkgs.writeTextDir "etc/passwd"
              "opencloud:x:${toString runtimeUser}:${toString runtimeUser}:openCloud:/var/lib/opencloud:${pkgs.stdenv.shell}\n")
            (pkgs.writeTextDir "etc/group"
              "opencloud:x:${toString runtimeUser}:\n")
          ];

          # Create + correctly own the data dir inside the (fake-root) build
          # environment. This is what makes plain `docker run` and Docker
          # Compose named-volume copy-up work for the non-root user without
          # requiring an fsGroup-style fix at runtime.
          fakeRootCommands = ''
            mkdir -p /var/lib/opencloud
            chown -R ${toString runtimeUser}:${toString runtimeUser} /var/lib/opencloud
          '';

          config = {
            # Exec via absolute store paths: the dockerTools /bin symlink farm
            # is drwx------ root in current nixpkgs, so `tini -- opencloud`
            # (PATH lookup -> /bin/opencloud) fails for non-root. Both the
            # tini and the opencloud store paths are known at build time.
            Entrypoint = [ "${pkgs.tini}/bin/tini" "--" ];
            Cmd = [ "${opencloud}/bin/opencloud" "server" ];
            User = "${toString runtimeUser}:${toString runtimeUser}";
            WorkingDir = "/var/lib/opencloud";
            ExposedPorts = { "9200/tcp" = { }; };
            Volumes = { "/var/lib/opencloud" = { }; };
            Env = [
              # OC_CONFIG_DIR must point at the dir containing opencloud.yaml
              # (the config that is mounted/provided at runtime).
              "OC_CONFIG_DIR=/etc/opencloud"
              "TZ=${timezone}"
            ];
            Labels = labels;
          };
        };
      in {
        packages = {
          opencloud = image;
          default = image;
        };

        devShells.default = pkgs.mkShell {
          packages = [ opencloud pkgs.skopeo ];
          shellHook = ''
            echo "OpenCloud image:  nix build .#opencloud"
            echo "Push example:     skopeo copy docker-archive:result docker://${registry}/opencloud:${version}"
            echo "Run locally:      docker load < result && docker run --rm -p 9200:9200 -e OC_INSECURE=true ${registry}/opencloud:${version}"
          '';
        };
      });
}
