# AppleTV Screensaver Video Downloader

Apple's screensaver videos can be downloaded directly from their servers. They posted a JSON documemt that provides the details of the screensaver location videos here: http://a1.phobos.apple.com/us/r1000/000/Features/atv/AutumnResources/videos/entries.json. So, I decided to put together a little Swift script that will:

* Download the JSON file and parse it
* Extract the list of URLs for all of the videos
* Download all of the videos to the local disk

The script, while fairly short, isn't as short as I thought it would be. I'm sure it can be improved, but if you have the Apple developer command line tools installed, you can just download the main.swift file from this repo, change its permissions to be executable (e.g. `chmod +x main.swift`) and then just run it with `./main.swift`.

**Note:** Make sure you change the `baseSaveLocationUrl` to a location on your own computer befroe trying to run the script.

Here is the script in its entirety:

```swift
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
        // the FileManager's fileExisrts(atPath:) method
        let unDownloaded = urls.filter({ (url) -> Bool in
            let saveLocation = baseSaveLocationUrl.appendingPathComponent(url.lastPathComponent)
            return !FileManager.default.fileExists(atPath: saveLocation.path)
        })
        
        // Go ahead and bail out so that the semaphore gets signaled 
        // and the app quits
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
```
## Some Notes

* I didn't make it so you could specify the output location on the command line. I might do that later (not likely).
* I am checking to see if a file exists on the local disk before attempting to download it again.
* Because this is a script that runs on the command line, there is nothing to prevent it from qutting once the last line has been run. This is a problem since our download tasks run async in the background. I am therefore using a semaphore to block until everthing has finished.
* I am using `URLSession`'s delegate methods to be notified when all downloads have completed.
* When the downloads have all finished, I signal the semaphore and the app quits.

You should be able to see all the videos (55 at the time of this writing) in the finder:

![Videos in Finder](http://i.imgur.com/BaJp0O4.png)

## License

Do whatever you like with it. Consider it public domain.


