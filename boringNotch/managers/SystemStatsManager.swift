//
//  SystemStatsManager.swift
//  boringNotch
//
//  Samples CPU and memory usage every 2 seconds via Mach (host_processor_info /
//  host_statistics64) and keeps the .stats sneak peek visible while running.
//

import Foundation

@MainActor
final class SystemStatsManager: ObservableObject {
    static let shared = SystemStatsManager()

    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Double = 0

    private var pollTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard pollTask == nil else {
            BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .stats, duration: 3.0)
            return
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.sample()
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .stats, duration: 3.0)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func sample() {
        cpuUsage = cpuLoad()
        memoryUsage = memoryLoad()
    }

    private func cpuLoad() -> Double {
        var processorCount: mach_msg_type_number_t = 0
        var processorInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &processorInfo, &infoCount)
        guard result == KERN_SUCCESS, let info = processorInfo else { return cpuUsage }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<Int32>.stride)) }
        var used: Double = 0
        var total: Double = 0
        for core in 0..<Int(processorCount) {
            let base = core * Int(CPU_STATE_MAX)
            let busy = Double(info[base + Int(CPU_STATE_USER)]) + Double(info[base + Int(CPU_STATE_SYSTEM)]) + Double(info[base + Int(CPU_STATE_NICE)])
            let idle = Double(info[base + Int(CPU_STATE_IDLE)])
            if busy + idle > 0 {
                used += busy
                total += busy + idle
            }
        }
        return total > 0 ? used / total * 100 : cpuUsage
    }

    private func memoryLoad() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let port = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(port, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return memoryUsage }
        let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count)
        let available = Double(stats.free_count + stats.purgeable_count)
        let total = used + available
        return total > 0 ? used / total * 100 : memoryUsage
    }
}

#if DEBUG
@MainActor
enum SystemStatsManagerTests {
    static func run() {
        let m = SystemStatsManager.shared
        m.sample()
        assert(m.cpuUsage >= 0 && m.cpuUsage <= 100, "cpuUsage out of range: \(m.cpuUsage)")
        assert(m.memoryUsage >= 0 && m.memoryUsage <= 100, "memoryUsage out of range: \(m.memoryUsage)")
        print("SystemStatsManager self-check passed: cpu=\(m.cpuUsage)%, mem=\(m.memoryUsage)%")
    }
}
#endif
