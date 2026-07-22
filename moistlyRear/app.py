


from flask import Flask, request


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

app = Flask(import_name=__name__)


@app.route("/")
def index():
    return '200'
    

@app.route('/auth', methods=['GET', 'POST'])
def auth():
    if request.method == 'GET':
        #TODO: Add method for user getting authentication credentials
        pass
    if request.method == 'POST':
        #TODO: Add method for validating credentials
        pass
    return '404'
