cmake_minimum_required(VERSION 3.22.1)
project(softether_jni C)

add_library(softether_jni SHARED softether_jni.c)

set(PREBUILT ${CMAKE_CURRENT_SOURCE_DIR}/prebuilt/${ANDROID_ABI})

target_link_libraries(
    softether_jni
    -Wl,--start-group
    ${PREBUILT}/libsoftether.a
    ${PREBUILT}/libssl.a
    ${PREBUILT}/libcrypto.a
    -Wl,--end-group
    log
    dl
)
