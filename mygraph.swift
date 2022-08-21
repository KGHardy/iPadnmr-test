//
//  mygraph.swift
//  CutDown
//
//  Created by Ken Hardy on 20/08/2022.
//

import Foundation
import SwiftUI

struct MyGraphView: View {
    var body: some View {
        Path() {path in
            path.move(to: CGPoint(x:5, y:0))
            path.addLine(to: CGPoint(x:365, y:0))
            path.addLine(to: CGPoint(x:365, y:600))
            path.addLine(to: CGPoint(x:5, y:600))
            path.closeSubpath()
        }
        .stroke(Color.blue, lineWidth:2)
    }
}

struct MyGraphView_Previews: PreviewProvider {
    static var previews: some View {
        MyGraphView()
    }
}
