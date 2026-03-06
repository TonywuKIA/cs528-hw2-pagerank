# HW4 (VM-based)

This directory satisfies the required grading workflow:

```bash
HW=4
git clone --recursive <repo> repo/
pushd repo/hw${HW}/
bash setup.sh
# tests...
bash cleanup.sh
popd
```

## Files
- `setup.sh`: provisions required HW4 infrastructure
- `cleanup.sh`: tears down resources created by `setup.sh`
- `startup.sh`: server VM bootstrap (service1)
- `startup_forbidden.sh`: forbidden VM bootstrap (service2)
- `service1_server.py`: source for VM web server logic
- `service2_subscriber.py`: source for VM subscriber logic

## Defaults
- Region: `us-central1`
- Zone: `us-central1-a`
- Bucket: `cs528-hw2-chunyu`
- Topic: `hw3-forbidden-topic`
- Subscription: `hw3-sub`

You can override with environment variables, e.g.:

```bash
export REGION=us-central1
export ZONE=us-central1-a
export BUCKET_NAME=cs528-hw2-chunyu
bash setup.sh
```

## Notes
- VM internal setup is done strictly with startup scripts passed using `--metadata-from-file startup-script=...`.
- No `gcloud compute ssh --command` is required for VM provisioning.
- Startup scripts include run-once lock files:
  - `/var/log/startup_already_done_hw4_server`
  - `/var/log/startup_already_done_hw4_forbidden`
