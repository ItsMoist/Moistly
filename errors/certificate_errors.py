


class CertificateNotLoadedFromEnvironmentError(Exception):
    """Raised when a certificate is not loaded from the environment."""
    def __init__(self, *args):
        super().__init__(*args)
    pass
