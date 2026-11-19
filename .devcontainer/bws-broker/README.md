# bws-broker

Keeps the Bitwarden Secrets Manager access token **out of the devcontainer**.
The token lives in a separate Podman container, the broker, which runs `bws`
for the devcontainer. The devcontainer's `bws` is a small client that forwards
commands to it.

```
 host (podman)
 ┌───────────────────────── compose project (../compose.yaml) ────────────────────────┐
 │  devcontainer                              bws-broker                              │
 │  ~/.local/bin/bws (client) ── HTTP ──────► server.py ── real bws ──► Bitwarden API │
 │  no token, no real bws                     token: podman secret bws_access_token   │
 └────────────────────────────────────────────────────────────────────────────────────┘
```

A transparent header-injecting proxy can't do this job: a BWS token also
carries the key that decrypts secrets on the client, so whatever runs `bws`
needs the whole token.

## What the broker allows

| Command | Notes |
|---|---|
| `bws --version` | |
| `bws project list` | |
| `bws secret list [PROJECT_ID]` | values removed |
| `bws secret create [--note N] KEY VALUE PROJECT_ID` | response has the value removed |
| `bws secret edit [--key/--value/--note/--project-id] ID` | overwrites a value; set `BWS_BROKER_ALLOW_EDIT=0` to refuse |

Output formats: `json` (default), `tsv`, `none`. Everything else is refused,
including `secret get`, `secret delete`, `run`, `--server-url` and
`--access-token`. The devcontainer can **write** secrets but can't read one
back. `bws_upsert_secret.sh` (the `bws-upsert-secret` skill) only needs these
commands.

Requests are logged without values: `podman logs bws-broker`.

## Proxmox API proxy (`https://bws-broker:8006/`)

OpenTofu's `bpg/proxmox` provider talks to the broker instead of Proxmox, so
the Proxmox API token stays out of the devcontainer too:

```
 devcontainer: tofu ── https://bws-broker:8006/api2/json/... ──► bws-broker ── https (pinned) ──► Proxmox
               placeholder token                                 reads the real token from Bitwarden,
                                                                 replaces Authorization
```

A Proxmox token is a plain header, so unlike `bws` the broker can add it
without handing it out. Configured in [`../compose.yaml`](../compose.yaml):

| Variable | Value |
|---|---|
| `BWS_BROKER_PVE_URL` | `https://<proxmox>:8006` |
| `BWS_BROKER_PVE_TOKEN_SECRET_ID` | Bitwarden secret holding `user@realm!tokenid=uuid` (`proxmox_api_token`) |
| `BWS_BROKER_PVE_FINGERPRINT` | SHA-256 of the Proxmox API cert. The broker refuses to connect on a mismatch |

- **Separate TLS port.** bpg only accepts `https://` endpoints and drops any
  path prefix, so the proxy can't live under `:8080/pve`. Its cert is
  self-signed, made at startup in `/tmp`, so OpenTofu runs with
  `insecure = true`. Only the placeholder token crosses this hop.
- **Allowed paths:** `/version`, `/cluster/*` and `/nodes/*`, plus `GET
  /pools*`. Refused: `/access/*` (users, tokens, ACLs), `/storage/*`, consoles
  and shells (`termproxy`, `vncproxy`, `spiceproxy`, ...), migration tunnels,
  the batch `nodes/*/execute` call, and guest agent `exec`/`file-read`/
  `file-write`/`set-user-password`. Paths are checked after URL-decoding, and
  `..` segments are refused.
- **Rotating the Proxmox token:** update the Bitwarden secret. The broker
  re-reads it every 5 minutes, and immediately when Proxmox answers 401.
- **Proxmox cert renewed:** update `BWS_BROKER_PVE_FINGERPRINT` (the command
  is in `compose.yaml`) and recreate the broker.
- Leave `BWS_BROKER_PVE_URL` unset to turn the proxy off.

## Setup (on the host)

The devcontainer and the broker are two services in
[`../compose.yaml`](../compose.yaml). Compose builds both, starts the broker
first, and stops both when VS Code closes (`shutdownAction: stopCompose`).

1. Use **podman-compose** as the compose provider. The token is an external
   Podman secret, which docker-compose only supports with Swarm, and
   `podman compose` hands off to docker-compose when it's installed.
   ```bash
   brew install podman-compose
   ```
   In VS Code user settings:
   ```json
   "dev.containers.dockerPath": "podman",
   "dev.containers.dockerComposePath": "podman-compose"
   ```
   For the CLI: `devcontainer up --workspace-folder . --docker-path podman --docker-compose-path podman-compose`.
2. Store the token as a Podman secret, once:
   ```bash
   # bash
   read -rsp 'BWS access token: ' t && printf '%s' "$t" | podman secret create bws_access_token - ; unset t
   # zsh (read -p means something else there)
   read -rs 't?BWS access token: ' && printf '%s' "$t" | podman secret create bws_access_token - ; unset t
   ```
   If `02-ansible/playbooks/bws/token.yml` already stored the token in the
   macOS keychain, copy it from there instead:
   ```bash
   security find-generic-password -a "$USER" -s bws-access-token -w | podman secret create --replace bws_access_token -
   ```
   Without it the compose project, and so the devcontainer, won't start.
3. Rebuild or reopen the devcontainer.

Check from inside the devcontainer:

```bash
bws project list -o tsv
```

### Rotating the token

```bash
# bash
read -rsp 'BWS access token: ' t && printf '%s' "$t" | podman secret create --replace bws_access_token - ; unset t
# zsh
read -rs 't?BWS access token: ' && printf '%s' "$t" | podman secret create --replace bws_access_token - ; unset t
```

Then rebuild the devcontainer. A running broker keeps the old token until its
container is recreated.

## Limits of the isolation

- **Container socket.** Anything in the devcontainer that can reach the host's
  Podman or Docker socket can run `podman exec bws-broker ...` and read the
  token. Don't add docker-outside-of-docker or mount a container socket.
  docker-in-docker needs `--privileged`, which weakens the boundary (badly on
  rootful Podman), so avoid it too.
- **This directory is editable from the devcontainer.** `compose.yaml`
  decides what runs on the host (build contexts, mounts, privileges) and
  `server.py` runs with the token. A change made from inside the
  devcontainer (for example by an agent) takes effect at the next rebuild.
  Review `git diff .devcontainer` before rebuilding.
- **Writes are allowed.** Anything in the devcontainer can create secrets, or
  overwrite them unless `BWS_BROKER_ALLOW_EDIT=0`. Limit the machine account
  in Bitwarden to the projects it needs.
- **The Proxmox proxy still acts for the devcontainer.** The token can't be
  copied out, but anything in the devcontainer can make any allowed API call
  with it (create, change or delete VMs). The path rules narrow that, and the
  `tofu@pve` token's own Proxmox permissions are the real limit. OpenTofu's
  SSH access to Proxmox (root, through the SSH agent) is not covered by the
  broker at all.
- **Values pass through the devcontainer.** Values created there (generated
  or typed in) exist in the devcontainer briefly. Only existing secrets and
  the token are out of reach.
