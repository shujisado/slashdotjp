# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id: Console.pm,v 1.2 2006/02/22 00:14:56 pudge Exp $

package Slash::Console;

=head1 NAME

Slash::Console - Perl extension for Console


=head1 SYNOPSIS

	use Slash::Console;


=head1 DESCRIPTION

LONG DESCRIPTION.


=head1 EXPORTED FUNCTIONS

=cut

use strict;
use DBIx::Password;
use Slash;
use Slash::Display;
use Slash::Utility;

use base 'Slash::DB::Utility';
use base 'Slash::DB::MySQL';
use vars qw($VERSION);

($VERSION) = ' $Revision: 1.2 $ ' =~ /\$Revision:\s+([^\s]+)/;

1;

__END__


=head1 SEE ALSO

Slash(3).

=head1 VERSION

$Id: Console.pm,v 1.2 2006/02/22 00:14:56 pudge Exp $
