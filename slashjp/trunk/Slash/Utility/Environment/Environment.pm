# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2003 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::Utility::Environment;

=head1 NAME

Slash::Utility::Environment - SHORT DESCRIPTION for Slash


=head1 SYNOPSIS

	use Slash::Utility;
	# do not use this module directly

=head1 DESCRIPTION

LONG DESCRIPTION.


=head1 EXPORTED FUNCTIONS

=cut

use strict;
use Apache::ModuleConfig;
use Digest::MD5 'md5_hex';
use Time::HiRes;

use base 'Exporter';
use vars qw($VERSION @EXPORT);

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;
@EXPORT	   = qw(
	createCurrentAnonymousCoward
	createCurrentCookie
	createCurrentDB
	createCurrentForm
	createCurrentHostname
	createCurrentStatic
	createCurrentUser
	createCurrentVirtualUser

	setCurrentForm
	setCurrentUser

	getCurrentAnonymousCoward
	getCurrentCookie
	getCurrentDB
	getCurrentForm
	getCurrentMenu
	getCurrentStatic
	getCurrentUser
	getCurrentVirtualUser
	getCurrentCache

	createEnvironment
	getObject
	getAnonId
	isAnon
	isSubscriber
	prepareUser
	filter_params

	setUserDate
	isDST

	bakeUserCookie
	eatUserCookie
	setCookie

	slashProf
	slashProfInit
	slashProfEnd

	createLog
	errorLog
	writeLog
);

use constant DST_HR  => 0;
use constant DST_NUM => 1;
use constant DST_DAY => 2;
use constant DST_MON => 3;

# These are file-scoped variables that are used when you need to use the
# set methods when not running under mod_perl
my($static_user, $static_form, $static_constants, $static_site_constants, 
	$static_db, $static_anonymous_coward, $static_cookie,
	$static_virtual_user, $static_objects, $static_cache, $static_hostname);

# FRY: I don't regret this.  But I both rue and lament it.

#========================================================================

=head2 getCurrentMenu([NAME])

Returns the menu for the resource requested.

=over 4

=item Parameters

=over 4

=item NAME

Name of the menu that you want to fetch.  If not supplied,
menu named after active script will be used (i.e., the "users"
menu for "users.pl").

=back

=item Return value

A reference to an array with the menu in it is returned.

=back

=cut

sub getCurrentMenu {
	my($menu) = @_;
	my($user, @menus, $user_menu);

	# do we want to bother with menus at all for static pages?
	# i can see why we might ... i dunno -- pudge
	#
	# Well, yes. Since createMenu() may be used in a header
	# and a footer, if we don't generate menus on static pages,
	# the page itself will be busted. We've already run into this
	# for one site, so took a stab at fixing it. -- Cliff
	if ($ENV{GATEWAY_INTERFACE}) {;
		$user = getCurrentUser();

		unless ($menu) {
			($menu = $ENV{SCRIPT_NAME}) =~ s/\.pl$//;
		}

		my $r = Apache->request;
		my $cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');

		return unless $cfg->{menus}{$menu};
		@menus = @{$cfg->{menus}{$menu}};
	} else {
		# Load menus direct from the database.
		my $reader = getObject('Slash::DB', { db_type => 'reader' });
		my $menus = $reader->getMenus();

		@menus = @{$menus->{$menu}} if exists $menus->{$menu};
	}
	
	if ($user && ($user_menu = $user->{menus}{$menu})) {
		push @menus, values %$user_menu;
	}

	return \@menus;
}

#========================================================================

=head2 getCurrentUser([MEMBER])

Returns the current authenicated user.

=over 4

=item Parameters

=over 4

=item MEMBER

A member from the users record to be returned.

=back

=item Return value

A hash reference with the user information is returned unless VALUE is passed. If
MEMBER is passed in then only its value will be returned.

=back

=cut

sub getCurrentUser {
	my($value) = @_;
	my $user;

	if ($ENV{GATEWAY_INTERFACE} && (my $r = Apache->request)) {
		my $cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
		$user = $cfg->{'user'} ||= {};
	} else {
		$user = $static_user   ||= {};
	}

	# i think we want to test defined($foo), not just $foo, right?
	if ($value) {
		return defined($user->{$value})
			? $user->{$value}
			: undef;
	} else {
		return $user;
	}
}

#========================================================================

=head2 setCurrentUser(MEMBER, VALUE)

Sets a value for the current user.  It will not be permanently stored.

=over 4

=item Parameters

=over 4

=item MEMBER

The member to store VALUE in.

=item VALUE

VALUE to be stored in the current user hash.

=back

=item Return value

The passed value.

=back

=cut

sub setCurrentUser {
	my($key, $value) = @_;
	my $user;

	if ($ENV{GATEWAY_INTERFACE}) {
		my $r = Apache->request;
		my $cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
		$user = $cfg->{'user'};
	} else {
		$user = $static_user;
	}

	$user->{$key} = $value;
}

#========================================================================

=head2 setCurrentForm(MEMBER, VALUE)

Sets a value for the current user.  It will not be permanently stored.

=over 4

=item Parameters

=over 4

=item MEMBER

The member to store VALUE in.

=item VALUE

VALUE to be stored in the current user hash.

=back

=item Return value

The passed value.

=back

=cut

sub setCurrentForm {
	my($key, $value) = @_;
	my $form;

	if ($ENV{GATEWAY_INTERFACE}) {
		my $r = Apache->request;
		my $cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
		$form = $cfg->{'form'};
	} else {
		$form = $static_form;
	}

	$form->{$key} = $value;
}

#========================================================================

=head2 createCurrentUser(USER)

Creates the current user.

=over 4

=item Parameters

=over 4

=item USER

USER to be inserted into current user.

=back

=item Return value

Returns no value.

=back

=cut

sub createCurrentUser {
	my($user) = @_;

	$user ||= {};

	if ($ENV{GATEWAY_INTERFACE} && (my $r = Apache->request)) {
		my $cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
		$cfg->{'user'} = $user;
	} else {
		$static_user = $user;
	}
}

#========================================================================

=head2 getCurrentForm([MEMBER])

Returns the current form.

=over 4

=item Parameters

=over 4

=item MEMBER

A member from the forms record to be returned.

=back

=item Return value

A hash reference with the form information is returned unless VALUE is passed.  If
MEMBER is passed in then only its value will be returned.

=back

=cut

sub getCurrentForm {
	my($value) = @_;
	my $form;

	if ($ENV{GATEWAY_INTERFACE} && (my $r = Apache->request)) {
		my $cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
		$form = $cfg->{'form'};
	} else {
		$form = $static_form;
	}

	if ($value) {
		return defined($form->{$value})
			? $form->{$value}
			: undef;
	} else {
		return $form;
	}
}

#========================================================================

=head2 createCurrentForm(FORM)

Creates the current form.

=over 4

=item Parameters

=over 4

=item FORM

FORM to be inserted into current form.

=back

=item Return value

Returns no value.

=back

=cut

sub createCurrentForm {
	my($form) = @_;

	$form ||= {};

	if ($ENV{GATEWAY_INTERFACE}) {
		my $r = Apache->request;
		my $cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
		$cfg->{'form'} = $form;
	} else {
		$static_form = $form;
	}
}

#========================================================================

=head2 getCurrentCookie([MEMBER])

Returns the current cookie.

=over 4

=item Parameters

=over 4

=item MEMBER

A member from the cookies record to be returned.

=back

=item Return value

A hash reference with the cookie incookieation is returned
unless VALUE is passed.  If MEMBER is passed in then
only its value will be returned.

=back

=cut

sub getCurrentCookie {
	my($value) = @_;
	my $cookie;

	if ($ENV{GATEWAY_INTERFACE}) {
		my $r = Apache->request;
		my $cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
		$cookie = $cfg->{'cookie'};
	} else {
		$cookie = $static_cookie;
	}

	if ($value) {
		return defined($cookie->{$value})
			? $cookie->{$value}
			: undef;
	} else {
		return $cookie;
	}
}

#========================================================================

=head2 createCurrentCookie(COOKIE)

Creates the current cookie.

=over 4

=item Parameters

=over 4

=item COOKIE

COOKIE to be inserted into current cookie.

=back

=item Return value

Returns no value.

=back

=cut

sub createCurrentCookie {
	my($cookie) = @_;

	$cookie ||= {};

	if ($ENV{GATEWAY_INTERFACE}) {
		my $r = Apache->request;
		my $cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
		$cfg->{'cookie'} = $cookie;
	} else {
		$static_cookie = $cookie;
	}
}

#========================================================================

=head2 getCurrentStatic([MEMBER])

Returns the current static variables (or variable).

=over 4

=item Parameters

=over 4

=item MEMBER

A member from the static record to be returned.

=back

=item Return value

A hash reference with the static information is returned unless MEMBER is passed. If
MEMBER is passed in then only its value will be returned.

=back

=cut

sub getCurrentStatic {
	my($value) = @_;
	my $constants;

	if ($ENV{GATEWAY_INTERFACE} && (my $r = Apache->request)) {
		my $const_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
		my $hostname = $r->header_in('host');
		if ($const_cfg->{'site_constants'}{$hostname}) { 
			$constants = $const_cfg->{site_constants}{$hostname};
		} else {
			$constants = $const_cfg->{'constants'};
		}
	} else {
		if ($static_site_constants->{$static_hostname}) {
			$constants = $static_site_constants->{$static_hostname};
		} else {
			$constants = $static_constants;
		}
	}

	if ($value) {
		return defined($constants->{$value})
			? $constants->{$value}
			: undef;
	} else {
		return $constants;
	}
}

#========================================================================

=head2 createCurrentStatic(HASH)

Creates the current static information for non Apache scripts.

=over 4

=item Parameters

=over 4

=item HASH

A hash that is to be used in scripts not running in Apache to simulate a
script running under Apache.

=back

=item Return value

Returns no value.

=back

=cut

sub createCurrentStatic {
	($static_constants) = @_;
	$static_site_constants = $_[1] if defined $_[1];
}

#========================================================================

=head2 createCurrentHostname(HOSTNAME)

Allows you to set a host so that constants will behave properly.

=over 4

=item Parameters

=over 4

=item HOSTNAME

A name of a host to use to force constants to think it is being used by a host.

=back

=item Return value

Returns no value.

=back

=cut

sub createCurrentHostname {
	($static_hostname) = @_;
}

#========================================================================

=head2 getCurrentAnonymousCoward([MEMBER])

Returns the current anonymous corward (or value from that object).

=over 4

=item Parameters

=over 4

=item MEMBER

A member from the AC record to be returned.

=back

=item Return value

If MEMBER, then that value is returned; else, the hash containing all
the AC info will be returned.

=back

=cut

sub getCurrentAnonymousCoward {
	my($value) = @_;

	if ($ENV{GATEWAY_INTERFACE}) {
		my $r = Apache->request;
		my $const_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
		if ($value) {
			return $const_cfg->{'anonymous_coward'}{$value};
		} else {
			my %coward = %{$const_cfg->{'anonymous_coward'}};
			return \%coward;
		}
	} else {
		if ($value) {
			return $static_anonymous_coward->{$value};
		} else {
			my %coward = %{$static_anonymous_coward};
			return \%coward;
		}
	}
}

#========================================================================

=head2 createCurrentAnonymousCoward(HASH)

Creates the current anonymous coward for non Apache scripts.

=over 4

=item Parameters

=over 4

=item HASH

A hash that is to be used in scripts not running in Apache to simulate a
script running under Apache.

=back

=item Return value

Returns no value.

=back

=cut

sub createCurrentAnonymousCoward {
	($static_anonymous_coward) = @_;
}

#========================================================================

=head2 getCurrentVirtualUser()

Returns the current virtual user that the site is running under.

=over 4

=item Return value

The current virtual user that the site is running under.

=back

=cut

sub getCurrentVirtualUser {
	if ($ENV{GATEWAY_INTERFACE} && (my $r = Apache->request)) {
		my $cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
		return $cfg->{'VirtualUser'};
	} else {
		return $static_virtual_user;
	}
}

#========================================================================

=head2 createCurrentVirtualUser(VIRTUAL_USER)

Creates the current virtual user for non Apache scripts.

=over 4

=item Parameters

=over 4

=item VIRTUAL_USER

The current virtual user that is to be used in scripts not running in Apache
to simulate a script running under Apache.

=back

=item Return value

Returns no value.

=back

=cut

sub createCurrentVirtualUser {
	($static_virtual_user) = @_;
}

#========================================================================

=head2 getCurrentDB()

Returns the current Slash::DB object.

=over 4

=item Return value

Returns the current Slash::DB object.

=back

=cut

sub getCurrentDB {
	my $slashdb;

	if ($ENV{GATEWAY_INTERFACE} && (my $r = Apache->request)) {
		my $const_cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
		$slashdb = $const_cfg->{slashdb};
	} else {
		$slashdb = $static_db;
	}

	return $slashdb;
}

#========================================================================

=head2 createCurrentDB(SLASHDB)

Creates the current DB object for scripts not running under Apache.

=over 4

=item Parameters

=over 4

=item SLASHDB

Pass in a Slash::DB object to be used for scripts not running
in Apache.

=back

=item Return value

Returns no value.

=back

=cut

sub createCurrentDB {
	($static_db) = @_;
}

#========================================================================

=head2 isAnon(UID)

Tests to see if the uid passed in is an anonymous coward.

=over 4

=item Parameters

=over 4

=item UID

Value UID.

=back

=item Return value

Returns true if the UID is an anonymous coward, otherwise false.

=back

=cut

sub isAnon {
	my($uid) = @_;
	# this might be undefined in the event of a comment preview
	# when a data structure is not fully filled out, etc.
	return 1 if	!defined($uid)		# no undef
		||	$uid eq ''		# no empty string
		||	$uid =~ /[^0-9]/	# only integers
		||	$uid < 1		# only positive
	;
	return $uid == getCurrentStatic('anonymous_coward_uid');
}

#========================================================================

=head2 isSubscriber(USER)

Tests to see if the user passed in is a subscriber.

=over 4

=item Parameters

=over 4

=item USER

User data hashref from getUser() call.

If you pass a UID instead of a USER, then the function will call getUser() for you.

=back

=item Return value

Returns true if the USER is a subscriber, otherwise false.

=back

=cut

sub isSubscriber {
	my($suser) = @_;
	my $constants = getCurrentStatic();

	# assume is not subscriber by default
	my $subscriber = 0;

	if ($constants->{subscribe}) {
		if (! ref $suser) {
			my $slashdb = getCurrentDB();
			$suser = $slashdb->getUser($suser);
		}

		$subscriber = 1 if $suser->{hits_paidfor} &&
			$suser->{hits_bought} < $suser->{hits_paidfor};
	} else {
		$subscriber = 1;  # everyone is a subscriber if subscriptions are turned off
	}

	return $subscriber;
}

#========================================================================

=head2 getAnonId([FORMKEY])

Creates an anonymous ID that is used to set an AC cookie,
with some random data (well, as random as random gets)

=over 4

=item Parameters

=over 4

=item FORMKEY

Return the same value as normal, but without prepending with a '-1-'.
The normal case, with '-1-', is for easy identification of cookies.
This case is for use with formkeys.

=back

=item Return value

A random value based on alphanumeric characters

=back

=cut

{
	my @chars = (0..9, 'A'..'Z', 'a'..'z');
	sub getAnonId {
		my $str;
		$str = '-1-' unless $_[0];
		$str .= join('', map { $chars[rand @chars] }  0 .. 9);
		return $str;
	}
}

#========================================================================

=head2 bakeUserCookie(UID, PASSWD)

Bakes (creates) a user cookie from its ingredients (UID, PASSWD).

Currently cookie is hexified: this should be changed, no need anymore,
perhaps?  -- pudge

=over 4

=item Parameters

=over 4

=item UID

User ID.

=item PASSWD

Password.

=back

=item Return value

Created cookie.

=back

=cut

# create a user cookie from ingredients
sub bakeUserCookie {
	my($uid, $passwd) = @_;
	my $cookie = $uid . '::' . $passwd;
	$cookie =~ s/(.)/sprintf("%%%02x", ord($1))/ge;
	return $cookie;
}

#========================================================================

=head2 eatUserCookie(COOKIE)

Digests (parses) a user cookie, returning it to its original ingredients
(UID, password).

Currently cookie is hexified: this should be changed, no need anymore,
perhaps?  -- pudge

=over 4

=item Parameters

=over 4

=item COOKIE

Cookie to be parsed.

=back

=item Return value

The UID and password encoded in the cookie.

=back

=cut

sub eatUserCookie {
	my($cookie) = @_;
	$cookie =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack('C', hex($1))/ge;
	my($uid, $passwd) = split(/::/, $cookie, 2);
	return($uid, $passwd);
}

#========================================================================

=head2 setCookie(NAME, VALUE, SESSION)

Creates a cookie and places it into the outbound headers.  Can be
called multiple times to set multiple cookies.

=over 4

=item Parameters

=over 4

=item NAME

NAme of the cookie.

=item VALUE

Value to be placed in the cookie.

=item SESSION

Flag to determine if the cookie should be a session cookie.

=back

=item Return value

No value is returned.

=back

=cut

sub setCookie {
	return unless $ENV{GATEWAY_INTERFACE};

	my($name, $val, $session) = @_;
	return unless $name;

	my $r = Apache->request;
	my $constants = getCurrentStatic();

	# We need to actually determine domain from preferences,
	# not from the server, so the site admin can specify
	# special preferences if they want to. -- pudge
	my $cookiedomain = $constants->{cookiedomain};
	my $cookiepath   = $constants->{cookiepath};

	# note that domain is not a *host*, it is a *domain*,
	# so "slashdot.org" is an invalid domain, but
	# ".slashdot.org" is OK.  the only way to set a cookie
	# to a *host* is to leave the domain blank, which is
	# why we set the first cookie with no domain. -- pudge

	# domain must start with a '.' and have one more '.'
	# embedded in it, else we ignore it
	my $domain = ($cookiedomain && $cookiedomain =~ /^\..+\./)
		? $cookiedomain
		: '';

	my %cookiehash = (
		-name    =>  $name,
		-value   =>  $val || 'nobody',
		-path    =>  $cookiepath
	);

	$cookiehash{-secure} = 1
		if $constants->{cookiesecure} && Slash::Apache::ConnectionIsSSL();

	my $cookie = Apache::Cookie->new($r, %cookiehash);

	# this should be fine, but if there is a problem, comment the following
	# lines, and uncomment the one right above "bake"
	if (!$val) {
		$cookie->expires('-1y');  # delete
	} elsif (!$session) {
		$cookie->expires('+1y');
	}

	$cookie->bake;

	if ($domain) {
		$cookie->domain($domain);
		$cookie->bake;
	}
}

#========================================================================

=head2 prepareUser(UID, FORM, URI [, COOKIES])

This is called to initialize the user.  It is called from
Slash::Apache::User::handler, and from createEnvironment (so it
can set up a user in "command line" mode).  See those two functions
to see how to call this function in each kind of environment.

=over 4

=item Parameters

=over 4

=item UID

The UID of the user.  Can be anonymous coward.  Will be anonymous
coward if uid is not defined.

=item FORM

The form data (which may be the same data returned by getCurrentForm).

=item URI

The URI of the page the user is on.

=item COOKIES

An Apache::Cookie object (not used in "command line" mode).

=back

=item Return value

The prepared user data.

=item Side effects

Sets some cookies in Apache mode, sets currentPage (for templates) and
bunches of other user datum.

=back

=cut

sub prepareUser {
	# we must get form data and cookies, because we are preparing it here
	my($uid, $form, $uri, $cookies, $method) = @_;
	my($slashdb, $constants, $user, $hostip);

	$cookies ||= {};
	$method ||= "";
	$slashdb = getCurrentDB();
	$constants = getCurrentStatic();

	my $r;
	if ($ENV{GATEWAY_INTERFACE}) {
		$r = Apache->request;
		$hostip = $r->connection->remote_ip;
	} else {
		$hostip = '';
	}
	
	# First we find a good reader DB so that we can use that for the user.
	my $databases = $slashdb->getDBs();
	my %user_types;
	for my $type (keys %$databases) {
		my $db = $databases->{$type};

		# shuffle the deck
		my $i = @$db;
		while ($i--) {
			my $j = int rand($i+1);
			@$db[$i, $j] = @$db[$j, $i];
		}

		# there can be only one
		my $virtual_user;
		for (@$db) {
			if ($_->{isalive} eq 'yes') {
				$virtual_user = $_->{virtual_user};
				last;
			}
		}

		# save in user's state
		$user_types{$type} = $virtual_user;
	}

	$uid = $constants->{anonymous_coward_uid} unless defined($uid) && $uid ne '';

	my $reader = getObject('Slash::DB', { virtual_user => $user_types{reader} });

	if (isAnon($uid)) {
		if ($ENV{GATEWAY_INTERFACE}) {
			$user = getCurrentAnonymousCoward();
		} else {
			$user = $reader->getUser($constants->{anonymous_coward_uid});
		}
		$user->{is_anon} = 1;
		$user->{state} = {};
	} else {
		$user = $reader->getUser($uid);
		$user->{is_anon} = 0;
	}

	# Now store the DB information from above in the user. -Brian
	for my $type (keys %user_types) {
		$user->{state}{dbs}{$type} = $user_types{$type};
	}


	unless ($user->{is_anon} && $ENV{GATEWAY_INTERFACE}) { # already done in Apache.pm
		setUserDate($user);
	}

	$user->{state}{post}	= $method eq 'POST' ? 1 : 0;
	$user->{ipid}		= md5_hex($hostip);
	$user->{subnetid}	= $hostip;
	$user->{subnetid}	=~ s/(\d+\.\d+\.\d+)\.\d+/$1\.0/;
	$user->{subnetid}	= md5_hex($user->{subnetid});

	my @defaults = (
		['mode', 'thread'], qw[
		savechanges commentsort threshold
		posttype noboxes light
	]);

	for my $param (@defaults) {
		my $default;
		if (ref($param) eq 'ARRAY') {
			($param, $default) = @$param;
		}

		if (defined $form->{$param} && $form->{$param} ne '') {
			$user->{$param} = $form->{$param};
		} else {
			$user->{$param} ||= $default || 0;
		}
	}
	$user->{karma_bonus} = '+1' unless defined($user->{karma_bonus});

	# All sorts of checks on user data
	$user->{exaid}		= _testExStr($user->{exaid}) if $user->{exaid};
	$user->{exboxes}	= _testExStr($user->{exboxes}) if $user->{exboxes};
	$user->{extid}		= _testExStr($user->{extid}) if $user->{extid};
	$user->{points}		= 0 unless $user->{willing}; # No points if you dont want 'em
	$user->{domaintags}	= 2 if !defined($user->{domaintags}) || $user->{domaintags} !~ /^\d+$/;

	# This is here so when user selects "6 ish" it
	# "posted by xxx around 6 ish" instead of "on 6 ish"
	## this does not call Slash::getData right now because
	## it is just so early in the code that the AC user does
	## not even exist yet in static mode, and it causes problems
	## with slashDisplay.  -- pudge
	if ($user->{'format'} eq '%l ish') {	# %i
		$user->{aton} = 'around'; # Slash::getData('atonish');
	} else {
		$user->{aton} = 'on'; # Slash::getData('aton');
	}

	if ($uri =~ m[^/$]) {
		$user->{currentPage} = 'index';
	} elsif ($uri =~ m{(?:/|\b)([^/]+)\.pl$}) {
		$user->{currentPage} = $1;
	} else {
		$user->{currentPage} = 'misc';
	}

	if (	   ( $user->{currentPage} eq 'article'
			|| $user->{currentPage} eq 'comments' )
		&& ( $user->{commentlimit} > $constants->{breaking}
			&& $user->{mode} ne 'archive'
			&& $user->{mode} ne 'metamod' )
	) {
		$user->{commentlimit} = int($constants->{breaking} / 2);
		$user->{breaking} = 1;
	} else {
		$user->{breaking} = 0;
	}

	if ($constants->{subscribe}) {
		# Decide whether the user is a subscriber.
		$user->{is_subscriber} = 1 if $user->{hits_paidfor}
			&& $user->{hits_bought} < $user->{hits_paidfor};
		# Make other decisions about subscriber-related attributes
		# of this page.  Note that we still have $r lying around,
		# so we can save Subscribe.pm a bit of work.
		if (my $subscribe = getObject('Slash::Subscribe', { db_type => 'reader' })) {
			$user->{state}{page_plummy} = $subscribe->plummyPage($r, $user);
			$user->{state}{page_buying} = $subscribe->buyingThisPage($r, $user);
			$user->{state}{page_adless} = $subscribe->adlessPage($r, $user);
		}
	}
	if ($user->{seclev} >= 100) {
		$user->{is_admin} = 1;
		my $sid;
		#This cookie could go, and we could have session instance
		#do its own thing without the cookie. -Brian
		if ($cookies->{session}) {
			$sid = $slashdb->getSessionInstance($uid, $cookies->{session}->value);
		} else {
			$sid = $slashdb->getSessionInstance($uid);
		}
		setCookie('session', $sid) if $sid;
		if ($constants->{admin_check_clearpass}
			&& !Slash::Apache::ConnectionIsSecure()) {
			$user->{state}{admin_clearpass_thisclick} = 1;
		}
	}
	if ($user->{seclev} > 1
		&& $constants->{admin_clearpass_disable}
		&& ($user->{state}{admin_clearpass_thisclick} || $user->{admin_clearpass})) {
		# User temporarily loses their admin privileges until they
		# change their password.
		$user->{seclev} = 1;
		$user->{state}{lostprivs} = 1;
	}

	return $user;
}


#========================================================================

=head2 filter_params(PARAMS)

This cleans up form data before it is used by the program.

=over 4

=item Parameters

=over 4

=item PARAMS

A hash of the parameters to clean up.

=back

=item Return value

Hashref of cleaned-up data.

=back

=cut

{
	my %multivalue = map {($_ => 1)} qw(
		section_multiple
	);

	# fields that are numeric only
	my %nums = map {($_ => 1)} qw(
		approved artcount bseclev
		buymore cid clbig clsmall
		commentlimit commentsort commentspill
		del displaystatus
		filter_id hbtm height highlightthresh
		isolate issue last maillist max
		maxcommentsize maximum_length maxstories
		min minimum_length minimum_match next
		nobonus_present
		nosubscriberbonus_present
		ordernum pid
		postanon_present posttype ratio retrieve
		seclev start startat threshold
		thresh_count thresh_secs thresh_hps
		uid uthreshold voters width
		textarea_rows textarea_cols tokens
		subid stid tpid tid qid aid
		url_id spider_id miner_id keyword_id
	);

	# fields that have ONLY a-zA-Z0-9_
	my %alphas = map {($_ => 1)} qw(
		fieldname formkey commentstatus
		hcanswer mode op section type
	);

	# regexes to match dynamically generated numeric fields
	my @regints = (qr/^reason_.+$/, qr/^votes.+$/, qr/^people_bonus_.+$/);

	# special few
	my %special = (
		sid	=> sub { $_[0] =~ s|[^A-Za-z0-9/._]||g	},
		flags	=> sub { $_[0] =~ s|[^a-z0-9_,]||g	},
		query	=> sub { $_[0] =~ s|[\000-\040<>\177-\377]+| |g;
			         $_[0] =~ s|\s+| |g;		},
	);


sub filter_params {
	my($apr) = @_;
	my %form;

	if (ref($apr) eq "HASH") {
		# for now, we cannot have more than simple key->value
		# (see createEnvironment())
		%form = %$apr;
	} else {
		for ($apr->param) {
			my @values = $apr->param($_);
			if (scalar(@values) > 1) { 
				$form{$_} = $values[0];
				$form{_multi}{$_} = \@values;
			} else {
				$form{$_} = $values[0];
			}
			# allow any param ending in _multiple to be multiple -- pudge
			if (exists $multivalue{$_} || /_multiple$/) {
				my @multi = $apr->param($_);
				$form{$_} = \@multi;
				$form{_multi}{$_} = \@multi;
				next;
			}
		}
	}

	for my $key (keys %form) {
		if ($key eq '_multi') {
			for my $key (keys %{$form{_multi}}) {
				my @data;
				for my $data (@{$form{_multi}{$key}}) {
					push @data, filter_param($key, $data);
				}
				$form{_multi}{$key} = \@data;
			}			
		} elsif (ref($form{$key}) eq 'ARRAY') {
			my @data;
			for my $data (@{$form{$key}}) {
				push @data, filter_param($key, $data);
			}
			$form{$key} = \@data;
		} else {
			$form{$key} = filter_param($key, $form{$key});
		}
	}

	return \%form;
}


sub filter_param {
	my($key, $data) = @_;

	# Paranoia - Clean out any embedded NULs. -- cbwood
	# hm.  NULs in a param() value means multiple values
	# for that item.  do we use that anywhere? -- pudge
	$data =~ s/\0//g;

	# clean up numbers
	if (exists $nums{$key}) {
		$data = fixint($data);
	} elsif (exists $alphas{$key}) {
		$data =~ s|[^a-zA-Z0-9_]+||g;
	} elsif (exists $special{$key}) {
		$special{$key}->($data);
	} else {
		for my $ri (@regints) {
			$data = fixint($data) if /$ri/;
		}
	}

	return $data;
}
} # see lexical variables above

########################################################
sub _testExStr {
	local($_) = @_;
	$_ .= "'" unless m/'$/;
	return $_;
}

########################################################
# fix parameter input that should be integers
sub fixint {
	my($int) = @_;
# allow + ... should be OK ... ?  -- pudge
# 	$int =~ s/^\+//;
# 	$int =~ s/^(-?[\d.]+).*$/$1/s or return;
	$int =~ s/^([+-]?[\d.]+).*$/$1/s or return;
	return $int;
}


#========================================================================

=head2 setUserDate(USER)

Sets some date information for the user, including date format, time zone,
and time zone offset from GMT.  This is a separate function because the
logic is a bit complex, and it needs to happen in two different places:
anonymous coward creation in the httpd creation, and each time a user is
prepared.

=over 4

=item Parameters

=over 4

=item USER

The user hash reference.

=back

=item Return value

None.

=back

=cut

sub setUserDate {
	my($user) = @_;
	my $slashdb = getCurrentDB();

	my $dateformats   = $slashdb->getDescriptions('datecodes');
	$user->{'format'} = $dateformats->{ $user->{dfid} };

	my $timezones     = $slashdb->getTZCodes;
	my $tz            = $timezones->{ $user->{tzcode} };
	$user->{off_set}  = $tz->{off_set};  # we need for calculation

	my $is_dst = 0;
	if ($user->{dst} && $user->{dst} eq "on") {  # manual on ("on")
		$is_dst = 1;

	} elsif (!$user->{dst}) { # automatic (calculate on/off) ("")
		$is_dst = isDST($tz->{dst_region}, $user);

	} # manual off ("off")

	if ($is_dst) {
		# if tz has no dst_off_set, default to base off_set + 3600 (one hour)
		$user->{off_set}     = defined $tz->{dst_off_set}
			? $tz->{dst_off_set}
			: ($tz->{off_set} + 3600);

		# if tz no dst_tz, fake a new tzcode by appending ' (D)'
		# (tzcode is rarely used, this shouldn't matter much)
		$user->{tzcode_orig} = $user->{tzcode};
		$user->{tzcode}      = defined $tz->{dst_tz}
			? $tz->{dst_tz}
			: ($user->{tzcode} . ' (D)');
	} else {
		$user->{off_set}     = $tz->{off_set};
	}
}

#========================================================================

=head2 isDST(REGION [, USER, TIME, OFFSET])

Returns boolean for whether given time, for given user, is in Daylight
Savings Time.

=over 4

=item Parameters

=over 4

=item REGION

The name of the current DST region (e.g., America, Europe, Australia).
It must match the C<region> column of the C<dst> table.

=item USER

You will get better results if you pass in the USER, but it is optional.

=item TIME

Time in seconds since beginning of epoch, in GMT (which is the default
for Unix).  Optional; default is current time if undefined.

=item OFFSET

Offset of current timezone in seconds from GMT.  Optional; default is
current user's C<off_set> if undefined.

=back

=item Return value

Boolean for whether we are currently in DST.

=back

=cut

{
my %last = (
	1	=> 28, # yes, i know, February may have 29 days; but barely worth fixing
	2	=> 31, # barely worth fixing, since we don't even currently have
	3	=> 30, # a DST region that uses the end of February, though some
	8	=> 30, # do exist -- pudge
	9	=> 31,
	10	=> 30,
);

# we don't bother trying to figure out exact offset for calculations,
# since that is what we are changing!  if we are off by an hour per year,
# oh well, unless someone has a solution.

sub isDST {
	my($region, $user, $unixtime, $off_set) = @_;

	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	$user     ||= getCurrentUser();
	my $regions = $reader->getDSTRegions;

	return 0 unless $region;
	my $start = $regions->{$region}{start} or return 0;
	my $end   = $regions->{$region}{end}   or return 0;

	$unixtime = time unless defined $unixtime;
	$off_set  = $user->{off_set} unless defined $off_set;

	my($hour, $mday, $month, $wday) = (gmtime($unixtime + $off_set))[2,3,4,6];


	# if we are outside the monthly boundaries, the calculations is easy
	# assume start and end months are different
	if ($start->[DST_MON] < $end->[DST_MON]) { # up over
		return 1 if $month > $start->[DST_MON]  &&  $month < $end->[DST_MON];
		return 0 if $month < $start->[DST_MON]  ||  $month > $end->[DST_MON];

	} else { # down under
		return 1 if $month > $start->[DST_MON]  ||  $month < $end->[DST_MON];
		return 0 if $month < $start->[DST_MON]  &&  $month > $end->[DST_MON];
	}

	# assume, by now, that current month contains either start or end date
	for my $mon ($start, $end) {
		if ($month == $mon->[DST_MON]) {
			my($max_day, $switch_day);

			# 1st, 2d, 3d ${foo}day of month
			if ($mon->[DST_NUM] > 0) {
				$max_day = ($mon->[DST_NUM] * 7) - 1;
			# last, second-to-last $fooday of month
			} else { # assume != 0
				$max_day = $last{$month} - ((abs($mon->[DST_NUM]) - 1) * 7);
			}

			# figure out the day we switch
			$switch_day = $mday - ($wday - $start->[DST_DAY]);

			$switch_day += 7 while $switch_day < $max_day;
			$switch_day -= 7 while $switch_day > $max_day;

			my($v1, $v2) = (1, 0);
			# start/end are the same, except for the reversed values here
			($v1, $v2) = ($v2, $v1) if $month == $end->[DST_MON];

			return $v1 if	$mday >  $switch_day;
			return $v1 if	$mday == $switch_day
					&& $hour >= $start->[DST_HR];
			return $v2;
		}
	}
	return 0; # we shouldn't ever get here, but if we do, assume not in DST
}
}

#========================================================================

=head2 getObject(CLASS_NAME [, VIRTUAL_USER, ARGS])
=head2 getObject(CLASS_NAME [, OPTIONS, ARGS])

Returns a object in CLASS_NAME, using the new() constructor.  It passes
VIRTUAL_USER and ARGS to it, and then caches it by CLASS_NAME and VIRTUAL_USER.
If the object for that CLASS_NAME/VIRTUAL_USER exists the second time through,
it will just return, without reinitializing (even if different ARGS are passed,
so don't do that; see "nocache" option).

In the second form, OPTIONS is a hashref.

=over 4

=item Parameters

=over 4

=item CLASS_NAME

A class name to use in creating a object.  Only [\w:] characters are allowed.

=item VIRTUAL_USER

Optional; will default to main Virtual User for site if not supplied.
Passed as second argument to the new() constructor (after class name).

=item OPTIONS

Optional; several options are currently recognized.

=over 4

=item virtual_user

String.  This is handled the same was as the first form, as though using
VIRTUAL_USER, but allows for passing other options too.  Overrides "db_type"
option.

=item db_type

String.  There are types of DBs (reader, writer, search, log), and there may be more
than one DB of each type.  By passing a db_type instead of a virtual_user, you
request any DB of that ype, instead of a specific DB.

If neither "virtual_user" or "db_type" is passed, then the function will do a
lookup of the class for what type of DB handle it wants, and then pick one
DB at random that is of that type.

=item nocache

Boolean.  Get a new object, not a cached one.  Also won't cache the resulting object
for future calls.

=back


=item ARGS

Any other arguments to be passed to the object's constructor.

=back

=item Return value

An object, unless object cannot be gotten; then undef.

=back

=cut

sub getObject {
	my($class, $data, @args) = @_;
	my($vuser, $cfg, $objects);
	my $user = getCurrentUser();

	# clean up dangerous characters
	$class =~ s/[^\w:]+//g;

	# only if passed a hash, or no passed data at all
	if (!$data || ref $data eq 'HASH') {
		$data ||= {};
		if ($data->{virtual_user}) {
			$vuser = $data->{virtual_user};

		} else {
			my $classes = getCurrentStatic('classes');

			# try passed db first, then db for given class
			my $db_type  = $data->{db_type}  || $classes->{$class}{db_type};
			my $fallback = $data->{fallback} || $classes->{$class}{fallback};

			$vuser = ($db_type  && $user->{state}{dbs}{$db_type})
			      || ($fallback && $user->{state}{dbs}{$fallback});

			return undef if $db_type && $fallback && !$vuser;
		}
	}

	# if plain string, use it as vuser
	elsif (!ref $data) {
		$data = { virtual_user => $data };
		$vuser = $data->{virtual_user};
	}

	# in the future, we may default to something else, but for now it is the writer
	$vuser ||= $user->{state}{dbs}{writer} || getCurrentVirtualUser();
	return undef unless $vuser && $class;

	if ($ENV{GATEWAY_INTERFACE} && (my $r = Apache->request)) {
		$cfg     = Apache::ModuleConfig->get($r, 'Slash::Apache');
		$objects = $cfg->{'objects'} ||= {};
	} else {
		$objects = $static_objects   ||= {};
	}

	if (!$data->{nocache} && $objects->{$class, $vuser}) {
		# we've been here before, and it didn't work last time ...
		# what, you think you can try it again and it will work
		# magically this time?  you think you're better than me?
		if ($objects->{$class, $vuser} eq 'NA') {
			return undef;
		} else {
			return $objects->{$class, $vuser};
		}

	} else {
		# see if module has been loaded in already ...
		(my $file = $class) =~ s|::|/|g;
		# ... because i really hate eval
		local $@; # $@ won't get cleared unless eval is performed
		eval "require $class" unless exists $INC{"$file.pm"};

		if ($@) {
			errorLog($@);
		} elsif (!$class->can("new")) {
			errorLog("Class $class is not returning an object.  Try " .
				"`perl -M$class -le '$class->new'` to see why.\n");
		} else {
			my $object = $class->new($vuser, @args);
			if ($object) {
				$objects->{$class, $vuser} = $object if !$data->{nocache};
				return $object;
			}
		}

		$objects->{$class, $vuser} = 'NA' if !$data->{nocache};
		return undef;
	}
}

#========================================================================

=head2 errorLog()

Generates an error that either goes to Apache's error log
or to STDERR. The error consists of the package and
and filename the error was generated and the same information
on the previous caller.

=over 4

=item Return value

Returns 0;

=back

=cut

sub errorLog {
	return if $Slash::Utility::NO_ERROR_LOG;

	my $level = 1;
	$level++ while (caller($level))[3] =~ /log/i;  # ignore other logging subs

	my(@errors, $package, $filename, $line);

	($package, $filename, $line) = caller($level++);
	push @errors, ":$package:$filename:$line:@_";
	($package, $filename, $line) = caller($level++);
	push @errors, "Which was called by:$package:$filename:$line:@_" if $package;

	if ($ENV{GATEWAY_INTERFACE} && (my $r = Apache->request)) {
		$errors[0] = $ENV{SCRIPT_NAME} . $errors[0];
		$errors[-1] .= "\n";
		$r->log_error($_) for @errors;
	} else {
		$errors[0] = 'Error' . $errors[0];
		print STDERR $_, "\n" for @errors;
	}

	return 0;
}

#========================================================================

=head2 writeLog(DATA)

Places optional data in the accesslog.

=over 4

=item Parameters

=over 4

=item DATA

Strings that are concatenated together to be used in the SLASH_LOG_DATA field.

=back

=item Return value

No value is returned.

=back

=cut

sub writeLog {
	return unless $ENV{GATEWAY_INTERFACE};
	my $dat = join("\t", @_);

	my $r = Apache->request;

	# Notes has a bug (still in apache 1.3.17 at
	# last look). Apache's directory sub handler
	# is not copying notes. Bad Apache!
	# -Brian
	$r->err_header_out(SLASH_LOG_DATA => $dat);
}

sub createLog {
	my($uri, $dat, $status) = @_;
	my $constants = getCurrentStatic();

	# At this point, if we have short-circuited the
	# "PerlAccessHandler  Slash::Apache::User"
	# by returning an apache code like DONE before that processing
	# could take place (which currently happens in Banlist.pm), then
	# prepareUser() has not been called, thus the $user->{state}{dbs}
	# table is not set up.  So to make sure we write to the proper
	# logging DB (assuming there is one), we have to use the old-style
	# arguments to getObject(), instead of passing in {db_type=>'log'}.
	# - Jamie 2003/05/25
	my $logdb = getObject('Slash::DB', { virtual_user => $constants->{log_db_user} });

	my $page = qr|\d{2}/\d{2}/\d{2}/\d{4,7}|;

	if ($status == 302) {
		# See mod_relocate -Brian
		if ($uri =~ /\.relo$/) {
			my $apr = Apache::Request->new(Apache->request);
			$dat = $apr->param('_URL');
			$uri = 'relocate';
		} else  {
			$dat = $uri;
			$uri = 'relocate-undef';
		}
	} elsif ($status == 404) {
		$dat = $uri;
		$uri = 'not found';
	} elsif ($uri =~ /^\/palm/) {
		($dat = $ENV{REQUEST_URI}) =~ s|\.shtml$||;
		$uri = 'palm';
	} elsif ($uri eq '/') {
		$uri = 'index';
	} elsif ($uri =~ /\.ico$/) {
		$uri = 'image';
	} elsif ($uri =~ /\.jpg$/) {
		$uri = 'image';
	} elsif ($uri =~ /\.jpeg$/) {
		$uri = 'image';
	} elsif ($uri =~ /\.gif$/) {
		$uri = 'image';
	} elsif ($uri =~ /\.tiff$/) {
		$uri = 'image';
	} elsif ($uri =~ /\.pl$/) {
		$uri =~ s|^/(.*)\.pl$|$1|;
	# This is for me, I am getting tired of patching my local copy -Brian
	} elsif ($uri =~ /\.tar\.gz$/) {
		$uri =~ s|^/(.*)\.tar\.gz$|$1|;
	} elsif ($uri =~ /\.rpm$/) {
		$uri =~ s|^/(.*)\.rpm$|$1|;
	} elsif ($uri =~ /\.dmg$/) {
		$uri =~ s|^/(.*)\.dmg$|$1|;
	} elsif ($uri =~ /\.rss$/ || $uri =~ /\.xml$/ || $uri =~ /\.rdf$/) {
		$uri = 'rss';
	} elsif ($uri =~ /\.shtml$/) {
		$uri =~ s|^/(.*)\.shtml$|$1|;
		$dat = $uri if $uri =~ $page;	
		$uri =~ s|^/?(\w+)/?(.*)|$1|;
		my $suspected_handler = $2;
		my $SECT;
		my $reader = getObject('Slash::DB', { db_type => 'reader' });
		if ($SECT = $reader->getSection($uri) ) {
			my $handler = $SECT->{index_handler};
			$handler =~ s|^(.*)\.pl$|$1|;
			if ($handler eq $suspected_handler) {
				$uri = $handler;
			}
		}
	} elsif ($uri =~ /\.html$/) {
		$uri =~ s|^/(.*)\.html$|$1|;
		$dat = $uri if $uri =~ $page;	
		$uri =~ s|^/?(\w+)/?.*|$1|;
	}
	$logdb->createAccessLog($uri, $dat, $status);
	if (getCurrentUser('is_admin')) {
		$logdb->createAccessLogAdmin($uri, $dat, $status);
	}
}

#========================================================================

=head2 createEnvironment([VIRTUAL_USER])

Places data into the request records notes table. The two keys
it uses are SLASH_LOG_OPERATION and SLASH_LOG_DATA.

=over 4

=item Parameters

=over 4

=item VIRTUAL_USER

Optional.  You can pass in a virtual user that will be used instead of
parsing C<@ARGV>.

=back

=item Return value

No value is returned.

=back

=cut

sub createEnvironment {
	return if $ENV{GATEWAY_INTERFACE};
	my($virtual_user) = @_;
	my %form;
	unless ($virtual_user) {
		while (my $pair = shift @ARGV) {
			my($key, $val) = split /=/, $pair;
			# stop processing if key=val stops, and put last arg back on
			unshift(@ARGV, $pair), last if ! defined $val;
			$form{$key} = $val;
		}
		$virtual_user = $form{'virtual_user'};
	}

	createCurrentVirtualUser($virtual_user);
	createCurrentForm(filter_params(\%form));

	my $slashdb = Slash::DB->new($virtual_user);
	my $constants = $slashdb->getSlashConf();
	my $site_constants;
	my $sections = $slashdb->getSections();
	for (values %$sections) {
		if ($_->{hostname} && $_->{url}) {
			my $new_cfg;
			for (keys %{$constants}) {
				$new_cfg->{$_} = $constants->{$_}
					unless $_ eq 'form_override';
			}
			# Must not just copy the form_override info
			$new_cfg->{form_override} = {}; 
			$new_cfg->{absolutedir} = $_->{url};
			$new_cfg->{rootdir} = $_->{url};
			$new_cfg->{cookiedomain} = $_->{cookiedomain} if $_->{cookiedomain};
			$new_cfg->{defaultsubsection} = $_->{defaultsubsection} if $_->{defaultsubsection};
			$new_cfg->{defaulttopic} = $_->{defaulttopic} if $_->{defaulttopic};
			$new_cfg->{defaultdisplaystatus} = $_->{defaultdisplaystatus} if $_->{defaultdisplaystatus};
			$new_cfg->{defaultcommentstatus} = $_->{defaultcommentstatus} if $_->{defaultcommentstatus};
			$new_cfg->{defaultsection} = $_->{defaultsection} || $_->{section};
			$new_cfg->{section} = $_->{section};
			$new_cfg->{basedomain} = $_->{hostname};
			$new_cfg->{static_section} = $_->{section};
			$new_cfg->{index_handler} = $_->{index_handler};
			$site_constants->{$_->{hostname}} = $new_cfg;
		}
	}
	my $form = getCurrentForm();

	# If this is a sectional site, we need to set our hostname if one exists.
	my $hostname = $slashdb->getSection($form->{section}, 'hostname') || "";
	createCurrentHostname($hostname);

	# We assume that the user for scripts is the anonymous user
	createCurrentDB($slashdb);
	createCurrentStatic($constants, $site_constants);

	$ENV{SLASH_USER} = $constants->{anonymous_coward_uid};
	my $user = prepareUser($constants->{anonymous_coward_uid}, $form, $0);
	createCurrentUser($user);
	createCurrentAnonymousCoward($user);
}

#========================================================================
{my @prof;
sub slashProf {
	return unless getCurrentStatic('use_profiling');
	my($begin, $end) = @_;
	$begin ||= '';
	$end   ||= '';
	push @prof, [ Time::HiRes::time(), (caller(0))[0, 1, 2, 3], $begin, $end ];
}

sub slashProfInit {
	return unless getCurrentStatic('use_profiling');
	@prof = ();
}

sub slashProfEnd {
	my $use_profiling = getCurrentStatic('use_profiling');
	return unless $use_profiling;
	return unless @prof;

	my $first = $prof[0][0];
	my $last  = $first;  # Matthew 20:16
	my $end   = $prof[-1][0];
	my $total = ($end - $first) * 1_000;

	$total ||= $first || $end || 1;  # just in case

	print STDERR "\n*** Begin profiling ($$)\n";
	print STDERR "*** Begin ordered ($$)\n";
	printf STDERR <<'EOT', "PID", "what", "this #", "pct", "tot. #", "pct";
%-6.6s: %-64.64s % 6.6s ms (%6.6s%%) / % 6.6s ms (%6.6s%%)
EOT

	my(%totals, %begin);
	for my $prof (@prof) {
		my $t1 = ($prof->[0] - $first) * 1_000;
		my $t2 = ($prof->[0] - $last) * 1_000;
		my $p1 = $t1 / $total * 100;
		my $p2 = $t2 / $total * 100;
		my $s1 = sprintf('%.2f', $p1);
		my $s2 = sprintf('%.2f', $p2);
		$last = $prof->[0];

		# either use passed tag(s), or package/line number
		my $where;
		if ($prof->[6]) {
			$where = "$prof->[6] end";
		}

		if ($prof->[5]) {
			$where .= '; ' if $where;
			$where .= "$prof->[5] begin";
		}
		
		$where ||= sprintf('%56s:%d:', @{$prof}[1, 3]);
		$where =~ s/[\t\r\n]/ /g;
		$where =~ s/^ +//;
		$where =~ s/ +$//;

		# if we know what this is the end of, we want that;
		# if no begin or end, use that; else, punt
		if ($prof->[6] && defined $begin{$prof->[6]}) {
			$totals{$prof->[6]} += $t1 - $begin{$prof->[6]};
			delete $begin{$prof->[6]};
		} elsif (!$prof->[5] && !$prof->[6]) {
			$totals{$where} += $t2;
		}

		# only take away if an end of something
		# (note: assume nested)
		if ($prof->[6]) {
			for (keys %begin) {
				$begin{$_} += $t2 unless $_ eq $prof->[5];
			}
		}

		# mark new beginning
		$begin{$prof->[5]} = $t1 if $prof->[5];

		printf STDERR <<'EOT', $$, $where, $t2, $s2, $t1, $s1 if $use_profiling > 1;
%-6d: %-64.64s % 6d ms (%6.6s%%) / % 6d ms (%6.6s%%)
EOT
	}

	print STDERR "\n*** Begin summary ($$)\n";
	printf STDERR <<'EOT', "PID", "what", "time", "pct";
%-6.6s: %-64.64s % 6.6s ms (%6.6s%%)
EOT
	for (sort { $totals{$b} <=> $totals{$a} } keys %totals) {
		my $p = $totals{$_} / $total * 100;
		my $s = sprintf('%.2f', $p);
		printf STDERR <<'EOT', $$, $_, $totals{$_}, $s;
%-6d: %-64.64s % 6d ms (%6.6s%%)
EOT
	}


	print STDERR "*** End profiling ($$)\n\n";

	@prof = ();
}
}

######################################################################
# Quick intro -Brian
sub getCurrentCache {
	my($value) = @_;
	my $cache;

	if ($ENV{GATEWAY_INTERFACE} && (my $r = Apache->request)) {
		my $cfg = Apache::ModuleConfig->get($r, 'Slash::Apache');
		$cache = $cfg->{'cache'} ||= {};
	} else {
		$cache = $static_cache   ||= {};
	}

	# i think we want to test defined($foo), not just $foo, right?
	if ($value) {
		return defined($cache->{$value})
			? $cache->{$value}
			: undef;
	} else {
		return $cache;
	}
}

1;

__END__


=head1 SEE ALSO

Slash(3), Slash::Utility(3).

=head1 VERSION

$Id$
