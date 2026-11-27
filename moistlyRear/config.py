# moistlyRear/config.py
import os


def _rpc_providers() -> dict[str, str]:
    providers: dict[str, str] = {}

    mapping = {
        "ethereum": ("ALCHEMY_ETH_RPC",),
        "base": ("ALCHEMY_BASE_RPC",),
        "arbitrum": ("ALCHEMY_ARB_RPC",),
        "bnb": ("ALCHEMY_BNB_RPC",),
        "elysium": ("ALCHEMY_ELYSIUM_RPC", "ELYSIUM_RPC"),
        "elysium-testnet": ("ALCHEMY_ELYSIUM_TESTNET_RPC", "ELYSIUM_TESTNET_RPC"),
        "hyperevm": ("ALCHEMY_HYPEREVM_RPC", "HYPEREVM_RPC"),
    }

    defaults = {
        "elysium": "https://rpc.elysium.kinetiq.xyz",
        "elysium-testnet": "https://testnet-rpc.elysium.kinetiq.xyz",
        "hyperevm": "https://rpc.hyperliquid.xyz/evm",
    }

    for name, env_vars in mapping.items():
        for env_var in env_vars:
            value = os.environ.get(env_var)
            if value:
                providers[name] = value
                break
        else:
            if name in defaults:
                providers[name] = defaults[name]

    return providers


class BaseConfig:
    TESTING = False
    RPC_PROVIDERS = _rpc_providers()
    DEFAULT_RPC_PROVIDER = os.environ.get("DEFAULT_RPC_PROVIDER", "elysium")
    WALLET_PROVIDERS = ("alchemy", "privy")
    ALCHEMY_API_KEY = os.environ.get("ALCHEMY_API_KEY")
    PRIVY_APP_ID = os.environ.get("PRIVY_APP_ID")
    PRIVY_APP_SECRET = os.environ.get("PRIVY_APP_SECRET")


class LocalConfig(BaseConfig):
    DEBUG = True


class RemoteConfig(BaseConfig):
    DEBUG = False


class TestingConfig(BaseConfig):
    TESTING = True
