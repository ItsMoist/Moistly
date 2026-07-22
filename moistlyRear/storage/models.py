from datetime import datetime

from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, Identity, Integer, SmallInteger, String, Text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class Chain(Base):
    __tablename__ = "chains"

    id: Mapped[int] = mapped_column(Integer, Identity(), primary_key=True)
    provider: Mapped[str] = mapped_column(String(32))
    chain_id: Mapped[int] = mapped_column(BigInteger)
    name: Mapped[str] = mapped_column(String(128))
    rpc_alias: Mapped[str | None] = mapped_column(String(128))
    is_testnet: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime)
    updated_at: Mapped[datetime] = mapped_column(DateTime)

    blocks: Mapped[list["Block"]] = relationship(back_populates="chain")
    transactions: Mapped[list["Transaction"]] = relationship(back_populates="chain")
    tracked_accounts: Mapped[list["TrackedAccount"]] = relationship(back_populates="chain")


class Wallet(Base):
    __tablename__ = "wallets"

    id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    provider: Mapped[str] = mapped_column(String(32))
    provider_wallet_id: Mapped[str | None] = mapped_column(String(255))
    address: Mapped[str] = mapped_column(String(66))
    chain_type: Mapped[str] = mapped_column(String(32), default="ethereum")
    owner_external_id: Mapped[str | None] = mapped_column(String(255))
    display_name: Mapped[str | None] = mapped_column(String(128))
    policy_id: Mapped[str | None] = mapped_column(String(255))
    metadata_json: Mapped[str | None] = mapped_column("metadata", Text)
    created_at: Mapped[datetime] = mapped_column(DateTime)
    updated_at: Mapped[datetime] = mapped_column(DateTime)

    webhook_events: Mapped[list["WebhookEvent"]] = relationship(back_populates="wallet")


class TrackedAccount(Base):
    __tablename__ = "tracked_accounts"

    id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    chain_ref: Mapped[int] = mapped_column(ForeignKey("chains.id"))
    address: Mapped[str] = mapped_column(String(66))
    label: Mapped[str | None] = mapped_column(String(128))
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime)

    chain: Mapped[Chain] = relationship(back_populates="tracked_accounts")


class Block(Base):
    __tablename__ = "blocks"

    id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    chain_ref: Mapped[int] = mapped_column(ForeignKey("chains.id"))
    block_number: Mapped[int] = mapped_column(BigInteger)
    block_hash: Mapped[str] = mapped_column(String(66))
    parent_hash: Mapped[str | None] = mapped_column(String(66))
    block_timestamp: Mapped[datetime | None] = mapped_column(DateTime)
    transaction_count: Mapped[int] = mapped_column(Integer, default=0)
    raw_json: Mapped[str | None] = mapped_column(Text)
    indexed_at: Mapped[datetime] = mapped_column(DateTime)

    chain: Mapped[Chain] = relationship(back_populates="blocks")


class Transaction(Base):
    __tablename__ = "transactions"

    id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    chain_ref: Mapped[int] = mapped_column(ForeignKey("chains.id"))
    tx_hash: Mapped[str] = mapped_column(String(66))
    block_number: Mapped[int | None] = mapped_column(BigInteger)
    block_hash: Mapped[str | None] = mapped_column(String(66))
    transaction_index: Mapped[int | None] = mapped_column(Integer)
    from_address: Mapped[str] = mapped_column(String(66))
    to_address: Mapped[str | None] = mapped_column(String(66))
    nonce: Mapped[int] = mapped_column(BigInteger)
    value_wei: Mapped[str] = mapped_column(String(78))
    gas_limit: Mapped[str | None] = mapped_column(String(78))
    gas_price_wei: Mapped[str | None] = mapped_column(String(78))
    status: Mapped[int | None] = mapped_column(SmallInteger)
    input_data: Mapped[str | None] = mapped_column(Text)
    raw_json: Mapped[str | None] = mapped_column(Text)
    indexed_at: Mapped[datetime] = mapped_column(DateTime)

    chain: Mapped[Chain] = relationship(back_populates="transactions")
    deployments: Mapped[list["ContractDeployment"]] = relationship(back_populates="transaction")


class ContractDeployment(Base):
    __tablename__ = "contract_deployments"

    id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    chain_ref: Mapped[int] = mapped_column(ForeignKey("chains.id"))
    transaction_ref: Mapped[int | None] = mapped_column(ForeignKey("transactions.id"))
    contract_address: Mapped[str] = mapped_column(String(66))
    deployer_address: Mapped[str | None] = mapped_column(String(66))
    contract_name: Mapped[str | None] = mapped_column(String(255))
    artifact_path: Mapped[str | None] = mapped_column(String(1024))
    create2_salt: Mapped[str | None] = mapped_column(String(66))
    metadata_json: Mapped[str | None] = mapped_column("metadata", Text)
    deployed_at: Mapped[datetime | None] = mapped_column(DateTime)
    created_at: Mapped[datetime] = mapped_column(DateTime)

    transaction: Mapped[Transaction | None] = relationship(back_populates="deployments")


class WebhookEvent(Base):
    __tablename__ = "webhook_events"

    id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    received_at: Mapped[datetime] = mapped_column(DateTime)
    provider: Mapped[str] = mapped_column(String(32))
    event_type: Mapped[str | None] = mapped_column(String(255))
    verified: Mapped[bool] = mapped_column(Boolean)
    verify_reason: Mapped[str | None] = mapped_column(String(512))
    path: Mapped[str] = mapped_column(String(512))
    transaction_hash: Mapped[str | None] = mapped_column(String(66))
    payload: Mapped[str] = mapped_column(Text)
    normalized: Mapped[str] = mapped_column(Text)
    actions: Mapped[str] = mapped_column(Text)
    reaction: Mapped[str] = mapped_column(Text)
    chain_ref: Mapped[int | None] = mapped_column(ForeignKey("chains.id"))
    wallet_ref: Mapped[int | None] = mapped_column(ForeignKey("wallets.id"))

    wallet: Mapped[Wallet | None] = relationship(back_populates="webhook_events")


class ProcessingCheckpoint(Base):
    __tablename__ = "processing_checkpoints"

    consumer: Mapped[str] = mapped_column(String(128), primary_key=True)
    chain_ref: Mapped[int] = mapped_column(ForeignKey("chains.id"), primary_key=True)
    last_block_number: Mapped[int] = mapped_column(BigInteger)
    updated_at: Mapped[datetime] = mapped_column(DateTime)
