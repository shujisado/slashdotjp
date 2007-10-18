use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
# $Id: Makefile.PL,v 1.1 2006/09/27 02:07:59 jamiemccarthy Exp $
WriteMakefile(
    'NAME'	=> 'Slash::Tagbox::FHActivity',
    'VERSION_FROM' => 'FHActivity.pm', # finds $VERSION
    'PM'	=> { 'FHActivity.pm' =>   '$(INST_LIBDIR)/FHActivity.pm' },
);
