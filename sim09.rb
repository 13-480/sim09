# -*- mode: ruby; mode: outline-minor; coding: utf-8 -*-
# usage:
# $ ruby sim09.rb -h > sim09.html
# $ ruby sim09.rb -d > sim09data.js
# sim09.js, sim09.css, sim09glpk.js, sim09query.js, sim09worker.js は自分で書く
# 他のオプション
# -s 装飾品のソート
# -b デバッグ (番号表示)

# sim09で新規なのは、glpk.js を変更して glpk-all.js にして、
# 最良ではない解も取得するようにしたこと。
# 同時に、検索ボタンに中止も機能させるようにして、単純化

# TODO
# 検索結果の防御力によるソート

CSVFILES = {
  :head => '../5ch/MHR_EQUIP_HEAD.csv',
  :body => '../5ch/MHR_EQUIP_BODY.csv',
  :arm => '../5ch/MHR_EQUIP_ARM.csv',
  :wst => '../5ch/MHR_EQUIP_WST.csv',
  :leg => '../5ch/MHR_EQUIP_LEG.csv',
  :charm => '../5ch/MHR_CHARM.csv',
  :deco => '../5ch/MHR_DECO.csv',
  :skill => '../5ch/MHR_SKILL.csv',
}

# y変数の添字
Yi = {
  '名前'=>0,
  '頭'=>1,       '胴'=>2,       '腕'=>3,       '腰'=>4,       '脚'=>5,
  '男'=>6,       '女'=>7,
  '護石'=>8,
  'スロ1'=>9,    'スロ2'=>10,   'スロ3'=>11,   'スロ4'=>12,
  '防御力'=>13,
  '火耐性'=>14,  '水耐性'=>15,  '雷耐性'=>16,  '氷耐性'=>17,  '龍耐性'=>18,
  'スキル'=>19
}

# スキルの変数の開始番号 (スキル番号は0開始)
SKILL_OFST = Yi['スキル']

# 極意の情報。スキル, 最大Lv, 解放後最大Lv, 極意スキル, 極意必要Lv
GOKUI = [
  ['整備',                  3,  5,  '炎妃龍の真髄',    3],
  ['渾身',                  3,  5,  '斬竜の真髄',      3],
  ['ＫＯ術',                3,  5,  '角竜の覇気',      3],
  ['スリンガー装填数ＵＰ',  3,  5,  '銀火竜の真髄',    2],
  ['スタミナ奪取',          3,  5,  '恐暴竜の真髄',    3],
  ['精霊の加護',            3,  5,  '金火竜の真髄',    2],
  ['力の解放',              5,  7,  '雷狼竜の真髄',    3],
  ['砲術',                  3,  5,  '熔山龍の真髄',    3],
  ['ボマー',                3,  5,  '調査団の錬金術',  3],
  ['満足感',                1,  3,  '轟竜の真髄',      3],
]

# 極意の情報。スキル, 最大Lv, 解放後最大Lv, 極意スキル, 極意必要Lv
# 挑戦者のみ極意が2つあるので別扱い
GOKUI_CHO = [
  ['挑戦者',                5,  7,  '砕竜の真髄',      3],
  ['挑戦者',                5,  7,  'サバイバー',      4],
]

# スキルのファイルを読み、
# スキル系統=>[スキル番号(0開始), Lvの配列, カテゴリ, 発動スキル名の配列]
# のHashを返す。
# シリーズスキルのためにLvは配列にした。0含まず
# スキルのファイルの列番号 (抜粋):
# 0 スキル系統
# 1 発動スキル
# 2 必要ポイント
# 3 カテゴリ (シリーズスキルも)
# シリーズスキルの各発動スキル名も返り値に含める
def read_skills(filename = CSVFILES[:skill])
  res = {}
  open(filename) {|file|
    while line = file.gets
      line = line.strip
      next if line.empty? || line[0] == '#' # 先頭行だけ引用符がある
      cs = line.split(',')
      if ! res.has_key?(cs[0]) then
        num = res.size
        res[cs[0]] = [num, [cs[2].to_i], cs[3], [cs[1]]]
      else
        res[cs[0]][1].push(cs[2].to_i)
        res[cs[0]][3].push(cs[1])
      end
    end
  }
  res
end

# 防具の拡大係数行列の転置を返す。拡大とは名前の追加。各行は、
# 0 名前
# 1-5 頭、胴、腕、腰、脚防具カウンタ
# 6 男カウンタ
# 7 女カウンタ
# 8 護石カウンタ
# 9-12 スロット
# 13 防御力
# 14 火耐性
# 15 水耐性
# 16 雷耐性
# 17 氷耐性
# 18 龍耐性
# 19-(n+18) スキル
# を成分に持つArrayのArrayを返す。
#
# 防具の列番号 (抜粋)
# 0     名前
# 1     "性別(0=両,1=男,2=女)"
# 3-5   スロット1,..,スロット3
# 7     初期防御力
# 9-13  火、水、雷、氷、龍耐性
# 14-23 スキル系統1,スキル値1,..,スキル系統5,スキル値5
# 32    カスタム強化防御力
# 37    ワンセット防具
def read_eqp(skllist)
  res = [] # 拡大係数行列の転置
  [:head, :body, :arm, :wst, :leg].each_with_index {|part, i|
    open(CSVFILES[part]) {|file|
      while line = file.gets
        line = line.strip
        next if line.empty? || line[0] == '#' # 先頭行だけ引用符がある
        cs = line.split(',')
        next if cs.empty? || cs[0].empty? # 名前が空で仮番号のある行がある
        # 名前とカウンタ
        row1 = [cs[0], 0,0,0,0,0, 0,0, 0]
        row1[i+1] = 1 # 部位カウンタ
        row1[6] = 1 if cs[1] == '1' # 男カウンタ
        row1[7] = 1 if cs[1] == '2' # 女カウンタ
        # スロット (エンコーディング注意)
        row2 = [0,0,0,0]
        cs[3..5].each {|lv| lv.to_i.times {|i| row2[i] += 1 }}
        # 防御力
        row3 = [cs[32].to_i]
        row3 = [cs[7].to_i]
        # 耐性
        row4 = cs[9..13].map {|s| s.to_i }
        # スキル
        row5 = [0] * skllist.size
        cs[14..23].each_slice(2) {|s, v|
          next if s.empty?
          if ! skllist.has_key?(s) then
            $stderr.puts '! %s 付属のスキル %s がリストにない' % [cs[0], s]
            next
          end
          row5[skllist[s][0]] += v.to_i
        }
        # 登録
        res.push( row1+row2+row3+row4+row5 )
      end
    }
  }
  res
end

# 護石の拡大係数行列の転置を返す。
# 護石の列番号 (抜粋)
# 0 名前
# 3-6 スキル系統1,スキル値1,スキル系統2,スキル値2
def read_charm(skllist)
  res = []
  open(CSVFILES[:charm]) {|file|
    while line = file.gets
      line = line.strip
      next if line.empty? || line[0] == '#' # 先頭行だけ引用符がある
      cs = line.split(',')
      next if cs[0].empty? # 名前が空で仮番号のある行がある
      # 名前とカウンタ
      row1 = [cs[0], 0,0,0,0,0, 0,0, 1]
      # スロット (エンコーディング注意)
      row2 = [0,0,0,0]
      # 防御力
      row3 = [0]
      # 属性
      row4 = [0,0,0,0,0]
      # スキル
      row5 = [0] * skllist.size
      cs[3..6].each_slice(2) {|s, v|
        row5[skllist[s][0]] += v.to_i if ! s.empty? }
      # 登録
      res.push( row1+row2+row3+row4+row5 )
    end
  }
  res
end

# 珠の拡大係数行列の転置を返す。
# 珠の列番号 (抜粋)
# 0 名前
# 2 スロットサイズ
# 4-7 スキル系統1,スキル値1,スキル系統2,スキル値2
def read_deco(skllist)
  res = []
  open(CSVFILES[:deco]) {|file|
    while line = file.gets
      line = line.strip
      next if line.empty? || line[0] == '#' # 先頭行だけ引用符がある
      cs = line.split(',')
      next if cs[0].empty? # 名前が空で仮番号のある行がある
      # 名前とカウンタ
      row1 = [cs[0], 0,0,0,0,0, 0,0, 0]
      # スロット (エンコーディング注意)
      row2 = [0,0,0,0]
      cs[2].to_i.times {|i| row2[i] = -1 }
      # 防御力
      row3 = [0]
      # 属性
      row4 = [0,0,0,0,0]
      # スキル
      row5 = [0] * skllist.size
      cs[4..7].each_slice(2) {|s, v|
        row5[skllist[s][0]] += v.to_i if ! s.empty? }
      # 登録
      res.push( row1+row2+row3+row4+row5 )
    end
  }
  res
end

#### sim09.html

# ヘッダのhtmlを表示
def print_header_html
puts <<EOS
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>mhw:ibスキルシミュレータlp</title>

<script type="text/javascript" src="./sim09.js"></script>
<script type="text/javascript" src="./sim09query.js"></script>
<script type="text/javascript" src="./sim09data.js"></script>
<script type="text/javascript" src="./sim09glpk.js"></script>
<link rel=stylesheet type="text/css" href="sim09.css">

</head>
<body style="font-family:sans-serif;font-size:small">

<!-- ================ ヘッダ ================ -->
<div id=header>
<div id=tabbar>
<h2>mhw:ibスキルシミュレータlp</h2>
<a show="querytab" class=activebtn>検索</a>
<a show="skilltab">スキル表示一覧</a>
<a show="decotab">装飾品上限</a>
<a show="excludetab">除外装備一覧</a>
<a show="exporttab">エクスポート・インポート</a>
<a show="glpktab">ＧＬＰＫ</a>
</div>
</div>
EOS
end

# 「検索タブ」の前半のhtmlを表示
def print_querytab_header1
puts <<EOS
<!-- ================ 第1タブ: スキルLv指定と検索 ================ -->
<div class="usualtab activetab" id=querytab>

<span class=querytab-heading>武器データ</span>

<!-- 武器倍率 -->
武器種
<select id=weapKind>
<option value=4.8>大剣</option>
<option value=3.3>太刀</option>
<option value=1.4>片手剣</option>
<option value=1.4>双剣</option>
<option value=5.2>ハンマー</option>
<option value=4.2>狩猟笛</option>
<option value=2.3>ランス</option>
<option value=2.3>ガンランス</option>
<option value=3.5>スラッシュアックス</option>
<option value=3.6>チャージアックス</option>
<option value=3.1>操虫棍</option>
<option value=1.3>ライトボウガン</option>
<option value=1.5>ヘビィボウガン</option>
<option value=1.2>弓</option>
</select>

表示攻撃力: <input type=text id=dispAtk value=1000 style="width:40px"></input>

武器会心率 (%): <input type=text id=critical value=0 style="width:20px"></input>

武器スロット:
<select id=weaponslot>
<option>なし</option>
<option>Lv1</option>
<option>Lv1-1</option>
<option>Lv1-1-1</option>
<option>Lv2</option>
<option>Lv2-1</option>
<option>Lv2-1-1</option>
<option>Lv2-2</option>
<option>Lv2-2-1</option>
<option>Lv2-2-2</option>
<option>Lv3</option>
<option>Lv3-1</option>
<option>Lv3-1-1</option>
<option>Lv3-2</option>
<option>Lv3-2-1</option>
<option>Lv3-2-2</option>
<option>Lv3-3</option>
<option>Lv3-3-1</option>
<option>Lv3-3-2</option>
<option>Lv3-3-3</option>
<option>Lv4</option>
<option>Lv4-1</option>
<option>Lv4-1-1</option>
<option>Lv4-2</option>
<option>Lv4-2-1</option>
<option>Lv4-2-2</option>
<option>Lv4-3</option>
<option>Lv4-3-1</option>
<option>Lv4-3-2</option>
<option>Lv4-3-3</option>
<option>Lv4-4</option>
<option>Lv4-4-1</option>
<option>Lv4-4-2</option>
<option>Lv4-4-3</option>
<option>Lv4-4-4</option>
</select>
EOS
end

# 「検索タブ」の武器スキル指定ドロップダウンのhtmlを表示
WEAPONSKILL_OPTION = '<option v=%s>%s</option>'
def print_weaponskill(skllist)
  puts '武器スキル:'
  puts '<select id=weaponskill>'
  ord = %w(クエスト アイテム 戦闘(生存) 特殊攻撃耐性 パラメータ変化
戦闘(属性・異常) 戦闘(攻撃) シリーズスキル)
  puts WEAPONSKILL_OPTION % ['', 'なし']
  skllist.to_a.sort_by {|k,val| [ord.index(val[2]), val[0]] }.
    each {|s, (num, lvs, cat, lvtxt)|
    next if cat != 'シリーズスキル'
    v = 'y' + (num + SKILL_OFST).to_s
    puts WEAPONSKILL_OPTION % [v, skill_str(num, s)]
  }
  puts '</select>'
  puts
end

# 「検索タブ」の中盤のhtmlを表示
def print_querytab_header2
puts <<EOS
<br>
<span class=querytab-heading>耐性最低値指定</span>
火耐性: <input type=text id=hiResist value=-30 style="width:25px"></input>
水耐性: <input type=text id=mizuResist value=-30 style="width:25px"></input>
雷耐性: <input type=text id=kamiResist value=-30 style="width:25px"></input>
氷耐性: <input type=text id=koriResist value=-30 style="width:25px"></input>
龍耐性: <input type=text id=ryuResist value=-30 style="width:25px"></input>

<br>
<span class=querytab-heading>防御力最低値指定</span>
: <input type=text id=minDefence value=0 style="width:25px"></input>


EOS
end

# 「検索タブ」の「スキルLv指定ペイン」のhtmlを表示
SKILL_DROPDOWN = <<EOS
<span><button id=btn%s v=%s>%s</button>
<select id=sel%s v=%s maxlv=%s>%s</select></span>
EOS
SKILL_DROPDOWN_OPTION = '<option value=%s>%s</option>'
SKILL_DROPDOWN_LV = %w(無指定 Lv1 Lv2 Lv3 Lv4 Lv5 Lv6 Lv7)
def print_skillpane(skllist)
  puts '<!-- スキルLv指定ペイン -->'
  puts '<div id=skillpane>'
  puts '<h4 class=querytab-headings>スキルLv指定</h4>'
  ord = %w(クエスト アイテム 戦闘(生存) 特殊攻撃耐性 パラメータ変化
戦闘(属性・異常) 戦闘(攻撃) シリーズスキル)
  skllist.to_a.sort_by {|k,val| [ord.index(val[2]), val[0]] }.
    each {|s, (num, lvs, cat, lvtxt)|
    opts = [0, *lvs.sort].map {|i|
      SKILL_DROPDOWN_OPTION % [i, SKILL_DROPDOWN_LV[i]] }.join
    v = 'y' + (num + SKILL_OFST).to_s
    maxLv = (cat=='シリーズスキル') ? 5 : lvs.max
    puts SKILL_DROPDOWN % [v, v, skill_str(num, s), v, v, maxLv, opts]
  }
  puts '</div> <!-- of skillpane -->'
end

# スキル名の文字列。$debugに応じてスキル番号を入れる
def skill_str(num, name)
  $debug ? [num+SKILL_OFST, name].join : name
end

# 「検索タブ」の検索ボタンと結果ペインのhtmlを表示
def print_querytab_btns_result
puts <<EOS

<hr>

<!-- 防御力最大化検索 -->
<button id=querybtn style="height:30px; width:200px; display:inline-block" onclick='doQuery(null, null, 1)'>検索</button>
<button id=querybtn-add style="height:30px; width:200px; display:none" onclick='doQuery(null, "除外", 1)'>追加検索</button>
<button id=querybtn-stop style="height:30px; width:200px; display:none" onclick='doStop()'>検索中止</button>

<span id=progress style="display:inline-block;width:100px"></span>
<button style="height:30px" onclick='clearResult()'>検索結果の全消去</button>

<hr>

<!-- 検索結果 -->
<div id=resultpane>
</div> <!-- of resultpane -->

EOS
end

# 「検索タブ」の使用方法ペインのhtmlを表示
def print_querytab_instruction
  puts <<EOS
<div id=instructionpane>
<h4>使い方</h4>
<p>
(1) 検索に使いたいスキルを「スキル表示一覧」タブで選び、
「検索」タブに表示させる。
<br>
(2) 「検索」タブで、武器データ、耐性と防御力の最低値、
スキルLvを指定して検索する。
(5)も参照。
<br>
(2a) 「検索」ボタンは、防御力最大のものを検索。
<br>
(2b) 検索結果がリストにある状態だと「追加検索」ボタンになる。
既に検索結果にある防具5部位の組合せは除外して検索。
ただし、検索結果で防具に「なし」が含まれるものは除外しないので、
再度検索される可能性があります。
<br>
(2c) スキル名のボタンを押すとそのスキルを最大化して検索。
<br>
(3) 検索結果の左の数値は、順に防御力、可能な最大の会心率、
簡易的に計算した物理攻撃力。
<br>
(3a) 会心率で考慮するのは、
滑走強化、攻撃、渾身、弱点特効、力の解放、挑戦者、抜刀術【技】、見切り
の各スキル。
<br>
(3b) 攻撃力ＵＰで考慮するのは、加算が攻撃、挑戦者、フルチャージ、
乗算が無属性強化、攻めの守勢、飛燕の各スキル。
<br>
(3c) 攻撃力の期待値を超会心スキルも考慮して計算。
（斬れ味は考慮していません）: <br>
簡易的な攻撃力 = (表示攻撃力 / 武器係数 + 加算補正) x 乗算補正 x
(会心率 x 会心倍率 + (100-会心率)) / 100
<br>
(4) 検索結果中の「追加スキル」のボタンを押すと、
その検索結果の防具5部位を固定したとき、
検索で指定したスキルの条件を満たした上で、
「スキルLv指定」にあるスキルで追加で発動しうるものを検索する。
<br>
(5) このスキルシミュレータは、線形計画法を用いています。
線形計画法は、条件を満たす結果すべてを求めるのではなく、
最良のもの1件を求めます。
つまり、1件しか検索されなくても、
防御力最大のものが見付かったことは保証されます。

ただ、このバージョン (2021年1月16日公開) では、
他のシミュレータの動作に近づけるため、
最良のものを求める過程で発見したそれ以外の結果も表示するようにしています。
それでも、条件を満たす結果すべてを求めるのではないので、
必要に応じて「追加検索」を行い、希望の装備を探索して下さい。
</p>
</div>

EOS
end

# 「検索タブ」の後半のhtmlを表示
def print_querytab_footer
  puts '</div> <!-- of querytab -->'
end

# 「スキル表示一覧」のhtmlを表示
# skllstは、スキル系統=>[スキル番号(0開始), LvのArray, カテゴリ] のHash
SKILL_SHOWWHIDE_CHKBOX =
  '<span><input type=checkbox id=sel%s v=%s>%s</span>'
def print_skilltab(skllist)
  puts '<!-- ================ 第2タブ: スキル表示一覧 ================ -->'
  puts '<div class=usualtab id=skilltab>'
  puts '<h3>スキル表示一覧</h3>'
  ord = %w(クエスト アイテム 戦闘(生存) 特殊攻撃耐性 パラメータ変化
戦闘(属性・異常) 戦闘(攻撃) シリーズスキル)
  cat0 = '-'
  skllist.to_a.sort_by {|k,v| [ord.index(v[2]), v[0]] }.
    each {|s, (num, lvs, cat, lvtxt)|
    if cat != cat0 then
      cat0 = cat
      puts "<h4>#{cat}</h4>"
    end
    v = 'y' + (num + SKILL_OFST).to_s
    puts SKILL_SHOWWHIDE_CHKBOX % [v, v, skill_str(num, s)]
  }
  puts '</div> <!-- of skilltab -->'
  puts
end

# 「装飾品上限」のhtmlを表示。matは拡大係数行列
DECO_DROPDOWN = '<span>%s <select id=sel%s v=%s>%s</select></span>'
DECO_DROPDOWN_OPTION = '<option value=%s>%s</option>'

DECO_CAT3 = %w(クエスト アイテム 戦闘(生存) 特殊攻撃耐性 パラメータ変化
戦闘(属性・異常) 戦闘(攻撃))
DECO_CAT4 = %w(加護 体力 治癒 攻撃 達人 匠 解放 体術 回避 整備)

DECO_ORD3 = %w(奪気 飛燕 防風 耐震 速納 耐衝 抜刀 逆境 滑走 解放 短縮 早気
強走 挑戦 重撃 昂揚 窮地 全開 ＫＯ 跳躍 鉄壁 無傷 守勢 逆上 友愛 早食 渾身
節食 茸好 爆師 投石) # 追加次第更新

DECO_ORD4 = %w(防御 早復 耐火 耐氷 耐雷 耐龍 耐毒 耐麻 耐眠 耐爆 達人
鼓笛 無食 鉄壁 標本 植学 地学 砲手 環境 沼渡 威嚇 潜伏 采配) # 追加次第更新

def print_decotab(mat, skllist)
  puts '<!-- ================ 第3タブ: 装飾品上限 ================ -->'
  puts '<div class=usualtab id=decotab>'
  puts '<h3>装飾品上限</h3>'
  # すべて除外する・しないのボタン
  puts '<button onclick="setAllDeco(1)">すべての装飾品の上限を最大にする</button>'
  puts '<button onclick="setAllDeco(0)">すべての装飾品の上限を0にする</button>'
  # まず、Lv3までの装飾品を、カテゴリごとに。シリーズスキルはないはず
  DECO_CAT3.each {|cat|
    puts "<h4>#{cat}</h4>"
    mat.each_with_index {|row, i|
      next if row[Yi['スロ1']] >= 0 # 装飾品以外
      next if row[Yi['スロ4']] < 0 # Lv4装飾品以外
      j = row[Yi['スキル']..-1].find_index {|x| x > 0 }
      skllist.each {|s, (num, lvs, cat0, lvtxt)|
        next if num != j || cat0 != cat
        opts = (0..lvs.max).map {|k| DECO_DROPDOWN_OPTION % [k,k] }.join
        v = 'x' + i.to_s
        puts DECO_DROPDOWN % [eqp_str(i, row[Yi['名前']]), v, v, opts]
        break
      }
    }
  }
  # Lv4の2スキル珠
  DECO_CAT4.each {|cat|
    name = "・#{cat}珠"
    puts "<h4>＊#{name}</h4>"
    rows = mat.each_with_index.select {|row, i| # Lv4の2スキル珠のみ選択
      next nil if row[Yi['スロ4']] >= 0
      next nil if ! row[Yi['名前']].include?(name)
      [row, i]
    }
    if $decosort then  # ソートする
      rows = rows.sort_by {|row, i|
        s = row[Yi['名前']]
        [DECO_ORD3.index(s[0..1]) || 99999, s] }
    end
    rows.each {|row, i|
      opts = (0..7).map {|k| DECO_DROPDOWN_OPTION % [k,k] }.join
      v = 'x' + i.to_s
      puts DECO_DROPDOWN % [eqp_str(i, row[Yi['名前']]), v, v, opts]
    }
  }
  # Lv4の1スキル珠
  puts "<h4>Lv4単一スキル珠</h4>"
  rows = mat.each_with_index.select {|row, i| # Lv4の1スキル珠のみ選択
    next nil if row[Yi['スロ4']] >= 0
    next nil if row[Yi['名前']].include?('・')
    [row, i]
  }
  if $decosort then  # ソートする
    rows = rows.sort_by {|row, i|
      s = row[Yi['名前']]
      [DECO_ORD4.index(s[0..1]) || 99999, s] }
  end
  rows.each {|row, i|
    opts = (0..7).map {|k| DECO_DROPDOWN_OPTION % [k,k] }.join
    v = 'x' + i.to_s
    puts DECO_DROPDOWN % [eqp_str(i, row[Yi['名前']]), v, v, opts]
  }
  puts '</div> <!-- of decotab -->'
  puts
end

# 防具、護石、装飾品の文字列。$debugに応じて装備番号を入れる
def eqp_str(num, name)
  $debug ? [num, name].join : name
end


# 配列の配列を与えると、カテゴリごとに何番目かが揃うようにnilを挿入
# 例: [[1,1,2,2,3], [1,2,2,3,3]] => [[1,1,2,2,3,nil], [1,nil,2,2,3,3]]
# ブロックを与えると、それでカテゴリに変換する
def align_vbox(xss, &f)
  xss = xss.map {|xs| xs.dup }
  g = f ? (proc {|x| x ? f[x] : x }) : (proc {|x| x} )
  n = xss.size
  yss = n.times.map {[]}
  #
  while xss.any? {|xs| ! xs.empty? }
    ass = n.times.map {|i|
      n.times.map {|j| xss[j].index {|x| g[x] == g[xss[i][0]] }}}
    n.times {|ii|
      if ! ass[ii].empty? && ass[ii].compact.max == 0 then
        n.times {|jj|
          yss[jj].push(ass[ii][jj]==0 ? xss[jj].shift : nil ) }
        break
      end
    }
  end
  yss
end

# 「除外装備一覧」のhtmlを表示。matは拡大係数行列
EXCLUDE_CHKBOX = '<div><input type=checkbox id=chk%s v=%s>%s</div><br>'
def print_excludetab(mat)
  # 装備ごとのリストを作る
  xss = [Yi['頭'], Yi['胴'], Yi['腕'], Yi['腰'], Yi['脚'], Yi['護石']].map {|j|
    xs = []
    mat.each_with_index {|row, i|
      next if row[j] == 0
      v = 'x' + i.to_s
      xs.push(EXCLUDE_CHKBOX % [v, v, eqp_str(i, row[Yi['名前']])])
    }
    xs
  }
  xss[0..4] = align_vbox(xss[0..4]) {|x|
    />[0-9]*((EX)?[^0-9]{3})([^<>]+)<\/div>/ =~ x
    str = $1
    str[0..1] == 'シリ' ? 'シリ' : str # 先頭3文字で判断できない唯一の例外
  }
  # 表示
  puts '<!-- ================ 第4タブ: 除外装備一覧 ================ -->'
  puts '<div class=usualtab id=excludetab>'
  puts '<h3>除外装備一覧</h3>'
  puts '<button onclick="excludeOld(1)">ワールド防具をすべて除外</button>'
  puts '<button onclick="excludeOld(0)">ワールド防具をすべて除外解除</button>'
  puts '<table>'
  # 見出し
  puts '<tr>'
  puts %w(頭防具 胴防具 腕防具 腰防具 脚防具 護石).map {|s|
    '<td class=head>%s' %s }.join
  # リスト
  puts '<tr style="vertical-align:top">'
  xss.each {|xs|
    puts '<td>'
    xs.each {|x| puts(x ? x : '<div>　</div><br>') }
  }
  puts '</table>'
  puts '</div> <!-- of excludetab -->'
  puts
end

# 「エクスポート・インポート」タブのhtmlを表示
def print_exporttab
puts <<EOS
<!-- ================ 第5タブ: エクスポート・インポート ================ -->
<div class=usualtab id=exporttab>
<h3>エクスポート・インポート</h3>
<button onclick='exportSkl()'>スキル表示一覧エクスポート</button>
<button onclick=importSkl()>スキル表示一覧インポート</button>
<textarea id=export-skilltab rows=5 style="width:100%"></textarea>

<hr>

<button onclick=exportExclude()>除外防具・護石エクスポート</button>
<button onclick=importExclude()>除外防具・護石インポート</button>
<textarea id=export-exclude rows=5 style="width:100%"></textarea>

<hr>

<button onclick=exportDeco()>装飾品上限エクスポート</button>
<button onclick=importDeco()>装飾品上限インポート</button>
（泣きシミュ互換予定）
<textarea id=export-deco rows=5 style="width:100%"></textarea>

</div> <!-- of exporttab -->

EOS
end


# 「GLPK」タブのhtmlを表示
def print_glpktab
puts <<EOS
<!-- ================ 第6タブ: GLPK ================ -->
<div class=usualtab id=glpktab>
<h3>GLPK</h3>
<h4>GLPKソース</h4>
<textarea id=glpksource cols=150 rows=10></textarea>
<br>
<input type="submit" id="runbutton" value=" run " onclick="run()" />

<h4>ログ</h4>
<textarea id=glpklog cols=150 rows=10 ></textarea>

</div> <!-- of glpktab -->

EOS
end

# フッタのhtmlを表示
def print_footer_html
puts <<EOS
</body>
</html>
EOS
end

#### sim09data.js

# 各装備のx変数の開始番号
def print_eqp_beg_num(mat)
  res = [] # 開始番号をためる
  cnt = [nil] * 6 # 前の行と異なるか判定用
  idx = %w(頭 胴 腕 腰 脚 護石).map {|s| Yi[s] }
  mat.each_with_index{|row, i|
    if cnt != row.values_at(*idx) then
      res.push(i)
      cnt = row.values_at(*idx)
    end
  }
  puts '// 装備のx変数の開始番号'
  puts "var headBegin = #{res[0]};"
  puts "var bodyBegin = #{res[1]};"
  puts "var armBegin = #{res[2]};"
  puts "var wstBegin = #{res[3]};"
  puts "var legBegin = #{res[4]};"
  puts "var charmBegin = #{res[5]};"
  puts "var decoBegin = #{res[6]};"
  puts
end

# y変数の添字
def print_y_index
puts <<EOS
// y変数の添字
var Yi = {
    '名前':0,
    '頭':1,       '胴':2,       '腕':3,       '腰':4,       '脚':5,
    '男':6,       '女':7,
    '護石':8,
    'スロ1':9,    'スロ2':10,   'スロ3':11,   'スロ4':12,
    '防御力':13,
    '火耐性':14,  '水耐性':15,  '雷耐性':16,  '氷耐性':17,  '龍耐性':18,
    'スキル':19
};

EOS
end

# 会心率を上げるスキルの辞書を表示
def print_skill_attack_data_js
puts <<EOS
// 会心率を上げるスキル
var skillCritical = {
    '滑走強化':[0,30],
    '攻撃':[0,0,0,0,5,5,5,5],
    '渾身':[0,10,20,30,40,40],
    '弱点特効':[0,15,30,50],
    '力の解放':[0,10,20,30,40,50,50,60],
    '挑戦者':[0,5,5,7,7,10,15,20],
    '抜刀術【技】':[0,30,60,100],
    '見切り':[0,5,10,15,20,25,30,40],
}

// 攻撃力可算補正 (一部)
var skillAttackAdd = {
    '攻撃':[0,3,6,9,12,15,18,21],
    '挑戦者':[0,4,8,12,16,20,24,28],
    'フルチャージ':[0,5,10,20],
};

// 攻撃力乗算補正 (一部)
var skillAttackMul = {
    '無属性強化':[1,1.05],
    '攻めの守勢':[1,1.05,1.1,1.15],
    '飛燕':[1,1.3],
};

// 超会心倍率
var choCritical = [1.25,1.3,1.35,1.4];

EOS
end

# x0 => 拡大係数ベクトルの辞書のjsを表示
def print_coef_mat_js(mat)
  puts '// 拡大係数ベクトルの辞書'
  puts 'var coefMat = {'
  mat.each_with_index {|row, i|
    puts'"x%d":%s,' % [i, row.inspect]
  }
  puts '};';
  puts
end

# 防具名=>変数名の辞書のjsを表示
def print_eqp_to_var(mat)
  puts '// 防具名=>変数名の辞書'
  puts 'var eqpToVar = {'
  puts mat.each_with_index.map {|row, i|
    '%s:"x%s"' % [row[0].inspect, i]
  }.join(",\n")
  puts '};'
  puts
end

# スキル名=>変数名の辞書のjsを表示
def print_skill_to_var(skllist)
  puts '// スキル名=>変数名の辞書'
  puts 'var skillToVar = {'
  puts skllist.map {|k, v|
    '"%s":"y%d"' % [k, v[0]+Yi['スキル']]
  }.join(",\n")
  puts '};'
  puts
end

# スキル名=>変数名の辞書のjsを表示
def print_var_to_skill(skllist)
  puts '// 変数名=>スキル名の辞書'
  puts 'var varToSkill = {'
  puts skllist.map {|k, v|
    '"y%d":"%s"' % [v[0]+Yi['スキル'], k]
  }.join(",\n")
  puts '};'
  puts
end

# シリーズスキルの変数名=>{Lv:発動スキル}の辞書を表示
def print_series_data_dic(skllist)
  puts '// シリーズスキルの変数名=>{Lv=>発動スキル}の辞書'
  puts 'var seriesDic = {'
  skllist.each {|s, (num, lvs, cat, lvtxt)|
    next if cat != 'シリーズスキル'
    raise unless lvs.size == lvtxt.size
    puts 'y%s:{%s},' % [
      num + SKILL_OFST,
      lvs.size.times.map {|i| '%d:"%s"' % [lvs[i], lvtxt[i]] }.join(',') ]
  }
  puts '};'
  puts
end

# glpkに渡すテキスト。ワンセット防具の等式を表示
def print_glpk_oneset(mat)
  # まずワンセット防具すべての名前を収集
  names = []
  [:head, :body, :arm, :wst, :leg].each {|part|
    open(CSVFILES[part]) {|file|
      while line = file.gets
        line = line.strip
        next if line.empty? || line[0] == '#' # 先頭行だけ引用符がある
        cs = line.split(',')
        next if cs.empty? || cs[0].empty? # 名前が空で仮番号のある行がある
        next if cs[37] != '1' # ワンセットか
        names.push(cs[0])
      end
    }
  }
  # 名前を、5部位の組合せにグループ化 (先頭2文字と最後のギリシア文字で判定)
  h = {}
  names.each {|name|
    if /^((EX)?(..))[^αβγ]*([αβγ]?)/ !~ name then
      $stderr.push("規定外のワンセット防具名: #{name}")
      next
    end
    key = $1+$4
    i0 = nil
    mat.size.times {|i|
      if mat[i][0] == name then
        i0 = i
        break
      end
    }
    next if ! i0
    h[key] = [] if ! h.has_key?(key)
    h[key].push(i0)
  }
  # 表示
  puts '// ワンセット防具のglpk等式'
  puts 'var glpkOneset =`'
  h.each {|s, num|
    if num.size != 5 then
      $stderr.puts('ワンセット防具 %s が %d 個ある' % [s, num.size])
      next
    end
    num[1..4].each {|i| puts "x#{num[0]} - x#{i} = 0" }
  }
  puts '`;'
  puts
end

# glpkに渡すテキスト。y変数の定義の辞書を表示 (結局全部使いそうだが)
def print_glpk_rel_dic(mat)
  puts '// x変数とy変数のglpk関係式の辞書'
  puts 'var glpkRelDic = {'
  (1...mat[0].size).each {|i| # 0列は名前なので、y0はない
    str = mat.size.times.map {|j|
      c = mat[j][i]
      c==0 ? '' : (c==1) ? (' + x%d' % j) : ' %+d x%d' % [c, j]
    }.join
    str = '' if str.empty? # この場合は空文字列でよい
    puts '"y%d":"%s - y%d = 0",' % [i, str, i]
  }
  puts '};'
  puts
end

# glpkに渡すテキスト。極意による上限解放の関係式
def print_glpk_gokui_sbj(mat, skllist)
  puts '// 極意による上限解放の関係式'
  puts 'var glpkGokuiSbj = `'
  GOKUI.each {|s, l1, l2, g, m| # スキル,最大Lv,解放後最大Lv,極意,極意必要Lv
    ys = 'y%d' % (skllist[s][0] + Yi['スキル'])
    yg = 'y%d' % (skllist[g][0] + Yi['スキル'])
    yyg = 'yy%d' % (skllist[g][0] + Yi['スキル']) # 補助変数 [yg/m] にあたる
    puts "#{ys} - #{l2-l1} #{yyg} <= #{l1}"
    puts "#{m} #{yyg} - #{yg} <= 0"
  }
  print_glpk_gokui_cho_sbj(mat, skllist)
  puts '`;'
  puts
end

# glpkに渡すテキスト。極意による上限解放の関係式
# 挑戦者のみ2つ極意があるので別扱い。print_glpk_gokui_sbj から呼ばれる
def print_glpk_gokui_cho_sbj(mat, skllist)
  ys = nil
  yygs = []
  ls = []
  GOKUI_CHO.each {|s, l1, l2, g, m| # スキル,最大Lv,解放後最大Lv,極意,極意必要Lv
    ys = 'y%d' % (skllist[s][0] + Yi['スキル'])
    yg = 'y%d' % (skllist[g][0] + Yi['スキル'])
    yyg = 'yy%d' % (skllist[g][0] + Yi['スキル']) # 補助変数 [yg/m] にあたる
    yygs.push(yyg)
    ls = [l1, l2]
    puts "#{m} #{yyg} - #{yg} <= 0"
  }
  l1, l2 = ls
  puts "#{ys} - #{l2-l1} #{yygs[0]} - #{l2-l1}#{yygs[1]} <= #{l1}"
end


# glpkに渡すテキスト。極意による上限解放での補助変数の宣言
def print_glpk_gokui_gen(skllist)
  puts '// 極意による上限解放の補助変数glpk'
  print 'var glpkGokuiGen = "'
  print (GOKUI+GOKUI_CHO).map {|s,l1,l2, g, m| # _, _, _, 極意スキル, _
    yyg = 'yy%d' % (skllist[g][0] + Yi['スキル']); # 補助変数 [yg/m] にあたる
  }.join(' ')
  puts '";'
  puts
end

# glpkに渡すテキスト。極意による上限解放での補助変数の範囲
def print_glpk_gokui_bnd(skllist)
  puts '// 極意による上限解放の補助変数の範囲glpk'
  print 'var glpkGokuiBnd = `'
  GOKUI.each {|s, l1, l2, g, m| # スキル,最大Lv,解放後最大Lv,極意,極意必要Lv
    yyg = 'yy%d' % (skllist[g][0] + Yi['スキル']); # 補助変数 [yg/m] にあたる
    puts "0 <= #{yyg} <= #{5/m}"
  }.join("\n")
  puts '`;'
  puts
end

#### main
skllist = read_skills() # スキルのHash
mat = read_eqp(skllist)+read_charm(skllist)+read_deco(skllist) # 拡大係数行列

$debug = ARGV.delete('-b')
$decosort = ARGV.delete('-s')

if ARGV.delete('-h') then
  # htmlファイルの出力
  print_header_html
  print_querytab_header1
  print_weaponskill(skllist)
  print_querytab_header2
  print_skillpane(skllist)
  print_querytab_btns_result
  print_querytab_instruction
  print_querytab_footer
  print_skilltab(skllist)
  print_decotab(mat, skllist)
  print_excludetab(mat)
  print_exporttab
  print_glpktab
  print_footer_html
elsif ARGV.delete('-d') then
  # data.jsファイルの出力
  print_eqp_beg_num(mat)
  print_y_index
  print_skill_attack_data_js
  print_coef_mat_js(mat)
  print_eqp_to_var(mat)
  print_skill_to_var(skllist)
  print_var_to_skill(skllist)
  print_series_data_dic(skllist)
  print_glpk_oneset(mat)
  print_glpk_rel_dic(mat)
  print_glpk_gokui_sbj(mat, skllist)
  print_glpk_gokui_bnd(skllist)
  print_glpk_gokui_gen(skllist)
end
