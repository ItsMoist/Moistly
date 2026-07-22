


from flask import Flask


from .config import LocalConfig, RemoteConfig, TestingConfig


CONFIGS = {
    "local": LocalConfig,
    "remote": RemoteConfig,
    "testing": TestingConfig,
}


def create_app(environment="local"):
    try:
        config = CONFIGS[environment]
    except KeyError:
        raise ValueError(f"Unknown environment: {environment}") from None

    app = Flask(__name__)
    app.config.from_object(config)
    return app

app = Flask(import_name=__name__, static_host='moistbandz.com')


@app.route("/")
def index():
    pass
    

@app.route('/auth', methods=['GET', 'POST'])
def auth():
