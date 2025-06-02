# frozen_string_literal: true

require "rake/file_list"

# Load the test files from the command line.
argv = ARGV.select do |argument|
  case argument
  when /^-/ then
    argument
  when /\*/ then
    Rake::FileList[argument].to_a.each do |file|
      require File.expand_path file
    end

    false
  else
    path = File.expand_path argument

    abort "\nFile does not exist: #{path}\n\n" unless File.exist?(path)

    require path

    false
  end
end

ARGV.replace argv
