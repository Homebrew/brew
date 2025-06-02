# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

class Gem::Ext::ExtConfBuilder < Gem::Ext::Builder
  def self.build(extension, dest_path, results, args=[], lib_dir=nil, extension_dir=Dir.pwd)
    require "fileutils"
    require "tempfile"

    tmp_dest = Dir.mktmpdir(".gem.", extension_dir)

    # Some versions of `mktmpdir` return absolute paths, which will break make
    # if the paths contain spaces.
    #
    # As such, we convert to a relative path.
    tmp_dest_relative = get_relative_path(tmp_dest.clone, extension_dir)

    destdir = ENV["DESTDIR"]

    begin
      require "shellwords"
      cmd = Gem.ruby.shellsplit << "-I" << File.expand_path("../..", __dir__) << File.basename(extension)
      cmd.push(*args)

      run(cmd, results, class_name, extension_dir) do |s, r|
        mkmf_log = File.join(extension_dir, "mkmf.log")
        if File.exist? mkmf_log
          unless s.success?
            r << "To see why this extension failed to compile, please check" \
              " the mkmf.log which can be found here:\n"
            r << "  " + File.join(dest_path, "mkmf.log") + "\n"
          end
          FileUtils.mv mkmf_log, dest_path
        end
      end

      ENV["DESTDIR"] = nil

      make dest_path, results, extension_dir, tmp_dest_relative

      full_tmp_dest = File.join(extension_dir, tmp_dest_relative)

      # TODO remove in RubyGems 4
      if Gem.install_extension_in_lib && lib_dir
        FileUtils.mkdir_p lib_dir
        entries = Dir.entries(full_tmp_dest) - %w[. ..]
        entries = entries.map {|entry| File.join full_tmp_dest, entry }
        FileUtils.cp_r entries, lib_dir, :remove_destination => true
      end

      FileUtils::Entry_.new(full_tmp_dest).traverse do |ent|
        destent = ent.class.new(dest_path, ent.rel)
        destent.exist? || FileUtils.mv(ent.path, destent.path)
      end
    ensure
      ENV["DESTDIR"] = destdir
    end

    results
  ensure
    FileUtils.rm_rf tmp_dest if tmp_dest
  end

  private

  def self.get_relative_path(path, base)
    path[0..base.length - 1] = "." if path.start_with?(base)
    path
  end
end
