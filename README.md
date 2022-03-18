---
title: 'RxCoreData'
tags: CoreData
disqus: hackmd
---

RxCoreData
===

## Table of Contents

[TOC]

## SPM

```shell=
git clone http://192.168.12.29/Cheng-Hong/rxcoredatapackage
```

### Init

```swift=
// TODO: - for RxCoreDataPackage
private let coreDataManager = CoreDataManager("Model")

var managedObjectContext: NSManagedObjectContext {
    coreDataManager.managedObjectContext
}
```

上面程式碼中的"Model"是你的Data Model名稱，例如：

![](https://imgur.com/g9boHWj.png)

## Create Data Model

![](https://imgur.com/V07AEQi.png)

## CoreDataManager

- .documentDirectory -> 把sqlite放在document folder底下
- forResource: "Model" -> Model是你剛剛創建的Data Model名稱
- "RxCoreData.sqlite" -> sqlite的名稱(自訂)

<details>
    <summary>Source Code</summary>

```swift=
import Foundation
import CoreData

class CoreDataManager {
    
    static let shared = CoreDataManager()
    
    // MARK: - Core Data stack
    
    lazy var applicationDocumentsDirectory: URL = {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return urls.last!
    }()
    
    lazy var managedObjectModel: NSManagedObjectModel = {
        let modelURL = Bundle.main.url(forResource: "Model", withExtension: "momd")!
        return NSManagedObjectModel(contentsOf: modelURL)!
    }()
    
    lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator = {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
        let url = self.applicationDocumentsDirectory.appendingPathComponent("RxCoreData.sqlite")
        var failureReason = "There was an error creating or loading the application's saved data."
        
        do {
            try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil)
        } catch {
            var dict = [String: Any]()
            dict[NSLocalizedDescriptionKey] = "Failed to initialize the application's saved data"
            dict[NSLocalizedFailureReasonErrorKey] = failureReason
            
            dict[NSUnderlyingErrorKey] = error as NSError
            let wrappedError = NSError(domain: "YOUR_ERROR_DOMAIN", code: 9999, userInfo: dict)
            NSLog("Unresolved error \(wrappedError), \(wrappedError.userInfo)")
            abort()
        }
        
        return coordinator
    }()
    
    lazy var managedObjectContext: NSManagedObjectContext = {
        let coordinator = self.persistentStoreCoordinator
        var managedObjectContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = coordinator
        return managedObjectContext
    }()
}
```
    
</details>

## Persistable

- 將需要實例化的variable、function創建成Protocol

<details>
    <summary>Source Code</summary>

```swift=
import Foundation
import CoreData

public protocol Persistable {
    associatedtype T: NSManagedObject
    
    static var entityName: String { get }
    
    /// The attribute name to be used to uniquely identify each instance.
    static var primaryAttributeName: String { get }
    
    var identity: String { get }

    init(entity: T)

    func update(_ entity: T)
    
    /* predicate to uniquely identify the record, such as: NSPredicate(format: "code == '\(code)'") */
    func predicate() -> NSPredicate
    
}

public extension Persistable {
    
    func predicate() -> NSPredicate {
        return NSPredicate(format: "%K = %@", Self.primaryAttributeName, self.identity)
    }

}
```

</details>

## NSManagedObjectContext+Rx

- 創建CoreDate Rx的方法

<details>
    <summary>Source Code</summary>

```swift=
import Foundation
import CoreData
import RxSwift

public extension Reactive where Base: NSManagedObjectContext {
    
    /**
     Executes a fetch request and returns the fetched objects as an `Observable` array of `NSManagedObjects`.
     - parameter fetchRequest: an instance of `NSFetchRequest` to describe the search criteria used to retrieve data from a persistent store
     - parameter sectionNameKeyPath: the key path on the fetched objects used to determine the section they belong to; defaults to `nil`
     - parameter cacheName: the name of the file used to cache section information; defaults to `nil`
     - returns: An `Observable` array of `NSManagedObjects` objects that can be bound to a table view.
     */
    func entities<T: NSManagedObject>(fetchRequest: NSFetchRequest<T>,
                                      sectionNameKeyPath: String? = nil,
                                      cacheName: String? = nil) -> Observable<[T]> {
        
        return Observable.create { observer in
            let observerAdapter = FetchedResultsControllerEntityObserver(observer: observer,
                                                                         fetchRequest: fetchRequest,
                                                                         managedObjectContext: self.base,
                                                                         sectionNameKeyPath: sectionNameKeyPath,
                                                                         cacheName: cacheName)
            
            return Disposables.create {
                observerAdapter.dispose()
            }
        }
    }
    
    /**
     Executes a fetch request and returns the fetched section objects as an `Observable` array of `NSFetchedResultsSectionInfo`.
     - parameter fetchRequest: an instance of `NSFetchRequest` to describe the search criteria used to retrieve data from a persistent store
     - parameter sectionNameKeyPath: the key path on the fetched objects used to determine the section they belong to; defaults to `nil`
     - parameter cacheName: the name of the file used to cache section information; defaults to `nil`
     - returns: An `Observable` array of `NSFetchedResultsSectionInfo` objects that can be bound to a table view.
     */
    func sections<T: NSManagedObject>(fetchRequest: NSFetchRequest<T>,
                                      sectionNameKeyPath: String? = nil,
                                      cacheName: String? = nil) -> Observable<[NSFetchedResultsSectionInfo]> {

        return Observable.create { observer in
            let frc = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                 managedObjectContext: self.base,
                                                 sectionNameKeyPath: sectionNameKeyPath,
                                                 cacheName: cacheName)
            
            let observerAdapter = FetchedResultsControllerSectionObserver(observer: observer, frc: frc)
            return Disposables.create {
                observerAdapter.dispose()
            }
        }
    }
    
    /**
     Performs transactional update, initiated on a separate managed object context, and propagating thrown errors.
     - parameter updateAction: a throwing update action
     */
    func performUpdate(updateAction: (NSManagedObjectContext) throws -> Void) throws {
        
        let privateContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        privateContext.parent = self.base
        
        try updateAction(privateContext)
        guard privateContext.hasChanges else { return }
        try privateContext.save()
        try self.base.save()
    }
}

public extension Reactive where Base: NSManagedObjectContext {
    
    /**
     Creates, inserts, and returns a new `NSManagedObject` instance for the given `Persistable` concrete type (defaults to `Persistable`).
     */
    private func create<E: Persistable>(_ type: E.Type = E.self) -> E.T {
        return NSEntityDescription.insertNewObject(forEntityName: E.entityName, into: self.base) as! E.T
    }
    
    private func get<P: Persistable>(_ persistable: P) throws -> P.T? {
        let fetchRequest: NSFetchRequest<P.T> = NSFetchRequest(entityName: P.entityName)
        fetchRequest.predicate = persistable.predicate()
        let result = (try self.base.execute(fetchRequest)) as! NSAsynchronousFetchResult<P.T>
        return result.finalResult?.first
    }
    
    /**
     Attempts to retrieve  remove a `Persistable` object from a persistent store, and then attempts to commit that change or throws an error if unsuccessful.
     - seealso: `Persistable`
     - parameter persistable: a `Persistable` object
     */
    func delete<P: Persistable>(_ persistable: P) throws {
        
        if let entity = try get(persistable) {
            self.base.delete(entity)
            
            do {
                try entity.managedObjectContext?.save()
            } catch let e {
                print(e)
            }
        }
    }
    
    /**
     Creates and executes a fetch request and returns the fetched objects as an `Observable` array of `Persistable`.
     - parameter type: the `Persistable` concrete type; defaults to `Persistable`
     - parameter format: the format string for the predicate; defaults to `""`
     - parameter arguments: the arguments to substitute into `format`, in the order provided; defaults to `nil`
     - parameter sortDescriptors: the sort descriptors for the fetch request; defaults to `nil`
     - returns: An `Observable` array of `Persistable` objects that can be bound to a table view.
     */
    func entities<P: Persistable>(_ type: P.Type = P.self,
                                  predicate: NSPredicate? = nil,
                                  sortDescriptors: [NSSortDescriptor]? = nil) -> Observable<[P]> {
        
        let fetchRequest: NSFetchRequest<P.T> = NSFetchRequest(entityName: P.entityName)
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors ?? [NSSortDescriptor(key: P.primaryAttributeName, ascending: true)]
        
        return entities(fetchRequest: fetchRequest).map {$0.map(P.init)}
    }
    
    /**
     Attempts to fetch and update (or create if not found) a `Persistable` instance. Will throw error if fetch fails.
     - parameter persistable: a `Persistable` instance
     */
    func update<P: Persistable>(_ persistable: P) throws {
        persistable.update(try get(persistable) ?? self.create(P.self))
    }
    
}
```
    
</details>

## NSManagedObjectContext

- 雖然是RxCoreData，不過有時候只是需要取資料，卻都要通過Observer在存起來有點麻煩，所以另外創建了一個非Rx的讀取

<details>
    <summary>Source Code</summary>
    
```swift=
import Foundation
import CoreData

extension NSManagedObjectContext {
    /**
     Executes a fetch request and returns the fetched objects as an `Observable` array of `NSManagedObjects`.
     - parameter fetchRequest: an instance of `NSFetchRequest` to describe the search criteria used to retrieve data from a persistent store
     - parameter sectionNameKeyPath: the key path on the fetched objects used to determine the section they belong to; defaults to `nil`
     - parameter cacheName: the name of the file used to cache section information; defaults to `nil`
     - returns: An `Observable` array of `NSManagedObjects` objects that can be bound to a table view.
     */
    func entities<T: NSManagedObject>(fetchRequest: NSFetchRequest<T>,
                                      sectionNameKeyPath: String? = nil,
                                      cacheName: String? = nil) -> [T] {
        
        let frc = NSFetchedResultsController(fetchRequest: fetchRequest,
                                             managedObjectContext: self,
                                             sectionNameKeyPath: sectionNameKeyPath,
                                             cacheName: cacheName)
        
        do {
            try frc.performFetch()
        } catch let e {
            print(e)
        }
        
        let entities = frc.fetchedObjects ?? []
        return entities
    }
    
    func fetchData<T>(_ fetchRequest: NSFetchRequest<T>) -> [T] where T : NSFetchRequestResult {
        do {
            return try fetch(fetchRequest)
        } catch {
            print("Fetching Failed")
        }
        return []
    }
}


extension NSManagedObjectContext {
    /**
     Creates and executes a fetch request and returns the fetched objects as an `Observable` array of `Persistable`.
     - parameter type: the `Persistable` concrete type; defaults to `Persistable`
     - parameter format: the format string for the predicate; defaults to `""`
     - parameter arguments: the arguments to substitute into `format`, in the order provided; defaults to `nil`
     - parameter sortDescriptors: the sort descriptors for the fetch request; defaults to `nil`
     - returns: An `Observable` array of `Persistable` objects that can be bound to a table view.
     */
    func entities<P: Persistable>(_ type: P.Type = P.self,
                                  predicate: NSPredicate? = nil,
                                  sortDescriptors: [NSSortDescriptor]? = nil) -> [P] {
        
        let fetchRequest: NSFetchRequest<P.T> = NSFetchRequest(entityName: P.entityName)
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors ?? [NSSortDescriptor(key: P.primaryAttributeName, ascending: true)]
        
        
//        return fetchData(fetchRequest).map { P.init(entity: $0) }
        return entities(fetchRequest: fetchRequest).map { P.init(entity: $0) }
    }
}
```
    
</details>

## FetchedResultsControllerControllerEntityObserver

- 將fetch request轉換成entities: [NSManagedObject]
- 利用NSFetchedResultsControllerDelegate的controllerDidChangeContent去監聽，當有變化時發送onNext出去

<details>
    <summary>Source Code</summary>
    
```swift=
import Foundation
import CoreData
import RxSwift

public final class FetchedResultsControllerEntityObserver<T: NSManagedObject>: NSObject, NSFetchedResultsControllerDelegate {
    
    typealias Observer = AnyObserver<[T]>
    
    private let observer: Observer
    private let frc: NSFetchedResultsController<T>
    
    init(observer: Observer, fetchRequest: NSFetchRequest<T>, managedObjectContext context: NSManagedObjectContext, sectionNameKeyPath: String?, cacheName: String?) {
        self.observer = observer
        

        self.frc = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, sectionNameKeyPath: sectionNameKeyPath, cacheName: cacheName)
        super.init()
        
        context.perform {
            self.frc.delegate = self
            
            do {
                try self.frc.performFetch()
            } catch let e {
                observer.on(.error(e))
            }
            
            self.sendNextElement()
        }
    }
    
    private func sendNextElement() {
        self.frc.managedObjectContext.perform {
            let entities = self.frc.fetchedObjects ?? []
            self.observer.on(.next(entities))
        }
    }
    
    public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        sendNextElement()
    }
    /// Delegate implementation for `Disposable`
    /// required methods - This is kept in here
    /// to make `frc` private.
    public func dispose() {
        frc.delegate = nil
    }
}

extension FetchedResultsControllerEntityObserver : Disposable { }
```
    
</details>

## FetchedResultsControllerSectionObserver(目前未用到)

- 將fetch request轉換成entities: [NSFetchedResultsSectionInfo]
- 利用NSFetchedResultsControllerDelegate的controllerDidChangeContent去監聽，當有變化時發送onNext出去

<details>
    <summary>Source Code</summary>
    
```swift=
import Foundation
import CoreData
import RxSwift

public final class FetchedResultsControllerSectionObserver<T: NSManagedObject> : NSObject, NSFetchedResultsControllerDelegate {
    
    typealias Observer = AnyObserver<[NSFetchedResultsSectionInfo]>
    
    private let observer: Observer
    private let frc: NSFetchedResultsController<T>
    
    init(observer: Observer, frc: NSFetchedResultsController<T>) {
        self.observer = observer
        self.frc = frc
        
        super.init()
        
        self.frc.delegate = self
        
        do {
            try self.frc.performFetch()
        } catch let e {
            observer.on(.error(e))
        }
        
        sendNextElement()
    }
    
    private func sendNextElement() {
        let sections = self.frc.sections ?? []
        observer.on(.next(sections))
    }
    
    public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        sendNextElement()
    }
    
    public func dispose() {
        frc.delegate = nil
    }
}

extension FetchedResultsControllerSectionObserver : Disposable { }
```
    
</details>

## Model

- 依照Data Model Entities去創建Model，例如下圖：

[![](https://imgur.com/px2RuVV.png)](https://imgur.com/px2RuVV)

<details>
    <summary>Source Code</summary>
    
```swift=
import Foundation
import CoreData
import PhoneNumberKit

struct LoginData {
    var countryCode: String
    
    var phoneNumber: String
    
    var token: String
    
    var refreshToken: String
    
    var uName: String
    
    var nick: String
}

extension LoginData: Persistable {
    typealias T = NSManagedObject
    
    private static let COUNTRYCODE = "countryCode"
    private static let PHONENUMBER = "phoneNumber"
    private static let TOKEN = "token"  // LoginSys Token
    private static let REFRESHTOKEN = "refreshToken" // refresh token
    private static let UNAME = "uName"
    private static let NICK = "nick"
    
    var identity: String {
        return phoneNumber
    }
    
    static var entityName: String {
        return String(describing: self)
    }
    
    static var primaryAttributeName: String {
        return "phoneNumber"
    }
    
    init(entity: T) {
        if let countryCode = entity.value(forKey: LoginData.COUNTRYCODE) as? String {
            self.countryCode = countryCode
        }
        
        if let phoneNumber = entity.value(forKey: LoginData.PHONENUMBER) as? String {
            self.phoneNumber = phoneNumber
        }
        
        if let token = entity.value(forKey: LoginData.TOKEN) as? String {
            self.token = token
        }

        if let refreshToken = entity.value(forKey: LoginData.REFRESHTOKEN) as? String {
            self.refreshToken = refreshToken
        }
        
        if let uName = entity.value(forKey: LoginData.UNAME) as? String {
            self.uName = uName
        }
        
        if let nick = entity.value(forKey: LoginData.NICK) as? String {
            self.nick = nick
        }
    }
    
    func update(_ entity: T) {
        entity.setValue(countryCode, forKey: LoginData.COUNTRYCODE)
        entity.setValue(phoneNumber, forKey: LoginData.PHONENUMBER)
        entity.setValue(token, forKey: LoginData.TOKEN)
        entity.setValue(refreshToken, forKey: LoginData.REFRESHTOKEN)
        entity.setValue(uName, forKey: LoginData.UNAME)
        entity.setValue(nick, forKey: LoginData.NICK)
        
        do {
            try entity.managedObjectContext?.save()
        } catch let e {
            print("CoreData Error: \(e)")
        }
    }
}
```

</details>

## How to use

### Fetch

- Swift

```swift=
private var loginData = CoreDataManager.shared.managedObjectContext.entities(LoginData.self).first ?? LoginData()
```

- RxSwift
- predicate -> 篩選條件(optional)
- sortDescriptors -> 排序方法(optional)
    
```swift=
CoreDataManager.shared.managedObjectContext
    .rx
    .entities(Event.self,
              predicate: NSPredicate(format: "%K == %@", "id", "123"),
              sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)])
    .bind {
        print("LoginData: \($0)")
    }.disposed(by: disposeBag)
```

### Create or update
    
- Swift
    
```swift=
_ = try? CoreDataManager.shared.managedObjectContext.update(loginData)
```
    
- RxSwift

```swift=
_ = try? CoreDataManager.shared.managedObjectContext.rx.update(loginData)
```

### delete
    
- Swift
    
```swift=
do {
    try CoreDataManager.shared.managedObjectContext.delete(loginData)
} catch {
    print(error)
}
```

- RxSwift    

```swift=
do {
    try CoreDataManager.shared.managedObjectContext.rx.delete(loginData)
} catch {
    print(error)
}
```

## CoreData warning

- 這感覺是CoreData的一個bug，因為就算不理他也不會影響我們存取資料

[![](https://imgur.com/LgZk23r.png)](https://imgur.com/LgZk23r)

- 解決方法：

打開專案Folder找到剛剛創建的Data Model，並顯示套件內容

[![](https://imgur.com/NGVO29P.png)](https://imgur.com/NGVO29P)
    
打開contents
    
[![](https://imgur.com/QCX7ycM.png)](https://imgur.com/QCX7ycM)

把紅框的變數整個砍掉之後就不會再出現這個警告了

[![](https://imgur.com/GNpJM83.png)](https://imgur.com/GNpJM83)

## 參考資料

[https://github.com/RxSwiftCommunity/RxCoreData](https://github.com/RxSwiftCommunity/RxCoreData)
