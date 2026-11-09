#include "timing.hpp"
#include <atomic>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <string>
#include <sys/mman.h>
#include <unistd.h>

class UioRegisters {
    int descriptor_;
    void* mapping_;
public:
    explicit UioRegisters(const char* path) : descriptor_(::open(path, O_RDWR | O_CLOEXEC)), mapping_(MAP_FAILED) {
        if (descriptor_ < 0) throw std::runtime_error(std::strerror(errno));
        mapping_ = ::mmap(nullptr, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor_, 0);
        if (mapping_ == MAP_FAILED) {
            const int saved_errno = errno;
            ::close(descriptor_);
            throw std::runtime_error(std::strerror(saved_errno));
        }
    }
    UioRegisters(const UioRegisters&) = delete;
    UioRegisters& operator=(const UioRegisters&) = delete;
    ~UioRegisters() { ::munmap(mapping_, 4096); ::close(descriptor_); }
    std::uint32_t read(unsigned offset) {
        const auto registers = static_cast<volatile std::uint32_t*>(mapping_);
        const auto word = registers[offset / sizeof(std::uint32_t)];
        // This C++ fence is not a portable device-memory barrier. The physical UIO
        // path needs target-specific mapping/order validation, especially on ARM.
        std::atomic_thread_fence(std::memory_order_seq_cst);
        return word;
    }
};

class SimulatedRegisters {
    std::uint64_t live_ = 0x1234ffffffff;
    std::uint64_t captured_ = 0;
public:
    std::uint32_t read(unsigned offset) {
        if (offset == 4) {
            captured_ = live_;
            live_ += 100;
            return static_cast<std::uint32_t>(captured_);
        }
        if (offset == 8) return static_cast<std::uint32_t>(captured_ >> 32);
        throw std::invalid_argument("unsupported simulated register");
    }
};

int main(int argc, char** argv) {
    try {
        if (argc == 2 && std::string(argv[1]) == "--simulate") {
            SimulatedRegisters registers;
            const auto ticks = timing::snapshot(registers);
            if (ticks != 0x1234ffffffffULL) throw std::runtime_error("torn simulated snapshot");
            std::cout << ticks << '\n';
        } else if (argc == 3 && std::string(argv[1]) == "--uio") {
            UioRegisters registers(argv[2]);
            std::cout << timing::snapshot(registers) << '\n';
        } else {
            std::cerr << "usage: timing_read --simulate | --uio /dev/uioN\n"; return 2;
        }
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
