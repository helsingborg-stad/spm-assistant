import Combine
import Foundation

public protocol QueueTask {
    var id: UUID { get }
    var end: AnyPublisher<Void, Never> { get }
    func run()
    func interrupt()
    func pause()
    func `continue`()
}
public class TaskQueue : ObservableObject {

    private var publishers = Set<AnyCancellable>()
    private var queue = [QueueTask]()
    private var currentTask:QueueTask?
    
    private func subscribe(to task:[QueueTask]) {
        task.forEach { t in
            subscribe(to: t)
        }
    }
    private func subscribe(to task:QueueTask) {
        var p:AnyCancellable?
        p = task.end.receive(on: DispatchQueue.main).sink { [weak self] in
            guard let this = self else {
                return
            }
            if task.id == this.currentTask?.id {
                this.currentTask = nil
            }
            if let p = p {
                self?.publishers.remove(p)
            }
            this.runQueue()
        }
        if let p = p {
            publishers.insert(p)
        }
    }
    public func clear() {
        for t in queue {
            t.interrupt()
        }
        currentTask?.interrupt()
        currentTask = nil
        publishers.removeAll()
        queue.removeAll()
    }
    private func runQueue() {
        if currentTask != nil {
            return
        }
        guard let task = queue.first else {
            return
        }
        queue.removeFirst()
        self.currentTask = task
        task.run()
    }
    public init() {}
    
    public final func queue(_ task:QueueTask) {
        queue.append(task)
        subscribe(to: task)
        runQueue()
    }

    public final func queue(_ tasks:[QueueTask]) {
        tasks.forEach { t in
            queue(t)
        }
    }
    public final func interject(with task:QueueTask) {
        if let c = currentTask {
            subscribe(to: task)
            c.pause()
            queue.insert(contentsOf: [task,c],at:0)
            self.currentTask = nil
            runQueue()
        } else {
            queue(task)
        }
    }
    public final func interject(with tasks:[QueueTask]) {
        if let c = currentTask {
            subscribe(to: tasks)
            var tasks = tasks
            tasks.append(c)
            c.pause()
            queue.insert(contentsOf: tasks,at:0)
            self.currentTask = nil
            runQueue()
        } else {
            queue(tasks)
        }
    }
    public final func interrupt(with task:QueueTask) {
        clear()
        queue(task)
    }
    public final func interrupt(with tasks:[QueueTask]) {
        clear()
        queue(tasks)
    }
}
