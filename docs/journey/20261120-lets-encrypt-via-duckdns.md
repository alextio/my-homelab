# Publicly trusted certificates via Let's Encrypt and DuckDNS

What looked like "change some URLs" turned into a day of DNS, cert-manager,
Gateway API and SSO work. This is the record of why.

## What we set out to do

Every service was on a `*.lan` name with a certificate signed by the
self-signed `homelab-root-ca` (cert-manager `homelab-ca` ClusterIssuer). Every
browser and phone had to install that root CA, and any device that trusts it
can be sent a valid-looking certificate for *any* site by whoever holds the
CA key.

The goal: browser-trusted certificates for the homelab services, so the root
CA can come off client devices, **without exposing anything to the internet**.

## Where we ended up

- A Let's Encrypt wildcard, `*.alextio.duckdns.org`, issued by cert-manager
  over DNS-01 through a DuckDNS webhook (the `duckdns` Argo CD Application).
- Traefik's shared Gateway has a second HTTPS listener, `websecure-duckdns`,
  next to the `*.lan` one. Every service except Dex answers on both names.
- Grafana, Coder and Argo CD build their links and SSO callbacks on the new
  names. Immich and the oauth2-proxy services accept logins on both.
- AdGuard Home resolves `*.alextio.duckdns.org` to Traefik (192.168.6.200) and
  `agentgateway.alextio.duckdns.org` to agentgateway (192.168.6.202). Nothing
  is in public DNS and nothing is port-forwarded.

## Gotchas

### 1. Cloudflare doesn't hand out a CA, and its free plan can't scope a token to a subdomain

The first idea was "get a CA certificate from Cloudflare" for `alextio.com`.

- Cloudflare offers no CA you can sign your own certs with. Its **Origin CA**
  certs are trusted only by Cloudflare's own edge proxy, not browsers, so
  they're useless for direct LAN access.
- What works is **ACME DNS-01**: cert-manager proves domain ownership by
  writing a TXT record through the Cloudflare API, so services can stay
  LAN-only.
- The catch is the API token. Cloudflare scopes tokens to a **zone**, and the
  free plan can't make a subdomain like `lab.alextio.com` its own zone. The
  token would need `Zone:DNS:Edit` on all of `alextio.com`. Whoever steals it
  can redirect mail, repoint the website, and get valid certs for anything
  under the domain. That token would sit in a cluster Secret.

### 2. `.lan` can't get a public certificate

Let's Encrypt only issues for real, publicly registered domains, so the
services needed new names under a domain we control.

### 3. cert-manager has no built-in DuckDNS solver

DuckDNS is free, and its token only controls DuckDNS subdomains, not a real
domain. But cert-manager only ships solvers for the big providers. DuckDNS
needs a third-party **webhook**, which runs as an extension of the Kubernetes
API server (an `APIService`).

- **`ebrianne/cert-manager-webhook-duckdns`** was dead. The last commit was in
  2021, its Helm repo returns 404, it was built with Go 1.15, and its DuckDNS
  client library has been deleted from GitHub, so it can't even be rebuilt.
- **`csp33/cert-manager-duckdns-webhook`** works. It's small (about 200 lines),
  on Go 1.22, and has a live Helm repo, but it's been idle since 2024-09.
  Reading the code turned up:
  - **The token can leak into logs.** It travels in the URL query string, and
    on a network error that URL gets written to the pod's log.
  - **It runs as root** on port 443, and the chart has no `securityContext`.
  - **The image is pushed by hand**, not built by CI, and the default tag is
    `latest`.
  - **Its chart has an RBAC bug:** the RoleBinding names the ServiceAccount
    in `cert-manager`, so the webhook only works in that namespace.
  - **Like any webhook, it registers an `APIService`.** While the pod is
    down, API discovery for its group fails cluster-wide, which can stall
    Argo CD syncs and namespace deletion.

### 4. DuckDNS keeps one TXT record for the whole domain

- **A token covers the whole account.** It can repoint every subdomain on
  the DuckDNS account.
- **There is only one TXT record**, shared by `alextio.duckdns.org` and
  everything under it. A certificate covering both `alextio.duckdns.org` and
  `*.alextio.duckdns.org` makes the two challenges overwrite each other.
- **The same applies to two certificates renewing at once.** That came up
  when agentgateway needed its own copy of the wildcard (gotcha 7).

### 5. Split-horizon DNS breaks cert-manager's DNS check

Before asking Let's Encrypt to validate, cert-manager checks that the TXT
record is visible. Through the cluster's DNS, an AdGuard rewrite for
`*.alextio.duckdns.org` can hide that record. The opposite problem also
showed up: CoreDNS has an override only for `dex.lan`, so pods can't resolve
`*.alextio.duckdns.org` at all.

### 6. Every certificate is published

Let's Encrypt logs every issued certificate in public Certificate Transparency
logs. Per-service certificates would publish a list of every service name.

### 7. Gateway API details

- **Routes are pinned to a listener.** Every HTTPRoute sets
  `sectionName: websecure`, so a new listener starts with zero routes.
- **A Gateway can't read another namespace's Secret.** agentgateway has its
  own Gateway and LoadBalancer IP outside Traefik, so it couldn't use the
  wildcard in the `traefik` namespace.
- **Traefik's IngressRoute takes one `tls.secretName`.** The Traefik
  dashboard couldn't serve both certificates from one IngressRoute.
- **The Coder chart's HTTPRoute takes one `host`.** Its other field,
  `wildcardHost`, is for workspace apps.

### 8. Changing URLs ripples through SSO and Dex

This was the biggest surprise.

- **Apps build their OIDC callback from one configured URL:** Grafana's
  `root_url`, `CODER_ACCESS_URL`, Argo CD's `url`. Adding a route on a new
  name isn't enough. A login started there gets sent back to the old name.
- **Dex only redirects to `redirectURIs` it knows.** Each client needs the
  new callback registered, or the login fails with "unregistered
  redirect_uri".
- **Immich builds its callback from whatever host you're on**, so its new
  name needed Dex callbacks even though nothing else about Immich changed.
- **oauth2-proxy has its own allow-list** (`whitelist_domains`) of hosts it
  will redirect back to after login. Its Dex client needs a `/oauth2/callback`
  for each protected host.
- **Adding a hostname can bypass the login.** A route for Prometheus, AdGuard
  or the Traefik dashboard without the oauth2-proxy filter would expose them
  without login.
- **Dex's own URL is baked into every client.** Moving `dex.lan` means
  changing the issuer in Argo CD, Coder, Grafana, Immich and oauth2-proxy at
  once, plus a CoreDNS override so pods can resolve it.

### 9. Smaller ones

- **AdGuard only reads its config once**, when its storage is empty. Live
  rewrites have to go in through the UI, and they now exist in three places
  to keep in step: the live AdGuard, the seed configmap and the Ansible
  template.
- **Changing a Certificate's `issuerRef` reissues it automatically**
  (reason `IncorrectIssuer`), so there's no need to delete the Secret.
- **Coder workspaces don't use `CODER_ACCESS_URL`.** The Kubernetes template
  points agents at `http://coder.coder.svc.cluster.local`, so changing it
  needed no workspace rebuild.
- **The DuckDNS token is now as sensitive as a CA key** for these names.
  Whoever holds it can repoint `*.alextio.duckdns.org` and get valid
  certificates for it. With `*.lan`, no outsider could get a trusted cert for
  our services.

## Key decisions

| Decision | Why |
|---|---|
| DuckDNS instead of the Cloudflare zone | Without subdomain zones, a Cloudflare token can rewrite all of `alextio.com`. A DuckDNS token only controls a throwaway subdomain. Considered and not taken: delegating the challenge with a CNAME to a cheap second Cloudflare domain (about $10/yr), and cert-manager's built-in `acmeDNS` solver (needs a public acme-dns server). |
| `csp33` webhook, not `ebrianne` | `ebrianne` can't be installed (Helm repo gone) or rebuilt (dependency deleted). `csp33` is small enough to read in full, and its permissions are tightly scoped. |
| Run `csp33` as-is now, harden later | The risks are moderate for a homelab, and fixing them needs a vendored chart and our own image. The free mitigations went in on day one: image pinned by digest, token from Bitwarden via an ExternalSecret (never in Git), issuers scoped to `alextio.duckdns.org`. The rest is a `TODO(duckdns)` in `manifests/templates/duckdns.yaml`. |
| Install the webhook into `cert-manager` | Works around the chart's RBAC bug without patching. It still can't read other Secrets there: its Role names only `duckdns-token`. |
| Our own ClusterIssuers, not the chart's | No ACME email (it would sit in a public repo), and a `dnsZones: [alextio.duckdns.org]` selector so they never try other names. |
| Staging first, then production | Proves the whole chain without spending production rate limits. Staging was issued in about 2 minutes, production in about 70 seconds. |
| Wildcard certs only | Keeps service names out of Certificate Transparency logs. Also avoids the apex + wildcard TXT collision. |
| `dns01RecursiveNameservers: 1.1.1.1` in cert-manager | Its DNS check bypasses the cluster's DNS and AdGuard's rewrites. |
| AdGuard rewrite, no public A record, no port forward | Names resolve only on the LAN. A trusted certificate doesn't need public exposure. |
| A second Gateway listener, not a replacement | `*.lan` keeps working during the move. Routes attach to both listeners and opt in per service. |
| Separate IngressRoute for the Traefik dashboard | One TLS Secret per IngressRoute. It carries the same oauth2-proxy middleware. |
| Second wildcard cert for agentgateway, `renewBefore: 360h` | A Gateway can't use another namespace's Secret. A wildcard keeps `agentgateway` out of the public logs. The offset keeps its renewals about two weeks away from Traefik's (2027-02-03 vs 2027-01-19), so they don't fight over the single TXT record. |
| Same route for both names on oauth2-proxy services | The filter rule has no host match, so it covers every hostname on the route. Unauthenticated API calls on the new names were checked to redirect to Dex. |
| Switch Grafana, Coder and Argo CD URLs; keep the `.lan` callbacks | Logins land on the trusted name. Argo CD keeps `argocd.lan` working via `additionalUrls`. The old Dex callbacks stay for rollback. |
| Leave Dex on `dex.lan` for now | Moving it touches every client and CoreDNS at once. It's a separate step. |
| Fresh worktrees off `origin/main` for each change | Kept unrelated uncommitted work in the submodule out of these commits. |

## Commits

`03-argocd-kubernetes`, on `main`. The range is `c9eeef3..2663dc6`, which is
`e795af5` through `2663dc6`:

| Commit | What |
|---|---|
| `e795af5` | duckdns webhook Application, ExternalSecret, staging and production ClusterIssuers, `*.alextio.duckdns.org` certificate on staging, `websecure-duckdns` listener, cert-manager DNS check against 1.1.1.1 |
| `037dcbe` | non-root `TODO(duckdns)`; corrected the staging-to-production note |
| `69ecf04` | Grafana route on both listeners; Grafana's new Dex callback; AdGuard seed rewrite |
| `c85c684` | Coder route on the new name; Coder's new Dex callback |
| `1d75480` | Wildcard switched to the production issuer |
| `3a4b6eb` | Grafana `root_url` and `CODER_ACCESS_URL` moved to the new names |
| `78bd87a` | Argo CD, Prometheus, AdGuard, Immich and Traefik dashboard on the new names; oauth2-proxy `whitelist_domains` and callbacks |
| `2663dc6` | Immich Dex callbacks; Argo CD `url` + `additionalUrls`; agentgateway listener and certificate; agentgateway AdGuard seed rewrite |

The first Cloudflare attempt was reverted before it was ever committed.

Not committed: the matching `02-ansible` change
(`playbooks/dns/templates/rewrites.yml.j2`, `playbooks/dns/vars.yml`).

## Still to do

- **Harden the webhook** (`TODO(duckdns)` in `manifests/templates/duckdns.yaml`):
  - non-root
  - our own image without the token-in-URL log line
  - a dedicated namespace
  - a NetworkPolicy
- **Move Dex off `dex.lan`.** Then remove `homelab-root-ca` from client
  devices. Keep the CA for in-cluster use (bitwarden-sdk-server).
- **Fix the agentgateway proxy.** It had been crash-looping for 15 days before
  this work started: exit code 132 (SIGILL), most likely a CPU instruction the
  host lacks. `.202` serves nothing until it's fixed.
- **Remove the old `.lan` routes and Dex callbacks** once nothing uses them.
- **Add an expiry alert** on `certmanager_certificate_expiration_timestamp_seconds`,
  so a dead webhook or a rotated token doesn't surface only when every
  certificate expires on the same day.
