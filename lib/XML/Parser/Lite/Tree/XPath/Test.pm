use strict;


package main;

use Test;


package XML::Parser::Lite::Tree::XPath::Test;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA=('Exporter');
@EXPORT= qw(&load_paths);

sub load_paths {
	my ($filename) = @_;
	my @lines;

	open F, 't/'.$filename or die "can't open paths file t/$filename : $!";
	while(my $line = <F>){
		chomp $line;
		push @lines, $line;
	}
	close F;

	return \@lines;
}

1;

