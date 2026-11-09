#include "trace_io.hpp"
#include "robot/core.hpp"
#include <cmath>
#include <iomanip>
#include <iostream>
#include <limits>

struct SensorSample {
    timing::Sample stamp;
    double left_angle, right_angle, range;
};

const auto command = robot::wheel_twist({0.05, 0.4}, 10, 14);

double front_range(const robot::World& world, double time) {
    const auto pose = robot::integrate({1, 1, 0}, command, time);
    return robot::lidar(world, pose, {0, 1, 20, 1}).front();
}

void emit(const std::string& trace) {
    const auto stamps = timing::load_trace(trace);
    const robot::World world(100, 100, 0.1);
    std::cout << "sequence,ticks,left_angle_rad,right_angle_rad,front_range_m\n" << std::setprecision(17);
    for (const auto sample : stamps) {
        // Plant sampling follows the independent simulation schedule, not the FPGA timestamp.
        const double time = (sample.sequence - stamps.front().sequence) * 0.01;
        std::cout << sample.sequence << ',' << sample.ticks << ',' << 10 * time << ','
                  << 14 * time << ',' << front_range(world, time) << '\n';
    }
}

double real_field(const std::string& field) {
    double value{};
    const auto parsed = std::from_chars(field.data(), field.data() + field.size(), value);
    if (parsed.ec != std::errc{} || parsed.ptr != field.data() + field.size() || !std::isfinite(value))
        throw std::runtime_error("invalid sensor value");
    return value;
}

SensorSample decode(const std::string& line) {
    std::istringstream stream(line);
    std::vector<std::string> fields;
    for (std::string field; std::getline(stream, field, ',');) fields.push_back(field);
    if (fields.size() != 5 || line.back() == ',') throw std::runtime_error("sensor message needs five fields");
    SensorSample sample{{timing::unsigned_field<unsigned>(fields[0], 10),
                         timing::unsigned_field<std::uint64_t>(fields[1], 10)},
                        real_field(fields[2]), real_field(fields[3]), real_field(fields[4])};
    if (sample.stamp.ticks > timing::mask || sample.range < 0 || sample.range > 20)
        throw std::runtime_error("sensor message outside declared range");
    return sample;
}

bool read_line(std::istream& input, std::string& line) {
    if (!std::getline(input, line)) return false;
    if (!line.empty() && line.back() == '\r') line.pop_back();
    return true;
}

void replay(const std::string& filename) {
    std::ifstream input(filename);
    if (!input) throw std::runtime_error("cannot open sensor message file: " + filename);
    std::string line;
    if (!read_line(input, line) || line != "sequence,ticks,left_angle_rad,right_angle_rad,front_range_m")
        throw std::runtime_error("sensor message header missing or invalid");
    const robot::World world(100, 100, 0.1);
    std::uint64_t elapsed = 0;
    timing::Sample previous{};
    unsigned count = 0;
    bool mismatch = false;
    std::cout << "sequence,time_s,predicted_range_m,measured_range_m,left_error_rad,right_error_rad\n" << std::setprecision(17);
    while (read_line(input, line)) {
        const auto sample = decode(line);
        if (count) {
            if (sample.stamp.sequence <= previous.sequence) throw std::runtime_error("sensor sequence is not increasing");
            const auto delta = timing::elapsed_ticks(previous.ticks, sample.stamp.ticks);
            if (delta > std::numeric_limits<std::uint64_t>::max() - elapsed)
                throw std::runtime_error("sensor elapsed time overflow");
            elapsed += delta;
        }
        const double time = static_cast<double>(elapsed) / 1000;
        const double predicted = front_range(world, time);
        const double left_error = sample.left_angle - 10 * time;
        const double right_error = sample.right_angle - 14 * time;
        mismatch |= std::abs(left_error) > 0.005 || std::abs(right_error) > 0.005 || std::abs(predicted - sample.range) > 0.004;
        std::cout << sample.stamp.sequence << ',' << time << ',' << predicted << ',' << sample.range
                  << ',' << left_error << ',' << right_error << '\n';
        previous = sample.stamp; ++count;
    }
    if (count < 2) throw std::runtime_error("at least two sensor messages required");
    if (mismatch) throw std::runtime_error("sensor/timestamp mismatch exceeds declared ideal-simulation limits");
}

int main(int argc, char** argv) {
    if (argc != 3) { std::cerr << "usage: sensor_cosim emit|replay INPUT\n"; return 2; }
    try {
        if (std::string(argv[1]) == "emit") emit(argv[2]);
        else if (std::string(argv[1]) == "replay") replay(argv[2]);
        else throw std::runtime_error("unknown sensor co-simulation mode");
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
