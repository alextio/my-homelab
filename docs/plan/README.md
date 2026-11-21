# Roadmap

Improvements we intend to make to the homelab. Format: [AGENTS.md](AGENTS.md).
Finished work moves to [docs/journey/](../journey/).

## Now

- **Finish coder-1 setup.** Install the homelab CA and the remaining default
  tools (Python with uv, Go, Rust, Chromium with Playwright). T3 Code,
  Node, pi and Claude Code are done.
  from: [coder-1 rootless podman VM](../journey/20261121-coder-1-rootless-podman-vm.md),
  [T3 Code on coder-1](../journey/20261121-t3code-on-coder-1.md)
- **Harden the DuckDNS webhook.** Run it as non-root, build our own image
  without the log line that puts the token in a URL, and give it a dedicated
  namespace and a NetworkPolicy. `TODO(duckdns)` in
  `03-argocd-kubernetes/manifests/templates/duckdns.yaml`.
  from: [Let's Encrypt via DuckDNS](../journey/20261120-lets-encrypt-via-duckdns.md)

## Next

- **Certificate expiry alert.** Alert on
  `certmanager_certificate_expiration_timestamp_seconds`, so a dead webhook
  or a rotated token shows up before every certificate expires on the same
  day.
  from: [Let's Encrypt via DuckDNS](../journey/20261120-lets-encrypt-via-duckdns.md)
- **Move Dex off `dex.lan`.** Then remove `homelab-root-ca` from client
  devices. Keep the CA for in-cluster use (bitwarden-sdk-server).
  from: [Let's Encrypt via DuckDNS](../journey/20261120-lets-encrypt-via-duckdns.md)
- **Remove the old `.lan` routes and Dex callbacks** once nothing uses them.
  Do this after the Dex move.
  from: [Let's Encrypt via DuckDNS](../journey/20261120-lets-encrypt-via-duckdns.md)
- **Inbound firewall rules for coder-1.** Decide what may reach it, for
  example SSH and the T3 server (port 3773, where a pairing code is the
  only lock) only from the home subnet and the Tailscale subnet router.
  from: [LAN isolation firewall](../journey/20261121-lan-isolation-firewall-for-coder-1.md),
  [T3 Code on coder-1](../journey/20261121-t3code-on-coder-1.md)

## Later

- **No API tokens on coder-1.** Point Claude Code and pi at agentgateway
  instead. Waits on the agentgateway proxy, which waits on new hardware.
  Design: [agentgateway-for-coder-1.md](agentgateway-for-coder-1.md).
  from: [coder-1 rootless podman VM](../journey/20261121-coder-1-rootless-podman-vm.md)
- **Bring agentgateway back on new hardware.** The proxy crash-loops with
  SIGILL (exit 132), most likely a CPU instruction the current host lacks,
  so nothing serves `192.168.6.202`. On the new host, remove `replicas` from
  `apps/agentgateway/parameters-proxy.yaml` (`03-argocd-kubernetes`).
  from: [Let's Encrypt via DuckDNS](../journey/20261120-lets-encrypt-via-duckdns.md),
  [LAN isolation firewall](../journey/20261121-lan-isolation-firewall-for-coder-1.md)
- **Unpin Claude Code on coder-1.** Remove `claude_code_npm_version`
  (2.1.112, the last release that runs on the Athlon II) from
  `host_vars/coder-1/vars.yml` (`02-ansible`). Waits on new hardware.
  from: [T3 Code on coder-1](../journey/20261121-t3code-on-coder-1.md)
- **If Coder comes back:** a workspace node needs `node-taint` /
  `node-label` in its k3s config, and its old `.node-password.k3s` entry
  deleted. `templates push` needs a Coder owner or template admin.
  from: [Coder workspaces as k3s pods](../journey/20261120-coder-workspaces-as-k3s-pods.md)

## Housekeeping

- **Merge `chore/agentgateway-scale-to-zero`** (`03-argocd-kubernetes`).
  Then check that `kubectl -n agentgateway get deploy agentgateway-proxy`
  shows `0/0`. The controller's handling of `replicas: 0` is untested.
- **Merge `chore/coder-scale-to-zero`** (`03-argocd-kubernetes`). Coder
  keeps running until it is merged.
- **Merge `refactor/roles`** (`02-ansible`) and `feat/coder-1-agent-vm`
  (parent repo), then bump the submodules in the parent repo.
- **Rebuild and verify the dev container** with `devcontainer up`
  (`.devcontainer/AGENTS.md`): check `echo $LOGNAME $LANG` prints
  `vscode C.UTF-8` and that `start-t3.sh` started `t3 serve`.
  from: [T3 Code on coder-1](../journey/20261121-t3code-on-coder-1.md)
- **Finish the T3 providers on coder-1.** Enable Pi in the T3 app, log in
  to pi (`/login`) and Claude Code (`claude auth login`), and check T3
  works with Claude Code 2.1.112.
  from: [T3 Code on coder-1](../journey/20261121-t3code-on-coder-1.md)
- **Suspend or delete Coder's `a` account**, if it isn't done yet.
- **Delete the two Bitwarden secrets** for the old coder-1 `coder` user.
  Nothing has read them since PR #5.
- **Check Coder's HTTPRoute**, which showed OutOfSync in Argo CD. It's
  unknown whether it was OutOfSync before.
