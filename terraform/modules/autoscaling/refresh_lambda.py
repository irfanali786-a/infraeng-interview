import os
import logging
import boto3
import botocore.exceptions

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    asg = os.environ.get("ASG_NAME")
    if not asg:
        logger.error("ASG_NAME environment variable is not set")
        return {"status": "error", "message": "ASG_NAME not set"}

    region = os.environ.get("AWS_REGION")  # optional override
    try:
        client_kwargs = {}
        if region:
            client_kwargs["region_name"] = region
        client = boto3.client("autoscaling", **client_kwargs)

        resp = client.start_instance_refresh(
            AutoScalingGroupName=asg,
            Strategy="Rolling",
            Preferences={
                "MinHealthyPercentage": 90,
                "InstanceWarmup": 300
            }
        )

        instance_refresh_id = resp.get("InstanceRefreshId") or resp.get("InstanceRefreshId", "unknown")
        logger.info("Started instance refresh for %s: %s", asg, instance_refresh_id)
        return {"status": "started", "instance_refresh_id": instance_refresh_id, "raw_response": resp}

    except botocore.exceptions.ClientError as e:
        logger.exception("AWS ClientError starting instance refresh for %s", asg)
        return {"status": "error", "message": str(e), "code": e.response.get("Error", {}).get("Code")}
    except Exception as e:
        logger.exception("Unexpected error starting instance refresh for %s", asg)
        return {"status": "error", "message": str(e)}