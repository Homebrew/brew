# typed: strict
# frozen_string_literal: true

require "language/python"
require "utils/service"

# A formula's caveats.
class Caveats
  extend Forwardable

  sig { returns(Formula) }
  attr_reader :formula

  sig { params(formula: Formula).void }
  def initialize(formula)
    @formula = formula
    @caveats = T.let(nil, T.nilable(String))
    @completions_and_elisp = T.let(nil, T.nilable(T::Array[String]))
  end

  sig { returns(String) }
  def caveats
    @caveats ||= begin
      caveats = []
      build = formula.build
      begin
        formula.build = Tab.for_formula(formula)
        string = formula.caveats.to_s
        caveats << "#{string.chomp}\n" unless string.empty?
      ensure
        formula.build = build
      end
      caveats << keg_only_text
      caveats << service_caveats
      caveats.compact.join("\n")
    end
  end

  sig { returns(T::Boolean) }
  def empty?
    caveats.blank? && completions_and_elisp.blank?
  end

  delegate [:to_s] => :caveats

  sig { returns(T::Array[String]) }
  def completions_and_elisp
    @completions_and_elisp ||= begin
      valid_shells = [:bash, :zsh, :fish, :pwsh].freeze
      current_shell = Utils::Shell.preferred || Utils::Shell.parent
      shells = if current_shell.present? &&
                  (shell_sym = current_shell.to_sym) &&
                  valid_shells.include?(shell_sym)
        [shell_sym]
      else
        valid_shells
      end
      completions_and_elisp = shells.map do |shell|
        function_completion_caveats(shell)
      end
      completions_and_elisp << elisp_caveats
      completions_and_elisp.compact
    end
  end

  sig { params(skip_reason: T::Boolean).returns(T.nilable(String)) }
  def keg_only_text(skip_reason: false)
    return unless formula.keg_only?

    s = if skip_reason
      ""
    else
      <<~EOS
        #{formula.name} is keg-only, which means it was not symlinked into #{HOMEBREW_PREFIX},
        because #{formula.keg_only_reason.to_s.chomp}.
      EOS
    end.dup

    if formula.bin.directory? || formula.sbin.directory?
      s << <<~EOS

        If you need to have #{formula.name} first in your PATH, run:
      EOS
      s << "  #{Utils::Shell.prepend_path_in_profile(formula.opt_bin.to_s)}\n" if formula.bin.directory?
      s << "  #{Utils::Shell.prepend_path_in_profile(formula.opt_sbin.to_s)}\n" if formula.sbin.directory?
    end

    if formula.lib.directory? || formula.include.directory?
      s << <<~EOS

        For compilers to find #{formula.name} you may need to set:
      EOS

      s << "  #{Utils::Shell.export_value("LDFLAGS", "-L#{formula.opt_lib}")}\n" if formula.lib.directory?

      s << "  #{Utils::Shell.export_value("CPPFLAGS", "-I#{formula.opt_include}")}\n" if formula.include.directory?

      if which("pkg-config", ORIGINAL_PATHS) &&
         ((formula.lib/"pkgconfig").directory? || (formula.share/"pkgconfig").directory?)
        s << <<~EOS

          For pkg-config to find #{formula.name} you may need to set:
        EOS

        if (formula.lib/"pkgconfig").directory?
          s << "  #{Utils::Shell.export_value("PKG_CONFIG_PATH", "#{formula.opt_lib}/pkgconfig")}\n"
        end

        if (formula.share/"pkgconfig").directory?
          s << "  #{Utils::Shell.export_value("PKG_CONFIG_PATH", "#{formula.opt_share}/pkgconfig")}\n"
        end
      end
    end
    s << "\n" unless s.end_with?("\n")
    s
  end

  private

  sig { returns(T.nilable(Keg)) }
  def keg
    @keg ||= T.let([formula.prefix, formula.opt_prefix, formula.linked_keg].filter_map do |d|
      Keg.new(d.resolved_path)
    rescue
      nil
    end.first, T.nilable(Keg))
  end

  sig { params(shell: Symbol).returns(T.nilable(String)) }
  def function_completion_caveats(shell)
    return unless (keg = self.keg)
    return unless which(shell.to_s, ORIGINAL_PATHS)

    completion_installed = keg.completion_installed?(shell)
    functions_installed = keg.functions_installed?(shell)
    return if !completion_installed && !functions_installed

    installed = []
    installed << "completions" if completion_installed
    installed << "functions" if functions_installed

    root_dir = formula.keg_only? ? formula.opt_prefix : HOMEBREW_PREFIX

    case shell
    when :bash
      <<~EOS
        Bash completion has been installed to:
          #{root_dir}/etc/bash_completion.d
      EOS
    when :fish
      fish_caveats = "fish #{installed.join(" and ")} have been installed to:"
      fish_caveats << "\n  #{root_dir}/share/fish/vendor_completions.d" if completion_installed
      fish_caveats << "\n  #{root_dir}/share/fish/vendor_functions.d" if functions_installed
      fish_caveats.freeze
    when :zsh
      <<~EOS
        zsh #{installed.join(" and ")} have been installed to:
          #{root_dir}/share/zsh/site-functions
      EOS
    when :pwsh
      <<~EOS
        PowerShell completion has been installed to:
          #{root_dir}/share/pwsh/completions
      EOS
    end
  end

  sig { returns(T.nilable(String)) }
  def elisp_caveats
    return if formula.keg_only?
    return unless (keg = self.keg)
    return unless keg.elisp_installed?

    <<~EOS
      Emacs Lisp files have been installed to:
        #{HOMEBREW_PREFIX}/share/emacs/site-lisp/#{formula.name}
    EOS
  end

  sig { returns(T.nilable(String)) }
  def service_caveats
    return if !formula.service? && !Utils::Service.installed?(formula) && !keg&.plist_installed?
    return if formula.service? && !formula.service.command? && !Utils::Service.installed?(formula)

    s = []

    # Brew services only works with these two tools
    return <<~EOS if !Utils::Service.systemctl? && !Utils::Service.launchctl? && formula.service.command?
      #{Formatter.warning("Warning:")} #{formula.name} provides a service which can only be used on macOS or systemd!
      You can manually execute the service instead with:
        #{formula.service.manual_command}
    EOS

    startup = formula.service.requires_root?
    if Utils::Service.running?(formula)
      s << "To restart #{formula.full_name} after an upgrade:"
      s << "  #{"sudo " if startup}brew services restart #{formula.full_name}"
    elsif startup
      s << "To start #{formula.full_name} now and restart at startup:"
      s << "  sudo brew services start #{formula.full_name}"
    else
      s << "To start #{formula.full_name} now and restart at login:"
      s << "  brew services start #{formula.full_name}"
    end

    if formula.service.command?
      s << "Or, if you don't want/need a background service you can just run:"
      s << "  #{formula.service.manual_command}"
    end

    # pbpaste is the system clipboard tool on macOS and fails with `tmux` by default
    # check if this is being run under `tmux` to avoid failing
    if ENV["HOMEBREW_TMUX"] && !quiet_system("/usr/bin/pbpaste")
      s << "" << "WARNING: brew services will fail when run under tmux."
    end

    "#{s.join("\n")}\n" unless s.empty?
  end
end
