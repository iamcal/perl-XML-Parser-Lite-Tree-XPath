package XML::Parser::Lite::Tree::XPath;

use strict;
use XML::Parser::Lite::Tree::XPath::Tokener;
use XML::Parser::Lite::Tree::XPath::Tree;
use XML::Parser::Lite::Tree::XPath::Eval;

our $VERSION = '0.21';

sub new {
	my $class = shift;
	my $self = bless {}, $class;
	$self->{tree} = shift;
	$self->{error} = 0;

	return $self;
}

sub query {
	my ($self, $xpath) = @_;

	#
	# toke the xpath
	#

	my $tokener = XML::Parser::Lite::Tree::XPath::Tokener->new();

	unless ($tokener->parse($xpath)){
		$self->{error} = $tokener->{error};
		return 0;
	}


	#
	# tree the xpath
	#

	my $xtree = XML::Parser::Lite::Tree::XPath::Tree->new();

	unless ($xtree->build_tree($tokener->{tokens})){
		$self->{error} = $xtree->{error};
		return 0;
	}


	#
	# eval
	#

	my $eval = XML::Parser::Lite::Tree::XPath::Eval->new();

	my $out = $eval->query($xtree, $self->{tree});

	$self->{error} = $eval->{error};

	return $out;
}

sub select_nodes {
	my ($self, $xpath) = @_;

	my $out = $self->query($xpath);

	return 0 unless $out;

	if ($out->{type} ne 'nodeset'){
                $self->{error} = "Result was not a nodeset (was a $out->{type})";
                return 0;
        }

        return $out->{value};
}

1;

