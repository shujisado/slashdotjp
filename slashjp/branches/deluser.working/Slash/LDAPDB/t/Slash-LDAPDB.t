# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Slash-LDAPDB.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 6;
BEGIN { use_ok('Slash::LDAPDB') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.


package Slash::LDAPDB;
    sub __getCurrentStatic {
	# DUMMY
	{
	    ldap_base_dn => "ou=people,dc=osdn,dc=jp",
	    ldap_bind_dn => "",
	    ldap_bind_dn => "cn=admin,dc=osdn,dc=jp",
	    ldap_bind_passwd => 'dztUrsI',
            ldap_attrib_prefix => "slash",
	    ldap_server => "192.168.51.72",
        }
    }

    sub errorLog {
	print STDERR @_, "\n";
    }

package main;

    use Data::Dumper;

    $DEBUG_LEVEL = 9;

    my $ldap = Slash::LDAPDB->new();

    cmp_ok($ldap->authUser("sugi0001", "sugitest"), '==', 30989, 'auth');

    my $userinfo = $ldap->getUser("sugi0001");
    #print Dumper($userinfo);
    ok(defined($userinfo), 'userinfo');
    ok($userinfo->{nickname} eq 'sugi_0001', 'userinfo - nick');
    cmp_ok($ldap->authUser("sugi0001", "sugitest"), '==', 30989, 'auth');

    is_deeply($ldap->getUser("sugi0001"),
	      $ldap->getUserByUid(30989),
	      'cmp getUser and getUserByUid');

    ok($ldap->setUser("sugi0001", {realname => "moge"}), 'setUser');
    cmp_ok($ldap->getUser("sugi0001")->{realname}, 'eq', "moge",
	   'setUser - check');

    $ldap->setUser("sugi0001", {realname => "sugi_0001"}); # revert

    ok($ldap->setUser("sugi0001", {realemail => ""}),
       'setUser (delete)');
    cmp_ok($ldap->getUser("sugi0001")->{realemail}, 'eq', '',
	   'setUser (delete) - check');


    ok($ldap->setUser("sugi0001", {realemail => 'moge@example.com'}),
       'setUser (new key)');
    cmp_ok($ldap->getUser("sugi0001")->{realemail}, 'eq', 'moge@example.com',
	   'setUser (new key) - check');


    cmp_ok($ldap->setUser("sugi0001", {unknownkey => "moge"}), '==', 1*-1,
	   'setUser (null update)');

    ok($ldap->createUser("usernick0001",
			 { nickname => "user-nick0001",
			   realname => "REAL!",
			   passwd => "passwoooord",
			   uid => 123123123}), 'createUser');

    ok($ldap->getUser("usernick0001"), 'createUser - check');
    cmp_ok($ldap->getUser("usernick0001")->{nickname}, 'eq', 'user-nick0001',
	   'createUser - check attrib');


    ok($ldap->setUserByUid(123123123, {realemail => 'foo@example.com'}),
       'setUserByUid');
    cmp_ok($ldap->getUser("usernick0001")->{realemail}, 'eq', 'foo@example.com',
	   'setUserByUid - check');

    ok($ldap->deleteUser("usernick0001"), 'deleteUser');
    ok(!defined($ldap->getUser("usernick0001")), 'deleteUser - check');
}


1;
__END__
# Below is stub documentation for your module. You'd better edit it!
