# Lima Template — Rocky Linux 10 + Podman rootless + docker-compose

macOS（Apple Silicon）の上に、Rocky Linux 10 ＋ rootless Podman ＋ docker-compose の開発 VM を、**YAML 1枚から誰でも同じ形で立ち上げる**ための Lima テンプレート。GUI で VM を作る方式（UTM など）は、再現が人の手に委ねられ、構成がアプリ固有のバイナリに閉じるため、差分レビューも配布もしにくい。対して Lima は、CPU・メモリ・ディスク・ネットワーク・初期構築（provision）までを**テキストの YAML に宣言**する。リポジトリに置けばマージリクエストでレビューでき、raw URL を渡せば `limactl start <URL>` だけで同じ VM が再現できる——いわば「VM の Dockerfile」。

## リポジトリの中身

| ファイル | 役割 |
|---|---|
| [`rocky-podman.yaml`](rocky-podman.yaml) | VM 定義の本体。器（CPU／メモリ／ディスク）・イメージ（Rocky 10 aarch64・digest 固定）・ポート転送・初期構築（provision）を 1 枚に宣言する。provision は中身をインラインで持つ**自己完結版**なので、この 1 枚（の URL）だけで VM が完成する。 |
| [`bootstrap.sh`](bootstrap.sh) | VM の中を整えるスクリプト（システム更新・Podman・rootless・docker-compose〔aarch64〕）。VM 内の構築はハイパーバイザに依存しないので、Lima 以外（UTM 等）で用意した VM にも SSH して同じ 1 枚を流用できる。 |

## 前提

- Apple Silicon の Mac（macOS 13 以降）。テンプレート既定の `vmType: vz`（Apple Virtualization）が使える条件で、Rosetta による x86_64 コンテナ実行もこの組み合わせが前提。
- Homebrew。

Lima を導入する。

```bash
brew install lima
```

導入できたか確認する。

```bash
limactl --version
```

## 使い方①：URL から VM を立ち上げる

このリポジトリの raw URL を `limactl start` に渡すだけで、イメージの取得から provision（Podman・rootless・docker-compose の構築）まで自動で進む。

```bash
limactl start --name=rocky-podman https://raw.githubusercontent.com/KBi-K3i/lima_template/main/rocky-podman.yaml
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

止めるとき。

```bash
limactl stop rocky-podman
```

作り直すとき。Lima は YAML から**何度でも同じ VM を再生成できる**のが強みで、壊したら delete して start し直せばよい（この「コードから再生成」が、スナップショットに頼る運用の代わりになる）。

```bash
limactl delete rocky-podman
```

## 使い方②：既存の VM に bootstrap.sh を流す

VM の中でやる構築（更新・Podman・rootless・docker-compose）は仮想化の道具に依存しない。すでに UTM などで VM がある場合は、その VM に SSH して一般ユーザー（sudo 可）で次を実行すれば、`rocky-podman.yaml` の provision と同じ状態になる。

```bash
curl -fsSL https://raw.githubusercontent.com/KBi-K3i/lima_template/main/bootstrap.sh | bash
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

### ネットワークが変わっても同じに使える（オフィス／在宅）

Lima の host↔VM アクセスは、物理 LAN に VM を晒す方式ではなく、Mac の `localhost` に向けたポート転送と SSH で取り持たれる。だからホストのネットワークがオフィスの有線 LAN でも自宅の WiFi でも、立ち上げ方・入り方・叩き方は同一で済む。VM は Mac の経路を通って外へ出る（NAT）ので、社内資源へ届かせたいときは Mac が VPN に乗っているかが効く。vmnet を直接使う方式（UTM の Shared/Bridged）には企業 VPN クライアントとの干渉報告があるが、Lima のユーザーモード寄りの経路は Mac の通常のネットワークスタックを通るため、この干渉を受けにくい。

## 社内 GitLab で配る場合

チーム配布では、この 2 ファイルを職場の GitLab にコミットし、raw URL（例：`https://<GitLab>/<group>/<proj>/-/raw/main/rocky-podman.yaml`）を共有して、各メンバーが使い方①の `limactl start <raw URL>` を実行する形になる。非公開リポジトリ・スニペットの raw を取りに行くには認証が要るが、URL にトークンを素で埋めたりログに残したりしない。使うなら一時的に環境変数へ読み、`curl --header "PRIVATE-TOKEN: $TOKEN" ...` の形で渡す。**公開してよい土台（この YAML／bootstrap.sh）と、秘匿すべき値（トークン・社内ホスト名）を分ける**のが安全。

## 公式リファレンス

- Lima の設定項目（`vmType`・`rosetta`・`images`・`provision`・`portForwards`）：[lima-vm.io ドキュメント](https://lima-vm.io/docs/)／全項目に注釈のある既定テンプレート [templates/default.yaml（lima-vm/lima）](https://github.com/lima-vm/lima/blob/master/templates/default.yaml)
- Rocky Linux のクラウドイメージ（GenericCloud・アーキ別配布・CHECKSUM）：[Rocky Linux ISOs and Images](https://docs.rockylinux.org/10/teams/rel_eng/image/)／[dl.rockylinux.org /pub/rocky/10/images/aarch64/](https://dl.rockylinux.org/pub/rocky/10/images/aarch64/)
- rootless Podman（linger・subuid/subgid・Docker 互換ソケット）：[podman-system-service(1)](https://docs.podman.io/en/latest/markdown/podman-system-service.1.html)
