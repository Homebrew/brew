# frozen_string_literal: true

require_relative "../command"

##
# Installs RubyGems itself.  This command is ordinarily only available from a
# RubyGems checkout or tarball.

class Gem::Commands::SetupCommand < Gem::Command
  HISTORY_HEADER = %r{^#\s*[\d.a-zA-Z]+\s*/\s*\d{4}-\d{2}-\d{2}\s*$}
  VERSION_MATCHER = %r{^#\s*([\d.a-zA-Z]+)\s*/\s*\d{4}-\d{2}-\d{2}\s*$}

  ENV_PATHS = %w[/usr/bin/env /bin/env].freeze

  def initialize
    super "setup", "Install RubyGems",
          format_executable: false, document: %w[ri],
          force: true,
          site_or_vendor: "sitelibdir",
          destdir: "", prefix: "", previous_version: "",
          regenerate_binstubs: true,
          regenerate_plugins: true

    add_option "--previous-version=VERSION",
               "Previous version of RubyGems",
               "Used for changelog processing" do |version, options|
      options[:previous_version] = version
    end

    add_option "--prefix=PREFIX",
               "Prefix path for installing RubyGems",
               "Will not affect gem repository location" do |prefix, options|
      options[:prefix] = File.expand_path prefix
    end

    add_option "--destdir=DESTDIR",
               "Root directory to install RubyGems into",
               "Mainly used for packaging RubyGems" do |destdir, options|
      options[:destdir] = File.expand_path destdir
    end

    add_option "--[no-]vendor",
               "Install into vendorlibdir not sitelibdir" do |vendor, options|
      options[:site_or_vendor] = vendor ? "vendorlibdir" : "sitelibdir"
    end

    add_option "--[no-]format-executable",
               "Makes `gem` match ruby",
               "If Ruby is ruby18, gem will be gem18" do |value, options|
      options[:format_executable] = value
    end

    add_option "--[no-]document [TYPES]", Array,
               "Generate documentation for RubyGems",
               "List the documentation types you wish to",
               "generate.  For example: rdoc,ri" do |value, options|
      options[:document] = case value
                           when nil   then %w[rdoc ri]
                           when false then []
                           else value
      end
    end

    add_option "--[no-]rdoc",
               "Generate RDoc documentation for RubyGems" do |value, options|
      if value
        options[:document] << "rdoc"
      else
        options[:document].delete "rdoc"
      end

      options[:document].uniq!
    end

    add_option "--[no-]ri",
               "Generate RI documentation for RubyGems" do |value, options|
      if value
        options[:document] << "ri"
      else
        options[:document].delete "ri"
      end

      options[:document].uniq!
    end

    add_option "--[no-]regenerate-binstubs",
               "Regenerate gem binstubs" do |value, options|
      options[:regenerate_binstubs] = value
    end

    add_option "--[no-]regenerate-plugins",
               "Regenerate gem plugins" do |value, options|
      options[:regenerate_plugins] = value
    end

    add_option "-f", "--[no-]force",
               "Forcefully overwrite binstubs" do |value, options|
      options[:force] = value
    end

    add_option("-E", "--[no-]env-shebang",
               "Rewrite executables with a shebang",
               "of /usr/bin/env") do |value, options|
      options[:env_shebang] = value
    end

    @verbose = nil
  end

  def check_ruby_version
    required_version = Gem::Requirement.new ">= 2.6.0"

    unless required_version.satisfied_by? Gem.ruby_version
      alert_error "Expected Ruby version #{required_version}, is #{Gem.ruby_version}"
      terminate_interaction 1
    end
  end

  def defaults_str # :nodoc:
    "--format-executable --document ri --regenerate-binstubs"
  end

  def description # :nodoc:
    <<-EOF
Installs RubyGems itself.

RubyGems installs RDoc for itself in GEM_HOME.  By default this is:
  #{Gem.dir}

If you prefer a different directory, set the GEM_HOME environment variable.

RubyGems will install the gem command with a name matching ruby's
prefix and suffix.  If ruby was installed as `ruby18`, gem will be
installed as `gem18`.

By default, this RubyGems will install gem as:
  #{Gem.default_exec_format % "gem"}
    EOF
  end

  module MakeDirs
    def mkdir_p(path, **opts)
      super
      (@mkdirs ||= []) << path
    end
  end

  def execute
    @verbose = Gem.configuration.really_verbose

    check_ruby_version

    require "fileutils"
    if Gem.configuration.really_verbose
      extend FileUtils::Verbose
    else
      extend FileUtils
    end
    extend MakeDirs

    lib_dir, bin_dir = make_destination_dirs
    man_dir = generate_default_man_dir

    install_lib lib_dir

    install_executables bin_dir

    remove_old_bin_files bin_dir

    remove_old_lib_files lib_dir

    # Can be removed one we drop support for bundler 2.2.3 (the last version installing man files to man_dir)
    remove_old_man_files man_dir if man_dir && File.exist?(man_dir)

    install_default_bundler_gem bin_dir

    if mode = options[:dir_mode]
      @mkdirs.uniq!
      File.chmod(mode, @mkdirs)
    end

    say "RubyGems #{Gem::VERSION} installed"

    regenerate_binstubs(bin_dir) if options[:regenerate_binstubs]
    regenerate_plugins(bin_dir) if options[:regenerate_plugins]

    uninstall_old_gemcutter

    documentation_success = install_rdoc

    say
    if @verbose
      say "-" * 78
      say
    end

    if options[:previous_version].empty?
      options[:previous_version] = Gem::VERSION.sub(/[0-9]+$/, "0")
    end

    options[:previous_version] = Gem::Version.new(options[:previous_version])

    show_release_notes

    say
    say "-" * 78
    say

    say "RubyGems installed the following executables:"
    say bin_file_names.map {|name| "\t#{name}\n" }
    say

    unless bin_file_names.grep(/#{File::SEPARATOR}gem$/)
      say "If `gem` was installed by a previous RubyGems installation, you may need"
      say "to remove it by hand."
      say
    end

    if documentation_success
      if options[:document].include? "rdoc"
        say "Rdoc documentation was installed. You may now invoke:"
        say "  gem server"
        say "and then peruse beautifully formatted documentation for your gems"
        say "with your web browser."
        say "If you do not wish to install this documentation in the future, use the"
        say "--no-document flag, or set it as the default in your ~/.gemrc file. See"
        say "'gem help env' for details."
        say
      end

      if options[:document].include? "ri"
        say "Ruby Interactive (ri) documentation was installed. ri is kind of like man "
        say "pages for Ruby libraries. You may access it like this:"
        say "  ri Classname"
        say "  ri Classname.class_method"
        say "  ri Classname#instance_method"
        say "If you do not wish to install this documentation in the future, use the"
        say "--no-document flag, or set it as the default in your ~/.gemrc file. See"
        say "'gem help env' for details."
        say
      end
    end
  end

  def install_executables(bin_dir)
    prog_mode = options[:prog_mode] || 0o755

    executables = { "gem" => "exe" }
    executables.each do |tool, path|
      say "Installing #{tool} executable" if @verbose

      Dir.chdir path do
        bin_file = "gem"

        require "tmpdir"

        dest_file = target_bin_path(bin_dir, bin_file)
        bin_tmp_file = File.join Dir.tmpdir, "#{bin_file}.#{$$}"

        begin
          bin = File.readlines bin_file
          bin[0] = shebang

          File.open bin_tmp_file, "w" do |fp|
            fp.puts bin.join
          end

          install bin_tmp_file, dest_file, mode: prog_mode
          bin_file_names << dest_file
        ensure
          rm bin_tmp_file
        end

        next unless Gem.win_platform?

        begin
          bin_cmd_file = File.join Dir.tmpdir, "#{bin_file}.bat"

          File.open bin_cmd_file, "w" do |file|
            file.puts <<-TEXT
  @ECHO OFF
  IF NOT "%~f0" == "~f0" GOTO :WinNT
  @"#{File.basename(Gem.ruby).chomp('"')}" "#{dest_file}" %1 %2 %3 %4 %5 %6 %7 %8 %9
  GOTO :EOF
  :WinNT
  @"#{File.basename(Gem.ruby).chomp('"')}" "%~dpn0" %*
  TEXT
          end

          install bin_cmd_file, "#{dest_file}.bat", mode: prog_mode
        ensure
          rm bin_cmd_file
        end
      end
    end
  end

  def shebang
    if options[:env_shebang]
      ruby_name = RbConfig::CONFIG["ruby_install_name"]
      @env_path ||= ENV_PATHS.find {|env_path| File.executable? env_path }
      "#!#{@env_path} #{ruby_name}\n"
    else
      "#!#{Gem.ruby}\n"
    end
  end

  def install_lib(lib_dir)
    libs = { "RubyGems" => "lib" }
    libs["Bundler"] = "bundler/lib"
    libs.each do |tool, path|
      say "Installing #{tool}" if @verbose

      lib_files = files_in path

      Dir.chdir path do
        install_file_list(lib_files, lib_dir)
      end
    end
  end

  def install_rdoc
    gem_doc_dir = File.join Gem.dir, "doc"
    rubygems_name = "rubygems-#{Gem::VERSION}"
    rubygems_doc_dir = File.join gem_doc_dir, rubygems_name

    begin
      Gem.ensure_gem_subdirectories Gem.dir
    rescue SystemCallError
      # ignore
    end

    if File.writable?(gem_doc_dir) &&
       (!File.exist?(rubygems_doc_dir) ||
        File.writable?(rubygems_doc_dir))
      say "Removing old RubyGems RDoc and ri" if @verbose
      Dir[File.join(Gem.dir, "doc", "rubygems-[0-9]*")].each do |dir|
        rm_rf dir
      end

      require_relative "../rdoc"

      return false unless defined?(Gem::RDoc)

      fake_spec = Gem::Specification.new "rubygems", Gem::VERSION
      def fake_spec.full_gem_path
        File.expand_path "../../..", __dir__
      end

      generate_ri   = options[:document].include? "ri"
      generate_rdoc = options[:document].include? "rdoc"

      rdoc = Gem::RDoc.new fake_spec, generate_rdoc, generate_ri
      rdoc.generate

      return true
    elsif @verbose
      say "Skipping RDoc generation, #{gem_doc_dir} not writable"
      say "Set the GEM_HOME environment variable if you want RDoc generated"
    end

    false
  end

  def install_default_bundler_gem(bin_dir)
    current_default_spec = Gem::Specification.default_stubs.find {|s| s.name == "bundler" }
    specs_dir = if current_default_spec && default_dir == Gem.default_dir
      Gem::Specification.remove_spec current_default_spec
      loaded_from = current_default_spec.loaded_from
      File.delete(loaded_from)
      File.dirname(loaded_from)
    else
      target_specs_dir = File.join(default_dir, "specifications", "default")
      mkdir_p target_specs_dir, mode: 0o755
      target_specs_dir
    end

    new_bundler_spec = Dir.chdir("bundler") { Gem::Specification.load("bundler.gemspec") }
    full_name = new_bundler_spec.full_name
    gemspec_path = "#{full_name}.gemspec"

    default_spec_path = File.join(specs_dir, gemspec_path)
    Gem.write_binary(default_spec_path, new_bundler_spec.to_ruby)

    bundler_spec = Gem::Specification.load(default_spec_path)

    # Remove gemspec that was same version of vendored bundler.
    normal_gemspec = File.join(default_dir, "specifications", gemspec_path)
    if File.file? normal_gemspec
      File.delete normal_gemspec
    end

    # Remove gem files that were same version of vendored bundler.
    if File.directory? bundler_spec.gems_dir
      Dir.entries(bundler_spec.gems_dir).
        select {|default_gem| File.basename(default_gem) == full_name }.
        each {|default_gem| rm_r File.join(bundler_spec.gems_dir, default_gem) }
    end

    require_relative "../installer"

    Dir.chdir("bundler") do
      built_gem = Gem::Package.build(new_bundler_spec)
      begin
        Gem::Installer.at(
          built_gem,
          env_shebang: options[:env_shebang],
          format_executable: options[:format_executable],
          force: options[:force],
          install_as_default: true,
          bin_dir: bin_dir,
          install_dir: default_dir,
          wrappers: true
        ).install
      ensure
        FileUtils.rm_f built_gem
      end
    end

    new_bundler_spec.executables.each {|executable| bin_file_names << target_bin_path(bin_dir, executable) }

    say "Bundler #{new_bundler_spec.version} installed"
  end

  def make_destination_dirs
    lib_dir, bin_dir = Gem.default_rubygems_dirs

    unless lib_dir
      lib_dir, bin_dir = generate_default_dirs
    end

    mkdir_p lib_dir, mode: 0o755
    mkdir_p bin_dir, mode: 0o755

    [lib_dir, bin_dir]
  end

  def generate_default_man_dir
    prefix = options[:prefix]

    if prefix.empty?
      man_dir = RbConfig::CONFIG["mandir"]
      return unless man_dir
    else
      man_dir = File.join prefix, "man"
    end

    prepend_destdir_if_present(man_dir)
  end

  def generate_default_dirs
    prefix = options[:prefix]
    site_or_vendor = options[:site_or_vendor]

    if prefix.empty?
      lib_dir = RbConfig::CONFIG[site_or_vendor]
      bin_dir = RbConfig::CONFIG["bindir"]
    else
      lib_dir = File.join prefix, "lib"
      bin_dir = File.join prefix, "bin"
    end

    [prepend_destdir_if_present(lib_dir), prepend_destdir_if_present(bin_dir)]
  end

  def files_in(dir)
    Dir.chdir dir do
      Dir.glob(File.join("**", "*"), File::FNM_DOTMATCH).
        select {|f| !File.directory?(f) }
    end
  end

  def remove_old_bin_files(bin_dir)
    old_bin_files = {
      "gem_mirror" => "gem mirror",
      "gem_server" => "gem server",
      "gemlock" => "gem lock",
      "gemri" => "ri",
      "gemwhich" => "gem which",
      "index_gem_repository.rb" => "gem generate_index",
    }

    old_bin_files.each do |old_bin_file, new_name|
      old_bin_path = File.join bin_dir, old_bin_file
      next unless File.exist? old_bin_path

      deprecation_message = "`#{old_bin_file}` has been deprecated. Use `#{new_name}` instead."

      File.open old_bin_path, "w" do |fp|
        fp.write <<-EOF
#!#{Gem.ruby}

abort "#{deprecation_message}"
    EOF
      end

      next unless Gem.win_platform?

      File.open "#{old_bin_path}.bat", "w" do |fp|
        fp.puts %(@ECHO.#{deprecation_message})
      end
    end
  end

  def remove_old_lib_files(lib_dir)
    lib_dirs = { File.join(lib_dir, "rubygems") => "lib/rubygems" }
    lib_dirs[File.join(lib_dir, "bundler")] = "bundler/lib/bundler"
    lib_dirs.each do |old_lib_dir, new_lib_dir|
      lib_files = files_in(new_lib_dir)

      old_lib_files = files_in(old_lib_dir)

      to_remove = old_lib_files - lib_files

      gauntlet_rubygems = File.join(lib_dir, "gauntlet_rubygems.rb")
      to_remove << gauntlet_rubygems if File.exist? gauntlet_rubygems

      to_remove.delete_if do |file|
        file.start_with? "defaults"
      end

      remove_file_list(to_remove, old_lib_dir)
    end
  end

  def remove_old_man_files(old_man_dir)
    old_man1_dir = "#{old_man_dir}/man1"

    if File.exist?(old_man1_dir)
      man1_to_remove = Dir.chdir(old_man1_dir) { Dir["bundle*.1{,.txt,.ronn}"] }

      remove_file_list(man1_to_remove, old_man1_dir)
    end

    old_man5_dir = "#{old_man_dir}/man5"

    if File.exist?(old_man5_dir)
      man5_to_remove = Dir.chdir(old_man5_dir) { Dir["gemfile.5{,.txt,.ronn}"] }

      remove_file_list(man5_to_remove, old_man5_dir)
    end
  end

  def show_release_notes
    release_notes = File.join Dir.pwd, "CHANGELOG.md"

    release_notes =
      if File.exist? release_notes
        history = File.read release_notes

        history.force_encoding Encoding::UTF_8

        text = history.split(HISTORY_HEADER)
        text.shift # correct an off-by-one generated by split
        version_lines = history.scan(HISTORY_HEADER)
        versions = history.scan(VERSION_MATCHER).flatten.map do |x|
          Gem::Version.new(x)
        end

        history_string = ""

        until versions.length == 0 ||
              versions.shift <= options[:previous_version] do
          history_string += version_lines.shift + text.shift
        end

        history_string
      else
        "Oh-no! Unable to find release notes!"
      end

    say release_notes
  end

  def uninstall_old_gemcutter
    require_relative "../uninstaller"

    ui = Gem::Uninstaller.new("gemcutter", all: true, ignore: true,
                                           version: "< 0.4")
    ui.uninstall
  rescue Gem::InstallError
  end

  def regenerate_binstubs(bindir)
    require_relative "pristine_command"
    say "Regenerating binstubs"

    args = %w[--all --only-executables --silent]
    args << "--bindir=#{bindir}"
    args << "--install-dir=#{default_dir}"

    if options[:env_shebang]
      args << "--env-shebang"
    end

    command = Gem::Commands::PristineCommand.new
    command.invoke(*args)
  end

  def regenerate_plugins(bindir)
    require_relative "pristine_command"
    say "Regenerating plugins"

    args = %w[--all --only-plugins --silent]
    args << "--bindir=#{bindir}"
    args << "--install-dir=#{default_dir}"

    command = Gem::Commands::PristineCommand.new
    command.invoke(*args)
  end

  private

  def default_dir
    prefix = options[:prefix]

    if prefix.empty?
      dir = Gem.default_dir
    else
      dir = prefix
    end

    prepend_destdir_if_present(dir)
  end

  def prepend_destdir_if_present(path)
    destdir = options[:destdir]
    return path if destdir.empty?

    File.join(options[:destdir], path.gsub(/^[a-zA-Z]:/, ""))
  end

  def install_file_list(files, dest_dir)
    files.each do |file|
      install_file file, dest_dir
    end
  end

  def install_file(file, dest_dir)
    dest_file = File.join dest_dir, file
    dest_dir = File.dirname dest_file
    unless File.directory? dest_dir
      mkdir_p dest_dir, mode: 0o755
    end

    install file, dest_file, mode: options[:data_mode] || 0o644
  end

  def remove_file_list(files, dir)
    Dir.chdir dir do
      files.each do |file|
        FileUtils.rm_f file

        warn "unable to remove old file #{file} please remove it by hand" if
          File.exist? file
      end
    end
  end

  def target_bin_path(bin_dir, bin_file)
    bin_file_formatted = if options[:format_executable]
      Gem.default_exec_format % bin_file
    else
      bin_file
    end
    File.join bin_dir, bin_file_formatted
  end

  def bin_file_names
    @bin_file_names ||= []
  end
end
