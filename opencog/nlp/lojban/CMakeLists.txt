ADD_SUBDIRECTORY (CWrapper)

# ----------------------------------------
# Lojban cogserver module

LINK_DIRECTORIES(${CMAKE_SOURCE_DIR}/opencog/nlp/lojban/CWrapper/)

ADD_LIBRARY (LojbanModule SHARED
    LojbanModule
)

ADD_DEPENDENCIES(LojbanModule LojbanLib)

TARGET_LINK_LIBRARIES (LojbanModule
    opencog-lojban-wrapper-0.1.0.0
)

INSTALL (TARGETS LojbanModule
	LIBRARY DESTINATION "lib${LIB_DIR_SUFFIX}/opencog/modules"
)
