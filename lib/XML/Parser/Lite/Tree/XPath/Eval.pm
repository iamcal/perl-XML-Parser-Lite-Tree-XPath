package XML::Parser::Lite::Tree::XPath::Eval;

use XML::Parser::Lite::Tree::XPath::Token;
use strict;

sub new {
	my ($class) = @_;
	my $self = bless {}, $class;
	$self->{error} = 0;
	return $self;
}

sub query {
	my ($self, $xpath, $tree) = @_;
	$self->{error} = 0;
	$self->{tree} = $tree;

	$self->{root} = XML::Parser::Lite::Tree::XPath::Result->new('nodeset', [$self->{tree}]);
	$self->{max_order} = $self->mark_orders($self->{tree}, 1, undef);

	my $token = $xpath->{tokens}->[0];
	unless (defined $token){
		$self->{error} = "couldn't get root token to eval.";
		return 0;
	}

	$self->mark_token($token);

	my $out = $token->eval($self->{root});

	if ($out->is_error){
		$self->{error} = $out->{value};
		return 0;
	}

	return $out;

	if ($out->{type} ne 'nodeset'){
		$self->{error} = "Result was not a nodeset (was a $out->{type})";
		return 0;
	}

	return $out->{value};
}

sub mark_orders {
	my ($self, $tag, $i, $parent) = @_;

	$tag->{order} = $i++;
	$tag->{parent} = $parent;

	for my $child(@{$tag->{children}}){
		$i = $self->mark_orders($child, $i, $tag);
	}

	return $i;
}

sub mark_token {
	my ($self, $token) = @_;

	$token->{root} = $self->{root};
	$token->{max_order} = $self->{max_order};

	for my $child(@{$token->{tokens}}){
		$self->mark_token($child);
	}
}

1;
