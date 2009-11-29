
Matchmaker is a powerful and expressive DSL that
brings pattern matching into Ruby. Often we need
to check if an object is what we expect, and if
so, we want to take it apart. Pattern matching is
an expressive idiom from functional programming
languages to make checking on an object and taking
it apart concisely readable.

# Install

    > sudo gem install hayeah-matchmaker
    > irb -rubygems
    irb> require 'matchmaker'
    irb> Case(1) { of(1) }
    # => true

# Case Statement

A case statement can have many alternative
patterns to match. The patterns are run in
sequence until the first one that matches. If no
pattern matches, a `Case::NoMatch` exception is
raised.

    Case(1) {
     of(1)
     of(:b)
    } # => true

    Case(2) {
     of(1)
     of(:b)
    } # => raise Case::NoMatch

    Case(:b) {
     of(1)
     of(:b)
    } # => true

Matchmaker uses the Case DSL to build a runnable
pattern matcher. You can store the pattern matcher
in a constant or variable, so Matchmaker doesn't
have to build it everytime you use it.

    c = Case.new {
      of(1)
      of(:b)
    }
    c.match(1)  # => true
    c.match(0)  # => Case::NoMatch
    c.match(:b) # => true
    
For each pattern in the case statement, there can
be an action associated with it. The action is run
when the pattern of that branch matches, and the
result of the action returned:

    c = Case.new {
     of(1) { :a }
     of(2) { :b }
     of(3) # { true } by default
    }
    c.match(1) # => :a
    c.match(2) # => :b
    c.match(3) # => true

# Simple Patterns

Literals ruby objects are matched by `==`

    of(1)   # matches 1
    of(:a)  # matches :a
    of("a") # matches "a"

A regex is used to match string

    # matches "0abc0"
    of(/abc/) 

A class is used to match objects of the that class

    # matches "abc"
    of(String)

A range can be used to match a range of integers

    # matches integer within 1 and 10
    of(1..10) 

An array should be an array of patterns that
matches an array object, such that each element in
the array should match its pattern.

    # matches ["a",[],{}]
    of([String,Array,Hash]) 

# Destructuring and Pattern Guard

There are patterns to match common ruby
objects. For example, Case#string is a method of
the DSL to build the string pattern.

    of(string)        # matches any string
    of(string("a"))   # matches "a"
    of(string(/foo/)) # matches any string of that regexp

These pattern methods can make variable bindings
of the matched object,

    Case([1,"a"]) {
     of([1,string(/a/,:a)]) { a }
    } # => "a"

In this example, the pattern sets the variable
`:a` to the matched string. These variables are
actually bindings. Binding of the same name in
different patterns must equal to each other,
otherwise the overall pattern won't match.

    c = Case.new {
     of([string(/a/,:a),string(/b/,:a)])
    }
    c.match(["ab","ab"]) # => true
    c.match(["ab","ba"]) # Case::NoMatch

A guard is an arbitray ruby block associated with
a pattern, so that a pattern matches iff the guard
returns true.

    c = Case.new {
     of(string(/a/) {|s| s.length == 2 })
    }
    c.match("ab")  # => true
    c.match("ba")  # => true
    c.match("abc") # Case::NoMatch

# Value Patterns

These patterns are used to match a single Ruby
object. See later for structural patterns for ways
to combine these value patterns. All these methods
can make binding and take a guard, as in

    of(some_pattern(pattern_spec,:binding) {|matched_value|
      some_more_test_on(matched_value)
    })

## Case#_

This is the wildcard that matches anything

    of(_)

You can use binding to say "I don't care what this
and that are, but I want them to be the same", like so,

    of([_(:a),1,_(:a)])

The pattern matcher binds whatever matches the
first and last element of the array to ":a", the
binding fails unless those elements are the same.

## Case#a

Matches any object of a class.

    of(a(String)) 

## Case#literal

Matches an object by its `==` method.

    of(literal(1))
    of(literal(:b))

## Case#integer

Matches an integer.

    of(integer)              # any integer
    of(integer(1))           # matches 1
    of(integer(1..10))       # matches a range
    of(integer([1,3,5,7,9])) # matches any number in the set

## Case#string

    of(string)
    of(string("abc"))
    of(string(/abc/))

## Case#symbol

    of(string)
    of(string(:abc))
    # matches a symbol if its to_s matches the regexp.
    of(string(/abc/))


# Structural Patterns

For "container" objects like arrays and hashes,
pattern matching is a nice way to specify the
properties of the object, and taking it apart.


## Case#array

    of([])    # == of(array([]))
    of([1,2]) # matches exactly [1,2]
    of([symbol,string,symbol])
    
    # matches an array the first and last element are
    # the same symbol, the second element is a string
    of([symbol(nil,:a),string,symbol(nil,:a)])

You can match the tail of an array by using the
special method `Case#_!`

    c = Case.new {
     of([1,2,_!(integer)])
    }
    c.match([1])         # Case::NoMatch
    c.match([1,2])       # => true
    c.match([1,2,3])     # => true
    c.match([1,2,3,4,5]) # => true
    c.match([1,2,3,:a])  # Case::NoMatch

this pattern matches any array whose first two
elements are 1 and 2, the rest are integers.


## Case#hash

Hashes are pattern matched by specifying the what
pattern a key's value should match. A key can be
either be required, or optional, for the pattern
matching to succeed.

    c = Case.new {
     of("required" => integer, ["optional"] => string)
    }
    c.match("required" => 10, "optional" => "a") # => true
    c.match("required" => 10, "optional" => 1)   # Case::NoMatch
    c.match("required" => 10)                    # => true
    c.match("required" => "a")                   # => Case::NoMatch

The optional key is denoted by wrapping that in an
array.

## Case#one_of

This pattern matches if any one of its array of
patterns matches.

    c = Case.new {
     of(one_of([integer,string]))
    }
    c.match(10)    # => true
    c.match("yay") # => true
    c.match(:foo)  # => Case::NoMatch

# Higher Order Pattern

The pattern matcher is just constructed with a
bunch of objects. So it's possible to save a
pattern in a variable, and use that to build
larger patterns.

Build a two element array of a custom pattern,

    c = Case.new {
     my_pattern = [symbol,string]
     of([my_pattern,my_pattern])
    }

Generate pattern with lambda,

    c = Case.new {
     pattern = lambda {|pattern1,pattern2| [pattern1,pattern2]}
     of(pattern.call(symbol,string))
     of(pattern.call(string,symbol))
    }

## Case#is

This method is used to coerce an object into
pattern if it isn't already.

    is(/regexp/)   # string(regexp)
    is(some_class) # matches by class
    is(obj)        # literal(obj) for any object

Mostly useful for higher order stuff you are
doing.

## Case#bind

This is used to matched values to variables. It
takes a pattern, and a binding name, and possibly
a guard.

    c = Case.new {
     foo = is([string])
     of(bind(foo,:a)) { [1,a] }
     of(bind([foo],:a)) { [2,a] }
    }
    c.match(["a"])   # => [1,["a"]]
    c.match([["a"]]) # => [2,[["a"]]]

