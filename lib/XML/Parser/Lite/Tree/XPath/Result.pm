package XML::Parser::Lite::Tree::XPath::Result;

use strict;
use Data::Dumper;

#
# types:
#
# number
# boolean
# string
# nodeset
# attributeset
# node
# attribute
#

sub new {
	my $class = shift;
	my $self = bless {}, $class;

	$self->{type} = shift;
	$self->{value} = shift;

	return $self;
}

sub is_error {
	my ($self) = @_;
	return ($self->{type} eq 'Error') ? 1 : 0;
}

sub normalize {
	my ($self) = @_;

	if ($self->{type} eq 'nodeset'){

		# uniquify and sort
		my %seen = ();
		my @tags =  sort { $a->{order} <=> $b->{order} } grep { ! $seen{$_->{order}} ++ } @{$self->{value}};

		$self->{value} = \@tags;
	}
}

sub ret {
	my ($self, $a, $b) = @_;
	return  XML::Parser::Lite::Tree::XPath::Result->new($a, $b);
}

sub get_type {
	my ($self, $type) = @_;

	return $self->get_boolean if $type eq 'boolean';
	return $self->get_number if $type eq 'number';
	return $self->get_string if $type eq 'string';
	return $self->get_nodeset if $type eq 'nodeset';
}

sub get_boolean {
	my ($self) = @_;

	return $self if $self->{type} eq 'boolean';

	if ($self->{type} eq 'number'){
		return $self->ret('boolean', 0) if $self->{value} eq 'NaN';
		return $self->ret('boolean', $self->{value} != 0);
	}

	if ($self->{type} eq 'nodeset'){
		return $self->ret('boolean', scalar(@{$self->{value}}) > 0);
	}

	if ($self->{type} eq 'attributeset'){
		return $self->ret('boolean', scalar(@{$self->{value}}) > 0);
	}

	die "$self->{value}" if $self->{type} eq 'Error';

	die "can't convert type $self->{type} to boolean";
}

sub get_string {
	my ($self) = @_;

	return $self if $self->{type} eq 'string';

	if ($self->{type} eq 'nodeset'){
		return $self->ret('string', '') unless scalar @{$self->{value}};

		my $node = $self->ret('node', $self->{value}->[0]);

		return $node->get_string;
	}

	if ($self->{type} eq 'attributeset'){

		return $self->ret('string', '') unless scalar @{$self->{value}};

		my $node = $self->ret('attribute', $self->{value}->[0]);

		return $node->get_string;
	}

	if ($self->{type} eq 'attribute'){
		return $self->ret('string', $self->{value}->{value});
	}

	die "can't convert type $self->{type} to string";
}

sub get_nodeset {
	my ($self) = @_;

	return $self if $self->{type} eq 'nodeset';
	return $self if $self->{type} eq 'attributeset';

	if ($self->{type} eq 'node'){
		return $self->ret('nodeset', [$self->{value}]);
	}

	die "can't convert type $self->{type} to nodeset";
}

sub get_number {
	my ($self) = @_;

	return $self if $self->{type} eq 'number';

	die "can't convert type $self->{type} to number";
}

1;
