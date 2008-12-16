#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use Slash::Utility;
use Slash::Constants qw( :messages :slashd );

use vars qw( %task $me $task_exit_flag );

$task{$me}{timespec} = '28 0-23 * * *';
$task{$me}{timespec_panic_1} = '';
$task{$me}{resource_locks} = { log_slave => 1, moderatorlog => 1 };
$task{$me}{fork} = SLASHD_NOWAIT;
$task{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	if (!$constants->{m2}) {
		slashdLog("$me - metamoderation inactive") if verbosity() >= 2;
		return ;
	}
	if ($constants->{tagbox}{Metamod}) {
		slashdLog("$me - superceded by Metamod tagbox");
		return ;
	}

	reconcile_m2();
	update_modlog_ids();
	mark_m2_oldzone();
	adjust_m2_freq() if $constants->{adjust_m2_freq};
	delete_old_m2_rows();

	return ;
};

sub reconcile_m2 {
	my $constants = getCurrentStatic();
	my $moddb = getObject("Slash::$constants->{m1_pluginname}");
	my $metamod_db = getObject('Slash::Metamod::Static');
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $metamod_reader = getObject('Slash::Metamod::Static', { db_type => 'reader' });

	my $consensus = $constants->{m2_consensus};
	my $reasons = $moddb->getReasons();
	my $sql;

	# %m2_results is a hash whose keys are uids.  Its values are
	# hashrefs with the keys "change" (an int) and "m2" (an array of
	# hashrefs with values title, url, subject, vote, reason).
	my %m2_results = ( );

	# We load the optional plugin objects here.
	my $messages = getObject('Slash::Messages');
	my $statsSave = getObject('Slash::Stats::Writer');

	# $mod_ids is an arrayref of moderatorlog IDs which need to be
	# reconciled.
	my $mods_ar = $metamod_reader->getModsNeedingReconcile();

	my $both0 = { };
	my $tievote = { };
	my %newstats = ( );
	for my $mod_hr (@$mods_ar) {

		# Get data about every M2 done to this moderation.
		my $m2_ar = $metamod_reader->getMetaModerations($mod_hr->{id});

		my $nunfair = scalar(grep { $_->{active} && $_->{val} == -1 } @$m2_ar);
		my $nfair   = scalar(grep { $_->{active} && $_->{val} ==  1 } @$m2_ar);

		# Sanity-checking... what could go wrong?
		next unless rec_sanity_check({
			mod_hr =>       $mod_hr,
			nunfair =>      $nunfair,
			nfair =>        $nfair,
			both0 =>        $both0,
			tievote =>      $tievote,
		});

		my $winner_val = 0;
		   if ($nfair > $nunfair) {     $winner_val =  1 }
		elsif ($nunfair > $nfair) {     $winner_val = -1 }
		my $fair_frac = $nfair/($nunfair+$nfair);
		my $lonedissent_val =
			scalar(grep { $_->{active} && $_->{val} == -$winner_val } @$m2_ar) <= 1
			? -$winner_val : 0;

		# Get the token and karma consequences of this vote.
		# This uses a complex algorithm to return a fairly
		# complex data structure but at least its fields are
		# named reasonably well.
		my $csq = $metamod_reader->getM2Consequences($fair_frac, $mod_hr);

		########################################
		# We should wrap this in a transaction to make it faster.
		# XXX START TRANSACTION

		# First update the moderator's tokens.
		my $use_possible = $csq->{m1_tokens}{num}
			&& rand(1) < $csq->{m1_tokens}{chance};
		$sql = $use_possible
			? $csq->{m1_tokens}{sql_possible}
			: $csq->{m1_tokens}{sql_base};
		if ($sql) {
			$moddb->setUser(
				$mod_hr->{uid},
				{ -tokens => $sql },
				{ and_where => $csq->{m1_tokens}{sql_and_where} }
			);
			if ($statsSave) {
				my $token_change = $use_possible
					? ($csq->{m1_tokens}{num_possible} || 0)
					: ($csq->{m1_tokens}{num_base} || 0);
				if ($token_change > 0) {
					$newstats{mod_tokens_gain_m1fair} += $token_change;
				} elsif ($token_change < 0) {
					$newstats{mod_tokens_lost_m1unfair} -= $token_change;
				}
			}
		}

		# Now update the moderator's karma.
		$sql = ($csq->{m1_karma}{num}
				&& rand(1) < $csq->{m1_karma}{chance})
			? $csq->{m1_karma}{sql_possible}
			: $csq->{m1_karma}{sql_base};
		my $m1_karma_changed = 0;
		$m1_karma_changed = $moddb->setUser(
			$mod_hr->{uid},
			{ -karma => $sql },
			{ and_where => $csq->{m1_karma}{sql_and_where} }
		) if $sql;

		# Now update the moderator's m2info.
		my $old_m2info = $moddb->getUser($mod_hr->{uid}, 'm2info');
		my $new_m2info = add_m2info($old_m2info, $nfair, $nunfair);
		$moddb->setUser(
			$mod_hr->{uid},
			{ m2info => $new_m2info }
		) if $new_m2info ne $old_m2info;

		# Now update the moderator's tally of csq bonuses/penalties.
		my $csqtc = $csq->{csq_token_change}{num} || 0;
		my $val = sprintf("csq_bonuses %+0.3f", $csqtc);
		$moddb->setUser(
			$mod_hr->{uid},
			{ -csq_bonuses => $val },
		) if $csqtc;

		# Now update the tokens of each M2'er.
		for my $m2 (@$m2_ar) {
			if (!$m2->{uid}) {
				slashdLog("no uid in \$m2: " . Dumper($m2));
				next;
			}
			my $key = "m2_fair_tokens";
			$key = "m2_unfair_tokens" if $m2->{val} == -1;
			my $use_possible = $csq->{$key}{num}
				&& rand(1) < $csq->{$key}{chance};
			$sql = $use_possible
				? $csq->{$key}{sql_possible}
				: $csq->{$key}{sql_base};
			if ($sql) {
				$moddb->setUser(
					$m2->{uid},
					{ -tokens => $sql },
					{ and_where => $csq->{$key}{sql_and_where} }
				);
			}
			if ($m2->{val} == $winner_val) {
				$moddb->setUser($m2->{uid},
					{ -m2voted_majority     => "m2voted_majority + 1" });
			} elsif ($m2->{val} == $lonedissent_val) {
				$moddb->setUser($m2->{uid},
					{ -m2voted_lonedissent  => "m2voted_lonedissent + 1" });
			}
			if ($statsSave) {
				my $token_change = $use_possible
					? ($csq->{$key}{num_possible} || 0)
					: ($csq->{$key}{num_base} || 0);
				if ($token_change > 0) {
					$newstats{mod_tokens_gain_m2majority} += $token_change;
				} elsif ($token_change < 0) {
					$newstats{mod_tokens_lost_m2minority} -= $token_change;
				}
			}
		}

		if ($statsSave) {
			my $reason_name = $reasons->{$mod_hr->{reason}}{name};
			$newstats{"m2_${reason_name}_fair"} += $nfair;
			$newstats{"m2_${reason_name}_unfair"} += $nunfair;
			$newstats{"m2_${reason_name}_${nfair}_${nunfair}"}++;
		}

		# Store data for the message we may send.
		if ($messages) {
			# Only send message if the moderation was deemed unfair
			if ($winner_val < 0) {
				# Get discussion metadata without caching it.
				my $discuss = $moddb->getDiscussion(
					$mod_hr->{sid}
				);

				# Get info on the comment.
				my $comment_subj = ($moddb->getComments(
					$mod_hr->{sid}, $mod_hr->{cid}
				))[2];
				my $comment_url = "/comments.pl?sid=$mod_hr->{sid}&cid=$mod_hr->{cid}";

				$m2_results{$mod_hr->{uid}}{change} ||= 0;
				$m2_results{$mod_hr->{uid}}{change} += $csq->{m1_karma}{sign}
					if $m1_karma_changed;

				push @{$m2_results{$mod_hr->{uid}}{m2}}, {
					title   => $discuss->{title},
					url     => $comment_url,
					subj    => $comment_subj,
					vote    => $winner_val,
					reason  => $reasons->{$mod_hr->{reason}}
				};
			}
		}

		# This mod has been reconciled.
		$moddb->sqlUpdate("moderatorlog", {
			-m2status => 2,
		}, "id=$mod_hr->{id}");

		# XXX END TRANSACTION
		########################################

	}

	if ($both0 && %$both0) {
		slashdLog("$both0->{num} mods had both fair and unfair 0, ids $both0->{minid} to $both0->{maxid}");
	}
	if ($tievote && %$tievote) {
		slashdLog("$tievote->{num} mods had a tie fair-unfair vote, ids $tievote->{minid} to $tievote->{maxid}");
	}

	# Update stats to reflect all the token and M2-judgment
	# information we just learned.
	if ($statsSave) {
		for my $key (keys %newstats) {
			$statsSave->addStatDaily($key, $newstats{$key});
		}
	}

	# Optional: Send message to original moderator indicating that
	# metamoderation has occured.
	if ($messages && scalar(keys %m2_results)) {
		# Unfortunately, the template must be aware
		# of the valid states of $mod_hr->{val}, but
		# for default Slashcode (and Slashdot), this
		# isn't a problem.
		my $data = {
			template_name   => 'msg_m2',
			template_page   => 'messages',
			subject         => {
				template_name   => 'msg_m2_subj',
			},
		};

		# Sends the actual message, varying M2 results by user.
		for (keys %m2_results) {
			my $msg_user = 
				$messages->checkMessageCodes(MSG_CODE_M2, [$_]);
			if (@{$msg_user}) {
				$data->{m2} = $m2_results{$_}{m2};
				$data->{change} = $m2_results{$_}{change};
				$data->{m2_summary} = $metamod_db->getModResolutionSummaryForUser($_, 20);
				$messages->create($_, MSG_CODE_M2, $data, 0, '', 'collective');
			}
		}
	}

}

sub rec_sanity_check {
	my($args) = @_;
	my($mod_hr, $nunfair, $nfair, $both0, $tievote) = (
		$args->{mod_hr}, $args->{nunfair}, $args->{nfair},
		$args->{both0}, $args->{tievote}
	);
	if (!$mod_hr->{uid}) {
		slashdLog("no uid in \$mod_hr: " . Dumper($mod_hr));
		return 0;
	}
	if ($nunfair+$nfair == 0) {
		$both0->{num}++;
		$both0->{minid} = $mod_hr->{id} if !$both0->{minid} || $mod_hr->{id} < $both0->{minid};
		$both0->{maxid} = $mod_hr->{id} if !$both0->{maxid} || $mod_hr->{id} > $both0->{maxid};
		if (verbosity() >= 3) {
			slashdLog("M2 fair,unfair both 0 for mod id $mod_hr->{id}");
		}
		return 0;
	}
	if (($nunfair+$nfair) % 2 == 0) {
		$tievote->{num}++;
		$tievote->{minid} = $mod_hr->{id} if !$tievote->{minid} || $mod_hr->{id} < $tievote->{minid};
		$tievote->{maxid} = $mod_hr->{id} if !$tievote->{maxid} || $mod_hr->{id} > $tievote->{maxid};
		if (verbosity() >= 3) {
			my $constants = getCurrentStatic();
			slashdLog("M2 fair+unfair=" . ($nunfair+$nfair) . ","
				. " consensus=$constants->{m2_consensus}"
				. " for mod id $mod_hr->{id}");
		}
	}
	return 1;
}

# users_info.m2info is kind of a hack:  a short string field that
# was originally intended to just store some numeric codes about
# the user's last moderations and how they'd been metamodded.
# Since then it's been used for other things too.  The protocol is
# that various substrings are separated by semicolons, and all
# those substrings are sorted in reverse 'cmp' order inside the
# field.  Thus '0604 30' (a mod from April 2006 M2'd 3-0 fair)
# sorts before '0605 21' (a mod from May 2006 M2'd 2-1 fair)
# and the older 

sub add_m2info {
	my($old, $nfair, $nunfair) = @_;

	my @lt = localtime;
	my $thismonth = sprintf("%02d%02d", $lt[5] % 100, $lt[4]+1);
	my @old = split /\s*;\s*/, $old;
	my %val = ( );
	for my $item (@old, "$thismonth $nfair$nunfair") {
		my($date, $more) = $item =~ /^(\w+)\s+(.+)$/;
		next unless $date;
		$val{$date} = [ ] if !defined($val{$date});
		push @{$val{$date}}, $more;
	}
	my @combined = sort { $b cmp $a } keys %val;
	my $combined = "";
	for my $item (@combined) {
		$combined .= "; " if $combined;
		$combined .= "$item @{$val{$item}}";
		if (length($combined) > 63) {
			$combined = substr($combined, 0, 63);
			last;
		}
	}
	return $combined;
}

sub reconcile_stats {
	my($statsSave, $stats_created, $today,
		$reason, $nfair, $nunfair) = @_;
	return unless $statsSave;

	my $constants = getCurrentStatic();
	my $moddb = getObject("Slash::$constants->{m1_pluginname}");
	my $consensus = $constants->{m2_consensus};
	my $reasons = $moddb->getReasons();
	my @reasons_m2able =
		sort map { $reasons->{$_}{name} }
		grep { $reasons->{$_}{m2able} }
		keys %$reasons;
	my $reason_name = $reasons->{$reason}{name};

	# Update the stats.

	# We could just use addStatDaily() for these values.  But
	# this function may be called many times (hundreds) in
	# quick succession and we will save many pointless
	# INSERT IGNOREs if we cache some information about which
	# values have already been added.

	# First create the rows if necessary.
	if (!$stats_created) {
		# Test... has this first item has been created
		# already today?
		$stats_created = 1 if $moddb->sqlSelect(
			"id",
			"stats_daily",
			"day='$today'
			 AND name='m2_${reason_name}_fair'
			 AND section='all'"
		);
	}
	if (!$stats_created) {
		for my $r (@reasons_m2able) {
			$statsSave->createStatDaily("m2_${r}_fair", 0);
			$statsSave->createStatDaily("m2_${r}_unfair", 0);
			for my $f (0..$consensus) {
				$statsSave->createStatDaily(
					"m2_${r}_${f}_" . ($consensus-$f),
					0);
			}
		}
	}

	# Now increment the stats values appropriately.
	$statsSave->updateStatDaily(
		"m2_${reason_name}_fair",
		"value + $nfair") if $nfair;
	$statsSave->updateStatDaily(
		"m2_${reason_name}_unfair",
		"value + $nunfair") if $nunfair;
	$statsSave->updateStatDaily(
		"m2_${reason_name}_${nfair}_${nunfair}",
		"value + 1");
}

############################################################

sub update_modlog_ids {
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $mod_reader = getObject("Slash::$constants->{m1_pluginname}", { db_type => "reader" });
	my $days_back = $constants->{archive_delay_mod} || 30;
	$days_back = 30 if $days_back > 30;
	my $days_back_cushion = int($days_back/10);
	$days_back_cushion = $constants->{m2_min_daysbackcushion} || 2
		if $days_back_cushion < ($constants->{m2_min_daysbackcushion} || 2);
	$days_back -= $days_back_cushion;

	my $reasons = $mod_reader->getReasons();
	my $m2able_reasons = join(",",
	       sort grep { $reasons->{$_}{m2able} }
	       keys %$reasons);
	return if !$m2able_reasons;

	# XXX I'm considering adding a 'WHERE m2status=0' clause to the
	# MIN/MAX selects below.  This might help choose mods more
	# smoothly and make failure (as archive_delay_mod is approached)
	# less dramatic too.  On the other hand it might screw things
	# up, making older mods at N-1 M2's never make it to N.  I've
	# run tests on changes like this before and there's almost no
	# way to predict accurately what it will do on a live site
	# without doing it... -Jamie 2002/11/16

	my $m2status_clause = $constants->{m2} ? ' AND m2status=0' : '';
	my($min_old) = $mod_reader->sqlSelect("MIN(id)", "moderatorlog",
		"active=1 AND reason IN ($m2able_reasons) $m2status_clause");
	my($max_old) = $mod_reader->sqlSelect("MAX(id)", "moderatorlog",
		"ts < DATE_SUB(NOW(), INTERVAL $days_back DAY)
		 AND active=1 AND reason IN ($m2able_reasons) $m2status_clause");
	$min_old = 0 if !$min_old;
	$max_old = $min_old if !$max_old;
	my($min_new) = $mod_reader->sqlSelect("MIN(id)", "moderatorlog",
		"ts >= DATE_SUB(NOW(), INTERVAL $days_back_cushion DAY)
		 AND active=1 AND reason IN ($m2able_reasons) $m2status_clause");
	my($max_new) = $mod_reader->sqlSelect("MAX(id)", "moderatorlog",
		"active=1 AND reason IN ($m2able_reasons) $m2status_clause");
	$min_new = 0 if !$min_new;
	$max_new = $min_new if !$max_new;

	$slashdb->setVar("m2_modlogid_min_old", $min_old);
	$slashdb->setVar("m2_modlogid_max_old", $max_old);
	$slashdb->setVar("m2_modlogid_min_new", $min_new);
	$slashdb->setVar("m2_modlogid_max_new", $max_new);
}

############################################################

sub mark_m2_oldzone {
	my $constants = getCurrentStatic();
	my $moddb = getObject("Slash::$constants->{m1_pluginname}");

	my $reasons = $moddb->getReasons();
	my $m2able_reasons = join(",",
	       sort grep { $reasons->{$_}{m2able} }
	       keys %$reasons);
	my $count_oldzone_clause = "";
	if ($m2able_reasons) {
		$count_oldzone_clause = "active=1 AND m2status=0 AND reason IN ($m2able_reasons)";
	}

	my $prev_oldzone = $moddb->getVar('m2_oldzone', 'value', 1);
	my $prev_oldzone_count = 0;
	if ($prev_oldzone && $count_oldzone_clause) {
		$prev_oldzone_count = $moddb->sqlCount("moderatorlog",
			"id <= $prev_oldzone AND $count_oldzone_clause");
	}
	$prev_oldzone = "undef" if !defined($prev_oldzone);

	set_new_m2_oldzone();

	my $new_oldzone = $moddb->getVar('m2_oldzone', 'value', 1);
	my $new_oldzone_count = 0;
	if ($new_oldzone && $count_oldzone_clause) {
		$new_oldzone_count = $moddb->sqlCount("moderatorlog",
			"id <= $new_oldzone AND $count_oldzone_clause");
	}
	$new_oldzone = "undef" if !defined($new_oldzone);

	slashdLog("m2_oldzone was $prev_oldzone ($prev_oldzone_count mods) now $new_oldzone ($new_oldzone_count mods)");
}

sub set_new_m2_oldzone {
	my $constants = getCurrentStatic();
	my $moddb = getObject("Slash::$constants->{m1_pluginname}");

	my $reasons = $moddb->getReasons();
	my $m2able_reasons = join(",",
	       sort grep { $reasons->{$_}{m2able} }
	       keys %$reasons);
	return if !$m2able_reasons;
	my $archive_delay_mod =
		   $constants->{archive_delay_mod}
		|| $constants->{archive_delay}
		|| 14;
	my $m2_oldest_wanted = $constants->{m2_oldest_wanted}
		|| int($archive_delay_mod * 0.9);

	my $need_m2_clause = "active=1 AND m2status=0 AND reason IN ($m2able_reasons)";
	my $m2_oldest_id = $moddb->sqlSelect("MIN(id)",
		"moderatorlog", $need_m2_clause);
	if (!$m2_oldest_id) {
		# If there's nothing to M2, we're good.
		$moddb->setVar('m2_oldzone', 0);
		return ;
	}

	my $oldest_time_days = $moddb->sqlSelect(
		"( UNIX_TIMESTAMP(NOW()) - UNIX_TIMESTAMP(ts) ) / 86400",
		"moderatorlog",
		"id=$m2_oldest_id");
	if ($oldest_time_days < $m2_oldest_wanted) {
		# If the oldest unM2'd mod is younger than
		# the limit set in the m2_oldest_wanted var,
		# we're good.
		$moddb->setVar('m2_oldzone', 0);
		return ;
	}

	# OK, the oldest mods are too old.  We're going to call
	# the "oldzone" the nth percentile:  everything older
	# than the oldest n% of mods.  Find the id of that mod
	# and write it.  A percentile of 2 gives us overhead
	# of about a factor of 10 on Slashdot without having to
	# worry about running out past the "oldzone" before the
	# next run of run_moderatord.
	my $percentile = $constants->{m2_oldest_zone_percentile} || 2;
	my $modlog_size = $moddb->sqlCount("moderatorlog", $need_m2_clause);
	my $oldzone_size = int($modlog_size * $percentile / 100 + 0.5);
	if (!$oldzone_size) {
		# We probably shouldn't get here except on a site which
		# has _very_ little moderation... but if we do, then
		# we're good.
		$moddb->setVar('m2_oldzone', 0);
		return ;
	}
	my $oldzone_id = $moddb->sqlSelect(
		"id",
		"moderatorlog",
		"$need_m2_clause",
		"ORDER BY id LIMIT $oldzone_size, 1");
	$moddb->setVar('m2_oldzone', $oldzone_id);
}

############################################################

sub adjust_m2_freq {
	my $metamod_db = getObject('Slash::Metamod');
	my $constants = getCurrentStatic();

	# Decide how far back we're going to look for the
	# "roughly weekly" factor.  Earlier, this maxxed out at
	# 10 days but I think it might be better to try 7,
	# to smooth out any fluctuations from weekday to
	# weekend.
	my $t = $constants->{archive_delay};
	$t = 3 if $t < 3;
	$t = 7 if $t > 7;

	my $avg_consensus_t = $metamod_db->sqlSelect("AVG(m2needed)", "moderatorlog",
		"active=1 AND ts > DATE_SUB(NOW(), INTERVAL $t DAY)");
	my $avg_consensus_day = $metamod_db->sqlSelect("AVG(m2needed)", "moderatorlog",
		"active=1 AND ts > DATE_SUB(NOW(), INTERVAL  1 DAY)");

	my $m2count_t = $metamod_db->sqlCount("metamodlog",
		"active=1 AND ts > DATE_SUB(NOW(), INTERVAL $t day)");
	my $m1count_t = $metamod_db->sqlCount("moderatorlog",
		"active=1 AND ts > DATE_SUB(NOW(), INTERVAL $t day)");

	my $m2count_day = $metamod_db->sqlCount("metamodlog",
		"active=1 AND ts > DATE_SUB(NOW(), INTERVAL  1 day)");
	my $m1count_day = $metamod_db->sqlCount("moderatorlog",
		"active=1 AND ts > DATE_SUB(NOW(), INTERVAL  1 day)");

	# If this site gets very little moderation/metamoderation,
	# don't bother adjusting m2_freq.
	return 1 unless $m1count_t >= 50 && $m2count_t >= 50;

	my $x = $m2count_t / ($m1count_t * $avg_consensus_t);
	my $y = $m2count_day / ($m1count_day * $avg_consensus_day);
	my $z = ($y * 2 + $x) / 3;
	slashdLog(sprintf("m2_freq vars: x: %0.6f y: %0.6f z: %0.6f\n", $x, $y, $z));

	# If the daily and the roughly-weekly factors do not agree, we
	# still adjust the m2_freq, but not nearly as much.  This may
	# help avoid oscillations where the daily factor can get very
	# far away from 1.0 while the weekly factor creeps toward it,
	# causing a sudden change when the weekly factor crosses 1.0
	# to be on the same side as the daily factor.
	my $dampen = ($x > 1 && $y < 1) || ($x < 1 && $y > 1) ? 0.2 : 1.0;

	$z = 3/4 if $z < 3/4;
	$z = 4/3 if $z > 4/3;
	$z = ($z-1)*$dampen + 1;
	slashdLog(sprintf("m2_freq: adjusted  z: %0.6f\n", $z));

	my $cur_m2_freq = $metamod_db->getVar('m2_freq', 'value', 1) || 86400;
	my $new_m2_freq = int($cur_m2_freq * $z ** (1/24) + 0.5);

	$new_m2_freq = $constants->{m2_freq_min}
		if defined $constants->{m2_freq_min} && $new_m2_freq < $constants->{m2_freq_min};
	$new_m2_freq = $constants->{m2_freq_max}
		if defined $constants->{m2_freq_max} && $new_m2_freq > $constants->{m2_freq_max};
	slashdLog("adjusting m2_freq from $cur_m2_freq to $new_m2_freq");
	$metamod_db->setVar('m2_freq', $new_m2_freq);
}

sub delete_old_m2_rows {
	my $metamod_db = getObject('Slash::Metamod::Static');
	$metamod_db->deleteOldM2Rows({ sleep_between => 30 });
}

1;

