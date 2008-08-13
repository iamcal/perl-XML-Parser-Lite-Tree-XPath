package XML::Parser::Lite::Tree::XPath;

use strict;
use XML::Parser::Lite::Tree::XPath::Tokener;
use XML::Parser::Lite::Tree::XPath::Tree;
use XML::Parser::Lite::Tree::XPath::Eval;

our $VERSION = '0.21';

# v0.10 - tokener finished
# v0.11 - tree builder started
# v0.12 - tree builder can tree all zvon examples correctly (t/04_tree2.t)
# v0.14 - started on the eval engine - zvon examples 1 and 2 eval correctly (t/05_zvon0[12].t)
# v0.15 - more eval engine work - zvon examples 3,4,5 and some of 6
# v0.16 - more eval engine work - 6 and some of 7 (ret type coersion)
# v0.17 - more eval engine work - 7,8,9 (function arg validation)
# v0.18 - more eval engine work - 1-22 (function map, arg validation, axis handlers)
# v0.19 - cleanup, code coverage, split out axis parser
# v0.20 - moved to string types, fixed attribute axis, enabled all zvon tests, started on function tests
# v0.21 - ???

# TODO
# move context/input into property of the token
# change context info (positions/count) into a stack on the context object, for nested predicates
# implement the missing functions
# tests for all functions ops
# check test coverage (a module for this?)

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

