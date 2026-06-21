import os
import sys
import pytest
from unittest.mock import MagicMock

HANDLERS_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..",
    "terraform/modules/lambda-functions/handlers",
)
GLUE_SCRIPTS_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..",
    "terraform/modules/glue-jobs/scripts",
)
sys.path.insert(0, os.path.abspath(HANDLERS_DIR))
sys.path.insert(0, os.path.abspath(GLUE_SCRIPTS_DIR))


def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line(
        "markers", "slow: marks tests as slow (deselect with '-m \"not slow\"')"
    )
    config.addinivalue_line(
        "markers",
        "spark: marks tests that require a local SparkSession "
        "(skip with '-m \"not spark\"' if Java is unavailable)",
    )


@pytest.fixture
def lambda_context():
    """Return a mock Lambda context with aws_request_id."""
    ctx = MagicMock()
    ctx.aws_request_id = "test-request-id"
    ctx.function_name = "test-function"
    ctx.invoked_function_arn = (
        "arn:aws:lambda:us-east-1:123456789012:function:test-function"
    )
    return ctx
