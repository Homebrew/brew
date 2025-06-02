require "bundler/gem_tasks"
require "rake/testtask"

task :default => :test
Rake::TestTask.new(:test) do |t|
  # helper(simplecov) must be required before loading power_assert
  helper_path = File.realpath("test/test_helper.rb")
  t.ruby_opts = ["-w", "-r#{helper_path}"]
  t.test_files = FileList["test/**/*_test.rb"].exclude do |i|
    begin
      next false unless defined?(RubyVM)
      RubyVM::InstructionSequence.compile(File.read(i))
      false
    rescue SyntaxError
      true
    end
  end
end

# ruby/ruby:test/pathname/test_pathname.rb
def has_symlink?
  begin
    File.symlink("", "")
  rescue NotImplementedError, Errno::EACCES
    return false
  rescue Errno::ENOENT
  end
  return true
end

SYMLINK_DIRS = ["lib", "test"]

task :before_script do
  if ENV["TEST_SYMLINK"] == "yes" and has_symlink?
    SYMLINK_DIRS.each do |d|
      File.rename(d, ".#{d}")
      File.symlink(".#{d}", d)
    end
  end
end

task :after_script do
  SYMLINK_DIRS.each do |d|
    if File.symlink?(d) and File.directory?(".#{d}")
      File.unlink(d)
      File.rename(".#{d}", d)
    end
    unless File.directory?(d)
      raise "#{d} should be directory"
    end
  end
end

desc "Run the benchmark suite"
task :benchmark do
  Dir.glob("benchmark/bm_*.rb").each do |f|
    load(f)
  end
end
