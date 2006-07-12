# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::Hof;

use strict;
use Slash::Utility;
use Slash::DB::Utility;
use vars qw($VERSION);
use base 'Slash::DB::Utility';

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

# FRY: And where would a giant nerd be? THE LIBRARY!

#################################################################
sub new {
	my($class, $user) = @_;
	my $self = {};

	my $plugin = getCurrentStatic('plugin');
	return unless $plugin->{'Hof'};

	bless($self, $class);
	$self->{virtual_user} = $user;
	$self->sqlConnect();

	return $self;
}

########################################################
sub countStories {
	my($self) = @_;
	my $dnc = getCurrentStatic("hof_do_not_count") || "";
	my $dnc_clause = "";
	my @dnc_sid   = map { $self->sqlQuote($_) } grep { /^[\d\/]+$/ } split / /, $dnc;
	my @dnc_stoid = map { $self->sqlQuote($_) } grep { /^\d+$/   }   split / /, $dnc;
	if (@dnc_sid) {
		$dnc_clause .= " AND stories.sid NOT IN ("   . join (",", @dnc_sid)   . ") ";
	}
	if (@dnc_stoid) {
		$dnc_clause .= " AND stories.stoid NOT IN (" . join (",", @dnc_stoid) . ") ";
	}
	my $stories = $self->sqlSelectAll(
		'stories.sid, story_text.title,
		 stories.primaryskid, stories.commentcount,
		 nickname',
		'stories, story_text, users, discussions',
		"stories.uid=users.uid
		 AND stories.discussion=discussions.id
		 AND stories.stoid=story_text.stoid
		 $dnc_clause",
		'ORDER BY commentcount DESC LIMIT 10'
	);

	# XXXSKIN - not sure if this is the best way to do this, but
	# i figure it is fine ... please change or advise if should be changed ...
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	for (@$stories) {
		$_->[2] = $reader->getSkin($_->[2])->{name};
	}

	return $stories;
}

########################################################
sub countPollquestions {
	my($self) = @_;
	my $pollquestions = $self->sqlSelectAll("voters,question,qid", "pollquestions",
		"1=1", "ORDER by voters DESC LIMIT 10"
	);
	return $pollquestions;
}

########################################################
# Not used currently
sub countUsersIndexSlashboxesByBid {
	my($self, $bid) = @_;
	my $bid_q = $self->sqlQuote("\%$bid\%");
	return $self->sqlCount("users_index", "slashboxes LIKE $bid_q");
}

########################################################
sub countStorySubmitters {
	my($self) = @_;

	# Sometimes getCurrentAnonymousCoward() is missing data when it is
	# called, so we drop in an appropriate default.
	my $ac_uid = getCurrentAnonymousCoward('uid') ||
		     getCurrentStatic('anonymous_coward_uid');
	my $uid = $self->sqlSelectColArrayref('uid', 'authors_cache');
	my $in_list = join(',', @{$uid}, $ac_uid);

	my $submitters = $self->sqlSelectAll(
		'COUNT(*) AS c, users.nickname',
		'stories, users', 
		"users.uid=stories.submitter AND submitter NOT IN ($in_list)",
		'GROUP BY users.uid ORDER BY c DESC LIMIT 10'
	);

	return $submitters;
}


########################################################
# Just used for Hof
sub countStoriesAuthors {
	my($self) = @_;
	my $authors = $self->sqlSelectAll('storycount, nickname, homepage',
		'authors_cache', '',
		'GROUP BY uid ORDER BY storycount DESC LIMIT 10'
	);
	return $authors;
}

########################################################
sub countStoriesTopHits {
	my($self) = @_;
	my $stories = $self->sqlSelectAll(
		'stories.sid, title, primaryskid, hits, users.nickname',
		"story_text, users,
		 stories LEFT JOIN story_param
			ON stories.stoid=story_param.stoid AND story_param.name='neverdisplay'",
		'stories.stoid=story_text.stoid
		 AND story_param.name IS NULL
		 AND primaryskid > 0
		 AND stories.uid=users.uid',
		'ORDER BY hits DESC LIMIT 10'
	);

	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	for my $story (@$stories) {
		my $primaryskid = $story->[2];
		my $skin = $reader->getSkin($primaryskid);
		next unless $skin;
		$story->[2] = $skin->{name};
	}

	return $stories;
}

##################################################################
# counts the number of stories
sub countStory {
	my($self, $tid) = @_;
	my($value) = $self->sqlSelect("COUNT(*)",
		'stories',
		"tid=" . $self->sqlQuote($tid));

	return $value;
}

########################################################
# This is going to blow chunks -Brian
# To be precise it locks the DB every two hours when hof.pl is run
# by slashd.  I've commented out the 3-way join and STARTED coding
# up a replacement (it should select the comments first, then pull
# from story_heap and users without doing a join).  I don't have
# time to finish this right now so I've also commented out the code
# that calls this method, see themes/slashcode/htdocs/hof.pl.
# - Jamie 2001/07/12
sub getCommentsTop {
	my($self, $sid) = @_;
	my $user = getCurrentUser();

	my $where = 'stories.discussion=comments.sid AND stories.uid=users.uid';
	$where .= ' AND stories.sid=' . $self->sqlQuote($sid) if $sid;
	my $stories = $self->sqlSelectAll(
		'primaryskid, stories.sid, users.nickname, title,
		pid, subject, date, time, comments.uid, cid, points',
		'stories, comments, users',
		$where,
		' ORDER BY points DESC, date DESC LIMIT 10 '
	);

	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	# XXXSKIN - not sure if this is the best way to do this, but
	# i figure it is fine ... please change or advise if should be changed ...
	for (@$stories) {
		$_->[0] = $reader->getSkin($_->[0])->{name};
	}

	# First select the top scoring comments (which on Slashdot or
	# any big site will just be the latest score:5 comments).
	my $columns = "sid, pid, cid, uid, points, date, subject";
	my $tables = 'comments';
	$where = "1=1";
	my $other = "ORDER BY points DESC, date DESC LIMIT 10";
	my $top_comments = $self->sqlSelectAll($columns,$tables,$where,$other);
	formatDate($top_comments, 5);

	# Then we want to match the sids against story_heap.discussion
	# and then the uids against users.nickname.  But I have not
	# written that code yet because there are bigger bugs to kill.
	# Meanwhile...
	return $top_comments;

#	my $where = "comments.points >= 2 AND stories.discussion=comments.sid AND comments.uid=users.uid";
#	$where .= " AND stories.sid=" . $self->sqlQuote($sid) if $sid;
#	my $stories = $self->sqlSelectAll(
#		"section, stories.sid, users.nickname, title, pid,
#		subject, date, time, comments.uid, cid, points",
#		"stories, comments, users",
#		$where,
#		" ORDER BY points DESC, date DESC LIMIT 10"
#	);
#
#	formatDate($stories, 6);
#	formatDate($stories, 7);
#	return $stories;
}

#################################################################
sub DESTROY {
	my($self) = @_;
	$self->{_dbh}->disconnect if $self->{_dbh} && !$ENV{GATEWAY_INTERFACE};
}

1;

=head1 NAME

Slash::Hof - Slash Hof module

=head1 SYNOPSIS

	use Slash::Hof;

=head1 DESCRIPTION

This contains all of the routines currently used by Hof to generate it's stats. 

=head1 SEE ALSO

Slash(3).

=cut
