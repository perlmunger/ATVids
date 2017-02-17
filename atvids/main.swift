#!/usr/bin/swift
//
//  main.swift
//  atvids
//
//  Created by Matt Long on 2/16/17.
//  Copyright © 2017 Skye Road Systems. All rights reserved.
//

import Foundation

let semaphore           = DispatchSemaphore(value: 0)

let baseSaveLocationUrl = URL(fileURLWithPath: "/Users/mlong/Downloads/atv/")
let downloadUrl         = URL(string:          "http://a1.phobos.apple.com/us/r1000/000/Features/atv/AutumnResources/videos/entries.json")!

func downloadJson(with completion:@escaping ((_ saveLocation:URL) -> ())) {

    let task:URLSessionDownloadTask = URLSession.shared.downloadTask(with: downloadUrl) { (localUrl, response, error) in
        if error == nil {
            if let localUrl = localUrl {
                let saveLocation = baseSaveLocationUrl.appendingPathComponent("vids.json")
                if FileManager.default.fileExists(atPath: saveLocation.path) {
                    try! FileManager.default.removeItem(at: saveLocation)
                }
                try! FileManager.default.copyItem(at: localUrl, to: saveLocation)
                
                completion(saveLocation)
            }
        }
    }
    
    task.resume()
    
    // URLSessions and their tasks are run asynchronously which means we need
    // to block until everything has completed in the background
    _ = semaphore.wait(timeout: .distantFuture)
}

func parseJson(at location:URL, completion:((_ urls:[URL]) -> ())?) {
    if let data = try? Data(contentsOf: location) {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [[String:Any]]{
            let urls = json.map({ (item) -> [[String]] in
                let arrayOfStrings = item.map({ (inner) -> [String] in
                    if let assets = inner["assets"] as? [[String:String]] {
                        return assets.flatMap({ (asset) -> String? in
                            return asset["url"]
                        })
                    }
                    return []
                })
                return arrayOfStrings
            })

            completion?(Array(urls!.joined()).flatMap({ (urlString) -> URL? in
                return URL(string: urlString)
            }))
        }
    }
}

class ConfigDelegate : NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        print("All files downloaded")
        // Signal the semaphore so that we can quit now since all
        // downloads have completed
        semaphore.signal()
    }
}

downloadJson { (saveLocation) in
    parseJson(at: saveLocation, completion: { 
        (urls:[URL]) in
        
        // Adjust the config so we can change the default timeout
        var config = URLSessionConfiguration.default
        // Need a pretty big timeout value. Let's give it 2 hours
        config.timeoutIntervalForRequest = TimeInterval(60*60*2)
        let delegate = ConfigDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        
        // Only get the files that haven't already been downloaded
        let unDownloaded = urls.filter({ (url) -> Bool in
            let saveLocation = baseSaveLocationUrl.appendingPathComponent(url.lastPathComponent)
            return !FileManager.default.fileExists(atPath: saveLocation.path)
        })
        
        // Go ahead and bail out so that the semaphore gets signaled 
        // and the app quits
        if unDownloaded.count <= 0 {
            session.finishTasksAndInvalidate()
            return
        }
        
        // Download files that haven't been downloaded yet.
        unDownloaded.forEach({ (url) in
            let saveLocation = baseSaveLocationUrl.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: saveLocation.path) {
                return
            }
            print("Downloading \(url)")
            let downloadTask = session.downloadTask(with: url, completionHandler: { (localUrl, response, error) in
                if error == nil {
                    try! FileManager.default.copyItem(at: localUrl!, to: saveLocation)
                    print("Saved file to \(saveLocation.path)")
                }
            })
            downloadTask.resume()
            session.finishTasksAndInvalidate()
        })
    })
}
