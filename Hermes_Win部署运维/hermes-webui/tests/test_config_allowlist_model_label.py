"""Picker labels for providers.<provider>.models allowlist entries.

A vendor-routing prefix (``xai/grok-4.3``) must stay in the option VALUE — the
provider requires it — but the dropdown should read ``grok-4.3`` instead of
repeating the full routing id.
"""


def test_vendor_prefix_is_dropped_from_label():
    from api.config import _config_model_allowlist_label

    assert _config_model_allowlist_label("xai/grok-4.3") == "grok-4.3"
    assert _config_model_allowlist_label("xai/grok-4.5") == "grok-4.5"


def test_bare_model_id_is_unchanged():
    from api.config import _config_model_allowlist_label

    assert _config_model_allowlist_label("gpt-5.6-sol") == "gpt-5.6-sol"


def test_multi_segment_id_keeps_remaining_hierarchy():
    from api.config import _config_model_allowlist_label

    assert _config_model_allowlist_label("proxy/deepseek/deepseek-v4-pro") == (
        "deepseek/deepseek-v4-pro"
    )


def test_uri_scheme_id_is_untouched():
    from api.config import _config_model_allowlist_label

    model_id = "gpt://folder123/deepseek-v4-flash/latest"
    assert _config_model_allowlist_label(model_id) == model_id


def test_empty_and_non_string_inputs_are_safe():
    from api.config import _config_model_allowlist_label

    assert _config_model_allowlist_label("") == ""
    assert _config_model_allowlist_label(None) == ""
    assert _config_model_allowlist_label("  xai/grok-4.3  ") == "grok-4.3"
