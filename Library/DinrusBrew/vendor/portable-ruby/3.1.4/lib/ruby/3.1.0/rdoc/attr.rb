# frozen_string_literal: true
##
# An attribute created by \#attr, \#attr_reader, \#attr_writer or
# \#attr_accessor

class RDoc::Attr < RDoc::MethodAttr

  ##
  # 3::
  #   RDoc 4
  #    Added parent name and class
  #    Added section title

  MARSHAL_VERSION = 3 # :nodoc:

  ##
  # Is the attribute readable ('R'), writable ('W') or both ('RW')?

  attr_accessor :rw

  ##
  # Creates a new Attr with body +text+, +name+, read/write status +rw+ and
  # +comment+.  +singleton+ marks this as a class attribute.

  def initialize(text, name, rw, comment, singleton = false)
    super text, name

    @rw = rw
    @singleton = singleton
    self.comment = comment
  end

  ##
  # Attributes are equal when their names, singleton and rw are identical

  def == other
    self.class == other.class and
      self.name == other.name and
      self.rw == other.rw and
      self.singleton == other.singleton
  end

  ##
  # Add +an_alias+ as an attribute in +context+.

  def add_alias(an_alias, context)
    new_attr = self.class.new(self.text, an_alias.new_name, self.rw,
                              self.comment, self.singleton)

    new_attr.record_location an_alias.file
    new_attr.visibility = self.visibility
    new_attr.is_alias_for = self
    @aliases << new_attr
    context.add_attribute new_attr
    new_attr
  end

  ##
  # The #aref prefix for attributes

  def aref_prefix
    'attribute'
  end

  ##
  # Attributes never call super.  See RDoc::AnyMethod#calls_super
  #
  # An RDoc::Attr can show up in the method list in some situations (see
  # Gem::ConfigFile)

  def calls_super # :nodoc:
    false
  end

  ##
  # Returns attr_reader, attr_writer or attr_accessor as appropriate.

  def definition
    case @rw
    when 'RW' then 'attr_accessor'
    when 'R'  then 'attr_reader'
    when 'W'  then 'attr_writer'
    end
  end

  def inspect # :nodoc:
    alias_for = @is_alias_for ? " (alias for #{@is_alias_for.name})" : nil
    visibility = self.visibility
    visibility = "forced #{visibility}" if force_documentation
    "#<%s:0x%x %s %s (%s)%s>" % [
      self.class, object_id,
      full_name,
      rw,
      visibility,
      alias_for,
    ]
  end

  ##
  # Dumps this Attr for use by ri.  See also #marshal_load

  def marshal_dump
    [ MARSHAL_VERSION,
      @name,
      full_name,
      @rw,
      @visibility,
      parse(@comment),
      singleton,
      @file.relative_name,
      @parent.full_name,
      @parent.class,
      @section.title
    ]
  end

  ##
  # Loads this Attr from +array+.  For a loaded Attr the following
  # methods will return cached values:
  #
  # * #full_name
  # * #parent_name

  def marshal_load array
    initialize_visibility

    @aliases      = []
    @parent       = nil
    @parent_name  = nil
    @parent_class = nil
    @section      = nil
    @file         = nil

    version        = array[0]
    @name          = array[1]
    @full_name     = array[2]
    @rw            = array[3]
    @visibility    = array[4]
    @comment       = array[5]
    @singleton     = array[6] || false # MARSHAL_VERSION == 0
    #                      7 handled below
    @parent_name   = array[8]
    @parent_class  = array[9]
    @section_title = array[10]

    @file = RDoc::TopLevel.new array[7] if version > 1

    @parent_name ||= @full_name.split('#', 2).first
  end

  def pretty_print q # :nodoc:
    q.group 2, "[#{self.class.name} #{full_name} #{rw} #{visibility}", "]" do
      unless comment.empty? then
        q.breakable
        q.text "comment:"
        q.breakable
        q.pp @comment
      end
    end
  end

  def to_s # :nodoc:
    "#{definition} #{name} in: #{parent}"
  end

  ##
  # Attributes do not have token streams.
  #
  # An RDoc::Attr can show up in the method list in some situations (see
  # Gem::ConfigFile)

  def token_stream # :nodoc:
  end

end

