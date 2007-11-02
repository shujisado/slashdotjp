use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
# $Id: Makefile.PL,v 1.1 2006/11/20 22:01:40 jamiemccarthy Exp $
WriteMakefile(
    'NAME'	=> 'Slash::Tagbox::CommentScoreReason',
    'VERSION_FROM' => 'CommentScoreReason.pm', # finds $VERSION
    'PM'	=> { 'CommentScoreReason.pm' =>   '$(INST_LIBDIR)/CommentScoreReason.pm' },
);
