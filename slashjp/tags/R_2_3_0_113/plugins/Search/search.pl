#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2003 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use Slash;
use Slash::Search;
use Slash::Display;
use Slash::Utility;
use Slash::XML;

#################################################################
sub main {
	my %ops = (
		comments	=> \&commentSearch,
		users		=> \&userSearch,
		stories		=> \&storySearch,
		polls		=> \&pollSearch,
		journals	=> \&journalSearch,
		submissions	=> \&submissionSearch,
		rss		=> \&rssSearch,
	);
	my %ops_rss = (
		comments	=> \&commentSearchRSS,
		users		=> \&userSearchRSS,
		stories		=> \&storySearchRSS,
		polls		=> \&pollSearchRSS,
		journals	=> \&journalSearchRSS,
		submissions	=> \&submissionSearchRSS,
		rss		=> \&rssSearchRSS,
	);

	my $constants = getCurrentStatic();
	my $form = getCurrentForm();
	my $user = getCurrentUser();
	# Backwards compatibility, we now favor tid over topic 
	$form->{tid} ||= $form->{topic};

	my($slashdb, $searchDB) = Slash::Search::SelectDataBases();

	# Set some defaults
	$form->{query}		||= '';
	$form->{'sort'}		||= 1;
	# this makes it so *no* results get returned, so i changed it back
	#$form->{section}	||= $constants->{section}; # Set to our current section if section is not passed in

	# if we're on a sectional page, default to that section unless another
	# is specified. If someone needs to search on all sections, they
	# shouldn't be in one.				--Pater
	$form->{section}	||= $user->{currentSection} || '';

	# switch search mode to poll if in polls section and other
	# search type isn't specified
	if ($user->{currentSection} eq 'polls' and !$form->{op}) {
		$form->{op} = 'polls';
		$form->{section} = '';
	}
         
	# This next line could be removed -Brian
	$form->{section}	= '' if $form->{section} eq 'index';
	$form->{threshold}	= getCurrentUser('threshold') if !defined($form->{threshold});

	# The default search operation is to search stories.
	$form->{op} ||= 'stories';
	if ($form->{op} eq 'rss' && !$user->{is_admin}) {
		$form->{op} = 'stories'
			unless $constants->{search_rss_enabled};
	} elsif ($form->{op} eq 'submissions' && !$user->{is_admin}) {
		$form->{op} = 'stories'
			unless $constants->{submiss_view};
	}

	if ($form->{content_type} eq 'rss') {
		# Here, panic mode is handled within the individual funcs.
		# We want to return valid (though empty) RSS data even
		# when search is down.
		$form->{op} = 'stories' if !exists($ops_rss{$form->{op}});
		$ops_rss{$form->{op}}->($form, $constants, $slashdb, $searchDB);
	} else {
		# Yep, these are hardcoded, and someday this should change... -Brian 
		my $text = strip_notags($form->{query});
		header("$constants->{sitename}: Search  $text") or return;
		titlebar("100%", "Searching For:  $text");
		$form->{op} = 'stories' if !exists($ops{$form->{op}});

		# Here, panic mode is handled without needing to call the
		# individual search subroutines;  we're going to tell the
		# user the same thing in each case anyway.
		if ($constants->{panic} >= 1 or $constants->{search_google} or !$searchDB) {
			slashDisplay('nosearch');
		} else {
			if ($ops{$form->{op}}) {
				$ops{$form->{op}}->($form, $constants, $slashdb, $searchDB);
			}
		}

		footer();
	}

	writeLog($form->{query})
		if $form->{op} =~ /^(?:comments|stories|users|polls|journals|submissions|rss)$/;
}


#################################################################
# Ugly isn't it?
sub _authors {
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $authors = $reader->getDescriptions('all-authors');
	my %newauthors = %$authors;
	$newauthors{''} = getData('all_authors');

	return \%newauthors;
}

#################################################################
# Ugly isn't it?
sub _topics {
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $section = getCurrentForm('section');

	my $topics;
	if ($section) {
		$topics = $reader->getDescriptions('topics_section', $section);
	} else {
		$topics = $reader->getDescriptions('topics');
	}

	my %newtopics = %$topics;
	$newtopics{''} = getData('all_topics');

	return \%newtopics;
}

#################################################################
sub _sort {
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $sort = $reader->getDescriptions('sortorder');

	return $sort;
}

#################################################################
# Ugly isn't it?
sub _sections {
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $sections = $reader->getDescriptions('sections');
	my %newsections = %$sections;
	$newsections{''} = getData('all_sections');
	delete $newsections{'polls'};
	return \%newsections;
}

#################################################################
# Ugly isn't it?
sub _subsections {
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $form = getCurrentForm();
	my $subsections = $reader->getDescriptions('section_subsection', $form->{section}, 1)
		if $form->{section};
	return undef
		unless (keys %$subsections);
	my %newsections = %$subsections;
	$newsections{''} = getData('all_subsections');

	return \%newsections;
}

#################################################################
sub _buildargs {
	my($form) = @_;
	my $uri;

	for (qw[threshold query author op topic tid section sort journal_only]) {
		my $x = "";
		$x =  $form->{$_} if defined $form->{$_} && $x eq "";
		$x =~ s/ /+/g;
		$uri .= "$_=$x&" unless $x eq "";
	}
	$uri =~ s/&$//;

	return fixurl($uri);
}

#################################################################
sub commentSearch {
	my($form, $constants, $slashdb, $searchDB) = @_;

	my $start = $form->{start} || 0;
	my $comments = $searchDB->findComments($form, $start, $constants->{search_default_display} + 1, $form->{sort});

	my $formats = $slashdb->getDescriptions('threshcodes');
	my $threshold_select = createSelect(
		'threshold', $formats, $form->{threshold}, 1
	);

	slashDisplay('searchform', {
		sections	 => _sections(),
		topics		 => _topics(),
		tref		 => $slashdb->getTopic($form->{tid}),
		op		 => $form->{op},
		'sort'		 => _sort(),
		threshhold 	 => 1,
		threshold_select => $threshold_select,
	});

	if ($comments && @$comments) {
		# check for extra articles ... we request one more than we need
		# and if we get the extra one, we know we have extra ones, and
		# we pop it off
		my $forward;
		if (@$comments == $constants->{search_default_display} + 1) {
			pop @$comments;
			$forward = $start + $constants->{search_default_display} + 1;
		} else {
			$forward = 0;
		}

		# if there are less than search_default_display remaning,
		# just set it to 0
		my $back;
		if ($start > 0) {
			$back = $start - $constants->{search_default_display};
			$back = $back > 0 ? $back : 0;
		} else {
			$back = -1;
		}

		slashDisplay('commentsearch', {
			comments	=> $comments,
			back		=> $back,
			forward		=> $forward,
			args		=> _buildargs($form),
			start		=> $start,
		});
	} else {
		print getData('nocomments');
	}
}

#################################################################
sub userSearch {
	my($form, $constants, $slashdb, $searchDB) = @_;

	my $start = $form->{start} || 0;
	my $users = $searchDB->findUsers($form, $start, $constants->{search_default_display} + 1, $form->{sort}, $form->{journal_only});
	slashDisplay('searchform', {
		op		=> $form->{op},
		'sort'		=> _sort(),
		journal_option	=> 1,
	});

	if ($users && @$users) {
		# check for extra articles ... we request one more than we need
		# and if we get the extra one, we know we have extra ones, and
		# we pop it off
		my $forward;
		if (@$users == $constants->{search_default_display} + 1) {
			pop @$users;
			$forward = $start + $constants->{search_default_display};
		} else {
			$forward = 0;
		}

		# if there are less than search_default_display remaning,
		# just set it to 0
		my $back;
		if ($start > 0) {
			$back = $start - $constants->{search_default_display};
			$back = $back > 0 ? $back : 0;
		} else {
			$back = -1;
		}

		slashDisplay('usersearch', {
			users		=> $users,
			back		=> $back,
			forward		=> $forward,
			args		=> _buildargs($form),
		});
	} else {
		print getData('nousers');
	}
}

#################################################################
sub storySearch {
	my($form, $constants, $slashdb, $searchDB) = @_;

	my $start = $form->{start} || 0;
	my $stories = $searchDB->findStory($form, $start, $constants->{search_default_display} + 1, $form->{sort});

	slashDisplay('searchform', {
		sections	=> _sections(),
		subsections	=> _subsections(),
		topics		=> _topics(),
		tref		=> $slashdb->getTopic($form->{tid}),
		op		=> $form->{op},
		authors		=> _authors(),
		'sort'		=> _sort(),
	});

	if ($stories && @$stories) {
		# check for extra articles ... we request one more than we need
		# and if we get the extra one, we know we have extra ones, and
		# we pop it off
		my $forward;
		if (@$stories == $constants->{search_default_display} + 1) {
			pop @$stories;
			$forward = $start + $constants->{search_default_display};
		} else {
			$forward = 0;
		}

		for (@$stories) {
			$_->{introtext} = substr(strip_notags($_->{introtext}),0,$constants->{search_text_length});
			$_->{introtext} =~ s/(.*) .*$/$1.../g;
		}

		# if there are less than search_default_display remaning,
		# just set it to 0
		my $back;
		if ($start > 0) {
			$back = $start - $constants->{search_default_display};
			$back = $back > 0 ? $back : 0;
		} else {
			$back = -1;
		}

		slashDisplay('storysearch', {
			stories		=> $stories,
			back		=> $back,
			forward		=> $forward,
			args		=> _buildargs($form),
			start		=> $start,
		});
	} else {
		print getData('nostories');
	}
}

#################################################################
sub pollSearch {
	my($form, $constants, $slashdb, $searchDB) = @_;

	my $start = $form->{start} || 0;
	my $polls = $searchDB->findPollQuestion($form, $start, $constants->{search_default_display} + 1, $form->{sort});
	slashDisplay('searchform', {
		op		=> $form->{op},
		topics		=> _topics(),
		sections	=> _sections(),
		tref		=> $slashdb->getTopic($form->{tid}),
		'sort'		=> _sort(),
	});

	if ($polls && @$polls) {
		# check for extra articles ... we request one more than we need
		# and if we get the extra one, we know we have extra ones, and
		# we pop it off
		my $forward;
		if (@$polls == $constants->{search_default_display} + 1) {
			pop @$polls;
			$forward = $start + $constants->{search_default_display};
		} else {
			$forward = 0;
		}

		# if there are less than search_default_display remaning,
		# just set it to 0
		my $back;
		if ($start > 0) {
			$back = $start - $constants->{search_default_display};
			$back = $back > 0 ? $back : 0;
		} else {
			$back = -1;
		}

		slashDisplay('pollsearch', {
			polls		=> $polls,
			back		=> $back,
			forward		=> $forward,
			args		=> _buildargs($form),
			start		=> $start,
		});
	} else {
		print getData('nopolls');
	}
}

#################################################################
sub commentSearchRSS {
	my($form, $constants, $slashdb, $searchDB) = @_;

	my $start = $form->{start} || 0;
	my $comments;
	if ($constants->{panic} >= 1 or $constants->{search_google}) {
		$comments = [ ];
	} else {
		$comments = $searchDB->findComments($form, $start, 15, $form->{sort});
	}

	my @items;
	for my $entry (@$comments) {
		my $time = timeCalc($entry->{date});
		push @items, {
			title	=> "$entry->{subject} ($time)",
			'link'	=> ($constants->{absolutedir} . "/comments.pl?sid=$entry->{did}&cid=$entry->{cid}"),
		};
	}

	xmlDisplay(rss => {
		channel => {
			title		=> "$constants->{sitename} Comment Search",
			'link'		=> "$constants->{absolutedir}/search.pl",
			description	=> "$constants->{sitename} Comment Search",
		},
		image	=> 1,
		items	=> \@items
	});
}

#################################################################
sub userSearchRSS {
	my($form, $constants, $slashdb, $searchDB) = @_;

	my $start = $form->{start} || 0;
	my $users;
	if ($constants->{panic} >= 1 or $constants->{search_google}) {
		$users = [ ];
	} else {
		$users = $searchDB->findUsers($form, $start, 15, $form->{sort});
	}

	my @items;
	for my $entry (@$users) {
		my $time = timeCalc($entry->{journal_last_entry_date});
		push @items, {
			title	=> $entry->{nickname},
			'link'	=> ($constants->{absolutedir} . '/users.pl?nick=' . $entry->{nickname}),
		};
	}

	xmlDisplay(rss => {
		channel => {
			title		=> "$constants->{sitename} User Search",
			'link'		=> "$constants->{absolutedir}/search.pl",
			description	=> "$constants->{sitename} User Search",
		},
		image	=> 1,
		items	=> \@items
	});
}

#################################################################
sub storySearchRSS {
	my($form, $constants, $slashdb, $searchDB) = @_;

	my $start = $form->{start} || 0;
	my $stories;
	if ($constants->{panic} >= 1 or $constants->{search_google}) {
		$stories = [ ];
	} else {
		$stories = $searchDB->findStory($form, $start, 15, $form->{sort});
	}

	my @items;
	for my $entry (@$stories) {
		my $time = timeCalc($entry->{time});
		# Link should be made to be sectional -Brian
		push @items, {
			title	=> $entry->{title},
			'link'	=> ($constants->{absolutedir} . '/article.pl?sid=' . $entry->{sid}),
			description	=> $entry->{introtext}
		};
	}

	xmlDisplay(rss => {
		channel => {
			title		=> "$constants->{sitename} Story Search",
			'link'		=> "$constants->{absolutedir}/search.pl",
			description	=> "$constants->{sitename} Story Search",
		},
		image	=> 1,
		items	=> \@items
	});
}

#################################################################
sub pollSearchRSS {
	my($form, $constants, $slashdb, $searchDB) = @_;

	my $start = $form->{start} || 0;
	my $stories;
	if ($constants->{panic} >= 1 or $constants->{search_google}) {
		$stories = [ ];
	} else {
		$stories = $searchDB->findPollQuestion($form, $start, 15, $form->{sort});
	}

	my @items;
	for my $entry (@$stories) {
		my $time = timeCalc($entry->{date});
		my $url = $slashdb->getSection($entry->{section}, 'url');
		my $link = $url || $constants->{absolutedir};
		push @items, {
			title	=> "$entry->{question} ($time)",
			'link'	=> ($link . '/pollBooth.pl?qid=' . $entry->{qid}),
		};
	}

	xmlDisplay(rss => {
		channel => {
			title		=> "$constants->{sitename} Poll Search",
			'link'		=> "$constants->{absolutedir}/search.pl",
			description	=> "$constants->{sitename} Poll Search",
		},
		image	=> 1,
		items	=> \@items
	});
}

#################################################################
# Do not enable -Brian
sub findRetrieveSite {
	my($form, $constants, $slashdb, $searchDB) = @_;

	my $start = $form->{start} || 0;
	my $feeds = $searchDB->findRetrieveSite($form->{query}, $start, $constants->{search_default_display} + 1, $form->{sort});

	# check for extra feeds ... we request one more than we need
	# and if we get the extra one, we know we have extra ones, and
	# we pop it off
	my $forward;
	if (@$feeds == $constants->{search_default_display} + 1) {
		pop @$feeds;
		$forward = $start + $constants->{search_default_display};
	} else {
		$forward = 0;
	}

	# if there are less than search_default_display remaning,
	# just set it to 0
	my $back;
	if ($start > 0) {
		$back = $start - $constants->{search_default_display};
		$back = $back > 0 ? $back : 0;
	} else {
		$back = -1;
	}

	slashDisplay('retrievedsites', {
		feeds		=> $feeds,
		back		=> $back,
		forward		=> $forward,
		start		=> $start,
	});
}


#################################################################
# Do not enable -Brian
sub findRetrieveSiteRSS {
	my($form, $constants, $slashdb, $searchDB) = @_;

	my $start = $form->{start} || 0;
	my $feeds = $searchDB->findFeeds($form->{query}, $start, 15, $form->{sort});

	# I am aware that the link has to be improved.
	my @items;
	for my $entry (@$feeds) {
		my $time = timeCalc($entry->{'time'});
		push @items, {
			title	=> "$entry->{title} ($time)",
			'link'	=> ($constants->{absolutedir} . "/users.pl?op=preview&bid=entry->{bid} %]"),
		};
	}

	xmlDisplay(rss => {
		channel => {
			title		=> "$constants->{sitename} Retrieve Site Search",
			'link'		=> "$constants->{absolutedir}/search.pl",
			description	=> "$constants->{sitename} Retrieve Site Search",
		},
		image	=> 1,
		items	=> \@items
	});
}

#################################################################
sub journalSearch {
	my($form, $constants, $slashdb, $searchDB) = @_;

	my $start = $form->{start} || 0;
	my $entries = $searchDB->findJournalEntry($form, $start, $constants->{search_default_display} + 1, $form->{sort});
	slashDisplay('searchform', {
		op		=> $form->{op},
		'sort'		=> _sort(),
	});

	# check for extra articles ... we request one more than we need
	# and if we get the extra one, we know we have extra ones, and
	# we pop it off
	if ($entries && @$entries) {
		my $forward;
		if (@$entries == $constants->{search_default_display} + 1) {
			pop @$entries;
			$forward = $start + $constants->{search_default_display};
		} else {
			$forward = 0;
		}

		for (@$entries) {
			$_->{article} = substr(strip_notags($_->{article}),0,$constants->{search_text_length});
			$_->{article} =~ s/(.*) .*$/$1.../g;
		}

		# if there are less than search_default_display remaning,
		# just set it to 0
		my $back;
		if ($start > 0) {
			$back = $start - $constants->{search_default_display};
			$back = $back > 0 ? $back : 0;
		} else {
			$back = -1;
		}

		slashDisplay('journalsearch', {
			entries		=> $entries,
			back		=> $back,
			forward		=> $forward,
			args		=> _buildargs($form),
			start		=> $start,
		});
	} else {
		print getData('nojournals');
	}
}

#################################################################
sub journalSearchRSS {
	my($form, $constants, $slashdb, $searchDB) = @_;

	my $start = $form->{start} || 0;
	my $entries = $searchDB->findJournalEntry($form, $start, 15, $form->{sort});

	my @items;
	for my $entry (@$entries) {
		my $time = timeCalc($entry->{date});
		push @items, {
			title	=> "$entry->{description} ($time)",
			'link'	=> ($constants->{absolutedir} . '/~' . fixparam($entry->{nickname}) . '/journal/' . $entry->{id}),
			description	=> $constants->{article},
		};
	}

	xmlDisplay(rss => {
		channel => {
			title		=> "$constants->{sitename} Journal Search",
			'link'		=> "$constants->{absolutedir}/search.pl",
			description	=> "$constants->{sitename} Journal Search"
		},
		image	=> 1,
		items	=> \@items
	});
}

#################################################################
sub submissionSearch {
	my($form, $constants, $slashdb, $searchDB) = @_;

	my $start = $form->{start} || 0;
	my $entries = $searchDB->findSubmission($form, $start, $constants->{search_default_display} + 1, $form->{sort});
	slashDisplay('searchform', {
		op		=> $form->{op},
		sections	=> _sections(),
		topics		=> _topics(),
		submission_notes => $slashdb->getDescriptions('submission-notes'),
		tref		=> $slashdb->getTopic($form->{tid}),
		'sort'		=> _sort(),
	});

	# check for extra articles ... we request one more than we need
	# and if we get the extra one, we know we have extra ones, and
	# we pop it off
	if ($entries && @$entries) {
		my $forward;
		if (@$entries == $constants->{search_default_display} + 1) {
			pop @$entries;
			$forward = $start + $constants->{search_default_display};
		} else {
			$forward = 0;
		}

		for (@$entries) {
			$_->{story} = substr(strip_notags($_->{story}),0,$constants->{search_text_length});
			$_->{story} =~ s/(.*) .*$/$1.../g;
		}

		# if there are less than search_default_display remaning,
		# just set it to 0
		my $back;
		if ($start > 0) {
			$back = $start - $constants->{search_default_display};
			$back = $back > 0 ? $back : 0;
		} else {
			$back = -1;
		}

		slashDisplay('subsearch', {
			entries		=> $entries,
			back		=> $back,
			forward		=> $forward,
			args		=> _buildargs($form),
			start		=> $start,
		});
	} else {
		print getData('nosubmissions');
	}
}

#################################################################
sub submissionSearchRSS {
	my($form, $constants, $slashdb, $searchDB) = @_;

	my $start = $form->{start} || 0;
	my $entries = $searchDB->findSubmission($form, $start, 15, $form->{sort});

	my @items;
	for my $entry (@$entries) {
		my $time = timeCalc($entry->{time});
		push @items, {
			title		=> "$entry->{subj} ($time)",
			'link'		=> ($constants->{absolutedir} . '/submit.pl?subid=' . $entry->{subid}),
			'description'	=> $entry->{story},
		};
	}

	xmlDisplay(rss => {
		channel => {
			title		=> "$constants->{sitename} Submission Search",
			'link'		=> "$constants->{absolutedir}/search.pl",
			description	=> "$constants->{sitename} Submission Search",
		},
		image	=> 1,
		items	=> \@items
	});
}

#################################################################
sub rssSearch {
	my($form, $constants, $slashdb, $searchDB) = @_;

	my $start = $form->{start} || 0;
	my $entries = $searchDB->findRSS($form, $start, $constants->{search_default_display} + 1, $form->{sort});
	slashDisplay('searchform', {
		op		=> $form->{op},
		'sort'		=> _sort(),
	});

	# check for extra articles ... we request one more than we need
	# and if we get the extra one, we know we have extra ones, and
	# we pop it off
	if ($entries && @$entries) {
		for (@$entries) {
			$_->{title} = strip_plaintext($_->{title});
			$_->{description} = substr(strip_plaintext($_->{description}),0,$constants->{search_text_length});
		}
		my $forward;
		if (@$entries == $constants->{search_default_display} + 1) {
			pop @$entries;
			$forward = $start + $constants->{search_default_display};
		} else {
			$forward = 0;
		}

		# if there are less than search_default_display remaning,
		# just set it to 0
		my $back;
		if ($start > 0) {
			$back = $start - $constants->{search_default_display};
			$back = $back > 0 ? $back : 0;
		} else {
			$back = -1;
		}

		slashDisplay('rsssearch', {
			entries		=> $entries,
			back		=> $back,
			forward		=> $forward,
			args		=> _buildargs($form),
			start		=> $start,
		});
	} else {
		print getData('norss');
	}
}

#################################################################
sub rssSearchRSS {
	my($form, $constants, $slashdb, $searchDB) = @_;

	my $start = $form->{start} || 0;
	my $entries = $searchDB->findRSS($form, $start, 15, $form->{sort});

	my @items;
	for my $entry (@$entries) {
		my $time = timeCalc($entry->[2]);
		push @items, {
			title	=> "$entry->{title} ($time)",
			'link'	=> $entry->{link}, # No, this is not right -Brian
			'description'	=> $entry->{description},
		};
	}

	xmlDisplay(rss => {
		channel => {
			title		=> "$constants->{sitename} RSS Search",
			'link'		=> "$constants->{absolutedir}/search.pl",
			description	=> "$constants->{sitename} RSS Search",
		},
		image	=> 1,
		items	=> \@items
	});
}

#################################################################
createEnvironment();
main();

#=======================================================================
#package Slash::Search;
#use Slash::Utility;
#
#sub getDBUsers {
#	my $constants = getCurrentStatic();
#	my ($slashdb, $searchDB);
#	if ($constants->{search_db_user}) {
#		$slashdb  = getObject('Slash::DB', $constants->{search_db_user});
#		$searchDB = getObject('Slash::Search', $constants->{search_db_user});
#	} else {
#		$slashdb  = getCurrentDB();
#		$searchDB = getObject('Slash::Search');
#	}
#	return($slashdb, $searchDB);
#}
#
#
##=======================================================================
#package Slash::Search::SOAP;
#use Slash::Utility;
#
#sub findStory {
#	my($class, $query) = @_;
#	my $user      = getCurrentUser();
#	my $constants = getCurrentStatic();
#	my($slashdb, $searchDB) = Slash::Search::getDBUsers();
#
#	my $stories;
#	if ($constants->{panic} >= 1 or $constants->{search_google}) {
#		$stories = [ ];
#	} else {
#		$stories = $searchDB->findStory({ query => $query }, 0, 15);
#	}
#
#	return $stories;
#}

#################################################################
1;
