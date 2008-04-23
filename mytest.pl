#!/usr/bin/perl -w

use strict;
use Data::Dumper;
use lib 'lib';
use XML::Parser::Lite::Tree::XPath::Parser;

my $parser = XML::Parser::Lite::Tree::XPath::Parser->new();
print Dumper $parser->parse('//a/b[1]');
print Dumper \$parser;
