use Test::More tests => 18;

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
# Function: string string(object?)
# The string function converts an object to a string as follows: ...
#

test_string('string()', ''); # the context - the root node
test_string('string(/aaa)', '');
test_string('string(0)', '0');
test_string('string(1)', '1');
test_string('string(1.1)', '1.1');
test_string('string(-3)', '-3');
test_string('string(true)', 'true');
test_string('string(false)', 'false');
test_string('string("woo")', 'woo');


#
# Function: string concat(string, string, string*)
# The concat function returns the concatenation of its arguments.
#

#
# Function: boolean starts-with(string, string)
# The starts-with function returns true if the first argument string starts with the second
# argument string, and otherwise returns false.
#

#
# Function: boolean contains(string, string)
# The contains function returns true if the first argument string contains the second argument
# string, and otherwise returns false.
#

#
# Function: string substring-before(string, string)
# The substring-before function returns the substring of the first argument string that precedes
# the first occurrence of the second argument string in the first argument string, or the empty 
# string if the first argument string does not contain the second argument string.
#

#
# Function: string substring-after(string, string)
# The substring-after function returns the substring of the first argument string that follows 
# the first occurrence of the second argument string in the first argument string, or the empty 
# string if the first argument string does not contain the second argument string. 
#

#
# Function: string substring(string, number, number?)
# The substring function returns the substring of the first argument starting at the position
# specified in the second argument with length specified in the third argument.
#

#
# Function: number string-length(string?)
# The string-length returns the number of characters in the string (see [3.6 Strings]). 
#

#
# Function: string normalize-space(string?)
# The normalize-space function returns the argument string with whitespace normalized by 
# stripping leading and trailing whitespace and replacing sequences of whitespace characters 
# by a single space. 
#

#
# Function: string translate(string, string, string)
# The translate function returns the first argument string with occurrences of characters in 
# the second argument string replaced by the character at the corresponding position in the third 
# argument string.
#

