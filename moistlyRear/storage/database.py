from flask import current_app
from sqlalchemy import URL, create_engine
from sqlalchemy.orm import Session


def database_url() -> URL:
    password = current_app.config.get("MSSQL_PASSWORD")
    if not password:
        raise RuntimeError("MSSQL_SA_PASSWORD is not configured")
    return URL.create(
        "mssql+pymssql",
        username=current_app.config.get("MSSQL_USER", "sa"),
        password=password,
        host=current_app.config.get("MSSQL_HOST", "127.0.0.1"),
        port=current_app.config.get("MSSQL_PORT", 1433),
        database=current_app.config.get("MSSQL_DATABASE", "moistly"),
    )


def engine():
    cached = current_app.extensions.get("moistly_database_engine")
    if cached is None:
        cached = create_engine(
            database_url(),
            pool_pre_ping=True,
            connect_args={"login_timeout": 5, "timeout": 10},
        )
        current_app.extensions["moistly_database_engine"] = cached
    return cached


def session() -> Session:
    return Session(engine())
