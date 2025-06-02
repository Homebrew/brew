# frozen_string_literal: true
##
# AnyMethod is the base class for objects representing methods

class RDoc::AnyMethod < RDoc::MethodAttr

  ##
  # 2::
  #   RDoc 4
  #   Added calls_super
  #   Added parent name and class
  #   Added section title
  # 3::
  #   RDoc 4.1
  #   Added is_alias_for

  MARSHAL_VERSION = 3 # :nodoc:

  ##
  # Don't rename \#initialize to \::new

  attr_accessor :dont_rename_initialize

  ##
  # The C function that implements this method (if it was defined in a C file)

  attr_accessor :c_function

  # The section title of the method (if defined in a C file via +:category:+)
  attr_accessor :section_title

  # Parameters for this method

  attr_accessor :params

  ##
  # If true this method uses +super+ to call a superclass version

  attr_accessor :calls_super

  include RDoc::TokenStream

  ##
  # Creates a new AnyMethod with a token stream +text+ and +name+

  def initialize text, name
    super

    @c_function = nil
    @dont_rename_initialize = false
    @token_stream = nil
    @calls_super = false
    @superclass_method = nil
  end

  ##
  # Adds +an_alias+ as an alias for this method in +context+.

  def add_alias an_alias, context = nil
    method = self.class.new an_alias.text, an_alias.new_name

    method.record_location an_alias.file
    method.singleton = self.singleton
    method.params = self.params
    method.visibility = self.visibility
    method.comment = an_alias.comment
    method.is_alias_for = self
    @aliases << method
    context.add_method method if context
    method
  end

  ##
  # Prefix for +aref+ is 'method'.

  def aref_prefix
    'method'
  end

  ##
  # The call_seq or the param_seq with method name, if there is no call_seq.
  #
  # Use this for displaying a method's argument lists.

  def arglists
    if @call_seq then
      @call_seq
    elsif @params then
      "#{name}#{param_seq}"
    end
  end

  ##
  # Different ways to call this method

  def call_seq
    unless call_seq = _call_seq
      call_seq = is_alias_for._call_seq if is_alias_for
    end

    return unless call_seq

    deduplicate_call_seq(call_seq)
  end

  ##
  # Sets the different ways you can call this method.  If an empty +call_seq+
  # is given nil is assumed.
  #
  # See also #param_seq

  def call_seq= call_seq
    return if call_seq.empty?

    @call_seq = call_seq
  end

  ##
  # Loads is_alias_for from the internal name.  Returns nil if the alias
  # cannot be found.

  def is_alias_for # :nodoc:
    case @is_alias_for
    when RDoc::MethodAttr then
      @is_alias_for
    when Array then
      return nil unless @store

      klass_name, singleton, method_name = @is_alias_for

      return nil unless klass = @store.find_class_or_module(klass_name)

      @is_alias_for = klass.find_method method_name, singleton
    end
  end

  ##
  # Dumps this AnyMethod for use by ri.  See also #marshal_load

  def marshal_dump
    aliases = @aliases.map do |a|
      [a.name, parse(a.comment)]
    end

    is_alias_for = [
      @is_alias_for.parent.full_name,
      @is_alias_for.singleton,
      @is_alias_for.name
    ] if @is_alias_for

    [ MARSHAL_VERSION,
      @name,
      full_name,
      @singleton,
      @visibility,
      parse(@comment),
      @call_seq,
      @block_params,
      aliases,
      @params,
      @file.relative_name,
      @calls_super,
      @parent.name,
      @parent.class,
      @section.title,
      is_alias_for,
    ]
  end

  ##
  # Loads this AnyMethod from +array+.  For a loaded AnyMethod the following
  # methods will return cached values:
  #
  # * #full_name
  # * #parent_name

  def marshal_load array
    initialize_visibility

    @dont_rename_initialize = nil
    @token_stream           = nil
    @aliases                = []
    @parent                 = nil
    @parent_name            = nil
    @parent_class           = nil
    @section                = nil
    @file                   = nil

    version        = array[0]
    @name          = array[1]
    @full_name     = array[2]
    @singleton     = array[3]
    @visibility    = array[4]
    @comment       = array[5]
    @call_seq      = array[6]
    @block_params  = array[7]
    #                      8 handled below
    @params        = array[9]
    #                      10 handled below
    @calls_super   = array[11]
    @parent_name   = array[12]
    @parent_title  = array[13]
    @section_title = array[14]
    @is_alias_for  = array[15]

    array[8].each do |new_name, comment|
      add_alias RDoc::Alias.new(nil, @name, new_name, comment, @singleton)
    end

    @parent_name ||= if @full_name =~ /#/ then
                       $`
                     else
                       name = @full_name.split('::')
                       name.pop
                       name.join '::'
                     end

    @file = RDoc::TopLevel.new array[10] if version > 0
  end

  ##
  # Method name
  #
  # If the method has no assigned name, it extracts it from #call_seq.

  def name
    return @name if @name

    @name =
      @call_seq[/^.*?\.(\w+)/, 1] ||
      @call_seq[/^.*?(\w+)/, 1] ||
      @call_seq if @call_seq
  end

  ##
  # A list of this method's method and yield parameters.  +call-seq+ params
  # are preferred over parsed method and block params.

  def param_list
    if @call_seq then
      params = @call_seq.split("\n").last
      params = params.sub(/.*?\((.*)\)/, '\1')
      params = params.sub(/(\{|do)\s*\|([^|]*)\|.*/, ',\2')
    elsif @params then
      params = @params.sub(/\((.*)\)/, '\1')

      params << ",#{@block_params}" if @block_params
    elsif @block_params then
      params = @block_params
    else
      return []
    end

    if @block_params then
      # If this method has explicit block parameters, remove any explicit
      # &block
      params = params.sub(/,?\s*&\w+/, '')
    else
      params = params.sub(/\&(\w+)/, '\1')
    end

    params = params.gsub(/\s+/, '').split(',').reject(&:empty?)

    params.map { |param| param.sub(/=.*/, '') }
  end

  ##
  # Pretty parameter list for this method.  If the method's parameters were
  # given by +call-seq+ it is preferred over the parsed values.

  def param_seq
    if @call_seq then
      params = @call_seq.split("\n").last
      params = params.sub(/[^( ]+/, '')
      params = params.sub(/(\|[^|]+\|)\s*\.\.\.\s*(end|\})/, '\1 \2')
    elsif @params then
      params = @params.gsub(/\s*\#.*/, '')
      params = params.tr_s("\n ", " ")
      params = "(#{params})" unless params[0] == ?(
    else
      params = ''
    end

    if @block_params then
      # If this method has explicit block parameters, remove any explicit
      # &block
      params = params.sub(/,?\s*&\w+/, '')

      block = @block_params.tr_s("\n ", " ")
      if block[0] == ?(
        block = block.sub(/^\(/, '').sub(/\)/, '')
      end
      params << " { |#{block}| ... }"
    end

    params
  end

  ##
  # Sets the store for this method and its referenced code objects.

  def store= store
    super

    @file = @store.add_file @file.full_name if @file
  end

  ##
  # For methods that +super+, find the superclass method that would be called.

  def superclass_method
    return unless @calls_super
    return @superclass_method if @superclass_method

    parent.each_ancestor do |ancestor|
      if method = ancestor.method_list.find { |m| m.name == @name } then
        @superclass_method = method
        break
      end
    end

    @superclass_method
  end

  protected

  ##
  # call_seq without deduplication and alias lookup.

  def _call_seq
    @call_seq if defined?(@call_seq) && @call_seq
  end

  private

  ##
  # call_seq with alias examples information removed, if this
  # method is an alias method.

  def deduplicate_call_seq(call_seq)
    return call_seq unless is_alias_for || !aliases.empty?

    method_name = self.name
    method_name = method_name[0, 1] if method_name =~ /\A\[/

    entries = call_seq.split "\n"

    ignore = aliases.map(&:name)
    if is_alias_for
      ignore << is_alias_for.name
      ignore.concat is_alias_for.aliases.map(&:name)
    end
    ignore.map! { |n| n =~ /\A\[/ ? n[0, 1] : n}
    ignore.delete(method_name)
    ignore = Regexp.union(ignore)

    matching = entries.reject do |entry|
      entry =~ /^\w*\.?#{ignore}/ or
        entry =~ /\s#{ignore}\s/
    end

    matching.empty? ? nil : matching.join("\n")
  end
end
