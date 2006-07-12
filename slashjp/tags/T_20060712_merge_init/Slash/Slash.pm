# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash;

# BENDER: It's time to kick some shiny metal ass!

=head1 NAME

Slash - the BEAST

=head1 SYNOPSIS

	use Slash;  # figure the rest out ;-)

=head1 DESCRIPTION

Slash is the code that runs Slashdot.

=head1 FUNCTIONS

=cut

use strict;  # ha ha ha ha ha!
use Symbol 'gensym';

use Slash::Constants ':people';
use Slash::DB;
use Slash::Display;
use Slash::Utility;
use Fcntl;
use File::Spec::Functions;
use Time::Local;
use Time::HiRes;

use base 'Exporter';
use vars qw($VERSION @EXPORT);

$VERSION   	= '2.005000';  # v2.5.0
# note: those last two lines of functions will be moved elsewhere
@EXPORT		= qw(
	constrain_score
	getData
	gensym

	dispComment displayStory displayRelatedStories displayThread dispStory
	getOlderStories getOlderDays moderatorCommentLog printComments
	jsSelectComments

	tempUofmLinkGenerate tempUofmCipherObj
);


# this is the worst damned warning ever, so SHUT UP ALREADY!
#$SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /Use of uninitialized value/ };

# BENDER: Fry, of all the friends I've had ... you're the first.


########################################################
# Behold, the beast that is threaded comments
sub selectComments {
	my($discussion, $cid, $options) = @_;
	my $slashdb = getCurrentDB();
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my($min, $max) = ($constants->{comment_minscore}, 
			  $constants->{comment_maxscore});
	my $num_scores = $max - $min + 1;

	my $commentsort = defined $options->{commentsort}
		? $options->{commentsort}
		: $user->{commentsort};
	my $threshold = defined $options->{threshold}
		? $options->{threshold}
		: $user->{threshold};


	my $comments; # One bigass hashref full of comments
	for my $x (0..$num_scores-1) {
		$comments->{0}{totals}[$x] = 0;
	}
	my $y = 0;
	for my $x ($min..$max) {
		$comments->{0}{total_keys}{$x} = $y;
		$y++;
	}

	# When we pull comment text from the DB, we only want to cache it if
	# there's a good chance we'll use it again.
	my $cache_read_only = 0;
	$cache_read_only = 1 if $discussion->{type} eq 'archived';
	$cache_read_only = 1 if timeCalc($discussion->{ts}, '%s') <
		time - 3600 * $constants->{comment_cache_max_hours};

	my $thisComment;
	my $gcfu_opt = {
		cache_read_only	=> $cache_read_only,
		one_cid_only	=> $options->{one_cid_only},
	};
	if ($options->{force_read_from_master}) {
		$thisComment = $slashdb->getCommentsForUser($discussion->{id}, $cid, $gcfu_opt);
	} else {
		$thisComment = $reader->getCommentsForUser($discussion->{id}, $cid, $gcfu_opt);
	}

	if (!$thisComment) {
		_print_cchp($discussion);
		return ( {}, 0 );
	}

	my $max_uid = $reader->countUsers({ max => 1 });
	my $reasons = $reader->getReasons();
	# We first loop through the comments and assign bonuses and
	# and such.
	for my $C (@$thisComment) {
		# By setting pid to zero, we remove the threaded
		# relationship between the comments. Don't ignore threads
		# in forums, or when viewing a single comment (cid > 0)
		$C->{pid} = 0 if $commentsort > 3
			&& $cid == 0
			&& $user->{mode} ne 'parents'; # Ignore Threads

		# I think instead we want something like this... (not this
		# precisely, it munges up other things).
		# I'm still looking into how to get parent links and
		# children to show up properly in flat mode. - Jamie 2002/07/30
#		$user->{state}{noreparent} = 1 if $commentsort > 3;

		$C->{points} = _get_points($C, $user, $min, $max, $max_uid, $reasons);

		# Let us fill the hash range for hitparade
		$comments->{0}{totals}[$comments->{0}{total_keys}{$C->{points}}]++;  
	}

	# If we are sorting by highest score we resort to figure in bonuses
	if ($commentsort == 3) {
		@$thisComment = sort {
			$b->{points} <=> $a->{points} || $a->{cid} <=> $b->{cid}
		} @$thisComment;
	} elsif ($commentsort == 1 || $commentsort == 5) {
		@$thisComment = sort {
			$b->{cid} <=> $a->{cid}
		} @$thisComment;
	} else {
		@$thisComment = sort {
			$a->{cid} <=> $b->{cid}
		} @$thisComment;
	}

	# This loop mainly takes apart the array and builds 
	# a hash with the comments in it.  Each comment is
	# in the index of the hash (based on its cid).
	for my $C (@$thisComment) {
		# So we save information. This will only have data if we have 
		# happened through this cid while it was a pid for another
		# comments. -Brian
		my $tmpkids = $comments->{$C->{cid}}{kids};
		my $tmpvkids = $comments->{$C->{cid}}{visiblekids};

		# We save a copy of the comment in the root of the hash
		# which we will use later to find it via its cid
		$comments->{$C->{cid}} = $C;

		# Kids is what displayThread will actually use.
		$comments->{$C->{cid}}{kids} = $tmpkids;
		$comments->{$C->{cid}}{visiblekids} = $tmpvkids;

		# The comment pushes itself onto its parent's
		# kids array.
		push @{$comments->{$C->{pid}}{kids}}, $C->{cid};

		# The next line deals with hitparade -Brian
		#$comments->{0}{totals}[$C->{points} - $min]++;  # invert minscore

		# Increment the parent comment's count of visible kids,
		# if this comment is indeed visible.
		$comments->{$C->{pid}}{visiblekids}++
			if $C->{points} >= (defined $threshold ? $threshold : $min);

		# Can't mod in a discussion that you've posted in.
		# Just a point rule -Brian
		$user->{points} = 0 if $C->{uid} == $user->{uid}; # Mod/Post Rule
	}

	# After that loop, there may be comments in the $comments hashref
	# which have no visible parents and thus which incremented an
	# otherwise-empty comment's visiblekids field and appended to an
	# otherwise-empty kids arrayref.  For cleanliness' sake, eliminate
	# those comments.  We do leave "comment 0" alone, though.
	my @phantom_cids =
		grep { $_ > 0 && !defined $comments->{$_}{cid} }
		keys %$comments;
	delete @$comments{@phantom_cids};

	my $count = @$thisComment;

	# Cascade comment point totals down to the lowest score, so
	# (2, 1, 3, 5, 4, 2, 1) becomes (18, 16, 15, 12, 7, 3, 1).
	# We do a bit of a weird thing here, returning this data in
	# the fields for a fake comment with "cid 0"...
	for my $x (reverse(0..$num_scores-2)) {
		$comments->{0}{totals}[$x] += $comments->{0}{totals}[$x + 1];
	}

	# get the total visible kids for each comment --Pater
	countTotalVisibleKids($comments);

	_print_cchp($discussion, $count, $comments->{0}{totals});

	reparentComments($comments, $reader, $options);
	return($comments, $count);
}

sub jsSelectComments {
	require Data::JavaScript::Anon;
	my($slashdb, $constants, $user, $form) = @_;
	$slashdb   ||= getCurrentDB();
	$constants ||= getCurrentStatic();
	$user      ||= getCurrentUser();
	$form      ||= getCurrentForm();

	$user->{mode} = 'thread';
	$user->{reparent} = 0;
	$user->{state}{max_depth} = $constants->{max_depth} + 3;

	my $threshold = $user->{threshold};
	my $highlightthresh = $user->{highlightthresh};
	$highlightthresh = $threshold if $highlightthresh < $threshold;

	my $id = $form->{sid};
	return unless $id;

	my $cid = $form->{cid} || 0;

	my($comments) = selectComments(
		$slashdb->getDiscussion($id),
		$cid,
		{
			commentsort	=> 0,
			threshold	=> -1
		}
	);

	delete $comments->{0}; # non-comment data

	my @roots = $cid ? $cid : grep { !$comments->{$_}{pid} } keys %$comments;

	if ($form->{full}) {
		my $comment_text = $slashdb->getCommentTextCached(
			$comments, [ keys %$comments ],
		);

		for my $cid (keys %$comment_text) {
			$comments->{$cid}{comment} = $comment_text->{$cid};
		}
	} else {
		my $comments_new;
		my @keys = qw(pid kids points uid);
		for my $cid (keys %$comments) {
			@{$comments_new->{$cid}}{@keys} = @{$comments->{$cid}}{@keys};
		}
		$comments = $comments_new;
	}

	my $anon_comments = Data::JavaScript::Anon->anon_dump($comments);
	my $anon_roots    = Data::JavaScript::Anon->anon_dump(\@roots);

	return <<EOT;
comments = $anon_comments;

root_comments = $anon_roots;
root_comment = $cid;

user_uid = $user->{uid};
user_is_anon = $user->{is_anon};
user_threshold = $threshold;
user_highlightthresh = $highlightthresh;

discussion_id = $id;
EOT
}

sub constrain_score {
	my($score) = @_;
	my $constants = getCurrentStatic();
	my($min, $max) = ($constants->{comment_minscore}, $constants->{comment_maxscore});
	$score = $min if $score < $min;
	$score = $max if $score > $max;
	return $score;
}

sub _get_points {
	my($C, $user, $min, $max, $max_uid, $reasons) = @_;
	my $hr = {
		score_start => constrain_score($C->{pointsorig} + $C->{tweak_orig}),
		moderations => constrain_score($C->{points} + $C->{tweak}) - constrain_score($C->{pointsorig} + $C->{tweak_orig}),
	};
	my $points = $hr->{score_start} || 0;

	# User can setup to give points based on size.
#	my $len = length($C->{comment});
	my $len = $C->{len};
	if ($len) {
		# comments.len should always be > 0, because Slash doesn't
		# accept zero-length comments.  If it is = 0, something is
		# wrong;  don't apply these score modifiers.  (What is
		# likely is that the admin hasn't properly updated the
		# comments table with this new column. - Jamie 2003/03/20)
		if ($user->{clbig} && $user->{clbig_bonus} && $len > $user->{clbig}) {
			$hr->{clbig} = $user->{clbig_bonus};
		}
		if ($user->{clsmall} && $user->{clsmall_bonus} && $len < $user->{clsmall}) {
			$hr->{clsmall} = $user->{clsmall_bonus};
		}
	}

	# If the user is AC and we give AC's a penalty/bonus
	if ($user->{people_bonus_anonymous} && isAnon($C->{uid})) {
		$hr->{people_bonus_anonymous} =
			$user->{people_bonus_anonymous};
	}

	# If you don't trust new users
	if ($user->{new_user_bonus} && $user->{new_user_percent}
		&& 100 - 100*$C->{uid}/$max_uid < $user->{new_user_percent}) {
		$hr->{new_user_bonus} = $user->{new_user_bonus};
	}

	# Adjust reasons. Do we need a reason?
	# Are you threatening me?
	my $reason_name = $reasons->{$C->{reason}}{name};
	if ($reason_name && $user->{"reason_alter_$reason_name"}) {
		$hr->{reason_bonus} =
			$user->{"reason_alter_$reason_name"};
	}

	# Keep your friends close but your enemies closer.
	# Or ignore them, we don't care.
	if ($user->{uid} != $C->{uid}) {
		if ($user->{people}{FRIEND()}{$C->{uid}}) {
			$hr->{people_bonus_friend} =
				$user->{people_bonus_friend};
		}
		if ($user->{people}{FOE()}{$C->{uid}}) {
			$hr->{people_bonus_foe} =
				$user->{people_bonus_foe}
		}
		if ($user->{people}{FREAK()}{$C->{uid}}) {
			$hr->{people_bonus_freak} =
				$user->{people_bonus_freak}
		}
		if ($user->{people}{FAN()}{$C->{uid}}) {
			$hr->{people_bonus_fan} =
				$user->{people_bonus_fan}
		}
		if ($user->{people}{FOF()}{$C->{uid}}) {
			$hr->{people_bonus_fof} =
				$user->{people_bonus_fof}
		}
		if ($user->{people}{EOF()}{$C->{uid}}) {
			$hr->{people_bonus_eof} =
				$user->{people_bonus_eof}
		}
	}

	# Karma bonus time
	if ($user->{karma_bonus} && $C->{karma_bonus} eq 'yes') {
		$hr->{karma_bonus} =
			$user->{karma_bonus};
	}

	# And, the poster-was-a-subscriber bonus
	if ($user->{subscriber_bonus} && $C->{subscriber_bonus} eq 'yes') {
		$hr->{subscriber_bonus} =
			$user->{subscriber_bonus};
	}

	for my $key (grep !/^score_/, keys %$hr) { $points += $hr->{$key} || 0 }
	$points = $max if $points > $max;
	$points = $min if $points < $min;
	$hr->{score_end} = $points;

	if (wantarray) {
		for my $key (grep !/^score_/, keys %$hr) {
			my $val = $hr->{$key} + 0;
			$hr->{$key} = "+$val" if $val > 0;
		}
		return ($points, $hr);
	} else {
		return $points;
	}
}

sub _print_cchp {
	my($discussion, $count, $hp_ar) = @_;
	return unless $discussion->{stoid};
	my $form = getCurrentForm();
	return unless $form->{ssi} && $form->{ssi} eq 'yes' && $form->{cchp};
	my $file_suffix = $form->{cchp};
	$count ||= 0;
	$hp_ar ||= [ ];
	my $constants = getCurrentStatic();

	my($min, $max) = ($constants->{comment_minscore}, 
			  $constants->{comment_maxscore});
	my $num_scores = $max - $min + 1;
	push @$hp_ar, 0 while scalar(@$hp_ar) < $num_scores;
	my $hp_str = join(",", @$hp_ar);

	# If these totals are wanted, print them to the file, so
	# the freshenup.pl task (or whatever) can update without
	# having to redo the work we just did.  Make sure the
	# file exists first (if a malicious web user is able to
	# pass in a cchp value without having created a file that
	# we can write to, it will be ignored).
	my $filename = File::Spec->catfile($constants->{logdir},
		"cchp.$file_suffix");
	if (!-e $filename || !-w _
		|| ((stat _)[2] & 0007)) {
		warn "_print_cchp not trying to open '$filename': "
			. "missing, unwriteable or insecure\n";
	} else {
		if (!sysopen(my $fh, $filename,
			O_WRONLY # file must already exist
		)) {
			warn "_print_cchp cannot open '$filename', $!\n";
		} else {
			$count ||= 0;
			$hp_str ||= '0';
			print $fh "count $count, hitparade $hp_str\n";
			close $fh;
		}
	}
}

########################################################
sub reparentComments {
	my($comments, $reader, $options) = @_;
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	my $threshold = defined $options->{threshold}
		? $options->{threshold}
		: $user->{threshold};

	my $max_depth_allowed = $user->{state}{max_depth} || $constants->{max_depth} || 7;

	return if $user->{state}{noreparent} || (!$max_depth_allowed && !$user->{reparent});

	# Adjust the max_depth_allowed for the root pid or cid.
	# Actually I'm not sure this should be done at all.
	# My guess is that it does the opposite of what's desired
	# when $form->{cid|pid} is set.  And besides, max depth we
	# display is for display, so it should be based on how much
	# we're displaying, not on absolute depth of this thread.
	my $root_cid_or_pid = $form->{cid} || $form->{pid} || 0;
	if ($root_cid_or_pid) {
		my $tmpcid = $root_cid_or_pid;
		while ($tmpcid) {
			my $pid = $reader->getComment($tmpcid, 'pid') || 0;
			last unless $pid;
			$max_depth_allowed++;
			$tmpcid = $pid;
		}
	}

	# The below algorithm assumes that comments are inserted into
	# the database with cid's that increase chronologically, in order
	# words that for any two comments where A's cid > B's cid, that
	# A's timestamp > B's timestamp also.

	for my $x (sort { $a <=> $b } keys %$comments) {
		next if $x == 0; # exclude the fake "cid 0" comment

		my $pid = $comments->{$x}{pid} || 0;
		my $reparent = 0;

		# First, if this comment is above the user's desired threshold
		# (and thus will likely be shown), but its parent is below
		# the desired threshold (and thus will not likely be shown),
		# bounce it up the chain until we can reparent it to a comment
		# that IS being shown.  Effectively we pretend the invisible
		# comments between this comment and its (great-etc.) grandparent
		# do not exist.
		#
		# But, if all its (great-etc.) grandparents are either invisible
		# or chronologically precede the root comment, don't reparent it
		# at all.
		if ($user->{reparent} && $comments->{$x}{points} >= $threshold) { # XXX either $comments->{$x}{points} or $threshold is undefined here, not sure which or why
			my $tmppid = $pid;
			while ($tmppid
				&& $comments->{$tmppid} && defined($comments->{$tmppid}{points})
				&& $comments->{$tmppid}{points} < $threshold) {
				$tmppid = $comments->{$tmppid}{pid} || 0;
				$reparent = 1;
			}

			if ($reparent && $tmppid >= $root_cid_or_pid) {
				$pid = $tmppid;
			} else {
				$reparent = 0;
			}
		}

		# Second, if the above did not find a suitable (great)grandparent,
		# we try a second method of collapsing to a (great)grandparent:
		# check whether the depth of this comment is too great to show
		# nested so deeply, and if so, ratchet it back.  Note that since
		# we are iterating through %$comments in cid order, the parents of
		# this comment will already have gone through this code and thus
		# already should have their {depth}s set.  (At least that's the
		# theory, I'm not sure that part really works.)
		if ($max_depth_allowed && !$reparent) {
			# set depth of this comment based on parent's depth
			$comments->{$x}{depth} = ($pid ? ($comments->{$pid}{depth} ||= 0) : 0) + 1;

			# go back each pid until we find one with depth less than $max_depth_allowed
			while ($pid && defined($comments->{$pid})
				&& ($comments->{$pid}{depth} ||= 0) >= $max_depth_allowed) {
				$pid = $comments->{$pid}{pid};
				$reparent = 1;
			}
		}

		if ($reparent) {
			# remove child from old parent
			if ($pid >= $root_cid_or_pid) {
				@{$comments->{$comments->{$x}{pid}}{kids}} =
					grep { $_ != $x }
					@{$comments->{$comments->{$x}{pid}}{kids}}
			}

			# add child to new parent
			$comments->{$x}{pid} = $pid;
			push @{$comments->{$pid}{kids}}, $x;
		}
	}
}

# I wonder if much of this logic should be moved out to the theme.
# This logic can then be placed at the theme level and would eventually
# become what is put into $comment->{no_moderation}. As it is, a lot
# of the functionality of the moderation engine is intrinsically linked
# with how things behave on Slashdot.	- Cliff 6/6/01
# I rearranged the order of these tests (check anon first for speed)
# and pulled some of the tests from dispComment/_hard_dispComment
# back here as well, just to have it all in one place. - Jamie 2001/08/17
# And now it becomes a function of its own - Jamie 2002/02/26
sub _can_mod {
	my($comment) = @_;
	my $user = getCurrentUser();
	my $constants = getCurrentStatic();

	# Do some easy and high-priority initial tests.  If any of
	# these is true, this comment is not moderatable, and these
	# override the ACL and seclev tests.
	return 0 if !$comment;
	return 0 if
		    $user->{is_anon}
		|| !$constants->{allow_moderation}
		||  $comment->{no_moderation};
	
	# More easy tests.  If any of these is true, the user has
	# authorization to mod any comments, regardless of any of
	# the tests that come later.
	return 1 if
		    $constants->{authors_unlimited}
		&&  $user->{seclev} >= $constants->{authors_unlimited};
	return 1 if
		    $user->{acl}{modpoints_always};

	# OK, the user is an ordinary user, so see if they have mod
	# points and do some other fairly ordinary tests to try to
	# rule out whether they can mod.
	return 0 if
		    $user->{points} <= 0
		|| !$user->{willing}
		||  $comment->{uid} == $user->{uid}
		||  $comment->{lastmod} == $user->{uid}
		||  $comment->{ipid} eq $user->{ipid};
	return 0 if
		    $constants->{mod_same_subnet_forbid}
		&&  $comment->{subnetid} eq $user->{subnetid};
	return 0 if
		   !$constants->{comments_moddable_archived}
		&&  $user->{state}{discussion_archived};

	# Last test; this one involves a bit of calculation to set
	# time_unixepoch in the comment structure itself, which is
	# why we saved it for last.  timeCalc() is not the world's
	# fastest function.
	$comment->{time_unixepoch} ||= timeCalc($comment->{date}, "%s", 0);
	my $hours = $constants->{comments_moddable_hours}
		|| 24 * $constants->{archive_delay};
	return 0 if $comment->{time_unixepoch} < time - 3600*$hours;

	# All the ordinary tests passed, there's nothing stopping
	# this user from modding this comment.
	return 1;
}

#========================================================================

=head2 printComments(SID [, PID, CID])

Prints all that comment stuff.

=over 4

=item Parameters

=over 4

=item SID

The story ID to print comments for.

=item PID

The parent ID of the comments to print.

=item CID

The comment ID to print.

=back

=item Return value

None.

=item Dependencies

The 'printCommentsMain', 'printCommNoArchive',
and 'printCommComments' template blocks.

=back

=cut

sub printComments {
	my($discussion, $pid, $cid, $options) = @_;
	my $user = getCurrentUser();
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $form = getCurrentForm();

	if (!$discussion || !$discussion->{id}) {
		print getData('no_such_sid', {}, '');
		return 0;
	}

	my $discussion2 = $user->{discussion2} && $user->{discussion2} =~ /^(?:slashdot|uofm)$/;

	if ($discussion2 && $user->{mode} ne 'metamod') {
		$user->{mode} = $form->{mode} = 'thread';
		$user->{commentsort} = 0;
		$user->{reparent} = 0;
		$user->{state}{max_depth} = $constants->{max_depth} + 3;
	}

	# Couple of rules on how to treat the discussion depending on how mode is set -Brian
	$discussion->{type} = isDiscussionOpen($discussion);

	$pid ||= 0;
	$cid ||= 0;
	my $cidorpid = $cid || $pid;
	my $lvl = 0;

	# Get the Comments
	my $sco = { force_read_from_master => $options->{force_read_from_master} || 0 };
	$sco->{one_cid_only} = 1 if $cidorpid && (
		   $user->{mode} eq 'nocomment'
		|| ( $user->{mode} eq 'flat' && $user->{commentsort} > 3 )
		|| $options->{just_submitted}
	);
	# For now, until we are able to pull hitparade into discussions so we can
	# read it here, don't use the one_cid_only optimization feature.
	$sco->{one_cid_only} = 0;

	my($comments, $count) = selectComments($discussion, $cidorpid, $sco);

	if ($cidorpid && !exists($comments->{$cidorpid})) {
		# No such comment in this discussion.
		my $d = getData('no_such_comment', {
			sid => $discussion->{id},
			cid => $cid,
		}, '');
		print $d;
		return 0;
	}

	# Should I index or just display normally?
	my $cc = 0;
	$cc = $comments->{$cidorpid}{visiblekids}
		if $comments->{$cidorpid}
			&& $comments->{$cidorpid}{visiblekids};

	$lvl++ if $user->{mode} ne 'flat'
		&& $user->{mode} ne 'archive'
		&& $user->{mode} ne 'metamod'
		&& $cc > $user->{commentspill}
		&& ( $user->{commentlimit} > $cc ||
		     $user->{commentlimit} > $user->{commentspill} );

	if ($discussion->{type} eq 'archived'
		|| ($discussion->{is_future} && !$constants->{subscribe_future_post})
		|| ($discussion->{commentstatus} && $discussion->{commentstatus} ne 'enabled')
	) {
		# This was named "comment_read_only" but that's not very
		# descriptive;  let's call it what it is... -Jamie 2002/02/26
		if ($discussion->{type} eq 'archived') {
			$user->{state}{discussion_archived} = 1;
		}
		if ($discussion->{is_future} && !$constants->{subscribe_future_post}) {
			$user->{state}{discussion_future_nopost} = 1;
		}
		slashDisplay('printCommNoArchive', { discussion => $discussion });
	}

	slashDisplay('printCommentsMain', {
		comments	=> $comments,
		title		=> $discussion->{title},
		'link'		=> $discussion->{url},
		count		=> $count,
		sid		=> $discussion->{id},
		cid		=> $cid,
		pid		=> $pid,
		lvl		=> $lvl,
	});

	return if $user->{state}{nocomment} || $user->{mode} eq 'nocomment';

	my($comment, $next, $previous);
	if ($cid) {
		my($next, $previous);
		$comment = $comments->{$cid};
		if (my $sibs = $comments->{$comment->{pid}}{kids}) {
			for (my $x = 0; $x < @$sibs; $x++) {
				($next, $previous) = ($sibs->[$x+1], $sibs->[$x-1])
					if $sibs->[$x] == $cid;
			}
		}

		$next = $comments->{$next} if $next;
		$previous = $comments->{$previous} if $previous;
	}

	# Flat and theaded mode don't index, even on large stories, so they
	# need to use more, smaller pages. if $cid is 0, then we get the
	# totalviskids for the story 		--Pater
	my $total = ($user->{mode} eq 'flat' || $user->{mode} eq 'nested')
		? $comments->{$cidorpid}{totalvisiblekids}
		: $cc;

	my $lcp = $discussion2
		? ''
		: linkCommentPages($discussion->{id}, $pid, $cid, $total);

	# Figure out whether to show the moderation button.  We do, but
	# only if at least one of the comments is moderatable.
	my $can_mod_any = _can_mod($comment);
	if (!$can_mod_any) {
		CID: for my $cid (keys %$comments) {
			if (_can_mod($comments->{$cid})) {
				$can_mod_any = 1;
				last CID;
			}
		}
	}

	my $anon_dump;
	if ($discussion2) {
		require Data::JavaScript::Anon;
		$anon_dump = \&Data::JavaScript::Anon::anon_dump;
	}

	my $comment_html = slashDisplay('printCommComments', {
		can_moderate	=> $can_mod_any,
		comment		=> $comment,
		comments	=> $comments,
		'next'		=> $next,
		previous	=> $previous,
		sid		=> $discussion->{id},
		cid		=> $cid,
		pid		=> $pid,
		cc		=> $cc,
		lcp		=> $lcp,
		lvl		=> $lvl,
		discussion2	=> $discussion2,
		anon_dump	=> $anon_dump,
	}, { Return => 1 });

	# We have to get the comment text we need (later we'll search/replace
	# them into the text).
	my $comment_text = $slashdb->getCommentTextCached(
		$comments, $user->{state}{cids},
		{ mode => $form->{mode}, cid => $form->{cid} }
	);

	# OK we have all the comment data in our hashref, so the search/replace
	# on the nearly-fully-rendered page will work now.
	$comment_html =~ s|<SLASH type="COMMENT-TEXT">(\d+)</SLASH>|$comment_text->{$1}|g;

	print $comment_html;
}

#========================================================================

=head2 moderatorCommentLog(TYPE, ID)

Prints a table detailing the history of moderation of a particular
comment and/or the reasons why a comment is scored like it is.
(The template name is modCommentLog and this shows info about not
just moderation but modifiers;  this function should probably be
renamed the same.)

=over 4

=item Parameters

=over 4

=item TYPE

String describing type of the ID data:  cid, uid, cuid, ipid, subnetid,
bipid or bsubnetid.

=item ID

Cid or IPID.

=back

=item Return value

The HTML.

=item Dependencies

The 'modCommentLog' template block.

=back

=cut

sub moderatorCommentLog {
	my($type, $value, $options) = @_;
	$options ||= {};
	my $title = $options->{title};
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();

	# If the user doesn't want even to see the numeric score of
	# a comment, they certainly don't want to see all this detail.
	return "" if $user->{noscores};

	my $seclev = $user->{seclev};
	my $mod_admin = $seclev >= $constants->{modviewseclev} ? 1 : 0;

	my $asc_desc = $type eq 'cid' ? 'ASC' : 'DESC';
	my $limit = $type eq 'cid' ? 0 : 100;
	my $both_mods = (($type =~ /ipid/) || ($type =~ /subnetid/) || ($type =~ /global/)) ? 1 : 0;
	my $skip_ip_disp = 0;
	if ($type =~ /^b(ip|subnet)id$/) {
		$skip_ip_disp = 1;
	} elsif ($type =~ /^(ip|subnet)id$/) {
		$skip_ip_disp = 2;
	}
	my $gmcl_opts = {};
	$gmcl_opts->{hours_back} = $options->{hours_back} if $options->{hours_back};
	$gmcl_opts->{order_col} = "reason" if $type eq "cid";

	my $mods = $slashdb->getModeratorCommentLog($asc_desc, $limit,
		$type, $value, $gmcl_opts);

	my $timestamp_hr = exists $options->{hr_hours_back}
		? $slashdb->getTime({ add_secs => -3600 * $options->{hr_hours_back} })
		: "";

	if (!$mod_admin) {
		# Eliminate inactive moderations from the list.
		$mods = [ grep { $_->{active} } @$mods ];
	}

	my($reasons, @return, @reasonHist);
	my $reasonTotal = 0;
	$reasons = $slashdb->getReasons();

	# Note: Before 2001/01/27 or so, the only things being displayed
	# in this template were moderations, and if there were none,
	# we could short-circuit here if @$mods was empty.  But now,
	# the template handles that decision.
	my $seen_mods = {};
	for my $mod (@$mods) {
		$seen_mods->{$mod->{id}}++;
		vislenify($mod); # add $mod->{ipid_vis}
		#$mod->{ts} = substr($mod->{ts}, 5, -3);
		$mod->{nickname2} = $slashdb->getUser($mod->{uid2},
			'nickname') if $both_mods; # need to get 2nd nick
		next unless $mod->{active};
		$reasonHist[$mod->{reason}]++;
		$reasonTotal++;
	}

	my $listed_reason = 0;
	if ($type eq 'cid') {
		my $val_q = $slashdb->sqlQuote($value);
		$listed_reason = $slashdb->sqlSelect("reason", "comments", "cid=$val_q");
	}
	my @reasonsTop = _getTopModReasons($reasonTotal, $listed_reason, \@reasonHist);

	my $show_cid    = ($type eq 'cid') ? 0 : 1;
	my $show_modder = $mod_admin ? 1 : 0;
	my $mod_to_from = ($type eq 'uid') ? 'to' : 'from';

	my $modifier_hr = { };
	my $reason = 0;
	if ($type eq 'cid') {
		my $cid_q = $slashdb->sqlQuote($value);
		my($min, $max) = ($constants->{comment_minscore}, 
				  $constants->{comment_maxscore});
		my $max_uid = $slashdb->countUsers({ max => 1 });

		my $select = "cid, uid, karma_bonus, reason, points, pointsorig, tweak, tweak_orig";
		if ($constants->{plugin}{Subscribe} && $constants->{subscribe}) {
			$select .= ", subscriber_bonus";
		}
		my $comment = $slashdb->sqlSelectHashref(
			$select,
			"comments",
			"cid=$cid_q");
		$comment->{comment} = $slashdb->sqlSelect(
			"comment",
			"comment_text",
			"cid=$cid_q");
		$reason = $comment->{reason};

		my $user = getCurrentUser();
		my $points;
		($points, $modifier_hr) = _get_points($comment, $user, $min, $max, $max_uid, $reasons);
	}

	my $this_user;
	$this_user = $slashdb->getUser($value) if $type eq "uid";
	my $cur_uid;
	$cur_uid = $value if $type eq "uid" || $type eq "cuid";

	my $mod_ids = [keys %$seen_mods];
	my $mods_to_m2s;
	if ($constants->{show_m2s_with_mods} && $options->{show_m2s}) {
		$mods_to_m2s = $slashdb->getMetamodsForMods($mod_ids, $constants->{m2_limit_with_mods});
	}
	
	# Do the work to determine which moderations share the same m2s
	if ($type eq "cid"
		&& $constants->{show_m2s_with_mods}
		&& $constants->{m2_multicount}
		&& $options->{show_m2s}){
		foreach my $m (@$mods){
			my $key = '';
			foreach my $m2 (@{$mods_to_m2s->{$m->{id}}}) {
				$key .= "$m2->{uid} $m2->{val},";
			}
			$m->{m2_identity} = $key;
		}
		@$mods = sort {
			$a->{reason} <=> $b->{reason}
				||
			$b->{active} <=> $a->{active}
				||
			$a->{m2_identity} cmp $b->{m2_identity}
		} @$mods;
	}
	my $data = {
		type		=> $type,
		mod_admin	=> $mod_admin, 
		mods		=> $mods,
		reasonTotal	=> $reasonTotal,
		reasonHist	=> \@reasonHist,
		reasonsTop	=> \@reasonsTop,
		reasons		=> $reasons,
		reason		=> $reason,
		modifier_hr	=> $modifier_hr,
		show_cid	=> $show_cid,
		show_modder	=> $show_modder,
		mod_to_from	=> $mod_to_from,
		both_mods	=> $both_mods,
		timestamp_hr	=> $timestamp_hr,
		skip_ip_disp    => $skip_ip_disp,
		this_user	=> $this_user,
		title		=> $title,
		mods_to_m2s	=> $mods_to_m2s,
		show_m2s	=> $options->{show_m2s},
		cur_uid		=> $cur_uid,
		value		=> $value,
		need_m2_form	=> $options->{need_m2_form},
		need_m2_button	=> $options->{need_m2_button},
		meta_mod_only	=> $options->{meta_mod_only},
	};
	slashDisplay('modCommentLog', $data, { Return => 1, Nocomm => 1 });
}

# Takes a reason histogram, a list of counts of each reason mod.
# So $reasonHist[1] is the number of Offtopic moderations (at
# least if Offtopic is still reason 1).  Returns a list of hashrefs,
# the top 3 mods performed and their percentages, rounded to the
# nearest 10%, sorted largest to smallest.
sub _getTopModReasons{
	my($reasonTotal, $listed_reason, $reasonHist_ar) = @_;
	return ( ) unless $reasonTotal;
	my $top_needed = 3;
	my @reasonsTop = ( );

	# Algorithm by MJD in Perl Quiz of the Week #7
	# http://perl.plover.com/qotw/r/solution/007
	my @p = map { $_*10/$reasonTotal } @$reasonHist_ar;
	my @r = map { int($_+0.5) } @p;
	my @e = map { $p[$_] - $r[$_] } (0..$#r);
	my $total_error = 0;
	for (@e) { $total_error += $_ }
	# Round total_error to int, to avoid float rounding error
	my $sign = $total_error < 0 ? -1 : 1;
	$total_error *= $sign;
	$total_error = int($total_error+0.5);
	if ($total_error) {
		for (0..$#r) {
			next unless $e[$_] * $sign > 0;
			$r[$_] += $sign;
			$total_error--;
			last if $total_error <= 0;
		}
	}

	# This part I added, so if it breaks, don't blame MJD :) JRM
	my %reasonRound = map { ($_, $r[$_]*10) } (0..$#r);
	my @rr_keys = sort { $a <=> $b } keys %reasonRound;
	my $min = (sort { $b <=> $a } values %reasonRound)[$top_needed-1];
	for my $key (0..$#r) {
		$reasonRound{$key} = 0 if $reasonRound{$key} < $min;
	}
	my $have = 0;
	for my $key (0..$#r) {
		++$have if $reasonRound{$key} > $min;
	}
	for my $key (0..$#r) {
		if ($reasonRound{$key} == $min) {
			if ($have >= $top_needed) {
				$reasonRound{$key} = 0;
			} else {
				++$have;
			}
		}
	}
	for my $reason (1..$#r) {
		next unless $reasonRound{$reason};
		push @reasonsTop, {
			reason => $reason,
			percent => $reasonRound{$reason},
		};
	}
	@reasonsTop = sort {
		($b->{reason} == $listed_reason) <=> ($a->{reason} == $listed_reason)
		||
		$b->{percent} <=> $a->{percent}
		||
		$a->{reason} <=> $b->{reason}
	} @reasonsTop;

	return @reasonsTop;
}

#========================================================================

=head2 displayThread(SID, PID, LVL, COMMENTS)

Displays an entire thread.  w00p!

=over 4

=item Parameters

=over 4

=item SID

The story ID.

=item PID

The parent ID.

=item LVL

What level of the thread we're at.

=item COMMENTS

Arrayref of all our comments.

=back

=item Return value

The thread.

=item Dependencies

The 'displayThread' template block.

=back

=cut

sub displayThread {
	my($sid, $pid, $lvl, $comments, $const) = @_;
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	$lvl ||= 0;
	my $displayed = 0;
	my $mode = getCurrentUser('mode');
	my $indent = 1;
	my $full = my $cagedkids = !$lvl;
	my $hidden = my $skipped = 0;
	my $return = '';

	my $discussion2 = $user->{discussion2} && $user->{discussion2} =~ /^(?:slashdot|uofm)$/;
	my $highlightthresh = $user->{highlightthresh};
	$highlightthresh = $user->{threshold} if $highlightthresh < $user->{threshold};

	# FYI: 'archive' means we're to write the story to .shtml at the close
	# of the discussion without page breaks.  'metamod' means we're doing
	# metamoderation.
	if ($user->{mode} eq 'flat'
		|| $user->{mode} eq 'archive'
		|| $user->{mode} eq 'metamod'
		|| $user->{mode} eq 'parents'
		|| $user->{mode} eq 'child') {
		$indent = 0;
		$full = 1;
	} elsif ($user->{mode} eq 'nested') {
		$indent = 1;
		$full = 1;
	}

	unless ($const) {
		for (map { ($_ . "begin", $_ . "end") }
			qw(table cage cagebig indent comment fullcomment)) {
			$const->{$_} = getData($_, '', '');
		}
	}

	for my $cid (@{$comments->{$pid}{kids}}) {
		my $comment = $comments->{$cid};

		$skipped++;
		# since nested and threaded show more comments, we can skip
		# ahead more, counting all the visible kids.	--Pater
		$skipped += $comment->{totalvisiblekids} if ($user->{mode} eq 'flat' || $user->{mode} eq 'nested');
		$form->{startat} ||= 0;
		next if $skipped <= $form->{startat} && !$discussion2;
		$form->{startat} = 0; # Once We Finish Skipping... STOP

		my $class = 'oneline';
		if ($comment->{points} < $user->{threshold}) {
			if ($user->{is_anon} || ($user->{uid} != $comment->{uid})) {
				if ($discussion2) {
					$class = 'hidden';
					$hidden++;
				} else {
					$hidden++;
					next;
				}
			}
		}

		my $highlight = 1 if $comment->{points} >= $highlightthresh && $class ne 'hidden';
		$class = 'full' if $highlight;

		$user->{state}{comments}{totals}{$class}++;

		my $finish_list = 0;

		if ($full || $highlight || $discussion2) {
			if ($lvl && $indent) {
				$return .= $const->{tablebegin} .
					dispComment($comment, { class => $class }) .
					$const->{tableend};
				$cagedkids = 0;
			} else {
				$return .= dispComment($comment, { class => $class });
			}
			$displayed++;
		} else {
			my $pntcmt = @{$comments->{$comment->{pid}}{kids}} > $user->{commentspill};
			$return .= $const->{commentbegin} .
				linkComment($comment, $pntcmt, 1);
			$finish_list++;
		}
		$return .= $const->{fullcommentend} if ($user->{mode} eq 'flat');

		if ($comment->{kids} && ($user->{mode} ne 'parents' || $pid)) {
			if (my $str = displayThread($sid, $cid, $lvl+1, $comments, $const)) {
				$return .= $const->{cagebegin} if $cagedkids;
				$return .= $const->{indentbegin} if $indent;
				$return .= $str;
				$return .= "$const->{indentend}" if $indent;
				$return .= $const->{cageend} if $cagedkids;
			}
			# in flat or nested mode, all visible kids will
			# be shown, so count them.	-- Pater
			$displayed += $comment->{totalvisiblekids} if ($user->{mode} eq 'flat' || $user->{mode} eq 'nested');
		}

		$return .= "$const->{commentend}" if $finish_list;
		$return .= "$const->{fullcommentend}" if (($full || $highlight || $discussion2) && $user->{mode} ne 'flat');

		last if $displayed >= $user->{commentlimit} && !$discussion2;
	}

	if ($hidden && ($discussion2 || (!$user->{hardthresh} && $user->{mode} ne 'archive' && $user->{mode} ne 'metamod'))) {
		my $link = linkComment({
			sid		=> $sid,
			threshold	=> $constants->{comment_minscore},
			pid		=> $pid,
			subject		=> getData('displayThreadLink', { 
						hidden => $hidden 
					   }, ''),
			subject_only	=> 1,
		});
		if ($discussion2) {
			$return .= slashDisplay('displayThread', {
				'link'		=> $link,
				discussion2	=> $discussion2,
				pid		=> $pid,
				hidden		=> $hidden
			}, { Return => 1, Nocomm => 1 });
		} else {
			$return .= $const->{cagebigbegin} if $cagedkids;
			$return .= slashDisplay('displayThread',
				{ 'link' => $link },
				{ Return => 1, Nocomm => 1 }
			);
			$return .= $const->{cagebigend} if $cagedkids;
		}
	}

	return $return;
}

#========================================================================

=head2 dispComment(COMMENT)

Displays a particular comment.

=over 4

=item Parameters

=over 4

=item COMMENT

Hashref of comment data.
If the 'no_moderation' key of the COMMENT hashref exists, the
moderation elements of the comment will not be displayed.

=back

=item Return value

The comment to display.

=item Dependencies

The 'dispComment' template block.

=back

=cut

sub dispComment {
	my($comment, $options) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $gSkin = getCurrentSkin();
	my $maxcommentsize = $options->{maxcommentsize} || $user->{maxcommentsize};

	my($comment_shrunk, %reasons);
	if ($form->{mode} ne 'archive'
		&& $comment->{len} > $maxcommentsize
		&& $form->{cid} ne $comment->{cid})
	{
		$comment_shrunk = 1;
	}

	$comment->{sig} = parseDomainTags($comment->{sig}, $comment->{fakeemail});
	if ($comment->{sig}) {
		$comment->{sig} =~ s/^\s*-{1,5}\s*<(?:P|BR)>//i;
		$comment->{sig} = getData('sigdash', {}, 'comments')
			. $comment->{sig};
	}

	if (!$comment->{karma_bonus} || $comment->{karma_bonus} eq 'no') {
		for ($comment->{sig}, $comment->{comment}) {
			$_ = noFollow($_);
		}
	}

	my $reasons = $reader->getReasons();

	my $can_mod = _can_mod($comment);

	# don't inherit these ...
	for (qw(sid cid pid date subject comment uid points lastmod
		reason nickname fakeemail homepage sig)) {
		$comment->{$_} = '' unless exists $comment->{$_};
	}

	# ipid/subnetid need munging into one text string
	if ($user->{seclev} >= 100 && $comment->{ipid} && $comment->{subnetid}) {
		vislenify($comment); # create $comment->{ipid_vis} and {subnetid_vis}
		if ($constants->{comments_hardcoded}) {
			$comment->{ipid_display} = <<EOT;
<br>IPID: <a href="$constants->{real_rootdir}/users.pl?op=userinfo&amp;userfield=$comment->{ipid}&amp;fieldname=ipid">$comment->{ipid_vis}</a>&nbsp;&nbsp;SubnetID: 
<a href="$constants->{real_rootdir}/users.pl?op=userinfo&amp;userfield=$comment->{subnetid}&amp;fieldname=subnetid">$comment->{subnetid_vis}</a>
EOT
		} else {
			$comment->{ipid_display} = slashDisplay(
				"ipid_display", { data => $comment },
				1);
		}
	} else {
		$comment->{ipid_display} = "";
	}

	# we need a display-friendly fakeemail string
	$comment->{fakeemail_vis} = ellipsify($comment->{fakeemail});
	push @{$user->{state}{cids}}, $comment->{cid};

	$options->{class} ||= 'full';

	return _hard_dispComment(
		$comment, $constants, $user, $form, $comment_shrunk,
		$can_mod, $reasons, $options
	) if $constants->{comments_hardcoded};

	return slashDisplay('dispComment', {
		%$comment,
		comment_shrunk	=> $comment_shrunk,
		reasons		=> $reasons,
		can_mod		=> $can_mod,
		is_anon		=> isAnon($comment->{uid}),
		class		=> $options->{class}
	}, { Return => 1, Nocomm => 1 });
}

#========================================================================

=head2 dispStory(STORY, AUTHOR, TOPIC, FULL, OTHER)

Display a story.

=over 4

=item Parameters

=over 4

=item STORY

Hashref of data about the story.

=item AUTHOR

Hashref of data about the story's author.

=item TOPIC

Hashref of data about the story's topic.

=item FULL

Boolean for show full story, or just the
introtext portion.

=item OTHER

Hash with parameters such as alternate template.

=back

=item Return value

Story to display.

=item Dependencies

The 'dispStory' template block.

=back

=cut


sub dispStory {
	my($story, $author, $topic, $full, $other) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $constants = getCurrentStatic();
	my $gSkin = getCurrentSkin();
	my $template_name = $other->{story_template}
		? $other->{story_template} : 'dispStory';

	# Might this logic be better off in the template? Its sole purpose
	# is aesthetics.
	$other->{magic} = !$full
			&& index($story->{title}, ':') == -1
			&& $story->{primaryskid} ne $gSkin->{skid}
			&& $story->{primaryskid} ne $constants->{mainpage_skid}
		if !exists $other->{magic};

	$other->{preview} ||= 0;
	my %data = (
		story		=> $story,
		topic		=> $topic,
		author		=> $author,
		full		=> $full,
		stid	 	=> $other->{stid},
		topics	 	=> $other->{topics_chosen},
		topiclist 	=> $other->{topiclist},
		magic	 	=> $other->{magic},
		width	 	=> $constants->{titlebar_width},
		preview  	=> $other->{preview},
		dispmode 	=> $other->{dispmode},
		dispoptions	=> $other->{dispoptions} || {},
		thresh_commentcount => $other->{thresh_commentcount},
		expandable 	=> $other->{expandable},
		getintro	=> $other->{getintro},
	);

#use Data::Dumper; print STDERR scalar(localtime) . " dispStory data: " . Dumper(\%data);

	return slashDisplay($template_name, \%data, 1);
}

#========================================================================

=head2 displayStory(SID, FULL, OTHER)

Display a story by SID (frontend to C<dispStory>).

=over 4

=item Parameters

=over 4

=item SID

Story ID to display.

=item FULL

Boolean for show full story, or just the
introtext portion.

=item OTHER 

hash containing other parameters such as 
alternate template name, or titlebar magic.

=back

=item Return value

Rendered story

=back

=cut

sub displayStory {
	my($stoid, $full, $options, $story_cache) = @_;	

	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $gSkin = getCurrentSkin();
	
	my $return;
	my $story;
	if ($story_cache && $story_cache->{$stoid}) {
		# If the caller passed us a ref to a cache of all the
		# story data we need, great!  Use it.
		$story = $story_cache->{$stoid};
	} elsif ($options->{force_cache_freshen}) {
		# If the caller is insisting that we go to the main DB
		# rather than using any cached data or even a reader,
		# then do that.  This is done when e.g. freshenup.pl
		# wants to write the "rendered" version of a story.
		my $slashdb = getCurrentDB();
		$story = $slashdb->getStory($stoid, "", $options->{force_cache_freshen});
		$story->{is_future} = 0;
	} else {
		# The above don't apply;  just use a reader (and maybe
		# its cache will save a trip to the actual DB).
		$story = $reader->getStory($stoid);
	}

	# There are many cases when we'd not want to return the pre-rendered text
	# from the DB.
	#
	# XXXNEWINDEX - Currently don't have a rendered copy for brief mode
	#               This is probably okay since brief mode contains basically
	#               the same info as storylinks which is generated dynamically
	#               and different users will have different links / threshold counts

	if (	   !$constants->{no_prerendered_stories}
		&& $constants->{cache_enabled}
		&& $story->{rendered} && !$options->{force_cache_freshen}
		&& !$form->{simpledesign} && !$user->{simpledesign}
		&& !$form->{lowbandwidth} && !$user->{lowbandwidth}
		&& (!$form->{ssi} || $form->{ssi} ne 'yes')
		&& !$user->{noicons}
		&& !$form->{issue}
		&& $gSkin->{skid} == $constants->{mainpage_skid}
		&& !$full
		&& !$options->{is_future}	 # can $story->{is_future} ever matter?
		&& ($options->{mode} && $options->{mode} ne "full")
		&& (!$options->{dispmode} || $options->{dispmode} ne "brief")
	) {
		$return = $story->{rendered};
	} else {

		my $author = $reader->getAuthor($story->{uid},
				['nickname', 'fakeemail', 'homepage']);
		my $topic = $reader->getTopic($story->{tid});
		$story->{atstorytime} = "__TIME_TAG__";

		if (!$options->{dispmode} || $options->{dispmode} ne "brief" || $options->{getintro}) {
			$story->{introtext} = parseSlashizedLinks($story->{introtext});
			$story->{introtext} = processSlashTags($story->{introtext});
		}

		if ($full) {
			$story->{bodytext} = parseSlashizedLinks($story->{bodytext});
			$story->{bodytext} = processSlashTags($story->{bodytext}, { break => 1 });
			$options->{topiclist} = $reader->getTopiclistForStory($story->{sid});
			# if a secondary page, put bodytext where introtext would normally go
			# maybe this is not the right thing, but is what we are doing for now;
			# let me know if you have another idea -- pudge
			$story->{introtext} = delete $story->{bodytext} if $form->{pagenum} > 1;
		}

		$return = dispStory($story, $author, $topic, $full, $options);

	}

	if (!$options->{force_cache_freshen}) {
		# Only do the following if force_cache_freshen is not set:
		# as it is by freshenup.pl when (re)building the 'rendered'
		# cached data for a story.
		my $df = ($user->{mode} eq "archive" || ($story->{is_archived} eq "yes" && $user->{is_anon}))
			? $constants->{archive_dateformat} : "";
		my $storytime = timeCalc($story->{'time'}, $df);
		my $atstorytime;
		if ($options->{is_future} && !($user->{author} || $user->{is_admin})) {
			$atstorytime = $constants->{subscribe_future_name};
		} else {
			$atstorytime = $user->{aton} . " " . timeCalc($story->{'time'}, $df);
		}
		$return =~ s/\Q__TIME_TAG__\E/$atstorytime/;

		if ($constants->{plugin}{Tags}
			&&  $user->{tags_canread_stories}
			&& !$user->{tags_turnedoff}
			&& (!$options->{dispmode} || $options->{dispmode} ne 'brief')) {

			my @tags_top = split / /, ($story->{tags_top} || '');
			my $tags_reader = getObject('Slash::Tags', { db_type => 'reader' });
			my @tags_example = $tags_reader->getExampleTagsForStory($story);
			$return .= slashDisplay('tagsstorydivtagbox', {
				story		=>  $story,
				tags_top	=> \@tags_top,
				tags_example	=> \@tags_example,
			}, { Return => 1 });

		}
	}

	return $return;
}

#========================================================================

sub displayRelatedStories {
	my($stoid) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();
	my $gSkin = getCurrentSkin();
	my $return = "";

	my $related = $reader->getRelatedStoriesForStoid($stoid);

	foreach my $rel (@$related) {
		if ($rel->{rel_sid}) {
			my $viewable = $reader->checkStoryViewable($rel->{rel_sid});
			next if !$viewable;
			my $related_story = $reader->getStory($rel->{rel_sid});
			$return .= displayStory($related_story->{stoid}, 0, { dispmode => "brief", getintro => 1, expandable => 1 });
		} elsif ($rel->{cid}) {
			my $comment = $reader->getComment($rel->{cid});
			my $discussion = $reader->getDiscussion($comment->{sid});
			my $comment_user = $reader->getUser($comment->{uid});
			my $is_anon = isAnon($comment->{uid});
			$return .= slashDisplay("comment_related", { comment => $comment, comment_user => $comment_user, discussion => $discussion, is_anon => $is_anon }, { Return => 1});
		} elsif ($rel->{title}) {
			$return .= slashDisplay("url_related", { title => $rel->{title}, url => $rel->{url} }, { Return => 1 });
		}
	}
	return $return;
}


#========================================================================

=head2 getOlderStories(STORIES, SECTION)

Get older stories for older stories box.

=over 4

=item Parameters

=over 4

=item STORIES

Array ref of the "essentials" of the stories to display, retrieved from
getStoriesEssentials.

=item SECTION

Section name or Hashref of section data.

=back

=item Return value

The older stories, formatted.

=item Dependencies

The 'getOlderStories' template block.

=back

=cut

sub getOlderStories {
	my($stories, $section, $stuff) = @_;
	my($count, $newstories);
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $form = getCurrentForm();

	for my $story (@$stories) {
		# Use one call and parse it, it's cheaper :) -Brian
		my($day_of_week, $month, $day, $secs) =
			split m/ /, timeCalc($story->{time}, "%A %B %d %s");
		$day =~ s/^0//;
		$story->{day_of_week} = $day_of_week;
		$story->{month} = $month;
		$story->{day} = $day;
		$story->{secs} = $secs;
		$story->{issue} ||= timeCalc($story->{time}, '%Y%m%d');
		$story->{'link'} = linkStory({
			'link'  => $story->{title},
			sid     => $story->{sid},
			tid     => $story->{tid},
			section => $story->{section},
		});
	}

	my($today, $tomorrow, $yesterday, $week_ago) = getOlderDays($form->{issue});

	$form->{start} ||= 0;

	my $artcount = $user->{is_anon} ? $section->{artcount} : $user->{maxstories};
	$artcount ||= 0;

	# The template won't display all of what's passed to it (by default
	# only the first $section->{artcount}).  "start" is just an offset
	# that gets incremented.
	slashDisplay('getOlderStories', {
		stories		=> $stories,
		section		=> $section,
		cur_time	=> time,
		today		=> $today,
		tomorrow	=> $tomorrow,
		yesterday	=> $yesterday,
		week_ago	=> $week_ago,
		start		=> int($artcount/3) + $form->{start},	
		first_date	=> $stuff->{first_date},
		last_date	=> $stuff->{last_date}
	}, 1);
}

#========================================================================
sub getOlderDays {
	my($issue) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my($today, $tomorrow, $yesterday, $week_ago);
	# week prior to yesterday (oldest story we'll get back when we do
	# a getStoriesEssentials for yesterday's issue)
	if ($issue) {
		my($y, $m, $d) = $issue =~ /^(\d\d\d\d)(\d\d)(\d\d)$/;
		if ($y) {
			$today    = $reader->getDay(0);
			$tomorrow = timeCalc(scalar localtime(
				timelocal(0, 0, 12, $d, $m - 1, $y - 1900) + 86400
			), '%Y%m%d', 0);
			$yesterday = timeCalc(scalar localtime(
				timelocal(0, 0, 12, $d, $m - 1, $y - 1900) - 86400
			), '%Y%m%d', 0);
			$week_ago  = timeCalc(scalar localtime(
				timelocal(0, 0, 12, $d, $m - 1, $y - 1900) - 86400 * 8 
			), '%Y%m%d', 0);
		}
	} else {
		$today     = $reader->getDay(0);
		$tomorrow  = $reader->getDay(-1);
		$yesterday = $reader->getDay(1);
		$week_ago  = $reader->getDay(8);
	}
	return($today, $tomorrow, $yesterday, $week_ago);
}

#========================================================================

=head2 getData(VALUE [, PARAMETERS, PAGE])

Returns snippets of data associated with a given page.

=over 4

=item Parameters

=over 4

=item VALUE

The name of the data-snippet to process and retrieve.

=item PARAMETERS

Data stored in a hashref which is to be passed to the retrieved snippet.

=item PAGE

The name of the page to which VALUE is associated.

=back

=item Return value

Returns data snippet with all necessary data interpolated.

=item Dependencies

Gets little snippets of data, determined by the value parameter, from
a data template. A data template is a colletion of data snippets
in one template, which are grouped together for efficiency. Each
script can have it's own data template (specified by the PAGE
parameter). If PAGE is unspecified, snippets will be retrieved from
the last page visited by the user as determined by Slash::Apache::User.

=item Notes

This is in Slash.pm instead of Slash::Utility because it depends on Slash::Display,
which also depends on Slash::Utility.  Slash::Utility can call Slash::getData
(note package name), because Slash.pm should always be loaded by scripts first
before loading Slash::Utility, so as long as nothing in Slash::Utility requires
getData for compilation, we should be good (except, note that the environment
Slash::Display depends on needs to be there, so you can't call getData before
createCurrentDB and friends are called ... see note in prepareUser).

=back

=cut

sub getData {
	my($value, $hashref, $page) = @_;
	my $cache = getCurrentCache();
	_dataCacheRefresh($cache);

	$hashref ||= {};
	$hashref->{value} = $value;
	$hashref->{returnme} = {};
	my $opts = { Return => 1, Nocomm => 1 };
	$opts->{Page} = $page || 'NONE' if defined $page;
	my $opts_getname = $opts; $opts_getname->{GetName} = 1;

	my $name = slashDisplayName('data', $hashref, $opts_getname);
	return undef if !$name || !$name->{tempdata} || !defined($name->{tempdata}{tpid});
	my $var  = $cache->{getdata}{ $name->{tempdata}{tpid} } ||= { };

	if (defined $var->{$value}) {
		# restore our original values; this is done if
		# slashDisplay is called, but it is not called here -- pudge
		my $user = getCurrentUser();
		$user->{currentSkin}	= $name->{origSkin};
		$user->{currentPage}	= $name->{origPage};

		return $var->{$value};
	}

	my $str = slashDisplay($name, $hashref, $opts);
	return undef if !defined($str);

	if ($hashref->{returnme}{data_constant}) {
		$cache->{getdata}{_last_refresh} ||= time;
		$var->{$value} = $str;
	}
	return $str;
}

sub _dataCacheRefresh {
	my($cache) = @_;
	if (($cache->{getdata}{_last_refresh} || 0)
		< time - ($cache->{getdata}{_expiration} || 0)) {
		$cache->{getdata} = {};
		$cache->{getdata}{_last_refresh} = time;
		$cache->{getdata}{_expiration} = getCurrentStatic('block_expire');
	}
}

########################################################
# this sucks, but it is here for now
sub _hard_dispComment {
	my($comment, $constants, $user, $form, $comment_shrunk, $can_mod, $reasons, $options) = @_;
	my $gSkin = getCurrentSkin();

	my($comment_to_display, $score_to_display,
		$user_nick_to_display, $zoosphere_display, $user_email_to_display,
		$time_to_display, $comment_link_to_display, $userinfo_to_display)
		= ("") x 7;

	my $discussion2 = $user->{discussion2} && $user->{discussion2} =~ /^(?:slashdot|uofm)$/;

	$comment_to_display = qq'<div id="comment_body_$comment->{cid}">$comment->{comment}</div>';
	my $sighide = $comment_shrunk ? ' hide' : '';
	$comment_to_display .= qq'<div id="comment_sig_$comment->{cid}" class="sig$sighide">$comment->{sig}</div>' if $comment->{sig} && !$user->{nosigs};

	if ($comment_shrunk) {
		my $readtext = 'Read the rest of this comment...';
		my $link;
		if ($discussion2) {
			$link = qq'<a href="$gSkin->{rootdir}/comments.pl?sid=$comment->{sid}&amp;cid=$comment->{cid}" onclick="return readRest($comment->{cid})">$readtext</a>';
		} else {
			$link = linkComment({
				sid	=> $comment->{sid},
				cid	=> $comment->{cid},
				pid	=> $comment->{cid},
				subject	=> $readtext,
				subject_only => 1,
			}, 1);
		}
		$comment_to_display .= qq'<div id="comment_shrunk_$comment->{cid}" class="commentshrunk">$link</div>';
	}

	$time_to_display = timeCalc($comment->{date});
	unless ($user->{noscores}) {
		$score_to_display .= "(Score:";
		$score_to_display .= length($comment->{points}) ? $comment->{points} : "?";
		if ($comment->{reason}) {
			$score_to_display .= ", $reasons->{$comment->{reason}}{name}";
		}
		$score_to_display .= ")";
	}

	if ($comment->{sid} && $comment->{cid}) {
		$comment_link_to_display = qq| (<a href="$gSkin->{rootdir}/comments.pl?sid=$comment->{sid}&amp;cid=$comment->{cid}">#$comment->{cid}</a>)|;
	} else {
		$comment_link_to_display = " ";
	}

	if (isAnon($comment->{uid})) {
		$user_nick_to_display = strip_literal($comment->{nickname});
	} else {
		my $nick_literal = strip_literal($comment->{nickname});
		my $nick_param   = strip_paramattr($comment->{nickname});

		my $homepage = $comment->{homepage} || '';
		$homepage = '' if length($homepage) <= 8;
		my $homepage_maxlen = $constants->{comment_homepage_disp} || 50;
		if (length($homepage) > $homepage_maxlen) {
			my $halflen = $homepage_maxlen/2 - 5;
			$halflen = 10 if $halflen < 10;
			$homepage = substr($homepage, 0, $halflen) . "..." . substr($homepage, -$halflen);
		}
		$homepage = strip_literal($homepage);

		$userinfo_to_display = "";
		my $nofollow = '';
		if (!$comment->{karma_bonus} || $comment->{karma_bonus} eq 'no') {
			$nofollow = ' rel="nofollow"';
		}
		$userinfo_to_display = qq[<a href="$comment->{homepage}"$nofollow>$homepage</a>]
			if $homepage;
		if ($comment->{journal_last_entry_date} =~ /[1-9]/) {
			$userinfo_to_display .= " | " if $userinfo_to_display;
			$userinfo_to_display .= sprintf('Last Journal: <a href="%s/~%s/journal/">%s</a>',
				$constants->{real_rootdir},
				$nick_param,
				timeCalc($comment->{journal_last_entry_date})
			);
		}
		$userinfo_to_display = "<br>($userinfo_to_display)" if $userinfo_to_display;

		$user_nick_to_display = qq{<a href="$constants->{real_rootdir}/~$nick_param">$nick_literal ($comment->{uid})</a>};
		if ($constants->{plugin}{Subscribe} && $constants->{subscribe}
			&& $comment->{subscriber_bonus} eq 'yes') {
			if ($constants->{plugin}{FAQSlashdot}) {
				$user_nick_to_display .= qq{ <a href="/faq/com-mod.shtml#cm2600">*</a>};
			} else {
				$user_nick_to_display .= " *";
			}
		}
		if ($comment->{fakeemail}) {
			my $mail_literal = strip_literal($comment->{fakeemail_vis});
			my $mail_param = strip_paramattr($comment->{fakeemail});
			$user_email_to_display = qq{ &lt;<a href="mailto:$mail_param">$mail_literal</a>&gt;};
		}
	}

	$zoosphere_display = " ";
	unless ($user->{is_anon} || isAnon($comment->{uid}) || $comment->{uid} == $user->{uid}) {
		my $person = $comment->{uid};
		if (!$user->{people}{FRIEND()}{$person} && !$user->{people}{FOE()}{$person} && !$user->{people}{FAN()}{$person} && !$user->{people}{FREAK()}{$person} && !$user->{people}{FOF()}{$person} && !$user->{people}{EOF()}{$person}) {
				$zoosphere_display .= qq|<a href="$gSkin->{rootdir}/zoo.pl?op=check&amp;type=friend&amp;uid=$person"><img src="$constants->{imagedir}/neutral.gif" alt="Alter Relationship" title="Alter Relationship"></a>|;
		} else {
			if ($user->{people}{FRIEND()}{$person}) {
				my $title = $user->{people}{people_bonus_friend} ? "Friend ($user->{people}{people_bonus_friend})" : "Friend";
				$zoosphere_display .= qq|<a href="$gSkin->{rootdir}/zoo.pl?op=check&amp;uid=$person"><img src="$constants->{imagedir}/friend.gif" alt="$title" title="$title"></a>|;
			}
			if ($user->{people}{FOE()}{$person}) {
				my $title = $user->{people}{people_bonus_foe} ? "Foe ($user->{people}{people_bonus_foe})" : "Foe";
				$zoosphere_display .= qq|<a href="$gSkin->{rootdir}/zoo.pl?op=check&amp;uid=$person"><img src="$constants->{imagedir}/foe.gif" alt="$title" title="$title"></a>|;
			}
			if ($user->{people}{FAN()}{$person}) {
				my $title = $user->{people}{people_bonus_fan} ? "Fan ($user->{people}{people_bonus_fan})" : "Fan";
				$zoosphere_display .= qq|<a href="$gSkin->{rootdir}/zoo.pl?op=check&amp;uid=$person"><img src="$constants->{imagedir}/fan.gif" alt="$title" title="$title"></a>|;
			}
			if ($user->{people}{FREAK()}{$person}) {
				my $title = $user->{people}{people_bonus_freak} ? "Freak ($user->{people}{people_bonus_freak})" : "Freak";
				$zoosphere_display .= qq|<a href="$gSkin->{rootdir}/zoo.pl?op=check&amp;uid=$person"><img src="$constants->{imagedir}/freak.gif" alt="$title" title="$title"></a>|;
			}
			if ($user->{people}{FOF()}{$person}) {
				my $title = $user->{people}{people_bonus_fof} ? "Friend of a Friend ($user->{people}{people_bonus_fof})" : "Friend of a Friend";
				$zoosphere_display .= qq|<a href="$gSkin->{rootdir}/zoo.pl?op=check&amp;uid=$person"><img src="$constants->{imagedir}/fof.gif" alt="$title" title="$title"></a>|;
			}
			if ($user->{people}{EOF()}{$person}) {
				my $title = $user->{people}{people_bonus_eof} ? "Foe of a Friend ($user->{people}{people_bonus_eof})" : "Foe of a Friend";
				$zoosphere_display .= qq|<a href="$gSkin->{rootdir}/zoo.pl?op=check&amp;uid=$person"><img src="$constants->{imagedir}/eof.gif" alt="$title" title="$title"></a>|;
			}
		}
	}

	my $class = $options->{class}; 
	my $classattr = $discussion2 ? qq[ class="$class"] : '';

	my $head = $discussion2 ? <<EOT1 : <<EOT2;
			<h4><a id="comment_link_$comment->{cid}" name="comment_link_$comment->{cid}" href="$gSkin->{rootdir}/comments.pl?sid=$comment->{sid}&amp;cid=$comment->{cid}" onclick="return setFocusComment($comment->{cid})">$comment->{subject}</a></h4>
EOT1
			<h4><a name="$comment->{cid}">$comment->{subject}</a></h4>
EOT2

	my $return = <<EOT;
<li id="tree_$comment->{cid}" class="comment">
<div id="comment_status_$comment->{cid}" class="commentstatus"></div>
<div id="comment_$comment->{cid}"$classattr>
	<div class="commentTop">
		<div class="title">
$head
		 	<span class="score">$score_to_display</span>
		</div>
		<div class="details">
			by $user_nick_to_display$zoosphere_display
			<span class="otherdetails">
				$user_email_to_display
				on $time_to_display$comment_link_to_display
				<small>$userinfo_to_display $comment->{ipid_display}</small>
			</span>
		</div>
	</div>
	<div class="commentBody">	
		$comment_to_display
	</div>

	<div class="commentSub">
EOT

	# Do not display comment navigation and reply links if we are in
	# archive mode or if we are in metamod. Nicknames are always equal to
	# '-' in metamod. This logic is extremely old and could probably be
	# better formulated.
	if ($user->{mode} ne 'archive'
		&& $user->{mode} ne 'metamod'
		&& $comment->{nickname} ne "-") { # this last test probably useless
		my @link = ( );

		push @link, linkComment({
			sid	=> $comment->{sid},
			pid	=> $comment->{cid},
			op	=> 'Reply',
			subject	=> 'Reply to This',
			subject_only => 1,
			# onclick	=> ($discussion2 ? "return replyTo($comment->{cid})" : '')
		}) unless $user->{state}{discussion_archived};

		push @link, linkComment({
			sid	=> $comment->{sid},
			cid	=> $comment->{original_pid},
			pid	=> $comment->{original_pid},
			subject	=> 'Parent',
			subject_only => 1,
			onclick	=> ($discussion2 ? "return selectParent($comment->{original_pid})" : '')
		}, 1) if $comment->{original_pid};# && !($discussion2 &&
#			(!$form->{cid} || $form->{cid} != $comment->{cid})
#		);

		push @link, "<div class=\"modsel\">".createSelect("reason_$comment->{cid}",
			$reasons, '', 1, 1)."</div>" if $can_mod
				&& ( !$user->{state}{discussion_archived}
					|| $constants->{comments_moddable_archived} );

		push @link, qq|<input type="checkbox" name="del_$comment->{cid}">|
			if $user->{is_admin};

		my $link = join(" | ", @link);

		if (@link) {
			$return .= <<EOT;
					[ $link ]
EOT
		}

	}

	$return .= "</div></div>\n\n";

	if ($discussion2) {
		$return .= <<EOT;
<div id="replyto_$comment->{cid}"></div>

<ul id="group_$comment->{cid}">
	<li id="hiddens_$comment->{cid}" class="hide"></li>
</ul>

EOT
	}

	return $return;
}

sub tempUofmLinkGenerate {
	require URI::Escape;

	my $constants = getCurrentStatic();
	my $user = getCurrentUser();

	my $cipher = tempUofmCipherObj() or return;

	my $encrypted = $cipher->encrypt($user->{uid} . '|' . $user->{nickname});
	return sprintf($constants->{uofm_address}, URI::Escape::uri_escape($encrypted));
}

sub tempUofmCipherObj {
	my $constants = getCurrentStatic();
	return unless $constants->{uofm_key} && $constants->{uofm_iv};

	require Crypt::CBC;

	my $cipher = Crypt::CBC->new({
		key		=> $constants->{uofm_key},
		iv		=> $constants->{uofm_iv},
		cipher		=> 'Blowfish',
		regenerate_key	=> 0,
		padding		=> 'null',
		prepend_iv	=> 0
	});

	return $cipher;
}

1;

__END__

=head1 BENDER'S TOP TEN MOST FREQUENTLY UTTERED WORDS

=over 4

=item 1.

ass

=item 2.

daffodil

=item 3.

shiny

=item 4.

my

=item 5.

bite

=item 6.

pimpmobile

=item 7.

up

=item 8.

yours

=item 9.

chumpette

=item 10.

chump

=back
