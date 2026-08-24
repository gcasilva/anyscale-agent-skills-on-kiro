# Using Anyscale Agent Skills in Kiro

**[Anyscale agent skills](https://docs.anyscale.com/agent-skills/install)** are agent instructions that guide AI coding assistants through requirements gathering, code generation from validated templates, and deployment through the Anyscale CLI. 

[Kiro](https://kiro.dev/) is an AI-powered IDE built by AWS that uses spec-driven workflow, steering, and hooks to guide development from idea to implementation. It supports agent skills through its `~/.kiro/skills/` directory and provides a hooks system (`~/.kiro/hooks/`) for pre- and post-tool-use safety checks — making it a natural fit for Anyscale's skill-based workflows.

---

## Prerequisites

1. **[Kiro](https://kiro.dev/)**  installed and configured (`~/.kiro/` directory exists)
2. **Anyscale CLI** installed and authenticated:```bash pip install -U anyscale anyscale login
3. **jq** or **python3** available on your PATH (required by the safety hook)

---

## Installation

### Option A: Install via Anyscale CLI + Copy to Kiro

This approach installs the skills using the official CLI (targeting `claude-code` format, which is compatible), then copies the files to Kiro's directory structure.

Step 1: Install skills via CLI

```bash
anyscale skills install --platform claude-code

```

This writes skill files to `~/.claude/skills/` and hooks to `~/.claude/settings.json`.

Step 2: Copy skills to Kiro

```bash
# Create Kiro skills directory if it doesn't exist
mkdir -p ~/.kiro/skills/

# Copy all Anyscale skill folders to Kiro
cp -r ~/.claude/skills/anyscale-* ~/.kiro/skills/

```

Step 3: Copy hooks to Kiro

```bash
# Create Kiro hooks directory if it doesn't exist
mkdir -p ~/.kiro/hooks/

# Copy the Anyscale command-safety hook script
cp ~/.claude/hooks/main.sh ~/.kiro/hooks/main.sh
chmod +x ~/.kiro/hooks/main.sh

```

Step 4: Install the Kiro hook adapter files

Copy the two adapter files (`anyscale-command-safety.json` and `anyscale-command-safety.sh`) into Kiro's hooks folder:

```bash
# Copy the Kiro-specific hook registration and adapter script
cp anyscale-command-safety.json ~/.kiro/hooks/anyscale-command-safety.json
cp anyscale-command-safety.sh ~/.kiro/hooks/anyscale-command-safety.sh
chmod +x ~/.kiro/hooks/anyscale-command-safety.sh

```

---

### Option B: Manual Setup (Without CLI)

If you already have the skills installed for another platform (Codex, Cursor, Copilot) or have the skill files from a teammate, copy them directly.

Step 1: Copy skills folder

```bash
# From Claude Code installation:
cp -r ~/.claude/skills/anyscale-* ~/.kiro/skills/

# OR from Codex/Copilot shared location:
cp -r ~/.agents/skills/anyscale-* ~/.kiro/skills/

```

Step 2: Copy the upstream safety hook

```bash
mkdir -p ~/.kiro/hooks/

# From Claude Code:
cp ~/.claude/hooks/main.sh ~/.kiro/hooks/main.sh

# OR from Codex:
cp ~/.codex/hooks/main.sh ~/.kiro/hooks/main.sh

chmod +x ~/.kiro/hooks/main.sh

```

Step 3: Install the Kiro adapter files

```bash
cp anyscale-command-safety.json ~/.kiro/hooks/anyscale-command-safety.json
cp anyscale-command-safety.sh ~/.kiro/hooks/anyscale-command-safety.sh
chmod +x ~/.kiro/hooks/anyscale-command-safety.sh

```

---

## Hook Files Explained

### `anyscale-command-safety.json`

This is the Kiro hook registration file. It tells Kiro to run the safety script before any shell/bash tool execution:

```json
{
  "version": "v1",
  "hooks": [
    {
      "name": "Anyscale command safety",
      "description": "Replicates the Anyscale agent-skills PreToolUse screen for Kiro...",
      "trigger": "PreToolUse",
      "matcher": "execute_bash|execute_cmd|shell",
      "timeout": 10,
      "action": {
        "type": "command",
        "command": "bash \"${KIRO_HOME:-$HOME/.kiro}/hooks/anyscale-command-safety.sh\""
      }
    }
  ]
}

```

### `anyscale-command-safety.sh`

This is the adapter script that bridges between Kiro's hook convention and Anyscale's upstream `main.sh` denylist. It:

- Locates the Anyscale-managed `main.sh` screening script (checks `~/.codex/hooks/`, `~/.claude/hooks/`, etc.)
- Normalizes the Kiro event payload into the format upstream expects
- Translates deny decisions into Kiro's blocking convention (`exit 2` + reason on stderr)
- **Fails open** — if the upstream script is missing or crashes, commands are allowed through (safety net, not a brick wall)

**Blocked commands include:** recursive `rm`, `dd`, `mkfs`, `curl|bash` pipes, destructive `aws`/`gcloud`/`az`/`kubectl`/`helm`/`eksctl`/`anyscale` commands, and non-read-only `terraform` operations.

---

## Final Directory Structure

After setup, your Kiro directory should look like this:

```
~/.kiro/
├── hooks/
│   ├── anyscale-command-safety.json    # Hook registration for Kiro
│   ├── anyscale-command-safety.sh      # Kiro ↔ Anyscale adapter script
│   └── main.sh                         # Upstream Anyscale denylist script
└── skills/
    ├── anyscale-infra-aws-vm/
    │   └── SKILL.md
    ├── anyscale-infra-gcp-vm/
    │   └── SKILL.md
    ├── anyscale-infra-kubernetes/
    │   └── SKILL.md
    ├── anyscale-platform-ask/
    │   └── SKILL.md
    ├── anyscale-platform-fix/
    │   └── SKILL.md
    ├── anyscale-platform-inspect/
    │   └── SKILL.md
    ├── anyscale-platform-run/
    │   └── SKILL.md
    ├── anyscale-workload-batch-embedding/
    │   └── SKILL.md
    ├── anyscale-workload-llm-post-training/
    │   └── SKILL.md
    ├── anyscale-workload-llm-serving/
    │   └── SKILL.md
    ├── anyscale-workload-physical-ai/
    │   └── SKILL.md
    ├── anyscale-workload-ray-data/
    │   └── SKILL.md
    ├── anyscale-workload-ray-serve/
    │   └── SKILL.md
    └── anyscale-workload-ray-train/
        └── SKILL.md

```

---

## Updating Skills

When Anyscale releases skill updates, run:

```bash
anyscale skills update

```

Then re-copy the updated files to Kiro:

```bash
cp -r ~/.claude/skills/anyscale-* ~/.kiro/skills/
cp ~/.claude/hooks/main.sh ~/.kiro/hooks/main.sh

```

The `anyscale-command-safety.sh` adapter does **not** need updating — it delegates to the upstream `main.sh` which contains the actual denylist, so updates to blocked commands are picked up automatically.

---

## Available Skills

| Task | Skill Command |
| --- | --- |
| Deploy an LLM as a REST endpoint | `/anyscale-workload-llm-serving` |
| Serve a non-LLM model as a REST endpoint | `/anyscale-workload-ray-serve` |
| Run batch inference on a dataset | `/anyscale-workload-ray-data` |
| Generate embeddings at scale | `/anyscale-workload-batch-embedding` |
| Distributed training / fine-tuning (non-LLM) | `/anyscale-workload-ray-train` |
| LLM post-training (SFT, DPO, GRPO, CPT) | `/anyscale-workload-llm-post-training` |
| VLA / robotics workloads | `/anyscale-workload-physical-ai` |
| Answer questions about Ray or Anyscale | `/anyscale-platform-ask` |
| Launch a workspace, job, or service | `/anyscale-platform-run` |
| Diagnose a failing workload | `/anyscale-platform-inspect` |
| Fix a failing workload end-to-end | `/anyscale-platform-fix` |
| Set up Anyscale on Kubernetes (EKS/GKE/AKS) | `/anyscale-infra-kubernetes` |
| Set up Anyscale on AWS VMs | `/anyscale-infra-aws-vm` |
| Set up Anyscale on Google Cloud VMs | `/anyscale-infra-gcp-vm` |

### Usage Examples

```
/anyscale-workload-llm-serving deploy Qwen2.5-72B-Instruct on H100 GPUs

/anyscale-workload-ray-data run batch inference with Qwen2.5-7B-Instruct on PDF data

/anyscale-platform-ask recommend an architecture for building a RAG pipeline with Ray

/anyscale-platform-inspect debug this issue in the job [job-url]

/anyscale-infra-kubernetes deploy Anyscale on a new EKS cluster with GPU support

```

---

## Troubleshooting

| Issue | Fix |
| --- | --- |
| Hook not triggering | Verify `~/.kiro/hooks/anyscale-command-safety.json` exists and is valid JSON |
| "Permission denied" on hook script | Run `chmod +x ~/.kiro/hooks/anyscale-command-safety.sh ~/.kiro/hooks/main.sh` |
| Hook can't find upstream `main.sh` | Set `ANYSCALE_SAFETY_HOOK` env var to the path of `main.sh` |
| Commands blocked unexpectedly | Check `main.sh` denylist or set `ANYSCALE_SAFETY_HOOK=""` to disable temporarily |
| Skills not recognized by Kiro | Confirm each skill folder has a `SKILL.md` file at `~/.kiro/skills/<name>/SKILL.md` |

---

## Security Notes

- On first use, Anyscale skills surface a security policy and require you to type **"I accept"** before performing actions.
- Skills that call `/anyscale-platform-run` or `/anyscale-platform-fix` **launch real workloads** and incur cloud costs — always review before confirming.
- The command-safety hook blocks destructive shell commands but **fails open** — it won't brick your shell if something goes wrong.
- The hook adapter reuses Anyscale's managed denylist, so it stays current with `anyscale skills update`.

