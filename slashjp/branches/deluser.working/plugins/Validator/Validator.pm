# W3C Markup Validation Service
# A module for Slash based on "check",
# a CGI script to retrieve and validate a markup file
# This could be totally stripped down and cleaned up, but for now,
# making only minimally needed changes.
#
# Copyright 1995-2004 Gerald Oskoboiny <gerald@w3.org>
# for additional contributors, see http://dev.w3.org/cvsweb/validator/
#
# This source code is available under the license at:
#     http://www.w3.org/Consortium/Legal/copyright-software
#
# $Id$

package Slash::Validator;

#
# Disable buffering on STDOUT!
#$| = 1;

#
# We need Perl 5.6.0+.
use 5.006;

###############################################################################
#### Load modules. ############################################################
###############################################################################

#
# Pragmas.
use strict;
use warnings;

#
# Modules.  See also the BEGIN block further down below.
#
# Version numbers given where we absolutely need a minimum version of a given
# module (gives nicer error messages). By default, add an empty import list
# when loading modules to prevent non-OO or poorly written modules from
# polluting our namespace.
#
#use CGI             2.81 qw(
#                            -newstyle_urls
#                            -private_tempfiles
#                            redirect
#                           ); # 2.81 for XHTML, and import redirect() function.

#use CGI::Carp            qw(carp croak fatalsToBrowser);
use Config::General      qw();
use File::Spec           qw();
use HTML::Parser    3.25 qw(); # Need 3.25 for $p->ignore_elements.
#use HTTP::Request        qw();
#use HTTP::Headers::Auth  qw(); # Needs to be imported after other HTTP::*.
use IO::File             qw();
#use LWP::UserAgent  1.90 qw(); # Need 1.90 for protocols_(allowed|forbidden)
#use Net::hostent         qw(gethostbyname);
#use Net::IP              qw();
use Set::IntSpan         qw();
#use Socket               qw(inet_ntoa);
use Text::Iconv          qw();
use Text::Wrap           qw(wrap);
use URI                  qw();
use URI::Escape          qw(uri_escape);


###############################################################################
#### Constant definitions. ####################################################
###############################################################################

#
# Define global constants
use constant TRUE  => 1;
use constant FALSE => 0;

#
# Tentative Validation Severities.
use constant T_DEBUG =>  1; # 0000 0001
use constant T_INFO  =>  2; # 0000 0010
use constant T_WARN  =>  4; # 0000 0100
use constant T_ERROR =>  8; # 0000 1000
use constant T_FATAL => 16; # 0001 0000
use constant T_FALL  => 32; # 0010 0000, Fallback in effect.

#
# Output flags for error processing
use constant O_SOURCE  =>  1; # 0000 0001
use constant O_CHARSET =>  2; # 0000 0010
use constant O_DOCTYPE =>  4; # 0000 0100
use constant O_NONE    =>  8; # 0000 1000


#
# Define global variables.
use vars qw($DEBUG $CFG $RSRC $VERSION $HAVE_IPC_RUN);
#our $HAVE_SOAP_LITE;

  #
  # Strings
  ($VERSION    =  q$Revision$) =~ s/Revision: ([\d\.]+) /$1/;


use Slash::Constants ':messages';
use Slash::Utility;
use base 'Slash::DB';
use base 'Slash::DB::Utility';

#
# Things inside BEGIN don't happen on every request in persistent
# environments, such as mod_perl.  So let's do globals, eg. read config here.
sub new {  # BEGIN
  my($class, $user) = @_;
  my $self = {};

  my $constants = getCurrentStatic();
  return unless $constants->{plugin}{Validator};

  bless($self, $class);
  $self->{virtual_user} = $user;
  $self->sqlConnect;

  $ENV{W3C_VALIDATOR_CFG} = $constants->{slashdir} . '/plugins/Validator/validator/htdocs/config/validator.conf';

  #
  # Read Config Files.
  $CFG = &read_cfg($ENV{W3C_VALIDATOR_CFG} || '/etc/w3c/validator.conf');
  if (! -x $CFG->{'SGML Parser'}) {
    die("Configured SGML Parser '$CFG->{'SGML Parser'}' not executable!");
  }

  #
  # Use IPC::Run on mod_perl if it's available, IPC::Open3 otherwise.
  $HAVE_IPC_RUN = 0;
  if ($ENV{MOD_PERL}) {
    eval {
      local $SIG{__DIE__};
      require IPC::Run;
      IPC::Run->import('run', 'timeout');
    };
    $HAVE_IPC_RUN = !$@;
  }
  unless ($HAVE_IPC_RUN) {
    require IPC::Open3;
    IPC::Open3->import('open3');
  }

=begin comment
  #FIXME: This is just a framework and highly experimental!
  #
  # Load SOAP::Lite if available and allowed by config.
  $HAVE_SOAP_LITE = FALSE;
  if (exists $ENV{'HTTP_SOAPACTION'} and $CFG->{'Enable SOAP'} == TRUE) {
    eval {
      local $SIG{__DIE__};
      require SOAP::Transport::HTTP;
    };
    $HAVE_SOAP_LITE = !$@;
  }
  #FIXME;
=end comment
=cut

  #
  # Read Resource files... (friendly error messages)
  my %config_opts = (-ConfigFile => $CFG->{'Verbose Msg'});
  my %rsrc = Config::General->new(%config_opts)->getall();
  $RSRC = \%rsrc;

  #
  # Set debug flag.
  $DEBUG = TRUE if $ENV{W3C_VALIDATOR_DEBUG} || $CFG->{DEBUG};

  #
  # Use passive FTP by default.
  $ENV{FTP_PASSIVE} = 1 unless exists($ENV{FTP_PASSIVE});


  #
  # Read TAB-delimited configuration files. Returns a hash reference.
  sub read_cfg {
    my $file = shift;
    my %cfg;

    my $fh = new IO::File $file;
    unless (defined $fh) {
      die <<".EOF.";
open($file) returned: $!
(Did you forget to set \$ENV{W3C_VALIDATOR_CFG}
 or to copy validator.conf to /etc/w3c/validator.conf?)
.EOF.
    }

    while (<$fh>) {
      next if /^\s*$/;
      next if /^\s*\#/;
      chomp;
      my($k, $v) = split /\t+/, $_, 2;
      $v = '' unless defined $v;

      if ($v =~ s(^file://){}) {
        $cfg{$k} = &read_cfg($v);
      } elsif ($v =~ /,/) {
        $cfg{$k} = [split /,/, $v];
      } else {
        # Launder data for Perl 5.8+ taint mode, trusting the config...
        $v =~ /^(.*)$/;
        $cfg{$k} = $1;
      }
    }
    undef $fh;
    return \%cfg;
  }

  return $self;

} # end of BEGIN block.

#
# Get rid of (possibly insecure) $PATH.
#delete $ENV{PATH};


###############################################################################
#### Process CGI variables and initialize. ####################################
###############################################################################

sub validate {
	my($self, $data, $opts) = @_;
# XXX: we will deal with this separately later ... -- pudge
$data =~ s!<nobr>(.|&#?\w+;)<wbr></nobr>!$1!gi;
#
# Create a new CGI object.
=begin comment
my $q;
unless ($HAVE_SOAP_LITE) {
  $q = new CGI;
}

#
# The data structure that will hold all session data.
my $File;

#
# Pseudo-SSI include header and footer for output.
$File->{'Header'} = &prepSSI({
                              File     => $CFG->{'Header'},
                              Title    => 'Validation Results',
                              Revision => $VERSION,
                             });
$File->{'Footer'} = &prepSSI({
                              File => $CFG->{'Footer'},
                              Date => q$Date$,
                             });

#
# SSI Footer for static pages does not include closing tags for body & html.
$File->{'Footer'} .= qq(  </body>\n</html>\n);

#
# Prepare standard HTML preamble for output.
$File->{'Results'}  = "Content-Language: en\n";
$File->{'Results'} .= "Content-Type: text/html; charset=utf-8\n\n";
$File->{'Results'} .= $File->{'Header'};
=end comment
=cut

my $File;


##############################################
# Populate $File->{Env} -- Session Metadata. #
##############################################

#
# The URL to this CGI Script.
#unless ($HAVE_SOAP_LITE) {
#  $File->{Env}->{'Self URI'} = $q->url(-query => 0);
#}

#
# Initialize parameters we'll need (and override) later.
# (casing policy: lowercase early)
$File->{Charset}->{Use}      = ''; # The charset used for validation.
$File->{Charset}->{Auto}     = ''; # Autodetection using XML rules (Appendix F)
$File->{Charset}->{HTTP}     = ''; # From HTTP's "charset" parameter.
$File->{Charset}->{META}     = ''; # From HTML's <meta http-equiv>.
$File->{Charset}->{XML}      = ''; # From the XML Declaration.
$File->{Charset}->{Override} = ''; # From CGI/user override.

#
# Array (ref) used to store character offsets for the XML report.
$File->{Offsets}->[0] = [0, 0]; # The first item isn't used...

#
# List to hold line numbers for encoding errors
$File->{Lines} = [];


#########################################
# Populate $File->{Opt} -- CGI Options. #
#########################################

#
# Preprocess the CGI parameters.
=begin comment
if ($HAVE_SOAP_LITE) {
  SOAP::Transport::HTTP::CGI->dispatch_to('MySOAP')->handle;
  exit; # SOAP calls do all the processing in the sub...
} else {
  $q = &prepCGI($File, $q);
=end comment
=cut

=begin FIX
  #
  # Set session switches.
  $File->{Opt}->{'Outline'}        = $q->param('outline') ? TRUE                   :  FALSE;
  $File->{Opt}->{'Show Source'}    = $q->param('ss')      ? TRUE                   :  FALSE;
  $File->{Opt}->{'Show Parsetree'} = $q->param('sp')      ? TRUE                   :  FALSE;
  $File->{Opt}->{'No Attributes'}  = $q->param('noatt')   ? TRUE                   :  FALSE;
  $File->{Opt}->{'Show ESIS'}      = $q->param('esis')    ? TRUE                   :  FALSE;
  $File->{Opt}->{'Show Errors'}    = $q->param('errors')  ? TRUE                   :  FALSE;
  $File->{Opt}->{'Verbose'}        = $q->param('verbose') ? TRUE                   :  FALSE;
  $File->{Opt}->{'Debug'}          = $q->param('debug')   ? TRUE                   :  FALSE;
  $File->{Opt}->{'No200'}          = $q->param('No200')   ? TRUE                   :  FALSE;
  # $File->{Opt}->{'Fussy'}          = $q->param('fussy')   ? TRUE                   :  FALSE;
  $File->{Opt}->{'Charset'}        = $q->param('charset') ? lc $q->param('charset'):     '';
  $File->{Opt}->{'DOCTYPE'}        = $q->param('doctype') ? $q->param('doctype')   :     '';
  $File->{Opt}->{'URI'}            = $q->param('uri')     ? $q->param('uri')       :     '';
  $File->{Opt}->{'Output'}         = $q->param('output')  ? $q->param('output')    : 'html';
  $File->{Opt}->{'Max Errors'}     = $q->param('me')      ? $q->param('me')        :     '';

  #
  # "Fallback" info for Character Encoding (fbc), Content-Type (fbt),
  # and DOCTYPE (fbd). If TRUE, the Override values are treated as
  # Fallbacks instead of Overrides.
  $File->{Opt}->{FB}->{Charset} = $q->param('fbc') ? TRUE : FALSE;
  $File->{Opt}->{FB}->{Type}    = $q->param('fbt') ? TRUE : FALSE;
  $File->{Opt}->{FB}->{DOCTYPE} = $q->param('fbd') ? TRUE : FALSE;

  #
  # If ";debug" was given, let it overrule the value from the config file,
  # regardless of whether it's "0" or "1" (on or off).
  $DEBUG = $q->param('debug') if defined $q->param('debug');
  $File->{Opt}->{Verbose} = TRUE if $DEBUG;

  &abort_if_error_flagged($File, O_NONE); # Too early to &print_table.

  #
  # Get the file and metadata.
  if ($q->param('uploaded_file')) {
    $File = &handle_file($q, $File);
  } elsif ($q->param('fragment')) {
    $File = &handle_frag($q, $File);
  } elsif ($q->param('uri')) {
    $File = &handle_uri($q, $File);
  }
#}
=end FIX
=cut

$File->{Bytes}			= $data;
$File->{'Is Upload'}		= TRUE;
$File->{Charset}->{HTTP}	= $opts->{charset}	|| 'iso-8859-1';
$File->{ContentType}		= $opts->{content_type}	|| 'text/html';
$File->{Type}			= $opts->{type}		|| 'html';
$File->{Opt}->{'Max Errors'}	= defined($opts->{max_errors}) && $opts->{max_errors} !~ /\D/ ? $opts->{max_errors} : 1 || 'all';
$File->{Opt}->{Output}		= '';
$File->{Results}		= '';

unless ($opts->{no_wrapper}) {
	$File->{Bytes} = <<EOT;
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd"><html><head><meta http-equiv="content-type" content="text/html; charset=iso-8859-1"><title>Untitled</title></head><body><div>
$File->{Bytes}
</div></body></html>
EOT
}

#
# Get rid of the CGI object.
#undef $q;

#
# We don't need STDIN any more, so get rid of it to avoid getting clobbered
# by Apache::Registry's idiotic interference under mod_perl.
#untie *STDIN;


#
# Abort if an error was flagged during initialization.
#&abort_if_error_flagged($File, O_NONE); # Too early to &print_table.


###############################################################################
#### Output validation results. ###############################################
###############################################################################

#
# Print different things if we got redirected or had a file upload.
if ($File->{'Is Upload'}) {
  &add_table($File, 'File', &ent($File->{URI}));
} else {
  my $size = (length($File->{Opt}->{URI}) || 38) + 2;
  $size = 50 if $size > 50;

  if (URI::eq("$File->{Opt}->{URI}", $File->{URI})) {
    &add_table($File, qq(<label title="Address of Page to Validate (accesskey: 1)" for="uri">Address</label>),
               [1, 2, '<input accesskey="1" type="text" id="uri" name="uri" size="' . $size
             . '" value="' . &ent($File->{Opt}->{URI}) . '" />']);
  } else {
    my $furi = &ent($File->{URI});
    &add_table($File, qq(<label title="Address of Page to Validate (accesskey: 1)" for="uri">URL</label>),
               '<input accesskey="1" type="text" id="uri" name="uri" size="' . $size
             . '" value="' . $furi . '" />');
    &add_warning($File, 'note', 'Note:',
      sprintf(
        'The URL you gave me, &lt;%s&gt;, returned a redirect to &lt;%s&gt;.',
          &ent($File->{Opt}->{URI}), $furi
      )
    );
  }
}


$File = &find_xml_encoding($File);

#
# Decide on a charset to use (first part)
#
if ($File->{Charset}->{HTTP}) { # HTTP, if given, is authoritative.
  $File->{Charset}->{Use} = $File->{Charset}->{HTTP};
} elsif ($File->{ContentType} =~ m(^text/([-.a-zA-Z0-9]\+)?xml$)) {
  # Act as if $http_charset was 'us-ascii'. (MIME rules)
  $File->{Charset}->{Use} = 'us-ascii';
  my @_source;
  if ($File->{'Is Upload'}) {
    @_source = ('sent by your web browser', ($File->{Server}||'unknown'), 'browser send');
  } else {
    @_source = ('returned by your web server', ($File->{Server}||'unknown'), 'server return');
  }
  &add_warning($File, 'note', 'Note:', <<".EOF.");
      The HTTP Content-Type header $_source[0] ($_source[1]) did not contain
      a "charset" parameter, but the Content-Type was one of the XML text/*
      sub-types (<code>$File->{ContentType}</code>). The relevant
      specification
      (<a href="http://www.ietf.org/rfc/rfc3023.txt">RFC 3023</a>)
      specifies a strong default of "us-ascii" for
      such documents so we will use this value regardless of any encoding you
      may have indicated elsewhere. If you would like to use a different
      encoding, you should arrange to have your $_source[2] this new encoding
      information.
.EOF.
} elsif ($File->{Charset}->{XML}) {
  $File->{Charset}->{Use} = $File->{Charset}->{XML};
} elsif ($File->{Charset}->{Auto} =~ /^utf-16[bl]e$/ && $File->{BOM} == 2) {
  $File->{Charset}->{Use} = 'utf-16';
} elsif ($File->{ContentType} =~ m(^application/([-.a-zA-Z0-9]+\+)?xml$)) {
  $File->{Charset}->{Use} = "utf-8";
} elsif (&is_xml($File->{Type}) and not $File->{ContentType} =~ m(^text/)) {
  $File->{Charset}->{Use} = 'utf-8'; # UTF-8 (image/svg+xml etc.)
}

$File->{Content} = &normalize_newlines($File->{Bytes},
                       exact_charset($File, $File->{Charset}->{Use}));

#
# Try to extract META charset
# (works only if ascii-based and reasonably clean before <meta>)
$File = &preparse($File);
unless ($File->{Charset}->{Use}) {
  $File->{Charset}->{Use} = $File->{Charset}->{META};
}

#
# Handle any Fallback or Override for the charset.
if (&conflict($File->{Opt}->{Charset}, '(detect automatically)')) {
  # charset=foo was given to the CGI and it wasn't "autodetect".

  #
  # Extract the user-requested charset from CGI param.
  my ($override, undef) = split(/\s/, $File->{Opt}->{Charset}, 2);
  $File->{Charset}->{Override} = lc($override);

  if ($File->{Opt}->{FB}->{Charset}) {
    unless ($File->{Charset}->{Use}) {
      &add_warning($File, 'fallback', 'No Character Encoding Found!', <<".EOF."); # Warn about fallback...
  Falling back to "$File->{Charset}->{Override}"
  (<a href="docs/users.html#fbc">explain...</a>).
.EOF.
      $File->{Tentative} |= T_ERROR; # Tag it as Invalid.
      $File->{Charset}->{Use} = $File->{Charset}->{Override};
    }
  } else {
    # Warn about Override unless it's the same as the real charset...
    unless ($File->{Charset}->{Override} eq $File->{Charset}->{Use}) {
      my $cs_use = &ent($File->{Charset}->{Use});
      my $cs_opt = &ent($File->{Charset}->{Override});
      &add_warning($File, 'override', 'Character Encoding Override in effect!', <<".EOF.");
      The detected character encoding "<code>$cs_use</code>"
      has been suppressed and "<code>$cs_opt</code>" used instead.
.EOF.
      $File->{Tentative} |= T_ERROR;
      $File->{Charset}->{Use} = $File->{Charset}->{Override};
    }
  }
}

unless ($File->{Charset}->{Use}) { # No charset given...
  my $message = <<".EOF.";
    <p>
      I was not able to extract a character encoding labeling from any of
      the valid sources for such information. Without encoding information
      it is impossible to reliably validate the document. I'm falling back
      to the "UTF-8" encoding and will attempt to perform the validation,
      but this is likely to fail for all non-trivial documents.
    </p>
.EOF.
  if ($File->{Opt}->{Verbose}) {
    $message .= <<".EOF.";
    <p>The sources I tried to find encoding information include:</p>
    <ul>
      <li>The HTTP Content-Type field.</li>
      <li>The XML Declaration.</li>
      <li>The HTML "META" element.</li>
    </ul>
    <p>
      And I even tried to autodetect it using the algorithm defined in
      <a href="http://www.w3.org/TR/REC-xml#sec-guessing">Appendix F of
        the XML 1.0 Recommendation</a>.
    </p>
    <p>
      Since none of these sources yielded any usable information, I will not be
      able to reliably validate this document. Sorry. Please make sure you
      specify the character encoding in use.
    </p>
    <p class="note">
      Specifying a character encoding is normally done in the web server
      configuration file or administration program. The <a
        href="http://www.w3.org/"><abbr
          title="World Wide Web Consortium">W3C</abbr></a> <a
        href="http://www.w3.org/International/"><abbr
          title="Internationalization">I18N</abbr> Activity</a> has collected
        <a href="http://www.w3.org/International/O-HTTP-charset"
           title="A Few Tips On How To Specify The Character Encoding">a few
          tips on how to do this</a> in popular web server implementations.
    </p>
.EOF.
    $message .= &iana_charset_blurb();
    $message .= <<".EOF.";
    <p>
      To quickly check whether the document would validate after addressing
      the missing character encoding information, you can use the "Encoding"
      form control (accesskey "2") earlier in the page to force an encoding
      override to take effect. "iso-8859-1" (Western Europe and North America)
      and "utf-8" (Universal, but not commonly used in legacy documents) are
      common encodings if you are not sure what encoding to choose.
    </p>
.EOF.
  }
 else {
   $message .= <<".EOF.";
   <p>So what should I do? <a href="docs/help.html#faq-charset">Tell me more...</a></p>
.EOF.
 }
  my $title = 'No Character Encoding Found! Falling back to UTF-8.';
  &add_warning($File, 'fatal', $title, $message);
  $File->{Tentative} |= T_ERROR; # Can never be valid.
  $File->{Charset}->{Use} = 'utf-8';
}

sub iana_charset_blurb () {
  return <<".EOF.";
    <p>
      <a href="http://www.iana.org/"><abbr
      title="Internet Assigned Numbers Authority">IANA</abbr></a>
      maintains the list of <a
      href="http://www.iana.org/assignments/character-sets">official
      names for character sets</a> and the <abbr
        title="Web Design Group">WDG</abbr> has some <a
        href="http://www.htmlhelp.com/tools/validator/charset.html">information
        to help you correctly specify the character encoding</a>.
    </p>
.EOF.
}

#
# Abort if an error was flagged while finding the encoding.
#&abort_if_error_flagged($File, O_CHARSET|O_DOCTYPE);


#
# Check the detected Encoding and transcode.
if (&conflict($File->{Charset}->{Use}, 'utf-8')) {
  $File = &transcode($File);
#  &abort_if_error_flagged($File, O_CHARSET);
}


$File = &check_utf8($File); # always check
$File = &byte_error($File);

#
# Abort if an error was flagged during transcoding
#&abort_if_error_flagged($File, O_SOURCE|O_CHARSET);



#
# Overall parsing algorithm for documents returned as text/html:
#
# For documents that come to us as text/html,
#
#  1. check if there's a doctype
#  2. if there is a doctype, parse/validate against that DTD
#  3. if no doctype, check for an xmlns= attribute on the first element
#  4. if there is an xmlns= attribute, check for XML well-formedness
#  5. if there is no xmlns= attribute, and no DOCTYPE, punt.
#

#
# Override DOCTYPE if user asked for it.
if ($File->{Opt}->{DOCTYPE}
    and not $File->{Opt}->{DOCTYPE} =~ /(Inline|detect)/i) {
  $File = &override_doctype($File);
}

#
# Try to extract a DOCTYPE or xmlns.
$File = &preparse($File);


#
# Set document type to XHTML if the DOCTYPE was for XHTML.
# Set document type to MathML if the DOCTYPE was for MathML.
# This happens when the file is served as text/html
$File->{Type} = 'xhtml+xml'  if $File->{DOCTYPE} =~ /xhtml/i;
$File->{Type} = 'mathml+xml' if $File->{DOCTYPE} =~ /mathml/i;


#
# Sanity check Charset information and add any warnings necessary.
$File = &charset_conflicts($File);

#
# Add metadata iff asked for.
if ($File->{Opt}->{Verbose}) {
  &add_table($File, "Modified",     [1, 2, &ent($File->{Modified})   ]) if $File->{Modified};
  &add_table($File, "Server",       [1, 2, &ent($File->{Server})     ]) if $File->{Server};
  &add_table($File, "Size",         [1, 2, &ent($File->{Size})       ]) if $File->{Size};
  &add_table($File, "Content-Type", [1, 2, &ent($File->{ContentType})]) if $File->{ContentType};
}

if ($File->{'Is Upload'}) {
  &add_table($File, 'Encoding', &ent($File->{Charset}->{Use}));
} else {
  &add_table($File,
             qq(<label accesskey="2" title="Character Encoding (accesskey: 2)" for="charset">Encoding</label>),
             &ent($File->{Charset}->{Use}), &popup_charset);
}

#
# Abandon all hope ye who enter here...
$File = &parse($File);
sub parse (\$) {
  my $File = shift;

  #
  # By default, use SGML catalog file and SGML Declaration.
  my $catalog  = File::Spec->catfile($CFG->{'SGML Library'}, 'sgml.soc');
  my @spopt = qw(
                 -R
                 -wvalid
                 -wnon-sgml-char-ref
                 -wno-duplicate
                );

  #
  # Switch to XML semantics if file is XML.
  if (&is_xml($File->{Type})) {
    $catalog  = File::Spec->catfile($CFG->{'SGML Library'}, 'xml.soc');
    push(@spopt, '-wxml');
    &add_warning($File, 'note', 'Note:', <<".EOF.");
  The Validator XML support has
  <a href="http://openjade.sourceforge.net/doc/xml.htm"
     title="Limitations in Validator XML support">some limitations</a>.
.EOF.
  } else { # Only add these in SGML mode.
#    if ($File->{Opt}->{'Fussy'}) {
#      push @spopt, '-wmin-tag';
#      push @spopt, '-wfully-tagged';
#      push @spopt, '-wrefc';
#      push @spopt, '-wmissing-att-name';
#      push @spopt, '-wdata-delim';
#      &add_warning($File, 'note', 'Note:', <<".EOF.");
#    The Validator is running in "Fussy" mode. In this mode it will generate
#    warnings about some things that are not strictly forbidden in the HTML
#    Recommendation, but that are known to be problematic in popular browsers.
#    In general it is recommended that you fix any such errors regardless, but
#    if in doubt you can rerun the Validator in its lax mode to find out if it
#    will pass your document then.
#.EOF.
#    }
  }


  #
  # Defaults for SP; turn off fixed charset mode and set encoding to UTF-8.
  $ENV{SP_CHARSET_FIXED} = 'NO';
  $ENV{SP_ENCODING}      = 'UTF-8';
  $ENV{SP_BCTF}          = 'UTF-8';

  #
  # Tell onsgmls about the SGML Library.
  $ENV{SGML_SEARCH_PATH} = $CFG->{'SGML Library'};

  #
  # Set the command to execute.
  my @cmd = ($CFG->{'SGML Parser'}, '-n', '-c', $catalog, @spopt);

  #FIXME: This needs a UI and testing!
  #
  # Set onsgmls' -E switch to the number of errors requested.
  if ($File->{Opt}->{'Max Errors'} =~ m(^all$)i) {
    push @cmd, '-E0';
  } elsif ($File->{Opt}->{'Max Errors'} =~ m(^(\d+)$)) {
    my $numErr = $1;
    if ($numErr >= 200) {
      $numErr = 200;
    } elsif ($numErr <= 0) {
      $numErr = 0; #FIXME: Should add feature to supress error output in this case.;
    }
    push @cmd, '-E' . $numErr;
  } else {
    push @cmd, '-E' . ($CFG->{'Max Errors'} || 0); # "-E0" means "all".
  }
  #FIXME;

  if ($DEBUG) {
    &add_table($File, 'Command',
      [1, 2, &ent("@cmd")]);
    &add_table($File, 'SP_CHARSET_FIXED',
      [1, 2, '<code>' . &ent($ENV{SP_CHARSET_FIXED}) . '</code>']);
    &add_table($File, 'SP_ENCODING',
      [1, 2, '<code>' . &ent($ENV{SP_ENCODING})      . '</code>']);
    &add_table($File, 'SP_BCTF',
      [1, 2, '<code>' . &ent($ENV{SP_BCTF})          . '</code>']);
  }

  #
  # Temporary filehandles.
  my $spin  = IO::File->new_tmpfile;
  my $spout = IO::File->new_tmpfile;
  my $sperr = IO::File->new_tmpfile;

  #
  # Dump file to a temp file for parsing.
  for (@{$File->{Content}}) {
    print $spin $_, "\n";
  }

  #
  # seek() to beginning of the file.
  seek $spin, 0, 0;

  #
  # Run it through SP, redirecting output to temporary files.
  if ($HAVE_IPC_RUN) {
    local $^W = 0;
    run(\@cmd, $spin, $spout, $sperr, timeout(10));
    undef $spin;
  } else {
    my $pid = do {
      no warnings 'once';
      local(*SPIN, *SPOUT, *SPERR)  = ($spin, $spout, $sperr);
      open3("<&SPIN", ">&SPOUT", ">&SPERR", @cmd);
    };
    undef $spin;
    waitpid $pid, 0;
  }

  #
  # Rewind temporary filehandles.
  seek $_, 0, 0 for $spout, $sperr;

  $File = &parse_errors($File, $sperr); # Parse error output.
  undef $sperr; # Get rid of no longer needed filehandle.

  $File->{ESIS} = [];
  my $elements_found = 0;
  while (<$spout>) {
    push @{$File->{'DEBUG'}->{ESIS}}, $_;
    $elements_found++ if /^\(/;

    if (/^Axmlns() \w+ (.*)/ or /^Axmlns:([^ ]+) \w+ (.*)/) {
      if (not $File->{Namespace} and $elements_found == 0 and $1 eq "") {
        $File->{Namespace} = $2;
      }
      $File->{Namespaces}->{$2}++;
    }

    next if / IMPLIED$/;
    next if /^ASDAFORM CDATA /;
    next if /^ASDAPREF CDATA /;
    chomp; # Removes trailing newlines
    push @{$File->{ESIS}}, $_;
  }
  undef $spout;

  if (@{$File->{ESIS}} && $File->{ESIS}->[-1] =~ /^C$/) {
    pop(@{$File->{ESIS}});
    $File->{'Is Valid'} = TRUE;
  } else {
    $File->{'Is Valid'} = FALSE;
  }


  #
  # Set Version to be the FPI initially.
  $File->{Version} = $File->{DOCTYPE};

  #
  # Extract any version attribute from the ESIS.
  for (@{$File->{ESIS}}) {
    no warnings 'uninitialized';
    next unless /^AVERSION CDATA (.*)/;
    if ($1 eq '-//W3C//DTD HTML Fallback//EN') {
      $File->{Tentative} |= (T_ERROR | T_FALL);
      &add_warning($File, 'fallback', 'DOCTYPE Fallback in effect!', <<".EOF.");
      The DOCTYPE Declaration in your document was not recognized. This
      probably means that the Formal Public Identifier contains a spelling
      error, or that the Declaration is not using correct syntax. Validation
      has been performed using a default "fallback" Document Type Definition
      that closely resembles HTML 4.01 Transitional, but the document will not
      be Valid until you have corrected the problem with the DOCTYPE
      Declaration.
.EOF.
    }
    $File->{Version} = $1;
    last;
  }

  return $File;
}

#
# Force "XML" if type is an XML type and an FPI was not found.
# Otherwise set the type to be the FPI.
if (&is_xml($File->{Type}) and not $File->{DOCTYPE}) {
  $File->{Version} = 'XML';
} else {
  $File->{Version} = $File->{DOCTYPE} unless $File->{Version};
}

#
# Get the pretty text version of the FPI if a mapping exists.
if (my $prettyver = $CFG->{'FPI to Text'}->{$File->{Version}}) {
  $File->{Version} = $prettyver;
} else {
  $File->{Version} = &ent($File->{Version});
}

if ($File->{'Is Upload'}) {
  &add_table($File, 'Doctype', $File->{Version});
} else {
  &add_table($File, qq(<label accesskey="3" for="doctype" title="Document Type (accesskey: 3)">Doctype</label>),
             $File->{Version}, &popup_doctype);
}


if (&is_xml($File->{Type}) and $File->{Namespace}) {
  my $rns = &ent($File->{Namespace});
  if (&is_xhtml($File->{Type}) and $File->{Namespace} ne 'http://www.w3.org/1999/xhtml') {
    &add_warning($File, 'warning', 'Warning:',
      "Unknown namespace (&#171;<code>$rns</code>&#187;) for text/html document!",
    );
  } elsif (&is_svg($File->{Type}) and $File->{Namespace} ne 'http://www.w3.org/2000/svg') {
    &add_warning($File, 'warning', 'Warning:',
      "Unknown namespace (&#171;<code>$rns</code>&#187;) for SVG document!",
    );
  }

  &add_table($File, 'Root Namespace', [1, 2, qq(<a href="$rns">$rns</a>)])
    if $File->{Opt}->{Verbose};

  if (scalar keys %{$File->{Namespaces}} > 1) {
    my $namespaces = '<ul>';
    for (keys %{$File->{Namespaces}}) {
      my $ns = &ent($_);
      $namespaces .= qq(\t<li><a href="$ns">$ns</a></li>\n)
          unless $_ eq $File->{Namespace}; # Don't repeat Root Namespace.
    }
    $namespaces .= '</ul>';
    &add_table($File, 'Other Namespaces', [1, 2, $namespaces])
      if $File->{Opt}->{Verbose};
  }
}

if (defined $File->{Tentative}) {
  my $class = '';
     $class .= ($File->{Tentative} & T_INFO  ? ' info'    :'');
     $class .= ($File->{Tentative} & T_WARN  ? ' warning' :'');
     $class .= ($File->{Tentative} & T_ERROR ? ' error'   :'');
     $class .= ($File->{Tentative} & T_FATAL ? ' fatal'   :'');

  unless ($File->{Tentative} == T_DEBUG) {
    $File->{Notice} = <<".EOF.";
    <p id="Notice" class="$class">
      Please note that you have chosen one or more options that alter the
      content of the document before validation, or have not provided enough
      information to accurately validate the document. Even if no errors are
      reported below, the document will not be valid until you manually make
      the changes we have performed automatically. Specifically, if you used
      some of the options that override a property of the document (e.g. the
      DOCTYPE or Character Encoding), you must make the same change to the
      source document or the server setup before it can be valid. You will
      also need to insert an appropriate DOCTYPE Declaration or Character
      Encoding (the "charset" parameter for the Content-Type HTTP header) if
      any of those are missing.
    </p>
.EOF.
  }
}



=begin comments
if ($File->{Opt}->{Output} eq 'xml') {
  &report_xml($File);
} elsif ($File->{Opt}->{Output} eq 'earl') {
  &report_earl($File);
} elsif ($File->{Opt}->{Output} eq 'n3') {
  &report_n3($File);
} else {
  print $File->{Results};
  print &jump_links($File);
  print qq(    <div class="meat">\n);

  if ($File->{Opt}->{Verbose} or not $File->{'Is Valid'}) {
    print qq(<div class="splash">\n);
    &print_table($File);
    &print_warnings($File) unless $File->{'Is Valid'};
    print qq(</div>\n);
  } else {
    if ($File->{'Is Valid'} and not $File->{'Is Upload'}) {
      my $thispage = $File->{Env}->{'Self URI'};
      my $escaped_uri = uri_escape($File->{URI});
      $thispage .= qq(?uri=$escaped_uri);
      $thispage .= ';ss=1'      if $File->{Opt}->{'Show Source'};
      $thispage .= ';sp=1'      if $File->{Opt}->{'Show Parsetree'};
      $thispage .= ';noatt=1'   if $File->{Opt}->{'No Attributes'};
      $thispage .= ';outline=1' if $File->{Opt}->{'Outline'};
      $thispage .= ';No200=1'   if $File->{Opt}->{'No200'};

      &add_warning($File, 'note', 'Note:', <<".EOF.");
You can also view <a href="$thispage;verbose=1">verbose
results</a> by setting the corresponding option on the <a
  href="detailed.html">Extended Interface</a>.
.EOF.
    }
  }

  if ($File->{'Is Valid'}) {
    &report_valid($File);
  } else {
    &report_errors($File);
  }

  &outline($File)     if $File->{Opt}->{'Outline'};
  &show_source($File) if $File->{Opt}->{'Show Source'};
  &parse_tree($File)  if $File->{Opt}->{'Show Parsetree'};
  &show_esis($File)   if $File->{Opt}->{'Show ESIS'};
  &show_errors($File) if $File->{Opt}->{'Show Errors'};

  print qq(</div> <!-- End of "meat". -->\n); # End of "Meat".
  print $File->{'Footer'};
}

#
# Get rid of $File object and exit.
undef $File;
exit;
=end comments
=cut

return $File;
}


#############################################################################
# Subroutine definitions
#############################################################################

#
# Add a row to the metadata-table datastructure.
#
# Takes 3 or more arguments. The first is the reference to the datastructure to
# use for storing the table. The second is the header for this row. The third
# and subsequent arguments are table data cells. Each argument corresponds to
# exactly one table data cell. If the argument is a string it is inserted
# directly. If it is a reference it is assumed to be a reference to an array
# of 3 elements. The 3 are: rowspan, colspan, and data.
#
# Make sure that the arguments are properly encoded, this uses them as is.
#
sub add_table {
  my $File = shift;
  my $TH   = shift;
  my @td;

  foreach my $td (@_) {
    if (ref $td) {
      push @td, $td;
    } else {
      push @td, [1, 1, $td];
    }
  }

  if (defined $File->{Table}->{Max}) {
    $File->{Table}->{Max} = scalar @td
      if $File->{Table}->{Max} < scalar @td;
  } else {
    $File->{Table}->{Max} = scalar @td;
  }

  push @{$File->{Table}->{Data}}, { Head => $TH, Tail => \@td};
}



=begin comment
#
# Print the table containing the metadata about the Document Entity.
sub print_table {
  my $File = shift;

  # @@@FIXME@@@: This is a *hack*! ;D
  unless ($File->{'Is Valid'} or scalar @{$File->{Errors} || []} == 0) {
    &add_table($File, 'Errors', scalar @{$File->{Errors}});
  }

  print qq(  <form id="form" method="get" action="check">\n)
    unless $File->{'Is Upload'};

  print join '', @{&serialize_table($File, 'header')};

  # Don't output revalidation options for uploads, can't revalidate them.
  return if ($File->{'Is Upload'});

  my $Options = {};
  my $Form    = {};
  $Form->{Table}->{Fieldset}  = TRUE;
  $Form->{Table}->{Accesskey} = '4';
  $Form->{Table}->{Legend}    = 'Revalidate With Options: (accesskey: 4)';


  add_table($Options, '',
            # Show source?
            q(<label title="Show Page Source (accesskey: 5)" for="ss"><input type="checkbox" value="1" id="ss" name="ss" ) .
            q(accesskey="5" ) .
            ($File->{Opt}->{'Show Source'}    ? q(checked="checked" ) : '') .
            q(/>Show&nbsp;Source</label>),
            # Outline?
            q(<label title="Show an Outline of the document (accesskey: 6)" for="soutline"><input type="checkbox" value="1" id="soutline" name="outline" ) .
            q(accesskey="6" ) .
            ($File->{Opt}->{'Outline'}        ? q(checked="checked" ) : '') .
            q(/>Outline</label>)
           );
  add_table($Options, '',
            # Parse tree?
            q(<label title="Show Parse Tree (accesskey: 7)" for="sp"><input type="checkbox" value="1" id="sp" name="sp" ) .
            q(accesskey="7" ) .
            ($File->{Opt}->{'Show Parsetree'} ? q(checked="checked" ) : '') .
            q(/>Parse&nbsp;Tree</label>),
            # No attributes?
            q(<label title="Exclude Attributes from Parse Tree (accesskey: 8)" for="noatt"><input type="checkbox" value="1" id="noatt" name="noatt" ) .
            q(accesskey="8" ) .
            ($File->{Opt}->{'No Attributes'}  ? q(checked="checked" ) : '') .
            q(/>...no&nbsp;attributes</label>)
           );
  add_table($Options, '',
            # Validate error pages?
             q(<label title="Validate also pages for which the HTTP status code indicates an error" for="No200"><input type="checkbox" value="1" id="No200" name="No200" ) .
             # @@@ accesskey missing
             ($File->{Opt}->{'No200'}         ? q(checked="checked" ) : '') .
             q(/>Validate&nbsp;error&nbsp;pages</label>),
            # Verbose output?
             q(<label title="Show Verbose Output" for="verbose"><input type="checkbox" value="1" id="verbose" name="verbose" ) .
             # @@@ accesskey missing
             ($File->{Opt}->{'Verbose'}         ? q(checked="checked" ) : '') .
             q(/>Verbose&nbsp;Output</label>)
           );
#  add_table($Options, '',
#            # Fussy Parse Mode?
#             q(<label title="Use Fussy Error Reporting" for="fussy"><input type="checkbox" value="1" id="fussy" name="fussy" ) .
#             # @@@ accesskey missing
#             ($File->{Opt}->{Fussy}         ? q(checked="checked" ) : '') .
#             q(/>Fussy&nbsp;Parsing</label>),
#           );

  add_table(
            $Form,
            q(<input type="submit" value="Revalidate" accesskey="9" title="Revalidate file (accesskey: 9)" />),
            [1, $File->{Table}->{Max}, join('', @{&serialize_table($Options, 'options')})]
           );

  print <<".EOF.";
      <fieldset>
        <legend accesskey="4">Revalidate With Options</legend>
.EOF.
  print join '', @{&serialize_table($Form, 'header')};

  # this code should not be redundant - we have the same if page is valid
  my $thispage = $File->{Env}->{'Self URI'};
  my $escaped_uri = uri_escape($File->{URI});
  $thispage .= qq(?uri=$escaped_uri);
  $thispage .= ';ss=1'      if $File->{Opt}->{'Show Source'};
  $thispage .= ';sp=1'      if $File->{Opt}->{'Show Parsetree'};
  $thispage .= ';noatt=1'   if $File->{Opt}->{'No Attributes'};
  $thispage .= ';outline=1' if $File->{Opt}->{'Outline'};
  $thispage .= ';No200=1'   if $File->{Opt}->{'No200'};
  # end redundant code
  print <<".EOF.";
      <div class="moreinfo">
        <p>
          <a href="docs/users.html#Options">Help</a> on the options is available.
        </p>
.EOF.
#  unless ($File->{Opt}->{'Verbose'}) {
#    print <<".EOF.";
#        <p>
#          <a href="$thispage;verbose=1">Verbose output</a> will give you
#          explanations in addition to the error messages.
#        </p>
#.EOF.
#  }
  print qq(      </div>\n);
  print qq(      <div class="cheat"><!-- *sigh* --></div>\n);
  print qq(      </fieldset>\n);

  print qq(  </form>\n);
}
=end comment
=cut

#
# Serialize a table datastructure ($th, @td) into HTML.
# Takes two arguments; the datastructure, and a CSS class name for the table.
# Returns a reference to an array of lines (to enable re-indentation).
sub serialize_table {
  my $table = shift;
  my $class = shift;
  my @table = ();

  push @table, qq(<table class="$class">\n);

  foreach my $tr (@{$table->{Table}->{Data}}) {
    if (ref $tr->{Head}) {
      my $opts = '';
      push @table, "  <tr>\n";
      if ($tr->{Head}->[0] > 1) {
        $opts .= qq( rowspan="$tr->{Head}->[0]");
      }
      if ($tr->{Head}->[1] > 1) {
        $opts .= qq( colspan="$tr->{Head}->[1]");
      }
      push @table, "    <th$opts>" . $tr->{Head}->[2] . ": </th>\n";
    } elsif ($tr->{Head}) {
      push @table, "  <tr>\n";
      push @table, "    <th>" . $tr->{Head} . ": </th>\n";
    } else {
      push @table, "  <tr>\n";
      # Table has no header column.
    }

    for (my $i = 0; $i < scalar @{$tr->{Tail}}; $i++) {
      my $opts = '';
      if ($tr->{Tail}->[$i]->[0] > 1) {
        $opts .= qq( rowspan="$tr->{Tail}->[$i]->[0]");
      }
      if ($tr->{Tail}->[$i]->[1] > 1) {
        $opts .= qq( colspan="$tr->{Tail}->[$i]->[1]");
      }
      push @table, sprintf("    <td%s>%s</td>\n",
                           $opts, ($tr->{Tail}->[$i]->[2] || ''));
    }
    push @table, "  </tr>\n";
  }
  push @table, qq(</table>\n);

  return \@table;
}


#
# Add a waring message to the output.
sub add_warning ($$$$) {
  my $File    = shift;
  my $Class   = shift;
  my $Title   = shift;
  my $Message = shift;

  push @{$File->{Warnings}}, {
                              Class   => $Class,
                              Title   => $Title,
                              Message => $Message,
                             };
}


=begin comment
#
# Print out a list of warnings.
sub print_warnings {
  my $File = shift;
  return unless (defined $File->{Warnings} and scalar @{$File->{Warnings}});
  print qq(  <div class="Warnings">\n);
  for (@{$File->{Warnings}}) {
    if ($_->{Class} eq 'fake' and not $File->{'Is Valid'}) {
      next; # Don't report twice if file is invalid.
    }
    printf qq(    <div class="%s">\n      <h3>%s</h3>\n), $_->{Class}, $_->{Title};
    printf qq(      <div>\n%s      </div>\n    </div>), $_->{Message};
  }
  print qq(  </div>\n);
}

#
# Print HTML explaining why/how to use a DOCTYPE Declaration.
sub doctype_spiel {
  return <<".EOF.";
    <p>
      You should place a DOCTYPE declaration as the very first thing in your
      HTML document. For example, for a typical <a
      href="http://www.w3.org/TR/xhtml1/">XHTML 1.0</a> document:
    </p>
    <pre>
      &lt;!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd"&gt;
      &lt;html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en"&gt;
        &lt;head&gt;
          &lt;title&gt;Title&lt;/title&gt;
        &lt;/head&gt;

        &lt;body&gt;
          &lt;!-- ... body of document ... --&gt;
        &lt;/body&gt;
      &lt;/html&gt;
    </pre>
    <p>
      For XML documents, you may also wish to include an "XML Declaration"
      even before the DOCTYPE Declaration, but this is not well supported
      in older browsers. More information about this can be found in the
      <a href="http://www.w3.org/TR/xhtml1/">XHTML 1.0</a> Recommendation.
    </p>
.EOF.
}


#
# Generate HTML for the "Jump to:" links in results.
sub jump_links {
  my ($File) = @_;
  my $links = '';
  my $me = &uri_escape(&self_url_file($File));

  $links .= <<".EOF.";
      <div class="jumpbar">
        <a id="skip" name="skip"></a> Jump To:
        <ul>
          <li><a title="Result of Validation" href="#result">Results</a></li>
.EOF.
  if ($File->{Opt}->{Verbose}) {
    $links .= '<li><a title="Listing of Source Input" href="#source">Source&nbsp;Listing</a></li>'
      if $File->{Opt}->{'Show Source'};
    $links .= '<li><a title="Document Parse Tree" href="#parse">Parse&nbsp;Tree</a></li>'
      if $File->{Opt}->{'Show Parsetree'};
    $links .= '<li><a title="Document Outline" href="#outline">Outline</a></li>'
      if $File->{Opt}->{'Outline'};
  }
  $links .= "        </ul></div>\n";
  return $links;
}

#
# Proxy authentication requests.
# Note: expects the third argument to be a hash ref (see HTTP::Headers::Auth).
sub authenticate {
  my $File       = shift;
  my $resource   = shift;
  my $authHeader = shift || {};

  my $realm = $resource;
  $realm =~ s([^\w\d.-]*){}g;
  $resource = &ent($resource);

  for my $scheme (keys(%$authHeader)) {
    my $origrealm = $authHeader->{$scheme}->{realm};
    if (!defined($origrealm) || lc($scheme) !~ /^(?:basic|digest)$/) {
      delete($authHeader->{$scheme});
      next;
    }
    $authHeader->{$scheme}->{realm} = "$realm-$origrealm";
  }

  my $headers = HTTP::Headers->new(Connection => 'close');
  $headers->content_type('text/html; charset=utf-8');
  $headers->www_authenticate(%$authHeader);
  $headers = $headers->as_string();

  print <<"EOF";
Status: 401 Authorization Required
$headers

<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
  "http://www.w3.org/TR/1999/REC-html401-19991224/loose.dtd">
<html lang="en">
  <head><title>401 Authorization Required</title></head>
  <body>
    <h1>Authorization Required</h1>
    <p>Sorry, I am not authorized to access the specified URL.</p>
    <p>
      The URL you specified, &lt;<a href="$resource">$resource</a>&gt;,
      returned a 401 "authorization required" response when I tried
      to download it.
    </p>
    <p>
      You should have been prompted by your browser for a
      username/password pair; if you had supplied this information, I
      would have forwarded it to your server for authorization to
      access the resource. You can use your browser's "reload" function
      to try again, if you wish.
    </p>
    <p>
      Of course, you may not want to trust me with this information,
      which is fine. I can tell you that I don't log it or do
      anything else nasty with it, and you can <a href="source/">download the
      source code for this service</a> to see what it does, but you have no
      guarantee that this is actually the code I'm using; you basically have to
      decide whether to trust me or not :-)
    </p>
    <p>
      You should also be aware that the way we proxy this authentication
      information defeats the normal working of HTTP Authentication.
      If you authenticate to server A, your browser may keep sending
      the authentication information to us every time you validate
      a page, regardless of what server it's on, and we'll happily pass
      that on to the server thereby making it possible for a malicious
      server operator to capture your credentials.
    </p>
    <p>
      Due to the way HTTP Authentication works there is no way we can
      avoid this. We are using some "tricks" to fool your client into
      not sending this information in the first place, but there is no
      guarantee this will work. If security is a concern to you, you
      may wish to avoid validating protected resources or take extra
      precautions to prevent your browser from sending authentication
      information when validating other servers.
    </p>
    <p>
      Also note that you shouldn't use HTTP Basic Authentication for
      anything which really needs to be private, since the password
      goes across the network unencrypted.
    </p>
EOF
}


#
# Complain about unknown HTTP responses.
sub http_error {
  my $uri = &ent(shift);
  my $code = &ent(shift);
  my $message = &ent(shift);

  print <<"EOF";
  <a id="skip" name="skip"></a>
  <p>
    I got the following unexpected response when trying to
    retrieve &lt;<a href="$uri">$uri</a>&gt;:
  </p>

  <blockquote>
    <p><code>$code $message</code></p>
  </blockquote>

  <p>
    Please make sure you have entered the URL correctly.
  </p>

EOF
}


#
# Print blurb advocating using the CSS Validator.
sub output_css_validator_blurb {
  my $uri = ent(uri_escape(shift));

  print <<"EOHD";
  <p>
    If you use <a href="http://www.w3.org/Style/CSS/">CSS</a> in your document,
    you should also <a
    href="http://jigsaw.w3.org/css-validator/validator?uri=$uri">check it for
    validity</a> using the W3C <a
    href="http://jigsaw.w3.org/css-validator/">CSS Validation Service</a>.
  </p>
EOHD
}


sub daily_tip {
  my @tipAddrs = keys %{$CFG->{'Tips DB'}};
  srand(time());
  my $tipAddr = $tipAddrs[rand scalar @tipAddrs];
  my $tipSlug = $CFG->{'Tips DB'}->{$tipAddr};

  return <<"EOHD";
  <dl class="tip">
    <dt><a href="http://www.w3.org/2001/06tips/">Tip Of The Day</a>:</dt>
    <dd><a href="$tipAddr">$tipSlug</a></dd>
  </dl>
EOHD
}


#
# Fetch an URL and return the content and selected meta-info.
sub handle_uri {
  my $q    = shift; # The CGI object.
  my $File = shift; # The master datastructure.

  my $uri = new URI (ref $q ? $q->param('uri') : $q);

  my $ua = new LWP::UserAgent;
  $ua->agent("W3C_Validator/$VERSION " . $ua->agent);
  $ua->parse_head(0);  # Parse the http-equiv stuff ourselves. @@ Why?

  $ua->protocols_allowed($CFG->{'Allowed Protocols'} || ['http', 'https']);

  unless ($ua->is_protocol_supported($uri)) {
    $File->{'Error Flagged'} = TRUE;
    $File->{'Error Message'} = &uri_rejected($uri->scheme());
    return $File;
  }

  my $addr = my $iptype = undef;
  if (my $host = gethostbyname($uri->host())) {
    $addr = inet_ntoa($host->addr()) if $host->addr();
    if ($addr && (my $ip = Net::IP->new($addr))) {
      $iptype = $ip->iptype();
    }
  }
  $iptype = 'PUBLIC'
    if ($iptype && $iptype eq 'PRIVATE' && $CFG->{'Allow Private IPs'});
  if ($iptype && $iptype ne 'PUBLIC') {
    $File->{'Error Flagged'} = TRUE;
    $File->{'Error Message'} = &ip_rejected($uri->host(), $addr);
    return $File;
  }
  undef $iptype;
  undef $addr;

  my $req = new HTTP::Request(GET => $uri);

  # If we got a Authorization header, the client is back at it after being
  # prompted for a password so we insert the header as is in the request.
  if($ENV{HTTP_AUTHORIZATION}){
    $req->headers->header(Authorization => $ENV{HTTP_AUTHORIZATION});
  }

  my $res = $ua->request($req);

  unless ($res->code == 200 || $File->{Opt}->{'No200'}) {
    if ($res->code == 401) {
      my %auth = $res->www_authenticate(); # HTTP::Headers::Auth
      &authenticate($File, $res->request->url, \%auth);
    } else {
      print $File->{Results};
      &http_error($uri->as_string, $res->code, $res->message);
    }
    print $File->{'Footer'};
    exit;
  }

  my($type, $ct, $charset)
    = &parse_content_type(
                          $File,
                          $res->header('Content-Type'),
                          scalar($res->request->url),
                         );

  my $lastmod = undef;
  if ( $res->last_modified ) {
    $lastmod = scalar(gmtime($res->last_modified));
  }

  $File->{Bytes}           = $res->content;
  $File->{Type}            = $type;
  $File->{ContentType}     = $ct;
  $File->{Charset}->{HTTP} = lc $charset;
  $File->{Modified}        = $lastmod;
  $File->{Server}          = &ent(scalar $res->server);
  $File->{Size}            = scalar $res->content_length;
  $File->{URI}             = scalar $res->request->url;
  $File->{'Is Upload'}     = FALSE;

  return $File;

}

#
# Handle uploaded file and return the content and selected meta-info.
sub handle_file {
  my $q    = shift; # The CGI object.
  my $File = shift; # The master datastructure.

  my $f = $q->param('uploaded_file');
  my $h = $q->uploadInfo($f);
  my $file;

  local $/ = undef; # set line delimiter so that <> reads rest of file
  $file = <$f>;

  my($type, $ct, $charset) = &parse_content_type($File, $h->{'Content-Type'});

  $File->{Bytes}           = $file;
  $File->{Type}            = $type;
  $File->{ContentType}     = $ct;
  $File->{Charset}->{HTTP} = lc $charset;
  $File->{Modified}        = $h->{'Last-Modified'};
  $File->{Server}          = &ent($h->{'User-Agent'}); # Fake a "server". :-)
  $File->{Size}            = $h->{'Content-Length'};
  $File->{URI}             = "$f"; # Need to stringify because we want ref
                                   # to return false later in add_table.  This
                                   # is also a file handle... see man CGI.
  $File->{'Is Upload'}     = TRUE;

  return $File;
}

#
# Handle uploaded file and return the content and selected meta-info.
sub handle_frag {
  my $q    = shift; # The CGI object.
  my $File = shift; # The master datastructure.

  $File->{Bytes}       = $q->param('fragment');
  $File->{Type}        = 'html';
  $File->{Modified}    = '';
  $File->{Server}      = '';
  $File->{Size}        = '';
  $File->{URI}         = 'upload://Form Submission';
  $File->{'Is Upload'} = TRUE;

  return $File;
}


#
# Parse a Content-Type and parameters. Return document type and charset.
sub parse_content_type {
  my $File         = shift;
  my $Content_Type = shift;
  my $url          = shift;
  my $charset      = '';
  my $type         = '';

  my($ct, @param) = split /\s*;\s*/, lc $Content_Type;

  $type = $CFG->{'File Type'}->{$ct} || $ct;

  foreach my $param (@param) {
    my($p, $v) = split /\s*=\s*/, $param;
    next unless $p =~ m(charset)i;
    if ($v =~ m/([\'\"]?)(\S+)\1/i) {
      $charset = lc $2;
      last;
    }
  }

  if ($type =~ m(/)) {
    if ($type =~ m(text/css) and defined $url) {
      print redirect
        'http://jigsaw.w3.org/css-validator/validator?uri='
          . uri_escape $url;
      exit;
    } else {
      $File->{'Error Flagged'} = TRUE;
      $File->{'Error Message'} = sprintf(<<"      EOF", &ent($type));
    <div class="error">
      <p>
        Sorry, I am unable to validate this document because its content type
        is <code>%s</code>, which is not currently supported by this service.
      </p>
      <p>
        The Content-Type field is sent by your web server (or web browser if
        you use the file upload interface) and depends on its configuration.
        Commonly, web servers will have a mapping of filename extensions
        (such as ".html") to <abbr
          title="Multipurpose Internet Mail Extensions">MIME</abbr>
        <code>Content-Type</code> values (such as <code>text/html</code>).
      </p>
      <p>
        That you recieved this message can mean that your server is
        not configured correctly, that your file does not have the correct
        filename extension, or that you are attempting to validate a file
        type that we do not support yet. In the latter case you should let
        us know that you need us to support that content type (please include
        all relevant details, including the URL to the standards document
        defining the content type) using the instructions on the
        <a href="feedback.html">Feedback Page</a>.
      </p>
    </div>
      EOF
    }
  }

  return $type, $ct, $charset;
}
=end comment
=cut


#
# Normalize newline forms (CRLF/CR/LF) to native newline.
sub normalize_newlines {
  my $file = shift;
  local $_ = shift;  #charset
  my $pattern = '';

  # don't use backreference parentheses!
  $pattern = '\x00\x0D(?:\x00\x0A)?|\x00\x0A' if /^utf-16be$/;
  $pattern = '\x0D\x00(?:\x0A\x00)?|\x0A\x00' if /^utf-16le$/;
  # $pattern = '\x00\x00\x00\x0D(?:\x00\x00\x00\x0A)?|\x00\x00\x00\x0A' if /^UCS-4be$/;
  # $pattern = '\x0D\x00\x00\x00(?:\x0A\x00\x00\x00)?|\x0A\x00\x00\x00' if /^UCS-4le$/;
  # insert other special cases here, such as EBCDIC
  $pattern = '\x0D(?:\x0A)?|\x0A' if !$pattern;    # all other cases

  return [split /$pattern/, $file];
}

#
# find exact charset from general one (utf-16)
#
# needed for per-line conversion and line splitting
# (BE is default, but this will apply only to HTML)
sub exact_charset {
  my $File = shift;
  my $general_charset = shift;
  my $exact_charset = $general_charset;

  if ($general_charset eq 'utf-16') {
    if ($File->{Charset}->{Auto} =~ m/^utf-16[bl]e$/) {
      $exact_charset = $File->{Charset}->{Auto};
    } else { $exact_charset = 'utf-16be'; }
  }
  # add same code for ucs-4 here
  return $exact_charset;
}



#
# Return $_[0] encoded for HTML entities (cribbed from merlyn).
#
# Note that this is used both for HTML and XML escaping.
#
sub ent {
  local $_ = shift;
  return '' unless defined; # Eliminate warnings
  s(["<&>"]){'&#' . ord($&) . ';'}ge;  # should switch to hex sooner or later
  return $_;
}


#
# Truncate source lines for report.
#
# This *really* wants Perl 5.8.0 and it's improved UNICODE support.
# Byte semantics are in effect on all length(), substr(), etc. calls,
# so offsets will be wrong if there are multi-byte sequences prior to
# the column where the error is detected.
#
sub truncate_line {
  my $line  = shift;
  my $col   = shift;

  my $start = $col;
  my $end   = $col;

  for (1..40) {
    $start-- if ($start - 1 >= 0);            # in/de-crement until...
    $end++   if ($end   + 1 <= length $line); # ...we hit end of line.
  }

  unless ($end - $start == 80) {
    if ($start == 0) { # Hit start of line, maybe grab more at end.
      my $diff = 40 - $col;
      for (1..$diff) {
        $end++ if ($end + 1 <= length $line);
      }
    } elsif ($end == length $line) { # Hit end of line, maybe grab more at beginning.
      my $diff = 80 - $col;
      for (1..$diff) {
        $start-- if ($start - 1 >= 0);
      }
    }
  }

  #
  # Add elipsis at end if necessary.
  unless ($end   == length $line) {substr $line, -3, 3, '...'};

  $col = $col - $start; # New offset is diff from $col to $start.
  $line = substr $line, $start, $end - $start; # Truncate.

  #
  # Add elipsis at start if necessary.
  unless ($start == 0)            {substr $line,  0, 3, '...'};

  return $line, $col;
}


#
# Suppress any existing DOCTYPE by commenting it out.
sub override_doctype {
  no strict 'vars';
  my $File       = shift;

  local $dtd     = $CFG->{'Doctypes'}->{$File->{Opt}->{DOCTYPE}};
  local $org_dtd = '';
  local $HTML    = '';
  local $seen    = FALSE;

  my $declaration = sub {
    $seen = TRUE;

    # No Override if Fallback was requested.
    if ($File->{Opt}->{FB}->{DOCTYPE}) {
      $HTML .= $_[0]; # Stash it as is...
    } else { # Comment it out and insert the new one...
      $HTML .= "$dtd\n" . '<!-- ' . $_[0] . ' -->';
      $org_dtd = &ent($_[0]);
    }
  };

  HTML::Parser->new(default_h     => [sub {$HTML .= shift}, 'text'],
                    declaration_h => [$declaration, 'text']
                   )->parse(join "\n", @{$File->{Content}})->eof();

  $File->{Content} = [split /\n/, $HTML];

  if ($seen) {
    unless ($File->{Opt}->{FB}->{DOCTYPE}) {
      my $dtd = ent($File->{Opt}->{DOCTYPE});
      &add_warning($File, 'override', 'DOCTYPE Override in effect!', <<".EOF.");
The detected DOCTYPE Declaration "$org_dtd" has been suppressed and
the DOCTYPE for "<code>$dtd</code>" inserted instead, but even if no
errors are shown below the document will not be Valid until you update
it to reflect this new DOCTYPE.
.EOF.
      $File->{Tentative} |= T_ERROR; # Tag it as Invalid.
    }
  } else {
    unshift @{$File->{Content}}, $dtd;

    if ($File->{Opt}->{FB}->{DOCTYPE}) {
      &add_warning($File, 'fallback', 'No DOCTYPE Found!', <<".EOF.");
Falling back to HTML 4.01 Transitional. (<a href="docs/users.html#fbd">explain...</a>)
.EOF.
      $File->{Tentative} |= T_ERROR; # Tag it as Invalid.
    } else {
      my $dtd = ent($File->{Opt}->{DOCTYPE});
      &add_warning($File, 'override', 'DOCTYPE Override in effect!', <<".EOF.");
The DOCTYPE Declaration for "$dtd" has been inserted at the start of
the document, but even if no errors are shown below the document will
not be Valid until you add the new DOCTYPE Declaration.
.EOF.
      $File->{Tentative} |= T_ERROR; # Tag it as Invalid.
    }
  }

  return $File;
}


#
# Parse errors reported by SP.
sub parse_errors ($$) {
  my $File = shift;
  my $fh   = shift;

  $File->{Errors} = []; # Initialize to an (empty) anonymous array ref.

  for (<$fh>) {
    push @{$File->{'DEBUG'}->{Errors}}, $_;
    chomp;
    my($err, @errors);
    next if /^<OSFD>0:[0-9]+:[0-9]+:[^A-Z]/;
    next if /numbers exceeding 65535 not supported/;
    next if /URL Redirected to/;

    my(@_err) = split /:/;
    next unless $_err[1] eq '<OSFD>0'; #@@@ This is a polite fiction!
    if ($_err[1] =~ m(^<URL>)) {
      @errors = ($_err[0], join(':', $_err[1], $_err[2]), @_err[3..$#_err]);
    } else {
      @errors = @_err;
    }
    $err->{src}  = $errors[1];
    $err->{line} = $errors[2];
    $err->{char} = $errors[3];
    # Workaround for onsgmls 1.5 sometimes reporting errors beyond EOL.
    if ((my $l = length($File->{Content}->[$err->{line}-1])) < $err->{char}) {
      $err->{char} = $l;
    }
    $err->{num}  = $errors[4] || '';
    $err->{type} = $errors[5] || '';
    if ($err->{type} eq 'E' or $err->{type} eq 'X' or $err->{type} eq 'Q') {
      $err->{msg}  = join ':', @errors[6 .. $#errors];
    } elsif ($err->{type} eq 'W') {
      &add_warning($File, 'fake', 'Warning:',
        "Line $err->{line}, column $err->{char}: " . &ent($errors[6]));
      $err->{msg}  = join ':', @errors[6 .. $#errors];
    } else {
      $err->{type} = 'I';
      $err->{num}  = '';
      $err->{msg}  = join ':', @errors[4 .. $#errors];
    }

    # No or unknown FPI and a relative SI.
    if ($err->{msg} =~ m(cannot (open|find))) {
      $File->{'Error Flagged'} = TRUE;
      $File->{'Error Message'} = <<".EOF.";
    <div class="fatal">
      <h2>Fatal Error: $err->{msg}</h2>
      <p>
        I could not parse this document, because it makes reference to a
        system-specific file instead of using a well-known public identifier
        to specify the type of markup being used.
      </p>
.EOF.
      $File->{'Error Message'} .= &doctype_spiel();
      $File->{'Error Message'} .= "    </div>\n";
    }

    # No DOCTYPE.
    if ($err->{msg} =~ m(prolog can\'t be omitted)) {
      my $class = 'fatal';
      my $title = 'No DOCTYPE Found! Falling Back to HTML 4.01 Transitional';
      my $message = <<".EOF.";
      <p>
        A DOCTYPE Declaration is mandatory for most current markup languages
        and without one it is impossible to reliably validate this document.
        I am falling back to "HTML 4.01 Transitional" and will attempt to
        validate the document anyway, but this is very likely to produce
        spurious error messages for most non-trivial documents.
      </p>
.EOF.
      if ($File->{Opt}->{Verbose}) {
        $message .= &doctype_spiel();
        $message .= <<".EOF.";
      <p>
        The W3C QA Activity maintains a <a
          href="http://www.w3.org/QA/2002/04/valid-dtd-list.html">List of
            Valid Doctypes</a> that you can choose from, and the <acronym
          title="Web Design Group">WDG</acronym> maintains a document on
        "<a href="http://htmlhelp.com/tools/validator/doctype.html">Choosing
           a DOCTYPE</a>".
      </p>
.EOF.
      }
 else {
   $message .= <<".EOF.";
   <p>So what should I do? <a href="docs/help.html#faq-doctype">Tell me more...</a></p>
.EOF.
 }
      &add_warning($File, $class, $title, $message);
      next; # Don't report this as a normal error.
    }

#    &abort_if_error_flagged($File, O_DOCTYPE);
    $err->{msg} =~ s/^\s*//;
    push @{$File->{Errors}}, $err;
  }
  undef $fh;
  return $File;
}

=begin comment
#
# Generate a HTML report of detected errors.
sub report_errors ($) {
  my $File = shift;

  #
  # Hash to keep track of how many of each error is reported.
  my %Msgs; # Used to generate a UID for explanations.


  print <<"EOHD";
    <div><a id="result" name="result"></a>
      <h2 class="invalid">This page is <strong>not</strong> Valid $File->{Version}!</h2>
EOHD

  if ($File->{Type} eq 'xml' or $File->{Type} eq 'xhtml' or $File->{Type} eq 'mathml' or $File->{Type} eq 'svg' or $File->{Type} eq 'smil') {
    my $xmlvalid = ($File->{DOCTYPE} ? ' and validity' : '');
    print <<"EOHD";
      <p>
        Below are the results of checking this document for <a
        href="http://www.w3.org/TR/REC-xml#sec-conformance">XML
        well-formedness</a>$xmlvalid.
      </p>
EOHD
  } else {
    print <<"EOHD";
      <p>
        Below are the results of attempting to parse this document with
        an SGML parser.
      </p>
EOHD
  }

  if (scalar @{$File->{Errors}}) {
    print qq(      <ol id="errors">\n);

    foreach my $err (@{$File->{Errors}}) {
      my($line, $col) = &truncate_line($File->{Content}->[$err->{line}-1], $err->{char});

      #DEBUG: Gather vars for print below.
      my $orglength = length($File->{Content}->[$err->{line}-1]);
      my $adjlength = length $line;
      my $orgcol = $err->{char};
      my $adjcol = $col;
      #DEBUG;

      #
      # Chop the source line into 3 pieces; the character at which the error
      # was detected, and everything to the left and right of that position.
      # That way we can add markup to the relevant char without breaking &ent().
      #

      #
      # Left side...
      my $left;
      {
        my $offset = 0; # Left side allways starts at 0.
        my $length;

        if ($col - 1 < 0) { # If error is at start of line...
          $length = 0; # ...floor to 0 (no negative offset).
        } elsif ($col == length $line) { # If error is at EOL...
          $length = $col - 1; # ...leave last char to indicate position.
        } else { # Otherwise grab everything up to pos of error.
          $length = $col;
        }
        $left = substr $line, $offset, $length;
        $left = &ent($left);
      }

      #
      # The character where the error was detected.
      my $char;
      {
        my $offset;
        my $length = 1; # Length is always 1; the char where error was found.

        if ($col == length $line) { # If err is at EOL...
          $offset = $col - 1; # ...then grab last char on line instead.
        } else {
          $offset = $col; # Otherwise just grab the char.
        }
        $char = substr $line, $offset, $length;
        $char = &ent($char);
      }

      #
      # The right side up to the end of the line...
      my $right;
      {
        my $offset;
        my $length;

        # Offset...
        if ($col == length $line) { # If at EOL...
          $offset = 0; # Don't bother as there is nothing left to grab.
        } else {
          $offset = $col + 1; # Otherwise get everything from char-after-error.
        }

        # Length...
        if ($col == length $line) { # If at end of line...
          $length = 0; # ...then don't grab anything.
        } else {
          $length = length($line) - ($col - 1); # Otherwise get the rest of the line.
        }
        $right = substr $line, $offset, $length;
        $right = &ent($right);
      }

      $char = qq(<strong title="Position where error was detected.">$char</strong>);
      $line = $left . $char . $right;

      #DEBUG: Print misc. vars relevant to source display.
      if ($DEBUG) {
        $line .= "<br /> <strong>org length: $orglength - adj length: $adjlength - org col: $orgcol - adj col: $adjcol</strong>";
      }
      #DEBUG;

      my $msg = &ent($err->{msg}); # Entity encode error message.

      # Link from line numbers to source iff we're showing it.
      my $linenr = $File->{'Opt'}->{'Show Source'} ?
        qq(<a href="#line-$err->{line}">$err->{line}</a>) : $err->{line};

      print ' ' x 8; # Indent markup...
      print qq(<li><p><em>Line $linenr, column $err->{char}</em>: );
      print qq{<span class="msg">$msg</span></p>};
      print qq(<p><code class="input">$line</code></p>);

      if ($err->{num}) {
        my(undef, $num) = split /\./, $err->{num};
        if (exists $Msgs{$num}) { # We've already seen this message...
          if ($File->{Opt}->{Verbose}) { # ...so only repeat it in Verbose mode.
            print qq(\n    <div class="hidden mid-$num"></div>\n);
          }
        } else {
          $Msgs{$num} = 1;
          print "\n    $RSRC->{msg}->{$num}->{verbose}\n"
            if exists $RSRC->{msg}->{$num}
            && exists $RSRC->{msg}->{$num}->{verbose};
        }
        my $_msg = $RSRC->{msg}->{nomsg}->{verbose};
        $_msg =~ s/<!--MID-->/$num/g;
        print "    $_msg\n"; # The send feedback plea.
      }
      print "</li>\n";
    }
    print qq(  </ol>\n);
  }

  #
  # Add in Jim Ley's JavaScript to show the explanations for every error
  # message without having to actually download msg.size() * num err.
  if ($File->{Opt}->{Verbose}) {
    print '<script type="text/javascript" src="loadexplanation.js"></script>';
  }
  print "    </div><!-- End of #result -->\n\n";
}


#
# Output "This page is Valid" report.
sub report_valid {
  my $File        = shift;
  my $gifborder   = ' border="0"';
  my $xhtmlendtag = '';
  my $image_uri;
  my $alttext     = '';
  my $gifhw       = '';
  my $source;
  if ($File->{'Is Upload'}) {
    $source = qq(The uploaded file);
  } else {
    my $uri = &ent($File->{URI});
    $source = qq(The document located at &lt;<a href="$uri">$uri</a>&gt;);
  }

  unless ($File->{Version} eq 'unknown' or defined $File->{Tentative}) {
    if ($File->{Version} =~ /^HTML 2\.0$/) {
      $image_uri = "$CFG->{'Home Page'}images/vh20";
      $alttext   = "Valid HTML 2.0!";
      $gifborder = "";
    } elsif ($File->{Version} =~ /HTML 3\.2</) {
      $image_uri = "http://www.w3.org/Icons/valid-html32";
      $alttext   = "Valid HTML 3.2!";
      $gifhw     = ' height="31" width="88"';
    } elsif ($File->{Version} =~ /HTML 4\.0<\/a> Strict$/) {
      $image_uri = "http://www.w3.org/Icons/valid-html40";
      $alttext   = "Valid HTML 4.0!";
      $gifborder = "";
      $gifhw     = ' height="31" width="88"';
    } elsif ($File->{Version} =~ /HTML 4\.0<\/a> /) {
      $image_uri = "http://www.w3.org/Icons/valid-html40";
      $alttext   = "Valid HTML 4.0!";
      $gifhw     = ' height="31" width="88"';
    } elsif ($File->{Version} =~ /HTML 4\.01<\/a> Strict$/) {
      $image_uri = "http://www.w3.org/Icons/valid-html401";
      $alttext   = "Valid HTML 4.01!";
      $gifborder = "";
      $gifhw     = ' height="31" width="88"';
    } elsif ($File->{Version} =~ /HTML 4\.01<\/a> /) {
      $image_uri = "http://www.w3.org/Icons/valid-html401";
      $alttext   = "Valid HTML 4.01!";
      $gifhw     = ' height="31" width="88"';
    } elsif ($File->{Version} =~ /XHTML 1\.0<\/a> /) {
      $image_uri = "http://www.w3.org/Icons/valid-xhtml10";
      $alttext   = "Valid XHTML 1.0!";
      $gifborder = "";
      $gifhw     = ' height="31" width="88"';
      $xhtmlendtag = " /";
    } elsif ($File->{Version} =~ /XHTML Basic 1.0/) {
      $image_uri = "$CFG->{'Home Page'}images/vxhtml-basic10";
      $alttext   = "Valid XHTML Basic 1.0!";
      $gifborder = "";
      $gifhw     = ' height="31" width="88"';
      $xhtmlendtag = " /";
    } elsif ($File->{Version} =~ /XHTML 1.1/) {
      $image_uri = "http://www.w3.org/Icons/valid-xhtml11";
      $alttext   = "Valid XHTML 1.1!";
      $gifborder = "";
      $gifhw     = ' height="31" width="88"';
      $xhtmlendtag = " /";
    } elsif ($File->{Version} =~ /HTML 3\.0/) {
      $image_uri = "$CFG->{'Home Page'}images/vh30";
      $alttext   = "Valid HTML 3.0!";
    } elsif ($File->{Version} =~ /Netscape/) {
      $image_uri = "$CFG->{'Home Page'}images/vhns";
      $alttext   = "Valid Netscape-HTML!";
    } elsif ($File->{Version} =~ /Hotjava/) {
      $image_uri = "$CFG->{'Home Page'}images/vhhj";
      $alttext   = "Valid Hotjava-HTML!";
    } elsif ($File->{Version} =~ /ISO\/IEC 15445:2000/) {
      $image_uri = "$CFG->{'Home Page'}images/v15445";
      $alttext   = "Valid ISO-HTML!";
      $gifborder = "";
    }

    printf qq(<h2 id="result" class="valid">This Page Is Valid%s!</h2>\n),
      $File->{Version} ? " $File->{Version}" : '';

    print &daily_tip($File, $CFG->{'Tips DB'});
    &print_warnings($File) unless $File->{Opt}->{Verbose};

    print <<".EOF.";
    <p>
      $source
      was checked and found to be valid $File->{Version}. This means that the
      resource in question identified itself as "$File->{Version}" and that we
      successfully performed a formal validation using an SGML or XML Parser
      (depending on the markup language used).
    </p>
.EOF.
      if (defined $image_uri) {
        print <<".EOF.";
    <p>
      <img class="inline-badge" src="$image_uri" alt="$alttext"$gifhw />
      To show your readers that you have taken the care to create an
      interoperable Web page, you may display this icon on any page
      that validates. Here is the HTML you should use to add this icon
      to your Web page:
    </p>
    <pre>
    &lt;p&gt;
      &lt;a href="$CFG->{'Home Page'}check?uri=referer"&gt;&lt;img$gifborder
          src="$image_uri"
          alt="$alttext"$gifhw$xhtmlendtag&gt;&lt;/a&gt;
    &lt;/p&gt;
    </pre>
    <p>
    Thanks to this code, you will be able to re-validate your Web page by
    following the link (click on the image), and we encourage you to do so
    every time you modify your document.
    </p>
.EOF.
    }
  } elsif (&is_xml($File->{Type}) and not $File->{DOCTYPE}) {
    print qq(  <h2 class="valid">This document is well-formed XML.</h2>\n);
  } elsif (defined $File->{Tentative}) {
    print qq(<h2 class="valid">This Page <em>Tentatively</em> Validates As $File->{Version} (Tentatively Valid)!</h2>);
    print &daily_tip($File, $CFG->{'Tips DB'});
    &print_warnings($File);
    print <<".EOF.";
      <p>
        $source
        was tentatively found to be Valid. That means it would validate
        as $File->{Version} if you updated the source document to match
        the options used (typically this message indicates that you used
        either the Document Type override or the Character Encoding
        override).
      </p>
.EOF.
  } else {
    print qq(  <h2 class="valid">This document validates as the document type specified!</h2>\n);
    print <<".EOF.";
    <p>
      $source was checked and
      found to be valid $File->{Version}. This means that the resource in
      question identified itself as "$File->{Version}" and that we successfully
      performed a formal validation using an SGML or XML Parser (depending on
      the markup language used).
    </p>
.EOF.
  }

  unless ($File->{'Is Upload'}) {
    my $display = my $thispage = &self_url_file($File);
    $display =~ s/(^.+?)\?uri=(.+)/$1\? uri=$2/; # @@@FIXME: Needs better way!

    &output_css_validator_blurb($File->{URI});

    print <<"EOHD";
  <p>
    If you would like to create a link to <em>this</em> page (i.e., this
    validation result) to make it easier to validate this page in the
    future or to allow others to validate your page, the URL is
    &lt;<a href="$thispage">$display</a>&gt; (or you can just add the
    current page to your bookmarks or hotlist).</p>
EOHD
  }
}


#
# Produce an outline of the document based on Hn elements from the ESIS.
sub outline {
  my $File = shift;

  print <<'EOF';
  <div id="outline" class="mtb">
    <h2>Outline</h2>
    <p>
      Below is an outline for this document, automatically generated from the
      heading tags (<code>&lt;h1&gt;</code> through <code>&lt;h6&gt;</code>.)
    </p>
EOF

  my $prevlevel = 0;
  my $level     = 0;

  for (1 .. $#{$File->{ESIS}}) {
    my $line = $File->{ESIS}->[$_];
    next unless ($line && $line =~ /^\(H([1-6])$/i);

    $prevlevel = $level;
    $level     = $1;

    my $TAB = $level + 2;

    if ($prevlevel == 0) {
      print "    <ul>\n";
    } else {
      if ($level < $prevlevel) {
        print "</li>\n";
        for (my $i = $prevlevel; $i > $level; $i--) {
          print "  " x ($i + 2), "</ul>\n";
          print "  " x (($i + 2) - 1), "</li>\n";
        }
      } elsif ($level == $prevlevel) {
        print "</li>\n";
      } elsif ($level > $prevlevel) {
        if ($level - $prevlevel > 1) {
          foreach my $i (($prevlevel + 1) .. ($level - 1)) {
            print "\n", "  " x ($i + 2), "<ul>\n", "  " x ($i + 2);
            print qq(<li class="warning">A level $i heading is missing!);
          }
          print "\n", "  " x $TAB, "<ul>\n";
        } else {
          print "\n", "  " x $TAB;
          print "<ul>\n";
        }
      }
    }

    $line       = '';
    my $heading = '';
    until (substr($line, 0, 3) =~ /^\)H$level/i) {
      $line = $File->{ESIS}->[$_++];
      if ($line =~ /^-/) {
        my $headcont = $line;
        substr($headcont, 0, 1) = " ";
        $heading .= $headcont;
      } elsif ($line =~ /^AALT CDATA( .+)/i) {
        my $headcont = $1;
        $heading .= $headcont;
      }
    }

    $heading =~ s/\\011/ /g;
    $heading =~ s/\\012/ /g;
    $heading =~ s/\\n/ /g;
    $heading =~ s/\s+/ /g;
    $heading =~ s/^[- ]//;
    $heading = &ent($heading);
    print "  " x ($level + 2), "<li>$heading";
  }
  print "</li>\n";
  for (my $i = $level; $i > 1; $i--) {
    print "  " x ($i + 2), "</ul>\n";
    print "  " x (($i + 2) - 1), "</li>\n";
  }
  print "</ul>\n";

  print <<'EOF';
    <p>
      If this does not look like a real outline, it is likely that the
      heading tags are not being used properly. (Headings should reflect
      the logical structure of the document; they should not be used simply
      to add emphasis, or to change the font size.)
    </p>
    </div>
EOF
}


#
# Create a HTML representation of the document.
sub show_source {
  my $File = shift;

  my $comment = '';
  if ($File->{'Error Flagged'}) {
    $comment = "<p>I have marked lines that I haven't been able to decode.</p>\n";
  }

  # Remove any BOM since we're not at BOT anymore...
  $File->{Content}->[0] =
    substr $File->{Content}->[0], ($File->{BOM} ? 3 : 0); # remove BOM

  print <<".EOF.";
  <div id="source" class="mtb">
    <h2>Source Listing</h2>

    <p>Below is the source input I used for this validation:</p>
    $comment
    <div>
      <pre>
.EOF.

  my $line    = 1;
  my $maxhlen = length scalar @{$File->{Content}};
  for (@{$File->{Content}}) {
    my $hline = (' ' x ($maxhlen - length("$line"))) . $line;
    printf qq(<a id="line-%s" name="line-%s"><strong>%s</strong>: %s</a>\n),
      $line, $line, $hline, ent $_;
    $line++;
  }
  print "      </pre>\n    </div>\n  </div>";
}


#
# Create a HTML Parse Tree of the document for validation report.
sub parse_tree {
  my $File = shift;

  print <<'EOF';
  <div id="parse" class="mtb">
    <h2>Parse Tree</h2>
EOF
  if ($File->{Opt}->{'No Attributes'}) {
    print <<'EOF';
    <p class="note">
      I am excluding the attributes, as you requested.
    </p>
EOF
  } else {
    print <<'EOF';
    <p class="note">
      You can also view this parse tree without attributes by selecting the
      appropriate option on <a href="./#form">the form</a>.
    </p>
EOF
  }

  my $indent   = 0;
  my $prevdata = '';

  print "<pre>\n";
  foreach my $line (@{$File->{ESIS}}) {

    next if ($File->{Opt}->{'No Attributes'} && $line =~ /^A/);

    $line =~ s/\\n/ /g;
    $line =~ s/\\011/ /g;
    $line =~ s/\\012/ /g;
    $line =~ s/\s+/ /g;
    next if $line =~ /^-\s*$/;

    if ($line =~ /^-/) {
      substr($line, 0, 1) = ' ';
      $prevdata .= $line;
      next;
    } elsif ($prevdata) {
      $prevdata = &ent($prevdata);
      $prevdata =~ s/\s+/ /go;
      print wrap(' ' x $indent, ' ' x $indent, $prevdata), "\n";
      undef $prevdata;
    }

    $line = &ent($line);
    if ($line =~ /^\)/) {
      $indent -= 2;
    }

    my $printme;
    chomp($printme = $line);

    if (my ($close, $elem) = $printme =~ /^([()])(.+)/) {
      # reformat and add links on HTML elements
      $close = ($close eq ')') ? '/' : ''; # ")" -> close-tag
      if (my $u = $CFG->{'Element Map'}->{lc($elem)}) {
        $elem = '<a href="' . $CFG->{'Element Ref URI'} . "$u\">$elem</a>";
      }
      $printme = "&lt;$close$elem&gt;";
    } else {
      $printme =~ s,^A,  A,; # indent attributes a bit
    }

    print ' ' x $indent, $printme, "\n";
    if ($line =~ /^\(/) {
      $indent += 2;
    }
  }
  print "</pre>\n";
  print "</div>\n";
}
=end comment
=cut


#
# Do an initial parse of the Document Entity to extract charset and FPI.
sub preparse {
  my $File = shift;

  #
  # Reset DOCTYPE, Root, and Charset (for second invocation).
  $File->{Charset}->{META} = '';
  $File->{DOCTYPE}         = '';
  $File->{Root}            = '';

  my $dtd = sub {
    return if $File->{Root};
    ($File->{Root}, $File->{DOCTYPE}) = shift =~  m(<!DOCTYPE\s+(\w+)\s+PUBLIC\s+(?:[\'\"])([^\"\']+)(?:[\"\']).*>)si;
  };

  my $start = sub {
    my $tag  = shift;
    my $attr = shift;
    my %attr = map {lc($_) => $attr->{$_}} keys %{$attr};

    if ($File->{Root}) {
      if (lc $tag eq 'meta') {
        if (lc $attr{'http-equiv'} eq 'content-type') {
          if ($attr{content} =~ m(charset\s*=[\s\"\']*([^\s;\"\'>]*))si) {
            $File->{Charset}->{META} = lc $1;
          }
        }
      }
      return unless $tag eq $File->{Root};
    } else {
      $File->{Root} = $tag;
    }
    if ($attr->{xmlns}) {$File->{Namespace} = $attr->{xmlns}};
  };

  my $p = HTML::Parser->new(api_version => 3);
  $p->xml_mode(TRUE);
  $p->ignore_elements('BODY');
  $p->ignore_elements('body');
  $p->handler(declaration => $dtd, 'text');
  $p->handler(start => $start, 'tag,attr');
  $p->parse(join "\n", @{$File->{Content}});

  $File->{DOCTYPE} = '' unless defined $File->{DOCTYPE};
  $File->{DOCTYPE} =~ s(^\s+){ }g;
  $File->{DOCTYPE} =~ s(\s+$){ }g;
  $File->{DOCTYPE} =~ s(\s+) { }g;

  return $File;
}

=begin comment
#
# Print out the raw ESIS output for debugging.
sub show_esis ($) {
  print <<'EOF';
  <div id="raw_esis" class="mtb">
    <hr />
    <h2><a name="raw_esis">Raw ESIS Output</a></h2>
    <pre>
EOF
  for (@{shift->{'DEBUG'}->{ESIS}}) {
    s/\\012//g;
    s/\\n/\n/g;
    print ent $_;
  }
  print "    </pre>\n  </div>";
}

#
# Print out the raw error output for debugging.
sub show_errors ($) {
  print <<'EOF';
  <div id="raw_errors" class="mtb">
    <hr />
    <h2><a name="raw_errors">Raw Error Output</a></h2>
    <pre>
EOF
  for (@{shift->{'DEBUG'}->{Errors}}) {print ent $_};
  print "    </pre>\n  </div>";
}


#
# Preprocess CGI parameters.
sub prepCGI {
  my $File = shift;
  my    $q = shift;

  # Avoid CGI.pm's "exists but undef" behaviour.
  if (scalar $q->param) {
    foreach my $param ($q->param) {
      next if $param eq 'uploaded_file'; # 'uploaded_file' contains data.
      next if $q->param($param) eq '0';  # Keep false-but-set params.
      #
      # Parameters that are given to us without specifying a value get
      # set to "1" (the "TRUE" constant). This is so we can test for the
      # boolean value of a parameter instead of first checking whether
      # the param was given and then testing it's value. Needed because
      # CGI.pm sets ";param" and ";param=" to a boolean false value
      # (undef() or a null string, respectively).
      $q->param($param, TRUE) unless $q->param($param);
    }
  }

  # Futz the URL so "/referer" works.
  if ($q->path_info) {
    if ($q->path_info eq '/referer' or $q->path_info eq '/referrer') {
      if ($q->referer) {
        $q->param('uri', $q->referer);
        print redirect &self_url_q($q, $File);
        exit;
      } else {
        print redirect $q->url() . '?uri=' . 'referer';
        exit;
      }
    } else {
      print redirect &self_url_q($q, $File);
      exit;
    }
  }

  # Use "url" unless a "uri" was also given.
  if ($q->param('url') and not $q->param('uri')) {
    $q->param('uri', $q->param('url'));
  }

  # Munge the URL to include commonly omitted prefix.
  my $u = $q->param('uri');
  $q->param('uri', "http://$u") if $u && $u =~ m(^www)i;

  # Issue a redirect for uri=referer.
  if ($q->param('uri') and $q->param('uri') eq 'referer') {
    if ($q->referer) {
      $q->param('uri', $q->referer);
      print redirect &self_url_q($q, $File);
      exit;
    } else {
      # Redirected from /check/referer to /check?uri=referer because
      # the browser didn't send a Referer header, or the request was
      # for /check?uri=referer but no Referer header was found.
      $File->{'Error Flagged'} = TRUE;
      $File->{'Error Message'} = <<".EOF.";
      <div class="error">
        <a id="skip" name="skip"></a>
        <h2><strong>No Referer header found!</strong></h2>
        <p>
          You have requested we check the referring page, but your browser did
          not send the HTTP "Referer" header field. This can be for several
          reasons, but most commonly it is because your browser does not
          know about this header, has been configured not to send one, or is
          behind a proxy or firewall that strips it out of the request before
          it reaches us.
        </p>
        <p>This is <em>not</em> an error in the referring page!</p>
        <p>
          Please use the form interface on the
          <a href="$CFG->{'Home Page'}">Validator Home Page</a> (or the
          <a href="detailed.html">Extended Interface</a>) to check the
          page by URL.
        </p>
      </div>
.EOF.
    }
  }

  # Supersede URL with an uploaded file.
  if ($q->param('uploaded_file')) {
    $q->param('uri', 'upload://' . $q->param('uploaded_file'));
    $File->{'Is Upload'} = TRUE; # Tag it for later use.
  }

  # Supersede URL with an uploaded fragment.
  if ($q->param('fragment')) {
    $q->param('uri', 'upload://Form Submission');
    $File->{'Is Upload'} = TRUE; # Tag it for later use.
  }

  # Redirect to a GETable URL if method is POST without a file upload.
  if ($q->request_method eq 'POST' and not $File->{'Is Upload'}) {
    my $thispage = &self_url_q($q, $File);
    print redirect $thispage;
    exit;
  }

  #
  # Flag an error if we didn't get a file to validate.
  unless ($q->param('uri')) {
    $File->{'Error Flagged'} = TRUE;
    $File->{'Error Message'} = &uri_rejected();
  }

  return $q;
}

#
# Preprocess SSI files.
sub prepSSI {
  my $opt = shift;

  my $fh = new IO::File "< $opt->{File}"
    or croak "open($opt->{File}) returned: $!\n";
  my $ssi = join '', <$fh>;
  close $fh or carp "close($opt->{File}) returned: $!\n";

  $ssi =~ s/<!--\#echo var="title" -->/$opt->{Title}/g
    if defined $opt->{Title};

  $ssi =~ s/<!--\#echo var="date" -->/$opt->{Date}/g
    if defined $opt->{Date};

  $ssi =~ s/<!--\#echo\s+var="revision"\s+-->/$opt->{Revision}/g
    if defined $opt->{Revision};

  # No need to parametrize this one, it's always "./" in this context.
  $ssi =~ s|<!--\#echo\s+var="relroot"\s+-->|./|g;

  return $ssi;
}


#
# Output errors for a rejected IP address.
sub ip_rejected {
  my ($host, $ip) = @_;
  my $msg = $host || 'undefined';
  $msg = 'of ' . $msg if ($ip && $host ne $ip);
  return sprintf(<<".EOF.", &ent($msg));
    <div class="error">
      <a id="skip" name="skip"></a>
      <p>
        Sorry, the IP address %s is not public.
        For security reasons, validating resources located at non-public IP
        addresses has been disabled in this service.
      </p>
    </div>
.EOF.
}


#
# Output errors for a rejected URL.
sub uri_rejected {
  my $scheme = shift || 'undefined';

  return sprintf(<<".EOF.", &ent($scheme));
    <div class="error">
      <a id="skip" name="skip"></a>
      <p>
        Sorry, this type of
        <a href="http://www.w3.org/Addressing/">URL</a>
        <a href="http://www.iana.org/assignments/uri-schemes">scheme</a>
        (<q>%s</q>) is not supported by this service. Please check
        that you entered the URL correctly.
      </p>
      <p>URLs should be in the form: <code>http://validator.w3.org/</code></p>
      <p>
        If you entered a valid URL using a scheme that we should support,
        please let us know as outlined on our
        <a href="feedback.html">Feedback page</a>. Make sure to include the
        specific URL you would like us to support, and if possible provide a
        reference to the relevant standards document describing the URL scheme
        in question.
      </p>
      <p class="tip">
        Remember that you can always save the page to disk and Validate it
        using the File Upload interface.
      </p>
      <p>
        Incomplete support for <abbr title="Secure Sockets Layer">SSL</abbr>
        and <abbr title="Transport Layer Security">TLS</abbr> is a known
        limitation and is being tracked as
        <a href="http://www.w3.org/Bugs/Public/show_bug.cgi?id=77">Issue #77</a>.
      </p>
    </div>
.EOF.
}
=end comment
=cut


#
# Utility subs to tell if type "is" something.
sub is_xml    {shift =~ m(^[^+]+\+xml$)};
sub is_svg    {shift =~ m(svg\+xml$)};
sub is_smil   {shift =~ m(smil\+xml$)};
sub is_html   {shift =~ m(html\+sgml$)};
sub is_xhtml  {shift =~ m(xhtml\+xml$)};
sub is_mathml {shift =~ m(mathml\+xml$)};


#
# Check charset conflicts and add any warnings necessary.
sub charset_conflicts {
  my $File = shift;

  my $cs_use  = $File->{Charset}->{Use}  ? &ent($File->{Charset}->{Use})  : '';
  my $cs_opt  = $File->{Opt}->{Charset}  ? &ent($File->{Opt}->{Charset})  : '';
  my $cs_http = $File->{Charset}->{HTTP} ? &ent($File->{Charset}->{HTTP}) : '';
  my $cs_xml  = $File->{Charset}->{XML}  ? &ent($File->{Charset}->{XML})  : '';
  my $cs_meta = $File->{Charset}->{META} ? &ent($File->{Charset}->{META}) : '';

  #
  # Add a warning if there was charset info conflict (HTTP header,
  # XML declaration, or <meta> element).
  if (&conflict($File->{Charset}->{HTTP}, $File->{Charset}->{XML})) {
    &add_warning($File, 'note', 'Character Encoding mismatch!', <<".EOF.");
      The character encoding specified in the HTTP header (<code>$cs_http</code>)
      is different from the value in the XML declaration (<code>$cs_xml</code>).
      I will use the value from the HTTP header (<code>$cs_use</code>).
.EOF.
  } elsif (&conflict($File->{Charset}->{HTTP}, $File->{Charset}->{META})) {
    &add_warning($File, 'note', 'Character Encoding mismatch!', <<".EOF.");
      The character encoding specified in the HTTP header (<code>$cs_http</code>)
      is different from the value in the <code>&lt;meta&gt;</code> element
      (<code>$cs_meta</code>). I will use the value from the HTTP header
      (<code>$cs_use</code>) for this validation.
.EOF.
  }
  elsif (&conflict($File->{Charset}->{XML}, $File->{Charset}->{META})) {
    &add_warning($File, 'note', 'Character Encoding mismatch!', <<".EOF.");
      The character encoding specified in the XML declaration (<code>$cs_xml</code>)
      is different from the value in the <code>&lt;meta&gt;</code> element
      (<code>$cs_meta</code>). I will use the value from the XML declaration
      (<code>$cs_xml</code>) for this validation.
.EOF.
    $File->{Tentative} |= T_WARN;
  }

  return $File;
}


#
# Transcode to UTF-8
sub transcode {
  my $File = shift;

  my ($command, $result_charset) = ('', '');
  if ($CFG->{Charsets}->{$File->{Charset}->{Use}}) {
    ($command, $result_charset) =
      split(" ", $CFG->{Charsets}->{$File->{Charset}->{Use}}, 2);
  }

  $result_charset = exact_charset($File, $result_charset);
  if ($command eq 'I') {
    # test if given charset is available
    eval {my $c = Text::Iconv->new($result_charset, 'utf-8')};
    $command = '' if $@;
  } elsif ($command eq 'X') {
    $@ = "$File->{Charset}->{Use} undefined; replace by $result_charset";
  }

  if ($command ne 'I') {
    my $cs = &ent($File->{Charset}->{Use});
    $File->{'Error Flagged'} = TRUE;
    $File->{'Error Message'} = sprintf(<<".EOF.", $cs, &ent($@));
      <p>Sorry!
        A fatal error occurred when attempting to transcode the character
        encoding of the document. Either we do not support this character
        encoding yet, or you have specified a non-existent character encoding
        (often a misspelling).
      </p>
      <p>The detected character encoding was "%s".</p>
      <p>The error was "%s".</p>
      <p>
        If you believe the character encoding to be valid you can submit a
        request for that character encoding (see the
        <a href="feedback.html">feedback page</a> for details) and we will
        look into supporting it in the future.
      </p>
.EOF.
    $File->{'Error Message'} .= &iana_charset_blurb();
    return $File;
  }

  my $c = Text::Iconv->new($result_charset, 'utf-8');
  my $line = 0;
  for (@{$File->{Content}}) {
    my $in = $_;
    $line++;
    $_ = $c->convert($_); # $_ is local!!
    if ($in ne "" and (!defined($_) || $_ eq "")) {
      push @{$File->{Lines}}, $line;
      # try to decoded as much as possible of the line
      my $short = 0;               # longest okay
      my $long = (length $in) - 1; # longest unknown
      while ($long > $short) { # binary search
        my $try = int (($long+$short+1) / 2);
        my $converted = $c->convert(substr($in, 0, $try));
        if (!defined($converted) || $converted eq "") {
          $long  = $try-1;
        } else {
          $short = $try;
        }
      }
      my $remain = (length $in) - $short;
      $_ = $c->convert(substr($in,0,$short))
           . "#### $remain byte(s) unconvertable ####";
    }
  }
  return $File;
}

#
# Check correctness of UTF-8 both for UTF-8 input and for conversion results
sub check_utf8 {
  my $File = shift;

  for (my $i = 0; $i < $#{$File->{Content}}; $i++) {
    # substitution needed for very long lines (>32K), to avoid backtrack
    # stack overflow. Handily, this also happens to count characters.
    local $_ = $File->{Content}->[$i];
    my $count =
    s/  [\x00-\x7F]                           # ASCII
      | [\xC2-\xDF]        [\x80-\xBF]        # non-overlong 2-byte sequences
      |  \xE0[\xA0-\xBF]   [\x80-\xBF]        # excluding overlongs
      | [\xE1-\xEC\xEE\xEF][\x80-\xBF]{2}     # straight 3-byte sequences
      |  \xED[\x80-\x9F]   [\x80-\xBF]        # excluding surrogates
      |  \xF0[\x90-\xBF]   [\x80-\xBF]{2}     # planes 1-3
      | [\xF1-\xF3]        [\x80-\xBF]{3}     # planes 4-15
      |  \xF4[\x80-\x8F][\x80-\xBF]{2}        # plane 16
     //xg;
    if (length) {
      push @{$File->{Lines}}, ($i+1);
      $File->{Content}->[$i] = "#### encoding problem on this line, not shown ####";
      $count = 50; # length of above text
    }
    $count += 0; # Force numeric.
    $File->{Offsets}->[$i + 1] = [$count, $File->{Offsets}->[$i]->[1] + $count];
  }

  # Add a warning if doc is UTF-8 and contains a BOM.
  if ($File->{Content}->[0] =~ m(^\xEF\xBB\xBF)) {
    &add_warning($File, 'note', 'Note:', <<".EOF.");
      The Unicode Byte-Order Mark (BOM) in UTF-8 encoded files is known to cause
      problems for some text editors and older browsers. You may want to consider
      avoiding its use until it is better supported.
.EOF.
  }
  return $File;
}

#
# byte error analysis
sub byte_error {
  my $File = shift;
  my @lines = @{$File->{Lines}};
  if (scalar @lines) {
    $File->{'Error Flagged'} = TRUE;
    my $s = $#lines ? 's' : '';
    my $lines = join ', ', split ',', Set::IntSpan->new(\@lines)->run_list;
    my $cs = &ent($File->{Charset}->{Use});
    $File->{'Error Message'} = <<".EOF.";
      <p class="error">
        Sorry, I am unable to validate this document because on line$s
        <strong>$lines</strong>
        it contained one or more bytes that I cannot interpret as
        <code>$cs</code> (in other words, the bytes
        found are not valid values in the specified Character Encoding).
        Please check both the content of the file and the character
        encoding indication.
      </p>
.EOF.
  }
  return $File;
}


=begin comment
#
# Return an XML report for the page.
sub report_xml {
  my $File = shift;

  my $valid = ($File->{'Is Valid'} ? 'Valid' : 'Invalid');
  my $errs  = ($File->{'Is Valid'} ? '0' : scalar @{$File->{Errors}});

  print <<".EOF.";
Content-Type: application/xml; charset=UTF-8
X-W3C-Validator-Status: $valid
X-W3C-Validator-Errors: $errs

<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="xml-results.xsl"?>
<!DOCTYPE result [
  <!ELEMENT result (meta, warnings?, messages?)>
  <!ATTLIST result
    version CDATA #FIXED '0.9'
  >

  <!ELEMENT meta (uri, modified, server, size, encoding, doctype)>
  <!ELEMENT uri      (#PCDATA)>
  <!ELEMENT modified (#PCDATA)>
  <!ELEMENT server   (#PCDATA)>
  <!ELEMENT size     (#PCDATA)>
  <!ELEMENT encoding (#PCDATA)>
  <!ELEMENT doctype  (#PCDATA)>

  <!ELEMENT warnings (warning)+>
  <!ELEMENT warning  (#PCDATA)>

  <!ELEMENT messages (msg)*>
  <!ELEMENT msg      (#PCDATA)>
  <!ATTLIST msg
    line   CDATA #IMPLIED
    col    CDATA #IMPLIED
    offset CDATA #IMPLIED
  >
]>
.EOF.

  print qq(
<result>
  <meta>
    <uri>), &ent($File->{URI}), qq(</uri>
    <modified>), &ent($File->{Modified}), qq(</modified>
    <server>), $File->{Server}, qq(</server>
    <size>), &ent($File->{Size}), qq(</size>
    <encoding>), &ent($File->{Charset}->{Use}), qq(</encoding>
    <doctype>), &ent($File->{DOCTYPE}), qq(</doctype>
  </meta>
);

  &add_warning($File, 'note', 'Note:', <<".EOF.");
      This interface is highly experimental and the output *will* change
      -- probably even several times -- before finished. Do *not* rely on it!
      See http://validator.w3.org:8001/docs/users.html#api-warning
.EOF.

  if (defined $File->{Warnings} and scalar @{$File->{Warnings}}) {
    print qq(  <warnings>\n);
    printf qq(    <warning>%s</warning>\n),
      &ent($_->{Message}) for @{$File->{Warnings}};
    print qq(  </warnings>\n);
  }

  if (defined $File->{Errors} and scalar @{$File->{Errors}}) {
    print qq(  <messages>\n);

    foreach my $err (@{$File->{Errors}}) {
      chomp $err->{msg};

      # Find index into the %frag hash for the "explanation..." links.
      $err->{idx} =  $err->{msg};
      $err->{idx} =~ s/"[^\"]*"/FOO/g;
      $err->{idx} =~ s/[^A-Za-z ]//g;
      $err->{idx} =~ s/\s+/ /g; # Collapse spaces
      $err->{idx} =~ s/(^\s|\s$)//g; # Remove leading and trailing spaces.
      $err->{idx} =~ s/(FOO )+/FOO /g; # Collapse FOOs.
      $err->{idx} =~ s/FOO FOO/FOO/g; # Collapse FOOs.

      my $offset = $File->{Offsets}->[$err->{line} - 1]->[1] + $err->{char};
      printf <<".EOF.", &ent($err->{msg});
    <msg line="$err->{line}" col="$err->{char}" offset="$offset">%s</msg>
.EOF.
    }
    print qq(  </messages>\n);
  }
  print qq(</result>\n);
}



#
# Return an EARL report for the page.
sub report_earl {
  my $File = shift;

  my $valid = ($File->{'Is Valid'} ? 'Valid' : 'Invalid');
  my $errs  = ($File->{'Is Valid'} ? '0' : scalar @{$File->{Errors}});

  print <<".EOF.";
Content-Type: application/rdf+xml; charset=UTF-8
X-W3C-Validator-Status: $valid
X-W3C-Validator-Errors: $errs

<?xml version="1.0" encoding="UTF-8"?>
<rdf:RDF
  xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
  xmlns="http://www.w3.org/2001/03/earl/1.0-test#"
  xmlns:val="http://validator.w3.org/this_will_change/do_not_rely_on_it!">

  <Assertor rdf:about="http://validator.w3.org/">
    <name>W3 Validator</name>
    <contactInfo rdf:resource="http://validator.w3.org/about.html"/>
    <testMode rdf:resource="http://www.w3.org/2001/03/earl/1.00#Auto" />

.EOF.

  unless ($File->{'Is Valid'}) {
    printf <<".EOF.", &ent($File->{URI});
  <asserts>
   <Assertion rdf:ID="result">
    <subject rdf:resource="%s" />
    <result rdf:resource="http://www.w3.org/2001/03/earl/1.00#fails" />
    <testCase rdf:resource="http://www.w3.org/MarkUp/" />
    <note>Invalid!</note>
   </Assertion>
  </asserts>
.EOF.

    my $errnum = 0 ;
    foreach my $err (@{$File->{Errors}}) {
      ++$errnum ;
      chomp $err->{msg};

      # Find index into the %frag hash for the "explanation..." links.
      $err->{idx} =  $err->{msg};
      $err->{idx} =~ s/"[^\"]*"/FOO/g;
      $err->{idx} =~ s/[^A-Za-z ]//g;
      $err->{idx} =~ s/\s+/ /g; # Collapse spaces
      $err->{idx} =~ s/(^\s|\s\Z)//g; # Remove leading and trailing spaces.
      $err->{idx} =~ s/(FOO )+/FOO /g; # Collapse FOOs.
      $err->{idx} =~ s/FOO FOO/FOO/g; # Collapse FOOs.

      my @offsets = (
                     $File->{Offsets}->[$err->{line}    ]->[0],
                     $File->{Offsets}->[$err->{line} - 1]->[1],
                     $File->{Offsets}->[$err->{line} - 1]->[1] + $err->{char}
                    );
      printf <<".EOF.", &ent($File->{URI}), &ent($err->{msg});
    <asserts>
      <Assertion rdf:ID="err$errnum">
        <subject rdf:parseType="Resource">
          <reprOf rdf:resource="%s"/>
          <val:line>$err->{line}</val:line>
          <val:column>$err->{char}</val:column>
          <val:offset>@offsets</val:offset>
        </subject>
        <result rdf:resource="http://www.w3.org/2003/03/earl/1.00#fails" />
        <testCase rdf:resource="http://www.w3.org/Markup/" />
        <note>%s</note>
      </Assertion>
    </asserts>
.EOF.
    }
  } else {
    printf <<".EOF.", &ent($File->{URI});
  <asserts>
   <Assertion>
    <subject rdf:resource="%s" />
    <result rdf:resource="http://www.w3.org/2001/03/earl/1.00#passes" />
    <testCase rdf:resource="http://www.w3.org/MarkUp/" />
    <note>Valid!</note>
   </Assertion>
  </asserts>
.EOF.
  }

  print <<".EOF.";
  </Assertor>
</rdf:RDF>
.EOF.
}



#
# Return a Notation3 EARL report for the page.
#
# @@ TODO: escape output
sub report_n3 {
  my $File = shift;

  my $valid = ($File->{'Is Valid'} ? 'Valid' : 'Invalid');
  my $errs  = ($File->{'Is Valid'} ? '0' : scalar @{$File->{Errors}});

  print <<".EOF.";
Content-Type: text/plain; charset=UTF-8
X-W3C-Validator-Status: $valid
X-W3C-Validator-Errors: $errs

\@prefix earl: <http://www.w3.org/2001/03/earl/1.0-test#> .
\@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
\@prefix val: <http://validator.w3.org/this_will_change/do_not_rely_on_it!> .

<http://validator.w3.org/> a earl:Assertor;
  earl:name "W3 Validator";
  earl:asserts
.EOF.

  unless ($File->{'Is Valid'}) {
    for (my $i = 0; $i <= scalar @{$File->{Errors}}; $i++) {
      my $err = $File->{Errors}->[$i];
      chomp $err->{msg};

      # Find index into the %frag hash for the "explanation..." links.
      $err->{idx} =  $err->{msg};
      $err->{idx} =~ s/"[^\"]*"/FOO/g;
      $err->{idx} =~ s/[^A-Za-z ]//g;
      $err->{idx} =~ s/\s+/ /g; # Collapse spaces
      $err->{idx} =~ s/(^\s|\s\Z)//g; # Remove leading and trailing spaces.
      $err->{idx} =~ s/(FOO )+/FOO /g; # Collapse FOOs.
      $err->{idx} =~ s/FOO FOO/FOO/g; # Collapse FOOs.

      my @offsets = (
                     $File->{Offsets}->[$err->{line}    ]->[0],
                     $File->{Offsets}->[$err->{line} - 1]->[1],
                     $File->{Offsets}->[$err->{line} - 1]->[1] + $err->{char}
                    );
      print <<".EOF.";
    [
      earl:testMode earl:Auto;
      rdf:predicate earl:fails;
      rdf:subject [
                    val:column "$err->{char}";
                    val:line   "$err->{line}";
                    val:offset "@offsets";
                    earl:testSubject <$File->{URI}>
                  ];
      rdf:object [
                   earl:id <http://www.w3.org/HTML/>;
                   earl:note """$err->{msg} """
                 ]
.EOF.

     if ($i == scalar @{$File->{Errors}}) {
       print "    ]\n";
     } else {
       print "    ],\n";
     }
    }
  } else {
    print <<".EOF.";
    [
      earl:testMode earl:Auto;
      rdf:predicate earl:passes;
      rdf:subject   [earl:testSubject <$File->{URI}>];
      rdf:object    [
                      earl:id <http://www.w3.org/HTML/>;
                      earl:note "Valid"
                    ]
    ]
.EOF.
  }
  print " .\n";
}
=end comment
=cut


#
# Autodetection as in Appendix F of the XML 1.0 Recommendation.
# <http://www.w3.org/TR/2000/REC-xml-20001006#sec-guessing>
#
# return values are: (base_encoding, BOMSize, Size, Pattern)
sub find_base_encoding {
  local $_ = shift;

  # With a Byte Order Mark:
  return ('ucs-4be',  4, 4, '\0\0\0(.)')
    if /^\x00\x00\xFE\xFF/; # UCS-4, big-endian machine (1234)
  return ('ucs-4le',  4, 4, '(.)\0\0\0')
    if /^\xFF\xFE\x00\x00/; # UCS-4, little-endian machine (4321)
  return ('utf-16be', 2, 2, '\0(.)')
    if /^\xFE\xFF/;         # UTF-16, big-endian.
  return ('utf-16le', 2, 2, '(.)\0')
    if /^\xFF\xFE/;         # UTF-16, little-endian.
  return ('utf-8',    3, 1, '')
    if /^\xEF\xBB\xBF/; # UTF-8.

  # Without a Byte Order Mark:
  return ('ucs-4be',  0, 4, '\0\0\0(.)')
    if /^\x00\x00\x00\x3C/; # UCS-4 or 32bit; big-endian machine (1234 order).
  return ('ucs-4le',  0, 4, '(.)\0\0\0')
    if /^\x3C\x00\x00\x00/; # UCS-4 or 32bit; little-endian machine (4321 order).
  return ('utf-16be', 0, 2, '\0(.)')
    if /^\x00\x3C\x00\x3F/; # UCS-2, UTF-16, or 16bit; big-endian.
  return ('utf-16le', 0, 2, '(.)\0')
    if /^\x3C\x00\x3F\x00/; # UCS-2, UTF-16, or 16bit; little-endian.
  return ('utf-8',    0, 1, '')
    if /^\x3C\x3F\x78\x6D/; # UTF-8, ISO-646, ASCII, ISO-8859-*, Shift-JIS, EUC, etc.
  return ('ebcdic',   0, 1, '')
    if /^\x4C\x6F\xA7\x94/; # EBCDIC
  return ('',         0, 1, '');
                            # nothing in particular
}


#
# Find encoding in document according to XML rules
# Only meaningful if file contains a BOM, or for well-formed XML!
sub find_xml_encoding {
  my $File = shift;
  my ($CodeUnitSize, $Pattern);

  ($File->{Charset}->{Auto}, $File->{BOM}, $CodeUnitSize, $Pattern)
    = &find_base_encoding($File->{Bytes});
  my $someBytes = substr $File->{Bytes}, $File->{BOM}, ($CodeUnitSize * 100);
  my $someText = '';                  # 100 arbitrary, but enough in any case

  # translate from guessed encoding to ascii-compatible
  if ($File->{Charset}->{Auto} eq 'ebcdic') {
    # special treatment for EBCDIC, maybe use tr///
    # work on this later
  }
  elsif (!$Pattern) {
    $someText = $someBytes; # efficiency shortcut
  }
  else { # generic code for UTF-16/UCS-4
    $someBytes =~ /^(($Pattern)*)/s;
    $someText = $1;       # get initial piece without chars >255
    $someText =~ s/$Pattern/$1/sg;    # select the relevant bytes
  }

  # try to find encoding pseudo-attribute
  my $s = '[\ \t\n\r]';
  $someText =~ m(^<\?xml $s+ version $s* = $s* ([\'\"]) [-._:a-zA-Z0-9]+ \1 $s+
                  encoding $s* = $s* ([\'\"]) ([A-Za-z][-._A-Za-z0-9]*) \2
                )xso;

  $File->{Charset}->{XML} = lc $3;
  return $File;
}

=begin comment
#
# Abort with a message if an error was flagged at point.
sub abort_if_error_flagged {
  my $File = shift;
  my $Flags = shift;
  if ($File->{'Error Flagged'}) {
    print $File->{'Results'};

    #
    # "Manually" add DOCTYPE row to table if requested.
    if ($Flags & O_DOCTYPE) {
      # @@@ "accesskey" and "for" shouldn't be output for uploads.
      my @data = ($File->{Version});
      # Don't add popup for uploads.
      push(@data, &popup_doctype) unless ($File->{'Is Upload'});
      &add_table($File,
                 qq(<label accesskey="3" for="doctype" title="Document Type (accesskey: 3)">Doctype</label>),
                 @data);
    }

    #
    # "Manually" add charset row to table if requested.
    if ($Flags & O_CHARSET) {
      # @@@ "accesskey" and "for" shouldn't be output for uploads.
      my @data = (&ent($File->{Charset}->{Use}));
      # Don't add popup for uploads.
      push(@data, &popup_charset) unless ($File->{'Is Upload'});
      &add_table($File,
                 qq(<label accesskey="2" title="Character Encoding (accesskey: 2)" for="charset">Encoding</label>),
                 @data);
    }

    &print_table($File)    unless $Flags & O_NONE;
    &print_warnings($File) unless $Flags & O_NONE;
    print $File->{'Error Message'};
    if ($File->{Opt}->{'Show Source'} and $Flags & O_SOURCE) {
      &show_source($File);
    }
    print $File->{'Footer'};
    undef $File;
    exit;
  }
}
=end comment
=cut

#
# conflicting encodings
sub conflict {
  my $encodingA = shift;
  my $encodingB = shift;
  return $encodingA && $encodingB && ($encodingA ne $encodingB);
}

=begin comment
#
# Return a text string suitable for inclusion in the result table.
sub popup_doctype {
  return &CGI::popup_menu(
                          -name => 'doctype',
                            -id => 'doctype',
                       -default => '(detect automatically)',
                        -values => [
                                    '(detect automatically)',
                                    'XHTML 1.1',
                                    'XHTML Basic 1.0',
                                    'XHTML 1.0 Strict',
                                    'XHTML 1.0 Transitional',
                                    'XHTML 1.0 Frameset',
                                    'ISO/IEC 15445:2000 (ISO-HTML)',
                                    'HTML 4.01 Strict',
                                    'HTML 4.01 Transitional',
                                    'HTML 4.01 Frameset',
                                    'HTML 3.2',
                                    'HTML 2.0',
                                   ],
                          );
}

#
# Return a text string suitable for inclusion in the result table.
sub popup_charset {
  return &CGI::popup_menu(
                          -name      => 'charset',
                          -id        => 'charset',
                          -default   => '(detect automatically)',
                          -values => [
                                      '(detect automatically)',
                                      'utf-8 (Unicode, worldwide)',
                                      'utf-16 (Unicode, worldwide)',
                                      'iso-8859-1 (Western Europe)',
                                      'iso-8859-2 (Central Europe)',
                                      'iso-8859-3 (Southern Europe)',
                                      'iso-8859-4 (North European)',
                                      'iso-8859-5 (Cyrillic)',
                                      'iso-8859-6 (Arabic)',
                                      'iso-8859-7 (Greek)',
                                      'iso-8859-8 (Hebrew, visual)',
                                      'iso-8859-8-i (Hebrew, logical)',
                                      'iso-8859-9 (Turkish)',
                                      'iso-8859-10 (Latin 6)',
                                      'iso-8859-13 (Baltic Rim)',
                                      'iso-8859-14 (Celtic)',
                                      'iso-8859-15 (Latin 9)',
                                      'us-ascii (basic English)',
                                      'euc-jp (Japanese, Unix)',
                                      'shift_jis (Japanese, Win/Mac)',
                                      'iso-2022-jp (Japanese, email)',
                                      'euc-kr (Korean)',
                                      'gb2312 (Chinese, simplified)',
                                      'gb18030 (Chinese, simplified)',
                                      'big5 (Chinese, traditional)',
                                      'tis-620 (Thai)',
                                      'koi8-r (Russian)',
                                      'koi8-u (Ukrainian)',
                                      'iso-ir-111 (Cyrillic KOI-8)',
                                      'macintosh (MacRoman)',
                                      'windows-1250 (Central Europe)',
                                      'windows-1251 (Cyrillic)',
                                      'windows-1252 (Western Europe)',
                                      'windows-1253 (Greek)',
                                      'windows-1254 (Turkish)',
                                      'windows-1255 (Hebrew)',
                                      'windows-1256 (Arabic)',
                                      'windows-1257 (Baltic Rim)',
                                     ],
                         );
}

#
# Construct a self-referential URL from a CGI.pm $q object.
sub self_url_q {
  my ($q, $File) = @_;
  my $thispage = $File->{Env}->{'Self URI'};
     $thispage .= '?uri='       . uri_escape($q->param('uri'));
     $thispage .= ';ss=1'      if $q->param('ss');
     $thispage .= ';sp=1'      if $q->param('sp');
     $thispage .= ';noatt=1'   if $q->param('noatt');
     $thispage .= ';outline=1' if $q->param('outline');
     $thispage .= ';No200=1'   if $q->param('No200');
     $thispage .= ';verbose=1' if $q->param('verbose');
  if ($q->param('doctype')
      and not $q->param('doctype') =~ /(Inline|detect)/i) {
    $thispage .= ';doctype=' . uri_escape($q->param('doctype'));
  }
  if ($q->param('charset') and not $q->param('charset') =~ /detect/i) {
    $thispage .= ';charset=' . uri_escape($q->param('charset'));
  }
  return $thispage;
}


#
# Construct a self-referential URL from a $File object.
sub self_url_file {
  my $File = shift;

  my $thispage = $File->{Env}->{'Self URI'};
  my $escaped_uri = uri_escape($File->{URI});
  $thispage .= qq(?uri=$escaped_uri);
  $thispage .= ';ss=1'      if $File->{Opt}->{'Show Source'};
  $thispage .= ';sp=1'      if $File->{Opt}->{'Show Parsetree'};
  $thispage .= ';noatt=1'   if $File->{Opt}->{'No Attributes'};
  $thispage .= ';outline=1' if $File->{Opt}->{'Outline'};
  $thispage .= ';verbose=1' if $File->{Opt}->{'Verbose'};
  $thispage .= ';No200=1'   if $File->{Opt}->{'No200'};

  return $thispage;
}





################################################################################
# Abandon all hope ye who enter here... ########################################
################################################################################

#
# This is where the SOAP magic happens.
package MySOAP;

sub check {
  my $class = shift || '';
  my $uri   = shift || '';
  my $File  = &main::handle_uri($uri, {});
  $File     = &main::find_xml_encoding($File);
  if ($File->{Charset}->{HTTP}) { warn "HTTP";
    $File->{Charset}->{Use} = $File->{Charset}->{HTTP};
  } elsif ($File->{ContentType} =~ m(^text/([-.a-zA-Z0-9]\+)?xml$)) { warn "CT";
    $File->{Charset}->{Use} = 'us-ascii';
  } elsif ($File->{Charset}->{XML}) { warn "XML";
    $File->{Charset}->{Use} = $File->{Charset}->{XML};
  } elsif ($File->{Charset}->{Auto} =~ /^utf-16[bl]e$/ && $File->{BOM} == 2) { warn "autoBOM";
    $File->{Charset}->{Use} = 'utf-16';
  } elsif ($File->{ContentType} =~ m(^application/([-.a-zA-Z0-9]+\+)?xml$)) { warn "app+xml";
    $File->{Charset}->{Use} = "utf-8";
  } elsif (&main::is_xml($File->{Type}) and not $File->{ContentType} =~ m(^text/)) { warn "text";
    $File->{Charset}->{Use} = 'utf-8';
  }
  $File->{Content} = &main::normalize_newlines($File->{Bytes},
                       &main::exact_charset($File, $File->{Charset}->{Use}));
  $File = &main::preparse($File);
  unless ($File->{Charset}->{Use}) {
    $File->{Charset}->{Use} = $File->{Charset}->{META};
  }
  $File->{Type} = 'xhtml+xml'  if $File->{DOCTYPE} =~ /xhtml/i;
  $File->{Type} = 'mathml+xml' if $File->{DOCTYPE} =~ /mathml/i;
  $File = &main::parse($File);
  if ($File->{'Is Valid'}) {
    return $File->{ESIS};
  } else {
    return $File->{Errors};
#    return join '', map {"$_->{line}:$_->{char}:$_->{msg}\n"} @{$File->{Errors}};
  }
}
=end comment
=cut

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# tab-width: 2
# perl-indent-level: 2
# End:


# opts:
#  charset, content_type, type, max_errors
#  data_type, data_id

sub isValid {
	my($self, $data, $opts) = @_;
	my $File = $self->validate($data, $opts);

	if (grep { $_->{type} ne 'W' } @{$File->{Errors}}) {
		my $messages = getObject('Slash::Messages');
		if ($messages && $opts->{message}) {
			my $users = $messages->getMessageUsers(MSG_CODE_HTML_INVALID);
			my $msg   = {
				template_name	=> 'html_invalid',
				subject		=> { template_name => 'html_invalid_subj' },
				html		=> $data,
				opts		=> $opts,
				validator	=> $File,
			};

			$messages->create($users, MSG_CODE_HTML_INVALID, $msg) if @$users;
		}


		return 0;
	} else {
		return 1;
	}

}


1;

__END__
