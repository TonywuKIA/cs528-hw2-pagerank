import os

from googleapiclient.discovery import build


PROJECT_ID = os.environ["PROJECT_ID"]
INSTANCE_NAME = os.environ["INSTANCE_NAME"]
STOP_SQL_ENABLED = os.environ.get("STOP_SQL_ENABLED", "true").lower() == "true"


def stop_sql_if_enabled(request):
    if not STOP_SQL_ENABLED:
        return {"status": "skipped", "reason": "STOP_SQL_ENABLED is false"}, 200

    service = build("sqladmin", "v1beta4", cache_discovery=False)
    instance = service.instances().get(project=PROJECT_ID, instance=INSTANCE_NAME).execute()
    current_policy = instance["settings"].get("activationPolicy", "ALWAYS")
    if current_policy == "NEVER":
        return {"status": "unchanged", "activationPolicy": "NEVER"}, 200

    operation = (
        service.instances()
        .patch(
            project=PROJECT_ID,
            instance=INSTANCE_NAME,
            body={"settings": {"activationPolicy": "NEVER"}},
        )
        .execute()
    )
    return {"status": "patched", "operation": operation.get("name")}, 200
