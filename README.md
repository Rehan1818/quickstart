# Alchemyst AI — DevOps Internship Assignment
**Submitted by: Rehan**

Deploying the distributed inferencing prototype across isolated VMs on GCP,
wiring workers over RPC, and exposing Gemma 3 270M inference as a JSON HTTP API.

---

## Architecture

```
                    ┌──────────────────────────────────────────────────┐
                    │           GCP VPC  (alchemyst-net)               │
                    │           us-east1  |  192.168.1.0/24            │
                    │                                                  │
  User / curl       │  ┌────────────────────────────────┐             │
      │             │  │  rehan-gateway  (public IP)    │             │
      │  :3111      │  │  nginx reverse proxy           │             │
      └────────────►│  │  192.168.1.2                   │             │
                    │  └───────────────┬────────────────┘             │
                    │                  │ proxy_pass :3111             │
                    │                  ▼                              │
                    │  ┌────────────────────────────────┐             │
                    │  │  rehan-engine  (private)       │             │
                    │  │  iii RPC engine                │             │
                    │  │  192.168.1.3                   │             │
                    │  │  ws://192.168.1.3:49134        │             │
                    │  └────────────┬───────────────────┘             │
                    │               │  WebSocket RPC                  │
                    │         ┌─────┴──────┐                          │
                    │         ▼            ▼                          │
                    │  ┌────────────┐  ┌────────────┐                 │
                    │  │rehan-      │  │rehan-      │                 │
                    │  │inference   │  │caller      │                 │
                    │  │Python +    │  │TypeScript  │                 │
                    │  │Gemma model │  │HTTP trigger│                 │
                    │  │192.168.1.4 │  │192.168.1.5 │                 │
                    │  └────────────┘  └────────────┘                 │
                    │                                                  │
                    └──────────────────────────────────────────────────┘
```

### How a request travels

```
POST /v1/chat/completions
  1. rehan-gateway  → nginx receives request, proxies to engine
  2. rehan-engine   → iii routes to caller-worker's HTTP trigger
  3. rehan-caller   → TypeScript calls inference::run_inference via RPC
  4. rehan-engine   → iii routes RPC call to inference-worker
  5. rehan-inference → Python loads prompt into Gemma, generates response
  6. Result bubbles back up through the same chain → JSON response
```

### Network design decisions

- Only `rehan-gateway` has a public IP — all worker VMs are unreachable from the internet
- Workers communicate exclusively over the private subnet (192.168.1.0/24)
- Firewall rule `alchemyst-allow-http` is scoped to the `api-gateway` tag, not all VMs
- Port 49134 (iii WebSocket) is never exposed outside the subnet

---

## API Reference

### Endpoint
```
POST http://<GATEWAY_PUBLIC_IP>:3111/v1/chat/completions
Content-Type: application/json
```

### Request
```json
{
  "messages": [
    { "role": "system", "content": "You are a helpful assistant." },
    { "role": "user",   "content": "What is the capital of France?" }
  ]
}
```

### Response
```json
{
  "result": "The capital of France is Paris.",
  "success": "You've connected two workers and they're interoperating seamlessly..."
}
```

### Example curl
```bash
curl -X POST http://<GATEWAY_PUBLIC_IP>:3111/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [
      {"role": "user", "content": "What is the capital of France?"}
    ]
  }'
```

### Health check
```bash
curl http://<GATEWAY_PUBLIC_IP>:3111/health
# → {"status":"ok"}
```

---

## Redeploy from scratch

### Requirements
- GCP account with billing enabled and `gcloud` CLI authenticated
- This repo cloned locally

### Steps
```bash
# 1. Set your GCP project
export GCP_PROJECT_ID=your-project-id

# 2. Run the infra script — creates VPC, subnet, firewall, 4 VMs
bash infra/setup.sh

# 3. VMs run startup scripts automatically on boot (~5 min to fully start)
#    Monitor startup progress:
gcloud compute instances get-serial-port-output rehan-engine --zone=us-east1-b

# 4. Get gateway public IP
gcloud compute instances describe rehan-gateway \
  --zone=us-east1-b \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)"

# 5. Hit the API
curl -X POST http://<GATEWAY_IP>:3111/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages": [{"role": "user", "content": "Hello!"}]}'
```

### Tear down
```bash
bash infra/teardown.sh
```

### Debugging tips
```bash
# SSH into gateway (only VM with public IP)
gcloud compute ssh rehan-gateway --zone=us-east1-b

# Check service health
sudo systemctl status iii-engine
sudo systemctl status rehan-inference
sudo systemctl status rehan-caller

# Watch live logs
sudo journalctl -u rehan-inference -f   # model loading progress
sudo journalctl -u rehan-caller -f      # HTTP request logs
sudo journalctl -u iii-engine -f        # RPC routing logs
```

---

## Local setup notes

During development I ran the full stack on Google Cloud Shell to verify the
pipeline before writing the deployment scripts. Key things I found:

- The `iii` engine must be started before any workers try to connect
- Workers connect via WebSocket to port 49134 — this must be open between VMs
- The Gemma model (~292MB GGUF) downloads from HuggingFace on first run
- CPU inference is slow (~2-3 min per response) — acceptable for a prototype
- The TypeScript caller-worker logs `inference::get_response called` on every request, confirming the HTTP trigger works

---

## Production hardening

Things I would change before running this in production:

**Network**
- Lock SSH firewall rule to a bastion host IP, not `0.0.0.0/0`
- Add Cloud NAT so private VMs can reach the internet for updates without public IPs
- Enable VPC Flow Logs to monitor inter-VM traffic
- Put the gateway behind GCP Cloud Load Balancing for TLS termination and health checks

**Security**
- Add API key or JWT authentication at the nginx gateway layer
- Move any secrets (HuggingFace tokens, etc.) to GCP Secret Manager
- Run workers as non-root users with minimal filesystem permissions
- Enable OS Login on all VMs instead of SSH key management

**Reliability**
- Use a Managed Instance Group for inference VMs so failed VMs auto-replace
- Add a startup probe — don't route traffic until the Gemma model has fully loaded
- Add Cloud Monitoring uptime checks and alert policies for all 4 services
- Use `RestartSec` with exponential backoff in systemd units

**Performance**
- Cache the Gemma model on a persistent disk shared between inference VMs
  to avoid re-downloading on every VM restart

---

## What changes at 100x model size

If the model were ~27B parameters instead of 270M:

**Hardware**
- Replace `e2-medium` with `n1-standard-8` + NVIDIA T4 GPU
- Use `torch` with CUDA — CPU inference becomes impractical above ~7B params
- T4 GPUs have 16GB VRAM — enough for a 7B model at 8-bit quantization

**Storage**
- A 27B GGUF model at Q8 is ~27GB — too large for the VM boot disk
- Mount a GCP persistent SSD and pre-download the model at infrastructure setup time
- Point `TRANSFORMERS_CACHE` at the persistent disk path

**Serving**
- Replace the direct `model.generate()` call with a proper inference server
  like vLLM or TGI which handle batching, KV-cache, and concurrent requests
- Add a request queue (Cloud Pub/Sub or Redis) between the caller and inference
  workers so requests don't time out during slow generation

**Cost**
- Use Spot VMs for the inference tier — 60-70% cheaper with graceful retry on preemption
- Autoscale inference VMs based on queue depth

---

## Repo structure

```
.
├── README.md
├── infra/
│   ├── setup.sh          ← provisions VPC, subnet, firewall rules, 4 VMs
│   └── teardown.sh       ← deletes all resources
├── deploy/
│   ├── engine-startup.sh     ← iii engine as systemd service
│   ├── inference-startup.sh  ← Python + Gemma worker
│   ├── caller-startup.sh     ← TypeScript HTTP worker
│   └── gateway-startup.sh    ← nginx reverse proxy
└── quickstart/           ← original project (unmodified)
    ├── config.yaml
    └── workers/
        ├── inference-worker/
        └── caller-worker/
```
