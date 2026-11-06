//! Consolidated FreeRTOS Kernel Abstraction for Zig
//!
//! Provides a unified, zero-overhead Zig interface to FreeRTOS across:
//! - ESP-IDF FreeRTOS (SMP-capable RISC-V / Xtensa)
//! - Standard FreeRTOS (ARM Cortex-M / RISC-V freestanding)
//! - Host Testing (macOS/Linux): Native mock test execution without C RTOS dependency

pub const types = @import("types.zig");
pub const task = @import("task.zig");
pub const queue = @import("queue.zig");
pub const mutex = @import("mutex.zig");
pub const critical = @import("critical.zig");

// Direct Type Aliases
pub const BaseType_t = types.BaseType_t;
pub const UBaseType_t = types.UBaseType_t;
pub const TickType_t = types.TickType_t;
pub const StackType_t = types.StackType_t;
pub const TaskHandle_t = types.TaskHandle_t;
pub const QueueHandle_t = types.QueueHandle_t;
pub const SemaphoreHandle_t = types.SemaphoreHandle_t;

pub const StaticTask_t = types.StaticTask_t;
pub const StaticQueue_t = types.StaticQueue_t;
pub const TaskFunction_t = types.TaskFunction_t;

pub const pdTRUE = types.pdTRUE;
pub const pdFALSE = types.pdFALSE;
pub const pdPASS = types.pdPASS;
pub const pdFAIL = types.pdFAIL;
pub const portMAX_DELAY = types.portMAX_DELAY;

pub const TICK_RATE_HZ = types.TICK_RATE_HZ;
pub const MINIMAL_STACK_SIZE = types.MINIMAL_STACK_SIZE;

pub const msToTicks = types.msToTicks;
pub const ticksToMs = types.ticksToMs;
pub const RtosError = types.RtosError;

// Scheduler States
pub const taskSCHEDULER_NOT_STARTED = types.taskSCHEDULER_NOT_STARTED;
pub const taskSCHEDULER_RUNNING = types.taskSCHEDULER_RUNNING;
pub const taskSCHEDULER_SUSPENDED = types.taskSCHEDULER_SUSPENDED;

// Queue Send Constants
pub const queueSEND_TO_BACK = types.queueSEND_TO_BACK;
pub const queueSEND_TO_FRONT = types.queueSEND_TO_FRONT;
pub const queueOVERWRITE = types.queueOVERWRITE;

// Notification Actions
pub const eNotifyAction = types.eNotifyAction;

// Kernel Primitives
pub const Task = task.Task;
pub const Queue = queue.Queue;
pub const StaticQueue = queue.StaticQueue;
pub const Mutex = mutex.Mutex;
pub const Semaphore = mutex.Semaphore;
pub const CriticalGuard = critical.CriticalGuard;

// Execution Control
pub const delay = task.delay;
pub const delayMs = task.delayMs;
pub const delayUntil = task.delayUntil;
pub const yield = task.yield;
pub const yieldFromISR = task.yieldFromISR;
pub const getTickCount = task.getTickCount;
pub const getSchedulerState = task.getSchedulerState;
pub const startScheduler = task.startScheduler;

// Notifications
pub const notifyGive = task.notifyGive;
pub const notifyWait = task.notifyWait;
pub const notifyFromISR = task.notifyFromISR;

// Critical Section
pub const enterCritical = critical.enterCritical;
pub const exitCritical = critical.exitCritical;

// Direct aliases for C-style portability
pub const vPortEnterCritical = enterCritical;
pub const vPortExitCritical = exitCritical;
pub const xTaskGenericNotify = task.notifyGive;
pub const xTaskGenericNotifyFromISR = task.notifyFromISR;
pub const xTaskGenericNotifyWait = task.notifyWait;

// ============================================================================
// Unit Tests
// ============================================================================

test {
    _ = types;
    _ = task;
    _ = queue;
    _ = mutex;
    _ = critical;
}
