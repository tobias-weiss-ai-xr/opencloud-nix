# SPDPX-FileCopyrightText: 2026 opencloud-nix Contributors
# SPDX-License-Identifier: Apache-2.0

# OpenCloud Helm chart (generic, standalone deployment)

A generic Helm chart for deploying **OpenCloud** (the open-source ownCloud
Infinite Scale successor) on Kubernetes, using the Nix-built container image
from `nix/images/opencloud` of this repository.

## Configuration model

* `opencloud.yaml` is generated from the chart's `configmap.yaml` and mounted
  at `/etc/opencloud` (`OC_CONFIG_DIR` in the image). Secret values inside the
  yaml are stubs (`override-via-env`); the Deployment injects the real values
  from the `{{NAME}}-secrets` Secret via `OC_*` environment variables.
* With `oidc.enabled=false` (default) OpenCloud uses its built-in identity
  management and basic-auth login — best for a first demo. Enable `oidc` +
  optionally `graph.ldap` for SSO/LDAP setups.

## Key values

| Value | Default | Meaning |
| --- | --- | --- |
| `image.registry/repository/tag` | `ghcr.io/tobias-weiss-ai-xr` / `opencloud` / `9.1.0` | Nix-built image (push it yourself) |
| `service.port` | `9200` | OpenCloud HTTP port (matches the Nix image) |
| `ingress.className` | `nginx` | Ingress controller class |
| `persistence` | `100Gi` RWO, no storageClass | Data PVC |
| `oidc.enabled` | `false` | Use external OIDC instead of internal IDM |
| `jwtSecret` … `urlSigningSecret` | random per install | Pin for stable upgrades/replicas |
| `networkPolicy.enabled` | `true` | L3/L4 network policy |
| `monitoring.enabled` | `false` | Prometheus ServiceMonitor |

## Examples

```console
helm template opencloud . --set image.registry=ghcr.io/me --set image.tag=9.1.0 \
  --set ingress.hosts[0].host=cloud.example.com --set ingress.tls[0].secretName=cloud-tls
```

See `tests/` for helm-unittest suites (`make unittest`).
