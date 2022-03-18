//
//  NSManagedObjectContext.swift
//  QPPNative
//
//  Created by Cheng-Hong on 2022/2/9.
//

import Foundation
import CoreData

public extension NSManagedObjectContext {
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


public extension NSManagedObjectContext {
    
    /**
     Creates, inserts, and returns a new `NSManagedObject` instance for the given `Persistable` concrete type (defaults to `Persistable`).
     */
    private func create<E: Persistable>(_ type: E.Type = E.self) -> E.T {
        return NSEntityDescription.insertNewObject(forEntityName: E.entityName, into: self) as! E.T
    }
    
    private func get<P: Persistable>(_ persistable: P) throws -> P.T? {
        let fetchRequest: NSFetchRequest<P.T> = NSFetchRequest(entityName: P.entityName)
        fetchRequest.predicate = persistable.predicate()
        let result = (try self.execute(fetchRequest)) as! NSAsynchronousFetchResult<P.T>
        return result.finalResult?.first
    }
    
    /**
     Attempts to retrieve  remove a `Persistable` object from a persistent store, and then attempts to commit that change or throws an error if unsuccessful.
     - seealso: `Persistable`
     - parameter persistable: a `Persistable` object
     */
    func delete<P: Persistable>(_ persistable: P) throws {
        
        if let entity = try get(persistable) {
            self.delete(entity)
            
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
                                  sortDescriptors: [NSSortDescriptor]? = nil) -> [P] {
        
        let fetchRequest: NSFetchRequest<P.T> = NSFetchRequest(entityName: P.entityName)
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors ?? [NSSortDescriptor(key: P.primaryAttributeName, ascending: true)]
        
        
//        return fetchData(fetchRequest).map { P.init(entity: $0) }
        return entities(fetchRequest: fetchRequest).map { P.init(entity: $0) }
    }
    
    /**
     Attempts to fetch and update (or create if not found) a `Persistable` instance. Will throw error if fetch fails.
     - parameter persistable: a `Persistable` instance
     */
    func update<P: Persistable>(_ persistable: P) throws {
        persistable.update(try get(persistable) ?? self.create(P.self))
    }
}
