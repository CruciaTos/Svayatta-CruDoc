"""Resolves the correct provider adapter for a clinic's configuration.
This is the only place that knows which providers exist."""
from app.providers.base import AppointmentProvider
from app.providers.crudoc_adapter import CruDocAdapter

# Required keys in Clinic.config["appointment_provider_config"], per provider.
REQUIRED_CONFIG_KEYS = {"crudoc": ("base_url", "api_key")}

# Optional keys a clinic may set to override an adapter's defaults. CruDoc
# has no working-hours model of its own, so the availability grid is
# configured here per tenant.
OPTIONAL_CONFIG_KEYS = {"crudoc": ("open_time", "close_time", "slot_minutes")}

KNOWN_PROVIDERS = tuple(REQUIRED_CONFIG_KEYS)

# Every adapter owns an httpx.AsyncClient, i.e. a connection pool. Building
# a fresh adapter per tool call -- which is what the call sites do, once for
# availability and again for booking -- leaked a pool per call that was
# never closed, so a busy line would climb toward the process fd limit.
# Adapters hold no per-call state beyond that pool and are safe to share
# across concurrent calls, so they are cached against the exact config they
# were built from: a rotated credential yields a different key and
# therefore a fresh adapter.
_ADAPTER_CACHE: dict[tuple, AppointmentProvider] = {}


class ProviderNotConfiguredError(ValueError):
    """A clinic names a provider but is missing the config it needs.

    Raised instead of a bare KeyError so the cause is visible in the tool
    error and in preflight, rather than surfacing to the caller as a
    generic "could not be completed right now".
    """


def missing_config_keys(provider_name: str, provider_config: dict) -> list[str]:
    """Config keys this provider needs but the clinic has not set."""
    required = REQUIRED_CONFIG_KEYS.get(provider_name, ())
    return [key for key in required if not (provider_config or {}).get(key)]


def reset_provider_cache() -> None:
    """Drop cached adapters. For tests and config-reload paths."""
    _ADAPTER_CACHE.clear()


def _cached(key: tuple, build) -> AppointmentProvider:
    adapter = _ADAPTER_CACHE.get(key)
    if adapter is None:
        adapter = build()
        _ADAPTER_CACHE[key] = adapter
    return adapter


def get_provider(
    provider_name: str,
    provider_config: dict,
    timezone: str = "Asia/Kolkata",
) -> AppointmentProvider:
    """Adapter for this clinic's provider.

    `timezone` is the clinic's IANA zone. Adapters need it to qualify a
    naive slot time and to tell the provider which day boundaries an
    availability request means -- without it a booking can land hours off.
    """
    if provider_name not in KNOWN_PROVIDERS:
        raise ValueError(f"Unknown appointment provider: {provider_name}")

    missing = missing_config_keys(provider_name, provider_config)
    if missing:
        raise ProviderNotConfiguredError(
            f"Clinic's {provider_name} config is missing: {', '.join(missing)}. "
            f"Set them in the clinic's config.appointment_provider_config."
        )

    if provider_name == "crudoc":
        kwargs: dict = {
            "base_url": provider_config["base_url"],
            "api_key": provider_config["api_key"],
            "timezone": timezone,
        }
        # Only forward overrides the clinic actually set, so the adapter's
        # own defaults stay the single definition of them.
        if provider_config.get("open_time"):
            kwargs["open_time"] = str(provider_config["open_time"])
        if provider_config.get("close_time"):
            kwargs["close_time"] = str(provider_config["close_time"])
        if provider_config.get("slot_minutes"):
            try:
                kwargs["slot_minutes"] = int(provider_config["slot_minutes"])
            except (TypeError, ValueError) as exc:
                raise ProviderNotConfiguredError(
                    f"slot_minutes must be an integer, got "
                    f"{provider_config['slot_minutes']!r}"
                ) from exc

        key = ("crudoc",) + tuple(sorted(kwargs.items()))
        return _cached(key, lambda: CruDocAdapter(**kwargs))

    raise ValueError(f"Unknown appointment provider: {provider_name}")
