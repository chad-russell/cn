# OpenClaw - Personal AI Assistant

OpenClaw is a personal AI assistant that runs in a hybrid deployment:
- **Gateway**: K8s cluster (24/7 availability)
- **Node**: Desktop machine (bee) for local command execution

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   K8s Cluster                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  openclaw-gateway (Deployment)                     │   │
│  │  - WebChat UI (port 18789)                        │   │
│  │  - Discord bot integration                         │   │
│  │  - K8s API access (RBAC)                         │   │
│  │  - Persistent storage (Longhorn PVC)               │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  Ephemeral Workloads (openclaw-workloads namespace)           │
└─────────────────────────────────────────────────────────────┘
                      │
                      │ WebSocket
                      │
┌─────────────────────────────────────────────────────────────┐
│  bee (Desktop Machine - Fedora Bluefin)                    │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  openclaw-node (Podman systemd service)            │   │
│  │  - Filesystem access (/var/home/crussell/Code)      │   │
│  │  - Execute commands (opencode, git, etc.)           │   │
│  │  - Local development tools                          │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Components

### K8s Gateway (openclaw namespace)
- **01-namespace.yaml**: OpenClaw and workloads namespaces
- **02-serviceaccount.yaml**: ServiceAccount for gateway
- **03-rbac.yaml**: RBAC for managing ephemeral pods
- **04-configmap.yaml**: Base OpenClaw configuration
- **05-secret.yaml**: API keys (Anthropic, OpenAI, Discord)
- **06-pvc.yaml**: Persistent volume claim (50Gi)
- **07-deployment.yaml**: Gateway container deployment
- **08-service.yaml**: NodePort service (port 30086)
- **09-workloads-ns.yaml**: Namespace for ephemeral workloads

### bee Node
Located in `bee/openclaw-node/`:
- `openclaw-node.service`: Podman systemd service
- `setup.sh`: Installation script for bee machine
- `README.md`: Setup instructions

## Deployment

### Step 1: Update API Keys
Edit `05-secret.yaml` and replace placeholder values:
- `anthropic-api-key`: Your Anthropic API key
- `openai-api-key`: Your OpenAI API key (optional)
- `discord-bot-token`: Discord bot token (optional)

### Step 2: Apply K8s Manifests
```bash
kubectl apply -f k8s/openclaw/
```

### Step 3: Reload Caddy
```bash
# On the machine running Caddy
systemctl reload caddy
```

### Step 4: Set Up Node on bee
Copy `bee/openclaw-node/` to bee machine and run:
```bash
cd /var/home/crussell/Code/cn/bee/openclaw-node
./setup.sh
```

## Access

- **WebChat**: https://claw.internal.crussell.io
- **Gateway logs**: `kubectl logs -n openclaw deployment/openclaw-gateway -f`
- **Node logs** (on bee): `journalctl --user -u openclaw-node -f`

## Usage

### From Phone/Tablet
1. Open https://claw.internal.crussell.io
2. Start chatting with your AI assistant
3. Commands that need local execution will be routed to bee node

### From Desktop
Same WebChat interface, or integrate with Discord/other channels

### Ephemeral Workloads
The gateway can spawn temporary pods in the `openclaw-workloads` namespace for:
- Isolated environments per task
- Testing code changes
- Running specialized tools

## Security

- Gateway runs with namespace-scoped RBAC permissions
- Only can manage pods in `openclaw-workloads` namespace
- API keys stored in Kubernetes Secrets
- Sandbox mode enabled for non-main sessions
- Node mode only allowslisted commands

## Troubleshooting

### Gateway Not Starting
```bash
kubectl get pods -n openclaw
kubectl logs -n openclaw deployment/openclaw-gateway
```

### Node Not Connecting
```bash
# On bee machine
systemctl --user status openclaw-node
journalctl --user -u openclaw-node -n 100
```

### Can't Access WebChat
- Check Caddy is running: `systemctl status caddy`
- Check DNS resolution: `nslookup claw.internal.crussell.io`
- Check gateway pod is ready: `kubectl get pods -n openclaw`

## Post-Installation Setup

After deploying, you may want to:
1. Configure Linear integration (skills)
2. Set up Discord bot for secondary channel
3. Add iOS/Android nodes for voice/camera access
4. Create custom skills for your workflows

## References

- OpenClaw docs: https://docs.openclaw.ai
- GitHub: https://github.com/openclaw/openclaw
