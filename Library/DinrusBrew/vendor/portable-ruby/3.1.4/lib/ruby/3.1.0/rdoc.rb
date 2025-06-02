# frozen_string_literal: true
$DEBUG_RDOC = nil

# :main: README.rdoc

##
# RDoc produces documentation for Ruby source files by parsing the source and
# extracting the definition for classes, modules, methods, includes and
# requires.  It associates these with optional documentation contained in an
# immediately preceding comment block then renders the result using an output
# formatter.
#
# For a simple introduction to writing or generating documentation using RDoc
# see the README.
#
# == Roadmap
#
# If you think you found a bug in RDoc see CONTRIBUTING@Bugs
#
# If you want to use RDoc to create documentation for your Ruby source files,
# see RDoc::Markup and refer to <tt>rdoc --help</tt> for command line usage.
#
# If you want to set the default markup format see
# RDoc::Markup@Supported+Formats
#
# If you want to store rdoc configuration in your gem (such as the default
# markup format) see RDoc::Options@Saved+Options
#
# If you want to write documentation for Ruby files see RDoc::Parser::Ruby
#
# If you want to write documentation for extensions written in C see
# RDoc::Parser::C
#
# If you want to generate documentation using <tt>rake</tt> see RDoc::Task.
#
# If you want to drive RDoc programmatically, see RDoc::RDoc.
#
# If you want to use the library to format text blocks into HTML or other
# formats, look at RDoc::Markup.
#
# If you want to make an RDoc plugin such as a generator or directive handler
# see RDoc::RDoc.
#
# If you want to write your own output generator see RDoc::Generator.
#
# If you want an overview of how RDoc works see CONTRIBUTING
#
# == Credits
#
# RDoc is currently being maintained by Eric Hodel <drbrain@segment7.net>.
#
# Dave Thomas <dave@pragmaticprogrammer.com> is the original author of RDoc.
#
# * The Ruby parser in rdoc/parse.rb is based heavily on the outstanding
#   work of Keiju ISHITSUKA of Nippon Rational Inc, who produced the Ruby
#   parser for irb and the rtags package.

module RDoc

  ##
  # Exception thrown by any rdoc error.

  class Error < RuntimeError; end

  require 'rdoc/version'

  ##
  # Method visibilities

  VISIBILITIES = [:public, :protected, :private]

  ##
  # Name of the dotfile that contains the description of files to be processed
  # in the current directory

  DOT_DOC_FILENAME = ".document"

  ##
  # General RDoc modifiers

  GENERAL_MODIFIERS = %w[nodoc].freeze

  ##
  # RDoc modifiers for classes

  CLASS_MODIFIERS = GENERAL_MODIFIERS

  ##
  # RDoc modifiers for attributes

  ATTR_MODIFIERS = GENERAL_MODIFIERS

  ##
  # RDoc modifiers for constants

  CONSTANT_MODIFIERS = GENERAL_MODIFIERS

  ##
  # RDoc modifiers for methods

  METHOD_MODIFIERS = GENERAL_MODIFIERS +
    %w[arg args yield yields notnew not-new not_new doc]

  ##
  # Loads the best available YAML library.

  def self.load_yaml
    begin
      gem 'psych'
    rescue NameError => e # --disable-gems
      raise unless e.name == :gem
    rescue Gem::LoadError
    end

    begin
      require 'psych'
    rescue ::LoadError
    ensure
      require 'yaml'
    end
  end

  def self.home
    rdoc_dir = begin
                File.expand_path('~/.rdoc')
              rescue ArgumentError
              end

    if File.directory?(rdoc_dir)
      rdoc_dir
    else
      begin
        # XDG
        xdg_data_home = ENV["XDG_DATA_HOME"] || File.join(File.expand_path("~"), '.local', 'share')
        unless File.exist?(xdg_data_home)
          FileUtils.mkdir_p xdg_data_home
        end
        File.join xdg_data_home, "rdoc"
      rescue Errno::EACCES
      end
    end
  end

  autoload :RDoc,           'rdoc/rdoc'

  autoload :CrossReference, 'rdoc/cross_reference'
  autoload :ERBIO,          'rdoc/erbio'
  autoload :ERBPartial,     'rdoc/erb_partial'
  autoload :Encoding,       'rdoc/encoding'
  autoload :Generator,      'rdoc/generator'
  autoload :Options,        'rdoc/options'
  autoload :Parser,         'rdoc/parser'
  autoload :Servlet,        'rdoc/servlet'
  autoload :RI,             'rdoc/ri'
  autoload :Stats,          'rdoc/stats'
  autoload :Store,          'rdoc/store'
  autoload :Task,           'rdoc/task'
  autoload :Text,           'rdoc/text'

  autoload :Markdown,       'rdoc/markdown'
  autoload :Markup,         'rdoc/markup'
  autoload :RD,             'rdoc/rd'
  autoload :TomDoc,         'rdoc/tom_doc'

  autoload :KNOWN_CLASSES,  'rdoc/known_classes'

  autoload :TokenStream,    'rdoc/token_stream'

  autoload :Comment,        'rdoc/comment'

  require 'rdoc/i18n'

  # code objects
  #
  # We represent the various high-level code constructs that appear in Ruby
  # programs: classes, modules, methods, and so on.
  autoload :CodeObject,     'rdoc/code_object'

  autoload :Context,        'rdoc/context'
  autoload :TopLevel,       'rdoc/top_level'

  autoload :AnonClass,      'rdoc/anon_class'
  autoload :ClassModule,    'rdoc/class_module'
  autoload :NormalClass,    'rdoc/normal_class'
  autoload :NormalModule,   'rdoc/normal_module'
  autoload :SingleClass,    'rdoc/single_class'

  autoload :Alias,          'rdoc/alias'
  autoload :AnyMethod,      'rdoc/any_method'
  autoload :MethodAttr,     'rdoc/method_attr'
  autoload :GhostMethod,    'rdoc/ghost_method'
  autoload :MetaMethod,     'rdoc/meta_method'
  autoload :Attr,           'rdoc/attr'

  autoload :Constant,       'rdoc/constant'
  autoload :Mixin,          'rdoc/mixin'
  autoload :Include,        'rdoc/include'
  autoload :Extend,         'rdoc/extend'
  autoload :Require,        'rdoc/require'

end
