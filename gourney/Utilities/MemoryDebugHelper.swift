// Utils/MemoryDebugHelper.swift
// Memory monitoring and debugging utility

import Foundation

class MemoryDebugHelper {
    static let shared = MemoryDebugHelper()
    
    private var timer: Timer?
    private var isMonitoring = false
    
    private init() {}
    
    // MARK: - Memory Reporting
    
    func logMemory(tag: String = "") {
        let memoryMB = getMemoryUsage()
        let prefix = tag.isEmpty ? "💾 Memory" : "💾 Memory [\(tag)]"
        print("\(prefix): \(String(format: "%.1f", memoryMB)) MB")
    }
    
    private func getMemoryUsage() -> Double {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(taskInfo.resident_size) / 1024.0 / 1024.0
        } else {
            return 0
        }
    }
    
    // MARK: - Continuous Monitoring
    
    func startMonitoring(interval: TimeInterval = 3.0) {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        print("🔍 [Memory Monitor] Starting (every \(interval)s)")
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.logMemory(tag: "Monitor")
        }
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        print("🛑 [Memory Monitor] Stopped")
    }
}
