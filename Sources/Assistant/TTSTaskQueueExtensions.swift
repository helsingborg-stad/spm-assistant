//
//  File.swift
//  
//
//  Created by Tomas Green on 2021-06-07.
//

import Foundation
import Combine
import TTS

public class TTSTask : QueueTask {
    public let id = UUID()
    let endSubject = PassthroughSubject<Void, Never>()
    public var end:AnyPublisher<Void,Never> {
        return endSubject.eraseToAnyPublisher()
    }
    private var publishers = Set<AnyCancellable>()
    private weak var service: TTS?
    private var utterances:[TTSUtterance]
    public init(service:TTS,utterance:TTSUtterance) {
        self.service = service
        self.utterances = [utterance]
    }
    public init(service:TTS,utterances:[TTSUtterance]) {
        self.service = service
        self.utterances = utterances
    }
    public func run(){
        guard let service = service else {
            tearDown()
            return
        }
        if service.disabled {
            tearDown()
            return
        }
        service.finished.sink { [weak self] u in
            guard let this = self else {
                return
            }
            this.utterances.removeAll { $0.id == u.id }
            if this.utterances.isEmpty {
                this.tearDown()
            }
        }.store(in: &publishers)
        service.play(utterances)
    }
    
    public func interrupt() {
        for u in utterances {
            service?.cancel(u)
        }
        tearDown()
    }
    
    public func pause() {
        service?.pause()
    }
    public func `continue`() {
        service?.continue()
    }
    public func tearDown() {
        utterances.removeAll()
        endSubject.send()
        endSubject.send(completion: .finished)
        service = nil
        publishers.removeAll()
    }
}
public extension TaskQueue {
    func queue(_ utterance:TTSUtterance, using tts:TTS) {
        queue(TTSTask(service: tts, utterance: utterance))
    }
    func queue(_ utterances:[TTSUtterance], using tts:TTS) {
        queue(utterances.map({ TTSTask(service: tts, utterance: $0) }))
    }
    func interrupt(with utterance:TTSUtterance, using tts:TTS) {
        interrupt(with: TTSTask(service: tts, utterance: utterance))
    }
    func interrupt(with utterances:[TTSUtterance], using tts:TTS) {
        interrupt(with: utterances.map({ TTSTask(service: tts, utterance: $0) }))
    }
    func interject(with utterance:TTSUtterance, using tts:TTS) {
        interject(with: TTSTask(service: tts, utterance: utterance))
    }
    func interject(with utterances:[TTSUtterance], using tts:TTS) {
        interject(with: utterances.map({ TTSTask(service: tts, utterance: $0) }))
    }
}
