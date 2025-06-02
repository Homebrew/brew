# frozen_string_literal: true
##
# Stats printer that prints everything documented, including the documented
# status

class RDoc::Stats::Verbose < RDoc::Stats::Normal

  ##
  # Returns a marker for RDoc::CodeObject +co+ being undocumented

  def nodoc co
    " (undocumented)" unless co.documented?
  end

  def print_alias as # :nodoc:
    puts "    alias #{as.new_name} #{as.old_name}#{nodoc as}"
  end

  def print_attribute attribute # :nodoc:
    puts "    #{attribute.definition} #{attribute.name}#{nodoc attribute}"
  end

  def print_class(klass) # :nodoc:
    puts "  class #{klass.full_name}#{nodoc klass}"
  end

  def print_constant(constant) # :nodoc:
    puts "    #{constant.name}#{nodoc constant}"
  end

  def print_file(files_so_far, file) # :nodoc:
    super
    puts
  end

  def print_method(method) # :nodoc:
    puts "    #{method.singleton ? '::' : '#'}#{method.name}#{nodoc method}"
  end

  def print_module(mod) # :nodoc:
    puts "  module #{mod.full_name}#{nodoc mod}"
  end

end


