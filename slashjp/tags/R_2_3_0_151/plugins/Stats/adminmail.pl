#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2004 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use Slash::Constants qw( :messages :slashd );
use Slash::Display;

use vars qw( %task $me );

# Remember that timespec goes by the database's time, which should be
# GMT if you installed everything correctly.  So 6:07 AM GMT is a good
# sort of midnightish time for the Western Hemisphere.  Adjust for
# your audience and admins.
$task{$me}{timespec} = '50 6 * * *';
$task{$me}{timespec_panic_2} = ''; # if major panic, dailyStuff can wait
$task{$me}{resource_locks} = { log_slave => 1 };
$task{$me}{fork} = SLASHD_NOWAIT;
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;
	my(%data, %mod_data);
	
	# These are the ops (aka pages) that we scan for.
	my @PAGES = qw|index article search comments palm journal rss page users|;
	push @PAGES, @{$constants->{op_extras_countdaily}};
	$data{extra_pagetypes} = [ @{$constants->{op_extras_countdaily}} ];

	my $days_back;
	if (defined $constants->{task_options}{days_back}) {
		$days_back = $constants->{task_options}{days_back};
	} else {
		$days_back = 1;
	}
	my @yesttime = localtime(time-86400*$days_back);
	my $yesterday = sprintf "%4d-%02d-%02d", 
		$yesttime[5] + 1900, $yesttime[4] + 1, $yesttime[3];
	
	my $overwrite = 0;
	$overwrite = 1 if $constants->{task_options}{overwrite};

	# If overwrite is set to 1, we delete any stats which may have
	# been written by an earlier run of this task.
	my $statsSave = getObject('Slash::Stats::Writer',
		{ nocache => 1 }, { day => $yesterday, overwrite => $overwrite });

	my $stats = getObject('Slash::Stats', { db_type => 'reader' });
	my $backupdb = getObject('Slash::DB', { db_type => 'reader' });

	my $logdb = getObject('Slash::Stats', {
		db_type	=> 'log_slave',
		nocache		=> 1,
	}, {
		day		=> $yesterday,
		create		=> 1
	});

	unless ($logdb) {
		slashdLog('No database to run adminmail against');
		return;
	}

	slashdLog("Send Admin Mail Begin for $yesterday");

	# figure out all the days we want to set average story commentcounts for
	my $cc_days = $stats->getDaysOfUnarchivedStories();

	# compute dates for the last 3 days so we can get the
	# average hits per story for each in the e-mail	
	
	# we use this array to figure out what comment count
	# days we put in the the stats e-mail too

	my @ah_days = ($yesterday);
	for my $db (1, 2) {
		my @day = localtime(time-86400*($days_back+$db));
		my $day = sprintf "%4d-%02d-%02d",
        	        $day[5] + 1900, $day[4] + 1, $day[3];
		push @ah_days, $day;
	}
	
	
	# let's do the errors
	slashdLog("Counting Error Pages Begin");
	$data{not_found} = $logdb->countByStatus("404");
	$statsSave->createStatDaily("not_found", $data{not_found});
	$data{status_202} = $logdb->countByStatus("202");
	$statsSave->createStatDaily("status_202", $data{status_202});

	my $errors = $logdb->getErrorStatuses();
	my $error_count = $logdb->countErrorStatuses();
	$data{error_count} = $error_count;
	$statsSave->createStatDaily("error_count", $data{error_count});
	$data{errors} = {};
	for my $type (@$errors) {
		$data{errors}{$type->{op}} = $type->{count};
		$statsSave->createStatDaily("error_$type->{op}}", $type->{count});
	}
	slashdLog("Counting Error Pages End");

	my $articles = $logdb->countDailyStoriesAccess();

	my $admin_clearpass_warning = '';
	if ($constants->{admin_check_clearpass}) {
		my $clear_admins = $stats->getAdminsClearpass();
		if ($clear_admins and keys %$clear_admins) {
			for my $admin (sort keys %$clear_admins) {
				$admin_clearpass_warning .=
					"$admin $clear_admins->{$admin}{value}\n";
			}
		}
		if ($admin_clearpass_warning) {
			$admin_clearpass_warning = <<EOT;


WARNING: The following admins accessed the site with their passwords,
in cookies, sent in the clear.  They have been told to change their
passwords but have not, as of the generation of this email.  They
need to do so immediately.

$admin_clearpass_warning
EOT
		}
	}

	# depending on the options you pass these you can show the top N offenders in each category, 
	# the top N offenders above the threshold or all offenders above the defined threshold.
	# Right now we show up to 10 but only if they're above the designated thresholds 

	my $bp_ip     = $stats->getTopBadPasswordsByIP(
		{ limit => 10, min => $constants->{bad_password_warn_ip}     || 0 });
	my $bp_subnet = $stats->getTopBadPasswordsBySubnet(
		{ limit => 10, min => $constants->{bad_password_warn_subnet} || 0 });
	my $bp_uid    = $stats->getTopBadPasswordsByUID(
		{ limit => 10, min => $constants->{bad_password_warn_uid}    || 0 });
	my $bp_warning;

	if (@$bp_ip or @$bp_subnet or @$bp_uid) {
		$bp_warning .= "Bad password attempts\n\n";
		if (@$bp_uid) {
			$bp_warning .= "UID      Username                         Attempts\n";
			$bp_warning .= sprintf("%-8s %-32s   %6s\n",
				$_->{uid}, $_->{nickname}, $_->{count}
			) foreach @$bp_uid;
			$bp_warning .= "\n";
		}
		if (@$bp_ip) {
			$bp_warning .= "IP               Attempts\n";
			$bp_warning .= sprintf("%-15s  %8s\n",
				$_->{ip}, $_->{count}
			) foreach @$bp_ip;
			$bp_warning .= "\n";
		}
		if (@$bp_subnet) {
			$bp_warning .= "Subnet           Attempts\n";
			$bp_warning .= sprintf("%-15s  %8s\n",
				$_->{subnet}, $_->{count}
			) foreach @$bp_subnet;
			$bp_warning .= "\n";
		}
	}
	$data{bad_password_warning} = $bp_warning;

	slashdLog("Moderation Stats Begin");
	my $comments = $stats->countCommentsDaily();
	my $accesslog_rows = $logdb->sqlCount('accesslog');
	my $formkeys_rows = $stats->sqlCount('formkeys');

	slashdLog("countModeratorLog Begin");
	my $modlogs = $stats->countModeratorLog({
		active_only	=> 1,
	});
	my $modlogs_yest = $stats->countModeratorLog({
		active_only	=> 1,
		oneday_only	=> 1,
	});
	my $modlogs_needmeta = $stats->countModeratorLog({
		active_only	=> 1,
		m2able_only	=> 1,
	});
	my $modlogs_needmeta_yest = $stats->countModeratorLog({
		active_only	=> 1,
		oneday_only	=> 1,
		m2able_only	=> 1,
	});
	my $modlogs_incl_inactive = $stats->countModeratorLog();
	my $modlogs_incl_inactive_yest = $stats->countModeratorLog({
		oneday_only     => 1,
	});
	my $modlog_inactive_percent =
		($modlogs_incl_inactive - $modlogs)
		? ($modlogs_incl_inactive - $modlogs)*100 / $modlogs_incl_inactive
		: 0;
	my $modlog_inactive_percent_yest =
		($modlogs_incl_inactive_yest - $modlogs_yest)
		? ($modlogs_incl_inactive_yest - $modlogs_yest)*100 / $modlogs_incl_inactive_yest
		: 0;

	slashdLog("countModeratorLog End");
	slashdLog("countMetamodLog Begin");
	my $metamodlogs = $stats->countMetamodLog({
		active_only	=> 1,
	});
	my $unm2dmods = $stats->countUnmetamoddedMods({
		active_only	=> 1,
	});
	my $metamodlogs_yest_fair = $stats->countMetamodLog({
		active_only	=> 1,
		oneday_only	=> 1,
		val		=> 1,
	});
	my $metamodlogs_yest_unfair = $stats->countMetamodLog({
		active_only	=> 1,
		oneday_only	=> 1,
		val		=> -1,
	});
	my $metamodlogs_yest_total = $metamodlogs_yest_fair + $metamodlogs_yest_unfair;
	my $metamodlogs_incl_inactive = $stats->countMetamodLog();
	my $metamodlogs_incl_inactive_yest = $stats->countMetamodLog({
		oneday_only     => 1,
	});
	my $metamodlog_inactive_percent =
		($metamodlogs_incl_inactive - $metamodlogs)
		? ($metamodlogs_incl_inactive - $metamodlogs)*100 / $metamodlogs_incl_inactive
		: 0;
	my $metamodlog_inactive_percent_yest =
		($metamodlogs_incl_inactive_yest - $metamodlogs_yest_total)
		? ($metamodlogs_incl_inactive_yest - $metamodlogs_yest_total)*100 / $metamodlogs_incl_inactive_yest
		: 0;
	slashdLog("countMetamodLog End");

	my $oldest_unm2d = $stats->getOldestUnm2dMod();
	my $oldest_unm2d_days = sprintf("%10.1f", $oldest_unm2d ? (time-$oldest_unm2d)/86400 : -1);
	my $youngest_modelig_uid = $stats->getYoungestEligibleModerator();
	my $youngest_modelig_created = $stats->getUser($youngest_modelig_uid,
		'created_at');

	slashdLog("Points and Token Pool Begin");
	my $mod_points_pool = $stats->getPointsInPool();
	my $mod_tokens_pool_pos = $stats->getTokensInPoolPos();
	my $mod_tokens_pool_neg = $stats->getTokensInPoolNeg();
	slashdLog("Points and Token Pool End");
	
	my $used = $stats->countModeratorLog();
	my $modlog_yest_hr = $stats->countModeratorLogByVal();
	slashdLog("Comment Posting Stats Begin");
	my $distinct_comment_ipids = $stats->getCommentsByDistinctIPID();
	my($distinct_comment_ipids_anononly,
	   $distinct_comment_ipids_loggedinonly,
	   $distinct_comment_ipids_anonandloggedin,
	   $comments_ipids_anononly,
	   $comments_ipids_loggedinonly,
	   $comments_ipids_anonandloggedin) = $stats->countCommentsByDistinctIPIDPerAnon();
	my $comments_proxyanon = $stats->countCommentsFromProxyAnon();
	my $distinct_comment_posters_uids = $stats->getCommentsByDistinctUIDPosters();
	my $comments_discussiontype_hr = $stats->countCommentsByDiscussionType();
	slashdLog("Comment Posting Stats End");
	slashdLog("Submissions Stats Begin");
	my $submissions = $stats->countSubmissionsByDay();
	my $submissions_comments_match = $stats->countSubmissionsByCommentIPID($distinct_comment_ipids);
	slashdLog("Submissions Stats End");
	my $modlog_count_yest_total = $modlog_yest_hr->{1}{count} + $modlog_yest_hr->{-1}{count};
	my $modlog_spent_yest_total = $modlog_yest_hr->{1}{spent} + $modlog_yest_hr->{-1}{spent};
	my $consensus = $constants->{m2_consensus};
	slashdLog("Misc Moderation Stats Begin");
	my $token_conversion_point = $stats->getTokenConversionPoint();

	my $oldest_to_show = int($oldest_unm2d_days) + 7;
	$oldest_to_show = 21 if $oldest_to_show < 21;
	my $m2_text = getM2Text($stats->getModM2Ratios(), {
		oldest => $oldest_to_show
	});
	slashdLog("Misc Moderation Stats End");

	slashdLog("Problem Modders Begin");
	my $late_modders 		= $stats->getTopModdersNearArchive({limit => 5});
	my $early_inactive_modders      = $stats->getTopEarlyInactiveDownmodders({limit => 5 });
	slashdLog("Problem Modders End");

	foreach my $mod (@$late_modders){
		$mod_data{late_modders_report} .= sprintf("%-6d %-20s %5d \n",$mod->{uid}, $mod->{nickname}, $mod->{count});
	}

	foreach my $mod (@$early_inactive_modders){
		$mod_data{early_inactive_modders_report} .= sprintf("%-6d %-20s %5d \n",$mod->{uid}, $mod->{nickname}, $mod->{count});
	}
	
	slashdLog("Moderation Stats End");

	slashdLog("Page Counting Begin");
	my $sdTotalHits = $backupdb->getVar('totalhits', 'value', 1);
	my $daily_total = $logdb->countDailyByPage('', {
		no_op => $constants->{op_exclude_from_countdaily},
	});

	my $anon_daily_total = $logdb->countDailyByPage('', {
		no_op     => $constants->{op_exclude_from_countdaily},
		user_type => "anonymous"
	});

	my $logged_in_daily_total = $logdb->countDailyByPage('', {
		no_op     => $constants->{op_exclude_from_countdaily},
		user_type => "logged-in"
	});
	
	$sdTotalHits = $sdTotalHits + $daily_total;
	# Need to figure in the main section plus what the handler is.
	# This doesn't work for the other sites... -Brian
	my $homepage = $logdb->countDailyByPage('index', {
		section => 'index',
		no_op   => $constants->{op_exclude_from_countdaily},
	});

	my $unique_users = $logdb->countUsersByPage();
	my $unique_ips = $logdb->countDailyByPageDistinctIPID();
	my $anon_ips = $logdb->countDailyByPageDistinctIPID("", { user_type => 'anonymous'});
	my $logged_in_ips = $logdb->countDailyByPageDistinctIPID("", { user_type => 'logged-in'});

	my $grand_total = $logdb->countDailyByPage('');
	$data{grand_total} =  sprintf("%8d", $grand_total);
	my $grand_total_static = $logdb->countDailyByPage('',{ static => 'yes' } );
	$data{grand_total_static} = sprintf("%8d", $grand_total_static);
	my $total_static = $logdb->countDailyByPage('', {
		static => 'yes',
		no_op => $constants->{op_exclude_from_countdaily}
	} );
	$data{total_static} = sprintf("%8d", $total_static);
	my $recent_subscribers = $stats->getRecentSubscribers();
	my $recent_subscriber_uidlist = "";
	$recent_subscriber_uidlist = join(", ", @$recent_subscribers)
		if $recent_subscribers && @$recent_subscribers;
	my $total_subscriber = $logdb->countDailySubscribers($recent_subscribers);
	my $unique_users_subscriber = 0;
	$unique_users_subscriber = $logdb->countUsersByPage('', {
		extra_where_clause	=> "uid IN ($recent_subscriber_uidlist)"
	}) if $recent_subscriber_uidlist;
	my $total_secure = $logdb->countDailySecure();
	for my $op (@PAGES) {
		my $uniq = $logdb->countDailyByPageDistinctIPID($op);
		my $pages = $logdb->countDailyByPage($op);
		my $bytes = $logdb->countBytesByPage($op);
		my $uids = $logdb->countUsersByPage($op);
		$data{"${op}_label"} = sprintf("%8s", $op);
		$data{"${op}_uids"} = sprintf("%8d", $uids);
		$data{"${op}_ipids"} = sprintf("%8d", $uniq);
		$data{"${op}_bytes"} = sprintf("%0.1f MB",$bytes/(1024*1024));
		$data{"${op}_page"} = sprintf("%8d", $pages);
		# Section is problematic in this definition, going to store
		# the data in "all" till this is resolved. -Brian
		$statsSave->createStatDaily("${op}_uids", $uids);
		$statsSave->createStatDaily("${op}_ipids", $uniq);
		$statsSave->createStatDaily("${op}_bytes", $bytes);
		$statsSave->createStatDaily("${op}_page", $pages);
		if ($op eq "article") {
			my $avg = $stats->getAverageHitsPerStoryOnDay($yesterday, $pages);
			$statsSave->createStatDaily("avg_hits_per_story", $avg);
		}
	}
	#Other not recorded
	{
		my $options = { no_op => \@PAGES};
		my $uniq = $logdb->countDailyByPageDistinctIPID('', $options);
		my $pages = $logdb->countDailyByPage('', $options);
		my $bytes = $logdb->countBytesByPage('', $options);
		my $uids = $logdb->countUsersByPage('', $options);
		$data{"other_uids"} = sprintf("%8d", $uids);
		$data{"other_ipids"} = sprintf("%8d", $uniq);
		$data{"other_bytes"} = sprintf("%0.1f MB",$bytes/(1024*1024));
		$data{"other_page"} = sprintf("%8d", $pages);
		# Section is problematic in this definition, going to store
		# the data in "all" till this is resolved. -Brian
		$statsSave->createStatDaily("other_uids", $uids);
		$statsSave->createStatDaily("other_ipids", $uniq);
		$statsSave->createStatDaily("other_bytes", $bytes);
		$statsSave->createStatDaily("other_page", $pages);
	}
	slashdLog("Page Counting End");

# Not yet
#	my $codes = $stats->getMessageCodes();
#	for (@$codes) {
#		my $temp->{name} = $_;
#		my $people = $stats->countDailyMessagesByUID($_, );
#		my $uses = $stats->countDailyMessagesByCode($_, );
#		my $mode = $stats->countDailyMessagesByMode($_, );
#		$temp->{people} = sprintf("%8d", $people);
#		$temp->{uses} = sprintf("%8d", $uses);
#		$temp->{mode} = sprintf("%8d", $mode);
#		$statsSave->createStatDaily("message_${_}_people", $people);
#		$statsSave->createStatDaily("message_${_}_uses", $uses);
#		$statsSave->createStatDaily("message_${_}_mode", $mode);
#		push(@{$data{messages}}, $temp);
#	}

	slashdLog("Sectional Stats Begin");
	my $sections =  $slashdb->getDescriptions('sections-all');
	$sections->{index} = 'index';
	for my $section (sort keys %$sections) {
		my $index = $constants->{defaultsection} eq $section ? 1 : 0;
		my $temp = {};
		$temp->{section_name} = $section;
		my $uniq = $logdb->countDailyByPageDistinctIPID('', { section => $section });
		my $pages = $logdb->countDailyByPage('', {
			section		=> $section,
			no_op		=> $constants->{op_exclude_from_countdaily}
		} );
		my $bytes = $logdb->countBytesByPage('', { section => $section });
		my $users = $logdb->countUsersByPage('', { section => $section });
		my $users_subscriber = 0;
		$users_subscriber = $logdb->countUsersByPage('', {
			section			=> $section,
			extra_where_clause	=> "uid IN ($recent_subscriber_uidlist)"
		}) if $recent_subscriber_uidlist;
		$temp->{ipids} = sprintf("%8d", $uniq);
		$temp->{bytes} = sprintf("%8.1f MB",$bytes/(1024*1024));
		$temp->{pages} = sprintf("%8d", $pages);
		$temp->{site_users} = sprintf("%8d", $users);
		$statsSave->createStatDaily("ipids", $uniq, { section => $section });
		$statsSave->createStatDaily("bytes", $bytes, { section => $section } );
		$statsSave->createStatDaily("page", $pages, { section => $section });
		$statsSave->createStatDaily("users", $users, { section => $section });
		$statsSave->createStatDaily("users_subscriber", $users_subscriber, { section => $section });
			
		foreach my $d (@$cc_days) {
			my $avg_comments = $stats->getAverageCommentCountPerStoryOnDay($d, { section => $section }) || 0;
			$statsSave->createStatDaily("avg_comments_per_story", $avg_comments, 
							{ section => $section, overwrite => 1, day => $d });
		}

		for my $op (@PAGES) {
			my $uniq = $logdb->countDailyByPageDistinctIPID($op, { section => $section });
			my $pages = $logdb->countDailyByPage($op, {
				section => $section,
				no_op => $constants->{op_exclude_from_countdaily}
			} );
			my $bytes = $logdb->countBytesByPage($op, { section => $section });
			my $users = $logdb->countUsersByPage($op, { section => $section });
			$temp->{$op}{label} = sprintf("%8s", $op);
			$temp->{$op}{ipids} = sprintf("%8d", $uniq);
			$temp->{$op}{bytes} = sprintf("%8.1f MB",$bytes/(1024*1024));
			$temp->{$op}{pages} = sprintf("%8d", $pages);
			$temp->{$op}{users} = sprintf("%8d", $users);
			$statsSave->createStatDaily("${op}_ipids", $uniq, { section => $section});
			$statsSave->createStatDaily("${op}_bytes", $bytes, { section => $section});
			$statsSave->createStatDaily("${op}_page", $pages, { section => $section});
			$statsSave->createStatDaily("${op}_user", $users, { section => $section});

			if ($op eq "article") {
				my $avg = $stats->getAverageHitsPerStoryOnDay($yesterday, $pages, { section => $section });
				$statsSave->createStatDaily("avg_hits_per_story", $avg, { section => $section });
			}
		}
		#Other not recorded
		{
			my $options = { no_op => \@PAGES , section => $section };
			my $uniq = $logdb->countDailyByPageDistinctIPID('', $options);
			my $pages = $logdb->countDailyByPage('', $options);
			my $bytes = $logdb->countBytesByPage('', $options);
			my $uids = $logdb->countUsersByPage('', $options);
			my $op = 'other';
			$temp->{$op}{ipids} = sprintf("%8d", $uniq);
			$temp->{$op}{bytes} = sprintf("%8.1f MB",$bytes/(1024*1024));
			$temp->{$op}{pages} = sprintf("%8d", $pages);
			$temp->{$op}{users} = sprintf("%8d", $users);
			$statsSave->createStatDaily("${op}_ipids", $uniq, { section => $section});
			$statsSave->createStatDaily("${op}_bytes", $bytes, { section => $section});
			$statsSave->createStatDaily("${op}_page", $pages, { section => $section});
			$statsSave->createStatDaily("${op}_user", $users, { section => $section});
		}

		push(@{$data{sections}}, $temp);
	}
	slashdLog("Sectional Stats End");

	slashdLog("Story Comment Counts Begin");
	foreach my $d (@$cc_days) {
		my $avg_comments = $stats->getAverageCommentCountPerStoryOnDay($d) || 0;
		$statsSave->createStatDaily("avg_comments_per_story", $avg_comments, 
						{ overwrite => 1, day => $d });

		my $stories = $stats->getStoryHitsForDay($d);
		my %topic_hits;
		foreach my $st (@$stories){
			my $topics = $slashdb->getStoryTopics($st->{sid}, 2);
			foreach my $tid (keys %$topics){
				$topic_hits{$tid."_".$topics->{$tid}} += $st->{hits};
			}
		}
		foreach my $key (keys %topic_hits){
			$statsSave->createStatDaily("topichits_$key", $topic_hits{$key}, { overwrite => 1, day => $d });
		}

	}
	
	foreach my $day (@ah_days){
		my $avg = $stats->sqlSelect("value", "stats_daily",
			"day='$day' AND section='all' AND name='avg_comments_per_story'");
		push @{$data{avg_comments_per_story}}, sprintf("%12.1f", $avg);
	}
	slashdLog("Story Comment Counts End");


	my $total_bytes = $logdb->countBytesByPage('', {
		no_op => $constants->{op_exclude_from_countdaily}
	} );
	my $grand_total_bytes = $logdb->countBytesByPage('');

	my $admin_mods = $stats->getAdminModsInfo();
	my $admin_mods_text = getAdminModsText($admin_mods);

	$mod_data{repeat_mods} = $stats->getRepeatMods({
		min_count => $constants->{mod_stats_min_repeat}
	});
	$mod_data{reverse_mods} = $stats->getReverseMods();

	slashdLog("Duration Stats Begin");
	my $static_op_hour = $logdb->getDurationByStaticOpHour({});
	for my $is_static (keys %$static_op_hour) {
		for my $op (keys %{$static_op_hour->{$is_static}}) {
			for my $hour (keys %{$static_op_hour->{$is_static}{$op}}) {
				my $prefix = "duration_";
				$prefix .= $is_static eq 'yes' ? 'st_' : 'dy_';
				$prefix .= sprintf("%s_%02d_", $op, $hour);
				my $this_hr = $static_op_hour->{$is_static}{$op}{$hour};
				my @dur_keys =
					grep /^dur_(mean|stddev|ile_\d+)$/,
					keys %$this_hr;
				for my $dur_key (@dur_keys) {
					my($statname) = $dur_key =~ /^dur_(.+)/;
					$statname = "$prefix$statname";
					my $value = $this_hr->{$dur_key};
					$statsSave->createStatDaily($statname, $value);
				}
			}
		}
	}

	my $static_localaddr = $logdb->getDurationByStaticLocaladdr();
	for my $is_static (keys %$static_localaddr) {
		for my $localaddr (keys %{$static_localaddr->{$is_static}}) {
			my $prefix = "duration_";
			$prefix .= $is_static eq 'yes' ? 'st_' : 'dy_';
			$prefix .= "${localaddr}_";
			$prefix =~ s/\W+/_/g; # change "."s in localaddr into "_"s
			my $this_hr = $static_localaddr->{$is_static}{$localaddr};
			my @dur_keys =
				grep /^dur_(mean|stddev|ile_\d+)$/,
				keys %$this_hr;
			for my $dur_key (@dur_keys) {
				my($statname) = $dur_key =~ /^dur_(.+)/;
				$statname = "$prefix$statname";
				my $value = $this_hr->{$dur_key};
				$statsSave->createStatDaily($statname, $value);
			}
		}
	}
	slashdLog("Duration Stats End");

	$statsSave->createStatDaily("total", $daily_total);
	$statsSave->createStatDaily("anon_total", $anon_daily_total);
	$statsSave->createStatDaily("logged_in_total", $logged_in_daily_total);
	$statsSave->createStatDaily("total_static", $total_static);
	$statsSave->createStatDaily("total_subscriber", $total_subscriber);
	$statsSave->createStatDaily("total_secure", $total_secure);
	$statsSave->createStatDaily("grand_total", $grand_total);
	$statsSave->createStatDaily("grand_total_static", $grand_total_static);
	$statsSave->createStatDaily("total_bytes", $total_bytes);
	$statsSave->createStatDaily("grand_total_bytes", $grand_total_bytes);
	$statsSave->createStatDaily("unique", $unique_ips);
	$statsSave->createStatDaily("anon_unique", $anon_ips);
	$statsSave->createStatDaily("logged_in_unique", $logged_in_ips);
	$statsSave->createStatDaily("unique_users", $unique_users);
	$statsSave->createStatDaily("users_subscriber", $unique_users_subscriber);
	$statsSave->createStatDaily("comments", $comments);
	$statsSave->createStatDaily("homepage", $homepage);
	$statsSave->createStatDaily("distinct_comment_ipids", scalar(@$distinct_comment_ipids));
	$statsSave->createStatDaily("distinct_comment_ipids_anononly", $distinct_comment_ipids_anononly);
	$statsSave->createStatDaily("distinct_comment_ipids_loggedinonly", $distinct_comment_ipids_loggedinonly);
	$statsSave->createStatDaily("distinct_comment_ipids_anonandloggedin", $distinct_comment_ipids_anonandloggedin);
	$statsSave->createStatDaily("comments_ipids_anononly", $comments_ipids_anononly);
	$statsSave->createStatDaily("comments_ipids_loggedinonly", $comments_ipids_loggedinonly);
	$statsSave->createStatDaily("comments_ipids_anonandloggedin", $comments_ipids_anonandloggedin);
	$statsSave->createStatDaily("comments_proxyanon", $comments_proxyanon);
	$statsSave->createStatDaily("distinct_comment_posters_uids", $distinct_comment_posters_uids);
	for my $type (sort keys %$comments_discussiontype_hr) {
		$statsSave->createStatDaily("comments_discussiontype_$type", $comments_discussiontype_hr->{$type});
	}
	$statsSave->createStatDaily("consensus", $consensus);
	$statsSave->createStatDaily("modlogs", $modlogs);
	$statsSave->createStatDaily("modlog_inactive_percent", $modlog_inactive_percent);
	$statsSave->createStatDaily("metamodlogs", $metamodlogs);
	$statsSave->createStatDaily("xmodlog", $modlogs_needmeta ? $metamodlogs/$modlogs_needmeta : 0);
	$statsSave->createStatDaily("metamodlog_inactive_percent", $metamodlog_inactive_percent);
	$statsSave->createStatDaily("modlog_yest", $modlogs_yest);
	$statsSave->createStatDaily("modlog_inactive_percent_yest", $modlog_inactive_percent_yest);
	for my $m2c_hr (@$unm2dmods) {
		$statsSave->createStatDaily("modlog_m2count_$m2c_hr->{m2count}", $m2c_hr->{cnt});
	}
	$statsSave->createStatDaily("metamodlog_yest", $metamodlogs_yest_total);
	$statsSave->createStatDaily("xmodlog_yest", $modlogs_needmeta_yest ? $metamodlogs_yest_total/$modlogs_needmeta_yest : 0);
	$statsSave->createStatDaily("metamodlog_inactive_percent_yest", $metamodlog_inactive_percent_yest);
	$statsSave->createStatDaily("mod_used_total_pool", ($mod_points_pool ? $modlog_spent_yest_total*100/$mod_points_pool : 0));
	$statsSave->createStatDaily("mod_used_total_comments", ($comments ? $modlog_count_yest_total*100/$comments : 0));
	$statsSave->createStatDaily("mod_points_pool", $mod_points_pool);
	$statsSave->createStatDaily("mod_tokens_pool_pos", $mod_tokens_pool_pos);
	$statsSave->createStatDaily("mod_tokens_pool_neg", $mod_tokens_pool_neg);
	$statsSave->createStatDaily("mod_points_needmeta", $modlogs_needmeta_yest);
	$statsSave->createStatDaily("mod_points_lost_spent", $modlog_spent_yest_total);
	$statsSave->createStatDaily("mod_points_lost_spent_plus_1", $modlog_yest_hr->{+1}{spent});
	$statsSave->createStatDaily("mod_points_lost_spent_minus_1", $modlog_yest_hr->{-1}{spent});
	$statsSave->createStatDaily("mod_points_lost_spent_plus_1_percent", ($modlog_count_yest_total ? $modlog_yest_hr->{1}{count}*100/$modlog_count_yest_total : 0));
	$statsSave->createStatDaily("mod_points_lost_spent_minus_1_percent", ($modlog_count_yest_total ? $modlog_yest_hr->{-1}{count}*100/$modlog_count_yest_total : 0));
	$statsSave->createStatDaily("mod_points_avg_spent", $modlog_count_yest_total ? sprintf("%12.3f", $modlog_spent_yest_total/$modlog_count_yest_total) : "(n/a)");
	$statsSave->createStatDaily("m2_freq", $constants->{m2_freq} || 86400);
	$statsSave->createStatDaily("m2_consensus", $constants->{m2_consensus} || 0);
	$statsSave->createStatDaily("m2_mintokens", $slashdb->getVar("m2_mintokens", "value", 1) || 0);
	$statsSave->createStatDaily("m2_points_lost_spent", $metamodlogs_yest_total);
	$statsSave->createStatDaily("m2_points_lost_spent_fair", $metamodlogs_yest_fair);
	$statsSave->createStatDaily("m2_points_lost_spent_unfair", $metamodlogs_yest_unfair);
	$statsSave->createStatDaily("oldest_unm2d", $oldest_unm2d);
	$statsSave->createStatDaily("oldest_unm2d_days", $oldest_unm2d_days);
	$statsSave->createStatDaily("mod_token_conversion_point", $token_conversion_point);
	$statsSave->createStatDaily("submissions", $submissions);
	$statsSave->createStatDaily("submissions_comments_match", $submissions_comments_match);
	$statsSave->createStatDaily("youngest_modelig_uid", sprintf("%d", $youngest_modelig_uid));
	$statsSave->createStatDaily("youngest_modelig_created", sprintf("%11s", $youngest_modelig_created));

	foreach my $i ($constants->{comment_minscore}..$constants->{comment_maxscore}) {
		$statsSave->createStatDaily("comments_score_$i",
			$stats->getDailyScoreTotal($i));
	}

	for my $nickname (keys %$admin_mods) {
		my $uid = $admin_mods->{$nickname}{uid};
		# Each stat writes one row into stats_daily for each admin who
		# modded anything, which is a lot of rows, but we want all the
		# data.
		for my $stat (qw( m1_up m1_down m2_fair m2_unfair )) {
			my $suffix = $uid
				? "_admin_$uid"
				: "_total";
			my $val = $admin_mods->{$nickname}{$stat};
			$statsSave->createStatDaily("$stat$suffix", $val);
		}
	}

	my $accesslist_counts = $stats->getAccesslistCounts();
	for my $key (keys %$accesslist_counts) {
		$statsSave->createStatDaily("accesslist_$key", $accesslist_counts->{$key});
	}
	
	foreach my $day (@ah_days){
		my $avg = $stats->sqlSelect("value", "stats_daily", "day='$day' and section='all' and name='avg_hits_per_story'");
		push @{$data{avg_hits_per_story}}, sprintf("%12.1f", $avg);
	}

	$data{total} = sprintf("%8d", $daily_total);
	$data{total_bytes} = sprintf("%0.1f MB",$total_bytes/(1024*1024));
	$data{grand_total_bytes} = sprintf("%0.1f MB",$grand_total_bytes/(1024*1024));
	$data{total_subscriber} = sprintf("%8d", $total_subscriber);
	$data{total_secure} = sprintf("%8d", $total_secure);
	$data{unique} = sprintf("%8d", $unique_ips), 
	$data{users} = sprintf("%8d", $unique_users);
	$data{accesslog} = sprintf("%8d", $accesslog_rows);
	$data{formkeys} = sprintf("%8d", $formkeys_rows);
	$data{error_count} = sprintf("%8d", $data{error_count});
	$data{not_found} = sprintf("%8d", $data{not_found});
	$data{status_202} = sprintf("%8d", $data{status_202});

	$mod_data{comments} = sprintf("%8d", $comments);
	$mod_data{modlog} = sprintf("%8d", $modlogs);
	$mod_data{modlog_inactive_percent} = sprintf("%.1f", $modlog_inactive_percent);
	$mod_data{modlog_yest} = sprintf("%8d", $modlogs_yest);
	$mod_data{modlog_inactive_percent_yest} = sprintf("%.1f", $modlog_inactive_percent_yest);
	$mod_data{metamodlog} = sprintf("%8d", $metamodlogs);
	$mod_data{metamodlog_inactive_percent} = sprintf("%.1f", $metamodlog_inactive_percent);
	$mod_data{metamodlog_yest} = sprintf("%8d", $metamodlogs_yest_total);
	$mod_data{metamodlog_inactive_percent_yest} = sprintf("%.1f", $metamodlog_inactive_percent_yest);
	$mod_data{xmodlog} = sprintf("%.1fx", ($modlogs_needmeta ? $metamodlogs/$modlogs_needmeta : 0));
	$mod_data{xmodlog_yest} = sprintf("%.1fx", ($modlogs_needmeta_yest ? $metamodlogs_yest_total/$modlogs_needmeta_yest : 0));
	$mod_data{consensus} = sprintf("%8d", $consensus);
	$mod_data{oldest_unm2d_days} = $oldest_unm2d_days;
	$mod_data{youngest_modelig_uid} = sprintf("%d", $youngest_modelig_uid);
	$mod_data{youngest_modelig_created} = sprintf("%11s", $youngest_modelig_created);
	$mod_data{mod_points_pool} = sprintf("%8d", $mod_points_pool);
	$mod_data{used_total} = sprintf("%8d", $modlog_count_yest_total);
	$mod_data{used_total_pool} = sprintf("%.1f", ($mod_points_pool ? $modlog_spent_yest_total*100/$mod_points_pool : 0));
	$mod_data{used_total_comments} = sprintf("%.1f", ($comments ? $modlog_count_yest_total*100/$comments : 0));
	$mod_data{used_minus_1} = sprintf("%8d", $modlog_yest_hr->{-1}{count});
	$mod_data{used_minus_1_percent} = sprintf("%.1f", ($modlog_count_yest_total ? $modlog_yest_hr->{-1}{count}*100/$modlog_count_yest_total : 0) );
	$mod_data{used_plus_1} = sprintf("%8d", $modlog_yest_hr->{1}{count});
	$mod_data{used_plus_1_percent} = sprintf("%.1f", ($modlog_count_yest_total ? $modlog_yest_hr->{1}{count}*100/$modlog_count_yest_total : 0));
	$mod_data{mod_points_avg_spent} = $modlog_count_yest_total ? sprintf("%12.3f", $modlog_spent_yest_total/$modlog_count_yest_total) : "(n/a)";
	$mod_data{day} = $yesterday;
	$mod_data{token_conversion_point} = sprintf("%8d", $token_conversion_point);
	$mod_data{m2_text} = $m2_text;

	$data{comments} = $mod_data{comments};
	$data{IPIDS} = sprintf("%8d", scalar(@$distinct_comment_ipids));
	$data{submissions} = sprintf("%8d", $submissions);
	$data{sub_comments} = sprintf("%8.1f", ($submissions ? $submissions_comments_match*100/$submissions : 0));
	$data{total_hits} = sprintf("%8d", $sdTotalHits);

	$statsSave->createStatDaily("sub_comments", $data{sub_comments});
	$statsSave->createStatDaily("total_hits", $sdTotalHits);

	$data{homepage} = sprintf("%8d", $homepage);
	$data{day} = $yesterday ;
	$data{distinct_comment_posters_uids} = sprintf("%8d", $distinct_comment_posters_uids);

	my @top_articles =
		grep { $articles->{$_} >= 100 }
		sort { ($articles->{$b} || 0) <=> ($articles->{$a} || 0) }
		keys %$articles;
	$#top_articles = 24 if $#top_articles > 24; # only list top 25 stories
	my @lazy = ( );
	my %nick = ( );
	for my $sid (@top_articles) {
		my $hitcount = $articles->{$sid};
 		my $story = $backupdb->getStory($sid, [qw( title uid )]);
		next unless $story->{title} && $story->{uid};
		$nick{$story->{uid}} ||= $backupdb->getUser($story->{uid}, 'nickname')
			|| $story->{uid};

		push @lazy, sprintf( "%6d %-16s %-10s %-30s",
			$hitcount, $sid, $nick{$story->{uid}},
			substr($story->{title}, 0, 30),
		);
	}

	$mod_data{data} = \%mod_data;
	$mod_data{admin_mods_text} = $admin_mods_text;
	
	$data{data} = \%data;
	$data{lazy} = \@lazy; 
	$data{admin_clearpass_warning} = $admin_clearpass_warning;
	$data{tailslash} = $logdb->getTailslash();

	slashdLog("Random Stats Begin");
	$data{backup_lag} = "";
	for my $slave_name (qw( backup search )) {
		my $virtuser = $constants->{"${slave_name}_db_user"};
		next unless $virtuser;
		my $bytes = $stats->getSlaveDBLagCount($virtuser);
		if ($bytes > ($constants->{db_slave_lag_ignore} || 10000000)) {
			$data{backup_lag} .= "\n" . getData('db lagged', {
				slave_name =>	$slave_name,
				bytes =>	$bytes,
			}, 'adminmail') . "\n";
		}
	}

	$data{sfnet} = { };
	my $gids = $constants->{stats_sfnet_groupids};
	if ($gids && @$gids) {
		for my $groupid (@$gids) {
			my $hr = $stats->countSfNetIssues($groupid);
			for my $issue (sort keys %$hr) {
				my $lc_issue = lc($issue);
				$lc_issue =~ s/\W+//g;
				$statsSave->createStatDaily("sfnet_${groupid}_${lc_issue}_open", $hr->{$issue}{open});
				$statsSave->createStatDaily("sfnet_${groupid}_${lc_issue}_total", $hr->{$issue}{total});
				$data{sfnet}{$groupid}{$issue} = $hr->{$issue};
			}
		}
	}

	$data{top_referers} = $logdb->getTopReferers({count => 20});

	my $new_users_yest = $slashdb->getNumNewUsersSinceDaysback(1)
		- $slashdb->getNumNewUsersSinceDaysback(0);
	$statsSave->createStatDaily('users_created', $new_users_yest);
	$data{rand_users_yest} = $slashdb->getRandUsersCreatedYest(10, $yesterday);
	($data{top_recent_domains}, $data{top_recent_domains_daysback}, $data{top_recent_domains_newaccounts}) = $slashdb->getTopRecentRealemailDomains($yesterday);

	my $relocate = getObject('Slash::Relocate');

	if($relocate){
		my $rls      = $logdb->getRelocatedLinksSummary();
		my $sum      = $stats->getRelocatedLinkHitsByType($rls);
		my $rls_tu   = $logdb->getRelocatedLinksSummary({ limit => 10});

		$data{top_relocated_urls} = $stats->getRelocatedLinkHitsByUrl($rls_tu);

		my $total;
		foreach my $type (keys %$sum){
			my $label = $type eq "" ? "relocate_other" : "relocate_$type";
			$statsSave->createStatDaily($label, $sum->{$type});
			$total += $sum->{$type};
		}
		$statsSave->createStatDaily("relocate_all", $total);
	}
	
	my $subscribe = getObject('Slash::Subscribe');
	
	if($subscribe){
		my $rswh =   $stats->getSubscribersWithRecentHits();
		my $sub_cr = $logdb->getSubscriberCrawlers($rswh);
		my $sub_report;
		foreach my $sub (@$sub_cr){
			$sub_report .= sprintf("%6d %s\n", $sub->{cnt}, ($slashdb->getUser($sub->{uid}, 'nickname') || $sub->{uid})); 
	 	}
		$data{crawling_subscribers} = $sub_report if $sub_report; 
	}	

	my $email = slashDisplay('display', \%data, {
		Return => 1, Page => 'adminmail', Nocomm => 1
	});

	my $mod_email = slashDisplay('display', \%mod_data, {
		Return => 1, Page => 'modmail', Nocomm => 1
	}) if $constants->{mod_stats};

	my $messages = getObject('Slash::Messages');

	# do message log stuff
	if ($messages) {
		my $msg_log = $messages->getDailyLog( $statsSave->{_day} );
		my %msg_codes;

		# msg_12_1 -> code 12, mode 1 (relationship change, web)
		for my $type (@$msg_log) {
			my($code, $mode, $count) = @$type;
			$msg_codes{$code} += $count;
			$statsSave->createStatDaily("msg_${code}_${mode}", $count);
		}

		for my $code (keys %msg_codes) {
			$statsSave->createStatDaily("msg_${code}", $msg_codes{$code});
		}
	}
	slashdLog("Random Stats End");

	# Send a message to the site admin.
	if ($messages) {
		$data{template_name} = 'display';
		$data{subject} = getData('email subject', {
			day =>	$data{day}
		}, 'adminmail');
		$data{template_page} = 'adminmail';
		my $message_users = $messages->getMessageUsers(MSG_CODE_ADMINMAIL);
		for (@$message_users) {
			$messages->create($_, MSG_CODE_ADMINMAIL, \%data);
		}

		if ($constants->{mod_stats}) {
			$mod_data{template_name} = 'display';
			$mod_data{subject} = getData('modmail subject', {
				day => $mod_data{day}
			}, 'adminmail');
			$mod_data{template_page} = 'modmail';
			my $mod_message_users = $messages->getMessageUsers(MSG_CODE_MODSTATS);
			for (@$mod_message_users) {
				$messages->create($_, MSG_CODE_MODSTATS, \%mod_data);
			}
		}
	}

	if ($constants->{mod_stats} && $mod_email =~ /\S/) {
		for (@{$constants->{mod_stats_reports}}) {
			sendEmail($_, $mod_data{subject}, $mod_email, 'bulk');
		}
	}

	for (@{$constants->{stats_reports}}) {
		sendEmail($_, $data{subject}, $email, 'bulk');
	}
	slashdLog("Send Admin Mail End for $yesterday");

	# for stats.pl to know ...
	$slashdb->setVar('adminmail_last_run', $yesterday);

	return ;
};

sub getM2Text {
	my($mmr, $options) = @_;

	my $constants = getCurrentStatic();
	my $consensus = $constants->{m2_consensus};

	# %$mmr is a hashref whose keys are dates, "yyyy-mm-dd".
	# Its values are hashrefs whose keys are M2 counts for
	# those days.  _Those_ values are also hashrefs of which
	# only one key, "c", is important and its value is the
	# count of M2 counts for that day.
	# For example, if $mmr->{'2002-01-01'}{5}{c} == 200,
	# that means that of the moderations performed on
	# 2002-01-01, there are 200 which have been M2'd 5 times.
	# Special keys are "X", which substitutes for all mods
	# which have been completely M2'd, and "_" which is for
	# mods which cannot be M2'd.

	my $width = 78;
	$width = $options->{width} if $options->{width};
	$width = 10 if $width < 10;

	# Find the max count total for a day.
	my $max_day_count = 0;
	for my $day (keys %$mmr) {
		my $this_day_count = 0;
		for my $m2c (keys %{$mmr->{$day}}) {
			$this_day_count += $mmr->{$day}{$m2c}{c};
		}
		$max_day_count = $this_day_count
			if $this_day_count > $max_day_count;
	}

	# If there are no mods at all, we return nothing.
	return "" if $max_day_count == 0;

	# Prepare to build the $text data.
	my $prefix_len = 7;
	my $width_histo = $width-$prefix_len;
	$width_histo = 5 if $width_histo < 5;
	my $mult = $width_histo/$max_day_count;
	$mult = 1 if $mult > 1;
	my $per = sprintf("%.0f", 1/$mult);
	my $text = "Moderations and their M2 counts (each char represents $per mods):\n";

	# Build the $text data, one line at a time.
	my @days = sort keys %$mmr;
	my $oldest = $options->{oldest} || 30;
	if (scalar(@days) > $oldest) {
		# If we have too much data, throw away the oldest.
		@days = @days[-$oldest..-1];
	}
	sub valsort { ($b eq 'X' ? 999 : $b eq '_' ? -999 : $b) <=> ($a eq 'X' ? 999 : $a eq '_' ? -999 : $a) }
	for my $day (@days) {
		my $day_display = substr($day, 5); # e.g. '01-01'
		$text .= "$day_display: ";
		for my $m2c (sort valsort keys %{$mmr->{$day}}) {
			my $c = $mmr->{$day}{$m2c}{c};
			my $n = int($c*$mult+0.5);
			next unless $n;
			my $char = $m2c;
			$char = sprintf("%x", $m2c) if $m2c =~ /^\d+$/;
			$text .= $char x $n;
		}
		$text .= "\n";
	}

	$text .= "\n";
	return $text;
}

sub getAdminModsText {
	my($am) = @_;
	return "" if !$am or !scalar(keys %$am);

	my $text = sprintf("%-13s   %4s %4s %5s    %5s %5s %6s %14s\n",
		"Nickname",
		"M1up", "M1dn", "M1up%",
		"M2fr", "M2un", " M2un%", " M2un% (month)"
	);
	my($num_admin_mods, $num_mods) = (0, 0);
	for my $nickname (sort { lc($a) cmp lc($b) } keys %$am) {
		my $amn = $am->{$nickname};
		my $m1_up_percent = 0;
		$m1_up_percent = $amn->{m1_up}*100
			/ ($amn->{m1_up} + $amn->{m1_down})
			if $amn->{m1_up} + $amn->{m1_down} > 0;
		my $m2_un_percent = 0;
		$m2_un_percent = $amn->{m2_unfair}*100
			/ ($amn->{m2_unfair} + $amn->{m2_fair})
			if $amn->{m2_unfair} + $amn->{m2_fair} > 20;
		my $m2_un_percent_mo = 0;
		$m2_un_percent_mo = $amn->{m2_unfair_mo}*100
			/ ($amn->{m2_unfair_mo} + $amn->{m2_fair_mo})
			if $amn->{m2_unfair_mo} + $amn->{m2_fair_mo} > 20;
		next unless $amn->{m1_up} || $amn->{m1_down}
			|| $amn->{m2_fair} || $amn->{m2_unfair};
		$text .= sprintf("%13.13s   %4d %4d %4d%%    %5d %5d %5.1f%% %5.1f%%\n",
			$nickname,
			$amn->{m1_up},
			$amn->{m1_down},
			$m1_up_percent,
			$amn->{m2_fair},
			$amn->{m2_unfair},
			$m2_un_percent,
			$m2_un_percent_mo
		);
		if ($nickname eq '~Day Total') {
			$num_mods += $amn->{m1_up};
			$num_mods += $amn->{m1_down};
		} else {
			$num_admin_mods += $amn->{m1_up};
			$num_admin_mods += $amn->{m1_down};
		}
	}
	$text .= sprintf("%d of %d mods (%.2f%%) were performed by admins.\n",
		$num_admin_mods,
		$num_mods,
		($num_mods ? $num_admin_mods*100/$num_mods : 0));
	return $text;
}

1;
