#!/bin/bash
# Registers this VM as a self-hosted GitHub Actions runner and installs it as a service.
#
# Usage (on the VM, as a sudo-capable user):
#   sudo bash setup-runner.sh <owner/repo> <registration-token> <label> <deploy-dir>
# Example:
#   sudo bash setup-runner.sh hammuneer/dice-devops-finalproject-server AAAA... server-vm /opt/dice-server
#
# Get a registration token with:
#   gh api -X POST repos/<owner/repo>/actions/runners/registration-token -q .token
set -euo pipefail

REPO="$1"
TOKEN="$2"
LABEL="$3"
DEPLOY_DIR="$4"
RUNNER_USER=runner
RUNNER_HOME=/home/$RUNNER_USER/actions-runner

# Dedicated user that may run docker (no password, no sudo).
if ! id "$RUNNER_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$RUNNER_USER"
fi
usermod -aG docker "$RUNNER_USER"

# Directories the pipeline writes to.
mkdir -p "$DEPLOY_DIR" /opt/monitoring
chown -R "$RUNNER_USER:$RUNNER_USER" "$DEPLOY_DIR" /opt/monitoring

if [ -f "$RUNNER_HOME/.runner" ]; then
  echo "Runner already configured in $RUNNER_HOME - nothing to do."
  exit 0
fi

# Download the latest runner release.
VERSION=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/^v//')
mkdir -p "$RUNNER_HOME"
cd "$RUNNER_HOME"
curl -fsSL -o runner.tar.gz \
  "https://github.com/actions/runner/releases/download/v${VERSION}/actions-runner-linux-x64-${VERSION}.tar.gz"
tar xzf runner.tar.gz && rm runner.tar.gz
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME"
./bin/installdependencies.sh >/dev/null

sudo -u "$RUNNER_USER" ./config.sh --unattended \
  --url "https://github.com/$REPO" \
  --token "$TOKEN" \
  --name "$LABEL" \
  --labels "$LABEL" \
  --work _work \
  --replace

./svc.sh install "$RUNNER_USER"
./svc.sh start
./svc.sh status | head -5
