package XML::Parser::Lite::Tree::XPath::Tree;

use strict;
use XML::Parser::Lite::Tree::XPath::Tokener;

sub new {
	my ($class) = @_;
	my $self = bless {}, $class;
	$self->{error} = 0;
	return $self;
}

sub build_tree {
	my ($self, $tokens) = @_;

	$self->{error} = 0;
	$self->{tokens} = $tokens;

	#
	# build a basic tree using the brackets
	#

	return 0 unless $self->make_groups();
	return 0 unless $self->recurse_before($self, 'clean_axis_and_abbreviations');
	return 0 unless $self->recurse_before($self, 'claim_groups');
	return 0 unless $self->recurse_after($self, 'build_steps');

	return 1;
}

sub make_groups {
	my ($self) = @_;

	my $tokens = $self->{tokens};
	$self->{tokens} = [];

	my $parent = $self;

	for my $token(@{$tokens}){

		if ($token->match('Symbol', '(')){

			my $group = XML::Parser::Lite::Tree::XPath::Tokener::Token->new();
			$group->{type} = 'Group()';
			$group->{tokens} = [];
			$group->{parent} = $parent;

			push @{$parent->{tokens}}, $group;
			$parent = $group;

		}elsif ($token->match('Symbol', '[')){

			my $group = XML::Parser::Lite::Tree::XPath::Tokener::Token->new();
			$group->{type} = 'Predicate';
			$group->{tokens} = [];
			$group->{parent} = $parent;

			push @{$parent->{tokens}}, $group;
			$parent = $group;

		}elsif ($token->match('Symbol', ')')){

			if ($parent->{type} ne 'Group()'){
				$self->{error} = "Found unexpected closing bracket ')'.";
				return 0;
			}

			$parent = $parent->{parent};

		}elsif ($token->match('Symbol', ']')){

			if ($parent->{type} ne 'Predicate'){
				$self->{error} = "Found unexpected closing bracket ']'.";
				return 0;
			}

			$parent = $parent->{parent};

		}else{
			$token->{parent} = $parent;
			push @{$parent->{tokens}}, $token;
		}
	}

	return 1;
}

sub recurse_before {
	my ($self, $root, $method) = @_;

	return 0 unless $self->$method($root);

	for my $token(@{$root->{tokens}}){

		return 0 unless $self->recurse_before($token, $method);
	}

	return 1;
}

sub recurse_after {
	my ($self, $root, $method) = @_;

	for my $token(@{$root->{tokens}}){

		return 0 unless $self->recurse_after($token, $method);
	}

	return 0 unless $self->$method($root);

	return 1;
}

sub claim_groups {
	my ($self, $root) = @_;

	my $tokens = $root->{tokens};
	$root->{tokens} = [];

	while(my $token = shift @{$tokens}){


		#
		# makes claims
		#

		if ($token->match('NodeType')){

			# node type's claim the follow group node

			my $next = shift @{$tokens};

			if (!$next->match('Group()')){
				$self->{error} = "Found NodeType '$token->{content}' without a following '(' (found a following '$next->{type}').";
				return 0;
			}

			my $childs = scalar(@{$next->{tokens}});

			if ($token->{content} eq 'processing-instruction'){

				if ($childs == 0){

					#ok

				}elsif ($childs == 1){

					if ($next->{tokens}->[0]->{type} eq 'Literal'){

						$token->{argument} = $next->{tokens}->[0]->{content};

					}else{
						$self->{error} = "processing-instruction node has a non-Literal child node (of type '$next->{tokens}->[0]->{type}').";
						return 0;
					}
				}else{
					$self->{error} = "processing-instruction node has more than one child node.";
					return 0;
				}

			}else{
				if ($childs > 0){
					$self->{error} = "NodeType $token->{content} node has unexpected children.";
					return 0;
				}
			}

			$token->{type} = 'NodeTypeTest';
			push @{$root->{tokens}}, $token;

		}elsif ($token->match('FunctionName')){

			# FunctionNames's claim the follow group node - it should be an arglist

			my $next = shift @{$tokens};

			if (!$next->match('Group()')){
				$self->{error} = "Found FunctionName '$token->{content}' without a following '(' (found a following '$next->{type}').";
				return 0;
			}

			#
			# recurse manually - this node will never be scanned by this loop
			#

			return 0 unless $self->claim_groups($next);

			#
			# organise it into an arg list
			#

			return 0 unless $self->make_arg_list($token, $next);

			push @{$root->{tokens}}, $token;


		}elsif ($token->match('Group()')){

			$token->{type} = 'Expression';

			push @{$root->{tokens}}, $token;

		}else{

			push @{$root->{tokens}}, $token;
		}

	}

	return 1;
}

sub make_arg_list {
	my ($self, $root, $arg_group) = @_;

	$root->{type} = 'FunctionCall';
	$root->{tokens} = [];

	# no need to construct an arg list if there aren't any args
	return 1 unless scalar @{$arg_group->{tokens}};

	my $arg = XML::Parser::Lite::Tree::XPath::Tokener::Token->new();
	$arg->{type} = 'FunctionArg';
	$arg->{tokens} = [];

	while(my $token = shift @{$arg_group->{tokens}}){

		if ($token->match('Symbol', ',')){

			push @{$root->{args}}, $arg;
		}else{

			$token->{parent} = $arg;
			push @{$arg->{tokens}}, $token;
		}
	}

	$arg->{parent} = $root;
	push @{$root->{tokens}}, $arg;
	

	return 1;
}

sub clean_axis_and_abbreviations {

	my ($self, $root) = @_;

	my $tokens = $root->{tokens};
	$root->{tokens} = [];

	while(my $token = shift @{$tokens}){

		if ($token->match('AxisName')){

			my $next = shift @{$tokens};

			unless ($next->match('Symbol', '::')){

				$self->{error} = "Found an AxisName '$token->{content}' without a following ::";
				return 0;
			}

			$token->{type} = 'AxisSpecifier';
			$token->{content} .= '::';

			push @{$root->{tokens}}, $token;


		}elsif ($token->match('Symbol', '@')){

			$token->{type} = 'AxisSpecifier';
			$token->{content} = 'attribute::';

			push @{$root->{tokens}}, $token;


		}elsif ($token->match('Operator', '//')){

			# // == /descendant-or-self::node()/

			my $token = XML::Parser::Lite::Tree::XPath::Tokener::Token->new();
			$token->{type} = 'Symbol';
			$token->{content} = '/';
			push @{$root->{tokens}}, $token;

			my $token = XML::Parser::Lite::Tree::XPath::Tokener::Token->new();
			$token->{type} = 'AxisSpecifier';
			$token->{content} = 'descendant-or-self::';
			push @{$root->{tokens}}, $token;

			my $token = XML::Parser::Lite::Tree::XPath::Tokener::Token->new();
			$token->{type} = 'NodeTypeTest';
			$token->{content} = 'node';
			push @{$root->{tokens}}, $token;

			my $token = XML::Parser::Lite::Tree::XPath::Tokener::Token->new();
			$token->{type} = 'Symbol';
			$token->{content} = '/';
			push @{$root->{tokens}}, $token;


		}elsif ($token->match('Symbol', '.')){

			my $token = XML::Parser::Lite::Tree::XPath::Tokener::Token->new();
			$token->{type} = 'AxisSpecifier';
			$token->{content} = 'self::';
			push @{$root->{tokens}}, $token;

			my $token = XML::Parser::Lite::Tree::XPath::Tokener::Token->new();
			$token->{type} = 'NodeTypeTest';
			$token->{content} = 'node';
			push @{$root->{tokens}}, $token;


		}elsif ($token->match('Symbol', '..')){

			my $token = XML::Parser::Lite::Tree::XPath::Tokener::Token->new();
			$token->{type} = 'AxisSpecifier';
			$token->{content} = 'parent::';
			push @{$root->{tokens}}, $token;

			my $token = XML::Parser::Lite::Tree::XPath::Tokener::Token->new();
			$token->{type} = 'NodeTypeTest';
			$token->{content} = 'node';
			push @{$root->{tokens}}, $token;


		}else{

			push @{$root->{tokens}}, $token;
		}
	}

	return 1;
}

sub build_steps {
	my ($self, $root) = @_;

	my $tokens = $root->{tokens};
	$root->{tokens} = [];

	while(my $token = shift @{$tokens}){

		if ($token->match('AxisSpecifier')){

			my $next = shift @{$tokens};

			unless (defined $next){

				$self->{error} = "AxisSpecifier found without following NodeTest.";
				return 0;
			}

			unless ($next->match('NodeTypeTest') || $next->match('NameTest')){

				$self->{error} = "AxisSpecifier found without following NodeTest (NodeTypeTest | NameTest) (found $next->{type} instead).";
				return 0;
			}

			my $step = XML::Parser::Lite::Tree::XPath::Tokener::Token->new();
			$step->{type} = 'Step';
			$step->{tokens} = [];

			push @{$step->{tokens}}, $token;
			push @{$step->{tokens}}, $next;


			while(my $token = shift @{$tokens}){

				if ($token->match('Predicate')){

					push @{$step->{tokens}}, $token;
				}else{
					unshift @{$tokens}, $token;
					last;
				}
			}

			push @{$root->{tokens}}, $step;


		}elsif ($token->match('NodeTypeTest') || $token->match('NameTest')){

			my $step = XML::Parser::Lite::Tree::XPath::Tokener::Token->new();
			$step->{type} = 'Step';
			$step->{tokens} = [];

			push @{$step->{tokens}}, $token;


			while(my $token = shift @{$tokens}){

				if ($token->match('Predicate')){

					push @{$step->{tokens}}, $token;
				}else{
					unshift @{$tokens}, $token;
					last;
				}
			}

			push @{$root->{tokens}}, $step;


		}elsif ($token->match('Predicate')){

			$self->{error} = "Predicate found without preceeding NodeTest.";
			return 0;

		}else{

			push @{$root->{tokens}}, $token;
		}
	}

	return 1;
}

sub expression_binops {

	my ($self, $root) = @_;

	return 1;	
}

1;
