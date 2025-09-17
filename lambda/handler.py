import os
import boto3
from botocore.exceptions import BotoCoreError, ClientError

_ssm_client = boto3.client("ssm")

PARAM_NAME = os.getenv("PARAM_NAME")
DEFAULT_STRING = os.getenv("DEFAULT_STRING", "Hello")


def _get_dynamic_string() -> str:
    if not PARAM_NAME:
        return DEFAULT_STRING
    try:
        resp = _ssm_client.get_parameter(Name=PARAM_NAME, WithDecryption=False)
        value = resp.get("Parameter", {}).get("Value")
        if not value:
            return DEFAULT_STRING
        return value
    except (BotoCoreError, ClientError):
        return DEFAULT_STRING


def lambda_handler(event, context):
    value = _get_dynamic_string()
    html = f"<h1>The saved string is {value}</h1>"
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "text/html; charset=utf-8"
        },
        "body": html,
    }
