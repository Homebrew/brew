# typed: true
# frozen_string_literal: true

class Keg
  sig { params(id: String, file: Pathname).returns(T::Boolean) }
  def change_dylib_id(id, file)
    return false if file.dylib_id == id

    @require_relocation = true
    odebug "Changing dylib ID of #{file}\n  from #{file.dylib_id}\n    to #{id}"
    file.change_dylib_id(id, strict: false)
    true
  rescue MachO::MachOError
    onoe <<~EOS
      Failed changing dylib ID of #{file}
        from #{file.dylib_id}
          to #{id}
    EOS
    raise
  end

  sig { params(old: String, new: String, file: Pathname).returns(T::Boolean) }
  def change_install_name(old, new, file)
    return false if old == new

    @require_relocation = true
    odebug "Changing install name in #{file}\n  from #{old}\n    to #{new}"
    file.change_install_name(old, new, strict: false)
    true
  rescue MachO::MachOError
    onoe <<~EOS
      Failed changing install name in #{file}
        from #{old}
          to #{new}
    EOS
    raise
  end

  def change_rpath(old, new, file)
    return false if old == new

    @require_relocation = true
    odebug "Changing rpath in #{file}\n  from #{old}\n    to #{new}"
    file.change_rpath(old, new, strict: false)
    true
  rescue MachO::MachOError
    onoe <<~EOS
      Failed changing rpath in #{file}
        from #{old}
          to #{new}
    EOS
    raise
  end

  sig { params(rpath: String, file: MachOShim).returns(T::Boolean) }
  def delete_rpath(rpath, file)
    odebug "Deleting rpath #{rpath} in #{file}"
    file.delete_rpath(rpath, strict: false)
    true
  rescue MachO::MachOError
    onoe <<~EOS
      Failed deleting rpath #{rpath} in #{file}
    EOS
    raise
  end
end
