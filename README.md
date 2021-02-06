# sim09

モンスターハンターワールド:アイスボーン用の、
線形計画法を用いたスキルシミュレータ。
別リポジトリ (lp-doc) にある、線形計画法の説明にもとづく参照実装です。

## ファイルの説明
- **sim09.html**
シミュレータのページのhtmlファイル。後述のsim09.rbで生成されたもの。

- **sim09.css**
シミュレータのページのスタイルシート

- **sim09.js**
主にシミュレータのページで発生したイベントを処理するスクリプト

- **sim09query.js**
検索を実行するスクリプト

- **sim09worker.js**
検索を非同期に行うワーカー

- **sim09glpk.js**
シミュレータのページのGLPKタブでのイベントを処理するスクリプト

- **sim09data.js**
各種変数の定義。後述のsim09.rbで生成されたもの。

- **sim09.rb**
sim09.htmlとsim09data.jsを生成するrubyスクリプト。
生成するためだけに必要なので、ウェブサイトに設置する必要はない。

- **glpk-all.js**
線形計画法のjavascriptライブラリ
glpk.js - v4.49.0 (https://github.com/hgourvest/glpk.js)
を変更し、最良のものに限らず検索過程で発見した解も返すようにしたもの。

## サイトへのファイル設置方法
上記ファイルのうち、sim09.rb以外を同一ディレクトリに設置します。
エントリポイントはsim09.htmlです。

## sim09.rbによるファイル生成方法
1. 5chのスキルシミュレータスレッド有志の方々による、武器や防具のデータが、
google driveにあります。
google driveのurlは最新のスレッドのテンプレートを参照して下さい。
2021年2月6日現在は、モンスターハンターライズ用に見えますが、
ライズ発売前でもあり、
中身はワールド:アイスボーンのデータがコピーされているだけです。

csvでダウンロードし、以下のようにファイル名を修正しておきます。

- MHR_CHARM.csv
- MHR_DECO.csv
- MHR_EQUIP_ARM.csv
- MHR_EQUIP_BODY.csv
- MHR_EQUIP_HEAD.csv
- MHR_EQUIP_LEG.csv
- MHR_EQUIP_WST.csv
- MHR_SKILL.csv

2. これらのファイルを適当な場所に置いて、
sim09.rb内の変数「CSVFILES」にその位置を記述します。

3. 次の2命令でファイルが生成されます。
```
$ ruby sim09.rb -h > sim09.html
$ ruby sim09.rb -d > sim09data.js
```
