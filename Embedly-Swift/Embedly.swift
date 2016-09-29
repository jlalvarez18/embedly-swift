//
//  Embedly.swift
//  Embedly-Swift
//
//  Created by Juan Alvarez on 9/29/16.
//  Copyright © 2016 Alvarez Productions. All rights reserved.
//

import Foundation
import CoreGraphics

let kEmbedlySwiftDomain = "EmbedlySwiftDomain"

typealias EmbedlyDictionary = [String: Any]

class EmbedlySwift {
    
    enum EmbedlyError: Error {
        case ExceedsMaximumURLs
        case InvalidRequest
    }
    
    enum Result {
        case Success([EmbedlyDictionary])
        case Failure(Error)
    }
    
    typealias CompletionBlock = (Result) -> Void
    
    internal var key: String?
    
    internal static let sharedInstance = EmbedlySwift()
    
    internal lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "swift-embedly"]
        
        let session = URLSession(configuration: config)
        
        return session
    }()
    
    static func initializeWithKey(key: String) {
        sharedInstance.key = key
    }
    
    static func callEmbed(urls: [URL], params: EmbedlyDictionary? = nil, optimizeWithImageWidth width: Int? = nil, completion: @escaping CompletionBlock) throws {
        let endpoint = EmbedlyEndpoint.Embed(width: width)
        
        try sharedInstance.fetchEmbedlyAPI(endpoint: endpoint, urls: urls, otherParams: params, completion: completion)
    }
    
    static func callExtract(urls: [URL], params: EmbedlyDictionary? = nil, optimizeWithImageWidth width: Int? = nil, completion: @escaping CompletionBlock) throws {
        let endpoint = EmbedlyEndpoint.Extract(width: width)
        
        try sharedInstance.fetchEmbedlyAPI(endpoint: endpoint, urls: urls, otherParams: params, completion: completion)
    }
    
    static func callDisplayCrop(url: URL, size: CGSize, completion: @escaping CompletionBlock) throws {
        let endpoint = EmbedlyEndpoint.DisplayCrop(size: size)
        
        try sharedInstance.fetchEmbedlyAPI(endpoint: endpoint, urls: [url], completion: completion)
    }
    
    static func callDisplayResize(url: URL, width: Int, completion: @escaping CompletionBlock) throws {
        let endpoint = EmbedlyEndpoint.DisplayResize(width: width)
        
        try sharedInstance.fetchEmbedlyAPI(endpoint: endpoint, urls: [url], completion: completion)
    }
}

private extension EmbedlySwift {
    
    enum EmbedlyEndpoint {
        case Embed(width: Int?)
        case Extract(width: Int?)
        case DisplayCrop(size: CGSize)
        case DisplayResize(width: Int)
        case Custom(endpoint: String, params: EmbedlyDictionary?)
        
        var params: EmbedlyDictionary {
            var params = EmbedlyDictionary()
            
            switch self {
            case .Embed(let width):
                if let width = width {
                    params["image_width"] = width
                }
                
            case .Extract(let width):
                if let width = width {
                    params["image_width"] = width
                }
                
            case .DisplayCrop(let size):
                params["width"] = size.width
                params["height"] = size.height
                
            case .DisplayResize(let width):
                params["width"] = width
                
            case .Custom(_, let otherParams):
                if let otherParams = otherParams {
                    params.unionInPlace(otherDictionary: otherParams)
                }
            }
            
            return params
        }
        
        var URLString: String {
            let APIURL = URL(string: "http://api.embed.ly/1")!
            let DisplayAPIURL = URL(string: "http://i.embed.ly/1")!
            
            let url: URL
            
            switch self {
            case .Embed:
                url = APIURL.appendingPathComponent("oembed")
            case .Extract:
                url = APIURL.appendingPathComponent("extract")
            case .DisplayCrop:
                url = DisplayAPIURL.appendingPathComponent("display/crop")
            case .DisplayResize:
                url = DisplayAPIURL.appendingPathComponent("display/resize")
            case .Custom(let endpoint, _):
                url = APIURL.appendingPathComponent(endpoint)
            }
            
            return url.absoluteString
        }
        
        func constructURLStringWith(key: String, urls: [URL], otherParams: EmbedlyDictionary?) -> String {
            var params = self.params
            
            if let otherParams = otherParams {
                params.unionInPlace(otherDictionary: otherParams)
            }
            
            params["key"] = key
            
            let urlSet = Set<URL>(urls) // this makes sure there all URLs are unique :)
            let urlQueryCharacterSet = CharacterSet.urlQueryAllowed
            
            if let url = urlSet.first , urlSet.count == 1 {
                params["url"] = url.absoluteString
            } else if urlSet.count > 1 {
                let urlStrings = urlSet.map { $0.absoluteString.addingPercentEncoding(withAllowedCharacters: urlQueryCharacterSet)! }
                let finalURLString = (urlStrings as NSArray).componentsJoined(by: ",")
                
                params["urls"] = finalURLString
            }
            
            var displayQuery = "?"
            var param = ""
            
            for (key, value) in params {
                let paramValue = (value as! String).addingPercentEncoding(withAllowedCharacters: urlQueryCharacterSet)
                
                if displayQuery == "?" {
                    displayQuery = "?\(key)=\(paramValue)"
                } else {
                    param = "&\(key)=\(paramValue)"
                    
                    displayQuery = displayQuery.appending(param)
                }
            }
            
            let urlString = "\(URLString)\(displayQuery)"
            
            return urlString
        }
    }
    
    func fetchEmbedlyAPI(endpoint: EmbedlyEndpoint, urls: [URL], otherParams: EmbedlyDictionary? = [:], completion: @escaping CompletionBlock) throws {
        guard let key = key else {
            fatalError("Must call initializeWithKey() before making any requests.")
        }
        
        // The API only handles a maximum of 10 urls
        guard urls.count <= 10 else {
            throw EmbedlyError.ExceedsMaximumURLs
        }
        
        let urlString = endpoint.constructURLStringWith(key: key, urls: urls, otherParams: otherParams)
        
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "GET"
        
        session.dataTask(with: request) { (data, response, error) in
            guard error == nil else {
                let result: Result
                
                if let data = data, let embedlyError = self.parseEmbedlyError(data: data) {
                    result = Result.Failure(embedlyError)
                } else {
                    result = Result.Failure(error!)
                }
                
                completion(result)
                
                return
            }
            
            guard let data = data else {
                completion(Result.Failure(EmbedlyError.InvalidRequest))
                return
            }
            
            let result: Result
            
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                
                if let jsonDict = json as? EmbedlyDictionary {
                    result = Result.Success([jsonDict])
                }
                else if let jsonArray = json as? [EmbedlyDictionary] {
                    result = Result.Success(jsonArray)
                } else {
                    result = Result.Success([])
                }
            } catch let jsonError {
                result = Result.Failure(jsonError)
            }
            
            DispatchQueue.main.async {
                completion(result)
            }
        }.resume()
    }
    
    func parseEmbedlyError(data: Data) -> Error? {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? EmbedlyDictionary, let errorMessage = json["error_message"] as? String else {
                return nil
            }
            
            let embedlyError = NSError(domain: kEmbedlySwiftDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            
            return embedlyError
        } catch {
            return error
        }
    }
}

extension Dictionary {
    
    mutating func unionInPlace(otherDictionary: Dictionary) {
        otherDictionary.forEach { self.updateValue($1, forKey: $0) }
    }
    
    func union(otherDictionary: Dictionary) -> Dictionary {
        var otherDictionary = otherDictionary
        otherDictionary.unionInPlace(otherDictionary: self)
        
        return otherDictionary
    }
}
