# typed: strict
# frozen_string_literal: true

file_descriptor = ARGV.first.to_i
file = File.new(file_descriptor)
file.flock(File::LOCK_EX | File::LOCK_NB) || exit(1)
