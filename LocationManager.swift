//
//  LocationManager.swift
//
//  Created by Jens Grud on 26/05/16.
//  Copyright © 2016 Heaps. All rights reserved.
//

import CoreLocation
import AddressBook

public enum LocationUpdateStatus :String {
    case OK         = "OK"
    case ERROR      = "ERROR"
    case DISTANCE   = "Change in distance too little"
    case TIME       = "Time since last too little"
}

public enum ReverseGeoCodingType {
    case GOOGLE
    case APPLE
}

public typealias DidEnterRegion = (_ region :CLRegion?, _ error :NSError?) -> Void
public typealias LocationCompletionHandler = (_ latitude :Double,_  longitude :Double, _ status:LocationUpdateStatus, _ error:NSError?) -> Void
public typealias ReverseGeocodeCompletionHandler = (_ country :String?,_ state :String?,_ city :String?,_ reverseGecodeInfo:AnyObject?,_ placemark:CLPlacemark?, _ error :Error?) -> Void

public typealias LocationAuthorizationChanged = (_ manager :CLLocationManager, _ status :CLAuthorizationStatus) -> Void

public class LocationManagerSwift: NSObject, CLLocationManagerDelegate {
    
    enum GoogleAPIStatus :String {
        case OK             = "OK"
        case ZeroResults    = "ZERO_RESULTS"
        case APILimit       = "OVER_QUERY_LIMIT"
        case RequestDenied  = "REQUEST_DENIED"
        case InvalidRequest = "INVALID_REQUEST"
    }
    
    private var didEnterRegionCompletionHandlers :[String:DidEnterRegion] = [:]
    private var locationCompletionHandlers :[LocationCompletionHandler?] = []
    private var reverseGeocodingCompletionHandler:ReverseGeocodeCompletionHandler?
    private var authorizationChangedCompletionHandler:LocationAuthorizationChanged?
    
    private var locationManager: CLLocationManager!
    
    private var updateDistanceThreshold :Double!
    private var updateTimeintervalThreshold :Double!
    private var initWithLastKnownLocation = true
    
    private var googleAPIKey :String?
    private var googleAPIResultType :String?

    // Initialize longitude and latitude with last know location
    public lazy var latitude:Double = {
        guard self.initWithLastKnownLocation else {
            return 0.0
        }
        return UserDefaults.standard.double(forKey: self.kLastLocationLatitude)
    }()
    public lazy var longitude:Double = {
        guard self.initWithLastKnownLocation else {
            return 0.0
        }
        return UserDefaults.standard.double(forKey: self.kLastLocationLongitude)
    }()
    
    // Initialize country, state and city with last know location
    public lazy var country:String? = {
        guard self.initWithLastKnownLocation else {
            return nil
        }
        return UserDefaults.standard.value(forKey: self.kLastLocationCountry) as? String
    }()
    public lazy var state:String? = {
        guard self.initWithLastKnownLocation else {
            return nil
        }
        return UserDefaults.standard.value(forKey: self.kLastLocationState) as? String
    }()
    public lazy var city:String? = {
        guard self.initWithLastKnownLocation else {
            return nil
        }
        return UserDefaults.standard.value(forKey: self.kLastLocationCity) as? String
    }()
    
    lazy var googleAPI :String = {
        
        var url = "https://maps.googleapis.com/maps/api/geocode/json?latlng=%f,%f&sensor=true"
        
        if let resultType = self.googleAPIResultType {
            url = url + "&result_type=\(self.googleAPIResultType)"
        }
        if let apiKey = self.googleAPIKey {
            url = url + "&key=\(self.googleAPIKey)"
        }
        
        return url
    }()
    
    private let kDomain = "com.location-manager"
    
    private let kLastLocationUpdate = "com.location-manager.kLastLocationUpdate"
    private let kLocationUpdated = "com.location-manager.location-updated"
    
    private let kLastLocationLongitude = "com.location-manager.kLastLatitude"
    private let kLastLocationLatitude = "com.location-manager.kLastLongitude"
    private let kLastLocationCity = "com.location-manager.kLastCity"
    private let kLastLocationCountry = "com.location-manager.kLastCountry"
    private let kLastLocationState = "com.location-manager.kLastState"
    
    public static let sharedInstance = LocationManagerSwift()
    
    public init(locationAccuracy :CLLocationAccuracy = kCLLocationAccuracyBest, updateDistanceThreshold :Double = 0.0, updateTimeintervalThreshold :Double = 0.0, initWithLastKnownLocation :Bool = true, googleAPIKey :String? = nil, googleAPIResultType :String? = nil) {
        
        super.init()
        
        self.locationManager = CLLocationManager()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = locationAccuracy
        
        self.googleAPIKey = googleAPIKey
        self.googleAPIResultType = googleAPIResultType
        self.updateDistanceThreshold = updateDistanceThreshold
        self.updateTimeintervalThreshold = updateTimeintervalThreshold
        self.initWithLastKnownLocation = initWithLastKnownLocation
    }
    
    // MARK: Region monitoring
    
    public func monitorRegion(latitude :CLLocationDegrees, longitude :CLLocationDegrees, radius :CLLocationDistance = 100.0, completion :@escaping DidEnterRegion) {
        
        guard CLLocationManager.authorizationStatus() == .authorizedAlways else {
            return
        }
        
        guard radius < self.locationManager.maximumRegionMonitoringDistance else {
            return
        }
        
        let location = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let identifier = "\(longitude)\(latitude)\(radius)"
        
        let region = CLCircularRegion(center: location, radius: radius, identifier: identifier)
        region.notifyOnExit = true
        region.notifyOnEntry = false
        
        self.locationManager.startMonitoring(for: region)
        
        self.didEnterRegionCompletionHandlers[identifier] = completion
    }
    
    public func locationManager(manager: CLLocationManager, didEnterRegion region: CLRegion) {
        
    }
    
    public func locationManager(manager: CLLocationManager, didStartMonitoringForRegion region: CLRegion) {
        
    }
    
    public func locationManager(manager: CLLocationManager, didExitRegion region: CLRegion) {
        
        self.locationManager.stopMonitoring(for: region)
        
        guard let completion = self.didEnterRegionCompletionHandlers[region.identifier] else {
            return
        }
        
        completion(region, nil)
        
        self.didEnterRegionCompletionHandlers[region.identifier] = nil
    }
    
    public func locationManager(manager: CLLocationManager, monitoringDidFailForRegion region: CLRegion?, withError error: NSError) {
        
        guard let region = region else {
            return
        }
        
        self.locationManager.stopMonitoring(for: region)
        
        guard let completion = self.didEnterRegionCompletionHandlers[region.identifier] else {
            return
        }
        
        completion(nil, NSError(domain: "", code: 503, userInfo: nil))
        
        self.didEnterRegionCompletionHandlers[region.identifier] = nil
    }
    
    // MARK: - 
    
    public func updateLocation(completionHandler :@escaping LocationCompletionHandler) {
        
        self.locationCompletionHandlers.append(completionHandler)
        self.handleLocationStatus(status: CLLocationManager.authorizationStatus())
    }
    
    public func reverseGeocodeLocation(type :ReverseGeoCodingType = .APPLE, completionHandler :@escaping ReverseGeocodeCompletionHandler) {
        
        self.reverseGeocodingCompletionHandler = completionHandler
            
        self.updateLocation { (latitude, longitude, status, error) in
            
            guard error == nil else {
                return completionHandler("", "", "", nil, nil, error)
            }
            
            switch type {
            case .APPLE:
                self.reverseGeocodeApple()
            case .GOOGLE:
                self.reverseGeocodeGoogle()
            }
        }
    }
    
    private func reverseGeocodeApple() {
        
        let geocoder: CLGeocoder = CLGeocoder()
        let location = CLLocation(latitude: self.latitude, longitude: self.longitude)
        
        geocoder.reverseGeocodeLocation(location) { (placemarks, error) in
            
            guard let completionHandler = self.reverseGeocodingCompletionHandler else {
                return
            }
            
            guard error == nil else {
                return completionHandler("", "", "", nil, nil, error)
            }
            
            guard let placemark = placemarks?.first else {
                
                let error = NSError(domain: "", code: 0, userInfo: nil)
                return completionHandler("", "", "", nil, nil, error)
            }
            
            self.country = placemark.addressDictionary!["CNPostalAddress.ISOCountryCode"] as? String
            self.state = placemark.addressDictionary!["CNPostalAddress.state"] as? String
            self.city = placemark.addressDictionary!["CNPostalAddress.city"] as? String
            
            completionHandler(self.country, self.state, self.city, nil, placemark, nil)
        }
    }
 
    private func reverseGeocodeGoogle() {
 
        let url = String(format: googleAPI, arguments: [latitude, longitude])
 
        let request = URLRequest(url: URL(string: url)!)
 
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
 
            let response = response as? HTTPURLResponse
 
            guard let statusCode = response?.statusCode, statusCode == 200 else {
                return
            }
            
            guard let result = try! JSONSerialization.jsonObject(with: data!, options: JSONSerialization.ReadingOptions.init(rawValue: 0)) as? [String:AnyObject], let status = result["status"] as? String else {
                return
            }
            
            let googleAPIStatus = GoogleAPIStatus(rawValue: status.uppercased())!
            
            switch googleAPIStatus {
            case .OK:
                
                guard let results = result["results"] as? [NSDictionary] else {
                    return
                }
                
                var city, state, country :String?
                
                for result in results {
                    
                    guard let components = result["address_components"] as? [NSDictionary] else {
                        break
                    }
                    
                    for component in components {
                        
                        // TODO: Check that info is set and break?
                        
                        guard let types = component["types"] as? [String] else {
                            continue
                        }
                        
                        let longName = component["long_name"] as? String
                        let shortName = component["short_name"] as? String
                        
                        if types.contains("country") {
                            country = shortName
                        }
                        else if types.contains("administrative_area_level_1") {
                            state = shortName
                        }
                        else if types.contains("administrative_area_level_2") {
                            city = longName
                        }
                        else if types.contains("locality") {
                            city = longName
                        }
                    }
                }
                
                self.country = country
                self.state = state
                self.city = city
                
                UserDefaults.standard.set(country, forKey: self.kLastLocationCountry)
                UserDefaults.standard.set(state, forKey: self.kLastLocationState)
                UserDefaults.standard.set(city, forKey: self.kLastLocationCity)
                
                guard let completionHandler = self.reverseGeocodingCompletionHandler else {
                    return
                }
                
                completionHandler(self.country, self.state, self.city, results as AnyObject?, nil, nil)
                
            default:
                
                guard let completionHandler = self.reverseGeocodingCompletionHandler else {
                    return
                }
                
                let error = NSError(domain: "", code: 0, userInfo: nil)
                
                completionHandler("", "", "", nil, nil, error)
            }
        }
        
        task.resume()
    }
 
    // MARK: - Location Manager Delegate
 
    public func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
 
        guard let location = locations.last else {
            return
        }
        
        let timeSinceLastUpdate = location.timestamp.timeIntervalSinceNow
 
        // Check for cached location and invalid measurement
        guard fabs(timeSinceLastUpdate) < 5.0 && Double(location.horizontalAccuracy) > 0.0 else {
            return
        }
        
        manager.stopUpdatingLocation()
        
        let currentLocation = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let lastUpdate = UserDefaults.standard.object(forKey: kLastLocationUpdate) as? NSDate
        
        guard locationCompletionHandlers.count > 0 else {
            return
        }
        
        while locationCompletionHandlers.count > 0 {
            
            guard let completionHandler = locationCompletionHandlers.removeFirst() else {
                return
            }
            
            self.longitude = location.coordinate.longitude
            self.latitude = location.coordinate.latitude
            
            // Check for distance since last measurement
            guard fabs(currentLocation.distance(from: location)) > updateDistanceThreshold else {
                return completionHandler(latitude, longitude, .DISTANCE, nil)
            }
            
            // Check for time since last measurement
            guard lastUpdate == nil || fabs((lastUpdate?.timeIntervalSinceNow)!) > updateTimeintervalThreshold else {
                return completionHandler(latitude, longitude, .TIME, nil)
            }
            
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: kLocationUpdated), object: nil)
            
            UserDefaults.standard.set(NSDate(), forKey: kLastLocationUpdate)
            UserDefaults.standard.set(self.latitude, forKey: kLastLocationLatitude)
            UserDefaults.standard.set(self.longitude, forKey: kLastLocationLongitude)
            
            completionHandler(self.latitude, self.longitude, .OK, nil)
        }
    }
 
    public func locationManager(manager: CLLocationManager, didFailWithError error: NSError) {
        
        manager.stopUpdatingLocation()
        
        while locationCompletionHandlers.count > 0 {
            
            guard let completionHandler = locationCompletionHandlers.removeFirst() else {
                return
            }
        
            completionHandler(latitude, longitude, .ERROR, error)
        }
    }
    
    public func locationManager(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        
        self.handleLocationStatus(status: status)
        
        guard let authorizationChangedCompletionHandler = self.authorizationChangedCompletionHandler else {
            return
        }
        
        authorizationChangedCompletionHandler(manager, status)
    }
    
    // MARK: - Utils
    
    public func getLocation() -> CLLocation? {
        
        guard let longitude = self.longitude as? Double, let latitude = self.latitude as? Double else {
            return nil
        }
        
        return CLLocation(latitude: latitude, longitude: longitude)
    }
    
    private func handleLocationStatus(status :CLAuthorizationStatus) {
        
        guard CLLocationManager.locationServicesEnabled() else {
            return // TOOD: Error message
        }
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            self.locationManager.startUpdatingLocation()
        case .denied:
            // TODO: Handle denied
            break;
        case .notDetermined, .restricted:
            self.locationManager.requestWhenInUseAuthorization()
        }
    }
    
    public func requestAuthorization(status :CLAuthorizationStatus, callback: LocationAuthorizationChanged? = nil) {
        
        self.authorizationChangedCompletionHandler = callback
        
        switch status {
        case .authorizedAlways:
            self.locationManager.requestAlwaysAuthorization()
        default:
            self.locationManager.requestWhenInUseAuthorization()
        }
    }

}
