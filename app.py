import os
from pathlib import Path

import dotenv
from eth_account.signers.local import LocalAccount
from eth_defi.uniswap_v3.constants import UNISWAP_V3_DEPLOYMENTS
from eth_defi.uniswap_v3.deployment import fetch_deployment
from web3 import HTTPProvider
import web3

from foundry_contracts import get_foundry_deployed_contract
from foundry_keystore import load_account_from_env
from utils import generate_jwt_from_private_pem, generate_keypair


UNISWAP_V3_DEPLOYER="0xE592427A0AEce92De3Edee1F18E0157C05861564"
UNISWAP_POOL_MANAGER="0x498581fF718922c3f8e6A244956aF099B2652b2b"

dotenv.load_dotenv(Path(__file__).with_name(".env"))


url = os.environ.get("ALCHEMY_ETH_RPC") or os.environ.get("ALCHEMY_RPC")
assert url is not None, "Invalid Ethereum RPC"

# gen keypair for alchemy
if not os.path.exists("/Users/bnelligan/DEFI/debndni/private.pem") and not os.path.exists("/Users/bnelligan/DEFI/debndni/receiver.pem"):
    print('generating keypair - couldnt find it')
    generate_keypair()

jwt_key_id = os.environ.get("JWT_PK_ID")
assert jwt_key_id is not None, "JWT_PK_ID not provided"
alchemy_jwt = generate_jwt_from_private_pem(
    "/Users/bnelligan/DEFI/debndni/private.pem",
    jwt_key_id,
)
headers = {
    "Accept": "application/json",
    "Authorization": f"Bearer {alchemy_jwt}",
    "Content-Type": "application/json",
}

account9e9: LocalAccount = load_account_from_env()

if os.environ.get("FOUNDRY_KEYSTORE_ACCOUNT"):
    account_source = f"Foundry keystore {os.environ['FOUNDRY_KEYSTORE_ACCOUNT']}"
    assert account_source is not None, "FOUNDRY_KEYSTORE_ACCOUNT was not derived from the environment"
elif os.environ.get("FOUNDRY_KEYSTORE_PASSWORD") or os.environ.get("CAST_UNSAFE_PASSWORD"):
    account_source = "Foundry keystore deployer"
else:
    account_source = "PK9E9"
print(f"Loaded local account from {account_source}: {account9e9.address}")

jwt_rpc_url = url.rsplit("/", 1)[0] if "/v2/" in url else url
w3_provider = HTTPProvider(jwt_rpc_url, request_kwargs={"headers": headers})

w3 = web3.Web3(w3_provider)
print(f"Connected to blockchain, chain id is {w3.eth.chain_id}. the latest block is {w3.eth.block_number:,}")

deployment_data = UNISWAP_V3_DEPLOYMENTS['ethereum']
print(deployment_data)
uniswap_v3 = fetch_deployment(
    w3,
    factory_address=deployment_data["factory"],
    router_address=deployment_data["router"],
    position_manager_address=deployment_data["position_manager"],
    quoter_address=deployment_data["quoter"],
)

print(f"Using Uniwap v3 compatible router at {uniswap_v3.swap_router.address}")
eth_balance = w3.eth.get_balance(account9e9.address)
print(f'Eth Balance {eth_balance}')



# Example for a contract deployed by `forge script script/Deploy.s.sol:Deploy --broadcast`.
# Keep this commented until this repo has a Foundry project with out/ and broadcast/ files.
#
# my_contract = get_foundry_deployed_contract(
#     w3=w3,
#     contract_name="MyContract",
#     script_name="Deploy.s.sol",
#     chain_id=w3.eth.chain_id,
#     project_root="/path/to/foundry/project",
# )
# print(f"MyContract deployed at {my_contract.address}")
