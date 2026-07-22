
from flask import current_app


def provider_status() -> dict:
    rpc_providers = current_app.config.get("RPC_PROVIDERS", {})
    wallet_providers = current_app.config.get("WALLET_PROVIDERS", ())

    wallet_status = {}
    for provider in wallet_providers:
        if provider == "alchemy":
            configured = bool(current_app.config.get("ALCHEMY_API_KEY"))
        elif provider == "privy":
            configured = bool(
                current_app.config.get("PRIVY_APP_ID")
                and current_app.config.get("PRIVY_APP_SECRET")
            )
        else:
            configured = True
        wallet_status[provider] = {"configured": configured}

    return {
        "default_rpc_provider": current_app.config.get("DEFAULT_RPC_PROVIDER"),
        "rpc": {
            name: {"configured": bool(url)}
            for name, url in rpc_providers.items()
        },
        "wallets": wallet_status,
    }
