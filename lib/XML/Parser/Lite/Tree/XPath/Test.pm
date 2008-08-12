package XML::Parser::Lite::Tree::XPath::Test;

use strict;
use vars qw(@ISA @EXPORT);
use Test::More;

use XML::Parser::Lite::Tree;
use XML::Parser::Lite::Tree::XPath;

require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw(set_xml test_tree test_nodeset test_number);

our $xpath;

sub set_xml {
	my ($xml) = @_;

	$xml =~ s/>\s+</></sg;
	$xml =~ s/^\s*(.*?)\s*$/$1/;

	my $tree = XML::Parser::Lite::Tree::instance()->parse($xml);
	$xpath = new XML::Parser::Lite::Tree::XPath($tree);
}

sub test_tree {
	my ($path, $dump) = @_;

	my $tokener = XML::Parser::Lite::Tree::XPath::Tokener->new();
	if (!$tokener->parse($path)){
		print "Path: $path\n";
		print "Failed toke: ($tokener->{error})\n";
		ok(0);
		return;
	}

	my $tree = XML::Parser::Lite::Tree::XPath::Tree->new();
	if (!$tree->build_tree($tokener->{tokens})){
		print "Path: $path\n";
		print "Failed tree: ($tree->{error})\n";
		#print Dumper $tree;
		ok(0);
		return;
	}

	my $dump_got = $tree->dump_flat();

	ok($dump_got eq $dump);

	unless ($dump_got eq $dump){
		print "Path:     $path\n";
		print "Expected: $dump\n";
		print "Dump:     $dump_got\n";
		print $tree->dump_tree();
	}

	return $dump_got;
}

sub test_nodeset {
	my ($path, $expected) = @_;

	my $nodes = $xpath->select_nodes($path);

	unless ('ARRAY' eq ref $nodes){

		print "Error: $xpath->{error}\n";

		ok(0);
		ok(0) for @{$expected};
		return;
	}

	my $bad = 0;

	my $ok = scalar(@{$nodes}) == scalar(@{$expected});
	$bad++ unless $ok;
	ok($ok);

	my $i = 0;
	for my $xnode(@{$expected}){

		# $xnode is a hash ref which should match stuff in $nodes[$i]

		for my $key(keys %{$xnode}){

			if ($key eq 'nodename'){

				$ok = $nodes->[$i]->{name} eq $xnode->{$key};

			}elsif ($key eq 'attributecount'){

				$ok = scalar(keys %{$nodes->[$i]->{attributes}}) == $xnode->{$key};

			}elsif ($key eq 'type'){

				$ok = $nodes->[$i]->{type} eq $xnode->{$key};

			}else{
				$ok = $nodes->[$i]->{attributes}->{$key} eq $xnode->{$key};
			}

			$bad++ unless $ok;
			ok($ok);
		}

		$i++;
	}

	if ($bad){
		print "codes don't match. got:\n";
		for my $node(@{$nodes}){
			print "\t";
			print "($node->{type} : $node->{order}) ";
			print "$node->{name}";
			for my $key(keys %{$node->{attributes}}){
				print ", $key=$node->{attributes}->{$key}";
			}
			print "\n";
		}
		print "expected:\n";
		my $i = 1;
		for my $node(@{$expected}){
			print "\t$i";
			for my $key(keys %{$node}){
				print ", $key={$node->{$key}}";
			}
			print "\n";
			$i++;
		}
	}
}

sub test_number {
	my ($path, $expected) = @_;

	my $ret = $xpath->query($path);

	if (!$ret){
		print "Error: $xpath->{error}\n";
		ok(0);
		ok(0);
		return;
	}

	ok($ret->{type} eq 'number');

	if ($ret->{type} eq 'number'){
		ok($ret->{value} == $expected);

		if ($ret->{value} != $expected){
			print "expected $expected, got $ret->{value}\n";
		}
	}else{
		print "got a $ret->{type} result\n";
		ok(0);
	}
}

1;
