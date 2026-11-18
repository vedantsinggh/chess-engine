#pragma once

#include <istream>

namespace engine {

// Runs the UCI command loop until `quit` or end of input.
int runUci(std::istream& in);

} // namespace engine
