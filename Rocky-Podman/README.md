# Rocky-Podman — Rocky Linux 10 + Podman rootless + docker-compose

Rocky Linux 10（aarch64）の VM に、rootless Podman と docker-compose を初期構築（provision）まで込みで立ち上げるテンプレート。コンテナ開発の土台を「業務でよくある RHEL 系＋Podman」の形でコード化してある。前提・Lima の導入・共通の使い方（start／shell／stop／delete の型）は[ルートの README](../README.md) にまとめてある。

## テンプレートの中身

| ファイル | 役割 |
|---|---|
| [`rocky-podman.yaml`](rocky-podman.yaml) | VM 定義の本体。器（CPU／メモリ／ディスク）・イメージ（Rocky 10 aarch64・digest 固定）・ポート転送・provision を 1 枚に宣言する。provision は中身をインラインで持つ**自己完結版**なので、この 1 枚（の URL）だけで VM が完成する。 |
| [`bootstrap.sh`](bootstrap.sh) | VM の中を整えるスクリプト（システム更新・Podman・rootless・docker-compose〔aarch64〕）。VM 内の構築はハイパーバイザに依存しないので、Lima 以外（UTM 等）で用意した VM にも SSH して同じ 1 枚を流用できる。 |

## 使い方①：URL から VM を立ち上げる

raw URL を `limactl start` に渡す。

```bash
limactl start --name=rocky-podman https://raw.githubusercontent.com/KBi-K3i/lima_template/main/Rocky-Podman/rocky-podman.yaml
```

clone 済みならローカルのファイルを渡してもよい。

```bash
limactl start --name=rocky-podman ./rocky-podman.yaml
```

VM の中へ入る。

```bash
limactl shell rocky-podman
```

構築が通ったかを確認する（新しいシェルで `DOCKER_HOST` が効く）。

```bash
limactl shell rocky-podman -- bash -lc 'podman --version && docker-compose version'
```

## 使い方②：既存の VM に bootstrap.sh を流す

VM の中でやる構築（更新・Podman・rootless・docker-compose）は仮想化の道具に依存しない。すでに UTM などで VM がある場合は、その VM に SSH して一般ユーザー（sudo 可）で次を実行すれば、`rocky-podman.yaml` の provision と同じ状態になる。

```bash
curl -fsSL https://raw.githubusercontent.com/KBi-K3i/lima_template/main/Rocky-Podman/bootstrap.sh | bash
```

## 設定の要点

### vz と QEMU の選び分け（本テンプレートは vz を既定）

Lima の `vmType` は `vz`（Apple Virtualization）と `qemu` の両方を取れる。どちらでも同じ YAML でコード化でき、切り替えは `vmType` の 1 行を書き換えるだけで、ほか（images・provision・portForwards）はそのまま使える。本テンプレートが vz を既定にする決め手は下表のとおりで、とくに**入れ子仮想化（VM 内で KVM）が vz 経由でのみ使える**こと。スナップショット（`limactl snapshot`）が要るときだけ QEMU に替える。

| 観点 | `vmType: vz`（既定） | `vmType: qemu` |
|---|---|---|
| 実体 | Apple Virtualization（Apple ネイティブ） | QEMU（arm64 一致なら HVF で加速） |
| x86 コンテナ | **Rosetta で高速**（`rosetta` 有効時） | Rosetta 不可（`qemu-user` の binfmt 等で代替・遅い） |
| 入れ子仮想化（VM 内で KVM） | **可（M3 以降＋macOS 15 以降）** | 不可（VM 内は QEMU エミュのみ） |
| スナップショット | 対応は限定的 | `limactl snapshot` で取れる |
| 起動の軽さ | 軽い・速い | vz よりやや重い |
| host→VM SSH | 通る（`localhost` 転送） | 通る（`localhost` 転送） |

vz でも host→VM が通るのは、Lima が VM を物理 LAN に晒さず、`localhost` へのポート転送と SSH で host↔VM を取り持つため。入れ子仮想化は M3 以降＋macOS 15 以降が条件で、M1/M2 では VM 内が QEMU エミュレーションになる。

### イメージのバージョン固定（digest）と更新運用

`images.location` は**バージョン固定の URL**（`-10.2-20260525.0-`）にし、`digest` に公式配布元の `CHECKSUM` と照合した SHA256 を書いている（2026-11-16 照合）。これで「いつ・誰が起動しても同じ土台」になる。`...Base.latest.aarch64.qcow2` は中身が差し替わるので、配布テンプレートには使わない。新しいポイントリリースへ上げるときは、[配布ディレクトリ](https://dl.rockylinux.org/pub/rocky/10/images/aarch64/)の `CHECKSUM` で新しい版の SHA256 を確認し、`location` と `digest` の 2 行を更新してコミットする。

### 器・マウント・ポート転送（好みに合わせて書き換える所）

CPU（`cpus: 4`）・メモリ（`memory: "8GiB"`）・ディスク（`disk: "128GiB"`）は環境固有の値なので、手元の Mac に合わせて書き換えてよい。ホームディレクトリはひとまず読み取り専用でマウントしてあり（`writable: false`）、VM から Mac のファイルを壊さない安全側に倒している。書き込みたい作業フォルダがあれば `writable: true` の別マウントを足す。`portForwards` は VM の 8080/8443 を Mac の `localhost` へ転送する設定で、リバースプロキシ等の動作確認を `https://localhost:8443` のように Mac のブラウザから行える。

## 公式リファレンス

- Lima の設定項目（`vmType`・`rosetta`・`images`・`provision`・`portForwards`）：[lima-vm.io ドキュメント](https://lima-vm.io/docs/)／[templates/default.yaml（lima-vm/lima）](https://github.com/lima-vm/lima/blob/master/templates/default.yaml)
- Rocky Linux のクラウドイメージ（GenericCloud・アーキ別配布・CHECKSUM）：[Rocky Linux ISOs and Images](https://docs.rockylinux.org/10/teams/rel_eng/image/)／[dl.rockylinux.org /pub/rocky/10/images/aarch64/](https://dl.rockylinux.org/pub/rocky/10/images/aarch64/)
- rootless Podman（linger・subuid/subgid・Docker 互換ソケット）：[podman-system-service(1)](https://docs.podman.io/en/latest/markdown/podman-system-service.1.html)
