# frozen_string_literal: true
#--
# ERB::DefMethod
#
# Utility module to define eRuby script as instance method.
#
# === Example
#
# example.rhtml:
#   <% for item in @items %>
#   <b><%= item %></b>
#   <% end %>
#
# example.rb:
#   require 'erb'
#   class MyClass
#     extend ERB::DefMethod
#     def_erb_method('render()', 'example.rhtml')
#     def initialize(items)
#       @items = items
#     end
#   end
#   print MyClass.new([10,20,30]).render()
#
# result:
#
#   <b>10</b>
#
#   <b>20</b>
#
#   <b>30</b>
#
module ERB::DefMethod
  # define _methodname_ as instance method of current module, using ERB
  # object or eRuby file
  def def_erb_method(methodname, erb_or_fname)
    if erb_or_fname.kind_of? String
      fname = erb_or_fname
      erb = ERB.new(File.read(fname))
      erb.def_method(self, methodname, fname)
    else
      erb = erb_or_fname
      erb.def_method(self, methodname, erb.filename || '(ERB)')
    end
  end
  module_function :def_erb_method
end
