# moistlyRear/config.py
class BaseConfig:
    TESTING = False


class LocalConfig(BaseConfig):
    DEBUG = True


class RemoteConfig(BaseConfig):
    DEBUG = False


class TestingConfig(BaseConfig):
    TESTING = True
