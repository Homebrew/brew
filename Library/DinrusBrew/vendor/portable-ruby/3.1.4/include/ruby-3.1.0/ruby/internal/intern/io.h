#ifndef RBIMPL_INTERN_IO_H                           /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_IO_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed  with   either  `RBIMPL`   or  `rbimpl`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries.  They could be written in C++98.
 * @brief      Public APIs related to ::rb_cIO.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* io.c */

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define rb_defout rb_stdout

/* string.c */ /* ...why? moved in commit de7161526014b781468cea5d84411e23be */

/**
 * The field  separator character for  inputs, or  the `$;`.  This  affects how
 * `String#split` works.   You can set this  via the `-F` command  line option.
 * You can  also assign arbitrary  ruby objects programmatically, but  it makes
 * best sense for you to assign a regular expression here.
 *
 * @internal
 *
 * Tidbit: "fs" comes from AWK's `FS` variable.
 */
RUBY_EXTERN VALUE rb_fs;

/* io.c */ /* ...why? given rb_fs is in string.c? */

/**
 * The field  separator character for outputs,  or the `$,`.  This  affects how
 * `Array#join` works.
 *
 * @deprecated Assigning  anything other than  ::RUBY_Qnil to this  variable is
 *             deprecated.
 */
RUBY_EXTERN VALUE rb_output_fs;

/**
 * The record  separator character for inputs,  or the `$/`.  This  affects how
 * `IO#gets` works.  You can set this via the `-0` command line option.
 *
 * @deprecated Assigning  anything other than  ::RUBY_Qnil to this  variable is
 *             deprecated.
 *
 * @internal
 *
 * Tidbit: "rs" comes from AWK's `RS` variable.
 */
RUBY_EXTERN VALUE rb_rs;

/**
 * This is the default  value of ::rb_rs, i.e. `"\n"`.  It  seems it has always
 * been just a newline string since the beginning.  Not sure why C codes has to
 * use this, given there is no way for ruby programs to interface.
 *
 * Also it has not been deprecated for unknown reasons.
 */
RUBY_EXTERN VALUE rb_default_rs;

/**
 * The record separator  character for outputs, or the `$\`.   This affects how
 * `IO#print` works.
 *
 * @deprecated Assigning  anything other than  ::RUBY_Qnil to this  variable is
 *             deprecated.
 */
RUBY_EXTERN VALUE rb_output_rs;

/**
 * Writes the given string to the given IO.
 *
 * @param[out]  io                   An IO, opened for writing.
 * @param[in]   str                  A String-like object to write to `io`.
 * @exception   rb_eIOError          `io` isn't opened for writing.
 * @exception   rb_eFrozenError      `io` is frozen.
 * @exception   rb_eTypeError        No conversion from `str` to String.
 * @exception   rb_eSystemCallError  `write(2)` failed for some reason.
 * @return      The number of bytes written to the `io`.
 * @post        `str` (up to the length of return value) is written to `io`.
 * @note        This function blocks.
 * @note        Partial write is a thing.  It must be at least questionable not
 *              to check the return value.
 *
 * @internal
 *
 * Above description is  in fact inaccurate.  This function  can take arbitrary
 * objects, and  calls their  `write` method.   What is  written above  in fact
 * describes how `IO#write` works.  You can  pass StringIO etc. here, and would
 * work completely differently.
 */
VALUE rb_io_write(VALUE io, VALUE str);

/**
 * Reads a "line" from  the given IO.  A line here means  a chunk of characters
 * which is terminated by either `"\n"` or an EOF.
 *
 * @param[in,out]  io               An IO, opened for reading.
 * @exception      rb_eIOError      `io` isn't opened for reading.
 * @exception      rb_eFrozenError  `io` is frozen.
 * @retval         RUBY_Qnil        `io` is at EOF.
 * @retval         otherwise        An instance of ::rb_cString.
 * @post           `io` is read.
 * @note           Unlike `IO#gets` it doesn't set `$_`.
 * @note           Unlike `IO#gets` it doesn't consider `$/`.
 */
VALUE rb_io_gets(VALUE io);

/**
 * Reads a byte from the given IO.
 *
 * @note           In Ruby a "byte" always means  an 8 bit integer ranging from
 *                 0 to 255 inclusive.
 * @param[in,out]  io               An IO, opened for reading.
 * @exception      rb_eIOError      `io` is not opened for reading.
 * @exception      rb_eFrozenError  `io` is frozen.
 * @retval         RUBY_Qnil        `io` is at EOF.
 * @retval         otherwise        An instance of ::rb_cInteger.
 * @post           `io` is read.
 *
 * @internal
 *
 * Of course  there was a  function called  `rb_io_getc()`.  It was  removed in
 * commit a25fbe3b3e531bbe479f344af24eaf9d2eeae6ea.
 */
VALUE rb_io_getbyte(VALUE io);

/**
 * "Unget"s a  string.  This function  pushes back  the passed string  onto the
 * passed IO,  such that  a subsequent  buffered read will  return it.   If the
 * passed content  is in  fact an  integer, a single  character string  of that
 * codepoint of the encoding of the IO will be pushed back instead.
 *
 * It  might be  counter-intuitive but  this  function can  push back  multiple
 * characters at  once.  Also this function  can be called multiple  times on a
 * same IO.   Also a  "character" can be  wider than a  byte, depending  on the
 * encoding of the IO.
 *
 * @param[out]  io               An IO, opened for reading.
 * @param[in]   c                Either a String, or an Integer.
 * @exception   rb_eIOError      `io` is not opened for reading.
 * @exception   rb_eFrozenError  `io` is frozen.
 * @exception   rb_eTypeError    No conversion from `c` to ::rb_cString.
 * @return      Always returns ::RUBY_Qnil.
 *
 * @internal
 *
 * Why there is ungetc, given there is no getc?
 */
VALUE rb_io_ungetc(VALUE io, VALUE c);

/**
 * Identical  to rb_io_ungetc(),  except it  doesn't take  the encoding  of the
 * passed IO into account.  When an integer is passed, it just casts that value
 * to C's `unsigned char`, and pushes that back.
 *
 * @param[out]  io               An IO, opened for reading.
 * @param[in]   b                Either a String, or an Integer.
 * @exception   rb_eIOError      `io` is not opened for reading.
 * @exception   rb_eFrozenError  `io` is frozen.
 * @exception   rb_eTypeError    No conversion from `b` to ::rb_cString.
 * @return      Always returns ::RUBY_Qnil.
 */
VALUE rb_io_ungetbyte(VALUE io, VALUE b);

/**
 * Closes the IO.   Any buffered contents are flushed to  the operating system.
 * Any future operations against the IO would raise ::rb_eIOError.  In case the
 * io was created using `IO.popen`, it also sets the `$?`.
 *
 * @param[out]  io  Target IO to close.
 * @return      Always returns ::RUBY_Qnil.
 * @post        `$?` is set in case IO is a pipe.
 * @post        No operations are possible against `io` any further.
 * @note        This can block to flush the contents.
 * @note        This  can  wake other  threads  up,  especially those  who  are
 *              `select()`-ing the passed IO.
 * @note        Multiple invocations  of this function  over the same  IO again
 *              and again is not an error, since Ruby 2.3.
 *
 * @internal
 *
 * You can close a frozen IO... Is this intentional?
 */
VALUE rb_io_close(VALUE io);

/**
 * Flushes any buffered  data within the passed IO to  the underlying operating
 * system.
 *
 * @param[out]  io                   Target IO to flush.
 * @exception   rb_eIOError          `io` is closed.
 * @exception   rb_eFrozenError      `io` is frozen.
 * @exception   rb_eSystemCallError  `write(2)` failed for some reason.
 * @return      The passed `io`.
 * @post        `io`'s buffers are empty.
 * @note        This operation also discards the read buffer.  Should basically
 *              be harmless, but in an esoteric situation like when user pushed
 *              something  different from  what was  read using  `ungetc`, this
 *              operation in fact changes the behaviour of the `io`.
 * @note        Buffering is  difficult.  This operation flushes  the data from
 *              our userspace to  the kernel, but that doesn't  always mean you
 *              can expect them stored persistently onto your hard drive.
 */
VALUE rb_io_flush(VALUE io);

/**
 * Queries if the passed IO is at the end of file.  "The end of file" here mans
 * that there are  no more data to  read.  This function blocks  until the read
 * buffer is filled in, and if that operation reached the end of file, it still
 * returns  ::RUBY_Qfalse (because  there are  data  yet in  that buffer).   It
 * returns ::RUBY_Qtrue once after the buffer is cleared.
 *
 * @param[in,out]  io              Target io to query.
 * @exception      rb_eIOError     `io` is not opened for reading.
 * @exception      rb_eFrozenError  `io` is frozen.
 * @retval         RUBY_Qfalse     There are things yet to be read.
 * @retval         RUBY_Qtrue      "The end of file" situation.
 */
VALUE rb_io_eof(VALUE io);

/**
 * Sets the binmode.  This operation  nullifies the effect of textmode (newline
 * conversion from  `"\r\n"` to `"\n"`  or vice  versa).  Note that  it doesn't
 * stop character encodings conversions.  For instance an IO created using:
 *
 * ```ruby
 * File.open(
 *   "/dev/urandom",
 *   textmode: true,
 *   external_encoding: Encoding::GB18030,
 *   internal_encoding: Encoding::Windows_31J)
 * ```
 *
 * has both  newline and character  conversions.  If you  pass such IO  to this
 * function, only  the `textmode:true` part  is cancelled.  Texts  read through
 * the IO would still  be encoded in Windows-31J; texts written  to the IO will
 * be encoded in GB18030.
 *
 * @param[out]  io               Target IO to modify.
 * @exception   rb_eFrozenError  `io` is frozen.
 * @return      The passed `io`.
 * @post        `io` is in binmode.
 * @note        There is no equivalent operation in Ruby.  You can do this only
 *              in C.
 */
VALUE rb_io_binmode(VALUE io);

/**
 * Forces no conversions be applied  to the passed IO.  Unlike rb_io_binmode(),
 * this cancels any  newline conversions as well as  encoding conversions.  Any
 * texts read/written through the IO will be the verbatim binary contents.
 *
 * @param[out]  io               Target IO to modify.
 * @exception   rb_eFrozenError  `io` is frozen.
 * @return      The passed `io`.
 * @post        `io` is in binmode.  Both external/internal encoding are set to
 *              rb_ascii8bit_encoding().
 * @note        This is the implementation of `IO#binmode`.
 */
VALUE rb_io_ascii8bit_binmode(VALUE io);

/**
 * Identical to rb_io_write(), except it always returns the passed IO.
 *
 * @param[out]  io                   An IO, opened for writing.
 * @param[in]   str                  A String-like object to write to `io`.
 * @exception   rb_eIOError          `io` isn't opened for writing.
 * @exception   rb_eFrozenError      `io` is frozen.
 * @exception   rb_eTypeError        No conversion from `str` to String.
 * @exception   rb_eSystemCallError  `write(2)` failed.
 * @return      The passed `io`.
 * @post        `str` is written to `io`.
 * @note        This function blocks.
 *
 * @internal
 *
 * As rb_io_write(), above description is a fake.
 */
VALUE rb_io_addstr(VALUE io, VALUE str);

/**
 * This is a rb_f_sprintf() + rb_io_write() combo.
 *
 * @param[in]   argc                 Number of objects of `argv`.
 * @param[in]   argv                 A format string followed by its arguments.
 * @param[out]  io                   An IO, opened for writing.
 * @exception   rb_eIOError          `io` isn't opened for writing.
 * @exception   rb_eFrozenError      `io` is frozen.
 * @exception   rb_eTypeError        No conversion from `str` to String.
 * @exception   rb_eSystemCallError  `write(2)` failed.
 * @return      Always returns ::RUBY_Qnil.
 * @post        `argv` is formatted, then written to `io`.
 * @note        This function blocks.
 *
 * @internal
 *
 * As rb_io_write(), above descriptions include fakes.
 */
VALUE rb_io_printf(int argc, const VALUE *argv, VALUE io);

/**
 * Iterates  over the  passed array  to apply  rb_io_write() individually.   If
 * there  is  `$,`,  this  function  inserts  the  string  in  middle  of  each
 * iterations.  If there is `$\`, this  function appends the string at the end.
 * If the array is empty, this function outputs `$_`.
 *
 * @param[in]   argc                 Number of objects of `argv`.
 * @param[in]   argv                 An array of strings to display.
 * @param[out]  io                   An IO, opened for writing.
 * @exception   rb_eIOError          `io` isn't opened for writing.
 * @exception   rb_eFrozenError      `io` is frozen.
 * @exception   rb_eTypeError        No conversion from `str` to String.
 * @exception   rb_eSystemCallError  `write(2)` failed.
 * @return      Always returns ::RUBY_Qnil.
 * @post        `argv` is written to `io`.
 * @note        This function blocks.
 * @note        This function calls rb_io_write() multiple times.  Which means,
 *              it is not  an atomic operation.  Outputs  from multiple threads
 *              can interleave.
 *
 * @internal
 *
 * As rb_io_write(), above descriptions include fakes.
 */
VALUE rb_io_print(int argc, const VALUE *argv, VALUE io);

/**
 * Iterates over the passed array  to apply rb_io_write() individually.  Unlike
 * rb_io_print(), this  function prints  a newline per  each element.   It also
 * flattens   the   passed   array   (OTOH  rb_io_print()   just   resorts   to
 * rb_ary_to_s()).
 *
 * @param[in]   argc                 Number of objects of `argv`.
 * @param[in]   argv                 An array of strings to display.
 * @param[out]  io                   An IO, opened for writing.
 * @exception   rb_eIOError          `io` isn't opened for writing.
 * @exception   rb_eFrozenError      `io` is frozen.
 * @exception   rb_eTypeError        No conversion from `str` to String.
 * @exception   rb_eSystemCallError  `write(2)` failed.
 * @return      Always returns ::RUBY_Qnil.
 * @post        `argv` is written to `io`.
 * @note        This function blocks.
 * @note        This function calls rb_io_write() multiple times.  Which means,
 *              it is not  an atomic operation.  Outputs  from multiple threads
 *              can interleave.
 *
 * @internal
 *
 * As rb_io_write(), above descriptions include fakes.
 */
VALUE rb_io_puts(int argc, const VALUE *argv, VALUE io);

/**
 * Creates  an IO  instance  whose backend  is the  given  file descriptor.   C
 * extension libraries sometimes have file descriptors created elsewhere (maybe
 * deep inside  of another shared  library), which  they want ruby  programs to
 * handle.  This function is handy for such situations.
 *
 * @param[in]  fd     Target file descriptor.
 * @param[in]  flags  Flags, e.g. `O_CREAT|O_EXCL`
 * @param[in]  path   The path of the file that backs `fd`, for diagnostics.
 * @return     An allocated instance of ::rb_cIO.
 * @note       Leave `path` NULL if you don't know.
 */
VALUE rb_io_fdopen(int fd, int flags, const char *path);

RBIMPL_ATTR_NONNULL(())
/**
 * Opens a file located at the given path.
 *
 * `fmode` is a C string that represents the open mode.  It can be one of:
 *
 *   - `r` (means `O_RDONLY`),
 *   - `w` (means `O_WRONLY | O_TRUNC | O_CREAT`),
 *   - `a` (means `O_WRONLY | O_APPEND | O_CREAT`),
 *
 *  Followed by zero or more combinations of:
 *
 *   - `b` (means `_O_BINARY`),
 *   - `t` (means `_O_TEXT`),
 *   - `+` (means `O_RDWR`),
 *   - `x` (means `O_TRUNC`), or
 *   - `:[BOM|]enc[:enc]` (see below).
 *
 * This  last  one   specifies  external  (and  internal   if  any)  encodings,
 * respectively.  If  optional `BOM|` is  specified and the  specified external
 * encoding is capable of expressing  BOMs, opening file's contents' byte order
 * is auto-detected using the mechanism.
 *
 * So for instance, fmode of `"rt|BOM:utf-16le:utf-8"` specifies that...
 *
 *   - the physical representation of the contents of the file is in UTF-16;
 *   - honours its BOM but assumes little endian if absent;
 *   - opens the file for reading;
 *   - what is read is converted into UTF-8;
 *   - with newlines cannibalised to `\n`.
 *
 * @param[in]  fname                Path to open.
 * @param[in]  fmode                Mode specifier much like `fopen(3)`.
 * @exception  rb_eArgError         `fmode` contradicted (e.g. `"bt"`).
 * @exception  rb_eSystemCallError  `open(2)` failed for some reason.
 * @return     An instance of ::rb_cIO.
 */
VALUE rb_file_open(const char *fname, const char *fmode);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_file_open(), except it takes the pathname as a Ruby's string
 * instead of C's.  In case the passed  Ruby object is a non-String it tries to
 * call `#to_path`.
 *
 * @param[in]  fname                Path to open.
 * @param[in]  fmode                Mode specifier much like `fopen(3)`.
 * @exception  rb_eTypeError        `fname` is not a String.
 * @exception  rb_eEncCompatError   `fname` is not ASCII-compatible.
 * @exception  rb_eArgError         `fmode` contradicted (e.g. `"bt"`).
 * @exception  rb_eSystemCallError  `open(2)` failed for some reason.
 * @return     An instance of ::rb_cIO.
 */
VALUE rb_file_open_str(VALUE fname, const char *fmode);

/**
 * Much like rb_io_gets(), but it reads  from the mysterious ARGF object.  ARGF
 * in this context can  be seen as a virtual IO  which concatenates contents of
 * the files passed to the process via the  ARGV, or just STDIN if there are no
 * such files.
 *
 * Unlike rb_io_gets() this function sets `$_`.
 *
 * @exception      rb_eFrozenError  ARGF resorts to STDIN but it is frozen.
 * @retval         RUBY_Qnil        ARGF is at EOF.
 * @retval         otherwise        An instance of ::rb_cString.
 * @post           ARGF is read.
 * @post           `$_` is set.
 *
 * @internal
 *
 * In reality, this function can call `ARGF.gets`.  Its redefinition can affect
 * the behaviour.
 *
 * Also, you can tamper ARGV on-the-fly in middle of ARGF usages:
 *
 * ```
 * gets                        # Reads the first file.
 * ARGV << '/proc/self/limits' # Adds a file.
 * gets                        # Can read from /proc/self/limits.
 * ```
 */
VALUE rb_gets(void);

RBIMPL_ATTR_NONNULL(())
/**
 * Writes the given error message to  somewhere applicable.  On Windows it goes
 * to the console.  On POSIX environments it goes to the standard error.
 *
 * @warning  IT IS  A BAD  IDEA to  use this function  form your  C extensions.
 *           It  is often  annoying when  GUI applications  write to  consoles;
 *           users  don't want  to look  at  there.  Programmers  also want  to
 *           control  the cause  of the  message  itself, like  by rescuing  an
 *           exception.  Just let ruby handle errors.  That must be better than
 *           going your own way.
 *
 * @param[in]  str  Error message to display.
 * @post       `str` is written to somewhere.
 *
 * @internal
 *
 * AFAIK this function  is listed here without marked  deprecated because there
 * are usages of this function in the wild.
 */
void rb_write_error(const char *str);

/**
 * Identical to  rb_write_error(), except  it additionally takes  the message's
 * length.  Necessary when you want to handle wide characters.
 *
 * @param[in]  str  Error message to display.
 * @param[in]  len  Length of `str`, in bytes.
 * @post       `str` is written to somewhere.
 */
void rb_write_error2(const char *str, long len);

/**
 * Closes everything.  In case of  POSIX environments, a child process inherits
 * its parent's opened  file descriptors.  Which is nowadays  considered as one
 * of the UNIX mistakes.  This function closes such inherited file descriptors.
 * When your C  extension needs to have  a child process, don't  forget to call
 * this from your child process right before exec.
 *
 * @param[in]  lowfd        Lower bound of FDs (you want STDIN to remain, no?).
 * @param[in]  maxhint      Hint of max FDs.
 * @param[in]  noclose_fds  A hash, whose keys are an allowlist.
 *
 * @internal
 *
 * As of writing, in  spite of the name, this function  does not actually close
 * anything.  It just  sets `FD_CLOEXEC` for everything and  let `execve(2)` to
 * atomically close them at once.  This is  because as far as we know there are
 * no such platform that has `fork(2)` but lacks `FD_CLOEXEC`.
 *
 * Because this function is expected to run  on a forked process it is entirely
 * async-signal-safe.
 */
void rb_close_before_exec(int lowfd, int maxhint, VALUE noclose_fds);

RBIMPL_ATTR_NONNULL(())
/**
 * This is an rb_cloexec_pipe() + rb_update_max_fd() combo.
 *
 * @param[out]  pipes  Return buffer.  Must at least hold 2 elements.
 * @retval      0      Successful creation of a pipe.
 * @retval      -1     Failure in underlying system call(s).
 * @post        `pipes` is filled with file descriptors.
 * @post        `errno` is set on failure.
 */
int rb_pipe(int *pipes);

/**
 * Queries if the  given FD is reserved or not.   Occasionally Ruby interpreter
 * opens files  for its own  purposes.  Use  this function to  prevent touching
 * such behind-the-scene descriptors.
 *
 * @param[in]  fd  Target file descriptor.
 * @retval     1   `fd` is reserved.
 * @retval     0   Otherwise.
 */
int rb_reserved_fd_p(int fd);

/** @alias{rb_reserved_fd_p} */
#define RB_RESERVED_FD_P(fd) rb_reserved_fd_p(fd)

/**
 * Opens a file  that closes on exec.   In case of POSIX  environments, a child
 * process inherits  its parent's opened  file descriptors.  Which  is nowadays
 * considered  as  one of  the  UNIX  mistakes.   This  function opens  a  file
 * descriptor  as  `open(2)` does,  but  additionally  instructs the  operating
 * system that we don't want it be seen from child processes.
 *
 * @param[in]  pathname   File path to open.
 * @param[in]  flags      Open mode, as in `open(2)`.
 * @param[in]  mode       File mode, in case of `O_CREAT`.
 * @retval     -1         `open(2)` failed for some reason.
 * @retval     otherwise  An allocated new file descriptor.
 * @note       This function does not raise.
 *
 * @internal
 *
 * Whether this function can take NULL or not depends on the underlying open(2)
 * system call implementation but @shyouhei doesn't think it's worth trying.
 */
int rb_cloexec_open(const char *pathname, int flags, mode_t mode);

/**
 * Identical to rb_cloexec_fcntl_dupfd(), except it implies minfd is 3.
 *
 * @param[in]  oldfd     File descriptor to duplicate.
 * @retval     -1        `dup2(2)` failed for some reason.
 * @retval     otherwise  An allocated new file descriptor.
 * @note       This function does not raise.
 */
int rb_cloexec_dup(int oldfd);

/**
 * Identical to rb_cloexec_dup(),  except you can specify  the destination file
 * descriptor.   If  the  destination  is  already  squatted  by  another  file
 * descriptor that gets silently closed without  any warnings.  (This is a spec
 * requested by POSIX.)
 *
 * @param[in]  oldfd  File descriptor to duplicate.
 * @param[in]  newfd  Return value destination.
 * @retval     -1     `dup2(2)` failed for some reason.
 * @retval     newfd  An allocated new file descriptor.
 * @post       Whatever sat at `newfd` gets closed with no notifications.
 * @post       In case return value is -1 `newfd` is untouched.
 * @note       This function does not raise.
 */
int rb_cloexec_dup2(int oldfd, int newfd);

RBIMPL_ATTR_NONNULL(())
/**
 * Opens a pipe with  closing on exec.  In case of  POSIX environments, a child
 * process inherits  its parent's opened  file descriptors.  Which  is nowadays
 * considered  as one  of the  UNIX mistakes.   This function  opens a  pipe as
 * `pipe(2)`  does, but  additionally instructs  the operating  system that  we
 * don't want the duplicated FDs be seen from child processes.
 *
 * @param[out]  fildes  Return buffer.  Must at least hold 2 elements.
 * @retval      0       Successful creation of a pipe.
 * @retval      -1      Failure in underlying system call(s).
 * @post        `pipes` is filled with file descriptors.
 * @post        `errno` is set on failure.
 */
int rb_cloexec_pipe(int fildes[2]);

/**
 * Duplicates  a file  descriptor  with  closing on  exec.   In  case of  POSIX
 * environments, a child process inherits its parent's opened file descriptors.
 * Which is  nowadays considered as  one of  the UNIX mistakes.   This function
 * duplicates a  file descriptor as  `dup(2)` does, but  additionally instructs
 * the operating system that we don't want the duplicated FD be seen from child
 * processes.
 *
 * @param[in]  fd         File descriptor to duplicate.
 * @param[in]  minfd      Minimum allowed FD to return.
 * @retval     -1         `dup(2)` failed for some reason.
 * @retval     otherwise  An allocated new file descriptor.
 * @note       This function does not raise.
 *
 * `minfd` is handy  when for instance STDERR  is closed but you  don't want to
 * use fd 2.
 */
int rb_cloexec_fcntl_dupfd(int fd, int minfd);

/**
 * Informs the interpreter that the passed fd can be the max.  This information
 * is used from rb_close_before_exec().
 *
 * @param[in]  fd  An open FD, which can be large.
 */
void rb_update_max_fd(int fd);

/**
 * Sets or clears  the close-on-exec flag of the passed  file descriptor to the
 * desired state.  STDIN,  STDOUT, STDERR are the  exceptional file descriptors
 * that shall  remain open.  All  others are  to be closed  on exec.  When  a C
 * extension  library  opens  a  file  descriptor  using  anything  other  than
 * rb_cloexec_open() etc., that file descriptor shall experience this function.
 *
 * @param[in]  fd  An open file descriptor.
 */
void rb_fd_fix_cloexec(int fd);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_IO_H */
