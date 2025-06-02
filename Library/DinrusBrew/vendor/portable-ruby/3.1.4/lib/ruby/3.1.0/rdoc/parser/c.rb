# frozen_string_literal: true
require 'tsort'

##
# RDoc::Parser::C attempts to parse C extension files.  It looks for
# the standard patterns that you find in extensions: +rb_define_class+,
# +rb_define_method+ and so on.  It tries to find the corresponding
# C source for the methods and extract comments, but if we fail
# we don't worry too much.
#
# The comments associated with a Ruby method are extracted from the C
# comment block associated with the routine that _implements_ that
# method, that is to say the method whose name is given in the
# +rb_define_method+ call. For example, you might write:
#
#   /*
#    * Returns a new array that is a one-dimensional flattening of this
#    * array (recursively). That is, for every element that is an array,
#    * extract its elements into the new array.
#    *
#    *    s = [ 1, 2, 3 ]           #=> [1, 2, 3]
#    *    t = [ 4, 5, 6, [7, 8] ]   #=> [4, 5, 6, [7, 8]]
#    *    a = [ s, t, 9, 10 ]       #=> [[1, 2, 3], [4, 5, 6, [7, 8]], 9, 10]
#    *    a.flatten                 #=> [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
#    */
#    static VALUE
#    rb_ary_flatten(VALUE ary)
#    {
#        ary = rb_obj_dup(ary);
#        rb_ary_flatten_bang(ary);
#        return ary;
#    }
#
#    ...
#
#    void
#    Init_Array(void)
#    {
#      ...
#      rb_define_method(rb_cArray, "flatten", rb_ary_flatten, 0);
#
# Here RDoc will determine from the +rb_define_method+ line that there's a
# method called "flatten" in class Array, and will look for the implementation
# in the method +rb_ary_flatten+. It will then use the comment from that
# method in the HTML output. This method must be in the same source file
# as the +rb_define_method+.
#
# The comment blocks may include special directives:
#
# [Document-class: +name+]
#   Documentation for the named class.
#
# [Document-module: +name+]
#   Documentation for the named module.
#
# [Document-const: +name+]
#   Documentation for the named +rb_define_const+.
#
#   Constant values can be supplied on the first line of the comment like so:
#
#     /* 300: The highest possible score in bowling */
#     rb_define_const(cFoo, "PERFECT", INT2FIX(300));
#
#   The value can contain internal colons so long as they are escaped with a \
#
# [Document-global: +name+]
#   Documentation for the named +rb_define_global_const+
#
# [Document-variable: +name+]
#   Documentation for the named +rb_define_variable+
#
# [Document-method\: +method_name+]
#   Documentation for the named method.  Use this when the method name is
#   unambiguous.
#
# [Document-method\: <tt>ClassName::method_name</tt>]
#   Documentation for a singleton method in the given class.  Use this when
#   the method name alone is ambiguous.
#
# [Document-method\: <tt>ClassName#method_name</tt>]
#   Documentation for a instance method in the given class.  Use this when the
#   method name alone is ambiguous.
#
# [Document-attr: +name+]
#   Documentation for the named attribute.
#
# [call-seq:  <i>text up to an empty line</i>]
#   Because C source doesn't give descriptive names to Ruby-level parameters,
#   you need to document the calling sequence explicitly
#
# In addition, RDoc assumes by default that the C method implementing a
# Ruby function is in the same source file as the rb_define_method call.
# If this isn't the case, add the comment:
#
#   rb_define_method(....);  // in filename
#
# As an example, we might have an extension that defines multiple classes
# in its Init_xxx method. We could document them using
#
#   /*
#    * Document-class:  MyClass
#    *
#    * Encapsulate the writing and reading of the configuration
#    * file. ...
#    */
#
#   /*
#    * Document-method: read_value
#    *
#    * call-seq:
#    *   cfg.read_value(key)            -> value
#    *   cfg.read_value(key} { |key| }  -> value
#    *
#    * Return the value corresponding to +key+ from the configuration.
#    * In the second form, if the key isn't found, invoke the
#    * block and return its value.
#    */

class RDoc::Parser::C < RDoc::Parser

  parse_files_matching(/\.(?:([CcHh])\1?|c([+xp])\2|y)\z/)

  include RDoc::Text

  ##
  # Maps C variable names to names of Ruby classes or modules

  attr_reader :classes

  ##
  # C file the parser is parsing

  attr_accessor :content

  ##
  # Dependencies from a missing enclosing class to the classes in
  # missing_dependencies that depend upon it.

  attr_reader :enclosure_dependencies

  ##
  # Maps C variable names to names of Ruby classes (and singleton classes)

  attr_reader :known_classes

  ##
  # Classes found while parsing the C file that were not yet registered due to
  # a missing enclosing class.  These are processed by do_missing

  attr_reader :missing_dependencies

  ##
  # Maps C variable names to names of Ruby singleton classes

  attr_reader :singleton_classes

  ##
  # The TopLevel items in the parsed file belong to

  attr_reader :top_level

  ##
  # Prepares for parsing a C file.  See RDoc::Parser#initialize for details on
  # the arguments.

  def initialize top_level, file_name, content, options, stats
    super

    @known_classes = RDoc::KNOWN_CLASSES.dup
    @content = handle_tab_width handle_ifdefs_in @content
    @file_dir = File.dirname @file_name

    @classes           = load_variable_map :c_class_variables
    @singleton_classes = load_variable_map :c_singleton_class_variables

    @markup = @options.markup

    # class_variable => { function => [method, ...] }
    @methods = Hash.new { |h, f| h[f] = Hash.new { |i, m| i[m] = [] } }

    # missing variable => [handle_class_module arguments]
    @missing_dependencies = {}

    # missing enclosure variable => [dependent handle_class_module arguments]
    @enclosure_dependencies = Hash.new { |h, k| h[k] = [] }
    @enclosure_dependencies.instance_variable_set :@missing_dependencies,
                                                  @missing_dependencies

    @enclosure_dependencies.extend TSort

    def @enclosure_dependencies.tsort_each_node &block
      each_key(&block)
    rescue TSort::Cyclic => e
      cycle_vars = e.message.scan(/"(.*?)"/).flatten

      cycle = cycle_vars.sort.map do |var_name|
        delete var_name

        var_name, type, mod_name, = @missing_dependencies[var_name]

        "#{type} #{mod_name} (#{var_name})"
      end.join ', '

      warn "Unable to create #{cycle} due to a cyclic class or module creation"

      retry
    end

    def @enclosure_dependencies.tsort_each_child node, &block
      fetch(node, []).each(&block)
    end
  end

  ##
  # Scans #content for rb_define_alias

  def do_aliases
    @content.scan(/rb_define_alias\s*\(
                   \s*(\w+),
                   \s*"(.+?)",
                   \s*"(.+?)"
                   \s*\)/xm) do |var_name, new_name, old_name|
      class_name = @known_classes[var_name]

      unless class_name then
        @options.warn "Enclosing class or module %p for alias %s %s is not known" % [
          var_name, new_name, old_name]
        next
      end

      class_obj = find_class var_name, class_name
      comment = find_alias_comment var_name, new_name, old_name
      comment.normalize
      if comment.to_s.empty? and existing_method = class_obj.method_list.find { |m| m.name == old_name}
        comment = existing_method.comment
      end
      add_alias(var_name, class_obj, old_name, new_name, comment)
    end
  end

  ##
  # Add alias, either from a direct alias definition, or from two
  # method that reference the same function.

  def add_alias(var_name, class_obj, old_name, new_name, comment)
    al = RDoc::Alias.new '', old_name, new_name, ''
    al.singleton = @singleton_classes.key? var_name
    al.comment = comment
    al.record_location @top_level
    class_obj.add_alias al
    @stats.add_alias al
    al
  end

  ##
  # Scans #content for rb_attr and rb_define_attr

  def do_attrs
    @content.scan(/rb_attr\s*\(
                   \s*(\w+),
                   \s*([\w"()]+),
                   \s*([01]),
                   \s*([01]),
                   \s*\w+\);/xm) do |var_name, attr_name, read, write|
      handle_attr var_name, attr_name, read, write
    end

    @content.scan(%r%rb_define_attr\(
                             \s*([\w\.]+),
                             \s*"([^"]+)",
                             \s*(\d+),
                             \s*(\d+)\s*\);
                %xm) do |var_name, attr_name, read, write|
      handle_attr var_name, attr_name, read, write
    end
  end

  ##
  # Scans #content for boot_defclass

  def do_boot_defclass
    @content.scan(/(\w+)\s*=\s*boot_defclass\s*\(\s*"(\w+?)",\s*(\w+?)\s*\)/) do
      |var_name, class_name, parent|
      parent = nil if parent == "0"
      handle_class_module(var_name, :class, class_name, parent, nil)
    end
  end

  ##
  # Scans #content for rb_define_class, boot_defclass, rb_define_class_under
  # and rb_singleton_class

  def do_classes_and_modules
    do_boot_defclass if @file_name == "class.c"

    @content.scan(
      %r(
        (?<var_name>[\w\.]+)\s* =
        \s*rb_(?:
          define_(?:
            class(?: # rb_define_class(class_name_1, parent_name_1)
              \s*\(
                \s*"(?<class_name_1>\w+)",
                \s*(?<parent_name_1>\w+)\s*
              \)
            |
              _under\s*\( # rb_define_class_under(class_under, class_name2, parent_name2...)
                \s* (?<class_under>\w+),
                \s* "(?<class_name_2>\w+)",
                \s*
                (?:
                  (?<parent_name_2>[\w\*\s\(\)\.\->]+) |
                  rb_path2class\("(?<path>[\w:]+)"\)
                )
              \s*\)
            )
          |
            module(?: # rb_define_module(module_name_1)
              \s*\(
                \s*"(?<module_name_1>\w+)"\s*
              \)
            |
              _under\s*\( # rb_define_module_under(module_under, module_name_2)
                \s*(?<module_under>\w+),
                \s*"(?<module_name_2>\w+)"
              \s*\)
            )
          )
      |
        struct_define_without_accessor\s*\( # rb_struct_define_without_accessor(class_name_3, parent_name_3, ...)
          \s*"(?<class_name_3>\w+)",
          \s*(?<parent_name_3>\w+),
          \s*\w+,        # Allocation function
          (?:\s*"\w+",)* # Attributes
          \s*NULL
        \)
      |
        singleton_class\s*\( # rb_singleton_class(target_class_name)
          \s*(?<target_class_name>\w+)
        \)
        )
      )mx
    ) do
      class_name = $~[:class_name_1]
      type = :class
      if class_name
        # rb_define_class(class_name_1, parent_name_1)
        parent_name = $~[:parent_name_1]
        #under = nil
      else
        class_name = $~[:class_name_2]
        if class_name
          # rb_define_class_under(class_under, class_name2, parent_name2...)
          parent_name = $~[:parent_name_2] || $~[:path]
          under = $~[:class_under]
        else
          class_name = $~[:class_name_3]
          if class_name
            # rb_struct_define_without_accessor(class_name_3, parent_name_3, ...)
            parent_name = $~[:parent_name_3]
            #under = nil
          else
            type = :module
            class_name = $~[:module_name_1]
            #parent_name = nil
            if class_name
              # rb_define_module(module_name_1)
              #under = nil
            else
              class_name = $~[:module_name_2]
              if class_name
                # rb_define_module_under(module_under, module_name_1)
                under = $~[:module_under]
              else
                # rb_singleton_class(target_class_name)
                target_class_name = $~[:target_class_name]
                handle_singleton $~[:var_name], target_class_name
                next
              end
            end
          end
        end
      end

      handle_class_module($~[:var_name], type, class_name, parent_name, under)
    end
  end

  ##
  # Scans #content for rb_define_variable, rb_define_readonly_variable,
  # rb_define_const and rb_define_global_const

  def do_constants
    @content.scan(%r%\Wrb_define_
                   ( variable          |
                     readonly_variable |
                     const             |
                     global_const        )
               \s*\(
                 (?:\s*(\w+),)?
                 \s*"(\w+)",
                 \s*(.*?)\s*\)\s*;
                 %xm) do |type, var_name, const_name, definition|
      var_name = "rb_cObject" if !var_name or var_name == "rb_mKernel"
      handle_constants type, var_name, const_name, definition
    end

    @content.scan(%r%
                  \Wrb_curses_define_const
                  \s*\(
                    \s*
                    (\w+)
                    \s*
                  \)
                  \s*;%xm) do |consts|
      const = consts.first

      handle_constants 'const', 'mCurses', const, "UINT2NUM(#{const})"
    end

    @content.scan(%r%
                  \Wrb_file_const
                  \s*\(
                    \s*
                    "([^"]+)",
                    \s*
                    (.*?)
                    \s*
                  \)
                  \s*;%xm) do |name, value|
      handle_constants 'const', 'rb_mFConst', name, value
    end
  end


  ##
  # Scans #content for rb_include_module

  def do_includes
    @content.scan(/rb_include_module\s*\(\s*(\w+?),\s*(\w+?)\s*\)/) do |c,m|
      next unless cls = @classes[c]
      m = @known_classes[m] || m

      comment = new_comment '', @top_level, :c
      incl = cls.add_include RDoc::Include.new(m, comment)
      incl.record_location @top_level
    end
  end

  ##
  # Scans #content for rb_define_method, rb_define_singleton_method,
  # rb_define_module_function, rb_define_private_method,
  # rb_define_global_function and define_filetest_function

  def do_methods
    @content.scan(%r%rb_define_
                   (
                      singleton_method |
                      method           |
                      module_function  |
                      private_method
                   )
                   \s*\(\s*([\w\.]+),
                     \s*"([^"]+)",
                     \s*(?:RUBY_METHOD_FUNC\(|VALUEFUNC\(|\(METHOD\))?(\w+)\)?,
                     \s*(-?\w+)\s*\)
                   (?:;\s*/[*/]\s+in\s+(\w+?\.(?:cpp|c|y)))?
                 %xm) do |type, var_name, meth_name, function, param_count, source_file|

      # Ignore top-object and weird struct.c dynamic stuff
      next if var_name == "ruby_top_self"
      next if var_name == "nstr"

      var_name = "rb_cObject" if var_name == "rb_mKernel"
      handle_method(type, var_name, meth_name, function, param_count,
                    source_file)
    end

    @content.scan(%r%rb_define_global_function\s*\(
                             \s*"([^"]+)",
                             \s*(?:RUBY_METHOD_FUNC\(|VALUEFUNC\()?(\w+)\)?,
                             \s*(-?\w+)\s*\)
                (?:;\s*/[*/]\s+in\s+(\w+?\.[cy]))?
                %xm) do |meth_name, function, param_count, source_file|
      handle_method("method", "rb_mKernel", meth_name, function, param_count,
                    source_file)
    end

    @content.scan(/define_filetest_function\s*\(
                     \s*"([^"]+)",
                     \s*(?:RUBY_METHOD_FUNC\(|VALUEFUNC\()?(\w+)\)?,
                     \s*(-?\w+)\s*\)/xm) do |meth_name, function, param_count|

      handle_method("method", "rb_mFileTest", meth_name, function, param_count)
      handle_method("singleton_method", "rb_cFile", meth_name, function,
                    param_count)
    end
  end

  ##
  # Creates classes and module that were missing were defined due to the file
  # order being different than the declaration order.

  def do_missing
    return if @missing_dependencies.empty?

    @enclosure_dependencies.tsort.each do |in_module|
      arguments = @missing_dependencies.delete in_module

      next unless arguments # dependency on existing class

      handle_class_module(*arguments)
    end
  end

  ##
  # Finds the comment for an alias on +class_name+ from +new_name+ to
  # +old_name+

  def find_alias_comment class_name, new_name, old_name
    content =~ %r%((?>/\*.*?\*/\s+))
                  rb_define_alias\(\s*#{Regexp.escape class_name}\s*,
                                   \s*"#{Regexp.escape new_name}"\s*,
                                   \s*"#{Regexp.escape old_name}"\s*\);%xm

    new_comment($1 || '', @top_level, :c)
  end

  ##
  # Finds a comment for rb_define_attr, rb_attr or Document-attr.
  #
  # +var_name+ is the C class variable the attribute is defined on.
  # +attr_name+ is the attribute's name.
  #
  # +read+ and +write+ are the read/write flags ('1' or '0').  Either both or
  # neither must be provided.

  def find_attr_comment var_name, attr_name, read = nil, write = nil
    attr_name = Regexp.escape attr_name

    rw = if read and write then
           /\s*#{read}\s*,\s*#{write}\s*/xm
         else
           /.*?/m
         end

    comment = if @content =~ %r%((?>/\*.*?\*/\s+))
                                rb_define_attr\((?:\s*#{var_name},)?\s*
                                                "#{attr_name}"\s*,
                                                #{rw}\)\s*;%xm then
                $1
              elsif @content =~ %r%((?>/\*.*?\*/\s+))
                                   rb_attr\(\s*#{var_name}\s*,
                                            \s*#{attr_name}\s*,
                                            #{rw},.*?\)\s*;%xm then
                $1
              elsif @content =~ %r%(/\*.*?(?:\s*\*\s*)?)
                                   Document-attr:\s#{attr_name}\s*?\n
                                   ((?>(.|\n)*?\*/))%x then
                "#{$1}\n#{$2}"
              else
                ''
              end

    new_comment comment, @top_level, :c
  end

  ##
  # Generate a Ruby-method table

  def gen_body_table file_content
    table = {}
    file_content.scan(%r{
      ((?>/\*.*?\*/\s*)?)
      ((?:(?:\w+)\s+)?
        (?:intern\s+)?VALUE\s+(\w+)
        \s*(?:\([^)]*\))(?:[^\);]|$))
    | ((?>/\*.*?\*/\s*))^\s*(\#\s*define\s+(\w+)\s+(\w+))
    | ^\s*\#\s*define\s+(\w+)\s+(\w+)
    }xm) do
      case
      when $1
        table[$3] = [:func_def, $1, $2, $~.offset(2)] if !table[$3] || table[$3][0] != :func_def
      when $4
        table[$6] = [:macro_def, $4, $5, $~.offset(5), $7] if !table[$6] || table[$6][0] == :macro_alias
      when $8
        table[$8] ||= [:macro_alias, $9]
      end
    end
    table
  end

  ##
  # Find the C code corresponding to a Ruby method

  def find_body class_name, meth_name, meth_obj, file_content, quiet = false
    if file_content
      @body_table ||= {}
      @body_table[file_content] ||= gen_body_table file_content
      type, *args = @body_table[file_content][meth_name]
    end

    case type
    when :func_def
      comment = new_comment args[0], @top_level, :c
      body = args[1]
      offset, = args[2]

      comment.remove_private if comment

      # try to find the whole body
      body = $& if /#{Regexp.escape body}[^(]*?\{.*?^\}/m =~ file_content

      # The comment block may have been overridden with a 'Document-method'
      # block. This happens in the interpreter when multiple methods are
      # vectored through to the same C method but those methods are logically
      # distinct (for example Kernel.hash and Kernel.object_id share the same
      # implementation

      override_comment = find_override_comment class_name, meth_obj
      comment = override_comment if override_comment

      comment.normalize
      find_modifiers comment, meth_obj if comment

      #meth_obj.params = params
      meth_obj.start_collecting_tokens
      tk = { :line_no => 1, :char_no => 1, :text => body }
      meth_obj.add_token tk
      meth_obj.comment = comment
      meth_obj.line    = file_content[0, offset].count("\n") + 1

      body
    when :macro_def
      comment = new_comment args[0], @top_level, :c
      body = args[1]
      offset, = args[2]

      find_body class_name, args[3], meth_obj, file_content, true

      comment.normalize
      find_modifiers comment, meth_obj

      meth_obj.start_collecting_tokens
      tk = { :line_no => 1, :char_no => 1, :text => body }
      meth_obj.add_token tk
      meth_obj.comment = comment
      meth_obj.line    = file_content[0, offset].count("\n") + 1

      body
    when :macro_alias
      # with no comment we hope the aliased definition has it and use it's
      # definition

      body = find_body(class_name, args[0], meth_obj, file_content, true)

      return body if body

      @options.warn "No definition for #{meth_name}"
      false
    else # No body, but might still have an override comment
      comment = find_override_comment class_name, meth_obj

      if comment then
        comment.normalize
        find_modifiers comment, meth_obj
        meth_obj.comment = comment

        ''
      else
        @options.warn "No definition for #{meth_name}"
        false
      end
    end
  end

  ##
  # Finds a RDoc::NormalClass or RDoc::NormalModule for +raw_name+

  def find_class(raw_name, name)
    unless @classes[raw_name]
      if raw_name =~ /^rb_m/
        container = @top_level.add_module RDoc::NormalModule, name
      else
        container = @top_level.add_class RDoc::NormalClass, name
      end

      container.record_location @top_level
      @classes[raw_name] = container
    end
    @classes[raw_name]
  end

  ##
  # Look for class or module documentation above Init_+class_name+(void),
  # in a Document-class +class_name+ (or module) comment or above an
  # rb_define_class (or module).  If a comment is supplied above a matching
  # Init_ and a rb_define_class the Init_ comment is used.
  #
  #   /*
  #    * This is a comment for Foo
  #    */
  #   Init_Foo(void) {
  #       VALUE cFoo = rb_define_class("Foo", rb_cObject);
  #   }
  #
  #   /*
  #    * Document-class: Foo
  #    * This is a comment for Foo
  #    */
  #   Init_foo(void) {
  #       VALUE cFoo = rb_define_class("Foo", rb_cObject);
  #   }
  #
  #   /*
  #    * This is a comment for Foo
  #    */
  #   VALUE cFoo = rb_define_class("Foo", rb_cObject);

  def find_class_comment class_name, class_mod
    comment = nil

    if @content =~ %r%
        ((?>/\*.*?\*/\s+))
        (static\s+)?
        void\s+
        Init_#{class_name}\s*(?:_\(\s*)?\(\s*(?:void\s*)?\)%xmi then
      comment = $1.sub(%r%Document-(?:class|module):\s+#{class_name}%, '')
    elsif @content =~ %r%Document-(?:class|module):\s+#{class_name}\s*?
                         (?:<\s+[:,\w]+)?\n((?>.*?\*/))%xm then
      comment = "/*\n#{$1}"
    elsif @content =~ %r%((?>/\*.*?\*/\s+))
                         ([\w\.\s]+\s* = \s+)?rb_define_(class|module)[\t (]*?"(#{class_name})"%xm then
      comment = $1
    elsif @content =~ %r%((?>/\*.*?\*/\s+))
                         ([\w\. \t]+ = \s+)?rb_define_(class|module)_under[\t\w, (]*?"(#{class_name.split('::').last})"%xm then
      comment = $1
    else
      comment = ''
    end

    comment = new_comment comment, @top_level, :c
    comment.normalize

    look_for_directives_in class_mod, comment

    class_mod.add_comment comment, @top_level
  end

  ##
  # Generate a const table

  def gen_const_table file_content
    table = {}
    @content.scan(%r{
      ((?>^\s*/\*.*?\*/\s+))
        rb_define_(\w+)\((?:\s*(?:\w+),)?\s*
                           "(\w+)"\s*,
                           .*?\)\s*;
    | Document-(?:const|global|variable):\s
        ((?:\w+::)*\w+)
        \s*?\n((?>.*?\*/))
    }mxi) do
      case
      when $1 then table[[$2, $3]] = $1
      when $4 then table[$4] = "/*\n" + $5
      end
    end
    table
  end

  ##
  # Finds a comment matching +type+ and +const_name+ either above the
  # comment or in the matching Document- section.

  def find_const_comment(type, const_name, class_name = nil)
    @const_table ||= {}
    @const_table[@content] ||= gen_const_table @content
    table = @const_table[@content]

    comment =
      table[[type, const_name]] ||
      (class_name && table[class_name + "::" + const_name]) ||
      table[const_name] ||
      ''

    new_comment comment, @top_level, :c
  end

  ##
  # Handles modifiers in +comment+ and updates +meth_obj+ as appropriate.

  def find_modifiers comment, meth_obj
    comment.normalize
    comment.extract_call_seq meth_obj

    look_for_directives_in meth_obj, comment
  end

  ##
  # Finds a <tt>Document-method</tt> override for +meth_obj+ on +class_name+

  def find_override_comment class_name, meth_obj
    name = Regexp.escape meth_obj.name
    prefix = Regexp.escape meth_obj.name_prefix

    comment = if @content =~ %r%Document-method:
                                \s+#{class_name}#{prefix}#{name}
                                \s*?\n((?>.*?\*/))%xm then
                "/*#{$1}"
              elsif @content =~ %r%Document-method:
                                   \s#{name}\s*?\n((?>.*?\*/))%xm then
                "/*#{$1}"
              end

    return unless comment

    new_comment comment, @top_level, :c
  end

  ##
  # Creates a new RDoc::Attr +attr_name+ on class +var_name+ that is either
  # +read+, +write+ or both

  def handle_attr(var_name, attr_name, read, write)
    rw = ''
    rw += 'R' if '1' == read
    rw += 'W' if '1' == write

    class_name = @known_classes[var_name]

    return unless class_name

    class_obj = find_class var_name, class_name

    return unless class_obj

    comment = find_attr_comment var_name, attr_name
    comment.normalize

    name = attr_name.gsub(/rb_intern(?:_const)?\("([^"]+)"\)/, '\1')

    attr = RDoc::Attr.new '', name, rw, comment

    attr.record_location @top_level
    class_obj.add_attribute attr
    @stats.add_attribute attr
  end

  ##
  # Creates a new RDoc::NormalClass or RDoc::NormalModule based on +type+
  # named +class_name+ in +parent+ which was assigned to the C +var_name+.

  def handle_class_module(var_name, type, class_name, parent, in_module)
    parent_name = @known_classes[parent] || parent

    if in_module then
      enclosure = @classes[in_module] || @store.find_c_enclosure(in_module)

      if enclosure.nil? and enclosure = @known_classes[in_module] then
        enc_type = /^rb_m/ =~ in_module ? :module : :class
        handle_class_module in_module, enc_type, enclosure, nil, nil
        enclosure = @classes[in_module]
      end

      unless enclosure then
        @enclosure_dependencies[in_module] << var_name
        @missing_dependencies[var_name] =
          [var_name, type, class_name, parent, in_module]

        return
      end
    else
      enclosure = @top_level
    end

    if type == :class then
      full_name = if RDoc::ClassModule === enclosure then
                    enclosure.full_name + "::#{class_name}"
                  else
                    class_name
                  end

      if @content =~ %r%Document-class:\s+#{full_name}\s*<\s+([:,\w]+)% then
        parent_name = $1
      end

      cm = enclosure.add_class RDoc::NormalClass, class_name, parent_name
    else
      cm = enclosure.add_module RDoc::NormalModule, class_name
    end

    cm.record_location enclosure.top_level

    find_class_comment cm.full_name, cm

    case cm
    when RDoc::NormalClass
      @stats.add_class cm
    when RDoc::NormalModule
      @stats.add_module cm
    end

    @classes[var_name] = cm
    @known_classes[var_name] = cm.full_name
    @store.add_c_enclosure var_name, cm
  end

  ##
  # Adds constants.  By providing some_value: at the start of the comment you
  # can override the C value of the comment to give a friendly definition.
  #
  #   /* 300: The perfect score in bowling */
  #   rb_define_const(cFoo, "PERFECT", INT2FIX(300));
  #
  # Will override <tt>INT2FIX(300)</tt> with the value +300+ in the output
  # RDoc.  Values may include quotes and escaped colons (\:).

  def handle_constants(type, var_name, const_name, definition)
    class_name = @known_classes[var_name]

    return unless class_name

    class_obj = find_class var_name, class_name

    unless class_obj then
      @options.warn 'Enclosing class or module %p is not known' % [const_name]
      return
    end

    comment = find_const_comment type, const_name, class_name
    comment.normalize

    # In the case of rb_define_const, the definition and comment are in
    # "/* definition: comment */" form.  The literal ':' and '\' characters
    # can be escaped with a backslash.
    if type.downcase == 'const' then
      no_match, new_definition, new_comment = comment.text.split(/(\A.*):/)

      if no_match and no_match.empty? then
        if new_definition.empty? then # Default to literal C definition
          new_definition = definition
        else
          new_definition = new_definition.gsub("\:", ":")
          new_definition = new_definition.gsub("\\", '\\')
        end

        new_definition.sub!(/\A(\s+)/, '')

        new_comment = "#{$1}#{new_comment.lstrip}"

        new_comment = self.new_comment(new_comment, @top_level, :c)

        con = RDoc::Constant.new const_name, new_definition, new_comment
      else
        con = RDoc::Constant.new const_name, definition, comment
      end
    else
      con = RDoc::Constant.new const_name, definition, comment
    end

    con.record_location @top_level
    @stats.add_constant con
    class_obj.add_constant con
  end

  ##
  # Removes #ifdefs that would otherwise confuse us

  def handle_ifdefs_in(body)
    body.gsub(/^#ifdef HAVE_PROTOTYPES.*?#else.*?\n(.*?)#endif.*?\n/m, '\1')
  end

  ##
  # Adds an RDoc::AnyMethod +meth_name+ defined on a class or module assigned
  # to +var_name+.  +type+ is the type of method definition function used.
  # +singleton_method+ and +module_function+ create a singleton method.

  def handle_method(type, var_name, meth_name, function, param_count,
                    source_file = nil)
    class_name = @known_classes[var_name]
    singleton  = @singleton_classes.key? var_name

    @methods[var_name][function] << meth_name

    return unless class_name

    class_obj = find_class var_name, class_name

    if existing_method = class_obj.method_list.find { |m| m.c_function == function }
      add_alias(var_name, class_obj, existing_method.name, meth_name, existing_method.comment)
    end

    if class_obj then
      if meth_name == 'initialize' then
        meth_name = 'new'
        singleton = true
        type = 'method' # force public
      end

      meth_obj = RDoc::AnyMethod.new '', meth_name
      meth_obj.c_function = function
      meth_obj.singleton =
        singleton || %w[singleton_method module_function].include?(type)

      p_count = Integer(param_count) rescue -1

      if source_file then
        file_name = File.join @file_dir, source_file

        if File.exist? file_name then
          file_content = File.read file_name
        else
          @options.warn "unknown source #{source_file} for #{meth_name} in #{@file_name}"
        end
      else
        file_content = @content
      end

      body = find_body class_name, function, meth_obj, file_content

      if body and meth_obj.document_self then
        meth_obj.params = if p_count < -1 then # -2 is Array
                            '(*args)'
                          elsif p_count == -1 then # argc, argv
                            rb_scan_args body
                          else
                            "(#{(1..p_count).map { |i| "p#{i}" }.join ', '})"
                          end


        meth_obj.record_location @top_level

        if meth_obj.section_title
          class_obj.temporary_section = class_obj.add_section(meth_obj.section_title)
        end
        class_obj.add_method meth_obj

        @stats.add_method meth_obj
        meth_obj.visibility = :private if 'private_method' == type
      end
    end
  end

  ##
  # Registers a singleton class +sclass_var+ as a singleton of +class_var+

  def handle_singleton sclass_var, class_var
    class_name = @known_classes[class_var]

    @known_classes[sclass_var]     = class_name
    @singleton_classes[sclass_var] = class_name
  end

  ##
  # Normalizes tabs in +body+

  def handle_tab_width(body)
    if /\t/ =~ body
      tab_width = @options.tab_width
      body.split(/\n/).map do |line|
        1 while line.gsub!(/\t+/) do
          ' ' * (tab_width * $&.length - $`.length % tab_width)
        end && $~
        line
      end.join "\n"
    else
      body
    end
  end

  ##
  # Loads the variable map with the given +name+ from the RDoc::Store, if
  # present.

  def load_variable_map map_name
    return {} unless files = @store.cache[map_name]
    return {} unless name_map = files[@file_name]

    class_map = {}

    name_map.each do |variable, name|
      next unless mod = @store.find_class_or_module(name)

      class_map[variable] = if map_name == :c_class_variables then
                              mod
                            else
                              name
                            end
      @known_classes[variable] = name
    end

    class_map
  end

  ##
  # Look for directives in a normal comment block:
  #
  #   /*
  #    * :title: My Awesome Project
  #    */
  #
  # This method modifies the +comment+

  def look_for_directives_in context, comment
    @preprocess.handle comment, context do |directive, param|
      case directive
      when 'main' then
        @options.main_page = param
        ''
      when 'title' then
        @options.default_title = param if @options.respond_to? :default_title=
        ''
      end
    end

    comment
  end

  ##
  # Extracts parameters from the +method_body+ and returns a method
  # parameter string.  Follows 1.9.3dev's scan-arg-spec, see README.EXT

  def rb_scan_args method_body
    method_body =~ /rb_scan_args\((.*?)\)/m
    return '(*args)' unless $1

    $1.split(/,/)[2] =~ /"(.*?)"/ # format argument
    format = $1.split(//)

    lead = opt = trail = 0

    if format.first =~ /\d/ then
      lead = $&.to_i
      format.shift
      if format.first =~ /\d/ then
        opt = $&.to_i
        format.shift
        if format.first =~ /\d/ then
          trail = $&.to_i
          format.shift
          block_arg = true
        end
      end
    end

    if format.first == '*' and not block_arg then
      var = true
      format.shift
      if format.first =~ /\d/ then
        trail = $&.to_i
        format.shift
      end
    end

    if format.first == ':' then
      hash = true
      format.shift
    end

    if format.first == '&' then
      block = true
      format.shift
    end

    # if the format string is not empty there's a bug in the C code, ignore it

    args = []
    position = 1

    (1...(position + lead)).each do |index|
      args << "p#{index}"
    end

    position += lead

    (position...(position + opt)).each do |index|
      args << "p#{index} = v#{index}"
    end

    position += opt

    if var then
      args << '*args'
      position += 1
    end

    (position...(position + trail)).each do |index|
      args << "p#{index}"
    end

    position += trail

    if hash then
      args << "p#{position} = {}"
    end

    args << '&block' if block

    "(#{args.join ', '})"
  end

  ##
  # Removes lines that are commented out that might otherwise get picked up
  # when scanning for classes and methods

  def remove_commented_out_lines
    @content = @content.gsub(%r%//.*rb_define_%, '//')
  end

  ##
  # Extracts the classes, modules, methods, attributes, constants and aliases
  # from a C file and returns an RDoc::TopLevel for this file

  def scan
    remove_commented_out_lines

    do_classes_and_modules
    do_missing

    do_constants
    do_methods
    do_includes
    do_aliases
    do_attrs

    @store.add_c_variables self

    @top_level
  end

  def new_comment text = nil, location = nil, language = nil
    RDoc::Comment.new(text, location, language).tap do |comment|
      comment.format = @markup
    end
  end
end
