# Lima Templates — VM をコード化して配るテンプレート集

macOS（Apple Silicon）の上に Linux の開発 VM を、**YAML 1枚から誰でも同じ形で立ち上げる**ための Lima テンプレート集。GUI で VM を作る方式（UTM など）は、再現が人の手に委ねられ、構成がアプリ固有のバイナリに閉じるため、差分レビューも配布もしにくい。対して Lima は、CPU・メモリ・ディスク・ネットワーク・初期構築（provision）までを**テキストの YAML に宣言**する。リポジトリに置けばマージリクエストでレビューでき、raw URL を渡せば `limactl start <URL>` だけで同じ VM が再現できる——いわば「VM の Dockerfile」。

## 利用可能なテンプレート

| フォルダ | 内容 |
|---|---|
| [`Rocky-Podman/`](Rocky-Podman/) | Rocky Linux 10（aarch64）＋ rootless Podman ＋ docker-compose。`vmType: vz` 既定・Rosetta 有効・イメージは digest 固定。 |

（将来、別ディストリ・別用途のテンプレートを横に追加予定。各フォルダが、VM 定義の YAML と構築スクリプトを持つ自己完結したテンプレート。）

## 前提と Lima の導入

- Apple Silicon の Mac（macOS 13 以降）。各テンプレート既定の `vmType: vz`（Apple Virtualization）が使える条件で、Rosetta による x86_64 コンテナ実行もこの組み合わせが前提。
- Homebrew。

Lima を導入する。

```bash
brew install lima
```

導入できたか確認する。

```bash
limactl --version
```

## 共通の使い方

各テンプレートのフォルダにある VM 定義（YAML）の raw URL を `limactl start` に渡すだけで、イメージの取得から provision（VM 内の初期構築）まで自動で進む。具体的なコマンドは各テンプレートの README にあるが、形はどれも同じ。

```bash
limactl start --name=<名前> https://raw.githubusercontent.com/KBi-K3i/lima_template/main/<テンプレート>/<定義>.yaml
```

VM の中へ入る。

```bash
limactl shell <名前>
```

止める・作り直す。Lima は YAML から**何度でも同じ VM を再生成できる**のが強みで、壊したら delete して start し直せばよい（この「コードから再生成」が、スナップショットに頼る運用の代わりになる）。

```bash
limactl stop <名前>
```

```bash
limactl delete <名前>
```

## ネットワークが変わっても同じに使える（オフィス／在宅）

Lima の host↔VM アクセスは、物理 LAN に VM を晒す方式ではなく、Mac の `localhost` に向けたポート転送と SSH で取り持たれる。だからホストのネットワークがオフィスの有線 LAN でも自宅の WiFi でも、立ち上げ方・入り方・叩き方は同一で済む。VM は Mac の経路を通って外へ出る（NAT）ので、社内資源へ届かせたいときは Mac が VPN に乗っているかが効く。vmnet を直接使う方式（UTM の Shared/Bridged）には企業 VPN クライアントとの干渉報告があるが、Lima のユーザーモード寄りの経路は Mac の通常のネットワークスタックを通るため、この干渉を受けにくい。

## 社内 GitLab で配る場合

チーム配布では、テンプレートのフォルダごと職場の GitLab にコミットし、raw URL（例：`https://<GitLab>/<group>/<proj>/-/raw/main/Rocky-Podman/rocky-podman.yaml`）を共有して、各メンバーが `limactl start <raw URL>` を実行する形になる。非公開リポジトリ・スニペットの raw を取りに行くには認証が要るが、URL にトークンを素で埋めたりログに残したりしない。使うなら一時的に環境変数へ読み、`curl --header "PRIVATE-TOKEN: $TOKEN" ...` の形で渡す。**公開してよい土台（YAML／スクリプト）と、秘匿すべき値（トークン・社内ホスト名）を分ける**のが安全。

## 公式リファレンス

- Lima の設定項目（`vmType`・`rosetta`・`images`・`provision`・`portForwards`）：[lima-vm.io ドキュメント](https://lima-vm.io/docs/)／全項目に注釈のある既定テンプレート [templates/default.yaml（lima-vm/lima）](https://github.com/lima-vm/lima/blob/master/templates/default.yaml)
