use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
# $Id: Makefile.PL,v 1.1 2006/06/19 23:37:30 jamiemccarthy Exp $
WriteMakefile(
    'NAME'	=> 'Slash::Tagbox::Top',
    'VERSION_FROM' => 'Top.pm', # finds $VERSION
    'PM'	=> { 'Top.pm' =>   '$(INST_LIBDIR)/Top.pm' },
);
