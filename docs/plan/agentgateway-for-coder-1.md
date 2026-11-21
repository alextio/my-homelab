# No API tokens on coder-1

Status: idea
Depends on: agentgateway proxy running again (new hardware); see
[README.md](README.md#later).

## Why

Claude Code and pi on coder-1 need LLM API tokens. If the tokens sit on the
VM, anything that runs there (an agent, a dependency's install script, a
compromised tool) can read them and use them from anywhere until they are
rotated. coder-1 runs untrusted code by design, which is why it is already
LAN-isolated.

## Options

1. **Tokens on the VM** (current default). Simple, but it has the problem
   above.
2. **Route through agentgateway (preferred).** agentgateway holds the
   provider tokens. coder-1 talks only to agentgateway, which the
   LAN-isolation firewall already allows. The VM then needs a credential
   for agentgateway itself, or none if agentgateway trusts coder-1's
   address.
3. **Short-lived tokens injected per session.** Stronger than option 1, but
   needs tooling we don't have.

## Security

- With option 2, a compromise of coder-1 can still *use* the LLM APIs
  through agentgateway, but it can't take the provider tokens away. Rate
  limits or a spend cap on agentgateway bound the damage.
- If agentgateway trusts coder-1 by IP alone, anything that can send from
  that IP gets access. A per-client key is better, but it is a secret on
  the VM again (a revocable one, scoped to agentgateway).
- The provider tokens then live in agentgateway's Secret (from
  ExternalSecrets/Bitwarden). Anyone who can read secrets in the
  `agentgateway` namespace can read them.

## Open questions

- How should coder-1 authenticate to agentgateway: IP allow-list, API key,
  or mTLS?
- Do Claude Code and pi both support a custom base URL for every feature
  they use?
