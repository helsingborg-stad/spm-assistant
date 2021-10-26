//
//  Command.swift
//  ExampleAssistant
//
//  Created by Tomas Green on 2021-06-10.
//

import Foundation
import STT
import Combine


public protocol NLKeyDefinition : CustomStringConvertible & Hashable & CaseIterable & Equatable {
    
}
public extension NLKeyDefinition {
    static func createLocalizedDatabasePlist(fileName:String = "VoiceCommands", languages:[Locale]) -> NLParser<Self>.DB {
        var propertyListFormat = PropertyListSerialization.PropertyListFormat.xml
        var db = NLParser<Self>.DB()
        func bundle(for language:Locale) -> Bundle {
            guard let b = Bundle.main.path(forResource: language.identifier, ofType: "lproj") else {
                return Bundle.main
            }
            return Bundle(path: b) ?? Bundle.main
        }
        for lang in languages {
            db[lang] = [Self:[String]]()
            let bundle = bundle(for: lang)
            guard let path = bundle.path(forResource: fileName, ofType: "plist") else {
                print("no path for \(lang) in \(bundle.bundlePath)")
                continue
            }
            do {
                guard let plistXML = FileManager.default.contents(atPath: path) else {
                    continue
                }
                let data = try PropertyListSerialization.propertyList(from: plistXML, options: .mutableContainersAndLeaves, format: &propertyListFormat)
                guard let abc = data as? [String:[String]] else {
                    continue
                }
                var dict = NLParser<Self>.Entity()
                Self.allCases.forEach { key in
                    if let arr = abc[key.description] {
                        dict[key] = arr
                    }
                }
                db[lang] = dict
            } catch {
                print(error)
                continue
            }
        }
        return db
    }
}
public class NLParser<Key: NLKeyDefinition> : ObservableObject {
    public typealias DB = [Locale:Entity]
    
    public typealias Entity = [Key:[String]]
    public typealias ResultPublisher = AnyPublisher<Result,Never>
    
    public struct Result {
        public let collection:Set<Entity>
        public func contains(_ key : Key) -> Bool {
            collection.contains { db in
                db.keys.contains(key)
            }
        }
    }
    private var db: DB
    private var stringPublisher:AnyPublisher<String,Never>
    @Published public var locale:Locale = Locale.current {
        didSet {
            updateContextualStrings()
        }
    }
    @Published public private(set) var contextualStrings:[String] = []
    
    init(languages:[Locale], db:DB, stringPublisher:AnyPublisher<String,Never>) {
        self.db = db
        self.locale = languages.first ?? .current
        self.stringPublisher = stringPublisher
        updateContextualStrings()
    }
    init(languages:[Locale], fileName: String, stringPublisher:AnyPublisher<String,Never>) {
        db = Key.createLocalizedDatabasePlist(fileName:fileName, languages: languages)
        self.locale = languages.first ?? .current
        self.stringPublisher = stringPublisher
        updateContextualStrings()
    }
    func updateContextualStrings() {
        var str = [String]()
        guard let dict = db[locale] else {
            return
        }
        dict.keys.forEach({ key in
            if let arr = dict[key] {
                str.append(contentsOf: arr)
            }
        })
        self.contextualStrings = str
    }
    func publisher(using keys:[Key]) -> ResultPublisher {
        return stringPublisher.map { [weak self] string -> Result in
            guard let this = self else {
                return Result(collection: Set([]))
            }
            guard let collection = this.db[this.locale]?.filter({ key,value in
                return keys.contains(key)
            }) else {
                return Result(collection: Set([]))
            }
            var set = Set<Entity>()
            collection.forEach { a in
                let values = a.value.filter({ $0.range(of: "\\b\(string)", options: [.regularExpression,.caseInsensitive]) != nil})
                if !values.isEmpty {
                    set.insert([a.key:values])
                }
            }
            return Result(collection: set)
        }.eraseToAnyPublisher()
    }

}
