// これらは sim08glpk.js で定義されているはず
var logNode;
var glpksrc;
var runbtn;
var job;

// glpk実行関連 ================

// 検索実行。skl (変数名) のスキルを最大化。ad = true なら追加検索
function doQuery(skl, ad, loop) {
    updateQueryButton('stop'); // ボタンを更新
    skl = skl ? skl : `y${Yi['防御力']}`; // sklがnullなら防御力
    var sklLvDic = skillLvtoDic();
    var glpktxts = makeGlpkSrc(skl, ad);
    var glpktxt = glpktxts.flat().join("\n");
    // glpk実行
    document.getElementById('progress').innerHTML = '検索中';
    glpksrc.value = glpktxt;
    job = new Worker("sim09worker.js");
    var tm;
    job.onmessage = function(e) {
	if (e.data.action == 'tentative') {
	    var tm1 = performance.now() - tm;
	    insertResult(e.data.result, skl, sklLvDic, tm1, ad, glpktxts);
	    tm = performance.now();
	} else if (e.data.action == 'done') {
	    updateQueryButton('done'); // ボタンを更新
	    if (e.data.result['y'+Yi['防御力']] == 0) { // 結果なし表示のため
		insertResult(e.data.result, skl, sklLvDic, tm1, ad, glpktxts);
	    }
	    document.getElementById('progress').innerHTML = '';
	    job.terminate();
	    job = null;
	    if (loop > 1) {
		for (var k in e.data.result) {
		    if (e.data.result[k] != 0) {
			doQuery(skl, ad, loop-1);
			break;
		    }
		}
	    }
	} else if (e.data.action == 'log') {
	    log(e.data.message);
	}
    };
    tm = performance.now();
    job.postMessage({action: 'load', data: glpktxt, mip: true});
}

// 検索 / 追加検索を中断
function doStop() {
    job.terminate();
    job = null;
    updateQueryButton('done');
    document.getElementById('progress').innerHTML = '';
}

// glpkに渡すテキストを構築。flatしてjoinすれば良い配列を返す
// [max, sbj, adds, bnd, gen, bin, "\nEND\n"]
// ad = null / '除外'
function makeGlpkSrc(skl, ad) {
    var max = ['Maximize'];
    var sbj = ["\n", 'Subject to', glpkOneset, glpkGokuiSbj];
    var bnd = ["\n", 'Bounds', glpkGokuiBnd];
    var gen = ["\n", 'Generals', glpkGokuiGen];
    var bin = ["\n", 'Binaries'];
    // スキルの変数名=>指定レベルの辞書
    var sklLvDic = skillLvtoDic();
    // 防具カウンタ
    for (var i = Yi['頭']; i <= Yi['脚']; i++) {
	sbj.push(glpkRelDic[`y${i}`]); // sbj
	bin.push(`y${i}`); // bin
    }
    // 護石
    var i = Yi['護石'];
    sbj.push(glpkRelDic[`y${i}`]); // sbj
    bin.push(`y${i}`); // bin
    // スロット (武器スロットも考慮)
    var wesl = weaponSlot();
    var [a, b] = [Yi['スロ1'], Yi['スロ4']];
    for (var i = a; i <= b; i++) {
	sbj.push(glpkRelDic[`y${i}`]); // sbj
	gen.push(`y${i}`); // gen
	bnd.push(`y${i} >= -${wesl[i-a]}`); // bnd
    }
    // 防御力
    var i = Yi['防御力'];
    var minDef = parseInt(document.getElementById('minDefence').value);
    sbj.push(glpkRelDic[`y${i}`]); // sbj
    gen.push(`y${i}`); // gen
    bnd.push(`y${i} >= ${minDef}`); // bnd
    // 耐性
    var resistId = 
	['hiResist', 'mizuResist', 'kamiResist', 'koriResist', 'ryuResist'];
    for (var i = 0; i < 5; i++) {
	var ii = i + Yi['火耐性'];
	var lowBnd = parseInt(document.getElementById(resistId[i]).value);
	 sbj.push(glpkRelDic[`y${ii}`]); // sbj
	 gen.push(`y${ii}`); // gen
	 bnd.push(`y${ii} >= ${lowBnd}`); // bnd
    }
    // 何を最大化するか
    var maxStr = `20 y${Yi['防御力']} + y${Yi['スロ1']}`; //防御力,スロ1
    if (skl != `y${Yi['防御力']}`) { // スキル最大化なら上の位に追加
	maxStr = `40000 ${skl} + ` + maxStr;
    }
    max.push(maxStr);
    // スキルLv指定 (なぜか無関係なスキルも定義した方が早い)
    var wesklsel = document.getElementById('weaponskill'); // 武器スキル取得
    var weskl = wesklsel.options[wesklsel.selectedIndex].getAttribute('v');
    var es = document.querySelectorAll('div#skillpane select');
    for (var elt of es) {
	var v = elt.getAttribute('v');
	var minLv = (v in sklLvDic) ? sklLvDic[v] : 0;
	var maxLv = elt.getAttribute('maxlv');
	bnd.push(`${minLv} <= ${v} <= ${maxLv}`); // bnd
	sbjstr = glpkRelDic[v];
	if (v == weskl) { sbjstr = sbjstr.slice(0,-1) + '-1'; } // 武器スキル対応
	sbj.push(sbjstr); // sbj 
	gen.push(v); // gen
    }
    // 装飾品上限
    var decodic = decoToDic(); // 装飾品の変数名=>個数
    for (var v in decodic) {
	bnd.push(`0 <= ${v} <= ${decodic[v]}`); // bnd
	gen.push(v); // gen
    }
    // 防具・護石の除外
    var elts = document.querySelectorAll('div#excludetab input');
    for (elt of elts) {
	var v = elt.getAttribute('v')
	if (elt.checked) {
	    bnd.push(`0 <= ${v} <= 0`);
	    gen.push(v); // たしたよ
	} else {
	    bin.push(v);
	}
    }
    // 検索済み防具の組合せを除外した追加検索
    // 「なし」の部位があると不等式では除外できない
    var adds = [];
    if (ad == '除外') {
	var sums = document.querySelectorAll('div#resultpane details summary');
	for (var sum of sums) {
	    var eqps = [];
	    for (var elt of sum.children) {
		if (elt.classList.contains('item') && elt.hasAttribute('v')) {
		    eqps.push(elt.getAttribute('v'));
		}
	    }
	    if (eqps.length == 5) { adds.push(eqps.join(' + ') + ` <= 4`); 
	    }
	}
    } 
    // 返り値
    return [max, sbj, adds, bnd, gen, bin, "\nEND\n"]
}

// 武器スロットの数をプルダウンメニューから読み取る
function weaponSlot() {
    var wesl = [0, 0, 0, 0]; // Lv1以上, 2以上, 3以上, 4以上 のスロット数
    var selwe = document.getElementById('weaponslot');
    var selwestr = selwe.options[selwe.selectedIndex].text;
    var mch = selwestr.match(/[1-4]/g);
    if (! mch) return wesl;
    for (var t of mch) {
	var u = parseInt(t);
	for (var i = 0; i < u; i++) { wesl[i] += 1; }
    }
    return wesl;
}

// 検索結果消去 (ボタンから実行)
function clearResult() {
    elt = document.getElementById('resultpane');
    elt.innerHTML = '';
    updateQueryButton('clear'); // 検索ボタンの更新
}

// 検索結果の1アイテムを消去 ()
function clearItem(ev) {
    detailNode = ev.target.parentNode.parentNode;
    elt = detailNode.nextElementSibling;
    if (elt.tagName == 'HR') {
	elt.remove();
    }
    detailNode.remove();
    updateQueryButton('clear'); // 検索ボタンの更新
}

// スキルLv指定のあるものを辞書化。スキルの変数名=>Lv
function skillLvtoDic() {
    var sklLv = {}; // スキルの変数名=>Lv
    var es = document.querySelectorAll('div#skillpane select');
    for (var elt of es) {
	var lv = parseInt(elt.options[elt.selectedIndex].value);
	if (lv > 0) {
	    sklLv[elt.getAttribute('v')] = lv;
	}
    }
    return sklLv;
}

// 検索結果表示関連 ================

// 検索結果表示
// glpktxtsはglpk文字列の配列 [max, sbj, adds, bnd, gen, bin, "\nEND\n"]
function insertResult(res, meth, sklLv, tm, ad, glpktxts) {
    var eqp = ['なし', 'なし', 'なし', 'なし', 'なし', 'なし']; // 5部位+護石
    var deco = {}; // 装飾品
    var skls = {}; // スキルポイント
    var ks = Object.keys(res);
    for(var i = 0; i < ks.length; i++) {
	var ch = ks[i].slice(0,1);
	var idx = parseInt(ks[i].slice(1));
	var num = res[ks[i]];
	if (num != 0) {
	    if (ch == 'x') { // 防具・護石の数は1と信じる
		if (idx < bodyBegin) {         eqp[0] = ks[i]; 
		} else if (idx < armBegin) {   eqp[1] = ks[i];
		} else if (idx < wstBegin) {   eqp[2] = ks[i];
		} else if (idx < legBegin) {   eqp[3] = ks[i];
		} else if (idx < charmBegin) { eqp[4] = ks[i];
		} else if (idx < decoBegin) {  eqp[5] = ks[i];
		} else {                       deco[ks[i]] = num;
		}
	    } else if (ch == 'y') {
		skls[ks[i]] = num;
	    } else {
		console.log('bad variable name: ' + ks[i]);
	    }
	}
    }
    var str = [];
    str.push('<details>', '<summary>',
	     eqpHTML(eqp, deco, skls, meth),
	     '<input type=button value="x" onclick="clearItem(event)">',
	     '</summary>',
	     '<div class=bg>',
	     detailHTML(eqp, deco, skls, meth, sklLv, res, ad),
	     `${Math.round(tm)/1000.0}sec`,
	     '</div>',
	     '<textarea style="display:none"></textarea>', // glpk文字列用
	     '</details><hr>');
    var elt = str.join("\n");
    var respane = document.getElementById('resultpane');
    respane.insertAdjacentHTML('afterbegin', elt);
    // glpk文字列の保存
    var fix = []; // 防具を固定
    for (var i = 0; i < 5; i++) {
	if (eqp[i] != 'なし') { fix.push(`${eqp[i]} = 1`); }
    }
    var tarea = document.querySelector('div#resultpane details textarea');
    var save = [glpktxts[1], fix, glpktxts[3], glpktxts[4], glpktxts[5], res];
    tarea.value = JSON.stringify(save); // [sbj, fix, bnd, gen, bin, res]
}

// 防御力、会心率、攻撃力、防具、護石の1行表示のhtml
function eqpHTML(eqp, deco, skls, meth) {
    var defence = skls[`y${Yi['防御力']}`] || 'n/a';
    var critical = calcCritical(skls);
    var attack = calcAttack(skls);
    var str = [];
    str.push(`<span class=num>${defence} ${critical}% ${attack}</span> `);
    for(i = 0; i < 6; i++) { 
	var cls = (i==5) ? 'item-charm' : 'item';
	if (eqp[i] == 'なし') {
	    str.push(`<span class=${cls}>${eqp[i]}</span>`); 
	} else {
	    str.push(`<span class=${cls} v=${eqp[i]}>`);
	    str.push(`<input type=checkbox class=chk${eqp[i]} v=${eqp[i]} onclick=\"h_ExcludeChk(event)\">`);
	    str.push(`${coefMat[eqp[i]][0]}</span>`); 
	}
    }
    return str.join("\n");
}

// 最大の会心率を計算
function calcCritical(skls) {
    var wcri = parseInt(document.getElementById('critical').value);
    var scri = 0;
    for (var k in skls) {
	var criary = skillCritical[varToSkill[k]];
	if (! criary) continue;
	scri += criary[skls[k]];
    }
    return wcri + scri;
}

// 簡易的に攻撃力を計算
function calcAttack(skls) {
    // 表示攻撃力、武器倍率、基礎攻撃力
    var dispAtk = parseInt(document.getElementById('dispAtk').value);
    var weapRatio = parseFloat(document.getElementById('weapKind').value);
    var baseAtk = dispAtk / weapRatio;
    // 可算補正を計算
    var atkAdd = 0;
    for (var k in skls) {
	var addAry = skillAttackAdd[varToSkill[k]];
	if (addAry) atkAdd += addAry[skls[k]];
    }
    // 乗算補正を計算
    var atkMul = 1;
    for (var k in skls) {
	var mulAry = skillAttackMul[varToSkill[k]];
	if (mulAry) atkMul *= mulAry[skls[k]];
    }
    // 超会心補正を計算
    var cri = calcCritical(skls); // 会心率 (%)
    if (cri > 100) cri = 100;
    var choLv = skls[skillToVar['超会心']] || 0;
    var choMul = (cri*choCritical[choLv] + (100-cri)) * 0.01;
    //
    return Math.round((dispAtk/weapRatio + atkAdd) * atkMul * choMul);
}

// detailsのsummary以外の部分のhtml
function detailHTML(eqp, deco, skls, skl, sklLv, res, ad) {
    skl = (skl == `y${Yi['防御力']}`) ? '防御力' :  `「${varToSkill[skl]}」`;
    var str = [];
    if (ad) { str.push(`${skl}最大化・追加検索 / 検索条件`); 
    } else { str.push(skl + "最大化検索 / "); }
    str.push('武器スロット' + document.getElementById('weaponslot').value);
    str.push('武器スキル' + document.getElementById('weaponskill').value);
    str.push(' / 検索条件: ');
    for (k in sklLv) {
	str.push(varToSkill[k] + 'Lv' + sklLv[k] + " ");
    }
    str.push('<br>', 
	     skillHTML(eqp, deco, skls, sklLv, res),
	     decoHTML(eqp, deco, skls, sklLv, res),
	     slotHTML(res),
	     tolHTML(res),
	     moreSkillHTML(),
	     );
    return str.join("\n");
}

// 検索対象スキル・対象外スキル
function skillHTML(eqp, deco, skls, sklLv, res) {
    var str = [];
    // 検索対象スキル (Lv降順、タイブレークスキル番号昇順)
    var str0 = [];
    for (var k in sklLv) {
	var s = varToSkill[k] + 'Lv' + res[k];
	if (res[k] > sklLv[k]) { s += ` (${sklLv[k]})`; }
	str0.push([s, sklLv[k], parseInt(k.slice(1))]); 
    }
    str0.sort((s1, s2) => {return (s2[1]-s1[1])*10000 + (s2[2]-s1[2])});
    for (var i = 0; i < str0.length; i++) { str0[i] = str0[i][0]; }
    str0.unshift('検索対象スキル');
    str.push(vbox(str0));
    // 検索対象外スキル
    str0 = ['検索対象外スキル'];
    for (var k in res) {
	var num = parseInt(k.slice(1));
	if (k.slice(0,1) == 'y' && num >= Yi['スキル'] &&
	    ! (k in sklLv) && res[k] > 0) {
	    str0.push(varToSkill[k] + 'Lv' + res[k] + ' ');
	}
    }
    str.push(vbox(str0));
    return str.join("\n");
}

// 検索対象スキル・対象外スキル
function skillHTML(eqp, deco, skls, sklLv, res) {
    var str = [];
    // 検索対象スキル
    var str0 = Object.keys(sklLv);
    str0 = sortby(str0, (k) =>
		  (seriesDic[k] ? 1 : 0) * 100000 // シリーズは後へ
		  - res[k]*10000  // スキルポイントの高い順
		  + parseInt(k.slice(1))); // スキル番号順
    str0 = str0.map((k) => skillHTML_line(k, res[k], sklLv[k]));
    str0.unshift('検索対象スキル');
    str.push(vbox(str0));
    // 検索対象外スキル
    var str0 = [];
    for (var k in res) { // 検索結果のy変数のうちスキルを収集
	var num = parseInt(k.slice(1));
	if (k.slice(0,1) == 'y' && num >= Yi['スキル'] && 
	    ! (k in sklLv) && res[k] > 0) {
	    str0.push(k);
	}
    }
    str0 = sortby(str0, (k) =>
		  (seriesDic[k] ? 1 : 0) * 100000 // シリーズは後へ
		  - res[k]*10000  // スキルポイントの高い順
		  + parseInt(k.slice(1))); // スキル番号順
    str0 = str0.map((k) => skillHTML_line(k, res[k], res[k]));
    str0.unshift('検索対象外スキル');
    str.push(vbox(str0));
    return str.join("\n");
}

// 1スキルを表示する文字列。lv0は検索で指定したLv。以下が例
// 攻撃Lv6
// 攻撃Lv6 (4)
// 炎王龍の武技Lv2 (発動せず)
// 炎王龍の武技Lv3 (達人芸)
function skillHTML_line(skl, lv, lv0) {
    var lv0txt = '';
    var sertxt = '';
    if (! seriesDic[skl]) {
	lv0txt = (lv==lv0) ? '' : ` (${lv0})`; // 指定Lvと異なる場合
    } else {
	var ser = [];
	for (var lv1 in seriesDic[skl]) {
	    if (lv1 <= lv) { ser.push(seriesDic[skl][lv1]); }
	}
	sertxt = (ser.length==0) ? ' (発動なし)' : ` (${ser.join(', ')})`;
    }
    return varToSkill[skl] + `Lv${lv}` + lv0txt + sertxt;
}

// 装飾品・上限設定一覧
function decoHTML(eqp, deco, skls, sklLv, res) {
    var str = [];
    // Lv降順、タイブレーク変数番号順でソート
    var deco2 = Object.keys(deco);
    deco2 = sortby(deco2, (k) => {
	    var mch = coefMat[k][0].match(/【(.)】/);
	    return ['４', '３', '２', '１'].indexOf(mch[1]);
	});
    //
    var str0 = ['（上限）装飾品'];
    for (var k of deco2) {
	// 装飾品上限設定のチェックボックス
	var sel = document.getElementById(`sel${k}`);
	var opts = sel.innerHTML;
	var i = sel.selectedIndex;
	var hi = (i == sel.length-1) ? '' : 'hilite';
	// 選択中のアイテムを設定
	opts = opts.replace(/<option/gi, function(mch) {
		if (i-- == 0) { return '<option selected'; 
		} else { return mch; }
	    });
	var s = [`<select class="sel${k} ${hi}" v=${k} onchange=\"h_DecoDropdown(event)\">`,
		 opts,
		 '</select>'].join(' ');
	// 装飾品
	if (deco[k] == 1) {
	    s += coefMat[k][0];
	} else if (deco[k] > 1) {
	    s += coefMat[k][0] + 'x' + String(deco[k]);
	}
	str0.push(s);
    }
    str.push(vbox(str0));
    return str.join("\n");
}

// 空きスロットのhtml
function slotHTML(res) {
    var wsl = weaponSlot();
    sl1 = wsl[0] + parseInt(res[`y${Yi['スロ1']}`]);
    sl2 = Math.min(wsl[1] + parseInt(res[`y${Yi['スロ2']}`]), sl1);
    sl3 = Math.min(wsl[2] + parseInt(res[`y${Yi['スロ3']}`]), sl2);
    sl4 = Math.min(wsl[3] + parseInt(res[`y${Yi['スロ4']}`]), sl3);
    var str = ['空きスロット'];
    str.push(`Lv1 = ${sl1-sl2}`,
	     `Lv2 = ${sl2-sl3}`,
	     `Lv3 = ${sl3-sl4}`,
	     `Lv4 = ${sl4}`);
    return vbox(str);
}

// 耐性のhtml
function tolHTML(res) {
    var str = ['耐性'];
    var zs = ['火耐性', '水耐性', '雷耐性', '氷耐性', '龍耐性'];
    for (var i = 0; i < 5; i++) {
	var a = res[`y${Yi[zs[i]]}`];
	str.push(`${zs[i]} ${a}`);
    }
    return vbox(str);
}

// 追加スキルのhtml
// 後で位置を特定するときは、value="追加スキル"で探して、textnodeを追加
function moreSkillHTML() {
    var str = ['<input type=button value="追加スキル" onclick="doMoreSkill(event)">'];
    return vbox(str);
}

// 追加スキル検索
function doMoreSkill(ev) {
    var inputNode = ev.target;
    var tableNode = inputNode.parentNode;
    inputNode.disabled = 'true';
    // 検索時のglpkテキストを取得
    var detailNode = inputNode;
    while (detailNode.tagName != 'DETAILS') { 
	detailNode = detailNode.parentNode; 
    }
    var tarea = detailNode.children[2]; // 2 はハードコード
    var [sbj, fix, bnd, gen, bin, res] = JSON.parse(tarea.value);
    // 追加検索対象のスキルを列挙
    var skls = [];
    var spanNodes = document.querySelectorAll('div#skillpane span');
    for (var elt of spanNodes) {
	if (elt.classList.contains('hide')) { continue; }
	var v = elt.children[0].getAttribute('v');
	var sel = document.getElementById('sel'+v);
	if (res[v] == parseInt(sel.options[sel.length-1].value)) { continue; }
	skls.push(v);
    }
    // 非同期にglpk実行
    doMoreSkill2(sbj, fix, bnd, gen, bin, skls, res, tableNode);
}

// 非同期にglpkで追加スキルを検索し、結果を挿入
function doMoreSkill2(sbj, fix, bnd, gen, bin, skls, res, tableNode) {
    if (skls.length == 0) return;
    // スキル名を表示
    var elt = document.createElement('span');
    elt.innerHTML = varToSkill[skls[0]];
    tableNode.appendChild(elt);
    // glpkテキスト構築
    var max = `Maximize ${skls[0]}`;
    var glpktxt = [max, sbj, fix, bnd, gen, bin, 'END'].flat().join("\n");
    // glpk実行
    var job = new Worker("sim09worker.js");
    job.onmessage = function(e) {
	if (e.data.action == 'done') {
	    job.terminate();
	    job = null;
	    var lv = e.data.result[skls[0]];
	    if (lv > res[skls[0]]) {
		tableNode.appendChild(document.createTextNode(`Lv${lv}`));
		tableNode.appendChild(document.createElement('br'));
	    } else {
		tableNode.lastElementChild.remove();
	    }
	    doMoreSkill2(sbj, fix, bnd, gen, bin, skls.slice(1), res, tableNode);
	} else if (e.data.action == 'log') {
	    // log(e.data.message);
	}
    };
    job.postMessage({action: 'load', data: glpktxt, mip: true});
}

// 検索ボタンの更新
// 'clear' 検索結果を消去したとき
// 'stop'  検索開始時にボタンを「検索中止」にするとき
// 'done'  検索完了や中断のとき
function updateQueryButton(status) {
    var btn1 = document.getElementById('querybtn');
    var btn2 = document.getElementById('querybtn-add');
    var btn3 = document.getElementById('querybtn-stop');
    if (status == 'clear') {
	if (btn3.style.display == 'none') {
	    status = 'done';
	} else {
	    status = 'stop';
	}
    }
    btn1.style.display = 'none';
    btn2.style.display = 'none';
    btn3.style.display = 'none';
    
    if (status == 'stop') {
	btn3.style.display = 'inline-block';
    } else if (status == 'done') {
	if (document.querySelector('div#resultpane details') == null) {
	    btn1.style.display = 'inline-block';
	} else {
	    btn2.style.display = 'inline-block';
	}
    }
}

// 配列要素を縦に並べる
function vbox(strs) {
    res = [];
    res.push(`<table  style="vertical-align:top;display:inline-block">`);
    res.push('<tr><td>');
    for (var s of strs) { res.push(s, '<br>'); }
    res.push('</table>');
    return res.join("\n");
}

// sort_by
function sortby(ary, f) {
    ary = ary.map((x) => [x, f(x)]);
    ary.sort( (y1, y2) => (y1[1]<y2[1]) ? -1 : (y1[1]==y2[1]) ? 0 : 1);
    ary = ary.map((x) => x[0]);
    return ary;
}
