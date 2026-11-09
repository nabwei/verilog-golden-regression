#pragma once
#include "timing.hpp"
#include <charconv>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace timing {
struct Sample { unsigned sequence; std::uint64_t ticks; };

template<class Integer>
Integer unsigned_field(const std::string& token, int base) {
    Integer parsed{};
    const auto conversion = std::from_chars(token.data(), token.data() + token.size(), parsed, base);
    if (conversion.ec != std::errc{} || conversion.ptr != token.data() + token.size())
        throw std::runtime_error("invalid unsigned trace field");
    return parsed;
}

inline std::vector<Sample> load_trace(const std::string& path) {
    std::ifstream input(path);
    if (!input) throw std::runtime_error("cannot open HDL trace");
    std::vector<Sample> samples;
    std::string line;
    while (std::getline(input, line)) {
        std::string sequence, ticks, extra;
        std::istringstream row(line);
        if (!(row >> sequence >> ticks) || (row >> extra))
            throw std::runtime_error("malformed trace row");
        const Sample sample{unsigned_field<unsigned>(sequence, 10), unsigned_field<std::uint64_t>(ticks, 16)};
        if (sample.ticks > timing::mask) throw std::runtime_error("trace timestamp exceeds 48 bits");
        if (!samples.empty() && sample.sequence <= samples.back().sequence)
            throw std::runtime_error("sequence is not increasing");
        samples.push_back(sample);
    }
    if (samples.size() < 2) throw std::runtime_error("trace needs at least two samples");
    return samples;
}

}
