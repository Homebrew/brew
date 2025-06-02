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

  require_relative 'rdoc/version'

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

  ##
  # Seaches and returns the directory for settings.
  #
  # 1. <tt>$HOME/.rdoc</tt> directory, if it exists.
  # 2. The +rdoc+ directory under the path specified by the
  #    +XDG_DATA_HOME+ environment variable, if it is set.
  # 3. <tt>$HOME/.local/share/rdoc</tt> directory.
  #
  # Other than the home directory, the containing directory will be
  # created automatically.

  def self.home
    rdoc_dir = begin
                File.expand_path('~/.rdoc')
              rescue ArgumentError
              end

    if File.directory?(rdoc_dir)
      rdoc_dir
    else
      require 'fileutils'
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

  autoload :RDoc,           "#{__dir__}/rdoc/rdoc"

  autoload :CrossReference, "#{__dir__}/rdoc/cross_reference"
  autoload :ERBIO,          "#{__dir__}/rdoc/erbio"
  autoload :ERBPartial,     "#{__dir__}/rdoc/erb_partial"
  autoload :Encoding,       "#{__dir__}/rdoc/encoding"
  autoload :Generator,      "#{__dir__}/rdoc/generator"
  autoload :Options,        "#{__dir__}/rdoc/options"
  autoload :Parser,         "#{__dir__}/rdoc/parser"
  autoload :Servlet,        "#{__dir__}/rdoc/servlet"
  autoload :RI,             "#{__dir__}/rdoc/ri"
  autoload :Stats,          "#{__dir__}/rdoc/stats"
  autoload :Store,          "#{__dir__}/rdoc/store"
  autoload :Task,           "#{__dir__}/rdoc/task"
  autoload :Text,           "#{__dir__}/rdoc/text"

  autoload :Markdown,       "#{__dir__}/rdoc/markdown"
  autoload :Markup,         "#{__dir__}/rdoc/markup"
  autoload :RD,             "#{__dir__}/rdoc/rd"
  autoload :TomDoc,         "#{__dir__}/rdoc/tom_doc"

  autoload :KNOWN_CLASSES,  "#{__dir__}/rdoc/known_classes"

  autoload :TokenStream,    "#{__dir__}/rdoc/token_stream"

  autoload :Comment,        "#{__dir__}/rdoc/comment"

  require_relative 'rdoc/i18n'

  # code objects
  #
  # We represent the various high-level code constructs that appear in Ruby
  # programs: classes, modules, methods, and so on.
  autoload :CodeObject,     "#{__dir__}/rdoc/code_object"

  autoload :Context,        "#{__dir__}/rdoc/context"
  autoload :TopLevel,       "#{__dir__}/rdoc/top_level"

  autoload :AnonClass,      "#{__dir__}/rdoc/anon_class"
  autoload :ClassModule,    "#{__dir__}/rdoc/class_module"
  autoload :NormalClass,    "#{__dir__}/rdoc/normal_class"
  autoload :NormalModule,   "#{__dir__}/rdoc/normal_module"
  autoload :SingleClass,    "#{__dir__}/rdoc/single_class"

  autoload :Alias,          "#{__dir__}/rdoc/alias"
  autoload :AnyMethod,      "#{__dir__}/rdoc/any_method"
  autoload :MethodAttr,     "#{__dir__}/rdoc/method_attr"
  autoload :GhostMethod,    "#{__dir__}/rdoc/ghost_method"
  autoload :MetaMethod,     "#{__dir__}/rdoc/meta_method"
  autoload :Attr,           "#{__dir__}/rdoc/attr"

  autoload :Constant,       "#{__dir__}/rdoc/constant"
  autoload :Mixin,          "#{__dir__}/rdoc/mixin"
  autoload :Include,        "#{__dir__}/rdoc/include"
  autoload :Extend,         "#{__dir__}/rdoc/extend"
  autoload :Require,        "#{__dir__}/rdoc/require"

end
