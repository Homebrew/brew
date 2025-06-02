#ifndef RUBY_MEMORY_VIEW_H                           /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_MEMORY_VIEW_H 1
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Memory View.
 */

#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>                       /* size_t */
#endif

#ifdef HAVE_SYS_TYPES_H
# include <sys/types.h>                    /* ssize_t */
#endif

#include "ruby/internal/attr/pure.h"       /* RBIMPL_ATTR_PURE */
#include "ruby/internal/core/rtypeddata.h" /* rb_data_type_t */
#include "ruby/internal/dllexport.h"       /* RUBY_EXTERN */
#include "ruby/internal/stdbool.h"         /* bool */
#include "ruby/internal/value.h"           /* VALUE */

/**
 * Flags passed to rb_memory_view_get(), then to ::rb_memory_view_get_func_t.
 */
enum ruby_memory_view_flags {
    RUBY_MEMORY_VIEW_SIMPLE            = 0,
    RUBY_MEMORY_VIEW_WRITABLE          = (1<<0),
    RUBY_MEMORY_VIEW_FORMAT            = (1<<1),
    RUBY_MEMORY_VIEW_MULTI_DIMENSIONAL = (1<<2),
    RUBY_MEMORY_VIEW_STRIDES           = (1<<3) | RUBY_MEMORY_VIEW_MULTI_DIMENSIONAL,
    RUBY_MEMORY_VIEW_ROW_MAJOR         = (1<<4) | RUBY_MEMORY_VIEW_STRIDES,
    RUBY_MEMORY_VIEW_COLUMN_MAJOR      = (1<<5) | RUBY_MEMORY_VIEW_STRIDES,
    RUBY_MEMORY_VIEW_ANY_CONTIGUOUS    = RUBY_MEMORY_VIEW_ROW_MAJOR | RUBY_MEMORY_VIEW_COLUMN_MAJOR,
    RUBY_MEMORY_VIEW_INDIRECT          = (1<<6) | RUBY_MEMORY_VIEW_STRIDES,
};

/** Memory view component metadata. */
typedef struct {
    /** @see ::rb_memory_view_t::format */
    char format;

    /** :FIXME: what is a "native" size is unclear. */
    bool native_size_p;

    /** Endian of the component */
    bool little_endian_p;

    /** The component's offset. */
    size_t offset;

    /** The component's size. */
    size_t size;

    /**
     * How many numbers of components are there. For instance "CCC"'s repeat is
     * 3.
     */
    size_t repeat;
} rb_memory_view_item_component_t;

/**
 * A MemoryView  structure, `rb_memory_view_t`, is used  for exporting objects'
 * MemoryView.
 *
 * This structure contains  the reference of the object, which  is the owner of
 * the MemoryView, the pointer to the head of exported memory, and the metadata
 * that  describes the  structure of  the  memory.  The  metadata can  describe
 * multidimensional arrays with strides.
 */
typedef struct {
    /**
     * The original object that has the memory exported via this memory view.
     */
    VALUE obj;

    /** The pointer to the exported memory. */
    void *data;

    /** The number of bytes in data. */
    ssize_t byte_size;

    /** true for readonly memory, false for writable memory. */
    bool readonly;

    /**
     * A string to describe the format of an element, or NULL for unsigned bytes.
     * The format string is a sequence of the following pack-template specifiers:
     *
     *   c, C, s, s!, S, S!, n, v, i, i!, I, I!, l, l!, L, L!,
     *   N, V, f, e, g, q, q!, Q, Q!, d, E, G, j, J, x
     *
     * For example, "dd" for an element that consists of two double values,
     * and "CCC" for an element that consists of three bytes, such as
     * an RGB color triplet.
     *
     * Also, the value endianness can be explicitly specified by '<' or '>'
     * following a value type specifier.
     *
     * The items are packed contiguously.  When you emulate the alignment of
     * structure members, put '|' at the beginning of the format string,
     * like "|iqc".  On x86_64 Linux ABI, the size of the item by this format
     * is 24 bytes instead of 13 bytes.
     */
    const char *format;

    /**
     * The number of bytes in each element.
     * item_size should equal to rb_memory_view_item_size_from_format(format). */
    ssize_t item_size;

    /** Description of each components. */
    struct {
        /**
         * The array of rb_memory_view_item_component_t that describes the
         * item structure.  rb_memory_view_prepare_item_desc and
         * rb_memory_view_get_item allocate this memory if needed,
         * and rb_memory_view_release frees it. */
        const rb_memory_view_item_component_t *components;

        /** The number of components in an item. */
        size_t length;
    } item_desc;

    /** The number of dimension. */
    ssize_t ndim;

    /**
     * ndim size array indicating the number of elements in each dimension.
     * This can be NULL when ndim == 1. */
    const ssize_t *shape;

    /**
     * ndim size array indicating the number of bytes to skip to go to the
     * next element in each dimension. */
    const ssize_t *strides;

    /**
     * The offset in each dimension when this memory view exposes a nested array.
     * Or, NULL when this memory view exposes a flat array. */
    const ssize_t *sub_offsets;

    /** The private data for managing this exported memory */
    void *private_data;

    /** DO NOT TOUCH THIS: The memory view entry for the internal use */
    const struct rb_memory_view_entry *_memory_view_entry;
} rb_memory_view_t;

/** Type of function of ::rb_memory_view_entry_t::get_func. */
typedef bool (* rb_memory_view_get_func_t)(VALUE obj, rb_memory_view_t *view, int flags);

/** Type of function of ::rb_memory_view_entry_t::release_func. */
typedef bool (* rb_memory_view_release_func_t)(VALUE obj, rb_memory_view_t *view);

/** Type of function of ::rb_memory_view_entry_t::available_p_func. */
typedef bool (* rb_memory_view_available_p_func_t)(VALUE obj);

/** Operations applied to a specific kind of a memory view. */
typedef struct rb_memory_view_entry {
    /**
     * Exports a memory view from a Ruby object.
     */
    rb_memory_view_get_func_t get_func;

    /**
     * Releases   a   memory  view   that   was   previously  generated   using
     * ::rb_memory_view_entry_t::get_func.
     */
    rb_memory_view_release_func_t release_func;

    /**
     * Queries if an object understands memory view protocol.
     */
    rb_memory_view_available_p_func_t available_p_func;
} rb_memory_view_entry_t;

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* memory_view.c */

/**
 * Associates the passed class with the  passed memory view entry.  This has to
 * be called before actually creating a memory view from an instance.
 */
bool rb_memory_view_register(VALUE klass, const rb_memory_view_entry_t *entry);

RBIMPL_ATTR_PURE()
/**
 * Return `true` if the data in the MemoryView `view` is row-major contiguous.
 *
 * Return `false` otherwise.
 */
bool rb_memory_view_is_row_major_contiguous(const rb_memory_view_t *view);

RBIMPL_ATTR_PURE()
/**
 * Return  `true`  if  the  data  in  the  MemoryView  `view`  is  column-major
 * contiguous.
 *
 * Return `false` otherwise.
 */
bool rb_memory_view_is_column_major_contiguous(const rb_memory_view_t *view);

RBIMPL_ATTR_NOALIAS()
/**
 * Fill the  `strides` array  with byte-Strides  of a  contiguous array  of the
 * given shape with the given element size.
 */
void rb_memory_view_fill_contiguous_strides(const ssize_t ndim, const ssize_t item_size, const ssize_t *const shape, const bool row_major_p, ssize_t *const strides);

RBIMPL_ATTR_NOALIAS()
/**
 * Fill the members of `view` as an 1-dimensional byte array.
 */
bool rb_memory_view_init_as_byte_array(rb_memory_view_t *view, VALUE obj, void *data, const ssize_t len, const bool readonly);

/**
 * Deconstructs    the     passed    format    string,    as     describe    in
 * ::rb_memory_view_t::format.
 */
ssize_t rb_memory_view_parse_item_format(const char *format,
                                         rb_memory_view_item_component_t **members,
                                         size_t *n_members, const char **err);

/**
 * Calculate the number of bytes occupied by an element.
 *
 * When the calculation  fails, the failed location in `format`  is stored into
 * `err`, and returns `-1`.
 */
ssize_t rb_memory_view_item_size_from_format(const char *format, const char **err);

/**
 * Calculate the location of the item indicated by the given `indices`.
 *
 * The length of `indices` must equal to `view->ndim`.
 *
 * This function initializes `view->item_desc` if needed.
 */
void *rb_memory_view_get_item_pointer(rb_memory_view_t *view, const ssize_t *indices);

/**
 * Return a value that consists of item members.
 *
 * When an item is a single member, the return value is a single value.
 *
 * When an item consists of multiple members, an array will be returned.
 */
VALUE rb_memory_view_extract_item_members(const void *ptr, const rb_memory_view_item_component_t *members, const size_t n_members);

/** Fill the `item_desc` member of `view`. */
void rb_memory_view_prepare_item_desc(rb_memory_view_t *view);

/** * Return a value that consists of item members in the given memory view. */
VALUE rb_memory_view_get_item(rb_memory_view_t *view, const ssize_t *indices);

/**
 * Return  `true` if  `obj` supports  to export  a MemoryView.   Return `false`
 * otherwise.
 *
 * If   this  function   returns   `true`,  it   doesn't   mean  the   function
 * `rb_memory_view_get` will succeed.
 */
bool rb_memory_view_available_p(VALUE obj);

/**
 * If the given  `obj` supports to export a MemoryView  that conforms the given
 * `flags`, this function fills `view` by the information of the MemoryView and
 * returns `true`.  In this case, the reference count of `obj` is increased.
 *
 * If the  given combination of `obj`  and `flags` cannot export  a MemoryView,
 * this function returns `false`. The content  of `view` is not touched in this
 * case.
 *
 * The exported  MemoryView must  be released by  `rb_memory_view_release` when
 * the MemoryView is no longer needed.
 */
bool rb_memory_view_get(VALUE obj, rb_memory_view_t* memory_view, int flags);

/**
 * Release the  given MemoryView  `view` and decrement  the reference  count of
 * `memory_view->obj`.
 *
 * Consumers must call  this function when the MemoryView is  no longer needed.
 * Missing to call this function leads memory leak.
 */
bool rb_memory_view_release(rb_memory_view_t* memory_view);

/* for testing */
/** @cond INTERNAL_MACRO */
RUBY_EXTERN VALUE rb_memory_view_exported_object_registry;
RUBY_EXTERN const rb_data_type_t rb_memory_view_exported_object_registry_data_type;
/** @endcond */

RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_PURE()
/**
 * Return  `true`  if  the  data  in the  MemoryView  `view`  is  row-major  or
 * column-major contiguous.
 *
 * Return `false` otherwise.
 */
static inline bool
rb_memory_view_is_contiguous(const rb_memory_view_t *view)
{
    if (rb_memory_view_is_row_major_contiguous(view)) {
        return true;
    }
    else if (rb_memory_view_is_column_major_contiguous(view)) {
        return true;
    }
    else {
        return false;
    }
}

#endif /* RUBY_BUFFER_H */
