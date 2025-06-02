# frozen_string_literal: true
##
# Indicates this parser is text and doesn't contain code constructs.
#
# Include this module in a RDoc::Parser subclass to make it show up as a file,
# not as part of a class or module.
#--
# This is not named File to avoid overriding ::File

module RDoc::Parser::Text
end
