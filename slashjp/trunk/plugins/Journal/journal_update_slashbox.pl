#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright (C) 2008 OSDN Corporation.
#
# $Id: journal_fix.pl 153 2007-07-04 08:10:36Z tach $

use Data::Dumper;
use strict;

use Slash::Constants ':slashd';
use Slash::Utility;

use vars qw( %task $me);

$task{$me}{timespec} = '* * * * *'; # should happen every minute?
$task{$me}{fork} = SLASHD_NOWAIT;
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;
	my $force = $constants->{task_options}{force} || undef;
	my $block_suffix = '_topjournals';
	my $limit = getCurrentStatic('journal_top') || 10;
	my $skins = $slashdb->getSkins();

	foreach my $skin (values(%$skins)) {
		my $name = "$skin->{name}$block_suffix";
		my $block = $slashdb->getBlock($name);
		unless ($block->{bid}) {
			slashdLog("Could not get block \"$name\", skipped");
			next;
		}
		my $tids = [ $slashdb->getAllChildrenTids($skin->{nexus}) ];
		unless (@$tids > 0) {
			slashdLog("Could not get tid for \"$name\", skipped");
			next;
		}
		my $where = '1=1';
		$where .= ' AND tid IN ('.join(',', @$tids).')' if ($skin->{skid} != $constants->{mainpage_skid});
		next if ($slashdb->sqlCount('journals', $where . ($force ? '' : " AND date > '$block->{last_update}'")) < 1);

		slashdLog("Start updating block \"$name\"") if (verbosity() >= 3);
		my $result = $slashdb->sqlSelectAllHashrefArray(
			'nickname AS author,MAX(id) AS jid,description AS title',
			'journals JOIN users USING (uid)',
			$where,
			"GROUP BY uid ORDER BY jid DESC LIMIT $limit",
		);
		map { $_->{'link'} = "$constants->{absolutedir}/~" . strip_paramattr($_->{author}) . "/journal/". $_->{jid} } @$result;

		my $str = "<ul>\n";
		foreach my $item (@$result) {
			$str .= slashDisplay('topjournals', { 'item' => $item }, { Return => 1, Nocomm => 1, Page => 'portald' });
		}
		$str .= "\n</ul>";
		if ($skin->{skid} == $constants->{mainpage_skid}) {
			my $morestr = getData('journal_slashbox_more', {
				'link'	=> "$constants->{absolutedir}/journals/top/recent/?start=$limit",
			}, 'journal');
			$str .= $morestr if ($morestr);
		}
		$slashdb->setBlock($name, { block => $str });

		slashdLog("Updated block \"$name\"") if (verbosity() >= 2);
	}
};

1;
