# frozen_string_literal: true
##
# A file loaded by \#require

class RDoc::Require < RDoc::CodeObject

  ##
  # Name of the required file

  attr_accessor :name

  ##
  # Creates a new Require that loads +name+ with +comment+

  def initialize(name, comment)
    super()
    @name = name.gsub(/'|"/, "") #'
    @top_level = nil
    self.comment = comment
  end

  def inspect # :nodoc:
    "#<%s:0x%x require '%s' in %s>" % [
      self.class,
      object_id,
      @name,
      parent_file_name,
    ]
  end

  def to_s # :nodoc:
    "require #{name} in: #{parent}"
  end

  ##
  # The RDoc::TopLevel corresponding to this require, or +nil+ if not found.

  def top_level
    @top_level ||= begin
      tl = RDoc::TopLevel.all_files_hash[name + '.rb']

      if tl.nil? and RDoc::TopLevel.all_files.first.full_name =~ %r(^lib/) then
        # second chance
        tl = RDoc::TopLevel.all_files_hash['lib/' + name + '.rb']
      end

      tl
    end
  end

end

