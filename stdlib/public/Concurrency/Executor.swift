//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Swift

/// A service that can execute jobs.
@available(SwiftStdlib 5.1, *)
public protocol Executor: AnyObject, Sendable {

  // Since lack move-only type support in the SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY configuration
  // Do not deprecate the UnownedJob enqueue in that configuration just yet - as we cannot introduce the replacements.
  #if !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
  @available(SwiftStdlib 5.1, *)
  #endif // !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
  func enqueue(_ job: UnownedJob)

  // Cannot introduce these methods in SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
  // since it lacks move-only type support.
  #if !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
  @available(SwiftStdlib 5.9, *)
  @available(*, deprecated, message: "Implement 'enqueue(_: consuming ExecutorJob)' instead")
  func enqueue(_ job: consuming Job)
  #endif // !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY

  #if !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
  @available(SwiftStdlib 5.9, *)
  func enqueue(_ job: consuming ExecutorJob)
  #endif // !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY

  // The functions below could have been added to a separate protocol,
  // but doing that would then mean doing an `as?` cast in e.g.
  // enqueueOnGlobalExecutor (in ExecutorBridge.swift), which is
  // undesirable from a performance perspective.

  /// `true` if this is the main executor.
  @available(SwiftStdlib 6.2, *)
  var isMainExecutor: Bool { get }

  /// `true` if this Executor supports scheduling.
  ///
  /// This will default to false.  If you attempt to use the delayed
  /// enqueuing functions on an executor that does not support scheduling,
  /// the default executor will be used to do the scheduling instead,
  /// unless the default executor does not support scheduling in which
  /// case you will get a fatal error.
  @available(SwiftStdlib 6.2, *)
  var supportsScheduling: Bool { get }

  #if !$Embedded

  /// Enqueue a job to run after a specified delay.
  ///
  /// You need only implement one of the two enqueue functions here;
  /// the default implementation for the other will then call the one
  /// you have implemented.
  ///
  /// Parameters:
  ///
  /// - job:       The job to schedule.
  /// - after:     A `Duration` specifying the time after which the job
  ///              is to run.  The job will not be executed before this
  ///              time has elapsed.
  /// - tolerance: The maximum additional delay permissible before the
  ///              job is executed.  `nil` means no limit.
  /// - clock:     The clock used for the delay.
  @available(SwiftStdlib 6.2, *)
  func enqueue<C: Clock>(_ job: consuming ExecutorJob,
                         after delay: C.Duration,
                         tolerance: C.Duration?,
                         clock: C)

  /// Enqueue a job to run at a specified time.
  ///
  /// You need only implement one of the two enqueue functions here;
  /// the default implementation for the other will then call the one
  /// you have implemented.
  ///
  /// Parameters:
  ///
  /// - job:       The job to schedule.
  /// - at:        The `Instant` at which the job should run.  The job
  ///              will not be executed before this time.
  /// - tolerance: The maximum additional delay permissible before the
  ///              job is executed.  `nil` means no limit.
  /// - clock:     The clock used for the delay..
  @available(SwiftStdlib 6.2, *)
  func enqueue<C: Clock>(_ job: consuming ExecutorJob,
                         at instant: C.Instant,
                         tolerance: C.Duration?,
                         clock: C)

  #endif // !$Embedded
}

extension Executor {
  @available(SwiftStdlib 6.2, *)
  @usableFromInline
  internal var _isComplexEquality: Bool { false }
}

extension Executor where Self: Equatable {
  @available(SwiftStdlib 6.2, *)
  @usableFromInline
  internal var _isComplexEquality: Bool { true }
}

// Delay support
extension Executor {

  // This defaults to `false` so that existing third-party Executor
  // implementations will work as expected.
  @available(SwiftStdlib 6.2, *)
  public var isMainExecutor: Bool { false }

  // This defaults to `false` so that existing third-party TaskExecutor
  // implementations will work as expected.
  @available(SwiftStdlib 6.2, *)
  public var supportsScheduling: Bool { false }

  #if !$Embedded

  @available(SwiftStdlib 6.2, *)
  public func enqueue<C: Clock>(_ job: consuming ExecutorJob,
                                after delay: C.Duration,
                                tolerance: C.Duration? = nil,
                                clock: C) {
    if !supportsScheduling {
      fatalError("Executor \(self) does not support scheduling")
    }

    // If you crash here with a mutual recursion, it's because you didn't
    // implement one of these two functions
    enqueue(job, at: clock.now.advanced(by: delay),
            tolerance: tolerance, clock: clock)
  }

  @available(SwiftStdlib 6.2, *)
  public func enqueue<C: Clock>(_ job: consuming ExecutorJob,
                                at instant: C.Instant,
                                tolerance: C.Duration? = nil,
                                clock: C) {
    if !supportsScheduling {
      fatalError("Executor \(self) does not support scheduling")
    }

    // If you crash here with a mutual recursion, it's because you didn't
    // implement one of these two functions
    enqueue(job, after: clock.now.duration(to: instant),
            tolerance: tolerance, clock: clock)
  }

  #endif // !$Embedded
}

/// A service that executes jobs.
///
/// ### Custom Actor Executors
/// By default, all actor types execute tasks on a shared global concurrent pool.
/// The global pool does not guarantee any thread (or dispatch queue) affinity,
/// so actors are free to use different threads as they execute tasks.
///
/// > The runtime may perform various optimizations to minimize un-necessary
/// > thread switching.
///
/// Sometimes it is important to be able to customize the execution behavior
///  of an actor. For example, when an actor is known to perform heavy blocking
/// operations (such as IO), and we would like to keep this work *off* the global
/// shared pool, as blocking it may prevent other actors from being responsive.
///
/// You can implement a custom executor, by conforming a type to the
/// ``SerialExecutor`` protocol, and implementing the ``enqueue(_:)`` method.
///
/// Once implemented, you can configure an actor to use such executor by
/// implementing the actor's ``Actor/unownedExecutor`` computed property.
/// For example, you could accept an executor in the actor's initializer,
/// store it as a variable (in order to retain it for the duration of the
/// actor's lifetime), and return it from the `unownedExecutor` computed
/// property like this:
///
/// ```
/// actor MyActor {
///   let myExecutor: MyExecutor
///
///   // accepts an executor to run this actor on.
///   init(executor: MyExecutor) {
///     self.myExecutor = executor
///   }
///
///   nonisolated var unownedExecutor: UnownedSerialExecutor {
///     self.myExecutor.asUnownedSerialExecutor()
///   }
/// }
/// ```
///
/// It is also possible to use a form of shared executor, either created as a
/// global or static property, which you can then re-use for every MyActor
/// instance:
///
/// ```
/// actor MyActor {
///   // Serial executor reused by *all* instances of MyActor!
///   static let sharedMyActorsExecutor = MyExecutor() // implements SerialExecutor
///
///
///   nonisolated var unownedExecutor: UnownedSerialExecutor {
///     Self.sharedMyActorsExecutor.asUnownedSerialExecutor()
///   }
/// }
/// ```
///
/// In the example above, *all* "MyActor" instances would be using the same
/// serial executor, which would result in only one of such actors ever being
/// run at the same time. This may be useful if some of your code has some
/// "specific thread" requirement when interoperating with non-Swift runtimes
/// for example.
///
/// Since the ``UnownedSerialExecutor`` returned by the `unownedExecutor`
/// property *does not* retain the executor, you must make sure the lifetime of
/// it extends beyond the lifetime of any actor or task using it, as otherwise
/// it may attempt to enqueue work on a released executor object, causing a crash.
/// The executor returned by unownedExecutor *must* always be the same object,
/// and returning different executors can lead to unexpected behavior.
///
/// Alternatively, you can also use existing serial executor implementations,
/// such as Dispatch's `DispatchSerialQueue` or others.
@available(SwiftStdlib 5.1, *)
public protocol SerialExecutor: Executor {
  // This requirement is repeated here as a non-override so that we
  // get a redundant witness-table entry for it.  This allows us to
  // avoid drilling down to the base conformance just for the basic
  // work-scheduling operation.
  @_nonoverride
  #if !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
  @available(SwiftStdlib 5.1, *)
  @available(*, deprecated, message: "Implement 'enqueue(_: consuming ExecutorJob)' instead")
  #endif // !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
  func enqueue(_ job: UnownedJob)

  #if !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
  // This requirement is repeated here as a non-override so that we
  // get a redundant witness-table entry for it.  This allows us to
  // avoid drilling down to the base conformance just for the basic
  // work-scheduling operation.
  @_nonoverride
  @available(SwiftStdlib 5.9, *)
  @available(*, deprecated, message: "Implement 'enqueue(_: consuming ExecutorJob)' instead")
  func enqueue(_ job: consuming Job)
  #endif // !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY

  #if !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
  // This requirement is repeated here as a non-override so that we
  // get a redundant witness-table entry for it.  This allows us to
  // avoid drilling down to the base conformance just for the basic
  // work-scheduling operation.
  @_nonoverride
  @available(SwiftStdlib 5.9, *)
  func enqueue(_ job: consuming ExecutorJob)
  #endif // !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY

  /// Convert this executor value to the optimized form of borrowed
  /// executor references.
  @unsafe
  func asUnownedSerialExecutor() -> UnownedSerialExecutor

  /// If this executor has complex equality semantics, and the runtime needs to
  /// compare two executors, it will first attempt the usual pointer-based
  /// equality / check, / and if it fails it will compare the types of both
  /// executors, if they are the same, / it will finally invoke this method,
  ///  in an
  /// attempt to let the executor itself decide / if this and the `other`
  /// executor represent the same serial, exclusive, isolation context.
  ///
  /// This method must be implemented with great care, as wrongly returning
  /// `true` would allow / code from a different execution context (e.g. thread)
  /// to execute code which was intended to be isolated by another actor.
  ///
  /// This check is not used when performing executor switching.
  ///
  /// This check is used when performing ``Actor/assertIsolated()``,
  /// ``Actor/preconditionIsolated()``, ``Actor/assumeIsolated()`` and similar
  /// APIs which assert about the same "exclusive serial execution context".
  ///
  /// - Parameter other: the executor to compare with.
  /// - Returns: `true`, if `self` and the `other` executor actually are
  ///            mutually exclusive and it is safe–from a concurrency
  ///            perspective–to execute code assuming one on the other.
  @available(SwiftStdlib 5.9, *)
  func isSameExclusiveExecutionContext(other: Self) -> Bool

  /// Last resort "fallback" isolation check, called when the concurrency runtime
  /// is comparing executors e.g. during ``assumeIsolated()`` and is unable to prove
  /// serial equivalence between the expected (this object), and the current executor.
  ///
  /// During executor comparison, the Swift concurrency runtime attempts to compare
  /// current and expected executors in a few ways (including "complex" equality
  /// between executors (see ``isSameExclusiveExecutionContext(other:)``), and if all
  /// those checks fail, this method is invoked on the expected executor.
  ///
  /// This method MUST crash if it is unable to prove that the current execution
  /// context belongs to this executor. At this point usual executor comparison would
  /// have already failed, though the executor may have some external tracking of
  /// threads it owns, and may be able to prove isolation nevertheless.
  ///
  /// A default implementation is provided that unconditionally crashes the
  /// program, and prevents calling code from proceeding with potentially
  /// not thread-safe execution.
  ///
  /// - Warning: This method must crash and halt program execution if unable
  ///     to prove the isolation of the calling context.
  @available(SwiftStdlib 6.0, *)
  func checkIsolated()

  @available(SwiftStdlib 6.2, *)
  func isIsolatingCurrentContext() -> Bool

}

@available(SwiftStdlib 6.0, *)
extension SerialExecutor {

  @available(SwiftStdlib 6.2, *)
  public var isMainExecutor: Bool { return MainActor.executor._isSameExecutor(self) }

  @available(SwiftStdlib 6.0, *)
  public func checkIsolated() {
    #if !$Embedded
    fatalError("Unexpected isolation context, expected to be executing on \(Self.self)")
    #else
    Builtin.int_trap()
    #endif
  }

  @available(SwiftStdlib 6.2, *)
  internal func _isSameExecutor(_ rhs: some SerialExecutor) -> Bool {
    if rhs === self {
      return true
    }
    if let rhs = rhs as? Self {
      return isSameExclusiveExecutionContext(other: rhs)
    }
    return false
  }
}

@available(SwiftStdlib 6.2, *)
extension SerialExecutor {

  @available(SwiftStdlib 6.2, *)
  public func isIsolatingCurrentContext() -> Bool {
    self.checkIsolated()
    return true
  }
}

/// An executor that may be used as preferred executor by a task.
///
/// ### Impact of setting a task executor preference
/// By default, without setting a task executor preference, nonisolated
/// asynchronous functions, as well as methods declared on default actors --
/// that is actors which do not require a specific executor -- execute on
/// Swift's default global concurrent executor. This is an executor shared by
/// the entire runtime to execute any work which does not have strict executor
/// requirements.
///
/// By setting a task executor preference, either with a
/// ``withTaskExecutorPreference(_:operation:)``, creating a task with a preference
/// (`Task(executorPreference:)`, or `group.addTask(executorPreference:)`), the task and all of its child
/// tasks (unless a new preference is set) will be preferring to execute on
/// the provided task executor.
///
/// Unstructured tasks do not inherit the task executor.
@available(SwiftStdlib 6.0, *)
public protocol TaskExecutor: Executor {
  // This requirement is repeated here as a non-override so that we
  // get a redundant witness-table entry for it.  This allows us to
  // avoid drilling down to the base conformance just for the basic
  // work-scheduling operation.
  @_nonoverride
  func enqueue(_ job: UnownedJob)

  #if !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
  // This requirement is repeated here as a non-override so that we
  // get a redundant witness-table entry for it.  This allows us to
  // avoid drilling down to the base conformance just for the basic
  // work-scheduling operation.
  @_nonoverride
  @available(*, deprecated, message: "Implement 'enqueue(_: consuming ExecutorJob)' instead")
  func enqueue(_ job: consuming Job)
  #endif // !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY

  #if !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
  // This requirement is repeated here as a non-override so that we
  // get a redundant witness-table entry for it.  This allows us to
  // avoid drilling down to the base conformance just for the basic
  // work-scheduling operation.
  @_nonoverride
  func enqueue(_ job: consuming ExecutorJob)
  #endif // !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY

  func asUnownedTaskExecutor() -> UnownedTaskExecutor
}

@available(SwiftStdlib 6.0, *)
extension TaskExecutor {
  public func asUnownedTaskExecutor() -> UnownedTaskExecutor {
    UnownedTaskExecutor(ordinary: self)
  }
}

#if !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
@available(SwiftStdlib 5.9, *)
extension Executor {

  // Delegation goes like this:
  // Unowned Job -> Executor Job -> Job -> ---||---

  public func enqueue(_ job: UnownedJob) {
    self.enqueue(ExecutorJob(job))
  }

  public func enqueue(_ job: consuming ExecutorJob) {
    self.enqueue(Job(job))
  }

  public func enqueue(_ job: consuming Job) {
    self.enqueue(UnownedJob(job))
  }
}
#endif // !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY

@available(SwiftStdlib 5.9, *)
extension SerialExecutor {
  @available(SwiftStdlib 5.9, *)
  public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
    unsafe UnownedSerialExecutor(ordinary: self)
  }
}

@available(SwiftStdlib 5.9, *)
extension SerialExecutor {

  @available(SwiftStdlib 5.9, *)
  public func isSameExclusiveExecutionContext(other: Self) -> Bool {
    return self === other
  }

}

@available(SwiftStdlib 6.2, *)
extension SerialExecutor where Self: Equatable {

  @available(SwiftStdlib 6.2, *)
  public func isSameExclusiveExecutionContext(other: Self) -> Bool {
    return self == other
  }

}

/// An executor that is backed by some kind of run loop.
///
/// The idea here is that some executors may work by running a loop
/// that processes events of some sort; we want a way to enter that loop,
/// and we would also like a way to trigger the loop to exit.
@available(SwiftStdlib 6.2, *)
public protocol RunLoopExecutor: Executor {
  /// Run the executor's run loop.
  ///
  /// This method will synchronously block the calling thread.  Nested calls to
  /// `run()` may be permitted, however it is not permitted to call `run()` on a
  /// single executor instance from more than one thread.
  func run() throws

  /// Run the executor's run loop until a condition is satisfied.
  ///
  /// Not every `RunLoopExecutor` will support this method; you must not call
  /// it unless you *know* that it is supported.  The default implementation
  /// generates a fatal error.
  ///
  /// Parameters:
  ///
  /// - until condition: A closure that returns `true` if the run loop should
  ///                    stop.
  func run(until condition: () -> Bool) throws

  /// Signal to the run loop to stop running and return.
  ///
  /// This method may be called from the same thread that is in the `run()`
  /// method, or from some other thread.  It will not wait for the run loop to
  /// stop; calling this method simply signals that the run loop *should*, as
  /// soon as is practicable, stop the innermost `run()` invocation and make
  /// that `run()` invocation return.
  func stop()
}

@available(SwiftStdlib 6.2, *)
extension RunLoopExecutor {

  public func run(until condition: () -> Bool) throws {
    fatalError("run(until condition:) not supported on this executor")
  }

}


/// Represents an event; we don't want to allocate, so we can't use
/// a protocol here and use `any Event`.  Instead of doing that, wrap
/// an `Int` (which is pointer-sized) in a `struct`.
@available(SwiftStdlib 6.2, *)
public struct ExecutorEvent: Identifiable, Comparable, Sendable {
  public typealias ID = Int

  public var id: Self.ID

  public init(id: Self.ID) {
    self.id = id
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    return lhs.id < rhs.id
  }
  public static func == (lhs: Self, rhs: Self) -> Bool {
    return lhs.id == rhs.id
  }
}


/// An executor that has support for coalesced events.
@available(SwiftStdlib 6.2, *)
public protocol EventableExecutor {

  /// Register a new event with a given handler.
  ///
  /// Notifying the executor of the event will cause the executor to
  /// execute the handler, however the executor is free to coalesce multiple
  /// event notifications, and is also free to execute the handler at a time
  /// of its choosing.
  ///
  /// Parameters
  ///
  /// - handler:  The handler to call when the event fires.
  ///
  /// Returns a new opaque `Event`.
  func registerEvent(handler: @escaping () -> ()) -> ExecutorEvent

  /// Deregister the given event.
  ///
  /// After this function returns, there will be no further executions of the
  /// handler for the given event.
  func deregister(event: ExecutorEvent)

  /// Notify the executor of an event.
  ///
  /// This will trigger, at some future point, the execution of the associated
  /// event handler.  Prior to that time, multiple calls to `notify` may be
  /// coalesced and result in a single invocation of the event handler.
  func notify(event: ExecutorEvent)

}


/// The main executor must conform to these three protocols; we have to
/// make this a protocol for compatibility with Embedded Swift.
@available(SwiftStdlib 6.2, *)
public protocol MainExecutor: RunLoopExecutor, SerialExecutor, EventableExecutor {
}


/// An ExecutorFactory is used to create the default main and task
/// executors.
@available(SwiftStdlib 6.2, *)
public protocol ExecutorFactory {
  /// Constructs and returns the main executor, which is started implicitly
  /// by the `async main` entry point and owns the "main" thread.
  static var mainExecutor: any MainExecutor { get }

  /// Constructs and returns the default or global executor, which is the
  /// default place in which we run tasks.
  static var defaultExecutor: any TaskExecutor { get }
}

@available(SwiftStdlib 6.2, *)
@_silgen_name("swift_createExecutors")
public func _createExecutors<F: ExecutorFactory>(factory: F.Type) {
  MainActor._executor = factory.mainExecutor
  Task._defaultExecutor = factory.defaultExecutor
}

extension MainActor {
  @available(SwiftStdlib 6.2, *)
  static var _executor: (any MainExecutor)? = nil

  /// The main executor, which is started implicitly by the `async main`
  /// entry point and owns the "main" thread.
  ///
  /// Attempting to set this after the first `enqueue` on the main
  /// executor is a fatal error.
  @available(SwiftStdlib 6.2, *)
  public static var executor: any MainExecutor {
    if _executor == nil {
      _executor = PlatformExecutorFactory.mainExecutor
    }
    return _executor!
  }
}

extension Task where Success == Never, Failure == Never {
  @available(SwiftStdlib 6.2, *)
  static var _defaultExecutor: (any TaskExecutor)? = nil

  /// The default or global executor, which is the default place in which
  /// we run tasks.
  ///
  /// Attempting to set this after the first `enqueue` on the global
  /// executor is a fatal error.
  @available(SwiftStdlib 6.2, *)
  public static var defaultExecutor: any TaskExecutor {
    if _defaultExecutor == nil {
      _defaultExecutor = PlatformExecutorFactory.defaultExecutor
    }
    return _defaultExecutor!
  }
}

extension Task where Success == Never, Failure == Never {
  /// Get the current executor; this is the executor that the currently
  /// executing task is executing on.
  @available(SwiftStdlib 6.2, *)
  @_unavailableInEmbedded
  public static var currentExecutor: (any Executor)? {
    if let taskExecutor = _getPreferredTaskExecutor().asTaskExecutor() {
      return taskExecutor
    } else if let activeExecutor = _getActiveExecutor().asSerialExecutor() {
      return activeExecutor
    } else if let taskExecutor = _getCurrentTaskExecutor().asTaskExecutor() {
      return taskExecutor
    }
    return nil
  }
}


/// An unowned reference to a serial executor (a `SerialExecutor`
/// value).
///
/// This is an optimized type used internally by the core scheduling
/// operations.  It is an unowned reference to avoid unnecessary
/// reference-counting work even when working with actors abstractly.
/// Generally there are extra constraints imposed on core operations
/// in order to allow this.  For example, keeping an actor alive must
/// also keep the actor's associated executor alive; if they are
/// different objects, the executor must be referenced strongly by the
/// actor.
@available(SwiftStdlib 5.1, *)
@unsafe
@frozen
public struct UnownedSerialExecutor: Sendable {
  @usableFromInline
  internal var executor: Builtin.Executor

  /// SPI: Do not use. Cannot be marked @_spi, since we need to use it from Distributed module
  /// which needs to reach for this from an @_transparent function which prevents @_spi use.
  @available(SwiftStdlib 5.9, *)
  public var _executor: Builtin.Executor {
    unsafe self.executor
  }

  @inlinable
  public init(_ executor: Builtin.Executor) {
    unsafe self.executor = executor
  }

  @inlinable
  public init<E: SerialExecutor>(ordinary executor: __shared E) {
    unsafe self.executor = Builtin.buildOrdinarySerialExecutorRef(executor)
  }

  /// Opts the executor into complex "same exclusive execution context" equality checks.
  ///
  /// This means what when asserting or assuming executors, and the current and expected
  /// executor are not the same instance (by object equality), the runtime may invoke
  /// `isSameExclusiveExecutionContext` in order to compare the executors for equality.
  ///
  /// Implementing such complex equality can be useful if multiple executor instances
  /// actually use the same underlying serialization context and can be therefore
  /// safely treated as the same serial exclusive execution context (e.g. multiple
  /// dispatch queues targeting the same serial queue).
  @available(SwiftStdlib 5.9, *)
  @inlinable
  public init<E: SerialExecutor>(complexEquality executor: __shared E) {
    unsafe self.executor = Builtin.buildComplexEqualitySerialExecutorRef(executor)
  }

  /// Automatically opt-in to complex equality semantics if the Executor
  /// implements `Equatable`.
  @available(SwiftStdlib 6.2, *)
  @inlinable
  public init<E: SerialExecutor>(_ executor: __shared E) {
    if executor._isComplexEquality {
      self.executor = Builtin.buildComplexEqualitySerialExecutorRef(executor)
    } else {
      self.executor = Builtin.buildOrdinarySerialExecutorRef(executor)
    }
  }

  @_spi(ConcurrencyExecutors)
  @available(SwiftStdlib 5.9, *)
  public var _isComplexEquality: Bool {
    unsafe _executor_isComplexEquality(self)
  }

  @available(SwiftStdlib 6.2, *)
  public func asSerialExecutor() -> (any SerialExecutor)? {
    return unsafeBitCast(executor, to: (any SerialExecutor)?.self)
  }
}


@available(SwiftStdlib 6.0, *)
@frozen
public struct UnownedTaskExecutor: Sendable {
  @usableFromInline
  internal var executor: Builtin.Executor

  /// SPI: Do not use. Cannot be marked @_spi, since we need to use it from Distributed module
  /// which needs to reach for this from an @_transparent function which prevents @_spi use.
  @available(SwiftStdlib 6.0, *)
  public var _executor: Builtin.Executor {
    self.executor
  }

  @inlinable
  public init(_ executor: Builtin.Executor) {
    self.executor = executor
  }

  @inlinable
  public init<E: TaskExecutor>(ordinary executor: __shared E) {
    self.executor = Builtin.buildOrdinaryTaskExecutorRef(executor)
  }

  @available(SwiftStdlib 6.2, *)
  @inlinable
  public init<E: TaskExecutor>(_ executor: __shared E) {
    self.executor = Builtin.buildOrdinaryTaskExecutorRef(executor)
  }

  @available(SwiftStdlib 6.2, *)
  public func asTaskExecutor() -> (any TaskExecutor)? {
    return unsafeBitCast(executor, to: (any TaskExecutor)?.self)
  }
}

@available(SwiftStdlib 6.0, *)
extension UnownedTaskExecutor: Equatable {
  @inlinable
  public static func == (_ lhs: UnownedTaskExecutor, _ rhs: UnownedTaskExecutor) -> Bool {
    unsafe unsafeBitCast(lhs.executor, to: (Int, Int).self) == unsafeBitCast(rhs.executor, to: (Int, Int).self)
  }
}

/// Returns either `true` or will CRASH if called from a different executor
/// than the passed `executor`.
///
/// This method will attempt to verify the current executor against `executor`,
/// and as a last-resort call through to `SerialExecutor.checkIsolated`.
///
/// This method will never return `false`. It either can verify we're on the
/// correct executor, or will crash the program. It should be used in
/// isolation correctness guaranteeing APIs.
///
/// Generally, Swift programs should be constructed such that it is statically
/// known that a specific executor is used, for example by using global actors or
/// custom executors. However, in some APIs it may be useful to provide an
/// additional runtime check for this, especially when moving towards Swift
/// concurrency from other runtimes which frequently use such assertions.
///
/// - Parameter executor: The expected executor.
@_spi(ConcurrencyExecutors)
@available(SwiftStdlib 5.9, *)
@_silgen_name("swift_task_isOnExecutor") // This function will CRASH rather than return `false`!
public func _taskIsOnExecutor<Executor: SerialExecutor>(_ executor: Executor) -> Bool

@_spi(ConcurrencyExecutors)
@available(SwiftStdlib 5.9, *)
@_silgen_name("swift_executor_isComplexEquality")
public func _executor_isComplexEquality(_ executor: UnownedSerialExecutor) -> Bool

@available(SwiftStdlib 5.1, *)
@_transparent
public // COMPILER_INTRINSIC
func _checkExpectedExecutor(_filenameStart: Builtin.RawPointer,
                            _filenameLength: Builtin.Word,
                            _filenameIsASCII: Builtin.Int1,
                            _line: Builtin.Word,
                            _executor: Builtin.Executor) {
  if _taskIsCurrentExecutor(_executor) {
    return
  }

  _reportUnexpectedExecutor(
      _filenameStart, _filenameLength, _filenameIsASCII, _line, _executor)
}

/// Primarily a debug utility.
///
/// If the passed in ExecutorJob is a Task, returns the complete 64bit TaskId,
/// otherwise returns only the job's 32bit Id.
///
/// - Returns: the Id stored in this ExecutorJob or Task, for purposes of debug printing
@available(SwiftStdlib 5.9, *)
@_silgen_name("swift_task_getJobTaskId")
internal func _getJobTaskId(_ job: UnownedJob) -> UInt64

@available(SwiftStdlib 5.9, *)
@_silgen_name("_task_serialExecutor_isSameExclusiveExecutionContext")
internal func _task_serialExecutor_isSameExclusiveExecutionContext<E>(current currentExecutor: E, executor: E) -> Bool
    where E: SerialExecutor {
  currentExecutor.isSameExclusiveExecutionContext(other: executor)
}

@available(SwiftStdlib 6.0, *)
@_silgen_name("_task_serialExecutor_checkIsolated")
internal func _task_serialExecutor_checkIsolated<E>(executor: E)
    where E: SerialExecutor {
  executor.checkIsolated()
}

@available(SwiftStdlib 6.2, *)
@_silgen_name("_task_serialExecutor_isIsolatingCurrentContext")
internal func _task_serialExecutor_isIsolatingCurrentContext<E>(executor: E) -> Bool
    where E: SerialExecutor {
  return executor.isIsolatingCurrentContext()
}

/// Obtain the executor ref by calling the executor's `asUnownedSerialExecutor()`.
/// The obtained executor ref will have all the user-defined flags set on the executor.
@available(SwiftStdlib 5.9, *)
@_silgen_name("_task_serialExecutor_getExecutorRef")
internal func _task_serialExecutor_getExecutorRef<E>(_ executor: E) -> Builtin.Executor
    where E: SerialExecutor {
  return unsafe executor.asUnownedSerialExecutor().executor
}

/// Obtain the executor ref by calling the executor's `asUnownedTaskExecutor()`.
/// The obtained executor ref will have all the user-defined flags set on the executor.
@_unavailableInEmbedded
@available(SwiftStdlib 6.0, *)
@_silgen_name("_task_taskExecutor_getTaskExecutorRef")
internal func _task_taskExecutor_getTaskExecutorRef<E>(_ taskExecutor: E) -> Builtin.Executor
    where E: TaskExecutor {
  return taskExecutor.asUnownedTaskExecutor().executor
}

// Used by the concurrency runtime
@available(SwiftStdlib 5.1, *)
@_silgen_name("_swift_task_enqueueOnExecutor")
internal func _enqueueOnExecutor<E>(job unownedJob: UnownedJob, executor: E)
where E: SerialExecutor {
  #if !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
  if #available(SwiftStdlib 5.9, *) {
    executor.enqueue(ExecutorJob(context: unownedJob._context))
  } else {
    executor.enqueue(unownedJob)
  }
  #else // SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
  executor.enqueue(unownedJob)
  #endif // !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
}

@_unavailableInEmbedded
@available(SwiftStdlib 6.0, *)
@_silgen_name("_swift_task_enqueueOnTaskExecutor")
internal func _enqueueOnTaskExecutor<E>(job unownedJob: UnownedJob, executor: E) where E: TaskExecutor {
  #if !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
  executor.enqueue(ExecutorJob(context: unownedJob._context))
  #else // SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
  executor.enqueue(unownedJob)
  #endif // !SWIFT_STDLIB_TASK_TO_THREAD_MODEL_CONCURRENCY
}

#if SWIFT_CONCURRENCY_USES_DISPATCH
// This must take a DispatchQueueShim, not something like AnyObject,
// or else SILGen will emit a retain/release in unoptimized builds,
// which won't work because DispatchQueues aren't actually
// Swift-retainable.
@available(SwiftStdlib 5.1, *)
@_silgen_name("swift_task_enqueueOnDispatchQueue")
internal func _enqueueOnDispatchQueue(_ job: UnownedJob,
                                      queue: DispatchQueueShim)

/// Used by the runtime solely for the witness table it produces.
/// FIXME: figure out some way to achieve that which doesn't generate
/// all the other metadata
///
/// Expected to work for any primitive dispatch queue; note that this
/// means a dispatch_queue_t, which is not the same as DispatchQueue
/// on platforms where that is an instance of a wrapper class.
@available(SwiftStdlib 5.1, *)
internal final class DispatchQueueShim: @unchecked Sendable, SerialExecutor {
  func enqueue(_ job: UnownedJob) {
    _enqueueOnDispatchQueue(job, queue: self)
  }

  func asUnownedSerialExecutor() -> UnownedSerialExecutor {
    return unsafe UnownedSerialExecutor(ordinary: self)
  }
}
#endif // SWIFT_CONCURRENCY_USES_DISPATCH

@available(SwiftStdlib 6.1, *)
@_silgen_name("swift_task_deinitOnExecutor")
@usableFromInline
internal func _deinitOnExecutor(_ object: __owned AnyObject,
                                _ work: @convention(thin) (__owned AnyObject) -> Void,
                                _ executor: Builtin.Executor,
                                _ flags: Builtin.Word)
