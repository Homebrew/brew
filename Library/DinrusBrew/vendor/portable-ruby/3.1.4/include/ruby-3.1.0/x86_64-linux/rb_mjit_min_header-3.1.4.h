#ifdef __GNUC__
# pragma GCC system_header
#endif
#define ALWAYS_INLINE(x) __attribute__ ((__always_inline__)) x
typedef __builtin_va_list __gnuc_va_list;
typedef __gnuc_va_list va_list;

typedef long unsigned int size_t;
typedef unsigned char __u_char;
typedef unsigned short int __u_short;
typedef unsigned int __u_int;
typedef unsigned long int __u_long;
typedef signed char __int8_t;
typedef unsigned char __uint8_t;
typedef signed short int __int16_t;
typedef unsigned short int __uint16_t;
typedef signed int __int32_t;
typedef unsigned int __uint32_t;
typedef signed long int __int64_t;
typedef unsigned long int __uint64_t;
typedef long int __quad_t;
typedef unsigned long int __u_quad_t;
typedef unsigned long int __dev_t;
typedef unsigned int __uid_t;
typedef unsigned int __gid_t;
typedef unsigned long int __ino_t;
typedef unsigned long int __ino64_t;
typedef unsigned int __mode_t;
typedef unsigned long int __nlink_t;
typedef long int __off_t;
typedef long int __off64_t;
typedef int __pid_t;
typedef struct { int __val[2]; } __fsid_t;
typedef long int __clock_t;
typedef unsigned long int __rlim_t;
typedef unsigned long int __rlim64_t;
typedef unsigned int __id_t;
typedef long int __time_t;
typedef unsigned int __useconds_t;
typedef long int __suseconds_t;
typedef int __daddr_t;
typedef long int __swblk_t;
typedef int __key_t;
typedef int __clockid_t;
typedef void * __timer_t;
typedef long int __blksize_t;
typedef long int __blkcnt_t;
typedef long int __blkcnt64_t;
typedef unsigned long int __fsblkcnt_t;
typedef unsigned long int __fsblkcnt64_t;
typedef unsigned long int __fsfilcnt_t;
typedef unsigned long int __fsfilcnt64_t;
typedef long int __ssize_t;
typedef __off64_t __loff_t;
typedef __quad_t *__qaddr_t;
typedef char *__caddr_t;
typedef long int __intptr_t;
typedef unsigned int __socklen_t;
struct _IO_FILE;

typedef struct _IO_FILE FILE;


typedef struct _IO_FILE __FILE;
typedef struct
{
  int __count;
  union
  {
    unsigned int __wch;
    char __wchb[4];
  } __value;
} __mbstate_t;
typedef struct
{
  __off_t __pos;
  __mbstate_t __state;
} _G_fpos_t;
typedef struct
{
  __off64_t __pos;
  __mbstate_t __state;
} _G_fpos64_t;
typedef int _G_int16_t __attribute__ ((__mode__ (__HI__)));
typedef int _G_int32_t __attribute__ ((__mode__ (__SI__)));
typedef unsigned int _G_uint16_t __attribute__ ((__mode__ (__HI__)));
typedef unsigned int _G_uint32_t __attribute__ ((__mode__ (__SI__)));
struct _IO_jump_t; struct _IO_FILE;
typedef void _IO_lock_t;
struct _IO_marker {
  struct _IO_marker *_next;
  struct _IO_FILE *_sbuf;
  int _pos;
};
enum __codecvt_result
{
  __codecvt_ok,
  __codecvt_partial,
  __codecvt_error,
  __codecvt_noconv
};
struct _IO_FILE {
  int _flags;
  char* _IO_read_ptr;
  char* _IO_read_end;
  char* _IO_read_base;
  char* _IO_write_base;
  char* _IO_write_ptr;
  char* _IO_write_end;
  char* _IO_buf_base;
  char* _IO_buf_end;
  char *_IO_save_base;
  char *_IO_backup_base;
  char *_IO_save_end;
  struct _IO_marker *_markers;
  struct _IO_FILE *_chain;
  int _fileno;
  int _flags2;
  __off_t _old_offset;
  unsigned short _cur_column;
  signed char _vtable_offset;
  char _shortbuf[1];
  _IO_lock_t *_lock;
  __off64_t _offset;
  void *__pad1;
  void *__pad2;
  void *__pad3;
  void *__pad4;
  size_t __pad5;
  int _mode;
  char _unused2[15 * sizeof (int) - 4 * sizeof (void *) - sizeof (size_t)];
};
typedef struct _IO_FILE _IO_FILE;
struct _IO_FILE_plus;
extern struct _IO_FILE_plus _IO_2_1_stdin_;
extern struct _IO_FILE_plus _IO_2_1_stdout_;
extern struct _IO_FILE_plus _IO_2_1_stderr_;
typedef __ssize_t __io_read_fn (void *__cookie, char *__buf, size_t __nbytes);
typedef __ssize_t __io_write_fn (void *__cookie, __const char *__buf,
     size_t __n);
typedef int __io_seek_fn (void *__cookie, __off64_t *__pos, int __w);
typedef int __io_close_fn (void *__cookie);
typedef __io_read_fn cookie_read_function_t;
typedef __io_write_fn cookie_write_function_t;
typedef __io_seek_fn cookie_seek_function_t;
typedef __io_close_fn cookie_close_function_t;
typedef struct
{
  __io_read_fn *read;
  __io_write_fn *write;
  __io_seek_fn *seek;
  __io_close_fn *close;
} _IO_cookie_io_functions_t;
typedef _IO_cookie_io_functions_t cookie_io_functions_t;
struct _IO_cookie_file;
extern void _IO_cookie_init (struct _IO_cookie_file *__cfile, int __read_write,
        void *__cookie, _IO_cookie_io_functions_t __fns);
extern int __underflow (_IO_FILE *);
extern int __uflow (_IO_FILE *);
extern int __overflow (_IO_FILE *, int);
extern int _IO_getc (_IO_FILE *__fp);
extern int _IO_putc (int __c, _IO_FILE *__fp);
extern int _IO_feof (_IO_FILE *__fp) __attribute__ ((__nothrow__));
extern int _IO_ferror (_IO_FILE *__fp) __attribute__ ((__nothrow__));
extern int _IO_peekc_locked (_IO_FILE *__fp);
extern void _IO_flockfile (_IO_FILE *) __attribute__ ((__nothrow__));
extern void _IO_funlockfile (_IO_FILE *) __attribute__ ((__nothrow__));
extern int _IO_ftrylockfile (_IO_FILE *) __attribute__ ((__nothrow__));
extern int _IO_vfscanf (_IO_FILE * __restrict, const char * __restrict,
   __gnuc_va_list, int *__restrict);
extern int _IO_vfprintf (_IO_FILE *__restrict, const char *__restrict,
    __gnuc_va_list);
extern __ssize_t _IO_padn (_IO_FILE *, int, __ssize_t);
extern size_t _IO_sgetn (_IO_FILE *, void *, size_t);
extern __off64_t _IO_seekoff (_IO_FILE *, __off64_t, int, int);
extern __off64_t _IO_seekpos (_IO_FILE *, __off64_t, int);
extern void _IO_free_backup_area (_IO_FILE *) __attribute__ ((__nothrow__));
typedef __off_t off_t;
typedef __off64_t off64_t;
typedef __ssize_t ssize_t;

typedef _G_fpos_t fpos_t;

typedef _G_fpos64_t fpos64_t;
extern struct _IO_FILE *stdin;
extern struct _IO_FILE *stdout;
extern struct _IO_FILE *stderr;

extern int remove (__const char *__filename) __attribute__ ((__nothrow__));
extern int rename (__const char *__old, __const char *__new) __attribute__ ((__nothrow__));

extern int renameat (int __oldfd, __const char *__old, int __newfd,
       __const char *__new) __attribute__ ((__nothrow__));

extern FILE *tmpfile (void) ;
extern FILE *tmpfile64 (void) ;
extern char *tmpnam (char *__s) __attribute__ ((__nothrow__)) ;

extern char *tmpnam_r (char *__s) __attribute__ ((__nothrow__)) ;
extern char *tempnam (__const char *__dir, __const char *__pfx)
     __attribute__ ((__nothrow__)) __attribute__ ((__malloc__)) ;

extern int fclose (FILE *__stream);
extern int fflush (FILE *__stream);

extern int fflush_unlocked (FILE *__stream);
extern int fcloseall (void);

extern FILE *fopen (__const char *__restrict __filename,
      __const char *__restrict __modes) ;
extern FILE *freopen (__const char *__restrict __filename,
        __const char *__restrict __modes,
        FILE *__restrict __stream) ;

extern FILE *fopen64 (__const char *__restrict __filename,
        __const char *__restrict __modes) ;
extern FILE *freopen64 (__const char *__restrict __filename,
   __const char *__restrict __modes,
   FILE *__restrict __stream) ;
extern FILE *fdopen (int __fd, __const char *__modes) __attribute__ ((__nothrow__)) ;
extern FILE *fopencookie (void *__restrict __magic_cookie,
     __const char *__restrict __modes,
     _IO_cookie_io_functions_t __io_funcs) __attribute__ ((__nothrow__)) ;
extern FILE *fmemopen (void *__s, size_t __len, __const char *__modes)
  __attribute__ ((__nothrow__)) ;
extern FILE *open_memstream (char **__bufloc, size_t *__sizeloc) __attribute__ ((__nothrow__)) ;

extern void setbuf (FILE *__restrict __stream, char *__restrict __buf) __attribute__ ((__nothrow__));
extern int setvbuf (FILE *__restrict __stream, char *__restrict __buf,
      int __modes, size_t __n) __attribute__ ((__nothrow__));

extern void setbuffer (FILE *__restrict __stream, char *__restrict __buf,
         size_t __size) __attribute__ ((__nothrow__));
extern void setlinebuf (FILE *__stream) __attribute__ ((__nothrow__));

extern int fprintf (FILE *__restrict __stream,
      __const char *__restrict __format, ...);
extern int printf (__const char *__restrict __format, ...);
extern int sprintf (char *__restrict __s,
      __const char *__restrict __format, ...) __attribute__ ((__nothrow__));
extern int vfprintf (FILE *__restrict __s, __const char *__restrict __format,
       __gnuc_va_list __arg);
extern int vprintf (__const char *__restrict __format, __gnuc_va_list __arg);
extern int vsprintf (char *__restrict __s, __const char *__restrict __format,
       __gnuc_va_list __arg) __attribute__ ((__nothrow__));


extern int snprintf (char *__restrict __s, size_t __maxlen,
       __const char *__restrict __format, ...)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 3, 4)));
extern int vsnprintf (char *__restrict __s, size_t __maxlen,
        __const char *__restrict __format, __gnuc_va_list __arg)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 3, 0)));

extern int vasprintf (char **__restrict __ptr, __const char *__restrict __f,
        __gnuc_va_list __arg)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 2, 0))) ;
extern int __asprintf (char **__restrict __ptr,
         __const char *__restrict __fmt, ...)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 2, 3))) ;
extern int asprintf (char **__restrict __ptr,
       __const char *__restrict __fmt, ...)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 2, 3))) ;
extern int vdprintf (int __fd, __const char *__restrict __fmt,
       __gnuc_va_list __arg)
     __attribute__ ((__format__ (__printf__, 2, 0)));
extern int dprintf (int __fd, __const char *__restrict __fmt, ...)
     __attribute__ ((__format__ (__printf__, 2, 3)));

extern int fscanf (FILE *__restrict __stream,
     __const char *__restrict __format, ...) ;
extern int scanf (__const char *__restrict __format, ...) ;
extern int sscanf (__const char *__restrict __s,
     __const char *__restrict __format, ...) __attribute__ ((__nothrow__));


extern int vfscanf (FILE *__restrict __s, __const char *__restrict __format,
      __gnuc_va_list __arg)
     __attribute__ ((__format__ (__scanf__, 2, 0))) ;
extern int vscanf (__const char *__restrict __format, __gnuc_va_list __arg)
     __attribute__ ((__format__ (__scanf__, 1, 0))) ;
extern int vsscanf (__const char *__restrict __s,
      __const char *__restrict __format, __gnuc_va_list __arg)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__scanf__, 2, 0)));


extern int fgetc (FILE *__stream);
extern int getc (FILE *__stream);
extern int getchar (void);

extern int getc_unlocked (FILE *__stream);
extern int getchar_unlocked (void);
extern int fgetc_unlocked (FILE *__stream);

extern int fputc (int __c, FILE *__stream);
extern int putc (int __c, FILE *__stream);
extern int putchar (int __c);

extern int fputc_unlocked (int __c, FILE *__stream);
extern int putc_unlocked (int __c, FILE *__stream);
extern int putchar_unlocked (int __c);
extern int getw (FILE *__stream);
extern int putw (int __w, FILE *__stream);

extern char *fgets (char *__restrict __s, int __n, FILE *__restrict __stream)
     ;
extern char *gets (char *__s) ;

extern char *fgets_unlocked (char *__restrict __s, int __n,
        FILE *__restrict __stream) ;
extern __ssize_t __getdelim (char **__restrict __lineptr,
          size_t *__restrict __n, int __delimiter,
          FILE *__restrict __stream) ;
extern __ssize_t getdelim (char **__restrict __lineptr,
        size_t *__restrict __n, int __delimiter,
        FILE *__restrict __stream) ;
extern __ssize_t getline (char **__restrict __lineptr,
       size_t *__restrict __n,
       FILE *__restrict __stream) ;

extern int fputs (__const char *__restrict __s, FILE *__restrict __stream);
extern int puts (__const char *__s);
extern int ungetc (int __c, FILE *__stream);
extern size_t fread (void *__restrict __ptr, size_t __size,
       size_t __n, FILE *__restrict __stream) ;
extern size_t fwrite (__const void *__restrict __ptr, size_t __size,
        size_t __n, FILE *__restrict __s) ;

extern int fputs_unlocked (__const char *__restrict __s,
      FILE *__restrict __stream);
extern size_t fread_unlocked (void *__restrict __ptr, size_t __size,
         size_t __n, FILE *__restrict __stream) ;
extern size_t fwrite_unlocked (__const void *__restrict __ptr, size_t __size,
          size_t __n, FILE *__restrict __stream) ;

extern int fseek (FILE *__stream, long int __off, int __whence);
extern long int ftell (FILE *__stream) ;
extern void rewind (FILE *__stream);

extern int fseeko (FILE *__stream, __off_t __off, int __whence);
extern __off_t ftello (FILE *__stream) ;

extern int fgetpos (FILE *__restrict __stream, fpos_t *__restrict __pos);
extern int fsetpos (FILE *__stream, __const fpos_t *__pos);

extern int fseeko64 (FILE *__stream, __off64_t __off, int __whence);
extern __off64_t ftello64 (FILE *__stream) ;
extern int fgetpos64 (FILE *__restrict __stream, fpos64_t *__restrict __pos);
extern int fsetpos64 (FILE *__stream, __const fpos64_t *__pos);

extern void clearerr (FILE *__stream) __attribute__ ((__nothrow__));
extern int feof (FILE *__stream) __attribute__ ((__nothrow__)) ;
extern int ferror (FILE *__stream) __attribute__ ((__nothrow__)) ;

extern void clearerr_unlocked (FILE *__stream) __attribute__ ((__nothrow__));
extern int feof_unlocked (FILE *__stream) __attribute__ ((__nothrow__)) ;
extern int ferror_unlocked (FILE *__stream) __attribute__ ((__nothrow__)) ;

extern void perror (__const char *__s);

extern int sys_nerr;
extern __const char *__const sys_errlist[];
extern int _sys_nerr;
extern __const char *__const _sys_errlist[];
extern int fileno (FILE *__stream) __attribute__ ((__nothrow__)) ;
extern int fileno_unlocked (FILE *__stream) __attribute__ ((__nothrow__)) ;
extern FILE *popen (__const char *__command, __const char *__modes) ;
extern int pclose (FILE *__stream);
extern char *ctermid (char *__s) __attribute__ ((__nothrow__));
extern char *cuserid (char *__s);
struct obstack;
extern int obstack_printf (struct obstack *__restrict __obstack,
      __const char *__restrict __format, ...)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 2, 3)));
extern int obstack_vprintf (struct obstack *__restrict __obstack,
       __const char *__restrict __format,
       __gnuc_va_list __args)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 2, 0)));
extern void flockfile (FILE *__stream) __attribute__ ((__nothrow__));
extern int ftrylockfile (FILE *__stream) __attribute__ ((__nothrow__)) ;
extern void funlockfile (FILE *__stream) __attribute__ ((__nothrow__));


typedef __u_char u_char;
typedef __u_short u_short;
typedef __u_int u_int;
typedef __u_long u_long;
typedef __quad_t quad_t;
typedef __u_quad_t u_quad_t;
typedef __fsid_t fsid_t;
typedef __loff_t loff_t;
typedef __ino_t ino_t;
typedef __ino64_t ino64_t;
typedef __dev_t dev_t;
typedef __gid_t gid_t;
typedef __mode_t mode_t;
typedef __nlink_t nlink_t;
typedef __uid_t uid_t;
typedef __pid_t pid_t;
typedef __id_t id_t;
typedef __daddr_t daddr_t;
typedef __caddr_t caddr_t;
typedef __key_t key_t;

typedef __clock_t clock_t;



typedef __time_t time_t;


typedef __clockid_t clockid_t;
typedef __timer_t timer_t;
typedef __useconds_t useconds_t;
typedef __suseconds_t suseconds_t;
typedef unsigned long int ulong;
typedef unsigned short int ushort;
typedef unsigned int uint;
typedef int int8_t __attribute__ ((__mode__ (__QI__)));
typedef int int16_t __attribute__ ((__mode__ (__HI__)));
typedef int int32_t __attribute__ ((__mode__ (__SI__)));
typedef int int64_t __attribute__ ((__mode__ (__DI__)));
typedef unsigned int u_int8_t __attribute__ ((__mode__ (__QI__)));
typedef unsigned int u_int16_t __attribute__ ((__mode__ (__HI__)));
typedef unsigned int u_int32_t __attribute__ ((__mode__ (__SI__)));
typedef unsigned int u_int64_t __attribute__ ((__mode__ (__DI__)));
typedef int register_t __attribute__ ((__mode__ (__word__)));
typedef int __sig_atomic_t;
typedef struct
  {
    unsigned long int __val[(1024 / (8 * sizeof (unsigned long int)))];
  } __sigset_t;
typedef __sigset_t sigset_t;
struct timespec
  {
    __time_t tv_sec;
    long int tv_nsec;
  };
struct timeval
  {
    __time_t tv_sec;
    __suseconds_t tv_usec;
  };
typedef long int __fd_mask;
typedef struct
  {
    __fd_mask fds_bits[1024 / (8 * (int) sizeof (__fd_mask))];
  } fd_set;
typedef __fd_mask fd_mask;

extern int select (int __nfds, fd_set *__restrict __readfds,
     fd_set *__restrict __writefds,
     fd_set *__restrict __exceptfds,
     struct timeval *__restrict __timeout);
extern int pselect (int __nfds, fd_set *__restrict __readfds,
      fd_set *__restrict __writefds,
      fd_set *__restrict __exceptfds,
      const struct timespec *__restrict __timeout,
      const __sigset_t *__restrict __sigmask);

__extension__
extern unsigned int gnu_dev_major (unsigned long long int __dev)
     __attribute__ ((__nothrow__));
__extension__
extern unsigned int gnu_dev_minor (unsigned long long int __dev)
     __attribute__ ((__nothrow__));
__extension__
extern unsigned long long int gnu_dev_makedev (unsigned int __major,
            unsigned int __minor)
     __attribute__ ((__nothrow__));
typedef __blksize_t blksize_t;
typedef __blkcnt_t blkcnt_t;
typedef __fsblkcnt_t fsblkcnt_t;
typedef __fsfilcnt_t fsfilcnt_t;
typedef __blkcnt64_t blkcnt64_t;
typedef __fsblkcnt64_t fsblkcnt64_t;
typedef __fsfilcnt64_t fsfilcnt64_t;
typedef unsigned long int pthread_t;
typedef union
{
  char __size[56];
  long int __align;
} pthread_attr_t;
typedef struct __pthread_internal_list
{
  struct __pthread_internal_list *__prev;
  struct __pthread_internal_list *__next;
} __pthread_list_t;
typedef union
{
  struct __pthread_mutex_s
  {
    int __lock;
    unsigned int __count;
    int __owner;
    unsigned int __nusers;
    int __kind;
    int __spins;
    __pthread_list_t __list;
  } __data;
  char __size[40];
  long int __align;
} pthread_mutex_t;
typedef union
{
  char __size[4];
  int __align;
} pthread_mutexattr_t;
typedef union
{
  struct
  {
    int __lock;
    unsigned int __futex;
    __extension__ unsigned long long int __total_seq;
    __extension__ unsigned long long int __wakeup_seq;
    __extension__ unsigned long long int __woken_seq;
    void *__mutex;
    unsigned int __nwaiters;
    unsigned int __broadcast_seq;
  } __data;
  char __size[48];
  __extension__ long long int __align;
} pthread_cond_t;
typedef union
{
  char __size[4];
  int __align;
} pthread_condattr_t;
typedef unsigned int pthread_key_t;
typedef int pthread_once_t;
typedef union
{
  struct
  {
    int __lock;
    unsigned int __nr_readers;
    unsigned int __readers_wakeup;
    unsigned int __writer_wakeup;
    unsigned int __nr_readers_queued;
    unsigned int __nr_writers_queued;
    int __writer;
    int __shared;
    unsigned long int __pad1;
    unsigned long int __pad2;
    unsigned int __flags;
  } __data;
  char __size[56];
  long int __align;
} pthread_rwlock_t;
typedef union
{
  char __size[8];
  long int __align;
} pthread_rwlockattr_t;
typedef volatile int pthread_spinlock_t;
typedef union
{
  char __size[32];
  long int __align;
} pthread_barrier_t;
typedef union
{
  char __size[4];
  int __align;
} pthread_barrierattr_t;


struct stat
  {
    __dev_t st_dev;
    __ino_t st_ino;
    __nlink_t st_nlink;
    __mode_t st_mode;
    __uid_t st_uid;
    __gid_t st_gid;
    int __pad0;
    __dev_t st_rdev;
    __off_t st_size;
    __blksize_t st_blksize;
    __blkcnt_t st_blocks;
    struct timespec st_atim;
    struct timespec st_mtim;
    struct timespec st_ctim;
    long int __unused[3];
  };
struct stat64
  {
    __dev_t st_dev;
    __ino64_t st_ino;
    __nlink_t st_nlink;
    __mode_t st_mode;
    __uid_t st_uid;
    __gid_t st_gid;
    int __pad0;
    __dev_t st_rdev;
    __off_t st_size;
    __blksize_t st_blksize;
    __blkcnt64_t st_blocks;
    struct timespec st_atim;
    struct timespec st_mtim;
    struct timespec st_ctim;
    long int __unused[3];
  };
extern int stat (__const char *__restrict __file,
   struct stat *__restrict __buf) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int fstat (int __fd, struct stat *__buf) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern int stat64 (__const char *__restrict __file,
     struct stat64 *__restrict __buf) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int fstat64 (int __fd, struct stat64 *__buf) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern int fstatat (int __fd, __const char *__restrict __file,
      struct stat *__restrict __buf, int __flag)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 3)));
extern int fstatat64 (int __fd, __const char *__restrict __file,
        struct stat64 *__restrict __buf, int __flag)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 3)));
extern int lstat (__const char *__restrict __file,
    struct stat *__restrict __buf) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int lstat64 (__const char *__restrict __file,
      struct stat64 *__restrict __buf)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int chmod (__const char *__file, __mode_t __mode)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int lchmod (__const char *__file, __mode_t __mode)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int fchmod (int __fd, __mode_t __mode) __attribute__ ((__nothrow__));
extern int fchmodat (int __fd, __const char *__file, __mode_t __mode,
       int __flag)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2))) ;
extern __mode_t umask (__mode_t __mask) __attribute__ ((__nothrow__));
extern __mode_t getumask (void) __attribute__ ((__nothrow__));
extern int mkdir (__const char *__path, __mode_t __mode)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int mkdirat (int __fd, __const char *__path, __mode_t __mode)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern int mknod (__const char *__path, __mode_t __mode, __dev_t __dev)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int mknodat (int __fd, __const char *__path, __mode_t __mode,
      __dev_t __dev) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern int mkfifo (__const char *__path, __mode_t __mode)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int mkfifoat (int __fd, __const char *__path, __mode_t __mode)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern int utimensat (int __fd, __const char *__path,
        __const struct timespec __times[2],
        int __flags)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern int futimens (int __fd, __const struct timespec __times[2]) __attribute__ ((__nothrow__));
extern int __fxstat (int __ver, int __fildes, struct stat *__stat_buf)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3)));
extern int __xstat (int __ver, __const char *__filename,
      struct stat *__stat_buf) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 3)));
extern int __lxstat (int __ver, __const char *__filename,
       struct stat *__stat_buf) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 3)));
extern int __fxstatat (int __ver, int __fildes, __const char *__filename,
         struct stat *__stat_buf, int __flag)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4)));
extern int __fxstat64 (int __ver, int __fildes, struct stat64 *__stat_buf)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3)));
extern int __xstat64 (int __ver, __const char *__filename,
        struct stat64 *__stat_buf) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 3)));
extern int __lxstat64 (int __ver, __const char *__filename,
         struct stat64 *__stat_buf) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 3)));
extern int __fxstatat64 (int __ver, int __fildes, __const char *__filename,
    struct stat64 *__stat_buf, int __flag)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4)));
extern int __xmknod (int __ver, __const char *__path, __mode_t __mode,
       __dev_t *__dev) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 4)));
extern int __xmknodat (int __ver, int __fd, __const char *__path,
         __mode_t __mode, __dev_t *__dev)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 5)));

typedef int wchar_t;

union wait
  {
    int w_status;
    struct
      {
 unsigned int __w_termsig:7;
 unsigned int __w_coredump:1;
 unsigned int __w_retcode:8;
 unsigned int:16;
      } __wait_terminated;
    struct
      {
 unsigned int __w_stopval:8;
 unsigned int __w_stopsig:8;
 unsigned int:16;
      } __wait_stopped;
  };
typedef union
  {
    union wait *__uptr;
    int *__iptr;
  } __WAIT_STATUS __attribute__ ((__transparent_union__));

typedef struct
  {
    int quot;
    int rem;
  } div_t;
typedef struct
  {
    long int quot;
    long int rem;
  } ldiv_t;


__extension__ typedef struct
  {
    long long int quot;
    long long int rem;
  } lldiv_t;

extern size_t __ctype_get_mb_cur_max (void) __attribute__ ((__nothrow__)) ;

extern double atof (__const char *__nptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1))) ;
extern int atoi (__const char *__nptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1))) ;
extern long int atol (__const char *__nptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1))) ;


__extension__ extern long long int atoll (__const char *__nptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1))) ;


extern double strtod (__const char *__restrict __nptr,
        char **__restrict __endptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;


extern float strtof (__const char *__restrict __nptr,
       char **__restrict __endptr) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern long double strtold (__const char *__restrict __nptr,
       char **__restrict __endptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;


extern long int strtol (__const char *__restrict __nptr,
   char **__restrict __endptr, int __base)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern unsigned long int strtoul (__const char *__restrict __nptr,
      char **__restrict __endptr, int __base)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;

__extension__
extern long long int strtoq (__const char *__restrict __nptr,
        char **__restrict __endptr, int __base)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
__extension__
extern unsigned long long int strtouq (__const char *__restrict __nptr,
           char **__restrict __endptr, int __base)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;

__extension__
extern long long int strtoll (__const char *__restrict __nptr,
         char **__restrict __endptr, int __base)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
__extension__
extern unsigned long long int strtoull (__const char *__restrict __nptr,
     char **__restrict __endptr, int __base)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;

typedef struct __locale_struct
{
  struct __locale_data *__locales[13];
  const unsigned short int *__ctype_b;
  const int *__ctype_tolower;
  const int *__ctype_toupper;
  const char *__names[13];
} *__locale_t;
typedef __locale_t locale_t;
extern long int strtol_l (__const char *__restrict __nptr,
     char **__restrict __endptr, int __base,
     __locale_t __loc) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 4))) ;
extern unsigned long int strtoul_l (__const char *__restrict __nptr,
        char **__restrict __endptr,
        int __base, __locale_t __loc)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 4))) ;
__extension__
extern long long int strtoll_l (__const char *__restrict __nptr,
    char **__restrict __endptr, int __base,
    __locale_t __loc)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 4))) ;
__extension__
extern unsigned long long int strtoull_l (__const char *__restrict __nptr,
       char **__restrict __endptr,
       int __base, __locale_t __loc)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 4))) ;
extern double strtod_l (__const char *__restrict __nptr,
   char **__restrict __endptr, __locale_t __loc)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 3))) ;
extern float strtof_l (__const char *__restrict __nptr,
         char **__restrict __endptr, __locale_t __loc)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 3))) ;
extern long double strtold_l (__const char *__restrict __nptr,
         char **__restrict __endptr,
         __locale_t __loc)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 3))) ;
extern char *l64a (long int __n) __attribute__ ((__nothrow__)) ;
extern long int a64l (__const char *__s)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1))) ;
extern long int random (void) __attribute__ ((__nothrow__));
extern void srandom (unsigned int __seed) __attribute__ ((__nothrow__));
extern char *initstate (unsigned int __seed, char *__statebuf,
   size_t __statelen) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern char *setstate (char *__statebuf) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
struct random_data
  {
    int32_t *fptr;
    int32_t *rptr;
    int32_t *state;
    int rand_type;
    int rand_deg;
    int rand_sep;
    int32_t *end_ptr;
  };
extern int random_r (struct random_data *__restrict __buf,
       int32_t *__restrict __result) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int srandom_r (unsigned int __seed, struct random_data *__buf)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern int initstate_r (unsigned int __seed, char *__restrict __statebuf,
   size_t __statelen,
   struct random_data *__restrict __buf)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 4)));
extern int setstate_r (char *__restrict __statebuf,
         struct random_data *__restrict __buf)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));

extern int rand (void) __attribute__ ((__nothrow__));
extern void srand (unsigned int __seed) __attribute__ ((__nothrow__));

extern int rand_r (unsigned int *__seed) __attribute__ ((__nothrow__));
extern double drand48 (void) __attribute__ ((__nothrow__));
extern double erand48 (unsigned short int __xsubi[3]) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern long int lrand48 (void) __attribute__ ((__nothrow__));
extern long int nrand48 (unsigned short int __xsubi[3])
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern long int mrand48 (void) __attribute__ ((__nothrow__));
extern long int jrand48 (unsigned short int __xsubi[3])
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern void srand48 (long int __seedval) __attribute__ ((__nothrow__));
extern unsigned short int *seed48 (unsigned short int __seed16v[3])
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern void lcong48 (unsigned short int __param[7]) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
struct drand48_data
  {
    unsigned short int __x[3];
    unsigned short int __old_x[3];
    unsigned short int __c;
    unsigned short int __init;
    unsigned long long int __a;
  };
extern int drand48_r (struct drand48_data *__restrict __buffer,
        double *__restrict __result) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int erand48_r (unsigned short int __xsubi[3],
        struct drand48_data *__restrict __buffer,
        double *__restrict __result) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int lrand48_r (struct drand48_data *__restrict __buffer,
        long int *__restrict __result)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int nrand48_r (unsigned short int __xsubi[3],
        struct drand48_data *__restrict __buffer,
        long int *__restrict __result)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int mrand48_r (struct drand48_data *__restrict __buffer,
        long int *__restrict __result)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int jrand48_r (unsigned short int __xsubi[3],
        struct drand48_data *__restrict __buffer,
        long int *__restrict __result)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int srand48_r (long int __seedval, struct drand48_data *__buffer)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern int seed48_r (unsigned short int __seed16v[3],
       struct drand48_data *__buffer) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int lcong48_r (unsigned short int __param[7],
        struct drand48_data *__buffer)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));

extern void *malloc (size_t __size) __attribute__ ((__nothrow__)) __attribute__ ((__malloc__)) ;
extern void *calloc (size_t __nmemb, size_t __size)
     __attribute__ ((__nothrow__)) __attribute__ ((__malloc__)) ;


extern void *realloc (void *__ptr, size_t __size)
     __attribute__ ((__nothrow__)) __attribute__ ((__warn_unused_result__));
extern void free (void *__ptr) __attribute__ ((__nothrow__));

extern void cfree (void *__ptr) __attribute__ ((__nothrow__));

extern void *alloca (size_t __size) __attribute__ ((__nothrow__));

extern void *valloc (size_t __size) __attribute__ ((__nothrow__)) __attribute__ ((__malloc__)) ;
extern int posix_memalign (void **__memptr, size_t __alignment, size_t __size)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;

extern void abort (void) __attribute__ ((__nothrow__)) __attribute__ ((__noreturn__));
extern int atexit (void (*__func) (void)) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int at_quick_exit (void (*__func) (void)) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

extern int on_exit (void (*__func) (int __status, void *__arg), void *__arg)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

extern void exit (int __status) __attribute__ ((__nothrow__)) __attribute__ ((__noreturn__));
extern void quick_exit (int __status) __attribute__ ((__nothrow__)) __attribute__ ((__noreturn__));


extern void _Exit (int __status) __attribute__ ((__nothrow__)) __attribute__ ((__noreturn__));


extern char *getenv (__const char *__name) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;

extern char *__secure_getenv (__const char *__name)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern int putenv (char *__string) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int setenv (__const char *__name, __const char *__value, int __replace)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern int unsetenv (__const char *__name) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int clearenv (void) __attribute__ ((__nothrow__));
extern char *mktemp (char *__template) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern int mkstemp (char *__template) __attribute__ ((__nonnull__ (1))) ;
extern int mkstemp64 (char *__template) __attribute__ ((__nonnull__ (1))) ;
extern int mkstemps (char *__template, int __suffixlen) __attribute__ ((__nonnull__ (1))) ;
extern int mkstemps64 (char *__template, int __suffixlen)
     __attribute__ ((__nonnull__ (1))) ;
extern char *mkdtemp (char *__template) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern int mkostemp (char *__template, int __flags) __attribute__ ((__nonnull__ (1))) ;
extern int mkostemp64 (char *__template, int __flags) __attribute__ ((__nonnull__ (1))) ;
extern int mkostemps (char *__template, int __suffixlen, int __flags)
     __attribute__ ((__nonnull__ (1))) ;
extern int mkostemps64 (char *__template, int __suffixlen, int __flags)
     __attribute__ ((__nonnull__ (1))) ;

extern int system (__const char *__command) ;

extern char *canonicalize_file_name (__const char *__name)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern char *realpath (__const char *__restrict __name,
         char *__restrict __resolved) __attribute__ ((__nothrow__)) ;
typedef int (*__compar_fn_t) (__const void *, __const void *);
typedef __compar_fn_t comparison_fn_t;
typedef int (*__compar_d_fn_t) (__const void *, __const void *, void *);

extern void *bsearch (__const void *__key, __const void *__base,
        size_t __nmemb, size_t __size, __compar_fn_t __compar)
     __attribute__ ((__nonnull__ (1, 2, 5))) ;
extern void qsort (void *__base, size_t __nmemb, size_t __size,
     __compar_fn_t __compar) __attribute__ ((__nonnull__ (1, 4)));
extern void qsort_r (void *__base, size_t __nmemb, size_t __size,
       __compar_d_fn_t __compar, void *__arg)
  __attribute__ ((__nonnull__ (1, 4)));
extern int abs (int __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)) ;
extern long int labs (long int __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)) ;

__extension__ extern long long int llabs (long long int __x)
     __attribute__ ((__nothrow__)) __attribute__ ((__const__)) ;

extern div_t div (int __numer, int __denom)
     __attribute__ ((__nothrow__)) __attribute__ ((__const__)) ;
extern ldiv_t ldiv (long int __numer, long int __denom)
     __attribute__ ((__nothrow__)) __attribute__ ((__const__)) ;


__extension__ extern lldiv_t lldiv (long long int __numer,
        long long int __denom)
     __attribute__ ((__nothrow__)) __attribute__ ((__const__)) ;

extern char *ecvt (double __value, int __ndigit, int *__restrict __decpt,
     int *__restrict __sign) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4))) ;
extern char *fcvt (double __value, int __ndigit, int *__restrict __decpt,
     int *__restrict __sign) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4))) ;
extern char *gcvt (double __value, int __ndigit, char *__buf)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3))) ;
extern char *qecvt (long double __value, int __ndigit,
      int *__restrict __decpt, int *__restrict __sign)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4))) ;
extern char *qfcvt (long double __value, int __ndigit,
      int *__restrict __decpt, int *__restrict __sign)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4))) ;
extern char *qgcvt (long double __value, int __ndigit, char *__buf)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3))) ;
extern int ecvt_r (double __value, int __ndigit, int *__restrict __decpt,
     int *__restrict __sign, char *__restrict __buf,
     size_t __len) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4, 5)));
extern int fcvt_r (double __value, int __ndigit, int *__restrict __decpt,
     int *__restrict __sign, char *__restrict __buf,
     size_t __len) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4, 5)));
extern int qecvt_r (long double __value, int __ndigit,
      int *__restrict __decpt, int *__restrict __sign,
      char *__restrict __buf, size_t __len)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4, 5)));
extern int qfcvt_r (long double __value, int __ndigit,
      int *__restrict __decpt, int *__restrict __sign,
      char *__restrict __buf, size_t __len)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4, 5)));

extern int mblen (__const char *__s, size_t __n) __attribute__ ((__nothrow__)) ;
extern int mbtowc (wchar_t *__restrict __pwc,
     __const char *__restrict __s, size_t __n) __attribute__ ((__nothrow__)) ;
extern int wctomb (char *__s, wchar_t __wchar) __attribute__ ((__nothrow__)) ;
extern size_t mbstowcs (wchar_t *__restrict __pwcs,
   __const char *__restrict __s, size_t __n) __attribute__ ((__nothrow__));
extern size_t wcstombs (char *__restrict __s,
   __const wchar_t *__restrict __pwcs, size_t __n)
     __attribute__ ((__nothrow__));

extern int rpmatch (__const char *__response) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern int getsubopt (char **__restrict __optionp,
        char *__const *__restrict __tokens,
        char **__restrict __valuep)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2, 3))) ;
extern void setkey (__const char *__key) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int posix_openpt (int __oflag) ;
extern int grantpt (int __fd) __attribute__ ((__nothrow__));
extern int unlockpt (int __fd) __attribute__ ((__nothrow__));
extern char *ptsname (int __fd) __attribute__ ((__nothrow__)) ;
extern int ptsname_r (int __fd, char *__buf, size_t __buflen)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern int getpt (void);
extern int getloadavg (double __loadavg[], int __nelem)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

typedef long int ptrdiff_t;


extern void *memcpy (void *__restrict __dest,
       __const void *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern void *memmove (void *__dest, __const void *__src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));

extern void *memccpy (void *__restrict __dest, __const void *__restrict __src,
        int __c, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));

extern void *memset (void *__s, int __c, size_t __n) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int memcmp (__const void *__s1, __const void *__s2, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
extern void *memchr (__const void *__s, int __c, size_t __n)
      __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));

extern void *rawmemchr (__const void *__s, int __c)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));
extern void *memrchr (__const void *__s, int __c, size_t __n)
      __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));

extern char *strcpy (char *__restrict __dest, __const char *__restrict __src)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *strncpy (char *__restrict __dest,
        __const char *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *strcat (char *__restrict __dest, __const char *__restrict __src)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *strncat (char *__restrict __dest, __const char *__restrict __src,
        size_t __n) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int strcmp (__const char *__s1, __const char *__s2)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
extern int strncmp (__const char *__s1, __const char *__s2, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
extern int strcoll (__const char *__s1, __const char *__s2)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
extern size_t strxfrm (char *__restrict __dest,
         __const char *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));

extern int strcoll_l (__const char *__s1, __const char *__s2, __locale_t __l)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2, 3)));
extern size_t strxfrm_l (char *__dest, __const char *__src, size_t __n,
    __locale_t __l) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 4)));
extern char *strdup (__const char *__s)
     __attribute__ ((__nothrow__)) __attribute__ ((__malloc__)) __attribute__ ((__nonnull__ (1)));
extern char *strndup (__const char *__string, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__malloc__)) __attribute__ ((__nonnull__ (1)));

extern char *strchr (__const char *__s, int __c)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));
extern char *strrchr (__const char *__s, int __c)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));

extern char *strchrnul (__const char *__s, int __c)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));

extern size_t strcspn (__const char *__s, __const char *__reject)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
extern size_t strspn (__const char *__s, __const char *__accept)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *strpbrk (__const char *__s, __const char *__accept)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *strstr (__const char *__haystack, __const char *__needle)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *strtok (char *__restrict __s, __const char *__restrict __delim)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));

extern char *__strtok_r (char *__restrict __s,
    __const char *__restrict __delim,
    char **__restrict __save_ptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 3)));
extern char *strtok_r (char *__restrict __s, __const char *__restrict __delim,
         char **__restrict __save_ptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 3)));
extern char *strcasestr (__const char *__haystack, __const char *__needle)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
extern void *memmem (__const void *__haystack, size_t __haystacklen,
       __const void *__needle, size_t __needlelen)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 3)));
extern void *__mempcpy (void *__restrict __dest,
   __const void *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern void *mempcpy (void *__restrict __dest,
        __const void *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));

extern size_t strlen (__const char *__s)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));

extern size_t strnlen (__const char *__string, size_t __maxlen)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));

extern char *strerror (int __errnum) __attribute__ ((__nothrow__));

extern char *strerror_r (int __errnum, char *__buf, size_t __buflen)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern char *strerror_l (int __errnum, __locale_t __l) __attribute__ ((__nothrow__));
extern void __bzero (void *__s, size_t __n) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern void bcopy (__const void *__src, void *__dest, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern void bzero (void *__s, size_t __n) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int bcmp (__const void *__s1, __const void *__s2, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *index (__const char *__s, int __c)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));
extern char *rindex (__const char *__s, int __c)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));
extern int ffs (int __i) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern int ffsl (long int __l) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
__extension__ extern int ffsll (long long int __ll)
     __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern int strcasecmp (__const char *__s1, __const char *__s2)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
extern int strncasecmp (__const char *__s1, __const char *__s2, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
extern int strcasecmp_l (__const char *__s1, __const char *__s2,
    __locale_t __loc)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2, 3)));
extern int strncasecmp_l (__const char *__s1, __const char *__s2,
     size_t __n, __locale_t __loc)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2, 4)));
extern char *strsep (char **__restrict __stringp,
       __const char *__restrict __delim)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *strsignal (int __sig) __attribute__ ((__nothrow__));
extern char *__stpcpy (char *__restrict __dest, __const char *__restrict __src)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *stpcpy (char *__restrict __dest, __const char *__restrict __src)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *__stpncpy (char *__restrict __dest,
   __const char *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *stpncpy (char *__restrict __dest,
        __const char *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int strverscmp (__const char *__s1, __const char *__s2)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *strfry (char *__string) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern void *memfrob (void *__s, size_t __n) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern char *basename (__const char *__filename) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));

typedef unsigned char uint8_t;
typedef unsigned short int uint16_t;
typedef unsigned int uint32_t;
typedef unsigned long int uint64_t;
typedef signed char int_least8_t;
typedef short int int_least16_t;
typedef int int_least32_t;
typedef long int int_least64_t;
typedef unsigned char uint_least8_t;
typedef unsigned short int uint_least16_t;
typedef unsigned int uint_least32_t;
typedef unsigned long int uint_least64_t;
typedef signed char int_fast8_t;
typedef long int int_fast16_t;
typedef long int int_fast32_t;
typedef long int int_fast64_t;
typedef unsigned char uint_fast8_t;
typedef unsigned long int uint_fast16_t;
typedef unsigned long int uint_fast32_t;
typedef unsigned long int uint_fast64_t;
typedef long int intptr_t;
typedef unsigned long int uintptr_t;
typedef long int intmax_t;
typedef unsigned long int uintmax_t;
typedef int __gwchar_t;

typedef struct
  {
    long int quot;
    long int rem;
  } imaxdiv_t;
extern intmax_t imaxabs (intmax_t __n) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern imaxdiv_t imaxdiv (intmax_t __numer, intmax_t __denom)
      __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern intmax_t strtoimax (__const char *__restrict __nptr,
      char **__restrict __endptr, int __base) __attribute__ ((__nothrow__));
extern uintmax_t strtoumax (__const char *__restrict __nptr,
       char ** __restrict __endptr, int __base) __attribute__ ((__nothrow__));
extern intmax_t wcstoimax (__const __gwchar_t *__restrict __nptr,
      __gwchar_t **__restrict __endptr, int __base)
     __attribute__ ((__nothrow__));
extern uintmax_t wcstoumax (__const __gwchar_t *__restrict __nptr,
       __gwchar_t ** __restrict __endptr, int __base)
     __attribute__ ((__nothrow__));


typedef __socklen_t socklen_t;
extern int access (__const char *__name, int __type) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int euidaccess (__const char *__name, int __type)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int eaccess (__const char *__name, int __type)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int faccessat (int __fd, __const char *__file, int __type, int __flag)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2))) ;
extern __off_t lseek (int __fd, __off_t __offset, int __whence) __attribute__ ((__nothrow__));
extern __off64_t lseek64 (int __fd, __off64_t __offset, int __whence)
     __attribute__ ((__nothrow__));
extern int close (int __fd);
extern ssize_t read (int __fd, void *__buf, size_t __nbytes) ;
extern ssize_t write (int __fd, __const void *__buf, size_t __n) ;
extern ssize_t pread (int __fd, void *__buf, size_t __nbytes,
        __off_t __offset) ;
extern ssize_t pwrite (int __fd, __const void *__buf, size_t __n,
         __off_t __offset) ;
extern ssize_t pread64 (int __fd, void *__buf, size_t __nbytes,
   __off64_t __offset) ;
extern ssize_t pwrite64 (int __fd, __const void *__buf, size_t __n,
    __off64_t __offset) ;
extern int pipe (int __pipedes[2]) __attribute__ ((__nothrow__)) ;
extern int pipe2 (int __pipedes[2], int __flags) __attribute__ ((__nothrow__)) ;
extern unsigned int alarm (unsigned int __seconds) __attribute__ ((__nothrow__));
extern unsigned int sleep (unsigned int __seconds);
extern __useconds_t ualarm (__useconds_t __value, __useconds_t __interval)
     __attribute__ ((__nothrow__));
extern int usleep (__useconds_t __useconds);
extern int pause (void);
extern int chown (__const char *__file, __uid_t __owner, __gid_t __group)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern int fchown (int __fd, __uid_t __owner, __gid_t __group) __attribute__ ((__nothrow__)) ;
extern int lchown (__const char *__file, __uid_t __owner, __gid_t __group)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern int fchownat (int __fd, __const char *__file, __uid_t __owner,
       __gid_t __group, int __flag)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2))) ;
extern int chdir (__const char *__path) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern int fchdir (int __fd) __attribute__ ((__nothrow__)) ;
extern char *getcwd (char *__buf, size_t __size) __attribute__ ((__nothrow__)) ;
extern char *get_current_dir_name (void) __attribute__ ((__nothrow__));
extern char *getwd (char *__buf)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) __attribute__ ((__deprecated__)) ;
extern int dup (int __fd) __attribute__ ((__nothrow__)) ;
extern int dup2 (int __fd, int __fd2) __attribute__ ((__nothrow__));
extern int dup3 (int __fd, int __fd2, int __flags) __attribute__ ((__nothrow__));
extern char **__environ;
extern char **environ;
extern int execve (__const char *__path, char *__const __argv[],
     char *__const __envp[]) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int fexecve (int __fd, char *__const __argv[], char *__const __envp[])
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern int execv (__const char *__path, char *__const __argv[])
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int execle (__const char *__path, __const char *__arg, ...)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int execl (__const char *__path, __const char *__arg, ...)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int execvp (__const char *__file, char *__const __argv[])
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int execlp (__const char *__file, __const char *__arg, ...)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int execvpe (__const char *__file, char *__const __argv[],
      char *__const __envp[])
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int nice (int __inc) __attribute__ ((__nothrow__)) ;
extern void _exit (int __status) __attribute__ ((__noreturn__));
enum
  {
    _PC_LINK_MAX,
    _PC_MAX_CANON,
    _PC_MAX_INPUT,
    _PC_NAME_MAX,
    _PC_PATH_MAX,
    _PC_PIPE_BUF,
    _PC_CHOWN_RESTRICTED,
    _PC_NO_TRUNC,
    _PC_VDISABLE,
    _PC_SYNC_IO,
    _PC_ASYNC_IO,
    _PC_PRIO_IO,
    _PC_SOCK_MAXBUF,
    _PC_FILESIZEBITS,
    _PC_REC_INCR_XFER_SIZE,
    _PC_REC_MAX_XFER_SIZE,
    _PC_REC_MIN_XFER_SIZE,
    _PC_REC_XFER_ALIGN,
    _PC_ALLOC_SIZE_MIN,
    _PC_SYMLINK_MAX,
    _PC_2_SYMLINKS
  };
enum
  {
    _SC_ARG_MAX,
    _SC_CHILD_MAX,
    _SC_CLK_TCK,
    _SC_NGROUPS_MAX,
    _SC_OPEN_MAX,
    _SC_STREAM_MAX,
    _SC_TZNAME_MAX,
    _SC_JOB_CONTROL,
    _SC_SAVED_IDS,
    _SC_REALTIME_SIGNALS,
    _SC_PRIORITY_SCHEDULING,
    _SC_TIMERS,
    _SC_ASYNCHRONOUS_IO,
    _SC_PRIORITIZED_IO,
    _SC_SYNCHRONIZED_IO,
    _SC_FSYNC,
    _SC_MAPPED_FILES,
    _SC_MEMLOCK,
    _SC_MEMLOCK_RANGE,
    _SC_MEMORY_PROTECTION,
    _SC_MESSAGE_PASSING,
    _SC_SEMAPHORES,
    _SC_SHARED_MEMORY_OBJECTS,
    _SC_AIO_LISTIO_MAX,
    _SC_AIO_MAX,
    _SC_AIO_PRIO_DELTA_MAX,
    _SC_DELAYTIMER_MAX,
    _SC_MQ_OPEN_MAX,
    _SC_MQ_PRIO_MAX,
    _SC_VERSION,
    _SC_PAGESIZE,
    _SC_RTSIG_MAX,
    _SC_SEM_NSEMS_MAX,
    _SC_SEM_VALUE_MAX,
    _SC_SIGQUEUE_MAX,
    _SC_TIMER_MAX,
    _SC_BC_BASE_MAX,
    _SC_BC_DIM_MAX,
    _SC_BC_SCALE_MAX,
    _SC_BC_STRING_MAX,
    _SC_COLL_WEIGHTS_MAX,
    _SC_EQUIV_CLASS_MAX,
    _SC_EXPR_NEST_MAX,
    _SC_LINE_MAX,
    _SC_RE_DUP_MAX,
    _SC_CHARCLASS_NAME_MAX,
    _SC_2_VERSION,
    _SC_2_C_BIND,
    _SC_2_C_DEV,
    _SC_2_FORT_DEV,
    _SC_2_FORT_RUN,
    _SC_2_SW_DEV,
    _SC_2_LOCALEDEF,
    _SC_PII,
    _SC_PII_XTI,
    _SC_PII_SOCKET,
    _SC_PII_INTERNET,
    _SC_PII_OSI,
    _SC_POLL,
    _SC_SELECT,
    _SC_UIO_MAXIOV,
    _SC_IOV_MAX = _SC_UIO_MAXIOV,
    _SC_PII_INTERNET_STREAM,
    _SC_PII_INTERNET_DGRAM,
    _SC_PII_OSI_COTS,
    _SC_PII_OSI_CLTS,
    _SC_PII_OSI_M,
    _SC_T_IOV_MAX,
    _SC_THREADS,
    _SC_THREAD_SAFE_FUNCTIONS,
    _SC_GETGR_R_SIZE_MAX,
    _SC_GETPW_R_SIZE_MAX,
    _SC_LOGIN_NAME_MAX,
    _SC_TTY_NAME_MAX,
    _SC_THREAD_DESTRUCTOR_ITERATIONS,
    _SC_THREAD_KEYS_MAX,
    _SC_THREAD_STACK_MIN,
    _SC_THREAD_THREADS_MAX,
    _SC_THREAD_ATTR_STACKADDR,
    _SC_THREAD_ATTR_STACKSIZE,
    _SC_THREAD_PRIORITY_SCHEDULING,
    _SC_THREAD_PRIO_INHERIT,
    _SC_THREAD_PRIO_PROTECT,
    _SC_THREAD_PROCESS_SHARED,
    _SC_NPROCESSORS_CONF,
    _SC_NPROCESSORS_ONLN,
    _SC_PHYS_PAGES,
    _SC_AVPHYS_PAGES,
    _SC_ATEXIT_MAX,
    _SC_PASS_MAX,
    _SC_XOPEN_VERSION,
    _SC_XOPEN_XCU_VERSION,
    _SC_XOPEN_UNIX,
    _SC_XOPEN_CRYPT,
    _SC_XOPEN_ENH_I18N,
    _SC_XOPEN_SHM,
    _SC_2_CHAR_TERM,
    _SC_2_C_VERSION,
    _SC_2_UPE,
    _SC_XOPEN_XPG2,
    _SC_XOPEN_XPG3,
    _SC_XOPEN_XPG4,
    _SC_CHAR_BIT,
    _SC_CHAR_MAX,
    _SC_CHAR_MIN,
    _SC_INT_MAX,
    _SC_INT_MIN,
    _SC_LONG_BIT,
    _SC_WORD_BIT,
    _SC_MB_LEN_MAX,
    _SC_NZERO,
    _SC_SSIZE_MAX,
    _SC_SCHAR_MAX,
    _SC_SCHAR_MIN,
    _SC_SHRT_MAX,
    _SC_SHRT_MIN,
    _SC_UCHAR_MAX,
    _SC_UINT_MAX,
    _SC_ULONG_MAX,
    _SC_USHRT_MAX,
    _SC_NL_ARGMAX,
    _SC_NL_LANGMAX,
    _SC_NL_MSGMAX,
    _SC_NL_NMAX,
    _SC_NL_SETMAX,
    _SC_NL_TEXTMAX,
    _SC_XBS5_ILP32_OFF32,
    _SC_XBS5_ILP32_OFFBIG,
    _SC_XBS5_LP64_OFF64,
    _SC_XBS5_LPBIG_OFFBIG,
    _SC_XOPEN_LEGACY,
    _SC_XOPEN_REALTIME,
    _SC_XOPEN_REALTIME_THREADS,
    _SC_ADVISORY_INFO,
    _SC_BARRIERS,
    _SC_BASE,
    _SC_C_LANG_SUPPORT,
    _SC_C_LANG_SUPPORT_R,
    _SC_CLOCK_SELECTION,
    _SC_CPUTIME,
    _SC_THREAD_CPUTIME,
    _SC_DEVICE_IO,
    _SC_DEVICE_SPECIFIC,
    _SC_DEVICE_SPECIFIC_R,
    _SC_FD_MGMT,
    _SC_FIFO,
    _SC_PIPE,
    _SC_FILE_ATTRIBUTES,
    _SC_FILE_LOCKING,
    _SC_FILE_SYSTEM,
    _SC_MONOTONIC_CLOCK,
    _SC_MULTI_PROCESS,
    _SC_SINGLE_PROCESS,
    _SC_NETWORKING,
    _SC_READER_WRITER_LOCKS,
    _SC_SPIN_LOCKS,
    _SC_REGEXP,
    _SC_REGEX_VERSION,
    _SC_SHELL,
    _SC_SIGNALS,
    _SC_SPAWN,
    _SC_SPORADIC_SERVER,
    _SC_THREAD_SPORADIC_SERVER,
    _SC_SYSTEM_DATABASE,
    _SC_SYSTEM_DATABASE_R,
    _SC_TIMEOUTS,
    _SC_TYPED_MEMORY_OBJECTS,
    _SC_USER_GROUPS,
    _SC_USER_GROUPS_R,
    _SC_2_PBS,
    _SC_2_PBS_ACCOUNTING,
    _SC_2_PBS_LOCATE,
    _SC_2_PBS_MESSAGE,
    _SC_2_PBS_TRACK,
    _SC_SYMLOOP_MAX,
    _SC_STREAMS,
    _SC_2_PBS_CHECKPOINT,
    _SC_V6_ILP32_OFF32,
    _SC_V6_ILP32_OFFBIG,
    _SC_V6_LP64_OFF64,
    _SC_V6_LPBIG_OFFBIG,
    _SC_HOST_NAME_MAX,
    _SC_TRACE,
    _SC_TRACE_EVENT_FILTER,
    _SC_TRACE_INHERIT,
    _SC_TRACE_LOG,
    _SC_LEVEL1_ICACHE_SIZE,
    _SC_LEVEL1_ICACHE_ASSOC,
    _SC_LEVEL1_ICACHE_LINESIZE,
    _SC_LEVEL1_DCACHE_SIZE,
    _SC_LEVEL1_DCACHE_ASSOC,
    _SC_LEVEL1_DCACHE_LINESIZE,
    _SC_LEVEL2_CACHE_SIZE,
    _SC_LEVEL2_CACHE_ASSOC,
    _SC_LEVEL2_CACHE_LINESIZE,
    _SC_LEVEL3_CACHE_SIZE,
    _SC_LEVEL3_CACHE_ASSOC,
    _SC_LEVEL3_CACHE_LINESIZE,
    _SC_LEVEL4_CACHE_SIZE,
    _SC_LEVEL4_CACHE_ASSOC,
    _SC_LEVEL4_CACHE_LINESIZE,
    _SC_IPV6 = _SC_LEVEL1_ICACHE_SIZE + 50,
    _SC_RAW_SOCKETS,
    _SC_V7_ILP32_OFF32,
    _SC_V7_ILP32_OFFBIG,
    _SC_V7_LP64_OFF64,
    _SC_V7_LPBIG_OFFBIG,
    _SC_SS_REPL_MAX,
    _SC_TRACE_EVENT_NAME_MAX,
    _SC_TRACE_NAME_MAX,
    _SC_TRACE_SYS_MAX,
    _SC_TRACE_USER_EVENT_MAX,
    _SC_XOPEN_STREAMS,
    _SC_THREAD_ROBUST_PRIO_INHERIT,
    _SC_THREAD_ROBUST_PRIO_PROTECT
  };
enum
  {
    _CS_PATH,
    _CS_V6_WIDTH_RESTRICTED_ENVS,
    _CS_GNU_LIBC_VERSION,
    _CS_GNU_LIBPTHREAD_VERSION,
    _CS_V5_WIDTH_RESTRICTED_ENVS,
    _CS_V7_WIDTH_RESTRICTED_ENVS,
    _CS_LFS_CFLAGS = 1000,
    _CS_LFS_LDFLAGS,
    _CS_LFS_LIBS,
    _CS_LFS_LINTFLAGS,
    _CS_LFS64_CFLAGS,
    _CS_LFS64_LDFLAGS,
    _CS_LFS64_LIBS,
    _CS_LFS64_LINTFLAGS,
    _CS_XBS5_ILP32_OFF32_CFLAGS = 1100,
    _CS_XBS5_ILP32_OFF32_LDFLAGS,
    _CS_XBS5_ILP32_OFF32_LIBS,
    _CS_XBS5_ILP32_OFF32_LINTFLAGS,
    _CS_XBS5_ILP32_OFFBIG_CFLAGS,
    _CS_XBS5_ILP32_OFFBIG_LDFLAGS,
    _CS_XBS5_ILP32_OFFBIG_LIBS,
    _CS_XBS5_ILP32_OFFBIG_LINTFLAGS,
    _CS_XBS5_LP64_OFF64_CFLAGS,
    _CS_XBS5_LP64_OFF64_LDFLAGS,
    _CS_XBS5_LP64_OFF64_LIBS,
    _CS_XBS5_LP64_OFF64_LINTFLAGS,
    _CS_XBS5_LPBIG_OFFBIG_CFLAGS,
    _CS_XBS5_LPBIG_OFFBIG_LDFLAGS,
    _CS_XBS5_LPBIG_OFFBIG_LIBS,
    _CS_XBS5_LPBIG_OFFBIG_LINTFLAGS,
    _CS_POSIX_V6_ILP32_OFF32_CFLAGS,
    _CS_POSIX_V6_ILP32_OFF32_LDFLAGS,
    _CS_POSIX_V6_ILP32_OFF32_LIBS,
    _CS_POSIX_V6_ILP32_OFF32_LINTFLAGS,
    _CS_POSIX_V6_ILP32_OFFBIG_CFLAGS,
    _CS_POSIX_V6_ILP32_OFFBIG_LDFLAGS,
    _CS_POSIX_V6_ILP32_OFFBIG_LIBS,
    _CS_POSIX_V6_ILP32_OFFBIG_LINTFLAGS,
    _CS_POSIX_V6_LP64_OFF64_CFLAGS,
    _CS_POSIX_V6_LP64_OFF64_LDFLAGS,
    _CS_POSIX_V6_LP64_OFF64_LIBS,
    _CS_POSIX_V6_LP64_OFF64_LINTFLAGS,
    _CS_POSIX_V6_LPBIG_OFFBIG_CFLAGS,
    _CS_POSIX_V6_LPBIG_OFFBIG_LDFLAGS,
    _CS_POSIX_V6_LPBIG_OFFBIG_LIBS,
    _CS_POSIX_V6_LPBIG_OFFBIG_LINTFLAGS,
    _CS_POSIX_V7_ILP32_OFF32_CFLAGS,
    _CS_POSIX_V7_ILP32_OFF32_LDFLAGS,
    _CS_POSIX_V7_ILP32_OFF32_LIBS,
    _CS_POSIX_V7_ILP32_OFF32_LINTFLAGS,
    _CS_POSIX_V7_ILP32_OFFBIG_CFLAGS,
    _CS_POSIX_V7_ILP32_OFFBIG_LDFLAGS,
    _CS_POSIX_V7_ILP32_OFFBIG_LIBS,
    _CS_POSIX_V7_ILP32_OFFBIG_LINTFLAGS,
    _CS_POSIX_V7_LP64_OFF64_CFLAGS,
    _CS_POSIX_V7_LP64_OFF64_LDFLAGS,
    _CS_POSIX_V7_LP64_OFF64_LIBS,
    _CS_POSIX_V7_LP64_OFF64_LINTFLAGS,
    _CS_POSIX_V7_LPBIG_OFFBIG_CFLAGS,
    _CS_POSIX_V7_LPBIG_OFFBIG_LDFLAGS,
    _CS_POSIX_V7_LPBIG_OFFBIG_LIBS,
    _CS_POSIX_V7_LPBIG_OFFBIG_LINTFLAGS,
    _CS_V6_ENV,
    _CS_V7_ENV
  };
extern long int pathconf (__const char *__path, int __name)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern long int fpathconf (int __fd, int __name) __attribute__ ((__nothrow__));
extern long int sysconf (int __name) __attribute__ ((__nothrow__));
extern size_t confstr (int __name, char *__buf, size_t __len) __attribute__ ((__nothrow__));
extern __pid_t getpid (void) __attribute__ ((__nothrow__));
extern __pid_t getppid (void) __attribute__ ((__nothrow__));
extern __pid_t getpgrp (void) __attribute__ ((__nothrow__));
extern __pid_t __getpgid (__pid_t __pid) __attribute__ ((__nothrow__));
extern __pid_t getpgid (__pid_t __pid) __attribute__ ((__nothrow__));
extern int setpgid (__pid_t __pid, __pid_t __pgid) __attribute__ ((__nothrow__));
extern int setpgrp (void) __attribute__ ((__nothrow__));
extern __pid_t setsid (void) __attribute__ ((__nothrow__));
extern __pid_t getsid (__pid_t __pid) __attribute__ ((__nothrow__));
extern __uid_t getuid (void) __attribute__ ((__nothrow__));
extern __uid_t geteuid (void) __attribute__ ((__nothrow__));
extern __gid_t getgid (void) __attribute__ ((__nothrow__));
extern __gid_t getegid (void) __attribute__ ((__nothrow__));
extern int getgroups (int __size, __gid_t __list[]) __attribute__ ((__nothrow__)) ;
extern int group_member (__gid_t __gid) __attribute__ ((__nothrow__));
extern int setuid (__uid_t __uid) __attribute__ ((__nothrow__));
extern int setreuid (__uid_t __ruid, __uid_t __euid) __attribute__ ((__nothrow__));
extern int seteuid (__uid_t __uid) __attribute__ ((__nothrow__));
extern int setgid (__gid_t __gid) __attribute__ ((__nothrow__));
extern int setregid (__gid_t __rgid, __gid_t __egid) __attribute__ ((__nothrow__));
extern int setegid (__gid_t __gid) __attribute__ ((__nothrow__));
extern int getresuid (__uid_t *__ruid, __uid_t *__euid, __uid_t *__suid)
     __attribute__ ((__nothrow__));
extern int getresgid (__gid_t *__rgid, __gid_t *__egid, __gid_t *__sgid)
     __attribute__ ((__nothrow__));
extern int setresuid (__uid_t __ruid, __uid_t __euid, __uid_t __suid)
     __attribute__ ((__nothrow__));
extern int setresgid (__gid_t __rgid, __gid_t __egid, __gid_t __sgid)
     __attribute__ ((__nothrow__));
extern __pid_t fork (void) __attribute__ ((__nothrow__));
extern __pid_t vfork (void) __attribute__ ((__nothrow__));
extern char *ttyname (int __fd) __attribute__ ((__nothrow__));
extern int ttyname_r (int __fd, char *__buf, size_t __buflen)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2))) ;
extern int isatty (int __fd) __attribute__ ((__nothrow__));
extern int ttyslot (void) __attribute__ ((__nothrow__));
extern int link (__const char *__from, __const char *__to)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2))) ;
extern int linkat (int __fromfd, __const char *__from, int __tofd,
     __const char *__to, int __flags)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 4))) ;
extern int symlink (__const char *__from, __const char *__to)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2))) ;
extern ssize_t readlink (__const char *__restrict __path,
    char *__restrict __buf, size_t __len)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2))) ;
extern int symlinkat (__const char *__from, int __tofd,
        __const char *__to) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 3))) ;
extern ssize_t readlinkat (int __fd, __const char *__restrict __path,
      char *__restrict __buf, size_t __len)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 3))) ;
extern int unlink (__const char *__name) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int unlinkat (int __fd, __const char *__name, int __flag)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern int rmdir (__const char *__path) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern __pid_t tcgetpgrp (int __fd) __attribute__ ((__nothrow__));
extern int tcsetpgrp (int __fd, __pid_t __pgrp_id) __attribute__ ((__nothrow__));
extern char *getlogin (void);
extern int getlogin_r (char *__name, size_t __name_len) __attribute__ ((__nonnull__ (1)));
extern int setlogin (__const char *__name) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern char *optarg;
extern int optind;
extern int opterr;
extern int optopt;
extern int getopt (int ___argc, char *const *___argv, const char *__shortopts)
       __attribute__ ((__nothrow__));
extern int gethostname (char *__name, size_t __len) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int sethostname (__const char *__name, size_t __len)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern int sethostid (long int __id) __attribute__ ((__nothrow__)) ;
extern int getdomainname (char *__name, size_t __len)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern int setdomainname (__const char *__name, size_t __len)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern int vhangup (void) __attribute__ ((__nothrow__));
extern int revoke (__const char *__file) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern int profil (unsigned short int *__sample_buffer, size_t __size,
     size_t __offset, unsigned int __scale)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int acct (__const char *__name) __attribute__ ((__nothrow__));
extern char *getusershell (void) __attribute__ ((__nothrow__));
extern void endusershell (void) __attribute__ ((__nothrow__));
extern void setusershell (void) __attribute__ ((__nothrow__));
extern int daemon (int __nochdir, int __noclose) __attribute__ ((__nothrow__)) ;
extern int chroot (__const char *__path) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern char *getpass (__const char *__prompt) __attribute__ ((__nonnull__ (1)));
extern int fsync (int __fd);
extern long int gethostid (void);
extern void sync (void) __attribute__ ((__nothrow__));
extern int getpagesize (void) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern int getdtablesize (void) __attribute__ ((__nothrow__));
extern int truncate (__const char *__file, __off_t __length)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern int truncate64 (__const char *__file, __off64_t __length)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern int ftruncate (int __fd, __off_t __length) __attribute__ ((__nothrow__)) ;
extern int ftruncate64 (int __fd, __off64_t __length) __attribute__ ((__nothrow__)) ;
extern int brk (void *__addr) __attribute__ ((__nothrow__)) ;
extern void *sbrk (intptr_t __delta) __attribute__ ((__nothrow__));
extern long int syscall (long int __sysno, ...) __attribute__ ((__nothrow__));
extern int lockf (int __fd, int __cmd, __off_t __len) ;
extern int lockf64 (int __fd, int __cmd, __off64_t __len) ;
extern int fdatasync (int __fildes);
extern char *crypt (__const char *__key, __const char *__salt)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern void encrypt (char *__block, int __edflag) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern void swab (__const void *__restrict __from, void *__restrict __to,
    ssize_t __n) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *ctermid (char *__s) __attribute__ ((__nothrow__));



[[nodiscard]]
__attribute__((__malloc__))
__attribute__((__returns_nonnull__))
__attribute__((__alloc_size__ (1)))
void *ruby_xmalloc(size_t size)

;
[[nodiscard]]
__attribute__((__malloc__))
__attribute__((__returns_nonnull__))
__attribute__((__alloc_size__ (1,2)))
void *ruby_xmalloc2(size_t nelems, size_t elemsiz)

;
[[nodiscard]]
__attribute__((__malloc__))
__attribute__((__returns_nonnull__))
__attribute__((__alloc_size__ (1,2)))
void *ruby_xcalloc(size_t nelems, size_t elemsiz)

;
[[nodiscard]]
__attribute__((__returns_nonnull__))
__attribute__((__alloc_size__ (2)))
void *ruby_xrealloc(void *ptr, size_t newsiz)

;
[[nodiscard]]
__attribute__((__returns_nonnull__))
__attribute__((__alloc_size__ (2,3)))
void *ruby_xrealloc2(void *ptr, size_t newelems, size_t newsiz)

;
void ruby_xfree(void *ptr)

;


#define RBIMPL_ATTR_COLD_H 
#define RBIMPL_ATTR_COLD() __attribute__((__cold__))


__attribute__((__noreturn__))
__attribute__((__cold__))
void rb_assert_failure(const char *file, int line, const char *name, const char *expr);


#define COLDFUNC RBIMPL_ATTR_COLD()

typedef float float_t;
typedef double double_t;

extern double acos (double __x) __attribute__ ((__nothrow__)); extern double __acos (double __x) __attribute__ ((__nothrow__));
extern double asin (double __x) __attribute__ ((__nothrow__)); extern double __asin (double __x) __attribute__ ((__nothrow__));
extern double atan (double __x) __attribute__ ((__nothrow__)); extern double __atan (double __x) __attribute__ ((__nothrow__));
extern double atan2 (double __y, double __x) __attribute__ ((__nothrow__)); extern double __atan2 (double __y, double __x) __attribute__ ((__nothrow__));
extern double cos (double __x) __attribute__ ((__nothrow__)); extern double __cos (double __x) __attribute__ ((__nothrow__));
extern double sin (double __x) __attribute__ ((__nothrow__)); extern double __sin (double __x) __attribute__ ((__nothrow__));
extern double tan (double __x) __attribute__ ((__nothrow__)); extern double __tan (double __x) __attribute__ ((__nothrow__));
extern double cosh (double __x) __attribute__ ((__nothrow__)); extern double __cosh (double __x) __attribute__ ((__nothrow__));
extern double sinh (double __x) __attribute__ ((__nothrow__)); extern double __sinh (double __x) __attribute__ ((__nothrow__));
extern double tanh (double __x) __attribute__ ((__nothrow__)); extern double __tanh (double __x) __attribute__ ((__nothrow__));

extern void sincos (double __x, double *__sinx, double *__cosx) __attribute__ ((__nothrow__)); extern void __sincos (double __x, double *__sinx, double *__cosx) __attribute__ ((__nothrow__));

extern double acosh (double __x) __attribute__ ((__nothrow__)); extern double __acosh (double __x) __attribute__ ((__nothrow__));
extern double asinh (double __x) __attribute__ ((__nothrow__)); extern double __asinh (double __x) __attribute__ ((__nothrow__));
extern double atanh (double __x) __attribute__ ((__nothrow__)); extern double __atanh (double __x) __attribute__ ((__nothrow__));


extern double exp (double __x) __attribute__ ((__nothrow__)); extern double __exp (double __x) __attribute__ ((__nothrow__));
extern double frexp (double __x, int *__exponent) __attribute__ ((__nothrow__)); extern double __frexp (double __x, int *__exponent) __attribute__ ((__nothrow__));
extern double ldexp (double __x, int __exponent) __attribute__ ((__nothrow__)); extern double __ldexp (double __x, int __exponent) __attribute__ ((__nothrow__));
extern double log (double __x) __attribute__ ((__nothrow__)); extern double __log (double __x) __attribute__ ((__nothrow__));
extern double log10 (double __x) __attribute__ ((__nothrow__)); extern double __log10 (double __x) __attribute__ ((__nothrow__));
extern double modf (double __x, double *__iptr) __attribute__ ((__nothrow__)); extern double __modf (double __x, double *__iptr) __attribute__ ((__nothrow__));

extern double exp10 (double __x) __attribute__ ((__nothrow__)); extern double __exp10 (double __x) __attribute__ ((__nothrow__));
extern double pow10 (double __x) __attribute__ ((__nothrow__)); extern double __pow10 (double __x) __attribute__ ((__nothrow__));

extern double expm1 (double __x) __attribute__ ((__nothrow__)); extern double __expm1 (double __x) __attribute__ ((__nothrow__));
extern double log1p (double __x) __attribute__ ((__nothrow__)); extern double __log1p (double __x) __attribute__ ((__nothrow__));
extern double logb (double __x) __attribute__ ((__nothrow__)); extern double __logb (double __x) __attribute__ ((__nothrow__));


extern double exp2 (double __x) __attribute__ ((__nothrow__)); extern double __exp2 (double __x) __attribute__ ((__nothrow__));
extern double log2 (double __x) __attribute__ ((__nothrow__)); extern double __log2 (double __x) __attribute__ ((__nothrow__));


extern double pow (double __x, double __y) __attribute__ ((__nothrow__)); extern double __pow (double __x, double __y) __attribute__ ((__nothrow__));
extern double sqrt (double __x) __attribute__ ((__nothrow__)); extern double __sqrt (double __x) __attribute__ ((__nothrow__));


extern double hypot (double __x, double __y) __attribute__ ((__nothrow__)); extern double __hypot (double __x, double __y) __attribute__ ((__nothrow__));


extern double cbrt (double __x) __attribute__ ((__nothrow__)); extern double __cbrt (double __x) __attribute__ ((__nothrow__));


extern double ceil (double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern double __ceil (double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern double fabs (double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern double __fabs (double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern double floor (double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern double __floor (double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern double fmod (double __x, double __y) __attribute__ ((__nothrow__)); extern double __fmod (double __x, double __y) __attribute__ ((__nothrow__));
extern int __isinf (double __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern int __finite (double __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));

extern int isinf (double __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern int finite (double __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern double drem (double __x, double __y) __attribute__ ((__nothrow__)); extern double __drem (double __x, double __y) __attribute__ ((__nothrow__));
extern double significand (double __x) __attribute__ ((__nothrow__)); extern double __significand (double __x) __attribute__ ((__nothrow__));

extern double copysign (double __x, double __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern double __copysign (double __x, double __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__));


extern double nan (__const char *__tagb) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern double __nan (__const char *__tagb) __attribute__ ((__nothrow__)) __attribute__ ((__const__));

extern int __isnan (double __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern int isnan (double __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern double j0 (double) __attribute__ ((__nothrow__)); extern double __j0 (double) __attribute__ ((__nothrow__));
extern double j1 (double) __attribute__ ((__nothrow__)); extern double __j1 (double) __attribute__ ((__nothrow__));
extern double jn (int, double) __attribute__ ((__nothrow__)); extern double __jn (int, double) __attribute__ ((__nothrow__));
extern double y0 (double) __attribute__ ((__nothrow__)); extern double __y0 (double) __attribute__ ((__nothrow__));
extern double y1 (double) __attribute__ ((__nothrow__)); extern double __y1 (double) __attribute__ ((__nothrow__));
extern double yn (int, double) __attribute__ ((__nothrow__)); extern double __yn (int, double) __attribute__ ((__nothrow__));

extern double erf (double) __attribute__ ((__nothrow__)); extern double __erf (double) __attribute__ ((__nothrow__));
extern double erfc (double) __attribute__ ((__nothrow__)); extern double __erfc (double) __attribute__ ((__nothrow__));
extern double lgamma (double) __attribute__ ((__nothrow__)); extern double __lgamma (double) __attribute__ ((__nothrow__));


extern double tgamma (double) __attribute__ ((__nothrow__)); extern double __tgamma (double) __attribute__ ((__nothrow__));

extern double gamma (double) __attribute__ ((__nothrow__)); extern double __gamma (double) __attribute__ ((__nothrow__));
extern double lgamma_r (double, int *__signgamp) __attribute__ ((__nothrow__)); extern double __lgamma_r (double, int *__signgamp) __attribute__ ((__nothrow__));

extern double rint (double __x) __attribute__ ((__nothrow__)); extern double __rint (double __x) __attribute__ ((__nothrow__));
extern double nextafter (double __x, double __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern double __nextafter (double __x, double __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern double nexttoward (double __x, long double __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern double __nexttoward (double __x, long double __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern double remainder (double __x, double __y) __attribute__ ((__nothrow__)); extern double __remainder (double __x, double __y) __attribute__ ((__nothrow__));
extern double scalbn (double __x, int __n) __attribute__ ((__nothrow__)); extern double __scalbn (double __x, int __n) __attribute__ ((__nothrow__));
extern int ilogb (double __x) __attribute__ ((__nothrow__)); extern int __ilogb (double __x) __attribute__ ((__nothrow__));
extern double scalbln (double __x, long int __n) __attribute__ ((__nothrow__)); extern double __scalbln (double __x, long int __n) __attribute__ ((__nothrow__));
extern double nearbyint (double __x) __attribute__ ((__nothrow__)); extern double __nearbyint (double __x) __attribute__ ((__nothrow__));
extern double round (double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern double __round (double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern double trunc (double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern double __trunc (double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern double remquo (double __x, double __y, int *__quo) __attribute__ ((__nothrow__)); extern double __remquo (double __x, double __y, int *__quo) __attribute__ ((__nothrow__));
extern long int lrint (double __x) __attribute__ ((__nothrow__)); extern long int __lrint (double __x) __attribute__ ((__nothrow__));
extern long long int llrint (double __x) __attribute__ ((__nothrow__)); extern long long int __llrint (double __x) __attribute__ ((__nothrow__));
extern long int lround (double __x) __attribute__ ((__nothrow__)); extern long int __lround (double __x) __attribute__ ((__nothrow__));
extern long long int llround (double __x) __attribute__ ((__nothrow__)); extern long long int __llround (double __x) __attribute__ ((__nothrow__));
extern double fdim (double __x, double __y) __attribute__ ((__nothrow__)); extern double __fdim (double __x, double __y) __attribute__ ((__nothrow__));
extern double fmax (double __x, double __y) __attribute__ ((__nothrow__)); extern double __fmax (double __x, double __y) __attribute__ ((__nothrow__));
extern double fmin (double __x, double __y) __attribute__ ((__nothrow__)); extern double __fmin (double __x, double __y) __attribute__ ((__nothrow__));
extern int __fpclassify (double __value) __attribute__ ((__nothrow__))
     __attribute__ ((__const__));
extern int __signbit (double __value) __attribute__ ((__nothrow__))
     __attribute__ ((__const__));
extern double fma (double __x, double __y, double __z) __attribute__ ((__nothrow__)); extern double __fma (double __x, double __y, double __z) __attribute__ ((__nothrow__));

extern double scalb (double __x, double __n) __attribute__ ((__nothrow__)); extern double __scalb (double __x, double __n) __attribute__ ((__nothrow__));

extern float acosf (float __x) __attribute__ ((__nothrow__)); extern float __acosf (float __x) __attribute__ ((__nothrow__));
extern float asinf (float __x) __attribute__ ((__nothrow__)); extern float __asinf (float __x) __attribute__ ((__nothrow__));
extern float atanf (float __x) __attribute__ ((__nothrow__)); extern float __atanf (float __x) __attribute__ ((__nothrow__));
extern float atan2f (float __y, float __x) __attribute__ ((__nothrow__)); extern float __atan2f (float __y, float __x) __attribute__ ((__nothrow__));
extern float cosf (float __x) __attribute__ ((__nothrow__)); extern float __cosf (float __x) __attribute__ ((__nothrow__));
extern float sinf (float __x) __attribute__ ((__nothrow__)); extern float __sinf (float __x) __attribute__ ((__nothrow__));
extern float tanf (float __x) __attribute__ ((__nothrow__)); extern float __tanf (float __x) __attribute__ ((__nothrow__));
extern float coshf (float __x) __attribute__ ((__nothrow__)); extern float __coshf (float __x) __attribute__ ((__nothrow__));
extern float sinhf (float __x) __attribute__ ((__nothrow__)); extern float __sinhf (float __x) __attribute__ ((__nothrow__));
extern float tanhf (float __x) __attribute__ ((__nothrow__)); extern float __tanhf (float __x) __attribute__ ((__nothrow__));

extern void sincosf (float __x, float *__sinx, float *__cosx) __attribute__ ((__nothrow__)); extern void __sincosf (float __x, float *__sinx, float *__cosx) __attribute__ ((__nothrow__));

extern float acoshf (float __x) __attribute__ ((__nothrow__)); extern float __acoshf (float __x) __attribute__ ((__nothrow__));
extern float asinhf (float __x) __attribute__ ((__nothrow__)); extern float __asinhf (float __x) __attribute__ ((__nothrow__));
extern float atanhf (float __x) __attribute__ ((__nothrow__)); extern float __atanhf (float __x) __attribute__ ((__nothrow__));


extern float expf (float __x) __attribute__ ((__nothrow__)); extern float __expf (float __x) __attribute__ ((__nothrow__));
extern float frexpf (float __x, int *__exponent) __attribute__ ((__nothrow__)); extern float __frexpf (float __x, int *__exponent) __attribute__ ((__nothrow__));
extern float ldexpf (float __x, int __exponent) __attribute__ ((__nothrow__)); extern float __ldexpf (float __x, int __exponent) __attribute__ ((__nothrow__));
extern float logf (float __x) __attribute__ ((__nothrow__)); extern float __logf (float __x) __attribute__ ((__nothrow__));
extern float log10f (float __x) __attribute__ ((__nothrow__)); extern float __log10f (float __x) __attribute__ ((__nothrow__));
extern float modff (float __x, float *__iptr) __attribute__ ((__nothrow__)); extern float __modff (float __x, float *__iptr) __attribute__ ((__nothrow__));

extern float exp10f (float __x) __attribute__ ((__nothrow__)); extern float __exp10f (float __x) __attribute__ ((__nothrow__));
extern float pow10f (float __x) __attribute__ ((__nothrow__)); extern float __pow10f (float __x) __attribute__ ((__nothrow__));

extern float expm1f (float __x) __attribute__ ((__nothrow__)); extern float __expm1f (float __x) __attribute__ ((__nothrow__));
extern float log1pf (float __x) __attribute__ ((__nothrow__)); extern float __log1pf (float __x) __attribute__ ((__nothrow__));
extern float logbf (float __x) __attribute__ ((__nothrow__)); extern float __logbf (float __x) __attribute__ ((__nothrow__));


extern float exp2f (float __x) __attribute__ ((__nothrow__)); extern float __exp2f (float __x) __attribute__ ((__nothrow__));
extern float log2f (float __x) __attribute__ ((__nothrow__)); extern float __log2f (float __x) __attribute__ ((__nothrow__));


extern float powf (float __x, float __y) __attribute__ ((__nothrow__)); extern float __powf (float __x, float __y) __attribute__ ((__nothrow__));
extern float sqrtf (float __x) __attribute__ ((__nothrow__)); extern float __sqrtf (float __x) __attribute__ ((__nothrow__));


extern float hypotf (float __x, float __y) __attribute__ ((__nothrow__)); extern float __hypotf (float __x, float __y) __attribute__ ((__nothrow__));


extern float cbrtf (float __x) __attribute__ ((__nothrow__)); extern float __cbrtf (float __x) __attribute__ ((__nothrow__));


extern float ceilf (float __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern float __ceilf (float __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern float fabsf (float __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern float __fabsf (float __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern float floorf (float __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern float __floorf (float __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern float fmodf (float __x, float __y) __attribute__ ((__nothrow__)); extern float __fmodf (float __x, float __y) __attribute__ ((__nothrow__));
extern int __isinff (float __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern int __finitef (float __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));

extern int isinff (float __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern int finitef (float __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern float dremf (float __x, float __y) __attribute__ ((__nothrow__)); extern float __dremf (float __x, float __y) __attribute__ ((__nothrow__));
extern float significandf (float __x) __attribute__ ((__nothrow__)); extern float __significandf (float __x) __attribute__ ((__nothrow__));

extern float copysignf (float __x, float __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern float __copysignf (float __x, float __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__));


extern float nanf (__const char *__tagb) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern float __nanf (__const char *__tagb) __attribute__ ((__nothrow__)) __attribute__ ((__const__));

extern int __isnanf (float __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern int isnanf (float __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern float j0f (float) __attribute__ ((__nothrow__)); extern float __j0f (float) __attribute__ ((__nothrow__));
extern float j1f (float) __attribute__ ((__nothrow__)); extern float __j1f (float) __attribute__ ((__nothrow__));
extern float jnf (int, float) __attribute__ ((__nothrow__)); extern float __jnf (int, float) __attribute__ ((__nothrow__));
extern float y0f (float) __attribute__ ((__nothrow__)); extern float __y0f (float) __attribute__ ((__nothrow__));
extern float y1f (float) __attribute__ ((__nothrow__)); extern float __y1f (float) __attribute__ ((__nothrow__));
extern float ynf (int, float) __attribute__ ((__nothrow__)); extern float __ynf (int, float) __attribute__ ((__nothrow__));

extern float erff (float) __attribute__ ((__nothrow__)); extern float __erff (float) __attribute__ ((__nothrow__));
extern float erfcf (float) __attribute__ ((__nothrow__)); extern float __erfcf (float) __attribute__ ((__nothrow__));
extern float lgammaf (float) __attribute__ ((__nothrow__)); extern float __lgammaf (float) __attribute__ ((__nothrow__));


extern float tgammaf (float) __attribute__ ((__nothrow__)); extern float __tgammaf (float) __attribute__ ((__nothrow__));

extern float gammaf (float) __attribute__ ((__nothrow__)); extern float __gammaf (float) __attribute__ ((__nothrow__));
extern float lgammaf_r (float, int *__signgamp) __attribute__ ((__nothrow__)); extern float __lgammaf_r (float, int *__signgamp) __attribute__ ((__nothrow__));

extern float rintf (float __x) __attribute__ ((__nothrow__)); extern float __rintf (float __x) __attribute__ ((__nothrow__));
extern float nextafterf (float __x, float __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern float __nextafterf (float __x, float __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern float nexttowardf (float __x, long double __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern float __nexttowardf (float __x, long double __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern float remainderf (float __x, float __y) __attribute__ ((__nothrow__)); extern float __remainderf (float __x, float __y) __attribute__ ((__nothrow__));
extern float scalbnf (float __x, int __n) __attribute__ ((__nothrow__)); extern float __scalbnf (float __x, int __n) __attribute__ ((__nothrow__));
extern int ilogbf (float __x) __attribute__ ((__nothrow__)); extern int __ilogbf (float __x) __attribute__ ((__nothrow__));
extern float scalblnf (float __x, long int __n) __attribute__ ((__nothrow__)); extern float __scalblnf (float __x, long int __n) __attribute__ ((__nothrow__));
extern float nearbyintf (float __x) __attribute__ ((__nothrow__)); extern float __nearbyintf (float __x) __attribute__ ((__nothrow__));
extern float roundf (float __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern float __roundf (float __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern float truncf (float __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern float __truncf (float __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern float remquof (float __x, float __y, int *__quo) __attribute__ ((__nothrow__)); extern float __remquof (float __x, float __y, int *__quo) __attribute__ ((__nothrow__));
extern long int lrintf (float __x) __attribute__ ((__nothrow__)); extern long int __lrintf (float __x) __attribute__ ((__nothrow__));
extern long long int llrintf (float __x) __attribute__ ((__nothrow__)); extern long long int __llrintf (float __x) __attribute__ ((__nothrow__));
extern long int lroundf (float __x) __attribute__ ((__nothrow__)); extern long int __lroundf (float __x) __attribute__ ((__nothrow__));
extern long long int llroundf (float __x) __attribute__ ((__nothrow__)); extern long long int __llroundf (float __x) __attribute__ ((__nothrow__));
extern float fdimf (float __x, float __y) __attribute__ ((__nothrow__)); extern float __fdimf (float __x, float __y) __attribute__ ((__nothrow__));
extern float fmaxf (float __x, float __y) __attribute__ ((__nothrow__)); extern float __fmaxf (float __x, float __y) __attribute__ ((__nothrow__));
extern float fminf (float __x, float __y) __attribute__ ((__nothrow__)); extern float __fminf (float __x, float __y) __attribute__ ((__nothrow__));
extern int __fpclassifyf (float __value) __attribute__ ((__nothrow__))
     __attribute__ ((__const__));
extern int __signbitf (float __value) __attribute__ ((__nothrow__))
     __attribute__ ((__const__));
extern float fmaf (float __x, float __y, float __z) __attribute__ ((__nothrow__)); extern float __fmaf (float __x, float __y, float __z) __attribute__ ((__nothrow__));

extern float scalbf (float __x, float __n) __attribute__ ((__nothrow__)); extern float __scalbf (float __x, float __n) __attribute__ ((__nothrow__));

extern long double acosl (long double __x) __attribute__ ((__nothrow__)); extern long double __acosl (long double __x) __attribute__ ((__nothrow__));
extern long double asinl (long double __x) __attribute__ ((__nothrow__)); extern long double __asinl (long double __x) __attribute__ ((__nothrow__));
extern long double atanl (long double __x) __attribute__ ((__nothrow__)); extern long double __atanl (long double __x) __attribute__ ((__nothrow__));
extern long double atan2l (long double __y, long double __x) __attribute__ ((__nothrow__)); extern long double __atan2l (long double __y, long double __x) __attribute__ ((__nothrow__));
extern long double cosl (long double __x) __attribute__ ((__nothrow__)); extern long double __cosl (long double __x) __attribute__ ((__nothrow__));
extern long double sinl (long double __x) __attribute__ ((__nothrow__)); extern long double __sinl (long double __x) __attribute__ ((__nothrow__));
extern long double tanl (long double __x) __attribute__ ((__nothrow__)); extern long double __tanl (long double __x) __attribute__ ((__nothrow__));
extern long double coshl (long double __x) __attribute__ ((__nothrow__)); extern long double __coshl (long double __x) __attribute__ ((__nothrow__));
extern long double sinhl (long double __x) __attribute__ ((__nothrow__)); extern long double __sinhl (long double __x) __attribute__ ((__nothrow__));
extern long double tanhl (long double __x) __attribute__ ((__nothrow__)); extern long double __tanhl (long double __x) __attribute__ ((__nothrow__));

extern void sincosl (long double __x, long double *__sinx, long double *__cosx) __attribute__ ((__nothrow__)); extern void __sincosl (long double __x, long double *__sinx, long double *__cosx) __attribute__ ((__nothrow__));

extern long double acoshl (long double __x) __attribute__ ((__nothrow__)); extern long double __acoshl (long double __x) __attribute__ ((__nothrow__));
extern long double asinhl (long double __x) __attribute__ ((__nothrow__)); extern long double __asinhl (long double __x) __attribute__ ((__nothrow__));
extern long double atanhl (long double __x) __attribute__ ((__nothrow__)); extern long double __atanhl (long double __x) __attribute__ ((__nothrow__));


extern long double expl (long double __x) __attribute__ ((__nothrow__)); extern long double __expl (long double __x) __attribute__ ((__nothrow__));
extern long double frexpl (long double __x, int *__exponent) __attribute__ ((__nothrow__)); extern long double __frexpl (long double __x, int *__exponent) __attribute__ ((__nothrow__));
extern long double ldexpl (long double __x, int __exponent) __attribute__ ((__nothrow__)); extern long double __ldexpl (long double __x, int __exponent) __attribute__ ((__nothrow__));
extern long double logl (long double __x) __attribute__ ((__nothrow__)); extern long double __logl (long double __x) __attribute__ ((__nothrow__));
extern long double log10l (long double __x) __attribute__ ((__nothrow__)); extern long double __log10l (long double __x) __attribute__ ((__nothrow__));
extern long double modfl (long double __x, long double *__iptr) __attribute__ ((__nothrow__)); extern long double __modfl (long double __x, long double *__iptr) __attribute__ ((__nothrow__));

extern long double exp10l (long double __x) __attribute__ ((__nothrow__)); extern long double __exp10l (long double __x) __attribute__ ((__nothrow__));
extern long double pow10l (long double __x) __attribute__ ((__nothrow__)); extern long double __pow10l (long double __x) __attribute__ ((__nothrow__));

extern long double expm1l (long double __x) __attribute__ ((__nothrow__)); extern long double __expm1l (long double __x) __attribute__ ((__nothrow__));
extern long double log1pl (long double __x) __attribute__ ((__nothrow__)); extern long double __log1pl (long double __x) __attribute__ ((__nothrow__));
extern long double logbl (long double __x) __attribute__ ((__nothrow__)); extern long double __logbl (long double __x) __attribute__ ((__nothrow__));


extern long double exp2l (long double __x) __attribute__ ((__nothrow__)); extern long double __exp2l (long double __x) __attribute__ ((__nothrow__));
extern long double log2l (long double __x) __attribute__ ((__nothrow__)); extern long double __log2l (long double __x) __attribute__ ((__nothrow__));


extern long double powl (long double __x, long double __y) __attribute__ ((__nothrow__)); extern long double __powl (long double __x, long double __y) __attribute__ ((__nothrow__));
extern long double sqrtl (long double __x) __attribute__ ((__nothrow__)); extern long double __sqrtl (long double __x) __attribute__ ((__nothrow__));


extern long double hypotl (long double __x, long double __y) __attribute__ ((__nothrow__)); extern long double __hypotl (long double __x, long double __y) __attribute__ ((__nothrow__));


extern long double cbrtl (long double __x) __attribute__ ((__nothrow__)); extern long double __cbrtl (long double __x) __attribute__ ((__nothrow__));


extern long double ceill (long double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern long double __ceill (long double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern long double fabsl (long double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern long double __fabsl (long double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern long double floorl (long double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern long double __floorl (long double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern long double fmodl (long double __x, long double __y) __attribute__ ((__nothrow__)); extern long double __fmodl (long double __x, long double __y) __attribute__ ((__nothrow__));
extern int __isinfl (long double __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern int __finitel (long double __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));

extern int isinfl (long double __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern int finitel (long double __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern long double dreml (long double __x, long double __y) __attribute__ ((__nothrow__)); extern long double __dreml (long double __x, long double __y) __attribute__ ((__nothrow__));
extern long double significandl (long double __x) __attribute__ ((__nothrow__)); extern long double __significandl (long double __x) __attribute__ ((__nothrow__));

extern long double copysignl (long double __x, long double __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern long double __copysignl (long double __x, long double __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__));


extern long double nanl (__const char *__tagb) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern long double __nanl (__const char *__tagb) __attribute__ ((__nothrow__)) __attribute__ ((__const__));

extern int __isnanl (long double __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern int isnanl (long double __value) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern long double j0l (long double) __attribute__ ((__nothrow__)); extern long double __j0l (long double) __attribute__ ((__nothrow__));
extern long double j1l (long double) __attribute__ ((__nothrow__)); extern long double __j1l (long double) __attribute__ ((__nothrow__));
extern long double jnl (int, long double) __attribute__ ((__nothrow__)); extern long double __jnl (int, long double) __attribute__ ((__nothrow__));
extern long double y0l (long double) __attribute__ ((__nothrow__)); extern long double __y0l (long double) __attribute__ ((__nothrow__));
extern long double y1l (long double) __attribute__ ((__nothrow__)); extern long double __y1l (long double) __attribute__ ((__nothrow__));
extern long double ynl (int, long double) __attribute__ ((__nothrow__)); extern long double __ynl (int, long double) __attribute__ ((__nothrow__));

extern long double erfl (long double) __attribute__ ((__nothrow__)); extern long double __erfl (long double) __attribute__ ((__nothrow__));
extern long double erfcl (long double) __attribute__ ((__nothrow__)); extern long double __erfcl (long double) __attribute__ ((__nothrow__));
extern long double lgammal (long double) __attribute__ ((__nothrow__)); extern long double __lgammal (long double) __attribute__ ((__nothrow__));


extern long double tgammal (long double) __attribute__ ((__nothrow__)); extern long double __tgammal (long double) __attribute__ ((__nothrow__));

extern long double gammal (long double) __attribute__ ((__nothrow__)); extern long double __gammal (long double) __attribute__ ((__nothrow__));
extern long double lgammal_r (long double, int *__signgamp) __attribute__ ((__nothrow__)); extern long double __lgammal_r (long double, int *__signgamp) __attribute__ ((__nothrow__));

extern long double rintl (long double __x) __attribute__ ((__nothrow__)); extern long double __rintl (long double __x) __attribute__ ((__nothrow__));
extern long double nextafterl (long double __x, long double __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern long double __nextafterl (long double __x, long double __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern long double nexttowardl (long double __x, long double __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern long double __nexttowardl (long double __x, long double __y) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern long double remainderl (long double __x, long double __y) __attribute__ ((__nothrow__)); extern long double __remainderl (long double __x, long double __y) __attribute__ ((__nothrow__));
extern long double scalbnl (long double __x, int __n) __attribute__ ((__nothrow__)); extern long double __scalbnl (long double __x, int __n) __attribute__ ((__nothrow__));
extern int ilogbl (long double __x) __attribute__ ((__nothrow__)); extern int __ilogbl (long double __x) __attribute__ ((__nothrow__));
extern long double scalblnl (long double __x, long int __n) __attribute__ ((__nothrow__)); extern long double __scalblnl (long double __x, long int __n) __attribute__ ((__nothrow__));
extern long double nearbyintl (long double __x) __attribute__ ((__nothrow__)); extern long double __nearbyintl (long double __x) __attribute__ ((__nothrow__));
extern long double roundl (long double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern long double __roundl (long double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern long double truncl (long double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)); extern long double __truncl (long double __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern long double remquol (long double __x, long double __y, int *__quo) __attribute__ ((__nothrow__)); extern long double __remquol (long double __x, long double __y, int *__quo) __attribute__ ((__nothrow__));
extern long int lrintl (long double __x) __attribute__ ((__nothrow__)); extern long int __lrintl (long double __x) __attribute__ ((__nothrow__));
extern long long int llrintl (long double __x) __attribute__ ((__nothrow__)); extern long long int __llrintl (long double __x) __attribute__ ((__nothrow__));
extern long int lroundl (long double __x) __attribute__ ((__nothrow__)); extern long int __lroundl (long double __x) __attribute__ ((__nothrow__));
extern long long int llroundl (long double __x) __attribute__ ((__nothrow__)); extern long long int __llroundl (long double __x) __attribute__ ((__nothrow__));
extern long double fdiml (long double __x, long double __y) __attribute__ ((__nothrow__)); extern long double __fdiml (long double __x, long double __y) __attribute__ ((__nothrow__));
extern long double fmaxl (long double __x, long double __y) __attribute__ ((__nothrow__)); extern long double __fmaxl (long double __x, long double __y) __attribute__ ((__nothrow__));
extern long double fminl (long double __x, long double __y) __attribute__ ((__nothrow__)); extern long double __fminl (long double __x, long double __y) __attribute__ ((__nothrow__));
extern int __fpclassifyl (long double __value) __attribute__ ((__nothrow__))
     __attribute__ ((__const__));
extern int __signbitl (long double __value) __attribute__ ((__nothrow__))
     __attribute__ ((__const__));
extern long double fmal (long double __x, long double __y, long double __z) __attribute__ ((__nothrow__)); extern long double __fmal (long double __x, long double __y, long double __z) __attribute__ ((__nothrow__));

extern long double scalbl (long double __x, long double __n) __attribute__ ((__nothrow__)); extern long double __scalbl (long double __x, long double __n) __attribute__ ((__nothrow__));
extern int signgam;
enum
  {
    FP_NAN,
    FP_INFINITE,
    FP_ZERO,
    FP_SUBNORMAL,
    FP_NORMAL
  };
typedef enum
{
  _IEEE_ = -1,
  _SVID_,
  _XOPEN_,
  _POSIX_,
  _ISOC_
} _LIB_VERSION_TYPE;
extern _LIB_VERSION_TYPE _LIB_VERSION;
struct exception
  {
    int type;
    char *name;
    double arg1;
    double arg2;
    double retval;
  };
extern int matherr (struct exception *__exc);



struct tm
{
  int tm_sec;
  int tm_min;
  int tm_hour;
  int tm_mday;
  int tm_mon;
  int tm_year;
  int tm_wday;
  int tm_yday;
  int tm_isdst;
  long int tm_gmtoff;
  __const char *tm_zone;
};


struct itimerspec
  {
    struct timespec it_interval;
    struct timespec it_value;
  };
struct sigevent;

extern clock_t clock (void) __attribute__ ((__nothrow__));
extern time_t time (time_t *__timer) __attribute__ ((__nothrow__));
extern double difftime (time_t __time1, time_t __time0)
     __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern time_t mktime (struct tm *__tp) __attribute__ ((__nothrow__));
extern size_t strftime (char *__restrict __s, size_t __maxsize,
   __const char *__restrict __format,
   __const struct tm *__restrict __tp) __attribute__ ((__nothrow__));

extern char *strptime (__const char *__restrict __s,
         __const char *__restrict __fmt, struct tm *__tp)
     __attribute__ ((__nothrow__));
extern size_t strftime_l (char *__restrict __s, size_t __maxsize,
     __const char *__restrict __format,
     __const struct tm *__restrict __tp,
     __locale_t __loc) __attribute__ ((__nothrow__));
extern char *strptime_l (__const char *__restrict __s,
    __const char *__restrict __fmt, struct tm *__tp,
    __locale_t __loc) __attribute__ ((__nothrow__));

extern struct tm *gmtime (__const time_t *__timer) __attribute__ ((__nothrow__));
extern struct tm *localtime (__const time_t *__timer) __attribute__ ((__nothrow__));

extern struct tm *gmtime_r (__const time_t *__restrict __timer,
       struct tm *__restrict __tp) __attribute__ ((__nothrow__));
extern struct tm *localtime_r (__const time_t *__restrict __timer,
          struct tm *__restrict __tp) __attribute__ ((__nothrow__));

extern char *asctime (__const struct tm *__tp) __attribute__ ((__nothrow__));
extern char *ctime (__const time_t *__timer) __attribute__ ((__nothrow__));

extern char *asctime_r (__const struct tm *__restrict __tp,
   char *__restrict __buf) __attribute__ ((__nothrow__));
extern char *ctime_r (__const time_t *__restrict __timer,
        char *__restrict __buf) __attribute__ ((__nothrow__));
extern char *__tzname[2];
extern int __daylight;
extern long int __timezone;
extern char *tzname[2];
extern void tzset (void) __attribute__ ((__nothrow__));
extern int daylight;
extern long int timezone;
extern int stime (__const time_t *__when) __attribute__ ((__nothrow__));
extern time_t timegm (struct tm *__tp) __attribute__ ((__nothrow__));
extern time_t timelocal (struct tm *__tp) __attribute__ ((__nothrow__));
extern int dysize (int __year) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern int nanosleep (__const struct timespec *__requested_time,
        struct timespec *__remaining);
extern int clock_getres (clockid_t __clock_id, struct timespec *__res) __attribute__ ((__nothrow__));
extern int clock_gettime (clockid_t __clock_id, struct timespec *__tp) __attribute__ ((__nothrow__));
extern int clock_settime (clockid_t __clock_id, __const struct timespec *__tp)
     __attribute__ ((__nothrow__));
extern int clock_nanosleep (clockid_t __clock_id, int __flags,
       __const struct timespec *__req,
       struct timespec *__rem);
extern int clock_getcpuclockid (pid_t __pid, clockid_t *__clock_id) __attribute__ ((__nothrow__));
extern int timer_create (clockid_t __clock_id,
    struct sigevent *__restrict __evp,
    timer_t *__restrict __timerid) __attribute__ ((__nothrow__));
extern int timer_delete (timer_t __timerid) __attribute__ ((__nothrow__));
extern int timer_settime (timer_t __timerid, int __flags,
     __const struct itimerspec *__restrict __value,
     struct itimerspec *__restrict __ovalue) __attribute__ ((__nothrow__));
extern int timer_gettime (timer_t __timerid, struct itimerspec *__value)
     __attribute__ ((__nothrow__));
extern int timer_getoverrun (timer_t __timerid) __attribute__ ((__nothrow__));
extern int getdate_err;
extern struct tm *getdate (__const char *__string);
extern int getdate_r (__const char *__restrict __string,
        struct tm *__restrict __resbufp);


struct timezone
  {
    int tz_minuteswest;
    int tz_dsttime;
  };
typedef struct timezone *__restrict __timezone_ptr_t;
extern int gettimeofday (struct timeval *__restrict __tv,
    __timezone_ptr_t __tz) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int settimeofday (__const struct timeval *__tv,
    __const struct timezone *__tz)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int adjtime (__const struct timeval *__delta,
      struct timeval *__olddelta) __attribute__ ((__nothrow__));
enum __itimer_which
  {
    ITIMER_REAL = 0,
    ITIMER_VIRTUAL = 1,
    ITIMER_PROF = 2
  };
struct itimerval
  {
    struct timeval it_interval;
    struct timeval it_value;
  };
typedef enum __itimer_which __itimer_which_t;
extern int getitimer (__itimer_which_t __which,
        struct itimerval *__value) __attribute__ ((__nothrow__));
extern int setitimer (__itimer_which_t __which,
        __const struct itimerval *__restrict __new,
        struct itimerval *__restrict __old) __attribute__ ((__nothrow__));
extern int utimes (__const char *__file, __const struct timeval __tvp[2])
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int lutimes (__const char *__file, __const struct timeval __tvp[2])
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int futimes (int __fd, __const struct timeval __tvp[2]) __attribute__ ((__nothrow__));
extern int futimesat (int __fd, __const char *__file,
        __const struct timeval __tvp[2]) __attribute__ ((__nothrow__));



extern size_t strlcpy(char *, const char*, size_t);
extern size_t strlcat(char *, const char*, size_t);
__attribute__((__format__(__printf__, 1, 2)))
extern void setproctitle(const char *fmt, ...);
extern void explicit_bzero(void *b, size_t len);


typedef unsigned long VALUE;
typedef unsigned long ID;
__extension__ _Static_assert(4 == sizeof(int), "sizeof_int" ": " "SIZEOF_INT == sizeof(int)");
__extension__ _Static_assert(8 == sizeof(long), "sizeof_long" ": " "SIZEOF_LONG == sizeof(long)");
__extension__ _Static_assert(8 == sizeof(long long), "sizeof_long_long" ": " "SIZEOF_LONG_LONG == sizeof(LONG_LONG)");
__extension__ _Static_assert(8 == sizeof(void *), "sizeof_voidp" ": " "SIZEOF_VOIDP == sizeof(void *)");


VALUE rb_class_new(VALUE super);
VALUE rb_mod_init_copy(VALUE clone, VALUE orig);
void rb_check_inheritable(VALUE super);
VALUE rb_define_class_id(ID id, VALUE super);
VALUE rb_define_class_id_under(VALUE outer, ID id, VALUE super);
VALUE rb_module_new(void);
VALUE rb_refinement_new(void);
VALUE rb_define_module_id(ID id);
VALUE rb_define_module_id_under(VALUE outer, ID id);
VALUE rb_mod_included_modules(VALUE mod);
VALUE rb_mod_include_p(VALUE child, VALUE parent);
VALUE rb_mod_ancestors(VALUE mod);
VALUE rb_class_descendants(VALUE klass);
VALUE rb_class_subclasses(VALUE klass);
VALUE rb_class_instance_methods(int argc, const VALUE *argv, VALUE mod);
VALUE rb_class_public_instance_methods(int argc, const VALUE *argv, VALUE mod);
VALUE rb_class_protected_instance_methods(int argc, const VALUE *argv, VALUE mod);
VALUE rb_class_private_instance_methods(int argc, const VALUE *argv, VALUE mod);
VALUE rb_obj_singleton_methods(int argc, const VALUE *argv, VALUE obj);
void rb_define_method_id(VALUE klass, ID mid, VALUE (*func)(), int arity);
void rb_undef(VALUE mod, ID mid);
__attribute__((__nonnull__ ()))
void rb_define_protected_method(VALUE klass, const char *mid, VALUE (*func)(), int arity);
__attribute__((__nonnull__ ()))
void rb_define_private_method(VALUE klass, const char *mid, VALUE (*func)(), int arity);
__attribute__((__nonnull__ ()))
void rb_define_singleton_method(VALUE obj, const char *mid, VALUE(*func)(), int arity);
VALUE rb_singleton_class(VALUE obj);




int rb_sourceline(void);
const char *rb_sourcefile(void);
int rb_frame_method_id_and_class(ID *idp, VALUE *klassp);
VALUE rb_check_funcall(VALUE recv, ID mid, int argc, const VALUE *argv);
VALUE rb_check_funcall_kw(VALUE recv, ID mid, int argc, const VALUE *argv, int kw_splat);
VALUE rb_eval_cmd_kw(VALUE cmd, VALUE arg, int kw_splat);
VALUE rb_apply(VALUE recv, ID mid, VALUE args);
VALUE rb_obj_instance_eval(int argc, const VALUE *argv, VALUE recv);
VALUE rb_obj_instance_exec(int argc, const VALUE *argv, VALUE recv);
VALUE rb_mod_module_eval(int argc, const VALUE *argv, VALUE mod);
VALUE rb_mod_module_exec(int argc, const VALUE *argv, VALUE mod);
typedef VALUE (*rb_alloc_func_t)(VALUE klass);
void rb_define_alloc_func(VALUE klass, rb_alloc_func_t func);
void rb_undef_alloc_func(VALUE klass);
rb_alloc_func_t rb_get_alloc_func(VALUE klass);
void rb_clear_constant_cache(void);
void rb_alias(VALUE klass, ID dst, ID src);
void rb_attr(VALUE klass, ID name, int need_reader, int need_writer, int honour_visibility);
__attribute__((__nonnull__ ()))
void rb_remove_method(VALUE klass, const char *name);
void rb_remove_method_id(VALUE klass, ID mid);
int rb_method_boundp(VALUE klass, ID id, int ex);
int rb_method_basic_definition_p(VALUE klass, ID mid);
int rb_obj_respond_to(VALUE obj, ID mid, int private_p);
int rb_respond_to(VALUE obj, ID mid);
__attribute__((__noreturn__))
VALUE rb_f_notimplement(int argc, const VALUE *argv, VALUE obj, VALUE marker);
void rb_backtrace(void);
VALUE rb_make_backtrace(void);




__attribute__((__nonnull__ ()))
void rb_define_method(VALUE klass, const char *mid, VALUE (*func)(), int arity);
__attribute__((__nonnull__ ()))
void rb_define_module_function(VALUE klass, const char *mid, VALUE (*func)(), int arity);
__attribute__((__nonnull__ ()))
void rb_define_global_function(const char *mid, VALUE (*func)(), int arity);
__attribute__((__nonnull__ ()))
void rb_undef_method(VALUE klass, const char *name);
__attribute__((__nonnull__ ()))
void rb_define_alias(VALUE klass, const char *dst, const char *src);
__attribute__((__nonnull__ ()))
void rb_define_attr(VALUE klass, const char *name, int read, int write);


[[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_m3(VALUE, const char *, VALUE(*)(), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_m2(VALUE, const char *, VALUE(*)(VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_m1(VALUE, const char *, VALUE(*)(int, union { VALUE *x; const VALUE *y; } __attribute__((__transparent_union__)), VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_00(VALUE, const char *, VALUE(*)(VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_01(VALUE, const char *, VALUE(*)(VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_02(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_03(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_04(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_05(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_06(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_07(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_08(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_09(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_10(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_11(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_12(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_13(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_14(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_singleton_method"))) static void rb_define_singleton_method_15(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int);
[[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_m3(VALUE, const char *, VALUE(*)(), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_m2(VALUE, const char *, VALUE(*)(VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_m1(VALUE, const char *, VALUE(*)(int, union { VALUE *x; const VALUE *y; } __attribute__((__transparent_union__)), VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_00(VALUE, const char *, VALUE(*)(VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_01(VALUE, const char *, VALUE(*)(VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_02(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_03(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_04(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_05(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_06(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_07(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_08(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_09(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_10(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_11(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_12(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_13(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_14(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_protected_method"))) static void rb_define_protected_method_15(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int);
[[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_m3(VALUE, const char *, VALUE(*)(), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_m2(VALUE, const char *, VALUE(*)(VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_m1(VALUE, const char *, VALUE(*)(int, union { VALUE *x; const VALUE *y; } __attribute__((__transparent_union__)), VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_00(VALUE, const char *, VALUE(*)(VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_01(VALUE, const char *, VALUE(*)(VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_02(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_03(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_04(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_05(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_06(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_07(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_08(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_09(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_10(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_11(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_12(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_13(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_14(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_private_method"))) static void rb_define_private_method_15(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int);
[[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_m3(VALUE, const char *, VALUE(*)(), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_m2(VALUE, const char *, VALUE(*)(VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_m1(VALUE, const char *, VALUE(*)(int, union { VALUE *x; const VALUE *y; } __attribute__((__transparent_union__)), VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_00(VALUE, const char *, VALUE(*)(VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_01(VALUE, const char *, VALUE(*)(VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_02(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_03(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_04(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_05(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_06(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_07(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_08(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_09(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_10(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_11(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_12(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_13(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_14(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_module_function"))) static void rb_define_module_function_15(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int);
[[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_m3(const char *, VALUE(*)(), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_m2(const char *, VALUE(*)(VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_m1(const char *, VALUE(*)(int, union { VALUE *x; const VALUE *y; } __attribute__((__transparent_union__)), VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_00(const char *, VALUE(*)(VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_01(const char *, VALUE(*)(VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_02(const char *, VALUE(*)(VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_03(const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_04(const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_05(const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_06(const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_07(const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_08(const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_09(const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_10(const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_11(const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_12(const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_13(const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_14(const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_global_function"))) static void rb_define_global_function_15(const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int);
[[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_m3(VALUE, ID, VALUE(*)(), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_m2(VALUE, ID, VALUE(*)(VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_m1(VALUE, ID, VALUE(*)(int, union { VALUE *x; const VALUE *y; } __attribute__((__transparent_union__)), VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_00(VALUE, ID, VALUE(*)(VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_01(VALUE, ID, VALUE(*)(VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_02(VALUE, ID, VALUE(*)(VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_03(VALUE, ID, VALUE(*)(VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_04(VALUE, ID, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_05(VALUE, ID, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_06(VALUE, ID, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_07(VALUE, ID, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_08(VALUE, ID, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_09(VALUE, ID, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_10(VALUE, ID, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_11(VALUE, ID, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_12(VALUE, ID, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_13(VALUE, ID, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_14(VALUE, ID, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method_id"))) static void rb_define_method_id_15(VALUE, ID, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int);
[[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_m3(VALUE, const char *, VALUE(*)(), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_m2(VALUE, const char *, VALUE(*)(VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_m1(VALUE, const char *, VALUE(*)(int, union { VALUE *x; const VALUE *y; } __attribute__((__transparent_union__)), VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_00(VALUE, const char *, VALUE(*)(VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_01(VALUE, const char *, VALUE(*)(VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_02(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_03(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_04(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_05(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_06(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_07(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_08(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_09(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_10(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_11(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_12(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_13(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_14(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); [[maybe_unused]] __attribute__((__nonnull__ ())) __attribute__((__weakref__("rb_define_method"))) static void rb_define_method_15(VALUE, const char *, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int);


VALUE rb_int2big(intptr_t i);
VALUE rb_int2inum(intptr_t i);
VALUE rb_uint2big(uintptr_t i);
VALUE rb_uint2inum(uintptr_t i);


enum

ruby_special_consts {
    RUBY_Qfalse = 0x00,
    RUBY_Qtrue = 0x14,
    RUBY_Qnil = 0x08,
    RUBY_Qundef = 0x34,
    RUBY_IMMEDIATE_MASK = 0x07,
    RUBY_FIXNUM_FLAG = 0x01,
    RUBY_FLONUM_MASK = 0x03,
    RUBY_FLONUM_FLAG = 0x02,
    RUBY_SYMBOL_FLAG = 0x0c,
    RUBY_SPECIAL_SHIFT = 8
};
__attribute__((__const__))

__attribute__((__artificial__))
static inline _Bool
RB_TEST(VALUE obj)
{
    return obj & ~RUBY_Qnil;
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline _Bool
RB_NIL_P(VALUE obj)
{
    return obj == RUBY_Qnil;
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline _Bool
RB_FIXNUM_P(VALUE obj)
{
    return obj & RUBY_FIXNUM_FLAG;
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline _Bool
RB_STATIC_SYM_P(VALUE obj)
{
   
    const VALUE mask = ~((0x7fffffffffffffffL * 2UL + 1UL) << RUBY_SPECIAL_SHIFT);
    return (obj & mask) == RUBY_SYMBOL_FLAG;
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline _Bool
RB_FLONUM_P(VALUE obj)
{
    return (obj & RUBY_FLONUM_MASK) == RUBY_FLONUM_FLAG;
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline _Bool
RB_IMMEDIATE_P(VALUE obj)
{
    return obj & RUBY_IMMEDIATE_MASK;
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline _Bool
RB_SPECIAL_CONST_P(VALUE obj)
{
    return RB_IMMEDIATE_P(obj) || ! RB_TEST(obj);
}
__attribute__((__const__))

static inline VALUE
rb_special_const_p(VALUE obj)
{
    return RB_SPECIAL_CONST_P(obj) * RUBY_Qtrue;
}


__attribute__((__noreturn__))
__attribute__((__cold__))
void rb_out_of_int(long num);
long rb_num2long(VALUE num);
unsigned long rb_num2ulong(VALUE num);


__attribute__((__const__))

__attribute__((__artificial__))
static inline VALUE
RB_INT2FIX(long i)
{
    ((void)0);
    const unsigned long j = i;
    const unsigned long k = 2 * j + RUBY_FIXNUM_FLAG;
    const long l = k;
    const long m = l;
    const VALUE n = m;
    ((void)0);
    return n;
}
static inline int
rb_long2int_inline(long n)
{
    int i = ((int)n);
    if (sizeof(long) <= sizeof(int)) {
        ((__builtin_expect(!!(!!(i == n)), 1)) ? ((void)0) : __builtin_unreachable());
    }
    if (i != n)
        rb_out_of_int(n);
    return i;
}
__attribute__((__const__))

static inline long
rbimpl_fix2long_by_idiv(VALUE x)
{
    ((void)0);
    const long y = x - RUBY_FIXNUM_FLAG;
    const long z = y / 2;
    const long w = ((long)z);
    ((void)0);
    return w;
}
__attribute__((__const__))

static inline long
rbimpl_fix2long_by_shift(VALUE x)
{
    ((void)0);
    const long y = x;
    const long z = y >> 1;
    const long w = ((long)z);
    ((void)0);
    return w;
}
__attribute__((__const__))

static inline _Bool
rbimpl_right_shift_is_arithmetic_p(void)
{
    return (-1 >> 1) == -1;
}
__attribute__((__const__))

static inline long
rb_fix2long(VALUE x)
{
    if (rbimpl_right_shift_is_arithmetic_p()) {
        return rbimpl_fix2long_by_shift(x);
    }
    else {
        return rbimpl_fix2long_by_idiv(x);
    }
}
__attribute__((__const__))

static inline unsigned long
rb_fix2ulong(VALUE x)
{
    ((void)0);
    return rb_fix2long(x);
}
static inline long
rb_num2long_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
        return rb_fix2long(x);
    else
        return rb_num2long(x);
}
static inline unsigned long
rb_num2ulong_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
        return rb_fix2ulong(x);
    else
        return rb_num2ulong(x);
}
static inline VALUE
rb_long2num_inline(long v)
{
    if ((((v) < (0x7fffffffffffffffL / 2) + 1) && ((v) >= ((-0x7fffffffffffffffL - 1L) / 2))))
        return RB_INT2FIX(v);
    else
        return rb_int2big(v);
}
static inline VALUE
rb_ulong2num_inline(unsigned long v)
{
    if (((v) < (0x7fffffffffffffffL / 2) + 1))
        return RB_INT2FIX(v);
    else
        return rb_uint2big(v);
}


long rb_num2int(VALUE num);
long rb_fix2int(VALUE num);
unsigned long rb_num2uint(VALUE num);
unsigned long rb_fix2uint(VALUE num);


__attribute__((__artificial__))
static inline int
RB_FIX2INT(VALUE x)
{
    long ret;
    if (sizeof(int) < sizeof(long)) {
        ret = rb_fix2int(x);
    }
    else {
        ret = rb_fix2long(x);
    }
    return ((int)ret);
}
static inline int
rb_num2int_inline(VALUE x)
{
    long ret;
    if (sizeof(int) == sizeof(long)) {
        ret = rb_num2long_inline(x);
    }
    else if (RB_FIXNUM_P(x)) {
        ret = rb_fix2int(x);
    }
    else {
        ret = rb_num2int(x);
    }
    return ((int)ret);
}
__attribute__((__artificial__))
static inline unsigned int
RB_NUM2UINT(VALUE x)
{
    unsigned long ret;
    if (sizeof(int) < sizeof(long)) {
        ret = rb_num2uint(x);
    }
    else {
        ret = rb_num2ulong_inline(x);
    }
    return ((unsigned int)ret);
}
__attribute__((__artificial__))
static inline unsigned int
RB_FIX2UINT(VALUE x)
{
    unsigned long ret;
    if (sizeof(int) < sizeof(long)) {
        ret = rb_fix2uint(x);
    }
    else {
        ret = rb_fix2ulong(x);
    }
    return ((unsigned int)ret);
}




static inline VALUE
rb_int2num_inline(int v)
{
    if ((((v) < (0x7fffffffffffffffL / 2) + 1) && ((v) >= ((-0x7fffffffffffffffL - 1L) / 2))))
        return RB_INT2FIX(v);
    else
        return rb_int2big(v);
}
static inline VALUE
rb_uint2num_inline(unsigned int v)
{
    if (((v) < (0x7fffffffffffffffL / 2) + 1))
        return RB_INT2FIX(v);
    else
        return rb_uint2big(v);
}


enum ruby_rvalue_flags {
    RVALUE_EMBED_LEN_MAX = 3
};
struct
__attribute__((__aligned__(8)))
RBasic {
    VALUE flags;
    const VALUE klass;
};


VALUE rb_obj_hide(VALUE obj);
VALUE rb_obj_reveal(VALUE obj, VALUE klass);


__attribute__((__pure__))
__attribute__((__artificial__))
static inline VALUE
RBASIC_CLASS(VALUE obj)
{
    ((void)0);
    return ((struct RBasic *)(obj))->klass;
}
typedef enum {
    RB_WARN_CATEGORY_NONE,
    RB_WARN_CATEGORY_DEPRECATED,
    RB_WARN_CATEGORY_EXPERIMENTAL,
    RB_WARN_CATEGORY_ALL_BITS = 0x6
} rb_warning_category_t;
enum rb_io_wait_readwrite {RB_IO_WAIT_READABLE, RB_IO_WAIT_WRITABLE};


VALUE rb_errinfo(void);
void rb_set_errinfo(VALUE err);
__attribute__((__noreturn__))
__attribute__((__nonnull__ (2)))
__attribute__((__format__(__printf__, 2, 3)))
void rb_raise(VALUE exc, const char *fmt, ...);
__attribute__((__noreturn__))
__attribute__((__nonnull__ (1)))
__attribute__((__format__(__printf__, 1, 2)))
void rb_fatal(const char *fmt, ...);
__attribute__((__cold__))
__attribute__((__noreturn__))
__attribute__((__nonnull__ (1)))
__attribute__((__format__(__printf__, 1, 2)))
void rb_bug(const char *fmt, ...);
__attribute__((__noreturn__))
__attribute__((__nonnull__ ()))
void rb_bug_errno(const char *msg, int err);
__attribute__((__noreturn__))
void rb_sys_fail(const char *msg);
__attribute__((__noreturn__))
void rb_sys_fail_str(VALUE msg);
__attribute__((__noreturn__))
__attribute__((__nonnull__ (2)))
void rb_mod_sys_fail(VALUE mod, const char *msg);
__attribute__((__noreturn__))
void rb_mod_sys_fail_str(VALUE mod, VALUE msg);
__attribute__((__noreturn__))
void rb_readwrite_sys_fail(enum rb_io_wait_readwrite waiting, const char *msg);
__attribute__((__noreturn__))
void rb_iter_break(void);
__attribute__((__noreturn__))
void rb_iter_break_value(VALUE val);
__attribute__((__noreturn__))
void rb_exit(int status);
__attribute__((__noreturn__))
void rb_notimplement(void);
VALUE rb_syserr_new(int err, const char * msg);
VALUE rb_syserr_new_str(int n, VALUE arg);
__attribute__((__noreturn__))
void rb_syserr_fail(int err, const char *msg);
__attribute__((__noreturn__))
void rb_syserr_fail_str(int err, VALUE msg);
__attribute__((__noreturn__))
__attribute__((__nonnull__ ()))
void rb_mod_syserr_fail(VALUE mod, int err, const char *msg);
__attribute__((__noreturn__))
void rb_mod_syserr_fail_str(VALUE mod, int err, VALUE msg);
__attribute__((__noreturn__))
void rb_readwrite_syserr_fail(enum rb_io_wait_readwrite waiting, int err, const char *msg);
__attribute__((__cold__))
__attribute__((__noreturn__))
void rb_unexpected_type(VALUE self, int t);
VALUE *rb_ruby_verbose_ptr(void);
VALUE *rb_ruby_debug_ptr(void);
__attribute__((__nonnull__ (1)))
__attribute__((__format__(__printf__, 1, 2)))
void rb_warning(const char *fmt, ...);
__attribute__((__nonnull__ (2)))
__attribute__((__format__(__printf__, 2, 3)))
void rb_category_warning(rb_warning_category_t cat, const char *fmt, ...);
__attribute__((__nonnull__ (1, 3)))
__attribute__((__format__(__printf__, 3, 4)))
void rb_compile_warning(const char *file, int line, const char *fmt, ...);
__attribute__((__nonnull__ (1)))
__attribute__((__format__(__printf__, 1, 2)))
void rb_sys_warning(const char *fmt, ...);
__attribute__((__cold__))
__attribute__((__nonnull__ (1)))
__attribute__((__format__(__printf__, 1, 2)))
void rb_warn(const char *fmt, ...);
__attribute__((__cold__))
__attribute__((__nonnull__ (2)))
__attribute__((__format__(__printf__, 2, 3)))
void rb_category_warn(rb_warning_category_t cat, const char *fmt, ...);
__attribute__((__nonnull__ (1, 3)))
__attribute__((__format__(__printf__, 3, 4)))
void rb_compile_warn(const char *file, int line, const char *fmt, ...);
__attribute__((__nonnull__ (2, 4)))
__attribute__((__format__(__printf__, 4, 5)))
void rb_category_compile_warn(rb_warning_category_t cat, const char *file, int line, const char *fmt, ...);


enum

ruby_value_type {
    RUBY_T_NONE = 0x00,
    RUBY_T_OBJECT = 0x01,
    RUBY_T_CLASS = 0x02,
    RUBY_T_MODULE = 0x03,
    RUBY_T_FLOAT = 0x04,
    RUBY_T_STRING = 0x05,
    RUBY_T_REGEXP = 0x06,
    RUBY_T_ARRAY = 0x07,
    RUBY_T_HASH = 0x08,
    RUBY_T_STRUCT = 0x09,
    RUBY_T_BIGNUM = 0x0a,
    RUBY_T_FILE = 0x0b,
    RUBY_T_DATA = 0x0c,
    RUBY_T_MATCH = 0x0d,
    RUBY_T_COMPLEX = 0x0e,
    RUBY_T_RATIONAL = 0x0f,
    RUBY_T_NIL = 0x11,
    RUBY_T_TRUE = 0x12,
    RUBY_T_FALSE = 0x13,
    RUBY_T_SYMBOL = 0x14,
    RUBY_T_FIXNUM = 0x15,
    RUBY_T_UNDEF = 0x16,
    RUBY_T_IMEMO = 0x1a,
    RUBY_T_NODE = 0x1b,
    RUBY_T_ICLASS = 0x1c,
    RUBY_T_ZOMBIE = 0x1d,
    RUBY_T_MOVED = 0x1e,
    RUBY_T_MASK = 0x1f
};


__attribute__((__cold__))
void rb_check_type(VALUE obj, int t);


__attribute__((__pure__))
__attribute__((__artificial__))
static inline enum ruby_value_type
RB_BUILTIN_TYPE(VALUE obj)
{
    ((void)0);
    VALUE ret = ((struct RBasic *)(obj))->flags & RUBY_T_MASK;
    return ((enum ruby_value_type)ret);
}
__attribute__((__pure__))
static inline _Bool
rb_integer_type_p(VALUE obj)
{
    if (RB_FIXNUM_P(obj)) {
        return 1;
    }
    else if (RB_SPECIAL_CONST_P(obj)) {
        return 0;
    }
    else {
        return RB_BUILTIN_TYPE(obj) == RUBY_T_BIGNUM;
    }
}
__attribute__((__pure__))
static inline enum ruby_value_type
rb_type(VALUE obj)
{
    if (! RB_SPECIAL_CONST_P(obj)) {
        return RB_BUILTIN_TYPE(obj);
    }
    else if (obj == ((VALUE)RUBY_Qfalse)) {
        return RUBY_T_FALSE;
    }
    else if (obj == ((VALUE)RUBY_Qnil)) {
        return RUBY_T_NIL;
    }
    else if (obj == ((VALUE)RUBY_Qtrue)) {
        return RUBY_T_TRUE;
    }
    else if (obj == ((VALUE)RUBY_Qundef)) {
        return RUBY_T_UNDEF;
    }
    else if (RB_FIXNUM_P(obj)) {
        return RUBY_T_FIXNUM;
    }
    else if (RB_STATIC_SYM_P(obj)) {
        return RUBY_T_SYMBOL;
    }
    else {
        ((__builtin_expect(!!(!!(RB_FLONUM_P(obj))), 1)) ? ((void)0) : __builtin_unreachable());
        return RUBY_T_FLOAT;
    }
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline _Bool
RB_FLOAT_TYPE_P(VALUE obj)
{
    if (RB_FLONUM_P(obj)) {
        return 1;
    }
    else if (RB_SPECIAL_CONST_P(obj)) {
        return 0;
    }
    else {
        return RB_BUILTIN_TYPE(obj) == RUBY_T_FLOAT;
    }
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline _Bool
RB_DYNAMIC_SYM_P(VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) {
        return 0;
    }
    else {
        return RB_BUILTIN_TYPE(obj) == RUBY_T_SYMBOL;
    }
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline _Bool
RB_SYMBOL_P(VALUE obj)
{
    return RB_STATIC_SYM_P(obj) || RB_DYNAMIC_SYM_P(obj);
}
__attribute__((__pure__))
__attribute__((__artificial__))
__attribute__((__always_inline__)) inline
static _Bool
rbimpl_RB_TYPE_P_fastpath(VALUE obj, enum ruby_value_type t)
{
    if (t == RUBY_T_TRUE) {
        return obj == ((VALUE)RUBY_Qtrue);
    }
    else if (t == RUBY_T_FALSE) {
        return obj == ((VALUE)RUBY_Qfalse);
    }
    else if (t == RUBY_T_NIL) {
        return obj == ((VALUE)RUBY_Qnil);
    }
    else if (t == RUBY_T_UNDEF) {
        return obj == ((VALUE)RUBY_Qundef);
    }
    else if (t == RUBY_T_FIXNUM) {
        return RB_FIXNUM_P(obj);
    }
    else if (t == RUBY_T_SYMBOL) {
        return RB_SYMBOL_P(obj);
    }
    else if (t == RUBY_T_FLOAT) {
        return RB_FLOAT_TYPE_P(obj);
    }
    else if (RB_SPECIAL_CONST_P(obj)) {
        return 0;
    }
    else if (t == RB_BUILTIN_TYPE(obj)) {
        return 1;
    }
    else {
        return 0;
    }
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline _Bool
RB_TYPE_P(VALUE obj, enum ruby_value_type t)
{
    if (__builtin_constant_p(t)) {
        return rbimpl_RB_TYPE_P_fastpath(obj, t);
    }
    else {
        return t == rb_type(obj);
    }
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline _Bool rbimpl_rtypeddata_p(VALUE obj);
__attribute__((__artificial__))
static inline void
Check_Type(VALUE v, enum ruby_value_type t)
{
    if ((__builtin_expect(!!(! RB_TYPE_P(v, t)), 0))) {
        goto unexpected_type;
    }
    else if (t == RUBY_T_DATA && rbimpl_rtypeddata_p(v)) {
        goto unexpected_type;
    }
    else {
        return;
    }
  unexpected_type:
    rb_unexpected_type(v, t);
}
enum ruby_fl_ushift {
    RUBY_FL_USHIFT = 12
};
__extension__
enum

ruby_fl_type {
    RUBY_FL_WB_PROTECTED = (1<<5),
    RUBY_FL_PROMOTED0 = (1<<5),
    RUBY_FL_PROMOTED1 = (1<<6),
    RUBY_FL_PROMOTED = RUBY_FL_PROMOTED0 | RUBY_FL_PROMOTED1,
    RUBY_FL_FINALIZE = (1<<7),
    RUBY_FL_TAINT
    __attribute__((__deprecated__ ("taintedness turned out to be a wrong idea.")))
                         = (1<<8),
    RUBY_FL_SHAREABLE = (1<<8),
    RUBY_FL_UNTRUSTED
    __attribute__((__deprecated__ ("trustedness turned out to be a wrong idea.")))
                         = (1<<8),
    RUBY_FL_SEEN_OBJ_ID = (1<<9),
    RUBY_FL_EXIVAR = (1<<10),
    RUBY_FL_FREEZE = (1<<11),
    RUBY_FL_USER0 = (1<<(RUBY_FL_USHIFT+0)),
    RUBY_FL_USER1 = (1<<(RUBY_FL_USHIFT+1)),
    RUBY_FL_USER2 = (1<<(RUBY_FL_USHIFT+2)),
    RUBY_FL_USER3 = (1<<(RUBY_FL_USHIFT+3)),
    RUBY_FL_USER4 = (1<<(RUBY_FL_USHIFT+4)),
    RUBY_FL_USER5 = (1<<(RUBY_FL_USHIFT+5)),
    RUBY_FL_USER6 = (1<<(RUBY_FL_USHIFT+6)),
    RUBY_FL_USER7 = (1<<(RUBY_FL_USHIFT+7)),
    RUBY_FL_USER8 = (1<<(RUBY_FL_USHIFT+8)),
    RUBY_FL_USER9 = (1<<(RUBY_FL_USHIFT+9)),
    RUBY_FL_USER10 = (1<<(RUBY_FL_USHIFT+10)),
    RUBY_FL_USER11 = (1<<(RUBY_FL_USHIFT+11)),
    RUBY_FL_USER12 = (1<<(RUBY_FL_USHIFT+12)),
    RUBY_FL_USER13 = (1<<(RUBY_FL_USHIFT+13)),
    RUBY_FL_USER14 = (1<<(RUBY_FL_USHIFT+14)),
    RUBY_FL_USER15 = (1<<(RUBY_FL_USHIFT+15)),
    RUBY_FL_USER16 = (1<<(RUBY_FL_USHIFT+16)),
    RUBY_FL_USER17 = (1<<(RUBY_FL_USHIFT+17)),
    RUBY_FL_USER18 = (1<<(RUBY_FL_USHIFT+18)),
    RUBY_FL_USER19 = (1<<(RUBY_FL_USHIFT+19)),
    RUBY_ELTS_SHARED = RUBY_FL_USER2,
    RUBY_FL_SINGLETON = RUBY_FL_USER0,
};
enum {
    RUBY_FL_DUPPED
    __attribute__((__deprecated__ ("It seems there is no actual usage of this enum.")))
    = (int)RUBY_T_MASK | (int)RUBY_FL_EXIVAR
};


void rb_obj_infect(VALUE victim, VALUE carrier);
void rb_freeze_singleton_class(VALUE klass);


__attribute__((__pure__))
__attribute__((__artificial__))
__attribute__((__always_inline__)) inline
static _Bool
RB_FL_ABLE(VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) {
        return 0;
    }
    else if (RB_TYPE_P(obj, RUBY_T_NODE)) {
        return 0;
    }
    else {
        return 1;
    }
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline VALUE
RB_FL_TEST_RAW(VALUE obj, VALUE flags)
{
    ((void)0);
    return ((struct RBasic *)(obj))->flags & flags;
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline VALUE
RB_FL_TEST(VALUE obj, VALUE flags)
{
    if (RB_FL_ABLE(obj)) {
        return RB_FL_TEST_RAW(obj, flags);
    }
    else {
        return 0UL;
    }
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline _Bool
RB_FL_ANY_RAW(VALUE obj, VALUE flags)
{
    return RB_FL_TEST_RAW(obj, flags);
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline _Bool
RB_FL_ANY(VALUE obj, VALUE flags)
{
    return RB_FL_TEST(obj, flags);
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline _Bool
RB_FL_ALL_RAW(VALUE obj, VALUE flags)
{
    return RB_FL_TEST_RAW(obj, flags) == flags;
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline _Bool
RB_FL_ALL(VALUE obj, VALUE flags)
{
    return RB_FL_TEST(obj, flags) == flags;
}

__attribute__((__artificial__))
static inline void
rbimpl_fl_set_raw_raw(struct RBasic *obj, VALUE flags)
{
    obj->flags |= flags;
}
__attribute__((__artificial__))
static inline void
RB_FL_SET_RAW(VALUE obj, VALUE flags)
{
    ((void)0);
    rbimpl_fl_set_raw_raw(((struct RBasic *)(obj)), flags);
}
__attribute__((__artificial__))
static inline void
RB_FL_SET(VALUE obj, VALUE flags)
{
    if (RB_FL_ABLE(obj)) {
        RB_FL_SET_RAW(obj, flags);
    }
}

__attribute__((__artificial__))
static inline void
rbimpl_fl_unset_raw_raw(struct RBasic *obj, VALUE flags)
{
    obj->flags &= ~flags;
}
__attribute__((__artificial__))
static inline void
RB_FL_UNSET_RAW(VALUE obj, VALUE flags)
{
    ((void)0);
    rbimpl_fl_unset_raw_raw(((struct RBasic *)(obj)), flags);
}
__attribute__((__artificial__))
static inline void
RB_FL_UNSET(VALUE obj, VALUE flags)
{
    if (RB_FL_ABLE(obj)) {
        RB_FL_UNSET_RAW(obj, flags);
    }
}

__attribute__((__artificial__))
static inline void
rbimpl_fl_reverse_raw_raw(struct RBasic *obj, VALUE flags)
{
    obj->flags ^= flags;
}
__attribute__((__artificial__))
static inline void
RB_FL_REVERSE_RAW(VALUE obj, VALUE flags)
{
    ((void)0);
    rbimpl_fl_reverse_raw_raw(((struct RBasic *)(obj)), flags);
}
__attribute__((__artificial__))
static inline void
RB_FL_REVERSE(VALUE obj, VALUE flags)
{
    if (RB_FL_ABLE(obj)) {
        RB_FL_REVERSE_RAW(obj, flags);
    }
}
__attribute__((__pure__))
__attribute__((__artificial__))
__attribute__((__deprecated__ ("taintedness turned out to be a wrong idea.")))
static inline _Bool
RB_OBJ_TAINTABLE(VALUE obj)
{
    return 0;
}
__attribute__((__pure__))
__attribute__((__artificial__))
__attribute__((__deprecated__ ("taintedness turned out to be a wrong idea.")))
static inline VALUE
RB_OBJ_TAINTED_RAW(VALUE obj)
{
    return 0;
}
__attribute__((__pure__))
__attribute__((__artificial__))
__attribute__((__deprecated__ ("taintedness turned out to be a wrong idea.")))
static inline _Bool
RB_OBJ_TAINTED(VALUE obj)
{
    return 0;
}
__attribute__((__artificial__))
__attribute__((__deprecated__ ("taintedness turned out to be a wrong idea.")))
static inline void
RB_OBJ_TAINT_RAW(VALUE obj)
{
    return;
}
__attribute__((__artificial__))
__attribute__((__deprecated__ ("taintedness turned out to be a wrong idea.")))
static inline void
RB_OBJ_TAINT(VALUE obj)
{
    return;
}
__attribute__((__artificial__))
__attribute__((__deprecated__ ("taintedness turned out to be a wrong idea.")))
static inline void
RB_OBJ_INFECT_RAW(VALUE dst, VALUE src)
{
    return;
}
__attribute__((__artificial__))
__attribute__((__deprecated__ ("taintedness turned out to be a wrong idea.")))
static inline void
RB_OBJ_INFECT(VALUE dst, VALUE src)
{
    return;
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline VALUE
RB_OBJ_FROZEN_RAW(VALUE obj)
{
    return RB_FL_TEST_RAW(obj, RUBY_FL_FREEZE);
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline _Bool
RB_OBJ_FROZEN(VALUE obj)
{
    if (! RB_FL_ABLE(obj)) {
        return 1;
    }
    else {
        return RB_OBJ_FROZEN_RAW(obj);
    }
}
__attribute__((__artificial__))
static inline void
RB_OBJ_FREEZE_RAW(VALUE obj)
{
    RB_FL_SET_RAW(obj, RUBY_FL_FREEZE);
}
static inline void
rb_obj_freeze_inline(VALUE x)
{
    if (RB_FL_ABLE(x)) {
        RB_OBJ_FREEZE_RAW(x);
        if (RBASIC_CLASS(x) && !(((struct RBasic *)(x))->flags & RUBY_FL_SINGLETON)) {
            rb_freeze_singleton_class(x);
        }
    }
}
enum ruby_rstring_flags {
    RSTRING_NOEMBED = RUBY_FL_USER1,
    RSTRING_EMBED_LEN_MASK = RUBY_FL_USER2 | RUBY_FL_USER3 | RUBY_FL_USER4 |
                              RUBY_FL_USER5 | RUBY_FL_USER6,
    RSTRING_FSTR = RUBY_FL_USER17
};
enum ruby_rstring_consts {
    RSTRING_EMBED_LEN_SHIFT = RUBY_FL_USHIFT + 2,
    RSTRING_EMBED_LEN_MAX = ((int)(sizeof(VALUE[3]) / (sizeof(char)))) - 1
};
struct RString {
    struct RBasic basic;
    union {
        struct {
            long len;
            char *ptr;
            union {
                long capa;
                VALUE shared;
            } aux;
        } heap;
        struct {
            char ary[RSTRING_EMBED_LEN_MAX + 1];
        } embed;
    } as;
};


VALUE rb_str_to_str(VALUE obj);
VALUE rb_string_value(volatile VALUE *ptr);
char *rb_string_value_ptr(volatile VALUE *ptr);
char *rb_string_value_cstr(volatile VALUE *ptr);
VALUE rb_str_export(VALUE obj);
VALUE rb_str_export_locale(VALUE obj);
__attribute__((__error__ ("rb_check_safe_str() and Check_SafeStr() are obsolete; use StringValue() instead")))
void rb_check_safe_str(VALUE);
void rb_debug_rstring_null_ptr(const char *func);


__attribute__((__pure__))
__attribute__((__artificial__))
static inline long
RSTRING_EMBED_LEN(VALUE str)
{
    ((void)0);
    ((void)0);
    VALUE f = ((struct RBasic *)(str))->flags;
    f &= RSTRING_EMBED_LEN_MASK;
    f >>= RSTRING_EMBED_LEN_SHIFT;
    return ((long)f);
}


__attribute__((__pure__))
__attribute__((__artificial__))
static inline struct RString
rbimpl_rstring_getmem(VALUE str)
{
    ((void)0);
    if (RB_FL_ANY_RAW(str, RSTRING_NOEMBED)) {
        return *((struct RString *)(str));
    }
    else {
        struct RString retval;
        retval.as.heap.len = RSTRING_EMBED_LEN(str);
        retval.as.heap.ptr = ((struct RString *)(str))->as.embed.ary;
        return retval;
    }
}


__attribute__((__pure__))
__attribute__((__artificial__))
static inline long
RSTRING_LEN(VALUE str)
{
    return rbimpl_rstring_getmem(str).as.heap.len;
}
__attribute__((__artificial__))
static inline char *
RSTRING_PTR(VALUE str)
{
    char *ptr = rbimpl_rstring_getmem(str).as.heap.ptr;
    if ((__builtin_expect(!!(! ptr), 0))) {
        rb_debug_rstring_null_ptr("RSTRING_PTR");
    }
    return ptr;
}
__attribute__((__artificial__))
static inline char *
RSTRING_END(VALUE str)
{
    struct RString buf = rbimpl_rstring_getmem(str);
    if ((__builtin_expect(!!(! buf.as.heap.ptr), 0))) {
        rb_debug_rstring_null_ptr("RSTRING_END");
    }
    return &buf.as.heap.ptr[buf.as.heap.len];
}
__attribute__((__artificial__))
static inline int
RSTRING_LENINT(VALUE str)
{
    return rb_long2int_inline(RSTRING_LEN(str));
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline VALUE
RB_CHR2FIX(unsigned char c)
{
    return RB_INT2FIX(c);
}
static inline char
rb_num2char_inline(VALUE x)
{
    if (RB_TYPE_P(x, RUBY_T_STRING) && (RSTRING_LEN(x)>=1))
        return RSTRING_PTR(x)[0];
    else
        return ((char)rb_num2int_inline(x));
}


double rb_num2dbl(VALUE num);
__attribute__((__pure__))
double rb_float_value(VALUE num);
VALUE rb_float_new(double d);
VALUE rb_float_new_in_heap(double d);




VALUE rb_ll2inum(long long num);
VALUE rb_ull2inum(unsigned long long num);
long long rb_num2ll(VALUE num);
unsigned long long rb_num2ull(VALUE num);


static inline VALUE
rb_ll2num_inline(long long n)
{
    if ((((n) < (0x7fffffffffffffffL / 2) + 1) && ((n) >= ((-0x7fffffffffffffffL - 1L) / 2)))) return RB_INT2FIX((long)n);
    return rb_ll2inum(n);
}
static inline VALUE
rb_ull2num_inline(unsigned long long n)
{
    if (((n) < (0x7fffffffffffffffL / 2) + 1)) return RB_INT2FIX((long)n);
    return rb_ull2inum(n);
}
static inline long long
rb_num2ll_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
        return rb_fix2long(x);
    else
        return rb_num2ll(x);
}
static inline unsigned long long
rb_num2ull_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
        return rb_fix2long(x);
    else
        return rb_num2ull(x);
}


short rb_num2short(VALUE num);
unsigned short rb_num2ushort(VALUE num);
short rb_fix2short(VALUE num);
unsigned short rb_fix2ushort(VALUE num);


static inline short
rb_num2short_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
        return rb_fix2short(x);
    else
        return rb_num2short(x);
}


typedef unsigned long st_data_t;
typedef struct st_table st_table;
typedef st_data_t st_index_t;
typedef int st_compare_func(st_data_t, st_data_t);
typedef st_index_t st_hash_func(st_data_t);
typedef char st_check_for_sizeof_st_index_t[8 == (int)sizeof(st_index_t) ? 1 : -1];
struct st_hash_type {
    int (*compare)(st_data_t, st_data_t);
    st_index_t (*hash)(st_data_t);
};
typedef struct st_table_entry st_table_entry;
struct st_table_entry;
struct st_table {
    unsigned char entry_power, bin_power, size_ind;
    unsigned int rebuilds_num;
    const struct st_hash_type *type;
    st_index_t num_entries;
    st_index_t *bins;
    st_index_t entries_start, entries_bound;
    st_table_entry *entries;
};
enum st_retval {ST_CONTINUE, ST_STOP, ST_DELETE, ST_CHECK, ST_REPLACE};
st_table *rb_st_init_table(const struct st_hash_type *);
st_table *rb_st_init_table_with_size(const struct st_hash_type *, st_index_t);
st_table *rb_st_init_numtable(void);
st_table *rb_st_init_numtable_with_size(st_index_t);
st_table *rb_st_init_strtable(void);
st_table *rb_st_init_strtable_with_size(st_index_t);
st_table *rb_st_init_strcasetable(void);
st_table *rb_st_init_strcasetable_with_size(st_index_t);
int rb_st_delete(st_table *, st_data_t *, st_data_t *);
int rb_st_delete_safe(st_table *, st_data_t *, st_data_t *, st_data_t);
int rb_st_shift(st_table *, st_data_t *, st_data_t *);
int rb_st_insert(st_table *, st_data_t, st_data_t);
int rb_st_insert2(st_table *, st_data_t, st_data_t, st_data_t (*)(st_data_t));
int rb_st_lookup(st_table *, st_data_t, st_data_t *);
int rb_st_get_key(st_table *, st_data_t, st_data_t *);
typedef int st_update_callback_func(st_data_t *key, st_data_t *value, st_data_t arg, int existing);
int rb_st_update(st_table *table, st_data_t key, st_update_callback_func *func, st_data_t arg);
typedef int st_foreach_callback_func(st_data_t, st_data_t, st_data_t);
typedef int st_foreach_check_callback_func(st_data_t, st_data_t, st_data_t, int);
int rb_st_foreach_with_replace(st_table *tab, st_foreach_check_callback_func *func, st_update_callback_func *replace, st_data_t arg);
int rb_st_foreach(st_table *, st_foreach_callback_func *, st_data_t);
int rb_st_foreach_check(st_table *, st_foreach_check_callback_func *, st_data_t, st_data_t);
st_index_t rb_st_keys(st_table *table, st_data_t *keys, st_index_t size);
st_index_t rb_st_keys_check(st_table *table, st_data_t *keys, st_index_t size, st_data_t never);
st_index_t rb_st_values(st_table *table, st_data_t *values, st_index_t size);
st_index_t rb_st_values_check(st_table *table, st_data_t *values, st_index_t size, st_data_t never);
void rb_st_add_direct(st_table *, st_data_t, st_data_t);
void rb_st_free_table(st_table *);
void rb_st_cleanup_safe(st_table *, st_data_t);
void rb_st_clear(st_table *);
st_table *rb_st_copy(st_table *);
__attribute__((__const__)) int rb_st_numcmp(st_data_t, st_data_t);
__attribute__((__const__)) st_index_t rb_st_numhash(st_data_t);
__attribute__((__pure__)) int rb_st_locale_insensitive_strcasecmp(const char *s1, const char *s2);
__attribute__((__pure__)) int rb_st_locale_insensitive_strncasecmp(const char *s1, const char *s2, size_t n);
__attribute__((__pure__)) size_t rb_st_memsize(const st_table *);
__attribute__((__pure__)) st_index_t rb_st_hash(const void *ptr, size_t len, st_index_t h);
__attribute__((__const__)) st_index_t rb_st_hash_uint32(st_index_t h, uint32_t i);
__attribute__((__const__)) st_index_t rb_st_hash_uint(st_index_t h, st_index_t i);
__attribute__((__const__)) st_index_t rb_st_hash_end(st_index_t h);
__attribute__((__const__)) st_index_t rb_st_hash_start(st_index_t h);
void rb_hash_bulk_insert_into_st_table(long, const VALUE *, VALUE);


__attribute__((__const__))

__attribute__((__artificial__))
static inline VALUE
RB_ST2FIX(st_data_t i)
{
    long x = i;
    if (x >= 0) {
        x &= (0x7fffffffffffffffL / 2);
    }
    else {
        x |= ((-0x7fffffffffffffffL - 1L) / 2);
    }
    ((void)0);
    unsigned long y = ((unsigned long)x);
    return RB_INT2FIX(y);
}


void rb_gc_writebarrier(VALUE old, VALUE young);
void rb_gc_writebarrier_unprotect(VALUE obj);


__attribute__((__pure__))
__attribute__((__artificial__))
static inline _Bool
RB_OBJ_PROMOTED_RAW(VALUE obj)
{
    ((void)0);
    return RB_FL_ANY_RAW(obj, RUBY_FL_PROMOTED);
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline _Bool
RB_OBJ_PROMOTED(VALUE obj)
{
    if (! RB_FL_ABLE(obj)) {
        return 0;
    }
    else {
        return RB_OBJ_PROMOTED_RAW(obj);
    }
}
static inline VALUE
rb_obj_wb_unprotect(
    VALUE x,
    [[maybe_unused]]
    const char *filename,
    [[maybe_unused]]
    int line)
{
    rb_gc_writebarrier_unprotect(x);
    return x;
}
static inline VALUE
rb_obj_written(
    VALUE a,
    [[maybe_unused]]
    VALUE oldv,
    VALUE b,
    [[maybe_unused]]
    const char *filename,
    [[maybe_unused]]
    int line)
{
    if (!RB_SPECIAL_CONST_P(b)) {
        rb_gc_writebarrier(a, b);
    }
    return a;
}
static inline VALUE
rb_obj_write(
    VALUE a, VALUE *slot, VALUE b,
    [[maybe_unused]]
    const char *filename,
    [[maybe_unused]]
    int line)
{
    *slot = b;
    rb_obj_written(a, ((VALUE)RUBY_Qundef) , b, filename, line);
    return a;
}
enum ruby_rarray_flags {
    RARRAY_EMBED_FLAG = RUBY_FL_USER1,
    RARRAY_EMBED_LEN_MASK = RUBY_FL_USER4 | RUBY_FL_USER3
    ,
    RARRAY_TRANSIENT_FLAG = RUBY_FL_USER13
};
enum ruby_rarray_consts {
    RARRAY_EMBED_LEN_SHIFT = RUBY_FL_USHIFT + 3,
    RARRAY_EMBED_LEN_MAX = ((int)(sizeof(VALUE[3]) / (sizeof(VALUE))))
};
struct RArray {
    struct RBasic basic;
    union {
        struct {
            long len;
            union {
                long capa;
                const
                VALUE shared_root;
            } aux;
            const VALUE *ptr;
        } heap;
        const VALUE ary[RARRAY_EMBED_LEN_MAX];
    } as;
};


VALUE *rb_ary_ptr_use_start(VALUE ary);
void rb_ary_ptr_use_end(VALUE a);
void rb_ary_detransient(VALUE a);


__attribute__((__pure__))
__attribute__((__artificial__))
static inline long
RARRAY_EMBED_LEN(VALUE ary)
{
    ((void)0);
    ((void)0);
    VALUE f = ((struct RBasic *)(ary))->flags;
    f &= RARRAY_EMBED_LEN_MASK;
    f >>= RARRAY_EMBED_LEN_SHIFT;
    return ((long)f);
}
__attribute__((__pure__))
static inline long
rb_array_len(VALUE a)
{
    ((void)0);
    if (RB_FL_ANY_RAW(a, RARRAY_EMBED_FLAG)) {
        return RARRAY_EMBED_LEN(a);
    }
    else {
        return ((struct RArray *)(a))->as.heap.len;
    }
}
__attribute__((__artificial__))
static inline int
RARRAY_LENINT(VALUE ary)
{
    return rb_long2int_inline(rb_array_len(ary));
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline _Bool
RARRAY_TRANSIENT_P(VALUE ary)
{
    ((void)0);
    return RB_FL_ANY_RAW(ary, RARRAY_TRANSIENT_FLAG);
}
__attribute__((__pure__))
static inline const VALUE *
rb_array_const_ptr_transient(VALUE a)
{
    ((void)0);
    if (RB_FL_ANY_RAW(a, RARRAY_EMBED_FLAG)) {
        return (((struct RArray *)(a))->as.ary);
    }
    else {
        return (((struct RArray *)(a))->as.heap.ptr);
    }
}
static inline const VALUE *
rb_array_const_ptr(VALUE a)
{
    ((void)0);
    if (RARRAY_TRANSIENT_P(a)) {
        rb_ary_detransient(a);
    }
    return rb_array_const_ptr_transient(a);
}
static inline VALUE *
rb_array_ptr_use_start(VALUE a,
                       [[maybe_unused]]
                       int allow_transient)
{
    ((void)0);
    if (!allow_transient) {
        if (RARRAY_TRANSIENT_P(a)) {
            rb_ary_detransient(a);
        }
    }
    return rb_ary_ptr_use_start(a);
}
static inline void
rb_array_ptr_use_end(VALUE a,
                     [[maybe_unused]]
                     int allow_transient)
{
    ((void)0);
    rb_ary_ptr_use_end(a);
}
static inline VALUE *
RARRAY_PTR(VALUE ary)
{
    ((void)0);
    VALUE tmp = (1 ? rb_obj_wb_unprotect(ary, "./include/ruby/internal/core/rarray.h", 555) : ary);
    return ((VALUE *)rb_array_const_ptr(tmp));
}
static inline void
RARRAY_ASET(VALUE ary, long i, VALUE v)
{
    do { ((void)0); const VALUE rbimpl_ary = (ary); VALUE *ptr = rb_array_ptr_use_start(rbimpl_ary, (1)); (rb_obj_write((VALUE)(ary), (VALUE *)(&ptr[i]), (VALUE)(v), "./include/ruby/internal/core/rarray.h", 574)); rb_array_ptr_use_end(rbimpl_ary, (1)); } while (0);
}


int rb_big_sign(VALUE num);


static inline _Bool
RBIGNUM_POSITIVE_P(VALUE b)
{
    ((void)0);
    return rb_big_sign(b);
}
static inline _Bool
RBIGNUM_NEGATIVE_P(VALUE b)
{
    ((void)0);
    return ! RBIGNUM_POSITIVE_P(b);
}
enum ruby_rmodule_flags {
    RMODULE_IS_OVERLAID = RUBY_FL_USER2,
    RMODULE_IS_REFINEMENT = RUBY_FL_USER3,
    RMODULE_INCLUDED_INTO_REFINEMENT = RUBY_FL_USER4
};
struct RClass;


VALUE rb_class_get_superclass(VALUE klass);


typedef void (*RUBY_DATA_FUNC)(void*);
struct RData {
    struct RBasic basic;
    RUBY_DATA_FUNC dmark;
    RUBY_DATA_FUNC dfree;
    void *data;
};


VALUE rb_data_object_wrap(VALUE klass, void *datap, RUBY_DATA_FUNC dmark, RUBY_DATA_FUNC dfree);
VALUE rb_data_object_zalloc(VALUE klass, size_t size, RUBY_DATA_FUNC dmark, RUBY_DATA_FUNC dfree);
extern VALUE rb_cObject;


__attribute__((__warning__ ("untyped Data is unsafe; use TypedData instead"))) __attribute__((__deprecated__ ("by TypedData")))
static inline VALUE
rb_data_object_wrap_warning(VALUE klass, void *ptr, RUBY_DATA_FUNC mark, RUBY_DATA_FUNC free)
{
    return rb_data_object_wrap(klass, ptr, mark, free);
}
static inline void *
rb_data_object_get(VALUE obj)
{
    Check_Type(obj, RUBY_T_DATA);
    return ((struct RData *)(obj))->data;
}
__attribute__((__warning__ ("untyped Data is unsafe; use TypedData instead"))) __attribute__((__deprecated__ ("by TypedData")))
static inline void *
rb_data_object_get_warning(VALUE obj)
{
    return rb_data_object_get(obj);
}
static inline VALUE
rb_data_object_make(VALUE klass, RUBY_DATA_FUNC mark_func, RUBY_DATA_FUNC free_func, void **datap, size_t size)
{
    VALUE result = rb_data_object_zalloc( (klass), (size), ((void (*)(void *))(mark_func)), ((void (*)(void *))(free_func))); (*datap) = ((void *)((struct RData *)(result))->data); ((void)(*datap));
    return result;
}
__attribute__((__deprecated__ ("by: rb_data_object_wrap")))
static inline VALUE
rb_data_object_alloc(VALUE klass, void *data, RUBY_DATA_FUNC dmark, RUBY_DATA_FUNC dfree)
{
    return rb_data_object_wrap(klass, data, dmark, dfree);
}
__attribute__((__deprecated__ ("by: rb_cObject.  Will be removed in 3.1.")))
__attribute__((__pure__))
static inline VALUE
rb_cData(void)
{
    return rb_cObject;
}
struct rb_io_t;
struct RFile {
    struct RBasic basic;
    struct rb_io_t *fptr;
};
struct st_table;


size_t rb_hash_size_num(VALUE hash);
struct st_table *rb_hash_tbl(VALUE hash, const char *file, int line);
VALUE rb_hash_set_ifnone(VALUE hash, VALUE ifnone);


enum ruby_robject_flags {
    ROBJECT_EMBED = RUBY_FL_USER1
};
enum ruby_robject_consts {
    ROBJECT_EMBED_LEN_MAX = ((int)(sizeof(VALUE[3]) / (sizeof(VALUE))))
};
struct st_table;
struct RObject {
    struct RBasic basic;
    union {
        struct {
            uint32_t numiv;
            VALUE *ivptr;
            struct st_table *iv_index_tbl;
        } heap;
        VALUE ary[ROBJECT_EMBED_LEN_MAX];
    } as;
};
__attribute__((__pure__))
__attribute__((__artificial__))
static inline uint32_t
ROBJECT_NUMIV(VALUE obj)
{
    ((void)0);
    if (RB_FL_ANY_RAW(obj, ROBJECT_EMBED)) {
        return ROBJECT_EMBED_LEN_MAX;
    }
    else {
        return ((struct RObject *)(obj))->as.heap.numiv;
    }
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline VALUE *
ROBJECT_IVPTR(VALUE obj)
{
    ((void)0);
    struct RObject *const ptr = ((struct RObject *)(obj));
    if (RB_FL_ANY_RAW(obj, ROBJECT_EMBED)) {
        return ptr->as.ary;
    }
    else {
        return ptr->as.heap.ivptr;
    }
}
struct re_patter_buffer;
struct RRegexp {
    struct RBasic basic;
    struct re_pattern_buffer *ptr;
    const VALUE src;
    unsigned long usecnt;
};
__attribute__((__pure__))
__attribute__((__artificial__))
static inline VALUE
RREGEXP_SRC(VALUE rexp)
{
    ((void)0);
    VALUE ret = ((struct RRegexp *)(rexp))->src;
    ((void)0);
    return ret;
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline char *
RREGEXP_SRC_PTR(VALUE rexp)
{
    return RSTRING_PTR(RREGEXP_SRC(rexp));
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline long
RREGEXP_SRC_LEN(VALUE rexp)
{
    return RSTRING_LEN(RREGEXP_SRC(rexp));
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline char *
RREGEXP_SRC_END(VALUE rexp)
{
    return RSTRING_END(RREGEXP_SRC(rexp));
}


VALUE rb_struct_size(VALUE st);
VALUE rb_struct_aref(VALUE st, VALUE k);
VALUE rb_struct_aset(VALUE st, VALUE k, VALUE v);


__attribute__((__artificial__))
static inline long
RSTRUCT_LEN(VALUE st)
{
    ((void)0);
    return rb_num2long_inline(rb_struct_size(st));
}
__attribute__((__artificial__))
static inline VALUE
RSTRUCT_SET(VALUE st, int k, VALUE v)
{
    ((void)0);
    return rb_struct_aset(st, rb_int2num_inline(k), (v));
}
__attribute__((__artificial__))
static inline VALUE
RSTRUCT_GET(VALUE st, int k)
{
    ((void)0);
    return rb_struct_aref(st, rb_int2num_inline(k));
}
enum

rbimpl_typeddata_flags {
    RUBY_TYPED_FREE_IMMEDIATELY = 1,
    RUBY_TYPED_FROZEN_SHAREABLE = RUBY_FL_SHAREABLE,
    RUBY_TYPED_WB_PROTECTED = RUBY_FL_WB_PROTECTED,
    RUBY_TYPED_PROMOTED1 = RUBY_FL_PROMOTED1
};
typedef struct rb_data_type_struct rb_data_type_t;
struct rb_data_type_struct {
    const char *wrap_struct_name;
    struct {
        RUBY_DATA_FUNC dmark;
        RUBY_DATA_FUNC dfree;
        size_t (*dsize)(const void *);
        RUBY_DATA_FUNC dcompact;
        void *reserved[1];
    } function;
    const rb_data_type_t *parent;
    void *data;
    VALUE flags;
};
struct RTypedData {
    struct RBasic basic;
    const rb_data_type_t *type;
    VALUE typed_flag;
    void *data;
};


__attribute__((__nonnull__ (3)))
VALUE rb_data_typed_object_wrap(VALUE klass, void *datap, const rb_data_type_t *type);
VALUE rb_data_typed_object_zalloc(VALUE klass, size_t size, const rb_data_type_t *type);
int rb_typeddata_inherited_p(const rb_data_type_t *child, const rb_data_type_t *parent);
int rb_typeddata_is_kind_of(VALUE obj, const rb_data_type_t *data_type);
void *rb_check_typeddata(VALUE obj, const rb_data_type_t *data_type);


__attribute__((__pure__))
__attribute__((__artificial__))
static inline _Bool
rbimpl_rtypeddata_p(VALUE obj)
{
    return ((struct RTypedData *)(obj))->typed_flag == 1;
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline _Bool
RTYPEDDATA_P(VALUE obj)
{
    return rbimpl_rtypeddata_p(obj);
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline const struct rb_data_type_struct *
RTYPEDDATA_TYPE(VALUE obj)
{
    return ((struct RTypedData *)(obj))->type;
}
static inline VALUE
rb_data_typed_object_make(VALUE klass, const rb_data_type_t *type, void **datap, size_t size)
{
    VALUE result = rb_data_typed_object_zalloc(klass, size, type); (*datap) = ((void *)(((struct RTypedData *)(result))->data)); ((void)(*datap));
    return result;
}
__attribute__((__deprecated__ ("by: rb_data_typed_object_wrap")))
static inline VALUE
rb_data_typed_object_alloc(VALUE klass, void *datap, const rb_data_type_t *type)
{
    return rb_data_typed_object_wrap(klass, datap, type);
}

enum
{
  _ISupper = ((0) < 8 ? ((1 << (0)) << 8) : ((1 << (0)) >> 8)),
  _ISlower = ((1) < 8 ? ((1 << (1)) << 8) : ((1 << (1)) >> 8)),
  _ISalpha = ((2) < 8 ? ((1 << (2)) << 8) : ((1 << (2)) >> 8)),
  _ISdigit = ((3) < 8 ? ((1 << (3)) << 8) : ((1 << (3)) >> 8)),
  _ISxdigit = ((4) < 8 ? ((1 << (4)) << 8) : ((1 << (4)) >> 8)),
  _ISspace = ((5) < 8 ? ((1 << (5)) << 8) : ((1 << (5)) >> 8)),
  _ISprint = ((6) < 8 ? ((1 << (6)) << 8) : ((1 << (6)) >> 8)),
  _ISgraph = ((7) < 8 ? ((1 << (7)) << 8) : ((1 << (7)) >> 8)),
  _ISblank = ((8) < 8 ? ((1 << (8)) << 8) : ((1 << (8)) >> 8)),
  _IScntrl = ((9) < 8 ? ((1 << (9)) << 8) : ((1 << (9)) >> 8)),
  _ISpunct = ((10) < 8 ? ((1 << (10)) << 8) : ((1 << (10)) >> 8)),
  _ISalnum = ((11) < 8 ? ((1 << (11)) << 8) : ((1 << (11)) >> 8))
};
extern __const unsigned short int **__ctype_b_loc (void)
     __attribute__ ((__nothrow__)) __attribute__ ((__const));
extern __const __int32_t **__ctype_tolower_loc (void)
     __attribute__ ((__nothrow__)) __attribute__ ((__const));
extern __const __int32_t **__ctype_toupper_loc (void)
     __attribute__ ((__nothrow__)) __attribute__ ((__const));

extern int isalnum (int) __attribute__ ((__nothrow__));
extern int isalpha (int) __attribute__ ((__nothrow__));
extern int iscntrl (int) __attribute__ ((__nothrow__));
extern int isdigit (int) __attribute__ ((__nothrow__));
extern int islower (int) __attribute__ ((__nothrow__));
extern int isgraph (int) __attribute__ ((__nothrow__));
extern int isprint (int) __attribute__ ((__nothrow__));
extern int ispunct (int) __attribute__ ((__nothrow__));
extern int isspace (int) __attribute__ ((__nothrow__));
extern int isupper (int) __attribute__ ((__nothrow__));
extern int isxdigit (int) __attribute__ ((__nothrow__));
extern int tolower (int __c) __attribute__ ((__nothrow__));
extern int toupper (int __c) __attribute__ ((__nothrow__));


extern int isblank (int) __attribute__ ((__nothrow__));

extern int isctype (int __c, int __mask) __attribute__ ((__nothrow__));
extern int isascii (int __c) __attribute__ ((__nothrow__));
extern int toascii (int __c) __attribute__ ((__nothrow__));
extern int _toupper (int) __attribute__ ((__nothrow__));
extern int _tolower (int) __attribute__ ((__nothrow__));
extern int isalnum_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int isalpha_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int iscntrl_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int isdigit_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int islower_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int isgraph_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int isprint_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int ispunct_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int isspace_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int isupper_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int isxdigit_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int isblank_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int __tolower_l (int __c, __locale_t __l) __attribute__ ((__nothrow__));
extern int tolower_l (int __c, __locale_t __l) __attribute__ ((__nothrow__));
extern int __toupper_l (int __c, __locale_t __l) __attribute__ ((__nothrow__));
extern int toupper_l (int __c, __locale_t __l) __attribute__ ((__nothrow__));



__attribute__((__nonnull__ ()))
int rb_st_locale_insensitive_strcasecmp(const char *s1, const char *s2);
__attribute__((__nonnull__ ()))
int rb_st_locale_insensitive_strncasecmp(const char *s1, const char *s2, size_t n);
__attribute__((__nonnull__ (1)))
unsigned long ruby_strtoul(const char *str, char **endptr, int base);


__attribute__((__const__))

__attribute__((__artificial__))
static inline int
rb_isascii(int c)
{
    return '\0' <= c && c <= '\x7f';
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline int
rb_isupper(int c)
{
    return 'A' <= c && c <= 'Z';
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline int
rb_islower(int c)
{
    return 'a' <= c && c <= 'z';
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline int
rb_isalpha(int c)
{
    return rb_isupper(c) || rb_islower(c);
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline int
rb_isdigit(int c)
{
    return '0' <= c && c <= '9';
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline int
rb_isalnum(int c)
{
    return rb_isalpha(c) || rb_isdigit(c);
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline int
rb_isxdigit(int c)
{
    return rb_isdigit(c) || ('A' <= c && c <= 'F') || ('a' <= c && c <= 'f');
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline int
rb_isblank(int c)
{
    return c == ' ' || c == '\t';
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline int
rb_isspace(int c)
{
    return c == ' ' || ('\t' <= c && c <= '\r');
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline int
rb_iscntrl(int c)
{
    return ('\0' <= c && c < ' ') || c == '\x7f';
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline int
rb_isprint(int c)
{
    return ' ' <= c && c <= '\x7e';
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline int
rb_ispunct(int c)
{
    return !rb_isalnum(c);
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline int
rb_isgraph(int c)
{
    return '!' <= c && c <= '\x7e';
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline int
rb_tolower(int c)
{
    return rb_isupper(c) ? (c|0x20) : c;
}
__attribute__((__const__))

__attribute__((__artificial__))
static inline int
rb_toupper(int c)
{
    return rb_islower(c) ? (c&0x5f) : c;
}


__attribute__((__nonnull__ ()))
VALUE rb_eval_string(const char *str);
__attribute__((__nonnull__ (1)))
VALUE rb_eval_string_protect(const char *str, int *state);
__attribute__((__nonnull__ (1)))
VALUE rb_eval_string_wrap(const char *str, int *state);
VALUE rb_funcall(VALUE recv, ID mid, int n, ...);
VALUE rb_funcallv(VALUE recv, ID mid, int argc, const VALUE *argv);
VALUE rb_funcallv_kw(VALUE recv, ID mid, int argc, const VALUE *argv, int kw_splat);
VALUE rb_funcallv_public(VALUE recv, ID mid, int argc, const VALUE *argv);
VALUE rb_funcallv_public_kw(VALUE recv, ID mid, int argc, const VALUE *argv, int kw_splat);
VALUE rb_funcall_passing_block(VALUE recv, ID mid, int argc, const VALUE *argv);
VALUE rb_funcall_passing_block_kw(VALUE recv, ID mid, int argc, const VALUE *argv, int kw_splat);
VALUE rb_funcall_with_block(VALUE recv, ID mid, int argc, const VALUE *argv, VALUE procval);
VALUE rb_funcall_with_block_kw(VALUE recv, ID mid, int argc, const VALUE *argv, VALUE procval, int kw_splat);
VALUE rb_call_super(int argc, const VALUE *argv);
VALUE rb_call_super_kw(int argc, const VALUE *argv, int kw_splat);
VALUE rb_current_receiver(void);
__attribute__((__nonnull__ (2)))
int rb_get_kwargs(VALUE keyword_hash, const ID *table, int required, int optional, VALUE *values);
__attribute__((__nonnull__ ()))
VALUE rb_extract_keywords(VALUE *orighash);


typedef uint32_t rb_event_flag_t;
typedef void (*rb_event_hook_func_t)(rb_event_flag_t evflag, VALUE data, VALUE self, ID mid, VALUE klass);


void rb_add_event_hook(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data);
int rb_remove_event_hook(rb_event_hook_func_t func);




void rb_gc_register_address(VALUE *valptr);
void rb_global_variable(VALUE *);
void rb_gc_unregister_address(VALUE *valptr);
void rb_gc_register_mark_object(VALUE object);




typedef int ruby_glob_func(const char *path, VALUE arg, void *enc);
__attribute__((__nonnull__ ()))
void rb_glob(const char *pattern, void (*func)(const char *path, VALUE arg, void *enc), VALUE arg);
__attribute__((__nonnull__ ()))
int ruby_glob(const char *pattern, int flags, ruby_glob_func *func, VALUE arg);
__attribute__((__nonnull__ ()))
int ruby_brace_glob(const char *pattern, int flags, ruby_glob_func *func, VALUE arg);




extern VALUE rb_mKernel;
extern VALUE rb_mComparable;
extern VALUE rb_mEnumerable;
extern VALUE rb_mErrno;
extern VALUE rb_mFileTest;
extern VALUE rb_mGC;
extern VALUE rb_mMath;
extern VALUE rb_mProcess;
extern VALUE rb_mWaitReadable;
extern VALUE rb_mWaitWritable;
extern VALUE rb_cBasicObject;
extern VALUE rb_cObject;
extern VALUE rb_cArray;
extern VALUE rb_cBinding;
extern VALUE rb_cClass;
extern VALUE rb_cDir;
extern VALUE rb_cEncoding;
extern VALUE rb_cEnumerator;
extern VALUE rb_cFalseClass;
extern VALUE rb_cFile;
extern VALUE rb_cComplex;
extern VALUE rb_cFloat;
extern VALUE rb_cHash;
extern VALUE rb_cIO;
extern VALUE rb_cInteger;
extern VALUE rb_cMatch;
extern VALUE rb_cMethod;
extern VALUE rb_cModule;
extern VALUE rb_cRefinement;
extern VALUE rb_cNameErrorMesg;
extern VALUE rb_cNilClass;
extern VALUE rb_cNumeric;
extern VALUE rb_cProc;
extern VALUE rb_cRandom;
extern VALUE rb_cRange;
extern VALUE rb_cRational;
extern VALUE rb_cRegexp;
extern VALUE rb_cStat;
extern VALUE rb_cString;
extern VALUE rb_cStruct;
extern VALUE rb_cSymbol;
extern VALUE rb_cThread;
extern VALUE rb_cTime;
extern VALUE rb_cTrueClass;
extern VALUE rb_cUnboundMethod;
extern VALUE rb_eException;
extern VALUE rb_eStandardError;
extern VALUE rb_eSystemExit;
extern VALUE rb_eInterrupt;
extern VALUE rb_eSignal;
extern VALUE rb_eFatal;
extern VALUE rb_eArgError;
extern VALUE rb_eEOFError;
extern VALUE rb_eIndexError;
extern VALUE rb_eStopIteration;
extern VALUE rb_eKeyError;
extern VALUE rb_eRangeError;
extern VALUE rb_eIOError;
extern VALUE rb_eRuntimeError;
extern VALUE rb_eFrozenError;
extern VALUE rb_eSecurityError;
extern VALUE rb_eSystemCallError;
extern VALUE rb_eThreadError;
extern VALUE rb_eTypeError;
extern VALUE rb_eZeroDivError;
extern VALUE rb_eNotImpError;
extern VALUE rb_eNoMemError;
extern VALUE rb_eNoMethodError;
extern VALUE rb_eFloatDomainError;
extern VALUE rb_eLocalJumpError;
extern VALUE rb_eSysStackError;
extern VALUE rb_eRegexpError;
extern VALUE rb_eEncodingError;
extern VALUE rb_eEncCompatError;
extern VALUE rb_eNoMatchingPatternError;
extern VALUE rb_eNoMatchingPatternKeyError;
extern VALUE rb_eScriptError;
extern VALUE rb_eNameError;
extern VALUE rb_eSyntaxError;
extern VALUE rb_eLoadError;
extern VALUE rb_eMathDomainError;
extern VALUE rb_stdin;
extern VALUE rb_stdout;
extern VALUE rb_stderr;
__attribute__((__pure__))
static inline VALUE
rb_class_of(VALUE obj)
{
    if (! RB_SPECIAL_CONST_P(obj)) {
        return RBASIC_CLASS(obj);
    }
    else if (obj == ((VALUE)RUBY_Qfalse)) {
        return rb_cFalseClass;
    }
    else if (obj == ((VALUE)RUBY_Qnil)) {
        return rb_cNilClass;
    }
    else if (obj == ((VALUE)RUBY_Qtrue)) {
        return rb_cTrueClass;
    }
    else if (RB_FIXNUM_P(obj)) {
        return rb_cInteger;
    }
    else if (RB_STATIC_SYM_P(obj)) {
        return rb_cSymbol;
    }
    else if (RB_FLONUM_P(obj)) {
        return rb_cFloat;
    }
    __builtin_unreachable();
}




__attribute__((__nonnull__ ()))
void ruby_sysinit(int *argc, char ***argv);
void ruby_init(void);
void* ruby_options(int argc, char** argv);
int ruby_executable_node(void *n, int *status);
int ruby_run_node(void *n);
void ruby_show_version(void);
void ruby_show_copyright(void);
void ruby_init_stack(volatile VALUE *addr);
int ruby_setup(void);
int ruby_cleanup(int ex);
void ruby_finalize(void);
__attribute__((__noreturn__))
void ruby_stop(int);
int ruby_stack_check(void);
size_t ruby_stack_length(VALUE **topnotch);
int ruby_exec_node(void *n);
void ruby_script(const char* name);
void ruby_set_script_name(VALUE name);
void ruby_prog_init(void);
void ruby_set_argv(int argc, char **argv);
void *ruby_process_options(int argc, char **argv);
void ruby_init_loadpath(void);
void ruby_incpush(const char *path);
void ruby_sig_finalize(void);




typedef VALUE rb_block_call_func(VALUE yielded_arg, VALUE callback_arg, int argc, const VALUE *argv, VALUE blockarg);
typedef rb_block_call_func *rb_block_call_func_t;
VALUE rb_each(VALUE obj);
VALUE rb_yield(VALUE val);
VALUE rb_yield_values(int n, ...);
VALUE rb_yield_values2(int n, const VALUE *argv);
VALUE rb_yield_values_kw(int n, const VALUE *argv, int kw_splat);
VALUE rb_yield_splat(VALUE ary);
VALUE rb_yield_splat_kw(VALUE ary, int kw_splat);
VALUE rb_yield_block(VALUE yielded_arg, VALUE callback_arg, int argc, const VALUE *argv, VALUE blockarg);
int rb_keyword_given_p(void);
int rb_block_given_p(void);
void rb_need_block(void);
__attribute__((__deprecated__ ("by: rb_block_call since 1.9")))
VALUE rb_iterate(VALUE (*func1)(VALUE), VALUE data1, rb_block_call_func_t proc, VALUE data2);
VALUE rb_block_call(VALUE obj, ID mid, int argc, const VALUE *argv, rb_block_call_func_t proc, VALUE data2);
VALUE rb_block_call_kw(VALUE obj, ID mid, int argc, const VALUE *argv, rb_block_call_func_t proc, VALUE data2, int kw_splat);
VALUE rb_rescue(VALUE (*b_proc)(VALUE), VALUE data1, VALUE (*r_proc)(VALUE, VALUE), VALUE data2);
VALUE rb_rescue2(VALUE (*b_proc)(VALUE), VALUE data1, VALUE (*r_proc)(VALUE, VALUE), VALUE data2, ...);
VALUE rb_vrescue2(VALUE (*b_proc)(VALUE), VALUE data1, VALUE (*r_proc)(VALUE, VALUE), VALUE data2, va_list ap);
VALUE rb_ensure(VALUE (*b_proc)(VALUE), VALUE data1, VALUE (*e_proc)(VALUE), VALUE data2);
VALUE rb_catch(const char *tag, rb_block_call_func_t func, VALUE data);
VALUE rb_catch_obj(VALUE tag, rb_block_call_func_t func, VALUE data);
__attribute__((__noreturn__))
void rb_throw(const char *tag, VALUE val);
__attribute__((__noreturn__))
void rb_throw_obj(VALUE tag, VALUE val);


struct rbimpl_size_mul_overflow_tag {
    _Bool left;
    size_t right;
};


__attribute__((__malloc__))
__attribute__((__returns_nonnull__))
__attribute__((__alloc_size__ (2)))
__attribute__((__nonnull__ ()))
void *rb_alloc_tmp_buffer(volatile VALUE *store, long len);
__attribute__((__malloc__))
__attribute__((__returns_nonnull__))
__attribute__((__alloc_size__ (2,3)))
__attribute__((__nonnull__ ()))
void *rb_alloc_tmp_buffer_with_count(volatile VALUE *store, size_t len,size_t count);
void rb_free_tmp_buffer(volatile VALUE *store);
__attribute__((__noreturn__))
void ruby_malloc_size_overflow(size_t x, size_t y);


static inline int
rb_mul_size_overflow(size_t a, size_t b, size_t max, size_t *c)
{
    __extension__ unsigned __int128 da, db, c2;
    da = a;
    db = b;
    c2 = da * db;
    if (c2 > max) return 1;
    *c = ((size_t)c2);
    return 0;
}

__attribute__((__const__))
static inline struct rbimpl_size_mul_overflow_tag
rbimpl_size_mul_overflow(size_t x, size_t y)
{
    struct rbimpl_size_mul_overflow_tag ret = { 0, 0, };
    ret.left = __builtin_mul_overflow(x, y, &ret.right);
    return ret;
}
static inline size_t
rbimpl_size_mul_or_raise(size_t x, size_t y)
{
    struct rbimpl_size_mul_overflow_tag size =
        rbimpl_size_mul_overflow(x, y);
    if ((__builtin_expect(!!(! size.left), 1))) {
        return size.right;
    }
    else {
        ruby_malloc_size_overflow(x, y);
        __builtin_unreachable();
    }
}
static inline void *
rb_alloc_tmp_buffer2(volatile VALUE *store, long count, size_t elsize)
{
    const size_t total_size = rbimpl_size_mul_or_raise(count, elsize);
    const size_t cnt = (total_size + sizeof(VALUE) - 1) / sizeof(VALUE);
    return rb_alloc_tmp_buffer_with_count(store, total_size, cnt);
}



__attribute__((__nonnull__ (1)))
__attribute__((__returns_nonnull__))
static inline void *
ruby_nonempty_memcpy(void *dest, const void *src, size_t n)
{
    if (n) {
        return memcpy(dest, src, n);
    }
    else {
        return dest;
    }
}




__attribute__((__nonnull__ ()))
VALUE rb_define_class(const char *name, VALUE super);
__attribute__((__nonnull__ ()))
VALUE rb_define_module(const char *name);
__attribute__((__nonnull__ ()))
VALUE rb_define_class_under(VALUE outer, const char *name, VALUE super);
__attribute__((__nonnull__ ()))
VALUE rb_define_module_under(VALUE outer, const char *name);
void rb_include_module(VALUE klass, VALUE module);
void rb_extend_object(VALUE obj, VALUE mod);
void rb_prepend_module(VALUE klass, VALUE module);




VALUE rb_newobj(void);
VALUE rb_newobj_of(VALUE klass, VALUE flags);
VALUE rb_obj_setup(VALUE obj, VALUE klass, VALUE type);
VALUE rb_obj_class(VALUE obj);
VALUE rb_singleton_class_clone(VALUE obj);
void rb_singleton_class_attached(VALUE klass, VALUE obj);
void rb_copy_generic_ivar(VALUE clone, VALUE obj);


__attribute__((__deprecated__ ("This is no longer how Object#clone works.")))
static inline void
rb_clone_setup(VALUE clone, VALUE obj)
{
    return;
}
__attribute__((__deprecated__ ("This is no longer how Object#dup works.")))
static inline void
rb_dup_setup(VALUE dup, VALUE obj)
{
    return;
}


__attribute__((__nonnull__ ()))

void rb_mem_clear(VALUE *buf, long len)
   
    ;
VALUE rb_assoc_new(VALUE car, VALUE cdr);
VALUE rb_check_array_type(VALUE obj);
VALUE rb_ary_new(void);
VALUE rb_ary_new_capa(long capa);
VALUE rb_ary_new_from_args(long n, ...);
VALUE rb_ary_new_from_values(long n, const VALUE *elts);
VALUE rb_ary_tmp_new(long capa);
void rb_ary_free(VALUE ary);
void rb_ary_modify(VALUE ary);
VALUE rb_ary_freeze(VALUE obj);
__attribute__((__pure__))
VALUE rb_ary_shared_with_p(VALUE lhs, VALUE rhs);
VALUE rb_ary_aref(int argc, const VALUE *argv, VALUE ary);
VALUE rb_ary_subseq(VALUE ary, long beg, long len);
void rb_ary_store(VALUE ary, long key, VALUE val);
VALUE rb_ary_dup(VALUE ary);
VALUE rb_ary_resurrect(VALUE ary);
VALUE rb_ary_to_ary(VALUE obj);
VALUE rb_ary_to_s(VALUE ary);
VALUE rb_ary_cat(VALUE ary, const VALUE *train, long len);
VALUE rb_ary_push(VALUE ary, VALUE elem);
VALUE rb_ary_pop(VALUE ary);
VALUE rb_ary_shift(VALUE ary);
VALUE rb_ary_unshift(VALUE ary, VALUE elem);
__attribute__((__pure__))
VALUE rb_ary_entry(VALUE ary, long off);
VALUE rb_ary_each(VALUE ary);
VALUE rb_ary_join(VALUE ary, VALUE sep);
VALUE rb_ary_reverse(VALUE ary);
VALUE rb_ary_rotate(VALUE ary, long rot);
VALUE rb_ary_sort(VALUE ary);
VALUE rb_ary_sort_bang(VALUE ary);
VALUE rb_ary_delete(VALUE ary, VALUE elem);
VALUE rb_ary_delete_at(VALUE ary, long pos);
VALUE rb_ary_clear(VALUE ary);
VALUE rb_ary_plus(VALUE lhs, VALUE rhs);
VALUE rb_ary_concat(VALUE lhs, VALUE rhs);
VALUE rb_ary_assoc(VALUE alist, VALUE key);
VALUE rb_ary_rassoc(VALUE alist, VALUE key);
VALUE rb_ary_includes(VALUE ary, VALUE elem);
VALUE rb_ary_cmp(VALUE lhs, VALUE rhs);
VALUE rb_ary_replace(VALUE copy, VALUE orig);
VALUE rb_get_values_at(VALUE obj, long olen, int argc, const VALUE *argv, VALUE (*func)(VALUE obj, long oidx));
VALUE rb_ary_resize(VALUE ary, long len);




VALUE rb_exc_new(VALUE etype, const char *ptr, long len);
__attribute__((__nonnull__ ()))
VALUE rb_exc_new_cstr(VALUE etype, const char *str);
VALUE rb_exc_new_str(VALUE etype, VALUE str);
__attribute__((__noreturn__))
__attribute__((__nonnull__ (1)))
__attribute__((__format__(__printf__, 1, 2)))
void rb_loaderror(const char *fmt, ...);
__attribute__((__noreturn__))
__attribute__((__nonnull__ (2)))
__attribute__((__format__(__printf__, 2, 3)))
void rb_loaderror_with_path(VALUE path, const char *fmt, ...);
__attribute__((__noreturn__))
__attribute__((__nonnull__ (2)))
__attribute__((__format__(__printf__, 2, 3)))
void rb_name_error(ID name, const char *fmt, ...);
__attribute__((__noreturn__))
__attribute__((__nonnull__ (2)))
__attribute__((__format__(__printf__, 2, 3)))
void rb_name_error_str(VALUE name, const char *fmt, ...);
__attribute__((__noreturn__))
__attribute__((__nonnull__ (2)))
__attribute__((__format__(__printf__, 2, 3)))
void rb_frozen_error_raise(VALUE recv, const char *fmt, ...);
__attribute__((__noreturn__))
__attribute__((__nonnull__ ()))
void rb_invalid_str(const char *str, const char *type);
__attribute__((__noreturn__))
__attribute__((__nonnull__ ()))
void rb_error_frozen(const char *what);
__attribute__((__noreturn__))
void rb_error_frozen_object(VALUE what);
void rb_error_untrusted(VALUE);
void rb_check_frozen(VALUE obj);
void rb_check_trusted(VALUE);
void rb_check_copyable(VALUE obj, VALUE orig);
__attribute__((__noreturn__))
static void rb_error_arity(int argc, int min, int max);


static inline void
rb_check_frozen_inline(VALUE obj)
{
    if ((__builtin_expect(!!(RB_OBJ_FROZEN(obj)), 0))) {
        rb_error_frozen_object(obj);
    }
}
static inline int
rb_check_arity(int argc, int min, int max)
{
    if ((argc < min) || (max != (-1) && argc > max))
        rb_error_arity(argc, min, max);
    return argc;
}


__attribute__((__nonnull__ ()))
void rb_st_foreach_safe(struct st_table *st, st_foreach_callback_func *func, st_data_t arg);
VALUE rb_check_hash_type(VALUE obj);
__attribute__((__nonnull__ ()))
void rb_hash_foreach(VALUE hash, int (*func)(VALUE key, VALUE val, VALUE arg), VALUE arg);
VALUE rb_hash(VALUE obj);
VALUE rb_hash_new(void);
VALUE rb_hash_dup(VALUE hash);
VALUE rb_hash_freeze(VALUE obj);
VALUE rb_hash_aref(VALUE hash, VALUE key);
VALUE rb_hash_lookup(VALUE hash, VALUE key);
VALUE rb_hash_lookup2(VALUE hash, VALUE key, VALUE def);
VALUE rb_hash_fetch(VALUE hash, VALUE key);
VALUE rb_hash_aset(VALUE hash, VALUE key, VALUE val);
VALUE rb_hash_clear(VALUE hash);
VALUE rb_hash_delete_if(VALUE hash);
VALUE rb_hash_delete(VALUE hash, VALUE key);
void rb_hash_bulk_insert(long argc, const VALUE *argv, VALUE hash);
typedef VALUE rb_hash_update_func(VALUE newkey, VALUE oldkey, VALUE value);
VALUE rb_hash_update_by(VALUE hash1, VALUE hash2, rb_hash_update_func *func);
int rb_path_check(const char *path);
int rb_env_path_tainted(void);
VALUE rb_env_clear(void);
VALUE rb_hash_size(VALUE hash);




VALUE rb_block_proc(void);
VALUE rb_block_lambda(void);
VALUE rb_proc_new(rb_block_call_func_t func, VALUE callback_arg);
VALUE rb_obj_is_proc(VALUE recv);
VALUE rb_proc_call(VALUE recv, VALUE args);
VALUE rb_proc_call_kw(VALUE recv, VALUE args, int kw_splat);
VALUE rb_proc_call_with_block(VALUE recv, int argc, const VALUE *argv, VALUE proc);
VALUE rb_proc_call_with_block_kw(VALUE recv, int argc, const VALUE *argv, VALUE proc, int kw_splat);
int rb_proc_arity(VALUE recv);
VALUE rb_proc_lambda_p(VALUE recv);
VALUE rb_binding_new(void);
VALUE rb_obj_method(VALUE recv, VALUE mid);
VALUE rb_obj_is_method(VALUE recv);
VALUE rb_method_call(int argc, const VALUE *argv, VALUE recv);
VALUE rb_method_call_kw(int argc, const VALUE *argv, VALUE recv, int kw_splat);
VALUE rb_method_call_with_block(int argc, const VALUE *argv, VALUE recv, VALUE proc);
VALUE rb_method_call_with_block_kw(int argc, const VALUE *argv, VALUE recv, VALUE proc, int kw_splat);
int rb_mod_method_arity(VALUE mod, ID mid);
int rb_obj_method_arity(VALUE obj, ID mid);
__attribute__((__nonnull__ (1)))
VALUE rb_protect(VALUE (*func)(VALUE args), VALUE args, int *state);




__attribute__((__nonnull__ (2, 3)))
int rb_scan_args(int argc, const VALUE *argv, const char *fmt, ...);
__attribute__((__nonnull__ (3, 4)))
int rb_scan_args_kw(int kw_splat, int argc, const VALUE *argv, const char *fmt, ...);
__attribute__((__error__ ("bad scan arg format")))
void rb_scan_args_bad_format(const char*);
__attribute__((__error__ ("variable argument length doesn't match")))
void rb_scan_args_length_mismatch(const char*,int);


static inline _Bool
rb_scan_args_keyword_p(int kw_flag, VALUE last)
{
    switch (kw_flag) {
      case 0:
        return !! rb_keyword_given_p();
      case 1:
        return 1;
      case 3:
        return RB_TYPE_P(last, RUBY_T_HASH);
      default:
        return 0;
    }
}
__attribute__((__always_inline__)) inline
static _Bool
rb_scan_args_lead_p(const char *fmt)
{
    return (((unsigned char)((fmt[0])-'0'))<10);
}
__attribute__((__always_inline__)) inline
static int
rb_scan_args_n_lead(const char *fmt)
{
    return (rb_scan_args_lead_p(fmt) ? fmt[0]-'0' : 0);
}
__attribute__((__always_inline__)) inline
static _Bool
rb_scan_args_opt_p(const char *fmt)
{
    return (rb_scan_args_lead_p(fmt) && (((unsigned char)((fmt[1])-'0'))<10));
}
__attribute__((__always_inline__)) inline
static int
rb_scan_args_n_opt(const char *fmt)
{
    return (rb_scan_args_opt_p(fmt) ? fmt[1]-'0' : 0);
}
__attribute__((__always_inline__)) inline
static int
rb_scan_args_var_idx(const char *fmt)
{
    return (!rb_scan_args_lead_p(fmt) ? 0 : !(((unsigned char)((fmt[1])-'0'))<10) ? 1 : 2);
}
__attribute__((__always_inline__)) inline
static _Bool
rb_scan_args_f_var(const char *fmt)
{
    return (fmt[rb_scan_args_var_idx(fmt)]=='*');
}
__attribute__((__always_inline__)) inline
static int
rb_scan_args_trail_idx(const char *fmt)
{
    const int idx = rb_scan_args_var_idx(fmt);
    return idx+(fmt[idx]=='*');
}
__attribute__((__always_inline__)) inline
static int
rb_scan_args_n_trail(const char *fmt)
{
    const int idx = rb_scan_args_trail_idx(fmt);
    return ((((unsigned char)((fmt[idx])-'0'))<10) ? fmt[idx]-'0' : 0);
}
__attribute__((__always_inline__)) inline
static int
rb_scan_args_hash_idx(const char *fmt)
{
    const int idx = rb_scan_args_trail_idx(fmt);
    return idx+(((unsigned char)((fmt[idx])-'0'))<10);
}
__attribute__((__always_inline__)) inline
static _Bool
rb_scan_args_f_hash(const char *fmt)
{
    return (fmt[rb_scan_args_hash_idx(fmt)]==':');
}
__attribute__((__always_inline__)) inline
static int
rb_scan_args_block_idx(const char *fmt)
{
    const int idx = rb_scan_args_hash_idx(fmt);
    return idx+(fmt[idx]==':');
}
__attribute__((__always_inline__)) inline
static _Bool
rb_scan_args_f_block(const char *fmt)
{
    return (fmt[rb_scan_args_block_idx(fmt)]=='&');
}
__attribute__((__always_inline__)) inline
static int
rb_scan_args_set(int kw_flag, int argc, const VALUE *argv,
                 int n_lead, int n_opt, int n_trail,
                 _Bool f_var, _Bool f_hash, _Bool f_block,
                 VALUE *vars[], const char *fmt [[maybe_unused]], int varc [[maybe_unused]])
   
   
{
    int i, argi = 0, vari = 0;
    VALUE *var, hash = ((VALUE)RUBY_Qnil);
    const int n_mand = n_lead + n_trail;
    if (f_hash && argc > 0) {
        VALUE last = argv[argc - 1];
        if (rb_scan_args_keyword_p(kw_flag, last)) {
            hash = rb_hash_dup(last);
            argc--;
        }
    }
    if (argc < n_mand) {
        goto argc_error;
    }
    for (i = 0; i < n_lead; i++) {
        var = vars[vari++];
        if (var) *var = argv[argi];
        argi++;
    }
    for (i = 0; i < n_opt; i++) {
        var = vars[vari++];
        if (argi < argc - n_trail) {
            if (var) *var = argv[argi];
            argi++;
        }
        else {
            if (var) *var = ((VALUE)RUBY_Qnil);
        }
    }
    if (f_var) {
        int n_var = argc - argi - n_trail;
        var = vars[vari++];
        if (0 < n_var) {
            if (var) *var = rb_ary_new_from_values(n_var, &argv[argi]);
            argi += n_var;
        }
        else {
            if (var) *var = rb_ary_new();
        }
    }
    for (i = 0; i < n_trail; i++) {
        var = vars[vari++];
        if (var) *var = argv[argi];
        argi++;
    }
    if (f_hash) {
        var = vars[vari++];
        if (var) *var = hash;
    }
    if (f_block) {
        var = vars[vari++];
        if (rb_block_given_p()) {
            *var = rb_block_proc();
        }
        else {
            *var = ((VALUE)RUBY_Qnil);
        }
    }
    if (argi == argc) {
        return argc;
    }
  argc_error:
    rb_error_arity(argc, n_mand, f_var ? (-1) : n_mand + n_opt);
    __builtin_unreachable();
}


ID rb_sym2id(VALUE obj);
VALUE rb_id2sym(ID id);
__attribute__((__nonnull__ ()))
ID rb_intern(const char *name);
ID rb_intern2(const char *name, long len);
ID rb_intern_str(VALUE str);
const char *rb_id2name(ID id);
__attribute__((__nonnull__ ()))
ID rb_check_id(volatile VALUE *namep);
ID rb_to_id(VALUE str);
VALUE rb_id2str(ID id);
VALUE rb_sym2str(VALUE id);
VALUE rb_to_symbol(VALUE name);
__attribute__((__nonnull__ ()))
VALUE rb_check_symbol(volatile VALUE *namep);


__attribute__((__pure__))
__attribute__((__nonnull__ ()))
static inline ID
rb_intern_const(const char *str)
{
    size_t len = strlen(str);
    return rb_intern2(str, ((long)len));
}

__attribute__((__nonnull__ ()))
static inline ID
rbimpl_intern_const(ID *ptr, const char *str)
{
    while (! *ptr) {
        *ptr = rb_intern_const(str);
    }
    return *ptr;
}


typedef VALUE rb_gvar_getter_t(ID id, VALUE *data);
typedef void rb_gvar_setter_t(VALUE val, ID id, VALUE *data);
typedef void rb_gvar_marker_t(VALUE *var);
rb_gvar_getter_t rb_gvar_undef_getter;
rb_gvar_setter_t rb_gvar_undef_setter;
rb_gvar_marker_t rb_gvar_undef_marker;
rb_gvar_getter_t rb_gvar_val_getter;
rb_gvar_setter_t rb_gvar_val_setter;
rb_gvar_marker_t rb_gvar_val_marker;
rb_gvar_getter_t rb_gvar_var_getter;
rb_gvar_setter_t rb_gvar_var_setter;
rb_gvar_marker_t rb_gvar_var_marker;
__attribute__((__noreturn__))
rb_gvar_setter_t rb_gvar_readonly_setter;
__attribute__((__nonnull__ ()))
void rb_define_variable(const char *name, VALUE *var);
__attribute__((__nonnull__ (1)))
void rb_define_virtual_variable(const char *name, rb_gvar_getter_t *getter, rb_gvar_setter_t *setter);
__attribute__((__nonnull__ (1)))
void rb_define_hooked_variable(const char *name, VALUE *var, rb_gvar_getter_t *getter, rb_gvar_setter_t *setter);
__attribute__((__nonnull__ ()))
void rb_define_readonly_variable(const char *name, const VALUE *var);
__attribute__((__nonnull__ ()))
void rb_define_const(VALUE klass, const char *name, VALUE val);
__attribute__((__nonnull__ ()))
void rb_define_global_const(const char *name, VALUE val);
__attribute__((__nonnull__ ()))
void rb_deprecate_constant(VALUE mod, const char *name);
__attribute__((__nonnull__ ()))
VALUE rb_gv_set(const char *name, VALUE val);
__attribute__((__nonnull__ ()))
VALUE rb_gv_get(const char *name);
__attribute__((__nonnull__ ()))
VALUE rb_iv_get(VALUE obj, const char *name);
__attribute__((__nonnull__ ()))
VALUE rb_iv_set(VALUE obj, const char *name, VALUE val);




VALUE rb_get_path(VALUE obj);
VALUE rb_get_path_no_checksafe(VALUE);
__attribute__((__error__ (" argument length doesn't match"))) int rb_varargs_bad_length(int,int);
const char *rb_class2name(VALUE klass);
const char *rb_obj_classname(VALUE obj);
void rb_p(VALUE obj);
VALUE rb_equal(VALUE lhs, VALUE rhs);
VALUE rb_require(const char *feature);


VALUE rb_big_new(size_t len, int sign);
int rb_bigzero_p(VALUE x);
VALUE rb_big_clone(VALUE num);
void rb_big_2comp(VALUE num);
VALUE rb_big_norm(VALUE x);
void rb_big_resize(VALUE big, size_t len);
__attribute__((__nonnull__ ()))
VALUE rb_cstr_to_inum(const char *str, int base, int badcheck);
VALUE rb_str_to_inum(VALUE str, int base, int badcheck);
__attribute__((__nonnull__ ()))
VALUE rb_cstr2inum(const char *str, int base);
VALUE rb_str2inum(VALUE str, int base);
VALUE rb_big2str(VALUE x, int base);
long rb_big2long(VALUE x);
unsigned long rb_big2ulong(VALUE x);
long long rb_big2ll(VALUE);
unsigned long long rb_big2ull(VALUE);
__attribute__((__nonnull__ ()))
void rb_big_pack(VALUE val, unsigned long *buf, long num_longs);
__attribute__((__nonnull__ ()))
VALUE rb_big_unpack(unsigned long *buf, long num_longs);
__attribute__((__nonnull__ ()))
int rb_uv_to_utf8(char buf[6], unsigned long uv);
VALUE rb_dbl2big(double d);
double rb_big2dbl(VALUE x);
VALUE rb_big_cmp(VALUE lhs, VALUE rhs);
VALUE rb_big_eq(VALUE lhs, VALUE rhs);
VALUE rb_big_eql(VALUE lhs, VALUE rhs);
VALUE rb_big_plus(VALUE x, VALUE y);
VALUE rb_big_minus(VALUE x, VALUE y);
VALUE rb_big_mul(VALUE x, VALUE y);
VALUE rb_big_div(VALUE x, VALUE y);
VALUE rb_big_idiv(VALUE x, VALUE y);
VALUE rb_big_modulo(VALUE x, VALUE y);
VALUE rb_big_divmod(VALUE x, VALUE y);
VALUE rb_big_pow(VALUE x, VALUE y);
VALUE rb_big_and(VALUE x, VALUE y);
VALUE rb_big_or(VALUE x, VALUE y);
VALUE rb_big_xor(VALUE x, VALUE y);
VALUE rb_big_lshift(VALUE x, VALUE y);
VALUE rb_big_rshift(VALUE x, VALUE y);
__attribute__((__nonnull__ ()))
int rb_integer_pack(VALUE val, void *words, size_t numwords, size_t wordsize, size_t nails, int flags);
__attribute__((__nonnull__ ()))
VALUE rb_integer_unpack(const void *words, size_t numwords, size_t wordsize, size_t nails, int flags);
size_t rb_absint_size(VALUE val, int *nlz_bits_ret);
size_t rb_absint_numwords(VALUE val, size_t word_numbits, size_t *nlz_bits_ret);
int rb_absint_singlebit_p(VALUE val);




int rb_cmpint(VALUE val, VALUE a, VALUE b);
__attribute__((__cold__))
__attribute__((__noreturn__))
void rb_cmperr(VALUE a, VALUE b);




VALUE rb_complex_raw(VALUE real, VALUE imag);
VALUE rb_complex_new(VALUE real, VALUE imag);
VALUE rb_complex_new_polar(VALUE abs, VALUE arg);
__attribute__((__deprecated__ ("by: rb_complex_new_polar")))
VALUE rb_complex_polar(VALUE abs, VALUE arg);
__attribute__((__pure__))
VALUE rb_complex_real(VALUE z);
__attribute__((__pure__))
VALUE rb_complex_imag(VALUE z);
VALUE rb_complex_plus(VALUE x, VALUE y);
VALUE rb_complex_minus(VALUE x, VALUE y);
VALUE rb_complex_mul(VALUE x, VALUE y);
VALUE rb_complex_div(VALUE x, VALUE y);
VALUE rb_complex_uminus(VALUE z);
VALUE rb_complex_conjugate(VALUE z);
VALUE rb_complex_abs(VALUE z);
VALUE rb_complex_arg(VALUE z);
VALUE rb_complex_pow(VALUE base, VALUE exp);
VALUE rb_dbl_complex_new(double real, double imag);
VALUE rb_Complex(VALUE real, VALUE imag);




VALUE rb_fiber_new(rb_block_call_func_t func, VALUE callback_obj);
VALUE rb_fiber_current(void);
VALUE rb_fiber_alive_p(VALUE fiber);
VALUE rb_obj_is_fiber(VALUE obj);
VALUE rb_fiber_resume(VALUE fiber, int argc, const VALUE *argv);
VALUE rb_fiber_resume_kw(VALUE fiber, int argc, const VALUE *argv, int kw_splat);
VALUE rb_fiber_yield(int argc, const VALUE *argv);
VALUE rb_fiber_yield_kw(int argc, const VALUE *argv, int kw_splat);
VALUE rb_fiber_transfer(VALUE fiber, int argc, const VALUE *argv);
VALUE rb_fiber_transfer_kw(VALUE fiber, int argc, const VALUE *argv, int kw_splat);
VALUE rb_fiber_raise(VALUE fiber, int argc, const VALUE *argv);




VALUE rb_dir_getwd(void);




VALUE rb_enum_values_pack(int argc, const VALUE *argv);




__attribute__((__noreturn__))
void rb_exc_raise(VALUE exc);
__attribute__((__noreturn__))
void rb_exc_fatal(VALUE exc);
__attribute__((__noreturn__))
VALUE rb_f_exit(int argc, const VALUE *argv);
__attribute__((__noreturn__))
VALUE rb_f_abort(int argc, const VALUE *argv);
__attribute__((__noreturn__))
void rb_interrupt(void);
ID rb_frame_this_func(void);
__attribute__((__noreturn__))
void rb_jump_tag(int state);
void rb_obj_call_init(VALUE obj, int argc, const VALUE *argv);
void rb_obj_call_init_kw(VALUE, int, const VALUE*, int);
ID rb_frame_callee(void);
VALUE rb_make_exception(int argc, const VALUE *argv);
void rb_set_end_proc(void (*func)(VALUE arg), VALUE arg);




typedef VALUE rb_enumerator_size_func(VALUE recv, VALUE argv, VALUE eobj);
typedef struct {
    VALUE begin;
    VALUE end;
    VALUE step;
    int exclude_end;
} rb_arithmetic_sequence_components_t;
VALUE rb_enumeratorize(VALUE recv, VALUE meth, int argc, const VALUE *argv);
VALUE rb_enumeratorize_with_size(VALUE recv, VALUE meth, int argc, const VALUE *argv, rb_enumerator_size_func *func);
VALUE rb_enumeratorize_with_size_kw(VALUE recv, VALUE meth, int argc, const VALUE *argv, rb_enumerator_size_func *func, int kw_splat);
__attribute__((__nonnull__ ()))
int rb_arithmetic_sequence_extract(VALUE as, rb_arithmetic_sequence_components_t *buf);
__attribute__((__nonnull__ ()))
VALUE rb_arithmetic_sequence_beg_len_step(VALUE as, long *begp, long *lenp, long *stepp, long len, int err);




__attribute__((__nonnull__ ()))
VALUE rb_file_s_expand_path(int argc, const VALUE *argv);
VALUE rb_file_expand_path(VALUE fname, VALUE dname);
__attribute__((__nonnull__ ()))
VALUE rb_file_s_absolute_path(int argc, const VALUE *argv);
VALUE rb_file_absolute_path(VALUE fname, VALUE dname);
VALUE rb_file_dirname(VALUE fname);
__attribute__((__nonnull__ ()))
int rb_find_file_ext(VALUE *feature, const char *const *exts);
VALUE rb_find_file(VALUE path);
VALUE rb_file_directory_p(VALUE _, VALUE path);
VALUE rb_str_encode_ospath(VALUE path);
__attribute__((__nonnull__ ()))
__attribute__((__pure__))
int rb_is_absolute_path(const char *path);
off_t rb_file_size(VALUE file);




__attribute__((__cold__))
__attribute__((__noreturn__))
void rb_memerror(void);
__attribute__((__pure__))
int rb_during_gc(void);
__attribute__((__nonnull__ (1)))
void rb_gc_mark_locations(const VALUE *start, const VALUE *end);
void rb_mark_tbl(struct st_table *tbl);
void rb_mark_tbl_no_pin(struct st_table *tbl);
void rb_mark_set(struct st_table *tbl);
void rb_mark_hash(struct st_table *tbl);
void rb_gc_update_tbl_refs(st_table *ptr);
void rb_gc_mark_maybe(VALUE obj);
void rb_gc_mark(VALUE obj);
void rb_gc_mark_movable(VALUE obj);
VALUE rb_gc_location(VALUE obj);
__attribute__((__deprecated__ ("this is now a no-op function")))
void rb_gc_force_recycle(VALUE obj);
void rb_gc(void);
void rb_gc_copy_finalizer(VALUE dst, VALUE src);
VALUE rb_gc_enable(void);
VALUE rb_gc_disable(void);
VALUE rb_gc_start(void);
VALUE rb_define_finalizer(VALUE obj, VALUE block);
VALUE rb_undefine_finalizer(VALUE obj);
size_t rb_gc_count(void);
size_t rb_gc_stat(VALUE key_or_buf);
VALUE rb_gc_latest_gc_info(VALUE key_or_buf);
void rb_gc_adjust_memory_usage(ssize_t diff);




extern VALUE rb_fs;
extern VALUE rb_output_fs;
extern VALUE rb_rs;
extern VALUE rb_default_rs;
extern VALUE rb_output_rs;
VALUE rb_io_write(VALUE io, VALUE str);
VALUE rb_io_gets(VALUE io);
VALUE rb_io_getbyte(VALUE io);
VALUE rb_io_ungetc(VALUE io, VALUE c);
VALUE rb_io_ungetbyte(VALUE io, VALUE b);
VALUE rb_io_close(VALUE io);
VALUE rb_io_flush(VALUE io);
VALUE rb_io_eof(VALUE io);
VALUE rb_io_binmode(VALUE io);
VALUE rb_io_ascii8bit_binmode(VALUE io);
VALUE rb_io_addstr(VALUE io, VALUE str);
VALUE rb_io_printf(int argc, const VALUE *argv, VALUE io);
VALUE rb_io_print(int argc, const VALUE *argv, VALUE io);
VALUE rb_io_puts(int argc, const VALUE *argv, VALUE io);
VALUE rb_io_fdopen(int fd, int flags, const char *path);
__attribute__((__nonnull__ ()))
VALUE rb_file_open(const char *fname, const char *fmode);
__attribute__((__nonnull__ ()))
VALUE rb_file_open_str(VALUE fname, const char *fmode);
VALUE rb_gets(void);
__attribute__((__nonnull__ ()))
void rb_write_error(const char *str);
void rb_write_error2(const char *str, long len);
void rb_close_before_exec(int lowfd, int maxhint, VALUE noclose_fds);
__attribute__((__nonnull__ ()))
int rb_pipe(int *pipes);
int rb_reserved_fd_p(int fd);
int rb_cloexec_open(const char *pathname, int flags, mode_t mode);
int rb_cloexec_dup(int oldfd);
int rb_cloexec_dup2(int oldfd, int newfd);
__attribute__((__nonnull__ ()))
int rb_cloexec_pipe(int fildes[2]);
int rb_cloexec_fcntl_dupfd(int fd, int minfd);
void rb_update_max_fd(int fd);
void rb_fd_fix_cloexec(int fd);




void rb_load(VALUE path, int wrap);
void rb_load_protect(VALUE path, int wrap, int *state);
__attribute__((__nonnull__ ()))
int rb_provided(const char *feature);
__attribute__((__nonnull__ (1)))
int rb_feature_provided(const char *feature, const char **loading);
__attribute__((__nonnull__ ()))
void rb_provide(const char *feature);
VALUE rb_f_require(VALUE self, VALUE feature);
VALUE rb_require_string(VALUE feature);
void rb_ext_ractor_safe(_Bool flag);




VALUE rb_marshal_dump(VALUE obj, VALUE port);
VALUE rb_marshal_load(VALUE port);
void rb_marshal_define_compat(VALUE newclass, VALUE oldclass, VALUE (*dumper)(VALUE), VALUE (*loader)(VALUE, VALUE));




__attribute__((__noreturn__))
__attribute__((__cold__))
void rb_num_zerodiv(void);
VALUE rb_num_coerce_bin(VALUE lhs, VALUE rhs, ID op);
VALUE rb_num_coerce_cmp(VALUE lhs, VALUE rhs, ID op);
VALUE rb_num_coerce_relop(VALUE lhs, VALUE rhs, ID op);
VALUE rb_num_coerce_bit(VALUE lhs, VALUE rhs, ID op);
VALUE rb_num2fix(VALUE val);
VALUE rb_fix2str(VALUE val, int base);
__attribute__((__const__))
VALUE rb_dbl_cmp(double lhs, double rhs);
extern VALUE rb_int_positive_pow(long x, unsigned long y);




VALUE rb_class_new_instance_pass_kw(int argc, const VALUE *argv, VALUE klass);
VALUE rb_class_new_instance(int argc, const VALUE *argv, VALUE klass);
VALUE rb_class_new_instance_kw(int argc, const VALUE *argv, VALUE klass, int kw_splat);
int rb_eql(VALUE lhs, VALUE rhs);
VALUE rb_any_to_s(VALUE obj);
VALUE rb_inspect(VALUE obj);
VALUE rb_obj_is_instance_of(VALUE obj, VALUE klass);
VALUE rb_obj_is_kind_of(VALUE obj, VALUE klass);
VALUE rb_obj_alloc(VALUE klass);
VALUE rb_obj_clone(VALUE obj);
VALUE rb_obj_dup(VALUE obj);
VALUE rb_obj_init_copy(VALUE src, VALUE dst);

VALUE rb_obj_taint(VALUE obj);
__attribute__((__pure__))

VALUE rb_obj_tainted(VALUE obj);

VALUE rb_obj_untaint(VALUE obj);

VALUE rb_obj_untrust(VALUE obj);
__attribute__((__pure__))

VALUE rb_obj_untrusted(VALUE obj);

VALUE rb_obj_trust(VALUE obj);
VALUE rb_obj_freeze(VALUE obj);
__attribute__((__pure__))
VALUE rb_obj_frozen_p(VALUE obj);
VALUE rb_obj_id(VALUE obj);
__attribute__((__const__))
VALUE rb_memory_id(VALUE obj);
__attribute__((__pure__))
VALUE rb_class_real(VALUE klass);
__attribute__((__pure__))
VALUE rb_class_inherited_p(VALUE scion, VALUE ascendant);
__attribute__((__pure__))
VALUE rb_class_superclass(VALUE klass);
__attribute__((__nonnull__ ()))
VALUE rb_convert_type(VALUE val, int type, const char *name, const char *mid);
__attribute__((__nonnull__ ()))
VALUE rb_check_convert_type(VALUE val, int type, const char *name, const char *mid);
__attribute__((__nonnull__ ()))
VALUE rb_check_to_integer(VALUE val, const char *mid);
VALUE rb_check_to_float(VALUE val);
VALUE rb_to_int(VALUE val);
VALUE rb_check_to_int(VALUE val);
VALUE rb_Integer(VALUE val);
VALUE rb_to_float(VALUE val);
VALUE rb_Float(VALUE val);
VALUE rb_String(VALUE val);
VALUE rb_Array(VALUE val);
VALUE rb_Hash(VALUE val);
__attribute__((__nonnull__ ()))
double rb_cstr_to_dbl(const char *str, int mode);
double rb_str_to_dbl(VALUE str, int mode);




ID rb_id_attrset(ID id);
__attribute__((__const__))
int rb_is_const_id(ID id);
__attribute__((__const__))
int rb_is_global_id(ID id);
__attribute__((__const__))
int rb_is_instance_id(ID id);
__attribute__((__const__))
int rb_is_attrset_id(ID id);
__attribute__((__const__))
int rb_is_class_id(ID id);
__attribute__((__const__))
int rb_is_local_id(ID id);
__attribute__((__const__))
int rb_is_junk_id(ID);
__attribute__((__nonnull__ ()))
int rb_symname_p(const char *str);
VALUE rb_backref_get(void);
void rb_backref_set(VALUE md);
VALUE rb_lastline_get(void);
void rb_lastline_set(VALUE str);
VALUE rb_sym_all_symbols(void);




void rb_last_status_set(int status, pid_t pid);
VALUE rb_last_status_get(void);
__attribute__((__nonnull__ ()))
int rb_proc_exec(const char *cmd);
__attribute__((__noreturn__))
VALUE rb_f_exec(int argc, const VALUE *argv);
pid_t rb_waitpid(pid_t pid, int *status, int flags);
void rb_syswait(pid_t pid);
pid_t rb_spawn(int argc, const VALUE *argv);
pid_t rb_spawn_err(int argc, const VALUE *argv, char *errbuf, size_t buflen);
VALUE rb_proc_times(VALUE _);
VALUE rb_detach_process(pid_t pid);




unsigned int rb_genrand_int32(void);
double rb_genrand_real(void);
void rb_reset_random_seed(void);
VALUE rb_random_bytes(VALUE rnd, long n);
unsigned int rb_random_int32(VALUE rnd);
double rb_random_real(VALUE rnd);
unsigned long rb_random_ulong_limited(VALUE rnd, unsigned long limit);
unsigned long rb_genrand_ulong_limited(unsigned long i);




VALUE rb_range_new(VALUE beg, VALUE end, int excl);
__attribute__((__nonnull__ ()))
VALUE rb_range_beg_len(VALUE range, long *begp, long *lenp, long len, int err);
__attribute__((__nonnull__ ()))
int rb_range_values(VALUE range, VALUE *begp, VALUE *endp, int *exclp);




VALUE rb_rational_raw(VALUE num, VALUE den);
VALUE rb_rational_new(VALUE num, VALUE den);
VALUE rb_Rational(VALUE num, VALUE den);
__attribute__((__pure__))
VALUE rb_rational_num(VALUE rat);
__attribute__((__pure__))
VALUE rb_rational_den(VALUE rat);
VALUE rb_flt_rationalize_with_prec(VALUE flt, VALUE prec);
VALUE rb_flt_rationalize(VALUE flt);




int rb_memcicmp(const void *s1,const void *s2, long n);
void rb_match_busy(VALUE md);
VALUE rb_reg_nth_defined(int n, VALUE md);
VALUE rb_reg_nth_match(int n, VALUE md);
int rb_reg_backref_number(VALUE match, VALUE backref);
VALUE rb_reg_last_match(VALUE md);
VALUE rb_reg_match_pre(VALUE md);
VALUE rb_reg_match_post(VALUE md);
VALUE rb_reg_match_last(VALUE md);
VALUE rb_reg_new_str(VALUE src, int opts);
__attribute__((__nonnull__ ()))
VALUE rb_reg_new(const char *src, long len, int opts);
VALUE rb_reg_alloc(void);
VALUE rb_reg_init_str(VALUE re, VALUE s, int options);
VALUE rb_reg_match(VALUE re, VALUE str);
VALUE rb_reg_match2(VALUE re);
int rb_reg_options(VALUE re);




extern VALUE rb_argv0;
VALUE rb_get_argv(void);
__attribute__((__nonnull__ ()))
void *rb_load_file(const char *file);
void *rb_load_file_str(VALUE file);


struct timeval;
typedef struct {
    int maxfd;
    fd_set *fdset;
} rb_fdset_t;


__attribute__((__nonnull__ ()))
void rb_fd_init(rb_fdset_t *f);
__attribute__((__nonnull__ ()))
void rb_fd_term(rb_fdset_t *f);
__attribute__((__nonnull__ ()))
void rb_fd_zero(rb_fdset_t *f);
__attribute__((__nonnull__ ()))
void rb_fd_set(int fd, rb_fdset_t *f);
__attribute__((__nonnull__ ()))
void rb_fd_clr(int fd, rb_fdset_t *f);
__attribute__((__nonnull__ ()))
__attribute__((__pure__))
int rb_fd_isset(int fd, const rb_fdset_t *f);
void rb_fd_copy(rb_fdset_t *dst, const fd_set *src, int max);
void rb_fd_dup(rb_fdset_t *dst, const rb_fdset_t *src);
int rb_fd_select(int nfds, rb_fdset_t *rfds, rb_fdset_t *wfds, rb_fdset_t *efds, struct timeval *timeout);


__attribute__((__nonnull__ ()))
__attribute__((__pure__))
static inline fd_set *
rb_fd_ptr(const rb_fdset_t *f)
{
    return f->fdset;
}
__attribute__((__nonnull__ ()))
__attribute__((__pure__))
static inline int
rb_fd_max(const rb_fdset_t *f)
{
    return f->maxfd;
}


struct timeval;
int rb_thread_fd_select(int nfds, rb_fdset_t *rfds, rb_fdset_t *wfds, rb_fdset_t *efds, struct timeval *timeout);




__attribute__((__nonnull__ ()))
VALUE rb_f_kill(int argc, const VALUE *argv);
void (*ruby_posix_signal(int, void (*)(int)))(int);
__attribute__((__pure__))
const char *ruby_signal_name(int signo);
void ruby_default_signal(int sig);




VALUE rb_f_sprintf(int argc, const VALUE *argv);
__attribute__((__nonnull__ (1)))
__attribute__((__format__(__printf__, 1, 2)))
VALUE rb_sprintf(const char *fmt, ...);
__attribute__((__nonnull__ (1)))
__attribute__((__format__(__printf__, 1, 0)))
VALUE rb_vsprintf(const char *fmt, va_list ap);
__attribute__((__nonnull__ (2)))
__attribute__((__format__(__printf__, 2, 3)))
VALUE rb_str_catf(VALUE dst, const char *fmt, ...);
__attribute__((__nonnull__ (2)))
__attribute__((__format__(__printf__, 2, 0)))
VALUE rb_str_vcatf(VALUE dst, const char *fmt, va_list ap);
VALUE rb_str_format(int argc, const VALUE *argv, VALUE fmt);




VALUE rb_str_new(const char *ptr, long len);
VALUE rb_str_new_cstr(const char *ptr);
VALUE rb_str_new_shared(VALUE str);
VALUE rb_str_new_frozen(VALUE str);
VALUE rb_str_new_with_class(VALUE obj, const char *ptr, long len);
VALUE rb_tainted_str_new_cstr(const char *ptr);
VALUE rb_tainted_str_new(const char *ptr, long len);
VALUE rb_external_str_new(const char *ptr, long len);
__attribute__((__nonnull__ ()))
VALUE rb_external_str_new_cstr(const char *ptr);
VALUE rb_locale_str_new(const char *ptr, long len);
__attribute__((__nonnull__ ()))
VALUE rb_locale_str_new_cstr(const char *ptr);
VALUE rb_filesystem_str_new(const char *ptr, long len);
__attribute__((__nonnull__ ()))
VALUE rb_filesystem_str_new_cstr(const char *ptr);
VALUE rb_str_buf_new(long capa);
__attribute__((__nonnull__ ()))
VALUE rb_str_buf_new_cstr(const char *ptr);
VALUE rb_str_tmp_new(long len);
VALUE rb_usascii_str_new(const char *ptr, long len);
VALUE rb_usascii_str_new_cstr(const char *ptr);
VALUE rb_utf8_str_new(const char *ptr, long len);
VALUE rb_utf8_str_new_cstr(const char *ptr);
VALUE rb_str_new_static(const char *ptr, long len);
VALUE rb_usascii_str_new_static(const char *ptr, long len);
VALUE rb_utf8_str_new_static(const char *ptr, long len);
VALUE rb_str_to_interned_str(VALUE str);
VALUE rb_interned_str(const char *ptr, long len);
__attribute__((__nonnull__ ()))
VALUE rb_interned_str_cstr(const char *ptr);
void rb_str_free(VALUE str);
void rb_str_shared_replace(VALUE dst, VALUE src);
VALUE rb_str_buf_append(VALUE dst, VALUE src);
VALUE rb_str_buf_cat(VALUE, const char*, long);
VALUE rb_str_buf_cat2(VALUE, const char*);
__attribute__((__nonnull__ ()))
VALUE rb_str_buf_cat_ascii(VALUE dst, const char *src);
VALUE rb_obj_as_string(VALUE obj);
VALUE rb_check_string_type(VALUE obj);
void rb_must_asciicompat(VALUE obj);
VALUE rb_str_dup(VALUE str);
VALUE rb_str_resurrect(VALUE str);
VALUE rb_str_locktmp(VALUE str);
VALUE rb_str_unlocktmp(VALUE str);
VALUE rb_str_dup_frozen(VALUE);
VALUE rb_str_plus(VALUE lhs, VALUE rhs);
VALUE rb_str_times(VALUE str, VALUE num);
long rb_str_sublen(VALUE str, long pos);
VALUE rb_str_substr(VALUE str, long beg, long len);
VALUE rb_str_subseq(VALUE str, long beg, long len);
char *rb_str_subpos(VALUE str, long beg, long *len);
void rb_str_modify(VALUE str);
void rb_str_modify_expand(VALUE str, long capa);
VALUE rb_str_freeze(VALUE str);
void rb_str_set_len(VALUE str, long len);
VALUE rb_str_resize(VALUE str, long len);
VALUE rb_str_cat(VALUE dst, const char *src, long srclen);
VALUE rb_str_cat_cstr(VALUE dst, const char *src);
VALUE rb_str_cat2(VALUE, const char*);
VALUE rb_str_append(VALUE dst, VALUE src);
VALUE rb_str_concat(VALUE dst, VALUE src);
st_index_t rb_memhash(const void *ptr, long len);
st_index_t rb_hash_start(st_index_t i);
st_index_t rb_str_hash(VALUE str);
int rb_str_hash_cmp(VALUE str1, VALUE str2);
int rb_str_comparable(VALUE str1, VALUE str2);
int rb_str_cmp(VALUE lhs, VALUE rhs);
VALUE rb_str_equal(VALUE str1, VALUE str2);
VALUE rb_str_drop_bytes(VALUE str, long len);
void rb_str_update(VALUE dst, long beg, long len, VALUE src);
VALUE rb_str_replace(VALUE dst, VALUE src);
VALUE rb_str_inspect(VALUE str);
VALUE rb_str_dump(VALUE str);
VALUE rb_str_split(VALUE str, const char *delim);
rb_gvar_setter_t rb_str_setter;
VALUE rb_str_intern(VALUE str);
VALUE rb_sym_to_s(VALUE sym);
long rb_str_strlen(VALUE str);
VALUE rb_str_length(VALUE);
long rb_str_offset(VALUE str, long pos);
__attribute__((__pure__))
size_t rb_str_capacity(VALUE str);
VALUE rb_str_ellipsize(VALUE str, long len);
VALUE rb_str_scrub(VALUE str, VALUE repl);
VALUE rb_str_succ(VALUE orig);
__attribute__((__nonnull__ ()))
static inline long
rbimpl_strlen(const char *str)
{
    return ((long)strlen(str));
}
__attribute__((__nonnull__ ()))
static inline VALUE
rbimpl_str_new_cstr(const char *str)
{
    long len = rbimpl_strlen(str);
    return rb_str_new_static(str, len);
}
__attribute__((__deprecated__ ("taintedness turned out to be a wrong idea.")))
static inline VALUE
rbimpl_tainted_str_new_cstr(const char *str)
{
    long len = rbimpl_strlen(str);
    return rb_tainted_str_new(str, len);
}
__attribute__((__nonnull__ ()))
static inline VALUE
rbimpl_usascii_str_new_cstr(const char *str)
{
    long len = rbimpl_strlen(str);
    return rb_usascii_str_new_static(str, len);
}
__attribute__((__nonnull__ ()))
static inline VALUE
rbimpl_utf8_str_new_cstr(const char *str)
{
    long len = rbimpl_strlen(str);
    return rb_utf8_str_new_static(str, len);
}
__attribute__((__nonnull__ ()))
static inline VALUE
rbimpl_external_str_new_cstr(const char *str)
{
    long len = rbimpl_strlen(str);
    return rb_external_str_new(str, len);
}
__attribute__((__nonnull__ ()))
static inline VALUE
rbimpl_locale_str_new_cstr(const char *str)
{
    long len = rbimpl_strlen(str);
    return rb_locale_str_new(str, len);
}
__attribute__((__nonnull__ ()))
static inline VALUE
rbimpl_str_buf_new_cstr(const char *str)
{
    long len = rbimpl_strlen(str);
    VALUE buf = rb_str_buf_new(len);
    return rb_str_buf_cat(buf, str, len);
}
__attribute__((__nonnull__ ()))
static inline VALUE
rbimpl_str_cat_cstr(VALUE buf, const char *str)
{
    long len = rbimpl_strlen(str);
    return rb_str_cat(buf, str, len);
}
__attribute__((__nonnull__ ()))
static inline VALUE
rbimpl_exc_new_cstr(VALUE exc, const char *str)
{
    long len = rbimpl_strlen(str);
    return rb_exc_new(exc, str, len);
}




VALUE rb_struct_new(VALUE klass, ...);
VALUE rb_struct_define(const char *name, ...);
__attribute__((__nonnull__ (2)))
VALUE rb_struct_define_under(VALUE space, const char *name, ...);
VALUE rb_struct_alloc(VALUE klass, VALUE values);
VALUE rb_struct_initialize(VALUE self, VALUE values);
VALUE rb_struct_getmember(VALUE self, ID key);
VALUE rb_struct_s_members(VALUE klass);
VALUE rb_struct_members(VALUE self);
VALUE rb_struct_alloc_noinit(VALUE klass);
VALUE rb_struct_define_without_accessor(const char *name, VALUE super, rb_alloc_func_t func, ...);
__attribute__((__nonnull__ (2)))
VALUE rb_struct_define_without_accessor_under(VALUE outer, const char *class_name, VALUE super, rb_alloc_func_t alloc, ...);




struct timeval;
void rb_thread_schedule(void);
int rb_thread_wait_fd(int fd);
int rb_thread_fd_writable(int fd);
void rb_thread_fd_close(int fd);
int rb_thread_alone(void);
void rb_thread_sleep(int sec);
void rb_thread_sleep_forever(void);
void rb_thread_sleep_deadly(void);
VALUE rb_thread_stop(void);
VALUE rb_thread_wakeup(VALUE thread);
VALUE rb_thread_wakeup_alive(VALUE thread);
VALUE rb_thread_run(VALUE thread);
VALUE rb_thread_kill(VALUE thread);
__attribute__((__nonnull__ (1)))
VALUE rb_thread_create(VALUE (*f)(void *g), void *g);
void rb_thread_wait_for(struct timeval time);
VALUE rb_thread_current(void);
VALUE rb_thread_main(void);
VALUE rb_thread_local_aref(VALUE thread, ID key);
VALUE rb_thread_local_aset(VALUE thread, ID key, VALUE val);
void rb_thread_atfork(void);
void rb_thread_atfork_before_exec(void);
VALUE rb_exec_recursive(VALUE (*f)(VALUE g, VALUE h, int r), VALUE g, VALUE h);
VALUE rb_exec_recursive_paired(VALUE (*f)(VALUE g, VALUE h, int r), VALUE g, VALUE p, VALUE h);
VALUE rb_exec_recursive_outer(VALUE (*f)(VALUE g, VALUE h, int r), VALUE g, VALUE h);
VALUE rb_exec_recursive_paired_outer(VALUE (*f)(VALUE g, VALUE h, int r), VALUE g, VALUE p, VALUE h);
typedef void rb_unblock_function_t(void *);
typedef VALUE rb_blocking_function_t(void *);
void rb_thread_check_ints(void);
int rb_thread_interrupted(VALUE thval);
VALUE rb_mutex_new(void);
VALUE rb_mutex_locked_p(VALUE mutex);
VALUE rb_mutex_trylock(VALUE mutex);
VALUE rb_mutex_lock(VALUE mutex);
VALUE rb_mutex_unlock(VALUE mutex);
VALUE rb_mutex_sleep(VALUE self, VALUE timeout);
VALUE rb_mutex_synchronize(VALUE mutex, VALUE (*func)(VALUE arg), VALUE arg);




struct timespec;
struct timeval;
__attribute__((__nonnull__ ()))
void rb_timespec_now(struct timespec *ts);
VALUE rb_time_new(time_t sec, long usec);
VALUE rb_time_nano_new(time_t sec, long nsec);
__attribute__((__nonnull__ ()))
VALUE rb_time_timespec_new(const struct timespec *ts, int offset);
VALUE rb_time_num_new(VALUE timev, VALUE off);
struct timeval rb_time_interval(VALUE num);
struct timeval rb_time_timeval(VALUE time);
struct timespec rb_time_timespec(VALUE time);
struct timespec rb_time_timespec_interval(VALUE num);
VALUE rb_time_utc_offset(VALUE time);




VALUE rb_mod_name(VALUE mod);
VALUE rb_class_path(VALUE mod);
VALUE rb_class_path_cached(VALUE mod);
__attribute__((__nonnull__ ()))
void rb_set_class_path(VALUE klass, VALUE space, const char *name);
void rb_set_class_path_string(VALUE klass, VALUE space, VALUE name);
VALUE rb_path_to_class(VALUE path);
__attribute__((__nonnull__ ()))
VALUE rb_path2class(const char *path);
VALUE rb_class_name(VALUE obj);
VALUE rb_autoload_load(VALUE space, ID name);
VALUE rb_autoload_p(VALUE space, ID name);
VALUE rb_f_trace_var(int argc, const VALUE *argv);
VALUE rb_f_untrace_var(int argc, const VALUE *argv);
VALUE rb_f_global_variables(void);
void rb_alias_variable(ID dst, ID src);
void rb_free_generic_ivar(VALUE obj);
VALUE rb_ivar_get(VALUE obj, ID name);
VALUE rb_ivar_set(VALUE obj, ID name, VALUE val);
VALUE rb_ivar_defined(VALUE obj, ID name);
void rb_ivar_foreach(VALUE obj, int (*func)(ID name, VALUE val, st_data_t arg), st_data_t arg);
st_index_t rb_ivar_count(VALUE obj);
VALUE rb_attr_get(VALUE obj, ID name);
VALUE rb_obj_instance_variables(VALUE obj);
VALUE rb_obj_remove_instance_variable(VALUE obj, VALUE name);
void *rb_mod_const_at(VALUE, void*);
void *rb_mod_const_of(VALUE, void*);
VALUE rb_const_list(void*);
VALUE rb_mod_constants(int argc, const VALUE *argv, VALUE recv);
VALUE rb_mod_remove_const(VALUE space, VALUE name);
int rb_const_defined(VALUE space, ID name);
int rb_const_defined_at(VALUE space, ID name);
int rb_const_defined_from(VALUE space, ID name);
VALUE rb_const_get(VALUE space, ID name);
VALUE rb_const_get_at(VALUE space, ID name);
VALUE rb_const_get_from(VALUE space, ID name);
void rb_const_set(VALUE space, ID name, VALUE val);
VALUE rb_const_remove(VALUE space, ID name);
VALUE rb_cvar_defined(VALUE klass, ID name);
void rb_cvar_set(VALUE klass, ID name, VALUE val);
VALUE rb_cvar_get(VALUE klass, ID name);
__attribute__((__nonnull__ ()))
VALUE rb_cvar_find(VALUE klass, ID name, VALUE *front);
__attribute__((__nonnull__ ()))
void rb_cv_set(VALUE klass, const char *name, VALUE val);
__attribute__((__nonnull__ ()))
VALUE rb_cv_get(VALUE klass, const char *name);
__attribute__((__nonnull__ ()))
void rb_define_class_variable(VALUE, const char*, VALUE);
VALUE rb_mod_class_variables(int argc, const VALUE *argv, VALUE recv);
VALUE rb_mod_remove_cvar(VALUE mod, VALUE name);


int ruby_native_thread_p(void);
__attribute__((__nonnull__ (3)))
__attribute__((__format__(__printf__, 3, 4)))
int ruby_snprintf(char *str, size_t n, char const *fmt, ...);
__attribute__((__nonnull__ (3)))
__attribute__((__format__(__printf__, 3, 0)))
int ruby_vsnprintf(char *str, size_t n, char const *fmt, va_list ap);



extern int __sigismember (__const __sigset_t *, int);
extern int __sigaddset (__sigset_t *, int);
extern int __sigdelset (__sigset_t *, int);

typedef __sig_atomic_t sig_atomic_t;

typedef union sigval
  {
    int sival_int;
    void *sival_ptr;
  } sigval_t;
typedef struct siginfo
  {
    int si_signo;
    int si_errno;
    int si_code;
    union
      {
 int _pad[((128 / sizeof (int)) - 4)];
 struct
   {
     __pid_t si_pid;
     __uid_t si_uid;
   } _kill;
 struct
   {
     int si_tid;
     int si_overrun;
     sigval_t si_sigval;
   } _timer;
 struct
   {
     __pid_t si_pid;
     __uid_t si_uid;
     sigval_t si_sigval;
   } _rt;
 struct
   {
     __pid_t si_pid;
     __uid_t si_uid;
     int si_status;
     __clock_t si_utime;
     __clock_t si_stime;
   } _sigchld;
 struct
   {
     void *si_addr;
   } _sigfault;
 struct
   {
     long int si_band;
     int si_fd;
   } _sigpoll;
      } _sifields;
  } siginfo_t;
enum
{
  SI_ASYNCNL = -60,
  SI_TKILL = -6,
  SI_SIGIO,
  SI_ASYNCIO,
  SI_MESGQ,
  SI_TIMER,
  SI_QUEUE,
  SI_USER,
  SI_KERNEL = 0x80
};
enum
{
  ILL_ILLOPC = 1,
  ILL_ILLOPN,
  ILL_ILLADR,
  ILL_ILLTRP,
  ILL_PRVOPC,
  ILL_PRVREG,
  ILL_COPROC,
  ILL_BADSTK
};
enum
{
  FPE_INTDIV = 1,
  FPE_INTOVF,
  FPE_FLTDIV,
  FPE_FLTOVF,
  FPE_FLTUND,
  FPE_FLTRES,
  FPE_FLTINV,
  FPE_FLTSUB
};
enum
{
  SEGV_MAPERR = 1,
  SEGV_ACCERR
};
enum
{
  BUS_ADRALN = 1,
  BUS_ADRERR,
  BUS_OBJERR
};
enum
{
  TRAP_BRKPT = 1,
  TRAP_TRACE
};
enum
{
  CLD_EXITED = 1,
  CLD_KILLED,
  CLD_DUMPED,
  CLD_TRAPPED,
  CLD_STOPPED,
  CLD_CONTINUED
};
enum
{
  POLL_IN = 1,
  POLL_OUT,
  POLL_MSG,
  POLL_ERR,
  POLL_PRI,
  POLL_HUP
};
typedef struct sigevent
  {
    sigval_t sigev_value;
    int sigev_signo;
    int sigev_notify;
    union
      {
 int _pad[((64 / sizeof (int)) - 4)];
 __pid_t _tid;
 struct
   {
     void (*_function) (sigval_t);
     void *_attribute;
   } _sigev_thread;
      } _sigev_un;
  } sigevent_t;
enum
{
  SIGEV_SIGNAL = 0,
  SIGEV_NONE,
  SIGEV_THREAD,
  SIGEV_THREAD_ID = 4
};
typedef void (*__sighandler_t) (int);
extern __sighandler_t __sysv_signal (int __sig, __sighandler_t __handler)
     __attribute__ ((__nothrow__));
extern __sighandler_t sysv_signal (int __sig, __sighandler_t __handler)
     __attribute__ ((__nothrow__));

extern __sighandler_t signal (int __sig, __sighandler_t __handler)
     __attribute__ ((__nothrow__));

extern __sighandler_t bsd_signal (int __sig, __sighandler_t __handler)
     __attribute__ ((__nothrow__));
extern int kill (__pid_t __pid, int __sig) __attribute__ ((__nothrow__));
extern int killpg (__pid_t __pgrp, int __sig) __attribute__ ((__nothrow__));

extern int raise (int __sig) __attribute__ ((__nothrow__));

extern __sighandler_t ssignal (int __sig, __sighandler_t __handler)
     __attribute__ ((__nothrow__));
extern int gsignal (int __sig) __attribute__ ((__nothrow__));
extern void psignal (int __sig, __const char *__s);
extern void psiginfo (__const siginfo_t *__pinfo, __const char *__s);
extern int __sigpause (int __sig_or_mask, int __is_sig);
extern int sigpause (int __sig) __asm__ ("__xpg_sigpause");
extern int sigblock (int __mask) __attribute__ ((__nothrow__)) __attribute__ ((__deprecated__));
extern int sigsetmask (int __mask) __attribute__ ((__nothrow__)) __attribute__ ((__deprecated__));
extern int siggetmask (void) __attribute__ ((__nothrow__)) __attribute__ ((__deprecated__));
typedef __sighandler_t sighandler_t;
typedef __sighandler_t sig_t;
extern int sigemptyset (sigset_t *__set) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int sigfillset (sigset_t *__set) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int sigaddset (sigset_t *__set, int __signo) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int sigdelset (sigset_t *__set, int __signo) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int sigismember (__const sigset_t *__set, int __signo)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int sigisemptyset (__const sigset_t *__set) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int sigandset (sigset_t *__set, __const sigset_t *__left,
        __const sigset_t *__right) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2, 3)));
extern int sigorset (sigset_t *__set, __const sigset_t *__left,
       __const sigset_t *__right) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2, 3)));
struct sigaction
  {
    union
      {
 __sighandler_t sa_handler;
 void (*sa_sigaction) (int, siginfo_t *, void *);
      }
    __sigaction_handler;
    __sigset_t sa_mask;
    int sa_flags;
    void (*sa_restorer) (void);
  };
extern int sigprocmask (int __how, __const sigset_t *__restrict __set,
   sigset_t *__restrict __oset) __attribute__ ((__nothrow__));
extern int sigsuspend (__const sigset_t *__set) __attribute__ ((__nonnull__ (1)));
extern int sigaction (int __sig, __const struct sigaction *__restrict __act,
        struct sigaction *__restrict __oact) __attribute__ ((__nothrow__));
extern int sigpending (sigset_t *__set) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int sigwait (__const sigset_t *__restrict __set, int *__restrict __sig)
     __attribute__ ((__nonnull__ (1, 2)));
extern int sigwaitinfo (__const sigset_t *__restrict __set,
   siginfo_t *__restrict __info) __attribute__ ((__nonnull__ (1)));
extern int sigtimedwait (__const sigset_t *__restrict __set,
    siginfo_t *__restrict __info,
    __const struct timespec *__restrict __timeout)
     __attribute__ ((__nonnull__ (1)));
extern int sigqueue (__pid_t __pid, int __sig, __const union sigval __val)
     __attribute__ ((__nothrow__));
extern __const char *__const _sys_siglist[65];
extern __const char *__const sys_siglist[65];
struct sigvec
  {
    __sighandler_t sv_handler;
    int sv_mask;
    int sv_flags;
  };
extern int sigvec (int __sig, __const struct sigvec *__vec,
     struct sigvec *__ovec) __attribute__ ((__nothrow__));
struct _fpreg
{
  unsigned short significand[4];
  unsigned short exponent;
};
struct _fpxreg
{
  unsigned short significand[4];
  unsigned short exponent;
  unsigned short padding[3];
};
struct _xmmreg
{
  __uint32_t element[4];
};
struct _fpstate
{
  __uint16_t cwd;
  __uint16_t swd;
  __uint16_t ftw;
  __uint16_t fop;
  __uint64_t rip;
  __uint64_t rdp;
  __uint32_t mxcsr;
  __uint32_t mxcr_mask;
  struct _fpxreg _st[8];
  struct _xmmreg _xmm[16];
  __uint32_t padding[24];
};
struct sigcontext
{
  unsigned long r8;
  unsigned long r9;
  unsigned long r10;
  unsigned long r11;
  unsigned long r12;
  unsigned long r13;
  unsigned long r14;
  unsigned long r15;
  unsigned long rdi;
  unsigned long rsi;
  unsigned long rbp;
  unsigned long rbx;
  unsigned long rdx;
  unsigned long rax;
  unsigned long rcx;
  unsigned long rsp;
  unsigned long rip;
  unsigned long eflags;
  unsigned short cs;
  unsigned short gs;
  unsigned short fs;
  unsigned short __pad0;
  unsigned long err;
  unsigned long trapno;
  unsigned long oldmask;
  unsigned long cr2;
  struct _fpstate * fpstate;
  unsigned long __reserved1 [8];
};
extern int sigreturn (struct sigcontext *__scp) __attribute__ ((__nothrow__));
extern int siginterrupt (int __sig, int __interrupt) __attribute__ ((__nothrow__));
struct sigstack
  {
    void *ss_sp;
    int ss_onstack;
  };
enum
{
  SS_ONSTACK = 1,
  SS_DISABLE
};
typedef struct sigaltstack
  {
    void *ss_sp;
    int ss_flags;
    size_t ss_size;
  } stack_t;
typedef long int greg_t;
typedef greg_t gregset_t[23];
enum
{
  REG_R8 = 0,
  REG_R9,
  REG_R10,
  REG_R11,
  REG_R12,
  REG_R13,
  REG_R14,
  REG_R15,
  REG_RDI,
  REG_RSI,
  REG_RBP,
  REG_RBX,
  REG_RDX,
  REG_RAX,
  REG_RCX,
  REG_RSP,
  REG_RIP,
  REG_EFL,
  REG_CSGSFS,
  REG_ERR,
  REG_TRAPNO,
  REG_OLDMASK,
  REG_CR2
};
struct _libc_fpxreg
{
  unsigned short int significand[4];
  unsigned short int exponent;
  unsigned short int padding[3];
};
struct _libc_xmmreg
{
  __uint32_t element[4];
};
struct _libc_fpstate
{
  __uint16_t cwd;
  __uint16_t swd;
  __uint16_t ftw;
  __uint16_t fop;
  __uint64_t rip;
  __uint64_t rdp;
  __uint32_t mxcsr;
  __uint32_t mxcr_mask;
  struct _libc_fpxreg _st[8];
  struct _libc_xmmreg _xmm[16];
  __uint32_t padding[24];
};
typedef struct _libc_fpstate *fpregset_t;
typedef struct
  {
    gregset_t gregs;
    fpregset_t fpregs;
    unsigned long __reserved1 [8];
} mcontext_t;
typedef struct ucontext
  {
    unsigned long int uc_flags;
    struct ucontext *uc_link;
    stack_t uc_stack;
    mcontext_t uc_mcontext;
    __sigset_t uc_sigmask;
    struct _libc_fpstate __fpregs_mem;
  } ucontext_t;
extern int sigstack (struct sigstack *__ss, struct sigstack *__oss)
     __attribute__ ((__nothrow__)) __attribute__ ((__deprecated__));
extern int sigaltstack (__const struct sigaltstack *__restrict __ss,
   struct sigaltstack *__restrict __oss) __attribute__ ((__nothrow__));
extern int sighold (int __sig) __attribute__ ((__nothrow__));
extern int sigrelse (int __sig) __attribute__ ((__nothrow__));
extern int sigignore (int __sig) __attribute__ ((__nothrow__));
extern __sighandler_t sigset (int __sig, __sighandler_t __disp) __attribute__ ((__nothrow__));
extern int pthread_sigmask (int __how,
       __const __sigset_t *__restrict __newmask,
       __sigset_t *__restrict __oldmask)__attribute__ ((__nothrow__));
extern int pthread_kill (pthread_t __threadid, int __signo) __attribute__ ((__nothrow__));
extern int pthread_sigqueue (pthread_t __threadid, int __signo,
        const union sigval __value) __attribute__ ((__nothrow__));
extern int __libc_current_sigrtmin (void) __attribute__ ((__nothrow__));
extern int __libc_current_sigrtmax (void) __attribute__ ((__nothrow__));


typedef long int __jmp_buf[8];
struct __jmp_buf_tag
  {
    __jmp_buf __jmpbuf;
    int __mask_was_saved;
    __sigset_t __saved_mask;
  };

typedef struct __jmp_buf_tag jmp_buf[1];
extern int setjmp (jmp_buf __env) __attribute__ ((__nothrow__));

extern int __sigsetjmp (struct __jmp_buf_tag __env[1], int __savemask) __attribute__ ((__nothrow__));
extern int _setjmp (struct __jmp_buf_tag __env[1]) __attribute__ ((__nothrow__));

extern void longjmp (struct __jmp_buf_tag __env[1], int __val)
     __attribute__ ((__nothrow__)) __attribute__ ((__noreturn__));

extern void _longjmp (struct __jmp_buf_tag __env[1], int __val)
     __attribute__ ((__nothrow__)) __attribute__ ((__noreturn__));
typedef struct __jmp_buf_tag sigjmp_buf[1];
extern void siglongjmp (sigjmp_buf __env, int __val)
     __attribute__ ((__nothrow__)) __attribute__ ((__noreturn__));

static inline char *container_of_or_null_(void *member_ptr, size_t offset)
{
 return member_ptr ? (char *)member_ptr - offset : ((void *)0);
}
struct list_node
{
 struct list_node *next, *prev;
};
struct list_head
{
 struct list_node n;
};
static inline void list_head_init(struct list_head *h)
{
 h->n.next = h->n.prev = &h->n;
}
static inline void list_node_init(struct list_node *n)
{
 n->next = n->prev = n;
}
static inline void list_add_after_(struct list_head *h,
       struct list_node *p,
       struct list_node *n,
       const char *abortstr)
{
 n->next = p->next;
 n->prev = p;
 p->next->prev = n;
 p->next = n;
 (void)((void)abortstr, h);
}
static inline void list_add_(struct list_head *h,
        struct list_node *n,
        const char *abortstr)
{
 list_add_after_(h, &h->n, n, abortstr);
}
static inline void list_add_before_(struct list_head *h,
        struct list_node *p,
        struct list_node *n,
        const char *abortstr)
{
 n->next = p;
 n->prev = p->prev;
 p->prev->next = n;
 p->prev = n;
 (void)((void)abortstr, h);
}
static inline void list_add_tail_(struct list_head *h,
      struct list_node *n,
      const char *abortstr)
{
 list_add_before_(h, &h->n, n, abortstr);
}
static inline int list_empty_(const struct list_head *h, const char* abortstr)
{
 (void)((void)abortstr, h);
 return h->n.next == &h->n;
}
static inline _Bool list_empty_nocheck(const struct list_head *h)
{
 return h->n.next == &h->n;
}
static inline void list_del_(struct list_node *n, const char* abortstr)
{
 (void)((void)abortstr, n);
 n->next->prev = n->prev;
 n->prev->next = n->next;
}
static inline void list_del_init_(struct list_node *n, const char *abortstr)
{
 list_del_(n, abortstr);
 list_node_init(n);
}
static inline void list_del_from(struct list_head *h, struct list_node *n)
{
 ((void) (0));
 list_del_(n, "./ccan/list/list.h" ":" "329");
}
static inline void list_swap_(struct list_node *o,
         struct list_node *n,
         const char* abortstr)
{
 (void)((void)abortstr, o);
 *n = *o;
 n->next->prev = n;
 n->prev->next = n;
}
static inline const void *list_top_(const struct list_head *h, size_t off)
{
 if (list_empty_(h, "./ccan/list/list.h" ":" "399"))
  return ((void *)0);
 return (const char *)h->n.next - off;
}
static inline const void *list_pop_(const struct list_head *h, size_t off)
{
 struct list_node *n;
 if (list_empty_(h, "./ccan/list/list.h" ":" "425"))
  return ((void *)0);
 n = h->n.next;
 list_del_(n, "./ccan/list/list.h" ":" "428");
 return (const char *)n - off;
}
static inline const void *list_tail_(const struct list_head *h, size_t off)
{
 if (list_empty_(h, "./ccan/list/list.h" ":" "451"))
  return ((void *)0);
 return (const char *)h->n.prev - off;
}
static inline void list_append_list_(struct list_head *to,
         struct list_head *from,
         const char *abortstr)
{
 struct list_node *from_tail = ((void)abortstr, from)->n.prev;
 struct list_node *to_tail = ((void)abortstr, to)->n.prev;
 to->n.prev = from_tail;
 from_tail->next = &to->n;
 to_tail->next = &from->n;
 from->n.prev = to_tail;
 list_del_(&from->n, "./ccan/list/list.h" ":" "600");
 list_head_init(from);
}
static inline void list_prepend_list_(struct list_head *to,
          struct list_head *from,
          const char *abortstr)
{
 struct list_node *from_tail = ((void)abortstr, from)->n.prev;
 struct list_node *to_head = ((void)abortstr, to)->n.next;
 to->n.next = &from->n;
 from->n.prev = &to->n;
 to_head->prev = from_tail;
 from_tail->next = to_head;
 list_del_(&from->n, "./ccan/list/list.h" ":" "632");
 list_head_init(from);
}
static inline void *list_node_to_off_(struct list_node *node, size_t off)
{
 return (void *)((char *)node - off);
}
static inline struct list_node *list_node_from_off_(void *ptr, size_t off)
{
 return (struct list_node *)((char *)ptr + off);
}
static inline void *list_entry_or_null(const struct list_head *h,
           const struct list_node *n,
           size_t off)
{
 if (n == &h->n)
  return ((void *)0);
 return (char *)n - off;
}
enum ruby_id_types {
    RUBY_ID_STATIC_SYM = 0x01,
    RUBY_ID_LOCAL = 0x00,
    RUBY_ID_INSTANCE = (0x01<<1),
    RUBY_ID_GLOBAL = (0x03<<1),
    RUBY_ID_ATTRSET = (0x04<<1),
    RUBY_ID_CONST = (0x05<<1),
    RUBY_ID_CLASS = (0x06<<1),
    RUBY_ID_JUNK = (0x07<<1),
    RUBY_ID_INTERNAL = RUBY_ID_JUNK,
    RUBY_ID_SCOPE_SHIFT = 4,
    RUBY_ID_SCOPE_MASK = (~(~0U<<(RUBY_ID_SCOPE_SHIFT-1))<<1)
};
enum ruby_method_ids {
    idDot2 = 128,
    idDot3 = 129,
    idUPlus = 132,
    idUMinus = 133,
    idPow = 134,
    idCmp = 135,
    idPLUS = '+',
    idMINUS = '-',
    idMULT = '*',
    idDIV = '/',
    idMOD = '%',
    idLTLT = 136,
    idGTGT = 137,
    idLT = '<',
    idLE = 138,
    idGT = '>',
    idGE = 139,
    idEq = 140,
    idEqq = 141,
    idNeq = 142,
    idNot = '!',
    idAnd = '&',
    idOr = '|',
    idBackquote = '`',
    idEqTilde = 143,
    idNeqTilde = 144,
    idAREF = 145,
    idASET = 146,
    idCOLON2 = 147,
    idANDOP = 148,
    idOROP = 149,
    idANDDOT = 150,
    tPRESERVED_ID_BEGIN = 150,
    idNilP,
    idNULL,
    idEmptyP,
    idEqlP,
    idRespond_to,
    idRespond_to_missing,
    idIFUNC,
    idCFUNC,
    id_core_set_method_alias,
    id_core_set_variable_alias,
    id_core_undef_method,
    id_core_define_method,
    id_core_define_singleton_method,
    id_core_set_postexe,
    id_core_hash_merge_ptr,
    id_core_hash_merge_kwd,
    id_core_raise,
    id_core_sprintf,
    id_debug_created_info,
    tPRESERVED_ID_END,
    tTOKEN_LOCAL_BEGIN = tPRESERVED_ID_END-1,
    tMax,
    tMin,
    tFreeze,
    tInspect,
    tIntern,
    tObject_id,
    tConst_missing,
    tMethodMissing,
    tMethod_added,
    tSingleton_method_added,
    tMethod_removed,
    tSingleton_method_removed,
    tMethod_undefined,
    tSingleton_method_undefined,
    tLength,
    tSize,
    tGets,
    tSucc,
    tEach,
    tProc,
    tLambda,
    tSend,
    t__send__,
    t__attached__,
    t__recursive_key__,
    tInitialize,
    tInitialize_copy,
    tInitialize_clone,
    tInitialize_dup,
    tTo_int,
    tTo_ary,
    tTo_str,
    tTo_sym,
    tTo_hash,
    tTo_proc,
    tTo_io,
    tTo_a,
    tTo_s,
    tTo_i,
    tTo_f,
    tTo_r,
    tBt,
    tBt_locations,
    tCall,
    tMesg,
    tException,
    tLocals,
    tNOT,
    tAND,
    tOR,
    tDiv,
    tDivmod,
    tFdiv,
    tQuo,
    tName,
    tNil,
    tUScore,
    tNUMPARAM_1,
    tNUMPARAM_2,
    tNUMPARAM_3,
    tNUMPARAM_4,
    tNUMPARAM_5,
    tNUMPARAM_6,
    tNUMPARAM_7,
    tNUMPARAM_8,
    tNUMPARAM_9,
    tTOKEN_LOCAL_END,
    tTOKEN_INSTANCE_BEGIN = tTOKEN_LOCAL_END-1,
    tTOKEN_INSTANCE_END,
    tTOKEN_GLOBAL_BEGIN = tTOKEN_INSTANCE_END-1,
    tLASTLINE,
    tBACKREF,
    tERROR_INFO,
    tTOKEN_GLOBAL_END,
    tTOKEN_CONST_BEGIN = tTOKEN_GLOBAL_END-1,
    tTOKEN_CONST_END,
    tTOKEN_CLASS_BEGIN = tTOKEN_CONST_END-1,
    tTOKEN_CLASS_END,
    tTOKEN_ATTRSET_BEGIN = tTOKEN_CLASS_END-1,
    tTOKEN_ATTRSET_END,
    tNEXT_ID = tTOKEN_ATTRSET_END,
    idMax = ((tMax<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idMin = ((tMin<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idFreeze = ((tFreeze<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idInspect = ((tInspect<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idIntern = ((tIntern<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idObject_id = ((tObject_id<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idConst_missing = ((tConst_missing<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idMethodMissing = ((tMethodMissing<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idMethod_added = ((tMethod_added<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idSingleton_method_added = ((tSingleton_method_added<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idMethod_removed = ((tMethod_removed<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idSingleton_method_removed = ((tSingleton_method_removed<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idMethod_undefined = ((tMethod_undefined<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idSingleton_method_undefined = ((tSingleton_method_undefined<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idLength = ((tLength<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idSize = ((tSize<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idGets = ((tGets<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idSucc = ((tSucc<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idEach = ((tEach<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idProc = ((tProc<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idLambda = ((tLambda<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idSend = ((tSend<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    id__send__ = ((t__send__<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    id__attached__ = ((t__attached__<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    id__recursive_key__ = ((t__recursive_key__<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idInitialize = ((tInitialize<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idInitialize_copy = ((tInitialize_copy<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idInitialize_clone = ((tInitialize_clone<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idInitialize_dup = ((tInitialize_dup<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idTo_int = ((tTo_int<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idTo_ary = ((tTo_ary<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idTo_str = ((tTo_str<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idTo_sym = ((tTo_sym<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idTo_hash = ((tTo_hash<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idTo_proc = ((tTo_proc<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idTo_io = ((tTo_io<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idTo_a = ((tTo_a<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idTo_s = ((tTo_s<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idTo_i = ((tTo_i<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idTo_f = ((tTo_f<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idTo_r = ((tTo_r<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idBt = ((tBt<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idBt_locations = ((tBt_locations<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idCall = ((tCall<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idMesg = ((tMesg<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idException = ((tException<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idLocals = ((tLocals<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idNOT = ((tNOT<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idAND = ((tAND<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idOR = ((tOR<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idDiv = ((tDiv<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idDivmod = ((tDivmod<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idFdiv = ((tFdiv<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idQuo = ((tQuo<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idName = ((tName<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idNil = ((tNil<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idUScore = ((tUScore<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idNUMPARAM_1 = ((tNUMPARAM_1<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idNUMPARAM_2 = ((tNUMPARAM_2<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idNUMPARAM_3 = ((tNUMPARAM_3<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idNUMPARAM_4 = ((tNUMPARAM_4<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idNUMPARAM_5 = ((tNUMPARAM_5<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idNUMPARAM_6 = ((tNUMPARAM_6<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idNUMPARAM_7 = ((tNUMPARAM_7<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idNUMPARAM_8 = ((tNUMPARAM_8<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idNUMPARAM_9 = ((tNUMPARAM_9<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_LOCAL|RUBY_ID_STATIC_SYM),
    idLASTLINE = ((tLASTLINE<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_GLOBAL|RUBY_ID_STATIC_SYM),
    idBACKREF = ((tBACKREF<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_GLOBAL|RUBY_ID_STATIC_SYM),
    idERROR_INFO = ((tERROR_INFO<<RUBY_ID_SCOPE_SHIFT)|RUBY_ID_GLOBAL|RUBY_ID_STATIC_SYM),
    tLAST_OP_ID = tPRESERVED_ID_END-1,
    idLAST_OP_ID = tLAST_OP_ID >> RUBY_ID_SCOPE_SHIFT
};
void rb_obj_info_dump(VALUE obj);
void rb_obj_info_dump_loc(VALUE obj, const char *file, int line, const char *func);


void ruby_debug_breakpoint(void);
__attribute__((__format__(__printf__, (1), (2)))) void ruby_debug_printf(const char*, ...);


VALUE rb_ary_last(int, const VALUE *, VALUE);
void rb_ary_set_len(VALUE, long);
void rb_ary_delete_same(VALUE, VALUE);
VALUE rb_ary_tmp_new_fill(long capa);
VALUE rb_ary_at(VALUE, VALUE);
size_t rb_ary_memsize(VALUE);
VALUE rb_to_array_type(VALUE obj);
VALUE rb_to_array(VALUE obj);
void rb_ary_cancel_sharing(VALUE ary);
static inline VALUE rb_ary_entry_internal(VALUE ary, long offset);
static inline _Bool ARY_PTR_USING_P(VALUE ary);
static inline void RARY_TRANSIENT_SET(VALUE ary);
static inline void RARY_TRANSIENT_UNSET(VALUE ary);


VALUE rb_ary_tmp_new_from_values(VALUE, long, const VALUE *);
VALUE rb_check_to_array(VALUE ary);
VALUE rb_ary_behead(VALUE, long);
VALUE rb_ary_aref1(VALUE ary, VALUE i);
struct rb_execution_context_struct;
VALUE rb_ec_ary_new_from_values(struct rb_execution_context_struct *ec, long n, const VALUE *elts);


static inline VALUE
rb_ary_entry_internal(VALUE ary, long offset)
{
    long len = rb_array_len(ary);
    const VALUE *ptr = rb_array_const_ptr_transient(ary);
    if (len == 0) return ((VALUE)RUBY_Qnil);
    if (offset < 0) {
        offset += len;
        if (offset < 0) return ((VALUE)RUBY_Qnil);
    }
    else if (len <= offset) {
        return ((VALUE)RUBY_Qnil);
    }
    return ptr[offset];
}
static inline _Bool
ARY_PTR_USING_P(VALUE ary)
{
    return RB_FL_TEST_RAW(ary, ((VALUE)RUBY_FL_USER14));
}
static inline void
RARY_TRANSIENT_SET(VALUE ary)
{
    RB_FL_SET_RAW(ary, RARRAY_TRANSIENT_FLAG);
}
static inline void
RARY_TRANSIENT_UNSET(VALUE ary)
{
    RB_FL_UNSET_RAW(ary, RARRAY_TRANSIENT_FLAG);
}
__attribute__((__pure__))
__attribute__((__artificial__))
static inline VALUE
RARRAY_AREF(VALUE ary, long i)
{
    ((void)0);
    return rb_array_const_ptr_transient(ary)[i];
}
typedef unsigned long long rb_serial_t;
struct rb_callable_method_entry_struct;
struct rb_method_definition_struct;
struct rb_execution_context_struct;
struct rb_control_frame_struct;
struct rb_callinfo;
enum method_missing_reason {
    MISSING_NOENTRY = 0x00,
    MISSING_PRIVATE = 0x01,
    MISSING_PROTECTED = 0x02,
    MISSING_FCALL = 0x04,
    MISSING_VCALL = 0x08,
    MISSING_SUPER = 0x10,
    MISSING_MISSING = 0x20,
    MISSING_NONE = 0x40
};
rb_serial_t rb_next_class_serial(void);
VALUE rb_obj_is_thread(VALUE obj);
void rb_vm_mark(void *ptr);
void rb_vm_each_stack_value(void *ptr, void (*cb)(VALUE, void*), void *ctx);
__attribute__((__pure__)) VALUE rb_vm_top_self(void);
void rb_vm_inc_const_missing_count(void);
const void **rb_vm_get_insns_address_table(void);
VALUE rb_source_location(int *pline);
const char *rb_source_location_cstr(int *pline);
static void rb_vm_pop_cfunc_frame(void);
int rb_vm_add_root_module(VALUE module);
void rb_vm_check_redefinition_by_prepend(VALUE klass);
int rb_vm_check_optimizable_mid(VALUE mid);
VALUE rb_yield_refine_block(VALUE refinement, VALUE refinements);
static VALUE ruby_vm_special_exception_copy(VALUE);
__attribute__((__pure__)) st_table *rb_vm_fstring_table(void);


VALUE rb_vm_exec(struct rb_execution_context_struct *, _Bool);


VALUE rb_current_realfilepath(void);
VALUE rb_check_block_call(VALUE, ID, int, const VALUE *, rb_block_call_func_t, VALUE);
typedef void rb_check_funcall_hook(int, VALUE, ID, int, const VALUE *, VALUE);
VALUE rb_check_funcall_with_hook(VALUE recv, ID mid, int argc, const VALUE *argv,
                                 rb_check_funcall_hook *hook, VALUE arg);
VALUE rb_check_funcall_with_hook_kw(VALUE recv, ID mid, int argc, const VALUE *argv,
                                 rb_check_funcall_hook *hook, VALUE arg, int kw_splat);
const char *rb_type_str(enum ruby_value_type type);
VALUE rb_check_funcall_default(VALUE, ID, int, const VALUE *, VALUE);
VALUE rb_check_funcall_basic_kw(VALUE, ID, VALUE, int, const VALUE*, int);
VALUE rb_yield_1(VALUE val);
VALUE rb_yield_force_blockarg(VALUE values);
VALUE rb_lambda_call(VALUE obj, ID mid, int argc, const VALUE *argv,
                     rb_block_call_func_t bl_proc, int min_argc, int max_argc,
                     VALUE data2);
void rb_check_stack_overflow(void);
VALUE rb_equal_opt(VALUE obj1, VALUE obj2);
VALUE rb_eql_opt(VALUE obj1, VALUE obj2);
struct rb_iseq_struct;


const struct rb_callcache *rb_vm_search_method_slowpath(const struct rb_callinfo *ci, VALUE klass);


struct rb_execution_context_struct;


int rb_ec_obj_respond_to(struct rb_execution_context_struct *ec, VALUE obj, ID id, int priv);


void rb_print_backtrace(void);
VALUE rb_vm_thread_backtrace(int argc, const VALUE *argv, VALUE thval);
VALUE rb_vm_thread_backtrace_locations(int argc, const VALUE *argv, VALUE thval);
VALUE rb_vm_backtrace(int argc, const VALUE * argv, struct rb_execution_context_struct * ec);
VALUE rb_vm_backtrace_locations(int argc, const VALUE * argv, struct rb_execution_context_struct * ec);
VALUE rb_make_backtrace(void);
void rb_backtrace_print_as_bugreport(void);
int rb_backtrace_p(VALUE obj);
VALUE rb_backtrace_to_str_ary(VALUE obj);
VALUE rb_backtrace_to_location_ary(VALUE obj);
void rb_backtrace_each(VALUE (*iter)(VALUE recv, VALUE str), VALUE output);
int rb_frame_info_p(VALUE obj);
int rb_get_node_id_from_frame_info(VALUE obj);
const struct rb_iseq_struct *rb_get_iseq_from_frame_info(VALUE obj);


VALUE rb_ec_backtrace_object(const struct rb_execution_context_struct *ec);
void rb_backtrace_use_iseq_first_lineno_for_last_location(VALUE self);


struct rb_execution_context_struct;
struct rb_objspace;
typedef struct ractor_newobj_size_pool_cache {
    struct RVALUE *freelist;
    struct heap_page *using_page;
} rb_ractor_newobj_size_pool_cache_t;
typedef struct ractor_newobj_cache {
    rb_ractor_newobj_size_pool_cache_t size_pool_caches[1];
} rb_ractor_newobj_cache_t;
extern VALUE *ruby_initial_gc_stress_ptr;
extern int ruby_disable_gc;
__attribute__((__malloc__)) void *ruby_mimmalloc(size_t size);
void ruby_mimfree(void *ptr);
void rb_objspace_set_event_hook(const rb_event_flag_t event);
VALUE rb_objspace_gc_enable(struct rb_objspace *);
VALUE rb_objspace_gc_disable(struct rb_objspace *);
void ruby_gc_set_params(void);
void rb_copy_wb_protected_attribute(VALUE dest, VALUE obj);
__attribute__((__alloc_align__(1)))
__attribute__((__malloc__)) void *rb_aligned_malloc(size_t, size_t) __attribute__((__alloc_size__ (2)));
size_t rb_size_mul_or_raise(size_t, size_t, VALUE);
size_t rb_size_mul_add_or_raise(size_t, size_t, size_t, VALUE);
__attribute__((__malloc__)) void *rb_xmalloc_mul_add(size_t, size_t, size_t);
void *rb_xrealloc_mul_add(const void *, size_t, size_t, size_t);
__attribute__((__malloc__)) void *rb_xmalloc_mul_add_mul(size_t, size_t, size_t, size_t);
__attribute__((__malloc__)) void *rb_xcalloc_mul_add_mul(size_t, size_t, size_t, size_t);
static inline void *ruby_sized_xrealloc_inlined(void *ptr, size_t new_size, size_t old_size) __attribute__((__returns_nonnull__)) __attribute__((__alloc_size__ (2)));
static inline void *ruby_sized_xrealloc2_inlined(void *ptr, size_t new_count, size_t elemsiz, size_t old_count) __attribute__((__returns_nonnull__)) __attribute__((__alloc_size__ (2, 3)));
static inline void ruby_sized_xfree_inlined(void *ptr, size_t size);
VALUE rb_class_allocate_instance(VALUE klass);
void rb_gc_ractor_newobj_cache_clear(rb_ractor_newobj_cache_t *newobj_cache);
size_t rb_gc_obj_slot_size(VALUE obj);
_Bool rb_gc_size_allocatable_p(size_t size);
int rb_objspace_garbage_object_p(VALUE obj);


const char *rb_objspace_data_type_name(VALUE obj);
VALUE rb_wb_protected_newobj_of(VALUE, VALUE, size_t);
VALUE rb_wb_unprotected_newobj_of(VALUE, VALUE, size_t);
VALUE rb_ec_wb_protected_newobj_of(struct rb_execution_context_struct *ec, VALUE klass, VALUE flags, size_t);
size_t rb_obj_memsize_of(VALUE);
void rb_gc_verify_internal_consistency(void);
size_t rb_obj_gc_flags(VALUE, ID[], size_t);
void rb_gc_mark_values(long n, const VALUE *values);
void rb_gc_mark_vm_stack_values(long n, const VALUE *values);
void *ruby_sized_xrealloc(void *ptr, size_t new_size, size_t old_size) __attribute__((__returns_nonnull__)) __attribute__((__alloc_size__ (2)));
void *ruby_sized_xrealloc2(void *ptr, size_t new_count, size_t element_size, size_t old_count) __attribute__((__returns_nonnull__)) __attribute__((__alloc_size__ (2, 3)));
void ruby_sized_xfree(void *x, size_t size);




int rb_ec_stack_check(struct rb_execution_context_struct *ec);
void rb_gc_writebarrier_remember(VALUE obj);
const char *rb_obj_info(VALUE obj);


static inline void *
ruby_sized_xrealloc_inlined(void *ptr, size_t new_size, size_t old_size)
{
    return ruby_xrealloc(ptr, new_size);
}
static inline void *
ruby_sized_xrealloc2_inlined(void *ptr, size_t new_count, size_t elemsiz, size_t old_count)
{
    return ruby_xrealloc2(ptr, new_count, elemsiz);
}
static inline void
ruby_sized_xfree_inlined(void *ptr, size_t size)
{
    ruby_xfree(ptr);
}
enum imemo_type {
    imemo_env = 0,
    imemo_cref = 1,
    imemo_svar = 2,
    imemo_throw_data = 3,
    imemo_ifunc = 4,
    imemo_memo = 5,
    imemo_ment = 6,
    imemo_iseq = 7,
    imemo_tmpbuf = 8,
    imemo_ast = 9,
    imemo_parser_strterm = 10,
    imemo_callinfo = 11,
    imemo_callcache = 12,
    imemo_constcache = 13,
};
struct vm_svar {
    VALUE flags;
    const VALUE cref_or_me;
    const VALUE lastline;
    const VALUE backref;
    const VALUE others;
};
struct vm_throw_data {
    VALUE flags;
    VALUE reserved;
    const VALUE throw_obj;
    const struct rb_control_frame_struct *catch_frame;
    int throw_state;
};
struct vm_ifunc_argc {
    int min, max;
};
struct vm_ifunc {
    VALUE flags;
    VALUE reserved;
    rb_block_call_func_t func;
    const void *data;
    struct vm_ifunc_argc argc;
};
struct rb_imemo_tmpbuf_struct {
    VALUE flags;
    VALUE reserved;
    VALUE *ptr;
    struct rb_imemo_tmpbuf_struct *next;
    size_t cnt;
};
struct MEMO {
    VALUE flags;
    VALUE reserved;
    const VALUE v1;
    const VALUE v2;
    union {
        long cnt;
        long state;
        const VALUE value;
        void (*func)(void);
    } u3;
};
typedef struct rb_imemo_tmpbuf_struct rb_imemo_tmpbuf_t;
VALUE rb_imemo_new(enum imemo_type type, VALUE v1, VALUE v2, VALUE v3, VALUE v0);
rb_imemo_tmpbuf_t *rb_imemo_tmpbuf_parser_heap(void *buf, rb_imemo_tmpbuf_t *old_heap, size_t cnt);
struct vm_ifunc *rb_vm_ifunc_new(rb_block_call_func_t func, const void *data, int min_argc, int max_argc);
void rb_strterm_mark(VALUE obj);
static inline enum imemo_type imemo_type(VALUE imemo);
static inline int imemo_type_p(VALUE imemo, enum imemo_type imemo_type);
static inline _Bool imemo_throw_data_p(VALUE imemo);
static inline struct vm_ifunc *rb_vm_ifunc_proc_new(rb_block_call_func_t func, const void *data);
static inline VALUE rb_imemo_tmpbuf_auto_free_pointer(void);
static inline void *RB_IMEMO_TMPBUF_PTR(VALUE v);
static inline void *rb_imemo_tmpbuf_set_ptr(VALUE v, void *ptr);
static inline VALUE rb_imemo_tmpbuf_auto_free_pointer_new_from_an_RString(VALUE str);
static inline void MEMO_V1_SET(struct MEMO *m, VALUE v);
static inline void MEMO_V2_SET(struct MEMO *m, VALUE v);


VALUE rb_imemo_new(enum imemo_type type, VALUE v1, VALUE v2, VALUE v3, VALUE v0);
const char *rb_imemo_name(enum imemo_type type);


static inline enum imemo_type
imemo_type(VALUE imemo)
{
    return (((struct RBasic *)(imemo))->flags >> ((VALUE)RUBY_FL_USHIFT)) & 0x0f;
}
static inline int
imemo_type_p(VALUE imemo, enum imemo_type imemo_type)
{
    if ((__builtin_expect(!!(!RB_SPECIAL_CONST_P(imemo)), 1))) {
        const VALUE mask = (0x0f << ((VALUE)RUBY_FL_USHIFT)) | RUBY_T_MASK;
        const VALUE expected_type = (imemo_type << ((VALUE)RUBY_FL_USHIFT)) | RUBY_T_IMEMO;
        return expected_type == (((struct RBasic *)(imemo))->flags & mask);
    }
    else {
        return 0;
    }
}
static inline _Bool
imemo_throw_data_p(VALUE imemo)
{
    return RB_TYPE_P(imemo, RUBY_T_IMEMO);
}
static inline struct vm_ifunc *
rb_vm_ifunc_proc_new(rb_block_call_func_t func, const void *data)
{
    return rb_vm_ifunc_new(func, data, 0, (-1));
}
static inline VALUE
rb_imemo_tmpbuf_auto_free_pointer(void)
{
    return rb_imemo_new(imemo_tmpbuf, 0, 0, 0, 0);
}
static inline void *
RB_IMEMO_TMPBUF_PTR(VALUE v)
{
    const struct rb_imemo_tmpbuf_struct *p = (const void *)v;
    return p->ptr;
}
static inline void *
rb_imemo_tmpbuf_set_ptr(VALUE v, void *ptr)
{
    return ((rb_imemo_tmpbuf_t *)v)->ptr = ptr;
}
static inline VALUE
rb_imemo_tmpbuf_auto_free_pointer_new_from_an_RString(VALUE str)
{
    const void *src;
    VALUE imemo;
    rb_imemo_tmpbuf_t *tmpbuf;
    void *dst;
    size_t len;
    rb_string_value(&(str));
    imemo = rb_imemo_tmpbuf_auto_free_pointer();
    tmpbuf = (rb_imemo_tmpbuf_t *)imemo;
    len = RSTRING_LEN(str);
    src = RSTRING_PTR(str);
    dst = ruby_xmalloc(len);
    ruby_nonempty_memcpy(dst, src, len);
    tmpbuf->ptr = dst;
    return imemo;
}
static inline void
MEMO_V1_SET(struct MEMO *m, VALUE v)
{
    rb_obj_write((VALUE)(m), __extension__({
   ;
   ; __typeof__((VALUE *)(&m->v1)) unaligned_member_access_result = ((VALUE *)(&m->v1));
   ; unaligned_member_access_result; }), (VALUE)(v), "./internal/imemo.h", 234);
}
static inline void
MEMO_V2_SET(struct MEMO *m, VALUE v)
{
    rb_obj_write((VALUE)(m), __extension__({
   ;
   ; __typeof__((VALUE *)(&m->v2)) unaligned_member_access_result = ((VALUE *)(&m->v2));
   ; unaligned_member_access_result; }), (VALUE)(v), "./internal/imemo.h", 240);
}
typedef enum {
    METHOD_VISI_UNDEF = 0x00,
    METHOD_VISI_PUBLIC = 0x01,
    METHOD_VISI_PRIVATE = 0x02,
    METHOD_VISI_PROTECTED = 0x03,
    METHOD_VISI_MASK = 0x03
} rb_method_visibility_t;
typedef struct rb_scope_visi_struct {
    rb_method_visibility_t method_visi : 3;
    unsigned int module_func : 1;
} rb_scope_visibility_t;
typedef struct rb_cref_struct {
    VALUE flags;
    VALUE refinements;
    VALUE klass_or_self;
    struct rb_cref_struct * next;
    const rb_scope_visibility_t scope_visi;
} rb_cref_t;
typedef struct rb_method_entry_struct {
    VALUE flags;
    VALUE defined_class;
    struct rb_method_definition_struct * const def;
    ID called_id;
    VALUE owner;
} rb_method_entry_t;
typedef struct rb_callable_method_entry_struct {
    VALUE flags;
    const VALUE defined_class;
    struct rb_method_definition_struct * const def;
    ID called_id;
    const VALUE owner;
} rb_callable_method_entry_t;
static inline void
METHOD_ENTRY_VISI_SET(rb_method_entry_t *me, rb_method_visibility_t visi)
{
    ((void)0);
    me->flags = (me->flags & ~(((VALUE)RUBY_FL_USER4) | ((VALUE)RUBY_FL_USER5))) | (visi << ((((VALUE)RUBY_FL_USHIFT) + 4)+0));
}
static inline void
METHOD_ENTRY_BASIC_SET(rb_method_entry_t *me, unsigned int basic)
{
    ((void)0);
    me->flags = (me->flags & ~(((VALUE)RUBY_FL_USER6) )) | (basic << ((((VALUE)RUBY_FL_USHIFT) + 4)+2));
}
static inline void
METHOD_ENTRY_FLAGS_SET(rb_method_entry_t *me, rb_method_visibility_t visi, unsigned int basic)
{
    ((void)0);
    ((void)0);
    me->flags =
      (me->flags & ~(((VALUE)RUBY_FL_USER4)|((VALUE)RUBY_FL_USER5)|((VALUE)RUBY_FL_USER6))) |
        ((visi << ((((VALUE)RUBY_FL_USHIFT) + 4)+0)) | (basic << ((((VALUE)RUBY_FL_USHIFT) + 4)+2)));
}
static inline void
METHOD_ENTRY_FLAGS_COPY(rb_method_entry_t *dst, const rb_method_entry_t *src)
{
    dst->flags =
      (dst->flags & ~(((VALUE)RUBY_FL_USER4)|((VALUE)RUBY_FL_USER5)|((VALUE)RUBY_FL_USER6))) |
        (src->flags & (((VALUE)RUBY_FL_USER4)|((VALUE)RUBY_FL_USER5)|((VALUE)RUBY_FL_USER6)));
}
typedef enum {
    VM_METHOD_TYPE_ISEQ,
    VM_METHOD_TYPE_CFUNC,
    VM_METHOD_TYPE_ATTRSET,
    VM_METHOD_TYPE_IVAR,
    VM_METHOD_TYPE_BMETHOD,
    VM_METHOD_TYPE_ZSUPER,
    VM_METHOD_TYPE_ALIAS,
    VM_METHOD_TYPE_UNDEF,
    VM_METHOD_TYPE_NOTIMPLEMENTED,
    VM_METHOD_TYPE_OPTIMIZED,
    VM_METHOD_TYPE_MISSING,
    VM_METHOD_TYPE_REFINED,
   
} rb_method_type_t;
__extension__ _Static_assert(VM_METHOD_TYPE_REFINED <= (1<<4), "VM_METHOD_TYPE_MINIMUM_BITS" ": " "VM_METHOD_TYPE_REFINED <= (1<<VM_METHOD_TYPE_MINIMUM_BITS)");
typedef struct rb_iseq_struct rb_iseq_t;
typedef struct rb_method_iseq_struct {
    const rb_iseq_t * iseqptr;
    rb_cref_t * cref;
} rb_method_iseq_t;
typedef struct rb_method_cfunc_struct {
    VALUE (*func)();
    VALUE (*invoker)(VALUE recv, int argc, const VALUE *argv, VALUE (*func)());
    int argc;
} rb_method_cfunc_t;
typedef struct rb_method_attr_struct {
    ID id;
    VALUE location;
} rb_method_attr_t;
typedef struct rb_method_alias_struct {
    struct rb_method_entry_struct * original_me;
} rb_method_alias_t;
typedef struct rb_method_refined_struct {
    struct rb_method_entry_struct * orig_me;
    VALUE owner;
} rb_method_refined_t;
typedef struct rb_method_bmethod_struct {
    VALUE proc;
    struct rb_hook_list_struct *hooks;
    VALUE defined_ractor;
} rb_method_bmethod_t;
enum method_optimized_type {
    OPTIMIZED_METHOD_TYPE_SEND,
    OPTIMIZED_METHOD_TYPE_CALL,
    OPTIMIZED_METHOD_TYPE_BLOCK_CALL,
    OPTIMIZED_METHOD_TYPE_STRUCT_AREF,
    OPTIMIZED_METHOD_TYPE_STRUCT_ASET,
    OPTIMIZED_METHOD_TYPE__MAX
};
typedef struct rb_method_optimized {
    enum method_optimized_type type;
    unsigned int index;
} rb_method_optimized_t;
struct rb_method_definition_struct {
    rb_method_type_t type : 4;
    unsigned int iseq_overload: 1;
    int alias_count : 27;
    int complemented_count : 28;
    unsigned int no_redef_warning: 1;
    union {
        rb_method_iseq_t iseq;
        rb_method_cfunc_t cfunc;
        rb_method_attr_t attr;
        rb_method_alias_t alias;
        rb_method_refined_t refined;
        rb_method_bmethod_t bmethod;
        rb_method_optimized_t optimized;
    } body;
    ID original_id;
    uintptr_t method_serial;
};
struct rb_id_table;
typedef struct rb_method_definition_struct rb_method_definition_t;
__extension__ _Static_assert(__builtin_offsetof (rb_method_definition_t, body)==8, "sizeof_method_def" ": " "offsetof(rb_method_definition_t, body)==8");
void rb_add_method(VALUE klass, ID mid, rb_method_type_t type, void *option, rb_method_visibility_t visi);
void rb_add_method_cfunc(VALUE klass, ID mid, VALUE (*func)(), int argc, rb_method_visibility_t visi);
void rb_add_method_iseq(VALUE klass, ID mid, const rb_iseq_t *iseq, rb_cref_t *cref, rb_method_visibility_t visi);
void rb_add_method_optimized(VALUE klass, ID mid, enum method_optimized_type, unsigned int index, rb_method_visibility_t visi);
void rb_add_refined_method_entry(VALUE refined_class, ID mid);
rb_method_entry_t *rb_method_entry_set(VALUE klass, ID mid, const rb_method_entry_t *, rb_method_visibility_t noex);
rb_method_entry_t *rb_method_entry_create(ID called_id, VALUE klass, rb_method_visibility_t visi, const rb_method_definition_t *def);
const rb_method_entry_t *rb_method_entry_at(VALUE obj, ID id);
const rb_method_entry_t *rb_method_entry(VALUE klass, ID id);
const rb_method_entry_t *rb_method_entry_with_refinements(VALUE klass, ID id, VALUE *defined_class);
const rb_method_entry_t *rb_method_entry_without_refinements(VALUE klass, ID id, VALUE *defined_class);
const rb_method_entry_t *rb_resolve_refined_method(VALUE refinements, const rb_method_entry_t *me);


const rb_method_entry_t *rb_resolve_me_location(const rb_method_entry_t *, VALUE[5]);


const rb_callable_method_entry_t *rb_callable_method_entry(VALUE klass, ID id);
const rb_callable_method_entry_t *rb_callable_method_entry_with_refinements(VALUE klass, ID id, VALUE *defined_class);
const rb_callable_method_entry_t *rb_callable_method_entry_without_refinements(VALUE klass, ID id, VALUE *defined_class);
int rb_method_entry_arity(const rb_method_entry_t *me);
int rb_method_entry_eq(const rb_method_entry_t *m1, const rb_method_entry_t *m2);
st_index_t rb_hash_method_entry(st_index_t hash, const rb_method_entry_t *me);
VALUE rb_method_entry_location(const rb_method_entry_t *me);
void rb_free_method_entry(const rb_method_entry_t *me);
const rb_method_entry_t *rb_method_entry_clone(const rb_method_entry_t *me);
const rb_callable_method_entry_t *rb_method_entry_complement_defined_class(const rb_method_entry_t *src_me, ID called_id, VALUE defined_class);
void rb_method_entry_copy(rb_method_entry_t *dst, const rb_method_entry_t *src);
void rb_method_table_insert(VALUE klass, struct rb_id_table *table, ID method_id, const rb_method_entry_t *me);
void rb_scope_visibility_set(rb_method_visibility_t);
VALUE rb_unnamed_parameters(int arity);
void rb_clear_method_cache(VALUE klass_or_module, ID mid);
void rb_clear_method_cache_all(void);
enum node_type {
    NODE_SCOPE,
    NODE_BLOCK,
    NODE_IF,
    NODE_UNLESS,
    NODE_CASE,
    NODE_CASE2,
    NODE_CASE3,
    NODE_WHEN,
    NODE_IN,
    NODE_WHILE,
    NODE_UNTIL,
    NODE_ITER,
    NODE_FOR,
    NODE_FOR_MASGN,
    NODE_BREAK,
    NODE_NEXT,
    NODE_REDO,
    NODE_RETRY,
    NODE_BEGIN,
    NODE_RESCUE,
    NODE_RESBODY,
    NODE_ENSURE,
    NODE_AND,
    NODE_OR,
    NODE_MASGN,
    NODE_LASGN,
    NODE_DASGN,
    NODE_GASGN,
    NODE_IASGN,
    NODE_CDECL,
    NODE_CVASGN,
    NODE_OP_ASGN1,
    NODE_OP_ASGN2,
    NODE_OP_ASGN_AND,
    NODE_OP_ASGN_OR,
    NODE_OP_CDECL,
    NODE_CALL,
    NODE_OPCALL,
    NODE_FCALL,
    NODE_VCALL,
    NODE_QCALL,
    NODE_SUPER,
    NODE_ZSUPER,
    NODE_LIST,
    NODE_ZLIST,
    NODE_VALUES,
    NODE_HASH,
    NODE_RETURN,
    NODE_YIELD,
    NODE_LVAR,
    NODE_DVAR,
    NODE_GVAR,
    NODE_IVAR,
    NODE_CONST,
    NODE_CVAR,
    NODE_NTH_REF,
    NODE_BACK_REF,
    NODE_MATCH,
    NODE_MATCH2,
    NODE_MATCH3,
    NODE_LIT,
    NODE_STR,
    NODE_DSTR,
    NODE_XSTR,
    NODE_DXSTR,
    NODE_EVSTR,
    NODE_DREGX,
    NODE_ONCE,
    NODE_ARGS,
    NODE_ARGS_AUX,
    NODE_OPT_ARG,
    NODE_KW_ARG,
    NODE_POSTARG,
    NODE_ARGSCAT,
    NODE_ARGSPUSH,
    NODE_SPLAT,
    NODE_BLOCK_PASS,
    NODE_DEFN,
    NODE_DEFS,
    NODE_ALIAS,
    NODE_VALIAS,
    NODE_UNDEF,
    NODE_CLASS,
    NODE_MODULE,
    NODE_SCLASS,
    NODE_COLON2,
    NODE_COLON3,
    NODE_DOT2,
    NODE_DOT3,
    NODE_FLIP2,
    NODE_FLIP3,
    NODE_SELF,
    NODE_NIL,
    NODE_TRUE,
    NODE_FALSE,
    NODE_ERRINFO,
    NODE_DEFINED,
    NODE_POSTEXE,
    NODE_DSYM,
    NODE_ATTRASGN,
    NODE_LAMBDA,
    NODE_ARYPTN,
    NODE_HSHPTN,
    NODE_FNDPTN,
    NODE_LAST
};
typedef struct rb_code_position_struct {
    int lineno;
    int column;
} rb_code_position_t;
typedef struct rb_code_location_struct {
    rb_code_position_t beg_pos;
    rb_code_position_t end_pos;
} rb_code_location_t;
static inline rb_code_location_t
code_loc_gen(const rb_code_location_t *loc1, const rb_code_location_t *loc2)
{
    rb_code_location_t loc;
    loc.beg_pos = loc1->beg_pos;
    loc.end_pos = loc2->end_pos;
    return loc;
}
typedef struct rb_ast_id_table {
    int size;
    ID ids[];
} rb_ast_id_table_t;
typedef struct RNode {
    VALUE flags;
    union {
 struct RNode *node;
 ID id;
 VALUE value;
 rb_ast_id_table_t *tbl;
    } u1;
    union {
 struct RNode *node;
 ID id;
 long argc;
 VALUE value;
    } u2;
    union {
 struct RNode *node;
 ID id;
 long state;
 struct rb_args_info *args;
 struct rb_ary_pattern_info *apinfo;
 struct rb_fnd_pattern_info *fpinfo;
 VALUE value;
    } u3;
    rb_code_location_t nd_loc;
    int node_id;
} NODE;
VALUE rb_node_case_when_optimizable_literal(const NODE *const node);


typedef struct node_buffer_struct node_buffer_t;
typedef struct rb_ast_body_struct {
    const NODE *root;
    VALUE compile_option;
    VALUE script_lines;
} rb_ast_body_t;
typedef struct rb_ast_struct {
    VALUE flags;
    node_buffer_t *node_buffer;
    rb_ast_body_t body;
} rb_ast_t;
rb_ast_t *rb_ast_new(void);
void rb_ast_mark(rb_ast_t*);
void rb_ast_update_references(rb_ast_t*);
void rb_ast_dispose(rb_ast_t*);
void rb_ast_free(rb_ast_t*);
size_t rb_ast_memsize(const rb_ast_t*);
void rb_ast_add_mark_object(rb_ast_t*, VALUE);
NODE *rb_ast_newnode(rb_ast_t*, enum node_type type);
void rb_ast_delete_node(rb_ast_t*, NODE *n);
rb_ast_id_table_t *rb_ast_new_local_table(rb_ast_t*, int);
rb_ast_id_table_t *rb_ast_resize_latest_local_table(rb_ast_t*, int);
VALUE rb_parser_new(void);
VALUE rb_parser_end_seen_p(VALUE);
VALUE rb_parser_encoding(VALUE);
VALUE rb_parser_set_yydebug(VALUE, VALUE);
VALUE rb_parser_dump_tree(const NODE *node, int comment);
void rb_parser_set_options(VALUE, int, int, int, int);
rb_ast_t *rb_parser_compile_string(VALUE, const char*, VALUE, int);
rb_ast_t *rb_parser_compile_string_path(VALUE vparser, VALUE fname, VALUE src, int line);
rb_ast_t *rb_parser_compile_file_path(VALUE vparser, VALUE fname, VALUE input, int line);
rb_ast_t *rb_parser_compile_generic(VALUE vparser, VALUE (*lex_gets)(VALUE, int), VALUE fname, VALUE input, int line);
void rb_node_init(NODE *n, enum node_type type, VALUE a0, VALUE a1, VALUE a2);
const char *ruby_node_name(int node);
const struct kwtable *rb_reserved_word(const char *, unsigned int);
struct rb_args_info {
    NODE *pre_init;
    NODE *post_init;
    int pre_args_num;
    int post_args_num;
    ID first_post_arg;
    ID rest_arg;
    ID block_arg;
    NODE *kw_args;
    NODE *kw_rest_arg;
    NODE *opt_args;
    unsigned int no_kwarg: 1;
    unsigned int ruby2_keywords: 1;
    VALUE imemo;
};
struct rb_ary_pattern_info {
    NODE *pre_args;
    NODE *rest_arg;
    NODE *post_args;
};
struct rb_fnd_pattern_info {
    NODE *pre_rest_arg;
    NODE *args;
    NODE *post_rest_arg;
};
struct parser_params;
void *rb_parser_malloc(struct parser_params *, size_t);
void *rb_parser_realloc(struct parser_params *, void *, size_t);
void *rb_parser_calloc(struct parser_params *, size_t, size_t);
void rb_parser_free(struct parser_params *, void *);
__attribute__((__format__(__printf__, (2), (3)))) void rb_parser_printf(struct parser_params *parser, const char *fmt, ...);
void rb_ast_node_type_change(NODE *n, enum node_type type);


static inline VALUE
rb_node_set_type(NODE *n, enum node_type t)
{
    return (n)->flags=(((n)->flags&~(((VALUE)0x7f)<<8))|((((unsigned long)(t))<<8)&(((VALUE)0x7f)<<8)));
}
static inline _Bool
nd_type_p(const NODE *n, enum node_type t)
{
    return (enum node_type)((int) (((n)->flags & (((VALUE)0x7f)<<8))>>8)) == t;
}
typedef unsigned int rb_atomic_t;
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline rb_atomic_t
rbimpl_atomic_fetch_add(volatile rb_atomic_t *ptr, rb_atomic_t val)
{
    return __atomic_fetch_add(ptr, val, 5);
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline void
rbimpl_atomic_add(volatile rb_atomic_t *ptr, rb_atomic_t val)
{
    __atomic_add_fetch(ptr, val, 5);
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline void
rbimpl_atomic_size_add(volatile size_t *ptr, size_t val)
{
    __atomic_add_fetch(ptr, val, 5);
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline void
rbimpl_atomic_inc(volatile rb_atomic_t *ptr)
{
    rbimpl_atomic_add(ptr, 1);
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline void
rbimpl_atomic_size_inc(volatile size_t *ptr)
{
    rbimpl_atomic_size_add(ptr, 1);
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline rb_atomic_t
rbimpl_atomic_fetch_sub(volatile rb_atomic_t *ptr, rb_atomic_t val)
{
    return __atomic_fetch_sub(ptr, val, 5);
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline void
rbimpl_atomic_sub(volatile rb_atomic_t *ptr, rb_atomic_t val)
{
    __atomic_sub_fetch(ptr, val, 5);
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline void
rbimpl_atomic_size_sub(volatile size_t *ptr, size_t val)
{
    __atomic_sub_fetch(ptr, val, 5);
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline void
rbimpl_atomic_dec(volatile rb_atomic_t *ptr)
{
    rbimpl_atomic_sub(ptr, 1);
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline void
rbimpl_atomic_size_dec(volatile size_t *ptr)
{
    rbimpl_atomic_size_sub(ptr, 1);
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline void
rbimpl_atomic_or(volatile rb_atomic_t *ptr, rb_atomic_t val)
{
    __atomic_or_fetch(ptr, val, 5);
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline rb_atomic_t
rbimpl_atomic_exchange(volatile rb_atomic_t *ptr, rb_atomic_t val)
{
    return __atomic_exchange_n(ptr, val, 5);
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline size_t
rbimpl_atomic_size_exchange(volatile size_t *ptr, size_t val)
{
    return __atomic_exchange_n(ptr, val, 5);
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline void *
rbimpl_atomic_ptr_exchange(void *volatile *ptr, const void *val)
{
    __extension__ _Static_assert(sizeof *ptr == sizeof(size_t), "sizeof_voidp" ": " "sizeof *ptr == sizeof(size_t)");
    const size_t sval = ((size_t)val);
    volatile size_t *const sptr = ((volatile size_t *)ptr);
    const size_t sret = rbimpl_atomic_size_exchange(sptr, sval);
    return ((void *)sret);
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline VALUE
rbimpl_atomic_value_exchange(volatile VALUE *ptr, VALUE val)
{
    __extension__ _Static_assert(sizeof *ptr == sizeof(size_t), "sizeof_value" ": " "sizeof *ptr == sizeof(size_t)");
    const size_t sval = ((size_t)val);
    volatile size_t *const sptr = ((volatile size_t *)ptr);
    const size_t sret = rbimpl_atomic_size_exchange(sptr, sval);
    return ((VALUE)sret);
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline void
rbimpl_atomic_set(volatile rb_atomic_t *ptr, rb_atomic_t val)
{
    __atomic_store_n(ptr, val, 5);
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline rb_atomic_t
rbimpl_atomic_cas(volatile rb_atomic_t *ptr, rb_atomic_t oldval, rb_atomic_t newval)
{
    __atomic_compare_exchange_n(
        ptr, &oldval, newval, 0, 5, 5);
    return oldval;
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline size_t
rbimpl_atomic_size_cas(volatile size_t *ptr, size_t oldval, size_t newval)
{
    __atomic_compare_exchange_n(
        ptr, &oldval, newval, 0, 5, 5);
    return oldval;
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline void *
rbimpl_atomic_ptr_cas(void **ptr, const void *oldval, const void *newval)
{
    __extension__ _Static_assert(sizeof *ptr == sizeof(size_t), "sizeof_voidp" ": " "sizeof *ptr == sizeof(size_t)");
    const size_t snew = ((size_t)newval);
    const size_t sold = ((size_t)oldval);
    volatile size_t *const sptr = ((volatile size_t *)ptr);
    const size_t sret = rbimpl_atomic_size_cas(sptr, sold, snew);
    return ((void *)sret);
}
__attribute__((__artificial__))

__attribute__((__nonnull__ (1)))
static inline VALUE
rbimpl_atomic_value_cas(volatile VALUE *ptr, VALUE oldval, VALUE newval)
{
    __extension__ _Static_assert(sizeof *ptr == sizeof(size_t), "sizeof_value" ": " "sizeof *ptr == sizeof(size_t)");
    const size_t snew = ((size_t)newval);
    const size_t sold = ((size_t)oldval);
    volatile size_t *const sptr = ((volatile size_t *)ptr);
    const size_t sret = rbimpl_atomic_size_cas(sptr, sold, snew);
    return ((VALUE)sret);
}
typedef struct rb_darray_meta {
    int32_t size;
    int32_t capa;
} rb_darray_meta_t;
static inline int32_t
rb_darray_size(const void *ary)
{
    const rb_darray_meta_t *meta = ary;
    return meta ? meta->size : 0;
}
static inline int32_t
rb_darray_capa(const void *ary)
{
    const rb_darray_meta_t *meta = ary;
    return meta ? meta->capa : 0;
}
static inline void
rb_darray_free(void *ary)
{
    free(ary);
}
static inline size_t
rb_darray_buffer_size(int32_t capacity, size_t header_size, size_t element_size)
{
    if (capacity == 0) return 0;
    return header_size + (size_t)capacity * element_size;
}
static inline int
rb_darray_ensure_space(void *ptr_to_ary, size_t header_size, size_t element_size)
{
    rb_darray_meta_t **ptr_to_ptr_to_meta = ptr_to_ary;
    rb_darray_meta_t *meta = *ptr_to_ptr_to_meta;
    int32_t current_capa = rb_darray_capa(meta);
    if (rb_darray_size(meta) < current_capa) return 1;
    int32_t new_capa;
    if (current_capa == 0) {
        new_capa = 1;
    }
    else {
        int64_t doubled = 2 * (int64_t)current_capa;
        new_capa = (int32_t)doubled;
        if (new_capa != doubled) return 0;
    }
    size_t current_buffer_size = rb_darray_buffer_size(current_capa, header_size, element_size);
    size_t new_buffer_size = rb_darray_buffer_size(new_capa, header_size, element_size);
    if (new_buffer_size <= current_buffer_size) return 0;
    rb_darray_meta_t *doubled_ary = realloc(meta, new_buffer_size);
    if (!doubled_ary) return 0;
    if (meta == ((void *)0)) {
        doubled_ary->size = 0;
    }
    doubled_ary->capa = new_capa;
    ruby_nonempty_memcpy(ptr_to_ary, &doubled_ary, sizeof(doubled_ary));
    return 1;
}
static inline int
rb_darray_make_impl(void *ptr_to_ary, int32_t array_size, size_t header_size, size_t element_size)
{
    rb_darray_meta_t **ptr_to_ptr_to_meta = ptr_to_ary;
    if (array_size < 0) return 0;
    if (array_size == 0) {
        *ptr_to_ptr_to_meta = ((void *)0);
        return 1;
    }
    size_t buffer_size = rb_darray_buffer_size(array_size, header_size, element_size);
    rb_darray_meta_t *meta = calloc(buffer_size, 1);
    if (!meta) return 0;
    meta->size = array_size;
    meta->capa = array_size;
    ruby_nonempty_memcpy(ptr_to_ary, &meta, sizeof(meta));
    return 1;
}
struct sched_param
  {
    int __sched_priority;
  };

extern int clone (int (*__fn) (void *__arg), void *__child_stack,
    int __flags, void *__arg, ...) __attribute__ ((__nothrow__));
extern int unshare (int __flags) __attribute__ ((__nothrow__));
extern int sched_getcpu (void) __attribute__ ((__nothrow__));

struct __sched_param
  {
    int __sched_priority;
  };
typedef unsigned long int __cpu_mask;
typedef struct
{
  __cpu_mask __bits[1024 / (8 * sizeof (__cpu_mask))];
} cpu_set_t;

extern int __sched_cpucount (size_t __setsize, const cpu_set_t *__setp)
  __attribute__ ((__nothrow__));
extern cpu_set_t *__sched_cpualloc (size_t __count) __attribute__ ((__nothrow__)) ;
extern void __sched_cpufree (cpu_set_t *__set) __attribute__ ((__nothrow__));


extern int sched_setparam (__pid_t __pid, __const struct sched_param *__param)
     __attribute__ ((__nothrow__));
extern int sched_getparam (__pid_t __pid, struct sched_param *__param) __attribute__ ((__nothrow__));
extern int sched_setscheduler (__pid_t __pid, int __policy,
          __const struct sched_param *__param) __attribute__ ((__nothrow__));
extern int sched_getscheduler (__pid_t __pid) __attribute__ ((__nothrow__));
extern int sched_yield (void) __attribute__ ((__nothrow__));
extern int sched_get_priority_max (int __algorithm) __attribute__ ((__nothrow__));
extern int sched_get_priority_min (int __algorithm) __attribute__ ((__nothrow__));
extern int sched_rr_get_interval (__pid_t __pid, struct timespec *__t) __attribute__ ((__nothrow__));
extern int sched_setaffinity (__pid_t __pid, size_t __cpusetsize,
         __const cpu_set_t *__cpuset) __attribute__ ((__nothrow__));
extern int sched_getaffinity (__pid_t __pid, size_t __cpusetsize,
         cpu_set_t *__cpuset) __attribute__ ((__nothrow__));

enum
{
  PTHREAD_CREATE_JOINABLE,
  PTHREAD_CREATE_DETACHED
};
enum
{
  PTHREAD_MUTEX_TIMED_NP,
  PTHREAD_MUTEX_RECURSIVE_NP,
  PTHREAD_MUTEX_ERRORCHECK_NP,
  PTHREAD_MUTEX_ADAPTIVE_NP
  ,
  PTHREAD_MUTEX_NORMAL = PTHREAD_MUTEX_TIMED_NP,
  PTHREAD_MUTEX_RECURSIVE = PTHREAD_MUTEX_RECURSIVE_NP,
  PTHREAD_MUTEX_ERRORCHECK = PTHREAD_MUTEX_ERRORCHECK_NP,
  PTHREAD_MUTEX_DEFAULT = PTHREAD_MUTEX_NORMAL
  , PTHREAD_MUTEX_FAST_NP = PTHREAD_MUTEX_TIMED_NP
};
enum
{
  PTHREAD_MUTEX_STALLED,
  PTHREAD_MUTEX_STALLED_NP = PTHREAD_MUTEX_STALLED,
  PTHREAD_MUTEX_ROBUST,
  PTHREAD_MUTEX_ROBUST_NP = PTHREAD_MUTEX_ROBUST
};
enum
{
  PTHREAD_PRIO_NONE,
  PTHREAD_PRIO_INHERIT,
  PTHREAD_PRIO_PROTECT
};
enum
{
  PTHREAD_RWLOCK_PREFER_READER_NP,
  PTHREAD_RWLOCK_PREFER_WRITER_NP,
  PTHREAD_RWLOCK_PREFER_WRITER_NONRECURSIVE_NP,
  PTHREAD_RWLOCK_DEFAULT_NP = PTHREAD_RWLOCK_PREFER_READER_NP
};
enum
{
  PTHREAD_INHERIT_SCHED,
  PTHREAD_EXPLICIT_SCHED
};
enum
{
  PTHREAD_SCOPE_SYSTEM,
  PTHREAD_SCOPE_PROCESS
};
enum
{
  PTHREAD_PROCESS_PRIVATE,
  PTHREAD_PROCESS_SHARED
};
struct _pthread_cleanup_buffer
{
  void (*__routine) (void *);
  void *__arg;
  int __canceltype;
  struct _pthread_cleanup_buffer *__prev;
};
enum
{
  PTHREAD_CANCEL_ENABLE,
  PTHREAD_CANCEL_DISABLE
};
enum
{
  PTHREAD_CANCEL_DEFERRED,
  PTHREAD_CANCEL_ASYNCHRONOUS
};

extern int pthread_create (pthread_t *__restrict __newthread,
      __const pthread_attr_t *__restrict __attr,
      void *(*__start_routine) (void *),
      void *__restrict __arg) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 3)));
extern void pthread_exit (void *__retval) __attribute__ ((__noreturn__));
extern int pthread_join (pthread_t __th, void **__thread_return);
extern int pthread_tryjoin_np (pthread_t __th, void **__thread_return) __attribute__ ((__nothrow__));
extern int pthread_timedjoin_np (pthread_t __th, void **__thread_return,
     __const struct timespec *__abstime);
extern int pthread_detach (pthread_t __th) __attribute__ ((__nothrow__));
extern pthread_t pthread_self (void) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern int pthread_equal (pthread_t __thread1, pthread_t __thread2) __attribute__ ((__nothrow__));
extern int pthread_attr_init (pthread_attr_t *__attr) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_attr_destroy (pthread_attr_t *__attr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_attr_getdetachstate (__const pthread_attr_t *__attr,
     int *__detachstate)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_attr_setdetachstate (pthread_attr_t *__attr,
     int __detachstate)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_attr_getguardsize (__const pthread_attr_t *__attr,
          size_t *__guardsize)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_attr_setguardsize (pthread_attr_t *__attr,
          size_t __guardsize)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_attr_getschedparam (__const pthread_attr_t *__restrict
           __attr,
           struct sched_param *__restrict __param)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_attr_setschedparam (pthread_attr_t *__restrict __attr,
           __const struct sched_param *__restrict
           __param) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_attr_getschedpolicy (__const pthread_attr_t *__restrict
     __attr, int *__restrict __policy)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_attr_setschedpolicy (pthread_attr_t *__attr, int __policy)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_attr_getinheritsched (__const pthread_attr_t *__restrict
      __attr, int *__restrict __inherit)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_attr_setinheritsched (pthread_attr_t *__attr,
      int __inherit)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_attr_getscope (__const pthread_attr_t *__restrict __attr,
      int *__restrict __scope)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_attr_setscope (pthread_attr_t *__attr, int __scope)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_attr_getstackaddr (__const pthread_attr_t *__restrict
          __attr, void **__restrict __stackaddr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2))) __attribute__ ((__deprecated__));
extern int pthread_attr_setstackaddr (pthread_attr_t *__attr,
          void *__stackaddr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) __attribute__ ((__deprecated__));
extern int pthread_attr_getstacksize (__const pthread_attr_t *__restrict
          __attr, size_t *__restrict __stacksize)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_attr_setstacksize (pthread_attr_t *__attr,
          size_t __stacksize)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_attr_getstack (__const pthread_attr_t *__restrict __attr,
      void **__restrict __stackaddr,
      size_t *__restrict __stacksize)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2, 3)));
extern int pthread_attr_setstack (pthread_attr_t *__attr, void *__stackaddr,
      size_t __stacksize) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_attr_setaffinity_np (pthread_attr_t *__attr,
     size_t __cpusetsize,
     __const cpu_set_t *__cpuset)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 3)));
extern int pthread_attr_getaffinity_np (__const pthread_attr_t *__attr,
     size_t __cpusetsize,
     cpu_set_t *__cpuset)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 3)));
extern int pthread_getattr_np (pthread_t __th, pthread_attr_t *__attr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern int pthread_setschedparam (pthread_t __target_thread, int __policy,
      __const struct sched_param *__param)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3)));
extern int pthread_getschedparam (pthread_t __target_thread,
      int *__restrict __policy,
      struct sched_param *__restrict __param)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 3)));
extern int pthread_setschedprio (pthread_t __target_thread, int __prio)
     __attribute__ ((__nothrow__));
extern int pthread_getname_np (pthread_t __target_thread, char *__buf,
          size_t __buflen)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern int pthread_setname_np (pthread_t __target_thread, __const char *__name)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern int pthread_getconcurrency (void) __attribute__ ((__nothrow__));
extern int pthread_setconcurrency (int __level) __attribute__ ((__nothrow__));
extern int pthread_yield (void) __attribute__ ((__nothrow__));
extern int pthread_setaffinity_np (pthread_t __th, size_t __cpusetsize,
       __const cpu_set_t *__cpuset)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3)));
extern int pthread_getaffinity_np (pthread_t __th, size_t __cpusetsize,
       cpu_set_t *__cpuset)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3)));
extern int pthread_once (pthread_once_t *__once_control,
    void (*__init_routine) (void)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_setcancelstate (int __state, int *__oldstate);
extern int pthread_setcanceltype (int __type, int *__oldtype);
extern int pthread_cancel (pthread_t __th);
extern void pthread_testcancel (void);
typedef struct
{
  struct
  {
    __jmp_buf __cancel_jmp_buf;
    int __mask_was_saved;
  } __cancel_jmp_buf[1];
  void *__pad[4];
} __pthread_unwind_buf_t __attribute__ ((__aligned__));
struct __pthread_cleanup_frame
{
  void (*__cancel_routine) (void *);
  void *__cancel_arg;
  int __do_it;
  int __cancel_type;
};
extern void __pthread_register_cancel (__pthread_unwind_buf_t *__buf)
     ;
extern void __pthread_unregister_cancel (__pthread_unwind_buf_t *__buf)
  ;
extern void __pthread_register_cancel_defer (__pthread_unwind_buf_t *__buf)
     ;
extern void __pthread_unregister_cancel_restore (__pthread_unwind_buf_t *__buf)
  ;
extern void __pthread_unwind_next (__pthread_unwind_buf_t *__buf)
     __attribute__ ((__noreturn__))
     __attribute__ ((__weak__))
     ;
struct __jmp_buf_tag;
extern int __sigsetjmp (struct __jmp_buf_tag *__env, int __savemask) __attribute__ ((__nothrow__));
extern int pthread_mutex_init (pthread_mutex_t *__mutex,
          __const pthread_mutexattr_t *__mutexattr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_mutex_destroy (pthread_mutex_t *__mutex)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_mutex_trylock (pthread_mutex_t *__mutex)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_mutex_lock (pthread_mutex_t *__mutex)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_mutex_timedlock (pthread_mutex_t *__restrict __mutex,
        __const struct timespec *__restrict
        __abstime) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_mutex_unlock (pthread_mutex_t *__mutex)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_mutex_getprioceiling (__const pthread_mutex_t *
      __restrict __mutex,
      int *__restrict __prioceiling)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_mutex_setprioceiling (pthread_mutex_t *__restrict __mutex,
      int __prioceiling,
      int *__restrict __old_ceiling)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 3)));
extern int pthread_mutex_consistent (pthread_mutex_t *__mutex)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_mutex_consistent_np (pthread_mutex_t *__mutex)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_mutexattr_init (pthread_mutexattr_t *__attr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_mutexattr_destroy (pthread_mutexattr_t *__attr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_mutexattr_getpshared (__const pthread_mutexattr_t *
      __restrict __attr,
      int *__restrict __pshared)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_mutexattr_setpshared (pthread_mutexattr_t *__attr,
      int __pshared)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_mutexattr_gettype (__const pthread_mutexattr_t *__restrict
          __attr, int *__restrict __kind)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_mutexattr_settype (pthread_mutexattr_t *__attr, int __kind)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_mutexattr_getprotocol (__const pthread_mutexattr_t *
       __restrict __attr,
       int *__restrict __protocol)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_mutexattr_setprotocol (pthread_mutexattr_t *__attr,
       int __protocol)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_mutexattr_getprioceiling (__const pthread_mutexattr_t *
          __restrict __attr,
          int *__restrict __prioceiling)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_mutexattr_setprioceiling (pthread_mutexattr_t *__attr,
          int __prioceiling)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_mutexattr_getrobust (__const pthread_mutexattr_t *__attr,
     int *__robustness)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_mutexattr_getrobust_np (__const pthread_mutexattr_t *__attr,
        int *__robustness)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_mutexattr_setrobust (pthread_mutexattr_t *__attr,
     int __robustness)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_mutexattr_setrobust_np (pthread_mutexattr_t *__attr,
        int __robustness)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_rwlock_init (pthread_rwlock_t *__restrict __rwlock,
    __const pthread_rwlockattr_t *__restrict
    __attr) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_rwlock_destroy (pthread_rwlock_t *__rwlock)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_rwlock_rdlock (pthread_rwlock_t *__rwlock)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_rwlock_tryrdlock (pthread_rwlock_t *__rwlock)
  __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_rwlock_timedrdlock (pthread_rwlock_t *__restrict __rwlock,
           __const struct timespec *__restrict
           __abstime) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_rwlock_wrlock (pthread_rwlock_t *__rwlock)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_rwlock_trywrlock (pthread_rwlock_t *__rwlock)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_rwlock_timedwrlock (pthread_rwlock_t *__restrict __rwlock,
           __const struct timespec *__restrict
           __abstime) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_rwlock_unlock (pthread_rwlock_t *__rwlock)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_rwlockattr_init (pthread_rwlockattr_t *__attr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_rwlockattr_destroy (pthread_rwlockattr_t *__attr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_rwlockattr_getpshared (__const pthread_rwlockattr_t *
       __restrict __attr,
       int *__restrict __pshared)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_rwlockattr_setpshared (pthread_rwlockattr_t *__attr,
       int __pshared)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_rwlockattr_getkind_np (__const pthread_rwlockattr_t *
       __restrict __attr,
       int *__restrict __pref)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_rwlockattr_setkind_np (pthread_rwlockattr_t *__attr,
       int __pref) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_cond_init (pthread_cond_t *__restrict __cond,
         __const pthread_condattr_t *__restrict
         __cond_attr) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_cond_destroy (pthread_cond_t *__cond)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_cond_signal (pthread_cond_t *__cond)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_cond_broadcast (pthread_cond_t *__cond)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_cond_wait (pthread_cond_t *__restrict __cond,
         pthread_mutex_t *__restrict __mutex)
     __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_cond_timedwait (pthread_cond_t *__restrict __cond,
       pthread_mutex_t *__restrict __mutex,
       __const struct timespec *__restrict
       __abstime) __attribute__ ((__nonnull__ (1, 2, 3)));
extern int pthread_condattr_init (pthread_condattr_t *__attr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_condattr_destroy (pthread_condattr_t *__attr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_condattr_getpshared (__const pthread_condattr_t *
     __restrict __attr,
     int *__restrict __pshared)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_condattr_setpshared (pthread_condattr_t *__attr,
     int __pshared) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_condattr_getclock (__const pthread_condattr_t *
          __restrict __attr,
          __clockid_t *__restrict __clock_id)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_condattr_setclock (pthread_condattr_t *__attr,
          __clockid_t __clock_id)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_spin_init (pthread_spinlock_t *__lock, int __pshared)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_spin_destroy (pthread_spinlock_t *__lock)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_spin_lock (pthread_spinlock_t *__lock)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_spin_trylock (pthread_spinlock_t *__lock)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_spin_unlock (pthread_spinlock_t *__lock)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_barrier_init (pthread_barrier_t *__restrict __barrier,
     __const pthread_barrierattr_t *__restrict
     __attr, unsigned int __count)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_barrier_destroy (pthread_barrier_t *__barrier)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_barrier_wait (pthread_barrier_t *__barrier)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_barrierattr_init (pthread_barrierattr_t *__attr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_barrierattr_destroy (pthread_barrierattr_t *__attr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_barrierattr_getpshared (__const pthread_barrierattr_t *
        __restrict __attr,
        int *__restrict __pshared)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int pthread_barrierattr_setpshared (pthread_barrierattr_t *__attr,
        int __pshared)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_key_create (pthread_key_t *__key,
          void (*__destr_function) (void *))
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern int pthread_key_delete (pthread_key_t __key) __attribute__ ((__nothrow__));
extern void *pthread_getspecific (pthread_key_t __key) __attribute__ ((__nothrow__));
extern int pthread_setspecific (pthread_key_t __key,
    __const void *__pointer) __attribute__ ((__nothrow__)) ;
extern int pthread_getcpuclockid (pthread_t __thread_id,
      __clockid_t *__clock_id)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));
extern int pthread_atfork (void (*__prepare) (void),
      void (*__parent) (void),
      void (*__child) (void)) __attribute__ ((__nothrow__));

typedef pthread_t rb_nativethread_id_t;
typedef pthread_mutex_t rb_nativethread_lock_t;
typedef pthread_cond_t rb_nativethread_cond_t;


rb_nativethread_id_t rb_nativethread_self(void);
void rb_nativethread_lock_initialize(rb_nativethread_lock_t *lock);
void rb_nativethread_lock_destroy(rb_nativethread_lock_t *lock);
void rb_nativethread_lock_lock(rb_nativethread_lock_t *lock);
void rb_nativethread_lock_unlock(rb_nativethread_lock_t *lock);
void rb_native_mutex_lock(rb_nativethread_lock_t *lock);
int rb_native_mutex_trylock(rb_nativethread_lock_t *lock);
void rb_native_mutex_unlock(rb_nativethread_lock_t *lock);
void rb_native_mutex_initialize(rb_nativethread_lock_t *lock);
void rb_native_mutex_destroy(rb_nativethread_lock_t *lock);
void rb_native_cond_signal(rb_nativethread_cond_t *cond);
void rb_native_cond_broadcast(rb_nativethread_cond_t *cond);
void rb_native_cond_wait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex);
void rb_native_cond_timedwait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex, unsigned long msec);
void rb_native_cond_initialize(rb_nativethread_cond_t *cond);
void rb_native_cond_destroy(rb_nativethread_cond_t *cond);


typedef struct native_thread_data_struct {
    union {
        struct list_node ubf;
        struct list_node gvl;
    } node;
    union
    {
        rb_nativethread_cond_t intr;
        rb_nativethread_cond_t gvlq;
    } cond;
} native_thread_data_t;
typedef struct rb_global_vm_lock_struct {
    const struct rb_thread_struct *owner;
    rb_nativethread_lock_t lock;
    struct list_head waitq;
    const struct rb_thread_struct *timer;
    int timer_err;
    rb_nativethread_cond_t switch_cond;
    rb_nativethread_cond_t switch_wait_cond;
    int need_yield;
    int wait_yield;
} rb_global_vm_lock_t;


    extern __thread struct rb_execution_context_struct *ruby_current_ec;


void *rb_allocate_sigaltstack(void);
void *rb_register_sigaltstack(void *);
void rb_vm_encoded_insn_data_table_init(void);
typedef unsigned long rb_num_t;
typedef signed long rb_snum_t;
enum ruby_tag_type {
    RUBY_TAG_NONE = 0x0,
    RUBY_TAG_RETURN = 0x1,
    RUBY_TAG_BREAK = 0x2,
    RUBY_TAG_NEXT = 0x3,
    RUBY_TAG_RETRY = 0x4,
    RUBY_TAG_REDO = 0x5,
    RUBY_TAG_RAISE = 0x6,
    RUBY_TAG_THROW = 0x7,
    RUBY_TAG_FATAL = 0x8,
    RUBY_TAG_MASK = 0xf
};
enum ruby_vm_throw_flags {
    VM_THROW_NO_ESCAPE_FLAG = 0x8000,
    VM_THROW_STATE_MASK = 0xff
};
struct rb_thread_struct;
struct rb_control_frame_struct;
typedef struct rb_compile_option_struct rb_compile_option_t;
union ic_serial_entry {
    rb_serial_t raw;
    VALUE data[2];
};
struct iseq_inline_constant_cache_entry {
    VALUE flags;
    VALUE value;
    union ic_serial_entry ic_serial;
    const rb_cref_t *ic_cref;
};
__extension__ _Static_assert((__builtin_offsetof (struct iseq_inline_constant_cache_entry, ic_cref) + sizeof(const rb_cref_t *)) <= sizeof(struct RObject), "sizeof_iseq_inline_constant_cache_entry" ": " "(offsetof(struct iseq_inline_constant_cache_entry, ic_cref) + sizeof(const rb_cref_t *)) <= sizeof(struct RObject)");
struct iseq_inline_constant_cache {
    struct iseq_inline_constant_cache_entry *entry;
    unsigned get_insn_idx;
};
struct iseq_inline_iv_cache_entry {
    struct rb_iv_index_tbl_entry *entry;
};
struct iseq_inline_cvar_cache_entry {
    struct rb_cvar_class_tbl_entry *entry;
};
union iseq_inline_storage_entry {
    struct {
 struct rb_thread_struct *running_thread;
 VALUE value;
    } once;
    struct iseq_inline_constant_cache ic_cache;
    struct iseq_inline_iv_cache_entry iv_cache;
};
struct rb_calling_info {
    const struct rb_callinfo *ci;
    const struct rb_callcache *cc;
    VALUE block_handler;
    VALUE recv;
    int argc;
    int kw_splat;
};
struct rb_execution_context_struct;
typedef struct rb_iseq_location_struct {
    VALUE pathobj;
    VALUE base_label;
    VALUE label;
    VALUE first_lineno;
    int node_id;
    rb_code_location_t code_location;
} rb_iseq_location_t;
static inline VALUE
pathobj_path(VALUE pathobj)
{
    if (RB_TYPE_P(pathobj, RUBY_T_STRING)) {
 return pathobj;
    }
    else {
 ((void)0);
 return RARRAY_AREF(pathobj, 0);
    }
}
static inline VALUE
pathobj_realpath(VALUE pathobj)
{
    if (RB_TYPE_P(pathobj, RUBY_T_STRING)) {
 return pathobj;
    }
    else {
 ((void)0);
 return RARRAY_AREF(pathobj, 1);
    }
}
struct rb_mjit_unit;
typedef struct { rb_darray_meta_t meta; struct yjit_block_version * data[]; } * rb_yjit_block_array_t;
typedef struct { rb_darray_meta_t meta; rb_yjit_block_array_t data[]; } * rb_yjit_block_array_array_t;
struct rb_iseq_constant_body {
    enum iseq_type {
 ISEQ_TYPE_TOP,
 ISEQ_TYPE_METHOD,
 ISEQ_TYPE_BLOCK,
 ISEQ_TYPE_CLASS,
 ISEQ_TYPE_RESCUE,
 ISEQ_TYPE_ENSURE,
 ISEQ_TYPE_EVAL,
 ISEQ_TYPE_MAIN,
 ISEQ_TYPE_PLAIN
    } type;
    unsigned int iseq_size;
    VALUE *iseq_encoded;
    struct {
 struct {
     unsigned int has_lead : 1;
     unsigned int has_opt : 1;
     unsigned int has_rest : 1;
     unsigned int has_post : 1;
     unsigned int has_kw : 1;
     unsigned int has_kwrest : 1;
     unsigned int has_block : 1;
     unsigned int ambiguous_param0 : 1;
     unsigned int accepts_no_kwarg : 1;
            unsigned int ruby2_keywords: 1;
 } flags;
 unsigned int size;
 int lead_num;
 int opt_num;
 int rest_start;
 int post_start;
 int post_num;
 int block_start;
 const VALUE *opt_table;
 const struct rb_iseq_param_keyword {
     int num;
     int required_num;
     int bits_start;
     int rest_start;
     const ID *table;
            VALUE *default_values;
 } *keyword;
    } param;
    rb_iseq_location_t location;
    struct iseq_insn_info {
 const struct iseq_insn_info_entry *body;
 unsigned int *positions;
 unsigned int size;
 struct succ_index_table *succ_index_table;
    } insns_info;
    const ID *local_table;
    struct iseq_catch_table *catch_table;
    const struct rb_iseq_struct *parent_iseq;
    struct rb_iseq_struct *local_iseq;
    union iseq_inline_storage_entry *is_entries;
    struct rb_call_data *call_data;
    struct {
 rb_snum_t flip_count;
        VALUE script_lines;
 VALUE coverage;
        VALUE pc2branchindex;
 VALUE *original_iseq;
    } variable;
    unsigned int local_table_size;
    unsigned int is_size;
    unsigned int ci_size;
    unsigned int stack_max;
    char catch_except_p;
    _Bool builtin_inline_p;
    struct rb_id_table *outer_variables;
    const rb_iseq_t *mandatory_only_iseq;
    VALUE (*jit_func)(struct rb_execution_context_struct *,
                      struct rb_control_frame_struct *);
    long unsigned total_calls;
    struct rb_mjit_unit *jit_unit;
    rb_yjit_block_array_array_t yjit_blocks;
};
struct rb_iseq_struct {
    VALUE flags;
    VALUE wrapper;
    struct rb_iseq_constant_body *body;
    union {
 struct iseq_compile_data *compile_data;
 struct {
     VALUE obj;
     int index;
 } loader;
        struct {
            struct rb_hook_list_struct *local_hooks;
            rb_event_flag_t global_trace_events;
        } exec;
    } aux;
};
static inline const rb_iseq_t *
rb_iseq_check(const rb_iseq_t *iseq)
{
    return iseq;
}
static inline const rb_iseq_t *
def_iseq_ptr(rb_method_definition_t *def)
{
    return rb_iseq_check(def->body.iseq.iseqptr);
}
enum ruby_special_exceptions {
    ruby_error_reenter,
    ruby_error_nomemory,
    ruby_error_sysstack,
    ruby_error_stackfatal,
    ruby_error_stream_closed,
    ruby_special_error_count
};
enum ruby_basic_operators {
    BOP_PLUS,
    BOP_MINUS,
    BOP_MULT,
    BOP_DIV,
    BOP_MOD,
    BOP_EQ,
    BOP_EQQ,
    BOP_LT,
    BOP_LE,
    BOP_LTLT,
    BOP_AREF,
    BOP_ASET,
    BOP_LENGTH,
    BOP_SIZE,
    BOP_EMPTY_P,
    BOP_NIL_P,
    BOP_SUCC,
    BOP_GT,
    BOP_GE,
    BOP_NOT,
    BOP_NEQ,
    BOP_MATCH,
    BOP_FREEZE,
    BOP_UMINUS,
    BOP_MAX,
    BOP_MIN,
    BOP_CALL,
    BOP_AND,
    BOP_OR,
    BOP_LAST_
};
struct rb_vm_struct;
typedef void rb_vm_at_exit_func(struct rb_vm_struct*);
typedef struct rb_at_exit_list {
    rb_vm_at_exit_func *func;
    struct rb_at_exit_list *next;
} rb_at_exit_list;
struct rb_objspace;
struct rb_objspace *rb_objspace_alloc(void);
void rb_objspace_free(struct rb_objspace *);
void rb_objspace_call_finalizer(struct rb_objspace *);
typedef struct rb_hook_list_struct {
    struct rb_event_hook_struct *hooks;
    rb_event_flag_t events;
    unsigned int running;
    _Bool need_clean;
    _Bool is_local;
} rb_hook_list_t;
typedef const struct rb_builtin_function *RB_BUILTIN;
typedef struct rb_vm_struct {
    VALUE self;
    struct {
        struct list_head set;
        unsigned int cnt;
        unsigned int blocking_cnt;
        struct rb_ractor_struct *main_ractor;
        struct rb_thread_struct *main_thread;
        struct {
            rb_nativethread_lock_t lock;
            struct rb_ractor_struct *lock_owner;
            unsigned int lock_rec;
            _Bool barrier_waiting;
            unsigned int barrier_cnt;
            rb_nativethread_cond_t barrier_cond;
            rb_nativethread_cond_t terminate_cond;
            _Bool terminate_waiting;
        } sync;
    } ractor;
    void *main_altstack;
    rb_serial_t fork_gen;
    rb_nativethread_lock_t waitpid_lock;
    struct list_head waiting_pids;
    struct list_head waiting_grps;
    struct list_head waiting_fds;
    volatile int ubf_async_safe;
    unsigned int running: 1;
    unsigned int thread_abort_on_exception: 1;
    unsigned int thread_report_on_exception: 1;
    unsigned int thread_ignore_deadlock: 1;
    VALUE mark_object_ary;
    const VALUE special_exceptions[ruby_special_error_count];
    VALUE top_self;
    VALUE load_path;
    VALUE load_path_snapshot;
    VALUE load_path_check_cache;
    VALUE expanded_load_path;
    VALUE loaded_features;
    VALUE loaded_features_snapshot;
    VALUE loaded_features_realpaths;
    struct st_table *loaded_features_index;
    struct st_table *loading_table;
    struct st_table *static_ext_inits;
    struct {
 VALUE cmd[65];
    } trap_list;
    struct st_table *ensure_rollback_table;
    struct rb_postponed_job_struct *postponed_job_buffer;
    rb_atomic_t postponed_job_index;
    int src_encoding_index;
    struct list_head workqueue;
    rb_nativethread_lock_t workqueue_lock;
    VALUE orig_progname, progname;
    VALUE coverages, me2counter;
    int coverage_mode;
    st_table * defined_module_hash;
    struct rb_objspace *objspace;
    rb_at_exit_list *at_exit;
    st_table *frozen_strings;
    const struct rb_builtin_function *builtin_function_table;
    int builtin_inline_index;
    struct rb_id_table *negative_cme_table;
    st_table *overloaded_cme_table;
    const struct rb_callcache *global_cc_cache_table[1023];
    struct {
 size_t thread_vm_stack_size;
 size_t thread_machine_stack_size;
 size_t fiber_vm_stack_size;
 size_t fiber_machine_stack_size;
    } default_params;
    short redefined_flag[BOP_LAST_];
} rb_vm_t;
struct rb_captured_block {
    VALUE self;
    const VALUE *ep;
    union {
 const rb_iseq_t *iseq;
 const struct vm_ifunc *ifunc;
 VALUE val;
    } code;
};
enum rb_block_handler_type {
    block_handler_type_iseq,
    block_handler_type_ifunc,
    block_handler_type_symbol,
    block_handler_type_proc
};
enum rb_block_type {
    block_type_iseq,
    block_type_ifunc,
    block_type_symbol,
    block_type_proc
};
struct rb_block {
    union {
 struct rb_captured_block captured;
 VALUE symbol;
 VALUE proc;
    } as;
    enum rb_block_type type;
};
typedef struct rb_control_frame_struct {
    const VALUE *pc;
    VALUE *sp;
    const rb_iseq_t *iseq;
    VALUE self;
    const VALUE *ep;
    const void *block_code;
    VALUE *__bp__;
    void *jit_return;
} rb_control_frame_t;
extern const rb_data_type_t ruby_threadptr_data_type;
static inline struct rb_thread_struct *
rb_thread_ptr(VALUE thval)
{
    return (struct rb_thread_struct *)rb_check_typeddata(thval, &ruby_threadptr_data_type);
}
enum rb_thread_status {
    THREAD_RUNNABLE,
    THREAD_STOPPED,
    THREAD_STOPPED_FOREVER,
    THREAD_KILLED
};
typedef void *rb_jmpbuf_t[5];
struct rb_vm_tag {
    VALUE tag;
    VALUE retval;
    rb_jmpbuf_t buf;
    struct rb_vm_tag *prev;
    enum ruby_tag_type state;
    unsigned int lock_rec;
};
__extension__ _Static_assert(__builtin_offsetof (struct rb_vm_tag, buf) > 0, "rb_vm_tag_buf_offset" ": " "offsetof(struct rb_vm_tag, buf) > 0");
__extension__ _Static_assert(__builtin_offsetof (struct rb_vm_tag, buf) + sizeof(rb_jmpbuf_t) < sizeof(struct rb_vm_tag), "rb_vm_tag_buf_end" ": " "offsetof(struct rb_vm_tag, buf) + sizeof(rb_jmpbuf_t) < sizeof(struct rb_vm_tag)");
struct rb_unblock_callback {
    rb_unblock_function_t *func;
    void *arg;
};
struct rb_mutex_struct;
typedef struct rb_ensure_entry {
    VALUE marker;
    VALUE (*e_proc)(VALUE);
    VALUE data2;
} rb_ensure_entry_t;
typedef struct rb_ensure_list {
    struct rb_ensure_list *next;
    struct rb_ensure_entry entry;
} rb_ensure_list_t;
typedef char rb_thread_id_string_t[sizeof(rb_nativethread_id_t) * 2 + 3];
typedef struct rb_fiber_struct rb_fiber_t;
struct rb_waiting_list {
    struct rb_waiting_list *next;
    struct rb_thread_struct *thread;
    struct rb_fiber_struct *fiber;
};
struct rb_execution_context_struct {
    VALUE *vm_stack;
    size_t vm_stack_size;
    rb_control_frame_t *cfp;
    struct rb_vm_tag *tag;
    rb_atomic_t interrupt_flag;
    rb_atomic_t interrupt_mask;
    rb_fiber_t *fiber_ptr;
    struct rb_thread_struct *thread_ptr;
    struct rb_id_table *local_storage;
    VALUE local_storage_recursive_hash;
    VALUE local_storage_recursive_hash_for_trace;
    const VALUE *root_lep;
    VALUE root_svar;
    rb_ensure_list_t *ensure_list;
    struct rb_trace_arg_struct *trace_arg;
    VALUE errinfo;
    VALUE passed_block_handler;
    uint8_t raised_flag;
    enum method_missing_reason method_missing_reason : 8;
    VALUE private_const_reference;
    struct {
 VALUE *stack_start;
 VALUE *stack_end;
 size_t stack_maxsize;
 __attribute__((__aligned__(8))) jmp_buf regs;
    } machine;
};
typedef struct rb_execution_context_struct rb_execution_context_t;
void rb_ec_set_vm_stack(rb_execution_context_t *ec, VALUE *stack, size_t size);
void rb_ec_initialize_vm_stack(rb_execution_context_t *ec, VALUE *stack, size_t size);
void rb_ec_clear_vm_stack(rb_execution_context_t *ec);
struct rb_ext_config {
    _Bool ractor_safe;
};
typedef struct rb_ractor_struct rb_ractor_t;
typedef struct rb_thread_struct {
    struct list_node lt_node;
    VALUE self;
    rb_ractor_t *ractor;
    rb_vm_t *vm;
    rb_execution_context_t *ec;
    VALUE last_status;
    struct rb_calling_info *calling;
    VALUE top_self;
    VALUE top_wrapper;
    rb_nativethread_id_t thread_id;
    int tid;
    enum rb_thread_status status : 2;
    unsigned int to_kill : 1;
    unsigned int abort_on_exception: 1;
    unsigned int report_on_exception: 1;
    unsigned int pending_interrupt_queue_checked: 1;
    int8_t priority;
    uint32_t running_time_us;
    native_thread_data_t native_thread_data;
    void *blocking_region_buffer;
    VALUE thgroup;
    VALUE value;
    VALUE pending_interrupt_queue;
    VALUE pending_interrupt_mask_stack;
    rb_nativethread_lock_t interrupt_lock;
    struct rb_unblock_callback unblock;
    VALUE locking_mutex;
    struct rb_mutex_struct *keeping_mutexes;
    struct rb_waiting_list *join_list;
    union {
        struct {
            VALUE proc;
            VALUE args;
            int kw_splat;
        } proc;
        struct {
            VALUE (*func)(void *);
            void *arg;
        } func;
    } invoke_arg;
    enum thread_invoke_type {
        thread_invoke_type_none = 0,
        thread_invoke_type_proc,
        thread_invoke_type_ractor_proc,
        thread_invoke_type_func
    } invoke_type;
    VALUE stat_insn_usage;
    rb_fiber_t *root_fiber;
    VALUE scheduler;
    unsigned blocking;
    VALUE name;
    struct rb_ext_config ext_config;
    void *altstack;
} rb_thread_t;
typedef enum {
    VM_DEFINECLASS_TYPE_CLASS = 0x00,
    VM_DEFINECLASS_TYPE_SINGLETON_CLASS = 0x01,
    VM_DEFINECLASS_TYPE_MODULE = 0x02,
    VM_DEFINECLASS_TYPE_MASK = 0x07
} rb_vm_defineclass_type_t;


rb_iseq_t *rb_iseq_new (const rb_ast_body_t *ast, VALUE name, VALUE path, VALUE realpath, const rb_iseq_t *parent, enum iseq_type);
rb_iseq_t *rb_iseq_new_top (const rb_ast_body_t *ast, VALUE name, VALUE path, VALUE realpath, const rb_iseq_t *parent);
rb_iseq_t *rb_iseq_new_main (const rb_ast_body_t *ast, VALUE path, VALUE realpath, const rb_iseq_t *parent, int opt);
rb_iseq_t *rb_iseq_new_eval (const rb_ast_body_t *ast, VALUE name, VALUE path, VALUE realpath, VALUE first_lineno, const rb_iseq_t *parent, int isolated_depth);
rb_iseq_t *rb_iseq_new_with_opt(const rb_ast_body_t *ast, VALUE name, VALUE path, VALUE realpath, VALUE first_lineno, const rb_iseq_t *parent, int isolated_depth,
                                enum iseq_type, const rb_compile_option_t*);
struct iseq_link_anchor;
struct rb_iseq_new_with_callback_callback_func {
    VALUE flags;
    VALUE reserved;
    void (*func)(rb_iseq_t *, struct iseq_link_anchor *, const void *);
    const void *data;
};
static inline struct rb_iseq_new_with_callback_callback_func *
rb_iseq_new_with_callback_new_callback(
    void (*func)(rb_iseq_t *, struct iseq_link_anchor *, const void *), const void *ptr)
{
    VALUE memo = rb_imemo_new(imemo_ifunc, (VALUE)func, (VALUE)ptr, ((VALUE)RUBY_Qundef), ((VALUE)RUBY_Qfalse));
    return (struct rb_iseq_new_with_callback_callback_func *)memo;
}
rb_iseq_t *rb_iseq_new_with_callback(const struct rb_iseq_new_with_callback_callback_func * ifunc,
    VALUE name, VALUE path, VALUE realpath, VALUE first_lineno,
    const rb_iseq_t *parent, enum iseq_type, const rb_compile_option_t*);
VALUE rb_iseq_disasm(const rb_iseq_t *iseq);
int rb_iseq_disasm_insn(VALUE str, const VALUE *iseqval, size_t pos, const rb_iseq_t *iseq, VALUE child);
VALUE rb_iseq_coverage(const rb_iseq_t *iseq);
extern VALUE rb_cISeq;
extern VALUE rb_cRubyVM;
extern VALUE rb_mRubyVMFrozenCore;
extern VALUE rb_block_param_proxy;


typedef struct {
    const struct rb_block block;
    unsigned int is_from_method: 1;
    unsigned int is_lambda: 1;
    unsigned int is_isolated: 1;
} rb_proc_t;


VALUE rb_proc_isolate(VALUE self);
VALUE rb_proc_isolate_bang(VALUE self);
VALUE rb_proc_ractor_make_shareable(VALUE self);


typedef struct {
    VALUE flags;
    rb_iseq_t *iseq;
    const VALUE *ep;
    const VALUE *env;
    unsigned int env_size;
} rb_env_t;
extern const rb_data_type_t ruby_binding_data_type;
typedef struct {
    const struct rb_block block;
    const VALUE pathobj;
    unsigned short first_lineno;
} rb_binding_t;
enum vm_check_match_type {
    VM_CHECKMATCH_TYPE_WHEN = 1,
    VM_CHECKMATCH_TYPE_CASE = 2,
    VM_CHECKMATCH_TYPE_RESCUE = 3
};
enum vm_special_object_type {
    VM_SPECIAL_OBJECT_VMCORE = 1,
    VM_SPECIAL_OBJECT_CBASE,
    VM_SPECIAL_OBJECT_CONST_BASE
};
enum vm_svar_index {
    VM_SVAR_LASTLINE = 0,
    VM_SVAR_BACKREF = 1,
    VM_SVAR_EXTRA_START = 2,
    VM_SVAR_FLIPFLOP_START = 2
};
typedef struct iseq_inline_constant_cache *IC;
typedef struct iseq_inline_iv_cache_entry *IVC;
typedef struct iseq_inline_cvar_cache_entry *ICVARC;
typedef union iseq_inline_storage_entry *ISE;
typedef const struct rb_callinfo *CALL_INFO;
typedef const struct rb_callcache *CALL_CACHE;
typedef struct rb_call_data *CALL_DATA;
typedef VALUE CDHASH;
typedef rb_control_frame_t *
  (*rb_insn_func_t)(rb_execution_context_t *, rb_control_frame_t *);
enum {
    VM_FRAME_MAGIC_METHOD = 0x11110001,
    VM_FRAME_MAGIC_BLOCK = 0x22220001,
    VM_FRAME_MAGIC_CLASS = 0x33330001,
    VM_FRAME_MAGIC_TOP = 0x44440001,
    VM_FRAME_MAGIC_CFUNC = 0x55550001,
    VM_FRAME_MAGIC_IFUNC = 0x66660001,
    VM_FRAME_MAGIC_EVAL = 0x77770001,
    VM_FRAME_MAGIC_RESCUE = 0x78880001,
    VM_FRAME_MAGIC_DUMMY = 0x79990001,
    VM_FRAME_MAGIC_MASK = 0x7fff0001,
    VM_FRAME_FLAG_FINISH = 0x0020,
    VM_FRAME_FLAG_BMETHOD = 0x0040,
    VM_FRAME_FLAG_CFRAME = 0x0080,
    VM_FRAME_FLAG_LAMBDA = 0x0100,
    VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM = 0x0200,
    VM_FRAME_FLAG_CFRAME_KW = 0x0400,
    VM_FRAME_FLAG_PASSED = 0x0800,
    VM_ENV_FLAG_LOCAL = 0x0002,
    VM_ENV_FLAG_ESCAPED = 0x0004,
    VM_ENV_FLAG_WB_REQUIRED = 0x0008,
    VM_ENV_FLAG_ISOLATED = 0x0010,
};
static inline void VM_FORCE_WRITE_SPECIAL_CONST(const VALUE *ptr, VALUE special_const_value);
static inline void
VM_ENV_FLAGS_SET(const VALUE *ep, VALUE flag)
{
    VALUE flags = ep[( 0)];
    ((void)0);
    VM_FORCE_WRITE_SPECIAL_CONST(&ep[( 0)], flags | flag);
}
static inline void
VM_ENV_FLAGS_UNSET(const VALUE *ep, VALUE flag)
{
    VALUE flags = ep[( 0)];
    ((void)0);
    VM_FORCE_WRITE_SPECIAL_CONST(&ep[( 0)], flags & ~flag);
}
static inline unsigned long
VM_ENV_FLAGS(const VALUE *ep, long flag)
{
    VALUE flags = ep[( 0)];
    ((void)0);
    return flags & flag;
}
static inline unsigned long
VM_FRAME_TYPE(const rb_control_frame_t *cfp)
{
    return VM_ENV_FLAGS(cfp->ep, VM_FRAME_MAGIC_MASK);
}
static inline int
VM_FRAME_LAMBDA_P(const rb_control_frame_t *cfp)
{
    return VM_ENV_FLAGS(cfp->ep, VM_FRAME_FLAG_LAMBDA) != 0;
}
static inline int
VM_FRAME_CFRAME_KW_P(const rb_control_frame_t *cfp)
{
    return VM_ENV_FLAGS(cfp->ep, VM_FRAME_FLAG_CFRAME_KW) != 0;
}
static inline int
VM_FRAME_FINISHED_P(const rb_control_frame_t *cfp)
{
    return VM_ENV_FLAGS(cfp->ep, VM_FRAME_FLAG_FINISH) != 0;
}
static inline int
VM_FRAME_BMETHOD_P(const rb_control_frame_t *cfp)
{
    return VM_ENV_FLAGS(cfp->ep, VM_FRAME_FLAG_BMETHOD) != 0;
}
static inline int
rb_obj_is_iseq(VALUE iseq)
{
    return imemo_type_p(iseq, imemo_iseq);
}
static inline int
VM_FRAME_CFRAME_P(const rb_control_frame_t *cfp)
{
    int cframe_p = VM_ENV_FLAGS(cfp->ep, VM_FRAME_FLAG_CFRAME) != 0;
    ((void)0);
    return cframe_p;
}
static inline int
VM_FRAME_RUBYFRAME_P(const rb_control_frame_t *cfp)
{
    return !VM_FRAME_CFRAME_P(cfp);
}
static inline int
VM_ENV_LOCAL_P(const VALUE *ep)
{
    return VM_ENV_FLAGS(ep, VM_ENV_FLAG_LOCAL) ? 1 : 0;
}
static inline const VALUE *
VM_ENV_PREV_EP(const VALUE *ep)
{
    ((void)0);
    return ((void *)(((ep[(-1)])) & ~0x03));
}
static inline VALUE
VM_ENV_BLOCK_HANDLER(const VALUE *ep)
{
    ((void)0);
    return ep[(-1)];
}
static inline int
VM_ENV_ESCAPED_P(const VALUE *ep)
{
    ((void)0);
    return VM_ENV_FLAGS(ep, VM_ENV_FLAG_ESCAPED) ? 1 : 0;
}
__attribute__((__nonnull__ (1)))
static inline VALUE
VM_ENV_ENVVAL(const VALUE *ep)
{
    VALUE envval = ep[( 1)];
    ((void)0);
    ((void)0);
    return envval;
}
__attribute__((__nonnull__ (1)))
static inline const rb_env_t *
VM_ENV_ENVVAL_PTR(const VALUE *ep)
{
    return (const rb_env_t *)VM_ENV_ENVVAL(ep);
}
static inline const rb_env_t *
vm_env_new(VALUE *env_ep, VALUE *env_body, unsigned int env_size, const rb_iseq_t *iseq)
{
    rb_env_t *env = (rb_env_t *)rb_imemo_new(imemo_env, (VALUE)env_ep, (VALUE)env_body, 0, (VALUE)iseq);
    env->env_size = env_size;
    env_ep[( 1)] = (VALUE)env;
    return env;
}
static inline void
VM_FORCE_WRITE(const VALUE *ptr, VALUE v)
{
    *((VALUE *)ptr) = v;
}
static inline void
VM_FORCE_WRITE_SPECIAL_CONST(const VALUE *ptr, VALUE special_const_value)
{
    ((void)0);
    VM_FORCE_WRITE(ptr, special_const_value);
}
static inline void
VM_STACK_ENV_WRITE(const VALUE *ep, int index, VALUE v)
{
    ((void)0);
    VM_FORCE_WRITE(&ep[index], v);
}static inline 
const VALUE *rb_vm_ep_local_ep(const VALUE *ep);
const VALUE *rb_vm_proc_local_ep(VALUE proc);static inline 
void rb_vm_block_ep_update(VALUE obj, const struct rb_block *dst, const VALUE *ep);
void rb_vm_block_copy(VALUE obj, const struct rb_block *dst, const struct rb_block *src);static inline 
VALUE rb_vm_frame_block_handler(const rb_control_frame_t *cfp);
static inline const rb_control_frame_t *
RUBY_VM_END_CONTROL_FRAME(const rb_execution_context_t *ec)
{
    return (rb_control_frame_t *)(ec->vm_stack + ec->vm_stack_size);
}
static inline int
RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(const rb_execution_context_t *ec, const rb_control_frame_t *cfp)
{
    return !((void *)(RUBY_VM_END_CONTROL_FRAME(ec)) > (void *)(cfp));
}
static inline int
VM_BH_ISEQ_BLOCK_P(VALUE block_handler)
{
    if ((block_handler & 0x03) == 0x01) {
 return 1;
    }
    else {
 return 0;
    }
}
static inline VALUE
VM_BH_FROM_ISEQ_BLOCK(const struct rb_captured_block *captured)
{
    VALUE block_handler = ((VALUE)(captured) | (0x01));
    ((void)0);
    return block_handler;
}
static inline const struct rb_captured_block *
VM_BH_TO_ISEQ_BLOCK(VALUE block_handler)
{
    struct rb_captured_block *captured = ((void *)((block_handler) & ~0x03));
    ((void)0);
    return captured;
}
static inline int
VM_BH_IFUNC_P(VALUE block_handler)
{
    if ((block_handler & 0x03) == 0x03) {
 return 1;
    }
    else {
 return 0;
    }
}
static inline VALUE
VM_BH_FROM_IFUNC_BLOCK(const struct rb_captured_block *captured)
{
    VALUE block_handler = ((VALUE)(captured) | (0x03));
    ((void)0);
    return block_handler;
}
static inline const struct rb_captured_block *
VM_BH_TO_IFUNC_BLOCK(VALUE block_handler)
{
    struct rb_captured_block *captured = ((void *)((block_handler) & ~0x03));
    ((void)0);
    return captured;
}
static inline const struct rb_captured_block *
VM_BH_TO_CAPT_BLOCK(VALUE block_handler)
{
    struct rb_captured_block *captured = ((void *)((block_handler) & ~0x03));
    ((void)0);
    return captured;
}
static inline enum rb_block_handler_type
vm_block_handler_type(VALUE block_handler)
{
    if (VM_BH_ISEQ_BLOCK_P(block_handler)) {
 return block_handler_type_iseq;
    }
    else if (VM_BH_IFUNC_P(block_handler)) {
 return block_handler_type_ifunc;
    }
    else if (RB_SYMBOL_P(block_handler)) {
 return block_handler_type_symbol;
    }
    else {
 ((void)0);
 return block_handler_type_proc;
    }
}
static inline void
vm_block_handler_verify(__attribute__ ((__unused__)) VALUE block_handler)
{
    ((void)0);
}
static inline int
vm_cfp_forwarded_bh_p(const rb_control_frame_t *cfp, VALUE block_handler)
{
    return ((VALUE) cfp->block_code) == block_handler;
}
static inline enum rb_block_type
vm_block_type(const struct rb_block *block)
{
    return block->type;
}
static inline void
vm_block_type_set(const struct rb_block *block, enum rb_block_type type)
{
    struct rb_block *mb = (struct rb_block *)block;
    mb->type = type;
}
static inline const struct rb_block *
vm_proc_block(VALUE procval)
{
    ((void)0);
    return &((rb_proc_t *)(((struct RTypedData *)(procval))->data))->block;
}
static inline const rb_iseq_t *vm_block_iseq(const struct rb_block *block);
static inline const VALUE *vm_block_ep(const struct rb_block *block);
static inline const rb_iseq_t *
vm_proc_iseq(VALUE procval)
{
    return vm_block_iseq(vm_proc_block(procval));
}
static inline const VALUE *
vm_proc_ep(VALUE procval)
{
    return vm_block_ep(vm_proc_block(procval));
}
static inline const rb_iseq_t *
vm_block_iseq(const struct rb_block *block)
{
    switch (vm_block_type(block)) {
      case block_type_iseq: return rb_iseq_check(block->as.captured.code.iseq);
      case block_type_proc: return vm_proc_iseq(block->as.proc);
      case block_type_ifunc:
      case block_type_symbol: return ((void *)0);
    }
    __builtin_unreachable();
    return ((void *)0);
}
static inline const VALUE *
vm_block_ep(const struct rb_block *block)
{
    switch (vm_block_type(block)) {
      case block_type_iseq:
      case block_type_ifunc: return block->as.captured.ep;
      case block_type_proc: return vm_proc_ep(block->as.proc);
      case block_type_symbol: return ((void *)0);
    }
    __builtin_unreachable();
    return ((void *)0);
}
static inline VALUE
vm_block_self(const struct rb_block *block)
{
    switch (vm_block_type(block)) {
      case block_type_iseq:
      case block_type_ifunc:
 return block->as.captured.self;
      case block_type_proc:
 return vm_block_self(vm_proc_block(block->as.proc));
      case block_type_symbol:
 return ((VALUE)RUBY_Qundef);
    }
    __builtin_unreachable();
    return ((VALUE)RUBY_Qundef);
}
static inline VALUE
VM_BH_TO_SYMBOL(VALUE block_handler)
{
    ((void)0);
    return block_handler;
}
static inline VALUE
VM_BH_FROM_SYMBOL(VALUE symbol)
{
    ((void)0);
    return symbol;
}
static inline VALUE
VM_BH_TO_PROC(VALUE block_handler)
{
    ((void)0);
    return block_handler;
}
static inline VALUE
VM_BH_FROM_PROC(VALUE procval)
{
    ((void)0);
    return procval;
}
VALUE rb_thread_alloc(VALUE klass);
VALUE rb_binding_alloc(VALUE klass);
VALUE rb_proc_alloc(VALUE klass);
VALUE rb_proc_dup(VALUE self);
extern void rb_vmdebug_stack_dump_raw(const rb_execution_context_t *ec, const rb_control_frame_t *cfp);
extern void rb_vmdebug_debug_print_pre(const rb_execution_context_t *ec, const rb_control_frame_t *cfp, const VALUE *_pc);
extern void rb_vmdebug_debug_print_post(const rb_execution_context_t *ec, const rb_control_frame_t *cfp
);
void rb_vm_bugreport(const void *);
typedef void (*ruby_sighandler_t)(int);
__attribute__((__format__(__printf__, 4, 5)))
__attribute__((__noreturn__)) void rb_bug_for_fatal_signal(ruby_sighandler_t default_sighandler, int sig, const void *, const char *fmt, ...);


VALUE rb_iseq_eval(const rb_iseq_t *iseq);
VALUE rb_iseq_eval_main(const rb_iseq_t *iseq);
VALUE rb_iseq_path(const rb_iseq_t *iseq);
VALUE rb_iseq_realpath(const rb_iseq_t *iseq);


VALUE rb_iseq_pathobj_new(VALUE path, VALUE realpath);
void rb_iseq_pathobj_set(const rb_iseq_t *iseq, VALUE path, VALUE realpath);
int rb_ec_frame_method_id_and_class(const rb_execution_context_t *ec, ID *idp, ID *called_idp, VALUE *klassp);
void rb_ec_setup_exception(const rb_execution_context_t *ec, VALUE mesg, VALUE cause);
VALUE rb_vm_invoke_proc(rb_execution_context_t *ec, rb_proc_t *proc, int argc, const VALUE *argv, int kw_splat, VALUE block_handler);
VALUE rb_vm_make_proc_lambda(const rb_execution_context_t *ec, const struct rb_captured_block *captured, VALUE klass, int8_t is_lambda);
static inline VALUE
rb_vm_make_proc(const rb_execution_context_t *ec, const struct rb_captured_block *captured, VALUE klass)
{
    return rb_vm_make_proc_lambda(ec, captured, klass, 0);
}
static inline VALUE
rb_vm_make_lambda(const rb_execution_context_t *ec, const struct rb_captured_block *captured, VALUE klass)
{
    return rb_vm_make_proc_lambda(ec, captured, klass, 1);
}
VALUE rb_vm_make_binding(const rb_execution_context_t *ec, const rb_control_frame_t *src_cfp);
VALUE rb_vm_env_local_variables(const rb_env_t *env);
const rb_env_t *rb_vm_env_prev_env(const rb_env_t *env);
const VALUE *rb_binding_add_dynavars(VALUE bindval, rb_binding_t *bind, int dyncount, const ID *dynvars);
void rb_vm_inc_const_missing_count(void);
VALUE rb_vm_call_kw(rb_execution_context_t *ec, VALUE recv, VALUE id, int argc,
                 const VALUE *argv, const rb_callable_method_entry_t *me, int kw_splat);
static void rb_vm_pop_frame(rb_execution_context_t *ec);
void rb_gvl_destroy(rb_global_vm_lock_t *gvl);
void rb_thread_start_timer_thread(void);
void rb_thread_stop_timer_thread(void);
void rb_thread_reset_timer_thread(void);
void rb_thread_wakeup_timer_thread(int);
static inline void
rb_vm_living_threads_init(rb_vm_t *vm)
{
    list_head_init(&vm->waiting_fds);
    list_head_init(&vm->waiting_pids);
    list_head_init(&vm->workqueue);
    list_head_init(&vm->waiting_grps);
    list_head_init(&vm->ractor.set);
}
typedef int rb_backtrace_iter_func(void *, VALUE, int, VALUE);
rb_control_frame_t *rb_vm_get_ruby_level_next_cfp(const rb_execution_context_t *ec, const rb_control_frame_t *cfp);
rb_control_frame_t *rb_vm_get_binding_creatable_next_cfp(const rb_execution_context_t *ec, const rb_control_frame_t *cfp);
int rb_vm_get_sourceline(const rb_control_frame_t *);
void rb_vm_stack_to_heap(rb_execution_context_t *ec);
void ruby_thread_init_stack(rb_thread_t *th);
rb_thread_t * ruby_thread_from_native(void);
int ruby_thread_set_native(rb_thread_t *th);
int rb_vm_control_frame_id_and_class(const rb_control_frame_t *cfp, ID *idp, ID *called_idp, VALUE *klassp);
void rb_vm_rewind_cfp(rb_execution_context_t *ec, rb_control_frame_t *cfp);
static VALUE rb_vm_bh_to_procval(const rb_execution_context_t *ec, VALUE block_handler);
void rb_vm_register_special_exception_str(enum ruby_special_exceptions sp, VALUE exception_class, VALUE mesg);
void rb_gc_mark_machine_stack(const rb_execution_context_t *ec);static inline 
void rb_vm_rewrite_cref(rb_cref_t *node, VALUE old_klass, VALUE new_klass, rb_cref_t **new_cref_ptr);
static const rb_callable_method_entry_t *rb_vm_frame_method_entry(const rb_control_frame_t *cfp);
VALUE rb_catch_protect(VALUE t, rb_block_call_func *func, VALUE data, enum ruby_tag_type *stateptr);
rb_execution_context_t *rb_vm_main_ractor_ec(rb_vm_t *vm);


extern struct rb_ractor_struct *ruby_single_main_ractor;
extern rb_vm_t *ruby_current_vm_ptr;
extern rb_event_flag_t ruby_vm_event_flags;
extern rb_event_flag_t ruby_vm_event_enabled_global_flags;
extern unsigned int ruby_vm_event_local_num;


static inline rb_thread_t *
rb_ec_thread_ptr(const rb_execution_context_t *ec)
{
    return ec->thread_ptr;
}
static inline rb_ractor_t *
rb_ec_ractor_ptr(const rb_execution_context_t *ec)
{
    const rb_thread_t *th = rb_ec_thread_ptr(ec);
    if (th) {
        ((void)0);
 return th->ractor;
    }
    else {
        return ((void *)0);
    }
}
static inline rb_vm_t *
rb_ec_vm_ptr(const rb_execution_context_t *ec)
{
    const rb_thread_t *th = rb_ec_thread_ptr(ec);
    if (th) {
 return th->vm;
    }
    else {
 return ((void *)0);
    }
}
static inline rb_execution_context_t *
rb_current_execution_context(_Bool expect_ec)
{
    rb_execution_context_t *ec = ruby_current_ec;
    ((void)0);
    return ec;
}
static inline rb_thread_t *
rb_current_thread(void)
{
    const rb_execution_context_t *ec = rb_current_execution_context(1);
    return rb_ec_thread_ptr(ec);
}
static inline rb_ractor_t *
rb_current_ractor(void)
{
    if (ruby_single_main_ractor) {
        return ruby_single_main_ractor;
    }
    else {
        const rb_execution_context_t *ec = rb_current_execution_context(1);
        return rb_ec_ractor_ptr(ec);
    }
}
static inline rb_vm_t *
rb_current_vm(void)
{
    return ruby_current_vm_ptr;
}
void rb_ec_vm_lock_rec_release(const rb_execution_context_t *ec,
                               unsigned int recorded_lock_rec,
                               unsigned int current_lock_rec);
static inline unsigned int
rb_ec_vm_lock_rec(const rb_execution_context_t *ec)
{
    rb_vm_t *vm = rb_ec_vm_ptr(ec);
    if (vm->ractor.sync.lock_owner != rb_ec_ractor_ptr(ec)) {
        return 0;
    }
    else {
        return vm->ractor.sync.lock_rec;
    }
}
enum {
    TIMER_INTERRUPT_MASK = 0x01,
    PENDING_INTERRUPT_MASK = 0x02,
    POSTPONED_JOB_INTERRUPT_MASK = 0x04,
    TRAP_INTERRUPT_MASK = 0x08,
    TERMINATE_INTERRUPT_MASK = 0x10,
    VM_BARRIER_INTERRUPT_MASK = 0x20,
};
static inline _Bool
RUBY_VM_INTERRUPTED_ANY(rb_execution_context_t *ec)
{
    return ec->interrupt_flag & ~(ec)->interrupt_mask;
}
VALUE rb_exc_set_backtrace(VALUE exc, VALUE bt);
int rb_signal_buff_size(void);
int rb_signal_exec(rb_thread_t *th, int sig);
void rb_threadptr_check_signal(rb_thread_t *mth);
void rb_threadptr_signal_raise(rb_thread_t *th, int sig);
void rb_threadptr_signal_exit(rb_thread_t *th);
int rb_threadptr_execute_interrupts(rb_thread_t *, int);
void rb_threadptr_interrupt(rb_thread_t *th);
void rb_threadptr_unlock_all_locking_mutexes(rb_thread_t *th);
void rb_threadptr_pending_interrupt_clear(rb_thread_t *th);
void rb_threadptr_pending_interrupt_enque(rb_thread_t *th, VALUE v);
VALUE rb_ec_get_errinfo(const rb_execution_context_t *ec);
void rb_ec_error_print(rb_execution_context_t * volatile ec, volatile VALUE errinfo);
void rb_execution_context_update(const rb_execution_context_t *ec);
void rb_execution_context_mark(const rb_execution_context_t *ec);
void rb_fiber_close(rb_fiber_t *fib);
void Init_native_thread(rb_thread_t *th);
int rb_vm_check_ints_blocking(rb_execution_context_t *ec);
void rb_vm_cond_wait(rb_vm_t *vm, rb_nativethread_cond_t *cond);
void rb_vm_cond_timedwait(rb_vm_t *vm, rb_nativethread_cond_t *cond, unsigned long msec);
static inline void
rb_vm_check_ints(rb_execution_context_t *ec)
{
    ((void)0);
    if ((__builtin_expect(!!(RUBY_VM_INTERRUPTED_ANY(ec)), 0))) {
 rb_threadptr_execute_interrupts(rb_ec_thread_ptr(ec), 0);
    }
}
struct rb_trace_arg_struct {
    rb_event_flag_t event;
    rb_execution_context_t *ec;
    const rb_control_frame_t *cfp;
    VALUE self;
    ID id;
    ID called_id;
    VALUE klass;
    VALUE data;
    int klass_solved;
    int lineno;
    VALUE path;
};
void rb_hook_list_mark(rb_hook_list_t *hooks);
void rb_hook_list_free(rb_hook_list_t *hooks);
void rb_hook_list_connect_tracepoint(VALUE target, rb_hook_list_t *list, VALUE tpval, unsigned int target_line);
void rb_hook_list_remove_tracepoint(rb_hook_list_t *list, VALUE tpval);
void rb_exec_event_hooks(struct rb_trace_arg_struct *trace_arg, rb_hook_list_t *hooks, int pop_p);
static inline void
rb_exec_event_hook_orig(rb_execution_context_t *ec, rb_hook_list_t *hooks, rb_event_flag_t flag,
                        VALUE self, ID id, ID called_id, VALUE klass, VALUE data, int pop_p)
{
    struct rb_trace_arg_struct trace_arg;
    ((void)0);
    trace_arg.event = flag;
    trace_arg.ec = ec;
    trace_arg.cfp = ec->cfp;
    trace_arg.self = self;
    trace_arg.id = id;
    trace_arg.called_id = called_id;
    trace_arg.klass = klass;
    trace_arg.data = data;
    trace_arg.path = ((VALUE)RUBY_Qundef);
    trace_arg.klass_solved = 0;
    rb_exec_event_hooks(&trace_arg, hooks, pop_p);
}
struct rb_ractor_pub {
    VALUE self;
    uint32_t id;
    rb_hook_list_t hooks;
};
static inline rb_hook_list_t *
rb_ec_ractor_hooks(const rb_execution_context_t *ec)
{
    struct rb_ractor_pub *cr_pub = (struct rb_ractor_pub *)rb_ec_ractor_ptr(ec);
    return &cr_pub->hooks;
}
static inline void
rb_exec_event_hook_script_compiled(rb_execution_context_t *ec, const rb_iseq_t *iseq, VALUE eval_script)
{
    do { const rb_event_flag_t flag_arg_ = (0x2000); rb_hook_list_t *hooks_arg_ = (rb_ec_ractor_hooks(ec)); if ((__builtin_expect(!!((hooks_arg_)->events & (flag_arg_)), 0))) { rb_exec_event_hook_orig(ec, hooks_arg_, flag_arg_, ec->cfp->self, 0, 0, 0, RB_NIL_P(eval_script) ? (VALUE)iseq : __extension__ ({ const VALUE args_to_new_ary[] = {eval_script, (VALUE)iseq}; if (__builtin_constant_p(2)) { __extension__ _Static_assert(((int)(sizeof(args_to_new_ary) / sizeof((args_to_new_ary)[0]))) == (2), "rb_ary_new_from_args" ": " "numberof(args_to_new_ary) == (2)"); } rb_ary_new_from_values(((int)(sizeof(args_to_new_ary) / sizeof((args_to_new_ary)[0]))), args_to_new_ary); }), 0); } } while (0);
}
void rb_vm_trap_exit(rb_vm_t *vm);


int rb_thread_check_trap_pending(void);
extern VALUE rb_get_coverages(void);
extern void rb_set_coverages(VALUE, int, VALUE);
extern void rb_clear_coverages(void);
extern void rb_reset_coverages(void);
extern void rb_resume_coverages(void);
extern void rb_suspend_coverages(void);
void rb_postponed_job_flush(rb_vm_t *vm);
extern VALUE rb_eRactorUnsafeError;
extern VALUE rb_eRactorIsolationError;


static inline void
vm_passed_block_handler_set(rb_execution_context_t *ec, VALUE block_handler)
{
    vm_block_handler_verify(block_handler);
    ec->passed_block_handler = block_handler;
}
static inline void
pass_passed_block_handler(rb_execution_context_t *ec)
{
    VALUE block_handler = rb_vm_frame_block_handler(ec->cfp);
    vm_passed_block_handler_set(ec, block_handler);
    VM_ENV_FLAGS_SET(ec->cfp->ep, VM_FRAME_FLAG_PASSED);
}

extern int *__errno_location (void) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern char *program_invocation_name, *program_invocation_short_name;

typedef int error_t;
static inline void
rb_ec_vm_lock_rec_check(const rb_execution_context_t *ec, unsigned int recorded_lock_rec)
{
    unsigned int current_lock_rec = rb_ec_vm_lock_rec(ec);
    if (current_lock_rec != recorded_lock_rec) {
        rb_ec_vm_lock_rec_release(ec, recorded_lock_rec, current_lock_rec);
    }
}
static inline int
rb_ec_tag_state(const rb_execution_context_t *ec)
{
    struct rb_vm_tag *tag = ec->tag;
    enum ruby_tag_type state = tag->state;
    tag->state = RUBY_TAG_NONE;
    rb_ec_vm_lock_rec_check(ec, tag->lock_rec);
    return state;
}
__attribute__((__noreturn__)) static inline void rb_ec_tag_jump(const rb_execution_context_t *ec, enum ruby_tag_type st);
static inline void
rb_ec_tag_jump(const rb_execution_context_t *ec, enum ruby_tag_type st)
{
    ec->tag->state = st;
    __builtin_longjmp(((ec->tag->buf)),(1));
}
static inline int CREF_SINGLETON(const rb_cref_t *cref);
static inline VALUE
CREF_CLASS(const rb_cref_t *cref)
{
    if (CREF_SINGLETON(cref)) {
        return rb_class_of(cref->klass_or_self);
    }
    else {
        return cref->klass_or_self;
    }
}
static inline VALUE
CREF_CLASS_FOR_DEFINITION(const rb_cref_t *cref)
{
    if (CREF_SINGLETON(cref)) {
        return rb_singleton_class(cref->klass_or_self);
    }
    else {
        return cref->klass_or_self;
    }
}
static inline rb_cref_t *
CREF_NEXT(const rb_cref_t *cref)
{
    return cref->next;
}
static inline const rb_scope_visibility_t *
CREF_SCOPE_VISI(const rb_cref_t *cref)
{
    return &cref->scope_visi;
}
static inline VALUE
CREF_REFINEMENTS(const rb_cref_t *cref)
{
    return cref->refinements;
}
static inline void
CREF_REFINEMENTS_SET(rb_cref_t *cref, VALUE refs)
{
    rb_obj_write((VALUE)(cref), __extension__({
   ;
   ; __typeof__((VALUE *)(&cref->refinements)) unaligned_member_access_result = ((VALUE *)(&cref->refinements));
   ; unaligned_member_access_result; }), (VALUE)(refs), "./eval_intern.h", 223);
}
static inline int
CREF_PUSHED_BY_EVAL(const rb_cref_t *cref)
{
    return cref->flags & ((VALUE)RUBY_FL_USER5);
}
static inline void
CREF_PUSHED_BY_EVAL_SET(rb_cref_t *cref)
{
    cref->flags |= ((VALUE)RUBY_FL_USER5);
}
static inline int
CREF_SINGLETON(const rb_cref_t *cref)
{
    return cref->flags & ((VALUE)RUBY_FL_USER7);
}
static inline void
CREF_SINGLETON_SET(rb_cref_t *cref)
{
    cref->flags |= ((VALUE)RUBY_FL_USER7);
}
static inline int
CREF_OMOD_SHARED(const rb_cref_t *cref)
{
    return cref->flags & ((VALUE)RUBY_FL_USER6);
}
static inline void
CREF_OMOD_SHARED_SET(rb_cref_t *cref)
{
    cref->flags |= ((VALUE)RUBY_FL_USER6);
}
static inline void
CREF_OMOD_SHARED_UNSET(rb_cref_t *cref)
{
    cref->flags &= ~((VALUE)RUBY_FL_USER6);
}
enum {
    RAISED_EXCEPTION = 1,
    RAISED_STACKOVERFLOW = 2,
    RAISED_NOMEMORY = 4
};
int rb_ec_set_raised(rb_execution_context_t *ec);
int rb_ec_reset_raised(rb_execution_context_t *ec);
int rb_ec_stack_check(rb_execution_context_t *ec);
VALUE rb_f_eval(int argc, const VALUE *argv, VALUE self);
VALUE rb_make_exception(int argc, const VALUE *argv);
__attribute__((__noreturn__)) void rb_method_name_error(VALUE, VALUE);
__attribute__((__noreturn__)) void rb_fiber_start(rb_fiber_t*);
__attribute__((__noreturn__)) void rb_print_undef(VALUE, ID, rb_method_visibility_t);
__attribute__((__noreturn__)) void rb_print_undef_str(VALUE, VALUE);
__attribute__((__noreturn__)) void rb_print_inaccessible(VALUE, ID, rb_method_visibility_t);
__attribute__((__noreturn__)) void rb_vm_localjump_error(const char *,VALUE, int);
__attribute__((__noreturn__)) void rb_vm_jump_tag_but_local_jump(int);
VALUE rb_vm_make_jump_tag_but_local_jump(int state, VALUE val);
rb_cref_t *rb_vm_cref(void);
rb_cref_t *rb_vm_cref_replace_with_duplicated_cref(void);
VALUE rb_vm_call_cfunc(VALUE recv, VALUE (*func)(VALUE), VALUE arg, VALUE block_handler, VALUE filename);
void rb_vm_set_progname(VALUE filename);
VALUE rb_vm_cbase(void);
VALUE rb_ec_backtrace_object(const rb_execution_context_t *ec);
VALUE rb_ec_backtrace_str_ary(const rb_execution_context_t *ec, long lev, long n);
VALUE rb_ec_backtrace_location_ary(const rb_execution_context_t *ec, long lev, long n, _Bool skip_internal);
static inline char *
rb_char_next(const char *p)
{
    if (p) {
        int len = mblen(p, 0x7fffffff);
        p += len > 0 ? len : 1;
    }
    return (char *)p;
}
const char *rb_obj_info(VALUE obj);
const char *rb_raw_obj_info(char *buff, const int buff_size, VALUE obj);
VALUE rb_gc_disable_no_rest(void);
struct rb_thread_struct;


size_t rb_objspace_data_type_memsize(VALUE obj);
void rb_objspace_reachable_objects_from(VALUE obj, void (func)(VALUE, void *), void *data);
void rb_objspace_reachable_objects_from_root(void (func)(const char *category, VALUE, void *), void *data);
int rb_objspace_markable_object_p(VALUE obj);
int rb_objspace_internal_object_p(VALUE obj);
int rb_objspace_marked_object_p(VALUE obj);
void rb_objspace_each_objects(
    int (*callback)(void *start, void *end, size_t stride, void *data),
    void *data);
void rb_objspace_each_objects_without_setup(
    int (*callback)(void *, void *, size_t, void *),
    void *data);


struct rb_iseq_struct;
int rb_dvar_defined(ID, const struct rb_iseq_struct *);
int rb_local_defined(ID, const struct rb_iseq_struct *);
const char *rb_insns_name(int i);
VALUE rb_insns_name_array(void);
int rb_iseq_cdhash_cmp(VALUE val, VALUE lit);
st_index_t rb_iseq_cdhash_hash(VALUE a);
int rb_vm_insn_addr2insn(const void *);
int rb_vm_insn_decode(const VALUE encoded);
extern _Bool ruby_vm_keep_script_lines;


rb_event_flag_t rb_iseq_event_flags(const struct rb_iseq_struct *iseq, size_t pos);


struct rb_thread_struct;
struct rb_fiber_struct;
void rb_fiber_reset_root_local_storage(struct rb_thread_struct *);
void ruby_register_rollback_func_for_ensure(VALUE (*ensure_func)(VALUE), VALUE (*rollback_func)(VALUE));
void rb_fiber_init_mjit_cont(struct rb_fiber_struct *fiber);
VALUE rb_fiberptr_self(struct rb_fiber_struct *fiber);
unsigned int rb_fiberptr_blocking(struct rb_fiber_struct *fiber);


enum ruby_coderange_type {
    RUBY_ENC_CODERANGE_UNKNOWN = 0,
    RUBY_ENC_CODERANGE_7BIT = ((int)RUBY_FL_USER8),
    RUBY_ENC_CODERANGE_VALID = ((int)RUBY_FL_USER9),
    RUBY_ENC_CODERANGE_BROKEN = ((int)(RUBY_FL_USER8|RUBY_FL_USER9)),
    RUBY_ENC_CODERANGE_MASK = (RUBY_ENC_CODERANGE_7BIT|
                                   RUBY_ENC_CODERANGE_VALID|
                                   RUBY_ENC_CODERANGE_BROKEN)
};
__attribute__((__const__))
static inline int
rb_enc_coderange_clean_p(int cr)
{
    return (cr ^ (cr >> 1)) & RUBY_ENC_CODERANGE_7BIT;
}
__attribute__((__const__))
static inline _Bool
RB_ENC_CODERANGE_CLEAN_P(enum ruby_coderange_type cr)
{
    return rb_enc_coderange_clean_p(cr);
}
__attribute__((__pure__))
static inline enum ruby_coderange_type
RB_ENC_CODERANGE(VALUE obj)
{
    VALUE ret = RB_FL_TEST_RAW(obj, RUBY_ENC_CODERANGE_MASK);
    return ((enum ruby_coderange_type)ret);
}
__attribute__((__pure__))
static inline _Bool
RB_ENC_CODERANGE_ASCIIONLY(VALUE obj)
{
    return RB_ENC_CODERANGE(obj) == RUBY_ENC_CODERANGE_7BIT;
}
static inline void
RB_ENC_CODERANGE_SET(VALUE obj, enum ruby_coderange_type cr)
{
    RB_FL_UNSET_RAW(obj, RUBY_ENC_CODERANGE_MASK);
    RB_FL_SET_RAW(obj, cr);
}
static inline void
RB_ENC_CODERANGE_CLEAR(VALUE obj)
{
    RB_FL_UNSET_RAW(obj, RUBY_ENC_CODERANGE_MASK);
}
__attribute__((__const__))
static inline enum ruby_coderange_type
RB_ENC_CODERANGE_AND(enum ruby_coderange_type a, enum ruby_coderange_type b)
{
    if (a == RUBY_ENC_CODERANGE_7BIT) {
        return b;
    }
    else if (a != RUBY_ENC_CODERANGE_VALID) {
        return RUBY_ENC_CODERANGE_UNKNOWN;
    }
    else if (b == RUBY_ENC_CODERANGE_7BIT) {
        return RUBY_ENC_CODERANGE_VALID;
    }
    else {
        return b;
    }
}




typedef unsigned char OnigUChar;
typedef unsigned int OnigCodePoint;
typedef unsigned int OnigCtype;
typedef size_t OnigDistance;
typedef ptrdiff_t OnigPosition;
typedef unsigned int OnigCaseFoldType;
extern OnigCaseFoldType OnigDefaultCaseFoldFlag;
typedef struct {
  int byte_len;
  int code_len;
  OnigCodePoint code[3];
} OnigCaseFoldCodeItem;
typedef struct {
  OnigCodePoint esc;
  OnigCodePoint anychar;
  OnigCodePoint anytime;
  OnigCodePoint zero_or_one_time;
  OnigCodePoint one_or_more_time;
  OnigCodePoint anychar_anytime;
} OnigMetaCharTableType;
typedef int (*OnigApplyAllCaseFoldFunc)(OnigCodePoint from, OnigCodePoint* to, int to_len, void* arg);
typedef struct OnigEncodingTypeST {
  int (*precise_mbc_enc_len)(const OnigUChar* p,const OnigUChar* e, const struct OnigEncodingTypeST* enc);
  const char* name;
  int max_enc_len;
  int min_enc_len;
  int (*is_mbc_newline)(const OnigUChar* p, const OnigUChar* end, const struct OnigEncodingTypeST* enc);
  OnigCodePoint (*mbc_to_code)(const OnigUChar* p, const OnigUChar* end, const struct OnigEncodingTypeST* enc);
  int (*code_to_mbclen)(OnigCodePoint code, const struct OnigEncodingTypeST* enc);
  int (*code_to_mbc)(OnigCodePoint code, OnigUChar *buf, const struct OnigEncodingTypeST* enc);
  int (*mbc_case_fold)(OnigCaseFoldType flag, const OnigUChar** pp, const OnigUChar* end, OnigUChar* to, const struct OnigEncodingTypeST* enc);
  int (*apply_all_case_fold)(OnigCaseFoldType flag, OnigApplyAllCaseFoldFunc f, void* arg, const struct OnigEncodingTypeST* enc);
  int (*get_case_fold_codes_by_str)(OnigCaseFoldType flag, const OnigUChar* p, const OnigUChar* end, OnigCaseFoldCodeItem acs[], const struct OnigEncodingTypeST* enc);
  int (*property_name_to_ctype)(const struct OnigEncodingTypeST* enc, const OnigUChar* p, const OnigUChar* end);
  int (*is_code_ctype)(OnigCodePoint code, OnigCtype ctype, const struct OnigEncodingTypeST* enc);
  int (*get_ctype_code_range)(OnigCtype ctype, OnigCodePoint* sb_out, const OnigCodePoint* ranges[], const struct OnigEncodingTypeST* enc);
  OnigUChar* (*left_adjust_char_head)(const OnigUChar* start, const OnigUChar* p, const OnigUChar* end, const struct OnigEncodingTypeST* enc);
  int (*is_allowed_reverse_match)(const OnigUChar* p, const OnigUChar* end, const struct OnigEncodingTypeST* enc);
  int (*case_map)(OnigCaseFoldType* flagP, const OnigUChar** pp, const OnigUChar* end, OnigUChar* to, OnigUChar* to_end, const struct OnigEncodingTypeST* enc);
  int ruby_encoding_index;
  unsigned int flags;
} OnigEncodingType;
typedef const OnigEncodingType* OnigEncoding;
extern const OnigEncodingType OnigEncodingASCII;
extern
int onigenc_ascii_only_case_map(OnigCaseFoldType* flagP, const OnigUChar** pp, const OnigUChar* end, OnigUChar* to, OnigUChar* to_end, const struct OnigEncodingTypeST* enc);
extern
int onigenc_mbclen_approximate(const OnigUChar* p,const OnigUChar* e, const struct OnigEncodingTypeST* enc);
extern
OnigUChar* onigenc_step_back(OnigEncoding enc, const OnigUChar* start, const OnigUChar* s, const OnigUChar* end, int n);
extern
int onigenc_init(void);
extern
int onigenc_set_default_encoding(OnigEncoding enc);
extern
OnigEncoding onigenc_get_default_encoding(void);
extern
OnigUChar* onigenc_get_right_adjust_char_head_with_prev(OnigEncoding enc, const OnigUChar* start, const OnigUChar* s, const OnigUChar* end, const OnigUChar** prev);
extern
OnigUChar* onigenc_get_prev_char_head(OnigEncoding enc, const OnigUChar* start, const OnigUChar* s, const OnigUChar* end);
extern
OnigUChar* onigenc_get_left_adjust_char_head(OnigEncoding enc, const OnigUChar* start, const OnigUChar* s, const OnigUChar* end);
extern
OnigUChar* onigenc_get_right_adjust_char_head(OnigEncoding enc, const OnigUChar* start, const OnigUChar* s, const OnigUChar* end);
extern
int onigenc_strlen(OnigEncoding enc, const OnigUChar* p, const OnigUChar* end);
extern
int onigenc_strlen_null(OnigEncoding enc, const OnigUChar* p);
extern
int onigenc_str_bytelen_null(OnigEncoding enc, const OnigUChar* p);
typedef unsigned int OnigOptionType;
typedef struct {
  unsigned int op;
  unsigned int op2;
  unsigned int behavior;
  OnigOptionType options;
  OnigMetaCharTableType meta_char_table;
} OnigSyntaxType;
extern const OnigSyntaxType OnigSyntaxASIS;
extern const OnigSyntaxType OnigSyntaxPosixBasic;
extern const OnigSyntaxType OnigSyntaxPosixExtended;
extern const OnigSyntaxType OnigSyntaxEmacs;
extern const OnigSyntaxType OnigSyntaxGrep;
extern const OnigSyntaxType OnigSyntaxGnuRegex;
extern const OnigSyntaxType OnigSyntaxJava;
extern const OnigSyntaxType OnigSyntaxPerl58;
extern const OnigSyntaxType OnigSyntaxPerl58_NG;
extern const OnigSyntaxType OnigSyntaxPerl;
extern const OnigSyntaxType OnigSyntaxRuby;
extern const OnigSyntaxType OnigSyntaxPython;
extern const OnigSyntaxType* OnigDefaultSyntax;
struct re_registers {
  int allocated;
  int num_regs;
  OnigPosition* beg;
  OnigPosition* end;
};
typedef struct re_registers OnigRegion;
typedef struct {
  OnigEncoding enc;
  OnigUChar* par;
  OnigUChar* par_end;
} OnigErrorInfo;
typedef struct {
  int lower;
  int upper;
} OnigRepeatRange;
typedef void (*OnigWarnFunc)(const char* s);
extern void onig_null_warn(const char* s);
typedef struct re_pattern_buffer {
  unsigned char* p;
  unsigned int used;
  unsigned int alloc;
  int num_mem;
  int num_repeat;
  int num_null_check;
  int num_comb_exp_check;
  int num_call;
  unsigned int capture_history;
  unsigned int bt_mem_start;
  unsigned int bt_mem_end;
  int stack_pop_level;
  int repeat_range_alloc;
  OnigOptionType options;
  OnigRepeatRange* repeat_range;
  OnigEncoding enc;
  const OnigSyntaxType* syntax;
  void* name_table;
  OnigCaseFoldType case_fold_flag;
  int optimize;
  int threshold_len;
  int anchor;
  OnigDistance anchor_dmin;
  OnigDistance anchor_dmax;
  int sub_anchor;
  unsigned char *exact;
  unsigned char *exact_end;
  unsigned char map[256];
  int *int_map;
  int *int_map_backward;
  OnigDistance dmin;
  OnigDistance dmax;
  struct re_pattern_buffer* chain;
} OnigRegexType;
typedef OnigRegexType* OnigRegex;
typedef OnigRegexType regex_t;
typedef struct {
  int num_of_elements;
  OnigEncoding pattern_enc;
  OnigEncoding target_enc;
  const OnigSyntaxType* syntax;
  OnigOptionType option;
  OnigCaseFoldType case_fold_flag;
} OnigCompileInfo;
extern
int onig_initialize(OnigEncoding encodings[], int n);
extern
int onig_init(void);
extern
int onig_error_code_to_str(OnigUChar* s, OnigPosition err_code, ...);
extern
void onig_set_warn_func(OnigWarnFunc f);
extern
void onig_set_verb_warn_func(OnigWarnFunc f);
extern
int onig_new(OnigRegex*, const OnigUChar* pattern, const OnigUChar* pattern_end, OnigOptionType option, OnigEncoding enc, const OnigSyntaxType* syntax, OnigErrorInfo* einfo);
extern
int onig_reg_init(OnigRegex reg, OnigOptionType option, OnigCaseFoldType case_fold_flag, OnigEncoding enc, const OnigSyntaxType* syntax);
extern
int onig_new_without_alloc(OnigRegex, const OnigUChar* pattern, const OnigUChar* pattern_end, OnigOptionType option, OnigEncoding enc, const OnigSyntaxType* syntax, OnigErrorInfo* einfo);
extern
int onig_new_deluxe(OnigRegex* reg, const OnigUChar* pattern, const OnigUChar* pattern_end, OnigCompileInfo* ci, OnigErrorInfo* einfo);
extern
void onig_free(OnigRegex);
extern
void onig_free_body(OnigRegex);
extern
OnigPosition onig_scan(OnigRegex reg, const OnigUChar* str, const OnigUChar* end, OnigRegion* region, OnigOptionType option, int (*scan_callback)(OnigPosition, OnigPosition, OnigRegion*, void*), void* callback_arg);
extern
OnigPosition onig_search(OnigRegex, const OnigUChar* str, const OnigUChar* end, const OnigUChar* start, const OnigUChar* range, OnigRegion* region, OnigOptionType option);
extern
OnigPosition onig_search_gpos(OnigRegex, const OnigUChar* str, const OnigUChar* end, const OnigUChar* global_pos, const OnigUChar* start, const OnigUChar* range, OnigRegion* region, OnigOptionType option);
extern
OnigPosition onig_match(OnigRegex, const OnigUChar* str, const OnigUChar* end, const OnigUChar* at, OnigRegion* region, OnigOptionType option);
extern
OnigRegion* onig_region_new(void);
extern
void onig_region_init(OnigRegion* region);
extern
void onig_region_free(OnigRegion* region, int free_self);
extern
void onig_region_copy(OnigRegion* to, const OnigRegion* from);
extern
void onig_region_clear(OnigRegion* region);
extern
int onig_region_resize(OnigRegion* region, int n);
extern
int onig_region_set(OnigRegion* region, int at, int beg, int end);
extern
int onig_name_to_group_numbers(OnigRegex reg, const OnigUChar* name, const OnigUChar* name_end, int** nums);
extern
int onig_name_to_backref_number(OnigRegex reg, const OnigUChar* name, const OnigUChar* name_end, const OnigRegion *region);
extern
int onig_foreach_name(OnigRegex reg, int (*func)(const OnigUChar*, const OnigUChar*,int,int*,OnigRegex,void*), void* arg);
extern
int onig_number_of_names(const OnigRegexType *reg);
extern
int onig_number_of_captures(const OnigRegexType *reg);
extern
int onig_number_of_capture_histories(const OnigRegexType *reg);
extern
int onig_capture_tree_traverse(OnigRegion* region, int at, int(*callback_func)(int,OnigPosition,OnigPosition,int,int,void*), void* arg);
extern
int onig_noname_group_capture_is_active(const OnigRegexType *reg);
extern
OnigEncoding onig_get_encoding(const OnigRegexType *reg);
extern
OnigOptionType onig_get_options(const OnigRegexType *reg);
extern
OnigCaseFoldType onig_get_case_fold_flag(const OnigRegexType *reg);
extern
const OnigSyntaxType* onig_get_syntax(const OnigRegexType *reg);
extern
int onig_set_default_syntax(const OnigSyntaxType* syntax);
extern
void onig_copy_syntax(OnigSyntaxType* to, const OnigSyntaxType* from);
extern
unsigned int onig_get_syntax_op(const OnigSyntaxType* syntax);
extern
unsigned int onig_get_syntax_op2(const OnigSyntaxType* syntax);
extern
unsigned int onig_get_syntax_behavior(const OnigSyntaxType* syntax);
extern
OnigOptionType onig_get_syntax_options(const OnigSyntaxType* syntax);
extern
void onig_set_syntax_op(OnigSyntaxType* syntax, unsigned int op);
extern
void onig_set_syntax_op2(OnigSyntaxType* syntax, unsigned int op2);
extern
void onig_set_syntax_behavior(OnigSyntaxType* syntax, unsigned int behavior);
extern
void onig_set_syntax_options(OnigSyntaxType* syntax, OnigOptionType options);
extern
int onig_set_meta_char(OnigSyntaxType* syntax, unsigned int what, OnigCodePoint code);
extern
void onig_copy_encoding(OnigEncodingType *to, OnigEncoding from);
extern
OnigCaseFoldType onig_get_default_case_fold_flag(void);
extern
int onig_set_default_case_fold_flag(OnigCaseFoldType case_fold_flag);
extern
unsigned int onig_get_match_stack_limit_size(void);
extern
int onig_set_match_stack_limit_size(unsigned int size);
extern
unsigned int onig_get_parse_depth_limit(void);
extern
int onig_set_parse_depth_limit(unsigned int depth);
extern
int onig_end(void);
extern
const char* onig_version(void);
extern
const char* onig_copyright(void);




extern VALUE rb_cEncoding;
enum ruby_encoding_consts {
    RUBY_ENCODING_INLINE_MAX = 127,
    RUBY_ENCODING_SHIFT = (RUBY_FL_USHIFT+10),
    RUBY_ENCODING_MASK = (RUBY_ENCODING_INLINE_MAX<<RUBY_ENCODING_SHIFT
                                                              ),
    RUBY_ENCODING_MAXNAMELEN = 42
};
static inline void
RB_ENCODING_SET_INLINED(VALUE obj, int encindex)
{
    VALUE f = encindex;
    f <<= RUBY_ENCODING_SHIFT;
    RB_FL_UNSET_RAW(obj, RUBY_ENCODING_MASK);
    RB_FL_SET_RAW(obj, f);
}
static inline int
RB_ENCODING_GET_INLINED(VALUE obj)
{
    VALUE ret = RB_FL_TEST_RAW(obj, RUBY_ENCODING_MASK) >> RUBY_ENCODING_SHIFT;
    return ((int)ret);
}
typedef const OnigEncodingType rb_encoding;

int rb_char_to_option_kcode(int c, int *option, int *kcode);
int rb_enc_replicate(const char *name, rb_encoding *src);
int rb_define_dummy_encoding(const char *name);
__attribute__((__pure__))
int rb_enc_dummy_p(rb_encoding *enc);
__attribute__((__pure__))
int rb_enc_to_index(rb_encoding *enc);
int rb_enc_get_index(VALUE obj);
static inline int
RB_ENCODING_GET(VALUE obj)
{
    int encindex = RB_ENCODING_GET_INLINED(obj);
    if (encindex == RUBY_ENCODING_INLINE_MAX) {
        return rb_enc_get_index(obj);
    }
    else {
        return encindex;
    }
}
void rb_enc_set_index(VALUE obj, int encindex);
static inline void
RB_ENCODING_SET(VALUE obj, int encindex)
{
    rb_enc_set_index(obj, encindex);
}
static inline void
RB_ENCODING_CODERANGE_SET(VALUE obj, int encindex, enum ruby_coderange_type cr)
{
    RB_ENCODING_SET(obj, encindex);
    RB_ENC_CODERANGE_SET(obj, cr);
}
__attribute__((__pure__))
int rb_enc_capable(VALUE obj);
int rb_enc_find_index(const char *name);
int rb_enc_alias(const char *alias, const char *orig);
int rb_to_encoding_index(VALUE obj);
rb_encoding *rb_to_encoding(VALUE obj);
rb_encoding *rb_find_encoding(VALUE obj);
rb_encoding *rb_enc_get(VALUE obj);
rb_encoding *rb_enc_compatible(VALUE str1, VALUE str2);
rb_encoding *rb_enc_check(VALUE str1,VALUE str2);
VALUE rb_enc_associate_index(VALUE obj, int encindex);
VALUE rb_enc_associate(VALUE obj, rb_encoding *enc);
void rb_enc_copy(VALUE dst, VALUE src);
rb_encoding *rb_enc_from_index(int idx);
rb_encoding *rb_enc_find(const char *name);
static inline const char *
rb_enc_name(rb_encoding *enc)
{
    return enc->name;
}
static inline int
rb_enc_mbminlen(rb_encoding *enc)
{
    return enc->min_enc_len;
}
static inline int
rb_enc_mbmaxlen(rb_encoding *enc)
{
    return enc->max_enc_len;
}
int rb_enc_mbclen(const char *p, const char *e, rb_encoding *enc);
int rb_enc_fast_mbclen(const char *p, const char *e, rb_encoding *enc);
int rb_enc_precise_mbclen(const char *p, const char *e, rb_encoding *enc);
int rb_enc_ascget(const char *p, const char *e, int *len, rb_encoding *enc);
unsigned int rb_enc_codepoint_len(const char *p, const char *e, int *len, rb_encoding *enc);
static inline unsigned int
rb_enc_codepoint(const char *p, const char *e, rb_encoding *enc)
{
    return rb_enc_codepoint_len(p, e, 0, enc);
}
static inline OnigCodePoint
rb_enc_mbc_to_codepoint(const char *p, const char *e, rb_encoding *enc)
{
    const OnigUChar *up = ((const OnigUChar *)p);
    const OnigUChar *ue = ((const OnigUChar *)e);
    return (enc)->mbc_to_code((up),(ue),enc);
}
int rb_enc_codelen(int code, rb_encoding *enc);
static inline int
rb_enc_code_to_mbclen(int c, rb_encoding *enc)
{
    OnigCodePoint uc = ((OnigCodePoint)c);
    return (enc)->code_to_mbclen(uc,enc);
}
static inline int
rb_enc_mbcput(unsigned int c, void *buf, rb_encoding *enc)
{
    OnigCodePoint uc = ((OnigCodePoint)c);
    OnigUChar *ubuf = ((OnigUChar *)buf);
    return (enc)->code_to_mbc(uc,ubuf,enc);
}
static inline char *
rb_enc_prev_char(const char *s, const char *p, const char *e, rb_encoding *enc)
{
    const OnigUChar *us = ((const OnigUChar *)s);
    const OnigUChar *up = ((const OnigUChar *)p);
    const OnigUChar *ue = ((const OnigUChar *)e);
    OnigUChar *ur = onigenc_get_prev_char_head(enc, us, up, ue);
    return ((char *)ur);
}
static inline char *
rb_enc_left_char_head(const char *s, const char *p, const char *e, rb_encoding *enc)
{
    const OnigUChar *us = ((const OnigUChar *)s);
    const OnigUChar *up = ((const OnigUChar *)p);
    const OnigUChar *ue = ((const OnigUChar *)e);
    OnigUChar *ur = onigenc_get_left_adjust_char_head(enc, us, up, ue);
    return ((char *)ur);
}
static inline char *
rb_enc_right_char_head(const char *s, const char *p, const char *e, rb_encoding *enc)
{
    const OnigUChar *us = ((const OnigUChar *)s);
    const OnigUChar *up = ((const OnigUChar *)p);
    const OnigUChar *ue = ((const OnigUChar *)e);
    OnigUChar *ur = onigenc_get_right_adjust_char_head(enc, us, up, ue);
    return ((char *)ur);
}
static inline char *
rb_enc_step_back(const char *s, const char *p, const char *e, int n, rb_encoding *enc)
{
    const OnigUChar *us = ((const OnigUChar *)s);
    const OnigUChar *up = ((const OnigUChar *)p);
    const OnigUChar *ue = ((const OnigUChar *)e);
    const OnigUChar *ur = onigenc_step_back(enc, us, up, ue, n);
    return ((char *)ur);
}
static inline int
rb_enc_asciicompat_inline(rb_encoding *enc)
{
    return rb_enc_mbminlen(enc)==1 && !rb_enc_dummy_p(enc);
}
static inline _Bool
rb_enc_asciicompat(rb_encoding *enc)
{
    if (rb_enc_mbminlen(enc) != 1) {
        return 0;
    }
    else if (rb_enc_dummy_p(enc)) {
        return 0;
    }
    else {
        return 1;
    }
}
static inline _Bool
rb_enc_str_asciicompat_p(VALUE str)
{
    rb_encoding *enc = rb_enc_get(str);
    return rb_enc_asciicompat(enc);
}
VALUE rb_enc_from_encoding(rb_encoding *enc);
__attribute__((__pure__))
int rb_enc_unicode_p(rb_encoding *enc);
__attribute__((__returns_nonnull__))
rb_encoding *rb_ascii8bit_encoding(void);
__attribute__((__returns_nonnull__))
rb_encoding *rb_utf8_encoding(void);
__attribute__((__returns_nonnull__))
rb_encoding *rb_usascii_encoding(void);
rb_encoding *rb_locale_encoding(void);
rb_encoding *rb_filesystem_encoding(void);
rb_encoding *rb_default_external_encoding(void);
rb_encoding *rb_default_internal_encoding(void);
__attribute__((__const__))
int rb_ascii8bit_encindex(void);
static inline _Bool
RB_ENCODING_IS_ASCII8BIT(VALUE obj)
{
    return RB_ENCODING_GET_INLINED(obj) == rb_ascii8bit_encindex();
}
__attribute__((__const__))
int rb_utf8_encindex(void);
__attribute__((__const__))
int rb_usascii_encindex(void);
int rb_locale_encindex(void);
int rb_filesystem_encindex(void);
VALUE rb_enc_default_external(void);
VALUE rb_enc_default_internal(void);
void rb_enc_set_default_external(VALUE encoding);
void rb_enc_set_default_internal(VALUE encoding);
VALUE rb_locale_charmap(VALUE klass);




static inline _Bool
rb_enc_is_newline(const char *p, const char *e, rb_encoding *enc)
{
    OnigUChar *up = ((OnigUChar *)p);
    OnigUChar *ue = ((OnigUChar *)e);
    return (enc)->is_mbc_newline((up),(ue),enc);
}
static inline _Bool
rb_enc_isctype(OnigCodePoint c, OnigCtype t, rb_encoding *enc)
{
    return (enc)->is_code_ctype(c,t,enc);
}
static inline _Bool
rb_enc_isascii(OnigCodePoint c, rb_encoding *enc)
{
    return ((c) < 128);
}
static inline _Bool
rb_enc_isalpha(OnigCodePoint c, rb_encoding *enc)
{
    return (enc)->is_code_ctype(c,1,enc);
}
static inline _Bool
rb_enc_islower(OnigCodePoint c, rb_encoding *enc)
{
    return (enc)->is_code_ctype(c,6,enc);
}
static inline _Bool
rb_enc_isupper(OnigCodePoint c, rb_encoding *enc)
{
    return (enc)->is_code_ctype(c,10,enc);
}
static inline _Bool
rb_enc_ispunct(OnigCodePoint c, rb_encoding *enc)
{
    return (enc)->is_code_ctype(c,8,enc);
}
static inline _Bool
rb_enc_isalnum(OnigCodePoint c, rb_encoding *enc)
{
    return (enc)->is_code_ctype(c,13,enc);
}
static inline _Bool
rb_enc_isprint(OnigCodePoint c, rb_encoding *enc)
{
    return (enc)->is_code_ctype(c,7,enc);
}
static inline _Bool
rb_enc_isspace(OnigCodePoint c, rb_encoding *enc)
{
    return (enc)->is_code_ctype(c,9,enc);
}
static inline _Bool
rb_enc_isdigit(OnigCodePoint c, rb_encoding *enc)
{
    return (enc)->is_code_ctype(c,4,enc);
}
__attribute__((__const__))
int rb_enc_toupper(int c, rb_encoding *enc);
__attribute__((__const__))
int rb_enc_tolower(int c, rb_encoding *enc);




__attribute__((__nonnull__ ()))
char *rb_enc_path_next(const char *path, const char *end, rb_encoding *enc);
__attribute__((__nonnull__ ()))
char *rb_enc_path_skip_prefix(const char *path, const char *end, rb_encoding *enc);
__attribute__((__nonnull__ ()))
char *rb_enc_path_last_separator(const char *path, const char *end, rb_encoding *enc);
__attribute__((__nonnull__ ()))
char *rb_enc_path_end(const char *path, const char *end, rb_encoding *enc);
__attribute__((__nonnull__ (1, 4)))
const char *ruby_enc_find_basename(const char *name, long *baselen, long *alllen, rb_encoding *enc);
__attribute__((__nonnull__ (1, 3)))
const char *ruby_enc_find_extname(const char *name, long *len, rb_encoding *enc);




VALUE rb_enc_reg_new(const char *ptr, long len, rb_encoding *enc, int opts);




__attribute__((__nonnull__ (2)))
__attribute__((__format__(__printf__, 2, 3)))
VALUE rb_enc_sprintf(rb_encoding *enc, const char *fmt, ...);
__attribute__((__nonnull__ (2)))
__attribute__((__format__(__printf__, 2, 0)))
VALUE rb_enc_vsprintf(rb_encoding *enc, const char *fmt, va_list ap);
__attribute__((__noreturn__))
__attribute__((__nonnull__ (3)))
__attribute__((__format__(__printf__, 3, 4)))
void rb_enc_raise(rb_encoding *enc, VALUE exc, const char *fmt, ...);




VALUE rb_enc_str_new(const char *ptr, long len, rb_encoding *enc);
__attribute__((__nonnull__ (1)))
VALUE rb_enc_str_new_cstr(const char *ptr, rb_encoding *enc);
VALUE rb_enc_str_new_static(const char *ptr, long len, rb_encoding *enc);
VALUE rb_enc_interned_str(const char *ptr, long len, rb_encoding *enc);
__attribute__((__nonnull__ (1)))
VALUE rb_enc_interned_str_cstr(const char *ptr, rb_encoding *enc);
long rb_enc_strlen(const char *head, const char *tail, rb_encoding *enc);
char *rb_enc_nth(const char *head, const char *tail, long nth, rb_encoding *enc);
VALUE rb_obj_encoding(VALUE obj);
VALUE rb_enc_str_buf_cat(VALUE str, const char *ptr, long len, rb_encoding *enc);
VALUE rb_enc_uint_chr(unsigned int code, rb_encoding *enc);
VALUE rb_external_str_new_with_enc(const char *ptr, long len, rb_encoding *enc);
VALUE rb_str_export_to_enc(VALUE obj, rb_encoding *enc);
VALUE rb_str_conv_enc(VALUE str, rb_encoding *from, rb_encoding *to);
VALUE rb_str_conv_enc_opts(VALUE str, rb_encoding *from, rb_encoding *to, int ecflags, VALUE ecopts);
int rb_enc_str_coderange(VALUE str);
long rb_str_coderange_scan_restartable(const char *str, const char *end, rb_encoding *enc, int *cr);
int rb_enc_str_asciionly_p(VALUE str);
__attribute__((__nonnull__ ()))
long rb_memsearch(const void *x, long m, const void *y, long n, rb_encoding *enc);
__attribute__((__nonnull__ ()))
static inline VALUE
rbimpl_enc_str_new_cstr(const char *str, rb_encoding *enc)
{
    long len = rbimpl_strlen(str);
    return rb_enc_str_new_static(str, len, enc);
}




ID rb_intern3(const char *name, long len, rb_encoding *enc);
__attribute__((__nonnull__ ()))
int rb_enc_symname_p(const char *str, rb_encoding *enc);
int rb_enc_symname2_p(const char *name, long len, rb_encoding *enc);
ID rb_check_id_cstr(const char *ptr, long len, rb_encoding *enc);
VALUE rb_check_symbol_cstr(const char *ptr, long len, rb_encoding *enc);




typedef enum {
    econv_invalid_byte_sequence,
    econv_undefined_conversion,
    econv_destination_buffer_full,
    econv_source_buffer_empty,
    econv_finished,
    econv_after_output,
    econv_incomplete_input
} rb_econv_result_t;
typedef struct rb_econv_t rb_econv_t;
VALUE rb_str_encode(VALUE str, VALUE to, int ecflags, VALUE ecopts);
int rb_econv_has_convpath_p(const char* from_encoding, const char* to_encoding);
int rb_econv_prepare_options(VALUE opthash, VALUE *ecopts, int ecflags);
int rb_econv_prepare_opts(VALUE opthash, VALUE *ecopts);
rb_econv_t *rb_econv_open(const char *source_encoding, const char *destination_encoding, int ecflags);
rb_econv_t *rb_econv_open_opts(const char *source_encoding, const char *destination_encoding, int ecflags, VALUE ecopts);
rb_econv_result_t rb_econv_convert(rb_econv_t *ec,
    const unsigned char **source_buffer_ptr, const unsigned char *source_buffer_end,
    unsigned char **destination_buffer_ptr, unsigned char *destination_buffer_end,
    int flags);
void rb_econv_close(rb_econv_t *ec);
int rb_econv_set_replacement(rb_econv_t *ec, const unsigned char *str, size_t len, const char *encname);
int rb_econv_decorate_at_first(rb_econv_t *ec, const char *decorator_name);
int rb_econv_decorate_at_last(rb_econv_t *ec, const char *decorator_name);
VALUE rb_econv_open_exc(const char *senc, const char *denc, int ecflags);
int rb_econv_insert_output(rb_econv_t *ec,
    const unsigned char *str, size_t len, const char *str_encoding);
const char *rb_econv_encoding_to_insert_output(rb_econv_t *ec);
void rb_econv_check_error(rb_econv_t *ec);
VALUE rb_econv_make_exception(rb_econv_t *ec);
int rb_econv_putbackable(rb_econv_t *ec);
void rb_econv_putback(rb_econv_t *ec, unsigned char *p, int n);
const char *rb_econv_asciicompat_encoding(const char *encname);
VALUE rb_econv_str_convert(rb_econv_t *ec, VALUE src, int flags);
VALUE rb_econv_substr_convert(rb_econv_t *ec, VALUE src, long byteoff, long bytesize, int flags);
VALUE rb_econv_str_append(rb_econv_t *ec, VALUE src, VALUE dst, int flags);
VALUE rb_econv_substr_append(rb_econv_t *ec, VALUE src, long byteoff, long bytesize, VALUE dst, int flags);
VALUE rb_econv_append(rb_econv_t *ec, const char *bytesrc, long bytesize, VALUE dst, int flags);
void rb_econv_binmode(rb_econv_t *ec);
enum ruby_econv_flag_type {
    RUBY_ECONV_ERROR_HANDLER_MASK = 0x000000ff,
    RUBY_ECONV_INVALID_MASK = 0x0000000f,
    RUBY_ECONV_INVALID_REPLACE = 0x00000002,
    RUBY_ECONV_UNDEF_MASK = 0x000000f0,
    RUBY_ECONV_UNDEF_REPLACE = 0x00000020,
    RUBY_ECONV_UNDEF_HEX_CHARREF = 0x00000030,
    RUBY_ECONV_DECORATOR_MASK = 0x0000ff00,
    RUBY_ECONV_NEWLINE_DECORATOR_MASK = 0x00003f00,
    RUBY_ECONV_NEWLINE_DECORATOR_READ_MASK = 0x00000f00,
    RUBY_ECONV_NEWLINE_DECORATOR_WRITE_MASK = 0x00003000,
    RUBY_ECONV_UNIVERSAL_NEWLINE_DECORATOR = 0x00000100,
    RUBY_ECONV_CRLF_NEWLINE_DECORATOR = 0x00001000,
    RUBY_ECONV_CR_NEWLINE_DECORATOR = 0x00002000,
    RUBY_ECONV_XML_TEXT_DECORATOR = 0x00004000,
    RUBY_ECONV_XML_ATTR_CONTENT_DECORATOR = 0x00008000,
    RUBY_ECONV_STATEFUL_DECORATOR_MASK = 0x00f00000,
    RUBY_ECONV_XML_ATTR_QUOTE_DECORATOR = 0x00100000,
    RUBY_ECONV_DEFAULT_NEWLINE_DECORATOR =
        0,
    RUBY_ECONV_PARTIAL_INPUT = 0x00010000,
    RUBY_ECONV_AFTER_OUTPUT = 0x00020000,
    RUBY_ECONV_FLAGS_PLACEHOLDER
};


VALUE rb_fstring(VALUE);
VALUE rb_fstring_cstr(const char *str);
VALUE rb_fstring_enc_new(const char *ptr, long len, rb_encoding *enc);
int rb_str_buf_cat_escaped_char(VALUE result, unsigned int c, int unicode_p);
int rb_str_symname_p(VALUE);
VALUE rb_str_quote_unprintable(VALUE);
char *rb_str_fill_terminator(VALUE str, const int termlen);
void rb_str_change_terminator_length(VALUE str, const int oldtermlen, const int termlen);
VALUE rb_str_locktmp_ensure(VALUE str, VALUE (*func)(VALUE), VALUE arg);
VALUE rb_str_chomp_string(VALUE str, VALUE chomp);
VALUE rb_external_str_with_enc(VALUE str, rb_encoding *eenc);
VALUE rb_str_cat_conv_enc_opts(VALUE newstr, long ofs, const char *ptr, long len,
                               rb_encoding *from, int ecflags, VALUE ecopts);
VALUE rb_enc_str_scrub(rb_encoding *enc, VALUE str, VALUE repl);
VALUE rb_str_escape(VALUE str);
size_t rb_str_memsize(VALUE);
char *rb_str_to_cstr(VALUE str);
const char *ruby_escaped_char(int c);
void rb_str_make_independent(VALUE str);
int rb_enc_str_coderange_scan(VALUE str, rb_encoding *enc);
static inline _Bool STR_EMBED_P(VALUE str);
static inline _Bool STR_SHARED_P(VALUE str);
static inline VALUE QUOTE(VALUE v);
static inline VALUE QUOTE_ID(ID v);
static inline _Bool is_ascii_string(VALUE str);
static inline _Bool is_broken_string(VALUE str);
static inline VALUE rb_str_eql_internal(const VALUE str1, const VALUE str2);


VALUE rb_str_tmp_frozen_acquire(VALUE str);
void rb_str_tmp_frozen_release(VALUE str, VALUE tmp);
VALUE rb_setup_fake_str(struct RString *fake_str, const char *name, long len, rb_encoding *enc);
VALUE rb_str_upto_each(VALUE, VALUE, int, int (*each)(VALUE, VALUE), VALUE);
VALUE rb_str_upto_endless_each(VALUE, int (*each)(VALUE, VALUE), VALUE);




VALUE rb_fstring_new(const char *ptr, long len);
VALUE rb_obj_as_string_result(VALUE str, VALUE obj);
VALUE rb_str_opt_plus(VALUE x, VALUE y);
VALUE rb_str_concat_literals(size_t num, const VALUE *strary);
VALUE rb_str_eql(VALUE str1, VALUE str2);
VALUE rb_id_quote_unprintable(ID);
VALUE rb_sym_proc_call(ID mid, int argc, const VALUE *argv, int kw_splat, VALUE passed_proc);
struct rb_execution_context_struct;
VALUE rb_ec_str_resurrect(struct rb_execution_context_struct *ec, VALUE str);


static inline VALUE
QUOTE(VALUE v)
{
    return rb_str_quote_unprintable(v);
}
static inline VALUE
QUOTE_ID(ID i)
{
    return rb_id_quote_unprintable(i);
}
static inline _Bool
STR_EMBED_P(VALUE str)
{
    return ! RB_FL_TEST_RAW(str, ((VALUE)RUBY_FL_USER1));
}
static inline _Bool
STR_SHARED_P(VALUE str)
{
    return RB_FL_ALL_RAW(str, ((VALUE)RUBY_FL_USER1) | RUBY_ELTS_SHARED);
}
static inline _Bool
is_ascii_string(VALUE str)
{
    return rb_enc_str_coderange(str) == RUBY_ENC_CODERANGE_7BIT;
}
static inline _Bool
is_broken_string(VALUE str)
{
    return rb_enc_str_coderange(str) == RUBY_ENC_CODERANGE_BROKEN;
}
static inline VALUE
rb_str_eql_internal(const VALUE str1, const VALUE str2)
{
    const long len = RSTRING_LEN(str1);
    const char *ptr1, *ptr2;
    if (len != RSTRING_LEN(str2)) return ((VALUE)RUBY_Qfalse);
    if (!rb_str_comparable(str1, str2)) return ((VALUE)RUBY_Qfalse);
    if ((ptr1 = RSTRING_PTR(str1)) == (ptr2 = RSTRING_PTR(str2)))
        return ((VALUE)RUBY_Qtrue);
    if (memcmp(ptr1, ptr2, len) == 0)
        return ((VALUE)RUBY_Qtrue);
    return ((VALUE)RUBY_Qfalse);
}
extern long rb_backtrace_length_limit;
extern VALUE rb_eEAGAIN;
extern VALUE rb_eEWOULDBLOCK;
extern VALUE rb_eEINPROGRESS;
__attribute__((__format__(__printf__, 3, 0)))
void rb_report_bug_valist(VALUE file, int line, const char *fmt, va_list args);
__attribute__((__noreturn__)) void rb_async_bug_errno(const char *,int);
const char *rb_builtin_type_name(int t);
const char *rb_builtin_class_name(VALUE x);
__attribute__((__format__(__printf__, (1), (3)))) void rb_warn_deprecated(const char *fmt, const char *suggest, ...);
__attribute__((__format__(__printf__, (2), (4)))) void rb_warn_deprecated_to_remove(const char *removal, const char *fmt, const char *suggest, ...);
__attribute__((__format__(__printf__, 6, 0)))
VALUE rb_syntax_error_append(VALUE, VALUE, int, int, rb_encoding*, const char*, va_list);
__attribute__((__format__(__printf__, (2), (3)))) void rb_enc_warn(rb_encoding *enc, const char *fmt, ...);
__attribute__((__format__(__printf__, (2), (3)))) void rb_sys_enc_warning(rb_encoding *enc, const char *fmt, ...);
__attribute__((__format__(__printf__, (3), (4)))) void rb_syserr_enc_warning(int err, rb_encoding *enc, const char *fmt, ...);
rb_warning_category_t rb_warning_category_from_name(VALUE category);
_Bool rb_warning_category_enabled_p(rb_warning_category_t category);
VALUE rb_name_err_new(VALUE mesg, VALUE recv, VALUE method);
VALUE rb_nomethod_err_new(VALUE mesg, VALUE recv, VALUE method, VALUE args, int priv);
VALUE rb_key_err_new(VALUE mesg, VALUE recv, VALUE name);
__attribute__((__format__(__printf__, (1), (2)))) VALUE rb_warning_string(const char *fmt, ...);
__attribute__((__format__(__printf__, 2, 0)))
__attribute__((__noreturn__)) void rb_vraise(VALUE, const char *, va_list);
__attribute__((__noreturn__)) static inline void rb_raise_cstr(VALUE etype, const char *mesg);
__attribute__((__noreturn__)) static inline void rb_raise_cstr_i(VALUE etype, VALUE mesg);
__attribute__((__noreturn__)) static inline void rb_name_err_raise_str(VALUE mesg, VALUE recv, VALUE name);
__attribute__((__noreturn__)) static inline void rb_name_err_raise(const char *mesg, VALUE recv, VALUE name);
__attribute__((__noreturn__)) static inline void rb_key_err_raise(VALUE mesg, VALUE recv, VALUE name);
static inline void Check_Type(VALUE v, enum ruby_value_type t);
static inline _Bool rb_typeddata_is_instance_of_inline(VALUE obj, const rb_data_type_t *data_type);


int rb_bug_reporter_add(void (*func)(FILE *, void *), void *data);
__attribute__((__noreturn__)) void rb_sys_fail_path_in(const char *func_name, VALUE path);
__attribute__((__noreturn__)) void rb_syserr_fail_path_in(const char *func_name, int err, VALUE path);
VALUE rb_syserr_new_path_in(const char *func_name, int n, VALUE path);


static inline void
rb_raise_cstr_i(VALUE etype, VALUE mesg)
{
    VALUE exc = rb_exc_new_str(etype, mesg);
    rb_exc_raise(exc);
}
static inline void
rb_raise_cstr(VALUE etype, const char *mesg)
{
    VALUE str = ((__builtin_constant_p(mesg) ? rbimpl_str_new_cstr : rb_str_new_cstr) (mesg));
    rb_raise_cstr_i(etype, str);
}
static inline void
rb_name_err_raise_str(VALUE mesg, VALUE recv, VALUE name)
{
    VALUE exc = rb_name_err_new(mesg, recv, name);
    rb_exc_raise(exc);
}
static inline void
rb_name_err_raise(const char *mesg, VALUE recv, VALUE name)
{
    VALUE str = (__builtin_constant_p(mesg) ? rb_fstring_new((mesg), (long)strlen(mesg)) : (rb_fstring_cstr)(mesg));
    rb_name_err_raise_str(str, recv, name);
}
static inline void
rb_key_err_raise(VALUE mesg, VALUE recv, VALUE name)
{
    VALUE exc = rb_key_err_new(mesg, recv, name);
    rb_exc_raise(exc);
}
static inline _Bool
rb_typeddata_is_instance_of_inline(VALUE obj, const rb_data_type_t *data_type)
{
    return RB_TYPE_P(obj, RUBY_T_DATA) && RTYPEDDATA_P(obj) && (RTYPEDDATA_TYPE(obj) == data_type);
}
extern ID ruby_static_id_signo;
extern ID ruby_static_id_status;
VALUE rb_refinement_module_get_refined_class(VALUE module);
void rb_class_modify_check(VALUE);
__attribute__((__noreturn__)) VALUE rb_f_raise(int argc, VALUE *argv);
VALUE rb_get_backtrace(VALUE info);
void rb_call_end_proc(VALUE data);
void rb_mark_end_proc(void);
void Init_class_hierarchy(void);
void Init_enc(void);
void Init_ext(void);
void Init_File(void);
void Init_heap(void);
int Init_enc_set_filesystem_encoding(void);
void Init_newline(void);
void Init_BareVM(void);
void Init_vm_objects(void);
void Init_vm_backtrace(void);
void Init_vm_eval(void);static inline 
void Init_vm_stack_canary(void);
void Init_eval_method(void);
void rb_call_inits(void);
struct rb_id_table;
enum rb_id_table_iterator_result {
    ID_TABLE_CONTINUE = ST_CONTINUE,
    ID_TABLE_STOP = ST_STOP,
    ID_TABLE_DELETE = ST_DELETE,
    ID_TABLE_REPLACE = ST_REPLACE,
    ID_TABLE_ITERATOR_RESULT_END
};
struct rb_id_table *rb_id_table_create(size_t size);
void rb_id_table_free(struct rb_id_table *tbl);
void rb_id_table_clear(struct rb_id_table *tbl);
size_t rb_id_table_size(const struct rb_id_table *tbl);
size_t rb_id_table_memsize(const struct rb_id_table *tbl);
int rb_id_table_insert(struct rb_id_table *tbl, ID id, VALUE val);
int rb_id_table_lookup(struct rb_id_table *tbl, ID id, VALUE *valp);
int rb_id_table_delete(struct rb_id_table *tbl, ID id);
typedef enum rb_id_table_iterator_result rb_id_table_update_callback_func_t(ID *id, VALUE *val, void *data, int existing);
typedef enum rb_id_table_iterator_result rb_id_table_foreach_func_t(ID id, VALUE val, void *data);
typedef enum rb_id_table_iterator_result rb_id_table_foreach_values_func_t(VALUE val, void *data);
void rb_id_table_foreach(struct rb_id_table *tbl, rb_id_table_foreach_func_t *func, void *data);
void rb_id_table_foreach_with_replace(struct rb_id_table *tbl, rb_id_table_foreach_func_t *func, rb_id_table_update_callback_func_t *replace, void *data);
void rb_id_table_foreach_values(struct rb_id_table *tbl, rb_id_table_foreach_values_func_t *func, void *data);
struct rb_subclass_entry {
    VALUE klass;
    struct rb_subclass_entry *next;
    struct rb_subclass_entry *prev;
};
struct rb_iv_index_tbl_entry {
    uint32_t index;
    rb_serial_t class_serial;
    VALUE class_value;
};
struct rb_cvar_class_tbl_entry {
    uint32_t index;
    rb_serial_t global_cvar_state;
    VALUE class_value;
};
struct rb_classext_struct {
    struct st_table *iv_index_tbl;
    struct st_table *iv_tbl;
    struct rb_id_table *m_tbl;
    struct rb_id_table *const_tbl;
    struct rb_id_table *callable_m_tbl;
    struct rb_id_table *cc_tbl;
    struct rb_id_table *cvc_tbl;
    struct rb_subclass_entry *subclasses;
    struct rb_subclass_entry *subclass_entry;
    struct rb_subclass_entry *module_subclass_entry;
    const VALUE origin_;
    const VALUE refined_class;
    rb_alloc_func_t allocator;
    const VALUE includer;
};
struct RClass {
    struct RBasic basic;
    VALUE super;
    struct rb_classext_struct *ptr;
    rb_serial_t class_serial;
};
typedef struct rb_subclass_entry rb_subclass_entry_t;
typedef struct rb_classext_struct rb_classext_t;
void rb_class_subclass_add(VALUE super, VALUE klass);
void rb_class_remove_from_super_subclasses(VALUE);
void rb_class_remove_subclass_head(VALUE);
int rb_singleton_class_internal_p(VALUE sklass);
VALUE rb_class_boot(VALUE);
VALUE rb_class_s_alloc(VALUE klass);
VALUE rb_module_s_alloc(VALUE klass);
void rb_module_set_initialized(VALUE module);
void rb_module_check_initializable(VALUE module);
VALUE rb_make_metaclass(VALUE, VALUE);
VALUE rb_include_class_new(VALUE, VALUE);
void rb_class_foreach_subclass(VALUE klass, void (*f)(VALUE, VALUE), VALUE);
void rb_class_detach_subclasses(VALUE);
void rb_class_detach_module_subclasses(VALUE);
void rb_class_remove_from_module_subclasses(VALUE);
VALUE rb_obj_methods(int argc, const VALUE *argv, VALUE obj);
VALUE rb_obj_protected_methods(int argc, const VALUE *argv, VALUE obj);
VALUE rb_obj_private_methods(int argc, const VALUE *argv, VALUE obj);
VALUE rb_obj_public_methods(int argc, const VALUE *argv, VALUE obj);
VALUE rb_special_singleton_class(VALUE);
VALUE rb_singleton_class_clone_and_attach(VALUE obj, VALUE attach);
VALUE rb_singleton_class_get(VALUE obj);
void rb_undef_methods_from(VALUE klass, VALUE super);
static inline void RCLASS_SET_ORIGIN(VALUE klass, VALUE origin);
static inline void RICLASS_SET_ORIGIN_SHARED_MTBL(VALUE iclass);
static inline VALUE RCLASS_SUPER(VALUE klass);
static inline VALUE RCLASS_SET_SUPER(VALUE klass, VALUE super);
static inline void RCLASS_SET_INCLUDER(VALUE iclass, VALUE klass);


VALUE rb_class_inherited(VALUE, VALUE);
VALUE rb_keyword_error_new(const char *, VALUE);


static inline void
RCLASS_SET_ORIGIN(VALUE klass, VALUE origin)
{
    rb_obj_write((VALUE)(klass), __extension__({
   ;
   ; __typeof__((VALUE *)(&((((struct RClass *)(klass))->ptr)->origin_))) unaligned_member_access_result = ((VALUE *)(&((((struct RClass *)(klass))->ptr)->origin_)));
   ; unaligned_member_access_result; }), (VALUE)(origin), "./internal/class.h", 157);
    if (klass != origin) RB_FL_SET(origin, ((VALUE)RUBY_FL_USER5));
}
static inline void
RICLASS_SET_ORIGIN_SHARED_MTBL(VALUE iclass)
{
    RB_FL_SET(iclass, ((VALUE)RUBY_FL_USER8));
}
static inline _Bool
RICLASS_OWNS_M_TBL_P(VALUE iclass)
{
    return RB_FL_TEST_RAW(iclass, ((VALUE)RUBY_FL_USER5) | ((VALUE)RUBY_FL_USER8)) == ((VALUE)RUBY_FL_USER5);
}
static inline void
RCLASS_SET_INCLUDER(VALUE iclass, VALUE klass)
{
    rb_obj_write((VALUE)(iclass), __extension__({
   ;
   ; __typeof__((VALUE *)(&((((struct RClass *)(iclass))->ptr)->includer))) unaligned_member_access_result = ((VALUE *)(&((((struct RClass *)(iclass))->ptr)->includer)));
   ; unaligned_member_access_result; }), (VALUE)(klass), "./internal/class.h", 176);
}
static inline VALUE
RCLASS_SUPER(VALUE klass)
{
    return ((struct RClass *)(klass))->super;
}
static inline VALUE
RCLASS_SET_SUPER(VALUE klass, VALUE super)
{
    if (super) {
        rb_class_remove_from_super_subclasses(klass);
        rb_class_subclass_add(super, klass);
    }
    rb_obj_write((VALUE)(klass), __extension__({
   ;
   ; __typeof__((VALUE *)(&((struct RClass *)(klass))->super)) unaligned_member_access_result = ((VALUE *)(&((struct RClass *)(klass))->super));
   ; unaligned_member_access_result; }), (VALUE)(super), "./internal/class.h", 192);
    return super;
}
VALUE rb_class_search_ancestor(VALUE klass, VALUE super);
__attribute__((__noreturn__)) void rb_undefined_alloc(VALUE klass);
double rb_num_to_dbl(VALUE val);
VALUE rb_obj_dig(int argc, VALUE *argv, VALUE self, VALUE notfound);
VALUE rb_immutable_obj_clone(int, VALUE *, VALUE);
VALUE rb_check_convert_type_with_id(VALUE,int,const char*,ID);
int rb_bool_expected(VALUE, const char *);
static inline void RBASIC_CLEAR_CLASS(VALUE obj);
static inline void RBASIC_SET_CLASS_RAW(VALUE obj, VALUE klass);
static inline void RBASIC_SET_CLASS(VALUE obj, VALUE klass);
static inline struct st_table *ROBJECT_IV_INDEX_TBL_inline(VALUE obj);


int rb_opts_exception_p(VALUE opts, int default_value);




__attribute__((__const__)) VALUE rb_obj_equal(VALUE obj1, VALUE obj2);
__attribute__((__const__)) VALUE rb_obj_not(VALUE obj);
VALUE rb_obj_not_equal(VALUE obj1, VALUE obj2);
void rb_obj_copy_ivar(VALUE dest, VALUE obj);
VALUE rb_false(VALUE obj);
VALUE rb_convert_type_with_id(VALUE v, int t, const char* nam, ID mid);
VALUE rb_obj_size(VALUE self, VALUE args, VALUE obj);
VALUE rb_get_freeze_opt(int argc, VALUE *argv);


static inline void
RBASIC_SET_CLASS_RAW(VALUE obj, VALUE klass)
{
    const VALUE *ptr = &((struct RBasic *)(obj))->klass;
    *(VALUE *)ptr = klass;
}
static inline void
RBASIC_CLEAR_CLASS(VALUE obj)
{
    RBASIC_SET_CLASS_RAW(obj, 0);
}
static inline void
RBASIC_SET_CLASS(VALUE obj, VALUE klass)
{
    VALUE oldv = RBASIC_CLASS(obj);
    RBASIC_SET_CLASS_RAW(obj, klass);
    (rb_obj_written((VALUE)(obj), (VALUE)(oldv), (VALUE)(klass), "./internal/object.h", 65));
}
__attribute__((__pure__))
static inline struct st_table *
ROBJECT_IV_INDEX_TBL_inline(VALUE obj)
{
    if (RB_FL_ANY_RAW(obj, ROBJECT_EMBED)) {
        VALUE klass = rb_obj_class(obj);
        return ((((struct RClass *)(klass))->ptr)->iv_index_tbl);
    }
    else {
        const struct RObject *const ptr = ((struct RObject *)(obj));
        return ptr->as.heap.iv_index_tbl;
    }
}
struct rb_iseq_struct;
VALUE rb_parser_set_yydebug(VALUE, VALUE);
void *rb_parser_load_file(VALUE parser, VALUE name);
void rb_parser_keep_script_lines(VALUE vparser);


VALUE rb_parser_set_context(VALUE, const struct rb_iseq_struct *, int);


struct rb_block;
struct rb_iseq_struct;
VALUE rb_proc_location(VALUE self);
st_index_t rb_hash_proc(st_index_t hash, VALUE proc);
int rb_block_pair_yield_optimizable(void);
int rb_block_arity(void);
int rb_block_min_max_arity(int *max);
VALUE rb_block_to_s(VALUE self, const struct rb_block *block, const char *additional_info);
VALUE rb_callable_receiver(VALUE);


VALUE rb_func_proc_new(rb_block_call_func_t func, VALUE val);
VALUE rb_func_lambda_new(rb_block_call_func_t func, VALUE val, int min_argc, int max_argc);
VALUE rb_iseq_location(const struct rb_iseq_struct *iseq);
VALUE rb_sym_to_proc(VALUE sym);


VALUE rb_reg_compile(VALUE str, int options, const char *sourcefile, int sourceline);
VALUE rb_reg_check_preprocess(VALUE);
long rb_reg_search0(VALUE, VALUE, long, int, int);
VALUE rb_reg_match_p(VALUE re, VALUE str, long pos);
_Bool rb_reg_start_with_p(VALUE re, VALUE str);
VALUE rb_reg_hash(VALUE re);
VALUE rb_reg_equal(VALUE re1, VALUE re2);
void rb_backref_set_string(VALUE string, long pos, long len);
void rb_match_unbusy(VALUE);
int rb_match_count(VALUE match);
int rb_match_nth_defined(int nth, VALUE match);


VALUE rb_reg_new_ary(VALUE ary, int options);


VALUE rb_to_symbol_type(VALUE obj);
VALUE rb_sym_intern(const char *ptr, long len, rb_encoding *enc);
VALUE rb_sym_intern_ascii(const char *ptr, long len);
VALUE rb_sym_intern_ascii_cstr(const char *ptr);
int rb_is_const_name(VALUE name);
int rb_is_class_name(VALUE name);
int rb_is_instance_name(VALUE name);
int rb_is_local_name(VALUE name);
__attribute__((__pure__)) int rb_is_const_sym(VALUE sym);
__attribute__((__pure__)) int rb_is_attrset_sym(VALUE sym);
ID rb_make_internal_id(void);
ID rb_make_temporary_id(size_t n);
void rb_gc_free_dsymbol(VALUE);
struct rb_thread_struct;
VALUE rb_obj_is_mutex(VALUE obj);
VALUE rb_suppress_tracing(VALUE (*func)(VALUE), VALUE arg);
void rb_thread_execute_interrupts(VALUE th);
VALUE rb_get_coverages(void);
int rb_get_coverage_mode(void);
VALUE rb_default_coverage(int);
VALUE rb_thread_shield_new(void);
_Bool rb_thread_shield_owned(VALUE self);
VALUE rb_thread_shield_wait(VALUE self);
VALUE rb_thread_shield_release(VALUE self);
VALUE rb_thread_shield_destroy(VALUE self);
int rb_thread_to_be_killed(VALUE thread);
void rb_mutex_allow_trap(VALUE self, int val);
VALUE rb_uninterruptible(VALUE (*b_proc)(VALUE), VALUE data);
VALUE rb_mutex_owned_p(VALUE self);
int rb_thread_wait_for_single_fd(int fd, int events, struct timeval * timeout);


VALUE rb_thread_io_blocking_region(rb_blocking_function_t *func, void *data1, int fd);
int ruby_thread_has_gvl_p(void);




int rb_threadptr_execute_interrupts(struct rb_thread_struct *th, int blocking_timing);


typedef struct {
  int coverage_sandboxed;
  intptr_t coverage_fd;
  unsigned int coverage_max_block_size;
} __sanitizer_sandbox_arguments;
void __sanitizer_set_report_path(const char *path);
void __sanitizer_set_report_fd(void *fd);
void __sanitizer_sandbox_on_notify(__sanitizer_sandbox_arguments *args);
void __sanitizer_report_error_summary(const char *error_summary);
uint16_t __sanitizer_unaligned_load16(const void *p);
uint32_t __sanitizer_unaligned_load32(const void *p);
uint64_t __sanitizer_unaligned_load64(const void *p);
void __sanitizer_unaligned_store16(void *p, uint16_t x);
void __sanitizer_unaligned_store32(void *p, uint32_t x);
void __sanitizer_unaligned_store64(void *p, uint64_t x);
int __sanitizer_acquire_crash_state();
void __sanitizer_annotate_contiguous_container(const void *beg,
                                               const void *end,
                                               const void *old_mid,
                                               const void *new_mid);
int __sanitizer_verify_contiguous_container(const void *beg, const void *mid,
                                            const void *end);
const void *__sanitizer_contiguous_container_find_bad_address(const void *beg,
                                                              const void *mid,
                                                              const void *end);
void __sanitizer_print_stack_trace(void);
void __sanitizer_symbolize_pc(void *pc, const char *fmt, char *out_buf,
                              size_t out_buf_size);
void __sanitizer_symbolize_global(void *data_ptr, const char *fmt,
                                  char *out_buf, size_t out_buf_size);
void __sanitizer_set_death_callback(void (*callback)(void));
void __sanitizer_weak_hook_memcmp(void *called_pc, const void *s1,
                                  const void *s2, size_t n, int result);
void __sanitizer_weak_hook_strncmp(void *called_pc, const char *s1,
                                  const char *s2, size_t n, int result);
void __sanitizer_weak_hook_strncasecmp(void *called_pc, const char *s1,
                                       const char *s2, size_t n, int result);
void __sanitizer_weak_hook_strcmp(void *called_pc, const char *s1,
                                  const char *s2, int result);
void __sanitizer_weak_hook_strcasecmp(void *called_pc, const char *s1,
                                      const char *s2, int result);
void __sanitizer_weak_hook_strstr(void *called_pc, const char *s1,
                                  const char *s2, char *result);
void __sanitizer_weak_hook_strcasestr(void *called_pc, const char *s1,
                                      const char *s2, char *result);
void __sanitizer_weak_hook_memmem(void *called_pc,
                                  const void *s1, size_t len1,
                                  const void *s2, size_t len2, void *result);
void __sanitizer_print_memory_profile(size_t top_percent,
                                      size_t max_number_of_contexts);
void __sanitizer_start_switch_fiber(void **fake_stack_save,
                                    const void *bottom, size_t size);
void __sanitizer_finish_switch_fiber(void *fake_stack_save,
                                     const void **bottom_old,
                                     size_t *size_old);
int __sanitizer_get_module_and_offset_for_pc(void *pc, char *module_path,
                                             size_t module_path_len,
                                             void **pc_offset);
void __asan_poison_memory_region(void const volatile *addr, size_t size);
void __asan_unpoison_memory_region(void const volatile *addr, size_t size);
int __asan_address_is_poisoned(void const volatile *addr);
void *__asan_region_is_poisoned(void *beg, size_t size);
void __asan_describe_address(void *addr);
int __asan_report_present(void);
void *__asan_get_report_pc(void);
void *__asan_get_report_bp(void);
void *__asan_get_report_sp(void);
void *__asan_get_report_address(void);
int __asan_get_report_access_type(void);
size_t __asan_get_report_access_size(void);
const char *__asan_get_report_description(void);
const char *__asan_locate_address(void *addr, char *name, size_t name_size,
                                  void **region_address, size_t *region_size);
size_t __asan_get_alloc_stack(void *addr, void **trace, size_t size,
                              int *thread_id);
size_t __asan_get_free_stack(void *addr, void **trace, size_t size,
                             int *thread_id);
void __asan_get_shadow_mapping(size_t *shadow_scale, size_t *shadow_offset);
void __asan_report_error(void *pc, void *bp, void *sp,
                         void *addr, int is_write, size_t access_size);
void __asan_set_death_callback(void (*callback)(void));
void __asan_set_error_report_callback(void (*callback)(const char *));
void __asan_on_error(void);
void __asan_print_accumulated_stats(void);
const char* __asan_default_options(void);
void *__asan_get_current_fake_stack(void);
void *__asan_addr_is_in_fake_stack(void *fake_stack, void *addr, void **beg,
                                   void **end);
void __asan_handle_no_return(void);
int __asan_update_allocation_context(void* addr);
extern const int ruby_api_version[];
extern const ID rb_iseq_shared_exc_local_tbl[];
static inline rb_snum_t
ISEQ_FLIP_CNT_INCREMENT(const rb_iseq_t *iseq)
{
    rb_snum_t cnt = iseq->body->variable.flip_count;
    iseq->body->variable.flip_count += 1;
    return cnt;
}
static inline VALUE *
ISEQ_ORIGINAL_ISEQ(const rb_iseq_t *iseq)
{
    return iseq->body->variable.original_iseq;
}
static inline void
ISEQ_ORIGINAL_ISEQ_CLEAR(const rb_iseq_t *iseq)
{
    void *ptr = iseq->body->variable.original_iseq;
    iseq->body->variable.original_iseq = ((void *)0);
    if (ptr) {
        ruby_xfree(ptr);
    }
}
static inline VALUE *
ISEQ_ORIGINAL_ISEQ_ALLOC(const rb_iseq_t *iseq, long size)
{
    return iseq->body->variable.original_iseq =
        ((VALUE *)ruby_xmalloc2((size), sizeof(VALUE)));
}
struct iseq_compile_data {
    const VALUE err_info;
    const VALUE catch_table_ary;
    struct iseq_label_data *start_label;
    struct iseq_label_data *end_label;
    struct iseq_label_data *redo_label;
    const rb_iseq_t *current_block;
    struct iseq_compile_data_ensure_node_stack *ensure_node_stack;
    struct {
      struct iseq_compile_data_storage *storage_head;
      struct iseq_compile_data_storage *storage_current;
    } node;
    struct {
      struct iseq_compile_data_storage *storage_head;
      struct iseq_compile_data_storage *storage_current;
    } insn;
    _Bool in_rescue;
    int loopval_popped;
    int last_line;
    int label_no;
    int node_level;
    int isolated_depth;
    unsigned int ci_index;
    const rb_compile_option_t *option;
    struct rb_id_table *ivar_cache_table;
    const struct rb_builtin_function *builtin_function_table;
    const NODE *root_node;
};
static inline struct iseq_compile_data *
ISEQ_COMPILE_DATA(const rb_iseq_t *iseq)
{
    if (iseq->flags & ((VALUE)RUBY_FL_USER6)) {
 return iseq->aux.compile_data;
    }
    else {
 return ((void *)0);
    }
}
static inline void
ISEQ_COMPILE_DATA_ALLOC(rb_iseq_t *iseq)
{
    iseq->aux.compile_data = (((struct iseq_compile_data *)ruby_xcalloc((1), sizeof(struct iseq_compile_data))));
    iseq->flags |= ((VALUE)RUBY_FL_USER6);
}
static inline void
ISEQ_COMPILE_DATA_CLEAR(rb_iseq_t *iseq)
{
    iseq->flags &= ~((VALUE)RUBY_FL_USER6);
    iseq->aux.compile_data = ((void *)0);
}
static inline rb_iseq_t *
iseq_imemo_alloc(void)
{
    return (rb_iseq_t *)rb_imemo_new(imemo_iseq, 0, 0, 0, 0);
}
VALUE rb_iseq_ibf_dump(const rb_iseq_t *iseq, VALUE opt);
void rb_ibf_load_iseq_complete(rb_iseq_t *iseq);
const rb_iseq_t *rb_iseq_ibf_load(VALUE str);
const rb_iseq_t *rb_iseq_ibf_load_bytes(const char *cstr, size_t);
VALUE rb_iseq_ibf_load_extra_data(VALUE str);
void rb_iseq_init_trace(rb_iseq_t *iseq);
int rb_iseq_add_local_tracepoint_recursively(const rb_iseq_t *iseq, rb_event_flag_t turnon_events, VALUE tpval, unsigned int target_line, _Bool target_bmethod);
int rb_iseq_remove_local_tracepoint_recursively(const rb_iseq_t *iseq, VALUE tpval);
const rb_iseq_t *rb_iseq_load_iseq(VALUE fname);
unsigned int *rb_iseq_insns_info_decode_positions(const struct rb_iseq_constant_body *body);
int rb_vm_insn_addr2opcode(const void *addr);


VALUE rb_iseq_compile_node(rb_iseq_t *iseq, const NODE *node);
VALUE rb_iseq_compile_callback(rb_iseq_t *iseq, const struct rb_iseq_new_with_callback_callback_func * ifunc);
VALUE *rb_iseq_original_iseq(const rb_iseq_t *iseq);
void rb_iseq_build_from_ary(rb_iseq_t *iseq, VALUE misc,
       VALUE locals, VALUE args,
       VALUE exception, VALUE body);
void rb_iseq_mark_insn_storage(struct iseq_compile_data_storage *arena);
VALUE rb_iseq_load(VALUE data, VALUE parent, VALUE opt);
VALUE rb_iseq_parameters(const rb_iseq_t *iseq, int is_proc);
unsigned int rb_iseq_line_no(const rb_iseq_t *iseq, size_t pos);
int rb_iseq_node_id(const rb_iseq_t *iseq, size_t pos);
void rb_iseq_trace_set(const rb_iseq_t *iseq, rb_event_flag_t turnon_events);
void rb_iseq_trace_set_all(rb_event_flag_t turnon_events);
void rb_iseq_insns_info_encode_positions(const rb_iseq_t *iseq);
struct rb_iseq_constant_body *rb_iseq_constant_body_alloc(void);
VALUE rb_iseqw_new(const rb_iseq_t *iseq);
const rb_iseq_t *rb_iseqw_to_iseq(VALUE iseqw);
VALUE rb_iseq_absolute_path(const rb_iseq_t *iseq);
int rb_iseq_from_eval_p(const rb_iseq_t *iseq);
VALUE rb_iseq_type(const rb_iseq_t *iseq);
VALUE rb_iseq_label(const rb_iseq_t *iseq);
VALUE rb_iseq_base_label(const rb_iseq_t *iseq);
VALUE rb_iseq_first_lineno(const rb_iseq_t *iseq);
VALUE rb_iseq_method_name(const rb_iseq_t *iseq);
void rb_iseq_code_location(const rb_iseq_t *iseq, int *first_lineno, int *first_column, int *last_lineno, int *last_column);
void rb_iseq_remove_coverage_all(void);
const rb_iseq_t *rb_method_iseq(VALUE body);
const rb_iseq_t *rb_proc_get_iseq(VALUE proc, int *is_proc);
struct rb_compile_option_struct {
    unsigned int inline_const_cache: 1;
    unsigned int peephole_optimization: 1;
    unsigned int tailcall_optimization: 1;
    unsigned int specialized_instruction: 1;
    unsigned int operands_unification: 1;
    unsigned int instructions_unification: 1;
    unsigned int stack_caching: 1;
    unsigned int frozen_string_literal: 1;
    unsigned int debug_frozen_string_literal: 1;
    unsigned int coverage_enabled: 1;
    int debug_level;
};
struct iseq_insn_info_entry {
    int line_no;
    int node_id;
    rb_event_flag_t events;
};
struct iseq_catch_table_entry {
    enum catch_type {
 CATCH_TYPE_RESCUE = __builtin_choose_expr( __builtin_constant_p(1), ((VALUE)(1)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(1)),
 CATCH_TYPE_ENSURE = __builtin_choose_expr( __builtin_constant_p(2), ((VALUE)(2)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(2)),
 CATCH_TYPE_RETRY = __builtin_choose_expr( __builtin_constant_p(3), ((VALUE)(3)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(3)),
 CATCH_TYPE_BREAK = __builtin_choose_expr( __builtin_constant_p(4), ((VALUE)(4)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(4)),
 CATCH_TYPE_REDO = __builtin_choose_expr( __builtin_constant_p(5), ((VALUE)(5)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(5)),
 CATCH_TYPE_NEXT = __builtin_choose_expr( __builtin_constant_p(6), ((VALUE)(6)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(6))
    } type;
    rb_iseq_t *iseq;
    unsigned int start;
    unsigned int end;
    unsigned int cont;
    unsigned int sp;
};
struct iseq_catch_table { unsigned int size; struct iseq_catch_table_entry entries[]; } __attribute__((packed));
static inline int
iseq_catch_table_bytes(int n)
{
    enum {
 catch_table_entry_size = sizeof(struct iseq_catch_table_entry),
 catch_table_entries_max = (0x7fffffff - __builtin_offsetof (struct iseq_catch_table, entries)) / catch_table_entry_size
    };
    if (n > catch_table_entries_max) rb_fatal("too large iseq_catch_table - %d", n);
    return (int)(__builtin_offsetof (struct iseq_catch_table, entries) +
   n * catch_table_entry_size);
}
struct iseq_compile_data_storage {
    struct iseq_compile_data_storage *next;
    unsigned int pos;
    unsigned int size;
    char buff[];
};
enum defined_type {
    DEFINED_NOT_DEFINED,
    DEFINED_NIL = 1,
    DEFINED_IVAR,
    DEFINED_LVAR,
    DEFINED_GVAR,
    DEFINED_CVAR,
    DEFINED_CONST,
    DEFINED_METHOD,
    DEFINED_YIELD,
    DEFINED_ZSUPER,
    DEFINED_SELF,
    DEFINED_TRUE,
    DEFINED_FALSE,
    DEFINED_ASGN,
    DEFINED_EXPR,
    DEFINED_REF,
    DEFINED_FUNC,
    DEFINED_CONST_FROM
};
VALUE rb_iseq_defined_string(enum defined_type type);
VALUE rb_iseq_local_variables(const rb_iseq_t *iseq);


enum rb_debug_counter_type {
RB_DEBUG_COUNTER_mc_inline_hit,
RB_DEBUG_COUNTER_mc_inline_miss_klass,
RB_DEBUG_COUNTER_mc_inline_miss_invalidated,
RB_DEBUG_COUNTER_mc_inline_miss_empty,
RB_DEBUG_COUNTER_mc_inline_miss_same_cc,
RB_DEBUG_COUNTER_mc_inline_miss_same_cme,
RB_DEBUG_COUNTER_mc_inline_miss_same_def,
RB_DEBUG_COUNTER_mc_inline_miss_diff,
RB_DEBUG_COUNTER_cvar_write_inline_hit,
RB_DEBUG_COUNTER_cvar_read_inline_hit,
RB_DEBUG_COUNTER_cvar_inline_miss,
RB_DEBUG_COUNTER_cvar_class_invalidate,
RB_DEBUG_COUNTER_cvar_include_invalidate,
RB_DEBUG_COUNTER_mc_cme_complement,
RB_DEBUG_COUNTER_mc_cme_complement_hit,
RB_DEBUG_COUNTER_mc_search,
RB_DEBUG_COUNTER_mc_search_notfound,
RB_DEBUG_COUNTER_mc_search_super,
RB_DEBUG_COUNTER_ci_packed,
RB_DEBUG_COUNTER_ci_kw,
RB_DEBUG_COUNTER_ci_nokw,
RB_DEBUG_COUNTER_ci_runtime,
RB_DEBUG_COUNTER_cc_new,
RB_DEBUG_COUNTER_cc_temp,
RB_DEBUG_COUNTER_cc_found_in_ccs,
RB_DEBUG_COUNTER_cc_not_found_in_ccs,
RB_DEBUG_COUNTER_cc_ent_invalidate,
RB_DEBUG_COUNTER_cc_cme_invalidate,
RB_DEBUG_COUNTER_cc_invalidate_leaf,
RB_DEBUG_COUNTER_cc_invalidate_leaf_ccs,
RB_DEBUG_COUNTER_cc_invalidate_leaf_callable,
RB_DEBUG_COUNTER_cc_invalidate_tree,
RB_DEBUG_COUNTER_cc_invalidate_tree_cme,
RB_DEBUG_COUNTER_cc_invalidate_tree_callable,
RB_DEBUG_COUNTER_cc_invalidate_negative,
RB_DEBUG_COUNTER_ccs_free,
RB_DEBUG_COUNTER_ccs_maxlen,
RB_DEBUG_COUNTER_ccs_found,
RB_DEBUG_COUNTER_ccs_not_found,
RB_DEBUG_COUNTER_call0_public,
RB_DEBUG_COUNTER_call0_other,
RB_DEBUG_COUNTER_gccct_hit,
RB_DEBUG_COUNTER_gccct_miss,
RB_DEBUG_COUNTER_gccct_null,
RB_DEBUG_COUNTER_iseq_num,
RB_DEBUG_COUNTER_iseq_cd_num,
RB_DEBUG_COUNTER_ccf_general,
RB_DEBUG_COUNTER_ccf_iseq_setup,
RB_DEBUG_COUNTER_ccf_iseq_setup_0start,
RB_DEBUG_COUNTER_ccf_iseq_setup_tailcall_0start,
RB_DEBUG_COUNTER_ccf_iseq_fix,
RB_DEBUG_COUNTER_ccf_iseq_opt,
RB_DEBUG_COUNTER_ccf_iseq_kw1,
RB_DEBUG_COUNTER_ccf_iseq_kw2,
RB_DEBUG_COUNTER_ccf_cfunc,
RB_DEBUG_COUNTER_ccf_cfunc_with_frame,
RB_DEBUG_COUNTER_ccf_ivar,
RB_DEBUG_COUNTER_ccf_attrset,
RB_DEBUG_COUNTER_ccf_method_missing,
RB_DEBUG_COUNTER_ccf_zsuper,
RB_DEBUG_COUNTER_ccf_bmethod,
RB_DEBUG_COUNTER_ccf_opt_send,
RB_DEBUG_COUNTER_ccf_opt_call,
RB_DEBUG_COUNTER_ccf_opt_block_call,
RB_DEBUG_COUNTER_ccf_opt_struct_aref,
RB_DEBUG_COUNTER_ccf_opt_struct_aset,
RB_DEBUG_COUNTER_ccf_super_method,
RB_DEBUG_COUNTER_frame_push,
RB_DEBUG_COUNTER_frame_push_method,
RB_DEBUG_COUNTER_frame_push_block,
RB_DEBUG_COUNTER_frame_push_class,
RB_DEBUG_COUNTER_frame_push_top,
RB_DEBUG_COUNTER_frame_push_cfunc,
RB_DEBUG_COUNTER_frame_push_ifunc,
RB_DEBUG_COUNTER_frame_push_eval,
RB_DEBUG_COUNTER_frame_push_rescue,
RB_DEBUG_COUNTER_frame_push_dummy,
RB_DEBUG_COUNTER_frame_R2R,
RB_DEBUG_COUNTER_frame_R2C,
RB_DEBUG_COUNTER_frame_C2C,
RB_DEBUG_COUNTER_frame_C2R,
RB_DEBUG_COUNTER_ivar_get_ic_hit,
RB_DEBUG_COUNTER_ivar_get_ic_miss,
RB_DEBUG_COUNTER_ivar_get_ic_miss_serial,
RB_DEBUG_COUNTER_ivar_get_ic_miss_unset,
RB_DEBUG_COUNTER_ivar_get_ic_miss_noobject,
RB_DEBUG_COUNTER_ivar_set_ic_hit,
RB_DEBUG_COUNTER_ivar_set_ic_miss,
RB_DEBUG_COUNTER_ivar_set_ic_miss_serial,
RB_DEBUG_COUNTER_ivar_set_ic_miss_unset,
RB_DEBUG_COUNTER_ivar_set_ic_miss_iv_hit,
RB_DEBUG_COUNTER_ivar_set_ic_miss_noobject,
RB_DEBUG_COUNTER_ivar_get_base,
RB_DEBUG_COUNTER_ivar_set_base,
RB_DEBUG_COUNTER_lvar_get,
RB_DEBUG_COUNTER_lvar_get_dynamic,
RB_DEBUG_COUNTER_lvar_set,
RB_DEBUG_COUNTER_lvar_set_dynamic,
RB_DEBUG_COUNTER_lvar_set_slowpath,
RB_DEBUG_COUNTER_gc_count,
RB_DEBUG_COUNTER_gc_minor_newobj,
RB_DEBUG_COUNTER_gc_minor_malloc,
RB_DEBUG_COUNTER_gc_minor_method,
RB_DEBUG_COUNTER_gc_minor_capi,
RB_DEBUG_COUNTER_gc_minor_stress,
RB_DEBUG_COUNTER_gc_major_nofree,
RB_DEBUG_COUNTER_gc_major_oldgen,
RB_DEBUG_COUNTER_gc_major_shady,
RB_DEBUG_COUNTER_gc_major_force,
RB_DEBUG_COUNTER_gc_major_oldmalloc,
RB_DEBUG_COUNTER_gc_enter_start,
RB_DEBUG_COUNTER_gc_enter_mark_continue,
RB_DEBUG_COUNTER_gc_enter_sweep_continue,
RB_DEBUG_COUNTER_gc_enter_rest,
RB_DEBUG_COUNTER_gc_enter_finalizer,
RB_DEBUG_COUNTER_gc_isptr_trial,
RB_DEBUG_COUNTER_gc_isptr_range,
RB_DEBUG_COUNTER_gc_isptr_align,
RB_DEBUG_COUNTER_gc_isptr_maybe,
RB_DEBUG_COUNTER_obj_newobj,
RB_DEBUG_COUNTER_obj_newobj_slowpath,
RB_DEBUG_COUNTER_obj_newobj_wb_unprotected,
RB_DEBUG_COUNTER_obj_free,
RB_DEBUG_COUNTER_obj_promote,
RB_DEBUG_COUNTER_obj_wb_unprotect,
RB_DEBUG_COUNTER_obj_obj_embed,
RB_DEBUG_COUNTER_obj_obj_transient,
RB_DEBUG_COUNTER_obj_obj_ptr,
RB_DEBUG_COUNTER_obj_str_ptr,
RB_DEBUG_COUNTER_obj_str_embed,
RB_DEBUG_COUNTER_obj_str_shared,
RB_DEBUG_COUNTER_obj_str_nofree,
RB_DEBUG_COUNTER_obj_str_fstr,
RB_DEBUG_COUNTER_obj_ary_embed,
RB_DEBUG_COUNTER_obj_ary_transient,
RB_DEBUG_COUNTER_obj_ary_ptr,
RB_DEBUG_COUNTER_obj_ary_extracapa,
RB_DEBUG_COUNTER_obj_ary_shared_create,
RB_DEBUG_COUNTER_obj_ary_shared,
RB_DEBUG_COUNTER_obj_ary_shared_root_occupied,
RB_DEBUG_COUNTER_obj_hash_empty,
RB_DEBUG_COUNTER_obj_hash_1,
RB_DEBUG_COUNTER_obj_hash_2,
RB_DEBUG_COUNTER_obj_hash_3,
RB_DEBUG_COUNTER_obj_hash_4,
RB_DEBUG_COUNTER_obj_hash_5_8,
RB_DEBUG_COUNTER_obj_hash_g8,
RB_DEBUG_COUNTER_obj_hash_null,
RB_DEBUG_COUNTER_obj_hash_ar,
RB_DEBUG_COUNTER_obj_hash_st,
RB_DEBUG_COUNTER_obj_hash_transient,
RB_DEBUG_COUNTER_obj_hash_force_convert,
RB_DEBUG_COUNTER_obj_struct_embed,
RB_DEBUG_COUNTER_obj_struct_transient,
RB_DEBUG_COUNTER_obj_struct_ptr,
RB_DEBUG_COUNTER_obj_data_empty,
RB_DEBUG_COUNTER_obj_data_xfree,
RB_DEBUG_COUNTER_obj_data_imm_free,
RB_DEBUG_COUNTER_obj_data_zombie,
RB_DEBUG_COUNTER_obj_match_under4,
RB_DEBUG_COUNTER_obj_match_ge4,
RB_DEBUG_COUNTER_obj_match_ge8,
RB_DEBUG_COUNTER_obj_match_ptr,
RB_DEBUG_COUNTER_obj_iclass_ptr,
RB_DEBUG_COUNTER_obj_class_ptr,
RB_DEBUG_COUNTER_obj_module_ptr,
RB_DEBUG_COUNTER_obj_bignum_ptr,
RB_DEBUG_COUNTER_obj_bignum_embed,
RB_DEBUG_COUNTER_obj_float,
RB_DEBUG_COUNTER_obj_complex,
RB_DEBUG_COUNTER_obj_rational,
RB_DEBUG_COUNTER_obj_regexp_ptr,
RB_DEBUG_COUNTER_obj_file_ptr,
RB_DEBUG_COUNTER_obj_symbol,
RB_DEBUG_COUNTER_obj_imemo_ment,
RB_DEBUG_COUNTER_obj_imemo_iseq,
RB_DEBUG_COUNTER_obj_imemo_env,
RB_DEBUG_COUNTER_obj_imemo_tmpbuf,
RB_DEBUG_COUNTER_obj_imemo_ast,
RB_DEBUG_COUNTER_obj_imemo_cref,
RB_DEBUG_COUNTER_obj_imemo_svar,
RB_DEBUG_COUNTER_obj_imemo_throw_data,
RB_DEBUG_COUNTER_obj_imemo_ifunc,
RB_DEBUG_COUNTER_obj_imemo_memo,
RB_DEBUG_COUNTER_obj_imemo_parser_strterm,
RB_DEBUG_COUNTER_obj_imemo_callinfo,
RB_DEBUG_COUNTER_obj_imemo_callcache,
RB_DEBUG_COUNTER_obj_imemo_constcache,
RB_DEBUG_COUNTER_artable_hint_hit,
RB_DEBUG_COUNTER_artable_hint_miss,
RB_DEBUG_COUNTER_artable_hint_notfound,
RB_DEBUG_COUNTER_heap_xmalloc,
RB_DEBUG_COUNTER_heap_xrealloc,
RB_DEBUG_COUNTER_heap_xfree,
RB_DEBUG_COUNTER_theap_alloc,
RB_DEBUG_COUNTER_theap_alloc_fail,
RB_DEBUG_COUNTER_theap_evacuate,
RB_DEBUG_COUNTER_vm_sync_lock,
RB_DEBUG_COUNTER_vm_sync_lock_enter,
RB_DEBUG_COUNTER_vm_sync_lock_enter_nb,
RB_DEBUG_COUNTER_vm_sync_lock_enter_cr,
RB_DEBUG_COUNTER_vm_sync_barrier,
RB_DEBUG_COUNTER_mjit_exec,
RB_DEBUG_COUNTER_mjit_exec_not_added,
RB_DEBUG_COUNTER_mjit_exec_not_ready,
RB_DEBUG_COUNTER_mjit_exec_not_compiled,
RB_DEBUG_COUNTER_mjit_exec_call_func,
RB_DEBUG_COUNTER_mjit_add_iseq_to_process,
RB_DEBUG_COUNTER_mjit_unload_units,
RB_DEBUG_COUNTER_mjit_frame_VM2VM,
RB_DEBUG_COUNTER_mjit_frame_VM2JT,
RB_DEBUG_COUNTER_mjit_frame_JT2JT,
RB_DEBUG_COUNTER_mjit_frame_JT2VM,
RB_DEBUG_COUNTER_mjit_cancel,
RB_DEBUG_COUNTER_mjit_cancel_ivar_inline,
RB_DEBUG_COUNTER_mjit_cancel_exivar_inline,
RB_DEBUG_COUNTER_mjit_cancel_send_inline,
RB_DEBUG_COUNTER_mjit_cancel_opt_insn,
RB_DEBUG_COUNTER_mjit_cancel_invalidate_all,
RB_DEBUG_COUNTER_mjit_cancel_leave,
RB_DEBUG_COUNTER_mjit_length_unit_queue,
RB_DEBUG_COUNTER_mjit_length_active_units,
RB_DEBUG_COUNTER_mjit_length_compact_units,
RB_DEBUG_COUNTER_mjit_length_stale_units,
RB_DEBUG_COUNTER_mjit_compile_failures,
    RB_DEBUG_COUNTER_MAX
};
void rb_debug_counter_show_results(const char *msg);


size_t ruby_debug_counter_get(const char **names_ptr, size_t *counters_ptr);
void ruby_debug_counter_reset(void);
void ruby_debug_counter_show_at_exit(int enable);


struct rb_yjit_options {
    _Bool yjit_enabled;
    unsigned exec_mem_size;
    unsigned call_threshold;
    _Bool greedy_versioning;
    _Bool no_type_prop;
    unsigned max_versions;
    _Bool gen_stats;
    _Bool test_backend;
};
_Bool rb_yjit_enabled_p(void);
unsigned rb_yjit_call_threshold(void);
void rb_yjit_invalidate_all_method_lookup_assumptions(void);
void rb_yjit_method_lookup_change(VALUE klass, ID mid);
void rb_yjit_cme_invalidate(VALUE cme);
void rb_yjit_collect_vm_usage_insn(int insn);
void rb_yjit_collect_binding_alloc(void);
void rb_yjit_collect_binding_set(void);
_Bool rb_yjit_compile_iseq(const rb_iseq_t *iseq, rb_execution_context_t *ec);
void rb_yjit_init(struct rb_yjit_options *options);
void rb_yjit_bop_redefined(VALUE klass, const rb_method_entry_t *me, enum ruby_basic_operators bop);
void rb_yjit_constant_state_changed(void);
void rb_yjit_iseq_mark(const struct rb_iseq_constant_body *body);
void rb_yjit_iseq_update_references(const struct rb_iseq_constant_body *body);
void rb_yjit_iseq_free(const struct rb_iseq_constant_body *body);
void rb_yjit_before_ractor_spawn(void);
void rb_yjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic);
void rb_yjit_tracing_invalidate_all(void);
enum rb_mjit_iseq_func {
    NOT_ADDED_JIT_ISEQ_FUNC = 0,
    NOT_READY_JIT_ISEQ_FUNC = 1,
    NOT_COMPILED_JIT_ISEQ_FUNC = 2,
    LAST_JIT_ISEQ_FUNC = 3
};
struct mjit_options {
    char on;
    char save_temps;
    char warnings;
    char debug;
    char* debug_flags;
    unsigned int wait;
    unsigned int min_calls;
    int verbose;
    int max_cache_size;
};
struct rb_mjit_compile_info {
    _Bool disable_ivar_cache;
    _Bool disable_exivar_cache;
    _Bool disable_send_cache;
    _Bool disable_inlining;
    _Bool disable_const_cache;
};
typedef VALUE (*mjit_func_t)(rb_execution_context_t *, rb_control_frame_t *);


extern struct mjit_options mjit_opts;
extern _Bool mjit_call_p;
extern void rb_mjit_add_iseq_to_process(const rb_iseq_t *iseq);
extern VALUE rb_mjit_wait_call(rb_execution_context_t *ec, struct rb_iseq_constant_body *body);
extern struct rb_mjit_compile_info* rb_mjit_iseq_compile_info(const struct rb_iseq_constant_body *body);
extern void rb_mjit_recompile_send(const rb_iseq_t *iseq);
extern void rb_mjit_recompile_ivar(const rb_iseq_t *iseq);
extern void rb_mjit_recompile_exivar(const rb_iseq_t *iseq);
extern void rb_mjit_recompile_inlining(const rb_iseq_t *iseq);
extern void rb_mjit_recompile_const(const rb_iseq_t *iseq);


extern void mjit_cancel_all(const char *reason);
extern _Bool mjit_compile(FILE *f, const rb_iseq_t *iseq, const char *funcname, int id);
extern void mjit_init(const struct mjit_options *opts);
extern void mjit_gc_start_hook(void);
extern void mjit_gc_exit_hook(void);
extern void mjit_free_iseq(const rb_iseq_t *iseq);
extern void mjit_update_references(const rb_iseq_t *iseq);
extern void mjit_mark(void);
extern struct mjit_cont *mjit_cont_new(rb_execution_context_t *ec);
extern void mjit_cont_free(struct mjit_cont *cont);
extern void mjit_mark_cc_entries(const struct rb_iseq_constant_body *const body);
__attribute__((__noinline__)) static __attribute__((__cold__)) VALUE mjit_exec_slowpath(rb_execution_context_t *ec, const rb_iseq_t *iseq, struct rb_iseq_constant_body *body);
static VALUE
mjit_exec_slowpath(rb_execution_context_t *ec, const rb_iseq_t *iseq, struct rb_iseq_constant_body *body)
{
    uintptr_t func_i = (uintptr_t)(body->jit_func);
    ((__builtin_expect(!!(!!(func_i <= LAST_JIT_ISEQ_FUNC)), 1)) ? ((void)0) : __builtin_unreachable());
    switch ((enum rb_mjit_iseq_func)func_i) {
      case NOT_ADDED_JIT_ISEQ_FUNC:
        ((void)0);
        if (body->total_calls == mjit_opts.min_calls) {
            rb_mjit_add_iseq_to_process(iseq);
            if ((__builtin_expect(!!(mjit_opts.wait), 0))) {
                return rb_mjit_wait_call(ec, body);
            }
        }
        break;
      case NOT_READY_JIT_ISEQ_FUNC:
        ((void)0);
        break;
      case NOT_COMPILED_JIT_ISEQ_FUNC:
        ((void)0);
        break;
      default:
        break;
    }
    return ((VALUE)RUBY_Qundef);
}
static inline VALUE
mjit_exec(rb_execution_context_t *ec)
{
    const rb_iseq_t *iseq = ec->cfp->iseq;
    struct rb_iseq_constant_body *body = iseq->body;
    _Bool yjit_enabled = 0;
    if (mjit_call_p || yjit_enabled) {
        body->total_calls++;
    }
    if (!(mjit_call_p || yjit_enabled))
        return ((VALUE)RUBY_Qundef);
    ((void)0);
    mjit_func_t func = body->jit_func;
    if (yjit_enabled && func == 0) {
        return ((VALUE)RUBY_Qundef);
    }
    if ((__builtin_expect(!!((uintptr_t)func <= LAST_JIT_ISEQ_FUNC), 0))) {
        ((void)0);
        return mjit_exec_slowpath(ec, iseq, body);
    }
    ((void)0);
    ((void)0);
    return func(ec, ec->cfp);
}
void mjit_child_after_fork(void);
VALUE mjit_pause(_Bool wait_p);
VALUE mjit_resume(void);
void mjit_finish(_Bool close_handle_p);


typedef struct rb_vm_struct ruby_vm_t;
int ruby_vm_destruct(ruby_vm_t *vm);
void ruby_vm_at_exit(void(*func)(ruby_vm_t *));


enum vm_call_flag_bits {
    VM_CALL_ARGS_SPLAT_bit,
    VM_CALL_ARGS_BLOCKARG_bit,
    VM_CALL_FCALL_bit,
    VM_CALL_VCALL_bit,
    VM_CALL_ARGS_SIMPLE_bit,
    VM_CALL_BLOCKISEQ_bit,
    VM_CALL_KWARG_bit,
    VM_CALL_KW_SPLAT_bit,
    VM_CALL_TAILCALL_bit,
    VM_CALL_SUPER_bit,
    VM_CALL_ZSUPER_bit,
    VM_CALL_OPT_SEND_bit,
    VM_CALL_KW_SPLAT_MUT_bit,
    VM_CALL__END
};
struct rb_callinfo_kwarg {
    int keyword_len;
    VALUE keywords[];
};
static inline size_t
rb_callinfo_kwarg_bytes(int keyword_len)
{
    return rb_size_mul_add_or_raise(
        keyword_len,
        sizeof(VALUE),
        sizeof(struct rb_callinfo_kwarg),
        rb_eRuntimeError);
}
struct rb_callinfo {
    VALUE flags;
    const struct rb_callinfo_kwarg *kwarg;
    VALUE mid;
    VALUE flag;
    VALUE argc;
};
static inline _Bool
vm_ci_packed_p(const struct rb_callinfo *ci)
{
    if ((__builtin_expect(!!(((VALUE)ci) & 0x01), 1))) {
        return 1;
    }
    else {
        ((void)0);
        return 0;
    }
}
static inline _Bool
vm_ci_p(const struct rb_callinfo *ci)
{
    if (vm_ci_packed_p(ci) || imemo_type_p((VALUE)ci, imemo_callinfo)) {
        return 1;
    }
    else {
        return 0;
    }
}
static inline ID
vm_ci_mid(const struct rb_callinfo *ci)
{
    if (vm_ci_packed_p(ci)) {
        return (((VALUE)ci) >> (1 + 15 + 16)) & ((((VALUE)1)<<32) - 1);
    }
    else {
        return (ID)ci->mid;
    }
}
static inline unsigned int
vm_ci_flag(const struct rb_callinfo *ci)
{
    if (vm_ci_packed_p(ci)) {
        return (unsigned int)((((VALUE)ci) >> (1 + 15)) & ((((VALUE)1)<<16) - 1));
    }
    else {
        return (unsigned int)ci->flag;
    }
}
static inline unsigned int
vm_ci_argc(const struct rb_callinfo *ci)
{
    if (vm_ci_packed_p(ci)) {
        return (unsigned int)((((VALUE)ci) >> (1)) & ((((VALUE)1)<<15) - 1));
    }
    else {
        return (unsigned int)ci->argc;
    }
}
static inline const struct rb_callinfo_kwarg *
vm_ci_kwarg(const struct rb_callinfo *ci)
{
    if (vm_ci_packed_p(ci)) {
        return ((void *)0);
    }
    else {
        return ci->kwarg;
    }
}
static inline void
vm_ci_dump(const struct rb_callinfo *ci)
{
    if (vm_ci_packed_p(ci)) {
        ruby_debug_printf("packed_ci ID:%s flag:%x argc:%u\n",
                          rb_id2name(vm_ci_mid(ci)), vm_ci_flag(ci), vm_ci_argc(ci));
    }
    else {
        rb_obj_info_dump_loc((VALUE)(ci), "./vm_callinfo.h", 175, __func__);
    }
}
static inline const struct rb_callinfo *
vm_ci_new_(ID mid, unsigned int flag, unsigned int argc, const struct rb_callinfo_kwarg *kwarg, const char *file, int line)
{
    if ((((mid ) & ~((((VALUE)1)<<32) - 1)) ? 0 : ((flag) & ~((((VALUE)1)<<16) - 1)) ? 0 : ((argc) & ~((((VALUE)1)<<15) - 1)) ? 0 : (kwarg) ? 0 : 1)) {
        ((void)0);
        return ((const struct rb_callinfo *) ((((VALUE)(mid )) << (1 + 15 + 16)) | (((VALUE)(flag)) << (1 + 15)) | (((VALUE)(argc)) << (1)) | RUBY_FIXNUM_FLAG));
    }
    const _Bool debug = 0;
    if (debug) ruby_debug_printf("%s:%d ", file, line);
    const struct rb_callinfo *ci = (const struct rb_callinfo *)
      rb_imemo_new(imemo_callinfo,
                   (VALUE)mid,
                   (VALUE)flag,
                   (VALUE)argc,
                   (VALUE)kwarg);
    if (debug) rb_obj_info_dump_loc((VALUE)(ci), "./vm_callinfo.h", 216, __func__);
    if (kwarg) {
        ((void)0);
    }
    else {
        ((void)0);
    }
    ((void)0);
    ((void)0);
    return ci;
}
static inline const struct rb_callinfo *
vm_ci_new_runtime_(ID mid, unsigned int flag, unsigned int argc, const struct rb_callinfo_kwarg *kwarg, const char *file, int line)
{
    ((void)0);
    return vm_ci_new_(mid, flag, argc, kwarg, file, line);
}
static inline _Bool
vm_ci_markable(const struct rb_callinfo *ci)
{
    if (! ci) {
        return 0;
    }
    else if (vm_ci_packed_p(ci)) {
        return 1;
    }
    else {
        ((void)0);
        return ! RB_FL_ANY_RAW((VALUE)ci, ((VALUE)RUBY_FL_USER4));
    }
}
typedef VALUE (*vm_call_handler)(
    struct rb_execution_context_struct *ec,
    struct rb_control_frame_struct *cfp,
    struct rb_calling_info *calling);
struct rb_callcache {
    const VALUE flags;
    const VALUE klass;
    const struct rb_callable_method_entry_struct * const cme_;
    const vm_call_handler call_;
    union {
        const unsigned int attr_index;
        const enum method_missing_reason method_missing_reason;
        VALUE v;
    } aux_;
};
static inline const struct rb_callcache *
vm_cc_new(VALUE klass,
          const struct rb_callable_method_entry_struct *cme,
          vm_call_handler call)
{
    const struct rb_callcache *cc = (const struct rb_callcache *)rb_imemo_new(imemo_callcache, (VALUE)cme, (VALUE)call, 0, klass);
    ((void)0);
    return cc;
}
static inline _Bool
vm_cc_class_check(const struct rb_callcache *cc, VALUE klass)
{
    ((void)0);
    ((void)0);
    return cc->klass == klass;
}
static inline int
vm_cc_markable(const struct rb_callcache *cc)
{
    ((void)0);
    return RB_FL_TEST_RAW((VALUE)cc, ((VALUE)RUBY_FL_USER4)) == 0;
}
static inline const struct rb_callable_method_entry_struct *
vm_cc_cme(const struct rb_callcache *cc)
{
    ((void)0);
    ((void)0);
    return cc->cme_;
}
static inline vm_call_handler
vm_cc_call(const struct rb_callcache *cc)
{
    ((void)0);
    ((void)0);
    return cc->call_;
}
static inline unsigned int
vm_cc_attr_index(const struct rb_callcache *cc)
{
    ((void)0);
    return cc->aux_.attr_index;
}
static inline unsigned int
vm_cc_cmethod_missing_reason(const struct rb_callcache *cc)
{
    ((void)0);
    return cc->aux_.method_missing_reason;
}
static inline _Bool
vm_cc_invalidated_p(const struct rb_callcache *cc)
{
    if (cc->klass && !((vm_cc_cme(cc))->flags & ((VALUE)RUBY_FL_USER9))) {
        return 0;
    }
    else {
        return 1;
    }
}
static inline _Bool
vm_cc_valid_p(const struct rb_callcache *cc, const rb_callable_method_entry_t *cc_cme, VALUE klass)
{
    ((void)0);
    if (cc->klass == klass && !((cc_cme)->flags & ((VALUE)RUBY_FL_USER9))) {
        return 1;
    }
    else {
        return 0;
    }
}
extern const struct rb_callcache *rb_vm_empty_cc(void);
extern const struct rb_callcache *rb_vm_empty_cc_for_super(void);
static inline void
vm_cc_call_set(const struct rb_callcache *cc, vm_call_handler call)
{
    ((void)0);
    ((void)0);
    *(vm_call_handler *)&cc->call_ = call;
}
static inline void
vm_cc_attr_index_set(const struct rb_callcache *cc, int index)
{
    ((void)0);
    ((void)0);
    *(int *)&cc->aux_.attr_index = index;
}
static inline void
vm_cc_method_missing_reason_set(const struct rb_callcache *cc, enum method_missing_reason reason)
{
    ((void)0);
    ((void)0);
    *(enum method_missing_reason *)&cc->aux_.method_missing_reason = reason;
}
static inline void
vm_cc_invalidate(const struct rb_callcache *cc)
{
    ((void)0);
    ((void)0);
    ((void)0);
    *(VALUE *)&cc->klass = 0;
    ((void)0);
}
struct rb_call_data {
    const struct rb_callinfo *ci;
    const struct rb_callcache *cc;
};
struct rb_class_cc_entries {
    int capa;
    int len;
    const struct rb_callable_method_entry_struct *cme;
    struct rb_class_cc_entries_entry {
        const struct rb_callinfo *ci;
        const struct rb_callcache *cc;
    } *entries;
};
void rb_vm_ccs_free(struct rb_class_cc_entries *ccs);


struct RNode;
VALUE ruby_debug_print_value(int level, int debug_level, const char *header, VALUE v);
ID ruby_debug_print_id(int level, int debug_level, const char *header, ID id);
struct RNode *ruby_debug_print_node(int level, int debug_level, const char *header, const struct RNode *node);
int ruby_debug_print_indent(int level, int debug_level, int indent_level);
void ruby_debug_gc_check_func(void);
void ruby_set_debug_option(const char *str);


extern enum ruby_debug_log_mode {
    ruby_debug_log_disabled = 0x00,
    ruby_debug_log_memory = 0x01,
    ruby_debug_log_stderr = 0x02,
    ruby_debug_log_file = 0x04,
} ruby_debug_log_mode;
__attribute__((__format__(__printf__, 4, 5)))
void ruby_debug_log(const char *file, int line, const char *func_name, const char *fmt, ...);
void ruby_debug_log_print(unsigned int n);
_Bool ruby_debug_log_filter(const char *func_name);
typedef long OFFSET;
typedef unsigned long lindex_t;
typedef VALUE GENTRY;
typedef rb_iseq_t *ISEQ;


extern VALUE ruby_vm_const_missing_count;
extern rb_serial_t ruby_vm_global_constant_state;
extern rb_serial_t ruby_vm_class_serial;
extern rb_serial_t ruby_vm_global_cvar_state;


static inline void
CC_SET_FASTPATH(const struct rb_callcache *cc, vm_call_handler func, _Bool enabled)
{
    if ((__builtin_expect(!!(enabled), 1))) {
        vm_cc_call_set(cc, func);
    }
}
static inline struct vm_throw_data *
THROW_DATA_NEW(VALUE val, const rb_control_frame_t *cf, int st)
{
    struct vm_throw_data *obj = (struct vm_throw_data *)rb_imemo_new(imemo_throw_data, val, (VALUE)cf, 0, 0);
    obj->throw_state = st;
    return obj;
}
static inline VALUE
THROW_DATA_VAL(const struct vm_throw_data *obj)
{
    ((void)0);
    return obj->throw_obj;
}
static inline const rb_control_frame_t *
THROW_DATA_CATCH_FRAME(const struct vm_throw_data *obj)
{
    ((void)0);
    return obj->catch_frame;
}
static inline int
THROW_DATA_STATE(const struct vm_throw_data *obj)
{
    ((void)0);
    return obj->throw_state;
}
static inline int
THROW_DATA_CONSUMED_P(const struct vm_throw_data *obj)
{
    ((void)0);
    return obj->flags & ((VALUE)RUBY_FL_USER4);
}
static inline void
THROW_DATA_CATCH_FRAME_SET(struct vm_throw_data *obj, const rb_control_frame_t *cfp)
{
    ((void)0);
    obj->catch_frame = cfp;
}
static inline void
THROW_DATA_STATE_SET(struct vm_throw_data *obj, int st)
{
    ((void)0);
    obj->throw_state = st;
}
static inline void
THROW_DATA_CONSUMED_SET(struct vm_throw_data *obj)
{
    if (imemo_throw_data_p((VALUE)obj) &&
 THROW_DATA_STATE(obj) == RUBY_TAG_BREAK) {
 obj->flags |= ((VALUE)RUBY_FL_USER4);
    }
}
static inline _Bool
vm_call_iseq_optimizable_p(const struct rb_callinfo *ci, const struct rb_callcache *cc)
{
    return !(vm_ci_flag(ci) & (0x01 << VM_CALL_ARGS_SPLAT_bit)) && !(vm_ci_flag(ci) & (0x01 << VM_CALL_KWARG_bit)) &&
        !((rb_method_visibility_t)(((vm_cc_cme(cc))->flags & (((VALUE)RUBY_FL_USER4) | ((VALUE)RUBY_FL_USER5))) >> ((((VALUE)RUBY_FL_USHIFT) + 4)+0)) == METHOD_VISI_PROTECTED);
}
struct rb_ractor_local_storage_type {
    void (*mark)(void *ptr);
    void (*free)(void *ptr);
};
typedef struct rb_ractor_local_key_struct *rb_ractor_local_key_t;


extern VALUE rb_cRactor;
VALUE rb_ractor_stdin(void);
VALUE rb_ractor_stdout(void);
VALUE rb_ractor_stderr(void);
void rb_ractor_stdin_set(VALUE io);
void rb_ractor_stdout_set(VALUE io);
void rb_ractor_stderr_set(VALUE io);
rb_ractor_local_key_t rb_ractor_local_storage_value_newkey(void);
VALUE rb_ractor_local_storage_value(rb_ractor_local_key_t key);
_Bool rb_ractor_local_storage_value_lookup(rb_ractor_local_key_t key, VALUE *val);
void rb_ractor_local_storage_value_set(rb_ractor_local_key_t key, VALUE val);
extern const struct rb_ractor_local_storage_type rb_ractor_local_storage_type_free;
rb_ractor_local_key_t rb_ractor_local_storage_ptr_newkey(const struct rb_ractor_local_storage_type *type);
void *rb_ractor_local_storage_ptr(rb_ractor_local_key_t key);
void rb_ractor_local_storage_ptr_set(rb_ractor_local_key_t key, void *ptr);
VALUE rb_ractor_make_shareable(VALUE obj);
VALUE rb_ractor_make_shareable_copy(VALUE obj);


static inline _Bool
rb_ractor_shareable_p(VALUE obj)
{
    _Bool rb_ractor_shareable_p_continue(VALUE obj);
    if (RB_SPECIAL_CONST_P(obj)) {
        return 1;
    }
    else if (RB_FL_TEST_RAW((obj), RUBY_FL_SHAREABLE)) {
        return 1;
    }
    else {
        return rb_ractor_shareable_p_continue(obj);
    }
}
enum rb_ractor_basket_type {
    basket_type_none,
    basket_type_ref,
    basket_type_copy,
    basket_type_move,
    basket_type_will,
    basket_type_deleted,
    basket_type_reserved,
};
struct rb_ractor_basket {
    _Bool exception;
    enum rb_ractor_basket_type type;
    VALUE v;
    VALUE sender;
};
struct rb_ractor_queue {
    struct rb_ractor_basket *baskets;
    int start;
    int cnt;
    int size;
    unsigned int serial;
    unsigned int reserved_cnt;
};
struct rb_ractor_waiting_list {
    int cnt;
    int size;
    rb_ractor_t **ractors;
};
struct rb_ractor_sync {
    rb_nativethread_lock_t lock;
    rb_nativethread_cond_t cond;
    struct rb_ractor_queue incoming_queue;
    struct rb_ractor_waiting_list taking_ractors;
    _Bool incoming_port_closed;
    _Bool outgoing_port_closed;
    struct ractor_wait {
        enum ractor_wait_status {
            wait_none = 0x00,
            wait_receiving = 0x01,
            wait_taking = 0x02,
            wait_yielding = 0x04,
            wait_moving = 0x08,
        } status;
        enum ractor_wakeup_status {
            wakeup_none,
            wakeup_by_send,
            wakeup_by_yield,
            wakeup_by_take,
            wakeup_by_close,
            wakeup_by_interrupt,
            wakeup_by_retry,
        } wakeup_status;
        struct rb_ractor_basket yielded_basket;
        struct rb_ractor_basket taken_basket;
    } wait;
};
struct rb_ractor_struct {
    struct rb_ractor_pub pub;
    struct rb_ractor_sync sync;
    VALUE receiving_mutex;
    _Bool yield_atexit;
    rb_nativethread_cond_t barrier_wait_cond;
    struct {
        struct list_head set;
        unsigned int cnt;
        unsigned int blocking_cnt;
        unsigned int sleeper;
        rb_global_vm_lock_t gvl;
        rb_execution_context_t *running_ec;
        rb_thread_t *main;
    } threads;
    VALUE thgroup_default;
    VALUE name;
    VALUE loc;
    enum ractor_status {
        ractor_created,
        ractor_running,
        ractor_blocking,
        ractor_terminated,
    } status_;
    struct list_node vmlr_node;
    st_table *local_storage;
    struct rb_id_table *idkey_local_storage;
    VALUE r_stdin;
    VALUE r_stdout;
    VALUE r_stderr;
    VALUE verbose;
    VALUE debug;
    rb_ractor_newobj_cache_t newobj_cache;
    struct gc_mark_func_data_struct {
        void *data;
        void (*mark_func)(VALUE v, void *data);
    } *mfd;
};
static inline VALUE
rb_ractor_self(const rb_ractor_t *r)
{
    return r->pub.self;
}
rb_ractor_t *rb_ractor_main_alloc(void);
void rb_ractor_main_setup(rb_vm_t *vm, rb_ractor_t *main_ractor, rb_thread_t *main_thread);
void rb_ractor_atexit(rb_execution_context_t *ec, VALUE result);
void rb_ractor_atexit_exception(rb_execution_context_t *ec);
void rb_ractor_teardown(rb_execution_context_t *ec);
void rb_ractor_receive_parameters(rb_execution_context_t *ec, rb_ractor_t *g, int len, VALUE *ptr);
void rb_ractor_send_parameters(rb_execution_context_t *ec, rb_ractor_t *g, VALUE args);
VALUE rb_thread_create_ractor(rb_ractor_t *g, VALUE args, VALUE proc);
rb_global_vm_lock_t *rb_ractor_gvl(rb_ractor_t *);
int rb_ractor_living_thread_num(const rb_ractor_t *);
VALUE rb_ractor_thread_list(rb_ractor_t *r);
_Bool rb_ractor_p(VALUE rv);
void rb_ractor_living_threads_init(rb_ractor_t *r);
void rb_ractor_living_threads_insert(rb_ractor_t *r, rb_thread_t *th);
void rb_ractor_living_threads_remove(rb_ractor_t *r, rb_thread_t *th);
void rb_ractor_blocking_threads_inc(rb_ractor_t *r, const char *file, int line);
void rb_ractor_blocking_threads_dec(rb_ractor_t *r, const char *file, int line);
void rb_ractor_vm_barrier_interrupt_running_thread(rb_ractor_t *r);
void rb_ractor_terminate_interrupt_main_thread(rb_ractor_t *r);
void rb_ractor_terminate_all(void);
_Bool rb_ractor_main_p_(void);
void rb_ractor_finish_marking(void);
void rb_ractor_atfork(rb_vm_t *vm, rb_thread_t *th);
VALUE rb_ractor_ensure_shareable(VALUE obj, VALUE name);


_Bool rb_ractor_shareable_p_continue(VALUE obj);
void rb_ractor_local_storage_delkey(rb_ractor_local_key_t key);


static inline _Bool
rb_ractor_main_p(void)
{
    if (ruby_single_main_ractor) {
        return 1;
    }
    else {
        return rb_ractor_main_p_();
    }
}
static inline _Bool
rb_ractor_status_p(rb_ractor_t *r, enum ractor_status status)
{
    return r->status_ == status;
}
static inline void
rb_ractor_sleeper_threads_inc(rb_ractor_t *r)
{
    r->threads.sleeper++;
}
static inline void
rb_ractor_sleeper_threads_dec(rb_ractor_t *r)
{
    r->threads.sleeper--;
}
static inline void
rb_ractor_sleeper_threads_clear(rb_ractor_t *r)
{
    r->threads.sleeper = 0;
}
static inline int
rb_ractor_sleeper_thread_num(rb_ractor_t *r)
{
    return r->threads.sleeper;
}
static inline void
rb_ractor_thread_switch(rb_ractor_t *cr, rb_thread_t *th)
{
    if (cr->threads.running_ec != th->ec) {
        if (0) {
            ruby_debug_printf("rb_ractor_thread_switch ec:%p->%p\n",
                              (void *)cr->threads.running_ec, (void *)th->ec);
        }
    }
    else {
        return;
    }
    if (cr->threads.running_ec != th->ec) {
        th->running_time_us = 0;
    }
    cr->threads.running_ec = th->ec;
    ((void)0);
}
static inline void
rb_ractor_set_current_ec(rb_ractor_t *cr, rb_execution_context_t *ec)
{
    ruby_current_ec = ec;
    if (cr->threads.running_ec != ec) {
        if (0) {
            ruby_debug_printf("rb_ractor_set_current_ec ec:%p->%p\n",
                              (void *)cr->threads.running_ec, (void *)ec);
        }
    }
    else {
        ((void)0);
    }
    cr->threads.running_ec = ec;
}
void rb_vm_ractor_blocking_cnt_inc(rb_vm_t *vm, rb_ractor_t *cr, const char *file, int line);
void rb_vm_ractor_blocking_cnt_dec(rb_vm_t *vm, rb_ractor_t *cr, const char *file, int line);
static inline uint32_t
rb_ractor_id(const rb_ractor_t *r)
{
    return r->pub.id;
}
_Bool rb_vm_locked_p(void);
void rb_vm_lock_body(void);
void rb_vm_unlock_body(void);
struct rb_ractor_struct;
void rb_vm_lock_enter_body_cr(struct rb_ractor_struct *cr, unsigned int *lev );
void rb_vm_lock_enter_body_nb(unsigned int *lev );
void rb_vm_lock_enter_body(unsigned int *lev );
void rb_vm_lock_leave_body(unsigned int *lev );
void rb_vm_barrier(void);
extern struct rb_ractor_struct *ruby_single_main_ractor;
static inline _Bool
rb_multi_ractor_p(void)
{
    if ((__builtin_expect(!!(ruby_single_main_ractor), 1))) {
        ((void)0);
        return 0;
    }
    else {
        return 1;
    }
}
static inline void
rb_vm_lock(const char *file, int line)
{
    ((void)0);
    if (rb_multi_ractor_p()) {
        rb_vm_lock_body();
    }
}
static inline void
rb_vm_unlock(const char *file, int line)
{
    if (rb_multi_ractor_p()) {
        rb_vm_unlock_body();
    }
}
static inline void
rb_vm_lock_enter(unsigned int *lev, const char *file, int line)
{
    ((void)0);
    if (rb_multi_ractor_p()) {
        rb_vm_lock_enter_body(lev );
    }
}
static inline void
rb_vm_lock_enter_nb(unsigned int *lev, const char *file, int line)
{
    ((void)0);
    if (rb_multi_ractor_p()) {
        rb_vm_lock_enter_body_nb(lev );
    }
}
static inline void
rb_vm_lock_leave(unsigned int *lev, const char *file, int line)
{
    if (rb_multi_ractor_p()) {
        rb_vm_lock_leave_body(lev );
    }
}
static inline void
rb_vm_lock_enter_cr(struct rb_ractor_struct *cr, unsigned int *levp, const char *file, int line)
{
    ((void)0);
    rb_vm_lock_enter_body_cr(cr, levp );
}
static inline void
rb_vm_lock_leave_cr(struct rb_ractor_struct *cr, unsigned int *levp, const char *file, int line)
{
    rb_vm_lock_leave_body(levp );
}
struct rb_builtin_function {
    const void * const func_ptr;
    const int argc;
    const int index;
    const char * const name;
    void (*compiler)(FILE *, long, unsigned, _Bool);
};
void rb_load_with_builtin_functions(const char *feature_name, const struct rb_builtin_function *table);
static inline void rb_builtin_function_check_arity0(VALUE (*f)(rb_execution_context_t *ec, VALUE self)){}
static inline void rb_builtin_function_check_arity1(VALUE (*f)(rb_execution_context_t *ec, VALUE self, VALUE)){}
static inline void rb_builtin_function_check_arity2(VALUE (*f)(rb_execution_context_t *ec, VALUE self, VALUE, VALUE)){}
static inline void rb_builtin_function_check_arity3(VALUE (*f)(rb_execution_context_t *ec, VALUE self, VALUE, VALUE, VALUE)){}
static inline void rb_builtin_function_check_arity4(VALUE (*f)(rb_execution_context_t *ec, VALUE self, VALUE, VALUE, VALUE, VALUE)){}
static inline void rb_builtin_function_check_arity5(VALUE (*f)(rb_execution_context_t *ec, VALUE self, VALUE, VALUE, VALUE, VALUE, VALUE)){}
static inline void rb_builtin_function_check_arity6(VALUE (*f)(rb_execution_context_t *ec, VALUE self, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)){}
static inline void rb_builtin_function_check_arity7(VALUE (*f)(rb_execution_context_t *ec, VALUE self, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)){}
static inline void rb_builtin_function_check_arity8(VALUE (*f)(rb_execution_context_t *ec, VALUE self, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)){}
static inline void rb_builtin_function_check_arity9(VALUE (*f)(rb_execution_context_t *ec, VALUE self, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)){}
static inline void rb_builtin_function_check_arity10(VALUE (*f)(rb_execution_context_t *ec, VALUE self, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)){}
static inline void rb_builtin_function_check_arity11(VALUE (*f)(rb_execution_context_t *ec, VALUE self, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)){}
static inline void rb_builtin_function_check_arity12(VALUE (*f)(rb_execution_context_t *ec, VALUE self, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)){}
static inline void rb_builtin_function_check_arity13(VALUE (*f)(rb_execution_context_t *ec, VALUE self, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)){}
static inline void rb_builtin_function_check_arity14(VALUE (*f)(rb_execution_context_t *ec, VALUE self, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)){}
static inline void rb_builtin_function_check_arity15(VALUE (*f)(rb_execution_context_t *ec, VALUE self, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)){}static inline 
__attribute__((__pure__)) VALUE rb_vm_lvar_exposed(rb_execution_context_t *ec, int index);static inline 
VALUE rb_vm_lvar_exposed(rb_execution_context_t *ec, int index);
__attribute__((__pure__)) static inline VALUE rb_vm_lvar(rb_execution_context_t *ec, int index);
static inline VALUE
rb_vm_lvar(rb_execution_context_t *ec, int index)
{
    return ec->cfp->ep[index];
}
struct builtin_binary {
    const char *feature;
    const unsigned char *bin;
    size_t bin_size;
};
struct ruby_dtrace_method_hook_args {
    const char *classname;
    const char *methodname;
    const char *filename;
    int line_no;
    volatile VALUE klass;
    volatile VALUE name;
};


__attribute__((__noinline__)) int rb_dtrace_setup(rb_execution_context_t *, VALUE, ID, struct ruby_dtrace_method_hook_args *);


VALUE rb_str_concat_literals(size_t, const VALUE*);
__attribute__ ((__visibility__("default"))) extern
VALUE rb_vm_exec(rb_execution_context_t *, _Bool);
__attribute__((__pure__)) static inline const VALUE *VM_EP_LEP(const VALUE *);
static inline const VALUE *
VM_EP_LEP(const VALUE *ep)
{
    while (!VM_ENV_LOCAL_P(ep)) {
 ep = VM_ENV_PREV_EP(ep);
    }
    return ep;
}
static inline const rb_control_frame_t *
rb_vm_search_cf_from_ep(const rb_execution_context_t *ec, const rb_control_frame_t *cfp, const VALUE * const ep)
{
    if (!ep) {
 return ((void *)0);
    }
    else {
 const rb_control_frame_t * const eocfp = RUBY_VM_END_CONTROL_FRAME(ec);
 while (cfp < eocfp) {
     if (cfp->ep == ep) {
  return cfp;
     }
     cfp = ((cfp)+1);
 }
 return ((void *)0);
    }
}static inline 
const VALUE *
rb_vm_ep_local_ep(const VALUE *ep)
{
    return VM_EP_LEP(ep);
}
__attribute__((__pure__)) static inline const VALUE *VM_CF_LEP(const rb_control_frame_t * const cfp);
static inline const VALUE *
VM_CF_LEP(const rb_control_frame_t * const cfp)
{
    return VM_EP_LEP(cfp->ep);
}
static inline const VALUE *
VM_CF_PREV_EP(const rb_control_frame_t * const cfp)
{
    return VM_ENV_PREV_EP(cfp->ep);
}
__attribute__((__pure__)) static inline VALUE VM_CF_BLOCK_HANDLER(const rb_control_frame_t * const cfp);
static inline VALUE
VM_CF_BLOCK_HANDLER(const rb_control_frame_t * const cfp)
{
    const VALUE *ep = VM_CF_LEP(cfp);
    return VM_ENV_BLOCK_HANDLER(ep);
}static inline 
int
rb_vm_cframe_keyword_p(const rb_control_frame_t *cfp)
{
    return VM_FRAME_CFRAME_KW_P(cfp);
}static inline 
VALUE
rb_vm_frame_block_handler(const rb_control_frame_t *cfp)
{
    return VM_CF_BLOCK_HANDLER(cfp);
}
static struct rb_captured_block *
VM_CFP_TO_CAPTURED_BLOCK(const rb_control_frame_t *cfp)
{
    ((void)0);
    return (struct rb_captured_block *)&cfp->self;
}
static rb_control_frame_t *
VM_CAPTURED_BLOCK_TO_CFP(const struct rb_captured_block *captured)
{
    rb_control_frame_t *cfp = ((rb_control_frame_t *)((VALUE *)(captured) - 3));
    ((void)0);
    ((void)0);
    return cfp;
}
static int
VM_BH_FROM_CFP_P(VALUE block_handler, const rb_control_frame_t *cfp)
{
    const struct rb_captured_block *captured = VM_CFP_TO_CAPTURED_BLOCK(cfp);
    return ((void *)((block_handler) & ~0x03)) == captured;
}
static VALUE
vm_passed_block_handler(rb_execution_context_t *ec)
{
    VALUE block_handler = ec->passed_block_handler;
    ec->passed_block_handler = 0;
    vm_block_handler_verify(block_handler);
    return block_handler;
}
static rb_cref_t *
vm_cref_new0(VALUE klass, rb_method_visibility_t visi, int module_func, rb_cref_t *prev_cref, int pushed_by_eval, int use_prev_prev, int singleton)
{
    VALUE refinements = ((VALUE)RUBY_Qnil);
    int omod_shared = 0;
    rb_cref_t *cref;
    union {
 rb_scope_visibility_t visi;
 VALUE value;
    } scope_visi;
    scope_visi.visi.method_visi = visi;
    scope_visi.visi.module_func = module_func;
    if (prev_cref != ((void *)0) && prev_cref != (void *)1 ) {
 refinements = CREF_REFINEMENTS(prev_cref);
 if (!RB_NIL_P(refinements)) {
     omod_shared = 1;
     CREF_OMOD_SHARED_SET(prev_cref);
 }
    }
    ((void)0);
    cref = (rb_cref_t *)rb_imemo_new(imemo_cref, klass, (VALUE)(use_prev_prev ? CREF_NEXT(prev_cref) : prev_cref), scope_visi.value, refinements);
    if (pushed_by_eval) CREF_PUSHED_BY_EVAL_SET(cref);
    if (omod_shared) CREF_OMOD_SHARED_SET(cref);
    if (singleton) CREF_SINGLETON_SET(cref);
    return cref;
}
static rb_cref_t *
vm_cref_new(VALUE klass, rb_method_visibility_t visi, int module_func, rb_cref_t *prev_cref, int pushed_by_eval, int singleton)
{
    return vm_cref_new0(klass, visi, module_func, prev_cref, pushed_by_eval, 0, singleton);
}
static rb_cref_t *
vm_cref_new_use_prev(VALUE klass, rb_method_visibility_t visi, int module_func, rb_cref_t *prev_cref, int pushed_by_eval)
{
    return vm_cref_new0(klass, visi, module_func, prev_cref, pushed_by_eval, 1, 0);
}
static int
ref_delete_symkey(VALUE key, VALUE value, VALUE unused)
{
    return RB_SYMBOL_P(key) ? ST_DELETE : ST_CONTINUE;
}
static rb_cref_t *
vm_cref_dup(const rb_cref_t *cref)
{
    const rb_scope_visibility_t *visi = CREF_SCOPE_VISI(cref);
    rb_cref_t *next_cref = CREF_NEXT(cref), *new_cref;
    int pushed_by_eval = CREF_PUSHED_BY_EVAL(cref);
    int singleton = CREF_SINGLETON(cref);
    new_cref = vm_cref_new(cref->klass_or_self, visi->method_visi, visi->module_func, next_cref, pushed_by_eval, singleton);
    if (!RB_NIL_P(CREF_REFINEMENTS(cref))) {
        VALUE ref = rb_hash_dup(CREF_REFINEMENTS(cref));
        rb_hash_foreach(ref, ref_delete_symkey, ((VALUE)RUBY_Qnil));
        CREF_REFINEMENTS_SET(new_cref, ref);
        CREF_OMOD_SHARED_UNSET(new_cref);
    }
    return new_cref;
}static inline 
rb_cref_t *
rb_vm_cref_dup_without_refinements(const rb_cref_t *cref)
{
    const rb_scope_visibility_t *visi = CREF_SCOPE_VISI(cref);
    rb_cref_t *next_cref = CREF_NEXT(cref), *new_cref;
    int pushed_by_eval = CREF_PUSHED_BY_EVAL(cref);
    int singleton = CREF_SINGLETON(cref);
    new_cref = vm_cref_new(cref->klass_or_self, visi->method_visi, visi->module_func, next_cref, pushed_by_eval, singleton);
    if (!RB_NIL_P(CREF_REFINEMENTS(cref))) {
        CREF_REFINEMENTS_SET(new_cref, ((VALUE)RUBY_Qnil));
        CREF_OMOD_SHARED_UNSET(new_cref);
    }
    return new_cref;
}
static rb_cref_t *
vm_cref_new_toplevel(rb_execution_context_t *ec)
{
    rb_cref_t *cref = vm_cref_new(rb_cObject, METHOD_VISI_PRIVATE , 0, ((void *)0), 0, 0);
    VALUE top_wrapper = rb_ec_thread_ptr(ec)->top_wrapper;
    if (top_wrapper) {
 cref = vm_cref_new(top_wrapper, METHOD_VISI_PRIVATE, 0, cref, 0, 0);
    }
    return cref;
}static inline 
rb_cref_t *
rb_vm_cref_new_toplevel(void)
{
    return vm_cref_new_toplevel(rb_current_execution_context(1));
}
static void
vm_cref_dump(const char *mesg, const rb_cref_t *cref)
{
    ruby_debug_printf("vm_cref_dump: %s (%p)\n", mesg, (void *)cref);
    while (cref) {
 ruby_debug_printf("= cref| klass: %s\n", RSTRING_PTR(rb_class_path(CREF_CLASS(cref))));
 cref = CREF_NEXT(cref);
    }
}static inline 
void
rb_vm_block_ep_update(VALUE obj, const struct rb_block *dst, const VALUE *ep)
{
    *((const VALUE **)&dst->as.captured.ep) = ep;
    (rb_obj_written((VALUE)(obj), (VALUE)(((VALUE)RUBY_Qundef)), (VALUE)(VM_ENV_ENVVAL(ep)), "./vm.c", 353));
}
static void
vm_bind_update_env(VALUE bindval, rb_binding_t *bind, VALUE envval)
{
    const rb_env_t *env = (rb_env_t *)envval;
    rb_obj_write((VALUE)(bindval), __extension__({
   ;
   ; __typeof__((VALUE *)(&bind->block.as.captured.code.iseq)) unaligned_member_access_result = ((VALUE *)(&bind->block.as.captured.code.iseq));
   ; unaligned_member_access_result; }), (VALUE)(env->iseq), "./vm.c", 360);
    rb_vm_block_ep_update(bindval, &bind->block, env->ep);
}
static VALUE vm_make_env_object(const rb_execution_context_t *ec, rb_control_frame_t *cfp);
extern VALUE rb_vm_invoke_bmethod(rb_execution_context_t *ec, rb_proc_t *proc, VALUE self,
                                  int argc, const VALUE *argv, int kw_splat, VALUE block_handler,
                                  const rb_callable_method_entry_t *me);
static VALUE vm_invoke_proc(rb_execution_context_t *ec, rb_proc_t *proc, VALUE self, int argc, const VALUE *argv, int kw_splat, VALUE block_handler);
typedef enum {
    CONST_DEPRECATED = 0x100,
    CONST_VISIBILITY_MASK = 0xff,
    CONST_PUBLIC = 0x00,
    CONST_PRIVATE,
    CONST_VISIBILITY_MAX
} rb_const_flag_t;
typedef struct rb_const_entry_struct {
    rb_const_flag_t flag;
    int line;
    VALUE value;
    VALUE file;
} rb_const_entry_t;
VALUE rb_mod_private_constant(int argc, const VALUE *argv, VALUE obj);
VALUE rb_mod_public_constant(int argc, const VALUE *argv, VALUE obj);
VALUE rb_mod_deprecate_constant(int argc, const VALUE *argv, VALUE obj);
void rb_free_const_table(struct rb_id_table *tbl);
VALUE rb_const_source_location(VALUE, ID);


int rb_autoloading_value(VALUE mod, ID id, VALUE *value, rb_const_flag_t *flag);
rb_const_entry_t *rb_const_lookup(VALUE klass, ID id);
VALUE rb_public_const_get_at(VALUE klass, ID id);
VALUE rb_public_const_get_from(VALUE klass, ID id);
int rb_public_const_defined_from(VALUE klass, ID id);
VALUE rb_const_source_location_at(VALUE, ID);


enum {
    cmp_opt_Integer,
    cmp_opt_String,
    cmp_opt_Float,
    cmp_optimizable_count
};
struct cmp_opt_data {
    unsigned int opt_methods;
    unsigned int opt_inited;
};
VALUE rb_invcmp(VALUE, VALUE);
struct ar_table_struct;
typedef unsigned char ar_hint_t;
enum ruby_rhash_flags {
    RHASH_PASS_AS_KEYWORDS = ((VALUE)RUBY_FL_USER1),
    RHASH_PROC_DEFAULT = ((VALUE)RUBY_FL_USER2),
    RHASH_ST_TABLE_FLAG = ((VALUE)RUBY_FL_USER3),
    RHASH_AR_TABLE_SIZE_MASK = (((VALUE)RUBY_FL_USER4)|((VALUE)RUBY_FL_USER5)|((VALUE)RUBY_FL_USER6)|((VALUE)RUBY_FL_USER7)),
    RHASH_AR_TABLE_SIZE_SHIFT = (((VALUE)RUBY_FL_USHIFT)+4),
    RHASH_AR_TABLE_BOUND_MASK = (((VALUE)RUBY_FL_USER8)|((VALUE)RUBY_FL_USER9)|((VALUE)RUBY_FL_USER10)|((VALUE)RUBY_FL_USER11)),
    RHASH_AR_TABLE_BOUND_SHIFT = (((VALUE)RUBY_FL_USHIFT)+8),
    RHASH_TRANSIENT_FLAG = ((VALUE)RUBY_FL_USER12),
    RHASH_LEV_SHIFT = (((VALUE)RUBY_FL_USHIFT) + 13),
    RHASH_LEV_MAX = 127,
};
struct RHash {
    struct RBasic basic;
    union {
        st_table *st;
        struct ar_table_struct *ar;
    } as;
    const VALUE ifnone;
    union {
        ar_hint_t ary[8];
        VALUE word;
    } ar_hint;
};
void rb_hash_st_table_set(VALUE hash, st_table *st);
VALUE rb_hash_default_value(VALUE hash, VALUE key);
VALUE rb_hash_set_default_proc(VALUE hash, VALUE proc);
long rb_dbl_long_hash(double d);
st_table *rb_init_identtable(void);
VALUE rb_to_hash_type(VALUE obj);
VALUE rb_hash_key_str(VALUE);
VALUE rb_hash_values(VALUE hash);
VALUE rb_hash_rehash(VALUE hash);
int rb_hash_add_new_element(VALUE hash, VALUE key, VALUE val);
VALUE rb_hash_set_pair(VALUE hash, VALUE pair);
int rb_hash_stlike_delete(VALUE hash, st_data_t *pkey, st_data_t *pval);
int rb_hash_stlike_foreach_with_replace(VALUE hash, st_foreach_check_callback_func *func, st_update_callback_func *replace, st_data_t arg);
int rb_hash_stlike_update(VALUE hash, st_data_t key, st_update_callback_func *func, st_data_t arg);
extern st_table *rb_hash_st_table(VALUE hash);
VALUE rb_ident_hash_new_with_size(st_index_t size);
static inline unsigned RHASH_AR_TABLE_SIZE_RAW(VALUE h);
static inline VALUE RHASH_IFNONE(VALUE h);
static inline size_t RHASH_SIZE(VALUE h);
static inline _Bool RHASH_EMPTY_P(VALUE h);
static inline _Bool RHASH_AR_TABLE_P(VALUE h);
static inline _Bool RHASH_ST_TABLE_P(VALUE h);
static inline struct ar_table_struct *RHASH_AR_TABLE(VALUE h);
static inline st_table *RHASH_ST_TABLE(VALUE h);
static inline size_t RHASH_ST_SIZE(VALUE h);
static inline void RHASH_ST_CLEAR(VALUE h);
static inline _Bool RHASH_TRANSIENT_P(VALUE h);
static inline void RHASH_SET_TRANSIENT_FLAG(VALUE h);
static inline void RHASH_UNSET_TRANSIENT_FLAG(VALUE h);


VALUE rb_hash_delete_entry(VALUE hash, VALUE key);
VALUE rb_ident_hash_new(void);
int rb_hash_stlike_foreach(VALUE hash, st_foreach_callback_func *func, st_data_t arg);




VALUE rb_hash_new_with_size(st_index_t size);
VALUE rb_hash_resurrect(VALUE hash);
int rb_hash_stlike_lookup(VALUE hash, st_data_t key, st_data_t *pval);
VALUE rb_hash_keys(VALUE hash);
VALUE rb_hash_has_key(VALUE hash, VALUE key);
VALUE rb_hash_compare_by_id_p(VALUE hash);
st_table *rb_hash_tbl_raw(VALUE hash, const char *file, int line);


VALUE rb_hash_compare_by_id(VALUE hash);
static inline _Bool
RHASH_AR_TABLE_P(VALUE h)
{
    return ! RB_FL_TEST_RAW(h, RHASH_ST_TABLE_FLAG);
}
static inline struct ar_table_struct *
RHASH_AR_TABLE(VALUE h)
{
    return ((struct RHash *)(h))->as.ar;
}
static inline st_table *
RHASH_ST_TABLE(VALUE h)
{
    return ((struct RHash *)(h))->as.st;
}
static inline VALUE
RHASH_IFNONE(VALUE h)
{
    return ((struct RHash *)(h))->ifnone;
}
static inline size_t
RHASH_SIZE(VALUE h)
{
    if (RHASH_AR_TABLE_P(h)) {
        return RHASH_AR_TABLE_SIZE_RAW(h);
    }
    else {
        return RHASH_ST_SIZE(h);
    }
}
static inline _Bool
RHASH_EMPTY_P(VALUE h)
{
    return RHASH_SIZE(h) == 0;
}
static inline _Bool
RHASH_ST_TABLE_P(VALUE h)
{
    return ! RHASH_AR_TABLE_P(h);
}
static inline size_t
RHASH_ST_SIZE(VALUE h)
{
    return RHASH_ST_TABLE(h)->num_entries;
}
static inline void
RHASH_ST_CLEAR(VALUE h)
{
    RB_FL_UNSET_RAW(h, RHASH_ST_TABLE_FLAG);
    ((struct RHash *)(h))->as.ar = ((void *)0);
}
static inline unsigned
RHASH_AR_TABLE_SIZE_RAW(VALUE h)
{
    VALUE ret = RB_FL_TEST_RAW(h, RHASH_AR_TABLE_SIZE_MASK);
    ret >>= RHASH_AR_TABLE_SIZE_SHIFT;
    return (unsigned)ret;
}
static inline _Bool
RHASH_TRANSIENT_P(VALUE h)
{
    return RB_FL_TEST_RAW(h, RHASH_TRANSIENT_FLAG);
}
static inline void
RHASH_SET_TRANSIENT_FLAG(VALUE h)
{
    RB_FL_SET_RAW(h, RHASH_TRANSIENT_FLAG);
}
static inline void
RHASH_UNSET_TRANSIENT_FLAG(VALUE h)
{
    RB_FL_UNSET_RAW(h, RHASH_TRANSIENT_FLAG);
}
enum rb_int_parse_flags {
    RB_INT_PARSE_SIGN = 0x01,
    RB_INT_PARSE_UNDERSCORE = 0x02,
    RB_INT_PARSE_PREFIX = 0x04,
    RB_INT_PARSE_ALL = 0x07,
    RB_INT_PARSE_DEFAULT = 0x07,
};
struct RBignum {
    struct RBasic basic;
    union {
        struct {
            size_t len;
            unsigned int *digits;
        } heap;
        unsigned int ary[(8*3/4)];
    } as;
};
extern const char ruby_digitmap[];
double rb_big_fdiv_double(VALUE x, VALUE y);
VALUE rb_big_uminus(VALUE x);
VALUE rb_big_hash(VALUE);
VALUE rb_big_odd_p(VALUE);
VALUE rb_big_even_p(VALUE);
size_t rb_big_size(VALUE);
VALUE rb_integer_float_cmp(VALUE x, VALUE y);
VALUE rb_integer_float_eq(VALUE x, VALUE y);
VALUE rb_str_convert_to_inum(VALUE str, int base, int badcheck, int raise_exception);
VALUE rb_big_comp(VALUE x);
VALUE rb_big_aref(VALUE x, VALUE y);
VALUE rb_big_abs(VALUE x);
VALUE rb_big_size_m(VALUE big);
VALUE rb_big_bit_length(VALUE big);
VALUE rb_big_remainder(VALUE x, VALUE y);
VALUE rb_big_gt(VALUE x, VALUE y);
VALUE rb_big_ge(VALUE x, VALUE y);
VALUE rb_big_lt(VALUE x, VALUE y);
VALUE rb_big_le(VALUE x, VALUE y);
VALUE rb_int_powm(int const argc, VALUE * const argv, VALUE const num);
VALUE rb_big_isqrt(VALUE n);
static inline _Bool BIGNUM_SIGN(VALUE b);
static inline _Bool BIGNUM_POSITIVE_P(VALUE b);
static inline _Bool BIGNUM_NEGATIVE_P(VALUE b);
static inline void BIGNUM_SET_SIGN(VALUE b, _Bool sign);
static inline void BIGNUM_NEGATE(VALUE b);
static inline size_t BIGNUM_LEN(VALUE b);
static inline unsigned int *BIGNUM_DIGITS(VALUE b);
static inline int BIGNUM_LENINT(VALUE b);
static inline _Bool BIGNUM_EMBED_P(VALUE b);


VALUE rb_big_mul_normal(VALUE x, VALUE y);
VALUE rb_big_mul_balance(VALUE x, VALUE y);
VALUE rb_big_mul_karatsuba(VALUE x, VALUE y);
VALUE rb_big_mul_toom3(VALUE x, VALUE y);
VALUE rb_big_sq_fast(VALUE x);
VALUE rb_big_divrem_normal(VALUE x, VALUE y);
VALUE rb_big2str_poweroftwo(VALUE x, int base);
VALUE rb_big2str_generic(VALUE x, int base);
VALUE rb_str2big_poweroftwo(VALUE arg, int base, int badcheck);
VALUE rb_str2big_normal(VALUE arg, int base, int badcheck);
VALUE rb_str2big_karatsuba(VALUE arg, int base, int badcheck);
VALUE rb_int_parse_cstr(const char *str, ssize_t len, char **endp, size_t *ndigits, int base, int flags);




VALUE rb_int128t2big(__int128 n);


static inline _Bool
BIGNUM_SIGN(VALUE b)
{
    return RB_FL_TEST_RAW(b, ((VALUE)RUBY_FL_USER1));
}
static inline _Bool
BIGNUM_POSITIVE_P(VALUE b)
{
    return BIGNUM_SIGN(b);
}
static inline _Bool
BIGNUM_NEGATIVE_P(VALUE b)
{
    return ! BIGNUM_POSITIVE_P(b);
}
static inline void
BIGNUM_SET_SIGN(VALUE b, _Bool sign)
{
    if (sign) {
        RB_FL_SET_RAW(b, ((VALUE)RUBY_FL_USER1));
    }
    else {
        RB_FL_UNSET_RAW(b, ((VALUE)RUBY_FL_USER1));
    }
}
static inline void
BIGNUM_NEGATE(VALUE b)
{
    RB_FL_REVERSE_RAW(b, ((VALUE)RUBY_FL_USER1));
}
static inline size_t
BIGNUM_LEN(VALUE b)
{
    if (! BIGNUM_EMBED_P(b)) {
        return ((struct RBignum *)(b))->as.heap.len;
    }
    else {
        size_t ret = ((struct RBasic *)(b))->flags;
        ret &= (~(~(VALUE)0U << 3) << (((VALUE)RUBY_FL_USHIFT)+3));
        ret >>= (((VALUE)RUBY_FL_USHIFT)+3);
        return ret;
    }
}
static inline int
BIGNUM_LENINT(VALUE b)
{
    return rb_long2int_inline(BIGNUM_LEN(b));
}
static inline unsigned int *
BIGNUM_DIGITS(VALUE b)
{
    if (BIGNUM_EMBED_P(b)) {
        return ((struct RBignum *)(b))->as.ary;
    }
    else {
        return ((struct RBignum *)(b))->as.heap.digits;
    }
}
static inline _Bool
BIGNUM_EMBED_P(VALUE b)
{
    return RB_FL_TEST_RAW(b, ((VALUE)((VALUE)RUBY_FL_USER2)));
}
static inline uint16_t ruby_swap16(uint16_t);
static inline uint32_t ruby_swap32(uint32_t);
static inline uint64_t ruby_swap64(uint64_t);
static inline unsigned nlz_int(unsigned x);
static inline unsigned nlz_long(unsigned long x);
static inline unsigned nlz_long_long(unsigned long long x);
static inline unsigned nlz_intptr(uintptr_t x);
static inline unsigned nlz_int32(uint32_t x);
static inline unsigned nlz_int64(uint64_t x);
static inline unsigned nlz_int128(unsigned __int128 x);
static inline unsigned rb_popcount32(uint32_t x);
static inline unsigned rb_popcount64(uint64_t x);
static inline unsigned rb_popcount_intptr(uintptr_t x);
static inline int ntz_int32(uint32_t x);
static inline int ntz_int64(uint64_t x);
static inline int ntz_intptr(uintptr_t x);
static inline VALUE RUBY_BIT_ROTL(VALUE, int);
static inline VALUE RUBY_BIT_ROTR(VALUE, int);
static inline uint16_t
ruby_swap16(uint16_t x)
{
    return __builtin_bswap16(x);
}
static inline uint32_t
ruby_swap32(uint32_t x)
{
    return __builtin_bswap32(x);
}
static inline uint64_t
ruby_swap64(uint64_t x)
{
    return __builtin_bswap64(x);
}
static inline unsigned int
nlz_int32(uint32_t x)
{
    __extension__ _Static_assert(sizeof(int) * 8 == 32, "sizeof_int" ": " "sizeof(int) * CHAR_BIT == 32");
    return x ? (unsigned int)__builtin_clz(x) : 32;
}
static inline unsigned int
nlz_int64(uint64_t x)
{
    if (x == 0) {
        return 64;
    }
    else if (sizeof(long) * 8 == 64) {
        return (unsigned int)__builtin_clzl((unsigned long)x);
    }
    else if (sizeof(long long) * 8 == 64) {
        return (unsigned int)__builtin_clzll((unsigned long long)x);
    }
    else {
        __builtin_unreachable();
    }
}
static inline unsigned int
nlz_int128(unsigned __int128 x)
{
    uint64_t y = (uint64_t)(x >> 64);
    if (x == 0) {
        return 128;
    }
    else if (y == 0) {
        return (unsigned int)nlz_int64(x) + 64;
    }
    else {
        return (unsigned int)nlz_int64(y);
    }
}
static inline unsigned int
nlz_int(unsigned int x)
{
    if (sizeof(unsigned int) * 8 == 32) {
        return nlz_int32((uint32_t)x);
    }
    else if (sizeof(unsigned int) * 8 == 64) {
        return nlz_int64((uint64_t)x);
    }
    else {
        __builtin_unreachable();
    }
}
static inline unsigned int
nlz_long(unsigned long x)
{
    if (sizeof(unsigned long) * 8 == 32) {
        return nlz_int32((uint32_t)x);
    }
    else if (sizeof(unsigned long) * 8 == 64) {
        return nlz_int64((uint64_t)x);
    }
    else {
        __builtin_unreachable();
    }
}
static inline unsigned int
nlz_long_long(unsigned long long x)
{
    if (sizeof(unsigned long long) * 8 == 64) {
        return nlz_int64((uint64_t)x);
    }
    else if (sizeof(unsigned long long) * 8 == 128) {
        return nlz_int128((unsigned __int128)x);
    }
    else {
        __builtin_unreachable();
    }
}
static inline unsigned int
nlz_intptr(uintptr_t x)
{
    if (sizeof(uintptr_t) == sizeof(unsigned int)) {
        return nlz_int((unsigned int)x);
    }
    if (sizeof(uintptr_t) == sizeof(unsigned long)) {
        return nlz_long((unsigned long)x);
    }
    if (sizeof(uintptr_t) == sizeof(unsigned long long)) {
        return nlz_long_long((unsigned long long)x);
    }
    else {
        __builtin_unreachable();
    }
}
static inline unsigned int
rb_popcount32(uint32_t x)
{
    __extension__ _Static_assert(sizeof(int) * 8 >= 32, "sizeof_int" ": " "sizeof(int) * CHAR_BIT >= 32");
    return (unsigned int)__builtin_popcount(x);
}
static inline unsigned int
rb_popcount64(uint64_t x)
{
    if (sizeof(long) * 8 == 64) {
        return (unsigned int)__builtin_popcountl((unsigned long)x);
    }
    else if (sizeof(long long) * 8 == 64) {
        return (unsigned int)__builtin_popcountll((unsigned long long)x);
    }
    else {
        __builtin_unreachable();
    }
}
static inline unsigned int
rb_popcount_intptr(uintptr_t x)
{
    if (sizeof(uintptr_t) * 8 == 64) {
        return rb_popcount64((uint64_t)x);
    }
    else if (sizeof(uintptr_t) * 8 == 32) {
        return rb_popcount32((uint32_t)x);
    }
    else {
        __builtin_unreachable();
    }
}
static inline int
ntz_int32(uint32_t x)
{
    __extension__ _Static_assert(sizeof(int) * 8 == 32, "sizeof_int" ": " "sizeof(int) * CHAR_BIT == 32");
    return x ? (unsigned)__builtin_ctz(x) : 32;
}
static inline int
ntz_int64(uint64_t x)
{
    if (x == 0) {
        return 64;
    }
    else if (sizeof(long) * 8 == 64) {
        return (unsigned)__builtin_ctzl((unsigned long)x);
    }
    else if (sizeof(long long) * 8 == 64) {
        return (unsigned)__builtin_ctzll((unsigned long long)x);
    }
    else {
        __builtin_unreachable();
    }
}
static inline int
ntz_intptr(uintptr_t x)
{
    if (sizeof(uintptr_t) * 8 == 64) {
        return ntz_int64((uint64_t)x);
    }
    else if (sizeof(uintptr_t) * 8 == 32) {
        return ntz_int32((uint32_t)x);
    }
    else {
        __builtin_unreachable();
    }
}
static inline VALUE
RUBY_BIT_ROTL(VALUE v, int n)
{
    const int m = (sizeof(VALUE) * 8) - 1;
    return (v << (n & m)) | (v >> (-n & m));
}
static inline VALUE
RUBY_BIT_ROTR(VALUE v, int n)
{
    const int m = (sizeof(VALUE) * 8) - 1;
    return (v << (-n & m)) | (v >> (n & m));
}
VALUE rb_int128t2big(__int128 n);
static inline long rb_overflowed_fix_to_int(long x);
static inline VALUE rb_fix_plus_fix(VALUE x, VALUE y);
static inline VALUE rb_fix_minus_fix(VALUE x, VALUE y);
static inline VALUE rb_fix_mul_fix(VALUE x, VALUE y);
static inline void rb_fix_divmod_fix(VALUE x, VALUE y, VALUE *divp, VALUE *modp);
static inline VALUE rb_fix_div_fix(VALUE x, VALUE y);
static inline VALUE rb_fix_mod_fix(VALUE x, VALUE y);
static inline _Bool FIXNUM_POSITIVE_P(VALUE num);
static inline _Bool FIXNUM_NEGATIVE_P(VALUE num);
static inline _Bool FIXNUM_ZERO_P(VALUE num);
static inline long
rb_overflowed_fix_to_int(long x)
{
    return (long)((unsigned long)(x >> 1) ^ (1LU << (8 * 8 - 1)));
}
static inline VALUE
rb_fix_plus_fix(VALUE x, VALUE y)
{
    long lz;
    if (__builtin_add_overflow((long)x, (long)y-1, &lz)) {
        return rb_int2big(rb_overflowed_fix_to_int(lz));
    }
    else {
        return (VALUE)lz;
    }
}
static inline VALUE
rb_fix_minus_fix(VALUE x, VALUE y)
{
    long lz;
    if (__builtin_sub_overflow((long)x, (long)y-1, &lz)) {
        return rb_int2big(rb_overflowed_fix_to_int(lz));
    }
    else {
        return (VALUE)lz;
    }
}
static inline VALUE
rb_fix_mul_fix(VALUE x, VALUE y)
{
    long lx = rb_fix2long(x);
    long ly = rb_fix2long(y);
    return (((((__int128)lx * (__int128)ly) < (0x7fffffffffffffffL / 2) + 1) && (((__int128)lx * (__int128)ly) >= ((-0x7fffffffffffffffL - 1L) / 2))) ? RB_INT2FIX((__int128)lx * (__int128)ly) : rb_int128t2big((__int128)lx * (__int128)ly));
}
static inline void
rb_fix_divmod_fix(VALUE a, VALUE b, VALUE *divp, VALUE *modp)
{
    long x = rb_fix2long(a);
    long y = rb_fix2long(b);
    long div, mod;
    if (x == ((-0x7fffffffffffffffL - 1L) / 2) && y == -1) {
        if (divp) *divp = rb_long2num_inline(-((-0x7fffffffffffffffL - 1L) / 2));
        if (modp) *modp = RB_INT2FIX(0);
        return;
    }
    div = x / y;
    mod = x % y;
    if (y > 0 ? mod < 0 : mod > 0) {
        mod += y;
        div -= 1;
    }
    if (divp) *divp = RB_INT2FIX(div);
    if (modp) *modp = RB_INT2FIX(mod);
}
static inline VALUE
rb_fix_div_fix(VALUE x, VALUE y)
{
    VALUE div;
    rb_fix_divmod_fix(x, y, &div, ((void *)0));
    return div;
}
static inline VALUE
rb_fix_mod_fix(VALUE x, VALUE y)
{
    VALUE mod;
    rb_fix_divmod_fix(x, y, ((void *)0), &mod);
    return mod;
}
static inline _Bool
FIXNUM_POSITIVE_P(VALUE num)
{
    return (long)num > (long)__builtin_choose_expr( __builtin_constant_p(0), ((VALUE)(0)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(0));
}
static inline _Bool
FIXNUM_NEGATIVE_P(VALUE num)
{
    return (long)num < 0;
}
static inline _Bool
FIXNUM_ZERO_P(VALUE num)
{
    return num == __builtin_choose_expr( __builtin_constant_p(0), ((VALUE)(0)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(0));
}
enum ruby_num_rounding_mode {
    RUBY_NUM_ROUND_HALF_UP,
    RUBY_NUM_ROUND_HALF_EVEN,
    RUBY_NUM_ROUND_HALF_DOWN,
    RUBY_NUM_ROUND_DEFAULT = RUBY_NUM_ROUND_HALF_UP,
};
typedef double rb_float_value_type;
struct RFloat {
    struct RBasic basic;
    rb_float_value_type float_value;
};
int rb_num_to_uint(VALUE val, unsigned int *ret);
VALUE ruby_num_interval_step_size(VALUE from, VALUE to, VALUE step, int excl);
double ruby_float_step_size(double beg, double end, double unit, int excl);
int ruby_float_step(VALUE from, VALUE to, VALUE step, int excl, int allow_endless);
int rb_num_negative_p(VALUE);
VALUE rb_int_succ(VALUE num);
VALUE rb_float_uminus(VALUE num);
VALUE rb_int_plus(VALUE x, VALUE y);
VALUE rb_float_plus(VALUE x, VALUE y);
VALUE rb_int_minus(VALUE x, VALUE y);
VALUE rb_float_minus(VALUE x, VALUE y);
VALUE rb_int_mul(VALUE x, VALUE y);
VALUE rb_float_mul(VALUE x, VALUE y);
VALUE rb_float_div(VALUE x, VALUE y);
VALUE rb_int_idiv(VALUE x, VALUE y);
VALUE rb_int_modulo(VALUE x, VALUE y);
VALUE rb_int2str(VALUE num, int base);
VALUE rb_fix_plus(VALUE x, VALUE y);
VALUE rb_int_gt(VALUE x, VALUE y);
VALUE rb_float_gt(VALUE x, VALUE y);
VALUE rb_int_ge(VALUE x, VALUE y);
enum ruby_num_rounding_mode rb_num_get_rounding_option(VALUE opts);
double rb_int_fdiv_double(VALUE x, VALUE y);
VALUE rb_int_pow(VALUE x, VALUE y);
VALUE rb_float_pow(VALUE x, VALUE y);
VALUE rb_int_cmp(VALUE x, VALUE y);
VALUE rb_int_equal(VALUE x, VALUE y);
VALUE rb_int_divmod(VALUE x, VALUE y);
VALUE rb_int_and(VALUE x, VALUE y);
VALUE rb_int_lshift(VALUE x, VALUE y);
VALUE rb_int_div(VALUE x, VALUE y);
int rb_int_positive_p(VALUE num);
int rb_int_negative_p(VALUE num);
VALUE rb_check_integer_type(VALUE);
VALUE rb_num_pow(VALUE x, VALUE y);
VALUE rb_float_ceil(VALUE num, int ndigits);
VALUE rb_float_floor(VALUE x, int ndigits);
VALUE rb_float_abs(VALUE flt);
static inline VALUE rb_num_compare_with_zero(VALUE num, ID mid);
static inline int rb_num_positive_int_p(VALUE num);
static inline int rb_num_negative_int_p(VALUE num);
static inline double rb_float_flonum_value(VALUE v);
static inline double rb_float_noflonum_value(VALUE v);
static inline double rb_float_value_inline(VALUE v);
static inline VALUE rb_float_new_inline(double d);
static inline _Bool INT_POSITIVE_P(VALUE num);
static inline _Bool INT_NEGATIVE_P(VALUE num);
static inline _Bool FLOAT_ZERO_P(VALUE num);






VALUE rb_flo_div_flo(VALUE x, VALUE y);
double ruby_float_mod(double x, double y);
VALUE rb_float_equal(VALUE x, VALUE y);
int rb_float_cmp(VALUE x, VALUE y);
VALUE rb_float_eql(VALUE x, VALUE y);
VALUE rb_fix_aref(VALUE fix, VALUE idx);
VALUE rb_int_zero_p(VALUE num);
VALUE rb_int_even_p(VALUE num);
VALUE rb_int_odd_p(VALUE num);
VALUE rb_int_abs(VALUE num);
VALUE rb_int_bit_length(VALUE num);
VALUE rb_int_uminus(VALUE num);
VALUE rb_int_comp(VALUE num);


static inline _Bool
INT_POSITIVE_P(VALUE num)
{
    if (RB_FIXNUM_P(num)) {
        return FIXNUM_POSITIVE_P(num);
    }
    else {
        return BIGNUM_POSITIVE_P(num);
    }
}
static inline _Bool
INT_NEGATIVE_P(VALUE num)
{
    if (RB_FIXNUM_P(num)) {
        return FIXNUM_NEGATIVE_P(num);
    }
    else {
        return BIGNUM_NEGATIVE_P(num);
    }
}
static inline _Bool
FLOAT_ZERO_P(VALUE num)
{
    return rb_float_value_inline(num) == 0.0;
}
static inline VALUE
rb_num_compare_with_zero(VALUE num, ID mid)
{
    VALUE zero = __builtin_choose_expr( __builtin_constant_p(0), ((VALUE)(0)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(0));
    VALUE r = rb_check_funcall(num, mid, 1, &zero);
    if (r == ((VALUE)RUBY_Qundef)) {
        rb_cmperr(num, zero);
    }
    return r;
}
static inline int
rb_num_positive_int_p(VALUE num)
{
    const ID mid = '>';
    if (RB_FIXNUM_P(num)) {
        if (rb_method_basic_definition_p(rb_cInteger, mid))
            return FIXNUM_POSITIVE_P(num);
    }
    else if (RB_TYPE_P(num, RUBY_T_BIGNUM)) {
        if (rb_method_basic_definition_p(rb_cInteger, mid))
            return BIGNUM_POSITIVE_P(num);
    }
    return RB_TEST(rb_num_compare_with_zero(num, mid));
}
static inline int
rb_num_negative_int_p(VALUE num)
{
    const ID mid = '<';
    if (RB_FIXNUM_P(num)) {
        if (rb_method_basic_definition_p(rb_cInteger, mid))
            return FIXNUM_NEGATIVE_P(num);
    }
    else if (RB_TYPE_P(num, RUBY_T_BIGNUM)) {
        if (rb_method_basic_definition_p(rb_cInteger, mid))
            return BIGNUM_NEGATIVE_P(num);
    }
    return RB_TEST(rb_num_compare_with_zero(num, mid));
}
static inline double
rb_float_flonum_value(VALUE v)
{
    if (v != (VALUE)0x8000000000000002) {
        union {
            double d;
            VALUE v;
        } t;
        VALUE b63 = (v >> 63);
        t.v = RUBY_BIT_ROTR((2 - b63) | (v & ~(VALUE)0x03), 3);
        return t.d;
    }
    return 0.0;
}
static inline double
rb_float_noflonum_value(VALUE v)
{
    return ((struct RFloat *)(v))->float_value;
}
static inline double
rb_float_value_inline(VALUE v)
{
    if (RB_FLONUM_P(v)) {
        return rb_float_flonum_value(v);
    }
    return rb_float_noflonum_value(v);
}
static inline VALUE
rb_float_new_inline(double d)
{
    union {
        double d;
        VALUE v;
    } t;
    int bits;
    t.d = d;
    bits = (int)((VALUE)(t.v >> 60) & 0x7);
    if (t.v != 0x3000000000000000 &&
        !((bits-3) & ~0x01)) {
        return (RUBY_BIT_ROTL(t.v, 3) & ~(VALUE)0x01) | 0x02;
    }
    else if (t.v == (VALUE)0) {
        return 0x8000000000000002;
    }
    return rb_float_new_in_heap(d);
}
int ruby_fill_random_bytes(void *, size_t, int);
void rb_gc_mark_global_tbl(void);
void rb_gc_update_global_tbl(void);
size_t rb_generic_ivar_memsize(VALUE);
VALUE rb_search_class_path(VALUE);
VALUE rb_attr_delete(VALUE, ID);
VALUE rb_ivar_lookup(VALUE obj, ID id, VALUE undef);
void rb_autoload_str(VALUE mod, ID id, VALUE file);
VALUE rb_autoload_at_p(VALUE, ID, int);
__attribute__((__noreturn__)) VALUE rb_mod_const_missing(VALUE,VALUE);
rb_gvar_getter_t *rb_gvar_getter_function_of(ID);
rb_gvar_setter_t *rb_gvar_setter_function_of(ID);
void rb_gvar_readonly_setter(VALUE v, ID id, VALUE *_);
void rb_gvar_ractor_local(const char *name);
static inline _Bool ROBJ_TRANSIENT_P(VALUE obj);
static inline void ROBJ_TRANSIENT_SET(VALUE obj);
static inline void ROBJ_TRANSIENT_UNSET(VALUE obj);
uint32_t rb_obj_ensure_iv_index_mapping(VALUE obj, ID id);


void rb_mark_generic_ivar(VALUE);
void rb_mv_generic_ivar(VALUE src, VALUE dst);
VALUE rb_const_missing(VALUE klass, VALUE name);
int rb_class_ivar_set(VALUE klass, ID vid, VALUE value);
void rb_iv_tbl_copy(VALUE dst, VALUE src);




VALUE rb_gvar_get(ID);
VALUE rb_gvar_set(ID, VALUE);
VALUE rb_gvar_defined(ID);
void rb_const_warn_if_deprecated(const rb_const_entry_t *, VALUE, ID);
void rb_init_iv_list(VALUE obj);


static inline _Bool
ROBJ_TRANSIENT_P(VALUE obj)
{
    return RB_FL_TEST_RAW(obj, ((VALUE)RUBY_FL_USER13));
}
static inline void
ROBJ_TRANSIENT_SET(VALUE obj)
{
    RB_FL_SET_RAW(obj, ((VALUE)RUBY_FL_USER13));
}
static inline void
ROBJ_TRANSIENT_UNSET(VALUE obj)
{
    RB_FL_UNSET_RAW(obj, ((VALUE)RUBY_FL_USER13));
}
enum {
    RSTRUCT_EMBED_LEN_MAX = RVALUE_EMBED_LEN_MAX,
    RSTRUCT_EMBED_LEN_MASK = (RUBY_FL_USER2|RUBY_FL_USER1),
    RSTRUCT_EMBED_LEN_SHIFT = (RUBY_FL_USHIFT+1),
    RSTRUCT_TRANSIENT_FLAG = ((VALUE)RUBY_FL_USER3),
};
struct RStruct {
    struct RBasic basic;
    union {
        struct {
            long len;
            const VALUE *ptr;
        } heap;
        const VALUE ary[RSTRUCT_EMBED_LEN_MAX];
    } as;
};
VALUE rb_struct_init_copy(VALUE copy, VALUE s);
VALUE rb_struct_lookup(VALUE s, VALUE idx);
VALUE rb_struct_s_keyword_init(VALUE klass);
static inline const VALUE *rb_struct_const_heap_ptr(VALUE st);
static inline _Bool RSTRUCT_TRANSIENT_P(VALUE st);
static inline void RSTRUCT_TRANSIENT_SET(VALUE st);
static inline void RSTRUCT_TRANSIENT_UNSET(VALUE st);
static inline long RSTRUCT_EMBED_LEN(VALUE st);
static inline long internal_RSTRUCT_LEN(VALUE st);
static inline int RSTRUCT_LENINT(VALUE st);
static inline const VALUE *RSTRUCT_CONST_PTR(VALUE st);
static inline void internal_RSTRUCT_SET(VALUE st, long k, VALUE v);
static inline VALUE internal_RSTRUCT_GET(VALUE st, long k);
static inline _Bool
RSTRUCT_TRANSIENT_P(VALUE st)
{
    return RB_FL_TEST_RAW(st, RSTRUCT_TRANSIENT_FLAG);
}
static inline void
RSTRUCT_TRANSIENT_SET(VALUE st)
{
    RB_FL_SET_RAW(st, RSTRUCT_TRANSIENT_FLAG);
}
static inline void
RSTRUCT_TRANSIENT_UNSET(VALUE st)
{
    RB_FL_UNSET_RAW(st, RSTRUCT_TRANSIENT_FLAG);
}
static inline long
RSTRUCT_EMBED_LEN(VALUE st)
{
    long ret = RB_FL_TEST_RAW(st, RSTRUCT_EMBED_LEN_MASK);
    ret >>= RSTRUCT_EMBED_LEN_SHIFT;
    return ret;
}
static inline long
internal_RSTRUCT_LEN(VALUE st)
{
    if (RB_FL_TEST_RAW(st, RSTRUCT_EMBED_LEN_MASK)) {
        return RSTRUCT_EMBED_LEN(st);
    }
    else {
        return ((struct RStruct *)(st))->as.heap.len;
    }
}
static inline int
RSTRUCT_LENINT(VALUE st)
{
    return rb_long2int_inline(internal_RSTRUCT_LEN(st));
}
static inline const VALUE *
RSTRUCT_CONST_PTR(VALUE st)
{
    const struct RStruct *p = ((struct RStruct *)(st));
    if (RB_FL_TEST_RAW(st, RSTRUCT_EMBED_LEN_MASK)) {
        return p->as.ary;
    }
    else {
        return p->as.heap.ptr;
    }
}
static inline void
internal_RSTRUCT_SET(VALUE st, long k, VALUE v)
{
    rb_obj_write((VALUE)(st), __extension__({
   ;
   ; __typeof__((VALUE *)(&RSTRUCT_CONST_PTR(st)[k])) unaligned_member_access_result = ((VALUE *)(&RSTRUCT_CONST_PTR(st)[k]));
   ; unaligned_member_access_result; }), (VALUE)(v), "./internal/struct.h", 137);
}
static inline VALUE
internal_RSTRUCT_GET(VALUE st, long k)
{
    return RSTRUCT_CONST_PTR(st)[k];
}
static inline const VALUE *
rb_struct_const_heap_ptr(VALUE st)
{
    return ((struct RStruct *)(st))->as.heap.ptr;
}
struct gen_ivtbl {
    uint32_t numiv;
    VALUE ivptr[];
};
int rb_ivar_generic_ivtbl_lookup(VALUE obj, struct gen_ivtbl **);
VALUE rb_ivar_generic_lookup_with_index(VALUE obj, ID id, uint32_t index);
enum ruby_vminsn_type {
    YARVINSN_nop,
    YARVINSN_getlocal,
    YARVINSN_setlocal,
    YARVINSN_getblockparam,
    YARVINSN_setblockparam,
    YARVINSN_getblockparamproxy,
    YARVINSN_getspecial,
    YARVINSN_setspecial,
    YARVINSN_getinstancevariable,
    YARVINSN_setinstancevariable,
    YARVINSN_getclassvariable,
    YARVINSN_setclassvariable,
    YARVINSN_getconstant,
    YARVINSN_setconstant,
    YARVINSN_getglobal,
    YARVINSN_setglobal,
    YARVINSN_putnil,
    YARVINSN_putself,
    YARVINSN_putobject,
    YARVINSN_putspecialobject,
    YARVINSN_putstring,
    YARVINSN_concatstrings,
    YARVINSN_anytostring,
    YARVINSN_toregexp,
    YARVINSN_intern,
    YARVINSN_newarray,
    YARVINSN_newarraykwsplat,
    YARVINSN_duparray,
    YARVINSN_duphash,
    YARVINSN_expandarray,
    YARVINSN_concatarray,
    YARVINSN_splatarray,
    YARVINSN_newhash,
    YARVINSN_newrange,
    YARVINSN_pop,
    YARVINSN_dup,
    YARVINSN_dupn,
    YARVINSN_swap,
    YARVINSN_topn,
    YARVINSN_setn,
    YARVINSN_adjuststack,
    YARVINSN_defined,
    YARVINSN_checkmatch,
    YARVINSN_checkkeyword,
    YARVINSN_checktype,
    YARVINSN_defineclass,
    YARVINSN_definemethod,
    YARVINSN_definesmethod,
    YARVINSN_send,
    YARVINSN_opt_send_without_block,
    YARVINSN_objtostring,
    YARVINSN_opt_str_freeze,
    YARVINSN_opt_nil_p,
    YARVINSN_opt_str_uminus,
    YARVINSN_opt_newarray_max,
    YARVINSN_opt_newarray_min,
    YARVINSN_invokesuper,
    YARVINSN_invokeblock,
    YARVINSN_leave,
    YARVINSN_throw,
    YARVINSN_jump,
    YARVINSN_branchif,
    YARVINSN_branchunless,
    YARVINSN_branchnil,
    YARVINSN_opt_getinlinecache,
    YARVINSN_opt_setinlinecache,
    YARVINSN_once,
    YARVINSN_opt_case_dispatch,
    YARVINSN_opt_plus,
    YARVINSN_opt_minus,
    YARVINSN_opt_mult,
    YARVINSN_opt_div,
    YARVINSN_opt_mod,
    YARVINSN_opt_eq,
    YARVINSN_opt_neq,
    YARVINSN_opt_lt,
    YARVINSN_opt_le,
    YARVINSN_opt_gt,
    YARVINSN_opt_ge,
    YARVINSN_opt_ltlt,
    YARVINSN_opt_and,
    YARVINSN_opt_or,
    YARVINSN_opt_aref,
    YARVINSN_opt_aset,
    YARVINSN_opt_aset_with,
    YARVINSN_opt_aref_with,
    YARVINSN_opt_length,
    YARVINSN_opt_size,
    YARVINSN_opt_empty_p,
    YARVINSN_opt_succ,
    YARVINSN_opt_not,
    YARVINSN_opt_regexpmatch2,
    YARVINSN_invokebuiltin,
    YARVINSN_opt_invokebuiltin_delegate,
    YARVINSN_opt_invokebuiltin_delegate_leave,
    YARVINSN_getlocal_WC_0,
    YARVINSN_getlocal_WC_1,
    YARVINSN_setlocal_WC_0,
    YARVINSN_setlocal_WC_1,
    YARVINSN_putobject_INT2FIX_0_,
    YARVINSN_putobject_INT2FIX_1_,
    YARVINSN_trace_nop,
    YARVINSN_trace_getlocal,
    YARVINSN_trace_setlocal,
    YARVINSN_trace_getblockparam,
    YARVINSN_trace_setblockparam,
    YARVINSN_trace_getblockparamproxy,
    YARVINSN_trace_getspecial,
    YARVINSN_trace_setspecial,
    YARVINSN_trace_getinstancevariable,
    YARVINSN_trace_setinstancevariable,
    YARVINSN_trace_getclassvariable,
    YARVINSN_trace_setclassvariable,
    YARVINSN_trace_getconstant,
    YARVINSN_trace_setconstant,
    YARVINSN_trace_getglobal,
    YARVINSN_trace_setglobal,
    YARVINSN_trace_putnil,
    YARVINSN_trace_putself,
    YARVINSN_trace_putobject,
    YARVINSN_trace_putspecialobject,
    YARVINSN_trace_putstring,
    YARVINSN_trace_concatstrings,
    YARVINSN_trace_anytostring,
    YARVINSN_trace_toregexp,
    YARVINSN_trace_intern,
    YARVINSN_trace_newarray,
    YARVINSN_trace_newarraykwsplat,
    YARVINSN_trace_duparray,
    YARVINSN_trace_duphash,
    YARVINSN_trace_expandarray,
    YARVINSN_trace_concatarray,
    YARVINSN_trace_splatarray,
    YARVINSN_trace_newhash,
    YARVINSN_trace_newrange,
    YARVINSN_trace_pop,
    YARVINSN_trace_dup,
    YARVINSN_trace_dupn,
    YARVINSN_trace_swap,
    YARVINSN_trace_topn,
    YARVINSN_trace_setn,
    YARVINSN_trace_adjuststack,
    YARVINSN_trace_defined,
    YARVINSN_trace_checkmatch,
    YARVINSN_trace_checkkeyword,
    YARVINSN_trace_checktype,
    YARVINSN_trace_defineclass,
    YARVINSN_trace_definemethod,
    YARVINSN_trace_definesmethod,
    YARVINSN_trace_send,
    YARVINSN_trace_opt_send_without_block,
    YARVINSN_trace_objtostring,
    YARVINSN_trace_opt_str_freeze,
    YARVINSN_trace_opt_nil_p,
    YARVINSN_trace_opt_str_uminus,
    YARVINSN_trace_opt_newarray_max,
    YARVINSN_trace_opt_newarray_min,
    YARVINSN_trace_invokesuper,
    YARVINSN_trace_invokeblock,
    YARVINSN_trace_leave,
    YARVINSN_trace_throw,
    YARVINSN_trace_jump,
    YARVINSN_trace_branchif,
    YARVINSN_trace_branchunless,
    YARVINSN_trace_branchnil,
    YARVINSN_trace_opt_getinlinecache,
    YARVINSN_trace_opt_setinlinecache,
    YARVINSN_trace_once,
    YARVINSN_trace_opt_case_dispatch,
    YARVINSN_trace_opt_plus,
    YARVINSN_trace_opt_minus,
    YARVINSN_trace_opt_mult,
    YARVINSN_trace_opt_div,
    YARVINSN_trace_opt_mod,
    YARVINSN_trace_opt_eq,
    YARVINSN_trace_opt_neq,
    YARVINSN_trace_opt_lt,
    YARVINSN_trace_opt_le,
    YARVINSN_trace_opt_gt,
    YARVINSN_trace_opt_ge,
    YARVINSN_trace_opt_ltlt,
    YARVINSN_trace_opt_and,
    YARVINSN_trace_opt_or,
    YARVINSN_trace_opt_aref,
    YARVINSN_trace_opt_aset,
    YARVINSN_trace_opt_aset_with,
    YARVINSN_trace_opt_aref_with,
    YARVINSN_trace_opt_length,
    YARVINSN_trace_opt_size,
    YARVINSN_trace_opt_empty_p,
    YARVINSN_trace_opt_succ,
    YARVINSN_trace_opt_not,
    YARVINSN_trace_opt_regexpmatch2,
    YARVINSN_trace_invokebuiltin,
    YARVINSN_trace_opt_invokebuiltin_delegate,
    YARVINSN_trace_opt_invokebuiltin_delegate_leave,
    YARVINSN_trace_getlocal_WC_0,
    YARVINSN_trace_getlocal_WC_1,
    YARVINSN_trace_setlocal_WC_0,
    YARVINSN_trace_setlocal_WC_1,
    YARVINSN_trace_putobject_INT2FIX_0_,
    YARVINSN_trace_putobject_INT2FIX_1_,
    VM_INSTRUCTION_SIZE
};
extern rb_method_definition_t *rb_method_definition_create(rb_method_type_t type, ID mid);
extern void rb_method_definition_set(const rb_method_entry_t *me, rb_method_definition_t *def, void *opts);
extern int rb_method_definition_eq(const rb_method_definition_t *d1, const rb_method_definition_t *d2);
extern VALUE rb_make_no_method_exception(VALUE exc, VALUE format, VALUE obj,
                                         int argc, const VALUE *argv, int priv);
static rb_control_frame_t *vm_get_ruby_level_caller_cfp(const rb_execution_context_t *ec, const rb_control_frame_t *cfp);
static VALUE
ruby_vm_special_exception_copy(VALUE exc)
{
    VALUE e = rb_obj_alloc(rb_class_real(RBASIC_CLASS(exc)));
    rb_obj_copy_ivar(e, exc);
    return e;
}
__attribute__((__noreturn__)) static void ec_stack_overflow(rb_execution_context_t *ec, int);
static void
ec_stack_overflow(rb_execution_context_t *ec, int setup)
{
    VALUE mesg = rb_ec_vm_ptr(ec)->special_exceptions[ruby_error_sysstack];
    ec->raised_flag = RAISED_STACKOVERFLOW;
    if (setup) {
 VALUE at = rb_ec_backtrace_object(ec);
 mesg = ruby_vm_special_exception_copy(mesg);
 rb_ivar_set(mesg, idBt, at);
 rb_ivar_set(mesg, idBt_locations, at);
    }
    ec->errinfo = mesg;
    rb_ec_tag_jump(ec, RUBY_TAG_RAISE);
}
__attribute__((__noreturn__)) static void vm_stackoverflow(void);
__attribute__((__noinline__)) static __attribute__((__cold__)) void vm_stackoverflow(void);
static void
vm_stackoverflow(void)
{
    ec_stack_overflow(rb_current_execution_context(1), 1);
}
__attribute__((__noreturn__)) static void rb_ec_stack_overflow(rb_execution_context_t *ec, int crit);
static void
rb_ec_stack_overflow(rb_execution_context_t *ec, int crit)
{
    if (rb_during_gc()) {
        rb_bug("system stack overflow during GC. Faulty native extension?");
    }
    if (crit) {
 ec->raised_flag = RAISED_STACKOVERFLOW;
 ec->errinfo = rb_ec_vm_ptr(ec)->special_exceptions[ruby_error_stackfatal];
 rb_ec_tag_jump(ec, RUBY_TAG_RAISE);
    }
    ec_stack_overflow(ec, 1);
}
__extension__ _Static_assert((-2) == -2, "VM_ENV_DATA_INDEX_ME_CREF" ": " "VM_ENV_DATA_INDEX_ME_CREF == -2");
__extension__ _Static_assert((-1) == -1, "VM_ENV_DATA_INDEX_SPECVAL" ": " "VM_ENV_DATA_INDEX_SPECVAL == -1");
__extension__ _Static_assert(( 0) == -0, "VM_ENV_DATA_INDEX_FLAGS" ": " "VM_ENV_DATA_INDEX_FLAGS == -0");
static void
vm_push_frame(rb_execution_context_t *ec,
       const rb_iseq_t *iseq,
       VALUE type,
       VALUE self,
       VALUE specval,
       VALUE cref_or_me,
       const VALUE *pc,
       VALUE *sp,
       int local_size,
       int stack_max)
{
    rb_control_frame_t *const cfp = ((ec->cfp)-1);
    ;
    ((void)0);
    do { __extension__ _Static_assert(sizeof(*(sp)) == sizeof(VALUE), "sizeof_sp" ": " "sizeof(*(sp)) == sizeof(VALUE)"); __extension__ _Static_assert(sizeof(*(cfp)) == sizeof(rb_control_frame_t), "sizeof_cfp" ": " "sizeof(*(cfp)) == sizeof(rb_control_frame_t)"); const struct rb_control_frame_struct *bound = (void *)&(sp)[(local_size + stack_max)]; if ((__builtin_expect(!!((cfp) <= &bound[1]), 0))) { vm_stackoverflow(); } } while (0);
    ;
    for (int i=0; i < local_size; i++) {
 *sp++ = ((VALUE)RUBY_Qnil);
    }
    *sp++ = cref_or_me;
    *sp++ = specval ;
    *sp++ = type;
    *cfp = (const struct rb_control_frame_struct) {
        .pc = pc,
        .sp = sp,
        .iseq = iseq,
        .self = self,
        .ep = sp - 1,
        .block_code = ((void *)0),
        .__bp__ = sp,
        .jit_return = ((void *)0)
    };
    ec->cfp = cfp;
    if (0 == 2) {
 rb_vmdebug_stack_dump_raw(rb_current_execution_context(1), rb_current_execution_context(1)->cfp);
    }
    ;
}
static inline int
vm_pop_frame(rb_execution_context_t *ec, rb_control_frame_t *cfp, const VALUE *ep)
{
    VALUE flags = ep[( 0)];
    if ((((0) > 0) ? (0) : 0) >= 4) rb_gc_verify_internal_consistency();
    if (0 == 2) rb_vmdebug_stack_dump_raw(rb_current_execution_context(1), rb_current_execution_context(1)->cfp);
    rb_vm_check_ints(ec);
    ec->cfp = ((cfp)+1);
    return flags & VM_FRAME_FLAG_FINISH;
}
static void
rb_vm_pop_frame(rb_execution_context_t *ec)
{
    vm_pop_frame(ec, ec->cfp, ec->cfp->ep);
}
static inline VALUE
rb_arity_error_new(int argc, int min, int max)
{
    VALUE err_mess = 0;
    if (min == max) {
 err_mess = rb_sprintf("wrong number of arguments (given %d, expected %d)", argc, min);
    }
    else if (max == (-1)) {
 err_mess = rb_sprintf("wrong number of arguments (given %d, expected %d+)", argc, min);
    }
    else {
 err_mess = rb_sprintf("wrong number of arguments (given %d, expected %d..%d)", argc, min, max);
    }
    return rb_exc_new_str(rb_eArgError, err_mess);
}
static void
rb_error_arity(int argc, int min, int max)
{
    rb_exc_raise(rb_arity_error_new(argc, min, max));
}
__attribute__((__noinline__)) static void vm_env_write_slowpath(const VALUE *ep, int index, VALUE v);
static void
vm_env_write_slowpath(const VALUE *ep, int index, VALUE v)
{
    rb_gc_writebarrier_remember(VM_ENV_ENVVAL(ep));
    VM_FORCE_WRITE(&ep[index], v);
    VM_ENV_FLAGS_UNSET(ep, VM_ENV_FLAG_WB_REQUIRED);
    ((void)0);
}
static inline void
vm_env_write(const VALUE *ep, int index, VALUE v)
{
    VALUE flags = ep[( 0)];
    if ((__builtin_expect(!!((flags & VM_ENV_FLAG_WB_REQUIRED) == 0), 1))) {
 VM_STACK_ENV_WRITE(ep, index, v);
    }
    else {
 vm_env_write_slowpath(ep, index, v);
    }
}
static VALUE
rb_vm_bh_to_procval(const rb_execution_context_t *ec, VALUE block_handler)
{
    if (block_handler == 0) {
 return ((VALUE)RUBY_Qnil);
    }
    else {
 switch (vm_block_handler_type(block_handler)) {
   case block_handler_type_iseq:
   case block_handler_type_ifunc:
     return rb_vm_make_proc(ec, VM_BH_TO_CAPT_BLOCK(block_handler), rb_cProc);
   case block_handler_type_symbol:
     return rb_sym_to_proc(VM_BH_TO_SYMBOL(block_handler));
   case block_handler_type_proc:
     return VM_BH_TO_PROC(block_handler);
   default:
     __builtin_unreachable();
 }
    }
}
static inline struct vm_svar *
lep_svar(const rb_execution_context_t *ec, const VALUE *lep)
{
    VALUE svar;
    if (lep && (ec == ((void *)0) || ec->root_lep != lep)) {
 svar = lep[(-2)];
    }
    else {
 svar = ec->root_svar;
    }
    ((void)0);
    return (struct vm_svar *)svar;
}
static inline void
lep_svar_write(const rb_execution_context_t *ec, const VALUE *lep, const struct vm_svar *svar)
{
    ((void)0);
    if (lep && (ec == ((void *)0) || ec->root_lep != lep)) {
 vm_env_write(lep, (-2), (VALUE)svar);
    }
    else {
 rb_obj_write((VALUE)(rb_ec_thread_ptr(ec)->self), __extension__({
;
; __typeof__((VALUE *)(&ec->root_svar)) unaligned_member_access_result = ((VALUE *)(&ec->root_svar));
; unaligned_member_access_result; }), (VALUE)(svar), "./vm_insnhelper.c", 544);
    }
}
static VALUE
lep_svar_get(const rb_execution_context_t *ec, const VALUE *lep, rb_num_t key)
{
    const struct vm_svar *svar = lep_svar(ec, lep);
    if ((VALUE)svar == ((VALUE)RUBY_Qfalse) || imemo_type((VALUE)svar) != imemo_svar) return ((VALUE)RUBY_Qnil);
    switch (key) {
      case VM_SVAR_LASTLINE:
 return svar->lastline;
      case VM_SVAR_BACKREF:
 return svar->backref;
      default: {
 const VALUE ary = svar->others;
 if (RB_NIL_P(ary)) {
     return ((VALUE)RUBY_Qnil);
 }
 else {
     return rb_ary_entry(ary, key - VM_SVAR_EXTRA_START);
 }
      }
    }
}
static struct vm_svar *
svar_new(VALUE obj)
{
    return (struct vm_svar *)rb_imemo_new(imemo_svar, ((VALUE)RUBY_Qnil), ((VALUE)RUBY_Qnil), ((VALUE)RUBY_Qnil), obj);
}
static void
lep_svar_set(const rb_execution_context_t *ec, const VALUE *lep, rb_num_t key, VALUE val)
{
    struct vm_svar *svar = lep_svar(ec, lep);
    if ((VALUE)svar == ((VALUE)RUBY_Qfalse) || imemo_type((VALUE)svar) != imemo_svar) {
 lep_svar_write(ec, lep, svar = svar_new((VALUE)svar));
    }
    switch (key) {
      case VM_SVAR_LASTLINE:
 rb_obj_write((VALUE)(svar), __extension__({
;
; __typeof__((VALUE *)(&svar->lastline)) unaligned_member_access_result = ((VALUE *)(&svar->lastline));
; unaligned_member_access_result; }), (VALUE)(val), "./vm_insnhelper.c", 590);
 return;
      case VM_SVAR_BACKREF:
 rb_obj_write((VALUE)(svar), __extension__({
;
; __typeof__((VALUE *)(&svar->backref)) unaligned_member_access_result = ((VALUE *)(&svar->backref));
; unaligned_member_access_result; }), (VALUE)(val), "./vm_insnhelper.c", 593);
 return;
      default: {
 VALUE ary = svar->others;
 if (RB_NIL_P(ary)) {
     rb_obj_write((VALUE)(svar), __extension__({
    ;
    ; __typeof__((VALUE *)(&svar->others)) unaligned_member_access_result = ((VALUE *)(&svar->others));
    ; unaligned_member_access_result; }), (VALUE)(ary = rb_ary_new()), "./vm_insnhelper.c", 599);
 }
 rb_ary_store(ary, key - VM_SVAR_EXTRA_START, val);
      }
    }
}
static inline VALUE
vm_getspecial(const rb_execution_context_t *ec, const VALUE *lep, rb_num_t key, rb_num_t type)
{
    VALUE val;
    if (type == 0) {
 val = lep_svar_get(ec, lep, key);
    }
    else {
 VALUE backref = lep_svar_get(ec, lep, VM_SVAR_BACKREF);
 if (type & 0x01) {
     switch (type >> 1) {
       case '&':
  val = rb_reg_last_match(backref);
  break;
       case '`':
  val = rb_reg_match_pre(backref);
  break;
       case '\'':
  val = rb_reg_match_post(backref);
  break;
       case '+':
  val = rb_reg_match_last(backref);
  break;
       default:
  rb_bug("unexpected back-ref");
     }
 }
 else {
     val = rb_reg_nth_match((int)(type >> 1), backref);
 }
    }
    return val;
}
__attribute__((__pure__)) static rb_callable_method_entry_t *check_method_entry(VALUE obj, int can_be_svar);
static rb_callable_method_entry_t *
check_method_entry(VALUE obj, int can_be_svar)
{
    if (obj == ((VALUE)RUBY_Qfalse)) return ((void *)0);
    switch (imemo_type(obj)) {
      case imemo_ment:
 return (rb_callable_method_entry_t *)obj;
      case imemo_cref:
 return ((void *)0);
      case imemo_svar:
 if (can_be_svar) {
     return check_method_entry(((struct vm_svar *)obj)->cref_or_me, 0);
 }
      default:
 return ((void *)0);
    }
}
static const rb_callable_method_entry_t *
rb_vm_frame_method_entry(const rb_control_frame_t *cfp)
{
    const VALUE *ep = cfp->ep;
    rb_callable_method_entry_t *me;
    while (!VM_ENV_LOCAL_P(ep)) {
 if ((me = check_method_entry(ep[(-2)], 0)) != ((void *)0)) return me;
 ep = VM_ENV_PREV_EP(ep);
    }
    return check_method_entry(ep[(-2)], 1);
}
static const rb_iseq_t *
method_entry_iseqptr(const rb_callable_method_entry_t *me)
{
    switch (me->def->type) {
      case VM_METHOD_TYPE_ISEQ:
        return me->def->body.iseq.iseqptr;
      default:
        return ((void *)0);
    }
}
static rb_cref_t *
method_entry_cref(const rb_callable_method_entry_t *me)
{
    switch (me->def->type) {
      case VM_METHOD_TYPE_ISEQ:
 return me->def->body.iseq.cref;
      default:
 return ((void *)0);
    }
}
__attribute__((__pure__)) static rb_cref_t *check_cref(VALUE, int);
static rb_cref_t *
check_cref(VALUE obj, int can_be_svar)
{
    if (obj == ((VALUE)RUBY_Qfalse)) return ((void *)0);
    switch (imemo_type(obj)) {
      case imemo_ment:
 return method_entry_cref((rb_callable_method_entry_t *)obj);
      case imemo_cref:
 return (rb_cref_t *)obj;
      case imemo_svar:
 if (can_be_svar) {
     return check_cref(((struct vm_svar *)obj)->cref_or_me, 0);
 }
      default:
 return ((void *)0);
    }
}
static inline rb_cref_t *
vm_env_cref(const VALUE *ep)
{
    rb_cref_t *cref;
    while (!VM_ENV_LOCAL_P(ep)) {
 if ((cref = check_cref(ep[(-2)], 0)) != ((void *)0)) return cref;
 ep = VM_ENV_PREV_EP(ep);
    }
    return check_cref(ep[(-2)], 1);
}
static int
is_cref(const VALUE v, int can_be_svar)
{
    if (RB_TYPE_P(v, RUBY_T_IMEMO)) {
 switch (imemo_type(v)) {
   case imemo_cref:
     return 1;
   case imemo_svar:
     if (can_be_svar) return is_cref(((struct vm_svar *)v)->cref_or_me, 0);
   default:
     break;
 }
    }
    return 0;
}
static int
vm_env_cref_by_cref(const VALUE *ep)
{
    while (!VM_ENV_LOCAL_P(ep)) {
 if (is_cref(ep[(-2)], 0)) return 1;
 ep = VM_ENV_PREV_EP(ep);
    }
    return is_cref(ep[(-2)], 1);
}
static rb_cref_t *
cref_replace_with_duplicated_cref_each_frame(const VALUE *vptr, int can_be_svar, VALUE parent)
{
    const VALUE v = *vptr;
    rb_cref_t *cref, *new_cref;
    if (RB_TYPE_P(v, RUBY_T_IMEMO)) {
 switch (imemo_type(v)) {
   case imemo_cref:
     cref = (rb_cref_t *)v;
     new_cref = vm_cref_dup(cref);
     if (parent) {
  rb_obj_write((VALUE)(parent), __extension__({
 ;
 ; __typeof__((VALUE *)(vptr)) unaligned_member_access_result = ((VALUE *)(vptr));
 ; unaligned_member_access_result; }), (VALUE)(new_cref), "./vm_insnhelper.c", 785);
     }
     else {
  VM_FORCE_WRITE(vptr, (VALUE)new_cref);
     }
     return (rb_cref_t *)new_cref;
   case imemo_svar:
     if (can_be_svar) {
  return cref_replace_with_duplicated_cref_each_frame(&((struct vm_svar *)v)->cref_or_me, 0, v);
     }
   case imemo_ment:
     rb_bug("cref_replace_with_duplicated_cref_each_frame: unreachable");
   default:
     break;
 }
    }
    return 0;
}
static rb_cref_t *
vm_cref_replace_with_duplicated_cref(const VALUE *ep)
{
    if (vm_env_cref_by_cref(ep)) {
 rb_cref_t *cref;
 VALUE envval;
 while (!VM_ENV_LOCAL_P(ep)) {
     envval = VM_ENV_ESCAPED_P(ep) ? VM_ENV_ENVVAL(ep) : ((VALUE)RUBY_Qfalse);
     if ((cref = cref_replace_with_duplicated_cref_each_frame(&ep[(-2)], 0, envval)) != ((void *)0)) {
  return cref;
     }
     ep = VM_ENV_PREV_EP(ep);
 }
 envval = VM_ENV_ESCAPED_P(ep) ? VM_ENV_ENVVAL(ep) : ((VALUE)RUBY_Qfalse);
 return cref_replace_with_duplicated_cref_each_frame(&ep[(-2)], 1, envval);
    }
    else {
 rb_bug("vm_cref_dup: unreachable");
    }
}
static rb_cref_t *
vm_get_cref(const VALUE *ep)
{
    rb_cref_t *cref = vm_env_cref(ep);
    if (cref != ((void *)0)) {
 return cref;
    }
    else {
        rb_bug("vm_get_cref: unreachable");
    }
}static inline 
rb_cref_t *
rb_vm_get_cref(const VALUE *ep)
{
    return vm_get_cref(ep);
}
static rb_cref_t *
vm_ec_cref(const rb_execution_context_t *ec)
{
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);
    if (cfp == ((void *)0)) {
        return ((void *)0);
    }
    return vm_get_cref(cfp->ep);
}
static const rb_cref_t *
vm_get_const_key_cref(const VALUE *ep)
{
    const rb_cref_t *cref = vm_get_cref(ep);
    const rb_cref_t *key_cref = cref;
    while (cref) {
        if (RB_FL_TEST(CREF_CLASS(cref), ((VALUE)RUBY_FL_SINGLETON)) ||
            RB_FL_TEST(CREF_CLASS(cref), ((VALUE)RUBY_FL_USER6))) {
            return key_cref;
 }
 cref = CREF_NEXT(cref);
    }
    return ((void *)0);
}static inline 
void
rb_vm_rewrite_cref(rb_cref_t *cref, VALUE old_klass, VALUE new_klass, rb_cref_t **new_cref_ptr)
{
    rb_cref_t *new_cref;
    while (cref) {
 if (CREF_CLASS(cref) == old_klass) {
     new_cref = vm_cref_new_use_prev(new_klass, METHOD_VISI_UNDEF, 0, cref, 0);
     *new_cref_ptr = new_cref;
     return;
 }
 new_cref = vm_cref_new_use_prev(CREF_CLASS(cref), METHOD_VISI_UNDEF, 0, cref, 0);
 cref = CREF_NEXT(cref);
 *new_cref_ptr = new_cref;
 new_cref_ptr = &new_cref->next;
    }
    *new_cref_ptr = ((void *)0);
}
static rb_cref_t *
vm_cref_push(const rb_execution_context_t *ec, VALUE klass, const VALUE *ep, int pushed_by_eval, int singleton)
{
    rb_cref_t *prev_cref = ((void *)0);
    if (ep) {
 prev_cref = vm_env_cref(ep);
    }
    else {
 rb_control_frame_t *cfp = vm_get_ruby_level_caller_cfp(ec, ec->cfp);
 if (cfp) {
     prev_cref = vm_env_cref(cfp->ep);
 }
    }
    return vm_cref_new(klass, METHOD_VISI_PUBLIC, 0, prev_cref, pushed_by_eval, singleton);
}
static inline VALUE
vm_get_cbase(const VALUE *ep)
{
    const rb_cref_t *cref = vm_get_cref(ep);
    return CREF_CLASS_FOR_DEFINITION(cref);
}
static inline VALUE
vm_get_const_base(const VALUE *ep)
{
    const rb_cref_t *cref = vm_get_cref(ep);
    while (cref) {
        if (!CREF_PUSHED_BY_EVAL(cref)) {
            return CREF_CLASS_FOR_DEFINITION(cref);
        }
        cref = CREF_NEXT(cref);
    }
    return ((VALUE)RUBY_Qundef);
}
static inline void
vm_check_if_namespace(VALUE klass)
{
    if (!RB_TYPE_P(klass, RUBY_T_CLASS) && !RB_TYPE_P(klass, RUBY_T_MODULE)) {
 rb_raise(rb_eTypeError, "%+""l""i" "\v"" is not a class/module", klass);
    }
}
static inline void
vm_ensure_not_refinement_module(VALUE self)
{
    if (RB_TYPE_P(self, RUBY_T_MODULE) && RB_FL_TEST(self, RMODULE_IS_REFINEMENT)) {
 rb_warn("not defined at the refinement, but at the outer class/module");
    }
}
static inline VALUE
vm_get_iclass(const rb_control_frame_t *cfp, VALUE klass)
{
    return klass;
}
static inline VALUE
vm_get_ev_const(rb_execution_context_t *ec, VALUE orig_klass, ID id, _Bool allow_nil, int is_defined)
{
    void rb_const_warn_if_deprecated(const rb_const_entry_t *ce, VALUE klass, ID id);
    VALUE val;
    if (RB_NIL_P(orig_klass) && allow_nil) {
        const rb_cref_t *root_cref = vm_get_cref(ec->cfp->ep);
 const rb_cref_t *cref;
 VALUE klass = ((VALUE)RUBY_Qnil);
 while (root_cref && CREF_PUSHED_BY_EVAL(root_cref)) {
     root_cref = CREF_NEXT(root_cref);
 }
 cref = root_cref;
 while (cref && CREF_NEXT(cref)) {
     if (CREF_PUSHED_BY_EVAL(cref)) {
  klass = ((VALUE)RUBY_Qnil);
     }
     else {
  klass = CREF_CLASS(cref);
     }
     cref = CREF_NEXT(cref);
     if (!RB_NIL_P(klass)) {
  VALUE av, am = 0;
  rb_const_entry_t *ce;
       search_continue:
  if ((ce = rb_const_lookup(klass, id))) {
      rb_const_warn_if_deprecated(ce, klass, id);
      val = ce->value;
      if (val == ((VALUE)RUBY_Qundef)) {
   if (am == klass) break;
   am = klass;
   if (is_defined) return 1;
   if (rb_autoloading_value(klass, id, &av, ((void *)0))) return av;
   rb_autoload_load(klass, id);
   goto search_continue;
      }
      else {
   if (is_defined) {
       return 1;
   }
                        else {
                            if ((__builtin_expect(!!(!rb_ractor_main_p()), 0))) {
                                if (!rb_ractor_shareable_p(val)) {
                                    rb_raise(rb_eRactorIsolationError,
                                             "can not access non-shareable objects in constant %""l""i" "\v""::%s by non-main ractor.", rb_class_path(klass), rb_id2name(id));
                                }
                            }
       return val;
   }
      }
  }
     }
 }
 if (root_cref && !RB_NIL_P(CREF_CLASS(root_cref))) {
     klass = vm_get_iclass(ec->cfp, CREF_CLASS(root_cref));
 }
 else {
     klass = rb_class_of(ec->cfp->self);
 }
 if (is_defined) {
     return rb_const_defined(klass, id);
 }
 else {
     return rb_const_get(klass, id);
 }
    }
    else {
 vm_check_if_namespace(orig_klass);
 if (is_defined) {
     return rb_public_const_defined_from(orig_klass, id);
 }
 else {
     return rb_public_const_get_from(orig_klass, id);
 }
    }
}
static inline VALUE
vm_get_cvar_base(const rb_cref_t *cref, const rb_control_frame_t *cfp, int top_level_raise)
{
    VALUE klass;
    if (!cref) {
 rb_bug("vm_get_cvar_base: no cref");
    }
    while (CREF_NEXT(cref) &&
    (RB_NIL_P(CREF_CLASS(cref)) || RB_FL_TEST(CREF_CLASS(cref), ((VALUE)RUBY_FL_SINGLETON)) ||
     CREF_PUSHED_BY_EVAL(cref) || CREF_SINGLETON(cref))) {
 cref = CREF_NEXT(cref);
    }
    if (top_level_raise && !CREF_NEXT(cref)) {
        rb_raise(rb_eRuntimeError, "class variable access from toplevel");
    }
    klass = vm_get_iclass(cfp, CREF_CLASS(cref));
    if (RB_NIL_P(klass)) {
 rb_raise(rb_eTypeError, "no class variables available");
    }
    return klass;
}
static VALUE
vm_search_const_defined_class(const VALUE cbase, ID id)
{
    if (rb_const_defined_at(cbase, id)) return cbase;
    if (cbase == rb_cObject) {
 VALUE tmp = RCLASS_SUPER(cbase);
 while (tmp) {
     if (rb_const_defined_at(tmp, id)) return tmp;
     tmp = RCLASS_SUPER(tmp);
 }
    }
    return 0;
}
static _Bool
iv_index_tbl_lookup(struct st_table *iv_index_tbl, ID id, struct rb_iv_index_tbl_entry **ent)
{
    int found;
    st_data_t ent_data;
    if (iv_index_tbl == ((void *)0)) return 0;
    { unsigned int _lev; rb_vm_lock_enter(&_lev, "./vm_insnhelper.c", 1090);;
    {
        found = rb_st_lookup(iv_index_tbl, (st_data_t)id, &ent_data);
    }
    rb_vm_lock_leave(&_lev, "./vm_insnhelper.c", 1094); };
    if (found) *ent = (struct rb_iv_index_tbl_entry *)ent_data;
    return found ? 1 : 0;
}
__attribute__ ((__always_inline__)) static void fill_ivar_cache(const rb_iseq_t *iseq, IVC ic, const struct rb_callcache *cc, int is_attr, struct rb_iv_index_tbl_entry *ent);
static inline void
fill_ivar_cache(const rb_iseq_t *iseq, IVC ic, const struct rb_callcache *cc, int is_attr, struct rb_iv_index_tbl_entry *ent)
{
    if (!is_attr) {
        ic->entry = ent;
        (rb_obj_written((VALUE)(iseq), (VALUE)(((VALUE)RUBY_Qundef)), (VALUE)(ent->class_value), "./vm_insnhelper.c", 1108));
    }
    else {
        vm_cc_attr_index_set(cc, (int)ent->index + 1);
    }
}
__attribute__ ((__always_inline__)) static VALUE vm_getivar(VALUE, ID, const rb_iseq_t *, IVC, const struct rb_callcache *, int);
static inline VALUE
vm_getivar(VALUE obj, ID id, const rb_iseq_t *iseq, IVC ic, const struct rb_callcache *cc, int is_attr)
{
    VALUE val = ((VALUE)RUBY_Qundef);
    if (RB_SPECIAL_CONST_P(obj)) {
    }
    else if ((__builtin_expect(!!(is_attr ? (!!(vm_cc_attr_index(cc) > 0)) : (!!(ic->entry && ic->entry->class_serial == (((struct RClass *)(((struct RBasic *)(obj))->klass))->class_serial)))), 1))) {
        uint32_t index = !is_attr ? ic->entry->index : (vm_cc_attr_index(cc) - 1);
        ((void)0);
        if ((__builtin_expect(!!(RB_BUILTIN_TYPE(obj) == RUBY_T_OBJECT), 1)) &&
            (__builtin_expect(!!(index < ROBJECT_NUMIV(obj)), 1))) {
            val = ROBJECT_IVPTR(obj)[index];
            ((void)0);
        }
        else if (RB_FL_TEST_RAW(obj, ((VALUE)RUBY_FL_EXIVAR))) {
            val = rb_ivar_generic_lookup_with_index(obj, id, index);
        }
        goto ret;
    }
    else {
        struct rb_iv_index_tbl_entry *ent;
        if (RB_BUILTIN_TYPE(obj) == RUBY_T_OBJECT) {
            struct st_table *iv_index_tbl = ROBJECT_IV_INDEX_TBL_inline(obj);
            if (iv_index_tbl && iv_index_tbl_lookup(iv_index_tbl, id, &ent)) {
                fill_ivar_cache(iseq, ic, cc, is_attr, ent);
                if (ent->index < ROBJECT_NUMIV(obj)) {
                    val = ROBJECT_IVPTR(obj)[ent->index];
                    ((void)0);
                }
            }
        }
        else if (RB_FL_TEST_RAW(obj, ((VALUE)RUBY_FL_EXIVAR))) {
            struct st_table *iv_index_tbl = ((((struct RClass *)(rb_obj_class(obj)))->ptr)->iv_index_tbl);
            if (iv_index_tbl && iv_index_tbl_lookup(iv_index_tbl, id, &ent)) {
                fill_ivar_cache(iseq, ic, cc, is_attr, ent);
                val = rb_ivar_generic_lookup_with_index(obj, id, ent->index);
            }
        }
        else {
            goto general_path;
        }
      ret:
        if ((__builtin_expect(!!(val != ((VALUE)RUBY_Qundef)), 1))) {
            return val;
        }
        else {
            return ((VALUE)RUBY_Qnil);
        }
    }
  general_path:
    ((void)0);
    if (is_attr) {
        return rb_attr_get(obj, id);
    }
    else {
        return rb_ivar_get(obj, id);
    }
}
__attribute__ ((__always_inline__)) static VALUE vm_setivar_slowpath(VALUE obj, ID id, VALUE val, const rb_iseq_t *iseq, IVC ic, const struct rb_callcache *cc, int is_attr);
__attribute__((__noinline__)) static VALUE vm_setivar_slowpath_ivar(VALUE obj, ID id, VALUE val, const rb_iseq_t *iseq, IVC ic);
__attribute__((__noinline__)) static VALUE vm_setivar_slowpath_attr(VALUE obj, ID id, VALUE val, const struct rb_callcache *cc);
static VALUE
vm_setivar_slowpath(VALUE obj, ID id, VALUE val, const rb_iseq_t *iseq, IVC ic, const struct rb_callcache *cc, int is_attr)
{
    do { VALUE frozen_obj = (obj); if ((__builtin_expect(!!(RB_OBJ_FROZEN(frozen_obj)), 0))) { rb_error_frozen_object(frozen_obj); } } while (0);
    if (RB_TYPE_P(obj, RUBY_T_OBJECT)) {
        struct st_table *iv_index_tbl = ROBJECT_IV_INDEX_TBL_inline(obj);
        struct rb_iv_index_tbl_entry *ent;
        if (iv_index_tbl_lookup(iv_index_tbl, id, &ent)) {
            if (!is_attr) {
                ic->entry = ent;
                (rb_obj_written((VALUE)(iseq), (VALUE)(((VALUE)RUBY_Qundef)), (VALUE)(ent->class_value), "./vm_insnhelper.c", 1212));
            }
            else if (ent->index >= 0x7fffffff) {
                rb_raise(rb_eArgError, "too many instance variables");
            }
            else {
                vm_cc_attr_index_set(cc, (int)(ent->index + 1));
            }
            uint32_t index = ent->index;
            if ((__builtin_expect(!!(index >= ROBJECT_NUMIV(obj)), 0))) {
                rb_init_iv_list(obj);
            }
            VALUE *ptr = ROBJECT_IVPTR(obj);
            rb_obj_write((VALUE)(obj), __extension__({
           ;
           ; __typeof__((VALUE *)(&ptr[index])) unaligned_member_access_result = ((VALUE *)(&ptr[index]));
           ; unaligned_member_access_result; }), (VALUE)(val), "./vm_insnhelper.c", 1227);
            ((void)0);
            return val;
        }
    }
    ((void)0);
    return rb_ivar_set(obj, id, val);
}
static VALUE
vm_setivar_slowpath_ivar(VALUE obj, ID id, VALUE val, const rb_iseq_t *iseq, IVC ic)
{
    return vm_setivar_slowpath(obj, id, val, iseq, ic, ((void *)0), 0);
}
static VALUE
vm_setivar_slowpath_attr(VALUE obj, ID id, VALUE val, const struct rb_callcache *cc)
{
    return vm_setivar_slowpath(obj, id, val, ((void *)0), ((void *)0), cc, 1);
}
static inline VALUE
vm_setivar(VALUE obj, ID id, VALUE val, const rb_iseq_t *iseq, IVC ic, const struct rb_callcache *cc, int is_attr)
{
    if ((__builtin_expect(!!(RB_TYPE_P(obj, RUBY_T_OBJECT)), 1)) &&
        (__builtin_expect(!!(!RB_OBJ_FROZEN_RAW(obj)), 1))) {
        ((void)0);
 if ((__builtin_expect(!!((!is_attr && (!!(ic->entry && ic->entry->class_serial == (((struct RClass *)(((struct RBasic *)(obj))->klass))->class_serial)))) || ( is_attr && (!!(vm_cc_attr_index(cc) > 0)))), 1))) {
            uint32_t index = !is_attr ? ic->entry->index : vm_cc_attr_index(cc)-1;
            if ((__builtin_expect(!!(index >= ROBJECT_NUMIV(obj)), 0))) {
                rb_init_iv_list(obj);
            }
            VALUE *ptr = ROBJECT_IVPTR(obj);
            rb_obj_write((VALUE)(obj), __extension__({
           ;
           ; __typeof__((VALUE *)(&ptr[index])) unaligned_member_access_result = ((VALUE *)(&ptr[index]));
           ; unaligned_member_access_result; }), (VALUE)(val), "./vm_insnhelper.c", 1268);
            ((void)0);
            return val;
 }
    }
    else {
 ((void)0);
    }
    if (is_attr) {
        return vm_setivar_slowpath_attr(obj, id, val, cc);
    }
    else {
        return vm_setivar_slowpath_ivar(obj, id, val, iseq, ic);
    }
}
static VALUE
update_classvariable_cache(const rb_iseq_t *iseq, VALUE klass, ID id, ICVARC ic)
{
    VALUE defined_class = 0;
    VALUE cvar_value = rb_cvar_find(klass, id, &defined_class);
    if (RB_TYPE_P(defined_class, RUBY_T_ICLASS)) {
        defined_class = ((struct RBasic *)(defined_class))->klass;
    }
    struct rb_id_table *rb_cvc_tbl = ((((struct RClass *)(defined_class))->ptr)->cvc_tbl);
    if (!rb_cvc_tbl) {
        rb_bug("the cvc table should be set");
    }
    VALUE ent_data;
    if (!rb_id_table_lookup(rb_cvc_tbl, id, &ent_data)) {
        rb_bug("should have cvar cache entry");
    }
    struct rb_cvar_class_tbl_entry *ent = (void *)ent_data;
    ent->global_cvar_state = (ruby_vm_global_cvar_state);
    ic->entry = ent;
    (rb_obj_written((VALUE)(iseq), (VALUE)(((VALUE)RUBY_Qundef)), (VALUE)(ent->class_value), "./vm_insnhelper.c", 1309));
    return cvar_value;
}
static inline VALUE
vm_getclassvariable(const rb_iseq_t *iseq, const rb_control_frame_t *reg_cfp, ID id, ICVARC ic)
{
    const rb_cref_t *cref;
    if (ic->entry && ic->entry->global_cvar_state == (ruby_vm_global_cvar_state)) {
        VALUE v = ((VALUE)RUBY_Qundef);
        ((void)0);
        if (rb_st_lookup(((((struct RClass *)(ic->entry->class_value))->ptr)->iv_tbl), (st_data_t)id, &v) &&
            (__builtin_expect(!!(rb_ractor_main_p()), 1))) {
            return v;
        }
    }
    cref = vm_get_cref(((((reg_cfp)->ep))));
    VALUE klass = vm_get_cvar_base(cref, reg_cfp, 1);
    return update_classvariable_cache(iseq, klass, id, ic);
}static inline 
VALUE
rb_vm_getclassvariable(const rb_iseq_t *iseq, const rb_control_frame_t *cfp, ID id, ICVARC ic)
{
    return vm_getclassvariable(iseq, cfp, id, ic);
}
static inline void
vm_setclassvariable(const rb_iseq_t *iseq, const rb_control_frame_t *reg_cfp, ID id, VALUE val, ICVARC ic)
{
    const rb_cref_t *cref;
    if (ic->entry && ic->entry->global_cvar_state == (ruby_vm_global_cvar_state)) {
        ((void)0);
        rb_class_ivar_set(ic->entry->class_value, id, val);
        return;
    }
    cref = vm_get_cref(((((reg_cfp)->ep))));
    VALUE klass = vm_get_cvar_base(cref, reg_cfp, 1);
    rb_cvar_set(klass, id, val);
    update_classvariable_cache(iseq, klass, id, ic);
}static inline 
void
rb_vm_setclassvariable(const rb_iseq_t *iseq, const rb_control_frame_t *cfp, ID id, VALUE val, ICVARC ic)
{
    vm_setclassvariable(iseq, cfp, id, val, ic);
}
static inline VALUE
vm_getinstancevariable(const rb_iseq_t *iseq, VALUE obj, ID id, IVC ic)
{
    return vm_getivar(obj, id, iseq, ic, ((void *)0), 0);
}
static inline void
vm_setinstancevariable(const rb_iseq_t *iseq, VALUE obj, ID id, VALUE val, IVC ic)
{
    vm_setivar(obj, id, val, iseq, ic, 0, 0);
}static inline 
void
rb_vm_setinstancevariable(const rb_iseq_t *iseq, VALUE obj, ID id, VALUE val, IVC ic)
{
    vm_setinstancevariable(iseq, obj, id, val, ic);
}static inline 
VALUE
rb_vm_set_ivar_idx(VALUE obj, uint32_t index, VALUE val)
{
    ((void)0);
    do { VALUE frozen_obj = (obj); if ((__builtin_expect(!!(RB_OBJ_FROZEN(frozen_obj)), 0))) { rb_error_frozen_object(frozen_obj); } } while (0);
    ((void)0);
    if ((__builtin_expect(!!(index >= ROBJECT_NUMIV(obj)), 0))) {
        rb_init_iv_list(obj);
    }
    VALUE *ptr = ROBJECT_IVPTR(obj);
    rb_obj_write((VALUE)(obj), __extension__({
   ;
   ; __typeof__((VALUE *)(&ptr[index])) unaligned_member_access_result = ((VALUE *)(&ptr[index]));
   ; unaligned_member_access_result; }), (VALUE)(val), "./vm_insnhelper.c", 1403);
    return val;
}
static VALUE
vm_throw_continue(const rb_execution_context_t *ec, VALUE err)
{
    if (RB_FIXNUM_P(err)) {
 ec->tag->state = RB_FIX2INT(err);
    }
    else if (RB_SYMBOL_P(err)) {
 ec->tag->state = RUBY_TAG_THROW;
    }
    else if (imemo_throw_data_p((VALUE)err)) {
 ec->tag->state = THROW_DATA_STATE((struct vm_throw_data *)err);
    }
    else {
 ec->tag->state = RUBY_TAG_RAISE;
    }
    return err;
}
static VALUE
vm_throw_start(const rb_execution_context_t *ec, rb_control_frame_t *const reg_cfp, enum ruby_tag_type state,
               const int flag, const VALUE throwobj)
{
    const rb_control_frame_t *escape_cfp = ((void *)0);
    const rb_control_frame_t * const eocfp = RUBY_VM_END_CONTROL_FRAME(ec);
    if (flag != 0) {
    }
    else if (state == RUBY_TAG_BREAK) {
 int is_orphan = 1;
 const VALUE *ep = ((((reg_cfp)->ep)));
 const rb_iseq_t *base_iseq = ((((reg_cfp)))->iseq);
 escape_cfp = reg_cfp;
 while (base_iseq->body->type != ISEQ_TYPE_BLOCK) {
     if (escape_cfp->iseq->body->type == ISEQ_TYPE_CLASS) {
  escape_cfp = ((escape_cfp)+1);
  ep = escape_cfp->ep;
  base_iseq = escape_cfp->iseq;
     }
     else {
  ep = VM_ENV_PREV_EP(ep);
  base_iseq = base_iseq->body->parent_iseq;
  escape_cfp = rb_vm_search_cf_from_ep(ec, escape_cfp, ep);
  ((void)0);
     }
 }
 if (VM_FRAME_LAMBDA_P(escape_cfp)) {
     is_orphan = 0;
     state = RUBY_TAG_RETURN;
 }
 else {
     ep = VM_ENV_PREV_EP(ep);
     while (escape_cfp < eocfp) {
  if (escape_cfp->ep == ep) {
      const rb_iseq_t *const iseq = escape_cfp->iseq;
      const VALUE epc = escape_cfp->pc - iseq->body->iseq_encoded;
      const struct iseq_catch_table *const ct = iseq->body->catch_table;
      unsigned int i;
      if (!ct) break;
      for (i=0; i < ct->size; i++) {
   const struct iseq_catch_table_entry *const entry =
       __extension__({
      ;
      ; __typeof__(&(ct)->entries[i]) unaligned_member_access_result = (&(ct)->entries[i]);
      ; unaligned_member_access_result; });
   if (entry->type == CATCH_TYPE_BREAK &&
       entry->iseq == base_iseq &&
       entry->start < epc && entry->end >= epc) {
       if (entry->cont == epc) {
    is_orphan = 0;
       }
       break;
   }
      }
      break;
  }
  escape_cfp = ((escape_cfp)+1);
     }
 }
 if (is_orphan) {
     rb_vm_localjump_error("break from proc-closure", throwobj, RUBY_TAG_BREAK);
 }
    }
    else if (state == RUBY_TAG_RETRY) {
 const VALUE *ep = VM_ENV_PREV_EP(((((reg_cfp)->ep))));
 escape_cfp = rb_vm_search_cf_from_ep(ec, reg_cfp, ep);
    }
    else if (state == RUBY_TAG_RETURN) {
 const VALUE *current_ep = ((((reg_cfp)->ep)));
        const VALUE *target_ep = ((void *)0), *target_lep, *ep = current_ep;
 int in_class_frame = 0;
 int toplevel = 1;
 escape_cfp = reg_cfp;
        while (!VM_ENV_LOCAL_P(ep)) {
            if (VM_ENV_FLAGS(ep, VM_FRAME_FLAG_LAMBDA) && target_ep == ((void *)0)) {
                target_ep = ep;
            }
            ep = VM_ENV_PREV_EP(ep);
        }
        target_lep = ep;
        while (escape_cfp < eocfp) {
            const VALUE *lep = VM_CF_LEP(escape_cfp);
     if (!target_lep) {
  target_lep = lep;
     }
     if (lep == target_lep &&
  VM_FRAME_RUBYFRAME_P(escape_cfp) &&
  escape_cfp->iseq->body->type == ISEQ_TYPE_CLASS) {
  in_class_frame = 1;
  target_lep = 0;
     }
     if (lep == target_lep) {
  if (VM_FRAME_LAMBDA_P(escape_cfp)) {
      toplevel = 0;
      if (in_class_frame) {
                        goto valid_return;
      }
      else {
   const VALUE *tep = current_ep;
   while (target_lep != tep) {
       if (escape_cfp->ep == tep) {
                                if (tep == target_ep) {
                                    goto valid_return;
                                }
                                else {
                                    goto unexpected_return;
                                }
       }
       tep = VM_ENV_PREV_EP(tep);
   }
      }
  }
  else if (VM_FRAME_RUBYFRAME_P(escape_cfp)) {
      switch (escape_cfp->iseq->body->type) {
        case ISEQ_TYPE_TOP:
        case ISEQ_TYPE_MAIN:
                        if (toplevel) {
                            if (in_class_frame) goto unexpected_return;
                            if (target_ep == ((void *)0)) {
                                goto valid_return;
                            }
                            else {
                                goto unexpected_return;
                            }
                        }
   break;
        case ISEQ_TYPE_EVAL:
        case ISEQ_TYPE_CLASS:
   toplevel = 0;
   break;
        default:
   break;
      }
  }
     }
     if (escape_cfp->ep == target_lep && escape_cfp->iseq->body->type == ISEQ_TYPE_METHOD) {
                if (target_ep == ((void *)0)) {
                    goto valid_return;
                }
                else {
                    goto unexpected_return;
                }
     }
     escape_cfp = ((escape_cfp)+1);
 }
      unexpected_return:;
 rb_vm_localjump_error("unexpected return", throwobj, RUBY_TAG_RETURN);
      valid_return:;
    }
    else {
 rb_bug("isns(throw): unsupported throw type");
    }
    ec->tag->state = state;
    return (VALUE)THROW_DATA_NEW(throwobj, escape_cfp, state);
}
static VALUE
vm_throw(const rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
  rb_num_t throw_state, VALUE throwobj)
{
    const int state = (int)(throw_state & VM_THROW_STATE_MASK);
    const int flag = (int)(throw_state & VM_THROW_NO_ESCAPE_FLAG);
    if (state != 0) {
        return vm_throw_start(ec, reg_cfp, state, flag, throwobj);
    }
    else {
 return vm_throw_continue(ec, throwobj);
    }
}
static inline void
vm_expandarray(VALUE *sp, VALUE ary, rb_num_t num, int flag)
{
    int is_splat = flag & 0x01;
    rb_num_t space_size = num + is_splat;
    VALUE *base = sp - 1;
    const VALUE *ptr;
    rb_num_t len;
    const VALUE obj = ary;
    if (!RB_TYPE_P(ary, RUBY_T_ARRAY) && RB_NIL_P(ary = rb_check_array_type(ary))) {
 ary = obj;
 ptr = &ary;
 len = 1;
    }
    else {
        ptr = rb_array_const_ptr_transient(ary);
 len = (rb_num_t)rb_array_len(ary);
    }
    if (space_size == 0) {
    }
    else if (flag & 0x02) {
 rb_num_t i = 0, j;
 if (len < num) {
     for (i=0; i<num-len; i++) {
  *base++ = ((VALUE)RUBY_Qnil);
     }
 }
 for (j=0; i<num; i++, j++) {
     VALUE v = ptr[len - j - 1];
     *base++ = v;
 }
 if (is_splat) {
     *base = rb_ary_new_from_values(len - j, ptr);
 }
    }
    else {
 rb_num_t i;
 VALUE *bptr = &base[space_size - 1];
 for (i=0; i<num; i++) {
     if (len <= i) {
  for (; i<num; i++) {
      *bptr-- = ((VALUE)RUBY_Qnil);
  }
  break;
     }
     *bptr-- = ptr[i];
 }
 if (is_splat) {
     if (num > len) {
  *bptr = rb_ary_new();
     }
     else {
  *bptr = rb_ary_new_from_values(len - num, ptr + num);
     }
 }
    }
    (*__extension__ ({ volatile VALUE *rb_gc_guarded_ptr = &(ary); __asm__("" : : "m"(rb_gc_guarded_ptr)); rb_gc_guarded_ptr; }));
}
static VALUE vm_call_general(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling);
static VALUE vm_mtbl_dump(VALUE klass, ID target_mid);
static struct rb_class_cc_entries *
vm_ccs_create(VALUE klass, const rb_callable_method_entry_t *cme)
{
    struct rb_class_cc_entries *ccs = ((struct rb_class_cc_entries *)ruby_xmalloc(sizeof(struct rb_class_cc_entries)));
    ccs->capa = 0;
    ccs->len = 0;
    rb_obj_write((VALUE)(klass), __extension__({
   ;
   ; __typeof__((VALUE *)(&ccs->cme)) unaligned_member_access_result = ((VALUE *)(&ccs->cme));
   ; unaligned_member_access_result; }), (VALUE)(cme), "./vm_insnhelper.c", 1700);
    (((rb_callable_method_entry_t *)cme)->flags |= ((VALUE)RUBY_FL_USER8));
    ccs->entries = ((void *)0);
    return ccs;
}
static void
vm_ccs_push(VALUE klass, struct rb_class_cc_entries *ccs, const struct rb_callinfo *ci, const struct rb_callcache *cc)
{
    if (! vm_cc_markable(cc)) {
        return;
    }
    else if (! vm_ci_markable(ci)) {
        return;
    }
    if ((__builtin_expect(!!(ccs->len == ccs->capa), 0))) {
        if (ccs->capa == 0) {
            ccs->capa = 1;
            ccs->entries = ((struct rb_class_cc_entries_entry *)ruby_xmalloc2((ccs->capa), sizeof(struct rb_class_cc_entries_entry)));
        }
        else {
            ccs->capa *= 2;
            ((ccs->entries) = ((struct rb_class_cc_entries_entry *)ruby_xrealloc2((void *)(ccs->entries), (ccs->capa), sizeof(struct rb_class_cc_entries_entry))));
        }
    }
    ((void)0);
    const int pos = ccs->len++;
    rb_obj_write((VALUE)(klass), __extension__({
   ;
   ; __typeof__((VALUE *)(&ccs->entries[pos].ci)) unaligned_member_access_result = ((VALUE *)(&ccs->entries[pos].ci));
   ; unaligned_member_access_result; }), (VALUE)(ci), "./vm_insnhelper.c", 1729);
    rb_obj_write((VALUE)(klass), __extension__({
   ;
   ; __typeof__((VALUE *)(&ccs->entries[pos].cc)) unaligned_member_access_result = ((VALUE *)(&ccs->entries[pos].cc));
   ; unaligned_member_access_result; }), (VALUE)(cc), "./vm_insnhelper.c", 1730);
    if (0) {
    }
}
static const struct rb_callcache *
vm_search_method_slowpath0(VALUE cd_owner, struct rb_call_data *cd, VALUE klass)
{
    const struct rb_callcache *cc = rb_vm_search_method_slowpath(cd->ci, klass);
    cd->cc = cc;
    const struct rb_callcache *empty_cc =
      rb_vm_empty_cc();
    if (cd_owner && cc != empty_cc) (rb_obj_written((VALUE)(cd_owner), (VALUE)(((VALUE)RUBY_Qundef)), (VALUE)(cc), "./vm_insnhelper.c", 1912));
    ((void)0);
    return cc;
}
static const struct rb_callcache *
vm_search_method_fastpath(VALUE cd_owner, struct rb_call_data *cd, VALUE klass)
{
    const struct rb_callcache *cc = cd->cc;
    if ((__builtin_expect(!!(vm_cc_class_check(cc, klass)), 1))) {
        if ((__builtin_expect(!!(!((vm_cc_cme(cc))->flags & ((VALUE)RUBY_FL_USER9))), 1))) {
            ((void)0);
            ((void)0);
            ((void)0);
            return cc;
        }
        ((void)0);
    }
    else {
        ((void)0);
    }
    return vm_search_method_slowpath0(cd_owner, cd, klass);
}
static const struct rb_callcache *
vm_search_method(VALUE cd_owner, struct rb_call_data *cd, VALUE recv)
{
    VALUE klass = rb_class_of(recv);
    ((void)0);
    ((void)0);
    return vm_search_method_fastpath(cd_owner, cd, klass);
}
static inline int
check_cfunc(const rb_callable_method_entry_t *me, VALUE (*func)())
{
    if (! me) {
        return 0;
    }
    else {
        ((void)0);
        ((void)0);
        ((void)0);
        if (me->def->type != VM_METHOD_TYPE_CFUNC) {
            return 0;
        }
        else {
            return me->def->body.cfunc.func == func;
        }
    }
}
static inline int
vm_method_cfunc_is(const rb_iseq_t *iseq, CALL_DATA cd, VALUE recv, VALUE (*func)())
{
    ((void)0);
    const struct rb_callcache *cc = vm_search_method((VALUE)iseq, cd, recv);
    return check_cfunc(vm_cc_cme(cc), func);
}
static inline _Bool
FIXNUM_2_P(VALUE a, VALUE b)
{
    long x = a;
    long y = b;
    long z = x & y & 1;
    return z == 1;
}
static inline _Bool
FLONUM_2_P(VALUE a, VALUE b)
{
    long x = a;
    long y = b;
    long z = ((x ^ 2) | (y ^ 2)) & 3;
    return !z;
}
static VALUE
opt_equality_specialized(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) && ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_EQ)]&((1 << 0))) == 0), 1)))) {
        goto compare_by_identity;
    }
    else if (FLONUM_2_P(recv, obj) && ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_EQ)]&((1 << 1))) == 0), 1)))) {
        goto compare_by_identity;
    }
    else if (RB_STATIC_SYM_P(recv) && RB_STATIC_SYM_P(obj) && ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_EQ)]&((1 << 6))) == 0), 1)))) {
        goto compare_by_identity;
    }
    else if (RB_SPECIAL_CONST_P(recv)) {
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat && RB_FLOAT_TYPE_P(obj) && ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_EQ)]&((1 << 1))) == 0), 1)))) {
        double a = rb_float_value_inline(recv);
        double b = rb_float_value_inline(obj);
        return ((a == b) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
    }
    else if (RBASIC_CLASS(recv) == rb_cString && ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_EQ)]&((1 << 2))) == 0), 1)))) {
        if (recv == obj) {
            return ((VALUE)RUBY_Qtrue);
        }
        else if (RB_TYPE_P(obj, RUBY_T_STRING)) {
            return rb_str_eql_internal(obj, recv);
        }
    }
    return ((VALUE)RUBY_Qundef);
  compare_by_identity:
    return ((recv == obj) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
}
static VALUE
opt_equality(const rb_iseq_t *cd_owner, VALUE recv, VALUE obj, CALL_DATA cd)
{
    ((void)0);
    VALUE val = opt_equality_specialized(recv, obj);
    if (val != ((VALUE)RUBY_Qundef)) return val;
    if (!vm_method_cfunc_is(cd_owner, cd, recv, rb_obj_equal)) {
        return ((VALUE)RUBY_Qundef);
    }
    else {
        return ((recv == obj) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
    }
}
extern VALUE rb_vm_call0(rb_execution_context_t *ec, VALUE, ID, int, const VALUE*, const rb_callable_method_entry_t *, int kw_splat);
extern VALUE rb_vm_call_with_refinements(rb_execution_context_t *, VALUE, ID, int, const VALUE *, int);
static VALUE
check_match(rb_execution_context_t *ec, VALUE pattern, VALUE target, enum vm_check_match_type type)
{
    switch (type) {
      case VM_CHECKMATCH_TYPE_WHEN:
 return pattern;
      case VM_CHECKMATCH_TYPE_RESCUE:
 if (!rb_obj_is_kind_of(pattern, rb_cModule)) {
     rb_raise(rb_eTypeError, "class or module required for rescue clause");
 }
      case VM_CHECKMATCH_TYPE_CASE: {
        return rb_vm_call_with_refinements(ec, pattern, idEqq, 1, &target, 0);
      }
      default:
 rb_bug("check_match: unreachable");
    }
}
static inline VALUE
double_cmp_lt(double a, double b)
{
    ;
    return ((a < b) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
}
static inline VALUE
double_cmp_le(double a, double b)
{
    ;
    return ((a <= b) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
}
static inline VALUE
double_cmp_gt(double a, double b)
{
    ;
    return ((a > b) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
}
static inline VALUE
double_cmp_ge(double a, double b)
{
    ;
    return ((a >= b) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
}
static inline VALUE *
vm_base_ptr(const rb_control_frame_t *cfp)
{
    return cfp->__bp__;
}
__attribute__((__noreturn__)) static void raise_argument_error(rb_execution_context_t *ec, const rb_iseq_t *iseq, const VALUE exc);
__attribute__((__noreturn__)) static void argument_arity_error(rb_execution_context_t *ec, const rb_iseq_t *iseq, const int miss_argc, const int min_argc, const int max_argc);
__attribute__((__noreturn__)) static void argument_kw_error(rb_execution_context_t *ec, const rb_iseq_t *iseq, const char *error, const VALUE keys);
VALUE rb_keyword_error_new(const char *error, VALUE keys);
static VALUE method_missing(rb_execution_context_t *ec, VALUE obj, ID id, int argc, const VALUE *argv,
                            enum method_missing_reason call_status, int kw_splat);
__attribute__ ((__visibility__("default"))) extern
const rb_callable_method_entry_t *rb_resolve_refined_method_callable(VALUE refinements, const rb_callable_method_entry_t *me);
struct args_info {
    VALUE *argv;
    int argc;
    int rest_index;
    int rest_dupped;
    const struct rb_callinfo_kwarg *kw_arg;
    VALUE *kw_argv;
    VALUE rest;
};
enum arg_setup_type {
    arg_setup_method,
    arg_setup_block
};
static inline void
arg_rest_dup(struct args_info *args)
{
    if (!args->rest_dupped) {
        args->rest = rb_ary_dup(args->rest);
        args->rest_dupped = 1;
    }
}
static inline int
args_argc(struct args_info *args)
{
    if (args->rest == ((VALUE)RUBY_Qfalse)) {
 return args->argc;
    }
    else {
 return args->argc + RARRAY_LENINT(args->rest) - args->rest_index;
    }
}
static inline void
args_extend(struct args_info *args, const int min_argc)
{
    int i;
    if (args->rest) {
        arg_rest_dup(args);
 ((void)0);
 for (i=args->argc + RARRAY_LENINT(args->rest); i<min_argc; i++) {
     rb_ary_push(args->rest, ((VALUE)RUBY_Qnil));
 }
    }
    else {
 for (i=args->argc; i<min_argc; i++) {
     args->argv[args->argc++] = ((VALUE)RUBY_Qnil);
 }
    }
}
static inline void
args_reduce(struct args_info *args, int over_argc)
{
    if (args->rest) {
 const long len = rb_array_len(args->rest);
 if (len > over_argc) {
     arg_rest_dup(args);
     rb_ary_resize(args->rest, len - over_argc);
     return;
 }
 else {
     args->rest = ((VALUE)RUBY_Qfalse);
     over_argc -= len;
 }
    }
    ((void)0);
    args->argc -= over_argc;
}
static inline int
args_check_block_arg0(struct args_info *args)
{
    VALUE ary = ((VALUE)RUBY_Qnil);
    if (args->rest && rb_array_len(args->rest) == 1) {
 VALUE arg0 = RARRAY_AREF(args->rest, 0);
 ary = rb_check_array_type(arg0);
    }
    else if (args->argc == 1) {
 VALUE arg0 = args->argv[0];
 ary = rb_check_array_type(arg0);
 args->argv[0] = arg0;
    }
    if (!RB_NIL_P(ary)) {
 args->rest = ary;
 args->rest_index = 0;
 args->argc = 0;
 return 1;
    }
    return 0;
}
static inline void
args_copy(struct args_info *args)
{
    if (args->rest != ((VALUE)RUBY_Qfalse)) {
 int argc = args->argc;
 args->argc = 0;
        arg_rest_dup(args);
 while (args->rest_index > 0 && argc > 0) {
     RARRAY_ASET(args->rest, --args->rest_index, args->argv[--argc]);
 }
 while (argc > 0) {
     rb_ary_unshift(args->rest, args->argv[--argc]);
 }
    }
    else if (args->argc > 0) {
 args->rest = rb_ary_new_from_values(args->argc, args->argv);
 args->rest_index = 0;
        args->rest_dupped = 1;
 args->argc = 0;
    }
}
static inline const VALUE *
args_rest_argv(struct args_info *args)
{
    return rb_array_const_ptr_transient(args->rest) + args->rest_index;
}
static inline VALUE
args_rest_array(struct args_info *args)
{
    VALUE ary;
    if (args->rest) {
        ary = rb_ary_behead(args->rest, args->rest_index);
        args->rest_index = 0;
 args->rest = 0;
    }
    else {
 ary = rb_ary_new();
    }
    return ary;
}
static int
args_kw_argv_to_hash(struct args_info *args)
{
    const struct rb_callinfo_kwarg *kw_arg = args->kw_arg;
    const VALUE *const passed_keywords = kw_arg->keywords;
    const int kw_len = kw_arg->keyword_len;
    VALUE h = rb_hash_new_with_size(kw_len);
    const int kw_start = args->argc - kw_len;
    const VALUE * const kw_argv = args->argv + kw_start;
    int i;
    args->argc = kw_start + 1;
    for (i=0; i<kw_len; i++) {
 rb_hash_aset(h, passed_keywords[i], kw_argv[i]);
    }
    args->argv[args->argc - 1] = h;
    return args->argc;
}
static inline void
args_setup_lead_parameters(struct args_info *args, int argc, VALUE *locals)
{
    if (args->argc >= argc) {
 args->argc -= argc;
 args->argv += argc;
    }
    else {
 int i, j;
 const VALUE *argv = args_rest_argv(args);
 for (i=args->argc, j=0; i<argc; i++, j++) {
     locals[i] = argv[j];
 }
 args->rest_index += argc - args->argc;
 args->argc = 0;
    }
}
static inline void
args_setup_post_parameters(struct args_info *args, int argc, VALUE *locals)
{
    long len;
    len = rb_array_len(args->rest);
    ruby_nonempty_memcpy((locals), (rb_array_const_ptr_transient(args->rest) + len - argc), rbimpl_size_mul_or_raise(sizeof(VALUE), (argc)));
    rb_ary_resize(args->rest, len - argc);
}
static inline int
args_setup_opt_parameters(struct args_info *args, int opt_max, VALUE *locals)
{
    int i;
    if (args->argc >= opt_max) {
 args->argc -= opt_max;
 args->argv += opt_max;
 i = opt_max;
    }
    else {
 int j;
 i = args->argc;
 args->argc = 0;
 if (args->rest) {
            int len = RARRAY_LENINT(args->rest);
            const VALUE *argv = rb_array_const_ptr_transient(args->rest);
            for (; i<opt_max && args->rest_index < len; i++, args->rest_index++) {
                locals[i] = argv[args->rest_index];
            }
        }
 for (j=i; j<opt_max; j++) {
     locals[j] = ((VALUE)RUBY_Qnil);
 }
    }
    return i;
}
static inline void
args_setup_rest_parameter(struct args_info *args, VALUE *locals)
{
    *locals = args_rest_array(args);
}
static VALUE
make_unknown_kw_hash(const VALUE *passed_keywords, int passed_keyword_len, const VALUE *kw_argv)
{
    int i;
    VALUE obj = rb_ary_tmp_new(1);
    for (i=0; i<passed_keyword_len; i++) {
 if (kw_argv[i] != ((VALUE)RUBY_Qundef)) {
     rb_ary_push(obj, passed_keywords[i]);
 }
    }
    return obj;
}
static VALUE
make_rest_kw_hash(const VALUE *passed_keywords, int passed_keyword_len, const VALUE *kw_argv)
{
    int i;
    VALUE obj = rb_hash_new_with_size(passed_keyword_len);
    for (i=0; i<passed_keyword_len; i++) {
 if (kw_argv[i] != ((VALUE)RUBY_Qundef)) {
     rb_hash_aset(obj, passed_keywords[i], kw_argv[i]);
 }
    }
    return obj;
}
static inline int
args_setup_kw_parameters_lookup(const ID key, VALUE *ptr, const VALUE *const passed_keywords, VALUE *passed_values, const int passed_keyword_len)
{
    int i;
    const VALUE keyname = rb_id2sym(key);
    for (i=0; i<passed_keyword_len; i++) {
 if (keyname == passed_keywords[i]) {
     *ptr = passed_values[i];
     passed_values[i] = ((VALUE)RUBY_Qundef);
     return 1;
 }
    }
    return 0;
}
static void
args_setup_kw_parameters(rb_execution_context_t *const ec, const rb_iseq_t *const iseq,
    VALUE *const passed_values, const int passed_keyword_len, const VALUE *const passed_keywords,
    VALUE *const locals)
{
    const ID *acceptable_keywords = iseq->body->param.keyword->table;
    const int req_key_num = iseq->body->param.keyword->required_num;
    const int key_num = iseq->body->param.keyword->num;
    const VALUE * const default_values = iseq->body->param.keyword->default_values;
    VALUE missing = 0;
    int i, di, found = 0;
    int unspecified_bits = 0;
    VALUE unspecified_bits_value = ((VALUE)RUBY_Qnil);
    for (i=0; i<req_key_num; i++) {
 ID key = acceptable_keywords[i];
 if (args_setup_kw_parameters_lookup(key, &locals[i], passed_keywords, passed_values, passed_keyword_len)) {
     found++;
 }
 else {
     if (!missing) missing = rb_ary_tmp_new(1);
     rb_ary_push(missing, rb_id2sym(key));
 }
    }
    if (missing) argument_kw_error(ec, iseq, "missing", missing);
    for (di=0; i<key_num; i++, di++) {
 if (args_setup_kw_parameters_lookup(acceptable_keywords[i], &locals[i], passed_keywords, passed_values, passed_keyword_len)) {
     found++;
 }
 else {
     if (default_values[di] == ((VALUE)RUBY_Qundef)) {
  locals[i] = ((VALUE)RUBY_Qnil);
  if ((__builtin_expect(!!(i < (32-1)), 1))) {
      unspecified_bits |= 0x01 << di;
  }
  else {
      if (RB_NIL_P(unspecified_bits_value)) {
   int j;
   unspecified_bits_value = rb_hash_new();
   for (j=0; j<(32-1); j++) {
       if (unspecified_bits & (0x01 << j)) {
    rb_hash_aset(unspecified_bits_value, __builtin_choose_expr( __builtin_constant_p(j), ((VALUE)(j)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(j)), ((VALUE)RUBY_Qtrue));
       }
   }
      }
      rb_hash_aset(unspecified_bits_value, __builtin_choose_expr( __builtin_constant_p(di), ((VALUE)(di)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(di)), ((VALUE)RUBY_Qtrue));
  }
     }
     else {
  locals[i] = default_values[di];
     }
 }
    }
    if (iseq->body->param.flags.has_kwrest) {
 const int rest_hash_index = key_num + 1;
 locals[rest_hash_index] = make_rest_kw_hash(passed_keywords, passed_keyword_len, passed_values);
    }
    else {
 if (found != passed_keyword_len) {
     VALUE keys = make_unknown_kw_hash(passed_keywords, passed_keyword_len, passed_values);
     argument_kw_error(ec, iseq, "unknown", keys);
 }
    }
    if (RB_NIL_P(unspecified_bits_value)) {
 unspecified_bits_value = __builtin_choose_expr( __builtin_constant_p(unspecified_bits), ((VALUE)(unspecified_bits)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(unspecified_bits));
    }
    locals[key_num] = unspecified_bits_value;
}
static inline void
args_setup_kw_rest_parameter(VALUE keyword_hash, VALUE *locals, int kw_flag)
{
    if (RB_NIL_P(keyword_hash)) {
        keyword_hash = rb_hash_new();
    }
    else if (!(kw_flag & (0x01 << VM_CALL_KW_SPLAT_MUT_bit))) {
        keyword_hash = rb_hash_dup(keyword_hash);
    }
    locals[0] = keyword_hash;
}
static inline void
args_setup_block_parameter(const rb_execution_context_t *ec, struct rb_calling_info *calling, VALUE *locals)
{
    VALUE block_handler = calling->block_handler;
    *locals = rb_vm_bh_to_procval(ec, block_handler);
}
struct fill_values_arg {
    VALUE *keys;
    VALUE *vals;
    int argc;
};
static int
fill_keys_values(st_data_t key, st_data_t val, st_data_t ptr)
{
    struct fill_values_arg *arg = (struct fill_values_arg *)ptr;
    int i = arg->argc++;
    arg->keys[i] = (VALUE)key;
    arg->vals[i] = (VALUE)val;
    return ST_CONTINUE;
}
static inline int
ignore_keyword_hash_p(VALUE keyword_hash, const rb_iseq_t * const iseq, unsigned int * kw_flag, VALUE * converted_keyword_hash)
{
    if (!RB_TYPE_P(keyword_hash, RUBY_T_HASH)) {
        keyword_hash = rb_to_hash_type(keyword_hash);
    }
    if (!(*kw_flag & (0x01 << VM_CALL_KW_SPLAT_MUT_bit)) &&
            (iseq->body->param.flags.has_kwrest ||
             iseq->body->param.flags.ruby2_keywords)) {
        *kw_flag |= (0x01 << VM_CALL_KW_SPLAT_MUT_bit);
        keyword_hash = rb_hash_dup(keyword_hash);
    }
    *converted_keyword_hash = keyword_hash;
    return !(iseq->body->param.flags.has_kw) &&
           !(iseq->body->param.flags.has_kwrest) &&
           RHASH_EMPTY_P(keyword_hash);
}
COLDFUNC static int
setup_parameters_complex(rb_execution_context_t * const ec, const rb_iseq_t * const iseq,
    struct rb_calling_info *const calling,
                         const struct rb_callinfo *ci,
                         VALUE * const locals, const enum arg_setup_type arg_setup_type) {
    const int min_argc = iseq->body->param.lead_num + iseq->body->param.post_num;
    const int max_argc = (iseq->body->param.flags.has_rest == 0) ? min_argc + iseq->body->param.opt_num : (-1);
    int given_argc;
    unsigned int kw_flag = vm_ci_flag(ci) & ((0x01 << VM_CALL_KWARG_bit) | (0x01 << VM_CALL_KW_SPLAT_bit) | (0x01 << VM_CALL_KW_SPLAT_MUT_bit));
    int opt_pc = 0, allow_autosplat = !kw_flag;
    struct args_info args_body, *args;
    VALUE keyword_hash = ((VALUE)RUBY_Qnil);
    VALUE * const orig_sp = ec->cfp->sp;
    unsigned int i;
    VALUE flag_keyword_hash = 0;
    VALUE converted_keyword_hash = 0;
    ;
    for (i=calling->argc; i<iseq->body->param.size; i++) {
 locals[i] = ((VALUE)RUBY_Qnil);
    }
    ec->cfp->sp = &locals[i];
    args = &args_body;
    given_argc = args->argc = calling->argc;
    args->argv = locals;
    args->rest_dupped = 0;
    if (kw_flag & (0x01 << VM_CALL_KWARG_bit)) {
 args->kw_arg = vm_ci_kwarg(ci);
 if (iseq->body->param.flags.has_kw) {
     int kw_len = args->kw_arg->keyword_len;
     args->kw_argv = ((VALUE *)__builtin_alloca (rbimpl_size_mul_or_raise(sizeof(VALUE), (kw_len))));
     args->argc -= kw_len;
     given_argc -= kw_len;
     ruby_nonempty_memcpy((args->kw_argv), (locals + args->argc), rbimpl_size_mul_or_raise(sizeof(VALUE), (kw_len)));
 }
 else {
     args->kw_argv = ((void *)0);
     given_argc = args_kw_argv_to_hash(args);
            kw_flag |= (0x01 << VM_CALL_KW_SPLAT_bit) | (0x01 << VM_CALL_KW_SPLAT_MUT_bit);
 }
    }
    else {
 args->kw_arg = ((void *)0);
 args->kw_argv = ((void *)0);
    }
    if (vm_ci_flag(ci) & (0x01 << VM_CALL_ARGS_SPLAT_bit)) {
        VALUE rest_last = 0;
        int len;
 args->rest = locals[--args->argc];
 args->rest_index = 0;
        len = RARRAY_LENINT(args->rest);
        given_argc += len - 1;
        rest_last = RARRAY_AREF(args->rest, len - 1);
        if (!kw_flag && len > 0) {
            if (RB_TYPE_P(rest_last, RUBY_T_HASH) &&
                (((struct RHash *)rest_last)->basic.flags & RHASH_PASS_AS_KEYWORDS)) {
                rest_last = rb_hash_dup(rest_last);
                kw_flag |= (0x01 << VM_CALL_KW_SPLAT_bit) | (0x01 << VM_CALL_KW_SPLAT_MUT_bit);
            }
            else {
                rest_last = 0;
            }
        }
        if (kw_flag & (0x01 << VM_CALL_KW_SPLAT_bit)) {
            if (ignore_keyword_hash_p(rest_last, iseq, &kw_flag, &converted_keyword_hash)) {
                arg_rest_dup(args);
                rb_ary_pop(args->rest);
                given_argc--;
                kw_flag &= ~((0x01 << VM_CALL_KW_SPLAT_bit) | (0x01 << VM_CALL_KW_SPLAT_MUT_bit));
     }
            else {
                if (rest_last != converted_keyword_hash) {
                    rest_last = converted_keyword_hash;
                    arg_rest_dup(args);
                    RARRAY_ASET(args->rest, len - 1, rest_last);
                }
                if (iseq->body->param.flags.ruby2_keywords && rest_last) {
                    flag_keyword_hash = rest_last;
                }
                else if (iseq->body->param.flags.has_kw || iseq->body->param.flags.has_kwrest) {
                    arg_rest_dup(args);
                    rb_ary_pop(args->rest);
                    given_argc--;
                    keyword_hash = rest_last;
                }
            }
        }
    }
    else {
        if (kw_flag & (0x01 << VM_CALL_KW_SPLAT_bit)) {
            VALUE last_arg = args->argv[args->argc-1];
            if (ignore_keyword_hash_p(last_arg, iseq, &kw_flag, &converted_keyword_hash)) {
                args->argc--;
                given_argc--;
                kw_flag &= ~((0x01 << VM_CALL_KW_SPLAT_bit) | (0x01 << VM_CALL_KW_SPLAT_MUT_bit));
     }
            else {
                if (last_arg != converted_keyword_hash) {
                    last_arg = converted_keyword_hash;
                    args->argv[args->argc-1] = last_arg;
                }
                if (iseq->body->param.flags.ruby2_keywords) {
                    flag_keyword_hash = last_arg;
                }
                else if (iseq->body->param.flags.has_kw || iseq->body->param.flags.has_kwrest) {
                    args->argc--;
                    given_argc--;
                    keyword_hash = last_arg;
                }
            }
        }
 args->rest = ((VALUE)RUBY_Qfalse);
    }
    if (flag_keyword_hash && RB_TYPE_P(flag_keyword_hash, RUBY_T_HASH)) {
        ((struct RHash *)flag_keyword_hash)->basic.flags |= RHASH_PASS_AS_KEYWORDS;
    }
    if (kw_flag && iseq->body->param.flags.accepts_no_kwarg) {
 rb_raise(rb_eArgError, "no keywords accepted");
    }
    switch (arg_setup_type) {
      case arg_setup_method:
 break;
      case arg_setup_block:
        if (given_argc == (RB_NIL_P(keyword_hash) ? 1 : 2) &&
            allow_autosplat &&
            (min_argc > 0 || iseq->body->param.opt_num > 1) &&
     !iseq->body->param.flags.ambiguous_param0 &&
     args_check_block_arg0(args)) {
     given_argc = RARRAY_LENINT(args->rest);
 }
 break;
    }
    if (given_argc < min_argc) {
        if (arg_setup_type == arg_setup_block) {
            do { __extension__ _Static_assert(sizeof(*((ec->cfp)->sp)) == sizeof(VALUE), "sizeof_sp" ": " "sizeof(*((ec->cfp)->sp)) == sizeof(VALUE)"); __extension__ _Static_assert(sizeof(*((ec->cfp))) == sizeof(rb_control_frame_t), "sizeof_cfp" ": " "sizeof(*((ec->cfp))) == sizeof(rb_control_frame_t)"); const struct rb_control_frame_struct *bound = (void *)&((ec->cfp)->sp)[((min_argc))]; if ((__builtin_expect(!!(((ec->cfp)) <= &bound[1]), 0))) { vm_stackoverflow(); } } while (0);
            given_argc = min_argc;
            args_extend(args, min_argc);
        }
        else {
            argument_arity_error(ec, iseq, given_argc, min_argc, max_argc);
        }
    }
    if (given_argc > max_argc && max_argc != (-1)) {
 if (arg_setup_type == arg_setup_block) {
     args_reduce(args, given_argc - max_argc);
     given_argc = max_argc;
 }
 else {
     argument_arity_error(ec, iseq, given_argc, min_argc, max_argc);
 }
    }
    if (iseq->body->param.flags.has_lead) {
 args_setup_lead_parameters(args, iseq->body->param.lead_num, locals + 0);
    }
    if (iseq->body->param.flags.has_rest || iseq->body->param.flags.has_post){
        args_copy(args);
    }
    if (iseq->body->param.flags.has_post) {
 args_setup_post_parameters(args, iseq->body->param.post_num, locals + iseq->body->param.post_start);
    }
    if (iseq->body->param.flags.has_opt) {
 int opt = args_setup_opt_parameters(args, iseq->body->param.opt_num, locals + iseq->body->param.lead_num);
 opt_pc = (int)iseq->body->param.opt_table[opt];
    }
    if (iseq->body->param.flags.has_rest) {
 args_setup_rest_parameter(args, locals + iseq->body->param.rest_start);
    }
    if (iseq->body->param.flags.has_kw) {
 VALUE * const klocals = locals + iseq->body->param.keyword->bits_start - iseq->body->param.keyword->num;
 if (args->kw_argv != ((void *)0)) {
     const struct rb_callinfo_kwarg *kw_arg = args->kw_arg;
     args_setup_kw_parameters(ec, iseq, args->kw_argv, kw_arg->keyword_len, kw_arg->keywords, klocals);
 }
 else if (!RB_NIL_P(keyword_hash)) {
     int kw_len = rb_long2int_inline(RHASH_SIZE(keyword_hash));
     struct fill_values_arg arg;
     arg.keys = args->kw_argv = ((VALUE *)__builtin_alloca (rbimpl_size_mul_or_raise(sizeof(VALUE), (kw_len * 2))));
     arg.vals = arg.keys + kw_len;
     arg.argc = 0;
     rb_hash_foreach(keyword_hash, fill_keys_values, (VALUE)&arg);
     ((void)0);
     args_setup_kw_parameters(ec, iseq, arg.vals, kw_len, arg.keys, klocals);
 }
 else {
     ((void)0);
     args_setup_kw_parameters(ec, iseq, ((void *)0), 0, ((void *)0), klocals);
 }
    }
    else if (iseq->body->param.flags.has_kwrest) {
        args_setup_kw_rest_parameter(keyword_hash, locals + iseq->body->param.keyword->rest_start, kw_flag);
    }
    else if (!RB_NIL_P(keyword_hash) && RHASH_SIZE(keyword_hash) > 0 && arg_setup_type == arg_setup_method) {
 argument_kw_error(ec, iseq, "unknown", rb_hash_keys(keyword_hash));
    }
    if (iseq->body->param.flags.has_block) {
 if (iseq->body->local_iseq == iseq) {
 }
 else {
     args_setup_block_parameter(ec, calling, locals + iseq->body->param.block_start);
 }
    }
    ec->cfp->sp = orig_sp;
    return opt_pc;
}
static void
raise_argument_error(rb_execution_context_t *ec, const rb_iseq_t *iseq, const VALUE exc)
{
    VALUE at;
    if (iseq) {
 vm_push_frame(ec, iseq, VM_FRAME_MAGIC_DUMMY | VM_ENV_FLAG_LOCAL, ((VALUE)RUBY_Qnil) ,
        0 , ((VALUE)RUBY_Qfalse) ,
        iseq->body->iseq_encoded,
        ec->cfp->sp, 0, 0 );
 at = rb_ec_backtrace_object(ec);
 rb_backtrace_use_iseq_first_lineno_for_last_location(at);
 rb_vm_pop_frame(ec);
    }
    else {
 at = rb_ec_backtrace_object(ec);
    }
    rb_ivar_set(exc, idBt_locations, at);
    rb_exc_set_backtrace(exc, at);
    rb_exc_raise(exc);
}
static void
argument_arity_error(rb_execution_context_t *ec, const rb_iseq_t *iseq, const int miss_argc, const int min_argc, const int max_argc)
{
    VALUE exc = rb_arity_error_new(miss_argc, min_argc, max_argc);
    if (iseq->body->param.flags.has_kw) {
 const struct rb_iseq_param_keyword *const kw = iseq->body->param.keyword;
 const ID *keywords = kw->table;
 int req_key_num = kw->required_num;
 if (req_key_num > 0) {
     static const char required[] = "; required keywords";
     VALUE mesg = rb_attr_get(exc, idMesg);
     rb_str_resize(mesg, RSTRING_LEN(mesg)-1);
     rb_str_cat(mesg, required, sizeof(required) - 1 - (req_key_num == 1));
     ((__builtin_constant_p(":") ? rbimpl_str_cat_cstr : rb_str_cat_cstr) ((mesg), (":")));
     do {
  ((__builtin_constant_p(" ") ? rbimpl_str_cat_cstr : rb_str_cat_cstr) ((mesg), (" ")));
  rb_str_append(mesg, rb_id2str(*keywords++));
  ((__builtin_constant_p(",") ? rbimpl_str_cat_cstr : rb_str_cat_cstr) ((mesg), (",")));
     } while (--req_key_num);
     RSTRING_PTR(mesg)[RSTRING_LEN(mesg)-1] = ')';
 }
    }
    raise_argument_error(ec, iseq, exc);
}
static void
argument_kw_error(rb_execution_context_t *ec, const rb_iseq_t *iseq, const char *error, const VALUE keys)
{
    raise_argument_error(ec, iseq, rb_keyword_error_new(error, keys));
}
static inline void
vm_caller_setup_arg_splat(rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    int argc = calling->argc;
    VALUE *argv = cfp->sp - argc;
    VALUE ary = argv[argc-1];
    ;
    cfp->sp--;
    if (!RB_NIL_P(ary)) {
        const VALUE *ptr = rb_array_const_ptr_transient(ary);
        long len = rb_array_len(ary), i;
        do { __extension__ _Static_assert(sizeof(*((cfp)->sp)) == sizeof(VALUE), "sizeof_sp" ": " "sizeof(*((cfp)->sp)) == sizeof(VALUE)"); __extension__ _Static_assert(sizeof(*((cfp))) == sizeof(rb_control_frame_t), "sizeof_cfp" ": " "sizeof(*((cfp))) == sizeof(rb_control_frame_t)"); const struct rb_control_frame_struct *bound = (void *)&((cfp)->sp)[((len))]; if ((__builtin_expect(!!(((cfp)) <= &bound[1]), 0))) { vm_stackoverflow(); } } while (0);
        for (i = 0; i < len; i++) {
            *cfp->sp++ = ptr[i];
        }
        calling->argc += i - 1;
    }
}
static inline void
vm_caller_setup_arg_kw(rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_callinfo *ci)
{
    const VALUE *const passed_keywords = vm_ci_kwarg(ci)->keywords;
    const int kw_len = vm_ci_kwarg(ci)->keyword_len;
    const VALUE h = rb_hash_new_with_size(kw_len);
    VALUE *sp = cfp->sp;
    int i;
    for (i=0; i<kw_len; i++) {
 rb_hash_aset(h, passed_keywords[i], (sp - kw_len)[i]);
    }
    (sp-kw_len)[0] = h;
    cfp->sp -= kw_len - 1;
    calling->argc -= kw_len - 1;
    calling->kw_splat = 1;
}
static VALUE
vm_to_proc(VALUE proc)
{
    if ((__builtin_expect(!!(!rb_obj_is_proc(proc)), 0))) {
 VALUE b;
 const rb_callable_method_entry_t *me =
     rb_callable_method_entry_with_refinements(rb_class_of(proc), idTo_proc, ((void *)0));
 if (me) {
            b = rb_vm_call0(rb_current_execution_context(1), proc, idTo_proc, 0, ((void *)0), me, 0);
 }
 else {
     b = rb_check_convert_type_with_id(proc, RUBY_T_DATA, "Proc", idTo_proc);
 }
 if (RB_NIL_P(b) || !rb_obj_is_proc(b)) {
     rb_raise(rb_eTypeError,
       "wrong argument type %s (expected Proc)",
       rb_obj_classname(proc));
 }
 return b;
    }
    else {
 return proc;
    }
}
static VALUE
refine_sym_proc_call(VALUE yielded_arg, VALUE callback_arg, int argc, const VALUE *argv, VALUE blockarg)
{
    VALUE obj;
    ID mid;
    const rb_callable_method_entry_t *me = 0;
    rb_execution_context_t *ec;
    const VALUE symbol = RARRAY_AREF(callback_arg, 0);
    const VALUE refinements = RARRAY_AREF(callback_arg, 1);
    int kw_splat = rb_keyword_given_p();
    VALUE klass;
    if (argc-- < 1) {
 rb_raise(rb_eArgError, "no receiver given");
    }
    obj = *argv++;
    mid = rb_sym2id(symbol);
    for (klass = rb_class_of(obj); klass; klass = RCLASS_SUPER(klass)) {
        me = rb_callable_method_entry(klass, mid);
        if (me) {
            me = rb_resolve_refined_method_callable(refinements, me);
            if (me) break;
        }
    }
    ec = rb_current_execution_context(1);
    if (!RB_NIL_P(blockarg)) {
 vm_passed_block_handler_set(ec, blockarg);
    }
    if (!me) {
        return method_missing(ec, obj, mid, argc, argv, MISSING_NOENTRY, kw_splat);
    }
    return rb_vm_call0(ec, obj, mid, argc, argv, me, kw_splat);
}
static VALUE
vm_caller_setup_arg_block(const rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
                          const struct rb_callinfo *ci, const rb_iseq_t *blockiseq, const int is_super)
{
    if (vm_ci_flag(ci) & (0x01 << VM_CALL_ARGS_BLOCKARG_bit)) {
 VALUE block_code = *(--reg_cfp->sp);
 if (RB_NIL_P(block_code)) {
            return 0;
        }
 else if (block_code == rb_block_param_proxy) {
            ((void)0);
            VALUE handler = VM_CF_BLOCK_HANDLER(reg_cfp);
            reg_cfp->block_code = (const void *) handler;
            return handler;
        }
 else if (RB_SYMBOL_P(block_code) && rb_method_basic_definition_p(rb_cSymbol, idTo_proc)) {
     const rb_cref_t *cref = vm_env_cref(reg_cfp->ep);
     if (cref && !RB_NIL_P(cref->refinements)) {
  VALUE ref = cref->refinements;
  VALUE func = rb_hash_lookup(ref, block_code);
  if (RB_NIL_P(func)) {
                    VALUE callback_arg = rb_ary_tmp_new(2);
                    rb_ary_push(callback_arg, block_code);
                    rb_ary_push(callback_arg, ref);
                    RB_OBJ_FREEZE_RAW(callback_arg);
                    func = rb_func_lambda_new(refine_sym_proc_call, callback_arg, 1, (-1));
      rb_hash_aset(ref, block_code, func);
  }
  block_code = func;
     }
            return block_code;
        }
        else {
            return vm_to_proc(block_code);
        }
    }
    else if (blockiseq != ((void *)0)) {
 struct rb_captured_block *captured = VM_CFP_TO_CAPTURED_BLOCK(reg_cfp);
 captured->code.iseq = blockiseq;
        return VM_BH_FROM_ISEQ_BLOCK(captured);
    }
    else {
 if (is_super) {
            return ((VM_EP_LEP(((((reg_cfp)->ep)))))[(-1)]);
        }
        else {
            return 0;
        }
    }
}
static inline VALUE vm_call_iseq_setup_2(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, int opt_pc, int param_size, int local_size);
__attribute__ ((__always_inline__)) static VALUE vm_call_iseq_setup_normal(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const rb_callable_method_entry_t *me, int opt_pc, int param_size, int local_size);
static inline VALUE vm_call_iseq_setup_tailcall(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, int opt_pc);
static VALUE vm_call_super_method(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling);
static VALUE vm_call_method_nome(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling);
static VALUE vm_call_method_each_type(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling);
static inline VALUE vm_call_method(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling);
static vm_call_handler vm_call_iseq_setup_func(const struct rb_callinfo *ci, const int param_size, const int local_size);
static VALUE
vm_call_iseq_setup_tailcall_0start(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_tailcall(ec, cfp, calling, 0);
}
static VALUE
vm_call_iseq_setup_normal_0start(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    const struct rb_callcache *cc = calling->cc;
    const rb_iseq_t *iseq = def_iseq_ptr(vm_cc_cme(cc)->def);
    int param = iseq->body->param.size;
    int local = iseq->body->local_table_size;
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(cc), 0, param, local);
}
static _Bool
rb_simple_iseq_p(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.has_opt == 0 &&
           iseq->body->param.flags.has_rest == 0 &&
    iseq->body->param.flags.has_post == 0 &&
    iseq->body->param.flags.has_kw == 0 &&
    iseq->body->param.flags.has_kwrest == 0 &&
           iseq->body->param.flags.accepts_no_kwarg == 0 &&
    iseq->body->param.flags.has_block == 0;
}static inline 
__attribute__ ((__visibility__("default")))  _Bool
rb_iseq_only_optparam_p(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.has_opt == 1 &&
           iseq->body->param.flags.has_rest == 0 &&
           iseq->body->param.flags.has_post == 0 &&
           iseq->body->param.flags.has_kw == 0 &&
           iseq->body->param.flags.has_kwrest == 0 &&
           iseq->body->param.flags.accepts_no_kwarg == 0 &&
           iseq->body->param.flags.has_block == 0;
}static inline 
__attribute__ ((__visibility__("default")))  _Bool
rb_iseq_only_kwparam_p(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.has_opt == 0 &&
           iseq->body->param.flags.has_rest == 0 &&
           iseq->body->param.flags.has_post == 0 &&
           iseq->body->param.flags.has_kw == 1 &&
           iseq->body->param.flags.has_kwrest == 0 &&
           iseq->body->param.flags.has_block == 0;
}
static _Bool
rb_splat_or_kwargs_p(const struct rb_callinfo *__restrict__ ci)
{
    return (vm_ci_flag(ci) & (0x01 << VM_CALL_ARGS_SPLAT_bit)) || (vm_ci_flag(ci) & ((0x01 << VM_CALL_KWARG_bit) | (0x01 << VM_CALL_KW_SPLAT_bit)));
}
static inline void
CALLER_SETUP_ARG(struct rb_control_frame_struct *__restrict__ cfp,
                 struct rb_calling_info *__restrict__ calling,
                 const struct rb_callinfo *__restrict__ ci)
{
    if ((__builtin_expect(!!((vm_ci_flag(ci) & (0x01 << VM_CALL_ARGS_SPLAT_bit))), 0))) {
        VALUE final_hash;
        vm_caller_setup_arg_splat(cfp, calling);
        if (!(vm_ci_flag(ci) & ((0x01 << VM_CALL_KWARG_bit) | (0x01 << VM_CALL_KW_SPLAT_bit))) &&
                calling->argc > 0 &&
                RB_TYPE_P((final_hash = *(cfp->sp - 1)), RUBY_T_HASH) &&
                (((struct RHash *)final_hash)->basic.flags & RHASH_PASS_AS_KEYWORDS)) {
            *(cfp->sp - 1) = rb_hash_dup(final_hash);
            calling->kw_splat = 1;
        }
    }
    if ((__builtin_expect(!!((vm_ci_flag(ci) & ((0x01 << VM_CALL_KWARG_bit) | (0x01 << VM_CALL_KW_SPLAT_bit)))), 0))) {
        if ((vm_ci_flag(ci) & (0x01 << VM_CALL_KWARG_bit))) {
            vm_caller_setup_arg_kw(cfp, calling, ci);
        }
        else {
            VALUE keyword_hash = cfp->sp[-1];
            if (!RB_TYPE_P(keyword_hash, RUBY_T_HASH)) {
                cfp->sp[-1] = rb_hash_dup(rb_to_hash_type(keyword_hash));
            }
            else if (!(vm_ci_flag(ci) & (0x01 << VM_CALL_KW_SPLAT_MUT_bit))) {
                cfp->sp[-1] = rb_hash_dup(keyword_hash);
            }
        }
    }
}
static inline void
CALLER_REMOVE_EMPTY_KW_SPLAT(struct rb_control_frame_struct *__restrict__ cfp,
                             struct rb_calling_info *__restrict__ calling,
                             const struct rb_callinfo *__restrict__ ci)
{
    if ((__builtin_expect(!!(calling->kw_splat), 0))) {
        if (RHASH_EMPTY_P(cfp->sp[-1])) {
            cfp->sp--;
            calling->argc--;
            calling->kw_splat = 0;
        }
    }
}
static VALUE
vm_call_iseq_setup_normal_opt_start(rb_execution_context_t *ec, rb_control_frame_t *cfp,
                                    struct rb_calling_info *calling)
{
    const struct rb_callcache *cc = calling->cc;
    const rb_iseq_t *iseq = def_iseq_ptr(vm_cc_cme(cc)->def);
    const int lead_num = iseq->body->param.lead_num;
    const int opt = calling->argc - lead_num;
    const int opt_num = iseq->body->param.opt_num;
    const int opt_pc = (int)iseq->body->param.opt_table[opt];
    const int param = iseq->body->param.size;
    const int local = iseq->body->local_table_size;
    const int delta = opt_num - opt;
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(cc), opt_pc, param - delta, local);
}
static VALUE
vm_call_iseq_setup_tailcall_opt_start(rb_execution_context_t *ec, rb_control_frame_t *cfp,
                                      struct rb_calling_info *calling)
{
    const struct rb_callcache *cc = calling->cc;
    const rb_iseq_t *iseq = def_iseq_ptr(vm_cc_cme(cc)->def);
    const int lead_num = iseq->body->param.lead_num;
    const int opt = calling->argc - lead_num;
    const int opt_pc = (int)iseq->body->param.opt_table[opt];
    ((void)0);
    return vm_call_iseq_setup_tailcall(ec, cfp, calling, opt_pc);
}
static void
args_setup_kw_parameters(rb_execution_context_t *const ec, const rb_iseq_t *const iseq,
                         VALUE *const passed_values, const int passed_keyword_len, const VALUE *const passed_keywords,
                         VALUE *const locals);
static VALUE
vm_call_iseq_setup_kwparm_kwarg(rb_execution_context_t *ec, rb_control_frame_t *cfp,
                                struct rb_calling_info *calling)
{
    const struct rb_callinfo *ci = calling->ci;
    const struct rb_callcache *cc = calling->cc;
    ((void)0);
    ((void)0);
    const rb_iseq_t *iseq = def_iseq_ptr(vm_cc_cme(cc)->def);
    const struct rb_iseq_param_keyword *kw_param = iseq->body->param.keyword;
    const struct rb_callinfo_kwarg *kw_arg = vm_ci_kwarg(ci);
    const int ci_kw_len = kw_arg->keyword_len;
    const VALUE * const ci_keywords = kw_arg->keywords;
    VALUE *argv = cfp->sp - calling->argc;
    VALUE *const klocals = argv + kw_param->bits_start - kw_param->num;
    const int lead_num = iseq->body->param.lead_num;
    VALUE * const ci_kws = ((VALUE *)__builtin_alloca (rbimpl_size_mul_or_raise(sizeof(VALUE), (ci_kw_len))));
    ruby_nonempty_memcpy((ci_kws), (argv + lead_num), rbimpl_size_mul_or_raise(sizeof(VALUE), (ci_kw_len)));
    args_setup_kw_parameters(ec, iseq, ci_kws, ci_kw_len, ci_keywords, klocals);
    int param = iseq->body->param.size;
    int local = iseq->body->local_table_size;
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(cc), 0, param, local);
}
static VALUE
vm_call_iseq_setup_kwparm_nokwarg(rb_execution_context_t *ec, rb_control_frame_t *cfp,
                                  struct rb_calling_info *calling)
{
    const struct rb_callinfo *__attribute__ ((__unused__)) ci = calling->ci;
    const struct rb_callcache *cc = calling->cc;
    ((void)0);
    ((void)0);
    const rb_iseq_t *iseq = def_iseq_ptr(vm_cc_cme(cc)->def);
    const struct rb_iseq_param_keyword *kw_param = iseq->body->param.keyword;
    VALUE * const argv = cfp->sp - calling->argc;
    VALUE * const klocals = argv + kw_param->bits_start - kw_param->num;
    int i;
    for (i=0; i<kw_param->num; i++) {
        klocals[i] = kw_param->default_values[i];
    }
    klocals[i] = __builtin_choose_expr( __builtin_constant_p(0), ((VALUE)(0)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(0));
    int param = iseq->body->param.size;
    int local = iseq->body->local_table_size;
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(cc), 0, param, local);
}
static inline int
vm_callee_setup_arg(rb_execution_context_t *ec, struct rb_calling_info *calling,
      const rb_iseq_t *iseq, VALUE *argv, int param_size, int local_size)
{
    const struct rb_callinfo *ci = calling->ci;
    const struct rb_callcache *cc = calling->cc;
    _Bool cacheable_ci = vm_ci_markable(ci);
    if ((__builtin_expect(!!(!(vm_ci_flag(ci) & (0x01 << VM_CALL_KW_SPLAT_bit))), 1))) {
        if ((__builtin_expect(!!(rb_simple_iseq_p(iseq)), 1))) {
            rb_control_frame_t *cfp = ec->cfp;
            CALLER_SETUP_ARG(cfp, calling, ci);
            CALLER_REMOVE_EMPTY_KW_SPLAT(cfp, calling, ci);
            if (calling->argc != iseq->body->param.lead_num) {
                argument_arity_error(ec, iseq, calling->argc, iseq->body->param.lead_num, iseq->body->param.lead_num);
            }
            ((void)0);
            ((void)0);
            CC_SET_FASTPATH(cc, vm_call_iseq_setup_func(ci, param_size, local_size), cacheable_ci && vm_call_iseq_optimizable_p(ci, cc));
            return 0;
        }
        else if (rb_iseq_only_optparam_p(iseq)) {
            rb_control_frame_t *cfp = ec->cfp;
            CALLER_SETUP_ARG(cfp, calling, ci);
            CALLER_REMOVE_EMPTY_KW_SPLAT(cfp, calling, ci);
            const int lead_num = iseq->body->param.lead_num;
            const int opt_num = iseq->body->param.opt_num;
            const int argc = calling->argc;
            const int opt = argc - lead_num;
            if (opt < 0 || opt > opt_num) {
                argument_arity_error(ec, iseq, argc, lead_num, lead_num + opt_num);
            }
            if ((__builtin_expect(!!(!(vm_ci_flag(ci) & (0x01 << VM_CALL_TAILCALL_bit))), 1))) {
                CC_SET_FASTPATH(cc, vm_call_iseq_setup_normal_opt_start,
                                !(vm_ci_flag(ci) & (0x01 << VM_CALL_ARGS_SPLAT_bit)) && !(vm_ci_flag(ci) & (0x01 << VM_CALL_KWARG_bit)) &&
                                cacheable_ci && !((rb_method_visibility_t)(((vm_cc_cme(cc))->flags & (((VALUE)RUBY_FL_USER4) | ((VALUE)RUBY_FL_USER5))) >> ((((VALUE)RUBY_FL_USHIFT) + 4)+0)) == METHOD_VISI_PROTECTED));
            }
            else {
                CC_SET_FASTPATH(cc, vm_call_iseq_setup_tailcall_opt_start,
                                !(vm_ci_flag(ci) & (0x01 << VM_CALL_ARGS_SPLAT_bit)) && !(vm_ci_flag(ci) & (0x01 << VM_CALL_KWARG_bit)) &&
                                cacheable_ci && !((rb_method_visibility_t)(((vm_cc_cme(cc))->flags & (((VALUE)RUBY_FL_USER4) | ((VALUE)RUBY_FL_USER5))) >> ((((VALUE)RUBY_FL_USHIFT) + 4)+0)) == METHOD_VISI_PROTECTED));
            }
            ((void)0);
            for (int i=argc; i<lead_num + opt_num; i++) {
                argv[i] = ((VALUE)RUBY_Qnil);
            }
            return (int)iseq->body->param.opt_table[opt];
        }
        else if (rb_iseq_only_kwparam_p(iseq) && !(vm_ci_flag(ci) & (0x01 << VM_CALL_ARGS_SPLAT_bit))) {
            const int lead_num = iseq->body->param.lead_num;
            const int argc = calling->argc;
            const struct rb_iseq_param_keyword *kw_param = iseq->body->param.keyword;
            if (vm_ci_flag(ci) & (0x01 << VM_CALL_KWARG_bit)) {
                const struct rb_callinfo_kwarg *kw_arg = vm_ci_kwarg(ci);
                if (argc - kw_arg->keyword_len == lead_num) {
                    const int ci_kw_len = kw_arg->keyword_len;
                    const VALUE * const ci_keywords = kw_arg->keywords;
                    VALUE * const ci_kws = ((VALUE *)__builtin_alloca (rbimpl_size_mul_or_raise(sizeof(VALUE), (ci_kw_len))));
                    ruby_nonempty_memcpy((ci_kws), (argv + lead_num), rbimpl_size_mul_or_raise(sizeof(VALUE), (ci_kw_len)));
                    VALUE *const klocals = argv + kw_param->bits_start - kw_param->num;
                    args_setup_kw_parameters(ec, iseq, ci_kws, ci_kw_len, ci_keywords, klocals);
                    CC_SET_FASTPATH(cc, vm_call_iseq_setup_kwparm_kwarg,
                                    cacheable_ci && !((rb_method_visibility_t)(((vm_cc_cme(cc))->flags & (((VALUE)RUBY_FL_USER4) | ((VALUE)RUBY_FL_USER5))) >> ((((VALUE)RUBY_FL_USHIFT) + 4)+0)) == METHOD_VISI_PROTECTED));
                    return 0;
                }
            }
            else if (argc == lead_num) {
                VALUE *const klocals = argv + kw_param->bits_start - kw_param->num;
                args_setup_kw_parameters(ec, iseq, ((void *)0), 0, ((void *)0), klocals);
                if (klocals[kw_param->num] == __builtin_choose_expr( __builtin_constant_p(0), ((VALUE)(0)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(0))) {
                    CC_SET_FASTPATH(cc, vm_call_iseq_setup_kwparm_nokwarg,
                                    cacheable_ci && !((rb_method_visibility_t)(((vm_cc_cme(cc))->flags & (((VALUE)RUBY_FL_USER4) | ((VALUE)RUBY_FL_USER5))) >> ((((VALUE)RUBY_FL_USHIFT) + 4)+0)) == METHOD_VISI_PROTECTED));
                }
                return 0;
            }
        }
    }
    return setup_parameters_complex(ec, iseq, calling, ci, argv, arg_setup_method);
}
COLDFUNC static VALUE
vm_call_iseq_setup(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling) {
    ((void)0);
    const struct rb_callcache *cc = calling->cc;
    const rb_iseq_t *iseq = def_iseq_ptr(vm_cc_cme(cc)->def);
    const int param_size = iseq->body->param.size;
    const int local_size = iseq->body->local_table_size;
    const int opt_pc = vm_callee_setup_arg(ec, calling, def_iseq_ptr(vm_cc_cme(cc)->def), cfp->sp - calling->argc, param_size, local_size);
    return vm_call_iseq_setup_2(ec, cfp, calling, opt_pc, param_size, local_size);
}
COLDFUNC static VALUE
vm_call_iseq_setup_2(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling,
                     int opt_pc, int param_size, int local_size) {
    const struct rb_callinfo *ci = calling->ci;
    const struct rb_callcache *cc = calling->cc;
    if ((__builtin_expect(!!(!(vm_ci_flag(ci) & (0x01 << VM_CALL_TAILCALL_bit))), 1))) {
        return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(cc), opt_pc, param_size, local_size);
    }
    else {
        return vm_call_iseq_setup_tailcall(ec, cfp, calling, opt_pc);
    }
}
static inline VALUE
vm_call_iseq_setup_normal(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const rb_callable_method_entry_t *me,
                          int opt_pc, int param_size, int local_size)
{
    const rb_iseq_t *iseq = def_iseq_ptr(me->def);
    VALUE *argv = cfp->sp - calling->argc;
    VALUE *sp = argv + param_size;
    cfp->sp = argv - 1 ;
    vm_push_frame(ec, iseq, VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL, calling->recv,
                  calling->block_handler, (VALUE)me,
                  iseq->body->iseq_encoded + opt_pc, sp,
                  local_size - param_size,
                  iseq->body->stack_max);
    return ((VALUE)RUBY_Qundef);
}
COLDFUNC static VALUE
vm_call_iseq_setup_tailcall(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, int opt_pc) {
    const struct rb_callcache *cc = calling->cc;
    unsigned int i;
    VALUE *argv = cfp->sp - calling->argc;
    const rb_callable_method_entry_t *me = vm_cc_cme(cc);
    const rb_iseq_t *iseq = def_iseq_ptr(me->def);
    VALUE *src_argv = argv;
    VALUE *sp_orig, *sp;
    VALUE finish_flag = VM_FRAME_FINISHED_P(cfp) ? VM_FRAME_FLAG_FINISH : 0;
    if (VM_BH_FROM_CFP_P(calling->block_handler, cfp)) {
 struct rb_captured_block *dst_captured = VM_CFP_TO_CAPTURED_BLOCK(((cfp)+1));
 const struct rb_captured_block *src_captured = VM_BH_TO_CAPT_BLOCK(calling->block_handler);
 dst_captured->code.val = src_captured->code.val;
 if (VM_BH_ISEQ_BLOCK_P(calling->block_handler)) {
     calling->block_handler = VM_BH_FROM_ISEQ_BLOCK(dst_captured);
 }
 else {
     calling->block_handler = VM_BH_FROM_IFUNC_BLOCK(dst_captured);
 }
    }
    vm_pop_frame(ec, cfp, cfp->ep);
    cfp = ec->cfp;
    sp_orig = sp = cfp->sp;
    sp[0] = calling->recv;
    sp++;
    for (i=0; i < iseq->body->param.size; i++) {
 *sp++ = src_argv[i];
    }
    vm_push_frame(ec, iseq, VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL | finish_flag,
    calling->recv, calling->block_handler, (VALUE)me,
    iseq->body->iseq_encoded + opt_pc, sp,
    iseq->body->local_table_size - iseq->body->param.size,
    iseq->body->stack_max);
    cfp->sp = sp_orig;
    return ((VALUE)RUBY_Qundef);
}
static void
ractor_unsafe_check(void)
{
    if (!rb_ractor_main_p()) {
        rb_raise(rb_eRactorUnsafeError, "ractor unsafe method called from not main ractor");
    }
}
static VALUE
call_cfunc_m2(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    return (*func)(recv, rb_ary_new_from_values(argc, argv));
}
static VALUE
call_cfunc_m1(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    return (*func)(argc, argv, recv);
}
static VALUE
call_cfunc_0(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE) = (VALUE(*)(VALUE))func;
    return (*f)(recv);
}
static VALUE
call_cfunc_1(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE) = (VALUE(*)(VALUE, VALUE))func;
    return (*f)(recv, argv[0]);
}
static VALUE
call_cfunc_2(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1]);
}
static VALUE
call_cfunc_3(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2]);
}
static VALUE
call_cfunc_4(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3]);
}
static VALUE
call_cfunc_5(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4]);
}
static VALUE
call_cfunc_6(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}
static VALUE
call_cfunc_7(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]);
}
static VALUE
call_cfunc_8(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7]);
}
static VALUE
call_cfunc_9(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8]);
}
static VALUE
call_cfunc_10(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9]);
}
static VALUE
call_cfunc_11(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10]);
}
static VALUE
call_cfunc_12(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11]);
}
static VALUE
call_cfunc_13(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12]);
}
static VALUE
call_cfunc_14(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12], argv[13]);
}
static VALUE
call_cfunc_15(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12], argv[13], argv[14]);
}
static VALUE
ractor_safe_call_cfunc_m2(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    return (*func)(recv, rb_ary_new_from_values(argc, argv));
}
static VALUE
ractor_safe_call_cfunc_m1(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    return (*func)(argc, argv, recv);
}
static VALUE
ractor_safe_call_cfunc_0(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    VALUE(*f)(VALUE) = (VALUE(*)(VALUE))func;
    return (*f)(recv);
}
static VALUE
ractor_safe_call_cfunc_1(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    VALUE(*f)(VALUE, VALUE) = (VALUE(*)(VALUE, VALUE))func;
    return (*f)(recv, argv[0]);
}
static VALUE
ractor_safe_call_cfunc_2(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    VALUE(*f)(VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1]);
}
static VALUE
ractor_safe_call_cfunc_3(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2]);
}
static VALUE
ractor_safe_call_cfunc_4(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3]);
}
static VALUE
ractor_safe_call_cfunc_5(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4]);
}
static VALUE
ractor_safe_call_cfunc_6(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}
static VALUE
ractor_safe_call_cfunc_7(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]);
}
static VALUE
ractor_safe_call_cfunc_8(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7]);
}
static VALUE
ractor_safe_call_cfunc_9(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8]);
}
static VALUE
ractor_safe_call_cfunc_10(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9]);
}
static VALUE
ractor_safe_call_cfunc_11(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10]);
}
static VALUE
ractor_safe_call_cfunc_12(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11]);
}
static VALUE
ractor_safe_call_cfunc_13(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12]);
}
static VALUE
ractor_safe_call_cfunc_14(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12], argv[13]);
}
static VALUE
ractor_safe_call_cfunc_15(VALUE recv, int argc, const VALUE *argv, VALUE (*func)())
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12], argv[13], argv[14]);
}
static inline int
vm_cfp_consistent_p(rb_execution_context_t *ec, const rb_control_frame_t *reg_cfp)
{
    const int ov_flags = RAISED_STACKOVERFLOW;
    if ((__builtin_expect(!!(reg_cfp == ec->cfp + 1), 1))) return 1;
    if ((((ec)->raised_flag & (ov_flags)) != 0)) {
 ((ec)->raised_flag &= ~(ov_flags));
 return 1;
    }
    return 0;
}
static inline
const rb_method_cfunc_t *
vm_method_cfunc_entry(const rb_callable_method_entry_t *me)
{
    return __extension__({
   ;
   ; __typeof__(&(me->def)->body.cfunc) unaligned_member_access_result = (&(me->def)->body.cfunc);
   ; unaligned_member_access_result; });
}
static VALUE
vm_call_cfunc_with_frame(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    ((void)0);
    const struct rb_callinfo *ci = calling->ci;
    const struct rb_callcache *cc = calling->cc;
    VALUE val;
    const rb_callable_method_entry_t *me = vm_cc_cme(cc);
    const rb_method_cfunc_t *cfunc = vm_method_cfunc_entry(me);
    int len = cfunc->argc;
    VALUE recv = calling->recv;
    VALUE block_handler = calling->block_handler;
    VALUE frame_type = VM_FRAME_MAGIC_CFUNC | VM_FRAME_FLAG_CFRAME | VM_ENV_FLAG_LOCAL;
    int argc = calling->argc;
    int orig_argc = argc;
    if ((__builtin_expect(!!(calling->kw_splat), 0))) {
        frame_type |= VM_FRAME_FLAG_CFRAME_KW;
    }
    do { if ((__builtin_expect(!!(0), 0))) { struct ruby_dtrace_method_hook_args args; if (rb_dtrace_setup(ec, me->owner, me->def->original_id, &args)) { do {} while (0); } } } while (0);
    do { const rb_event_flag_t flag_arg_ = (0x0020); rb_hook_list_t *hooks_arg_ = (rb_ec_ractor_hooks(ec)); if ((__builtin_expect(!!((hooks_arg_)->events & (flag_arg_)), 0))) { rb_exec_event_hook_orig(ec, hooks_arg_, flag_arg_, recv, me->def->original_id, vm_ci_mid(ci), me->owner, ((VALUE)RUBY_Qundef), 0); } } while (0);
    vm_push_frame(ec, ((void *)0), frame_type, recv,
    block_handler, (VALUE)me,
    0, ec->cfp->sp, 0, 0);
    if (len >= 0) rb_check_arity(argc, len, len);
    reg_cfp->sp -= orig_argc + 1;
    val = (*cfunc->invoker)(recv, argc, reg_cfp->sp + 1, cfunc->func);
    ((__builtin_expect(!!(vm_cfp_consistent_p(ec, reg_cfp)), 1)) ? (void)0 : rb_bug("vm_call_cfunc" ": cfp consistency error (%p, %p)", (void *)reg_cfp, (void *)(ec->cfp+1)));
    rb_vm_pop_frame(ec);
    do { const rb_event_flag_t flag_arg_ = (0x0040); rb_hook_list_t *hooks_arg_ = (rb_ec_ractor_hooks(ec)); if ((__builtin_expect(!!((hooks_arg_)->events & (flag_arg_)), 0))) { rb_exec_event_hook_orig(ec, hooks_arg_, flag_arg_, recv, me->def->original_id, vm_ci_mid(ci), me->owner, val, 0); } } while (0);
    do { if ((__builtin_expect(!!(0), 0))) { struct ruby_dtrace_method_hook_args args; if (rb_dtrace_setup(ec, me->owner, me->def->original_id, &args)) { do {} while (0); } } } while (0);
    return val;
}
static VALUE
vm_call_cfunc(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    const struct rb_callinfo *ci = calling->ci;
    ((void)0);
    CALLER_SETUP_ARG(reg_cfp, calling, ci);
    CALLER_REMOVE_EMPTY_KW_SPLAT(reg_cfp, calling, ci);
    CC_SET_FASTPATH(calling->cc, vm_call_cfunc_with_frame, !rb_splat_or_kwargs_p(ci) && !calling->kw_splat);
    return vm_call_cfunc_with_frame(ec, reg_cfp, calling);
}
static VALUE
vm_call_ivar(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    const struct rb_callcache *cc = calling->cc;
    ((void)0);
    cfp->sp -= 1;
    return vm_getivar(calling->recv, vm_cc_cme(cc)->def->body.attr.id, ((void *)0), ((void *)0), cc, 1);
}
static VALUE
vm_call_attrset(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    const struct rb_callcache *cc = calling->cc;
    ((void)0);
    VALUE val = *(cfp->sp - 1);
    cfp->sp -= 2;
    return vm_setivar(calling->recv, vm_cc_cme(cc)->def->body.attr.id, val, ((void *)0), ((void *)0), cc, 1);
}static inline 
_Bool
rb_vm_call_ivar_attrset_p(const vm_call_handler ch)
{
    return (ch == vm_call_ivar || ch == vm_call_attrset);
}
static inline VALUE
vm_call_bmethod_body(rb_execution_context_t *ec, struct rb_calling_info *calling, const VALUE *argv)
{
    rb_proc_t *proc;
    VALUE val;
    const struct rb_callcache *cc = calling->cc;
    const rb_callable_method_entry_t *cme = vm_cc_cme(cc);
    VALUE procv = cme->def->body.bmethod.proc;
    if (!RB_FL_TEST_RAW((procv), RUBY_FL_SHAREABLE) &&
        cme->def->body.bmethod.defined_ractor != rb_ractor_self(rb_ec_ractor_ptr(ec))) {
        rb_raise(rb_eRuntimeError, "defined with an un-shareable Proc in a different Ractor");
    }
    (((proc)) = (rb_proc_t*)((struct RData *)(((procv))))->data);
    val = rb_vm_invoke_bmethod(ec, proc, calling->recv, calling->argc, argv, calling->kw_splat, calling->block_handler, vm_cc_cme(cc));
    return val;
}
static VALUE
vm_call_bmethod(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    VALUE *argv;
    int argc;
    const struct rb_callinfo *ci = calling->ci;
    CALLER_SETUP_ARG(cfp, calling, ci);
    argc = calling->argc;
    argv = ((VALUE *)__builtin_alloca (rbimpl_size_mul_or_raise(sizeof(VALUE), (argc))));
    ruby_nonempty_memcpy((argv), (cfp->sp - argc), rbimpl_size_mul_or_raise(sizeof(VALUE), (argc)));
    cfp->sp += - argc - 1;
    return vm_call_bmethod_body(ec, calling, argv);
}static inline 
__attribute__ ((__visibility__("default")))  VALUE
rb_find_defined_class_by_owner(VALUE current_class, VALUE target_owner)
{
    VALUE klass = current_class;
    if (RB_TYPE_P(klass, RUBY_T_ICLASS) && RB_FL_TEST(klass, ((VALUE)RUBY_FL_USER5)) &&
            RB_TYPE_P(RBASIC_CLASS(klass), RUBY_T_CLASS)) {
        klass = RBASIC_CLASS(klass);
    }
    while (RB_TEST(klass)) {
 VALUE owner = RB_TYPE_P(klass, RUBY_T_ICLASS) ? RBASIC_CLASS(klass) : klass;
 if (owner == target_owner) {
     return klass;
 }
 klass = RCLASS_SUPER(klass);
    }
    return current_class;
}
static const rb_callable_method_entry_t *
aliased_callable_method_entry(const rb_callable_method_entry_t *me)
{
    const rb_method_entry_t *orig_me = me->def->body.alias.original_me;
    const rb_callable_method_entry_t *cme;
    if (orig_me->defined_class == 0) {
        VALUE defined_class = rb_find_defined_class_by_owner(me->defined_class, orig_me->owner);
 ((void)0);
 cme = rb_method_entry_complement_defined_class(orig_me, me->called_id, defined_class);
 if (me->def->alias_count + me->def->complemented_count == 0) {
     rb_obj_write((VALUE)(me), __extension__({
    ;
    ; __typeof__((VALUE *)(&me->def->body.alias.original_me)) unaligned_member_access_result = ((VALUE *)(&me->def->body.alias.original_me));
    ; unaligned_member_access_result; }), (VALUE)(cme), "./vm_insnhelper.c", 3159);
 }
 else {
     rb_method_definition_t *def =
  rb_method_definition_create(VM_METHOD_TYPE_ALIAS, me->def->original_id);
     rb_method_definition_set((rb_method_entry_t *)me, def, (void *)cme);
 }
    }
    else {
 cme = (const rb_callable_method_entry_t *)orig_me;
    }
    ((void)0);
    return cme;
}static inline 
const rb_callable_method_entry_t *
rb_aliased_callable_method_entry(const rb_callable_method_entry_t *me)
{
    return aliased_callable_method_entry(me);
}
static VALUE
vm_call_alias(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    calling->cc = &(struct rb_callcache) { .flags = RUBY_T_IMEMO | (imemo_callcache << ((VALUE)RUBY_FL_USHIFT)) | ((VALUE)RUBY_FL_USER4) | ((VALUE)RUBY_FL_USER5), .klass = ((VALUE)RUBY_Qundef), .cme_ = aliased_callable_method_entry(vm_cc_cme(calling->cc)), .call_ = vm_call_general, .aux_ = { 0 }, };
    return vm_call_method_each_type(ec, cfp, calling);
}
static enum method_missing_reason
ci_missing_reason(const struct rb_callinfo *ci)
{
    enum method_missing_reason stat = MISSING_NOENTRY;
    if (vm_ci_flag(ci) & (0x01 << VM_CALL_VCALL_bit)) stat |= MISSING_VCALL;
    if (vm_ci_flag(ci) & (0x01 << VM_CALL_FCALL_bit)) stat |= MISSING_FCALL;
    if (vm_ci_flag(ci) & (0x01 << VM_CALL_SUPER_bit)) stat |= MISSING_SUPER;
    return stat;
}
static VALUE
vm_call_symbol(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
               struct rb_calling_info *calling, const struct rb_callinfo *ci, VALUE symbol)
{
    ((__builtin_expect(!!(!!(calling->argc >= 0)), 1)) ? ((void)0) : __builtin_unreachable());
    enum method_missing_reason missing_reason = MISSING_NOENTRY;
    int argc = calling->argc;
    VALUE recv = calling->recv;
    VALUE klass = rb_class_of(recv);
    ID mid = rb_check_id(&symbol);
    int flags = (0x01 << VM_CALL_FCALL_bit) |
                (0x01 << VM_CALL_OPT_SEND_bit) |
                (calling->kw_splat ? (0x01 << VM_CALL_KW_SPLAT_bit) : 0);
    if ((__builtin_expect(!!(! mid), 0))) {
        mid = idMethodMissing;
        missing_reason = ci_missing_reason(ci);
        ec->method_missing_reason = missing_reason;
        int i = argc;
        do { __extension__ _Static_assert(sizeof(*((reg_cfp)->sp)) == sizeof(VALUE), "sizeof_sp" ": " "sizeof(*((reg_cfp)->sp)) == sizeof(VALUE)"); __extension__ _Static_assert(sizeof(*((reg_cfp))) == sizeof(rb_control_frame_t), "sizeof_cfp" ": " "sizeof(*((reg_cfp))) == sizeof(rb_control_frame_t)"); const struct rb_control_frame_struct *bound = (void *)&((reg_cfp)->sp)[((1))]; if ((__builtin_expect(!!(((reg_cfp)) <= &bound[1]), 0))) { vm_stackoverflow(); } } while (0);
        (((reg_cfp)->sp) += (((1))));
        memmove((&(*(((((reg_cfp)->sp)))-(i - 1)-1))), (&(*(((((reg_cfp)->sp)))-(i)-1))), rbimpl_size_mul_or_raise(sizeof(VALUE), (i)));
        argc = ++calling->argc;
        if (rb_method_basic_definition_p(klass, idMethodMissing)) {
            (*(((((reg_cfp)->sp)))-(i)-1)) = symbol;
            int priv = vm_ci_flag(ci) & ((0x01 << VM_CALL_FCALL_bit) | (0x01 << VM_CALL_VCALL_bit));
            const VALUE *argv = (((((reg_cfp)->sp)))-(argc));
            VALUE exc = rb_make_no_method_exception(
                rb_eNoMethodError, 0, recv, argc, argv, priv);
            rb_exc_raise(exc);
        }
        else {
            (*(((((reg_cfp)->sp)))-(i)-1)) = rb_str_intern(symbol);
        }
    }
    calling->ci = &(struct rb_callinfo) { .flags = RUBY_T_IMEMO | (imemo_callinfo << ((VALUE)RUBY_FL_USHIFT)) | ((VALUE)RUBY_FL_USER4), .mid = mid, .flag = flags, .argc = argc, .kwarg = vm_ci_kwarg(ci), };
    calling->cc = &(struct rb_callcache) { .flags = RUBY_T_IMEMO | (imemo_callcache << ((VALUE)RUBY_FL_USHIFT)) | ((VALUE)RUBY_FL_USER4) | ((VALUE)RUBY_FL_USER5), .klass = klass, .cme_ = rb_callable_method_entry_with_refinements(klass, mid, ((void *)0)), .call_ = vm_call_general, .aux_ = { .method_missing_reason = missing_reason }, };
    return vm_call_method(ec, reg_cfp, calling);
}
static VALUE
vm_call_opt_send(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    ((void)0);
    int i;
    VALUE sym;
    CALLER_SETUP_ARG(reg_cfp, calling, calling->ci);
    i = calling->argc - 1;
    if (calling->argc == 0) {
 rb_raise(rb_eArgError, "no method name given");
    }
    else {
        sym = (*(((((reg_cfp)->sp)))-(i)-1));
 if (i > 0) {
     memmove((&(*(((((reg_cfp)->sp)))-(i)-1))), (&(*(((((reg_cfp)->sp)))-(i-1)-1))), rbimpl_size_mul_or_raise(sizeof(VALUE), (i)));
 }
 calling->argc -= 1;
 (((reg_cfp)->sp) -= (((1))));
        return vm_call_symbol(ec, reg_cfp, calling, calling->ci, sym);
    }
}
static VALUE
vm_call_method_missing_body(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling,
                            const struct rb_callinfo *orig_ci, enum method_missing_reason reason)
{
    ((void)0);
    VALUE *argv = (((((reg_cfp)->sp)))-(calling->argc));
    unsigned int argc;
    CALLER_SETUP_ARG(reg_cfp, calling, orig_ci);
    argc = calling->argc + 1;
    unsigned int flag = (0x01 << VM_CALL_FCALL_bit) | (0x01 << VM_CALL_OPT_SEND_bit) | (calling->kw_splat ? (0x01 << VM_CALL_KW_SPLAT_bit) : 0);
    calling->argc = argc;
    do { __extension__ _Static_assert(sizeof(*((reg_cfp)->sp)) == sizeof(VALUE), "sizeof_sp" ": " "sizeof(*((reg_cfp)->sp)) == sizeof(VALUE)"); __extension__ _Static_assert(sizeof(*((reg_cfp))) == sizeof(rb_control_frame_t), "sizeof_cfp" ": " "sizeof(*((reg_cfp))) == sizeof(rb_control_frame_t)"); const struct rb_control_frame_struct *bound = (void *)&((reg_cfp)->sp)[((1))]; if ((__builtin_expect(!!(((reg_cfp)) <= &bound[1]), 0))) { vm_stackoverflow(); } } while (0);
    ;
    if (argc > 1) {
 memmove((argv+1), (argv), rbimpl_size_mul_or_raise(sizeof(VALUE), (argc-1)));
    }
    argv[0] = rb_id2sym(vm_ci_mid(orig_ci));
    (((reg_cfp)->sp) += (((1))));
    ec->method_missing_reason = reason;
    calling->ci = &(struct rb_callinfo) { .flags = RUBY_T_IMEMO | (imemo_callinfo << ((VALUE)RUBY_FL_USHIFT)) | ((VALUE)RUBY_FL_USER4), .mid = idMethodMissing, .flag = flag, .argc = argc, .kwarg = vm_ci_kwarg(orig_ci), };
    calling->cc = &(struct rb_callcache) { .flags = RUBY_T_IMEMO | (imemo_callcache << ((VALUE)RUBY_FL_USHIFT)) | ((VALUE)RUBY_FL_USER4) | ((VALUE)RUBY_FL_USER5), .klass = ((VALUE)RUBY_Qundef), .cme_ = rb_callable_method_entry_without_refinements(rb_class_of(calling->recv), idMethodMissing, ((void *)0)), .call_ = vm_call_general, .aux_ = { 0 }, };
    return vm_call_method(ec, reg_cfp, calling);
}
static VALUE
vm_call_method_missing(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    return vm_call_method_missing_body(ec, reg_cfp, calling, calling->ci, vm_cc_cmethod_missing_reason(calling->cc));
}
static const rb_callable_method_entry_t *refined_method_callable_without_refinement(const rb_callable_method_entry_t *me);
static VALUE
vm_call_zsuper(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, VALUE klass)
{
    klass = RCLASS_SUPER(klass);
    const rb_callable_method_entry_t *cme = klass ? rb_callable_method_entry(klass, vm_ci_mid(calling->ci)) : ((void *)0);
    if (cme == ((void *)0)) {
        return vm_call_method_nome(ec, cfp, calling);
    }
    if (cme->def->type == VM_METHOD_TYPE_REFINED &&
        cme->def->body.refined.orig_me) {
        cme = refined_method_callable_without_refinement(cme);
    }
    calling->cc = &(struct rb_callcache) { .flags = RUBY_T_IMEMO | (imemo_callcache << ((VALUE)RUBY_FL_USHIFT)) | ((VALUE)RUBY_FL_USER4) | ((VALUE)RUBY_FL_USER5), .klass = ((VALUE)RUBY_Qundef), .cme_ = cme, .call_ = vm_call_general, .aux_ = { 0 }, };
    return vm_call_method_each_type(ec, cfp, calling);
}
static inline VALUE
find_refinement(VALUE refinements, VALUE klass)
{
    if (RB_NIL_P(refinements)) {
 return ((VALUE)RUBY_Qnil);
    }
    return rb_hash_lookup(refinements, klass);
}
__attribute__((__pure__)) static rb_control_frame_t * current_method_entry(const rb_execution_context_t *ec, rb_control_frame_t *cfp);
static rb_control_frame_t *
current_method_entry(const rb_execution_context_t *ec, rb_control_frame_t *cfp)
{
    rb_control_frame_t *top_cfp = cfp;
    if (cfp->iseq && cfp->iseq->body->type == ISEQ_TYPE_BLOCK) {
 const rb_iseq_t *local_iseq = cfp->iseq->body->local_iseq;
 do {
     cfp = ((cfp)+1);
     if (RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(ec, cfp)) {
  return top_cfp;
     }
 } while (cfp->iseq != local_iseq);
    }
    return cfp;
}
static const rb_callable_method_entry_t *
refined_method_callable_without_refinement(const rb_callable_method_entry_t *me)
{
    const rb_method_entry_t *orig_me = me->def->body.refined.orig_me;
    const rb_callable_method_entry_t *cme;
    if (orig_me->defined_class == 0) {
 cme = ((void *)0);
 rb_notimplement();
    }
    else {
 cme = (const rb_callable_method_entry_t *)orig_me;
    }
    ((void)0);
    if ((!(cme) || !(cme)->def || (cme)->def->type == VM_METHOD_TYPE_UNDEF)) {
 cme = ((void *)0);
    }
    return cme;
}
static const rb_callable_method_entry_t *
search_refined_method(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ID mid = vm_ci_mid(calling->ci);
    const rb_cref_t *cref = vm_get_cref(cfp->ep);
    const struct rb_callcache * const cc = calling->cc;
    const rb_callable_method_entry_t *cme = vm_cc_cme(cc);
    for (; cref; cref = CREF_NEXT(cref)) {
        const VALUE refinement = find_refinement(CREF_REFINEMENTS(cref), vm_cc_cme(cc)->owner);
        if (RB_NIL_P(refinement)) continue;
        const rb_callable_method_entry_t *const ref_me =
            rb_callable_method_entry(refinement, mid);
        if (ref_me) {
            if (vm_cc_call(cc) == vm_call_super_method) {
                const rb_control_frame_t *top_cfp = current_method_entry(ec, cfp);
                const rb_callable_method_entry_t *top_me = rb_vm_frame_method_entry(top_cfp);
                if (top_me && rb_method_definition_eq(ref_me->def, top_me->def)) {
                    continue;
                }
            }
            if (cme->def->type != VM_METHOD_TYPE_REFINED ||
                cme->def != ref_me->def) {
                cme = ref_me;
            }
            if (ref_me->def->type != VM_METHOD_TYPE_REFINED) {
                return cme;
            }
        }
        else {
            return ((void *)0);
        }
    }
    if (vm_cc_cme(cc)->def->body.refined.orig_me) {
        return refined_method_callable_without_refinement(vm_cc_cme(cc));
    }
    else {
        VALUE klass = RCLASS_SUPER(vm_cc_cme(cc)->defined_class);
        const rb_callable_method_entry_t *cme = klass ? rb_callable_method_entry(klass, mid) : ((void *)0);
        return cme;
    }
}
static VALUE
vm_call_refined(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    struct rb_callcache *ref_cc = &(struct rb_callcache) { .flags = RUBY_T_IMEMO | (imemo_callcache << ((VALUE)RUBY_FL_USHIFT)) | ((VALUE)RUBY_FL_USER4) | ((VALUE)RUBY_FL_USER5), .klass = ((VALUE)RUBY_Qundef), .cme_ = search_refined_method(ec, cfp, calling), .call_ = vm_call_general, .aux_ = { 0 }, };
    if (vm_cc_cme(ref_cc)) {
        calling->cc= ref_cc;
        return vm_call_method(ec, cfp, calling);
    }
    else {
        return vm_call_method_nome(ec, cfp, calling);
    }
}
static inline VALUE vm_invoke_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_callinfo *ci, _Bool is_lambda, VALUE block_handler);
__attribute__((__noinline__)) static VALUE vm_invoke_block_opt_call(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_callinfo *ci, VALUE block_handler);
static VALUE
vm_invoke_block_opt_call(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
    struct rb_calling_info *calling, const struct rb_callinfo *ci, VALUE block_handler)
{
    int argc = calling->argc;
    if (argc > 0) memmove((&(*(((((reg_cfp)->sp)))-(argc)-1))), (&(*(((((reg_cfp)->sp)))-(argc-1)-1))), rbimpl_size_mul_or_raise(sizeof(VALUE), (argc)));
    (((reg_cfp)->sp) -= (((1))));
    return vm_invoke_block(ec, reg_cfp, calling, ci, 0, block_handler);
}
static VALUE
vm_call_opt_call(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    ((void)0);
    const struct rb_callinfo *ci = calling->ci;
    VALUE procval = calling->recv;
    return vm_invoke_block_opt_call(ec, reg_cfp, calling, ci, VM_BH_FROM_PROC(procval));
}
static VALUE
vm_call_opt_block_call(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    ((void)0);
    VALUE block_handler = VM_ENV_BLOCK_HANDLER(VM_CF_LEP(reg_cfp));
    const struct rb_callinfo *ci = calling->ci;
    if (((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_CALL)]&((1 << 12))) == 0), 1)))) {
 return vm_invoke_block_opt_call(ec, reg_cfp, calling, ci, block_handler);
    }
    else {
 calling->recv = rb_vm_bh_to_procval(ec, block_handler);
        calling->cc = rb_vm_search_method_slowpath(ci, rb_class_of(calling->recv));
        return vm_call_general(ec, reg_cfp, calling);
    }
}
static VALUE
vm_call_opt_struct_aref0(rb_execution_context_t *ec, struct rb_calling_info *calling)
{
    VALUE recv = calling->recv;
    ((void)0);
    ((void)0);
    ((void)0);
    const unsigned int off = vm_cc_cme(calling->cc)->def->body.optimized.index;
    return internal_RSTRUCT_GET(recv, off);
}
static VALUE
vm_call_opt_struct_aref(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    ((void)0);
    VALUE ret = vm_call_opt_struct_aref0(ec, calling);
    reg_cfp->sp -= 1;
    return ret;
}
static VALUE
vm_call_opt_struct_aset0(rb_execution_context_t *ec, struct rb_calling_info *calling, VALUE val)
{
    VALUE recv = calling->recv;
    ((void)0);
    ((void)0);
    ((void)0);
    rb_check_frozen_inline(recv);
    const unsigned int off = vm_cc_cme(calling->cc)->def->body.optimized.index;
    internal_RSTRUCT_SET(recv, off, val);
    return val;
}
static VALUE
vm_call_opt_struct_aset(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    ((void)0);
    VALUE ret = vm_call_opt_struct_aset0(ec, calling, *(reg_cfp->sp - 1));
    reg_cfp->sp -= 2;
    return ret;
}
__attribute__((__noinline__)) static VALUE vm_call_optimized(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_callinfo *ci, const struct rb_callcache *cc);
static VALUE
vm_call_optimized(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling,
                  const struct rb_callinfo *ci, const struct rb_callcache *cc)
{
    switch (vm_cc_cme(cc)->def->body.optimized.type) {
      case OPTIMIZED_METHOD_TYPE_SEND:
        CC_SET_FASTPATH(cc, vm_call_opt_send, 1);
        return vm_call_opt_send(ec, cfp, calling);
      case OPTIMIZED_METHOD_TYPE_CALL:
        CC_SET_FASTPATH(cc, vm_call_opt_call, 1);
        return vm_call_opt_call(ec, cfp, calling);
      case OPTIMIZED_METHOD_TYPE_BLOCK_CALL:
        CC_SET_FASTPATH(cc, vm_call_opt_block_call, 1);
        return vm_call_opt_block_call(ec, cfp, calling);
      case OPTIMIZED_METHOD_TYPE_STRUCT_AREF:
        CALLER_SETUP_ARG(cfp, calling, ci);
        CALLER_REMOVE_EMPTY_KW_SPLAT(cfp, calling, ci);
        rb_check_arity(calling->argc, 0, 0);
        CC_SET_FASTPATH(cc, vm_call_opt_struct_aref, (vm_ci_flag(ci) & (0x01 << VM_CALL_ARGS_SIMPLE_bit)));
        return vm_call_opt_struct_aref(ec, cfp, calling);
      case OPTIMIZED_METHOD_TYPE_STRUCT_ASET:
        CALLER_SETUP_ARG(cfp, calling, ci);
        CALLER_REMOVE_EMPTY_KW_SPLAT(cfp, calling, ci);
        rb_check_arity(calling->argc, 1, 1);
        CC_SET_FASTPATH(cc, vm_call_opt_struct_aset, (vm_ci_flag(ci) & (0x01 << VM_CALL_ARGS_SIMPLE_bit)));
        return vm_call_opt_struct_aset(ec, cfp, calling);
      default:
        rb_bug("vm_call_method: unsupported optimized method type (%d)", vm_cc_cme(cc)->def->body.optimized.type);
    }
}
COLDFUNC static VALUE
vm_call_method_each_type(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling) {
    const struct rb_callinfo *ci = calling->ci;
    const struct rb_callcache *cc = calling->cc;
    const rb_callable_method_entry_t *cme = vm_cc_cme(cc);
    VALUE v;
    switch (cme->def->type) {
      case VM_METHOD_TYPE_ISEQ:
        CC_SET_FASTPATH(cc, vm_call_iseq_setup, 1);
        return vm_call_iseq_setup(ec, cfp, calling);
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
      case VM_METHOD_TYPE_CFUNC:
        CC_SET_FASTPATH(cc, vm_call_cfunc, 1);
        return vm_call_cfunc(ec, cfp, calling);
      case VM_METHOD_TYPE_ATTRSET:
        CALLER_SETUP_ARG(cfp, calling, ci);
        CALLER_REMOVE_EMPTY_KW_SPLAT(cfp, calling, ci);
 rb_check_arity(calling->argc, 1, 1);
 vm_cc_attr_index_set(cc, 0);
        const unsigned int aset_mask = ((0x01 << VM_CALL_ARGS_SPLAT_bit) | (0x01 << VM_CALL_KW_SPLAT_bit) | (0x01 << VM_CALL_KWARG_bit));
        if ((__builtin_expect(!!(ruby_vm_event_flags & (0x0020 | 0x0040)), 0))) { do { const rb_event_flag_t flag_arg_ = (0x0020); rb_hook_list_t *hooks_arg_ = (rb_ec_ractor_hooks(ec)); if ((__builtin_expect(!!((hooks_arg_)->events & (flag_arg_)), 0))) { rb_exec_event_hook_orig(ec, hooks_arg_, flag_arg_, calling->recv, vm_cc_cme(cc)->def->original_id, vm_ci_mid(ci), vm_cc_cme(cc)->owner, ((VALUE)RUBY_Qundef), 0); } } while (0); v = vm_call_attrset(ec, cfp, calling); do { const rb_event_flag_t flag_arg_ = (0x0040); rb_hook_list_t *hooks_arg_ = (rb_ec_ractor_hooks(ec)); if ((__builtin_expect(!!((hooks_arg_)->events & (flag_arg_)), 0))) { rb_exec_event_hook_orig(ec, hooks_arg_, flag_arg_, calling->recv, vm_cc_cme(cc)->def->original_id, vm_ci_mid(ci), vm_cc_cme(cc)->owner, (v), 0); } } while (0); } else { CC_SET_FASTPATH(cc, vm_call_attrset, !(vm_ci_flag(ci) & aset_mask)); v = vm_call_attrset(ec, cfp, calling); };
        return v;
      case VM_METHOD_TYPE_IVAR:
        CALLER_SETUP_ARG(cfp, calling, ci);
        CALLER_REMOVE_EMPTY_KW_SPLAT(cfp, calling, ci);
 rb_check_arity(calling->argc, 0, 0);
 vm_cc_attr_index_set(cc, 0);
        const unsigned int ivar_mask = ((0x01 << VM_CALL_ARGS_SPLAT_bit) | (0x01 << VM_CALL_KW_SPLAT_bit));
        if ((__builtin_expect(!!(ruby_vm_event_flags & (0x0020 | 0x0040)), 0))) { do { const rb_event_flag_t flag_arg_ = (0x0020); rb_hook_list_t *hooks_arg_ = (rb_ec_ractor_hooks(ec)); if ((__builtin_expect(!!((hooks_arg_)->events & (flag_arg_)), 0))) { rb_exec_event_hook_orig(ec, hooks_arg_, flag_arg_, calling->recv, vm_cc_cme(cc)->def->original_id, vm_ci_mid(ci), vm_cc_cme(cc)->owner, ((VALUE)RUBY_Qundef), 0); } } while (0); v = vm_call_ivar(ec, cfp, calling); do { const rb_event_flag_t flag_arg_ = (0x0040); rb_hook_list_t *hooks_arg_ = (rb_ec_ractor_hooks(ec)); if ((__builtin_expect(!!((hooks_arg_)->events & (flag_arg_)), 0))) { rb_exec_event_hook_orig(ec, hooks_arg_, flag_arg_, calling->recv, vm_cc_cme(cc)->def->original_id, vm_ci_mid(ci), vm_cc_cme(cc)->owner, (v), 0); } } while (0); } else { CC_SET_FASTPATH(cc, vm_call_ivar, !(vm_ci_flag(ci) & ivar_mask)); v = vm_call_ivar(ec, cfp, calling); };
        return v;
      case VM_METHOD_TYPE_MISSING:
        vm_cc_method_missing_reason_set(cc, 0);
        CC_SET_FASTPATH(cc, vm_call_method_missing, 1);
        return vm_call_method_missing(ec, cfp, calling);
      case VM_METHOD_TYPE_BMETHOD:
        CC_SET_FASTPATH(cc, vm_call_bmethod, 1);
        return vm_call_bmethod(ec, cfp, calling);
      case VM_METHOD_TYPE_ALIAS:
        CC_SET_FASTPATH(cc, vm_call_alias, 1);
        return vm_call_alias(ec, cfp, calling);
      case VM_METHOD_TYPE_OPTIMIZED:
        return vm_call_optimized(ec, cfp, calling, ci, cc);
      case VM_METHOD_TYPE_UNDEF:
 break;
      case VM_METHOD_TYPE_ZSUPER:
        return vm_call_zsuper(ec, cfp, calling, ((((struct RClass *)(vm_cc_cme(cc)->defined_class))->ptr)->origin_));
      case VM_METHOD_TYPE_REFINED:
        return vm_call_refined(ec, cfp, calling);
    }
    rb_bug("vm_call_method: unsupported method type (%d)", vm_cc_cme(cc)->def->type);
}
__attribute__((__noreturn__)) static void vm_raise_method_missing(rb_execution_context_t *ec, int argc, const VALUE *argv, VALUE obj, int call_status);
static VALUE
vm_call_method_nome(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    const struct rb_callinfo *ci = calling->ci;
    const int stat = ci_missing_reason(ci);
    if (vm_ci_mid(ci) == idMethodMissing) {
 rb_control_frame_t *reg_cfp = cfp;
 VALUE *argv = (((((reg_cfp)->sp)))-(calling->argc));
 vm_raise_method_missing(ec, calling->argc, argv, calling->recv, stat);
    }
    else {
        return vm_call_method_missing_body(ec, cfp, calling, ci, stat);
    }
}
static inline VALUE
vm_call_method(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    const struct rb_callinfo *ci = calling->ci;
    const struct rb_callcache *cc = calling->cc;
    ((void)0);
    if (vm_cc_cme(cc) != ((void *)0)) {
 switch ((rb_method_visibility_t)(((vm_cc_cme(cc))->flags & (((VALUE)RUBY_FL_USER4) | ((VALUE)RUBY_FL_USER5))) >> ((((VALUE)RUBY_FL_USHIFT) + 4)+0))) {
   case METHOD_VISI_PUBLIC:
            return vm_call_method_each_type(ec, cfp, calling);
   case METHOD_VISI_PRIVATE:
     if (!(vm_ci_flag(ci) & (0x01 << VM_CALL_FCALL_bit))) {
  enum method_missing_reason stat = MISSING_PRIVATE;
  if (vm_ci_flag(ci) & (0x01 << VM_CALL_VCALL_bit)) stat |= MISSING_VCALL;
                vm_cc_method_missing_reason_set(cc, stat);
                CC_SET_FASTPATH(cc, vm_call_method_missing, 1);
                return vm_call_method_missing(ec, cfp, calling);
     }
            return vm_call_method_each_type(ec, cfp, calling);
   case METHOD_VISI_PROTECTED:
     if (!(vm_ci_flag(ci) & (0x01 << VM_CALL_OPT_SEND_bit))) {
  if (!rb_obj_is_kind_of(cfp->self, vm_cc_cme(cc)->defined_class)) {
                    vm_cc_method_missing_reason_set(cc, MISSING_PROTECTED);
                    return vm_call_method_missing(ec, cfp, calling);
  }
  else {
      ((void)0);
                    struct rb_callcache cc_on_stack = *cc;
                    RB_FL_SET_RAW((VALUE)&cc_on_stack, ((VALUE)RUBY_FL_USER4));
                    calling->cc = &cc_on_stack;
                    return vm_call_method_each_type(ec, cfp, calling);
  }
     }
            return vm_call_method_each_type(ec, cfp, calling);
   default:
     rb_bug("unreachable");
 }
    }
    else {
        return vm_call_method_nome(ec, cfp, calling);
    }
}
static VALUE
vm_call_general(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_method(ec, reg_cfp, calling);
}static inline 
void
rb_vm_cc_general(const struct rb_callcache *cc)
{
    ((void)0);
    ((void)0);
    *(vm_call_handler *)&cc->call_ = vm_call_general;
}
static VALUE
vm_call_super_method(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    ((void)0);
    if (ec == ((void *)0)) rb_bug("unreachable");
    ((void)0);
    return vm_call_method(ec, reg_cfp, calling);
}
static inline VALUE
vm_search_normal_superclass(VALUE klass)
{
    if (RB_BUILTIN_TYPE(klass) == RUBY_T_ICLASS &&
 RB_FL_TEST_RAW(((struct RBasic *)(klass))->klass, RMODULE_IS_REFINEMENT)) {
 klass = ((struct RBasic *)(klass))->klass;
    }
    klass = ((((struct RClass *)(klass))->ptr)->origin_);
    return RCLASS_SUPER(klass);
}
__attribute__((__noreturn__)) static void vm_super_outside(void);
static void
vm_super_outside(void)
{
    rb_raise(rb_eNoMethodError, "super called outside of method");
}
static const struct rb_callcache *
empty_cc_for_super(void)
{
    return rb_vm_empty_cc_for_super();
}
static const struct rb_callcache *
vm_search_super_method(const rb_control_frame_t *reg_cfp, struct rb_call_data *cd, VALUE recv)
{
    VALUE current_defined_class;
    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(reg_cfp);
    if (!me) {
 vm_super_outside();
    }
    current_defined_class = me->defined_class;
    if (!RB_NIL_P(((((struct RClass *)(current_defined_class))->ptr)->refined_class))) {
 current_defined_class = ((((struct RClass *)(current_defined_class))->ptr)->refined_class);
    }
    if (RB_BUILTIN_TYPE(current_defined_class) != RUBY_T_MODULE &&
 !RB_FL_TEST_RAW(current_defined_class, RMODULE_INCLUDED_INTO_REFINEMENT) &&
        reg_cfp->iseq != method_entry_iseqptr(me) &&
        !rb_obj_is_kind_of(recv, current_defined_class)) {
 VALUE m = RB_TYPE_P(current_defined_class, RUBY_T_ICLASS) ?
            ((((struct RClass *)(current_defined_class))->ptr)->includer) : current_defined_class;
        if (m) {
            rb_raise(rb_eTypeError,
                     "self has wrong type to call super in this context: "
                     "%""l""i" "\v"" (expected %""l""i" "\v"")",
                     rb_obj_class(recv), m);
        }
    }
    if (me->def->type == VM_METHOD_TYPE_BMETHOD && (vm_ci_flag(cd->ci) & (0x01 << VM_CALL_ZSUPER_bit))) {
 rb_raise(rb_eRuntimeError,
   "implicit argument passing of super from method defined"
   " by define_method() is not supported."
   " Specify all arguments explicitly.");
    }
    ID mid = me->def->original_id;
    cd->ci = vm_ci_new_runtime_(mid, vm_ci_flag(cd->ci), vm_ci_argc(cd->ci), vm_ci_kwarg(cd->ci), "./vm_insnhelper.c", 3867);
    (rb_obj_written((VALUE)(reg_cfp->iseq), (VALUE)(((VALUE)RUBY_Qundef)), (VALUE)(cd->ci), "./vm_insnhelper.c", 3872));
    const struct rb_callcache *cc;
    VALUE klass = vm_search_normal_superclass(me->defined_class);
    if (!klass) {
        cc = vm_cc_new(klass, ((void *)0), vm_call_method_missing);
        rb_obj_write((VALUE)(reg_cfp->iseq), __extension__({
       ;
       ; __typeof__((VALUE *)(&cd->cc)) unaligned_member_access_result = ((VALUE *)(&cd->cc));
       ; unaligned_member_access_result; }), (VALUE)(cc), "./vm_insnhelper.c", 3881);
    }
    else {
        cc = vm_search_method_fastpath((VALUE)reg_cfp->iseq, cd, klass);
        const rb_callable_method_entry_t *cached_cme = vm_cc_cme(cc);
        if (cached_cme == ((void *)0)) {
            cd->cc = empty_cc_for_super();
        }
        else if (cached_cme->called_id != mid) {
            const rb_callable_method_entry_t *cme = rb_callable_method_entry(klass, mid);
            if (cme) {
                cc = vm_cc_new(klass, cme, vm_call_super_method);
                rb_obj_write((VALUE)(reg_cfp->iseq), __extension__({
               ;
               ; __typeof__((VALUE *)(&cd->cc)) unaligned_member_access_result = ((VALUE *)(&cd->cc));
               ; unaligned_member_access_result; }), (VALUE)(cc), "./vm_insnhelper.c", 3896);
            }
            else {
                cd->cc = cc = empty_cc_for_super();
            }
        }
        else {
            switch (cached_cme->def->type) {
              case VM_METHOD_TYPE_REFINED:
              case VM_METHOD_TYPE_ATTRSET:
              case VM_METHOD_TYPE_IVAR:
                vm_cc_call_set(cc, vm_call_super_method);
                break;
              default:
                break;
            }
        }
    }
    ((void)0);
    return cc;
}
static inline int
block_proc_is_lambda(const VALUE procval)
{
    rb_proc_t *proc;
    if (procval) {
 (((proc)) = (rb_proc_t*)((struct RData *)(((procval))))->data);
 return proc->is_lambda;
    }
    else {
 return 0;
    }
}
static VALUE
vm_yield_with_cfunc(rb_execution_context_t *ec,
      const struct rb_captured_block *captured,
                    VALUE self, int argc, const VALUE *argv, int kw_splat, VALUE block_handler,
                    const rb_callable_method_entry_t *me)
{
    int is_lambda = 0;
    VALUE val, arg, blockarg;
    int frame_flag;
    const struct vm_ifunc *ifunc = captured->code.ifunc;
    if (is_lambda) {
 arg = rb_ary_new_from_values(argc, argv);
    }
    else if (argc == 0) {
 arg = ((VALUE)RUBY_Qnil);
    }
    else {
 arg = argv[0];
    }
    blockarg = rb_vm_bh_to_procval(ec, block_handler);
    frame_flag = VM_FRAME_MAGIC_IFUNC | VM_FRAME_FLAG_CFRAME | (me ? VM_FRAME_FLAG_BMETHOD : 0);
    if (kw_splat) {
        frame_flag |= VM_FRAME_FLAG_CFRAME_KW;
    }
    vm_push_frame(ec, (const rb_iseq_t *)captured->code.ifunc,
                  frame_flag,
    self,
    ((VALUE)((captured->ep)) | (0x01)),
                  (VALUE)me,
    0, ec->cfp->sp, 0, 0);
    val = (*ifunc->func)(arg, (VALUE)ifunc->data, argc, argv, blockarg);
    rb_vm_pop_frame(ec);
    return val;
}
static VALUE
vm_yield_with_symbol(rb_execution_context_t *ec, VALUE symbol, int argc, const VALUE *argv, int kw_splat, VALUE block_handler)
{
    return rb_sym_proc_call(rb_sym2id(symbol), argc, argv, kw_splat, rb_vm_bh_to_procval(ec, block_handler));
}
static inline int
vm_callee_setup_block_arg_arg0_splat(rb_control_frame_t *cfp, const rb_iseq_t *iseq, VALUE *argv, VALUE ary)
{
    int i;
    long len = rb_array_len(ary);
    do { __extension__ _Static_assert(sizeof(*((cfp)->sp)) == sizeof(VALUE), "sizeof_sp" ": " "sizeof(*((cfp)->sp)) == sizeof(VALUE)"); __extension__ _Static_assert(sizeof(*((cfp))) == sizeof(rb_control_frame_t), "sizeof_cfp" ": " "sizeof(*((cfp))) == sizeof(rb_control_frame_t)"); const struct rb_control_frame_struct *bound = (void *)&((cfp)->sp)[((iseq->body->param.lead_num))]; if ((__builtin_expect(!!(((cfp)) <= &bound[1]), 0))) { vm_stackoverflow(); } } while (0);
    for (i=0; i<len && i<iseq->body->param.lead_num; i++) {
 argv[i] = RARRAY_AREF(ary, i);
    }
    return i;
}
static inline VALUE
vm_callee_setup_block_arg_arg0_check(VALUE *argv)
{
    VALUE ary, arg0 = argv[0];
    ary = rb_check_array_type(arg0);
    ((void)0);
    return ary;
}
static int
vm_callee_setup_block_arg(rb_execution_context_t *ec, struct rb_calling_info *calling, const struct rb_callinfo *ci, const rb_iseq_t *iseq, VALUE *argv, const enum arg_setup_type arg_setup_type)
{
    if (rb_simple_iseq_p(iseq)) {
 rb_control_frame_t *cfp = ec->cfp;
 VALUE arg0;
        CALLER_SETUP_ARG(cfp, calling, ci);
        CALLER_REMOVE_EMPTY_KW_SPLAT(cfp, calling, ci);
 if (arg_setup_type == arg_setup_block &&
     calling->argc == 1 &&
     iseq->body->param.flags.has_lead &&
     !iseq->body->param.flags.ambiguous_param0 &&
     !RB_NIL_P(arg0 = vm_callee_setup_block_arg_arg0_check(argv))) {
     calling->argc = vm_callee_setup_block_arg_arg0_splat(cfp, iseq, argv, arg0);
 }
 if (calling->argc != iseq->body->param.lead_num) {
     if (arg_setup_type == arg_setup_block) {
  if (calling->argc < iseq->body->param.lead_num) {
      int i;
      do { __extension__ _Static_assert(sizeof(*((cfp)->sp)) == sizeof(VALUE), "sizeof_sp" ": " "sizeof(*((cfp)->sp)) == sizeof(VALUE)"); __extension__ _Static_assert(sizeof(*((cfp))) == sizeof(rb_control_frame_t), "sizeof_cfp" ": " "sizeof(*((cfp))) == sizeof(rb_control_frame_t)"); const struct rb_control_frame_struct *bound = (void *)&((cfp)->sp)[((iseq->body->param.lead_num))]; if ((__builtin_expect(!!(((cfp)) <= &bound[1]), 0))) { vm_stackoverflow(); } } while (0);
      for (i=calling->argc; i<iseq->body->param.lead_num; i++) argv[i] = ((VALUE)RUBY_Qnil);
      calling->argc = iseq->body->param.lead_num;
  }
  else if (calling->argc > iseq->body->param.lead_num) {
      calling->argc = iseq->body->param.lead_num;
  }
     }
     else {
  argument_arity_error(ec, iseq, calling->argc, iseq->body->param.lead_num, iseq->body->param.lead_num);
     }
 }
 return 0;
    }
    else {
 return setup_parameters_complex(ec, iseq, calling, ci, argv, arg_setup_type);
    }
}
static int
vm_yield_setup_args(rb_execution_context_t *ec, const rb_iseq_t *iseq, const int argc, VALUE *argv, int kw_splat, VALUE block_handler, enum arg_setup_type arg_setup_type)
{
    struct rb_calling_info calling_entry, *calling;
    calling = &calling_entry;
    calling->argc = argc;
    calling->block_handler = block_handler;
    calling->kw_splat = kw_splat;
    calling->recv = ((VALUE)RUBY_Qundef);
    struct rb_callinfo dummy_ci = (struct rb_callinfo) { .flags = RUBY_T_IMEMO | (imemo_callinfo << ((VALUE)RUBY_FL_USHIFT)) | ((VALUE)RUBY_FL_USER4), .mid = 0, .flag = (kw_splat ? (0x01 << VM_CALL_KW_SPLAT_bit) : 0), .argc = 0, .kwarg = 0, };
    return vm_callee_setup_block_arg(ec, calling, &dummy_ci, iseq, argv, arg_setup_type);
}
static VALUE
vm_invoke_iseq_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
       struct rb_calling_info *calling, const struct rb_callinfo *ci,
                     _Bool is_lambda, VALUE block_handler)
{
    const struct rb_captured_block *captured = VM_BH_TO_ISEQ_BLOCK(block_handler);
    const rb_iseq_t *iseq = rb_iseq_check(captured->code.iseq);
    const int arg_size = iseq->body->param.size;
    VALUE * const rsp = ((((reg_cfp)->sp))) - calling->argc;
    int opt_pc = vm_callee_setup_block_arg(ec, calling, ci, iseq, rsp, is_lambda ? arg_setup_method : arg_setup_block);
    (((reg_cfp)->sp) = (((rsp))));
    vm_push_frame(ec, iseq,
    VM_FRAME_MAGIC_BLOCK | (is_lambda ? VM_FRAME_FLAG_LAMBDA : 0),
    captured->self,
    ((VALUE)((captured->ep)) | (0x01)), 0,
    iseq->body->iseq_encoded + opt_pc,
    rsp + arg_size,
    iseq->body->local_table_size - arg_size, iseq->body->stack_max);
    return ((VALUE)RUBY_Qundef);
}
static VALUE
vm_invoke_symbol_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
         struct rb_calling_info *calling, const struct rb_callinfo *ci,
                       __attribute__ ((__unused__)) _Bool is_lambda, VALUE block_handler)
{
    if (calling->argc < 1) {
        rb_raise(rb_eArgError, "no receiver given");
    }
    else {
        VALUE symbol = VM_BH_TO_SYMBOL(block_handler);
        CALLER_SETUP_ARG(reg_cfp, calling, ci);
        calling->recv = (*(((((reg_cfp)->sp)))-(--calling->argc)-1));
        return vm_call_symbol(ec, reg_cfp, calling, ci, symbol);
    }
}
static VALUE
vm_invoke_ifunc_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
        struct rb_calling_info *calling, const struct rb_callinfo *ci,
                      __attribute__ ((__unused__)) _Bool is_lambda, VALUE block_handler)
{
    VALUE val;
    int argc;
    const struct rb_captured_block *captured = VM_BH_TO_IFUNC_BLOCK(block_handler);
    CALLER_SETUP_ARG(ec->cfp, calling, ci);
    CALLER_REMOVE_EMPTY_KW_SPLAT(ec->cfp, calling, ci);
    argc = calling->argc;
    val = vm_yield_with_cfunc(ec, captured, captured->self, argc, (((((reg_cfp)->sp)))-(argc)), calling->kw_splat, calling->block_handler, ((void *)0));
    ((((reg_cfp)->sp) -= (((argc)))));
    return val;
}
static VALUE
vm_proc_to_block_handler(VALUE procval)
{
    const struct rb_block *block = vm_proc_block(procval);
    switch (vm_block_type(block)) {
      case block_type_iseq:
 return VM_BH_FROM_ISEQ_BLOCK(&block->as.captured);
      case block_type_ifunc:
 return VM_BH_FROM_IFUNC_BLOCK(&block->as.captured);
      case block_type_symbol:
 return VM_BH_FROM_SYMBOL(block->as.symbol);
      case block_type_proc:
 return VM_BH_FROM_PROC(block->as.proc);
    }
    __builtin_unreachable();
    return ((VALUE)RUBY_Qundef);
}
static VALUE
vm_invoke_proc_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
                     struct rb_calling_info *calling, const struct rb_callinfo *ci,
                     _Bool is_lambda, VALUE block_handler)
{
    while (vm_block_handler_type(block_handler) == block_handler_type_proc) {
        VALUE proc = VM_BH_TO_PROC(block_handler);
        is_lambda = block_proc_is_lambda(proc);
        block_handler = vm_proc_to_block_handler(proc);
    }
    return vm_invoke_block(ec, reg_cfp, calling, ci, is_lambda, block_handler);
}
static inline VALUE
vm_invoke_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
                struct rb_calling_info *calling, const struct rb_callinfo *ci,
                _Bool is_lambda, VALUE block_handler)
{
    VALUE (*func)(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
                  struct rb_calling_info *calling, const struct rb_callinfo *ci,
                  _Bool is_lambda, VALUE block_handler);
    switch (vm_block_handler_type(block_handler)) {
      case block_handler_type_iseq: func = vm_invoke_iseq_block; break;
      case block_handler_type_ifunc: func = vm_invoke_ifunc_block; break;
      case block_handler_type_proc: func = vm_invoke_proc_block; break;
      case block_handler_type_symbol: func = vm_invoke_symbol_block; break;
      default: rb_bug("vm_invoke_block: unreachable");
    }
    return func(ec, reg_cfp, calling, ci, is_lambda, block_handler);
}
static VALUE
vm_make_proc_with_iseq(const rb_iseq_t *blockiseq)
{
    const rb_execution_context_t *ec = rb_current_execution_context(1);
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);
    struct rb_captured_block *captured;
    if (cfp == 0) {
 rb_bug("vm_make_proc_with_iseq: unreachable");
    }
    captured = VM_CFP_TO_CAPTURED_BLOCK(cfp);
    captured->code.iseq = blockiseq;
    return rb_vm_make_proc(ec, captured, rb_cProc);
}
static VALUE
vm_once_exec(VALUE iseq)
{
    VALUE proc = vm_make_proc_with_iseq((rb_iseq_t *)iseq);
    return rb_proc_call_with_block(proc, 0, 0, ((VALUE)RUBY_Qnil));
}
static VALUE
vm_once_clear(VALUE data)
{
    union iseq_inline_storage_entry *is = (union iseq_inline_storage_entry *)data;
    is->once.running_thread = ((void *)0);
    return ((VALUE)RUBY_Qnil);
}
static _Bool
check_respond_to_missing(VALUE obj, VALUE v)
{
    VALUE args[2];
    VALUE r;
    args[0] = obj; args[1] = ((VALUE)RUBY_Qfalse);
    r = rb_check_funcall(v, idRespond_to_missing, 2, args);
    if (r != ((VALUE)RUBY_Qundef) && RB_TEST(r)) {
 return 1;
    }
    else {
 return 0;
    }
}
static _Bool
vm_defined(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, rb_num_t op_type, VALUE obj, VALUE v)
{
    VALUE klass;
    enum defined_type type = (enum defined_type)op_type;
    switch (type) {
      case DEFINED_IVAR:
        return rb_ivar_defined((((((reg_cfp)))->self)), rb_sym2id(obj));
 break;
      case DEFINED_GVAR:
        return rb_gvar_defined(rb_sym2id(obj));
 break;
      case DEFINED_CVAR: {
        const rb_cref_t *cref = vm_get_cref(((((reg_cfp)->ep))));
        klass = vm_get_cvar_base(cref, (((reg_cfp))), 0);
        return rb_cvar_defined(klass, rb_sym2id(obj));
 break;
      }
      case DEFINED_CONST:
      case DEFINED_CONST_FROM: {
 _Bool allow_nil = type == DEFINED_CONST;
 klass = v;
        return vm_get_ev_const(ec, klass, rb_sym2id(obj), allow_nil, 1);
 break;
      }
      case DEFINED_FUNC:
 klass = rb_class_of(v);
        return rb_ec_obj_respond_to(ec, v, rb_sym2id(obj), 1);
 break;
      case DEFINED_METHOD:{
 VALUE klass = rb_class_of(v);
 const rb_method_entry_t *me = rb_method_entry_with_refinements(klass, rb_sym2id(obj), ((void *)0));
 if (me) {
     switch ((rb_method_visibility_t)(((me)->flags & (((VALUE)RUBY_FL_USER4) | ((VALUE)RUBY_FL_USER5))) >> ((((VALUE)RUBY_FL_USHIFT) + 4)+0))) {
       case METHOD_VISI_PRIVATE:
  break;
       case METHOD_VISI_PROTECTED:
  if (!rb_obj_is_kind_of((((((reg_cfp)))->self)), rb_class_real(me->defined_class))) {
      break;
  }
       case METHOD_VISI_PUBLIC:
                return 1;
  break;
       default:
  rb_bug("vm_defined: unreachable: %u", (unsigned int)(rb_method_visibility_t)(((me)->flags & (((VALUE)RUBY_FL_USER4) | ((VALUE)RUBY_FL_USER5))) >> ((((VALUE)RUBY_FL_USHIFT) + 4)+0)));
     }
 }
 else {
     return check_respond_to_missing(obj, v);
 }
 break;
      }
      case DEFINED_YIELD:
 if (((VM_EP_LEP(((((reg_cfp)->ep)))))[(-1)]) != 0) {
            return 1;
 }
 break;
      case DEFINED_ZSUPER:
 {
     const rb_callable_method_entry_t *me = rb_vm_frame_method_entry((((reg_cfp))));
     if (me) {
  VALUE klass = vm_search_normal_superclass(me->defined_class);
  ID id = me->def->original_id;
  return rb_method_boundp(klass, id, 0);
     }
 }
 break;
      case DEFINED_REF:{
 return vm_getspecial(ec, (VM_EP_LEP(((((reg_cfp)->ep))))), ((VALUE)RUBY_Qfalse), RB_FIX2INT(obj)) != ((VALUE)RUBY_Qnil);
 break;
      }
      default:
 rb_bug("unimplemented defined? type (VM)");
 break;
    }
    return 0;
}static inline 
_Bool
rb_vm_defined(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, rb_num_t op_type, VALUE obj, VALUE v)
{
    return vm_defined(ec, reg_cfp, op_type, obj, v);
}
static const VALUE *
vm_get_ep(const VALUE *const reg_ep, rb_num_t lv)
{
    rb_num_t i;
    const VALUE *ep = reg_ep;
    for (i = 0; i < lv; i++) {
 ep = ((VALUE *)((ep)[(-1)] & ~0x03));
    }
    return ep;
}
static VALUE
vm_get_special_object(const VALUE *const reg_ep,
        enum vm_special_object_type type)
{
    switch (type) {
      case VM_SPECIAL_OBJECT_VMCORE:
 return rb_mRubyVMFrozenCore;
      case VM_SPECIAL_OBJECT_CBASE:
 return vm_get_cbase(reg_ep);
      case VM_SPECIAL_OBJECT_CONST_BASE:
 return vm_get_const_base(reg_ep);
      default:
 rb_bug("putspecialobject insn: unknown value_type %d", type);
    }
}
static VALUE
vm_concat_array(VALUE ary1, VALUE ary2st)
{
    const VALUE ary2 = ary2st;
    VALUE tmp1 = rb_check_to_array(ary1);
    VALUE tmp2 = rb_check_to_array(ary2);
    if (RB_NIL_P(tmp1)) {
 tmp1 = __extension__ ({ const VALUE args_to_new_ary[] = {ary1}; if (__builtin_constant_p(1)) { __extension__ _Static_assert(((int)(sizeof(args_to_new_ary) / sizeof((args_to_new_ary)[0]))) == (1), "rb_ary_new_from_args" ": " "numberof(args_to_new_ary) == (1)"); } rb_ary_new_from_values(((int)(sizeof(args_to_new_ary) / sizeof((args_to_new_ary)[0]))), args_to_new_ary); });
    }
    if (RB_NIL_P(tmp2)) {
 tmp2 = __extension__ ({ const VALUE args_to_new_ary[] = {ary2}; if (__builtin_constant_p(1)) { __extension__ _Static_assert(((int)(sizeof(args_to_new_ary) / sizeof((args_to_new_ary)[0]))) == (1), "rb_ary_new_from_args" ": " "numberof(args_to_new_ary) == (1)"); } rb_ary_new_from_values(((int)(sizeof(args_to_new_ary) / sizeof((args_to_new_ary)[0]))), args_to_new_ary); });
    }
    if (tmp1 == ary1) {
 tmp1 = rb_ary_dup(ary1);
    }
    return rb_ary_concat(tmp1, tmp2);
}
static VALUE
vm_splat_array(VALUE flag, VALUE ary)
{
    VALUE tmp = rb_check_to_array(ary);
    if (RB_NIL_P(tmp)) {
 return __extension__ ({ const VALUE args_to_new_ary[] = {ary}; if (__builtin_constant_p(1)) { __extension__ _Static_assert(((int)(sizeof(args_to_new_ary) / sizeof((args_to_new_ary)[0]))) == (1), "rb_ary_new_from_args" ": " "numberof(args_to_new_ary) == (1)"); } rb_ary_new_from_values(((int)(sizeof(args_to_new_ary) / sizeof((args_to_new_ary)[0]))), args_to_new_ary); });
    }
    else if (RB_TEST(flag)) {
 return rb_ary_dup(tmp);
    }
    else {
 return tmp;
    }
}static inline 
VALUE
rb_vm_splat_array(VALUE flag, VALUE ary)
{
    return vm_splat_array(flag, ary);
}
static VALUE
vm_check_match(rb_execution_context_t *ec, VALUE target, VALUE pattern, rb_num_t flag)
{
    enum vm_check_match_type type = ((int)flag) & 0x03;
    if (flag & 0x04) {
 long i;
 const long n = rb_array_len(pattern);
 for (i = 0; i < n; i++) {
     VALUE v = RARRAY_AREF(pattern, i);
     VALUE c = check_match(ec, v, target, type);
     if (RB_TEST(c)) {
  return c;
     }
 }
 return ((VALUE)RUBY_Qfalse);
    }
    else {
 return check_match(ec, pattern, target, type);
    }
}
static VALUE
vm_check_keyword(lindex_t bits, lindex_t idx, const VALUE *ep)
{
    const VALUE kw_bits = *(ep - bits);
    if (RB_FIXNUM_P(kw_bits)) {
 unsigned int b = (unsigned int)rb_fix2ulong(kw_bits);
 if ((idx < (32-1)) && (b & (0x01 << idx)))
     return ((VALUE)RUBY_Qfalse);
    }
    else {
 ((void)0);
 if (rb_hash_has_key(kw_bits, __builtin_choose_expr( __builtin_constant_p(idx), ((VALUE)(idx)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(idx)))) return ((VALUE)RUBY_Qfalse);
    }
    return ((VALUE)RUBY_Qtrue);
}
static void
vm_dtrace(rb_event_flag_t flag, rb_execution_context_t *ec)
{
    if (0 ||
 0 ||
 0 ||
 0) {
 switch (flag) {
   case 0x0008:
     do { if ((__builtin_expect(!!(0), 0))) { struct ruby_dtrace_method_hook_args args; if (rb_dtrace_setup(ec, 0, 0, &args)) { do {} while (0); } } } while (0);
     return;
   case 0x0020:
     do { if ((__builtin_expect(!!(0), 0))) { struct ruby_dtrace_method_hook_args args; if (rb_dtrace_setup(ec, 0, 0, &args)) { do {} while (0); } } } while (0);
     return;
   case 0x0010:
     do { if ((__builtin_expect(!!(0), 0))) { struct ruby_dtrace_method_hook_args args; if (rb_dtrace_setup(ec, 0, 0, &args)) { do {} while (0); } } } while (0);
     return;
   case 0x0040:
     do { if ((__builtin_expect(!!(0), 0))) { struct ruby_dtrace_method_hook_args args; if (rb_dtrace_setup(ec, 0, 0, &args)) { do {} while (0); } } } while (0);
     return;
 }
    }
}
static VALUE
vm_const_get_under(ID id, rb_num_t flags, VALUE cbase)
{
    VALUE ns;
    if ((ns = vm_search_const_defined_class(cbase, id)) == 0) {
 return ns;
    }
    else if (((flags) & 0x08)) {
 return rb_public_const_get_at(ns, id);
    }
    else {
 return rb_const_get_at(ns, id);
    }
}
static VALUE
vm_check_if_class(ID id, rb_num_t flags, VALUE super, VALUE klass)
{
    if (!RB_TYPE_P(klass, RUBY_T_CLASS)) {
        return 0;
    }
    else if (((flags) & 0x10)) {
 VALUE tmp = rb_class_real(RCLASS_SUPER(klass));
 if (tmp != super) {
     rb_raise(rb_eTypeError,
       "superclass mismatch for class %""l""i" "\v""",
       rb_id2str(id));
 }
 else {
     return klass;
 }
    }
    else {
 return klass;
    }
}
static VALUE
vm_check_if_module(ID id, VALUE mod)
{
    if (!RB_TYPE_P(mod, RUBY_T_MODULE)) {
        return 0;
    }
    else {
 return mod;
    }
}
static VALUE
declare_under(ID id, VALUE cbase, VALUE c)
{
    rb_set_class_path_string(c, cbase, rb_id2str(id));
    rb_const_set(cbase, id, c);
    return c;
}
static VALUE
vm_declare_class(ID id, rb_num_t flags, VALUE cbase, VALUE super)
{
    VALUE s = ((flags) & 0x10) ? super : rb_cObject;
    VALUE c = declare_under(id, cbase, rb_define_class_id(id, s));
    rb_define_alloc_func(c, rb_get_alloc_func(c));
    rb_class_inherited(s, c);
    return c;
}
static VALUE
vm_declare_module(ID id, VALUE cbase)
{
    return declare_under(id, cbase, rb_module_new());
}
__attribute__((__noreturn__)) static void unmatched_redefinition(const char *type, VALUE cbase, ID id, VALUE old);
static void
unmatched_redefinition(const char *type, VALUE cbase, ID id, VALUE old)
{
    VALUE name = rb_id2str(id);
    VALUE message = rb_sprintf("%""l""i" "\v"" is not a %s",
                               name, type);
    VALUE location = rb_const_source_location_at(cbase, id);
    if (!RB_NIL_P(location)) {
        rb_str_catf(message, "\n%""l""i" "\v"":%""l""i" "\v"":"
                    " previous definition of %""l""i" "\v"" was here",
                    rb_ary_entry(location, 0), rb_ary_entry(location, 1), name);
    }
    rb_exc_raise(rb_exc_new_str(rb_eTypeError, message));
}
static VALUE
vm_define_class(ID id, rb_num_t flags, VALUE cbase, VALUE super)
{
    VALUE klass;
    if (((flags) & 0x10) && !RB_TYPE_P(super, RUBY_T_CLASS)) {
 rb_raise(rb_eTypeError,
                 "superclass must be an instance of Class (given an instance of %""l""i" "\v"")",
   rb_obj_class(super));
    }
    vm_check_if_namespace(cbase);
    rb_autoload_load(cbase, id);
    if ((klass = vm_const_get_under(id, flags, cbase)) != 0) {
        if (!vm_check_if_class(id, flags, super, klass))
            unmatched_redefinition("class", cbase, id, klass);
        return klass;
    }
    else {
 return vm_declare_class(id, flags, cbase, super);
    }
}
static VALUE
vm_define_module(ID id, rb_num_t flags, VALUE cbase)
{
    VALUE mod;
    vm_check_if_namespace(cbase);
    if ((mod = vm_const_get_under(id, flags, cbase)) != 0) {
        if (!vm_check_if_module(id, mod))
            unmatched_redefinition("module", cbase, id, mod);
        return mod;
    }
    else {
 return vm_declare_module(id, cbase);
    }
}
static VALUE
vm_find_or_create_class_by_id(ID id,
         rb_num_t flags,
         VALUE cbase,
         VALUE super)
{
    rb_vm_defineclass_type_t type = ((rb_vm_defineclass_type_t)(flags) & VM_DEFINECLASS_TYPE_MASK);
    switch (type) {
      case VM_DEFINECLASS_TYPE_CLASS:
 return vm_define_class(id, flags, cbase, super);
      case VM_DEFINECLASS_TYPE_SINGLETON_CLASS:
 return rb_singleton_class(cbase);
      case VM_DEFINECLASS_TYPE_MODULE:
 return vm_define_module(id, flags, cbase);
      default:
 rb_bug("unknown defineclass type: %d", (int)type);
    }
}
static rb_method_visibility_t
vm_scope_visibility_get(const rb_execution_context_t *ec)
{
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);
    if (!vm_env_cref_by_cref(cfp->ep)) {
        return METHOD_VISI_PUBLIC;
    }
    else {
        return CREF_SCOPE_VISI(vm_ec_cref(ec))->method_visi;
    }
}
static int
vm_scope_module_func_check(const rb_execution_context_t *ec)
{
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);
    if (!vm_env_cref_by_cref(cfp->ep)) {
        return 0;
    }
    else {
        return CREF_SCOPE_VISI(vm_ec_cref(ec))->module_func;
    }
}
static void
vm_define_method(const rb_execution_context_t *ec, VALUE obj, ID id, VALUE iseqval, int is_singleton)
{
    VALUE klass;
    rb_method_visibility_t visi;
    rb_cref_t *cref = vm_ec_cref(ec);
    if (is_singleton) {
        klass = rb_singleton_class(obj);
        visi = METHOD_VISI_PUBLIC;
    }
    else {
        klass = CREF_CLASS_FOR_DEFINITION(cref);
        visi = vm_scope_visibility_get(ec);
    }
    if (RB_NIL_P(klass)) {
        rb_raise(rb_eTypeError, "no class/module to add method");
    }
    rb_add_method_iseq(klass, id, (const rb_iseq_t *)iseqval, cref, visi);
    if (!is_singleton && vm_scope_module_func_check(ec)) {
        klass = rb_singleton_class(klass);
        rb_add_method_iseq(klass, id, (const rb_iseq_t *)iseqval, cref, METHOD_VISI_PUBLIC);
    }
}
static VALUE
vm_invokeblock_i(struct rb_execution_context_struct *ec,
                 struct rb_control_frame_struct *reg_cfp,
                 struct rb_calling_info *calling)
{
    const struct rb_callinfo *ci = calling->ci;
    VALUE block_handler = VM_CF_BLOCK_HANDLER((((reg_cfp))));
    if (block_handler == 0) {
        rb_vm_localjump_error("no block given (yield)", ((VALUE)RUBY_Qnil), 0);
    }
    else {
        return vm_invoke_block(ec, (((reg_cfp))), calling, ci, 0, block_handler);
    }
}
static const struct rb_callcache *
vm_search_method_wrap(const struct rb_control_frame_struct *reg_cfp, struct rb_call_data *cd, VALUE recv)
{
    return vm_search_method((VALUE)reg_cfp->iseq, cd, recv);
}
static const struct rb_callcache *
vm_search_invokeblock(const struct rb_control_frame_struct *reg_cfp, struct rb_call_data *cd, VALUE recv)
{
    static const struct rb_callcache cc = {
        .flags = RUBY_T_IMEMO | (imemo_callcache << ((VALUE)RUBY_FL_USHIFT)) | ((VALUE)RUBY_FL_USER4),
        .klass = 0,
        .cme_ = 0,
        .call_ = vm_invokeblock_i,
        .aux_ = {0},
    };
    return &cc;
}
static
VALUE
vm_sendish(
    struct rb_execution_context_struct *ec,
    struct rb_control_frame_struct *reg_cfp,
    struct rb_call_data *cd,
    VALUE block_handler,
    const struct rb_callcache *(*method_explorer)(const struct rb_control_frame_struct *cfp, struct rb_call_data *cd, VALUE recv)
) {
    VALUE val = ((VALUE)RUBY_Qundef);
    const struct rb_callinfo *ci = cd->ci;
    const struct rb_callcache *cc;
    int argc = vm_ci_argc(ci);
    VALUE recv = (*(((((reg_cfp)->sp)))-(argc)-1));
    struct rb_calling_info calling = {
        .block_handler = block_handler,
        .kw_splat = (vm_ci_flag(ci) & (0x01 << VM_CALL_KW_SPLAT_bit)) > 0,
        .recv = recv,
        .argc = argc,
        .ci = ci,
    };
    calling.cc = cc = method_explorer((((reg_cfp))), cd, recv);
    val = vm_cc_call(cc)(ec, (((reg_cfp))), &calling);
    if (val != ((VALUE)RUBY_Qundef)) {
        return val;
    }
    else {
        do { (reg_cfp) = ec->cfp; } while (0);
    }
    if (((((reg_cfp)))->iseq)->body->catch_except_p) {
        VM_ENV_FLAGS_SET(((((reg_cfp)->ep))), VM_FRAME_FLAG_FINISH);
        return rb_vm_exec(ec, 1);
    }
    else if ((val = mjit_exec(ec)) == ((VALUE)RUBY_Qundef)) {
        VM_ENV_FLAGS_SET(((((reg_cfp)->ep))), VM_FRAME_FLAG_FINISH);
        return rb_vm_exec(ec, 0);
    }
    else {
        return val;
    }
}
VALUE rb_nil_to_s(VALUE);
VALUE rb_true_to_s(VALUE);
VALUE rb_false_to_s(VALUE);
VALUE rb_int_to_s(int argc, VALUE *argv, VALUE x);
VALUE rb_fix_to_s(VALUE);
VALUE rb_mod_to_s(VALUE);
VALUE rb_mod_name(VALUE);
static VALUE
vm_objtostring(const rb_iseq_t *iseq, VALUE recv, CALL_DATA cd)
{
    const struct rb_callcache *cc = vm_search_method((VALUE)iseq, cd, recv);
    switch (((int)rb_type(recv))) {
      case RUBY_T_STRING:
        return recv;
      case RUBY_T_SYMBOL:
        if (check_cfunc(vm_cc_cme(cc), rb_sym_to_s)) {
            return rb_sym2str(recv);
        }
        break;
      case RUBY_T_MODULE:
      case RUBY_T_CLASS:
        if (check_cfunc(vm_cc_cme(cc), rb_mod_to_s)) {
            VALUE val = rb_mod_name(recv);
            if (val == ((VALUE)RUBY_Qnil)) {
                val = rb_mod_to_s(recv);
            }
            return val;
        }
        break;
      case RUBY_T_NIL:
        if (check_cfunc(vm_cc_cme(cc), rb_nil_to_s)) {
            return rb_nil_to_s(recv);
        }
        break;
      case RUBY_T_TRUE:
        if (check_cfunc(vm_cc_cme(cc), rb_true_to_s)) {
            return rb_true_to_s(recv);
        }
        break;
      case RUBY_T_FALSE:
        if (check_cfunc(vm_cc_cme(cc), rb_false_to_s)) {
            return rb_false_to_s(recv);
        }
        break;
      case RUBY_T_FIXNUM:
        if (check_cfunc(vm_cc_cme(cc), rb_int_to_s)) {
            return rb_fix_to_s(recv);
        }
        break;
    }
    return ((VALUE)RUBY_Qundef);
}
static VALUE
vm_opt_str_freeze(VALUE str, int bop, ID id)
{
    if (((__builtin_expect(!!((rb_current_vm()->redefined_flag[(bop)]&((1 << 2))) == 0), 1)))) {
 return str;
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
static VALUE
vm_opt_newarray_max(rb_execution_context_t *ec, rb_num_t num, const VALUE *ptr)
{
    if (((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_MAX)]&((1 << 3))) == 0), 1)))) {
 if (num == 0) {
     return ((VALUE)RUBY_Qnil);
 }
 else {
     struct cmp_opt_data cmp_opt = { 0, 0 };
     VALUE result = *ptr;
            rb_snum_t i = num - 1;
     while (i-- > 0) {
  const VALUE v = *++ptr;
  if (((RB_FIXNUM_P(v) && RB_FIXNUM_P(result) && (((cmp_opt).opt_inited & (1U << cmp_opt_Integer)) ? ((cmp_opt).opt_methods & (1U << cmp_opt_Integer)) : (((cmp_opt).opt_inited |= (1U << cmp_opt_Integer)), rb_method_basic_definition_p(rb_cInteger, idCmp) && ((cmp_opt).opt_methods |= (1U << cmp_opt_Integer))))) ? (((long)v > (long)result) ? 1 : ((long)v < (long)result) ? -1 : 0) : ((RB_TYPE_P((v), RUBY_T_STRING) && rb_class_of(v) == rb_cString) && (RB_TYPE_P((result), RUBY_T_STRING) && rb_class_of(result) == rb_cString) && (((cmp_opt).opt_inited & (1U << cmp_opt_String)) ? ((cmp_opt).opt_methods & (1U << cmp_opt_String)) : (((cmp_opt).opt_inited |= (1U << cmp_opt_String)), rb_method_basic_definition_p(rb_cString, idCmp) && ((cmp_opt).opt_methods |= (1U << cmp_opt_String))))) ? rb_str_cmp(v, result) : (RB_FLOAT_TYPE_P(v) && RB_FLOAT_TYPE_P(result) && (((cmp_opt).opt_inited & (1U << cmp_opt_Float)) ? ((cmp_opt).opt_methods & (1U << cmp_opt_Float)) : (((cmp_opt).opt_inited |= (1U << cmp_opt_Float)), rb_method_basic_definition_p(rb_cFloat, idCmp) && ((cmp_opt).opt_methods |= (1U << cmp_opt_Float))))) ? rb_float_cmp(v, result) : rb_cmpint(rb_funcallv(v, idCmp, 1, &result), v, result)) > 0) {
      result = v;
  }
     }
     return result;
 }
    }
    else {
        return rb_vm_call_with_refinements(ec, rb_ary_new_from_values(num, ptr), idMax, 0, ((void *)0), 0);
    }
}
static VALUE
vm_opt_newarray_min(rb_execution_context_t *ec, rb_num_t num, const VALUE *ptr)
{
    if (((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_MIN)]&((1 << 3))) == 0), 1)))) {
 if (num == 0) {
     return ((VALUE)RUBY_Qnil);
 }
 else {
     struct cmp_opt_data cmp_opt = { 0, 0 };
     VALUE result = *ptr;
            rb_snum_t i = num - 1;
     while (i-- > 0) {
  const VALUE v = *++ptr;
  if (((RB_FIXNUM_P(v) && RB_FIXNUM_P(result) && (((cmp_opt).opt_inited & (1U << cmp_opt_Integer)) ? ((cmp_opt).opt_methods & (1U << cmp_opt_Integer)) : (((cmp_opt).opt_inited |= (1U << cmp_opt_Integer)), rb_method_basic_definition_p(rb_cInteger, idCmp) && ((cmp_opt).opt_methods |= (1U << cmp_opt_Integer))))) ? (((long)v > (long)result) ? 1 : ((long)v < (long)result) ? -1 : 0) : ((RB_TYPE_P((v), RUBY_T_STRING) && rb_class_of(v) == rb_cString) && (RB_TYPE_P((result), RUBY_T_STRING) && rb_class_of(result) == rb_cString) && (((cmp_opt).opt_inited & (1U << cmp_opt_String)) ? ((cmp_opt).opt_methods & (1U << cmp_opt_String)) : (((cmp_opt).opt_inited |= (1U << cmp_opt_String)), rb_method_basic_definition_p(rb_cString, idCmp) && ((cmp_opt).opt_methods |= (1U << cmp_opt_String))))) ? rb_str_cmp(v, result) : (RB_FLOAT_TYPE_P(v) && RB_FLOAT_TYPE_P(result) && (((cmp_opt).opt_inited & (1U << cmp_opt_Float)) ? ((cmp_opt).opt_methods & (1U << cmp_opt_Float)) : (((cmp_opt).opt_inited |= (1U << cmp_opt_Float)), rb_method_basic_definition_p(rb_cFloat, idCmp) && ((cmp_opt).opt_methods |= (1U << cmp_opt_Float))))) ? rb_float_cmp(v, result) : rb_cmpint(rb_funcallv(v, idCmp, 1, &result), v, result)) < 0) {
      result = v;
  }
     }
     return result;
 }
    }
    else {
        return rb_vm_call_with_refinements(ec, rb_ary_new_from_values(num, ptr), idMin, 0, ((void *)0), 0);
    }
}
static inline _Bool
vm_inlined_ic_hit_p(VALUE flags, VALUE value, const rb_cref_t *ic_cref, rb_serial_t ic_serial, const VALUE *reg_ep)
{
    if (ic_serial == (ruby_vm_global_constant_state) &&
        ((flags & ((VALUE)RUBY_FL_USER4)) || rb_ractor_main_p())) {
        ((void)0);
        return (ic_cref == ((void *)0) ||
                ic_cref == vm_get_cref(reg_ep));
    }
    return 0;
}
static _Bool
vm_ic_hit_p(const struct iseq_inline_constant_cache_entry *ice, const VALUE *reg_ep)
{
    ((void)0);
    return vm_inlined_ic_hit_p(ice->flags, ice->value, ice->ic_cref, (ice)->ic_serial.raw, reg_ep);
}static inline 
_Bool
rb_vm_ic_hit_p(IC ic, const VALUE *reg_ep)
{
    return ic->entry && vm_ic_hit_p(ic->entry, reg_ep);
}
COLDFUNC static void
vm_ic_update(const rb_iseq_t *iseq, IC ic, VALUE val, const VALUE *reg_ep) {
    struct iseq_inline_constant_cache_entry *ice = (struct iseq_inline_constant_cache_entry *)rb_imemo_new(imemo_constcache, 0, 0, 0, 0);
    rb_obj_write((VALUE)(ice), __extension__({
   ;
   ; __typeof__((VALUE *)(&ice->value)) unaligned_member_access_result = ((VALUE *)(&ice->value));
   ; unaligned_member_access_result; }), (VALUE)(val), "./vm_insnhelper.c", 4963);
    ice->ic_cref = vm_get_const_key_cref(reg_ep);
    (ice)->ic_serial.raw = ((ruby_vm_global_constant_state) - ruby_vm_const_missing_count);
    if (rb_ractor_shareable_p(val)) ice->flags |= ((VALUE)RUBY_FL_USER4);
    ruby_vm_const_missing_count = 0;
    rb_obj_write((VALUE)(iseq), __extension__({
   ;
   ; __typeof__((VALUE *)(&ic->entry)) unaligned_member_access_result = ((VALUE *)(&ic->entry));
   ; unaligned_member_access_result; }), (VALUE)(ice), "./vm_insnhelper.c", 4968);
}
static VALUE
vm_once_dispatch(rb_execution_context_t *ec, ISEQ iseq, ISE is)
{
    rb_thread_t *th = rb_ec_thread_ptr(ec);
    rb_thread_t *const RUNNING_THREAD_ONCE_DONE = (rb_thread_t *)(0x1);
  again:
    if (is->once.running_thread == RUNNING_THREAD_ONCE_DONE) {
 return is->once.value;
    }
    else if (is->once.running_thread == ((void *)0)) {
 VALUE val;
 is->once.running_thread = th;
 val = rb_ensure(vm_once_exec, (VALUE)iseq, vm_once_clear, (VALUE)is);
 rb_obj_write((VALUE)(ec->cfp->iseq), __extension__({
;
; __typeof__((VALUE *)(&is->once.value)) unaligned_member_access_result = ((VALUE *)(&is->once.value));
; unaligned_member_access_result; }), (VALUE)(val), "./vm_insnhelper.c", 4990);
 is->once.running_thread = RUNNING_THREAD_ONCE_DONE;
 return val;
    }
    else if (is->once.running_thread == th) {
 return vm_once_exec((VALUE)iseq);
    }
    else {
 rb_vm_check_ints(ec);
 rb_thread_schedule();
 goto again;
    }
}
static OFFSET
vm_case_dispatch(CDHASH hash, OFFSET else_offset, VALUE key)
{
    switch (__extension__({ VALUE arg_obj = (key); RB_SPECIAL_CONST_P(arg_obj) ? -1 : (int)RB_BUILTIN_TYPE(arg_obj); })) {
      case -1:
      case RUBY_T_FLOAT:
      case RUBY_T_SYMBOL:
      case RUBY_T_BIGNUM:
      case RUBY_T_STRING:
 if (((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_EQQ)]&((1 << 6) | (1 << 0) | (1 << 1) | (1 << 9) | (1 << 10) | (1 << 11) | (1 << 2))) == 0), 1)))) {
     st_data_t val;
     if (RB_FLOAT_TYPE_P(key)) {
  double kval = rb_float_value_inline(key);
  if (!(sizeof (kval) == sizeof (float) ? __isinff (kval) : sizeof (kval) == sizeof (double) ? __isinf (kval) : __isinfl (kval)) && modf(kval, &kval) == 0.0) {
      key = (((kval) < (0x7fffffffffffffffL / 2) + 1) && ((kval) >= ((-0x7fffffffffffffffL - 1L) / 2))) ? RB_INT2FIX((long)kval) : rb_dbl2big(kval);
  }
     }
            if (rb_hash_stlike_lookup(hash, key, &val)) {
  return rb_fix2long((VALUE)val);
     }
     else {
  return else_offset;
     }
 }
    }
    return 0;
}
__attribute__((__noreturn__)) static void vm_stack_consistency_error(const rb_execution_context_t *ec, const rb_control_frame_t *, const VALUE *);
static void
vm_stack_consistency_error(const rb_execution_context_t *ec,
      const rb_control_frame_t *cfp,
      const VALUE *bp)
{
    const ptrdiff_t nsp = ((cfp->sp) - (ec)->vm_stack);
    const ptrdiff_t nbp = ((bp) - (ec)->vm_stack);
    static const char stack_consistency_error[] =
 "Stack consistency error (sp: %""t""d"", bp: %""t""d"")";
    VALUE mesg = rb_sprintf(stack_consistency_error, nsp, nbp);
    ((__builtin_constant_p("\n") ? rbimpl_str_cat_cstr : rb_str_cat_cstr) ((mesg), ("\n")));
    rb_str_append(mesg, rb_iseq_disasm(cfp->iseq));
    rb_exc_fatal(rb_exc_new_str(rb_eFatal, mesg));
}
ALWAYS_INLINE(static inline VALUE
vm_opt_plus(VALUE recv, VALUE obj));
static inline VALUE
vm_opt_plus(VALUE recv, VALUE obj) {
    if (FIXNUM_2_P(recv, obj) &&
 ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_PLUS)]&((1 << 0))) == 0), 1)))) {
 return rb_fix_plus_fix(recv, obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_PLUS)]&((1 << 1))) == 0), 1)))) {
 return rb_float_new_inline(rb_float_value_inline(recv) + rb_float_value_inline(obj));
    }
    else if (RB_SPECIAL_CONST_P(recv) || RB_SPECIAL_CONST_P(obj)) {
 return ((VALUE)RUBY_Qundef);
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
      RBASIC_CLASS(obj) == rb_cFloat &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_PLUS)]&((1 << 1))) == 0), 1)))) {
 return rb_float_new_inline(rb_float_value_inline(recv) + rb_float_value_inline(obj));
    }
    else if (RBASIC_CLASS(recv) == rb_cString &&
      RBASIC_CLASS(obj) == rb_cString &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_PLUS)]&((1 << 2))) == 0), 1)))) {
        return rb_str_opt_plus(recv, obj);
    }
    else if (RBASIC_CLASS(recv) == rb_cArray &&
             RBASIC_CLASS(obj) == rb_cArray &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_PLUS)]&((1 << 3))) == 0), 1)))) {
 return rb_ary_plus(recv, obj);
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
ALWAYS_INLINE(static inline VALUE
vm_opt_minus(VALUE recv, VALUE obj));
static inline VALUE
vm_opt_minus(VALUE recv, VALUE obj) {
    if (FIXNUM_2_P(recv, obj) &&
 ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_MINUS)]&((1 << 0))) == 0), 1)))) {
 return rb_fix_minus_fix(recv, obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_MINUS)]&((1 << 1))) == 0), 1)))) {
 return rb_float_new_inline(rb_float_value_inline(recv) - rb_float_value_inline(obj));
    }
    else if (RB_SPECIAL_CONST_P(recv) || RB_SPECIAL_CONST_P(obj)) {
 return ((VALUE)RUBY_Qundef);
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
      RBASIC_CLASS(obj) == rb_cFloat &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_MINUS)]&((1 << 1))) == 0), 1)))) {
 return rb_float_new_inline(rb_float_value_inline(recv) - rb_float_value_inline(obj));
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
ALWAYS_INLINE(static inline VALUE
vm_opt_mult(VALUE recv, VALUE obj));
static inline VALUE
vm_opt_mult(VALUE recv, VALUE obj) {
    if (FIXNUM_2_P(recv, obj) &&
 ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_MULT)]&((1 << 0))) == 0), 1)))) {
 return rb_fix_mul_fix(recv, obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_MULT)]&((1 << 1))) == 0), 1)))) {
 return rb_float_new_inline(rb_float_value_inline(recv) * rb_float_value_inline(obj));
    }
    else if (RB_SPECIAL_CONST_P(recv) || RB_SPECIAL_CONST_P(obj)) {
 return ((VALUE)RUBY_Qundef);
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
      RBASIC_CLASS(obj) == rb_cFloat &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_MULT)]&((1 << 1))) == 0), 1)))) {
 return rb_float_new_inline(rb_float_value_inline(recv) * rb_float_value_inline(obj));
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
ALWAYS_INLINE(static inline VALUE
vm_opt_div(VALUE recv, VALUE obj));
static inline VALUE
vm_opt_div(VALUE recv, VALUE obj) {
    if (FIXNUM_2_P(recv, obj) &&
 ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_DIV)]&((1 << 0))) == 0), 1)))) {
 return (rb_fix2long(obj) == 0) ? ((VALUE)RUBY_Qundef) : rb_fix_div_fix(recv, obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_DIV)]&((1 << 1))) == 0), 1)))) {
        return rb_flo_div_flo(recv, obj);
    }
    else if (RB_SPECIAL_CONST_P(recv) || RB_SPECIAL_CONST_P(obj)) {
 return ((VALUE)RUBY_Qundef);
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
      RBASIC_CLASS(obj) == rb_cFloat &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_DIV)]&((1 << 1))) == 0), 1)))) {
        return rb_flo_div_flo(recv, obj);
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
ALWAYS_INLINE(static inline VALUE
vm_opt_mod(VALUE recv, VALUE obj));
static inline VALUE
vm_opt_mod(VALUE recv, VALUE obj) {
    if (FIXNUM_2_P(recv, obj) &&
 ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_MOD)]&((1 << 0))) == 0), 1)))) {
 return (rb_fix2long(obj) == 0) ? ((VALUE)RUBY_Qundef) : rb_fix_mod_fix(recv, obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_MOD)]&((1 << 1))) == 0), 1)))) {
 return rb_float_new_inline(ruby_float_mod(rb_float_value_inline(recv), rb_float_value_inline(obj)));
    }
    else if (RB_SPECIAL_CONST_P(recv) || RB_SPECIAL_CONST_P(obj)) {
 return ((VALUE)RUBY_Qundef);
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
      RBASIC_CLASS(obj) == rb_cFloat &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_MOD)]&((1 << 1))) == 0), 1)))) {
 return rb_float_new_inline(ruby_float_mod(rb_float_value_inline(recv), rb_float_value_inline(obj)));
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}static inline 
VALUE
rb_vm_opt_mod(VALUE recv, VALUE obj)
{
    return vm_opt_mod(recv, obj);
}
ALWAYS_INLINE(static inline VALUE
vm_opt_neq(const rb_iseq_t *iseq, CALL_DATA cd, CALL_DATA cd_eq, VALUE recv, VALUE obj));
static inline VALUE
vm_opt_neq(const rb_iseq_t *iseq, CALL_DATA cd, CALL_DATA cd_eq, VALUE recv, VALUE obj) {
    if (vm_method_cfunc_is(iseq, cd, recv, rb_obj_not_equal)) {
        VALUE val = opt_equality(iseq, recv, obj, cd_eq);
 if (val != ((VALUE)RUBY_Qundef)) {
     return RB_TEST(val) ? ((VALUE)RUBY_Qfalse) : ((VALUE)RUBY_Qtrue);
 }
    }
    return ((VALUE)RUBY_Qundef);
}
ALWAYS_INLINE(static inline VALUE
vm_opt_lt(VALUE recv, VALUE obj));
static inline VALUE
vm_opt_lt(VALUE recv, VALUE obj) {
    if (FIXNUM_2_P(recv, obj) &&
 ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_LT)]&((1 << 0))) == 0), 1)))) {
 return (((long)recv < (long)obj) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
    }
    else if (FLONUM_2_P(recv, obj) &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_LT)]&((1 << 1))) == 0), 1)))) {
 return ((rb_float_value_inline(recv) < rb_float_value_inline(obj)) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
    }
    else if (RB_SPECIAL_CONST_P(recv) || RB_SPECIAL_CONST_P(obj)) {
 return ((VALUE)RUBY_Qundef);
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
      RBASIC_CLASS(obj) == rb_cFloat &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_LT)]&((1 << 1))) == 0), 1)))) {
 ;
 return ((rb_float_value_inline(recv) < rb_float_value_inline(obj)) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
ALWAYS_INLINE(static inline VALUE
vm_opt_le(VALUE recv, VALUE obj));
static inline VALUE
vm_opt_le(VALUE recv, VALUE obj) {
    if (FIXNUM_2_P(recv, obj) &&
 ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_LE)]&((1 << 0))) == 0), 1)))) {
 return (((long)recv <= (long)obj) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
    }
    else if (FLONUM_2_P(recv, obj) &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_LE)]&((1 << 1))) == 0), 1)))) {
 return ((rb_float_value_inline(recv) <= rb_float_value_inline(obj)) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
    }
    else if (RB_SPECIAL_CONST_P(recv) || RB_SPECIAL_CONST_P(obj)) {
 return ((VALUE)RUBY_Qundef);
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
      RBASIC_CLASS(obj) == rb_cFloat &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_LE)]&((1 << 1))) == 0), 1)))) {
 ;
 return ((rb_float_value_inline(recv) <= rb_float_value_inline(obj)) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
ALWAYS_INLINE(static inline VALUE
vm_opt_gt(VALUE recv, VALUE obj));
static inline VALUE
vm_opt_gt(VALUE recv, VALUE obj) {
    if (FIXNUM_2_P(recv, obj) &&
 ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_GT)]&((1 << 0))) == 0), 1)))) {
 return (((long)recv > (long)obj) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
    }
    else if (FLONUM_2_P(recv, obj) &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_GT)]&((1 << 1))) == 0), 1)))) {
 return ((rb_float_value_inline(recv) > rb_float_value_inline(obj)) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
    }
    else if (RB_SPECIAL_CONST_P(recv) || RB_SPECIAL_CONST_P(obj)) {
 return ((VALUE)RUBY_Qundef);
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
      RBASIC_CLASS(obj) == rb_cFloat &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_GT)]&((1 << 1))) == 0), 1)))) {
 ;
 return ((rb_float_value_inline(recv) > rb_float_value_inline(obj)) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
ALWAYS_INLINE(static inline VALUE
vm_opt_ge(VALUE recv, VALUE obj));
static inline VALUE
vm_opt_ge(VALUE recv, VALUE obj) {
    if (FIXNUM_2_P(recv, obj) &&
 ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_GE)]&((1 << 0))) == 0), 1)))) {
 return (((long)recv >= (long)obj) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
    }
    else if (FLONUM_2_P(recv, obj) &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_GE)]&((1 << 1))) == 0), 1)))) {
 return ((rb_float_value_inline(recv) >= rb_float_value_inline(obj)) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
    }
    else if (RB_SPECIAL_CONST_P(recv) || RB_SPECIAL_CONST_P(obj)) {
 return ((VALUE)RUBY_Qundef);
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
      RBASIC_CLASS(obj) == rb_cFloat &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_GE)]&((1 << 1))) == 0), 1)))) {
 ;
 return ((rb_float_value_inline(recv) >= rb_float_value_inline(obj)) ? ((VALUE)RUBY_Qtrue) : ((VALUE)RUBY_Qfalse));
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
ALWAYS_INLINE(static inline VALUE
vm_opt_ltlt(VALUE recv, VALUE obj));
static inline VALUE
vm_opt_ltlt(VALUE recv, VALUE obj) {
    if (RB_SPECIAL_CONST_P(recv)) {
 return ((VALUE)RUBY_Qundef);
    }
    else if (RBASIC_CLASS(recv) == rb_cString &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_LTLT)]&((1 << 2))) == 0), 1)))) {
 return rb_str_concat(recv, obj);
    }
    else if (RBASIC_CLASS(recv) == rb_cArray &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_LTLT)]&((1 << 3))) == 0), 1)))) {
 return rb_ary_push(recv, obj);
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
ALWAYS_INLINE(static inline VALUE
vm_opt_and(VALUE recv, VALUE obj));
static inline VALUE
vm_opt_and(VALUE recv, VALUE obj) {
    if (FIXNUM_2_P(recv, obj) &&
        ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_AND)]&((1 << 0))) == 0), 1)))) {
        return (recv & obj) | 1;
    }
    else {
        return ((VALUE)RUBY_Qundef);
    }
}
ALWAYS_INLINE(static inline VALUE
vm_opt_or(VALUE recv, VALUE obj));
static inline VALUE
vm_opt_or(VALUE recv, VALUE obj) {
    if (FIXNUM_2_P(recv, obj) &&
        ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_OR)]&((1 << 0))) == 0), 1)))) {
        return recv | obj;
    }
    else {
        return ((VALUE)RUBY_Qundef);
    }
}
ALWAYS_INLINE(static inline VALUE
vm_opt_aref(VALUE recv, VALUE obj));
static inline VALUE
vm_opt_aref(VALUE recv, VALUE obj) {
    if (RB_SPECIAL_CONST_P(recv)) {
        if (FIXNUM_2_P(recv, obj) &&
                ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_AREF)]&((1 << 0))) == 0), 1)))) {
            return rb_fix_aref(recv, obj);
        }
 return ((VALUE)RUBY_Qundef);
    }
    else if (RBASIC_CLASS(recv) == rb_cArray &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_AREF)]&((1 << 3))) == 0), 1)))) {
        if (RB_FIXNUM_P(obj)) {
            return rb_ary_entry_internal(recv, rb_fix2long(obj));
        }
        else {
            return rb_ary_aref1(recv, obj);
        }
    }
    else if (RBASIC_CLASS(recv) == rb_cHash &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_AREF)]&((1 << 4))) == 0), 1)))) {
 return rb_hash_aref(recv, obj);
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
ALWAYS_INLINE(static inline VALUE
vm_opt_aset(VALUE recv, VALUE obj, VALUE set));
static inline VALUE
vm_opt_aset(VALUE recv, VALUE obj, VALUE set) {
    if (RB_SPECIAL_CONST_P(recv)) {
 return ((VALUE)RUBY_Qundef);
    }
    else if (RBASIC_CLASS(recv) == rb_cArray &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_ASET)]&((1 << 3))) == 0), 1))) &&
      RB_FIXNUM_P(obj)) {
 rb_ary_store(recv, rb_fix2long(obj), set);
 return set;
    }
    else if (RBASIC_CLASS(recv) == rb_cHash &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_ASET)]&((1 << 4))) == 0), 1)))) {
 rb_hash_aset(recv, obj, set);
 return set;
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
ALWAYS_INLINE(static inline VALUE
vm_opt_aref_with(VALUE recv, VALUE key));
static inline VALUE
vm_opt_aref_with(VALUE recv, VALUE key) {
    if (!RB_SPECIAL_CONST_P(recv) && RBASIC_CLASS(recv) == rb_cHash &&
 ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_AREF)]&((1 << 4))) == 0), 1))) &&
 rb_hash_compare_by_id_p(recv) == ((VALUE)RUBY_Qfalse)) {
 return rb_hash_aref(recv, key);
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
ALWAYS_INLINE(static inline VALUE
vm_opt_aset_with(VALUE recv, VALUE key, VALUE val));
static inline VALUE
vm_opt_aset_with(VALUE recv, VALUE key, VALUE val) {
    if (!RB_SPECIAL_CONST_P(recv) && RBASIC_CLASS(recv) == rb_cHash &&
 ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_ASET)]&((1 << 4))) == 0), 1))) &&
 rb_hash_compare_by_id_p(recv) == ((VALUE)RUBY_Qfalse)) {
 return rb_hash_aset(recv, key, val);
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
static VALUE
vm_opt_length(VALUE recv, int bop)
{
    if (RB_SPECIAL_CONST_P(recv)) {
 return ((VALUE)RUBY_Qundef);
    }
    else if (RBASIC_CLASS(recv) == rb_cString &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(bop)]&((1 << 2))) == 0), 1)))) {
 if (bop == BOP_EMPTY_P) {
     return rb_long2num_inline(RSTRING_LEN(recv));
 }
 else {
     return rb_str_length(recv);
 }
    }
    else if (RBASIC_CLASS(recv) == rb_cArray &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(bop)]&((1 << 3))) == 0), 1)))) {
 return rb_long2num_inline(rb_array_len(recv));
    }
    else if (RBASIC_CLASS(recv) == rb_cHash &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(bop)]&((1 << 4))) == 0), 1)))) {
 return __builtin_choose_expr( __builtin_constant_p(RHASH_SIZE(recv)), ((VALUE)(RHASH_SIZE(recv))) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(RHASH_SIZE(recv)));
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
static VALUE
vm_opt_empty_p(VALUE recv)
{
    switch (vm_opt_length(recv, BOP_EMPTY_P)) {
      case ((VALUE)RUBY_Qundef): return ((VALUE)RUBY_Qundef);
      case __builtin_choose_expr( __builtin_constant_p(0), ((VALUE)(0)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(0)): return ((VALUE)RUBY_Qtrue);
      default: return ((VALUE)RUBY_Qfalse);
    }
}
VALUE rb_false(VALUE obj);
static VALUE
vm_opt_nil_p(const rb_iseq_t *iseq, CALL_DATA cd, VALUE recv)
{
    if (RB_NIL_P(recv) &&
        ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_NIL_P)]&((1 << 9))) == 0), 1)))) {
        return ((VALUE)RUBY_Qtrue);
    }
    else if (vm_method_cfunc_is(iseq, cd, recv, rb_false)) {
        return ((VALUE)RUBY_Qfalse);
    }
    else {
        return ((VALUE)RUBY_Qundef);
    }
}
static VALUE
fix_succ(VALUE x)
{
    switch (x) {
      case ~0UL:
        return __builtin_choose_expr( __builtin_constant_p(0), ((VALUE)(0)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(0));
      case ((~0UL)>>(int)(1)):
        return rb_uint2big(1UL << (8 * 8 - 2));
      default:
        return x + 2;
    }
}
static VALUE
vm_opt_succ(VALUE recv)
{
    if (RB_FIXNUM_P(recv) &&
 ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_SUCC)]&((1 << 0))) == 0), 1)))) {
        return fix_succ(recv);
    }
    else if (RB_SPECIAL_CONST_P(recv)) {
 return ((VALUE)RUBY_Qundef);
    }
    else if (RBASIC_CLASS(recv) == rb_cString &&
      ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_SUCC)]&((1 << 2))) == 0), 1)))) {
 return rb_str_succ(recv);
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
ALWAYS_INLINE(static inline VALUE
vm_opt_not(const rb_iseq_t *iseq, CALL_DATA cd, VALUE recv));
static inline VALUE
vm_opt_not(const rb_iseq_t *iseq, CALL_DATA cd, VALUE recv) {
    if (vm_method_cfunc_is(iseq, cd, recv, rb_obj_not)) {
 return RB_TEST(recv) ? ((VALUE)RUBY_Qfalse) : ((VALUE)RUBY_Qtrue);
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
static VALUE
vm_opt_regexpmatch2(VALUE recv, VALUE obj)
{
    if (RB_SPECIAL_CONST_P(recv)) {
        return ((VALUE)RUBY_Qundef);
    }
    else if (RBASIC_CLASS(recv) == rb_cString &&
        rb_class_of(obj) == rb_cRegexp &&
 ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_MATCH)]&((1 << 2))) == 0), 1)))) {
 return rb_reg_match(obj, recv);
    }
    else if (RBASIC_CLASS(recv) == rb_cRegexp &&
        ((__builtin_expect(!!((rb_current_vm()->redefined_flag[(BOP_MATCH)]&((1 << 8))) == 0), 1)))) {
 return rb_reg_match(recv, obj);
    }
    else {
 return ((VALUE)RUBY_Qundef);
    }
}
rb_event_flag_t rb_iseq_event_flags(const rb_iseq_t *iseq, size_t pos);
__attribute__((__noinline__)) static void vm_trace(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp);
static inline void
vm_trace_hook(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, const VALUE *pc,
              rb_event_flag_t pc_events, rb_event_flag_t target_event,
              rb_hook_list_t *global_hooks, rb_hook_list_t *local_hooks, VALUE val)
{
    rb_event_flag_t event = pc_events & target_event;
    VALUE self = (((((reg_cfp)))->self));
    ((void)0);
    if (event & global_hooks->events) {
        reg_cfp->pc++;
        vm_dtrace(event, ec);
        rb_exec_event_hook_orig(ec, global_hooks, event, self, 0, 0, 0 , val, 0);
        reg_cfp->pc--;
    }
    if (local_hooks != ((void *)0)) {
        if (event & local_hooks->events) {
            reg_cfp->pc++;
            rb_exec_event_hook_orig(ec, local_hooks, event, self, 0, 0, 0 , val, 0);
            reg_cfp->pc--;
        }
    }
}static inline 
_Bool
rb_vm_opt_cfunc_p(CALL_CACHE cc, int insn)
{
    switch (insn) {
      case YARVINSN_opt_eq:
        return check_cfunc(vm_cc_cme(cc), rb_obj_equal);
      case YARVINSN_opt_nil_p:
        return check_cfunc(vm_cc_cme(cc), rb_false);
      case YARVINSN_opt_not:
        return check_cfunc(vm_cc_cme(cc), rb_obj_not);
      default:
        return 0;
    }
}
static void
vm_trace(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp)
{
    const VALUE *pc = reg_cfp->pc;
    rb_event_flag_t enabled_flags = ruby_vm_event_flags & (0x0001 | 0x0002 | 0x0004 | 0x0008 | 0x0010| 0x0020| 0x0040| 0x0100| 0x0200| 0x010000| 0x020000);
    rb_event_flag_t global_events = enabled_flags;
    if (enabled_flags == 0 && ruby_vm_event_local_num == 0) {
        return;
    }
    else {
 const rb_iseq_t *iseq = reg_cfp->iseq;
 size_t pos = pc - iseq->body->iseq_encoded;
        rb_event_flag_t pc_events = rb_iseq_event_flags(iseq, pos);
        rb_hook_list_t *local_hooks = iseq->aux.exec.local_hooks;
        rb_event_flag_t iseq_local_events = local_hooks != ((void *)0) ? local_hooks->events : 0;
        rb_hook_list_t *bmethod_local_hooks = ((void *)0);
        rb_event_flag_t bmethod_local_events = 0;
        _Bool bmethod_frame = VM_FRAME_BMETHOD_P(reg_cfp);
        enabled_flags |= iseq_local_events;
        ((void)0);
        if (bmethod_frame) {
            const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(reg_cfp);
            ((void)0);
            bmethod_local_hooks = me->def->body.bmethod.hooks;
            if (bmethod_local_hooks) {
                bmethod_local_events = bmethod_local_hooks->events;
            }
        }
        if ((pc_events & enabled_flags) == 0 && !bmethod_frame) {
     return;
        }
        else if (ec->trace_arg != ((void *)0)) {
            return;
        }
        else {
            rb_hook_list_t *global_hooks = rb_ec_ractor_hooks(ec);
            rb_event_flag_t bmethod_events = global_events | bmethod_local_events;
            if (0) {
                ruby_debug_printf("vm_trace>>%4d (%4x) - %s:%d %s\n",
                                  (int)pos,
                                  (int)pc_events,
                                  RSTRING_PTR(rb_iseq_path(iseq)),
                                  (int)rb_iseq_line_no(iseq, pos),
                                  RSTRING_PTR(rb_iseq_label(iseq)));
            }
            ((void)0);
            ((void)0);
            if ((pc_events & 0x0100) && bmethod_frame && (bmethod_events & 0x0008)) {
                vm_trace_hook(ec, reg_cfp, pc, 0x0008, 0x0008, global_hooks, bmethod_local_hooks, ((VALUE)RUBY_Qundef));
            }
            do { if ((pc_events & (0x0002 | 0x0008 | 0x0100)) & enabled_flags) { vm_trace_hook(ec, reg_cfp, pc, pc_events, (0x0002 | 0x0008 | 0x0100), global_hooks, local_hooks, (((VALUE)RUBY_Qundef))); } } while (0);
            do { if ((pc_events & (0x0001)) & enabled_flags) { vm_trace_hook(ec, reg_cfp, pc, pc_events, (0x0001), global_hooks, local_hooks, (((VALUE)RUBY_Qundef))); } } while (0);
            do { if ((pc_events & (0x010000)) & enabled_flags) { vm_trace_hook(ec, reg_cfp, pc, pc_events, (0x010000), global_hooks, local_hooks, (((VALUE)RUBY_Qundef))); } } while (0);
            do { if ((pc_events & (0x020000)) & enabled_flags) { vm_trace_hook(ec, reg_cfp, pc, pc_events, (0x020000), global_hooks, local_hooks, (((VALUE)RUBY_Qundef))); } } while (0);
            do { if ((pc_events & (0x0004 | 0x0010 | 0x0200)) & enabled_flags) { vm_trace_hook(ec, reg_cfp, pc, pc_events, (0x0004 | 0x0010 | 0x0200), global_hooks, local_hooks, ((*(((((reg_cfp)->sp)))-(0)-1)))); } } while (0);
            if ((pc_events & 0x0200) && bmethod_frame && (bmethod_events & 0x0010)) {
                vm_trace_hook(ec, reg_cfp, pc, 0x0010, 0x0010, global_hooks, bmethod_local_hooks, (*(((((reg_cfp)->sp)))-(0)-1)));
            }
        }
    }
}static inline 
void Init_vm_stack_canary(void) { }
static VALUE
builtin_invoker0(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr0_t)(rb_execution_context_t *ec, VALUE self);
    return (*(rb_invoke_funcptr0_t)funcptr)(ec, self);
}
static VALUE
builtin_invoker1(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr1_t)(rb_execution_context_t *ec, VALUE self, VALUE v1);
    return (*(rb_invoke_funcptr1_t)funcptr)(ec, self, argv[0]);
}
static VALUE
builtin_invoker2(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr2_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2);
    return (*(rb_invoke_funcptr2_t)funcptr)(ec, self, argv[0], argv[1]);
}
static VALUE
builtin_invoker3(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr3_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3);
    return (*(rb_invoke_funcptr3_t)funcptr)(ec, self, argv[0], argv[1], argv[2]);
}
static VALUE
builtin_invoker4(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr4_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4);
    return (*(rb_invoke_funcptr4_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3]);
}
static VALUE
builtin_invoker5(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr5_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5);
    return (*(rb_invoke_funcptr5_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4]);
}
static VALUE
builtin_invoker6(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr6_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6);
    return (*(rb_invoke_funcptr6_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}
static VALUE
builtin_invoker7(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr7_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7);
    return (*(rb_invoke_funcptr7_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]);
}
static VALUE
builtin_invoker8(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr8_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7, VALUE v8);
    return (*(rb_invoke_funcptr8_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7]);
}
static VALUE
builtin_invoker9(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr9_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7, VALUE v8, VALUE v9);
    return (*(rb_invoke_funcptr9_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8]);
}
static VALUE
builtin_invoker10(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr10_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7, VALUE v8, VALUE v9, VALUE v10);
    return (*(rb_invoke_funcptr10_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9]);
}
static VALUE
builtin_invoker11(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr11_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7, VALUE v8, VALUE v9, VALUE v10, VALUE v11);
    return (*(rb_invoke_funcptr11_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10]);
}
static VALUE
builtin_invoker12(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr12_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7, VALUE v8, VALUE v9, VALUE v10, VALUE v11, VALUE v12);
    return (*(rb_invoke_funcptr12_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11]);
}
static VALUE
builtin_invoker13(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr13_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7, VALUE v8, VALUE v9, VALUE v10, VALUE v11, VALUE v12, VALUE v13);
    return (*(rb_invoke_funcptr13_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12]);
}
static VALUE
builtin_invoker14(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr14_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7, VALUE v8, VALUE v9, VALUE v10, VALUE v11, VALUE v12, VALUE v13, VALUE v14);
    return (*(rb_invoke_funcptr14_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12], argv[13]);
}
static VALUE
builtin_invoker15(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr15_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7, VALUE v8, VALUE v9, VALUE v10, VALUE v11, VALUE v12, VALUE v13, VALUE v14, VALUE v15);
    return (*(rb_invoke_funcptr15_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12], argv[13], argv[14]);
}
typedef VALUE (*builtin_invoker)(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr);
static builtin_invoker
lookup_builtin_invoker(int argc)
{
    static const builtin_invoker invokers[] = {
        builtin_invoker0,
        builtin_invoker1,
        builtin_invoker2,
        builtin_invoker3,
        builtin_invoker4,
        builtin_invoker5,
        builtin_invoker6,
        builtin_invoker7,
        builtin_invoker8,
        builtin_invoker9,
        builtin_invoker10,
        builtin_invoker11,
        builtin_invoker12,
        builtin_invoker13,
        builtin_invoker14,
        builtin_invoker15,
    };
    return invokers[argc];
}
static inline VALUE
invoke_bf(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, const struct rb_builtin_function* bf, const VALUE *argv)
{
    const _Bool canary_p = reg_cfp->iseq->body->builtin_inline_p;
    if (canary_p) {} else {};
    VALUE ret = (*lookup_builtin_invoker(bf->argc))(ec, reg_cfp->self, argv, (rb_insn_func_t)bf->func_ptr);
    if (canary_p) {(void)(YARVINSN_invokebuiltin);};
    return ret;
}
static VALUE
vm_invoke_builtin(rb_execution_context_t *ec, rb_control_frame_t *cfp, const struct rb_builtin_function* bf, const VALUE *argv)
{
    return invoke_bf(ec, cfp, bf, argv);
}
static VALUE
vm_invoke_builtin_delegate(rb_execution_context_t *ec, rb_control_frame_t *cfp, const struct rb_builtin_function *bf, unsigned int start_index)
{
    if (0) {
        fputs("vm_invoke_builtin_delegate: passing -> ", stderr);
        for (int i=0; i<bf->argc; i++) {
            ruby_debug_printf(":%s ", rb_id2name(cfp->iseq->body->local_table[i+start_index]));
        }
        ruby_debug_printf("\n" "%s %s(%d):%p\n", __func__, bf->name, bf->argc, bf->func_ptr);
    }
    if (bf->argc == 0) {
        return invoke_bf(ec, cfp, bf, ((void *)0));
    }
    else {
        const VALUE *argv = cfp->ep - cfp->iseq->body->local_table_size - ( 3) + 1 + start_index;
        return invoke_bf(ec, cfp, bf, argv);
    }
}static inline 
VALUE
rb_vm_lvar_exposed(rb_execution_context_t *ec, int index)
{
    const rb_control_frame_t *cfp = ec->cfp;
    return cfp->ep[index];
}
struct local_var_list {
    VALUE tbl;
};
static inline VALUE method_missing(rb_execution_context_t *ec, VALUE obj, ID id, int argc, const VALUE *argv, enum method_missing_reason call_status, int kw_splat);
static inline VALUE vm_yield_with_cref(rb_execution_context_t *ec, int argc, const VALUE *argv, int kw_splat, const rb_cref_t *cref, int is_lambda);
static inline VALUE vm_yield(rb_execution_context_t *ec, int argc, const VALUE *argv, int kw_splat);
static inline VALUE vm_yield_with_block(rb_execution_context_t *ec, int argc, const VALUE *argv, VALUE block_handler, int kw_splat);
static inline VALUE vm_yield_force_blockarg(rb_execution_context_t *ec, VALUE args);
VALUE rb_vm_exec(rb_execution_context_t *ec, _Bool mjit_enable_p);
static void vm_set_eval_stack(rb_execution_context_t * th, const rb_iseq_t *iseq, const rb_cref_t *cref, const struct rb_block *base_block);
static int vm_collect_local_variables_in_heap(const VALUE *dfp, const struct local_var_list *vars);
static VALUE rb_eUncaughtThrow;
static ID id_result, id_tag, id_value;
typedef enum call_type {
    CALL_PUBLIC,
    CALL_FCALL,
    CALL_VCALL,
    CALL_PUBLIC_KW,
    CALL_FCALL_KW,
    CALL_TYPE_MAX
} call_type;
static VALUE send_internal(int argc, const VALUE *argv, VALUE recv, call_type scope);
static VALUE vm_call0_body(rb_execution_context_t* ec, struct rb_calling_info *calling, const VALUE *argv);
static inline void
stack_check(rb_execution_context_t *ec)
{
    if (!(((ec)->raised_flag & (RAISED_STACKOVERFLOW)) != 0) &&
 rb_ec_stack_check(ec)) {
 ((ec)->raised_flag |= (RAISED_STACKOVERFLOW));
 rb_ec_stack_overflow(ec, 0);
    }
}
static void
raise_method_missing(rb_execution_context_t *ec, int argc, const VALUE *argv, VALUE obj,
       enum method_missing_reason last_call_status)
{
    VALUE exc = rb_eNoMethodError;
    VALUE format = 0;
    if ((__builtin_expect(!!(argc == 0), 0))) {
 rb_raise(rb_eArgError, "no method name given");
    }
    else if ((__builtin_expect(!!(!RB_SYMBOL_P(argv[0])), 0))) {
 const VALUE e = rb_eArgError;
 rb_raise(e, "method name must be a Symbol but %""l""i" "\v"" is given",
   rb_obj_class(argv[0]));
    }
    stack_check(ec);
    if (last_call_status & MISSING_PRIVATE) {
 format = rb_fstring_new(("private method `%s' called for %s%s%s"), (sizeof("private method `%s' called for %s%s%s" "") - 1));
    }
    else if (last_call_status & MISSING_PROTECTED) {
 format = rb_fstring_new(("protected method `%s' called for %s%s%s"), (sizeof("protected method `%s' called for %s%s%s" "") - 1));
    }
    else if (last_call_status & MISSING_VCALL) {
 format = rb_fstring_new(("undefined local variable or method `%s' for %s%s%s"), (sizeof("undefined local variable or method `%s' for %s%s%s" "") - 1));
 exc = rb_eNameError;
    }
    else if (last_call_status & MISSING_SUPER) {
 format = rb_fstring_new(("super: no superclass method `%s' for %s%s%s"), (sizeof("super: no superclass method `%s' for %s%s%s" "") - 1));
    }
    {
 exc = rb_make_no_method_exception(exc, format, obj, argc, argv,
       last_call_status & (MISSING_FCALL|MISSING_VCALL));
 if (!(last_call_status & MISSING_MISSING)) {
     rb_vm_pop_cfunc_frame();
 }
 rb_exc_raise(exc);
    }
}
static void
vm_raise_method_missing(rb_execution_context_t *ec, int argc, const VALUE *argv,
   VALUE obj, int call_status)
{
    vm_passed_block_handler_set(ec, 0);
    raise_method_missing(ec, argc, argv, obj, call_status | MISSING_MISSING);
}
static inline VALUE
method_missing(rb_execution_context_t *ec, VALUE obj, ID id, int argc, const VALUE *argv, enum method_missing_reason call_status, int kw_splat)
{
    VALUE *nargv, result, work, klass;
    VALUE block_handler = vm_passed_block_handler(ec);
    const rb_callable_method_entry_t *me;
    ec->method_missing_reason = call_status;
    if (id == idMethodMissing) {
        goto missing;
    }
    nargv = ((VALUE *) (((size_t)(argc + 1) < 1024 / sizeof(VALUE)) ? ((work) = 0, __builtin_alloca ((argc + 1) * sizeof(VALUE))) : rb_alloc_tmp_buffer2(&(work), (argc + 1), sizeof(VALUE))));
    nargv[0] = rb_id2sym(id);
    if (!argv) {
        static const VALUE buf = ((VALUE)RUBY_Qfalse);
        ((void)0);
        argv = &buf;
    }
    ruby_nonempty_memcpy((nargv + 1), (argv), rbimpl_size_mul_or_raise(sizeof(VALUE), (argc)));
    ++argc;
    argv = nargv;
    klass = rb_class_of(obj);
    if (!klass) goto missing;
    me = rb_callable_method_entry(klass, idMethodMissing);
    if (!me || (int) (((me)->flags & (((VALUE)RUBY_FL_USER6) )) >> ((((VALUE)RUBY_FL_USHIFT) + 4)+2))) goto missing;
    vm_passed_block_handler_set(ec, block_handler);
    result = rb_vm_call_kw(ec, obj, idMethodMissing, argc, argv, me, kw_splat);
    if (work) rb_free_tmp_buffer(&(work));
    return result;
  missing:
    raise_method_missing(ec, argc, argv, obj, call_status | MISSING_MISSING);
    __builtin_unreachable();
}
static rb_control_frame_t *
vm_get_ruby_level_caller_cfp(const rb_execution_context_t *ec, const rb_control_frame_t *cfp)
{
    if (VM_FRAME_RUBYFRAME_P(cfp)) {
 return (rb_control_frame_t *)cfp;
    }
    cfp = ((cfp)+1);
    while (!RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(ec, cfp)) {
 if (VM_FRAME_RUBYFRAME_P(cfp)) {
     return (rb_control_frame_t *)cfp;
 }
 if (VM_ENV_FLAGS(cfp->ep, VM_FRAME_FLAG_PASSED) == 0) {
     break;
 }
 cfp = ((cfp)+1);
    }
    return 0;
}
static void
rb_vm_pop_cfunc_frame(void)
{
    rb_execution_context_t *ec = rb_current_execution_context(1);
    rb_control_frame_t *cfp = ec->cfp;
    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);
    do { const rb_event_flag_t flag_arg_ = (0x0040); rb_hook_list_t *hooks_arg_ = (rb_ec_ractor_hooks(ec)); if ((__builtin_expect(!!((hooks_arg_)->events & (flag_arg_)), 0))) { rb_exec_event_hook_orig(ec, hooks_arg_, flag_arg_, cfp->self, me->def->original_id, me->called_id, me->owner, ((VALUE)RUBY_Qnil), 0); } } while (0);
    do { if ((__builtin_expect(!!(0), 0))) { struct ruby_dtrace_method_hook_args args; if (rb_dtrace_setup(ec, me->owner, me->def->original_id, &args)) { do {} while (0); } } } while (0);
    vm_pop_frame(ec, cfp, cfp->ep);
}
static VALUE
vm_call_iseq_setup_normal_0start_0params_0locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 0, 0);
}
static VALUE
vm_call_iseq_setup_normal_0start_0params_1locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 0, 1);
}
static VALUE
vm_call_iseq_setup_normal_0start_0params_2locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 0, 2);
}
static VALUE
vm_call_iseq_setup_normal_0start_0params_3locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 0, 3);
}
static VALUE
vm_call_iseq_setup_normal_0start_0params_4locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 0, 4);
}
static VALUE
vm_call_iseq_setup_normal_0start_0params_5locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 0, 5);
}
static VALUE
vm_call_iseq_setup_normal_0start_1params_0locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 1, 0);
}
static VALUE
vm_call_iseq_setup_normal_0start_1params_1locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 1, 1);
}
static VALUE
vm_call_iseq_setup_normal_0start_1params_2locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 1, 2);
}
static VALUE
vm_call_iseq_setup_normal_0start_1params_3locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 1, 3);
}
static VALUE
vm_call_iseq_setup_normal_0start_1params_4locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 1, 4);
}
static VALUE
vm_call_iseq_setup_normal_0start_1params_5locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 1, 5);
}
static VALUE
vm_call_iseq_setup_normal_0start_2params_0locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 2, 0);
}
static VALUE
vm_call_iseq_setup_normal_0start_2params_1locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 2, 1);
}
static VALUE
vm_call_iseq_setup_normal_0start_2params_2locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 2, 2);
}
static VALUE
vm_call_iseq_setup_normal_0start_2params_3locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 2, 3);
}
static VALUE
vm_call_iseq_setup_normal_0start_2params_4locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 2, 4);
}
static VALUE
vm_call_iseq_setup_normal_0start_2params_5locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 2, 5);
}
static VALUE
vm_call_iseq_setup_normal_0start_3params_0locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 3, 0);
}
static VALUE
vm_call_iseq_setup_normal_0start_3params_1locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 3, 1);
}
static VALUE
vm_call_iseq_setup_normal_0start_3params_2locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 3, 2);
}
static VALUE
vm_call_iseq_setup_normal_0start_3params_3locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 3, 3);
}
static VALUE
vm_call_iseq_setup_normal_0start_3params_4locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 3, 4);
}
static VALUE
vm_call_iseq_setup_normal_0start_3params_5locals(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ((void)0);
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(calling->cc), 0, 3, 5);
}
static const vm_call_handler vm_call_iseq_handlers[][6] = {
    {
        vm_call_iseq_setup_normal_0start_0params_0locals,
        vm_call_iseq_setup_normal_0start_0params_1locals,
        vm_call_iseq_setup_normal_0start_0params_2locals,
        vm_call_iseq_setup_normal_0start_0params_3locals,
        vm_call_iseq_setup_normal_0start_0params_4locals,
        vm_call_iseq_setup_normal_0start_0params_5locals,
    },
    {
        vm_call_iseq_setup_normal_0start_1params_0locals,
        vm_call_iseq_setup_normal_0start_1params_1locals,
        vm_call_iseq_setup_normal_0start_1params_2locals,
        vm_call_iseq_setup_normal_0start_1params_3locals,
        vm_call_iseq_setup_normal_0start_1params_4locals,
        vm_call_iseq_setup_normal_0start_1params_5locals,
    },
    {
        vm_call_iseq_setup_normal_0start_2params_0locals,
        vm_call_iseq_setup_normal_0start_2params_1locals,
        vm_call_iseq_setup_normal_0start_2params_2locals,
        vm_call_iseq_setup_normal_0start_2params_3locals,
        vm_call_iseq_setup_normal_0start_2params_4locals,
        vm_call_iseq_setup_normal_0start_2params_5locals,
    },
    {
        vm_call_iseq_setup_normal_0start_3params_0locals,
        vm_call_iseq_setup_normal_0start_3params_1locals,
        vm_call_iseq_setup_normal_0start_3params_2locals,
        vm_call_iseq_setup_normal_0start_3params_3locals,
        vm_call_iseq_setup_normal_0start_3params_4locals,
        vm_call_iseq_setup_normal_0start_3params_5locals,
    },
};
static inline vm_call_handler
vm_call_iseq_setup_func(const struct rb_callinfo *ci, const int param_size, const int local_size)
{
    if ((__builtin_expect(!!(vm_ci_flag(ci) & (0x01 << VM_CALL_TAILCALL_bit)), 0))) {
        return &vm_call_iseq_setup_tailcall_0start;
    }
    else if (0) {
        return &vm_call_iseq_setup_normal_0start;
    }
    else if (param_size <= 3 && local_size <= 5) {
        ((void)0);
        return vm_call_iseq_handlers[param_size][local_size];
    }
    else {
        return &vm_call_iseq_setup_normal_0start;
    }
}
#define MJIT_HEADER 1
#define _FORTIFY_SOURCE 2
#define RUBY_EXPORT 1
#define vm_exec rb_vm_exec
#define RUBY_EVAL_INTERN_H 
#define RUBY_RUBY_H 1
#define RBIMPL_CONFIG_H 
#define INCLUDE_RUBY_CONFIG_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_STDINT_H 1
#define HAVE_STRINGS_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1
#define HAVE_WCHAR_H 1
#define STDC_HEADERS 1
#define _ALL_SOURCE 1
#define _DARWIN_C_SOURCE 1
#define _GNU_SOURCE 1
#define _HPUX_ALT_XOPEN_SOCKET_API 1
#define _NETBSD_SOURCE 1
#define _OPENBSD_SOURCE 1
#define _POSIX_PTHREAD_SEMANTICS 1
#define __STDC_WANT_IEC_60559_ATTRIBS_EXT__ 1
#define __STDC_WANT_IEC_60559_BFP_EXT__ 1
#define __STDC_WANT_IEC_60559_DFP_EXT__ 1
#define __STDC_WANT_IEC_60559_FUNCS_EXT__ 1
#define __STDC_WANT_IEC_60559_TYPES_EXT__ 1
#define __STDC_WANT_LIB_EXT2__ 1
#define __STDC_WANT_MATH_SPEC_FUNCS__ 1
#define _TANDEM_SOURCE 1
#define __EXTENSIONS__ 1
#define RUBY_SYMBOL_EXPORT_BEGIN _Pragma("GCC visibility push(default)")
#define RUBY_SYMBOL_EXPORT_END _Pragma("GCC visibility pop")
#define HAVE_STMT_AND_DECL_IN_EXPR 1
#define HAVE_LIBCRYPT 1
#define HAVE_LIBDL 1
#define HAVE_DIRENT_H 1
#define HAVE__BOOL 1
#define HAVE_STDBOOL_H 1
#define HAVE_SYS_WAIT_H 1
#define HAVE_GRP_H 1
#define HAVE_FCNTL_H 1
#define HAVE_FLOAT_H 1
#define HAVE_LANGINFO_H 1
#define HAVE_LIMITS_H 1
#define HAVE_LOCALE_H 1
#define HAVE_MALLOC_H 1
#define HAVE_PWD_H 1
#define HAVE_SANITIZER_ASAN_INTERFACE_H 1
#define HAVE_STDALIGN_H 1
#define HAVE_SYS_EVENTFD_H 1
#define HAVE_SYS_FCNTL_H 1
#define HAVE_SYS_FILE_H 1
#define HAVE_SYS_IOCTL_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_PRCTL_H 1
#define HAVE_SYS_RESOURCE_H 1
#define HAVE_SYS_SELECT_H 1
#define HAVE_SYS_SENDFILE_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_SYS_SYSCALL_H 1
#define HAVE_SYS_SYSMACROS_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TIMES_H 1
#define HAVE_SYS_UIO_H 1
#define HAVE_SYSCALL_H 1
#define HAVE_TIME_H 1
#define HAVE_UCONTEXT_H 1
#define HAVE_UTIME_H 1
#define HAVE_X86INTRIN_H 1
#define HAVE_X86INTRIN_H 1
#define HAVE_TYPEOF 1
#define restrict __restrict__
#define HAVE_LONG_LONG 1
#define HAVE_OFF_T 1
#define SIZEOF_INT 4
#define SIZEOF_SHORT 2
#define SIZEOF_LONG 8
#define SIZEOF_LONG_LONG 8
#define SIZEOF___INT64 0
#define SIZEOF___INT128 16
#define SIZEOF_OFF_T 8
#define SIZEOF_VOIDP 8
#define SIZEOF_FLOAT 4
#define SIZEOF_DOUBLE 8
#define SIZEOF_TIME_T 8
#define SIZEOF_CLOCK_T 8
#define PACKED_STRUCT(x) x __attribute__((packed))
#define USE_UNALIGNED_MEMBER_ACCESS 1
#define PRI_LL_PREFIX "ll"
#define HAVE_PID_T 1
#define rb_pid_t pid_t
#define SIGNEDNESS_OF_PID_T -1
#define PIDT2NUM(v) INT2NUM(v)
#define NUM2PIDT(v) NUM2INT(v)
#define PRI_PIDT_PREFIX PRI_INT_PREFIX
#define HAVE_UID_T 1
#define rb_uid_t uid_t
#define SIGNEDNESS_OF_UID_T +1
#define UIDT2NUM(v) UINT2NUM(v)
#define NUM2UIDT(v) NUM2UINT(v)
#define PRI_UIDT_PREFIX PRI_INT_PREFIX
#define HAVE_GID_T 1
#define rb_gid_t gid_t
#define SIGNEDNESS_OF_GID_T +1
#define GIDT2NUM(v) UINT2NUM(v)
#define NUM2GIDT(v) NUM2UINT(v)
#define PRI_GIDT_PREFIX PRI_INT_PREFIX
#define HAVE_TIME_T 1
#define rb_time_t time_t
#define SIGNEDNESS_OF_TIME_T -1
#define TIMET2NUM(v) LONG2NUM(v)
#define NUM2TIMET(v) NUM2LONG(v)
#define PRI_TIMET_PREFIX PRI_LONG_PREFIX
#define HAVE_DEV_T 1
#define rb_dev_t dev_t
#define SIGNEDNESS_OF_DEV_T +1
#define DEVT2NUM(v) ULONG2NUM(v)
#define NUM2DEVT(v) NUM2ULONG(v)
#define PRI_DEVT_PREFIX PRI_LONG_PREFIX
#define HAVE_MODE_T 1
#define rb_mode_t mode_t
#define SIGNEDNESS_OF_MODE_T +1
#define MODET2NUM(v) UINT2NUM(v)
#define NUM2MODET(v) NUM2UINT(v)
#define PRI_MODET_PREFIX PRI_INT_PREFIX
#define HAVE_RLIM_T 1
#define rb_rlim_t rlim_t
#define SIGNEDNESS_OF_RLIM_T +1
#define RLIM2NUM(v) ULONG2NUM(v)
#define NUM2RLIM(v) NUM2ULONG(v)
#define PRI_RLIM_PREFIX PRI_LONG_PREFIX
#define HAVE_OFF_T 1
#define rb_off_t off_t
#define SIGNEDNESS_OF_OFF_T -1
#define OFFT2NUM(v) LONG2NUM(v)
#define NUM2OFFT(v) NUM2LONG(v)
#define PRI_OFFT_PREFIX PRI_LONG_PREFIX
#define HAVE_CLOCKID_T 1
#define rb_clockid_t clockid_t
#define SIGNEDNESS_OF_CLOCKID_T -1
#define CLOCKID2NUM(v) INT2NUM(v)
#define NUM2CLOCKID(v) NUM2INT(v)
#define PRI_CLOCKID_PREFIX PRI_INT_PREFIX
#define HAVE_VA_ARGS_MACRO 1
#define HAVE__ALIGNOF 1
#define CONSTFUNC(x) __attribute__ ((__const__)) x
#define PUREFUNC(x) __attribute__ ((__pure__)) x
#define NORETURN(x) __attribute__ ((__noreturn__)) x
#define DEPRECATED(x) __attribute__ ((__deprecated__)) x
#define DEPRECATED_BY(n,x) __attribute__ ((__deprecated__("by "#n))) x
#define NOINLINE(x) __attribute__ ((__noinline__)) x
#define NO_SANITIZE(san,x) __attribute__ ((__no_sanitize__(san))) x
#define NO_SANITIZE_ADDRESS(x) __attribute__ ((__no_sanitize_address__)) x
#define NO_ADDRESS_SAFETY_ANALYSIS(x) __attribute__ ((__no_address_safety_analysis__)) x
#define WARN_UNUSED_RESULT(x) __attribute__ ((__warn_unused_result__)) x
#define MAYBE_UNUSED(x) __attribute__ ((__unused__)) x
#define ERRORFUNC(mesg,x) __attribute__ ((__error__ mesg)) x
#define WARNINGFUNC(mesg,x) __attribute__ ((__warning__ mesg)) x
#define WEAK(x) __attribute__ ((__weak__)) x
#define HAVE_FUNC_WEAK 1
#define FUNC_UNOPTIMIZED(x) __attribute__ ((__optimize__("O0"))) x
#define FUNC_MINIMIZED(x) __attribute__ ((__optimize__("-Os","-fomit-frame-pointer"))) x
#define HAVE_ATTRIBUTE_FUNCTION_ALIAS 1
#define RUBY_ALIAS_FUNCTION_TYPE(type,prot,name,args) type prot __attribute__((alias(#name)));
#define RUBY_ALIAS_FUNCTION_VOID(prot,name,args) RUBY_ALIAS_FUNCTION_TYPE(void, prot, name, args)
#define HAVE_GCC_ATOMIC_BUILTINS 1
#define HAVE_GCC_SYNC_BUILTINS 1
#define UNREACHABLE __builtin_unreachable()
#define RUBY_FUNC_EXPORTED __attribute__ ((__visibility__("default"))) extern
#define RUBY_FUNC_NONNULL(n,x) __attribute__ ((__nonnull__(n))) x
#define RUBY_FUNCTION_NAME_STRING __func__
#define ENUM_OVER_INT 1
#define HAVE_DECL_SYS_NERR 1
#define HAVE_DECL_GETENV 1
#define SIZEOF_SIZE_T 8
#define SIZEOF_PTRDIFF_T 8
#define SIZEOF_DEV_T 8
#define PRI_SIZE_PREFIX "z"
#define PRI_PTRDIFF_PREFIX "t"
#define HAVE_STRUCT_STAT_ST_BLKSIZE 1
#define HAVE_STRUCT_STAT_ST_BLOCKS 1
#define HAVE_STRUCT_STAT_ST_RDEV 1
#define SIZEOF_STRUCT_STAT_ST_SIZE SIZEOF_OFF_T
#define SIZEOF_STRUCT_STAT_ST_BLOCKS SIZEOF_OFF_T
#define SIZEOF_STRUCT_STAT_ST_INO SIZEOF_LONG
#define SIZEOF_STRUCT_STAT_ST_DEV SIZEOF_DEV_T
#define SIZEOF_STRUCT_STAT_ST_RDEV SIZEOF_DEV_T
#define HAVE_STRUCT_STAT_ST_ATIM 1
#define HAVE_STRUCT_STAT_ST_MTIM 1
#define HAVE_STRUCT_STAT_ST_CTIM 1
#define HAVE_STRUCT_TIMEVAL 1
#define SIZEOF_STRUCT_TIMEVAL_TV_SEC SIZEOF_TIME_T
#define HAVE_STRUCT_TIMESPEC 1
#define HAVE_STRUCT_TIMEZONE 1
#define HAVE_RB_FD_INIT 1
#define HAVE_INT8_T 1
#define SIZEOF_INT8_T 1
#define HAVE_UINT8_T 1
#define SIZEOF_UINT8_T 1
#define HAVE_INT16_T 1
#define SIZEOF_INT16_T 2
#define HAVE_UINT16_T 1
#define SIZEOF_UINT16_T 2
#define HAVE_INT32_T 1
#define SIZEOF_INT32_T 4
#define HAVE_UINT32_T 1
#define SIZEOF_UINT32_T 4
#define HAVE_INT64_T 1
#define SIZEOF_INT64_T 8
#define HAVE_UINT64_T 1
#define SIZEOF_UINT64_T 8
#define HAVE_INT128_T 1
#define int128_t __int128
#define SIZEOF_INT128_T SIZEOF___INT128
#define HAVE_UINT128_T 1
#define uint128_t unsigned __int128
#define SIZEOF_UINT128_T SIZEOF___INT128
#define HAVE_INTPTR_T 1
#define SIZEOF_INTPTR_T 8
#define HAVE_UINTPTR_T 1
#define SIZEOF_UINTPTR_T 8
#define HAVE_SSIZE_T 1
#define SIZEOF_SSIZE_T 8
#define STACK_END_ADDRESS __libc_stack_end
#define GETGROUPS_T gid_t
#define HAVE_ALLOCA_H 1
#define HAVE_ALLOCA 1
#define HAVE_DUP 1
#define HAVE_DUP2 1
#define HAVE_ACOSH 1
#define HAVE_CBRT 1
#define HAVE_CRYPT 1
#define HAVE_ERF 1
#define HAVE_FFS 1
#define HAVE_FLOCK 1
#define HAVE_HYPOT 1
#define HAVE_LGAMMA_R 1
#define HAVE_MEMMOVE 1
#define HAVE_NAN 1
#define HAVE_NEXTAFTER 1
#define HAVE_STRCHR 1
#define HAVE_STRERROR 1
#define HAVE_STRSTR 1
#define HAVE_TGAMMA 1
#define HAVE_ISFINITE 1
#define SPT_TYPE SPT_REUSEARGV
#define HAVE_SIGNBIT 1
#define HAVE_FORK 1
#define HAVE_VFORK 1
#define HAVE_WORKING_VFORK 1
#define HAVE_WORKING_FORK 1
#define HAVE__LONGJMP 1
#define HAVE_ATAN2L 1
#define HAVE_ATAN2F 1
#define HAVE_CHROOT 1
#define HAVE_COSH 1
#define HAVE_CRYPT_R 1
#define HAVE_DIRFD 1
#define HAVE_DL_ITERATE_PHDR 1
#define HAVE_DLOPEN 1
#define HAVE_DLADDR 1
#define HAVE_DUP3 1
#define HAVE_EACCESS 1
#define HAVE_ENDGRENT 1
#define HAVE_EVENTFD 1
#define HAVE_FCHMOD 1
#define HAVE_FCHOWN 1
#define HAVE_FCNTL 1
#define HAVE_FDATASYNC 1
#define HAVE_FDOPENDIR 1
#define HAVE_FMOD 1
#define HAVE_FSTATAT 1
#define HAVE_FSYNC 1
#define HAVE_FTRUNCATE 1
#define HAVE_FTRUNCATE64 1
#define HAVE_GETCWD 1
#define HAVE_GETGRNAM 1
#define HAVE_GETGRNAM_R 1
#define HAVE_GETGROUPS 1
#define HAVE_GETLOGIN 1
#define HAVE_GETLOGIN_R 1
#define HAVE_GETPGID 1
#define HAVE_GETPGRP 1
#define HAVE_GETPRIORITY 1
#define HAVE_GETPWNAM 1
#define HAVE_GETPWNAM_R 1
#define HAVE_GETPWUID 1
#define HAVE_GETPWUID_R 1
#define HAVE_GETRESGID 1
#define HAVE_GETRESUID 1
#define HAVE_GETRLIMIT 1
#define HAVE_GETSID 1
#define HAVE_GETTIMEOFDAY 1
#define HAVE_GMTIME_R 1
#define HAVE_GRANTPT 1
#define HAVE_INITGROUPS 1
#define HAVE_IOCTL 1
#define HAVE_KILLPG 1
#define HAVE_LCHOWN 1
#define HAVE_LINK 1
#define HAVE_LLABS 1
#define HAVE_LOCKF 1
#define HAVE_LOG2 1
#define HAVE_LSTAT 1
#define HAVE_LUTIMES 1
#define HAVE_MALLOC_USABLE_SIZE 1
#define HAVE_MBLEN 1
#define HAVE_MEMALIGN 1
#define HAVE_WRITEV 1
#define HAVE_MEMRCHR 1
#define HAVE_MEMMEM 1
#define HAVE_MKFIFO 1
#define HAVE_MKNOD 1
#define HAVE_MKTIME 1
#define HAVE_MMAP 1
#define HAVE_OPENAT 1
#define HAVE_PIPE2 1
#define HAVE_POLL 1
#define HAVE_POSIX_FADVISE 1
#define HAVE_POSIX_MEMALIGN 1
#define HAVE_PPOLL 1
#define HAVE_PREAD 1
#define HAVE_PWRITE 1
#define HAVE_QSORT_R 1
#define HAVE_READLINK 1
#define HAVE_REALPATH 1
#define HAVE_ROUND 1
#define HAVE_SCHED_GETAFFINITY 1
#define HAVE_SEEKDIR 1
#define HAVE_SENDFILE 1
#define HAVE_SETEGID 1
#define HAVE_SETENV 1
#define HAVE_SETEUID 1
#define HAVE_SETGID 1
#define HAVE_SETGROUPS 1
#define HAVE_SETPGID 1
#define HAVE_SETPGRP 1
#define HAVE_SETREGID 1
#define HAVE_SETRESGID 1
#define HAVE_SETRESUID 1
#define HAVE_SETREUID 1
#define HAVE_SETRLIMIT 1
#define HAVE_SETSID 1
#define HAVE_SETUID 1
#define HAVE_SHUTDOWN 1
#define HAVE_SIGACTION 1
#define HAVE_SIGALTSTACK 1
#define HAVE_SIGPROCMASK 1
#define HAVE_SINH 1
#define HAVE_SYMLINK 1
#define HAVE_SYSCALL 1
#define HAVE_SYSCONF 1
#define HAVE_TANH 1
#define HAVE_TELLDIR 1
#define HAVE_TIMEGM 1
#define HAVE_TIMES 1
#define HAVE_TRUNCATE 1
#define HAVE_TRUNCATE64 1
#define HAVE_UNSETENV 1
#define HAVE_UTIMENSAT 1
#define HAVE_UTIMES 1
#define HAVE_WAIT4 1
#define HAVE_WAITPID 1
#define HAVE_CRYPT_H 1
#define HAVE_STRUCT_CRYPT_DATA_INITIALIZED 1
#define HAVE_BUILTIN___BUILTIN_ALLOCA_WITH_ALIGN 1
#define HAVE_BUILTIN___BUILTIN_ASSUME_ALIGNED 1
#define HAVE_BUILTIN___BUILTIN_BSWAP16 1
#define HAVE_BUILTIN___BUILTIN_BSWAP32 1
#define HAVE_BUILTIN___BUILTIN_BSWAP64 1
#define HAVE_BUILTIN___BUILTIN_POPCOUNT 1
#define HAVE_BUILTIN___BUILTIN_POPCOUNTLL 1
#define HAVE_BUILTIN___BUILTIN_CLZ 1
#define HAVE_BUILTIN___BUILTIN_CLZL 1
#define HAVE_BUILTIN___BUILTIN_CLZLL 1
#define HAVE_BUILTIN___BUILTIN_CTZ 1
#define HAVE_BUILTIN___BUILTIN_CTZLL 1
#define HAVE_BUILTIN___BUILTIN_ADD_OVERFLOW 1
#define HAVE_BUILTIN___BUILTIN_SUB_OVERFLOW 1
#define HAVE_BUILTIN___BUILTIN_MUL_OVERFLOW 1
#define HAVE_BUILTIN___BUILTIN_MUL_OVERFLOW_P 1
#define HAVE_BUILTIN___BUILTIN_CONSTANT_P 1
#define HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR 1
#define HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P 1
#define HAVE_BUILTIN___BUILTIN_TYPES_COMPATIBLE_P 1
#define HAVE_BUILTIN___BUILTIN_TRAP 1
#define HAVE_BUILTIN___BUILTIN_EXPECT 1
#define HAVE_GNU_QSORT_R 1
#define ATAN2_INF_C99 1
#define HAVE_LIBRT 1
#define HAVE_CLOCK_GETTIME 1
#define HAVE_CLOCK_GETRES 1
#define HAVE_LIBRT 1
#define HAVE_LIBRT 1
#define HAVE_TIMER_CREATE 1
#define HAVE_TIMER_SETTIME 1
#define HAVE_STRUCT_TM_TM_ZONE 1
#define HAVE_TM_ZONE 1
#define HAVE_STRUCT_TM_TM_GMTOFF 1
#define HAVE_DAYLIGHT 1
#define NEGATIVE_TIME_T 1
#define POSIX_SIGNAL 1
#define HAVE_SIG_T 1
#define RSHIFT(x,y) ((x)>>(int)(y))
#define HAVE__SC_CLK_TCK 1
#define STACK_GROW_DIRECTION -1
#define COROUTINE_H "coroutine/amd64/Context.h"
#define _REENTRANT 1
#define _THREAD_SAFE 1
#define HAVE_LIBPTHREAD 1
#define HAVE_SCHED_YIELD 1
#define HAVE_PTHREAD_ATTR_SETINHERITSCHED 1
#define HAVE_PTHREAD_ATTR_GETSTACK 1
#define HAVE_PTHREAD_ATTR_GETGUARDSIZE 1
#define HAVE_PTHREAD_CONDATTR_SETCLOCK 1
#define HAVE_PTHREAD_SETNAME_NP 1
#define HAVE_PTHREAD_SIGMASK 1
#define HAVE_PTHREAD_GETATTR_NP 1
#define SET_CURRENT_THREAD_NAME(name) pthread_setname_np(pthread_self(), name)
#define SET_ANOTHER_THREAD_NAME(thid,name) pthread_setname_np(thid, name)
#define DEFINE_MCONTEXT_PTR(mc,uc) mcontext_t *mc = &(uc)->uc_mcontext
#define HAVE_GETCONTEXT 1
#define HAVE_SETCONTEXT 1
#define HAVE_SYS_USER_H 1
#define HAVE_CONST_PAGE_SIZE 1
#define IOCTL_REQ_TYPE unsigned long
#define NUM2IOCTLREQ(num) NUM2ULONG(num)
#define USE_ELF 1
#define HAVE_ELF_H 1
#define HAVE_LIBZ 1
#define HAVE_BACKTRACE 1
#define DLEXT_MAXLEN 3
#define DLEXT ".so"
#define EXTSTATIC 1
#define HAVE__SETJMP 1
#define RUBY_SETJMP(env) __builtin_setjmp((env))
#define RUBY_LONGJMP(env,val) __builtin_longjmp((env),val)
#define USE_MJIT 1
#define HAVE_PTHREAD_H 1
#define THREAD_IMPL_H "thread_pthread.h"
#define THREAD_IMPL_SRC "thread_pthread.c"
#define LOAD_RELATIVE 1
#define RUBY_PLATFORM "x86_64-linux"
#define RBIMPL_COMPILER_SINCE_H 
#define RBIMPL_COMPILER_IS_H 
#define RBIMPL_COMPILER_IS(cc) RBIMPL_COMPILER_IS_ ## cc
#define RBIMPL_COMPILER_IS_APPLE_H 
#define RBIMPL_COMPILER_IS_Apple 0
#define RBIMPL_COMPILER_IS_CLANG_H 
#define RBIMPL_COMPILER_IS_Clang 0
#define RBIMPL_COMPILER_IS_GCC_H 
#define RBIMPL_COMPILER_IS_INTEL_H 
#define RBIMPL_COMPILER_IS_Intel 0
#define RBIMPL_COMPILER_IS_GCC 1
#define RBIMPL_COMPILER_VERSION_MAJOR __GNUC__
#define RBIMPL_COMPILER_VERSION_MINOR __GNUC_MINOR__
#define RBIMPL_COMPILER_VERSION_PATCH __GNUC_PATCHLEVEL__
#define RBIMPL_COMPILER_IS_MSVC_H 
#define RBIMPL_COMPILER_IS_MSVC 0
#define RBIMPL_COMPILER_IS_SUNPRO_H 
#define RBIMPL_COMPILER_IS_SunPro 0
#define RBIMPL_COMPILER_SINCE(cc,x,y,z) (RBIMPL_COMPILER_IS(cc) && ((RBIMPL_COMPILER_VERSION_MAJOR > (x)) || ((RBIMPL_COMPILER_VERSION_MAJOR == (x)) && ((RBIMPL_COMPILER_VERSION_MINOR > (y)) || ((RBIMPL_COMPILER_VERSION_MINOR == (y)) && (RBIMPL_COMPILER_VERSION_PATCH >= (z)))))))
#define RBIMPL_COMPILER_BEFORE(cc,x,y,z) (RBIMPL_COMPILER_IS(cc) && ((RBIMPL_COMPILER_VERSION_MAJOR < (x)) || ((RBIMPL_COMPILER_VERSION_MAJOR == (x)) && ((RBIMPL_COMPILER_VERSION_MINOR < (y)) || ((RBIMPL_COMPILER_VERSION_MINOR == (y)) && (RBIMPL_COMPILER_VERSION_PATCH < (z)))))))
#undef HAVE_PROTOTYPES
#define HAVE_PROTOTYPES 1
#undef HAVE_STDARG_PROTOTYPES
#define HAVE_STDARG_PROTOTYPES 1
#undef TOKEN_PASTE
#define TOKEN_PASTE(x,y) x ##y
#define STRINGIZE(expr) STRINGIZE0(expr)
#define STRINGIZE0(expr) #expr
#define UNALIGNED_WORD_ACCESS 1
#define RBIMPL_TEST3(q,w,e,...) e
#define RBIMPL_TEST2(...) RBIMPL_TEST3(__VA_OPT__(,),1,0,0)
#define RBIMPL_TEST1() RBIMPL_TEST2("ruby")
#define HAVE___VA_OPT__ 
#undef RBIMPL_TEST1
#undef RBIMPL_TEST2
#undef RBIMPL_TEST3
#define USE_RVARGC 0
#define _STDARG_H 
#define _ANSI_STDARG_H_ 
#undef __need___va_list
#define __GNUC_VA_LIST 
#define va_start(v,l) __builtin_va_start(v,l)
#define va_end(v) __builtin_va_end(v)
#define va_arg(v,l) __builtin_va_arg(v,l)
#define va_copy(d,s) __builtin_va_copy(d,s)
#define __va_copy(d,s) __builtin_va_copy(d,s)
#define _VA_LIST_ 
#define _VA_LIST 
#define _VA_LIST_DEFINED 
#define _VA_LIST_T_H 
#define __va_list__ 
#define RUBY_DEFINES_H 1
#define _STDIO_H 1
#define _FEATURES_H 1
#undef __USE_ISOC99
#undef __USE_ISOC95
#undef __USE_POSIX
#undef __USE_POSIX2
#undef __USE_POSIX199309
#undef __USE_POSIX199506
#undef __USE_XOPEN
#undef __USE_XOPEN_EXTENDED
#undef __USE_UNIX98
#undef __USE_XOPEN2K
#undef __USE_XOPEN2KXSI
#undef __USE_XOPEN2K8
#undef __USE_XOPEN2K8XSI
#undef __USE_LARGEFILE
#undef __USE_LARGEFILE64
#undef __USE_FILE_OFFSET64
#undef __USE_BSD
#undef __USE_SVID
#undef __USE_MISC
#undef __USE_ATFILE
#undef __USE_GNU
#undef __USE_REENTRANT
#undef __USE_FORTIFY_LEVEL
#undef __FAVOR_BSD
#undef __KERNEL_STRICT_NAMES
#define __KERNEL_STRICT_NAMES 
#define __USE_ANSI 1
#define __GNUC_PREREQ(maj,min) ((__GNUC__ << 16) + __GNUC_MINOR__ >= ((maj) << 16) + (min))
#undef _ISOC95_SOURCE
#define _ISOC95_SOURCE 1
#undef _ISOC99_SOURCE
#define _ISOC99_SOURCE 1
#undef _POSIX_SOURCE
#define _POSIX_SOURCE 1
#undef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#undef _XOPEN_SOURCE
#define _XOPEN_SOURCE 700
#undef _XOPEN_SOURCE_EXTENDED
#define _XOPEN_SOURCE_EXTENDED 1
#undef _LARGEFILE64_SOURCE
#define _LARGEFILE64_SOURCE 1
#undef _BSD_SOURCE
#define _BSD_SOURCE 1
#undef _SVID_SOURCE
#define _SVID_SOURCE 1
#undef _ATFILE_SOURCE
#define _ATFILE_SOURCE 1
#define __USE_ISOC99 1
#define __USE_ISOC95 1
#define __USE_POSIX 1
#define __USE_POSIX2 1
#define __USE_POSIX199309 1
#define __USE_POSIX199506 1
#define __USE_XOPEN2K 1
#undef __USE_ISOC95
#define __USE_ISOC95 1
#undef __USE_ISOC99
#define __USE_ISOC99 1
#define __USE_XOPEN2K8 1
#undef _ATFILE_SOURCE
#define _ATFILE_SOURCE 1
#define __USE_XOPEN 1
#define __USE_XOPEN_EXTENDED 1
#define __USE_UNIX98 1
#undef _LARGEFILE_SOURCE
#define _LARGEFILE_SOURCE 1
#define __USE_XOPEN2K8 1
#define __USE_XOPEN2K8XSI 1
#define __USE_XOPEN2K 1
#define __USE_XOPEN2KXSI 1
#undef __USE_ISOC95
#define __USE_ISOC95 1
#undef __USE_ISOC99
#define __USE_ISOC99 1
#define __USE_LARGEFILE 1
#define __USE_LARGEFILE64 1
#define __USE_MISC 1
#define __USE_BSD 1
#define __USE_SVID 1
#define __USE_ATFILE 1
#define __USE_GNU 1
#define __USE_REENTRANT 1
#define __USE_FORTIFY_LEVEL 0
#define __STDC_IEC_559__ 1
#define __STDC_IEC_559_COMPLEX__ 1
#define __STDC_ISO_10646__ 200009L
#undef __GNU_LIBRARY__
#define __GNU_LIBRARY__ 6
#define __GLIBC__ 2
#define __GLIBC_MINOR__ 13
#define __GLIBC_PREREQ(maj,min) ((__GLIBC__ << 16) + __GLIBC_MINOR__ >= ((maj) << 16) + (min))
#define __GLIBC_HAVE_LONG_LONG 1
#define _SYS_CDEFS_H 1
#undef __P
#undef __PMT
#define __THROW __attribute__ ((__nothrow__))
#define __NTH(fct) __attribute__ ((__nothrow__)) fct
#define __P(args) args
#define __PMT(args) args
#define __CONCAT(x,y) x ## y
#define __STRING(x) #x
#define __ptr_t void *
#define __long_double_t long double
#define __BEGIN_DECLS 
#define __END_DECLS 
#define __BEGIN_NAMESPACE_STD 
#define __END_NAMESPACE_STD 
#define __USING_NAMESPACE_STD(name) 
#define __BEGIN_NAMESPACE_C99 
#define __END_NAMESPACE_C99 
#define __USING_NAMESPACE_C99(name) 
#define __bounded 
#define __unbounded 
#define __ptrvalue 
#define __bos(ptr) __builtin_object_size (ptr, __USE_FORTIFY_LEVEL > 1)
#define __bos0(ptr) __builtin_object_size (ptr, 0)
#define __warndecl(name,msg) extern void name (void) __attribute__((__warning__ (msg)))
#define __warnattr(msg) __attribute__((__warning__ (msg)))
#define __errordecl(name,msg) extern void name (void) __attribute__((__error__ (msg)))
#define __flexarr []
#define __REDIRECT(name,proto,alias) name proto __asm__ (__ASMNAME (#alias))
#define __REDIRECT_NTH(name,proto,alias) name proto __asm__ (__ASMNAME (#alias)) __THROW
#define __ASMNAME(cname) __ASMNAME2 (__USER_LABEL_PREFIX__, cname)
#define __ASMNAME2(prefix,cname) __STRING (prefix) cname
#define __attribute_malloc__ __attribute__ ((__malloc__))
#define __attribute_pure__ __attribute__ ((__pure__))
#define __attribute_used__ __attribute__ ((__used__))
#define __attribute_noinline__ __attribute__ ((__noinline__))
#define __attribute_deprecated__ __attribute__ ((__deprecated__))
#define __attribute_format_arg__(x) __attribute__ ((__format_arg__ (x)))
#define __attribute_format_strfmon__(a,b) __attribute__ ((__format__ (__strfmon__, a, b)))
#define __nonnull(params) __attribute__ ((__nonnull__ params))
#define __attribute_warn_unused_result__ __attribute__ ((__warn_unused_result__))
#define __wur 
#define __always_inline __inline __attribute__ ((__always_inline__))
#define __extern_inline extern __inline __attribute__ ((__gnu_inline__))
#define __extern_always_inline extern __always_inline __attribute__ ((__gnu_inline__, __artificial__))
#define __va_arg_pack() __builtin_va_arg_pack ()
#define __va_arg_pack_len() __builtin_va_arg_pack_len ()
#define __restrict_arr __restrict
#define __WORDSIZE 64
#define __WORDSIZE_COMPAT32 1
#define __LDBL_REDIR1(name,proto,alias) name proto
#define __LDBL_REDIR(name,proto) name proto
#define __LDBL_REDIR1_NTH(name,proto,alias) name proto __THROW
#define __LDBL_REDIR_NTH(name,proto) name proto __THROW
#define __LDBL_REDIR_DECL(name) 
#define __REDIRECT_LDBL(name,proto,alias) __REDIRECT (name, proto, alias)
#define __REDIRECT_NTH_LDBL(name,proto,alias) __REDIRECT_NTH (name, proto, alias)
#define __WORDSIZE 64
#define __WORDSIZE_COMPAT32 1
#define __stub_bdflush 
#define __stub_chflags 
#define __stub_fattach 
#define __stub_fchflags 
#define __stub_fdetach 
#define __stub_getmsg 
#define __stub_gtty 
#define __stub_lchmod 
#define __stub_putmsg 
#define __stub_revoke 
#define __stub_setlogin 
#define __stub_sigreturn 
#define __stub_sstk 
#define __stub_stty 
#define __need_size_t 
#define __need_NULL 
#define __size_t__ 
#define __SIZE_T__ 
#define _SIZE_T 
#define _SYS_SIZE_T_H 
#define _T_SIZE_ 
#define _T_SIZE 
#define __SIZE_T 
#define _SIZE_T_ 
#define _BSD_SIZE_T_ 
#define _SIZE_T_DEFINED_ 
#define _SIZE_T_DEFINED 
#define _BSD_SIZE_T_DEFINED_ 
#define _SIZE_T_DECLARED 
#define ___int_size_t_h 
#define _GCC_SIZE_T 
#define _SIZET_ 
#define __size_t 
#undef __need_size_t
#undef NULL
#define NULL ((void *)0)
#undef __need_NULL
#define _BITS_TYPES_H 1
#define __WORDSIZE 64
#define __WORDSIZE_COMPAT32 1
#define __S16_TYPE short int
#define __U16_TYPE unsigned short int
#define __S32_TYPE int
#define __U32_TYPE unsigned int
#define __SLONGWORD_TYPE long int
#define __ULONGWORD_TYPE unsigned long int
#define __SQUAD_TYPE long int
#define __UQUAD_TYPE unsigned long int
#define __SWORD_TYPE long int
#define __UWORD_TYPE unsigned long int
#define __SLONG32_TYPE int
#define __ULONG32_TYPE unsigned int
#define __S64_TYPE long int
#define __U64_TYPE unsigned long int
#define __STD_TYPE typedef
#define _BITS_TYPESIZES_H 1
#define __DEV_T_TYPE __UQUAD_TYPE
#define __UID_T_TYPE __U32_TYPE
#define __GID_T_TYPE __U32_TYPE
#define __INO_T_TYPE __ULONGWORD_TYPE
#define __INO64_T_TYPE __UQUAD_TYPE
#define __MODE_T_TYPE __U32_TYPE
#define __NLINK_T_TYPE __UWORD_TYPE
#define __OFF_T_TYPE __SLONGWORD_TYPE
#define __OFF64_T_TYPE __SQUAD_TYPE
#define __PID_T_TYPE __S32_TYPE
#define __RLIM_T_TYPE __ULONGWORD_TYPE
#define __RLIM64_T_TYPE __UQUAD_TYPE
#define __BLKCNT_T_TYPE __SLONGWORD_TYPE
#define __BLKCNT64_T_TYPE __SQUAD_TYPE
#define __FSBLKCNT_T_TYPE __ULONGWORD_TYPE
#define __FSBLKCNT64_T_TYPE __UQUAD_TYPE
#define __FSFILCNT_T_TYPE __ULONGWORD_TYPE
#define __FSFILCNT64_T_TYPE __UQUAD_TYPE
#define __ID_T_TYPE __U32_TYPE
#define __CLOCK_T_TYPE __SLONGWORD_TYPE
#define __TIME_T_TYPE __SLONGWORD_TYPE
#define __USECONDS_T_TYPE __U32_TYPE
#define __SUSECONDS_T_TYPE __SLONGWORD_TYPE
#define __DADDR_T_TYPE __S32_TYPE
#define __SWBLK_T_TYPE __SLONGWORD_TYPE
#define __KEY_T_TYPE __S32_TYPE
#define __CLOCKID_T_TYPE __S32_TYPE
#define __TIMER_T_TYPE void *
#define __BLKSIZE_T_TYPE __SLONGWORD_TYPE
#define __FSID_T_TYPE struct { int __val[2]; }
#define __SSIZE_T_TYPE __SWORD_TYPE
#define __FD_SETSIZE 1024
#undef __STD_TYPE
#define __need_FILE 
#define __need___FILE 
#define __FILE_defined 1
#undef __need_FILE
#define ____FILE_defined 1
#undef __need___FILE
#define _STDIO_USES_IOSTREAM 
#define _IO_STDIO_H 
#define _G_config_h 1
#define __need_size_t 
#define __need_NULL 
#undef __need_size_t
#undef NULL
#define NULL ((void *)0)
#undef __need_NULL
#define __need_mbstate_t 
#define __mbstate_t_defined 1
#undef __need_mbstate_t
#undef __need_mbstate_t
#undef __need_wint_t
#define _G_size_t size_t
#define _G_ssize_t __ssize_t
#define _G_off_t __off_t
#define _G_off64_t __off64_t
#define _G_pid_t __pid_t
#define _G_uid_t __uid_t
#define _G_wchar_t wchar_t
#define _G_wint_t wint_t
#define _G_stat64 stat64
#define _G_HAVE_BOOL 1
#define _G_HAVE_ATEXIT 1
#define _G_HAVE_SYS_CDEFS 1
#define _G_HAVE_SYS_WAIT 1
#define _G_NEED_STDARG_H 1
#define _G_va_list __gnuc_va_list
#define _G_HAVE_PRINTF_FP 1
#define _G_HAVE_MMAP 1
#define _G_HAVE_MREMAP 1
#define _G_HAVE_LONG_DOUBLE_IO 1
#define _G_HAVE_IO_FILE_OPEN 1
#define _G_HAVE_IO_GETLINE_INFO 1
#define _G_IO_IO_FILE_VERSION 0x20001
#define _G_OPEN64 __open64
#define _G_LSEEK64 __lseek64
#define _G_MMAP64 __mmap64
#define _G_FSTAT64(fd,buf) __fxstat64 (_STAT_VER, fd, buf)
#define _G_HAVE_ST_BLKSIZE defined (_STATBUF_ST_BLKSIZE)
#define _G_BUFSIZ 8192
#define _G_NAMES_HAVE_UNDERSCORE 0
#define _G_VTABLE_LABEL_HAS_LENGTH 1
#define _G_USING_THUNKS 1
#define _G_VTABLE_LABEL_PREFIX "__vt_"
#define _G_VTABLE_LABEL_PREFIX_ID __vt_
#define _G_ARGS(ARGLIST) ARGLIST
#define _IO_pos_t _G_fpos_t
#define _IO_fpos_t _G_fpos_t
#define _IO_fpos64_t _G_fpos64_t
#define _IO_size_t _G_size_t
#define _IO_ssize_t _G_ssize_t
#define _IO_off_t _G_off_t
#define _IO_off64_t _G_off64_t
#define _IO_pid_t _G_pid_t
#define _IO_uid_t _G_uid_t
#define _IO_iconv_t _G_iconv_t
#define _IO_HAVE_SYS_WAIT _G_HAVE_SYS_WAIT
#define _IO_HAVE_ST_BLKSIZE _G_HAVE_ST_BLKSIZE
#define _IO_BUFSIZ _G_BUFSIZ
#define _IO_va_list _G_va_list
#define _IO_wint_t _G_wint_t
#define __need___va_list 
#undef _IO_va_list
#define _IO_va_list __gnuc_va_list
#define _PARAMS(protos) __P(protos)
#define _IO_UNIFIED_JUMPTABLES 1
#define EOF (-1)
#define _IOS_INPUT 1
#define _IOS_OUTPUT 2
#define _IOS_ATEND 4
#define _IOS_APPEND 8
#define _IOS_TRUNC 16
#define _IOS_NOCREATE 32
#define _IOS_NOREPLACE 64
#define _IOS_BIN 128
#define _IO_MAGIC 0xFBAD0000
#define _OLD_STDIO_MAGIC 0xFABC0000
#define _IO_MAGIC_MASK 0xFFFF0000
#define _IO_USER_BUF 1
#define _IO_UNBUFFERED 2
#define _IO_NO_READS 4
#define _IO_NO_WRITES 8
#define _IO_EOF_SEEN 0x10
#define _IO_ERR_SEEN 0x20
#define _IO_DELETE_DONT_CLOSE 0x40
#define _IO_LINKED 0x80
#define _IO_IN_BACKUP 0x100
#define _IO_LINE_BUF 0x200
#define _IO_TIED_PUT_GET 0x400
#define _IO_CURRENTLY_PUTTING 0x800
#define _IO_IS_APPENDING 0x1000
#define _IO_IS_FILEBUF 0x2000
#define _IO_BAD_SEEN 0x4000
#define _IO_USER_LOCK 0x8000
#define _IO_FLAGS2_MMAP 1
#define _IO_FLAGS2_NOTCANCEL 2
#define _IO_FLAGS2_USER_WBUF 8
#define _IO_SKIPWS 01
#define _IO_LEFT 02
#define _IO_RIGHT 04
#define _IO_INTERNAL 010
#define _IO_DEC 020
#define _IO_OCT 040
#define _IO_HEX 0100
#define _IO_SHOWBASE 0200
#define _IO_SHOWPOINT 0400
#define _IO_UPPERCASE 01000
#define _IO_SHOWPOS 02000
#define _IO_SCIENTIFIC 04000
#define _IO_FIXED 010000
#define _IO_UNITBUF 020000
#define _IO_STDIO 040000
#define _IO_DONT_CLOSE 0100000
#define _IO_BOOLALPHA 0200000
#define _IO_file_flags _flags
#define __HAVE_COLUMN 
#define _IO_stdin ((_IO_FILE*)(&_IO_2_1_stdin_))
#define _IO_stdout ((_IO_FILE*)(&_IO_2_1_stdout_))
#define _IO_stderr ((_IO_FILE*)(&_IO_2_1_stderr_))
#define _IO_BE(expr,res) __builtin_expect ((expr), res)
#define _IO_getc_unlocked(_fp) (_IO_BE ((_fp)->_IO_read_ptr >= (_fp)->_IO_read_end, 0) ? __uflow (_fp) : *(unsigned char *) (_fp)->_IO_read_ptr++)
#define _IO_peekc_unlocked(_fp) (_IO_BE ((_fp)->_IO_read_ptr >= (_fp)->_IO_read_end, 0) && __underflow (_fp) == EOF ? EOF : *(unsigned char *) (_fp)->_IO_read_ptr)
#define _IO_putc_unlocked(_ch,_fp) (_IO_BE ((_fp)->_IO_write_ptr >= (_fp)->_IO_write_end, 0) ? __overflow (_fp, (unsigned char) (_ch)) : (unsigned char) (*(_fp)->_IO_write_ptr++ = (_ch)))
#define _IO_feof_unlocked(__fp) (((__fp)->_flags & _IO_EOF_SEEN) != 0)
#define _IO_ferror_unlocked(__fp) (((__fp)->_flags & _IO_ERR_SEEN) != 0)
#define _IO_PENDING_OUTPUT_COUNT(_fp) ((_fp)->_IO_write_ptr - (_fp)->_IO_write_base)
#define _IO_peekc(_fp) _IO_peekc_unlocked (_fp)
#define _IO_flockfile(_fp) 
#define _IO_funlockfile(_fp) 
#define _IO_ftrylockfile(_fp) 
#define _IO_cleanup_region_start(_fct,_fp) 
#define _IO_cleanup_region_end(_Doit) 
#define __off_t_defined 
#define __off64_t_defined 
#define __ssize_t_defined 
#define _IOFBF 0
#define _IOLBF 1
#define _IONBF 2
#define BUFSIZ _IO_BUFSIZ
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#define P_tmpdir "/tmp"
#define L_tmpnam 20
#define TMP_MAX 238328
#define FILENAME_MAX 4096
#define L_ctermid 9
#define L_cuserid 9
#undef FOPEN_MAX
#define FOPEN_MAX 16
#define stdin stdin
#define stdout stdout
#define stderr stderr
#define getc(_fp) _IO_getc (_fp)
#define putc(_ch,_fp) _IO_putc (_ch, _fp)
#define _SYS_TYPES_H 1
#define __u_char_defined 
#define __ino_t_defined 
#define __ino64_t_defined 
#define __dev_t_defined 
#define __gid_t_defined 
#define __mode_t_defined 
#define __nlink_t_defined 
#define __uid_t_defined 
#define __pid_t_defined 
#define __id_t_defined 
#define __daddr_t_defined 
#define __key_t_defined 
#define __need_clock_t 
#define __need_time_t 
#define __need_timer_t 
#define __need_clockid_t 
#define __clock_t_defined 1
#undef __need_clock_t
#define __time_t_defined 1
#undef __need_time_t
#define __clockid_t_defined 1
#undef __clockid_time_t
#define __timer_t_defined 1
#undef __need_timer_t
#undef __need_timespec
#define __useconds_t_defined 
#define __suseconds_t_defined 
#define __need_size_t 
#undef __need_size_t
#undef __need_NULL
#define __intN_t(N,MODE) typedef int int ##N ##_t __attribute__ ((__mode__ (MODE)))
#define __u_intN_t(N,MODE) typedef unsigned int u_int ##N ##_t __attribute__ ((__mode__ (MODE)))
#define __int8_t_defined 
#define __BIT_TYPES_DEFINED__ 1
#define _ENDIAN_H 1
#define __LITTLE_ENDIAN 1234
#define __BIG_ENDIAN 4321
#define __PDP_ENDIAN 3412
#define __BYTE_ORDER __LITTLE_ENDIAN
#define __FLOAT_WORD_ORDER __BYTE_ORDER
#define LITTLE_ENDIAN __LITTLE_ENDIAN
#define BIG_ENDIAN __BIG_ENDIAN
#define PDP_ENDIAN __PDP_ENDIAN
#define BYTE_ORDER __BYTE_ORDER
#define __LONG_LONG_PAIR(HI,LO) LO, HI
#define _BITS_BYTESWAP_H 1
#define __WORDSIZE 64
#define __WORDSIZE_COMPAT32 1
#define __bswap_constant_16(x) ((unsigned short int) ((((x) >> 8) & 0xff) | (((x) & 0xff) << 8)))
#define __bswap_16(x) (__extension__ ({ register unsigned short int __v, __x = (unsigned short int) (x); if (__builtin_constant_p (__x)) __v = __bswap_constant_16 (__x); else __asm__ ("rorw $8, %w0" : "=r" (__v) : "0" (__x) : "cc"); __v; }))
#define __bswap_constant_32(x) ((((x) & 0xff000000) >> 24) | (((x) & 0x00ff0000) >> 8) | (((x) & 0x0000ff00) << 8) | (((x) & 0x000000ff) << 24))
#define __bswap_32(x) (__extension__ ({ register unsigned int __v, __x = (x); if (__builtin_constant_p (__x)) __v = __bswap_constant_32 (__x); else __asm__ ("bswap %0" : "=r" (__v) : "0" (__x)); __v; }))
#define __bswap_constant_64(x) ((((x) & 0xff00000000000000ull) >> 56) | (((x) & 0x00ff000000000000ull) >> 40) | (((x) & 0x0000ff0000000000ull) >> 24) | (((x) & 0x000000ff00000000ull) >> 8) | (((x) & 0x00000000ff000000ull) << 8) | (((x) & 0x0000000000ff0000ull) << 24) | (((x) & 0x000000000000ff00ull) << 40) | (((x) & 0x00000000000000ffull) << 56))
#define __bswap_64(x) (__extension__ ({ register unsigned long __v, __x = (x); if (__builtin_constant_p (__x)) __v = __bswap_constant_64 (__x); else __asm__ ("bswap %q0" : "=r" (__v) : "0" (__x)); __v; }))
#define htobe16(x) __bswap_16 (x)
#define htole16(x) (x)
#define be16toh(x) __bswap_16 (x)
#define le16toh(x) (x)
#define htobe32(x) __bswap_32 (x)
#define htole32(x) (x)
#define be32toh(x) __bswap_32 (x)
#define le32toh(x) (x)
#define htobe64(x) __bswap_64 (x)
#define htole64(x) (x)
#define be64toh(x) __bswap_64 (x)
#define le64toh(x) (x)
#define _SYS_SELECT_H 1
#define __WORDSIZE 64
#define __WORDSIZE_COMPAT32 1
#define __FD_ZERO_STOS "stosq"
#define __FD_ZERO(fdsp) do { int __d0, __d1; __asm__ __volatile__ ("cld; rep; " __FD_ZERO_STOS : "=c" (__d0), "=D" (__d1) : "a" (0), "0" (sizeof (fd_set) / sizeof (__fd_mask)), "1" (&__FDS_BITS (fdsp)[0]) : "memory"); } while (0)
#define __FD_SET(d,set) ((void) (__FDS_BITS (set)[__FDELT (d)] |= __FDMASK (d)))
#define __FD_CLR(d,set) ((void) (__FDS_BITS (set)[__FDELT (d)] &= ~__FDMASK (d)))
#define __FD_ISSET(d,set) ((__FDS_BITS (set)[__FDELT (d)] & __FDMASK (d)) != 0)
#define _SIGSET_H_types 1
#define _SIGSET_NWORDS (1024 / (8 * sizeof (unsigned long int)))
#define __sigset_t_defined 
#define __need_time_t 
#define __need_timespec 
#undef __need_clock_t
#undef __need_time_t
#undef __clockid_time_t
#undef __need_timer_t
#define __timespec_defined 1
#undef __need_timespec
#define __need_timeval 
#undef __need_timeval
#define _STRUCT_TIMEVAL 1
#undef __NFDBITS
#undef __FDELT
#undef __FDMASK
#define __NFDBITS (8 * (int) sizeof (__fd_mask))
#define __FDELT(d) ((d) / __NFDBITS)
#define __FDMASK(d) ((__fd_mask) 1 << ((d) % __NFDBITS))
#define __FDS_BITS(set) ((set)->fds_bits)
#define FD_SETSIZE __FD_SETSIZE
#define NFDBITS __NFDBITS
#define FD_SET(fd,fdsetp) __FD_SET (fd, fdsetp)
#define FD_CLR(fd,fdsetp) __FD_CLR (fd, fdsetp)
#define FD_ISSET(fd,fdsetp) __FD_ISSET (fd, fdsetp)
#define FD_ZERO(fdsetp) __FD_ZERO (fdsetp)
#define _SYS_SYSMACROS_H 1
#define major(dev) gnu_dev_major (dev)
#define minor(dev) gnu_dev_minor (dev)
#define makedev(maj,min) gnu_dev_makedev (maj, min)
#define __blksize_t_defined 
#define __blkcnt_t_defined 
#define __fsblkcnt_t_defined 
#define __fsfilcnt_t_defined 
#define _BITS_PTHREADTYPES_H 1
#define __WORDSIZE 64
#define __WORDSIZE_COMPAT32 1
#define __SIZEOF_PTHREAD_ATTR_T 56
#define __SIZEOF_PTHREAD_MUTEX_T 40
#define __SIZEOF_PTHREAD_MUTEXATTR_T 4
#define __SIZEOF_PTHREAD_COND_T 48
#define __SIZEOF_PTHREAD_CONDATTR_T 4
#define __SIZEOF_PTHREAD_RWLOCK_T 56
#define __SIZEOF_PTHREAD_RWLOCKATTR_T 8
#define __SIZEOF_PTHREAD_BARRIER_T 32
#define __SIZEOF_PTHREAD_BARRIERATTR_T 4
#define __PTHREAD_MUTEX_HAVE_PREV 1
#define _SYS_STAT_H 1
#define __need_time_t 
#define __need_timespec 
#undef __need_clock_t
#undef __need_time_t
#undef __clockid_time_t
#undef __need_timer_t
#undef __need_timespec
#define _BITS_STAT_H 1
#define _STAT_VER_KERNEL 0
#define _STAT_VER_LINUX 1
#define _MKNOD_VER_LINUX 0
#define _STAT_VER _STAT_VER_LINUX
#define st_atime st_atim.tv_sec
#define st_mtime st_mtim.tv_sec
#define st_ctime st_ctim.tv_sec
#define st_atime st_atim.tv_sec
#define st_mtime st_mtim.tv_sec
#define st_ctime st_ctim.tv_sec
#define _STATBUF_ST_BLKSIZE 
#define _STATBUF_ST_RDEV 
#define _STATBUF_ST_NSEC 
#define __S_IFMT 0170000
#define __S_IFDIR 0040000
#define __S_IFCHR 0020000
#define __S_IFBLK 0060000
#define __S_IFREG 0100000
#define __S_IFIFO 0010000
#define __S_IFLNK 0120000
#define __S_IFSOCK 0140000
#define __S_TYPEISMQ(buf) ((buf)->st_mode - (buf)->st_mode)
#define __S_TYPEISSEM(buf) ((buf)->st_mode - (buf)->st_mode)
#define __S_TYPEISSHM(buf) ((buf)->st_mode - (buf)->st_mode)
#define __S_ISUID 04000
#define __S_ISGID 02000
#define __S_ISVTX 01000
#define __S_IREAD 0400
#define __S_IWRITE 0200
#define __S_IEXEC 0100
#define UTIME_NOW ((1l << 30) - 1l)
#define UTIME_OMIT ((1l << 30) - 2l)
#define S_IFMT __S_IFMT
#define S_IFDIR __S_IFDIR
#define S_IFCHR __S_IFCHR
#define S_IFBLK __S_IFBLK
#define S_IFREG __S_IFREG
#define S_IFIFO __S_IFIFO
#define S_IFLNK __S_IFLNK
#define S_IFSOCK __S_IFSOCK
#define __S_ISTYPE(mode,mask) (((mode) & __S_IFMT) == (mask))
#define S_ISDIR(mode) __S_ISTYPE((mode), __S_IFDIR)
#define S_ISCHR(mode) __S_ISTYPE((mode), __S_IFCHR)
#define S_ISBLK(mode) __S_ISTYPE((mode), __S_IFBLK)
#define S_ISREG(mode) __S_ISTYPE((mode), __S_IFREG)
#define S_ISFIFO(mode) __S_ISTYPE((mode), __S_IFIFO)
#define S_ISLNK(mode) __S_ISTYPE((mode), __S_IFLNK)
#define S_ISSOCK(mode) __S_ISTYPE((mode), __S_IFSOCK)
#define S_TYPEISMQ(buf) __S_TYPEISMQ(buf)
#define S_TYPEISSEM(buf) __S_TYPEISSEM(buf)
#define S_TYPEISSHM(buf) __S_TYPEISSHM(buf)
#define S_ISUID __S_ISUID
#define S_ISGID __S_ISGID
#define S_ISVTX __S_ISVTX
#define S_IRUSR __S_IREAD
#define S_IWUSR __S_IWRITE
#define S_IXUSR __S_IEXEC
#define S_IRWXU (__S_IREAD|__S_IWRITE|__S_IEXEC)
#define S_IREAD S_IRUSR
#define S_IWRITE S_IWUSR
#define S_IEXEC S_IXUSR
#define S_IRGRP (S_IRUSR >> 3)
#define S_IWGRP (S_IWUSR >> 3)
#define S_IXGRP (S_IXUSR >> 3)
#define S_IRWXG (S_IRWXU >> 3)
#define S_IROTH (S_IRGRP >> 3)
#define S_IWOTH (S_IWGRP >> 3)
#define S_IXOTH (S_IXGRP >> 3)
#define S_IRWXO (S_IRWXG >> 3)
#define ACCESSPERMS (S_IRWXU|S_IRWXG|S_IRWXO)
#define ALLPERMS (S_ISUID|S_ISGID|S_ISVTX|S_IRWXU|S_IRWXG|S_IRWXO)
#define DEFFILEMODE (S_IRUSR|S_IWUSR|S_IRGRP|S_IWGRP|S_IROTH|S_IWOTH)
#define S_BLKSIZE 512
#define _MKNOD_VER 0
#define __need_size_t 
#define __need_wchar_t 
#define __need_NULL 
#undef __need_size_t
#define __wchar_t__ 
#define __WCHAR_T__ 
#define _WCHAR_T 
#define _T_WCHAR_ 
#define _T_WCHAR 
#define __WCHAR_T 
#define _WCHAR_T_ 
#define _BSD_WCHAR_T_ 
#define _WCHAR_T_DEFINED_ 
#define _WCHAR_T_DEFINED 
#define _WCHAR_T_H 
#define ___int_wchar_t_h 
#define __INT_WCHAR_T_H 
#define _GCC_WCHAR_T 
#define _WCHAR_T_DECLARED 
#undef _BSD_WCHAR_T_
#undef __need_wchar_t
#undef NULL
#define NULL ((void *)0)
#undef __need_NULL
#define _STDLIB_H 1
#define WNOHANG 1
#define WUNTRACED 2
#define WSTOPPED 2
#define WEXITED 4
#define WCONTINUED 8
#define WNOWAIT 0x01000000
#define __WNOTHREAD 0x20000000
#define __WALL 0x40000000
#define __WCLONE 0x80000000
#define __WEXITSTATUS(status) (((status) & 0xff00) >> 8)
#define __WTERMSIG(status) ((status) & 0x7f)
#define __WSTOPSIG(status) __WEXITSTATUS(status)
#define __WIFEXITED(status) (__WTERMSIG(status) == 0)
#define __WIFSIGNALED(status) (((signed char) (((status) & 0x7f) + 1) >> 1) > 0)
#define __WIFSTOPPED(status) (((status) & 0xff) == 0x7f)
#define __WIFCONTINUED(status) ((status) == __W_CONTINUED)
#define __WCOREDUMP(status) ((status) & __WCOREFLAG)
#define __W_EXITCODE(ret,sig) ((ret) << 8 | (sig))
#define __W_STOPCODE(sig) ((sig) << 8 | 0x7f)
#define __W_CONTINUED 0xffff
#define __WCOREFLAG 0x80
#define w_termsig __wait_terminated.__w_termsig
#define w_coredump __wait_terminated.__w_coredump
#define w_retcode __wait_terminated.__w_retcode
#define w_stopsig __wait_stopped.__w_stopsig
#define w_stopval __wait_stopped.__w_stopval
#define __WAIT_INT(status) (__extension__ (((union { __typeof(status) __in; int __i; }) { .__in = (status) }).__i))
#define __WAIT_STATUS_DEFN int *
#define WEXITSTATUS(status) __WEXITSTATUS (__WAIT_INT (status))
#define WTERMSIG(status) __WTERMSIG (__WAIT_INT (status))
#define WSTOPSIG(status) __WSTOPSIG (__WAIT_INT (status))
#define WIFEXITED(status) __WIFEXITED (__WAIT_INT (status))
#define WIFSIGNALED(status) __WIFSIGNALED (__WAIT_INT (status))
#define WIFSTOPPED(status) __WIFSTOPPED (__WAIT_INT (status))
#define WIFCONTINUED(status) __WIFCONTINUED (__WAIT_INT (status))
#define __ldiv_t_defined 1
#define __lldiv_t_defined 1
#define RAND_MAX 2147483647
#define EXIT_FAILURE 1
#define EXIT_SUCCESS 0
#define MB_CUR_MAX (__ctype_get_mb_cur_max ())
#define _XLOCALE_H 1
#define __malloc_and_calloc_defined 
#define _ALLOCA_H 1
#define __need_size_t 
#undef __need_size_t
#undef __need_NULL
#undef alloca
#define alloca(size) __builtin_alloca (size)
#define __COMPAR_FN_T 
#undef __need_malloc_and_calloc
#define _STDDEF_H 
#define _STDDEF_H_ 
#define _ANSI_STDDEF_H 
#define _PTRDIFF_T 
#define _T_PTRDIFF_ 
#define _T_PTRDIFF 
#define __PTRDIFF_T 
#define _PTRDIFF_T_ 
#define _BSD_PTRDIFF_T_ 
#define ___int_ptrdiff_t_h 
#define _GCC_PTRDIFF_T 
#define _PTRDIFF_T_DECLARED 
#undef __need_ptrdiff_t
#undef __need_size_t
#undef __need_wchar_t
#undef NULL
#define NULL ((void *)0)
#undef __need_NULL
#define offsetof(TYPE,MEMBER) __builtin_offsetof (TYPE, MEMBER)
#define _STRING_H 1
#define __need_size_t 
#define __need_NULL 
#undef __need_ptrdiff_t
#undef __need_size_t
#undef __need_wchar_t
#undef NULL
#define NULL ((void *)0)
#undef __need_NULL
#define offsetof(TYPE,MEMBER) __builtin_offsetof (TYPE, MEMBER)
#define strdupa(s) (__extension__ ({ __const char *__old = (s); size_t __len = strlen (__old) + 1; char *__new = (char *) __builtin_alloca (__len); (char *) memcpy (__new, __old, __len); }))
#define strndupa(s,n) (__extension__ ({ __const char *__old = (s); size_t __len = strnlen (__old, (n)); char *__new = (char *) __builtin_alloca (__len + 1); __new[__len] = '\0'; (char *) memcpy (__new, __old, __len); }))
#define _STRINGS_H 1
#define _INTTYPES_H 1
#define _STDINT_H 1
#define _BITS_WCHAR_H 1
#define __WCHAR_MIN (-2147483647 - 1)
#define __WCHAR_MAX (2147483647)
#define __WORDSIZE 64
#define __WORDSIZE_COMPAT32 1
#define __uint32_t_defined 
#define __intptr_t_defined 
#define __INT64_C(c) c ## L
#define __UINT64_C(c) c ## UL
#define INT8_MIN (-128)
#define INT16_MIN (-32767-1)
#define INT32_MIN (-2147483647-1)
#define INT64_MIN (-__INT64_C(9223372036854775807)-1)
#define INT8_MAX (127)
#define INT16_MAX (32767)
#define INT32_MAX (2147483647)
#define INT64_MAX (__INT64_C(9223372036854775807))
#define UINT8_MAX (255)
#define UINT16_MAX (65535)
#define UINT32_MAX (4294967295U)
#define UINT64_MAX (__UINT64_C(18446744073709551615))
#define INT_LEAST8_MIN (-128)
#define INT_LEAST16_MIN (-32767-1)
#define INT_LEAST32_MIN (-2147483647-1)
#define INT_LEAST64_MIN (-__INT64_C(9223372036854775807)-1)
#define INT_LEAST8_MAX (127)
#define INT_LEAST16_MAX (32767)
#define INT_LEAST32_MAX (2147483647)
#define INT_LEAST64_MAX (__INT64_C(9223372036854775807))
#define UINT_LEAST8_MAX (255)
#define UINT_LEAST16_MAX (65535)
#define UINT_LEAST32_MAX (4294967295U)
#define UINT_LEAST64_MAX (__UINT64_C(18446744073709551615))
#define INT_FAST8_MIN (-128)
#define INT_FAST16_MIN (-9223372036854775807L-1)
#define INT_FAST32_MIN (-9223372036854775807L-1)
#define INT_FAST64_MIN (-__INT64_C(9223372036854775807)-1)
#define INT_FAST8_MAX (127)
#define INT_FAST16_MAX (9223372036854775807L)
#define INT_FAST32_MAX (9223372036854775807L)
#define INT_FAST64_MAX (__INT64_C(9223372036854775807))
#define UINT_FAST8_MAX (255)
#define UINT_FAST16_MAX (18446744073709551615UL)
#define UINT_FAST32_MAX (18446744073709551615UL)
#define UINT_FAST64_MAX (__UINT64_C(18446744073709551615))
#define INTPTR_MIN (-9223372036854775807L-1)
#define INTPTR_MAX (9223372036854775807L)
#define UINTPTR_MAX (18446744073709551615UL)
#define INTMAX_MIN (-__INT64_C(9223372036854775807)-1)
#define INTMAX_MAX (__INT64_C(9223372036854775807))
#define UINTMAX_MAX (__UINT64_C(18446744073709551615))
#define PTRDIFF_MIN (-9223372036854775807L-1)
#define PTRDIFF_MAX (9223372036854775807L)
#define SIG_ATOMIC_MIN (-2147483647-1)
#define SIG_ATOMIC_MAX (2147483647)
#define SIZE_MAX (18446744073709551615UL)
#define WCHAR_MIN __WCHAR_MIN
#define WCHAR_MAX __WCHAR_MAX
#define WINT_MIN (0u)
#define WINT_MAX (4294967295u)
#define INT8_C(c) c
#define INT16_C(c) c
#define INT32_C(c) c
#define INT64_C(c) c ## L
#define UINT8_C(c) c
#define UINT16_C(c) c
#define UINT32_C(c) c ## U
#define UINT64_C(c) c ## UL
#define INTMAX_C(c) c ## L
#define UINTMAX_C(c) c ## UL
#define ____gwchar_t_defined 1
#define __PRI64_PREFIX "l"
#define __PRIPTR_PREFIX "l"
#define PRId8 "d"
#define PRId16 "d"
#define PRId32 "d"
#define PRId64 __PRI64_PREFIX "d"
#define PRIdLEAST8 "d"
#define PRIdLEAST16 "d"
#define PRIdLEAST32 "d"
#define PRIdLEAST64 __PRI64_PREFIX "d"
#define PRIdFAST8 "d"
#define PRIdFAST16 __PRIPTR_PREFIX "d"
#define PRIdFAST32 __PRIPTR_PREFIX "d"
#define PRIdFAST64 __PRI64_PREFIX "d"
#define PRIi8 "i"
#define PRIi16 "i"
#define PRIi32 "i"
#define PRIi64 __PRI64_PREFIX "i"
#define PRIiLEAST8 "i"
#define PRIiLEAST16 "i"
#define PRIiLEAST32 "i"
#define PRIiLEAST64 __PRI64_PREFIX "i"
#define PRIiFAST8 "i"
#define PRIiFAST16 __PRIPTR_PREFIX "i"
#define PRIiFAST32 __PRIPTR_PREFIX "i"
#define PRIiFAST64 __PRI64_PREFIX "i"
#define PRIo8 "o"
#define PRIo16 "o"
#define PRIo32 "o"
#define PRIo64 __PRI64_PREFIX "o"
#define PRIoLEAST8 "o"
#define PRIoLEAST16 "o"
#define PRIoLEAST32 "o"
#define PRIoLEAST64 __PRI64_PREFIX "o"
#define PRIoFAST8 "o"
#define PRIoFAST16 __PRIPTR_PREFIX "o"
#define PRIoFAST32 __PRIPTR_PREFIX "o"
#define PRIoFAST64 __PRI64_PREFIX "o"
#define PRIu8 "u"
#define PRIu16 "u"
#define PRIu32 "u"
#define PRIu64 __PRI64_PREFIX "u"
#define PRIuLEAST8 "u"
#define PRIuLEAST16 "u"
#define PRIuLEAST32 "u"
#define PRIuLEAST64 __PRI64_PREFIX "u"
#define PRIuFAST8 "u"
#define PRIuFAST16 __PRIPTR_PREFIX "u"
#define PRIuFAST32 __PRIPTR_PREFIX "u"
#define PRIuFAST64 __PRI64_PREFIX "u"
#define PRIx8 "x"
#define PRIx16 "x"
#define PRIx32 "x"
#define PRIx64 __PRI64_PREFIX "x"
#define PRIxLEAST8 "x"
#define PRIxLEAST16 "x"
#define PRIxLEAST32 "x"
#define PRIxLEAST64 __PRI64_PREFIX "x"
#define PRIxFAST8 "x"
#define PRIxFAST16 __PRIPTR_PREFIX "x"
#define PRIxFAST32 __PRIPTR_PREFIX "x"
#define PRIxFAST64 __PRI64_PREFIX "x"
#define PRIX8 "X"
#define PRIX16 "X"
#define PRIX32 "X"
#define PRIX64 __PRI64_PREFIX "X"
#define PRIXLEAST8 "X"
#define PRIXLEAST16 "X"
#define PRIXLEAST32 "X"
#define PRIXLEAST64 __PRI64_PREFIX "X"
#define PRIXFAST8 "X"
#define PRIXFAST16 __PRIPTR_PREFIX "X"
#define PRIXFAST32 __PRIPTR_PREFIX "X"
#define PRIXFAST64 __PRI64_PREFIX "X"
#define PRIdMAX __PRI64_PREFIX "d"
#define PRIiMAX __PRI64_PREFIX "i"
#define PRIoMAX __PRI64_PREFIX "o"
#define PRIuMAX __PRI64_PREFIX "u"
#define PRIxMAX __PRI64_PREFIX "x"
#define PRIXMAX __PRI64_PREFIX "X"
#define PRIdPTR __PRIPTR_PREFIX "d"
#define PRIiPTR __PRIPTR_PREFIX "i"
#define PRIoPTR __PRIPTR_PREFIX "o"
#define PRIuPTR __PRIPTR_PREFIX "u"
#define PRIxPTR __PRIPTR_PREFIX "x"
#define PRIXPTR __PRIPTR_PREFIX "X"
#define SCNd8 "hhd"
#define SCNd16 "hd"
#define SCNd32 "d"
#define SCNd64 __PRI64_PREFIX "d"
#define SCNdLEAST8 "hhd"
#define SCNdLEAST16 "hd"
#define SCNdLEAST32 "d"
#define SCNdLEAST64 __PRI64_PREFIX "d"
#define SCNdFAST8 "hhd"
#define SCNdFAST16 __PRIPTR_PREFIX "d"
#define SCNdFAST32 __PRIPTR_PREFIX "d"
#define SCNdFAST64 __PRI64_PREFIX "d"
#define SCNi8 "hhi"
#define SCNi16 "hi"
#define SCNi32 "i"
#define SCNi64 __PRI64_PREFIX "i"
#define SCNiLEAST8 "hhi"
#define SCNiLEAST16 "hi"
#define SCNiLEAST32 "i"
#define SCNiLEAST64 __PRI64_PREFIX "i"
#define SCNiFAST8 "hhi"
#define SCNiFAST16 __PRIPTR_PREFIX "i"
#define SCNiFAST32 __PRIPTR_PREFIX "i"
#define SCNiFAST64 __PRI64_PREFIX "i"
#define SCNu8 "hhu"
#define SCNu16 "hu"
#define SCNu32 "u"
#define SCNu64 __PRI64_PREFIX "u"
#define SCNuLEAST8 "hhu"
#define SCNuLEAST16 "hu"
#define SCNuLEAST32 "u"
#define SCNuLEAST64 __PRI64_PREFIX "u"
#define SCNuFAST8 "hhu"
#define SCNuFAST16 __PRIPTR_PREFIX "u"
#define SCNuFAST32 __PRIPTR_PREFIX "u"
#define SCNuFAST64 __PRI64_PREFIX "u"
#define SCNo8 "hho"
#define SCNo16 "ho"
#define SCNo32 "o"
#define SCNo64 __PRI64_PREFIX "o"
#define SCNoLEAST8 "hho"
#define SCNoLEAST16 "ho"
#define SCNoLEAST32 "o"
#define SCNoLEAST64 __PRI64_PREFIX "o"
#define SCNoFAST8 "hho"
#define SCNoFAST16 __PRIPTR_PREFIX "o"
#define SCNoFAST32 __PRIPTR_PREFIX "o"
#define SCNoFAST64 __PRI64_PREFIX "o"
#define SCNx8 "hhx"
#define SCNx16 "hx"
#define SCNx32 "x"
#define SCNx64 __PRI64_PREFIX "x"
#define SCNxLEAST8 "hhx"
#define SCNxLEAST16 "hx"
#define SCNxLEAST32 "x"
#define SCNxLEAST64 __PRI64_PREFIX "x"
#define SCNxFAST8 "hhx"
#define SCNxFAST16 __PRIPTR_PREFIX "x"
#define SCNxFAST32 __PRIPTR_PREFIX "x"
#define SCNxFAST64 __PRI64_PREFIX "x"
#define SCNdMAX __PRI64_PREFIX "d"
#define SCNiMAX __PRI64_PREFIX "i"
#define SCNoMAX __PRI64_PREFIX "o"
#define SCNuMAX __PRI64_PREFIX "u"
#define SCNxMAX __PRI64_PREFIX "x"
#define SCNdPTR __PRIPTR_PREFIX "d"
#define SCNiPTR __PRIPTR_PREFIX "i"
#define SCNoPTR __PRIPTR_PREFIX "o"
#define SCNuPTR __PRIPTR_PREFIX "u"
#define SCNxPTR __PRIPTR_PREFIX "x"
#define _STDALIGN_H 
#define alignas _Alignas
#define alignof _Alignof
#define __alignas_is_defined 1
#define __alignof_is_defined 1
#define _UNISTD_H 1
#define _POSIX_VERSION 200809L
#define __POSIX2_THIS_VERSION 200809L
#define _POSIX2_VERSION __POSIX2_THIS_VERSION
#define _POSIX2_C_BIND __POSIX2_THIS_VERSION
#define _POSIX2_C_DEV __POSIX2_THIS_VERSION
#define _POSIX2_SW_DEV __POSIX2_THIS_VERSION
#define _POSIX2_LOCALEDEF __POSIX2_THIS_VERSION
#define _XOPEN_VERSION 700
#define _XOPEN_XCU_VERSION 4
#define _XOPEN_XPG2 1
#define _XOPEN_XPG3 1
#define _XOPEN_XPG4 1
#define _XOPEN_UNIX 1
#define _XOPEN_CRYPT 1
#define _XOPEN_ENH_I18N 1
#define _XOPEN_LEGACY 1
#define _BITS_POSIX_OPT_H 1
#define _POSIX_JOB_CONTROL 1
#define _POSIX_SAVED_IDS 1
#define _POSIX_PRIORITY_SCHEDULING 200809L
#define _POSIX_SYNCHRONIZED_IO 200809L
#define _POSIX_FSYNC 200809L
#define _POSIX_MAPPED_FILES 200809L
#define _POSIX_MEMLOCK 200809L
#define _POSIX_MEMLOCK_RANGE 200809L
#define _POSIX_MEMORY_PROTECTION 200809L
#define _POSIX_CHOWN_RESTRICTED 0
#define _POSIX_VDISABLE '\0'
#define _POSIX_NO_TRUNC 1
#define _XOPEN_REALTIME 1
#define _XOPEN_REALTIME_THREADS 1
#define _XOPEN_SHM 1
#define _POSIX_THREADS 200809L
#define _POSIX_REENTRANT_FUNCTIONS 1
#define _POSIX_THREAD_SAFE_FUNCTIONS 200809L
#define _POSIX_THREAD_PRIORITY_SCHEDULING 200809L
#define _POSIX_THREAD_ATTR_STACKSIZE 200809L
#define _POSIX_THREAD_ATTR_STACKADDR 200809L
#define _POSIX_THREAD_PRIO_INHERIT 200809L
#define _POSIX_THREAD_PRIO_PROTECT 200809L
#define _POSIX_THREAD_ROBUST_PRIO_INHERIT 200809L
#define _POSIX_THREAD_ROBUST_PRIO_PROTECT -1
#define _POSIX_SEMAPHORES 200809L
#define _POSIX_REALTIME_SIGNALS 200809L
#define _POSIX_ASYNCHRONOUS_IO 200809L
#define _POSIX_ASYNC_IO 1
#define _LFS_ASYNCHRONOUS_IO 1
#define _POSIX_PRIORITIZED_IO 200809L
#define _LFS64_ASYNCHRONOUS_IO 1
#define _LFS_LARGEFILE 1
#define _LFS64_LARGEFILE 1
#define _LFS64_STDIO 1
#define _POSIX_SHARED_MEMORY_OBJECTS 200809L
#define _POSIX_CPUTIME 0
#define _POSIX_THREAD_CPUTIME 0
#define _POSIX_REGEXP 1
#define _POSIX_READER_WRITER_LOCKS 200809L
#define _POSIX_SHELL 1
#define _POSIX_TIMEOUTS 200809L
#define _POSIX_SPIN_LOCKS 200809L
#define _POSIX_SPAWN 200809L
#define _POSIX_TIMERS 200809L
#define _POSIX_BARRIERS 200809L
#define _POSIX_MESSAGE_PASSING 200809L
#define _POSIX_THREAD_PROCESS_SHARED 200809L
#define _POSIX_MONOTONIC_CLOCK 0
#define _POSIX_CLOCK_SELECTION 200809L
#define _POSIX_ADVISORY_INFO 200809L
#define _POSIX_IPV6 200809L
#define _POSIX_RAW_SOCKETS 200809L
#define _POSIX2_CHAR_TERM 200809L
#define _POSIX_SPORADIC_SERVER -1
#define _POSIX_THREAD_SPORADIC_SERVER -1
#define _POSIX_TRACE -1
#define _POSIX_TRACE_EVENT_FILTER -1
#define _POSIX_TRACE_INHERIT -1
#define _POSIX_TRACE_LOG -1
#define _POSIX_TYPED_MEMORY_OBJECTS -1
#define __WORDSIZE 64
#define __WORDSIZE_COMPAT32 1
#define _POSIX_V7_LPBIG_OFFBIG -1
#define _POSIX_V6_LPBIG_OFFBIG -1
#define _XBS5_LPBIG_OFFBIG -1
#define _POSIX_V7_LP64_OFF64 1
#define _POSIX_V6_LP64_OFF64 1
#define _XBS5_LP64_OFF64 1
#define __ILP32_OFF32_CFLAGS "-m32"
#define __ILP32_OFFBIG_CFLAGS "-m32 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"
#define __ILP32_OFF32_LDFLAGS "-m32"
#define __ILP32_OFFBIG_LDFLAGS "-m32"
#define __LP64_OFF64_CFLAGS "-m64"
#define __LP64_OFF64_LDFLAGS "-m64"
#define STDIN_FILENO 0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2
#define __need_size_t 
#define __need_NULL 
#undef __need_ptrdiff_t
#undef __need_size_t
#undef __need_wchar_t
#undef NULL
#define NULL ((void *)0)
#undef __need_NULL
#define offsetof(TYPE,MEMBER) __builtin_offsetof (TYPE, MEMBER)
#define __socklen_t_defined 
#define R_OK 4
#define W_OK 2
#define X_OK 1
#define F_OK 0
#define L_SET SEEK_SET
#define L_INCR SEEK_CUR
#define L_XTND SEEK_END
#define _PC_LINK_MAX _PC_LINK_MAX
#define _PC_MAX_CANON _PC_MAX_CANON
#define _PC_MAX_INPUT _PC_MAX_INPUT
#define _PC_NAME_MAX _PC_NAME_MAX
#define _PC_PATH_MAX _PC_PATH_MAX
#define _PC_PIPE_BUF _PC_PIPE_BUF
#define _PC_CHOWN_RESTRICTED _PC_CHOWN_RESTRICTED
#define _PC_NO_TRUNC _PC_NO_TRUNC
#define _PC_VDISABLE _PC_VDISABLE
#define _PC_SYNC_IO _PC_SYNC_IO
#define _PC_ASYNC_IO _PC_ASYNC_IO
#define _PC_PRIO_IO _PC_PRIO_IO
#define _PC_SOCK_MAXBUF _PC_SOCK_MAXBUF
#define _PC_FILESIZEBITS _PC_FILESIZEBITS
#define _PC_REC_INCR_XFER_SIZE _PC_REC_INCR_XFER_SIZE
#define _PC_REC_MAX_XFER_SIZE _PC_REC_MAX_XFER_SIZE
#define _PC_REC_MIN_XFER_SIZE _PC_REC_MIN_XFER_SIZE
#define _PC_REC_XFER_ALIGN _PC_REC_XFER_ALIGN
#define _PC_ALLOC_SIZE_MIN _PC_ALLOC_SIZE_MIN
#define _PC_SYMLINK_MAX _PC_SYMLINK_MAX
#define _PC_2_SYMLINKS _PC_2_SYMLINKS
#define _SC_ARG_MAX _SC_ARG_MAX
#define _SC_CHILD_MAX _SC_CHILD_MAX
#define _SC_CLK_TCK _SC_CLK_TCK
#define _SC_NGROUPS_MAX _SC_NGROUPS_MAX
#define _SC_OPEN_MAX _SC_OPEN_MAX
#define _SC_STREAM_MAX _SC_STREAM_MAX
#define _SC_TZNAME_MAX _SC_TZNAME_MAX
#define _SC_JOB_CONTROL _SC_JOB_CONTROL
#define _SC_SAVED_IDS _SC_SAVED_IDS
#define _SC_REALTIME_SIGNALS _SC_REALTIME_SIGNALS
#define _SC_PRIORITY_SCHEDULING _SC_PRIORITY_SCHEDULING
#define _SC_TIMERS _SC_TIMERS
#define _SC_ASYNCHRONOUS_IO _SC_ASYNCHRONOUS_IO
#define _SC_PRIORITIZED_IO _SC_PRIORITIZED_IO
#define _SC_SYNCHRONIZED_IO _SC_SYNCHRONIZED_IO
#define _SC_FSYNC _SC_FSYNC
#define _SC_MAPPED_FILES _SC_MAPPED_FILES
#define _SC_MEMLOCK _SC_MEMLOCK
#define _SC_MEMLOCK_RANGE _SC_MEMLOCK_RANGE
#define _SC_MEMORY_PROTECTION _SC_MEMORY_PROTECTION
#define _SC_MESSAGE_PASSING _SC_MESSAGE_PASSING
#define _SC_SEMAPHORES _SC_SEMAPHORES
#define _SC_SHARED_MEMORY_OBJECTS _SC_SHARED_MEMORY_OBJECTS
#define _SC_AIO_LISTIO_MAX _SC_AIO_LISTIO_MAX
#define _SC_AIO_MAX _SC_AIO_MAX
#define _SC_AIO_PRIO_DELTA_MAX _SC_AIO_PRIO_DELTA_MAX
#define _SC_DELAYTIMER_MAX _SC_DELAYTIMER_MAX
#define _SC_MQ_OPEN_MAX _SC_MQ_OPEN_MAX
#define _SC_MQ_PRIO_MAX _SC_MQ_PRIO_MAX
#define _SC_VERSION _SC_VERSION
#define _SC_PAGESIZE _SC_PAGESIZE
#define _SC_PAGE_SIZE _SC_PAGESIZE
#define _SC_RTSIG_MAX _SC_RTSIG_MAX
#define _SC_SEM_NSEMS_MAX _SC_SEM_NSEMS_MAX
#define _SC_SEM_VALUE_MAX _SC_SEM_VALUE_MAX
#define _SC_SIGQUEUE_MAX _SC_SIGQUEUE_MAX
#define _SC_TIMER_MAX _SC_TIMER_MAX
#define _SC_BC_BASE_MAX _SC_BC_BASE_MAX
#define _SC_BC_DIM_MAX _SC_BC_DIM_MAX
#define _SC_BC_SCALE_MAX _SC_BC_SCALE_MAX
#define _SC_BC_STRING_MAX _SC_BC_STRING_MAX
#define _SC_COLL_WEIGHTS_MAX _SC_COLL_WEIGHTS_MAX
#define _SC_EQUIV_CLASS_MAX _SC_EQUIV_CLASS_MAX
#define _SC_EXPR_NEST_MAX _SC_EXPR_NEST_MAX
#define _SC_LINE_MAX _SC_LINE_MAX
#define _SC_RE_DUP_MAX _SC_RE_DUP_MAX
#define _SC_CHARCLASS_NAME_MAX _SC_CHARCLASS_NAME_MAX
#define _SC_2_VERSION _SC_2_VERSION
#define _SC_2_C_BIND _SC_2_C_BIND
#define _SC_2_C_DEV _SC_2_C_DEV
#define _SC_2_FORT_DEV _SC_2_FORT_DEV
#define _SC_2_FORT_RUN _SC_2_FORT_RUN
#define _SC_2_SW_DEV _SC_2_SW_DEV
#define _SC_2_LOCALEDEF _SC_2_LOCALEDEF
#define _SC_PII _SC_PII
#define _SC_PII_XTI _SC_PII_XTI
#define _SC_PII_SOCKET _SC_PII_SOCKET
#define _SC_PII_INTERNET _SC_PII_INTERNET
#define _SC_PII_OSI _SC_PII_OSI
#define _SC_POLL _SC_POLL
#define _SC_SELECT _SC_SELECT
#define _SC_UIO_MAXIOV _SC_UIO_MAXIOV
#define _SC_IOV_MAX _SC_IOV_MAX
#define _SC_PII_INTERNET_STREAM _SC_PII_INTERNET_STREAM
#define _SC_PII_INTERNET_DGRAM _SC_PII_INTERNET_DGRAM
#define _SC_PII_OSI_COTS _SC_PII_OSI_COTS
#define _SC_PII_OSI_CLTS _SC_PII_OSI_CLTS
#define _SC_PII_OSI_M _SC_PII_OSI_M
#define _SC_T_IOV_MAX _SC_T_IOV_MAX
#define _SC_THREADS _SC_THREADS
#define _SC_THREAD_SAFE_FUNCTIONS _SC_THREAD_SAFE_FUNCTIONS
#define _SC_GETGR_R_SIZE_MAX _SC_GETGR_R_SIZE_MAX
#define _SC_GETPW_R_SIZE_MAX _SC_GETPW_R_SIZE_MAX
#define _SC_LOGIN_NAME_MAX _SC_LOGIN_NAME_MAX
#define _SC_TTY_NAME_MAX _SC_TTY_NAME_MAX
#define _SC_THREAD_DESTRUCTOR_ITERATIONS _SC_THREAD_DESTRUCTOR_ITERATIONS
#define _SC_THREAD_KEYS_MAX _SC_THREAD_KEYS_MAX
#define _SC_THREAD_STACK_MIN _SC_THREAD_STACK_MIN
#define _SC_THREAD_THREADS_MAX _SC_THREAD_THREADS_MAX
#define _SC_THREAD_ATTR_STACKADDR _SC_THREAD_ATTR_STACKADDR
#define _SC_THREAD_ATTR_STACKSIZE _SC_THREAD_ATTR_STACKSIZE
#define _SC_THREAD_PRIORITY_SCHEDULING _SC_THREAD_PRIORITY_SCHEDULING
#define _SC_THREAD_PRIO_INHERIT _SC_THREAD_PRIO_INHERIT
#define _SC_THREAD_PRIO_PROTECT _SC_THREAD_PRIO_PROTECT
#define _SC_THREAD_PROCESS_SHARED _SC_THREAD_PROCESS_SHARED
#define _SC_NPROCESSORS_CONF _SC_NPROCESSORS_CONF
#define _SC_NPROCESSORS_ONLN _SC_NPROCESSORS_ONLN
#define _SC_PHYS_PAGES _SC_PHYS_PAGES
#define _SC_AVPHYS_PAGES _SC_AVPHYS_PAGES
#define _SC_ATEXIT_MAX _SC_ATEXIT_MAX
#define _SC_PASS_MAX _SC_PASS_MAX
#define _SC_XOPEN_VERSION _SC_XOPEN_VERSION
#define _SC_XOPEN_XCU_VERSION _SC_XOPEN_XCU_VERSION
#define _SC_XOPEN_UNIX _SC_XOPEN_UNIX
#define _SC_XOPEN_CRYPT _SC_XOPEN_CRYPT
#define _SC_XOPEN_ENH_I18N _SC_XOPEN_ENH_I18N
#define _SC_XOPEN_SHM _SC_XOPEN_SHM
#define _SC_2_CHAR_TERM _SC_2_CHAR_TERM
#define _SC_2_C_VERSION _SC_2_C_VERSION
#define _SC_2_UPE _SC_2_UPE
#define _SC_XOPEN_XPG2 _SC_XOPEN_XPG2
#define _SC_XOPEN_XPG3 _SC_XOPEN_XPG3
#define _SC_XOPEN_XPG4 _SC_XOPEN_XPG4
#define _SC_CHAR_BIT _SC_CHAR_BIT
#define _SC_CHAR_MAX _SC_CHAR_MAX
#define _SC_CHAR_MIN _SC_CHAR_MIN
#define _SC_INT_MAX _SC_INT_MAX
#define _SC_INT_MIN _SC_INT_MIN
#define _SC_LONG_BIT _SC_LONG_BIT
#define _SC_WORD_BIT _SC_WORD_BIT
#define _SC_MB_LEN_MAX _SC_MB_LEN_MAX
#define _SC_NZERO _SC_NZERO
#define _SC_SSIZE_MAX _SC_SSIZE_MAX
#define _SC_SCHAR_MAX _SC_SCHAR_MAX
#define _SC_SCHAR_MIN _SC_SCHAR_MIN
#define _SC_SHRT_MAX _SC_SHRT_MAX
#define _SC_SHRT_MIN _SC_SHRT_MIN
#define _SC_UCHAR_MAX _SC_UCHAR_MAX
#define _SC_UINT_MAX _SC_UINT_MAX
#define _SC_ULONG_MAX _SC_ULONG_MAX
#define _SC_USHRT_MAX _SC_USHRT_MAX
#define _SC_NL_ARGMAX _SC_NL_ARGMAX
#define _SC_NL_LANGMAX _SC_NL_LANGMAX
#define _SC_NL_MSGMAX _SC_NL_MSGMAX
#define _SC_NL_NMAX _SC_NL_NMAX
#define _SC_NL_SETMAX _SC_NL_SETMAX
#define _SC_NL_TEXTMAX _SC_NL_TEXTMAX
#define _SC_XBS5_ILP32_OFF32 _SC_XBS5_ILP32_OFF32
#define _SC_XBS5_ILP32_OFFBIG _SC_XBS5_ILP32_OFFBIG
#define _SC_XBS5_LP64_OFF64 _SC_XBS5_LP64_OFF64
#define _SC_XBS5_LPBIG_OFFBIG _SC_XBS5_LPBIG_OFFBIG
#define _SC_XOPEN_LEGACY _SC_XOPEN_LEGACY
#define _SC_XOPEN_REALTIME _SC_XOPEN_REALTIME
#define _SC_XOPEN_REALTIME_THREADS _SC_XOPEN_REALTIME_THREADS
#define _SC_ADVISORY_INFO _SC_ADVISORY_INFO
#define _SC_BARRIERS _SC_BARRIERS
#define _SC_BASE _SC_BASE
#define _SC_C_LANG_SUPPORT _SC_C_LANG_SUPPORT
#define _SC_C_LANG_SUPPORT_R _SC_C_LANG_SUPPORT_R
#define _SC_CLOCK_SELECTION _SC_CLOCK_SELECTION
#define _SC_CPUTIME _SC_CPUTIME
#define _SC_THREAD_CPUTIME _SC_THREAD_CPUTIME
#define _SC_DEVICE_IO _SC_DEVICE_IO
#define _SC_DEVICE_SPECIFIC _SC_DEVICE_SPECIFIC
#define _SC_DEVICE_SPECIFIC_R _SC_DEVICE_SPECIFIC_R
#define _SC_FD_MGMT _SC_FD_MGMT
#define _SC_FIFO _SC_FIFO
#define _SC_PIPE _SC_PIPE
#define _SC_FILE_ATTRIBUTES _SC_FILE_ATTRIBUTES
#define _SC_FILE_LOCKING _SC_FILE_LOCKING
#define _SC_FILE_SYSTEM _SC_FILE_SYSTEM
#define _SC_MONOTONIC_CLOCK _SC_MONOTONIC_CLOCK
#define _SC_MULTI_PROCESS _SC_MULTI_PROCESS
#define _SC_SINGLE_PROCESS _SC_SINGLE_PROCESS
#define _SC_NETWORKING _SC_NETWORKING
#define _SC_READER_WRITER_LOCKS _SC_READER_WRITER_LOCKS
#define _SC_SPIN_LOCKS _SC_SPIN_LOCKS
#define _SC_REGEXP _SC_REGEXP
#define _SC_REGEX_VERSION _SC_REGEX_VERSION
#define _SC_SHELL _SC_SHELL
#define _SC_SIGNALS _SC_SIGNALS
#define _SC_SPAWN _SC_SPAWN
#define _SC_SPORADIC_SERVER _SC_SPORADIC_SERVER
#define _SC_THREAD_SPORADIC_SERVER _SC_THREAD_SPORADIC_SERVER
#define _SC_SYSTEM_DATABASE _SC_SYSTEM_DATABASE
#define _SC_SYSTEM_DATABASE_R _SC_SYSTEM_DATABASE_R
#define _SC_TIMEOUTS _SC_TIMEOUTS
#define _SC_TYPED_MEMORY_OBJECTS _SC_TYPED_MEMORY_OBJECTS
#define _SC_USER_GROUPS _SC_USER_GROUPS
#define _SC_USER_GROUPS_R _SC_USER_GROUPS_R
#define _SC_2_PBS _SC_2_PBS
#define _SC_2_PBS_ACCOUNTING _SC_2_PBS_ACCOUNTING
#define _SC_2_PBS_LOCATE _SC_2_PBS_LOCATE
#define _SC_2_PBS_MESSAGE _SC_2_PBS_MESSAGE
#define _SC_2_PBS_TRACK _SC_2_PBS_TRACK
#define _SC_SYMLOOP_MAX _SC_SYMLOOP_MAX
#define _SC_STREAMS _SC_STREAMS
#define _SC_2_PBS_CHECKPOINT _SC_2_PBS_CHECKPOINT
#define _SC_V6_ILP32_OFF32 _SC_V6_ILP32_OFF32
#define _SC_V6_ILP32_OFFBIG _SC_V6_ILP32_OFFBIG
#define _SC_V6_LP64_OFF64 _SC_V6_LP64_OFF64
#define _SC_V6_LPBIG_OFFBIG _SC_V6_LPBIG_OFFBIG
#define _SC_HOST_NAME_MAX _SC_HOST_NAME_MAX
#define _SC_TRACE _SC_TRACE
#define _SC_TRACE_EVENT_FILTER _SC_TRACE_EVENT_FILTER
#define _SC_TRACE_INHERIT _SC_TRACE_INHERIT
#define _SC_TRACE_LOG _SC_TRACE_LOG
#define _SC_LEVEL1_ICACHE_SIZE _SC_LEVEL1_ICACHE_SIZE
#define _SC_LEVEL1_ICACHE_ASSOC _SC_LEVEL1_ICACHE_ASSOC
#define _SC_LEVEL1_ICACHE_LINESIZE _SC_LEVEL1_ICACHE_LINESIZE
#define _SC_LEVEL1_DCACHE_SIZE _SC_LEVEL1_DCACHE_SIZE
#define _SC_LEVEL1_DCACHE_ASSOC _SC_LEVEL1_DCACHE_ASSOC
#define _SC_LEVEL1_DCACHE_LINESIZE _SC_LEVEL1_DCACHE_LINESIZE
#define _SC_LEVEL2_CACHE_SIZE _SC_LEVEL2_CACHE_SIZE
#define _SC_LEVEL2_CACHE_ASSOC _SC_LEVEL2_CACHE_ASSOC
#define _SC_LEVEL2_CACHE_LINESIZE _SC_LEVEL2_CACHE_LINESIZE
#define _SC_LEVEL3_CACHE_SIZE _SC_LEVEL3_CACHE_SIZE
#define _SC_LEVEL3_CACHE_ASSOC _SC_LEVEL3_CACHE_ASSOC
#define _SC_LEVEL3_CACHE_LINESIZE _SC_LEVEL3_CACHE_LINESIZE
#define _SC_LEVEL4_CACHE_SIZE _SC_LEVEL4_CACHE_SIZE
#define _SC_LEVEL4_CACHE_ASSOC _SC_LEVEL4_CACHE_ASSOC
#define _SC_LEVEL4_CACHE_LINESIZE _SC_LEVEL4_CACHE_LINESIZE
#define _SC_IPV6 _SC_IPV6
#define _SC_RAW_SOCKETS _SC_RAW_SOCKETS
#define _SC_V7_ILP32_OFF32 _SC_V7_ILP32_OFF32
#define _SC_V7_ILP32_OFFBIG _SC_V7_ILP32_OFFBIG
#define _SC_V7_LP64_OFF64 _SC_V7_LP64_OFF64
#define _SC_V7_LPBIG_OFFBIG _SC_V7_LPBIG_OFFBIG
#define _SC_SS_REPL_MAX _SC_SS_REPL_MAX
#define _SC_TRACE_EVENT_NAME_MAX _SC_TRACE_EVENT_NAME_MAX
#define _SC_TRACE_NAME_MAX _SC_TRACE_NAME_MAX
#define _SC_TRACE_SYS_MAX _SC_TRACE_SYS_MAX
#define _SC_TRACE_USER_EVENT_MAX _SC_TRACE_USER_EVENT_MAX
#define _SC_XOPEN_STREAMS _SC_XOPEN_STREAMS
#define _SC_THREAD_ROBUST_PRIO_INHERIT _SC_THREAD_ROBUST_PRIO_INHERIT
#define _SC_THREAD_ROBUST_PRIO_PROTECT _SC_THREAD_ROBUST_PRIO_PROTECT
#define _CS_PATH _CS_PATH
#define _CS_V6_WIDTH_RESTRICTED_ENVS _CS_V6_WIDTH_RESTRICTED_ENVS
#define _CS_POSIX_V6_WIDTH_RESTRICTED_ENVS _CS_V6_WIDTH_RESTRICTED_ENVS
#define _CS_GNU_LIBC_VERSION _CS_GNU_LIBC_VERSION
#define _CS_GNU_LIBPTHREAD_VERSION _CS_GNU_LIBPTHREAD_VERSION
#define _CS_V5_WIDTH_RESTRICTED_ENVS _CS_V5_WIDTH_RESTRICTED_ENVS
#define _CS_POSIX_V5_WIDTH_RESTRICTED_ENVS _CS_V5_WIDTH_RESTRICTED_ENVS
#define _CS_V7_WIDTH_RESTRICTED_ENVS _CS_V7_WIDTH_RESTRICTED_ENVS
#define _CS_POSIX_V7_WIDTH_RESTRICTED_ENVS _CS_V7_WIDTH_RESTRICTED_ENVS
#define _CS_LFS_CFLAGS _CS_LFS_CFLAGS
#define _CS_LFS_LDFLAGS _CS_LFS_LDFLAGS
#define _CS_LFS_LIBS _CS_LFS_LIBS
#define _CS_LFS_LINTFLAGS _CS_LFS_LINTFLAGS
#define _CS_LFS64_CFLAGS _CS_LFS64_CFLAGS
#define _CS_LFS64_LDFLAGS _CS_LFS64_LDFLAGS
#define _CS_LFS64_LIBS _CS_LFS64_LIBS
#define _CS_LFS64_LINTFLAGS _CS_LFS64_LINTFLAGS
#define _CS_XBS5_ILP32_OFF32_CFLAGS _CS_XBS5_ILP32_OFF32_CFLAGS
#define _CS_XBS5_ILP32_OFF32_LDFLAGS _CS_XBS5_ILP32_OFF32_LDFLAGS
#define _CS_XBS5_ILP32_OFF32_LIBS _CS_XBS5_ILP32_OFF32_LIBS
#define _CS_XBS5_ILP32_OFF32_LINTFLAGS _CS_XBS5_ILP32_OFF32_LINTFLAGS
#define _CS_XBS5_ILP32_OFFBIG_CFLAGS _CS_XBS5_ILP32_OFFBIG_CFLAGS
#define _CS_XBS5_ILP32_OFFBIG_LDFLAGS _CS_XBS5_ILP32_OFFBIG_LDFLAGS
#define _CS_XBS5_ILP32_OFFBIG_LIBS _CS_XBS5_ILP32_OFFBIG_LIBS
#define _CS_XBS5_ILP32_OFFBIG_LINTFLAGS _CS_XBS5_ILP32_OFFBIG_LINTFLAGS
#define _CS_XBS5_LP64_OFF64_CFLAGS _CS_XBS5_LP64_OFF64_CFLAGS
#define _CS_XBS5_LP64_OFF64_LDFLAGS _CS_XBS5_LP64_OFF64_LDFLAGS
#define _CS_XBS5_LP64_OFF64_LIBS _CS_XBS5_LP64_OFF64_LIBS
#define _CS_XBS5_LP64_OFF64_LINTFLAGS _CS_XBS5_LP64_OFF64_LINTFLAGS
#define _CS_XBS5_LPBIG_OFFBIG_CFLAGS _CS_XBS5_LPBIG_OFFBIG_CFLAGS
#define _CS_XBS5_LPBIG_OFFBIG_LDFLAGS _CS_XBS5_LPBIG_OFFBIG_LDFLAGS
#define _CS_XBS5_LPBIG_OFFBIG_LIBS _CS_XBS5_LPBIG_OFFBIG_LIBS
#define _CS_XBS5_LPBIG_OFFBIG_LINTFLAGS _CS_XBS5_LPBIG_OFFBIG_LINTFLAGS
#define _CS_POSIX_V6_ILP32_OFF32_CFLAGS _CS_POSIX_V6_ILP32_OFF32_CFLAGS
#define _CS_POSIX_V6_ILP32_OFF32_LDFLAGS _CS_POSIX_V6_ILP32_OFF32_LDFLAGS
#define _CS_POSIX_V6_ILP32_OFF32_LIBS _CS_POSIX_V6_ILP32_OFF32_LIBS
#define _CS_POSIX_V6_ILP32_OFF32_LINTFLAGS _CS_POSIX_V6_ILP32_OFF32_LINTFLAGS
#define _CS_POSIX_V6_ILP32_OFFBIG_CFLAGS _CS_POSIX_V6_ILP32_OFFBIG_CFLAGS
#define _CS_POSIX_V6_ILP32_OFFBIG_LDFLAGS _CS_POSIX_V6_ILP32_OFFBIG_LDFLAGS
#define _CS_POSIX_V6_ILP32_OFFBIG_LIBS _CS_POSIX_V6_ILP32_OFFBIG_LIBS
#define _CS_POSIX_V6_ILP32_OFFBIG_LINTFLAGS _CS_POSIX_V6_ILP32_OFFBIG_LINTFLAGS
#define _CS_POSIX_V6_LP64_OFF64_CFLAGS _CS_POSIX_V6_LP64_OFF64_CFLAGS
#define _CS_POSIX_V6_LP64_OFF64_LDFLAGS _CS_POSIX_V6_LP64_OFF64_LDFLAGS
#define _CS_POSIX_V6_LP64_OFF64_LIBS _CS_POSIX_V6_LP64_OFF64_LIBS
#define _CS_POSIX_V6_LP64_OFF64_LINTFLAGS _CS_POSIX_V6_LP64_OFF64_LINTFLAGS
#define _CS_POSIX_V6_LPBIG_OFFBIG_CFLAGS _CS_POSIX_V6_LPBIG_OFFBIG_CFLAGS
#define _CS_POSIX_V6_LPBIG_OFFBIG_LDFLAGS _CS_POSIX_V6_LPBIG_OFFBIG_LDFLAGS
#define _CS_POSIX_V6_LPBIG_OFFBIG_LIBS _CS_POSIX_V6_LPBIG_OFFBIG_LIBS
#define _CS_POSIX_V6_LPBIG_OFFBIG_LINTFLAGS _CS_POSIX_V6_LPBIG_OFFBIG_LINTFLAGS
#define _CS_POSIX_V7_ILP32_OFF32_CFLAGS _CS_POSIX_V7_ILP32_OFF32_CFLAGS
#define _CS_POSIX_V7_ILP32_OFF32_LDFLAGS _CS_POSIX_V7_ILP32_OFF32_LDFLAGS
#define _CS_POSIX_V7_ILP32_OFF32_LIBS _CS_POSIX_V7_ILP32_OFF32_LIBS
#define _CS_POSIX_V7_ILP32_OFF32_LINTFLAGS _CS_POSIX_V7_ILP32_OFF32_LINTFLAGS
#define _CS_POSIX_V7_ILP32_OFFBIG_CFLAGS _CS_POSIX_V7_ILP32_OFFBIG_CFLAGS
#define _CS_POSIX_V7_ILP32_OFFBIG_LDFLAGS _CS_POSIX_V7_ILP32_OFFBIG_LDFLAGS
#define _CS_POSIX_V7_ILP32_OFFBIG_LIBS _CS_POSIX_V7_ILP32_OFFBIG_LIBS
#define _CS_POSIX_V7_ILP32_OFFBIG_LINTFLAGS _CS_POSIX_V7_ILP32_OFFBIG_LINTFLAGS
#define _CS_POSIX_V7_LP64_OFF64_CFLAGS _CS_POSIX_V7_LP64_OFF64_CFLAGS
#define _CS_POSIX_V7_LP64_OFF64_LDFLAGS _CS_POSIX_V7_LP64_OFF64_LDFLAGS
#define _CS_POSIX_V7_LP64_OFF64_LIBS _CS_POSIX_V7_LP64_OFF64_LIBS
#define _CS_POSIX_V7_LP64_OFF64_LINTFLAGS _CS_POSIX_V7_LP64_OFF64_LINTFLAGS
#define _CS_POSIX_V7_LPBIG_OFFBIG_CFLAGS _CS_POSIX_V7_LPBIG_OFFBIG_CFLAGS
#define _CS_POSIX_V7_LPBIG_OFFBIG_LDFLAGS _CS_POSIX_V7_LPBIG_OFFBIG_LDFLAGS
#define _CS_POSIX_V7_LPBIG_OFFBIG_LIBS _CS_POSIX_V7_LPBIG_OFFBIG_LIBS
#define _CS_POSIX_V7_LPBIG_OFFBIG_LINTFLAGS _CS_POSIX_V7_LPBIG_OFFBIG_LINTFLAGS
#define _CS_V6_ENV _CS_V6_ENV
#define _CS_V7_ENV _CS_V7_ENV
#define __need_getopt 
#undef __need_getopt
#define F_ULOCK 0
#define F_LOCK 1
#define F_TLOCK 2
#define F_TEST 3
#define TEMP_FAILURE_RETRY(expression) (__extension__ ({ long int __result; do __result = (long int) (expression); while (__result == -1L && errno == EINTR); __result; }))
#define RBIMPL_DLLEXPORT_H 
#undef RUBY_EXTERN
#define RUBY_EXTERN extern
#define MJIT_FUNC_EXPORTED RUBY_FUNC_EXPORTED
#define MJIT_SYMBOL_EXPORT_BEGIN RUBY_SYMBOL_EXPORT_BEGIN
#define MJIT_SYMBOL_EXPORT_END RUBY_SYMBOL_EXPORT_END
#define MJIT_STATIC static
#define RBIMPL_SYMBOL_EXPORT_BEGIN() RUBY_SYMBOL_EXPORT_BEGIN
#define RBIMPL_SYMBOL_EXPORT_END() RUBY_SYMBOL_EXPORT_END
#define RBIMPL_XMALLOC_H 
#define RBIMPL_ATTR_ALLOC_SIZE_H 
#define RBIMPL_HAS_ATTRIBUTE_H 
#define RBIMPL_HAVE___HAS_ATTRIBUTE 1
#define RBIMPL_HAS_ATTRIBUTE(_) __has_attribute(_)
#define RBIMPL_ATTR_ALLOC_SIZE(tuple) __attribute__((__alloc_size__ tuple))
#define RBIMPL_ATTR_NODISCARD_H 
#define RBIMPL_HAS_C_ATTRIBUTE_H 
#define RBIMPL_HAS_C_ATTRIBUTE(_) __has_c_attribute(_)
#define RBIMPL_HAS_CPP_ATTRIBUTE_H 
#define RBIMPL_HAS_CPP_ATTRIBUTE0(_) __has_cpp_attribute(_)
#define RBIMPL_HAS_CPP_ATTRIBUTE(_) 0
#define RBIMPL_ATTR_NODISCARD() [[nodiscard]]
#define RBIMPL_ATTR_NOEXCEPT_H 
#define RBIMPL_HAS_FEATURE_H 
#define RBIMPL_HAS_FEATURE(_) 0
#define RBIMPL_ATTR_NOEXCEPT(_) 
#define RBIMPL_ATTR_RESTRICT_H 
#define RBIMPL_ATTR_RESTRICT() __attribute__((__malloc__))
#define RBIMPL_ATTR_RETURNS_NONNULL_H 
#define RBIMPL_ATTR_RETURNS_NONNULL() __attribute__((__returns_nonnull__))
#define USE_GC_MALLOC_OBJ_INFO_DETAILS 0
#define xmalloc ruby_xmalloc
#define xmalloc2 ruby_xmalloc2
#define xcalloc ruby_xcalloc
#define xrealloc ruby_xrealloc
#define xrealloc2 ruby_xrealloc2
#define xfree ruby_xfree
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RUBY_BACKWARD2_ASSUME_H 
#define RBIMPL_ASSUME_H 
#define RBIMPL_CAST_H 
#define RBIMPL_HAS_WARNING_H 
#define RBIMPL_HAS_WARNING(_) 0
#define RBIMPL_WARNING_PUSH_H 
#define RBIMPL_WARNING_PRAGMA0(x) _Pragma(#x)
#define RBIMPL_WARNING_PRAGMA1(x) RBIMPL_WARNING_PRAGMA0(GCC diagnostic x)
#define RBIMPL_WARNING_PRAGMA2(x,y) RBIMPL_WARNING_PRAGMA1(x #y)
#define RBIMPL_WARNING_PUSH() RBIMPL_WARNING_PRAGMA1(push)
#define RBIMPL_WARNING_POP() RBIMPL_WARNING_PRAGMA1(pop)
#define RBIMPL_WARNING_ERROR(flag) RBIMPL_WARNING_PRAGMA2(error, flag)
#define RBIMPL_WARNING_IGNORED(flag) RBIMPL_WARNING_PRAGMA2(ignored, flag)
#define RBIMPL_CAST(expr) (expr)
#define RBIMPL_HAS_BUILTIN_H 
#define RBIMPL_HAVE___HAS_BUILTIN 1
#define RBIMPL_HAS_BUILTIN(_) __has_builtin(_)
#define RBIMPL_UNREACHABLE_RETURN(_) __builtin_unreachable()
#define RBIMPL_UNREACHABLE __builtin_unreachable
#define RBIMPL_ASSUME(_) (RB_LIKELY(!!(_)) ? RBIMPL_CAST((void)0) : RBIMPL_UNREACHABLE())
#undef ASSUME
#undef UNREACHABLE
#define ASSUME RBIMPL_ASSUME
#define UNREACHABLE RBIMPL_UNREACHABLE()
#define UNREACHABLE_RETURN RBIMPL_UNREACHABLE_RETURN
#define RB_LIKELY(x) (__builtin_expect(!!(x), 1))
#define RB_UNLIKELY(x) (__builtin_expect(!!(x), 0))
#define RUBY_BACKWARD2_ATTRIBUTES_H 
#define RBIMPL_ATTR_CONST_H 
#define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_H 
#define RBIMPL_HAS_DECLSPEC_ATTRIBUTE(_) (RBIMPL_HAS_DECLSPEC_ATTRIBUTE_ ## _)
#define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_align RBIMPL_COMPILER_SINCE(MSVC, 8, 0, 0)
#define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_deprecated RBIMPL_COMPILER_SINCE(MSVC,13, 0, 0)
#define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_dllexport RBIMPL_COMPILER_SINCE(MSVC, 8, 0, 0)
#define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_dllimport RBIMPL_COMPILER_SINCE(MSVC, 8, 0, 0)
#define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_empty_bases RBIMPL_COMPILER_SINCE(MSVC,19, 0, 23918)
#define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_noalias RBIMPL_COMPILER_SINCE(MSVC, 8, 0, 0)
#define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_noinline RBIMPL_COMPILER_SINCE(MSVC,13, 0, 0)
#define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_noreturn RBIMPL_COMPILER_SINCE(MSVC,11, 0, 0)
#define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_nothrow RBIMPL_COMPILER_SINCE(MSVC, 8, 0, 0)
#define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_restrict RBIMPL_COMPILER_SINCE(MSVC,14, 0, 0)
#undef RBIMPL_HAS_DECLSPEC_ATTRIBUTE_nothrow
#define RBIMPL_ATTR_CONST() __attribute__((__const__))
#define RBIMPL_ATTR_CONST_UNLESS_DEBUG() RBIMPL_ATTR_CONST()
#define RBIMPL_ATTR_DEPRECATED_H 
#define RBIMPL_HAS_EXTENSION_H 
#define RBIMPL_HAS_EXTENSION(_) RBIMPL_HAS_FEATURE(_)
#define RBIMPL_ATTR_DEPRECATED(msg) __attribute__((__deprecated__ msg))
#define RBIMPL_ATTR_DEPRECATED_EXT(msg) 
#define RBIMPL_ATTR_ERROR_H 
#define RBIMPL_ATTR_ERROR(msg) __attribute__((__error__ msg))
#define RBIMPL_ATTR_FORCEINLINE_H 
#define RBIMPL_ATTR_FORCEINLINE() __attribute__((__always_inline__)) inline
#define RBIMPL_ATTR_FORMAT_H 
#define RBIMPL_ATTR_FORMAT(x,y,z) __attribute__((__format__(x, y, z)))
#define RBIMPL_PRINTF_FORMAT __printf__
#define RBIMPL_ATTR_MAYBE_UNUSED_H 
#define RBIMPL_ATTR_MAYBE_UNUSED() [[maybe_unused]]
#define RBIMPL_ATTR_NOINLINE_H 
#define RBIMPL_ATTR_NOINLINE() __attribute__((__noinline__))
#define RBIMPL_ATTR_NONNULL_H 
#define RBIMPL_ATTR_NONNULL(list) __attribute__((__nonnull__ list))
#define RBIMPL_NONNULL_ARG(arg) RBIMPL_ASSERT_NOTHING
#define RBIMPL_ATTR_NORETURN_H 
#define RBIMPL_ATTR_NORETURN() __attribute__((__noreturn__))
#define RBIMPL_ATTR_PURE_H 
#define RUBY_ASSERT_H 
#define RBIMPL_RUBY_DEBUG 0
#define RBIMPL_NDEBUG 0
#undef RUBY_DEBUG
#undef RUBY_NDEBUG
#undef NDEBUG
#define RUBY_DEBUG 0
#define RUBY_NDEBUG 1
#define NDEBUG 
#undef RBIMPL_NDEBUG
#undef RBIMPL_RUBY_DEBUG
#define RBIMPL_ASSERT_NOTHING RBIMPL_CAST((void)0)
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_ASSERT_FUNC RUBY_FUNCTION_NAME_STRING
#define RUBY_ASSERT_FAIL(mesg) rb_assert_failure(__FILE__, __LINE__, RBIMPL_ASSERT_FUNC, mesg)
#define RUBY_ASSERT_MESG(expr,mesg) (RB_LIKELY(expr) ? RBIMPL_ASSERT_NOTHING : RUBY_ASSERT_FAIL(mesg))
#define RUBY_ASSERT_ALWAYS(expr) RUBY_ASSERT_MESG((expr), #expr)
#define RUBY_ASSERT(expr) RBIMPL_ASSERT_NOTHING
#define RUBY_ASSERT_NDEBUG(expr) RBIMPL_ASSERT_NOTHING
#define RUBY_ASSERT_MESG_WHEN(cond,expr,mesg) ((cond) ? RUBY_ASSERT_MESG((expr), (mesg)) : RBIMPL_ASSERT_NOTHING)
#define RUBY_ASSERT_WHEN(cond,expr) RUBY_ASSERT_MESG_WHEN((cond), (expr), #expr)
#define RBIMPL_ASSERT_OR_ASSUME(expr) RBIMPL_ASSERT_NOTHING
#define RBIMPL_ATTR_PURE() __attribute__((__pure__))
#define RBIMPL_ATTR_PURE_UNLESS_DEBUG() RBIMPL_ATTR_PURE()
#define RBIMPL_ATTR_WARNING_H 
#define RBIMPL_ATTR_WARNING(msg) __attribute__((__warning__ msg))
#undef CONSTFUNC
#define CONSTFUNC(x) RBIMPL_ATTR_CONST() x
#undef PUREFUNC
#define PUREFUNC(x) RBIMPL_ATTR_PURE() x
#undef DEPRECATED
#define DEPRECATED(x) RBIMPL_ATTR_DEPRECATED(("")) x
#undef DEPRECATED_BY
#define DEPRECATED_BY(n,x) RBIMPL_ATTR_DEPRECATED(("by: " #n)) x
#undef DEPRECATED_TYPE
#define DEPRECATED_TYPE(mesg,decl) _Pragma("message \"DEPRECATED_TYPE is deprecated\""); decl RBIMPL_ATTR_DEPRECATED(mseg)
#undef RUBY_CXX_DEPRECATED
#define RUBY_CXX_DEPRECATED(mseg) RBIMPL_ATTR_DEPRECATED((mseg))
#undef NOINLINE
#define NOINLINE(x) RBIMPL_ATTR_NOINLINE() x
#undef ERRORFUNC
#define ERRORFUNC(mesg,x) RBIMPL_ATTR_ERROR(mesg) x
#define HAVE_ATTRIBUTE_ERRORFUNC 1
#undef WARNINGFUNC
#define WARNINGFUNC(mesg,x) RBIMPL_ATTR_WARNING(mesg) x
#define HAVE_ATTRIBUTE_WARNINGFUNC 1
#undef COLDFUNC
#define PRINTF_ARGS(decl,string_index,first_to_check) RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, (string_index), (first_to_check)) decl
#undef RUBY_ATTR_ALLOC_SIZE
#define RUBY_ATTR_ALLOC_SIZE RBIMPL_ATTR_ALLOC_SIZE
#undef RUBY_ATTR_MALLOC
#define RUBY_ATTR_MALLOC RBIMPL_ATTR_RESTRICT()
#undef RUBY_ATTR_RETURNS_NONNULL
#define RUBY_ATTR_RETURNS_NONNULL RBIMPL_ATTR_RETURNS_NONNULL()
#define RUBY_ALIAS_FUNCTION(prot,name,args) RUBY_ALIAS_FUNCTION_TYPE(VALUE, prot, name, args)
#undef RUBY_FUNC_NONNULL
#define RUBY_FUNC_NONNULL(n,x) RBIMPL_ATTR_NONNULL(n) x
#undef NORETURN
#define NORETURN(x) RBIMPL_ATTR_NORETURN() x
#define NORETURN_STYLE_NEW 
#define PACKED_STRUCT_UNALIGNED(x) PACKED_STRUCT(x)
#undef RB_UNUSED_VAR
#define RB_UNUSED_VAR(x) x RBIMPL_ATTR_MAYBE_UNUSED()
#define RUBY_BACKWARD2_BOOL_H 
#define RBIMPL_STDBOOL_H 
#define _STDBOOL_H 
#define bool _Bool
#define true 1
#define false 0
#define __bool_true_false_are_defined 1
#define FALSE false
#define TRUE true
#define RUBY_BACKWARD2_LONG_LONG_H 
#define HAVE_TRUE_LONG_LONG 1
#define LONG_LONG long long
#define RUBY_BACKWARD2_STDALIGN_H 
#define RBIMPL_STDALIGN_H 
#define RBIMPL_ALIGNAS(_) __attribute__((__aligned__(_)))
#define RBIMPL_ALIGNOF(T) RB_GNUC_EXTENSION(_Alignof(T))
#undef RUBY_ALIGNAS
#undef RUBY_ALIGNOF
#define RUBY_ALIGNAS RBIMPL_ALIGNAS
#define RUBY_ALIGNOF RBIMPL_ALIGNOF
#define RUBY_BACKWARD2_STDARG_H 
#undef _
#define _(args) args
#undef __
#define __(args) args
#define ANYARGS 
#define RBIMPL_DOSISH_H 
#define PATH_SEP ":"
#define PATH_SEP_CHAR PATH_SEP[0]
#define PATH_ENV "PATH"
#define CASEFOLD_FILESYSTEM 0
#define RUBY_MISSING_H 1
#define _MATH_H 1
#define HUGE_VAL (__builtin_huge_val())
#define HUGE_VALF (__builtin_huge_valf())
#define HUGE_VALL (__builtin_huge_vall())
#define INFINITY (__builtin_inff())
#define NAN (__builtin_nanf (""))
#define _MATH_H_MATHDEF 1
#define __WORDSIZE 64
#define __WORDSIZE_COMPAT32 1
#define FP_ILOGB0 (-2147483647 - 1)
#define FP_ILOGBNAN (-2147483647 - 1)
#define __MATHCALL(function,suffix,args) __MATHDECL (_Mdouble_,function,suffix, args)
#define __MATHDECL(type,function,suffix,args) __MATHDECL_1(type, function,suffix, args); __MATHDECL_1(type, __CONCAT(__,function),suffix, args)
#define __MATHCALLX(function,suffix,args,attrib) __MATHDECLX (_Mdouble_,function,suffix, args, attrib)
#define __MATHDECLX(type,function,suffix,args,attrib) __MATHDECL_1(type, function,suffix, args) __attribute__ (attrib); __MATHDECL_1(type, __CONCAT(__,function),suffix, args) __attribute__ (attrib)
#define __MATHDECL_1(type,function,suffix,args) extern type __MATH_PRECNAME(function,suffix) args __THROW
#define _Mdouble_ double
#define __MATH_PRECNAME(name,r) __CONCAT(name,r)
#define _Mdouble_BEGIN_NAMESPACE __BEGIN_NAMESPACE_STD
#define _Mdouble_END_NAMESPACE __END_NAMESPACE_STD
#undef _Mdouble_
#undef _Mdouble_BEGIN_NAMESPACE
#undef _Mdouble_END_NAMESPACE
#undef __MATH_PRECNAME
#define _Mfloat_ float
#define _Mdouble_ _Mfloat_
#define __MATH_PRECNAME(name,r) name ##f ##r
#define _Mdouble_BEGIN_NAMESPACE __BEGIN_NAMESPACE_C99
#define _Mdouble_END_NAMESPACE __END_NAMESPACE_C99
#undef _Mdouble_
#undef _Mdouble_BEGIN_NAMESPACE
#undef _Mdouble_END_NAMESPACE
#undef __MATH_PRECNAME
#define _Mlong_double_ long double
#define _Mdouble_ _Mlong_double_
#define __MATH_PRECNAME(name,r) name ##l ##r
#define _Mdouble_BEGIN_NAMESPACE __BEGIN_NAMESPACE_C99
#define _Mdouble_END_NAMESPACE __END_NAMESPACE_C99
#undef _Mdouble_
#undef _Mdouble_BEGIN_NAMESPACE
#undef _Mdouble_END_NAMESPACE
#undef __MATH_PRECNAME
#undef __MATHDECL_1
#undef __MATHDECL
#undef __MATHCALL
#define FP_NAN FP_NAN
#define FP_INFINITE FP_INFINITE
#define FP_ZERO FP_ZERO
#define FP_SUBNORMAL FP_SUBNORMAL
#define FP_NORMAL FP_NORMAL
#define fpclassify(x) (sizeof (x) == sizeof (float) ? __fpclassifyf (x) : sizeof (x) == sizeof (double) ? __fpclassify (x) : __fpclassifyl (x))
#define signbit(x) (sizeof (x) == sizeof (float) ? __signbitf (x) : sizeof (x) == sizeof (double) ? __signbit (x) : __signbitl (x))
#define isfinite(x) (sizeof (x) == sizeof (float) ? __finitef (x) : sizeof (x) == sizeof (double) ? __finite (x) : __finitel (x))
#define isnormal(x) (fpclassify (x) == FP_NORMAL)
#define isnan(x) (sizeof (x) == sizeof (float) ? __isnanf (x) : sizeof (x) == sizeof (double) ? __isnan (x) : __isnanl (x))
#define isinf(x) (sizeof (x) == sizeof (float) ? __isinff (x) : sizeof (x) == sizeof (double) ? __isinf (x) : __isinfl (x))
#define MATH_ERRNO 1
#define MATH_ERREXCEPT 2
#define math_errhandling (MATH_ERRNO | MATH_ERREXCEPT)
#define X_TLOSS 1.41484755040568800000e+16
#define DOMAIN 1
#define SING 2
#define OVERFLOW 3
#define UNDERFLOW 4
#define TLOSS 5
#define PLOSS 6
#define HUGE 3.40282347e+38F
#define M_E 2.7182818284590452354
#define M_LOG2E 1.4426950408889634074
#define M_LOG10E 0.43429448190325182765
#define M_LN2 0.69314718055994530942
#define M_LN10 2.30258509299404568402
#define M_PI 3.14159265358979323846
#define M_PI_2 1.57079632679489661923
#define M_PI_4 0.78539816339744830962
#define M_1_PI 0.31830988618379067154
#define M_2_PI 0.63661977236758134308
#define M_2_SQRTPI 1.12837916709551257390
#define M_SQRT2 1.41421356237309504880
#define M_SQRT1_2 0.70710678118654752440
#define M_El 2.7182818284590452353602874713526625L
#define M_LOG2El 1.4426950408889634073599246810018921L
#define M_LOG10El 0.4342944819032518276511289189166051L
#define M_LN2l 0.6931471805599453094172321214581766L
#define M_LN10l 2.3025850929940456840179914546843642L
#define M_PIl 3.1415926535897932384626433832795029L
#define M_PI_2l 1.5707963267948966192313216916397514L
#define M_PI_4l 0.7853981633974483096156608458198757L
#define M_1_PIl 0.3183098861837906715377675267450287L
#define M_2_PIl 0.6366197723675813430755350534900574L
#define M_2_SQRTPIl 1.1283791670955125738961589031215452L
#define M_SQRT2l 1.4142135623730950488016887242096981L
#define M_SQRT1_2l 0.7071067811865475244008443621048490L
#define isgreater(x,y) __builtin_isgreater(x, y)
#define isgreaterequal(x,y) __builtin_isgreaterequal(x, y)
#define isless(x,y) __builtin_isless(x, y)
#define islessequal(x,y) __builtin_islessequal(x, y)
#define islessgreater(x,y) __builtin_islessgreater(x, y)
#define isunordered(u,v) __builtin_isunordered(u, v)
#define _TIME_H 1
#define __need_size_t 
#define __need_NULL 
#undef __need_ptrdiff_t
#undef __need_size_t
#undef __need_wchar_t
#undef NULL
#define NULL ((void *)0)
#undef __need_NULL
#define offsetof(TYPE,MEMBER) __builtin_offsetof (TYPE, MEMBER)
#define _BITS_TIME_H 1
#define CLOCKS_PER_SEC 1000000l
#define CLOCK_REALTIME 0
#define CLOCK_MONOTONIC 1
#define CLOCK_PROCESS_CPUTIME_ID 2
#define CLOCK_THREAD_CPUTIME_ID 3
#define CLOCK_MONOTONIC_RAW 4
#define CLOCK_REALTIME_COARSE 5
#define CLOCK_MONOTONIC_COARSE 6
#define TIMER_ABSTIME 1
#undef __need_clock_t
#undef __need_time_t
#undef __clockid_time_t
#undef __need_timer_t
#undef __need_timespec
#define __isleap(year) ((year) % 4 == 0 && ((year) % 100 != 0 || (year) % 400 == 0))
#define _SYS_TIME_H 1
#define __need_time_t 
#define __need_timeval 
#undef __need_timeval
#define TIMEVAL_TO_TIMESPEC(tv,ts) { (ts)->tv_sec = (tv)->tv_sec; (ts)->tv_nsec = (tv)->tv_usec * 1000; }
#define TIMESPEC_TO_TIMEVAL(tv,ts) { (tv)->tv_sec = (ts)->tv_sec; (tv)->tv_usec = (ts)->tv_nsec / 1000; }
#define ITIMER_REAL ITIMER_REAL
#define ITIMER_VIRTUAL ITIMER_VIRTUAL
#define ITIMER_PROF ITIMER_PROF
#define timerisset(tvp) ((tvp)->tv_sec || (tvp)->tv_usec)
#define timerclear(tvp) ((tvp)->tv_sec = (tvp)->tv_usec = 0)
#define timercmp(a,b,CMP) (((a)->tv_sec == (b)->tv_sec) ? ((a)->tv_usec CMP (b)->tv_usec) : ((a)->tv_sec CMP (b)->tv_sec))
#define timeradd(a,b,result) do { (result)->tv_sec = (a)->tv_sec + (b)->tv_sec; (result)->tv_usec = (a)->tv_usec + (b)->tv_usec; if ((result)->tv_usec >= 1000000) { ++(result)->tv_sec; (result)->tv_usec -= 1000000; } } while (0)
#define timersub(a,b,result) do { (result)->tv_sec = (a)->tv_sec - (b)->tv_sec; (result)->tv_usec = (a)->tv_usec - (b)->tv_usec; if ((result)->tv_usec < 0) { --(result)->tv_sec; (result)->tv_usec += 1000000; } } while (0)
#pragma GCC visibility push(default)
#define HAVE_FINITE 1
#define finite(x) isfinite(x)
#pragma GCC visibility pop
#define RUBY 
#define RB_GNUC_EXTENSION __extension__
#define RB_GNUC_EXTENSION_BLOCK(x) __extension__ ({ x; })
#define RUBY_MBCHAR_MAXSIZE INT_MAX
#define FLUSH_REGISTER_WINDOWS ((void)0)
#define RBIMPL_ANYARGS_H 
#define RBIMPL_ATTR_WEAKREF_H 
#define RBIMPL_ATTR_WEAKREF(sym) __attribute__((__weakref__(#sym)))
#define RBIMPL_INTERN_CLASS_H 
#define RBIMPL_VALUE_H 
#define RBIMPL_STATIC_ASSERT_H 
#define _ASSERT_H 1
#define __ASSERT_VOID_CAST (void)
#define assert(expr) (__ASSERT_VOID_CAST (0))
#define assert_perror(errnum) (__ASSERT_VOID_CAST (0))
#define RBIMPL_STATIC_ASSERT0 __extension__ _Static_assert
#define RBIMPL_STATIC_ASSERT(name,expr) RBIMPL_STATIC_ASSERT0(expr, #name ": " #expr)
#define RUBY_BACKWARD2_LIMITS_H 
#define _LIBC_LIMITS_H_ 1
#define MB_LEN_MAX 16
#define _GCC_LIMITS_H_ 
#define _LIMITS_H___ 
#undef CHAR_BIT
#define CHAR_BIT __CHAR_BIT__
#undef SCHAR_MIN
#define SCHAR_MIN (-SCHAR_MAX - 1)
#undef SCHAR_MAX
#define SCHAR_MAX __SCHAR_MAX__
#undef UCHAR_MAX
#define UCHAR_MAX (SCHAR_MAX * 2 + 1)
#undef CHAR_MIN
#define CHAR_MIN SCHAR_MIN
#undef CHAR_MAX
#define CHAR_MAX SCHAR_MAX
#undef SHRT_MIN
#define SHRT_MIN (-SHRT_MAX - 1)
#undef SHRT_MAX
#define SHRT_MAX __SHRT_MAX__
#undef USHRT_MAX
#define USHRT_MAX (SHRT_MAX * 2 + 1)
#undef INT_MIN
#define INT_MIN (-INT_MAX - 1)
#undef INT_MAX
#define INT_MAX __INT_MAX__
#undef UINT_MAX
#define UINT_MAX (INT_MAX * 2U + 1U)
#undef LONG_MIN
#define LONG_MIN (-LONG_MAX - 1L)
#undef LONG_MAX
#define LONG_MAX __LONG_MAX__
#undef ULONG_MAX
#define ULONG_MAX (LONG_MAX * 2UL + 1UL)
#undef LLONG_MIN
#define LLONG_MIN (-LLONG_MAX - 1LL)
#undef LLONG_MAX
#define LLONG_MAX __LONG_LONG_MAX__
#undef ULLONG_MAX
#define ULLONG_MAX (LLONG_MAX * 2ULL + 1ULL)
#undef LONG_LONG_MIN
#define LONG_LONG_MIN (-LONG_LONG_MAX - 1LL)
#undef LONG_LONG_MAX
#define LONG_LONG_MAX __LONG_LONG_MAX__
#undef ULONG_LONG_MAX
#define ULONG_LONG_MAX (LONG_LONG_MAX * 2ULL + 1ULL)
#undef CHAR_WIDTH
#define CHAR_WIDTH __SCHAR_WIDTH__
#undef SCHAR_WIDTH
#define SCHAR_WIDTH __SCHAR_WIDTH__
#undef UCHAR_WIDTH
#define UCHAR_WIDTH __SCHAR_WIDTH__
#undef SHRT_WIDTH
#define SHRT_WIDTH __SHRT_WIDTH__
#undef USHRT_WIDTH
#define USHRT_WIDTH __SHRT_WIDTH__
#undef INT_WIDTH
#define INT_WIDTH __INT_WIDTH__
#undef UINT_WIDTH
#define UINT_WIDTH __INT_WIDTH__
#undef LONG_WIDTH
#define LONG_WIDTH __LONG_WIDTH__
#undef ULONG_WIDTH
#define ULONG_WIDTH __LONG_WIDTH__
#undef LLONG_WIDTH
#define LLONG_WIDTH __LONG_LONG_WIDTH__
#undef ULLONG_WIDTH
#define ULLONG_WIDTH __LONG_LONG_WIDTH__
#define _BITS_POSIX1_LIM_H 1
#define _POSIX_AIO_LISTIO_MAX 2
#define _POSIX_AIO_MAX 1
#define _POSIX_ARG_MAX 4096
#define _POSIX_CHILD_MAX 25
#define _POSIX_DELAYTIMER_MAX 32
#define _POSIX_HOST_NAME_MAX 255
#define _POSIX_LINK_MAX 8
#define _POSIX_LOGIN_NAME_MAX 9
#define _POSIX_MAX_CANON 255
#define _POSIX_MAX_INPUT 255
#define _POSIX_MQ_OPEN_MAX 8
#define _POSIX_MQ_PRIO_MAX 32
#define _POSIX_NAME_MAX 14
#define _POSIX_NGROUPS_MAX 8
#define _POSIX_OPEN_MAX 20
#define _POSIX_FD_SETSIZE _POSIX_OPEN_MAX
#define _POSIX_PATH_MAX 256
#define _POSIX_PIPE_BUF 512
#define _POSIX_RE_DUP_MAX 255
#define _POSIX_RTSIG_MAX 8
#define _POSIX_SEM_NSEMS_MAX 256
#define _POSIX_SEM_VALUE_MAX 32767
#define _POSIX_SIGQUEUE_MAX 32
#define _POSIX_SSIZE_MAX 32767
#define _POSIX_STREAM_MAX 8
#define _POSIX_SYMLINK_MAX 255
#define _POSIX_SYMLOOP_MAX 8
#define _POSIX_TIMER_MAX 32
#define _POSIX_TTY_NAME_MAX 9
#define _POSIX_TZNAME_MAX 6
#define _POSIX_QLIMIT 1
#define _POSIX_HIWAT _POSIX_PIPE_BUF
#define _POSIX_UIO_MAXIOV 16
#define _POSIX_CLOCKRES_MIN 20000000
#define __undef_NR_OPEN 
#define __undef_LINK_MAX 
#define __undef_OPEN_MAX 
#define __undef_ARG_MAX 
#define _LINUX_LIMITS_H 
#define NR_OPEN 1024
#define NGROUPS_MAX 65536
#define ARG_MAX 131072
#define LINK_MAX 127
#define MAX_CANON 255
#define MAX_INPUT 255
#define NAME_MAX 255
#define PATH_MAX 4096
#define PIPE_BUF 4096
#define XATTR_NAME_MAX 255
#define XATTR_SIZE_MAX 65536
#define XATTR_LIST_MAX 65536
#define RTSIG_MAX 32
#undef NR_OPEN
#undef __undef_NR_OPEN
#undef LINK_MAX
#undef __undef_LINK_MAX
#undef OPEN_MAX
#undef __undef_OPEN_MAX
#undef ARG_MAX
#undef __undef_ARG_MAX
#define _POSIX_THREAD_KEYS_MAX 128
#define PTHREAD_KEYS_MAX 1024
#define _POSIX_THREAD_DESTRUCTOR_ITERATIONS 4
#define PTHREAD_DESTRUCTOR_ITERATIONS _POSIX_THREAD_DESTRUCTOR_ITERATIONS
#define _POSIX_THREAD_THREADS_MAX 64
#undef PTHREAD_THREADS_MAX
#define AIO_PRIO_DELTA_MAX 20
#define PTHREAD_STACK_MIN 16384
#define DELAYTIMER_MAX 2147483647
#define TTY_NAME_MAX 32
#define LOGIN_NAME_MAX 256
#define HOST_NAME_MAX 64
#define MQ_PRIO_MAX 32768
#define SEM_VALUE_MAX (2147483647)
#define SSIZE_MAX LONG_MAX
#define _BITS_POSIX2_LIM_H 1
#define _POSIX2_BC_BASE_MAX 99
#define _POSIX2_BC_DIM_MAX 2048
#define _POSIX2_BC_SCALE_MAX 99
#define _POSIX2_BC_STRING_MAX 1000
#define _POSIX2_COLL_WEIGHTS_MAX 2
#define _POSIX2_EXPR_NEST_MAX 32
#define _POSIX2_LINE_MAX 2048
#define _POSIX2_RE_DUP_MAX 255
#define _POSIX2_CHARCLASS_NAME_MAX 14
#define BC_BASE_MAX _POSIX2_BC_BASE_MAX
#define BC_DIM_MAX _POSIX2_BC_DIM_MAX
#define BC_SCALE_MAX _POSIX2_BC_SCALE_MAX
#define BC_STRING_MAX _POSIX2_BC_STRING_MAX
#define COLL_WEIGHTS_MAX 255
#define EXPR_NEST_MAX _POSIX2_EXPR_NEST_MAX
#define LINE_MAX _POSIX2_LINE_MAX
#define CHARCLASS_NAME_MAX 2048
#define RE_DUP_MAX (0x7fff)
#define _XOPEN_LIM_H 1
#define __need_IOV_MAX 
#define L_tmpnam 20
#define TMP_MAX 238328
#define FILENAME_MAX 4096
#define L_ctermid 9
#define L_cuserid 9
#undef FOPEN_MAX
#define FOPEN_MAX 16
#define IOV_MAX 1024
#define _XOPEN_IOV_MAX _POSIX_UIO_MAXIOV
#define NL_ARGMAX _POSIX_ARG_MAX
#define NL_LANGMAX _POSIX2_LINE_MAX
#define NL_MSGMAX INT_MAX
#define NL_NMAX INT_MAX
#define NL_SETMAX INT_MAX
#define NL_TEXTMAX INT_MAX
#define NZERO 20
#define WORD_BIT 32
#define LONG_BIT 64
#define SIGNED_VALUE long
#define SIZEOF_VALUE SIZEOF_LONG
#define PRI_VALUE_PREFIX "l"
#define RBIMPL_VALUE_NULL 0UL
#define RBIMPL_VALUE_ONE 1UL
#define RBIMPL_VALUE_FULL ULONG_MAX
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_INTERN_VM_H 
#pragma GCC visibility push(default)
#define HAVE_RB_DEFINE_ALLOC_FUNC 1
#pragma GCC visibility pop
#define RBIMPL_METHOD_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_CFUNC_IS_rb_f_notimplement(f) __builtin_types_compatible_p( __typeof__(f), __typeof__(rb_f_notimplement))
#define RBIMPL_ANYARGS_DISPATCH(expr,truthy,falsy) __builtin_choose_expr( __builtin_choose_expr( __builtin_constant_p(expr), (expr), 0), (truthy), (falsy))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_m2(n) RBIMPL_ANYARGS_DISPATCH((n) == -2, rb_define_singleton_method_m2, rb_define_singleton_method_m3)
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_m1(n) RBIMPL_ANYARGS_DISPATCH((n) == -1, rb_define_singleton_method_m1, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_m2(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_00(n) RBIMPL_ANYARGS_DISPATCH((n) == 0, rb_define_singleton_method_00, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_m1(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_01(n) RBIMPL_ANYARGS_DISPATCH((n) == 1, rb_define_singleton_method_01, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_00(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_02(n) RBIMPL_ANYARGS_DISPATCH((n) == 2, rb_define_singleton_method_02, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_01(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_03(n) RBIMPL_ANYARGS_DISPATCH((n) == 3, rb_define_singleton_method_03, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_02(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_04(n) RBIMPL_ANYARGS_DISPATCH((n) == 4, rb_define_singleton_method_04, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_03(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_05(n) RBIMPL_ANYARGS_DISPATCH((n) == 5, rb_define_singleton_method_05, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_04(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_06(n) RBIMPL_ANYARGS_DISPATCH((n) == 6, rb_define_singleton_method_06, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_05(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_07(n) RBIMPL_ANYARGS_DISPATCH((n) == 7, rb_define_singleton_method_07, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_06(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_08(n) RBIMPL_ANYARGS_DISPATCH((n) == 8, rb_define_singleton_method_08, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_07(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_09(n) RBIMPL_ANYARGS_DISPATCH((n) == 9, rb_define_singleton_method_09, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_08(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_10(n) RBIMPL_ANYARGS_DISPATCH((n) == 10, rb_define_singleton_method_10, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_09(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_11(n) RBIMPL_ANYARGS_DISPATCH((n) == 11, rb_define_singleton_method_11, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_10(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_12(n) RBIMPL_ANYARGS_DISPATCH((n) == 12, rb_define_singleton_method_12, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_11(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_13(n) RBIMPL_ANYARGS_DISPATCH((n) == 13, rb_define_singleton_method_13, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_12(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_14(n) RBIMPL_ANYARGS_DISPATCH((n) == 14, rb_define_singleton_method_14, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_13(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_15(n) RBIMPL_ANYARGS_DISPATCH((n) == 15, rb_define_singleton_method_15, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_14(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_m2(n) RBIMPL_ANYARGS_DISPATCH((n) == -2, rb_define_protected_method_m2, rb_define_protected_method_m3)
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_m1(n) RBIMPL_ANYARGS_DISPATCH((n) == -1, rb_define_protected_method_m1, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_m2(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_00(n) RBIMPL_ANYARGS_DISPATCH((n) == 0, rb_define_protected_method_00, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_m1(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_01(n) RBIMPL_ANYARGS_DISPATCH((n) == 1, rb_define_protected_method_01, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_00(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_02(n) RBIMPL_ANYARGS_DISPATCH((n) == 2, rb_define_protected_method_02, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_01(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_03(n) RBIMPL_ANYARGS_DISPATCH((n) == 3, rb_define_protected_method_03, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_02(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_04(n) RBIMPL_ANYARGS_DISPATCH((n) == 4, rb_define_protected_method_04, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_03(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_05(n) RBIMPL_ANYARGS_DISPATCH((n) == 5, rb_define_protected_method_05, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_04(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_06(n) RBIMPL_ANYARGS_DISPATCH((n) == 6, rb_define_protected_method_06, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_05(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_07(n) RBIMPL_ANYARGS_DISPATCH((n) == 7, rb_define_protected_method_07, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_06(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_08(n) RBIMPL_ANYARGS_DISPATCH((n) == 8, rb_define_protected_method_08, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_07(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_09(n) RBIMPL_ANYARGS_DISPATCH((n) == 9, rb_define_protected_method_09, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_08(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_10(n) RBIMPL_ANYARGS_DISPATCH((n) == 10, rb_define_protected_method_10, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_09(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_11(n) RBIMPL_ANYARGS_DISPATCH((n) == 11, rb_define_protected_method_11, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_10(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_12(n) RBIMPL_ANYARGS_DISPATCH((n) == 12, rb_define_protected_method_12, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_11(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_13(n) RBIMPL_ANYARGS_DISPATCH((n) == 13, rb_define_protected_method_13, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_12(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_14(n) RBIMPL_ANYARGS_DISPATCH((n) == 14, rb_define_protected_method_14, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_13(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_15(n) RBIMPL_ANYARGS_DISPATCH((n) == 15, rb_define_protected_method_15, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_14(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_m2(n) RBIMPL_ANYARGS_DISPATCH((n) == -2, rb_define_private_method_m2, rb_define_private_method_m3)
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_m1(n) RBIMPL_ANYARGS_DISPATCH((n) == -1, rb_define_private_method_m1, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_m2(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_00(n) RBIMPL_ANYARGS_DISPATCH((n) == 0, rb_define_private_method_00, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_m1(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_01(n) RBIMPL_ANYARGS_DISPATCH((n) == 1, rb_define_private_method_01, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_00(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_02(n) RBIMPL_ANYARGS_DISPATCH((n) == 2, rb_define_private_method_02, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_01(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_03(n) RBIMPL_ANYARGS_DISPATCH((n) == 3, rb_define_private_method_03, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_02(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_04(n) RBIMPL_ANYARGS_DISPATCH((n) == 4, rb_define_private_method_04, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_03(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_05(n) RBIMPL_ANYARGS_DISPATCH((n) == 5, rb_define_private_method_05, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_04(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_06(n) RBIMPL_ANYARGS_DISPATCH((n) == 6, rb_define_private_method_06, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_05(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_07(n) RBIMPL_ANYARGS_DISPATCH((n) == 7, rb_define_private_method_07, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_06(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_08(n) RBIMPL_ANYARGS_DISPATCH((n) == 8, rb_define_private_method_08, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_07(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_09(n) RBIMPL_ANYARGS_DISPATCH((n) == 9, rb_define_private_method_09, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_08(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_10(n) RBIMPL_ANYARGS_DISPATCH((n) == 10, rb_define_private_method_10, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_09(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_11(n) RBIMPL_ANYARGS_DISPATCH((n) == 11, rb_define_private_method_11, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_10(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_12(n) RBIMPL_ANYARGS_DISPATCH((n) == 12, rb_define_private_method_12, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_11(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_13(n) RBIMPL_ANYARGS_DISPATCH((n) == 13, rb_define_private_method_13, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_12(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_14(n) RBIMPL_ANYARGS_DISPATCH((n) == 14, rb_define_private_method_14, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_13(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_15(n) RBIMPL_ANYARGS_DISPATCH((n) == 15, rb_define_private_method_15, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_14(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_m2(n) RBIMPL_ANYARGS_DISPATCH((n) == -2, rb_define_module_function_m2, rb_define_module_function_m3)
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_m1(n) RBIMPL_ANYARGS_DISPATCH((n) == -1, rb_define_module_function_m1, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_m2(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_00(n) RBIMPL_ANYARGS_DISPATCH((n) == 0, rb_define_module_function_00, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_m1(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_01(n) RBIMPL_ANYARGS_DISPATCH((n) == 1, rb_define_module_function_01, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_00(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_02(n) RBIMPL_ANYARGS_DISPATCH((n) == 2, rb_define_module_function_02, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_01(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_03(n) RBIMPL_ANYARGS_DISPATCH((n) == 3, rb_define_module_function_03, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_02(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_04(n) RBIMPL_ANYARGS_DISPATCH((n) == 4, rb_define_module_function_04, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_03(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_05(n) RBIMPL_ANYARGS_DISPATCH((n) == 5, rb_define_module_function_05, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_04(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_06(n) RBIMPL_ANYARGS_DISPATCH((n) == 6, rb_define_module_function_06, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_05(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_07(n) RBIMPL_ANYARGS_DISPATCH((n) == 7, rb_define_module_function_07, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_06(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_08(n) RBIMPL_ANYARGS_DISPATCH((n) == 8, rb_define_module_function_08, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_07(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_09(n) RBIMPL_ANYARGS_DISPATCH((n) == 9, rb_define_module_function_09, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_08(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_10(n) RBIMPL_ANYARGS_DISPATCH((n) == 10, rb_define_module_function_10, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_09(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_11(n) RBIMPL_ANYARGS_DISPATCH((n) == 11, rb_define_module_function_11, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_10(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_12(n) RBIMPL_ANYARGS_DISPATCH((n) == 12, rb_define_module_function_12, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_11(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_13(n) RBIMPL_ANYARGS_DISPATCH((n) == 13, rb_define_module_function_13, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_12(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_14(n) RBIMPL_ANYARGS_DISPATCH((n) == 14, rb_define_module_function_14, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_13(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_15(n) RBIMPL_ANYARGS_DISPATCH((n) == 15, rb_define_module_function_15, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_14(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_m2(n) RBIMPL_ANYARGS_DISPATCH((n) == -2, rb_define_global_function_m2, rb_define_global_function_m3)
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_m1(n) RBIMPL_ANYARGS_DISPATCH((n) == -1, rb_define_global_function_m1, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_m2(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_00(n) RBIMPL_ANYARGS_DISPATCH((n) == 0, rb_define_global_function_00, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_m1(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_01(n) RBIMPL_ANYARGS_DISPATCH((n) == 1, rb_define_global_function_01, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_00(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_02(n) RBIMPL_ANYARGS_DISPATCH((n) == 2, rb_define_global_function_02, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_01(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_03(n) RBIMPL_ANYARGS_DISPATCH((n) == 3, rb_define_global_function_03, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_02(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_04(n) RBIMPL_ANYARGS_DISPATCH((n) == 4, rb_define_global_function_04, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_03(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_05(n) RBIMPL_ANYARGS_DISPATCH((n) == 5, rb_define_global_function_05, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_04(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_06(n) RBIMPL_ANYARGS_DISPATCH((n) == 6, rb_define_global_function_06, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_05(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_07(n) RBIMPL_ANYARGS_DISPATCH((n) == 7, rb_define_global_function_07, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_06(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_08(n) RBIMPL_ANYARGS_DISPATCH((n) == 8, rb_define_global_function_08, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_07(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_09(n) RBIMPL_ANYARGS_DISPATCH((n) == 9, rb_define_global_function_09, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_08(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_10(n) RBIMPL_ANYARGS_DISPATCH((n) == 10, rb_define_global_function_10, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_09(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_11(n) RBIMPL_ANYARGS_DISPATCH((n) == 11, rb_define_global_function_11, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_10(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_12(n) RBIMPL_ANYARGS_DISPATCH((n) == 12, rb_define_global_function_12, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_11(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_13(n) RBIMPL_ANYARGS_DISPATCH((n) == 13, rb_define_global_function_13, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_12(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_14(n) RBIMPL_ANYARGS_DISPATCH((n) == 14, rb_define_global_function_14, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_13(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_15(n) RBIMPL_ANYARGS_DISPATCH((n) == 15, rb_define_global_function_15, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_14(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_m2(n) RBIMPL_ANYARGS_DISPATCH((n) == -2, rb_define_method_id_m2, rb_define_method_id_m3)
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_m1(n) RBIMPL_ANYARGS_DISPATCH((n) == -1, rb_define_method_id_m1, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_m2(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_00(n) RBIMPL_ANYARGS_DISPATCH((n) == 0, rb_define_method_id_00, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_m1(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_01(n) RBIMPL_ANYARGS_DISPATCH((n) == 1, rb_define_method_id_01, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_00(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_02(n) RBIMPL_ANYARGS_DISPATCH((n) == 2, rb_define_method_id_02, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_01(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_03(n) RBIMPL_ANYARGS_DISPATCH((n) == 3, rb_define_method_id_03, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_02(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_04(n) RBIMPL_ANYARGS_DISPATCH((n) == 4, rb_define_method_id_04, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_03(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_05(n) RBIMPL_ANYARGS_DISPATCH((n) == 5, rb_define_method_id_05, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_04(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_06(n) RBIMPL_ANYARGS_DISPATCH((n) == 6, rb_define_method_id_06, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_05(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_07(n) RBIMPL_ANYARGS_DISPATCH((n) == 7, rb_define_method_id_07, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_06(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_08(n) RBIMPL_ANYARGS_DISPATCH((n) == 8, rb_define_method_id_08, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_07(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_09(n) RBIMPL_ANYARGS_DISPATCH((n) == 9, rb_define_method_id_09, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_08(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_10(n) RBIMPL_ANYARGS_DISPATCH((n) == 10, rb_define_method_id_10, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_09(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_11(n) RBIMPL_ANYARGS_DISPATCH((n) == 11, rb_define_method_id_11, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_10(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_12(n) RBIMPL_ANYARGS_DISPATCH((n) == 12, rb_define_method_id_12, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_11(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_13(n) RBIMPL_ANYARGS_DISPATCH((n) == 13, rb_define_method_id_13, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_12(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_14(n) RBIMPL_ANYARGS_DISPATCH((n) == 14, rb_define_method_id_14, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_13(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_15(n) RBIMPL_ANYARGS_DISPATCH((n) == 15, rb_define_method_id_15, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_14(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_m2(n) RBIMPL_ANYARGS_DISPATCH((n) == -2, rb_define_method_m2, rb_define_method_m3)
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_m1(n) RBIMPL_ANYARGS_DISPATCH((n) == -1, rb_define_method_m1, RBIMPL_ANYARGS_DISPATCH_rb_define_method_m2(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_00(n) RBIMPL_ANYARGS_DISPATCH((n) == 0, rb_define_method_00, RBIMPL_ANYARGS_DISPATCH_rb_define_method_m1(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_01(n) RBIMPL_ANYARGS_DISPATCH((n) == 1, rb_define_method_01, RBIMPL_ANYARGS_DISPATCH_rb_define_method_00(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_02(n) RBIMPL_ANYARGS_DISPATCH((n) == 2, rb_define_method_02, RBIMPL_ANYARGS_DISPATCH_rb_define_method_01(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_03(n) RBIMPL_ANYARGS_DISPATCH((n) == 3, rb_define_method_03, RBIMPL_ANYARGS_DISPATCH_rb_define_method_02(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_04(n) RBIMPL_ANYARGS_DISPATCH((n) == 4, rb_define_method_04, RBIMPL_ANYARGS_DISPATCH_rb_define_method_03(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_05(n) RBIMPL_ANYARGS_DISPATCH((n) == 5, rb_define_method_05, RBIMPL_ANYARGS_DISPATCH_rb_define_method_04(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_06(n) RBIMPL_ANYARGS_DISPATCH((n) == 6, rb_define_method_06, RBIMPL_ANYARGS_DISPATCH_rb_define_method_05(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_07(n) RBIMPL_ANYARGS_DISPATCH((n) == 7, rb_define_method_07, RBIMPL_ANYARGS_DISPATCH_rb_define_method_06(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_08(n) RBIMPL_ANYARGS_DISPATCH((n) == 8, rb_define_method_08, RBIMPL_ANYARGS_DISPATCH_rb_define_method_07(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_09(n) RBIMPL_ANYARGS_DISPATCH((n) == 9, rb_define_method_09, RBIMPL_ANYARGS_DISPATCH_rb_define_method_08(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_10(n) RBIMPL_ANYARGS_DISPATCH((n) == 10, rb_define_method_10, RBIMPL_ANYARGS_DISPATCH_rb_define_method_09(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_11(n) RBIMPL_ANYARGS_DISPATCH((n) == 11, rb_define_method_11, RBIMPL_ANYARGS_DISPATCH_rb_define_method_10(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_12(n) RBIMPL_ANYARGS_DISPATCH((n) == 12, rb_define_method_12, RBIMPL_ANYARGS_DISPATCH_rb_define_method_11(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_13(n) RBIMPL_ANYARGS_DISPATCH((n) == 13, rb_define_method_13, RBIMPL_ANYARGS_DISPATCH_rb_define_method_12(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_14(n) RBIMPL_ANYARGS_DISPATCH((n) == 14, rb_define_method_14, RBIMPL_ANYARGS_DISPATCH_rb_define_method_13(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_15(n) RBIMPL_ANYARGS_DISPATCH((n) == 15, rb_define_method_15, RBIMPL_ANYARGS_DISPATCH_rb_define_method_14(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method(n,f) RBIMPL_ANYARGS_DISPATCH(RBIMPL_CFUNC_IS_rb_f_notimplement(f), rb_define_singleton_method_m3, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_15(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method(n,f) RBIMPL_ANYARGS_DISPATCH(RBIMPL_CFUNC_IS_rb_f_notimplement(f), rb_define_protected_method_m3, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_15(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method(n,f) RBIMPL_ANYARGS_DISPATCH(RBIMPL_CFUNC_IS_rb_f_notimplement(f), rb_define_private_method_m3, RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_15(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function(n,f) RBIMPL_ANYARGS_DISPATCH(RBIMPL_CFUNC_IS_rb_f_notimplement(f), rb_define_module_function_m3, RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_15(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function(n,f) RBIMPL_ANYARGS_DISPATCH(RBIMPL_CFUNC_IS_rb_f_notimplement(f), rb_define_global_function_m3, RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_15(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id(n,f) RBIMPL_ANYARGS_DISPATCH(RBIMPL_CFUNC_IS_rb_f_notimplement(f), rb_define_method_id_m3, RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_15(n))
#define RBIMPL_ANYARGS_DISPATCH_rb_define_method(n,f) RBIMPL_ANYARGS_DISPATCH(RBIMPL_CFUNC_IS_rb_f_notimplement(f), rb_define_method_m3, RBIMPL_ANYARGS_DISPATCH_rb_define_method_15(n))
#define RBIMPL_ANYARGS_ATTRSET(sym) RBIMPL_ATTR_MAYBE_UNUSED() RBIMPL_ATTR_NONNULL(()) RBIMPL_ATTR_WEAKREF(sym)
#define RBIMPL_ANYARGS_DECL(sym,...) RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _m3(__VA_ARGS__, VALUE(*)(ANYARGS), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _m2(__VA_ARGS__, VALUE(*)(VALUE, VALUE), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _m1(__VA_ARGS__, VALUE(*)(int, union { VALUE *x; const VALUE *y; } __attribute__((__transparent_union__)), VALUE), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _00(__VA_ARGS__, VALUE(*)(VALUE), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _01(__VA_ARGS__, VALUE(*)(VALUE, VALUE), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _02(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _03(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _04(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _05(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _06(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _07(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _08(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _09(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _10(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _11(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _12(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _13(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _14(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _15(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int);
#define rb_define_method(klass,mid,func,arity) RBIMPL_ANYARGS_DISPATCH_rb_define_method((arity), (func))((klass), (mid), (func), (arity))
#define rb_define_method_id(klass,mid,func,arity) RBIMPL_ANYARGS_DISPATCH_rb_define_method_id((arity), (func))((klass), (mid), (func), (arity))
#define rb_define_singleton_method(obj,mid,func,arity) RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method((arity), (func))((obj), (mid), (func), (arity))
#define rb_define_protected_method(klass,mid,func,arity) RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method((arity), (func))((klass), (mid), (func), (arity))
#define rb_define_private_method(klass,mid,func,arity) RBIMPL_ANYARGS_DISPATCH_rb_define_private_method((arity), (func))((klass), (mid), (func), (arity))
#define rb_define_module_function(mod,mid,func,arity) RBIMPL_ANYARGS_DISPATCH_rb_define_module_function((arity), (func))((mod), (mid), (func), (arity))
#define rb_define_global_function(mid,func,arity) RBIMPL_ANYARGS_DISPATCH_rb_define_global_function((arity), (func))((mid), (func), (arity))
#define RUBY_METHOD_FUNC(func) RBIMPL_CAST((VALUE (*)(ANYARGS))(func))
#define RBIMPL_ARITHMETIC_H 
#define RBIMPL_ARITHMETIC_CHAR_H 
#define RBIMPL_ARITHMETIC_INT_H 
#define RBIMPL_ARITHMETIC_FIXNUM_H 
#define FIXABLE RB_FIXABLE
#define FIXNUM_MAX RUBY_FIXNUM_MAX
#define FIXNUM_MIN RUBY_FIXNUM_MIN
#define NEGFIXABLE RB_NEGFIXABLE
#define POSFIXABLE RB_POSFIXABLE
#define RB_POSFIXABLE(_) ((_) < RUBY_FIXNUM_MAX + 1)
#define RB_NEGFIXABLE(_) ((_) >= RUBY_FIXNUM_MIN)
#define RB_FIXABLE(_) (RB_POSFIXABLE(_) && RB_NEGFIXABLE(_))
#define RUBY_FIXNUM_MAX (LONG_MAX / 2)
#define RUBY_FIXNUM_MIN (LONG_MIN / 2)
#define RBIMPL_ARITHMETIC_INTPTR_T_H 
#define rb_int_new rb_int2inum
#define rb_uint_new rb_uint2inum
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_ARITHMETIC_LONG_H 
#define RBIMPL_ATTR_ARTIFICIAL_H 
#define RBIMPL_ATTR_ARTIFICIAL() __attribute__((__artificial__))
#define RBIMPL_ATTR_CONSTEXPR_H 
#define RBIMPL_HAS_ATTR_CONSTEXPR_CXX11 0
#define RBIMPL_HAS_ATTR_CONSTEXPR_CXX14 0
#define RBIMPL_ATTR_CONSTEXPR(_) 
#define RBIMPL_ATTR_CONSTEXPR_UNLESS_DEBUG(_) RBIMPL_ATTR_CONSTEXPR(_)
#define RBIMPL_SPECIAL_CONSTS_H 
#define RBIMPL_ATTR_ENUM_EXTENSIBILITY_H 
#define RBIMPL_ATTR_ENUM_EXTENSIBILITY(_) 
#define USE_FLONUM 1
#define RTEST RB_TEST
#define FIXNUM_P RB_FIXNUM_P
#define IMMEDIATE_P RB_IMMEDIATE_P
#define NIL_P RB_NIL_P
#define SPECIAL_CONST_P RB_SPECIAL_CONST_P
#define STATIC_SYM_P RB_STATIC_SYM_P
#define Qfalse RUBY_Qfalse
#define Qnil RUBY_Qnil
#define Qtrue RUBY_Qtrue
#define Qundef RUBY_Qundef
#define FIXNUM_FLAG RUBY_FIXNUM_FLAG
#define FLONUM_FLAG RUBY_FLONUM_FLAG
#define FLONUM_MASK RUBY_FLONUM_MASK
#define FLONUM_P RB_FLONUM_P
#define IMMEDIATE_MASK RUBY_IMMEDIATE_MASK
#define SYMBOL_FLAG RUBY_SYMBOL_FLAG
#define RB_FIXNUM_P RB_FIXNUM_P
#define RB_FLONUM_P RB_FLONUM_P
#define RB_IMMEDIATE_P RB_IMMEDIATE_P
#define RB_NIL_P RB_NIL_P
#define RB_SPECIAL_CONST_P RB_SPECIAL_CONST_P
#define RB_STATIC_SYM_P RB_STATIC_SYM_P
#define RB_TEST RB_TEST
#define RUBY_Qfalse RBIMPL_CAST((VALUE)RUBY_Qfalse)
#define RUBY_Qtrue RBIMPL_CAST((VALUE)RUBY_Qtrue)
#define RUBY_Qnil RBIMPL_CAST((VALUE)RUBY_Qnil)
#define RUBY_Qundef RBIMPL_CAST((VALUE)RUBY_Qundef)
#define FIX2LONG RB_FIX2LONG
#define FIX2ULONG RB_FIX2ULONG
#define INT2FIX RB_INT2FIX
#define LONG2FIX RB_INT2FIX
#define LONG2NUM RB_LONG2NUM
#define NUM2LONG RB_NUM2LONG
#define NUM2ULONG RB_NUM2ULONG
#define RB_FIX2LONG rb_fix2long
#define RB_FIX2ULONG rb_fix2ulong
#define RB_LONG2FIX RB_INT2FIX
#define RB_LONG2NUM rb_long2num_inline
#define RB_NUM2LONG rb_num2long_inline
#define RB_NUM2ULONG rb_num2ulong_inline
#define RB_ULONG2NUM rb_ulong2num_inline
#define ULONG2NUM RB_ULONG2NUM
#define rb_fix_new RB_INT2FIX
#define rb_long2int rb_long2int_inline
#define RB_INT2FIX RB_INT2FIX
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#undef INT2FIX
#define INT2FIX(i) __builtin_choose_expr( __builtin_constant_p(i), RBIMPL_CAST((VALUE)(i)) << 1 | RUBY_FIXNUM_FLAG, RB_INT2FIX(i))
#define RB_INT2NUM rb_int2num_inline
#define RB_NUM2INT rb_num2int_inline
#define RB_UINT2NUM rb_uint2num_inline
#define FIX2INT RB_FIX2INT
#define FIX2UINT RB_FIX2UINT
#define INT2NUM RB_INT2NUM
#define NUM2INT RB_NUM2INT
#define NUM2UINT RB_NUM2UINT
#define UINT2NUM RB_UINT2NUM
#define RB_FIX2INT RB_FIX2INT
#define RB_NUM2UINT RB_NUM2UINT
#define RB_FIX2UINT RB_FIX2UINT
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wtype-limits"
#pragma GCC diagnostic pop
#define RBIMPL_RSTRING_H 
#define RBIMPL_RBASIC_H 
#define RBIMPL_ATTR_NOALIAS_H 
#define RBIMPL_ATTR_NOALIAS() 
#define RBASIC(obj) RBIMPL_CAST((struct RBasic *)(obj))
#define RBASIC_CLASS RBASIC_CLASS
#define RBIMPL_RVALUE_EMBED_LEN_MAX 3
#define RVALUE_EMBED_LEN_MAX RVALUE_EMBED_LEN_MAX
#define RBIMPL_EMBED_LEN_MAX_OF(T) RBIMPL_CAST((int)(sizeof(VALUE[RBIMPL_RVALUE_EMBED_LEN_MAX]) / (sizeof(T))))
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_FL_TYPE_H 
#define RBIMPL_ATTR_FLAG_ENUM_H 
#define RBIMPL_ATTR_FLAG_ENUM() 
#define RBIMPL_VALUE_TYPE_H 
#define RBIMPL_CONSTANT_P_H 
#define RBIMPL_CONSTANT_P(expr) __builtin_constant_p(expr)
#define RBIMPL_ERROR_H 
#define RB_IO_WAIT_READABLE RB_IO_WAIT_READABLE
#define RB_IO_WAIT_WRITABLE RB_IO_WAIT_WRITABLE
#pragma GCC visibility push(default)
#define ruby_verbose (*rb_ruby_verbose_ptr())
#define ruby_debug (*rb_ruby_debug_ptr())
#pragma GCC visibility pop
#define T_ARRAY RUBY_T_ARRAY
#define T_BIGNUM RUBY_T_BIGNUM
#define T_CLASS RUBY_T_CLASS
#define T_COMPLEX RUBY_T_COMPLEX
#define T_DATA RUBY_T_DATA
#define T_FALSE RUBY_T_FALSE
#define T_FILE RUBY_T_FILE
#define T_FIXNUM RUBY_T_FIXNUM
#define T_FLOAT RUBY_T_FLOAT
#define T_HASH RUBY_T_HASH
#define T_ICLASS RUBY_T_ICLASS
#define T_IMEMO RUBY_T_IMEMO
#define T_MASK RUBY_T_MASK
#define T_MATCH RUBY_T_MATCH
#define T_MODULE RUBY_T_MODULE
#define T_MOVED RUBY_T_MOVED
#define T_NIL RUBY_T_NIL
#define T_NODE RUBY_T_NODE
#define T_NONE RUBY_T_NONE
#define T_OBJECT RUBY_T_OBJECT
#define T_RATIONAL RUBY_T_RATIONAL
#define T_REGEXP RUBY_T_REGEXP
#define T_STRING RUBY_T_STRING
#define T_STRUCT RUBY_T_STRUCT
#define T_SYMBOL RUBY_T_SYMBOL
#define T_TRUE RUBY_T_TRUE
#define T_UNDEF RUBY_T_UNDEF
#define T_ZOMBIE RUBY_T_ZOMBIE
#define BUILTIN_TYPE RB_BUILTIN_TYPE
#define DYNAMIC_SYM_P RB_DYNAMIC_SYM_P
#define RB_INTEGER_TYPE_P rb_integer_type_p
#define SYMBOL_P RB_SYMBOL_P
#define rb_type_p RB_TYPE_P
#define RB_BUILTIN_TYPE RB_BUILTIN_TYPE
#define RB_DYNAMIC_SYM_P RB_DYNAMIC_SYM_P
#define RB_FLOAT_TYPE_P RB_FLOAT_TYPE_P
#define RB_SYMBOL_P RB_SYMBOL_P
#define RB_TYPE_P RB_TYPE_P
#define Check_Type Check_Type
#define RBIMPL_ASSERT_TYPE(v,t) RBIMPL_ASSERT_OR_ASSUME(RB_TYPE_P((v), (t)))
#define TYPE(_) RBIMPL_CAST((int)rb_type(_))
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_HAVE_ENUM_ATTRIBUTE 1
#define RBIMPL_WIDER_ENUM 1
#define FL_SINGLETON RBIMPL_CAST((VALUE)RUBY_FL_SINGLETON)
#define FL_WB_PROTECTED RBIMPL_CAST((VALUE)RUBY_FL_WB_PROTECTED)
#define FL_PROMOTED0 RBIMPL_CAST((VALUE)RUBY_FL_PROMOTED0)
#define FL_PROMOTED1 RBIMPL_CAST((VALUE)RUBY_FL_PROMOTED1)
#define FL_FINALIZE RBIMPL_CAST((VALUE)RUBY_FL_FINALIZE)
#define FL_TAINT RBIMPL_CAST((VALUE)RUBY_FL_TAINT)
#define FL_SHAREABLE RBIMPL_CAST((VALUE)RUBY_FL_SHAREABLE)
#define FL_UNTRUSTED RBIMPL_CAST((VALUE)RUBY_FL_UNTRUSTED)
#define FL_SEEN_OBJ_ID RBIMPL_CAST((VALUE)RUBY_FL_SEEN_OBJ_ID)
#define FL_EXIVAR RBIMPL_CAST((VALUE)RUBY_FL_EXIVAR)
#define FL_FREEZE RBIMPL_CAST((VALUE)RUBY_FL_FREEZE)
#define FL_USHIFT RBIMPL_CAST((VALUE)RUBY_FL_USHIFT)
#define FL_USER0 RBIMPL_CAST((VALUE)RUBY_FL_USER0)
#define FL_USER1 RBIMPL_CAST((VALUE)RUBY_FL_USER1)
#define FL_USER2 RBIMPL_CAST((VALUE)RUBY_FL_USER2)
#define FL_USER3 RBIMPL_CAST((VALUE)RUBY_FL_USER3)
#define FL_USER4 RBIMPL_CAST((VALUE)RUBY_FL_USER4)
#define FL_USER5 RBIMPL_CAST((VALUE)RUBY_FL_USER5)
#define FL_USER6 RBIMPL_CAST((VALUE)RUBY_FL_USER6)
#define FL_USER7 RBIMPL_CAST((VALUE)RUBY_FL_USER7)
#define FL_USER8 RBIMPL_CAST((VALUE)RUBY_FL_USER8)
#define FL_USER9 RBIMPL_CAST((VALUE)RUBY_FL_USER9)
#define FL_USER10 RBIMPL_CAST((VALUE)RUBY_FL_USER10)
#define FL_USER11 RBIMPL_CAST((VALUE)RUBY_FL_USER11)
#define FL_USER12 RBIMPL_CAST((VALUE)RUBY_FL_USER12)
#define FL_USER13 RBIMPL_CAST((VALUE)RUBY_FL_USER13)
#define FL_USER14 RBIMPL_CAST((VALUE)RUBY_FL_USER14)
#define FL_USER15 RBIMPL_CAST((VALUE)RUBY_FL_USER15)
#define FL_USER16 RBIMPL_CAST((VALUE)RUBY_FL_USER16)
#define FL_USER17 RBIMPL_CAST((VALUE)RUBY_FL_USER17)
#define FL_USER18 RBIMPL_CAST((VALUE)RUBY_FL_USER18)
#define FL_USER19 RBIMPL_CAST((VALUE)(unsigned int)RUBY_FL_USER19)
#define ELTS_SHARED RUBY_ELTS_SHARED
#define RB_OBJ_FREEZE rb_obj_freeze_inline
#define RUBY_ELTS_SHARED RUBY_ELTS_SHARED
#define RB_FL_ABLE RB_FL_ABLE
#define RB_FL_ALL RB_FL_ALL
#define RB_FL_ALL_RAW RB_FL_ALL_RAW
#define RB_FL_ANY RB_FL_ANY
#define RB_FL_ANY_RAW RB_FL_ANY_RAW
#define RB_FL_REVERSE RB_FL_REVERSE
#define RB_FL_REVERSE_RAW RB_FL_REVERSE_RAW
#define RB_FL_SET RB_FL_SET
#define RB_FL_SET_RAW RB_FL_SET_RAW
#define RB_FL_TEST RB_FL_TEST
#define RB_FL_TEST_RAW RB_FL_TEST_RAW
#define RB_FL_UNSET RB_FL_UNSET
#define RB_FL_UNSET_RAW RB_FL_UNSET_RAW
#define RB_OBJ_FREEZE_RAW RB_OBJ_FREEZE_RAW
#define RB_OBJ_FROZEN RB_OBJ_FROZEN
#define RB_OBJ_FROZEN_RAW RB_OBJ_FROZEN_RAW
#define RB_OBJ_INFECT RB_OBJ_INFECT
#define RB_OBJ_INFECT_RAW RB_OBJ_INFECT_RAW
#define RB_OBJ_TAINT RB_OBJ_TAINT
#define RB_OBJ_TAINTABLE RB_OBJ_TAINTABLE
#define RB_OBJ_TAINTED RB_OBJ_TAINTED
#define RB_OBJ_TAINTED_RAW RB_OBJ_TAINTED_RAW
#define RB_OBJ_TAINT_RAW RB_OBJ_TAINT_RAW
#define RB_OBJ_UNTRUST RB_OBJ_TAINT
#define RB_OBJ_UNTRUSTED RB_OBJ_TAINTED
#define FL_ABLE RB_FL_ABLE
#define FL_ALL RB_FL_ALL
#define FL_ALL_RAW RB_FL_ALL_RAW
#define FL_ANY RB_FL_ANY
#define FL_ANY_RAW RB_FL_ANY_RAW
#define FL_REVERSE RB_FL_REVERSE
#define FL_REVERSE_RAW RB_FL_REVERSE_RAW
#define FL_SET RB_FL_SET
#define FL_SET_RAW RB_FL_SET_RAW
#define FL_TEST RB_FL_TEST
#define FL_TEST_RAW RB_FL_TEST_RAW
#define FL_UNSET RB_FL_UNSET
#define FL_UNSET_RAW RB_FL_UNSET_RAW
#define OBJ_FREEZE RB_OBJ_FREEZE
#define OBJ_FREEZE_RAW RB_OBJ_FREEZE_RAW
#define OBJ_FROZEN RB_OBJ_FROZEN
#define OBJ_FROZEN_RAW RB_OBJ_FROZEN_RAW
#define OBJ_INFECT RB_OBJ_INFECT
#define OBJ_INFECT_RAW RB_OBJ_INFECT_RAW
#define OBJ_TAINT RB_OBJ_TAINT
#define OBJ_TAINTABLE RB_OBJ_TAINTABLE
#define OBJ_TAINTED RB_OBJ_TAINTED
#define OBJ_TAINTED_RAW RB_OBJ_TAINTED_RAW
#define OBJ_TAINT_RAW RB_OBJ_TAINT_RAW
#define OBJ_UNTRUST RB_OBJ_UNTRUST
#define OBJ_UNTRUSTED RB_OBJ_UNTRUSTED
#define RBIMPL_FL_USER_N(n) RUBY_FL_USER ##n = (1<<(RUBY_FL_USHIFT+n))
#undef RBIMPL_FL_USER_N
#undef RBIMPL_WIDER_ENUM
#undef RBIMPL_HAVE_ENUM_ATTRIBUTE
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RSTRING(obj) RBIMPL_CAST((struct RString *)(obj))
#define RSTRING_NOEMBED RSTRING_NOEMBED
#define RSTRING_EMBED_LEN_MASK RSTRING_EMBED_LEN_MASK
#define RSTRING_EMBED_LEN_SHIFT RSTRING_EMBED_LEN_SHIFT
#define RSTRING_EMBED_LEN_MAX RSTRING_EMBED_LEN_MAX
#define RSTRING_FSTR RSTRING_FSTR
#define RSTRING_EMBED_LEN RSTRING_EMBED_LEN
#define RSTRING_LEN RSTRING_LEN
#define RSTRING_LENINT RSTRING_LENINT
#define RSTRING_PTR RSTRING_PTR
#define RSTRING_END RSTRING_END
#define StringValue(v) rb_string_value(&(v))
#define StringValuePtr(v) rb_string_value_ptr(&(v))
#define StringValueCStr(v) rb_string_value_cstr(&(v))
#define SafeStringValue(v) StringValue(v)
#define ExportStringValue(v) do { StringValue(v); (v) = rb_str_export(v); } while (0)
#pragma GCC visibility push(default)
#define Check_SafeStr(v) rb_check_safe_str(RBIMPL_CAST((VALUE)(v)))
#pragma GCC visibility pop
#pragma GCC diagnostic push
#pragma GCC diagnostic pop
#define RSTRING_GETMEM(str,ptrvar,lenvar) __extension__ ({ struct RString rbimpl_str = rbimpl_rstring_getmem(str); (ptrvar) = rbimpl_str.as.heap.ptr; (lenvar) = rbimpl_str.as.heap.len; })
#define RB_NUM2CHR rb_num2char_inline
#define NUM2CHR RB_NUM2CHR
#define CHR2FIX RB_CHR2FIX
#define RB_CHR2FIX RB_CHR2FIX
#define RBIMPL_ARITHMETIC_DOUBLE_H 
#define NUM2DBL rb_num2dbl
#define RFLOAT_VALUE rb_float_value
#define DBL2NUM rb_float_new
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_ARITHMETIC_GID_T_H 
#define RBIMPL_ARITHMETIC_LONG_LONG_H 
#define RB_LL2NUM rb_ll2num_inline
#define RB_ULL2NUM rb_ull2num_inline
#define LL2NUM RB_LL2NUM
#define ULL2NUM RB_ULL2NUM
#define RB_NUM2LL rb_num2ll_inline
#define RB_NUM2ULL rb_num2ull_inline
#define NUM2LL RB_NUM2LL
#define NUM2ULL RB_NUM2ULL
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_ARITHMETIC_MODE_T_H 
#define RBIMPL_ARITHMETIC_OFF_T_H 
#define RBIMPL_ARITHMETIC_PID_T_H 
#define RBIMPL_ARITHMETIC_SHORT_H 
#define RB_NUM2SHORT rb_num2short_inline
#define RB_NUM2USHORT rb_num2ushort
#define NUM2SHORT RB_NUM2SHORT
#define NUM2USHORT RB_NUM2USHORT
#define USHORT2NUM RB_INT2FIX
#define RB_FIX2SHORT rb_fix2short
#define FIX2SHORT RB_FIX2SHORT
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_ARITHMETIC_SIZE_T_H 
#define RB_SIZE2NUM RB_ULL2NUM
#define RB_SSIZE2NUM RB_LL2NUM
#define RB_NUM2SIZE RB_NUM2ULL
#define RB_NUM2SSIZE RB_NUM2LL
#define NUM2SIZET RB_NUM2SIZE
#define SIZET2NUM RB_SIZE2NUM
#define NUM2SSIZET RB_NUM2SSIZE
#define SSIZET2NUM RB_SSIZE2NUM
#define RBIMPL_ARITHMERIC_ST_DATA_T_H 
#define RUBY_ST_H 1
#pragma GCC visibility push(default)
#define ST_DATA_T_DEFINED 
#define MAX_ST_INDEX_VAL (~(st_index_t) 0)
#define SIZEOF_ST_INDEX_T SIZEOF_VOIDP
#define ST_INDEX_BITS (SIZEOF_ST_INDEX_T * CHAR_BIT)
#define ST_DATA_COMPATIBLE_P(type) __builtin_choose_expr(__builtin_types_compatible_p(type, st_data_t), 1, 0)
#define st_is_member(table,key) st_lookup((table),(key),(st_data_t *)0)
#define st_init_table rb_st_init_table
#define st_init_table_with_size rb_st_init_table_with_size
#define st_init_numtable rb_st_init_numtable
#define st_init_numtable_with_size rb_st_init_numtable_with_size
#define st_init_strtable rb_st_init_strtable
#define st_init_strtable_with_size rb_st_init_strtable_with_size
#define st_init_strcasetable rb_st_init_strcasetable
#define st_init_strcasetable_with_size rb_st_init_strcasetable_with_size
#define st_delete rb_st_delete
#define st_delete_safe rb_st_delete_safe
#define st_shift rb_st_shift
#define st_insert rb_st_insert
#define st_insert2 rb_st_insert2
#define st_lookup rb_st_lookup
#define st_get_key rb_st_get_key
#define st_update rb_st_update
#define st_foreach_with_replace rb_st_foreach_with_replace
#define st_foreach rb_st_foreach
#define st_foreach_check rb_st_foreach_check
#define st_keys rb_st_keys
#define st_keys_check rb_st_keys_check
#define st_values rb_st_values
#define st_values_check rb_st_values_check
#define st_add_direct rb_st_add_direct
#define st_free_table rb_st_free_table
#define st_cleanup_safe rb_st_cleanup_safe
#define st_clear rb_st_clear
#define st_copy rb_st_copy
#define st_numcmp rb_st_numcmp
#define st_numhash rb_st_numhash
#define st_locale_insensitive_strcasecmp rb_st_locale_insensitive_strcasecmp
#define st_locale_insensitive_strncasecmp rb_st_locale_insensitive_strncasecmp
#define st_strcasecmp rb_st_locale_insensitive_strcasecmp
#define st_strncasecmp rb_st_locale_insensitive_strncasecmp
#define st_memsize rb_st_memsize
#define st_hash rb_st_hash
#define st_hash_uint32 rb_st_hash_uint32
#define st_hash_uint rb_st_hash_uint
#define st_hash_end rb_st_hash_end
#define st_hash_start(h) ((st_index_t)(h))
#pragma GCC visibility pop
#define ST2FIX RB_ST2FIX
#define RB_ST2FIX RB_ST2FIX
#define RBIMPL_ARITHMETIC_UID_T_H 
#define RBIMPL_CORE_H 
#define RBIMPL_RARRAY_H 
#define RBIMPL_RGENGC_H 
#undef USE_RGENGC
#define USE_RGENGC 1
#define USE_RINCGC 1
#define USE_RGENGC_LOGGING_WB_UNPROTECT 0
#define RGENGC_WB_PROTECTED_ARRAY 1
#define RGENGC_WB_PROTECTED_HASH 1
#define RGENGC_WB_PROTECTED_STRUCT 1
#define RGENGC_WB_PROTECTED_STRING 1
#define RGENGC_WB_PROTECTED_OBJECT 1
#define RGENGC_WB_PROTECTED_REGEXP 1
#define RGENGC_WB_PROTECTED_CLASS 1
#define RGENGC_WB_PROTECTED_FLOAT 1
#define RGENGC_WB_PROTECTED_COMPLEX 1
#define RGENGC_WB_PROTECTED_RATIONAL 1
#define RGENGC_WB_PROTECTED_BIGNUM 1
#define RGENGC_WB_PROTECTED_NODE_CREF 1
#define RB_OBJ_WRITE(old,slot,young) RBIMPL_CAST(rb_obj_write((VALUE)(old), (VALUE *)(slot), (VALUE)(young), __FILE__, __LINE__))
#define RB_OBJ_WRITTEN(old,oldv,young) RBIMPL_CAST(rb_obj_written((VALUE)(old), (VALUE)(oldv), (VALUE)(young), __FILE__, __LINE__))
#define OBJ_PROMOTED_RAW RB_OBJ_PROMOTED_RAW
#define OBJ_PROMOTED RB_OBJ_PROMOTED
#define OBJ_WB_UNPROTECT RB_OBJ_WB_UNPROTECT
#define RB_OBJ_WB_UNPROTECT(x) rb_obj_wb_unprotect(x, __FILE__, __LINE__)
#define RB_OBJ_WB_UNPROTECT_FOR(type,obj) (RGENGC_WB_PROTECTED_ ##type ? OBJ_WB_UNPROTECT(obj) : obj)
#define RGENGC_LOGGING_WB_UNPROTECT rb_gc_unprotect_logging
#define RB_OBJ_PROMOTED_RAW RB_OBJ_PROMOTED_RAW
#define RB_OBJ_PROMOTED RB_OBJ_PROMOTED
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define USE_TRANSIENT_HEAP 1
#define RARRAY(obj) RBIMPL_CAST((struct RArray *)(obj))
#define RARRAY_EMBED_FLAG RARRAY_EMBED_FLAG
#define RARRAY_EMBED_LEN_MASK RARRAY_EMBED_LEN_MASK
#define RARRAY_EMBED_LEN_MAX RARRAY_EMBED_LEN_MAX
#define RARRAY_EMBED_LEN_SHIFT RARRAY_EMBED_LEN_SHIFT
#define RARRAY_TRANSIENT_FLAG RARRAY_TRANSIENT_FLAG
#define RARRAY_LEN rb_array_len
#define RARRAY_CONST_PTR rb_array_const_ptr
#define RARRAY_CONST_PTR_TRANSIENT rb_array_const_ptr_transient
#define FIX_CONST_VALUE_PTR(x) (x)
#define RARRAY_EMBED_LEN RARRAY_EMBED_LEN
#define RARRAY_LENINT RARRAY_LENINT
#define RARRAY_TRANSIENT_P RARRAY_TRANSIENT_P
#define RARRAY_ASET RARRAY_ASET
#define RARRAY_PTR RARRAY_PTR
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_RARRAY_STMT(flag,ary,var,expr) do { RBIMPL_ASSERT_TYPE((ary), RUBY_T_ARRAY); const VALUE rbimpl_ary = (ary); VALUE *var = rb_array_ptr_use_start(rbimpl_ary, (flag)); expr; rb_array_ptr_use_end(rbimpl_ary, (flag)); } while (0)
#define RARRAY_PTR_USE_START(a) rb_array_ptr_use_start(a, 0)
#define RARRAY_PTR_USE_END(a) rb_array_ptr_use_end(a, 0)
#define RARRAY_PTR_USE(ary,ptr_name,expr) RBIMPL_RARRAY_STMT(0, ary, ptr_name, expr)
#define RARRAY_PTR_USE_START_TRANSIENT(a) rb_array_ptr_use_start(a, 1)
#define RARRAY_PTR_USE_END_TRANSIENT(a) rb_array_ptr_use_end(a, 1)
#define RARRAY_PTR_USE_TRANSIENT(ary,ptr_name,expr) RBIMPL_RARRAY_STMT(1, ary, ptr_name, expr)
#define RARRAY_AREF(a,i) RARRAY_CONST_PTR_TRANSIENT(a)[i]
#define RBIMPL_RBIGNUM_H 
#define RBIGNUM_SIGN rb_big_sign
#define RBIGNUM_POSITIVE_P RBIGNUM_POSITIVE_P
#define RBIGNUM_NEGATIVE_P RBIGNUM_NEGATIVE_P
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_RCLASS_H 
#define RMODULE_IS_OVERLAID RMODULE_IS_OVERLAID
#define RMODULE_IS_REFINEMENT RMODULE_IS_REFINEMENT
#define RMODULE_INCLUDED_INTO_REFINEMENT RMODULE_INCLUDED_INTO_REFINEMENT
#define RCLASS(obj) RBIMPL_CAST((struct RClass *)(obj))
#define RMODULE RCLASS
#define RCLASS_SUPER rb_class_get_superclass
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_RDATA_H 
#define RUBY_UNTYPED_DATA_WARNING 1
#define RBIMPL_DATA_FUNC(f) RBIMPL_CAST((void (*)(void *))(f))
#define RBIMPL_ATTRSET_UNTYPED_DATA_FUNC() RBIMPL_ATTR_WARNING(("untyped Data is unsafe; use TypedData instead")) RBIMPL_ATTR_DEPRECATED(("by TypedData"))
#define RBIMPL_MACRO_SELECT(x,y) x ## y
#define RUBY_MACRO_SELECT(x,y) RBIMPL_MACRO_SELECT(x, y)
#define RDATA(obj) RBIMPL_CAST((struct RData *)(obj))
#define DATA_PTR(obj) RDATA(obj)->data
#define RUBY_DEFAULT_FREE RBIMPL_DATA_FUNC(-1)
#define RUBY_NEVER_FREE RBIMPL_DATA_FUNC(0)
#define RUBY_UNTYPED_DATA_FUNC(f) f RBIMPL_ATTRSET_UNTYPED_DATA_FUNC()
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define Data_Wrap_Struct(klass,mark,free,sval) rb_data_object_wrap( (klass), (sval), RBIMPL_DATA_FUNC(mark), RBIMPL_DATA_FUNC(free))
#define Data_Make_Struct0(result,klass,type,size,mark,free,sval) VALUE result = rb_data_object_zalloc( (klass), (size), RBIMPL_DATA_FUNC(mark), RBIMPL_DATA_FUNC(free)); (sval) = RBIMPL_CAST((type *)DATA_PTR(result)); RBIMPL_CAST( (void)(sval))
#define Data_Make_Struct(klass,type,mark,free,sval) RB_GNUC_EXTENSION({ Data_Make_Struct0( data_struct_obj, klass, type, sizeof(type), mark, free, sval); data_struct_obj; })
#define Data_Get_Struct(obj,type,sval) ((sval) = RBIMPL_CAST((type*)rb_data_object_get(obj)))
#define rb_data_object_wrap_warning(klass,ptr,mark,free) RB_GNUC_EXTENSION( __builtin_choose_expr( __builtin_constant_p(klass) && !(klass), rb_data_object_wrap(klass, ptr, mark, free), (rb_data_object_wrap_warning)(klass, ptr, mark, free)))
#define rb_cData rb_cData()
#define rb_data_object_wrap_0 rb_data_object_wrap
#define rb_data_object_wrap_1 rb_data_object_wrap_warning
#define rb_data_object_wrap_2 rb_data_object_wrap_
#define rb_data_object_wrap RUBY_MACRO_SELECT(rb_data_object_wrap_2, RUBY_UNTYPED_DATA_WARNING)
#define rb_data_object_get_0 rb_data_object_get
#define rb_data_object_get_1 rb_data_object_get_warning
#define rb_data_object_get_2 rb_data_object_get_
#define rb_data_object_get RUBY_MACRO_SELECT(rb_data_object_get_2, RUBY_UNTYPED_DATA_WARNING)
#define rb_data_object_make_0 rb_data_object_make
#define rb_data_object_make_1 rb_data_object_make_warning
#define rb_data_object_make_2 rb_data_object_make_
#define rb_data_object_make RUBY_MACRO_SELECT(rb_data_object_make_2, RUBY_UNTYPED_DATA_WARNING)
#define RBIMPL_RFILE_H 
#define RFILE(obj) RBIMPL_CAST((struct RFile *)(obj))
#define RBIMPL_RHASH_H 
#define RHASH_TBL(h) rb_hash_tbl(h, __FILE__, __LINE__)
#define RHASH_ITER_LEV(h) rb_hash_iter_lev(h)
#define RHASH_IFNONE(h) rb_hash_ifnone(h)
#define RHASH_SIZE(h) rb_hash_size_num(h)
#define RHASH_EMPTY_P(h) (RHASH_SIZE(h) == 0)
#define RHASH_SET_IFNONE(h,ifnone) rb_hash_set_ifnone((VALUE)h, ifnone)
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_ROBJECT_H 
#define ROBJECT(obj) RBIMPL_CAST((struct RObject *)(obj))
#define ROBJECT_EMBED_LEN_MAX ROBJECT_EMBED_LEN_MAX
#define ROBJECT_EMBED ROBJECT_EMBED
#define ROBJECT_NUMIV ROBJECT_NUMIV
#define ROBJECT_IVPTR ROBJECT_IVPTR
#define ROBJECT_IV_INDEX_TBL ROBJECT_IV_INDEX_TBL
#define RBIMPL_RREGEXP_H 
#define RREGEXP(obj) RBIMPL_CAST((struct RRegexp *)(obj))
#define RREGEXP_PTR(obj) (RREGEXP(obj)->ptr)
#define RREGEXP_SRC RREGEXP_SRC
#define RREGEXP_SRC_PTR RREGEXP_SRC_PTR
#define RREGEXP_SRC_LEN RREGEXP_SRC_LEN
#define RREGEXP_SRC_END RREGEXP_SRC_END
#define RBIMPL_RSTRUCT_H 
#define RSTRUCT_PTR(st) rb_struct_ptr(st)
#define RSTRUCT_LEN RSTRUCT_LEN
#define RSTRUCT_SET RSTRUCT_SET
#define RSTRUCT_GET RSTRUCT_GET
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_RTYPEDDATA_H 
#define HAVE_TYPE_RB_DATA_TYPE_T 1
#define HAVE_RB_DATA_TYPE_T_FUNCTION 1
#define HAVE_RB_DATA_TYPE_T_PARENT 1
#define RUBY_TYPED_DEFAULT_FREE RUBY_DEFAULT_FREE
#define RUBY_TYPED_NEVER_FREE RUBY_NEVER_FREE
#define RTYPEDDATA(obj) RBIMPL_CAST((struct RTypedData *)(obj))
#define RTYPEDDATA_DATA(v) (RTYPEDDATA(v)->data)
#define Check_TypedStruct(v,t) rb_check_typeddata(RBIMPL_CAST((VALUE)(v)), (t))
#define RTYPEDDATA_P RTYPEDDATA_P
#define RTYPEDDATA_TYPE RTYPEDDATA_TYPE
#define RUBY_TYPED_FREE_IMMEDIATELY RUBY_TYPED_FREE_IMMEDIATELY
#define RUBY_TYPED_FROZEN_SHAREABLE RUBY_TYPED_FROZEN_SHAREABLE
#define RUBY_TYPED_WB_PROTECTED RUBY_TYPED_WB_PROTECTED
#define RUBY_TYPED_PROMOTED1 RUBY_TYPED_PROMOTED1
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define TypedData_Wrap_Struct(klass,data_type,sval) rb_data_typed_object_wrap((klass),(sval),(data_type))
#define TypedData_Make_Struct0(result,klass,type,size,data_type,sval) VALUE result = rb_data_typed_object_zalloc(klass, size, data_type); (sval) = RBIMPL_CAST((type *)RTYPEDDATA_DATA(result)); RBIMPL_CAST( (void)(sval))
#define TypedData_Make_Struct(klass,type,data_type,sval) RB_GNUC_EXTENSION({ TypedData_Make_Struct0( data_struct_obj, klass, type, sizeof(type), data_type, sval); data_struct_obj; })
#define TypedData_Get_Struct(obj,type,data_type,sval) ((sval) = RBIMPL_CAST((type *)rb_check_typeddata((obj), (data_type))))
#define RBIMPL_CTYPE_H 
#define _CTYPE_H 1
#define _ISbit(bit) ((bit) < 8 ? ((1 << (bit)) << 8) : ((1 << (bit)) >> 8))
#define __isctype(c,type) ((*__ctype_b_loc ())[(int) (c)] & (unsigned short int) type)
#define __isascii(c) (((c) & ~0x7f) == 0)
#define __toascii(c) ((c) & 0x7f)
#define __exctype(name) extern int name (int) __THROW
#define __tobody(c,f,a,args) (__extension__ ({ int __res; if (sizeof (c) > 1) { if (__builtin_constant_p (c)) { int __c = (c); __res = __c < -128 || __c > 255 ? __c : (a)[__c]; } else __res = f args; } else __res = (a)[(int) (c)]; __res; }))
#define isalnum(c) __isctype((c), _ISalnum)
#define isalpha(c) __isctype((c), _ISalpha)
#define iscntrl(c) __isctype((c), _IScntrl)
#define isdigit(c) __isctype((c), _ISdigit)
#define islower(c) __isctype((c), _ISlower)
#define isgraph(c) __isctype((c), _ISgraph)
#define isprint(c) __isctype((c), _ISprint)
#define ispunct(c) __isctype((c), _ISpunct)
#define isspace(c) __isctype((c), _ISspace)
#define isupper(c) __isctype((c), _ISupper)
#define isxdigit(c) __isctype((c), _ISxdigit)
#define isblank(c) __isctype((c), _ISblank)
#define isascii(c) __isascii (c)
#define toascii(c) __toascii (c)
#define _tolower(c) ((int) (*__ctype_tolower_loc ())[(int) (c)])
#define _toupper(c) ((int) (*__ctype_toupper_loc ())[(int) (c)])
#define __isctype_l(c,type,locale) ((locale)->__ctype_b[(int) (c)] & (unsigned short int) type)
#define __exctype_l(name) extern int name (int, __locale_t) __THROW
#define __isalnum_l(c,l) __isctype_l((c), _ISalnum, (l))
#define __isalpha_l(c,l) __isctype_l((c), _ISalpha, (l))
#define __iscntrl_l(c,l) __isctype_l((c), _IScntrl, (l))
#define __isdigit_l(c,l) __isctype_l((c), _ISdigit, (l))
#define __islower_l(c,l) __isctype_l((c), _ISlower, (l))
#define __isgraph_l(c,l) __isctype_l((c), _ISgraph, (l))
#define __isprint_l(c,l) __isctype_l((c), _ISprint, (l))
#define __ispunct_l(c,l) __isctype_l((c), _ISpunct, (l))
#define __isspace_l(c,l) __isctype_l((c), _ISspace, (l))
#define __isupper_l(c,l) __isctype_l((c), _ISupper, (l))
#define __isxdigit_l(c,l) __isctype_l((c), _ISxdigit, (l))
#define __isblank_l(c,l) __isctype_l((c), _ISblank, (l))
#define __isascii_l(c,l) ((l), __isascii (c))
#define __toascii_l(c,l) ((l), __toascii (c))
#define isalnum_l(c,l) __isalnum_l ((c), (l))
#define isalpha_l(c,l) __isalpha_l ((c), (l))
#define iscntrl_l(c,l) __iscntrl_l ((c), (l))
#define isdigit_l(c,l) __isdigit_l ((c), (l))
#define islower_l(c,l) __islower_l ((c), (l))
#define isgraph_l(c,l) __isgraph_l ((c), (l))
#define isprint_l(c,l) __isprint_l ((c), (l))
#define ispunct_l(c,l) __ispunct_l ((c), (l))
#define isspace_l(c,l) __isspace_l ((c), (l))
#define isupper_l(c,l) __isupper_l ((c), (l))
#define isxdigit_l(c,l) __isxdigit_l ((c), (l))
#define isblank_l(c,l) __isblank_l ((c), (l))
#define isascii_l(c,l) __isascii_l ((c), (l))
#define toascii_l(c,l) __toascii_l ((c), (l))
#define ISASCII rb_isascii
#define ISPRINT rb_isprint
#define ISGRAPH rb_isgraph
#define ISSPACE rb_isspace
#define ISUPPER rb_isupper
#define ISLOWER rb_islower
#define ISALNUM rb_isalnum
#define ISALPHA rb_isalpha
#define ISDIGIT rb_isdigit
#define ISXDIGIT rb_isxdigit
#define ISBLANK rb_isblank
#define ISCNTRL rb_iscntrl
#define ISPUNCT rb_ispunct
#define TOUPPER rb_toupper
#define TOLOWER rb_tolower
#define STRCASECMP st_locale_insensitive_strcasecmp
#define STRNCASECMP st_locale_insensitive_strncasecmp
#define STRTOUL ruby_strtoul
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_EVAL_H 
#pragma GCC visibility push(default)
#define rb_funcall2 rb_funcallv
#define rb_funcall3 rb_funcallv_public
#pragma GCC visibility pop
#define RBIMPL_EVENT_H 
#define RUBY_EVENT_NONE 0x0000
#define RUBY_EVENT_LINE 0x0001
#define RUBY_EVENT_CLASS 0x0002
#define RUBY_EVENT_END 0x0004
#define RUBY_EVENT_CALL 0x0008
#define RUBY_EVENT_RETURN 0x0010
#define RUBY_EVENT_C_CALL 0x0020
#define RUBY_EVENT_C_RETURN 0x0040
#define RUBY_EVENT_RAISE 0x0080
#define RUBY_EVENT_ALL 0x00ff
#define RUBY_EVENT_B_CALL 0x0100
#define RUBY_EVENT_B_RETURN 0x0200
#define RUBY_EVENT_THREAD_BEGIN 0x0400
#define RUBY_EVENT_THREAD_END 0x0800
#define RUBY_EVENT_FIBER_SWITCH 0x1000
#define RUBY_EVENT_SCRIPT_COMPILED 0x2000
#define RUBY_EVENT_TRACEPOINT_ALL 0xffff
#define RUBY_EVENT_RESERVED_FOR_INTERNAL_USE 0x030000
#define RUBY_INTERNAL_EVENT_SWITCH 0x040000
#define RUBY_EVENT_SWITCH 0x040000
#define RUBY_INTERNAL_EVENT_NEWOBJ 0x100000
#define RUBY_INTERNAL_EVENT_FREEOBJ 0x200000
#define RUBY_INTERNAL_EVENT_GC_START 0x400000
#define RUBY_INTERNAL_EVENT_GC_END_MARK 0x800000
#define RUBY_INTERNAL_EVENT_GC_END_SWEEP 0x1000000
#define RUBY_INTERNAL_EVENT_GC_ENTER 0x2000000
#define RUBY_INTERNAL_EVENT_GC_EXIT 0x4000000
#define RUBY_INTERNAL_EVENT_OBJSPACE_MASK 0x7f00000
#define RUBY_INTERNAL_EVENT_MASK 0xffff0000
#define RB_EVENT_HOOKS_HAVE_CALLBACK_DATA 1
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_GC_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_GLOB_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_GLOBALS_H 
#pragma GCC visibility push(default)
#define RUBY_INTEGER_UNIFICATION 1
#define CLASS_OF rb_class_of
#pragma GCC visibility pop
#define RBIMPL_INTERPRETER_H 
#pragma GCC visibility push(default)
#define RUBY_INIT_STACK VALUE variable_in_this_stack_frame; ruby_init_stack(&variable_in_this_stack_frame);
#pragma GCC visibility pop
#define RBIMPL_ITERATOR_H 
#pragma GCC visibility push(default)
#define RB_BLOCK_CALL_FUNC_STRICT 1
#define RUBY_BLOCK_CALL_FUNC_TAKES_BLOCKARG 1
#define RB_BLOCK_CALL_FUNC_ARGLIST(yielded_arg,callback_arg) VALUE yielded_arg, VALUE callback_arg, int argc, const VALUE *argv, VALUE blockarg
#pragma GCC visibility pop
#define RBIMPL_MEMORY_H 
#define DSIZE_T uint128_t
#define RUBY_ALLOCV_LIMIT 1024
#define RB_GC_GUARD(v) (*__extension__ ({ volatile VALUE *rb_gc_guarded_ptr = &(v); __asm__("" : : "m"(rb_gc_guarded_ptr)); rb_gc_guarded_ptr; }))
#define RB_ALLOC_N(type,n) RBIMPL_CAST((type *)ruby_xmalloc2((n), sizeof(type)))
#define RB_ALLOC(type) RBIMPL_CAST((type *)ruby_xmalloc(sizeof(type)))
#define RB_ZALLOC_N(type,n) RBIMPL_CAST((type *)ruby_xcalloc((n), sizeof(type)))
#define RB_ZALLOC(type) (RB_ZALLOC_N(type, 1))
#define RB_REALLOC_N(var,type,n) ((var) = RBIMPL_CAST((type *)ruby_xrealloc2((void *)(var), (n), sizeof(type))))
#define ALLOCA_N(type,n) RBIMPL_CAST((type *)alloca(rbimpl_size_mul_or_raise(sizeof(type), (n))))
#define RB_ALLOCV(v,n) ((n) < RUBY_ALLOCV_LIMIT ? ((v) = 0, alloca(n)) : rb_alloc_tmp_buffer(&(v), (n)))
#define RB_ALLOCV_N(type,v,n) RBIMPL_CAST((type *) (((size_t)(n) < RUBY_ALLOCV_LIMIT / sizeof(type)) ? ((v) = 0, alloca((n) * sizeof(type))) : rb_alloc_tmp_buffer2(&(v), (n), sizeof(type))))
#define RB_ALLOCV_END(v) rb_free_tmp_buffer(&(v))
#define MEMZERO(p,type,n) memset((p), 0, rbimpl_size_mul_or_raise(sizeof(type), (n)))
#define MEMCPY(p1,p2,type,n) memcpy((p1), (p2), rbimpl_size_mul_or_raise(sizeof(type), (n)))
#define MEMMOVE(p1,p2,type,n) memmove((p1), (p2), rbimpl_size_mul_or_raise(sizeof(type), (n)))
#define MEMCMP(p1,p2,type,n) memcmp((p1), (p2), rbimpl_size_mul_or_raise(sizeof(type), (n)))
#define ALLOC_N RB_ALLOC_N
#define ALLOC RB_ALLOC
#define ZALLOC_N RB_ZALLOC_N
#define ZALLOC RB_ZALLOC
#define REALLOC_N RB_REALLOC_N
#define ALLOCV RB_ALLOCV
#define ALLOCV_N RB_ALLOCV_N
#define ALLOCV_END RB_ALLOCV_END
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#undef memcpy
#define memcpy ruby_nonempty_memcpy
#define RBIMPL_MODULE_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_NEWOBJ_H 
#define RB_NEWOBJ(obj,type) type *(obj) = RBIMPL_CAST((type *)rb_newobj())
#define RB_NEWOBJ_OF(obj,type,klass,flags) type *(obj) = RBIMPL_CAST((type *)rb_newobj_of(klass, flags))
#define NEWOBJ RB_NEWOBJ
#define NEWOBJ_OF RB_NEWOBJ_OF
#define OBJSETUP rb_obj_setup
#define CLONESETUP rb_clone_setup
#define DUPSETUP rb_dup_setup
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_SCAN_ARGS_H 
#define RBIMPL_ATTR_DIAGNOSE_IF_H 
#define RBIMPL_ATTR_DIAGNOSE_IF(_,__,___) 
#define RBIMPL_INTERN_ARRAY_H 
#pragma GCC visibility push(default)
#define rb_ary_new2 rb_ary_new_capa
#define rb_ary_new3 rb_ary_new_from_args
#define rb_ary_new4 rb_ary_new_from_values
#pragma GCC visibility pop
#define RBIMPL_INTERN_ERROR_H 
#define UNLIMITED_ARGUMENTS (-1)
#define rb_exc_new2 rb_exc_new_cstr
#define rb_exc_new3 rb_exc_new_str
#define rb_check_trusted rb_check_trusted
#define rb_check_trusted_inline rb_check_trusted
#define rb_check_arity rb_check_arity
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define rb_check_frozen_internal(obj) do { VALUE frozen_obj = (obj); if (RB_UNLIKELY(RB_OBJ_FROZEN(frozen_obj))) { rb_error_frozen_object(frozen_obj); } } while (0)
#define rb_check_frozen rb_check_frozen_inline
#define RBIMPL_INTERN_HASH_H 
#pragma GCC visibility push(default)
#define st_foreach_safe rb_st_foreach_safe
#pragma GCC visibility pop
#define RBIMPL_INTERN_PROC_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RB_SCAN_ARGS_PASS_CALLED_KEYWORDS 0
#define RB_SCAN_ARGS_KEYWORDS 1
#define RB_SCAN_ARGS_LAST_HASH_KEYWORDS 3
#define RB_NO_KEYWORDS 0
#define RB_PASS_KEYWORDS 1
#define RB_PASS_CALLED_KEYWORDS rb_keyword_given_p()
#define HAVE_RB_SCAN_ARGS_OPTIONAL_HASH 1
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define rb_scan_args_isdigit(c) (RBIMPL_CAST((unsigned char)((c)-'0'))<10)
#define rb_scan_args_count_end(fmt,ofs,vari) ((fmt)[ofs] ? -1 : (vari))
#define rb_scan_args_count_block(fmt,ofs,vari) ((fmt)[ofs]!='&' ? rb_scan_args_count_end(fmt, ofs, vari) : rb_scan_args_count_end(fmt, (ofs)+1, (vari)+1))
#define rb_scan_args_count_hash(fmt,ofs,vari) ((fmt)[ofs]!=':' ? rb_scan_args_count_block(fmt, ofs, vari) : rb_scan_args_count_block(fmt, (ofs)+1, (vari)+1))
#define rb_scan_args_count_trail(fmt,ofs,vari) (!rb_scan_args_isdigit((fmt)[ofs]) ? rb_scan_args_count_hash(fmt, ofs, vari) : rb_scan_args_count_hash(fmt, (ofs)+1, (vari)+((fmt)[ofs]-'0')))
#define rb_scan_args_count_var(fmt,ofs,vari) ((fmt)[ofs]!='*' ? rb_scan_args_count_trail(fmt, ofs, vari) : rb_scan_args_count_trail(fmt, (ofs)+1, (vari)+1))
#define rb_scan_args_count_opt(fmt,ofs,vari) (!rb_scan_args_isdigit((fmt)[ofs]) ? rb_scan_args_count_var(fmt, ofs, vari) : rb_scan_args_count_var(fmt, (ofs)+1, (vari)+(fmt)[ofs]-'0'))
#define rb_scan_args_count_lead(fmt,ofs,vari) (!rb_scan_args_isdigit((fmt)[ofs]) ? rb_scan_args_count_var(fmt, ofs, vari) : rb_scan_args_count_opt(fmt, (ofs)+1, (vari)+(fmt)[ofs]-'0'))
#define rb_scan_args_count(fmt) rb_scan_args_count_lead(fmt, 0, 0)
#define rb_scan_args_verify(fmt,varc) (sizeof(char[1-2*(rb_scan_args_count(fmt)<0)])!=1 ? rb_scan_args_bad_format(fmt) : sizeof(char[1-2*(rb_scan_args_count(fmt)!=(varc))])!=1 ? rb_scan_args_length_mismatch(fmt, varc) : RBIMPL_ASSERT_NOTHING)
#define rb_scan_args0(argc,argv,fmt,varc,vars) rb_scan_args_set(RB_SCAN_ARGS_PASS_CALLED_KEYWORDS, argc, argv, rb_scan_args_n_lead(fmt), rb_scan_args_n_opt(fmt), rb_scan_args_n_trail(fmt), rb_scan_args_f_var(fmt), rb_scan_args_f_hash(fmt), rb_scan_args_f_block(fmt), (rb_scan_args_verify(fmt, varc), vars), (char *)fmt, varc)
#define rb_scan_args_kw0(kw_flag,argc,argv,fmt,varc,vars) rb_scan_args_set(kw_flag, argc, argv, rb_scan_args_n_lead(fmt), rb_scan_args_n_opt(fmt), rb_scan_args_n_trail(fmt), rb_scan_args_f_var(fmt), rb_scan_args_f_hash(fmt), rb_scan_args_f_block(fmt), (rb_scan_args_verify(fmt, varc), vars), (char *)fmt, varc)
#define rb_scan_args_next_param() vars[vari++]
#undef rb_scan_args_next_param
#define RBIMPL_SYMBOL_H 
#define RB_ID2SYM rb_id2sym
#define RB_SYM2ID rb_sym2id
#define ID2SYM RB_ID2SYM
#define SYM2ID RB_SYM2ID
#define CONST_ID_CACHE RUBY_CONST_ID_CACHE
#define CONST_ID RUBY_CONST_ID
#define rb_intern_const rb_intern_const
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RUBY_CONST_ID_CACHE(result,str) { static ID rb_intern_id_cache; rbimpl_intern_const(&rb_intern_id_cache, (str)); result rb_intern_id_cache; }
#define RUBY_CONST_ID(var,str) do { static ID rbimpl_id; (var) = rbimpl_intern_const(&rbimpl_id, (str)); } while (0)
#define rb_intern(str) (RBIMPL_CONSTANT_P(str) ? __extension__ ({ static ID rbimpl_id; rbimpl_intern_const(&rbimpl_id, (str)); }) : (rb_intern)(str))
#define RBIMPL_VARIABLE_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RUBY_BACKWARD2_INTTYPES_H 
#define PRI_INT_PREFIX ""
#define PRI_LONG_PREFIX "l"
#define PRI_SHORT_PREFIX "h"
#define PRI_64_PREFIX PRI_LONG_PREFIX
#define RUBY_PRI_VALUE_MARK "\v"
#define PRIdVALUE PRI_VALUE_PREFIX"d"
#define PRIoVALUE PRI_VALUE_PREFIX"o"
#define PRIuVALUE PRI_VALUE_PREFIX"u"
#define PRIxVALUE PRI_VALUE_PREFIX"x"
#define PRIXVALUE PRI_VALUE_PREFIX"X"
#define PRIsVALUE PRI_VALUE_PREFIX"i" RUBY_PRI_VALUE_MARK
#define PRIdPTRDIFF PRI_PTRDIFF_PREFIX"d"
#define PRIiPTRDIFF PRI_PTRDIFF_PREFIX"i"
#define PRIoPTRDIFF PRI_PTRDIFF_PREFIX"o"
#define PRIuPTRDIFF PRI_PTRDIFF_PREFIX"u"
#define PRIxPTRDIFF PRI_PTRDIFF_PREFIX"x"
#define PRIXPTRDIFF PRI_PTRDIFF_PREFIX"X"
#define PRIdSIZE PRI_SIZE_PREFIX"d"
#define PRIiSIZE PRI_SIZE_PREFIX"i"
#define PRIoSIZE PRI_SIZE_PREFIX"o"
#define PRIuSIZE PRI_SIZE_PREFIX"u"
#define PRIxSIZE PRI_SIZE_PREFIX"x"
#define PRIXSIZE PRI_SIZE_PREFIX"X"
#pragma GCC visibility push(default)
#define USE_SYMBOL_AS_METHOD_NAME 1
#define FilePathValue(v) (RB_GC_GUARD(v) = rb_get_path(v))
#define FilePathStringValue(v) ((v) = rb_get_path(v))
#define rb_varargs_argc_check_runtime(argc,vargc) (((argc) <= (vargc)) ? (argc) : (rb_fatal("argc(%d) exceeds actual arguments(%d)", argc, vargc), 0))
#define rb_varargs_argc_valid_p(argc,vargc) ((argc) == 0 ? (vargc) <= 1 : (argc) == (vargc))
#define rb_varargs_argc_check(argc,vargc) __builtin_choose_expr(__builtin_constant_p(argc), (rb_varargs_argc_valid_p(argc, vargc) ? (argc) : rb_varargs_bad_length(argc, vargc)), rb_varargs_argc_check_runtime(argc, vargc))
#define RUBY_INTERN_H 1
#define RBIMPL_INTERN_BIGNUM_H 
#pragma GCC visibility push(default)
#define rb_big2int(x) rb_big2long(x)
#define rb_big2uint(x) rb_big2ulong(x)
#define INTEGER_PACK_MSWORD_FIRST 0x01
#define INTEGER_PACK_LSWORD_FIRST 0x02
#define INTEGER_PACK_MSBYTE_FIRST 0x10
#define INTEGER_PACK_LSBYTE_FIRST 0x20
#define INTEGER_PACK_NATIVE_BYTE_ORDER 0x40
#define INTEGER_PACK_2COMP 0x80
#define INTEGER_PACK_FORCE_GENERIC_IMPLEMENTATION 0x400
#define INTEGER_PACK_FORCE_BIGNUM 0x100
#define INTEGER_PACK_NEGATIVE 0x200
#define INTEGER_PACK_LITTLE_ENDIAN (INTEGER_PACK_LSWORD_FIRST | INTEGER_PACK_LSBYTE_FIRST)
#define INTEGER_PACK_BIG_ENDIAN (INTEGER_PACK_MSWORD_FIRST | INTEGER_PACK_MSBYTE_FIRST)
#pragma GCC visibility pop
#define RBIMPL_INTERN_COMPAR_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_INTERN_COMPLEX_H 
#pragma GCC visibility push(default)
#define rb_complex_raw1(x) rb_complex_raw((x), INT2FIX(0))
#define rb_complex_raw2(x,y) rb_complex_raw((x), (y))
#define rb_complex_new1(x) rb_complex_new((x), INT2FIX(0))
#define rb_complex_new2(x,y) rb_complex_new((x), (y))
#define rb_complex_add rb_complex_plus
#define rb_complex_sub rb_complex_minus
#define rb_complex_nagate rb_complex_uminus
#define rb_Complex1(x) rb_Complex((x), INT2FIX(0))
#define rb_Complex2(x,y) rb_Complex((x), (y))
#pragma GCC visibility pop
#define RBIMPL_INTERN_CONT_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_INTERN_DIR_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_INTERN_ENUM_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_INTERN_ENUMERATOR_H 
#define RBIMPL_INTERN_EVAL_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define SIZED_ENUMERATOR(obj,argc,argv,size_fn) rb_enumeratorize_with_size((obj), ID2SYM(rb_frame_this_func()), (argc), (argv), (size_fn))
#define SIZED_ENUMERATOR_KW(obj,argc,argv,size_fn,kw_splat) rb_enumeratorize_with_size_kw((obj), ID2SYM(rb_frame_this_func()), (argc), (argv), (size_fn), (kw_splat))
#define RETURN_SIZED_ENUMERATOR(obj,argc,argv,size_fn) do { if (!rb_block_given_p()) return SIZED_ENUMERATOR(obj, argc, argv, size_fn); } while (0)
#define RETURN_SIZED_ENUMERATOR_KW(obj,argc,argv,size_fn,kw_splat) do { if (!rb_block_given_p()) return SIZED_ENUMERATOR_KW(obj, argc, argv, size_fn, kw_splat); } while (0)
#define RETURN_ENUMERATOR(obj,argc,argv) RETURN_SIZED_ENUMERATOR(obj, argc, argv, 0)
#define RETURN_ENUMERATOR_KW(obj,argc,argv,kw_splat) RETURN_SIZED_ENUMERATOR_KW(obj, argc, argv, 0, kw_splat)
#define RBIMPL_INTERN_FILE_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_INTERN_GC_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_INTERN_IO_H 
#pragma GCC visibility push(default)
#define rb_defout rb_stdout
#define RB_RESERVED_FD_P(fd) rb_reserved_fd_p(fd)
#pragma GCC visibility pop
#define RBIMPL_INTERN_LOAD_H 
#pragma GCC visibility push(default)
#define RB_EXT_RACTOR_SAFE(f) rb_ext_ractor_safe(f)
#define HAVE_RB_EXT_RACTOR_SAFE 1
#pragma GCC visibility pop
#define RBIMPL_INTERN_MARSHAL_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_INTERN_NUMERIC_H 
#define RB_NUM_COERCE_FUNCS_NEED_OPID 1
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_INTERN_OBJECT_H 
#pragma GCC visibility push(default)
#define RB_OBJ_INIT_COPY(obj,orig) ((obj) != (orig) && (rb_obj_init_copy((obj), (orig)), 1))
#define OBJ_INIT_COPY(obj,orig) RB_OBJ_INIT_COPY(obj, orig)
#pragma GCC visibility pop
#define RBIMPL_INTERN_PARSE_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_INTERN_PROCESS_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_INTERN_RANDOM_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_INTERN_RANGE_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_INTERN_RATIONAL_H 
#pragma GCC visibility push(default)
#define rb_rational_raw1(x) rb_rational_raw((x), INT2FIX(1))
#define rb_rational_raw2(x,y) rb_rational_raw((x), (y))
#define rb_rational_new1(x) rb_rational_new((x), INT2FIX(1))
#define rb_rational_new2(x,y) rb_rational_new((x), (y))
#define rb_Rational1(x) rb_Rational((x), INT2FIX(1))
#define rb_Rational2(x,y) rb_Rational((x), (y))
#pragma GCC visibility pop
#define RBIMPL_INTERN_RE_H 
#pragma GCC visibility push(default)
#define rb_memcmp memcmp
#define HAVE_RB_REG_NEW_STR 1
#pragma GCC visibility pop
#define RBIMPL_INTERN_RUBY_H 
#pragma GCC visibility push(default)
#define rb_argv rb_get_argv()
#pragma GCC visibility pop
#define RBIMPL_INTERN_SELECT_H 
#define RBIMPL_INTERN_SELECT_LARGESIZE_H 
#define rb_fd_ptr rb_fd_ptr
#define rb_fd_max rb_fd_max
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_INTERN_SIGNAL_H 
#pragma GCC visibility push(default)
#define posix_signal ruby_posix_signal
#pragma GCC visibility pop
#define RBIMPL_INTERN_SPRINTF_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_INTERN_STRING_H 
#pragma GCC visibility push(default)
#define rb_str_dup_frozen rb_str_new_frozen
#define rb_hash_uint32(h,i) st_hash_uint32((h), (i))
#define rb_hash_uint(h,i) st_hash_uint((h), (i))
#define rb_hash_end(h) st_hash_end(h)
#define rb_str_new(str,len) ((RBIMPL_CONSTANT_P(str) && RBIMPL_CONSTANT_P(len) ? rb_str_new_static : rb_str_new) ((str), (len)))
#define rb_str_new_cstr(str) ((RBIMPL_CONSTANT_P(str) ? rbimpl_str_new_cstr : rb_str_new_cstr) (str))
#define rb_usascii_str_new(str,len) ((RBIMPL_CONSTANT_P(str) && RBIMPL_CONSTANT_P(len) ? rb_usascii_str_new_static : rb_usascii_str_new) ((str), (len)))
#define rb_utf8_str_new(str,len) ((RBIMPL_CONSTANT_P(str) && RBIMPL_CONSTANT_P(len) ? rb_utf8_str_new_static : rb_utf8_str_new) ((str), (len)))
#define rb_tainted_str_new_cstr(str) ((RBIMPL_CONSTANT_P(str) ? rbimpl_tainted_str_new_cstr : rb_tainted_str_new_cstr) (str))
#define rb_usascii_str_new_cstr(str) ((RBIMPL_CONSTANT_P(str) ? rbimpl_usascii_str_new_cstr : rb_usascii_str_new_cstr) (str))
#define rb_utf8_str_new_cstr(str) ((RBIMPL_CONSTANT_P(str) ? rbimpl_utf8_str_new_cstr : rb_utf8_str_new_cstr) (str))
#define rb_external_str_new_cstr(str) ((RBIMPL_CONSTANT_P(str) ? rbimpl_external_str_new_cstr : rb_external_str_new_cstr) (str))
#define rb_locale_str_new_cstr(str) ((RBIMPL_CONSTANT_P(str) ? rbimpl_locale_str_new_cstr : rb_locale_str_new_cstr) (str))
#define rb_str_buf_new_cstr(str) ((RBIMPL_CONSTANT_P(str) ? rbimpl_str_buf_new_cstr : rb_str_buf_new_cstr) (str))
#define rb_str_cat_cstr(buf,str) ((RBIMPL_CONSTANT_P(str) ? rbimpl_str_cat_cstr : rb_str_cat_cstr) ((buf), (str)))
#define rb_exc_new_cstr(exc,str) ((RBIMPL_CONSTANT_P(str) ? rbimpl_exc_new_cstr : rb_exc_new_cstr) ((exc), (str)))
#define rb_str_new2 rb_str_new_cstr
#define rb_str_new3 rb_str_new_shared
#define rb_str_new4 rb_str_new_frozen
#define rb_str_new5 rb_str_new_with_class
#define rb_tainted_str_new2 rb_tainted_str_new_cstr
#define rb_str_buf_new2 rb_str_buf_new_cstr
#define rb_usascii_str_new2 rb_usascii_str_new_cstr
#define rb_str_buf_cat rb_str_cat
#define rb_str_buf_cat2 rb_str_cat_cstr
#define rb_str_cat2 rb_str_cat_cstr
#define rb_strlen_lit(str) (sizeof(str "") - 1)
#define rb_str_new_lit(str) rb_str_new_static((str), rb_strlen_lit(str))
#define rb_usascii_str_new_lit(str) rb_usascii_str_new_static((str), rb_strlen_lit(str))
#define rb_utf8_str_new_lit(str) rb_utf8_str_new_static((str), rb_strlen_lit(str))
#define rb_enc_str_new_lit(str,enc) rb_enc_str_new_static((str), rb_strlen_lit(str), (enc))
#define rb_str_new_literal(str) rb_str_new_lit(str)
#define rb_usascii_str_new_literal(str) rb_usascii_str_new_lit(str)
#define rb_utf8_str_new_literal(str) rb_utf8_str_new_lit(str)
#define rb_enc_str_new_literal(str,enc) rb_enc_str_new_lit(str, enc)
#pragma GCC visibility pop
#define RBIMPL_INTERN_STRUCT_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_INTERN_THREAD_H 
#pragma GCC visibility push(default)
#define RUBY_UBF_IO RBIMPL_CAST((rb_unblock_function_t *)-1)
#define RUBY_UBF_PROCESS RBIMPL_CAST((rb_unblock_function_t *)-1)
#pragma GCC visibility pop
#define RBIMPL_INTERN_TIME_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RBIMPL_INTERN_VARIABLE_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RUBY_VM 1
#define HAVE_NATIVETHREAD 
#define InitVM(ext) {void InitVM_ ##ext(void);InitVM_ ##ext();}
#define RUBY_SUBST_H 1
#undef snprintf
#undef vsnprintf
#define snprintf ruby_snprintf
#define vsnprintf ruby_vsnprintf
#pragma GCC visibility pop
#define RUBY_VM_CORE_H 
#define N_OR_RUBY_DEBUG(n) (((n) > 0) ? (n) : RUBY_DEBUG)
#define VM_CHECK_MODE N_OR_RUBY_DEBUG(0)
#define VMDEBUG 0
#define _SIGNAL_H 
#define _SIGSET_H_fns 1
#define _EXTERN_INLINE __extern_inline
#define __sigmask(sig) (((unsigned long int) 1) << (((sig) - 1) % (8 * sizeof (unsigned long int))))
#define __sigword(sig) (((sig) - 1) / (8 * sizeof (unsigned long int)))
#define __sigemptyset(set) (__extension__ ({ int __cnt = _SIGSET_NWORDS; sigset_t *__set = (set); while (--__cnt >= 0) __set->__val[__cnt] = 0; 0; }))
#define __sigfillset(set) (__extension__ ({ int __cnt = _SIGSET_NWORDS; sigset_t *__set = (set); while (--__cnt >= 0) __set->__val[__cnt] = ~0UL; 0; }))
#define __sigisemptyset(set) (__extension__ ({ int __cnt = _SIGSET_NWORDS; const sigset_t *__set = (set); int __ret = __set->__val[--__cnt]; while (!__ret && --__cnt >= 0) __ret = __set->__val[__cnt]; __ret == 0; }))
#define __sigandset(dest,left,right) (__extension__ ({ int __cnt = _SIGSET_NWORDS; sigset_t *__dest = (dest); const sigset_t *__left = (left); const sigset_t *__right = (right); while (--__cnt >= 0) __dest->__val[__cnt] = (__left->__val[__cnt] & __right->__val[__cnt]); 0; }))
#define __sigorset(dest,left,right) (__extension__ ({ int __cnt = _SIGSET_NWORDS; sigset_t *__dest = (dest); const sigset_t *__left = (left); const sigset_t *__right = (right); while (--__cnt >= 0) __dest->__val[__cnt] = (__left->__val[__cnt] | __right->__val[__cnt]); 0; }))
#define __sig_atomic_t_defined 
#undef __need_sig_atomic_t
#undef __need_sigset_t
#define SIG_ERR ((__sighandler_t) -1)
#define SIG_DFL ((__sighandler_t) 0)
#define SIG_IGN ((__sighandler_t) 1)
#define SIG_HOLD ((__sighandler_t) 2)
#define SIGHUP 1
#define SIGINT 2
#define SIGQUIT 3
#define SIGILL 4
#define SIGTRAP 5
#define SIGABRT 6
#define SIGIOT 6
#define SIGBUS 7
#define SIGFPE 8
#define SIGKILL 9
#define SIGUSR1 10
#define SIGSEGV 11
#define SIGUSR2 12
#define SIGPIPE 13
#define SIGALRM 14
#define SIGTERM 15
#define SIGSTKFLT 16
#define SIGCLD SIGCHLD
#define SIGCHLD 17
#define SIGCONT 18
#define SIGSTOP 19
#define SIGTSTP 20
#define SIGTTIN 21
#define SIGTTOU 22
#define SIGURG 23
#define SIGXCPU 24
#define SIGXFSZ 25
#define SIGVTALRM 26
#define SIGPROF 27
#define SIGWINCH 28
#define SIGPOLL SIGIO
#define SIGIO 29
#define SIGPWR 30
#define SIGSYS 31
#define SIGUNUSED 31
#define _NSIG 65
#define SIGRTMIN (__libc_current_sigrtmin ())
#define SIGRTMAX (__libc_current_sigrtmax ())
#define __SIGRTMIN 32
#define __SIGRTMAX (_NSIG - 1)
#define __need_timespec 
#define __WORDSIZE 64
#define __WORDSIZE_COMPAT32 1
#define __have_sigval_t 1
#define __have_siginfo_t 1
#define __SI_MAX_SIZE 128
#define __SI_PAD_SIZE ((__SI_MAX_SIZE / sizeof (int)) - 4)
#define si_pid _sifields._kill.si_pid
#define si_uid _sifields._kill.si_uid
#define si_timerid _sifields._timer.si_tid
#define si_overrun _sifields._timer.si_overrun
#define si_status _sifields._sigchld.si_status
#define si_utime _sifields._sigchld.si_utime
#define si_stime _sifields._sigchld.si_stime
#define si_value _sifields._rt.si_sigval
#define si_int _sifields._rt.si_sigval.sival_int
#define si_ptr _sifields._rt.si_sigval.sival_ptr
#define si_addr _sifields._sigfault.si_addr
#define si_band _sifields._sigpoll.si_band
#define si_fd _sifields._sigpoll.si_fd
#define SI_ASYNCNL SI_ASYNCNL
#define SI_TKILL SI_TKILL
#define SI_SIGIO SI_SIGIO
#define SI_ASYNCIO SI_ASYNCIO
#define SI_MESGQ SI_MESGQ
#define SI_TIMER SI_TIMER
#define SI_QUEUE SI_QUEUE
#define SI_USER SI_USER
#define SI_KERNEL SI_KERNEL
#define ILL_ILLOPC ILL_ILLOPC
#define ILL_ILLOPN ILL_ILLOPN
#define ILL_ILLADR ILL_ILLADR
#define ILL_ILLTRP ILL_ILLTRP
#define ILL_PRVOPC ILL_PRVOPC
#define ILL_PRVREG ILL_PRVREG
#define ILL_COPROC ILL_COPROC
#define ILL_BADSTK ILL_BADSTK
#define FPE_INTDIV FPE_INTDIV
#define FPE_INTOVF FPE_INTOVF
#define FPE_FLTDIV FPE_FLTDIV
#define FPE_FLTOVF FPE_FLTOVF
#define FPE_FLTUND FPE_FLTUND
#define FPE_FLTRES FPE_FLTRES
#define FPE_FLTINV FPE_FLTINV
#define FPE_FLTSUB FPE_FLTSUB
#define SEGV_MAPERR SEGV_MAPERR
#define SEGV_ACCERR SEGV_ACCERR
#define BUS_ADRALN BUS_ADRALN
#define BUS_ADRERR BUS_ADRERR
#define BUS_OBJERR BUS_OBJERR
#define TRAP_BRKPT TRAP_BRKPT
#define TRAP_TRACE TRAP_TRACE
#define CLD_EXITED CLD_EXITED
#define CLD_KILLED CLD_KILLED
#define CLD_DUMPED CLD_DUMPED
#define CLD_TRAPPED CLD_TRAPPED
#define CLD_STOPPED CLD_STOPPED
#define CLD_CONTINUED CLD_CONTINUED
#define POLL_IN POLL_IN
#define POLL_OUT POLL_OUT
#define POLL_MSG POLL_MSG
#define POLL_ERR POLL_ERR
#define POLL_PRI POLL_PRI
#define POLL_HUP POLL_HUP
#undef __need_siginfo_t
#define __have_sigevent_t 1
#define __SIGEV_MAX_SIZE 64
#define __SIGEV_PAD_SIZE ((__SIGEV_MAX_SIZE / sizeof (int)) - 4)
#define sigev_notify_function _sigev_un._sigev_thread._function
#define sigev_notify_attributes _sigev_un._sigev_thread._attribute
#define SIGEV_SIGNAL SIGEV_SIGNAL
#define SIGEV_NONE SIGEV_NONE
#define SIGEV_THREAD SIGEV_THREAD
#define SIGEV_THREAD_ID SIGEV_THREAD_ID
#define sigmask(sig) __sigmask(sig)
#define NSIG _NSIG
#define sa_handler __sigaction_handler.sa_handler
#define sa_sigaction __sigaction_handler.sa_sigaction
#define SA_NOCLDSTOP 1
#define SA_NOCLDWAIT 2
#define SA_SIGINFO 4
#define SA_ONSTACK 0x08000000
#define SA_RESTART 0x10000000
#define SA_NODEFER 0x40000000
#define SA_RESETHAND 0x80000000
#define SA_INTERRUPT 0x20000000
#define SA_NOMASK SA_NODEFER
#define SA_ONESHOT SA_RESETHAND
#define SA_STACK SA_ONSTACK
#define SIG_BLOCK 0
#define SIG_UNBLOCK 1
#define SIG_SETMASK 2
#define sv_onstack sv_flags
#define SV_ONSTACK (1 << 0)
#define SV_INTERRUPT (1 << 1)
#define SV_RESETHAND (1 << 2)
#define _BITS_SIGCONTEXT_H 1
#define __WORDSIZE 64
#define __WORDSIZE_COMPAT32 1
#define __need_size_t 
#undef __need_ptrdiff_t
#undef __need_size_t
#undef __need_wchar_t
#undef NULL
#define NULL ((void *)0)
#undef __need_NULL
#define offsetof(TYPE,MEMBER) __builtin_offsetof (TYPE, MEMBER)
#define SS_ONSTACK SS_ONSTACK
#define SS_DISABLE SS_DISABLE
#define MINSIGSTKSZ 2048
#define SIGSTKSZ 8192
#define _SYS_UCONTEXT_H 1
#define __WORDSIZE 64
#define __WORDSIZE_COMPAT32 1
#define NGREG 23
#define REG_R8 REG_R8
#define REG_R9 REG_R9
#define REG_R10 REG_R10
#define REG_R11 REG_R11
#define REG_R12 REG_R12
#define REG_R13 REG_R13
#define REG_R14 REG_R14
#define REG_R15 REG_R15
#define REG_RDI REG_RDI
#define REG_RSI REG_RSI
#define REG_RBP REG_RBP
#define REG_RBX REG_RBX
#define REG_RDX REG_RDX
#define REG_RAX REG_RAX
#define REG_RCX REG_RCX
#define REG_RSP REG_RSP
#define REG_RIP REG_RIP
#define REG_EFL REG_EFL
#define REG_CSGSFS REG_CSGSFS
#define REG_ERR REG_ERR
#define REG_TRAPNO REG_TRAPNO
#define REG_OLDMASK REG_OLDMASK
#define REG_CR2 REG_CR2
#define _BITS_SIGTHREAD_H 1
#define RUBY_TOPLEVEL_ASSERT_H 
#undef assert
#define assert RUBY_ASSERT_NDEBUG
#define VM_ASSERT(expr) ((void)0)
#define VM_UNREACHABLE(func) UNREACHABLE
#define _SETJMP_H 1
#define _BITS_SETJMP_H 1
#define __WORDSIZE 64
#define __WORDSIZE_COMPAT32 1
#define setjmp(env) _setjmp (env)
#define sigsetjmp(env,savemask) __sigsetjmp (env, savemask)
#define CCAN_LIST_H 
#undef _ASSERT_H
#undef assert
#undef __ASSERT_VOID_CAST
#undef assert_perror
#define _ASSERT_H 1
#define __ASSERT_VOID_CAST (void)
#define assert(expr) (__ASSERT_VOID_CAST (0))
#define assert_perror(errnum) (__ASSERT_VOID_CAST (0))
#define CCAN_STR_H 
#define stringify(expr) stringify_1(expr)
#define stringify_1(expr) #expr
#define CCAN_CONTAINER_OF_H 
#define CCAN_CHECK_TYPE_H 
#define check_type(expr,type) ((typeof(expr) *)0 != (type *)0)
#define check_types_match(expr1,expr2) ((typeof(expr1) *)0 != (typeof(expr2) *)0)
#define container_of(member_ptr,containing_type,member) ((containing_type *) ((char *)(member_ptr) - container_off(containing_type, member)) + check_types_match(*(member_ptr), ((containing_type *)0)->member))
#define container_of_or_null(member_ptr,containing_type,member) ((containing_type *) container_of_or_null_(member_ptr, container_off(containing_type, member)) + check_types_match(*(member_ptr), ((containing_type *)0)->member))
#define container_off(containing_type,member) offsetof(containing_type, member)
#define container_of_var(member_ptr,container_var,member) container_of(member_ptr, typeof(*container_var), member)
#define container_off_var(var,member) container_off(typeof(*var), member)
#define LIST_LOC __FILE__ ":" stringify(__LINE__)
#define list_debug(h,loc) ((void)loc, h)
#define list_debug_node(n,loc) ((void)loc, n)
#define LIST_HEAD_INIT(name) { { &(name).n, &(name).n } }
#define LIST_HEAD(name) struct list_head name = LIST_HEAD_INIT(name)
#define list_add_after(h,p,n) list_add_after_(h, p, n, LIST_LOC)
#define list_add(h,n) list_add_(h, n, LIST_LOC)
#define list_add_before(h,p,n) list_add_before_(h, p, n, LIST_LOC)
#define list_add_tail(h,n) list_add_tail_(h, n, LIST_LOC)
#define list_empty(h) list_empty_(h, LIST_LOC)
#define list_empty_nodebug(h) list_empty(h)
#define list_del(n) list_del_(n, LIST_LOC)
#define list_del_init(n) list_del_init_(n, LIST_LOC)
#define list_swap(o,n) list_swap_(o, n, LIST_LOC)
#define list_entry(n,type,member) container_of(n, type, member)
#define list_top(h,type,member) ((type *)list_top_((h), list_off_(type, member)))
#define list_pop(h,type,member) ((type *)list_pop_((h), list_off_(type, member)))
#define list_tail(h,type,member) ((type *)list_tail_((h), list_off_(type, member)))
#define list_for_each(h,i,member) list_for_each_off(h, i, list_off_var_(i, member))
#define list_for_each_rev(h,i,member) list_for_each_rev_off(h, i, list_off_var_(i, member))
#define list_for_each_rev_safe(h,i,nxt,member) list_for_each_rev_safe_off(h, i, nxt, list_off_var_(i, member))
#define list_for_each_safe(h,i,nxt,member) list_for_each_safe_off(h, i, nxt, list_off_var_(i, member))
#define list_next(h,i,member) ((list_typeof(i))list_entry_or_null(list_debug(h, __FILE__ ":" stringify(__LINE__)), (i)->member.next, list_off_var_((i), member)))
#define list_prev(h,i,member) ((list_typeof(i))list_entry_or_null(list_debug(h, __FILE__ ":" stringify(__LINE__)), (i)->member.prev, list_off_var_((i), member)))
#define list_append_list(t,f) list_append_list_(t, f, __FILE__ ":" stringify(__LINE__))
#define list_prepend_list(t,f) list_prepend_list_(t, f, LIST_LOC)
#define list_for_each_off_dir_(h,i,off,dir) for (i = list_node_to_off_(list_debug(h, LIST_LOC)->n.dir, (off)); list_node_from_off_((void *)i, (off)) != &(h)->n; i = list_node_to_off_(list_node_from_off_((void *)i, (off))->dir, (off)))
#define list_for_each_safe_off_dir_(h,i,nxt,off,dir) for (i = list_node_to_off_(list_debug(h, LIST_LOC)->n.dir, (off)), nxt = list_node_to_off_(list_node_from_off_(i, (off))->dir, (off)); list_node_from_off_(i, (off)) != &(h)->n; i = nxt, nxt = list_node_to_off_(list_node_from_off_(i, (off))->dir, (off)))
#define list_for_each_off(h,i,off) list_for_each_off_dir_((h),(i),(off),next)
#define list_for_each_rev_off(h,i,off) list_for_each_off_dir_((h),(i),(off),prev)
#define list_for_each_safe_off(h,i,nxt,off) list_for_each_safe_off_dir_((h),(i),(nxt),(off),next)
#define list_for_each_rev_safe_off(h,i,nxt,off) list_for_each_safe_off_dir_((h),(i),(nxt),(off),prev)
#define list_entry_off(n,type,off) ((type *)list_node_from_off_((n), (off)))
#define list_head_off(h,type,off) ((type *)list_head_off((h), (off)))
#define list_tail_off(h,type,off) ((type *)list_tail_((h), (off)))
#define list_add_off(h,n,off) list_add((h), list_node_from_off_((n), (off)))
#define list_del_off(n,off) list_del(list_node_from_off_((n), (off)))
#define list_del_from_off(h,n,off) list_del_from(h, list_node_from_off_((n), (off)))
#define list_off_(type,member) (container_off(type, member) + check_type(((type *)0)->member, struct list_node))
#define list_off_var_(var,member) (container_off_var(var, member) + check_type(var->member, struct list_node))
#define list_typeof(var) typeof(var)
#define RUBY_ID_H 
#define ID_STATIC_SYM RUBY_ID_STATIC_SYM
#define ID_SCOPE_SHIFT RUBY_ID_SCOPE_SHIFT
#define ID_SCOPE_MASK RUBY_ID_SCOPE_MASK
#define ID_LOCAL RUBY_ID_LOCAL
#define ID_INSTANCE RUBY_ID_INSTANCE
#define ID_GLOBAL RUBY_ID_GLOBAL
#define ID_ATTRSET RUBY_ID_ATTRSET
#define ID_CONST RUBY_ID_CONST
#define ID_CLASS RUBY_ID_CLASS
#define ID_JUNK RUBY_ID_JUNK
#define ID_INTERNAL RUBY_ID_INTERNAL
#define symIFUNC ID2SYM(idIFUNC)
#define symCFUNC ID2SYM(idCFUNC)
#define RUBY_TOKEN_DOT2 128
#define RUBY_TOKEN_DOT3 129
#define RUBY_TOKEN_BDOT2 130
#define RUBY_TOKEN_BDOT3 131
#define RUBY_TOKEN_UPLUS 132
#define RUBY_TOKEN_UMINUS 133
#define RUBY_TOKEN_POW 134
#define RUBY_TOKEN_CMP 135
#define RUBY_TOKEN_LSHFT 136
#define RUBY_TOKEN_RSHFT 137
#define RUBY_TOKEN_LEQ 138
#define RUBY_TOKEN_GEQ 139
#define RUBY_TOKEN_EQ 140
#define RUBY_TOKEN_EQQ 141
#define RUBY_TOKEN_NEQ 142
#define RUBY_TOKEN_MATCH 143
#define RUBY_TOKEN_NMATCH 144
#define RUBY_TOKEN_AREF 145
#define RUBY_TOKEN_ASET 146
#define RUBY_TOKEN_COLON2 147
#define RUBY_TOKEN_ANDOP 148
#define RUBY_TOKEN_OROP 149
#define RUBY_TOKEN_ANDDOT 150
#define RUBY_TOKEN(t) RUBY_TOKEN_ ##t
#define RUBY_TOKEN2ID_TYPE(tok,type) ((tok<<RUBY_ID_SCOPE_SHIFT)|type|RUBY_ID_STATIC_SYM)
#define TOKEN2LOCALID(tok) RUBY_TOKEN2ID_TYPE(tok, RUBY_ID_LOCAL)
#define TOKEN2INSTANCEID(tok) RUBY_TOKEN2ID_TYPE(tok, RUBY_ID_INSTANCE)
#define TOKEN2GLOBALID(tok) RUBY_TOKEN2ID_TYPE(tok, RUBY_ID_GLOBAL)
#define TOKEN2CONSTID(tok) RUBY_TOKEN2ID_TYPE(tok, RUBY_ID_CONST)
#define TOKEN2CLASSID(tok) RUBY_TOKEN2ID_TYPE(tok, RUBY_ID_CLASS)
#define TOKEN2ATTRSETID(tok) RUBY_TOKEN2ID_TYPE(tok, RUBY_ID_ATTRSET)
#define DEFINE_LOCALID_FROM_TOKEN(n) id ##n = TOKEN2LOCALID(t ##n)
#define DEFINE_INSTANCEID_FROM_TOKEN(n) id ##n = TOKEN2INSTANCEID(t ##n)
#define DEFINE_GLOBALID_FROM_TOKEN(n) id ##n = TOKEN2GLOBALID(t ##n)
#define DEFINE_CONSTID_FROM_TOKEN(n) id ##n = TOKEN2CONSTID(t ##n)
#define DEFINE_CLASSID_FROM_TOKEN(n) id ##n = TOKEN2CLASSID(t ##n)
#define DEFINE_ATTRSETID_FROM_TOKEN(n) id ##n = TOKEN2ATTRSETID(t ##n)
#define RUBY_INTERNAL_H 1
#define LIKELY(x) RB_LIKELY(x)
#define UNLIKELY(x) RB_UNLIKELY(x)
#define numberof(array) ((int)(sizeof(array) / sizeof((array)[0])))
#define roomof(x,y) (((x) + (y) - 1) / (y))
#define type_roomof(x,y) roomof(sizeof(x), sizeof(y))
#define ACCESS_ONCE(type,x) (*((volatile type *)&(x)))
#undef RARRAY_AREF
#undef RClass
#undef RCLASS_SUPER
#undef NEWOBJ_OF
#undef RB_NEWOBJ_OF
#undef RB_OBJ_WRITE
#undef RHASH_IFNONE
#undef RHASH_SIZE
#undef RHASH_TBL
#undef RHASH_EMPTY_P
#undef ROBJECT_IV_INDEX_TBL
#undef RSTRUCT_LEN
#undef RSTRUCT_PTR
#undef RSTRUCT_SET
#undef RSTRUCT_GET
#define rb_ary_new_from_args(...) rb_nonexistent_symbol(__VA_ARGS__)
#define rb_io_fptr_finalize(...) rb_nonexistent_symbol(__VA_ARGS__)
#define rb_fstring_cstr(...) rb_nonexistent_symbol(__VA_ARGS__)
#define rb_sym_intern_ascii_cstr(...) rb_nonexistent_symbol(__VA_ARGS__)
#define rb_funcallv(...) rb_nonexistent_symbol(__VA_ARGS__)
#define rb_method_basic_definition_p(...) rb_nonexistent_symbol(__VA_ARGS__)
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define rp(obj) rb_obj_info_dump_loc((VALUE)(obj), __FILE__, __LINE__, RUBY_FUNCTION_NAME_STRING)
#define rp_m(msg,obj) do { fputs((msg), stderr); rb_obj_info_dump((VALUE)(obj)); } while (0)
#define bp() ruby_debug_breakpoint()
#define RBOOL(v) ((v) ? Qtrue : Qfalse)
#define RB_BIGNUM_TYPE_P(x) RB_TYPE_P((x), T_BIGNUM)
#define INTERNAL_ARRAY_H 
#define INTERNAL_STATIC_ASSERT_H 
#define STATIC_ASSERT RBIMPL_STATIC_ASSERT
#define ARRAY_DEBUG (0+RUBY_DEBUG)
#define RARRAY_PTR_IN_USE_FLAG FL_USER14
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#undef rb_ary_new_from_args
#define rb_ary_new_from_args(n,...) __extension__ ({ const VALUE args_to_new_ary[] = {__VA_ARGS__}; if (__builtin_constant_p(n)) { STATIC_ASSERT(rb_ary_new_from_args, numberof(args_to_new_ary) == (n)); } rb_ary_new_from_values(numberof(args_to_new_ary), args_to_new_ary); })
#undef RARRAY_AREF
#define INTERNAL_SERIAL_H 
#define SERIALT2NUM ULL2NUM
#define PRI_SERIALT_PREFIX PRI_LL_PREFIX
#define SIZEOF_SERIAL_T SIZEOF_LONG_LONG
#define INTERNAL_VM_H 
#undef rb_funcallv
#undef rb_method_basic_definition_p
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RUBY_DTRACE_CREATE_HOOK(name,arg) RUBY_DTRACE_HOOK(name ##_CREATE, arg)
#define RUBY_DTRACE_HOOK(name,arg) do { if (UNLIKELY(RUBY_DTRACE_ ##name ##_ENABLED())) { int dtrace_line; const char *dtrace_file = rb_source_location_cstr(&dtrace_line); if (!dtrace_file) dtrace_file = ""; RUBY_DTRACE_ ##name(arg, dtrace_file, dtrace_line); } } while (0)
#define RUBY_METHOD_H 1
#define INTERNAL_IMEMO_H 
#define INTERNAL_GC_H 
#define INTERNAL_COMPILERS_H 
#define RUBY_BACKWARD2_GCC_VERSION_SINCE_H 
#define GCC_VERSION_SINCE(x,y,z) RBIMPL_COMPILER_SINCE(GCC, (x), (y), (z))
#define GCC_VERSION_BEFORE(x,y,z) (RBIMPL_COMPILER_BEFORE(GCC, (x), (y), (z)) || (RBIMPL_COMPILER_IS(GCC) && ((RBIMPL_COMPILER_VERSION_MAJOR == (x)) && ((RBIMPL_COMPILER_VERSION_MINOR == (y)) && (RBIMPL_COMPILER_VERSION_PATCH == (z))))))
#define MSC_VERSION_SINCE(_) RBIMPL_COMPILER_SINCE(MSVC, (_) / 100, (_) % 100, 0)
#define MSC_VERSION_BEFORE(_) RBIMPL_COMPILER_BEFORE(MSVC, (_) / 100, (_) % 100, 0)
#define __has_declspec_attribute(...) RBIMPL_HAS_DECLSPEC_ATTRIBUTE(__VA_ARGS__)
#define __has_feature(...) RBIMPL_HAS_FEATURE(__VA_ARGS__)
#define __has_extension(...) RBIMPL_HAS_EXTENSION(__VA_ARGS__)
#define __has_warning(...) RBIMPL_HAS_WARNING(__VA_ARGS__)
#define RB_OBJ_BUILTIN_TYPE(obj) rb_obj_builtin_type(obj)
#define OBJ_BUILTIN_TYPE(obj) RB_OBJ_BUILTIN_TYPE(obj)
#define rb_obj_builtin_type(obj) __extension__({ VALUE arg_obj = (obj); RB_SPECIAL_CONST_P(arg_obj) ? -1 : (int)RB_BUILTIN_TYPE(arg_obj); })
#define FLEX_ARY_LEN 
#define BITFIELD(type,name,size) type name : size
#define RVALUE_SIZE (sizeof(struct RBasic) + sizeof(VALUE[RBIMPL_RVALUE_EMBED_LEN_MAX]))
#define RB_RVARGC_NEWOBJ_OF(var,T,c,f,s) T *(var) = (T *)(((f) & FL_WB_PROTECTED) ? rb_wb_protected_newobj_of((c), (f) & ~FL_WB_PROTECTED, s) : rb_wb_unprotected_newobj_of((c), (f), s))
#define RB_RVARGC_EC_NEWOBJ_OF(ec,var,T,c,f,s) T *(var) = (T *)(((f) & FL_WB_PROTECTED) ? rb_ec_wb_protected_newobj_of((ec), (c), (f) & ~FL_WB_PROTECTED, s) : rb_wb_unprotected_newobj_of((c), (f), s))
#define RB_NEWOBJ_OF(var,T,c,f) RB_RVARGC_NEWOBJ_OF(var, T, c, f, RVALUE_SIZE)
#define RB_EC_NEWOBJ_OF(ec,var,T,c,f) RB_RVARGC_EC_NEWOBJ_OF(ec, var, T, c, f, RVALUE_SIZE)
#define NEWOBJ_OF(var,T,c,f) RB_NEWOBJ_OF((var), T, (c), (f))
#define RVARGC_NEWOBJ_OF(var,T,c,f,s) RB_RVARGC_NEWOBJ_OF((var), T, (c), (f), (s))
#define RB_OBJ_GC_FLAGS_MAX 6
#define INTERNAL_WARNINGS_H 
#define COMPILER_WARNING_PUSH RBIMPL_WARNING_PUSH()
#define COMPILER_WARNING_POP RBIMPL_WARNING_POP()
#define COMPILER_WARNING_ERROR(flag) RBIMPL_WARNING_ERROR(flag)
#define COMPILER_WARNING_IGNORED(flag) RBIMPL_WARNING_IGNORED(flag)
#define UNALIGNED_MEMBER_ACCESS(expr) __extension__({ COMPILER_WARNING_PUSH; COMPILER_WARNING_IGNORED(-Waddress-of-packed-member); __typeof__(expr) unaligned_member_access_result = (expr); COMPILER_WARNING_POP; unaligned_member_access_result; })
#define UNALIGNED_MEMBER_PTR(ptr,mem) UNALIGNED_MEMBER_ACCESS(&(ptr)->mem)
#define RB_OBJ_WRITE(a,slot,b) rb_obj_write((VALUE)(a), UNALIGNED_MEMBER_ACCESS((VALUE *)(slot)), (VALUE)(b), __FILE__, __LINE__)
#define SIZE_POOL_COUNT 1
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define SIZED_REALLOC_N(x,y,z,w) REALLOC_N(x, y, z)
#define ruby_sized_xrealloc ruby_sized_xrealloc_inlined
#define ruby_sized_xrealloc2 ruby_sized_xrealloc2_inlined
#define ruby_sized_xfree ruby_sized_xfree_inlined
#define IMEMO_DEBUG 0
#define IMEMO_MASK 0x0f
#define IMEMO_FL_USHIFT (FL_USHIFT + 4)
#define IMEMO_FL_USER0 FL_USER4
#define IMEMO_FL_USER1 FL_USER5
#define IMEMO_FL_USER2 FL_USER6
#define IMEMO_FL_USER3 FL_USER7
#define IMEMO_FL_USER4 FL_USER8
#define IMEMO_FL_USER5 FL_USER9
#define THROW_DATA_CONSUMED IMEMO_FL_USER0
#define THROW_DATA_P(err) imemo_throw_data_p((VALUE)err)
#define MEMO_CAST(m) ((struct MEMO *)(m))
#define MEMO_NEW(a,b,c) ((struct MEMO *)rb_imemo_new(imemo_memo, (VALUE)(a), (VALUE)(b), (VALUE)(c), 0))
#define MEMO_FOR(type,value) ((type *)RARRAY_PTR(value))
#define NEW_MEMO_FOR(type,value) ((value) = rb_ary_tmp_new_fill(type_roomof(type, VALUE)), MEMO_FOR(type, value))
#define NEW_PARTIAL_MEMO_FOR(type,value,member) ((value) = rb_ary_tmp_new_fill(type_roomof(type, VALUE)), rb_ary_set_len((value), offsetof(type, member) / sizeof(VALUE)), MEMO_FOR(type, value))
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define IMEMO_TYPE_P(v,t) imemo_type_p((VALUE)v, t)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#define END_OF_ENUMERATION(key) 
#define METHOD_ENTRY_VISI(me) (rb_method_visibility_t)(((me)->flags & (IMEMO_FL_USER0 | IMEMO_FL_USER1)) >> (IMEMO_FL_USHIFT+0))
#define METHOD_ENTRY_BASIC(me) (int) (((me)->flags & (IMEMO_FL_USER2 )) >> (IMEMO_FL_USHIFT+2))
#define METHOD_ENTRY_COMPLEMENTED(me) ((me)->flags & IMEMO_FL_USER3)
#define METHOD_ENTRY_COMPLEMENTED_SET(me) ((me)->flags |= IMEMO_FL_USER3)
#define METHOD_ENTRY_CACHED(me) ((me)->flags & IMEMO_FL_USER4)
#define METHOD_ENTRY_CACHED_SET(me) ((me)->flags |= IMEMO_FL_USER4)
#define METHOD_ENTRY_INVALIDATED(me) ((me)->flags & IMEMO_FL_USER5)
#define METHOD_ENTRY_INVALIDATED_SET(me) ((me)->flags |= IMEMO_FL_USER5)
#define METHOD_ENTRY_CACHEABLE(me) !(METHOD_ENTRY_VISI(me) == METHOD_VISI_PROTECTED)
#define VM_METHOD_TYPE_MINIMUM_BITS 4
#define rb_iseq_t rb_iseq_t
#define UNDEFINED_METHOD_ENTRY_P(me) (!(me) || !(me)->def || (me)->def->type == VM_METHOD_TYPE_UNDEF)
#define UNDEFINED_REFINED_METHOD_P(def) ((def)->type == VM_METHOD_TYPE_REFINED && UNDEFINED_METHOD_ENTRY_P((def)->body.refined.orig_me))
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RUBY_NODE_H 1
#define RNODE(obj) ((struct RNode *)(obj))
#define NODE_FL_NEWLINE (((VALUE)1)<<7)
#define NODE_TYPESHIFT 8
#define NODE_TYPEMASK (((VALUE)0x7f)<<NODE_TYPESHIFT)
#define nd_type(n) ((int) (((n)->flags & NODE_TYPEMASK)>>NODE_TYPESHIFT))
#define nd_set_type(n,t) rb_node_set_type(n, t)
#define nd_init_type(n,t) (n)->flags=(((n)->flags&~NODE_TYPEMASK)|((((unsigned long)(t))<<NODE_TYPESHIFT)&NODE_TYPEMASK))
#define NODE_LSHIFT (NODE_TYPESHIFT+7)
#define NODE_LMASK (((SIGNED_VALUE)1<<(sizeof(VALUE)*CHAR_BIT-NODE_LSHIFT))-1)
#define nd_line(n) (int)(((SIGNED_VALUE)(n)->flags)>>NODE_LSHIFT)
#define nd_set_line(n,l) (n)->flags=(((n)->flags&~((VALUE)(-1)<<NODE_LSHIFT))|((VALUE)((l)&NODE_LMASK)<<NODE_LSHIFT))
#define nd_first_column(n) ((int)((n)->nd_loc.beg_pos.column))
#define nd_set_first_column(n,v) ((n)->nd_loc.beg_pos.column = (v))
#define nd_first_lineno(n) ((int)((n)->nd_loc.beg_pos.lineno))
#define nd_set_first_lineno(n,v) ((n)->nd_loc.beg_pos.lineno = (v))
#define nd_first_loc(n) ((n)->nd_loc.beg_pos)
#define nd_set_first_loc(n,v) (nd_first_loc(n) = (v))
#define nd_last_column(n) ((int)((n)->nd_loc.end_pos.column))
#define nd_set_last_column(n,v) ((n)->nd_loc.end_pos.column = (v))
#define nd_last_lineno(n) ((int)((n)->nd_loc.end_pos.lineno))
#define nd_set_last_lineno(n,v) ((n)->nd_loc.end_pos.lineno = (v))
#define nd_last_loc(n) ((n)->nd_loc.end_pos)
#define nd_set_last_loc(n,v) (nd_last_loc(n) = (v))
#define nd_node_id(n) ((n)->node_id)
#define nd_set_node_id(n,id) ((n)->node_id = (id))
#define nd_head u1.node
#define nd_alen u2.argc
#define nd_next u3.node
#define nd_cond u1.node
#define nd_body u2.node
#define nd_else u3.node
#define nd_resq u2.node
#define nd_ensr u3.node
#define nd_1st u1.node
#define nd_2nd u2.node
#define nd_stts u1.node
#define nd_entry u3.id
#define nd_vid u1.id
#define nd_var u1.node
#define nd_iter u3.node
#define nd_value u2.node
#define nd_aid u3.id
#define nd_lit u1.value
#define nd_recv u1.node
#define nd_mid u2.id
#define nd_args u3.node
#define nd_ainfo u3.args
#define nd_defn u3.node
#define nd_cpath u1.node
#define nd_super u3.node
#define nd_beg u1.node
#define nd_end u2.node
#define nd_state u3.state
#define nd_nth u2.argc
#define nd_alias u1.id
#define nd_orig u2.id
#define nd_undef u2.node
#define nd_brace u2.argc
#define nd_pconst u1.node
#define nd_pkwargs u2.node
#define nd_pkwrestarg u3.node
#define nd_apinfo u3.apinfo
#define nd_fpinfo u3.fpinfo
#define nd_tbl u1.tbl
#define nd_pid u1.id
#define nd_plen u2.argc
#define nd_cflag u2.id
#define nd_cval u3.value
#define nd_rval u2.value
#define nd_tag u1.id
#define NEW_NODE(t,a0,a1,a2,loc) rb_node_newnode((t),(VALUE)(a0),(VALUE)(a1),(VALUE)(a2),loc)
#define NEW_NODE_WITH_LOCALS(t,a1,a2,loc) node_newnode_with_locals(p, (t),(VALUE)(a1),(VALUE)(a2),loc)
#define NEW_DEFN(i,a,d,loc) NEW_NODE(NODE_DEFN,0,i,NEW_SCOPE(a,d,loc),loc)
#define NEW_DEFS(r,i,a,d,loc) NEW_NODE(NODE_DEFS,r,i,NEW_SCOPE(a,d,loc),loc)
#define NEW_SCOPE(a,b,loc) NEW_NODE_WITH_LOCALS(NODE_SCOPE,b,a,loc)
#define NEW_BLOCK(a,loc) NEW_NODE(NODE_BLOCK,a,0,0,loc)
#define NEW_IF(c,t,e,loc) NEW_NODE(NODE_IF,c,t,e,loc)
#define NEW_UNLESS(c,t,e,loc) NEW_NODE(NODE_UNLESS,c,t,e,loc)
#define NEW_CASE(h,b,loc) NEW_NODE(NODE_CASE,h,b,0,loc)
#define NEW_CASE2(b,loc) NEW_NODE(NODE_CASE2,0,b,0,loc)
#define NEW_CASE3(h,b,loc) NEW_NODE(NODE_CASE3,h,b,0,loc)
#define NEW_WHEN(c,t,e,loc) NEW_NODE(NODE_WHEN,c,t,e,loc)
#define NEW_IN(c,t,e,loc) NEW_NODE(NODE_IN,c,t,e,loc)
#define NEW_WHILE(c,b,n,loc) NEW_NODE(NODE_WHILE,c,b,n,loc)
#define NEW_UNTIL(c,b,n,loc) NEW_NODE(NODE_UNTIL,c,b,n,loc)
#define NEW_FOR(i,b,loc) NEW_NODE(NODE_FOR,0,b,i,loc)
#define NEW_FOR_MASGN(v,loc) NEW_NODE(NODE_FOR_MASGN,v,0,0,loc)
#define NEW_ITER(a,b,loc) NEW_NODE(NODE_ITER,0,NEW_SCOPE(a,b,loc),0,loc)
#define NEW_LAMBDA(a,b,loc) NEW_NODE(NODE_LAMBDA,0,NEW_SCOPE(a,b,loc),0,loc)
#define NEW_BREAK(s,loc) NEW_NODE(NODE_BREAK,s,0,0,loc)
#define NEW_NEXT(s,loc) NEW_NODE(NODE_NEXT,s,0,0,loc)
#define NEW_REDO(loc) NEW_NODE(NODE_REDO,0,0,0,loc)
#define NEW_RETRY(loc) NEW_NODE(NODE_RETRY,0,0,0,loc)
#define NEW_BEGIN(b,loc) NEW_NODE(NODE_BEGIN,0,b,0,loc)
#define NEW_RESCUE(b,res,e,loc) NEW_NODE(NODE_RESCUE,b,res,e,loc)
#define NEW_RESBODY(a,ex,n,loc) NEW_NODE(NODE_RESBODY,n,ex,a,loc)
#define NEW_ENSURE(b,en,loc) NEW_NODE(NODE_ENSURE,b,0,en,loc)
#define NEW_RETURN(s,loc) NEW_NODE(NODE_RETURN,s,0,0,loc)
#define NEW_YIELD(a,loc) NEW_NODE(NODE_YIELD,a,0,0,loc)
#define NEW_LIST(a,loc) NEW_NODE(NODE_LIST,a,1,0,loc)
#define NEW_ZLIST(loc) NEW_NODE(NODE_ZLIST,0,0,0,loc)
#define NEW_HASH(a,loc) NEW_NODE(NODE_HASH,a,0,0,loc)
#define NEW_MASGN(l,r,loc) NEW_NODE(NODE_MASGN,l,0,r,loc)
#define NEW_GASGN(v,val,loc) NEW_NODE(NODE_GASGN,v,val,v,loc)
#define NEW_LASGN(v,val,loc) NEW_NODE(NODE_LASGN,v,val,0,loc)
#define NEW_DASGN(v,val,loc) NEW_NODE(NODE_DASGN,v,val,0,loc)
#define NEW_IASGN(v,val,loc) NEW_NODE(NODE_IASGN,v,val,0,loc)
#define NEW_CDECL(v,val,path,loc) NEW_NODE(NODE_CDECL,v,val,path,loc)
#define NEW_CVASGN(v,val,loc) NEW_NODE(NODE_CVASGN,v,val,0,loc)
#define NEW_OP_ASGN1(p,id,a,loc) NEW_NODE(NODE_OP_ASGN1,p,id,a,loc)
#define NEW_OP_ASGN2(r,t,i,o,val,loc) NEW_NODE(NODE_OP_ASGN2,r,val,NEW_OP_ASGN22(i,o,t,loc),loc)
#define NEW_OP_ASGN22(i,o,t,loc) NEW_NODE(NODE_OP_ASGN2,i,o,t,loc)
#define NEW_OP_ASGN_OR(i,val,loc) NEW_NODE(NODE_OP_ASGN_OR,i,val,0,loc)
#define NEW_OP_ASGN_AND(i,val,loc) NEW_NODE(NODE_OP_ASGN_AND,i,val,0,loc)
#define NEW_OP_CDECL(v,op,val,loc) NEW_NODE(NODE_OP_CDECL,v,val,op,loc)
#define NEW_GVAR(v,loc) NEW_NODE(NODE_GVAR,v,0,v,loc)
#define NEW_LVAR(v,loc) NEW_NODE(NODE_LVAR,v,0,0,loc)
#define NEW_DVAR(v,loc) NEW_NODE(NODE_DVAR,v,0,0,loc)
#define NEW_IVAR(v,loc) NEW_NODE(NODE_IVAR,v,0,0,loc)
#define NEW_CONST(v,loc) NEW_NODE(NODE_CONST,v,0,0,loc)
#define NEW_CVAR(v,loc) NEW_NODE(NODE_CVAR,v,0,0,loc)
#define NEW_NTH_REF(n,loc) NEW_NODE(NODE_NTH_REF,0,n,0,loc)
#define NEW_BACK_REF(n,loc) NEW_NODE(NODE_BACK_REF,0,n,0,loc)
#define NEW_MATCH(c,loc) NEW_NODE(NODE_MATCH,c,0,0,loc)
#define NEW_MATCH2(n1,n2,loc) NEW_NODE(NODE_MATCH2,n1,n2,0,loc)
#define NEW_MATCH3(r,n2,loc) NEW_NODE(NODE_MATCH3,r,n2,0,loc)
#define NEW_LIT(l,loc) NEW_NODE(NODE_LIT,l,0,0,loc)
#define NEW_STR(s,loc) NEW_NODE(NODE_STR,s,0,0,loc)
#define NEW_DSTR(s,loc) NEW_NODE(NODE_DSTR,s,1,0,loc)
#define NEW_XSTR(s,loc) NEW_NODE(NODE_XSTR,s,0,0,loc)
#define NEW_DXSTR(s,loc) NEW_NODE(NODE_DXSTR,s,0,0,loc)
#define NEW_DSYM(s,loc) NEW_NODE(NODE_DSYM,s,0,0,loc)
#define NEW_EVSTR(n,loc) NEW_NODE(NODE_EVSTR,0,(n),0,loc)
#define NEW_CALL(r,m,a,loc) NEW_NODE(NODE_CALL,r,m,a,loc)
#define NEW_OPCALL(r,m,a,loc) NEW_NODE(NODE_OPCALL,r,m,a,loc)
#define NEW_FCALL(m,a,loc) NEW_NODE(NODE_FCALL,0,m,a,loc)
#define NEW_VCALL(m,loc) NEW_NODE(NODE_VCALL,0,m,0,loc)
#define NEW_SUPER(a,loc) NEW_NODE(NODE_SUPER,0,0,a,loc)
#define NEW_ZSUPER(loc) NEW_NODE(NODE_ZSUPER,0,0,0,loc)
#define NEW_ARGS_AUX(r,b,loc) NEW_NODE(NODE_ARGS_AUX,r,b,0,loc)
#define NEW_OPT_ARG(i,v,loc) NEW_NODE(NODE_OPT_ARG,i,v,0,loc)
#define NEW_KW_ARG(i,v,loc) NEW_NODE(NODE_KW_ARG,i,v,0,loc)
#define NEW_POSTARG(i,v,loc) NEW_NODE(NODE_POSTARG,i,v,0,loc)
#define NEW_ARGSCAT(a,b,loc) NEW_NODE(NODE_ARGSCAT,a,b,0,loc)
#define NEW_ARGSPUSH(a,b,loc) NEW_NODE(NODE_ARGSPUSH,a,b,0,loc)
#define NEW_SPLAT(a,loc) NEW_NODE(NODE_SPLAT,a,0,0,loc)
#define NEW_BLOCK_PASS(b,loc) NEW_NODE(NODE_BLOCK_PASS,0,b,0,loc)
#define NEW_ALIAS(n,o,loc) NEW_NODE(NODE_ALIAS,n,o,0,loc)
#define NEW_VALIAS(n,o,loc) NEW_NODE(NODE_VALIAS,n,o,0,loc)
#define NEW_UNDEF(i,loc) NEW_NODE(NODE_UNDEF,0,i,0,loc)
#define NEW_CLASS(n,b,s,loc) NEW_NODE(NODE_CLASS,n,NEW_SCOPE(0,b,loc),(s),loc)
#define NEW_SCLASS(r,b,loc) NEW_NODE(NODE_SCLASS,r,NEW_SCOPE(0,b,loc),0,loc)
#define NEW_MODULE(n,b,loc) NEW_NODE(NODE_MODULE,n,NEW_SCOPE(0,b,loc),0,loc)
#define NEW_COLON2(c,i,loc) NEW_NODE(NODE_COLON2,c,i,0,loc)
#define NEW_COLON3(i,loc) NEW_NODE(NODE_COLON3,0,i,0,loc)
#define NEW_DOT2(b,e,loc) NEW_NODE(NODE_DOT2,b,e,0,loc)
#define NEW_DOT3(b,e,loc) NEW_NODE(NODE_DOT3,b,e,0,loc)
#define NEW_SELF(loc) NEW_NODE(NODE_SELF,0,0,1,loc)
#define NEW_NIL(loc) NEW_NODE(NODE_NIL,0,0,0,loc)
#define NEW_TRUE(loc) NEW_NODE(NODE_TRUE,0,0,0,loc)
#define NEW_FALSE(loc) NEW_NODE(NODE_FALSE,0,0,0,loc)
#define NEW_ERRINFO(loc) NEW_NODE(NODE_ERRINFO,0,0,0,loc)
#define NEW_DEFINED(e,loc) NEW_NODE(NODE_DEFINED,e,0,0,loc)
#define NEW_PREEXE(b,loc) NEW_SCOPE(b,loc)
#define NEW_POSTEXE(b,loc) NEW_NODE(NODE_POSTEXE,0,b,0,loc)
#define NEW_ATTRASGN(r,m,a,loc) NEW_NODE(NODE_ATTRASGN,r,m,a,loc)
#define NODE_SPECIAL_REQUIRED_KEYWORD ((NODE *)-1)
#define NODE_REQUIRED_KEYWORD_P(node) ((node)->nd_value == NODE_SPECIAL_REQUIRED_KEYWORD)
#define NODE_SPECIAL_NO_NAME_REST ((NODE *)-1)
#define NODE_NAMED_REST_P(node) ((node) != NODE_SPECIAL_NO_NAME_REST)
#define NODE_SPECIAL_EXCESSIVE_COMMA ((ID)1)
#define NODE_SPECIAL_NO_REST_KEYWORD ((NODE *)-1)
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RUBY_ATOMIC_H 
#define RUBY_ATOMIC_GENERIC_MACRO 1
#define RUBY_ATOMIC_FETCH_ADD(var,val) rbimpl_atomic_fetch_add(&(var), (val))
#define RUBY_ATOMIC_FETCH_SUB(var,val) rbimpl_atomic_fetch_sub(&(var), (val))
#define RUBY_ATOMIC_OR(var,val) rbimpl_atomic_or(&(var), (val))
#define RUBY_ATOMIC_EXCHANGE(var,val) rbimpl_atomic_exchange(&(var), (val))
#define RUBY_ATOMIC_CAS(var,oldval,newval) rbimpl_atomic_cas(&(var), (oldval), (newval))
#define RUBY_ATOMIC_SET(var,val) rbimpl_atomic_set(&(var), (val))
#define RUBY_ATOMIC_ADD(var,val) rbimpl_atomic_add(&(var), (val))
#define RUBY_ATOMIC_SUB(var,val) rbimpl_atomic_sub(&(var), (val))
#define RUBY_ATOMIC_INC(var) rbimpl_atomic_inc(&(var))
#define RUBY_ATOMIC_DEC(var) rbimpl_atomic_dec(&(var))
#define RUBY_ATOMIC_SIZE_INC(var) rbimpl_atomic_size_inc(&(var))
#define RUBY_ATOMIC_SIZE_DEC(var) rbimpl_atomic_size_dec(&(var))
#define RUBY_ATOMIC_SIZE_EXCHANGE(var,val) rbimpl_atomic_size_exchange(&(var), (val))
#define RUBY_ATOMIC_SIZE_CAS(var,oldval,newval) rbimpl_atomic_size_cas(&(var), (oldval), (newval))
#define RUBY_ATOMIC_SIZE_ADD(var,val) rbimpl_atomic_size_add(&(var), (val))
#define RUBY_ATOMIC_SIZE_SUB(var,val) rbimpl_atomic_size_sub(&(var), (val))
#define RUBY_ATOMIC_PTR_EXCHANGE(var,val) RBIMPL_CAST(rbimpl_atomic_ptr_exchange((void **)&(var), (void *)val))
#define RUBY_ATOMIC_PTR_CAS(var,oldval,newval) RBIMPL_CAST(rbimpl_atomic_ptr_cas((void **)&(var), (oldval), (newval)))
#define RUBY_ATOMIC_VALUE_EXCHANGE(var,val) rbimpl_atomic_value_exchange(&(var), (val))
#define RUBY_ATOMIC_VALUE_CAS(var,oldval,newval) rbimpl_atomic_value_cas(&(var), (oldval), (newval))
#define ATOMIC_ADD(var,val) RUBY_ATOMIC_ADD(var, val)
#define ATOMIC_CAS(var,oldval,newval) RUBY_ATOMIC_CAS(var, oldval, newval)
#define ATOMIC_DEC(var) RUBY_ATOMIC_DEC(var)
#define ATOMIC_EXCHANGE(var,val) RUBY_ATOMIC_EXCHANGE(var, val)
#define ATOMIC_FETCH_ADD(var,val) RUBY_ATOMIC_FETCH_ADD(var, val)
#define ATOMIC_FETCH_SUB(var,val) RUBY_ATOMIC_FETCH_SUB(var, val)
#define ATOMIC_INC(var) RUBY_ATOMIC_INC(var)
#define ATOMIC_OR(var,val) RUBY_ATOMIC_OR(var, val)
#define ATOMIC_PTR_CAS(var,oldval,newval) RUBY_ATOMIC_PTR_CAS(var, oldval, newval)
#define ATOMIC_PTR_EXCHANGE(var,val) RUBY_ATOMIC_PTR_EXCHANGE(var, val)
#define ATOMIC_SET(var,val) RUBY_ATOMIC_SET(var, val)
#define ATOMIC_SIZE_ADD(var,val) RUBY_ATOMIC_SIZE_ADD(var, val)
#define ATOMIC_SIZE_CAS(var,oldval,newval) RUBY_ATOMIC_SIZE_CAS(var, oldval, newval)
#define ATOMIC_SIZE_DEC(var) RUBY_ATOMIC_SIZE_DEC(var)
#define ATOMIC_SIZE_EXCHANGE(var,val) RUBY_ATOMIC_SIZE_EXCHANGE(var, val)
#define ATOMIC_SIZE_INC(var) RUBY_ATOMIC_SIZE_INC(var)
#define ATOMIC_SIZE_SUB(var,val) RUBY_ATOMIC_SIZE_SUB(var, val)
#define ATOMIC_SUB(var,val) RUBY_ATOMIC_SUB(var, val)
#define ATOMIC_VALUE_CAS(var,oldval,val) RUBY_ATOMIC_VALUE_CAS(var, oldval, val)
#define ATOMIC_VALUE_EXCHANGE(var,val) RUBY_ATOMIC_VALUE_EXCHANGE(var, val)
#define RUBY_VM_OPTS_H 
#define OPT_TAILCALL_OPTIMIZATION 0
#define OPT_PEEPHOLE_OPTIMIZATION 1
#define OPT_SPECIALISED_INSTRUCTION 1
#define OPT_INLINE_CONST_CACHE 1
#define OPT_FROZEN_STRING_LITERAL 0
#define OPT_DEBUG_FROZEN_STRING_LITERAL 0
#define OPT_THREADED_CODE 0
#define OPT_DIRECT_THREADED_CODE (OPT_THREADED_CODE == 0)
#define OPT_TOKEN_THREADED_CODE (OPT_THREADED_CODE == 1)
#define OPT_CALL_THREADED_CODE (OPT_THREADED_CODE == 2)
#define OPT_CHECKED_RUN 1
#define OPT_INLINE_METHOD_CACHE 1
#define OPT_GLOBAL_METHOD_CACHE 1
#define OPT_BLOCKINLINING 0
#define OPT_IC_FOR_IVAR 1
#define OPT_OPERANDS_UNIFICATION 1
#define OPT_INSTRUCTIONS_UNIFICATION 0
#define OPT_UNIFY_ALL_COMBINATION 0
#define OPT_STACK_CACHING 0
#define OPT_SUPPORT_JOKE 0
#define OPT_SUPPORT_CALL_C_FUNCTION 0
#define VM_COLLECT_USAGE_DETAILS 0
#define RUBY_DARRAY_H 
#define rb_darray(T) struct { rb_darray_meta_t meta; T data[]; } *
#define rb_darray_get(ary,idx) ((ary)->data[(idx)])
#define rb_darray_set(ary,idx,element) ((ary)->data[(idx)] = (element))
#define rb_darray_ref(ary,idx) (&((ary)->data[(idx)]))
#define rb_darray_append(ptr_to_ary,element) ( rb_darray_ensure_space((ptr_to_ary), sizeof(**(ptr_to_ary)), sizeof((*(ptr_to_ary))->data[0])) ? ( rb_darray_set(*(ptr_to_ary), (*(ptr_to_ary))->meta.size, (element)), ++((*(ptr_to_ary))->meta.size), 1 ) : 0)
#define rb_darray_back(ary) ((ary)->data[(ary)->meta.size - 1])
#define rb_darray_pop_back(ary) ((ary)->meta.size--)
#define rb_darray_remove_unordered(ary,idx) do { rb_darray_set(ary, idx, rb_darray_back(ary)); rb_darray_pop_back(ary); } while (0);
#define rb_darray_foreach(ary,idx_name,elem_ptr_var) for (int idx_name = 0; idx_name < rb_darray_size(ary) && ((elem_ptr_var) = rb_darray_ref(ary, idx_name)); ++idx_name)
#define rb_darray_for(ary,idx_name) for (int idx_name = 0; idx_name < rb_darray_size(ary); ++idx_name)
#define rb_darray_make(ptr_to_ary,size) rb_darray_make_impl((ptr_to_ary), size, sizeof(**(ptr_to_ary)), sizeof((*(ptr_to_ary))->data[0]))
#define rb_darray_clear(ary) (ary->meta.size = 0)
#define RUBY_THREAD_NATIVE_H 1
#define _PTHREAD_H 1
#define _SCHED_H 1
#define __need_size_t 
#undef __need_ptrdiff_t
#undef __need_size_t
#undef __need_wchar_t
#undef NULL
#define NULL ((void *)0)
#undef __need_NULL
#define offsetof(TYPE,MEMBER) __builtin_offsetof (TYPE, MEMBER)
#define __need_time_t 
#define __need_timespec 
#define SCHED_OTHER 0
#define SCHED_FIFO 1
#define SCHED_RR 2
#define SCHED_BATCH 3
#define SCHED_IDLE 5
#define SCHED_RESET_ON_FORK 0x40000000
#define CSIGNAL 0x000000ff
#define CLONE_VM 0x00000100
#define CLONE_FS 0x00000200
#define CLONE_FILES 0x00000400
#define CLONE_SIGHAND 0x00000800
#define CLONE_PTRACE 0x00002000
#define CLONE_VFORK 0x00004000
#define CLONE_PARENT 0x00008000
#define CLONE_THREAD 0x00010000
#define CLONE_NEWNS 0x00020000
#define CLONE_SYSVSEM 0x00040000
#define CLONE_SETTLS 0x00080000
#define CLONE_PARENT_SETTID 0x00100000
#define CLONE_CHILD_CLEARTID 0x00200000
#define CLONE_DETACHED 0x00400000
#define CLONE_UNTRACED 0x00800000
#define CLONE_CHILD_SETTID 0x01000000
#define CLONE_NEWUTS 0x04000000
#define CLONE_NEWIPC 0x08000000
#define CLONE_NEWUSER 0x10000000
#define CLONE_NEWPID 0x20000000
#define CLONE_NEWNET 0x40000000
#define CLONE_IO 0x80000000
#define __defined_schedparam 1
#undef __need_schedparam
#define __cpu_set_t_defined 
#define __CPU_SETSIZE 1024
#define __NCPUBITS (8 * sizeof (__cpu_mask))
#define __CPUELT(cpu) ((cpu) / __NCPUBITS)
#define __CPUMASK(cpu) ((__cpu_mask) 1 << ((cpu) % __NCPUBITS))
#define __CPU_ZERO_S(setsize,cpusetp) do __builtin_memset (cpusetp, '\0', setsize); while (0)
#define __CPU_SET_S(cpu,setsize,cpusetp) (__extension__ ({ size_t __cpu = (cpu); __cpu < 8 * (setsize) ? (((__cpu_mask *) ((cpusetp)->__bits))[__CPUELT (__cpu)] |= __CPUMASK (__cpu)) : 0; }))
#define __CPU_CLR_S(cpu,setsize,cpusetp) (__extension__ ({ size_t __cpu = (cpu); __cpu < 8 * (setsize) ? (((__cpu_mask *) ((cpusetp)->__bits))[__CPUELT (__cpu)] &= ~__CPUMASK (__cpu)) : 0; }))
#define __CPU_ISSET_S(cpu,setsize,cpusetp) (__extension__ ({ size_t __cpu = (cpu); __cpu < 8 * (setsize) ? ((((__const __cpu_mask *) ((cpusetp)->__bits))[__CPUELT (__cpu)] & __CPUMASK (__cpu))) != 0 : 0; }))
#define __CPU_COUNT_S(setsize,cpusetp) __sched_cpucount (setsize, cpusetp)
#define __CPU_EQUAL_S(setsize,cpusetp1,cpusetp2) (__builtin_memcmp (cpusetp1, cpusetp2, setsize) == 0)
#define __CPU_OP_S(setsize,destset,srcset1,srcset2,op) (__extension__ ({ cpu_set_t *__dest = (destset); __const __cpu_mask *__arr1 = (srcset1)->__bits; __const __cpu_mask *__arr2 = (srcset2)->__bits; size_t __imax = (setsize) / sizeof (__cpu_mask); size_t __i; for (__i = 0; __i < __imax; ++__i) ((__cpu_mask *) __dest->__bits)[__i] = __arr1[__i] op __arr2[__i]; __dest; }))
#define __CPU_ALLOC_SIZE(count) ((((count) + __NCPUBITS - 1) / __NCPUBITS) * sizeof (__cpu_mask))
#define __CPU_ALLOC(count) __sched_cpualloc (count)
#define __CPU_FREE(cpuset) __sched_cpufree (cpuset)
#define sched_priority __sched_priority
#define CPU_SETSIZE __CPU_SETSIZE
#define CPU_SET(cpu,cpusetp) __CPU_SET_S (cpu, sizeof (cpu_set_t), cpusetp)
#define CPU_CLR(cpu,cpusetp) __CPU_CLR_S (cpu, sizeof (cpu_set_t), cpusetp)
#define CPU_ISSET(cpu,cpusetp) __CPU_ISSET_S (cpu, sizeof (cpu_set_t), cpusetp)
#define CPU_ZERO(cpusetp) __CPU_ZERO_S (sizeof (cpu_set_t), cpusetp)
#define CPU_COUNT(cpusetp) __CPU_COUNT_S (sizeof (cpu_set_t), cpusetp)
#define CPU_SET_S(cpu,setsize,cpusetp) __CPU_SET_S (cpu, setsize, cpusetp)
#define CPU_CLR_S(cpu,setsize,cpusetp) __CPU_CLR_S (cpu, setsize, cpusetp)
#define CPU_ISSET_S(cpu,setsize,cpusetp) __CPU_ISSET_S (cpu, setsize, cpusetp)
#define CPU_ZERO_S(setsize,cpusetp) __CPU_ZERO_S (setsize, cpusetp)
#define CPU_COUNT_S(setsize,cpusetp) __CPU_COUNT_S (setsize, cpusetp)
#define CPU_EQUAL(cpusetp1,cpusetp2) __CPU_EQUAL_S (sizeof (cpu_set_t), cpusetp1, cpusetp2)
#define CPU_EQUAL_S(setsize,cpusetp1,cpusetp2) __CPU_EQUAL_S (setsize, cpusetp1, cpusetp2)
#define CPU_AND(destset,srcset1,srcset2) __CPU_OP_S (sizeof (cpu_set_t), destset, srcset1, srcset2, &)
#define CPU_OR(destset,srcset1,srcset2) __CPU_OP_S (sizeof (cpu_set_t), destset, srcset1, srcset2, |)
#define CPU_XOR(destset,srcset1,srcset2) __CPU_OP_S (sizeof (cpu_set_t), destset, srcset1, srcset2, ^)
#define CPU_AND_S(setsize,destset,srcset1,srcset2) __CPU_OP_S (setsize, destset, srcset1, srcset2, &)
#define CPU_OR_S(setsize,destset,srcset1,srcset2) __CPU_OP_S (setsize, destset, srcset1, srcset2, |)
#define CPU_XOR_S(setsize,destset,srcset1,srcset2) __CPU_OP_S (setsize, destset, srcset1, srcset2, ^)
#define CPU_ALLOC_SIZE(count) __CPU_ALLOC_SIZE (count)
#define CPU_ALLOC(count) __CPU_ALLOC (count)
#define CPU_FREE(cpuset) __CPU_FREE (cpuset)
#define __WORDSIZE 64
#define __WORDSIZE_COMPAT32 1
#define PTHREAD_CREATE_JOINABLE PTHREAD_CREATE_JOINABLE
#define PTHREAD_CREATE_DETACHED PTHREAD_CREATE_DETACHED
#define PTHREAD_MUTEX_INITIALIZER { { 0, 0, 0, 0, 0, 0, { 0, 0 } } }
#define PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP { { 0, 0, 0, 0, PTHREAD_MUTEX_RECURSIVE_NP, 0, { 0, 0 } } }
#define PTHREAD_ERRORCHECK_MUTEX_INITIALIZER_NP { { 0, 0, 0, 0, PTHREAD_MUTEX_ERRORCHECK_NP, 0, { 0, 0 } } }
#define PTHREAD_ADAPTIVE_MUTEX_INITIALIZER_NP { { 0, 0, 0, 0, PTHREAD_MUTEX_ADAPTIVE_NP, 0, { 0, 0 } } }
#define PTHREAD_RWLOCK_INITIALIZER { { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } }
#define PTHREAD_RWLOCK_WRITER_NONRECURSIVE_INITIALIZER_NP { { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, PTHREAD_RWLOCK_PREFER_WRITER_NONRECURSIVE_NP } }
#define PTHREAD_INHERIT_SCHED PTHREAD_INHERIT_SCHED
#define PTHREAD_EXPLICIT_SCHED PTHREAD_EXPLICIT_SCHED
#define PTHREAD_SCOPE_SYSTEM PTHREAD_SCOPE_SYSTEM
#define PTHREAD_SCOPE_PROCESS PTHREAD_SCOPE_PROCESS
#define PTHREAD_PROCESS_PRIVATE PTHREAD_PROCESS_PRIVATE
#define PTHREAD_PROCESS_SHARED PTHREAD_PROCESS_SHARED
#define PTHREAD_COND_INITIALIZER { { 0, 0, 0, 0, 0, (void *) 0, 0, 0 } }
#define PTHREAD_CANCEL_ENABLE PTHREAD_CANCEL_ENABLE
#define PTHREAD_CANCEL_DISABLE PTHREAD_CANCEL_DISABLE
#define PTHREAD_CANCEL_DEFERRED PTHREAD_CANCEL_DEFERRED
#define PTHREAD_CANCEL_ASYNCHRONOUS PTHREAD_CANCEL_ASYNCHRONOUS
#define PTHREAD_CANCELED ((void *) -1)
#define PTHREAD_ONCE_INIT 0
#define PTHREAD_BARRIER_SERIAL_THREAD -1
#define __cleanup_fct_attribute 
#define pthread_cleanup_push(routine,arg) do { __pthread_unwind_buf_t __cancel_buf; void (*__cancel_routine) (void *) = (routine); void *__cancel_arg = (arg); int __not_first_call = __sigsetjmp ((struct __jmp_buf_tag *) (void *) __cancel_buf.__cancel_jmp_buf, 0); if (__builtin_expect (__not_first_call, 0)) { __cancel_routine (__cancel_arg); __pthread_unwind_next (&__cancel_buf); } __pthread_register_cancel (&__cancel_buf); do {
#define pthread_cleanup_pop(execute) do { } while (0); } while (0); __pthread_unregister_cancel (&__cancel_buf); if (execute) __cancel_routine (__cancel_arg); } while (0)
#define pthread_cleanup_push_defer_np(routine,arg) do { __pthread_unwind_buf_t __cancel_buf; void (*__cancel_routine) (void *) = (routine); void *__cancel_arg = (arg); int __not_first_call = __sigsetjmp ((struct __jmp_buf_tag *) (void *) __cancel_buf.__cancel_jmp_buf, 0); if (__builtin_expect (__not_first_call, 0)) { __cancel_routine (__cancel_arg); __pthread_unwind_next (&__cancel_buf); } __pthread_register_cancel_defer (&__cancel_buf); do {
#define pthread_cleanup_pop_restore_np(execute) do { } while (0); } while (0); __pthread_unregister_cancel_restore (&__cancel_buf); if (execute) __cancel_routine (__cancel_arg); } while (0)
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RUBY_THREAD_PTHREAD_H 
#define RB_NATIVETHREAD_LOCK_INIT PTHREAD_MUTEX_INITIALIZER
#define RB_NATIVETHREAD_COND_INIT PTHREAD_COND_INITIALIZER
#undef except
#undef try
#undef leave
#undef finally
#define RB_THREAD_LOCAL_SPECIFIER __thread
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RUBY_VM_THREAD_MODEL 2
#define VM_INSN_INFO_TABLE_IMPL 2
#define RUBY_NSIG NSIG
#define RUBY_SIGCHLD (SIGCLD)
#define SIGCHLD_LOSSY (0)
#define WAITPID_USE_SIGCHLD (RUBY_SIGCHLD || SIGCHLD_LOSSY)
#define USE_SIGALTSTACK 
#define RB_ALTSTACK_INIT(var,altstack) var = rb_register_sigaltstack(altstack)
#define RB_ALTSTACK_FREE(var) free(var)
#define RB_ALTSTACK(var) var
#define TAG_NONE RUBY_TAG_NONE
#define TAG_RETURN RUBY_TAG_RETURN
#define TAG_BREAK RUBY_TAG_BREAK
#define TAG_NEXT RUBY_TAG_NEXT
#define TAG_RETRY RUBY_TAG_RETRY
#define TAG_REDO RUBY_TAG_REDO
#define TAG_RAISE RUBY_TAG_RAISE
#define TAG_THROW RUBY_TAG_THROW
#define TAG_FATAL RUBY_TAG_FATAL
#define TAG_MASK RUBY_TAG_MASK
#define GET_IC_SERIAL(ice) (ice)->ic_serial.raw
#define SET_IC_SERIAL(ice,v) (ice)->ic_serial.raw = (v)
#define CoreDataFromValue(obj,type) (type*)DATA_PTR(obj)
#define GetCoreDataFromValue(obj,type,ptr) ((ptr) = CoreDataFromValue((obj), type))
#define PATHOBJ_PATH 0
#define PATHOBJ_REALPATH 1
#define USE_LAZY_LOAD 0
#define GetVMPtr(obj,ptr) GetCoreDataFromValue((obj), rb_vm_t, (ptr))
#define VM_GLOBAL_CC_CACHE_TABLE_SIZE 1023
#define RUBY_VM_SIZE_ALIGN 4096
#define RUBY_VM_THREAD_VM_STACK_SIZE ( 128 * 1024 * sizeof(VALUE))
#define RUBY_VM_THREAD_VM_STACK_SIZE_MIN ( 2 * 1024 * sizeof(VALUE))
#define RUBY_VM_THREAD_MACHINE_STACK_SIZE ( 128 * 1024 * sizeof(VALUE))
#define RUBY_VM_THREAD_MACHINE_STACK_SIZE_MIN ( 16 * 1024 * sizeof(VALUE))
#define RUBY_VM_FIBER_VM_STACK_SIZE ( 16 * 1024 * sizeof(VALUE))
#define RUBY_VM_FIBER_VM_STACK_SIZE_MIN ( 2 * 1024 * sizeof(VALUE))
#define RUBY_VM_FIBER_MACHINE_STACK_SIZE ( 64 * 1024 * sizeof(VALUE))
#define RUBY_VM_FIBER_MACHINE_STACK_SIZE_MIN ( 16 * 1024 * sizeof(VALUE))
#define INTEGER_REDEFINED_OP_FLAG (1 << 0)
#define FLOAT_REDEFINED_OP_FLAG (1 << 1)
#define STRING_REDEFINED_OP_FLAG (1 << 2)
#define ARRAY_REDEFINED_OP_FLAG (1 << 3)
#define HASH_REDEFINED_OP_FLAG (1 << 4)
#define SYMBOL_REDEFINED_OP_FLAG (1 << 6)
#define TIME_REDEFINED_OP_FLAG (1 << 7)
#define REGEXP_REDEFINED_OP_FLAG (1 << 8)
#define NIL_REDEFINED_OP_FLAG (1 << 9)
#define TRUE_REDEFINED_OP_FLAG (1 << 10)
#define FALSE_REDEFINED_OP_FLAG (1 << 11)
#define PROC_REDEFINED_OP_FLAG (1 << 12)
#define BASIC_OP_UNREDEFINED_P(op,klass) (LIKELY((GET_VM()->redefined_flag[(op)]&(klass)) == 0))
#define VM_DEBUG_BP_CHECK 0
#define VM_DEBUG_VERIFY_METHOD_CACHE (VMDEBUG != 0)
#define rb_execution_context_t rb_execution_context_t
#define VM_CORE_H_EC_DEFINED 1
#define RB_THREAD_T_HAS_NATIVE_ID 
#define VM_DEFINECLASS_TYPE(x) ((rb_vm_defineclass_type_t)(x) & VM_DEFINECLASS_TYPE_MASK)
#define VM_DEFINECLASS_FLAG_SCOPED 0x08
#define VM_DEFINECLASS_FLAG_HAS_SUPERCLASS 0x10
#define VM_DEFINECLASS_SCOPED_P(x) ((x) & VM_DEFINECLASS_FLAG_SCOPED)
#define VM_DEFINECLASS_HAS_SUPERCLASS_P(x) ((x) & VM_DEFINECLASS_FLAG_HAS_SUPERCLASS)
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define GetProcPtr(obj,ptr) GetCoreDataFromValue((obj), rb_proc_t, (ptr))
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define GetBindingPtr(obj,ptr) GetCoreDataFromValue((obj), rb_binding_t, (ptr))
#define VM_CHECKMATCH_TYPE_MASK 0x03
#define VM_CHECKMATCH_ARRAY 0x04
#define FUNC_FASTCALL(x) x
#define VM_TAGGED_PTR_SET(p,tag) ((VALUE)(p) | (tag))
#define VM_TAGGED_PTR_REF(v,mask) ((void *)((v) & ~mask))
#define GC_GUARDED_PTR(p) VM_TAGGED_PTR_SET((p), 0x01)
#define GC_GUARDED_PTR_REF(p) VM_TAGGED_PTR_REF((p), 0x03)
#define GC_GUARDED_PTR_P(p) (((VALUE)(p)) & 0x01)
#define VM_ENV_DATA_SIZE ( 3)
#define VM_ENV_DATA_INDEX_ME_CREF (-2)
#define VM_ENV_DATA_INDEX_SPECVAL (-1)
#define VM_ENV_DATA_INDEX_FLAGS ( 0)
#define VM_ENV_DATA_INDEX_ENV ( 1)
#define VM_ENV_INDEX_LAST_LVAR (-VM_ENV_DATA_SIZE)
#define RUBYVM_CFUNC_FRAME_P(cfp) (VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_CFUNC)
#define VM_GUARDED_PREV_EP(ep) GC_GUARDED_PTR(ep)
#define VM_BLOCK_HANDLER_NONE 0
#define RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp) ((cfp)+1)
#define RUBY_VM_NEXT_CONTROL_FRAME(cfp) ((cfp)-1)
#define RUBY_VM_VALID_CONTROL_FRAME_P(cfp,ecfp) ((void *)(ecfp) > (void *)(cfp))
#define SDR() rb_vmdebug_stack_dump_raw(GET_EC(), GET_EC()->cfp)
#define SDR2(cfp) rb_vmdebug_stack_dump_raw(GET_EC(), (cfp))
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define rb_vm_register_special_exception(sp,e,m) rb_vm_register_special_exception_str(sp, e, rb_usascii_str_new_static((m), (long)rb_strlen_lit(m)))
#define sysstack_error GET_VM()->special_exceptions[ruby_error_sysstack]
#define CHECK_VM_STACK_OVERFLOW0(cfp,sp,margin) do { STATIC_ASSERT(sizeof_sp, sizeof(*(sp)) == sizeof(VALUE)); STATIC_ASSERT(sizeof_cfp, sizeof(*(cfp)) == sizeof(rb_control_frame_t)); const struct rb_control_frame_struct *bound = (void *)&(sp)[(margin)]; if (UNLIKELY((cfp) <= &bound[1])) { vm_stackoverflow(); } } while (0)
#define CHECK_VM_STACK_OVERFLOW(cfp,margin) CHECK_VM_STACK_OVERFLOW0((cfp), (cfp)->sp, (margin))
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define GET_VM() rb_current_vm()
#define GET_RACTOR() rb_current_ractor()
#define GET_THREAD() rb_current_thread()
#define GET_EC() rb_current_execution_context(true)
#define RUBY_VM_SET_TIMER_INTERRUPT(ec) ATOMIC_OR((ec)->interrupt_flag, TIMER_INTERRUPT_MASK)
#define RUBY_VM_SET_INTERRUPT(ec) ATOMIC_OR((ec)->interrupt_flag, PENDING_INTERRUPT_MASK)
#define RUBY_VM_SET_POSTPONED_JOB_INTERRUPT(ec) ATOMIC_OR((ec)->interrupt_flag, POSTPONED_JOB_INTERRUPT_MASK)
#define RUBY_VM_SET_TRAP_INTERRUPT(ec) ATOMIC_OR((ec)->interrupt_flag, TRAP_INTERRUPT_MASK)
#define RUBY_VM_SET_TERMINATE_INTERRUPT(ec) ATOMIC_OR((ec)->interrupt_flag, TERMINATE_INTERRUPT_MASK)
#define RUBY_VM_SET_VM_BARRIER_INTERRUPT(ec) ATOMIC_OR((ec)->interrupt_flag, VM_BARRIER_INTERRUPT_MASK)
#define RUBY_VM_INTERRUPTED(ec) ((ec)->interrupt_flag & ~(ec)->interrupt_mask & (PENDING_INTERRUPT_MASK|TRAP_INTERRUPT_MASK))
#define RUBY_VM_CHECK_INTS(ec) rb_vm_check_ints(ec)
#define EXEC_EVENT_HOOK_ORIG(ec_,hooks_,flag_,self_,id_,called_id_,klass_,data_,pop_p_) do { const rb_event_flag_t flag_arg_ = (flag_); rb_hook_list_t *hooks_arg_ = (hooks_); if (UNLIKELY((hooks_arg_)->events & (flag_arg_))) { rb_exec_event_hook_orig(ec_, hooks_arg_, flag_arg_, self_, id_, called_id_, klass_, data_, pop_p_); } } while (0)
#define EXEC_EVENT_HOOK(ec_,flag_,self_,id_,called_id_,klass_,data_) EXEC_EVENT_HOOK_ORIG(ec_, rb_ec_ractor_hooks(ec_), flag_, self_, id_, called_id_, klass_, data_, 0)
#define EXEC_EVENT_HOOK_AND_POP_FRAME(ec_,flag_,self_,id_,called_id_,klass_,data_) EXEC_EVENT_HOOK_ORIG(ec_, rb_ec_ractor_hooks(ec_), flag_, self_, id_, called_id_, klass_, data_, 1)
#pragma GCC visibility push(default)
#define RUBY_EVENT_COVERAGE_LINE 0x010000
#define RUBY_EVENT_COVERAGE_BRANCH 0x020000
#pragma GCC visibility pop
#define PASS_PASSED_BLOCK_HANDLER_EC(ec) pass_passed_block_handler(ec)
#define PASS_PASSED_BLOCK_HANDLER() pass_passed_block_handler(GET_EC())
#define ruby_setjmp(env) RUBY_SETJMP(env)
#define ruby_longjmp(env,val) RUBY_LONGJMP((env),(val))
#define _ERRNO_H 1
#undef EDOM
#undef EILSEQ
#undef ERANGE
#define _ASM_GENERIC_ERRNO_H 
#define _ASM_GENERIC_ERRNO_BASE_H 
#define EPERM 1
#define ENOENT 2
#define ESRCH 3
#define EINTR 4
#define EIO 5
#define ENXIO 6
#define E2BIG 7
#define ENOEXEC 8
#define EBADF 9
#define ECHILD 10
#define EAGAIN 11
#define ENOMEM 12
#define EACCES 13
#define EFAULT 14
#define ENOTBLK 15
#define EBUSY 16
#define EEXIST 17
#define EXDEV 18
#define ENODEV 19
#define ENOTDIR 20
#define EISDIR 21
#define EINVAL 22
#define ENFILE 23
#define EMFILE 24
#define ENOTTY 25
#define ETXTBSY 26
#define EFBIG 27
#define ENOSPC 28
#define ESPIPE 29
#define EROFS 30
#define EMLINK 31
#define EPIPE 32
#define EDOM 33
#define ERANGE 34
#define EDEADLK 35
#define ENAMETOOLONG 36
#define ENOLCK 37
#define ENOSYS 38
#define ENOTEMPTY 39
#define ELOOP 40
#define EWOULDBLOCK EAGAIN
#define ENOMSG 42
#define EIDRM 43
#define ECHRNG 44
#define EL2NSYNC 45
#define EL3HLT 46
#define EL3RST 47
#define ELNRNG 48
#define EUNATCH 49
#define ENOCSI 50
#define EL2HLT 51
#define EBADE 52
#define EBADR 53
#define EXFULL 54
#define ENOANO 55
#define EBADRQC 56
#define EBADSLT 57
#define EDEADLOCK EDEADLK
#define EBFONT 59
#define ENOSTR 60
#define ENODATA 61
#define ETIME 62
#define ENOSR 63
#define ENONET 64
#define ENOPKG 65
#define EREMOTE 66
#define ENOLINK 67
#define EADV 68
#define ESRMNT 69
#define ECOMM 70
#define EPROTO 71
#define EMULTIHOP 72
#define EDOTDOT 73
#define EBADMSG 74
#define EOVERFLOW 75
#define ENOTUNIQ 76
#define EBADFD 77
#define EREMCHG 78
#define ELIBACC 79
#define ELIBBAD 80
#define ELIBSCN 81
#define ELIBMAX 82
#define ELIBEXEC 83
#define EILSEQ 84
#define ERESTART 85
#define ESTRPIPE 86
#define EUSERS 87
#define ENOTSOCK 88
#define EDESTADDRREQ 89
#define EMSGSIZE 90
#define EPROTOTYPE 91
#define ENOPROTOOPT 92
#define EPROTONOSUPPORT 93
#define ESOCKTNOSUPPORT 94
#define EOPNOTSUPP 95
#define EPFNOSUPPORT 96
#define EAFNOSUPPORT 97
#define EADDRINUSE 98
#define EADDRNOTAVAIL 99
#define ENETDOWN 100
#define ENETUNREACH 101
#define ENETRESET 102
#define ECONNABORTED 103
#define ECONNRESET 104
#define ENOBUFS 105
#define EISCONN 106
#define ENOTCONN 107
#define ESHUTDOWN 108
#define ETOOMANYREFS 109
#define ETIMEDOUT 110
#define ECONNREFUSED 111
#define EHOSTDOWN 112
#define EHOSTUNREACH 113
#define EALREADY 114
#define EINPROGRESS 115
#define ESTALE 116
#define EUCLEAN 117
#define ENOTNAM 118
#define ENAVAIL 119
#define EISNAM 120
#define EREMOTEIO 121
#define EDQUOT 122
#define ENOMEDIUM 123
#define EMEDIUMTYPE 124
#define ECANCELED 125
#define ENOKEY 126
#define EKEYEXPIRED 127
#define EKEYREVOKED 128
#define EKEYREJECTED 129
#define EOWNERDEAD 130
#define ENOTRECOVERABLE 131
#define ERFKILL 132
#define EHWPOISON 133
#define ENOTSUP EOPNOTSUPP
#define errno (*__errno_location ())
#undef __need_Emath
#define __error_t_defined 1
#undef __need_error_t
#define _SYS_PARAM_H 1
#define __undef_ARG_MAX 
#define _LINUX_PARAM_H 
#define __ASM_GENERIC_PARAM_H 
#define HZ 100
#define EXEC_PAGESIZE 4096
#define NOGROUP (-1)
#define MAXHOSTNAMELEN 64
#define NBBY CHAR_BIT
#define NGROUPS NGROUPS_MAX
#define MAXSYMLINKS 20
#define CANBSIZ MAX_CANON
#define MAXPATHLEN PATH_MAX
#define NOFILE 256
#define NCARGS 131072
#define setbit(a,i) ((a)[(i)/NBBY] |= 1<<((i)%NBBY))
#define clrbit(a,i) ((a)[(i)/NBBY] &= ~(1<<((i)%NBBY)))
#define isset(a,i) ((a)[(i)/NBBY] & (1<<((i)%NBBY)))
#define isclr(a,i) (((a)[(i)/NBBY] & (1<<((i)%NBBY))) == 0)
#define howmany(x,y) (((x) + ((y) - 1)) / (y))
#define roundup(x,y) (__builtin_constant_p (y) && powerof2 (y) ? (((x) + (y) - 1) & ~((y) - 1)) : ((((x) + ((y) - 1)) / (y)) * (y)))
#define powerof2(x) ((((x) - 1) & (x)) == 0)
#define MIN(a,b) (((a)<(b))?(a):(b))
#define MAX(a,b) (((a)>(b))?(a):(b))
#define DEV_BSIZE 512
#define SAVE_ROOT_JMPBUF(th,stmt) do if (true) { stmt; } else if (th) { } while (0)
#define EC_PUSH_TAG(ec) do { rb_execution_context_t * const _ec = (ec); struct rb_vm_tag _tag; _tag.state = TAG_NONE; _tag.tag = Qundef; _tag.prev = _ec->tag; _tag.lock_rec = rb_ec_vm_lock_rec(_ec);
#define EC_POP_TAG() _ec->tag = _tag.prev; } while (0)
#define EC_TMPPOP_TAG() _ec->tag = _tag.prev
#define EC_REPUSH_TAG() (void)(_ec->tag = &_tag)
#define VAR_FROM_MEMORY(var) (var)
#define VAR_INITIALIZED(var) ((void)&(var))
#define VAR_NOCLOBBERED(var) var
#define EC_EXEC_TAG() (ruby_setjmp(_tag.buf) ? rb_ec_tag_state(VAR_FROM_MEMORY(_ec)) : (EC_REPUSH_TAG(), 0))
#define EC_JUMP_TAG(ec,st) rb_ec_tag_jump(ec, st)
#define INTERNAL_EXCEPTION_P(exc) FIXNUM_P(exc)
#define CREF_FL_PUSHED_BY_EVAL IMEMO_FL_USER1
#define CREF_FL_OMOD_SHARED IMEMO_FL_USER2
#define CREF_FL_SINGLETON IMEMO_FL_USER3
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#define rb_ec_raised_set(ec,f) ((ec)->raised_flag |= (f))
#define rb_ec_raised_reset(ec,f) ((ec)->raised_flag &= ~(f))
#define rb_ec_raised_p(ec,f) (((ec)->raised_flag & (f)) != 0)
#define rb_ec_raised_clear(ec) ((ec)->raised_flag = 0)
#define CharNext(p) rb_char_next(p)
#define RUBY_GC_H 1
#define SET_MACHINE_STACK_END(p) __asm__ __volatile__ ("movq\t%%rsp, %0" : "=r" (*(p)))
#define RB_GC_SAVE_MACHINE_CONTEXT(th) do { FLUSH_REGISTER_WINDOWS; setjmp((th)->ec->machine.regs); SET_MACHINE_STACK_END(&(th)->ec->machine.stack_end); } while (0)
#define RUBY_MARK_FREE_DEBUG 0
#define RUBY_MARK_ENTER(msg) 
#define RUBY_MARK_LEAVE(msg) 
#define RUBY_FREE_ENTER(msg) 
#define RUBY_FREE_LEAVE(msg) 
#define RUBY_GC_INFO if(0)printf
#define RUBY_MARK_MOVABLE_UNLESS_NULL(ptr) do { VALUE markobj = (ptr); if (RTEST(markobj)) {rb_gc_mark_movable(markobj);} } while (0)
#define RUBY_MARK_UNLESS_NULL(ptr) do { VALUE markobj = (ptr); if (RTEST(markobj)) {rb_gc_mark(markobj);} } while (0)
#define RUBY_FREE_UNLESS_NULL(ptr) if(ptr){ruby_xfree(ptr);(ptr)=NULL;}
#define STACK_UPPER(x,a,b) (b)
#define STACK_GROW_DIR_DETECTION 
#define STACK_DIR_UPPER(a,b) STACK_UPPER(0, (a), (b))
#define IS_STACK_DIR_UPPER() STACK_DIR_UPPER(1,0)
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define INTERNAL_COMPILE_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define INTERNAL_CONT_H 
#define INTERNAL_ERROR_H 
#define INTERNAL_STRING_H 
#define RUBY_ENCODING_H 1
#define RUBY_INTERNAL_ENCODING_CODERANGE_H 
#pragma GCC visibility push(default)
#define ENC_CODERANGE_MASK RUBY_ENC_CODERANGE_MASK
#define ENC_CODERANGE_UNKNOWN RUBY_ENC_CODERANGE_UNKNOWN
#define ENC_CODERANGE_7BIT RUBY_ENC_CODERANGE_7BIT
#define ENC_CODERANGE_VALID RUBY_ENC_CODERANGE_VALID
#define ENC_CODERANGE_BROKEN RUBY_ENC_CODERANGE_BROKEN
#define ENC_CODERANGE_CLEAN_P(cr) RB_ENC_CODERANGE_CLEAN_P(cr)
#define ENC_CODERANGE(obj) RB_ENC_CODERANGE(obj)
#define ENC_CODERANGE_ASCIIONLY(obj) RB_ENC_CODERANGE_ASCIIONLY(obj)
#define ENC_CODERANGE_SET(obj,cr) RB_ENC_CODERANGE_SET(obj,cr)
#define ENC_CODERANGE_CLEAR(obj) RB_ENC_CODERANGE_CLEAR(obj)
#define ENC_CODERANGE_AND(a,b) RB_ENC_CODERANGE_AND(a, b)
#define ENCODING_CODERANGE_SET(obj,encindex,cr) RB_ENCODING_CODERANGE_SET(obj, encindex, cr)
#define RB_ENC_CODERANGE RB_ENC_CODERANGE
#define RB_ENC_CODERANGE_AND RB_ENC_CODERANGE_AND
#define RB_ENC_CODERANGE_ASCIIONLY RB_ENC_CODERANGE_ASCIIONLY
#define RB_ENC_CODERANGE_CLEAN_P RB_ENC_CODERANGE_CLEAN_P
#define RB_ENC_CODERANGE_CLEAR RB_ENC_CODERANGE_CLEAR
#define RB_ENC_CODERANGE_SET RB_ENC_CODERANGE_SET
#pragma GCC visibility pop
#define RUBY_INTERNAL_ENCODING_CTYPE_H 
#define ONIGMO_H 
#define ONIGMO_VERSION_MAJOR 6
#define ONIGMO_VERSION_MINOR 1
#define ONIGMO_VERSION_TEENY 3
#define ONIG_EXTERN RUBY_EXTERN
#pragma GCC visibility push(default)
#define UChar OnigUChar
#define ONIG_INFINITE_DISTANCE ~((OnigDistance )0)
#define OnigCodePointMaskWidth 3
#define OnigCodePointMask ((1<<OnigCodePointMaskWidth)-1)
#define OnigCodePointCount(n) ((n)&OnigCodePointMask)
#define OnigCaseFoldFlags(n) ((n)&~OnigCodePointMask)
#define OnigSpecialIndexShift 3
#define OnigSpecialIndexWidth 10
#define ONIGENC_CASE_UPCASE (1<<13)
#define ONIGENC_CASE_DOWNCASE (1<<14)
#define ONIGENC_CASE_TITLECASE (1<<15)
#define ONIGENC_CASE_SPECIAL_OFFSET 3
#define ONIGENC_CASE_UP_SPECIAL (1<<16)
#define ONIGENC_CASE_DOWN_SPECIAL (1<<17)
#define ONIGENC_CASE_MODIFIED (1<<18)
#define ONIGENC_CASE_FOLD (1<<19)
#define ONIGENC_CASE_FOLD_TURKISH_AZERI (1<<20)
#define ONIGENC_CASE_FOLD_LITHUANIAN (1<<21)
#define ONIGENC_CASE_ASCII_ONLY (1<<22)
#define ONIGENC_CASE_IS_TITLECASE (1<<23)
#define INTERNAL_ONIGENC_CASE_FOLD_MULTI_CHAR (1<<30)
#define ONIGENC_CASE_FOLD_MIN INTERNAL_ONIGENC_CASE_FOLD_MULTI_CHAR
#define ONIGENC_CASE_FOLD_DEFAULT OnigDefaultCaseFoldFlag
#define ONIGENC_MAX_COMP_CASE_FOLD_CODE_LEN 3
#define ONIGENC_GET_CASE_FOLD_CODES_MAX_NUM 13
#define ONIGENC_CODE_RANGE_NUM(range) ((int )range[0])
#define ONIGENC_CODE_RANGE_FROM(range,i) range[((i)*2) + 1]
#define ONIGENC_CODE_RANGE_TO(range,i) range[((i)*2) + 2]
#define ONIG_ENCODING_ASCII (&OnigEncodingASCII)
#define ONIG_ENCODING_UNDEF ((OnigEncoding )0)
#define ONIGENC_CODE_TO_MBC_MAXLEN 7
#define ONIGENC_MBC_CASE_FOLD_MAXLEN 18
#define ONIGENC_CTYPE_NEWLINE 0
#define ONIGENC_CTYPE_ALPHA 1
#define ONIGENC_CTYPE_BLANK 2
#define ONIGENC_CTYPE_CNTRL 3
#define ONIGENC_CTYPE_DIGIT 4
#define ONIGENC_CTYPE_GRAPH 5
#define ONIGENC_CTYPE_LOWER 6
#define ONIGENC_CTYPE_PRINT 7
#define ONIGENC_CTYPE_PUNCT 8
#define ONIGENC_CTYPE_SPACE 9
#define ONIGENC_CTYPE_UPPER 10
#define ONIGENC_CTYPE_XDIGIT 11
#define ONIGENC_CTYPE_WORD 12
#define ONIGENC_CTYPE_ALNUM 13
#define ONIGENC_CTYPE_ASCII 14
#define ONIGENC_MAX_STD_CTYPE ONIGENC_CTYPE_ASCII
#define ONIGENC_FLAG_NONE 0U
#define ONIGENC_FLAG_UNICODE 1U
#define onig_enc_len(enc,p,e) ONIGENC_MBC_ENC_LEN(enc, p, e)
#define ONIGENC_IS_UNDEF(enc) ((enc) == ONIG_ENCODING_UNDEF)
#define ONIGENC_IS_SINGLEBYTE(enc) (ONIGENC_MBC_MAXLEN(enc) == 1)
#define ONIGENC_IS_MBC_HEAD(enc,p,e) (ONIGENC_MBC_ENC_LEN(enc,p,e) != 1)
#define ONIGENC_IS_MBC_ASCII(p) (*(p) < 128)
#define ONIGENC_IS_CODE_ASCII(code) ((code) < 128)
#define ONIGENC_IS_MBC_WORD(enc,s,end) ONIGENC_IS_CODE_WORD(enc,ONIGENC_MBC_TO_CODE(enc,s,end))
#define ONIGENC_IS_MBC_ASCII_WORD(enc,s,end) onigenc_ascii_is_code_ctype( ONIGENC_MBC_TO_CODE(enc,s,end),ONIGENC_CTYPE_WORD,enc)
#define ONIGENC_IS_UNICODE(enc) ((enc)->flags & ONIGENC_FLAG_UNICODE)
#define ONIGENC_NAME(enc) ((enc)->name)
#define ONIGENC_MBC_CASE_FOLD(enc,flag,pp,end,buf) (enc)->mbc_case_fold(flag,(const OnigUChar** )pp,end,buf,enc)
#define ONIGENC_IS_ALLOWED_REVERSE_MATCH(enc,s,end) (enc)->is_allowed_reverse_match(s,end,enc)
#define ONIGENC_LEFT_ADJUST_CHAR_HEAD(enc,start,s,end) (enc)->left_adjust_char_head(start, s, end, enc)
#define ONIGENC_APPLY_ALL_CASE_FOLD(enc,case_fold_flag,f,arg) (enc)->apply_all_case_fold(case_fold_flag,f,arg,enc)
#define ONIGENC_GET_CASE_FOLD_CODES_BY_STR(enc,case_fold_flag,p,end,acs) (enc)->get_case_fold_codes_by_str(case_fold_flag,p,end,acs,enc)
#define ONIGENC_STEP_BACK(enc,start,s,end,n) onigenc_step_back((enc),(start),(s),(end),(n))
#define ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(n) (n)
#define ONIGENC_MBCLEN_CHARFOUND_P(r) (0 < (r))
#define ONIGENC_MBCLEN_CHARFOUND_LEN(r) (r)
#define ONIGENC_CONSTRUCT_MBCLEN_INVALID() (-1)
#define ONIGENC_MBCLEN_INVALID_P(r) ((r) == -1)
#define ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE(n) (-1-(n))
#define ONIGENC_MBCLEN_NEEDMORE_P(r) ((r) < -1)
#define ONIGENC_MBCLEN_NEEDMORE_LEN(r) (-1-(r))
#define ONIGENC_PRECISE_MBC_ENC_LEN(enc,p,e) (enc)->precise_mbc_enc_len(p,e,enc)
#define ONIGENC_MBC_ENC_LEN(enc,p,e) onigenc_mbclen_approximate(p,e,enc)
#define ONIGENC_MBC_MAXLEN(enc) ((enc)->max_enc_len)
#define ONIGENC_MBC_MAXLEN_DIST(enc) ONIGENC_MBC_MAXLEN(enc)
#define ONIGENC_MBC_MINLEN(enc) ((enc)->min_enc_len)
#define ONIGENC_IS_MBC_NEWLINE(enc,p,end) (enc)->is_mbc_newline((p),(end),enc)
#define ONIGENC_MBC_TO_CODE(enc,p,end) (enc)->mbc_to_code((p),(end),enc)
#define ONIGENC_CODE_TO_MBCLEN(enc,code) (enc)->code_to_mbclen(code,enc)
#define ONIGENC_CODE_TO_MBC(enc,code,buf) (enc)->code_to_mbc(code,buf,enc)
#define ONIGENC_PROPERTY_NAME_TO_CTYPE(enc,p,end) (enc)->property_name_to_ctype(enc,p,end)
#define ONIGENC_IS_CODE_CTYPE(enc,code,ctype) (enc)->is_code_ctype(code,ctype,enc)
#define ONIGENC_IS_CODE_NEWLINE(enc,code) ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_NEWLINE)
#define ONIGENC_IS_CODE_GRAPH(enc,code) ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_GRAPH)
#define ONIGENC_IS_CODE_PRINT(enc,code) ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_PRINT)
#define ONIGENC_IS_CODE_ALNUM(enc,code) ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_ALNUM)
#define ONIGENC_IS_CODE_ALPHA(enc,code) ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_ALPHA)
#define ONIGENC_IS_CODE_LOWER(enc,code) ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_LOWER)
#define ONIGENC_IS_CODE_UPPER(enc,code) ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_UPPER)
#define ONIGENC_IS_CODE_CNTRL(enc,code) ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_CNTRL)
#define ONIGENC_IS_CODE_PUNCT(enc,code) ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_PUNCT)
#define ONIGENC_IS_CODE_SPACE(enc,code) ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_SPACE)
#define ONIGENC_IS_CODE_BLANK(enc,code) ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_BLANK)
#define ONIGENC_IS_CODE_DIGIT(enc,code) ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_DIGIT)
#define ONIGENC_IS_CODE_XDIGIT(enc,code) ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_XDIGIT)
#define ONIGENC_IS_CODE_WORD(enc,code) ONIGENC_IS_CODE_CTYPE(enc,code,ONIGENC_CTYPE_WORD)
#define ONIGENC_GET_CTYPE_CODE_RANGE(enc,ctype,sbout,ranges) (enc)->get_ctype_code_range(ctype,sbout,ranges,enc)
#define ONIG_NREGION 4
#define ONIG_MAX_CAPTURE_GROUP_NUM 32767
#define ONIG_MAX_BACKREF_NUM 1000
#define ONIG_MAX_REPEAT_NUM 100000
#define ONIG_MAX_MULTI_BYTE_RANGES_NUM 10000
#define ONIG_MAX_ERROR_MESSAGE_LEN 90
#define ONIG_OPTION_DEFAULT ONIG_OPTION_NONE
#define ONIG_OPTION_NONE 0U
#define ONIG_OPTION_IGNORECASE 1U
#define ONIG_OPTION_EXTEND (ONIG_OPTION_IGNORECASE << 1)
#define ONIG_OPTION_MULTILINE (ONIG_OPTION_EXTEND << 1)
#define ONIG_OPTION_DOTALL ONIG_OPTION_MULTILINE
#define ONIG_OPTION_SINGLELINE (ONIG_OPTION_MULTILINE << 1)
#define ONIG_OPTION_FIND_LONGEST (ONIG_OPTION_SINGLELINE << 1)
#define ONIG_OPTION_FIND_NOT_EMPTY (ONIG_OPTION_FIND_LONGEST << 1)
#define ONIG_OPTION_NEGATE_SINGLELINE (ONIG_OPTION_FIND_NOT_EMPTY << 1)
#define ONIG_OPTION_DONT_CAPTURE_GROUP (ONIG_OPTION_NEGATE_SINGLELINE << 1)
#define ONIG_OPTION_CAPTURE_GROUP (ONIG_OPTION_DONT_CAPTURE_GROUP << 1)
#define ONIG_OPTION_NOTBOL (ONIG_OPTION_CAPTURE_GROUP << 1)
#define ONIG_OPTION_NOTEOL (ONIG_OPTION_NOTBOL << 1)
#define ONIG_OPTION_NOTBOS (ONIG_OPTION_NOTEOL << 1)
#define ONIG_OPTION_NOTEOS (ONIG_OPTION_NOTBOS << 1)
#define ONIG_OPTION_ASCII_RANGE (ONIG_OPTION_NOTEOS << 1)
#define ONIG_OPTION_POSIX_BRACKET_ALL_RANGE (ONIG_OPTION_ASCII_RANGE << 1)
#define ONIG_OPTION_WORD_BOUND_ALL_RANGE (ONIG_OPTION_POSIX_BRACKET_ALL_RANGE << 1)
#define ONIG_OPTION_NEWLINE_CRLF (ONIG_OPTION_WORD_BOUND_ALL_RANGE << 1)
#define ONIG_OPTION_MAXBIT ONIG_OPTION_NEWLINE_CRLF
#define ONIG_OPTION_ON(options,regopt) ((options) |= (regopt))
#define ONIG_OPTION_OFF(options,regopt) ((options) &= ~(regopt))
#define ONIG_IS_OPTION_ON(options,option) ((options) & (option))
#define ONIG_SYNTAX_ASIS (&OnigSyntaxASIS)
#define ONIG_SYNTAX_POSIX_BASIC (&OnigSyntaxPosixBasic)
#define ONIG_SYNTAX_POSIX_EXTENDED (&OnigSyntaxPosixExtended)
#define ONIG_SYNTAX_EMACS (&OnigSyntaxEmacs)
#define ONIG_SYNTAX_GREP (&OnigSyntaxGrep)
#define ONIG_SYNTAX_GNU_REGEX (&OnigSyntaxGnuRegex)
#define ONIG_SYNTAX_JAVA (&OnigSyntaxJava)
#define ONIG_SYNTAX_PERL58 (&OnigSyntaxPerl58)
#define ONIG_SYNTAX_PERL58_NG (&OnigSyntaxPerl58_NG)
#define ONIG_SYNTAX_PERL (&OnigSyntaxPerl)
#define ONIG_SYNTAX_RUBY (&OnigSyntaxRuby)
#define ONIG_SYNTAX_PYTHON (&OnigSyntaxPython)
#define ONIG_SYNTAX_DEFAULT OnigDefaultSyntax
#define ONIG_SYN_OP_VARIABLE_META_CHARACTERS (1U<<0)
#define ONIG_SYN_OP_DOT_ANYCHAR (1U<<1)
#define ONIG_SYN_OP_ASTERISK_ZERO_INF (1U<<2)
#define ONIG_SYN_OP_ESC_ASTERISK_ZERO_INF (1U<<3)
#define ONIG_SYN_OP_PLUS_ONE_INF (1U<<4)
#define ONIG_SYN_OP_ESC_PLUS_ONE_INF (1U<<5)
#define ONIG_SYN_OP_QMARK_ZERO_ONE (1U<<6)
#define ONIG_SYN_OP_ESC_QMARK_ZERO_ONE (1U<<7)
#define ONIG_SYN_OP_BRACE_INTERVAL (1U<<8)
#define ONIG_SYN_OP_ESC_BRACE_INTERVAL (1U<<9)
#define ONIG_SYN_OP_VBAR_ALT (1U<<10)
#define ONIG_SYN_OP_ESC_VBAR_ALT (1U<<11)
#define ONIG_SYN_OP_LPAREN_SUBEXP (1U<<12)
#define ONIG_SYN_OP_ESC_LPAREN_SUBEXP (1U<<13)
#define ONIG_SYN_OP_ESC_AZ_BUF_ANCHOR (1U<<14)
#define ONIG_SYN_OP_ESC_CAPITAL_G_BEGIN_ANCHOR (1U<<15)
#define ONIG_SYN_OP_DECIMAL_BACKREF (1U<<16)
#define ONIG_SYN_OP_BRACKET_CC (1U<<17)
#define ONIG_SYN_OP_ESC_W_WORD (1U<<18)
#define ONIG_SYN_OP_ESC_LTGT_WORD_BEGIN_END (1U<<19)
#define ONIG_SYN_OP_ESC_B_WORD_BOUND (1U<<20)
#define ONIG_SYN_OP_ESC_S_WHITE_SPACE (1U<<21)
#define ONIG_SYN_OP_ESC_D_DIGIT (1U<<22)
#define ONIG_SYN_OP_LINE_ANCHOR (1U<<23)
#define ONIG_SYN_OP_POSIX_BRACKET (1U<<24)
#define ONIG_SYN_OP_QMARK_NON_GREEDY (1U<<25)
#define ONIG_SYN_OP_ESC_CONTROL_CHARS (1U<<26)
#define ONIG_SYN_OP_ESC_C_CONTROL (1U<<27)
#define ONIG_SYN_OP_ESC_OCTAL3 (1U<<28)
#define ONIG_SYN_OP_ESC_X_HEX2 (1U<<29)
#define ONIG_SYN_OP_ESC_X_BRACE_HEX8 (1U<<30)
#define ONIG_SYN_OP_ESC_O_BRACE_OCTAL (1U<<31)
#define ONIG_SYN_OP2_ESC_CAPITAL_Q_QUOTE (1U<<0)
#define ONIG_SYN_OP2_QMARK_GROUP_EFFECT (1U<<1)
#define ONIG_SYN_OP2_OPTION_PERL (1U<<2)
#define ONIG_SYN_OP2_OPTION_RUBY (1U<<3)
#define ONIG_SYN_OP2_PLUS_POSSESSIVE_REPEAT (1U<<4)
#define ONIG_SYN_OP2_PLUS_POSSESSIVE_INTERVAL (1U<<5)
#define ONIG_SYN_OP2_CCLASS_SET_OP (1U<<6)
#define ONIG_SYN_OP2_QMARK_LT_NAMED_GROUP (1U<<7)
#define ONIG_SYN_OP2_ESC_K_NAMED_BACKREF (1U<<8)
#define ONIG_SYN_OP2_ESC_G_SUBEXP_CALL (1U<<9)
#define ONIG_SYN_OP2_ATMARK_CAPTURE_HISTORY (1U<<10)
#define ONIG_SYN_OP2_ESC_CAPITAL_C_BAR_CONTROL (1U<<11)
#define ONIG_SYN_OP2_ESC_CAPITAL_M_BAR_META (1U<<12)
#define ONIG_SYN_OP2_ESC_V_VTAB (1U<<13)
#define ONIG_SYN_OP2_ESC_U_HEX4 (1U<<14)
#define ONIG_SYN_OP2_ESC_GNU_BUF_ANCHOR (1U<<15)
#define ONIG_SYN_OP2_ESC_P_BRACE_CHAR_PROPERTY (1U<<16)
#define ONIG_SYN_OP2_ESC_P_BRACE_CIRCUMFLEX_NOT (1U<<17)
#define ONIG_SYN_OP2_ESC_H_XDIGIT (1U<<19)
#define ONIG_SYN_OP2_INEFFECTIVE_ESCAPE (1U<<20)
#define ONIG_SYN_OP2_ESC_CAPITAL_R_LINEBREAK (1U<<21)
#define ONIG_SYN_OP2_ESC_CAPITAL_X_EXTENDED_GRAPHEME_CLUSTER (1U<<22)
#define ONIG_SYN_OP2_ESC_V_VERTICAL_WHITESPACE (1U<<23)
#define ONIG_SYN_OP2_ESC_H_HORIZONTAL_WHITESPACE (1U<<24)
#define ONIG_SYN_OP2_ESC_CAPITAL_K_KEEP (1U<<25)
#define ONIG_SYN_OP2_ESC_G_BRACE_BACKREF (1U<<26)
#define ONIG_SYN_OP2_QMARK_SUBEXP_CALL (1U<<27)
#define ONIG_SYN_OP2_QMARK_VBAR_BRANCH_RESET (1U<<28)
#define ONIG_SYN_OP2_QMARK_LPAREN_CONDITION (1U<<29)
#define ONIG_SYN_OP2_QMARK_CAPITAL_P_NAMED_GROUP (1U<<30)
#define ONIG_SYN_OP2_QMARK_TILDE_ABSENT (1U<<31)
#define ONIG_SYN_CONTEXT_INDEP_ANCHORS (1U<<31)
#define ONIG_SYN_CONTEXT_INDEP_REPEAT_OPS (1U<<0)
#define ONIG_SYN_CONTEXT_INVALID_REPEAT_OPS (1U<<1)
#define ONIG_SYN_ALLOW_UNMATCHED_CLOSE_SUBEXP (1U<<2)
#define ONIG_SYN_ALLOW_INVALID_INTERVAL (1U<<3)
#define ONIG_SYN_ALLOW_INTERVAL_LOW_ABBREV (1U<<4)
#define ONIG_SYN_STRICT_CHECK_BACKREF (1U<<5)
#define ONIG_SYN_DIFFERENT_LEN_ALT_LOOK_BEHIND (1U<<6)
#define ONIG_SYN_CAPTURE_ONLY_NAMED_GROUP (1U<<7)
#define ONIG_SYN_ALLOW_MULTIPLEX_DEFINITION_NAME (1U<<8)
#define ONIG_SYN_FIXED_INTERVAL_IS_GREEDY_ONLY (1U<<9)
#define ONIG_SYN_ALLOW_MULTIPLEX_DEFINITION_NAME_CALL (1U<<10)
#define ONIG_SYN_USE_LEFT_MOST_NAMED_GROUP (1U<<11)
#define ONIG_SYN_NOT_NEWLINE_IN_NEGATIVE_CC (1U<<20)
#define ONIG_SYN_BACKSLASH_ESCAPE_IN_CC (1U<<21)
#define ONIG_SYN_ALLOW_EMPTY_RANGE_IN_CC (1U<<22)
#define ONIG_SYN_ALLOW_DOUBLE_RANGE_OP_IN_CC (1U<<23)
#define ONIG_SYN_WARN_CC_OP_NOT_ESCAPED (1U<<24)
#define ONIG_SYN_WARN_REDUNDANT_NESTED_REPEAT (1U<<25)
#define ONIG_SYN_WARN_CC_DUP (1U<<26)
#define ONIG_META_CHAR_ESCAPE 0
#define ONIG_META_CHAR_ANYCHAR 1
#define ONIG_META_CHAR_ANYTIME 2
#define ONIG_META_CHAR_ZERO_OR_ONE_TIME 3
#define ONIG_META_CHAR_ONE_OR_MORE_TIME 4
#define ONIG_META_CHAR_ANYCHAR_ANYTIME 5
#define ONIG_INEFFECTIVE_META_CHAR 0
#define ONIG_IS_PATTERN_ERROR(ecode) ((ecode) <= -100 && (ecode) > -1000)
#define ONIG_NORMAL 0
#define ONIG_MISMATCH -1
#define ONIG_NO_SUPPORT_CONFIG -2
#define ONIGERR_MEMORY -5
#define ONIGERR_TYPE_BUG -6
#define ONIGERR_PARSER_BUG -11
#define ONIGERR_STACK_BUG -12
#define ONIGERR_UNDEFINED_BYTECODE -13
#define ONIGERR_UNEXPECTED_BYTECODE -14
#define ONIGERR_MATCH_STACK_LIMIT_OVER -15
#define ONIGERR_PARSE_DEPTH_LIMIT_OVER -16
#define ONIGERR_DEFAULT_ENCODING_IS_NOT_SET -21
#define ONIGERR_SPECIFIED_ENCODING_CANT_CONVERT_TO_WIDE_CHAR -22
#define ONIGERR_INVALID_ARGUMENT -30
#define ONIGERR_END_PATTERN_AT_LEFT_BRACE -100
#define ONIGERR_END_PATTERN_AT_LEFT_BRACKET -101
#define ONIGERR_EMPTY_CHAR_CLASS -102
#define ONIGERR_PREMATURE_END_OF_CHAR_CLASS -103
#define ONIGERR_END_PATTERN_AT_ESCAPE -104
#define ONIGERR_END_PATTERN_AT_META -105
#define ONIGERR_END_PATTERN_AT_CONTROL -106
#define ONIGERR_META_CODE_SYNTAX -108
#define ONIGERR_CONTROL_CODE_SYNTAX -109
#define ONIGERR_CHAR_CLASS_VALUE_AT_END_OF_RANGE -110
#define ONIGERR_CHAR_CLASS_VALUE_AT_START_OF_RANGE -111
#define ONIGERR_UNMATCHED_RANGE_SPECIFIER_IN_CHAR_CLASS -112
#define ONIGERR_TARGET_OF_REPEAT_OPERATOR_NOT_SPECIFIED -113
#define ONIGERR_TARGET_OF_REPEAT_OPERATOR_INVALID -114
#define ONIGERR_NESTED_REPEAT_OPERATOR -115
#define ONIGERR_UNMATCHED_CLOSE_PARENTHESIS -116
#define ONIGERR_END_PATTERN_WITH_UNMATCHED_PARENTHESIS -117
#define ONIGERR_END_PATTERN_IN_GROUP -118
#define ONIGERR_UNDEFINED_GROUP_OPTION -119
#define ONIGERR_INVALID_POSIX_BRACKET_TYPE -121
#define ONIGERR_INVALID_LOOK_BEHIND_PATTERN -122
#define ONIGERR_INVALID_REPEAT_RANGE_PATTERN -123
#define ONIGERR_INVALID_CONDITION_PATTERN -124
#define ONIGERR_TOO_BIG_NUMBER -200
#define ONIGERR_TOO_BIG_NUMBER_FOR_REPEAT_RANGE -201
#define ONIGERR_UPPER_SMALLER_THAN_LOWER_IN_REPEAT_RANGE -202
#define ONIGERR_EMPTY_RANGE_IN_CHAR_CLASS -203
#define ONIGERR_MISMATCH_CODE_LENGTH_IN_CLASS_RANGE -204
#define ONIGERR_TOO_MANY_MULTI_BYTE_RANGES -205
#define ONIGERR_TOO_SHORT_MULTI_BYTE_STRING -206
#define ONIGERR_TOO_BIG_BACKREF_NUMBER -207
#define ONIGERR_INVALID_BACKREF -208
#define ONIGERR_NUMBERED_BACKREF_OR_CALL_NOT_ALLOWED -209
#define ONIGERR_TOO_MANY_CAPTURE_GROUPS -210
#define ONIGERR_TOO_SHORT_DIGITS -211
#define ONIGERR_TOO_LONG_WIDE_CHAR_VALUE -212
#define ONIGERR_EMPTY_GROUP_NAME -214
#define ONIGERR_INVALID_GROUP_NAME -215
#define ONIGERR_INVALID_CHAR_IN_GROUP_NAME -216
#define ONIGERR_UNDEFINED_NAME_REFERENCE -217
#define ONIGERR_UNDEFINED_GROUP_REFERENCE -218
#define ONIGERR_MULTIPLEX_DEFINED_NAME -219
#define ONIGERR_MULTIPLEX_DEFINITION_NAME_CALL -220
#define ONIGERR_NEVER_ENDING_RECURSION -221
#define ONIGERR_GROUP_NUMBER_OVER_FOR_CAPTURE_HISTORY -222
#define ONIGERR_INVALID_CHAR_PROPERTY_NAME -223
#define ONIGERR_INVALID_CODE_POINT_VALUE -400
#define ONIGERR_INVALID_WIDE_CHAR_VALUE -400
#define ONIGERR_TOO_BIG_WIDE_CHAR_VALUE -401
#define ONIGERR_NOT_SUPPORTED_ENCODING_COMBINATION -402
#define ONIGERR_INVALID_COMBINATION_OF_OPTIONS -403
#define ONIG_MAX_CAPTURE_HISTORY_GROUP 31
#define ONIG_IS_CAPTURE_HISTORY_GROUP(r,i) ((i) <= ONIG_MAX_CAPTURE_HISTORY_GROUP && (r)->list && (r)->list[i])
#define ONIG_TRAVERSE_CALLBACK_AT_FIRST 1
#define ONIG_TRAVERSE_CALLBACK_AT_LAST 2
#define ONIG_TRAVERSE_CALLBACK_AT_BOTH ( ONIG_TRAVERSE_CALLBACK_AT_FIRST | ONIG_TRAVERSE_CALLBACK_AT_LAST )
#define ONIG_REGION_NOTPOS -1
#define ONIG_NULL_WARN onig_null_warn
#define ONIG_CHAR_TABLE_SIZE 256
#pragma GCC visibility pop
#define RUBY_INTERNAL_ENCODING_ENCODING_H 
#define ONIGURUMA_H 
#define ONIGURUMA 
#define ONIGURUMA_VERSION_MAJOR ONIGMO_VERSION_MAJOR
#define ONIGURUMA_VERSION_MINOR ONIGMO_VERSION_MINOR
#define ONIGURUMA_VERSION_TEENY ONIGMO_VERSION_TEENY
#pragma GCC visibility push(default)
#define ENCODING_INLINE_MAX RUBY_ENCODING_INLINE_MAX
#define ENCODING_SHIFT RUBY_ENCODING_SHIFT
#define ENCODING_MASK RUBY_ENCODING_MASK
#define ENCODING_SET_INLINED(obj,i) RB_ENCODING_SET_INLINED(obj,i)
#define ENCODING_SET(obj,i) RB_ENCODING_SET(obj,i)
#define ENCODING_GET_INLINED(obj) RB_ENCODING_GET_INLINED(obj)
#define ENCODING_GET(obj) RB_ENCODING_GET(obj)
#define ENCODING_IS_ASCII8BIT(obj) RB_ENCODING_IS_ASCII8BIT(obj)
#define ENCODING_MAXNAMELEN RUBY_ENCODING_MAXNAMELEN
#define MBCLEN_CHARFOUND_P(ret) ONIGENC_MBCLEN_CHARFOUND_P(ret)
#define MBCLEN_CHARFOUND_LEN(ret) ONIGENC_MBCLEN_CHARFOUND_LEN(ret)
#define MBCLEN_INVALID_P(ret) ONIGENC_MBCLEN_INVALID_P(ret)
#define MBCLEN_NEEDMORE_P(ret) ONIGENC_MBCLEN_NEEDMORE_P(ret)
#define MBCLEN_NEEDMORE_LEN(ret) ONIGENC_MBCLEN_NEEDMORE_LEN(ret)
#pragma GCC visibility pop
#define RB_ENCODING_GET RB_ENCODING_GET
#define RB_ENCODING_GET_INLINED RB_ENCODING_GET_INLINED
#define RB_ENCODING_IS_ASCII8BIT RB_ENCODING_IS_ASCII8BIT
#define RB_ENCODING_SET RB_ENCODING_SET
#define RB_ENCODING_SET_INLINED RB_ENCODING_SET_INLINED
#define rb_enc_asciicompat rb_enc_asciicompat
#define rb_enc_code_to_mbclen rb_enc_code_to_mbclen
#define rb_enc_codepoint rb_enc_codepoint
#define rb_enc_left_char_head rb_enc_left_char_head
#define rb_enc_mbc_to_codepoint rb_enc_mbc_to_codepoint
#define rb_enc_mbcput rb_enc_mbcput
#define rb_enc_mbmaxlen rb_enc_mbmaxlen
#define rb_enc_mbminlen rb_enc_mbminlen
#define rb_enc_name rb_enc_name
#define rb_enc_prev_char rb_enc_prev_char
#define rb_enc_right_char_head rb_enc_right_char_head
#define rb_enc_step_back rb_enc_step_back
#define rb_enc_str_asciicompat_p rb_enc_str_asciicompat_p
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define rb_enc_is_newline rb_enc_is_newline
#define rb_enc_isalnum rb_enc_isalnum
#define rb_enc_isalpha rb_enc_isalpha
#define rb_enc_isascii rb_enc_isascii
#define rb_enc_isctype rb_enc_isctype
#define rb_enc_isdigit rb_enc_isdigit
#define rb_enc_islower rb_enc_islower
#define rb_enc_isprint rb_enc_isprint
#define rb_enc_ispunct rb_enc_ispunct
#define rb_enc_isspace rb_enc_isspace
#define rb_enc_isupper rb_enc_isupper
#define RUBY_INTERNAL_ENCODING_PATHNAME_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RUBY_INTERNAL_ENCODING_RE_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RUBY_INTERNAL_ENCODING_SPRINTF_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RUBY_INTERNAL_ENCODING_STRING_H 
#pragma GCC visibility push(default)
#define rb_enc_str_new(str,len,enc) ((RBIMPL_CONSTANT_P(str) && RBIMPL_CONSTANT_P(len) ? rb_enc_str_new_static: rb_enc_str_new) ((str), (len), (enc)))
#define rb_enc_str_new_cstr(str,enc) ((RBIMPL_CONSTANT_P(str) ? rbimpl_enc_str_new_cstr : rb_enc_str_new_cstr) ((str), (enc)))
#pragma GCC visibility pop
#define RUBY_INTERNAL_ENCODING_SYMBOL_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RUBY_INTERNAL_ENCODING_TRANSCODE_H 
#pragma GCC visibility push(default)
#define ECONV_ERROR_HANDLER_MASK RUBY_ECONV_ERROR_HANDLER_MASK
#define ECONV_INVALID_MASK RUBY_ECONV_INVALID_MASK
#define ECONV_INVALID_REPLACE RUBY_ECONV_INVALID_REPLACE
#define ECONV_UNDEF_MASK RUBY_ECONV_UNDEF_MASK
#define ECONV_UNDEF_REPLACE RUBY_ECONV_UNDEF_REPLACE
#define ECONV_UNDEF_HEX_CHARREF RUBY_ECONV_UNDEF_HEX_CHARREF
#define ECONV_DECORATOR_MASK RUBY_ECONV_DECORATOR_MASK
#define ECONV_NEWLINE_DECORATOR_MASK RUBY_ECONV_NEWLINE_DECORATOR_MASK
#define ECONV_NEWLINE_DECORATOR_READ_MASK RUBY_ECONV_NEWLINE_DECORATOR_READ_MASK
#define ECONV_NEWLINE_DECORATOR_WRITE_MASK RUBY_ECONV_NEWLINE_DECORATOR_WRITE_MASK
#define ECONV_UNIVERSAL_NEWLINE_DECORATOR RUBY_ECONV_UNIVERSAL_NEWLINE_DECORATOR
#define ECONV_CRLF_NEWLINE_DECORATOR RUBY_ECONV_CRLF_NEWLINE_DECORATOR
#define ECONV_CR_NEWLINE_DECORATOR RUBY_ECONV_CR_NEWLINE_DECORATOR
#define ECONV_XML_TEXT_DECORATOR RUBY_ECONV_XML_TEXT_DECORATOR
#define ECONV_XML_ATTR_CONTENT_DECORATOR RUBY_ECONV_XML_ATTR_CONTENT_DECORATOR
#define ECONV_STATEFUL_DECORATOR_MASK RUBY_ECONV_STATEFUL_DECORATOR_MASK
#define ECONV_XML_ATTR_QUOTE_DECORATOR RUBY_ECONV_XML_ATTR_QUOTE_DECORATOR
#define ECONV_DEFAULT_NEWLINE_DECORATOR RUBY_ECONV_DEFAULT_NEWLINE_DECORATOR
#define ECONV_PARTIAL_INPUT RUBY_ECONV_PARTIAL_INPUT
#define ECONV_AFTER_OUTPUT RUBY_ECONV_AFTER_OUTPUT
#pragma GCC visibility pop
#define STR_NOEMBED FL_USER1
#define STR_SHARED FL_USER2
#undef rb_fstring_cstr
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define rb_fstring_lit(str) rb_fstring_new((str), rb_strlen_lit(str))
#define rb_fstring_literal(str) rb_fstring_lit(str)
#define rb_fstring_enc_lit(str,enc) rb_fstring_enc_new((str), rb_strlen_lit(str), (enc))
#define rb_fstring_enc_literal(str,enc) rb_fstring_enc_lit(str, enc)
#define rb_fstring_cstr(str) (__builtin_constant_p(str) ? rb_fstring_new((str), (long)strlen(str)) : (rb_fstring_cstr)(str))
#undef Check_Type
#define rb_raise_static(e,m) rb_raise_cstr_i((e), rb_str_new_static((m), rb_strlen_lit(m)))
#define rb_sys_fail_path(path) rb_sys_fail_path_in(RUBY_FUNCTION_NAME_STRING, path)
#define rb_syserr_fail_path(err,path) rb_syserr_fail_path_in(RUBY_FUNCTION_NAME_STRING, (err), (path))
#define rb_syserr_new_path(err,path) rb_syserr_new_path_in(RUBY_FUNCTION_NAME_STRING, (err), (path))
#define rb_warn_deprecated_to_remove_at(removal,...) rb_warn_deprecated_to_remove(#removal, __VA_ARGS__)
#define RUBY_VERSION_SINCE(major,minor) 0
#define RUBY_VERSION_BEFORE(major,minor) 0
#define RBIMPL_TODO0(x) 
#define RBIMPL_TODO(message) RBIMPL_TODO0("TODO: " message)
#define rb_typeddata_is_instance_of rb_typeddata_is_instance_of_inline
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define INTERNAL_EVAL_H 
#define id_signo ruby_static_id_signo
#define id_status ruby_static_id_status
#define INTERNAL_INITS_H 
#define INTERNAL_OBJECT_H 
#define INTERNAL_CLASS_H 
#define RUBY_ID_TABLE_H 1
#define RCLASS_EXT(c) (RCLASS(c)->ptr)
#define RCLASS_IV_TBL(c) (RCLASS_EXT(c)->iv_tbl)
#define RCLASS_CONST_TBL(c) (RCLASS_EXT(c)->const_tbl)
#define RCLASS_M_TBL(c) (RCLASS_EXT(c)->m_tbl)
#define RCLASS_CALLABLE_M_TBL(c) (RCLASS_EXT(c)->callable_m_tbl)
#define RCLASS_CC_TBL(c) (RCLASS_EXT(c)->cc_tbl)
#define RCLASS_CVC_TBL(c) (RCLASS_EXT(c)->cvc_tbl)
#define RCLASS_IV_INDEX_TBL(c) (RCLASS_EXT(c)->iv_index_tbl)
#define RCLASS_ORIGIN(c) (RCLASS_EXT(c)->origin_)
#define RCLASS_REFINED_CLASS(c) (RCLASS_EXT(c)->refined_class)
#define RCLASS_SERIAL(c) (RCLASS(c)->class_serial)
#define RCLASS_INCLUDER(c) (RCLASS_EXT(c)->includer)
#define RCLASS_SUBCLASS_ENTRY(c) (RCLASS_EXT(c)->subclass_entry)
#define RCLASS_MODULE_SUBCLASS_ENTRY(c) (RCLASS_EXT(c)->module_subclass_entry)
#define RCLASS_ALLOCATOR(c) (RCLASS_EXT(c)->allocator)
#define RCLASS_SUBCLASSES(c) (RCLASS_EXT(c)->subclasses)
#define RICLASS_IS_ORIGIN FL_USER5
#define RCLASS_CLONED FL_USER6
#define RICLASS_ORIGIN_SHARED_MTBL FL_USER8
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define ROBJECT_IV_INDEX_TBL ROBJECT_IV_INDEX_TBL_inline
#define INTERNAL_PARSE_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define INTERNAL_PROC_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define INTERNAL_RE_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define INTERNAL_SYMBOL_H 
#undef rb_sym_intern_ascii_cstr
#define rb_sym_intern_ascii_cstr(ptr) (__builtin_constant_p(ptr) ? rb_sym_intern_ascii((ptr), (long)strlen(ptr)) : rb_sym_intern_ascii_cstr(ptr))
#define INTERNAL_THREAD_H 
#define COVERAGE_INDEX_LINES 0
#define COVERAGE_INDEX_BRANCHES 1
#define COVERAGE_TARGET_LINES 1
#define COVERAGE_TARGET_BRANCHES 2
#define COVERAGE_TARGET_METHODS 4
#define COVERAGE_TARGET_ONESHOT_LINES 8
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define INTERNAL_SANITIZERS_H 
#define SANITIZER_ASAN_INTERFACE_H 
#define SANITIZER_COMMON_INTERFACE_DEFS_H 
#define ASAN_POISON_MEMORY_REGION(addr,size) ((void)(addr), (void)(size))
#define ASAN_UNPOISON_MEMORY_REGION(addr,size) ((void)(addr), (void)(size))
#define ATTRIBUTE_NO_ADDRESS_SAFETY_ANALYSIS(x) NO_SANITIZE_ADDRESS(NOINLINE(x))
#undef NO_SANITIZE
#define NO_SANITIZE(x,y) COMPILER_WARNING_PUSH; COMPILER_WARNING_IGNORED(-Wattributes); __attribute__((__no_sanitize__(x))) y; COMPILER_WARNING_POP
#define __asan_poison_memory_region(x,y) 
#define __asan_unpoison_memory_region(x,y) 
#define __asan_region_is_poisoned(x,y) 0
#define __msan_allocated_memory(x,y) ((void)(x), (void)(y))
#define __msan_poison(x,y) ((void)(x), (void)(y))
#define __msan_unpoison(x,y) ((void)(x), (void)(y))
#define __msan_unpoison_string(x) ((void)(x))
#define VALGRIND_MAKE_MEM_DEFINED(p,n) 0
#define VALGRIND_MAKE_MEM_UNDEFINED(p,n) 0
#define RUBY_ISEQ_H 1
#define ISEQ_MAJOR_VERSION ((unsigned int)ruby_api_version[0])
#define ISEQ_MINOR_VERSION ((unsigned int)ruby_api_version[1])
#define USE_ISEQ_NODE_ID 1
#define ISEQ_COVERAGE(iseq) iseq->body->variable.coverage
#define ISEQ_COVERAGE_SET(iseq,cov) RB_OBJ_WRITE(iseq, &iseq->body->variable.coverage, cov)
#define ISEQ_LINE_COVERAGE(iseq) RARRAY_AREF(ISEQ_COVERAGE(iseq), COVERAGE_INDEX_LINES)
#define ISEQ_BRANCH_COVERAGE(iseq) RARRAY_AREF(ISEQ_COVERAGE(iseq), COVERAGE_INDEX_BRANCHES)
#define ISEQ_PC2BRANCHINDEX(iseq) iseq->body->variable.pc2branchindex
#define ISEQ_PC2BRANCHINDEX_SET(iseq,h) RB_OBJ_WRITE(iseq, &iseq->body->variable.pc2branchindex, h)
#define ISEQ_FLIP_CNT(iseq) (iseq)->body->variable.flip_count
#define ISEQ_TRACE_EVENTS (RUBY_EVENT_LINE | RUBY_EVENT_CLASS | RUBY_EVENT_END | RUBY_EVENT_CALL | RUBY_EVENT_RETURN| RUBY_EVENT_C_CALL| RUBY_EVENT_C_RETURN| RUBY_EVENT_B_CALL| RUBY_EVENT_B_RETURN| RUBY_EVENT_COVERAGE_LINE| RUBY_EVENT_COVERAGE_BRANCH)
#define ISEQ_NOT_LOADED_YET IMEMO_FL_USER1
#define ISEQ_USE_COMPILE_DATA IMEMO_FL_USER2
#define ISEQ_TRANSLATED IMEMO_FL_USER3
#define ISEQ_MARKABLE_ISEQ IMEMO_FL_USER4
#define ISEQ_EXECUTABLE_P(iseq) (FL_TEST_RAW(((VALUE)iseq), ISEQ_NOT_LOADED_YET | ISEQ_USE_COMPILE_DATA) == 0)
#pragma GCC visibility push(default)
#define INITIAL_ISEQ_COMPILE_DATA_STORAGE_BUFF_SIZE (512)
#pragma GCC visibility pop
#define RUBY_MJIT_H 1
#define USE_DEBUG_COUNTER 0
#define RUBY_DEBUG_COUNTER_H 1
#define RB_DEBUG_COUNTER(name) RB_DEBUG_COUNTER_ ##name,
#undef RB_DEBUG_COUNTER
#define RB_DEBUG_COUNTER_INC(type) ((void)0)
#define RB_DEBUG_COUNTER_INC_UNLESS(type,cond) (!!(cond))
#define RB_DEBUG_COUNTER_INC_IF(type,cond) (!!(cond))
#define RB_DEBUG_COUNTER_ADD(type,num) ((void)0)
#define RB_DEBUG_COUNTER_SETMAX(type,num) 0
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RUBY_H 1
#define HAVE_RUBY_ATOMIC_H 1
#define HAVE_RUBY_DEBUG_H 1
#define HAVE_RUBY_DEFINES_H 1
#define HAVE_RUBY_ENCODING_H 1
#define HAVE_RUBY_FIBER_SCHEDULER_H 1
#define HAVE_RUBY_INTERN_H 1
#define HAVE_RUBY_IO_H 1
#define HAVE_RUBY_MEMORY_VIEW_H 1
#define HAVE_RUBY_MISSING_H 1
#define HAVE_RUBY_ONIGMO_H 1
#define HAVE_RUBY_ONIGURUMA_H 1
#define HAVE_RUBY_RACTOR_H 1
#define HAVE_RUBY_RANDOM_H 1
#define HAVE_RUBY_RE_H 1
#define HAVE_RUBY_REGEX_H 1
#define HAVE_RUBY_RUBY_H 1
#define HAVE_RUBY_ST_H 1
#define HAVE_RUBY_THREAD_H 1
#define HAVE_RUBY_THREAD_NATIVE_H 1
#define HAVE_RUBY_UTIL_H 1
#define HAVE_RUBY_VERSION_H 1
#define HAVE_RUBY_VM_H 1
#define YJIT_H 1
#define YJIT_STATS RUBY_DEBUG
#define YJIT_SUPPORTED_P 1
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define mjit_enabled true
#define RUBY_VM_H 1
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RUBY_VM_CALLINFO_H 
#define VM_CALL_ARGS_SPLAT (0x01 << VM_CALL_ARGS_SPLAT_bit)
#define VM_CALL_ARGS_BLOCKARG (0x01 << VM_CALL_ARGS_BLOCKARG_bit)
#define VM_CALL_FCALL (0x01 << VM_CALL_FCALL_bit)
#define VM_CALL_VCALL (0x01 << VM_CALL_VCALL_bit)
#define VM_CALL_ARGS_SIMPLE (0x01 << VM_CALL_ARGS_SIMPLE_bit)
#define VM_CALL_BLOCKISEQ (0x01 << VM_CALL_BLOCKISEQ_bit)
#define VM_CALL_KWARG (0x01 << VM_CALL_KWARG_bit)
#define VM_CALL_KW_SPLAT (0x01 << VM_CALL_KW_SPLAT_bit)
#define VM_CALL_TAILCALL (0x01 << VM_CALL_TAILCALL_bit)
#define VM_CALL_SUPER (0x01 << VM_CALL_SUPER_bit)
#define VM_CALL_ZSUPER (0x01 << VM_CALL_ZSUPER_bit)
#define VM_CALL_OPT_SEND (0x01 << VM_CALL_OPT_SEND_bit)
#define VM_CALL_KW_SPLAT_MUT (0x01 << VM_CALL_KW_SPLAT_MUT_bit)
#define USE_EMBED_CI 1
#define CI_EMBED_TAG_bits 1
#define CI_EMBED_ARGC_bits 15
#define CI_EMBED_FLAG_bits 16
#define CI_EMBED_ID_bits 32
#define CI_EMBED_FLAG 0x01
#define CI_EMBED_ARGC_SHFT (CI_EMBED_TAG_bits)
#define CI_EMBED_ARGC_MASK ((((VALUE)1)<<CI_EMBED_ARGC_bits) - 1)
#define CI_EMBED_FLAG_SHFT (CI_EMBED_TAG_bits + CI_EMBED_ARGC_bits)
#define CI_EMBED_FLAG_MASK ((((VALUE)1)<<CI_EMBED_FLAG_bits) - 1)
#define CI_EMBED_ID_SHFT (CI_EMBED_TAG_bits + CI_EMBED_ARGC_bits + CI_EMBED_FLAG_bits)
#define CI_EMBED_ID_MASK ((((VALUE)1)<<CI_EMBED_ID_bits) - 1)
#define vm_ci_new(mid,flag,argc,kwarg) vm_ci_new_(mid, flag, argc, kwarg, __FILE__, __LINE__)
#define vm_ci_new_runtime(mid,flag,argc,kwarg) vm_ci_new_runtime_(mid, flag, argc, kwarg, __FILE__, __LINE__)
#define VM_CI_EMBEDDABLE_P(mid,flag,argc,kwarg) (((mid ) & ~CI_EMBED_ID_MASK) ? false : ((flag) & ~CI_EMBED_FLAG_MASK) ? false : ((argc) & ~CI_EMBED_ARGC_MASK) ? false : (kwarg) ? false : true)
#define vm_ci_new_id(mid,flag,argc,must_zero) ((const struct rb_callinfo *) ((((VALUE)(mid )) << CI_EMBED_ID_SHFT) | (((VALUE)(flag)) << CI_EMBED_FLAG_SHFT) | (((VALUE)(argc)) << CI_EMBED_ARGC_SHFT) | RUBY_FIXNUM_FLAG))
#define VM_CALLINFO_NOT_UNDER_GC IMEMO_FL_USER0
#define VM_CI_ON_STACK(mid_,flags_,argc_,kwarg_) (struct rb_callinfo) { .flags = T_IMEMO | (imemo_callinfo << FL_USHIFT) | VM_CALLINFO_NOT_UNDER_GC, .mid = mid_, .flag = flags_, .argc = argc_, .kwarg = kwarg_, }
#define VM_CALLCACHE_UNMARKABLE IMEMO_FL_USER0
#define VM_CALLCACHE_ON_STACK IMEMO_FL_USER1
#define VM_CC_ON_STACK(clazz,call,aux,cme) (struct rb_callcache) { .flags = T_IMEMO | (imemo_callcache << FL_USHIFT) | VM_CALLCACHE_UNMARKABLE | VM_CALLCACHE_ON_STACK, .klass = clazz, .cme_ = cme, .call_ = call, .aux_ = aux, }
#define vm_cc_empty() rb_vm_empty_cc()
#define RUBY_DEBUG_H 
#pragma GCC visibility push(default)
#define dpv(h,v) ruby_debug_print_value(-1, 0, (h), (v))
#define dp(v) ruby_debug_print_value(-1, 0, "", (v))
#define dpi(i) ruby_debug_print_id(-1, 0, "", (i))
#define dpn(n) ruby_debug_print_node(-1, 0, "", (n))
#pragma GCC visibility pop
#define RUBY_DEVEL 0
#define _RUBY_DEBUG_LOG(...) ruby_debug_log(__FILE__, __LINE__, RUBY_FUNCTION_NAME_STRING, "" __VA_ARGS__)
#define RUBY_DEBUG_LOG(...) 
#define RUBY_DEBUG_LOG2(file,line,...) 
#define RUBY_VM_EXEC_H 
#define debugs 
#define DEBUG_ENTER_INSN(insn) 
#define DEBUG_END_INSN() 
#define throwdebug if(0)ruby_debug_printf
#define USE_INSNS_COUNTER 0
#define LABEL(x) INSN_LABEL_ ##x
#define ELABEL(x) INSN_ELABEL_ ##x
#define LABEL_PTR(x) RB_GNUC_EXTENSION(&&LABEL(x))
#define INSN_ENTRY_SIG(insn) if (0) { ruby_debug_printf("exec: %s@(%"PRIdPTRDIFF", %"PRIdPTRDIFF")@%s:%u\n", #insn, (reg_pc - reg_cfp->iseq->body->iseq_encoded), (reg_cfp->pc - reg_cfp->iseq->body->iseq_encoded), RSTRING_PTR(rb_iseq_path(reg_cfp->iseq)), rb_iseq_line_no(reg_cfp->iseq, reg_pc - reg_cfp->iseq->body->iseq_encoded)); } if (USE_INSNS_COUNTER) vm_insns_counter_count_insn(BIN(insn));
#define INSN_DISPATCH_SIG(insn) 
#define INSN_ENTRY(insn) LABEL(insn): INSN_ENTRY_SIG(insn);
#define TC_DISPATCH(insn) INSN_DISPATCH_SIG(insn); RB_GNUC_EXTENSION_BLOCK(goto *(void const *)GET_CURRENT_INSN()); ;
#define END_INSN(insn) DEBUG_END_INSN(); TC_DISPATCH(insn);
#define INSN_DISPATCH() TC_DISPATCH(__START__) {
#define END_INSNS_DISPATCH() rb_bug("unknown insn: %"PRIdVALUE, GET_CURRENT_INSN()); }
#define NEXT_INSN() TC_DISPATCH(__NEXT_INSN__)
#define START_OF_ORIGINAL_INSN(x) if (0) goto start_of_ ##x; start_of_ ##x:
#define DISPATCH_ORIGINAL_INSN(x) goto start_of_ ##x;
#define VM_SP_CNT(ec,sp) ((sp) - (ec)->vm_stack)
#define THROW_EXCEPTION(exc) do { ec->errinfo = (VALUE)(exc); EC_JUMP_TAG(ec, ec->tag->state); } while (0)
#define SCREG(r) (reg_ ##r)
#define VM_DEBUG_STACKOVERFLOW 0
#define CHECK_VM_STACK_OVERFLOW_FOR_INSN(cfp,margin) 
#define INSN_LABEL2(insn,name) INSN_LABEL_ ## insn ## _ ## name
#define INSN_LABEL(x) INSN_LABEL2(NAME_OF_CURRENT_INSN, x)
#define RUBY_INSNHELPER_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define COLLECT_USAGE_INSN(insn) 
#define COLLECT_USAGE_OPERAND(insn,n,op) 
#define COLLECT_USAGE_REGISTER(reg,s) 
#define PUSH(x) (SET_SV(x), INC_SP(1))
#define TOPN(n) (*(GET_SP()-(n)-1))
#define POPN(n) (DEC_SP(n))
#define POP() (DEC_SP(1))
#define STACK_ADDR_FROM_TOP(n) (GET_SP()-(n))
#define VM_REG_CFP (reg_cfp)
#define VM_REG_PC (VM_REG_CFP->pc)
#define VM_REG_SP (VM_REG_CFP->sp)
#define VM_REG_EP (VM_REG_CFP->ep)
#define RESTORE_REGS() do { VM_REG_CFP = ec->cfp; } while (0)
#define COLLECT_USAGE_REGISTER_HELPER(a,b,v) (v)
#define GET_PC() (COLLECT_USAGE_REGISTER_HELPER(PC, GET, VM_REG_PC))
#define SET_PC(x) (VM_REG_PC = (COLLECT_USAGE_REGISTER_HELPER(PC, SET, (x))))
#define GET_CURRENT_INSN() (*GET_PC())
#define GET_OPERAND(n) (GET_PC()[(n)])
#define ADD_PC(n) (SET_PC(VM_REG_PC + (n)))
#define JUMP(dst) (SET_PC(VM_REG_PC + (dst)))
#define GET_CFP() (COLLECT_USAGE_REGISTER_HELPER(CFP, GET, VM_REG_CFP))
#define GET_EP() (COLLECT_USAGE_REGISTER_HELPER(EP, GET, VM_REG_EP))
#define SET_EP(x) (VM_REG_EP = (COLLECT_USAGE_REGISTER_HELPER(EP, SET, (x))))
#define GET_LEP() (VM_EP_LEP(GET_EP()))
#define GET_SP() (COLLECT_USAGE_REGISTER_HELPER(SP, GET, VM_REG_SP))
#define SET_SP(x) (VM_REG_SP = (COLLECT_USAGE_REGISTER_HELPER(SP, SET, (x))))
#define INC_SP(x) (VM_REG_SP += (COLLECT_USAGE_REGISTER_HELPER(SP, SET, (x))))
#define DEC_SP(x) (VM_REG_SP -= (COLLECT_USAGE_REGISTER_HELPER(SP, SET, (x))))
#define SET_SV(x) (*GET_SP() = rb_ractor_confirm_belonging(x))
#define GET_ISEQ() (GET_CFP()->iseq)
#define GET_PREV_EP(ep) ((VALUE *)((ep)[VM_ENV_DATA_INDEX_SPECVAL] & ~0x03))
#define GET_SELF() (COLLECT_USAGE_REGISTER_HELPER(SELF, GET, GET_CFP()->self))
#define GET_BLOCK_HANDLER() (GET_LEP()[VM_ENV_DATA_INDEX_SPECVAL])
#define SETUP_CANARY(cond) if (cond) {} else {}
#define CHECK_CANARY(cond,insn) if (cond) {(void)(insn);}
#define PREV_CLASS_SERIAL() (ruby_vm_class_serial)
#define NEXT_CLASS_SERIAL() (++ruby_vm_class_serial)
#define GET_GLOBAL_CONSTANT_STATE() (ruby_vm_global_constant_state)
#define INC_GLOBAL_CONSTANT_STATE() (++ruby_vm_global_constant_state)
#define GET_GLOBAL_CVAR_STATE() (ruby_vm_global_cvar_state)
#define INC_GLOBAL_CVAR_STATE() (++ruby_vm_global_cvar_state)
#define IS_ARGS_SPLAT(ci) (vm_ci_flag(ci) & VM_CALL_ARGS_SPLAT)
#define IS_ARGS_KEYWORD(ci) (vm_ci_flag(ci) & VM_CALL_KWARG)
#define IS_ARGS_KW_SPLAT(ci) (vm_ci_flag(ci) & VM_CALL_KW_SPLAT)
#define IS_ARGS_KW_OR_KW_SPLAT(ci) (vm_ci_flag(ci) & (VM_CALL_KWARG | VM_CALL_KW_SPLAT))
#define IS_ARGS_KW_SPLAT_MUT(ci) (vm_ci_flag(ci) & VM_CALL_KW_SPLAT_MUT)
#define RUBY_RACTOR_H 1
#pragma GCC visibility push(default)
#define RB_RACTOR_LOCAL_STORAGE_TYPE_FREE (&rb_ractor_local_storage_type_free)
#pragma GCC visibility pop
#define RB_OBJ_SHAREABLE_P(obj) FL_TEST_RAW((obj), RUBY_FL_SHAREABLE)
#define RACTOR_CHECK_MODE (0 || VM_CHECK_MODE || RUBY_DEBUG)
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define rb_ractor_confirm_belonging(obj) obj
#define RUBY_VM_SYNC_H 
#define LOCATION_ARGS void
#define LOCATION_PARAMS 
#define APPEND_LOCATION_ARGS 
#define APPEND_LOCATION_PARAMS 
#define RB_VM_LOCKED_P() rb_vm_locked_p()
#define RB_VM_LOCK() rb_vm_lock(__FILE__, __LINE__)
#define RB_VM_UNLOCK() rb_vm_unlock(__FILE__, __LINE__)
#define RB_VM_LOCK_ENTER_CR_LEV(cr,levp) rb_vm_lock_enter_cr(cr, levp, __FILE__, __LINE__)
#define RB_VM_LOCK_LEAVE_CR_LEV(cr,levp) rb_vm_lock_leave_cr(cr, levp, __FILE__, __LINE__)
#define RB_VM_LOCK_ENTER_LEV(levp) rb_vm_lock_enter(levp, __FILE__, __LINE__)
#define RB_VM_LOCK_LEAVE_LEV(levp) rb_vm_lock_leave(levp, __FILE__, __LINE__)
#define RB_VM_LOCK_ENTER() { unsigned int _lev; RB_VM_LOCK_ENTER_LEV(&_lev);
#define RB_VM_LOCK_LEAVE() RB_VM_LOCK_LEAVE_LEV(&_lev); }
#define RB_VM_LOCK_ENTER_LEV_NB(levp) rb_vm_lock_enter_nb(levp, __FILE__, __LINE__)
#define RB_VM_LOCK_ENTER_NO_BARRIER() { unsigned int _lev; RB_VM_LOCK_ENTER_LEV_NB(&_lev);
#define RB_VM_LOCK_LEAVE_NO_BARRIER() RB_VM_LOCK_LEAVE_LEV(&_lev); }
#define ASSERT_vm_locking() 
#define ASSERT_vm_unlocking() 
#define BUILTIN_H_INCLUDED 
#define RB_BUILTIN_FUNCTION(_i,_name,_fname,_arity,_compiler) { .name = #_name, .func_ptr = (void *)_fname, .argc = _arity, .index = _i, .compiler = _compiler, }
#define _PROBES_H 
#define DTRACE_PROBES_DISABLED 1
#define RUBY_DTRACE_METHOD_ENTRY_ENABLED() 0
#define RUBY_DTRACE_METHOD_ENTRY(classname,methodname,filename,lineno) do {} while (0)
#define RUBY_DTRACE_METHOD_RETURN_ENABLED() 0
#define RUBY_DTRACE_METHOD_RETURN(classname,methodname,filename,lineno) do {} while (0)
#define RUBY_DTRACE_CMETHOD_ENTRY_ENABLED() 0
#define RUBY_DTRACE_CMETHOD_ENTRY(classname,methodname,filename,lineno) do {} while (0)
#define RUBY_DTRACE_CMETHOD_RETURN_ENABLED() 0
#define RUBY_DTRACE_CMETHOD_RETURN(classname,methodname,filename,lineno) do {} while (0)
#define RUBY_DTRACE_REQUIRE_ENTRY_ENABLED() 0
#define RUBY_DTRACE_REQUIRE_ENTRY(rquiredfile,filename,lineno) do {} while (0)
#define RUBY_DTRACE_REQUIRE_RETURN_ENABLED() 0
#define RUBY_DTRACE_REQUIRE_RETURN(requiredfile,filename,lineno) do {} while (0)
#define RUBY_DTRACE_FIND_REQUIRE_ENTRY_ENABLED() 0
#define RUBY_DTRACE_FIND_REQUIRE_ENTRY(requiredfile,filename,lineno) do {} while (0)
#define RUBY_DTRACE_FIND_REQUIRE_RETURN_ENABLED() 0
#define RUBY_DTRACE_FIND_REQUIRE_RETURN(requiredfile,filename,lineno) do {} while (0)
#define RUBY_DTRACE_LOAD_ENTRY_ENABLED() 0
#define RUBY_DTRACE_LOAD_ENTRY(loadedfile,filename,lineno) do {} while (0)
#define RUBY_DTRACE_LOAD_RETURN_ENABLED() 0
#define RUBY_DTRACE_LOAD_RETURN(loadedfile,filename,lineno) do {} while (0)
#define RUBY_DTRACE_RAISE_ENABLED() 0
#define RUBY_DTRACE_RAISE(classname,filename,lineno) do {} while (0)
#define RUBY_DTRACE_OBJECT_CREATE_ENABLED() 0
#define RUBY_DTRACE_OBJECT_CREATE(classname,filename,lineno) do {} while (0)
#define RUBY_DTRACE_ARRAY_CREATE_ENABLED() 0
#define RUBY_DTRACE_ARRAY_CREATE(length,filename,lineno) do {} while (0)
#define RUBY_DTRACE_HASH_CREATE_ENABLED() 0
#define RUBY_DTRACE_HASH_CREATE(length,filename,lineno) do {} while (0)
#define RUBY_DTRACE_STRING_CREATE_ENABLED() 0
#define RUBY_DTRACE_STRING_CREATE(length,filename,lineno) do {} while (0)
#define RUBY_DTRACE_SYMBOL_CREATE_ENABLED() 0
#define RUBY_DTRACE_SYMBOL_CREATE(str,filename,lineno) do {} while (0)
#define RUBY_DTRACE_PARSE_BEGIN_ENABLED() 0
#define RUBY_DTRACE_PARSE_BEGIN(sourcefile,lineno) do {} while (0)
#define RUBY_DTRACE_PARSE_END_ENABLED() 0
#define RUBY_DTRACE_PARSE_END(sourcefile,lineno) do {} while (0)
#define RUBY_DTRACE_INSN_ENABLED() 0
#define RUBY_DTRACE_INSN(insns_name) do {} while (0)
#define RUBY_DTRACE_INSN_OPERAND_ENABLED() 0
#define RUBY_DTRACE_INSN_OPERAND(val,insns_name) do {} while (0)
#define RUBY_DTRACE_GC_MARK_BEGIN_ENABLED() 0
#define RUBY_DTRACE_GC_MARK_BEGIN() do {} while (0)
#define RUBY_DTRACE_GC_MARK_END_ENABLED() 0
#define RUBY_DTRACE_GC_MARK_END() do {} while (0)
#define RUBY_DTRACE_GC_SWEEP_BEGIN_ENABLED() 0
#define RUBY_DTRACE_GC_SWEEP_BEGIN() do {} while (0)
#define RUBY_DTRACE_GC_SWEEP_END_ENABLED() 0
#define RUBY_DTRACE_GC_SWEEP_END() do {} while (0)
#define RUBY_PROBES_HELPER_H 
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define RUBY_DTRACE_METHOD_HOOK(name,ec,klazz,id) do { if (UNLIKELY(RUBY_DTRACE_ ##name ##_ENABLED())) { struct ruby_dtrace_method_hook_args args; if (rb_dtrace_setup(ec, klazz, id, &args)) { RUBY_DTRACE_ ##name(args.classname, args.methodname, args.filename, args.line_no); } } } while (0)
#define RUBY_DTRACE_METHOD_ENTRY_HOOK(ec,klass,id) RUBY_DTRACE_METHOD_HOOK(METHOD_ENTRY, ec, klass, id)
#define RUBY_DTRACE_METHOD_RETURN_HOOK(ec,klass,id) RUBY_DTRACE_METHOD_HOOK(METHOD_RETURN, ec, klass, id)
#define RUBY_DTRACE_CMETHOD_ENTRY_HOOK(ec,klass,id) RUBY_DTRACE_METHOD_HOOK(CMETHOD_ENTRY, ec, klass, id)
#define RUBY_DTRACE_CMETHOD_RETURN_HOOK(ec,klass,id) RUBY_DTRACE_METHOD_HOOK(CMETHOD_RETURN, ec, klass, id)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#define CONSTANT_H 
#define RB_CONST_PRIVATE_P(ce) (((ce)->flag & CONST_VISIBILITY_MASK) == CONST_PRIVATE)
#define RB_CONST_PUBLIC_P(ce) (((ce)->flag & CONST_VISIBILITY_MASK) == CONST_PUBLIC)
#define RB_CONST_DEPRECATED_P(ce) ((ce)->flag & CONST_DEPRECATED)
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define INTERNAL_COMPAR_H 
#define STRING_P(s) (RB_TYPE_P((s), T_STRING) && CLASS_OF(s) == rb_cString)
#define NEW_CMP_OPT_MEMO(type,value) NEW_PARTIAL_MEMO_FOR(type, value, cmp_opt)
#define CMP_OPTIMIZABLE_BIT(type) (1U << TOKEN_PASTE(cmp_opt_,type))
#define CMP_OPTIMIZABLE(data,type) (((data).opt_inited & CMP_OPTIMIZABLE_BIT(type)) ? ((data).opt_methods & CMP_OPTIMIZABLE_BIT(type)) : (((data).opt_inited |= CMP_OPTIMIZABLE_BIT(type)), rb_method_basic_definition_p(TOKEN_PASTE(rb_c,type), id_cmp) && ((data).opt_methods |= CMP_OPTIMIZABLE_BIT(type))))
#define OPTIMIZED_CMP(a,b,data) ((FIXNUM_P(a) && FIXNUM_P(b) && CMP_OPTIMIZABLE(data, Integer)) ? (((long)a > (long)b) ? 1 : ((long)a < (long)b) ? -1 : 0) : (STRING_P(a) && STRING_P(b) && CMP_OPTIMIZABLE(data, String)) ? rb_str_cmp(a, b) : (RB_FLOAT_TYPE_P(a) && RB_FLOAT_TYPE_P(b) && CMP_OPTIMIZABLE(data, Float)) ? rb_float_cmp(a, b) : rb_cmpint(rb_funcallv(a, id_cmp, 1, &b), a, b))
#define INTERNAL_HASH_H 
#define RHASH_AR_TABLE_MAX_SIZE SIZEOF_VALUE
#define RHASH_LEV_MASK (FL_USER13 | FL_USER14 | FL_USER15 | FL_USER16 | FL_USER17 | FL_USER18 | FL_USER19)
#define RHASH(obj) ((struct RHash *)(obj))
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#pragma GCC visibility push(default)
#define RHASH_TBL_RAW(h) rb_hash_tbl_raw(h, __FILE__, __LINE__)
#pragma GCC visibility pop
#define INTERNAL_NUMERIC_H 
#define INTERNAL_BIGNUM_H 
#define BDIGIT unsigned int
#define SIZEOF_BDIGIT SIZEOF_INT
#define BDIGIT_DBL unsigned LONG_LONG
#define BDIGIT_DBL_SIGNED LONG_LONG
#define PRI_BDIGIT_PREFIX ""
#define PRI_BDIGIT_DBL_PREFIX PRI_LL_PREFIX
#define SIZEOF_ACTUAL_BDIGIT SIZEOF_BDIGIT
#define PRIdBDIGIT PRI_BDIGIT_PREFIX"d"
#define PRIiBDIGIT PRI_BDIGIT_PREFIX"i"
#define PRIoBDIGIT PRI_BDIGIT_PREFIX"o"
#define PRIuBDIGIT PRI_BDIGIT_PREFIX"u"
#define PRIxBDIGIT PRI_BDIGIT_PREFIX"x"
#define PRIXBDIGIT PRI_BDIGIT_PREFIX"X"
#define PRIdBDIGIT_DBL PRI_BDIGIT_DBL_PREFIX"d"
#define PRIiBDIGIT_DBL PRI_BDIGIT_DBL_PREFIX"i"
#define PRIoBDIGIT_DBL PRI_BDIGIT_DBL_PREFIX"o"
#define PRIuBDIGIT_DBL PRI_BDIGIT_DBL_PREFIX"u"
#define PRIxBDIGIT_DBL PRI_BDIGIT_DBL_PREFIX"x"
#define PRIXBDIGIT_DBL PRI_BDIGIT_DBL_PREFIX"X"
#define RBIGNUM(obj) ((struct RBignum *)(obj))
#define BIGNUM_SIGN_BIT FL_USER1
#define BIGNUM_EMBED_FLAG ((VALUE)FL_USER2)
#define BIGNUM_EMBED_LEN_NUMBITS 3
#define BIGNUM_EMBED_LEN_MASK (~(~(VALUE)0U << BIGNUM_EMBED_LEN_NUMBITS) << BIGNUM_EMBED_LEN_SHIFT)
#define BIGNUM_EMBED_LEN_SHIFT (FL_USHIFT+3)
#define BIGNUM_EMBED_LEN_MAX (SIZEOF_VALUE*RBIMPL_RVALUE_EMBED_LEN_MAX/SIZEOF_ACTUAL_BDIGIT)
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define INTERNAL_BITS_H 
#define HALF_LONG_MSB ((SIGNED_VALUE)1<<((SIZEOF_LONG*CHAR_BIT-1)/2))
#define SIGNED_INTEGER_TYPE_P(T) (0 > ((T)0)-1)
#define SIGNED_INTEGER_MIN(T) ((sizeof(T) == sizeof(int8_t)) ? ((T)INT8_MIN) : ((sizeof(T) == sizeof(int16_t)) ? ((T)INT16_MIN) : ((sizeof(T) == sizeof(int32_t)) ? ((T)INT32_MIN) : ((sizeof(T) == sizeof(int64_t)) ? ((T)INT64_MIN) : 0))))
#define SIGNED_INTEGER_MAX(T) ((T)(SIGNED_INTEGER_MIN(T) ^ ((T)~(T)0)))
#define UNSIGNED_INTEGER_MAX(T) ((T)~(T)0)
#define MUL_OVERFLOW_P(a,b) __builtin_mul_overflow_p((a), (b), (__typeof__(a * b))0)
#define MUL_OVERFLOW_SIGNED_INTEGER_P(a,b,min,max) ( (a) == 0 ? 0 : (a) == -1 ? (b) < -(max) : (a) > 0 ? ((b) > 0 ? (max) / (a) < (b) : (min) / (a) > (b)) : ((b) > 0 ? (min) / (a) < (b) : (max) / (a) > (b)))
#define MUL_OVERFLOW_FIXNUM_P(a,b) __extension__ ({ struct { long fixnum : sizeof(long) * CHAR_BIT - 1; } c = { 0 }; __builtin_mul_overflow_p((a), (b), c.fixnum); })
#define MUL_OVERFLOW_LONG_LONG_P(a,b) MUL_OVERFLOW_P(a, b)
#define MUL_OVERFLOW_LONG_P(a,b) MUL_OVERFLOW_P(a, b)
#define MUL_OVERFLOW_INT_P(a,b) MUL_OVERFLOW_P(a, b)
#define bit_length(x) (unsigned int) (sizeof(x) <= sizeof(int32_t) ? 32 - nlz_int32((uint32_t)(x)) : sizeof(x) <= sizeof(int64_t) ? 64 - nlz_int64((uint64_t)(x)) : 128 - nlz_int128((uint128_t)(x)))
#define swap16 ruby_swap16
#define swap32 ruby_swap32
#define swap64 ruby_swap64
#define INTERNAL_FIXNUM_H 
#define DLONG int128_t
#define DL2NUM(x) (RB_FIXABLE(x) ? LONG2FIX(x) : rb_int128t2big(x))
#define ROUND_TO(mode,even,up,down) ((mode) == RUBY_NUM_ROUND_HALF_EVEN ? even : (mode) == RUBY_NUM_ROUND_HALF_UP ? up : down)
#define ROUND_FUNC(mode,name) ROUND_TO(mode, name ##_half_even, name ##_half_up, name ##_half_down)
#define ROUND_CALL(mode,name,args) ROUND_TO(mode, name ##_half_even args, name ##_half_up args, name ##_half_down args)
#define ROUND_DEFAULT RUBY_NUM_ROUND_HALF_UP
#define RFLOAT(obj) ((struct RFloat *)(obj))
#define rb_float_value rb_float_value_inline
#define rb_float_new rb_float_new_inline
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define INTERNAL_RANDOM_H 
#define INTERNAL_VARIABLE_H 
#define ROBJECT_TRANSIENT_FLAG FL_USER13
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#pragma GCC visibility push(default)
#pragma GCC visibility pop
#define INTERNAL_STRUCT_H 
#define RSTRUCT(obj) ((struct RStruct *)(obj))
#define RSTRUCT_LEN internal_RSTRUCT_LEN
#define RSTRUCT_SET internal_RSTRUCT_SET
#define RSTRUCT_GET internal_RSTRUCT_GET
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#define RUBY_TOPLEVEL_VARIABLE_H 
#define BIN(n) YARVINSN_ ##n
#define ASSERT_VM_INSTRUCTION_SIZE(array) STATIC_ASSERT(numberof_ ##array, numberof(array) == VM_INSTRUCTION_SIZE)
#define vm_check_canary(ec,sp) 
#define vm_check_frame(a,b,c,d) 
#define vm_push_frame_debug_counter_inc(ec,cfp,t) 
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#define EQ_UNREDEFINED_P(t) BASIC_OP_UNREDEFINED_P(BOP_EQ, t ##_REDEFINED_OP_FLAG)
#undef EQ_UNREDEFINED_P
#define CHECK_CMP_NAN(a,b) 
#define KW_SPECIFIED_BITS_MAX (32-1)
#define USE_OPT_HIST 0
#define CHECK_CFP_CONSISTENCY(func) (LIKELY(vm_cfp_consistent_p(ec, reg_cfp)) ? (void)0 : rb_bug(func ": cfp consistency error (%p, %p)", (void *)reg_cfp, (void *)(ec->cfp+1)))
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#define VM_CALL_METHOD_ATTR(var,func,nohook) if (UNLIKELY(ruby_vm_event_flags & (RUBY_EVENT_C_CALL | RUBY_EVENT_C_RETURN))) { EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_CALL, calling->recv, vm_cc_cme(cc)->def->original_id, vm_ci_mid(ci), vm_cc_cme(cc)->owner, Qundef); var = func; EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_RETURN, calling->recv, vm_cc_cme(cc)->def->original_id, vm_ci_mid(ci), vm_cc_cme(cc)->owner, (var)); } else { nohook; var = func; }
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#define mexp_search_method vm_search_method_wrap
#define mexp_search_super vm_search_super_method
#define mexp_search_invokeblock vm_search_invokeblock
#define id_cmp idCmp
#undef id_cmp
#define IMEMO_CONST_CACHE_SHAREABLE IMEMO_FL_USER0
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Waddress-of-packed-member"
#pragma GCC diagnostic pop
#define VM_TRACE_HOOK(target_event,val) do { if ((pc_events & (target_event)) & enabled_flags) { vm_trace_hook(ec, reg_cfp, pc, pc_events, (target_event), global_hooks, local_hooks, (val)); } } while (0)
#undef VM_TRACE_HOOK
#define id_mesg idMesg
