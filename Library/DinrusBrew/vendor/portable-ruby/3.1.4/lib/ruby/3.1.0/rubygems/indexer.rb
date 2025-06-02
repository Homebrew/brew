# frozen_string_literal: true
require_relative "../rubygems"
require_relative "package"
require "tmpdir"

##
# Top level class for building the gem repository index.

class Gem::Indexer
  include Gem::UserInteraction

  ##
  # Build indexes for RubyGems 1.2.0 and newer when true

  attr_accessor :build_modern

  ##
  # Index install location

  attr_reader :dest_directory

  ##
  # Specs index install location

  attr_reader :dest_specs_index

  ##
  # Latest specs index install location

  attr_reader :dest_latest_specs_index

  ##
  # Prerelease specs index install location

  attr_reader :dest_prerelease_specs_index

  ##
  # Index build directory

  attr_reader :directory

  ##
  # Create an indexer that will index the gems in +directory+.

  def initialize(directory, options = {})
    require "fileutils"
    require "tmpdir"
    require "zlib"

    options = { :build_modern => true }.merge options

    @build_modern = options[:build_modern]

    @dest_directory = directory
    @directory = Dir.mktmpdir "gem_generate_index"

    marshal_name = "Marshal.#{Gem.marshal_version}"

    @master_index = File.join @directory, "yaml"
    @marshal_index = File.join @directory, marshal_name

    @quick_dir = File.join @directory, "quick"
    @quick_marshal_dir = File.join @quick_dir, marshal_name
    @quick_marshal_dir_base = File.join "quick", marshal_name # FIX: UGH

    @quick_index = File.join @quick_dir, "index"
    @latest_index = File.join @quick_dir, "latest_index"

    @specs_index = File.join @directory, "specs.#{Gem.marshal_version}"
    @latest_specs_index =
      File.join(@directory, "latest_specs.#{Gem.marshal_version}")
    @prerelease_specs_index =
      File.join(@directory, "prerelease_specs.#{Gem.marshal_version}")
    @dest_specs_index =
      File.join(@dest_directory, "specs.#{Gem.marshal_version}")
    @dest_latest_specs_index =
      File.join(@dest_directory, "latest_specs.#{Gem.marshal_version}")
    @dest_prerelease_specs_index =
      File.join(@dest_directory, "prerelease_specs.#{Gem.marshal_version}")

    @files = []
  end

  ##
  # Build various indices

  def build_indices
    specs = map_gems_to_specs gem_file_list
    Gem::Specification._resort! specs
    build_marshal_gemspecs specs
    build_modern_indices specs if @build_modern

    compress_indices
  end

  ##
  # Builds Marshal quick index gemspecs.

  def build_marshal_gemspecs(specs)
    count = specs.count
    progress = ui.progress_reporter count,
                                    "Generating Marshal quick index gemspecs for #{count} gems",
                                    "Complete"

    files = []

    Gem.time "Generated Marshal quick index gemspecs" do
      specs.each do |spec|
        next if spec.default_gem?
        spec_file_name = "#{spec.original_name}.gemspec.rz"
        marshal_name = File.join @quick_marshal_dir, spec_file_name

        marshal_zipped = Gem.deflate Marshal.dump(spec)

        File.open marshal_name, "wb" do |io|
          io.write marshal_zipped
        end

        files << marshal_name

        progress.updated spec.original_name
      end

      progress.done
    end

    @files << @quick_marshal_dir

    files
  end

  ##
  # Build a single index for RubyGems 1.2 and newer

  def build_modern_index(index, file, name)
    say "Generating #{name} index"

    Gem.time "Generated #{name} index" do
      File.open(file, "wb") do |io|
        specs = index.map do |*spec|
          # We have to splat here because latest_specs is an array, while the
          # others are hashes.
          spec = spec.flatten.last
          platform = spec.original_platform

          # win32-api-1.0.4-x86-mswin32-60
          unless String === platform
            alert_warning "Skipping invalid platform in gem: #{spec.full_name}"
            next
          end

          platform = Gem::Platform::RUBY if platform.nil? || platform.empty?
          [spec.name, spec.version, platform]
        end

        specs = compact_specs(specs)
        Marshal.dump(specs, io)
      end
    end
  end

  ##
  # Builds indices for RubyGems 1.2 and newer. Handles full, latest, prerelease

  def build_modern_indices(specs)
    prerelease, released = specs.partition do |s|
      s.version.prerelease?
    end
    latest_specs =
      Gem::Specification._latest_specs specs

    build_modern_index(released.sort, @specs_index, "specs")
    build_modern_index(latest_specs.sort, @latest_specs_index, "latest specs")
    build_modern_index(prerelease.sort, @prerelease_specs_index,
                       "prerelease specs")

    @files += [@specs_index,
               "#{@specs_index}.gz",
               @latest_specs_index,
               "#{@latest_specs_index}.gz",
               @prerelease_specs_index,
               "#{@prerelease_specs_index}.gz"]
  end

  def map_gems_to_specs(gems)
    gems.map do |gemfile|
      if File.size(gemfile) == 0
        alert_warning "Skipping zero-length gem: #{gemfile}"
        next
      end

      begin
        spec = Gem::Package.new(gemfile).spec
        spec.loaded_from = gemfile

        spec.abbreviate
        spec.sanitize

        spec
      rescue SignalException
        alert_error "Received signal, exiting"
        raise
      rescue Exception => e
        msg = ["Unable to process #{gemfile}",
               "#{e.message} (#{e.class})",
               "\t#{e.backtrace.join "\n\t"}"].join("\n")
        alert_error msg
      end
    end.compact
  end

  ##
  # Compresses indices on disk
  #--
  # All future files should be compressed using gzip, not deflate

  def compress_indices
    say "Compressing indices"

    Gem.time "Compressed indices" do
      if @build_modern
        gzip @specs_index
        gzip @latest_specs_index
        gzip @prerelease_specs_index
      end
    end
  end

  ##
  # Compacts Marshal output for the specs index data source by using identical
  # objects as much as possible.

  def compact_specs(specs)
    names = {}
    versions = {}
    platforms = {}

    specs.map do |(name, version, platform)|
      names[name] = name unless names.include? name
      versions[version] = version unless versions.include? version
      platforms[platform] = platform unless platforms.include? platform

      [names[name], versions[version], platforms[platform]]
    end
  end

  ##
  # Compress +filename+ with +extension+.

  def compress(filename, extension)
    data = Gem.read_binary filename

    zipped = Gem.deflate data

    File.open "#{filename}.#{extension}", "wb" do |io|
      io.write zipped
    end
  end

  ##
  # List of gem file names to index.

  def gem_file_list
    Gem::Util.glob_files_in_dir("*.gem", File.join(@dest_directory, "gems"))
  end

  ##
  # Builds and installs indices.

  def generate_index
    make_temp_directories
    build_indices
    install_indices
  rescue SignalException
  ensure
    FileUtils.rm_rf @directory
  end

  ##
  # Zlib::GzipWriter wrapper that gzips +filename+ on disk.

  def gzip(filename)
    Zlib::GzipWriter.open "#{filename}.gz" do |io|
      io.write Gem.read_binary(filename)
    end
  end

  ##
  # Install generated indices into the destination directory.

  def install_indices
    verbose = Gem.configuration.really_verbose

    say "Moving index into production dir #{@dest_directory}" if verbose

    files = @files
    files.delete @quick_marshal_dir if files.include? @quick_dir

    if files.include?(@quick_marshal_dir) && !files.include?(@quick_dir)
      files.delete @quick_marshal_dir

      dst_name = File.join(@dest_directory, @quick_marshal_dir_base)

      FileUtils.mkdir_p File.dirname(dst_name), :verbose => verbose
      FileUtils.rm_rf dst_name, :verbose => verbose
      FileUtils.mv(@quick_marshal_dir, dst_name,
                   :verbose => verbose, :force => true)
    end

    files = files.map do |path|
      path.sub(/^#{Regexp.escape @directory}\/?/, "") # HACK?
    end

    files.each do |file|
      src_name = File.join @directory, file
      dst_name = File.join @dest_directory, file

      FileUtils.rm_rf dst_name, :verbose => verbose
      FileUtils.mv(src_name, @dest_directory,
                   :verbose => verbose, :force => true)
    end
  end

  ##
  # Make directories for index generation

  def make_temp_directories
    FileUtils.rm_rf @directory
    FileUtils.mkdir_p @directory, :mode => 0700
    FileUtils.mkdir_p @quick_marshal_dir
  end

  ##
  # Ensure +path+ and path with +extension+ are identical.

  def paranoid(path, extension)
    data = Gem.read_binary path
    compressed_data = Gem.read_binary "#{path}.#{extension}"

    unless data == Gem::Util.inflate(compressed_data)
      raise "Compressed file #{compressed_path} does not match uncompressed file #{path}"
    end
  end

  ##
  # Perform an in-place update of the repository from newly added gems.

  def update_index
    make_temp_directories

    specs_mtime = File.stat(@dest_specs_index).mtime
    newest_mtime = Time.at 0

    updated_gems = gem_file_list.select do |gem|
      gem_mtime = File.stat(gem).mtime
      newest_mtime = gem_mtime if gem_mtime > newest_mtime
      gem_mtime >= specs_mtime
    end

    if updated_gems.empty?
      say "No new gems"
      terminate_interaction 0
    end

    specs = map_gems_to_specs updated_gems
    prerelease, released = specs.partition {|s| s.version.prerelease? }

    files = build_marshal_gemspecs specs

    Gem.time "Updated indexes" do
      update_specs_index released, @dest_specs_index, @specs_index
      update_specs_index released, @dest_latest_specs_index, @latest_specs_index
      update_specs_index(prerelease,
                         @dest_prerelease_specs_index,
                         @prerelease_specs_index)
    end

    compress_indices

    verbose = Gem.configuration.really_verbose

    say "Updating production dir #{@dest_directory}" if verbose

    files << @specs_index
    files << "#{@specs_index}.gz"
    files << @latest_specs_index
    files << "#{@latest_specs_index}.gz"
    files << @prerelease_specs_index
    files << "#{@prerelease_specs_index}.gz"

    files = files.map do |path|
      path.sub(/^#{Regexp.escape @directory}\/?/, "") # HACK?
    end

    files.each do |file|
      src_name = File.join @directory, file
      dst_name = File.join @dest_directory, file # REFACTOR: duped above

      FileUtils.mv src_name, dst_name, :verbose => verbose,
                   :force => true

      File.utime newest_mtime, newest_mtime, dst_name
    end
  ensure
    FileUtils.rm_rf @directory
  end

  ##
  # Combines specs in +index+ and +source+ then writes out a new copy to
  # +dest+.  For a latest index, does not ensure the new file is minimal.

  def update_specs_index(index, source, dest)
    specs_index = Marshal.load Gem.read_binary(source)

    index.each do |spec|
      platform = spec.original_platform
      platform = Gem::Platform::RUBY if platform.nil? || platform.empty?
      specs_index << [spec.name, spec.version, platform]
    end

    specs_index = compact_specs specs_index.uniq.sort

    File.open dest, "wb" do |io|
      Marshal.dump specs_index, io
    end
  end
end
