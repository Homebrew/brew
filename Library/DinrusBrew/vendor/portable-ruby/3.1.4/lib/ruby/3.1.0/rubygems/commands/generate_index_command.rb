# frozen_string_literal: true
require_relative "../command"
require_relative "../indexer"

##
# Generates a index files for use as a gem server.
#
# See `gem help generate_index`

class Gem::Commands::GenerateIndexCommand < Gem::Command
  def initialize
    super "generate_index",
          "Generates the index files for a gem server directory",
          :directory => ".", :build_modern => true

    add_option "-d", "--directory=DIRNAME",
               "repository base dir containing gems subdir" do |dir, options|
      options[:directory] = File.expand_path dir
    end

    add_option "--[no-]modern",
               "Generate indexes for RubyGems",
               "(always true)" do |value, options|
      options[:build_modern] = value
    end

    deprecate_option("--modern", version: "4.0", extra_msg: "Modern indexes (specs, latest_specs, and prerelease_specs) are always generated, so this option is not needed.")
    deprecate_option("--no-modern", version: "4.0", extra_msg: "The `--no-modern` option is currently ignored. Modern indexes (specs, latest_specs, and prerelease_specs) are always generated.")

    add_option "--update",
               "Update modern indexes with gems added",
               "since the last update" do |value, options|
      options[:update] = value
    end
  end

  def defaults_str # :nodoc:
    "--directory . --modern"
  end

  def description # :nodoc:
    <<-EOF
The generate_index command creates a set of indexes for serving gems
statically.  The command expects a 'gems' directory under the path given to
the --directory option.  The given directory will be the directory you serve
as the gem repository.

For `gem generate_index --directory /path/to/repo`, expose /path/to/repo via
your HTTP server configuration (not /path/to/repo/gems).

When done, it will generate a set of files like this:

  gems/*.gem                                   # .gem files you want to
                                               # index

  specs.<version>.gz                           # specs index
  latest_specs.<version>.gz                    # latest specs index
  prerelease_specs.<version>.gz                # prerelease specs index
  quick/Marshal.<version>/<gemname>.gemspec.rz # Marshal quick index file

The .rz extension files are compressed with the inflate algorithm.
The Marshal version number comes from ruby's Marshal::MAJOR_VERSION and
Marshal::MINOR_VERSION constants.  It is used to ensure compatibility.
    EOF
  end

  def execute
    # This is always true because it's the only way now.
    options[:build_modern] = true

    if !File.exist?(options[:directory]) ||
       !File.directory?(options[:directory])
      alert_error "unknown directory name #{options[:directory]}."
      terminate_interaction 1
    else
      indexer = Gem::Indexer.new options.delete(:directory), options

      if options[:update]
        indexer.update_index
      else
        indexer.generate_index
      end
    end
  end
end
