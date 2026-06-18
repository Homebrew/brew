# typed: strict
# frozen_string_literal: true

require "bundle/extensions/extension"
require "json"
require "tempfile"
require "utils/popen"

module Homebrew
  module Bundle
    # Support dumping and installing Windows packages through WinGet from WSL.
    class Winget < Extension
      # Parsed WinGet package details.
      class App < T::Struct
        const :id, String
        const :name, String
        const :source, String
      end

      DEFAULT_SOURCE = "winget"
      SOURCES = T.let([DEFAULT_SOURCE, "msstore"].freeze, T::Array[String])
      ELEVATED_INSTALL_FAILURE_PATTERNS = T.let([
        /Installer failed with exit code:\s*1603/i,
        /\b(?:admin|administrator|elevat|UAC)\b/i,
      ].freeze, T::Array[Regexp])
      INSTALLER_UI_FAILURE_PATTERNS = T.let([
        /\b(?:interactive|user input|user cancelled)\b/i,
      ].freeze, T::Array[Regexp])
      INTERNAL_PACKAGE_PATTERNS = T.let([
        /\AApp Installer\z/i,
        /\A9NBLGGH4NNS1\z/i,
        /\AMicrosoft Store\z/i,
        /\AStore Experience Host\z/i,
        /\AWindows (?:Feature|Web) Experience Pack\z/i,
        /\AMicrosoft Edge WebView2 Runtime\z/i,
        /\AMicrosoft Visual C\+\+/i,
        /\AWindows App Runtime/i,
        /\AMicrosoft\.(?:AppInstaller|DesktopAppInstaller|DirectX|DotNet|Edge|EdgeWebView2Runtime|GameInput)\b/i,
        /\AMicrosoft\.(?:HEVCVideoExtension|NET\.Native|RawImageExtension)\b/i,
        /\AMicrosoft\.(?:OneDrive|WSL)\z/i,
        /\AMicrosoft\.(?:Services\.Store\.Engagement|StorePurchaseApp|UI\.Xaml|VCLibs|WindowsAppRuntime)\b/i,
        /\AMicrosoft\.(?:WindowsStore|WebMediaExtensions|WebpImageExtension|VP9VideoExtensions)\b/i,
        /\AMicrosoft\.VCRedist\./i,
        /\ANvidia\.PhysX\z/i,
      ].freeze, T::Array[Regexp])

      class << self
        sig { override.returns(Symbol) }
        def type = :winget

        sig { override.returns(String) }
        def check_label = "WinGet Package"

        sig { override.returns(String) }
        def banner_name = "WinGet packages"

        sig { override.params(description: String).returns(String) }
        def switch_description(description)
          "#{super} Note: WSL only."
        end

        sig { override.returns(T::Boolean) }
        def add_supported?
          false
        end

        sig { override.returns(T.nilable(String)) }
        def cleanup_heading
          banner_name
        end

        sig { override.params(name: String, options: Homebrew::Bundle::EntryInputOptions).returns(Dsl::Entry) }
        def entry(name, options = {})
          unknown_options = options.keys - [:id, :source]
          raise "unknown options(#{unknown_options.inspect}) for winget" if unknown_options.present?

          id = options.fetch(:id, name)
          raise "options[:id](#{id.inspect}) should be a String object" unless id.is_a?(String)

          source = options.fetch(:source, DEFAULT_SOURCE)
          raise "options[:source](#{source.inspect}) should be a String object" unless source.is_a?(String)
          unless SOURCES.include?(source)
            raise "options[:source](#{source.inspect}) should be one of #{SOURCES.inspect}"
          end

          Dsl::Entry.new(type, name, id:, source:)
        end

        sig { override.returns(T.nilable(Pathname)) }
        def package_manager_executable
          return unless OS.wsl?

          which("winget.exe", ORIGINAL_PATHS) || windows_apps_executables.find(&:executable?)
        end

        sig { returns(T::Array[Pathname]) }
        def windows_apps_executables
          [
            ENV.fetch("LOCALAPPDATA", nil)&.+("\\Microsoft\\WindowsApps\\winget.exe"),
            ENV.fetch("USERPROFILE", nil)&.+("\\AppData\\Local\\Microsoft\\WindowsApps\\winget.exe"),
            windows_local_appdata&.+("\\Microsoft\\WindowsApps\\winget.exe"),
          ].compact.uniq.filter_map do |path|
            windows_path_to_wsl_path(path) if path.exclude?("%")
          end
        end

        sig { returns(T.nilable(String)) }
        def windows_local_appdata
          cmd = which("cmd.exe", ORIGINAL_PATHS) || Pathname.new("/mnt/c/Windows/System32/cmd.exe")
          return unless cmd.executable?

          `"#{cmd}" /d /c echo %LOCALAPPDATA% 2>/dev/null`.strip.presence
        end

        sig { params(path: String).returns(T.nilable(Pathname)) }
        def windows_path_to_wsl_path(path)
          path = path.tr("\\", "/")
          return Pathname.new(path) if path.start_with?("/")

          match = path.match(%r{\A([A-Za-z]):/(.+)\z})
          return if match.nil?

          drive = match[1]
          relative_path = match[2]
          return if drive.nil? || relative_path.nil?

          Pathname.new("/mnt/#{drive.downcase}/#{relative_path}")
        end

        sig { override.void }
        def reset!
          @apps = T.let(nil, T.nilable(T::Array[App]))
          @packages = T.let(nil, T.nilable(T::Array[App]))
          @installed_app_records = T.let(nil, T.nilable(T::Array[[String, String]]))
        end

        sig { returns(T::Array[App]) }
        def apps
          apps = @apps
          return apps if apps

          @apps = if (winget = package_manager_executable)
            SOURCES.flat_map do |source|
              export_apps(winget, source:)
            end
          end
          return [] if @apps.nil?

          @apps
        end

        sig { params(winget: Pathname, source: String).returns(T::Array[App]) }
        def export_apps(winget, source:)
          names = listed_app_names(winget, source:)
          exported_apps(winget, source:).map do |app|
            App.new(id: app.id, name: names.fetch(app.id.downcase, app.name), source: app.source)
          end
        end

        sig { params(winget: Pathname, source: String).returns(T::Array[App]) }
        def exported_apps(winget, source:)
          Tempfile.create(["brew-bundle-winget", ".json"]) do |file|
            next [] unless Kernel.system(winget.to_s, "export", "--source", source, "--output",
                                         windows_export_path(file.path), "--accept-source-agreements",
                                         "--disable-interactivity", out: File::NULL, err: File::NULL)

            parse_export(File.read(file.path), source:)
          end
        end

        sig { params(winget: Pathname, source: String).returns(T::Hash[String, String]) }
        def listed_app_names(winget, source:)
          output = Utils.popen_read(winget, "list", "--source", source, "--accept-source-agreements",
                                    "--disable-interactivity", "--nowarn", err: :close)

          parse_list_names(output)
        end

        sig { params(output: String).returns(T::Hash[String, String]) }
        def parse_list_names(output)
          lines = output.encode("UTF-8", invalid: :replace, undef: :replace)
                        .delete("\r")
                        .lines
                        .map(&:chomp)
          header_index = lines.index { |line| line.match?(/\bName\s+Id\s+Version\b/) }
          return {} if header_index.nil?

          header = lines[header_index]
          return {} if header.nil?

          header_start = header.index("Name")
          id_column = header.index("Id", header_start || 0)
          version_column = header.index("Version", header_start || 0)
          return {} if header_start.nil? || id_column.nil? || version_column.nil?

          lines.drop(header_index + 1).each_with_object({}) do |line, names|
            next if line.blank? || line[header_start..].to_s.match?(/\A-+\z/)

            name = line[header_start...id_column].to_s.strip
            id = line[id_column...version_column].to_s.strip
            names[id.downcase] = name if name.present? && id.present?
          end
        end

        sig { params(path: String).returns(String) }
        def windows_export_path(path)
          wslpath = which("wslpath", ORIGINAL_PATHS)
          return path if wslpath.nil?

          Utils.safe_popen_read(wslpath, "-w", path, err: :close).chomp.presence || path
        rescue ErrorDuringExecution
          path
        end

        sig { params(output: String, source: String).returns(T::Array[App]) }
        def parse_export(output, source:)
          export = JSON.parse(output)
          return [] unless export.is_a?(Hash)

          sources = export["Sources"]
          return [] unless sources.is_a?(Array)

          sources.flat_map do |source_export|
            next [] unless source_export.is_a?(Hash)

            packages = source_export["Packages"]
            next [] unless packages.is_a?(Array)

            packages.filter_map do |package|
              next unless package.is_a?(Hash)

              id = package["PackageIdentifier"]
              next if !id.is_a?(String) || id.blank?

              App.new(id:, name: id, source:)
            end
          end
        rescue JSON::ParserError
          []
        end

        sig { override.returns(T::Array[App]) }
        def packages
          packages = @packages
          return packages if packages

          @packages = apps.reject { |app| internal_package?(app) }
                          .sort_by { |app| [SOURCES.index(app.source) || SOURCES.length, app.name.downcase] }
        end

        sig { override.returns(T::Array[App]) }
        def installed_packages
          apps
        end

        sig { params(app: App).returns(T::Boolean) }
        def internal_package?(app)
          INTERNAL_PACKAGE_PATTERNS.any? do |pattern|
            pattern.match?(app.id) || pattern.match?(app.name)
          end
        end

        sig { returns(T::Array[[String, String]]) }
        def installed_app_records
          installed_app_records = @installed_app_records
          return installed_app_records if installed_app_records

          @installed_app_records = apps.map { |app| [app.id, app.source] }
        end

        sig { override.params(package: Object).returns(String) }
        def dump_name(package)
          T.cast(package, App).name
        end

        sig { override.params(package: Object).returns(String) }
        def dump_entry(package)
          app = T.cast(package, App)
          line = "winget #{quote(app.name)}"
          line += ", id: #{quote(app.id)}" if app.id != app.name
          return line if app.source == DEFAULT_SOURCE

          "#{line}, source: #{quote(app.source)}"
        end

        sig { params(app: App).returns(String) }
        def cleanup_item(app)
          JSON.generate("id" => app.id, "name" => app.name, "source" => app.source)
        end

        sig { params(item: String).returns(String) }
        def cleanup_item_name(item)
          app = parse_cleanup_item(item)
          return app.id if app.name == app.id && app.source == DEFAULT_SOURCE
          return "#{app.id} (#{app.source})" if app.name == app.id

          return "#{app.name} (#{app.id})" if app.source == DEFAULT_SOURCE

          "#{app.name} (#{app.id}, #{app.source})"
        end

        sig { override.params(entries: T::Array[Dsl::Entry]).returns(T::Array[String]) }
        def cleanup_items(entries)
          kept_apps = entries.filter_map do |entry|
            next if entry.type != type

            [entry.options.fetch(:id, entry.name).to_s, entry.options.fetch(:source, DEFAULT_SOURCE).to_s]
          end
          return [].freeze if kept_apps.empty?

          winget = package_manager_executable
          return [].freeze if winget.nil?

          cleanup_packages = SOURCES.flat_map { |source| exported_apps(winget, source:) }
                                    .reject { |app| internal_package?(app) }
                                    .sort_by do |app|
                                      [SOURCES.index(app.source) || SOURCES.length, app.name.downcase]
                                    end
          packages_to_cleanup = cleanup_packages.reject do |app|
            kept_apps.any? { |id, source| app.id.casecmp?(id) && app.source == source }
          end
          packages_to_cleanup.map { |app| cleanup_item(app) }
        end

        sig { override.params(items: T::Array[String]).void }
        def cleanup!(items)
          winget = package_manager_executable
          return if winget.nil?

          items.each do |item|
            app = parse_cleanup_item(item)
            Bundle.system(winget, "uninstall", "--id", app.id, "--exact", "--source", app.source,
                          "--accept-source-agreements", "--disable-interactivity", verbose: false)
          end
          puts "Uninstalled #{items.size} WinGet package#{"s" if items.size != 1}"
        end

        sig { params(id: String, source: String).returns(T::Boolean) }
        def app_installed?(id, source:)
          installed_app_records.any? { |app_id, app_source| app_id.casecmp?(id) && app_source == source }
        end

        sig {
          override.params(
            name:       String,
            id:         T.nilable(String),
            with:       T.nilable(T::Array[String]),
            no_upgrade: T::Boolean,
            verbose:    T::Boolean,
            source:     String,
            options:    Homebrew::Bundle::EntryOption,
          ).returns(T::Boolean)
        }
        def preinstall!(name, id: nil, with: nil, no_upgrade: false, verbose: false, source: DEFAULT_SOURCE,
                        **options)
          _ = with
          _ = no_upgrade
          _ = options

          id ||= name

          unless package_manager_installed?
            raise "Unable to install #{name} WinGet package. winget.exe is not installed."
          end

          if app_installed?(id, source:)
            puts "Skipping install of #{name} WinGet package. It is already installed." if verbose
            return false
          end

          true
        end

        sig {
          override.params(
            name:       String,
            id:         T.nilable(String),
            with:       T.nilable(T::Array[String]),
            preinstall: T::Boolean,
            no_upgrade: T::Boolean,
            verbose:    T::Boolean,
            force:      T::Boolean,
            source:     String,
            options:    Homebrew::Bundle::EntryOption,
          ).returns(T::Boolean)
        }
        def install!(name, id: nil, with: nil, preinstall: true, no_upgrade: false, verbose: false, force: false,
                     source: DEFAULT_SOURCE, **options)
          _ = with
          _ = no_upgrade
          _ = force
          _ = options

          return true unless preinstall

          id ||= name
          winget = package_manager_executable!
          args = ["install", "--id", id, "--exact", "--source", source,
                  "--accept-source-agreements", "--accept-package-agreements",
                  "--disable-interactivity"]
          success, output = run_install_command(winget, args, verbose:, elevated: false)
          if !success && elevation_failure?(output)
            puts "WinGet install for #{name} may require Windows UAC/elevation; retrying elevated."
            success, elevated_output = run_install_command(winget, args, verbose:, elevated: true)
            output = elevated_output.presence || output
          end
          unless success
            report_install_failure(name, id:, source:, output:)
            return false
          end

          unless apps.any? { |app| app.id.casecmp?(id) && app.source == source }
            apps << App.new(id:, name:, source:)
            @packages = nil
          end
          installed_app_records << [id, source] unless installed_app_records.any? do |app_id, app_source|
            app_id.casecmp?(id) && app_source == source
          end
          true
        end

        sig {
          params(
            winget:   Pathname,
            args:     T::Array[String],
            verbose:  T::Boolean,
            elevated: T::Boolean,
          ).returns([T::Boolean, String])
        }
        def run_install_command(winget, args, verbose:, elevated:)
          return run_elevated_install_command(winget, args, verbose:) if elevated

          logs = T.let([], T::Array[String])
          success = T.let(false, T::Boolean)
          IO.popen([winget.to_s, *args], err: [:child, :out]) do |pipe|
            while (line = pipe.gets)
              print line if verbose
              logs << line
            end
            Process.wait(pipe.pid)
            success = $CHILD_STATUS.success?
            pipe.close
          end
          [success, logs.join]
        end

        sig { params(winget: Pathname, args: T::Array[String], verbose: T::Boolean).returns([T::Boolean, String]) }
        def run_elevated_install_command(winget, args, verbose:)
          powershell = which("powershell.exe", ORIGINAL_PATHS) ||
                       Pathname.new("/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe")
          return [false, "powershell.exe is not available.\n"] unless powershell.executable?

          winget_path = winget.to_s.include?("/") ? windows_export_path(winget.to_s) : winget.to_s
          argument_list = args.map { |arg| powershell_quote(arg) }.join(", ")
          script = <<~POWERSHELL
            $startProcessArgs = @{
              FilePath = #{powershell_quote(winget_path)}
              ArgumentList = @(#{argument_list})
              Verb = 'RunAs'
              Wait = $true
              PassThru = $true
            }
            $process = Start-Process @startProcessArgs
            $process.WaitForExit()
            exit $process.ExitCode
          POWERSHELL

          [Bundle.system(powershell, "-NoProfile", "-Command", script, verbose:), ""]
        end

        sig { params(value: String).returns(String) }
        def powershell_quote(value)
          "'#{value.gsub("'", "''")}'"
        end

        sig { params(output: String).returns(T::Boolean) }
        def elevation_failure?(output)
          ELEVATED_INSTALL_FAILURE_PATTERNS.any? { |pattern| output.match?(pattern) }
        end

        sig { params(output: String).returns(T::Boolean) }
        def installer_ui_failure?(output)
          INSTALLER_UI_FAILURE_PATTERNS.any? { |pattern| output.match?(pattern) }
        end

        sig { params(name: String, id: String, source: String, output: String).void }
        def report_install_failure(name, id:, source:, output:)
          puts "WinGet failed to install #{name} (#{id}) from #{source}."
          if elevation_failure?(output)
            puts "The installer may require Windows UAC/elevation."
            puts "Try installing it from an elevated Windows Terminal:"
            puts "  winget install --id #{id} --exact --source #{source} --disable-interactivity"
          elsif installer_ui_failure?(output)
            puts "The installer appears to require installer UI or user input, which brew bundle does not automate."
            puts "Install it manually from Windows:"
            puts "  winget install --id #{id} --exact --source #{source}"
          else
            puts "Try installing it manually from Windows:"
            puts "  winget install --id #{id} --exact --source #{source}"
          end
        end

        sig { params(item: String).returns(App) }
        def parse_cleanup_item(item)
          parsed = JSON.parse(item)
          raise TypeError, "Invalid WinGet cleanup item: #{item}" unless parsed.is_a?(Hash)

          id = parsed["id"]
          name = parsed["name"]
          source = parsed["source"]
          if !id.is_a?(String) || !name.is_a?(String) || !source.is_a?(String)
            raise TypeError, "Invalid WinGet cleanup item: #{item}"
          end

          App.new(id:, name:, source:)
        end
      end

      sig { override.params(entries: T::Array[Object]).returns(T::Array[Object]) }
      def format_checkable(entries)
        checkable_entries(entries).map do |entry|
          entry = T.cast(entry, Dsl::Entry)
          App.new(id: T.cast(entry.options.fetch(:id), String), name: entry.name,
                  source: T.cast(entry.options.fetch(:source), String))
        end
      end

      sig { override.params(package: Object, no_upgrade: T::Boolean).returns(T::Boolean) }
      def installed_and_up_to_date?(package, no_upgrade: false)
        _ = no_upgrade

        app = T.cast(package, App)
        self.class.app_installed?(app.id, source: app.source)
      end
    end
  end
end
