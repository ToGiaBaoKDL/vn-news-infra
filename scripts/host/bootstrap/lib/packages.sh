#!/usr/bin/env bash
# shellcheck disable=SC1091

install_base_packages() {
  log "Installing base packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    ca-certificates \
    curl \
    git \
    gnupg \
    lsb-release \
    openssh-server \
    python3 \
    python3-venv \
    ufw \
    util-linux \
    xfsprogs
}

install_oci_cli() {
  local version="${VN_NEWS_OCI_CLI_VERSION:-3.85.0}"

  if command -v oci >/dev/null 2>&1 && [[ "$(oci --version 2>&1)" == "$version" ]]; then
    log "OCI CLI already installed"
    return
  fi

  log "Installing OCI CLI ${version}"
  rm -rf /opt/oci-cli
  python3 -m venv /opt/oci-cli
  /opt/oci-cli/bin/python -m pip install --upgrade pip
  /opt/oci-cli/bin/python -m pip install "oci-cli==${version}"
  ln -sf /opt/oci-cli/bin/oci /usr/local/bin/oci
}

install_uv() {
  local version="${VN_NEWS_UV_VERSION:-0.11.17}"

  if command -v uv >/dev/null 2>&1 && [[ "$(uv --version)" == "uv $version" ]]; then
    log "uv already installed"
    return
  fi

  log "Installing uv ${version}"
  rm -rf /opt/uv
  python3 -m venv /opt/uv
  /opt/uv/bin/python -m pip install --upgrade pip
  /opt/uv/bin/python -m pip install "uv==${version}"
  ln -sf /opt/uv/bin/uv /usr/local/bin/uv
}

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker already installed"
    return
  fi

  log "Installing Docker Engine"
  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "Unsupported OS for this bootstrap script: ${ID:-unknown}" >&2
    exit 1
  fi

  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable
EOF

  apt-get update
  apt-get install -y \
    containerd.io \
    docker-buildx-plugin \
    docker-ce \
    docker-ce-cli \
    docker-compose-plugin

  install -d -m 0755 /etc/docker
  cat >/etc/docker/daemon.json <<'EOF'
{
  "log-driver": "local"
}
EOF

  systemctl enable docker
  systemctl restart docker
}
