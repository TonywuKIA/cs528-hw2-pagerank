# HW8 (Multi-Zone Web Tier + Network Load Balancer)

This directory builds on the HW4 web-server design and adds:
- two web-server VMs in different zones
- a regional external network load balancer
- health checks for failover and recovery
- a local client that prints the backend zone returned by the server

The web server preserves the HW4 behavior for file serving and forbidden-country Pub/Sub publishing, and now adds:
- `X-Zone: <zone>`
- `X-Instance-Name: <vm-name>`

## Files
- `setup.sh`: provisions the two web VMs, firewall rules, health check, target pool, reserved IP, and forwarding rule
- `cleanup.sh`: deletes the HW8 resources in dependency-safe order
- `startup_web.sh`: bootstraps each VM and registers the `hw8-server` systemd unit
- `service1_server.py`: source-of-truth server code copied onto each VM at startup
- `client_zone_probe.py`: one-request-per-second observer client with JSONL/CSV logging

## Defaults
- Project ID: active `gcloud` project
- Region: `us-central1`
- Zone A: `us-central1-a`
- Zone B: `us-central1-b`
- Bucket: `cs528-hw2-chunyu`
- Topic: `hw3-forbidden-topic`
- Subscription: `hw3-sub`
- VMs: `hw8-server-a`, `hw8-server-b`
- Load balancer IP resource: `hw8-lb-ip`

## Prerequisites
- Run from Cloud Shell, WSL, or another Linux shell with `bash`, `gcloud`, and `base64 -w`
- The active `gcloud` project is the project you want to use
- HW4 bucket/topic/subscription can be reused; if missing, `setup.sh` creates them
- If you want forbidden-request logging end to end, keep your HW4-style subscriber path available

## Setup
From the repo root:

```bash
bash hw8/setup.sh
```

The script prints the load balancer IP and useful verification commands.

You can override defaults:

```bash
PROJECT_ID="$(gcloud config get-value project)" \
REGION="us-central1" \
ZONE_A="us-central1-a" \
ZONE_B="us-central1-b" \
bash hw8/setup.sh
```

## Validation
After setup:

```bash
source hw8/.hw8_state.env
curl -i "http://${LB_IP}/healthz"
curl -i "http://${LB_IP}/?file=index.html"
curl -i "http://${LB_IP}/?file=does_not_exist.html"
curl -i -X POST "http://${LB_IP}/?file=index.html"
curl -i -H "X-Country: Iran" "http://${LB_IP}/?file=index.html"
gcloud compute target-pools get-health "${TARGET_POOL_NAME}" --region="${REGION}"
```

Expected behavior:
- `/healthz` returns `200`
- `index.html` returns `200`
- nonexistent file returns `404`
- `POST` returns `501`
- forbidden country returns `400`
- all responses include `X-Zone`

## Client Run
From your local machine:

```bash
python hw8/client_zone_probe.py \
  --base-url "http://<LB_IP>" \
  --interval 1 \
  --jsonl-out hw8/probe_logs/run.jsonl \
  --csv-out hw8/probe_logs/run.csv
```

Useful shorter test:

```bash
python hw8/client_zone_probe.py --base-url "http://<LB_IP>" --count 20
```

## Failover Test
Start the client first. Then stop one backend service from Cloud Shell:

```bash
gcloud compute ssh hw8-server-a --zone us-central1-a --command 'date -Is && sudo systemctl stop hw8-server'
```

Watch the client output:
- note any transient network errors
- record when responses become stable from only the surviving zone

Check backend health during the transition:

```bash
gcloud compute target-pools get-health hw8-target-pool --region us-central1
```

## Recovery Test
Restart the stopped backend:

```bash
gcloud compute ssh hw8-server-a --zone us-central1-a --command 'date -Is && sudo systemctl restart hw8-server'
```

Watch for:
- the backend to become healthy again
- `X-Zone` for the restarted zone to reappear in client output

## Screenshot Checklist For Report
- Compute Engine instances page showing both VMs, their zones, and `RUNNING`
- forwarding rule / load balancer view with the external IP
- target pool backend health showing both healthy before failover
- terminal with `curl -i` showing `X-Zone`
- terminal with repeated client output showing both zones before failure
- terminal where the stop command is issued with timestamp visible
- client output during failover showing errors or the zone shift
- backend health view after one backend becomes unhealthy
- terminal where the restart command is issued with timestamp visible
- backend health view after recovery shows both healthy again
- client output showing the recovered zone returning

## Cleanup
When finished:

```bash
bash hw8/cleanup.sh
```

## Notes
- The `hw8-server` systemd service is installed on both VMs.
- Timing measurements should be based on client-visible behavior, which matches the homework requirement.
- The client summary prints the successful-response ratio by zone for the report.
