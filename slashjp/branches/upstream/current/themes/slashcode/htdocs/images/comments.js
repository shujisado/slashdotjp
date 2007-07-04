// $Id: comments.js,v 1.79 2007/03/22 02:34:34 pudge Exp $

var comments;
var root_comments;
var noshow_comments;
var pieces_comments;
var abbrev_comments = {};
var init_hiddens = [];
var fetch_comments = [];
var fetch_comments_pieces = {};
var update_comments = {};
var root_comments_hash = {};
var behaviors = {
	'default': { ancestors: 'none', parent: 'none', children: 'none', descendants: 'none', siblings: 'none', sameauthor: 'none' }, 
	'focus': { ancestors: 'none', parent: 'none', children: 'prehidden', descendants: 'prehidden', siblings: 'none', sameauthor: 'none' }, 
	'collapse': { ancestors: 'none', parent: 'none', siblings: 'none', sameauthor: 'none', currentmessage: 'oneline', children: 'hidden', descendants: 'hidden'}
};
var displaymode = {};
var futuredisplaymode = {};
var prehiddendisplaymode = {};
var viewmodevalue = { full: 3, oneline: 2, hidden: 1};
var currents = { full: 0, oneline: 0, hidden: 0 };
var commentelements = {};
var thresh_totals = {};

var boxStatusQueue = [];
var comment_body_reply = [];
var root_comment = 0;
var discussion_id = 0;
var user_is_admin = 0;
var user_is_anon = 0;
var user_uid = 0;
var user_threshold = 0;
var user_highlightthresh = 0;
var user_threshold_orig = -9;
var user_highlightthresh_orig = -9;
var loaded = 0;
var shift_down = 0;
var alt_down = 0;

var agt = navigator.userAgent.toLowerCase();
var is_firefox = (agt.indexOf("firefox") != -1);

/* thread functions */
function updateComment(cid, mode) {
	var existingdiv = fetchEl('comment_' + cid);
	if (existingdiv && mode != displaymode[cid]) {
		var doshort = 0;
		if (viewmodevalue[mode] >= viewmodevalue[displaymode[cid]]) {
			var cl = fetchEl('comment_link_' + cid);
			if (!cl) {
				fetch_comments.push(cid);
				doshort = 1;
			} else if (viewmodevalue[mode] >= viewmodevalue['full']) {
				var cd = fetchEl('comment_otherdetails_' + cid);
				if (!cd.innerHTML) {
					fetch_comments.push(cid);
					fetch_comments_pieces[cid] = 1;
					doshort = 1;
				}
			}
		}
		if (doshort)
			setShortSubject(cid, mode, cl);
		existingdiv.className = mode;
	}

	currents[displaymode[cid]]--;
	currents[mode]++;
	displaymode[cid] = mode;

	return void(0);
}

function updateCommentTree(cid, threshold, subexpand) {
	setDefaultDisplayMode(cid);
	var comment = comments[cid];

	// skip the root comment, if it exists; leave it full, but let user collapse
	// if he chooses, and leave it that way: this comment will not move with
	// T/HT changes
	if ((subexpand || threshold) && cid != root_comment) {
		if (subexpand && subexpand == 1) {
			if (prehiddendisplaymode[cid] == 'oneline' || prehiddendisplaymode[cid] == 'full') {
				futuredisplaymode[cid] = 'full';
			} else {
				futuredisplaymode[cid] = 'hidden';
			}
		} else {
			futuredisplaymode[cid] = determineMode(cid, threshold, user_highlightthresh);
		}

		updateDisplayMode(cid, futuredisplaymode[cid], 1);
	}

//	if (subexpand && subexpand == 2) {
//		updateComment(cid, 'hidden');
//		prehiddendisplaymode[cid] = futuredisplaymode[cid];
//	} else if (futuredisplaymode[cid] && futuredisplaymode[cid] != displaymode[cid]) {
		//updateComment(cid, futuredisplaymode[cid]);
		if (displaymode[cid] != futuredisplaymode[cid]) {
			update_comments[cid] = futuredisplaymode[cid];
		}
//	}

	var kidhiddens = 0;
	if (comment && comment['kids'] && comment['kids'].length) {
		if (!subexpand) {
			if (shift_down && !alt_down && futuredisplaymode[cid] == 'full') {
				subexpand = 1;
			} else if (shift_down && !alt_down && futuredisplaymode[cid] == 'oneline') {
				subexpand = 2;
				threshold = user_threshold;
			}
		}

		for (var kiddie = 0; kiddie < comment['kids'].length; kiddie++) {
			kidhiddens += updateCommentTree(comment['kids'][kiddie], threshold, subexpand);
		}
	}

	return kidHiddens(cid, kidhiddens);
}

function setFocusComment(cid, alone, mods) {
	if (!loaded)
		return false;

	var abscid = Math.abs(cid);
	setDefaultDisplayMode(abscid);
	if ((alone && alone == 2) || (!alone && viewmodevalue[displaymode[abscid]] == viewmodevalue['full']))
		cid = '-' + abscid;

// this doesn't work
//	var statusdiv = $('comment_status_' + abscid);
//	statusdiv.innerHTML = 'Working ...';

//	doModifiers();
//	if (!user_is_admin) // XXX: for now, admins-only, for testing
//		mods = 1;

	if (!alone && mods) {
		if (mods == 1 || ((mods == 3) && (abscid == cid)) || ((mods == 4) && (abscid != cid))) {
			shift_down = 0;
			alt_down   = 0;
		} else if (mods == 2 || ((mods == 3) && (abscid != cid)) || ((mods == 4) && (abscid == cid))) {
			shift_down = 1;
			alt_down   = 0;
		} else if (mods == 5) {
			shift_down = 1;
			alt_down   = 1;
		}
	}

	if (shift_down && alt_down)
		alone = 1;

	if (alone && alone == 1) {
		var thismode = abscid == cid ? 'full' : 'oneline';
		updateDisplayMode(abscid, thismode, 1);
	} else {
		refreshDisplayModes(cid);
	}
	updateCommentTree(abscid);
	finishCommentUpdates();

//	resetModifiers();

//	statusdiv.innerHTML = '';

	if (!commentIsInWindow(abscid)) {
		scrollWindowTo(abscid);
	}

	return false;
}

function changeTHT(t_delta, ht_delta) {
	if (!t_delta && !ht_delta)
		return void(0);

	user_threshold       += t_delta;
	user_highlightthresh += ht_delta;
	// limit to between -1 and 6
	user_threshold       = Math.min(Math.max(user_threshold,       -1), 6);
	user_highlightthresh = Math.min(Math.max(user_highlightthresh, -1), 6);

	// T cannot be higher than HT; this also modifies delta
	if (user_threshold > user_highlightthresh)
		user_threshold = user_highlightthresh;

	changeThreshold(user_threshold + ''); // needs to be a string value
}

function changeHT(delta) {
	if (!delta)
		return void(0);

	user_highlightthresh += delta;
	// limit to between -1 and 6
	user_highlightthresh = Math.min(Math.max(user_highlightthresh, -1), 6);

	// T cannot be higher than HT; this also modifies delta
	if (user_threshold > user_highlightthresh)
		user_threshold = user_highlightthresh;

	changeThreshold(user_threshold + ''); // needs to be a string value
}

function changeT(delta) {
	if (!delta)
		return void(0);

	var threshold = user_threshold + delta;
	// limit to between -1 and 6
	threshold = Math.min(Math.max(threshold, -1), 6);

	// HT moves with T, but that is taken care of by changeThreshold()
	changeThreshold(threshold + ''); // needs to be a string value
}

function changeThreshold(threshold) {
	var threshold_num = parseInt(threshold);
	var t_delta = threshold_num + (user_highlightthresh - user_threshold);
	user_highlightthresh = Math.min(Math.max(t_delta, -1), 6);
	user_threshold = threshold_num;

	if ($('currentHT'))
		$('currentHT').innerHTML = user_highlightthresh;

	if ($('currentT'))
		$('currentT').innerHTML = user_threshold;

	if ($('threshold'))
		$('threshold').value = threshold;

	for (var root = 0; root < root_comments.length; root++) {
		updateCommentTree(root_comments[root], threshold);
	}
	finishCommentUpdates();

	savePrefs();

	return void(0);
}


/* thread kid/hidden functions */
function kidHiddens(cid, kidhiddens) {
	var hiddens_cid = fetchEl('hiddens_' + cid);
	if (! hiddens_cid) // race condition, probably: new comment added in between rendering, and JS data structure
		return 0;

	// silly workaround to hide noscript LI bullet
	var hidestring_cid = fetchEl('hidestring_' + cid);
	if (hidestring_cid)
		hidestring_cid.className = 'hide';

	// may not be changed yet, that's OK
	if (futuredisplaymode[cid] == 'hidden') {
		hiddens_cid.className = 'hide';
		return kidhiddens + 1;
	} else if (kidhiddens) {
		var kidstring = '<a href="javascript:revealKids(' + cid + ')">' + kidhiddens;
		if (kidhiddens == 1) {
			kidstring += ' hidden comment</a>';
		} else {
			kidstring += ' hidden comments</a>';
		}
		hiddens_cid.innerHTML = kidstring; 
		hiddens_cid.className = 'show';
	} else {
		hiddens_cid.className = 'hide';
	} 

	return 0;
}

function revealKids(cid) {
	if (!loaded)
		return false;

	setDefaultDisplayMode(cid);
	var comment = comments[cid];

	if (comment['kids'].length) {
		for (var kiddie = 0; kiddie < comment['kids'].length; kiddie++) {
			var kid = comment['kids'][kiddie];
			setDefaultDisplayMode(kid);
			if (displaymode[kid] == 'hidden') {
				futuredisplaymode[kid] = 'oneline';
				updateDisplayMode(kid, futuredisplaymode[kid], 1);
				updateComment(kid, futuredisplaymode[kid]);
			}
		}
	}

	updateCommentTree(cid);
	finishCommentUpdates();

	return void(0);
}

// update textual hidden counts
function updateHiddens(cids) {
	if (!cids || !cids.length)
		return;

	var seen = {};
	// something wrong here, not always working -- pudge 2007-01-16
	OUTER: for (var i = 0; i < cids.length; i++) {
		var cid = cids[i];
		while (cid && comments[cid] && comments[cid]['pid']) {
			cid = comments[cid]['pid'];
			if (seen[cid])
				continue OUTER;
			seen[cid] = 1;
		}
		updateCommentTree(cid);
	}
}

function selectParent(cid, collapse) {
	if (!loaded)
		return false;

	var comment = comments[cid];
	if (comment && fetchEl('comment_' + cid)) {
		var was_hidden = 0;
		if (displaymode[cid] == 'hidden')
			was_hidden = 1;

		setFocusComment(cid, (collapse ? 2 : 1));

		if (was_hidden)
			updateHiddens([cid]);

		return false;
	} else {
		return true; // follow link
	}
	return false;
}

function setShortSubject(cid, mode, cl) {
	if (!cl)
		cl = fetchEl('comment_link_' + cid);

	// subject is there only if it is a "reply"
	// check pid to make sure parent is there at all ... check visibility too?
	if (cl && cl.innerHTML && comments[cid]['subject'] && comments[cid]['pid']) {
		var thisdiv = fetchEl('comment_' + comments[cid]['pid']);
		if (thisdiv) {
			setDefaultDisplayMode(comments[cid]['pid']);
			if (!mode)
				mode = displaymode[cid];
			if (mode == 'full' || (mode == 'oneline' && displaymode[comments[cid]['pid']] == 'hidden')) {
				cl.innerHTML = comments[cid]['subject'];
			} else if (mode == 'oneline') {
				cl.innerHTML = 'Re:';
			}
		}
	}
}


/* thread utility functions */
function refreshDisplayModes(cid) {
	if (cid > 0) {
		updateDisplayMode(cid, 'full', 1);
		findAffected('focus', cid, 0); 
	} else {
		cid = -1 * cid;
		updateDisplayMode(cid, behaviors['collapse']['currentmessage'], 1);
		findAffected('collapse', cid, 1);
	}

	return void(0);
}

function getDescendants(cids, first) {
	// don't include first round of kids in descendants, redundant
	var descs = first ? [] : cids;

	for (var i = 0; i < cids.length; i++) {
		var cid = cids[i];
		var kids = comments[cid]['kids'];
		if (kids.length)
			descs = descs.concat(getDescendants(kids)); 
	}

	return descs;
}

function faGetSetting(cid, ctype, relation, prevview, canbelower) {
	var newview = behaviors[ctype][relation];
	if (newview == 'none') {
		return prevview;
	} else if (newview == 'prehidden') {
		setDefaultDisplayMode(cid);
		return prehiddendisplaymode[cid];
	}

	if ((viewmodevalue[newview] > viewmodevalue[prevview]) || canbelower) {
		return newview;
	}

	return prevview; 
}

function findAffected(type, cid, override) {
	if (!cid) { return }
	var comment = comments[cid];

	var kids = comment['kids'];
	if (kids.length) {
		for (var i = 0; i < kids.length; i++) {
			var kid = kids[i];
			updateDisplayMode(kid, faGetSetting(kid, type, 'children', futuredisplaymode[kid], override));
		}

		var descendants = getDescendants(kids, 1);
		for (var i = 0; i < descendants.length; i++) {
			var desc = descendants[i];
			var thistype = type;
			updateDisplayMode(desc, faGetSetting(desc, thistype, 'descendants', futuredisplaymode[desc], override));
		}
	}
}

function setDefaultDisplayMode(cid) {
	if (displaymode[cid]) { return }

	var comment = fetchEl('comment_' + cid);
	if (!comment) { return }

	var defmode = comment.className;
	if (!defmode) { return }

	futuredisplaymode[cid] = prehiddendisplaymode[cid] = displaymode[cid] = defmode;
}

function updateDisplayMode(cid, mode, newdefault) {
	if (!mode) { return }

	setDefaultDisplayMode(cid);
	futuredisplaymode[cid] = mode;
	if (newdefault)
		prehiddendisplaymode[cid] = mode;
}

// don't want to actually use this -- pudge
function calcTotals() {
	var currentFull = 0;
	var currentOneline = 0;

	for (var mode in currents) {
		if (currents[mode])
			currents[mode] = 0;
	}

	for (var cid in comments) {
		setDefaultDisplayMode(cid);
		currents[displaymode[cid]]++;
	}
}

function getSliderTotals(thresh, hthresh) {
	// we are precalculating, so this code should never be used!
	// here for testing -- pudge
/*	if (!thresh_totals[thresh] || !thresh_totals[thresh][hthresh]) {
		if (!thresh_totals[thresh])
			thresh_totals[thresh]  = {};
		thresh_totals[thresh][hthresh] = {};
		thresh_totals[thresh][hthresh][ viewmodevalue['hidden']]  = 0;
		thresh_totals[thresh][hthresh][ viewmodevalue['oneline']] = 0;
		thresh_totals[thresh][hthresh][ viewmodevalue['full']]    = 0;

		for (var cid in comments) {
			var mode = determineMode(cid, thresh, hthresh);
			thresh_totals[thresh][hthresh][ viewmodevalue[mode] ]++;
		}
	}
*/

	return [
		thresh_totals[thresh][hthresh][viewmodevalue['hidden']],
		thresh_totals[thresh][hthresh][viewmodevalue['oneline']],
		thresh_totals[thresh][hthresh][viewmodevalue['full']]
	];
}

function determineMode(cid, thresh, hthresh) {
	if (!hthresh)
		hthresh = user_highlightthresh;

	if (thresh >= 6 || (comments[cid]['points'] < thresh && (user_is_anon || user_uid != comments[cid]['uid'])))
		return 'hidden';
	else if (comments[cid]['points'] < (hthresh - (root_comments_hash[cid] ? 1 : 0)))
		return 'oneline';
	else
		return 'full';
}

function finishCommentUpdates() {
	for (var cid in update_comments) {
		updateComment(cid, update_comments[cid]);
	}

	ajaxFetchComments(fetch_comments);

	updateTotals();
	update_comments = {};
	fetch_comments = [];
	fetch_comments_pieces = {};
}

// not currently used
function refreshCommentDisplays() {
	var roothiddens = 0;
	for (var root = 0; root < root_comments.length; root++) {
		roothiddens += updateCommentTree(root_comments[root]);
	}
	finishCommentUpdates();

	if (roothiddens) {
		$('roothiddens').innerHTML = roothiddens + ' comments are beneath your threshhold';
		$('roothiddens').className = 'show';
	} else {
		$('roothiddens').className = 'hide';
	}
	/* NOTE need to display note for hidden root comments */
	return void(0);
}

/* misc. functions */
function toHash(thisobject) {
	return thisobject.map(function (pair) {
		return pair.map(encodeURIComponent).join(',');
	}).join(';');
}

function ajaxFetchComments(cids) {
	if (cids && !cids.length)
		return;

	var params = [];
	params['op']            = 'comments_fetch';
	params['cids']          = (cids || noshow_comments);
	params['cid']           = root_comment;
	params['discussion_id'] = discussion_id;
	params['reskey']        = reskey_static;

	var abbrev = {};
	for (var i = 0; i < cids.length; i++) {
		if (abbrev_comments[cids[i]] >= 0)
			abbrev[cids[i]] = abbrev_comments[cids[i]];
	}
	params['abbreviated'] = $H(abbrev);
	params['abbreviated'] = toHash(params['abbreviated']);

	params['pieces'] = $H(cids ? fetch_comments_pieces : pieces_comments);
	params['pieces'] = toHash(params['pieces']);

	var handlers = {
		onComplete: function (transport) {
			var response = eval_response(transport);
			json_update(response);
			updateHiddens(cids);
			for (var i = 0; i < cids.length; i++) {
				// this is needed for Firefox
				// better way to do automatically?
				if (is_firefox) {
					loadNamedElement('comment_link_' + cids[i]);
					loadNamedElement('comment_shrunk_' + cids[i]);
					loadNamedElement('comment_sig_' + cids[i]);
					loadNamedElement('comment_otherdetails_' + cids[i]);
					loadNamedElement('comment_sub_' + cids[i]);
				}
				setShortSubject(cids[i]);
			}
			boxStatus(0);
		}
	};

	boxStatus(1);
	ajax_update(params, '', handlers);

	if (cids) {
		for (var cid in fetch_comments_pieces) {
			pieces_comments[cid] = 0;
		}

		var remove = [];
		for (var i = 0; i < cids.length; i++) {
			// no Array.indexOf in Safari etc.
			for (var j = 0; j < noshow_comments.length; j++) {
				if (cids[i] == noshow_comments[j]) {
					remove.push(j);
				}
			}
		}
		for (var i = 0; i < remove.length; i++) {
			noshow_comments.splice(remove[i], 1, 0);
		}

		// remove zeroes added above
		for (var i = (noshow_comments.length-1); i >= 0; i--) {
			if (noshow_comments[i] == 0)
				noshow_comments.splice(i, 1);
		}

	} else {
		noshow_comments = [];
		pieces_comments = [];
	}

	return false;
}

function savePrefs() {
	if ((user_threshold_orig != user_threshold)
		||
	    (user_highlightthresh_orig != user_highlightthresh)
	) {
		var params = [];
		params['op'] = 'comments_set_prefs';
		params['threshold'] = user_threshold;
		params['highlightthresh'] = user_highlightthresh;
		params['reskey'] = reskey_static;
		ajax_update(params);

		user_threshold_orig = user_threshold;
		user_highlightthresh_orig = user_highlightthresh;
	}

	return false;
}

function readRest(cid) {
	var shrunkdiv = fetchEl('comment_shrunk_' + cid);
	if (!shrunkdiv)
		return false; // seems we shouldn't be here ...

	var params = [];
	params['op']  = 'comments_read_rest';
	params['cid'] = cid;
	params['sid'] = discussion_id;

	var handlers = {
		onComplete: function() {
			shrunkdiv.innerHTML = '';
			var sigdiv = fetchEl('comment_sig_' + cid);
			if (sigdiv) {
				sigdiv.className = 'sig'; // show
			}
		}
	};

	shrunkdiv.innerHTML = 'Loading...';
	ajax_update(params, 'comment_body_' + cid, handlers);

	return false;
}

function doModerate(el) {
	var matches = el.name.match(/_(\d+)$/);
	var cid = matches[1];

	if (!cid)
		return true;

	el.disabled = 'true';
	var params = [];
	params['op']  = 'comments_moderate_cid';
	params['cid'] = cid;
	params['sid'] = discussion_id;
	params['msgdiv'] = 'reasondiv_' + cid;
	params['reason'] = el.value;
	params['reskey'] = reskey_static;

	var handlers = {
		onComplete: json_handler
	};

	ajax_update(params, '', handlers);

	return false;
}

// not used yet
function replyTo(cid) {
	var replydiv = fetchEl('replyto_' + cid);

	replydiv.innerHTML = '';

	return false;
}

function quoteReply(pid) {
	var this_reply = comment_body_reply[pid];

	// tailor whitespace to postmode
	if ($('posttype').value != 2) {
		this_reply = this_reply.replace(/<br>/g, "\n");
	} else {
		this_reply = this_reply.replace(/<br>\n*/g, "<br>\n");
		this_reply = this_reply.replace(/\n*<p>/g, "\n\n<p>");
		this_reply = this_reply.replace(/<\/p>\n*/g, "</p>\n\n");
		this_reply = this_reply.replace(/<\/p>\n\n\n*<p>/g, "</p>\n\n<p>");
	}
	// <quote> parse code takes care of whitespace
	this_reply = this_reply.replace(/\n*<quote>/g, "\n\n<quote>");
	this_reply = this_reply.replace(/^\n+/g, "");
	this_reply = this_reply.replace(/<\/quote>\n*/g, "</quote>\n\n");

	$('postercomment').value = this_reply + $('postercomment').value;
}

/* utility functions */
function loadAllElements(tagname) {
	var elements = document.getElementsByTagName(tagname);

	for (var i = 0; i < elements.length; i++) {
		var e = elements[i];
		commentelements[e.id] = e;
	}

	return;
}

function loadNamedElement(name) {
	commentelements[name] = $(name);
	return;
}

function fetchEl(str) {
/* 	if (!loaded || !is_firefox) { */
/* 		return $(str); */
/*  */
/* 	if (commentelements[str]) { */
/* 		commentelements[str] = loadNamedElement(str); */
/* 		return commentelements[str]; */
/* 	} */

	return loaded
		? (is_firefox ? commentelements[str] : $(str))
		: $(str);
}

function finishLoading() {
	if (is_firefox) {
		loadAllElements('span');
		loadAllElements('div');
		loadAllElements('li');
		loadAllElements('a');
	}

	if (root_comment)
		currents['full'] += 1;

	for (var i = 0; i < root_comments.length; i++) {
		root_comments_hash[ root_comments[i] ] = 1;
	}

	if (user_threshold_orig == -9 || user_highlightthresh_orig == -9) {
		user_threshold_orig = user_threshold;
		user_highlightthresh_orig = user_highlightthresh;
	}

	updateHiddens(init_hiddens);

	//window.onbeforeunload = function () { savePrefs() };
	//window.onunload = function () { savePrefs() };

	updateTotals();
	enableControls();

	//setTimeout('ajaxFetchComments()', 10*1000);
}

function cloneObject(what) {
	for (i in what) {
		if (typeof what[i] == 'object') {
			this[i] = new cloneObject(what[i]);
		} else {
			this[i] = what[i];
		}
	}
}


/* UI functions */
function resetModifiers () {
	shift_down = 0;
	alt_down   = 0;
}

function doModifiers () {
	return;
	var ev = window.event;
	shift_down = 0;
	alt_down   = 0;

	if (ev) {
		if (ev.modifiers) {
			if (e.modifiers & Event.SHIFT_MASK)
				shift_down = 1;
			if (e.modifiers & Event.ALT_MASK)
				alt_down = 1;
		} else {
			if (ev.shiftKey)
				shift_down = 1;
			if (ev.altKey)
				alt_down = 1;
		}
	}
}

function boxStatus(bool) {
	var box = $('commentControlBoxStatus');
	if (bool) {
		boxStatusQueue.push(1);
		box.className = '';
	} else {
		boxStatusQueue.shift();
		if (!boxStatusQueue.length)
			box.className = 'hide';
	}
}

function enableControls() {
	boxStatus(0);
	d2act();
	loaded = 1;
}

function floatButtons () {
	$('gods').className='thor';
}

function d2act () {
	var gd = $('d2act'); 
	if (gd) {
		var targetTop = YAHOO.util.Dom.getY('commentwrap');
		var vOffset = 0;
		if ( typeof window.pageYOffset == 'number' )
			vOffset = window.pageYOffset;
		else if ( document.body && document.body.scrollTop )
			vOffset = document.body.scrollTop;
		else if ( document.documentElement && document.documentElement.scrollTop )
			vOffset = document.documentElement.scrollTop;
  
		var oldpos = gd.style.position;

		var mode = $('d2out').className;
		if (mode=='horizontal rooted' || targetTop>vOffset) {
			gd.style.position = 'absolute';
			gd.className      = 'rooted';
			gd.style.top      = '0px';
		} else {
			gd.style.position = 'fixed';
			gd.className      = '';
			gd.style.top      = '0px';
		}

		// for Safari and maybe others, force redraw on change
		if ( oldpos != gd.style.position ) {
			gd.style.display = 'none';
			setTimeout("$('d2act').style.display = 'inline'", 1);
			// gd.style.display = 'inline';
		}
	}
}

function toggleDisplayOptions() {
	var gods  = $('gods');
	var d2out = $('d2out');

	// update user prefs
	var newMode = '';

	var isHidden = gods.style.display == 'none';
	gods.style.display = 'none';

	// none -> ( vertical -> horizontal -> rooted )
	if ( d2out.className == 'vertical' ) { // vertical->horizontal
		newMode = d2out.className = 'horizontal';
		gCommentControlWidget.setOrientation('X');
	} else if ( d2out.className == 'horizontal' ) { // horizontal->rooted
		newMode = 'rooted';
		d2out.className = 'horizontal rooted';
	} else { // (rooted, none)->vertical
		newMode = d2out.className = 'vertical';
		gCommentControlWidget.setOrientation('Y');
	}

	d2act();
	gods.style.display = 'block';


	var params = [];
	params['comments_control'] = newMode;
	params['op'] = 'comments_set_prefs';
	params['reskey'] = reskey_static;
	ajax_update(params);

	return false;
}


function updateTotals() {
	$('currentHidden' ).innerHTML = currents['hidden'];
	$('currentFull'   ).innerHTML = currents['full'];
	$('currentOneline').innerHTML = currents['oneline'];
}

function scrollWindowTo(cid) {
	var comment_y = getOffsetTop(fetchEl('comment_' + cid));
	if ($('d2out').className == 'horizontal')
		comment_y -= 60;
	scroll(viewWindowLeft(), comment_y);
}

function getOffsetLeft (el) {
	var ol = el.offsetLeft;
	while ((el = el.offsetParent) != null)
		ol += el.offsetLeft;
	return ol;
}

function getOffsetTop (el) {
	var ot = el.offsetTop;
	while((el = el.offsetParent) != null)
		ot += el.offsetTop;
	return ot;
}

function viewWindowLeft() {
	if (self.pageXOffset) // all except Explorer
	{
		return self.pageXOffset;
	}
	else if (document.documentElement && document.documentElement.scrollTop)
		// Explorer 6 Strict
	{
		return document.documentElement.scrollLeft;
	}
	else if (document.body) // all other Explorers
	{
		return document.body.scrollLeft;
	}
}

function viewWindowTop() {
	if (self.pageYOffset) // all except Explorer
	{
		return self.pageYOffset;
	}
	else if (document.documentElement && document.documentElement.scrollTop)
		// Explorer 6 Strict
	{
		return document.documentElement.scrollTop;
	}
	else if (document.body) // all other Explorers
	{
		return document.body.scrollTop;
	}
	return;
}

function viewWindowRight() {
	return viewWindowLeft() + (window.innerWidth || document.documentElement.clientWidth);
}

function viewWindowBottom() {
	return viewWindowTop() + (window.innerHeight || document.documentElement.clientHeight);
}

function commentIsInWindow(cid) {
	return isInWindow(fetchEl('comment_' + cid));
}

function isInWindow(obj) {
	var y = getOffsetTop(obj);

	if (y > viewWindowTop() && y < viewWindowBottom()) {
		return 1;
	}
	return 0;
}


/* code for the draggable threshold widget */

function showPrefs( category ) {
	var panel = document.getElementById("d2prefs");
	panel.className = category;
	panel.style.display = "block";
}

function hidePrefs() {
	var panel = document.getElementById("d2prefs");
	panel.className = "";
	panel.style.display = "none";
}

function partitionedRange( range, partitions ) {
	return [].concat(range[0], partitions, range[1]);
}

function pinToRange( range, partitions ) {
	var result = partitions.slice();
	var hi = range[0], lo = range[1];

	function pin( x ) {
		return hi = Math.min(Math.max(x, lo), hi);
	}

	for ( var i=0; i<partitions.length; ++i )
		result[i] = pin(partitions[i]);

	return result;
}

function boundsToDimensions( bounds, scaleFactor ) {
	if ( scaleFactor === undefined )
		scaleFactor = 1;

	var sizes = new Array(bounds.length-1);
	for ( var i=0; i<sizes.length; ++i )
		sizes[i] = { size: Math.abs(bounds[i+1]-bounds[i]) * scaleFactor };

	var left = 0;
	var right = 0;

	for ( var L=0, R=sizes.length-1; R>=0; ++L, --R ) {
		sizes[L].start = left; left += sizes[L].size;
		sizes[R].stop = right; right += sizes[R].size;
	}

	return sizes;
}

Y_UNITS_IN_PIXELS = 20;

ABBR_BAR = 0;
HIDE_BAR = 1;


YAHOO.namespace("slashdot");

YAHOO.slashdot.ThresholdWidget = function( initialOrientation ) {
	this.PANEL_KINDS = [ "full", "abbr", "hide" ];
	this.displayRange = [6, -1];
	this.constraintRange = [6, -1];
	this.getEl_cache = new Object();

	this.orientations = new Object();
	this.orientations["Y"] = { axis:"Y", startPos:"top", endPos:"bottom", getPos:YAHOO.util.Dom.getY, units:"px", scale:Y_UNITS_IN_PIXELS };
	this.orientations["X"] = { axis:"X", startPos:"left", endPos:"right", getPos:YAHOO.util.Dom.getX, units:"%", scale:(100.0 / (this.displayRange[0]-this.displayRange[1])) };
	this.orientations["X"].other = this.orientations["Y"];
	this.orientations["Y"].other = this.orientations["X"];

	if ( initialOrientation === undefined )
		initialOrientation = "Y";
	this.orient = this.orientations[initialOrientation];

	function initBar( id, whichBar, parentWidget ) {
		id = "ccw-"+id+"-bar";

		var el = YAHOO.util.Dom.get(id+"-pos");

		var dd = new YAHOO.slashdot.ThresholdBar(el, "ccw", {scroll:false});
		dd.setOuterHandleElId(id+"-tab");
		dd.setHandleElId(id);
		dd.whichBar = whichBar;
		dd.parentWidget = parentWidget;

		return dd;
	}

	var abbrBar = initBar("abbr", ABBR_BAR, this);
	var hideBar = initBar("hide", HIDE_BAR, this);

	this.dragBars = [ abbrBar, hideBar ];
}

YAHOO.slashdot.ThresholdWidget.prototype = new Object();

YAHOO.slashdot.ThresholdWidget.prototype._getEl = function( id ) {
	var el = this.getEl_cache[id];
	if ( el === undefined )
		el = this.getEl_cache[id] = YAHOO.util.Dom.get(id);
	return el;
}

YAHOO.slashdot.ThresholdWidget.prototype.setTHT = function( T, HT ) {
	this._setTs(pinToRange(this.constraintRange, [HT, T]));
}

YAHOO.slashdot.ThresholdWidget.prototype.getTHT = function() {
	return this.displayedTs.slice().reverse();
}

YAHOO.slashdot.ThresholdWidget.prototype.setCounts = function( counts ) {
	// counts is an array: [ num-hidden, num-abbreviated, num-full ]
	if ( counts === undefined )
		counts = this._requestCounts();

	this._getEl("currentHidden").innerHTML = counts[0];
	this._getEl("currentOneline").innerHTML = counts[1];
	this._getEl("currentFull").innerHTML = counts[2];
}


YAHOO.slashdot.ThresholdWidget.prototype._requestCounts = function() {
	return getSliderTotals(this.displayedTs[HIDE_BAR], this.displayedTs[ABBR_BAR]);
}

YAHOO.slashdot.ThresholdWidget.prototype._onBarStartDrag = function( whichBar ) {
	YAHOO.util.Dom.addClass(this._getEl("ccw-control"), "ccw-active");
	this.preDragTs = this.displayedTs.slice();
}

YAHOO.slashdot.ThresholdWidget.prototype._onBarEndDrag = function( whichBar ) {
	YAHOO.util.Dom.removeClass(this._getEl("ccw-control"), "ccw-active");

	var deltas = this.displayedTs.slice();
	for ( var i=0; i<deltas.length; ++i )
		deltas[i] -= this.preDragTs[i];

	changeTHT(deltas[HIDE_BAR], deltas[ABBR_BAR]);
}

YAHOO.slashdot.ThresholdWidget.prototype.setOrientation = function( newAxis ) {
	if ( newAxis != this.orient.axis ) {
		var o = this.orient = this.orientations[newAxis];
		for ( var i=0; i<this.PANEL_KINDS.length; ++i ) {
			var prefix = "ccw-"+this.PANEL_KINDS[i];
			var panel = this._getEl(prefix+"-panel").style;
			if ( i != 0 ) panel[ o.other.startPos ] = 0;
			if ( i != this.PANEL_KINDS.length-1 ) panel[ o.other.endPos ] = 0;

			this._getEl(prefix+"-phrase").style.display = "inline";
			this._getEl(prefix+"-count-pos").style.top = 0;
		}
		this._setTs();
	}
}

YAHOO.slashdot.ThresholdWidget.prototype._scaleToPixels = function() {
	return this._getEl("ccw-control").scrollWidth / 100.0;
}

YAHOO.slashdot.ThresholdWidget.prototype._setTs = function( newTs, draggingBar ) {
	var w = this;
	var o = w.orient;

	function fixPanel( id, newDims ) {
		var prefix = "ccw-"+id;
		var countText = w._getEl(prefix+"-count-text").style;
		if ( newDims.size == 0 )
			countText.display = "none";
		else {
			countText.display = "block";
			if ( o.axis == "Y" )
				w._getEl(prefix+"-count-pos").style.top = (newDims.size/2) + o.units;
			else
				w._getEl(prefix+"-phrase").style.display = (newDims.size>o.scale) ? "inline" : "none";
		}

		var panel = w._getEl(prefix+"-panel").style;
		if ( newDims.start !== undefined ) panel[ o.startPos ] = newDims.start + o.units;
		if ( newDims.stop !== undefined ) panel[ o.endPos ] = newDims.stop + o.units;
	}

	if ( newTs === undefined )
		newTs = this.displayedTs;

	if ( draggingBar !== undefined ) {
		var pin = draggingBar==ABBR_BAR ? Math.min : Math.max;
		var other = 1-draggingBar;
		newTs[other] = pin(newTs[draggingBar], this.preDragTs[other]);
	}
	this.displayedTs = newTs;

	for ( i=ABBR_BAR; i<=HIDE_BAR; ++i )
		if ( i != draggingBar )
			this.dragBars[i].setPosFromT(newTs[i]);

	var dims = boundsToDimensions(partitionedRange(this.displayRange, newTs), o.scale);
	delete dims[0].start;
	delete dims[ dims.length-1 ].stop;

	for ( var i=0; i<this.PANEL_KINDS.length; ++i )
		fixPanel(this.PANEL_KINDS[i], dims[i]);

	this.setCounts(this._requestCounts());
    	return newTs;
}




YAHOO.slashdot.ThresholdBar = function( barElId, sGroup, config ) {
	if ( barElId )
		this.init(barElId, sGroup, config);
}

YAHOO.extend(YAHOO.slashdot.ThresholdBar, YAHOO.util.DD);

YAHOO.slashdot.ThresholdBar.prototype.posToT = function( pos ) {
	var el = this.getEl();
	if ( el.style.display != "block" )
		return null;

	var w = this.parentWidget;
	var o = w.orient;
	var widgetStart = o.getPos(w._getEl("ccw-control"));

	if ( pos === undefined )
	  pos = o.getPos(el);

	var scale = o.scale;
	if ( o.units != "px" )
		scale *= w._scaleToPixels();
	return w.displayRange[0] - Math.round((pos - widgetStart) / scale);
}

YAHOO.slashdot.ThresholdBar.prototype.setPosFromT = function( x ) {
	if ( this.posToT() != x ) {
		var w = this.parentWidget;
		var o = w.orient;
		var elStyle = this.getEl().style;
		elStyle[ o.startPos ] = ((w.displayRange[0]-x) * o.scale) + o.units;
		elStyle[ o.other.startPos ] = 0;
		elStyle.display = "block";
	}
}

YAHOO.slashdot.ThresholdBar.prototype.fixConstraints = function() {
	var w = this.parentWidget;
	var o = w.orient;

	var scale = o.scale;
	if ( o.units != "px" )
		scale *= w._scaleToPixels();

	this.resetConstraints();
	this[ "set" + o.other.axis + "Constraint" ](0, 0);

	var thisT = this.draggingTs[this.whichBar];
	var availableSpace = boundsToDimensions(partitionedRange(w.constraintRange, [thisT]), scale);
	this[ "set" + o.axis + "Constraint" ](availableSpace[0].size+1, availableSpace[1].size+1, scale);
}

YAHOO.slashdot.ThresholdBar.prototype.startDrag = function( x, y ) {
	var w = this.parentWidget;
	w._onBarStartDrag(this.whichBar);
	this.draggingTs = w.displayedTs.slice();
	this.fixConstraints();
}

YAHOO.slashdot.ThresholdBar.prototype.onDrag = function( e ) {
	var newT = this.posToT();
	if ( this.draggingTs[this.whichBar] != newT ) {
		this.draggingTs[this.whichBar] = newT;
		this.draggingTs = this.parentWidget._setTs(this.draggingTs, this.whichBar);
	}
}

YAHOO.slashdot.ThresholdBar.prototype.endDrag = function( e ) {
	this.parentWidget._onBarEndDrag(this.whichBar);
}

YAHOO.slashdot.ThresholdBar.prototype.alignElWithMouse = function( el, iPageX, iPageY ) {
	var w = this.parentWidget;
	var o = w.orient;

	var oCoord = this.getTargetCoord(iPageX, iPageY);
	var newThreshold = this.posToT( oCoord[ o.axis.toLowerCase() ] );
	this.setPosFromT(newThreshold);

	var newPos = YAHOO.util.Dom.getXY(el);
	oCoord = { x:newPos[0], y:newPos[1] };

	this.cachePosition(oCoord.x, oCoord.y);
	this.autoScroll(oCoord.x, oCoord.y, el.offsetHeight, el.offsetWidth);
}
