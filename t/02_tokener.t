use XML::Parser::Lite::Tree::XPath::Test;
use XML::Parser::Lite::Tree::XPath::Tokener;

my $paths = load_paths('paths.txt');

plan(tests => scalar(@{$paths}));

my $tokener = XML::Parser::Lite::Tree::XPath::Tokener->new();

for my $path(@{$paths}){
	ok($tokener->parse($path));
}



