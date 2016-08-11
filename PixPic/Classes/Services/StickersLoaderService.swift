//
//  EffectsService.swift
//  PixPic
//
//  Created by anna on 2/16/16.
//  Copyright © 2016 Yalantis. All rights reserved.
//

import Foundation

typealias LoadingStickersCompletion = (objects: [StickersModel]?, error: NSError?) -> Void

class StickersLoaderService {
    
    private var cachePolicy: PFCachePolicy!
    
    //register Parse subclasses
    init() {
        StickersGroup.initialize()
        Sticker.initialize()
    }
    
    func loadStickers(completion: LoadingStickersCompletion? = nil) {
        figureOutCachePolicy{ [weak self] in
            guard let this = self else {
                return
            }
            
            let query = StickersVersion.sortedQuery
            query.cachePolicy = this.cachePolicy
            
            query.getFirstObjectInBackgroundWithBlock { object, error in
                if let error = error {
                    log.debug(error.localizedDescription)
                    completion?(objects: nil, error: error)
                    
                    return
                }
                
                guard let stickersVersion = object as? StickersVersion  else {
                    completion?(objects: nil, error: nil)
                    
                    return
                }
                
                this.loadStickersGroups(stickersVersion) { objects, error in
                    completion?(objects: objects, error: error)
                }
            }
        }
    }
    
    private func loadStickersGroups(stickersVersion: StickersVersion, completion: LoadingStickersCompletion) {
        let groupsRelationQuery = stickersVersion.groupsRelation.query()
        groupsRelationQuery.cachePolicy = cachePolicy
        groupsRelationQuery.findObjectsInBackgroundWithBlock { [weak self] objects, error in
            if let error = error {
                log.debug(error.localizedDescription)
                completion(objects: nil, error: error)
                
                return
            }
            
            guard let objects = objects as? [StickersGroup] else {
                completion(objects: nil, error: nil)
                
                return
            }
            
            self?.loadAllStickers(objects) { objects, error in
                completion(objects: objects, error: error)
            }
        }
    }
    
    private func loadAllStickers(stickersGroups: [StickersGroup], completion: LoadingStickersCompletion) {
        var stickersModels = [StickersModel]()
        
        let dispatchGroup = dispatch_group_create()
        
        for group in stickersGroups {
            dispatch_group_enter(dispatchGroup)
            
            let comletionBlock = {
                let stickersRelationQuery = group.stickersRelation.query().addAscendingOrder("createdAt")
                stickersRelationQuery.cachePolicy = self.cachePolicy
                stickersRelationQuery.findObjectsInBackgroundWithBlock { objects, error in
                    if let error = error {
                        log.debug(error.localizedDescription)
                        completion(objects: nil, error: error)
                        
                        return
                    }
                    guard let stickers = objects as? [Sticker] else {
                        completion(objects: nil, error: nil)
                        
                        return
                    }
                    
                    let model = StickersModel(stickersGroup: group, stickers: stickers)
                    stickersModels.append(model)
                    
                    dispatch_group_leave(dispatchGroup)
                    
                    for sticker in stickers {
                        sticker.image.getDataInBackground()
                    }
                }
            }
            
            group.image.getDataInBackgroundWithBlock { _, _ in
                comletionBlock()
            }
            
        }
        dispatch_group_notify(dispatchGroup, dispatch_get_main_queue()) {
            completion(objects: stickersModels, error: nil)
        }
        
    }
    
    private func figureOutCachePolicy(with handler: Void -> Void) {
        //load stickers from cache
        cachePolicy = PFCachePolicy.CacheElseNetwork
        handler()
        
        //figure out update necessity and handle it if needed
        let remoteQuery = StickersVersion.sortedQuery
        remoteQuery.cachePolicy = .NetworkOnly
        
        let localQuery = StickersVersion.sortedQuery
        localQuery.cachePolicy = .CacheOnly
        
        guard ReachabilityHelper.isReachable() else {
            handler()
            
            return
        }
        
        localQuery.getFirstObjectInBackgroundWithBlock { localObject, error in
            if let error = error {
                log.debug(error.localizedDescription)
                self.cachePolicy = .NetworkElseCache
                handler()
                
                return
            }
            
            guard let localVersion = localObject as? StickersVersion else {
                return
            }
            
            remoteQuery.getFirstObjectInBackgroundWithBlock { remoteObject, error in
                if let error = error {
                    log.debug(error.localizedDescription)
                    handler()
                    
                    return
                }
                
                guard let remoteVersion = remoteObject as? StickersVersion else {
                    return
                }
                
                if remoteVersion.version > localVersion.version {
                    log.debug("\(remoteVersion.version) > \(localVersion.version)")
                    self.cachePolicy = .NetworkElseCache
                    handler()
                }
            }
        }
    }
    
}
