#!/usr/bin/env python3
"""Make /api/models?freshness=session_visit stale-while-revalidate (idempotent).

Upstream session-visit freshness waits on a live provider-catalog rebuild
(up to HERMES_WEBUI_MODELS_REBUILD_BUDGET, default 4s) even when a
shape-valid stale cache exists. That blocks session load / model picker
and can starve streaming (Broken pipe).

Fix: if a stale catalog is available, return it immediately and kick a
coalesced background refresh.
"""
from __future__ import annotations

import sys
from pathlib import Path

WEBUI = Path(sys.argv[1] if len(sys.argv) > 1 else "/opt/hermes/hermes-webui")
CONFIG = WEBUI / "api" / "config.py"

HELPER = '''_session_visit_refresh_lock = threading.Lock()
_session_visit_refresh_in_flight = False


def _kick_session_visit_background_refresh() -> None:
    """Start at most one out-of-band live catalog refresh for session_visit SWR.

    The session-visit hot path must not wait on provider probes. When a
    shape-valid stale catalog exists, return it immediately and let this
    helper coalesce overlapping refresh kicks onto a single daemon thread.
    """
    global _session_visit_refresh_in_flight
    with _session_visit_refresh_lock:
        if _session_visit_refresh_in_flight or _cache_build_in_progress:
            return
        _session_visit_refresh_in_flight = True

    def _refresh_worker() -> None:
        global _session_visit_refresh_in_flight
        try:
            get_available_models(force_refresh=True)
        except Exception:
            logger.debug("session-visit background models refresh failed", exc_info=True)
        finally:
            with _session_visit_refresh_lock:
                _session_visit_refresh_in_flight = False

    threading.Thread(
        target=_refresh_worker,
        name="models-session-visit-refresh",
        daemon=True,
    ).start()


'''

OLD_STALE = '''    _mark("cache_age_stale_or_missing")
    stale_cached = disk_cached or _load_stale_models_cache_from_disk()
    _mark(f"stale_cached_loaded:{bool(stale_cached)}")
    try:
        _mark("force_refresh_start")
        result = get_available_models(force_refresh=True)
        _mark("force_refresh_done")
        _maybe_log_slow_stages(_logger, _stagelog, _slow_threshold_ms, "models.session_visit")
        return result
    except Exception:
        _mark("force_refresh_failed")
        logger.debug("session-visit models refresh failed", exc_info=True)
        if stale_cached is not None:
            _mark("stale_fallback_return")
            _maybe_log_slow_stages(_logger, _stagelog, _slow_threshold_ms, "models.session_visit")
            return copy.deepcopy(stale_cached)
        _mark("prefer_cache_fallback")
        _maybe_log_slow_stages(_logger, _stagelog, _slow_threshold_ms, "models.session_visit")
        return get_available_models(prefer_cache=True)
'''

NEW_STALE = '''    _mark("cache_age_stale_or_missing")
    stale_cached = disk_cached or _load_stale_models_cache_from_disk()
    _mark(f"stale_cached_loaded:{bool(stale_cached)}")
    # session-visit SWR: if a prior live rebuild already published a fresh
    # memory cache, return it instead of serving stale + kicking another.
    if stale_cached is not None:
        with _available_models_cache_lock:
            if (
                _available_models_live_rebuild_ts > 0
                and _available_models_live_rebuild_ts >= _available_models_cache_ts
            ):
                fresh = _get_fresh_memory_models_cache(time.monotonic())
                if fresh is not None:
                    _mark("stale_path_live_rebuild_cache_hit")
                    _maybe_log_slow_stages(_logger, _stagelog, _slow_threshold_ms, "models.session_visit")
                    return fresh
        _kick_session_visit_background_refresh()
        _mark("stale_swr_return")
        _maybe_log_slow_stages(_logger, _stagelog, _slow_threshold_ms, "models.session_visit")
        return copy.deepcopy(stale_cached)
    try:
        _mark("force_refresh_start")
        result = get_available_models(force_refresh=True)
        _mark("force_refresh_done")
        _maybe_log_slow_stages(_logger, _stagelog, _slow_threshold_ms, "models.session_visit")
        return result
    except Exception:
        _mark("force_refresh_failed")
        logger.debug("session-visit models refresh failed", exc_info=True)
        _mark("prefer_cache_fallback")
        _maybe_log_slow_stages(_logger, _stagelog, _slow_threshold_ms, "models.session_visit")
        return get_available_models(prefer_cache=True)
'''

ANCHOR = "def get_available_models_for_session_visit() -> dict:\n"


def ready(text: str) -> bool:
    return (
        "def _kick_session_visit_background_refresh() -> None:" in text
        and "stale_swr_return" in text
        and "stale_path_live_rebuild_cache_hit" in text
        and "_kick_session_visit_background_refresh()" in text
    )


def apply(text: str) -> str:
    if ready(text):
        return text
    if ANCHOR not in text:
        raise RuntimeError("config.py: get_available_models_for_session_visit() not found")
    if "def _kick_session_visit_background_refresh() -> None:" not in text:
        text = text.replace(ANCHOR, HELPER + ANCHOR, 1)
    if "stale_swr_return" not in text:
        if OLD_STALE not in text:
            raise RuntimeError("config.py: upstream session_visit stale block changed")
        text = text.replace(OLD_STALE, NEW_STALE, 1)
    if not ready(text):
        raise RuntimeError("config.py: session_visit SWR patch did not apply cleanly")
    return text


def main() -> int:
    if not CONFIG.is_file():
        print(f"SKIP: missing {CONFIG}")
        return 0
    original = CONFIG.read_text(encoding="utf-8")
    if ready(original):
        print(f"OK: already patched {CONFIG}")
        return 0
    updated = apply(original)
    CONFIG.write_text(updated, encoding="utf-8")
    print(f"OK: patched {CONFIG}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
