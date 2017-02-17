#!/usr/bin/swift

import Foundation

let semaphore           = DispatchSemaphore(value: 0)

let baseSaveLocationUrl = URL(fileURLWithPath: "/Users/mlong/Downloads/atv/") // <-- Change me!!
let downloadUrl         = URL(string:          "http://a1.phobos.apple.com/us/r1000/000/Features/atv/AutumnResources/videos/entries.json")!

func downloadJson(with completion:@escaping ((_ saveLocation:URL) -> ())) {

    let task:URLSessionDownloadTask = URLSession.shared.downloadTask(with: downloadUrl) { (localUrl, response, error) in
        if error == nil {
            if let localUrl = localUrl {
                // Save the JSON file to the local filesystem. We could just do a data
                // task and keep everything in memory, but this lets us keep a copy
                // of the JSON file
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
            // Map all of the asset arrays into an array of url strings
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

            // The urls array is an array of arrays right now, so we need to join
            // the sub arrays together to get a single dimensional array with all
            // of the url strings. We then convert those to URL objects and hand
            // that array off to our completion block
            completion?(Array(urls!.joined()).flatMap({ (urlString) -> URL? in
                return URL(string: urlString)
            }))
        }
    }
}

// Since we are running as a script, we can't make self our delegate since there is
// no self. Instead we need to creatd a class that can act as delegate and provide
// a place to respond to the callbacks. A ConfigDelegate object is instantiated in
// the parseJson completion block below
class ConfigDelegate : NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        print("All files downloaded")
        // Signal the semaphore so that we can quit now since all
        // downloads have completed
        semaphore.signal()
    }
}

// Main begins here
downloadJson { (saveLocation) in
    parseJson(at: saveLocation, completion: { 
        (urls:[URL]) in
        
        // Adjust the config so we can change the default timeout
        var config = URLSessionConfiguration.default
        // Need a pretty big timeout value. Let's give it 2 hours
        config.timeoutIntervalForRequest = TimeInterval(60*60*2)
        // Create our ConfigDelegate class here so we have a way to implement the delegate
        // methods
        let delegate = ConfigDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        
        // Only get the files that haven't already been downloaded by filtering using
        // the FileManager's fileExists(atPath:) method
        let unDownloaded = urls.filter({ (url) -> Bool in
            let saveLocation = baseSaveLocationUrl.appendingPathComponent(url.lastPathComponent)
            return !FileManager.default.fileExists(atPath: saveLocation.path)
        })
        
        // Go ahead and bail out so that the semaphore gets signaled 
        // and the app quits since we have nothing new to download
        if unDownloaded.count <= 0 {
            // Since there won't be any tasks, this will immediately call back to our
            // ConfigDelegate object's implementation of urlSession:didBecomeInvalidWithError:
            session.finishTasksAndInvalidate()
            return
        }
        
        // Download files that haven't been downloaded yet.
        unDownloaded.forEach({ (url) in
            print("Downloading \(url)")
            let downloadTask = session.downloadTask(with: url, completionHandler: { (localUrl, response, error) in
                if error == nil {
                    // No error, save the file to a known location on disk
                    let saveLocation = baseSaveLocationUrl.appendingPathComponent(url.lastPathComponent)
                    try! FileManager.default.copyItem(at: localUrl!, to: saveLocation)
                    print("Saved file to \(saveLocation.path)")
                }
            })
            downloadTask.resume()
            session.finishTasksAndInvalidate()
        })
    })
}
