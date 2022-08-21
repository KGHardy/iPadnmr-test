//
//  ContentView.swift
//  CutDown
//
//  Created by Ken Hardy on 03/08/2022.
//

import SwiftUI

var result: [[Int16]] = [[]]

struct ContentView: View {
    @State private var caption1 = "Press to start"
    //@State private var caption2 = "Press to start (Test 1)"
    //@State private var caption3 = "Press to start (Test 2)"
    @State private var gotResult = false
                 
    var body: some View {
        VStack {
            Button(caption1) {
                caption1 = "Pressed"
                gotResult = false
                let queue = DispatchQueue(label: "work-queue", qos: .userInitiated)
                queue.async {
                    result = callWpServer()
                    gotResult = result.count > 0
                    DispatchQueue.main.async {
                        caption1 = "result \(result)"
                    }
                }
            }

            //if gotResult {
                GeometryReader{reader in
                    MyGraphView()
                }
            //}
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

/*
Button(caption2) {
    caption2 = "Pressed"
    let queue = DispatchQueue(label: "work-queue", qos: .userInitiated)
    queue.async {
        var dataArray: [UInt32] = [1,120,2300,32000,340000,4500000,1,2,3,4,5,6,7,8,9,0]
        let rcvData = sendAndRecvData(sndData: &dataArray,sndOnly: true)
        DispatchQueue.main.async {
            caption2 = "\(rcvData.count) Integers"
        }
    }
}
Button(caption3) {
    caption3 = "Pressed"
    let queue = DispatchQueue(label: "work-queue", qos: .userInitiated)
    queue.async {
        var dataArray: [UInt32] = [0]
        let rcvData = sendAndRecvData(sndData: &dataArray,sndOnly: false)
        DispatchQueue.main.async {
            caption3 = "\(rcvData.count) Integers"
        }
    }
}
 */
