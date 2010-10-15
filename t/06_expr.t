use Test::More tests => 31;

use lib 'lib';
use strict;
use XML::Parser::Lite::Tree::XPath::Test;

use Data::Dumper;

set_xml(q!
	<aaa id="a1">
		<bbb id="b1" />
		<ccc id="c1" />
		<bbb id="b2" />
		<ddd>
			<bbb id="b3" />
		</ddd>
		<ccc id="c2" />
	</aaa>
!);

# super simple
test_number('1', 1);
test_number('-3', -3);

# ops
test_number('1+1', 2);
test_number('2-1', 1);
test_number('2*2', 4);
test_number('4 div 2', 2);

# spacing
test_number('1 +1', 2);
test_number('1+ 1', 2);
test_number('1 + 1', 2);

# mod
test_number('5 mod 2', 1);
test_number('5 mod -2', 1);
test_number('-5 mod 2', -1);
test_number('-5 mod -2', -1);

test_tree('-1',	  '[UnaryExpr:-[Number:1]]');
test_tree('2-1',  '[AdditiveExpr:-[Number:2][Number:1]]');
test_tree('2 -1', '[AdditiveExpr:-[Number:2][Number:1]]');
test_tree('2- 1', '[AdditiveExpr:-[Number:2][Number:1]]');
test_tree('2--1', '[AdditiveExpr:-[Number:2][UnaryExpr:-[Number:1]]]');

#
# IEEE 754
# http://java.sun.com/docs/books/jls/second_edition/html/typesValues.doc.html#9208
#

print "starting -0 test...\n";
test_tree('1 div -0', '[MultiplicativeExpr:div[Number:1][UnaryExpr:-[Number:1]]]');
print "ok!\n";

test_number('1 div 0', 'Infinity');
test_number('1 div -0', '-Infinity');
test_number('0 div 0', 'NaN');
test_number('(1 div 0) * 0', 'NaN');

test_boolean('1 < (0 div 0)', 0);
test_boolean('1 > (0 div 0)', 0);
test_boolean('5 <= (0 div 0)', 0);
test_boolean('5 >= (0 div 0)', 0);
test_boolean('(0 div 0) > (0 div 0)', 0);

test_boolean('1 == (0 div 0)', 0);
test_boolean('(0 div 0) == (0 div 0)', 0);

test_boolean('1 != (0 div 0)', 1);
test_boolean('(0 div 0) != (0 div 0)', 1);

test_boolean('1 < (1 div 0)', 1);
test_boolean('0 < 1', 1);
test_boolean('-1 < 0', 1);
test_boolean('(1 div -0) < -1', 1);


#
# More IEEE 754
# http://en.wikipedia.org/wiki/%E2%88%920_%28number%29
#

test_number('-0 div (1 div 0)', '-0');
test_number('-0 * -0', '0');
test_number('(1 div 0) * -0', '-0');

test_number('1 + -0', 1);
test_number('0 + -0', '-0');
test_number('-0 + -0', '-0');
test_number('-0 - 0', '-0');
test_number('0 + 0', '0');
test_number('0 - -0', '0');

test_number('-0 div (1 div -0)', '0');
test_number('(1 div 0) div -0', '-Infinity');
test_number('0 * (1 div 0)', 'NaN');
test_number('-0 * (1 div 0)', 'NaN');
test_number('0 * (1 div -0)', 'NaN');
test_number('-0 * (1 div -0)', 'NaN');
test_number('0 / 0', 'NaN');
test_number('0 / -0', 'NaN');
test_number('-0 / 0', 'NaN');
test_number('-0 / -0', 'NaN');

test_boolean('0 == -0', 1);

