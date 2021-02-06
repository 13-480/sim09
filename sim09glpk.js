var logNode;
var glpksrc;
var runbtn;
var job;

// onloadで初期化する
function initGlpk() {
    logNode = document.getElementById("glpklog");
    glpksrc = document.getElementById("glpksource");
    runbtn = document.getElementById("runbutton");
}

// ログを書き足し
function log(value){
    logNode.appendChild(document.createTextNode(value + "\n"));
    logNode.scrollTop = logNode.scrollHeight;
}

// ランボタン (ボタンから実行)
var run = function(){
    job = new Worker("sim09worker.js");
    job.onmessage = function (e) {
	var obj = e.data;
	switch (obj.action){
	case 'log':
	    log(obj.message);
	    break;
	case 'done':
	    stop();
	    log(JSON.stringify(obj.result));
	    log(JSON.stringify(Object.keys(obj.result)));

	    ks = Object.keys(obj.result);
	    for(i = 0; i < ks.length; i++) {
		k = ks[i];
		v = obj.result[k];
		if (v != 0) {
		    log(k + " = " + String(v));
		}
	    }
	    break;
	}
    };
    logNode.innerHTML = "";
    runbtn.value = 'stop';
    runbtn.onclick = stop;
    job.postMessage({action: 'load', data: glpksrc.value, mip: true});
}

// ストップボタン (ボタンから実行)
var stop = function(){
    job.terminate();
    job = null;
    runbtn.value = ' run ';
    runbtn.onclick = run;
}
