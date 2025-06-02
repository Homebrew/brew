/*
 * Suggested reading order:
 * 1. Skim Init_bootsnap
 * 2. Skim bs_fetch
 * 3. The rest of everything
 *
 * Init_bootsnap sets up the ruby objects and binds bs_fetch to
 * Bootsnap::CompileCache::Native.fetch.
 *
 * bs_fetch is the ultimate caller for for just about every other function in
 * here.
 */

#include "bootsnap.h"
#include "ruby.h"
#include <stdint.h>
#include <stdbool.h>
#include <sys/types.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

#ifdef __APPLE__
  // The symbol is present, however not in the headers
  // See: https://github.com/Shopify/bootsnap/issues/470
  extern int fdatasync(int);
#endif

#ifndef O_NOATIME
#define O_NOATIME 0
#endif

/* 1000 is an arbitrary limit; FNV64 plus some slashes brings the cap down to
 * 981 for the cache dir */
#define MAX_CACHEPATH_SIZE 1000
#define MAX_CACHEDIR_SIZE  981

#define KEY_SIZE 64

#define MAX_CREATE_TEMPFILE_ATTEMPT 3

#ifndef RB_UNLIKELY
#define RB_UNLIKELY(x) (x)
#endif

/*
 * An instance of this key is written as the first 64 bytes of each cache file.
 * The mtime and size members track whether the file contents have changed, and
 * the version, ruby_platform, compile_option, and ruby_revision members track
 * changes to the environment that could invalidate compile results without
 * file contents having changed. The data_size member is not truly part of the
 * "key". Really, this could be called a "header" with the first six members
 * being an embedded "key" struct and an additional data_size member.
 *
 * The data_size indicates the remaining number of bytes in the cache file
 * after the header (the size of the cached artifact).
 *
 * After data_size, the struct is padded to 64 bytes.
 */
struct bs_cache_key {
  uint32_t version;
  uint32_t ruby_platform;
  uint32_t compile_option;
  uint32_t ruby_revision;
  uint64_t size;
  uint64_t mtime;
  uint64_t data_size; //
  uint64_t digest;
  uint8_t digest_set;
  uint8_t pad[15];
} __attribute__((packed));

/*
 * If the struct padding isn't correct to pad the key to 64 bytes, refuse to
 * compile.
 */
#define STATIC_ASSERT(X)            STATIC_ASSERT2(X,__LINE__)
#define STATIC_ASSERT2(X,L)         STATIC_ASSERT3(X,L)
#define STATIC_ASSERT3(X,L)         STATIC_ASSERT_MSG(X,at_line_##L)
#define STATIC_ASSERT_MSG(COND,MSG) typedef char static_assertion_##MSG[(!!(COND))*2-1]
STATIC_ASSERT(sizeof(struct bs_cache_key) == KEY_SIZE);

/* Effectively a schema version. Bumping invalidates all previous caches */
static const uint32_t current_version = 6;

/* hash of e.g. "x86_64-darwin17", invalidating when ruby is recompiled on a
 * new OS ABI, etc. */
static uint32_t current_ruby_platform;
/* Invalidates cache when switching ruby versions */
static uint32_t current_ruby_revision;
/* Invalidates cache when RubyVM::InstructionSequence.compile_option changes */
static uint32_t current_compile_option_crc32 = 0;
/* Current umask */
static mode_t current_umask;

/* Bootsnap::CompileCache::{Native, Uncompilable} */
static VALUE rb_mBootsnap;
static VALUE rb_mBootsnap_CompileCache;
static VALUE rb_mBootsnap_CompileCache_Native;
static VALUE rb_cBootsnap_CompileCache_UNCOMPILABLE;
static ID instrumentation_method;
static VALUE sym_hit, sym_miss, sym_stale, sym_revalidated;
static bool instrumentation_enabled = false;
static bool readonly = false;
static bool revalidation = false;
static bool perm_issue = false;

/* Functions exposed as module functions on Bootsnap::CompileCache::Native */
static VALUE bs_instrumentation_enabled_set(VALUE self, VALUE enabled);
static VALUE bs_readonly_set(VALUE self, VALUE enabled);
static VALUE bs_revalidation_set(VALUE self, VALUE enabled);
static VALUE bs_compile_option_crc32_set(VALUE self, VALUE crc32_v);
static VALUE bs_rb_fetch(VALUE self, VALUE cachedir_v, VALUE path_v, VALUE handler, VALUE args);
static VALUE bs_rb_precompile(VALUE self, VALUE cachedir_v, VALUE path_v, VALUE handler);

/* Helpers */
enum cache_status {
  miss,
  hit,
  stale,
};
static void bs_cache_path(const char * cachedir, const VALUE path, char (* cache_path)[MAX_CACHEPATH_SIZE]);
static int bs_read_key(int fd, struct bs_cache_key * key);
static enum cache_status cache_key_equal_fast_path(struct bs_cache_key * k1, struct bs_cache_key * k2);
static int cache_key_equal_slow_path(struct bs_cache_key * current_key, struct bs_cache_key * cached_key, const VALUE input_data);
static int update_cache_key(struct bs_cache_key *current_key, struct bs_cache_key *old_key, int cache_fd, const char ** errno_provenance);

static void bs_cache_key_digest(struct bs_cache_key * key, const VALUE input_data);
static VALUE bs_fetch(char * path, VALUE path_v, char * cache_path, VALUE handler, VALUE args);
static VALUE bs_precompile(char * path, VALUE path_v, char * cache_path, VALUE handler);
static int open_current_file(const char * path, struct bs_cache_key * key, const char ** errno_provenance);
static int fetch_cached_data(int fd, ssize_t data_size, VALUE handler, VALUE args, VALUE * output_data, int * exception_tag, const char ** errno_provenance);
static uint32_t get_ruby_revision(void);
static uint32_t get_ruby_platform(void);

/*
 * Helper functions to call ruby methods on handler object without crashing on
 * exception.
 */
static int bs_storage_to_output(VALUE handler, VALUE args, VALUE storage_data, VALUE * output_data);
static VALUE prot_input_to_output(VALUE arg);
static void bs_input_to_output(VALUE handler, VALUE args, VALUE input_data, VALUE * output_data, int * exception_tag);
static int bs_input_to_storage(VALUE handler, VALUE args, VALUE input_data, VALUE pathval, VALUE * storage_data);
struct s2o_data;
struct i2o_data;
struct i2s_data;

static VALUE
bs_rb_get_path(VALUE self, VALUE fname)
{
    return rb_get_path(fname);
}

/*
 * Ruby C extensions are initialized by calling Init_<extname>.
 *
 * This sets up the module hierarchy and attaches functions as methods.
 *
 * We also populate some semi-static information about the current OS and so on.
 */
void
Init_bootsnap(void)
{
  rb_mBootsnap = rb_define_module("Bootsnap");

  rb_define_singleton_method(rb_mBootsnap, "rb_get_path", bs_rb_get_path, 1);

  rb_mBootsnap_CompileCache = rb_define_module_under(rb_mBootsnap, "CompileCache");
  rb_mBootsnap_CompileCache_Native = rb_define_module_under(rb_mBootsnap_CompileCache, "Native");
  rb_cBootsnap_CompileCache_UNCOMPILABLE = rb_const_get(rb_mBootsnap_CompileCache, rb_intern("UNCOMPILABLE"));
  rb_global_variable(&rb_cBootsnap_CompileCache_UNCOMPILABLE);

  current_ruby_revision = get_ruby_revision();
  current_ruby_platform = get_ruby_platform();

  instrumentation_method = rb_intern("_instrument");

  sym_hit = ID2SYM(rb_intern("hit"));
  sym_miss = ID2SYM(rb_intern("miss"));
  sym_stale = ID2SYM(rb_intern("stale"));
  sym_revalidated = ID2SYM(rb_intern("revalidated"));

  rb_define_module_function(rb_mBootsnap, "instrumentation_enabled=", bs_instrumentation_enabled_set, 1);
  rb_define_module_function(rb_mBootsnap_CompileCache_Native, "readonly=", bs_readonly_set, 1);
  rb_define_module_function(rb_mBootsnap_CompileCache_Native, "revalidation=", bs_revalidation_set, 1);
  rb_define_module_function(rb_mBootsnap_CompileCache_Native, "fetch", bs_rb_fetch, 4);
  rb_define_module_function(rb_mBootsnap_CompileCache_Native, "precompile", bs_rb_precompile, 3);
  rb_define_module_function(rb_mBootsnap_CompileCache_Native, "compile_option_crc32=", bs_compile_option_crc32_set, 1);

  current_umask = umask(0777);
  umask(current_umask);
}

static VALUE
bs_instrumentation_enabled_set(VALUE self, VALUE enabled)
{
  instrumentation_enabled = RTEST(enabled);
  return enabled;
}

static inline void
bs_instrumentation(VALUE event, VALUE path)
{
    if (RB_UNLIKELY(instrumentation_enabled)) {
       rb_funcall(rb_mBootsnap, instrumentation_method, 2, event, path);
    }
}

static VALUE
bs_readonly_set(VALUE self, VALUE enabled)
{
  readonly = RTEST(enabled);
  return enabled;
}

static VALUE
bs_revalidation_set(VALUE self, VALUE enabled)
{
  revalidation = RTEST(enabled);
  return enabled;
}

/*
 * Bootsnap's ruby code registers a hook that notifies us via this function
 * when compile_option changes. These changes invalidate all existing caches.
 *
 * Note that on 32-bit platforms, a CRC32 can't be represented in a Fixnum, but
 * can be represented by a uint.
 */
static VALUE
bs_compile_option_crc32_set(VALUE self, VALUE crc32_v)
{
  if (!RB_TYPE_P(crc32_v, T_BIGNUM) && !RB_TYPE_P(crc32_v, T_FIXNUM)) {
    Check_Type(crc32_v, T_FIXNUM);
  }
  current_compile_option_crc32 = NUM2UINT(crc32_v);
  return Qnil;
}

static uint64_t
fnv1a_64_iter(uint64_t h, const VALUE str)
{
  unsigned char *s = (unsigned char *)RSTRING_PTR(str);
  unsigned char *str_end = (unsigned char *)RSTRING_PTR(str) + RSTRING_LEN(str);

  while (s < str_end) {
    h ^= (uint64_t)*s++;
    h += (h << 1) + (h << 4) + (h << 5) + (h << 7) + (h << 8) + (h << 40);
  }

  return h;
}

static uint64_t
fnv1a_64(const VALUE str)
{
  uint64_t h = (uint64_t)0xcbf29ce484222325ULL;
  return fnv1a_64_iter(h, str);
}

/*
 * Ruby's revision may be Integer or String. CRuby 2.7 or later uses
 * Git commit ID as revision. It's String.
 */
static uint32_t
get_ruby_revision(void)
{
  VALUE ruby_revision;

  ruby_revision = rb_const_get(rb_cObject, rb_intern("RUBY_REVISION"));
  if (RB_TYPE_P(ruby_revision, RUBY_T_FIXNUM)) {
    return FIX2INT(ruby_revision);
  } else {
    uint64_t hash;

    hash = fnv1a_64(ruby_revision);
    return (uint32_t)(hash >> 32);
  }
}

/*
 * When ruby's version doesn't change, but it's recompiled on a different OS
 * (or OS version), we need to invalidate the cache.
 */
static uint32_t
get_ruby_platform(void)
{
  uint64_t hash;
  VALUE ruby_platform;

  ruby_platform = rb_const_get(rb_cObject, rb_intern("RUBY_PLATFORM"));
  hash = fnv1a_64(ruby_platform);
  return (uint32_t)(hash >> 32);
}

/*
 * Given a cache root directory and the full path to a file being cached,
 * generate a path under the cache directory at which the cached artifact will
 * be stored.
 *
 * The path will look something like: <cachedir>/12/34567890abcdef
 */
static void
bs_cache_path(const char * cachedir, const VALUE path, char (* cache_path)[MAX_CACHEPATH_SIZE])
{
  uint64_t hash = fnv1a_64(path);
  uint8_t first_byte = (hash >> (64 - 8));
  uint64_t remainder = hash & 0x00ffffffffffffff;

  sprintf(*cache_path, "%s/%02"PRIx8"/%014"PRIx64, cachedir, first_byte, remainder);
}

/*
 * Test whether a newly-generated cache key based on the file as it exists on
 * disk matches the one that was generated when the file was cached (or really
 * compare any two keys).
 *
 * The data_size member is not compared, as it serves more of a "header"
 * function.
 */
static enum cache_status cache_key_equal_fast_path(struct bs_cache_key *k1,
                                     struct bs_cache_key *k2) {
  if (k1->version == k2->version &&
          k1->ruby_platform == k2->ruby_platform &&
          k1->compile_option == k2->compile_option &&
          k1->ruby_revision == k2->ruby_revision && k1->size == k2->size) {
      if (k1->mtime == k2->mtime) {
        return hit;
      }
      if (revalidation) {
        return stale;
      }
  }
  return miss;
}

static int cache_key_equal_slow_path(struct bs_cache_key *current_key,
                                     struct bs_cache_key *cached_key,
                                     const VALUE input_data)
{
  bs_cache_key_digest(current_key, input_data);
  return current_key->digest == cached_key->digest;
}

static int update_cache_key(struct bs_cache_key *current_key, struct bs_cache_key *old_key, int cache_fd, const char ** errno_provenance)
{
  old_key->mtime = current_key->mtime;
  lseek(cache_fd, 0, SEEK_SET);
  ssize_t nwrite = write(cache_fd, old_key, KEY_SIZE);
  if (nwrite < 0) {
      *errno_provenance = "update_cache_key:write";
      return -1;
  }

#ifdef HAVE_FDATASYNC
  if (fdatasync(cache_fd) < 0) {
      *errno_provenance = "update_cache_key:fdatasync";
      return -1;
  }
#endif

  return 0;
}

/*
 * Fills the cache key digest.
 */
static void bs_cache_key_digest(struct bs_cache_key *key,
                                const VALUE input_data) {
  if (key->digest_set)
    return;
  key->digest = fnv1a_64(input_data);
  key->digest_set = 1;
}

/*
 * Entrypoint for Bootsnap::CompileCache::Native.fetch. The real work is done
 * in bs_fetch; this function just performs some basic typechecks and
 * conversions on the ruby VALUE arguments before passing them along.
 */
static VALUE
bs_rb_fetch(VALUE self, VALUE cachedir_v, VALUE path_v, VALUE handler, VALUE args)
{
  FilePathValue(path_v);

  Check_Type(cachedir_v, T_STRING);
  Check_Type(path_v, T_STRING);

  if (RSTRING_LEN(cachedir_v) > MAX_CACHEDIR_SIZE) {
    rb_raise(rb_eArgError, "cachedir too long");
  }

  char * cachedir = RSTRING_PTR(cachedir_v);
  char * path     = RSTRING_PTR(path_v);
  char cache_path[MAX_CACHEPATH_SIZE];

  /* generate cache path to cache_path */
  bs_cache_path(cachedir, path_v, &cache_path);

  return bs_fetch(path, path_v, cache_path, handler, args);
}

/*
 * Entrypoint for Bootsnap::CompileCache::Native.precompile.
 * Similar to fetch, but it only generate the cache if missing
 * and doesn't return the content.
 */
static VALUE
bs_rb_precompile(VALUE self, VALUE cachedir_v, VALUE path_v, VALUE handler)
{
  FilePathValue(path_v);

  Check_Type(cachedir_v, T_STRING);
  Check_Type(path_v, T_STRING);

  if (RSTRING_LEN(cachedir_v) > MAX_CACHEDIR_SIZE) {
    rb_raise(rb_eArgError, "cachedir too long");
  }

  char * cachedir = RSTRING_PTR(cachedir_v);
  char * path     = RSTRING_PTR(path_v);
  char cache_path[MAX_CACHEPATH_SIZE];

  /* generate cache path to cache_path */
  bs_cache_path(cachedir, path_v, &cache_path);

  return bs_precompile(path, path_v, cache_path, handler);
}

static int bs_open_noatime(const char *path, int flags) {
  int fd = 1;
  if (!perm_issue) {
    fd = open(path, flags | O_NOATIME);
    if (fd < 0 && errno == EPERM) {
      errno = 0;
      perm_issue = true;
    }
  }

  if (perm_issue) {
    fd = open(path, flags);
  }
  return fd;
}

/*
 * Open the file we want to load/cache and generate a cache key for it if it
 * was loaded.
 */
static int
open_current_file(const char * path, struct bs_cache_key * key, const char ** errno_provenance)
{
  struct stat statbuf;
  int fd;

  fd = bs_open_noatime(path, O_RDONLY);
  if (fd < 0) {
    *errno_provenance = "bs_fetch:open_current_file:open";
    return fd;
  }
  #ifdef _WIN32
  setmode(fd, O_BINARY);
  #endif

  if (fstat(fd, &statbuf) < 0) {
    *errno_provenance = "bs_fetch:open_current_file:fstat";
    int previous_errno = errno;
    close(fd);
    errno = previous_errno;
    return -1;
  }

  key->version        = current_version;
  key->ruby_platform  = current_ruby_platform;
  key->compile_option = current_compile_option_crc32;
  key->ruby_revision  = current_ruby_revision;
  key->size           = (uint64_t)statbuf.st_size;
  key->mtime          = (uint64_t)statbuf.st_mtime;
  key->digest_set     = false;

  return fd;
}

#define ERROR_WITH_ERRNO -1
#define CACHE_MISS -2
#define CACHE_STALE -3
#define CACHE_UNCOMPILABLE -4

/*
 * Read the cache key from the given fd, which must have position 0 (e.g.
 * freshly opened file).
 *
 * Possible return values:
 *   - 0 (OK, key was loaded)
 *   - ERROR_WITH_ERRNO (-1, errno is set)
 *   - CACHE_MISS (-2)
 *   - CACHE_STALE (-3)
 */
static int
bs_read_key(int fd, struct bs_cache_key * key)
{
  ssize_t nread = read(fd, key, KEY_SIZE);
  if (nread < 0)        return ERROR_WITH_ERRNO;
  if (nread < KEY_SIZE) return CACHE_STALE;
  return 0;
}

/*
 * Open the cache file at a given path, if it exists, and read its key into the
 * struct.
 *
 * Possible return values:
 *   - 0 (OK, key was loaded)
 *   - CACHE_MISS (-2)
 *   - CACHE_STALE (-3)
 *   - ERROR_WITH_ERRNO (-1, errno is set)
 */
static int
open_cache_file(const char * path, struct bs_cache_key * key, const char ** errno_provenance)
{
  int fd, res;

  if (readonly || !revalidation) {
    fd = bs_open_noatime(path, O_RDONLY);
  } else {
    fd = bs_open_noatime(path, O_RDWR);
  }

  if (fd < 0) {
    *errno_provenance = "bs_fetch:open_cache_file:open";
    return CACHE_MISS;
  }
  #ifdef _WIN32
  setmode(fd, O_BINARY);
  #endif

  res = bs_read_key(fd, key);
  if (res < 0) {
    *errno_provenance = "bs_fetch:open_cache_file:read";
    close(fd);
    return res;
  }

  return fd;
}

/*
 * The cache file is laid out like:
 *   0...64 : bs_cache_key
 *   64..-1 : cached artifact
 *
 * This function takes a file descriptor whose position is pre-set to 64, and
 * the data_size (corresponding to the remaining number of bytes) listed in the
 * cache header.
 *
 * We load the text from this file into a buffer, and pass it to the ruby-land
 * handler with exception handling via the exception_tag param.
 *
 * Data is returned via the output_data parameter, which, if there's no error
 * or exception, will be the final data returnable to the user.
 */
static int
fetch_cached_data(int fd, ssize_t data_size, VALUE handler, VALUE args, VALUE * output_data, int * exception_tag, const char ** errno_provenance)
{
  ssize_t nread;
  int ret;

  VALUE storage_data;

  if (data_size > 100000000000) {
    *errno_provenance = "bs_fetch:fetch_cached_data:datasize";
    errno = EINVAL; /* because wtf? */
    ret = ERROR_WITH_ERRNO;
    goto done;
  }
  storage_data = rb_str_buf_new(data_size);
  nread = read(fd, RSTRING_PTR(storage_data), data_size);
  if (nread < 0) {
    *errno_provenance = "bs_fetch:fetch_cached_data:read";
    ret = ERROR_WITH_ERRNO;
    goto done;
  }
  if (nread != data_size) {
    ret = CACHE_STALE;
    goto done;
  }

  rb_str_set_len(storage_data, nread);

  *exception_tag = bs_storage_to_output(handler, args, storage_data, output_data);
  if (*output_data == rb_cBootsnap_CompileCache_UNCOMPILABLE) {
    ret = CACHE_UNCOMPILABLE;
    goto done;
  }
  ret = 0;
done:
  return ret;
}

/*
 * Like mkdir -p, this recursively creates directory parents of a file. e.g.
 * given /a/b/c, creates /a and /a/b.
 */
static int
mkpath(char * file_path, mode_t mode)
{
  /* It would likely be more efficient to count back until we
   * find a component that *does* exist, but this will only run
   * at most 256 times, so it seems not worthwhile to change. */
  char * p;
  for (p = strchr(file_path + 1, '/'); p; p = strchr(p + 1, '/')) {
    *p = '\0';
    #ifdef _WIN32
    if (mkdir(file_path) == -1) {
    #else
    if (mkdir(file_path, mode) == -1) {
    #endif
      if (errno != EEXIST) {
        *p = '/';
        return -1;
      }
    }
    *p = '/';
  }
  return 0;
}

/*
 * Write a cache header/key and a compiled artifact to a given cache path by
 * writing to a tmpfile and then renaming the tmpfile over top of the final
 * path.
 */
static int
atomic_write_cache_file(char * path, struct bs_cache_key * key, VALUE data, const char ** errno_provenance)
{
  char template[MAX_CACHEPATH_SIZE + 20];
  char * tmp_path;
  int fd, ret, attempt;
  ssize_t nwrite;

  for (attempt = 0; attempt < MAX_CREATE_TEMPFILE_ATTEMPT; ++attempt) {
    tmp_path = strncpy(template, path, MAX_CACHEPATH_SIZE);
    strcat(tmp_path, ".tmp.XXXXXX");

    // mkstemp modifies the template to be the actual created path
    fd = mkstemp(tmp_path);
    if (fd > 0) break;

    if (attempt == 0 && mkpath(tmp_path, 0775) < 0) {
      *errno_provenance = "bs_fetch:atomic_write_cache_file:mkpath";
      return -1;
    }
  }
  if (fd < 0) {
    *errno_provenance = "bs_fetch:atomic_write_cache_file:mkstemp";
    return -1;
  }

  if (chmod(tmp_path, 0644) < 0) {
    *errno_provenance = "bs_fetch:atomic_write_cache_file:chmod";
    return -1;
  }

  #ifdef _WIN32
  setmode(fd, O_BINARY);
  #endif

  key->data_size = RSTRING_LEN(data);
  nwrite = write(fd, key, KEY_SIZE);
  if (nwrite < 0) {
    *errno_provenance = "bs_fetch:atomic_write_cache_file:write";
    return -1;
  }
  if (nwrite != KEY_SIZE) {
    *errno_provenance = "bs_fetch:atomic_write_cache_file:keysize";
    errno = EIO; /* Lies but whatever */
    return -1;
  }

  nwrite = write(fd, RSTRING_PTR(data), RSTRING_LEN(data));
  if (nwrite < 0) return -1;
  if (nwrite != RSTRING_LEN(data)) {
    *errno_provenance = "bs_fetch:atomic_write_cache_file:writelength";
    errno = EIO; /* Lies but whatever */
    return -1;
  }

  close(fd);
  ret = rename(tmp_path, path);
  if (ret < 0) {
    *errno_provenance = "bs_fetch:atomic_write_cache_file:rename";
    return -1;
  }
  ret = chmod(path, 0664 & ~current_umask);
  if (ret < 0) {
    *errno_provenance = "bs_fetch:atomic_write_cache_file:chmod";
  }
  return ret;
}


/* Read contents from an fd, whose contents are asserted to be +size+ bytes
 * long, returning a Ruby string on success and Qfalse on failure */
static VALUE
bs_read_contents(int fd, size_t size, const char ** errno_provenance)
{
  VALUE contents;
  ssize_t nread;
  contents = rb_str_buf_new(size);
  nread = read(fd, RSTRING_PTR(contents), size);

  if (nread < 0) {
    *errno_provenance = "bs_fetch:bs_read_contents:read";
    return Qfalse;
  } else {
    rb_str_set_len(contents, nread);
    return contents;
  }
}

/*
 * This is the meat of the extension. bs_fetch is
 * Bootsnap::CompileCache::Native.fetch.
 *
 * There are three "formats" in use here:
 *   1. "input" format, which is what we load from the source file;
 *   2. "storage" format, which we write to the cache;
 *   3. "output" format, which is what we return.
 *
 * E.g., For ISeq compilation:
 *   input:   ruby source, as text
 *   storage: binary string (RubyVM::InstructionSequence#to_binary)
 *   output:  Instance of RubyVM::InstructionSequence
 *
 * And for YAML:
 *   input:   yaml as text
 *   storage: MessagePack or Marshal text
 *   output:  ruby object, loaded from yaml/messagepack/marshal
 *
 * A handler<I,S,O> passed in must support three messages:
 *   * storage_to_output(S) -> O
 *   * input_to_output(I)   -> O
 *   * input_to_storage(I)  -> S
 *     (input_to_storage may raise Bootsnap::CompileCache::Uncompilable, which
 *     will prevent caching and cause output to be generated with
 *     input_to_output)
 *
 * The semantics of this function are basically:
 *
 *   return storage_to_output(cache[path]) if cache[path]
 *   storage = input_to_storage(input)
 *   cache[path] = storage
 *   return storage_to_output(storage)
 *
 * Or expanded a bit:
 *
 *   - Check if the cache file exists and is up to date.
 *   - If it is, load this data to storage_data.
 *   - return storage_to_output(storage_data)
 *   - Read the file to input_data
 *   - Generate storage_data using input_to_storage(input_data)
 *   - Write storage_data data, with a cache key, to the cache file.
 *   - Return storage_to_output(storage_data)
 */
static VALUE
bs_fetch(char * path, VALUE path_v, char * cache_path, VALUE handler, VALUE args)
{
  struct bs_cache_key cached_key, current_key;
  int cache_fd = -1, current_fd = -1;
  int res, valid_cache = 0, exception_tag = 0;
  const char * errno_provenance = NULL;

  VALUE status = Qfalse;
  VALUE input_data = Qfalse;   /* data read from source file, e.g. YAML or ruby source */
  VALUE storage_data; /* compiled data, e.g. msgpack / binary iseq */
  VALUE output_data;  /* return data, e.g. ruby hash or loaded iseq */

  VALUE exception; /* ruby exception object to raise instead of returning */
  VALUE exception_message; /* ruby exception string to use instead of errno_provenance */

  /* Open the source file and generate a cache key for it */
  current_fd = open_current_file(path, &current_key, &errno_provenance);
  if (current_fd < 0) {
    exception_message = path_v;
    goto fail_errno;
  }

  /* Open the cache key if it exists, and read its cache key in */
  cache_fd = open_cache_file(cache_path, &cached_key, &errno_provenance);
  if (cache_fd == CACHE_MISS || cache_fd == CACHE_STALE) {
    /* This is ok: valid_cache remains false, we re-populate it. */
    bs_instrumentation(cache_fd == CACHE_MISS ? sym_miss : sym_stale, path_v);
  } else if (cache_fd < 0) {
    exception_message = rb_str_new_cstr(cache_path);
    goto fail_errno;
  } else {
    /* True if the cache existed and no invalidating changes have occurred since
     * it was generated. */

    switch(cache_key_equal_fast_path(&current_key, &cached_key)) {
    case hit:
      status = sym_hit;
      valid_cache = true;
      break;
    case miss:
      valid_cache = false;
      break;
    case stale:
      valid_cache = false;
      if ((input_data = bs_read_contents(current_fd, current_key.size,
                                     &errno_provenance)) == Qfalse) {
        exception_message = path_v;
        goto fail_errno;
      }
      valid_cache = cache_key_equal_slow_path(&current_key, &cached_key, input_data);
      if (valid_cache) {
        if (!readonly) {
          if (update_cache_key(&current_key, &cached_key, cache_fd, &errno_provenance)) {
              exception_message = path_v;
              goto fail_errno;
          }
        }
        status = sym_revalidated;
      }
      break;
    };

    if (!valid_cache) {
      status = sym_stale;
    }
  }

  if (valid_cache) {
    /* Fetch the cache data and return it if we're able to load it successfully */
    res = fetch_cached_data(
      cache_fd, (ssize_t)cached_key.data_size, handler, args,
      &output_data, &exception_tag, &errno_provenance
    );
    if (exception_tag != 0) goto raise;
    else if (res == CACHE_UNCOMPILABLE) {
      /* If fetch_cached_data returned `Uncompilable` we fallback to `input_to_output`
        This happens if we have say, an unsafe YAML cache, but try to load it in safe mode */
      if (input_data == Qfalse && (input_data = bs_read_contents(current_fd, current_key.size, &errno_provenance)) == Qfalse) {
        exception_message = path_v;
        goto fail_errno;
      }
      bs_input_to_output(handler, args, input_data, &output_data, &exception_tag);
      if (exception_tag != 0) goto raise;
      goto succeed;
    } else if (res == CACHE_MISS || res == CACHE_STALE) valid_cache = 0;
    else if (res == ERROR_WITH_ERRNO){
      exception_message = rb_str_new_cstr(cache_path);
      goto fail_errno;
    }
    else if (!NIL_P(output_data)) goto succeed; /* fast-path, goal */
  }
  close(cache_fd);
  cache_fd = -1;
  /* Cache is stale, invalid, or missing. Regenerate and write it out. */

  /* Read the contents of the source file into a buffer */
  if (input_data == Qfalse && (input_data = bs_read_contents(current_fd, current_key.size, &errno_provenance)) == Qfalse) {
    exception_message = path_v;
    goto fail_errno;
  }

  /* Try to compile the input_data using input_to_storage(input_data) */
  exception_tag = bs_input_to_storage(handler, args, input_data, path_v, &storage_data);
  if (exception_tag != 0) goto raise;
  /* If input_to_storage raised Bootsnap::CompileCache::Uncompilable, don't try
   * to cache anything; just return input_to_output(input_data) */
  if (storage_data == rb_cBootsnap_CompileCache_UNCOMPILABLE) {
    bs_input_to_output(handler, args, input_data, &output_data, &exception_tag);
    if (exception_tag != 0) goto raise;
    goto succeed;
  }
  /* If storage_data isn't a string, we can't cache it */
  if (!RB_TYPE_P(storage_data, T_STRING)) goto invalid_type_storage_data;

  /* Attempt to write the cache key and storage_data to the cache directory.
   * We do however ignore any failures to persist the cache, as it's better
   * to move along, than to interrupt the process.
   */
  bs_cache_key_digest(&current_key, input_data);
  atomic_write_cache_file(cache_path, &current_key, storage_data, &errno_provenance);

  /* Having written the cache, now convert storage_data to output_data */
  exception_tag = bs_storage_to_output(handler, args, storage_data, &output_data);
  if (exception_tag != 0) goto raise;

  if (output_data == rb_cBootsnap_CompileCache_UNCOMPILABLE) {
    /* If storage_to_output returned `Uncompilable` we fallback to `input_to_output` */
    bs_input_to_output(handler, args, input_data, &output_data, &exception_tag);
    if (exception_tag != 0) goto raise;
  } else if (NIL_P(output_data)) {
    /* If output_data is nil, delete the cache entry and generate the output
     * using input_to_output */
    if (unlink(cache_path) < 0) {
      /* If the cache was already deleted, it might be that another process did it before us.
      * No point raising an error */
      if (errno != ENOENT) {
        errno_provenance = "bs_fetch:unlink";
        exception_message = rb_str_new_cstr(cache_path);
        goto fail_errno;
      }
    }
    bs_input_to_output(handler, args, input_data, &output_data, &exception_tag);
    if (exception_tag != 0) goto raise;
  }

  goto succeed; /* output_data is now the correct return. */

#define CLEANUP \
  if (current_fd >= 0)  close(current_fd); \
  if (cache_fd >= 0)    close(cache_fd); \
  if (status != Qfalse) bs_instrumentation(status, path_v);

succeed:
  CLEANUP;
  return output_data;
fail_errno:
  CLEANUP;
  if (errno_provenance) {
    exception_message = rb_str_concat(
      rb_str_new_cstr(errno_provenance),
      rb_str_concat(rb_str_new_cstr(": "), exception_message)
    );
  }
  exception = rb_syserr_new_str(errno, exception_message);
  rb_exc_raise(exception);
  __builtin_unreachable();
raise:
  CLEANUP;
  rb_jump_tag(exception_tag);
  __builtin_unreachable();
invalid_type_storage_data:
  CLEANUP;
  Check_Type(storage_data, T_STRING);
  __builtin_unreachable();

#undef CLEANUP
}

static VALUE
bs_precompile(char * path, VALUE path_v, char * cache_path, VALUE handler)
{
  if (readonly) {
    return Qfalse;
  }

  struct bs_cache_key cached_key, current_key;
  int cache_fd = -1, current_fd = -1;
  int res, valid_cache = 0, exception_tag = 0;
  const char * errno_provenance = NULL;

  VALUE input_data = Qfalse;   /* data read from source file, e.g. YAML or ruby source */
  VALUE storage_data; /* compiled data, e.g. msgpack / binary iseq */

  /* Open the source file and generate a cache key for it */
  current_fd = open_current_file(path, &current_key, &errno_provenance);
  if (current_fd < 0) goto fail;

  /* Open the cache key if it exists, and read its cache key in */
  cache_fd = open_cache_file(cache_path, &cached_key, &errno_provenance);
  if (cache_fd == CACHE_MISS || cache_fd == CACHE_STALE) {
    /* This is ok: valid_cache remains false, we re-populate it. */
  } else if (cache_fd < 0) {
    goto fail;
  } else {
    /* True if the cache existed and no invalidating changes have occurred since
     * it was generated. */
    switch(cache_key_equal_fast_path(&current_key, &cached_key)) {
    case hit:
      valid_cache = true;
      break;
    case miss:
      valid_cache = false;
      break;
    case stale:
      valid_cache = false;
      if ((input_data = bs_read_contents(current_fd, current_key.size, &errno_provenance)) == Qfalse) {
        goto fail;
      }
      valid_cache = cache_key_equal_slow_path(&current_key, &cached_key, input_data);
       if (valid_cache) {
         if (update_cache_key(&current_key, &cached_key, cache_fd, &errno_provenance)) {
             goto fail;
         }
      }
      break;
    };
  }

  if (valid_cache) {
    goto succeed;
  }

  close(cache_fd);
  cache_fd = -1;
  /* Cache is stale, invalid, or missing. Regenerate and write it out. */

  /* Read the contents of the source file into a buffer */
  if ((input_data = bs_read_contents(current_fd, current_key.size, &errno_provenance)) == Qfalse) goto fail;

  /* Try to compile the input_data using input_to_storage(input_data) */
  exception_tag = bs_input_to_storage(handler, Qnil, input_data, path_v, &storage_data);
  if (exception_tag != 0) goto fail;

  /* If input_to_storage raised Bootsnap::CompileCache::Uncompilable, don't try
   * to cache anything; just return false */
  if (storage_data == rb_cBootsnap_CompileCache_UNCOMPILABLE) {
    goto fail;
  }
  /* If storage_data isn't a string, we can't cache it */
  if (!RB_TYPE_P(storage_data, T_STRING)) goto fail;

  /* Write the cache key and storage_data to the cache directory */
  bs_cache_key_digest(&current_key, input_data);
  res = atomic_write_cache_file(cache_path, &current_key, storage_data, &errno_provenance);
  if (res < 0) goto fail;

  goto succeed;

#define CLEANUP \
  if (current_fd >= 0)  close(current_fd); \
  if (cache_fd >= 0)    close(cache_fd);

succeed:
  CLEANUP;
  return Qtrue;
fail:
  CLEANUP;
  return Qfalse;
#undef CLEANUP
}


/*****************************************************************************/
/********************* Handler Wrappers **************************************/
/*****************************************************************************
 * Everything after this point in the file is just wrappers to deal with ruby's
 * clunky method of handling exceptions from ruby methods invoked from C:
 *
 * In order to call a ruby method from C, while protecting against crashing in
 * the event of an exception, we must call the method with rb_protect().
 *
 * rb_protect takes a C function and precisely one argument; however, we want
 * to pass multiple arguments, so we must create structs to wrap them up.
 *
 * These functions return an exception_tag, which, if non-zero, indicates an
 * exception that should be jumped to with rb_jump_tag after cleaning up
 * allocated resources.
 */

struct s2o_data {
  VALUE handler;
  VALUE args;
  VALUE storage_data;
};

struct i2o_data {
  VALUE handler;
  VALUE args;
  VALUE input_data;
};

struct i2s_data {
  VALUE handler;
  VALUE input_data;
  VALUE pathval;
};

static VALUE
try_storage_to_output(VALUE arg)
{
  struct s2o_data * data = (struct s2o_data *)arg;
  return rb_funcall(data->handler, rb_intern("storage_to_output"), 2, data->storage_data, data->args);
}

static int
bs_storage_to_output(VALUE handler, VALUE args, VALUE storage_data, VALUE * output_data)
{
  int state;
  struct s2o_data s2o_data = {
    .handler      = handler,
    .args         = args,
    .storage_data = storage_data,
  };
  *output_data = rb_protect(try_storage_to_output, (VALUE)&s2o_data, &state);
  return state;
}

static void
bs_input_to_output(VALUE handler, VALUE args, VALUE input_data, VALUE * output_data, int * exception_tag)
{
  struct i2o_data i2o_data = {
    .handler    = handler,
    .args       = args,
    .input_data = input_data,
  };
  *output_data = rb_protect(prot_input_to_output, (VALUE)&i2o_data, exception_tag);
}

static VALUE
prot_input_to_output(VALUE arg)
{
  struct i2o_data * data = (struct i2o_data *)arg;
  return rb_funcall(data->handler, rb_intern("input_to_output"), 2, data->input_data, data->args);
}

static VALUE
try_input_to_storage(VALUE arg)
{
  struct i2s_data * data = (struct i2s_data *)arg;
  return rb_funcall(data->handler, rb_intern("input_to_storage"), 2, data->input_data, data->pathval);
}

static int
bs_input_to_storage(VALUE handler, VALUE args, VALUE input_data, VALUE pathval, VALUE * storage_data)
{
  if (readonly) {
    *storage_data = rb_cBootsnap_CompileCache_UNCOMPILABLE;
    return 0;
  } else {
    int state;
    struct i2s_data i2s_data = {
      .handler    = handler,
      .input_data = input_data,
      .pathval    = pathval,
    };
    *storage_data = rb_protect(try_input_to_storage, (VALUE)&i2s_data, &state);
    return state;
  }
}
