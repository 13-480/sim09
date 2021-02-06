// イベントハンドラ ================

// 各イベントハンドラを登録
function addHandlers() {
    // タブボタンのイベントハドラを設定
    tabbtns = document.querySelectorAll('div#header div#tabbar a');
    for (var elt of tabbtns) { 
	elt.addEventListener('click', h_TabButton); 
    }
    // スキルLv最大化ボタンのイベントハンドラを設定
    sklpane_btns = document.querySelectorAll('div#skillpane button');
    for (var elt of sklpane_btns) {
	elt.addEventListener('click', h_SkillButton);
    } 
    // スキルLv指定のドロップダウンのイベントハンドラを設定
    sklpane_drps = document.querySelectorAll('div#skillpane select');
    for (var elt of sklpane_drps) { 
	elt.addEventListener('change', h_SkillDropdown);
    }
    // スキル表示非表示のチェックボックスにイベントハンドラを設定
    skltab_cks = document.querySelectorAll('div#skilltab input');
    for (var elt of skltab_cks) {
	elt.addEventListener('click', h_ShowHideChk);
    }
    // 装飾品上限のドロップダウンのイベントハンドラを設定
    deco_drps = document.querySelectorAll('div#decotab select');
    for (var elt of deco_drps) {
	elt.addEventListener('change', h_DecoDropdown);
    }
    // 除外装備一覧のチェックボックスのイベントハンドラを設定
    exclude_cks = document.querySelectorAll('div#excludetab input');
    for (var elt of exclude_cks) {
	elt.addEventListener('change', h_ExcludeChk);
    }
}

// タブ切り替え
function h_TabButton(ev) {
    // ボタンの見た目変更
    tabbtns = document.querySelectorAll('div#header div#tabbar a');
    for (i=0; i < tabbtns.length; i++) {
	tabbtns[i].classList.remove('activebtn');
    }
    ev.target.classList.add('activebtn');
    // タブ内容の変更
    tabs = document.querySelectorAll('div.usualtab');
    for (i=0; i < tabs.length; i++) {
	tabs[i].classList.remove('activetab');
    }
    tabid = ev.target.getAttribute('show');
    document.getElementById(tabid).classList.add('activetab');
}

// スキルLv最大化検索ボタンのイベントハンドラ
function h_SkillButton(ev) {
    skl = ev.target.getAttribute('v');
    doQuery(skl, false, 1);
}

// スキルLv指定のドロップダウンのイベントハンドラ
// 指定があれば背景色を変える
function h_SkillDropdown(ev) {
    hiliteElement(ev.target, ev.target.selectedIndex > 0);
    saveSkl();
}

// 表示非表示のチェックボックスのイベントハンドラ
// チェックに応じてスキル指定のドロップダウンを表示・非表示
function h_ShowHideChk(ev) {
    setSkillShowHide(ev.target, ev.target.checked);
}

// 装飾品上限のドロップダウンのイベントハンドラ
// 指定があれば背景色を変える
// 装飾品上限は id=sely19、検索結果は class=sely19
var h_DecoDropdown = function (ev) {
    var v = ev.target.getAttribute('v');
    var i = ev.target.selectedIndex;
    // 装飾品上限タブのドロップダウン
    var sel = document.getElementById('sel' + v);
    sel.selectedIndex = i;
    hiliteElement0(sel);
    // 検索結果のドロップダウン
    var sels = document.querySelectorAll('select.sel' + v);
    for (var sel of sels) {
	sel.selectedIndex = i;
	hiliteElement0(sel);
    }
    // 保存
    saveDeco();
}

// 除外装備一覧のチェックボックスのイベントハンドラ
// チェックに応じて自身のクラスにhideを付け外しする
// 検索結果の装備のチェックボックスもここに来る
// 除外装備一覧は id=chkx0、検索結果は class=chkx0
var h_ExcludeChk = function (ev) {
    var v = ev.target.getAttribute('v');
    var f = ev.target.checked;
    // 除外装備一覧のチェックボックス
    var chk = document.getElementById('chk' + v);
    chk.checked = f;
    hideElement(chk.parentNode, !f); // でも消さなくしてるな、きっと
    // 検索結果のチェックボックス
    var chks = document.querySelectorAll('input.chk' + v);
    for (var chk of chks) chk.checked = f;
    // 保存
    saveExclude();
}

// 表示非表示のチェックボックス elt と対応するドロップダウンメニューを
// フラグ f に応じて設定
function setSkillShowHide(elt, f) {
    elt.checked = f;
    v = elt.getAttribute('v');
    drpid = 'sel' + v;
    drp = document.getElementById(drpid);
    hideElement(drp.parentNode, ! f);
    saveSkl();
}

// 装飾品上限の一斉に変更
var setAllDeco = function (n) {
    decotab_drp = document.querySelectorAll('div#decotab select');
    for (elt of decotab_drp) {
	if (n == 0)  {
	    elt.selectedIndex = 0;
	    hiliteElement0(elt);
	} else {
	    elt.selectedIndex = elt.length - 1;
	    hiliteElement0(elt);
	}
    }
    saveDeco();
}

// スキル表示の永続化 ================

// スキル表示一覧を、対応する変数名で配列化
function sklToArray() {
    // チェックされているものを収集
    res = [];
    skltab_cks = document.querySelectorAll('div#skilltab input');
    for (elt of skltab_cks) {
	if (elt.checked) { res.push(elt.getAttribute('v')); }
    }
    return res;
}

// スキルの変数名の配列をスキル表示一覧とスキルLv指定に反映
function arrayToSkl(ary) {
    skltab_cks = document.querySelectorAll('div#skilltab input');
    for (chk of skltab_cks) {
	flg = ary.includes(chk.getAttribute('v'));
	setSkillShowHide(chk, flg);
    }
}

// スキル表示一覧をlocal storageに記録
var LOCALSTORAGE_KEY_SKILL = `mhwlpsim-skill`;
function saveSkl() {
    var ary = [];
    for (var x of sklToArray()) { 
	ary.push(varToSkill[x]);
    }
    localStorage['LOCALSTORAGE_KEY_SKILL'] = JSON.stringify(ary);
}

// スキル表示一覧をlocal storageから回復
function loadSkl() {
    var str = localStorage['LOCALSTORAGE_KEY_SKILL'];
    var ary = [];
    if (str) {
	ary = JSON.parse(str);
	for (var i = 0; i < ary.length; i++) { ary[i] = skillToVar[ary[i]]; }
    }
    arrayToSkl(ary);
}

// スキル表示一覧のエクスポート (ボタンから実行)
var exportSkl = function() {
    tarea = document.getElementById('export-skilltab');
    saveSkl();
    tarea.value = localStorage['LOCALSTORAGE_KEY_SKILL'];
}

// スキル表示一覧のインポート (ボタンから実行)
var importSkl= function() {
    tarea = document.getElementById('export-skilltab');
    localStorage['LOCALSTORAGE_KEY_SKILL'] = tarea.value;
    loadSkl();
}

// 装飾品上限の永続化 ================

// 装飾品上限を辞書化。装飾品の変数名=>上限
function decoToDic() {
    // すべて収集
    res = {};
    decotab_drp = document.querySelectorAll('div#decotab select');
    for (elt of decotab_drp) {
	key = elt.getAttribute('v');
	num = parseInt(elt.options[elt.selectedIndex].value);
	res[key] = num;
    }
    return res;
}

// 装飾品上限の辞書を除外装備一覧に反映
function dicToDeco(dic) {
    decotab_drp = document.querySelectorAll('div#decotab select');
    for (drp of decotab_drp) {
	var v = drp.getAttribute('v');
	if (v in dic) {
	    var num = dic[v];
	    for (var i = 0; i < drp.length; i++) {
		if (drp.options[i].value == num) {
		    drp.selectedIndex = i;
		    break;
		}
	    }
	    // 満タンでなければハイライト
	    hiliteElement0(drp);
	}
    }
}

// 装飾品上限をlacal storageに記録
var LOCALSTORAGE_KEY_DECO = 'mhwlpsim-deco';
function saveDeco() {
    var dic = decoToDic();
    var dic1 = {};
    for (var x in dic) {
	dic1[coefMat[x][0]] = dic[x];
    }
    localStorage['LOCALSTORAGE_KEY_DECO'] = JSON.stringify(dic1);
}

// 装飾品上限をlacal storageから回復
function loadDeco() {
    var str = localStorage['LOCALSTORAGE_KEY_DECO'];
    var dic = {};
    if (str) {
	var dic1 = JSON.parse(str);
	for (var x in dic1) { dic[eqpToVar[x]] = dic1[x]; }
    }
    dicToDeco(dic);
}

// 装飾品上限のエクスポート (ボタンから実行)
var exportDeco = function() {
    tarea = document.getElementById('export-deco');
    saveDeco();
    tarea.value = localStorage['LOCALSTORAGE_KEY_DECO'];
}

// 装飾品上限のインポート (ボタンから実行)
var importDeco = function() {
    tarea = document.getElementById('export-deco');
    localStorage['LOCALSTORAGE_KEY_DECO'] = tarea.value;
    loadDeco();

}

// 除外防具・護石の永続化 ================

// 除外防具・護石を配列化
function excludeToArray() {
    // チェックされているものを収集
    res = [];
    excludetab_cks = document.querySelectorAll('div#excludetab input');
    for (elt of excludetab_cks) {
	if (elt.checked) { 
	    res.push(elt.getAttribute('v'));
	}
    }
    return res;
}

// 除外防具・護石の変数名の配列を除外装備一覧に反映
function arrayToExclude(ary) {
    excludetab_cks = document.querySelectorAll('div#excludetab input');
    for (chk of excludetab_cks) {
	v = chk.getAttribute('v')
	chk.checked = ary.includes(v);
	hideElement(chk.parentNode, ! chk.checked);
    }
}

// 除外防具・護石をlacal storageに記録
var LOCALSTORAGE_KEY_EXCLUDE = 'mhwlpsim-exclude';
function saveExclude() {
    var ary = [];
    for (var x of excludeToArray()) { ary.push(coefMat[x][0]); }
    localStorage['LOCALSTORAGE_KEY_EXCLUDE'] = JSON.stringify(ary);
}

// 除外防具・護石をlacal storageから回復
function loadExclude() {
    var str = localStorage['LOCALSTORAGE_KEY_EXCLUDE'];
    var ary = [];
    if (str) {
	ary = JSON.parse(str);
	for (var i = 0; i < ary.length; i++) { ary[i] = eqpToVar[ary[i]]; }
    }
    arrayToExclude(ary);
}

// 除外防具・護石のエクスポート (ボタンから実行)
var exportExclude = function() {
    tarea = document.getElementById('export-exclude');
    saveExclude();
    tarea.value = localStorage['LOCALSTORAGE_KEY_EXCLUDE'];
}

// 除外防具・護石のインポート (ボタンから実行)
var importExclude = function() {
    tarea = document.getElementById('export-exclude');
    localStorage['LOCALSTORAGE_KEY_EXCLUDE'] = tarea.value;
    loadExclude();
}

// 除外装備の一斉チェック ================

// ワールド防具をすべて除外 (f=1) / 除外しない(f=0)
var excludeOld = function(f) {
    var es = document.querySelectorAll('div#excludetab input');
    for (var elt of es) {
	var v = elt.getAttribute('v');
	if (coefMat[v][Yi['護石']] == 0 &&
	    coefMat[v][0].slice(0,2) != 'EX') {
	    elt.checked = (f==1);
	    hideElement(elt.parentNode, (f!=1));
	}
    }
    saveExclude();
}
	
// 汎用関数 ================

// フラグに応じてhideクラスを付けたり外したりする。trueならhide
function hideElement(elt, f) {
    if (f) {
	elt.classList.add('hide');
    } else {
	elt.classList.remove('hide');
    }
}

// フラグに応じてhiliteクラスを付けたり外したりする。trueならhilite
function hiliteElement(elt, f) {
    if (f) {
	elt.classList.add('hilite');
    } else {
	elt.classList.remove('hilite');
    }
}

// 装飾品のドロップダウンに特化したhiliteElement
// 0個ならhilite0、満タンならなし、他はhilite
function hiliteElement0(elt) {
    var i = elt.selectedIndex;
    elt.classList.remove('hilite');
    elt.classList.remove('hilite0');
    if (i == 0) {
	elt.classList.add('hilite0');
    } else if (i != elt.length-1) {
	elt.classList.add('hilite');
    }
}

// onload ================
onload = function () {
    // 各種イベントハンドラを登録
    addHandlers();
    // スキル表示一覧をlocal storageから回復
    loadSkl();
    // 除外防具・護石をlocal storageから回復
    loadExclude();
    // 装飾品上限をlocal storageから回復
    loadDeco();
    // glpkの初期化
    initGlpk();
}
