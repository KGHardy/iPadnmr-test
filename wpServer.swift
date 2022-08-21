//
//  wpServer.swift
//  CutDown
//
//  Created by Ken Hardy on 05/08/2022.
//

import Foundation

let redPitayaIp = "10.42.0.1"

let BLKS = 512
let BUFSIZE = 4096

// Following are hardware control lines
let PA_OFF = 0
let PA_ON = 2
let BL_OFF = 0
let BL_ON = 4

// Following forces TX to be 0
let RF_OFF = 0
let ADC_STOP = 1
let ADC_START = 0
let DC = 4

//  Line  D03 Hardware Pin 5 for field gradients
let GA_OFF = 0
let GA_ON = 8
let GA_CTRL = 0x8000
let G_OFF = 0

func saveToFile(data: [[UInt16]],fileName: String) -> Void {
    if data.count == 0 {
        return
    }
    let fm = FileManager.default
    let homeURL = fm.urls(for: .documentDirectory, in: .userDomainMask).last
    if let fileURL = homeURL?.appendingPathComponent(fileName)
    {
        var filePath = fileURL.absoluteString
        filePath.removeFirst(7)
        if fm.fileExists(atPath: filePath)
        {
            do
            {
                try fm.removeItem(at: fileURL)
            }
            catch
            {
            }
        }
        var alldata: [UInt16] = []
        for part in data {
            alldata.append(contentsOf: part)
        }
        do
        {
            try
                convertData(input: alldata).write(to: fileURL)
        } catch
        {
            print("Write Failed")
        }
    }
}



func callWpServer() -> [[Int16]] {
    
let portNumber = 1001
let ncoFreq = 16004000 //12360100
let stepFreq  = 0
let pulseLength = 5000
let pulseStep  = 0
let noScans = 1 // Changed from 4
let noExpts = 1
let rptTime = 1000
let tauTime = 0
let tauInc = 0
let tauDelay = 0
//let stepFreq  = 0 duplcated
let exptName = "FID"
let progSatArray = 1
let noData=5000
let delayInSeconds=1
let tauD=0

/*
 passingData[1]=port_Number
 passingData[2]=nco_Freq
 passingData[3]=step_Freq
 passingData[4]=pulse_Length
 passingData[5]=pulse_Step
 passingData[6]=1 ? noScans
 passingData[7]=1 ? noExpts
 passingData[8]=rpt_Time
 passingData[9]=tau_Time
 passingData[10]=tau_Inc
 passingData[11]=no_Data
 passingData[12]=delayInSeconds
 passingData[13]=tauD

 */
    let cS: [Int] = [0,
                     portNumber,
                     ncoFreq,
                     stepFreq,
                     pulseLength,
                     pulseStep,
                     noScans,
                     noExpts,
                     rptTime,
                     tauTime,
                     tauInc,
                     noData,
                     delayInSeconds,
                     tauD,
                     0,             // 14 not used
                     0]             // 15 not used
    var retData: [[Int16]] = [[]]
    if wpServer(redPitayaIp,exptName,cS,&retData) {
        return retData
    } else {
        return [[]]
    }
}

func wpServer(_ hostName: String, _ exptSelect: String,_ cS: [Int],_ nmrData: inout [[Int16]]) -> Bool {
    
    let semaphore = DispatchSemaphore(value: 1) // semaphore to signal rcvr() has exited
    
    var retval = true
    
    var iii = 0
    var rtn = 0
    let portno = cS[1]
    let ncoFreq = cS[2]
    let stepFreq = cS[3]
    let pulseLength = cS[4]
    let pulseStep = cS[5]
    let noScans = cS[6]
    let noExpts = cS[7]
    var rptTime = cS[8]
    var tauTime = cS[9]
    let tauInc = cS[10]
    let noData = cS[11]
    let delayInSeconds = cS[12]
    var tauD = cS[13]

    var noEchoes: Int = 0
    var t1Guess: Int = 0
    var pl: Int = 0
    var tau: Int = 0
    var scanCounter = 0
    
    var bufTrnr = [UInt32](repeating:0,count: BLKS + 1)
    var bufDelay = [UInt32](repeating:0,count: BLKS + 1)
    var bufCPMG = [UInt32](repeating:0,count: BLKS + 1)
    var tauSteps = [UInt32](repeating:0,count: 13)

    var retData: [[UInt16]] = []
    var retDataS: [[Int16]] = []
    var rcvIx = 0
    
    var noInstructions: Int = 0

    func updateBuf2(_ scanCounter: Int) -> Void {
        var ii : Int = 0
        
        pl = pulseLength / 8
        if pl > 3000 { pl = 3000 } // 3000*8/1000 = 24 microseconds
        if pl == 0 { pl = 750 } // 6 microseconds 750/125
        
        var d = Double(ncoFreq)
        d = d / 125.0e6
        d = d * 256.0 * 256.0 * 256.0 * 256.0
        d = d + 0.5
        bufTrnr[0] = UInt32(floor(d))
        bufTrnr[0] = 549824533
        //bufTrnr[0] = UInt32(floor(Double(ncoFreq)/125.0e6*256.0*256.0*256.0*256.0+0.5))
        bufDelay[0] = bufTrnr[0]
        bufCPMG[0] = bufTrnr[0]
        
        var reVal = [Int](repeating:0,count: BLKS / 2) // Was Int16
        var imVal = [Int](repeating:0,count: BLKS / 2) // Was Int16
        var duration = [Int](repeating:0,count: BLKS / 2) // Was UInt32
        var hwCtrl = [Int](repeating:0,count: BLKS / 2) // Was UInt8

        var reValC = [Int](repeating:0,count: BLKS / 2) // Was Int16
        var imValC = [Int](repeating:0,count: BLKS / 2) // Was Int16
        var durationC = [Int](repeating:0,count: BLKS / 2) // Was UInt32
        var hwCtrlC = [Int](repeating:0,count: BLKS / 2)  // Was UInt8

        let cntr = 0
        
        var rw = rptTime / 100000
        
        ii = 0
        while ii < (BLKS / 2 ) {
            bufDelay[2 * ii + 1] = UInt32(((PA_OFF | ADC_STOP) & 0xFF) << 24 | ((125 * 390 * rw - DC) & 0xffffff))
            bufDelay[2 * ii + 2] = UInt32((RF_OFF & 0xffff) | ((RF_OFF & 0xffff) << 16 ))
            ii += 1
        }
        
        if exptSelect == "FID" {
            noInstructions = 15
            hwCtrl[ 0] = PA_OFF | BL_OFF | ADC_STOP;  duration[ 0] = 125 * 1      - DC; reVal[ 0] = RF_OFF
            hwCtrl[ 1] = PA_OFF | BL_OFF | ADC_STOP;  duration[ 1] = 125 * 1      - DC; reVal[ 1] = RF_OFF
            hwCtrl[ 2] = PA_OFF | BL_OFF | ADC_STOP;  duration[ 2] = 125 * 1      - DC; reVal[ 2] = RF_OFF
            hwCtrl[ 3] = PA_OFF | BL_OFF | ADC_STOP;  duration[ 3] = 125 * 1      - DC; reVal[ 3] = RF_OFF
            hwCtrl[ 4] = PA_OFF | BL_OFF | ADC_STOP;  duration[ 4] = 125 * 1      - DC; reVal[ 4] = RF_OFF
            hwCtrl[ 5] = PA_ON  | BL_OFF | ADC_STOP;  duration[ 5] = 125 * 10     - DC; reVal[ 5] = RF_OFF
            hwCtrl[ 6] = PA_ON  | BL_OFF | ADC_STOP;  duration[ 6] = pl           - DC; reVal[ 6] = 8100
            hwCtrl[ 7] = PA_OFF | BL_OFF | ADC_STOP;  duration[ 7] = 125 * 5      - DC; reVal[ 7] = RF_OFF
            hwCtrl[ 8] = PA_OFF | BL_ON  | ADC_START; duration[ 8] = 125 * noData - DC; reVal[ 8] = RF_OFF
            hwCtrl[ 9] = PA_OFF | BL_OFF | ADC_STOP;  duration[ 9] = 125 * 1      - DC; reVal[ 9] = RF_OFF
            hwCtrl[10] = PA_OFF | BL_OFF | ADC_STOP;  duration[10] = 125 * 1      - DC; reVal[10] = RF_OFF
            hwCtrl[11] = PA_OFF | BL_OFF | ADC_STOP;  duration[11] = 125 * 1      - DC; reVal[11] = RF_OFF
            hwCtrl[12] = PA_OFF | BL_OFF | ADC_STOP;  duration[12] = 125 * 1      - DC; reVal[12] = RF_OFF
            hwCtrl[13] = PA_OFF | BL_OFF | ADC_STOP;  duration[13] = 125 * 1      - DC; reVal[13] = RF_OFF
            hwCtrl[14] = PA_OFF | BL_OFF | ADC_STOP;  duration[14] = 125 * 1      - DC; reVal[14] = RF_OFF
        }
        
        ii = 0
        while ii < noInstructions {
            bufTrnr[2 * ii + 1] = UInt32(((hwCtrl[ii] & 0xff) << 24) | (duration[ii] & 0xffffff))
            bufTrnr[2 * ii + 2] = UInt32((reVal[ii] & 0xffff) | (imVal[ii] << 16))
            ii += 1
        }
        ii = noInstructions
        while ii < (BLKS / 2) {
            bufTrnr[2 * ii + 1] = UInt32((((PA_OFF | ADC_STOP) & 0xff) << 24) | ((125 * 1 - DC) & 0xffffff))
            bufTrnr[2 * ii + 2] = UInt32((RF_OFF & 0xffff) | ((RF_OFF & 0xffff) << 16))
            ii += 1
        }
    }
    
    func trnr() -> Bool {
        
        let Cmd: [UInt32] = [1]
        var data: Data
        
        if exptSelect == "PROG_SAT" { return false } // cannot find any values for prog_sat_delay
        if exptSelect != "FID" { return false } // Limit to FID pro tem
        
        let socket = UserSocket(ipAddrs: hostName, port: portno)
        if !socket.connect() {
            return false
        }
        
        data = convertData(input: Cmd)
        if !socket.send(data: data) {
            socket.close()
            return false
        }
        
        iii = 0
        while iii < (noScans * noExpts) {
            scanCounter = iii
            updateBuf2(scanCounter)
            
            data = convertData(input: bufTrnr)
            if !socket.send(data: data) {
                socket.close()
                return false
            }
            data = convertData(input: bufDelay)
            if !socket.send(data: data) {
                socket.close()
                return false
            }
            iii += 1
        }
        socket.close()
        return true
    }
    
    func rcvr() -> Bool {
        let Cmd: [UInt32] = [0]
        
        var data: Data
        var rcvba: [Byte]? = []
        
        var rcvData: [UInt16] = []
        var rcvDataS: [Int16] = []
        
        var byteIndex = 0
        var currentInt: UInt16 = 0

        rcvIx = 0
        
        let expectedNodeCount = (noData + (BUFSIZE - 1)) / BUFSIZE
        
        func buildIntegers() -> Void {
            var arrayIndex = 0
            while arrayIndex < rcvba!.count {
                switch byteIndex {
                case 0:
                    currentInt  = UInt16(rcvba![arrayIndex])
                    byteIndex = 1
                case 1:
                    currentInt |= UInt16(rcvba![arrayIndex]) << 8
                    rcvData.append(currentInt)
                    rcvDataS.append(Int16(bitPattern: currentInt))
                    byteIndex = 0
                    rcvIx += 1
                    if rcvIx >= BUFSIZE {
                        retData.append(rcvData)
                        retDataS.append(rcvDataS)
                        endTime = DispatchTime.now()
                        rcvData.removeAll()
                        rcvDataS.removeAll()
                        rcvIx = 0
                    }
                    currentInt = 0
                    byteIndex = 0
                default:
                    break
                }
                arrayIndex += 1
            }
        }

        let deadline = Date().advanced(by: 0.1)
        Thread.sleep(until: deadline)
        
        let socket = UserSocket(ipAddrs: hostName, port: portno)
        if !socket.connect() {
            return false
        }
        data = convertData(input: Cmd)
        if !socket.send(data: data) { return false }
        
        var timeout = 0
        var rcvcount = 0
        
        let startTime = DispatchTime.now()
        var endTime = startTime
        

        var socketTimeout = 1
        while true {
            rcvba = socket.recv(expectedLength: 2048,timeout: socketTimeout)
            if rcvba != nil {
                timeout = 0                 // received data so reset timeout count
                rcvcount += rcvba!.count
                //print(rcvba)
                buildIntegers()
                if retData.count >= expectedNodeCount {
                    break
                }
                if ((endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / UInt64(1e9)) > delayInSeconds {
                    break
                }
            } else {
                timeout += 1
                if timeout > 9 {
                    if (rcvcount == 0)
                    {
                        print("recv failed") // failed to receive data after approx 10 seconds
                    }
                    break
                }
            }
        }
        socket.close()
        return rcvcount > 0
    }
    
    if exptSelect == "CPMG" { noEchoes = tauInc }
    if exptSelect == "CPMGX" { noEchoes = tauInc }
    if tauD > 100000 { tauD = 100000 }
    rptTime *= 1000 // change to micro seconds?
    t1Guess = tauTime
    if t1Guess > 2000 { t1Guess = 2000 }
    if tauTime < 25 && tauTime > 0 { tauTime = 25 }
    
    pl = pulseLength
    tau = tauTime
    
    semaphore.wait()
    let queue = DispatchQueue(label:"RcvQueue",qos: .userInitiated)
    queue.async {
        if !rcvr() {
            retval = false
        }
        semaphore.signal()  // rcvr() has exited
    }
    
    // rcvr is called in another thread. This thread continues to execute

    if !trnr() {
        retval = false
    }
    
    semaphore.wait()        // wait for rcvr() to exit
    semaphore.signal()      // required for possible swift bug
    
    // return received blocks in reverse order of receipt
    var ix = 0
    nmrData = []
    while ix < retData.count {
        //nmrData.append(retData[retData.count - 1 - ix])
        nmrData.append(retDataS[ix])
        ix += 1
    }
    saveToFile(data: retData,fileName: "cutdown.bin")
    saveToFile(data: [[0x1234,0x5678]],fileName: "test.bin")
    return retval
}
