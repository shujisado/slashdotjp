use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
# $Id: Makefile.PL,v 1.1 2007/11/01 20:35:18 jamiemccarthy Exp $
WriteMakefile(
    'NAME'	=> 'Slash::Tagbox::Despam',
    'VERSION_FROM' => 'Despam.pm', # finds $VERSION
    'PM'	=> { 'Despam.pm' =>   '$(INST_LIBDIR)/Despam.pm' },
);
