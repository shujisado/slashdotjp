# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.

package Slash::Rating;

use strict;
use Slash;
use Slash::Constants;

use base 'Slash::Plugin';

our $VERSION = $Slash::Constants::VERSION;

sub create_comment_vote {
	my ($data) = @_;
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	
	my $slashdb = getCurrentDB();
	my $ratings_reader = getObject('Slash::Rating', { db_type => 'reader' });
	my $can_create_vote = 0;
	my $comment = $data->{comment};

	my $discussion = $slashdb->getDiscussion($comment->{sid});
	my $disc_skin = $slashdb->getSkin($discussion->{primaryskid});

	my %unlimited_votes = map {$_, 1} split(/\|/, $constants->{rating_unlimited_vote_uids});
	
	my $extras;
	$extras =  $slashdb->getNexusExtrasForChosen({$disc_skin->{nexus} => 1}, {content_type => "comment"}) if $disc_skin && $disc_skin->{nexus};

	return 0 unless $extras;
	
	foreach my $extra(@$extras) {
		$can_create_vote=1 if $extra->[1] eq "comment_vote";	
	}

	return 0 unless $can_create_vote;
	
	my $active = "yes";
	my $val = 0;
	if ($form->{comment_vote} =~/^\d+$/) {
		$val = $form->{comment_vote};
	} else {
		$active = "no";
	}
	
	my $count = $ratings_reader->getDiscussionVoteCountForUser($comment->{uid}, $comment->{sid});
	$active = "no" if $count && !$unlimited_votes{$user->{uid}};
	
	my $comment_vote = {
		val  => $val,
		cid => $comment->{cid},
		active => $active
	};
	
	my $success = $slashdb->sqlInsert("comment_vote", $comment_vote);

}

sub getUniqueDiscussionsBetweenCids {
	my($self, $start_cid, $end_cid) = @_;
	my $discussions = $self->sqlSelectColArrayref(
		"DISTINCT comments.sid",
		"comments, comment_vote",
		"comments.cid=comment_vote.cid
		 AND comments.cid BETWEEN $start_cid AND $end_cid");
	return $discussions;
}

sub getDiscussionVoteCountForUser {
	my ($self, $uid, $sid) = @_;
	my $uid_q = $self->sqlQuote($uid);
	my $sid_q = $self->sqlQuote($sid);
	return $self->sqlCount("comments,comment_vote", "comments.cid=comment_vote.cid AND active='yes' AND uid=$uid_q AND sid=$sid_q");
}

sub updateDiscussionRatingStats {
	my($self, $discussions) = @_;
	return 0 unless $discussions && @$discussions;
	my $sid_clause = "sid IN (" . join(",", @$discussions) . ")";
	my $hr = $self->sqlSelectAllHashref(
		[qw( sid active )],
		"sid, active, COUNT(*) AS c, AVG(val) AS avgval",
		"comments, comment_vote",
		"comments.cid=comment_vote.cid
		 AND $sid_clause",
		"GROUP BY sid, active");
	
	my $rows = 0;
	for my $sid (keys %$hr) {
		my $sid_hr = $hr->{$sid};
		my $replace_hr = { discussion => $sid };
		$replace_hr->{active_votes} =  $sid_hr->{yes}{c} || 0;
		$replace_hr->{total_votes}  = ($sid_hr->{yes}{c} || 0) + ($sid_hr->{no}{c} || 0);
		$replace_hr->{avg_rating}   = $sid_hr->{yes}{avgval} || undef;
		$rows += $self->sqlReplace("discussion_rating", $replace_hr);
	}
	return $rows;
}

sub getCommentVoteForCid {
	my ($self, $cid) = @_;
	my $cid_q = $self->sqlQuote($cid);
	return $self->sqlSelectHashref("*", "comment_vote", "cid=$cid_q");
}

sub getDiscussionRating {
	my ($self, $sid) = @_;
	my $sid_q = $self->sqlQuote($sid);
	return $self->sqlSelectHashref("*", "discussion_rating", "discussion=$sid_q");
	
}

sub DESTROY {
	my($self) = @_;
	$self->{_dbh}->disconnect if !$ENV{GATEWAY_INTERFACE} && $self->{_dbh};
}

1;

__END__

# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

Slash::Rating - Rating system

=head1 SYNOPSIS

	use Slash::Rating;

=head1 DESCRIPTION

This allows user reviews/ratings to accompany a discussion.  Users vote/rate the discussion when
they create a comment.  The averages are then totalled by a task for display as you choose.

Blah blah blah.

=head1 AUTHOR

Tim Vroom

=head1 SEE ALSO

perl(1).

=cut
