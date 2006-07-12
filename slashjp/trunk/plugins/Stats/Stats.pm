# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::Stats;

=head1 NAME

Slash::Stats - Stats plugin for Slash

=cut

use strict;
use DBIx::Password;
use Slash;
use Slash::Utility;
use Slash::DB::Utility;
use LWP::UserAgent;

use vars qw($VERSION);
use base 'Slash::DB::Utility';
use base 'Slash::DB::MySQL';

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

sub new {
	my($class, $user, $options) = @_;
	my $self = {};
	my $slashdb = getCurrentDB();
	my $plugin = getCurrentStatic('plugin');
	my $constants = getCurrentStatic();
	
	return unless $plugin->{'Stats'};

	bless($self, $class);
	$self->{virtual_user} = $user;
	$self->sqlConnect;

	# The default _day is yesterday.  (86400 seconds = 1 day)
	# Build _day_between_clause for testing the usual DATETIME column
	# type against the day in question, and _ts_between_clause for
	# testing the somewhat rarer TIMESTAMP column type.
	my @yest_lt = localtime(time - 86400);
	$self->{_day} = $options->{day}
		? $options->{day}
		: sprintf("%4d-%02d-%02d", $yest_lt[5] + 1900, $yest_lt[4] + 1, $yest_lt[3]);
	$self->{_day_between_clause} = " BETWEEN '$self->{_day} 00:00' AND '$self->{_day} 23:59:59' ";
	$self->{_day_min_clause} = " >= '$self->{_day} 00:00'";
	$self->{_day_max_clause} = " <= '$self->{_day} 23:59:59'";
	($self->{_ts} = $self->{_day}) =~ s/-//g;
	$self->{_ts_between_clause}  = " BETWEEN '$self->{_ts}000000' AND '$self->{_ts}235959' ";
	$self->{_ts_min_clause} = " >= '$self->{_ts}000000'";
	$self->{_ts_max_clause} = " <= '$self->{_ts}235959'";

	my @today_lt = localtime(time);
	my $today = sprintf("%4d-%02d-%02d", $today_lt[5] + 1900, $today_lt[4] + 1, $today_lt[3]);
	
	my $count = 0;
	if ($options->{create}) {
		
		if (getCurrentStatic('adminmail_check_replication')) {
			my $wait_sec = 600;
			my $num_try = 0;
			my $max_tries = 48;
			
			my $caught_up = 0;
			while (!$caught_up) {
				my $max_id = $self->sqlSelect("MAX(id)", "accesslog");
				$caught_up = $self->sqlCount("accesslog", "id=$max_id AND ts>='$today" . "000000'");
				$num_try++;
				if (!$caught_up) {
					if ($num_try < $max_tries) {
						print STDERR "log_slave replication not caught up.  Waiting $wait_sec seconds and retrying.\n";
						sleep $wait_sec if !$caught_up;
					} else {
						print STDERR "Checked replication $num_try times without success, giving up.";
						$slashdb->insertErrnoteLog("adminmail", "Failed creating temp tables", "Checked replication $num_try times without success, giving up");
						return undef;
					}
				}
				
			}
		}

		# Why not just truncate? If we did we would never pick up schema changes -Brian
		# Create "accesslog_temp" and "accesslog_temp_errors" from the
		# schema of "accesslog".

		# First, drop them (if they exist).
		$self->sqlDo("DROP TABLE IF EXISTS accesslog_temp");
		$self->sqlDo("DROP TABLE IF EXISTS accesslog_temp_errors");
		$self->sqlDo("DROP TABLE IF EXISTS accesslog_temp_subscriber");
		$self->sqlDo("DROP TABLE IF EXISTS accesslog_temp_other");
		$self->sqlDo("DROP TABLE IF EXISTS accesslog_temp_rss");
		$self->sqlDo("DROP TABLE IF EXISTS accesslog_temp_host_addr");
		$self->sqlDo("DROP TABLE IF EXISTS accesslog_build_unique_uid");

		$self->sqlDo("CREATE TABLE accesslog_temp_host_addr (host_addr char(32) UNIQUE NOT NULL, anon ENUM('no','yes') NOT NULL DEFAULT 'yes', PRIMARY KEY (host_addr, anon)) TYPE = InnoDB");
		$self->sqlDo("CREATE TABLE accesslog_build_unique_uid ( uid MEDIUMINT UNSIGNED NOT NULL, PRIMARY KEY (uid)) TYPE = InnoDB");

		# Then, get the schema in its CREATE TABLE statement format.
		my $sth = $self->{_dbh}->prepare("SHOW CREATE TABLE accesslog");
		$sth->execute();
		my $rows = $sth->fetchrow_arrayref;
		$self->{_table} = "accesslog_temp";

		# Munge the schema to do each of the new tables.
		my $create_sql = $rows->[1];
		$create_sql =~ s/accesslog/__TABLENAME__/;
		for my $new_table (qw(
			accesslog_temp
			accesslog_temp_errors
			accesslog_temp_other
			accesslog_temp_subscriber
			accesslog_temp_rss
		)) {
			my $new_sql = $create_sql;
			$new_sql =~ s/__TABLENAME__/$new_table/;
			$self->sqlDo($new_sql);
		}

		# Create the accesslog_temp table, then add indexes to its data.
		my $minid = $self->sqlSelectNumericKeyAssumingMonotonic(
			'accesslog', 'min', 'id',
			"ts $self->{_day_min_clause}");
		my $maxid = $self->sqlSelectNumericKeyAssumingMonotonic(
			'accesslog', 'max', 'id',
			"ts $self->{_day_max_clause}");
		return undef unless $self->_do_insert_select(
			"accesslog_temp",
			"*",
			"accesslog",
			"id BETWEEN $minid AND $maxid AND ts $self->{_day_between_clause}
			 AND status  = 200 AND op != 'rss'",
			3, 60);
		# Some of these (notably ts) may be redundant but that's OK,
		# they will just throw errors we don't care about.  They're here
		# in case the table on the DB we're operating on has had its ts
		# index removed.
		$self->sqlDo("ALTER TABLE accesslog_temp ADD INDEX uid (uid)");
		$self->sqlDo("ALTER TABLE accesslog_temp ADD INDEX skid_op (skid,op)");
		$self->sqlDo("ALTER TABLE accesslog_temp ADD INDEX op_uid_skid (op, uid, skid)");
		$self->sqlDo("ALTER TABLE accesslog_temp ADD INDEX referer (referer(4))");
		$self->sqlDo("ALTER TABLE accesslog_temp ADD INDEX ts (ts)");
		$self->sqlDo("ALTER TABLE accesslog_temp_errors ADD INDEX ts (ts)");
		$self->sqlDo("ALTER TABLE accesslog_temp_subscriber ADD INDEX ts (ts)");
		$self->sqlDo("ALTER TABLE accesslog_temp_other ADD INDEX ts (ts)");
		$self->sqlDo("ALTER TABLE accesslog_temp_rss ADD INDEX ts (ts)");

		# Create the other accesslog_temp_* tables and add their indexes.
		return undef unless $self->_do_insert_select(
			"accesslog_temp_rss",
			"*",
			"accesslog",
			"id BETWEEN $minid AND $maxid AND ts $self->{_day_between_clause}
			 AND status  = 200 AND op = 'rss'",
			3, 60);
		return undef unless $self->_do_insert_select(
			"accesslog_temp_errors",
			"*",
			"accesslog",
			"id BETWEEN $minid AND $maxid AND ts $self->{_day_between_clause}
			 AND status != 200",
			3, 60);

		my $stats_reader = getObject('Slash::Stats', { db_type => 'reader' });	
		my $recent_subscribers = $stats_reader->getRecentSubscribers();

		if ($recent_subscribers && @$recent_subscribers) {
			my $recent_subscriber_uidlist = join(", ", @$recent_subscribers);
		
			return undef unless $self->_do_insert_select(
				"accesslog_temp_subscriber",
				"*",
				"accesslog_temp",
				"uid IN ($recent_subscriber_uidlist)",
				3, 60);
		}

		my @pages;
		if ($options->{other_no_op}) {
			@pages = @{$options->{other_no_op}};
		} else {
			@pages = qw|index article search comments palm journal rss page users|;
			push @pages, @{$constants->{op_extras_countdaily}};
		}

		my $page_list = join ',', map {$self->sqlQuote($_)} @pages;
		return undef unless $self->_do_insert_select(
			"accesslog_temp_other",
			"*",
			"accesslog_temp",
			"op NOT IN ($page_list)",
			3, 60);

		# Add in the indexes we need for those tables.
		$self->sqlDo("ALTER TABLE accesslog_temp_errors ADD INDEX status_op_skid (status, op, skid)");
		$self->sqlDo("ALTER TABLE accesslog_temp_subscriber ADD INDEX skid (skid)");
		$self->sqlDo("ALTER TABLE accesslog_temp_other ADD INDEX skid (skid)");
		$self->sqlDo("ALTER TABLE accesslog_temp_rss ADD INDEX skid (skid)");

		# Two more accesslog_temp_* tables, these with no special indexes.
		return undef unless $self->_do_insert_select(
			"accesslog_temp_host_addr",
			"host_addr, IF(uid = $constants->{anonymous_coward_uid}, 'yes', 'no')",
			"accesslog_temp",
			"",
			3, 60, 
			{ ignore => 1 }
			);
	
		return undef unless $self->_do_insert_select(
			"accesslog_temp_host_addr",
			"host_addr, IF(uid = $constants->{anonymous_coward_uid}, 'yes', 'no')",
			"accesslog_temp_rss",
			"",
			3, 60, 
			{ ignore => 1 } 
			);


	}

	return $self;
}


########################################################
sub getAL2Counts {
	my($self) = @_;
	my $hr = { };
	my $types = $self->getAL2Types();
	my $type_count = $self->sqlSelectAllKeyValue(
		'value, COUNT(*)',
		'al2',
		'',
		'GROUP BY value');
	for my $this_type (keys %$types) {
		next if $this_type eq 'comment';
		$hr->{$this_type} = 0;
		my $this_value = 1 << $types->{$this_type}{bitpos};
		for my $value (keys %$type_count) {
			next unless $value & $this_value;
			$hr->{$this_type} += $type_count->{$value};
		}
	}
	$hr->{all} = 0;
	for my $value (keys %$type_count) {
		$hr->{all} += $type_count->{$value};
	}
	return $hr;
}

########################################################
sub getPointsInPool {
	my($self) = @_;
	return $self->sqlSelect('SUM(points)', 'users_comments');
}

########################################################
sub getTokenConversionPoint {
	my($self) = @_;
	# We can't actually predict what the exact token value will be
	# where they get converted to mod points;  we'd have to predict
	# number of comments posted and run the same logic as
	# run_moderatord.pl to find that.  But we can make a good
	# educated guess that's probably off by a maximum of 1 token.
	my $limit = 100; # XXX need to determine this based off a stat, probably mod_tokens_lost_converted/(24*40)
	return +(@{$self->sqlSelectColArrayref(
		"tokens",
		"users_info",
		"tokens > 20", # sanity check, also appears in run_moderatord algorithm
		"ORDER BY tokens DESC LIMIT $limit"
	)})[-1];
}

########################################################
sub getTokensInPoolPos {
	my($self) = @_;
	return $self->sqlSelect('SUM(tokens)', 'users_info',
		'tokens > 0');
}

########################################################
sub getTokensInPoolNeg {
	my($self) = @_;
	return $self->sqlSelect('SUM(tokens)', 'users_info',
		'tokens < 0');
}

########################################################
sub getAdminsClearpass {
	my($self) = @_;
	return $self->sqlSelectAllHashref(
		"nickname",
		"nickname, value",
		"users, users_param",
		"users.uid = users_param.uid
			AND users.seclev > 1
			AND users_param.name='admin_clearpass'
			AND users_param.value",
		"LIMIT 999"
	);
}

########################################################
sub countModeratorLog {
	my($self, $options) = @_;

	my @clauses = ( );

	my $day = $self->{_day};
	$day = $options->{day} if $options->{day};
	push @clauses, "ts $self->{_day_between_clause}"
		if $options->{oneday_only};

	push @clauses, "active=1" if $options->{active_only};

	if ($options->{m2able_only}) {
		my $reasons = $self->getReasons();
		my @reasons_m2able = grep { $reasons->{$_}{m2able} } keys %$reasons;
		my $reasons_m2able = join(",", @reasons_m2able);
		push @clauses, "reason IN ($reasons_m2able)" if $reasons_m2able;
	}

	my $where = join(" AND ", @clauses) || "";
	my $count = $self->sqlCount("moderatorlog", $where);
	return $count;
}

########################################################
sub countMetamodLog {
	my($self, $options) = @_;

	my @clauses = ( );

	my $day = $self->{_day};
	$day = $options->{day} if $options->{day};
	push @clauses, "ts $self->{_day_between_clause}"
		if $options->{oneday_only};

	push @clauses, "active=1" if $options->{active_only};

	if ($options->{val}) {
		push @clauses, "val=" . $self->sqlQuote($options->{val});
	}

	my $where = join(" AND ", @clauses) || "";
	my $count = $self->sqlCount("metamodlog", $where);
	return $count;
}

########################################################
# Well this stat ends up being written as modlog_m2count_0
# which is useless to date (2004-04-20) since it also counts
# active mods which are un-m2able (under/overrated).  At the
# 0 count level, it's including old mods.  (Of course, at
# the 1 and above count levels, the un-m2able mods don't
# show up, so that's fine.)  Question is, do we change the
# stat now and just ignore all the old data, or do we create
# a new stat to correctly track count=0, reason IN m2able?
# - Jamie
sub countUnmetamoddedMods {
	my($self, $options) = @_;
	my $active_clause = $options->{active_only} ? " AND active=1" : "";
	return $self->sqlSelectAllHashrefArray(
		"m2count, COUNT(*) AS cnt",
		"moderatorlog",
		"m2status = 0 $active_clause",
		"GROUP BY m2count");
}

########################################################
sub getOldestUnm2dMod {
	my($self) = @_;
	my $reasons = $self->getReasons();
	my @reasons_m2able = grep { $reasons->{$_}{m2able} } keys %$reasons;
	my $reasons_m2able = join(",", @reasons_m2able);
	my @clauses = ("active=1", "m2status=0");
	push @clauses, "reason IN ($reasons_m2able)" if $reasons_m2able;
	my $where = join(" AND ", @clauses) || "";

	my($oldest) = $self->sqlSelect(
		"UNIX_TIMESTAMP(MIN(ts))",
		"moderatorlog",
		$where
	);
	return $oldest || 0;
}

########################################################
# Note, we have to use $slashdb here instead of $self.
sub getSlaveDBLagCount {
	my($self) = @_;
	my $constants = getCurrentStatic();
	my $slashdb = getCurrentDB();
	my $bdu = $constants->{backup_db_user};
	# If there *is* no backup DB, it's not lagged.
	return 0 if !$bdu || $bdu eq getCurrentVirtualUser();

	my $backupdb = getObject('Slash::DB', $bdu);
	# If there is supposed to be a backup DB but we can't contact it,
	# return a large number that is sufficiently noticeable that it
	# should alert people that something is wrong.
	return 2**30 if !$backupdb;

	# Get the actual lag count.  Assume that each file is 2**30
	# (a billion) bytes (should this be a var?).  Yes, the same
	# data is called "File" vs. "Log_File", "Position" vs. "Pos",
	# depending on whether it's on the master or slave side.
	# And on the slave side, for MySQL 4.x, I *think* I want
	# Master_Log_File and Read_Master_Log_Pos but other possible
	# candidates are Relay_Master_Log_File and Exec_master_log_pos
	# respectively.
	my $master = ($slashdb->sqlShowMasterStatus())->[0];
	my $slave  = ($backupdb->sqlShowSlaveStatus())->[0];
	my $master_filename = $master->{File};
	my $slave_filename  = $slave ->{Log_File} || $slave->{Master_Log_File};
	my($master_file_num) = $master_filename =~ /\.(\d+)$/;
	my($slave_file_num)  = $slave_filename  =~ /\.(\d+)$/;
	my $master_pos = $master->{Position};
	my $slave_pos  = $slave->{Pos} || $slave->{Read_Master_Log_Pos};

	my $count = 2**30 * ($master_file_num - $slave_file_num)
		+ $master_pos - $slave_pos;
	$count = 0 if $count < 0;
	$count = 2**30 if $count > 2**30;
	return $count;
}

########################################################
sub getRepeatMods {
	my($self, $options) = @_;
	my $constants = getCurrentStatic();
	my $ac_uid = $constants->{anonymous_coward_uid};

	my $lookback = $options->{lookback_days} || 30;
	my $within = $options->{within_hours} || 96;
	my $limit = $options->{limit} || 50;
	my $min_count = $options->{min_count}
		|| $constants->{mod_stats_min_repeat}
		|| 2;

	my $hr = $self->sqlSelectAllHashref(
		[qw( val orguid destuid )],
		"usersorg.uid AS orguid,
		 usersorg.nickname AS orgnick,
		 COUNT(*) AS c, val,
		 MAX(ts) AS latest,
		 IF(MAX(ts) > DATE_SUB(NOW(), INTERVAL 24 HOUR),
			1, 0) AS isrecent,
		 usersdest.uid AS destuid,
		 usersdest.nickname AS destnick,
		 usersdesti.karma AS destkarma",
		"users AS usersorg,
		 users_info AS usersorgi,
		 moderatorlog,
		 users AS usersdest,
		 users_info AS usersdesti",
		"usersorg.uid=moderatorlog.uid
		 AND usersorg.uid=usersorgi.uid
		 AND usersorgi.tokens >= -50
		 AND usersorg.seclev < 100
		 AND moderatorlog.cuid=usersdest.uid
		 AND moderatorlog.ts >= DATE_SUB(NOW(), INTERVAL $lookback DAY)
		 AND usersdest.uid=usersdesti.uid
		 AND usersdest.uid != $ac_uid",
		"GROUP BY usersorg.uid, usersdest.uid, val
		 HAVING c >= $min_count
			AND latest >= DATE_SUB(NOW(), INTERVAL $within HOUR)
		 ORDER BY c DESC, orguid
		 LIMIT $limit"
	);
	return $hr;
}

########################################################
sub getModM2Ratios {
	my($self, $options) = @_;

	# The SQL here tells the DB to count up how many of the mods
	# have been M2'd how much, basically building a histogram.
	# (The DB returns the counts for each character in each row
	# of the histogram, and perl assembles them into the text
	# that is output.)
	# If there are no m2able modreasons, every char in the
	# histogram is "X".  Otherwise, the chars in the histogram
	# are "X" for fully-M2'd mods, "_" for un-m2able mods, and
	# for mods which have been partially M2'd, the digit showing
	# the number of M2's applied to them so far.
	my $reasons = $self->getReasons();
	my @reasons_m2able = grep { $reasons->{$_}{m2able} } keys %$reasons;
	my $reasons_m2able = join(",", @reasons_m2able);
	my $m2able_char_clause = $reasons_m2able
		? "IF(reason IN ($reasons_m2able), m2count, '_')"
		: "'X'";

	my $hr = $self->sqlSelectAllHashref(
		[qw( day val )],
		"SUBSTRING(ts, 1, 10) AS day,
		 IF(m2status=0,
			$m2able_char_clause,
			'X'
		 ) AS val,
		 COUNT(*) AS c",
		"moderatorlog",
		"active=1",
		"GROUP BY day, val"
	);

	return $hr;
}

########################################################
sub getReverseMods {
	my($self, $options) = @_;

	# Double-check that options are numeric because we're going to
	# drop them directly into the SQL.
	for my $key (keys %$options) {
		$options->{$key} =~ s/[^\d.-]+//g;
	}

	my $down5 =     0.5;	$down5 = $options->{down5} if defined $options->{down5};
	my $upmax =     0  ;	$upmax = $options->{upmax} if defined $options->{upmax};
	my $upsub =     3  ;	$upsub = $options->{upsub} if defined $options->{upsub};
	my $upmul =     2  ;	$upmul = $options->{upmul} if defined $options->{upmul};
	my $unm2able =  0.5;	$unm2able = $options->{unm2able} if defined $options->{unm2able};
	my $denomadd =  4  ;	$denomadd = $options->{denomadd} if defined $options->{denomadd};
	my $limit =    12  ;	$limit = $options->{limit} if defined $options->{limit};
	my $min_tokens = -50; # fudge factor: only users who are likely to mod soon

	my $reasons = $self->getReasons();
	my @reasons_m2able = grep { $reasons->{$_}{m2able} } keys %$reasons;
	my $reasons_m2able = join(",", @reasons_m2able);
	my $m2able_score_clause = $reasons_m2able
		? "IF( moderatorlog.reason IN ($reasons_m2able), 0, $unm2able )"
		: "0";
	my $ar = $self->sqlSelectAllHashrefArray(
		"moderatorlog.uid AS muid,
		 nickname, tokens, users_info.karma AS karma,
		 ( SUM( IF( moderatorlog.val=-1,
				IF(points=5, $down5, 0),
				IF(points<=$upmax, $upsub-points*$upmul, 0) ) )
		  +SUM( $m2able_score_clause )
		 )/(COUNT(*)+$denomadd) AS score,
		 IF(MAX(moderatorlog.ts) > DATE_SUB(NOW(), INTERVAL 24 HOUR),
			1, 0) AS isrecent",
		"moderatorlog, comments, users, users_info",
		"comments.cid=moderatorlog.cid
		 AND users.uid=moderatorlog.uid
		 AND users_info.uid=moderatorlog.uid
		 AND moderatorlog.active
		 AND tokens >= $min_tokens",
		"GROUP BY muid ORDER BY score DESC, karma, tokens, muid LIMIT $limit",
	);
	for my $rm (@$ar) {
		$rm->{score} = sprintf("%0.3f", $rm->{score});
	}

	return $ar;
}

########################################################
sub countErrorStatuses {
	my($self, $options) = @_;

	my $where = "status BETWEEN 500 AND 599";

	$self->sqlSelect("COUNT(id)", "accesslog_temp_errors", $where);
}

########################################################
sub countByStatus {
	my($self, $status, $options) = @_;

	my $where = "status = '$status'";

	$self->sqlSelect("COUNT(id)", "accesslog_temp_errors", $where);
}

########################################################
sub getErrorStatuses {
	my($self, $op, $options) = @_;

	my $where = "status BETWEEN 500 AND 599";
	$where .= " AND op='$op'"			if $op;
	$where .= " AND skid='$options->{skid}'"	if $options->{skid};

	$self->sqlSelectAllHashrefArray(
		"status, COUNT(op) AS count, op",
		"accesslog_temp_errors",
		$where,
		"GROUP BY status ORDER BY status");
}

########################################################
sub getStoryHitsForDay {
	my ($self, $day, $options) = @_;
	my $sids = $self->sqlSelectAllHashrefArray("sid,hits","stories","day_published=".$self->sqlQuote($day));
	return $sids;
}

########################################################
sub getDaysOfUnarchivedStories {
	my($self, $options) = @_;
	my $max_days = $options->{max_days} || 180;
	my $days = $self->sqlSelectColArrayref(
		"day_published",
		"stories",
		"is_archived = 'no' AND primaryskid != 0",
		"GROUP BY day_published ORDER BY day_published DESC LIMIT $max_days");
	return $days;
}

########################################################
sub getAverageCommentCountPerStoryOnDay {
	my($self, $day, $options) = @_;
	my $col = "AVG(commentcount)";
	my $where = " DATE_FORMAT(time,'%Y-%m-%d') = '$day' ";
	$where .= " AND primaryskid = '$options->{skid}' " if $options->{skid};
	return $self->sqlSelect($col, "stories", $where);
}

########################################################
sub getAverageHitsPerStoryOnDay {
	my($self, $day, $pages, $other) = @_;
	my $numStories = $self->getNumberStoriesPerDay($day, $other);
	return $numStories ? $pages / $numStories : 0;
}

########################################################
sub getNumberStoriesPerDay {
	my($self, $day, $options) = @_;
	my $col = "COUNT(*)";
	my $where = " DATE_FORMAT(time,'%Y-%m-%d') = '$day' ";
	$where .= " AND primaryskid = '$options->{skid}' " if $options->{skid};
	return $self->sqlSelect($col, "stories", $where);

}

########################################################
sub getCommentsByDistinctIPID {
	my($self, $options) = @_;

	my $where = "date $self->{_day_between_clause}";
	$where .= " AND discussions.id = comments.sid
		    AND discussions.primaryskid= '$options->{skid}'"
		if $options->{skid};

	my $tables = 'comments';
	$tables .= ", discussions" if $options->{skid};

	my $used = $self->sqlSelectColArrayref(
		'ipid',
		$tables, 
		$where,
		'',
		{ distinct => 1 }
	);
}

########################################################
sub countCommentsByDistinctIPIDPerAnon {
	my($self, $options) = @_;
	my $constants = getCurrentStatic();

	my $where = "date $self->{_day_between_clause}";
	$where .= " AND discussions.id = comments.sid
		    AND discussions.primaryskid = '$options->{skid}'"
		if $options->{skid};

	my $tables = 'comments';
	$tables .= ", discussions" if $options->{skid};

	my $ipid_uid_hr = $self->sqlSelectAllHashref(
		[qw( ipid uid )],
		"ipid, comments.uid AS uid, COUNT(*) AS c",
		$tables, 
		$where,
		"GROUP BY ipid, uid"
	);
	return (0, 0, 0) unless $ipid_uid_hr && scalar keys %$ipid_uid_hr;

	my($ipids_anon_only, $ipids_loggedin_only, $ipids_both) = (0, 0, 0);
	my($comments_anon_only, $comments_loggedin_only, $comments_both) = (0, 0, 0);
	my $ac_uid = $constants->{anonymous_coward_uid};
	for my $ipid (keys %$ipid_uid_hr) {
		my @uids = keys %{$ipid_uid_hr->{$ipid}};
		my($c, $c_anon, $c_loggedin) = (0, 0, 0);
		for my $uid (@uids) {
			$c += $ipid_uid_hr->{$ipid}{$uid}{c};
		}
		if ($ipid_uid_hr->{$ipid}{$ac_uid}) {
			# At least one post by AC.
			if (scalar(@uids) > 1) {
				++$ipids_both;
				$comments_both += $c;
			} else {
				++$ipids_anon_only;
				$comments_anon_only += $c;
			}
		} else {
			++$ipids_loggedin_only;
			$comments_loggedin_only += $c;
		}
	}
	return ($ipids_anon_only, $ipids_loggedin_only, $ipids_both,
		$comments_anon_only, $comments_loggedin_only, $comments_both);
}

########################################################
# XXX Maybe bring this back once Slash is entirely converted
# to srcids. - Jamie 2005/07/21
#sub countCommentsFromProxyAnon {
#	my($self, $options) = @_;
#	my $constants = getCurrentStatic();
#
#	my $where = "date $self->{_day_between_clause}";
#	$where .= " AND discussions.id = comments.sid
#		    AND discussions.primaryskid = '$options->{skid}'"
#		if $options->{skid};
#
#	my $tables = 'comments, accesslist';
#	$tables .= ", discussions" if $options->{skid};
#
#	my $c = $self->sqlCount(
#		$tables,
#		"$where
#		 AND comments.ipid = accesslist.ipid
#		 AND accesslist.now_proxy = 'yes'
#		 AND comments.uid = $constants->{anonymous_coward_uid}");
#	return $c;
#}

########################################################
sub countCommentsByDiscussionType {
	my($self) = @_;
	my $constants = getCurrentStatic();

	my $return_hr = { };

	# First count comments posted to polls.
	if ($constants->{plugin}{PollBooth}) {
		$return_hr->{polls} = $self->sqlSelect(
			"COUNT(*), IF(pollquestions.discussion IS NULL, 'no', 'yes') AS ispoll",
			"comments,
			 discussions LEFT JOIN pollquestions
				ON discussions.id=pollquestions.discussion",
			"comments.date $self->{_day_between_clause}
				AND comments.sid=discussions.id",
			"GROUP BY ispoll HAVING ispoll='yes'"
		) || 0;
	} else {
		$return_hr->{polls} = 0;
	}

	# Now comments posted to journals.
	if ($constants->{plugin}{Journal}) {
		$return_hr->{journals} = $self->sqlSelect(
			"COUNT(*), IF(journals.discussion IS NULL, 'no', 'yes') AS isjournal",
			"comments,
			 discussions LEFT JOIN journals
				ON discussions.id=journals.discussion",
			"comments.date $self->{_day_between_clause}
				AND comments.sid=discussions.id",
			"GROUP BY isjournal HAVING isjournal='yes'"
		) || 0;
	} else {
		$return_hr->{journals} = 0;
	}

	# Don't forget comments posted to stories.
	$return_hr->{stories} = $self->sqlSelect(
		"COUNT(*), IF(stories.discussion IS NULL, 'no', 'yes') AS isstory",
		"comments,
		 discussions LEFT JOIN stories
			ON discussions.id=stories.discussion",
		"comments.date $self->{_day_between_clause}
			AND comments.sid=discussions.id",
		"GROUP BY isstory HAVING isstory='yes'"
	) || 0;

	# Whatever's left must be user-created discussions.
	my $total = $self->sqlCount("comments", "date $self->{_day_between_clause}");
	$return_hr->{user} = $total -
		( $return_hr->{polls} + $return_hr->{journals} + $return_hr->{stories} );

	return $return_hr;
}

########################################################
sub getCommentsByDistinctUIDPosters {
	my($self, $options) = @_;

	my $skid_where = "";
	$skid_where = " AND discussions.id = comments.sid
			   AND discussions.primaryskid = '$options->{skid}'"
		if $options->{skid};

	my $tables = 'comments';
	$tables .= ", discussions" if $options->{skid};

	my $used = $self->sqlSelect(
		"COUNT(DISTINCT uid)", $tables, 
		"date $self->{_day_between_clause}
		$skid_where",
		'',
		{ }
	);
}

########################################################
sub getAdminModsInfo {
	my($self) = @_;

	# First get the list of admins.
	my $admin_uids_ar = $self->sqlSelectColArrayref(
		"uid", "users", "seclev > 1");
	my $admin_uids_str = join(",", sort { $a <=> $b } @$admin_uids_ar);
	my $nickname_hr = $self->sqlSelectAllKeyValue(
		"uid, nickname",
		"users",
		"uid IN ($admin_uids_str)");

	# First get the count of upmods and downmods performed by each admin.
	my $m1_uid_val_hr = $self->sqlSelectAllHashref(
		[qw( uid val )],
		"uid, val, COUNT(*) AS count",
		"moderatorlog",
		"uid IN ($admin_uids_str)
		 AND ts $self->{_day_between_clause}",
		"GROUP BY moderatorlog.uid, val"
	);
	for my $uid (keys %$m1_uid_val_hr) {
		for my $val (keys %{ $m1_uid_val_hr->{$uid} }) {
			$m1_uid_val_hr->{$uid}{$val}{nickname} = $nickname_hr->{$uid};
		}
	}

	# Now get a count of fair/unfair counts for each admin.
	my $m2_uid_val_hr = $self->sqlSelectAllHashref(
		[qw( uid val )],
		"moderatorlog.uid AS uid, metamodlog.val AS val, COUNT(*) AS count",
		"moderatorlog, metamodlog",
		"moderatorlog.uid IN ($admin_uids_str)
		 AND metamodlog.mmid=moderatorlog.id 
		 AND metamodlog.ts $self->{_day_between_clause}",
		"GROUP BY moderatorlog.uid, metamodlog.val"
	);
	for my $uid (keys %$m2_uid_val_hr) {
		for my $val (keys %{ $m2_uid_val_hr->{$uid} }) {
			$m2_uid_val_hr->{$uid}{$val}{nickname} = $nickname_hr->{$uid};
		}
	}

	# If nothing for either, no data to return.
	return { } if !%$m1_uid_val_hr && !%$m2_uid_val_hr;

	# Get the history of moderation fairness for all admins from the
	# last month.  This reads the last 30 days worth of stats_daily
	# data (not counting today, which will be added to that table
	# shortly).  Set up both the {count} and {nickname} fields for
	# each combination of uid and 1/-1 fairness.
	my $m2_history_mo_hr = $self->sqlSelectAllHashref(
		"name",
		"name, SUM(value) AS count",
		"stats_daily",
		"name LIKE 'm%fair_%' AND day > DATE_SUB(NOW(), INTERVAL 732 HOUR)",
		"GROUP BY name"
	);
	my $m2_uid_val_mo_hr = { };
	for my $name (keys %$m2_history_mo_hr) {
		my($fairness, $uid) = $name =~ /^m2_((?:un)?fair)_admin_(\d+)$/;
		next unless defined($fairness);
		$fairness = ($fairness eq 'unfair') ? -1 : 1;
		$m2_uid_val_mo_hr->{$uid}{$fairness}{count} =
			$m2_history_mo_hr->{$name}{count};
	}
	if (%$m2_uid_val_mo_hr) {
		# Get nicknames for every user that shows up in the stats
		# for the last 30 days (which may be different from the
		# admins we have now).
		my $m2_uid_nickname = $self->sqlSelectAllKeyValue(
			"uid, nickname",
			"users",
			"uid IN (" . join(",", keys %$m2_uid_val_mo_hr) . ")"
		);
		for my $uid (keys %$m2_uid_nickname) {
			for my $fairness (qw( -1 1 )) {
				$m2_uid_val_mo_hr->{$uid}{$fairness}{nickname} =
					$m2_uid_nickname->{$uid};
				$m2_uid_val_mo_hr->{$uid}{$fairness}{count} ||= 0;
				$m2_uid_val_mo_hr->{$uid}{$fairness}{count} +=
					($m2_uid_val_hr->{$uid}{$fairness}{count} || 0);
			}
		}
	}

	# For comparison, get the same stats for all users on the site and
	# add them in as a phony admin user that sorts itself alphabetically
	# last.  Hack, hack.
	my($total_nick, $total_uid) = ("~Day Total", 0);
	my $m1_val_hr = $self->sqlSelectAllHashref(
		"val",
		"val, COUNT(*) AS count",
		"moderatorlog",
		"ts $self->{_day_between_clause}",
		"GROUP BY val"
	);
	$m1_uid_val_hr->{$total_uid} = {
		uid =>	$total_uid,
		  1 =>	{ nickname => $total_nick, count => $m1_val_hr-> {1}{count} },
		 -1 =>	{ nickname => $total_nick, count => $m1_val_hr->{-1}{count} },
	};
	my $m2_val_hr = $self->sqlSelectAllHashref(
		"val",
		"val, COUNT(*) AS count",
		"metamodlog",
		"ts $self->{_day_between_clause}",
		"GROUP BY val"
	);
	$m2_uid_val_hr->{$total_uid} = {
		uid =>	$total_uid,
		  1 =>	{ nickname => $total_nick, count => $m2_val_hr-> {1}{count} },
		 -1 =>	{ nickname => $total_nick, count => $m2_val_hr->{-1}{count} },
	};

	# Build a hashref with one key for each admin user, and subkeys
	# that give data we will want for stats.
	my($nup, $ndown, $nfair, $nunfair, $percent);
	my @m1_keys = sort keys %$m1_uid_val_hr;
	my @m2_keys = sort keys %$m2_uid_val_hr;
	my %all_keys = map { $_ => 1 } @m1_keys, @m2_keys;
	my @all_keys = sort keys %all_keys;
	my $hr = { };
	for my $uid (@m1_keys) {
		my $nickname = $m1_uid_val_hr->{$uid} {1}{nickname}
			|| $m1_uid_val_hr->{$uid}{-1}{nickname}
			|| "";
		next unless $nickname;
		$nup   = $m1_uid_val_hr->{$uid} {1}{count} || 0;
		$ndown = $m1_uid_val_hr->{$uid}{-1}{count} || 0;
		$percent = ($nup+$ndown > 0)
			? $nup*100/($nup+$ndown)
			: 0;
		# Add the m1 data for this admin.
		$hr->{$nickname}{uid} = $uid;
		$hr->{$nickname}{m1_up} = $nup;
		$hr->{$nickname}{m1_down} = $ndown;
		# If this admin had m1 activity today but no m2 activity,
		# blank out that field.
		if (!exists($m2_uid_val_hr->{$uid})) {
			# $hr->{$nickname}{m2_fair} = 0;
			# $hr->{$nickname}{m2_unfair} = 0;
		}
	}
	for my $uid (@all_keys) {
		my $nickname =
			   $m2_uid_val_hr->{$uid} {1}{nickname}
			|| $m2_uid_val_hr->{$uid}{-1}{nickname}
			|| $m2_uid_val_mo_hr->{$uid} {1}{nickname}
			|| $m2_uid_val_mo_hr->{$uid}{-1}{nickname}
			|| "";
		next unless $nickname;
		$nfair   = $m2_uid_val_hr->{$uid} {1}{count} || 0;
		$nunfair = $m2_uid_val_hr->{$uid}{-1}{count} || 0;
		$percent = ($nfair+$nunfair > 0)
			? $nunfair*100/($nfair+$nunfair)
			: 0;
		# Add the m2 data for this admin.
		$hr->{$nickname}{uid} = $uid;
		# Also calculate overall-month percentage.
		my $nfair_mo   = $m2_uid_val_mo_hr->{$uid} {1}{count} || 0;
		my $nunfair_mo = $m2_uid_val_mo_hr->{$uid}{-1}{count} || 0;
		$percent = ($nfair_mo+$nunfair_mo > 0)
			? $nunfair_mo*100/($nfair_mo+$nunfair_mo)
			: 0;
		# Set another few data points.
		$hr->{$nickname}{m2_fair} = $nfair;
		$hr->{$nickname}{m2_unfair} = $nunfair;
		$hr->{$nickname}{m2_fair_mo} = $nfair_mo;
		$hr->{$nickname}{m2_unfair_mo} = $nunfair_mo;
		# If this admin had m2 activity today but no m1 activity,
		# blank out that field.
		if (!exists($m1_uid_val_hr->{$uid})) {
			# Not really necessary
			# $hr->{$nickname}{m1_up} = 0;
			# $hr->{$nickname}{m1_down} = 0;
		}
	}

	return $hr;
}

########################################################
sub countSubmissionsByDay {
	my($self, $options) = @_;

	my $where = "time $self->{_day_between_clause}";
	$where .= " AND skid = '$options->{skid}'" if $options->{skid};

	my $used = $self->sqlCount(
		'submissions', 
		$where
	);
	return $used;
}

########################################################
sub countSubmissionsByCommentIPID {
	my($self, $ipids, $options) = @_;
	return unless @$ipids;
	my $slashdb = getCurrentDB();
	my $in_list = join(",", map { $slashdb->sqlQuote($_) } @$ipids);

	my $where = "time $self->{_day_between_clause}
		AND ipid IN ($in_list)";
	$where .= " AND skid = '$options->{skid}'" if $options->{skid};

	my $used = $self->sqlCount(
		'submissions', 
		$where
	);
	return $used;
}

########################################################
sub countModeratorLogByVal {
	my($self) = @_;

	my $modlog_hr = $self->sqlSelectAllHashref(
		"val",
		"val, SUM(spent) AS spent, COUNT(*) AS count",
		"moderatorlog",
		"ts $self->{_day_between_clause}",
		"GROUP BY val"
	);
	
	return $modlog_hr;
}

########################################################
sub countCommentsDaily {
	my($self, $options) = @_;

	my $tables = 'comments';

	my $skid_where = "";
	$skid_where = " AND discussions.id = comments.sid
			   AND discussions.primaryskid = '$options->{skid}'"
		if $options->{skid};
	
	# Count comments posted yesterday... using a primary key,
	# if it'll save us a table scan.  On Slashdot this cuts the
	# query time from about 12 seconds to about 0.8 seconds.
	my $cid_limit_clause = "";
	my $max_cid = $self->sqlSelect("MAX(comments.cid)", $tables);
	if ($max_cid > 300_000) {
		# No site can get more than 100K comments a day in
		# all its skins combined.  It is decided.  :)
		$cid_limit_clause = " AND cid > " . ($max_cid-100_000);
	}

	my $comments = $self->sqlSelect(
		"COUNT(*)",
		"comments",
		"date $self->{_day_between_clause}
		 $cid_limit_clause $skid_where"
	);

	return $comments; 
}


sub getSummaryStats {
	my ($self, $options) = @_;
	my @where;
	
	my $no_op = $options->{no_op} || [ ];
	$no_op = [ $no_op ] if $options->{no_op} && !ref($no_op);
	if (@$no_op) {
		my $op_not_in = join(",", map { $self->sqlQuote($_) } @$no_op);
		push @where,  "op NOT IN ($op_not_in)";
	}

	push @where, "op = ".$self->sqlQuote($options->{op}) if $options->{op};
	push @where, "skid = ".$self->sqlQuote($options->{skid}) if $options->{skid};

	my $where = join ' AND ', @where;
	my $table_suffix = $options->{table_suffix} || '';
	
	$self->sqlSelectHashref(
		"COUNT(DISTINCT host_addr) AS cnt, COUNT(DISTINCT uid) AS uids,
		 COUNT(*) AS pages, SUM(bytes) AS bytes",
		"accesslog_temp$table_suffix",
		$where);
}


########################################################
sub getSectionSummaryStats {
	my ($self, $options) = @_;
	my @where;
	push @where, "skid IN (" . join(',', map { $self->sqlQuote($_)} @{$options->{skids}}) . ")" if ref $options->{skids} eq "ARRAY";

	my $no_op = $options->{no_op} || [ ];
	$no_op = [ $no_op ] if $options->{no_op} && !ref($no_op);
	if (@$no_op) {
		my $op_not_in = join(",", map { $self->sqlQuote($_) } @$no_op);
		push @where,  "op NOT IN ($op_not_in)";
	}

	my $table_suffix = $options->{table_suffix};
	
	my $where_clause = join ' AND ', @where;
	$self->sqlSelectAllHashref("skid", "skid, COUNT(DISTINCT host_addr) AS cnt, COUNT(DISTINCT uid) AS uids, COUNT(*) as pages, SUM(bytes) as bytes", "accesslog_temp$table_suffix", $where_clause, "GROUP BY skid");
}

########################################################
sub getPageSummaryStats {
	my ($self, $options) = @_;
	my @where;
	push @where, "op IN (" . join(',', map { $self->sqlQuote($_)} @{$options->{ops}}) . ")" if ref $options->{ops} eq "ARRAY";
	my $where_clause = join ' AND ', @where;
	$self->sqlSelectAllHashref("op", "op, COUNT(DISTINCT host_addr) AS cnt, COUNT(DISTINCT uid) AS uids, COUNT(*) AS pages, SUM(bytes) AS bytes", "accesslog_temp", $where_clause, "GROUP BY op");

}
########################################################
sub getSectionPageSummaryStats {
	my ($self, $options) = @_;
	my @where;
	push @where, "op IN (" . join(',', map { $self->sqlQuote($_)} @{$options->{ops}}) . ")" if ref $options->{ops} eq "ARRAY";
	push @where, "skid IN (" . join(',', map { $self->sqlQuote($_)} @{$options->{skids}}) . ")" if ref $options->{skids} eq "ARRAY";
	my $where_clause = join ' AND ', @where;
	$self->sqlSelectAllHashref(["skid","op"], "op, skid, COUNT(DISTINCT host_addr) AS cnt, COUNT(DISTINCT uid) AS uids, COUNT(*) AS pages, SUM(bytes) AS bytes", "accesslog_temp", $where_clause, "GROUP BY op, skid");
}

########################################################
sub countBytesByPage {
	my($self, $op, $options) = @_;

	my $where = "1=1 ";
	$where .= " AND op='$op'"
		if $op;
	$where .= " AND skid='$options->{skid}'"
		if $options->{skid};

	# The "no_op" option can take either a scalar for one op to exclude,
	# or an arrayref of multiple ops to exclude.
	my $no_op = $options->{no_op} || [ ];
	$no_op = [ $no_op ] if $options->{no_op} && !ref($no_op);
	if (@$no_op) {
		my $op_not_in = join(",", map { $self->sqlQuote($_) } @$no_op);
		$where .= " AND op NOT IN ($op_not_in)";
	}
	
	my $table_suffix = $options->{table_suffix} || '';

	$self->sqlSelect("SUM(bytes)", "accesslog_temp$table_suffix", $where);
}

########################################################
sub countBytesByPages {
	my($self, $options) = @_;
	$self->sqlSelectAllHashref("op","op, SUM(bytes) as bytes", "accesslog_temp", '', "GROUP BY op");
}

########################################################
sub countUsersMultiTable {
	my ($self, $options) = @_;
	$self->sqlDo("DELETE FROM accesslog_build_unique_uid");
	my $tables = $options->{tables} || [];

	foreach my $table (@$tables) {
		$self->sqlDo("INSERT IGNORE INTO accesslog_build_unique_uid SELECT DISTINCT uid FROM $table");
	}
	$self->sqlCount("accesslog_build_unique_uid");
}

########################################################

sub countUniqueIPs {
	my ($self, $options) = @_;
	my $where;
	$where = "anon=".$self->sqlQuote($options->{anon}) if $options->{anon};
	$self->sqlSelect("COUNT(DISTINCT host_addr)", "accesslog_temp_host_addr", $where);
}
########################################################
sub countUsersByPage {
	my($self, $op, $options) = @_;
	my $where = "1=1 ";
	$where .= "AND op='$op' "
		if $op;
	$where .= " AND skid='$options->{skid}' "
		if $options->{skid};
	$where = "($where) AND $options->{extra_where_clause}"
		if $options->{extra_where_clause};
	my $no_op = $options->{no_op} || [ ];
	$no_op = [ $no_op ] if $options->{no_op} && !ref($no_op);
	if (@$no_op) {
		my $op_not_in = join(",", map { $self->sqlQuote($_) } @$no_op);
		$where .= " AND op NOT IN ($op_not_in)";
	}
	my $table_suffix = $options->{table_suffix};
		

	$self->sqlSelect("COUNT(DISTINCT uid)", "accesslog_temp$table_suffix", $where);
}

########################################################
sub countUsersByPages {
	my($self, $options) = @_;
	$self->sqlSelectAllHashref("op", "op, COUNT(DISTINCT uid) AS uids", "accesslog_temp", '', "GROUP BY op");
}

########################################################
sub countDailyByPage {
	my($self, $op, $options) = @_;
	my $constants = getCurrentStatic();
	$options ||= {};

	my $where = "1=1 ";
	$where .= " AND op='$op'"
		if $op;
	$where .= " AND skid='$options->{skid}'"
		if $options->{skid};
	$where .= " AND static='$options->{static}'"
		if $options->{static};
	$where .=" AND uid = $constants->{anonymous_coward_uid} " if $options->{user_type} && $options->{user_type} eq "anonymous";
	$where .=" AND uid != $constants->{anonymous_coward_uid} " if $options->{user_type} && $options->{user_type} eq "logged-in";

	# The "no_op" option can take either a scalar for one op to exclude,
	# or an arrayref of multiple ops to exclude.
	my $no_op = $options->{no_op} || [ ];
	$no_op = [ $no_op ] if $options->{no_op} && !ref($no_op);
	if (@$no_op) {
		my $op_not_in = join(",", map { $self->sqlQuote($_) } @$no_op);
		$where .= " AND op NOT IN ($op_not_in)";
	}

	my $table_suffix = $options->{table_suffix} || '';

	$self->sqlSelect("COUNT(*)", "accesslog_temp$table_suffix", $where);
}

########################################################
sub countDailyByPages {
	my($self, $options) = @_;
	my $constants = getCurrentStatic();
	$options ||= {};

	$self->sqlSelectAllHashref("op", "op,count(*) AS cnt", "accesslog_temp", "", "GROUP BY op");
}

########################################################
sub countFromRSSStatsBySections {
	my ($self) = @_;
	$self->sqlSelectAllHashref("skid",
		"skid, count(*) AS cnt, COUNT(DISTINCT uid) AS uids, COUNT(DISTINCT host_addr) AS ipids",
		"accesslog_temp",
		"referer='rss'",
		"GROUP BY skid");
}

########################################################
sub countDailyByPageDistinctIPID {
	# This is so lame, and so not ANSI SQL -Brian
	my($self, $op, $options) = @_;
	my $constants = getCurrentStatic();

	my $where = "1=1 ";
	$where .= "AND op='$op' "
		if $op;
	$where .= " AND skid='$options->{skid}' "
		if $options->{skid};
	$where .=" AND uid = $constants->{anonymous_coward_uid} " if $options->{user_type} && $options->{user_type} eq "anonymous";
	$where .=" AND uid != $constants->{anonymous_coward_uid} " if $options->{user_type} && $options->{user_type} eq "logged-in";

	my $no_op = $options->{no_op} || [ ];
	$no_op = [ $no_op ] if $options->{no_op} && !ref($no_op);
	if (@$no_op) {
		my $op_not_in = join(",", map { $self->sqlQuote($_) } @$no_op);
		$where .= " AND op NOT IN ($op_not_in)";
	}
	my $table_suffix = $options->{table_suffix};
	
	$self->sqlSelect("COUNT(DISTINCT host_addr)", "accesslog_temp$table_suffix", $where);
}

########################################################
sub countDailyByPageDistinctIPIDs {
	my($self, $options) = @_;
	my $constants = getCurrentStatic();
	
	$self->sqlSelectAllHashref("op", "op, COUNT(DISTINCT host_addr) AS cnt", "accesslog_temp", "", "GROUP BY op");
}



########################################################
sub countDailyStoriesAccess {
	my($self) = @_;
	my $qlid = $self->_querylog_start('SELECT', 'accesslog_temp');
	my $c = $self->sqlSelectMany("dat, COUNT(*), op", "accesslog_temp",
		"op='article'",
		"GROUP BY dat");

	my %articles; 
	while (my($sid, $cnt) = $c->fetchrow) {
		$articles{$sid} = $cnt;
	}
	$c->finish;
	$self->_querylog_finish($qlid);
	return \%articles;
}

########################################################
sub countDailySecure {
	my($self) = @_;
	return $self->sqlCount("accesslog_temp", "secure=1");
}

########################################################
sub getRecentSubscribers {
	my($self) = @_;
	my $constants = getCurrentStatic();
	return 0 unless $constants->{subscribe};
	my $subscribers_all = $self->sqlSelectColArrayref(
		"uid",
		"users_hits",
		"hits_paidfor > hits_bought
		 AND lastclick >= DATE_SUB(NOW(), INTERVAL 48 HOUR)",
	);
	return [ ] unless $subscribers_all && @$subscribers_all;
	my $uid_list = join(", ", @$subscribers_all);
	my $subscribers = $self->sqlSelectColArrayref(
		"uid",
		"users",
		"uid in ($uid_list) AND seclev < 100");

	return $subscribers;
}

########################################################
sub countDailySubscribers {
	my($self) = @_;
	my $constants = getCurrentStatic();
	return 0 unless $constants->{subscribe};
	my $count = $self->sqlCount("accesslog_temp_subscriber");
	return $count;
}

########################################################
sub getStat {
	my($self, $name, $day, $skid) = @_;
	$skid ||= 0;
	my $name_q = $self->sqlQuote($name);
	my $day_q =  $self->sqlQuote($day);
	my $skid_q = $self->sqlQuote($skid);
	return $self->sqlSelect("value", "stats_daily",
		"name=$name_q AND day=$day_q AND skid=$skid_q");
}

########################################################
sub getStatToday {
	my($self, $name) = @_;
	my $name_q = $self->sqlQuote($name);
	return $self->sqlSelect("value + 0", "stats_daily",
		"name = $name_q AND day = '$self->{_day}'");
}

########################################################
sub getStatLastNDays {
	my($self, $name, $days) = @_;
	my $name_q = $self->sqlQuote($name);
	return $self->sqlSelect("AVG(value) + 0", "stats_daily",
		"name = $name_q
		 AND day BETWEEN DATE_SUB('$self->{_day}', INTERVAL $days DAY) AND '$self->{_day}'");
}

########################################################
sub getDurationByStaticOpHour {
	my($self, $options) = @_;

	my @ops = qw( index article comments metamod users rss );
	@ops = @{$options->{ops}} if $options->{ops} && @{$options->{ops}};
	my $ops = join(", ", map { $self->sqlQuote($_) } @ops);

	# First get the stats that are easy, the AVG() and STDDEV()
	# which the DB feeds to us.
	my $hr = $self->sqlSelectAllHashref(
		[qw( static op hour )],
		"static, op, HOUR(ts) AS hour,
		 COUNT(*) AS c,
		 AVG(duration) AS dur_mean, STDDEV(duration) AS dur_stddev",
		"accesslog_temp",
		"op IN ($ops)",
		"GROUP BY static, op, hour"
	);

	# Now we need the stats that are hard, the various percentiles
	# in the duration list for each static/localaddr key
	# (including the median, which is just the 50th %ile).

	# Pick a duration precision.  The more precise, the more data
	# to chew through.  I think 10 ms should be good enough and yet
	# not run us out of memory processing even Slashdot's log.
	my $precision = 0.010;

	my $ile_hr = $self->sqlSelectAllHashref(
		[qw( static op hour dur_round )],
		"static, op, HOUR(ts) AS hour,
		 ROUND(duration/$precision)*$precision AS dur_round,
		 COUNT(*) AS c",
		"accesslog_temp",
		"op IN ($ops)",
		"GROUP BY static, op, hour, dur_round"
	);

	_calc_percentiles($hr, $ile_hr);

	return $hr;
}

########################################################
sub getDurationByStaticLocaladdr {
	my($self) = @_;

	# First get the stats that are easy, the AVG() and STDDEV()
	# which the DB feeds to us.
	my $hr = $self->sqlSelectAllHashref(
		[qw( static local_addr )],
		"static, local_addr,
		 COUNT(*) AS c,
		 AVG(duration) AS dur_mean, STDDEV(duration) AS dur_stddev",
		"accesslog_temp",
		"",
		"GROUP BY static, local_addr"
	);

	# Now we need the stats that are hard, the various percentiles
	# in the duration list for each static/localaddr key
	# (including the median, which is just the 50th %ile).

	# Pick a duration precision.  The more precise, the more data
	# to chew through.  I think 10 ms should be good enough and yet
	# not run us out of memory processing even Slashdot's log.
	my $precision = 0.010;

	my $ile_hr = $self->sqlSelectAllHashref(
		[qw( static local_addr dur_round )],
		"static, local_addr,
		 ROUND(duration/$precision)*$precision AS dur_round,
		 COUNT(*) AS c",
		"accesslog_temp",
		"",
		"GROUP BY static, local_addr, dur_round"
	);

#use Data::Dumper; print Dumper $ile_hr;

	_calc_percentiles($hr, $ile_hr);

	return $hr;
}

sub _walk_keys {
	my($hr) = @_;
	my @hr_keys = keys %$hr;
	if (@hr_keys && !exists $hr->{$hr_keys[0]}{dur_round}) {
		# We need to recurse down at least one more
		# level.  Keep track of where we are.
		my @results = ( );
		for my $key (sort @hr_keys) {
			my @sub_results = ( );
			@sub_results = _walk_keys($hr->{$key}) if %{$hr->{$key}};
			for my $sub_r (@sub_results) {
				unshift @$sub_r, $key;
			}
			push @results, @sub_results;
		}
		return @results;
	} else {
		# This hashref's keys hold the data we want.
		# We don't want to return that data.
		return [ ];
	}
}

sub _calc_percentiles {
	my($main_hr, $ile_hr, $percentiles) = @_;

	# List of percentiles we want.  The expensive part is doing this
	# at all, so we might as well grab more than just the median!
	$percentiles = [qw( 10 50 90 95 99 )]
		if !$percentiles || !@$percentiles;

	# Go through a somewhat convoluted process to walk the keys of the
	# hashrefs, given that we have a scalar numeric that tells us how
	# deep those keys go.  Essentially we're doing an any-depth version
	# of "for $i {for $j {for $k ... } }".
	my @keysets = _walk_keys($ile_hr);
	while (my $keyset = shift @keysets) {

		# Each keyset is an arrayref that lists the keys needed
		# to walk down into $main_hr and $ile_hr to get to a
		# set of data that we want.  Use it to walk the hashrefs
		# $main_hr_entry and $ile_hr_entry down to that data.

		my $main_hr_entry = $main_hr;
		my $ile_hr_entry = $ile_hr;
		for my $key (@$keyset) {
			$main_hr_entry = $main_hr_entry->{$key};
			$ile_hr_entry = $ile_hr_entry->{$key};
		}

#print "main_hr_entry for keyset '@$keyset': " . Dumper($main_hr_entry);
#print "ile_hr_entry for keyset '@$keyset': " . Dumper($ile_hr_entry);

		my $cur_count = 0;
		my $total_count = $main_hr_entry->{c};
		next unless $total_count; # sanity check
		my $cur_duration = 0;
		# Get the list of all the rounded durations that we
		# had returned (for this value of static/localaddr).
		my @rounds = sort { $a <=> $b } keys %$ile_hr_entry;
		# Start counting with the current percentile at 0.
		# For each one that we need, walk up through the
		# list of rounded durations totalling up how many
		# hits took that long (or faster).  If the percentage
		# of hits out of total hits (for this value of
		# static/localaddr) equals or exceeds the percentile
		# that is needed, this duration corresponds to that
		# percentile.  Store it in the main hashref (not
		# ile_hr, it will be thrown away) with a key of
		# "ile_50" for the median, "ile_95" for the
		# 95th percentile, etc.
		my $cur_ile = 0;
		for my $ile_needed (@$percentiles) {
			my $ile_frac = $ile_needed/100;
			# Note, if we wanted to get really fancy in
			# this next while loop, we could also do
			# interpolation between this $cur_ile and
			# the next $cur_ile, effectively almost
			# doubling $precision.  I don't think it's
			# necessary;  our sample sets should be
			# plenty large enough and RAM is cheap.
			while ($cur_ile <= $ile_frac && @rounds) {
				$cur_duration = shift @rounds;
				$cur_count += $ile_hr_entry->{$cur_duration}{c};
				$cur_ile = $cur_count / $total_count;
			}
			my $ile_key = sprintf("dur_ile_%02d", $ile_needed);
			$main_hr_entry->{$ile_key} = $cur_duration;
		}
	}
}

########################################################
sub getDailyScoreTotals {
	my($self, $scores) = @_;

	return $self->sqlSelectAllHashref(
		"points",
		"points, COUNT(*) AS c",
		"comments",
		"date $self->{_day_between_clause}",
		"GROUP BY points");
}


########################################################
sub getTopBadPasswordsByUID{
	my($self, $options) = @_;
	my $limit = $options->{limit} || 10;
	my $min = $options->{min};

	my $other = "GROUP BY uid ";
	$other .= " HAVING count >= $options->{min}" if $min;
	$other .= "  ORDER BY count DESC LIMIT $limit";

	# XXXTIMESTAMP The _ts_between_clause works for MySQL 4.0 but
	# not 4.1, which formats timestamps as YYYY-MM-DD HH:MM:SS.
	return $self->sqlSelectAllHashrefArray(
		"nickname, users.uid AS uid, count(DISTINCT password) AS count",
		"badpasswords, users",
		"ts $self->{_ts_between_clause} AND users.uid = badpasswords.uid",
		$other);
}

########################################################
sub getTopBadPasswordsByIP{
	my($self, $options) = @_;
	my $limit = $options->{limit} || 10;
	my $min = $options->{min};

	my $other = "GROUP BY ip";
	$other .= " HAVING count >= $options->{min}" if $min;
	$other .= "  ORDER BY count DESC LIMIT $limit";
	
	# XXXTIMESTAMP The _ts_between_clause works for MySQL 4.0 but
	# not 4.1, which formats timestamps as YYYY-MM-DD HH:MM:SS.
	return $self->sqlSelectAllHashrefArray(
		"ip, count(DISTINCT password) AS count",
		"badpasswords",
		"ts $self->{_ts_between_clause}",
		$other);
}

########################################################
sub getTopBadPasswordsBySubnet{
	my($self, $options) = @_;
	my $limit = $options->{limit} || 10;
	my $min = $options->{min};

	my $other = "GROUP BY subnet";
	$other .= " HAVING count >= $options->{min}" if $min;
	$other .= "  ORDER BY count DESC LIMIT $limit";

	# XXXTIMESTAMP The _ts_between_clause works for MySQL 4.0 but
	# not 4.1, which formats timestamps as YYYY-MM-DD HH:MM:SS.
	return $self->sqlSelectAllHashrefArray(
		"subnet, count(DISTINCT password) AS count",
		"badpasswords",
		"ts $self->{_ts_between_clause}",
		$other);
}

########################################################
sub getTailslash {
	my($self) = @_;
	my $retval =         "Hour        Hits        Hits/sec\n";
	my $sprintf_format = "  %02d    %8d          %6.2f    %-40s\n";

        my $page_ar = $self->sqlSelectAllHashrefArray(
                "HOUR(ts) AS hour, COUNT(*) AS c",
                "accesslog_temp",
                "",
                "GROUP BY hour ORDER BY hour ASC");
		
       
	my $rss_ar = $self->sqlSelectAllHashrefArray(
		"HOUR(ts) AS hour, COUNT(*) AS c",
		"accesslog_temp_rss",
		"",
		"GROUP BY hour ORDER BY hour ASC");

	my $total = {};

	foreach my $item (@$page_ar) {
		$total->{$item->{hour}} += $item->{c};		
	}

	foreach my $item (@$rss_ar) {
		$total->{$item->{hour}} += $item->{c};		
	}

	my $max_count = 0;
	for my $hr (keys %$total) {
		$max_count = $total->{$hr} if $total->{$hr} > $max_count;
	}
	for my $hr (sort {$a <=> $b} keys %$total) {
		my $hour = $hr;
		my $count = $total->{$hr};
		$retval .= sprintf( $sprintf_format,
			$hour, $count, $count/3600,
			("#" x (40*$count/$max_count)) );
	}
	return $retval;
}

########################################################
# Note, we are carrying the misspelling of "referrer" over from
# the HTTP spec.
sub getTopReferers {
	my($self, $options) = @_;

	my $count = $options->{count} || 10;
	my $where;
	if ($options->{include_local}) {
		$where = "";
	} else {
		my $gSkin = getCurrentSkin();
		$where = " AND referer NOT REGEXP '$gSkin->{basedomain}'";
	}

	return $self->sqlSelectAll(
		"DISTINCT SUBSTRING_INDEX(referer,'/',3) AS referer, COUNT(id) AS c",
		"accesslog_temp",
		"referer IS NOT NULL AND LENGTH(referer) > 0 AND referer LIKE 'http%' $where ",
		"GROUP BY referer ORDER BY c DESC, referer LIMIT $count"
	);
}

########################################################
sub countSfNetIssues {
	my($self, $group_id) = @_;
	my $constants = getCurrentStatic();
	my $url = "http://sf.net/export/projhtml.php?group_id=$group_id&mode=full&no_table=1";
	my $ua = new LWP::UserAgent;
	my $request = new HTTP::Request('GET', $url);
        $ua->proxy(http => $constants->{http_proxy}) if $constants->{http_proxy};
        $ua->timeout(30);
        my $result = $ua->request($request);
	my $content = $result->is_success ? $result->content : "";
	if (!$content) {
		return { };
	}
	my $hr = { };
	while ($content =~ m{
		>
		([\w\s]+)
		</A>
		\s*
		\( \s* <B>
		(\d+) \s+ open \s* / \s* (\d+) \s* total
		</B> \s* \)
	}gx) {
		my($tracker, $open, $total) = ($1, $2, $3);
		$hr->{$tracker}{open} = $open;
		$hr->{$tracker}{total} = $total;
	}
	return $hr;
}

#######################################################

sub getRelocatedLinksSummary {
	my($self, $options) = @_;
	$options ||= {};
	my $limit = $options->{limit} ? "LIMIT $options->{limit}" : '';
	return $self->sqlSelectAllHashrefArray(
		'query_string, COUNT(query_string) AS cnt',
		'accesslog_temp_errors',
		"op='relocate-undef' AND dat = '/relocate.pl'",
		"GROUP BY query_string ORDER BY cnt DESC $limit");
}

########################################################
#  expects arrayref returned by getRelocatedLinksSummary

sub getRelocatedLinkHitsByType {
	my($self, $ls) = @_;
	my $summary;
	foreach my $l (@$ls) {
		my($id) = $l->{query_string} =~/id=([^&]*)/;
		my $type = $self->sqlSelect("stats_type", "links", "id=" . $self->sqlQuote($id));
		next unless $type; $summary->{$type} ||= 0; $summary->{$type} += $l->{cnt}; 
	}
	return $summary;
}

########################################################
#  expects arrayref returned by getRelocatedLinksSummary
sub getRelocatedLinkHitsByUrl {
	my($self, $ls) = @_;
	my $top_links = [];
	foreach my $l (@$ls) {
		my($id) = $l->{query_string} =~/id=([^&]*)/;
		my($url, $stats_type) = $self->sqlSelect("url, stats_type","links","id=".$self->sqlQuote($id));
		push @$top_links, { url => $url,
				  count => $l->{cnt},
			     stats_type => $stats_type }; 
	}
	return $top_links;
}

########################################################

sub getSubscribersWithRecentHits {
	my($self) = @_;
	return $self->sqlSelectColArrayref("uid", "users_hits", "hits_paidfor > hits_bought and lastclick >= date_sub(now(), interval 3 day)", "order by uid");
}

########################################################

sub getSubscriberCrawlers {
	my($self, $uids) = @_;
	return [] unless @$uids;
	my $uid_list = join(',',@$uids);
	return $self->sqlSelectAllHashrefArray("uid, count(*) as cnt", "accesslog_temp", 
						"uid in ($uid_list) and op='users' and query_string like '\%min_comment\%'",
						" group by uid having cnt >= 5 order by cnt desc limit 10");


}

########################################################

sub getTopEarlyInactiveDownmodders {
	my($self, $options) = @_;
	$options ||= {};
	my $constants = getCurrentStatic();
	my %user_hits;
	my $limit = $options->{limit};
	my $token_cutoff = $constants->{m2_mintokens} || 0;
	my $mods = $self->sqlSelectAllHashrefArray("id,moderatorlog.cid as cid, moderatorlog.uid as uid",
				"moderatorlog,comments,users_info",
				"comments.cid=moderatorlog.cid and moderatorlog.uid=users_info.uid AND points<=1 AND active=0 AND val=-1 AND tokens>=$token_cutoff");

	foreach my $m (@$mods) {
		my $first_mod = $self->sqlSelectColArrayref("id", "moderatorlog", "cid=$m->{cid}", "order by ts asc limit 2");
		for my $id (@$first_mod) {
			$user_hits{$m->{uid}}++ if $id == $m->{id};
		}
	}
	
	my @uids =  sort {$user_hits{$b} <=> $user_hits{$a}} keys %user_hits;
	@uids = splice(@uids, 0, $limit) if $limit;

	my $top_users;
	foreach (@uids) {
        	push @$top_users, { uid => $_, count=> $user_hits{$_}, nickname=> $self->getUser($_, "nickname")};

	}
	return $top_users;
}

sub getTopModdersNearArchive {
	my($self, $options) = @_;
	$options ||= {};
	my $constants = getCurrentStatic();
	my $archive_delay = $constants->{archive_delay};
	return [] unless $archive_delay;

	my($token_cutoff, $limit_clause);
	$token_cutoff = $constants->{m2_mintokens} || 0;
	$limit_clause = " LIMIT $options->{limit}" if $options->{limit};

	my $top_users = $self->sqlSelectAllHashrefArray(
		"COUNT(moderatorlog.uid) AS count, moderatorlog.uid AS uid, nickname",
		"discussions, moderatorlog, users_info, users",
		"moderatorlog.sid=discussions.id AND type='archived'
		 AND users_info.uid = moderatorlog.uid 
		 AND moderatorlog.ts > DATE_ADD(discussions.ts, INTERVAL $archive_delay - 3 DAY)
		 AND tokens >= $token_cutoff
		 AND users_info.uid = users.uid",
		"GROUP BY moderatorlog.uid ORDER BY count DESC $limit_clause");
	return $top_users;

}


########################################################
sub setGraph {
	my($self, $data) = @_;

	return unless $data->{id} && $data->{day} && $data->{image};
	$data->{content_type} ||= 'image/png';

	# check to see if we have a duplicate, just in case
	$data->{want_md5} = 1;
	my $md5 = $self->getGraph($data);
	return $md5 if $md5;

	my $blob = getObject('Slash::Blob');
	$md5 = $blob->create({
		data		=> $data->{image},
		content_type	=> $data->{content_type},
		# see stats.pl:main()
		seclev		=> getCurrentStatic('stats_admin_seclev') || 100
	});

	$self->sqlInsert('stats_graphs_index', {
		day	=> $data->{day},
		id	=> $data->{id},
		md5	=> $md5
	});

	return $md5;
}

########################################################
sub getGraph {
	my($self, $data) = @_;

	return unless $data->{id} && $data->{day};

	my $id  = $self->sqlQuote($data->{id});
	my $day = $self->sqlQuote($data->{day});

	my $md5 = $self->sqlSelect('md5', 'stats_graphs_index',
		"id=$id AND day=$day");

	return $md5 if $data->{want_md5};

	my $blob = getObject('Slash::Blob');
	my $image = $blob->get($md5);

	return $image || {};
}

########################################################
sub deleteGraph {
	my($self, $data) = @_;

	return unless $data->{id} && $data->{day};

	my $id  = $self->sqlQuote($data->{id});
	my $day = $self->sqlQuote($data->{day});

	my $md5 = $self->sqlSelect('md5', 'stats_graphs_index',
		"id=$id AND day=$day");

	$self->sqlDelete('stats_graphs_index', "id=$id AND day=$day");

	if ($md5) {
		my $blob = getObject('Slash::Blob');
		$blob->delete($md5);
	}
}

########################################################
sub cleanGraphs {
	my($self, $data) = @_;

	# default 7 days, should be var?  don't care, myself -- pudge
	$data->{days} ||= 7;

	my @time = localtime(time() - (86400 * $data->{days}));
	my $oldday = $self->sqlQuote(sprintf "%4d-%02d-%02d", 
		$time[5] + 1900, $time[4] + 1, $time[3]
	);

	my $images = $self->sqlSelectAll(
		"day, id",
		"stats_graphs_index",
		"day < $oldday"
	);

	my $count = 0;
	for my $image (@$images) {
		$count += 1 if $self->deleteGraph({
			day	=> $image->[0],
			id	=> $image->[1],
		});
	}
	return $count;
}


########################################################
sub getAllStats {
	my($self, $options) = @_;
	my $table = 'stats_daily';
	my $sel   = 'name, value+0 as value, skid, day';
	my $extra = 'ORDER BY skid, day, name';
	my @where;
	my @name_where;

	if ($options->{skid}) {
		push @where, 'skid = ' . $self->sqlQuote($options->{skid});
	}

	if ($options->{name}) {
		push @name_where, 'name = ' . $self->sqlQuote($options->{name});
	}

	if ($options->{name_pre}) {
		push @name_where, 'name like '. $self->sqlQuote($options->{name_pre} . '%');
	}
	
	my $sep_name_select = $options->{separate_name_select};

	# today is no good
	my $offset = 1;
	# yesterday no good either, early in the GMT day
	# (based on standard task timespec's)
	$offset++ if (gmtime)[2] < 8;

	push @where, sprintf(
		'(day <= DATE_SUB(NOW(), INTERVAL %d DAY))',
		$offset
	);

	if ($options->{days} && $options->{days} > 0) {
		push @where, sprintf(
			'(day > DATE_SUB(NOW(), INTERVAL %d DAY))',
			$options->{days} + $offset
		) if $options->{days};
	}

	my $data = $self->sqlSelectAll($sel, $table, join(' AND ', @where, @name_where), $extra) or return;
	my %returnable;

	for my $d (@$data) {
		# $returnable{SECTION}{DAY}{NAME} = VALUE
		$returnable{$d->[2]}{$d->[3]}{$d->[0]} = $d->[1];
		if (!$sep_name_select) {
			$returnable{$d->[2]}{names} ||= [];
			push @{$returnable{$d->[2]}{names}}, $d->[0]
				unless grep { $_ eq $d->[0] } @{$returnable{$d->[2]}{names}};
		}
	}
	
	if ($sep_name_select) {
		my $names = $self->sqlSelectAll("DISTINCT name, skid", $table, join(' AND ', @where));
		foreach my $name (@$names){
			$returnable{$name->[1]}{names} ||= [];
			push @{$returnable{$name->[1]}{names}}, $name->[0]
				unless grep { $_ eq $name->[0] } @{$returnable{$name->[1]}{names}};
		}
	}

	return \%returnable;
}

########################################################
sub _do_insert_select {
	my($self, $to_table, $from_cols, $from_table, $where, $retries, $sleep_time, $options) = @_;
	my $try_num = 0;
	my $rows = 0;
	my $ignore = $options->{ignore} ? "IGNORE" : "";
	I_S_LOOP: while (!$rows) {
		my $where_clause = "";
		$where_clause = "WHERE $where " if $where;

		my $sql = "INSERT $ignore INTO $to_table"
			. " SELECT $from_cols FROM $from_table $where_clause FOR UPDATE";
		$rows = $self->sqlDo($sql);
		# Apparently this insert can, under some circumstances,
		# including mismatched lib versions, succeed but return
		# 0 (or 0E0?) for the number of rows affected.  Check
		# instead for an undef, which indicates an actual error.
		last I_S_LOOP if defined $rows;

		# This should be a more reliable test, try it too.
		sleep 1;
		my $any_rows = $self->sqlSelect("1", $to_table, $where_clause, "LIMIT 1");
		if ($any_rows) {
			print STDERR scalar(localtime) . " INSERT-SELECT $to_table reported 0 rows inserted, but apparently succeeded with '$any_rows' rows, proceeding\n";
			last I_S_LOOP;
		}

		# Apparently the INSERT-SELECT failed.  This may be due to
		# a known bug in at least one version of MySQL under some
		# circumstance.  If appropriate, sleep and try it again.
		if (++$try_num < $retries) {
			print STDERR scalar(localtime) . " INSERT-SELECT $to_table failed on attempt $try_num, sleeping $sleep_time and retrying\n";
			sleep $sleep_time;
		} else {
			print STDERR scalar(localtime) . " INSERT-SELECT $to_table still failed, giving up\n";
			return undef;
		}

		$any_rows = $self->sqlSelect("1", $to_table, "", "LIMIT 1");
		if ($any_rows) {
			print STDERR scalar(localtime) . " after mere sleep, INSERT-SELECT $to_table now says it succeeded with '$any_rows' rows, proceeding\n";
			last I_S_LOOP;
		}
	}
	return $self;
}

########################################################
sub DESTROY {
	my($self) = @_;
	#$self->sqlDo("DROP TABLE $self->{_table}");
	$self->{_dbh}->disconnect if !$ENV{GATEWAY_INTERFACE} && $self->{_dbh};
}


1;

__END__

=head1 SEE ALSO

Slash(3).

=head1 VERSION

$Id$
