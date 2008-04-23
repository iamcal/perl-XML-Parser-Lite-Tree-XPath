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

			$ret->normalize();
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

		if ($input->{type} eq 'attributeset'){

			my $out = $self->ret('attributeset', []);

			for my $attr(@{$input->{value}}){

				push @{$out->{value}}, $attr if $attr->{name} eq $self->{content};

			}

			return $out;
		}

		return $self->ret('Error', "filter by name $self->{content} on input $input->{type}");


	}elsif ($self->{type} eq 'NodeTypeTest'){

		if ($self->{content} eq 'node'){
			if ($input->{type} eq 'nodeset'){
				return $input;
			}else{
				return $self->ret('Error', "can't filter node() on a non-nodeset value.");
			}
		}

		return $self->ret('Error', "NodeTypeTest with an unknown filter ($self->{content})");


	}elsif ($self->{type} eq 'Predicate'){

		my $expr = $self->{tokens}->[0];

		my $out = $self->ret('nodeset', []);
		my $i = 1;
		my $c = scalar @{$input->{value}};

		for my $child(@{$input->{value}}){

			$child->{proximity_position} = $i;
			$child->{context_size} = $c;
			$i++;

			my $ret = $expr->eval($self->ret('node', $child));

			if ($ret->{type} eq 'boolean'){

				if ($ret->{value}){
					push @{$out->{value}}, $child;
				}

			}elsif ($ret->{type} eq 'number'){

				if ($ret->{value} == $child->{proximity_position}){
					push @{$out->{value}}, $child;
				}

			}elsif ($ret->{type} eq 'attributeset'){

				if (scalar @{$ret->{value}}){
					push @{$out->{value}}, $child;
				}

			}elsif ($ret->{type} eq 'Error'){

				return $ret;

			}else{
				return $self->ret('Error', "unexpected predicate result type ($ret->{type})");
			}

			delete $child->{proximity_position};
			delete $child->{context_size};
		}

		return $out;

	}elsif ($self->{type} eq 'Number'){

		return $self->ret('number', $self->{content});

	}elsif ($self->{type} eq 'FunctionCall'){

		my $handler = $self->get_function_handler($self->{content});

		if (!defined $handler){
			return return $self->ret('Error', "No handler for function call '$self->{content}'");
		}

		return &$handler($self, $input, $self->{tokens});

	}elsif ($self->{type} eq 'FunctionArg'){

		# a FunctionArg should have a single child

		return $self->ret('Error', 'FunctionArg should have 1 token') unless 1 == scalar @{$self->{tokens}};

		return $self->{tokens}->[0]->eval($input);

	}elsif ($self->{type} eq 'EqualityExpr'){

		my $v1 = $self->{tokens}->[0]->eval($input);
		my $v2 = $self->{tokens}->[1]->eval($input);
		my $t = "$v1->{type}/$v2->{type}";

		return $v1 if $v1->is_error;
		return $v2 if $v2->is_error;

		if ($v1->{type} > $v2->{type}){
			$t = "$v2->{type}/$v1->{type}";
			($v1, $v2) = ($v2, $v1);
		}

		if ($t eq 'attributeset/string'){

			for my $attr(@{$v1->{value}}){;

				my $v1_s = $self->ret('attribute', $attr)->get_string;
				my $ok = $self->compare_op($self->{content}, $v1_s, $v2);

				return $self->ret('boolean', 1) if $ok;
			}

			return $self->ret('boolean', 0);
		}

		if ($t eq 'string/string'){

			return $self->ret('boolean',  $self->compare_op($self->{content}, $v1, $v2));
		}

		return $self->ret('Error', "can't do an EqualityExpr on $t");

	}elsif ($self->{type} eq 'Literal'){

		return $self->ret('string', $self->{content});

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
	return $self->_axis_attribute($input)		if $axis eq 'attribute';

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

		map{
			push @{$out->{value}}, $_;

		}$self->_axis_descendant_single($tag, $me);
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

sub _axis_attribute {
	my ($self, $input) = @_;

	my $out = $self->ret('attributeset', []);

	return $self->ret('Error', "attribute axis can only filter single node (not a $input->{type})") unless $input->{type} eq 'node';

	my $node = $input->{value};

	for my $key(keys %{$node->{attributes}}){
		push @{$out->{value}}, { 'name' => $key, 'value' => $node->{attributes}->{$key} };
	}

	return $out;
}

sub get_function_handler {
	my ($self, $function) = @_;

	my $function_map = {
		'last'			=> 'function_last',
		'not'			=> 'function_not',
		'normalize-space'	=> 'function_normalize_space',
		'count'			=> 'function_count',
	};

	return $function_map->{$function} if defined $function_map->{$function};

	return undef;
}

sub function_last {
	my ($self, $input, $args) = @_;

	return $self->ret('number', $input->{value}->{context_size});
}

sub function_not {
	my ($self, $input, $args) = @_;

	return $self->ret('Error', "not() needs an argument") unless 1 == scalar @{$args};

	my $ret = $args->[0]->eval($input);
	return $ret if $ret->is_error;

	my $out = $ret->get_boolean;

	$out->{value} = !$out->{value};

	return $out
}

sub function_normalize_space {
	my ($self, $input, $args) = @_;

	my $value;

	if (scalar @{$args}){
		my $out = $args->[0]->eval($input);
		return $out if $out->is_error;

		$value = $out->get_string->{value};
	}else{
		$value = $input->get_string->{value};
	}

	$value =~ s!^[\x20\x09\x0d\x0a]+!!;
	$value =~ s![\x20\x09\x0d\x0a]+$!!;
	$value =~ s![\x20\x09\x0d\x0a]+! !g;

	return $self->ret('string', $value);
}

sub function_count {
	my ($self, $input, $args) = @_;

	print Dumper $input;
	print Dumper $args;
	die;

	return $self->ret('Error', 'count() requires a single argument') unless 1 == scalar @{$args};

	my $out = $args->[0]->eval($input);

	return $self->ret('number', scalar($out->{value})) if $out->{type} eq 'nodeset';
	return $self->ret('number', scalar($out->{value})) if $out->{type} eq 'attributeset';

	return $self->ret('Error', 'count() requires a nodeset argument');
}

sub compare_op {
	my ($self, $op, $a1, $a2) = @_;

	if ($a1->{type} eq 'string'){
		if ($op eq '='){
			return ($a1->{value} eq $a2->{value}) ? 1 : 0;
		}else{
			return ($a1->{value} ne $a2->{value}) ? 1 : 0;
		}
	}

	return $self->ret('Error', "compare $op one type $a1->{type}");
}

package XML::Parser::Lite::Tree::XPath::Token::Ret;

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
	return  XML::Parser::Lite::Tree::XPath::Token::Ret->new($a, $b);
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

1;
