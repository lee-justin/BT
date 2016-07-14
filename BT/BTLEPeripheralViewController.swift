//
//  BTLEPeripheralViewController.swift
//  BT
//
//  Created by King Justin on 7/13/16.
//  Copyright © 2016 justinleesf. All rights reserved.
//

import UIKit
import CoreBluetooth
class BTLEPeripheralViewController: UIViewController, CBPeripheralManagerDelegate, UITextViewDelegate {
    
    @IBOutlet weak var advertisingSwitch: UISwitch!
    @IBOutlet weak var textView: UITextView!
    
    let NOTIFY_MTU = 20
    let TRANSFER_SERVICE_UUID = "E20A39F4-73F5-4BC4-A12F-17D1AD07A961"
    let TRANSFER_CHARACTERISTIC_UUID = "08590F7E-DB05-467E-8757-72F6FAEB13D4"
    
    var peripheralManager: CBPeripheralManager?
    var transferCharacteristic: CBMutableCharacteristic?
    var dataToSend: NSData?
    var sendDataIndex: NSInteger?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        // Start up the CBPeripheralManager
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    override func viewWillDisappear(animated: Bool) {
        // Don't keep it going while we're not showing.
        if let actualPeripheralManager = self.peripheralManager {
            actualPeripheralManager.stopAdvertising()
        }
        
        super.viewWillDisappear(animated)
    }
    
    // Mark: - Peripheral Methods
    
    /** Required protocol method.  A full app should take care of all the possible states,
     *  but we're just waiting for  to know when the CBPeripheralManager is ready
     */
    
    func peripheralManagerDidUpdateState(peripheral: CBPeripheralManager) {
        // Opt out from any other state
        if peripheral.state != .PoweredOn {
            return
        }
        // We're in CBPeripheralManagerStatePoweredOn state...
        print("self.peripheralManager powered on.")
        // ... so build our service.
        // Start with the CBMutableCharacteristic
        self.transferCharacteristic = CBMutableCharacteristic(type: CBUUID(string: TRANSFER_CHARACTERISTIC_UUID), properties: .Notify, value: nil, permissions: .Readable)
        // Then the service
        var transferService: CBMutableService = CBMutableService(type: CBUUID(string: TRANSFER_SERVICE_UUID), primary: true)
        // Add the characteristic to the service
        transferService.characteristics = [self.transferCharacteristic!]
        // And add it to the peripheral manager
        self.peripheralManager!.addService(transferService)
    }
    
    // Catch when someone subscribes to our characteristic, then start sending them data
    func peripheralManager(peripheral: CBPeripheralManager, central: CBCentral, didSubscribeToCharacteristic characteristic: CBCharacteristic) {
        print("Central subscribed to characteristic")
        // Get the data
        self.dataToSend = self.textView.text!.dataUsingEncoding(NSUTF8StringEncoding)
        // Reset the index
        self.sendDataIndex = 0
        // Start sending
        self.sendData()
    }
    /** Recognise when the central unsubscribes
     */
    
    func peripheralManager(peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFromCharacteristic characteristic: CBCharacteristic) {
        print("Central unsubscribed from characteristic")
    }
    
    /** Sends the next amount of data to the connected central
     */
    
    func sendData() {
        // First up, check if we're meant to be sending an EOM
        var sendingEOM: Bool = false
        if sendingEOM {
            // send it
            var didSend: Bool = self.peripheralManager!.updateValue("EOM".dataUsingEncoding(NSUTF8StringEncoding)!, forCharacteristic: self.transferCharacteristic!, onSubscribedCentrals: nil)
            // Did it send?
            if didSend {
                // It did, so mark it as sent
                sendingEOM = false
                print("Sent: EOM")
            }
            // It didn't send, so we'll exit and wait for peripheralManagerIsReadyToUpdateSubscribers to call sendData again
            return
        }
        // We're not sending an EOM, so we're sending data
        // Is there any left to send?
        if self.sendDataIndex >= self.dataToSend!.length {
            // No data left.  Do nothing
            return
        }
        // There's data left, so send until the callback fails, or we're done.
        var didSend: Bool = true
        while didSend {
            // Make the next chunk
            // Work out how big it should be
            var amountToSend: Int = self.dataToSend!.length - self.sendDataIndex!
            // Can't be longer than 20 bytes
            if amountToSend > NOTIFY_MTU {
                amountToSend = NOTIFY_MTU
            }
            // Copy out the data we want
            var chunk: NSData = NSData(bytes: self.dataToSend!.bytes + self.sendDataIndex!, length: amountToSend)
            // Send it
            didSend = self.peripheralManager!.updateValue(chunk, forCharacteristic: self.transferCharacteristic!, onSubscribedCentrals: nil)
            // If it didn't work, drop out and wait for the callback
            if !didSend {
                return
            }
            var stringFromData: String = String(data: chunk, encoding: NSUTF8StringEncoding)!
            print("Sent: \(stringFromData)")
            // It did send, so update our index
            // ******************************************************************************************************************************************************************************************
            if var actualSendDataIndex = self.sendDataIndex {
                actualSendDataIndex += amountToSend
            }
            // Was it the last one?
            if self.sendDataIndex >= self.dataToSend!.length {
                // It was - send an EOM
                // Set this so if the send fails, we'll send it next time
                sendingEOM = true
                // Send it
                var eomSent: Bool = self.peripheralManager!.updateValue("EOM".dataUsingEncoding(NSUTF8StringEncoding)!, forCharacteristic: self.transferCharacteristic!, onSubscribedCentrals: nil)
                if eomSent {
                    // It sent, we're all done
                    sendingEOM = false
                    print("Sent: EOM")
                }
                return
            }
        }
    }
   
    // This callback comes in when the PeripheralManager is ready to send the next chunk of data.
    // This is to ensure that packets will arrive in the order they are sent
    func peripheralManagerIsReadyToUpdateSubscribers(peripheral: CBPeripheralManager) {
        // Start sending again
        self.sendData()
    }
    // MARK: - TextView Methods
    /** This is called when a change happens, so we know to stop advertising
     */
    
    func textViewDidChange(textView: UITextView) {
        // If we're already advertising, stop
        print("text view did change")
        if self.advertisingSwitch.on {
            self.advertisingSwitch.on = false
            if let actualPeripheralManager = self.peripheralManager {
                actualPeripheralManager.stopAdvertising()
            }
        }
    }
    /** Adds the 'Done' button to the title bar
     */
    
    func textViewDidBeginEditing(textView: UITextView) {
        // We need to add this manually so we have a way to dismiss the keyboard
        var rightButton: UIBarButtonItem = UIBarButtonItem(title: "Done", style: .Done, target: self, action: #selector(self.dismissKeyboard))
        self.navigationItem.rightBarButtonItem = rightButton
    }
    /** Finishes the editing */
    
    func dismissKeyboard() {
        self.textView.resignFirstResponder()
        self.navigationItem.rightBarButtonItem = nil
    }
    // MARK: - Switch Methods
    /** Start advertising
     */
    
    @IBAction func switchChanged(sender: AnyObject) {
        if self.advertisingSwitch.on {
            // All we advertise is our service's UUID
            if let actualPeripheralManager = self.peripheralManager {
                actualPeripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: TRANSFER_SERVICE_UUID)]])
            }
        }
        else {
            if let actualPeripheralManager = self.peripheralManager {
                actualPeripheralManager.stopAdvertising()
            }
        }
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
