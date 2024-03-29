# typed: true

# DO NOT EDIT MANUALLY
# This is an autogenerated file for dynamic methods in `Homebrew::DevCmd::PrUpload`.
# Please instead update this file by running `bin/tapioca dsl Homebrew::DevCmd::PrUpload`.

class Homebrew::CLI::Args
  sig { returns(T.nilable(String)) }
  def committer; end

  sig { returns(T::Boolean) }
  def dry_run?; end

  sig { returns(T::Boolean) }
  def keep_old?; end

  sig { returns(T::Boolean) }
  def n?; end

  sig { returns(T::Boolean) }
  def no_commit?; end

  sig { returns(T.nilable(String)) }
  def root_url; end

  sig { returns(T.nilable(String)) }
  def root_url_using; end

  sig { returns(T::Boolean) }
  def upload_only?; end

  sig { returns(T::Boolean) }
  def warn_on_upload_failure?; end
end
