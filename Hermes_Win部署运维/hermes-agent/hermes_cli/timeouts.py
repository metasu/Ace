from __future__ import annotations


def _coerce_timeout(raw: object) -> float | None:
    try:
        timeout = float(raw)
    except (TypeError, ValueError):
        return None
    if timeout <= 0:
        return None
    return timeout


def _lookup_provider_config(providers: dict, provider_id: str) -> dict | None:
    """Return a provider config, matching IDs case-insensitively.

    Runtime provider IDs are normalized with ``str.lower()`` (see
    ``hermes_cli.models.normalize_provider``), but user-authored
    ``providers:`` keys in config.yaml may keep mixed case
    (e.g. ``SudoCX-gpt-5.6-sol``). An exact-key miss would drop
    ``request_timeout_seconds`` and fall back to ``HERMES_API_TIMEOUT``.
    """
    if not isinstance(providers, dict) or not provider_id:
        return None
    direct = providers.get(provider_id)
    if isinstance(direct, dict):
        return direct
    needle = provider_id.casefold()
    for key, value in providers.items():
        if isinstance(key, str) and key.casefold() == needle and isinstance(value, dict):
            return value
    return None


def get_provider_request_timeout(
    provider_id: str, model: str | None = None
) -> float | None:
    """Return a configured provider request timeout in seconds, if any."""
    if not provider_id:
        return None

    try:
        from hermes_cli.config import load_config_readonly
        config = load_config_readonly()
    except Exception:
        return None

    providers = config.get("providers", {}) if isinstance(config, dict) else {}
    provider_config = _lookup_provider_config(providers, provider_id)
    if not isinstance(provider_config, dict):
        return None

    model_config = _get_model_config(provider_config, model)
    if model_config is not None:
        timeout = _coerce_timeout(model_config.get("timeout_seconds"))
        if timeout is not None:
            return timeout

    return _coerce_timeout(provider_config.get("request_timeout_seconds"))


def get_provider_stale_timeout(
    provider_id: str, model: str | None = None
) -> float | None:
    """Return a configured non-stream stale timeout in seconds, if any."""
    if not provider_id:
        return None

    try:
        from hermes_cli.config import load_config_readonly
        config = load_config_readonly()
    except Exception:
        return None

    providers = config.get("providers", {}) if isinstance(config, dict) else {}
    provider_config = _lookup_provider_config(providers, provider_id)
    if not isinstance(provider_config, dict):
        return None

    model_config = _get_model_config(provider_config, model)
    if model_config is not None:
        timeout = _coerce_timeout(model_config.get("stale_timeout_seconds"))
        if timeout is not None:
            return timeout

    return _coerce_timeout(provider_config.get("stale_timeout_seconds"))


def _get_model_config(
    provider_config: dict[str, object], model: str | None
) -> dict[str, object] | None:
    if not model:
        return None

    models = provider_config.get("models", {})
    model_config = models.get(model, {}) if isinstance(models, dict) else {}
    if isinstance(model_config, dict):
        return model_config
    return None
