package XML::Parser::Lite::Tree::XPath::Token;

use strict;
use XML::Parser::Lite::Tree::XPath::Result;
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
	return XML::Parser::Lite::Tree::XPath::Result->new($a, $b);
}

sub eval {
	my ($self, $input) = @_;

	return $input if $input->is_error;

	if ($self->{type} eq 'LocationPath'){

		# a LocationPath should just be a list of Steps, so eval them in order

		my $ret;

		if ($self->{absolute}){
			$ret = $self->{root};
		}else{
			#die "relative path";
			$ret = $input->get_nodeset;
		}


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
			return $self->ret('Error', "No handler for function call '$self->{content}'");
		}

		# prepare the arguments

		my $func = $handler->[0];
		my $sig = $handler->[1];

		my @sig = split /,/, $sig;
		my @args;

		for my $sig(@sig){

			my $source = $self->{tokens}->[scalar @args];

			if (defined $source){
				$sig =~ s/\?$//;

				my $out = $source->eval($input);
				return $out if $out->is_error;

				my $value = undef;

				$value = $out->get_string if $sig eq 'string';
				$value = $out->get_number if $sig eq 'number';
				$value = $out->get_nodeset if $sig eq 'nodeset';
				$value = $out->get_boolean if $sig eq 'boolean';

				return $self->ret('Error', "Can't coerce a function argument into a '$sig'") unless defined $value;
				return $value if $value->is_error;

				push @args, $value;

			}else{
				if ($sig =~ m/\?$/){
					# it's ok - this arg was optional
				}else{
					my $num = 1 + scalar @args;
					return $self->ret('Error', "Argument $num to function $self->{content} is required (type $sig)");
				}
			}
		}

		return &{$func}($self, $input, \@args);

	}elsif ($self->{type} eq 'FunctionArg'){

		# a FunctionArg should have a single child

		return $self->ret('Error', 'FunctionArg should have 1 token') unless 1 == scalar @{$self->{tokens}};

		return $self->{tokens}->[0]->eval($input);

	}elsif (($self->{type} eq 'EqualityExpr') || ($self->{type} eq 'RelationalExpr')){

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

				return $ok if $ok->is_error;
				return $ok if $ok->{value};
			}

			return $self->ret('boolean', 0);
		}

		if ($t eq 'string/string'){

			return $self->compare_op($self->{content}, $v1, $v2);
		}

		if ($t eq 'number/number'){

			return $self->compare_op($self->{content}, $v1, $v2);
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
	my $node = undef;

	if ($input->{type} eq 'nodeset'){
		$node = shift @{$input->{value}};
	}

	if ($input->{type} eq 'node'){
		$node = $input->{value};
	}

	return $self->ret('Error', "attribute axis can only filter single node (not a $input->{type})") unless defined $node;

	for my $key(keys %{$node->{attributes}}){
		push @{$out->{value}}, { 'name' => $key, 'value' => $node->{attributes}->{$key} };
	}

	return $out;
}

sub get_function_handler {
	my ($self, $function) = @_;

	my $function_map = {
		'last'			=> [\&function_last,		'',			],
		'not'			=> [\&function_not,		'boolean',		],
		'normalize-space'	=> [\&function_normalize_space,	'string?',		],
		'count'			=> [\&function_count,		'nodeset',		],
		'name'			=> [\&function_name,		'nodeset?',		],
		'starts-with'		=> [\&function_starts_with,	'string,string',	],
		'contains'		=> [\&function_contains,	'string,string',	],
		'string-length'		=> [\&function_string_length,	'string?',		],
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

	my $out = $args->[0];
	$out->{value} = !$out->{value};

	return $out
}

sub function_normalize_space {
	my ($self, $input, $args) = @_;

	my $value = $args->[0];

	unless (defined $value){
		$value = $input->get_string;
		return $value if $value->get_error;
	}

	$value = $value->{value};
	$value =~ s!^[\x20\x09\x0d\x0a]+!!;
	$value =~ s![\x20\x09\x0d\x0a]+$!!;
	$value =~ s![\x20\x09\x0d\x0a]+! !g;

	return $self->ret('string', $value);
}

sub function_count {
	my ($self, $input, $args) = @_;

	my $subject = $args->[0];

	return $self->ret('number', scalar(@{$subject->{value}})) if $subject->{type} eq 'nodeset';
	return $self->ret('number', scalar(@{$subject->{value}})) if $subject->{type} eq 'attributeset';
}

sub function_name {
	my ($self, $input, $args) = @_;

	my $subject;

	if (defined $args->[0]){
		$subject = $args->[0]->eval($input);
		return $subject if $subject->is_error;
	}else{
		$subject = $input;
	}

	return $self->ret('string', $subject->{value}->{name}) if ($subject->{type} eq 'node');

	if ($subject->{type} eq 'nodeset'){
		my $node = shift @{$subject->{value}};
		
		return $self->ret('string', $node->{name}) if defined $node;
		return $self->ret('Error', "Can't perform name() on an empty nodeset");
	}

	return $self->ret('Error', "Can't perform name() function on a '$subject->{type}'");
}

sub function_starts_with {
	my ($self, $input, $args) = @_;

	my $s1 = $args->[0]->{value};
	my $s2 = $args->[1]->{value};

	return $self->ret('boolean', (substr($s1, 0, length $s2) eq $s2));
}

sub function_contains {
	my ($self, $input, $args) = @_;

	my $s1 = $args->[0]->{value};
	my $s2 = quotemeta $args->[1]->{value};

	return $self->ret('boolean', ($s1 =~ /$s2/));
}

sub function_string_length {
	my ($self, $input, $args) = @_;

	my $value = $args->[0];

	unless (defined $value){
		$value = $input->get_string;
		return $value if $value->is_error;
	}

	return $self->ret('number', length $value->{value});
}

sub compare_op {
	my ($self, $op, $a1, $a2) = @_;

	if ($a1->{type} eq 'string'){
		if ($op eq '=' ){ return $self->ret('boolean', ($a1->{value} eq $a2->{value}) ? 1 : 0); }
		if ($op eq '!='){ return $self->ret('boolean', ($a1->{value} ne $a2->{value}) ? 1 : 0); }
		if ($op eq '>='){ return $self->ret('boolean', ($a1->{value} ge $a2->{value}) ? 1 : 0); }
		if ($op eq '<='){ return $self->ret('boolean', ($a1->{value} le $a2->{value}) ? 1 : 0); }
		if ($op eq '>' ){ return $self->ret('boolean', ($a1->{value} gt $a2->{value}) ? 1 : 0); }
		if ($op eq '<' ){ return $self->ret('boolean', ($a1->{value} lt $a2->{value}) ? 1 : 0); }
	}

	if ($a1->{type} eq 'number'){
		if ($op eq '=' ){ return $self->ret('boolean', ($a1->{value} == $a2->{value}) ? 1 : 0); }
		if ($op eq '!='){ return $self->ret('boolean', ($a1->{value} != $a2->{value}) ? 1 : 0); }
		if ($op eq '>='){ return $self->ret('boolean', ($a1->{value} >= $a2->{value}) ? 1 : 0); }
		if ($op eq '<='){ return $self->ret('boolean', ($a1->{value} <= $a2->{value}) ? 1 : 0); }
		if ($op eq '>' ){ return $self->ret('boolean', ($a1->{value} >  $a2->{value}) ? 1 : 0); }
		if ($op eq '<' ){ return $self->ret('boolean', ($a1->{value} <  $a2->{value}) ? 1 : 0); }
	}

	return $self->ret('Error', "Don't know how to compare $op on type $a1->{type}");
}

1;
