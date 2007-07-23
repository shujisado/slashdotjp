// $Id$

function admin_signoff(el) {
	var params = [];
	var reskeyel = $('signoff-reskey-' + el.value);
	params['op'] = 'admin_signoff';
	params['stoid'] = el.value;
	params['reskey'] = reskeyel.value;
	ajax_update(params, 'signoff_' + el.value);
	
}

function adminTagsCommands(id, type) {
	var toggletags_message_id = 'toggletags-message-' + id;
	var toggletags_message_el = $(toggletags_message_id);
	toggletags_message_el.innerHTML = 'Executing commands...';

	var params = [];
	type = type || "stories";
	params['op'] = 'tags_admin_commands';
	if (type == "stories") {
		params['sidenc'] = id;
	} else if (type == "urls") {
		params['id'] = id;
	}
	params['type'] = type;
	var tags_admin_commands_el = $('tags_admin_commands-' + id);
	params['commands'] = tags_admin_commands_el.value;
	var reskeyel = $('admin_commands-reskey-' + id);
	params['reskey'] = reskeyel.value;
	ajax_update(params, 'tags-admin-' + id);

	toggletags_message_el.innerHTML = 'Commands executed.';
}

function tagsHistory(id, type) {
	var params = [];
	type = type || "stories";
	params['type'] = type;
	if (type == "stories") {
		params['op'] = 'tags_history';
		params['sidenc'] = id;
	} else if (type == "urls") {
		params['op'] = 'tags_history';
		params['id'] = id;
	}
	var tagshistid = "taghist-" + id;
	var popupid    = "taghistory-" + id;
	var title      = "History ";
	var buttons    = createPopupButtons("<a href=\"#\">[?]</a></span><span><a href=\"javascript:closePopup('" + popupid + "-popup')\">[X]</a>");
	title = title + buttons;
	createPopup(getXYForId(tagshistid), title, popupid);
	ajax_update(params, "taghistory-" + id + "-contents");
}

function remarks_create() {
	var reskey = $('remarks_reskey');
	var remark = $('remarks_new');
	if (!remark || !remark.value || !reskey || !reskey.value) {
		return false;
	}

	var params = [];
	params['op']     = 'remarks_create';
	params['remark'] = remark.value;
	params['reskey'] = reskey.value;
	remarks_max = $('remarks_max');
	if (remarks_max && remarks_max.value) {
		params['limit'] = remarks_max.value;
	}
	ajax_update(params, 'remarks_whole');
}

function remarks_fetch(secs, limit) {
	var params = [];
	params['op'] = 'remarks_fetch';
	// this not being used? -- pudge
	remarks_max = $('remarks_max');
	params['limit'] = limit;
	// run it every 30 seconds; don't need to call again
	ajax_periodic_update(secs, params, 'remarks_table');
}

function remarks_popup() {
	var params = [];
	params['op'] = 'remarks_config';
	var title = "Remarks Config ";
	var buttons = createPopupButtons('<a href="javascript:closePopup(\'remarksconfig-popup\', 1)">[X]</a>');
	title = title + buttons;
	createPopup(getXYForId('remarks_table'), title + buttons, 'remarksconfig');
	ajax_update(params, 'remarksconfig-contents');
	
}

function remarks_config_save() {
	var params = [];
	var reskey = $('remarks_reskey');
	var min_priority = $('remarks_min_priority');
	var limit = $('remarks_limit');
	var filter = $('remarks_filter');
	params['op'] = 'remarks_config_save';
	if (!reskey && !reskey.value) {
		return false;
	} 
	if (min_priority) {
		params['min_priority'] = min_priority.value;
	}
	if (limit) {
		params['limit'] = limit.value;
	}
	if (filter) {
		params['filter'] = filter.value;
	}
	var message = $('remarksconfig-message');
	if (message) {
		message.innerHTML = "Saving...";
	}
	ajax_update(params, 'remarksconfig-message');
}

function admin_slashdbox_fetch(secs) {
	var params = [];
	params['op'] = 'admin_slashdbox';
	ajax_periodic_update(secs, params, "slashdbox-content");
}

function admin_perfbox_fetch(secs) {
	var params = [];
	params['op'] = 'admin_perfbox';
	ajax_periodic_update(secs, params, "performancebox-content");
}

function admin_authorbox_fetch(secs) {
	var params = [];
	params['op'] = 'admin_authorbox';
	ajax_periodic_update(secs, params, "authoractivity-content");
}

function admin_storyadminbox_fetch(secs) {
	var params = [];
	params['op'] = 'admin_storyadminbox';
	ajax_periodic_update(secs, params, "storyadmin-content");
}

function make_spelling_correction(misspelled_word, form_element) {
	var selected_key   = "select_" + form_element + '_' + misspelled_word;
	var selected_index = document.forms.slashstoryform.elements[selected_key].selectedIndex;
	
	if (selected_index == 0) {
		return(0);
	}

	// Either learning a word or making a correction.
	if (selected_index >= 1) {
		if (selected_index == 1) {
			var params = [];
			params['op'] = 'admin_learnword';
			params['word'] = misspelled_word;
			ajax_update(params);
		}
		else {
                        // Try to weed out HREFs and parameters
                        var pattern = misspelled_word + "(?![^<]*>)";
                        var re = new RegExp(pattern, "g");
			var correction = document.forms.slashstoryform.elements[selected_key].value;
			document.forms.slashstoryform.elements[form_element].value =
				document.forms.slashstoryform.elements[form_element].value.replace(re, correction);
		}

		// Remove this row from the table.
		var rowname = misspelled_word + '_' + form_element + '_correction';
		var row = document.getElementById(rowname);
		row.parentNode.removeChild(row);

	}

	// Remove the table if we're done.
	var tablename = "spellcheck_" + form_element;
	var table = document.getElementById(tablename);
	var numrows = table.getElementsByTagName("TR");
	if (numrows.length == 1) {
		table.parentNode.removeChild(table);
	}	
}
