package XML::Parser::Lite::Tree::XPath::Token;

use Data::Dumper;

sub new {
	my $class = shift;
 	my $self = bless {}, $class;
	return $self;
}

sub match {
	my ($self, $type, $content) = @_;

	return 0 unless $self->{type} eq $type;

	return 0 if (defined($content) && ($self->{content} ne $content));

	return 1;
}

sub dump {
	my ($self) = @_;

	my $ret = $self->{type};
	$ret .= ':absolute' if $self->{absolute};
	$ret .= ':'.$self->{content} if defined $self->{content};
	$ret .= '::'.$self->{axis} if defined $self->{axis};

	return $ret;
}

sub ret {
	my ($self, $a, $b) = @_;
	return XML::Parser::Lite::Tree::XPath::Token::Ret->new($a, $b);
}

sub eval {
	my ($self, $input) = @_;

	if ($self->{type} eq 'LocationPath'){

		# a LocationPath should just be a list of Steps, so eval them in order

		my $ret = $input;
		for my $step(@{$self->{tokens}}){

			unless ($step->match('Step')){
				return $self->ret('Error', "Found a non-Step token ('$step->{type}') in a LocationPath");
			}

			$ret = $step->eval($ret);

			return $ret if $ret->is_error;
		}

		return $ret;

	}elsif ($self->{type} eq 'Step'){

		# for a step, loop through it's children

		my $axis = defined($self->{axis}) ? $self->{axis} : 'child';
		my $ret = $self->filter_axis($axis, $input);

		for my $step(@{$self->{tokens}}){

			unless ($step->match('AxisSpecifier') || $step->match('NameTest') || $step->match('Predicate') || $step->match('NodeTypeTest')){

				return $self->ret('Error', "Found an unexpected token ('$step->{type}') in a Step");
			}

			$ret = $step->eval($ret);

			return $ret if $ret->is_error;
		}

		return $ret;


	}elsif ($self->{type} eq 'NameTest'){

		return $input if $self->{content} eq '*';

		if ($self->{content} =~ m!\:\*$!){
			return $self->ret('Error', "Can't do NCName:* NameTests");
		}

		if ($input->{type} eq 'nodeset'){
			my $out = $self->ret('nodeset', []);

			for my $tag(@{$input->{value}}){
				if (($tag->{'type'} eq 'tag') && ($tag->{'name'} eq $self->{content})){
					push @{$out->{value}}, $tag;
				}
			}

			return $out;
		}

		# filter by name here
		die "filter by name $self->{content}";


	}elsif ($self->{type} eq 'NodeTypeTest'){

		if ($self->{content} eq 'node'){
			if ($input->{type} eq 'nodeset'){
				return $input;
			}else{
				die "can't filter node() on a non-nodeset value.";
			}
		}

		die Dumper $self;

	}else{
		return $self->ret('Error', "Don't know how to eval a '$self->{type}' node.");
	}
}

sub filter_axis {
	my ($self, $axis, $input) = @_;

	return $self->_axis_child($input)		if $axis eq 'child';
	return $self->_axis_descendant($input, 0)	if $axis eq 'descendant';
	return $self->_axis_descendant($input, 1)	if $axis eq 'descendant-or-self';
	return $self->_axis_parent($input)		if $axis eq 'parent';
	return $self->_axis_ancestor($input, 0)		if $axis eq 'ancestor';
	return $self->_axis_ancestor($input, 1)		if $axis eq 'ancestor-or-self';
	return $self->_axis_following_sibling($input)	if $axis eq 'following-sibling';
	return $self->_axis_preceding_sibling($input)	if $axis eq 'preceding-sibling';
	return $self->_axis_following($input)		if $axis eq 'following';
	return $self->_axis_preceding($input)		if $axis eq 'preceding';

	return $input if $axis eq 'self';

	return $self->ret('Error', "Unknown axis '$axis'");
}

sub _axis_child {
	my ($self, $in) = @_;

	my $out = $self->ret('nodeset', []);

	for my $tag(@{$in->{value}}){
		for my $child(@{$tag->{children}}){
			push @{$out->{value}}, $child;
		}
	}

	return $out;
}

sub _axis_descendant {
	my ($self, $in, $me) = @_;

	my $out = $self->ret('nodeset', []);

	for my $tag(@{$in->{value}}){

		push @{$out->{value}}, $tag if $me;

		map{
			push @{$out->{value}}, $_;

		}$self->_axis_descendant_single($tag, 0);
	}

	return $out;
}

sub _axis_descendant_single {
	my ($self, $tag, $me) = @_;

	my @out;

	push @out, $tag if $me;

	for my $child(@{$tag->{children}}){

		if ($child->{type} eq 'tag'){

			map{
				push @out, $_;
			}$self->_axis_descendant_single($child, 1);
		}
	}

	return @out;
}


package XML::Parser::Lite::Tree::XPath::Token::Ret;

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

1;
