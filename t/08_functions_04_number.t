use Test::More tests => 40;

use lib 'lib';
use strict;
use XML::Parser::Lite::Tree::XPath::Test;

#
# all functions are defined here:
# http://www.w3.org/TR/xpath#corelib
#

set_xml(q!
	<aaa>
		<bbb/>
		<bbb>woo</bbb>
		<bbb>yay</bbb>
	</aaa>
!);


#
# IEEE 754
# http://java.sun.com/docs/books/jls/second_edition/html/typesValues.doc.html#9208
#

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


#
# Operator: mod
#

test_number('5 mod 2', 1);
test_number('5 mod -2', 1);
test_number('-5 mod 2', -1);
test_number('-5 mod -2', -1);



#
# Function: number number(object?)
# The number function converts its argument to a number as follows: ...
#

#
# Function: number sum(node-set)
# The sum function returns the sum, for each node in the argument node-set, of the
# result of converting the string-values of the node to a number.
#

#
# Function: number floor(number)
# The floor function returns the largest (closest to positive infinity) number that
# is not greater than the argument and that is an integer.
#

#
# Function: number ceiling(number)
# The ceiling function returns the smallest (closest to negative infinity) number
# that is not less than the argument and that is an integer.
#

#
# Function: number round(number)
# The round function returns the number that is closest to the argument and that is
# an integer. 
#
