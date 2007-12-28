#!/usr/bin/perl -w

use strict;
use Slash;
use Slash::Display;
use Slash::Utility;

# for debug
use Data::Dumper;

use vars qw( %task $me );

$task{$me}{timespec} = '2,12,22,32,42,52 * * * *';
$task{$me}{timespec_panic_1} = ''; # not that important
$task{$me}{on_startup} = 1;
$task{$me}{code} = sub {

        my($virtual_user, $constants, $slashdb, $user) = @_;
	my $mainskin = $slashdb->getSkin( $constants->{mainpage_skid} );
	my $skins = $slashdb->sqlSelectAll("skid, name, title","skins", "skid != " . $mainskin->{skid});
	my $html = '';
        $html .= q|<ul>|;
        $html .= qq|<li><a href="[% constants.real_rootdir %]/">$mainskin->{title}</a></li>|;

	foreach my $skin (@$skins) {
		my ($skid, $skinname, $skintitle) = @$skin;
		#my $date = timeCalc($slashdb->sqlSelect("time","stories","section='$sectid'"," ORDER BY time DESC"),'%m/%d');
		my $date = $slashdb->sqlSelect("time","stories","primaryskid='$skid'"," ORDER BY time DESC LIMIT 1" );
		if ($date) {
			$date = timeCalc($date,'%m/%d');
		} else {
			next;
		}
		$html .= qq|<li><a href="[% constants.real_rootdir %]/$skinname/">$skintitle <span class="date">$date</span></a></li>|;

	}
	$html .= '</ul>';

	my($tpid) = $slashdb->getTemplateByName('recentSections', 'tpid');
	$slashdb->setTemplate($tpid, { template => $html });

        return ;
};

1;

