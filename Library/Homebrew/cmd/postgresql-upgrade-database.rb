# typed: true
# frozen_string_literal: true

require "cli/parser"
require "formula"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def postgresql_upgrade_database_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Upgrades the database for the `postgresql` formula.
      EOS

      named_args :none

      hide_from_man_page!
    end
  end

  sig { void }
  def postgresql_upgrade_database
    postgresql_upgrade_database_args.parse

    odisabled "brew postgresql_upgrade_database",
              "using new, versioned e.g. `var/postgres@14` datadir and `pg_upgrade`"

    name = "postgresql"
    pg = Formula[name]
    bin = pg.bin
    var = pg.var
    version = pg.version
    pg_version_file = var/"postgres/PG_VERSION"

    pg_version_installed = version.to_s[/^\d+/]
    pg_version_data = pg_version_file.read.chomp
    if pg_version_installed == pg_version_data
      odie <<~EOS
        #{name} data already upgraded!
      EOS
    end

    datadir = var/"postgres"
    old_datadir = var/"postgres.old"
    if old_datadir.exist?
      odie <<~EOS
        #{old_datadir} already exists!
        Remove it if you want to upgrade data automatically.
      EOS
    end

    old_pg_name = "#{name}@#{pg_version_data}"
    old_pg_glob = "#{HOMEBREW_CELLAR}/#{old_pg_name}/#{pg_version_data}.*/bin"
    old_bin = Pathname.glob(old_pg_glob).first
    old_bin ||= begin
      Formula[old_pg_name]
      ohai "brew install #{old_pg_name}"
      system HOMEBREW_BREW_FILE, "install", old_pg_name
      Pathname.glob(old_pg_glob).first
    rescue FormulaUnavailableError
      nil
    end

    odie "No #{name} #{pg_version_data}.* version installed!" unless old_bin

    server_stopped = T.let(false, T::Boolean)
    moved_data = T.let(false, T::Boolean)
    initdb_run = T.let(false, T::Boolean)
    upgraded = T.let(false, T::Boolean)

    begin
      # Following instructions from:
      # https://www.postgresql.org/docs/10/static/pgupgrade.html
      ohai "Upgrading #{name} data from #{pg_version_data} to #{pg_version_installed}..."
      services_json_output = Utils.popen_read(HOMEBREW_BREW_FILE, "services", "info", "--all", "--json")
      services_json = JSON.parse(services_json_output)
      loaded_service_names = services_json.select { |sj| sj[:loaded] }.map { |sj| sj[:name] }
      if loaded_service_names.include?(name)
        system HOMEBREW_BREW_FILE, "services", "stop", name
        service_stopped = true
      elsif quiet_system "#{bin}/pg_ctl", "-D", datadir, "status"
        system "#{bin}/pg_ctl", "-D", datadir, "stop"
        server_stopped = true
      end

      # Shut down old server if it is up via brew services
      system HOMEBREW_BREW_FILE, "services", "stop", old_pg_name if loaded_service_names.include?(old_pg_name)

      # get 'lc_collate' from old DB"
      unless quiet_system "#{old_bin}/pg_ctl", "-w", "-D", datadir, "status"
        system "#{old_bin}/pg_ctl", "-w", "-D", datadir, "start"
      end

      initdb_args = T.let([], T::Array[String])
      locale_settings = %w[
        lc_collate
        lc_ctype
        lc_messages
        lc_monetary
        lc_numeric
        lc_time
        server_encoding
      ]
      locale_settings.each do |setting|
        sql = "SELECT setting FROM pg_settings WHERE name LIKE '#{setting}';"
        value = Utils.popen_read("#{old_bin}/psql", "postgres", "-qtAX", "-U", ENV.fetch("USER"), "-c", sql).strip

        next if value.empty?

        initdb_args += if setting == "server_encoding"
          ["-E #{value}"]
        else
          ["--#{setting.tr("_", "-")}=#{value}"]
        end
      end

      if quiet_system "#{old_bin}/pg_ctl", "-w", "-D", datadir, "status"
        system "#{old_bin}/pg_ctl", "-w", "-D", datadir, "stop"
      end

      ohai "Moving #{name} data from #{datadir} to #{old_datadir}..."
      FileUtils.mv datadir, old_datadir
      moved_data = true

      (var/"postgres").mkpath
      ohai "Creating database..."
      safe_system "#{bin}/initdb", *initdb_args, "#{var}/postgres"
      initdb_run = true

      ohai "Migrating and upgrading data..."
      (var/"log").cd do
        safe_system "#{bin}/pg_upgrade",
                    "-r",
                    "-b", old_bin,
                    "-B", bin,
                    "-d", old_datadir,
                    "-D", datadir,
                    "-j", Hardware::CPU.cores.to_s
      end
      upgraded = true

      ohai "Upgraded #{name} data from #{pg_version_data} to #{pg_version_installed}!"
      ohai "Your #{name} #{pg_version_data} data remains at #{old_datadir}"
    ensure
      if upgraded
        if server_stopped
          safe_system "#{bin}/pg_ctl", "-D", datadir, "start"
        elsif service_stopped
          safe_system HOMEBREW_BREW_FILE, "services", "start", name
        end
      else
        onoe "Upgrading #{name} data from #{pg_version_data} to #{pg_version_installed} failed!"
        if initdb_run
          ohai "Removing empty #{name} initdb database..."
          FileUtils.rm_r datadir
        end
        if moved_data
          ohai "Moving #{name} data back from #{old_datadir} to #{datadir}..."
          FileUtils.mv old_datadir, datadir
        end
        if server_stopped
          system "#{bin}/pg_ctl", "-D", datadir, "start"
        elsif service_stopped
          system HOMEBREW_BREW_FILE, "services", "start", name
        end
      end
    end
  end
end
