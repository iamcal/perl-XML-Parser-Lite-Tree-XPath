use Test::More tests => 18;

use lib 'lib';
use strict;
use XML::Parser::Lite::Tree::XPath::Test;

use Data::Dumper;

#
# all functions are defined here:
# http://www.w3.org/TR/xpath#corelib
#

set_xml(q!
	<aaa>
		<bbb id="b1" />
		<bbb id="b2">
			<ddd id="d1" />
			<ddd id="d2" />
		</bbb>
		<bbb foo="bar">
			<ccc />
		</bbb>
	</aaa>
!);


#
# Function: number last()
# The last function returns a number equal to the context size from the expression evaluation context.
#

test_nodeset(
	'//bbb[last()]',
	[
		{'nodename' => 'bbb', 'foo' => 'bar'},
	]
);


#
# Function: number position()
# The position function returns a number equal to the context position from the expression evaluation context.
#

test_nodeset(
	'//bbb[position() = 1]',
	[
		{'nodename' => 'bbb', id => 'b1'},
	]
);


#
# Function: number count(node-set)
# The count function returns the number of nodes in the argument node-set.
#

test_nodeset(
	'//bbb[count(*) = 2]',
	[
		{'nodename' => 'bbb', id => 'b2'},
	]
);


#
# Function: node-set id(object)
# The id function selects elements by their unique ID
#

test_nodeset(
	'//bbb[id("b2")]',
	[
	]
);

test_nodeset(
	'//bbb[id("b1 b2")]',
	[
	]
);

test_nodeset(
	'//bbb[id(//*)]',
	[
	]
);



#
# Function: string local-name(node-set?)
# The local-name function returns the local part of the expanded-name of the node in the argument node-set that is first in document order.
#

#
# Function: string namespace-uri(node-set?)
# The namespace-uri function returns the namespace URI of the expanded-name of the node in the argument node-set that is first in document order.
#

#
# Function: string name(node-set?)
# The name function returns a string containing a QName representing the expanded-name of the node in the argument node-set that is first in document order.
#




