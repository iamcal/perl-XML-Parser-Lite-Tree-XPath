package XML::Parser::Lite::Tree::XPath::Eval;

use XML::Parser::Lite::Tree::XPath::Token;
use Data::Dumper;
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

	$self->{uids} = {};
	$self->mark_uids($self->{tree});

	unless ($self->{tree}->{ns_done}){

		$self->{ns_stack} = {};
		$self->mark_namespaces($self->{tree});
		$self->{tree}->{ns_done} = 1;
	}

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

sub mark_uids {
	my ($self, $tag) = @_;

	#
	# mark
	#

	if ($tag->{type} eq 'element'){

		$tag->{uid} = '';

		my $id = $tag->{attributes}->{id};

		if (defined $id && length $id){
			unless (defined $self->{uids}->{$id}){

				$tag->{uid} = $id;
				$self->{uids}->{$id} = 1;
			}
		}
	}


	#
	# descend
	#

	if ($tag->{type} eq 'root' || $tag->{type} eq 'element'){

		for my $child (@{$tag->{children}}){

			$self->mark_uids($child);
		}
	}
}

sub mark_namespaces {
	my ($self, $obj) = @_;


	my @ns_keys;

	#
	# mark
	#

	if ($obj->{type} eq 'element'){

		#
		# first, add any new NS's to the stack
		#

		my @keys = keys %{$obj->{attributes}};

		for my $k(@keys){

			if ($k =~ /^xmlns:(.*)$/){

				push @{$self->{ns_stack}->{$1}}, $obj->{attributes}->{$k};
				push @ns_keys, $1;
				delete $obj->{attributes}->{$k};
			}

			if ($k eq 'xmlns'){

				push @{$self->{ns_stack}->{__default__}}, $obj->{attributes}->{$k};
				push @ns_keys, '__default__';
				delete $obj->{attributes}->{$k};
			}
		}


		#
		# now - does this tag have a NS?
		#

		if ($obj->{name} =~ /^(.*?):(.*)$/){

			$obj->{local_name} = $2;
			$obj->{ns_key} = $1;
			$obj->{ns} = $self->{ns_stack}->{$1}->[-1];
		}else{
			$obj->{local_name} = $obj->{name};
			$obj->{ns} = $self->{ns_stack}->{__default__}->[-1];
		}
	}


	#
	# descend
	#

	if ($obj->{type} eq 'root' || $obj->{type} eq 'element'){

		for my $child (@{$obj->{children}}){

			$self->mark_namespaces($child);
		}
	}


	#
	# pop from stack
	#

	for my $k (@ns_keys){
		pop @{$self->{ns_stack}->{$k}};
	}
}

1;
