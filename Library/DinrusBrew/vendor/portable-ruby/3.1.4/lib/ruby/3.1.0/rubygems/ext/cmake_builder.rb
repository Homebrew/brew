# frozen_string_literal: true

class Gem::Ext::CmakeBuilder < Gem::Ext::Builder
  def self.build(extension, dest_path, results, args=[], lib_dir=nil, cmake_dir=Dir.pwd)
    unless File.exist?(File.join(cmake_dir, "Makefile"))
      require_relative "../command"
      cmd = ["cmake", ".", "-DCMAKE_INSTALL_PREFIX=#{dest_path}", *Gem::Command.build_args]

      run cmd, results, class_name, cmake_dir
    end

    make dest_path, results, cmake_dir

    results
  end
end
