require 'mkmf'
require_relative '../../lib/debug/version'
File.write("debug_version.h", "#define RUBY_DEBUG_VERSION \"#{DEBUGGER__::VERSION}\"\n")
$distcleanfiles << "debug_version.h"

if defined? RubyVM
  $defs << '-DHAVE_RB_ISEQ'
  $defs << '-DHAVE_RB_ISEQ_PARAMETERS'
  $defs << '-DHAVE_RB_ISEQ_CODE_LOCATION'

  if RUBY_VERSION >= '3.1.0'
    $defs << '-DHAVE_RB_ISEQ_TYPE'
  end
else
  # not on MRI

  have_func "rb_iseq_parameters(NULL, 0)",
             [["VALUE rb_iseq_parameters(void *, int is_proc);"]]

  have_func "rb_iseq_code_location(NULL, NULL, NULL, NULL, NULL)",
            [["void rb_iseq_code_location(void *, int *first_lineno, int *first_column, int *last_lineno, int *last_column);"]]
  # from Ruby 3.1
  have_func "rb_iseq_type(NULL)",
            [["VALUE rb_iseq_type(void *);"]]
end

create_makefile 'debug/debug'
