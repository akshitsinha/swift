// RUN: %target-swift-emit-silgen %s | %FileCheck %s


// CHECK: sil [ossa] @$s29mangling_predates_concurrency16excitingFunction5value4bodyyycx_yycSgtlF : $@convention(thin) <T where T : Sendable> (@in_guaranteed T, @guaranteed Optional<@Sendable @callee_guaranteed () -> ()>) -> @owned @callee_guaranteed () -> ()
@_predatesConcurrency
public func excitingFunction<T: Sendable>(value: T, body: (@Sendable () -> Void)?) -> (@MainActor () -> Void) {
  { }
}
