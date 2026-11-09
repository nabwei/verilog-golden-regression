#include "timing.hpp"
#include <functional>
#include <iostream>

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

void rejects(const std::function<void()>& action) {
    try { action(); }
    catch (const std::invalid_argument&) { return; }
    throw std::runtime_error("invalid input accepted");
}

void test_tick_boundaries() {
    require(timing::elapsed_ticks(timing::modulus - 2, 3) == 5, "wrap interval");
    require(timing::elapsed_ticks(0, timing::modulus / 2 - 1) == timing::modulus / 2 - 1,
            "largest unambiguous interval");
    rejects([] { timing::elapsed_ticks(1, 1); });
    rejects([] { timing::elapsed_ticks(2, 1); });
    rejects([] { timing::elapsed_ticks(0, timing::modulus / 2); });
    rejects([] { timing::elapsed_ticks(timing::modulus, 1); });
}

int main() {
    try { test_tick_boundaries(); }
    catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
    std::cout << "PASS: timestamp boundary tests\n";
}
