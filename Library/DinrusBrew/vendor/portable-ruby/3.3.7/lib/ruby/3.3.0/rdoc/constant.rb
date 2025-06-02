# frozen_string_literal: true
##
# A constant

class RDoc::Constant < RDoc::CodeObject

  MARSHAL_VERSION = 0 # :nodoc:

  ##
  # Sets the module or class this is constant is an alias for.

  attr_writer :is_alias_for

  ##
  # The constant's name

  attr_accessor :name

  ##
  # The constant's value

  attr_accessor :value

  ##
  # The constant's visibility

  attr_accessor :visibility

  ##
  # Creates a new constant with +name+, +value+ and +comment+

  def initialize(name, value, comment)
    super()

    @name  = name
    @value = value

    @is_alias_for = nil
    @visibility   = :public

    self.comment = comment
  end

  ##
  # Constants are ordered by name

  def <=> other
    return unless self.class === other

    [parent_name, name] <=> [other.parent_name, other.name]
  end

  ##
  # Constants are equal when their #parent and #name is the same

  def == other
    self.class == other.class and
      @parent == other.parent and
      @name == other.name
  end

  ##
  # A constant is documented if it has a comment, or is an alias
  # for a documented class or module.

  def documented?
    return true if super
    return false unless @is_alias_for
    case @is_alias_for
    when String then
      found = @store.find_class_or_module @is_alias_for
      return false unless found
      @is_alias_for = found
    end
    @is_alias_for.documented?
  end

  ##
  # Full constant name including namespace

  def full_name
    @full_name ||= "#{parent_name}::#{@name}"
  end

  ##
  # The module or class this constant is an alias for

  def is_alias_for
    case @is_alias_for
    when String then
      found = @store.find_class_or_module @is_alias_for
      @is_alias_for = found if found
      @is_alias_for
    else
      @is_alias_for
    end
  end

  def inspect # :nodoc:
    "#<%s:0x%x %s::%s>" % [
      self.class, object_id,
      parent_name, @name,
    ]
  end

  ##
  # Dumps this Constant for use by ri.  See also #marshal_load

  def marshal_dump
    alias_name = case found = is_alias_for
                 when RDoc::CodeObject then found.full_name
                 else                       found
                 end

    [ MARSHAL_VERSION,
      @name,
      full_name,
      @visibility,
      alias_name,
      parse(@comment),
      @file.relative_name,
      parent.name,
      parent.class,
      section.title,
    ]
  end

  ##
  # Loads this Constant from +array+.  For a loaded Constant the following
  # methods will return cached values:
  #
  # * #full_name
  # * #parent_name

  def marshal_load array
    initialize array[1], nil, array[5]

    @full_name     = array[2]
    @visibility    = array[3] || :public
    @is_alias_for  = array[4]
    #                      5 handled above
    #                      6 handled below
    @parent_name   = array[7]
    @parent_class  = array[8]
    @section_title = array[9]

    @file = RDoc::TopLevel.new array[6]
  end

  ##
  # Path to this constant for use with HTML generator output.

  def path
    "#{@parent.path}##{@name}"
  end

  def pretty_print q # :nodoc:
    q.group 2, "[#{self.class.name} #{full_name}", "]" do
      unless comment.empty? then
        q.breakable
        q.text "comment:"
        q.breakable
        q.pp @comment
      end
    end
  end

  ##
  # Sets the store for this class or module and its contained code objects.

  def store= store
    super

    @file = @store.add_file @file.full_name if @file
  end

  def to_s # :nodoc:
    parent_name = parent ? parent.full_name : '(unknown)'
    if is_alias_for
      "constant #{parent_name}::#@name -> #{is_alias_for}"
    else
      "constant #{parent_name}::#@name"
    end
  end

end
