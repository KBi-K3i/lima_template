#!/usr/bin/env bash
# bootstrap.sh — Rocky 10 (aarch64) を Podman rootless + docker-compose に整える
# 使い方(手動): VM に SSH 後、一般ユーザー(sudo可)で実行。次の 1 行でも可：
#   curl -fsSL https://raw.githubusercontent.com/KBi-K3i/lima_template/main/bootstrap.sh | bash
# ※ rocky-podman.yaml の provision は同じ内容をインラインで持つ（自己完結）。
#   このファイルは、Lima 以外（UTM 等）で用意した VM に同じ構築を流用するための 1 枚。
set -euo pipefail

# 1) システム更新と基本ツール（root 権限）
sudo dnf -y update
sudo dnf -y install podman git curl tar

# 2) rootless の前提：この user に subuid/subgid を割り当て（クラウドイメージは未設定のことがある）
if ! grep -q "^$(id -un):" /etc/subuid 2>/dev/null; then
  sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$(id -un)"
  podman system migrate || true
fi

# 3) docker-compose（aarch64 版バイナリ）を /usr/local/bin へ
COMPOSE_VER="$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')"
sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-aarch64" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 4) rootless：ログアウト後も動かす(linger)＋Podman の Docker 互換ソケット＋DOCKER_HOST
sudo loginctl enable-linger "$(id -un)"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
systemctl --user enable --now podman.socket
grep -q 'DOCKER_HOST=' ~/.bashrc || echo 'export DOCKER_HOST=unix://${XDG_RUNTIME_DIR}/podman/podman.sock' >> ~/.bashrc

echo "[bootstrap] 完了。新しいシェルを開くか 'source ~/.bashrc' 後に 'docker-compose version' で確認。"
