# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

class Gem::Ext::ConfigureBuilder < Gem::Ext::Builder
  def self.build(extension, dest_path, results, args=[], lib_dir=nil, configure_dir=Dir.pwd)
    unless File.exist?(File.join(configure_dir, "Makefile"))
      cmd = ["sh", "./configure", "--prefix=#{dest_path}", *args]

      run cmd, results, class_name, configure_dir
    end

    make dest_path, results, configure_dir

    results
  end
end
