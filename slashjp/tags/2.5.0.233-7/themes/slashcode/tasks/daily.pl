#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;

use Slash::Constants qw(:slashd :messages);
use Slash::Display;
use Slash::Utility;

use vars qw( %task $me );

# Remember that timespec goes by the database's time, which should be
# GMT if you installed everything correctly.  So 2:00 AM GMT is a good
# sort of midnightish time for the Western Hemisphere.  Adjust for
# your audience and admins.
$task{$me}{timespec} = '5 0 * * *'; # 9:05 AM JST
$task{$me}{timespec_panic_2} = ''; # if major panic, dailyStuff can wait
$task{$me}{fork} = SLASHD_NOWAIT;
$task{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

# this used to call dailyStuff; now it is just in a task
#	system("$constants->{sbindir}/dailyStuff $virtual_user &");
	my $messages  = getObject('Slash::Messages');
	daily_mailingList($virtual_user, $constants, $slashdb, $user, $messages);

	return;
};

sub daily_generateDailyMailees {
	my($n_users, $h_users) = @_;
	my %mailings = (
		dailynews	=> {
			users	=> $n_users,
			code	=> MSG_CODE_NEWSLETTER,
			subj	=> getData('newsletter subject', {}, 'messages'),
		},
		dailyheadlines	=> {
			users	=> $h_users,
			code	=> MSG_CODE_HEADLINES,
			subj	=> getData('headlines subject',  {}, 'messages'),
		},
	);

	for my $mailing (keys %mailings) {
		my $users = $mailings{$mailing}{users};
		my $mkeys = $mailings{$mailing}{mkeys} ||= {};

		for my $uid (keys %$users) {
			my $user = $users->{$uid};

			my $key  = $user->{sectioncollapse} || "";
			for my $cust_key (qw(
				story_never_topic	story_never_author	story_never_nexus
				story_always_topic	story_always_author	story_always_nexus
			)) {
				my $value = $user->{$cust_key};
				my @values = sort grep /^\d+$/, split /[,']+/, $value;
				$key .= '|' . join(',', @values);
			}
			# allow us to make certain emails sent individually,
			# by including a unique value in users_param for
			# this key -- pudge
			$user->{daily_mail_special} ||= '';
			$key .= '|' . $user->{daily_mail_special};

			# this may not be available, so manufacture on the fly ...
			my $is_admin = $user->{seclev} >= 100 ? 1 : 0;
			$key .= '|' . $is_admin;

			if (exists $mkeys->{$key}) {
				push @{$mkeys->{$key}{mails}}, $user->{realemail};
			} else {
				$mkeys->{$key}{mails} = [$user->{realemail}];
				$mkeys->{$key}{user}  = {
					uid => $uid,
					map { ($_ => $user->{$_}) }
					qw(
						sectioncollapse
						story_never_topic	story_never_author	story_never_nexus
						story_always_topic	story_always_author	story_always_nexus
						daily_mail_special
					)
				};
				$mkeys->{$key}{user}{is_admin} = $is_admin;
			}
		}
	}

	return \%mailings;
}

sub daily_generateDailyMail {
	my($mailing, $user, $constants, $slashdb) = @_;
	my $gSkin = getCurrentSkin();

	my $stories;
	# get data if not gotten yet
	my $data = $slashdb->getDailyMail($user) or return;
	return unless @$data; # no mail, no mas!

	for (@$data) {
		my(%story, @ref);
		@story{qw(sid title section author tid time dept
			introtext bodytext)} = @$_;

		1 while chomp($story{introtext});
		1 while chomp($story{bodytext});

		$story{introtext} = parseSlashizedLinks($story{introtext});
		$story{bodytext} =  parseSlashizedLinks($story{bodytext});

		my $asciitext = $story{introtext};
		$asciitext .= "\n\n" . $story{bodytext}
			if $constants->{newsletter_body};
		if ($constants->{tweak_japanese}) {
			require Jcode;
			@ref = ();
			$story{asciitext} = strip_notags($asciitext);
			$story{asciitext} =~ tr/\n//;
			$story{asciitext} = Encode::decode('utf-8', join("\n", Jcode->new(Encode::encode('utf-8', $story{asciitext}), 'utf8')->jfold(74)));
		} else {
			($story{asciitext}, @ref) = html2text($asciitext, 74);
		}

		$story{refs} = \@ref;
		push @$stories, \%story;
	}

	my $absolutedir = $user->{is_admin}
		? $gSkin->{absolutedir_secure}
		: $gSkin->{absolutedir};

	return slashDisplay($mailing,
		{ stories => $stories, urlize => \&daily_urlize, absolutedir => $absolutedir },
		{ Return => 1, Nocomm => 1, Page => 'messages', Skin => 'NONE' }
	);
}

sub daily_mailingList {
	my($virtual_user, $constants, $slashdb, $user, $messages) = @_;
	return unless $messages;
	my $n_users	= $messages->getNewsletterUsers();
	my $h_users	= $messages->getHeadlineUsers();

	my $mailings	= daily_generateDailyMailees($n_users, $h_users) or return;

	for my $mailing (sort keys %$mailings) {
		my $subj  = $mailings->{$mailing}{subj};
		my $code  = $mailings->{$mailing}{code};
		my $mkeys = $mailings->{$mailing}{mkeys};

		slashdLog("Daily Mail ($mailing) begin for " . scalar(keys %$mkeys) . " mkeys");
		for my $key (sort keys %$mkeys) {
			my $user = $mkeys->{$key}{user};
			my $n_users = scalar(@{ $mkeys->{$key}{mails} });
			my $text = daily_generateDailyMail($mailing, $user, $constants, $slashdb);
			next unless $text;
			if ($n_users >= 100) {
				slashdLog("Sending " . length($text) . " bytes to $n_users users: '$key'");
			}
			$messages->bulksend(
				$mkeys->{$key}{mails}, $subj,
				$text, $code, $user->{uid}
			);
		}
		slashdLog("Daily Mail ($mailing) end");
	}
}

sub daily_urlize {
	local($_) = @_;
	s/^(.{62})/$1\n/g;
	s/(\S{74})/$1\n/g;
	$_ = "<URL:" . $_ . ">";
	return $_;
}

1;
