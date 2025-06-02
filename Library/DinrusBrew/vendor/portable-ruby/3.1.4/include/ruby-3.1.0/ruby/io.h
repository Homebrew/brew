#ifndef RUBY_IO_H                                    /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_IO_H 1
/**
 * @file
 * @author     $Author$
 * @date       Fri Nov 12 16:47:09 JST 1993
 * @copyright  Copyright (C) 1993-2007 Yukihiro Matsumoto
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/internal/config.h"

#include <stdio.h>
#include "ruby/encoding.h"

#if defined(HAVE_STDIO_EXT_H)
#include <stdio_ext.h>
#endif

#include <errno.h>

/** @cond INTERNAL_MACRO */
#if defined(HAVE_POLL)
#  ifdef _AIX
#    define reqevents events
#    define rtnevents revents
#  endif
#  include <poll.h>
#  ifdef _AIX
#    undef reqevents
#    undef rtnevents
#    undef events
#    undef revents
#  endif
#  define RB_WAITFD_IN  POLLIN
#  define RB_WAITFD_PRI POLLPRI
#  define RB_WAITFD_OUT POLLOUT
#else
#  define RB_WAITFD_IN  0x001
#  define RB_WAITFD_PRI 0x002
#  define RB_WAITFD_OUT 0x004
#endif
/** @endcond */

#include "ruby/internal/attr/const.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/backward/2/attributes.h" /* PACKED_STRUCT_UNALIGNED */

RBIMPL_SYMBOL_EXPORT_BEGIN()

struct stat;
struct timeval;

/**
 * Type of events that an IO can wait.
 *
 * @internal
 *
 * This is visible from extension libraries because `io/wait` wants it.
 */
typedef enum {
    RUBY_IO_READABLE = RB_WAITFD_IN,  /**< `IO::READABLE` */
    RUBY_IO_WRITABLE = RB_WAITFD_OUT, /**< `IO::WRITABLE` */
    RUBY_IO_PRIORITY = RB_WAITFD_PRI, /**< `IO::PRIORITY` */
} rb_io_event_t;

/**
 * IO  buffers.   This  is  an implementation  detail  of  ::rb_io_t::wbuf  and
 * ::rb_io_t::rbuf.  People don't manipulate it directly.
 */
PACKED_STRUCT_UNALIGNED(struct rb_io_buffer_t {

    /** Pointer to the underlying memory region, of at least `capa` bytes. */
    char *ptr;                  /* off + len <= capa */

    /** Offset inside of `ptr`. */
    int off;

    /** Length of the buffer. */
    int len;

    /** Designed capacity of the buffer. */
    int capa;
});

/** @alias{rb_io_buffer_t} */
typedef struct rb_io_buffer_t rb_io_buffer_t;

/** Ruby's IO, metadata and buffers. */
typedef struct rb_io_t {

    /** The IO's Ruby level counterpart. */
    VALUE self;

    /** stdio ptr for read/write, if available. */
    FILE *stdio_file;

    /** file descriptor. */
    int fd;

    /** mode flags: FMODE_XXXs */
    int mode;

    /** child's pid (for pipes) */
    rb_pid_t pid;

    /** number of lines read */
    int lineno;

    /** pathname for file */
    VALUE pathv;

    /** finalize proc */
    void (*finalize)(struct rb_io_t*,int);

    /** Write buffer. */
    rb_io_buffer_t wbuf;

    /**
     * (Byte)  read   buffer.   Note  also   that  there  is  a   field  called
     * ::rb_io_t::cbuf, which also concerns read IO.
     */
    rb_io_buffer_t rbuf;

    /**
     * Duplex IO object, if set.
     *
     * @see rb_io_set_write_io()
     */
    VALUE tied_io_for_writing;

    /** Decomposed encoding flags (e.g. `"enc:enc2""`). */
    /*
     * enc  enc2 read action                      write action
     * NULL NULL force_encoding(default_external) write the byte sequence of str
     * e1   NULL force_encoding(e1)               convert str.encoding to e1
     * e1   e2   convert from e2 to e1            convert str.encoding to e2
     */
    struct rb_io_enc_t {
        /** Internal encoding. */
        rb_encoding *enc;

        /** External encoding. */
        rb_encoding *enc2;

        /**
         * Flags.
         *
         * @see enum ::ruby_econv_flag_type
         */
        int ecflags;

        /**
         * Flags as Ruby hash.
         *
         * @internal
         *
         * This is set.  But used from nowhere maybe?
         */
        VALUE ecopts;
    } encs; /**< Decomposed encoding flags. */

    /** Encoding converter used when reading from this IO. */
    rb_econv_t *readconv;

    /**
     * rb_io_ungetc()  destination.   This  buffer   is  read  before  checking
     * ::rb_io_t::rbuf
     */
    rb_io_buffer_t cbuf;

    /** Encoding converter used when writing to this IO. */
    rb_econv_t *writeconv;

    /**
     * This is, when set, an instance  of ::rb_cString which holds the "common"
     * encoding.   Write  conversion  can  convert strings  twice...   In  case
     * conversion from encoding  X to encoding Y does not  exist, Ruby finds an
     * encoding Z that bridges the two, so that X to Z to Y conversion happens.
     */
    VALUE writeconv_asciicompat;

    /** Whether ::rb_io_t::writeconv is already set up. */
    int writeconv_initialized;

    /**
     * Value   of    ::rb_io_t::rb_io_enc_t::ecflags   stored    right   before
     * initialising ::rb_io_t::writeconv.
     */
    int writeconv_pre_ecflags;

    /**
     * Value of ::rb_io_t::rb_io_enc_t::ecopts stored right before initialising
     * ::rb_io_t::writeconv.
     */
    VALUE writeconv_pre_ecopts;

    /**
     * This is a Ruby  level mutex.  It avoids multiple threads  to write to an
     * IO at  once; helps  for instance rb_io_puts()  to ensure  newlines right
     * next to its arguments.
     *
     * This of course doesn't help inter-process IO interleaves, though.
     */
    VALUE write_lock;
} rb_io_t;

/** @alias{rb_io_enc_t} */
typedef struct rb_io_enc_t rb_io_enc_t;

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define HAVE_RB_IO_T 1

/**
 * @name Possible flags for ::rb_io_t::mode
 *
 * @{
 */

/** The IO is opened for reading. */
#define FMODE_READABLE              0x00000001

/** The IO is opened for writing. */
#define FMODE_WRITABLE              0x00000002

/** The IO is opened for both read/write. */
#define FMODE_READWRITE             (FMODE_READABLE|FMODE_WRITABLE)

/**
 * The IO  is in "binary  mode".  This  is not what  everything rb_io_binmode()
 * concerns.  This low-level flag is to stop CR <-> CRLF conversions that would
 * happen in the underlying operating system.
 *
 * Setting this  one and #FMODE_TEXTMODE at  the same time is  a contradiction.
 * Setting this one and #ECONV_NEWLINE_DECORATOR_MASK  at the same time is also
 * a contradiction.
 */
#define FMODE_BINMODE               0x00000004

/**
 * The  IO  is in  "sync  mode".   All output  is  immediately  flushed to  the
 * underlying operating system then.  Can  be set via rb_io_synchronized(), but
 * there is no way except calling `IO#sync=` to reset.
 */
#define FMODE_SYNC                  0x00000008

/**
 * The IO  is a TTY.  What  is a TTY and  what isn't depends on  the underlying
 * operating system's `isatty(3)` output.  You cannot change this.
 */
#define FMODE_TTY                   0x00000010

/**
 * Ruby eventually  detects that the IO  is bidirectional.  For instance  a TTY
 * has such  property.  There are  several other  things known to  be duplexed.
 * Additionally you  (extension library  authors) can  also implement  your own
 * bidirectional IO subclasses.  One of such example is `Socket`.
 */
#define FMODE_DUPLEX                0x00000020

/**
 * The IO is opened  for appending.  This mode always writes at  the end of the
 * IO.  Ruby manages  this flag for record but basically  the logic behind this
 * mode is at the underlying operating system.  We almost do nothing.
 */
#define FMODE_APPEND                0x00000040

/**
 * The IO is  opened for creating.  This makes sense  only when the destination
 * file does  not exist at  the time  the IO object  was created.  This  is the
 * default mode  for writing,  but you  can pass `"r+"`  to `IO.open`  etc., to
 * reroute this creation.
 */
#define FMODE_CREATE                0x00000080
/* #define FMODE_NOREVLOOKUP        0x00000100 */

/**
 * This flag amends the effect of #FMODE_CREATE,  so that if there already is a
 * file at the given path the operation fails.  Using this you can be sure that
 * the file you get is a fresh new one.
 */
#define FMODE_EXCL                  0x00000400

/**
 * This flag amends the effect of #FMODE_CREATE,  so that if there already is a
 * file at the given path it gets truncated.
 */
#define FMODE_TRUNC                 0x00000800

/**
 * The IO is in "text mode".  On  systems where such mode make sense, this flag
 * changes  the way  the  IO handles  the  contents.  On  POSIX  systems it  is
 * basically  a no-op,  but with  this  flag set  you can  optionally let  Ruby
 * manually convert newlines, unlike when in binary mode:
 *
 * ```ruby
 * IO.open("/p/a/t/h", "wt", crlf_newline: true) # "wb" is NG.
 * ```
 *
 * Setting this one and #FMODE_BINMODE at the same time is a contradiction.
 */
#define FMODE_TEXTMODE              0x00001000
/* #define FMODE_PREP               0x00010000 */
/* #define FMODE_SIGNAL_ON_EPIPE    0x00020000 */

/**
 * This flag amends the  encoding of the IO so that the BOM  of the contents of
 * the IO takes effect.
 */
#define FMODE_SETENC_BY_BOM         0x00100000
/* #define FMODE_UNIX                  0x00200000 */
/* #define FMODE_INET                  0x00400000 */
/* #define FMODE_INET6                 0x00800000 */

/** @} */

/**
 * Queries the underlying IO pointer.
 *
 * @param[in]   obj              An IO object.
 * @param[out]  fp               A variable of type ::rb_io_t.
 * @exception   rb_eFrozenError  `obj` is frozen.
 * @exception   rb_eIOError      `obj` is closed.
 * @post        `fp` holds `obj`'s underlying IO.
 */
#define RB_IO_POINTER(obj,fp) rb_io_check_closed((fp) = RFILE(rb_io_taint_check(obj))->fptr)

/**
 * This is  an old name  of #RB_IO_POINTER.  Not sure  if we want  to deprecate
 * this macro.  There still are tons of usages out there in the wild.
 */
#define GetOpenFile RB_IO_POINTER

/**
 * Fills an IO object.  This makes the best sense when called from inside of an
 * `#initialize`  method  of  a  3rd  party  extension  library  that  inherits
 * ::rb_cIO.
 *
 * If the passed  IO is already opened  for something it first  closes that and
 * opens a new one instead.
 *
 * @param[out]  obj              An IO object to fill in.
 * @param[out]  fp               A variable of type ::rb_io_t.
 * @exception   rb_eTypeError    `obj` is not ::RUBY_T_FILE.
 * @post        `fp` holds `obj`'s underlying IO.
 */
#define RB_IO_OPEN(obj, fp) do {\
    (fp) = rb_io_make_open_file(obj);\
} while (0)

/**
 * This is an old  name of #RB_IO_OPEN.  Not sure if we  want to deprecate this
 * macro.  There still are usages out there in the wild.
 */
#define MakeOpenFile RB_IO_OPEN

/**
 * @private
 *
 * This  is an  implementation  detail  of #RB_IO_OPEN.   People  don't use  it
 * directly.
 *
 * @param[out]  obj              An IO object to fill in.
 * @exception   rb_eTypeError    `obj` is not ::RUBY_T_FILE.
 * @return      `obj`'s backend IO.
 * @post        `obj` is initialised.
 */
rb_io_t *rb_io_make_open_file(VALUE obj);

/**
 * Finds or creates  a stdio's file structure  from a Ruby's one.   This can be
 * handy if you want to call an external API that accepts `FILE *`.
 *
 * @note  Note however, that `FILE`s can  have their own buffer.  Mixing Ruby's
 *        and stdio's file are basically dangerous.  Use with care.
 *
 * @param[in,out]  fptr  Target IO.
 * @return         A stdio's file, created if absent.
 * @post           `fptr` has its corresponding stdio's file.
 *
 * @internal
 *
 * We had rich support  for `FILE` before!  In the days  of 1.8.x ::rb_io_t was
 * like this:
 *
 * ```CXX
 * typedef struct rb_io_t {
 *     FILE *f;                    // stdio ptr for read/write
 *     FILE *f2;                   // additional ptr for rw pipes
 *     int mode;                   // mode flags
 *     int pid;                    // child's pid (for pipes)
 *     int lineno;                 // number of lines read
 *     char *path;                 // pathname for file
 *     void (*finalize) _((struct rb_io_t*,int)); // finalize proc
 * } rb_io_t;
 *```
 *
 * But we  eventually abandoned this layout.   It was too difficult.   We could
 * not have fine-grained control over the `f` field.
 *
 * - `FILE` tends  to be  an opaque  struct.  It does  not interface  well with
 *   `select(2)` etc.   This makes  IO multiplexing  quite hard.   Using stdio,
 *   there is arguably no portable way to know if `fwrite(3)` blocks.
 *
 * - Nonblocking  mode,  which   is  another  core  concept   that  enables  IO
 *   multiplexing, does not interface with stdio routines at all.
 *
 * - Detection of duplexed IO is also hard for the same reason.
 *
 * - `feof(3)` is not portable.
 *   https://mail.python.org/pipermail/python-dev/2001-January/011390.html
 *
 * - Solaris was a thing  back then.  They could not have  more than 256 `FILE`
 *   structures  at  a  time.   Their   file  descriptors  ware  stored  in  an
 *   `unsigned char`.
 *
 * - It is next to impossible to avoid  SEGV, especially when a thread tries to
 *   `ungetc(3)`-ing from a `FILE` which is `fread(3)`-ed by another one.
 *
 * In short, it is a bad idea to let someone else manage IO buffers, especially
 * someone  you cannot  control.   This still  applies  to extension  libraries
 * methinks.  Ruby doesn't prevent you from  shooting yourself in the foot, but
 * consider yourself warned here.
 */
FILE *rb_io_stdio_file(rb_io_t *fptr);

/**
 * Identical to rb_io_stdio_file(), except it takes file descriptors instead of
 * Ruby's  IO.   It  can  also  be  seen  as  a  compatibility  layer  to  wrap
 * `fdopen(3)`.   Nowadays  all  supporting systems,  including  Windows,  have
 * `fdopen`.  Why not use them.
 *
 * @param[in]  fd                   A file descriptor.
 * @param[in]  modestr              C string, something like `"r+"`.
 * @exception  rb_eSystemCallError  `fdopen` failed for some reason.
 * @return     A stdio's file associated with `fd`.
 * @note       Interpretation of `modestr` depends  on the underlying operating
 *             system.  On  glibc you might  be able  to pass e.g.  `"rm"`, but
 *             that's an extension to POSIX.
 */
FILE *rb_fdopen(int fd, const char *modestr);

/**
 * Maps  a file  mode  string (that  rb_file_open() takes)  into  a mixture  of
 * `FMODE_`        flags.         This       for        instance        returns
 * `FMODE_WRITABLE | FMODE_TRUNC | FMODE_CREATE | FMODE_EXCL` for `"wx"`.
 *
 * @note  You cannot pass this return value to OS provided `open(2)` etc.
 *
 * @param[in]  modestr       File mode, in C's string.
 * @exception  rb_eArgError  `modestr` is broken.
 * @return     A set of flags.
 *
 * @internal
 *
 * rb_io_modestr_fmode() is not a pure function because it raises.
 */
int rb_io_modestr_fmode(const char *modestr);

/**
 * Identical  to rb_io_modestr_fmode(),  except it  returns a  mixture of  `O_`
 * flags.  This for instance returns `O_WRONLY | O_TRUNC | O_CREAT | O_EXCL` for
 * `"wx"`.
 *
 * @param[in]  modestr       File mode, in C's string.
 * @exception  rb_eArgError  `modestr` is broken.
 * @return     A set of flags.
 *
 * @internal
 *
 * rb_io_modestr_oflags() is not a pure function because it raises.
 */
int rb_io_modestr_oflags(const char *modestr);

RBIMPL_ATTR_CONST()
/**
 * Converts an  oflags (that rb_io_modestr_oflags()  returns) to a  fmode (that
 * rb_io_mode_flags() returns).  This is a purely functional operation.
 *
 * @param[in]  oflags  A set of `O_` flags.
 * @return     Corresponding set of `FMODE_` flags.
 */
int rb_io_oflags_fmode(int oflags);

/**
 * Asserts that an IO is opened for writing.
 *
 * @param[in]  fptr         An IO you want to write to.
 * @exception  rb_eIOError  `fptr` is not for writing.
 * @post       Upon successful return `fptr` is ready for writing.
 *
 * @internal
 *
 * The parameter must have been `const rb_io_t *`.
 */
void rb_io_check_writable(rb_io_t *fptr);

/** @alias{rb_io_check_byte_readable} */
void rb_io_check_readable(rb_io_t *fptr);

/**
 * Asserts that an  IO is opened for character-based reading.   A character can
 * be  wider than  a  byte.  Because  of  this  we have  to  buffer reads  from
 * descriptors.  This fiction checks if that is possible.
 *
 * @param[in]  fptr         An IO you want to read characters from.
 * @exception  rb_eIOError  `fptr` is not for reading.
 * @post       Upon successful return `fptr` is ready for reading characters.
 *
 * @internal
 *
 * Unlike  rb_io_check_writable() the  parameter cannot  be `const  rb_io_t *`.
 * Behind the scene this operation flushes  its write buffers.  This is because
 * of OpenSSL.  They mandate this way.
 *
 * @see  "Can I use OpenSSL's SSL library with non-blocking I/O?"
 *        https://www.openssl.org/docs/faq.html
 */
void rb_io_check_char_readable(rb_io_t *fptr);

/**
 * Asserts  that  an IO  is  opened  for  byte-based reading.   Byte-based  and
 * character-based reading operations cannot be mixed at a time.
 *
 * @param[in]  fptr         An IO you want to read characters from.
 * @exception  rb_eIOError  `fptr` is not for reading.
 * @post       Upon successful return `fptr` is ready for reading bytes.
 */
void rb_io_check_byte_readable(rb_io_t *fptr);

/**
 * Destroys the given IO.  Any pending operations are flushed.
 *
 * @note  It makes no sense to call this function from anywhere outside of your
 *        class' ::rb_data_type_struct::dfree.
 *
 * @param[out]  fptr  IO to close.
 * @post        `fptr` is no longer a valid pointer.
 */
int rb_io_fptr_finalize(rb_io_t *fptr);

/**
 * Sets #FMODE_SYNC.
 *
 * @note  There is no way for C extensions to undo this operation.
 *
 * @param[out]  fptr         IO to set the flag.
 * @exception   rb_eIOError  `fptr` is not opened.
 * @post        `fptr` is in sync mode.
 */
void rb_io_synchronized(rb_io_t *fptr);

/**
 * Asserts that the passed IO is initialised.
 *
 * @param[in]  fptr         IO that you expect be initialised.
 * @exception  rb_eIOError  `fptr` is not initialised.
 * @post       `fptr` is initialised.
 */
void rb_io_check_initialized(rb_io_t *fptr);

/**
 * This badly named function asserts that the passed IO is _open_.
 *
 * @param[in]  fptr         An IO
 * @exception  rb_eIOError  `fptr` is closed.
 * @post       `fptr` is open.
 */
void rb_io_check_closed(rb_io_t *fptr);

/**
 * Identical  to rb_io_check_io(),  except it  raises exceptions  on conversion
 * failures.
 *
 * @param[in]  io             Target object.
 * @exception  rb_eTypeError  No implicit conversion to IO.
 * @return     Return value of `obj.to_io`.
 * @see        rb_str_to_str
 * @see        rb_ary_to_ary
 */
VALUE rb_io_get_io(VALUE io);

/**
 * Try converting an object to its  IO representation using its `to_io` method,
 * if any.  If there is no such thing, returns ::RUBY_Qnil.
 *
 * @param[in]  io             Arbitrary ruby object to convert.
 * @exception  rb_eTypeError  `obj.to_io` returned something non-IO.
 * @retval     RUBY_Qnil      No conversion from `obj` to IO defined.
 * @retval     otherwise      Converted IO representation of `obj`.
 * @see        rb_check_array_type
 * @see        rb_check_string_type
 * @see        rb_check_hash_type
 */
VALUE rb_io_check_io(VALUE io);

/**
 * Queries the tied IO  for writing.  An IO can be  duplexed.  Fine.  The thing
 * is,  that characteristics  could  sometimes be  achieved  by the  underlying
 * operating  system (for  instance  a  socket's duplexity  is  by nature)  but
 * sometimes  by us.   Notable example  is a  bidirectional pipe.   Suppose you
 * have:
 *
 * ```ruby
 * fp = IO.popen("-", "r+")
 * ```
 *
 * This pipe  is duplexed (the  `"r+"`).  You can  both read from/write  to it.
 * However your operating system may  or may not implement bidirectional pipes.
 * FreeBSD is one  of such operating systems  known to have one;  OTOH Linux is
 * known  to lack  such  things.   So to  achieve  maximum portability,  Ruby's
 * bidirectional pipes are done  purely in user land.  A pipe  in ruby can have
 * multiple file descriptors; one for reading  and the other for writing.  This
 * API  is to  obtain the  IO port  which corresponds  to the  passed one,  for
 * writing.
 *
 * @param[in]  io  An IO.
 * @return     Its tied IO for writing, if any, or `io` itself otherwise.
 */
VALUE rb_io_get_write_io(VALUE io);

/**
 * Assigns the tied IO for writing.   See rb_io_get_write_io() for what a "tied
 * IO for writing" is.
 *
 * @param[out]  io         An IO.
 * @param[in]   w          Another IO.
 * @retval      RUBY_Qnil  There was no tied IO for writing for `io`.
 * @retval      otherwise  The IO formerly tied to `io`.
 * @post        `io` ties `w` for writing.
 *
 * @internal
 *
 * @shyouhei doesn't  think there is any  needs of this function  for 3rd party
 * extension libraries.
 */
VALUE rb_io_set_write_io(VALUE io, VALUE w);

/**
 * Sets an IO to a "nonblock mode".  This amends the way an IO operates so that
 * instead of waiting for rooms for  read/write, it returns errors.  In case of
 * multiplexed IO  situations it can be  vital for IO operations  not to block.
 * This is the key API to achieve that property.
 *
 * @note  Note   however  that   nonblocking-ness  propagates   across  process
 *        boundaries.  You must  really carefully watch your  step when turning
 *        for  instance `stderr`  into nonblock  mode  (it tends  to be  shared
 *        across many  processes).  Also  it is  a complete  disaster to  mix a
 *        nonblocking file and stdio, and `stderr` tends to be under control of
 *        stdio in other processes.
 *
 * @param[out]  fptr  An IO that is to ne nonblocking.
 * @post        Descriptor that `fptr` describes is under nonblocking mode.
 *
 * @internal
 *
 * There  is  `O_NONBLOCK` but  not  `FMODE_NONBLOCK`.   You cannot  atomically
 * create a nonblocking file descriptor using our API.
 */
void rb_io_set_nonblock(rb_io_t *fptr);

/**
 * Returns an integer representing the numeric file descriptor for
 * <em>io</em>.
 *
 * @param[in]   io         An IO.
 * @retval      int        A file descriptor.
 */
int rb_io_descriptor(VALUE io);

/**
 * This function  breaks down the  option hash that `IO#initialize`  takes into
 * components.   This is  an implementation  detail of  rb_io_extract_modeenc()
 * today.  People prefer that API instead.
 *
 * @param[in]   opt            The hash to decompose.
 * @param[out]  enc_p          Return value buffer.
 * @param[out]  enc2_p         Return value buffer.
 * @param[out]  fmode_p        Return value buffer.
 * @exception   rb_eTypeError  `opt` is broken.
 * @exception   rb_eArgError   Specified encoding does not exist.
 * @retval      1              Components got extracted.
 * @retval      0              Otherwise.
 * @post        `enc_p` is the specified internal encoding.
 * @post        `enc2_p` is the specified external encoding.
 * @post        `fmode_p` is the specified set of `FMODE_` modes.
 */
int rb_io_extract_encoding_option(VALUE opt, rb_encoding **enc_p, rb_encoding **enc2_p, int *fmode_p);

/**
 * This    function    can   be    seen    as    an   extended    version    of
 * rb_io_extract_encoding_option() that  not only concerns the  option hash but
 * also mode string and so on.  This should be mixed with rb_scan_args() like:
 *
 * ```CXX
 * // This method mimics File.new
 * static VALUE
 * your_method(int argc, const VALUE *argv, VALUE self)
 * {
 *     VALUE       f; // file name
 *     VALUE       m; // open mode
 *     VALUE       p; // permission (O_CREAT)
 *     VALUE       k; // keywords
 *     rb_io_enc_t c; // converter
 *     int         oflags;
 *     int         fmode;
 *
 *     int n = rb_scan_args(argc, argv, "12:", &f, &m, &p, &k);
 *     rb_io_extract_modeenc(&m, &p, k, &oflags, &fmode, &c);
 *
 *     // Every local variables declared so far has been properly filled here.
 *    ...
 * }
 * ```
 *
 * @param[in,out]  vmode_p        Pointer to a mode object.
 * @param[in,out]  vperm_p        Pointer to a permission object.
 * @param[in]      opthash        Keyword arguments
 * @param[out]     oflags_p       `O_` flags return buffer.
 * @param[out]     fmode_p        `FMODE_` flags return buffer.
 * @param[out]     convconfig_p   Encoding config return buffer.
 * @exception      rb_eTypeError  Unexpected object (e.g. Time) passed.
 * @exception      rb_eArgError   Contradiction inside of params.
 * @post           `*vmode_p` is a mode object (filled if any).
 * @post           `*vperm_p` is a permission object (filled if any).
 * @post           `*oflags_p` is filled with `O_` flags.
 * @post           `*fmode_p` is filled with `FMODE_` flags.
 * @post           `*convconfig_p` is filled with conversion instructions.
 *
 * @internal
 *
 * ```rbs
 * class File
 *   def initialize: (
 *     (String | int)      path,
 *     ?(String | int)      fmode,
 *     ?(String | int)      perm,
 *     ?mode:              (String | int),
 *     ?flags:             int,
 *     ?external_encoding: (Encoding | String),
 *     ?internal_encoding: (Encoding | String),
 *     ?encoding:          String,
 *     ?textmode:          bool,
 *     ?binmode:           bool,
 *     ?autoclose:         bool,
 *     ?invalid:           :replace,
 *     ?undef:             :replace,
 *     ?replace:           String,
 *     ?fallback:          (Hash | Proc | Method),
 *     ?xml:               (:text | :attr),
 *     ?crlf_newline:      bool,
 *     ?cr_newline:        bool,
 *     ?universal_newline: bool
 *   ) -> void
 * ```
 */
void rb_io_extract_modeenc(VALUE *vmode_p, VALUE *vperm_p, VALUE opthash, int *oflags_p, int *fmode_p, rb_io_enc_t *convconfig_p);

/* :TODO: can this function be __attribute__((warn_unused_result)) or not? */
/**
 * Buffered write to the passed IO.
 *
 * @param[out]  io                   Destination IO.
 * @param[in]   buf                  Contents to go to `io`.
 * @param[in]   size                 Number of bytes of `buf`.
 * @exception   rb_eFrozenError      `io` is frozen.
 * @exception   rb_eIOError          `io` is not open for writing.
 * @exception   rb_eSystemCallError  `writev(2)` failed for some reason.
 * @retval      -1                   Write failed.
 * @retval      otherwise            Number of bytes actually written.
 * @post        `buf` is written to `io`.
 * @note        Partial write  is a thing.   It is a  failure not to  check the
 *              return value.
 */
ssize_t rb_io_bufwrite(VALUE io, const void *buf, size_t size);

//RBIMPL_ATTR_DEPRECATED(("use rb_io_maybe_wait_readable"))
/**
 * Blocks until the passed file descriptor gets readable.
 *
 * @deprecated  We now prefer rb_io_maybe_wait_readable() over this one.
 * @param[in]   fd           The file descriptor to wait.
 * @exception   rb_eIOError  Bad file descriptor.
 * @return      0 or 1 (meaning unclear).
 * @post        `fd` is ready for reading.
 */
int rb_io_wait_readable(int fd);

//RBIMPL_ATTR_DEPRECATED(("use rb_io_maybe_wait_writable"))
/**
 * Blocks until the passed file descriptor gets writable.
 *
 * @deprecated  We now prefer rb_io_maybe_wait_writable() over this one.
 * @param[in]   fd           The file descriptor to wait.
 * @exception   rb_eIOError  Bad file descriptor.
 * @return      0 or 1 (meaning unclear).
 */
int rb_io_wait_writable(int fd);

//RBIMPL_ATTR_DEPRECATED(("use rb_io_wait"))
/**
 * Blocks until the passed file descriptor is ready for the passed events.
 *
 * @deprecated     We now prefer rb_io_maybe_wait() over this one.
 * @param[in]      fd           The file descriptor to wait.
 * @param[in]      events       A set of enum ::rb_io_event_t.
 * @param[in,out]  tv           Timeout.
 * @retval         0            Operation timed out.
 * @retval         -1           `select(2)` failed for some reason.
 * @retval         otherwise    A set of enum ::rb_io_event_t.
 * @note           Depending on your  operating system `tv` might  or might not
 *                 be  updated (POSIX  permits both).   Portable programs  must
 *                 have no assumptions.
 */
int rb_wait_for_single_fd(int fd, int events, struct timeval *tv);

/**
 * Blocks until  the passed IO  is ready for  the passed events.   The "events"
 * here is  a Ruby level  integer, which is  an OR-ed value  of `IO::READABLE`,
 * `IO::WRITable`, and `IO::PRIORITY`.
 *
 * @param[in]  io                   An IO object to wait.
 * @param[in]  events               See above.
 * @param[in]  timeout              Time, or numeric seconds since UNIX epoch.
 * @exception  rb_eIOError          `io` is not open.
 * @exception  rb_eRangeError       `timeout` is out of range.
 * @exception  rb_eSystemCallError  `select(2)` failed for some reason.
 * @retval     RUBY_Qfalse          Operation timed out.
 * @retval     Otherwise            Actual events reached.
 */
VALUE rb_io_wait(VALUE io, VALUE events, VALUE timeout);

/**
 * Identical to rb_io_wait()  except it additionally takes  previous errno.  If
 * the  passed errno  indicates  for instance  `EINTR`,  this function  returns
 * immediately.  This is expected to be called in a loop.
 *
 * ```CXX
 * while (true) {
 *
 *     ... // Your interesting operation here
 *         // `errno` could be updated
 *
 *     rb_io_maybe_wait(errno, io, ev, Qnil);
 * }
 * ```
 *
 * @param[in]  error                System errno.
 * @param[in]  io                   An IO object to wait.
 * @param[in]  events               An integer set of interests.
 * @param[in]  timeout              Time, or numeric seconds since UNIX epoch.
 * @exception  rb_eIOError          `io` is not open.
 * @exception  rb_eRangeError       `timeout` is out of range.
 * @exception  rb_eSystemCallError  `select(2)` failed for some reason.
 * @retval     RUBY_Qfalse          Operation timed out.
 * @retval     Otherwise            Actual events reached.
 *
 * @internal
 *
 * This function  to return ::RUBY_Qfalse  on timeout could be  unintended.  It
 * seems timeout feature has some rough edge.
 */
VALUE rb_io_maybe_wait(int error, VALUE io, VALUE events, VALUE timeout);

/**
 * Blocks until the passed IO is ready for reading, if that makes sense for the
 * passed  errno.  This  is  a  special case  of  rb_io_maybe_wait() that  only
 * concerns for reading.
 *
 * @param[in]  error                System errno.
 * @param[in]  io                   An IO object to wait.
 * @param[in]  timeout              Time, or numeric seconds since UNIX epoch.
 * @exception  rb_eIOError          `io` is not open.
 * @exception  rb_eRangeError       `timeout` is out of range.
 * @exception  rb_eSystemCallError  `select(2)` failed for some reason.
 * @exception  rb_eTypeError        Operation timed out.
 * @return     Always returns ::RUBY_IO_READABLE.
 *
 * @internal
 *
 * Because rb_io_maybe_wait()  returns ::RUBY_Qfalse on timeout,  this function
 * fails to convert that value to `int`, and raises ::rb_eTypeError.
 */
int rb_io_maybe_wait_readable(int error, VALUE io, VALUE timeout);

/**
 * Blocks until the passed IO is ready for writing, if that makes sense for the
 * passed  errno.  This  is  a  special case  of  rb_io_maybe_wait() that  only
 * concernsfor writing.
 *
 * @param[in]  error                System errno.
 * @param[in]  io                   An IO object to wait.
 * @param[in]  timeout              Time, or numeric seconds since UNIX epoch.
 * @exception  rb_eIOError          `io` is not open.
 * @exception  rb_eRangeError       `timeout` is out of range.
 * @exception  rb_eSystemCallError  `select(2)` failed for some reason.
 * @exception  rb_eTypeError        Operation timed out.
 * @return     Always returns ::RUBY_IO_WRITABLE.
 *
 * @internal
 *
 * Because rb_io_maybe_wait()  returns ::RUBY_Qfalse on timeout,  this function
 * fails to convert that value to `int`, and raises ::rb_eTypeError.
 */
int rb_io_maybe_wait_writable(int error, VALUE io, VALUE timeout);

/** @cond INTERNAL_MACRO */
/* compatibility for ruby 1.8 and older */
#define rb_io_mode_flags(modestr) [<"rb_io_mode_flags() is obsolete; use rb_io_modestr_fmode()">]
#define rb_io_modenum_flags(oflags) [<"rb_io_modenum_flags() is obsolete; use rb_io_oflags_fmode()">]
/** @endcond */

/**
 * @deprecated  This function  once was a thing  in the old days,  but makes no
 *              sense   any   longer   today.   Exists   here   for   backwards
 *              compatibility only.  You can safely forget about it.
 *
 * @param[in]   obj              Object in question.
 * @exception   rb_eFrozenError  obj is frozen.
 * @return      The passed `obj`
 */
VALUE rb_io_taint_check(VALUE obj);

RBIMPL_ATTR_NORETURN()
/**
 * Utility function to raise ::rb_eEOFError.
 *
 * @exception  rb_eEOFError  End of file situation.
 * @note       It never returns.
 */
void rb_eof_error(void);

/**
 * Blocks until there is a pending read  in the passed IO.  If there already is
 * it just returns.
 *
 * @param[out]  fptr  An IO to wait for reading.
 * @post        The are bytes to be read.
 */
void rb_io_read_check(rb_io_t *fptr);

RBIMPL_ATTR_PURE()
/**
 * Queries if the  passed IO has any pending  reads.  Unlike rb_io_read_check()
 * this doesn't block; has no side effects.
 *
 * @param[in]  fptr  An IO which can have pending reads.
 * @retval     0     The IO is empty.
 * @retval     1     There is something buffered.
 */
int rb_io_read_pending(rb_io_t *fptr);

/**
 * Constructs an instance of ::rb_cStat from the passed information.
 *
 * @param[in]  st  A stat.
 * @return     Allocated new instance of ::rb_cStat.
 */
VALUE rb_stat_new(const struct stat *st);

/* gc.c */

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_IO_H */
