use Test::More tests => 34;

use lib 'lib';
use strict;
use XML::Parser::Lite::Tree::XPath::Tokener;


my @paths = split /\n/, <<PATHS
child::para
child::*
child::text()
child::node()
attribute::name
attribute::*
descendant::para
ancestor::div
ancestor-or-self::div
descendant-or-self::para
self::para
child::chapter/descendant::para
child::*/child::para
/
/descendant::para
/descendant::olist/child::item
child::para[position()=1]
child::para[position()=last()]
child::para[position()=last()-1]
child::para[position()>1]
following-sibling::chapter[position()=1]
preceding-sibling::chapter[position()=1]
/descendant::figure[position()=42]
/child::doc/child::chapter[position()=5]/child::section[position()=2]
child::para[attribute::type="warning"]
child::para[attribute::type='warning'][position()=5]
child::para[position()=5][attribute::type="warning"]
child::chapter[child::title='Introduction']
child::chapter[child::title]
child::*[self::chapter or self::appendix]
child::*[self::chapter or self::appendix][position()=last()]
)))))
(((((
]][[
PATHS
;

my $tokener = XML::Parser::Lite::Tree::XPath::Tokener->new();

for my $path(@paths){
	ok($tokener->parse($path));
}
