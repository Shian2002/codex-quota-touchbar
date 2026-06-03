# Security

Codex Quota Touch Bar is a local-only utility.

- It starts the local Codex binary at `/Applications/Codex.app/Contents/Resources/codex`.
- It talks to `codex app-server --listen stdio://` through local stdio JSON-RPC.
- It reads `account/rateLimits/read` and renders the result in the menu bar and Touch Bar.
- It does not send quota data to a third-party server.
- It does not store tokens, account data, or quota snapshots.

If you find a security issue, open a GitHub issue with reproduction details and avoid posting secrets or private account data.

