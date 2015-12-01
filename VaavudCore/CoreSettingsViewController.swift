//
//  CoreSettingsViewController.swift
//  Vaavud
//
//  Created by Gustaf Kugelberg on 11/02/15.
//  Copyright (c) 2015 Andreas Okholm. All rights reserved.
//

import Foundation

class CoreSettingsTableViewController: UITableViewController {
    let interactions = VaavudInteractions()
    
    @IBOutlet weak var limitControl: UISegmentedControl!
    
    @IBOutlet weak var logoutButton: UIBarButtonItem!
    @IBOutlet weak var meterTypeControl: UISegmentedControl!
    
    @IBOutlet weak var speedUnitControl: UISegmentedControl!
    @IBOutlet weak var directionUnitControl: UISegmentedControl!
    @IBOutlet weak var pressureUnitControl: UISegmentedControl!
    @IBOutlet weak var temperatureUnitControl: UISegmentedControl!

    @IBOutlet weak var dropboxControl: UISwitch!
    @IBOutlet weak var sleipnirClipControl: UISegmentedControl!
    
    @IBOutlet weak var sleipnirClipCell: UITableViewCell!
    
    @IBOutlet weak var sleipnirClipView: UIView!
    
    @IBOutlet weak var versionLabel: UILabel!
    
    private let logHelper = LogHelper(.Settings, counters: "scrolled")
    
    override func viewDidLoad() {
        hideVolumeHUD()
        
        versionLabel.text = NSBundle.mainBundle().infoDictionary?["CFBundleShortVersionString"] as? String
        
        dropboxControl.on = DBSession.sharedSession().isLinked()
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "unitsChanged:", name: KEY_UNIT_CHANGED, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "wasLoggedInOut:", name: KEY_DID_LOGINOUT, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "dropboxLinkedStatus:", name: KEY_IS_DROPBOXLINKED, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "modelChanged:", name: KEY_WINDMETERMODEL_CHANGED, object: nil)
        
        readUnits()
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        refreshLogoutButton()
        refreshWindmeterModel()
        refreshTimeLimit()
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        logHelper.began()
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        logHelper.ended()
    }
    
    func modelChanged(note: NSNotification) {
        refreshWindmeterModel()
    }

    func wasLoggedInOut(note: NSNotification) {
        refreshLogoutButton()
    }
    
    func refreshLogoutButton() {
        let titleKey = AccountManager.sharedInstance().isLoggedIn() ? "REGISTER_BUTTON_LOGOUT" : "REGISTER_BUTTON_LOGIN"
        logoutButton.title = NSLocalizedString(titleKey, comment: "")
    }
    
    func refreshWindmeterModel() {
        let usesSleipnir = Property.getAsBoolean(KEY_USES_SLEIPNIR, defaultValue: false)
        meterTypeControl.selectedSegmentIndex = usesSleipnir ? 1 : 0
        
        let sleipnirOnFront = Property.getAsBoolean(KEY_SLEIPNIR_ON_FRONT, defaultValue: false)
        sleipnirClipControl.selectedSegmentIndex = sleipnirOnFront ? 1 : 0
        UIView.animateWithDuration(0.2) {
            self.sleipnirClipView.alpha = usesSleipnir ? 1 : 0
        }
        
        LogHelper.setUserProperty("Device", value: usesSleipnir ? "Sleipnir" : "Mjolnir")
        LogHelper.setUserProperty("Sleipnir-Clip-Frontside", value: sleipnirOnFront)
    }
    
    func refreshTimeLimit() {
        let unlimited = Property.getAsBoolean(KEY_MEASUREMENT_TIME_UNLIMITED)
        LogHelper.setUserProperty("Measurement-Limit", value: unlimited ? 0 : limitedInterval)
        limitControl.selectedSegmentIndex = unlimited ? 1 : 0
    }
    
    func unitsChanged(note: NSNotification) {
        if note.object as? CoreSettingsTableViewController != self {
            readUnits()
        }
    }
    
    func dropboxLinkedStatus(note: NSNotification) {
        if let isDropboxLinked = note.object as? NSNumber.BooleanLiteralType {
            dropboxControl.on = isDropboxLinked
            let value = isDropboxLinked ? "Linking succeeded" : "Linking failed"
            if Property.isMixpanelEnabled() {
                Mixpanel.sharedInstance().track("Dropbox", properties: ["Action" : value])
            }
        }
    }
    
    func postUnitChange(unitType: String) {
        NSNotificationCenter.defaultCenter().postNotificationName(KEY_UNIT_CHANGED, object: self)
        LogHelper.log(event: "Changed-Unit", properties: ["place" : "settings", "type" : unitType])
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    func readUnits() {
        if let speedUnit = Property.getAsInteger(KEY_WIND_SPEED_UNIT)?.integerValue {
            speedUnitControl.selectedSegmentIndex = speedUnit
        }
        if let directionUnit = Property.getAsInteger(KEY_DIRECTION_UNIT)?.integerValue {
            directionUnitControl.selectedSegmentIndex = directionUnit
        }
        if let pressureUnit = Property.getAsInteger(KEY_PRESSURE_UNIT)?.integerValue {
            pressureUnitControl.selectedSegmentIndex = pressureUnit
        }
        if let temperatureUnit = Property.getAsInteger(KEY_TEMPERATURE_UNIT)?.integerValue {
            temperatureUnitControl.selectedSegmentIndex = temperatureUnit
        }
    }
        
    @IBAction func logInOutTapped(sender: AnyObject) {
        if AccountManager.sharedInstance().isLoggedIn() {
            interactions.showLocalAlert("REGISTER_BUTTON_LOGOUT",
                messageKey: "DIALOG_CONFIRM",
                cancelKey: "BUTTON_CANCEL",
                otherKey: "BUTTON_OK",
                action: { self.logoutConfirmed() },
                on: self)
        }
        else {
            registerUser()
        }
        logHelper.increase()
    }
    
    func logoutConfirmed() {
        AccountManager.sharedInstance().logout()
        LogHelper.log(event: "Logged-Out", properties: ["place" : "settings"])
    }
    
    func registerUser() {
        let storyboard = UIStoryboard(name: "Register", bundle: nil)
        let registration = storyboard.instantiateViewControllerWithIdentifier("RegisterViewController") as! RegisterViewController
        registration.teaserLabelText = NSLocalizedString("HISTORY_REGISTER_TEASER", comment: "")
        registration.completion = {
            print("========Login done, will try to sync") // fixme

            ServerUploadManager.sharedInstance().syncHistory(2, ignoreGracePeriod: true, success: { }, failure: { _ in })

            self.dismissViewControllerAnimated(true, completion: {
                print("========settings did dismiss") // fixme
            })
        };
        
        let navController = RotatableNavigationController(rootViewController: registration)
        presentViewController(navController, animated: true, completion: nil)
    }
    
    @IBAction func changedLimitToggle(sender: UISegmentedControl) {
        Property.setAsBoolean(sender.selectedSegmentIndex == 1, forKey: KEY_MEASUREMENT_TIME_UNLIMITED)
        refreshTimeLimit()
        logHelper.increase()
    }

    @IBAction func changedSpeedUnit(sender: UISegmentedControl) {
        Property.setAsInteger(sender.selectedSegmentIndex, forKey: KEY_WIND_SPEED_UNIT)
        postUnitChange("speed")
        logHelper.increase()
    }
    
    @IBAction func changedDirectionUnit(sender: UISegmentedControl) {
        Property.setAsInteger(sender.selectedSegmentIndex, forKey: KEY_DIRECTION_UNIT)
        postUnitChange("direction")
        logHelper.increase()
    }
    
    @IBAction func changedPressureUnit(sender: UISegmentedControl) {
        Property.setAsInteger(sender.selectedSegmentIndex, forKey: KEY_PRESSURE_UNIT)
        postUnitChange("pressure")
        logHelper.increase()
    }
    
    @IBAction func changedTemperatureUnit(sender: UISegmentedControl) {
        Property.setAsInteger(sender.selectedSegmentIndex, forKey: KEY_TEMPERATURE_UNIT)
        postUnitChange("temperature")
        logHelper.increase()
    }
    
    @IBAction func changedMeterModel(sender: UISegmentedControl) {
        let usesSleipnir = sender.selectedSegmentIndex == 1
        Property.setAsBoolean(usesSleipnir, forKey: KEY_USES_SLEIPNIR)
        refreshWindmeterModel()
        logHelper.increase()
    }

    @IBAction func changedDropboxSetting(sender: UISwitch) {
        let value: String
        if sender.on {
            DBSession.sharedSession().linkFromController(self)
            value = "Try link"
        }
        else {
            DBSession.sharedSession().unlinkAll()
            value = "Unlinked"
        }
        Mixpanel.sharedInstance().track("Dropbox", properties: ["Action" : value])
        logHelper.increase()
    }

    @IBAction func changedSleipnirPlacement(sender: UISegmentedControl) {
        let frontPlaced = sender.selectedSegmentIndex == 1
        Property.setAsBoolean(frontPlaced, forKey: KEY_SLEIPNIR_ON_FRONT)
        refreshWindmeterModel()
        logHelper.increase()
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if let webViewController = segue.destinationViewController as? WebViewController {
            if segue.identifier == "AboutSegue" {
                webViewController.html = NSLocalizedString("ABOUT_VAAVUD_TEXT", comment: "").html()
            }
            else if segue.identifier == "TermsSegue" {
                webViewController.url = VaavudInteractions.termsUrl()
                webViewController.title = NSLocalizedString("LINK_TERMS_OF_SERVICE", comment: "")
            }
            else if segue.identifier == "PrivacySegue" {
                webViewController.url = VaavudInteractions.privacyUrl()
                webViewController.title = NSLocalizedString("LINK_PRIVACY_POLICY", comment: "")
            }
            else if segue.identifier == "BuyWindmeterSegue" {
                webViewController.url = VaavudInteractions.buySleipnirUrl("settings")
                webViewController.title = NSLocalizedString("SETTINGS_SHOP_LINK", comment: "")
                LogHelper.log(event: "Pressed-Buy", properties: ["place" : "settings"])
            }
        }
        
// Fixme : make tip screen available in settings
        
        //        else if let firstTimeViewController = segue.destinationViewController as? FirstTimeFlowController {
//            FirstTimeFlowController.createInstructionFlowOn(firstTimeViewController)
//            firstTimeViewController.returnViaDismiss = true
//        }
        logHelper.increase()
    }
}

class WebViewController: UIViewController {
    @IBOutlet weak var webView: UIWebView!
    var baseUrl = NSURL(string: "http://vaavud.com")
    var html: String?
    var url: NSURL?
    
    override func viewDidLoad() {
        webView.backgroundColor = .whiteColor()
        load()
    }
    
    func load() {
        if let url = url {
            webView.loadRequest(NSURLRequest(URL: url))
        }
        else if let html = html {
            webView.loadHTMLString(html, baseURL: baseUrl)
        }
    }
}

extension String {
    func html() -> String {
        return "<html><head><style type='text/css'>a {color:#00aeef;text-decoration:none}\n" +
            "body {background-color:#f8f8f8;}</style></head><body>" +
            "<center style='padding-top:20px;font-family:helvetica,arial'>" +
            stringByReplacingOccurrencesOfString("\n" , withString: "<br/><br/>", options: []) + "</center></body></html>"
    }
}
