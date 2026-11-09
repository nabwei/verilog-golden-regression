#pragma once
#include <cstdint>
#include <stdexcept>

namespace timing {
constexpr std::uint64_t modulus = std::uint64_t{1} << 48;
constexpr std::uint64_t mask = modulus - 1;

inline std::uint64_t elapsed_ticks(std::uint64_t before, std::uint64_t after) {
    if (before > mask || after > mask) throw std::invalid_argument("timestamp exceeds 48 bits");
    const auto elapsed = (after - before) & mask;
    if (elapsed == 0 || elapsed >= modulus / 2)
        throw std::invalid_argument("duplicate, backwards or ambiguous timestamp");
    return elapsed;
}

template<class RegisterReader>
std::uint64_t snapshot(RegisterReader& registers) {
    const std::uint32_t low = registers.read(4);
    const std::uint32_t high = registers.read(8);
    if ((high & 0xffff0000U) != 0) throw std::runtime_error("reserved high timestamp bits set");
    return (static_cast<std::uint64_t>(high) << 32) | low;
}
}
