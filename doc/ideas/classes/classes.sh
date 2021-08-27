#!/bin/bash
# Trying to figure out a way of implementing classes in Bash. I have no idea
# how this is accomplished for real. Gonna be wingin' it, with a trusty nameref
# by my side.
#
# I feel like manually defining a singular class isn't that difficult. I need to
# make a function that behaves like a new keyword. You say...
#  $ class 'Foo'
# ...and pass some parameters to it, and it builds a class called 'Foo', which
# can then be instantiated. This feels like an appropriate challenge.
