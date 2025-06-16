# Dependency providers were introduced in CMake 3.24. We don't set cmake_minimum_required here because that would
# propagate to downstream projects, which may break projects that rely on deprecated CMake behavior. Since the build
# is using brewed CMake, we can assume that the CMake version in use is at least 3.24.

option(HOMEBREW_ALLOW_FETCHCONTENT "Allow FetchContent to be used in Homebrew builds" OFF)

if (HOMEBREW_ALLOW_FETCHCONTENT)
    return()
endif()

macro(trap_fetchcontent_provider method depName)
    message(FATAL_ERROR "Refusing to populate dependency '${depName}' with FetchContent while building in Homebrew, please use a formula dependency or add a resource to the formula.")
endmacro()

cmake_language(
    SET_DEPENDENCY_PROVIDER trap_fetchcontent_provider
    SUPPORTED_METHODS FETCHCONTENT_MAKEAVAILABLE_SERIAL
)
