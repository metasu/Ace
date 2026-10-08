# Model Context-Window Resolution

Use this procedure when Hermes WebUI shows a smaller context window than expected for a selected model.

## Evidence layers

| Layer | What it proves | What it does not prove |
|---|---|---|
| Selected model/provider in active config | The requested routing identity | Actual server-side weights or official direct service |
| Trusted model catalog metadata | Published context/output limits for that model slug | A custom gateway honors the full limit |
| Provider `/models` response | The gateway exposes the requested model ID and any returned limits | Full limits when the response omits metadata |
| Hermes resolver result | The window Hermes will budget for a new/default session | Server acceptance beyond its own cap |
| Persisted session JSON/index | The historical snapshot used by an existing session | Current config after restart/new session |

## Diagnostic sequence

1. Locate the active `HERMES_HOME`; portable installs commonly use `<root>\data`, not `%USERPROFILE%\.hermes`.
2. Read only the non-secret `model` and named-provider fields from `config.yaml`.
3. Search trusted model metadata for the exact bare and provider-prefixed slug.
4. Query the selected provider's `/models` endpoint with the configured credential, printing only safe fields: model ID, context/input/output limits, and owner.
5. Inspect the current session/index for its persisted `context_length` and `threshold_tokens`.
6. Read `agent/model_metadata.py::get_model_context_length` and the WebUI session resolver to establish precedence. Typical order begins with explicit config, then custom-provider override/cache/live metadata, then catalogs/defaults.
7. Test the resolver with the exact model, provider, base URL, and prospective explicit value before changing configuration.

## Repair

When the trusted model metadata is current, the endpoint exposes the model but omits context fields, and the user wants Hermes budgeting to match the catalog:

```bash
hermes config set model.context_length <tokens>
```

On a portable install whose `hermes` launcher is unavailable, invoke the installed environment's Python against the checked-out CLI module rather than bypassing config guards by editing protected files:

```bash
<portable-python> -m hermes_cli.main config set model.context_length <tokens>
```

Then verify:

1. `config.yaml` contains the intended positive integer.
2. `get_model_context_length(...)` returns that value.
3. The WebUI default-model resolver returns the same value.
4. `hermes config check` passes.
5. A new session or restarted WebUI records the new value.

Do not patch an active session JSON solely to update the indicator. Existing sessions may retain old snapshots by design.

## Safety and accuracy

- Confirm that the global override is scoped to `model.default`; switched and fallback models need independent metadata.
- Do not use a client-side override to claim the provider supports that amount. A provider can reject or truncate requests above its server limit.
- Do not claim authentic model weights or official direct access from the slug alone.
- Never print API keys while probing `/models`.
