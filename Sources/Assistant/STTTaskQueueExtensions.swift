//
//  File.swift
//  
//
//  Created by Tomas Green on 2021-06-07.
//

import Foundation
import Combine
import STT

public class STTTask : QueueTask {
    public let id = UUID()
    let endSubject = PassthroughSubject<Void, Never>()
    public var end:AnyPublisher<Void,Never> {
        return endSubject.eraseToAnyPublisher()
    }
    weak var service: STT?
    private var mode:STTMode
    private var publishers = Set<AnyCancellable>()
    private var paused = false
    public init(service:STT, mode:STTMode = .unspecified) {
        self.service = service
        self.mode = mode
    }
    public func run(){
        if paused {
            self.continue()
            return
        }
        guard let service = service else {
            tearDown()
            return
        }
        var started:Bool = false
        service.mode = mode
        service.$status.sink { [weak self] status in
            guard let this = self else {
                return
            }
            if status == .unavailable || (started && status == .idle) {
                if this.paused == false {
                    this.tearDown()
                }
            } else {
                started = true
            }
        }.store(in: &publishers)
        service.start()
    }
    public func interrupt() {
        tearDown()
    }
    public func pause() {
        paused = true
        service?.stop()
    }
    public func `continue`() {
        paused = false
        service?.start()
    }
    func tearDown() {
        endSubject.send()
        endSubject.send(completion: .finished)
        service?.stop()
        service = nil
        publishers.removeAll()
    }
}
public extension STT {
    func task(with mode:STTMode = .unspecified) -> STTTask {
        return STTTask(service: self, mode: mode)
    }
}
public extension TaskQueue {
    func queue(_ mode:STTMode = .unspecified, using stt:STT) {
        queue(STTTask(service: stt, mode: mode))
    }
    func interrupt(with mode:STTMode = .unspecified, using stt:STT) {
        interrupt(with: STTTask(service: stt, mode: mode))
    }
    func interject(with mode:STTMode = .unspecified, using stt:STT) {
        interject(with: STTTask(service: stt, mode: mode))
    }
}
