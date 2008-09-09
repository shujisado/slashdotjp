# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2003 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

package Slash::XML::FOAF;

=head1 NAME

Slash::XML::FOAF - Perl extension for Slash


=head1 SYNOPSIS

	use Slash::XML;
	xmlDisplay('foaf', %data);


=head1 DESCRIPTION

Module to output data about a user using the FOAF (Friend of a Friend)
RDF-schema. See http://www.foaf-project.org/ for details about FOAF.


=head1 EXPORTED FUNCTIONS

=cut

use strict;
use Slash;
use Slash::Utility;

use base 'Slash::XML';
use vars qw($VERSION);

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

my %foaf_elements = ( 
	maker		=> "",
	Agent		=> "",
	Document	=> "",
	Person		=> "",
	mbox_sha1sum	=> "",
	mbox		=> "resource",
	nick		=> "",
	weblog		=> "resource",
	page		=> "resource",
	homepage	=> "resource",
	knows		=> "",
	holdsAccount	=> "",
	OnlineAccount	=> "",
	accountName	=> "",
	accountServiceHomepage => "resource",
);

#========================================================================

=head2 create(PARAM)

Creates FOAF.

=over 4

=item Parameters

=over 4

=item PARAM

Hashref of parameters.  Currently supported options are below.

=over 4

=item Document 

Hash containing various info about the generated FOAF document.
Currently supported attributes are title (dc:title, human-readable
Title of the document), date (dc:date, when the document
was created/last-updated) and maker (foaf:maker, string describing the
creator).

=item Person

Hash containing various info about the foaf:Person desribed in
the generated FOAF document. Currently supported classes and
properties from FOAF are: mbox_sha1sum, foaf:nick, weblog, page,
homepage, knows, holdsAccount, OnlineAccount,accountName, 
accountServiceHomepage and Person. Additionally, seeAlso
can be specified and will be treated as belonging to the
RDF Schema namespace.


=back

=back

=item Return value

The complete FOAF data as a string.

=item NOTE

The validity in regards to the FOAF schema is NOT checked. 
The caller should make sure to abide by the rules.

=back

=cut


sub create {
	my($class, $param) = @_;
	my $self = bless {}, $class;
	my $ret;

	# create bare foaf document
	$ret =  "<?xml version='1.0'?>\n";
	$ret .= "<rdf:RDF\n";
	$ret .= "   xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"\n";
	$ret .= "   xmlns:rdfs=\"http://www.w3.org/2000/01/rdf-schema#\"\n";
	$ret .= "   xmlns:foaf=\"http://xmlns.com/foaf/0.1/\"\n";
	$ret .= "   xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n";

	# create info about current document
	if (defined $param->{Document}){
		my $document =  $param->{Document};
		$ret .= "<foaf:Document rdf:about=''>\n";
		if (defined $document->{title}){
			$ret .= "  <dc:title>$document->{title}</dc:title>\n";
		}
		my $date = defined $document->{date}
			? $document->{date}
			: $self->date2iso8601();
		my $maker = defined $document->{maker}
			? $document->{maker}
			: "Slashcode FOAF.pm $VERSION";

		$ret .= "  <dc:date>$date</dc:date>\n";
		$ret .= "  <foaf:maker><foaf:Agent>\n";
		$ret .= "    <foaf:name>$maker</foaf:name>\n";
		$ret .= "  </foaf:Agent></foaf:maker>\n";
		$ret .= "</foaf:Document>\n";
	}

	#info about the person to be described
	if (defined $param->{Person}){
		$ret .= $self->_processFoaf( "Person", $param->{Person} ); 
	}
	$ret .= "</rdf:RDF>\n";

	return $ret;
}

1;

sub _processFoaf{
	my ($self, $name, $node) = @_;
	my $ret;
	if (ref($node) eq "HASH" ){
		$ret .= "<foaf:$name>\n";
		foreach (keys %$node){
			$ret .= $self->_processFoaf( $_, $node->{$_} );
		}
		$ret .= "</foaf:$name>\n";
	}elsif (ref($node) eq "ARRAY"){
		foreach (@$node){
			$ret .= $self->_processFoaf( $name, $_ );
		}
        }else{
		if ($foaf_elements{$name} && $foaf_elements{$name} eq "resource"){
			$ret .= "<foaf:$name rdf:resource=\"$node\" />\n";
		}elsif ($name eq "seeAlso"){
			$ret .= "<rdfs:seeAlso rdf:resource=\"$node\" />\n";
		}else{
			$ret .= "<foaf:$name>$node</foaf:$name>\n";
		}
	}

	return $ret;
}

__END__


=head1 SEE ALSO

Slash(3), Slash::XML(3).

=head1 VERSION

$Id$
