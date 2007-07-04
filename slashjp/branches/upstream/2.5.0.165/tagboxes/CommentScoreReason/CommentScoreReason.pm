#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id: CommentScoreReason.pm,v 1.3 2007/02/22 22:45:21 jamiemccarthy Exp $

# Requires TagModeration plugin (not (just) Moderation)

package Slash::Tagbox::CommentScoreReason;

=head1 NAME

Slash::Tagbox::CommentScoreReason - track comment score and reason

=head1 SYNOPSIS

	my $tagbox_tcu = getObject("Slash::Tagbox::CommentScoreReason");
	my $feederlog_ar = $tagbox_tcu->feed_newtags($users_ar);
	$tagbox_tcu->run($affected_globjid);

=cut

use strict;

use Slash;
use Slash::DB;
use Slash::Utility::Environment;
use Slash::Tagbox;

use Data::Dumper;

use vars qw( $VERSION );
$VERSION = ' $Revision: 1.3 $ ' =~ /\$Revision:\s+([^\s]+)/;

use base 'Slash::DB::Utility';	# first for object init stuff, but really
				# needs to be second!  figure it out. -- pudge
use base 'Slash::DB::MySQL';

sub new {
	my($class, $user) = @_;

	my $plugin = getCurrentStatic('plugin');
	return undef if !$plugin->{Tags} || !$plugin->{TagModeration};
	my($tagbox_name) = $class =~ /(\w+)$/;
	my $tagbox = getCurrentStatic('tagbox');
	return undef if !$tagbox->{$tagbox_name};

	# Note that getTagboxes() would call back to this new() function
	# if the tagbox objects have not yet been created -- but the
	# no_objects option prevents that.  See getTagboxes() for details.
	my %self_hash = %{ getObject('Slash::Tagbox')->getTagboxes($tagbox_name, undef, { no_objects => 1 }) };
	my $self = \%self_hash;
	return undef if !$self || !keys %$self;

	bless($self, $class);
	$self->{virtual_user} = $user;
	$self->sqlConnect();

	return $self;
}

sub feed_newtags {
	my($self, $tags_ar) = @_;
	my $constants = getCurrentStatic();
	if (scalar(@$tags_ar) < 9) {
		main::tagboxLog("CommentScoreReason->feed_newtags called for tags '" . join(' ', map { $_->{tagid} } @$tags_ar) . "'");
	} else {
		main::tagboxLog("CommentScoreReason->feed_newtags called for " . scalar(@$tags_ar) . " tags " . $tags_ar->[0]{tagid} . " ... " . $tags_ar->[-1]{tagid});
	}
	my $tagsdb = getObject('Slash::Tags');

	# Only tags on comments matter to this tagbox.
	my $comments_gtid = $self->getGlobjTypes()->{comments};
	my %all_globjids = ( map { ($_->{globjid}, 1) } @$tags_ar );
	my $all_globjids_str = join(",", sort { $a <=> $b } keys %all_globjids);
	return [ ] if !$comments_gtid || !$all_globjids_str;
	my $globjids_wanted_ar = $self->sqlSelectColArrayref(
		'globjid',
		'globjs',
		"globjid IN ($all_globjids_str) AND gtid=$comments_gtid");
	my %globjid_wanted = ( map { ($_, 1) } @$globjids_wanted_ar );

	my $ret_ar = [ ];
	for my $tag_hr (@$tags_ar) {
		next unless $globjid_wanted{ $tag_hr->{globjid} };
		my $ret_hr = {
			affected_id =>	$tag_hr->{globjid},
			importance =>	1,
		};
		# We identify this little chunk of importance by either
		# tagid or tdid depending on whether the source data had
		# the tdid field (which tells us whether feed_newtags was
		# "really" called via feed_deactivatedtags).
		if ($tag_hr->{tdid})	{ $ret_hr->{tdid}  = $tag_hr->{tdid}  }
		else			{ $ret_hr->{tagid} = $tag_hr->{tagid} }
		push @$ret_ar, $ret_hr;
	}
	return [ ] if !@$ret_ar;

	main::tagboxLog("CommentScoreReason->feed_newtags returning " . scalar(@$ret_ar));
	return $ret_ar;
}

sub feed_deactivatedtags {
	my($self, $tags_ar) = @_;
	main::tagboxLog("CommentScoreReason->feed_deactivatedtags called: tags_ar='" . join(' ', map { $_->{tagid} } @$tags_ar) .  "'");
	my $ret_ar = $self->feed_newtags($tags_ar);
	main::tagboxLog("CommentScoreReason->feed_deactivatedtags returning " . scalar(@$ret_ar));
	return $ret_ar;
}

sub feed_userchanges {
	my($self, $users_ar) = @_;

	# Do not currently care about any user changes, since this tagbox
	# just replicates what comment moderation does and moderation does
	# not care about user tag clout.

	return [ ];
}

sub run {
	my($self, $affected_id) = @_;
	my $constants = getCurrentStatic();
	my $moddb = getObject('Slash::TagModeration');
	my $tagsdb = getObject('Slash::Tags');
	my $tagboxdb = getObject('Slash::Tagbox');

	my $reasons = $moddb->getReasons();
	my @reason_ids = (
		grep { $reasons->{$_}{val} != 0 }
		keys %$reasons
	);
	my %tagnameid_reasons = ( );
	for my $id (@reason_ids) {
		my $name = lc $reasons->{$id}{name};
		my $tagnameid = $tagsdb->getTagnameidCreate($name);
		$tagnameid_reasons{$tagnameid} = $reasons->{$id};
	}

	my $mod_score_sum = 0;
	my($gtid, $cid) = $self->getGlobjTarget($affected_id);
	my $tags_ar = $tagboxdb->getTagboxTags($self->{tbid}, $affected_id, 0);
	return unless $tags_ar && @$tags_ar;
	my($keep_karma_bonus, $karma_bonus_downmods_left) = (1, $constants->{mod_karma_bonus_max_downmods});
	my $current_reason_mode = 0;
	my $allreasons_hr = {( %{$reasons} )};
	for my $id (keys %$allreasons_hr) {
		$allreasons_hr->{$id} = { reason => $id, c => 0 };
	}
	for my $tag (@$tags_ar) {
		next if $tag->{inactivated};
		my $reason = $tagnameid_reasons{$tag->{tagnameid}};
		next unless $reason;
		if ($reason->{val} < 0) {
			$keep_karma_bonus = 0 if --$karma_bonus_downmods_left < 0;
		}
		$mod_score_sum += $reason->{val};
		$allreasons_hr->{$reason->{id}}{c}++;
		$current_reason_mode = $moddb->getCommentMostCommonReason($cid,
			$allreasons_hr, $reason->{id}, $current_reason_mode);
	}

	my($points_orig, $karma_bonus) = $self->sqlSelect(
		'pointsorig, karma_bonus', 'comments', "cid='$cid'");

	my $new_score = $points_orig + $mod_score_sum;
	my $new_karma_bonus = ($karma_bonus eq 'yes' && $keep_karma_bonus) ? 1 : 0;

#main::tagboxLog("CommentScoreReason->run setting cid $cid to score: $new_score, $reasons->{$current_reason_mode}{name} kb '$karma_bonus'->'$new_karma_bonus'");

	$self->sqlUpdate('comments', {
			f1 =>	$new_score,
			f2 =>	$current_reason_mode,
		}, "cid='$cid'");
}

1;

