#!/usr/bin/perl -w

# $Id$

use strict;
use Slash;
use Slash::Display;
use Slash::Events;
use Slash::Utility;

sub main {

	my $slashdb   = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user      = getCurrentUser();
	my $form      = getCurrentForm();
	my $gSkin     = getCurrentSkin();
	my $events    = getObject('Slash::Events');

	my $ops = {
		edit     => {
			function => \&editEvent,
			seclev	=> 100,
		},
		'delete'	=> {
			function => \&editEvent,
			seclev	=> 100,
		},
		add	    => {
			function => \&editEvent,
			seclev	=> 100,
		},
		list    => {
			function => \&listEvents,
			seclev	=> 100,
		},
	};

	my $op = lc($form->{op});
	chomp($op);
	$op = exists $ops->{$op} ? $op : 'list';

# eventsadmin.pl is not for regular users
	unless ($user->{is_admin}) {
		my $rootdir = getCurrentSkin('rootdir');
		redirect("$rootdir/users.pl");
		return;
	}
	header() or return;
	print createMenu('events');

	$ops->{$op}{function}->($slashdb, $constants, $user, $form, $events, $gSkin);

	footer();
}

##################################################################
sub editEvent {

	my ($slashdb,$constants,$user,$form,$events) = @_;

	# I really hate all this ugly select code
	if ($form->{beginmonth} && $form->{beginyear} && $form->{beginday}) {
	    $form->{begindate} = $form->{beginyear} . "/" . $form->{beginmonth} . "/" . $form->{beginday};
	}
	if ($form->{endmonth} && $form->{endyear} && $form->{endday}) {
	    $form->{enddate} = $form->{endyear} . "/" . $form->{endmonth} . "/" . $form->{endday};
	}

	$form->{begindate} ||= timeCalc($slashdb->getTime(), '%Y-%m-%d');
	$form->{enddate} ||= $form->{begindate}; 

	if ($form->{op} eq 'delete') {
		$events->deleteDates($form->{id});
		print "Deleted event $form->{id} sid $form->{sid}<br>\n";
	} elsif ($form->{op} eq 'add') {
		$form->{enddate} ||= $form->{begindate};
		$events->setDates($form->{sid} , $form->{begindate}, $form->{enddate});
	}
	my $dates =  $events->getDatesBySid($form->{sid});
	my $title =  $events->getStory($form->{sid}, 'title');

	my $days = [1 .. 31] ;
	my $months = $slashdb->getDescriptions('months');
	my $years = $slashdb->getDescriptions('years');
	my $selectedref = {};

	for ( 'beginday','beginmonth', 'beginyear', 'endday', 'endmonth', 'endyear') {
	    my $formatstring = '%d';
	    $formatstring = '%m' if $_ =~ /month/;
	    $formatstring = '%Y' if $_ =~ /year/;
	    $selectedref->{$_} = $form->{$_} ? $form->{$_} : int(timeCalc($slashdb->getTime(),$formatstring));
	}	


	slashDisplay('editevent', {
		storytitle 		=> $title,
		dates 			=> $dates,
		days			=> $days,
		months			=> $months,
		years			=> $years,
		sid 			=> $form->{sid},
		selectedref		=> $selectedref,
	});
};

##################################################################
sub listEvents { 
	my($slashdb, $constants, $user, $form, $events, $gSkin) = @_;

	# I really hate all this ugly select code
	if ($form->{beginmonth} && $form->{beginyear} && $form->{beginday}) {
	    $form->{begindate} = $form->{beginyear} . "/" . $form->{beginmonth} . "/" . $form->{beginday};
	}
	if ($form->{endmonth} && $form->{endyear} && $form->{endday}) {
	    $form->{enddate} = $form->{endyear} . "/" . $form->{endmonth} . "/" . $form->{endday};
	}

	$form->{begindate} ||= timeCalc($slashdb->getTime(), '%Y-%m-%d');
	# $form->{enddate} ||= $form->{begindate}; 
	my $stories =  $events->getEvents($form->{begindate},$form->{enddate});

	my $days = [1 .. 31] ;
	my $months = $slashdb->getDescriptions('months');
	my $years = $slashdb->getDescriptions('years');
	my $selectedref = {};

	for ( 'beginday','beginmonth', 'beginyear', 'endday', 'endmonth', 'endyear') {
	    my $formatstring = '%d';
	    $formatstring = '%m' if $_ =~ /month/;
	    $formatstring = '%Y' if $_ =~ /year/;
	    $selectedref->{$_} = $form->{$_} ? $form->{$_} : int(timeCalc($slashdb->getTime(),$formatstring));
	}	

	if ($form->{content_type} =~ $constants->{feed_types}) {
		my @items;
		for my $entry (@$stories) {
			push @items, {
				title	=> $entry->[1],
				'link'	=> ($gSkin->{absolutedir} . "/article.pl?sid=$entry->[0])"),
			};
		}

		xmlDisplay($form->{content_type} => {
			channel => {
				title		=> "$constants->{sitename} events",
				'link'		=> "$gSkin->{absolutedir}/",
			},
			image	=> 1,
			items	=> \@items
		});
	} else {
		if (@$stories) {
			slashDisplay('listevents', {
				events		=> $stories,
				days		=> $days,
				months		=> $months,	    
				years		=> $years,
				selectedref	=> $selectedref,
			});
		} else {
			my $message = "Sorry, nothing found";
			print $message;
		}
	}


}

##################################################################

createEnvironment();
main();
1;
