#include <iostream>

#include "engine/board.h"
#include "engine/uci.h"

int main() {
    engine::initTables();
    return engine::runUci(std::cin);
}
