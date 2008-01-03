package Slash::LDAPDB;

use 5.008004;
use strict;
use warnings;
use Carp;
use Net::LDAP;
use Net::LDAP::Constant qw(LDAP_TIMEOUT);
use Digest::MD5 'md5_hex';
use Data::Dumper;
use Slash::Utility;
use Slash::Utility::Environment;
require Exporter;

our @ISA = qw(Exporter);

# This allows declaration	use Slash::LDAPDB ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '0.01';


# Preloaded methods go here.

our %PREFIX_KEY;
@PREFIX_KEY{qw(UidNumber Passwd Email Realname)} = ();
our %keymap_s2l;
our %keymap_l2s;

our $DEBUG_LEVEL = 5;

sub new {
    my $class = shift;
    my $constants = __getCurrentStatic();
    my $self  = { bind_dn => $constants->{ldap_bind_dn}, # anonymous if empty
		  bind_passwd => $constants->{ldap_bind_passwd},
		  attrib_prefix => $constants->{ldap_attrib_prefix},
		  host => $constants->{ldap_server},
		  base_dn => $constants->{ldap_base_dn},
		  timeout => 10,
		  _disabled => $constants->{ldap_enable} ? 0 : "by init arg",
		  @_ };
    bless $self, $class;

    our %keymap_s2l = (uid => 'UidNumber', passwd => $constants->{ldap_attrib_prefix}.'Passwd', nickname => 'displayName',
		       matchname => 'cn',  realname => $constants->{ldap_attrib_prefix}.'Realname', realemail => $constants->{ldap_attrib_prefix}.'Email'
		      );
    @keymap_l2s{@keymap_s2l{keys(%keymap_s2l)}} = keys(%keymap_s2l); # make reverse map

    $DEBUG_LEVEL = $constants->{ldap_debug_level} || $DEBUG_LEVEL;

    if (!$self->{_disabled} &&
	!($self->{_ldap} = Net::LDAP->new($self->{host}, timeout => $self->{timeout}))){
	__debug(1, "LDAP: can't create LDAP object $@");
	$self->{_disabled} = "LDAP object create fail: $@";
    }
    return $self;
}

sub bind {
    my $self = shift;
    $self->_check_disabled and return undef;
    return 1 if defined $self->{_bind_p};
    $self->{_bind_p} = 1;
    my @args = ();
    if ( $self->{bind_dn} ) {
	push @args, $self->{bind_dn}, password => $self->{bind_passwd};
    }
    __debug(8, "LDAP: trying bind as '$self->{bind_dn}'");
    my $mesg = $self->_timeout(sub{ $self->{_ldap}->bind(@args) });
    if ($mesg->code) {
	__debug(1, "LDAP bind error: ". $mesg->error);
	$self->{_disabled} = "bind error: " . $mesg->error;
    }
    !$mesg->code;
}

sub authUser {
    my $self = shift;
    my $matchname = shift;
    my $pass = shift;
    __debug(8, "LDAP::authUser: start auth for $matchname");
    $self->_check_disabled and return undef;
    my $userinfo = $self->getUser($matchname);

    if ($userinfo->{passwd} eq md5_hex($pass)) {
	__debug(6, "LDAP::authUser auth success for $matchname");
	return $userinfo->{uid};
    }
    __debug(5, "LDAP::authUser auth fail for $matchname");
    0;
}

sub createUser {
    my $self = shift;
    my $user = shift;
    my $val  = shift;
    __debug(8, "LDAP::createUser called for user '$user'");
    __debug(9, "LDAP::createUser called with ". Data::Dumper->Dump([$val], [qw($val)]));
    $self->_check_disabled and return undef;
    $val->{matchname} = $user;

    unless ($self->getUser($val->{matchname})) {
        __debug(6, "LDAP::createUser no LDAP entry for '$val->{matchname}'. careating...");
        my $mesg = $self->_timeout(sub {
				   $self->{_ldap}->add("cn=$val->{matchname},".$self->{base_dn},
				        attr => [objectClass => "InetOrgPerson",
				                 sn => "(dummy)",
						 displayName => $val->{$keymap_l2s{displayName}},
					         cn => $val->{matchname}])
				   });
        if ($mesg->code) {
	    __debug(2, "LDAP Error when createUser add entry: ". $mesg->error);
	    return undef;
	}
    }

    my %attr = (objectClass => $self->{attrib_prefix}."UserInfo");
    foreach my $slash_key (keys(%keymap_s2l)) {
	next unless exists $val->{$slash_key};
	next unless exists($PREFIX_KEY{$keymap_s2l{$slash_key}});
	$attr{$self->{attrib_prefix}.$keymap_s2l{$slash_key}}
	    = $val->{$slash_key};
    }

    $self->bind;
    my $mesg = $self->_timeout(sub {
			       $self->{_ldap}->modify("cn=$val->{matchname},".$self->{base_dn},
						     add => \%attr) });
    $mesg->code && __debug(2, "LDAP Error when createUser: ". $mesg->error);
    !$mesg->code;
}

sub deleteUserByUid {
    my $self = shift;
    my $uid  = shift;
    __debug(8, "LDAP::deleteUser called for uid '$uid'");
    $self->_check_disabled and return undef;
    my $userent = $self->getUserByUid($uid);
    $userent && $self->deleteUser($userent->{matchname});
}

sub deleteUser {
    my $self = shift;
    my $user = shift;
    __debug(8, "LDAP::deleteUser called for user '$user'");
    $self->_check_disabled and return undef;

    my $entry = $self->_get_userent("(cn=$user)");
    my $mesg;
    if (grep(/otpUserInfo/, $entry->get_value('objectClass'))) {
      __debug(8, "LDAP::deleteUser: User $user is also OTP's. The LDAP entry is only modified.");
      $self->_timeout(sub { $self->{_ldap}->modify("cn=$user,$self->{base_dn}", delete => [qw(slashdotRealname)])});
      $mesg = $self->_timeout(sub { $self->{_ldap}->modify("cn=$user,$self->{base_dn}",
							   changes => [
								       delete => [slashdotUidNumber => []],
								       delete => [slashdotPasswd => []],
								       delete => [slashdotEmail => []],
								       delete => [objectClass => 'slashdotUserInfo']
								      ]) });
    } else {
      $mesg = $self->_timeout(sub { $self->{_ldap}->delete("cn=${user},".$self->{base_dn}) });
    }
    $mesg->code && __debug(3, "LDAP Error when deleteUser: ". $mesg->error);
    !$mesg->code;
}

sub setUser() {
    my $self = shift;
    my $user = shift;
    my $val  = shift;
    __debug(8, "LDAP::setUser called for user '$user'");
    __debug(9, "LDAP::setUser called with ". Data::Dumper->Dump([$val], [qw($val)]));
    $self->_check_disabled and return undef;
    my $changes = $self->_s2lop($val);
    return -1 unless @$changes;

    __debug(9, "LDAP::setUser ".Data::Dumper->Dump([$changes], [qw($changes)]));

    $self->bind;
    my $mesg = $self->_timeout(sub { $self->{_ldap}->modify("cn=$user,$self->{base_dn}",
							    changes => $changes) });
    $mesg->code && __debug(3, "LDAP Error when setUser: ". $mesg->error);
    !$mesg->code;
}

sub setUserByUid() {
    my $self = shift;
    my $uid  = shift;
    my $val  = shift;
    __debug(8, "LDAP::setUserByUid called for uid '$uid'");
    __debug(9, "LDAP::setUserByUid called with ". Data::Dumper->Dump([$val], [qw($val)]));
    $self->_check_disabled and return undef;
    my $changes = $self->_s2lop($val);
    return -1 unless @$changes;

    my $userent = $self->getUserByUid($uid) or return undef;

    $self->setUser($userent->{matchname}, $val);
}

sub getUser() {
    my $self = shift;
    my $user = shift;
    $self->_check_disabled and return undef;
    my $entry = $self->_get_userent("(cn=$user)");
    unless ($entry) {
	__debug(5, "LDAP::getUser: Can't find user cn=$user");
	return undef;
    }
    $self->_le2s($entry)
}

sub getUserByUid() {
    my $self = shift;
    my $uid  = shift;
    $self->_check_disabled and return undef;
    my $entry = $self->_get_userent("($self->{attrib_prefix}UidNumber=$uid)");
    unless ($entry) {
	__debug(5, "LDAP::getUser: Can't find user uid=$uid");
	return undef;
    }
    $self->_le2s($entry)
}

sub _get_userent {
    my $self   = shift;
    my $filter = shift;
    my $opt    = {uniq => 1, @_};

    $self->bind;
    my $mesg = $self->_timeout(sub {$self->{_ldap}->search(base => $self->{base_dn},
							   filter => $filter) });
    if ($mesg->code) {
	__debug(3, "LDAP Error when getting user entry: ". $mesg->error);
	return undef;
    }
    if ($opt->{uniq} && $mesg->count > 1) {
	__debug(3, "LDAP: got multiple entries with '$filter'. Abort!");
	return undef;
    }
    if ($mesg->count == 0) {
	__debug(6, "LDAP: user entry not found for '$filter'.");
	return undef;
    }
    $mesg->entry(0);
}

# convert LDAP Entry to slash style hash
sub _le2s {
    my $self  = shift;
    my $entry = shift;
    my $ret   = {};
    foreach my $k (keys(%keymap_l2s)){
	my $val = $entry->get_value((exists $PREFIX_KEY{$k}
				 ? $self->{attrib_prefix}.$k
				 : $k));
	$ret->{$keymap_l2s{$k}} = $val if defined($val);
    }
    $ret;
}

# convert slash hash to LDAP operation
sub _s2lop {
    my $self    = shift;
    my $val     = shift;
    my @delete  = ();
    my @replace = ();
    my @changes = ();
    foreach my $k (keys(%$val)){
	next unless exists $keymap_s2l{$k};
	my $ldap_key = $keymap_s2l{$k};
	$ldap_key = $self->{attrib_prefix} . $ldap_key if exists $PREFIX_KEY{$ldap_key};
	if ($ldap_key eq 'cn' || $ldap_key eq 'displayName') {
	    __debug(7, "Can't change cn(matchname) or displayName(nickname). skip!");
	    next
	}

	if (defined($val->{$k}) && $val->{$k} ne '') {
	    push @replace, $ldap_key => $val->{$k};
	} else {
	    push @delete, $ldap_key => [];
	}
    }
    #push @changes, delete => \@delete if @delete;
    push @changes, replace => \@delete if @delete;
    push @changes, replace => \@replace if @replace;
    \@changes;
}

sub unbind {
    shift->{_ldap}->unbind
}

sub _timeout {
    my $self = shift;
    my $proc = shift;
    my $mesg;
    eval {
	local $SIG{ALRM} = sub { die "__generic_timeout\n" };
	alarm($self->{timeout});
	$mesg = $proc->();
	alarm(0);
    };
    if ($@) { __debug(8, "Died in timeout eval block: $@"); }
    if ($@ eq "__generic_timeout\n") {
	$mesg = Slash::LDAPDB::DummyMessage->new(code  => LDAP_TIMEOUT,
			error => Carp::longmess("Generic Timeout in Operation"));
    } elsif ($@) {
	croak $@;
    }
    return $mesg;
}

sub __debug {
    (shift) <= $DEBUG_LEVEL && errorLog(@_);
}

sub __getCurrentStatic {
    Slash::Utility::Environment::getCurrentStatic();
}

sub _check_disabled {
    my $self = shift;
    $self->{_disabled} and
	__debug(1, "Slash::LDAP has been disabled: ($self->{_disabled})");
    $self->{_disabled};
}

{
    package Slash::LDAPDB::DummyMessage;
    sub new {
	my $class = shift;
	bless {@_}, $class
    }
    sub code { shift->{code} }
    sub error { shift->{error} }
}


1;
__END__
# Below is stub documentation for your module. You'd better edit it!
