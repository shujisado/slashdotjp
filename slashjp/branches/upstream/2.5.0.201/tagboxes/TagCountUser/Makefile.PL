use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
# $Id: Makefile.PL,v 1.2 2006/05/30 18:37:53 jamiemccarthy Exp $
WriteMakefile(
    'NAME'	=> 'Slash::Tagbox::TagCountUser',
    'VERSION_FROM' => 'TagCountUser.pm', # finds $VERSION
    'PM'	=> { 'TagCountUser.pm' =>   '$(INST_LIBDIR)/TagCountUser.pm' },
);
