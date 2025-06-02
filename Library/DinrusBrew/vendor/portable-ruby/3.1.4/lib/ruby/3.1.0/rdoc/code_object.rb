# frozen_string_literal: true
##
# Base class for the RDoc code tree.
#
# We contain the common stuff for contexts (which are containers) and other
# elements (methods, attributes and so on)
#
# Here's the tree of the CodeObject subclasses:
#
# * RDoc::Context
#   * RDoc::TopLevel
#   * RDoc::ClassModule
#     * RDoc::AnonClass (never used so far)
#     * RDoc::NormalClass
#     * RDoc::NormalModule
#     * RDoc::SingleClass
# * RDoc::MethodAttr
#   * RDoc::Attr
#   * RDoc::AnyMethod
#     * RDoc::GhostMethod
#     * RDoc::MetaMethod
# * RDoc::Alias
# * RDoc::Constant
# * RDoc::Mixin
#   * RDoc::Require
#   * RDoc::Include

class RDoc::CodeObject

  include RDoc::Text

  ##
  # Our comment

  attr_reader :comment

  ##
  # Do we document our children?

  attr_reader :document_children

  ##
  # Do we document ourselves?

  attr_reader :document_self

  ##
  # Are we done documenting (ie, did we come across a :enddoc:)?

  attr_reader :done_documenting

  ##
  # Which file this code object was defined in

  attr_reader :file

  ##
  # Force documentation of this CodeObject

  attr_reader :force_documentation

  ##
  # Line in #file where this CodeObject was defined

  attr_accessor :line

  ##
  # Hash of arbitrary metadata for this CodeObject

  attr_reader :metadata

  ##
  # Sets the parent CodeObject

  attr_writer :parent

  ##
  # Did we ever receive a +:nodoc:+ directive?

  attr_reader :received_nodoc

  ##
  # Set the section this CodeObject is in

  attr_writer :section

  ##
  # The RDoc::Store for this object.

  attr_reader :store

  ##
  # We are the model of the code, but we know that at some point we will be
  # worked on by viewers. By implementing the Viewable protocol, viewers can
  # associated themselves with these objects.

  attr_accessor :viewer

  ##
  # Creates a new CodeObject that will document itself and its children

  def initialize
    @metadata         = {}
    @comment          = ''
    @parent           = nil
    @parent_name      = nil # for loading
    @parent_class     = nil # for loading
    @section          = nil
    @section_title    = nil # for loading
    @file             = nil
    @full_name        = nil
    @store            = nil
    @track_visibility = true

    initialize_visibility
  end

  ##
  # Initializes state for visibility of this CodeObject and its children.

  def initialize_visibility # :nodoc:
    @document_children   = true
    @document_self       = true
    @done_documenting    = false
    @force_documentation = false
    @received_nodoc      = false
    @ignored             = false
    @suppressed          = false
    @track_visibility    = true
  end

  ##
  # Replaces our comment with +comment+, unless it is empty.

  def comment=(comment)
    @comment = case comment
               when NilClass               then ''
               when RDoc::Markup::Document then comment
               when RDoc::Comment          then comment.normalize
               else
                 if comment and not comment.empty? then
                   normalize_comment comment
                 else
                   # HACK correct fix is to have #initialize create @comment
                   #      with the correct encoding
                   if String === @comment and @comment.empty? then
                     @comment = RDoc::Encoding.change_encoding @comment, comment.encoding
                   end
                   @comment
                 end
               end
  end

  ##
  # Should this CodeObject be displayed in output?
  #
  # A code object should be displayed if:
  #
  # * The item didn't have a nodoc or wasn't in a container that had nodoc
  # * The item wasn't ignored
  # * The item has documentation and was not suppressed

  def display?
    @document_self and not @ignored and
      (documented? or not @suppressed)
  end

  ##
  # Enables or disables documentation of this CodeObject's children unless it
  # has been turned off by :enddoc:

  def document_children=(document_children)
    return unless @track_visibility

    @document_children = document_children unless @done_documenting
  end

  ##
  # Enables or disables documentation of this CodeObject unless it has been
  # turned off by :enddoc:.  If the argument is +nil+ it means the
  # documentation is turned off by +:nodoc:+.

  def document_self=(document_self)
    return unless @track_visibility
    return if @done_documenting

    @document_self = document_self
    @received_nodoc = true if document_self.nil?
  end

  ##
  # Does this object have a comment with content or is #received_nodoc true?

  def documented?
    @received_nodoc or !@comment.empty?
  end

  ##
  # Turns documentation on/off, and turns on/off #document_self
  # and #document_children.
  #
  # Once documentation has been turned off (by +:enddoc:+),
  # the object will refuse to turn #document_self or
  # #document_children on, so +:doc:+ and +:start_doc:+ directives
  # will have no effect in the current file.

  def done_documenting=(value)
    return unless @track_visibility
    @done_documenting  = value
    @document_self     = !value
    @document_children = @document_self
  end

  ##
  # Yields each parent of this CodeObject.  See also
  # RDoc::ClassModule#each_ancestor

  def each_parent
    code_object = self

    while code_object = code_object.parent do
      yield code_object
    end

    self
  end

  ##
  # File name where this CodeObject was found.
  #
  # See also RDoc::Context#in_files

  def file_name
    return unless @file

    @file.absolute_name
  end

  ##
  # Force the documentation of this object unless documentation
  # has been turned off by :enddoc:
  #--
  # HACK untested, was assigning to an ivar

  def force_documentation=(value)
    @force_documentation = value unless @done_documenting
  end

  ##
  # Sets the full_name overriding any computed full name.
  #
  # Set to +nil+ to clear RDoc's cached value

  def full_name= full_name
    @full_name = full_name
  end

  ##
  # Use this to ignore a CodeObject and all its children until found again
  # (#record_location is called).  An ignored item will not be displayed in
  # documentation.
  #
  # See github issue #55
  #
  # The ignored status is temporary in order to allow implementation details
  # to be hidden.  At the end of processing a file RDoc allows all classes
  # and modules to add new documentation to previously created classes.
  #
  # If a class was ignored (via stopdoc) then reopened later with additional
  # documentation it should be displayed.  If a class was ignored and never
  # reopened it should not be displayed.  The ignore flag allows this to
  # occur.

  def ignore
    return unless @track_visibility

    @ignored = true

    stop_doc
  end

  ##
  # Has this class been ignored?
  #
  # See also #ignore

  def ignored?
    @ignored
  end

  ##
  # The options instance from the store this CodeObject is attached to, or a
  # default options instance if the CodeObject is not attached.
  #
  # This is used by Text#snippet

  def options
    if @store and @store.rdoc then
      @store.rdoc.options
    else
      RDoc::Options.new
    end
  end

  ##
  # Our parent CodeObject.  The parent may be missing for classes loaded from
  # legacy RI data stores.

  def parent
    return @parent if @parent
    return nil unless @parent_name

    if @parent_class == RDoc::TopLevel then
      @parent = @store.add_file @parent_name
    else
      @parent = @store.find_class_or_module @parent_name

      return @parent if @parent

      begin
        @parent = @store.load_class @parent_name
      rescue RDoc::Store::MissingFileError
        nil
      end
    end
  end

  ##
  # File name of our parent

  def parent_file_name
    @parent ? @parent.base_name : '(unknown)'
  end

  ##
  # Name of our parent

  def parent_name
    @parent ? @parent.full_name : '(unknown)'
  end

  ##
  # Records the RDoc::TopLevel (file) where this code object was defined

  def record_location top_level
    @ignored    = false
    @suppressed = false
    @file       = top_level
  end

  ##
  # The section this CodeObject is in.  Sections allow grouping of constants,
  # attributes and methods inside a class or module.

  def section
    return @section if @section

    @section = parent.add_section @section_title if parent
  end

  ##
  # Enable capture of documentation unless documentation has been
  # turned off by :enddoc:

  def start_doc
    return if @done_documenting

    @document_self = true
    @document_children = true
    @ignored    = false
    @suppressed = false
  end

  ##
  # Disable capture of documentation

  def stop_doc
    return unless @track_visibility

    @document_self = false
    @document_children = false
  end

  ##
  # Sets the +store+ that contains this CodeObject

  def store= store
    @store = store

    return unless @track_visibility

    if :nodoc == options.visibility then
      initialize_visibility
      @track_visibility = false
    end
  end

  ##
  # Use this to suppress a CodeObject and all its children until the next file
  # it is seen in or documentation is discovered.  A suppressed item with
  # documentation will be displayed while an ignored item with documentation
  # may not be displayed.

  def suppress
    return unless @track_visibility

    @suppressed = true

    stop_doc
  end

  ##
  # Has this class been suppressed?
  #
  # See also #suppress

  def suppressed?
    @suppressed
  end

end
