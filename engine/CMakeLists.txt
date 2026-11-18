cmake_minimum_required(VERSION 3.10)
project(engine CXX)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Threads REQUIRED)

# NNUE network embedded into the binary (empty/missing file = HCE only).
set(RANK_EVALFILE "${CMAKE_CURRENT_SOURCE_DIR}/nets/rank-1.nnue" CACHE FILEPATH "Default NNUE network to embed")
option(RANK_USE_NNUE_DEFAULT "Default value of the 'Use NNUE' UCI option" ON)
option(RANK_NATIVE "Optimise for the build machine (-march=native)" OFF)

if(MSVC)
    add_compile_options(/W4)
else()
    add_compile_options(-Wall -Wextra)
    set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG")
    if(RANK_NATIVE)
        add_compile_options(-march=native)
    endif()
endif()

set(EMBED_NET_CPP "${CMAKE_CURRENT_BINARY_DIR}/embedded_net.cpp")
set(EMBED_NET_DEPS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/embed_net.cmake")
if(RANK_EVALFILE AND EXISTS "${RANK_EVALFILE}")
    list(APPEND EMBED_NET_DEPS "${RANK_EVALFILE}")
else()
    message(STATUS "NNUE: no network at '${RANK_EVALFILE}', building HCE-only")
endif()
add_custom_command(
    OUTPUT "${EMBED_NET_CPP}"
    COMMAND "${CMAKE_COMMAND}" -DNET_FILE=${RANK_EVALFILE} -DOUT_FILE=${EMBED_NET_CPP}
            -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/embed_net.cmake"
    DEPENDS ${EMBED_NET_DEPS}
    COMMENT "Embedding NNUE network ${RANK_EVALFILE}"
    VERBATIM)

# Core engine code shared by the UCI executable, tests and the C library.
add_library(engine_core STATIC
    src/board.cpp
    src/eval.cpp
    src/search.cpp
    src/uci.cpp
    src/nnue.cpp
    "${EMBED_NET_CPP}"
)
target_include_directories(engine_core PUBLIC include)
set_target_properties(engine_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_link_libraries(engine_core PUBLIC Threads::Threads)
target_compile_definitions(engine_core PRIVATE RANK_NNUE_DEFAULT=$<BOOL:${RANK_USE_NNUE_DEFAULT}>)

# UCI engine executable: build/chess_engine
add_executable(chess_engine src/main.cpp)
target_link_libraries(chess_engine PRIVATE engine_core)

# Small shared library exporting extern "C" int eval(const char* fen).
add_library(engine SHARED src/bridge.cpp)
target_link_libraries(engine PRIVATE engine_core)

# Tests
enable_testing()
add_executable(perft_test tests/perft_test.cpp)
target_link_libraries(perft_test PRIVATE engine_core)
add_test(NAME perft COMMAND perft_test)
add_executable(nnue_test tests/nnue_test.cpp)
target_link_libraries(nnue_test PRIVATE engine_core)
add_test(NAME nnue COMMAND nnue_test)

# NNUE pipeline: self-play data generation and the CPU trainer.
add_executable(datagen tools/datagen.cpp)
target_link_libraries(datagen PRIVATE engine_core)
add_executable(train tools/train.cpp)
target_link_libraries(train PRIVATE engine_core)
target_include_directories(datagen PRIVATE tools)
target_include_directories(train PRIVATE tools)
add_test(NAME train_gradcheck COMMAND train -gradcheck)

# Engine-vs-engine match / SPRT runner (POSIX process handling; Linux only).
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    add_executable(match tools/match.cpp)
    target_link_libraries(match PRIVATE engine_core)
endif()
