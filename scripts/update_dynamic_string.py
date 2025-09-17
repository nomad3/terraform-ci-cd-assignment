#!/usr/bin/env python3
import argparse
import subprocess
import sys
from typing import Optional

import boto3
from botocore.exceptions import BotoCoreError, ClientError


def get_param_name_from_terraform() -> Optional[str]:
    try:
        result = subprocess.run(
            ["terraform", "output", "-raw", "ssm_parameter_name"],
            check=True,
            capture_output=True,
            text=True,
        )
        name = result.stdout.strip()
        return name or None
    except Exception:
        return None


def update_parameter(name: str, value: str) -> None:
    ssm = boto3.client("ssm")
    try:
        ssm.put_parameter(Name=name, Value=value, Type="String", Overwrite=True)
        print(f"Updated SSM parameter {name} to: {value}")
    except (BotoCoreError, ClientError) as e:
        print(f"Failed to update parameter: {e}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Update the dynamic string in SSM Parameter Store")
    parser.add_argument("value", help="New value for the dynamic string")
    parser.add_argument("--param-name", dest="param_name", help="SSM parameter name. If omitted, reads from terraform output")
    args = parser.parse_args()

    param_name = args.param_name or get_param_name_from_terraform()
    if not param_name:
        print("Could not determine SSM parameter name. Pass --param-name or run in Terraform directory where outputs are available.")
        sys.exit(2)

    update_parameter(param_name, args.value)


if __name__ == "__main__":
    main()
