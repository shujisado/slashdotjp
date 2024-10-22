#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id: $

package Slash::Tagbox::Despam;

=head1 NAME

Slash::Tagbox::Despam - Reduce (firehose) spam

=head1 SYNOPSIS

	my $tagbox_tcu = getObject("Slash::Tagbox::Despam");
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
$VERSION = ' $Revision: $ ' =~ /\$Revision:\s+([^\s]+)/;

use base 'Slash::DB::Utility';	# first for object init stuff, but really
				# needs to be second!  figure it out. -- pudge
use base 'Slash::DB::MySQL';

sub new {
	my($class, $user) = @_;

	return undef if !$class->isInstalled();

	# Note that getTagboxes() would call back to this new() function
	# if the tagbox objects have not yet been created -- but the
	# no_objects option prevents that.  See getTagboxes() for details.
	my($tagbox_name) = $class =~ /(\w+)$/;
	my %self_hash = %{ getObject('Slash::Tagbox')->getTagboxes($tagbox_name, undef, { no_objects => 1 }) };
	my $self = \%self_hash;
	return undef if !$self || !keys %$self;

	bless($self, $class);
	$self->{virtual_user} = $user;
	$self->sqlConnect();

	my $constants = getCurrentStatic();
	my $tagsdb = getObject('Slash::Tags');
	$self->{spamid}          = $tagsdb->getTagnameidCreate('binspam');
	$self->{upvoteid}        = $tagsdb->getTagnameidCreate($constants->{tags_upvote_tagname} || 'nod');
	return undef unless $self->{spamid};

	return $self;
}

sub isInstalled {
	my($class) = @_;
	my $constants = getCurrentStatic();
	my($tagbox_name) = $class =~ /(\w+)$/;
	return $constants->{plugin}{Tags} && $constants->{tagbox}{$tagbox_name} || 0;
}

sub feed_newtags {
	my($self, $tags_ar) = @_;
	my $constants = getCurrentStatic();
	if (scalar(@$tags_ar) < 9) {
		main::tagboxLog("Despam->feed_newtags called for tags '" . join(' ', map { $_->{tagid} } @$tags_ar) . "'");
	} else {
		main::tagboxLog("Despam->feed_newtags called for " . scalar(@$tags_ar) . " tags " . $tags_ar->[0]{tagid} . " ... " . $tags_ar->[-1]{tagid});
	}

	my $slashdb = getCurrentDB();
	my $admins = $slashdb->getAdmins();

	my $ret_ar = [ ];
	for my $tag_hr (@$tags_ar) {
		# All admin binspam tags are equally important.
		# All other tags are equally unimportant :)
		next unless $tag_hr->{tagnameid} == $self->{spamid} && $admins->{ $tag_hr->{uid} };
		my $ret_hr = {
			tagid =>	$tag_hr->{tagid},
			affected_id =>	$tag_hr->{globjid},
			importance =>	1,
		};
		push @$ret_ar, $ret_hr;
	}
	return [ ] if !@$ret_ar;

	# Tags applied to globjs that have a firehose entry associated
	# are important.  Other tags are not.
	my %globjs = ( map { $_->{affected_id}, 1 } @$ret_ar );
	my $globjs_str = join(', ', sort keys %globjs);
	my $fh_globjs_ar = $self->sqlSelectColArrayref(
		'globjid',
		'firehose',
		"globjid IN ($globjs_str)");
	return [ ] if !@$fh_globjs_ar; # if no affected globjs have firehose entries, short-circuit out
	my %fh_globjs = ( map { $_, 1 } @$fh_globjs_ar );
	$ret_ar = [ grep { $fh_globjs{ $_->{affected_id} } } @$ret_ar ];

	main::tagboxLog("Despam->feed_newtags returning " . scalar(@$ret_ar) . ": '@$ret_ar'");
	return $ret_ar;
}

sub feed_deactivatedtags {
	my($self, $tags_ar) = @_;
	# XXX This need not do anything, I don't think -- not even call
	# feed_newtags.
	# The way Despam is set up, 2 admin binspam tags will mark a globjid,
	# and even if 1 of them is deactivated a moment later, we have no way
	# to undo the process.
	main::tagboxLog("Despam->feed_deactivatedtags called: tags_ar='" . join(' ', map { $_->{tagid} } @$tags_ar) .  "', returning nothing");
	return [ ];
}

sub feed_userchanges {
	my($self, $users_ar) = @_;
	main::tagboxLog("Despam->feed_userchanges called (oddly): users_ar='" . join(' ', map { $_->{tuid} } @$users_ar) .  "', returning nothing");
	return [ ];
}

sub run {
	my($self, $affected_id, $options) = @_;
	my $constants = getCurrentStatic();
	my $tagsdb = getObject('Slash::Tags');
	my $tagboxdb = getObject('Slash::Tagbox');
	my $firehose_db = getObject('Slash::FireHose');
	my $slashdb = getCurrentDB();

	my $admins = $tagsdb->getAdmins();
	my $admin_in_str = join(',',
		sort { $a <=> $b }
		grep { $admins->{$_}{seclev} >= 100 }
		keys %$admins);
	return unless $admin_in_str;

	my $affected_id_q = $self->sqlQuote($affected_id);
	my $fhid = $self->sqlSelect('id', 'firehose', "globjid = $affected_id_q");
	warn "Slash::Tagbox::Despam->run bad data, fhid='$fhid' db='$firehose_db'" if !$fhid || !$firehose_db;
	my $fhitem = $firehose_db->getFireHose($fhid);
	my $submitter_uid = $fhitem->{uid};
	my $submitter_srcid = $fhitem->{srcid_32};

	my $binspam_count = $slashdb->sqlCount(
		'tags, firehose',
		"tags.uid IN ($admin_in_str)
		 AND tags.inactivated IS NULL
		 AND tags.tagnameid = $self->{spamid}
		 AND tags.globjid = firehose.globjid
		 AND firehose.uid = $submitter_uid");
	my $binspam_tagids = $slashdb->sqlSelectColArrayref(
		'tagid',
		'tags, firehose',
		"tags.uid IN ($admin_in_str)
		 AND tags.inactivated IS NULL
		 AND tags.tagnameid = $self->{spamid}
		 AND tags.globjid = firehose.globjid
		 AND firehose.uid = $submitter_uid");
	main::tagboxLog(sprintf("%s->run marking fhid %d (%d) as is_spam (for count %d on uid %d: '%s')",
		ref($self), $fhid, $affected_id, $binspam_count, $submitter_uid, join(' ', @$binspam_tagids)));
	$firehose_db->setFireHose($fhid, { is_spam => 'yes' });

	if (isAnon($submitter_uid)) {
		# Non-logged-in user, check by IP (srcid_32)
		if ($submitter_srcid &&
			$binspam_count > $constants->{tagbox_despam_binspamsallowed_ip}
		) {
			main::tagboxLog(sprintf("%s->run marking srcid %s for %d admin binspam tags, based on %d (%d)",
			ref($self), $submitter_srcid, $binspam_count, $fhid, $affected_id));
			$self->despam_srcid($submitter_srcid, $binspam_count);
		}
	} else {
		# Logged-in user, check by uid
		if ($binspam_count > $constants->{tagbox_despam_binspamsallowed}) {
			main::tagboxLog(sprintf("%s->run marking uid %d for %d admin binspam tags, based on %d (%d)",
				ref($self), $submitter_uid, $binspam_count, $fhid, $affected_id));
			$self->despam_uid($submitter_uid, $binspam_count);
		}
	}
}

sub despam_srcid {
	my($self, $srcid, $count) = @_;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();

	my $al2_hr = $slashdb->getAL2($srcid);
	if ($count > $constants->{tagbox_despam_binspamsallowed_ip}) {
		main::tagboxLog("marking $srcid as spammer for $count");
		if (!$al2_hr->{spammer}) {
			$slashdb->setAL2($srcid, { spammer => 1, comment => "Despam $count" });
		}
	}
}

sub despam_uid {
	my($self, $uid, $count) = @_;
	my $constants = getCurrentStatic();
	my $slashdb = getCurrentDB();
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $tagboxdb = getObject('Slash::Tagbox');

	# First, set the user's 'spammer' AL2.
	my $adminuid = $constants->{tagbox_despam_al2adminuid};
	my $al2_hr = $slashdb->getAL2($uid);
	if (!$al2_hr->{spammer}) {
		$slashdb->setAL2($uid, { spammer => 1, comment => "Despam $count" },
			{ adminuid => $adminuid });
	}

	# Next, set the user's clout manually to 0.
	$slashdb->setUser($uid, { tag_clout => 0 });

        # Next, mark as spam everything the user's submitted.
	$slashdb->sqlUpdate('firehose', { is_spam => 'yes' },
		"accepted != 'no' AND uid=$uid");

	# Next, if $count is high enough, set the 'spammer' AL2 for all
	# the IPID's the user has submitted from.
	if ($count > $constants->{tagbox_despam_binspamsallowed_ip}) {
		my $days = defined($constants->{tagbox_despam_ipdayslookback})
			? $constants->{tagbox_despam_ipdayslookback} : 60;
		my %srcid_used = ( );
		if ($days) {
			my $sub_ipid_ar = $reader->sqlSelectColArrayref(
				'DISTINCT ipid',
				'submissions',
				"uid=$uid AND time >= DATE_SUB(NOW(), INTERVAL $days DAY) AND ipid != ''");
			my $journal_srcid_ar = $reader->sqlSelectColArrayref(
				'DISTINCT ' . get_srcid_sql_out('srcid_32'),
				'journals',
				"uid=$uid AND date >= DATE_SUB(NOW(), INTERVAL $days DAY) AND srcid_32 != 0");
			my $book_srcid_ar = $reader->sqlSelectColArrayref(
				'DISTINCT ' . get_srcid_sql_out('srcid_32'),
				'bookmarks',
				"uid=$uid AND createdtime >= DATE_SUB(NOW(), INTERVAL $days DAY) AND srcid_32 != 0");
			for my $ipid (@$sub_ipid_ar) {
				my $srcid = convert_srcid(ipid => $ipid);
				$srcid_used{$srcid} = 1;
			}
			for my $srcid (@$journal_srcid_ar) {
				$srcid_used{$srcid} = 1;
			}
			for my $srcid (@$book_srcid_ar) {
				$srcid_used{$srcid} = 1;
			}
			my @srcids = sort grep { $_ } keys %srcid_used;
			for my $srcid (@srcids) {
				$al2_hr = $slashdb->getAL2($srcid);
				if (!$al2_hr->{spammer}) {
					$slashdb->setAL2($srcid, { spammer => 1, comment => "Despam $count for $uid" });
				}
			}
		}
	}

	# Next, declout everyone who's upvoted any of the user's
	# recent submissions (except bookmarks, because those are
	# generic enough).
	my $daysback = $constants->{tagbox_despam_decloutdaysback} || 7;
	my $upvoter_ar = $slashdb->sqlSelectColArrayref(
		'DISTINCT tags.uid',
		'tags, firehose',
		"tags.globjid = firehose.globjid
		 AND firehose.uid = $uid
		 AND type IN ('submission', 'journal')
		 AND createtime >= DATE_SUB(NOW(), INTERVAL $daysback DAY)
		 AND tagnameid = $self->{upvoteid}
		 AND inactivated IS NULL");
	my $max_clout = defined($constants->{tagbox_despam_upvotermaxclout})
		? $constants->{tagbox_despam_upvotermaxclout} : '0.85';
	for my $upvoter (@$upvoter_ar) {
		main::tagboxLog("setting user $upvoter clout to max $max_clout for upvoting user $uid");
		$slashdb->setUser($upvoter, {
			-tag_clout => "MAX(tag_clout, $max_clout)"
		});
	}

	# Next, insert tagboxlog_feeder entries to tell the relevant
	# tagboxes to recalculate those scores.
	my $tagboxes = $tagboxdb->getTagboxes();
	my @tagboxids = map { $_->{tbid} } grep { $_->{name} =~ /^(FHEditorPop|FireHoseScores)$/ } @$tagboxes;
	my $globjid_tagid = $slashdb->sqlSelectAllKeyValue(
		'firehose.globjid, tagid',
		'firehose, tags',
		"firehose.uid=$uid
		 AND firehose.globjid=tags.globjid
		 AND tags.uid=$uid
		 AND tagnameid=$self->{upvoteid}",
		'GROUP BY firehose.globjid');
	for my $globjid (sort keys %$globjid_tagid) {
		for my $tbid (@tagboxids) {
			$tagboxdb->addFeederInfo($tbid, {
				affected_id => $globjid,
				importance => 1,
				tagid => $globjid_tagid->{ $globjid },
			});
		}
	}
}

1;

