"use strict";

var nmsOplog = nmsOplog || {

}

nmsOplog.init = function() {
	nmsData.addHandler("oplog", "nmsOplogHandler", nmsOplog.updateComments);
}

nmsOplog.commit = function() {
	var s = document.getElementById('logbox-id').value;
	var d = document.getElementById('logbox').value;

	var myData = {"systems": s, "log": d};
	myData = JSON.stringify(myData);
	$.ajax({
		type: "POST",
		url: "/api/write/oplog",
		dataType: "text",
		data:myData,
		success: function (data, textStatus, jqXHR) {
			nmsData.invalidate("oplog");
		}
	});
	document.getElementById('logbox-id').value = "";
	document.getElementById('logbox').value = "";
	document.getElementById('searchbox').value = "";

}

nmsOplog.updateComments = function() {
	nmsOplog._updateComments(5,"-mini","time");
	nmsOplog._updateComments(0,"","timestamp");
}

nmsOplog.getSwitchLogs = function(sw) {
	var logs = [];
	for (var v in nmsData['oplog']['oplog']) {
		var log = nmsData['oplog']['oplog'][v];
		if (nmsInfoBox.searchSmart(log['systems'],sw)) {
			logs.push(log);
		}
	}
	return logs;
}

nmsOplog._updateComments = function(limit,prefix,timefield) {
	var table = document.createElement("table");
	var tr;
	var td1;
	var td2;
	var td3;
	table.className = "table";
	table.classList.add("table");
	table.classList.add("table-condensed");
	var i = 0;
	for (var v in nmsData['oplog']['oplog']) {
		tr = table.insertRow(-1);
		td1 = tr.insertCell(0);
		td2 = tr.insertCell(1);
		td1.innerHTML = nmsData['oplog']['oplog'][v][timefield];
		td2.innerHTML = "[" + nmsData['oplog']['oplog'][v]['username'] + "] " + nmsData['oplog']['oplog'][v]['log'];
		if (++i == limit)
			break;
	}
	try {
		var old = document.getElementById("oplog-table" + prefix);
		old.parentElement.removeChild(old);
	} catch(e) {}
	var par = document.getElementById("oplog-parent" + prefix);
	table.id = "oplog-table" + prefix;
	par.appendChild(table);
};
