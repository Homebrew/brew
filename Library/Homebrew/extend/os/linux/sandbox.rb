# typed: strict
# frozen_string_literal: true

require "pathname"

class Sandbox
  PODMAN_EXEC = "/usr/bin/podman"

  def self.available?
    ENV["HOMEBREW_USE_LINUX_SANDBOX"] == "1" and File.executable?(PODMAN_EXEC)
  end

  sig { void }
  def allow_write_temp_and_cache
    allow_write_path HOMEBREW_CACHE
  end

  sig { params(path: T.any(String, Pathname)).void }
  def allow_write_path(path)
    path = path.to_s
    begin
      path = File.realpath path
    rescue Errno::ENOENT
      return
    end
    path = rewrite_var_home(path, true)
    @bind_mounts << path
  end

  # meaningless on Linux
  sig { void }
  def allow_write_xcode
  end

  sig { void }
  def initialize
    @bind_mounts = []
    allow_write_path HOMEBREW_REPOSITORY
  end

  sig { params(args: T.any(String, Pathname)).void }
  def run(*args)
    command = %w[
podman
run
--rm
--security-opt=label=disable
--security-opt=no-new-privileges
--userns=keep-id
--env-host
--interactive
--tty
]
    command << "--user=#{Process.uid}:#{Process.gid}"
    command += normalise_paths.map {|path| "--mount=type=bind,source=#{path},destination=#{path}"}
    Dir.mktmpdir("homebrew-sandbox", HOMEBREW_TEMP) do |tmpdir|
      command << "--mount=type=bind,source=#{tmpdir},destination=#{tmpdir}"
      command << "--workdir=#{tmpdir}"
      command += ["ghcr.io/homebrew/ubuntu22.04:latest", "/bin/bash"]
      command += ["-c", args.join(" ")]
      command.map! {|arg| rewrite_var_home(arg, false) }
      begin
        Utils.safe_fork(directory: tmpdir) do |error_pipe|
          if error_pipe
            # Child side
            ENV.update(ENV.to_hash.transform_values {|v| rewrite_var_home(v, true) })
            STDERR.puts command.join("\n")
            exec(*command)
          end
        end
      rescue ChildProcessError => e
        raise ErrorDuringExecution.new(command, status: e.status)
      end
    end
  end

  private

  def normalise_paths
    @bind_mounts.sort.reduce([]) {|reduced, path|
      if reduced.empty? or ! path.start_with? reduced.last
        reduced << path
      end
      reduced
    }
  end

  def rewrite_var_home(path, anchor)
    path.gsub(anchor ? /^\/var\/home\// : /\/var\/home\//, "/home/")
  end
end
