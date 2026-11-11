# SPDX-FileCopyrightText: 2026 opencloud-nix Contributors
# SPDX-License-Identifier: Apache-2.0
#
# OpenCloud raw k8s manifest (generic, standalone deployment):
# Deployment + ConfigMap + Secret + PVC + Service + Ingress.
# The lightweight `helmfile/charts/opencloud` chart is the maintained path;
# this manifest exists for users who prefer plain kubectl.
#
# Usage from the enclosing flake:
#   nix build .#opencloud-manifest && kubectl apply -f result/

{ lib
, registry ? "ghcr.io/tobias-weiss-ai-xr"   # where the Nix-built image is pushed
, tag ? "9.1.0"
, host ? "cloud.example.com"
, namespace ? "opencloud"
, storageSize ? "100Gi"
, port ? 9200
  # Instance identifiers used inside opencloud.yaml. Keep them stable per
  # deployment, change between separate OpenCloud instances.
, serviceAccountId ? "dc3eee3e-7831-45e4-b986-8e470f37ac23"
, storageUsersMountId ? "ca65db73-407e-43ca-b393-9b141f43aa8f"
, graphApplicationId ? "fdfc30d2-5cc5-40a4-8beb-ce6801bbca41"
}:

let
  name = "opencloud";
  image = registry;

  opencloudYaml = ''
    token_manager:
      jwt_secret: "override-via-env"
      machine_auth_api_key: "override-via-env"
      system_user_api_key: "override-via-env"
      transfer_secret: "override-via-env"
      url_signing_secret: "override-via-env"
      system_user_id: "admin"
    graph:
      application:
        id: ${graphApplicationId}
      events:
        tls_insecure: true
      spaces:
        insecure: true
      identity:
        ldap:
          bind_password: "disabled"
          write_disabled: true
      service_account:
        service_account_id: ${serviceAccountId}
        service_account_secret: "override-via-env"
    proxy:
      oidc:
        insecure: true
      insecure_backends: true
      service_account:
        service_account_id: ${serviceAccountId}
        service_account_secret: "override-via-env"
    storage_users:
      events:
        tls_insecure: true
      mount_id: ${storageUsersMountId}
      service_account:
        service_account_id: ${serviceAccountId}
        service_account_secret: "override-via-env"
    gateway:
      storage_registry:
        storage_users_mount_id: ${storageUsersMountId}
    settings:
      service_account_ids:
      - ${serviceAccountId}
    nats:
      nats:
        tls_skip_verify_client_cert: true
  '';

  commonEnv = [
    { name = "OC_URL"; value = "https://${host}"; }
    { name = "OC_INSECURE"; value = "true"; }
    { name = "OC_LOG_LEVEL"; value = "info"; }
    { name = "PROXY_TLS"; value = "false"; }
    { name = "PROXY_HTTP_ADDR"; value = "0.0.0.0:${toString port}"; }
    { name = "OC_SYSTEM_USER_ID"; value = "admin"; }
    { name = "OC_SYSTEM_USER_IDP"; value = "internal"; }
    (lib.mkEnvVarFromSecret { name = "OC_JWT_SECRET"; key = "jwt-secret"; secret = "${name}-secrets"; })
    (lib.mkEnvVarFromSecret { name = "OC_TRANSFER_SECRET"; key = "transfer-secret"; secret = "${name}-secrets"; })
    (lib.mkEnvVarFromSecret { name = "OC_MACHINE_AUTH_API_KEY"; key = "machine-auth-api-key"; secret = "${name}-secrets"; })
    (lib.mkEnvVarFromSecret { name = "OC_SYSTEM_USER_API_KEY"; key = "system-user-api-key"; secret = "${name}-secrets"; })
    (lib.mkEnvVarFromSecret { name = "OC_URL_SIGNING_SECRET"; key = "url-signing-secret"; secret = "${name}-secrets"; })
  ];

  dataVolume = lib.mkVolume { name = "opencloud-data"; mountPath = "/var/lib/opencloud"; };
  configVolume = lib.mkVolume { name = "opencloud-config"; mountPath = "/etc/opencloud"; configMap = "${name}-config"; };

in [
  (lib.namespace { inherit name; })
  (lib.configMap {
    name = "${name}-config";
    namespace = name;
    data = { "opencloud.yaml" = opencloudYaml; };
  })
  (lib.secret {
    name = "${name}-secrets";
    namespace = name;
    # Stub values — replace before real use (or manage via SOPS/external-secrets).
    stringData = {
      "jwt-secret" = "change-me";
      "transfer-secret" = "change-me";
      "machine-auth-api-key" = "change-me";
      "system-user-api-key" = "change-me";
      "url-signing-secret" = "change-me";
    };
  })
  (lib.pvc { name = "${name}-data"; namespace = name; storageSize = storageSize; })
  (lib.deployment {
    inherit name image tag port;
    namespace = name;
    replicas = 1;
    env = commonEnv;
    volumes = [ dataVolume configVolume ];
    probeType = "http";
    probePath = "/status.php";
    probePort = port;
    resources = {
      requests = { cpu = "256m"; memory = "256Mi"; };
      limits = { cpu = "1000m"; memory = "1Gi"; };
    };
  })
  (lib.service { inherit name port; namespace = name; })
  (lib.ingress { inherit name host port namespace; className = "nginx"; tls = false; })
]
