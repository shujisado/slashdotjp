#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2004 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;

use Data::Dumper;

use Slash;
use Slash::Constants ':slashd';
use Slash::Display;
use Slash::Utility;

use vars qw(
	%task	$me	$task_exit_flag
	$has_proc_processtable
	$irc	$conn	$nick	$channel
	$remarks_active	$next_remark_id	$next_handle_remarks	$hushed
	$next_check_slashd
	%stoid	$clean_exit_flag
	$parent_pid
);

$task{$me}{timespec} = '* * * * *';
$task{$me}{on_startup} = 1;
$task{$me}{fork} = SLASHD_NOWAIT;
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user, $info, $gSkin) = @_;
	return unless $constants->{ircslash};
	require Net::IRC;
	my $start_time = time;
	$parent_pid = $info->{parent_pid};

	my $success = ircinit();
	if (!$success) {
		# Probably the network is down and we can't establish
		# a connection.  Exit the task;  the next invocation
		# from slashd will try again.
		return "cannot connect, exiting to let slashd retry later";
	}

	$clean_exit_flag = 0;

	# Set the remark delay (how often we check the DB for new remarks).
	# If remarks are not wanted, we can check less frequently.
	$next_handle_remarks = 0;
	my $remark_delay = $constants->{ircslash_remarks_delay} || 5;
	$remark_delay = 180 if $remark_delay < 180 && !$remarks_active;

	while (!$task_exit_flag && !$clean_exit_flag) {
		$irc->do_one_loop();
		if ($@ && $@ =~ /No active connections left/) {
			return "Connection lost, exiting to let slashd retry later";
		}
		Time::HiRes::sleep(0.5); # don't waste CPU
		if (time() >= $next_handle_remarks) {
			$next_handle_remarks = time() + $remark_delay;
			handle_remarks();
		}
		if (!$clean_exit_flag && time() >= $next_check_slashd) {
			$next_check_slashd = time() + 20;
			my($not_ok, $response) = check_slashd();
			if ($not_ok) {
				# Parent slashd process seems to be gone.  Maybe
				# it just got killed and sent us the SIGUSR1 and
				# our $task_exit_flag is already set.  Pause a
				# moment and check that.
				sleep 1;
				if ($task_exit_flag) {
					# OK, forget this warning, just exit
					# normally.
					$not_ok = 0;
				}
			}
			if ($not_ok) {
				# Parent slashd process is gone, that's not good,
				# but the channel doesn't need to hear about it
				# every 20 seconds.
				$next_check_slashd = time() + 30 * 60;
				$conn->privmsg($channel, getIRCData('slashd_parent_gone'));
			}
		}
	}

	ircshutdown();

	return "exiting";
};

sub ircinit {
	my $constants = getCurrentStatic();
	my $server =	$constants->{ircslash_server}
				|| 'irc.slashnet.org';
	my $port =	$constants->{ircslash_port}
				|| 6667;
	my $ircname =	$constants->{ircslash_ircname}
				|| "$constants->{sitename} slashd";
	my $username =	$constants->{ircslash_username}
				|| ( map { s/\W+//g; $_ } $ircname )[0];
	$nick =		$constants->{ircslash_nick}
				|| substr($username, 0, 9);
	my $ssl =	$constants->{ircslash_ssl}
				|| 0;
	
	$remarks_active = $constants->{ircslash_remarks} || 0;
	$hushed = 0;

	$irc = new Net::IRC;
	$conn = $irc->newconn(	Nick =>		$nick,
				Server =>	$server,
				Port =>		$port,
				Ircname =>	$ircname,
				Username =>	$username,
				SSL =>		$ssl		);
	
	if (!$conn) {
		# Probably the network is down and we can't establish
		# a connection.  Exit the task;  the next invocation
		# from slashd will try again.
		return 0;
	}

	$conn->add_global_handler(376,	\&on_connect);
	$conn->add_global_handler(433,	\&on_nick_taken);
	$conn->add_handler('msg',	\&on_msg);
	$conn->add_handler('public',	\&on_public);

	$has_proc_processtable = eval { require Proc::ProcessTable };

	return 1;
}

sub ircshutdown {
	$conn->quit("exiting");
	# The disconnect seems to be unnecessary, and throws an error
	# in my testing, but just to be sure let's call it anyway.
	eval { $conn->disconnect() };
	if ($@ && $@ !~ /No active connections left/) {
		slashdLog("unexpected error on disconnect: $@");
	}
}

sub on_connect {
	my($self) = @_;
	my $constants = getCurrentStatic();
	$channel = $constants->{ircslash_channel} || '#ircslash';
	my $password = $constants->{ircslash_channel_password} || '';
	slashdLog("joining $channel" . ($password ? " (with password)" : ""));
	$self->join($channel, $password);
}

sub on_nick_taken {
	my($self) = @_;
	my $constants = getCurrentStatic();
	$nick = $constants->{ircslash_nick} if $constants->{ircslash_nick};
	$nick .= int(rand(10));
	$self->nick($nick);
}

# The only response right now to a private message is to "pong" it
# if it is a "ping".

sub on_msg {
	my($self, $event) = @_;

	my($arg) = $event->args();
	if ($arg =~ /ping/i) {
		$self->privmsg($nick, "pong");
	}
}

sub on_public {
	my($self, $event) = @_;
	my $constants = getCurrentStatic();

	my($arg) = $event->args();
	if (my($cmd) = $arg =~ /^$nick\b\S*\s*(.+)/) {
		handle_cmd($self, $cmd, $event);
	}
}

############################################################

sub getIRCData {
	my($value, $hashref) = @_;
	return getData($value, $hashref, 'ircslash');
}

############################################################

{
my %cmds = (
	help		=> \&cmd_help,
	hush		=> \&cmd_hush,
	unhush		=> \&cmd_unhush,
	'exit'		=> \&cmd_exit,
	ignore		=> \&cmd_ignore,
	unignore	=> \&cmd_unignore,
	whois		=> \&cmd_whois,
	daddypants	=> \&cmd_daddypants,
	slashd		=> \&cmd_slashd,
	dbs		=> \&cmd_dbs,
	quote		=> \&cmd_quote,
);
sub handle_cmd {
	my($self, $cmd, $event) = @_;
	my $responded = 0;
	for my $key (sort keys %cmds) {
		if (my($text) = $cmd =~ /\b$key\b\S*\s*(.*)/i) {
			my $func = $cmds{$key};
			$func->($self, {
				text	=> $text,
				key	=> $key,
				event	=> $event,
			});
			$responded = 1;
			last;
		}
	}
	# OK, none of those commands matched.  Try the template, or
	# our default response.
	if (!$responded) {
		# See if the template wants to field this.
		my $cmd_lc = lc($cmd);
		my $text = slashDisplay('responses',
			{ value => $cmd_lc },
			{ Page => 'ircslash', Return => 1, Nocomm => 1 });
		$text =~ s/^\s+//; $text =~ s/\s+$//;
		if ($text) {
			$self->privmsg($channel, $text);
		}
	}
}
}

sub cmd_help {
	my($self, $info) = @_;
	$self->privmsg($channel, getIRCData('help'));
}

sub cmd_hush {
	my($self, $info) = @_;
	if (!$hushed) {
		$hushed = 1;
		slashdLog("hushed by $info->{event}{nick}");
		$self->nick("$nick-hushed");
	}
}

sub cmd_unhush {
	my($self, $info) = @_;
	if ($hushed) {
		$hushed = 0;
		slashdLog("unhushed by $info->{event}{nick}");
		$self->nick("$nick");
	}
}

sub cmd_exit {
	my($self, $info) = @_;
	slashdLog("got exit from $info->{event}{nick}");
	$self->privmsg($channel, getIRCData('exiting'));
	$clean_exit_flag = 1;
}

sub cmd_ignore {
	my($self, $info) = @_;
	my($uid) = $info->{text} =~ /(\d+)/;
	my $slashdb = getCurrentDB();
	my $user = $slashdb->getUser($uid);
	if (!$user || !$user->{uid}) {
		$self->privmsg($channel, getIRCData('nosuchuser', { uid => $uid }));
	} elsif ($user->{noremarks}) {
		$self->privmsg($channel, getIRCData('alreadyignoring',
			{ nickname => $user->{nickname}, uid => $uid }));
	} else {
		$slashdb->setUser($uid, { noremarks => 1 });
		$self->privmsg($channel, getIRCData('ignoring',
			{ nickname => $user->{nickname}, uid => $uid }));
		slashdLog("ignoring $uid, cmd from $info->{event}{nick}");
	}
}

sub cmd_unignore {
	my($self, $info) = @_;
	my($uid) = $info->{text} =~ /(\d+)/;
	my $slashdb = getCurrentDB();
	my $user = $slashdb->getUser($uid);
	if (!$user || !$user->{uid}) {
		$self->privmsg($channel, getIRCData('nosuchuser', { uid => $uid }));
	} elsif (!$user->{noremarks}) {
		$self->privmsg($channel, getIRCData('wasntignoring',
			{ nickname => $user->{nickname}, uid => $uid }));
	} else {
		$slashdb->setUser($uid, { noremarks => undef });
		$self->privmsg($channel, getIRCData('unignored',
			{ nickname => $user->{nickname}, uid => $uid }));
		slashdLog("unignored $uid, cmd from $info->{event}{nick}");
	}
}

sub cmd_whois {
	my($self, $info) = @_;
	my $slashdb = getCurrentDB();

	my $uid;
	if ($info->{text} =~ /^(\d+)$/) {
		$uid = $1;
	} else {
		$uid = $slashdb->getUserUID($info->{text});
	}
	my $user = $slashdb->getUser($uid) if $uid;
	if (!$uid || !$user || !$user->{uid}) {
		$self->privmsg($channel, getIRCData('nosuchuser', { uid => $uid }));
	} else {
		$self->privmsg($channel, getIRCData('useris',
			{ nickname => $user->{nickname}, uid => $uid }));
	}
}

sub cmd_daddypants {
	my($self, $info) = @_;

	my $daddy = eval { require Slash::DaddyPants };
	return unless $daddy;

	my %args = ( name => 1 );

	if ($info->{text} =~ /^\s*([a-zA-Z]+)/) {
		$args{when} = $1;
	} elsif ($info->{text} =~ /^\s*(\d+\s+days)/) {
		$args{when} = $1;
	} elsif ($info->{text} && $info->{text} =~ /^(-?\d+)/) {
		$args{time} = $info->{text};
	}

	my $result = Slash::DaddyPants::daddypants(\%args);
	$self->privmsg($channel, $result);
	slashdLog("daddypants: $result, cmd from $info->{event}{nick}");
}

{ # closure
my %exchange = ( );
sub cmd_quote {
	my($self, $info) = @_;

	my $symbol = $info->{text};
	return unless $symbol;
	$symbol = uc($symbol);

	my $fq = eval { require Finance::Quote };
	return unless $fq;

	$fq = Finance::Quote->new();
	$fq->set_currency("USD");

	my %stock_raw = ( );

	my $exchange = $exchange{$symbol} || "";
	if ($exchange) {
		%stock_raw = $fq->fetch($exchange, $symbol);
	} else {
		TRY: for my $try (qw( nasdaq nyse europe canada )) {
			%stock_raw = $fq->fetch($try, $symbol);
			if (!%stock_raw) {
				# Nope, didn't get it.  Try again.
				next TRY;
			}
			# OK, we got it.
			$exchange{$symbol} = $try;
			last TRY;
		}
	}

	# Finance::Quote returns its data in a goofy format, not nested
	# hashrefs, but with the symbol name preceding the field name,
	# separated by the $; character.  Pull out the data for just the
	# one symbol we asked about.
	my %stock = ( );
	for my $key (keys %stock_raw) {
		my($dummy, $realfieldname) = split /$;/, $key;
		$stock{$realfieldname} = $stock_raw{$key};
	}

	# Add more useful data to that hash.
	if ($stock{year_range} =~ /^\s*([\d.]+)\D+([\d.]+)/) {
		($stock{year_low}, $stock{year_high}) = ($1, $2);
	}
	for my $key (qw( open close last high low year_high year_low )) {
		$stock{$key} = sprintf( "%.2f", $stock{$key}) if $stock{$key};
	}
	for my $key (qw( net p_change )) {
		$stock{$key} = sprintf("%+.2f", $stock{$key}) if $stock{$key};
	}
	$stock{symbol} = $symbol;

	# Generate and emit the response.
	my $response = getIRCData('quote_response', { stock => \%stock });
	$self->privmsg($channel, $response);
	slashdLog("quote: $response, cmd from $info->{event}{nick}");
}
} # end closure

sub cmd_slashd {
	my($self, $info) = @_;
	my $slashdb = getCurrentDB();
	my $st = $slashdb->getSlashdStatuses();
	my @lc_tasks =
		sort { $st->{$b}{last_completed_secs} <=> $st->{$a}{last_completed_secs} }
		keys %$st;
	my $last_task = $st->{ $lc_tasks[0] };
	$last_task->{last_completed_secs_ago} = time - $last_task->{last_completed_secs};

	my @response_strs = (
		getIRCData('slashd_lasttask', { task => $last_task })
	);

	my @cur_running_tasks = map { $st->{$_} }
		sort grep { $st->{$_}{in_progress} } keys %$st;
	push @response_strs, getIRCData('slashd_curtasks', { tasks => \@cur_running_tasks });

	my($slashd_not_ok, $check_slashd_data) = check_slashd();
	if ($slashd_not_ok) {
		push @response_strs, getIRCData('slashd_parent_gone');
	} elsif ($check_slashd_data) {
		push @response_strs, $check_slashd_data;
	}

	my $result = join " -- ", @response_strs;
	$self->privmsg($channel, $result);
	slashdLog("slashd: $result, cmd from $info->{event}{nick}");
}

sub check_slashd {
	my $parent_pid_str = "";
	if (!$has_proc_processtable) {
		# Don't know whether slashd is still present, can't check.
		# Return 0 meaning slashd is not not OK [sic], and a blank
		# string.
		return (0, "");
	}
	my $processtable = new Proc::ProcessTable;
	my $table = $processtable->table();
	my $response = "";
	for my $p (@$table) {
		next unless $p->{pid} == $parent_pid && $p->{fname} eq 'slashd';
		$response = getIRCData('slashd_parentpid', { process => $p });
		last;
	}
	my $ok = $response ? 1 : 0;
	return (!$ok, $response);
}

sub cmd_dbs {
	my($self, $info) = @_;
	my $slashdb = getCurrentDB();
	my $dbs = $slashdb->getDBs();
	my $dbs_data = $slashdb->getDBsReaderStatus(60);
	my $response;
	if (%$dbs_data) {
		for my $dbid (keys %$dbs_data) {
			$dbs_data->{$dbid}{virtual_user} = $dbs->{$dbid}{virtual_user};
			$dbs_data->{$dbid}{lag} = sprintf("%.1f", $dbs_data->{$dbid}{lag} || 0);
			$dbs_data->{$dbid}{bog} = sprintf("%.1f", $dbs_data->{$dbid}{bog} || 0);
		}
		my @dbids =
			sort { $dbs->{$a}{virtual_user} cmp $dbs->{$b}{virtual_user} }
			keys %$dbs_data;
		$response = getIRCData('dbs_response', { dbids => \@dbids, dbs => $dbs_data });
	} else {
		$response = getIRCData('dbs_nodata');
	}
	$self->privmsg($channel, $response);
}

############################################################

sub handle_remarks {
	my $slashdb = getCurrentDB();
	return if $hushed;

	my $constants = getCurrentStatic();
	$next_remark_id ||= $slashdb->getVar('ircslash_nextremarkid', 'value', 1) || 1;

	my $remarks_ar = $slashdb->getRemarksStarting($next_remark_id);
	return unless $remarks_ar && @$remarks_ar;

	my %story = ( );
	my %stoid_count = ( );
	my %uid_count = ( );
	my $max_rid = 0;
	for my $remark_hr (@$remarks_ar) {
		my $stoid = $remark_hr->{stoid};
		$stoid_count{$stoid}++;
		$story{$stoid} = $slashdb->getStory($stoid);
		$story{$stoid}{time_unix} = timeCalc($story{$stoid}{time}, "%s", "");
		my $uid = $remark_hr->{uid};
		$uid_count{$uid}++;
		$max_rid = $remark_hr->{rid} if $remark_hr->{rid} > $max_rid;
	}

	# If remarks are not active, just mark these as read and continue.
	if (!$remarks_active) {
		$next_remark_id = $max_rid + 1;
		$slashdb->setVar('ircslash_nextremarkid', $next_remark_id);
		return ;
	}

	# First pass:  outright strip out remarks from abusive users
	my %uid_blocked = ( );
	for my $uid (keys %uid_count) {
		# If a user's been ignored, block it.
		my $remark_user = $slashdb->getUser($uid);
		if ($remark_user->{noremarks}) {
			$uid_blocked{$uid} = 1;
		}
		# Or if a user has sent more than this many remarks in a day.
		elsif ($slashdb->getUserRemarkCount($uid, 86400      ) > $constants->{ircslash_remarks_max_day}) {
			$uid_blocked{$uid} = 1;
		}
		# Or if a user has sent more than this many remarks in a month.
		elsif ($slashdb->getUserRemarkCount($uid, 86400 *  30) > $constants->{ircslash_remarks_max_month}) {
			$uid_blocked{$uid} = 1;
		}
		# Or if a user has sent more than this many remarks in a year.
		elsif ($slashdb->getUserRemarkCount($uid, 86400 * 365) > $constants->{ircslash_remarks_max_year}) {
			$uid_blocked{$uid} = 1;
		}
	}

	# We should have a second pass in here to delay/join up remarks
	# about stories that are getting lots of remarks, so we don't
	# hear over and over about the same story.
	my $regex = regexSid();
	my $sidprefix = "$constants->{absolutedir_secure}/article.pl?sid=";
	STORY: for my $stoid (sort { $stoid_count{$a} <=> $stoid_count{$b} } %stoid_count) {
		# Skip a story that has already been live for a while.
		my $time_unix = $story{$stoid}{time_unix};
		next STORY if $time_unix < time - 600;

		my $url = "$sidprefix$story{$stoid}{sid}";
		my $remarks = "<$url>";
		my $do_send_msg = 0;
		my @stoid_remarks =
			grep { $_->{stoid} == $stoid }
			grep { ! $uid_blocked{$_->{uid}} }
			@$remarks_ar;
		REMARK: for my $i (0..$#stoid_remarks) {
			my $remark_hr = $stoid_remarks[$i];
			next if $uid_blocked{$remark_hr->{uid}};
			if ($i >= 3) {
				# OK, that's enough about this one story.
				# Summarize the rest.
				$remarks .= " (and " . (@stoid_remarks-$i) . " more)";
				last REMARK;
			}
			$do_send_msg = 1;
			$remarks .= " $remark_hr->{uid}:";
			if ($remark_hr->{remark} =~ $regex) {
				$remarks .= qq{<$sidprefix$remark_hr->{remark}>};
			} else {
				$remarks .= qq{"$remark_hr->{remark}"};
			}
		}
		if ($do_send_msg) {
			$conn->privmsg($channel, $remarks);
			# Every time we post remarks into the channel, we
			# wait a little longer before checking and sending
			# again.  This is so we don't flood.
			$next_handle_remarks += 20;
		}
	}
	$next_remark_id = $max_rid + 1;
	$slashdb->setVar('ircslash_nextremarkid', $next_remark_id);
}

1;

