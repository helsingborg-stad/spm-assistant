import Foundation
import AVFoundation
import SwiftUI
import Combine

import TTS
import STT
import TextTranslator
import Dragoman
import AudioSwitchboard

public class Assistant<Keys: NLKeyDefinition> : ObservableObject {
    public typealias CommandBridge = NLParser<Keys>
    public struct Settings {
        public let sttService: STTService
        public let ttsServices: [TTSService]
        public let supportedLocales:[Locale]
        public let mainLocale:Locale
        public let voiceCommands:CommandBridge.DB
        public let translator:TextTranslationService?
        public init(
            sttService: STTService,
            ttsServices: TTSService...,
            supportedLocales:[Locale],
            mainLocale:Locale? = nil,
            translator:TextTranslationService? = nil,
            voiceCommands:CommandBridge.DB? = nil
        ) {
            var supportedLocales = supportedLocales
            if supportedLocales.count == 0 {
                supportedLocales = [Locale.current]
            }
            self.sttService = sttService
            self.ttsServices = ttsServices
            self.supportedLocales = supportedLocales
            self.mainLocale = mainLocale ?? supportedLocales.first ?? Locale.current
            self.translator = translator
            self.voiceCommands = voiceCommands ?? Keys.createLocalizedDatabasePlist(languages: supportedLocales)
        }
    }

    
    private let sttStringPublisher = PassthroughSubject<String,Never>()
    private var publishers = Set<AnyCancellable>()
    private let commandBridge:CommandBridge
    
    public let stt: STT
    public let tts: TTS
    public let dragoman: Dragoman
    public let taskQueue = TaskQueue()
    public let supportedLocales:[Locale]
    public let mainLocale:Locale

    @Published public var locale:Locale {
        didSet {
            if let language = locale.languageCode {
                dragoman.language = language
            } else {
                debugPrint("unable to set dragoman language from \(locale)")
            }
            stt.locale = locale
            commandBridge.locale = locale
        }
    }
    @Published public var disabled:Bool = false {
        didSet {
            dragoman.disabled = disabled
            tts.disabled = disabled
            stt.disabled = disabled
        }
    }
    public init(settings:Settings) {
        self.supportedLocales = settings.supportedLocales
        self.mainLocale = settings.mainLocale
        self.dragoman = Dragoman(translationService:settings.translator, language:settings.mainLocale.languageCode ?? "en", supportedLanguages: settings.supportedLocales.compactMap({$0.languageCode}))
        self.stt = STT(service: settings.sttService)
        self.tts = TTS(settings.ttsServices)
        
        self.locale = settings.mainLocale
        commandBridge = CommandBridge(
            languages: supportedLocales,
            db: settings.voiceCommands,
            stringPublisher: sttStringPublisher.eraseToAnyPublisher()
        )
        commandBridge.locale = settings.mainLocale
        commandBridge.$contextualStrings.sink { [weak self] arr in
            self?.stt.contextualStrings = arr
        }.store(in: &publishers)
        
        stt.results.sink { [weak self] res in
            self?.sttStringPublisher.send(res.string)
        }.store(in: &publishers)
        
        dragoman.objectWillChange.sink {
            self.objectWillChange.send()
        }.store(in: &publishers)
        
        stt.locale = settings.mainLocale
        dragoman.language = settings.mainLocale.languageCode!
        commandBridge.locale = settings.mainLocale
        taskQueue.queue(.unspecified, using: stt)
    }
    private func string(for key:String) -> String {
        return dragoman.string(forKey: key)
    }
    private func utterance(for key:String, tag:String? = nil) -> TTSUtterance {
        return TTSUtterance(self.string(for: key), locale: locale, tag: tag)
    }
    // MARK: Task Queue
    @discardableResult public func interrupt(using utterances:[TTSUtterance], startSTT:Bool = true) -> TTSTask {
        let task = TTSTask(service: tts, utterances: utterances)
        taskQueue.interrupt(with: task)
        if startSTT {
            taskQueue.queue(.unspecified, using: stt)
        }
        return task
    }
    @discardableResult public func interrupt(using utterance:TTSUtterance, startSTT:Bool = true) -> TTSTask {
        let task = TTSTask(service: tts, utterance: utterance)
        taskQueue.interrupt(with: task)
        if startSTT {
            taskQueue.queue(STTTask(service: stt, mode: .unspecified))
        }
        return task
    }
    @discardableResult public func queue(utterance:TTSUtterance) -> TTSTask {
        let task = TTSTask(service: tts, utterance: utterance)
        taskQueue.queue(task)
        return task
    }
    @discardableResult public func queue(utterances:[TTSUtterance]) -> TTSTask {
        let task = TTSTask(service: tts, utterances: utterances)
        taskQueue.queue(task)
        return task
    }
    
    // MARK: Speaking strings
    @discardableResult public func speak(_ values:(String,String?)..., interrupt:Bool = true) -> [TTSUtterance] {
        var arr = [TTSUtterance]()
        for value in values {
            arr.append(self.utterance(for: value.0, tag: value.1))
        }
        if interrupt {
            self.interrupt(using: arr)
        } else {
            self.queue(utterances: arr)
        }
        return arr
    }
    @discardableResult public func speak(_ strings:String..., interrupt:Bool = true) -> [TTSUtterance] {
        var arr = [TTSUtterance]()
        for string in strings {
            arr.append(self.utterance(for: string))
        }
        if interrupt {
            self.interrupt(using: arr)
        } else {
            self.queue(utterances: arr)
        }
        return arr
    }
    public func listen(for keys:[Keys]) -> AnyPublisher<CommandBridge.Result,Never> {
        return commandBridge.publisher(using: keys)
    }
    public func translate(_ strings:String..., from:Locale? = nil, to:[String]? = nil) {
        if disabled {
            return
        }
        guard let f = (from ?? mainLocale).languageCode else {
            return
        }
        if let to = to {
            _ = dragoman.translate(strings, from: f, to: to)
        } else {
            _ = dragoman.translate(strings, from: f, to: supportedLocales.filter { $0.languageCode != nil }.compactMap({$0.languageCode!}))
        }
    }
    public struct ContainerView<Content: View>: View {
        @ObservedObject var assistant:Assistant
        let content: () -> Content
        public init(assistant: Assistant, @ViewBuilder content: @escaping () -> Content) {
            self.assistant = assistant
            self.content = content
        }
        public var body: some View {
            content()
                .environmentObject(assistant)
                .environmentObject(assistant.tts)
                .environmentObject(assistant.stt)
                .environmentObject(assistant.taskQueue)
                .environmentObject(assistant.dragoman)
                .environment(\.locale, assistant.locale)
        }
    }
}
