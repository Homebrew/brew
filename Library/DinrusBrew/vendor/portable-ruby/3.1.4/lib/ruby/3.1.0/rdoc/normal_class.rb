# frozen_string_literal: true
##
# A normal class, neither singleton nor anonymous

class RDoc::NormalClass < RDoc::ClassModule

  ##
  # The ancestors of this class including modules.  Unlike Module#ancestors,
  # this class is not included in the result.  The result will contain both
  # RDoc::ClassModules and Strings.

  def ancestors
    if String === superclass then
      super << superclass
    elsif superclass then
      ancestors = super
      ancestors << superclass
      ancestors.concat superclass.ancestors
    else
      super
    end
  end

  def aref_prefix # :nodoc:
    'class'
  end

  ##
  # The definition of this class, <tt>class MyClassName</tt>

  def definition
    "class #{full_name}"
  end

  def direct_ancestors
    superclass ? super + [superclass] : super
  end

  def inspect # :nodoc:
    superclass = @superclass ? " < #{@superclass}" : nil
    "<%s:0x%x class %s%s includes: %p extends: %p attributes: %p methods: %p aliases: %p>" % [
      self.class, object_id,
      full_name, superclass, @includes, @extends, @attributes, @method_list, @aliases
    ]
  end

  def to_s # :nodoc:
    display = "#{self.class.name} #{self.full_name}"
    if superclass
      display += ' < ' + (superclass.is_a?(String) ? superclass : superclass.full_name)
    end
    display += ' -> ' + is_alias_for.to_s if is_alias_for
    display
  end

  def pretty_print q # :nodoc:
    superclass = @superclass ? " < #{@superclass}" : nil

    q.group 2, "[class #{full_name}#{superclass} ", "]" do
      q.breakable
      q.text "includes:"
      q.breakable
      q.seplist @includes do |inc| q.pp inc end

      q.breakable
      q.text "constants:"
      q.breakable
      q.seplist @constants do |const| q.pp const end

      q.breakable
      q.text "attributes:"
      q.breakable
      q.seplist @attributes do |attr| q.pp attr end

      q.breakable
      q.text "methods:"
      q.breakable
      q.seplist @method_list do |meth| q.pp meth end

      q.breakable
      q.text "aliases:"
      q.breakable
      q.seplist @aliases do |aliaz| q.pp aliaz end

      q.breakable
      q.text "comment:"
      q.breakable
      q.pp comment
    end
  end

end

