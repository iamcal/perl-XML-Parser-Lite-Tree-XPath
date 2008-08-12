package XML::Parser::Lite::Tree::XPath::Token;

use strict;
use XML::Parser::Lite::Tree::XPath::Result;
use XML::Parser::Lite::Tree::XPath::Axis;
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

sub is_expression {
	my ($self) = @_;

	return 1 if $self->{type} eq 'Number';
	return 1 if $self->{type} eq 'Literal';
	return 0 if $self->{type} eq 'Operator';

	warn "Not sure if $self->{type} is an expression";

	return 0;
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
	my ($self, $context) = @_;

	return $context if $context->is_error;
	$self->{context} = $context;

	if ($self->{type} eq 'LocationPath'){

		# a LocationPath should just be a list of Steps, so eval them in order

		my $ret;

		if ($self->{absolute}){
			$ret = $self->{root};
		}else{
			$ret = $context->get_nodeset;
			return $ret if $ret->is_error;
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

		# my $axis = defined($self->{axis}) ? $self->{axis} : 'child';
		# my $ret = $self->filter_axis($axis, $context);

		my $ret = XML::Parser::Lite::Tree::XPath::Axis::instance->filter($self, $context);

		for my $step(@{$self->{tokens}}){

			unless ($step->match('AxisSpecifier') || $step->match('NameTest') || $step->match('Predicate') || $step->match('NodeTypeTest')){

				return $self->ret('Error', "Found an unexpected token ('$step->{type}') in a Step");
			}

			$ret = $step->eval($ret);

			return $ret if $ret->is_error;
		}

		return $ret;


	}elsif ($self->{type} eq 'NameTest'){

		return $context if $self->{content} eq '*';

		if ($self->{content} =~ m!\:\*$!){
			return $self->ret('Error', "Can't do NCName:* NameTests");
		}

		if ($context->{type} eq 'nodeset'){
			my $out = $self->ret('nodeset', []);

			for my $tag(@{$context->{value}}){

				if (($tag->{'type'} eq 'tag') && ($tag->{'name'} eq $self->{content})){
					push @{$out->{value}}, $tag;
				}

				if (($tag->{'type'} eq 'attribute') && ($tag->{'name'} eq $self->{content})){
					push @{$out->{value}}, $tag;
				}
			}

			return $out;
		}

		return $self->ret('Error', "filter by name $self->{content} on context $context->{type}");


	}elsif ($self->{type} eq 'NodeTypeTest'){

		if ($self->{content} eq 'node'){
			if ($context->{type} eq 'nodeset'){
				return $context;
			}else{
				return $self->ret('Error', "can't filter node() on a non-nodeset value.");
			}
		}

		return $self->ret('Error', "NodeTypeTest with an unknown filter ($self->{content})");


	}elsif ($self->{type} eq 'Predicate'){

		my $expr = $self->{tokens}->[0];

		my $out = $self->ret('nodeset', []);
		my $i = 1;
		my $c = scalar @{$context->{value}};

		for my $child(@{$context->{value}}){

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

			}elsif ($ret->{type} eq 'nodeset'){

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

				my $out = $source->eval($context);
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

		return &{$func}($self, \@args);

	}elsif ($self->{type} eq 'FunctionArg'){

		# a FunctionArg should have a single child

		return $self->ret('Error', 'FunctionArg should have 1 token') unless 1 == scalar @{$self->{tokens}};

		return $self->{tokens}->[0]->eval($context);

	}elsif (($self->{type} eq 'EqualityExpr') || ($self->{type} eq 'RelationalExpr')){

		my $v1 = $self->{tokens}->[0]->eval($context);
		my $v2 = $self->{tokens}->[1]->eval($context);
		my $t = "$v1->{type}/$v2->{type}";

		return $v1 if $v1->is_error;
		return $v2 if $v2->is_error;

		if ($v1->{type} gt $v2->{type}){
			$t = "$v2->{type}/$v1->{type}";
			($v1, $v2) = ($v2, $v1);
		}

		if ($t eq 'nodeset/string'){

			for my $node(@{$v1->{value}}){;

				my $v1_s = $self->ret('node', $node)->get_string;
				return $v1_s if $v1_s->is_error;

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

		my $a1 = $self->get_child_arg(0, 'nodeset');
		my $a2 = $self->get_child_arg(1, 'nodeset');

		return $a1 if $a1->is_error;
		return $a2 if $a2->is_error;

		my $out = $self->ret('nodeset', []);

		map{ push @{$out->{value}}, $_ } @{$a1->{value}};
		map{ push @{$out->{value}}, $_ } @{$a2->{value}};

		$out->normalize();

		return $out;

	}elsif ($self->{type} eq 'MultiplicativeExpr'){

		my $a1 = $self->get_child_arg(0, 'number');
		my $a2 = $self->get_child_arg(1, 'number');

		return $a1 if $a1->is_error;
		return $a2 if $a2->is_error;

		my $result = 0;
		$result = $a1->{value} * $a2->{value} if $self->{content} eq '*';
		$result = $self->op_mod($a1->{value}, $a2->{value}) if $self->{content} eq 'mod';
		$result = $self->op_div($a1->{value}, $a2->{value}) if $self->{content} eq 'div';

		return $self->ret('number', $result);

	}elsif (($self->{type} eq 'OrExpr') || ($self->{type} eq 'AndExpr')){

		my $a1 = $self->get_child_arg(0, 'boolean');
		my $a2 = $self->get_child_arg(1, 'boolean');

		return $a1 if $a1->is_error;
		return $a2 if $a2->is_error;

		return $self->ret('boolean', $a1->{value} || $a2->{value}) if $self->{type} eq 'OrExpr';
		return $self->ret('boolean', $a1->{value} && $a2->{value}) if $self->{type} eq 'AndExpr';

	}elsif ($self->{type} eq 'AdditiveExpr'){

		my $a1 = $self->get_child_arg(0, 'number');
		my $a2 = $self->get_child_arg(1, 'number');

		return $a1 if $a1->is_error;
		return $a2 if $a2->is_error;

		my $result = 0;
		$result = $a1->{value} + $a2->{value} if $self->{content} eq '+';
		$result = $a1->{value} - $a2->{value} if $self->{content} eq '-';

		return $self->ret('number', $result);

	}elsif ($self->{type} eq 'UnaryExpr'){

		my $a1 = $self->get_child_arg(0, 'number');

		return $a1 if $a1->is_error;

		$a1->{value} = - $a1->{value};

		return $a1;

	}else{
		return $self->ret('Error', "Don't know how to eval a '$self->{type}' node.");
	}
}

sub get_child_arg {
	my ($self, $pos, $type) = @_;

	my $token = $self->{tokens}->[$pos];
	return $self->ret('Error', "Required child token {1+$pos} for $self->{type} token wasn't found.") unless defined $token;

	my $out = $token->eval($self->{context});
	return $out if $out->is_error;

	return $out->get_type($type);
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
	my ($self, $args) = @_;

	return $self->ret('number', $self->{context}->{value}->{context_size});
}

sub function_not {
	my ($self, $args) = @_;

	my $out = $args->[0];
	$out->{value} = !$out->{value};

	return $out
}

sub function_normalize_space {
	my ($self, $args) = @_;

	my $value = $args->[0];

	unless (defined $value){
		$value = $self->{context}->get_string;
		return $value if $value->get_error;
	}

	$value = $value->{value};
	$value =~ s!^[\x20\x09\x0d\x0a]+!!;
	$value =~ s![\x20\x09\x0d\x0a]+$!!;
	$value =~ s![\x20\x09\x0d\x0a]+! !g;

	return $self->ret('string', $value);
}

sub function_count {
	my ($self, $args) = @_;

	my $subject = $args->[0];

	return $self->ret('number', scalar(@{$subject->{value}})) if $subject->{type} eq 'nodeset';

	die("can't perform count() on $subject->{type}");
}

sub function_name {
	my ($self, $args) = @_;

	my $subject;

	if (defined $args->[0]){
		$subject = $args->[0]->eval($self->{context});
		return $subject if $subject->is_error;
	}else{
		$subject = $self->{context};
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
	my ($self, $args) = @_;

	my $s1 = $args->[0]->{value};
	my $s2 = $args->[1]->{value};

	return $self->ret('boolean', (substr($s1, 0, length $s2) eq $s2));
}

sub function_contains {
	my ($self, $args) = @_;

	my $s1 = $args->[0]->{value};
	my $s2 = quotemeta $args->[1]->{value};

	return $self->ret('boolean', ($s1 =~ /$s2/));
}

sub function_string_length {
	my ($self, $args) = @_;

	my $value = $args->[0];

	unless (defined $value){
		$value = $self->{context}->get_string;
		return $value if $value->is_error;
	}

	return $self->ret('number', length $value->{value});
}

sub function_position {
	my ($self, $args) = @_;

	my $node = $self->{context}->get_nodeset;
	return $node if $node->is_error;

	$node = $node->{value}->[0];
	return $self->ret('Error', "No node in context nodeset o_O") unless defined $node;

	return $self->ret('number', $node->{proximity_position});
}

sub function_floor {
	my ($self, $args) = @_;

	my $val = $args->[0]->{value};
	my $ret = $self->simple_floor($val);

	$ret = - $self->simple_ceiling(-$val) if $val < 0;

	return $self->ret('number', $ret);
}

sub function_ceiling {
	my ($self, $args) = @_;

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
