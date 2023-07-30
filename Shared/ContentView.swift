import SwiftUI
import MessageUI

struct ContentView: View {
  @State var message : String = ""
  @State var hasReceievedMetadata = false;
  
  var body: some View {
    VStack {
      Text("iOS Camera Blocker").font(.title).alignmentGuide(HorizontalAlignment.center, computeValue: {dimensions in
        dimensions.width / 2
      })
      HStack {
        Button(
          action: { Task { await capturePhoto(printMessage, block: true) }},
          label: {Label("Block Camera system", systemImage: "camera").padding()}
        ).cornerRadius(10)
        Button(
          action: { Task { await capturePhoto(printMessage, block: false) }},
          label: {Label("Un-block Camera system", systemImage: "camera.fill").padding()}
        ).cornerRadius(10)
      }.padding()
      HStack {
        Text("\(message)").multilineTextAlignment(.center)
      }.padding()
    }
  }
  
  func printMessage(_ message: String) -> Void {
    self.message = message
  }
  
  struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
      ContentView()
        .previewInterfaceOrientation(.portrait)
    }
  }
}
