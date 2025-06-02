# frozen_string_literal: true
##
# RDoc statistics collector which prints a summary and report of a project's
# documentation totals.

class RDoc::Stats

  include RDoc::Text

  ##
  # Output level for the coverage report

  attr_reader :coverage_level

  ##
  # Count of files parsed during parsing

  attr_reader :files_so_far

  ##
  # Total number of files found

  attr_reader :num_files

  ##
  # Creates a new Stats that will have +num_files+.  +verbosity+ defaults to 1
  # which will create an RDoc::Stats::Normal outputter.

  def initialize store, num_files, verbosity = 1
    @num_files = num_files
    @store     = store

    @coverage_level   = 0
    @doc_items        = nil
    @files_so_far     = 0
    @fully_documented = false
    @num_params       = 0
    @percent_doc      = nil
    @start            = Time.now
    @undoc_params     = 0

    @display = case verbosity
               when 0 then Quiet.new   num_files
               when 1 then Normal.new  num_files
               else        Verbose.new num_files
               end
  end

  ##
  # Records the parsing of an alias +as+.

  def add_alias as
    @display.print_alias as
  end

  ##
  # Records the parsing of an attribute +attribute+

  def add_attribute attribute
    @display.print_attribute attribute
  end

  ##
  # Records the parsing of a class +klass+

  def add_class klass
    @display.print_class klass
  end

  ##
  # Records the parsing of +constant+

  def add_constant constant
    @display.print_constant constant
  end

  ##
  # Records the parsing of +file+

  def add_file(file)
    @files_so_far += 1
    @display.print_file @files_so_far, file
  end

  ##
  # Records the parsing of +method+

  def add_method(method)
    @display.print_method method
  end

  ##
  # Records the parsing of a module +mod+

  def add_module(mod)
    @display.print_module mod
  end

  ##
  # Call this to mark the beginning of parsing for display purposes

  def begin_adding
    @display.begin_adding
  end

  ##
  # Calculates documentation totals and percentages for classes, modules,
  # constants, attributes and methods.

  def calculate
    return if @doc_items

    ucm = @store.unique_classes_and_modules

    classes = @store.unique_classes.reject { |cm| cm.full_name == 'Object' }

    constants = []
    ucm.each { |cm| constants.concat cm.constants }

    methods = []
    ucm.each { |cm| methods.concat cm.method_list }

    attributes = []
    ucm.each { |cm| attributes.concat cm.attributes }

    @num_attributes, @undoc_attributes = doc_stats attributes
    @num_classes,    @undoc_classes    = doc_stats classes
    @num_constants,  @undoc_constants  = doc_stats constants
    @num_methods,    @undoc_methods    = doc_stats methods
    @num_modules,    @undoc_modules    = doc_stats @store.unique_modules

    @num_items =
      @num_attributes +
      @num_classes +
      @num_constants +
      @num_methods +
      @num_modules +
      @num_params

    @undoc_items =
      @undoc_attributes +
      @undoc_classes +
      @undoc_constants +
      @undoc_methods +
      @undoc_modules +
      @undoc_params

    @doc_items = @num_items - @undoc_items
  end

  ##
  # Sets coverage report level.  Accepted values are:
  #
  # false or nil:: No report
  # 0:: Classes, modules, constants, attributes, methods
  # 1:: Level 0 + method parameters

  def coverage_level= level
    level = -1 unless level

    @coverage_level = level
  end

  ##
  # Returns the length and number of undocumented items in +collection+.

  def doc_stats collection
    visible = collection.select { |item| item.display? }
    [visible.length, visible.count { |item| not item.documented? }]
  end

  ##
  # Call this to mark the end of parsing for display purposes

  def done_adding
    @display.done_adding
  end

  ##
  # The documentation status of this project.  +true+ when 100%, +false+ when
  # less than 100% and +nil+ when unknown.
  #
  # Set by calling #calculate

  def fully_documented?
    @fully_documented
  end

  ##
  # A report that says you did a great job!

  def great_job
    report = RDoc::Markup::Document.new

    report << RDoc::Markup::Paragraph.new('100% documentation!')
    report << RDoc::Markup::Paragraph.new('Great Job!')

    report
  end

  ##
  # Calculates the percentage of items documented.

  def percent_doc
    return @percent_doc if @percent_doc

    @fully_documented = (@num_items - @doc_items) == 0

    @percent_doc = @doc_items.to_f / @num_items * 100 if @num_items.nonzero?
    @percent_doc ||= 0

    @percent_doc
  end

  ##
  # Returns a report on which items are not documented

  def report
    if @coverage_level > 0 then
      extend RDoc::Text
    end

    if @coverage_level.zero? then
      calculate

      return great_job if @num_items == @doc_items
    end

    ucm = @store.unique_classes_and_modules

    report = RDoc::Markup::Document.new
    report << RDoc::Markup::Paragraph.new('The following items are not documented:')
    report << RDoc::Markup::BlankLine.new

    ucm.sort.each do |cm|
      body = report_class_module(cm) {
        [
          report_constants(cm),
          report_attributes(cm),
          report_methods(cm),
        ].compact
      }

      report << body if body
    end

    if @coverage_level > 0 then
      calculate

      return great_job if @num_items == @doc_items
    end

    report
  end

  ##
  # Returns a report on undocumented attributes in ClassModule +cm+

  def report_attributes cm
    return if cm.attributes.empty?

    report = []

    cm.each_attribute do |attr|
      next if attr.documented?
      line = attr.line ? ":#{attr.line}" : nil
      report << "  #{attr.definition} :#{attr.name} # in file #{attr.file.full_name}#{line}\n"
      report << "\n"
    end

    report
  end

  ##
  # Returns a report on undocumented items in ClassModule +cm+

  def report_class_module cm
    return if cm.fully_documented? and @coverage_level.zero?
    return unless cm.display?

    report = RDoc::Markup::Document.new

    if cm.in_files.empty? then
      report << RDoc::Markup::Paragraph.new("#{cm.definition} is referenced but empty.")
      report << RDoc::Markup::Paragraph.new("It probably came from another project.  I'm sorry I'm holding it against you.")

      return report
    elsif cm.documented? then
      documented = true
      klass = RDoc::Markup::Verbatim.new("#{cm.definition} # is documented\n")
    else
      report << RDoc::Markup::Paragraph.new('In files:')

      list = RDoc::Markup::List.new :BULLET

      cm.in_files.each do |file|
        para = RDoc::Markup::Paragraph.new file.full_name
        list << RDoc::Markup::ListItem.new(nil, para)
      end

      report << list
      report << RDoc::Markup::BlankLine.new

      klass = RDoc::Markup::Verbatim.new("#{cm.definition}\n")
    end

    klass << "\n"

    body = yield.flatten # HACK remove #flatten

    if body.empty? then
      return if documented

      klass.parts.pop
    else
      klass.parts.concat body
    end

    klass << "end\n"

    report << klass

    report
  end

  ##
  # Returns a report on undocumented constants in ClassModule +cm+

  def report_constants cm
    return if cm.constants.empty?

    report = []

    cm.each_constant do |constant|
      # TODO constant aliases are listed in the summary but not reported
      # figure out what to do here
      next if constant.documented? || constant.is_alias_for

      line = constant.line ? ":#{constant.line}" : line
      report << "  # in file #{constant.file.full_name}#{line}\n"
      report << "  #{constant.name} = nil\n"
      report << "\n"
    end

    report
  end

  ##
  # Returns a report on undocumented methods in ClassModule +cm+

  def report_methods cm
    return if cm.method_list.empty?

    report = []

    cm.each_method do |method|
      next if method.documented? and @coverage_level.zero?

      if @coverage_level > 0 then
        params, undoc = undoc_params method

        @num_params += params

        unless undoc.empty? then
          @undoc_params += undoc.length

          undoc = undoc.map do |param| "+#{param}+" end
          param_report = "  # #{undoc.join ', '} is not documented\n"
        end
      end

      next if method.documented? and not param_report

      line = method.line ? ":#{method.line}" : nil
      scope = method.singleton ? 'self.' : nil

      report << "  # in file #{method.file.full_name}#{line}\n"
      report << param_report if param_report
      report << "  def #{scope}#{method.name}#{method.params}; end\n"
      report << "\n"
    end

    report
  end

  ##
  # Returns a summary of the collected statistics.

  def summary
    calculate

    num_width = [@num_files, @num_items].max.to_s.length
    undoc_width = [
      @undoc_attributes,
      @undoc_classes,
      @undoc_constants,
      @undoc_items,
      @undoc_methods,
      @undoc_modules,
      @undoc_params,
    ].max.to_s.length

    report = RDoc::Markup::Verbatim.new

    report << "Files:      %*d\n" % [num_width, @num_files]

    report << "\n"

    report << "Classes:    %*d (%*d undocumented)\n" % [
      num_width, @num_classes, undoc_width, @undoc_classes]
    report << "Modules:    %*d (%*d undocumented)\n" % [
      num_width, @num_modules, undoc_width, @undoc_modules]
    report << "Constants:  %*d (%*d undocumented)\n" % [
      num_width, @num_constants, undoc_width, @undoc_constants]
    report << "Attributes: %*d (%*d undocumented)\n" % [
      num_width, @num_attributes, undoc_width, @undoc_attributes]
    report << "Methods:    %*d (%*d undocumented)\n" % [
      num_width, @num_methods, undoc_width, @undoc_methods]
    report << "Parameters: %*d (%*d undocumented)\n" % [
      num_width, @num_params, undoc_width, @undoc_params] if
        @coverage_level > 0

    report << "\n"

    report << "Total:      %*d (%*d undocumented)\n" % [
      num_width, @num_items, undoc_width, @undoc_items]

    report << "%6.2f%% documented\n" % percent_doc
    report << "\n"
    report << "Elapsed: %0.1fs\n" % (Time.now - @start)

    RDoc::Markup::Document.new report
  end

  ##
  # Determines which parameters in +method+ were not documented.  Returns a
  # total parameter count and an Array of undocumented methods.

  def undoc_params method
    @formatter ||= RDoc::Markup::ToTtOnly.new

    params = method.param_list

    params = params.map { |param| param.gsub(/^\*\*?/, '') }

    return 0, [] if params.empty?

    document = parse method.comment

    tts = document.accept @formatter

    undoc = params - tts

    [params.length, undoc]
  end

  autoload :Quiet,   'rdoc/stats/quiet'
  autoload :Normal,  'rdoc/stats/normal'
  autoload :Verbose, 'rdoc/stats/verbose'

end

