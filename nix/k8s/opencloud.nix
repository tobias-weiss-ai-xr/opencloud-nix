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
  # Instance identifiers used inside opencloud.yaml (mirror of
  # `opencloud init --insecure yes`). Keep them stable per deployment,
  # change between separate OpenCloud instances.
, serviceAccountId ? "99d1bcaa-b735-4c12-a620-6ed8148bc969"
, storageUsersMountId ? "9112edb4-06bb-4573-a057-4aef5479ba1d"
, graphApplicationId ? "c51bdf21-196c-4b35-969e-e05a21912eb7"
, systemUserId ? "980c181d-9c95-47f1-9669-564022535b5b"
, adminUserId ? "6b8dd20c-dbbb-46a8-8e00-aed13c490082"
}:

let
  name = "opencloud";
  image = registry;

  # Canonical OpenCloud 9.x development config — mirrors what
  # `opencloud init --insecure yes` generates (see config/opencloud.yaml).
  opencloudYaml = ''
    token_manager:
      jwt_secret: "override-via-env"
      machine_auth_api_key: "override-via-env"
      system_user_api_key: "override-via-env"
      transfer_secret: "override-via-env"
      url_signing_secret: "override-via-env"
      system_user_id: "${systemUserId}"
      admin_user_id: "${adminUserId}"
    graph:
      application:
        id: ${graphApplicationId}
      events:
        tls_insecure: true
      spaces:
        insecure: true
      identity:
        ldap:
          bind_password: "JrGpZLYg%ZYunrg!..mNQuR%o3pelYx3"
          write_disabled: false
      service_account:
        service_account_id: ${serviceAccountId}
        service_account_secret: "&70yt@bkIo6xY5rtab0lR%mV%zMX*UWb"
    idp:
      ldap:
        bind_password: "0D+MjP6kl&Che&!r7OjO4zif2t.TdMyT"
    idm:
      service_user_passwords:
        admin_password: "admin"
        idm_password: "JrGpZLYg%ZYunrg!..mNQuR%o3pelYx3"
        reva_password: "^SSawXD9IMbYC-q9cs*%wIuX9QmVrR^r"
        idp_password: "0D+MjP6kl&Che&!r7OjO4zif2t.TdMyT"
    collaboration:
      wopi:
        secret: "1Ok6d%9JAy2.Apv^01Y!EpR%+y03F3uV"
      app:
        insecure: true
    proxy:
      oidc:
        insecure: true
      insecure_backends: true
      service_account:
        service_account_id: ${serviceAccountId}
        service_account_secret: "&70yt@bkIo6xY5rtab0lR%mV%zMX*UWb"
    frontend:
      app_handler:
        insecure: true
      archiver:
        insecure: true
      service_account:
        service_account_id: ${serviceAccountId}
        service_account_secret: "&70yt@bkIo6xY5rtab0lR%mV%zMX*UWb"
      ocdav:
        insecure: true
    auth_basic:
      auth_providers:
        ldap:
          bind_password: "^SSawXD9IMbYC-q9cs*%wIuX9QmVrR^r"
    auth_bearer:
      auth_providers:
        oidc:
          insecure: true
    users:
      drivers:
        ldap:
          bind_password: "^SSawXD9IMbYC-q9cs*%wIuX9QmVrR^r"
          write_disabled: false
    groups:
      drivers:
        ldap:
          bind_password: "^SSawXD9IMbYC-q9cs*%wIuX9QmVrR^r"
          write_disabled: false
    auth_guest:
      service_account:
        service_account_id: ${serviceAccountId}
        service_account_secret: "&70yt@bkIo6xY5rtab0lR%mV%zMX*UWb"
    ocm:
      service_account:
        service_account_id: ${serviceAccountId}
        service_account_secret: "&70yt@bkIo6xY5rtab0lR%mV%zMX*UWb"
    search:
      events:
        tls_insecure: true
      service_account:
        service_account_id: ${serviceAccountId}
        service_account_secret: "&70yt@bkIo6xY5rtab0lR%mV%zMX*UWb"
    audit:
      events:
        tls_insecure: true
    settings:
      service_account_ids:
      - ${serviceAccountId}
    sharing:
      events:
        tls_insecure: true
      service_account:
        service_account_id: ${serviceAccountId}
        service_account_secret: "&70yt@bkIo6xY5rtab0lR%mV%zMX*UWb"
    storage_users:
      events:
        tls_insecure: true
      mount_id: ${storageUsersMountId}
      service_account:
        service_account_id: ${serviceAccountId}
        service_account_secret: "&70yt@bkIo6xY5rtab0lR%mV%zMX*UWb"
    notifications:
      notifications:
        events:
          tls_insecure: true
      service_account:
        service_account_id: ${serviceAccountId}
        service_account_secret: "&70yt@bkIo6xY5rtab0lR%mV%zMX*UWb"
    nats:
      nats:
        tls_skip_verify_client_cert: true
    gateway:
      storage_registry:
        storage_users_mount_id: ${storageUsersMountId}
    userlog:
      service_account:
        service_account_id: ${serviceAccountId}
        service_account_secret: "&70yt@bkIo6xY5rtab0lR%mV%zMX*UWb"
    auth_service:
      service_account:
        service_account_id: ${serviceAccountId}
        service_account_secret: "&70yt@bkIo6xY5rtab0lR%mV%zMX*UWb"
    clientlog:
      service_account:
        service_account_id: ${serviceAccountId}
        service_account_secret: "&70yt@bkIo6xY5rtab0lR%mV%zMX*UWb"
    activitylog:
      service_account:
        service_account_id: ${serviceAccountId}
        service_account_secret: "&70yt@bkIo6xY5rtab0lR%mV%zMX*UWb"
    webfinger:
      insecure: true
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
