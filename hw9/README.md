# HW9 (GKE Containerized Web Server)

This homework ports the HW4 web server into a container image and runs it on GKE Autopilot. The forbidden-country subscriber still runs on a Compute Engine VM.

## Files

- `service1_server.py`: containerized web server for GKE
- `service2_subscriber.py`: Pub/Sub subscriber for banned-country requests
- `Dockerfile`: builds the web server container image
- `k8s/hw9-web.yaml`: Kubernetes ServiceAccount, Deployment, and LoadBalancer Service template
- `setup.sh`: provisions Artifact Registry, GKE, IAM, Pub/Sub, bucket test files, forbidden VM, and client VM
- `cleanup.sh`: deletes resources created by setup when they were newly created
- `startup_forbidden.sh`: VM startup script for the subscriber app

## Defaults

- Project: active `gcloud` project
- Region: `us-central1`
- Zone: `us-central1-a`
- GKE cluster: `hw9-gke`
- Artifact Registry repo: `hw9-repo`
- Bucket: `cs528-hw2-chunyu`
- Topic: `hw3-forbidden-topic`
- Subscription: `hw3-sub`
- Forbidden VM: `hw9-forbidden-vm`
- Client VM: `hw9-client-vm`

## Setup

Run from the repository root:

```bash
bash hw9/setup.sh
```

The script prints the external IP and validation commands. You can also load the generated state:

```bash
source hw9/.hw9_state.env
```

## Kubernetes Checks

```bash
kubectl get deployments,pods,svc
kubectl rollout status deployment/hw9-web
kubectl describe service hw9-web
kubectl logs deployment/hw9-web --tail=50
```

Screenshot for report:
- GKE Workloads page showing `hw9-web`
- GKE Services page showing `hw9-web` with external endpoint
- Terminal output from `kubectl get deployments,pods,svc`

## Curl Checks

```bash
curl -i "http://${EXTERNAL_IP}/?file=index.html"
curl -i "http://${EXTERNAL_IP}/?file=does_not_exist.html"
curl -i -X POST "http://${EXTERNAL_IP}/?file=index.html"
curl -i -X PUT "http://${EXTERNAL_IP}/?file=index.html"
curl -i -X DELETE "http://${EXTERNAL_IP}/?file=index.html"
curl -i -X OPTIONS "http://${EXTERNAL_IP}/?file=index.html"
```

Expected:
- existing file returns `200`
- missing file returns `404`
- non-GET methods return `501`

Screenshot for report:
- terminal showing the `404` curl command and response
- terminal showing at least one `501` curl command and response

## Browser Checks

Open these URLs:

```text
http://<EXTERNAL_IP>/?file=index.html
http://<EXTERNAL_IP>/?file=does_not_exist.html
```

For method and header cases, open DevTools Console while you are on `http://<EXTERNAL_IP>/?file=index.html`, then run:

```javascript
fetch("/?file=index.html", { method: "POST" }).then(r => [r.status, r.statusText])
fetch("/?file=index.html", { headers: { "X-Country": "Iran" } }).then(r => [r.status, r.statusText])
```

Screenshot for report:
- browser address bar showing a successful file request
- browser address bar showing the missing-file `404`
- DevTools Console showing `501`
- DevTools Console showing forbidden-country `400`

## Forbidden Country Check

Trigger a banned-country request:

```bash
curl -i -H "X-Country: Iran" "http://${EXTERNAL_IP}/?file=index.html"
```

Check the VM subscriber output:

```bash
gcloud compute ssh "${FORBIDDEN_VM}" --zone "${ZONE}" --command 'sudo journalctl -u hw9-forbidden -n 80 --no-pager'
```

Screenshot for report:
- curl response showing `400 Permission denied`
- forbidden VM journal showing `FORBIDDEN request: country=Iran file=index.html`

## Cloud Logging Check

In Logs Explorer, use one of these filters:

```text
resource.type="k8s_container"
resource.labels.container_name="hw9-web"
jsonPayload.status=404
```

```text
resource.type="k8s_container"
resource.labels.container_name="hw9-web"
jsonPayload.status=501
```

Screenshot for report:
- one log entry for missing file `404`
- one log entry for method not implemented `501`

## Client VM Check

Upload the provided http client to the client VM:

```bash
gcloud compute scp ./http-client "${CLIENT_VM}:~/http-client" --zone "${ZONE}"
```

SSH to the VM and run the client against the GKE external IP. Use the exact flags required by the provided client. A typical pattern is:

```bash
gcloud compute ssh "${CLIENT_VM}" --zone "${ZONE}"
chmod +x ~/http-client
~/http-client -d "${EXTERNAL_IP}" -b "none" -w "" -n 300 -i 1 -s -v
```

If your provided client expects a path-style workload name, use `/?file=` style URLs if supported, or set the workload/path argument to request files such as `0.html`.

Screenshot for report:
- VM terminal showing the http client command
- output showing a few hundred successful file requests

## Cleanup

```bash
bash hw9/cleanup.sh
```

Cleanup only deletes shared resources such as the bucket/topic/subscription if this setup run created them.

## Report Checklist

- setup command and successful completion
- `kubectl get deployments,pods,svc`
- GKE console Workloads view for `hw9-web`
- GKE console Services view with external IP
- curl `404` screenshot
- curl `501` screenshot
- browser `200` and `404` screenshots
- Cloud Logging entries for `404` and `501`
- forbidden request curl `400`
- forbidden VM journal showing `FORBIDDEN request`
- client VM running the provided http client for a few hundred requests
- GitHub link to `hw9/service1_server.py` and `hw9/service2_subscriber.py`
