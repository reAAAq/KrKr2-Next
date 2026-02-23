
# Android platform configuration for ANGLE
# Uses ANGLE's own EGL implementation (NOT system EGL) to avoid conflicts
# with Flutter's Impeller renderer which also uses the system EGL.
# Backend: OpenGL ES (via ANGLE GL backend loading native GLES driver)

list(APPEND ANGLE_DEFINITIONS ANGLE_PLATFORM_ANDROID)

include(linux.cmake)

if (USE_ANGLE_EGL OR ENABLE_WEBGL)
    list(APPEND ANGLE_SOURCES
        ${gl_backend_sources}

        ${angle_system_utils_sources_linux}
        ${angle_system_utils_sources_posix}

        ${angle_dma_buf_sources}

        ${libangle_gl_egl_dl_sources}
        ${libangle_gl_egl_sources}
        ${libangle_gl_sources}

        ${libangle_gpu_info_util_sources}
        ${libangle_gpu_info_util_linux_sources}
    )

    list(APPEND ANGLE_DEFINITIONS
        ANGLE_ENABLE_OPENGL
    )

    # Enable GLSL compiler output
    list(APPEND ANGLE_DEFINITIONS ANGLE_ENABLE_GLSL)
endif ()

# Android system libraries
list(APPEND ANGLEGLESv2_LIBRARIES log android)
