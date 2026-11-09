#include "trace_io.hpp"
#include "robot/core.hpp"
#include <charconv>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <string>
#include <vector>

using timing::Sample;

void replay(const std::vector<Sample>& samples, std::ostream& output) {
    robot::Pose pose;
    const auto command = robot::wheel_twist({0.05, 0.4}, 10, 14);
    std::uint64_t elapsed = 0;
    output << "sequence,elapsed_ticks,x_m,y_m,heading_rad\n" << std::setprecision(17);
    output << samples.front().sequence << ",0,0,0,0\n";
    for (std::size_t index = 1; index < samples.size(); ++index) {
        const auto delta = timing::elapsed_ticks(samples[index - 1].ticks, samples[index].ticks);
        if (delta > std::numeric_limits<std::uint64_t>::max() - elapsed)
            throw std::runtime_error("elapsed tick sum overflow");
        elapsed += delta;
        pose = robot::integrate(pose, command, static_cast<double>(delta) / 1000);
        output << samples[index].sequence << ',' << elapsed << ',' << pose.x << ','
               << pose.y << ',' << pose.heading << '\n';
    }
}

int main(int argc, char** argv) {
    if (argc != 2) { std::cerr << "usage: replay HDL_TRACE\n"; return 2; }
    try { replay(timing::load_trace(argv[1]), std::cout); }
    catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
