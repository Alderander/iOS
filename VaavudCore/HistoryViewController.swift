//
//  THistoryViewController.swift
//  Vaavud
//
//  Created by Diego R on 12/3/15.
//  Copyright © 2015 Andreas Okholm. All rights reserved.
//

import UIKit
import Firebase
import VaavudSDK

// Reflection with computed properties
// Parse NSDate to Double using timeIntervalSince1970
// use optionals for things that are not known in the beginnning
// the parser should not set properties where the value is nil ( dict["windMean"] = windMean )
// NSDataFormatter : use VaavudFormatter



struct Location {
    
    var altitude: Float?
    var lat: Double
    var lon: Double
    var name: String?
    
    init?(location: [String:AnyObject]){
        guard let lat = location["lat"] as? Double, let lon = location["lon"] as? Double else{
            return nil
        }
        
        if let name = location["name"] as? String {
            self.name = name
        }
        
        if let altitude = location["altitude"] as? Float {
            self.altitude = altitude
        }
        
        self.lat = lat
        self.lon = lon
    }
    
    
    func dict() -> FirebaseDictionary {
        var dic = FirebaseDictionary()
        
        dic["altitude"] = altitude
        dic["lat"] = lat
        dic["lon"] = lon
        dic["name"] = name
        
        return dic
    }
    
}

struct Sourced {
    
    let humidity: Float
    let icon: String
    let pressure: Float
    let temperature: Float
    let windDirection: Float
    let windMean: Float
    
    init?(sourced: [String:AnyObject]) {
        guard let himidity = sourced["humidity"] as? Float,
            icon = sourced["icon"] as? String,
            pressure = sourced["pressure"] as? Float,
            temperature = sourced["temperature"] as? Float,
            windDirection = sourced["windBearing"] as? Float,
            windSpeed = sourced["windSpeed"] as? Float else {
            return nil
        }
        
        self.humidity = himidity
        self.icon = icon
        self.pressure = pressure
        self.temperature = temperature
        self.windDirection = windDirection
        self.windMean = windSpeed
    }
    
    func dict() -> FirebaseDictionary {
        return ["humidity": humidity, "icon": icon, "pressure": pressure, "temperature": temperature, "windDirection": windDirection, "windMean": windMean]
    }
}


struct Wind {
    
    var direction: Float?
    let speed: Float
    let time: Double
    
    init(speed: Float, time: Double){
        self.speed = speed
        self.time = time
    }
    
    func fireDict() -> FirebaseDictionary {
        var dict = FirebaseDictionary()
        dict["direction"] = direction
        dict["speed"] = speed
        dict["time"] = time
        
        return dict
    }
}

struct Session {
    
    let deviceKey: String
    var key: String?
    let timeStart: NSDate
    var timeEnd: Float?
    var windDirection: Float?
    var windMax: Float?
    var windMean: Float?
    let uid: String
    let windMeter: String
    var sourced: Sourced?
    var location: Location?
    var turbulence: Float?
    var wind = [Wind]()
    
    init(snapshot: FDataSnapshot) {
        key = snapshot.key
        uid = snapshot.value["uid"] as! String
        deviceKey = snapshot.value["deviceKey"] as! String
        timeStart = NSDate(ms: snapshot.value["timeStart"] as! NSNumber)
        timeEnd = snapshot.value["timeEnd"] as? Float
        windDirection = snapshot.value["windDirection"] as? Float
        windMax = snapshot.value["windMax"] as? Float
        windMean = snapshot.value["windMean"] as? Float
        windMeter = snapshot.value["windMeter"] as! String
        turbulence = snapshot.value["turbulence"] as? Float
        
        if let sourced = snapshot.value["sourced"] as? [String:AnyObject] {
            self.sourced = Sourced(sourced: sourced)
        }
        
        
        if let location = snapshot.value["location"] as? [String:AnyObject] {
            self.location = Location(location: location)
        }
    }
    
    init(uid:String, deviceId: String, timeStart: NSDate, windMeter: String){
        self.uid = uid
        self.deviceKey = deviceId
        self.timeStart = timeStart
        self.windMeter = windMeter
    }
    
    
    func initDict() -> FirebaseDictionary {
        var dict = FirebaseDictionary()
        dict["deviceKey"] = deviceKey
        dict["uid"] = uid
        dict["timeStart"] = timeStart.ms
        dict["windMeter"] = windMeter
        
        return dict
    }
    
    func fireDict() -> FirebaseDictionary {
        var dict = FirebaseDictionary()
        dict["uid"] = uid
        dict["deviceKey"] = deviceKey
        dict["timeStart"] = timeStart.ms
        dict["timeEnd"] = timeEnd
        dict["windMax"] = windMax
        dict["windDirection"] = windDirection
        dict["windMean"] = windMean
        dict["windMeter"] = windMeter
        dict["sourced"] = sourced?.dict()
        dict["location"] = location?.dict()
        dict["turbulence"] = turbulence
        
        return dict
    }
}


class HistoryViewController: UITableViewController, HistoryDelegate {
    
    var sessions = [[Session]]()
    var sessionDates = [String]()
    var controller: HistoryController?
    let spinner = MjolnirSpinner(frame: CGRectMake(100, 100, 100, 100))
    

    override func viewDidLoad() {
        super.viewDidLoad()
    
        spinner.alpha = 0.4
        spinner.center = tableView.bounds.center
        tableView.addSubview(spinner)
        spinner.show()
        
        controller = HistoryController(delegate: self)
    }
    
    func updateTable(sessions: [[Session]], sessionDates: [String]) {
        self.sessions = sessions
        self.sessionDates = sessionDates
        
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            self.tableView.reloadData()
        })

    }
    
    
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return sessions.count
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sessions[section].count
    }

    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        
        guard let cell = tableView.dequeueReusableCellWithIdentifier("HistoryCell", forIndexPath: indexPath) as? HistoryCell else{
            fatalError("Unknonw Cell")
        }
        
        cell.time.text = VaavudFormatter.shared.localizedTime(sessions[indexPath.section][indexPath.row].timeStart)
        
        if let windDirection = sessions[indexPath.section][indexPath.row].windDirection {
            cell.directionUnit.text = VaavudFormatter.shared.localizedDirection(windDirection)
            cell.directionArrow.transform = CGAffineTransformMakeRotation(CGFloat(windDirection) / 180 * CGFloat(π))
        }
        else{
            cell.directionUnit.hidden = true
            cell.directionArrow.hidden = true
        }
        
        cell.speedUnit.text = VaavudFormatter.shared.windSpeedUnit.localizedString
        cell.speed.text = VaavudFormatter.shared.localizedWindspeed(sessions[indexPath.section][indexPath.row].windMean)
        
        if let loc = sessions[indexPath.section][indexPath.row].location {
            
            if let name = loc.name {
                cell.location.text = name
            }
            else{
                cell.location.text = "Unknown"
            }
        }
        else{
            cell.location.text = "Unknown"
        }
            
        return cell
    }
    
    
    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            
            guard let sessionKey = sessions[indexPath.section][indexPath.row].key else {
                fatalError("no session key")
            }
            let sessionDeleted = sessions[indexPath.section][indexPath.row]
            
            sessions[indexPath.section].removeAtIndex(indexPath.row)
            tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
            
            
            if let controller = controller {
                controller.removeItem(sessionKey, sessionDeleted: sessionDeleted, section: indexPath.section, row: indexPath.row)
                print(sessionKey)
            }
        }
    }
    
    
    override func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let headerCell = tableView.dequeueReusableCellWithIdentifier("HistoryHeaderCell") as? HistoryHeaderCell else{
            fatalError("Unknown Cell")
        }
        
        headerCell.titleLabel.text = sessionDates[section]
        
        return headerCell.contentView
    }
    
    func hideSpinner() {
        spinner.hide()
        print("hide")
    }
    
    func noMeasurements() {
        
    }
    
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
        
        let currentSession = sessions[indexPath.section][indexPath.row]
        
        if let summary = self.storyboard?.instantiateViewControllerWithIdentifier("SummaryViewController") as? CoreSummaryViewController {
            summary.session = currentSession
            summary.historySummary = true
            
            navigationController?.pushViewController(summary, animated: true)
        }
        
        
        //NSUserDefaults.standardUserDefaults().removeObjectForKey("deviceId")
        
    }
    
    override func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 25.0
    }
}
