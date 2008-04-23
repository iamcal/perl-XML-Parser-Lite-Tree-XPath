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

		if ((!defined $handler) || (!defined $handler->[0])){
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


	}elsif ($self->{type} eq 'UnionExpr'){

		my $a1 = $self->{tokens}->[0]->eval($input);
		my $a2 = $self->{tokens}->[1]->eval($input);

		return $a1 if $a1->is_error;
		return $a2 if $a2->is_error;

		$a1 = $a1->get_nodeset;
		$a2 = $a2->get_nodeset;

		return $a1 if $a1->is_error;
		return $a2 if $a2->is_error;

		my $out = $self->ret('nodeset', []);

		map{ push @{$out->{value}}, $_ } @{$a1->{value}};
		map{ push @{$out->{value}}, $_ } @{$a2->{value}};

		$out->normalize();

		return $out;

	}elsif ($self->{type} eq 'MultiplicativeExpr'){

		my $a1 = $self->get_child_arg($input, 0, 'number');
		my $a2 = $self->get_child_arg($input, 1, 'number');

		return $a1 if $a1->is_error;
		return $a2 if $a2->is_error;

		my $result = 0;
		$result = $a1->{value} * $a2->{value} if $self->{content} eq '*';
		$result = $self->op_mod($a1->{value}, $a2->{value}) if $self->{content} eq 'mod';
		$result = $self->op_div($a1->{value}, $a2->{value}) if $self->{content} eq 'div';

		return $self->ret('number', $result);

	}elsif (($self->{type} eq 'OrExpr') || ($self->{type} eq 'AndExpr')){

		my $a1 = $self->get_child_arg($input, 0, 'boolean');
		my $a2 = $self->get_child_arg($input, 1, 'boolean');

		return $a1 if $a1->is_error;
		return $a2 if $a2->is_error;

		return $self->ret('boolean', $a1->{value} || $a2->{value}) if $self->{type} eq 'OrExpr';
		return $self->ret('boolean', $a1->{value} && $a2->{value}) if $self->{type} eq 'AndExpr';

	}elsif ($self->{type} eq 'AdditiveExpr'){

		my $a1 = $self->get_child_arg($input, 0, 'number');
		my $a2 = $self->get_child_arg($input, 1, 'number');

		return $a1 if $a1->is_error;
		return $a2 if $a2->is_error;

		my $result = 0;
		$result = $a1->{value} + $a2->{value} if $self->{content} eq '+';
		$result = $a1->{value} - $a2->{value} if $self->{content} eq '-';

		return $self->ret('number', $result);

	}else{
		return $self->ret('Error', "Don't know how to eval a '$self->{type}' node.");
	}
}

sub get_child_arg {
	my ($self, $context, $pos, $type) = @_;

	my $token = $self->{tokens}->[$pos];
	return $self->ret('Error', "Required child token {1+$pos} for $self->{type} token wasn't found.") unless defined $token;

	my $out = $token->eval($context);
	return $out if $out->is_error;

	my $ret = undef;
	$ret = $out->get_number if $type eq 'number';
	$ret = $out->get_boolean if $type eq 'boolean';

	return $self->ret('Error', "Can't convert token child to type $type") unless defined $ret;

	return $ret;
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

sub _axis_parent {
	my ($self, $in) = @_;

	my $out = $self->ret('nodeset', []);

	for my $tag(@{$in->{value}}){
		push @{$out->{value}}, $tag->{parent} if defined $tag->{parent};
	}

	return $out;
}

sub _axis_ancestor {
	my ($self, $in, $me) = @_;

	my $out = $self->ret('nodeset', []);

	for my $tag(@{$in->{value}}){

		map{
			push @{$out->{value}}, $_;

		}$self->_axis_ancestor_single($tag, $me);
	}

	return $out;
}

sub _axis_ancestor_single {
	my ($self, $tag, $me) = @_;

	my @out;

	push @out, $tag if $me;

	if (defined $tag->{parent}){

		map{
			push @out, $_;
		}$self->_axis_ancestor_single($tag->{parent}, 1);
	}

	return @out;	
}

sub _axis_following_sibling {
	my ($self, $in) = @_;

	my $out = $self->ret('nodeset', []);

	for my $tag(@{$in->{value}}){
		if (defined $tag->{parent}){
			my $parent = $tag->{parent};
			my $found = 0;
			for my $child(@{$parent->{children}}){
				push @{$out->{value}}, $child if $found;
				$found = 1 if $child->{order} == $tag->{order};
			}
		}
	}

	return $out;
}

sub _axis_preceding_sibling {
	my ($self, $in) = @_;

	my $out = $self->ret('nodeset', []);

	for my $tag(@{$in->{value}}){
		if (defined $tag->{parent}){
			my $parent = $tag->{parent};
			my $found = 0;
			for my $child(@{$parent->{children}}){
				$found = 1 if $child->{order} == $tag->{order};
				push @{$out->{value}}, $child unless $found;
			}
		}
	}

	return $out;
}

sub _axis_following {
	my ($self, $in) = @_;

	my $min_order  = 1 + $self->{max_order};
	for my $tag(@{$in->{value}}){
		$min_order = $tag->{order} if $tag->{order} < $min_order;
	}

	# recurse the whole tree, adding after we find $min_order (but don't descend into it!)

	my @tags = $self->_axis_following_recurse( $self->{root}->{value}->[0], $min_order );

	return $self->ret('nodeset', \@tags);
}

sub _axis_following_recurse {
	my ($self, $tag, $min) = @_;

	my @out;

	push @out, $tag if $tag->{order} > $min;

	for my $child(@{$tag->{children}}){

		if (($child->{order}) != $min && ($child->{type} eq 'tag')){

			map{
				push @out, $_;
			}$self->_axis_following_recurse($child, $min);
		}
	}

	return @out;
}

sub _axis_preceding {
	my ($self, $in) = @_;

	my $max_order = -1;
	my $parents;
	for my $tag(@{$in->{value}}){
		if ($tag->{order} > $max_order){
			$max_order = $tag->{order};
			$parents = $self->_get_parent_orders($tag);
		}
	}

	# recurse the whole tree, adding until we find $max_order (but don't descend into it!)

	my @tags = $self->_axis_preceding_recurse( $self->{root}->{value}->[0], $parents, $max_order );

	return $self->ret('nodeset', \@tags);
}

sub _axis_preceding_recurse {
	my ($self, $tag, $parents, $max) = @_;

	my @out;

	push @out, $tag if $tag->{order} < $max && !$parents->{$tag->{order}};

	for my $child(@{$tag->{children}}){

		if (($child->{order}) != $max && ($child->{type} eq 'tag')){

			map{
				push @out, $_;
			}$self->_axis_preceding_recurse($child, $parents, $max);
		}
	}

	return @out;
}

sub _get_parent_orders {
	my ($self, $tag) = @_;
	my $parents;

	while(defined $tag->{parent}){
		$tag = $tag->{parent};
		$parents->{$tag->{order}} = 1;
	}

	return $parents;
}

sub get_function_handler {
	my ($self, $function) = @_;

	my $function_map = {

		# nodeset functions
		'last'			=> [\&function_last,		''			],
		'position'		=> [\&function_position,	''			],
		'count'			=> [\&function_count,		'nodeset'		],
		'id'			=> [undef,			'any'			],
		'local-name'		=> [undef,			'nodeset?'		],
		'namespace-uri'		=> [undef,			'nodeset?'		],
		'name'			=> [\&function_name,		'nodeset?'		],

		# string functions
		'string'		=> [undef,			'any?'			],
		'concat'		=> [undef,			'string,string+'	],
		'starts-with'		=> [\&function_starts_with,	'string,string'		],
		'contains'		=> [\&function_contains,	'string,string'		],
		'substring-before'	=> [undef,			'string,string'		],
		'substring-after'	=> [undef,			'string,string'		],
		'substring'		=> [undef,			'string,number,number?'	],
		'string-length'		=> [\&function_string_length,	'string?'		],
		'normalize-space'	=> [\&function_normalize_space,	'string?'		],
		'translate'		=> [undef,			'string,string,string'	],

		# boolean functions
		'boolean'		=> [undef,			'any'			],
		'not'			=> [\&function_not,		'boolean'		],
		'true'			=> [undef,			''			],
		'false'			=> [undef,			''			],
		'lang'			=> [undef,			'string'		],

		# number functions
		'number'		=> [undef,			'any?'			],
		'sum'			=> [undef,			'nodeset'		],
		'floor'			=> [\&function_floor,		'number'		],
		'ceiling'		=> [\&function_ceiling,		'number'		],
		'round'			=> [undef,			'number'		],

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

sub function_position {
	my ($self, $input, $args) = @_;

	my $node = $input->get_nodeset;
	return $node if $node->is_error;

	$node = $node->{value}->[0];
	return $self->ret('Error', "No node in context nodeset o_O") unless defined $node;

	return $self->ret('number', $node->{proximity_position});
}

sub function_floor {
	my ($self, $input, $args) = @_;

	my $val = $args->[0]->{value};
	my $ret = $self->simple_floor($val);

	$ret = - $self->simple_ceiling(-$val) if $val < 0;

	return $self->ret('number', $ret);
}

sub function_ceiling {
	my ($self, $input, $args) = @_;

	my $val = $args->[0]->{value};
	my $ret = $self->simple_ceiling($val);

	$ret = - $self->simple_floor(-$val) if $val < 0;

	return $self->ret('number', $ret);
}

sub simple_floor {
	my ($self, $value) = @_;
	return int $value;
}

sub simple_ceiling {
	my ($self, $value) = @_;
	my $t = int $value;
	return $t if $t == $value;
	return $t+1;
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

sub op_mod {
	my ($self, $n1, $n2) = @_;

	my $r = int ($n1 / $n2);
	return $n1 - ($r * $n2);
}

sub op_div {
	my ($self, $n1, $n2) = @_;

	return $n1 / $n2;
}

1;
