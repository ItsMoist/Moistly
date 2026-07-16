

import base64
import json
import time
from pathlib import Path

from Crypto.Hash import SHA256
from Crypto.PublicKey import RSA
from Crypto.Signature import pkcs1_15


def generate_keypair():
    """Generate a local RSA keypair for JWT signing."""
    key = RSA.generate(2048)
    private_key = key.export_key()
    with open("private.pem", "wb") as f:
        f.write(private_key)

    public_key = key.publickey().export_key()
    with open("receiver.pem", "wb") as f:
        f.write(public_key)


def generate_jwt_from_private_pem(
    private_key_path: str | Path,
    key_id: str | None = None,
    expires_in_seconds: int = 300,
    include_iat: bool = True,
) -> str:
    now = int(time.time())
    header = {
        "alg": "RS256",
        "typ": "JWT",
    }
    if key_id:
        header["kid"] = key_id

    payload = {"exp": now + expires_in_seconds}
    if include_iat:
        payload["iat"] = now

    signing_input = ".".join(
        [
            _base64url_json(header),
            _base64url_json(payload),
        ]
    ).encode("ascii")

    private_key = RSA.import_key(Path(private_key_path).read_bytes())
    digest = SHA256.new(signing_input)
    signature = pkcs1_15.new(private_key).sign(digest)

    return signing_input.decode("ascii") + "." + _base64url_bytes(signature)


def _base64url_json(value: dict) -> str:
    encoded = json.dumps(value, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return _base64url_bytes(encoded)


def _base64url_bytes(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")
