# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2003 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::Utility::Display;

=head1 NAME

Slash::Utility::Display - SHORT DESCRIPTION for Slash


=head1 SYNOPSIS

	use Slash::Utility;
	# do not use this module directly

=head1 DESCRIPTION

LONG DESCRIPTION.


=head1 EXPORTED FUNCTIONS

=cut

use strict;
use Slash::Display;
use Slash::Utility::Data;
use Slash::Utility::Environment;

use base 'Exporter';
use vars qw($VERSION @EXPORT);

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
@EXPORT	   = qw(
	cleanSlashTags
	createMenu
	createSelect
	currentAdminUsers
	fancybox
	getImportantWords
	horizmenu
	linkComment
	linkCommentPages
	linkStory
	lockTest
	matchingStrings
	pollbooth
	portalbox
	processSlashTags
	selectMode
	selectSection
	selectSortcode
	selectThreshold
	selectTopic
	titlebar
);

#========================================================================

=head2 createSelect(LABEL, DATA [, DEFAULT, RETURN, NSORT, ORDERED])

Creates a drop-down list in HTML.  List is sorted by default
alphabetically according to list values.

=over 4

=item Parameters

=over 4

=item LABEL

The name for the HTML entity.

=item DATA

A hashref containing key-value pairs for the list.
Keys are list values, and values are list labels.
If an arrayref is passed, it is converted to a
hashref, where the keys and values are the same.

=item DEFAULT

Default value for the list.

=item RETURN

See "Return value" below.

=item NSORT

Sort numerically, not alphabetically.

=item ORDERED

If an arrayref is passed, an already-sorted array reference of keys.
If non-ref, then an arrayref of hash keys is created sorting the
hash values, alphabetically and case-insensitively.
If ORDERED is passed in either form, then the NSORT parameter is ignored.

=back

=item Return value

If RETURN is true, the text of the list is returned.
Otherwise, list is just printed, and returns
true/false if operation is successful.

If there are no elements in DATA, just returns/prints nothing.

=item Dependencies

The 'select' template block.

=back

=cut

sub createSelect {
	my($label, $hashref, $default, $return, $nsort, $ordered) = @_;

	if (ref $hashref eq 'ARRAY') {
		$hashref = { map { ($_, $_) } @$hashref };
	} else {
		# If $hashref is a hash whose elements are also hashrefs, and
		# they all have the field "name", then copy it into another
		# hashref that pulls those "name" fields up one level.  Talk
		# about wacky convenience features!
		my @keys = keys %$hashref;
		my $all_name = 1;
		for my $key (@keys) {
			if (!ref($hashref->{$key})
				|| !ref($hashref->{$key}) eq 'HASH'
				|| !defined($hashref->{$key}{name})) {
				$all_name = 0;
				last;
			}
		}
		if ($all_name) {
			$hashref = {
				map { ($_, $hashref->{$_}{name}) }
				keys %$hashref
			};
		}
	}

	return unless (ref $hashref eq 'HASH' && keys %$hashref);

	if ($ordered && !ref $ordered) {
		$ordered = [
			map  { $_->[0] }
			sort { $a->[1] cmp $b->[1] }
			map  { [$_, lc $hashref->{$_}] }
			keys %$hashref
		];
	}

	my $display = {
		label	=> $label,
		items	=> $hashref,
		default	=> $default,
		numeric	=> $nsort,
		ordered	=> $ordered,
	};

	if ($return) {
		return slashDisplay('select', $display, 1);
	} else {
		slashDisplay('select', $display);
	}
}

#========================================================================

=head2 selectTopic(LABEL [, DEFAULT, SECTION, RETURN])

Creates a drop-down list of topics in HTML.  Calls C<createSelect>.

=over 4

=item Parameters

=over 4

=item LABEL

The name for the HTML entity.

=item DEFAULT

Default topic for the list.

=item SECTION

Default section to take topics from.

=item RETURN

See "Return value" below.

=back

=item Return value

If RETURN is true, the text of the list is returned.
Otherwise, list is just printed, and returns
true/false if operation is successful.

=back

=cut

sub selectTopic {
	my($label, $default, $section, $return) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	$section ||= getCurrentStatic('defaultsection');
	$default ||= getCurrentStatic('defaulttopic');

	my $topics = $reader->getDescriptions('topics_section', $section);

	createSelect($label, $topics, $default, $return, 0, 1);
}

#========================================================================

=head2 selectSection(LABEL [, DEFAULT, SECT, RETURN, ALL])

Creates a drop-down list of sections in HTML.  Calls C<createSelect>.

=over 4

=item Parameters

=over 4

=item LABEL

The name for the HTML entity.

=item DEFAULT

Default topic for the list.

=item SECT

Hashref for current section.  If SECT->{isolate} is true,
list is not created, but hidden value is returned instead.

=item RETURN

See "Return value" below.

=item ALL

Boolean for including "All Topics" item.

=back

=item Return value

If RETURN is true, the text of the list is returned.
Otherwise, list is just printed, and returns
true/false if operation is successful.

=item Dependencies

The 'sectionisolate' template block.

=back

=cut

sub selectSection {
	my($label, $default, $SECT, $return, $all) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });

	my $seclev = getCurrentUser('seclev');
	my $sections = $reader->getDescriptions('sections');

	createSelect($label, $sections, $default, $return);
}

#========================================================================

=head2 selectSortcode()

Creates a drop-down list of sortcodes in HTML.  Default is the user's
preference.  Calls C<createSelect>.

=over 4

=item Return value

The created list.

=back

=cut

sub selectSortcode {
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	createSelect('commentsort', $reader->getDescriptions('sortcodes'),
		getCurrentUser('commentsort'), 1);
}

#========================================================================

=head2 selectMode()

Creates a drop-down list of modes in HTML.  Default is the user's
preference.  Calls C<createSelect>.

=over 4

=item Return value

The created list.

=back

=cut

sub selectMode {
	my $reader = getObject('Slash::DB', { db_type => 'reader' });

	createSelect('mode', $reader->getDescriptions('commentmodes'),
		getCurrentUser('mode'), 1);
}

#========================================================================

=head2 selectThreshold(COUNTS)

Creates a drop-down list of thresholds in HTML.  Default is the user's
preference.  Calls C<createSelect>.

=over 4

=item Parameters

=over 4

=item COUNTS

An arrayref of thresholds -E<gt> counts for that threshold.

=back

=item Return value

The created list.

=item Dependencies

The 'selectThreshLabel' template block.

=back

=cut

sub selectThreshold  {
	my($counts) = @_;
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();

	my %data;
	foreach my $c ($constants->{comment_minscore} .. $constants->{comment_maxscore}) {
		$data{$c} = slashDisplay('selectThreshLabel', {
			points	=> $c,
			count	=> $counts->[$c - $constants->{comment_minscore}],
		}, { Return => 1, Nocomm => 1 });
	}

	createSelect('threshold', \%data, getCurrentUser('threshold'), 1, 1);
}

#========================================================================

=head2 linkStory(STORY)

The generic "Link a Story" function, used wherever stories need linking.

=over 4

=item Parameters

=over 4

=item STORY

A hashref containing data about a story to be linked to.

=back

=item Return value

The complete E<lt>A HREF ...E<gt>E<lt>/AE<gt> text for linking to the story.

=item Dependencies

The 'linkStory' template block.

=back

=cut

sub linkStory {
	my($story_link, $render, $other) = @_;
	my $reader    = $other->{reader} || getObject('Slash::DB', { db_type => 'reader' });
	my $constants = $other->{constants} || getCurrentStatic();
	my $user      = $other->{user} || getCurrentUser();

	my($url, $script, $title, $section, %params);
	$script = 'article.pl';
	$params{sid} = $story_link->{sid};
	$params{mode} = $story_link->{mode} || $user->{mode};
	$params{threshold} = $story_link->{threshold} if exists $story_link->{threshold};

	# Setting $dynamic properly is important.  When generating the
	# AC index.shtml, it's a big win if we link to other
	# prerendered .shtml URLs whenever possible/appropriate.
	# But, we must link to the .pl when necessary.

	my $dynamic = 0;
	if ($ENV{SCRIPT_NAME} || !$user->{is_anon}) {
		# Whenever we're invoked from Apache, use dynamic links.
		# This test will be true 99% of the time we come through
		# here, so it's first.
		$dynamic = 1;
	} elsif ($params{mode}) {
		# If we're an AC script, but this is a link to e.g.
		# mode=nocomment, then we need to have it be dynamic.
		$dynamic = 1 if $params{mode} ne getCurrentAnonymousCoward('mode');
	}

	if (!$dynamic && defined($params{threshold})) {
		# If we still think we can get away with a nondynamic link,
		# we need to check one more thing.  Even an AC linking to
		# an article needs to make the link dynamic if it's the
		# "n comments" link, where threshold = -1.  For maximum
		# compatibility we check against the AC's threshold.
		$dynamic = 1 if $params{threshold} != getCurrentAnonymousCoward('threshold');
	}

	# We need to make sure we always get the right link -Brian
	$story_link->{'link'} = $reader->getStory($story_link->{sid}, 'title') if $story_link->{'link'} eq '';
	$title       = $story_link->{'link'};
	$section     = $story_link->{section} ||= $reader->getStory($story_link->{sid}, 'section');
	$params{tid} = $reader->getStoryTopicsJustTids($story_link->{sid}); 

	my $SECT = $reader->getSection($story_link->{section});
	$url = $SECT->{rootdir} || $constants->{real_rootdir} || $constants->{rootdir};

	if ($dynamic) {
		$url .= '/' . $script . '?';
		for my $key (keys %params) {
			if (ref $params{$key} eq 'ARRAY') {
				$url .= "$key=$_&" for @{$params{$key}};
			} else {
				$url .= "$key=$params{$key}&";
			}
		}
		chop $url;
	} else {
		$url .= '/' . $section . '/' . $story_link->{sid} . '.shtml';
		# manually add the tid for now
		if ($params{tid}) {
			$url .= '?';
			if (ref $params{tid} eq 'ARRAY') {
				$url .= 'tid=' . fixparam($_) . '&' for @{$params{tid}};
			} else {
				$url .= 'tid=' . fixparam($params{tid}) . '&';
			}
			chop $url;
		}
	}

	if ($render) {
		my $rendered = '<A HREF="' . $url . '"';
		$rendered .= ' TITLE="' . strip_attribute($story_link->{title}) . '"'
			if $story_link->{title} ne '';
		$rendered .= '>' . $title . '</A>';
		return $rendered;
	} else {
		return [$url, $title, $story_link->{title}];
	}
}

#========================================================================

=head2 pollbooth(QID [, NO_TABLE, CENTER, RETURNTO])

Creates a voting pollbooth.

=over 4

=item Parameters

=over 4

=item QID

The unique question ID for the poll.

=item NO_TABLE

Boolean for whether to leave the poll out of a table.
If false, then will be formatted inside a C<fancybox>.

=item CENTER

Whether or not to center the tabled pollbooth (only
works with NO_TABLE).

=item RETURNTO

If this parameter is specified, the voting widget will take the vote and return
the user to the specified URI. Note that you WILL NOT be able to redirect
outside of the site usign this parameter for security reasons (hence the need for 
URIs as opposed to URLs).

=back

=item Return value

Returns the pollbooth data.

=item Dependencies

The 'pollbooth' template block.

=back

=cut

sub pollbooth {
	my($qid, $no_table, $center, $returnto) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $constants = getCurrentStatic();
	my $sect = $reader->getSection();

	# This special qid means to use the current (sitewide) poll.
	$qid = $sect->{qid} if $qid eq '_currentqid';
	# If no qid (or no sitewide poll), short-circuit out.
	return '' if $qid eq '';

	my $poll = $reader->getPoll($qid);
	return '' unless %$poll;

	my $n_comments = $reader->countCommentsBySid(
		$poll->{pollq}{discussion});
	my $poll_open = $reader->isPollOpen($qid);
	my $has_voted = $reader->hasVotedIn($qid);
	my $can_vote = !$has_voted && $poll_open;

	return slashDisplay('pollbooth', {
		question	=> $poll->{pollq}{question},
		answers		=> $poll->{answers},
		qid		=> $qid,
		has_activated   => $reader->hasPollActivated($qid),
		poll_open	=> $poll_open,
		has_voted	=> $has_voted,
		can_vote	=> $can_vote,
		voters		=> $poll->{pollq}{voters},
		comments	=> $n_comments,
		sect		=> $sect->{section},
		returnto	=> $returnto,
	}, 1);
}

#========================================================================

=head2 currentAdminUsers()

Displays table of current admin users, with what they are adminning.

=over 4

=item Return value

The HTML to display.

=item Dependencies

The 'currentAdminUsers' template block.

=back

=cut

sub currentAdminUsers {
	my $html_to_display;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();

# 	my $now = UnixDate(ParseDate($slashdb->getTime()), "%s");
	my $now = timeCalc($slashdb->getTime(), "%s", 0);
	my $aids = $slashdb->currentAdmin();
	for my $data (@$aids) {
		my($usernick, $usertime, $lasttitle, $uid) = @$data;
		if ($usernick eq $user->{nickname}) {
			$usertime = "-";
		} else {
			$usertime = $now - timeCalc($usertime, "%s", 0); # UnixDate(ParseDate($usertime), "%s");
			if ($usertime <= 99) {
				$usertime .= "s";
			} elsif ($usertime <= 3600) {
				$usertime = int($usertime/60+0.5) . "m";
			} else {
				$usertime = int($usertime/3600) . "h"
					. int(($usertime%3600)/60+0.5) . "m";
			}
		}
		@$data = ($usernick, $usertime, $lasttitle, $uid);
	}

	return slashDisplay('currentAdminUsers', {
		ids		=> $aids,
		can_edit_admins	=> $user->{seclev} > 10000,
	}, 1);
}

#========================================================================

=head2 horizmenu()

Silly little function to create a horizontal menu from the
'mainmenu' block.

=over 4

=item Return value

The horizontal menu.

=item Dependencies

The 'mainmenu' template block.

=back

=cut

sub horizmenu {
	my $horizmenu = slashDisplay('mainmenu', {}, { Return => 1, Nocomm => 1 });
	$horizmenu =~ s/^\s*//mg;
	$horizmenu =~ s/^-\s*//mg;
	$horizmenu =~ s/\s*$//mg;
	$horizmenu =~ s/<NOBR>//gi;
	$horizmenu =~ s/<\/NOBR>//gi;
	$horizmenu =~ s/<HR(?:>|\s[^>]*>)//g;
	$horizmenu = join ' | ', split /<BR>/, $horizmenu;
	$horizmenu =~ s/[\|\s]+$//;
	$horizmenu =~ s/^[\|\s]+//;
	return "[ $horizmenu ]";
}

#========================================================================

=head2 titlebar(WIDTH, TITLE, OPTIONS)

Prints a titlebar widget.  Exactly equivalent to:

	slashDisplay('titlebar', {
		width	=> $width,
		title	=> $title
	});

or, if template is passed in as an option, e.g. template => user_titlebar:

	slashDisplay('user_titlebar', {
		width	=> $width,
		title	=> $title
	});

If you're calling this from a template, you better have a really good
reason, since [% PROCESS %] will work just as well.

=over 4

=item Parameters

=over 4

=item WIDTH

Width of the titlebar.

=item TITLE

Title of the titlebar.

=back

=item Return value

None.

=item Dependencies

The 'titlebar' template block.

=back

=cut

sub titlebar {
	my($width, $title, $options) = @_;
	my $templatename = $options->{template} ? $options->{template} : "titlebar";
	my $data = { width => $width, title => $title };
	$data->{tab_selected} = $options->{tab_selected} if $options->{tab_selected};
	slashDisplay($templatename, $data);
}

#========================================================================

=head2 fancybox(WIDTH, TITLE, CONTENTS [, CENTER, RETURN])

Creates a fancybox widget.

=over 4

=item Parameters

=over 4

=item WIDTH

Width of the fancybox.

=item TITLE

Title of the fancybox.

=item CONTENTS

Contents of the fancybox.  (I see a pattern here.)

=item CENTER

Boolean for whether or not the fancybox
should be centered.

=item RETURN

Boolean for whether to return or print the
fancybox.

=back

=item Return value

The fancybox if RETURN is true, or true/false
on success/failure.

=item Dependencies

The 'fancybox' template block.

=back

=cut

sub fancybox {
	my($width, $title, $contents, $center, $return) = @_;
	return unless $title && $contents;

	my $tmpwidth = $width;
	# allow width in percent or raw pixels
	my $pct = 1 if $tmpwidth =~ s/%$//;
	# used in some blocks
	my $mainwidth = $tmpwidth-4;
	my $insidewidth = $mainwidth-8;
	if ($pct) {
		for ($mainwidth, $insidewidth) {
			$_ .= '%';
		}
	}

	slashDisplay('fancybox', {
		width		=> $width,
		contents	=> $contents,
		title		=> $title,
		center		=> $center,
		mainwidth	=> $mainwidth,
		insidewidth	=> $insidewidth,
	}, $return);
}

#========================================================================

=head2 portalbox(WIDTH, TITLE, CONTENTS, BID [, URL])

Creates a portalbox widget.  Calls C<fancybox> to process
the box itself.

=over 4

=item Parameters

=over 4

=item WIDTH

Width of the portalbox.

=item TITLE

Title of the portalbox.

=item CONTENTS

Contents of the portalbox.

=item BID

The block ID for the portal in question.

=item URL

URL to link the title of the portalbox to.

=back

=item Return value

The portalbox.

=item Dependencies

The 'fancybox', 'portalboxtitle', and
'portalmap' template blocks.

=back

=cut

sub portalbox {
	my($width, $title, $contents, $bid, $url, $getblocks) = @_;
	return unless $title && $contents;
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	$getblocks ||= 'index';

	$title = slashDisplay('portalboxtitle', {
		title	=> $title,
		url	=> $url,
	}, { Return => 1, Nocomm => 1 });

	if (($user->{exboxes} && $getblocks eq 'index') || 
		($user->{exboxes} && $constants->{slashbox_sections})) {
		$title = slashDisplay('portalmap', {
			title	=> $title,
			bid	=> $bid,
		}, { Return => 1, Nocomm => 1 });
	}

	fancybox($width, $title, $contents, 0, 1);
}

#========================================================================

=head2 linkCommentPages(SID, PID, CID, TOTAL)

Print links to pages for additional comments.

=over 4

=item Parameters

=over 4

=item SID

Story ID.

=item PID

Parent ID.

=item CID

Comment ID.

=item TOTAL

Total number of comments.

=back

=item Return value

Links.

=item Dependencies

The 'linkCommentPages' template block.

=back

=cut

sub linkCommentPages {
	my($sid, $pid, $cid, $total) = @_;

	return slashDisplay('linkCommentPages', {
		sid	=> $sid,
		pid	=> $pid,
		cid	=> $cid,
		total	=> $total,
	}, 1);
}

#========================================================================

=head2 linkComment(COMMENT [, PRINTCOMMENT, DATE])

Print a link to a comment.

=over 4

=item Parameters

=over 4

=item COMMENT

A hashref containing data about the comment.

=item PRINTCOMMENT

Boolean for whether to create link directly
to comment, instead of to the story for that comment.

=item DATE

Boolean for whather to print date with link.

=back

=item Return value

Link for comment.

=item Dependencies

The 'linkComment' template block.

=back

=cut

sub linkComment {
	my($comment, $printcomment, $date) = @_;
	my $constants = getCurrentStatic();
	return _hard_linkComment(@_) if $constants->{comments_hardcoded};

	my $user = getCurrentUser();
	my $adminflag = $user->{seclev} >= 10000 ? 1 : 0;

	# don't inherit these ...
	for (qw(sid cid pid date subject comment uid points lastmod
		reason nickname fakeemail homepage sig)) {
		$comment->{$_} = '' unless exists $comment->{$_};
	}

	$comment->{pid} = $comment->{original_pid} || $comment->{pid};

	slashDisplay('linkComment', {
		%$comment, # defaults
		adminflag	=> $adminflag,
		date		=> $date,
			# $comment->{threshold}? Hmm. I'm not sure what it
			# means for a comment to have a threshold. If it's 0,
			# does the following line do the right thing? - Jamie
		threshold	=> $comment->{threshold} || $user->{threshold},
		commentsort	=> $user->{commentsort},
		mode		=> $user->{mode},
		comment		=> $printcomment,
	}, { Return => 1, Nocomm => 1 });
}

#========================================================================

=head2 createMenu(MENU)

Creates a menu.

=over 4

=item Parameters

=over 4

=item MENU

The name of the menu to get.

=back

=item Return value

The menu.

=item Dependencies

The template blocks 'admin', 'user' (in the 'menu' page), and any other
template blocks for menus, along with all the data in the
'menus' table.

=back

=cut

sub createMenu {
	my($menu, $options) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();

	# The style of menu desired.  While we're "evolving" the way we do
	# menus, createMenu() handles several different styles.
	my $style = $options->{style} || "";
	$style = 'oldstyle' unless $style eq 'tabbed';

	# Use the colored background, for tabs that sit on top of the
	# colored titlebar, or use the white background, for tabs that sit
	# on top of the page below ("within" the colored titlebar)?
	my $color = $options->{color} || "";
	$color = 'colored' unless $color eq 'white';

	# Get the list of menu items from the "menus" table.  Then add in
	# any special ones passed in.
	my $menu_items = getCurrentMenu($menu);
	if ($options->{extra_items} && @{$options->{extra_items}}) {
		push @$menu_items, @{$options->{extra_items}};
	}
	if ($menu eq 'users'
		&& $user->{lastlookuid}
		&& $user->{lastlookuid} =~ /^\d+$/
		&& $user->{lastlookuid} != $user->{uid}
		&& ($user->{lastlooktime} || 0) >= time - ($constants->{lastlookmemory} || 3600)
	) {
		my $ll_nick = $reader->getUser($user->{lastlookuid}, 'nickname');
		my $nick_fix = fixparam($ll_nick);
		my $nick_attribute = strip_attribute($ll_nick);
		push @$menu_items, {
			value =>	"$constants->{rootdir}/~$nick_fix",
			label =>	"~$nick_attribute ($user->{lastlookuid})",
			sel_label =>	"otheruser",
			menuorder =>	99999,
		};
	}

	if (!$menu_items || !@$menu_items) {
		return "";
#		return "<!-- createMenu($menu, $style, $color), no items -->\n"; # DEBUG
	}

	# Now convert each item in the list into a hashref that can
	# be passed to the appropriate template.  The different
	# styles of templates each take a slightly different format
	# of data, and createMenu() is the front-end that makes sure
	# they get what they expect.
	my $items = [];
	for my $item (sort { $a->{menuorder} <=> $b->{menuorder} } @$menu_items) {

		# Only use items that the user can see.
		next if $item->{seclev} && $user->{seclev} < $item->{seclev};
		next if !$item->{showanon} && $user->{is_anon};

		my $opts = { Return => 1, Nocomm => 1 };
		my $data = { };
		$data->{value} = $item->{value} && slashDisplay(\$item->{value}, 0, $opts);
		$data->{label} = $item->{label} && slashDisplay(\$item->{label}, 0, $opts);
		if ($style eq 'tabbed') {
			# Tabbed menus don't display menu items with no
			# links on them.
			next unless $data->{value};
			# Reconfigure data for what the tabbedmenu
			# template expects.
			$data->{sel_label} = $item->{sel_label} || lc($data->{label});
			$data->{sel_label} =~ s/\s+//g;
			$data->{label} =~ s/ +/&nbsp;/g;
			$data->{link} = $data->{value};
		}

		push @$items, $data;
	}

	my $menu_text = "";
#	$menu_text .= "<!-- createMenu($menu, $style, $color), " . scalar(@$items) . " items -->\n"; # DEBUG

	if ($style eq 'tabbed') {
		# All menus in the tabbed style use the same template.
		$menu_text .= slashDisplay("tabbedmenu",
		 	{ tabs =>		$items,
			  justify =>		$options->{justify} || 'left',
			  color =>		$color,
			  tab_selected =>	$options->{tab_selected},	},
			{ Return => 1, Page => 'menu' });
	} elsif ($style eq 'oldstyle') {
		# Oldstyle menus each hit a different template,
		# "$menu;menu;default" -- so the $menu input refers
		# not only to the column "menu" in table "menus" but
		# also to which template to look up.  If no template
		# with that name is available (or $menu;misc;default,
		# or $menu;menu;light or whatever the fallbacks are)
		# then punt and go with "users;menu;default".
		my $nm = $reader->getTemplateByName($menu, 0, 0, "menu", "", 1);
		$menu = "users" unless $nm->{page} eq "menu";
		if (@$items) {
			$menu_text .= slashDisplay($menu,
				{ items =>	$items,
				  color =>	$color },
				{ Return => 1, Page => 'menu' });
		}
	}

	return $menu_text;
}

########################################################
# use lockTest to test if a story is being edited by someone else
########################################################
sub getImportantWords {
	my $s = shift;
	$s =~ s/[^A-Z0-9 ]//gi;
	my @w = split m/ /, $s;
	my @words;
	foreach (@w) {
		if (length($_) > 3 || (length($_) < 4 && uc($_) eq $_)) {
			push @words, $_;
		}
	}
	return @words;
}

########################################################
sub matchingStrings {
	my($s1, $s2) = @_;
	return '100' if $s1 eq $s2;
	my @w1 = getImportantWords($s1);
	my @w2 = getImportantWords($s2);
	my $m = 0;
	return if @w1 < 2 || @w2 < 2;
	foreach my $w (@w1) {
		foreach (@w2) {
			$m++ if $w eq $_;
		}
	}
	return int($m / @w1 * 100) if $m;
	return;
}

########################################################
sub lockTest {
	my($subj) = @_;
	return unless $subj;
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();

	my $msg;
	my $locks = $slashdb->getSessions([qw|lasttitle uid|]);
	for (values %$locks) {
		if ($_->{uid} ne getCurrentUser('uid') && (my $pct = matchingStrings($_->{subject}, $subj))) {
			$msg .= slashDisplay('lockTest', {
				percent		=> $pct,
				subject		=> $_->{subject},
				nickname	=> $slashdb->getUser($_->{uid}, 'nickname')
				}, 1);
		}
	}
	return $msg;
}

########################################################
# this sucks, but it is here for now
sub _hard_linkComment {
	my($comment, $printcomment, $date) = @_;
	my $user = getCurrentUser();
	my $constants = getCurrentStatic();

	my $subject = $comment->{color}
	? qq|<FONT COLOR="$comment->{color}">$comment->{subject}</FONT>|
		: $comment->{subject};

	my $display = qq|<A HREF="$constants->{rootdir}/comments.pl?sid=$comment->{sid}|;
	$display .= "&amp;op=$comment->{op}" if $comment->{op};
# $comment->{threshold}? Hmm. I'm not sure what it
# means for a comment to have a threshold. If it's 0,
# does the following line do the right thing? - Jamie
# You know, I think this is a bug that comes up every so often. But in 
# theory when you go to the comment link "threshhold" should follow 
# with you. -Brian
	$display .= "&amp;threshold=" . ($comment->{threshold} || $user->{threshold});
	$display .= "&amp;commentsort=$user->{commentsort}";
	$display .= "&amp;tid=$user->{state}{tid}" if $user->{state}{tid};
	$display .= "&amp;mode=$user->{mode}";
	$display .= "&amp;startat=$comment->{startat}" if $comment->{startat};

	if ($printcomment) {
		$display .= "&amp;cid=$comment->{cid}";
	} else {
		$display .= "&amp;pid=" . ($comment->{original_pid} || $comment->{pid});
		$display .= "#$comment->{cid}" if $comment->{cid};
	}

	$display .= qq|">$subject</A>|;
	if (!$comment->{subject_only}) {
		$display .= qq| by $comment->{nickname}|;
		$display .= qq| <FONT SIZE="-1">(Score:$comment->{points})</FONT> |
			if !$user->{noscores} && $comment->{points};
		$display .= qq| <FONT SIZE="-1">| . timeCalc($comment->{date}) . qq| </FONT>|
			if $date;
	}
	$display .= "\n";

	return $display;
}

#========================================================================
my $slashTags = {
	'image'    => \&_slashImage,
	'story'    => \&_slashStory,
	'user'     => \&_slashUser,
	'link'     => \&_slashLink,
	'break'    => \&_slashPageBreak,
	'file'     => \&_slashFile,
	'comment'  => \&_slashComment,
	'journal'  => \&_slashJournal,
};

my $cleanSlashTags = {
	'story'    => \&_cleanSlashStory,
	'user'     => \&_cleanSlashUser,
	'nickname' => \&_cleanSlashUser, # alternative syntax
	'link'     => \&_cleanSlashLink,
	'comment'  => \&_cleanSlashComment,
	'journal'  => \&_cleanSlashJournal,
};

sub cleanSlashTags {
	my($text, $options) = @_;
	return unless $text;


	$text =~ s#<slash-(image|story|user|file|break|link|comment|journal)#<SLASH TYPE="\L$1\E"#gis;
	my $newtext = $text;
	my $tokens = Slash::Custom::TokeParser->new(\$text);
	while (my $token = $tokens->get_tag('slash')) {
		my $type = lc($token->[1]{type});
		if (ref($cleanSlashTags->{$type}) ne 'CODE') {
			$type = $token->[1]{href}     ? 'link'  :
				$token->[1]{story}    ? 'story' :
				$token->[1]{nickname} ? 'user'  :
				$token->[1]{user}     ? 'user'  :
				undef;
		}
		$cleanSlashTags->{$type}($tokens, $token, \$newtext)
			if $type;
	}

	return $newtext;
}

sub _cleanSlashUser {
	my($tokens, $token, $newtext) = @_;

	my $user = $token->[1]{user} || $token->[1]{nickname} || $token->[1]{uid};
	return unless $user;

	my $slashdb = getCurrentDB();
	my($uid, $nickname);
	if ($user =~ /^\d+$/) {
		$uid = $user;
		$nickname = $slashdb->getUser($uid, 'nickname');
	} else {
		$nickname = $user;
		$uid = $slashdb->getUserUID($nickname);
	}

	$uid = strip_attribute($uid);
	$nickname = strip_attribute($nickname);
	my $content = qq|<SLASH NICKNAME="$nickname" UID="$uid" TYPE="user">|;
	$$newtext =~ s#\Q$token->[3]\E#$content#is;
}

sub _cleanSlashStory {
	my ($tokens, $token, $newtext) = @_;
	return unless $token->[1]{story};

	my $text;
	if ($token->[1]{text}) {
		$text = $token->[1]{text};
	} else {
		$text = $tokens->get_text("/slash");
	}

	my $slashdb = getCurrentDB();
	my $title = $token->[1]{title} 
	? strip_attribute($token->[1]{title}) 
		: strip_attribute($slashdb->getStory($token->[1]{story}, 'title', 1));
	my $sid = strip_attribute($token->[1]{story});

	my $content = qq|<SLASH STORY="$sid" TITLE="$title" TYPE="story">$text</SLASH>|;
	if ($token->[1]{text}) {
		$$newtext =~ s#\Q$token->[3]\E#$content#is;
	} else {
		$$newtext =~ s#\Q$token->[3]$text</SLASH>\E#$content#is;
	}
}

sub _cleanSlashLink {
	my ($tokens, $token, $newtext) = @_;
	my $relocateDB = getObject('Slash::Relocate');

	if (!$token->[1]{id}) {
		my $link  = $relocateDB->create({ url => $token->[1]{href} });
		my $href  = strip_attribute($token->[1]{href});
		my $title = strip_attribute($token->[1]{title});
		$$newtext =~ s#\Q$token->[3]\E#<SLASH HREF="$href" ID="$link" TITLE="$title" TYPE="link">#is;
	} else {
		my $url   = $relocateDB->get($token->[1]{id}, 'url');
		my $link  = $relocateDB->create({ url => $token->[1]{href} });
		my $href  = strip_attribute($token->[1]{href});
		my $title = strip_attribute($token->[1]{title});
		$$newtext =~ s#\Q$token->[3]\E#<SLASH HREF="$href" ID="$link" TITLE="$title" TYPE="link">#is;
	}
}

sub _cleanSlashComment {
}
sub _cleanSlashJournal {
}

sub processSlashTags {
	my($text, $options) = @_;
	return unless $text;

	my $newtext = $text;
	my $user = getCurrentUser();
	my $tokens = Slash::Custom::TokeParser->new(\$text);

	return $newtext unless $tokens;
	while (my $token = $tokens->get_tag('slash')) {
		my $type = lc($token->[1]{type});
		if (ref($slashTags->{$type}) eq 'CODE') {
			$slashTags->{$type}($tokens, $token, \$newtext);
		} else {
			my $content = Slash::getData('SLASH-UNKNOWN-TAG', { tag => $token->[0] });
			print STDERR "BAD TAG $token->[0]:$type\n";
			$newtext =~ s/\Q$token->[3]\E/$content/;
		}
	}

	if ($user->{stats}{pagebreaks} && !$user->{state}{editing}) {
		my $form = getCurrentForm();
# The logic is that if they are on the first page then page will be empty
# -Brian
		my @parts = split /<SLASH TYPE="break">/is, $newtext;
		if ($form->{page}) {
			$newtext = $parts[$form->{page} - 1];
		} else {
			$newtext = $parts[0];
		}
	}

	return $newtext;
}

sub _slashImage {
	my($tokens, $token, $newtext) = @_;

	my $content = slashDisplay('imageLink', {
		id	=> $token->[1]{id},
		title	=> $token->[1]{title},
		align	=> $token->[1]{align},
		width	=> $token->[1]{width},
		height	=> $token->[1]{height},
	}, {
		Return => 1,
		Nocomm => 1,
	});
	$content ||= Slash::getData('SLASH-UNKNOWN-IMAGE');

	$$newtext =~ s/\Q$token->[3]\E/$content/;
}

sub _slashStory {
	my($tokens, $token, $newtext) = @_;

	my $sid = $token->[1]{story};
	my $text = $tokens->get_text("/slash");
	my $storylinks = linkStory({
		'link'	=> $text,
		sid	=> $token->[1]{story},
		title	=> $token->[1]{title},
	});

	my $content;
	if ($storylinks->[0] && $storylinks->[2]) {
		$content = '<A HREF="' . $storylinks->[0] . '"';
		$content .= ' TITLE="' . strip_attribute($storylinks->[2]) . '"'
			if $storylinks->[2] ne '';
		$content .= '>' . $storylinks->[1] . '</A>';
	}

	$content ||= Slash::getData('SLASH-UNKNOWN-STORY');

	$$newtext =~ s#\Q$token->[3]$text</SLASH>\E#$content#is;
}

sub _slashUser {
	my($tokens, $token, $newtext) = @_;

	my $content = slashDisplay('userLink', {
		uid      => $token->[1]{uid},
		nickname => $token->[1]{nickname}, 
	}, {
		Return => 1,
		Nocomm => 1,
	});
	$content ||= Slash::getData('SLASH-UNKNOWN-USER');

	$$newtext =~ s/\Q$token->[3]\E/$content/;
}

sub _slashFile {
	my($tokens, $token, $newtext) = @_;

	my $id = $token->[1]{id};
	my $title = $token->[1]{title};
	my $text = $tokens->get_text("/slash");
	$title ||= $text;
	my $content = slashDisplay('fileLink', {
		id    => $id,
		title => $title,
		text  => $text,
	}, {
		Return => 1,
		Nocomm => 1,
	});
	$content ||= Slash::getData('SLASH-UNKNOWN-FILE');

	$$newtext =~ s#\Q$token->[3]$text</SLASH>\E#$content#is;
}

sub _slashLink {
	my($tokens, $token, $newtext) = @_;

	my $reloDB = getObject('Slash::Relocate', { db_type => 'reader' });
	my($content);
	my $text = $tokens->get_text("/slash");
	if ($reloDB) {
		$content = slashDisplay('hrefLink', {
			id    => $token->[1]{id},
			title => $token->[1]{title} || $token->[1]{href} || $text,
			text  => $text,
		}, {
			Return => 1,
			Nocomm => 1,
		});
	}
	$content ||= Slash::getData('SLASH-UNKNOWN-LINK');

	$$newtext =~ s#\Q$token->[3]$text</SLASH>\E#$content#is;
}

sub _slashPageBreak {
	my($tokens, $token, $newtext) = @_;
	my $user = getCurrentUser();

	$user->{stats}{pagebreaks}++;

	return;
}

sub _slashComment {
	my($tokens, $token, $newtext) = @_;
}

sub _slashJournal {
	my($tokens, $token, $newtext) = @_;
}

# sigh ... we had to change one line of TokeParser rather than
# waste time rewriting the whole thing
package Slash::Custom::TokeParser;

use base 'HTML::TokeParser';

sub get_text
{
    my $self = shift;
    my $endat = shift;
    my @text;
    while (my $token = $self->get_token) {
	my $type = $token->[0];
	if ($type eq "T") {
	    my $text = $token->[1];
# this is the one changed line
#	    decode_entities($text) unless $token->[2];
	    push(@text, $text);
	} elsif ($type =~ /^[SE]$/) {
	    my $tag = $token->[1];
	    if ($type eq "S") {
		if (exists $self->{textify}{$tag}) {
		    my $alt = $self->{textify}{$tag};
		    my $text;
		    if (ref($alt)) {
			$text = &$alt(@$token);
		    } else {
			$text = $token->[2]{$alt || "alt"};
			$text = "[\U$tag]" unless defined $text;
		    }
		    push(@text, $text);
		    next;
		}
	    } else {
		$tag = "/$tag";
	    }
	    if (!defined($endat) || $endat eq $tag) {
		 $self->unget_token($token);
		 last;
	    }
	}
    }
    join("", @text);
}

1;

__END__


=head1 SEE ALSO

Slash(3), Slash::Utility(3).

=head1 VERSION

$Id$
