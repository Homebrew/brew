# frozen_string_literal: true
##
# Represent an alias, which is an old_name/new_name pair associated with a
# particular context
#--
# TODO implement Alias as a proxy to a method/attribute, inheriting from
#      MethodAttr

class RDoc::Alias < RDoc::CodeObject

  ##
  # Aliased method's name

  attr_reader :new_name

  alias name new_name

  ##
  # Aliasee method's name

  attr_reader :old_name

  ##
  # Is this an alias declared in a singleton context?

  attr_accessor :singleton

  ##
  # Source file token stream

  attr_reader :text

  ##
  # Creates a new Alias with a token stream of +text+ that aliases +old_name+
  # to +new_name+, has +comment+ and is a +singleton+ context.

  def initialize(text, old_name, new_name, comment, singleton = false)
    super()

    @text = text
    @singleton = singleton
    @old_name = old_name
    @new_name = new_name
    self.comment = comment
  end

  ##
  # Order by #singleton then #new_name

  def <=>(other)
    [@singleton ? 0 : 1, new_name] <=> [other.singleton ? 0 : 1, other.new_name]
  end

  ##
  # HTML fragment reference for this alias

  def aref
    type = singleton ? 'c' : 'i'
    "#alias-#{type}-#{html_name}"
  end

  ##
  # Full old name including namespace

  def full_old_name
    @full_name || "#{parent.name}#{pretty_old_name}"
  end

  ##
  # HTML id-friendly version of +#new_name+.

  def html_name
    CGI.escape(@new_name.gsub('-', '-2D')).gsub('%','-').sub(/^-/, '')
  end

  def inspect # :nodoc:
    parent_name = parent ? parent.name : '(unknown)'
    "#<%s:0x%x %s.alias_method %s, %s>" % [
      self.class, object_id,
      parent_name, @old_name, @new_name,
    ]
  end

  ##
  # '::' for the alias of a singleton method/attribute, '#' for instance-level.

  def name_prefix
    singleton ? '::' : '#'
  end

  ##
  # Old name with prefix '::' or '#'.

  def pretty_old_name
    "#{singleton ? '::' : '#'}#{@old_name}"
  end

  ##
  # New name with prefix '::' or '#'.

  def pretty_new_name
    "#{singleton ? '::' : '#'}#{@new_name}"
  end

  alias pretty_name pretty_new_name

  def to_s # :nodoc:
    "alias: #{self.new_name} -> #{self.pretty_old_name} in: #{parent}"
  end

end
