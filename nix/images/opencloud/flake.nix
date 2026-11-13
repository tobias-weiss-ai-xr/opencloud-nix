# SPDX-FileCopyrightText: 2026 opencloud-nix Contributors
# SPDX-License-Identifier: Apache-2.0
#
# OpenCloud server container image — Nix-built from the pinned upstream release
# binary. Reproducible: pinned SRI hash from the release .sha256 sidecar,
# locked nixpkgs (see flake.lock).
#
# OpenCloud is built FROM SOURCE at the pinned upstream tag (buildGoModule,
# static, disable_crypt tag) and wrapped in a minimal layered image (non-root
# user, tini init, CA/timezone data). We build from source instead of vendoring
# the release binary so we can carry go.mod patches — currently
# compress-1.20.2.patch (GO-2026-6865, fixed upstream in v1.20.2 but not yet
# in the v9.1.0 release binary).
#
# Version bump recipe (e.g. 9.1.0 -> 9.2.0):
#   1. set `version` below, drop/adjust patches that upstream has merged
#   2. set both hashes to pkgs.lib.fakeHash, run
#        nix build .#opencloud --no-link
#      and paste the 'got:' sha256 values from the error output
#   3. update the lock:   nix flake lock --update-input nixpkgs
#   4. rebuild + verify:  nix build .#opencloud && go version -m result-*/bin/opencloud
#   5. push via .github/workflows/build-image.yml (ghcr.io/tobias-weiss-ai-xr/opencloud)
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
        # Registry the image is pushed to (used by the dev shell hint only).
        registry = "ghcr.io/tobias-weiss-ai-xr";
        timezone = "UTC";
        runtimeUser = 1000;   # must match securityContext.runAsUser in helm/k8s
        maintainer = "opencloud-nix maintainers <dev@example.com>";
        source = "https://github.com/tobias-weiss-ai-xr/opencloud-nix";

        # Upstream source at the release tag. We build from source (instead of
        # vendoring the release binary) because v9.1.0 still ships
        # klauspost/compress v1.20.1 — vulnerable to GO-2026-6865 (panic on
        # two-block frames), fixed upstream in v1.20.2. Upstream main has not
        # bumped yet, so we carry the go.mod/go.sum patch here.
        src = pkgs.fetchFromGitHub {
          owner = "opencloud-eu";
          repo = "opencloud";
          rev = "v${version}";
          hash = "sha256-AZr4JB6PmCx1jqYzzETU/QgTMlDcmu31KQEhDzZbW8s=";
        };
        patches = [ ./compress-1.20.2.patch ];

        opencloud = pkgs.buildGoModule {
          pname = "opencloud";
          inherit version src patches;
          # upstream tarball ships vendor/; drop it so the modules are
          # vendored from the PATCHED go.mod (compress v1.20.2)
          deleteVendor = true;
          vendorHash = "sha256-2A/xrJHq7LK21kyHgoDzjtF45Kd4VOf9Pl0nixBULuc=";
          subPackages = [ "opencloud/cmd/opencloud" ];
          # static binary like the upstream release; go-crypt (libregraph/idm)
          # needs the disable_crypt tag when CGO is off
          preBuild = ''
            export CGO_ENABLED=0
          '';
          tags = [ "disable_crypt" ];
          ldflags = [ "-s" "-w" ];
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

          # The data dir is NOT created here (no-op): dockerTools'
          # fakeRootCommands relies on fakeroot/user-ns emulation that is
          # unavailable in containerized and in-cluster Nix build sandboxes
          # ("mkdir /var/lib: Permission denied"). Ownership is instead
          # provided at runtime:
          #   * docker compose: ./data bind mount, created + chowned by
          #     `make compose-setup` (host side, uid 1000)
          #   * kubernetes: pod securityContext fsGroup=1000 makes the
          #     kubelet create + chown the PVC/emptyDir mount
          fakeRootCommands = "true";

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
