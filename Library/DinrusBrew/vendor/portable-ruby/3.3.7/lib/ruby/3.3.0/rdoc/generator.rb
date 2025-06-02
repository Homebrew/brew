# frozen_string_literal: true
##
# RDoc uses generators to turn parsed source code in the form of an
# RDoc::CodeObject tree into some form of output.  RDoc comes with the HTML
# generator RDoc::Generator::Darkfish and an ri data generator
# RDoc::Generator::RI.
#
# == Registering a Generator
#
# Generators are registered by calling RDoc::RDoc.add_generator with the class
# of the generator:
#
#   class My::Awesome::Generator
#     RDoc::RDoc.add_generator self
#   end
#
# == Adding Options to +rdoc+
#
# Before option processing in +rdoc+, RDoc::Options will call ::setup_options
# on the generator class with an RDoc::Options instance.  The generator can
# use RDoc::Options#option_parser to add command-line options to the +rdoc+
# tool.  See RDoc::Options@Custom+Options for an example and see OptionParser
# for details on how to add options.
#
# You can extend the RDoc::Options instance with additional accessors for your
# generator.
#
# == Generator Instantiation
#
# After parsing, RDoc::RDoc will instantiate a generator by calling
# #initialize with an RDoc::Store instance and an RDoc::Options instance.
#
# The RDoc::Store instance holds documentation for parsed source code.  In
# RDoc 3 and earlier the RDoc::TopLevel class held this data.  When upgrading
# a generator from RDoc 3 and earlier you should only need to replace
# RDoc::TopLevel with the store instance.
#
# RDoc will then call #generate on the generator instance.  You can use the
# various methods on RDoc::Store and in the RDoc::CodeObject tree to create
# your desired output format.

module RDoc::Generator

  autoload :Markup,   "#{__dir__}/generator/markup"

  autoload :Darkfish,  "#{__dir__}/generator/darkfish"
  autoload :JsonIndex, "#{__dir__}/generator/json_index"
  autoload :RI,        "#{__dir__}/generator/ri"
  autoload :POT,       "#{__dir__}/generator/pot"

end
