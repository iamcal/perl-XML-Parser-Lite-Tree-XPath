package XML::Parser::Lite::Tree::XPath;

use strict;
use XML::Parser::Lite::Tree::XPath::Tokener;
use XML::Parser::Lite::Tree::XPath::Tree;
use XML::Parser::Lite::Tree::XPath::Eval;

our $VERSION = '0.14';

# v0.10 - tokener finished
# v0.11 - tree builder started
# v0.12 - tree builder can tree all zvon examples correctly (t/04_tree2.t)
# v0.14 - started on the eval engine - zvon examples 1 and 2 eval correctly (t/05_zvon0[12].t)

sub new {
	my $class = shift;
	my $self = bless {}, $class;
	$self->{tree} = shift;
	$self->{error} = 0;

	return $self;
}

sub select_nodes {
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

	my $ret = $eval->select_nodes($xtree, $self->{tree});

	$self->{error} = $eval->{error};

	return $ret;
}

1;

