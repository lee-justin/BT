//
//  BTLECentralViewController.swift
//  BT
//
//  Created by King Justin on 7/13/16.
//  Copyright © 2016 justinleesf. All rights reserved.
//

import UIKit
import CoreBluetooth

class BTLECentralViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate {
    

    @IBOutlet weak var textview: UITextView!

    
    let TRANSFER_SERVICE_UUID = "E20A39F4-73F5-4BC4-A12F-17D1AD07A961"
    let TRANSFER_CHARACTERISTIC_UUID = "08590F7E-DB05-467E-8757-72F6FAEB13D4"
    
    var centralManager: CBCentralManager?
    var discoveredPeripheral: CBPeripheral?
    var data: NSMutableData?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        self.data = NSMutableData()
    }
    
    override func viewWillDisappear(animated: Bool) {
        // Don't keep it going while we're not showing.
        if let actualCentralManager = self.centralManager {
            actualCentralManager.stopScan()
            print("Scanning stopped")
        }
        super.viewWillDisappear(animated)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Bluetooth Central Methods
    func centralManagerDidUpdateState(central: CBCentralManager) {
        if central.state != .PoweredOn {
            // In a real app, you'd deal with all the states correctly
            return
        }
        // The state must be CBCentralManagerStatePoweredOn...
        // ... so start scanning
        self.scan()
    }
    
    // Scan for peripherals - specifically for our service's 128bit CBUUID
    func scan() {
        if let actualCentralManager = self.centralManager {
            actualCentralManager.scanForPeripheralsWithServices([CBUUID(string: TRANSFER_SERVICE_UUID)], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            print("Scanning started")
        }
    }
    
    // This callback comes whenever a peripheral that is advertising the TRANSFER_SERVICE_UUID is discovered.
    // We check the RSSI, to make sure it's close enough that we're interested in it, and if it is,
    // we start the connection process
    func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
        // Reject any where the value is above reasonable range
        if RSSI.integerValue > -15 {
            return
        }
        // Reject if the signal strength is too low to be close enough (Close is around -22dB)
        if RSSI.integerValue < -35 {
            return
        }
        print("Discovered \(peripheral.name) at \(RSSI)")
        // Ok, it's in range - have we already seen it?
        if self.discoveredPeripheral != peripheral {
            // Save a local copy of the peripheral, so CoreBluetooth doesn't get rid of it
            self.discoveredPeripheral = peripheral
            // And connect
            print("Connecting to peripheral \(peripheral)")
            if let actualCentralManager = self.centralManager {
             actualCentralManager.connectPeripheral(peripheral, options: nil)
            }
        }
    }
    
    // If the connection fails for whatever reason, we need to deal with it.
    func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        print("Failed to connect to \(peripheral). (\(error!.localizedDescription))")
        self.cleanup()
    }
    
    // We've connected to the peripheral, now we need to discover the services and characteristics to find the 'transfer' characteristic.
    func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
        print("Peripheral Connected")
        // Stop scanning
        if let actualCentralManager = self.centralManager {
            actualCentralManager.stopScan()
            print("Scanning stopped")
        }
        // Clear the data that we may already have
        if let actualData = self.data {
            actualData.length = 0
        }
        // Make sure we get the discovery callbacks
        peripheral.delegate = self
        // Search only for services that match our UUID
        peripheral.discoverServices([CBUUID(string: TRANSFER_SERVICE_UUID)])
    }
    
    // The Transfer Service was discovered
    func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
        if let actualError = error {
            print("Error discovering services: \(error!.localizedDescription)")
            self.cleanup()
            return
        }
        // Discover the characteristic we want...
        // Loop through the newly filled peripheral.services array, just in case there's more than one.
        for service: CBService in peripheral.services! {
            peripheral.discoverCharacteristics([CBUUID(string: TRANSFER_CHARACTERISTIC_UUID)], forService: service)
        }
    }
    
    // The Transfer characteristic was discovered.
    //  Once this has been found, we want to subscribe to it, which lets the peripheral know we want the data it contains
    func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
        // Deal with errors (if any)
        if let actualError = error {
            print("Error discovering characteristics: \(actualError)")
            self.cleanup()
            return
        }
        // Again, we loop through the array, just in case.
        for characteristic: CBCharacteristic in service.characteristics! {
            // And check if it's the right one
            if characteristic.UUID.isEqual(CBUUID(string: TRANSFER_CHARACTERISTIC_UUID)) {
                // If it is, subscribe to it
                peripheral.setNotifyValue(true, forCharacteristic: characteristic)
            }
        }
        // Once this is complete, we just need to wait for the data to come in.
    }
    
    /** This callback lets us know more data has arrived via notification on the characteristic
     */
    func peripheral(peripheral: CBPeripheral, didUpdateValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        if let actualError = error {
            print("Error discovering characteristics: \(error!.localizedDescription)")
            return
        }
        var stringFromData: String = String(data: characteristic.value!, encoding: NSUTF8StringEncoding)!
        // Have we got everything we need?
        if (stringFromData == "EOM") {
            // We have, so show the data,
            self.textview.text = String(data: self.data!, encoding: NSUTF8StringEncoding)
            // Cancel our subscription to the characteristic
            peripheral.setNotifyValue(false, forCharacteristic: characteristic)
            // and disconnect from the peripehral
            if let actualCentralManager = self.centralManager {
                actualCentralManager.cancelPeripheralConnection(peripheral)
            }
            
        }
        // Otherwise, just add the data on to what we already have
        if let actualData = self.data {
            actualData.appendData(characteristic.value!)
        }
        
        // Log it
        print("Received: \(stringFromData)")
    }
    
    // The peripheral letting us know whether our subscribe/unsubscribe happened or not
    
    func peripheral(peripheral: CBPeripheral, didUpdateNotificationStateForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        if let actualError = error {
         print("Error changing notification state: \(error!.localizedDescription)")
        }
        // Exit if it's not the transfer characteristic
        if !characteristic.UUID.isEqual(CBUUID(string: TRANSFER_CHARACTERISTIC_UUID)) {
            return
        }
        // Notification has started
        if characteristic.isNotifying {
            print("Notification began on \(characteristic)")
        }
        else {
            // so disconnect from the peripheral
            print("Notification stopped on \(characteristic).  Disconnecting")
            if let actualCentralManager = self.centralManager {
                actualCentralManager.cancelPeripheralConnection(peripheral)
            }
        }
    }
    
    // Once the disconnection happens, we need to clean up our local copy of the peripheral
    func centralManager(central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        print("Peripheral Disconnected")
        self.discoveredPeripheral = nil
        // We're disconnected, so start scanning again
        self.scan()
    }
    
    func cleanup() {
        //Dont do anything if not connected
//        if .Disconnected {
//            return
//        }
        // See if we are subscribed to a characteristic on the peripheral
        if self.discoveredPeripheral!.services != nil {
            for service: CBService in self.discoveredPeripheral!.services! {
                if service.characteristics != nil {
                    for characteristic: CBCharacteristic in service.characteristics! {
                        if characteristic.UUID.isEqual(CBUUID(string: TRANSFER_CHARACTERISTIC_UUID)) {
                            if characteristic.isNotifying {
                                // It is notifying, so unsubscribe
                                self.discoveredPeripheral!.setNotifyValue(false, forCharacteristic: characteristic)
                                // And we're done.
                                return
                            }
                        }
                    }
                }
            }
        }
        // If we've got this far, we're connected, but we're not subscribed, so we just disconnect
        self.centralManager!.cancelPeripheralConnection(self.discoveredPeripheral!)
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
